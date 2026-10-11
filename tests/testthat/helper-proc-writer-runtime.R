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
