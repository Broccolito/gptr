# doc-formats.R -- document formats (plan P15; contract 7.15, 10.2 row 18, 11.5): `r`, `rmd`,
# `qmd`, `ipynb` (gptr's own nbformat serializer) and `transcript` as `doc_format` specs, inert
# (undone) blocks, and builtin:documents (formats, the `document` route, the `documents` prompt
# section, the agent_end/session_tree hooks, the handlers of P14's console:command and
# console:direct channels and the doc.* services; IC-34, IC-47, IC-68).
# Layer L4. The Rmd/qmd chunk functions and the notebook serializer are report 14 section 5.0
# (proto/rmd.R; proto/ipynb.R with the verifier's corrected json_num()). Chunks are divided and
# labelled as knitr (1.52) and xfun (0.61) do it, so the label knitr reports for a running chunk
# finds that chunk.

doc_rmd_begin = "^([\t >]*)(`{3,})\\s*\\{([a-zA-Z0-9_]+)( *[ ,].*)?\\}\\s*$"
doc_rmd_end = "^([\t >]*)(`{3,})\\s*$"

#' Remove a chunk's prefix from its body lines as knitr's parse_block() does: the header's
#' `[\t >]*` prefix, then that prefix without its trailing blanks
#' @noRd
doc_rmd_unprefix = function(lines, prefix) {
  if (!nzchar(prefix)) return(lines)
  for (p in c(prefix, sub("\\s+$", "", prefix))) {
    if (!nzchar(p)) next
    hit = startsWith(lines, p)
    lines[hit] = substring(lines[hit], nchar(p) + 1L)
  }
  lines
}

#' The chunk label an option string gives, as xfun::csv_options() reads it: a bare first
#' option is quoted (xfun's quote_label()), then `label=` or the one unnamed option is the label
#' (with `id = TRUE`, `id=` when neither is given, as for pipe options); a label that is not a
#' string is deparsed without blanks. NULL without a label or when knitr would refuse the text.
#' The text is parsed, never evaluated.
#' @noRd
doc_rmd_header_label = function(params, id = FALSE) {
  x = gsub("^\\s*,?", "", paste(as_utf8(params), collapse = "\n"))
  if (grepl("^\\s*[^'\"](,|\\s*$)", x)) {
    x = gsub("^\\s*([^'\"])(,|\\s*$)", "'\\1'\\2", x)
  } else if (grepl("^\\s*[^'\"](,|[^=]*(,|\\s*$))", x)) {
    x = gsub("^\\s*([^'\"][^=]*)(,|\\s*$)", "'\\1'\\2", x)
  }
  ex = tryCatch(doc_parse_text(paste0("alist(", x, ")"), keep_source = FALSE),
                error = function(e) NULL)
  if (length(ex) != 1L) return(NULL)
  e = ex[[1L]]
  if (!is.call(e) || !identical(e[[1L]], as.name("alist"))) return(NULL)
  args = as.list(e)[-1L]
  nms = names(args) %||% rep("", length(args))
  empty = vapply(seq_along(args), function(i) {
    is.name(args[[i]]) && !nzchar(as.character(args[[i]]))
  }, NA)
  unnamed = which(!nzchar(nms) & !empty)
  if (length(unnamed) > 1L) return(NULL)
  pick = match("label", nms)
  if (is.na(pick) && length(unnamed)) pick = unnamed
  if (is.na(pick) && id) pick = match("id", nms)
  if (is.na(pick) || empty[pick] || is.null(args[[pick]])) return(NULL)
  lab = args[[pick]]
  if (!is.character(lab)) lab = gsub(" ", "", as.character(as.expression(lab)))
  lab = as_utf8(lab[1L])
  if (is.na(lab) || !nzchar(lab)) NULL else lab
}

#' The comment that starts (and ends) chunk-option lines of an engine (xfun's comment_chars;
#' `#| ` for engines it does not list)
#' @noRd
doc_rmd_option_comment = function(engine) {
  ch = if (engine %in% c("awk", "bash", "coffee", "gawk", "julia", "octave", "perl",
                         "powershell", "python", "r", "ruby", "sed", "stan")) {
    "#"
  } else if (engine %in% c("Rcpp", "asy", "cc", "csharp", "d3", "dot", "fsharp", "go", "groovy",
                           "java", "js", "node", "ojs", "sass", "scala", "scss")) {
    "//"
  } else if (engine %in% c("haskell", "lua", "mysql", "psql", "sql")) {
    "--"
  } else if (engine %in% c("fortran", "fortran95")) {
    "!"
  } else if (engine %in% c("matlab", "tikz")) {
    "%"
  } else if (identical(engine, "mermaid")) {
    "%%"
  } else if (identical(engine, "stata")) {
    "*"
  } else if (identical(engine, "apl")) {
    "\u235d"
  } else if (engine %in% c("c", "css")) {
    c("/*", "*/")
  } else if (identical(engine, "sas")) {
    c("*", ";")
  } else {
    "#"
  }
  list(start = paste0(ch[1L], "| "), end = if (length(ch) > 1L) ch[2L] else "")
}

#' The `label` (else `id`) of YAML chunk options: the scalar of a top-level `label:` line, plain
#' (up to a ` #` comment), single-quoted or double-quoted; a null or empty plain value gives no
#' label. Read without the yaml package, which turns non-ASCII text into `<c3><a9>` escapes
#' outside a UTF-8 locale (IC-62); other YAML types are read as their text.
#' @noRd
doc_rmd_yaml_label = function(meta) {
  for (key in c("label", "id")) {
    hit = grep(paste0("^", key, ":(\\s|$)"), meta, value = TRUE)
    if (!length(hit)) next
    v = trimws(substring(hit[1L], nchar(key) + 2L))
    if (startsWith(v, "\"")) {
      q = regmatches(v, regexpr("^\"(?:[^\"\\\\]|\\\\.)*\"", v, perl = TRUE))
      if (length(q)) return(as_utf8(doc_str_unquote(q)))
    } else if (startsWith(v, "'")) {
      q = regmatches(v, regexpr("^'(?:[^']|'')*'", v, perl = TRUE))
      if (length(q)) return(as_utf8(gsub("''", "'", substr(q, 2L, nchar(q) - 1L), fixed = TRUE)))
    }
    v = trimws(sub("(^|\\s)#.*$", "", v))
    if (nzchar(v) && !v %in% c("~", "null", "Null", "NULL")) return(as_utf8(v))
  }
  NULL
}

#' The label given by the leading option lines of a chunk body (`#| label: x`; xfun's
#' divide_chunk()): YAML when the first option looks like `key:`, else csv options; `label`
#' wins over `id`. NULL when the body has no option lines or they give no label.
#' @noRd
doc_rmd_pipe_label = function(engine, body) {
  if (!length(body)) return(NULL)
  oc = doc_rmd_option_comment(engine)
  s1 = oc$start
  s2 = oc$end
  i1 = startsWith(body, s1)
  if (!i1[1L] && s1 != "#| ") {
    i1 = startsWith(body, "#| ")
    s1 = "#| "
    s2 = ""
  }
  if (!i1[1L]) return(NULL)
  if (!nzchar(s2)) {
    i2 = rep(FALSE, length(body))
    n2 = if (all(i1)) length(body) else which.min(i1) - 1L
  } else {
    i2 = endsWith(trimws(body, "right"), s2)
    n2 = if (i2[1L]) which.min(i2) - 1L else which.max(i2)
  }
  n2 = max(1L, n2)
  src = body[seq_len(n2)]
  meta = substr(src, nchar(s1) * i1[seq_len(n2)] + 1L, nchar(src) - nchar(s2) * i2[seq_len(n2)])
  if (grepl("^[^ :]+:($|\\s)", meta[1L])) doc_rmd_yaml_label(meta) else
    doc_rmd_header_label(meta, id = TRUE)
}

#' Code chunks of an Rmd/qmd text: df(start, end, engine, label, prefix, fence, params, closed),
#' divided as knitr divides them: YAML front matter is skipped, a chunk ends at a line holding
#' exactly its prefix and fence, and a begin line with its prefix and fence starts a new chunk
#' (the open one is unterminated: `closed` is FALSE and `end` is the line after its body). The
#' label is knitr's: the chunk's leading option lines, else its header, else `unnamed-chunk-<k>`
#' (k counts the unlabelled chunks of every engine).
#' @noRd
doc_rmd_chunks = function(lines) {
  lines = as_utf8(as.character(lines))
  n = length(lines)
  i = 1L
  if (n && grepl("^---\\s*$", lines[1L])) {
    j = which(grepl("^(---|\\.\\.\\.)\\s*$", lines))[-1L]
    if (length(j)) i = j[1L] + 1L
  }
  res = list()
  unnamed = 0L
  while (i <= n) {
    m = regmatches(lines[i], regexec(doc_rmd_begin, lines[i]))[[1L]]
    if (!length(m)) {
      i = i + 1L
      next
    }
    prefix = m[2L]
    fence = m[3L]
    j = i + 1L
    closed = FALSE
    while (j <= n) {
      if (startsWith(lines[j], paste0(prefix, fence, "{")) && grepl(doc_rmd_begin, lines[j])) break
      e = regmatches(lines[j], regexec(doc_rmd_end, lines[j]))[[1L]]
      if (length(e) && identical(e[2L], prefix) && identical(e[3L], fence)) {
        closed = TRUE
        break
      }
      j = j + 1L
    }
    params = trimws(sub("^[ ,]*", "", m[5L]))
    body = if (j - i > 1L) lines[(i + 1L):(j - 1L)] else character()
    label = doc_rmd_pipe_label(m[4L], doc_rmd_unprefix(body, prefix))
    if (is.null(label)) label = doc_rmd_header_label(gsub("^\\s*,*\\s*|\\s*,*\\s*$", "", m[5L]))
    if (is.null(label)) {
      unnamed = unnamed + 1L
      label = paste0("unnamed-chunk-", unnamed)
    }
    res[[length(res) + 1L]] = data.frame(start = i, end = j, engine = m[4L], label = label,
                                         prefix = prefix, fence = fence, params = params,
                                         closed = closed, stringsAsFactors = FALSE)
    i = if (closed) j + 1L else j
  }
  if (!length(res)) {
    return(data.frame(start = integer(), end = integer(), engine = character(),
                      label = character(), prefix = character(), fence = character(),
                      params = character(), closed = logical(), stringsAsFactors = FALSE))
  }
  do.call(rbind, res)
}

#' gptr() calls of the R chunks of an Rmd/qmd text, with document line numbers, chunk index and
#' label; attributes `blocks` (marker blocks) and `chunks`
#' @noRd
doc_rmd_calls = function(lines) {
  ch = doc_rmd_chunks(lines)
  blocks = doc_find_blocks(lines)
  out = list()
  for (k in seq_len(nrow(ch))) {
    if (!ch$engine[k] %in% c("r", "R") || ch$end[k] - ch$start[k] < 2L) next
    body = lines[(ch$start[k] + 1L):(ch$end[k] - 1L)]
    calls = doc_calls(body)
    if (!nrow(calls)) next
    shift = ch$start[k]
    calls$line1 = calls$line1 + shift
    calls$line2 = calls$line2 + shift
    calls$stmt1 = calls$stmt1 + shift
    calls$stmt2 = calls$stmt2 + shift
    calls$chunk = rep(k, nrow(calls))
    calls$label = rep(ch$label[k], nrow(calls))
    out[[length(out) + 1L]] = calls
  }
  res = if (length(out)) {
    do.call(rbind, out)
  } else {
    empty = doc_calls(character())
    empty$chunk = integer()
    empty$label = character()
    empty
  }
  attr(res, "blocks") = blocks
  attr(res, "chunks") = ch
  res
}

#' Lines strictly between two line numbers
#' @noRd
doc_lines_between = function(text, a, b) {
  if (b - a < 2L) character() else text[(a + 1L):(b - 1L)]
}

#' Which block of the agent chunks after a chunk (`run`) the top-level call `hit` owns, with the
#' prompt hash `ph` it runs with (contract 11.5). Every top-level call of the chunk shares that
#' run, so blocks are assigned one to one in document order: first by prompt and `call=` ordinal,
#' then by prompt alone (never a block whose ordinal belongs to another same-prompt call of the
#' statement, as doc_run_owner()), then by ordinal (stale). The other calls' prompts are their
#' literals. Returns list(index, stale) or NULL.
#' @noRd
doc_rmd_owner = function(run, calls, hit, ph) {
  if (!nrow(run)) return(NULL)
  top = calls[calls$chunk == hit$chunk & is.na(calls$block) & !calls$nested, , drop = FALSE]
  me = which(top$line1 == hit$line1 & top$col1 == hit$col1)
  if (!length(me)) return(NULL)
  phs = top$ph
  phs[me] = ph %||% NA_character_
  prompts = vapply(run$header, function(h) as.character(h[["prompt"]] %||% NA_character_), "")
  ord = doc_header_ordinals(run$header)
  owner = rep(NA_integer_, nrow(run))
  stale = rep(FALSE, nrow(run))
  for (pass in 1:3) {
    for (i in seq_len(nrow(top))) {
      if (i %in% owner) next
      free = is.na(owner)
      same = free & !is.na(prompts) & !is.na(phs[i]) & prompts == phs[i]
      k = top$n_in_stmt[i]
      cand = switch(pass,
                    which(same & ord == k),
                    which(same & !(ord %in% doc_same_ordinals(calls, top[i, , drop = FALSE]))),
                    which(free & ord == k))
      if (length(cand)) {
        owner[cand[1L]] = i
        stale[cand[1L]] = pass == 3L
      }
    }
  }
  b = which(owner == me)
  if (!length(b)) return(NULL)
  list(index = b[1L], stale = stale[b[1L]])
}

#' The rmd/qmd formats' locate(): the calling chunk and the agent chunks after it
#' @noRd
doc_rmd_locate = function(text, site) {
  calls = doc_rmd_calls(text)
  ch = attr(calls, "chunks")
  blocks = attr(calls, "blocks")
  out = list(stmt = NULL, blocks = blocks[0L, , drop = FALSE], hit = NULL, owned = NULL,
             insert_after = NULL, top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "")
  hit = doc_match_anchor(calls, site[["anchor"]])
  if (is.null(hit)) return(out)
  out$hit = hit
  out$stmt = c(hit$stmt1, hit$stmt2)
  if (isTRUE(hit$nested)) return(out)
  if (!is.na(hit$block)) {
    out$in_block = hit$block
    out$ordinal = hit$n_in_block
    return(out)
  }
  out$ordinal = hit$n_in_stmt
  out$top_level = TRUE
  k = hit$chunk
  last_end = ch$end[k]
  kk = k + 1L
  run = blocks[0L, , drop = FALSE]
  while (kk <= nrow(ch) && grepl("^gptr-", ch$label[kk]) &&
         all(!nzchar(trimws(doc_lines_between(text, last_end, ch$start[kk]))))) {
    run = rbind(run, blocks[blocks$start > ch$start[kk] & blocks$end < ch$end[kk], ,
                            drop = FALSE])
    last_end = ch$end[kk]
    kk = kk + 1L
  }
  out$blocks = run
  out$insert_after = last_end
  own = doc_rmd_owner(run, calls, hit, site[["prompt_hash"]])
  if (!is.null(own)) {
    b = run[own$index, , drop = FALSE]
    status = doc_block_status(b$header[[1L]], doc_block_body(text, b), site[["prompt_hash"]],
                              site[["args_hash"]])
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = b$id, header = b$header[[1L]], status = status, start = b$start,
                     end = b$end)
  }
  out
}

#' Append a prompt chunk holding a console statement (Rmd/qmd transcripts)
#' @noRd
doc_rmd_append_chunk = function(text, code) {
  while (length(text) && !nzchar(trimws(text[length(text)]))) text = text[-length(text)]
  c(text, "", "```{r}", code, "```")
}

#' The fence of an agent chunk: `fence`, made one backtick longer than the longest backtick run
#' that starts a line of the chunk's body when that run is at least as long (such a line would end
#' the chunk, or start another, under knitr's or pandoc's rules)
#' @noRd
doc_rmd_fence = function(fence, lines) {
  runs = regmatches(lines, regexpr("^[\t >]*`{3,}", lines))
  n = if (length(runs)) max(nchar(gsub("[^`]", "", runs))) else 0L
  if (n >= nchar(fence)) strrep("`", n + 1L) else fence
}

#' Lengthen the fences of an agent chunk (row `chunk` of doc_rmd_chunks()) that would no longer
#' hold its body once `lines` are written into it
#' @noRd
doc_rmd_refence = function(text, chunk, lines) {
  fence = doc_rmd_fence(chunk$fence, c(doc_lines_between(text, chunk$start, chunk$end), lines))
  if (identical(fence, chunk$fence)) return(text)
  text[chunk$start] = sub(chunk$fence, fence, text[chunk$start], fixed = TRUE)
  text[chunk$end] = sub(chunk$fence, fence, text[chunk$end], fixed = TRUE)
  text
}

#' The rmd/qmd formats' upsert(): replace inside an agent chunk, else add an agent chunk after
#' the owning chunk (fence and prefix copied, the fence lengthened when the body holds a fence
#' line); console sites append a prompt chunk first. An unterminated chunk is never written into
#' or after.
#' @noRd
doc_rmd_upsert_fn = function(style) {
  force(style)
  function(text, site, lines, block_id) {
    blocks = doc_find_blocks(text)
    if (isTRUE(attr(blocks, "malformed"))) {
      gptr_abort("The document has malformed gptr markers.", "doc_write", path = site[["path"]],
                 reason = "malformed")
    }
    ch = doc_rmd_chunks(text)
    hit = which(blocks$id == block_id)
    if (length(hit)) {
      b = blocks[hit, , drop = FALSE]
      k = which(ch$start < b$start & ch$end > b$end)
      if (length(k)) {
        if (!ch$closed[k[1L]]) {
          gptr_abort("The agent chunk is not terminated.", "doc_write", path = site[["path"]],
                     reason = "malformed")
        }
        text = doc_rmd_refence(text, ch[k[1L], , drop = FALSE], lines)
      }
      return(doc_splice(text, b$start, b$end, doc_indent_lines(lines, b$indent)))
    }
    if (isTRUE(site[["console"]])) {
      if (nrow(ch) && !ch$closed[nrow(ch)]) {
        gptr_abort("The last chunk of the document is not terminated.", "doc_write",
                   path = site[["path"]], reason = "malformed")
      }
      text = doc_rmd_append_chunk(text, site[["statement"]] %||% doc_console_statement(text, site))
      after = length(text)
      prefix = ""
      fence = "```"
    } else {
      loc = doc_rmd_locate(text, site)
      if (is.null(loc$stmt) || !isTRUE(loc$top_level)) {
        gptr_abort("The calling chunk was not found.", "doc_write", path = site[["path"]],
                   reason = "not found")
      }
      k = loc$hit$chunk
      after = loc$insert_after
      touched = ch$start >= ch$start[k] & ch$start <= after
      if (!all(ch$closed[touched])) {
        gptr_abort("The calling chunk or an agent chunk after it is not terminated.", "doc_write",
                   path = site[["path"]], reason = "malformed")
      }
      prefix = ch$prefix[k]
      fence = ch$fence[k]
    }
    fence = doc_rmd_fence(fence, lines)
    label = paste0("gptr-", block_id)
    header = if (identical(style, "qmd")) {
      c(paste0(prefix, fence, "{r}"), paste0(prefix, "#| label: ", label))
    } else {
      paste0(prefix, fence, "{r ", label, "}")
    }
    append(text, c("", header, doc_indent_lines(lines, prefix), paste0(prefix, fence)),
           after = after)
  }
}

#' Add or remove eval=FALSE (`#| eval: false`) on the agent chunk of a block (G7 section 3.8).
#' In qmd only the chunk's leading option lines are read and written (the lines from the first
#' one that start with `#| `, after the prefix, as doc_rmd_pipe_label() and xfun's
#' divide_chunk() read them), never the code of the block.
#' @noRd
doc_rmd_chunk_eval = function(text, id, inert, style) {
  ch = doc_rmd_chunks(text)
  k = which(ch$label %in% paste0("gptr-", id))
  if (!length(k)) return(text)
  k = k[1L]
  if (identical(style, "qmd")) {
    pre = ch$prefix[k]
    body_idx = seq.int(ch$start[k] + 1L, length.out = max(0L, ch$end[k] - ch$start[k] - 1L))
    body = doc_rmd_unprefix(text[body_idx], pre)
    opt = startsWith(body, "#| ")
    n_opt = if (all(opt)) length(body) else which.min(opt) - 1L
    body_idx = body_idx[seq_len(n_opt)]
    body = body[seq_len(n_opt)]
    has = body_idx[grepl("^#\\|\\s*eval:\\s*false\\s*$", body)]
    if (inert && !length(has)) {
      lab = body_idx[grepl("^#\\|\\s*label:", body)]
      text = append(text, paste0(pre, "#| eval: false"),
                    after = if (length(lab)) lab[1L] else ch$start[k])
    }
    if (!inert && length(has)) text = text[-has]
    return(text)
  }
  h = text[ch$start[k]]
  if (inert && !grepl("eval\\s*=\\s*FALSE", h)) h = sub("\\}\\s*$", ", eval=FALSE}", h)
  if (!inert) h = sub(",\\s*eval\\s*=\\s*FALSE", "", h)
  text[ch$start[k]] = h
  text
}

#' Make a whole marker block inert (status=undone, every non-empty body line prefixed `#~ `) or
#' live again (status dropped, one `#~ ` removed per line), G7 section 3.8. A block already in the
#' requested state, or lines that are not one whole block, are returned unchanged.
#' @noRd
doc_inert_marker_lines = function(seg, inert = TRUE) {
  n = length(seg)
  if (n < 2L) return(seg)
  open = regmatches(seg[1L], regexec(doc_re_open, seg[1L], perl = TRUE))[[1L]]
  close = regmatches(seg[n], regexec(doc_re_close, seg[n], perl = TRUE))[[1L]]
  if (!length(open) || !length(close) || !identical(open[3L], close[3L])) return(seg)
  hdr = doc_parse_kv(open[4L])
  if (identical(hdr[["status"]], "undone") == isTRUE(inert)) return(seg)
  indent = open[2L]
  hdr[["status"]] = if (inert) "undone" else NULL
  body = if (n > 2L) seg[2:(n - 1L)] else character()
  if (nzchar(indent)) {
    body = ifelse(startsWith(body, indent), substring(body, nchar(indent) + 1L), body)
  }
  body = if (inert) {
    ifelse(nzchar(body), paste0("#~ ", body), body)
  } else {
    sub("^#~ ", "", body)
  }
  doc_render_block(open[3L], hdr, body, indent)
}

#' The marker formats' inert(): the lines of one block made inert
#' @noRd
doc_marker_inert = function(lines) {
  doc_inert_marker_lines(lines, TRUE)
}

#' The r, rmd, qmd and transcript formats' render(): a marker block
#' @noRd
doc_r_render = function(block, site) {
  doc_render_block(block[["id"]], block[["header"]], block[["body"]])
}

#' The r format's locate()
#' @noRd
doc_r_locate = function(text, site) {
  doc_text_locate(text, site)
}

#' The r format's upsert(): replace a block in place, else insert it after the owned run
#' @noRd
doc_r_upsert = function(text, site, lines, block_id) {
  blocks = doc_find_blocks(text)
  if (isTRUE(attr(blocks, "malformed"))) {
    gptr_abort("The document has malformed gptr markers.", "doc_write", path = site[["path"]],
               reason = "malformed")
  }
  hit = which(blocks$id == block_id)
  if (length(hit)) {
    return(doc_splice(text, blocks$start[hit], blocks$end[hit],
                      doc_indent_lines(lines, blocks$indent[hit])))
  }
  loc = doc_text_locate(text, site)
  if (is.null(loc$stmt) || !isTRUE(loc$top_level)) {
    gptr_abort("The calling statement was not found.", "doc_write", path = site[["path"]],
               reason = "not found")
  }
  append(text, doc_indent_lines(lines, loc$indent), after = loc$insert_after)
}

#' The transcript statement of a console turn (IC-49): `s_<6 hex> = gptr(...)` for the
#' session's first prompt in this text, `s_<6 hex> |> gptr(...)` afterwards
#' @noRd
doc_console_statement = function(text, site) {
  var = paste0("s_", substr(sub("^s", "", site[["session_id"]] %||% "s000000"), 1L, 6L))
  args = paste(c(doc_str_literal(site[["template"]] %||% ""), site[["context_labels"]]),
               collapse = ", ")
  first = !any(startsWith(sub("^#~ ", "", text), paste0(var, " = gptr(")))
  if (first) paste0(var, " = gptr(", args, ")") else paste0(var, " |> gptr(", args, ")")
}

#' Header lines of a transcript session (contract 11.5 transcript row), once per session id
#' @noRd
doc_transcript_header = function(text, site) {
  id = site[["session_id"]] %||% "unknown"
  if (any(startsWith(text, paste0("# gptr session ", id, " ")))) return(character())
  head = c(paste0("# gptr session ", id, " -- started ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
           paste0("# machine log: ", site[["session_file"]] %||% "(none)"))
  if (!length(text)) {
    head = c(head, "# source() this file to replay the recorded code without calling a model;",
             "# options(gptr.replay = \"live\") re-asks the model.", "library(gptr)")
  }
  c(if (length(text)) "", head)
}

#' The transcript format's upsert(): replace by id, else append the header, statement and block
#' @noRd
doc_transcript_upsert = function(text, site, lines, block_id) {
  blocks = doc_find_blocks(text)
  if (isTRUE(attr(blocks, "malformed"))) {
    gptr_abort("The transcript has malformed gptr markers.", "doc_write", path = site[["path"]],
               reason = "malformed")
  }
  hit = which(blocks$id == block_id)
  if (length(hit)) {
    return(doc_splice(text, blocks$start[hit], blocks$end[hit],
                      doc_indent_lines(lines, blocks$indent[hit])))
  }
  c(text, doc_transcript_header(text, site), "",
    site[["statement"]] %||% doc_console_statement(text, site), lines)
}

#' The transcript format's locate(): console turns are appended, never located
#' @noRd
doc_transcript_locate = function(text, site) {
  list(stmt = NULL, blocks = doc_find_blocks(text)[0L, , drop = FALSE], hit = NULL, owned = NULL,
       insert_after = length(text), top_level = TRUE, in_block = NULL, ordinal = 1L, indent = "")
}
