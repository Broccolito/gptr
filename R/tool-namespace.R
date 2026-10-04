# tool-namespace.R -- the `gptr$` namespace (P10): member printing within token budgets, the r-call
# marker that tells a member it runs inside model code, member closures generated from tool specs,
# member resolution (the `ns.resolve`, `ns.names` and `search.sources` services behind P08's gateway
# methods, IC-36), `gptr_ns` nodes for plugin and MCP namespaces, the plugin catalog, BM25 search,
# `gptr$help()`, `gptr$search()`, `gptr$describe()`, `gptr$plot()`, `gptr$out()`, the specs of
# `read`, `edit`, `write`, `grep`, `find`, `ls` (one per capability, direct and member forms,
# IC-37), their `<rules>` guidelines, the `<r_session>` fragments and `builtin:tools` (IC-68).
# Sources: dev/research/G5-polyglot-glue-helpers.md (gateway-as-namespace pattern verified by the
# `gwtoy` R CMD check; 1,500-token prints and 0.6 x the r budget inside r),
# dev/research/G1-extensibility-sdk-surface.md sections 2.5 and 2.8 (one signature line per member;
# closures built by replacing formals(), never by replacing the environment),
# dev/research/06-pi-subagents-mcp-codemode.md section 5.7 (BM25 port, parity with Pi),
# dev/research/20-harness-feature-survey.md section 5.2 (help text through tools::Rd2txt, no `:::`).

#' Class of the marker that the `r` tool binds (as `gptr_r_call`) in its own frame while it
#' evaluates
#' @noRd
r_call_class = "gptr_r_call"

#' A new r-call marker: the session ctx plus collectors for images, bridge digests and artifact
#' paths
#'
#' The `r` tool binds it as the local variable `gptr_r_call` of its execute frame, so it exists
#' exactly for the dynamic extent of one evaluation and no package-level run state is kept
#' (INFRA-15). It holds no user object and no user frame.
#' @noRd
r_call_new = function(ctx) {
  rc = new.env(parent = emptyenv())
  rc$ctx = ctx
  rc$images = list()
  rc$dropped = 0L
  rc$printed = 0
  rc$bridge = character()
  rc$artifacts = character()
  class(rc) = r_call_class
  rc
}

#' The innermost r-call marker on the call stack, or NULL outside an `r` evaluation
#'
#' Walks the frames from the innermost outwards with sys.frame(k) (never sys.frames(), rule R3) and
#' looks only for the binding `gptr_r_call` of class `gptr_r_call`; no promise is forced: a lazy
#' or active binding of that name (a user formal, say) is skipped, since the `r` tool binds the
#' marker as an ordinary local value.
#' @noRd
ns_r_call = function() {
  k = sys.nframe() - 1L
  while (k > 0L) {
    fr = sys.frame(k)
    if (exists("gptr_r_call", envir = fr, inherits = FALSE) &&
          !rlang::env_binding_are_lazy(fr, "gptr_r_call") &&
          !rlang::env_binding_are_active(fr, "gptr_r_call")) {
      rc = get("gptr_r_call", envir = fr, inherits = FALSE)
      if (inherits(rc, r_call_class)) return(rc)
    }
    k = k - 1L
  }
  NULL
}

#' Attach an image block to the result of the innermost running `r` call; FALSE when there is none
#' or when gptr.r_max_images images are attached already (the refused ones are counted in
#' `dropped`, which the r tool names in a notice; IC-67)
#' @noRd
r_call_attach_image = function(block) {
  rc = ns_r_call()
  if (is.null(rc)) return(invisible(FALSE))
  if (length(rc$images) >= as.integer(gptr_opt("r_max_images"))) {
    rc$dropped = rc$dropped + 1L
    return(invisible(FALSE))
  }
  rc$images = c(rc$images, list(block))
  invisible(TRUE)
}

#' Print budget of a member result: gptr.helper_output_tokens, and inside r at most 0.6 x the r
#' budget that the member prints of this evaluation have left (04 section 9.4; G5)
#' @noRd
member_budget = function() {
  b = as.numeric(gptr_opt("helper_output_tokens"))
  rc = ns_r_call()
  if (!is.null(rc)) {
    left = max(0, as.numeric(gptr_opt("r_output_tokens")) - rc$printed)
    b = min(b, floor(0.6 * left))
  }
  b
}

#' The largest number of leading lines within a token budget (binary search over est_tokens())
#' @noRd
lines_fit = function(lines, budget, class = "r_output") {
  lo = 0L
  hi = length(lines)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (est_tokens(lines[seq_len(mid)], class) <= budget) lo = mid else hi = mid - 1L
  }
  lo
}

#' Leading lines within a budget and the number of lines left out
#' @noRd
budget_head = function(lines, budget, class = "r_output") {
  if (!length(lines) || est_tokens(lines, class) <= budget) {
    return(list(lines = lines, omitted = 0L))
  }
  k = lines_fit(lines, budget, class)
  list(lines = lines[seq_len(k)], omitted = length(lines) - k)
}

#' Head (40% of the budget) and tail (60%) of lines and the number left out
#' @noRd
budget_head_tail = function(lines, budget, class = "r_output") {
  n = length(lines)
  if (!n || est_tokens(lines, class) <= budget) {
    return(list(head = lines, tail = character(), omitted = 0L))
  }
  h = lines_fit(lines, 0.4 * budget, class)
  t = min(lines_fit(rev(lines), 0.6 * budget, class), n - h)
  list(head = lines[seq_len(h)], tail = if (t > 0L) lines[(n - t + 1L):n] else character(),
       omitted = n - h - t)
}

#' Write lines of a member result to standard output as UTF-8 bytes (the evaluator's sink captures
#' them); inside an `r` call their estimated tokens are added to the marker's `printed` count
#'
#' Plain writeLines(): the text is data, never a format string (rule C1), and cli output would go to
#' stderr in non-interactive sessions, where the evaluator's sink does not see it.
#' @noRd
ns_print_lines = function(lines) {
  lines = as_utf8(as.character(lines))
  rc = ns_r_call()
  if (!is.null(rc)) rc$printed = rc$printed + est_tokens(lines, "r_output")
  writeLines(lines, useBytes = TRUE)
  invisible(NULL)
}

#' A character result (`gptr$help()`, `gptr$out()`) that prints within the member budget
#' @noRd
new_gptr_text = function(x) structure(as_utf8(as.character(x)), class = c("gptr_text", "character"))

#' Print a gptr text result: head and tail within the member budget
#'
#' @param x A `gptr_text` character vector.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_text = function(x, ...) {
  s = budget_head_tail(as.character(x), member_budget())
  mid = if (s$omitted > 0L) {
    paste0("[... ", s$omitted, " lines not printed; index the value, e.g. x[a:b]]")
  }
  ns_print_lines(c(s$head, mid, s$tail))
  invisible(x)
}
