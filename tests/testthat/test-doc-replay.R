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
  writeLines(c(paste0("res = peter(\"", prompt, "\")"), doc_render_block("abc123", h, body)), f)
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
  writeLines(c("peter(\"outer\")", paste0("# >>> gptr:abc123 model=m prompt=", ph),
               "sub = peter(\"inner\")", "# <<< gptr:abc123"), f)
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

# ---- Task 13: the document route, the doc.* services and the hooks (IC-45..IC-49) -------------

# A session with recorded turns, built the way P06 records them: the turn counter moves first,
# then the turn's entries are appended (user messages carry their turn number)
doc_test_session = function(turns, mode = "auto", kind = "chat", home = new.env()) {
  s = session_new("fake/fake-1", mode, home = home, kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, outputs = character(), prompt = "count rows",
                         answer = "There are 32 rows.", id = "call_1") {
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call(id, "r", list(code = code))), api = "fake", provider = "fake",
      model = "fake-1", stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      id, "r", "ok", details = list(code = code, status = "ok", outputs = outputs))),
    list(type = "message", message = msg_assistant(answer, api = "fake", provider = "fake",
                                                   model = "fake-1"))
  )
}

# An environment whose peter() builds the call record as P08 does and runs only the document
# route: it returns the route's value, or list(pass = TRUE, doc = <call$doc>) when it passes
doc_route_env = function(session = NULL) {
  e = new.env()
  e$peter = function(prompt, ..., replay = NULL) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = session
    call$envir = parent.frame()
    call$args = list(replay = replay)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (!doc_route_match(call)) return(list(pass = TRUE, matched = FALSE, doc = NULL))
    res = doc_route_run(call)
    if (inherits(res, "gptr_route_pass")) return(list(pass = TRUE, matched = TRUE, doc = call$doc))
    res
  }
  e
}

test_that("the route replays a fresh block, passes a new call with its site, skips nested ones", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("fresh = peter(\"count rows\")",
               paste0("# >>> gptr:abc123 model=fake/fake-1 prompt=", ph,
                      " session=s0a1b2c3d4e turn=1"),
               "n = 32", "# <<< gptr:abc123", "new = peter(\"plot it\")",
               "f = function() peter(\"inside\")", "inner = f()"), f)
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_s3_class(e$fresh, "gptr_session")
  expect_identical(session_data(e$fresh)$id, "s0a1b2c3d4e")
  expect_identical(e$n, 32)
  expect_true(e$new$pass)
  expect_identical(e$new$doc$path, path_norm(f))
  expect_identical(e$new$doc$prompt_hash, prompt_hash("plot it"))
  expect_false(e$inner$matched)
})

test_that("without consent or under replay the route keeps no site; replay needs no consent", {
  local_project()
  local_gptr_options(record = "off", interactive = FALSE, replay = "auto")
  f = file.path(getwd(), "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("fresh = peter(\"count rows\")",
               paste0("# >>> gptr:abc123 model=fake/fake-1 prompt=", ph), "n = 32",
               "# <<< gptr:abc123", "new = peter(\"plot it\")"), f)
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_s3_class(e$fresh, "gptr_session")
  expect_true(e$new$pass)
  expect_null(e$new$doc)
  local_gptr_options(record = "auto", replay = "replay")
  e2 = doc_route_env()
  source(f, local = e2, keep.source = TRUE)
  expect_null(e2$new$doc)
})

test_that("a stale block regenerates under gptr_source() and errors under replay", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("s = peter(\"count rows again\")",
               paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count rows")),
               "n = 32", "# <<< gptr:abc123"), f)
  e = doc_route_env()
  withr::with_options(list(gptr.replay = "replay"), {
    expect_error(source(f, local = e, keep.source = TRUE), class = "gptr_error_stale_block")
  })
  depth = doc_source_push(f)
  withr::defer(doc_source_pop(depth))
  local_gptr_options(replay = "auto")
  source(f, local = e, keep.source = TRUE)
  expect_true(e$s$pass)
  expect_true(e$s$doc$regenerate)
  expect_identical(e$s$doc$block_id, "abc123")
  expect_identical(doc_state()$sources[[depth]]$skip, "abc123")
})

test_that("calls made from model code never match the route", {
  local_project()
  f = file.path(getwd(), "analysis.R")
  writeLines("x = peter(\"count rows\")", f)
  testthat::local_mocked_bindings(run_current = function() new.env())
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_false(e$x$matched)
})

test_that("agent_end writes the block of an idle run with a document site", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)", outputs = "[1] 32")))
  calls = doc_calls(readLines(f))
  site = list(kind = "srcref", path = path_norm(f), format = "r", backend = "file",
              anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = prompt_hash("count rows"),
              args_hash = NULL, template = "count rows", ordinal = 1L)
  doc_on_agent_end(list(status = "error", doc = site, turns = 1L), list(session = s))
  expect_identical(readLines(f), "peter(\"count rows\")")
  doc_on_agent_end(list(status = "idle", doc = site, turns = 1L), list(session = s))
  txt = readLines(f)
  expect_identical(txt[3:4], c("n = nrow(mtcars)", "#> [1] 32"))
  expect_match(txt[2], paste0("session=", session_data(s)$id, " turn=1"), fixed = TRUE)
  doc_on_agent_end(list(status = "idle", doc = NULL, turns = 1L), list(session = s))
  expect_identical(readLines(f), txt)
})

test_that("console turns become one steered session in the transcript (IC-49)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  s = doc_test_session(list(doc_test_turn("fit = lm(mpg ~ wt, data = mtcars)", prompt = "fit"),
                            doc_test_turn("p = predict(fit)", prompt = "predict")))
  for (k in 1:2) {
    site = doc_console_site(session_id = session_data(s)$id,
                            template = c("fit", "predict")[k])
    doc_on_agent_end(list(status = "idle", doc = site, turns = k), list(session = s))
  }
  tr = readLines(file.path(proj, ".gptr", "transcripts", "t.R"))
  hex = substr(sub("^s", "", session_data(s)$id), 1, 6)
  expect_true(paste0("s_", hex, " = peter(\"fit\")") %in% tr)
  expect_true(paste0("s_", hex, " |> peter(\"predict\")") %in% tr)
  expect_identical(sum(grepl("^# >>> gptr:", tr)), 2L)
})

test_that("doc.site answers the session's run site, else the gptr_doc() binding", {
  local_project()
  expect_null(doc_site_service(NULL))
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  bound = file.path(getwd(), "a.R")
  the$doc_binding = list(path = bound, format = "r")
  expect_identical(doc_site_service(NULL), list(path = bound, format = "r"))
  the$doc_binding = list(path = file.path(getwd(), "gone", "a.R"), format = "r")
  expect_null(doc_site_service(NULL))
  run = new.env()
  run$opts = list(doc = list(path = "/p/b.Rmd", format = "rmd"))
  testthat::local_mocked_bindings(session_live = function(s) list(run = run))
  s = doc_test_session(list())
  expect_identical(doc_site_service(s), list(path = "/p/b.Rmd", format = "rmd"))
  # P10's peter$edit() member passes no session: the running call's site answers
  outer = new.env()
  outer$opts = list(doc = list(path = "/p/c.R", format = "r"))
  testthat::local_mocked_bindings(run_current = function() outer)
  expect_identical(doc_site_service(NULL), list(path = "/p/c.R", format = "r"))
})

test_that("doc.edit goes through the edit tool, refreshes headers and protects hand edits", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  h = list(model = "m", date = "2020-01-01", prompt = "p", sha = doc_body_sha(body))
  writeLines(c("peter(\"p\")", doc_render_block("abc123", h, body), "y = 2"), f)
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = list(path = path_norm(f), format = "r")
  hits = new.env()
  hits$seen = character()
  edit_exec = function(input, ctx) {
    hits$seen = c(hits$seen, "execute")
    inner = doc_edit_service(input$path, input$edits, NULL)
    if (!is.null(inner)) return(inner)
    txt = readLines(input$path)
    for (e in input$edits) txt = sub(e$oldText, e$newText, txt, fixed = TRUE)
    writeLines(txt, input$path)
    gptr_tool_result("Successfully replaced text.")
  }
  off = gptr_register(gptr_spec("tool", "edit", description = "A test edit tool",
                                execute = edit_exec))
  withr::defer(off())
  expect_null(doc_edit_service(file.path(getwd(), "other.R"), list(), NULL))
  res = doc_edit_service(f, list(list(oldText = "x = 1", newText = "x = 2")), NULL)
  expect_false(res$is_error)
  expect_identical(hits$seen, "execute")
  b = doc_find_blocks(readLines(f))
  expect_identical(b$header[[1]]$sha, doc_body_sha("x = 2"))
  expect_identical(b$header[[1]]$date, format(Sys.Date(), "%Y-%m-%d"))
  txt = readLines(f)
  txt[3] = "x = 99 # mine"
  writeLines(txt, f)
  res2 = doc_edit_service(f, list(list(oldText = "x = 99", newText = "x = 3")), NULL)
  expect_true(res2$is_error)
  expect_identical(readLines(f)[3], "x = 99 # mine")
})

test_that("doc.s1_block writes one #> line below a top-level System 1 call, idempotently", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("is_rct = peter(\"Is this an RCT?\", abstracts, model = jev)", "table(is_rct)"), f)
  x = structure(c(TRUE, FALSE, TRUE), class = c("gptr_decision", "gptr_s1", "logical"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  e = new.env()
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_s1_block_service(call, x)
    x
  }
  source(f, local = e, keep.source = TRUE)
  txt = readLines(f)
  expect_identical(txt[3], "#> gptr_decision: 2 TRUE / 1 FALSE (jev-1.13.0, 2026-09-29)")
  expect_match(txt[2], "model=jev-1.13.0 date=2026-09-29", fixed = TRUE)
  source(f, local = e, keep.source = TRUE)
  expect_identical(readLines(f), txt)
  expect_identical(doc_s1_summary(structure(c("liver", "lung", "liver"),
                                            class = c("gptr_choice", "gptr_s1", "character"),
                                            meta = list(model = "jev", date = "2026-09-29"))),
                   "gptr_choice: liver 2, lung 1 (jev, 2026-09-29)")
})

test_that("doc.replay returns the replayed team of a fresh block and NULL otherwise (IC-47)", {
  local_project()
  local_replay_table()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "a.R")
  ph = prompt_hash("Review")
  writeLines(c("reviews = peter(\"Review\")", paste0("# >>> gptr:abc123 model=m prompt=", ph,
                                                    " session=s7777777777 turn=1 kind=team",
                                                    " children=\"code:s2222222222\""),
               "## Agent code (openai/gpt-5.5): Two bugs.", "# <<< gptr:abc123",
               "again = peter(\"Review two\")"), f)
  s2_put(s2_key("a.R", "abc123", "code", ph, ""),
         list(block = "abc123", doc = "a.R", part = "code", model = "openai/gpt-5.5",
              answer = "Two bugs.", session = "s2222222222", turn = 1L))
  e = new.env()
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$envir = parent.frame()
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    list(out = doc_replay_service(call), doc = call$doc)
  }
  source(f, local = e, keep.source = TRUE)
  expect_identical(session_data(e$reviews$out)$id, "s7777777777")
  expect_identical(session_data(gptr_resume(block = "abc123", child = "code"))$last_text,
                   "Two bugs.")
  expect_null(e$again$out)
  expect_identical(e$again$doc$prompt_hash, prompt_hash("Review two"))
})

test_that("a rewind makes abandoned blocks inert and notes it in the console transcript", {
  proj = local_project()
  local_gptr_options(record = "auto")
  f = file.path(proj, "a.R")
  body = "x = 1"
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  writeLines(c("peter(\"p\")", seg), f)
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  doc_project_transcript(".gptr/transcripts/t.R")
  dir.create(dirname(t), recursive = TRUE)
  writeLines("library(gptr)", t)
  s = doc_test_session(list(doc_test_turn("x = 1", prompt = "p")))
  root = session_data(s)$leaf
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = "a.R", format = "r", block = "abc123", action = "insert",
                                     backend = "file")))
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = ".gptr/transcripts/t.R", format = "transcript",
                                     block = "def456", action = "insert",
                                     backend = "transcript")))
  from = session_data(s)$leaf
  doc_on_session_tree(list(from = from, to = root, report = c("restored x", "y not restored")),
                      list(session = s))
  expect_identical(readLines(f)[3], "#~ x = 1")
  expect_identical(utils::tail(readLines(t), 1),
                   paste0("# /rewind: 1 items restored or removed, 1 not restored (session log ",
                          root, ")"))
  ents = session_data(s)$entries
  expect_identical(ents[[length(ents)]]$data$action, "undone")
})

test_that("direct R lines and slash commands of the console enter the transcript", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  # the payloads of P14's console:direct and console:command channels
  expect_null(doc_on_console_direct(list(data = list(
    code = "summary(fit)$r.squared", output = "[1] 0.7528", status = "ok", noted = TRUE)),
    list(session = NULL)))
  expect_null(doc_on_console_command(list(data = list(text = "/model opus")),
                                     list(session = NULL)))
  doc_on_console_command(list(data = list(text = "  ")), list(session = NULL))
  doc_on_console_direct(list(data = list(code = "", output = character())), list(session = NULL))
  expect_identical(readLines(file.path(proj, ".gptr", "transcripts", "t.R")),
                   c("", "# direct R (no model)", "summary(fit)$r.squared", "#> [1] 0.7528",
                     "# /model opus"))
})

# ---- Task 13 adaptations (dev/DEVIATIONS.md D-122) ----------------------------------------------

# A call record of a console call (no srcref, no source() frame)
doc_console_call = function(prompt = "fit a model") {
  call = new.env(parent = emptyenv())
  call$template = prompt
  call$prompt = prompt
  call$interp = character()
  call$context = list(list(kind = "symbol", name = "mtcars"))
  call$session = NULL
  call$envir = new.env()
  call$args = list(replay = NULL)
  call$sys_call = call("peter", prompt, quote(mtcars))
  call$nframe = 0L
  call$doc = NULL
  call
}

test_that("a console call asks once where to record and keeps the transcript site", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto", interactive = TRUE)
  testthat::local_mocked_bindings(doc_command_args = function() "R")
  asked = new.env()
  asked$n = 0L
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    "y"
  })
  call = doc_console_call()
  expect_true(doc_route_match(call))
  expect_true(call$top_level)
  expect_true(call$doc$console)
  expect_identical(call$doc$context_labels, "mtcars")
  expect_s3_class(doc_route_run(call), "gptr_route_pass")
  expect_identical(call$doc$format, "transcript")
  expect_match(call$doc$path, "/[.]gptr/transcripts/gptr-session-[0-9]{8}-[0-9]{6}[.]R$")
  again = doc_console_call("predict")
  expect_true(doc_route_match(again))
  expect_identical(again$doc$path, call$doc$path)
  expect_identical(asked$n, 1L)
})

test_that("a failing sidecar recovery never turns a replay into a live call", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("fresh = peter(\"count rows\")",
               paste0("# >>> gptr:abc123 model=fake/fake-1 prompt=", prompt_hash("count rows"),
                      " session=s0a1b2c3d4e turn=1"),
               "n = 32", "# <<< gptr:abc123"), f)
  testthat::local_mocked_bindings(doc_recover = function(path, defer = FALSE) {
    stop("the sidecar could not be read")
  })
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_s3_class(e$fresh, "gptr_session")
  expect_identical(session_data(e$fresh)$id, "s0a1b2c3d4e")
})

test_that("doc.edit never changes a hand-edited block, also through a loose match or old_text", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  h = list(model = "m", date = "2020-01-01", prompt = "p", sha = doc_body_sha(body))
  writeLines(c("peter(\"p\")", doc_render_block("abc123", h, body), "y = 2"), f)
  txt = readLines(f)
  txt[3] = "x = 99 # mine"
  writeLines(txt, f)
  local_doc_binding(f)
  hits = new.env()
  hits$n = 0L
  # an edit tool that matches loosely (as P10's fuzzy matching may): every "x = " line changes
  loose = function(input, ctx) {
    hits$n = hits$n + 1L
    inner = doc_edit_service(input$path, input$edits, NULL)
    if (!is.null(inner)) return(inner)
    writeLines(sub("^x = .*$", "x = 3", readLines(input$path)), input$path)
    gptr_tool_result("Successfully replaced text.")
  }
  off = gptr_register(gptr_spec("tool", "edit", description = "A loose test edit tool",
                                execute = loose))
  withr::defer(off())
  res = doc_edit_service(f, list(list(oldText = "x  =  99", newText = "x = 3")), NULL)
  expect_true(res$is_error)
  expect_true(res$details$document)
  expect_identical(hits$n, 1L)
  expect_identical(readLines(f), txt)
  # P10's edit_normalize_args() also accepts old_text: refused before the tool runs
  res2 = doc_edit_service(f, list(list(old_text = "x = 99", new_text = "x = 3")), NULL)
  expect_true(res2$is_error)
  expect_identical(hits$n, 1L)
  expect_identical(readLines(f), txt)
})

test_that("a rewind and a redo of a console turn keep the transcript format of its block", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  dir.create(dirname(t), recursive = TRUE)
  body = "fit = 1"
  seg = doc_render_block("def456", list(model = "m", prompt = "p", sha = doc_body_sha(body)),
                         body)
  live = c("library(gptr)", "", "s_ab12cd = peter(\"p\")", seg)
  writeLines(live, t)
  s = doc_test_session(list(doc_test_turn("fit = 1", prompt = "p")))
  root = session_data(s)$leaf
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = ".gptr/transcripts/t.R", format = "transcript",
                                     block = "def456", action = "insert",
                                     backend = "transcript")))
  from = session_data(s)$leaf
  note = function(to) {
    paste0("# /rewind: 0 items restored or removed, 0 not restored (session log ", to, ")")
  }
  doc_on_session_tree(list(from = from, to = root, report = character()), list(session = s))
  tr = readLines(t)
  expect_identical(tr[3], "#~ s_ab12cd = peter(\"p\")")
  expect_identical(tr[5], "#~ fit = 1")
  expect_identical(utils::tail(tr, 1), note(root))
  last = function() {
    ents = session_data(s)$entries
    ents[[length(ents)]]$data[c("doc", "format", "block", "action", "backend")]
  }
  expect_identical(last(), list(doc = ".gptr/transcripts/t.R", format = "transcript",
                                block = "def456", action = "undone", backend = "transcript"))
  doc_on_session_tree(list(from = root, to = from, report = character()), list(session = s))
  expect_identical(readLines(t), c(live, note(root), note(from)))
  expect_identical(last()$action, "replace")
  expect_identical(last()$format, "transcript")
})

test_that("a score summary gives its mean, or NA when every element is NA", {
  sc = function(v) {
    structure(v, class = c("gptr_score", "gptr_s1", "numeric"),
              meta = list(model = "jev", date = "2026-09-29"))
  }
  expect_identical(doc_s1_summary(sc(c(1, 2, 1.2))), "gptr_score: mean 1.4 (jev, 2026-09-29)")
  expect_identical(doc_s1_summary(sc(c(NA_real_, NA_real_))),
                   "gptr_score: mean NA (jev, 2026-09-29)")
})

# ---- Task 13 review round 1 (dev/DEVIATIONS.md D-122 items 8-10) -------------------------------

test_that("a direct R line that failed or was interrupted is inert, so the transcript re-sources", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  direct = function(data) doc_on_console_direct(list(data = data), list(session = NULL))
  # P14's payload: status "ok", "error", "interrupt" or "timeout"
  expect_null(direct(list(code = "summary(fti)", output = character(), status = "error",
                          noted = TRUE)))
  direct(list(code = "x_before = 1\nSys.sleep(1e6)", output = "partial", status = "interrupt",
              noted = FALSE))
  direct(list(code = "x_after = 2\nx_after", output = "[1] 2", status = "ok", noted = TRUE))
  # a payload without a status (an older front end) is a line that ran
  direct(list(code = "y_old = 3", output = character()))
  expect_identical(readLines(t),
                   c("", "# direct R (no model; error)", "#~ summary(fti)",
                     "", "# direct R (no model; interrupt)", "#~ x_before = 1",
                     "#~ Sys.sleep(1e6)",
                     "", "# direct R (no model)", "x_after = 2", "x_after", "#> [1] 2",
                     "", "# direct R (no model)", "y_old = 3"))
  e = new.env()
  expect_no_error(source(t, local = e))
  expect_identical(e$x_after, 2)
  expect_identical(e$y_old, 3)
  expect_false(exists("x_before", envir = e, inherits = FALSE))
})

test_that("a console call asks nothing when it cannot be recorded (record off, replay mode)", {
  local_project()
  testthat::local_mocked_bindings(doc_command_args = function() "R")
  asked = new.env()
  asked$n = 0L
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    "y"
  })
  local_gptr_options(record = "off", replay = "auto", interactive = TRUE)
  call = doc_console_call()
  expect_false(doc_route_match(call))
  expect_null(call$doc)
  local_gptr_options(record = "auto", replay = "replay")
  expect_false(doc_route_match(doc_console_call()))
  local_gptr_options(replay = "auto")
  call = doc_console_call()
  call$args = list(replay = "replay")
  expect_false(doc_route_match(call))
  expect_identical(asked$n, 0L)
  expect_null(doc_project_entry(doc_project_get(), "transcript", "target"))
  # the question was not used up: asked once recording is possible
  call = doc_console_call()
  expect_true(doc_route_match(call))
  expect_true(call$doc$console)
  expect_identical(asked$n, 1L)
})

test_that("an undone team block gives the undone notice and is logged as skipped (G7 3.8)", {
  local_project()
  local_replay_table()
  local_gptr_options(record = "auto", replay = "auto", quiet = FALSE)
  f = file.path(getwd(), "a.R")
  ph = prompt_hash("Review")
  live = c("reviews = peter(\"Review\")",
           paste0("# >>> gptr:abc123 model=m prompt=", ph, " session=s7777777777 turn=1",
                  " kind=team children=\"code:s2222222222\" status=undone"),
           "## Agent code (openai/gpt-5.5): Two bugs.", "# <<< gptr:abc123")
  writeLines(doc_inert_text(live, "r", "abc123"), f)
  e = new.env()
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$envir = parent.frame()
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    doc_replay_service(call)
  }
  depth = doc_source_push(f)
  withr::defer(doc_source_pop(depth))
  for (mode in c("auto", "replay")) {
    local_gptr_options(replay = mode)
    expect_message(source(f, local = e, keep.source = TRUE), "undone by /rewind",
                   class = "gptr_message_notice")
    # zero requests: the team is not run live, and nothing is recorded for it
    expect_s3_class(e$reviews, "gptr_session")
    expect_identical(doc_state()$sources[[depth]]$log[["abc123"]], "skipped")
  }
})

# ---- Task 13 review round 2 (dev/DEVIATIONS.md D-122 items 11-12) -------------------------------

test_that("a dead sidecar's block for the calling statement is replayed, not run again (IC-51)", {
  local_project()
  local_replay_table()
  local_gptr_options(record = "auto", replay = "auto")
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  f = file.path(getwd(), "analysis.R")
  writeLines(c("fresh = peter(\"count rows\")", "z = 1"), f)
  ph = prompt_hash("count rows")
  calls = doc_calls(readLines(f))
  site = list(kind = "rscript", path = path_norm(f), format = "r", backend = "file",
              anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = ph, args_hash = NULL,
              template = "count rows", top_level = TRUE)
  # a dead process's sidecar holding this call's block (a session id no earlier test made live)
  rec = doc_pending_new(path_norm(f), "deferred", "s5e4d3c2b1a")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "aaaaaa", site = site, lines = doc_render_block(
    "aaaaaa", list(model = "fake/fake-1", prompt = ph, session = "s5e4d3c2b1a", turn = 1L),
    "n = 32")))
  doc_sidecar_write(rec)
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  # the recovered block is this call's own: replayed (zero requests), never passed to run live
  expect_s3_class(e$fresh, "gptr_session")
  expect_identical(session_data(e$fresh)$id, "s5e4d3c2b1a")
  expect_null(doc_sidecar_read(f))
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  e2 = doc_route_env()
  source(f, local = e2, keep.source = TRUE)
  expect_s3_class(e2$fresh, "gptr_session")
  expect_identical(e2$n, 32)
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
})

test_that("a System 1 one-line block is redacted before it is written (IC-74)", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("kind = peter(\"Which key is this?\", notes, model = jev)", f)
  tok = paste0("ghp_", substr(strrep("a1B2c3D4e5", 4L), 1L, 36L))
  x = structure(c(tok, "lung", tok), class = c("gptr_choice", "gptr_s1", "character"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  e = new.env()
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_s1_block_service(call, x)
    x
  }
  source(f, local = e, keep.source = TRUE)
  txt = readLines(f)
  expect_identical(txt[3], paste0("#> gptr_choice: [secret:github-token] 2, lung 1 ",
                                   "(jev-1.13.0, 2026-09-29)"))
  expect_false(any(grepl(tok, txt, fixed = TRUE)))
  source(f, local = e, keep.source = TRUE)
  expect_identical(readLines(f), txt)
})

# ---- Task 13 review round 3 (dev/DEVIATIONS.md D-122 items 13-14) -------------------------------

test_that("a rewound turn's block stays inert after a new turn on the rewound branch (G7 3.8)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  f = file.path(proj, "a.R")
  blk = function(id, body) {
    doc_render_block(id, list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  }
  writeLines(c("peter(\"p\")", blk("abc123", "x = 1"), "peter(\"q\")", blk("def456", "y = 2")), f)
  s = doc_test_session(list(doc_test_turn("x = 0", prompt = "o")))
  d = session_data(s)
  rec = function(block) {
    list(type = "custom", custom_type = "gptr.doc_block",
         data = list(doc = "a.R", format = "r", block = block, action = "insert",
                     backend = "file"))
  }
  # as P16 moves the tree: the gptr.rewind entry is appended under the target, then session_tree
  tree = function(to) {
    from = d$leaf
    d$leaf = to
    session_append(s, list(type = "custom", custom_type = "gptr.rewind",
                           data = list(from = from, to = to)))
    doc_on_session_tree(list(from = from, to = to, report = character()), list(session = s))
  }
  status = function() {
    b = doc_find_blocks(readLines(f))
    stats::setNames(vapply(b$header, function(h) h$status %||% "live", ""), b$id)
  }
  r = d$leaf
  session_append(s, rec("abc123"))
  a = d$leaf
  tree(r)
  expect_identical(status(), c(abc123 = "undone", def456 = "live"))
  # a new turn on the rewound branch records def456 below the rewind's own "undone" entry
  session_append(s, rec("def456"))
  c_leaf = d$leaf
  tree(a)
  expect_identical(status(), c(abc123 = "live", def456 = "undone"))
  tree(c_leaf)
  expect_identical(status(), c(abc123 = "undone", def456 = "live"))
  expect_true("#~ x = 1" %in% readLines(f))
  tree(a)
  expect_identical(status(), c(abc123 = "live", def456 = "undone"))
})

test_that("doc.replay recovers a dead sidecar's team block for its statement first (IC-51)", {
  local_project()
  local_replay_table()
  local_gptr_options(record = "auto", replay = "auto")
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  f = file.path(getwd(), "a.R")
  writeLines(c("reviews = peter(\"Review\")", "z = 1"), f)
  ph = prompt_hash("Review")
  calls = doc_calls(readLines(f))
  site = list(kind = "rscript", path = path_norm(f), format = "r", backend = "file",
              anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = ph, args_hash = NULL,
              template = "Review", top_level = TRUE)
  # a dead process's sidecar holding this team statement's block (ids no earlier test made live)
  rec = doc_pending_new(path_norm(f), "deferred", "s6e5d4c3b2a")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "abc123", site = site, lines = doc_render_block(
    "abc123", list(model = "m", prompt = ph, session = "s6e5d4c3b2a", turn = 1L, kind = "team",
                   children = "code:s2b3c4d5e6f"),
    "## Agent code (openai/gpt-5.5): Two bugs.")))
  doc_sidecar_write(rec)
  s2_put(s2_key("a.R", "abc123", "code", ph, ""),
         list(block = "abc123", doc = "a.R", part = "code", model = "openai/gpt-5.5",
              answer = "Two bugs.", session = "s2b3c4d5e6f", turn = 1L))
  e = new.env()
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$envir = parent.frame()
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    list(out = doc_replay_service(call), doc = call$doc)
  }
  source(f, local = e, keep.source = TRUE)
  # the team route gets the replayed team (zero requests), not NULL (which would run it live)
  expect_s3_class(e$reviews$out, "gptr_session")
  expect_identical(session_data(e$reviews$out)$id, "s6e5d4c3b2a")
  expect_null(e$reviews$doc)
  expect_null(doc_sidecar_read(f))
  expect_identical(doc_find_blocks(readLines(f))$id, "abc123")
  expect_identical(session_data(gptr_resume(block = "abc123", child = "code"))$last_text,
                   "Two bugs.")
  # a recovery that fails is a diagnostic: the fresh block still replays
  testthat::local_mocked_bindings(doc_recover = function(path, defer = FALSE) {
    stop("the sidecar could not be read")
  })
  e2 = new.env()
  e2$peter = e$peter
  expect_no_error(source(f, local = e2, keep.source = TRUE))
  expect_identical(session_data(e2$reviews$out)$id, "s6e5d4c3b2a")
  expect_identical(doc_find_blocks(readLines(f))$id, "abc123")
})

# ---- Task 13 review round 4 (dev/DEVIATIONS.md D-122 items 15-16) -------------------------------

# A located site of the first call with this prompt in a script or notebook whose writes this
# process queues (`backend`: deferred under Rscript, pending in a Jupyter kernel)
doc_queue_site = function(path, prompt, backend) {
  text = doc_read(path)$lines
  ph = prompt_hash(prompt)
  anchor = if (identical(doc_format_of(path), "ipynb")) {
    list(ph = ph, th = NA_character_, j = 1L, block = NA_character_,
         cell = nb_find_call_cell(nb_parse(text), ph))
  } else {
    calls = doc_calls(text)
    doc_anchor_of(calls, calls[which(calls$ph %in% ph)[1], ])
  }
  list(kind = "rscript", path = path_norm(path), format = doc_format_of(path), backend = backend,
       anchor = anchor, prompt_hash = ph, args_hash = NULL, template = prompt, ordinal = 1L,
       top_level = TRUE)
}

# A session whose second turn recorded `code` for `prompt` through `site` (queued, not written):
# the session, the entry before that turn (`root`) and the turn's leaf (`leaf`)
doc_queue_turn = function(site, code, prompt) {
  s = doc_test_session(list(doc_test_turn("x = 0", prompt = "o")))
  d = session_data(s)
  root = d$leaf
  d$turns = d$turns + 1L
  for (e in doc_test_turn(code, prompt = prompt, id = "call_2")) session_append(s, e)
  cli::cli_fmt(doc_on_agent_end(list(status = "idle", doc = site, turns = d$turns),
                                list(session = s)))
  list(s = s, root = root, leaf = d$leaf)
}

test_that("a rewind under Rscript makes the queued block undone and the exit writes it (G7 4.4)", {
  local_project()
  local_gptr_options(record = "auto")
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  f = file.path(getwd(), "a.R")
  src = c("s = peter(\"count rows\")", "z = 1")
  writeLines(src, f)
  testthat::local_mocked_bindings(doc_rscript_running = function() path_norm(f))
  q = doc_queue_turn(doc_queue_site(f, "count rows", "deferred"), "n = nrow(mtcars)",
                     "count rows")
  queued = function() as.character(doc_sidecar_read(f)$upserts[[1]]$lines)
  last = function() {
    ents = session_data(q$s)$entries
    ents[[length(ents)]]$data[c("action", "backend")]
  }
  tree = function(from, to) {
    doc_on_session_tree(list(from = from, to = to, report = character()), list(session = q$s))
  }
  expect_true("n = nrow(mtcars)" %in% queued())
  tree(q$leaf, q$root)
  # the running script is not written now; the queued block is undone
  expect_identical(readLines(f), src)
  expect_true("#~ n = nrow(mtcars)" %in% queued())
  expect_identical(last(), list(action = "undone", backend = "deferred"))
  # a redo revives the queued block, a second rewind makes it inert again
  tree(q$root, q$leaf)
  expect_true("n = nrow(mtcars)" %in% queued())
  expect_identical(last(), list(action = "replace", backend = "deferred"))
  tree(q$leaf, q$root)
  expect_identical(readLines(f), src)
  # the exit finalizer writes the undone block, so a later source() skips the abandoned code
  doc_pending_flush_all()
  txt = readLines(f)
  expect_identical(doc_find_blocks(txt)$header[[1]]$status, "undone")
  expect_true("#~ n = nrow(mtcars)" %in% txt)
  e = new.env()
  e$peter = function(...) NULL
  source(f, local = e)
  expect_false(exists("n", envir = e, inherits = FALSE))
})

test_that("a rewind in a Jupyter kernel makes the pending block undone; sync writes it (IC-50)", {
  src = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  local_project()
  local_gptr_options(record = "auto")
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  nb = file.path(getwd(), "x.ipynb")
  expect_true(file.copy(src, nb))
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  q = doc_queue_turn(doc_queue_site(nb, "summarise the mpg column", "pending"),
                     "m = mean(mtcars$mpg)", "summarise the mpg column")
  doc_on_session_tree(list(from = q$leaf, to = q$root, report = character()),
                      list(session = q$s))
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  ents = session_data(q$s)$entries
  expect_identical(ents[[length(ents)]]$data[c("action", "backend")],
                   list(action = "undone", backend = "pending"))
  # gptr_doc(sync = TRUE) once the notebook is closed writes the agent cell undone
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  cell = nb_parse(doc_read(nb)$lines)$cells[[4]]
  expect_identical(nb_cell_meta(cell)$status, "undone")
  expect_true("#~ m = mean(mtcars$mpg)" %in% nb_cell_lines(cell))
  expect_false("m = mean(mtcars$mpg)" %in% nb_cell_lines(cell))
})

test_that("doc.edit never edits the running script or the open notebook it is bound to", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  h = list(model = "m", date = "2020-01-01", prompt = "p", sha = doc_body_sha(body))
  writeLines(c("peter(\"p\")", doc_render_block("abc123", h, body), "y = 2"), f)
  raw_of = function(p) readBin(p, "raw", n = file.info(p)$size)
  bytes = raw_of(f)
  hits = new.env()
  hits$n = 0L
  edit_exec = function(input, ctx) {
    hits$n = hits$n + 1L
    inner = doc_edit_service(input$path, input$edits, NULL)
    if (!is.null(inner)) return(inner)
    txt = readLines(input$path)
    for (e in input$edits) txt = sub(e$oldText, e$newText, txt, fixed = TRUE)
    writeLines(txt, input$path)
    gptr_tool_result("Successfully replaced text.")
  }
  off = gptr_register(gptr_spec("tool", "edit", description = "A test edit tool",
                                execute = edit_exec))
  withr::defer(off())
  # under Rscript the running call's site binds the script this process runs (D-109)
  run = new.env()
  run$opts = list(doc = list(path = path_norm(f), format = "r", backend = "deferred"))
  testthat::local_mocked_bindings(run_current = function() run,
                                  doc_rscript_running = function() path_norm(f))
  res = doc_edit_service(f, list(list(oldText = "x = 1", newText = "x = 2")), NULL)
  expect_true(res$is_error)
  expect_match(res$content[[1]]$text, "Rscript", fixed = TRUE)
  expect_identical(hits$n, 0L)
  expect_identical(raw_of(f), bytes)
  # the notebook open in this Jupyter kernel (IC-50)
  nb = file.path(getwd(), "x.ipynb")
  writeLines(c("{", " \"cells\": [", "  {", "   \"cell_type\": \"code\",",
               "   \"execution_count\": null,", "   \"id\": \"c1\",", "   \"metadata\": {},",
               "   \"outputs\": [],", "   \"source\": [\"a = 1\"]", "  }", " ],",
               " \"metadata\": {},", " \"nbformat\": 4,", " \"nbformat_minor\": 5", "}"), nb)
  nbytes = raw_of(nb)
  run$opts = list(doc = list(path = path_norm(nb), format = "ipynb", backend = "pending"))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  res2 = doc_edit_service(nb, list(list(oldText = "a = 1", newText = "a = 2")), NULL)
  expect_true(res2$is_error)
  expect_match(res2$content[[1]]$text, "Jupyter", fixed = TRUE)
  expect_identical(hits$n, 0L)
  expect_identical(raw_of(nb), nbytes)
  # a closed notebook is the edit tool's to write: doc.edit answers NULL
  withr::local_options(jupyter.in_kernel = NULL)
  expect_null(doc_edit_service(nb, list(list(oldText = "a = 1", newText = "a = 2")), NULL))
})

test_that("gptr_doc() binds, shows and unbinds the document of this process", {
  local_project()
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = NULL
  f = file.path(getwd(), "analysis.R")
  writeLines("library(gptr)", f)
  expect_null(gptr_doc())
  expect_invisible(gptr_doc(f))
  expect_identical(gptr_doc(), list(path = path_norm(f), format = "r"))
  expect_true(doc_consent(f, ask = FALSE))
  prev = gptr_doc(FALSE)
  expect_identical(prev$path, path_norm(f))
  expect_null(gptr_doc())
  expect_identical(gptr_doc(f, format = "transcript"), NULL)
  expect_identical(gptr_doc()$format, "transcript")
  expect_error(gptr_doc(file.path(getwd(), "notes.txt")), class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), ".gptr", "settings.json")),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), "missing", "a.R")),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(f, sync = NA), class = "gptr_error_invalid_argument")
  run = new.env()
  run$session = "s0123456789"
  run$signal = new.env()
  testthat::local_mocked_bindings(run_current = function() run)
  expect_error(gptr_doc(f), class = "gptr_error_permission")
  expect_identical(gptr_doc()$format, "transcript")
})

test_that("gptr_blocks() lists fresh, stale, user-edited and undone blocks", {
  local_project()
  f = file.path(getwd(), "a.R")
  ok = "x = 1"
  writeLines(c(
    "peter(\"one\")",
    doc_render_block("aaaaaa", list(model = "m", date = "2026-09-29", prompt = prompt_hash("one"),
                                    sha = doc_body_sha(ok), tokens = "10/2", cost = "0.01",
                                    session = "s0123456789"), ok),
    "peter(\"two, edited prompt\")",
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("two")), "y = 2"),
    "peter(\"three\")",
    doc_render_block("cccccc", list(model = "m", prompt = prompt_hash("three"),
                                    sha = doc_body_sha(ok)), "z = 3 # changed"),
    "peter(\"four\")",
    doc_render_block("dddddd", list(model = "m", prompt = prompt_hash("four"),
                                    status = "undone"), "#~ w = 4")), f)
  b = gptr_blocks(f)
  expect_s3_class(b, "gptr_blocks")
  expect_s3_class(b, "gptr_listing")
  expect_named(b, c("id", "lines", "prompt", "status", "model", "date", "tokens", "cost",
                    "session"))
  expect_identical(b$id, c("aaaaaa", "bbbbbb", "cccccc", "dddddd"))
  expect_identical(b$status, c("fresh", "stale", "user-edited", "undone"))
  expect_identical(b$lines[1], "2-4")
  expect_identical(b$prompt[1], "one")
  expect_identical(b$cost[1], 0.01)
  expect_identical(b$tokens[1], "10/2")
  expect_identical(b$session[1], "s0123456789")
  expect_error(gptr_blocks(file.path(getwd(), "a.txt")), class = "gptr_error_invalid_argument")
})

test_that("gptr_blocks() reads Rmd chunks and notebook cells", {
  # test_path() is relative to tests/testthat, which local_project() leaves: resolve it first
  rmd = normalizePath(testthat::test_path("fixtures", "docs", "report.expected.Rmd"))
  floats = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  local_project()
  b = gptr_blocks(rmd)
  expect_identical(b$id, "3fdfa0")
  expect_identical(b$status, "fresh")
  expect_identical(b$prompt, "count letters in this prompt")
  nb = file.path(getwd(), "a.ipynb")
  text = doc_read(floats)$lines
  ph = prompt_hash("summarise the mpg column")
  site = list(path = nb, format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
              prompt_hash = ph, args_hash = NULL)
  writeLines(doc_ipynb_upsert(text, site, structure("mean(x$mpg)", meta = nb_meta(
    "7f3a21", list(model = "m", prompt = ph, sha = doc_body_sha("mean(x$mpg)")))), "7f3a21"), nb)
  nbb = gptr_blocks(nb)
  expect_identical(nbb$id, "7f3a21")
  expect_identical(nbb$lines, "cell 4")
  expect_identical(nbb$status, "fresh")
})

test_that("gptr_cache() lists, prunes and clears, and never removes sidecars", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines(c("peter(\"one\")", doc_render_block("aaaaaa", list(model = "m"), "x = 1")), f)
  s2_put(s2_key("a.R", "aaaaaa", "", "p", ""), list(block = "aaaaaa", doc = "a.R", answer = "a"))
  s2_put(s2_key("a.R", "gone00", "", "p", ""), list(block = "gone00", doc = "a.R", answer = "b"))
  tmp = file.path(proj, ".gptr", "cache", "tmp")
  writeLines("old", file.path(tmp, "gptr-output-o111111.txt"))
  Sys.setFileTime(file.path(tmp, "gptr-output-o111111.txt"), Sys.time() - 30 * 86400)
  writeLines("new", file.path(tmp, "gptr-output-o222222.txt"))
  rec = doc_pending_new(path_norm(f), "pending", NULL)
  rec$upserts = list(list(block_id = "bbbbbb", lines = "x", site = list(format = "r")))
  doc_sidecar_write(rec)
  info = gptr_cache()
  expect_s3_class(info, "gptr_cache_info")
  expect_named(info, c("kind", "entries", "bytes", "oldest", "path"))
  expect_identical(info$kind, c("s1", "s2", "tmp", "sidecar"))
  expect_identical(info$entries, c(0L, 2L, 2L, 1L))
  expect_identical(gptr_cache("prune", "s2"), 1L)
  expect_identical(gptr_cache("prune", "tmp"), 1L)
  expect_identical(gptr_cache("clear", "tmp"), 1L)
  expect_identical(gptr_cache()$entries, c(0L, 1L, 0L, 1L))
  expect_identical(gptr_cache("clear"), 1L)
  expect_true(file.exists(doc_sidecar_path(f)))
  expect_error(gptr_cache("purge"), class = "gptr_error_invalid_argument")
  testthat::local_mocked_bindings(run_current = function() {
    run = new.env()
    run$signal = new.env()
    run
  })
  expect_error(gptr_cache("clear"), class = "gptr_error_permission")
  expect_s3_class(gptr_cache(), "gptr_cache_info")
})

# ---- Task 14 additions (D-127): blocks owned through the format's own locator, documents bound
# only in the format of their extension, a missing file, and a prune that keeps what it cannot
# check ------------------------------------------------------------------------------------------

test_that("gptr_blocks() gives each call of a pipeline its own block (contract 11.5)", {
  local_project()
  f = file.path(getwd(), "p.R")
  writeLines(c(
    "x = peter(\"draft\") |> peter(\"improve it\")",
    doc_render_block("aaaaaa", list(model = "m", prompt = prompt_hash("draft")), "a = 1"),
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("improve it"), call = "2",
                                    args = "0123abcd"), "b = 2"),
    "y = peter(\"plan\\nthe steps\")",
    doc_render_block("cccccc", list(model = "m", prompt = prompt_hash("plan\nthe steps")),
                     "c = 3"),
    "z = 1",
    doc_render_block("dddddd", list(model = "m", prompt = prompt_hash("draft")), "d = 4")), f)
  b = gptr_blocks(f)
  expect_identical(b$id, c("aaaaaa", "bbbbbb", "cccccc", "dddddd"))
  expect_identical(b$prompt, c("draft", "improve it", "plan the steps", NA))
  expect_identical(b$status, c("fresh", "fresh", "fresh", "stale"))
})

test_that("gptr_blocks() gives the calls of one notebook cell their own agent cells", {
  local_project()
  code = function(id, src, meta = json_obj()) {
    list(cell_type = "code", execution_count = NULL, id = id, metadata = meta,
         outputs = list(), source = as.list(src))
  }
  agent = function(id, ph, body) {
    code(paste0("gptr-", id), body,
         list(gptr = list(id = id, model = "m", prompt = ph, sha = doc_body_sha(body))))
  }
  nb = list(cells = list(code("c1", c("peter(\"one\")\n", "peter(\"two\")")),
                         agent("aaaaaa", prompt_hash("one"), "a = 1"),
                         agent("bbbbbb", prompt_hash("two"), "b = 2"),
                         code("c2", "x = 1"),
                         agent("cccccc", prompt_hash("one"), "c = 3")),
            metadata = json_obj(), nbformat = 4L, nbformat_minor = 5L)
  f = file.path(getwd(), "two.ipynb")
  writeLines(json_encode(nb, pretty = TRUE), f)
  b = gptr_blocks(f)
  expect_identical(b$id, c("aaaaaa", "bbbbbb", "cccccc"))
  expect_identical(b$lines, c("cell 2", "cell 3", "cell 5"))
  expect_identical(b$prompt, c("one", "two", NA))
  expect_identical(b$status, c("fresh", "fresh", "stale"))
})

test_that("gptr_doc() binds documents only in their own format; gptr_blocks() needs the file", {
  local_project()
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = NULL
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  q = file.path(getwd(), "r.qmd")
  writeLines("Some text.", q)
  dir.create(file.path(getwd(), "d.R"))
  expect_error(gptr_doc(f, format = "ipynb"), class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(q, format = "transcript"), class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), "notes.txt"), format = "r"),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), "d.R")), class = "gptr_error_invalid_argument")
  expect_null(gptr_doc())
  expect_invisible(gptr_doc(q, format = "qmd"))
  expect_identical(gptr_doc(), list(path = path_norm(q), format = "qmd"))
  expect_error(gptr_blocks(file.path(getwd(), "missing.R")),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_blocks(file.path(getwd(), "d.R")), class = "gptr_error_invalid_argument")
})

test_that("gptr_cache(\"prune\") keeps answers it cannot check and reads spill_days safely", {
  proj = local_project()
  writeBin(as.raw(c(0x78, 0xff, 0x0a)), file.path(proj, "bad.R"))
  s2_put(s2_key("bad.R", "aaaaaa", "", "p", ""), list(block = "aaaaaa", doc = "bad.R",
                                                      answer = "a"))
  s2_put(s2_key("gone.R", "bbbbbb", "", "p", ""), list(block = "bbbbbb", doc = "gone.R",
                                                       answer = "b"))
  junk = s2_path(s2_key("x.R", "cccccc"))
  dir.create(dirname(junk), recursive = TRUE, showWarnings = FALSE)
  writeLines("not json", junk)
  expect_identical(gptr_cache("prune", "s2"), 2L)
  info = gptr_cache()
  expect_identical(info$entries, c(0L, 1L, 0L, 0L))
  expect_s3_class(info$oldest, "POSIXct")
  expect_identical(is.na(info$oldest), c(TRUE, FALSE, TRUE, TRUE))
  old = file.path(proj, ".gptr", "cache", "tmp", "gptr-output-o333333.txt")
  writeLines("old", old)
  Sys.setFileTime(old, Sys.time() - 30 * 86400)
  local({
    local_gptr_options(spill_days = 60)
    expect_identical(gptr_cache("prune", "tmp"), 0L)
  })
  local({
    local_gptr_options(spill_days = "soon")
    expect_identical(gptr_cache("prune", "tmp"), 1L)
  })
  # the refreshed catalog beyond the newest, in R_user_dir("gptr", "cache"), only with kind "all"
  cat_dir = withr::local_tempdir()
  testthat::local_mocked_bindings(gptr_user_dir = function(which = "config", create = FALSE) {
    cat_dir
  })
  newest = file.path(cat_dir, "models.json")
  older = file.path(cat_dir, "models-2026-09-01.json")
  writeLines("{}", newest)
  writeLines("{}", older)
  writeLines("etag", file.path(cat_dir, "models.etag"))
  Sys.setFileTime(older, Sys.time() - 86400)
  expect_identical(gptr_cache("prune", "s1"), 0L)
  expect_true(file.exists(older))
  expect_identical(withVisible(gptr_cache("prune")), list(value = 1L, visible = FALSE))
  expect_false(file.exists(older))
  expect_true(all(file.exists(c(newest, file.path(cat_dir, "models.etag")))))
  expect_identical(gptr_cache()$entries[2L], 1L)
})

test_that("gptr_cache(\"prune\") keeps the answers of queued blocks (IC-50, IC-51)", {
  proj = local_project()
  st = doc_state()
  old = st$docs
  withr::defer({
    st$docs = old
  })
  f = file.path(proj, "a.R")
  writeLines(c("peter(\"one\")", doc_render_block("aaaaaa", list(model = "m"), "x = 1"),
               "peter(\"two\")"), f)
  # a pending sidecar queues bbbbbb, whose answers doc_after_write() cached when it was queued
  rec = doc_pending_new(path_norm(f), "pending", NULL)
  rec$upserts = list(list(block_id = "bbbbbb", lines = "x", site = list(format = "r")))
  doc_sidecar_write(rec)
  for (part in c("", "n1")) {
    s2_put(s2_key("a.R", "bbbbbb", part, "p", ""),
           list(block = "bbbbbb", doc = "a.R", part = part, answer = "b"))
  }
  s2_put(s2_key("a.R", "gone00", "", "p", ""), list(block = "gone00", doc = "a.R", answer = "g"))
  # this process's own deferred (Rscript) queue, for an existing script and a script not yet there
  writeLines("peter(\"three\")", file.path(proj, "b.R"))
  queue = function(doc, id) {
    st$docs[[path_key(doc_abs(doc))]] = list(
      doc = doc_abs(doc), kind = "deferred",
      upserts = list(list(block_id = id, lines = "x", site = list(format = "r"))))
    s2_put(s2_key(doc, id, "", "p", ""), list(block = id, doc = doc, answer = id))
  }
  queue("b.R", "cccccc")
  queue("new.R", "dddddd")
  expect_identical(gptr_cache()$entries, c(0L, 5L, 0L, 1L))
  expect_identical(gptr_cache("prune", "s2"), 1L)
  expect_identical(gptr_cache()$entries, c(0L, 4L, 0L, 1L))
  expect_true(file.exists(doc_sidecar_path(f)))
  # once nothing queues them and no document holds them, their answers are pruned
  unlink(doc_sidecar_path(f))
  st$docs = old
  expect_identical(gptr_cache("prune", "s2"), 4L)
  expect_identical(gptr_cache()$entries, c(0L, 0L, 0L, 0L))
})

# ---- Task 15: gptr_source() (contract 6.4; report 14 section 4.4.2) -----------------------------

# An environment whose peter() stands in for the gateway: the document route first, then (when it
# passes) a scripted "run" that evaluates `code` in the caller's frame as the agent's r call and
# writes the block through the agent_end hook, as the real run does
doc_source_env = function(code = "n = 99", log = new.env()) {
  e = new.env()
  log$runs = 0L
  e$log = log
  e$peter = function(prompt, ..., replay = NULL) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$envir = parent.frame()
    call$args = list(replay = replay)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(res)
    }
    log$runs = log$runs + 1L
    log$site = call$doc
    eval(parse(text = code), call$envir)
    s = doc_test_session(list(doc_test_turn(code, prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    s
  }
  e
}

test_that("gptr_source() replays fresh blocks, regenerates stale ones and skips their old code", {
  local_project()
  local_gptr_options(record = "auto")
  withr::local_options(gptr.replay = NULL)
  f = file.path(getwd(), "analysis.R")
  fresh_body = "a = 1"
  writeLines(c(
    "fresh = peter(\"first step\")",
    doc_render_block("aaaaaa", list(model = "m", prompt = prompt_hash("first step"),
                                    sha = doc_body_sha(fresh_body)), fresh_body),
    "stale = peter(\"second step, reworded\")",
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("second step")),
                     "old_ran = TRUE"),
    "after = a + 1"), f)
  e = doc_source_env(code = "n = 99")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(e$log$runs, 1L)
  expect_identical(e$log$site$kind, "srcref")
  expect_identical(e$log$site$driver, "gptr_source")
  expect_identical(e$a, 1)
  expect_identical(e$n, 99)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(e$after, 2)
  expect_identical(out$id, c("aaaaaa", "bbbbbb"))
  expect_identical(out$action, c("replayed", "regenerated"))
  expect_identical(out$status, c("fresh", "fresh"))
  b = doc_find_blocks(readLines(f))
  expect_identical(doc_block_body(readLines(f), b[2, ]), "n = 99")
  expect_identical(b$header[[2]]$prompt, prompt_hash("second step, reworded"))
  expect_null(getOption("gptr.replay"))
})

test_that("a call without a block runs and is recorded; replay mode refuses a stale block", {
  local_project()
  local_gptr_options(record = "auto")
  withr::local_options(gptr.replay = NULL)
  f = file.path(getwd(), "analysis.R")
  writeLines(c("x = peter(\"count rows\")", "y = 2"), f)
  e = doc_source_env(code = "n = nrow(mtcars)")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(out$action, "ran")
  expect_identical(e$n, 32L)
  again = gptr_source(f, replay = "replay", envir = e)
  expect_identical(again$action, "replayed")
  expect_identical(e$log$runs, 1L)
  txt = readLines(f)
  txt[1] = "x = peter(\"count the rows\")"
  writeLines(txt, f)
  expect_error(gptr_source(f, replay = "replay", envir = e), class = "gptr_error_stale_block")
  expect_null(getOption("gptr.replay"))
  expect_length(doc_state()$sources, 0L)
})

test_that("gptr_source() validates its arguments and runs plain scripts", {
  local_project()
  f = file.path(getwd(), "plain.R")
  writeLines(c("x = 1", "y = x + 1"), f)
  e = new.env()
  out = gptr_source(f, replay = "replay", envir = e)
  expect_identical(e$y, 2)
  expect_identical(nrow(out), 0L)
  expect_named(out, c("id", "lines", "prompt", "status", "model", "date", "tokens", "cost",
                      "session", "action"))
  expect_error(gptr_source(f, replay = "sometimes"), class = "gptr_error_invalid_argument")
  rmd = file.path(getwd(), "r.Rmd")
  writeLines("x", rmd)
  expect_error(gptr_source(rmd), class = "gptr_error_invalid_argument")
  echoed = cli::cli_fmt(gptr_source(f, envir = e, echo = TRUE))
  expect_identical(echoed, c("> x = 1", "> y = x + 1"))
})

# ---- Task 15 additions (dev/DEVIATIONS.md D-128) ------------------------------------------------

test_that("gptr_source() keeps UTF-8 literals exact in a non-UTF-8 locale (IC-62)", {
  local_project()
  local_gptr_options(record = "auto")
  word = "caf\u00e9"
  prompt = paste(word, "step")
  body = "a = 1"
  f = file.path(getwd(), "analysis.R")
  writeLines(c(paste0("x = \"", word, "\""), paste0("fresh = peter(\"", prompt, "\")"),
               doc_render_block("aaaaaa", list(model = "m", prompt = prompt_hash(prompt),
                                               sha = doc_body_sha(body)), body)),
             f, useBytes = TRUE)
  bytes = readBin(f, "raw", n = file.size(f))
  local_name_locale()
  e = doc_source_env()
  out = gptr_source(f, replay = "replay", envir = e)
  expect_identical(e$x, word)
  expect_identical(charToRaw(e$x), charToRaw(word))
  expect_identical(out$action, "replayed")
  expect_identical(e$log$runs, 0L)
  expect_identical(e$a, 1)
  expect_identical(readBin(f, "raw", n = file.size(f)), bytes)
})

test_that("gptr_source() of a missing file or a directory is an invalid argument", {
  local_project()
  err = expect_error(gptr_source(file.path(getwd(), "missing.R"), envir = new.env()),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "file")
  dir.create(file.path(getwd(), "d.R"))
  expect_error(gptr_source(file.path(getwd(), "d.R"), envir = new.env()),
               class = "gptr_error_invalid_argument")
  expect_length(doc_state()$sources, 0L)
})

test_that("gptr_source() without `replay` keeps GPTR_REPLAY and the replay setting (7.8)", {
  local_project()
  local_gptr_options(record = "auto")
  withr::local_options(gptr.replay = NULL)
  withr::local_envvar(GPTR_REPLAY = "replay")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("x = peter(\"count the rows\")",
               doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("count rows")),
                                "old_ran = TRUE")), f)
  before = readLines(f)
  e = doc_source_env()
  expect_error(gptr_source(f, envir = e), class = "gptr_error_stale_block")
  expect_identical(e$log$runs, 0L)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(readLines(f), before)
  expect_null(getOption("gptr.replay"))
  withr::local_envvar(GPTR_REPLAY = NA, R_USER_CONFIG_DIR = withr::local_tempdir("gptr-config-"))
  writeLines('{"replay": "replay"}', settings_path("user", create = TRUE))
  expect_identical(replay_mode(), "replay")
  expect_error(gptr_source(f, envir = e), class = "gptr_error_stale_block")
  expect_identical(e$log$runs, 0L)
  expect_identical(readLines(f), before)
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(e$log$runs, 1L)
  expect_identical(out$action, "regenerated")
  expect_null(getOption("gptr.replay"))
  expect_length(doc_state()$sources, 0L)
})

test_that("gptr_source() reports a stale call it ran without write consent as `ran`", {
  local_project()
  local_gptr_options(record = "off")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("x = peter(\"count the rows\")",
               doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("count rows")),
                                "old_ran = TRUE")), f)
  before = readLines(f)
  e = doc_source_env(code = "n = 99")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(e$log$runs, 1L)
  expect_identical(e$n, 99)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(readLines(f), before)
  expect_identical(out$id, "bbbbbb")
  expect_identical(out$action, "ran")
  expect_identical(out$status, "stale")
})

test_that("gptr_source() skips a regenerated block's old code below a #line comment", {
  local_project()
  local_gptr_options(record = "auto")
  withr::local_options(gptr.replay = NULL)
  f = file.path(getwd(), "analysis.R")
  # R's parser reads a comment that starts with "#line <digits>" as a line directive: the first
  # and last lines of every later srcref (fields 1 and 3) shift, its parsed lines (7, 8) do not
  writeLines(c(
    "#line 50 is where the old analysis began",
    "x = 1",
    "stale = peter(\"second step, reworded\")",
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("second step")),
                     c("old_ran = TRUE", "x = 0")),
    "after = x + 1"), f)
  e = doc_source_env(code = "n = 99")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(e$log$runs, 1L)
  expect_identical(e$n, 99)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(e$after, 2)
  expect_identical(out$action, "regenerated")
  b = doc_find_blocks(readLines(f))
  expect_identical(doc_block_body(readLines(f), b[1, ]), "n = 99")
  expect_null(getOption("gptr.replay"))
})

test_that("gptr_source() of a file it cannot read as UTF-8 is an invalid argument", {
  local_project()
  f = file.path(getwd(), "latin1.R")
  writeBin(c(charToRaw("x = \""), as.raw(0xe9), charToRaw("\"\n")), f)
  e = new.env()
  err = expect_error(gptr_source(f, envir = e), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "file")
  expect_false(inherits(err, "gptr_error_doc_write"))
  expect_false(exists("x", envir = e, inherits = FALSE))
  testthat::local_mocked_bindings(doc_read = function(path) {
    gptr_abort(paste0("Cannot read the document: ", path), "doc_write", path = path,
               reason = "unreadable")
  })
  err = expect_error(gptr_source(f, envir = e), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "file")
  expect_length(doc_state()$sources, 0L)
})

# ---- end to end through peter() and the fake provider (05 P15 acceptance 2-6) --------------------

# A temporary project where peter() records with the fake provider: replies are scripted, the
# model is fake/fake-1, mode auto (no human is asked), recording consent by option, replay auto.
# gptr.unsafe_no_permissions keeps the scripted r calls running when no mode policy is loaded
# (P11 is an M2 plan, but not a dependency of P15; IC-53 documents the switch for sandboxed runs)
local_doc_e2e = function(script, record = "auto", .env = parent.frame()) {
  root = local_project(.env = .env)
  local_gptr_options(record = record, replay = "auto", model = "fake/fake-1", mode = "auto",
                     unsafe_no_permissions = TRUE, .env = .env)
  fake = local_fake_provider(script, .env = .env)
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  the$doc_binding = NULL
  list(root = root, fake = fake)
}

# A peter() call built at run time, as the console and Jupyter evaluate it: the call carries no
# srcref and its prompt is not a literal of this test file, so the locator cannot mistake the
# test file for the document
doc_e2e_call = function(..., prompt) {
  as.call(c(list(as.name("peter")), list(...), list(prompt)))
}

# Source a document into a fresh environment (whose parent finds gptr) and return it
doc_e2e_source = function(path, envir = new.env(parent = globalenv()), keep_source = TRUE) {
  source(path, local = envir, keep.source = keep_source)
  envir
}

test_that("a recorded block replays under source() with zero model calls (acceptance 2)", {
  x = local_doc_e2e(list(fake_tool("r", code = "n_rows = nrow(d)\nn_rows", note = "count"),
                         fake_text("There are 4 rows.")))
  f = file.path(x$root, "analysis.R")
  writeLines(c("res = peter(\"Count the rows of d\", d)", "check = n_rows * 2"), f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(a = 1:4)
  doc_e2e_source(f, e1)
  expect_identical(length(fake_requests(x$fake)), 2L)
  txt = readLines(f)
  expect_match(txt[2], "^# >>> gptr:[0-9a-f]{6} model=fake/fake-1 date=")
  expect_identical(txt[3:6], c("n_rows = nrow(d)", "n_rows", "#> [1] 4", "## Decision: count"))
  expect_identical(e1$check, 8)
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(a = 1:4)
  doc_e2e_source(f, e2)
  expect_identical(length(fake_requests(x$fake)), 2L)
  expect_identical(e2$n_rows, 4L)
  expect_identical(e2$check, 8)
  expect_s3_class(e2$res, "gptr_session")
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(readLines(f), txt)
  e3 = new.env(parent = globalenv())
  e3$d = data.frame(a = 1:4)
  doc_e2e_source(f, e3, keep_source = FALSE)
  expect_identical(e3$check, 8)
  expect_identical(length(fake_requests(x$fake)), 2L)
})

test_that("a stale prompt regenerates through gptr_source(replay = \"record\") (acceptance 2)", {
  x = local_doc_e2e(list(fake_tool("r", code = "old_ran = TRUE"), fake_text("old"),
                         fake_tool("r", code = "new_ran = TRUE"), fake_text("new")))
  f = file.path(x$root, "analysis.R")
  writeLines("res = peter(\"Do the first thing\")", f)
  doc_e2e_source(f)
  id = doc_find_blocks(readLines(f))$id
  txt = readLines(f)
  txt[1] = "res = peter(\"Do the second thing\")"
  writeLines(txt, f)
  e = new.env(parent = globalenv())
  out = gptr_source(f, replay = "record", envir = e)
  expect_identical(length(fake_requests(x$fake)), 4L)
  expect_true(e$new_ran)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(out$id, id)
  expect_identical(out$action, "regenerated")
  expect_identical(doc_block_body(readLines(f), doc_find_blocks(readLines(f))), "new_ran = TRUE")
})

test_that("GPTR_REPLAY=replay blocks a real model called in a loop (acceptance 3)", {
  local_project()
  withr::local_options(gptr.replay = NULL)
  withr::local_envvar(GPTR_REPLAY = "replay")
  online = gptr_fake_provider(list("never sent"), name = "online")
  online$offline = FALSE
  off = gptr_register(online)
  withr::defer(off())
  local_gptr_options(model = "online/online-1", mode = "auto", record = "auto")
  f = file.path(getwd(), "loop.R")
  # no automatic context, so P08's egress guard (which runs first) lets the replay guard answer
  writeLines(c("for (i in 1:2) {",
               "  x = peter(\"Summarise step {i}\", .opts = list(context = \"none\"))", "}"), f)
  expect_error(doc_e2e_source(f), class = "gptr_error_not_recorded")
  expect_length(fake_requests(online), 0L)
})

test_that("value= replays by name and no document gets a $value line (acceptance 4)", {
  x = local_doc_e2e(list(
    fake_tool("r", code = "markers = c(\"CD3E\", \"MS4A1\")\ngptr_return(markers)"),
    fake_text("Two markers.")))
  f = file.path(x$root, "analysis.R")
  writeLines("res = peter(\"Find the markers\")", f)
  doc_e2e_source(f)
  txt = readLines(f)
  expect_match(txt[2], " value=markers", fixed = TRUE)
  expect_false(any(grepl("$value", txt, fixed = TRUE)))
  expect_false(any(grepl("gptr_return", txt, fixed = TRUE)))
  e = doc_e2e_source(f)
  expect_identical(e$res$value, c("CD3E", "MS4A1"))
  expect_length(fake_requests(x$fake), 2L)
})

test_that("documents are written only with consent; a project cannot grant it (acceptance 5)", {
  x = local_doc_e2e(function(request) {
    if (request$n %% 2L == 1L) fake_tool("r", code = "n = 1") else fake_text("one.")
  }, record = NULL)
  f = file.path(x$root, "analysis.R")
  writeLines("res = peter(\"Set n\")", f)
  local_gptr_options(interactive = FALSE)
  doc_e2e_source(f)
  expect_identical(readLines(f), "res = peter(\"Set n\")")
  writeLines("{\"version\": 1, \"record\": \"auto\"}",
             file.path(x$root, ".gptr", "settings.json"))
  gptr_trust(x$root, trust = TRUE)
  doc_e2e_source(f)
  expect_identical(readLines(f), "res = peter(\"Set n\")")
  settings_write("user", list(record = "auto"))
  withr::defer(settings_write("user", list(record = NULL)))
  doc_e2e_source(f)
  expect_length(doc_find_blocks(readLines(f))$id, 1L)
})

test_that("a fresh clone without consent replays with zero calls and runs each block once (5)", {
  x = local_doc_e2e(list(fake_tool("r", code = "hits = hits + 1"), fake_text("Counted.")))
  f = file.path(x$root, "analysis.R")
  writeLines(c("hits = 0", "res = peter(\"Count once\")"), f)
  doc_e2e_source(f)
  clone = withr::local_tempdir("gptr-clone-")
  file.copy(f, file.path(clone, "analysis.R"))
  withr::local_dir(clone)
  local_gptr_options(project_root = path_norm(clone), record = NULL, interactive = FALSE)
  e = doc_e2e_source(file.path(clone, "analysis.R"))
  expect_identical(e$hits, 1)
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(readLines(file.path(clone, "analysis.R")), readLines(f))
})

test_that("gptr_return() and peter$out() calls are dropped and the block re-sources (6)", {
  script = function(request) {
    if (request$n == 1L) {
      return(fake_tool("r", code = "cat(rep(\"line\", 400), sep = \"\\n\")", record = FALSE))
    }
    if (request$n == 2L) {
      txt = msg_text(request$last_results[[1L]])
      id = regmatches(txt, regexec("peter\\$out\\(\"(o[0-9a-f]{6})\"", txt))[[1L]][2L]
      return(fake_tool("r", code = paste0("fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\n",
                                          "peter$out(\"", id, "\", lines = 1)")))
    }
    fake_text("Fitted.")
  }
  x = local_doc_e2e(script)
  local_gptr_options(r_output_tokens = 200L)
  f = file.path(x$root, "analysis.R")
  writeLines("res = peter(\"Fit mpg on weight\")", f)
  doc_e2e_source(f)
  body = doc_block_body(readLines(f), doc_find_blocks(readLines(f)))
  # the code of gptr_return() and peter$out() is dropped; P10's flat `outputs` may keep the
  # printed line of peter$out() as a #> comment, which re-sources as a comment
  expect_identical(body[!startsWith(body, "#>")], "fit = lm(mpg ~ wt, data = mtcars)")
  expect_match(readLines(f)[2], " value=fit", fixed = TRUE)
  e = doc_e2e_source(f)
  expect_s3_class(e$res$value, "lm")
  expect_length(fake_requests(x$fake), 3L)
})

test_that("re-sourcing NS-3 twice keeps the main line and the fork's overlay apart (IC-46)", {
  x = local_doc_e2e(list(
    fake_tool("r", code = "qc_flags = d$mt > 20\ngptr_return(qc_flags)"), fake_text("Flagged."),
    fake_tool("r", code = "qc_flags = d$mt > 15\ngptr_return(qc_flags)"), fake_text("Updated."),
    fake_tool("r", code = "qc_flags = d$mt > 10"), fake_text("Tried 10%.")))
  f = file.path(x$root, "ns3.R")
  writeLines(c("qc = peter(\"Run QC on d and flag low-quality cells\", d)",
               "qc |> peter(\"Use 15% as the cut-off instead of 20%\")",
               "gptr_fork(qc) |> peter(\"Try a 10% cut-off as well\")"), f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(mt = c(5, 12, 18, 25))
  doc_e2e_source(f, e1)
  b = doc_find_blocks(readLines(f))
  expect_length(b$id, 3L)
  expect_match(readLines(f)[b$start[3]], " fork=s[0-9a-f]{10}:2", perl = TRUE)
  fork_body = doc_block_body(readLines(f), b[3, ])
  expect_identical(fork_body[1], "local({")
  expect_identical(fork_body[3], paste0("}, envir = gptr_resume(block = \"", b$id[3],
                                        "\")$envir)"))
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(mt = c(5, 12, 18, 25))
  for (pass in 1:2) {
    doc_e2e_source(f, e2)
    expect_identical(e2$qc_flags, c(FALSE, FALSE, TRUE, TRUE))
    expect_identical(e2$qc$value, c(FALSE, FALSE, TRUE, TRUE))
    overlay = gptr_resume(block = b$id[3])$envir
    expect_false(identical(overlay, e2))
    expect_identical(get("qc_flags", envir = overlay, inherits = FALSE), c(FALSE, TRUE, TRUE, TRUE))
  }
  expect_length(fake_requests(x$fake), 6L)
})

test_that("a replayed pipe chain is one session; a clone continues from its document (IC-46)", {
  x = local_doc_e2e(list(fake_tool("r", code = "a = 1"), fake_text("one."),
                         fake_tool("r", code = "b = 2"), fake_text("two."),
                         fake_text("three, live.")))
  f = file.path(x$root, "chain.R")
  writeLines("chain = peter(\"step one\") |> peter(\"step two\")", f)
  doc_e2e_source(f)
  b = doc_find_blocks(readLines(f))
  expect_match(readLines(f)[b$start[2]], " call=2", fixed = TRUE)
  clone = withr::local_tempdir("gptr-clone-")
  file.copy(f, file.path(clone, "chain.R"))
  # a clone that committed .gptr/cache (S2 answers) but not .gptr/sessions; file.copy() copies a
  # directory only into an existing directory
  dir.create(file.path(clone, ".gptr"))
  expect_true(file.copy(file.path(x$root, ".gptr", "cache"), file.path(clone, ".gptr"),
                        recursive = TRUE))
  expect_false(dir.exists(file.path(clone, ".gptr", "sessions")))
  withr::local_dir(clone)
  local_gptr_options(project_root = path_norm(clone))
  last_set(NULL)
  invisible(gc())
  e = doc_e2e_source(file.path(clone, "chain.R"))
  d = session_data(e$chain)
  expect_identical(sort(d$seen), sort(b$id))
  expect_identical(d$history_source, "reconstructed")
  expect_identical(e$chain$text, "two.")
  expect_length(fake_requests(x$fake), 4L)
  local_gptr_options(quiet = FALSE)
  expect_message(e$chain |> peter("step three", .opts = list(context = "none")),
                 class = "gptr_message_notice")
  req = fake_requests(x$fake)[[5L]]
  texts = vapply(req$messages, function(m) msg_text(m), "")
  expect_true("step one" %in% texts)
})

test_that("two values of an interpolated {gene} never replay each other's block (IC-45)", {
  skip_if_not_installed("knitr")
  x = local_doc_e2e(rep(list(fake_tool("r", code = "plotted = gene"), fake_text("Plotted.")), 2L))
  rmd = file.path(x$root, "report.Rmd")
  writeLines(c("```{r ask}", "peter(\"Plot the expression of {gene}\")", "```"), rmd)
  for (g in c("CD3E", "MS4A1")) {
    e = new.env(parent = globalenv())
    e$gene = g
    knitr::knit(rmd, output = file.path(x$root, "report.md"), envir = e, quiet = TRUE)
    expect_identical(e$plotted, g)
  }
  expect_length(fake_requests(x$fake), 4L)
  b = doc_find_blocks(readLines(rmd))
  expect_length(b$id, 1L)
  expect_identical(b$header[[1]]$args, args_hash("gene=MS4A1"))
})

test_that("a two-turn console session with a menu steer re-sources as one session (IC-49)", {
  steer_once = new.env()
  script = function(request) {
    if (request$n == 3L && is.null(steer_once$done)) {
      steer_once$done = TRUE
      session_enqueue(gptr_last(), "use log scale", as = "steer", source = "pause_menu")
    }
    switch(as.character(request$n),
           "1" = fake_tool("r", code = "fit = lm(mpg ~ wt, data = mtcars)"),
           "2" = fake_text("Fitted."),
           "3" = fake_tool("r", code = "p = predict(fit)"),
           fake_text("Predicted on the log scale."))
  }
  x = local_doc_e2e(script)
  # a console, not `Rscript <file>` (the test runner may be one)
  testthat::local_mocked_bindings(doc_command_args = function() "R")
  t = file.path(x$root, ".gptr", "transcripts", "console.R")
  dir.create(dirname(t), recursive = TRUE)
  gptr_doc(t, format = "transcript")
  e = new.env(parent = globalenv())
  s = eval(doc_e2e_call(prompt = paste("fit mpg on", "weight")), e)
  e$s = s
  eval(doc_e2e_call(as.name("s"), prompt = paste("add", "predictions")), e)
  tr = readLines(t)
  hex = substr(sub("^s", "", s$id), 1L, 6L)
  expect_true(paste0("s_", hex, " = peter(\"fit mpg on weight\")") %in% tr)
  expect_true(paste0("s_", hex, " |> peter(\"add predictions\")") %in% tr)
  expect_true("## Steer: use log scale" %in% tr)
  e2 = new.env(parent = globalenv())
  e2$library = function(...) invisible(NULL)
  local_gptr_options(replay = "replay")
  gptr_doc(FALSE)
  doc_e2e_source(t, e2)
  s2 = get(paste0("s_", hex), envir = e2)
  expect_identical(length(session_data(s2)$seen), 2L)
  expect_true(is.numeric(e2$p))
  expect_length(fake_requests(x$fake), 4L)
})

test_that("a plan-mode run records only its plan line (IC-48)", {
  skip_if_not(ext_service_has("plan.pending"), "plan mode (P11) is not loaded")
  x = local_doc_e2e(list(fake_tool("r", code = "x = 1"),
                         fake_text("Plan:\n1. Load the data\n2. Fit the model")))
  f = file.path(x$root, "plan.R")
  writeLines("p = peter(\"Plan the analysis\", mode = \"plan\")", f)
  doc_e2e_source(f)
  b = doc_find_blocks(readLines(f))
  body = doc_block_body(readLines(f), b)
  expect_length(body, 1L)
  expect_match(body, "^## Plan: ")
})

test_that("a block with a nested sub-agent call replays with zero requests (IC-47)", {
  x = local_doc_e2e(list(fake_tool("r", code = "sub = peter(\"Summarise d\")"),
                         fake_text("d has 4 rows."), fake_text("Done.")))
  f = file.path(x$root, "nested.R")
  writeLines("res = peter(\"Analyse d with a helper\")", f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(a = 1:4)
  doc_e2e_source(f, e1)
  expect_identical(doc_block_body(readLines(f), doc_find_blocks(readLines(f))),
                   "sub = peter(\"Summarise d\")")
  n = length(fake_requests(x$fake))
  local_gptr_options(replay = "replay")
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(a = 1:4)
  doc_e2e_source(f, e2)
  expect_length(fake_requests(x$fake), n)
  expect_identical(e2$sub$text, "d has 4 rows.")
})

test_that("an open notebook is never written; gptr_doc(sync = TRUE) applies it (IC-50)", {
  fixture = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  x = local_doc_e2e(list(fake_tool("r", code = "m = mean(mtcars$mpg)"), fake_text("20.09.")))
  nb = file.path(x$root, "analysis.ipynb")
  file.copy(fixture, nb)
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  e = new.env(parent = globalenv())
  out = cli::cli_fmt(eval(doc_e2e_call(prompt = paste("summarise the", "mpg column")), e))
  expect_true("m = mean(mtcars$mpg)" %in% out)
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  withr::local_options(jupyter.in_kernel = NULL)
  withr::local_envvar(JPY_SESSION_NAME = NA)
  gptr_doc(nb, sync = TRUE)
  cells = nb_parse(doc_read(nb)$lines)$cells
  expect_match(cells[[4]]$id, "^gptr-[0-9a-f]{6}$")
  expect_identical(unlist(cells[[4]]$source), "m = mean(mtcars$mpg)")
})
