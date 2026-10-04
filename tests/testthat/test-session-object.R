source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- the shell and the transcript

test_that("session_new() builds an idle shell whose only binding is .d", {
  home = new.env()
  s = test_session(mode = "manual", home = home)
  d = session_data(s)
  expect_s3_class(s, "gptr_session")
  expect_identical(ls(s, all.names = TRUE), ".d")
  # .d is unclassed; nothing is frozen before the first run (P07 freezes only a NULL `frozen`);
  # the out store is created lazily by P01's out_store() (it rejects a bare environment)
  expect_identical(list(attr(d, "class"), d$frozen, session_live(s)$out), list(NULL, NULL, NULL))
  expect_match(d$id, "^s[0-9a-f]{10}$")
  expect_identical(d$status, "idle")
  expect_identical(d$mode, "manual")
  expect_identical(d$kind, "chat")
  expect_identical(d$turns, 0L)
  expect_true(is.na(d$last_text))
  expect_identical(d$queue, list(steer = list(), follow_up = list()))
  expect_identical(names(d$usage), usage_columns)
  expect_identical(session_home(s), home)
  expect_identical(gptr_last(), s)
  expect_identical(session_live(s)$ctx$session, s)
})

test_that("session_new() validates its arguments with gptr_error_invalid_argument", {
  expect_error(session_new("fake/fake-1", "reckless"), class = "gptr_error_invalid_argument")
  expect_error(session_new(1, "auto"), class = "gptr_error_invalid_argument")
  expect_error(session_new("fake/fake-1", "auto", home = list()),
               class = "gptr_error_invalid_argument")
  expect_error(session_new("fake/fake-1", "auto", kind = "robot"),
               class = "gptr_error_invalid_argument")
})

test_that("an adopted id is one file-name-safe string: no path segments, no `_` (IC-20)", {
  local_store()
  expect_error(test_session(opts = list(id = 1)), class = "gptr_error_invalid_argument")
  expect_error(test_session(opts = list(id = "/../../../escaped")),
               class = "gptr_error_invalid_argument")
  expect_error(test_session(opts = list(id = "s_1")), class = "gptr_error_invalid_argument")
  expect_null(session_by_id("/../../../escaped"))
  # a gptr id and the uuid of a foreign Pi file are both adopted
  uuid = "0192f3a4-5b6c-7d8e-9f01-23456789abcd"
  expect_identical(session_data(test_session(opts = list(id = uuid)))$id, uuid)
})

test_that("an id already live in this process is split brain", {
  s = test_session()
  expect_error(test_session(opts = list(id = session_data(s)$id)), class = "gptr_error_split_brain")
})

test_that("child sessions are registered under their parent, one level deeper", {
  root = test_session()
  last = gptr_last()
  child = test_session(kind = "child", parent = root, opts = list(name = "stats"))
  cd = session_data(child)
  expect_identical(cd$parent_id, session_data(root)$id)
  expect_identical(cd$depth, 1L)
  expect_identical(session_data(root)$children$stats, child)
  expect_identical(gptr_last(), last)
})

test_that("session_append() numbers, parents and time-stamps entries and moves the leaf", {
  s = test_session()
  id1 = session_append(s, entry_message(msg_user("hello")))
  id2 = session_append(s, entry_custom("test.note", list(n = 1L)))
  d = session_data(s)
  expect_match(c(id1, id2), "^[0-9a-f]{8}$")
  expect_null(d$entries[[1L]]$parent_id)
  expect_identical(d$entries[[2L]]$parent_id, id1)
  expect_identical(d$leaf, id2)
  expect_match(d$entries[[1L]]$timestamp, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[.][0-9]{3}Z$")
  expect_identical(d$entries[[1L]]$gptr$turn, 0L)
  expect_identical(d$entries[[2L]]$custom_type, "test.note")
})

test_that("a user message's turn is added to its entry-level gptr fields, never replacing them", {
  s = test_session()
  d = session_data(s)
  d$turns = 2L
  session_append(s, c(entry_message(msg_user("hi")), list(gptr = list(note = "kept"))))
  session_append(s, c(entry_message(msg_user("again")), list(gptr = list(turn = 7L))))
  expect_identical(d$entries[[1L]]$gptr, list(note = "kept", turn = 2L))
  expect_identical(d$entries[[2L]]$gptr, list(turn = 7L))
})

test_that("entries_path() walks leaf to root; path_messages(), path_turn(), final_text() read it", {
  s = test_session()
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("q1")))
  session_append(s, entry_message(msg_assistant("a1", api = "fake", provider = "fake",
                                                model = "fake-1")))
  path = entries_path(d)
  expect_length(path, 2L)
  expect_identical(vapply(path_messages(path), function(m) m$role, ""), c("user", "assistant"))
  expect_identical(path_turn(path), 1L)
  expect_identical(final_text(path), "a1")
  call = block_tool_call("c1", "read", list(path = "a"))
  session_append(s, entry_message(msg_assistant(list(call), api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "tool_use")))
  expect_null(final_text(entries_path(d)))
})

test_that("entry_model_change() records routers as provider router", {
  e = entry_model_change("router:cheapest", reason = "router")
  expect_identical(c(e$provider, e$model_id), c("router", "cheapest"))
  e2 = entry_model_change("anthropic/claude-sonnet-5-5", thinking = "high")
  expect_identical(c(e2$provider, e2$model_id, e2$gptr$thinking), c("anthropic",
                                                                    "claude-sonnet-5-5", "high"))
})

# ---------------------------------------------------------------- accessors and printing

# answered_session() (a one-turn session built by appends, with one usage row) is in the harness.

test_that("accessors read .d; names() and .DollarNames() list them; unknown members are classed", {
  s = answered_session()
  expect_identical(s$text, "The data has 32 rows.")
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 1L)
  expect_identical(s[["model"]], "fake/fake-1")
  expect_identical(vapply(s$messages, function(m) m$role, ""), c("user", "assistant"))
  expect_equal(s$cost, 0.0123)
  expect_s3_class(s$usage, "gptr_usage")
  expect_identical(s$history$role, c("user", "assistant"))
  expect_true(all(c("text", "value", "usage", "history", "envir") %in% names(s)))
  expect_identical(.DollarNames(s, "^us"), "usage")
  err = expect_error(s$nope, class = "gptr_error_unknown_member")
  expect_true("text" %in% err$available)
})

test_that("$<- and [[<- are refused (gptr_error_readonly)", {
  s = test_session()
  expect_error({
    s$status = "x"
  }, class = "gptr_error_readonly")
  expect_error({
    s[["status"]] = "x"
  }, class = "gptr_error_readonly")
  expect_identical(s$status, "idle")
})

test_that("children are reachable by name and by index; team text joins the reports", {
  team = test_session(kind = "team")
  a = test_session(kind = "child", parent = team, opts = list(name = "stats"))
  ad = session_data(a)
  ad$last_text = "p < 0.05"
  expect_identical(team$stats, a)
  expect_identical(team[[1L]], a)
  expect_true("stats" %in% names(team))
  expect_identical(team$text, "### stats (fake/fake-1)\np < 0.05")
})

test_that("[[ takes one child index or one name; anything else is a classed error", {
  team = test_session(kind = "team")
  expect_error(team[[1L]], class = "gptr_error_invalid_argument")
  a = test_session(kind = "child", parent = team, opts = list(name = "stats"))
  expect_identical(team[[1]], a)
  expect_identical(team[["stats"]], a)
  err = expect_error(team[[2L]], class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "i")
  expect_error(team[[1.5]], class = "gptr_error_invalid_argument")
  expect_error(team[[c(1L, 1L)]], class = "gptr_error_invalid_argument")
  expect_error(team[[NA_integer_]], class = "gptr_error_invalid_argument")
  expect_error(team[[c("a", "b")]], class = "gptr_error_invalid_argument")
  expect_error(team[[NA_character_]], class = "gptr_error_invalid_argument")
  expect_error(team[["nope"]], class = "gptr_error_unknown_member")
})

test_that("print(), str(), format() and summary() read only .d", {
  s = answered_session()
  testthat::local_reproducible_output(width = 80)
  hide = function(x) gsub("s[0-9a-f]{10}", "s<id>", x)
  expect_snapshot(print(s), transform = hide)
  expect_snapshot(str(s), transform = hide)
  expect_identical(format(s), "The data has 32 rows.")
  expect_identical(as.character(s), "The data has 32 rows.")
  sm = summary(s)
  expect_s3_class(sm, "gptr_session_summary")
  expect_identical(sm$role, c("user", "assistant"))
  suppressMessages(utils::capture.output({
    vis = withVisible(print(s))
  }))
  expect_false(vis$visible)
  expect_identical(vis$value, s)
})

test_that("unknown usage prints as unknown, never as zero (IC-74)", {
  testthat::local_reproducible_output(width = 80)
  s = answered_session()
  id = session_data(s)$id
  # a second request that reported no cache use and no cost: both stay unknown (D-021)
  usage_add(s, usage_conform(data.frame(request_id = "q000000000002", session = id,
                                        agent = "main", provider = "fake", model = "fake-1",
                                        route = "api", input = 10, output = 2,
                                        stringsAsFactors = FALSE)))
  expect_identical(s$cost, NA_real_)
  expect_identical(attr(s$usage, "totals")[["cost"]], NA_real_)
  expect_identical(session_footer(s),
                   paste0("idle . fake/fake-1 . 1 turn . unknown tokens . unknown cost . ", id))
  printed = testthat::capture_messages(print(s))
  expect_match(printed, "unknown tokens . unknown cost", fixed = TRUE, all = FALSE)
  expect_false(any(grepl("$NA", printed, fixed = TRUE)))
  # a known zero stays a known zero; a fresh session has made no request (known zeros)
  z = test_session()
  usage_add(z, usage_conform(data.frame(request_id = "q000000000003",
                                        session = session_data(z)$id, input = 5, output = 1,
                                        cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
                                        cost = 0, stringsAsFactors = FALSE)))
  expect_identical(z$cost, 0)
  expect_match(session_footer(z), " . 6 tokens . $0.0000 . ", fixed = TRUE)
  expect_match(session_footer(test_session()), " . 0 turns . 0 tokens . $0.0000 . ", fixed = TRUE)
})

# ---------------------------------------------------------------- the value policy (03 section 5.1)

test_that("a small bound value is copied, a large one held by name, an anonymous one boxed", {
  home = new.env()
  home$small = 1:10
  home$big = as.numeric(1:3e5)
  s = test_session(home = home)
  session_value_set(s, "small", home$small, name = "small")
  session_value_set(s, "big", home$big, name = "big")
  session_value_set(s, "lm(...)", list(a = 1))
  vals = session_data(s)$values
  expect_identical(vapply(vals, function(v) v$mode, ""), c("copy", "name", "box"))
  expect_null(vals[[2L]]$value)
  expect_identical(s$values$mode, c("copy", "name", "box"))
  entries = Filter(function(e) identical(e$custom_type, "gptr.value"), session_data(s)$entries)
  expect_length(entries, 3L)
  expect_null(entries[[2L]]$data$value)
  expect_identical(entries[[2L]]$data$address, rlang::obj_address(home$big))
  expect_null(entries[[1L]]$data$address)
})

test_that("$value is the latest designated value; names are live views with a rebound notice", {
  home = new.env()
  home$big = as.numeric(1:3e5)
  s = test_session(home = home)
  session_value_set(s, "big", home$big, name = "big")
  expect_identical(s$value, home$big)
  home$big = "replaced"
  withr::local_options(gptr.quiet = FALSE)
  expect_message({
    v = s$value
  }, class = "gptr_message_value_rebound")
  expect_identical(v, "replaced")
})

test_that("a name is looked up in the home and its fork overlays, never in other parents", {
  withr::local_options(gptr.quiet = FALSE)
  big = as.numeric(1:3e5)
  # a home whose parent is baseenv: a removed binding is not bound, never base::pi
  home = new.env(parent = baseenv())
  home$pi = big
  s = test_session(home = home)
  session_value_set(s, "pi", home$pi, name = "pi")
  expect_identical(session_data(s)$values[[1L]]$mode, "name")
  rm("pi", envir = home)
  expect_message({
    v = s$value
  }, "not bound in this R process", class = "gptr_message_notice")
  expect_null(v)
  expect_null(binding_env("pi", home))
  # an enclosing environment that is not a fork overlay is not searched
  mid = new.env(parent = globalenv())
  mid$gptr_test_value_p06 = big
  inner = new.env(parent = mid)
  inner$gptr_test_value_p06 = big
  s2 = test_session(home = inner)
  session_value_set(s2, "v", big, name = "gptr_test_value_p06")
  rm("gptr_test_value_p06", envir = inner)
  expect_message({
    v2 = s2$value
  }, class = "gptr_message_notice")
  expect_null(v2)
  # a fork overlay (and an overlay of an overlay) falls through to its base home
  src = new.env(parent = globalenv())
  src$fit = big
  b = test_session(home = src)
  session_value_set(b, "fit", src$fit, name = "fit")
  ov = new.env(parent = src)
  attr(ov, "gptr_overlay") = "overlay of s0123456789"
  ov2 = new.env(parent = ov)
  attr(ov2, "gptr_overlay") = "overlay of s0123456780"
  expect_identical(binding_env("fit", ov2), src)
  f = test_session(home = ov2)
  fd = session_data(f)
  fd$values = session_data(b)$values
  expect_identical(f$value, big)
})

test_that("a value bound in a function frame that is not kept is boxed", {
  s = test_session(home = new.env())
  f = function() {
    fit = list(coef = 1)
    session_value_set(s, "fit", fit, name = "fit", forced_home = environment())
  }
  f()
  expect_identical(session_data(s)$values[[1L]]$mode, "box")
  expect_identical(s$value, list(coef = 1))
})

test_that("held copies and boxes are trimmed to gptr.values_max_bytes, the latest kept", {
  local_gptr_options(values_max_bytes = 5000)
  s = test_session()
  for (i in 1:5) session_value_set(s, paste0("v", i), rep(as.numeric(i), 500))
  held = vapply(session_data(s)$values, function(v) !is.null(v$value), NA)
  expect_true(held[[5L]])
  expect_false(held[[1L]])
  expect_identical(s$value, rep(5, 500))
})

test_that("session_value_get(turn =) returns the value of that turn or NULL", {
  s = test_session()
  d = session_data(s)
  session_value_set(s, "a", "first")
  d$turns = 1L
  session_value_set(s, "b", "second")
  expect_identical(session_value_get(s, turn = 0L), "first")
  expect_identical(session_value_get(s), "second")
  expect_null(session_value_get(s, turn = 7L))
})
