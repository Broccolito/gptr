# tests/testthat/test-console-ui.R -- UI backends, the approval prompt and ui.get (P11)

ui_request = function(code, tier = "ask", rule = NULL) {
  risk = gptr_risk(code)
  list(tool = "r", input = list(code = code), summary = strsplit(code, "\n")[[1]], risk = risk,
       reason = paste0("mode manual, risk level ", risk$level), suggested_rule = rule,
       undo_note = NULL, session = "s0000000001", turn = 1L, nested = FALSE, tier = tier)
}

# Run `fun()` with gptr_readline() answering from `answers`; returns the result and the
# printed lines
console_try = function(fun, answers) {
  i = 0L
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    i <<- i + 1L
    if (i > length(answers)) NA_character_ else answers[[i]]
  })
  res = NULL
  shown = utils::capture.output({
    res = fun()
  })
  list(result = res, shown = shown, asked = i)
}

test_that("displays escape C0/C1 controls, bidi and zero-width characters (IC-53 item 8)", {
  expect_identical(ui_escape("a\u202eb\u200bc\td\u2066"), "a<U+202E>b<U+200B>c\td<U+2066>")
  expect_identical(ui_escape(c("\u001b[2J", "ok", NA)), c("<U+001B>[2J", "ok", NA))
  # literals mixing U+0080-U+00FF with higher code points are mis-encoded by R's parser in a
  # C locale, so each literal stays on one side
  expect_identical(ui_escape(c("\u0085x", "y\u061c")), c("<U+0085>x", "y<U+061C>"))
})

test_that("console select preserves title line feeds but escapes other controls and labels", {
  out = console_try(function() {
    ui_console_select("First line\nSecond line\033[2J", c("One\nInjected", "Two"))
  }, "2")
  expect_identical(out$result, 2L)
  text = paste(out$shown, collapse = "\n")
  expect_match(text, "First line\nSecond line<U+001B>[2J", fixed = TRUE)
  expect_match(text, "1: One<U+000A>Injected", fixed = TRUE)
  expect_false(grepl("\033", text, fixed = TRUE))
})

test_that("a console select outside a run opens its own block in the margin (D-186)", {
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_gptr_options(verbose = 2L)
  withr::local_options(cli.dynamic = TRUE)
  out = console_try(function() ui_console_select("Rewind to", c("a", "b")), "1")
  expect_identical(out$shown, c("", "  Rewind to", "", "  1: a", "  2: b", ""))
})

test_that("the one-line prompt shows the first line, +N more lines and the flagged calls", {
  root = local_project()
  # R's parser refuses bidi controls inside string literals in UTF-8 locales, so the payload
  # sits in comments, where it parses everywhere
  req = ui_request(paste0("note = 1 # \u001b[2J\u202e\nwrite.csv(df, 'out.csv')\n",
                          "# \u001b[2J clear\nunlink('data', recursive = TRUE)"))
  lines = ui_permission_lines(req)
  expect_identical(lines[1L], "  r  note = 1 # <U+001B>[2J<U+202E>  (+3 more lines)")
  expect_identical(lines[2:3], c("     flagged: [3 file_delete] unlink(\"data\", recursive = TRUE)",
                                 "              [2 file_write] write.csv(df, \"out.csv\")"))
  expect_false(any(grepl("[\u0001-\u0008\u000b-\u001f\u007f\u202e]", lines, perl = TRUE)))
  detail = ui_permission_detail(req)
  expect_true(any(grepl("<U+001B>[2J clear", detail, fixed = TRUE)))
  expect_false(any(grepl("\u001b", detail, fixed = TRUE)))
  expect_true(any(grepl("[3] file_delete", detail, fixed = TRUE)))
  w = list(tool = "write", input = list(path = "notes.md"), risk = list(level = 2L))
  expect_identical(ui_permission_lines(w), "  write  notes.md")
})

test_that("the prompt's first line fits the console, keeping +N more lines (D-187)", {
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  req = ui_request(paste0("x = c(", strrep("1, ", 30L), "1)\ny = 2"))
  first = ui_permission_lines(req)[1L]
  expect_identical(first, "  r  x = c(1, 1, 1, ...  (+1 more lines)")
  withr::local_options(cli.dynamic = TRUE)
  local_gptr_options(verbose = 2L)
  expect_identical(nchar(ui_permission_lines(req)[1L]), 38L)
})

test_that("flagged calls fit one per line, highest level first, at most 5 (#33)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 40, crayon = FALSE, unicode = FALSE)
  root = local_project()
  code = c(sprintf("writeLines('%s', 'f%d.txt')", strrep("x", 30L), 1:7), "unlink('data')")
  lines = ui_permission_lines(ui_request(paste(code, collapse = "\n")))
  expect_length(lines, 7L)
  expect_true(all(nchar(lines) <= 40L))
  expect_identical(lines[2L], "     flagged: [3 file_delete] unlink(...")
  expect_identical(lines[3L], "              [2 file_write] writeLin...")
  expect_identical(lines[7L], "              (+3 more; ? shows all)")
})

test_that("a path tool's prompt shows the path relative to the project; no empty label (#33)", {
  root = local_project()
  # a tool's own risk record, as the dispatcher passes it: no label
  w = list(tool = "write", input = list(path = file.path(root, "R", "io.R")),
           risk = list(level = 2L, categories = "write", paths = "R/io.R"))
  expect_identical(ui_permission_lines(w), "  write  R/io.R")
  detail = ui_permission_detail(w)
  expect_identical(detail[1:4], c("  gptr wants to use write (level 2)", "  ```", "  R/io.R",
                                  "  ```"))
  expect_match(ui_permission_detail(ui_request("x = 1"))[1L], "(level 1: local)", fixed = TRUE)
})

test_that("[a]lways is offered only with a suggested rule; a and p say why not (#33)", {
  root = local_project()
  e = new.env()
  e$x = 1
  req = ui_request("x = 2")
  req$risk = gptr_risk("x = 2", envir = e)
  expect_null(rule_suggest(list(name = "r", risk = req$risk)))
  out = console_try(function() ui_console_permission(req), c("?", "a", "p", "y"))
  expect_identical(out$result, list(decision = "allow", remember = NULL, feedback = NULL))
  expect_false(any(grepl("[a] always", out$shown, fixed = TRUE)))
  expect_identical(sum(out$shown == paste0("  [a]lways is not offered: no rule covers these ",
                                           "calls; answer y, n or ?.")), 2L)
  expect_null(ui_answer_norm(list(decision = "allow", remember = "session"), req)$remember)
})

test_that("the detail view shows the code as a plain fence of at most 40 lines (D-187)", {
  root = local_project()
  code = sprintf("x%d = %d", 1:45, 1:45)
  detail = ui_permission_detail(ui_request(paste(code, collapse = "\n")))
  at = match("  ```r", detail)
  expect_identical(detail[at + 1:42],
                   c(paste0("  ", code[1:40]), "  # ... +5 more lines", "  ```"))
  expect_false(any(grepl("\033", detail, fixed = TRUE)))
  expect_true("  ````r" %in% ui_permission_detail(ui_request("x = '\n```\n'")))
  py = list(tool = "py", input = list(code = "a = 1"), risk = list(level = 2L))
  expect_identical(ui_permission_detail(py)[2:4], c("  ```", "  a = 1", "  ```"))
})

test_that("the console prompt maps y, a, p, n, n <feedback>, ? and Ctrl-C (6.8.3)", {
  root = local_project()
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  out = console_try(function() ui_console_permission(req), "y")
  expect_identical(out$result, list(decision = "allow", remember = NULL, feedback = NULL))
  expect_match(out$shown[1L], "write.csv", fixed = TRUE)
  expect_identical(console_try(function() ui_console_permission(req), "a")$result$remember,
                   "session")
  expect_identical(console_try(function() ui_console_permission(req), "p")$result$remember,
                   "project")
  expect_identical(console_try(function() ui_console_permission(req), "n")$result$decision,
                   "deny")
  fb = console_try(function() ui_console_permission(req), "n use write_csv instead")$result
  expect_identical(fb$feedback, "use write_csv instead")
  out = console_try(function() ui_console_permission(req), c("?", "y"))
  expect_identical(out$result$decision, "allow")
  expect_true(any(grepl("[a] always in this session: r(fn:write.csv)", out$shown, fixed = TRUE)))
  expect_identical(console_try(function() ui_console_permission(req), character())$result$decision,
                   "abort")
  crit = ui_request("q('no')", tier = "ask_human")
  out = console_try(function() ui_console_permission(crit), c("a", "y"))
  expect_identical(out$result$remember, NULL)
  expect_identical(out$asked, 2L)
})

test_that("lines typed or pasted before the approval prompt never answer it (IC-75)", {
  root = local_project()
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  rl = local_readline(c("h$config$codex", "y", "n"), secs = c(0.001, 0.001, 1.5))
  res = NULL
  utils::capture.output({
    res = ui_console_permission(ui_request("zz = 1"))
  })
  expect_identical(res$decision, "deny")
  expect_identical(rl$i, 3L)
})

test_that("a block pasted at the approval prompt never answers it nor steers (IC-75)", {
  skip_on_cran()
  local_console_test()
  local_gptr_options(interactive = TRUE)
  # fd 0 as one buffer: the rest of a paste whose first line answers the question waits there
  fd0 = new.env(parent = emptyenv())
  fd0$lines = character()
  fd0$answers = c("go", "y", "n", "/exit")
  fd0$prompts = character()
  reader = console_reader
  local_mocked_bindings(
    repl_terminal = function(rs) TRUE,
    console_typed_lines = function(rd, ...) {
      x = fd0$lines
      fd0$lines = character()
      x
    },
    console_reader = function(...) {
      rd = reader(...)
      rd$waiting = function() console_typed_lines(rd)
      rd
    },
    gptr_readline = function(prompt = "", ...) {
      x = fd0$answers[[1L]]
      fd0$answers = fd0$answers[-1L]
      fd0$prompts = c(fd0$prompts, prompt)
      if (identical(x, "y")) fd0$lines = c("pasted line two", "pasted line three")
      the$readline_secs = 1
      x
    })
  withr::defer(assign("readline_secs", NULL, envir = the))
  e = new.env()
  fake = gptr_fake_provider(list(fake_tool("r", code = "zz = 2", .text = "hmm"), "after"))
  rs = repl_state(NULL, e)
  rs$model = fake
  rs$mode = "manual"
  out = utils::capture.output(repl_main(rs))
  expect_null(e$zz)
  expect_identical(sum(startsWith(fd0$prompts, "  allow?")), 2L)
  expect_identical(sum(out == "  A pasted block is not an answer (3 lines dropped)."), 1L)
  expect_false(any(grepl("Not an answer", out, fixed = TRUE)))
  reqs = fake_requests(fake)
  expect_length(reqs, 2L)
  texts = vapply(reqs[[2L]]$messages, msg_text, "")
  expect_false(any(grepl("pasted line", texts, fixed = TRUE)))
  expect_length(rs$reader$typed, 0L)
})

test_that("a sub-agent's prompt and detail view name it; ask_human says why (D-188)", {
  root = local_project()
  req = ui_request("x = 1")
  expect_identical(ui_permission_lines(req)[1L], "  r  x = 1")
  expect_identical(ui_permission_lines(c(req, agent = "main"))[1L], "  r  x = 1")
  expect_identical(ui_permission_lines(c(req, agent = "alpha"))[1L], "  sub-agent alpha > r  x = 1")
  expect_identical(ui_permission_lines(c(req, agent = "'Sum\033...'"))[1L],
                   "  sub-agent 'Sum<U+001B>...' > r  x = 1")
  expect_match(ui_permission_detail(c(req, agent = "alpha"))[1L],
               "^  sub-agent alpha wants to use r \\(level")
  expect_match(ui_permission_detail(req)[1L], "^  gptr wants to use r")
  crit = ui_request("q('no')", tier = "ask_human")
  expect_identical(utils::tail(ui_permission_lines(crit), 1L),
                   paste0("     asks in every mode: ", crit$reason))
  expect_false(any(grepl("every mode", ui_permission_lines(req), fixed = TRUE)))
})

test_that("nested calls with the same prompt are told apart by their number (#36)", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80, crayon = FALSE, unicode = FALSE)
  local_project()
  sub = local_fake_provider(function(request) {
    if (length(request$last_results)) "child done" else fake_tool("r", code = "x = 1")
  }, name = "sub")
  code = "for (id in 1:2) peter('You are annotating one cluster of the object', model = sub)"
  fake = local_fake_provider(function(request) {
    if (length(request$last_results)) "parent done" else fake_tool("r", code = code)
  }, name = "main")
  local_gptr_options(mode = "manual", interactive = TRUE, verbose = 1L, quiet = FALSE,
                     ui = ui_console_spec(function(prompt, ...) "y"))
  e = new.env()
  e$sub = sub
  s = NULL
  out = utils::capture.output({
    s = peter("annotate", model = fake, envir = e)
  })
  expect_identical(s$text, "parent done")
  who = "  sub-agent 'You are annotating one cluster...' #"
  for (k in c("1", "2")) {
    expect_true(paste0(who, k, " > r  x = 1") %in% out, info = k)
    expect_true(paste0(who, k, " started (sub/sub-1)") %in% out, info = k)
    expect_true(any(startsWith(out, paste0(who, k, " done"))), info = k)
  }
})

test_that("invalid answers are explained; five end in a refusal the model is told (D-188)", {
  root = local_project()
  crit = ui_request("q('no')", tier = "ask_human")
  out = console_try(function() ui_console_permission(crit), c("a", "p", "y"))
  expect_identical(out$result$decision, "allow")
  expect_identical(sum(grepl("[a]lways is not offered: level-4 and control actions",
                             out$shown, fixed = TRUE)), 2L)
  req = ui_request("write.csv(df, 'out.csv')", rule = "r(fn:write.csv)")
  out = console_try(function() ui_console_permission(req), rep("zz", 5L))
  expect_identical(out$result, list(decision = "deny", remember = NULL,
                                    feedback = "no valid answer was given at the approval prompt"))
  expect_identical(sum(out$shown == paste0("  Not an answer: 'zz'. Type y, a, n (n <text> says ",
                                           "what to do instead) or ? for details.")), 5L)
  expect_identical(utils::tail(out$shown, 1L), "  No valid answer after 5 tries; refused.")
  # asking for details is not an invalid answer
  out = console_try(function() ui_console_permission(req), c("?", "?", "zz", "?", "zz", "?", "y"))
  expect_identical(out$result$decision, "allow")
  out = console_try(function() ui_console_permission(crit), c("maybe \033", "n"))
  expect_true(any(grepl("Not an answer: 'maybe <U+001B>'. Type y, n (n <text>", out$shown,
                        fixed = TRUE)))
})

test_that("the detail view shows the checkpoint.note service's undo note", {
  root = local_project()
  local_mocked_bindings(
    ext_service_has = function(name) identical(name, "checkpoint.note"),
    ext_service_get = function(name) function(call, run) "cannot be undone: pbmc 5.1 GB"
  )
  expect_true(any(grepl("cannot be undone: pbmc 5.1 GB",
                        ui_permission_detail(ui_request("pbmc = 1")), fixed = TRUE)))
})

test_that("ui.get resolves the snapshot of gptr.ui, else console or none (IC-43, IC-53)", {
  root = local_project()
  get_ui = ext_service_get("ui.get")
  expect_identical(get_ui()$name, "none")
  local_gptr_options(interactive = TRUE)
  expect_identical(get_ui()$name, "console")
  local_gptr_options(ui = "rstudio")
  expect_identical(get_ui()$name, "rstudio")
  local_gptr_options(ui = "no-such-ui", interactive = FALSE)
  expect_identical(get_ui()$name, "none")
  run = new.env(parent = emptyenv())
  run$id = "u00000001"
  run$session = "s0000000001"
  run$opts = list(safety = list(ui = "console", interactive = TRUE))
  local_mocked_bindings(run_current = function() run)
  expect_identical(get_ui()$name, "console")
  run$opts = list(safety = list(ui = ui_scripted_spec(ui_scripted_state(list()), "probe")))
  expect_identical(get_ui()$name, "probe")
  # P06's snapshot carries can_prompt; it wins over the live options (IC-53 item 2)
  local_gptr_options(interactive = TRUE)
  run$opts = list(safety = list(ui = NULL, interactive = NULL, can_prompt = FALSE))
  expect_identical(get_ui()$name, "none")
  run$opts = list(safety = list(ui = NULL, interactive = NULL, can_prompt = TRUE))
  local_gptr_options(interactive = FALSE)
  expect_identical(get_ui()$name, "console")
})

test_that("a failing or empty dialog is never an approval (10.2 row 22)", {
  broken = gptr_spec("ui", "broken", has_ui = function() TRUE,
                     select = function(title, choices, ...) stop("dialog crashed"),
                     permission = function(request) stop("dialog crashed"))
  ans = ui_wrap(broken)$permission(ui_request("unlink('x')"))
  expect_identical(ans$decision, "deny")
  odd = gptr_spec("ui", "odd", has_ui = function() TRUE, select = function(...) 1L,
                  permission = function(request) list(decision = "maybe"))
  expect_identical(ui_wrap(odd)$permission(ui_request("unlink('x')"))$decision, "deny")
  none = ui_wrap(ui_none_spec())
  expect_false(none$has_ui())
  expect_identical(none$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_true(none$questions(list(list(id = "a", question = "?")))$cancelled)
  expect_true(is.na(none$input("Name?")))
})

test_that("the rstudio UI has no UI outside RStudio and then denies", {
  rs = ui_rstudio_spec()
  skip_if(requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable(),
          "running inside RStudio")
  expect_false(rs$has_ui())
  expect_identical(rs$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_true(is.na(rs$select("t", c("a", "b"))))
})

test_that("the scripted UI answers in order, logs and fails closed when empty (12.2)", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("y", list(decision = "deny", feedback = "use a temp file"), 2L,
                              "fit", list(fmt = "Table")))
  ui = ext_service_get("ui.get")()
  expect_identical(ui$name, "scripted")
  expect_identical(ui$permission(ui_request("unlink('x')"))$decision, "allow")
  ans = ui$permission(ui_request("unlink('x')"))
  expect_identical(ans$feedback, "use a temp file")
  expect_identical(ui$select("Pick", c("a", "b")), 2L)
  expect_identical(ui$input("Name?"), "fit")
  expect_identical(ui$questions(list(list(id = "fmt", question = "Format?")))$answers,
                   list(fmt = "Table"))
  expect_identical(st$remaining(), 0L)
  expect_identical(ui$permission(ui_request("unlink('x')"))$decision, "deny")
  expect_identical(st$log$method, c("permission", "permission", "select", "input", "questions",
                                    "permission"))
})

test_that("answering [a]lways adds a session rule covering exactly the flagged calls", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("a", "p", "a"))
  ui = ext_service_get("ui.get")()
  code = "write.csv(df, 'results/a.csv')\nsaveRDS(df, 'results/df.rds')"
  expect_identical(ui$permission(ui_request(code, rule = "r(fn:write.csv,saveRDS)"))$remember,
                   "session")
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
  w = list(tool = "write", input = list(path = "results/t.csv"), risk = list(level = 2L),
           suggested_rule = "write(results/**)", tier = "ask")
  expect_identical(ui$permission(w)$remember, "project")
  expect_true("write(results/**)" %in% perm_rules_effective()$allow)
  gptr_permissions(remove = "write(results/**)", scope = "project")
  ans = ui$permission(ui_request("rm(list = ls())", tier = "ask_human"))
  expect_identical(ans$decision, "allow")
  expect_null(ans$remember)
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
})

test_that("[a]lways in a run covers the same calls in the next run (05 P11 acceptance 5)", {
  skip_on_cran()
  root = local_project()
  local_permission_rules()
  st = local_scripted_ui(list("a"))
  code = "write.csv(mtcars, 'a.csv'); saveRDS(mtcars, 'b.rds')"
  fake = local_fake_provider(list(fake_tool("r", code = code), "Saved.",
                                  fake_tool("r", code = code), "Saved again."))
  peter("Save mtcars.", model = fake, envir = new.env(), mode = "manual")
  expect_true(file.exists(file.path(root, "a.csv")))
  expect_identical(perm_store()$allow, "r(fn:write.csv,saveRDS)")
  unlink(file.path(root, c("a.csv", "b.rds")))
  peter("Save mtcars again.", model = fake, envir = new.env(), mode = "manual")
  expect_true(file.exists(file.path(root, "a.csv")))
  expect_identical(st$remaining(), 0L)
  expect_identical(sum(st$log$method == "permission"), 1L)
})
