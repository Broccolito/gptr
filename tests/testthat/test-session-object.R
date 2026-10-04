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
  # The plan's `expect_identical(session_live(s)$ctx$session, s)` is restored with live$ctx by
  # P06 Task 4: P02's ctx_new(s) reads the session id through the `$id` accessor (Task 4).
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
