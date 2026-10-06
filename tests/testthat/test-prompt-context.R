# P07 Task 5: context blocks, the first user message and per-turn blocks.

append_user = function(s, blocks, prompt) {
  session_append(s, list(type = "message",
                         message = msg_user(c(blocks, list(block_text(prompt))))))
}

mtcars_call = function() {
  list(context = list(list(label = "mtcars", kind = "symbol", name = "mtcars", slot = NULL,
                           facts = list(class = "data.frame", dim = c(32L, 11L)))),
       args = list(opts = list()))
}

user_agents = function(text, .env = parent.frame()) {
  user = gptr_user_dir("config", create = TRUE)
  f = file.path(user, "AGENTS.md")
  writeLines(text, f)
  withr::defer(unlink(f), envir = .env)
  f
}

test_that("instruction files load user-level first, root to cwd, vignette.Rmd last", {
  user_agents("# user rules")
  root = p07_project(list("AGENTS.md" = "# root", "CLAUDE.md" = "# not read (AGENTS.md first)",
                          "sub/CLAUDE.md" = "# sub", "sub/CLAUDE.local.md" = "# local",
                          ".gptr/vignette.Rmd" = "# vignette"))
  withr::local_dir(file.path(root, "sub"))
  f = context_instruction_files(root, getwd())
  labels = vapply(f, function(x) x$label, "")
  expect_identical(labels[-1], c("AGENTS.md", "sub/CLAUDE.md", "sub/CLAUDE.local.md",
                                 ".gptr/vignette.Rmd"))
  expect_match(labels[1], "AGENTS.md$")
  expect_identical(vapply(f, function(x) x$user, NA), c(TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("the directory walk runs from the root to cwd and never leaves the root", {
  root = p07_project(list("..cache/sub/AGENTS.md" = "# dotted"))
  sub = file.path(root, "..cache", "sub")
  expect_identical(context_dirs(root, sub),
                   c(root, file.path(root, "..cache"), file.path(root, "..cache/sub")))
  expect_identical(context_dirs(root, root), root)
  expect_identical(context_dirs(root, dirname(root)), root)
  expect_identical(context_dirs(root, withr::local_tempdir("gptr-elsewhere-")), root)
})

test_that("vignette.Rmd loses its YAML header and HTML comments but keeps chunks verbatim", {
  txt = paste(c("---", "title: \"Project instructions\"", "output: html_document", "---",
                "<!-- @AGENTS.md", "hint -->", "", "# Data", "- `pbmc` is loaded once.", "",
                "```{r}", "x = 1", "```"), collapse = "\n")
  expect_identical(context_strip_vignette(txt),
                   "# Data\n- `pbmc` is loaded once.\n\n```{r}\nx = 1\n```")
})

test_that("@file lines of vignette.Rmd include project files once, inside the project only", {
  p07_project(list("AGENTS.md" = "- root rule", "docs/style.md" = "- style rule",
                   ".gptr/vignette.Rmd" = c("# Project", "@AGENTS.md", "@docs/style.md",
                                            "@docs/style.md", "@../outside.md", "@missing.md")))
  s = p07_session("manual")
  b = context_first_message(s, list(turn = 1L))
  vig = Filter(function(x) identical(x$attrs$path, ".gptr/vignette.Rmd"), b)[[1]]$text
  expect_match(vig, "\n# Project\n- style rule\n</project_instructions>$")
  expect_false(grepl("@", vig, fixed = TRUE))
  expect_false(grepl("root rule", vig, fixed = TRUE))
})

test_that("an @file line naming an existing file outside the project is dropped", {
  # P01's path_rel() gives an absolute path (never "..") for a path outside the root
  outside = withr::local_tempdir("gptr-outside-")
  writeLines("- outside rule", file.path(outside, "rules.md"))
  rel = paste0("../", basename(outside), "/rules.md")
  root = p07_project(list(".gptr/vignette.Rmd" = c("# Project", paste0("@", rel), "- kept")))
  expect_true(file.exists(file.path(root, rel)))
  expect_identical(context_vignette_includes(paste0("# Project\n@", rel, "\n- kept"), root),
                   "# Project\n- kept")
  s = p07_session("manual")
  vig = Filter(function(x) identical(x$attrs$path, ".gptr/vignette.Rmd"),
               context_first_message(s, list(turn = 1L)))[[1]]$text
  expect_match(vig, "\n# Project\n- kept\n</project_instructions>$")
  expect_false(grepl("outside rule", vig, fixed = TRUE))
})

test_that("@file lines never include control, protected or secret-shaped project files", {
  inc = c("@.env", "@.secrets/x.env", "@.gptr/settings.json", "@.git/config", "@.Renviron",
          "@keys/id_rsa", "@credentials.json", "@docs/style.md")
  root = p07_project(list("docs/style.md" = "- style rule", ".env" = "DB_PASSWORD=fixture-a",
                          ".secrets/x.env" = "fixture-b", ".gptr/settings.json" = "{}",
                          ".git/config" = "[core]", ".Renviron" = "FIXTURE=c",
                          "keys/id_rsa" = "fixture-d", "credentials.json" = "{}",
                          ".gptr/vignette.Rmd" = c("# Project", inc)))
  expect_identical(context_vignette_includes(paste(c("# Project", inc), collapse = "\n"), root),
                   "# Project\n- style rule")
  s = p07_session("manual")
  vig = Filter(function(x) identical(x$attrs$path, ".gptr/vignette.Rmd"),
               context_first_message(s, list(turn = 1L)))[[1]]$text
  expect_match(vig, "\n# Project\n- style rule\n</project_instructions>$")
  expect_false(grepl("fixture", vig, fixed = TRUE))
  # a symlink is judged by its target as well as by its own name
  ok = suppressWarnings(file.symlink(file.path(root, ".env"), file.path(root, "docs", "env.md")))
  skip_if_not(isTRUE(ok), "symbolic links are not available")
  expect_identical(context_vignette_includes("@docs/env.md\n@docs/style.md", root), "- style rule")
})

test_that("a file above 64 KiB is cut at a line boundary", {
  big = paste(rep(strrep("x", 99), 700), collapse = "\n")
  out = context_cap_64k(big)
  expect_lte(nchar(out, type = "bytes"), 65536L)
  expect_true(endsWith(out, "[... file truncated at 64 KiB]"))
})

test_that("the first message follows architecture 7.4 with the anchor on the project block", {
  p07_project(list("AGENTS.md" = "- Use = for assignment.",
                   ".gptr/vignette.Rmd" = "# Project\n- data in data/"))
  s = p07_session("manual")
  b = context_first_message(s, list(call = mtcars_call(), turn = 1L, prompt = "hi"))
  expect_identical(block_kinds(b)[1:4], c("project_instructions", "project_instructions",
                                          "environment", "mode"))
  expect_true(isTRUE(b[[2]]$anchor))
  expect_false(isTRUE(b[[1]]$anchor))
  expect_identical(b[[1]]$text, paste0("<project_instructions path=\"AGENTS.md\" ",
                                       "trusted=\"false\">\n- Use = for assignment.\n",
                                       "</project_instructions>"))
  expect_identical(b[[2]]$attrs$path, ".gptr/vignette.Rmd")
  expect_length(prompt_frames$stack, 0L)
})

test_that("session_start blocks follow the registered blocks of the first message", {
  p07_project(list())
  s = p07_session()
  start = list(blocks = list(block_context("lab", "cohort B"), "plain note"))
  b = context_first_message(s, list(turn = 1L, start = start))
  k = block_kinds(b)
  expect_identical(k[(length(k) - 1L):length(k)], c("lab", "text"))
})

test_that("an untrusted project renders trusted=\"false\"; a trusted one does not (IC-52)", {
  p07_project(list("AGENTS.md" = "- rule"))
  s = p07_session("manual")
  b = context_first_message(s, list(turn = 1L))
  expect_match(b[[1]]$text, "<project_instructions path=\"AGENTS.md\" trusted=\"false\">",
               fixed = TRUE)
  local_mocked_bindings(prompt_trusted = function(root) TRUE)
  b2 = context_first_message(s, list(turn = 1L))
  expect_match(b2[[1]]$text, "<project_instructions path=\"AGENTS.md\">", fixed = TRUE)
})

test_that("untrusted project files are withheld non-interactively in auto; the user's stay", {
  user_agents("- my own rule")
  p07_project(list("AGENTS.md" = "- project rule"))
  local_gptr_options(quiet = FALSE)
  s = p07_session("auto")
  b = NULL
  expect_message({
    b = context_first_message(s, list(turn = 1L))
  }, class = "gptr_message_notice")
  proj = Filter(function(x) identical(x$kind, "project_instructions"), b)
  expect_length(proj, 1L)
  expect_match(proj[[1]]$text, "- my own rule", fixed = TRUE)
  expect_false(grepl("trusted=", proj[[1]]$text, fixed = TRUE))
  expect_false(grepl("project rule", proj[[1]]$text, fixed = TRUE))
})

test_that("the environment block states date, directory, front end and R", {
  p07_project(list())
  local_mocked_bindings(front_end = function() "rstudio")
  s = p07_session()
  env = Filter(function(b) identical(b$kind, "environment"),
               context_first_message(s, list(turn = 1L)))[[1]]$text
  lines = strsplit(env, "\n", fixed = TRUE)[[1]]
  n = length(lines)
  expect_identical(lines[c(1, n)], c("<environment>", "</environment>"))
  expect_identical(lines[2], paste0("Date: ", format(Sys.Date(), "%Y-%m-%d")))
  expect_match(lines[3], "^Working directory: .* \\(project root\\)$")
  expect_true("Front end: interactive console (RStudio)" %in% lines)
  expect_match(lines[n - 1], paste0("^R ", R.version$major, "\\.", R.version$minor, " on "))
  expect_lte(prompt_est(env), 100)
})

test_that("mode blocks carry the non-interactive suffixes of contract 9.3", {
  tx = prompt_texts()
  expect_identical(context_mode_body("manual", TRUE), tx$mode_manual)
  expect_identical(context_mode_body("manual", FALSE),
                   paste(tx$mode_manual, tx$noninteractive_manual))
  expect_identical(context_mode_body("auto", FALSE), paste(tx$mode_auto, tx$noninteractive_stop))
  expect_identical(context_mode_body("edits", FALSE, deny = TRUE),
                   paste(tx$mode_edits, tx$noninteractive_deny))
  p07_project(list())
  s = p07_session("plan")
  m = Filter(function(x) identical(x$kind, "mode"), context_first_message(s, list(turn = 1L)))[[1]]
  expect_identical(m$attrs$name, "plan")
  expect_match(m$text, "^<mode name=\"plan\">\nPlan mode is on: read-only.")
})

test_that("the plan block hands over a pending plan once, never in plan mode", {
  e = new.env()
  seen = new.env()
  seen$consume = NULL
  local_mocked_bindings(
    ext_service_has = function(name) identical(name, "plan.pending"),
    ext_service_get = function(name) {
      function(address, consume = TRUE) {
        seen$consume = consume
        structure("1. drop tmp files", from = "s0123456789")
      }
    }
  )
  ctx = list(input = list(mode = "manual", call = list(envir = e), preview = FALSE),
             session = NULL)
  out = context_provide_plan(ctx, 1500L)
  expect_identical(out$text, "1. drop tmp files")
  expect_identical(out$attrs$from, "s0123456789")
  expect_true(seen$consume)
  ctx$input$preview = TRUE
  context_provide_plan(ctx, 1500L)
  expect_false(seen$consume)
  ctx$input$mode = "plan"
  expect_null(context_provide_plan(ctx, 1500L))
})

test_that("an unchanged turn block is sent once; a changed one again (IC-38)", {
  p07_project(list())
  box = new.env()
  box$text = "cohort B only"
  off = gptr_register(gptr_context_block("lab", function(ctx, budget) box$text,
                                         placement = "both", order = 650L))
  withr::defer(off())
  s = p07_session()
  first = context_first_message(s, list(turn = 1L, prompt = "one"))
  expect_true("lab" %in% block_kinds(first))
  append_user(s, first, "one")
  expect_length(context_turn_blocks(s, list(turn = 2L, prompt = "two")), 0L)
  box$text = "cohort C only"
  t3 = context_turn_blocks(s, list(turn = 3L, prompt = "three"))
  expect_identical(block_kinds(t3), "lab")
  append_user(s, t3, "three")
  session_set_mode(s, "edits")
  t4 = context_turn_blocks(s, list(turn = 4L, prompt = "four"))
  expect_identical(block_kinds(t4), "mode")
  expect_identical(t4[[1]]$attrs$name, "edits")
})

test_that("the mode provider reads the session when the kernel calls it without an input", {
  p07_project(list())
  s = p07_session("manual")
  session_set_mode(s, "auto")
  out = registry_get("context_block", "mode")$provide(session_live(s)$ctx, 150L)
  expect_identical(out$attrs$name, "auto")
  expect_identical(out$text, context_mode_body("auto", FALSE))
})

test_that("a mode the kernel announced mid-run is not sent again as a turn block", {
  p07_project(list())
  s = p07_session("manual")
  append_user(s, context_first_message(s, list(turn = 1L, prompt = "one")), "one")
  session_set_mode(s, "auto")
  mode = Filter(function(b) identical(b$kind, "mode"), context_turn_blocks(s, list(turn = 2L)))
  expect_length(mode, 1L)
  # the session kernel's shape of the operator mode note (P06 entry_message())
  session_append(s, list(type = "custom_message", custom_type = "gptr.operator",
                         message = msg_operator("mode", mode[[1]]$text)))
  expect_false("mode" %in% block_kinds(context_turn_blocks(s, list(turn = 2L))))
})

test_that("a changed instruction file is announced once as project_instructions_update", {
  root = p07_project(list("AGENTS.md" = "- rule one"))
  s = p07_session("manual")
  first = context_first_message(s, list(turn = 1L, prompt = "one"))
  append_user(s, first, "one")
  expect_false("project_instructions_update" %in%
                 block_kinds(context_turn_blocks(s, list(turn = 2L))))
  writeLines("- rule two", file.path(root, "AGENTS.md"))
  t2 = context_turn_blocks(s, list(turn = 2L))
  upd = Filter(function(b) identical(b$kind, "project_instructions_update"), t2)
  expect_length(upd, 1L)
  expect_identical(upd[[1]]$text, paste0("<project_instructions_update path=\"AGENTS.md\" ",
                                         "trusted=\"false\">\n- rule two\n",
                                         "</project_instructions_update>"))
  append_user(s, t2, "two")
  expect_false("project_instructions_update" %in%
                 block_kinds(context_turn_blocks(s, list(turn = 3L))))
})

test_that("a project file dropped at compaction is announced again only when it changes", {
  root = p07_project(list("AGENTS.md" = "- rule one"))
  s = p07_session("manual")
  first = context_first_message(s, list(turn = 1L, prompt = "one"))
  append_user(s, first, "one")
  proj = Filter(function(b) identical(b$kind, "project_instructions"), first)[[1]]
  # a compaction whose re-injection budget dropped AGENTS.md (IC-71; Task 13 writes details$dropped)
  session_append(s, list(type = "compaction", summary = "s", first_kept_entry_id = NULL,
                         tokens_before = 1,
                         details = list(reason = "threshold",
                                        dropped = list(AGENTS.md = hash_sha256(proj$text))),
                         usage = NULL, gptr = list(blocks = list(block_text("c")),
                                                   state = list(), n = 1L)))
  expect_false("project_instructions_update" %in%
                 block_kinds(context_turn_blocks(s, list(turn = 2L))))
  writeLines("- rule two", file.path(root, "AGENTS.md"))
  expect_true("project_instructions_update" %in%
                block_kinds(context_turn_blocks(s, list(turn = 2L))))
})

test_that("blocks the transcript stores redacted are deduplicated all the same (IC-38)", {
  key = "OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123"
  root = p07_project(list("AGENTS.md" = paste("- set", key, "in .Renviron")))
  off = gptr_register(gptr_context_block("lab", function(ctx, budget) {
    "db at postgres://ana:pa55word@db.local/x"
  }, placement = "both", order = 650L))
  withr::defer(off())
  off2 = gptr_register(gptr_context_block("budget_note", function(ctx, budget) {
    "Authorization: Bearer abcdef0123456789abcdef"
  }, placement = "turn", authority = "operator"))
  withr::defer(off2())
  s = p07_session("manual")
  append_user(s, context_first_message(s, list(turn = 1L, prompt = "one")), "one")
  path = prompt_path(s)
  stored = paste(vapply(path[[length(path)]]$message$content, function(b) b$text %||% "", ""),
                 collapse = "\n")
  # P06's session_append() redacts entries with the persist profile
  expect_match(stored, "[secret:", fixed = TRUE)
  expect_false(grepl("sk-proj-|pa55word", stored))
  memo = session_live(s)$memo
  for (turn in 2:3) {
    t = context_turn_blocks(s, list(turn = turn))
    expect_length(t, 0L)
    queued = get0("prompt_pending", envir = memo, inherits = FALSE)
    expect_length(queued, if (turn == 2L) 1L else 0L)
    prompt_pending_flush(s)
    append_user(s, t, "next")
  }
  writeLines(paste("- set", sub("abcdef", "zyxwvu", key, fixed = TRUE), "in ~/.Renviron"),
             file.path(root, "AGENTS.md"))
  t4 = context_turn_blocks(s, list(turn = 4L))
  expect_identical(block_kinds(t4), "project_instructions_update")
  append_user(s, t4, "four")
  expect_length(context_turn_blocks(s, list(turn = 5L)), 0L)
})

test_that("operator-authority blocks are queued as operator messages, not user blocks", {
  p07_project(list())
  off = gptr_register(gptr_context_block("budget_note", function(ctx, budget) "80% used",
                                         placement = "turn", authority = "operator"))
  withr::defer(off())
  s = p07_session()
  b = context_turn_blocks(s, list(turn = 2L, prompt = "x"))
  expect_false("budget_note" %in% block_kinds(b))
  q = get0("prompt_pending", envir = session_live(s)$memo, inherits = FALSE)
  expect_identical(q[[1]]$kind, "reminder")
  expect_match(msg_text(q[[1]]), "<budget_note>\n80% used\n</budget_note>", fixed = TRUE)
  expect_identical(prompt_pending_flush(s), 1L)
  context_turn_blocks(s, list(turn = 3L, prompt = "y"))
  expect_length(get0("prompt_pending", envir = session_live(s)$memo, inherits = FALSE), 0L)
})

test_that("a failing provide() omits its block and records a diagnostic", {
  p07_project(list())
  off = gptr_register(gptr_context_block("broken", function(ctx, budget) stop("no data"),
                                         placement = "first"))
  withr::defer(off())
  s = p07_session()
  b = context_first_message(s, list(turn = 1L))
  expect_false("broken" %in% block_kinds(b))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "context_block:broken"))
})

test_that("the context blocks and services are P07's", {
  nm = vapply(prompt_specs("context_block"), function(x) x$name, "")
  expect_true(all(c("project_instructions", "environment", "mode", "plan") %in% nm))
  expect_identical(ext_service_get("context.first"), context_first_message)
  expect_identical(ext_service_get("context.turn"), context_turn_blocks)
})
