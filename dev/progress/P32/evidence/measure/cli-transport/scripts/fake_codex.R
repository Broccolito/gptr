# A timing-instrumented stand-in for `codex exec --json` (offline, no model): answers the probes
# gptr runs, then for a session run reads the prompt from stdin, starts the MCP server named by
# `-c mcp_servers.gptr.command/args` (gptr's real stdio relay), does the MCP handshake Codex
# does, makes FAKE_CALLS `tools/call` requests of the `r` tool with FAKE_CODE, and ends the turn.
# Each step's wall-clock time (Sys.time()) goes to FAKE_LOG.<pid> as JSON lines.
t_proc = as.numeric(Sys.time())
argv = commandArgs(trailingOnly = TRUE)
if ("--version" %in% argv) {
  writeLines("codex-cli 0.157.0")
  quit(save = "no", status = 0L)
}
if ("--help" %in% argv) {
  writeLines(c("Run Codex non-interactively", "", "Usage: codex exec [OPTIONS] [PROMPT]", "",
               "Commands:", "  resume  Resume a previous session by id", "", "Options:",
               "  --json  Print events", "  --ignore-user-config  Skip config",
               "  --skip-git-repo-check  Allow", "  -s, --sandbox <MODE>", "  -C, --cd <DIR>",
               "  -m, --model <MODEL>", "  -c, --config <key=value>"))
  quit(save = "no", status = 0L)
}
logf = paste0(Sys.getenv("FAKE_LOG"), ".", Sys.getpid())
lg = function(kind, ...) {
  cat(jsonlite::toJSON(list(kind = kind, t = as.numeric(Sys.time()), ...), auto_unbox = TRUE,
                       digits = NA), "\n", file = logf, append = TRUE, sep = "")
}
lg("proc_start", t_proc = t_proc, resume = identical(argv[2], "resume"),
   sandbox = if ("--sandbox" %in% argv) argv[[match("--sandbox", argv) + 1L]] else
     grep("^sandbox_mode=", argv, value = TRUE)[1])
out = function(x) {
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"), stdout(), useBytes = TRUE)
  flush(stdout())
}
con = file("stdin", open = "rb")
n = 0
repeat {
  b = readBin(con, "raw", 65536L)
  if (!length(b)) break
  n = n + length(b)
}
close(con)
lg("stdin_eof", bytes = n)
thread = if (length(argv) >= 3L && identical(argv[[2L]], "resume")) argv[[3L]] else
  "00000000-0000-4000-8000-000000000001"
out(list(type = "thread.started", thread_id = thread))
out(list(type = "turn.started"))
cfg = function(key) {
  hit = grep(paste0("^mcp_servers[.]gptr[.]", key, "="), argv, value = TRUE)
  sub("^[^=]*=", "", hit[[1L]])
}
cmd = jsonlite::fromJSON(cfg("command"))
args = as.character(unlist(jsonlite::fromJSON(cfg("args"))))
lg("relay_spawn")
p = processx::process$new(cmd, args, stdin = "|", stdout = "|", stderr = "|", encoding = "UTF-8")
ask = function(body, label) {
  t1 = as.numeric(Sys.time())
  p$write_input(paste0(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"), "\n"))
  if (is.null(body$id)) {
    lg("rpc", label = label, t_send = t1, t_recv = NA)
    return(NULL)
  }
  repeat {
    processx::poll(list(p), 1000L)
    ln = p$read_output_lines(1L)
    if (length(ln)) break
    if (!p$is_alive()) stop("relay died")
  }
  t2 = as.numeric(Sys.time())
  lg("rpc", label = label, t_send = t1, t_recv = t2, bytes = nchar(ln, "bytes"))
  jsonlite::fromJSON(ln, simplifyVector = FALSE)
}
ask(list(jsonrpc = "2.0", id = 0L, method = "initialize",
         params = list(protocolVersion = "2025-06-18", capabilities = structure(list(), names = character()),
                       clientInfo = list(name = "fake-codex", version = "0"))), "initialize")
ask(list(jsonrpc = "2.0", method = "notifications/initialized"), "initialized")
tl = ask(list(jsonrpc = "2.0", id = 1L, method = "tools/list"), "tools/list")
lg("handshake_done", tools = length(tl$result$tools))
calls = as.integer(Sys.getenv("FAKE_CALLS", "5"))
code = Sys.getenv("FAKE_CODE", "1 + 1")
text = ""
for (i in seq_len(calls)) {
  item = list(id = paste0("item_", i), type = "mcp_tool_call", server = "gptr", tool = "r",
              arguments = list(code = code), status = "in_progress")
  out(list(type = "item.started", item = item))
  r = ask(list(jsonrpc = "2.0", id = 1L + i, method = "tools/call",
               params = list(name = "r", arguments = list(code = code))), "tools/call")
  text = r$result$content[[1L]]$text %||% ""
  item$status = "completed"
  out(list(type = "item.completed", item = item))
}
close(p$get_input_connection())
p$wait(10000L)
lg("relay_exit", status = p$get_exit_status())
out(list(type = "item.completed", item = list(id = "msg", type = "agent_message",
                                              text = paste("done:", substr(text, 1, 40)))))
out(list(type = "turn.completed", usage = list(input_tokens = 100L, cached_input_tokens = 0L,
                                               cache_write_input_tokens = 0L,
                                               output_tokens = 10L, reasoning_output_tokens = 0L)))
lg("turn_completed")
quit(save = "no", status = 0L)
