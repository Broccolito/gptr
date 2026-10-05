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

# ---- Task 12: replay decisions and replaying fresh blocks (IC-45, IC-46, IC-47, IC-74) --------

# A located site whose call owns a block in the given state (as doc_locate() builds it)
doc_decide_site = function(status = "fresh", driver = "base", prompt = "p", args = NULL) {
  header = list(model = "fake/fake-1", prompt = prompt_hash(prompt), args = args)
  header = header[!vapply(header, is.null, NA)]
  if (identical(status, "undone")) header$status = "undone"
  list(path = file.path(getwd(), "a.R"), format = "r", driver = driver, template = prompt,
       block = list(id = "abc123", header = header, status = status))
}

# A file with one top-level call and its block; returns the located site of that call
doc_replay_fixture = function(prompt = "count rows", header = list(), body = "n = nrow(mtcars)") {
  f = file.path(getwd(), "a.R")
  h = utils::modifyList(list(model = "fake/fake-1", date = "2026-09-29",
                             prompt = prompt_hash(prompt), session = "s0a1b2c3d4e", turn = 1L),
                        header)
  writeLines(c(paste0("res = gptr(\"", prompt, "\")"), doc_render_block("abc123", h, body)), f)
  calls = doc_calls(readLines(f))
  site = list(kind = "srcref", path = path_norm(f), format = "r", backend = "file",
              driver = "base", template = prompt, prompt_hash = prompt_hash(prompt),
              args_hash = NULL, anchor = doc_anchor_of(calls, calls[1, ]))
  loc = doc_text_locate(readLines(f), site)
  site$block = loc$owned
  site$top_level = TRUE
  site
}

# A call record as P08 builds it (only the bindings P15 reads)
doc_test_call = function(session = NULL, envir = new.env(), prompt = "count rows") {
  call = new.env(parent = emptyenv())
  call$session = session
  call$envir = envir
  call$template = prompt
  call$prompt = prompt
  call$args = list(replay = NULL)
  call$doc = NULL
  call
}

# Give the calling test its own replay table (P06's the$replay_blocks), restored afterwards, so
# the sessions a test binds to block ids do not outlive it
local_replay_table = function(.env = parent.frame()) {
  old = the$replay_blocks
  the$replay_blocks = new.env(parent = emptyenv())
  withr::defer(assign("replay_blocks", old, envir = the), envir = .env)
  invisible(the$replay_blocks)
}

test_that("doc_decide() follows the replay table, the args hash and the undone row", {
  local_project()
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "auto"), "replay")
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "replay"), "replay")
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "record"), "replay")
  expect_identical(doc_decide(doc_decide_site(driver = "gptr_source"), prompt_hash("p"), NULL,
                              "live"), "regenerate")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "live"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  expect_identical(doc_decide(doc_decide_site(driver = "knitr"), prompt_hash("q"), NULL, "auto"),
                   "regenerate")
  expect_error(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "replay"),
               class = "gptr_error_stale_block")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "auto"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "record"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  a = doc_decide_site(args = "aaaa1111")
  expect_identical(doc_decide(a, prompt_hash("p"), "aaaa1111", "auto"), "replay")
  expect_error(doc_decide(a, prompt_hash("p"), "bbbb2222", "replay"),
               class = "gptr_error_stale_block")
  none = doc_decide_site()
  none$block = NULL
  expect_identical(doc_decide(none, prompt_hash("p"), NULL, "auto"), "run")
  cnd = expect_error(doc_decide(none, prompt_hash("p"), NULL, "replay"),
                     class = "gptr_error_not_recorded")
  expect_identical(cnd$prompt, "p")
  u = doc_decide_site("undone", driver = "gptr_source")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "auto"), "skip")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "replay"), "skip")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "live"), "run")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "record"), "regenerate")
  e = doc_decide_site("user-edited", driver = "gptr_source")
  expect_identical(doc_decide(e, prompt_hash("p"), NULL, "auto"), "replay")
  local_gptr_options(interactive = FALSE)
  expect_warning(expect_identical(doc_decide(e, prompt_hash("p"), NULL, "record"), "replay"),
                 class = "gptr_warning_replay_downgraded")
  expect_error(doc_decide(none, prompt_hash("p"), NULL, "sometimes"),
               class = "gptr_error_invalid_argument")
})

test_that("a piped session is advanced in place; identical() holds along a replayed chain", {
  local_project()
  site = doc_replay_fixture()
  s = session_new("fake/fake-1", "auto", home = new.env())
  call = doc_test_call(session = s)
  out = doc_replay_call(call, site)
  expect_identical(out, s)
  expect_identical(session_data(s)$seen, "abc123")
  expect_identical(session_data(s)$turns, 1L)
  expect_null(call$doc)
  again = doc_replay_call(doc_test_call(session = s), site)
  expect_identical(again, s)
  expect_identical(session_data(s)$turns, 1L)
})

test_that("without a piped session the replayed session is reconstructed from the document", {
  local_project()
  site = doc_replay_fixture(header = list(value = "n"),
                            body = c("n = nrow(mtcars)", "#> [1] 32", "## Decision: count"))
  rel = doc_rel(site$path)
  s2_put(s2_key(rel, "abc123", "", prompt_hash("count rows"), ""),
         list(block = "abc123", doc = rel, part = "", answer = "There are 32 rows."))
  env = new.env()
  s = doc_replay_call(doc_test_call(envir = env), site)
  d = session_data(s)
  expect_identical(d$id, "s0a1b2c3d4e")
  expect_identical(d$last_text, "There are 32 rows.")
  expect_identical(d$history_source, "reconstructed")
  msgs = lapply(Filter(function(e) identical(e$type, "message"), d$entries), function(e) e$message)
  expect_identical(msg_text(msgs[[1]]), "count rows")
  expect_identical(msgs[[2]]$content[[1]]$arguments$code, "n = nrow(mtcars)")
  expect_identical(msg_text(msgs[[3]]), "[1] 32")
  expect_identical(msg_text(msgs[[4]]), "There are 32 rows.")
  env$n = 32L
  expect_identical(s$value, 32L)
})

test_that("a fork block is bound to its id for gptr_resume(block =)", {
  local_project()
  local_replay_table()
  site = doc_replay_fixture(header = list(fork = "s0a1b2c3d4e:1", session = "s9f8e7d6c5b"))
  home = new.env()
  s = doc_replay_call(doc_test_call(envir = home), site)
  expect_identical(gptr_resume(block = "abc123"), s)
  expect_false(identical(gptr_resume(block = "abc123")$envir, home))
  expect_identical(parent.env(gptr_resume(block = "abc123")$envir), home)
})

test_that("block-nested calls replay from S2 and miss with not_recorded only under replay", {
  local_project()
  f = file.path(getwd(), "a.R")
  ph = prompt_hash("outer")
  writeLines(c("gptr(\"outer\")", paste0("# >>> gptr:abc123 model=m prompt=", ph),
               "sub = gptr(\"inner\")", "# <<< gptr:abc123"), f)
  site = list(path = path_norm(f), format = "r", in_block = "abc123", ordinal = 1L,
              template = "inner")
  expect_s3_class(doc_run_block_nested(doc_test_call(), site, "auto"), "gptr_route_pass")
  expect_error(doc_run_block_nested(doc_test_call(), site, "replay"),
               class = "gptr_error_not_recorded")
  s2_put(s2_key("a.R", "abc123", "n1", ph, ""),
         list(block = "abc123", doc = "a.R", part = "n1", model = "fake/fake-1",
              answer = "inner answer", session = "s1111111111", turn = 1L))
  s = doc_run_block_nested(doc_test_call(), site, "replay")
  expect_identical(session_data(s)$last_text, "inner answer")
  expect_identical(session_data(s)$id, "s1111111111")
  s2_put(s2_key("a.R", "abc123", "n1", ph, ""),
         list(block = "abc123", doc = "a.R", part = "n1", model = "fake/fake-1",
              answer = "inner answer", session = "s1111111111", turn = 1L,
              sent = prompt_hash("inner")))
  again = doc_run_block_nested(doc_test_call(prompt = "inner"), site, "replay")
  expect_identical(session_data(again)$last_text, "inner answer")
  expect_error(doc_run_block_nested(doc_test_call(prompt = "another prompt"), site, "replay"),
               class = "gptr_error_not_recorded")
  expect_s3_class(doc_run_block_nested(doc_test_call(), site, "live"), "gptr_route_pass")
})

test_that("a team block replays its children from S2 into overlays, with zero requests", {
  local_project()
  local_replay_table()
  site = doc_replay_fixture(prompt = "Review", header = list(
    kind = "team", session = "s7777777777", children = "code:s2222222222,stats:s3333333333"))
  ph = prompt_hash("Review")
  s2_put(s2_key("a.R", "abc123", "code", ph, ""),
         list(block = "abc123", doc = "a.R", part = "code", model = "openai/gpt-5.5",
              answer = "Two bugs.", session = "s2222222222", turn = 1L))
  s2_put(s2_key("a.R", "abc123", "stats", ph, ""),
         list(block = "abc123", doc = "a.R", part = "stats", model = "anthropic/claude-opus-5-5",
              answer = "Looks fine.", session = "s3333333333", turn = 1L))
  env = new.env()
  team = doc_replay_team(doc_test_call(envir = env, prompt = "Review"), site, "replay")
  code = gptr_resume(block = "abc123", child = "code")
  expect_identical(session_data(code)$last_text, "Two bugs.")
  expect_identical(parent.env(code$envir), env)
  expect_identical(session_data(gptr_resume(block = "abc123", child = "stats"))$id, "s3333333333")
  expect_identical(gptr_resume(block = "abc123"), team)
  expect_match(session_data(team)$last_text, "### code (openai/gpt-5.5)\nTwo bugs.", fixed = TRUE)
})

test_that("replay calls no provider, runs no discovery and keeps local provenance (IC-74)", {
  local_project()
  local_replay_table()
  # Counted as well as refused: P06's model_canonical() and the HTTP reactor catch errors, so a
  # refusal alone could be swallowed
  hits = new.env()
  hits$n = 0L
  refuse = function(...) {
    hits$n = hits$n + 1L
    stop("replay reached a provider or model discovery")
  }
  testthat::local_mocked_bindings(catalog_discover = refuse, catalog_ollama_discover = refuse,
                                  model_prepare = refuse, http_handle = refuse)
  site = doc_replay_fixture(prompt = "Classify", header = list(
    model = "ollama/qwen3:8b", kind = "fanout", session = "s4444444444",
    children = "liver:s5555555555"))
  ph = prompt_hash("Classify")
  s2_put(s2_key("a.R", "abc123", "liver", ph, ""),
         list(block = "abc123", doc = "a.R", part = "liver", model = "ollama/qwen3:8b",
              provider = "ollama", model_digest = paste0("sha256:", strrep("0a", 32)),
              locality = "local", answer = "Yes.", session = "s5555555555", turn = 1L))
  fan = doc_replay_team(doc_test_call(prompt = "Classify"), site, "replay")
  child = gptr_resume(block = "abc123", child = "liver")
  expect_identical(session_data(child)$model, "ollama/qwen3:8b")
  expect_identical(session_data(child)$last_text, "Yes.")
  msgs = lapply(Filter(function(e) identical(e$type, "message"), session_data(child)$entries),
                function(e) e$message)
  last = msgs[[length(msgs)]]
  expect_identical(c(last$provider, last$model), c("ollama", "qwen3:8b"))
  expect_identical(session_data(fan)$model, "ollama/qwen3:8b")
  expect_identical(gptr_resume(block = "abc123"), fan)
  one = doc_replay_fixture(prompt = "Summarise", header = list(model = "ollama/qwen3:8b"))
  piped = session_new("ollama/qwen3:8b", "auto", home = new.env())
  expect_identical(doc_replay_call(doc_test_call(session = piped, prompt = "Summarise"), one),
                   piped)
  expect_identical(session_data(piped)$turns, 1L)
  expect_identical(hits$n, 0L)
})

test_that("an S2 record whose answer is empty or not text replays without an answer", {
  local_project()
  site = doc_replay_fixture()
  s2_put(s2_key("a.R", "abc123", "", prompt_hash("count rows"), ""),
         list(block = "abc123", doc = "a.R", part = ""))
  s = session_new("fake/fake-1", "auto", home = new.env())
  expect_identical(doc_replay_call(doc_test_call(session = s), site), s)
  expect_identical(session_data(s)$last_text, NA_character_)
  f = s2_path(s2_key("a.R", "abc123", "n1", prompt_hash("count rows"), ""))
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLines("{\"answer\": 42, \"model\": \"fake/fake-1\"}", f)
  nested = list(path = site$path, format = "r", in_block = "abc123", ordinal = 1L,
                template = "inner")
  out = doc_run_block_nested(doc_test_call(), nested, "replay")
  d = session_data(out)
  expect_identical(d$history_source, "reconstructed")
  expect_identical(d$last_text, NA_character_)
  msgs = Filter(function(e) identical(e$type, "message"), d$entries)
  expect_match(msg_text(msgs[[length(msgs)]]$message), "was not recorded", fixed = TRUE)
})

test_that("a stale block under replay is a not_recorded error naming its document and block", {
  local_project()
  cnd = expect_error(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "replay"),
                     class = "gptr_error_not_recorded")
  expect_s3_class(cnd, "gptr_error_stale_block")
  expect_identical(cnd$block, "abc123")
  expect_identical(cnd$document, file.path(getwd(), "a.R"))
})

test_that("doc_skip_old() marks the old block in the gptr_source() frame of its document only", {
  local_project()
  site = doc_decide_site(driver = "gptr_source")
  outer = doc_source_push(file.path(getwd(), "b.R"))
  withr::defer(doc_source_pop(outer))
  doc_skip_old(site)
  expect_identical(doc_state()$sources[[outer]]$skip, character())
  inner = doc_source_push(site$path)
  doc_skip_old(site)
  doc_skip_old(site)
  doc_skip_old(doc_decide_site(driver = "base"))
  expect_identical(doc_state()$sources[[inner]]$skip, "abc123")
  site$block = NULL
  expect_invisible(doc_skip_old(site))
  expect_identical(doc_state()$sources[[inner]]$skip, "abc123")
})

test_that("a notebook agent cell gives the code and outputs a replay reconstructs", {
  local_project()
  f = file.path(getwd(), "a.ipynb")
  writeLines(c("{", " \"cells\": [", "  {", "   \"cell_type\": \"code\",",
               "   \"execution_count\": null,", "   \"id\": \"gptr-abc123\",",
               "   \"metadata\": {\"gptr\": {\"id\": \"abc123\"}},", "   \"outputs\": [],",
               "   \"source\": [\"n = nrow(mtcars)\\n\", \"#> [1] 32\"]", "  }", " ],",
               " \"metadata\": {},", " \"nbformat\": 4,", " \"nbformat_minor\": 5", "}"), f)
  site = list(path = path_norm(f), format = "ipynb", template = "count rows")
  expect_identical(doc_block_text(site, "abc123"), c("n = nrow(mtcars)", "#> [1] 32"))
  doc = doc_replay_doc(site, doc_test_call(), "abc123", "It is 32.")
  expect_identical(doc$code, "n = nrow(mtcars)")
  expect_identical(doc$output, "[1] 32")
  expect_identical(doc$text, "It is 32.")
  expect_identical(doc_block_text(site, "ffffff"), character())
  site$path = file.path(getwd(), "missing.R")
  site$format = "r"
  expect_identical(doc_block_text(site, "abc123"), character())
})

test_that("a hand-edited block is overwritten in live or record only after a yes", {
  local_project()
  local_gptr_options(interactive = TRUE)
  asked = new.env()
  asked$n = 0L
  asked$answer = "y"
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    asked$answer
  })
  e = doc_decide_site("user-edited", driver = "gptr_source")
  expect_identical(doc_decide(e, prompt_hash("p"), NULL, "live"), "regenerate")
  expect_identical(doc_decide(e, prompt_hash("p"), NULL, "record"), "regenerate")
  expect_identical(doc_decide(e, prompt_hash("p"), NULL, "auto"), "replay")
  expect_identical(asked$n, 2L)
  asked$answer = "n"
  expect_warning(expect_identical(doc_decide(e, prompt_hash("p"), NULL, "record"), "replay"),
                 class = "gptr_warning_replay_downgraded")
  expect_identical(asked$n, 3L)
  # Under base source()/Rscript a yes could not be honoured, so nothing is asked
  asked$answer = "y"
  for (mode in c("live", "record")) {
    w = expect_warning(expect_identical(doc_decide(doc_decide_site("user-edited"),
                                                   prompt_hash("p"), NULL, mode), "replay"),
                       class = "gptr_warning_replay_downgraded")
    expect_match(conditionMessage(w), "under source() or Rscript", fixed = TRUE)
  }
  expect_identical(asked$n, 3L)
})

test_that("a hand-edited block whose prompt or args changed is stale, never replayed silently", {
  local_project()
  local_gptr_options(interactive = TRUE)
  asked = new.env()
  asked$n = 0L
  asked$answer = "n"
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    asked$answer
  })
  e = doc_decide_site("user-edited", driver = "gptr_source", args = "aaaa1111")
  # Under replay a changed prompt or args errors stale_block (IC-45), edited or not
  cnd = expect_error(doc_decide(e, prompt_hash("q"), "aaaa1111", "replay"),
                     class = "gptr_error_stale_block")
  expect_s3_class(cnd, "gptr_error_not_recorded")
  expect_identical(cnd$block, "abc123")
  expect_identical(cnd$document, file.path(getwd(), "a.R"))
  expect_error(doc_decide(e, prompt_hash("p"), "bbbb2222", "replay"),
               class = "gptr_error_stale_block")
  expect_error(doc_decide(doc_decide_site("user-edited"), prompt_hash("p"), "bbbb2222",
                          "replay"), class = "gptr_error_stale_block")
  # Unchanged prompt and args: the user's code wins, silently
  expect_no_warning(expect_identical(doc_decide(e, prompt_hash("p"), "aaaa1111", "replay"),
                                     "replay"))
  expect_no_warning(expect_identical(doc_decide(e, prompt_hash("p"), "aaaa1111", "auto"),
                                     "replay"))
  expect_identical(asked$n, 0L)
  # auto under base source()/Rscript: a downgrade with a warning, nothing asked
  w = expect_warning(expect_identical(doc_decide(doc_decide_site("user-edited", args = "aaaa1111"),
                                                 prompt_hash("p"), "bbbb2222", "auto"), "replay"),
                     class = "gptr_warning_replay_downgraded")
  expect_match(conditionMessage(w), "under source() or Rscript", fixed = TRUE)
  expect_identical(asked$n, 0L)
  # auto under a driver that can regenerate: asked; a yes regenerates, a no warns and replays
  asked$answer = "y"
  expect_identical(doc_decide(e, prompt_hash("p"), "bbbb2222", "auto"), "regenerate")
  expect_identical(asked$n, 1L)
  asked$answer = "n"
  w = expect_warning(expect_identical(doc_decide(e, prompt_hash("q"), "aaaa1111", "auto"),
                                      "replay"), class = "gptr_warning_replay_downgraded")
  expect_match(conditionMessage(w), "prompt or interpolated values changed", fixed = TRUE)
  expect_identical(asked$n, 2L)
  asked$answer = "y"
  for (mode in c("live", "record")) {
    expect_identical(doc_decide(e, prompt_hash("q"), "aaaa1111", mode), "regenerate",
                     label = mode)
  }
  expect_identical(asked$n, 4L)
  # Without a human to ask: the warning, never a silent replay
  local_gptr_options(interactive = FALSE)
  for (mode in c("auto", "live", "record")) {
    expect_warning(expect_identical(doc_decide(e, prompt_hash("p"), "bbbb2222", mode), "replay",
                                    label = mode), class = "gptr_warning_replay_downgraded")
  }
  expect_identical(asked$n, 4L)
})

test_that("an undone block is regenerated under record by any driver, without a downgrade", {
  local_project()
  for (driver in c("base", "gptr_source", "knitr")) {
    u = doc_decide_site("undone", driver = driver)
    for (ph in c(prompt_hash("p"), prompt_hash("q"))) {
      expect_no_warning(expect_identical(doc_decide(u, ph, NULL, "record"), "regenerate",
                                         label = paste("record under", driver)))
    }
    expect_identical(doc_decide(u, prompt_hash("q"), NULL, "auto"), "skip", label = driver)
    expect_identical(doc_decide(u, prompt_hash("q"), NULL, "replay"), "skip", label = driver)
    expect_identical(doc_decide(u, prompt_hash("q"), NULL, "live"), "run", label = driver)
  }
})

test_that("children entries without a name or a session id are skipped", {
  local_project()
  local_replay_table()
  site = doc_replay_fixture(prompt = "Review", header = list(
    kind = "team", session = "s6666666666", children = ":s9999999999,code:,stats:s8888888888"))
  team = doc_replay_team(doc_test_call(prompt = "Review"), site, "replay")
  expect_identical(session_data(gptr_resume(block = "abc123", child = "stats"))$id, "s8888888888")
  expect_error(gptr_resume(block = "abc123", child = "code"), class = "gptr_error_replay_unbound")
  expect_identical(gptr_resume(block = "abc123"), team)
  expect_identical(session_data(team)$last_text, "### stats (fake/fake-1)\n")
})
