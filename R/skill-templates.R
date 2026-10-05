# skill-templates.R -- prompt templates (plan P17): Pi's grammar (report 05 sections 3.7 and
# 5.1, MIT), the `/name args` commands templates become, and builtin:prompts. Layer L4.

#' Placeholder pattern: Pi's regex plus Claude's `$ARGUMENTS[N]` (0-based)
#'
#' Groups: 1 default target, 2 default value, 3 slice start, 4 slice length, 5 the
#' `$ARGUMENTS[N]` index, 6 a simple placeholder (`$ARGUMENTS`, `$@`, `$N`).
#' @noRd
template_re = paste0(
  "\\$\\{(\\d+|ARGUMENTS|@):-([^}]*)\\}",
  "|\\$\\{@:(\\d+)(?::(\\d+))?\\}",
  "|\\$ARGUMENTS\\[(\\d+)\\]",
  "|\\$(ARGUMENTS|@|\\d+)"
)

#' Split command arguments: whitespace, `'...'` and `"..."` quotes, no escapes
#'
#' Port of Pi `parseCommandArgs()` (report 05 section 5.1): an empty quoted string gives no
#' argument. Whitespace is the ASCII set the command pattern's `\s` matches (space, tab, newline,
#' vertical tab, form feed, carriage return) in every locale (D-084). Each character is tagged
#' with the number of its argument and every argument is joined once, so the cost is linear.
#' Input is made UTF-8 before paste(), which would turn latin1 into "<e9>" in a C locale.
#' @noRd
template_args_parse = function(x) {
  x = paste(as_utf8(x), collapse = " ")
  chars = strsplit(x, "", fixed = TRUE)[[1L]]
  space = chars %in% c(" ", "\t", "\n", "\v", "\f", "\r")
  arg = integer(length(chars))
  cur = 1L
  open = FALSE
  in_quote = NULL
  for (i in seq_along(chars)) {
    ch = chars[i]
    if (!is.null(in_quote)) {
      if (identical(ch, in_quote)) in_quote = NULL else arg[i] = cur
    } else if (ch == "\"" || ch == "'") {
      in_quote = ch
    } else if (!space[i]) {
      arg[i] = cur
    } else if (open) {
      cur = cur + 1L
      open = FALSE
    }
    if (arg[i] > 0L) open = TRUE
  }
  keep = arg > 0L
  if (!any(keep)) return(character())
  vapply(split(chars[keep], arg[keep]), paste, "", collapse = "", USE.NAMES = FALSE)
}

#' Substitute placeholders in one pass; argument values and defaults are never re-scanned
#'
#' Port of Pi `substituteArgs()` (report 05 section 5.1). Matching runs on UTF-8 bytes and the
#' pieces are joined byte for byte, so the result does not depend on the locale.
#' @noRd
template_substitute = function(content, args = character()) {
  content = as_utf8(content)
  args = if (length(args)) as_utf8(as.character(args)) else character()
  mark = function(x) {
    Encoding(x) = "UTF-8"
    x
  }
  all_args = paste(args, collapse = " ")
  m = gregexpr(template_re, content, perl = TRUE, useBytes = TRUE)[[1L]]
  if (m[1L] == -1L) return(mark(content))
  raw = charToRaw(content)
  ml = attr(m, "match.length")
  cs = attr(m, "capture.start")
  cl = attr(m, "capture.length")
  bytes = function(start, len) {
    if (len <= 0L) "" else rawToChar(raw[seq.int(start, length.out = len)])
  }
  has = function(i, j) cs[i, j] > 0L
  grp = function(i, j) bytes(cs[i, j], cl[i, j])
  pick = function(idx) if (!is.na(idx) && idx >= 1 && idx <= length(args)) args[idx] else ""
  out = character()
  pos = 1L
  for (i in seq_along(m)) {
    out = c(out, bytes(pos, m[i] - pos))
    if (has(i, 1L)) {
      target = grp(i, 1L)
      value = if (target %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(target))
      rep = if (nzchar(value)) value else grp(i, 2L)
    } else if (has(i, 3L)) {
      start = max(1, as.numeric(grp(i, 3L)))
      end = if (has(i, 4L)) start + as.numeric(grp(i, 4L)) - 1 else length(args)
      end = min(end, length(args))
      rep = if (start <= end) paste(args[seq.int(start, end)], collapse = " ") else ""
    } else if (has(i, 5L)) {
      rep = pick(as.numeric(grp(i, 5L)) + 1)
    } else {
      simple = grp(i, 6L)
      rep = if (simple %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(simple))
    }
    out = c(out, rep)
    pos = m[i] + ml[i]
  }
  out = c(out, bytes(pos, length(raw) - pos + 1L))
  pieces = vapply(out, function(z) {
    Encoding(z) = "unknown"
    z
  }, "", USE.NAMES = FALSE)
  mark(paste(pieces, collapse = ""))
}

#' Expand a template with arguments (contract 04 section 7.17)
#'
#' `args` is the raw argument string after the command (one string, split with Pi's quoting
#' rules) or a character vector of arguments.
#' @noRd
template_expand = function(text, args = character()) {
  check_string(text, "text", empty = TRUE)
  if (is.null(args)) args = character()
  a = if (length(args) == 1L) template_args_parse(args) else as.character(args)
  template_substitute(text, a)
}

#' Expand `/name args` input when `lookup` knows the template, else return the input unchanged
#'
#' `lookup` is a named list or chr of template texts, or `function(name)` returning the text or
#' NULL. Pi's command pattern `^/([^\s]+)(?:\s+([\s\S]*))?$` (report 05 section 3.7).
#' @noRd
template_expand_input = function(text, lookup) {
  if (!startsWith(text, "/")) return(text)
  mm = regmatches(text, regexec("^/([^\\s]+)(?:\\s+([\\s\\S]*))?$", text, perl = TRUE))[[1L]]
  if (!length(mm)) return(text)
  name = mm[2L]
  argstr = if (length(mm) >= 3L && !is.na(mm[3L])) mm[3L] else ""
  content = if (is.function(lookup)) {
    lookup(name)
  } else if (name %in% names(lookup)) {
    lookup[[name]]
  } else {
    NULL
  }
  if (is.null(content)) return(text)
  template_substitute(content, template_args_parse(argstr))
}
