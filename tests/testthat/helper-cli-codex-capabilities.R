# Real owned filesystem controls for Codex marker tests; no provider or runtime mocks here.

codex_capability_fail = function(stage) {
  stop(structure(list(message = paste("Owned Codex capability fixture failed:", stage),
    call = NULL), class = c("gptr_fixture_capability_error", "error", "condition")))
}

codex_capability_require = function(value, stage) {
  if (!isTRUE(value)) codex_capability_fail(stage)
  invisible(NULL)
}

codex_capability_local = function(.env = parent.frame()) {
  # Initialize the framework's failure-formatting options before the caller-state snapshot.
  testthat::expect_failure(testthat::expect_identical(1L, 2L))
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  before = list(options = options(), env = Sys.getenv(), cwd = getwd(), seed = seed(),
    names = sort(ls(envir = globalenv(), all.names = TRUE)))
  withr::defer({
    testthat::expect_true(identical(options(), before$options), info = "options restored")
    testthat::expect_true(identical(Sys.getenv(), before$env), info = "environment restored")
    testthat::expect_true(identical(getwd(), before$cwd), info = "working directory restored")
    testthat::expect_true(identical(seed(), before$seed), info = "RNG restored")
    testthat::expect_true(identical(sort(ls(envir = globalenv(), all.names = TRUE)),
      before$names), info = "global names restored")
  }, envir = .env)
  invisible(NULL)
}

codex_capability_bytes = function(path) {
  con = file(path, "rb")
  on.exit(close(con), add = TRUE)
  bytes = readBin(con, "raw", n = 1024L^2)
  codex_capability_require(!length(readBin(con, "raw", n = 1L)), "byte-oracle-bound")
  bytes
}

codex_capability_preserve = function(path, .env = parent.frame()) {
  before = codex_capability_bytes(path)
  withr::defer({
    testthat::expect_true(file.exists(path), info = "unrelated sentinel survives cleanup")
    testthat::expect_identical(codex_capability_bytes(path), before)
  }, envir = .env)
  invisible(before)
}

# Resolve the parent independently; permissions may change only a direct owned regular file.
codex_capability_owned = function(path, root, existing = TRUE) {
  key = function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  parent = normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
  base = normalizePath(root, winslash = "/", mustWork = TRUE)
  inside = identical(key(parent), key(base)) || startsWith(key(parent), paste0(key(base), "/"))
  codex_capability_require(inside, "owned-parent")
  if (existing) {
    codex_capability_require(file.exists(path) && !dir.exists(path), "owned-regular-file")
    actual = normalizePath(path, winslash = "/", mustWork = TRUE)
    requested = file.path(parent, basename(path))
    codex_capability_require(identical(key(actual), key(requested)), "owned-direct-file")
    codex_capability_require(!isTRUE(nzchar(Sys.readlink(path))), "owned-no-link")
  } else {
    entries = list.files(parent, all.files = TRUE, no.. = TRUE)
    codex_capability_require(!(key(basename(path)) %in% key(entries)), "owned-fresh-name")
  }
  invisible(NULL)
}

codex_capability_process = function(command, args, stage) {
  codex_capability_require(nzchar(command), paste0(stage, "-executable"))
  tryCatch(processx::run(command, args, timeout = 5, error_on_status = TRUE,
    windows_hide_window = TRUE, cleanup_tree = TRUE, env = character()),
    error = function(error) codex_capability_fail(stage))
}

# Capture only the expected base file-open warning; any unrelated warning remains visible.
codex_capability_denied = function(path) {
  seen = new.env(parent = emptyenv())
  seen$warnings = 0L
  result = withCallingHandlers(tryCatch(codex_capability_bytes(path), error = identity),
    warning = function(w) {
      call = conditionCall(w)
      head = if (is.call(call)) call[[1L]] else NULL
      if (!identical(class(w), c("simpleWarning", "warning", "condition")) ||
          !identical(head, as.name("file"))) return(invisible(NULL))
      seen$warnings = seen$warnings + 1L
      invokeRestart("muffleWarning")
    })
  testthat::expect_true(inherits(result, "error"), info = "actual binary read is denied")
  codex_capability_require(inherits(result, "error"), "effective-read-denial")
  testthat::expect_identical(seen$warnings, 1L)
  codex_capability_require(identical(seen$warnings, 1L), "expected-file-open-warning")
  result = tryCatch(hash_file(path), error = identity)
  testthat::expect_true(inherits(result, "error"), info = "production content hash is denied")
  codex_capability_require(inherits(result, "error"), "effective-hash-denial")
  invisible(NULL)
}

codex_capability_link = function(link, root, .env = parent.frame()) {
  codex_capability_owned(link, root, existing = FALSE)
  windows = .Platform$OS.type == "windows"
  script = withr::local_tempfile(pattern = "codex-owned-unlink-", fileext = ".ps1",
    .local_envir = .env)
  writeLines(c("param([string]$Link)", "$ErrorActionPreference = 'Stop'",
    "[System.IO.File]::Delete($Link)"), script)
  state = new.env(parent = emptyenv())
  state$missing = character()
  present = function() {
    basename(link) %in% list.files(dirname(link), all.files = TRUE, no.. = TRUE)
  }
  detach = function() {
    if (present()) {
      if (windows) {
        codex_capability_process(Sys.which("powershell.exe"),
          c("-NoProfile", "-NonInteractive", "-File", script, "-Link", link), "link-detach")
      } else {
        codex_capability_require(identical(unlink(link, recursive = FALSE), 0L), "link-detach")
      }
    }
    testthat::expect_false(present(), info = "exact link entry is detached")
    codex_capability_require(!present(), "link-detach-membership")
    invisible(NULL)
  }
  # This is registered before creation, and still checks absence after a manual detach.
  withr::defer({
    detach()
    testthat::expect_false(any(file.exists(state$missing)), info = "owned targets stay absent")
  }, envir = .env)
  make = function(target) {
    codex_capability_require(!present(), "link-name-absent")
    codex_capability_owned(target, root, existing = FALSE)
    writeBin(charToRaw("owned target\n"), target)
    codex_capability_owned(target, root)
    made = file.symlink(target, link)
    testthat::expect_true(isTRUE(made), info = "real file-link creation succeeds")
    codex_capability_require(made, "file-link-create")
    testthat::expect_identical(codex_capability_bytes(link), codex_capability_bytes(target))
    native = if (windows) {
      out = codex_capability_process(Sys.which("fsutil.exe"),
        c("reparsepoint", "query", link), "link-tag-query")$stdout
      codex_capability_require(nchar(out, type = "bytes") <= 65536L, "link-query-bound")
      tag = regmatches(out, regexpr("0x[[:xdigit:]]{8}\\b", out))
      testthat::expect_identical(tolower(tag), "0xa000000c")
      codex_capability_require(identical(tolower(tag), "0xa000000c"), "true-file-link-tag")
      out
    } else {
      actual = Sys.readlink(link)
      testthat::expect_identical(actual, target)
      codex_capability_require(identical(actual, target), "posix-file-link-target")
      actual
    }
    codex_capability_require(file.remove(target), "owned-target-remove")
    state$missing = c(state$missing, target)
    testthat::expect_true(present(), info = "dangling entry is present independently of stat")
    testthat::expect_false(file.exists(target))
    codex_capability_denied(link)
    invisible(native)
  }
  list(make = make, detach = detach)
}

codex_capability_deny_read = function(path, root, .env = parent.frame()) {
  codex_capability_owned(path, root)
  windows = .Platform$OS.type == "windows"
  original = codex_capability_bytes(path)
  original_hash = hash_file(path)
  original_mode = file.mode(path)
  # A failed restoration must not lose its backup to local_project()'s recursive teardown.
  control = tempfile("codex-owned-access-", tmpdir = tempdir())
  codex_capability_require(dir.create(control, mode = "0700"), "private-control-create")
  control = normalizePath(control, winslash = "/", mustWork = TRUE)
  project = normalizePath(root, winslash = "/", mustWork = TRUE)
  codex_capability_require(!startsWith(tolower(control), paste0(tolower(project), "/")),
    "private-control-outside-project")
  script = file.path(control, "access.ps1")
  backup = file.path(control, "access.txt")
  reference = file.path(control, "expected.bin")
  stage = file.path(control, "stage.txt")
  diagnostic = file.path(control, "access-diagnostic.txt")
  state = new.env(parent = emptyenv())
  state$restored = FALSE
  state$verified = FALSE
  state$expected = original
  withr::defer({
    if (state$verified) {
      codex_capability_require(identical(unlink(control, recursive = TRUE), 0L),
        "private-control-remove")
      testthat::expect_false(dir.exists(control))
    }
  }, envir = .env)
  writeBin(original, reference)
  invoke = NULL
  if (windows) {
    writeLines(c(
      "param([string]$Path, [string]$Control, [string]$Backup,",
      "  [string]$Stage, [string]$Action)",
      "$ErrorActionPreference = 'Stop'",
      "[System.IO.File]::WriteAllText($Stage, 'script-entered')",
      "$section = [System.Security.AccessControl.AccessControlSections]::Access",
      "if ($Action -eq 'deny') {",
      "  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User",
      "  $attributes = [System.IO.File]::GetAttributes($Control)",
      "  if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {",
      "    throw 'Private control must not be a reparse point'",
      "  }",
      "  $private = [System.Security.AccessControl.DirectorySecurity]::new()",
      "  $private.SetOwner($sid)",
      "  $private.SetAccessRuleProtection($true, $false)",
      "  $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit",
      "  $inherit = $inherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit",
      "  $allow = [System.Security.AccessControl.FileSystemAccessRule]::new(",
      "    $sid, 'FullControl', $inherit, 'None', 'Allow')",
      "  $private.AddAccessRule($allow)",
      "  [System.IO.Directory]::SetAccessControl($Control, $private)",
      "  $sections = $section -bor [System.Security.AccessControl.AccessControlSections]::Owner",
      "  $current = [System.IO.Directory]::GetAccessControl($Control, $sections)",
      "  $owner = $current.GetOwner([System.Security.Principal.SecurityIdentifier])",
      "  $rules = $current.GetAccessRules($true, $true,",
      "    [System.Security.Principal.SecurityIdentifier])",
      "  if (-not $owner.Equals($sid) -or -not $current.AreAccessRulesProtected -or",
      "      $rules.Count -ne 1) { throw 'Private control owner or DACL differs' }",
      "  $rule = $rules[0]",
      "  if (-not $rule.IdentityReference.Equals($sid) -or $rule.IsInherited -or",
      "      $rule.FileSystemRights -ne",
      "        [System.Security.AccessControl.FileSystemRights]::FullControl -or",
      "      $rule.InheritanceFlags -ne $inherit -or",
      "      $rule.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None -or",
      "      $rule.AccessControlType -ne",
      "        [System.Security.AccessControl.AccessControlType]::Allow) {",
      "    throw 'Private control rule differs'",
      "  }",
      "  [System.IO.File]::WriteAllText($Stage, 'private-control-verified')",
      "  $acl = [System.IO.File]::GetAccessControl($Path, $section)",
      "  $original = $acl.GetSecurityDescriptorSddlForm($section)",
      "  $stream = [System.IO.File]::Open($Backup, 'CreateNew', 'Write', 'None')",
      "  try {",
      "    $bytes = [System.Text.Encoding]::UTF8.GetBytes($original)",
      "    $stream.Write($bytes, 0, $bytes.Length)",
      "    $stream.Flush()",
      "  } finally { $stream.Dispose() }",
      "  [System.IO.File]::WriteAllText($Stage, 'backup-saved')",
      "  $deny = [System.Security.AccessControl.FileSystemAccessRule]::new(",
      "    $sid, 'ReadData', 'Deny')",
      "  $acl.AddAccessRule($deny)",
      "  [System.IO.File]::SetAccessControl($Path, $acl)",
      "  [System.IO.File]::WriteAllText($Stage, 'deny-applied')",
      "} elseif ($Action -eq 'restore' -or $Action -eq 'verify') {",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-backup-read')",
      "  $original = [System.IO.File]::ReadAllText($Backup, [System.Text.Encoding]::UTF8)",
      "  if ($Action -eq 'restore') {",
      "    [System.IO.File]::WriteAllText($Stage, 'restore-sddl-set')",
      "    $acl = [System.Security.AccessControl.FileSecurity]::new()",
      "    $acl.SetSecurityDescriptorSddlForm($original, $section)",
      "    [System.IO.File]::WriteAllText($Stage, 'restore-apply')",
      "    [System.IO.File]::SetAccessControl($Path, $acl)",
      "  }",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-acl-read')",
      "  $current = [System.IO.File]::GetAccessControl($Path, $section)",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-sddl-read')",
      "  $restored = $current.GetSecurityDescriptorSddlForm($section)",
      "  if ($restored -cne $original) {",
      "    $diag = [System.IO.Path]::Combine($Control, 'access-diagnostic.txt')",
      "    try {",
      "      if ($original.Length -gt 262144 -or $restored.Length -gt 262144) {",
      "        throw 'Owned ACL diagnostic input bound'",
      "      }",
      "      $before = [System.Security.AccessControl.RawSecurityDescriptor]::new($original)",
      "      $after = [System.Security.AccessControl.RawSecurityDescriptor]::new($restored)",
      "      $af = [int]$before.ControlFlags",
      "      $bf = [int]$after.ControlFlags",
      "      $a = $before.DiscretionaryAcl",
      "      $b = $after.DiscretionaryAcl",
      "      $nullEqual = (($null -eq $a) -eq ($null -eq $b))",
      "      $countEqual = $false",
      "      $lengthEqual = $false",
      "      $bytesEqual = $false",
      "      if ($null -eq $a -and $null -eq $b) {",
      "        $countEqual = $true",
      "        $lengthEqual = $true",
      "        $bytesEqual = $true",
      "      } elseif ($null -ne $a -and $null -ne $b) {",
      "        if ($a.Count -gt 128 -or $b.Count -gt 128 -or",
      "            $a.BinaryLength -gt 65536 -or $b.BinaryLength -gt 65536) {",
      "          throw 'Owned ACL diagnostic binary bound'",
      "        }",
      "        $countEqual = ($a.Count -eq $b.Count)",
      "        $lengthEqual = ($a.BinaryLength -eq $b.BinaryLength)",
      "        $ab = [byte[]]::new($a.BinaryLength)",
      "        $bb = [byte[]]::new($b.BinaryLength)",
      "        $a.GetBinaryForm($ab, 0)",
      "        $b.GetBinaryForm($bb, 0)",
      "        $bytesEqual = ([Convert]::ToBase64String($ab) -ceq",
      "          [Convert]::ToBase64String($bb))",
      "      }",
      "      $bits = [int[]]@(($af -eq $bf), (($af -band 4) -eq ($bf -band 4)),",
      "        (($af -band 4096) -eq ($bf -band 4096)),",
      "        (($af -band 256) -eq ($bf -band 256)),",
      "        (($af -band 1024) -eq ($bf -band 1024)),",
      "        $nullEqual, $countEqual, $lengthEqual, $bytesEqual,",
      "        (($af -band 1024) -ne 0), (($bf -band 1024) -ne 0))",
      "      [System.IO.File]::WriteAllText($diag, [string]::Join(',', [string[]]$bits))",
      "    } catch {",
      "      try { [System.IO.File]::WriteAllText($diag, 'unavailable') } catch {}",
      "    }",
      "    [System.IO.File]::WriteAllText($Stage, 'restore-sddl-mismatch')",
      "    throw 'Owned file Access descriptor restoration did not match'",
      "  }",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-verified')",
      "} else { throw 'Unknown owned file Access action' }"), script)
    invoke = function(action) {
      writeBin(charToRaw("launch"), stage)
      writeBin(charToRaw("pending"), diagnostic)
      tryCatch({
        codex_capability_process(Sys.which("powershell.exe"),
          c("-NoProfile", "-NonInteractive", "-File", script, "-Path", path,
            "-Control", control, "-Backup", backup, "-Stage", stage, "-Action", action),
          paste0("file-access-", action))
      }, error = function(error) {
        phase = tryCatch(rawToChar(readBin(stage, "raw", 128L)), error = function(error) "unknown")
        if (!(phase %in% c("launch", "script-entered", "private-control-verified", "backup-saved",
            "deny-applied", "restore-backup-read", "restore-sddl-set", "restore-apply",
            "restore-acl-read", "restore-sddl-read", "restore-sddl-mismatch", "restore-verified")))
          phase = "unknown"
        if (phase == "restore-sddl-mismatch") {
          bits = tryCatch(rawToChar(readBin(diagnostic, "raw", 64L)),
                          error = function(error) "unavailable")
          fields = c("flags_equal", "present_equal", "protected_equal",
            "auto_required_equal", "auto_inherited_equal", "null_equal",
            "ace_count_equal", "binary_length_equal", "binary_equal",
            "auto_inherited_before", "auto_inherited_after")
          if (grepl("^[01](,[01]){10}$", bits)) {
            bits = strsplit(bits, ",", fixed = TRUE)[[1L]]
            text = paste(paste0(fields, "=", bits), collapse = " ")
          } else {
            text = "unavailable"
          }
          tryCatch(cat("Owned Codex file ACL diagnostic ", text, "\n",
                       sep = "", file = stdout()), error = function(error) NULL)
        }
        codex_capability_fail(paste0("file-access-", action, "/", phase))
      })
      invisible(NULL)
    }
  }
  restore = function() {
    state$verified = FALSE
    if (windows) {
      codex_capability_require(file.exists(backup), "access-backup-present")
      invoke(if (state$restored) "verify" else "restore")
    } else {
      if (!state$restored) {
        codex_capability_require(Sys.chmod(path, original_mode, use_umask = FALSE),
          "mode-restore")
      }
      testthat::expect_identical(file.mode(path), original_mode)
      codex_capability_require(identical(file.mode(path), original_mode), "exact-mode-restore")
    }
    # Do not early-return after a manual restore: deferred cleanup independently verifies again.
    testthat::expect_identical(codex_capability_bytes(path), state$expected)
    testthat::expect_identical(hash_file(path), hash_file(reference))
    codex_capability_require(identical(codex_capability_bytes(path), state$expected),
      "restored-exact-bytes")
    codex_capability_require(identical(hash_file(path), hash_file(reference)),
      "restored-exact-hash")
    state$restored = TRUE
    state$verified = TRUE
    invisible(NULL)
  }
  # Registered before native denial; runs before the private descriptor/control directory cleanup.
  withr::defer(restore(), envir = .env)
  testthat::expect_identical(hash_file(reference), original_hash)
  if (windows) {
    invoke("deny")
  } else {
    codex_capability_require(Sys.chmod(path, "0200", use_umask = FALSE), "mode-deny")
  }
  codex_capability_denied(path)
  info = file.info(path, extra_cols = FALSE)
  testthat::expect_true(is.finite(info$size) && is.finite(as.numeric(info$mtime)))
  codex_capability_require(is.finite(info$size) && is.finite(as.numeric(info$mtime)),
    "read-denial-metadata-readable")
  set_expected = function(bytes) {
    codex_capability_require(is.raw(bytes) && length(bytes) <= 1024L^2, "expected-byte-bound")
    state$expected = bytes
    state$verified = FALSE
    writeBin(bytes, reference)
    invisible(NULL)
  }
  list(bytes = original, restore = restore, set_expected = set_expected)
}
