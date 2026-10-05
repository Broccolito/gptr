# Tests for R/doc-replay.R (plan P15): consent, S2, decisions, the route, services, hooks, the
# exports, and the end-to-end record/replay acceptance of 05 P15.

# Bind a document for the calling test (restores the previous binding)
local_doc_binding = function(path, format = "r", .env = parent.frame()) {
  old = the$doc_binding
  the$doc_binding = list(path = path_norm(path), format = format)
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  invisible(path)
}

test_that("write consent comes from the binding, record = auto, a remembered answer or a yes", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines("x = 1", f)
  local_gptr_options(record = NULL, interactive = FALSE)
  expect_false(doc_consent(f))
  expect_false(doc_consent_possible(f))
  local({
    local_doc_binding(f)
    expect_true(doc_consent(f))
  })
  expect_false(doc_consent(f))
  local({
    local_gptr_options(record = "auto")
    expect_true(doc_consent(f))
  })
  local({
    local_gptr_options(record = "off")
    local_doc_binding(f)
    expect_true(doc_consent(f))
  })
  doc_project_remember("a.R", "auto")
  expect_true(doc_consent(f))
  doc_project_remember("a.R", "off")
  expect_false(doc_consent(f))
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  doc_project_transcript(".gptr/transcripts/t.R")
  expect_true(doc_consent(t))
})

test_that("an interactive yes is asked once and remembered per document", {
  proj = local_project()
  g = file.path(proj, "b.R")
  writeLines("y = 1", g)
  local_gptr_options(record = NULL, interactive = TRUE)
  expect_true(doc_consent_possible(g))
  asked = new.env()
  asked$n = 0L
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    "y"
  })
  expect_true(doc_consent(g))
  expect_identical(doc_project_get()$record$b.R, "auto")
  expect_true(doc_consent(g))
  expect_identical(asked$n, 1L)
})

test_that("model code cannot call a control export during a run unless approved (IC-53)", {
  expect_invisible(doc_control_guard("gptr_doc"))
  run = new.env()
  run$session = "s0123456789"
  run$signal = new.env()
  testthat::local_mocked_bindings(run_current = function() run)
  cnd = expect_error(doc_control_guard("gptr_doc"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_doc")
  run$signal$control = "gptr_doc"
  expect_invisible(doc_control_guard("gptr_doc"))
  expect_error(doc_control_guard("gptr_doc"), class = "gptr_error_permission")
})

test_that("S2 answers round-trip under keys that include the args hash and part", {
  local_project()
  k1 = s2_key("a.R", "abc123", "", "p", "")
  k2 = s2_key("a.R", "abc123", "", "p", "aaaa1111")
  k3 = s2_key("a.R", "abc123", "n1", "p", "")
  expect_false(identical(k1, k2))
  expect_false(identical(k1, k3))
  expect_identical(s2_key("a.R", "abc123", "", "p", NULL), k1)
  expect_match(k1, "^[0-9a-f]{64}$")
  s2_put(k1, list(block = "abc123", doc = "a.R", part = "", answer = "It is 32."))
  expect_identical(s2_get(k1)$answer, "It is 32.")
  expect_null(s2_get(k2))
  expect_identical(s2_path(k1), file.path(workspace_dir(), "cache", "s2", substr(k1, 1, 2),
                                          paste0(k1, ".json")))
})

# ---- Task 7 additions (contract 2.2, 11.9; IC-53, IC-74; dev/DEVIATIONS.md D-100) ------------

test_that("a control refusal names the running tool, risk 4 and the session (IC-53)", {
  run = new.env()
  run$session = "s0123456789"
  run$signal = new.env()
  testthat::local_mocked_bindings(run_current = function() run)
  cnd = expect_error(doc_control_guard("gptr_cache"), class = "gptr_error_permission")
  expect_identical(cnd$tool, "r")
  expect_identical(cnd$risk, 4L)
  expect_identical(cnd$session, "s0123456789")
  expect_true(nzchar(cnd$how_to_allow))
  run$tool_call = list(name = "r_background", id = "c1")
  cnd = expect_error(doc_control_guard("gptr_cache"), class = "gptr_error_permission")
  expect_identical(cnd$tool, "r_background")
  run$signal$control = c("gptr_doc", "gptr_cache")
  expect_invisible(doc_control_guard("gptr_cache"))
  expect_identical(run$signal$control, "gptr_doc")
})

test_that("an S2 answer is redacted at ingress and its provenance fields are kept (IC-74)", {
  local_project()
  k = s2_key("a.R", "abc123", "", "p", "")
  rec = list(block = "abc123", doc = "a.R", part = "", prompt = "p", model = "ollama/qwen3:8b",
             provider = "ollama", model_digest = paste0("sha256:", strrep("0a", 32)),
             locality = "local", images = list(list(sha256 = strrep("b", 64), mime = "image/png")),
             answer = "Authorization: Bearer FAKEtoken1234567890abcdef",
             usage = list(input_tokens = 12L, output_tokens = 3L), cost = 0, session = "s1",
             turn = 2L, date = "2026-10-04T10:00:00Z")
  s2_put(k, rec)
  got = s2_get(k)
  expect_identical(got$answer, "Authorization: Bearer [secret:auth-header]")
  expect_false(grepl("FAKEtoken", paste(readLines(s2_path(k), encoding = "UTF-8"),
                                        collapse = "\n"), fixed = TRUE))
  rec$answer = NULL
  got$answer = NULL
  expect_equal(got, rec)
})

test_that("an unreadable or non-object S2 file is a miss", {
  local_project()
  k = s2_key("a.R", "abc123", "", "p", "")
  dir.create(dirname(s2_path(k)), recursive = TRUE)
  writeLines("{not json", s2_path(k))
  expect_null(s2_get(k))
  writeLines("\"It is 32.\"", s2_path(k))
  expect_null(s2_get(k))
})

test_that("a project file whose record or transcript entry is not an object is ignored", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines("x = 1", f)
  local_gptr_options(record = NULL, interactive = FALSE)
  settings_write("user_project", list(transcript = "a.R", record = "auto"))
  expect_false(doc_consent(f))
  expect_false(doc_consent_possible(f))
  local({
    local_gptr_options(interactive = TRUE)
    expect_true(doc_consent_possible(f))
  })
  settings_write("user_project", list(transcript = list(target = c("a.R", "b.R"))))
  expect_false(doc_consent(f))
  expect_false(doc_consent_possible(f))
})

test_that("a remembered transcript target is consent only where IC-52 allows a target", {
  proj = local_project()
  local_gptr_options(record = NULL, interactive = FALSE)
  out = file.path(dirname(proj), "outside.R")
  doc_project_transcript("../outside.R")
  expect_false(doc_consent(out))
  doc_project_transcript(path_norm(out))
  expect_false(doc_consent(out))
  for (rel in c(".gptr/extensions/x.R", ".secrets/x.R", ".gptr/skills/x.R", "notes.txt")) {
    doc_project_transcript(rel)
    expect_false(doc_consent(file.path(proj, rel)), label = rel)
  }
  doc_project_transcript("analysis.R")
  expect_true(doc_consent(file.path(proj, "analysis.R")))
})
