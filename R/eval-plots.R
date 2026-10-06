# Plot capture during an evaluation and replay to PNG (P09; report 12 section 5.1, IC-67, D-049).
# With no device open and no human to see one, plots and the `device` option go to pdf(NULL) (no
# Rplots.pdf); the prior device is restored. PNGs are 768x512 at res 120 (532 Anthropic tokens);
# events carry PNG paths, never recorded plots (04 section 5.8).

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

#' Render a recorded plot to a PNG image block (04 section 4.1), or NULL without a PNG device
#' Also used by `peter$plot()` (P10) and `.opts$images` (P08, IC-44); the PNG is always removed and
#' a replay error is not caught (D-049).
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
#' Returns its number, which joins `ps$our_devs`; a number R reuses starts a new page (D-049).
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
#' A device R opens after the code closed one is offscreen too, not Rplots.pdf, so IC-67 holds for
#' the whole evaluation (D-049); the closure holds only the plot state.
#' @noRd
plot_device_option = function(ps) {
  force(ps)
  function(...) invisible(plot_open_offscreen(ps))
}

#' Start plot capture for an evaluation; returns the plot state environment
#' `mode` "auto": the user's device when one is open or a human is present, else pdf(NULL);
#' "capture": pdf(NULL); "none": nothing recorded (pdf(NULL) still keeps Rplots.pdf away).
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
#' Additions to a captured page replace its recording (knitr's `fig.keep = "high"`); "capture"
#' mode skips the user's devices, not an offscreen one R opened at a reused number (D-049).
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
#' Capture ends here: the display lists go, the recordings stay until plot_render_all().
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
#' One path per plot; NA, with the file removed, where the replay failed.
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
