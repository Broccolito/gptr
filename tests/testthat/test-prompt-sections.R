# P07 prompt-sections.R: rendering input, helpers, presets, composition, freeze, tool additions
# and gptr_prompt().

p07_session = function(mode = "auto", preset = NULL, .env = parent.frame()) {
  local_fake_provider(list("ok"), .env = .env)
  session_new("fake/fake-1", mode, home = new.env(), preset = preset)
}

pending_of = function(s) get0("prompt_pending", envir = session_live(s)$memo, inherits = FALSE)

# ---- Task 2: rendering input and shared helpers -------------------------------------------------

# The ctx.input service is served (and ctx$input reaches it) only once builtin:prompt is
# declared in Task 3: P01's service_builtin_active() hides a bootstrap service whose built-in
# has no record in a non-empty registry. These tests read the stack directly through
# prompt_input_get(); Task 3 checks ctx$input end to end.
test_that("the rendering input is bound only while rendering, innermost first", {
  s = p07_session()
  ctx = prompt_ctx(s)
  expect_null(prompt_input_get(ctx))
  expect_identical(with_prompt_input(ctx, list(a = 1), function() prompt_input_get(ctx)$a), 1)
  inner = with_prompt_input(ctx, list(a = 1), function() {
    with_prompt_input(ctx, list(a = 2), function() prompt_input_get(ctx)$a)
  })
  expect_identical(inner, 2)
  expect_null(prompt_input_get(ctx))
  expect_length(prompt_frames$stack, 0L)
  # the input is per ctx (04 section 7.0): another session's ctx never sees it
  s2 = p07_session()
  ctx2 = prompt_ctx(s2)
  expect_null(with_prompt_input(ctx, list(a = 1), function() prompt_input_get(ctx2)))
  mixed = with_prompt_input(ctx, list(a = 1), function() {
    with_prompt_input(ctx2, list(a = 2), function() {
      list(prompt_input_get(ctx)$a, prompt_input_get(ctx2)$a)
    })
  })
  expect_identical(mixed, list(1, 2))
  expect_length(prompt_frames$stack, 0L)
})

test_that("an error inside a rendering still pops the input", {
  s = p07_session()
  ctx = prompt_ctx(s)
  expect_error(with_prompt_input(ctx, list(a = 1), function() stop("boom")), "boom")
  expect_length(prompt_frames$stack, 0L)
})

test_that("prompt_truncate cuts at a line boundary and appends the notice", {
  txt = paste(rep("alpha beta gamma delta epsilon zeta eta theta iota kappa", 40),
              collapse = "\n")
  out = prompt_truncate(txt, 60, "[cut]")
  expect_match(out, "\n\\[cut\\]$")
  kept = sub("\n\\[cut\\]$", "", out)
  expect_true(startsWith(txt, kept))
  expect_lte(prompt_est(out), 65)
  expect_identical(prompt_truncate("short", 60, "[cut]"), "short")
})

test_that("prompt_path walks from the root to the leaf", {
  s = p07_session()
  session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(i = 1L)))
  session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(i = 2L)))
  p = Filter(function(e) identical(e$custom_type, "gptr.test"), prompt_path(s))
  expect_identical(vapply(p, function(e) as.integer(e$data$i), 0L), c(1L, 2L))
})

test_that("prompt_path leaves sibling branches out and survives torn lines and cycles", {
  tests_of = function(s) {
    p = Filter(function(e) identical(e$custom_type, "gptr.test"), prompt_path(s))
    vapply(p, function(e) as.character(e$data$x), "")
  }
  add = function(s, x) {
    session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(x = x)))
  }
  # a branch: B is a sibling of C once the leaf moves back to A (file order A, B, C)
  s = p07_session()
  a = add(s, "A")
  add(s, "B")
  d = session_data(s)
  d$leaf = a
  add(s, "C")
  expect_identical(tests_of(s), c("A", "C"))
  # a torn middle line (skipped at resume): the walk continues with the previous entry
  s = p07_session()
  add(s, "X")
  y = add(s, "Y")
  add(s, "Z")
  d = session_data(s)
  ids = vapply(d$entries, function(e) e$id, "")
  d$entries = d$entries[ids != y]
  expect_identical(tests_of(s), c("X", "Z"))
  # a parent cycle stops at the first repeated entry
  s = p07_session()
  p = add(s, "P")
  q = add(s, "Q")
  d = session_data(s)
  ids = vapply(d$entries, function(e) e$id, "")
  d$entries[[match(p, ids)]]$parent_id = q
  expect_identical(vapply(prompt_path(s), function(e) e$id, ""), c(p, q))
  # an unknown leaf has no path
  d$leaf = "no-such-id"
  expect_length(prompt_path(s), 0L)
})

test_that("prompt_read_file normalises line ends, the BOM and trailing newlines", {
  f = withr::local_tempfile(fileext = ".md")
  writeBin(charToRaw("\xef\xbb\xbf# Rules\r\n- one\r\n\r\n"), f)
  expect_identical(prompt_read_file(f), "# Rules\n- one")
})

test_that("prompt_specs keeps the winning record of each name, in order", {
  s = p07_session()
  sid = session_data(s)$id
  off1 = gptr_register(gptr_prompt_section("zz_late", "late", tier = "T1", order = 990L))
  off2 = gptr_register(gptr_prompt_section("aa_early", "early", tier = "T0", order = 50L))
  withr::defer({
    off1()
    off2()
  })
  registry_add(gptr_prompt_section("zz_late", "session override", tier = "T1", order = 990L),
               source = "session", rank = 0L, session = sid)
  specs = prompt_specs("prompt_section", sid)
  nm = vapply(specs, function(x) x$name, "")
  expect_identical(sum(nm == "zz_late"), 1L)
  expect_identical(specs[[which(nm == "zz_late")]]$text, "session override")
  ord = vapply(specs, function(x) as.numeric(x$order), 0)
  expect_false(is.unsorted(ord))
  expect_identical(nm[1], "aa_early")
  other = prompt_specs("prompt_section", NULL)
  hit = Filter(function(x) identical(x$name, "zz_late"), other)
  expect_identical(hit[[1]]$text, "late")
})

test_that("operator messages wait in the session memo until they are flushed", {
  s = p07_session()
  prompt_pending_add(s, msg_operator("reminder", "a note"))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(q[[1]]$kind, "reminder")
  e = prompt_operator_entry(q[[1]])
  expect_identical(e$type, "custom_message")
  expect_identical(e$custom_type, "gptr.operator")
  expect_identical(e$message, q[[1]])
  expect_identical(prompt_pending_flush(s), 1L)
  expect_length(pending_of(s), 0L)
  path = prompt_path(s)
  last = path[[length(path)]]
  expect_identical(last$custom_type, "gptr.operator")
  expect_identical(prompt_entry_operator(last)$kind, "reminder")
  # P06's store writes the kernel shape as the Pi custom_message line (contract section 4.6)
  line = json_decode(json_encode(entry_to_json(last)))
  expect_identical(line$customType, "gptr.operator")
  expect_identical(line$details$kind, "reminder")
  expect_identical(line$content[[1]]$text, "a note")
})

test_that("operator entries are read in the kernel shape and the flat Pi shape", {
  op = msg_operator("steer_relay", "relay text", origin_text = "use TPM")
  kernel = list(type = "custom_message", custom_type = "gptr.operator", message = op)
  expect_identical(prompt_entry_operator(kernel), op)
  flat = list(type = "custom_message", custom_type = "gptr.operator",
              content = list(block_text("a"), block_text("b")),
              details = list(kind = "mode", origin_text = NULL))
  got = prompt_entry_operator(flat)
  expect_identical(got$kind, "mode")
  expect_identical(prompt_operator_text(got), "a\n\nb")
  expect_null(prompt_entry_operator(list(type = "custom", custom_type = "gptr.test")))
  expect_null(prompt_entry_operator(list(type = "message", message = msg_user("x"))))
})

test_that("trust and the bound document fall back before P08 and P15 exist", {
  s = p07_session()
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  expect_false(prompt_trusted(tempdir()))
  expect_null(prompt_doc(s))
})
