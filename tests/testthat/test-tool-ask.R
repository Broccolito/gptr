# tests/testthat/test-tool-ask.R -- the ask tool (P11)

ask_ctx = function(mode = "manual") {
  list(session = NULL, mode = function() mode,
       ui = function() ext_service_get("ui.get")(),
       has_ui = function() isTRUE(ext_service_get("ui.get")()$has_ui()))
}

ask_input = function(...) list(questions = list(...))

test_that("the ask schema and description are byte-identical to contract 9.2", {
  spec = registry_get("tool", "ask")
  expect_identical(spec$description, paste0(
    "Ask the user one to four questions and wait for the answers, when a decision changes the ",
    "result and cannot be inferred. The user may always type their own answer. Not for ",
    "permission to run code: the harness asks for that itself."))
  expect_identical(as.character(json_encode(ask_parameters())), paste0(
    "{\"type\":\"object\",\"required\":[\"questions\"],\"properties\":{\"questions\":",
    "{\"type\":\"array\",\"maxItems\":4,\"items\":{\"type\":\"object\",\"required\":",
    "[\"id\",\"question\"],\"properties\":{\"id\":{\"type\":\"string\"},\"question\":",
    "{\"type\":\"string\"},\"type\":{\"enum\":[\"single\",\"multi\",\"text\"]},\"options\":",
    "{\"type\":\"array\",\"maxItems\":9,\"items\":{\"type\":\"string\"}},\"default\":",
    "{\"type\":\"string\"}}}}}}"))
  expect_identical(spec$snippet,
                   "Ask the user one to four questions when a decision changes the result")
  expect_identical(spec$exposure, "direct")
  expect_identical(spec$execution, "sequential")
  expect_identical(spec$risk(list(), NULL)$level, 0L)
  expect_true(isTRUE(spec$annotations$read_only))
})

test_that("ask is declared with a person, and in non-interactive manual runs (IC-68)", {
  expect_true(ask_available(ask_ctx("auto") |> utils::modifyList(list(has_ui = function() TRUE))))
  expect_true(ask_available(ask_ctx("manual")))
  expect_false(ask_available(ask_ctx("auto")))
  expect_false(ask_available(ask_ctx("plan")))
})

test_that("invalid questions are refused without asking (18 section 3.6)", {
  st = local_scripted_ui(list())
  bad = list(
    list(),
    ask_input(list(id = "a", question = "?"), list(id = "a", question = "??")),
    ask_input(list(id = "a", question = "?", type = "single", options = list("x"))),
    ask_input(list(id = "a", question = "?", type = "pick")),
    ask_input(list(id = "a", question = "?", options = as.list(letters[1:10]))),
    do.call(ask_input, rep(list(list(id = "a", question = "?")), 5))
  )
  for (input in bad) {
    res = ask_execute(input, ask_ctx())
    expect_true(res$is_error)
    expect_match(res$content[[1]]$text, "^Invalid ask call: ")
  }
  expect_identical(nrow(st$log), 0L)
})

test_that("answers come back as 18's result text and in details (18 section 3.6)", {
  st = local_scripted_ui(list(list(fmt = "Table", obj = structure("use a forest plot",
                                                                    other = TRUE),
                                   cols = c("a", "b"))))
  input = ask_input(list(id = "fmt", question = "Format?", options = list("Plot", "Table")),
                    list(id = "obj", question = "Which object?", type = "text"),
                    list(id = "cols", question = "Columns?", type = "multi",
                         options = list("a", "b", "c")))
  res = ask_execute(input, ask_ctx())
  expect_false(res$is_error)
  expect_identical(res$content[[1]]$text, paste(
    "The user answered:", "- fmt: Table", "- obj: (typed) use a forest plot", "- cols: a, b",
    sep = "\n"))
  expect_false(res$details$cancelled)
  expect_identical(res$details$answers$fmt, "Table")
  expect_identical(st$log$method, "questions")
})

test_that("a cancelled or failing dialog returns the cancellation text", {
  st = local_scripted_ui(list())
  res = ask_execute(ask_input(list(id = "a", question = "Go?")), ask_ctx())
  expect_identical(res$content[[1]]$text, paste(
    "The user dismissed the questions without answering. Do not guess silently: either stop",
    "and summarise what you need, or proceed with clearly stated assumptions."))
  expect_true(res$details$cancelled)
  expect_false(res$is_error)
})

test_that("without a person the call ends the batch with an error result (NS-12)", {
  res = ask_execute(ask_input(list(id = "a", question = "Which file?")), ask_ctx("manual"))
  expect_true(res$is_error)
  expect_true(isTRUE(res$terminate))
  expect_match(res$content[[1]]$text, "No one can answer questions in this run", fixed = TRUE)
  expect_match(res$content[[1]]$text, "Which file?", fixed = TRUE)
})

test_that("in IRkernel the console UI answers through readline() (IC-43)", {
  local_gptr_options(interactive = NULL)
  withr::local_options(jupyter.in_kernel = TRUE)
  local_mocked_bindings(is_testthat = function() FALSE, check_running = function() FALSE,
                        is_knitting = function() FALSE, gptr_is_interactive = function() FALSE,
                        gptr_readline = function(prompt = "") "2")
  expect_true(gptr_can_prompt())
  ctx = ask_ctx("auto")
  expect_identical(ctx$ui()$name, "console")
  res = NULL
  utils::capture.output({
    res = ask_execute(ask_input(list(id = "fmt", question = "Format?",
                                     options = list("Plot", "Table"))), ctx)
  }, type = "message")
  expect_identical(res$content[[1]]$text, "The user answered:\n- fmt: Table")
})
