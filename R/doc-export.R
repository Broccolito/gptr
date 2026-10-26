# doc-export.R -- deterministic exports of a synchronized, explicitly recorded R document.

#' Refuse an export without publishing input content in the condition.
#' @noRd
doc_export_refuse = function(reason) {
  gptr_abort(paste0("Cannot export this history: ", reason, "."), "doc_export", reason = reason)
}

#' Count a literal Peter-only chain after R's native pipe rewrite, which may start from one of the
#' session `handles` (a console transcript's later turns); no argument is evaluated.
#' @noRd
doc_export_chain = function(expr, handles = character(), depth = 0L) {
  if (!is.call(expr) || depth > doc_sidecar_bounds()$depth) return(0L)
  head = expr[[1L]]
  named = identical(head, as.name("peter")) ||
    identical(doc_call_norm(head), quote(gptr::peter))
  if (!named) return(0L)
  args = as.list(expr)[-1L]
  if (!length(args)) return(0L)
  for (i in seq_along(args)) {
    if (is.symbol(args[[i]]) && !nzchar(as.character(args[[i]]))) return(0L)
  }
  inner = if (is.call(args[[1L]])) doc_export_chain(args[[1L]], handles, depth + 1L) else 0L
  handle = is.symbol(args[[1L]]) && as.character(args[[1L]]) %in% handles
  rest = if (inner || handle) args[-1L] else args
  literal = vapply(rest, function(x) {
    is.null(x) || (is.atomic(x) && length(x) == 1L && !is.na(x))
  }, NA)
  if (!all(literal) || !any(vapply(rest, is.character, NA))) return(0L)
  1L + inner
}

#' Read-only pending-write admission: exporting must not recover or discard pending records.
#' @noRd
doc_export_pending = function(path) {
  st = the$doc_pending
  if (is.environment(st) && length(st$docs[[path_key(path)]]$upserts)) return(TRUE)
  any(doc_sidecar_exists(c(doc_sidecar_path(path), doc_sidecar_legacy_path(path))))
}

#' Preserve body code and ordinary notes, with a fixed readable bound on captured output.
#' @noRd
doc_export_body = function(body, format, indent = "") {
  output = grepl("^[ \t]*#>", body)
  comment = grepl("^[ \t]*#", body)
  unsafe = comment & grepl("[[:cntrl:]]", body)
  body[unsafe] = vapply(which(unsafe), function(i) {
    prefix = if (output[i]) "#> " else "# "
    paste0(prefix, doc_str_literal(body[i]))
  }, "")
  seen = cumsum(output)
  keep = !output | seen <= 12L
  if (sum(output) > 12L) {
    at = which(output & seen == 12L)
    body[at] = "#> ... (further captured output omitted)"
  }
  body = body[keep]
  if (identical(format, "peter")) {
    code = nzchar(trimws(body)) & !grepl("^[ \t]*#", body)
    body[code] = paste0("# ", body[code])
  }
  body = doc_indent_lines(body, indent)
  body[output[keep]] = vapply(body[output[keep]], function(line) {
    if (nchar(line) > 80L) paste0(substr(line, 1L, 77L), "...") else line
  }, "")
  body
}

#' Wrap escaped prompt metadata without changing its characters or executable source.
#' @noRd
doc_export_prompt = function(prompt) {
  literal = doc_str_literal(prompt)
  prefix = "# Recorded prompt: "
  if (nchar(literal) <= 80L - nchar(prefix)) return(paste0(prefix, literal))
  points = utf8ToInt(literal)
  total = length(points)
  # A latter-half space leaves at least thirty characters per nonfinal fragment.
  out = character(total %/% 30L + 1L)
  start = 1L
  i = 0L
  while (start <= total) {
    width = 80L - nchar(prefix)
    end = min(start + width - 1L, total)
    if (end < total) {
      spaces = which(points[seq.int(start, end)] == 32L)
      spaces = spaces[spaces > width %/% 2L]
      if (length(spaces)) end = start + spaces[length(spaces)] - 2L
    }
    i = i + 1L
    out[[i]] = paste0(prefix, intToUtf8(points[seq.int(start, end)]))
    start = end + 1L
    prefix = "# "
  }
  out[seq_len(i)]
}

#' The path of a top-level gptr_doc() call whose string literal names the exported source
#' (relative to its directory or the working directory), else NULL; no argument is evaluated.
#' @noRd
doc_export_bind = function(expr, path) {
  if (!is.call(expr)) return(NULL)
  head = doc_call_norm(expr[[1L]])
  if (!identical(head, quote(gptr_doc)) && !identical(head, quote(gptr::gptr_doc))) return(NULL)
  lit = tryCatch(match.call(gptr_doc, expr)$path, error = function(e) NULL)
  if (!rlang::is_string(lit) || !nzchar(lit)) return(NULL)
  rel = !is_abs_path(lit) && !startsWith(lit, "~")
  if (path_key(path) %in% path_key(c(if (rel) file.path(dirname(path), lit), lit))) lit
}

#' Validate ownership and transform lines without invoking a model, source() or recovery.
#' @noRd
doc_export_lines = function(lines, format, path, target) {
  blocks = doc_find_blocks(lines)
  if (isTRUE(attr(blocks, "malformed"))) doc_export_refuse("malformed record markers")
  if (nrow(blocks) > doc_sidecar_bounds()$upserts) doc_export_refuse("too many records")
  parsed = tryCatch(doc_parse_text(lines), error = function(e) NULL)
  if (is.null(parsed)) doc_export_refuse("invalid R source")
  refs = attr(parsed, "srcref")
  tokens = utils::getParseData(parsed)
  calls = doc_scan_parse(lines, 0L)
  calls$block = vapply(calls$line1, function(line) {
    i = which(line > blocks$start & line < blocks$end)
    if (length(i)) blocks$id[i[1L]] else NA_character_
  }, "")
  calls$ph = rep(NA_character_, nrow(calls))
  literal = !is.na(calls$prompt)
  calls$ph[literal] = vapply(calls$prompt[literal], prompt_hash, "")
  top = calls[is.na(calls$block), , drop = FALSE]
  if (any(top$nested) || anyNA(top$prompt)) doc_export_refuse("nested or computed Peter calls")
  claimed = integer()
  edits = list()
  bound = vector("list", length(parsed))
  owning = integer()
  for (j in seq_along(parsed)) {
    sr = refs[[j]]
    rows = which(top$stmt1 == sr[1L] & top$stmt2 == sr[3L])
    if (!length(rows)) next
    expr = parsed[[j]]
    binding = NULL
    if (is.call(expr) && as.character(expr[[1L]])[1L] %in% c("=", "<-")) {
      if (length(expr) != 3L || !is.symbol(expr[[2L]])) {
        doc_export_refuse("non-symbol session assignment")
      }
      binding = as.character(expr[[2L]])
      expr = expr[[3L]]
    }
    if (!identical(doc_export_chain(expr, unlist(bound)), as.integer(length(rows)))) {
      doc_export_refuse("mixed or non-literal Peter expressions")
    }
    overlap = vapply(refs, function(r) r[1L] <= sr[3L] && r[3L] >= sr[1L], NA)
    if (sum(overlap) != 1L) doc_export_refuse("shared-line Peter statements")
    owning = c(owning, j)
    bound[j] = list(binding)
    run = doc_blocks_after(lines, sr[3L], blocks)
    if (nrow(run) != length(rows)) doc_export_refuse("missing or extra recorded turns")
    separate = identical(format, "peter") && length(rows) > 1L &&
      all(top$line2[rows[-length(rows)]] < top$line1[rows[-1L]]) &&
      all(vapply(seq_along(rows), function(n) {
        hit = top[rows[n], , drop = FALSE]
        right = tokens[tokens$terminal & tokens$line1 == hit$line2 &
          tokens$col1 > hit$col2, , drop = FALSE]
        indent = sub("[^ \t].*$", "", lines[top$line1[rows[min(n + 1L, length(rows))]]])
        nchar(indent) <= 74L && all(right$token %in% c("PIPE", "COMMENT")) &&
          sum(right$token == "PIPE") == as.integer(n < length(rows))
      }, NA))
    for (k in rows) {
      hit = top[k, , drop = FALSE]
      own = doc_owner(run$header, top[rows, , drop = FALSE], hit, hit$ph)
      if (is.null(own) || own$stale) doc_export_refuse("ambiguous record ownership")
      b = run[own$index, , drop = FALSE]
      i = match(b$id, blocks$id)
      if (i %in% claimed) doc_export_refuse("duplicate record ownership")
      h = b$header[[1L]]
      body = doc_block_body(lines, b)
      if (!is.null(h[["status"]]) || !rlang::is_string(h[["sha"]]) ||
          !grepl("^[0-9a-f]{8}$", h[["sha"]]) ||
          !identical(doc_block_status(h, body, hit$ph, h[["args"]]), "fresh")) {
        doc_export_refuse("missing, stale, edited or undone record")
      }
      if (!rlang::is_string(h[["session"]]) || !nzchar(h[["session"]]) ||
          !grepl("^[1-9][0-9]*$", as.character(h[["turn"]] %||% ""))) {
        doc_export_refuse("missing completed-turn identity")
      }
      if (!is.null(h[["args"]])) doc_export_refuse("interpolated inputs need review")
      if (any(grepl(doc_secret_flag, body, fixed = TRUE))) doc_export_refuse("secret-marked record")
      code = tryCatch(doc_parse_text(body, keep_source = FALSE), error = function(e) NULL)
      if (is.null(code) || any(all.names(code) %in% c("peter", "gptr_return"))) {
        doc_export_refuse("unresolved control calls in recorded code")
      }
      indent = if (separate) {
        next_row = rows[min(match(k, rows) + 1L, length(rows))]
        sub("[^ \t].*$", "", lines[top$line1[next_row]])
      } else {
        ""
      }
      feedback = doc_export_body(body, format, indent)
      if (identical(format, "r")) {
        feedback = c(doc_export_prompt(hit$prompt), feedback)
      }
      if (separate) {
        edits[[length(edits) + 1L]] = list(start = b$start, end = b$end, lines = character())
        edits[[length(edits) + 1L]] = list(start = hit$line2, end = hit$line2,
          lines = c(lines[hit$line2], feedback))
      } else {
        edits[[length(edits) + 1L]] = list(start = b$start, end = b$end, lines = feedback)
      }
      claimed = c(claimed, i)
    }
    if (identical(format, "r")) {
      edits[[length(edits) + 1L]] = list(start = sr[1L], end = sr[3L],
                                        lines = paste0("# ", lines[sr[1L]:sr[3L]]))
    }
  }
  if (length(claimed) != nrow(blocks)) doc_export_refuse("unowned recorded blocks")
  # A session handle is live from its peter() statement until ordinary code assigns the name; a
  # function reads names when it is called, so one naming any handle of the document is refused.
  live = character()
  for (j in seq_along(parsed)) {
    expr = parsed[[j]]
    if (j %in% owning) {
      live = union(live, bound[[j]])
      next
    }
    sr = refs[[j]]
    lit = doc_export_bind(expr, path)
    if (!is.null(lit)) {
      stmt = lines[sr[1L]:sr[3L]]
      own = tokens$token == "STR_CONST" & tokens$line1 >= sr[1L] & tokens$line2 <= sr[3L]
      text = utils::getParseText(tokens, tokens$id[own])
      old = text[vapply(text, function(t) identical(doc_unquote(t), lit), NA)][1L]
      overlap = vapply(refs, function(r) r[1L] <= sr[3L] && r[3L] >= sr[1L], NA)
      if (sum(overlap) != 1L || is.na(old)) doc_export_refuse("unrewritable source gptr_doc() call")
      if (identical(format, "r")) {
        stmt = paste0("# ", stmt)
      } else {
        # In the source's directory only the file name changes; elsewhere the full path.
        same = identical(path_key(dirname(target)), path_key(dirname(path)))
        new = if (same) paste0(sub("[^/\\\\]*$", "", lit), basename(target)) else target
        stmt = sub(old, doc_str_literal(new), paste(stmt, collapse = "\n"), fixed = TRUE)
        stmt = strsplit(stmt, "\n", fixed = TRUE)[[1L]]
      }
      edits[[length(edits) + 1L]] = list(start = sr[1L], end = sr[3L], lines = stmt)
      next
    }
    if ("peter" %in% all.names(expr)) doc_export_refuse("unresolved Peter references")
    set = NULL
    if (is.call(expr) && as.character(expr[[1L]])[1L] %in% c("=", "<-") && length(expr) == 3L &&
        is.symbol(expr[[2L]])) {
      set = as.character(expr[[2L]])
      expr = expr[[3L]]
    }
    used = all.names(expr)
    if (identical(format, "r") &&
        any(used %in% if ("function" %in% used) unlist(bound) else live)) {
      doc_export_refuse("ordinary code depends on a removed session handle")
    }
    live = setdiff(live, set)
  }
  if (length(edits)) {
    order = order(vapply(edits, function(e) e$start, 0L), decreasing = TRUE)
    for (i in order) lines = doc_splice(lines, edits[[i]]$start, edits[[i]]$end, edits[[i]]$lines)
  }
  c("# Exported recorded R and ordinary source; not executed or validated.",
    "# Earlier console input and unrecorded tool effects are not recovered.",
    "# Review code, external inputs and package versions before running.", "", lines)
}

#' Export a recorded R document as ordinary R or a clean Peter script
#'
#' Reads a synchronized `.R` history without executing it, asking a model or recovering
#' pending writes. In `"r"` format the original Peter statements become comments and their
#' recorded R stays executable. In `"peter"` format calls stay active and recorded R becomes
#' comments, so it is not executed a second time. User R and comments keep their source order.
#'
#' @param file An existing `.R` document with fresh recorded blocks.
#' @param to A new `.R` path in an existing directory. Existing paths are never replaced.
#' @param format `"r"` (default) or `"peter"`.
#' @return Invisibly, the normalized destination path.
#' @details Only bare or symbol-assigned literal Peter calls and Peter-only native pipelines
#' are admitted; a pipeline may start from a session handle an earlier Peter statement assigned,
#' as the later turns of a console transcript do. Distinct statements sharing a line (including
#' semicolon-separated statements), mixed pipelines, nested or computed calls, pending writes,
#' missing or edited blocks, secret markers and interpolated-input hashes are refused.
#' Raw exports also refuse ordinary code that reads a session handle after its Peter statement
#' and before ordinary code assigns that name again, and a function that names any session handle
#' of the document, wherever it is defined, as it reads the name when called. The Peter format
#' retains such ordinary references, since its calls remain active.
#' A top-level `gptr_doc()` whose string literal names the source (relative to the source's
#' directory or the working directory) becomes a comment in raw R and binds the destination in
#' the Peter format, so its calls record there: in the source's directory only the file name
#' changes, elsewhere the literal becomes the destination's full path. It must be alone on its
#' lines. Other `gptr_doc()` calls are kept.
#' Feedback follows each pipeline operand when calls end on separate lines and only its
#' pipe operator or a comment follows the closing call. Feedback follows the next operand's
#' indentation (at most 74 characters); other layouts keep feedback after the complete
#' statement. Peter calls already show their prompts, so only raw R adds prompt comments.
#' Long raw prompt comments wrap at eighty characters. Strip the recorded-prompt prefix from
#' the first line and the two-character comment prefix from continuations, then join without
#' separators to recover the complete escaped R string literal.
#' A Peter-only pipeline on one line keeps grouped feedback after the statement.
#' Call source is never reformatted.
#'
#' A completed-turn identity and matching source hashes establish a recorded snapshot, not
#' verified execution or a complete session. Ordinary console input and `record = FALSE`
#' effects cannot be reconstructed. External files, objects and package versions must still
#' be supplied. Remaining user code may use gptr or perform network and filesystem operations.
#' Captured `#>` output is limited to twelve lines per block and eighty characters per line;
#' outputs are comments. Encoding, line endings and the final newline follow the input file.
#' A UTF-8 byte order mark is preserved; source that exported file with
#' `source(to, encoding = "UTF-8-BOM")`.
#' @seealso [gptr_doc()], [gptr_source()], [gptr_blocks()]
#' @export
#' @examples
#' input = tempfile(fileext = ".R")
#' output = tempfile(fileext = ".R")
#' writeLines(c("x = 1", "# Keep ordinary code and comments.", "y = x + 1"), input)
#' gptr_export(input, output)
#' readLines(output)
#' unlink(c(input, output))
gptr_export = function(file, to, format = c("r", "peter")) {
  doc_control_guard("gptr_export")
  format = match.arg(format)
  path = doc_file_arg(file, "r", "an existing .R document")
  check_string(to, "to")
  if (!identical(doc_format_of(to), "r") || any(doc_sidecar_exists(to))) {
    doc_export_refuse("destination must be a new R file")
  }
  target = path_norm(to)
  if (!dir.exists(dirname(target)) || identical(path_key(path), path_key(target))) {
    doc_export_refuse("destination parent missing or source alias")
  }
  size = file.info(path, extra_cols = FALSE)$size
  if (!is.finite(size) || size > doc_sidecar_limit()) doc_export_refuse("source byte limit")
  if (doc_export_pending(path)) doc_export_refuse("pending writes must be synchronized first")
  doc = doc_read(path)
  if (length(doc$lines) > doc_sidecar_bounds()$lines) doc_export_refuse("source line limit")
  lines = doc_export_lines(doc$lines, format, path, target)
  bytes = doc_serialize(lines, doc$eol, doc$bom, doc$final_nl)
  if (length(bytes) > doc_sidecar_limit()) doc_export_refuse("export byte limit")
  if (!identical(unname(tools::md5sum(path)), doc$md5)) doc_export_refuse("source changed")
  write_atomic(target, bytes, expected_md5 = NA_character_)
  if (!identical(unname(tools::md5sum(path)), doc$md5)) {
    if (identical(unname(tools::md5sum(target)), cli::hash_raw_md5(bytes))) {
      unlink(target, recursive = FALSE, expand = FALSE)
    }
    doc_export_refuse("source changed during publication")
  }
  invisible(target)
}
