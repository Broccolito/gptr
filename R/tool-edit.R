# The `edit` tool and `gptr$edit()` (P10; research 11 section 5.5, research 01 sections 2.5, 3.4):
# Pi's all-or-nothing multi-edit, the fuzzy fallback that rewrites only touched lines, other bytes
# kept exactly, `replace_all`, and Codex `*** Begin Patch` envelopes. Occurrences are counted in
# fuzzy space as in Pi; patch paths are compared by the file system, never by spelling.

#' Pi normalizeForFuzzyMatch() applied line by line (the line structure is unchanged). Every class
#' pattern starts with (*UTF) so it compiles on all-ASCII input (report 11 P5)
#' @noRd
fuzzy_normalize_lines = function(x) {
  x = utf8_mark(x)
  if (requireNamespace("stringi", quietly = TRUE)) x = stringi::stri_trans_nfkc(x)
  x = sub("(*UTF)[\\h\\v\\x{FEFF}]+$", "", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{2018}\\x{2019}\\x{201A}\\x{201B}]", "'", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{201C}\\x{201D}\\x{201E}\\x{201F}]", "\"", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{2010}-\\x{2015}\\x{2212}]", "-", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{00A0}\\x{2002}-\\x{200A}\\x{202F}\\x{205F}\\x{3000}]", " ", x, perl = TRUE)
  utf8_mark(x)
}

#' Fuzzy normalisation of a whole text
#' @noRd
fuzzy_normalize = function(text) {
  utf8_mark(paste(fuzzy_normalize_lines(split_lines_js(text)), collapse = "\n"))
}

#' All non-overlapping occurrences (0-based byte offsets) of a fixed string, leftmost first
#' strsplit() is linear in the matches (gregexpr(fixed = TRUE) is quadratic); the byte count
#' detects a match at the very end. An empty needle occurs nowhere.
#' @noRd
fixed_positions = function(haystack, needle) {
  if (!nzchar(needle)) return(integer(0))
  pieces = strsplit(haystack, needle, fixed = TRUE, useBytes = TRUE)[[1L]]
  len = nchar(needle, type = "bytes")
  pb = nchar(pieces, type = "bytes")
  n = length(pieces) - 1L
  if (sum(pb) + max(n, 0L) * len < nchar(haystack, type = "bytes")) n = n + 1L
  if (n < 1L) return(integer(0))
  as.integer(cumsum(pb[seq_len(n)]) + (seq_len(n) - 1L) * len)
}

#' Splice replacements (0-based start, byte length, new text) into a string, working on raw bytes
#' @noRd
splice_bytes = function(x, start, len, new) {
  if (!length(start)) return(x)
  o = order(start)
  start = start[o]
  len = len[o]
  new = new[o]
  b = charToRaw(x)
  pieces = vector("list", 2L * length(start) + 1L)
  pos = 0
  for (i in seq_along(start)) {
    pieces[[2L * i - 1L]] = if (start[i] > pos) b[(pos + 1):start[i]] else raw(0)
    pieces[[2L * i]] = charToRaw(new[i])
    pos = start[i] + len[i]
  }
  pieces[[length(pieces)]] = if (pos < length(b)) b[(pos + 1):length(b)] else raw(0)
  rawToChar(unlist(pieces))
}

#' Signal an edit error with Pi's single-edit or multi-edit wording (`i` is 1-based, shown 0-based)
#' @noRd
edit_error = function(single, multi, path, i, n) {
  msg = if (n == 1L) sprintf(single, path) else sprintf(multi, i - 1L, path)
  gptr_abort(msg, "invalid_argument", arg = "edits", expected = "edits that match the file")
}

#' Apply edits to decoded text (a string without BOM; unmarked bytes when it is lossy UTF-8)
#' Returns `list(text, base_old, base_new, fuzzy, counts, eol_changed)`; `base_old`/`base_new` are
#' the LF views for the diff (CRLF read as LF, a lone CR kept in both).
#' @noRd
apply_edits = function(text, edits, path = "file", replace_all = FALSE) {
  n = length(edits)
  if (!n) {
    gptr_abort("Edit tool input is invalid. edits must contain at least one replacement.",
               "invalid_argument", arg = "edits", expected = "at least one replacement")
  }
  pieces = strsplit(paste0(text, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  k = length(pieces)
  has_cr = grepl("\r$", pieces, perl = TRUE, useBytes = TRUE) & seq_len(k) < k
  lossy = !validUTF8(text)
  remark = function(x) if (lossy) x else utf8_mark(x)
  body = pieces
  body[has_cr] = sub("\r$", "", pieces[has_cr], perl = TRUE, useBytes = TRUE)
  body = remark(body)
  base = remark(paste(body, collapse = "\n"))
  eol = detect_eol(text)
  field = function(e, a, b) as_utf8(e[[a]] %||% e[[b]] %||% "")
  olds = normalize_lf(vapply(edits, field, "", "oldText", "old_text"))
  news = normalize_lf(vapply(edits, field, "", "newText", "new_text"))
  each_all = function(e) isTRUE(e$replaceAll %||% e$replace_all)
  all_ = isTRUE(replace_all) | vapply(edits, each_all, NA)
  for (i in seq_len(n)) {
    if (!nzchar(olds[i])) {
      edit_error("oldText must not be empty in %s.",
                 "edits[%d].oldText must not be empty in %s.", path, i, n)
    }
  }
  pos = lapply(olds, function(o) fixed_positions(base, o))
  space = base
  olds_space = olds
  fz_lines = NULL
  used_fuzzy = FALSE
  if (any(lengths(pos) == 0L) && !lossy) {
    fz_lines = fuzzy_normalize_lines(body)
    space = utf8_mark(paste(fz_lines, collapse = "\n"))
    in_space = function(o) if (length(fixed_positions(space, o))) o else fuzzy_normalize(o)
    olds_space = vapply(olds, in_space, "")
    pos = lapply(olds_space, function(o) fixed_positions(space, o))
    used_fuzzy = TRUE
  }
  fz_base = if (used_fuzzy) space else NULL
  starts = integer(0)
  lens = integer(0)
  repl = character(0)
  owner = integer(0)
  counts = integer(n)
  for (i in seq_len(n)) {
    p = pos[[i]]
    if (!length(p)) {
      edit_error(paste("Could not find the exact text in %s. The old text must match exactly",
                       "including all whitespace and newlines."),
                 paste("Could not find edits[%d] in %s. The oldText must match exactly",
                       "including all whitespace and newlines."), path, i, n)
    }
    if (!all_[i]) {
      occ = length(p)
      if (!lossy) {
        if (is.null(fz_base)) {
          fz_base = utf8_mark(paste(fuzzy_normalize_lines(body), collapse = "\n"))
        }
        occ = max(occ, length(fixed_positions(fz_base, fuzzy_normalize(olds[i]))))
      }
      if (occ > 1L) {
        msg = if (n == 1L) {
          paste0("Found ", occ, " occurrences of the text in ", path,
                 ". The text must be unique. Please provide more context to make it unique.")
        } else {
          paste0("Found ", occ, " occurrences of edits[", i - 1L, "] in ", path,
                 ". Each oldText must be unique. Please provide more context to make it unique.")
        }
        gptr_abort(msg, "invalid_argument", arg = "edits", expected = "a unique oldText")
      }
      p = p[1L]
    }
    counts[i] = length(p)
    starts = c(starts, p)
    lens = c(lens, rep(nchar(olds_space[i], type = "bytes"), length(p)))
    repl = c(repl, rep(news[i], length(p)))
    owner = c(owner, rep(i, length(p)))
  }
  o = order(starts)
  starts = starts[o]
  lens = lens[o]
  repl = repl[o]
  owner = owner[o]
  ov = which(starts[-1L] < (starts + lens)[-length(starts)])
  if (length(ov)) {
    gptr_abort(paste0("edits[", owner[ov[1L]] - 1L, "] and edits[", owner[ov[1L] + 1L] - 1L,
                      "] overlap in ", path,
                      ". Merge them into one edit or target disjoint regions."),
               "invalid_argument", arg = "edits", expected = "non-overlapping edits")
  }
  new_text = if (!used_fuzzy) {
    edit_splice_exact(text, body, has_cr, k, eol, starts, lens, repl)
  } else {
    edit_splice_fuzzy(body, fz_lines, has_cr, k, eol, starts, lens, repl)
  }
  new_text = remark(new_text)
  if (identical(new_text, text)) {
    msg = if (n == 1L) {
      paste0("No changes made to ", path, ". The replacement produced identical content. ",
             "This might indicate an issue with special characters or the text not existing ",
             "as expected.")
    } else {
      paste0("No changes made to ", path, ". The replacements produced identical content.")
    }
    gptr_abort(msg, "invalid_argument", arg = "edits", expected = "edits that change the file")
  }
  eol_changed = identical(eol, "\r\n") && any(grepl("\n", news, fixed = TRUE))
  base_new = remark(gsub("\r\n", "\n", new_text, fixed = TRUE, useBytes = TRUE))
  list(text = new_text, base_old = base, base_new = base_new, fuzzy = used_fuzzy, counts = counts,
       eol_changed = eol_changed)
}

#' Exact path: map offsets of the LF view to the original by adding one byte per CRLF before them,
#' then splice on the raw bytes; newText takes the file's line ending (Pi detectLineEnding())
#' @noRd
edit_splice_exact = function(text, body, has_cr, k, eol, starts, lens, repl) {
  nl_base = cumsum(nchar(body, type = "bytes") + 1L)[seq_len(k - 1L)] - 1L
  crs = cumsum(has_cr[seq_len(k - 1L)])
  shift = function(off) {
    j = findInterval(off, nl_base, left.open = TRUE)
    ifelse(j > 0L, crs[pmax(1L, j)], 0L)
  }
  o_start = starts + shift(starts)
  o_end = (starts + lens) + shift(starts + lens)
  repl_eol = if (eol == "\r\n") gsub("\n", "\r\n", repl, fixed = TRUE, useBytes = TRUE) else repl
  splice_bytes(text, o_start, o_end - o_start, repl_eol)
}

#' Fuzzy path (Pi applyReplacementsPreservingUnchangedLines()): lines carry their terminators,
#' touched line groups are rewritten from the fuzzy view, every other line keeps its original bytes
#' @noRd
edit_splice_fuzzy = function(body, fz_lines, has_cr, k, eol, starts, lens, repl) {
  term = ifelse(seq_len(k) < k, "\n", "")
  fz_with = paste0(fz_lines, term)
  orig_with = paste0(body, ifelse(has_cr, "\r\n", term))
  line_start = c(0, cumsum(nchar(fz_with, type = "bytes")))[seq_len(k)]
  s_line = findInterval(starts, line_start)
  e_line = findInterval(starts + lens - 1L, line_start)
  grp = cumsum(c(TRUE, s_line[-1L] > cummax(e_line)[-length(e_line)]))
  g_s = tapply(s_line, grp, min)
  g_e = tapply(e_line, grp, max)
  out = character(0)
  cur = 1L
  for (g in seq_along(g_s)) {
    if (g_s[g] > cur) out = c(out, orig_with[cur:(g_s[g] - 1L)])
    seg = paste(fz_with[g_s[g]:g_e[g]], collapse = "")
    sel = grp == g
    seg = splice_bytes(seg, starts[sel] - line_start[g_s[g]], lens[sel], repl[sel])
    if (eol == "\r\n") seg = gsub("\n", "\r\n", seg, fixed = TRUE, useBytes = TRUE)
    out = c(out, seg)
    cur = g_e[g] + 1L
  }
  if (cur <= k) out = c(out, orig_with[cur:k])
  paste(out, collapse = "")
}

#' Pi prepareEditArguments(): edits as a JSON string, a single object, a data frame or a list
#' json_decode(), never jsonlite::fromJSON(), which reads a non-JSON string as a file or URL; every
#' present `oldText`/`newText` (or `old_text`/`new_text`) must be one string.
#' @noRd
edit_normalize_args = function(edits) {
  if (is.character(edits) && length(edits) == 1L && !patch_is_envelope(edits)) {
    parsed = tryCatch(json_decode(edits), error = function(e) NULL)
    if (!is.null(parsed)) edits = parsed
  }
  if (is.data.frame(edits)) {
    unfactor = function(v) if (is.factor(v)) as.character(v) else v
    row_edit = function(i) lapply(as.list(edits[i, , drop = FALSE]), unfactor)
    edits = lapply(seq_len(nrow(edits)), row_edit)
  }
  single = is.list(edits) && !is.null(names(edits))
  if (single && !is.null(edits[["oldText"]] %||% edits[["old_text"]])) edits = list(edits)
  if (!is.list(edits) || !length(edits) || !all(vapply(edits, is.list, NA))) {
    gptr_abort("Edit tool input is invalid. edits must contain at least one replacement.",
               "invalid_argument", arg = "edits", expected = "a list of list(oldText =, newText =)")
  }
  for (i in seq_along(edits)) {
    for (f in c("oldText", "old_text", "newText", "new_text")) {
      v = edits[[i]][[f]]
      if (!is.null(v) && !(is.character(v) && length(v) == 1L && !is.na(v))) {
        msg = paste0("Edit tool input is invalid. edits[", i - 1L, "].", f, " must be a string.")
        gptr_abort(msg, "invalid_argument", arg = "edits", expected = "string oldText and newText")
      }
    }
  }
  edits
}

#' Load a file for editing: checks (Pi's texts), the link target, the decoding and the text that
#' apply_edits() works on (unmarked bytes when the file is lossy UTF-8)
#' @noRd
edit_source = function(abs, path) {
  p = fs_path(abs)
  code = if (!file.exists(p)) "ENOENT" else if (dir.exists(p)) "EISDIR" else NULL
  if (!is.null(code)) {
    gptr_abort(paste0("Could not edit file: ", path, ". Error code: ", code, "."),
               "invalid_argument", arg = "path", expected = "an existing file")
  }
  target = resolve_link_target(abs)
  if (file.access(fs_path(target), 2L) != 0L || file.access(fs_path(target), 4L) != 0L) {
    gptr_abort(paste0("Could not edit file: ", path, ". Error code: EACCES."), "invalid_argument",
               arg = "path", expected = "a readable and writable file")
  }
  b = read_raw(target)
  # A NUL anywhere makes a file without a UTF-16/32 BOM binary (a UTF-8 BOM is no exemption)
  if (is_binary_raw(b) || (any(b == as.raw(0L)) && sniff_bom(b) %in% c("", "UTF-8"))) {
    gptr_abort(paste0("Could not edit file: ", path, ". It is a binary file."), "invalid_argument",
               arg = "path", expected = "a text file")
  }
  d = decode_raw(b)
  text = if (d$lossy) {
    t = rawToChar(if (d$bom) b[-(1:3)] else b)
    Encoding(t) = "unknown"
    t
  } else {
    d$text
  }
  list(target = target, dec = d, text = text)
}

#' Compute an edit without writing: the target, the new bytes, the apply_edits() result and the
#' decoding (`src`: an edit_source() already loaded)
#' @noRd
edit_compute = function(abs, path, edits, replace_all = FALSE, src = edit_source(abs, path)) {
  d = src$dec
  res = apply_edits(src$text, edits, path, replace_all = replace_all)
  bytes = if (d$lossy) {
    c(if (d$bom) bom_bytes[["UTF-8"]], charToRaw(res$text))
  } else {
    encode_text(res$text, d$encoding, d$bom)
  }
  list(target = src$target, bytes = bytes, res = res, dec = d)
}

#' Text of a computed edit for a diff: invalid bytes of a lossy file shown as U+FFFD
#' @noRd
edit_view = function(cp, x) {
  if (cp$dec$lossy) utf8_mark(iconv(x, "UTF-8", "UTF-8", sub = replacement_sub)) else x
}

#' Why a computed edit deviates from the literal request (none: character())
#' @noRd
edit_reasons = function(cp) {
  enc = cp$dec$encoding
  c(if (cp$res$fuzzy) "matched after whitespace, quote or dash normalisation",
    if (cp$res$eol_changed) "line endings written as CRLF",
    if (!identical(enc, "UTF-8")) paste0("file re-encoded as ", enc),
    if (isTRUE(cp$dec$lossy)) "invalid UTF-8 bytes kept")
}

#' Edit a file: the `edit` tool (contract section 7.10)
#' `edits`: a list of `list(oldText =, newText =)` (or snake case, per-edit `replaceAll`), a JSON
#' string, one object or a `*** Begin Patch` envelope; `diff` is capped at 400 tokens.
#' @noRd
edit_file = function(path, edits, replace_all = FALSE) {
  check_string(path, "path")
  check_flag(replace_all, "replace_all")
  envelope = edit_envelope_of(edits)
  if (!is.null(envelope)) return(edit_from_patch(envelope))
  edits = edit_normalize_args(edits)
  abs = resolve_tool_path(path)
  cp = edit_compute(abs, path, edits, replace_all)
  write_bytes_keep_mode(cp$target, cp$bytes)
  res = cp$res
  old = edit_view(cp, res$base_old)
  new = edit_view(cp, res$base_new)
  reasons = edit_reasons(cp)
  list(message = paste0("Successfully replaced ", sum(res$counts), " block(s) in ", path, "."),
       diff = diff_lines(diff_split(old)$lines, diff_split(new)$lines, context = 3L,
                         max_tokens = 400L),
       fuzzy = res$fuzzy,
       details = list(path = cp$target, n_edits = length(edits), fuzzy = res$fuzzy,
                      diff = diff_unified(path, old, new), document = FALSE,
                      deviated = length(reasons) > 0L, reasons = reasons,
                      encoding = cp$dec$encoding))
}

#' Model-facing text of an edit: Pi's message, plus the reasons and the diff only when something
#' deviated from the literal request (contract sections 7.10 and 9.2)
#' @noRd
edit_result_text = function(ed) {
  if (!isTRUE(ed$details$deviated) || !length(ed$diff)) return(ed$message)
  reasons = paste0("[", paste(ed$details$reasons, collapse = "; "), "]")
  paste(c(ed$message, reasons, ed$diff), collapse = "\n")
}

#' Is `x` a pasted `*** Begin Patch` envelope (a string, or a one-element unnamed list of one)?
#' @noRd
patch_is_envelope = function(x) {
  if (is.list(x) && length(x) == 1L && is.null(names(x))) x = x[[1L]]
  is.character(x) && length(x) == 1L && !is.na(x) &&
    grepl("^\\s*\\*\\*\\* Begin Patch", x, perl = TRUE)
}

#' The patch envelope carried by an edit's arguments, or NULL
#' `edits` itself, or the only edit's `newText` (or `oldText`) when the other text is empty; after
#' Pi's shim, so an envelope in a JSON string, an object or a data frame is found too.
#' @noRd
edit_envelope_of = function(edits) {
  if (patch_is_envelope(edits)) return(if (is.list(edits)) edits[[1L]] else edits)
  norm = tryCatch(edit_normalize_args(edits), error = function(e) NULL)
  if (!is.null(norm)) edits = norm
  if (!is.list(edits) || length(edits) != 1L || !is.list(edits[[1L]])) return(NULL)
  e = edits[[1L]]
  pairs = list(c("newText", "oldText"), c("oldText", "newText"), c("new_text", "old_text"),
               c("old_text", "new_text"))
  for (p in pairs) {
    env = e[[p[1L]]]
    other = e[[p[2L]]]
    if (patch_is_envelope(env) && (is.null(other) || identical(other, ""))) {
      return(if (is.list(env)) env[[1L]] else env)
    }
  }
  NULL
}

#' The input of a nested `gptr$edit()` call for the gate: a patch envelope travels as `patch`, with
#' an empty `edits` array, so the input validates against the edit schema
#' @noRd
edit_nested_input = function(input) {
  envelope = edit_envelope_of(input$edits)
  if (is.null(envelope)) return(input)
  input$edits = list()
  input$patch = envelope
  input
}

#' Parse a Codex-style patch envelope into file operations
#' As in Codex, update lines start with " ", "-" or "+" (an empty line is empty context), and an
#' `*** Update File` needs at least one hunk.
#' @noRd
patch_parse = function(envelope) {
  lines = split_lines_count(normalize_lf(as_utf8(envelope)))
  marks = trimws(lines)
  bad = function(what) {
    gptr_abort(paste0("Invalid patch: ", what), "invalid_argument", arg = "edits",
               expected = "a *** Begin Patch envelope")
  }
  i = which(marks == "*** Begin Patch")[1L]
  if (is.na(i)) bad("missing '*** Begin Patch'.")
  j = which(marks == "*** End Patch")
  j = j[j > i][1L]
  if (is.na(j)) bad("missing '*** End Patch'.")
  body = if (j > i + 1L) lines[(i + 1L):(j - 1L)] else character()
  ops = list()
  cur = NULL
  add_op = function(ops, cur) {
    if (is.null(cur)) return(ops)
    if (identical(cur$op, "update") && !length(cur$hunks)) {
      bad(paste0("the update of ", cur$path, " has no hunks."))
    }
    c(ops, list(cur))
  }
  for (ln in body) {
    header = regmatches(ln, regexec("^\\*\\*\\* (Add|Delete|Update) File: (.+)$", ln))[[1L]]
    if (length(header)) {
      ops = add_op(ops, cur)
      cur = list(op = tolower(header[2L]), path = trimws(header[3L]), content = character(),
                 move_to = NULL, hunks = list())
    } else if (startsWith(ln, "*** Move to: ") && identical(cur$op, "update")) {
      cur$move_to = trimws(substring(ln, 14L))
    } else if (startsWith(ln, "*** End of File")) {
      next
    } else if (identical(cur$op, "add")) {
      if (!startsWith(ln, "+")) {
        bad(paste0("a line of the added file ", cur$path, " does not start with '+'."))
      }
      cur$content = c(cur$content, substring(ln, 2L))
    } else if (identical(cur$op, "update")) {
      if (startsWith(ln, "@@")) {
        cur$hunks[[length(cur$hunks) + 1L]] = list(old = character(), new = character())
        next
      }
      tag = substr(ln, 1L, 1L)
      if (!tag %in% c(" ", "-", "+", "")) {
        bad(paste0("a line of the update of ", cur$path, " does not start with ' ', '-' or '+': '",
                   substr(ln, 1L, 60L), "'."))
      }
      if (!length(cur$hunks)) cur$hunks[[1L]] = list(old = character(), new = character())
      h = length(cur$hunks)
      txt = substring(ln, 2L)
      if (tag != "+") cur$hunks[[h]]$old = c(cur$hunks[[h]]$old, txt)
      if (tag != "-") cur$hunks[[h]]$new = c(cur$hunks[[h]]$new, txt)
    } else if (nzchar(trimws(ln))) {
      bad(paste0("unexpected line '", substr(ln, 1L, 60L), "'."))
    }
  }
  add_op(ops, cur)
}

#' File paths an envelope touches (for the risk of the edit tool)
#' @noRd
patch_paths = function(envelope) {
  ops = tryCatch(patch_parse(envelope), error = function(e) list())
  unique(c(vapply(ops, function(o) o$path, ""), unlist(lapply(ops, function(o) o$move_to))))
}

#' Does a block of whole lines occur in a text (the LF view or its fuzzy normalisation)?
#' "after": it starts a line and a line ending follows; "before": it ends a text without a final
#' newline, after a line ending; NA: neither.
#' @noRd
patch_line_end = function(hay, block) {
  if (length(fixed_positions(paste0("\n", hay), paste0("\n", block, "\n")))) return("after")
  tail = charToRaw(paste0("\n", block))
  hb = charToRaw(hay)
  n = length(tail)
  if (length(hb) >= n && identical(hb[(length(hb) - n + 1L):length(hb)], tail)) return("before")
  NA_character_
}

#' The edits of an `*** Update File` operation: one per `@@` hunk, its old and new lines joined
#' A removal-only hunk also removes a line ending: the one after it, or the one before it at the end
#' of a file without a final newline (then a fuzzy match takes the file's own last lines).
#' @noRd
patch_hunk_edits = function(op, text) {
  lf = gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
  fz = NULL
  out = vector("list", length(op$hunks))
  for (k in seq_along(op$hunks)) {
    h = op$hunks[[k]]
    if (!length(h$old)) {
      gptr_abort(paste0("Invalid patch: a hunk of ", op$path, " has no context or removed lines."),
                 "invalid_argument", arg = "edits", expected = "hunks with context")
    }
    old = paste(h$old, collapse = "\n")
    if (!length(h$new)) {
      end = patch_line_end(lf, old)
      if (is.na(end) && validUTF8(lf)) {
        if (is.null(fz)) fz = fuzzy_normalize(lf)
        end = patch_line_end(fz, fuzzy_normalize(old))
        if (identical(end, "before")) {
          ln = split_lines_js(lf)
          old = paste(ln[(length(ln) - length(h$old) + 1L):length(ln)], collapse = "\n")
        }
      }
      if (identical(end, "after")) old = paste0(old, "\n")
      if (identical(end, "before")) old = paste0("\n", old)
    }
    out[[k]] = list(oldText = old, newText = paste(h$new, collapse = "\n"))
  }
  out
}

#' Remove a file named by a patch (a link is removed, not its target); a failure is an error. The
#' name is never a pattern: unlink() expands "*", "?" and "[...]" unless `expand = FALSE`.
#' @noRd
patch_remove = function(abs, path) {
  p = fs_path(abs)
  unlink(p, expand = FALSE)
  link = Sys.readlink(p)
  if (file.exists(p) || (!is.na(link) && nzchar(link))) {
    gptr_abort(paste0("Could not delete file: ", path, "."), "doc_write", path = abs,
               reason = "remove")
  }
  invisible(NULL)
}

#' The file a patch path names, as a key for finding two operations on one file
#' Links followed and the existing part resolved by the file system; on a case-insensitive file
#' system the key is folded (Unicode case and NFC with stringi, ASCII case without).
#' @noRd
patch_key = function(p, fold) {
  t = resolve_link_target(p)
  k = if (file.exists(fs_path(t))) {
    as_utf8(normalizePath(fs_path(t), winslash = "/", mustWork = FALSE))
  } else {
    tool_path_physical(t)
  }
  if (!fold) return(k)
  if (requireNamespace("stringi", quietly = TRUE)) {
    return(utf8_mark(stringi::stri_trans_nfc(stringi::stri_trans_tolower(k, locale = "en"))))
  }
  chartr(paste(LETTERS, collapse = ""), paste(letters, collapse = ""), k)
}

#' Finish a move once its new name holds `bytes`: remove the old name unless it is that entry
#' An old name (not a link) that reads as `bytes` is the new name under folding or a directory
#' link: it is renamed to the new spelling, so a move never deletes the file it wrote.
#' @noRd
patch_finish_move = function(old, new, bytes, path) {
  p = fs_path(old)
  link = Sys.readlink(p)
  if (is.na(link) || !nzchar(link)) {
    now = tryCatch(read_raw(old), error = function(e) NULL)
    if (identical(now, bytes)) {
      suppressWarnings(file.rename(p, fs_path(new)))
      return(invisible(NULL))
    }
  }
  patch_remove(old, path)
}

#' Apply a Codex-style patch envelope, relative paths against `root` (contract section 7.10)
#' Every operation is computed against the files as they were and nothing is written unless all
#' succeed, so a file named by two operations (patch_key()) is refused.
#' @noRd
patch_apply = function(envelope, root = project_root()) {
  check_string(envelope, "envelope")
  check_string(root, "root")
  ops = patch_parse(envelope)
  if (!length(ops)) {
    gptr_abort("Invalid patch: no file operations.", "invalid_argument", arg = "edits",
               expected = "a *** Begin Patch envelope")
  }
  resolve = function(p) resolve_tool_path(p, cwd = root)
  fold = fs_case_insensitive(root)
  keys = character()
  for (n in seq_along(ops)) {
    ops[[n]]$abs = resolve(ops[[n]]$path)
    if (!is.null(ops[[n]]$move_to)) ops[[n]]$move = resolve(ops[[n]]$move_to)
    k = unique(vapply(c(ops[[n]]$abs, ops[[n]]$move), patch_key, "", fold = fold,
                      USE.NAMES = FALSE))
    d = k[k %in% keys]
    if (length(d)) {
      gptr_abort(paste0("Invalid patch: more than one operation names ",
                        c(ops[[n]]$path, ops[[n]]$move_to)[match(d[1L], k)],
                        "; put all hunks of a file under one *** Update File."),
                 "invalid_argument", arg = "edits", expected = "one operation per file")
    }
    keys = c(keys, k)
  }
  plan = lapply(ops, function(op) {
    abs = op$abs
    p = fs_path(abs)
    if (identical(op$op, "add")) {
      if (file.exists(p)) {
        gptr_abort(paste0("Invalid patch: the file to add already exists: ", op$path),
                   "invalid_argument", arg = "edits", expected = "a new file path")
      }
      text = if (length(op$content)) paste0(paste(op$content, collapse = "\n"), "\n") else ""
      return(list(op = op, abs = abs, bytes = encode_text(text)))
    }
    if (identical(op$op, "delete")) {
      code = if (!file.exists(p)) "ENOENT" else if (dir.exists(p)) "EISDIR" else NULL
      if (!is.null(code)) {
        gptr_abort(paste0("Could not delete file: ", op$path, ". Error code: ", code, "."),
                   "invalid_argument", arg = "edits", expected = "an existing file")
      }
      return(list(op = op, abs = abs))
    }
    if (!is.null(op$move) && dir.exists(fs_path(op$move))) {
      gptr_abort(paste0("Could not move file: ", op$path, " to ", op$move_to,
                        ". Error code: EISDIR."), "invalid_argument", arg = "edits",
                 expected = "a file path to move to")
    }
    src = edit_source(abs, op$path)
    cp = edit_compute(abs, op$path, patch_hunk_edits(op, src$text), src = src)
    list(op = op, abs = abs, cp = cp, move = op$move)
  })
  diffs = character()
  tags = character()
  fuzzy = FALSE
  reasons = character()
  for (pl in plan) {
    if (identical(pl$op$op, "add")) {
      write_bytes_keep_mode(pl$abs, pl$bytes)
      tags = c(tags, paste0("A ", pl$op$path))
    } else if (identical(pl$op$op, "delete")) {
      patch_remove(pl$abs, pl$op$path)
      tags = c(tags, paste0("D ", pl$op$path))
    } else {
      write_bytes_keep_mode(pl$move %||% pl$cp$target, pl$cp$bytes)
      if (!is.null(pl$move)) patch_finish_move(pl$abs, pl$move, pl$cp$bytes, pl$op$path)
      diffs = c(diffs, diff_unified(pl$op$path, edit_view(pl$cp, pl$cp$res$base_old),
                                    edit_view(pl$cp, pl$cp$res$base_new)))
      fuzzy = fuzzy || pl$cp$res$fuzzy
      reasons = c(reasons, edit_reasons(pl$cp))
      tags = c(tags, paste0("M ", pl$op$path, if (!is.null(pl$move)) paste0(" -> ", pl$op$move_to)))
    }
  }
  files = vapply(plan, function(pl) pl$move %||% pl$abs, "")
  head = paste0("Applied patch: ", length(plan), " file(s) changed.")
  list(files = files, message = paste(c(head, tags), collapse = "\n"),
       details = list(ops = tags, files = files, diff = diffs, fuzzy = fuzzy,
                      reasons = unique(reasons)))
}

#' An edit given as a patch envelope, in edit_file()'s return shape (paths relative to getwd())
#' A fuzzy hunk, an EOL change or a re-encoding makes it deviate, so its text carries the diff.
#' @noRd
edit_from_patch = function(envelope) {
  if (is.list(envelope)) envelope = envelope[[1L]]
  pa = patch_apply(envelope, root = getwd())
  reasons = pa$details$reasons
  list(message = pa$message, diff = diff_budget(pa$details$diff, 400L), fuzzy = pa$details$fuzzy,
       details = list(path = pa$files[1L], n_edits = length(pa$files), fuzzy = pa$details$fuzzy,
                      diff = pa$details$diff, document = FALSE, deviated = length(reasons) > 0L,
                      reasons = reasons, encoding = "UTF-8", files = pa$files))
}

#' The value of `gptr$edit()` (contract section 5.10)
#' @noRd
new_gptr_patch = function(path, message, diff, n_edits, fuzzy) {
  structure(list(path = path, message = message, diff = as.character(diff),
                 n_edits = as.integer(n_edits), fuzzy = isTRUE(fuzzy)),
            class = "gptr_patch")
}

#' Print a gptr patch: the message, and the diff only when the fuzzy fallback was used
#'
#' @param x A `gptr_patch`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_patch = function(x, ...) {
  lines = x$message
  if (isTRUE(x$fuzzy) && length(x$diff)) lines = c(lines, x$diff)
  ns_print_lines(lines)
  invisible(x)
}
