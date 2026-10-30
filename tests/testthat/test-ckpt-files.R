# tests/testthat/test-ckpt-files.R -- the blob store, garbage collection, the tracker and the
# guarded 3-way restores (P16).

blob_count = function() {
  length(list.files(file.path(workspace_root(create = FALSE), "checkpoints", "blobs"),
                    recursive = TRUE))
}

# Deny file creation only in the freshly owned bucket. The saved Windows Access descriptor
# stays in an owner-only control directory; no SID or descriptor is returned or printed.
ckpt_test_deny_create = function(path, root, .env = parent.frame()) {
  inside = isTRUE(path_inside(path, root))
  lex = path_lexical(path)
  if (is_windows() || is_macos()) lex = tolower(lex)
  direct = !isTRUE(path_is_link(path)) && identical(path_key(path), lex)
  expect_true(inside)
  expect_true(direct)
  if (!inside || !direct) stop("Refusing permission changes outside an owned direct bucket")
  probe = tempfile("create-probe-", tmpdir = path)
  expect_true(file.create(probe))
  expect_true(file.remove(probe))
  state = new.env(parent = emptyenv())
  state$restored = FALSE
  windows = .Platform$OS.type == "windows"
  old_mode = file.mode(path)
  invoke = NULL
  backup = NULL
  stage = NULL
  diagnostic = NULL
  roundtrip = NULL
  if (windows) {
    control = tempfile("gptr-owned-acl-", tmpdir = root)
    created = dir.create(control, mode = "0700")
    expect_true(created)
    if (!isTRUE(created)) stop("Refusing an existing ACL control directory")
    script = file.path(control, "acl.ps1")
    backup = file.path(control, "access.txt")
    stage = file.path(control, "stage.txt")
    diagnostic = file.path(control, "access-diagnostic.txt")
    roundtrip = file.path(control, "original-roundtrip.txt")
    writeLines(c(
      "param([string]$Path, [string]$Control, [string]$Backup,",
      "  [string]$Stage, [string]$Action)",
      "$ErrorActionPreference = 'Stop'",
      "[System.IO.File]::WriteAllText($Stage, 'script-entered')",
      "$section = [System.Security.AccessControl.AccessControlSections]::Access",
      "if ($Action -eq 'deny') {",
      "  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User",
      "  [System.IO.File]::WriteAllText($Stage, 'token-read')",
      "  $attributes = [System.IO.File]::GetAttributes($Control)",
      "  if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {",
      "    throw 'Private control must not be a reparse point' }",
      "  $private = [System.Security.AccessControl.DirectorySecurity]::new()",
      "  $private.SetOwner($sid)",
      "  $private.SetAccessRuleProtection($true, $false)",
      "  $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit",
      "  $inherit = $inherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit",
      "  $allow = [System.Security.AccessControl.FileSystemAccessRule]::new(",
      "    $sid, 'FullControl', $inherit, 'None', 'Allow')",
      "  $private.AddAccessRule($allow)",
      "  [System.IO.File]::WriteAllText($Stage, 'private-acl-built')",
      "  [System.IO.Directory]::SetAccessControl($Control, $private)",
      "  [System.IO.File]::WriteAllText($Stage, 'private-acl-applied')",
      "  $sections = $section -bor [System.Security.AccessControl.AccessControlSections]::Owner",
      "  $current = [System.IO.Directory]::GetAccessControl($Control, $sections)",
      "  $owner = $current.GetOwner([System.Security.Principal.SecurityIdentifier])",
      "  $rules = @($current.GetAccessRules($true, $true,",
      "    [System.Security.Principal.SecurityIdentifier]))",
      "  if ($null -eq $owner -or -not $owner.Equals($sid) -or",
      "      -not $current.AreAccessRulesProtected -or $rules.Count -ne 1) {",
      "    throw 'Private control owner or DACL differs' }",
      "  $rule = $rules[0]",
      "  if (-not $rule.IdentityReference.Equals($sid) -or $rule.IsInherited -or",
      "      $rule.FileSystemRights -ne",
      "        [System.Security.AccessControl.FileSystemRights]::FullControl -or",
      "      $rule.InheritanceFlags -ne $inherit -or",
      "      $rule.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None -or",
      "      $rule.AccessControlType -ne",
      "        [System.Security.AccessControl.AccessControlType]::Allow) {",
      "    throw 'Private control rule differs' }",
      "  if ([System.IO.Directory]::GetFileSystemEntries($Path).Length -ne 0) {",
      "    throw 'Owned bucket must be empty before Access setup' }",
      "  [System.IO.File]::WriteAllText($Stage, 'private-control-verified')",
      "  $acl = [System.IO.Directory]::GetAccessControl($Path, $section)",
      "  [System.IO.File]::WriteAllText($Stage, 'bucket-acl-read')",
      "  # Only a fresh owned target is converted before its denial baseline is saved.",
      "  $sections = $section -bor [System.Security.AccessControl.AccessControlSections]::Owner",
      "  $initial = $acl.GetSecurityDescriptorSddlForm($section)",
      "  if ($initial.Length -gt 262144) { throw 'Initial Access input bound' }",
      "  $initialRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($initial)",
      "  $a = $initialRaw.DiscretionaryAcl",
      "  if ($null -eq $a -or $a.Count -lt 1 -or $a.Count -gt 128 -or",
      "      $a.BinaryLength -gt 65536) { throw 'Initial Access DACL bound' }",
      "  $initialFlags = [int]$initialRaw.ControlFlags",
      "  if (($initialFlags -band 4) -eq 0) { throw 'Initial Access DACL missing' }",
      "  $initialOwner = [System.IO.Directory]::GetAccessControl($Path, $sections).GetOwner(",
      "    [System.Security.Principal.SecurityIdentifier])",
      "  if ($null -eq $initialOwner -or $initialOwner.Value.Length -gt 512) {",
      "    throw 'Initial Access owner bound' }",
      "  foreach ($name in @('initial-access.txt', 'initial-owner.txt')) {",
      "    $value = if ($name -eq 'initial-access.txt') { $initial } else { $initialOwner.Value }",
      "    $saved = [System.IO.Path]::Combine($Control, $name)",
      "    $stream = [System.IO.File]::Open($saved, 'CreateNew', 'Write', 'None')",
      "    try {",
      "      $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)",
      "      $stream.Write($bytes, 0, $bytes.Length)",
      "      $stream.Flush()",
      "    } finally { $stream.Dispose() }",
      "  }",
      "  [System.IO.File]::WriteAllText($Stage, 'initial-access-saved')",
      "  $fresh = [System.Security.AccessControl.DirectorySecurity]::new()",
      "  $fresh.SetSecurityDescriptorSddlForm($initial, $section)",
      "  [System.IO.Directory]::SetAccessControl($Path, $fresh)",
      "  [System.IO.File]::WriteAllText($Stage, 'initial-access-persisted')",
      "  $actual = [System.IO.Directory]::GetAccessControl($Path, $sections)",
      "  $actualAccess = $actual.GetSecurityDescriptorSddlForm($section)",
      "  if ($actualAccess.Length -gt 262144) { throw 'Stable Access input bound' }",
      "  $actualRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($actualAccess)",
      "  $b = $actualRaw.DiscretionaryAcl",
      "  if ([int]$actualRaw.ControlFlags -ne ($initialFlags -bor 1024) -or",
      "      $null -eq $b -or $b.Count -ne $a.Count -or",
      "      $b.BinaryLength -ne $a.BinaryLength -or",
      "      -not $actual.GetOwner([System.Security.Principal.SecurityIdentifier]).Equals(",
      "        $initialOwner)) { throw 'Stable Access structure differs' }",
      "  $ab = [byte[]]::new($a.BinaryLength)",
      "  $bb = [byte[]]::new($b.BinaryLength)",
      "  $a.GetBinaryForm($ab, 0)",
      "  $b.GetBinaryForm($bb, 0)",
      "  if ([Convert]::ToBase64String($ab) -cne [Convert]::ToBase64String($bb)) {",
      "    throw 'Stable Access ordered DACL differs' }",
      "  [System.IO.File]::WriteAllText($Stage, 'stable-access-structure-verified')",
      "  $fresh = [System.Security.AccessControl.DirectorySecurity]::new()",
      "  $fresh.SetSecurityDescriptorSddlForm($actualAccess, $section)",
      "  [System.IO.Directory]::SetAccessControl($Path, $fresh)",
      "  [System.IO.File]::WriteAllText($Stage, 'stable-access-persisted')",
      "  $acl = [System.IO.Directory]::GetAccessControl($Path, $sections)",
      "  if ($acl.GetSecurityDescriptorSddlForm($section) -cne $actualAccess -or",
      "      -not $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Equals(",
      "        $initialOwner)) { throw 'Stable Access exact roundtrip differs' }",
      "  [System.IO.File]::WriteAllText($Stage, 'stable-access-roundtrip-verified')",
      "  $original = $acl.GetSecurityDescriptorSddlForm($section)",
      "  [System.IO.File]::WriteAllText($Stage, 'original-roundtrip')",
      "  $roundtrip = [System.IO.Path]::Combine($Control, 'original-roundtrip.txt')",
      "  try {",
      "    if ($original.Length -gt 262144) { throw 'Owned ACL diagnostic input bound' }",
      "    $raw = [System.Security.AccessControl.RawSecurityDescriptor]::new($original)",
      "    $rawEqual = ($raw.GetSddlForm($section) -ceq $original)",
      "    $reconstructed = [System.Security.AccessControl.DirectorySecurity]::new()",
      "    $reconstructed.SetSecurityDescriptorSddlForm($original, $section)",
      "    $objectEqual = ($reconstructed.GetSecurityDescriptorSddlForm($section) -ceq $original)",
      "    $bits = [int[]]@($rawEqual, $objectEqual)",
      "    [System.IO.File]::WriteAllText($roundtrip, [string]::Join(',', [string[]]$bits))",
      "  } catch {",
      "    try { [System.IO.File]::WriteAllText($roundtrip, 'unavailable') } catch {}",
      "  }",
      "  $stream = [System.IO.File]::Open($Backup, 'CreateNew', 'Write', 'None')",
      "  try {",
      "    $bytes = [System.Text.Encoding]::UTF8.GetBytes($original)",
      "    $stream.Write($bytes, 0, $bytes.Length)",
      "    $stream.Flush()",
      "  } finally { $stream.Dispose() }",
      "  [System.IO.File]::WriteAllText($Stage, 'backup-saved')",
      "  $deny = [System.Security.AccessControl.FileSystemAccessRule]::new(",
      "    $sid, 'CreateFiles', 'Deny')",
      "  $acl.AddAccessRule($deny)",
      "  [System.IO.Directory]::SetAccessControl($Path, $acl)",
      "  [System.IO.File]::WriteAllText($Stage, 'deny-applied')",
      "} elseif ($Action -eq 'restore') {",
      "  $original = [System.IO.File]::ReadAllText($Backup, [System.Text.Encoding]::UTF8)",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-read')",
      "  $acl = [System.Security.AccessControl.DirectorySecurity]::new()",
      "  $acl.SetSecurityDescriptorSddlForm($original, $section)",
      "  [System.IO.Directory]::SetAccessControl($Path, $acl)",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-applied')",
      "  $current = [System.IO.Directory]::GetAccessControl($Path, $section)",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-acl-read')",
      "  $restored = $current.GetSecurityDescriptorSddlForm($section)",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-sddl-read')",
      "  if ($restored -cne $original) {",
      "    [System.IO.File]::WriteAllText($Stage, 'restore-diagnostic')",
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
      "    throw 'Owned bucket Access descriptor restoration did not match'",
      "  }",
      "  $ownerPath = [System.IO.Path]::Combine($Control, 'initial-owner.txt')",
      "  if ([System.IO.FileInfo]::new($ownerPath).Length -gt 512) {",
      "    throw 'Restored Access owner input bound' }",
      "  $originalOwner = [System.IO.File]::ReadAllText($ownerPath, [System.Text.Encoding]::UTF8)",
      "  $sections = $section -bor [System.Security.AccessControl.AccessControlSections]::Owner",
      "  $owner = [System.IO.Directory]::GetAccessControl($Path, $sections).GetOwner(",
      "    [System.Security.Principal.SecurityIdentifier])",
      "  if ($null -eq $owner -or $owner.Value -cne $originalOwner) {",
      "    throw 'Restored Access owner differs' }",
      "  [System.IO.File]::WriteAllText($Stage, 'restore-verified')",
      "} else { throw 'Unknown owned ACL action' }"), script)
    shell = Sys.which("powershell.exe")
    if (!nzchar(shell)) stop("Owned Windows permission test requires powershell.exe")
    invoke = function(action) {
      writeBin(charToRaw("launch"), stage)
      writeBin(charToRaw("pending"), diagnostic)
      # A hang guard only: a cold PowerShell start alone has exceeded 5 s on Windows R-devel.
      tryCatch(processx::run(shell, c("-NoProfile", "-NonInteractive", "-File", script,
        "-Path", path, "-Control", control, "-Backup", backup, "-Stage", stage,
        "-Action", action), timeout = 60, error_on_status = TRUE, windows_hide_window = TRUE,
        cleanup_tree = TRUE, env = character()), error = function(error) {
          phase = tryCatch(rawToChar(readBin(stage, "raw", 128L)),
                           error = function(error) "unreadable-marker")
          allowed = c("launch", "script-entered", "token-read", "private-acl-built",
            "private-acl-applied", "bucket-acl-read", "original-roundtrip",
            "private-control-verified", "initial-access-saved", "initial-access-persisted",
            "stable-access-structure-verified", "stable-access-persisted",
            "stable-access-roundtrip-verified", "backup-saved", "deny-applied",
            "restore-read", "restore-applied", "restore-acl-read", "restore-sddl-read",
            "restore-sddl-mismatch", "restore-diagnostic", "restore-verified")
          if (!(phase %in% allowed)) phase = "invalid-marker"
          # Emit only fixed stage labels, then rethrow the original condition unchanged.
          tryCatch(cat("Owned checkpoint ACL action=", action, " stage=", phase, "\n",
                       sep = "", file = stdout()), error = function(error) NULL)
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
            original_bits = tryCatch(rawToChar(readBin(roundtrip, "raw", 64L)),
                                     error = function(error) "unavailable")
            if (grepl("^[01],[01]$", original_bits)) {
              values = strsplit(original_bits, ",", fixed = TRUE)[[1L]]
              labels = c("original_raw_parse_equal", "original_object_roundtrip_equal")
              text = paste(text, paste(paste0(labels, "=", values), collapse = " "))
            } else {
              text = paste(text, "original_roundtrip=unavailable")
            }
            tryCatch(cat("Owned checkpoint ACL diagnostic ", text, "\n",
                         sep = "", file = stdout()), error = function(error) NULL)
          }
          stop(error)
        })
      invisible(NULL)
    }
  }
  restore = function() {
    if (state$restored) return(invisible(NULL))
    if (windows) {
      if (!file.exists(backup)) return(invisible(NULL))
      invoke("restore")
    } else {
      expect_true(Sys.chmod(path, old_mode, use_umask = FALSE))
      expect_identical(file.mode(path), old_mode)
    }
    restored_probe = tempfile("restored-probe-", tmpdir = path)
    expect_true(file.create(restored_probe))
    expect_true(file.remove(restored_probe))
    state$restored = TRUE
    invisible(NULL)
  }
  # Register before any denial attempt, so an error after changing permissions still restores.
  withr::defer(restore(), envir = .env)
  if (windows) {
    invoke("deny")
  } else {
    expect_true(Sys.chmod(path, "0555", use_umask = FALSE))
    expect_true(file.access(path, 2L) != 0L)
  }
  denied_probe = tempfile("denied-probe-", tmpdir = path)
  expect_false(suppressWarnings(file.create(denied_probe)))
  expect_false(file.exists(denied_probe))
  restore
}

test_that("the blob store deduplicates, compresses small text and restores atomically", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines(c("x = 1", "y = 2"), f)
  h = ckpt_store_put(f)
  expect_match(h, "^[0-9a-f]{32}$")
  blob = ckpt_blob_find(h)
  expect_true(endsWith(blob, ".gz"))
  expect_match(blob, "/.gptr/checkpoints/blobs/", fixed = TRUE)
  n0 = blob_count()
  f2 = file.path(proj, "copy.R")
  file.copy(f, f2)
  expect_identical(ckpt_store_put(f2), h)
  expect_identical(blob_count(), n0)
  writeLines("changed", f)
  expect_true(ckpt_store_get(h, f))
  expect_identical(readLines(f), c("x = 1", "y = 2"))
  expect_false(ckpt_store_get(strrep("0", 32L), f))
  expect_false(ckpt_store_get("../../copy.R", file.path(proj, "out.R")))
  expect_identical(ckpt_store_put(character()), character())
})

test_that("already-compressed files are stored raw and come back byte for byte", {
  proj = local_project()
  f = file.path(proj, "d.rds")
  saveRDS(1:10, f)
  h = ckpt_store_put(f)
  expect_false(endsWith(ckpt_blob_find(h), ".gz"))
  out = file.path(proj, "restored", "d.rds")
  expect_true(ckpt_store_get(h, out))
  expect_identical(readBin(out, "raw", 1e4), readBin(f, "raw", 1e4))
})

test_that("the blob store reports effective create denial and restores its owned bucket", {
  proj = local_project()
  g = file.path(proj, "e.rds")
  saveRDS(11:20, g)
  hash = hash_file(g)
  blobs = dirname(ckpt_blob_path(hash, ""))
  expected = file.path(proj, ".gptr", "checkpoints", "blobs", substr(hash, 1L, 2L))
  same = identical(path_norm(blobs), path_norm(expected))
  expect_true(same)
  if (!same) stop("Refusing an unexpected checkpoint bucket")
  created = dir.create(blobs, recursive = TRUE, showWarnings = FALSE)
  expect_true(created)
  if (!isTRUE(created)) stop("Refusing permission changes on a preexisting bucket")
  expect_identical(path_norm(blobs), path_norm(expected))
  restore = ckpt_test_deny_create(blobs, proj)
  expect_error(suppressWarnings(ckpt_store_put(g)), class = "gptr_error_workspace")
  expect_null(ckpt_blob_find(hash))
  restore()
  expect_identical(ckpt_store_put(g), hash)
  expect_false(is.null(ckpt_blob_find(hash)))
})

test_that("without a workspace the store lives under tempdir(), never in the project", {
  proj = local_project(gptr = FALSE)
  f = file.path(proj, "a.txt")
  writeLines("a", f)
  h = ckpt_store_put(f)
  expect_true(startsWith(path_norm(ckpt_blob_find(h)), path_norm(tempdir())))
  expect_false(dir.exists(file.path(proj, ".gptr")))
})

test_that("blob GC keeps referenced and young blobs and deletes old unreferenced ones", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  make = function(txt) {
    f = tempfile(fileext = ".txt", tmpdir = proj)
    writeLines(txt, f)
    ckpt_store_put(f)
  }
  h_ref = make("referenced")
  h_old = make("old and unreferenced")
  h_new = make("young and unreferenced")
  old = Sys.time() - 40 * 86400
  Sys.setFileTime(ckpt_blob_find(h_ref), old)
  Sys.setFileTime(ckpt_blob_find(h_old), old)
  Sys.setFileTime(ckpt_blob_find(h_new), old)
  expect_identical(make("young and unreferenced"), h_new)
  sdir = file.path(root, "sessions")
  writeLines(c('{"type":"session","version":3,"id":"s0000000001"}',
               paste0('{"type":"custom","id":"a1b2c3d4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"a.R","pre":"', h_ref, '"}]}}}}')),
             file.path(sdir, "20260930T000000_s0000000001.jsonl"))
  stale = file.path(root, "checkpoints", "blobs", "ab", paste0(strrep("ab", 16L), ".tmp-1"))
  dir.create(dirname(stale), showWarnings = FALSE)
  writeLines("interrupted", stale)
  Sys.setFileTime(stale, old)
  spills = file.path(root, "checkpoints", "objects", c("s0000000001", "s0000000099"))
  for (d in spills) dir.create(d, recursive = TRUE)
  Sys.setFileTime(spills, old)
  res = ckpt_gc(root, days = 30)
  expect_false(file.exists(stale))
  expect_false(res$skipped)
  expect_identical(res$deleted, 1L)
  expect_false(is.null(ckpt_blob_find(h_ref)))
  expect_null(ckpt_blob_find(h_old))
  expect_false(is.null(ckpt_blob_find(h_new)))
  expect_identical(dir.exists(spills), c(TRUE, FALSE))
  idx = jsonlite::fromJSON(file.path(root, "checkpoints", "index.json"), simplifyVector = FALSE)
  expect_setequal(names(idx$blobs), c(h_ref, h_new))
  local_gptr_options(quiet = FALSE, checkpoint_disk_bytes = 1)
  expect_message(ckpt_gc(root, days = 30), "above gptr.checkpoint_disk_bytes",
                 class = "gptr_message_notice")
})

test_that("blob GC skips while another live process holds a session lock (IC-71)", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("old and unreferenced", f)
  h_old = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h_old), Sys.time() - 40 * 86400)
  sf = file.path(root, "sessions", "20260930T000000_s0000000002.jsonl")
  writeLines('{"type":"session","version":3,"id":"s0000000002"}', sf)
  dir.create(paste0(sf, ".lock"))
  writeLines(c("999999", "1790000000.5"), file.path(paste0(sf, ".lock"), "pid"))
  local_mocked_bindings(proc_identity = function(pid, create_time = NULL) list(alive = TRUE))
  res = ckpt_gc(root, days = 30)
  expect_true(res$skipped)
  expect_false(is.null(ckpt_blob_find(h_old)))
  local_mocked_bindings(proc_identity = function(pid, create_time = NULL) list(alive = FALSE))
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_null(ckpt_blob_find(h_old))
})

test_that("pruning in one process keeps the blobs another live process's session references", {
  skip_on_cran()
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("held by the other session", f)
  h = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h), Sys.time() - 40 * 86400)
  other = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(other$kill())
  sf = file.path(root, "sessions", "20260930T000000_s0000000003.jsonl")
  writeLines(c('{"type":"session","version":3,"id":"s0000000003"}',
               paste0('{"type":"custom","id":"b1c2d3e4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"x.R","pre":"', h, '"}]}}}}')), sf)
  dir.create(paste0(sf, ".lock"))
  pid_file = file.path(paste0(sf, ".lock"), "pid")
  writeLines(c(as.character(other$get_pid()), ""), pid_file)
  expect_true(ckpt_gc(root, days = 30)$skipped)
  # a holder its pid and creation time prove alive holds past a 24 h heartbeat (D-298)
  created = as.numeric(ps::ps_create_time(ps::ps_handle(other$get_pid())))
  writeLines(c(as.character(other$get_pid()), format(created, digits = 17)), pid_file)
  Sys.setFileTime(pid_file, Sys.time() - 25 * 3600)
  expect_true(ckpt_gc(root, days = 30)$skipped)
  other$kill()
  other$wait(5000)
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_false(is.null(ckpt_blob_find(h)))
})

paths_status = function(frag) {
  stats::setNames(vapply(frag$files, function(r) r$status, ""),
                  vapply(frag$files, function(r) r$path, ""))
}

test_that("the walk prunes .git and .gptr and lists links unfollowed; restores avoid them", {
  skip_on_os("windows")
  proj = local_project(files = list("R/a.R" = "a = 1", ".git/config" = "[core]",
                                    ".hg/dirstate" = "v1", ".svn/wc.db" = "v1",
                                    "data/x.csv" = "id"))
  file.symlink(file.path(proj, "data"), file.path(proj, "data_link"))
  w = ckpt_walk(proj)
  expect_setequal(w$path, c("R/a.R", "data/x.csv", "data_link"))
  expect_true(w$link[w$path == "data_link"])
  tr = list(root = proj, prune = ckpt_prune(proj))
  expect_identical(is.na(ckpt_walked(tr, file.path(proj, "Node_Modules", "x.js"))),
                   fs_case_insensitive(proj))
  g = ckpt_restore_guard(file.path(proj, "data_link", "x.csv"))
  expect_false(g$ok)
  expect_match(g$reason, "symbolic link")
})

test_that("the checkpoint store is never walked, also where it lies inside the project", {
  proj = local_project(gptr = FALSE, files = list("a.R" = "a = 1"))
  store = file.path(proj, "tmp[1]", "gptr")
  local_mocked_bindings(workspace_root = function(create = TRUE) {
    if (create) dir.create(store, recursive = TRUE, showWarnings = FALSE)
    store
  })
  ck = ckpt_ck_new("s0000000033")
  call = list(id = "c1", name = "r", input = list(code = "x"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 2", file.path(proj, "a.R"))
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(paths_status(frag), c(a.R = "modified"))
  expect_true(ckpt_files_undo(ck, frag)$ok)
  expect_identical(readLines(file.path(proj, "a.R")), "a = 1")
})

test_that("a mutating step records created, modified and deleted files; undo and redo swap them", {
  proj = local_project(files = list("R/a.R" = "f = function(x) x + 1",
                                    "notes.md" = c("# Notes", "keep me")))
  ck = ckpt_ck_new("s0000000021")
  call = list(id = "c1", name = "r",
              input = list(code = "write.csv(data.frame(id = 1:3), 'out.csv')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  expect_true(all(c("R/a.R", "notes.md") %in% names(ck$files$hash)))
  writeLines("f = function(x) x + 10", file.path(proj, "R", "a.R"))
  utils::write.csv(data.frame(id = 1:3), file.path(proj, "out.csv"), row.names = FALSE)
  file.remove(file.path(proj, "notes.md"))
  frag = ckpt_files_after(ck, call, tok)
  st = paths_status(frag)
  expect_identical(st[["out.csv"]], "created")
  expect_identical(st[["R/a.R"]], "modified")
  expect_identical(st[["notes.md"]], "deleted")
  expect_silent(json_encode(frag))
  expect_identical(ckpt_files_describe(frag), c("file out.csv: created", "file R/a.R: modified",
                                                "file notes.md: deleted"))
  u = ckpt_files_undo(ck, frag)
  expect_true(all(u$ok))
  expect_false(file.exists(file.path(proj, "out.csv")))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "f = function(x) x + 1")
  expect_identical(readLines(file.path(proj, "notes.md")), c("# Notes", "keep me"))
  r = ckpt_files_undo(ck, frag, redo = TRUE)
  expect_true(all(r$ok))
  expect_true(file.exists(file.path(proj, "out.csv")))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "f = function(x) x + 10")
  expect_false(file.exists(file.path(proj, "notes.md")))
})

test_that("files changed by a child process are recorded too", {
  skip_on_cran()
  proj = local_project(files = list("R/b.R" = "h = function() 'b'"))
  ck = ckpt_ck_new("s0000000022")
  call = list(id = "c1", name = "r", input = list(code = "system2('Rscript', 'job.R')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  processx::run(rscript_path(), c("--vanilla", "-e", "writeLines('child', 'R/b.R')"),
                wd = proj)
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(paths_status(frag)[["R/b.R"]], "modified")
  u = ckpt_files_undo(ck, frag)
  expect_true(all(u$ok))
  expect_identical(readLines(file.path(proj, "R", "b.R")), "h = function() 'b'")
})

test_that("undo keeps a file edited after the turn (3-way) unless forced", {
  proj = local_project(files = list("b.R" = "h = function() 'b'"))
  ck = ckpt_ck_new("s0000000023")
  call = list(id = "c1", name = "write", input = list(path = "b.R", content = "child"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("h = function() 'agent'", file.path(proj, "b.R"))
  frag = ckpt_files_after(ck, call, tok)
  writeLines("h = function() 'user edit'", file.path(proj, "b.R"))
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "conflict")
  expect_identical(readLines(file.path(proj, "b.R")), "h = function() 'user edit'")
  expect_identical(ckpt_files_undo(ck, frag, dry = TRUE)$ok, FALSE)
  u = ckpt_files_undo(ck, frag, force = TRUE)
  expect_true(u$ok)
  expect_identical(readLines(file.path(proj, "b.R")), "h = function() 'b'")
})

test_that("files over the capture cap and symbolic links are not restorable", {
  skip_on_os("windows")
  local_gptr_options(checkpoint_track_file_max = 10, checkpoint_capture_max = 10)
  proj = local_project(files = list("big.txt" = "0123456789ABCDEF", "notes.md" = "small"))
  file.symlink(file.path(proj, "notes.md"), file.path(proj, "link.md"))
  ck = ckpt_ck_new("s0000000024")
  call = list(id = "c1", name = "r", input = list(code = "cat('x', file = 'big.txt')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("0123456789ABCDEFGH", file.path(proj, "big.txt"))
  writeLines("longer text", file.path(proj, "notes.md"))
  frag = ckpt_files_after(ck, call, tok)
  rows = stats::setNames(frag$files, vapply(frag$files, function(r) r$path, ""))
  expect_false(rows[["big.txt"]]$restorable)
  expect_match(rows[["big.txt"]]$reason, "no pre-image")
  expect_false(rows[["link.md"]]$restorable)
  expect_match(rows[["link.md"]]$reason, "symbolic link")
  expect_true("file link.md: modified (not restorable)" %in% ckpt_files_describe(frag))
  u = ckpt_files_undo(ck, frag)
  expect_identical(u$ok[u$item == "file link.md"], FALSE)
  expect_true(nzchar(Sys.readlink(file.path(proj, "link.md"))))
})

test_that("without a sync, an unhashed file changed since the last walk has no pre-image (#24)", {
  local_gptr_options(checkpoint_track_file_max = 10)
  proj = local_project(files = list("edited.csv" = strrep("o", 20), "kept.csv" = strrep("o", 20)))
  ck = ckpt_ck_new("s0000000034")
  ckpt_files_sync(ckpt_files_tr(ck))
  writeLines(strrep("c", 30), file.path(proj, "edited.csv"))
  code = "writeLines('served', 'edited.csv'); writeLines('served', 'kept.csv')"
  call = list(id = "c1", name = "r", input = list(code = code))
  tok = ckpt_files_before(ck, call, turn = 1L, sync = FALSE)
  for (f in c("edited.csv", "kept.csv")) writeLines("served", file.path(proj, f))
  frag = ckpt_files_after(ck, call, tok)
  rows = stats::setNames(frag$files, vapply(frag$files, function(r) r$path, ""))
  expect_false(rows[["edited.csv"]]$restorable)
  expect_match(rows[["edited.csv"]]$reason, "no pre-image")
  expect_true(rows[["kept.csv"]]$restorable)
  u = ckpt_files_undo(ck, frag)
  expect_identical(u$ok[u$item == "file edited.csv"], FALSE)
  expect_identical(readLines(file.path(proj, "edited.csv")), "served")
  expect_identical(readLines(file.path(proj, "kept.csv")), strrep("o", 20))
})

test_that("undo restores mode bits; old rows, later edits and missing copies are not written", {
  skip_on_os("windows")
  local_gptr_options(checkpoint_capture_max = 10)
  proj = local_project(files = list("a.R" = "a = 1", "run.sh" = "echo"))
  Sys.chmod(file.path(proj, "run.sh"), "0750", use_umask = FALSE)
  ck = ckpt_ck_new("s0000000029")
  ckpt_files_sync(ckpt_files_tr(ck))
  Sys.chmod(file.path(proj, "a.R"), "0700", use_umask = FALSE)
  call = list(id = "c1", name = "r", input = list(code = "file.remove('run.sh')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 22", file.path(proj, "a.R"))
  writeLines("a longer new file", file.path(proj, "new.txt"))
  file.remove(file.path(proj, "run.sh"))
  frag = ckpt_files_after(ck, call, tok)
  expect_match(ckpt_files_undo(ck, frag, turn_now = 101L)$action, "older than", all = TRUE)
  expect_true(all(ckpt_files_undo(ck, frag)$ok))
  expect_identical(format(file.mode(file.path(proj, c("run.sh", "a.R")))), c("750", "700"))
  writeLines("a = 3", file.path(proj, "a.R"))
  r = ckpt_files_undo(ck, frag, redo = TRUE)
  expect_identical(r$action[r$item == "file new.txt"], "not redone (no stored copy)")
  expect_match(r$action[r$item == "file a.R"], "conflict: changed after the undo")
  expect_identical(readLines(file.path(proj, "a.R")), "a = 3")
  expect_false(file.exists(file.path(proj, "new.txt")))
})

test_that("a file that cannot be written or read is an item and the undo goes on", {
  skip_on_os("windows")
  proj = local_project(files = list("ro/a.R" = "a = 1", "b.R" = "b = 1", "c.R" = "c = 1"))
  ck = ckpt_ck_new("s0000000031")
  call = list(id = "c1", name = "r", input = list(code = "x"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 2", file.path(proj, "ro", "a.R"))
  writeLines("b = 2", file.path(proj, "b.R"))
  writeLines("c = 2", file.path(proj, "c.R"))
  frag = ckpt_files_after(ck, call, tok)
  Sys.chmod(file.path(proj, "ro"), "0555", use_umask = FALSE)
  withr::defer(Sys.chmod(file.path(proj, "ro"), "0755", use_umask = FALSE))
  Sys.chmod(file.path(proj, "c.R"), "0000", use_umask = FALSE)
  skip_if(file.access(file.path(proj, "ro"), 2L) == 0L, "the directory stays writable")
  u = ckpt_files_undo(ck, frag)
  expect_identical(u$action[u$item == "file ro/a.R"],
                   "not restored (the file could not be changed)")
  expect_match(u$action[u$item == "file c.R"], "conflict")
  expect_identical(readLines(file.path(proj, "b.R")), "b = 1")
})

test_that("undo and redo of a case-only rename preserve bytes on the observed filesystem", {
  proj = local_project(files = list("readme.md" = "hello"))
  folded = fs_case_insensitive(proj)
  expect_identical(file.exists(file.path(proj, "README.md")), folded)
  ck = ckpt_ck_new("s0000000032")
  call = list(id = "c1", name = "r", input = list(code = "file.rename('readme.md', 'README.md')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  expect_true(file.rename(file.path(proj, "readme.md"), file.path(proj, "README.md")))
  expect_identical(file.exists(file.path(proj, "readme.md")), folded)
  frag = ckpt_files_after(ck, call, tok)
  expect_true(all(ckpt_files_undo(ck, frag)$ok))
  expect_identical(list.files(proj), "readme.md")
  expect_true(all(ckpt_files_undo(ck, frag, redo = TRUE)$ok))
  expect_identical(list.files(proj), "README.md")
  expect_identical(readLines(file.path(proj, "README.md")), "hello")
})

test_that("a path outside the project and tempdir() is restored only after a human confirms", {
  proj = local_project()
  outside = withr::local_tempdir()
  local_mocked_bindings(ckpt_temp_root = function() file.path(tempdir(), "not-this-one"))
  out = path_norm(file.path(outside, "result.csv"))
  writeLines("old", out)
  ck = ckpt_ck_new("s0000000025")
  call = list(id = "c9", name = "r",
              input = list(code = paste0("writeLines('new', '", out, "')")))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("new", out)
  frag = ckpt_files_after(ck, call, tok)
  row = frag$files[[1L]]
  expect_true(row$abs)
  expect_identical(row$status, "modified")
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "not confirmed")
  expect_identical(readLines(out), "new")
  expect_true(is.na(ckpt_files_undo(ck, frag, dry = TRUE)$ok))
  local_scripted_ui(answers = list(1L))
  u = ckpt_files_undo(ck, frag)
  expect_true(u$ok)
  expect_identical(readLines(out), "old")
})

test_that("a planted record pointing outside the project is not restored without a human", {
  proj = local_project()
  outside = withr::local_tempdir()
  local_mocked_bindings(ckpt_temp_root = function() file.path(tempdir(), "not-this-one"))
  target = path_norm(file.path(outside, "victim.txt"))
  writeLines("current", target)
  src = file.path(proj, "planted.txt")
  writeLines("planted", src)
  h = ckpt_store_put(src)
  ck = ckpt_ck_new("s0000000026")
  frag = list(id = "kplanted", turn = 1L, root = path_norm(outside),
              files = list(ckpt_file_row("victim.txt", FALSE, "modified", h,
                                         unname(hash_file(target)), 420, 8, 0, TRUE, "")))
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "not confirmed")
  expect_identical(readLines(target), "current")
})

test_that("restores never write into .git or gptr's user directories; control paths ask", {
  proj = local_project()
  g = ckpt_restore_guard(file.path(proj, ".git", "config"))
  expect_false(g$ok)
  expect_match(g$reason, ".git")
  u = ckpt_restore_guard(path_norm(file.path(gptr_user_dir("config"), "settings.json")))
  expect_false(u$ok)
  expect_match(u$reason, "user directory")
  ok = ckpt_restore_guard(file.path(proj, "R", "a.R"))
  expect_true(ok$ok)
  expect_false(ok$ask)
  ctl = ckpt_restore_guard(file.path(proj, ".gptr", "settings.json"))
  expect_true(ctl$ok)
  expect_true(ctl$ask)
})

test_that("slow walks switch the session to one scan per turn plus predicted paths", {
  local_gptr_options(checkpoint_scan_budget = -1, checkpoint_capture_max = 20)
  proj = local_project(files = list("R/a.R" = "a = 1"))
  ck = ckpt_ck_new("s0000000027")
  call = list(id = "c1", name = "r", input = list(code = "writeLines('a = 2', 'R/a.R')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 2", file.path(proj, "R", "a.R"))
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(names(paths_status(frag)), "R/a.R")
  expect_true(ck$files$per_turn)
  call2 = list(id = "c2", name = "write", input = list(path = "R/b.R", content = "b = 1"))
  tok2 = ckpt_files_before(ck, call2, turn = 1L)
  writeLines("b = 1", file.path(proj, "R", "b.R"))
  writeLines("unpredicted", file.path(proj, "other.txt"))
  frag2 = ckpt_files_after(ck, call2, tok2)
  expect_length(frag2$files, 1L)
  expect_false(frag2$files[[1L]]$abs)
  expect_identical(frag2$files[[1L]]$path, "R/b.R")
  turn_frag = ckpt_files_turn_scan(ck, 1L)
  expect_identical(names(paths_status(turn_frag)), "other.txt")
  call3 = list(id = "c3", name = "write", input = list(path = "R/a.R", content = "big"))
  tok3 = ckpt_files_before(ck, call3, turn = 2L)
  writeLines(strrep("y", 100), file.path(proj, "R", "a.R"))
  frag3 = ckpt_files_after(ck, call3, tok3)
  expect_identical(frag3$files[[1L]]$status, "modified")
  expect_null(ckpt_files_turn_scan(ck, 2L))
  expect_true(ckpt_files_undo(ck, frag3)$ok)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 2")
  # a predicted path that unpredicted code changed earlier in the turn is left to the turn scan
  call4 = list(id = "c4", name = "r", input = list(code = "source('job.R')"))
  tok4 = ckpt_files_before(ck, call4, turn = 3L)
  writeLines("job output", file.path(proj, "R", "a.R"))
  expect_null(ckpt_files_after(ck, call4, tok4))
  call5 = list(id = "c5", name = "write", input = list(path = "R/a.R", content = "c5"))
  tok5 = ckpt_files_before(ck, call5, turn = 3L)
  writeLines("c5", file.path(proj, "R", "a.R"))
  expect_null(ckpt_files_after(ck, call5, tok5))
  expect_true(ckpt_files_undo(ck, ckpt_files_turn_scan(ck, 3L))$ok)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 2")
})

# The notices of gptr.checkpoint_scan_budget that `expr` signals (shown nowhere)
scan_notices = function(expr) {
  seen = new.env(parent = emptyenv())
  seen$text = character()
  withCallingHandlers(expr, gptr_message_notice = function(m) {
    seen$text = c(seen$text, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  grep("gptr.checkpoint_scan_budget", seen$text, fixed = TRUE, value = TRUE)
}

test_that("only the walk counts against gptr.checkpoint_scan_budget, not root lookups", {
  skip_on_cran()
  local_project(gptr = FALSE)
  local_gptr_options(checkpoint_scan_budget = 0.25, quiet = FALSE)
  prune = ckpt_prune
  local_mocked_bindings(ckpt_prune = function(root) {
    Sys.sleep(0.3)
    prune(root)
  })
  local_fake_provider(list(fake_tool("r", code = "writeLines('a', 'out.txt')"), "done"))
  e = new.env()
  notices = scan_notices({
    e$s = peter("write out.txt", model = "fake/fake-1", mode = "auto", envir = e)
  })
  expect_identical(notices, character())
  expect_identical(readLines("out.txt"), "a")
  ck = ckpt_ck_of(ckpt_ext_state(e$s), e$s, create = FALSE)
  expect_false(isTRUE(ck$files$per_turn))
})

test_that("a walk slower than gptr.checkpoint_scan_budget switches to per-turn scans once", {
  local_gptr_options(checkpoint_scan_budget = 0.25, quiet = FALSE)
  proj = local_project(files = list("a.R" = "a = 1"))
  walk = ckpt_walk
  local_mocked_bindings(ckpt_walk = function(...) {
    Sys.sleep(0.3)
    walk(...)
  })
  ck = ckpt_ck_new("s0000000096")
  call = list(id = "c1", name = "r", input = list(code = "writeLines('a = 2', 'a.R')"))
  notices = scan_notices(for (i in 1:2) {
    tok = ckpt_files_before(ck, call, turn = 1L)
    writeLines(paste("a =", i + 1L), file.path(proj, "a.R"))
    ckpt_files_after(ck, call, tok)
  })
  expect_length(notices, 1L)
  expect_match(notices, paste0("Checkpoint scans of ", proj), fixed = TRUE)
  expect_true(ck$files$per_turn)
})

test_that("files that cannot be read are listed, never captured and stop nothing else", {
  skip_on_os("windows")
  proj = local_project(files = list("R/a.R" = "a = 1", "R/b.R" = "b = 1", "secret.txt" = "s"))
  Sys.chmod(file.path(proj, "secret.txt"), "0000", use_umask = FALSE)
  skip_if(file.access(file.path(proj, "secret.txt"), 4L) == 0L, "the file stays readable")
  ck = ckpt_ck_new("s0000000030")
  call = list(id = "c1", name = "write", input = list(path = "secret.txt", content = "t"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 2", file.path(proj, "R", "a.R"))
  Sys.chmod(file.path(proj, "R", "b.R"), "0000", use_umask = FALSE)
  Sys.chmod(file.path(proj, "secret.txt"), "0600", use_umask = FALSE)
  writeLines("k", file.path(proj, "key.pem"))
  Sys.chmod(file.path(proj, "key.pem"), "0000", use_umask = FALSE)
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(paths_status(frag), c(key.pem = "created", `R/a.R` = "modified"))
  expect_true(all(ckpt_files_undo(ck, frag)$ok))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
  expect_false(file.exists(file.path(proj, "key.pem")))
  expect_identical(readLines(file.path(proj, "secret.txt")), "s")
})

test_that("a forced turn scan records what a CLI child changed (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  ck = ckpt_ck_new("s0000000028")
  ckpt_files_sync(ckpt_files_tr(ck))
  expect_null(ckpt_files_turn_scan(ck, 1L, force = TRUE))
  writeLines("a = 2", file.path(proj, "R", "a.R"))
  frag = ckpt_files_turn_scan(ck, 1L, force = TRUE)
  expect_identical(paths_status(frag), c(`R/a.R` = "modified"))
  u = ckpt_files_undo(ck, frag)
  expect_true(u$ok)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
})

test_that("gptr's own writes are no turn's change; an edit the tracker has not seen still is", {
  proj = local_project(files = list("analysis.R" = "a = 1"))
  ck = ckpt_ck_new("s0000000035")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  doc = file.path(proj, "analysis.R")
  new = file.path(proj, "transcript.R")
  ckpt_files_own_write(list(tr), doc, function() writeLines("a = 2", doc))
  ckpt_files_own_write(list(tr), new, function() writeLines("t = 1", new))
  expect_null(ckpt_files_turn_scan(ck, 1L, force = TRUE))
  for (f in c(doc, new)) writeLines("edited", f)
  ckpt_files_own_write(list(tr), doc, function() writeLines("a = 3", doc))
  frag = ckpt_files_turn_scan(ck, 2L, force = TRUE)
  expect_identical(paths_status(frag), c(analysis.R = "modified", transcript.R = "modified"))
  expect_true(all(ckpt_files_undo(ck, frag)$ok))
  expect_identical(readLines(doc), "a = 2")
  expect_identical(readLines(new), "t = 1")
  local_mocked_bindings(ckpt_ext_state = function(s = NULL) stop("no registry"))
  ckpt_own_write(doc, function() writeLines("a = 4", doc))
  expect_identical(readLines(doc), "a = 4")
})


test_that("checkpoint payloads are private before gzip or raw-copy writes", {
  skip_on_os("windows")
  proj = local_project()
  files = file.path(proj, c("private.txt", "public.rds"))
  bytes = list(charToRaw("synthetic private text"), charToRaw("synthetic raw payload"))
  for (i in seq_along(files)) writeBin(bytes[[i]], files[i])
  Sys.chmod(files, c("0600", "0644"), use_umask = FALSE)
  umask = Sys.umask("0022")
  withr::defer(Sys.umask(umask))
  modes = character()
  original_gzip = base::gzfile
  original_copy = base::file.copy
  local_mocked_bindings(gzfile = function(description, ...) {
    if (grepl("[.]tmp-", basename(description))) {
      modes <<- c(modes, format(file.info(description)$mode))
    }
    original_gzip(description, ...)
  }, file.copy = function(from, to, ...) {
    if (identical(from, files[2])) modes <<- c(modes, format(file.info(to)$mode))
    original_copy(from, to, ...)
  }, .package = "base")
  hashes = ckpt_store_put(files)
  blobs = vapply(hashes, ckpt_blob_find, "")
  expect_identical(modes, c("600", "600"))
  expect_identical(format(file.info(blobs)$mode), c("600", "600"))
  expect_true(endsWith(blobs[1], ".gz"))
  expect_false(endsWith(blobs[2], ".gz"))
  for (i in seq_along(files)) {
    out = file.path(proj, paste0("restored-", i))
    expect_true(ckpt_store_get(hashes[i], out))
    expect_identical(readBin(out, "raw", file.size(out)), bytes[[i]])
  }
  expect_identical(ckpt_store_put(files), hashes)
  expect_length(list.files(ckpt_store_root(), recursive = TRUE, pattern = "[.]tmp-"), 0L)
})

test_that("a failed raw checkpoint copy cannot publish an empty precreated blob", {
  proj = local_project()
  f = file.path(proj, "payload.rds")
  writeBin(charToRaw("synthetic raw payload"), f)
  hash = hash_file(f)
  original = base::file.copy
  local_mocked_bindings(file.copy = function(from, to, ...) {
    if (identical(from, f)) return(FALSE)
    original(from, to, ...)
  }, .package = "base")
  expect_error(suppressWarnings(ckpt_store_put(f)), class = "gptr_error_workspace")
  expect_null(ckpt_blob_find(hash))
  expect_length(list.files(ckpt_store_root(), recursive = TRUE, pattern = "[.]tmp-"), 0L)
})

test_that("a checkpoint permission failure publishes no blob or private payload", {
  skip_on_os("windows")
  proj = local_project()
  f = file.path(proj, "private.txt")
  writeBin(charToRaw("synthetic private text"), f)
  hash = hash_file(f)
  original = base::Sys.chmod
  local_mocked_bindings(Sys.chmod = function(paths, mode = "0777", use_umask = TRUE) {
    if (any(startsWith(basename(paths), ".gptr-write-"))) return(rep(FALSE, length(paths)))
    original(paths, mode, use_umask)
  }, .package = "base")
  expect_error(ckpt_store_put(f), class = "gptr_error_workspace")
  expect_null(ckpt_blob_find(hash))
  expect_length(list.files(ckpt_store_root(), recursive = TRUE, pattern = "[.]tmp-"), 0L)
})


test_that("checkpoint baseline excludes owned FIFOs before hashing", {
  skip_on_os("windows")
  proj = local_project(files = list("source.R" = "answer = 42", "empty.txt" = character()))
  pipe = file.path(proj, "supervisor_stdin")
  fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
  original = hash_file
  hashed = character()
  local_mocked_bindings(hash_file = function(path) {
    if (any(path == pipe)) {
      stop(structure(list(message = "FIFO hash refused", call = NULL),
        class = c("ckpt_fifo_hash_refused", "error", "condition")))
    }
    hashed <<- c(hashed, path)
    original(path)
  })
  ck = ckpt_ck_new("s0000000090")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  expect_setequal(names(tr$hash), c("source.R", "empty.txt"))
  expect_setequal(basename(hashed), c("source.R", "empty.txt"))
  expect_true("supervisor_stdin" %in% tr$stat$path)
  expect_false(ckpt_capturable(pipe))
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
})

test_that("checkpoint changed FIFOs and links stay listed without capture or restore", {
  skip_on_os("windows")
  proj = local_project(files = list("source.R" = "answer = 42"))
  ck = ckpt_ck_new("s0000000091")
  call = list(id = "fifo", name = "r", input = list(code = "invisible(NULL)"))
  token = ckpt_files_before(ck, call, 1L)
  pipe = file.path(proj, "supervisor_stdout")
  fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  link = file.path(proj, "source-link")
  expect_true(file.symlink(file.path(proj, "source.R"), link))
  original = hash_file
  local_mocked_bindings(hash_file = function(path) {
    if (any(path %in% c(pipe, link))) {
      stop(structure(list(message = "FIFO hash refused", call = NULL),
        class = c("ckpt_fifo_hash_refused", "error", "condition")))
    }
    original(path)
  })
  fragment = ckpt_files_after(ck, call, token)
  rows = stats::setNames(fragment$files, vapply(fragment$files, function(row) row$path, ""))
  expect_setequal(names(rows), c("supervisor_stdout", "source-link"))
  expect_identical(rows$supervisor_stdout$post, "")
  expect_false(rows$supervisor_stdout$restorable)
  expect_identical(rows$supervisor_stdout$reason, "not a regular file")
  expect_false(rows[["source-link"]]$restorable)
  expect_identical(rows[["source-link"]]$reason, "symbolic link")
  ckpt_files_undo(ck, fragment)
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
  expect_true(ckpt_is_link(link))
  expect_identical(readLines(file.path(proj, "source.R")), "answer = 42")
})

test_that("checkpoint racy scans reject a tracked regular file replaced by a FIFO", {
  skip_on_os("windows")
  proj = local_project(files = list("empty.txt" = character()))
  ck = ckpt_ck_new("s0000000092")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  observed = tr$stat
  tr$walk_time = observed$mtime[1L]
  pipe = file.path(proj, "empty.txt")
  expect_true(file.remove(pipe))
  fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
  original = hash_file
  local_mocked_bindings(ckpt_walk = function(root, prune) observed, hash_file = function(path) {
    if (any(path == pipe)) {
      stop(structure(list(message = "FIFO hash refused", call = NULL),
        class = c("ckpt_fifo_hash_refused", "error", "condition")))
    }
    original(path)
  })
  scan = ckpt_files_scan(tr)
  expect_identical(scan$modified, "empty.txt")
  rows = ckpt_files_step(tr)
  expect_length(rows, 1L)
  expect_identical(rows[[1L]]$status, "modified")
  expect_identical(rows[[1L]]$post, "")
  expect_false(rows[[1L]]$restorable)
  expect_identical(rows[[1L]]$reason, "not a regular file")
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
})

test_that("checkpoint file-type uncertainty preserves original stat conditions", {
  skip_on_os("windows")
  proj = local_project(files = list("source.R" = "answer = 42"))
  path = file.path(proj, "source.R")
  regular = ckpt_regular
  for (kind in c("error", "interrupt")) {
    condition = structure(list(message = "fixed stat condition", call = NULL),
      class = c("ckpt_stat_condition", kind, "condition"))
    actual = testthat::with_mocked_bindings(
      tryCatch(regular(path), error = identity, interrupt = identity),
      ps_fs_stat = function(paths, follow) stop(condition), .package = "ps")
    expect_identical(actual, condition)
  }
  for (type in list(NA_character_, "unknown", character(), 1L)) {
    actual = testthat::with_mocked_bindings(regular(path),
      ps_fs_stat = function(paths, follow) list(type = type), .package = "ps")
    expect_identical(actual, FALSE)
  }
  expect_identical(regular(character()), logical())
  expect_error(regular(file.path(proj, "absent")), class = "ps_error")
  expect_identical(regular(c(path, proj)), c(TRUE, FALSE))
})

test_that("checkpoint Windows fallback keeps existing filesystem and link guards", {
  proj = local_project(files = list("source.R" = "answer = 42", "empty.txt" = character()))
  paths = file.path(proj, c("source.R", "empty.txt", "absent"))
  regular = ckpt_regular
  local_mocked_bindings(is_windows = function() TRUE)
  testthat::with_mocked_bindings({
    expect_identical(regular(c(paths, proj)), c(TRUE, TRUE, FALSE, FALSE))
    expect_true(ckpt_capturable(paths[1L]))
    expect_true(ckpt_capturable(paths[2L]))
    expect_false(ckpt_capturable(paths[3L]))
    local_mocked_bindings(ckpt_is_link = function(path) rep(TRUE, length(path)))
    expect_false(regular(paths[1L]))
  }, ps_fs_stat = function(...) stop("Windows must not call POSIX stat"), .package = "ps")
})


test_that("checkpoint undo refuses a regular post-image replaced by an owned FIFO", {
  skip_on_os("windows")
  proj = local_project(files = list("source.R" = "answer = 1"))
  ck = ckpt_ck_new("s0000000093")
  call = list(id = "fifo-undo", name = "r", input = list(code = "invisible(NULL)"))
  token = ckpt_files_before(ck, call, 1L)
  pipe = file.path(proj, "source.R")
  writeLines("answer = 2", pipe)
  fragment = ckpt_files_after(ck, call, token)
  expect_true(fragment$files[[1L]]$restorable)
  expect_true(file.remove(pipe))
  fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  original = hash_file
  local_mocked_bindings(hash_file = function(path) {
    if (any(path == pipe)) {
      stop(structure(list(message = "FIFO hash refused", call = NULL),
        class = c("ckpt_fifo_hash_refused", "error", "condition")))
    }
    original(path)
  })
  for (force in c(FALSE, TRUE)) {
    result = ckpt_files_undo(ck, fragment, force = force)
    expect_identical(result$ok, FALSE)
    expect_identical(result$action, "not restored (not a regular file)")
    expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
  }
})


test_that("checkpoint prediction preserves capture of a newly created regular file", {
  proj = local_project()
  path = file.path(proj, "created.R")
  ck = ckpt_ck_new("s0000000094")
  call = list(id = "created", name = "write", input = list(path = path, content = "answer = 42"))
  expect_false(file.exists(path))
  expect_false(ckpt_capturable(path))
  token = ckpt_files_before(ck, call, 1L)
  expect_false(file.exists(path))
  writeLines("answer = 42", path)
  fragment = ckpt_files_after(ck, call, token)
  expect_length(fragment$files, 1L)
  expect_identical(fragment$files[[1L]]$status, "created")
  expect_true(fragment$files[[1L]]$restorable)
  expect_true(nzchar(fragment$files[[1L]]$post))
  expect_identical(readLines(path), "answer = 42")
  expect_true(ckpt_files_undo(ck, fragment)$ok)
  expect_false(file.exists(path))
})


test_that("checkpoint explicit paths reject FIFO and preserve regular size-cap semantics", {
  skip_on_os("windows")
  proj = local_project()
  local_gptr_options(checkpoint_capture_max = 1)
  ck = ckpt_ck_new("s0000000095")
  tr = ckpt_files_tr(ck)
  ckpt_files_sync(tr)
  tr$per_turn = TRUE
  pipe = file.path(proj, "supervisor_stdin")
  call = list(id = "explicit-fifo", name = "write", input = list(path = pipe, content = ""))
  token = ckpt_files_before(ck, call, 1L)
  fifo = processx::conn_create_fifo(pipe, read = TRUE, nonblocking = TRUE)
  withr::defer(close(fifo))
  original = hash_file
  local_mocked_bindings(hash_file = function(path) {
    if (any(path == pipe)) {
      stop(structure(list(message = "FIFO hash refused", call = NULL),
        class = c("ckpt_fifo_hash_refused", "error", "condition")))
    }
    original(path)
  })
  fragment = ckpt_files_after(ck, call, token)
  expect_length(fragment$files, 1L)
  row = fragment$files[[1L]]
  expect_false(row$abs)
  expect_identical(row$path, "supervisor_stdin")
  expect_identical(row$status, "created")
  expect_identical(row$post, "")
  expect_false(row$restorable)
  expect_identical(row$reason, "not a regular file")
  expect_identical(ckpt_files_undo(ck, fragment, force = TRUE)$ok, FALSE)
  expect_identical(ps::ps_fs_stat(pipe, follow = FALSE)$type, "FIFO")
  path = file.path(proj, "over-cap.R")
  call = list(id = "explicit-regular", name = "write", input = list(path = path, content = "42"))
  token = ckpt_files_before(ck, call, 1L)
  writeLines("answer = 42", path)
  regular = ckpt_files_after(ck, call, token)$files[[1L]]
  expect_true(regular$restorable)
  expect_identical(regular$reason, "")
  expect_identical(regular$post, "")
  expect_identical(readLines(path), "answer = 42")
})

test_that("protected and control files are never stored; their rows have no pre-image", {
  proj = local_project(files = list(".env" = "KEY=fake-env-0001", ".Renviron" = "T=fake-ren-0002",
                                    ".ssh/id_rsa" = "fake-key-0003", "a.txt" = "plain"))
  ck = ckpt_ck_new("s0000000197")
  call = list(id = "c1", name = "r", input = list(code = "x = 1"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  expect_identical(names(ck$files$hash), "a.txt")
  for (f in c(".env", ".Renviron")) writeLines("fake-new-0004", file.path(proj, f))
  file.remove(file.path(proj, ".ssh", "id_rsa"))
  frag = ckpt_files_after(ck, call, tok)
  rows = stats::setNames(frag$files, vapply(frag$files, function(r) r$path, ""))
  expect_setequal(names(rows), c(".env", ".Renviron", ".ssh/id_rsa"))
  for (r in rows) expect_match(r$reason, "no pre-image")
  blobs = list.files(file.path(proj, ".gptr", "checkpoints", "blobs"), recursive = TRUE,
                     full.names = TRUE)
  text = vapply(blobs, function(b) {
    x = readBin(b, "raw", file.size(b))
    rawToChar(if (endsWith(b, ".gz")) memDecompress(x, "gzip") else x)
  }, "")
  expect_false(any(grepl("fake-", text, fixed = TRUE)))
})

test_that("a rewind after setwd() uses the store of the session's project", {
  skip_on_cran()
  proj = local_project(files = list("a.txt" = "before"))
  local_fake_provider(list(fake_tool("r", code = "writeLines('after', 'a.txt')"), "done"))
  s = peter("edit a", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_identical(readLines(file.path(proj, "a.txt")), "after")
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  withr::local_dir(withr::local_tempdir())
  expect_no_warning(gptr_rewind(s, 0))
  expect_identical(readLines(file.path(proj, "a.txt")), "before")
})

test_that("a file with a UTF-8 name is captured and restored in a C locale", {
  proj = local_project()
  name = "caf\u00e9 data.txt"
  writeLines("x", fs_path(file.path(proj, name)))
  local_name_locale()
  ck = ckpt_ck_new("s0000000199")
  call = list(id = "c1", name = "r", input = list(code = "x = 1"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  expect_identical(names(ck$files$hash), name)
  file.remove(fs_path(file.path(proj, name)))
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(paths_status(frag), stats::setNames("deleted", name))
  expect_silent(json_encode(frag))
  u = ckpt_files_undo(ck, frag)
  expect_true(all(u$ok))
  expect_identical(readLines(fs_path(file.path(proj, name))), "x")
})
