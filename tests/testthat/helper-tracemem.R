# The copy-safety harness (contract section 12.2, IC-41, IC-60; report 12 section 5.4, G3 t5).
# Each call writes a script and runs it in a fresh `Rscript --vanilla`: load gptr, run `setup`
# (which creates `object`), start tracemem(object), run `action` (the gptr code under test), then
# `edit` (the user's next in-place edit). A `tracemem[` line printed after the action means the
# edit copied the object: something still holds a reference to it.

# How the child loads gptr: the installed package when the tested namespace is installed (R CMD
# check), else the source tree the tests run from (devtools::test()). pkgload::load_all() appears
# only inside the generated script text (IC-71).
tracemem_loader = function() {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (file.exists(file.path(path, "R", "aaa-state.R"))) {
    sprintf(
      "pkgload::load_all(%s, quiet = TRUE, export_all = FALSE, helpers = FALSE)",
      deparse(normalizePath(path, winslash = "/"))
    )
  } else {
    sprintf("library(gptr, lib.loc = %s)",
            deparse(normalizePath(dirname(path), winslash = "/")))
  }
}

# The script run by expect_no_copy(); exposed for its own tests
tracemem_script = function(setup, action, edit, object, in_run_edit) {
  fake = if (in_run_edit) {
    sprintf(
      "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = %s)), 'done.'))",
      deparse(edit)
    )
  }
  c(
    tracemem_loader(),
    setup,
    fake,
    sprintf("invisible(tracemem(%s))", object),
    "cat('GPTR-ACTION-START\\n')",
    action,
    "cat('GPTR-ACTION-END\\n')",
    edit,
    "cat('GPTR-END\\n')"
  )
}

# Count copies of `object`: after the action (the next edit), plus during it with in_run_edit
expect_no_copy = function(setup, action, edit = "big[1] = 0", object = "big", allow = 0L,
                          label = NULL, in_run_edit = FALSE) {
  testthat::skip_on_cran()
  testthat::skip_if_not(capabilities("profmem"), "R was built without memory profiling")
  script = withr::local_tempfile(fileext = ".R")
  writeLines(tracemem_script(setup, action, edit, object, in_run_edit), script)
  env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  res = processx::run(
    rscript_path(), c("--vanilla", script),
    env = env, error_on_status = FALSE, timeout = 300
  )
  out = strsplit(res$stdout, "\n", fixed = TRUE)[[1L]]
  label = label %||% action
  if (res$status != 0L || !("GPTR-END" %in% out)) {
    testthat::fail(paste0(
      "expect_no_copy(", label, "): the script did not finish (status ", res$status, ")\n",
      paste(utils::tail(strsplit(res$stderr, "\n", fixed = TRUE)[[1L]], 5L), collapse = "\n")
    ))
    return(invisible(NA_integer_))
  }
  from = match(if (in_run_edit) "GPTR-ACTION-START" else "GPTR-ACTION-END", out)
  copies = sum(startsWith(out[seq(from, length(out))], "tracemem["))
  testthat::expect(
    copies <= allow,
    sprintf("%s: %d copies of `%s` (allowed %d)", label, copies, object, allow)
  )
  invisible(copies)
}
