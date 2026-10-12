# Fixed private entry: no gptr namespace load and no credentials or source mutation.
local({
  argv = commandArgs(TRUE)
  stopifnot(length(argv) == 1L)
  request = jsonlite::read_json(argv[[1L]], simplifyVector = TRUE)
  stopifnot(request$mode %in% c("depends", "suggests", "revdeps"))
  output = normalizePath(request$output, mustWork = TRUE)
  archive = normalizePath(request$archive, mustWork = TRUE)
  options(Ncpus = 1L, timeout = 60)
  conditions = new.env(parent = emptyenv())
  conditions$warnings = 0L
  write_result = function(value) {
    part = file.path(output, "result.json.part")
    stopifnot(!file.exists(part))
    jsonlite::write_json(value, part, auto_unbox = TRUE, pretty = TRUE, null = "null")
    stopifnot(file.rename(part, file.path(output, "result.json")))
  }
  profile_finish = function(outcome, original, conditions, write_result) {
    withCallingHandlers({
      outcome$warnings = conditions$warnings
      outcome$passed = isTRUE(outcome$passed) && conditions$warnings == 0L
      publish = function(value) {
        tryCatch({
          write_result(value)
          NULL
        }, error = function(error) error, interrupt = function(error) error)
      }
      publication = publish(outcome)
      if (inherits(publication, "condition") && is.null(original)) {
        original = publication
      }
      if (conditions$warnings != outcome$warnings) {
        outcome$warnings = conditions$warnings
        outcome$passed = FALSE
        publication = publish(outcome)
        if (inherits(publication, "condition") && is.null(original)) {
          original = publication
        }
      }
      if (!is.null(original)) {
        stop(original)
      }
      stopifnot(isTRUE(outcome$passed), conditions$warnings == 0L)
    }, warning = function(warning) conditions$warnings = conditions$warnings + 1L)
  }
  conditions$original = NULL
  outcome = withCallingHandlers(tryCatch({
    stopifnot(is.na(Sys.getenv("NOT_CRAN", unset = NA_character_)),
      identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
    if (request$mode == "revdeps") {
      repository = "https://cloud.r-project.org"
      db = utils::available.packages(repos = c(CRAN = repository), filters = character())
      stopifnot("gptr" %in% rownames(db))
      direct = tools::package_dependencies("gptr", db = db, reverse = TRUE,
        which = "all")[["gptr"]]
      recursive = tools::package_dependencies("gptr", db = db, reverse = TRUE,
        which = "most", recursive = "strong")[["gptr"]]
      stopifnot(!is.null(direct), !is.null(recursive))
      saveRDS(list(day = Sys.Date(), repository = repository, db = db,
        direct = sort(direct), recursive = sort(recursive)), file.path(output, "revdeps.rds"))
      list(passed = TRUE, target_present = TRUE, day = as.character(Sys.Date()),
        repository = repository, direct = as.list(sort(direct)),
        recursive = as.list(sort(recursive)), r_version = R.version.string)
    } else {
      expected = unlist(request$flags, use.names = TRUE)
      stopifnot(identical(unname(Sys.getenv(names(expected))), unname(expected)))
      result = rcmdcheck::rcmdcheck(path = archive, args = "--as-cran", timeout = 7200,
        check_dir = file.path(output, "check"), error_on = "never",
        env = c(expected, NOT_CRAN = NA_character_))
      logs = list.files(file.path(output, "check"), "^00check[.]log$", recursive = TRUE,
        full.names = TRUE)
      status = if (length(logs) == 1L) {
        grep("^Status:", readLines(logs, warn = FALSE), value = TRUE)
      } else {
        character()
      }
      values = c(errors = length(result$errors), warnings = length(result$warnings),
        notes = length(result$notes))
      writeLines(c(status, paste(names(values), values)), file.path(output, "check-summary.txt"))
      list(passed = length(logs) == 1L && identical(status, "Status: OK") &&
        all(values == 0L) && !isTRUE(result$timeout), status = as.list(status),
        errors = values[["errors"]], check_warnings = values[["warnings"]],
        notes = values[["notes"]], timed_out = isTRUE(result$timeout),
        r_version = R.version.string, manual_incoming_enabled = TRUE,
        not_cran_unset = TRUE, flags = request$flags, check_seconds = as.numeric(result$duration),
        tooling_library_paths = as.list(.libPaths()))
    }
  }, error = function(error) {
    conditions$original = error
    list(passed = FALSE, error_class = class(error)[[1L]])
  }, interrupt = function(error) {
    conditions$original = error
    list(passed = FALSE, error_class = class(error)[[1L]])
  }), warning = function(warning) conditions$warnings = conditions$warnings + 1L)
  profile_finish(outcome, conditions$original, conditions, write_result)
})
