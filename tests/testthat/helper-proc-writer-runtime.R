# Production witnesses reuse the independent D-019 watchdog; no transport method is replaced.
rw_child_case = function(case, root) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  old = options(gptr.stdin_timeout = 2, gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old), add = TRUE)
  p = NULL
  on.exit({
    fun("reactor_shutdown")()
    if (!is.null(p)) fun("kill_all")(p, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  script = file.path(root, "target.R")
  echo = c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
    "repeat { x = readLines(con, n = 1L, warn = FALSE, encoding = 'UTF-8')",
    "if (!length(x)) break; cat(x, '\\n', sep = ''); flush(stdout()) }")
  binary = c("cat('READY\\n'); flush(stdout()); con = file('stdin', 'rb')",
    "bytes = readBin(con, 'raw', n = 8L)",
    "cat(paste(as.integer(bytes), collapse = ','), '\\n', sep = ''); flush(stdout())")
  writeLines(if (case == "binary") binary else echo, script)
  phase("spawn")
  p = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script),
    env = fun("child_env")("worker"), stdin = "|", supervise = FALSE)
  record = fun("proc_record")(p$get_pid(), p)
  saveRDS(record, file.path(root, "inner-identity.rds"))
  st = new.env(parent = emptyenv())
  st$out = character()
  st$status = NULL
  st$exits = 0L
  watcher = fun("reactor_proc")(p, function(line) st$out = c(st$out, line), function(status) {
    st$status = status
    st$exits = st$exits + 1L
  })
  stopifnot(fun("reactor_pump")(until = function() "READY" %in% st$out, timeout = 10))
  phase("ready")
  first = if (case == "binary") as.raw(c(0, 255, 195, 169)) else charToRaw("first\n")
  second = if (case == "binary") as.raw(c(10, 66, 0, 127)) else charToRaw("second\n")
  phase("writer-start")
  fun("write_all")(p, first)
  if (case != "binary")
    stopifnot(fun("reactor_pump")(until = function() "first" %in% st$out, timeout = 10))
  writer = fun("proc_writer_get")(p)
  stopifnot(is.environment(writer), isTRUE(writer$private))
  cat(fun("json_encode")(list(case = case, expression_bytes = writer$expression_bytes,
    startup_elapsed = writer$startup_elapsed)), "\n")
  writer_record = fun("proc_record")(writer$p$get_pid(), writer$p)
  stopifnot(is.finite(writer_record$create_time))
  directory = writer$dir
  same_writer = FALSE
  orphan_swept = FALSE
  error = NULL
  acl = NULL
  acl_readback = function(writer) {
    literal = function(text) paste0("'", gsub("'", "''", text, fixed = TRUE), "'")
    probe = file.path(writer$dir, "acl-created-file")
    stopifnot(fun("proc_writer_valid")(writer$dir, writer$canonical, writer$marker, probe),
      !file.exists(probe))
    bytes = charToRaw("PUBLIC-ACL-SENTINEL")
    utility = NULL
    on.exit({
      if (!is.null(utility)) fun("kill_all")(utility, grace = 0)
      if (fun("proc_writer_valid")(writer$dir, writer$canonical, writer$marker, probe))
        unlink(probe)
    }, add = TRUE)
    writeBin(bytes, probe)
    script = paste(c(
      "$ErrorActionPreference = 'Stop'",
      paste0("$parent = ", literal(writer$dir)),
      paste0("$file = ", literal(probe)),
      "$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()",
      "$sid = $identity.User",
      "$fileOwner = $identity.Owner",
      "if ($null -eq $fileOwner -or",
      "    -not ($fileOwner -is [System.Security.Principal.SecurityIdentifier])) {",
      "  throw 'Token owner' }",
      "$fullControl = [System.Security.AccessControl.FileSystemRights]::FullControl",
      "$sections = [System.Security.AccessControl.AccessControlSections]::Access",
      "$sections = $sections -bor [System.Security.AccessControl.AccessControlSections]::Owner",
      "$attributes = [System.IO.File]::GetAttributes($parent)",
      "if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Alias' }",
      "$acl = [System.IO.Directory]::GetAccessControl($parent, $sections)",
      "$rules = @($acl.GetAccessRules($true, $true,",
      "  [System.Security.Principal.SecurityIdentifier]))",
      "if (-not $acl.AreAccessRulesProtected -or $rules.Count -ne 1 -or",
      "    $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) {",
      "  throw 'Parent ACL' }",
      "$r = $rules[0]",
      "if ($r.IdentityReference.Value -ne $sid.Value -or $r.IsInherited -or",
      "    $r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or",
      "    $r.FileSystemRights -ne $fullControl -or",
      "    [int]$r.InheritanceFlags -ne 3 -or [int]$r.PropagationFlags -ne 0) {",
      "  throw 'Parent rights' }",
      "[Console]::WriteLine('GPTR-ACL-PARENT-OK')",
      "$attributes = [System.IO.File]::GetAttributes($file)",
      "if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'File alias' }",
      "$acl = [System.IO.File]::GetAccessControl($file, $sections)",
      "$rules = @($acl.GetAccessRules($true, $true,",
      "  [System.Security.Principal.SecurityIdentifier]))",
      "if ($acl.AreAccessRulesProtected -or $rules.Count -ne 1 -or",
      "    $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne",
      "    $fileOwner.Value) { throw 'File ACL' }",
      "$r = $rules[0]",
      "if ($r.IdentityReference.Value -ne $sid.Value -or -not $r.IsInherited -or",
      "    $r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or",
      "    $r.FileSystemRights -ne $fullControl -or",
      "    [int]$r.InheritanceFlags -ne 0 -or [int]$r.PropagationFlags -ne 0) {",
      "  throw 'File rights' }",
      "[Console]::WriteLine('GPTR-ACL-FILE-OK')",
      "$refused = $false",
      "try { & {",
      fun("proc_writer_acl")(writer$dir, "GPTR_PROC_ffffffffffffffff"),
      "} } catch {",
      "  if ($_.Exception.Message -ceq 'Existing writer directory') { $refused = $true }",
      "  else { throw }",
      "}",
      "if (-not $refused) { throw 'Existing path not refused' }",
      "[Console]::WriteLine('GPTR-ACL-EXISTING-REFUSED')"
    ), collapse = "\n")
    shell = file.path(Sys.getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0",
      "powershell.exe")
    seen = new.env(parent = emptyenv())
    seen$out = character()
    seen$status = NULL
    started = fun("reactor_now")()
    utility = fun("proc_spawn")(shell,
      c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
        fun("shell_ps_encode")(script)), env = fun("child_env")("helper"), stdin = NULL,
      stdout = "|", stderr = NULL, supervise = FALSE)
    record = fun("proc_record")(utility$get_pid(), utility)
    stopifnot(is.list(record), is.finite(record$create_time))
    fun("reactor_proc")(utility, on_line = function(line) {
      seen$out = c(seen$out, line)
      if (line %in% c("GPTR-ACL-PARENT-OK", "GPTR-ACL-FILE-OK", "GPTR-ACL-EXISTING-REFUSED"))
        phase(line)
    }, on_exit = function(status) {
      seen$status = status
      phase("acl-utility-exit")
    })
    complete = fun("reactor_pump")(until = function() !is.null(seen$status),
      timeout = max(0, 5 - (fun("reactor_now")() - started)))
    elapsed = fun("reactor_now")() - started
    stopifnot(complete, identical(seen$status, 0L), elapsed <= 5)
    settled = fun("kill_all")(utility, grace = 0)
    if (isTRUE(settled)) utility = NULL
    sentinel = identical(readBin(probe, "raw", n = length(bytes) + 1L), bytes)
    owner = identical(readBin(file.path(writer$dir, "owner"), "raw", n = 27L),
      charToRaw(writer$marker))
    stopifnot(fun("proc_writer_valid")(writer$dir, writer$canonical, writer$marker, probe))
    unlink(probe)
    list(output = seen$out, elapsed = elapsed, status = seen$status,
      sentinel_unchanged = sentinel, owner_unchanged = owner,
      probe_removed = !(basename(probe) %in% list.files(writer$dir, all.files = TRUE,
        no.. = TRUE)), utility_settled = isTRUE(settled),
      utility_dead = !fun("pid_alive")(record$pid, record$create_time),
      utility_marker_removed = !file.exists(file.path(fun("proc_dir")(),
        paste0(record$marker, ".json"))))
  }
  if (case %in% c("ordered", "binary")) {
    fun("write_all")(p, raw(0))
    fun("write_all")(p, second)
    same_writer = identical(fun("proc_writer_get")(p), writer)
    fun("write_close")(p)
    stopifnot(fun("reactor_pump")(until = function() !is.null(st$status), timeout = 10))
  } else if (case == "failed") {
    fun("kill_all")(writer$p, grace = 0)
    error = tryCatch(fun("write_all")(p, second), error = identity)
    fun("reactor_cancel")(watcher)
  } else if (case == "shutdown") {
    fun("reactor_shutdown")()
  } else if (case == "orphan") {
    saved = writer_record
    saved$parent_create = saved$parent_create + 1000
    stopifnot(isFALSE(fun("proc_parent_alive")(saved)))
    fun("write_atomic")(file.path(fun("proc_dir")(), paste0(saved$marker, ".json")),
      fun("json_encode")(saved))
    orphan_swept = fun("proc_sweep")() > 0L
  } else if (case == "acl") {
    phase("acl-readback")
    acl = acl_readback(writer)
    acl$writer_same = identical(fun("proc_writer_get")(p), writer) &&
      isTRUE(writer$p$is_alive()) && isTRUE(p$is_alive())
    fun("write_close")(p)
    stopifnot(fun("reactor_pump")(until = function() !is.null(st$status), timeout = 10))
  } else {
    stop("Unknown owned writer runtime case.")
  }
  fun("kill_all")(p, grace = 0)
  fun("reactor_cancel")(watcher)
  reactor = fun("reactor_get")()
  stdin_empty = !length(ls(reactor$stdin, all.names = TRUE))
  watchers_empty = !length(ls(reactor$procs, all.names = TRUE))
  st$tick = FALSE
  fun("reactor_timer")(fun("reactor_now")(), function() st$tick = TRUE)
  responsive = fun("reactor_pump")(until = function() st$tick, timeout = 5)
  phase("complete")
  list(complete = TRUE, input_bytes = length(first) + if (case == "acl") 0L else length(second),
    output = st$out,
    same_writer = same_writer, orphan_swept = orphan_swept, acl = acl,
    expression_bytes = writer$expression_bytes, startup_elapsed = writer$startup_elapsed,
    private = writer$private, status = st$status, writer_identity = writer_record,
    stdin_empty = stdin_empty, watchers_empty = watchers_empty, reactor_responsive = responsive,
    io_error = inherits(error, "gptr_error_io"), exit_callbacks = st$exits,
    writer_dead = !fun("pid_alive")(writer_record$pid, writer_record$create_time),
    inner_dead = !fun("pid_alive")(record$pid, record$create_time),
    mailbox_removed = !dir.exists(directory), writer_removed = is.null(fun("proc_writer_get")(p)),
    marker_removed = !file.exists(file.path(fun("proc_dir")(),
      paste0(writer_record$marker, ".json"))))
}

rw_run = function(case) {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = rw_child_case
  runner(case)
}

rw_expect_bounded = function(x) {
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(x$complete, label = paste(x$case, x$guard))
  if (!x$complete) return(FALSE)
  expect_true(is.list(x$result$writer_identity) && is.finite(x$result$writer_identity$create_time))
  expect_true(x$result$private)
  expect_true(is.numeric(x$result$expression_bytes) && length(x$result$expression_bytes) == 1L &&
    is.finite(x$result$expression_bytes) && x$result$expression_bytes <= 9998L)
  expect_true(is.numeric(x$result$startup_elapsed) && length(x$result$startup_elapsed) == 1L &&
    is.finite(x$result$startup_elapsed) && x$result$startup_elapsed >= 0)
  expect_true(x$result$stdin_empty)
  expect_true(x$result$watchers_empty)
  expect_true(x$result$reactor_responsive)
  expect_true(x$result$writer_dead)
  expect_true(x$result$inner_dead)
  expect_true(x$result$mailbox_removed)
  expect_true(x$result$writer_removed)
  expect_true(x$result$marker_removed)
  TRUE
}

# Deterministic state fixtures exercise failure/accounting without launching any child.
rw_local_state = function(.env = parent.frame()) {
  st = new.env(parent = emptyenv())
  st$dir = withr::local_tempdir(.local_envir = .env)
  st$canonical = normalizePath(st$dir, winslash = "/", mustWork = TRUE)
  st$marker = "GPTR_PROC_0123456789abcdef"
  writeBin(charToRaw(st$marker), file.path(st$dir, "owner"))
  st$private = TRUE
  st$pending = list(size = 6L, accepted = 0L)
  st$index = 1
  st$closing = FALSE
  st$closed = FALSE
  st$diagnostic_tail = ""
  st$diagnostic_bytes = 0L
  st$phases = numeric()
  st$p = list(is_alive = function() TRUE, get_exit_status = function() 0L,
    poll_io = function(timeout) NULL, read_error = function(n) "")
  b = new.env(parent = emptyenv())
  b$p = list(is_alive = function() TRUE)
  b$bytes = charToRaw("abcdef")
  b$pos = 0L
  b$last = 0
  b$close = FALSE
  b$limit = 2
  list(st = st, b = b)
}

# Run one native utility under the unchanged D-019 family/resource watchdog.
rw_absence_case = function(case, root) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) {
    cat(text, "\n", sep = "", file = file.path(root, "phases.txt"), append = TRUE)
  }
  old = options(gptr.stdin_timeout = 2, gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old), add = TRUE)
  file.create(file.path(root, "case-started"))
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  before = list(env = Sys.getenv(), cwd = getwd(), options = options(), seed = seed(),
    names = sort(ls(envir = globalenv(), all.names = TRUE)))
  paths = stats::setNames(file.path(root, c("fresh' mailbox", "existing-dir", "existing-file",
    "fresh' mailbox/denied-file", "dangling-file", "missing-target", "absence-probe.ps1",
    "absence-recovery.ps1", "parent-access.txt", "file-access.txt", "denial-armed")),
    c("fresh", "directory", "file", "denied", "link", "missing", "script", "recovery",
      "parent_backup", "file_backup", "armed"))
  marker = "GPTR_PROC_0123456789abcdef"
  sentinel = charToRaw("PUBLIC-ABSENCE-SENTINEL")
  bytes = function(path) readBin(path, "raw", n = length(sentinel) + 1L)
  stopifnot(dir.create(paths[["directory"]]))
  writeBin(sentinel, paths[["file"]])
  writeBin(sentinel, paths[["missing"]])
  state = new.env(parent = emptyenv())
  state$recovered = FALSE
  state$utility_unsettled = FALSE
  state$settlement_failed = FALSE
  recover = NULL
  present = function(path) {
    basename(path) %in% list.files(dirname(path), all.files = TRUE, no.. = TRUE)
  }
  on.exit({
    stopifnot(!state$utility_unsettled, !state$settlement_failed)
    if (present(paths[["armed"]]) && !state$recovered) recover()
    fun("reactor_shutdown")()
    # Recovery and exact readback precede deletion, including utility timeout/error.
    if (present(paths[["armed"]])) stopifnot(state$recovered)
    files = paths[c("link", "file", "denied", "script", "recovery", "parent_backup",
                    "file_backup", "armed")]
    for (path in files) if (present(path)) file.remove(path)
    owner = file.path(paths[["fresh"]], "owner")
    if (file.exists(owner) && identical(readBin(owner, "raw", n = 27L), charToRaw(marker)))
      file.remove(owner)
    if (dir.exists(paths[["fresh"]]) &&
        !length(list.files(paths[["fresh"]], all.files = TRUE, no.. = TRUE)))
      unlink(paths[["fresh"]], recursive = FALSE)
    if (dir.exists(paths[["directory"]]) &&
        !length(list.files(paths[["directory"]], all.files = TRUE, no.. = TRUE)))
      unlink(paths[["directory"]], recursive = FALSE)
  }, add = TRUE)
  phase("absence-link-create")
  stopifnot(isTRUE(file.symlink(paths[["missing"]], paths[["link"]])),
    identical(bytes(paths[["link"]]), sentinel), file.remove(paths[["missing"]]),
    basename(paths[["link"]]) %in% list.files(root, all.files = TRUE, no.. = TRUE),
    !file.exists(paths[["missing"]]))
  literal = function(text) paste0("'", gsub("'", "''", text, fixed = TRUE), "'")
  refuse = function(path, proof, kind = NULL) {
    capture = if (!is.null(kind)) {
      c(paste0("$entry = ", literal(path)),
        paste0("$before = [System.IO.", kind, "]::GetAccessControl($entry, $sections)"),
        "$descriptor = $before.GetSecurityDescriptorSddlForm($sections)")
    } else {
      character()
    }
    unchanged = if (!is.null(kind)) {
      c(paste0("$after = [System.IO.", kind, "]::GetAccessControl($entry, $sections)"),
        "if ($after.GetSecurityDescriptorSddlForm($sections) -cne $descriptor) {",
        "  throw 'Existing ACL changed' }")
    } else {
      character()
    }
    c(capture, "$refused = $false", "try { & {", fun("proc_writer_acl")(path, marker),
      "} } catch {",
      "  if ($_.Exception.Message -ceq 'Existing writer directory') { $refused = $true }",
      "  else { throw }", "}", "if (-not $refused) { throw 'Existing entry accepted' }",
      unchanged,
      paste0("[Console]::WriteLine('", proof, "')"))
  }
  script = paste(c(
    "$ErrorActionPreference = 'Stop'",
    paste0("$link = ", literal(paths[["link"]])),
    paste0("$denied = ", literal(paths[["denied"]])),
    paste0("$parentBackup = ", literal(paths[["parent_backup"]])),
    paste0("$fileBackup = ", literal(paths[["file_backup"]])),
    paste0("$armed = ", literal(paths[["armed"]])),
    "$access = [System.Security.AccessControl.AccessControlSections]::Access",
    "try {",
    fun("proc_writer_acl")(paths[["fresh"]], marker, .diagnostics = TRUE),
    paste0("$fresh = ", literal(paths[["fresh"]])),
    "$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()",
    "$sid = $identity.User",
    "$sections = [System.Security.AccessControl.AccessControlSections]::Access",
    "$sections = $sections -bor [System.Security.AccessControl.AccessControlSections]::Owner",
    "$got = [System.IO.Directory]::GetAccessControl($fresh, $sections)",
    "$rules = @($got.GetAccessRules($true, $true,",
    "  [System.Security.Principal.SecurityIdentifier]))",
    "if (-not $got.AreAccessRulesProtected -or $rules.Count -ne 1 -or",
    "    $got.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) {",
    "  throw 'Fresh owner or protected rules' }",
    "$r = $rules[0]",
    "if ($r.IdentityReference.Value -ne $sid.Value -or $r.IsInherited -or",
    "    $r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or",
    "    $r.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or",
    "    [int]$r.InheritanceFlags -ne 3 -or [int]$r.PropagationFlags -ne 0) {",
    "  throw 'Fresh exact rule' }",
    "$attributes = [System.IO.File]::GetAttributes($fresh)",
    "if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Fresh alias' }",
    "[Console]::WriteLine('GPTR-ABSENCE-FRESH-OK')",
    refuse(paths[["directory"]], "GPTR-ABSENCE-DIRECTORY-REFUSED", "Directory"),
    refuse(paths[["file"]], "GPTR-ABSENCE-FILE-REFUSED", "File"),
    "$attributes = [System.IO.File]::GetAttributes($link)",
    "if (-not ($attributes -band [System.IO.FileAttributes]::ReparsePoint)) {",
    "  throw 'Dangling entry not identified' }",
    refuse(paths[["link"]], "GPTR-ABSENCE-DANGLING-REFUSED"),
    "function WritePrivate([string]$path, [string]$text) {",
    "  $acl = [System.Security.AccessControl.FileSecurity]::new()",
    "  $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true, $false)",
    "  $allow = [System.Security.AccessControl.FileSystemAccessRule]::new(",
    "    $sid, [System.Security.AccessControl.FileSystemRights]::FullControl,",
    "    [System.Security.AccessControl.AccessControlType]::Allow)",
    "  $acl.AddAccessRule($allow)",
    "  $stream = [System.IO.File]::Create($path, 4096, [System.IO.FileOptions]::None, $acl)",
    "  try {",
    "    $bytes = [System.Text.Encoding]::ASCII.GetBytes($text)",
    "    $stream.Write($bytes, 0, $bytes.Length)",
    "  } finally { $stream.Close() }",
    "}",
    "WritePrivate $denied 'PUBLIC-ABSENCE-SENTINEL'",
    "$fileOriginal = [System.IO.File]::GetAccessControl($denied, $sections)",
    "$rules = @($fileOriginal.GetAccessRules($true, $true,",
    "  [System.Security.Principal.SecurityIdentifier]))",
    "if (-not $fileOriginal.AreAccessRulesProtected -or $rules.Count -ne 1 -or",
    "    $fileOriginal.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne",
    "    $sid.Value) { throw 'Protected file fixture' }",
    "$r = $rules[0]",
    "if ($r.IdentityReference.Value -ne $sid.Value -or $r.IsInherited -or",
    "    $r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or",
    "    $r.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or",
    "    [int]$r.InheritanceFlags -ne 0 -or [int]$r.PropagationFlags -ne 0) {",
    "  throw 'Protected file rule' }",
    "$parentOriginal = [System.IO.Directory]::GetAccessControl($fresh, $access)",
    "WritePrivate $parentBackup ($parentOriginal.GetSecurityDescriptorSddlForm($access))",
    "WritePrivate $fileBackup ($fileOriginal.GetSecurityDescriptorSddlForm($access))",
    "WritePrivate $armed 'ARMED'",
    "$deny = [System.IO.File]::GetAccessControl($denied)",
    "$rule = [System.Security.AccessControl.FileSystemAccessRule]::new(",
    "  $sid, [System.Security.AccessControl.FileSystemRights]::ReadAttributes,",
    "  [System.Security.AccessControl.AccessControlType]::Deny)",
    "$deny.AddAccessRule($rule)",
    "[System.IO.File]::SetAccessControl($denied, $deny)",
    "$denyParent = [System.IO.Directory]::GetAccessControl($fresh)",
    "$rule = [System.Security.AccessControl.FileSystemAccessRule]::new(",
    "  $sid, [System.Security.AccessControl.FileSystemRights]::ListDirectory,",
    "  [System.Security.AccessControl.AccessControlType]::Deny)",
    "$denyParent.AddAccessRule($rule)",
    "[System.IO.Directory]::SetAccessControl($fresh, $denyParent)",
    "$refused = $false",
    "try { & {", fun("proc_writer_acl")(paths[["denied"]], marker),
    "} } catch [System.UnauthorizedAccessException] { $refused = $true }",
    "if (-not $refused) { throw 'Attribute denial not effective' }",
    "[Console]::WriteLine('GPTR-ABSENCE-DENIED-REFUSED')",
    "} finally {",
    "  try {",
    "    if ($null -ne $parentOriginal) {",
    "      $restore = [System.Security.AccessControl.DirectorySecurity]::new()",
    "      $descriptor = $parentOriginal.GetSecurityDescriptorSddlForm($access)",
    "      $restore.SetSecurityDescriptorSddlForm($descriptor, $access)",
    "      [System.IO.Directory]::SetAccessControl($fresh, $restore)",
    "      $got = [System.IO.Directory]::GetAccessControl($fresh, $access)",
    "      if ($got.GetSecurityDescriptorSddlForm($access) -cne $descriptor) {",
    "        throw 'Parent access not restored' }",
    "    }",
    "    if ($null -ne $fileOriginal) {",
    "      $restore = [System.Security.AccessControl.FileSecurity]::new()",
    "      $descriptor = $fileOriginal.GetSecurityDescriptorSddlForm($access)",
    "      $restore.SetSecurityDescriptorSddlForm($descriptor, $access)",
    "      [System.IO.File]::SetAccessControl($denied, $restore)",
    "      $got = [System.IO.File]::GetAccessControl($denied, $access)",
    "      if ($got.GetSecurityDescriptorSddlForm($access) -cne $descriptor) {",
    "        throw 'File access not restored' }",
    "    }",
    "    [Console]::WriteLine('GPTR-ABSENCE-RESTORED')",
    "  } finally { [System.IO.File]::Delete($link) }",
    "}"
  ), collapse = "\n")
  writeLines(script, paths[["script"]], useBytes = TRUE)
  shell = file.path(Sys.getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0",
    "powershell.exe")
  run_utility = function(path, proof, identity = FALSE) {
    seen = new.env(parent = emptyenv())
    seen$out = character()
    seen$status = NULL
    utility = NULL
    record = NULL
    settle = function() {
      previous_failure = state$settlement_failed
      state$settlement_failed = TRUE
      stopped = fun("kill_all")(utility, grace = 0)
      stopifnot(isTRUE(stopped), is.list(record), is.finite(record$pid),
        is.finite(record$create_time), identical(fun("pid_alive")(record$pid,
          record$create_time), FALSE))
      entries = list.files(fun("proc_dir")(), all.files = TRUE, no.. = FALSE)
      stopifnot(all(c(".", "..") %in% entries),
        !(paste0(record$marker, ".json") %in% entries),
        is.null(fun("proc_record")(record$pid, utility)), !previous_failure)
      state$settlement_failed = FALSE
      state$utility_unsettled = FALSE
      invisible(TRUE)
    }
    on.exit({
      if (!is.null(utility)) settle()
    }, add = TRUE)
    started = fun("reactor_now")()
    state$utility_unsettled = TRUE
    utility = fun("proc_spawn")(shell,
      c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path),
      env = fun("child_env")("helper"), stdin = NULL, stdout = "|", stderr = NULL,
      supervise = FALSE)
    record = fun("proc_record")(utility$get_pid(), utility)
    stopifnot(is.list(record), is.finite(record$create_time))
    if (identity) saveRDS(record, file.path(root, "inner-identity.rds"))
    fun("reactor_proc")(utility, on_line = function(line) {
      stopifnot(line %in% proof, length(seen$out) < length(proof))
      seen$out = c(seen$out, line)
      phase(line)
    }, on_exit = function(status) {
      seen$status = status
      phase("absence-utility-exit")
    })
    complete = fun("reactor_pump")(until = function() !is.null(seen$status),
      timeout = max(0, 5 - (fun("reactor_now")() - started)))
    elapsed = fun("reactor_now")() - started
    stopifnot(complete, identical(seen$status, 0L), elapsed <= 5, identical(seen$out, proof))
    settle()
    utility = NULL
    list(proof = seen$out, elapsed = elapsed, status = seen$status,
      utility_settled = TRUE, utility_dead = TRUE, marker_removed = TRUE)
  }
  recovery = paste(c(
    "$ErrorActionPreference = 'Stop'",
    paste0("$parent = ", literal(paths[["fresh"]])),
    paste0("$file = ", literal(paths[["denied"]])),
    paste0("$parentBackup = ", literal(paths[["parent_backup"]])),
    paste0("$fileBackup = ", literal(paths[["file_backup"]])),
    "$access = [System.Security.AccessControl.AccessControlSections]::Access",
    "$descriptor = [System.IO.File]::ReadAllText($parentBackup)",
    "$restore = [System.Security.AccessControl.DirectorySecurity]::new()",
    "$restore.SetSecurityDescriptorSddlForm($descriptor, $access)",
    "[System.IO.Directory]::SetAccessControl($parent, $restore)",
    "$got = [System.IO.Directory]::GetAccessControl($parent, $access)",
    "if ($got.GetSecurityDescriptorSddlForm($access) -cne $descriptor) {",
    "  throw 'Parent recovery mismatch' }",
    "$descriptor = [System.IO.File]::ReadAllText($fileBackup)",
    "$restore = [System.Security.AccessControl.FileSecurity]::new()",
    "$restore.SetSecurityDescriptorSddlForm($descriptor, $access)",
    "[System.IO.File]::SetAccessControl($file, $restore)",
    "$got = [System.IO.File]::GetAccessControl($file, $access)",
    "if ($got.GetSecurityDescriptorSddlForm($access) -cne $descriptor) {",
    "  throw 'File recovery mismatch' }",
    "[Console]::WriteLine('GPTR-ABSENCE-RECOVERY-OK')"
  ), collapse = "\n")
  writeLines(recovery, paths[["recovery"]], useBytes = TRUE)
  recover = function() {
    stopifnot(!state$utility_unsettled, !state$settlement_failed,
      present(paths[["armed"]]), present(paths[["parent_backup"]]),
      present(paths[["file_backup"]]))
    x = run_utility(paths[["recovery"]], "GPTR-ABSENCE-RECOVERY-OK")
    stopifnot(x$utility_settled, x$utility_dead, x$marker_removed)
    state$recovered = TRUE
    invisible(TRUE)
  }
  proof = c(paste0("GPTR_STDIN_ACL ", c("enter", "absent", "created", "readback",
    "verified", "owner")), "GPTR-ABSENCE-FRESH-OK", "GPTR-ABSENCE-DIRECTORY-REFUSED",
    "GPTR-ABSENCE-FILE-REFUSED", "GPTR-ABSENCE-DANGLING-REFUSED",
    "GPTR-ABSENCE-DENIED-REFUSED", "GPTR-ABSENCE-RESTORED")
  phase("absence-utility-start")
  result = run_utility(paths[["script"]], proof, identity = TRUE)
  recover()
  owner = file.path(paths[["fresh"]], "owner")
  stopifnot(identical(readBin(owner, "raw", n = 27L), charToRaw(marker)),
    identical(bytes(paths[["file"]]), sentinel), identical(bytes(paths[["denied"]]), sentinel),
    !file.exists(paths[["missing"]]),
    !(basename(paths[["link"]]) %in% list.files(root, all.files = TRUE, no.. = TRUE)),
    !length(list.files(paths[["directory"]], all.files = TRUE, no.. = TRUE)),
    identical(sort(list.files(paths[["fresh"]], all.files = TRUE, no.. = TRUE)),
      sort(c("owner", "denied-file"))))
  stopifnot(file.remove(owner), file.remove(paths[["file"]]), file.remove(paths[["denied"]]),
    all(file.remove(paths[c("script", "recovery", "parent_backup", "file_backup", "armed")])),
    identical(unlink(paths[["fresh"]], recursive = FALSE), 0L),
    identical(unlink(paths[["directory"]], recursive = FALSE), 0L))
  fun("reactor_shutdown")()
  after = list(env = Sys.getenv(), cwd = getwd(), options = options(), seed = seed(),
    names = sort(ls(envir = globalenv(), all.names = TRUE)))
  phase("complete")
  c(list(complete = TRUE), result, list(sentinels_unchanged = TRUE,
    entries_removed = !any(basename(paths) %in% list.files(root, all.files = TRUE, no.. = TRUE)),
    restored = state$recovered && identical(before, after)))
}

rw_absence_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = rw_absence_case
  runner("native-absence")
}
