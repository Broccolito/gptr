# Polyglot bridges, shell side (P22; contract 7.22, 9.4, 10.2 row 6; architecture 4.2, 6.7):
# command resolution and budgeted head+tail views, after the verified G5 prototype.

#' Split a simple command line into words, or NULL when it needs a shell
#' Words split on space and tab (as sh); quotes group them. A metacharacter or backslash outside
#' quotes, `$`/backquote/backslash in double quotes, a leading `~`/`#`, a `NAME=` prefix or an
#' unclosed quote needs the shell.
#' @noRd
bridge_split = function(cmd) {
  quoted = "'[^']*'|\"[^\"$`\\\\]*\""
  shell = "^\\s*[A-Za-z_][A-Za-z0-9_]*=|[][|&;<>()$`*?{}!\\\\\n\r'\"]|(^|\\s)[~#]"
  if (grepl(shell, gsub(quoted, "q", cmd, perl = TRUE), perl = TRUE)) return(NULL)
  words = regmatches(cmd, gregexpr(paste0("(?:[^ \t'\"]+|", quoted, ")+"), cmd, perl = TRUE))[[1L]]
  if (length(words)) gsub("'([^']*)'|\"([^\"]*)\"", "\\1\\2", words, perl = TRUE)
}

#' The program of a word: R and Rscript mean the running R, never a PATH lookup (IC-60)
#' @noRd
bridge_program_word = function(word) {
  if (word %in% c("Rscript", "Rscript.exe")) return(rscript_path())
  if (word %in% c("R", "R.exe")) {
    return(file.path(R.home("bin"), if (is_windows()) "R.exe" else "R"))
  }
  word
}

#' Resolve cmd: an argv (length > 1), a simple line whose program exists (not a Windows batch
#' file) run directly, else P04's shell_resolve() (its `args` may carry `verbatim`)
#' @return `list(command = chr(1), args = chr, via = "argv" | "direct" | "shell")`
#' @noRd
bridge_resolve = function(cmd) {
  if (length(cmd) > 1L) {
    return(list(command = bridge_program_word(cmd[[1L]]), args = cmd[-1L], via = "argv"))
  }
  words = bridge_split(cmd)
  if (length(words)) {
    prog = bridge_program_word(words[[1L]])
    path = if (grepl("/", prog, fixed = TRUE)) prog else Sys.which(prog)
    if (file.exists(path) && !grepl("\\.(cmd|bat)$", path, ignore.case = TRUE)) {
      return(list(command = prog, args = words[-1L], via = "direct"))
    }
  }
  c(shell_resolve(cmd), via = "shell")
}

#' A validated JSON array (P06 turns chr into a list of strings) back to chr, names kept
#' @noRd
bridge_chr = function(x) {
  if (!is.list(x) || !all(vapply(x, rlang::is_string, NA))) return(x)
  unlist(x) %||% character()
}

#' The truncation notice, naming the peter$out() handle of the full text when stored
#' @noRd
bridge_notice = function(omitted, id = NULL, stream = "stdout") {
  if (is.null(id)) return(paste0("[... ", omitted, " lines omitted]"))
  if (identical(stream, "stdout")) return(truncation_notice(omitted, id))
  paste0("[... ", omitted, " lines omitted; all: peter$out(\"", id, "\", \"", stream, "\")]")
}

#' Head (`head` of the budget left after the notice) and tail of lines within a token budget
#' Per-line costs with their newline bound est_tokens() of the joined view (G5 budget_view).
#' @noRd
bridge_view_lines = function(lines, budget, head = 0.4, id = NULL, stream = "stdout") {
  n = length(lines)
  costs = est_tokens_each(paste0(lines, "\n"), "r_output")
  if (!n || sum(costs) <= budget) return(lines)
  avail = max(budget - est_tokens_each(paste0(bridge_notice(n, id, stream), "\n"), "r_output"), 0)
  head_n = sum(cumsum(costs) <= avail * head)
  left = avail - sum(costs[seq_len(head_n)])
  tail_n = min(sum(cumsum(rev(costs)) <= left), n - head_n - 1L)
  c(utils::head(lines, head_n), bridge_notice(n - head_n - tail_n, id, stream),
    utils::tail(lines, tail_n))
}

#' The print budget: max_tokens, else gptr.helper_output_tokens, at most 0.6 x gptr.r_output_tokens
#' inside a run (04 section 9.4; D-160)
#' @noRd
bridge_budget = function(max_tokens = NULL) {
  if (!is.null(max_tokens)) return(as.integer(max_tokens))
  b = gptr_opt("helper_output_tokens")
  if (!is.null(run_current())) b = min(b, floor(0.6 * gptr_opt("r_output_tokens")))
  as.integer(b)
}

#' A one-line label of a command for digests and job listings
#' @noRd
bridge_label = function(cmd, width = 50L) {
  x = gsub("\\s+", " ", paste(cmd, collapse = " "))
  if (nchar(x) > width) paste0(substr(x, 1L, width - 3L), "...") else x
}
