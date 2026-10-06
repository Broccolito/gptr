# Shared helpers of the P15 document tests (test-doc-*.R).

# Bind a document for the calling test (restores the previous binding)
local_doc_binding = function(path, format = "r", .env = parent.frame()) {
  old = the$doc_binding
  the$doc_binding = list(path = path_norm(path), format = format)
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  invisible(path)
}

# A session with recorded turns, built the way P06 records them: the turn counter moves first,
# then the turn's entries are appended (user messages carry their turn number)
doc_test_session = function(turns, mode = "auto", kind = "chat", home = new.env()) {
  s = session_new("fake/fake-1", mode, home = home, kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, note = NULL, outputs = character(), status = "ok", record = TRUE,
                         prompt = "count rows", answer = "There are 32 rows.", value = NULL,
                         id = "call_1") {
  usage = function(i, o) {
    list(input = i, output = o, cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
         cost = list(total = 0))
  }
  args = list(code = code)
  if (!is.null(note)) args$note = note
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call(id, "r", args)), api = "fake", provider = "fake",
      model = "fake-1", usage = usage(100, 20), stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      id, "r", "[1] 32", is_error = !identical(status, "ok"),
      details = list(code = code, record = record, note = note, status = status,
                     outputs = outputs, value = value))),
    list(type = "message", message = msg_assistant(
      answer, api = "fake", provider = "fake", model = "fake-1", usage = usage(150, 10)))
  )
}

# The call record P08 builds (call_new()) for the stand-in peter() whose body calls this directly
# (not as a lazy argument): its call, its frame number and its caller's environment. The prompt
# is forced first, so the inner calls of a pipe run before the outer call is located.
doc_record = function(prompt, replay = NULL) {
  force(prompt)
  nf = sys.nframe() - 1L
  call_new(prompt, envir = parent.frame(2L), args = list(replay = replay), sys_call = sys.call(-1L),
           nframe = nf)
}

# An environment whose peter() stands in for the gateway: the call record as P08 builds it, the
# document route first, then (when it passes) a scripted run that evaluates `code` in the
# caller's frame as the agent's r call and writes the block through the agent_end hook, as the
# real run does. `log` counts the runs and keeps the last run's site.
doc_stand_in = function(code = "n = 99", log = new.env()) {
  e = new.env()
  log$runs = 0L
  e$log = log
  e$peter = function(prompt, ..., replay = NULL) {
    call = doc_record(prompt, replay)
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(invisible(res))
    }
    log$runs = log$runs + 1L
    log$site = call$doc
    eval(parse(text = code), call$envir)
    s = doc_test_session(list(doc_test_turn(code, prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    invisible(s)
  }
  e
}
