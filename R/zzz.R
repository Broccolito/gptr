# Load and unload hooks. No disk, network or process activity at load (13 C-29).

#' Run the on_load() queue and load the built-ins (load errors are kept, never raised)
#' @noRd
.onLoad = function(libname, pkgname) {
  on_load_run()
  load_builtins = ns_fun("ext_load_builtins")
  if (!is.null(load_builtins)) {
    err = tryCatch({
      load_builtins()
      NULL
    }, error = function(e) e)
    if (!is.null(err)) {
      the$load_errors[[length(the$load_errors) + 1L]] =
        list(expr = quote(ext_load_builtins()), error = err)
    }
  }
  invisible(NULL)
}

#' Run the on_unload() queue
#' @noRd
.onUnload = function(libpath) {
  on_unload_run()
  invisible(NULL)
}

#' Imports used by later layers
#'
#' P01 writes the final Imports once (conventions section 8). Referencing each Imports package
#' here keeps `R CMD check` from reporting declared-but-unused Imports before the plans that use
#' them exist (curl, processx and ps in P04, callr in P19, yaml in P17, the graphics packages in
#' P09, methods in P16). The function is never called.
#' @noRd
imports_used = function() {
  list(
    callr::r_bg, cli::cli_verbatim, curl::new_handle, graphics::par, grDevices::dev.cur,
    jsonlite::toJSON, methods::slotNames, processx::poll, ps::ps_handle, rlang::hash,
    stats::setNames, tools::R_user_dir, utils::head, yaml::yaml.load
  )
}
