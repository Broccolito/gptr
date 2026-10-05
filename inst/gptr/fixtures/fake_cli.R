# fake_cli.R -- a fake `claude` / `codex` CLI for gptr's tests (P20; contract 12.4, IC-60).
#
# Run through rscript_path(), never by name:
#   Rscript --vanilla fake_cli.R --fake-cli <claude|codex> --fake-case <case> \
#           --fake-dir <fixtures dir> --fake-log <log file> <the real CLI's argv ...>
# It answers --version, --help and `exec --help` like the real CLIs (claude 2.1.261, codex-cli
# 0.157.0; case "old" reports older versions, "bare-default"/"bare-optout" change the claude
# help, "old"/"noresume" the codex help), logs its argv, pid, environment variable NAMES (never
# values), stdin lines and the start ("turn") and end ("turn_done") of each claude turn as JSON
# lines to the log file, and replays
# <fixtures dir>/claude-<case>.ndjson or codex-<case>.jsonl line by line. Fixture lines that are
# JSON objects with a "fake" key are directives:
#   {"fake":"sleep","seconds":0.5}                       pause
#   {"fake":"hang"}                                      claude: wait for stdin (an interrupt
#                                                        control request then ends the turn as
#                                                        aborted); codex: sleep for an hour
#   {"fake":"exit","status":1}                           exit with a status
#   {"fake":"mcp","method":"tools/call","params":{}}     claude: ask the host over mcp_message
#   {"fake":"can_use_tool","tool_name":"..","input":{}}  claude: ask the host for permission
#   {"fake":"mcp_call","tool":"r","arguments":{}}        codex: call gptr's HTTP MCP server
#   {"fake":"write_file","path":"x.txt","text":".."}     codex: write a file in its directory
# Other lines are printed verbatim after replacing $TOOL_TEXT (text of the last MCP result,
# JSON-escaped), $THREAD (the codex thread id) and $PROMPT_BYTES (bytes codex read on stdin).
# Base R, jsonlite and (for mcp_call only) curl. It never reads credentials or calls a model.

# `b` when `a` is NULL: gptr's internal infix is not visible in this script, base R has one only
# from 4.4.0, and a snake_case name needs no lint exception
if_null = function(a, b) if (is.null(a)) b else a

argv = commandArgs(trailingOnly = TRUE)
opt = list(cli = "claude", case = "text", dir = ".", log = "")
while (length(argv) >= 2L && startsWith(argv[[1L]], "--fake-")) {
  opt[[sub("^--fake-", "", argv[[1L]])]] = argv[[2L]]
  argv = argv[-(1:2)]
}

to_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
from_json = function(x) {
  Encoding(x) = "UTF-8"
  tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE), error = function(e) NULL)
}
out = function(txt) {
  writeLines(txt, stdout(), useBytes = TRUE)
  flush(stdout())
}
log_line = function(kind, ...) {
  if (!nzchar(opt$log)) return(invisible(NULL))
  con = file(opt$log, open = "ab")
  on.exit(close(con))
  writeLines(to_json(list(kind = kind, pid = Sys.getpid(), t = as.numeric(Sys.time()), ...)),
             con, useBytes = TRUE)
  invisible(NULL)
}
json_inner = function(x) {
  j = to_json(x)
  substr(j, 2L, nchar(j) - 1L)
}

state = new.env()
state$n = 0L
state$tool_text = ""
state$thread = "00000000-0000-4000-8000-000000000001"
state$session = "11111111-1111-4111-8111-111111111111"
state$prompt_bytes = 0L
state$queue = list()
state$hanging = FALSE

fill = function(ln) {
  ln = gsub("$TOOL_TEXT", json_inner(state$tool_text), ln, fixed = TRUE)
  ln = gsub("$THREAD", state$thread, ln, fixed = TRUE)
  gsub("$PROMPT_BYTES", as.character(state$prompt_bytes), ln, fixed = TRUE)
}

# ---- probes: --version, --help, exec --help, sandbox -----------------------------------------
if ("--version" %in% argv) {
  old = identical(opt$case, "old")
  out(if (identical(opt$cli, "claude")) {
    if (old) "1.9.0 (Claude Code)" else "2.1.261 (Claude Code)"
  } else {
    if (old) "codex-cli 0.100.0" else "codex-cli 0.157.0"
  })
  quit(save = "no", status = 0L)
}
if (identical(opt$cli, "codex") && length(argv) && identical(argv[[1L]], "sandbox")) {
  log_line("sandbox", argv = I(argv))
  quit(save = "no", status = 0L)
}
if ("--help" %in% argv) {
  if (identical(opt$cli, "claude")) {
    bare_default = "  --bare                 Minimal mode (the default with -p/--print)"
    bare = switch(opt$case,
                  "bare-optout" = c(bare_default, "  --no-bare              Full mode"),
                  "bare-default" = bare_default,
                  "  --bare                 Minimal mode: skip hooks, plugins and CLAUDE.md")
    out(c("Usage: claude [options] [command] [prompt]", "",
          "  -p, --print            Print response and exit (useful for pipes)",
          "  --output-format <format>  \"text\", \"json\" or \"stream-json\"",
          "  --input-format <format>   \"text\" or \"stream-json\"",
          "  --include-partial-messages  Include partial message chunks",
          "  --verbose              Override verbose mode setting from config",
          "  --tools <tools...>     Built-in tools; \"\" disables all",
          "  --mcp-config <configs...>  Load MCP servers from JSON files or strings",
          "  --strict-mcp-config    Only use MCP servers from --mcp-config",
          "  --setting-sources <sources>  Comma-separated setting sources",
          "  --disable-slash-commands  Disable all skills",
          "  --permission-mode <mode>  Permission mode for the session",
          "  --allowedTools, --allowed-tools <tools...>  Tools to allow",
          "  --model <model>        Model for the current session",
          "  --resume [value]       Resume a conversation by session ID",
          bare))
  } else {
    resume = if (identical(opt$case, "noresume")) character() else
      "  resume  Resume a previous session by id or pick the most recent with --last"
    flags = if (identical(opt$case, "old")) {
      c("  --json                 Print events to stdout as JSONL", "  -m, --model <MODEL>")
    } else {
      c("  --json                 Print events to stdout as JSONL",
        "  --ignore-user-config   Do not load $CODEX_HOME/config.toml",
        "  --skip-git-repo-check  Allow running outside a Git repository",
        "  -s, --sandbox <SANDBOX_MODE>", "  -C, --cd <DIR>", "  -m, --model <MODEL>",
        "  -c, --config <key=value>")
    }
    out(c("Run Codex non-interactively", "", "Usage: codex exec [OPTIONS] [PROMPT] [COMMAND]",
          "", "Commands:", resume, "", "Options:", flags))
  }
  quit(save = "no", status = 0L)
}

# ---- a session --------------------------------------------------------------------------------
log_line("argv", argv = I(argv))
log_line("env", names = I(sort(names(Sys.getenv()))))
log_line("start", wd = getwd())
ext = if (identical(opt$cli, "claude")) ".ndjson" else ".jsonl"
script = readLines(file.path(opt$dir, paste0(opt$cli, "-", opt$case, ext)), encoding = "UTF-8",
                   warn = FALSE)
script = script[nzchar(trimws(script))]

# ---- claude: stream-json on stdin and stdout, control protocol both ways ----------------------
if (identical(opt$cli, "claude")) {
  inp = file("stdin", open = "r")
  next_msg = function() {
    repeat {
      ln = readLines(inp, n = 1L, encoding = "UTF-8", warn = FALSE)
      if (!length(ln)) return(NULL)
      if (!nzchar(ln)) next
      log_line("stdin", line = ln)
      m = from_json(ln)
      if (is.list(m)) return(m)
    }
  }
  reply = function(id, response) {
    out(to_json(list(type = "control_response",
                     response = list(subtype = "success", request_id = id,
                                     response = response))))
  }
  aborted_result = function() {
    out(to_json(list(type = "result", subtype = "error_during_execution", is_error = TRUE,
                     terminal_reason = "aborted_streaming", result = "",
                     session_id = state$session, total_cost_usd = 0, num_turns = 1L,
                     usage = list(input_tokens = 0L, output_tokens = 0L,
                                  cache_read_input_tokens = 0L,
                                  cache_creation_input_tokens = 0L))))
  }
  host_request = function(m) {
    sub = if_null(m$request$subtype, "")
    if (identical(sub, "interrupt")) {
      log_line("interrupt")
      reply(m$request_id, list(still_queued = list()))
      if (isTRUE(state$hanging)) {
        state$hanging = FALSE
        aborted_result()
      }
      return(invisible(NULL))
    }
    if (identical(sub, "initialize")) {
      handshake()
      return(reply(m$request_id, list(commands = list(), models = list())))
    }
    out(to_json(list(type = "control_response",
                     response = list(subtype = "error", request_id = m$request_id,
                                     error = paste("Unsupported control request subtype:",
                                                   sub)))))
  }
  ask = function(request) {
    state$n = state$n + 1L
    id = paste0("cli_req_", state$n)
    out(to_json(list(type = "control_request", request_id = id, request = request)))
    repeat {
      m = next_msg()
      if (is.null(m)) quit(save = "no", status = 0L)
      if (identical(m$type, "control_response") && identical(m$response$request_id, id)) {
        return(m$response)
      }
      if (identical(m$type, "control_request")) {
        host_request(m)
      } else {
        state$queue[[length(state$queue) + 1L]] = m
      }
    }
  }
  mcp = function(method, params = NULL, notify = FALSE) {
    message = list(jsonrpc = "2.0", method = method)
    if (!notify) message$id = state$n + 100L
    if (!is.null(params)) message$params = params
    ask(list(subtype = "mcp_message", server_name = "gptr", message = message))
  }
  handshake = function() {
    mcp("initialize", list(protocolVersion = "2025-06-18",
                           capabilities = structure(list(), names = character()),
                           clientInfo = list(name = "fake-claude", version = "0.0.1")))
    mcp("notifications/initialized", notify = TRUE)
    mcp("tools/list")
    log_line("handshake")
    invisible(NULL)
  }
  run_turn = function() {
    for (ln in script) {
      d = from_json(ln)
      if (!is.list(d) || is.null(d$fake)) {
        out(fill(ln))
        next
      }
      if (identical(d$fake, "hang")) {
        state$hanging = TRUE
        return(invisible(FALSE))
      }
      if (identical(d$fake, "sleep")) Sys.sleep(as.numeric(if_null(d$seconds, 0.1)))
      if (identical(d$fake, "exit")) quit(save = "no", status = as.integer(if_null(d$status, 1L)))
      if (identical(d$fake, "mcp")) {
        r = mcp(d$method, d$params)
        content = r$response$mcp_response$result$content
        state$tool_text = if (length(content)) if_null(content[[1L]]$text, "") else ""
        log_line("mcp", method = d$method, text = state$tool_text)
      }
      if (identical(d$fake, "can_use_tool")) {
        r = ask(list(subtype = "can_use_tool", tool_name = d$tool_name,
                     input = if_null(d$input, structure(list(), names = character())),
                     tool_use_id = if_null(d$tool_use_id, "toolu_fake")))
        log_line("permission", behavior = if_null(r$response$behavior, "none"))
      }
    }
    invisible(TRUE)
  }
  repeat {
    if (length(state$queue)) {
      m = state$queue[[1L]]
      state$queue = state$queue[-1L]
    } else {
      m = next_msg()
    }
    if (is.null(m)) break
    if (identical(m$type, "control_request")) {
      host_request(m)
    } else if (identical(m$type, "user")) {
      log_line("turn")
      if (isTRUE(run_turn())) log_line("turn_done")
    }
  }
  log_line("end")
  quit(save = "no", status = 0L)
}

# ---- codex: the prompt on stdin until EOF, JSONL on stdout ------------------------------------
con = file("stdin", open = "rb")
chunks = list()
repeat {
  b = readBin(con, "raw", 65536L)
  if (!length(b)) break
  chunks[[length(chunks) + 1L]] = b
}
close(con)
prompt = if (length(chunks)) do.call(c, chunks) else raw()
state$prompt_bytes = length(prompt)
prompt_file = if (nzchar(opt$log)) paste0(opt$log, ".", Sys.getpid(), ".prompt") else ""
if (nzchar(prompt_file)) writeBin(prompt, prompt_file)
log_line("prompt", bytes = length(prompt), file = prompt_file)
if (length(argv) >= 3L && identical(argv[[2L]], "resume")) state$thread = argv[[3L]]

mcp_url = function() {
  hit = grep("^mcp_servers[.]gptr[.]url=", argv, value = TRUE)
  if (length(hit)) sub("^mcp_servers[.]gptr[.]url=", "", hit[[1L]]) else ""
}
mcp_post = function(url, token, body, sid = NULL) {
  h = curl::new_handle()
  hdr = list(`Content-Type` = "application/json", Accept = "application/json, text/event-stream",
             Authorization = paste("Bearer", token), `MCP-Protocol-Version` = "2025-11-25")
  if (!is.null(sid)) hdr[["Mcp-Session-Id"]] = sid
  do.call(curl::handle_setheaders, c(list(h), hdr))
  curl::handle_setopt(h, postfields = to_json(body), followlocation = 0L, timeout = 120L)
  curl::curl_fetch_memory(url, handle = h)
}
mcp_body = function(res) {
  txt = rawToChar(res$content)
  Encoding(txt) = "UTF-8"
  if (!grepl("^[[:space:]]*[{[]", txt)) {
    lines = strsplit(txt, "\r?\n")[[1L]]
    txt = paste(sub("^data: ?", "", grep("^data:", lines, value = TRUE)), collapse = "\n")
  }
  if_null(from_json(txt), list())
}
mcp_call = function(d) {
  url = mcp_url()
  token = Sys.getenv("GPTR_MCP_TOKEN")
  if (!nzchar(url) || !nzchar(token)) {
    state$tool_text = "no gptr MCP server"
    log_line("mcp", status = NA, text = state$tool_text)
    return(invisible(NULL))
  }
  params = list(protocolVersion = "2025-11-25",
                capabilities = structure(list(), names = character()),
                clientInfo = list(name = "fake-codex", version = "0.0.1"))
  init = mcp_post(url, token,
                  list(jsonrpc = "2.0", id = 1L, method = "initialize", params = params))
  sid = curl::parse_headers_list(init$headers)[["mcp-session-id"]]
  mcp_post(url, token, list(jsonrpc = "2.0", method = "notifications/initialized"), sid)
  res = mcp_post(url, token, list(jsonrpc = "2.0", id = 2L, method = "tools/call",
                                  params = list(name = d$tool, arguments = d$arguments)), sid)
  body = mcp_body(res)
  content = body$result$content
  state$tool_text = if (length(content)) {
    if_null(content[[1L]]$text, "")
  } else {
    if_null(body$error$message, "")
  }
  log_line("mcp", status = res$status_code, text = state$tool_text)
  invisible(NULL)
}

for (ln in script) {
  d = from_json(ln)
  if (!is.list(d) || is.null(d$fake)) {
    out(fill(ln))
    next
  }
  if (identical(d$fake, "sleep")) Sys.sleep(as.numeric(if_null(d$seconds, 0.1)))
  if (identical(d$fake, "hang")) Sys.sleep(3600)
  if (identical(d$fake, "exit")) quit(save = "no", status = as.integer(if_null(d$status, 1L)))
  if (identical(d$fake, "write_file")) writeLines(if_null(d$text, ""), d$path)
  if (identical(d$fake, "mcp_call")) mcp_call(d)
}
log_line("end")
quit(save = "no", status = 0L)
