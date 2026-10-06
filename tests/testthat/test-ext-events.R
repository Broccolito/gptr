test_that("the catalogue lists the 46 events of contract 10.4 with their semantics", {
  cat = ev_catalogue()
  expect_named(cat, c("event", "semantics", "fail_closed", "payload", "returns", "origin"))
  expect_equal(nrow(cat), 46L)
  expect_equal(anyDuplicated(cat$event), 0L)
  expect_setequal(cat$event[cat$fail_closed],
                  c("tool_call", "permission_request", "document_write"))
  expect_true(all(cat$semantics %in% c("notify", "collect", "transform", "decision",
                                       "first_decision", "patch", "block_patch")))
  expect_true(all(cat$origin %in% c("pi", "gptr")))
  expect_equal(cat$origin[cat$event == "request_params"], "gptr")
  expect_equal(cat$origin[cat$event == "tool_call"], "pi")
  expect_equal(ev_semantics("tool_call"), "decision")
  expect_equal(ev_semantics("tool_result"), "patch")
  expect_equal(ev_semantics("request_params"), "patch")
  expect_equal(ev_semantics("input"), "transform")
  expect_equal(ev_semantics("session_start"), "collect")
  expect_equal(ev_semantics("resources_discover"), "collect")
  expect_equal(ev_semantics("permission_request"), "first_decision")
  expect_equal(ev_semantics("project_trust"), "first_decision")
  expect_equal(ev_semantics("document_write"), "block_patch")
  expect_equal(ev_semantics("myplugin:done"), "notify")
  expect_null(ev_semantics("PreToolUse"))
})

test_that("Claude, Codex, pre-IC-03 and unported names are refused with a hint", {
  err = expect_error(ev_check_name("PreToolUse"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "did you mean 'tool_call'?", fixed = TRUE)
  expect_equal(err$arg, "event")
  err = expect_error(ev_check_name("session_end"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "session_shutdown", fixed = TRUE)
  err = expect_error(ev_check_name("context"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "not ported", fixed = TRUE)
  err = expect_error(ev_check_name("Tool_Call"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "did you mean 'tool_call'?", fixed = TRUE)
  expect_error(ev_check_name("no_such_event"), class = "gptr_error_invalid_argument")
  expect_error(ev_check_name(NA_character_), class = "gptr_error_invalid_argument")
  expect_error(ev_check_name(c("a", "b")), class = "gptr_error_invalid_argument")
  expect_equal(ev_check_name("tool_call"), "tool_call")
  expect_equal(ev_check_name("myplugin:done"), "myplugin:done")
  expect_true(ev_is_channel("my.plugin:topic-1"))
  expect_false(ev_is_channel("tool_call"))
  expect_false(ev_is_channel("a:b:c"))
})

test_that("notify runs listeners then hooks by rank; a handler error is a diagnostic", {
  local_registry()
  log = new.env()
  log$seen = character()
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "builtin"), rank = 6L,
           source = "builtin:demo")
  hook_add("turn_end", function(event, ctx) stop("hook bug"), rank = 3L, source = "user")
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "session"), rank = 0L,
           source = "session", session = "s1")
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "other"), rank = 0L,
           source = "session", session = "s2")
  expect_null(ev_dispatch("turn_end", list(message = NULL), session = "s1"))
  expect_equal(log$seen, c("session", "builtin"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "user" & d$event == "turn_end" & grepl("hook bug", d$message)))
})

test_that("events without handlers return the neutral result of their semantics", {
  local_registry()
  expect_null(ev_dispatch("agent_start", list()))
  expect_equal(ev_dispatch("session_start", list(reason = "new")), list())
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt")),
               list(action = "continue", text = "hi"))
  expect_equal(ev_dispatch("tool_call", list(tool_name = "r", input = list(code = "1"))),
               list(decision = "allow", reason = NULL, input = list(code = "1")))
  expect_null(ev_dispatch("permission_request", list(tool = "r")))
  expect_equal(ev_dispatch("document_write", list(lines = c("a", "b"))),
               list(block = FALSE, reason = NULL, lines = c("a", "b")))
  expect_error(ev_dispatch("PreToolUse", list()), class = "gptr_error_invalid_argument")
})

test_that("collect merges named lists (earlier wins) and concatenates the rest, capped", {
  local_registry()
  hook_add("session_start", function(event, ctx) {
    list(sections = list(house = "A", keep = NULL), blocks = list(list(text = "x")))
  }, rank = 0L, source = "session", session = "s1")
  hook_add("session_start", function(event, ctx) {
    list(sections = list(house = "B", extra = "C"), blocks = list(list(text = "y")))
  })
  res = ev_dispatch("session_start", list(reason = "new"), session = "s1")
  expect_equal(res$sections$house, "A")
  expect_equal(res$sections$extra, "C")
  expect_true("keep" %in% names(res$sections))
  expect_length(res$blocks, 2L)
  hook_add("session_start", function(event, ctx) {
    list(blocks = list(list(text = strrep("z", 9000L)), list(text = strrep("w", 2000L))))
  })
  res = ev_dispatch("session_start", list(reason = "new"), session = "s1")
  total = sum(vapply(res$blocks, function(b) nchar(b$text), 0))
  expect_lte(total, 10000)
  expect_true(any(gptr_registry(diagnostics = TRUE)$class == "context_cap"))
})

test_that("the input transform chain replaces text and stops at handled", {
  local_registry()
  hook_add("input", function(event, ctx) list(action = "transform", text = toupper(event$text)))
  hook_add("input", function(event, ctx) list(action = "transform", text = paste(event$text, "!")))
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt")),
               list(action = "transform", text = "HI !"))
  hook_add("input", function(event, ctx) list(action = "handled"), rank = 0L, source = "session",
           session = "s1")
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt"), session = "s1")$action,
               "handled")
})

test_that("plugin channels reject newline-suffixed names", {
  for (channel in c("plugin:topic\n", "plugin:topic\r\n", "plugin:topic\r")) {
    expect_false(ev_is_channel(channel))
    expect_error(ev_check_name(channel), class = "gptr_error_invalid_argument")
  }
})

test_that("handled transforms cannot bypass the injected context cap", {
  local_registry()
  hook_add("input", function(event, ctx) list(action = "handled", text = strrep("x", 10001)))
  res = ev_dispatch("input", list(text = "original"))
  expect_equal(res$action, "handled")
  expect_equal(nchar(res$text), ev_cap)
  expect_true(any(gptr_registry(diagnostics = TRUE)$class == "context_cap"))
  local_registry()
  hook_add("input", function(event, ctx) list(action = "transform", text = strrep("y", 10001)))
  hook_add("input", function(event, ctx) list(action = "handled"))
  expect_equal(nchar(ev_dispatch("input", list(text = "original"))$text), ev_cap)
})

test_that("tool_call: modify flows on, block stops, and a throwing hook blocks (fail closed)", {
  local_registry()
  hook_add("tool_call", function(event, ctx) {
    list(decision = "modify", input = list(code = paste0(event$input$code, " + 1")))
  })
  res = ev_dispatch("tool_call", list(tool_name = "r", tool_call_id = "c1",
                                      input = list(code = "1")))
  expect_equal(res$decision, "modify")
  expect_equal(res$input, list(code = "1 + 1"))
  hook_add("tool_call", function(event, ctx) stop("hook bug"), source = "plugin:bad", rank = 5L)
  res = ev_dispatch("tool_call", list(tool_name = "r", tool_call_id = "c1",
                                      input = list(code = "1")))
  expect_equal(res$decision, "block")
  expect_match(res$reason, "plugin:bad failed: hook bug", fixed = TRUE)
})

test_that("tool_call: an unknown decision blocks; a non-list return has no opinion", {
  local_registry()
  log = new.env()
  hook_add("tool_call", function(event, ctx) log$seen = event$tool_name)
  call = list(tool_name = "r", tool_call_id = "c1", input = list(code = "1"))
  expect_equal(ev_dispatch("tool_call", call)$decision, "allow")
  expect_equal(log$seen, "r")
  hook_add("tool_call", function(event, ctx) list(decision = "deny", reason = "no installs"),
           source = "plugin:guard", rank = 5L)
  res = ev_dispatch("tool_call", call)
  expect_equal(res$decision, "block")
  expect_match(res$reason, "unknown decision", fixed = TRUE)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "malformed_decision" & d$source == "plugin:guard"))
  local_registry()
  hook_add("tool_call", function(event, ctx) list(decision = "modify", input = "x = 1"))
  expect_equal(ev_dispatch("tool_call", call)$decision, "block")
})

test_that("a throwing permission_request hook denies; the first answer wins", {
  local_registry()
  hook_add("permission_request", function(event, ctx) stop("reviewer down"))
  res = ev_dispatch("permission_request", list(tool = "r", tier = "ask"))
  expect_equal(res$decision, "deny")
  expect_match(res$reason, "reviewer down", fixed = TRUE)
  local_registry()
  hook_add("permission_request", function(event, ctx) NULL)
  hook_add("permission_request", function(event, ctx) list(decision = "allow", reason = "ok"))
  hook_add("permission_request", function(event, ctx) list(decision = "deny", reason = "late"))
  expect_equal(ev_dispatch("permission_request", list(tool = "r"))$reason, "ok")
})

test_that("a failing first-decision handler of another event is skipped", {
  local_registry()
  hook_add("session_before_fork", function(event, ctx) stop("bug"))
  hook_add("session_before_fork", function(event, ctx) list(cancel = TRUE, reason = "no"))
  expect_equal(ev_dispatch("session_before_fork", list(source = "s1", at = "e1"))$reason, "no")
})

test_that("first decision: non-list and empty returns have no opinion", {
  local_registry()
  log = new.env()
  log$n = 0L
  hook_add("session_before_compact", function(event, ctx) log$n = log$n + 1L)
  hook_add("session_before_compact", function(event, ctx) list())
  hook_add("session_before_compact", function(event, ctx) list(cancel = TRUE))
  res = ev_dispatch("session_before_compact", list(reason = "manual", tokens = 10))
  expect_equal(res, list(cancel = TRUE))
  expect_equal(log$n, 1L)
  local_registry()
  hook_add("permission_request", function(event, ctx) "yes")
  expect_null(ev_dispatch("permission_request", list(tool = "r")))
})

test_that("tool_result patches content, details and is_error only", {
  local_registry()
  hook_add("tool_result", function(event, ctx) {
    list(content = list(list(type = "text", text = "[patched]")), status = "ignored")
  })
  hook_add("tool_result", function(event, ctx) {
    expect_equal(event$content[[1]]$text, "[patched]")
    list(is_error = TRUE)
  })
  res = ev_dispatch("tool_result", list(tool_name = "r", tool_call_id = "c1", input = list(),
                                        content = list(list(type = "text", text = "raw")),
                                        details = NULL, is_error = FALSE))
  expect_equal(res$content[[1]]$text, "[patched]")
  expect_true(res$is_error)
  expect_null(res$status)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "patch_ignored" & grepl("status", d$message)))
})

test_that("request_params patches only `params`; unset declared keys can be added (IC-69)", {
  local_registry()
  hook_add("request_params", function(event, ctx) {
    list(params = list(service_tier = "flex", metadata = list(team = "lab")), model = "other")
  })
  hook_add("request_params", function(event, ctx) {
    expect_equal(event$params$service_tier, "flex")
    list(params = "not a list")
  })
  # P06 sends only the declared keys that are set: here service_tier, not metadata
  res = ev_dispatch("request_params", list(provider = "openai", model = "gpt",
                                           params = list(service_tier = "auto")))
  expect_equal(res$params, list(service_tier = "flex", metadata = list(team = "lab")))
  expect_equal(res$model, "gpt")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "patch_ignored" & grepl("model", d$message, fixed = TRUE)))
  expect_true(any(d$class == "patch_ignored" & grepl("named list", d$message, fixed = TRUE)))
})

test_that("malformed parameter patch names cannot replace valid request parameters", {
  for (patch in list(stats::setNames(list("bad"), NA_character_),
                     stats::setNames(list("bad"), ""),
                     list(service_tier = "flex", service_tier = "hidden"))) {
    local_registry()
    hook_add("request_params", local({
      answer = patch
      function(event, ctx) list(params = answer)
    }))
    before = list(service_tier = "auto")
    expect_identical(ev_dispatch("request_params", list(params = before))$params, before)
    expect_true(any(gptr_registry(diagnostics = TRUE)$class == "patch_ignored"))
  }
})

test_that("document_write: lines patch, block stops, a throwing hook blocks", {
  local_registry()
  hook_add("document_write", function(event, ctx) list(lines = c(event$lines, "# footer")))
  res = ev_dispatch("document_write", list(path = "a.R", lines = "x = 1"))
  expect_false(res$block)
  expect_equal(res$lines, c("x = 1", "# footer"))
  hook_add("document_write", function(event, ctx) stop("disk policy bug"))
  res = ev_dispatch("document_write", list(path = "a.R", lines = "x = 1"))
  expect_true(res$block)
  expect_match(res$reason, "disk policy bug", fixed = TRUE)
})

test_that("sensitive hooks fail closed for ambiguous or malformed decisions", {
  cases = list(
    tool_call = list(list(decision = "allow", decision = "block"), list(reason = "stop"),
      list(decision = "modify", input = list("bad")),
      list(decision = "block", reason = new.env(parent = emptyenv()))),
    permission_request = list(list(decision = "allow", decision = "deny"),
      list(reason = "stop"), list(decision = NA_character_)),
    document_write = list(list(block = NA), list(block = "true"),
      list(block = FALSE, block = TRUE), list(lines = 1)))
  for (event in names(cases)) {
    for (answer in cases[[event]]) {
      local_registry()
      hook_add(event, local({
        result = answer
        function(event, ctx) result
      }))
      result = ev_dispatch(event, list(input = list(code = "1"), lines = "old"))
      if (identical(event, "document_write")) {
        expect_true(result$block)
        expect_identical(result$lines, "old")
      } else {
        expect_identical(result$decision, if (event == "tool_call") "block" else "deny")
      }
      expect_gt(nrow(gptr_registry(diagnostics = TRUE)), 0L)
    }
  }
})

test_that("policy decisions reject duplicate fields and malformed reasons or inputs", {
  local_registry()
  for (answer in list(list(decision = "allow", decision = "deny"),
                       list(decision = "deny", reason = new.env(parent = emptyenv())),
                       list(decision = "modify", input = list("bad")))) {
    policy = gptr_policy("guard", local({
      result = answer
      function(call, ctx) result
    }))
    expect_identical(ext_policy_decide(policy, list(input = list(code = "1")))$decision, "deny")
  }
})

test_that("malformed tool result patch fields are ignored with diagnostics", {
  local_registry()
  hook_add("tool_result", function(event, ctx) {
    list(is_error = list(TRUE), details = list("bad"), content = 1)
  })
  original = list(is_error = FALSE, details = list(note = "good"), content = list(block_text("x")))
  expect_identical(ev_dispatch("tool_result", original), original)
  expect_equal(sum(gptr_registry(diagnostics = TRUE)$class == "patch_ignored"), 3L)
})

test_that("replay preservation cannot exempt arbitrary user fields from redaction", {
  local_registry()
  old = the$redactor
  withr::defer(assign("redactor", old, envir = the))
  redactor_set(function(x, profile = "persist") gsub("CANARY", "[redacted]", x, fixed = TRUE))
  user = list(json = "CANARY", signature = "CANARY", plain = "CANARY",
              nested = list(type = "opaque", json = "CANARY"))
  payload = list(input = user, details = user, params = user, headers = user,
    settings = user, env = user,
    message = list(content = list(block_text("CANARY", signature = "CANARY"),
      block_thinking("CANARY", signature = "CANARY", redacted = TRUE, data = "CANARY"),
      block_opaque("p", "a", "m", "CANARY"),
      block_tool_call("c1", "r", user, thought_signature = "CANARY"))))
  result = ev_redact_payload(payload)
  for (field in c("input", "details", "params", "headers", "settings", "env")) {
    expect_identical(result[[field]]$json, "[redacted]")
    expect_identical(result[[field]]$signature, "[redacted]")
    expect_identical(result[[field]]$nested$json, "[redacted]")
  }
  blocks = result$message$content
  expect_identical(blocks[[1]]$text, "[redacted]")
  expect_identical(blocks[[1]]$signature, "CANARY")
  expect_identical(blocks[[2]]$thinking, "[redacted]")
  expect_identical(blocks[[2]]$signature, "CANARY")
  expect_identical(blocks[[2]]$data, "CANARY")
  expect_identical(blocks[[3]]$json, "CANARY")
  expect_identical(blocks[[4]]$thought_signature, "CANARY")
  expect_identical(blocks[[4]]$arguments$signature, "[redacted]")
})

test_that("matchers filter by tool-name glob or predicate", {
  local_registry()
  log = new.env()
  log$n = 0L
  hook_add("tool_execution_start", function(event, ctx) log$n = log$n + 1L, matcher = "mcp__*")
  hook_add("tool_execution_start", function(event, ctx) log$n = log$n + 10L,
           matcher = function(event) identical(event$tool_name, "r"))
  ev_dispatch("tool_execution_start", list(tool_name = "mcp__github__search", tool_call_id = "1"))
  ev_dispatch("tool_execution_start", list(tool_name = "r", tool_call_id = "2"))
  ev_dispatch("tool_execution_start", list(tool_name = "read", tool_call_id = "3"))
  expect_equal(log$n, 11L)
})

test_that("handlers see a stream-redacted copy with type and ts; opaque fields untouched", {
  local_registry()
  old = the$redactor
  withr::defer(assign("redactor", old, envir = the))
  redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  log = new.env()
  hook_add("message_end", function(event, ctx) log$ev = event)
  content = list(
    list(type = "text", text = "key sk-abc123"),
    list(type = "thinking", thinking = "t", signature = "sk-keepme1", redacted = TRUE,
         data = "sk-keepme2")
  )
  msg = list(role = "assistant", content = content)
  ev_dispatch("message_end", list(type = "message_end", role = "assistant", message = msg),
              session = "s9")
  expect_equal(log$ev$type, "message_end")
  expect_equal(names(log$ev)[[1]], "type")
  expect_equal(log$ev$session, "s9")
  expect_true(is.numeric(log$ev$ts))
  expect_equal(log$ev$message$content[[1]]$text, "key [secret:KEY]")
  expect_equal(log$ev$message$content[[2]]$signature, "sk-keepme1")
  expect_equal(log$ev$message$content[[2]]$data, "sk-keepme2")
})

test_that("handlers run with ctx attributed to their source; channels reach listeners", {
  local_registry()
  log = new.env()
  hook_add("myplugin:done", function(event, ctx) {
    log$data = event$data
    log$source = ctx_source(ctx)
  }, rank = 5L, source = "plugin:listener")
  ctx = ctx_new(NULL)
  ctx$emit("myplugin:done", list(n = 3L))
  expect_equal(log$data, list(n = 3L))
  expect_equal(log$source, "plugin:listener")
  expect_null(ctx_source(ctx))
  expect_error(ctx$emit("not a channel", 1), class = "gptr_error_invalid_argument")
})

test_that("session_shutdown drops the session's records after its handlers ran (IC-69)", {
  local_registry()
  log = new.env()
  hook_add("session_shutdown", function(event, ctx) log$reason = event$reason, rank = 0L,
           source = "session", session = "s1")
  registry_add(gptr_command("mine", function(args, ctx) "x"), source = "session", rank = 0L,
               session = "s1")
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
  ev_dispatch("session_shutdown", list(reason = "gc"), session = "s1")
  expect_equal(log$reason, "gc")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_length(get0("session_shutdown", envir = registry_env()$hooks), 0L)
})

test_that("runs and executing tools are tracked from agent and tool events (IC-53)", {
  reg = local_registry()
  ev_dispatch("agent_start", list(run = "u1"))
  ev_dispatch("agent_start", list(run = "u2"))
  expect_setequal(reg$runs, c("u1", "u2"))
  ev_dispatch("tool_execution_start", list(run = "u1", tool_call_id = "c1", tool_name = "r"))
  expect_error(gptr_register(gptr_command("x", function(args, ctx) NULL)),
               class = "gptr_error_permission")
  ev_dispatch("tool_execution_end", list(run = "u1", tool_call_id = "c1", tool_name = "r"))
  expect_length(reg$executing, 0L)
  ev_dispatch("tool_execution_start", list(run = "u2", tool_call_id = "c2", tool_name = "r"))
  ext_control_grant("u2", "gptr_reload")
  ev_dispatch("agent_end", list(run = "u2", status = "aborted"))
  expect_length(reg$executing, 0L)
  expect_length(reg$grants, 0L)
  expect_equal(reg$runs, "u1")
})

test_that("an unused control grant ends with the top-level call it was granted in (IC-53)", {
  reg = local_registry()
  ev_dispatch("agent_start", list(run = "u3"))
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c3", tool_name = "r"))
  ext_control_grant("u3", "gptr_register")
  # a nested call (id "<outer>/<k>") ends inside the approved call and keeps the grant
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c3/1", tool_name = "read"))
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c3/1", tool_name = "read"))
  expect_length(reg$grants, 1L)
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c3", tool_name = "r"))
  expect_length(reg$grants, 0L)
  # a later, unapproved call of the same run cannot use the approval
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c4", tool_name = "r"))
  err = expect_error(ext_control_guard("gptr_register"), class = "gptr_error_permission")
  expect_equal(err$action, "gptr_register")
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c4", tool_name = "r"))
  ev_dispatch("agent_end", list(run = "u3", status = "done"))
  expect_length(reg$runs, 0L)
})

test_that("hook_add validates names; hook_remove removes", {
  local_registry()
  expect_error(hook_add("PreToolUse", function(event, ctx) NULL),
               class = "gptr_error_invalid_argument")
  id = hook_add("turn_start", function(event, ctx) NULL)
  expect_true(hook_remove(id))
  expect_false(hook_remove(id))
})

test_that("a throwing policy denies; malformed answers deny; NULL or no decision has no opinion", {
  local_registry()
  call = list(id = "c1", name = "r", input = list(code = "1"))
  bad = gptr_policy("buggy", function(call, ctx) stop("policy bug"))
  res = ext_policy_decide(bad, call)
  expect_equal(res$decision, "deny")
  expect_match(res$reason, "policy 'buggy' failed: policy bug", fixed = TRUE)
  expect_true(any(gptr_registry(diagnostics = TRUE)$source == "policy:buggy"))
  expect_equal(ext_policy_decide(gptr_policy("odd", function(call, ctx) "yes"), call)$decision,
               "deny")
  expect_null(ext_policy_decide(gptr_policy("quiet", function(call, ctx) NULL), call))
  # D-030 item 4: a list without `decision` has no opinion, as in P06's perm_policies()
  expect_null(ext_policy_decide(gptr_policy("aside", function(call, ctx) list(reason = "n/a")),
                                call))
  mod = gptr_policy("mod", function(call, ctx) list(decision = "modify", input = list(code = "2")))
  expect_equal(ext_policy_decide(mod, call)$input, list(code = "2"))
  ok = gptr_policy("ok", function(call, ctx) list(decision = "allow"))
  expect_equal(ext_policy_decide(ok, call), list(decision = "allow", reason = "",
                                                 input = list(code = "1")))
  # IC-53 item 6: the ask_human tier of the guards is a well-formed answer, kept unchanged
  human = gptr_policy("human", function(call, ctx) {
    list(decision = "ask_human", reason = "control")
  })
  expect_equal(ext_policy_decide(human, call), list(decision = "ask_human", reason = "control",
                                                    input = list(code = "1")))
})
