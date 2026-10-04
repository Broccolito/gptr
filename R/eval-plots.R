# eval-plots.R -- plot capture during an evaluation and replay to PNG (P09).
#
# Adapted from report 12 section 5.1 (device-following capture; evaluate 1.0.5's visual-change
# and display-list prefix heuristics; replay to PNG) with the IC-67 amendments: when no device
# is open and no human can see one, plots go to pdf(NULL) with the display list enabled (no
# Rplots.pdf in getwd(); no screen device under _R_CHECK_SCREEN_DEVICE_=stop) and the prior
# device is restored; PNGs are 768x512 at res 120 (532 Anthropic tokens, G2 (g)), through ragg
# when installed. While no human can see a device, the `device` option opens pdf(NULL) as well,
# so a default device the code opens after closing one is offscreen too (D-049). Recorded plots
# are held only until they are rendered: events carry PNG paths, never recorded plots (04
# section 5.8).

#' Open a PNG device of `width` x `height` pixels; TRUE when one was opened
#' @noRd
plot_open_png = function(file, width, height, res) {
  if (requireNamespace("ragg", quietly = TRUE)) {
    ragg::agg_png(file, width = width, height = height, units = "px", res = res)
    return(TRUE)
  }
  linux = identical(Sys.info()[["sysname"]], "Linux")
  if (linux && isTRUE(capabilities("cairo"))) {
    grDevices::png(file, width = width, height = height, units = "px", res = res,
                   type = "cairo")
    return(TRUE)
  }
  if (isTRUE(capabilities("png"))) {
    grDevices::png(file, width = width, height = height, units = "px", res = res)
    return(TRUE)
  }
  FALSE
}

#' Replay a recorded plot into a PNG file; the path, or NULL when no PNG device is available
#' @noRd
plot_render = function(recorded, file, width, height, res) {
  prev = grDevices::dev.cur()
  if (!plot_open_png(file, width, height, res)) return(NULL)
  dev = grDevices::dev.cur()
  on.exit({
    if (dev %in% grDevices::dev.list()) grDevices::dev.off(dev)
    if (prev > 1L && prev %in% grDevices::dev.list()) grDevices::dev.set(prev)
  }, add = TRUE)
  suppressWarnings(grDevices::replayPlot(recorded))
  file
}

#' Image block of a PNG file (04 section 4.1; base64 without newlines)
#' @noRd
plot_block = function(file, width, height) {
  bytes = readBin(file, "raw", n = file.size(file))
  block_image(bytes, mime = "image/png", source = "plot", width = as.integer(width),
              height = as.integer(height))
}

#' A new PNG path in the workspace's spill directory (cache/tmp)
#' @noRd
plot_file = function() {
  ws_path("cache", "tmp", paste0("gptr-plot-", id_new("", 12L), ".png"))
}

#' Render a recorded plot to a PNG image block
#'
#' Used by the evaluator and by `gptr$plot()` (P10) and `.opts$images` (P08, IC-44). The PNG is
#' an intermediate: it is removed once the block holds its bytes, and when the replay fails (the
#' error is not caught).
#' @param recorded A `recordedplot` (grDevices::recordPlot()).
#' @param width,height Pixels (defaults `gptr.plot_width`, `gptr.plot_height`).
#' @param res Resolution in pixels per inch (default `gptr.plot_res`).
#' @return An image block (04 section 4.1), or NULL when no PNG device is available.
#' @noRd
plot_png = function(recorded, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"),
                    res = gptr_opt("plot_res")) {
  check_class(recorded, "recordedplot", "recorded")
  width = check_number(width, "width", min = 16, int = TRUE)
  height = check_number(height, "height", min = 16, int = TRUE)
  res = check_number(res, "res", min = 16, int = TRUE)
  file = plot_file()
  on.exit(unlink(file), add = TRUE)
  if (is.null(plot_render(recorded, file, width, height, res))) return(NULL)
  plot_block(file, width, height)
}

#' evaluate's heuristic: does a display list draw something? (report 12 section 5.1)
#' @noRd
plot_visual_change = function(dl) {
  non_visual = c("C_clip", "C_layout", "C_par", "C_plot_window", "C_strHeight", "C_strWidth",
                 "palette", "palette2")
  for (item in dl) {
    x = item[[2L]][[1L]]
    if (utils::hasName(x, "name")) {
      if (!(x$name %in% non_visual)) return(TRUE)
    } else if (is.call(x)) {
      if (!identical(as.character(x[[1L]]), "requireNamespace")) return(TRUE)
    }
  }
  FALSE
}

#' Is display list x a prefix of y? (`x[]` turns a pairlist into a list)
#' @noRd
plot_is_prefix = function(x, y) {
  length(x) <= length(y) && identical(x[], y[seq_along(x)])
}

#' Open an offscreen device: pdf(NULL) at the PNG's aspect ratio, display list enabled
#'
#' Its number joins `ps$our_devs` (closed by plot_close()). A device number R reuses after the
#' code closed a device starts as a new page: nothing captured on the old device is extended.
#' @return The device number.
#' @noRd
plot_open_offscreen = function(ps) {
  grDevices::pdf(file = NULL, width = ps$inches[[1L]], height = ps$inches[[2L]])
  grDevices::dev.control(displaylist = "enable")
  d = grDevices::dev.cur()
  key = as.character(d)
  ps$last_dl[[key]] = NULL
  ps$last_k[[key]] = NULL
  ps$our_devs = unique(c(ps$our_devs, d))
  d
}

#' The `device` option while no human can see a device (or in "capture" mode)
#'
#' R opens the `device` option when code draws with no device open (`plot()`, `par()`, grid)
#' or calls `dev.new()`. After the code closed the offscreen or the user's device, that is
#' another offscreen device instead of R's default (Rplots.pdf in getwd() under Rscript), so
#' the IC-67 rule holds for the whole evaluation and later plots are still recorded. The
#' closure holds only the plot state.
#' @noRd
plot_device_option = function(ps) {
  force(ps)
  function(...) invisible(plot_open_offscreen(ps))
}

#' Start plot capture for an evaluation; returns the plot state environment
#'
#' `mode`: "auto" draws on the user's device when one is open or a human is present, else on
#' pdf(NULL); "capture" always draws on pdf(NULL); "none" records nothing (pdf(NULL) is still
#' opened when no device is open and no human is present, so no Rplots.pdf is written). In
#' "capture" mode, and in every mode when no human is present, the `device` option opens
#' pdf(NULL) too until plot_close() restores it (plot_device_option()).
#' @noRd
plot_begin = function(mode, human, width = gptr_opt("plot_width"),
                      height = gptr_opt("plot_height"), res = gptr_opt("plot_res")) {
  ps = new.env(parent = emptyenv())
  ps$record = !identical(mode, "none")
  ps$dev_start = grDevices::dev.cur()
  ps$devs0 = grDevices::dev.list()
  ps$inches = c(width, height) / res
  ps$our_dev = NULL
  ps$our_devs = integer()
  ps$old_device = NULL
  ps$last_dl = list()
  ps$last_k = list()
  ps$recorded = list()
  ps$n = 0L
  ps$closed = FALSE
  offscreen = identical(mode, "capture") || (ps$dev_start == 1L && !isTRUE(human))
  if (offscreen) {
    ps$our_dev = plot_open_offscreen(ps)
  } else if (ps$dev_start > 1L && ps$record) {
    try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
    base = tryCatch(grDevices::recordPlot(), error = function(e) NULL)
    if (!is.null(base)) ps$last_dl[[as.character(ps$dev_start)]] = base[[1L]]
  }
  # Set last, so a failure above never leaves the option changed without a state to restore it
  if (offscreen || !isTRUE(human)) {
    ps$old_device = options(device = plot_device_option(ps))
  }
  ps
}

#' Enable the display list on a device the evaluated code opened itself
#' @noRd
plot_enable_new = function(ps) {
  d = grDevices::dev.cur()
  fresh = d > 1L && !(d %in% c(ps$devs0, ps$our_devs)) && is.null(ps$last_dl[[as.character(d)]])
  if (fresh) try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
  invisible()
}

#' Record the current page when it is complete and new; TRUE when a new plot was captured
#'
#' Low-level additions to a page this evaluation already captured (`abline()`, `lines()`,
#' `points()` in later top-level expressions) replace that plot's recording instead of adding
#' one, as knitr's `fig.keep = "high"` does: the model sees the finished page once, not each
#' intermediate state (each image costs 532 tokens and at most `max_images` are attached).
#' In "capture" mode the user's devices open at plot_begin() are skipped, but not an offscreen
#' device of `ps$our_devs` that R opened at the number of one the code closed (D-049).
#' @noRd
plot_capture = function(ps, incomplete = FALSE) {
  if (!ps$record) return(FALSE)
  d = grDevices::dev.cur()
  if (d == 1L) return(FALSE)
  if (!is.null(ps$our_dev) && !(d %in% ps$our_devs) && d %in% ps$devs0) return(FALSE)
  if (!incomplete && !isTRUE(graphics::par("page"))) return(FALSE)
  p = tryCatch(grDevices::recordPlot(), error = function(e) NULL)
  if (is.null(p) || !length(p[[1L]]) || !plot_visual_change(p[[1L]])) return(FALSE)
  key = as.character(d)
  old = ps$last_dl[[key]]
  same_page = !is.null(old) && plot_is_prefix(old, p[[1L]])
  if (same_page && !plot_visual_change(p[[1L]][-seq_along(old)])) return(FALSE)
  ps$last_dl[[key]] = p[[1L]]
  k = ps$last_k[[key]]
  if (same_page && !is.null(k)) {
    ps$recorded[[k]] = p
    return(FALSE)
  }
  ps$n = ps$n + 1L
  ps$recorded[[ps$n]] = p
  ps$last_k[[key]] = ps$n
  TRUE
}

#' Close the private devices, restore the `device` option and the prior device; idempotent
#'
#' Capture ends here, so the last display lists are dropped too (the recordings stay until
#' plot_render_all()).
#' @noRd
plot_close = function(ps) {
  if (is.null(ps) || isTRUE(ps$closed)) return(invisible())
  ps$closed = TRUE
  if (!is.null(ps$old_device)) options(ps$old_device)
  for (d in ps$our_devs) {
    if (d %in% grDevices::dev.list()) grDevices::dev.off(d)
  }
  if (ps$dev_start > 1L && ps$dev_start %in% grDevices::dev.list()) {
    grDevices::dev.set(ps$dev_start)
  }
  ps$last_dl = list()
  invisible()
}

#' Render the captured plots (at most `max_render`) to PNG files and drop the recordings
#'
#' A PNG whose replay failed is removed.
#' @return Character vector of PNG paths (NA where rendering failed), one per captured plot up
#'   to `max_render`.
#' @noRd
plot_render_all = function(ps, max_render = 50L, width = gptr_opt("plot_width"),
                           height = gptr_opt("plot_height"), res = gptr_opt("plot_res")) {
  n = min(ps$n, max_render)
  files = rep(NA_character_, n)
  for (k in seq_len(n)) {
    file = plot_file()
    f = tryCatch(plot_render(ps$recorded[[k]], file, width, height, res),
                 error = function(e) NULL)
    if (is.null(f)) unlink(file) else files[k] = f
  }
  ps$recorded = list()
  files
}
