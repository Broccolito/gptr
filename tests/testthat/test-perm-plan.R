# tests/testthat/test-perm-plan.R -- plan mode (P11)

# A session shell with the fields plan mode reads (contract 5.1, 7.6); `$` of a gptr_session
# refuses `.d`, so tests reach the data through session_data(). The kernel SDK verbs are mocked
# over it by local_plan_kernel()
plan_session = function(home, mode = "plan") {
  s = new.env(parent = emptyenv())
  d = new.env(parent = emptyenv())
  d$id = "s0000000042"
  d$mode = mode
  d$depth = 0L
  d$entries = list()
  d$queue = list()
  d$frozen = list(preset = "readonly", tool_names = c("read", "r"))
  d$home = home
  s$.d = d
  class(s) = "gptr_session"
  s
}

local_plan_kernel = function(.env = parent.frame()) {
  local_mocked_bindings(
    session_home = function(s) session_data(s)$home,
    session_append = function(s, entry) {
      d = session_data(s)
      d$entries[[length(d$entries) + 1L]] = entry
      invisible("00000001")
    },
    session_set_mode = function(s, mode, source = "user") {
      assign("mode", mode, envir = session_data(s))
      invisible(s)
    },
    session_enqueue = function(s, text, as = c("steer", "follow_up"), source = "api_user",
                               blocks = list()) {
      d = session_data(s)
      d$queue[[length(d$queue) + 1L]] = list(text = text, as = as[1L], source = source)
      invisible(s)
    },
    run_current = function() NULL,
    .env = .env
  )
}

# A fresh pending-plan store for the calling test
local_plan_store = function(.env = parent.frame()) {
  old = the$plan_pending
  the$plan_pending = NULL
  withr::defer(assign("plan_pending", old, envir = the), envir = .env)
  invisible(plan_store())
}

plan_ctx = function(s, envir = NULL) {
  st = new.env(parent = emptyenv())
  added = new.env(parent = emptyenv())
  added$specs = list()
  list(session = s, envir = envir, mode = function() session_data(s)$mode,
       state = function() st, has_ui = function() FALSE,
       ui = function() ext_service_get("ui.get")(s),
       add_tools = function(specs) added$specs = c(added$specs, specs), added = added)
}

plan_text = paste0("<proposed_plan>\nGoal: save the row count\n1. Compute nrow(d)\n",
                   "2. Write it\n</proposed_plan>")

test_that("the last <proposed_plan> block is extracted; steps and slugs (20 section 2.11)", {
  two = paste("draft <proposed_plan>old</proposed_plan> then", plan_text)
  expect_identical(plan_extract(two),
                   "Goal: save the row count\n1. Compute nrow(d)\n2. Write it")
  expect_null(plan_extract("no plan here"))
  expect_null(plan_extract("<proposed_plan>   </proposed_plan>"))
  expect_identical(plan_steps(plan_extract(plan_text)), c("1. Compute nrow(d)", "2. Write it"))
  expect_identical(plan_slug("Goal: Save the row-count!\n1. x"), "save-the-row-count")
  expect_identical(plan_slug("\n\n"), "plan")
})

test_that("the plan policy denies writes and code not known to be read-only (IC-54)", {
  root = local_project()
  local_plan_kernel()
  home = new.env()
  s = plan_session(home)
  scratch = new.env(parent = home)
  ctx = plan_ctx(s, envir = scratch)
  r = function(code) {
    list(id = "c1", name = "r", input = list(code = code), nested = FALSE, risk = gptr_risk(code))
  }
  w = list(id = "c2", name = "write", input = list(path = "out.txt", content = "x"),
           nested = FALSE, risk = list(level = 2L))
  expect_identical(plan_policy_check(w, ctx)$decision, "deny")
  expect_null(plan_policy_check(r("n = nrow(mtcars); summary(mtcars)"), ctx))
  d = plan_policy_check(r("FindClusters(x)"), ctx)
  expect_identical(d$decision, "deny")
  expect_match(d$reason, "not known to be read-only in plan mode", fixed = TRUE)
  expect_identical(plan_policy_check(r("targets::tar_destroy()"), ctx)$decision, "deny")
  expect_identical(plan_policy_check(r("usethis::create_package('.')"), ctx)$decision, "deny")
  expect_match(plan_policy_check(r("x[1] = 0"), ctx)$reason, "cannot change existing objects",
               fixed = TRUE)
  expect_null(plan_policy_check(r("gptr_permissions(allow = 'r(level<=3)')"), ctx))
  d = plan_policy_check(r("gptr_permissions(allow = 'r'); unlink('data', recursive = TRUE)"), ctx)
  expect_identical(d$decision, "deny")
  expect_match(d$reason, "unlink", fixed = TRUE)
  expect_match(plan_policy_check(r("n = 1"), plan_ctx(s, envir = home))$reason,
               "scratch environment", fixed = TRUE)
  assign("mode", "manual", envir = session_data(s))
  expect_null(plan_policy_check(w, ctx))
})

test_that("in plan mode blind spots are denied and control calls need a person (acc. 6)", {
  root = local_project()
  local_plan_kernel()
  home = new.env()
  s = plan_session(home)
  ctx = plan_ctx(s, envir = new.env(parent = home))
  decide = function(code) {
    call = list(id = "c1", name = "r", input = list(code = code), nested = FALSE,
                risk = gptr_risk(code))
    rank = c(allow = 1L, modify = 2L, ask = 3L, ask_human = 4L, deny = 5L)
    best = "allow"
    for (p in registry_all("policy")) {
      if (!p$name %in% c(perm_policy_names, "plan")) next
      d = p$check(call, ctx)
      if (!is.null(d) && rank[[d$decision]] > rank[[best]]) best = d$decision
    }
    best
  }
  expect_identical(decide("targets::tar_destroy()"), "deny")
  expect_identical(decide("usethis::create_package('.')"), "deny")
  expect_identical(decide("m = mean(mtcars$mpg)"), "allow")
  expect_identical(decide("gptr_permissions(allow = 'r(level<=3)')"), "ask_human")
  expect_identical(decide("options(gptr.critical_guard = FALSE)"), "ask_human")
  expect_identical(decide("writeLines('x', '.gptr/extensions/x.R')"), "ask_human")
  expect_identical(decide("gptr_trust('.', TRUE); unlink('data', recursive = TRUE)"), "deny")
})

test_that("a captured plan is saved, recorded and keyed by an address string (R2)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  home = new.env()
  s = plan_session(home)
  ctx = plan_ctx(s)
  plan_on_turn_end(list(message = list(role = "assistant", content = list(
    list(type = "text", text = paste("Here is the plan.", plan_text))))), ctx)
  expect_identical(session_data(s)$plan,
                   "Goal: save the row count\n1. Compute nrow(d)\n2. Write it")
  entry = session_data(s)$entries[[1L]]
  expect_identical(entry$custom_type, "gptr.plan")
  expect_identical(entry$data$status, "pending")
  files = list.files(file.path(root, ".gptr", "plans"), full.names = TRUE)
  expect_length(files, 1L)
  expect_match(basename(files), "^[0-9]{4}-[0-9]{2}-[0-9]{2}-save-the-row-count[.]md$")
  expect_identical(entry$data$path, path_rel(files, root))
  st = plan_store()
  rec = get0(home_address(home), envir = st, inherits = FALSE)
  expect_identical(rec$session, "s0000000042")
  for (nm in ls(st, all.names = TRUE)) {
    v = get(nm, envir = st)
    expect_false(is.environment(v) || is.function(v))
    if (is.list(v)) expect_false(any(vapply(v, function(x) is.environment(x) || is.function(x),
                                            logical(1))))
  }
  plan_on_turn_end(list(message = list(role = "assistant", content = list(
    list(type = "text", text = plan_text)))), ctx)
  expect_length(session_data(s)$entries, 1L)
})

test_that("plan.pending hands the plan once, to the next top-level call (IC-56)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  local_gptr_options(quiet = FALSE)
  pending = ext_service_get("plan.pending")
  home = new.env()
  addr = home_address(home)
  s = plan_session(home)
  plan_capture(s, "1. one\n2. two", plan_ctx(s))
  expect_identical(as.character(pending(addr, consume = FALSE)), "1. one\n2. two")
  got = NULL
  msgs = testthat::capture_messages({
    got = pending(addr)
  })
  expect_identical(attr(got, "from"), "s0000000042")
  expect_match(paste(msgs, collapse = ""), "Using the plan from session s0000000042")
  expect_match(paste(msgs, collapse = ""), "2. two", fixed = TRUE)
  expect_null(pending(addr))
  local_gptr_options(plan_handoff = FALSE)
  plan_capture(plan_session(home), "1. again", plan_ctx(s))
  expect_null(pending(addr))
})

test_that("an intervening peter() call, a run, a loop or an hour discard the plan (IC-56)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  pending = ext_service_get("plan.pending")
  home = new.env()
  addr = home_address(home)
  s = plan_session(home)
  plan_capture(s, "1. one", plan_ctx(s))
  plan_on_input(list(source = "prompt"), NULL)
  plan_on_input(list(source = "steer"), NULL)
  expect_false(is.null(pending(addr, consume = FALSE)))
  plan_on_decision(list(model = "jev"), NULL)
  expect_null(pending(addr))
  plan_capture(plan_session(home), "1. two", plan_ctx(s))
  local_mocked_bindings(run_current = function() new.env())
  expect_null(pending(addr))
  local_mocked_bindings(run_current = function() NULL)
  plan_capture(plan_session(home), "1. three", plan_ctx(s))
  rec = get(addr, envir = plan_store())
  rec$time = rec$time - 3601
  assign(addr, rec, envir = plan_store())
  expect_null(pending(addr))
})

test_that("a slash command between the plan and the next peter() call keeps the plan (IC-56)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  pending = ext_service_get("plan.pending")
  home = new.env()
  addr = home_address(home)
  s = plan_session(home)
  plan_capture(s, "1. one", plan_ctx(s))
  # P14 dispatches every slash-command line as an `input` of source "repl" (not a peter() call)
  ev_dispatch("input", ev_new("input", text = "/mode auto", source = "repl"))
  ev_dispatch("input", ev_new("input", text = "/status", source = "repl"))
  # the next peter() call (P08's `input`, source "prompt") is the one the plan goes to
  ev_dispatch("input", ev_new("input", text = "go", source = "prompt"))
  expect_identical(as.character(pending(addr, consume = FALSE)), "1. one")
  ev_dispatch("input", ev_new("input", text = "again", source = "pipe"))
  expect_null(pending(addr))
})

test_that("a peter() call inside a loop body does not receive the plan (IC-56)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  home = new.env()
  addr = home_address(home)
  run_env = new.env()
  run_env$gw = structure(function() plan_pending_get(addr),
                         class = c("gptr_gateway", "function"))
  script = file.path(root, "script.R")
  for (src in c("for (i in 1:2) got = gw()", "while (TRUE) {\n  got = gw()\n  break\n}")) {
    plan_capture(plan_session(home), paste("1.", src), plan_ctx(plan_session(home)))
    writeLines(src, script)
    source(script, local = run_env, keep.source = TRUE)
    expect_null(run_env$got)
    expect_false(exists(addr, envir = plan_store(), inherits = FALSE))
  }
  plan_capture(plan_session(home), "1. top", plan_ctx(plan_session(home)))
  writeLines("got = gw()", script)
  source(script, local = run_env, keep.source = TRUE)
  expect_identical(as.character(run_env$got), "1. top")
})

test_that("the execute menu follows the plan run: mode, tools, a queued go-ahead (6.8.5)", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  local_gptr_options(quiet = FALSE)
  st = local_scripted_ui(list(1L))
  home = new.env()
  s = plan_session(home)
  ctx = plan_ctx(s)
  plan_on_turn_end(list(message = list(role = "assistant", content = list(
    list(type = "text", text = plan_text)))), ctx)
  expect_identical(nrow(st$log), 0L)
  assign("last_text", plan_text, envir = session_data(s))
  msgs = testthat::capture_messages(plan_on_agent_end(list(status = "idle"), ctx))
  expect_identical(st$log$method, "select")
  expect_identical(session_data(s)$mode, "auto")
  expect_identical(session_data(s)$queue[[1L]], list(text = "Go ahead with the plan above.",
                                          as = "follow_up", source = "pause_menu"))
  expect_match(paste(msgs, collapse = ""), "gptr_step(gptr_last())", fixed = TRUE)
  expect_identical(vapply(session_data(s)$entries, function(e) e$data$status, ""),
                   c("pending", "used"))
  expect_false(exists(home_address(home), envir = plan_store(), inherits = FALSE))
  added = vapply(ctx$added$specs, function(sp) sp$name, "")
  expect_true(all(c("edit", "write") %in% added))
  plan_on_agent_start(list(), ctx)
  expect_identical(vapply(ctx$added$specs, function(sp) sp$name, ""), added)
  plan_on_agent_end(list(status = "idle"), ctx)
  expect_identical(nrow(st$log), 1L)
})

test_that("keep planning, a non-interactive run or a nested session show no menu", {
  root = local_project()
  local_plan_kernel()
  local_plan_store()
  st = local_scripted_ui(list(4L))
  s = plan_session(new.env())
  assign("last_text", plan_text, envir = session_data(s))
  plan_on_agent_end(list(status = "idle"), plan_ctx(s))
  expect_identical(session_data(s)$mode, "plan")
  expect_identical(nrow(st$log), 1L)
  s3 = plan_session(new.env())
  assign("depth", 1L, envir = session_data(s3))
  assign("last_text", plan_text, envir = session_data(s3))
  plan_on_agent_end(list(status = "idle"), plan_ctx(s3))
  expect_identical(nrow(st$log), 1L)
  local_gptr_options(interactive = FALSE)
  s2 = plan_session(new.env())
  assign("last_text", plan_text, envir = session_data(s2))
  plan_on_agent_end(list(status = "idle"), plan_ctx(s2))
  expect_identical(nrow(st$log), 1L)
  expect_identical(session_data(s2)$mode, "plan")
  expect_identical(session_data(s2)$plan,
                   "Goal: save the row count\n1. Compute nrow(d)\n2. Write it")
})

test_that("builtin:plan registers the policy and the plan.pending service", {
  expect_true("plan" %in% vapply(registry_all("policy"), function(p) p$name, ""))
  expect_false(isTRUE(the$builtins[["plan"]]$replaceable))
  expect_true(ext_service_has("plan.pending"))
})

test_that("plan mode on the fake provider: denied writes, scratch r, a plan handed over once", {
  root = local_project()
  local_plan_store()
  fake = local_fake_provider(list(
    fake_tool("r", code = "writeLines('x', 'out.txt')"),
    fake_tool("r", code = "n_rows = nrow(d); n_rows"),
    paste0("<proposed_plan>\nGoal: save the row count\n1. Compute nrow(d)\n",
           "2. Write it to out.txt\n</proposed_plan>"),
    "Done."))
  e = new.env()
  e$d = mtcars
  peter("Plan how to save the row count of d.", model = fake, envir = e, mode = "plan")
  reqs = fake_requests(fake)
  expect_false(file.exists(file.path(root, "out.txt")))
  expect_match(msg_text(reqs[[2]]$last_results[[1]]), "Permission denied", fixed = TRUE)
  expect_match(msg_text(reqs[[3]]$last_results[[1]]), "32", fixed = TRUE)
  expect_false(exists("n_rows", envir = e, inherits = FALSE))
  plans = list.files(file.path(root, ".gptr", "plans"), full.names = TRUE)
  expect_length(plans, 1L)
  expect_match(read_utf8(plans)$text, "1. Compute nrow(d)", fixed = TRUE)
  for (nm in ls(plan_store(), all.names = TRUE)) {
    v = get(nm, envir = plan_store())
    expect_false(is.environment(v) || is.function(v))
    if (is.list(v)) expect_false(any(vapply(v, is.environment, logical(1))))
  }
  first_text = function(req) {
    paste(vapply(req$messages[[1L]]$content, function(b) b$text %||% "", ""), collapse = "\n")
  }
  peter("Go ahead.", model = fake, envir = e, mode = "auto")
  expect_match(first_text(fake_requests(fake)[[4L]]), "<plan from=", fixed = TRUE)
  peter("Anything else?", model = fake, envir = e, mode = "auto")
  expect_false(grepl("<plan", first_text(fake_requests(fake)[[5L]]), fixed = TRUE))
})

test_that("a plan is pending for the environment its run evaluated in (IC-40, IC-56)", {
  root = local_project()
  local_plan_store()
  fake = local_fake_provider(list("ok", "<proposed_plan>\n1. a\n</proposed_plan>"))
  e1 = new.env()
  e2 = new.env()
  s = peter("start", model = fake, envir = e1)
  s |> peter("plan it", envir = e2, mode = "plan")
  expect_identical(plan_addresses(), home_address(e2))
})
