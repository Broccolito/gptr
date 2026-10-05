# doc-knitr.R -- knitr integration (plan P15; contract 5.1, 5.2, IC-07; report 14 section 4.6):
# the knit_print methods for sessions and System 1 vectors, registered lazily for the Suggests
# generic knitr::knit_print with P01's s3_register(), and the scoped label hook that skips the
# stale agent chunk of a block regenerated during the knit (report 14 section 2.1.3: an
# opts_hooks label hook disables a later chunk; it persists after knit() unless a knit_hooks
# document hook removes it). What they print is redacted with the persist profile, as the
# recorded blocks are (IC-74). Layer L5.

#' knit_print method for sessions: the answer as Markdown; for a turn that ran live in this
#' process also the code it ran, so the first render is complete before the new agent chunk
#' exists (its chunk runs from the next render on), fenced as the agent chunk is (a backtick line
#' in the code never ends the fence). Redacted like the agent block (IC-74)
#' @noRd
knit_print.gptr_session = function(x, ...) {
  txt = x$text %||% NA_character_
  out = if (length(txt) && !all(is.na(txt))) paste(txt[!is.na(txt)], collapse = "\n\n") else ""
  code = doc_knit_code(x)
  if (length(code)) {
    fence = doc_rmd_fence("```", unlist(strsplit(code, "\n", fixed = TRUE)))
    out = c(out, "", paste0(fence, "r"), code, fence)
  }
  knitr::asis_output(redact(paste(out, collapse = "\n"), "persist"))
}

#' knit_print method for System 1 vectors: the one-line summary of their document block,
#' redacted as doc.s1_block redacts that block (free-text choice levels reach it; IC-74)
#' @noRd
knit_print.gptr_s1 = function(x, ...) {
  knitr::asis_output(paste0("`", redact(doc_s1_summary(x), "persist"), "`\n"))
}

#' Recorded code of a session's last turn when it ran live (replayed sessions, teams and
#' fan-outs show none: their code is in the agent chunk)
#' @noRd
doc_knit_code = function(s) {
  d = session_data(s)
  if (isTRUE(d$replayed) || d$kind %in% c("team", "fanout", "replayed")) return(character())
  n = as.integer(d$turns %||% 0L)
  if (!n) return(character())
  tb = doc_turn_body(doc_turn_entries(s, n), with_out = FALSE)
  tb$body[!grepl("^#", tb$body)]
}

#' Skip the chunk with this label for the rest of the knit: a label hook (chaining any existing
#' one) sets eval = FALSE for skipped labels; the document hook of the knit restores the hooks it
#' replaced, and so does an after.knit hook, which knitr runs on exit also when the knit fails
#' (the document hook is then never reached, and knit() may have reset the document hook to its
#' default already). Both hooks run in every knit() of the session, so they end the skip only in
#' the knit that set it (or one around it): a child knit, or a knit or render run from a chunk,
#' sits deeper on the call stack and never ends the skip of the knit that runs it
#' @noRd
doc_knitr_skip = function(label) {
  if (!requireNamespace("knitr", quietly = TRUE)) return(invisible(FALSE))
  st = doc_state()
  st$knitr_skip = union(st$knitr_skip, label)
  if (isTRUE(st$knitr_hooked)) return(invisible(TRUE))
  old = list(label = knitr::opts_hooks$get("label"), document = knitr::knit_hooks$get("document"),
             after = knitr::knit_hooks$get("after.knit"))
  mine = list()
  depth = max(doc_knit_depth(), 1L)
  ours = function() doc_knit_depth() <= depth
  mine$label = function(options) {
    if (is.function(old$label)) options = old$label(options)
    if (isTRUE(options$label %in% doc_state()$knitr_skip)) options$eval = FALSE
    options
  }
  mine$document = function(x) {
    if (ours()) doc_knitr_unhook(old, mine)
    if (is.function(old$document)) old$document(x) else x
  }
  mine$after = function(...) {
    if (ours()) doc_knitr_unhook(old, mine)
    if (is.function(old$after)) old$after(...)
  }
  knitr::opts_hooks$set(label = mine$label)
  knitr::knit_hooks$set(document = mine$document, after.knit = mine$after)
  st$knitr_hooked = TRUE
  invisible(TRUE)
}

#' Number of knitr::knit() calls on the call stack: 1 in a top-level knit, one more in a child
#' knit (knit_child() runs knit()) and in a knit or render run from a chunk; 0 outside a knit
#' @noRd
doc_knit_depth = function() {
  knit = knitr::knit
  n = sys.nframe() - 1L
  if (n < 1L) return(0L)
  sum(vapply(seq_len(n), function(k) identical(sys.function(k), knit), NA))
}

#' Restore the label, document and after.knit hooks that doc_knitr_skip() replaced (`old`), each
#' only while it is still the hook doc_knitr_skip() set (`mine`), and end the skip. Calling it again
#' is harmless; it does not depend on the skip state, so hooks that code around a nested knit
#' saved and restored (rmarkdown::render() does) are still removed
#' @noRd
doc_knitr_unhook = function(old, mine) {
  restore = function(hooks, key, now, before) {
    if (!identical(hooks$get(key), now)) return(invisible(NULL))
    if (is.function(before)) hooks$set(stats::setNames(list(before), key)) else hooks$delete(key)
  }
  restore(knitr::opts_hooks, "label", mine$label, old$label)
  restore(knitr::knit_hooks, "document", mine$document, old$document)
  restore(knitr::knit_hooks, "after.knit", mine$after, old$after)
  st = doc_state()
  st$knitr_skip = character()
  st$knitr_hooked = FALSE
  invisible(NULL)
}

on_load(s3_register("knitr::knit_print", "gptr_session"))
on_load(s3_register("knitr::knit_print", "gptr_s1"))
