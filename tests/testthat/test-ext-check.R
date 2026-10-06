test_that("tool conformance distinguishes handler errors from malformed results", {
  local_registry()
  bad = gptr_tool("bad", "Malformed result", execute = function(input, ctx) 42)
  result = gptr_check(bad)
  expect_false(result$ok[result$check == "tool.empty_input"])
  rejected = gptr_tool("reject", "Typed rejection", execute = function(input, ctx) {
    gptr_abort("Input is required", "invalid_argument", arg = "input", expected = "input")
  })
  result = gptr_check(rejected)
  expect_true(result$ok[result$check == "tool.empty_input"])
})

test_that("factory checks count only the current invocation's records", {
  local_registry()
  registry_add(gptr_command("borrowed", function(args, ctx) "x"), "plugin:gptr-check", 5L)
  result = gptr_check(function(gptr) NULL)
  expect_false(result$ok[result$check == "factory.registers"])
  rows = check_in_scratch(function() {
    check_factory(function(gptr) NULL,
                  manifest = list(extension = list(provides = list(command = "borrowed"))))
  })
  result = check_rows(rows)
  expect_false(result$ok[result$check == "provides.command:borrowed"])
})

test_that("nested factories cannot satisfy the checked outer factory's declarations", {
  local_registry()
  nested = function(gptr) {
    ext_load(function(inner) {
      inner$register(gptr_command("nested", function(args, ctx) NULL))
    }, gptr$name, 5L)
  }
  result = gptr_check(nested)
  expect_false(result$ok[result$check == "factory.registers"])
  result = check_rows(check_in_scratch(function() {
    check_factory(nested, list(extension = list(provides = list(command = "nested"))))
  }))
  expect_false(result$ok[result$check == "provides.command:nested"])
})

test_that("policy matrix has exclusive synthetic kernel precedence", {
  local_registry()
  registry_add(gptr_spec("service", "ctx.kernel", fun = function() {
    list(mode = function(ctx) "outside")
  }), "user", 0L)
  seen = new.env(parent = emptyenv())
  seen$modes = character()
  policy = gptr_policy("modes", function(call, ctx) {
    seen$modes = c(seen$modes, ctx$mode())
    NULL
  })
  result = gptr_check(policy)
  expect_true(result$ok[result$check == "policy.matrix"])
  expect_setequal(unique(seen$modes), c("plan", "manual", "edits", "auto"))
  expect_identical(ctx_new(NULL)$mode(), "outside")
})

test_that("unavailable process observation cannot pass conformance", {
  local_registry()
  local_mocked_bindings(check_children = function() simpleError("enumeration denied"))
  backend = gptr_backend("probe", start = function(spec, ctx) NULL,
                         cancel = function(handle) NULL)
  result = gptr_check(backend)
  expect_false(result$ok[result$check == "backend.processes"])
  result = gptr_check(function(gptr) {
    gptr$register(gptr_command("probe", function(args, ctx) NULL))
  })
  expect_false(result$ok[result$check == "factory.no_action"])
})

test_that("package manifests cannot omit or malform a declared factory", {
  local_registry()
  root = withr::local_tempdir()
  dir.create(file.path(root, "gptr"))
  local_mocked_bindings(
    ext_pkg_path = function(pkg, ...) if (length(list(...))) file.path(root, ...) else root,
    ext_pkg_objects = function(pkg) list(),
    ext_pkg_description = function(pkg, field) NA_character_)
  for (extension in list(list(provides = list(tool = "missing")), "bad", list(entry = 42))) {
    man = list(name = "probe", gptr = list(api = "1.0"), extension = extension)
    writeLines(json_encode(man), file.path(root, "gptr", "plugin.json"))
    result = gptr_check("probe")
    expect_false(all(result$ok))
  }
})

test_that("package entries resolve the declared exported function exactly", {
  local_registry()
  root = withr::local_tempdir()
  dir.create(file.path(root, "gptr"))
  seen = new.env(parent = emptyenv())
  seen$target = NULL
  local_mocked_bindings(
    ext_pkg_path = function(pkg, ...) if (length(list(...))) file.path(root, ...) else root,
    ext_pkg_objects = function(pkg) list(),
    ext_pkg_description = function(pkg, field) NA_character_,
    ext_pkg_factory = function(pkg, fun) {
      seen$target = c(pkg, fun)
      function(gptr) gptr$register(gptr_command("entry", function(args, ctx) NULL))
    })
  for (entry in c("factory", "probe:::factory", "::factory", "probe::", "probe::factory::x")) {
    man = list(name = "probe", gptr = list(api = "1.0"), extension = list(entry = entry))
    writeLines(json_encode(man), file.path(root, "gptr", "plugin.json"))
    result = gptr_check("probe")
    expect_false(result$ok[result$check == "manifest.valid"])
    expect_null(seen$target)
  }
  man = list(name = "probe", gptr = list(api = "1.0"),
              extension = list(entry = "provider::factory"))
  writeLines(json_encode(man), file.path(root, "gptr", "plugin.json"))
  result = gptr_check("probe")
  expect_true(result$ok[result$check == "factory.exported"])
  expect_identical(seen$target, c("provider", "factory"))
})

test_that("conformance permits current captured API reads while keeping writes stale", {
  reg = local_registry()
  api = ext_api_new("plugin:reads")
  policy = gptr_policy("reads", function(call, ctx) {
    api$require("1.0") # nolint: object_usage_linter.
    if (api$has("kind.policy")) list(decision = "allow")
  })
  result = gptr_check(policy)
  expect_true(result$ok[result$check == "policy.matrix"])
  mutator = gptr_policy("writes", function(call, ctx) {
    api$register(gptr_command("escaped", function(args, ctx) NULL))
    NULL
  })
  result = gptr_check(mutator)
  expect_false(result$ok[result$check == "policy.matrix"])
  expect_null(registry_get("command", "escaped"))
  registry_swap(registry_scratch())
  expect_error(api$has("kind.policy"), class = "gptr_error_stale_api")
  registry_swap(reg)
  reg$generation = reg$generation + 1L
  result = gptr_check(policy)
  expect_false(result$ok[result$check == "policy.matrix"])
})

test_that("gptr_api() reports version 1.0 and the kind, event and named features", {
  local_registry()
  api = gptr_api()
  expect_s3_class(api, "gptr_api")
  expect_identical(api$version, package_version("1.0"))
  expect_true(all(paste0("kind.", kind_names()) %in% api$features))
  expect_true(all(paste0("event.", ev_catalogue()$event) %in% api$features))
  expect_true(all(c("lazy_activation", "declarations", "ctx.decide", "ctx.secret", "route",
                    "services") %in% api$features))
  expect_true("kind.router" %in% api$features)
  expect_false("kind.interpreter" %in% api$features)
  expect_output(print(api), "<gptr_api 1.0>", fixed = TRUE)
  kind_define("interpreter", validate = function(spec) spec, source = "builtin:bridges")
  expect_true("kind.interpreter" %in% gptr_api()$features)
})

test_that("a deprecated API member warns once, or errors for plugin CI (contract 10.9)", {
  local_registry()
  withr::defer(rm(list = grep("^warning:deprecated:", ls(the$once), value = TRUE),
                  envir = the$once))
  expect_false(ext_warn_deprecated("api", "register"))
  local_mocked_bindings(ext_deprecations = function() {
    list(api = list(has = list(since = "1.1", instead = "gptr$require()"),
                    require = list(since = "1.1", instead = "gptr$has()")),
         ctx = list())
  })
  api = ext_api_new("plugin:old")
  expect_warning(api$has("kind.tool"), class = "gptr_warning_deprecated")
  expect_no_warning(api$has("kind.tool"))
  withr::local_options(gptr.deprecations = "error")
  err = expect_error(api$require("1.0"), # nolint: object_usage_linter.
                     class = "gptr_error_deprecated")
  expect_match(conditionMessage(err), "gptr$require", fixed = TRUE)
})

# One valid spec of every kind P02 defines (contract 10.2 rows 1-5 and 7-38)
valid_specs = function() {
  empty_docs = data.frame(id = character(), text = character(), kind = character())
  risk_rows = data.frame(package = "pkg", `function` = "f", level = 1L, check.names = FALSE)
  list(
    gptr_provider("corp", api = "openai-completions"),
    gptr_adapter("wire", transport = "inprocess",
                 stream = function(model, context, opts) function() NULL),
    gptr_spec("model", "corp/corp-large", context = 128000),
    gptr_router("cheap", route = function(request, ctx) "corp/corp-large"),
    gptr_tool("add", "Add two numbers",
              parameters = list(type = "object", required = I(c("a", "b")),
                                properties = list(a = list(type = "number"),
                                                  b = list(type = "number"))),
              fun = function(a, b) a + b, exposure = "r", namespace = "demo"),
    gptr_spec("mcp_server", "files", command = "mcp-server-files", args = list("--root", ".")),
    gptr_spec("skill", "statistics", description = "Statistical review of analyses"),
    gptr_spec("prompt_template", "review", text = "Review $1"),
    gptr_command("hello", function(args, ctx) "hi"),
    gptr_hook("tool_result", function(event, ctx) NULL),
    gptr_policy("quiet", function(call, ctx) NULL),
    gptr_context_block("lab", function(ctx, budget) "Experiment 12"),
    gptr_prompt_section("rules", "Use SI units."),
    gptr_spec("compactor", "none", should = function(session, ctx) FALSE,
              compact = function(session, ctx) NULL),
    gptr_spec("cache_policy", "default", plan = function(parts, caps, session) list()),
    gptr_spec("estimator", "default", estimate = function(x, class) 1),
    gptr_spec("doc_format", "org", ext = "org", locate = function(text, site) list(),
              render = function(block, site) "",
              upsert = function(text, site, lines, block_id) text, inert = function(lines) lines),
    gptr_spec("artifact_type", "html", build = function(id, dir, data, ctx) NULL,
              check = function(dir, ctx) list(ok = TRUE), launch = function(version_dir, ctx) NULL,
              stop = function(handle) NULL),
    gptr_backend("echo", start = function(spec, ctx) NULL, cancel = function(handle) NULL),
    gptr_agent("stats", description = "Reviewer", model = "corp/corp-large"),
    gptr_spec("ui", "quiet", has_ui = function() FALSE,
              select = function(title, choices, ...) NA_integer_),
    gptr_spec("frontend", "echo", run = function(session, ...) session),
    gptr_spec("setting", "panel.size", default = 3L),
    gptr_spec("secret_source", "vault", resolve = function(name, ctx) NULL,
              list = function(ctx) character()),
    gptr_spec("redaction_rule", "mrn", pattern = "MRN[0-9]{8}", marker = "mrn"),
    gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token"),
    gptr_spec("child_env", "strict", base = "allowlist", keep = "PATH"),
    gptr_spec("checkpointer", "noop", scope = "other", before = function(call, ctx) NULL,
              after = function(call, ctx, token) NULL,
              undo = function(fragment, ctx, force) character(),
              redo = function(fragment, ctx, force) character()),
    gptr_spec("kind", "reviewer", validate = function(spec) spec),
    gptr_spec("route", "echo", order = 90, match = function(call) FALSE,
              run = function(call) NULL),
    gptr_spec("preset", "tiny", tools = c("read", "r")),
    gptr_spec("risk_rule", "mine", rows = risk_rows),
    gptr_spec("service", "p02.check", fun = function() NULL),
    gptr_spec("renderer", "panel.note", render = function(entry, width, ctx) "note"),
    gptr_spec("search_source", "corpus", docs = function(ctx) empty_docs),
    gptr_spec("store", "memory", open = function(...) NULL, append = function(...) NULL,
              read = function(...) list(), fork = function(...) NULL),
    gptr_spec("evaluator", "echo", eval = function(code, envir, ...) NULL)
  )
}

test_that("gptr_check() passes a valid spec of every kind (acceptance 3)", {
  local_registry()
  specs = valid_specs()
  expect_setequal(vapply(specs, function(s) s$kind, ""), kind_names())
  for (s in specs) {
    res = gptr_check(s)
    expect_s3_class(res, c("gptr_check", "data.frame"), exact = TRUE)
    expect_named(res, c("target", "check", "ok", "message"))
    timed = res$check == "policy.speed"
    expect_true(all(res$ok[!timed]), label = paste(s$kind, s$name))
    expect_equal(res$target[[1]], paste0(s$kind, ":", s$name))
  }
})

test_that("an invalid spec fails and names the failing field; error = TRUE signals", {
  local_registry()
  s = gptr_command("hello", function(args, ctx) "hi")
  s$handler = "not a function"
  res = gptr_check(s)
  row = res[res$check == "spec.fields", ]
  expect_false(row$ok)
  expect_match(row$message, "field 'handler'", fixed = TRUE)
  err = expect_error(gptr_check(s, error = TRUE), class = "gptr_error_conformance")
  expect_s3_class(err$results, "gptr_check")
  expect_false(gptr_check(list(kind = "command", name = "x"))$ok)
  u = s
  u$kind = "widget"
  expect_match(gptr_check(u)$message[[2]], "field 'kind'", fixed = TRUE)
  expect_error(gptr_check(42), class = "gptr_error_invalid_argument")
})

test_that("a direct tool description over 400 tokens fails (acceptance 3)", {
  local_registry()
  long = gptr_tool("long", paste(rep("word", 600), collapse = " "),
                   execute = function(input, ctx) "x")
  res = gptr_check(long)
  expect_false(res$ok[res$check == "tool.description_tokens"])
  short = gptr_tool("short", "A short description.", execute = function(input, ctx) "x")
  expect_true(all(gptr_check(short)$ok))
  member = gptr_tool("long_member", paste(rep("word", 600), collapse = " "),
                     fun = function() 1, exposure = "r", namespace = "demo")
  expect_false("tool.description_tokens" %in% gptr_check(member)$check)
})

test_that("tools: schema problems and empty-input handling are checked", {
  local_registry()
  bad_schema = gptr_tool("bad", "Bad schema",
                         parameters = list(type = "object",
                                           properties = list(a = list(type = "strng"))),
                         execute = function(input, ctx) "x")
  expect_false(gptr_check(bad_schema)$ok[gptr_check(bad_schema)$check == "tool.schema"])
  raw = gptr_tool("raw", "Fails on empty input", execute = function(input, ctx) stop("boom"))
  res = gptr_check(raw)
  expect_false(res$ok[res$check == "tool.empty_input"])
  expect_match(res$message[res$check == "tool.empty_input"], "boom", fixed = TRUE)
  classed = gptr_tool("classed", "Classed failure", execute = function(input, ctx) {
    gptr_abort("needs a path", "invalid_argument", arg = "path", expected = "a path")
  })
  expect_true(all(gptr_check(classed)$ok))
})

test_that("prompt sections must fit their budget", {
  local_registry()
  big = gptr_prompt_section("big", paste(rep("word", 500), collapse = " "), budget = 50L)
  res = gptr_check(big)
  expect_false(res$ok[res$check == "section.budget"])
  dyn = gptr_prompt_section("dyn", function(ctx) "x")
  expect_true(all(gptr_check(dyn)$ok))
})

test_that("policies are run over the modes x report 18 matrix", {
  local_registry()
  plan_guard = gptr_policy("plan_guard", function(call, ctx) {
    if (ctx$mode() == "plan" && call$risk$level > 0) list(decision = "deny", reason = "plan")
  })
  res = gptr_check(plan_guard)
  expect_true(all(res$ok[res$check != "policy.speed"]))
  expect_match(res$message[res$check == "policy.speed"], "^median [0-9.]+ ms$")
  expect_match(res$message[res$check == "policy.matrix"], "40 calls", fixed = TRUE)
  odd = gptr_policy("odd", function(call, ctx) list(decision = "maybe"))
  expect_false(gptr_check(odd)$ok[gptr_check(odd)$check == "policy.matrix"])
  # IC-53 item 6: the guards' ask_human tier (P11's mode and critical_guard) is well formed
  human = gptr_policy("human", function(call, ctx) {
    if (call$risk$level >= 4L) list(decision = "ask_human", reason = "level 4")
  })
  expect_true(gptr_check(human)$ok[gptr_check(human)$check == "policy.matrix"])
  thrower = gptr_policy("thrower", function(call, ctx) stop("policy bug"))
  res = gptr_check(thrower)
  expect_match(res$message[res$check == "policy.matrix"], "policy bug", fixed = TRUE)
})

test_that("backends: cancel must leave no child process", {
  skip_on_cran()
  local_registry()
  procs = new.env()
  start = function(spec, ctx) {
    p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"))
    procs$p = p
    list(proc = p)
  }
  withr::defer(if (!is.null(procs$p)) procs$p$kill())
  leaky = gptr_backend("leaky", start = start, cancel = function(handle) NULL)
  res = gptr_check(leaky)
  expect_false(res$ok[res$check == "backend.processes"])
  procs$p$kill()
  tidy = gptr_backend("tidy", start = start, cancel = function(handle) handle$proc$kill())
  expect_true(all(gptr_check(tidy)$ok))
})

test_that("adapters are replayed through the check.adapter service when it exists", {
  local_registry()
  # P12 registers check.adapter from on_load(); with the empty scratch registry every built-in
  # counts as active, so the "no service" case needs an empty bootstrap table in the full suite
  old = the$services
  withr::defer(assign("services", old, envir = the))
  assign("services", list(), envir = the)
  wire = gptr_adapter("wire", transport = "inprocess",
                      stream = function(model, context, opts) function() NULL)
  expect_equal(gptr_check(wire)$check, c("spec.class", "spec.fields"))
  ext_service_set("check.adapter", function(adapter, fixtures = NULL) {
    check_rows(list(check_row("adapter:wire", "adapter.golden_events", TRUE),
                    check_row("adapter:wire", "adapter.tool_choice", FALSE, "list tool_choice")))
  }, provided_by = "P12")
  res = gptr_check(wire)
  expect_equal(res$check, c("spec.class", "spec.fields", "adapter.golden_events",
                            "adapter.tool_choice"))
  expect_false(res$ok[[4]])
})

test_that("factories: load, register, no action at load, and every registered spec passes", {
  local_registry()
  res = gptr_check(function(gptr) {
    gptr$register(gptr_command("panel", function(args, ctx) "ok"))
    gptr$register(gptr_tool("long", paste(rep("word", 600), collapse = " "),
                            execute = function(input, ctx) "x"))
  })
  expect_true(all(res$ok[res$check %in% c("factory.load", "factory.registers",
                                          "factory.no_action")]))
  expect_true("command:panel" %in% res$target)
  expect_false(res$ok[res$target == "tool:long" & res$check == "tool.description_tokens"])
  expect_equal(nrow(gptr_registry()), 0L)
  broken = gptr_check(function(gptr) stop("factory bug"))
  expect_false(broken$ok[broken$check == "factory.load"])
  expect_match(broken$message[broken$check == "factory.load"], "factory bug", fixed = TRUE)
  empty = gptr_check(function(gptr) NULL)
  expect_false(empty$ok[empty$check == "factory.registers"])
  withr::defer(Sys.unsetenv("GPTR_P02_ACTION"))
  noisy = gptr_check(function(gptr) {
    Sys.setenv(GPTR_P02_ACTION = "1")
    gptr$register(gptr_command("x", function(args, ctx) NULL))
  })
  expect_false(noisy$ok[noisy$check == "factory.no_action"])
  expect_match(noisy$message[noisy$check == "factory.no_action"], "env", fixed = TRUE)
  withr::local_options(gptr.p02_action = NULL)
  optioned = gptr_check(function(gptr) {
    options(gptr.p02_action = TRUE)
    gptr$register(gptr_command("y", function(args, ctx) NULL))
  })
  expect_match(optioned$message[optioned$check == "factory.no_action"], "options", fixed = TRUE)
})

test_that("installed plugin packages: manifest, API, provides and bare identifiers (IC-42)", {
  local_registry()
  root = withr::local_tempdir()
  dir.create(file.path(root, "gptr"))
  decl = list(`trials/search` = list(signature = "search(condition: string)",
                                     description = "Search ClinicalTrials.gov"))
  provides = list(tool = list("trials/search"), command = list("panel", "missing"))
  man = list(name = "gptrpanel", version = "0.1.0", gptr = list(api = ">= 1.0, < 2"),
             extension = list(entry = "gptrpanel::gptr_plugin", activation = "lazy",
                              provides = provides, declarations = decl))
  writeLines(json_encode(man), file.path(root, "gptr", "plugin.json"))
  factory = function(gptr) {
    gptr$require(">= 1.0, < 2") # nolint: object_usage_linter.
    gptr$register(gptr_tool("search", "Search ClinicalTrials.gov for recruiting trials",
                            fun = function(condition) condition, exposure = "r",
                            namespace = "trials"))
    gptr$register(gptr_command("panel", function(args, ctx) "panel"))
  }
  objects = list(
    gptr_plugin = factory,
    panel_review = function(file) gptr::peter(paste("Review", file), model = opus),
    with_arg = function(m, file) peter(file, model = m, mode = "auto"),
    with_local = function(file) {
      judge = "jev"
      gptr_agent("judge", description = "Judge", model = judge)
    }
  )
  local_mocked_bindings(
    ext_pkg_path = function(pkg, ...) if (length(list(...))) file.path(root, ...) else root,
    ext_pkg_factory = function(pkg, fun) objects[[fun]],
    ext_pkg_objects = function(pkg) objects,
    ext_pkg_description = function(pkg, field) NA_character_
  )
  res = gptr_check("gptrpanel", tokens = TRUE)
  ok = stats::setNames(res$ok, res$check)
  expect_true(all(ok[c("package.installed", "manifest.present", "manifest.valid", "api.declared",
                       "api.satisfied", "factory.exported", "factory.load",
                       "provides.tool:trials/search", "provides.command:panel",
                       "tokens.declarations")]))
  expect_false(ok[["provides.command:missing"]])
  expect_false(ok[["code.identifiers"]])
  msg = res$message[res$check == "code.identifiers"]
  expect_match(msg, "panel_review: model = opus", fixed = TRUE)
  # peter() forces a local in its caller's frame; gptr_agent() stores it unevaluated (IC-34)
  expect_match(msg, "with_local: model = judge", fixed = TRUE)
  expect_false(grepl("with_arg", msg, fixed = TRUE))
  local_mocked_bindings(ext_pkg_path = function(pkg, ...) "")
  res = gptr_check("notinstalled")
  expect_equal(res$check, "package.installed")
  expect_false(res$ok)
})

test_that("tokens = TRUE reports declaration costs and the printed cost of examples", {
  local_registry()
  member = gptr_spec("tool", "rows", description = "Rows of a data frame.",
                     fun = function(n = "5") seq_len(as.integer(n)), exposure = "r",
                     namespace = "demo", output_tokens = 30L,
                     examples = list(list(n = "3"), list(n = "500")))
  res = gptr_check(member, tokens = TRUE)
  expect_true(res$ok[res$check == "tokens.declaration"])
  expect_true(res$ok[res$check == "tokens.example.1"])
  expect_false(res$ok[res$check == "tokens.example.2"])
  expect_match(res$message[res$check == "tokens.example.2"], "budget 30", fixed = TRUE)
})

test_that("gptr_check() output prints one line per check", {
  local_registry()
  res = gptr_check(gptr_command("hello", function(args, ctx) "hi"))
  expect_output(print(res), "<gptr_check> 2 check(s), 0 failed", fixed = TRUE)
  expect_output(print(res), "ok    command:hello  spec.fields", fixed = TRUE)
})

test_that("the contract 6.7 example passes", {
  local_registry()
  res = gptr_check(gptr_tool("add", "Add two numbers",
                             parameters = list(type = "object", required = I(c("a", "b")),
                                               properties = list(a = list(type = "number"),
                                                                 b = list(type = "number"))),
                             fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
  expect_true(all(res$ok))
})

test_that("checks see the live registry's records and services but never change them", {
  reg = local_registry()
  old = the$services
  withr::defer(assign("services", old, envir = the))
  ext_service_set("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    list(level = 0L)
  }, provided_by = "P11", builtin = "permissions")
  registry_add(gptr_policy("mode", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_tool("panel", "Panel", fun = function() 1, exposure = "r"), "user", 3L)
  registry_add(gptr_command("mine", function(args, ctx) "x"), "session", 0L, session = "s1")
  before = gptr_registry()
  uses_risk = gptr_policy("uses_risk", function(call, ctx) {
    ctx$risk(call$input$code %||% "")
    NULL
  })
  res = gptr_check(uses_risk)
  expect_true(res$ok[res$check == "policy.matrix"])
  clash = gptr_check(function(gptr) {
    gptr$register(gptr_tool("x", "X", fun = function() 1, exposure = "r", namespace = "panel"))
  })
  expect_false(clash$ok[clash$check == "factory.load"])
  expect_match(clash$message[clash$check == "factory.load"], "existing peter$ member",
               fixed = TRUE)
  expect_identical(gptr_registry(), before)
  expect_identical(registry_env(), reg)
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
})

test_that("a session finalized during a check keeps its deferred shutdown (D-085)", {
  reg = local_registry()
  seen = new.env(parent = emptyenv())
  seen$reasons = character()
  hook_add("session_shutdown", function(event, ctx) {
    seen$reasons = c(seen$reasons, event$reason)
    NULL
  })
  registry_add(gptr_command("mine", function(args, ctx) "x"), "session", 0L, session = "s1")
  gptr_check(function(gptr) {
    # what session_finalizer() does when a collection runs inside the scratch registry
    ev_defer("session_shutdown", list(reason = "gc"), session = "s1")
    gptr$register(gptr_command("probe", function(args, ctx) NULL))
  })
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_identical(seen$reasons, "gc")
  expect_length(ls(reg$deferred), 0L)
})

test_that("the identifier scan knows arrow assignments and for-loop variables (IC-42)", {
  arrowed = function(file) NULL
  body(arrowed) = call("{", call(ext_binding_heads[[2]], as.name("judge"), "jev"),
                       quote(peter(file, model = judge)))
  looped = function(files) {
    for (m in c("a", "b")) peter(files, model = m)
  }
  bare = function(file) gptr_agent("x", description = "d", skills = statistics)
  expect_equal(ext_bare_identifiers(list(arrowed = arrowed, looped = looped)), character())
  expect_equal(ext_bare_identifiers(list(bare = bare)), "bare: skills = statistics")
  stored = function(m) gptr_agent("x", description = "d", model = m, backend = m)
  valued = function(m) gptr_agent("x", description = "d", model = I(m))
  expect_equal(ext_bare_identifiers(list(stored = stored, valued = valued)), "stored: model = m")
})
