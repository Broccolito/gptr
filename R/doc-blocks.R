# doc-blocks.R -- history-document blocks (plan P15; contract 7.15, 11.5; IC-45..IC-49): the block
# grammar, prompt and args hashes, the gptr() call scanner, block ownership, stale and user-edited
# detection, the recorded block content and the writer doc_upsert(). Layer L4: it calls L0
# helpers, the record constructors, the kernel SDK (session_data(), session_append()) and its
# own area only. Adapted from report 14 section 5.0 (proto/gptrdoc.R: doc_find_blocks,
# doc_scan_calls, doc_blocks_after, doc_owned_block, doc_render_block, prompt_hash, parse_kv,
# format_kv) with the verification-log fixes (radix ordering; sys.source frames) and G3 (11).

doc_re_open = "^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$"
doc_re_close = "^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$"
doc_re_kv = "([A-Za-z_][A-Za-z0-9_.]*)=(\"([^\"\\\\]|\\\\.)*\"|[^ \t]+)"
doc_re_steer = "^[ \t]*## (Steer|Follow-up): "
doc_block_token = "@@GPTR_BLOCK@@"
doc_header_keys = c("model", "date", "prompt", "sha", "call", "tokens", "cost", "session", "turn",
                    "value", "fork", "plan", "status", "args", "kind", "children")
doc_quoted_keys = "children"

#' Collapse text to one comment-safe line
#' @noRd
doc_one_line = function(x) {
  x = as_utf8(paste(as.character(x), collapse = " "))
  trimws(gsub("[\r\n\t]+", " ", x))
}

#' An R string literal that keeps non-ASCII characters (encodeString() escapes them in a C locale)
#' @noRd
doc_str_literal = function(x) {
  x = as_utf8(as.character(x))
  x = gsub("\\", "\\\\", x, fixed = TRUE)
  x = gsub("\"", "\\\"", x, fixed = TRUE)
  x = gsub("\n", "\\n", x, fixed = TRUE)
  x = gsub("\r", "\\r", x, fixed = TRUE)
  x = gsub("\t", "\\t", x, fixed = TRUE)
  paste0("\"", x, "\"")
}

#' Undo doc_str_literal(): drop the outer quotes and decode the escapes it writes (backslash,
#' quote, n, r, t); any other escaped character stands for itself. Text that is not one whole
#' literal is returned as written. The R parser is not used: in a C locale it rewrites each
#' non-ASCII character of a literal as "<U+00E1>".
#' @noRd
doc_str_unquote = function(v) {
  if (!grepl("^\"(?:[^\"\\\\]|\\\\.)*\"\\z", v, perl = TRUE)) return(v)
  body = substr(v, 2L, nchar(v) - 1L)
  parts = regmatches(body, gregexpr("\\\\.", body, perl = TRUE), invert = NA)[[1L]]
  esc = seq_along(parts) %% 2L == 0L
  ch = substr(parts[esc], 2L, 2L)
  map = c(n = "\n", r = "\r", t = "\t")
  hit = ch %in% names(map)
  ch[hit] = map[ch[hit]]
  parts[esc] = ch
  paste(parts, collapse = "")
}

#' Parse the key=value pairs of a block header into a named list of strings
#' @noRd
doc_parse_kv = function(s) {
  if (is.null(s) || !length(s) || is.na(s) || !nzchar(trimws(s))) return(list())
  kv = regmatches(s, gregexpr(doc_re_kv, s, perl = TRUE))[[1L]]
  if (!length(kv)) return(list())
  keys = sub("=.*$", "", kv)
  vals = sub("^[^=]*=", "", kv)
  quoted = startsWith(vals, "\"")
  vals[quoted] = vapply(vals[quoted], doc_str_unquote, "", USE.NAMES = FALSE)
  stats::setNames(as.list(as_utf8(vals)), keys)
}

#' Format header fields in the key order of contract 11.5 (unknown keys last); values that hold
#' a blank, a line break, a quote, `=` or a backslash are quoted so the header stays one line
#' @noRd
doc_format_kv = function(x) {
  x = x[!vapply(x, function(v) is.null(v) || !length(v), NA)]
  if (!length(x)) return("")
  known = intersect(doc_header_keys, names(x))
  x = x[c(known, setdiff(names(x), known))]
  vals = vapply(names(x), function(k) {
    v = as.character(x[[k]])[1L]
    if (is.na(v)) v = "NA"
    quote = k %in% doc_quoted_keys || !nzchar(v) || grepl("[ \t\r\n\"=\\\\]", v)
    if (quote) doc_str_literal(v) else v
  }, "")
  paste0(names(x), "=", vals, collapse = " ")
}

#' The agent blocks of a text: df(id, start, end, indent, header (list column)); attribute
#' `malformed` flags unterminated, nested or orphan markers. Only lines holding "gptr:" are
#' matched against the marker patterns.
#' @noRd
doc_find_blocks = function(lines) {
  lines = as_utf8(as.character(lines))
  hit = which(grepl("gptr:", lines, fixed = TRUE))
  om = regmatches(lines[hit], regexec(doc_re_open, lines[hit], perl = TRUE))
  cm = regmatches(lines[hit], regexec(doc_re_close, lines[hit], perl = TRUE))
  is_open = lengths(om) > 0L
  is_close = lengths(cm) > 0L
  opens = hit[is_open]
  open_m = om[is_open]
  closes = hit[is_close]
  close_ids = vapply(cm[is_close], function(m) m[3L], "")
  ids = character()
  starts = integer()
  ends = integer()
  indents = character()
  headers = list()
  bad = FALSE
  for (k in seq_along(opens)) {
    i = opens[k]
    m = open_m[[k]]
    id = m[3L]
    j = closes[closes > i & close_ids == id]
    nxt = opens[opens > i]
    if (!length(j) || (length(nxt) && nxt[1L] < j[1L])) {
      bad = TRUE
      next
    }
    ids = c(ids, id)
    starts = c(starts, i)
    ends = c(ends, j[1L])
    indents = c(indents, m[2L])
    headers[[length(headers) + 1L]] = doc_parse_kv(m[4L])
  }
  if (anyDuplicated(ids) || length(setdiff(closes, ends))) bad = TRUE
  res = data.frame(id = ids, start = starts, end = ends, indent = indents,
                   stringsAsFactors = FALSE)
  res$header = headers
  attr(res, "malformed") = bad
  res
}

#' Body lines of one row of doc_find_blocks(), without the block's indentation
#' @noRd
doc_block_body = function(lines, block) {
  if (block$end - block$start < 2L) return(character())
  body = lines[(block$start + 1L):(block$end - 1L)]
  ind = block$indent
  if (nzchar(ind)) body = ifelse(startsWith(body, ind), substring(body, nchar(ind) + 1L), body)
  body
}

#' First 8 hex of sha256 of the body as written, without steering lines (IC-49)
#' @noRd
doc_body_sha = function(body) {
  body = as_utf8(as.character(body))
  body = body[!grepl(doc_re_steer, body)]
  substr(hash_sha256(paste(body, collapse = "\n")), 1L, 8L)
}

#' 12 hex of sha256 of the normalised prompt template (contract 7.15): trimws, CRLF -> LF,
#' whitespace around newlines removed
#' @noRd
prompt_hash = function(template) {
  p = as_utf8(paste(as.character(template), collapse = "\n"))
  p = gsub("[ \t]*\r?\n[ \t]*", "\n", trimws(p))
  substr(hash_sha256(p), 1L, 12L)
}

#' 8 hex of sha256 of the sorted interpolated `name=value` pairs, NULL without interpolation
#' (IC-45). `interp` is P08's character vector of pairs or a named list of values.
#' @noRd
args_hash = function(interp) {
  if (is.null(interp) || !length(interp)) return(NULL)
  if (is.list(interp) || (!is.null(names(interp)) && all(nzchar(names(interp))))) {
    vals = vapply(interp, function(v) paste(as.character(v), collapse = ", "), "")
    interp = paste0(names(interp), "=", vals)
  }
  x = sort(as_utf8(as.character(interp)), method = "radix")
  substr(hash_sha256(paste(x, collapse = "\n")), 1L, 8L)
}

#' Status of a block: undone > user-edited (sha) > stale (prompt or args) > fresh. With
#' `ph = NULL` only undone and user-edited are detected. Header keys are matched exactly.
#' @noRd
doc_block_status = function(header, body, ph = NULL, ah = NULL) {
  if (identical(header[["status"]], "undone")) return("undone")
  sha = header[["sha"]]
  if (!is.null(sha) && !identical(sha, doc_body_sha(body))) return("user-edited")
  if (!is.null(ph)) {
    if (!identical(header[["prompt"]], ph)) return("stale")
    if (!identical(header[["args"]] %||% "", ah %||% "")) return("stale")
  }
  "fresh"
}

#' Render a marker block (contract 11.5): header, indented non-empty body lines, footer
#' @noRd
doc_render_block = function(id, header = list(), body = character(), indent = "") {
  kv = doc_format_kv(header)
  head = paste0(indent, "# >>> gptr:", id, if (nzchar(kv)) paste0(" ", kv) else "")
  c(head, doc_indent_lines(as.character(body), indent), paste0(indent, "# <<< gptr:", id))
}

#' Prefix the non-empty lines with an indentation string
#' @noRd
doc_indent_lines = function(x, indent = "") {
  if (!nzchar(indent %||% "")) return(x)
  x[nzchar(x)] = paste0(indent, x[nzchar(x)])
  x
}

#' Replace lines from..to of a text by `new`
#' @noRd
doc_splice = function(lines, from, to, new) {
  c(lines[seq_len(from - 1L)], new, if (to < length(lines)) lines[(to + 1L):length(lines)])
}

# ---- the gptr() call scanner, anchors and block ownership (report 14 sections 3.1 and 4.2) ----

#' P15's process state `the$doc_pending` (contract 7.0): deferred and pending upserts by
#' document key (`docs`), document locks held until exit (`held`), whether the exit finalizer is
#' registered, gptr_source() frames, the knitr chunks to skip, Rscript call counters, the
#' doc.edit re-entrancy flag and the parse memo of doc_scan_calls() (`scan`, `scan_keys`)
#' @noRd
doc_state = function() {
  st = the$doc_pending
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$docs = list()
    st$held = list()
    st$finalizer = FALSE
    st$sources = list()
    st$knitr_skip = character()
    st$knitr_hooked = FALSE
    st$counters = list()
    st$in_edit = FALSE
    st$scan = new.env(parent = emptyenv())
    st$scan_keys = character()
    the$doc_pending = st
  }
  st
}

#' Parse R text so that parse-data columns and getParseText() (which cuts source lines with
#' substr()) count the same unit (IC-62). In a UTF-8 locale marked UTF-8 is parsed: nothing is
#' translated and both count characters. Elsewhere the parser would translate marked text to the
#' native encoding (in a C locale each non-ASCII character becomes "<U+00E9>" text), so the
#' unmarked UTF-8 bytes are parsed and both count bytes. Strings read back from the result go
#' through as_utf8(). Parse data is kept even where the caller turned it off: sys.source() sets
#' `keep.parse.data = FALSE` while the sourced code runs.
#' @noRd
doc_parse_text = function(lines, keep_source = TRUE) {
  old = options(keep.parse.data = TRUE)
  on.exit(options(old), add = TRUE)
  text = if (isTRUE(l10n_info()[["UTF-8"]])) as_utf8(lines) else os_bytes(lines)
  parse(text = text, keep.source = keep_source)
}

#' An empty call table (the columns of doc_scan_calls())
#' @noRd
doc_calls_empty = function() {
  data.frame(line1 = integer(), col1 = integer(), line2 = integer(), col2 = integer(),
             stmt1 = integer(), stmt2 = integer(), nested = logical(), prompt = character(),
             n_in_stmt = integer(), text = character(), ident = character(),
             stringsAsFactors = FALSE)
}

#' The gptr() calls of an R text: positions, statement range, nesting, prompt literal, ordinal
#' within the statement (report 14 doc_scan_calls, with `prompt =` and named-argument handling),
#' the call's text and its identity text (`ident`: the text that parses to the call R evaluates,
#' the whole pipe for the right-hand side of `|>`, the call with `.` inserted as magrittr calls
#' it for the right-hand side of a magrittr pipe, else the call's text). A text that does not
#' parse gives no calls and the attribute `parse_error`. Texts of 20 lines or more are remembered
#' (the 16 most recently used), so every gptr() call of a long script locates through one parse.
#' @noRd
doc_scan_calls = function(lines, fun = "gptr", line_offset = 0L) {
  lines = as_utf8(as.character(lines))
  if (!length(lines)) return(doc_calls_empty())
  if (length(lines) < 20L) return(doc_scan_parse(lines, fun, line_offset))
  st = doc_state()
  key = hash_sha256(paste(c(fun, line_offset, lines), collapse = "\n"))
  res = get0(key, envir = st$scan, inherits = FALSE)
  if (is.null(res)) {
    res = doc_scan_parse(lines, fun, line_offset)
    assign(key, res, envir = st$scan)
  }
  st$scan_keys = c(setdiff(st$scan_keys, key), key)
  if (length(st$scan_keys) > 16L) {
    rm(list = st$scan_keys[1L], envir = st$scan)
    st$scan_keys = st$scan_keys[-1L]
  }
  res
}

#' The parse behind doc_scan_calls(): ids are looked up through vectors indexed by parse-data id.
#' Parse data carries the text of terminal tokens only (the default); getParseText() reads the
#' text of a call back from the source, which keeps a long script's parse cheap. The parser
#' rewrites `lhs |> gptr(q)` into `gptr(lhs, q)`, which is what sys.call() reports, so a call
#' that is the right-hand operand of a pipe takes the pipe's text as its identity and its
#' left-hand side as an argument (doc_call_prompt()). magrittr (not a dependency, but users pipe
#' into gptr() with it: contract 6.1, research 12 D3) runs `lhs %>% gptr(q)` as `gptr(., q)`
#' with `.` bound to the left-hand side (doc_dot_ident()).
#' @noRd
doc_scan_parse = function(lines, fun, line_offset) {
  empty = doc_calls_empty()
  exprs = tryCatch(doc_parse_text(lines), error = function(e) e)
  if (inherits(exprs, "error")) {
    attr(empty, "parse_error") = conditionMessage(exprs)
    return(empty)
  }
  pd = utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) return(empty)
  sym = which(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == fun)
  if (!length(sym)) return(empty)
  parent = integer(max(pd$id))
  parent[pd$id] = pd$parent
  row = integer(max(pd$id))
  row[pd$id] = seq_len(nrow(pd))
  nest = c("FUNCTION", "'\\\\'", "FOR", "WHILE", "REPEAT", "IF", "'{'")
  nesting = unique(pd$parent[pd$token %in% nest])
  # magrittr's pipes that call their right-hand side with `.` (its %$% calls it as written)
  dot_pipes = c("%>%", "%T>%", "%!>%", "%<>%")
  pipes = which(pd$token == "PIPE" | (pd$token == "SPECIAL" & pd$text %in% dot_pipes))
  rows = vector("list", length(sym))
  for (i in seq_along(sym)) {
    call_id = parent[parent[pd$id[sym[i]]]]
    pipe = doc_pipe_operands(pd, pipes, parent[call_id], row[call_id])
    magrittr = isTRUE(pipe[["magrittr"]])
    anc = call_id
    nested = FALSE
    repeat {
      p = parent[anc]
      if (p <= 0L) break
      if (p %in% nesting) nested = TRUE
      anc = p
    }
    top = row[anc]
    cl = row[call_id]
    text = as_utf8(utils::getParseText(pd, call_id))
    ident = if (is.null(pipe)) {
      text
    } else if (magrittr) {
      doc_dot_ident(pd, call_id, text)
    } else {
      as_utf8(utils::getParseText(pd, parent[call_id]))
    }
    prompt = doc_call_prompt(pd, call_id, pipe[["lhs"]] %||% NA_integer_, magrittr)
    rows[[i]] = data.frame(line1 = pd$line1[cl], col1 = pd$col1[cl], line2 = pd$line2[cl],
                           col2 = pd$col2[cl], stmt1 = pd$line1[top], stmt2 = pd$line2[top],
                           nested = nested, prompt = prompt, n_in_stmt = NA_integer_,
                           text = text, ident = ident, stringsAsFactors = FALSE)
  }
  res = do.call(rbind, rows)
  res = res[order(res$line1, res$col1, method = "radix"), , drop = FALSE]
  shift = as.integer(line_offset)
  res$line1 = res$line1 + shift
  res$line2 = res$line2 + shift
  res$stmt1 = res$stmt1 + shift
  res$stmt2 = res$stmt2 + shift
  res$n_in_stmt = as.integer(stats::ave(res$line1, res$stmt1, FUN = seq_along))
  rownames(res) = NULL
  res
}

#' The pipe whose right-hand operand is the call at parse-data row `cl` (parent id `p`; `pipes`
#' are the rows of PIPE tokens and of magrittr's SPECIAL pipe tokens): list(lhs = parse-data id
#' of the left-hand expression, magrittr = whether the pipe is magrittr's), or NULL when the
#' call is not the right-hand side of a pipe (the left-hand call of a pipe has the same parent
#' but starts before the operator)
#' @noRd
doc_pipe_operands = function(pd, pipes, p, cl) {
  if (p <= 0L) return(NULL)
  op = pipes[pd$parent[pipes] == p]
  if (!length(op)) return(NULL)
  op = op[1L]
  if (pd$line1[cl] < pd$line1[op] || (pd$line1[cl] == pd$line1[op] && pd$col1[cl] < pd$col1[op])) {
    return(NULL)
  }
  lhs = pd$id[pd$parent == p & pd$token == "expr" & pd$id != pd$id[cl]]
  list(lhs = lhs[1L], magrittr = identical(pd$token[op], "SPECIAL"))
}

#' Is a parse-data argument (its child rows `arg`) the bare symbol `.` (magrittr's placeholder)
#' @noRd
doc_is_dot = function(arg) {
  nrow(arg) == 1L && identical(arg$token, "SYMBOL") && arg$text %in% c(".", "`.`")
}

#' The identity text of the right-hand call of a magrittr pipe (call text `text`): magrittr
#' calls it with `.` as its first argument unless an argument (named or not) is `.` itself, so
#' `x %>% gptr(q)` runs `gptr(., q)` and `x %>% gptr(q, .)` runs `gptr(q, .)`. The first `(` of
#' the text opens the argument list (the function part is `gptr` or `pkg::gptr`).
#' @noRd
doc_dot_ident = function(pd, call_id, text) {
  ch = pd[pd$parent == call_id & !(pd$token %in% c("'('", "')'", "COMMENT")), , drop = FALSE]
  if (any(vapply(ch$id, function(id) doc_is_dot(pd[pd$parent == id, , drop = FALSE]), NA))) {
    return(text)
  }
  sub("(", if (nrow(ch) > 1L) "(., " else "(.", text, fixed = TRUE)
}

#' The value of a parse-data argument (its child rows `arg`) when it is one string literal, else
#' NULL. A literal over 1000 bytes is read back from the source by getParseText().
#' @noRd
doc_str_const = function(pd, arg) {
  if (nrow(arg) != 1L || !identical(arg$token, "STR_CONST")) return(NULL)
  val = tryCatch(str2lang(os_bytes(utils::getParseText(pd, arg$id))), error = function(e) NULL)
  if (is.character(val)) val else NULL
}

#' The prompt literal of a call (contract 6.1.1 step 2): a given `prompt =` is the prompt, so a
#' computed one gives NA (the call is then found by its text), never a later unnamed literal;
#' else the first unnamed string literal. `prompt = NULL` and an empty `prompt =` are not given
#' (the default is NULL). Argument names are read as R binds them: `prompt`, `` `prompt` `` or
#' `"prompt"` (a name token is a direct child of the call; a value is wrapped in an `expr`). The
#' left-hand side `lhs_id` of a native pipe is the call's first unnamed argument, or the value of
#' the argument holding the placeholder `_` (`"Summarise" |> gptr()` and
#' `"Summarise" |> gptr(prompt = _)` both prompt "Summarise"). Under a magrittr pipe
#' (`magrittr = TRUE`) the left-hand side is the value of `.`, a symbol and never a literal: a
#' string-literal left side is the prompt as `prompt = .`, or when no unnamed literal is given
#' and `.` is the first unnamed argument (inserted or written), as the first length-1 character
#' value (`"S" %>% gptr(q)` prompts "S", `"S" %>% gptr("more")` prompts "more").
#' @noRd
doc_call_prompt = function(pd, call_id, lhs_id = NA_integer_, magrittr = FALSE) {
  ch = pd[pd$parent == call_id, , drop = FALSE]
  ch = ch[order(ch$line1, ch$col1, method = "radix"), , drop = FALSE]
  lhs = if (is.na(lhs_id)) NULL else doc_str_const(pd, pd[pd$parent == lhs_id, , drop = FALSE])
  named = NULL
  given = FALSE
  positional = NULL
  pending = NULL
  seen_fun = FALSE
  placeholder = FALSE
  dot_first = FALSE
  n_unnamed = 0L
  for (k in seq_len(nrow(ch))) {
    tok = ch$token[k]
    if (tok %in% c("SYMBOL_SUB", "STR_CONST")) {
      pending = doc_arg_name(ch$text[k])
      next
    }
    if (identical(tok, "','")) {
      pending = NULL
      next
    }
    if (!identical(tok, "expr")) next
    if (!seen_fun) {
      seen_fun = TRUE
      next
    }
    arg = pd[pd$parent == ch$id[k], , drop = FALSE]
    hole = if (magrittr) doc_is_dot(arg) else
      nrow(arg) == 1L && identical(arg$token, "PLACEHOLDER")
    if (hole) {
      placeholder = TRUE
      if (identical(pending, "prompt")) {
        given = TRUE
        named = lhs
      } else if (is.null(pending)) {
        if (n_unnamed == 0L) dot_first = TRUE
        n_unnamed = n_unnamed + 1L
      }
      pending = NULL
      next
    }
    val = doc_str_const(pd, arg)
    if (is.null(pending)) {
      n_unnamed = n_unnamed + 1L
      if (is.null(positional) && !is.null(val)) positional = val
    } else if (identical(pending, "prompt") &&
               !(nrow(arg) == 1L && identical(arg$token, "NULL_CONST"))) {
      given = TRUE
      named = val
    }
    pending = NULL
  }
  if (given) return(as_utf8(named %||% NA_character_))
  if (magrittr) {
    if (is.null(positional) && (!placeholder || dot_first)) positional = lhs
  } else if (!placeholder && !is.null(lhs)) {
    positional = lhs
  }
  as_utf8(positional %||% NA_character_)
}

#' The argument name a SYMBOL_SUB or name STR_CONST token binds: backticks removed, a quoted name
#' decoded
#' @noRd
doc_arg_name = function(text) {
  if (startsWith(text, "`")) return(sub("^`(.*)`$", "\\1", text))
  if (!startsWith(text, "\"") && !startsWith(text, "'")) return(text)
  val = tryCatch(str2lang(os_bytes(text)), error = function(e) NULL)
  if (is.character(val)) as_utf8(val) else text
}

#' All gptr() calls of an R text with their block, ordinal inside the block, prompt hash (`ph`)
#' and identity hash (`th`, of the identity text `ident`: the identity of calls with a computed
#' prompt)
#' @noRd
doc_calls = function(lines, blocks = doc_find_blocks(lines)) {
  calls = doc_scan_calls(lines)
  n = nrow(calls)
  calls$block = rep(NA_character_, n)
  calls$n_in_block = rep(NA_integer_, n)
  calls$ph = rep(NA_character_, n)
  calls$th = rep(NA_character_, n)
  if (n) {
    lit = !is.na(calls$prompt)
    calls$ph[lit] = vapply(calls$prompt[lit], prompt_hash, "", USE.NAMES = FALSE)
    calls$th = substr(hash_sha256(calls$ident), 1L, 12L)
    if (nrow(blocks)) {
      calls$block = vapply(calls$line1, function(l) {
        k = which(l > blocks$start & l < blocks$end)
        if (length(k)) blocks$id[k[1L]] else NA_character_
      }, "")
    }
    inb = !is.na(calls$block) & !calls$nested
    if (any(inb)) {
      calls$n_in_block[inb] = as.integer(stats::ave(seq_len(sum(inb)), calls$block[inb],
                                                    FUN = seq_along))
    }
  }
  attr(calls, "blocks") = blocks
  calls
}

#' Rows of a call table that contain the call: by prompt hash, else (computed prompts, whose
#' template is the prompt text) by identity of the call (`call0`, the call R evaluated, as
#' sys.call() reports it) with the parsed identity text, both without source references
#' @noRd
doc_calls_have = function(calls, ph, call0) {
  if (!nrow(calls)) return(integer())
  if (!is.na(ph)) {
    k = which(calls$ph %in% ph)
    if (length(k) || is.null(call0)) return(k)
  }
  if (is.null(call0)) return(integer())
  call0 = doc_call_norm(call0)
  which(is.na(calls$ph) & vapply(calls$ident, function(t) {
    identical(doc_call_norm(tryCatch(str2lang(os_bytes(t)), error = function(e) NULL)), call0)
  }, NA, USE.NAMES = FALSE))
}

#' A call without source references at any depth, for identity tests. Under keep.source = TRUE
#' a call carries a srcref attribute, each `{` carries srcref, srcfile and wholeSrcref attributes
#' and each `function` (or `\(x)`) call holds a srcref as its fourth element; a call parsed from
#' its text without them has NULL there. Done here rather than by utils::removeSource(), which
#' only handles language objects thoroughly from R 4.4.0 (the package supports R >= 4.2.0).
#' @noRd
doc_call_norm = function(x) {
  if (is.null(x) || is.symbol(x)) return(x)
  if (inherits(x, "srcref")) return(NULL)
  if (!is.call(x) && !is.pairlist(x)) return(x)
  attr(x, "srcref") = NULL
  attr(x, "srcfile") = NULL
  attr(x, "wholeSrcref") = NULL
  pl = is.pairlist(x)
  for (i in seq_along(x)) x[i] = list(doc_call_norm(x[[i]]))
  if (pl) as.pairlist(x) else x
}

#' Calls that share an anchor's identity (prompt hash, else call-text hash)
#' @noRd
doc_same_calls = function(calls, ph, th = NA_character_) {
  keep = if (!is.na(ph)) calls$ph %in% ph else calls$th %in% th
  calls[keep, , drop = FALSE]
}

#' The calls of a table in the scope of an anchor: the same agent block (or outside blocks) and,
#' when the table has a `label` column (knitr chunks), the same label. Columns and fields are
#' matched exactly.
#' @noRd
doc_anchor_scope = function(calls, block, label) {
  cls = if (is.na(block)) calls[is.na(calls$block), , drop = FALSE] else
    calls[calls$block %in% block, , drop = FALSE]
  if (!is.na(label) && !is.null(cls[["label"]])) {
    cls = cls[cls[["label"]] %in% label, , drop = FALSE]
  }
  cls
}

#' The anchor of call row `t` (IC-51: calls are re-located by content and ordinal, never by line)
#' @noRd
doc_anchor_of = function(calls, t) {
  label = t[["label"]] %||% NA_character_
  same = doc_same_calls(doc_anchor_scope(calls, t$block, label), t$ph, t$th)
  j = which(same$line1 == t$line1 & same$col1 == t$col1)
  list(ph = t$ph, th = t$th, j = if (length(j)) j[1L] else 1L, block = t$block, label = label)
}

#' Re-locate an anchored call in a (possibly edited) text; NULL when it is gone
#' @noRd
doc_match_anchor = function(calls, anchor) {
  if (is.null(anchor) || !nrow(calls)) return(NULL)
  cls = doc_anchor_scope(calls, anchor[["block"]], anchor[["label"]] %||% NA_character_)
  same = doc_same_calls(cls, anchor[["ph"]], anchor[["th"]])
  if (nrow(same) < anchor[["j"]]) return(NULL)
  same[anchor[["j"]], , drop = FALSE]
}

#' The run of blocks directly after a statement (blank lines allowed between blocks)
#' @noRd
doc_blocks_after = function(lines, stmt_end, blocks) {
  out = integer()
  pos = stmt_end
  repeat {
    k = pos + 1L
    while (k <= length(lines) && !nzchar(trimws(lines[k]))) k = k + 1L
    b = which(blocks$start == k)
    if (!length(b)) break
    out = c(out, b[1L])
    pos = blocks$end[b[1L]]
  }
  blocks[out, , drop = FALSE]
}

#' The `call=` ordinals of a list of block headers (1 when absent or not a number)
#' @noRd
doc_header_ordinals = function(headers) {
  ord = suppressWarnings(as.integer(vapply(headers, function(h) {
    as.character(h[["call"]] %||% NA_character_)
  }, "")))
  ord[is.na(ord)] = 1L
  ord
}

#' Which block of a statement's run the k-th call owns (contract 11.5): the block whose
#' `prompt=` matches (preferring `call=k`), else the one with `call=k` (then stale); `headers` is
#' the list of block headers in run order. `taken` holds the ordinals of the statement's other
#' calls with the same prompt: their blocks are never matched by prompt alone (a pipeline that
#' repeats a prompt, `... |> gptr("improve it") |> gptr("improve it")`). A missing prompt hash
#' never matches a header without `prompt=`. Returns list(index, stale) or NULL.
#' @noRd
doc_run_owner = function(headers, ph, k = 1L, taken = integer()) {
  if (!length(headers)) return(NULL)
  prompts = vapply(headers, function(h) as.character(h[["prompt"]] %||% NA_character_), "")
  ord = doc_header_ordinals(headers)
  same = !is.na(prompts) & prompts %in% ph
  exact = which(same & ord == k)
  if (!length(exact)) exact = which(same & !(ord %in% taken))
  if (length(exact)) return(list(index = exact[1L], stale = FALSE))
  pos = which(ord == k)
  if (length(pos)) return(list(index = pos[1L], stale = TRUE))
  NULL
}

#' The block owned by the k-th call of a statement (doc_run_owner() over the run of blocks after
#' the statement) and where a new block of that call goes: after the run, or after the blocks
#' of earlier calls of a pipeline; `taken` as in doc_run_owner()
#' @noRd
doc_owned_block = function(lines, hit, ph, blocks = doc_find_blocks(lines), taken = integer()) {
  run = doc_blocks_after(lines, hit$stmt2, blocks)
  k = hit$n_in_stmt
  if (!nrow(run)) return(list(block = NULL, stale = FALSE, run = run, insert_after = hit$stmt2))
  own = doc_run_owner(run$header, ph, k, taken)
  if (!is.null(own)) {
    return(list(block = run[own$index, , drop = FALSE], stale = own$stale, run = run,
                insert_after = run$end[nrow(run)]))
  }
  before = which(doc_header_ordinals(run$header) < k)
  list(block = NULL, stale = FALSE, run = run,
       insert_after = if (length(before)) run$end[max(before)] else hit$stmt2)
}

#' Ordinals of the other calls of a hit's statement that share its prompt hash (doc_run_owner())
#' @noRd
doc_same_ordinals = function(calls, hit) {
  if (is.na(hit$ph)) return(integer())
  keep = calls$stmt1 == hit$stmt1 & calls$ph %in% hit$ph & is.na(calls$block) &
    !calls$nested & calls$n_in_stmt != hit$n_in_stmt
  as.integer(calls$n_in_stmt[keep])
}

#' Locate an anchored call and its owned block in an R text (the `r` and `transcript` formats):
#' list(stmt, blocks, hit, owned = list(id, header, status, start, end) | NULL, insert_after,
#' top_level, in_block, ordinal, indent)
#' @noRd
doc_text_locate = function(text, site, calls = doc_calls(text)) {
  blocks = attr(calls, "blocks") %||% doc_find_blocks(text)
  out = list(stmt = NULL, blocks = blocks[0L, , drop = FALSE], hit = NULL, owned = NULL,
             insert_after = NULL, top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "")
  hit = doc_match_anchor(calls, site[["anchor"]])
  if (is.null(hit)) return(out)
  out$hit = hit
  out$stmt = c(hit$stmt1, hit$stmt2)
  out$indent = sub("^([ \t]*).*$", "\\1", text[hit$stmt1])
  if (isTRUE(hit$nested)) return(out)
  if (!is.na(hit$block)) {
    out$in_block = hit$block
    out$ordinal = hit$n_in_block
    return(out)
  }
  out$ordinal = hit$n_in_stmt
  out$top_level = TRUE
  ph = site[["prompt_hash"]]
  own = doc_owned_block(text, hit, ph, blocks, doc_same_ordinals(calls, hit))
  out$blocks = own$run
  out$insert_after = own$insert_after
  if (!is.null(own$block)) {
    b = own$block
    status = doc_block_status(b$header[[1L]], doc_block_body(text, b), ph, site[["args_hash"]])
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = b$id, header = b$header[[1L]], status = status, start = b$start,
                     end = b$end)
  }
  out
}

#' Line range of the k-th top-level expression identical to `expr` (source() frames)
#' @noRd
doc_stmt_by_expr = function(lines, expr, k = 1L) {
  p_src = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  if (is.null(p_src)) return(NULL)
  p_val = doc_parse_text(lines, keep_source = FALSE)
  srs = attr(p_src, "srcref")
  hits = which(vapply(seq_along(p_val), function(j) identical(p_val[[j]], expr), NA))
  if (length(hits) < k) return(NULL)
  sr = srs[[hits[k]]]
  c(sr[1L], sr[3L])
}

# ---- recorded block content (contract 11.5 body; IC-47, IC-48, IC-49) --------------------------

# gptr$ members that are never recorded when no tool spec says otherwise (IC-48)
doc_unrecorded_members = c("out", "plot", "help", "search", "describe")

#' Is a gptr$ member recorded? The tool spec's `record` field, else the IC-48 default list
#' @noRd
doc_member_recorded = function(name) {
  spec = tryCatch(registry_get("tool", name), error = function(e) NULL)
  if (!is.null(spec)) return(!isFALSE(spec[["record"]]))
  !name %in% doc_unrecorded_members
}

#' Should a top-level expression of recorded code be dropped: gptr_return() or a call of a
#' `record = FALSE` gptr$ member (IC-48). The `gptr::` forms are built with eval_guard_ns_call(),
#' not quoted: R CMD check reads a literal `gptr::name` as a use of an export (CI Task CI-4).
#' @noRd
doc_drop_expr = function(e) {
  if (!is.call(e)) return(FALSE)
  head = e[[1L]]
  if (identical(head, quote(gptr_return)) ||
      identical(head, eval_guard_ns_call("gptr_return"))) {
    return(TRUE)
  }
  if (is.call(head) && length(head) == 3L &&
      (identical(head[[1L]], as.name("$")) || identical(head[[1L]], as.name("[["))) &&
      (identical(head[[2L]], quote(gptr)) || identical(head[[2L]], eval_guard_ns_call("gptr")))) {
    return(!doc_member_recorded(as.character(head[[3L]])))
  }
  FALSE
}

#' The parse-data column of each byte of one line of a text parsed by doc_parse_text() (IC-62).
#' R's parser starts a line at column 0, advances one column per character when it reads the text
#' as UTF-8 (doc_parse_text() in a UTF-8 locale) and one per byte otherwise, and moves a tab to the
#' next multiple of 8. srcref byte fields are not used: in a UTF-8 locale R (4.5.0) reports them
#' shifted after a multi-byte character.
#' @noRd
doc_byte_cols = function(line, utf8 = isTRUE(l10n_info()[["UTF-8"]])) {
  b = as.integer(charToRaw(line))
  step = if (utf8) as.integer(b < 128L | b > 191L) else rep(1L, length(b))
  if (!any(b == 9L)) return(cumsum(step))
  col = integer(length(b))
  k = 0L
  for (i in seq_along(b)) {
    k = k + step[i]
    if (b[i] == 9L) k = bitwAnd(k + 7L, bitwNot(7L))
    col[i] = k
  }
  col
}

#' Join what is left of a line around a cut expression: the `;` that separated the expression
#' from the next one goes with it, else the one before it (it was the last on its line). Only the
#' edges of the cut are touched, never a string literal elsewhere on the line.
#' @noRd
doc_join_cut = function(left, right) {
  after = sub("^[ \t]*;[ \t]*", "", right)
  if (identical(after, right)) {
    left = sub("[ \t]*;[ \t]*$", "", left)
    if (!nzchar(trimws(left))) after = sub("^[ \t]+", "", right)
  }
  sub("[ \t]+$", "", paste0(left, after))
}

#' Remove dropped top-level expressions (srcrefs `drop`) from the lines. What is cut: the exact
#' text of each dropped expression, and every whole line that a dropped expression touches and no
#' kept expression (srcrefs `keep`) does, its comments included. Overlapping cuts are merged, so
#' expressions that share lines with each other go together. A cut that covers whole lines removes
#' them; any other cut joins the text before it to the text after it (doc_join_cut()) and removes
#' the lines in between, and the joined line too when nothing is left on it. Positions are srcref
#' lines and columns mapped to bytes by doc_byte_cols(). NULL when a position does not map.
#' @noRd
doc_drop_ranges = function(lines, drop, keep) {
  span = function(sr) seq(sr[1L], sr[3L])
  keep_lines = unique(unlist(lapply(keep, span), use.names = FALSE))
  drop_lines = setdiff(unique(unlist(lapply(drop, span), use.names = FALSE)), keep_lines)
  nb = nchar(lines, type = "bytes")
  cuts = lapply(drop, function(sr) {
    c(sr[1L], match(sr[5L], doc_byte_cols(lines[sr[1L]])), sr[3L],
      findInterval(sr[6L], doc_byte_cols(lines[sr[3L]])))
  })
  for (cut in cuts) {
    if (is.na(cut[2L]) || cut[4L] < 1L || (cut[1L] == cut[3L] && cut[4L] < cut[2L])) return(NULL)
  }
  cuts = c(cuts, lapply(drop_lines, function(l) c(l, 1L, l, nb[l])))
  starts = vapply(cuts, function(cut) cut[1L], 0L)
  cuts = cuts[order(starts, vapply(cuts, function(cut) cut[2L], 0L), method = "radix")]
  merged = list(cuts[[1L]])
  for (cut in cuts[-1L]) {
    cur = merged[[length(merged)]]
    if (cut[1L] > cur[3L] || (cut[1L] == cur[3L] && cut[2L] > cur[4L])) {
      merged[[length(merged) + 1L]] = cut
    } else if (cut[3L] > cur[3L] || (cut[3L] == cur[3L] && cut[4L] > cur[4L])) {
      merged[[length(merged)]][3:4] = cut[3:4]
    }
  }
  remove = logical(length(lines))
  for (cut in rev(merged)) {
    l1 = cut[1L]
    l2 = cut[3L]
    if (cut[2L] == 1L && cut[4L] >= nb[l2]) {
      remove[l1:l2] = TRUE
      next
    }
    first = charToRaw(lines[l1])
    last = charToRaw(lines[l2])
    left = as_utf8(rawToChar(first[seq_len(cut[2L] - 1L)]))
    right = as_utf8(rawToChar(last[seq_along(last) > cut[4L]]))
    lines[l1] = doc_join_cut(left, right)
    if (l2 > l1) remove[(l1 + 1L):l2] = TRUE
    if (!nzchar(trimws(lines[l1]))) remove[l1] = TRUE
  }
  lines[!remove]
}

#' Do the lines parse to exactly the expressions `ref` (source references ignored)?
#' @noRd
doc_same_exprs = function(lines, ref) {
  ex = tryCatch(doc_parse_text(lines, keep_source = FALSE), error = function(e) NULL)
  if (is.null(ex) || length(ex) != length(ref)) return(FALSE)
  identical(lapply(ex, doc_call_norm), lapply(ref, doc_call_norm))
}

#' Best-effort S-9 rewrite of the left arrow to `=` (IC-48): LEFT_ASSIGN tokens whose assignment
#' is a top-level expression or a direct child of a `{` list (itself top level or such a child),
#' never inside call arguments; `->`, the superassignment and pipes are left alone. Token columns
#' are mapped to bytes (doc_byte_cols()); a line whose mapped bytes are not the arrow is kept.
#' @noRd
doc_rewrite_assign = function(lines) {
  exprs = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  if (is.null(exprs) || !length(exprs)) return(lines)
  pd = utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) return(lines)
  la = which(pd$token == "LEFT_ASSIGN" & pd$text == paste0("<", "-"))
  if (!length(la)) return(lines)
  parent = integer(max(pd$id))
  parent[pd$id] = pd$parent
  brace = logical(max(pd$id))
  ob = pd$parent[pd$token == "'{'"]
  brace[ob[ob > 0L]] = TRUE
  allowed = function(p) {
    while (p > 0L) {
      if (!brace[p]) return(FALSE)
      p = parent[p]
    }
    TRUE
  }
  la = la[vapply(la, function(i) allowed(parent[pd$parent[i]]), NA)]
  for (l in unique(pd$line1[la])) {
    b = charToRaw(lines[l])
    at = match(pd$col1[la[pd$line1[la] == l]], doc_byte_cols(lines[l]))
    if (anyNA(at) || any(at >= length(b)) ||
        !all(b[at] == as.raw(60L) & b[at + 1L] == as.raw(45L))) {
      next
    }
    for (h in sort(at, decreasing = TRUE)) {
      b = c(b[seq_len(h - 1L)], as.raw(61L), b[seq_along(b) > h + 1L])
    }
    lines[l] = as_utf8(rawToChar(b))
  }
  lines
}

#' Recorded code of one r call: drop gptr_return() and record = FALSE members, rewrite the left
#' arrow, trim blank edges (IC-48). The text is parsed as doc_parse_text() parses it (IC-62; parse
#' data kept under sys.source()); a cut whose result does not parse to the kept expressions
#' leaves the code as written. Attribute `kept`: one logical per top-level expression (NULL when
#' the code does not parse; such code is kept as written).
#' @noRd
doc_code_clean = function(code) {
  lines = strsplit(as_utf8(paste(code, collapse = "\n")), "\n", fixed = TRUE)[[1L]]
  if (!length(lines)) return(character())
  exprs = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  kept = NULL
  if (!is.null(exprs) && length(exprs)) {
    drop = vapply(seq_along(exprs), function(i) doc_drop_expr(exprs[[i]]), NA)
    if (any(drop)) {
      srcs = attr(exprs, "srcref")
      cut = doc_drop_ranges(lines, srcs[drop], srcs[!drop])
      if (!is.null(cut) && doc_same_exprs(cut, exprs[!drop])) lines = cut else drop[] = FALSE
    }
    lines = doc_rewrite_assign(lines)
    kept = !drop
  }
  while (length(lines) && !nzchar(trimws(lines[1L]))) lines = lines[-1L]
  while (length(lines) && !nzchar(trimws(lines[length(lines)]))) lines = lines[-length(lines)]
  structure(lines, kept = kept)
}

#' The flag line of a block whose code holds a secret that cannot be replayed (contract 11.5)
#' @noRd
doc_secret_flag = "# gptr: block needs secrets that are not recorded"

#' Markers that redaction rules write (the built-in rules' and the registered rules' fixed
#' markers, P03's redact_known_markers() without registered secrets). Such a marker stands for a
#' value a rule matched, never for an environment variable.
#' @noRd
doc_rule_markers = function() {
  rules = tryCatch(rules_current(), error = function(e) list())
  redact_known_markers(list(rules = rules))
}

#' String literals that are exactly a secret marker of an environment variable become
#' Sys.getenv("NAME") (entries are redacted at ingress, so recorded code holds markers; G6 5.6).
#' A marker that a redaction rule writes (doc_rule_markers(), for example `[secret:jwt]`), a
#' marker inside a longer literal and one in a comment stay, and code_for_history() flags them.
#' Text that does not parse is returned as it is.
#' @noRd
doc_secret_literals = function(lines) {
  if (!any(grepl("[secret:", lines, fixed = TRUE))) return(lines)
  exprs = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  pd = if (is.null(exprs)) NULL else utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) return(lines)
  re = "^([\"'])\\[secret:([A-Za-z_][A-Za-z0-9_]*)\\]\\1$"
  hit = which(pd$token == "STR_CONST" & pd$line1 == pd$line2 & grepl(re, pd$text, perl = TRUE))
  marker = substr(pd$text[hit], 2L, nchar(pd$text[hit]) - 1L)
  hit = hit[!marker %in% doc_rule_markers()]
  for (l in unique(pd$line1[hit])) {
    h = hit[pd$line1[hit] == l]
    h = h[order(pd$col1[h], decreasing = TRUE)]
    cols = doc_byte_cols(lines[l])
    b = charToRaw(lines[l])
    for (i in h) {
      from = match(pd$col1[i], cols)
      to = findInterval(pd$col2[i], cols)
      if (is.na(from) || to < from || !identical(b[from:to], charToRaw(pd$text[i]))) next
      name = sub(re, "\\2", pd$text[i], perl = TRUE)
      b = c(b[seq_len(from - 1L)], charToRaw(paste0("Sys.getenv(\"", name, "\")")),
            b[seq_along(b) > to])
    }
    lines[l] = as_utf8(rawToChar(b))
  }
  lines
}

#' Recorded code made safe for a document (G6 5.6): marker literals become Sys.getenv("NAME")
#' (doc_secret_literals()), then P03's code_for_history() rewrites literal values and flags what
#' stays a marker. Returns list(lines, secrets) where `secrets` tells that the flag is needed.
#' @noRd
doc_history_code = function(lines) {
  if (!length(lines)) return(list(lines = character(), secrets = FALSE))
  code = paste(doc_secret_literals(lines), collapse = "\n")
  out = strsplit(as.character(code_for_history(code)), "\n", fixed = TRUE)[[1L]]
  secrets = length(out) > 0L && identical(out[1L], doc_secret_flag)
  if (secrets) out = out[-1L]
  list(lines = out, secrets = secrets)
}

#' Lines recorded per execution: gptr.doc_output_lines when set, else setting doc$output_lines
#' @noRd
doc_max_output_lines = function() {
  opt = getOption("gptr.doc_output_lines")
  if (!is.null(opt)) return(as.integer(opt))
  doc = tryCatch(setting_get("doc", default = list()), error = function(e) list())
  as.integer((if (is.list(doc)) doc$output_lines) %||% gptr_opt("doc_output_lines"))
}

#' Printed output (a character vector, or P09's list of output per top-level expression) as
#' `#> ` lines of at most 76 characters, then `#> ... (N more lines)`
#' @noRd
doc_output_lines = function(outputs, max_lines = NULL, width = 76L) {
  out = as.character(unlist(outputs, use.names = FALSE))
  out = unlist(strsplit(as_utf8(out), "\n", fixed = TRUE), use.names = FALSE)
  if (!length(out)) return(character())
  max_lines = max_lines %||% doc_max_output_lines()
  extra = length(out) - max_lines
  if (extra > 0L) out = out[seq_len(max_lines)]
  out = paste0("#> ", substr(out, 1L, width))
  if (extra > 0L) out = c(out, paste0("#> ... (", as.integer(extra), " more lines)"))
  out
}

#' Lines that continue a multi-line string literal (indenting them would change the string)
#' @noRd
doc_string_tails = function(lines) {
  out = logical(length(lines))
  exprs = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  pd = if (is.null(exprs)) NULL else utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) return(out)
  for (i in which(pd$token == "STR_CONST" & pd$line2 > pd$line1)) {
    out[(pd$line1[i] + 1L):pd$line2[i]] = TRUE
  }
  out
}

#' Wrap body lines for an overlay fork or a team child (IC-46, IC-47); the block id is filled in
#' when the block is written (doc_block_token). Lines inside a multi-line string keep their text.
#' @noRd
doc_wrap_local = function(body, child = NULL) {
  if (!length(body)) return(character())
  target = if (is.null(child)) {
    paste0("gptr_resume(block = \"", doc_block_token, "\")")
  } else {
    paste0("gptr_resume(block = \"", doc_block_token, "\", child = ", doc_str_literal(child), ")")
  }
  pad = nzchar(body) & !doc_string_tails(body)
  body[pad] = paste0("  ", body[pad])
  c("local({", body, paste0("}, envir = ", target, "$envir)"))
}

#' Entries on the active branch of a session, root first (the leaf's parent chain; P06's id index
#' when it agrees with the entries)
#' @noRd
doc_path_entries = function(session) {
  d = session_data(session)
  ents = d$entries
  if (!length(ents)) return(list())
  ids = vapply(ents, function(e) as.character(e$id %||% NA_character_), "")
  parents = vapply(ents, function(e) as.character(e$parent_id %||% NA_character_), "")
  index = if (is.environment(d$index)) d$index else emptyenv()
  at = function(id) {
    k = get0(id, envir = index, inherits = FALSE)
    if (is.numeric(k) && length(k) == 1L && k >= 1L && k <= length(ids) &&
        identical(ids[k], id)) {
      return(as.integer(k))
    }
    match(id, ids)
  }
  cur = d$leaf %||% ids[length(ids)]
  idx = integer()
  seen = logical(length(ents))
  while (length(cur) == 1L && !is.na(cur) && nzchar(cur)) {
    k = at(cur)
    if (is.na(k) || seen[k]) break
    seen[k] = TRUE
    idx = c(idx, k)
    cur = parents[k]
  }
  ents[rev(idx)]
}

#' The prompt turn of a user-message entry: P06's `gptr$turn` stamp, else counted
#' @noRd
doc_entry_turn = function(e, previous) {
  t = suppressWarnings(as.integer(e$gptr$turn %||% NA_integer_))
  if (!is.na(t)) return(t)
  src = e$message$source %||% "prompt"
  if (src %in% c("steer", "follow_up", "extension", "agent")) previous else previous + 1L
}

#' Entries of prompt turn `turn` on the active branch (from its first user message to the entry
#' before the next turn's first user message)
#' @noRd
doc_turn_entries = function(session, turn) {
  ents = doc_path_entries(session)
  start = NA_integer_
  end = length(ents)
  prev = 0L
  for (i in seq_along(ents)) {
    e = ents[[i]]
    if (!identical(e$type, "message") || !identical(e$message$role, "user")) next
    t = doc_entry_turn(e, prev)
    if (is.na(start) && identical(t, as.integer(turn))) start = i
    if (!is.na(start) && t > turn) {
      end = i - 1L
      break
    }
    prev = t
  }
  if (is.na(start)) return(list())
  ents[start:end]
}

#' Child sessions created during a turn (after the turn's first message), in creation order
#' (block-nested replay, IC-47)
#' @noRd
doc_turn_children = function(session, ents) {
  kids = session_data(session)$children
  if (!length(kids) || !length(ents)) return(list())
  first = ents[[1L]]$message$timestamp
  t0 = if (is.numeric(first)) first / 1000 - 0.001 else -Inf
  created = vapply(kids, function(k) as.numeric(session_data(k)$created %||% 0), 0)
  keep = which(created >= t0)
  kids[keep[order(created[keep], method = "radix")]]
}

#' S2 parts of the children a turn created (IC-47): the k-th direct gptr() call of the block body
#' (not inside a loop, function or braces) owns part "n<k>" and the first unused child whose first
#' prompt has that call's prompt hash; a computed or interpolated prompt takes the next unused
#' child that no literal call claims. Children of deeper calls get no part (those calls run live
#' on re-source). `sent` (the child's prompt hash) lets replay check the call it answers.
#' @noRd
doc_nested_parts = function(body, kids) {
  out = list()
  if (!length(kids) || !length(body)) return(out)
  calls = doc_calls(as.character(body))
  direct = calls[!calls$nested, , drop = FALSE]
  if (!nrow(direct)) return(out)
  sent = vapply(kids, function(k) {
    for (e in doc_path_entries(k)) {
      if (identical(e$type, "message") && identical(e$message$role, "user")) {
        return(prompt_hash(msg_text(e$message)))
      }
    }
    NA_character_
  }, "", USE.NAMES = FALSE)
  literal = direct$ph[!is.na(direct$ph)]
  used = logical(length(kids))
  for (k in seq_len(nrow(direct))) {
    ph = direct$ph[k]
    hit = if (is.na(ph)) integer() else which(!used & sent %in% ph)
    if (!length(hit)) hit = which(!used & !is.na(sent) & !(sent %in% literal))
    if (!length(hit)) next
    i = hit[1L]
    used[i] = TRUE
    cd = session_data(kids[[i]])
    out[[paste0("n", k)]] = list(text = cd$last_text %||% NA_character_, session = cd$id,
                                 model = cd$model, turn = cd$turns %||% 1L, sent = sent[i])
  }
  out
}

#' Body lines, recorded code, value, plan facts, last assistant message, tokens and cost of one
#' turn (tokens and cost are known only when every assistant message of the turn reports them,
#' IC-74: missing usage stays unknown)
#' @noRd
doc_turn_body = function(ents, with_out = TRUE, plan_mode = FALSE) {
  results = list()
  for (e in ents) {
    m = if (identical(e$type, "message")) e$message else NULL
    if (!is.null(m) && identical(m$role, "tool_result")) results[[m$tool_call_id]] = m
  }
  out = list(body = character(), code = character(), secrets = FALSE, value = NULL,
             plan_path = NULL, plan_from = NULL, last = NULL, tokens = c(0, 0),
             tokens_known = TRUE, cost = 0, cost_known = TRUE)
  for (i in seq_along(ents)) {
    e = ents[[i]]
    m = e$message
    if (identical(e$type, "custom_message") && identical(m$kind, "steer_relay")) {
      out$body = c(out$body, paste0("## Steer: ", doc_one_line(m$origin_text %||% "")))
    } else if (identical(e$type, "message") && identical(m$role, "user")) {
      for (blk in m$content) {
        if (identical(blk$type, "context") && identical(blk$kind, "plan")) {
          out$plan_from = blk$attrs$from %||% out$plan_from
        }
      }
      if (i == 1L) next
      src = m$source %||% "prompt"
      if (identical(src, "follow_up")) {
        out$body = c(out$body, paste0("## Follow-up: ", doc_one_line(msg_text(m))))
      } else if (identical(src, "steer")) {
        out$body = c(out$body, paste0("## Steer: ", doc_one_line(msg_text(m))))
      }
    } else if (identical(e$type, "message") && identical(m$role, "assistant")) {
      out = doc_turn_assistant(out, m, results, with_out, plan_mode)
    } else if (identical(e$type, "custom")) {
      ct = e$custom_type %||% ""
      if (identical(ct, "gptr.value") && !is.null(e$data$name) &&
          !identical(e$data$mode, "box")) {
        out$value = e$data$name
      }
      if (identical(ct, "gptr.plan")) out$plan_path = e$data$path %||% out$plan_path
    }
  }
  out
}

#' Add the usage of one assistant message to a turn body: an unknown (NA) or missing count makes
#' the turn's total unknown (IC-74)
#' @noRd
doc_turn_usage = function(out, u) {
  known = is.list(u) && !is.null(u[["input"]]) && !is.null(u[["output"]])
  tin = NA_real_
  tout = NA_real_
  if (known) {
    tin = unlist(u[c("input", "cache_read", "cache_write_5m", "cache_write_1h")], use.names = FALSE)
    tout = u[["output"]]
  }
  if (!known || !is.numeric(tin) || !is.numeric(tout) || anyNA(c(tin, tout))) {
    out$tokens_known = FALSE
  } else {
    out$tokens = out$tokens + c(sum(tin), sum(tout))
  }
  cost = if (is.list(u) && is.list(u[["cost"]])) u[["cost"]][["total"]] else NULL
  if (!is.numeric(cost) || length(cost) != 1L || is.na(cost)) {
    out$cost_known = FALSE
  } else {
    out$cost = out$cost + cost
  }
  out
}

#' Add one assistant message (its successful recorded r calls) to a turn body. When every
#' expression of a call was dropped, all its printed output belongs to dropped expressions and is
#' dropped too, even from P10's flat output vector (IC-48)
#' @noRd
doc_turn_assistant = function(out, m, results, with_out, plan_mode) {
  out$last = m
  out = doc_turn_usage(out, m$usage)
  for (b in m$content) {
    if (!identical(b$type, "tool_call") || !identical(b$name, "r")) next
    res = results[[b$id]]
    if (is.null(res) || isTRUE(res$is_error)) next
    det = res$details %||% list()
    if (!identical(det$status %||% "ok", "ok")) next
    if (!is.null(det$value)) out$value = det$value
    if (plan_mode || isFALSE(det$record) || isFALSE(b$arguments$record)) next
    chunk = doc_code_clean(det$code %||% b$arguments$code %||% "")
    kept = attr(chunk, "kept")
    chunk = as.character(chunk)
    safe = doc_history_code(chunk)
    hist = safe$lines
    if (safe$secrets) out$secrets = TRUE
    outs = det$outputs
    if (!length(chunk)) {
      outs = NULL
    } else if (is.list(outs) && length(kept) && length(outs) == length(kept)) {
      outs = outs[kept]
    }
    lines = hist
    if (with_out) lines = c(lines, doc_output_lines(outs))
    if (length(det$bridge)) {
      dig = as_utf8(as.character(det$bridge))
      lines = c(lines, ifelse(startsWith(dig, "#>"), dig, paste0("#> ", dig)))
    }
    if (length(det$artifacts)) {
      art = as_utf8(as.character(det$artifacts))
      tag = ifelse(basename(art) == "app.R", "#> [app] ", "#> [plot] ")
      lines = c(lines, paste0(tag, art))
    }
    note = det$note %||% b$arguments$note
    if (length(note) && nzchar(doc_one_line(note))) {
      lines = c(lines, paste0("## Decision: ", doc_one_line(note)))
    }
    out$body = c(out$body, lines)
    out$code = c(out$code, hist)
  }
  out
}

#' Recorded code of every turn of a (child) session, without outputs or comment lines (team
#' blocks); attribute `secrets` when a marker stays in it
#' @noRd
doc_session_code = function(session) {
  d = session_data(session)
  code = character()
  secrets = FALSE
  for (k in seq_len(d$turns %||% 0L)) {
    tb = doc_turn_body(doc_turn_entries(session, k), with_out = FALSE,
                       plan_mode = identical(d$mode, "plan"))
    code = c(code, tb$code)
    secrets = secrets || tb$secrets
  }
  structure(code, secrets = secrets)
}

#' Header facts common to every block
#' @noRd
doc_header_common = function(site, call_ordinal, model) {
  list(model = model, date = format(Sys.Date(), "%Y-%m-%d"),
       prompt = site$prompt_hash %||% prompt_hash(site$template %||% ""),
       call = if (isTRUE(call_ordinal > 1L)) as.integer(call_ordinal) else NULL,
       args = site$args_hash)
}

#' The lines of the block of a session turn (contract 7.15): chr with attributes `header` (named
#' list of 11.5 keys), `session`, `answer` (final text) and `children` (S2 parts to cache). The
#' header's `model` is the provider and model of the turn's last answer as recorded, so a local
#' model keeps its tag (IC-74).
#' @noRd
doc_block_lines = function(session, turn, site, call_ordinal) {
  d = session_data(session)
  if (d$kind %in% c("team", "fanout")) return(doc_team_block_lines(session, site, call_ordinal))
  ents = doc_turn_entries(session, turn)
  fmt = site$format %||% "r"
  doc_set = tryCatch(setting_get("doc", default = list()), error = function(e) list())
  with_out = !fmt %in% c("rmd", "qmd") && !isFALSE(if (is.list(doc_set)) doc_set$outputs)
  plan_mode = identical(d$mode, "plan")
  tb = doc_turn_body(ents, with_out = with_out, plan_mode = plan_mode)
  body = tb$body
  if (plan_mode) body = paste0("## Plan: ", tb$plan_path %||% "none")
  if (tb$secrets) body = c(doc_secret_flag, body)
  fork = NULL
  if (!is.null(d$fork_of)) {
    fork = paste0(d$fork_of$id, ":", d$fork_of$turn %||% 0L)
    if (startsWith(d$home_label %||% "", "overlay of")) body = doc_wrap_local(body)
  }
  body = redact(body, "persist")
  last = tb$last
  model = if (!is.null(last)) paste0(last$provider, "/", last$model) else d$model
  header = doc_header_common(site, call_ordinal, model)
  if (tb$tokens_known && any(tb$tokens > 0)) {
    header$tokens = sprintf("%.0f/%.0f", tb$tokens[1L], tb$tokens[2L])
  }
  if (tb$cost_known && tb$cost > 0) header$cost = format(round(tb$cost, 4L), scientific = FALSE)
  header$session = d$id
  header$turn = as.integer(turn)
  header$value = tb$value
  header$fork = fork
  header$plan = tb$plan_from
  children = doc_nested_parts(body, doc_turn_children(session, ents))
  answer = if (!is.null(last)) msg_text(last) else NA_character_
  structure(as.character(body), header = header, session = session, answer = answer,
            children = children)
}

#' The lines of a team or fan-out block (IC-47): one `## Agent` line per child in name order;
#' children with exports get their code in a child overlay plus one assignment per export
#' @noRd
doc_team_block_lines = function(team, site, call_ordinal) {
  d = session_data(team)
  kids = d$children
  nms = sort(names(kids), method = "radix")
  body = character()
  children = list()
  ids = character()
  secrets = FALSE
  for (nm in nms) {
    cd = session_data(kids[[nm]])
    txt = cd$last_text
    txt = if (length(txt) && !is.na(txt[1L])) {
      as_utf8(paste(txt, collapse = "\n"))
    } else {
      NA_character_
    }
    first = if (is.na(txt) || !nzchar(txt)) "" else strsplit(txt, "\n", fixed = TRUE)[[1L]][1L]
    body = c(body, sub("[ \t]+$", "", paste0("## Agent ", nm, " (", cd$model, "): ",
                                             doc_one_line(first))))
    exports = as.character(cd$exports %||% character())
    if (length(exports)) {
      code = doc_session_code(kids[[nm]])
      secrets = secrets || isTRUE(attr(code, "secrets"))
      body = c(body, doc_wrap_local(as.character(code), child = nm))
      body = c(body, paste0(exports, " = gptr_resume(block = \"", doc_block_token,
                            "\", child = ", doc_str_literal(nm), ")$envir$", exports))
    }
    children[[nm]] = list(text = txt, session = cd$id, model = cd$model,
                          turn = cd$turns %||% 1L)
    ids = c(ids, cd$id)
  }
  if (secrets) body = c(doc_secret_flag, body)
  model = if (length(nms)) session_data(kids[[nms[1L]]])$model else d$model
  header = doc_header_common(site, call_ordinal, model)
  header$session = d$id
  header$turn = 1L
  header$kind = d$kind
  header$children = paste0(nms, ":", ids, collapse = ",")
  structure(as.character(redact(body, "persist")), header = header, session = team,
            answer = d$last_text %||% NA_character_, children = children)
}
