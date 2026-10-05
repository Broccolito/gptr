# Tests for R/tool-r.R: the four schema variants (IC-68), evaluation and the details record
# (contract 4.4), record and note, plan mode, images from gptr$plot(), bridge and artifact
# collection, risk, and (below) end-to-end runs through gptr() on the fake provider: the gptr shim,
# the value policy, nested gating and the fuzzy-edit diff (05 P10 acceptance 4-7).

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# A stand-in for P06's dispatch_nested(): runs the tool's execute with the input and returns its
# value
local_nested_dispatch = function(seen = new.env(), .env = parent.frame()) {
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$name = c(seen$name, name)
    res = registry_get("tool", name)$execute(input, ctx)
    res$value
  }, .env = .env)
  seen
}

test_that("the r schema is frozen in one of four variants (IC-68)", {
  props = function(document, human) names(r_schema(document, human)$properties)
  expect_identical(props(TRUE, FALSE), c("code", "record", "note", "timeout"))
  expect_identical(props(TRUE, TRUE), c("code", "record", "note"))
  expect_identical(props(FALSE, FALSE), c("code", "timeout"))
  expect_identical(props(FALSE, TRUE), "code")
  expect_identical(
    json_encode(r_schema(FALSE, TRUE)),
    paste0("{\"type\":\"object\",\"required\":[\"code\"],\"properties\":{\"code\":",
           "{\"type\":\"string\",\"description\":\"R code to evaluate. May contain several ",
           "expressions.\"}}}")
  )
  expect_identical(r_schema(TRUE, FALSE)$properties$timeout$description,
                   "Seconds; best effort. Default 3600.")
  variant = function(input) names(r_tool_parameters(list(input = input))$properties)
  expect_identical(variant(list(human = TRUE, document = NULL)), "code")
  expect_identical(variant(list(human = FALSE, document = list(path = "a.R"))),
                   c("code", "record", "note", "timeout"))
  spec = registry_get("tool", "r")
  expect_true(is.function(spec$parameters))
  expect_identical(spec$exposure, "direct")
  expect_identical(spec$snippet, paste("Run R code in the user's live session (objects persist;",
                                       "plots come back as images)"))
  expect_identical(length(spec$guidelines), 3L)
  expect_error(ns_resolve("r"), class = "gptr_error_unknown_member")
})

test_that("the r spec reproduces P07's stand-in in each of its four variants (IC-68)", {
  sb = jsonlite::fromJSON(test_path("fixtures", "bench", "prefix-baseline.json"),
                          simplifyVector = FALSE)$standins
  t = Filter(function(x) identical(x$name, "r"), sb$tools)[[1L]]
  spec = registry_get("tool", "r")
  expect_identical(spec$description, t$description)
  expect_identical(spec$snippet, t$snippet)
  expect_identical(as.character(spec$guidelines), as.character(unlist(t$guidelines)))
  for (doc in c(TRUE, FALSE)) {
    for (human in c(TRUE, FALSE)) {
      want = t$input_schema
      want$properties = want$properties[c("code", if (doc) c("record", "note"),
                                          if (!human) "timeout")]
      if (!human) want$properties$timeout$description = sb$r_timeout_short
      expect_identical(json_encode(r_schema(doc, human)), json_encode(want))
    }
  }
})

test_that("the r tool evaluates in ctx$envir outside a run and fills the details record", {
  e = new.env()
  e$keep = 1
  res = r_tool_execute(list(code = "x = 41\nx + 1", note = "one decision"),
                       list(envir = e, session = NULL))
  expect_s3_class(res, "gptr_tool_result")
  expect_false(res$is_error)
  expect_identical(e$x, 41)
  d = res$details
  expect_identical(d$code, "x = 41\nx + 1")
  expect_true(d$record)
  expect_identical(d$note, "one decision")
  expect_identical(d$status, "ok")
  expect_identical(d$n_done, 2L)
  expect_identical(d$n_total, 2L)
  expect_true("x" %in% d$objects$added)
  expect_false("keep" %in% c(d$objects$added, d$objects$modified))
  expect_identical(d$nested, list())
  expect_null(d$value)
  expect_match(ns_result_text(res), "42", fixed = TRUE)
  fields = c("code", "record", "note", "status", "n_done", "n_total", "objects", "plots",
             "warnings", "error", "changes", "elapsed", "out_id", "spill", "outputs", "nested",
             "bridge", "artifacts", "checkpoint", "value")
  expect_true(all(fields %in% names(d)))
})

test_that("an error stops the evaluation and is reported; plan mode never records", {
  e = new.env()
  res = r_tool_execute(list(code = "a = 1\nstop('boom')\nb = 2"), list(envir = e, session = NULL))
  expect_true(res$is_error)
  expect_identical(res$details$status, "error")
  expect_match(res$details$error, "boom", fixed = TRUE)
  expect_false(exists("b", envir = e, inherits = FALSE))
  plan_ctx = list(envir = e, session = NULL, mode = function() "plan")
  expect_false(r_tool_execute(list(code = "1", record = TRUE), plan_ctx)$details$record)
  plain_ctx = list(envir = e, session = NULL)
  expect_false(r_tool_execute(list(code = "1", record = FALSE), plain_ctx)$details$record)
  expect_error(r_tool_execute(list(code = "1"), list(envir = NULL, session = NULL)),
               class = "gptr_error_internal")
})

test_that("images attached by gptr$plot() during the evaluation are added to the result", {
  local_nested_dispatch()
  e = new.env()
  withr::local_pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  code = "graphics::plot(1:3)\nns_resolve(\"plot\")(width = 800L, height = 600L)"
  res = r_tool_execute(list(code = code), list(envir = e, session = NULL))
  imgs = Filter(function(b) identical(b$type, "image"), res$content)
  widths = vapply(imgs, function(b) as.integer(b$width %||% NA_integer_), 0L)
  expect_true(800L %in% widths)
  expect_identical(res$details$plots, length(imgs))
})

test_that("images beyond gptr.r_max_images are not attached and the result names them (IC-67)", {
  local_nested_dispatch()
  local_gptr_options(r_max_images = 2L)
  td = withr::local_tempdir()
  png1 = jsonlite::base64_dec(paste0(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
    "BAEAX+XDSwAAAABJRU5ErkJggg=="
  ))
  writeBin(png1, file.path(td, "i.png"))
  e = new.env()
  e$f = file.path(td, "i.png")
  res = r_tool_execute(list(code = "for (i in 1:5) ns_resolve(\"read\")(f)"),
                       list(envir = e, session = NULL))
  imgs = Filter(function(b) identical(b$type, "image"), res$content)
  expect_identical(length(imgs), 2L)
  expect_identical(res$details$plots, 2L)
  expect_match(ns_result_text(res), paste0("[3 image(s) from gptr$plot() or gptr$read() not ",
                                           "attached: at most 2 per r call]"), fixed = TRUE)
})

test_that("#> outputs keep at most gptr.doc_output_lines lines of 76 characters per expression", {
  local_gptr_options(doc_output_lines = 2L)
  res = list(outputs = list(c("[1] 2", "", "[1] 3", "[1] 4"), strrep("x", 100)), n_done = 2L)
  expect_identical(r_doc_outputs(res), c("[1] 2", "[1] 3", paste0(strrep("x", 73), "...")))
  expect_identical(r_doc_outputs(list(outputs = list("a"), n_done = 0L)), character())
})

test_that("bridge digests and artifact paths are collected through session hooks and unhooked", {
  added = new.env()
  removed = new.env()
  removed$ids = character()
  fake_add = function(event, handler, matcher = NULL, rank = 3L, source = "user",
                      session = NULL) {
    assign(event, handler, envir = added)
    event
  }
  fake_remove = function(id) {
    removed$ids = c(removed$ids, id)
    invisible(TRUE)
  }
  local_mocked_bindings(hook_add = fake_add, hook_remove = fake_remove)
  rc = r_call_new(NULL)
  ids = r_collect_hooks(rc, "s0123456789")
  expect_identical(ids, c("bridge_call", "artifact_start"))
  added$bridge_call(list(digest = "#> sh git status --porcelain: exit 0, 6 lines"), NULL)
  added$artifact_start(list(id = "marker-explorer", url = "http://127.0.0.1:1"), NULL)
  expect_identical(rc$bridge, "#> sh git status --porcelain: exit 0, 6 lines")
  expect_match(rc$artifacts, "artifacts/marker-explorer/app.R$")
  r_collect_unhook(ids)
  expect_identical(removed$ids, ids)
  expect_identical(r_collect_hooks(rc, NULL), character())
})

test_that("the risk of r comes from the risk.classify service, level 2 before it exists", {
  # P06's call_risk() rates r calls; builtin:r adds no risk function of its own
  scratch = new.env()
  run = list(home = new.env(), scratch = scratch)
  call = list(name = "r", tool = registry_get("tool", "r"), input = list(code = "1 + 1"))
  if (!ext_service_has("risk.classify")) expect_identical(call_risk(call, NULL, run)$level, 2L)
  seen = new.env()
  local_service("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    seen$envir = envir
    list(level = 0L, categories = "read", paths = character(), kind = kind)
  })
  r = call_risk(call, NULL, run)
  expect_identical(r$level, 0L)
  expect_identical(r$kind, "r")
  expect_identical(seen$envir, scratch)
})

# ---- end to end through gptr() on the fake provider (P08, P06, P09; P11 does not exist yet, so the
# permission gate is switched off with the documented escape hatch gptr.unsafe_no_permissions,
# IC-53) ----

# The r tool results of a session, in order
r_results = function(s) {
  Filter(function(m) identical(m$role, "tool_result") && identical(m$tool_name, "r"), s$messages)
}

test_that("model code gptr$grep() runs through the shim; the recorded code keeps it", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_project(files = list("notes.txt" = "a needle here", "other.txt" = "hay"))
  e = new.env(parent = baseenv())
  fake = local_fake_provider(list(fake_tool("r", code = "m = gptr$grep(\"needle\")"), "Found it."))
  s = gptr("Find the needle", model = fake, envir = e, mode = "auto")
  expect_s3_class(e$m, "gptr_matches")
  expect_identical(e$m$file, "notes.txt")
  res = r_results(s)[[1L]]
  expect_identical(res$details$code, "m = gptr$grep(\"needle\")")
  expect_identical(res$details$status, "ok")
  expect_identical(res$details$nested[[1L]]$tool, "grep")
  expect_false(exists("gptr", envir = e, inherits = FALSE))
})

test_that("gptr_return(): 12 MB by name, 200 KB as a copy, an anonymous value boxed", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  e = new.env()
  e$big = stats::runif(1.5e6)
  e$small = stats::runif(25000)
  fake = local_fake_provider(list(
    fake_tool("r", code = "gptr_return(big)"), "Returned big.",
    fake_tool("r", code = "gptr_return(small)"), "Returned small.",
    fake_tool("r", code = "gptr_return(summary(small))"), "Returned a summary."
  ))
  s = gptr("Return big", model = fake, envir = e, mode = "auto")
  s |> gptr("Return small")
  s |> gptr("Return a summary")
  expect_identical(s$values$mode, c("name", "copy", "box"))
  expect_identical(s$values$name[1:2], c("big", "small"))
  expect_identical(vapply(r_results(s)[1:2], function(m) m$details$value, ""), c("big", "small"))
  expect_s3_class(s$value, "summaryDefault")
  expect_identical(withVisible(gptr_return(5)), list(value = 5, visible = FALSE))
})

test_that("a fuzzy edit returns the message and a diff; an exact edit the message only", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  root = local_project(files = list(
    "fuzzy.R" = sprintf("v%03d = %d   ", 1:300, 1:300),
    "exact.R" = "a = 1"
  ))
  fuzzy_edit = list(oldText = "v150 = 150\nv151 = 151", newText = "v150 = 0\nv151 = 0")
  fake = local_fake_provider(list(
    fake_tool("edit", path = "fuzzy.R", edits = list(fuzzy_edit)),
    fake_tool("edit", path = "exact.R", edits = list(list(oldText = "a = 1", newText = "a = 2"))),
    "Edited."
  ))
  s = gptr("Edit both files", model = fake, envir = new.env(), mode = "auto")
  reqs = fake_requests(fake)
  fuzzy = reqs[[2L]]$last_results[[1L]]$content[[1L]]$text
  lines = strsplit(fuzzy, "\n")[[1L]]
  expect_identical(lines[1L], "Successfully replaced 1 block(s) in fuzzy.R.")
  expect_identical(lines[2L], "[matched after whitespace, quote or dash normalisation]")
  expect_true(any(startsWith(lines, "@@")))
  expect_lte(est_tokens(lines[-(1:2)], "code"), 400)
  exact = reqs[[3L]]$last_results[[1L]]$content[[1L]]$text
  expect_identical(exact, "Successfully replaced 1 block(s) in exact.R.")
  expect_identical(readLines(file.path(root, "exact.R"), encoding = "UTF-8"), "a = 2")
})

test_that("the r schema frozen without a bound document has no record or note (IC-68)", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  fake = local_fake_provider(list("Hello."))
  s = gptr("Say hello", model = fake, envir = new.env(), mode = "auto")
  tools_json = session_data(s)$frozen$tools_json
  expect_match(tools_json, "\"name\":\"r\"", fixed = TRUE)
  expect_false(grepl("\"record\"", tools_json, fixed = TRUE))
  expect_false(grepl("\"note\"", tools_json, fixed = TRUE))
  expect_match(tools_json, "Seconds; best effort. Default 3600.", fixed = TRUE)
  expect_true(all(c("read", "r", "edit", "write") %in% fake_requests(fake)[[1L]]$tools))
})

# ---- added by the implementation (P10 Task 11; dev/DEVIATIONS.md D-136) ----

test_that("images from gptr$plot() count against gptr.r_output_tokens too (IC-67)", {
  local_nested_dispatch()
  local_gptr_options(r_output_tokens = 1500L)
  withr::local_pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  graphics::plot(1:3)
  e = new.env()
  out = "cat(sprintf(\"line %03d of the printed output\", 1:70), sep = \"\\n\")"
  plain = r_tool_execute(list(code = out), list(envir = e, session = NULL))
  expect_identical(plain$details$plots, 0L)
  expect_false(plain$truncated)
  code = paste0(out, "\nns_resolve(\"plot\")(width = 800L, height = 600L)")
  res = r_tool_execute(list(code = code), list(envir = e, session = NULL))
  expect_identical(res$details$plots, 1L)
  expect_true(res$truncated)
  expect_match(ns_result_text(res), "gptr$out(", fixed = TRUE)
  expect_identical(res$details$out_id, res$out_id)
})
