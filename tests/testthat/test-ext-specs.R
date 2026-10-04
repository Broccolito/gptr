local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("classifier callback validation keeps the IC-74 and chat signatures separate", {
  local_registry()
  build = function(model, state, questions, opts) NULL
  parse = function(model, status, headers, body, questions) NULL
  cls = gptr_spec("adapter", "native", transport = "http_json",
                 classify = list(build = build, parse = parse))
  expect_identical(cls$classify$parse, parse)
  chat_parse = function(model, opts) NULL
  chat = gptr_spec("adapter", "chat", transport = "http_sse",
                  build = function(model, context, opts) NULL, parse = chat_parse,
                  capabilities = list(operator_role = "user", request_params = "metadata"))
  expect_identical(chat$parse, chat_parse)
  expect_identical(chat$capabilities$operator_role, "user")
  err = expect_error(gptr_spec("adapter", "old", transport = "http_json",
    classify = list(build = build, parse = function(model, status, headers, body) NULL)),
    class = "gptr_error_invalid_spec")
  expect_match(err$problem, "questions", fixed = TRUE)
  expect_error(gptr_spec("adapter", "old", transport = "http_json",
    classify = list(build = function(model, state) NULL, parse = parse)),
    class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("adapter", "old", transport = "inprocess",
    classify = list(run = function(model, state) NULL)), class = "gptr_error_invalid_spec")
  expect_s3_class(gptr_spec("adapter", "flex", transport = "http_json",
    classify = list(build = function(...) NULL, parse = function(...) NULL)), "gptr_adapter")
})

test_that("IC-74 model decision metadata is typed separately from capability flags", {
  local_registry()
  decision = list(types = c("noul", "choice", "score"), images = TRUE,
    server_min = "0.35.1", max_questions = 64L, max_options = 26L,
    max_request_bytes_text = 65536L, max_request_bytes_images = 33554432L, max_active = 1L)
  m = gptr_spec("model", "ollama/clef", type = "classifier", api = "ollama-system-one",
    capabilities = list(vision = TRUE, tool_addition = FALSE), decision = decision,
    digest = "sha256:abc123", server_version = "0.35.1", locality = "local")
  expect_identical(m$decision, decision)
  expect_identical(m$digest, "sha256:abc123")
  expect_identical(m$server_version, "0.35.1")
  expect_identical(m$locality, "local")
  expect_identical(m$capabilities, list(vision = TRUE, tool_addition = FALSE))
  expect_true(all(c("decision", "digest", "server_version", "locality") %in%
                    kind_get("model")$fields))
  expect_s3_class(gptr_spec("model", "corp/future", future_field = list(x = "kept")),
                 "gptr_model")
  invalid = list(
    list(decision = "decision"), list(digest = TRUE), list(server_version = 35.1),
    list(locality = "probably"), list(capabilities = list(version = "0.35.1")),
    list(capabilities = list(vision = NA)), list(decision = list(images = "yes")),
    list(decision = list(types = "chat")), list(decision = list(types = character())),
    list(decision = list(server_min = "latest")), list(decision = list(max_active = 0)),
    list(decision = list(max_options = 1.5)), list(decision = list(max_questions = Inf)),
    list(decision = list(max_request_bytes_images = NA_real_)),
    list(decision = list(max_request_bytes_text = -1)),
    list(decision = stats::setNames(list(TRUE), NA_character_))
  )
  for (fields in invalid) {
    expect_error(do.call(gptr_spec, c(list(kind = "model", name = "ollama/clef"), fields)),
                 class = "gptr_error_invalid_spec")
  }
  embedded = list(id = "clef", type = "classifier", api = "ollama-system-one",
                  decision = decision, locality = "local")
  provider = gptr_spec("provider", "ollama", api = "openai-completions",
                      models = list(embedded))
  expect_identical(provider$models[[1]]$decision, decision)
  embedded$decision$max_questions = "sixty-four"
  expect_error(gptr_spec("provider", "ollama", api = "openai-completions",
                         models = list(embedded)), class = "gptr_error_invalid_spec")
})

test_that("spec numeric and named-list boundaries fail with typed errors", {
  local_registry()
  for (n in c(Inf, NaN, .Machine$integer.max + 1)) {
    expect_error(gptr_spec("context_block", "x", provide = function(ctx, budget) "x", order = n),
                 class = "gptr_error_invalid_spec")
  }
  for (caps in list(stats::setNames(list(TRUE), NA_character_),
                    stats::setNames(list(TRUE, FALSE), c("vision", "vision")))) {
    expect_error(gptr_spec("model", "corp/m", capabilities = caps),
                 class = "gptr_error_invalid_spec")
  }
})

test_that("callbacks accept the supplied positional arguments without missing required extras", {
  local_registry()
  build = function(model, state, questions, opts) NULL
  bad = list(function(a, b, c, d, e, mandatory) NULL,
             function(a, ..., mandatory) NULL, function(a, b, c, d) NULL)
  for (parse in bad) {
    expect_error(gptr_spec("adapter", "native", transport = "http_json",
      classify = list(build = build, parse = parse)), class = "gptr_error_invalid_spec")
  }
  for (parse in list(function(a, b, c, d, e, optional = NULL) NULL,
                      function(a, ..., optional = NULL) NULL)) {
    expect_s3_class(gptr_spec("adapter", "native", transport = "http_json",
      classify = list(build = build, parse = parse)), "gptr_adapter")
  }
})

test_that("UI selection fails closed for malformed index values", {
  for (value in list(1.9, TRUE, "1", NA_integer_, Inf, c(1L, 2L), list(1L))) {
    select = local({
      answer = value
      function(...) answer
    })
    expect_identical(spec_ui_permission(select)(list(tool = "r"))$decision, "deny")
  }
  expect_identical(spec_ui_permission(function(...) 1L)(list(tool = "r"))$decision, "allow")
})

test_that("generated member formals cannot be overwritten by implementation scratch names", {
  # Isolated unit boundary: the real Task 3/7 integration runs when those owners exist.
  scope = new.env(parent = environment(spec_tool_fun))
  scope$as_tool_result = identity
  scope$ctx_default = function(session) list(session = session)
  make_member = spec_tool_fun
  environment(make_member) = scope
  props = c("input", "nm", "v", "res", "name", "props", "run", "execute",
             "as_tool_result", "as.list", "environment", "all.names")
  parameters = list(type = "object", properties = stats::setNames(
    rep(list(list(type = "string")), length(props)), props), required = as.list(props))
  execute = function(input, ctx) list(is_error = FALSE, value = input)
  member = make_member(execute, parameters, "capture")
  values = stats::setNames(as.list(paste0("value_", props)), props)
  expect_identical(do.call(member, values), values)
  expect_identical(names(formals(member)), props)
})

test_that("top-level and embedded model records validate known fields and unique names", {
  local_registry()
  invalid = list(list(id = "m", type = TRUE), list(id = "m", api = 1L),
                 list(id = "m", context = "unlimited"), list(id = "m", local = "yes"),
                 list(id = "m", digest = "ok", digest = TRUE), data.frame(id = "m"))
  for (model in invalid) {
    expect_error(gptr_spec("provider", "corp", api = "chat", models = list(model)),
                 class = "gptr_error_invalid_spec")
  }
  raw = list(kind = "model", name = "corp/m", TRUE)
  names(raw)[3] = NA_character_
  expect_error(spec_finish(raw, kind_get("model")), class = "gptr_error_invalid_spec")
})

test_that("a scratch registry can be swapped in and out; the fields of `the` follow it", {
  before = registry_env()
  reg = local_registry()
  expect_s3_class(reg, "gptr_registry_env")
  expect_false(identical(reg, before))
  expect_identical(the$registry, reg)
  expect_identical(the$kinds, reg$kinds)
  expect_identical(the$hooks, reg$hooks)
  expect_identical(the$diagnostics, reg$diag)
  expect_equal(reg$generation, 1L)
})

test_that("ext_session_id() accepts ids, session-like objects and NULL", {
  expect_null(ext_session_id(NULL))
  expect_equal(ext_session_id("s123"), "s123")
  e = new.env()
  e$id = "s456"
  expect_equal(ext_session_id(e), "s456")
  expect_null(ext_session_id(42))
  expect_null(ext_session_id(NA_character_))
})

test_that("the kind table holds the 37 kinds of contract 10.2 (interpreter is P22's)", {
  local_registry()
  kinds = c("adapter", "agent", "artifact_type", "backend", "cache_policy", "checkpointer",
            "child_env", "command", "compactor", "context_block", "doc_format", "env_alias",
            "estimator", "evaluator", "frontend", "hook", "kind", "mcp_server", "model", "policy",
            "preset", "prompt_section", "prompt_template", "provider", "redaction_rule",
            "renderer", "risk_rule", "route", "router", "search_source", "secret_source",
            "service", "setting", "skill", "store", "tool", "ui")
  expect_equal(kind_names(), kinds)
  all_kinds = kinds[vapply(kinds, function(k) kind_get(k)$resolve == "all", NA)]
  expect_setequal(all_kinds, c("checkpointer", "context_block", "env_alias", "hook", "policy",
                               "prompt_section", "redaction_rule", "risk_rule", "route",
                               "search_source", "secret_source"))
  expect_equal(kind_get("policy")$order_field, "order")
  expect_equal(kind_get("route")$order_field, "order")
  expect_equal(kind_get("context_block")$order_field, "order")
  expect_null(kind_get("hook")$order_field)
  exp = kinds[vapply(kinds, function(k) isTRUE(kind_get(k)$experimental), NA)]
  expect_setequal(exp, c("artifact_type", "checkpointer", "evaluator", "frontend", "renderer",
                         "route", "search_source", "service", "store"))
})

test_that("gptr_spec() builds a classed spec carrying api_version", {
  local_registry()
  s = gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
  expect_s3_class(s, c("gptr_env_alias", "gptr_spec"), exact = TRUE)
  expect_equal(s$kind, "env_alias")
  expect_equal(s$api_version, "1.0")
  expect_equal(s$aliases, "slack-token")
  err = expect_error(gptr_spec("widget", "w"), class = "gptr_error_unknown_kind")
  expect_s3_class(err, "gptr_error_invalid_spec")
  expect_equal(err$kind, "widget")
  expect_error(gptr_spec(1, "w"), class = "gptr_error_invalid_argument")
})

test_that("validators name the failing field and accept unknown fields", {
  local_registry()
  err = expect_error(gptr_spec("router", "r1", route = "not a function"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "route")
  expect_equal(err$kind, "router")
  expect_equal(err$name, "r1")
  err = expect_error(gptr_spec("router", "r1"), class = "gptr_error_invalid_spec")
  expect_equal(err$problem, "is required")
  err = expect_error(gptr_spec("policy", "p", check = function(call) NULL),
                     class = "gptr_error_invalid_spec")
  expect_match(err$problem, "accepting (call, ctx)", fixed = TRUE)
  expect_equal(gptr_spec("command", "x", handler = function(args, ctx) NULL, colour = "b")$colour,
               "b")
  expect_error(gptr_spec("command", "x", handler = function(args, ctx) NULL, name = "y"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "", handler = function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "x", function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
})

test_that("defaults are filled and whole numbers become integers", {
  local_registry()
  b = gptr_spec("context_block", "lab", provide = function(ctx, budget) "x", order = 700)
  expect_equal(b$placement, "turn")
  expect_equal(b$authority, "data")
  expect_identical(b$budget, 300L)
  expect_identical(b$order, 700L)
  expect_error(gptr_spec("context_block", "lab", provide = function(ctx, budget) "x",
                         order = 7.5), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("policy", "p", check = function(call, ctx) NULL)$order, 500L)
  expect_equal(gptr_spec("prompt_section", "s", text = "x")$tier, "T0")
  expect_equal(gptr_spec("router", "r", route = function(request, ctx) "m")$timeout, 2)
})

test_that("provider specs: id rules, and the fake provider of P01 validates", {
  local_registry()
  p = gptr_spec("provider", "corp", api = "openai-completions")
  expect_equal(p$id, "corp")
  expect_equal(p$type, "chat")
  expect_false(p$offline)
  expect_false(p$local)
  err = expect_error(gptr_spec("provider", "Bad_Name", api = "x"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "id")
  expect_error(gptr_spec("provider", "corp", api = "x", models = list(list(context = 1))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("provider", "corp", api = "x", rate = list(rpm = 1)),
               class = "gptr_error_invalid_spec")
  fake = spec_finish(gptr_fake_provider(list("hi")), kind_get("provider"))
  expect_s3_class(fake, "gptr_provider")
  expect_true(fake$offline)
})

test_that("adapter specs are validated per transport (IC-35)", {
  local_registry()
  expect_error(gptr_spec("adapter", "wire", transport = "http_sse",
                         build = function(model, context, opts) NULL),
               class = "gptr_error_invalid_spec")
  a = gptr_spec("adapter", "wire", transport = "http_sse",
                build = function(model, context, opts) NULL, parse = function(model, opts) NULL)
  expect_equal(a$api, "wire")
  err = expect_error(gptr_spec("adapter", "gen", transport = "inprocess"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "stream")
  cls = gptr_spec("adapter", "cls", transport = "inprocess",
                  classify = list(run = function(model, state, questions, opts) NULL))
  expect_true(is.function(cls$classify$run))
  err = expect_error(gptr_spec("adapter", "cls", transport = "http_json",
                               classify = list(build = function(...) NULL)),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "classify")
  expect_error(gptr_spec("adapter", "x", api = "y", transport = "inprocess",
                         stream = function(model, context, opts) NULL),
               class = "gptr_error_invalid_spec")
})

test_that("model specs are keyed provider/id", {
  local_registry()
  m = gptr_spec("model", "corp/corp-large", context = 128000, release_date = NA_character_)
  expect_equal(m$provider, "corp")
  expect_equal(m$id, "corp-large")
  expect_equal(m$ref, "corp/corp-large")
  expect_error(gptr_spec("model", "corp-large"), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("model", "corp/a", id = "b"), class = "gptr_error_invalid_spec")
})

test_that("hook specs accept catalogued events and plugin channels only", {
  local_registry()
  expect_equal(gptr_spec("hook", "tool_result", event = "tool_result",
                         handler = function(event, ctx) NULL)$event, "tool_result")
  expect_equal(gptr_spec("hook", "x:y", event = "x:y", handler = function(event, ctx) NULL)$event,
               "x:y")
  err = expect_error(gptr_spec("hook", "PreToolUse", event = "PreToolUse",
                               handler = function(event, ctx) NULL),
                     class = "gptr_error_invalid_spec")
  expect_match(err$problem, "tool_call", fixed = TRUE)
})

test_that("tool specs: name rule, execute or fun, schema from formals, fun matching the schema", {
  local_registry()
  expect_error(gptr_spec("tool", "bad name", description = "d",
                         execute = function(input, ctx) NULL), class = "gptr_error_invalid_spec")
  err = expect_error(gptr_spec("tool", "t", description = "d"), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "execute")
  t = gptr_spec("tool", "paste2", description = "Paste two strings", exposure = "r",
                fun = function(a, b = "x") paste(a, b))
  expect_equal(t$parameters$properties, list(a = list(type = "string"), b = list(type = "string")))
  expect_equal(as.character(t$parameters$required), "a")
  expect_null(t$execute)
  expect_error(gptr_spec("tool", "t2", description = "d", fun = function(x) x,
                         parameters = list(type = "object", properties = list(y = list()))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t3", description = "d", fun = function(x, y) x,
                         parameters = list(type = "object", properties = list(x = list()))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t4", description = "d", fun = function(x) x,
                         parameters = list(type = "array")), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t5", description = "d", fun = function(x) x,
                         namespace = "1bad"), class = "gptr_error_invalid_spec")
  a = gptr_spec("tool", "look", description = "d", execute = function(input, ctx) "x",
                annotations = list(readOnlyHint = TRUE))
  expect_true(a$annotations$read_only)
  expect_equal(a$exposure, "direct")
  expect_equal(a$execution, "sequential")
  expect_true(a$record)
  dyn = gptr_spec("tool", "dyn", description = "d", execute = function(input, ctx) "x",
                  parameters = function(ctx) list(type = "object"))
  expect_true(is.function(dyn$parameters))
})

test_that("kind-specific rules: skill, command, setting, redaction, alias, risk, ui, preset", {
  local_registry()
  expect_error(gptr_spec("skill", "Bad", description = "d"), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("skill", "ok", description = strrep("x", 1025L)),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "/rows", handler = function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("setting", "Panel Size", default = 3L), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("setting", "panel.size", default = 3L)$scope, "both")
  expect_error(gptr_spec("redaction_rule", "anything", pattern = ".*", marker = "X"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("redaction_rule", "broken", pattern = "(", marker = "X"),
               class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("redaction_rule", "mrn", pattern = "MRN[0-9]{8}", marker = "MRN")$profiles,
               c("persist", "context", "stream", "code", "user_data"))
  expect_error(gptr_spec("env_alias", "JEV", aliases = character()),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("child_env", "strict", drop = "("), class = "gptr_error_invalid_spec")
  rows = data.frame(package = "pkg", `function` = "f", level = 3L, check.names = FALSE)
  expect_equal(gptr_spec("risk_rule", "mine", rows = rows)$target, "function")
  rows$level = 7L
  expect_error(gptr_spec("risk_rule", "mine", rows = rows), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("risk_rule", "cmds", target = "command",
                         rows = data.frame(package = "x", level = 1L)),
               class = "gptr_error_invalid_spec")
  ui = gptr_spec("ui", "yes", has_ui = function() TRUE, select = function(title, choices, ...) 1L)
  expect_equal(ui$permission(list(tool = "r"))$decision, "allow")
  expect_true(is.na(ui$input("Name?")))
  expect_true(ui$questions(list())$cancelled)
  no = gptr_spec("ui", "broken", has_ui = function() TRUE,
                 select = function(title, choices, ...) stop("dialog crashed"))
  expect_equal(no$permission(list(tool = "r"))$decision, "deny")
  expect_equal(gptr_spec("preset", "tiny", tools = c("read", "r"))$preamble, "standard")
  expect_error(gptr_spec("preset", "odd", tools = function(human) "r"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("mcp_server", "old", url = "https://x", type = "sse"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("mcp_server", "none"), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("mcp_server", "off", enabled = FALSE)$enabled, FALSE)
})

test_that("plugin kinds: kind_define() and validators that throw", {
  local_registry()
  kind_define("reviewer", validate = function(spec) spec, resolve = "all", source = "plugin:p")
  expect_true("reviewer" %in% kind_names())
  expect_equal(gptr_spec("reviewer", "stats", focus = "statistics")$focus, "statistics")
  expect_error(kind_define("reviewer", validate = identity, source = "plugin:other"),
               class = "gptr_error_invalid_spec")
  expect_error(kind_define("Bad Kind", validate = identity), class = "gptr_error_invalid_argument")
  kind_define("strict", validate = kind_user_validate(function(spec) stop("no")),
              source = "plugin:p")
  err = expect_error(gptr_spec("strict", "a"), class = "gptr_error_invalid_spec")
  expect_match(err$problem, "no", fixed = TRUE)
  kind_define("lazy_bad", validate = kind_user_validate(function(spec) "not a list"),
              source = "plugin:p")
  expect_error(gptr_spec("lazy_bad", "a"), class = "gptr_error_invalid_spec")
})

test_that("format() shows fields and never function bodies", {
  local_registry()
  s = gptr_spec("command", "hello", handler = function(args, ctx) "secret-body-text",
                description = "Say hi")
  out = format(s)
  expect_equal(out[[1]], "<gptr_command hello>")
  expect_true("  handler: <fn>" %in% out)
  expect_true("  description: Say hi" %in% out)
  expect_false(any(grepl("secret-body-text", out, fixed = TRUE)))
  expect_output(print(s), "<gptr_command hello>", fixed = TRUE)
})
