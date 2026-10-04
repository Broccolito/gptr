# ext-registry.R -- the registry keyed by (kind, name) with ranks, filters, diagnostics and a
# generation counter (contract 5.5, 7.2, 10.1; architecture 5.10, 11.1). Adapted from the verified
# G1 prototype (report G1 5.1) with its verification-log fixes: every regex on a registration or
# dispatch path uses perl = TRUE (row 9), overrides are per record (IC-69), filters are applied at
# resolution time (G1 pitfall 8), and no binding is ever locked (IC-26, rule R5).

#' A fresh registry environment holding all P02 state (contract 5.13 `gptr_registry_env`)
#'
#' `recs` maps record ids to records (contract 5.5); `by_kind`, `by_key` and `hooks` index them;
#' `exts` holds one environment per loaded extension and `states` the `gptr$state` environments;
#' `runs` and `executing` mirror the active runs and executing tools seen through ev_dispatch();
#' `grants` holds one-shot approvals of control exports (IC-53); `builtins_loaded` names the
#' built-ins already loaded into this registry and `watched` the packages whose unload is watched;
#' `version` counts changes that can alter gptr_registry() and `listing` caches its full listing.
#' @noRd
registry_new = function() {
  reg = new.env(parent = emptyenv())
  reg$recs = new.env(parent = emptyenv())
  reg$by_kind = new.env(parent = emptyenv())
  reg$by_key = new.env(parent = emptyenv())
  reg$hooks = new.env(parent = emptyenv())
  reg$exts = new.env(parent = emptyenv())
  reg$states = new.env(parent = emptyenv())
  reg$diag = new.env(parent = emptyenv())
  reg$diag$rows = list()
  reg$kinds = kinds_new()
  reg$filters = list(user = character(), project = character(), session = character())
  reg$eff = character()
  reg$runs = character()
  reg$executing = character()
  reg$grants = list()
  reg$builtins_loaded = character()
  reg$watched = character()
  reg$generation = 1L
  reg$seq = 0L
  reg$ext_seq = 0L
  reg$version = 0L
  reg$listing = NULL
  reg$listing_key = NULL
  reg$current_ext = NULL
  reg$ctx0 = NULL
  class(reg) = "gptr_registry_env"
  reg
}

#' Note a change that can alter gptr_registry() (records, filters, kinds); the cached listing
#' is rebuilt on its next call
#' @noRd
registry_touch = function(reg = registry_env()) {
  reg$version = reg$version + 1L
  invisible(NULL)
}

#' Make `reg` the process registry and point the P02 fields of `the` at it (contract 7.0)
#' @noRd
registry_bind = function(reg) {
  the$registry = reg
  the$kinds = reg$kinds
  the$hooks = reg$hooks
  the$diagnostics = reg$diag
  invisible(reg)
}

#' The process registry, created on first use
#' @noRd
registry_env = function() {
  reg = the$registry
  if (is.null(reg)) {
    reg = registry_new()
    registry_bind(reg)
  }
  reg
}

#' A scratch registry holding only the built-in kinds (gptr_check() and tests)
#' @noRd
registry_scratch = function() registry_new()

#' Swap the process registry; returns the previous one invisibly
#' @noRd
registry_swap = function(reg) {
  old = registry_env()
  registry_bind(reg)
  invisible(old)
}

#' The session id of a session object (anything with an `id` string), an id string, or NULL
#' @noRd
ext_session_id = function(session) {
  if (is.null(session)) return(NULL)
  if (is.character(session) && length(session) == 1L && !is.na(session)) return(session)
  if (!is.environment(session) && !is.list(session)) return(NULL)
  id = tryCatch(session$id, error = function(e) NULL)
  if (is.character(id) && length(id) == 1L && !is.na(id)) id else NULL
}
