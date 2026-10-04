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
