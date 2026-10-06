# Pure-R MCP fixture server for gptr's tests: either era, over stdio or Streamable HTTP on
# 127.0.0.1. Adapted from dev/research/16-mcp-skills-plugins.md 5.2 (mcp_server_stdio.R) and
# 5.9 (mcp_session_server()): only JSON-RPC on stdout, logs on stderr, ASCII JSON, exit on EOF.
# Usage: Rscript --vanilla server.R --transport=stdio|http --era=modern|legacy
#        --tools=echo,add,slow,fail,elicit --extra=N --log=<path> [--port=N]
args = commandArgs(trailingOnly = TRUE)
arg = function(name, default = NULL) {
  hit = grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1L]) else default
}
# base R has `%||%` only from R 4.4.0 (the fixture runs on R >= 4.2); an operator keeps its name
`%||%` = function(a, b) if (is.null(a)) b else a # nolint: object_name_linter.
transport = arg("transport", "stdio")
era = arg("era", "modern")
wanted = strsplit(arg("tools", "echo,add,slow,fail,elicit"), ",", fixed = TRUE)[[1L]]
n_extra = as.integer(arg("extra", "0"))
log_path = arg("log", tempfile())
modern_version = "2026-07-28"
legacy_versions = c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
k_ver = "io.modelcontextprotocol/protocolVersion"
k_caps = "io.modelcontextprotocol/clientCapabilities"
k_sinfo = "io.modelcontextprotocol/serverInfo"
page_size = 50L
empty_obj = function() structure(list(), names = character())
info = list(name = "gptr-fixture", version = "1.0.0")

json_ascii = function(s) {
  s = as.character(s)
  Encoding(s) = "UTF-8"
  if (!any(charToRaw(s) > as.raw(127L))) return(s)
  cp = utf8ToInt(s)
  hi = which(cp > 127L)
  out = intToUtf8(cp, multiple = TRUE)
  v = cp[hi]
  esc = character(length(v))
  bmp = v < 65536L
  esc[bmp] = sprintf("\\u%04x", v[bmp])
  a = v[!bmp] - 65536L
  esc[!bmp] = sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] = esc
  paste(out, collapse = "")
}
to_json = function(x) {
  json_ascii(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
log_msg = function(msg, via) {
  rec = list(t = as.numeric(Sys.time()), method = msg$method %||% "response", id = msg$id %||% NA,
             era = era, via = via, arguments = msg$params$arguments %||% empty_obj())
  cat(to_json(rec), "\n", sep = "", file = log_path, append = TRUE)
}
rpc_error = function(id, code, message, data = NULL) {
  e = list(code = code, message = message)
  if (!is.null(data)) e$data = data
  list(jsonrpc = "2.0", id = id, error = e)
}

object_schema = function(properties = empty_obj(), required = NULL) {
  s = list(type = "object", properties = properties)
  if (!is.null(required)) s$required = I(required)
  s
}
tool_defs = function() {
  defs = list(
    echo = list(name = "echo", description = "Echo the text back. Use it to test the connection.",
                inputSchema = object_schema(list(text = list(type = "string",
                                                             description = "Text to echo")),
                                            "text"),
                annotations = list(readOnlyHint = TRUE)),
    add = list(name = "add", description = "Add two numbers.",
               inputSchema = object_schema(list(a = list(type = "number"),
                                                b = list(type = "number")), c("a", "b")),
               annotations = list(readOnlyHint = TRUE, destructiveHint = FALSE)),
    slow = list(name = "slow",
                description = "Wait in steps and report progress between the steps.",
                inputSchema = object_schema(list(steps = list(type = "integer"),
                                                 step_ms = list(type = "integer"),
                                                 progress = list(type = "boolean")))),
    fail = list(name = "fail", description = "Always fails with a tool error.",
                inputSchema = object_schema()),
    elicit = list(name = "elicit", description = "Ask the user for a name and greet them.",
                  inputSchema = object_schema()))
  out = unname(defs[intersect(wanted, names(defs))])
  for (i in seq_len(n_extra)) {
    out[[length(out) + 1L]] = list(
      name = sprintf("tool_%03d", i),
      description = sprintf(paste("Generated tool %d for catalog budget tests.",
                                  "It returns its number."), i),
      inputSchema = object_schema(list(query = list(type = "string", description = "A query"),
                                       limit = list(type = "integer")), "query"))
  }
  out
}
tool_list = tool_defs()

finish_modern = function(result, cacheable = FALSE) {
  if (is.null(result$resultType)) result$resultType = "complete"
  result[["_meta"]] = stats::setNames(list(info), k_sinfo)
  if (cacheable) {
    result$ttlMs = 60000L
    result$cacheScope = "public"
  }
  result
}

list_page = function(cursor) {
  start = if (is.null(cursor)) 1L else suppressWarnings(as.integer(cursor))
  if (is.na(start) || start < 1L) return(NULL)
  idx = seq.int(start, length.out = max(0L, min(page_size, length(tool_list) - start + 1L)))
  res = list(tools = unname(tool_list[idx]))
  if (start + page_size <= length(tool_list)) res$nextCursor = as.character(start + page_size)
  res
}

text_result = function(txt, structured = NULL, is_error = FALSE) {
  r = list(content = list(list(type = "text", text = txt)), isError = is_error)
  if (!is.null(structured)) r$structuredContent = structured
  r
}

# The elicit tool: an input_required round (modern) or an elicitation/create request (legacy)
call_elicit = function(params, ctx) {
  form = list(mode = "form", message = "Who are you?",
              requestedSchema = object_schema(list(name = list(type = "string",
                                                               title = "Your name")), "name"))
  if (ctx$modern) {
    if (is.null(params$inputResponses)) {
      return(list(resultType = "input_required", requestState = "state-1",
                  inputRequests = list(who = list(method = "elicitation/create",
                                                  params = form))))
    }
    if (!identical(params$requestState, "state-1")) {
      return(text_result("bad requestState", is_error = TRUE))
    }
    r = params$inputResponses$who
  } else {
    r = ctx$ask(list(jsonrpc = "2.0", id = "e1", method = "elicitation/create",
                     params = form))$result
  }
  if (identical(r$action, "accept")) return(text_result(paste("Hello", r$content$name)))
  text_result(paste("No name:", r$action %||% "none"))
}

# ctx: list(modern, send = function(msg), ask = function(request), progress_token)
call_tool = function(name, a, params, ctx) {
  if (identical(name, "echo")) {
    txt = as.character(a$text %||% "")
    if (startsWith(txt, "stderr:")) {
      cat(substring(txt, 8L), "\n", sep = "", file = stderr())
      flush(stderr())
    }
    return(text_result(txt, list(text = txt)))
  }
  if (identical(name, "add")) {
    s = as.numeric(a$a) + as.numeric(a$b)
    return(text_result(format(s), list(sum = s)))
  }
  if (identical(name, "slow")) {
    steps = as.integer(a$steps %||% 3L)
    step_ms = as.integer(a$step_ms %||% 200L)
    for (i in seq_len(steps)) {
      Sys.sleep(step_ms / 1000)
      if (!isFALSE(a$progress) && !is.null(ctx$progress_token)) {
        ctx$send(list(jsonrpc = "2.0", method = "notifications/progress",
                      params = list(progressToken = ctx$progress_token, progress = i,
                                    total = steps)))
      }
    }
    return(text_result("done"))
  }
  if (identical(name, "fail")) return(text_result("boom", is_error = TRUE))
  if (identical(name, "elicit")) return(call_elicit(params, ctx))
  if (grepl("^tool_[0-9]+$", name)) return(text_result(sub("^tool_0*", "", name)))
  NULL
}

state = new.env()
state$legacy = FALSE

# One request: a response list, or NULL for notifications
handle = function(msg, ctx) {
  id = msg$id
  method = msg$method
  params = msg$params %||% list()
  if (is.null(method)) return(NULL)
  if (is.null(id)) {
    if (identical(method, "notifications/initialized")) state$legacy = TRUE
    return(NULL)
  }
  ok = function(result) list(jsonrpc = "2.0", id = id, result = result)
  meta_ver = params[["_meta"]][[k_ver]]
  if (identical(method, "initialize")) {
    if (identical(era, "modern")) return(rpc_error(id, -32601L, "Method not found: initialize"))
    v = params$protocolVersion
    v = if (!is.null(v) && v %in% legacy_versions) v else legacy_versions[1L]
    state$legacy = TRUE
    return(ok(list(protocolVersion = v, capabilities = list(tools = list(listChanged = FALSE)),
                   serverInfo = info, instructions = "Fixture server.")))
  }
  if (identical(method, "ping")) return(ok(empty_obj()))
  modern = FALSE
  if (!is.null(meta_ver)) {
    if (identical(era, "legacy")) return(rpc_error(id, -32601L, paste("Method not found:", method)))
    if (!identical(meta_ver, modern_version)) {
      return(rpc_error(id, -32022L, "Unsupported protocol version",
                       list(supported = I(modern_version), requested = meta_ver)))
    }
    if (is.null(params[["_meta"]][[k_caps]])) {
      return(rpc_error(id, -32602L, "Missing _meta clientCapabilities"))
    }
    modern = TRUE
  } else if (!isTRUE(state$legacy)) {
    return(rpc_error(id, -32602L, "Missing _meta protocol fields (or send initialize first)"))
  }
  ctx$modern = modern
  ctx$progress_token = params[["_meta"]]$progressToken
  if (identical(method, "server/discover")) {
    return(ok(finish_modern(list(supportedVersions = I(modern_version),
                                 capabilities = list(tools = list(listChanged = FALSE)),
                                 instructions = "Fixture server."), cacheable = TRUE)))
  }
  if (identical(method, "tools/list")) {
    res = list_page(params$cursor)
    if (is.null(res)) return(rpc_error(id, -32602L, "Invalid cursor"))
    return(ok(if (modern) finish_modern(res, cacheable = TRUE) else res))
  }
  if (identical(method, "tools/call")) {
    res = call_tool(as.character(params$name %||% ""), params$arguments %||% list(), params, ctx)
    if (is.null(res)) return(rpc_error(id, -32602L, paste("Unknown tool:", params$name)))
    return(ok(if (modern) finish_modern(res) else res))
  }
  rpc_error(id, -32601L, paste("Method not found:", method))
}

serve_stdio = function() {
  con = file("stdin", open = "r")
  send = function(msg) {
    cat(to_json(msg), "\n", sep = "", file = stdout())
    flush(stdout())
  }
  read_msg = function() {
    repeat {
      line = readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(line)) return(NULL)
      line = sub("\r$", "", line)
      if (!nzchar(trimws(line))) next
      msg = tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(msg)) {
        send(rpc_error(NULL, -32700L, "Parse error"))
        next
      }
      log_msg(msg, "stdio")
      return(msg)
    }
  }
  ask = function(request) {
    send(request)
    repeat {
      m = read_msg()
      if (is.null(m)) return(NULL)
      if (identical(m$id, request$id) && is.null(m$method)) return(m)
    }
  }
  repeat {
    msg = read_msg()
    if (is.null(msg)) break
    resp = tryCatch(handle(msg, list(send = send, ask = ask)), error = function(e) {
      rpc_error(msg$id, -32603L, conditionMessage(e))
    })
    if (!is.null(resp)) send(resp)
  }
  close(con)
}

serve_http = function(port) {
  sessions = new.env()
  resp = function(status, body = "", headers = list(), type = "application/json") {
    list(status = status, headers = c(list(`Content-Type` = type), headers), body = body)
  }
  bad = function(status, id, code, message) resp(status, to_json(rpc_error(id, code, message)))
  route = function(req) {
    h = function(name) req[[paste0("HTTP_", toupper(gsub("-", "_", name)))]]
    if (!identical(req$PATH_INFO, "/mcp")) return(resp(404L))
    if (!identical(req$REQUEST_METHOD, "POST")) {
      sid = h("Mcp-Session-Id")
      gone = identical(req$REQUEST_METHOD, "DELETE") && !is.null(sid) &&
        exists(sid, envir = sessions)
      if (gone) {
        rm(list = sid, envir = sessions)
        return(resp(200L))
      }
      return(resp(405L, "", list(Allow = "POST")))
    }
    body = rawToChar(req$rook.input$read())
    Encoding(body) = "UTF-8"
    msg = tryCatch(jsonlite::fromJSON(body, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) return(bad(400L, NULL, -32700L, "Parse error"))
    log_msg(msg, "http")
    notes = list()
    ctx = list(send = function(m) notes[[length(notes) + 1L]] <<- m, ask = function(r) NULL)
    meta_ver = msg$params[["_meta"]][[k_ver]]
    if (!is.null(meta_ver)) {
      if (identical(era, "legacy")) return(bad(400L, msg$id, -32600L, "Missing Mcp-Session-Id"))
      same = identical(h("MCP-Protocol-Version"), meta_ver) &&
        identical(h("Mcp-Method"), msg$method)
      if (!same) return(bad(400L, msg$id, -32020L, "Header mismatch"))
      if (is.null(msg$id)) return(resp(202L))
      out = handle(msg, ctx)
    } else {
      if (identical(msg$method, "initialize")) {
        out = handle(msg, ctx)
        if (!is.null(out$error)) return(resp(400L, to_json(out)))
        state$n_sessions = (state$n_sessions %||% 0L) + 1L
        sid = sprintf("session-%d-%d", Sys.getpid(), state$n_sessions)
        assign(sid, TRUE, envir = sessions)
        return(resp(200L, to_json(out), list(`Mcp-Session-Id` = sid)))
      }
      if (identical(era, "modern")) {
        return(bad(400L, msg$id, -32602L, "Missing _meta protocol fields"))
      }
      sid = h("Mcp-Session-Id")
      if (is.null(sid)) return(bad(400L, msg$id, -32600L, "Missing Mcp-Session-Id"))
      if (!exists(sid, envir = sessions)) return(resp(404L))
      if (is.null(msg$id)) return(resp(202L))
      state$legacy = TRUE
      out = handle(msg, ctx)
    }
    if (length(notes)) {
      ev = vapply(c(notes, list(out)), function(n) {
        paste0("event: message\ndata: ", to_json(n), "\n\n")
      }, "")
      return(resp(200L, paste(ev, collapse = ""), list(`Cache-Control` = "no-cache"),
                  type = "text/event-stream"))
    }
    resp(200L, to_json(out))
  }
  app = list(call = function(req) {
    tryCatch(route(req), error = function(e) {
      resp(500L, to_json(list(error = conditionMessage(e))))
    })
  })
  srv = tryCatch(httpuv::startServer("127.0.0.1", port, app), error = function(e) NULL)
  if (is.null(srv)) quit(save = "no", status = 3L)
  cat("READY", port, "\n")
  flush(stdout())
  parent = suppressWarnings(as.integer(Sys.getenv("GPTR_FIXTURE_PARENT")))
  repeat {
    httpuv::service(100)
    alive = is.na(parent) ||
      tryCatch(ps::ps_is_running(ps::ps_handle(parent)), error = function(e) FALSE)
    if (!alive) break
  }
  httpuv::stopServer(srv)
}

if (identical(transport, "http")) serve_http(as.integer(arg("port", "0"))) else serve_stdio()
quit(save = "no", status = 0L)
