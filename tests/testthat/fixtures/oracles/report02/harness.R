# Shared test harness of P06 (session kernel and agent loop). The first line of every P06 test
# file sources this file with local = TRUE, locating it through testthat::test_path().
# It lives in P06's own fixture directory (P06 owns no helper-*.R file) and holds the loader of
# report 02's oracle checks plus small helpers built only on P01's test helpers (contract 04
# section 12.2) and the P02 registry API.

#' The report 02 oracle checks of one group ("loop", "store", "recovery"), keyed by id
oracle = function(group) {
  path = testthat::test_path("fixtures", "oracles", "report02", paste0(group, ".json"))
  recs = json_decode(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"))
  stats::setNames(recs, vapply(recs, function(r) r$id, ""))
}

#' The title of the test of one oracle check: "<id> <gptr assertion>"
oracle_title = function(recs, id) paste(id, recs[[id]]$gptr)

#' Every oracle id of `recs` has a test_that() titled with oracle_title() in `file`
expect_oracles_covered = function(recs, file) {
  src = paste(readLines(testthat::test_path(file), encoding = "UTF-8", warn = FALSE),
              collapse = "\n")
  hits = regmatches(src, gregexpr("oracle_title\\([a-z_]+, \"[A-Z][0-9]{2}\"\\)", src))[[1L]]
  ids = sub("^.*\"([A-Z][0-9]{2})\"\\)$", "\\1", hits)
  testthat::expect_setequal(unique(ids), names(recs))
}

#' A temporary project with a .gptr/ workspace that project_root() resolves to
local_store = function(.env = parent.frame()) {
  dir = local_project(.env = .env)
  withr::local_envvar(GPTR_PROJECT_ROOT = dir, .local_envir = .env)
  withr::local_options(gptr.project_root = dir, .local_envir = .env)
  dir
}

#' Register a test tool (rank 3) for the calling test
local_tool = function(name, execute, parameters = list(type = "object", properties = json_obj()),
                      execution = "sequential", annotations = list(), risk = NULL,
                      .env = parent.frame()) {
  spec = gptr_tool(name, paste("Test tool", name), parameters = parameters, execute = execute,
                   execution = execution, annotations = annotations, risk = risk)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

#' Register a test policy (rank 3) for the calling test
local_policy = function(name, check, .env = parent.frame()) {
  off = gptr_register(gptr_policy(name, check))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

#' Provide or replace a service through the registry's `service` kind (IC-34)
local_service = function(name, fun, .env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), source = "user", rank = 3L)
  withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

#' Hide bootstrap services of later plans for the calling test (the fallbacks of 04 section 7.0)
#'
#' P07, P11, ... register their services in P01's bootstrap table from on_load(), so in the full
#' suite `ext_service_has()` is TRUE for them; a test of a P06 fallback hides them first. Records
#' added with local_service() live in the registry and are not affected.
local_without_services = function(names, .env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = .env)
  svc = old
  for (nm in names) svc[[nm]] = NULL
  assign("services", svc, envir = the)
  invisible(NULL)
}

#' A process-wide hook, or a session listener when `session` (an id) is given
local_hook = function(event, handler, session = NULL, .env = parent.frame()) {
  id = hook_add(event, handler, rank = if (is.null(session)) 3L else 0L,
                source = if (is.null(session)) "user" else "session", session = session)
  withr::defer(hook_remove(id), envir = .env)
  invisible(id)
}

#' Allow every tool call in the calling test (the IC-53 escape hatch, set outside the run)
local_permissive = function(.env = parent.frame()) {
  local_gptr_options(unsafe_no_permissions = TRUE, .env = .env)
}

# local_events(), test_session(), test_run(), run_text() are restored from the Task 1
# plan by their first dependent P06 tasks, once actual session/run functions exist.
roles = function(s) vapply(s$messages, function(m) m$role, "")
tool_results = function(s) Filter(function(m) identical(m$role, "tool_result"), s$messages)
req_roles = function(req) vapply(req$messages, function(m) m$role, "")
num_schema = function(...) {
  props = lapply(list(...), function(type) list(type = type))
  list(type = "object", required = I(names(props)), properties = props)
}
