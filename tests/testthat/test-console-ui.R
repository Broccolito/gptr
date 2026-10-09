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
  }, type = "message")
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

test_that("the one-line prompt shows the first line, +N more lines and every flagged call", {
  root = local_project()
  # R's parser refuses bidi controls inside string literals in UTF-8 locales, so the payload
  # sits in comments, where it parses everywhere
  req = ui_request(paste0("note = 1 # \u001b[2J\u202e\nwrite.csv(df, 'out.csv')\n",
                          "# \u001b[2J clear\nunlink('data', recursive = TRUE)"))
  lines = ui_permission_lines(req)
  expect_identical(lines[1L], "  r  note = 1 # <U+001B>[2J<U+202E>  (+3 more lines)")
  expect_match(lines[2L], "write.csv(df, \"out.csv\") [2 file_write]", fixed = TRUE)
  expect_match(lines[2L], "unlink(\"data\", recursive = TRUE) [3 file_delete]", fixed = TRUE)
  expect_false(any(grepl("[\u0001-\u0008\u000b-\u001f\u007f\u202e]", lines, perl = TRUE)))
  detail = ui_permission_detail(req)
  expect_true(any(grepl("<U+001B>[2J clear", detail, fixed = TRUE)))
  expect_false(any(grepl("\u001b", detail, fixed = TRUE)))
  expect_true(any(grepl("[3] file_delete", detail, fixed = TRUE)))
  w = list(tool = "write", input = list(path = "notes.md"), risk = list(level = 2L))
  expect_identical(ui_permission_lines(w), "  write  notes.md")
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
