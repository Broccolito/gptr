# Fixed pure PowerShell controls, before either held-B R protocol or native execution.
token_held_faults = function(packet, output) {
  stopifnot(identical(.Platform$OS.type, "windows"), dir.exists(packet), dir.exists(output))
  ns = asNamespace("gptr")
  spawn = get("proc_spawn", ns, inherits = FALSE)
  kill = get("kill_all", ns, inherits = FALSE)
  now = get("reactor_now", ns, inherits = FALSE)
  dir = tempfile("held-faults-", tmpdir = output)
  stopifnot(dir.create(dir, mode = "0700"))
  logs = file.path(dir, c("stdout.log", "stderr.log"))
  stopifnot(all(file.create(logs)), all(Sys.chmod(logs, "0600")))
  state = new.env(parent = emptyenv())
  state$process = NULL
  state$attempted = FALSE
  state$settled = FALSE
  outcome = NULL
  on.exit({
    cleanup = tryCatch({
      if (state$attempted && is.null(state$process)) stop("Held fault launch is unknown")
      if (!is.null(state$process) && !state$settled) {
        state$settled = isTRUE(kill(state$process, grace = 0)) &&
          identical(state$process$is_alive(), FALSE)
        if (!state$settled) stop("Held fault utility did not settle")
      }
      NULL
    }, error = identity, interrupt = identity)
    if (!is.null(cleanup) && (is.null(outcome) || is.null(outcome$error))) stop(cleanup)
  }, add = TRUE)
  outcome = tryCatch({
    started = now()
    shell = file.path(Sys.getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0",
      "powershell.exe")
    state$attempted = TRUE
    process = spawn(shell, c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-File", file.path(packet, "controls", "test-held-faults.ps1"),
      "-Fragment", file.path(packet, "token-held.ps1")), env = Sys.getenv(),
      stdin = NULL, stdout = logs[[1L]], stderr = logs[[2L]], supervise = FALSE,
      .on_spawn = function(p) state$process = p)
    repeat {
      remaining = 5 - (now() - started)
      if (remaining <= 0) stop("Held fault utility deadline exceeded")
      process$wait(as.integer(min(50, remaining * 1000)))
      alive = process$is_alive()
      if (now() - started > 5) stop("Held fault utility deadline exceeded")
      if (identical(alive, FALSE)) break
      if (!identical(alive, TRUE)) stop("Held fault utility liveness is unknown")
    }
    status = process$get_exit_status()
    elapsed = now() - started
    stdout = readBin(logs[[1L]], "raw", n = 16385L)
    stderr = readBin(logs[[2L]], "raw", n = 16385L)
    expected = "GPTR-HELD-FAULT-CONTROLS-12"
    stopifnot(identical(status, 0L), elapsed <= 5, !length(stderr),
      length(stdout) <= 16384L,
      identical(stdout, charToRaw(paste0(expected, "\r\n"))) ||
        identical(stdout, charToRaw(paste0(expected, "\n"))))
    state$settled = isTRUE(kill(process, grace = 0)) &&
      identical(process$is_alive(), FALSE)
    if (!state$settled) stop("Held fault utility did not settle")
    elapsed = now() - started
    if (elapsed > 5) stop("Held fault utility deadline exceeded")
    list(value = list(cases = 12L, status = status, elapsed_s = elapsed,
      utility_timeout_s = 5L, settled = TRUE, stderr_bytes = 0L), error = NULL)
  }, error = function(e) list(value = NULL, error = e),
     interrupt = function(e) list(value = NULL, error = e))
  if (!is.null(outcome$error)) stop(outcome$error)
  outcome$value
}
