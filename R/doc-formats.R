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

#' peter() calls of the R chunks of an Rmd/qmd text, with document line numbers, chunk index and
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

#' The transcript statement of a console turn (IC-49): `s_<6 hex> = peter(...)` for the
#' session's first prompt in this text, `s_<6 hex> |> peter(...)` afterwards
#' @noRd
doc_console_statement = function(text, site) {
  var = paste0("s_", substr(sub("^s", "", site[["session_id"]] %||% "s000000"), 1L, 6L))
  args = paste(c(doc_str_literal(site[["template"]] %||% ""), site[["context_labels"]]),
               collapse = ", ")
  first = !any(startsWith(sub("^#~ ", "", text), paste0(var, " = peter(")))
  if (first) paste0(var, " = peter(", args, ")") else paste0(var, " |> peter(", args, ")")
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

# ---- the notebook format: gptr's own nbformat 4 serializer (report 14 proto/ipynb.R, with the
# verification log's corrected number formatting) -----------------------------------------------

#' Escape a string as Python's json.dumps(ensure_ascii = False) does
#' @noRd
nb_json_escape = function(s) {
  s = as_utf8(s)
  s = gsub("\\", "\\\\", s, fixed = TRUE)
  s = gsub("\"", "\\\"", s, fixed = TRUE)
  s = gsub("\n", "\\n", s, fixed = TRUE)
  s = gsub("\r", "\\r", s, fixed = TRUE)
  s = gsub("\t", "\\t", s, fixed = TRUE)
  s = gsub("\b", "\\b", s, fixed = TRUE)
  s = gsub("\f", "\\f", s, fixed = TRUE)
  ctl = gregexpr("[\001-\037]", s, perl = TRUE)
  if (any(unlist(ctl) > 0L)) {
    regmatches(s, ctl) = lapply(regmatches(s, ctl), function(ch) {
      vapply(ch, function(c) sprintf("\\u%04x", utf8ToInt(c)), "", USE.NAMES = FALSE)
    })
  }
  paste0("\"", s, "\"")
}

#' Doubles read back from number strings by jsonlite's correctly rounded parser (never
#' as.numeric(), which is not correctly rounded; report 14 item 22)
#' @noRd
nb_json_back = function(s) {
  as.double(unlist(json_decode(paste0("[", paste(s, collapse = ","), "]"))))
}

#' A `%.<k>e` number string one unit up in its last digit (`9.99e+02` gives `1.00e+03`)
#' @noRd
nb_json_next_up = function(s) {
  ex = as.integer(sub("^.*e", "", s))
  d = as.integer(strsplit(gsub(".", "", sub("e.*$", "", s), fixed = TRUE), "",
                          fixed = TRUE)[[1L]])
  i = length(d)
  while (i >= 1L && d[i] == 9L) {
    d[i] = 0L
    i = i - 1L
  }
  if (i < 1L) {
    d = c(1L, d[-length(d)])
    ex = ex + 1L
  } else {
    d[i] = d[i] + 1L
  }
  paste0(d[1L], if (length(d) > 1L) paste0(".", paste(d[-1L], collapse = "")), "e",
         sprintf("%+03d", ex))
}

#' The shortest `%.<k>e` string of each positive finite double that parses back to it (one parse
#' for all 17 lengths). Just above a power of two the gap between doubles is twice the gap below
#' it, so there the shortest string can be the one a unit above the correctly rounded one;
#' Python's repr (David Gay's shortest round trip) takes it, so it is tried for powers of two.
#' @noRd
nb_json_shortest = function(ax) {
  n = length(ax)
  ks = 0:16
  cand = matrix(sprintf(rep(paste0("%.", ks, "e"), each = n), rep(ax, length(ks))), nrow = n)
  ok = matrix(nb_json_back(cand) == rep(ax, length(ks)), nrow = n)
  first = max.col(ok, ties.method = "first")
  s = cand[cbind(seq_len(n), first)]
  for (i in which(ax == 2^round(log2(ax)) & first > 1L)) {
    for (k in seq_len(first[i] - 1L)) {
      nxt = nb_json_next_up(cand[i, k])
      if (nb_json_back(nxt) == ax[i]) {
        s[i] = nxt
        break
      }
    }
  }
  s
}

#' Python repr() of numbers, vectorised: the shortest significand that parses back to the same
#' double (report 14 verification log, item 23, and nb_json_shortest()), laid out as Python does
#' (`1e+16`, `1e-05`, `0.0001`, `3.0`)
#' @noRd
nb_json_num = function(x) {
  if (is.integer(x)) return(as.character(x))
  x = as.double(x)
  if (!all(is.finite(x))) {
    gptr_abort("A notebook number is not finite.", "doc_write", path = NA, reason = "number")
  }
  out = character(length(x))
  zero = x == 0
  out[zero] = ifelse(1 / x[zero] < 0, "-0.0", "0.0")
  nz = which(!zero)
  if (!length(nz)) return(out)
  ax = abs(x[nz])
  s = character(length(nz))
  for (from in seq(1L, length(nz), by = 2048L)) {
    idx = from:min(length(nz), from + 2047L)
    s[idx] = nb_json_shortest(ax[idx])
  }
  digits = sub("0+$", "", gsub(".", "", sub("e.*$", "", s), fixed = TRUE))
  decpt = as.integer(sub("^.*e", "", s)) + 1L
  nd = nchar(digits)
  fixed = decpt > -4L & decpt <= 16L
  small = fixed & decpt <= 0L
  whole = fixed & !small & decpt >= nd
  part = fixed & !small & !whole
  expo = !fixed
  r = character(length(nz))
  if (any(small)) r[small] = paste0("0.", strrep("0", -decpt[small]), digits[small])
  if (any(whole)) r[whole] = paste0(digits[whole], strrep("0", decpt[whole] - nd[whole]), ".0")
  if (any(part)) {
    r[part] = paste0(substr(digits[part], 1L, decpt[part]), ".",
                     substring(digits[part], decpt[part] + 1L))
  }
  if (any(expo)) {
    r[expo] = paste0(substr(digits[expo], 1L, 1L),
                     ifelse(nd[expo] > 1L, paste0(".", substring(digits[expo], 2L)), ""),
                     "e", sprintf("%+03d", decpt[expo] - 1L))
  }
  out[nz] = paste0(ifelse(x[nz] < 0, "-", ""), r)
  out
}

#' Serialise a parsed notebook value like nbformat (indent unit, ", " and ": " separators). The
#' plain doubles of a list are formatted together; a number carrying attribute `nb_json` (see
#' nb_keep_ints()) is written as it was read.
#' @noRd
nb_json_write = function(x, indent = " ", level = 0L) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    nms = names(x)
    is_obj = !is.null(nms)
    if (!length(x)) return(if (is_obj) "{}" else "[]")
    num = vapply(x, function(v) {
      is.double(v) && length(v) == 1L && !is.na(v) && is.null(attributes(v))
    }, NA, USE.NAMES = FALSE)
    items = character(length(x))
    if (any(num)) items[num] = nb_json_num(unlist(x[num], use.names = FALSE))
    if (!all(num)) {
      items[!num] = vapply(x[!num], nb_json_write, "", indent = indent, level = level + 1L,
                           USE.NAMES = FALSE)
    }
    if (is_obj) items = paste0(nb_json_escape(nms), ": ", items)
    pad = strrep(indent, level)
    pad1 = strrep(indent, level + 1L)
    open = if (is_obj) "{" else "["
    close = if (is_obj) "}" else "]"
    return(paste0(open, "\n", paste0(pad1, items, collapse = ",\n"), "\n", pad, close))
  }
  if (length(x) != 1L) {
    gptr_abort("A notebook value is not a scalar.", "doc_write", path = NA, reason = "notebook")
  }
  tok = attr(x, "nb_json", exact = TRUE)
  if (is.character(tok) && length(tok) == 1L) return(tok)
  if (is.na(x)) return("null")
  if (is.logical(x)) return(if (x) "true" else "false")
  if (is.numeric(x)) return(nb_json_num(x))
  nb_json_escape(as.character(x))
}

#' Integers beyond 32 bits, which jsonlite reads as doubles, keep the digits they were written
#' with (attribute `nb_json`): Python reads and writes them as integers. The number tokens outside
#' strings are matched to the numbers of the parsed value in document order; only a text with a
#' run of ten or more digits after `[`, `,` or `:` is scanned, and nothing is marked when the
#' counts disagree.
#' @noRd
nb_keep_ints = function(nb, txt) {
  if (!grepl("[\\[,:][ \t\r\n]*-?[0-9]{10,}[ \t\r\n]*[],}]", txt, perl = TRUE)) return(nb)
  re = "\"(?:[^\"\\\\]++|\\\\.)*+\"|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
  tok = tryCatch(regmatches(txt, gregexpr(re, txt, perl = TRUE))[[1L]],
                 error = function(e) NULL)
  if (is.null(tok)) return(nb)
  tok = tok[!startsWith(tok, "\"")]
  n = 0L
  out = rapply(nb, function(v) {
    n <<- n + 1L
    tk = if (n <= length(tok)) tok[n] else NA_character_
    if (is.double(v) && !is.na(tk) && !grepl("[.eE]", tk)) attr(v, "nb_json") = tk
    v
  }, classes = c("integer", "numeric"), how = "replace")
  if (n != length(tok)) return(nb)
  out
}

#' Parse notebook lines (nbformat 4 only); attribute `indent` is the file's indentation unit.
#' Text that is not a JSON object with `nbformat` 4 is a doc_write error.
#' @noRd
nb_parse = function(lines) {
  txt = paste(as_utf8(as.character(lines)), collapse = "\n")
  nb = tryCatch(json_decode(txt), error = function(e) NULL)
  if (!is.list(nb) || is.null(names(nb))) {
    gptr_abort("The notebook is not a JSON object.", "doc_write", path = NA, reason = "notebook")
  }
  v = nb[["nbformat"]]
  if (!is.numeric(v) || length(v) != 1L || is.na(v) || v != 4) {
    gptr_abort("Only nbformat 4 notebooks are supported.", "doc_write", path = NA,
               reason = "notebook")
  }
  nb = nb_keep_ints(nb, txt)
  second = regmatches(txt, regexpr("\n[ \t]+", txt))
  attr(nb, "indent") = if (length(second)) sub("^\n", "", second) else " "
  nb
}

#' Serialise a notebook to lines (the final newline is kept by doc_serialize())
#' @noRd
nb_serialize = function(nb) {
  indent = attr(nb, "indent", exact = TRUE) %||% " "
  attr(nb, "indent") = NULL
  strsplit(nb_json_write(nb, indent), "\n", fixed = TRUE)[[1L]]
}

#' Split code into nbformat source lines as nbformat's split_lines() does (Python's
#' `str.splitlines(True)`: a line ends after `\r\n`, `\n`, `\r`, `\v`, `\f`, `\x1c`-`\x1e`,
#' U+0085, U+2028 or U+2029, and keeps its ending)
#' @noRd
nb_source_split = function(code) {
  s = paste(as_utf8(as.character(code)), collapse = "\n")
  if (!nzchar(s)) return(list())
  m = gregexpr("\r\n|[\n\r\v\f\u001c\u001d\u001e\u0085\u2028\u2029]", s, perl = TRUE)[[1L]]
  if (m[1L] == -1L) return(list(s))
  ends = as.integer(m) + attr(m, "match.length") - 1L
  parts = substring(s, c(1L, ends + 1L), c(ends, nchar(s)))
  as.list(parts[nzchar(parts)])
}

#' Source lines of a notebook cell: its source joined and split at newlines; a final newline
#' gives a final empty line, so the lines of nb_source_split() come back as they were
#' @noRd
nb_cell_lines = function(cell) {
  src = paste(as_utf8(as.character(unlist(cell[["source"]]))), collapse = "")
  if (!nzchar(src)) return(character())
  strsplit(paste0(src, "\n"), "\n", fixed = TRUE)[[1L]]
}

#' The `metadata.gptr` object of a cell (read by its exact name), else an empty list
#' @noRd
nb_cell_meta = function(cell) {
  md = if (is.list(cell)) cell[["metadata"]]
  m = if (is.list(md)) md[["gptr"]]
  if (is.list(m)) m else list()
}

#' Cell ids of a notebook, with agent cells known as `gptr-<id>`. A cell whose own id is not a
#' `gptr-` id (none before nbformat 4.5, or a fresh one from a save that upgraded the notebook to
#' 4.5) but whose `metadata.gptr.id` is `<id>` is known by `gptr-<id>` unless a cell carries that
#' id itself or an earlier cell already claimed it (a copy of an agent cell keeps its own id).
#' Other cells without an id give NA.
#' @noRd
nb_cell_ids = function(nb) {
  cells = nb[["cells"]]
  out = vapply(cells, function(cell) {
    id = if (is.list(cell)) cell[["id"]]
    if (is.character(id) && length(id) == 1L) id else NA_character_
  }, "", USE.NAMES = FALSE)
  gid = vapply(cells, function(cell) {
    g = nb_cell_meta(cell)[["id"]]
    ok = is.character(g) && length(g) == 1L && !is.na(g) && nzchar(g)
    if (ok) paste0("gptr-", g) else NA_character_
  }, "", USE.NAMES = FALSE)
  for (i in which(!nb_is_agent(out) & !is.na(gid))) {
    if (!(gid[i] %in% out)) out[i] = gid[i]
  }
  out
}

#' Which cell ids are agent cells (`gptr-<id>`)
#' @noRd
nb_is_agent = function(ids) {
  !is.na(ids) & startsWith(ids, "gptr-")
}

#' Index of the j-th code cell (not an agent cell) calling peter() with this prompt hash, or an
#' identical call for computed prompts; NA when none
#' @noRd
nb_find_call_cell = function(nb, ph, call0 = NULL, j = 1L) {
  cells = nb[["cells"]]
  agent = nb_is_agent(nb_cell_ids(nb))
  found = 0L
  for (i in seq_along(cells)) {
    if (agent[i] || !identical(cells[[i]][["cell_type"]], "code")) next
    calls = doc_calls(nb_cell_lines(cells[[i]]))
    if (length(doc_calls_have(calls, ph %||% NA_character_, call0))) {
      found = found + 1L
      if (found == j) return(i)
    }
  }
  NA_integer_
}

#' Ordinal of calling cell `cell` among the code cells that call peter() with the same prompt
#' hash (or the same call, for computed prompts): the `j` of a notebook anchor
#' @noRd
nb_call_ordinal = function(nb, cell, ph, call0 = NULL) {
  j = 1L
  repeat {
    k = nb_find_call_cell(nb, ph, call0, j)
    if (is.na(k) || k >= cell) return(j)
    j = j + 1L
  }
}

#' Agent-cell metadata `metadata.gptr` from a block header (contract 11.5), keys sorted
#' @noRd
nb_meta = function(id, header) {
  meta = c(list(id = id), header[!vapply(header, is.null, NA)])
  meta = lapply(meta, function(v) if (is.numeric(v) && !is.integer(v)) as.character(v) else v)
  meta[order(names(meta), method = "radix")]
}

#' Set key `key` of a JSON object (a named list); a new key goes in sorted order (nbformat's
#' sort_keys)
#' @noRd
nb_put = function(obj, key, value) {
  if (!is.list(obj) || is.null(names(obj))) obj = structure(list(), names = character())
  had = key %in% names(obj)
  obj[[key]] = value
  if (!had) obj = obj[order(names(obj), method = "radix")]
  obj
}

#' A new agent cell with nbformat's sorted keys; without `id` when the notebook predates
#' nbformat 4.5, whose cell schema has no id (the cell is then known by its metadata.gptr.id)
#' @noRd
nb_code_cell = function(code, id, meta, cell_id = TRUE) {
  cell = list(cell_type = "code", execution_count = NULL, id = paste0("gptr-", id),
              metadata = list(gptr = meta), outputs = list(), source = nb_source_split(code))
  if (!isTRUE(cell_id)) cell[["id"]] = NULL
  cell
}

#' Does the notebook's format version have cell ids (nbformat 4.5 and later)?
#' @noRd
nb_has_cell_ids = function(nb) {
  m = nb[["nbformat_minor"]]
  is.numeric(m) && length(m) == 1L && !is.na(m) && m >= 5
}

#' The ipynb format's locate(): the calling cell (found by content: the j-th code cell calling
#' peter() with the anchor's prompt hash, or its call0; IC-51), the located call in it (among the
#' cell's rows with that prompt hash, the one that is the anchor's call0 itself: the steps of a
#' pipeline that repeats a prompt, ambiguity 28) and the agent cells after it. The calling cell's
#' top-level calls share that run of agent cells and own them one to one (doc_rmd_owner()); a
#' call that is nested (in a function, loop, ...) or inside a marker block owns none (contract
#' 11.5).
#' @noRd
doc_ipynb_locate = function(text, site) {
  nb = nb_parse(text)
  a = site[["anchor"]]
  ph = a[["ph"]] %||% NA_character_
  call0 = a[["call0"]]
  # by content and ordinal, never by the cell index seen at locate time: agent cells inserted
  # above (earlier pending blocks of the same sync) move the calling cells down
  cell = nb_find_call_cell(nb, ph, call0, a[["j"]] %||% 1L)
  out = list(stmt = NULL, blocks = NULL, hit = NULL, owned = NULL, insert_after = NULL,
             top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "", cell = cell)
  if (is.na(cell)) return(out)
  cells = nb[["cells"]]
  calls = doc_calls(nb_cell_lines(cells[[cell]]))
  calls$chunk = rep(cell, nrow(calls))
  hit = doc_by_identity(calls[doc_calls_have(calls, ph, call0), , drop = FALSE], call0)
  hit = hit[1L, , drop = FALSE]
  out$hit = hit
  out$stmt = c(cell, cell)
  if (isTRUE(hit$nested)) return(out)
  if (!is.na(hit$block)) {
    out$in_block = hit$block
    out$ordinal = hit$n_in_block
    return(out)
  }
  out$ordinal = hit$n_in_stmt
  out$top_level = TRUE
  ids = nb_cell_ids(nb)
  agent = nb_is_agent(ids)
  run = integer()
  k = cell + 1L
  while (k <= length(cells) && agent[k]) {
    run = c(run, k)
    k = k + 1L
  }
  out$insert_after = if (length(run)) run[length(run)] else cell
  if (!length(run)) return(out)
  metas = lapply(cells[run], nb_cell_meta)
  heads = data.frame(cell = run)
  heads$header = metas
  own = doc_rmd_owner(heads, calls, hit, site[["prompt_hash"]])
  if (!is.null(own)) {
    k = run[own$index]
    meta = metas[[own$index]]
    status = doc_block_status(meta, nb_cell_lines(cells[[k]]), site[["prompt_hash"]],
                              site[["args_hash"]])
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = meta[["id"]] %||% sub("^gptr-", "", ids[k]), header = meta,
                     status = status, start = k, end = k)
  }
  out
}

#' The ipynb format's render(): body lines with the cell metadata as attribute `meta`
#' @noRd
doc_ipynb_render = function(block, site) {
  structure(as.character(block[["body"]]), meta = nb_meta(block[["id"]], block[["header"]]))
}

#' The ipynb format's upsert(): only `source` and `metadata.gptr` change on a rewrite; a new agent
#' cell goes after the run of agent cells that follows the calling cell
#' @noRd
doc_ipynb_upsert = function(text, site, lines, block_id) {
  nb = nb_parse(text)
  meta = attr(lines, "meta", exact = TRUE) %||% list(id = block_id)
  hit = match(paste0("gptr-", block_id), nb_cell_ids(nb))
  if (!is.na(hit)) {
    cell = nb[["cells"]][[hit]]
    cell = nb_put(cell, "metadata", nb_put(cell[["metadata"]], "gptr", meta))
    cell[["source"]] = nb_source_split(as.character(lines))
    nb[["cells"]][[hit]] = cell
  } else {
    loc = doc_ipynb_locate(text, site)
    if (is.null(loc$stmt) || !isTRUE(loc$top_level)) {
      gptr_abort("The calling cell was not found in the notebook.", "doc_write",
                 path = site[["path"]] %||% NA, reason = "not found")
    }
    cell = nb_code_cell(as.character(lines), block_id, meta, nb_has_cell_ids(nb))
    nb[["cells"]] = append(nb[["cells"]], list(cell), after = loc$insert_after)
  }
  nb_serialize(nb)
}

#' The ipynb format's inert(): every non-empty source line gets one `#~ ` (G7 section 3.8)
#' @noRd
doc_ipynb_inert = function(lines) {
  lines = as.character(lines)
  live = nzchar(lines)
  lines[live] = paste0("#~ ", lines[live])
  lines
}

#' Undo or revive agent cells of a notebook (G7 section 3.8: metadata.gptr.status = "undone" and
#' `#~ ` source lines). A cell already in the requested state is left alone, reviving removes
#' exactly the one `#~ ` inert added, and a notebook nothing is changed in is returned as it was.
#' @noRd
nb_inert_text = function(text, ids, inert = TRUE) {
  nb = nb_parse(text)
  cids = nb_cell_ids(nb)
  changed = FALSE
  for (id in ids) {
    k = match(paste0("gptr-", id), cids)
    if (is.na(k)) next
    cell = nb[["cells"]][[k]]
    old = structure(nb_cell_lines(cell), meta = nb_cell_meta(cell))
    src = doc_inert_block_lines(old, "ipynb", inert)
    if (identical(src, old)) next
    cell = nb_put(cell, "metadata", nb_put(cell[["metadata"]], "gptr", attr(src, "meta")))
    cell[["source"]] = nb_source_split(as.character(src))
    nb[["cells"]][[k]] = cell
    changed = TRUE
  }
  if (!changed) return(text)
  nb_serialize(nb)
}

# ---- the format registry -------------------------------------------------------------------------

#' The five built-in doc_format specs (contract 7.15, 10.2 row 18)
#' @noRd
doc_formats_builtin = function() {
  list(
    r = gptr_spec("doc_format", "r", ext = c("R", "r"), locate = doc_r_locate,
                  render = doc_r_render, upsert = doc_r_upsert, inert = doc_marker_inert),
    rmd = gptr_spec("doc_format", "rmd", ext = c("Rmd", "rmd"), locate = doc_rmd_locate,
                    render = doc_r_render, upsert = doc_rmd_upsert_fn("rmd"),
                    inert = doc_marker_inert),
    qmd = gptr_spec("doc_format", "qmd", ext = "qmd", locate = doc_rmd_locate,
                    render = doc_r_render, upsert = doc_rmd_upsert_fn("qmd"),
                    inert = doc_marker_inert),
    ipynb = gptr_spec("doc_format", "ipynb", ext = "ipynb", locate = doc_ipynb_locate,
                      render = doc_ipynb_render, upsert = doc_ipynb_upsert,
                      inert = doc_ipynb_inert),
    transcript = gptr_spec("doc_format", "transcript", ext = c("R", "r"),
                           locate = doc_transcript_locate, render = doc_r_render,
                           upsert = doc_transcript_upsert, inert = doc_marker_inert)
  )
}

#' A doc_format spec by name: the registered one, else the built-in (before builtin:documents
#' is loaded); NULL when builtin:documents is filtered out and nothing else provides it
#' @noRd
doc_format_get = function(name) {
  if (is.null(name)) return(NULL)
  spec = tryCatch(registry_get("doc_format", name), error = function(e) NULL)
  if (!is.null(spec)) return(spec)
  if (length(tryCatch(registry_names("doc_format"), error = function(e) character()))) {
    return(NULL)
  }
  doc_formats_builtin()[[name]]
}

#' Text of a document with the given blocks made inert or live again (G7 sections 3.8, 4.4);
#' in transcripts the owning `s_<hex>` statement line is prefixed too
#' @noRd
doc_inert_text = function(lines, fmt, ids, inert = TRUE, transcript = FALSE) {
  if (identical(fmt, "ipynb")) return(nb_inert_text(lines, ids, inert))
  for (id in ids) {
    b = doc_find_blocks(lines)
    k = which(b$id == id)
    if (!length(k)) next
    rng = b$start[k[1L]]:b$end[k[1L]]
    lines[rng] = doc_inert_marker_lines(lines[rng], inert)
    if (transcript) {
      p = b$start[k[1L]] - 1L
      while (p >= 1L && !nzchar(trimws(lines[p]))) p = p - 1L
      if (p >= 1L && grepl("^(#~ )?s_[0-9a-f]{6} (=|\\|>) peter\\(", lines[p])) {
        lines[p] = if (inert) sub("^(#~ )?", "#~ ", lines[p]) else sub("^#~ ", "", lines[p])
      }
    }
    if (fmt %in% c("rmd", "qmd")) lines = doc_rmd_chunk_eval(lines, id, inert, fmt)
  }
  lines
}

# ---- inert blocks on disk (G7 section 3.8) -------------------------------------------------------

#' One block's lines made inert or live again (G7 section 3.8), in the form a format's upsert()
#' takes: a marker block through doc_inert_marker_lines(); a notebook cell's source (its
#' `metadata.gptr` as attribute `meta`) gets or loses its `#~ ` prefixes and the meta its status
#' "undone". Lines already in the requested state are returned unchanged.
#' @noRd
doc_inert_block_lines = function(lines, fmt, inert = TRUE) {
  if (!identical(fmt, "ipynb")) {
    new = doc_inert_marker_lines(as.character(lines), inert)
    return(if (identical(new, as.character(lines))) lines else new)
  }
  meta = attr(lines, "meta", exact = TRUE)
  if (!is.list(meta)) meta = list()
  if (identical(meta[["status"]], "undone") == isTRUE(inert)) return(lines)
  src = as.character(lines)
  src = if (inert) doc_ipynb_inert(src) else sub("^#~ ", "", src)
  meta[["status"]] = if (inert) "undone" else NULL
  structure(src, meta = meta[order(names(meta), method = "radix")])
}

#' The lines of block `id` as a document's text holds it, in the form its format's upsert()
#' takes: a marker block without its indentation, or a notebook cell's source with its
#' `metadata.gptr` as attribute `meta`; NULL when the text holds no such block
#' @noRd
doc_disk_block_lines = function(fmt, text, id) {
  if (identical(fmt, "ipynb")) {
    nb = nb_parse(text)
    k = match(paste0("gptr-", id), nb_cell_ids(nb))
    if (is.na(k)) return(NULL)
    cell = nb[["cells"]][[k]]
    return(structure(nb_cell_lines(cell), meta = nb_cell_meta(cell)))
  }
  b = doc_find_blocks(text)
  k = which(b$id == id)
  if (!length(k)) return(NULL)
  seg = text[b$start[k[1L]]:b$end[k[1L]]]
  ind = b$indent[k[1L]]
  if (nzchar(ind)) seg = ifelse(startsWith(seg, ind), substring(seg, nchar(ind) + 1L), seg)
  seg
}

#' Make blocks of a document inert (undone) or live again, under write consent, the document
#' lock, the `document_write` event (kind "inert") and the md5 check; TRUE when written.
#' `transcript` (NULL: a file under .gptr/transcripts/) also makes the owning `s_<hex>` statement
#' of a console turn inert, wherever the transcript lives (an IDE's active document). A notebook
#' open in this Jupyter kernel (IC-50) and the script this process runs under Rscript (D-109)
#' are never written: their blocks change in this process's queue (doc_pending_inert()), which
#' gptr_doc(path, sync = TRUE) or the exit writes; TRUE when the queue changed.
#' @noRd
doc_set_inert = function(path, ids, inert = TRUE, session = NULL, transcript = NULL) {
  if (!file.exists(path) || !length(ids) || !doc_consent(path, ask = FALSE)) {
    return(invisible(FALSE))
  }
  fmt = doc_format_of(path)
  if (is.null(fmt)) return(invisible(FALSE))
  kind = doc_queue_kind(path)
  if (!is.null(kind)) {
    return(invisible(doc_pending_inert(path_norm(path), fmt, ids, inert, kind, session)))
  }
  transcript = transcript %||% startsWith(doc_rel(path), ".gptr/transcripts/")
  lock = doc_lock(path)
  if (is.null(lock)) return(invisible(FALSE))
  on.exit(doc_unlock(lock), add = TRUE)
  for (attempt in 1:3) {
    doc = doc_read(path)
    new = doc_inert_text(doc$lines, fmt, ids, inert, transcript)
    if (identical(new, doc$lines)) return(invisible(FALSE))
    ev = doc_event(path, fmt, "inert", paste(ids, collapse = ","), new, session)
    if (isTRUE(ev$block)) return(invisible(FALSE))
    ok = tryCatch({
      doc_write(doc, ev$lines %||% new)
      TRUE
    }, gptr_error_doc_write = function(e) {
      if (identical(e$reason, "conflict")) FALSE else stop(e)
    })
    if (ok) return(invisible(TRUE))
  }
  invisible(FALSE)
}

# ---- builtin:documents (contract 7.15, 10.3; IC-34, IC-68) -------------------------------------

#' The `documents` prompt section text (architecture 7.3, byte for byte; P07 replaces `{s1}`)
#' @noRd
doc_section_body = paste(c(
  paste0("Code from successful r calls is written into the user's document (named in ",
         "<environment>) in a block below the peter() call that asked for it, so the document ",
         "re-runs from top to bottom. Therefore:"),
  paste0("- Make recorded code the clean final version: named objects, no exploratory prints. ",
         "Pass record = false for throwaway checks (head(), summaries, tests)."),
  paste0("- Record key modelling decisions with note (one line, written as \"## Decision: ...\"); ",
         "key printed outputs are added as #> comments automatically."),
  paste0("- To change code you wrote earlier, edit that block in the document instead of ",
         "appending a second version."),
  paste0("- In the document, prompts are quoted strings in peter(\"...\"), and System 1 decisions ",
         "are peter(..., model = {s1}) inside if, for or while. Add such calls only when the user ",
         "asks for an agent step in the script.")
), collapse = "\n")

#' The `documents` section (contract 9.3: T0, order 500, budget 250): only when a history
#' document is bound (`ctx$input$document`, from the doc.site service)
#' @noRd
doc_section_text = function(ctx) {
  if (is.null(ctx$input$document)) return(NULL)
  doc_section_body
}

#' builtin:documents: the five doc formats, the route `document` (order 50), the `documents`
#' prompt section, the agent_end and session_tree hooks and the handlers of P14's
#' console:command and console:direct channels; the doc.* services are registered below with
#' `builtin = "documents"`, so filtering the built-in removes them too
#' @noRd
builtin_documents = function(gptr) {
  for (spec in doc_formats_builtin()) gptr$register(spec)
  gptr$register(gptr_spec("route", "document", order = 50, match = doc_route_match,
                          run = doc_route_run,
                          description = paste("a call located in a history document: replay",
                                              "its fresh block or record its new one")))
  gptr$register(gptr_prompt_section("documents", doc_section_text, tier = "T0", order = 500L,
                                    budget = 250L))
  gptr$on("agent_end", doc_on_agent_end)
  gptr$on("session_tree", doc_on_session_tree)
  gptr$on("console:command", doc_on_console_command)
  gptr$on("console:direct", doc_on_console_direct)
  invisible(NULL)
}

on_load(ext_declare_builtin("documents", builtin_documents))
on_load(ext_service_set("doc.site", doc_site_service, provided_by = "P15", builtin = "documents"))
on_load(ext_service_set("doc.edit", doc_edit_service, provided_by = "P15", builtin = "documents"))
on_load(ext_service_set("doc.s1_block", doc_s1_block_service, provided_by = "P15",
                        builtin = "documents"))
on_load(ext_service_set("doc.replay", doc_replay_service, provided_by = "P15",
                        builtin = "documents"))
