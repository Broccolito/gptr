# A timing-instrumented stand-in for `claude -p --input-format stream-json` (offline, no
# model): answers gptr's probes, the initialize control request (after the in-process `sdk` MCP
# handshake over mcp_message control requests, as Claude Code does), and for each user message
# makes FAKE_CALLS tools/call requests of the `r` tool with FAKE_CODE, then a result line.
# Wall-clock (Sys.time()) phases go to FAKE_LOG.<pid> as JSON lines.
t_proc = as.numeric(Sys.time())
argv = commandArgs(trailingOnly = TRUE)
if ("--version" %in% argv) {
  writeLines("2.1.261 (Claude Code)")
  quit(save = "no", status = 0L)
}
if ("--help" %in% argv) {
  writeLines(c("Usage: claude [options]", "  -p, --print  Print response and exit",
               "  --resume [value]  Resume a conversation"))
  quit(save = "no", status = 0L)
}
logf = paste0(Sys.getenv("FAKE_LOG"), ".", Sys.getpid())
lg = function(kind, ...) {
  cat(jsonlite::toJSON(list(kind = kind, t = as.numeric(Sys.time()), ...), auto_unbox = TRUE,
                       digits = NA), "\n", file = logf, append = TRUE, sep = "")
}
lg("proc_start", t_proc = t_proc, resume = "--resume" %in% argv)
sid = "11111111-1111-4111-8111-111111111111"
tj = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
out = function(x) {
  writeLines(tj(x), stdout(), useBytes = TRUE)
  flush(stdout())
}
inp = file("stdin", open = "r")
queue = list()
next_msg = function() {
  repeat {
    ln = readLines(inp, n = 1L, warn = FALSE)
    if (!length(ln)) return(NULL)
    if (nzchar(ln)) return(jsonlite::fromJSON(ln, simplifyVector = FALSE))
  }
}
n = 0L
ask = function(request, label) {
  n <<- n + 1L
  id = paste0("cli_req_", n)
  t1 = as.numeric(Sys.time())
  out(list(type = "control_request", request_id = id, request = request))
  repeat {
    m = next_msg()
    if (is.null(m)) quit(save = "no", status = 0L)
    if (identical(m$type, "control_response") && identical(m$response$request_id, id)) {
      lg("rpc", label = label, t_send = t1, t_recv = as.numeric(Sys.time()))
      return(m$response)
    }
    queue[[length(queue) + 1L]] <<- m
  }
}
mcp = function(method, params = NULL, notify = FALSE) {
  message = list(jsonrpc = "2.0", method = method)
  if (!notify) message$id = n + 100L
  if (!is.null(params)) message$params = params
  ask(list(subtype = "mcp_message", server_name = "gptr", message = message), method)
}
calls = as.integer(Sys.getenv("FAKE_CALLS", "5"))
code = Sys.getenv("FAKE_CODE", "1 + 1")
repeat {
  m = if (length(queue)) {
    x = queue[[1L]]
    queue = queue[-1L]
    x
  } else next_msg()
  if (is.null(m)) break
  if (identical(m$type, "control_request") && identical(m$request$subtype, "initialize")) {
    lg("initialize_received")
    mcp("initialize", list(protocolVersion = "2025-06-18",
                           capabilities = structure(list(), names = character()),
                           clientInfo = list(name = "fake-claude", version = "0")))
    mcp("notifications/initialized", notify = TRUE)
    mcp("tools/list")
    lg("handshake_done")
    out(list(type = "control_response", response = list(subtype = "success",
             request_id = m$request_id, response = list(commands = list(), models = list()))))
  } else if (identical(m$type, "control_request")) {
    out(list(type = "control_response", response = list(subtype = "success",
             request_id = m$request_id, response = list(still_queued = list()))))
  } else if (identical(m$type, "user")) {
    lg("turn_start")
    out(list(type = "system", subtype = "init", cwd = getwd(), session_id = sid,
             tools = I(c("mcp__gptr__r", "mcp__gptr__read", "mcp__gptr__edit", "mcp__gptr__write")),
             mcp_servers = list(list(name = "gptr", status = "connected")),
             model = "claude-sonnet-5-5", permissionMode = "default", apiKeySource = "none"))
    text = ""
    for (i in seq_len(calls)) {
      r = mcp("tools/call", list(name = "r", arguments = list(code = code)))
      text = r$response$mcp_response$result$content[[1L]]$text %||% ""
    }
    out(list(type = "result", subtype = "success", is_error = FALSE,
             result = paste("done:", substr(text, 1, 40)), stop_reason = "end_turn",
             session_id = sid, num_turns = 1L, total_cost_usd = 0,
             usage = list(input_tokens = 100L, cache_creation_input_tokens = 0L,
                          cache_read_input_tokens = 0L, output_tokens = 10L)))
    lg("turn_done")
  }
}
lg("end")
quit(save = "no", status = 0L)
