# S-11 conformance (plan P24; IC-73; REQ-41): a fixture plugin registers one record of every
# registry kind (the 38 of contract section 10.2) and every record is used at run time. Each
# function-valued field marks its kind in `s11$used` when gptr calls it; data kinds are marked
# when their effect is observed. The plugin loads once for this file (source plugin:s11fixture,
# rank 5) and is filtered out when the file ends.

s11 = new.env(parent = emptyenv())
s11$used = new.env(parent = emptyenv())
s11$requests = list()
s11$model_ids = character()
s11_mark = function(kind) assign(kind, TRUE, envir = s11$used)
s11_used = function(kind) isTRUE(get0(kind, envir = s11$used, inherits = FALSE))

s11_dir = tempfile("s11-")
dir.create(file.path(s11_dir, "skill"), recursive = TRUE)
s11_skill_md = file.path(s11_dir, "skill", "SKILL.md")
writeLines(c("---", "name: s11-skill", "description: S11 conformance skill.", "---",
             "S11 SKILL BODY"), s11_skill_md)

# The fake model behind the s11 adapter: a tool call when asked, else a text answer.
s11_reply = function(context) {
  msgs = context$messages
  last = msgs[[length(msgs)]]
  if (identical(last$role, "tool_result")) return(list(text = "s11 tool result seen"))
  text = msg_text(last)
  if (grepl("use the s11 tool", text, fixed = TRUE)) {
    return(list(tool = "s11_direct", input = json_obj()))
  }
  if (grepl("use r please", text, fixed = TRUE)) {
    return(list(tool = "r", input = list(code = "s11_x = 1")))
  }
  list(text = "s11 reply")
}

s11_stream = function(model, context, opts) {
  s11_mark("adapter")
  s11$requests[[length(s11$requests) + 1L]] = context
  s11$model_ids = c(s11$model_ids, model$id)
  n = length(s11$requests)
  st = new.env(parent = emptyenv())
  st$done = FALSE
  function() {
    if (st$done) return(NULL)
    st$done = TRUE
    r = s11_reply(context)
    start = ev_new("start", api = "s11-api", provider = "s11prov", model = model$id,
                   request_id = sprintf("q%012d", n), response_id = NULL)
    if (!is.null(r$tool)) {
      blk = block_tool_call(sprintf("s11call%d", n), r$tool, r$input)
      msg = msg_assistant(list(blk), api = "s11-api", provider = "s11prov", model = model$id,
                          usage = usage_new(input = 60, output = 8), stop_reason = "tool_use")
      evs = list(start, ev_new("toolcall_start", index = 1L, id = blk$id, name = blk$name),
                 ev_new("toolcall_end", index = 1L, block = blk))
    } else {
      blk = block_text(r$text)
      msg = msg_assistant(list(blk), api = "s11-api", provider = "s11prov", model = model$id,
                          usage = usage_new(input = 60, output = 4), stop_reason = "stop")
      evs = list(start, ev_new("text_start", index = 1L),
                 ev_new("text_delta", index = 1L, delta = r$text),
                 ev_new("text_end", index = 1L, block = blk))
    }
    done = ev_new("done", reason = msg$stop_reason, message = msg, usage = msg$usage)
    list(events = c(evs, list(done)), wait = 0)
  }
}

s11_model = function(id) {
  list(id = id, name = paste("S11", id), context = 200000, max_output = 4096, reasoning = FALSE,
       input = "text", tool_call = TRUE)
}

s11_store = function() registry_get("store", "jsonl")

# Every record of the fixture plugin except the MCP server (which needs a process, see below).
s11_specs = function() {
  list(
    gptr_provider("s11prov", api = "s11-api", models = list(s11_model("s11-model")), local = TRUE,
                  offline = TRUE),
    gptr_adapter("s11-api", transport = "inprocess", stream = s11_stream),
    gptr_spec("model", "s11prov/s11-extra", provider = "s11prov", id = "s11-extra",
              ref = "s11prov/s11-extra", api = "s11-api", type = "chat", context = 200000,
              max_output = 4096, reasoning = FALSE, input = "text", tool_call = TRUE),
    gptr_router("s11router", route = function(request, ctx) {
      s11_mark("router")
      "s11prov/s11-extra"
    }),
    gptr_tool("s11_direct", "S11 conformance tool.",
              parameters = list(type = "object", properties = json_obj()),
              execute = function(input, ctx) {
                s11_mark("tool")
                s11$tokens = ctx$tokens("abcd efgh")
                s11$handle = ctx$secret("S11_TOKEN")
                ctx$append_entry("note", list(text = "s11 note"))
                gptr_tool_result("s11 tool ran")
              }, exposure = "direct"),
    gptr_spec("interpreter", "s11interp", ext = ".s11r", programs = rscript_path(),
              args = function(path, args) c("--vanilla", path, args), windows_only = FALSE),
    gptr_spec("skill", "s11-skill", description = "S11 conformance skill.", path = s11_skill_md,
              dir = dirname(s11_skill_md), source = "plugin:s11fixture",
              disable_model_invocation = FALSE, allowed_tools = character(), tokens = 20),
    gptr_spec("prompt_template", "s11tmpl", text = "Say $1 politely", description = "S11 template",
              argument_hint = "<word>", source = "plugin:s11fixture"),
    gptr_command("s11cmd", function(args, ctx) {
      s11_mark("command")
      "s11 command ran"
    }, description = "S11 command"),
    gptr_hook("turn_end", function(event, ctx) {
      s11_mark("hook")
      NULL
    }),
    gptr_policy("s11policy", check = function(call, ctx) {
      s11_mark("policy")
      NULL
    }, description = "S11 policy"),
    gptr_context_block("s11block", provide = function(ctx, budget) {
      s11_mark("context_block")
      "s11 context"
    }, placement = "first", order = 660L),
    gptr_prompt_section("s11section", function(ctx) {
      s11_mark("prompt_section")
      "S11 SECTION"
    }, tier = "T1", order = 880L),
    gptr_spec("compactor", "s11compactor", should = function(session, ctx) {
      s11_mark("compactor")
      FALSE
    }, compact = function(session, ctx) stop("the s11 compactor never compacts")),
    gptr_spec("cache_policy", "s11-api", plan = function(parts, caps, session) {
      s11_mark("cache_policy")
      list(anchors = character(), tail_ttl = "5m", key = "s11")
    }),
    gptr_spec("estimator", "default", estimate = function(x, class) {
      s11_mark("estimator")
      nchar(paste(x, collapse = "")) / 4
    }, calibrate = function(state, estimated, reported) state),
    # P15's gptr_doc() binds only .R/.Rmd/.qmd/.ipynb and fetches the format record by those
    # names (doc_format_get()), so the fixture's record shadows the built-in `qmd` format
    # (rank 5 beats builtin:documents' rank 6; IC-69 per-record override). No other test of this
    # file binds a .qmd document, and the record is filtered out when the file ends.
    gptr_spec("doc_format", "qmd", ext = "qmd",
              locate = function(text, site) {
                s11_mark("doc_format")
                list(stmt = NULL, blocks = list())
              },
              render = function(block, site) {
                s11_mark("doc_format")
                "# s11 block"
              },
              upsert = function(text, site, lines, block_id) {
                s11_mark("doc_format")
                paste(c(text, lines), collapse = "\n")
              },
              inert = function(lines) paste0("#~ ", lines)),
    gptr_spec("artifact_type", "s11art",
              build = function(id, dir, data, ctx) {
                s11_mark("artifact_type")
                writeLines("s11 app", file.path(dir, "app.txt"))
                invisible(dir)
              },
              check = function(dir, ctx) list(ok = TRUE, messages = character()),
              launch = function(version_dir, ctx) {
                list(url = "http://127.0.0.1:1/", pid = NA_integer_, stop = function() NULL)
              },
              stop = function(handle) NULL),
    gptr_backend("s11backend", start = function(spec, ctx) {
      s11_mark("backend")
      registry_get("backend", "inline")$start(spec, ctx)
    }, cancel = function(handle) handle$cancel(),
    capabilities = list(parallel = "io", live_objects = TRUE, ask = "queue")),
    gptr_agent("s11agent", description = "S11 agent", model = "s11prov/s11-model",
               system = "S11 AGENT SYSTEM", backend = "s11backend"),
    gptr_spec("ui", "s11ui", has_ui = function() TRUE,
              select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                                allow_other = FALSE) {
                1L
              },
              input = function(prompt, default = "", secret = FALSE) "",
              questions = function(qs) list(answers = list(), cancelled = TRUE),
              notify = function(text, level = "info") invisible(NULL),
              permission = function(request) {
                s11_mark("ui")
                list(decision = "allow", remember = NULL, feedback = NULL)
              }),
    gptr_spec("frontend", "s11front", run = function(session, ...) {
      s11_mark("frontend")
      session
    }),
    gptr_spec("setting", "s11fixture.level", default = 1L, description = "S11 level",
              scope = "both", validate = function(value) {
                s11_mark("setting")
                as.integer(value)
              }, tighten = NULL),
    gptr_spec("secret_source", "s11secrets", resolve = function(name, ctx) {
      if (!identical(name, "S11_TOKEN")) return(NULL)
      s11_mark("secret_source")
      "s11-secret-value-abcdefgh"
    }, list = function(ctx) "S11_TOKEN"),
    gptr_spec("redaction_rule", "s11rule", pattern = "S11-[0-9]{6}", anchor = "S11-",
              marker = "S11_ID", profiles = c("persist", "stream", "context", "code")),
    gptr_spec("env_alias", "S11_API_KEY", aliases = "s11-key"),
    gptr_spec("child_env", "s11env", base = "inherit", keep = character(), drop = "^S11_DROP",
              set = c(S11_SET = "yes"), billing = list()),
    gptr_spec("checkpointer", "s11ckpt", scope = "other",
              before = function(call, ctx) {
                s11_mark("checkpointer")
                "s11token"
              },
              after = function(call, ctx, token) list(token = token),
              undo = function(fragment, ctx, force) "s11 undone",
              redo = function(fragment, ctx, force) "s11 redone",
              prune = function(live_keys, ctx) invisible(NULL),
              describe = function(fragment) "s11 fragment"),
    gptr_spec("kind", "s11kind", validate = function(spec) {
      s11_mark("kind")
      spec
    }, resolve = "first", fields = "value", order_field = NULL, experimental = TRUE),
    gptr_spec("route", "s11route", order = 5,
              match = function(call) isTRUE(identical(call$prompt, "s11 route please")),
              run = function(call) {
                s11_mark("route")
                "routed by s11"
              }, description = "S11 route"),
    gptr_spec("preset", "s11preset", tools = c("read", "r"), sections = function(name) {
      s11_mark("preset")
      name %in% c("preamble", "tools", "rules", "modes", "context", "s11section")
    }, preamble = "short"),
    # P02's validator requires `rows` (a data frame with the risk-functions.csv columns, IC-69);
    # top-level column fields would make gptr_spec() throw and ext_load() roll back every record.
    gptr_spec("risk_rule", "s11risk",
              rows = data.frame(package = "s11pkg", `function` = "danger", level = 4L,
                                category = "critical", path_arg = "", note = "S11 rule",
                                check.names = FALSE, stringsAsFactors = FALSE)),
    gptr_spec("service", "s11.echo", fun = function(x) {
      s11_mark("service")
      x
    }),
    gptr_spec("renderer", "s11fixture.note",
              render = function(entry, width, ctx) {
                s11_mark("renderer")
                "S11 NOTE"
              },
              doc = function(entry, format) {
                s11_mark("renderer")
                "## s11 note"
              }),
    gptr_spec("search_source", "s11src", docs = function(ctx) {
      s11_mark("search_source")
      data.frame(id = "s11doc", text = "zebra quantum lattice", kind = "s11")
    }),
    gptr_spec("store", "s11store",
              open = function(...) {
                s11_mark("store")
                s11_store()$open(...)
              },
              append = function(...) {
                s11_mark("store")
                s11_store()$append(...)
              },
              read = function(...) s11_store()$read(...),
              fork = function(...) s11_store()$fork(...)),
    gptr_spec("evaluator", "s11eval", eval = function(code, envir, ...) {
      s11_mark("evaluator")
      eval_r(code, envir, ...)
    }))
}

s11_loaded = ext_load(function(gptr) {
  for (spec in s11_specs()) gptr$register(spec)
}, source = "plugin:s11fixture", rank = 5L)
# A top-level defer of a testthat 3e file runs when this file ends. (A defer on
# testthat::teardown_env() would run only after every test file, and the fixture's rank-5
# `default` estimator, `qmd` doc format, T1 section and first-message block would leak into
# every later file: test-secrets-e2e.R, test-session-*.R, test-tool-*.R, ...)
withr::defer({
  gptr_config(store = NULL, evaluator = NULL, compactor = NULL, `s11fixture.level` = NULL,
              .scope = "session")
  registry_filters_set("-plugin:s11fixture", scope = "session")
  unlink(s11_dir, recursive = TRUE)
})

s11_last_request = function() s11$requests[[length(s11$requests)]]
# Everything printed: stdout, messages (cli output arrives as messages under testthat) and
# warnings, as text lines.
s11_capture = function(expr) {
  ep = testthat::evaluate_promise(expr)
  unlist(strsplit(c(ep$output, ep$messages, ep$warnings), "\n", fixed = TRUE))
}
s11_first_message_text = function(context) {
  paste(vapply(context$messages[[1L]]$content, function(b) b$text %||% "", ""), collapse = "\n")
}

test_that("the fixture plugin registers one record of every kind but the MCP server", {
  expect_true(s11_loaded)
  reg = gptr_registry()
  mine = unique(reg$kind[reg$source == "plugin:s11fixture"])
  expect_setequal(mine, setdiff(c(kind_names(), "s11kind"), c("mcp_server", "s11kind")))
})

test_that("a run uses the provider, adapter, tool, gate, context and cost records", {
  local_vault()
  local_project()
  # A compactor record is used only when the `compactor` setting selects it (P07
  # compact_compactor()); its should() runs at every request boundary and answers FALSE.
  gptr_config(compactor = "s11compactor", .scope = "session")
  withr::defer(gptr_config(compactor = NULL, .scope = "session"))
  e = new.env()
  s = peter("use the s11 tool", model = "s11prov/s11-model", mode = "auto", skills = "s11-skill",
           envir = e)
  expect_identical(s$text, "s11 tool result seen")
  first = s11$requests[[length(s11$requests) - 1L]]
  if (grepl("S11 SKILL BODY", s11_first_message_text(first), fixed = TRUE)) s11_mark("skill")
  if (identical(first$cache_plan$key, "s11")) s11_mark("cache_policy")
  if (grepl("s11 context", s11_first_message_text(first), fixed = TRUE)) s11_mark("context_block")
  expect_match(first$system$t1, "<s11section>\nS11 SECTION\n</s11section>", fixed = TRUE)
  s11_mark("provider")
  # Checkpointers run for sequential tools that are not read-only (04 section 10.2 row 29): an r
  # call that creates an object certainly is one, whatever risk the direct tool is given.
  s |> peter("use r please")
  expect_identical(e$s11_x, 1)
  for (k in c("adapter", "tool", "policy", "hook", "context_block", "prompt_section",
              "checkpointer", "compactor", "cache_policy", "estimator", "secret_source",
              "skill")) {
    expect_true(s11_used(k), info = k)
  }
  expect_false(is.null(s11$handle))
  expect_true(is.numeric(s11$tokens))
})

test_that("the router record sends each request to the model record it picks", {
  local_project()
  s = peter("hello router", model = "s11router", envir = new.env())
  expect_true(s11_used("router"))
  # The session keeps the router as its model (P06: `router:<name>`, routed per request); the
  # request itself went to the model record the router returned.
  expect_identical(s$model, "router:s11router")
  expect_identical(s11$model_ids[[length(s11$model_ids)]], "s11-extra")
  s11_mark("model")
})

test_that("the preset record decides the tool array", {
  local_project()
  peter("hello preset", model = "s11prov/s11-model", .opts = list(preset = "s11preset"),
       envir = new.env())
  tools = vapply(s11_last_request()$tools, function(t) t$name, "")
  expect_true(all(c("read", "r") %in% tools))
  expect_false("edit" %in% tools)
  expect_true(s11_used("preset"))
})

test_that("the ui record answers the permission ask of a manual run", {
  local_project()
  local_gptr_options(ui = "s11ui", interactive = TRUE)
  # An r call that creates an object is always asked in manual mode (level >= 1).
  s = peter("use r please", model = "s11prov/s11-model", mode = "manual", envir = new.env())
  expect_identical(s$text, "s11 tool result seen")
  expect_true(s11_used("ui"))
})

test_that("the frontend record runs a call without a prompt", {
  local_project()
  local_gptr_options(interactive = TRUE)
  # run(session, ...) gets the call's session: the piped one (P14's console route)
  s = peter("hello frontend", model = "s11prov/s11-model", envir = new.env())
  expect_identical(s |> peter(.opts = list(frontend = "s11front")), s)
  expect_true(s11_used("frontend"))
})

test_that("the console dispatches the command and the prompt template", {
  local_project()
  local_scripted_ui()
  inputs = c("/s11cmd", "/s11tmpl hello", "/exit")
  i = 0L
  local_mocked_bindings(gptr_readline = function(prompt = "") {
    i <<- i + 1L
    if (i > length(inputs)) "/exit" else inputs[[i]]
  })
  out = s11_capture(peter(model = "s11prov/s11-model", envir = new.env()))
  expect_true(s11_used("command"))
  expect_true(any(grepl("s11 command ran", out, fixed = TRUE)))
  expect_match(msg_text(s11_last_request()$messages[[length(s11_last_request()$messages)]]),
               "Say hello politely", fixed = TRUE)
  s11_mark("prompt_template")
})

test_that("the setting record validates gptr_config() and namespaced .opts", {
  local_project()
  gptr_config(`s11fixture.level` = 2L, .scope = "session")
  expect_identical(gptr_config()[["s11fixture.level"]], 2L)
  peter("hello setting", model = "s11prov/s11-model",
       .opts = list(s11fixture = list(level = 3L)), envir = new.env())
  expect_true(s11_used("setting"))
})

test_that("data records take effect: redaction, aliases, child env, risk, kind, service, route", {
  expect_match(gptr_redact("id S11-123456 end"), "[secret:S11_ID]", fixed = TRUE)
  s11_mark("redaction_rule")
  f = withr::local_tempfile(fileext = ".env")
  writeLines("s11-key=s11abcdefgh123456", f)
  withr::local_envvar(c(S11_API_KEY = NA, S11_DROP_ME = "x"))
  rep = gptr_env(f, set_env = FALSE, quiet = TRUE)
  expect_identical(rep$variable, "S11_API_KEY")
  s11_mark("env_alias")
  env = child_env("s11env")
  expect_identical(env[["S11_SET"]], "yes")
  expect_false("S11_DROP_ME" %in% names(env))
  s11_mark("child_env")
  expect_identical(gptr_risk("s11pkg::danger()")$level, 4L)
  s11_mark("risk_rule")
  off = gptr_register(gptr_spec("s11kind", "one", value = 1))
  withr::defer(off())
  expect_identical(registry_get("s11kind", "one")$value, 1)
  expect_true(s11_used("kind"))
  expect_identical(ext_service_get("s11.echo")("a"), "a")
  expect_true(s11_used("service"))
  expect_identical(peter("s11 route please"), "routed by s11")
  expect_true(s11_used("route"))
  hits = peter$search("zebra quantum lattice")
  expect_true("s11" %in% hits$kind)
  expect_true(s11_used("search_source"))
})

test_that("the store and evaluator records serve a run", {
  local_project()
  gptr_config(store = "s11store", evaluator = "s11eval", .scope = "session")
  withr::defer(gptr_config(store = NULL, evaluator = NULL, .scope = "session"))
  e = new.env()
  peter("use r please", model = "s11prov/s11-model", mode = "auto", envir = e)
  expect_identical(e$s11_x, 1)
  expect_true(s11_used("store"))
  expect_true(s11_used("evaluator"))
})

test_that("the agent record runs through the backend record", {
  local_project()
  team = peter("delegate this", agents = list(helper = agent("s11agent")), envir = new.env())
  expect_identical(team$kind, "team")
  expect_true(s11_used("backend"))
  seen = vapply(s11$requests, function(r) {
    grepl("S11 AGENT SYSTEM", paste(r$system$t0, r$system$t1), fixed = TRUE)
  }, NA)
  expect_true(any(seen))
  s11_mark("agent")
})

test_that("the artifact type record builds and checks an artifact", {
  skip_if_not_installed("shiny")
  # The working copy of a kind without a working file is the artifact's directory (P23)
  dir.create(file.path(local_project(), ".gptr", "artifacts", "s11-app"), recursive = TRUE)
  a = peter$app("s11-app", kind = "s11art", check = TRUE, launch = FALSE)
  expect_s3_class(a, "gptr_artifact")
  expect_identical(a$kind, "s11art")
  expect_true(s11_used("artifact_type"))
})

test_that("the doc format and renderer records write a bound document", {
  skip_if_not_installed("knitr")
  root = local_project()
  local_gptr_options(quiet = FALSE, verbose = 2L)
  # P15 writes the blocks of calls inside a document: here a chunk of the knitted .qmd
  doc = file.path(root, "notes.qmd")
  writeLines(c("```{r}",
               "s = peter(\"use the s11 tool\", model = \"s11prov/s11-model\", mode = \"auto\")",
               "```"), doc)
  gptr_doc(doc)
  withr::defer(gptr_doc(FALSE))
  knitr::knit(doc, output = file.path(root, "notes.md"), envir = new.env(), quiet = TRUE)
  expect_true(s11_used("doc_format"))
  expect_true(s11_used("renderer"))
})

test_that("the interpreter and MCP server records run their processes", {
  skip_on_cran()
  local_project()
  script = withr::local_tempfile(fileext = ".s11r")
  writeLines("cat('s11 interpreter ok')", script)
  res = peter$script(script)
  expect_match(res$stdout, "s11 interpreter ok", fixed = TRUE)
  s11_mark("interpreter")
  fx = local_mcp_fixture(tools = "echo")
  # fx$spec is a plain list in the mcp_server shape (P18): the fixture plugin registers it as a
  # record of kind mcp_server, built the way P18's mcp_sync() builds its records.
  server = do.call(gptr_spec, c(list("mcp_server", fx$spec$name),
                                fx$spec[setdiff(names(fx$spec), "name")]))
  expect_true(ext_load(function(gptr) gptr$register(server), source = "plugin:s11fixture",
                       rank = 5L))
  echo = peter$mcp[[fx$spec$name]]$echo
  expect_match(paste(unlist(echo(text = "s11 mcp")), collapse = " "), "s11 mcp", fixed = TRUE)
  s11_mark("mcp_server")
})

test_that("every registry kind was used at run time (IC-73)", {
  skip_on_cran()
  kinds = setdiff(kind_names(), "s11kind")
  expect_length(kinds, 38L)
  expect_setequal(ls(s11$used), kinds)
})
