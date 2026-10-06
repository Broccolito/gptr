# `peter$grep()`, `peter$find()`, `peter$ls()` and the direct `grep`, `find`, `ls` tools (P10;
# research 11 section 5.5, research 21 section 2.1): batched readChar() reads, a whole-file
# prefilter, per-line PCRE with `(*UTF)(*UCP)`, early stop at the limit, radix sorting (REQ-08)
# and Pi's texts; PCRE match-limit warnings are reported as incomplete results (report 11 section
# 7.1).

grep_default_limit = 100L
find_default_limit = 1000L
ls_default_limit = 500L
grep_max_line = 500L
grep_max_file = 20 * 1024^2

#' Batch reader: UTF-8 texts with LF line endings, NA for binary files (a NUL truncates readChar(),
#' so `nchar < size` detects binary files anywhere in the file, ripgrep's rule)
#' @noRd
search_read_texts = function(files, sizes) {
  txt = vapply(seq_along(files), function(k) {
    if (sizes[k] <= 0) return("")
    x = tryCatch(suppressWarnings(readChar(fs_path(files[k]), sizes[k], useBytes = TRUE)),
                 error = function(e) character())
    if (!length(x) || nchar(x, "bytes") < sizes[k]) NA_character_ else x
  }, "")
  for (k in which(is.na(txt))) {
    head = tryCatch(read_raw(files[k], n = min(4, sizes[k])), error = function(e) raw(0))
    bom = sniff_bom(head)
    if (nzchar(bom) && bom != "UTF-8") {
      txt[k] = tryCatch(decode_raw(read_raw(files[k]))$text, error = function(e) NA_character_)
    }
  }
  ok = !is.na(txt)
  bom8 = which(ok & grepl("^\xef\xbb\xbf", txt, perl = TRUE, useBytes = TRUE))
  if (length(bom8)) txt[bom8] = sub("^\xef\xbb\xbf", "", txt[bom8], perl = TRUE, useBytes = TRUE)
  for (k in which(ok & !validUTF8(txt))) txt[k] = decode_raw(charToRaw(txt[k]))$text
  cr = which(ok & grepl("\r", txt, fixed = TRUE, useBytes = TRUE))
  if (length(cr)) txt[cr] = gsub("\r\n", "\n", txt[cr], fixed = TRUE, useBytes = TRUE)
  utf8_mark(txt)
}

#' Matcher, prefilter and locator of a pattern; `state$incomplete` records PCRE match-limit warnings
#' @noRd
grep_prepare = function(pattern, fixed = FALSE, ignore_case = FALSE) {
  state = new.env(parent = emptyenv())
  state$incomplete = FALSE
  # A PCRE call with warnings muffled; `failed`: one was raised (a match or depth limit gives FALSE)
  pcre_run = function(expr_fun) {
    flag = new.env(parent = emptyenv())
    flag$failed = FALSE
    value = withCallingHandlers(expr_fun(), warning = function(w) {
      flag$failed = TRUE
      invokeRestart("muffleWarning")
    })
    list(value = value, failed = flag$failed)
  }
  quiet = function(expr_fun) {
    r = pcre_run(expr_fun)
    if (r$failed) state$incomplete = TRUE
    r$value
  }
  if (isTRUE(fixed) && !isTRUE(ignore_case)) {
    matcher = function(x) grepl(pattern, x, fixed = TRUE, useBytes = TRUE)
    return(list(matcher = matcher, prefilter = matcher, state = state,
                locator = function(x) as.integer(regexpr(pattern, x, fixed = TRUE))))
  }
  rx = pattern
  if (isTRUE(fixed)) rx = paste0("\\Q", gsub("\\E", "\\E\\\\E\\Q", pattern, fixed = TRUE), "\\E")
  utf = if (grepl("^\\(\\*UTF", rx)) "" else "(*UTF)(*UCP)"
  seen = new.env(parent = emptyenv())
  on_warning = function(w) {
    seen$warning = conditionMessage(w)
    invokeRestart("muffleWarning")
  }
  compile = function() {
    withCallingHandlers(grepl(paste0(utf, rx), "", perl = TRUE), warning = on_warning)
  }
  res = tryCatch(compile(), error = function(e) e)
  if (inherits(res, "error")) {
    why = seen$warning %||% conditionMessage(res)
    why = trimws(sub("^PCRE pattern compilation error\\s*", "", why))
    gptr_abort(paste0("regex parse error: ", gsub("\\s+", " ", why), " (pattern: ", pattern, ")"),
               "invalid_argument", arg = "pattern",
               expected = "a valid Perl-compatible regular expression")
  }
  ic = isTRUE(ignore_case)
  full = paste0(utf, rx)
  matcher = function(x) quiet(function() grepl(full, x, perl = TRUE, ignore.case = ic))
  # The prefilter must keep every file the per-line matcher matches, so it is off for constructs
  # a "\n" beyond the line edge can change: subject anchors, verbs, negative lookaround, atomic
  # groups, conditionals, (?s)/(?-m)/(?^), possessive quantifiers (and `\Q`, `\E`, `(?#`, `x` white
  # space before their `+`) and backreferences. Over-matching only costs speed.
  unsafe = !isTRUE(fixed) &&
    grepl(paste0("\\\\[AzZG1-9gkQE]|\\(\\*|\\(\\?(<?!|>|\\(|#|P=|[a-zA-Z]*[-^sx])",
                 "|([*+?]|\\{[0-9,[:space:]]*\\})\\+"), rx)
  prefilter = if (unsafe) {
    function(x) rep(TRUE, length(x))
  } else {
    pre = paste0(utf, "(?m)", rx)
    whole = function(x) pcre_run(function() grepl(pre, x, perl = TRUE, ignore.case = ic))
    # A PCRE limit on a whole file says nothing about its lines: after a failed batch each file is
    # tried alone, and those hitting the limit go to the per-line matcher
    function(x) {
      r = whole(x)
      if (!r$failed) return(r$value)
      vapply(x, function(text) {
        one = whole(text)
        one$failed || one$value
      }, NA, USE.NAMES = FALSE)
    }
  }
  # A failed locate (a PCRE match-limit error included) gives -1: the window starts the line
  locator = function(x) {
    at = suppressWarnings(as.integer(regexpr(full, x, perl = TRUE, ignore.case = ic)))
    at[is.na(at)] = -1L
    at
  }
  list(matcher = matcher, prefilter = prefilter, state = state, locator = locator)
}

#' Engine: data.frame(file, abs, line, text) of up to `limit` matching lines, files in the given
#' order, in batches of at most 256 files or 4 MB (early stop at the limit)
#' @noRd
grep_engine = function(files, labels, eng, limit, sizes, batch_files = 256L,
                       batch_bytes = 4 * 1024^2) {
  sizes[is.na(sizes)] = 0
  batch = cummax(pmax(cumsum(sizes) %/% batch_bytes, (seq_along(files) - 1L) %/% batch_files))
  res = list()
  n = 0L
  n_bin = 0L
  for (bi in unique(batch)) {
    idx = which(batch == bi)
    texts = search_read_texts(files[idx], sizes[idx])
    bin = is.na(texts)
    n_bin = n_bin + sum(bin & sizes[idx] > 0)
    idx = idx[!bin]
    texts = texts[!bin]
    if (!length(idx)) next
    cand = eng$prefilter(texts)
    idx = idx[cand]
    texts = texts[cand]
    if (!length(idx)) next
    pieces = strsplit(texts, "\n", fixed = TRUE, useBytes = TRUE)
    lines = utf8_mark(unlist(pieces, use.names = FALSE))
    fid = rep(idx, lengths(pieces))
    lno = sequence(lengths(pieces))
    hit = which(eng$matcher(lines))
    if (!length(hit)) next
    take = hit[seq_len(min(length(hit), limit - n))]
    res[[length(res) + 1L]] = data.frame(file = labels[fid[take]], abs = files[fid[take]],
                                         line = lno[take], text = lines[take],
                                         stringsAsFactors = FALSE)
    n = n + length(take)
    if (n >= limit) break
  }
  out = if (length(res)) {
    do.call(rbind, res)
  } else {
    data.frame(file = character(), abs = character(), line = integer(), text = character(),
               stringsAsFactors = FALSE)
  }
  attr(out, "limit_reached") = n >= limit
  attr(out, "binary_skipped") = n_bin
  out
}

#' Last component of "/"-separated paths, marked UTF-8 (basename() cannot translate a marked
#' non-ASCII path in a non-UTF-8 locale)
#' @noRd
search_basename = function(paths) as_utf8(sub("(?s)^.*/", "", paths, perl = TRUE))

#' Candidate files of a search root: the walker, a glob filter (comma list, `!` excludes), the 20 MB
#' cap and the file order (path, or mtime newest first)
#' @noRd
grep_candidates = function(root, glob = NULL, sort = "path") {
  if (!dir.exists(fs_path(root))) {
    return(list(files = root, labels = search_basename(root), sizes = file.size(fs_path(root)),
                skipped_big = 0L, mtime = file.mtime(fs_path(root))))
  }
  w = walk_files(root, type = "file", hidden = TRUE)
  if (!is.null(glob) && nzchar(glob)) {
    gl = trimws(strsplit(glob, ",(?![^{]*})", perl = TRUE)[[1L]])
    gl = gl[nzchar(gl)]
    inc = gl[!startsWith(gl, "!")]
    exc = substring(gl[startsWith(gl, "!")], 2L)
    keep = if (length(inc)) {
      Reduce(`|`, lapply(inc, function(g) grepl(glob_to_regex(g), w$path, perl = TRUE)))
    } else {
      rep(TRUE, nrow(w))
    }
    for (g in exc) keep = keep & !grepl(glob_to_regex(g), w$path, perl = TRUE)
    w = w[keep, , drop = FALSE]
  }
  big = !is.na(w$size) & w$size > grep_max_file
  w = w[!big, , drop = FALSE]
  if (identical(sort, "mtime")) {
    w = w[order(-as.numeric(w$mtime), tolower(w$path), w$path, method = "radix"), , drop = FALSE]
  }
  list(files = file.path(attr(w, "root"), w$path), labels = w$path, sizes = w$size,
       skipped_big = sum(big), mtime = w$mtime)
}

#' Search file contents: behind `peter$grep()` and the direct `grep` tool (contract 7.10)
#' Returns `gptr_matches` (`file`, `line`, `text`), `gptr_files` or a `file`, `n` data frame by
#' `output`; attributes `truncated`, `limit`, `root`, `skipped_big`, `binary_skipped`, `incomplete`.
#' @noRd
search_grep = function(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE,
                       context = 0L, limit = 100L, output = c("content", "files", "count"),
                       sort = c("path", "count", "mtime")) {
  check_string(pattern, "pattern")
  check_string(path, "path")
  check_string(glob, "glob", null = TRUE, empty = TRUE)
  check_flag(ignore_case, "ignore_case")
  check_flag(fixed, "fixed")
  context = check_number(context, "context", min = 0, int = TRUE)
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  output = check_choice(output, c("content", "files", "count"), "output")
  sort = check_choice(sort, c("path", "count", "mtime"), "sort")
  root = resolve_tool_path(path)
  if (!file.exists(fs_path(root))) {
    gptr_abort(paste0("Path not found: ", root), "invalid_argument", arg = "path",
               expected = "an existing file or directory")
  }
  eng = grep_prepare(as_utf8(pattern), fixed = fixed, ignore_case = ignore_case)
  content = identical(output, "content")
  cand = grep_candidates(root, glob, sort = if (content) "path" else sort)
  m = grep_engine(cand$files, cand$labels, eng, if (content) limit else .Machine$integer.max,
                  sizes = cand$sizes)
  common = list(root = root, skipped_big = cand$skipped_big,
                binary_skipped = attr(m, "binary_skipped"),
                incomplete = isTRUE(eng$state$incomplete), limit = limit)
  if (content) {
    ctx_rows = if (context > 0L && nrow(m)) grep_context_rows(m, context) else NULL
    out = data.frame(file = m$file, line = as.integer(m$line), text = m$text,
                     stringsAsFactors = FALSE)
    head = list(out, class = c("gptr_matches", "data.frame"),
                truncated = isTRUE(attr(m, "limit_reached")), context = ctx_rows,
                locator = eng$locator)
    return(do.call(structure, c(head, common)))
  }
  counts = table(factor(m$file, levels = unique(m$file)))
  df = data.frame(file = names(counts), n = as.integer(counts), stringsAsFactors = FALSE)
  if (identical(sort, "count")) {
    df = df[order(-df$n, tolower(df$file), df$file, method = "radix"), , drop = FALSE]
  }
  truncated = nrow(df) > limit
  df = utils::head(df, limit)
  rownames(df) = NULL
  if (identical(output, "count")) {
    return(do.call(structure, c(list(df, truncated = truncated), common)))
  }
  hit = match(df$file, cand$labels)
  files = data.frame(path = df$file, size = as.numeric(cand$sizes[hit]), mtime = cand$mtime[hit],
                     type = rep("file", nrow(df)), stringsAsFactors = FALSE)
  head = list(files, class = c("gptr_files", "data.frame"), truncated = truncated)
  do.call(structure, c(head, common))
}

#' Context lines around matches (the matching lines themselves excluded)
#' @noRd
grep_context_rows = function(m, context) {
  rows = list()
  for (f in unique(m$file)) {
    mm = m[m$file == f, , drop = FALSE]
    txt = search_read_texts(mm$abs[1L], file.size(fs_path(mm$abs[1L])))
    lines = if (is.na(txt)) character() else split_lines_count(txt)
    around = function(h) max(1L, h - context):min(length(lines), h + context)
    want = sort(unique(unlist(lapply(mm$line, around))))
    want = setdiff(want, mm$line)
    if (length(want)) {
      rows[[length(rows) + 1L]] = data.frame(file = f, line = as.integer(want), text = lines[want],
                                             stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

#' Cap long lines at 500 characters, keeping a window around the first match visible (report 11)
#' @noRd
grep_cap_lines = function(x, locator = NULL, max_chars = grep_max_line) {
  n = nchar(x, type = "chars", allowNA = TRUE)
  long = !is.na(n) & n > max_chars
  if (!any(long)) return(structure(x, truncated = long))
  start = rep(1L, length(x))
  if (is.function(locator)) {
    ctr = pmax(0L, locator(x[long]) - 1L)
    start[long] = pmax(1L, pmin(ctr - max_chars %/% 5L, n[long] - max_chars + 1L))
  }
  x[long] = paste0(ifelse(start[long] > 1L, "...", ""),
                   substr(x[long], start[long], start[long] + max_chars - 1L), "... [truncated]")
  structure(utf8_mark(x), truncated = long)
}

#' Pi-format lines of matches: `file:N: text`, context `file-N- text`, merged blocks separated by
#' `--`
#' @noRd
grep_format_lines = function(m) {
  if (!nrow(m)) return(list(lines = character(), truncated = FALSE))
  ctx = attr(m, "context")
  all = data.frame(file = m$file, line = m$line, text = m$text, match = TRUE,
                   stringsAsFactors = FALSE)
  if (!is.null(ctx) && nrow(ctx)) {
    all = rbind(all, data.frame(file = ctx$file, line = ctx$line, text = ctx$text, match = FALSE,
                                stringsAsFactors = FALSE))
  }
  first = match(all$file, unique(m$file))
  all = all[order(first, all$line, method = "radix"), , drop = FALSE]
  t = grep_cap_lines(all$text, attr(m, "locator"))
  body = ifelse(all$match, sprintf("%s:%d: %s", all$file, all$line, t),
                sprintf("%s-%d- %s", all$file, all$line, t))
  if (!is.null(ctx) && nrow(ctx)) {
    gap = c(FALSE, (all$file[-1L] != all$file[-nrow(all)]) | (diff(all$line) > 1L))
    body = as.vector(rbind(ifelse(gap, "--", NA_character_), body))
    body = body[!is.na(body)]
  }
  list(lines = utf8_mark(body), truncated = any(attr(t, "truncated")))
}

#' Head lines within the 50 KB byte limit (Pi truncateHead without a line limit)
#' @noRd
head_bytes = function(lines, max_bytes = tool_max_bytes) {
  tr = truncate_lines_head(lines, max_lines = .Machine$integer.max, max_bytes = max_bytes)
  list(lines = tr$lines, truncated = tr$truncated)
}

#' Pi's notice form: the text, a blank line, then the notes joined by ". " inside square brackets
#' @noRd
with_notices = function(text, notes) {
  if (!length(notes)) return(text)
  paste0(text, "\n\n[", paste(notes, collapse = ". "), "]")
}

#' Direct `grep` tool text (Pi's format and notices, report 11's extra notices)
#' @noRd
grep_tool_text = function(m) {
  big = search_skipped_note(m)
  incomplete = if (isTRUE(attr(m, "incomplete"))) {
    "The pattern was too expensive on some lines; results may be incomplete"
  }
  if (!nrow(m)) return(with_notices("No matches found", c(big, incomplete)))
  fm = grep_format_lines(m)
  tr = head_bytes(fm$lines)
  limit = attr(m, "limit")
  notes = c(
    if (isTRUE(attr(m, "truncated"))) {
      paste0(limit, " matches limit reached. Use limit=", limit * 2L,
             " for more, or refine pattern")
    },
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached"),
    if (fm$truncated) {
      paste0("Some lines truncated to ", grep_max_line, " chars. Use read tool to see full lines")
    },
    big,
    incomplete
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' Relevance classes of a name query (IC-71): 1 exact basename, 2 prefix, 3 substring, 4
#' subsequence, NA no match; glob characters are ignored
#' @noRd
find_relevance = function(query, paths) {
  q = tolower(gsub("[*?]", "", query))
  base = tolower(search_basename(paths))
  stem = path_sans_ext(base)
  cls = rep(NA_integer_, length(paths))
  if (!nzchar(q)) return(rep(4L, length(paths)))
  cls[base == q | stem == q] = 1L
  cls[is.na(cls) & startsWith(base, q)] = 2L
  cls[is.na(cls) & grepl(q, base, fixed = TRUE)] = 3L
  chars = strsplit(q, "", fixed = TRUE)[[1L]]
  rx = paste(gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", chars, perl = TRUE), collapse = ".*")
  cls[is.na(cls) & grepl(rx, base, perl = TRUE)] = 4L
  cls
}

#' Find files by glob: behind `peter$find()` and the direct `find` tool (contract 7.10)
#' A glob has fd semantics (smart case); `sort = "relevance"` takes a name query instead. Returns
#' `gptr_files` (`path` relative to the root, `size`, `mtime`, `type`).
#' @noRd
search_find = function(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"),
                       type = "file", limit = 1000L) {
  check_string(pattern, "pattern")
  check_string(path, "path")
  sort = check_choice(sort, c("path", "mtime", "size", "relevance"), "sort")
  type = check_choice(type, c("file", "dir", "any"), "type")
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  root = resolve_tool_path(path)
  if (!dir.exists(fs_path(root))) {
    gptr_abort(paste0("Path not found: ", root), "invalid_argument", arg = "path",
               expected = "an existing directory")
  }
  w = walk_files(root, type = type, hidden = TRUE)
  pattern = as_utf8(pattern)
  if (identical(sort, "relevance")) {
    cls = find_relevance(pattern, w$path)
    keep = !is.na(cls)
    w = w[keep, , drop = FALSE]
    cls = cls[keep]
    w = w[order(cls, tolower(w$path), w$path, method = "radix"), , drop = FALSE]
  } else {
    if (!(pattern %in% c("**", "*", "**/*"))) {
      ic = !grepl("[[:upper:]]", pattern)
      w = w[grepl(glob_to_regex(pattern), w$path, perl = TRUE, ignore.case = ic), , drop = FALSE]
    }
    ord = switch(sort,
                 path = order(tolower(w$path), w$path, method = "radix"),
                 mtime = order(-as.numeric(w$mtime), tolower(w$path), w$path, method = "radix"),
                 size = order(-w$size, tolower(w$path), w$path, method = "radix", na.last = TRUE))
    w = w[ord, , drop = FALSE]
  }
  truncated = nrow(w) > limit
  w = utils::head(w, limit)
  rownames(w) = NULL
  structure(w, class = c("gptr_files", "data.frame"), root = root, truncated = truncated,
            limit = limit)
}

#' Direct `find` tool text (Pi's format: relative paths, "/" after directories, notices)
#' @noRd
find_tool_text = function(f) {
  if (!nrow(f)) return("No files found matching pattern")
  tr = head_bytes(paste0(f$path, ifelse(f$type == "dir", "/", "")))
  limit = attr(f, "limit")
  notes = c(
    if (isTRUE(attr(f, "truncated"))) {
      paste0(limit, " results limit reached. Use limit=", limit * 2L,
             " for more, or refine pattern")
    },
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached")
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' List a directory: behind `peter$ls()` and the direct `ls` tool (contract 7.10)
#' Dot-files included, entries that cannot be stat-ed dropped (Pi), names that are not valid UTF-8
#' skipped and counted in attribute `invalid_names`, as the walker does.
#' @noRd
search_ls = function(path = ".", sort = c("name", "mtime", "size"), long = FALSE) {
  check_string(path, "path")
  sort = check_choice(sort, c("name", "mtime", "size"), "sort")
  check_flag(long, "long")
  dir = resolve_tool_path(path)
  p = fs_path(dir)
  if (!file.exists(p)) {
    gptr_abort(paste0("Path not found: ", dir), "invalid_argument", arg = "path",
               expected = "an existing directory")
  }
  if (!dir.exists(p)) {
    gptr_abort(paste0("Not a directory: ", dir), "invalid_argument", arg = "path",
               expected = "a directory")
  }
  nm = walk_list_dir(dir)
  bad = !validUTF8(nm)
  nm = as_utf8(nm[!bad])
  full = file.path(dir, nm)
  fi = file.info(fs_path(full), extra_cols = FALSE)
  lnk = Sys.readlink(fs_path(full))
  is_dir = fi$isdir %in% TRUE
  kind = ifelse(!is.na(lnk) & nzchar(lnk), "link", ifelse(is_dir, "dir", "file"))
  df = data.frame(path = nm, size = ifelse(is_dir, NA_real_, as.numeric(fi$size)), mtime = fi$mtime,
                  type = kind, stringsAsFactors = FALSE)
  keep = !is.na(fi$isdir)
  df = df[keep, , drop = FALSE]
  slash = is_dir[keep]
  ord = switch(sort,
               name = order(tolower(df$path), df$path, method = "radix"),
               mtime = order(-as.numeric(df$mtime), tolower(df$path), method = "radix"),
               size = order(-df$size, tolower(df$path), method = "radix", na.last = TRUE))
  df = df[ord, , drop = FALSE]
  slash = slash[ord]
  rownames(df) = NULL
  structure(df, class = c("gptr_files", "data.frame"), root = dir, long = long, truncated = FALSE,
            limit = NA_integer_, slash = slash, invalid_names = sum(bad))
}

#' Direct `ls` tool text (Pi's format and notices) of a search_ls() listing
#' @noRd
ls_tool_text = function(f, limit = ls_default_limit) {
  if (!nrow(f)) return("(empty directory)")
  slash = attr(f, "slash") %||% (f$type == "dir")
  reached = nrow(f) > limit
  keep = seq_len(min(nrow(f), limit))
  tr = head_bytes(paste0(f$path[keep], ifelse(slash[keep], "/", "")))
  notes = c(
    if (reached) paste0(limit, " entries limit reached. Use limit=", limit * 2L, " for more"),
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached")
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' Print grep matches in Pi's format within the member budget
#'
#' @param x A `gptr_matches` data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_matches = function(x, ...) {
  if (!nrow(x)) {
    notes = c(search_skipped_note(x), search_incomplete_note(x))
    ns_print_lines(c("No matches found", search_notice_line(notes)))
    return(invisible(x))
  }
  fm = grep_format_lines(x)
  shown = budget_head(fm$lines, member_budget())
  limit = attr(x, "limit")
  notes = c(
    if (shown$omitted > 0L) paste0(shown$omitted, " more lines not printed; subset the value"),
    if (isTRUE(attr(x, "truncated"))) {
      paste0(limit, " matches limit reached; use limit = ", limit * 2L, " for more")
    },
    search_skipped_note(x),
    search_incomplete_note(x)
  )
  ns_print_lines(c(shown$lines, search_notice_line(notes)))
  invisible(x)
}

#' The incomplete note of a print (a PCRE match-limit failure during `search_grep()`), or NULL
#' @noRd
search_incomplete_note = function(x) {
  if (isTRUE(attr(x, "incomplete"))) {
    "the pattern was too expensive on some lines; results may be incomplete"
  }
}

#' The skipped-files note of a grep result or print (files larger than 20 MB skipped by
#' `search_grep()`), or NULL
#' @noRd
search_skipped_note = function(x) {
  if (isTRUE(attr(x, "skipped_big") > 0L)) {
    paste0(attr(x, "skipped_big"), " file(s) larger than 20MB skipped")
  }
}

#' The bracketed notice line of a print, or NULL without notes
#' @noRd
search_notice_line = function(notes) {
  if (length(notes)) paste0("[", paste(notes, collapse = ". "), "]")
}

#' Print a file listing (paths, "/" after directories; size and time with `long`) within the member
#' budget
#'
#' @param x A `gptr_files` data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_files = function(x, ...) {
  if (!nrow(x)) {
    notes = c(search_skipped_note(x), search_incomplete_note(x))
    ns_print_lines(c("(no files)", search_notice_line(notes)))
    return(invisible(x))
  }
  slash = attr(x, "slash") %||% (x$type == "dir")
  lines = paste0(x$path, ifelse(slash, "/", ""))
  if (isTRUE(attr(x, "long"))) {
    size = vapply(x$size, function(s) if (is.na(s)) "-" else format_size(s), "")
    lines = sprintf("%8s  %s  %s", size, format(x$mtime, "%Y-%m-%d %H:%M"), lines)
  }
  shown = budget_head(lines, member_budget())
  limit = attr(x, "limit")
  notes = c(
    if (shown$omitted > 0L) paste0(shown$omitted, " more entries not printed; subset the value"),
    if (isTRUE(attr(x, "truncated"))) {
      paste0("limit of ", limit, " reached; use limit = ", limit * 2L, " for more")
    },
    search_skipped_note(x),
    search_incomplete_note(x)
  )
  ns_print_lines(c(shown$lines, search_notice_line(notes)))
  invisible(x)
}
