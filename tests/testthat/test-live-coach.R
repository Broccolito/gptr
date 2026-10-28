# Live tests of gptr_coach() at k = 1 (plan P29; 08 sections 1.3-1.7, 3.3, 3.6 and 3.7) on an API
# key (Bedrock Claude), a Claude Code plan and a Codex plan, and of a recorded coaching call. Each
# coaching call runs 4 runs and 3 coach sessions, each in its own R process, under a budget of
# 300,000 tokens per session; gptr is installed once per R session into a temporary library for
# those processes. Gated: GPTR_LIVE_TESTS=true, and each route only when it is available:
# - API: a Bedrock endpoint in GPTR_BEDROCK_BASE_URL and GPTR_BEDROCK_REGION (as in
#   test-live-bedrock.R) and a key pair, loaded with gptr_env() from GPTR_LLM_KEY_FILE (default
#   .secrets/llm-passwords.env, never printed) or set in AWS_ACCESS_KEY_ID and
#   AWS_SECRET_ACCESS_KEY. The model is GPTR_LIVE_COACH_MODEL, by default Bedrock's id of Claude
#   Haiku 4.5, the cheapest Claude in gptr's catalog (the catalog lists no Bedrock model);
# - plans: GPTR_LIVE_HOME, the real home directory (setup.R moves HOME; see test-live-cli.R), and
#   a claude or codex CLI that is signed in and passes gptr's coaching preflight.
#   GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME" GPTR_BEDROCK_BASE_URL=... GPTR_BEDROCK_REGION=... \
#     GPTR_LLM_KEY_FILE=... Rscript --vanilla -e 'devtools::test(filter = "live-coach")'

# Children load gptr with loadNamespace(): under R CMD check the installed package is on the
# library path; from a source tree it is installed once per R session into a temporary library
local_worker_lib = function(.env = parent.frame()) {
  testthat::skip_on_cran()
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (!file.exists(file.path(path, "R", "aaa-state.R"))) return(invisible(NULL))
  lib = file.path(tempdir(), "gptr-worker-lib")
  if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
    dir.create(lib, showWarnings = FALSE, recursive = TRUE)
    cmd = sprintf(paste0("install.packages('%s', lib = '%s', repos = NULL, type = 'source', ",
                         "INSTALL_opts = c('--no-docs', '--no-multiarch', '--no-test-load'))"),
                  normalizePath(path, winslash = "/"), normalizePath(lib, winslash = "/"))
    res = processx::run(rscript_path(), c("--vanilla", "-e", cmd), error_on_status = FALSE,
                        timeout = 600)
    if (!file.exists(file.path(lib, "gptr", "DESCRIPTION"))) {
      testthat::skip(paste("could not install gptr for worker children:", res$stderr))
    }
  }
  withr::local_libpaths(lib, action = "prefix", .local_envir = .env)
  invisible(lib)
}

skip_coach_live = function() {
  skip_on_cran()
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "GPTR_LIVE_TESTS is not true")
}

# What every route needs once it is available: the egress acknowledgement of `model`'s provider
# in the private user config, live replay, at most two children at once, and gptr for them
local_coach_route = function(model, .env) {
  pid = gateway_provider_id(gateway_model_ref(model))
  gptr_config(egress = stats::setNames(list("ack"), pid), .scope = "user")
  local_gptr_options(replay = "live", subagents.max_workers = 2L, .env = .env)
  local_worker_lib(.env)
  model
}

# The Bedrock route for the calling test: a private user config, project and vault, the key pair,
# and the provider "bedrock-coach"; returns the model reference
local_coach_bedrock = function(.env = parent.frame()) {
  skip_coach_live()
  url = Sys.getenv("GPTR_BEDROCK_BASE_URL")
  region = Sys.getenv("GPTR_BEDROCK_REGION")
  skip_if(!nzchar(url) || !nzchar(region),
          "GPTR_BEDROCK_BASE_URL and GPTR_BEDROCK_REGION name no Bedrock endpoint")
  local_gw(.env = .env)
  file = Sys.getenv("GPTR_LLM_KEY_FILE", test_path("..", "..", ".secrets", "llm-passwords.env"))
  if (file.exists(file)) {
    gptr_env(file, aliases = list(AWS_ACCESS_KEY_ID = "AWS_ACCESS_KEY",
                                  AWS_SECRET_ACCESS_KEY = "AWS_SECRET_KEY"),
             set_env = FALSE, quiet = TRUE)
  }
  have = function(nm) !is.null(secret_lookup(nm)) || nzchar(Sys.getenv(nm))
  skip_if_not(have("AWS_ACCESS_KEY_ID") && have("AWS_SECRET_ACCESS_KEY"),
              "no Bedrock key pair in GPTR_LLM_KEY_FILE or the environment")
  id = Sys.getenv("GPTR_LIVE_COACH_MODEL", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
  off = gptr_register(gptr_provider(
    "bedrock-coach", api = "bedrock-converse", base_url = url, auth = "AWS_SECRET_ACCESS_KEY",
    compat = list(region = region),
    models = list(list(id = id, tool_call = TRUE, context = 200000, max_output = 8192))))
  withr::defer(off(), envir = .env)
  local_coach_route(paste0("bedrock-coach/", id), .env)
}

# A plan route for the calling test: the real home, a signed-in CLI that passes the coaching
# preflight (08 section 3.7), a private user config and project; returns `model`
local_coach_plan = function(cli, model, .env = parent.frame()) {
  skip_coach_live()
  home = Sys.getenv("GPTR_LIVE_HOME")
  skip_if_not(nzchar(home) && dir.exists(home), "GPTR_LIVE_HOME names no directory")
  withr::local_envvar(HOME = home, USERPROFILE = home, .local_envir = .env)
  skip_if(is.null(tryCatch(pcli_find(cli), gptr_error = function(e) NULL)),
          paste("the", cli, "CLI is not installed"))
  skip_if_not(identical(pcli_login_status(cli), "signed in"),
              paste("the", cli, "CLI is not signed in"))
  refused = tryCatch(coach_model_kind(model), gptr_error_model_refused = identity)
  if (inherits(refused, "condition")) skip(conditionMessage(refused))
  local_gw(.env = .env)
  local_coach_route(model, .env)
}

live_task = paste("The data codes a missing age as -9. Recode those ages as missing, then hand",
                  "back the mean of the remaining ages with gptr_return().")

# A tiny survey with ages, -9 coding a missing one, and `canary` in a text column
live_survey = function(age, canary) data.frame(id = seq_along(age), age = age, site = canary)

# gptr_coach() on the survey task, with `model` for the runs and the coaches; the canary is in
# the prompt and in the data
live_coach = function(model, canary) {
  survey = live_survey(c(34, 51, -9, 28, 45, -9, 62, 39), canary)
  want = mean(c(34, 51, 28, 45, 62, 39))
  start = gptr_tailor(peter, model = I(model), mode = "auto")
  gptr_coach(prompt = paste0(live_task, " Batch ", canary, "."), survey, harness = start,
             budget = list(tokens = 3e5),
             check = function(r) is.numeric(r$value) && isTRUE(abs(r$value - want) < 1e-8))
}

# The harness a coaching call returned: its record (4 runs, 3 coach sessions, no data), its
# report, and a call on a second survey
expect_live_harness = function(h, canary) {
  expect_s3_class(h, "gptr_harness")
  rec = h$record
  if (identical(rec$decision, "stopped")) skip(rec$reason)
  rows = c(rec$runs, rec$coaches)
  message(rec$model, ": ", rec$decision, " (", rec$reason, "); ",
          paste(vapply(rows, function(r) paste(r$label, r$status), ""), collapse = ", "))
  expect_true(rec$decision %in% c("kept", "not kept"), info = rec$reason)
  expect_length(rec$runs, 4L)
  expect_length(rec$coaches, 3L)
  expect_true(all(nzchar(vapply(rows, function(r) r$status, ""))))
  # the starting run comes first; it ended normally and saw the canary
  expect_identical(rec$runs[[1L]]$status, "idle")
  expect_identical(h$report$record, rec)
  expect_match(h$report$results[[1L]]$transcript, canary, fixed = TRUE)
  expect_false(grepl(canary, paste(deparse(rec), collapse = "\n"), fixed = TRUE))
  survey_2 = live_survey(c(-9, 40, 22, 57, -9, 31), canary)
  s = h(prompt = live_task, survey_2, budget = list(tokens = 3e5))
  withr::defer(pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = s$id))))
  expect_identical(s$status, "idle")
  expect_true(is.numeric(s$value) && isTRUE(abs(s$value - 37.5) < 1e-8))
}

test_that("gptr_coach() on an API key (Bedrock Claude) gives a harness that works on new data", {
  model = local_coach_bedrock()
  canary = paste0("canary", id_new("", 8L))
  expect_live_harness(live_coach(model, canary), canary)
})

test_that("gptr_coach() on a Claude Code plan gives a harness and bills nothing", {
  model = local_coach_plan("claude", "claude_code")
  canary = paste0("canary", id_new("", 8L))
  h = live_coach(model, canary)
  expect_identical(h$record$cost, 0)
  expect_live_harness(h, canary)
})

test_that("gptr_coach() on a Codex plan leaves no prompt in CODEX_HOME (D-265)", {
  model = local_coach_plan("codex", "codex")
  canary = paste0("canary", id_new("", 8L))
  home = pcli_codex_home()
  # names, sizes and modification times only; a file is read only to count the canary
  files = function() {
    f = list.files(home, recursive = TRUE, all.files = TRUE, full.names = TRUE)
    info = file.info(f, extra_cols = FALSE)
    stats::setNames(paste(f, info$size, as.numeric(info$mtime)), f)
  }
  before = files()
  h = live_coach(model, canary)
  after = files()
  changed = names(after)[!after %in% before]
  holds = vapply(changed, function(f) {
    # Codex removes some temporary files between the listing and this read
    b = if (file.exists(f)) tryCatch(readBin(f, "raw", n = file.size(f)), error = function(e) raw())
    if (is.null(b)) b = raw()
    length(grepRaw(canary, b, fixed = TRUE)) > 0L
  }, NA, USE.NAMES = FALSE)
  message("D-265: ", length(changed), " file(s) under CODEX_HOME changed during gptr_coach(), ",
          sum(holds), " holding the prompt canary",
          if (length(changed)) {
            paste0(": ", paste0(substring(changed, nchar(home) + 2L), " (", file.size(changed),
                                " bytes", ifelse(holds, ", canary", ""), ")", collapse = ", "))
          })
  expect_identical(sum(holds), 0L)
  expect_identical(h$record$cost, 0)
  expect_live_harness(h, canary)
})

test_that("a recorded coaching call and harness call replay with no model request", {
  live_model = local_coach_bedrock()
  local_gptr_options(record = "auto")
  task = encodeString(live_task, quote = "\"")
  f = file.path(getwd(), "coach.R")
  writeLines(c(
    "survey = data.frame(id = 1:8, age = c(34, 51, -9, 28, 45, -9, 62, 39))",
    "start = gptr_tailor(peter, model = I(live_model), mode = \"auto\")",
    paste0("age_peter = gptr_coach(", task, ", survey, harness = start,"),
    "  budget = list(tokens = 3e5),",
    "  check = function(r) is.numeric(r$value) && isTRUE(abs(r$value - 259 / 6) < 1e-8))",
    "survey_2 = data.frame(id = 1:6, age = c(-9, 40, 22, 57, -9, 31))",
    paste0("answer = age_peter(", task, ", survey_2, budget = list(tokens = 3e5))")), f)
  e = new.env(parent = globalenv())
  e$live_model = live_model
  gptr_source(f, replay = "record", envir = e)
  hash = coaching_hash(e$age_peter$coaching)
  b = doc_find_blocks(readLines(f))
  expect_identical(b$header[[1L]]$kind, "coach")
  expect_identical(vapply(b$header, function(x) x$harness %||% "", ""),
                   rep(paste0("age_peter:", hash), 2L))
  # the same script again under GPTR_REPLAY=replay, in a fresh environment
  local_gptr_options(replay = NULL)
  withr::local_envvar(GPTR_REPLAY = "replay")
  n = new.env()
  n$requests = 0L
  testthat::local_mocked_bindings(
    provider_stream = function(...) {
      n$requests = n$requests + 1L
      stop("a model request during replay")
    },
    coach_run_jobs = function(...) {
      n$requests = n$requests + 1L
      stop("a coaching process during replay")
    })
  e2 = new.env(parent = globalenv())
  e2$live_model = live_model
  out = gptr_source(f, envir = e2)
  expect_identical(n$requests, 0L)
  expect_identical(out$action, c("replayed", "replayed"))
  expect_identical(coaching_hash(e2$age_peter$coaching), hash)
})
