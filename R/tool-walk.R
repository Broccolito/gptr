# Tool path resolution, glob to PCRE, the .gitignore engine and the pruned walker (P10; an L4
# service P11, P16 and P18 use, contract 7.10; research 11 section 5.5): Pi's `**/` prefix for
# patterns with "/", path.expand() only for "~", "~/" and "~\", and no probe file written to detect
# a case-insensitive file system.

walk_default_prune = c(".git/", "node_modules/", ".Rproj.user/", "renv/library/", "renv/staging/",
                       "renv/sandbox/", "packrat/lib*/", "packrat/src/", ".venv/", "__pycache__/",
                       ".ipynb_checkpoints/", ".quarto/")
walk_ignore_files = c(".gitignore", ".ignore", ".gptrignore")
walk_max_entries = 500000L

#' Path handed to base file-system functions: UTF-8 bytes without a mark in non-UTF-8 Unix locales
#' (a marked non-ASCII path fails there with "unable to translate"; report 01 E4)
#' @noRd
fs_path = function(p) {
  if (.Platform$OS.type != "windows" && !isTRUE(l10n_info()[["UTF-8"]])) Encoding(p) = "unknown"
  p
}

#' Resolve a model- or user-supplied path to an absolute, normalised path (Pi resolveToCwd; report
#' 11 section 2.8): Unicode spaces become " ", one leading "@" is dropped, file:// URLs are decoded,
#' Git-Bash and WSL drive paths are rewritten on Windows, "~" is expanded (only "~", "~/", "~\\").
#' @noRd
resolve_tool_path = function(path, cwd = getwd()) {
  p = as_utf8(path)
  cp = utf8ToInt(p)
  spaces = c(0xA0L, 0x2000:0x200A, 0x202FL, 0x205FL, 0x3000L)
  if (length(cp) && !anyNA(cp) && any(cp %in% spaces)) {
    cp[cp %in% spaces] = 32L
    p = intToUtf8(cp)
  }
  if (startsWith(p, "@")) p = substring(p, 2L)
  if (grepl("^file://", p)) {
    p = utils::URLdecode(sub("^file://(localhost)?", "", p))
    if (.Platform$OS.type == "windows") p = sub("^/([A-Za-z]:)", "\\1", p)
  }
  if (.Platform$OS.type == "windows" && grepl("^/(mnt/|cygdrive/)?[A-Za-z](/|$)", p) &&
        !startsWith(p, "//")) {
    p = sub("^/(mnt/|cygdrive/)?([A-Za-z])(/|$)", "\\2:/", p)
  }
  if (p == "~" || startsWith(p, "~/") || startsWith(p, "~\\")) p = as_utf8(path.expand(fs_path(p)))
  if (.Platform$OS.type == "windows" && grepl("^[A-Za-z]:[^/\\\\]", p)) {
    p = normalizePath(p, winslash = "/", mustWork = FALSE)
  }
  if (!is_abs_path(p)) p = paste0(as_utf8(cwd), "/", p)
  path_lexical(p)
}

#' Character classes git's wildmatch knows (PCRE also knows "ascii" and "word", accepted in globs)
#' @noRd
glob_posix = c("alnum", "alpha", "blank", "cntrl", "digit", "graph", "lower", "print", "punct",
               "space", "upper", "xdigit")

#' ASCII punctuation, emitted backslash-escaped inside a class (always a literal in PCRE)
#' @noRd
glob_punct = strsplit("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", "", fixed = TRUE)[[1L]]

#' Translate the bracket expression opening at `ch[i]` (git's wildmatch rules): `list(end, re)`
#' NULL when unclosed; `re = NA` when wildmatch matches nothing (`git = TRUE`, unknown class), where
#' a glob errors instead (also on a reversed range).
#' @noRd
glob_class = function(ch, i, git = FALSE) {
  n = length(ch)
  names_ok = if (git) glob_posix else c(glob_posix, "ascii", "word")
  esc = function(x) if (x %in% glob_punct) paste0("\\", x) else x
  bad = function(what) {
    gptr_abort(paste0("`glob` ", what, "."), "invalid_argument", arg = "glob",
               expected = "a valid glob")
  }
  p = i + 1L
  neg = p <= n && ch[p] %in% c("!", "^")
  if (neg) p = p + 1L
  out = character()
  prev = NULL
  first = TRUE
  while (p <= n && (first || ch[p] != "]")) {
    first = FALSE
    if (ch[p] == "\\") {
      if (p == n) return(NULL)
      prev = ch[p + 1L]
      out = c(out, esc(prev))
      p = p + 2L
      next
    }
    if (ch[p] == "-" && !is.null(prev) && p < n && ch[p + 1L] != "]") {
      p = p + 1L
      if (ch[p] == "\\") {
        if (p == n) return(NULL)
        p = p + 1L
      }
      lo = utf8ToInt(prev)
      hi = utf8ToInt(ch[p])
      if (isTRUE(hi >= lo)) {
        out[length(out)] = paste0(esc(prev), "-", esc(ch[p]))
      } else if (!git) {
        bad(paste0("has a reversed range `", prev, "-", ch[p], "`"))
      }
      prev = NULL
      p = p + 1L
      next
    }
    if (ch[p] == "[" && p < n && ch[p + 1L] == ":") {
      e = p + 2L
      while (e <= n && ch[e] != "]") e = e + 1L
      if (e > n) return(NULL)
      if (e > p + 2L && ch[e - 1L] == ":") {
        nm = if (e > p + 3L) paste(ch[(p + 2L):(e - 2L)], collapse = "") else ""
        if (!(nm %in% names_ok)) {
          if (git) return(list(end = e, re = NA_character_))
          bad(paste0("names an unknown character class `[:", nm, ":]`"))
        }
        out = c(out, paste0("[:", nm, ":]"))
        prev = NULL
        p = e + 1L
        next
      }
    }
    prev = ch[p]
    out = c(out, esc(prev))
    p = p + 1L
  }
  if (p > n) return(NULL)
  body = paste(out, collapse = "")
  re = if (neg) {
    paste0("[^/", body, "]")
  } else if (!nzchar(body)) {
    "(?!)"
  } else {
    paste0(if (git) "(?!/)", "[", body, "]")
  }
  list(end = p, re = re)
}

#' Translate one glob into a PCRE body (no anchors; report 11 section 3.4)
#' `*`/`?` never cross "/", a whole-segment `**` does, `{a,b}` only when balanced; `git = TRUE`
#' reads an ignore-file line (no braces) and returns NA where wildmatch matches nothing.
#' @noRd
glob_translate = function(glob, git = FALSE) {
  ch = strsplit(as_utf8(glob), "", fixed = TRUE)[[1L]]
  n = length(ch)
  i = 1L
  out = character()
  depth = 0L
  braces = !git
  meta = c(".", "+", "(", ")", "|", "^", "$", "{", "}", "[", "]", "\\", "*", "?")
  esc = function(x) if (x %in% meta) paste0("\\", x) else x
  closes = function(from) {
    d = 0L
    j = from
    while (j <= n) {
      if (ch[j] == "\\") {
        j = j + 2L
        next
      }
      if (ch[j] == "{") d = d + 1L
      if (ch[j] == "}") {
        d = d - 1L
        if (d == 0L) return(TRUE)
      }
      j = j + 1L
    }
    FALSE
  }
  while (i <= n) {
    chr = ch[i]
    if (chr == "\\" && i < n) {
      out = c(out, esc(ch[i + 1L]))
      i = i + 2L
      next
    }
    if (chr == "*") {
      j = i
      while (j < n && ch[j + 1L] == "*") j = j + 1L
      seg_start = i == 1L || ch[i - 1L] == "/"
      seg_end = j == n || ch[j + 1L] == "/"
      if (j > i && seg_start && seg_end) {
        if (j == n) {
          out = c(out, if (i == 1L) ".*" else "(?:.*)?")
          i = j + 1L
        } else {
          out = c(out, "(?:[^/]*/)*")
          i = j + 2L
        }
      } else {
        out = c(out, "[^/]*")
        i = j + 1L
      }
      next
    }
    if (chr == "?") {
      out = c(out, "[^/]")
      i = i + 1L
      next
    }
    if (chr == "[") {
      cls = glob_class(ch, i, git)
      if (is.null(cls)) {
        if (git) return(NA_character_)
        out = c(out, "\\[")
        i = i + 1L
        next
      }
      if (is.na(cls$re)) return(NA_character_)
      out = c(out, cls$re)
      i = cls$end + 1L
      next
    }
    if (braces && chr == "{" && closes(i)) {
      depth = depth + 1L
      out = c(out, "(?:")
      i = i + 1L
      next
    }
    if (braces && chr == "}" && depth > 0L) {
      depth = depth - 1L
      out = c(out, ")")
      i = i + 1L
      next
    }
    if (braces && chr == "," && depth > 0L) {
      out = c(out, "|")
      i = i + 1L
      next
    }
    out = c(out, esc(chr))
    i = i + 1L
  }
  as_utf8(paste(out, collapse = ""))
}

#' Anchor a translated pattern to the whole path (`(?s)` and `\\z`: a name may hold a newline)
#' @noRd
glob_anchor = function(body) paste0("(?s)^", body, "\\z")

#' Glob to an anchored PCRE for "/"-separated paths relative to the search root (contract 7.10)
#' A pattern without "/" matches the basename at any depth, one with "/" gets Pi's `**/` prefix
#' (report 11 row 5), a leading "/" anchors at the root; an invalid translation is an error.
#' @noRd
glob_to_regex = function(glob) {
  check_string(glob, "glob")
  g = as_utf8(glob)
  re = if (startsWith(g, "/")) {
    glob_anchor(glob_translate(substring(g, 2L)))
  } else if (!grepl("/", g, fixed = TRUE)) {
    glob_anchor(paste0("(?:.*/)?", glob_translate(g)))
  } else {
    glob_anchor(glob_translate(if (startsWith(g, "**/") || g == "**") g else paste0("**/", g)))
  }
  if (!spec_regex_ok(re)) {
    gptr_abort(paste0("`glob` is not a valid glob: ", g, "."), "invalid_argument", arg = "glob",
               expected = "a valid glob")
  }
  re
}

#' Compile ignore-file lines into rules (git PATTERN FORMAT; report 11 section 3.4); with
#' `ignore_case` a rule matches case-insensitively (`(?i)`, not wildmatch's casefold quirks)
#' @noRd
ignore_compile = function(lines, base = "", ignore_case = FALSE) {
  rules = list()
  for (ln in lines) {
    ln = sub("\r$", "", ln)
    if (!nzchar(ln) || startsWith(ln, "#")) next
    ln = sub("(?<!\\\\)[ ]+$", "", ln, perl = TRUE)
    if (!nzchar(ln) || (endsWith(ln, "\\") && !endsWith(ln, "\\ "))) next
    neg = startsWith(ln, "!")
    if (neg) ln = substring(ln, 2L)
    if (startsWith(ln, "\\#") || startsWith(ln, "\\!")) ln = substring(ln, 2L)
    dir_only = endsWith(ln, "/")
    if (dir_only) ln = sub("/+$", "", ln)
    if (!nzchar(ln)) next
    anchored = grepl("/", ln, fixed = TRUE)
    ln = sub("^/", "", ln)
    raw = ln
    if (ignore_case) ln = tolower(ln)
    kind = "regex"
    if (!anchored && !grepl("[][*?\\\\]", ln)) {
      kind = "literal"
      value = ln
    } else if (!anchored && grepl("^\\*[^][*?\\\\]+$", ln)) {
      kind = "suffix"
      value = substring(ln, 2L)
    } else {
      # A pattern wildmatch can never match (an unclosed bracket expression, an unknown class name)
      # has no effect, so its rule is dropped, as is one whose PCRE would not compile
      value = glob_translate(raw, git = TRUE)
      if (is.na(value)) next
      value = paste0(if (ignore_case) "(?i)", glob_anchor(value))
      if (!spec_regex_ok(value)) next
    }
    rules[[length(rules) + 1L]] = list(kind = kind, value = value, negated = neg,
                                       dir_only = dir_only, anchored = anchored, base = base)
  }
  rules
}

#' Evaluate compiled rules: TRUE ignored, FALSE re-included, NA no rule matched (the last match
#' wins)
#' @noRd
ignore_eval = function(rules, rel, is_dir, ignore_case = FALSE) {
  res = rep(NA, length(rel))
  if (!length(rules) || !length(rel)) return(res)
  relc = if (ignore_case) tolower(rel) else rel
  bn = sub("(?s)^.*/", "", relc, perl = TRUE)
  for (r in rules) {
    base = if (ignore_case) tolower(r$base) else r$base
    cand = if (nzchar(base)) startsWith(relc, paste0(base, "/")) else rep(TRUE, length(rel))
    if (r$dir_only) cand = cand & is_dir
    if (!any(cand)) next
    idx = which(cand)
    tgt = if (r$anchored) {
      if (nzchar(base)) substring(relc[idx], nchar(base) + 2L) else relc[idx]
    } else {
      bn[idx]
    }
    hit = switch(r$kind,
                 literal = tgt == r$value,
                 suffix = endsWith(tgt, r$value),
                 regex = grepl(r$value, tgt, perl = TRUE))
    res[idx[hit]] = !r$negated
  }
  res
}

#' Lines of an ignore file (none when it cannot be read)
#' @noRd
ignore_read_lines = function(f) {
  txt = tryCatch(read_utf8(fs_path(f))$text, error = function(e) "")
  if (!nzchar(txt)) return(character())
  strsplit(txt, "\n", fixed = TRUE)[[1L]]
}

#' Nearest ancestor (or self) holding a .git entry, or NULL (dirname() works on the unmarked bytes
#' of fs_path(), as it fails on a marked non-ASCII path in a non-UTF-8 locale)
#' @noRd
git_root_of = function(dir) {
  cur = fs_path(dir)
  repeat {
    if (file.exists(file.path(cur, ".git"))) return(as_utf8(cur))
    parent = dirname(cur)
    if (identical(parent, cur)) return(NULL)
    cur = parent
  }
}

#' Is the file system holding `dir` case-insensitive? Flips the case of a path component and asks
#' whether it still exists; writes nothing (basename() and dirname() see the bytes of fs_path())
#' @noRd
fs_case_insensitive = function(dir) {
  if (.Platform$OS.type == "windows") return(TRUE)
  cur = fs_path(dir)
  repeat {
    b = basename(cur)
    flip = chartr(paste(c(letters, LETTERS), collapse = ""),
                  paste(c(LETTERS, letters), collapse = ""), b)
    if (!identical(flip, b)) return(file.exists(file.path(dirname(cur), flip)))
    parent = dirname(cur)
    if (identical(parent, cur)) return(identical(Sys.info()[["sysname"]], "Darwin"))
    cur = parent
  }
}

#' Names in one directory, dot entries included ("." and ".." left out), as list.files() returns
#' them (native bytes; not yet checked or marked)
#' @noRd
walk_list_dir = function(dir) list.files(fs_path(dir), all.files = TRUE, no.. = TRUE)

#' Breadth-first walk (report 11 walk_tree); root-relative prunes beat ignore negations (7.10)
#' Never follows links; stops after the level where rows of kind `count` exceed `max_rows`, or at
#' `max_entries`. Git-root-relative ignore rules: .git/info/exclude, ancestors, then deeper files.
#' @noRd
walk_tree = function(root, hidden = TRUE, gitignore = TRUE, prune = walk_default_prune,
                     max_entries = walk_max_entries, max_rows = Inf, count = "any") {
  root = as_utf8(normalizePath(fs_path(root), winslash = "/", mustWork = TRUE))
  detect_cycles = .Platform$OS.type == "windows"
  visited = if (detect_cycles) root else character()
  ignore_case = fs_case_insensitive(root)
  prune_rules = ignore_compile(prune, "", ignore_case)
  rules = list()
  prefix = ""
  if (gitignore) {
    groot = git_root_of(root)
    if (!is.null(groot)) {
      # A git root at "/" or "C:/" keeps its slash; measure and join without it
      gbase = sub("/+$", "", groot)
      prefix = if (identical(groot, root)) "" else substring(root, nchar(gbase) + 2L)
      ex = file.path(gbase, ".git", "info", "exclude")
      if (file.exists(fs_path(ex))) {
        rules = c(rules, ignore_compile(ignore_read_lines(ex), "", ignore_case))
      }
      if (nzchar(prefix)) {
        segs = strsplit(prefix, "/", fixed = TRUE)[[1L]]
        bases = c("", vapply(seq_len(length(segs) - 1L), function(k) {
          paste(segs[seq_len(k)], collapse = "/")
        }, ""))
        for (bs in bases) {
          for (nm in walk_ignore_files) {
            f = if (nzchar(bs)) file.path(gbase, bs, nm) else file.path(gbase, nm)
            if (file.exists(fs_path(f))) {
              rules = c(rules, ignore_compile(ignore_read_lines(f), bs, ignore_case))
            }
          }
        }
      }
    }
  }
  anchor_rel = function(rel) if (nzchar(prefix)) paste(prefix, rel, sep = "/") else rel
  frontier = ""
  acc_rel = list()
  acc_dir = list()
  acc_lnk = list()
  total = 0L
  rows = 0
  invalid = 0L
  truncated = FALSE
  depth = 0L
  while (length(frontier)) {
    depth = depth + 1L
    dirs_abs = ifelse(nzchar(frontier), paste(root, frontier, sep = "/"), root)
    listing = lapply(dirs_abs, walk_list_dir)
    counts = lengths(listing)
    if (!sum(counts)) break
    nm = unlist(listing, use.names = FALSE)
    parent = rep(frontier, counts)
    bad = !validUTF8(nm)
    if (any(bad)) {
      invalid = invalid + sum(bad)
      nm = nm[!bad]
      parent = parent[!bad]
      if (!length(nm)) break
    }
    nm = as_utf8(nm)
    rel = ifelse(nzchar(parent), paste(parent, nm, sep = "/"), nm)
    full = paste(root, rel, sep = "/")
    if (gitignore) {
      found = which(nm %in% walk_ignore_files)
      found = found[order(match(parent[found], frontier), match(nm[found], walk_ignore_files))]
      for (f in found) {
        bs = if (nzchar(parent[f])) anchor_rel(parent[f]) else prefix
        rules = c(rules, ignore_compile(ignore_read_lines(full[f]), bs, ignore_case))
      }
    }
    lnk = Sys.readlink(fs_path(full))
    is_link = !is.na(lnk) & nzchar(lnk)
    is_dir = dir.exists(fs_path(full))
    pruned = ignore_eval(prune_rules, rel, is_dir, ignore_case) %in% TRUE
    ign = ignore_eval(rules, anchor_rel(rel), is_dir, ignore_case)
    keep = !pruned & (is.na(ign) | !ign)
    if (!hidden) keep = keep & !startsWith(nm, ".")
    rel = rel[keep]
    is_dir = is_dir[keep]
    is_link = is_link[keep]
    acc_rel[[depth]] = rel
    acc_dir[[depth]] = is_dir
    acc_lnk[[depth]] = is_link
    total = total + length(rel)
    rows = rows + switch(count, file = sum(!is_dir), dir = sum(is_dir), length(rel))
    if (total >= max_entries || rows > max_rows) {
      truncated = TRUE
      break
    }
    frontier = rel[is_dir & !is_link]
    if (detect_cycles && length(frontier)) {
      real = as_utf8(normalizePath(fs_path(paste(root, frontier, sep = "/")), winslash = "/",
                                   mustWork = FALSE))
      fresh = !duplicated(real) & !(real %in% visited)
      frontier = frontier[fresh]
      visited = c(visited, real[fresh])
    }
  }
  out = data.frame(rel = as_utf8(as.character(unlist(acc_rel))),
                   is_dir = as.logical(unlist(acc_dir)), is_link = as.logical(unlist(acc_lnk)),
                   stringsAsFactors = FALSE)
  attr(out, "truncated") = truncated
  attr(out, "root") = root
  attr(out, "invalid_names") = invalid
  out
}

#' Walk a directory tree (contract section 7.10): `path`, `size`, `mtime`, `type` sorted by path
#' `max` counts rows of `type` only (`Inf`: the 500,000-entry cap); `prune` replaces the default
#' list; attributes `root` (canonical), `truncated` and `invalid_names`.
#' @noRd
walk_files = function(root = ".", type = c("file", "dir", "any"), gitignore = TRUE, hidden = FALSE,
                      max = Inf, prune = NULL) {
  check_string(root, "root")
  type = check_choice(type, c("file", "dir", "any"), "type")
  check_flag(gitignore, "gitignore")
  check_flag(hidden, "hidden")
  check_number(max, "max", min = 0)
  check_strings(prune, "prune", null = TRUE)
  abs = resolve_tool_path(root)
  if (!dir.exists(fs_path(abs))) {
    gptr_abort(paste0("Path not found: ", abs), "invalid_argument", arg = "root",
               expected = "an existing directory")
  }
  w = walk_tree(abs, hidden = hidden, gitignore = gitignore, prune = prune %||% walk_default_prune,
                max_rows = max, count = type)
  truncated = isTRUE(attr(w, "truncated"))
  invalid = attr(w, "invalid_names")
  if (type == "file") w = w[!w$is_dir, , drop = FALSE]
  if (type == "dir") w = w[w$is_dir, , drop = FALSE]
  real_root = attr(w, "root")
  fi = file.info(fs_path(file.path(real_root, w$rel)), extra_cols = FALSE)
  size = as.numeric(fi$size)
  size[w$is_dir] = NA_real_
  kind = rep("file", nrow(w))
  kind[w$is_dir] = "dir"
  kind[w$is_link] = "link"
  out = data.frame(path = w$rel, size = size, mtime = fi$mtime, type = kind,
                   stringsAsFactors = FALSE)
  out = out[order(tolower(out$path), out$path, method = "radix"), , drop = FALSE]
  if (is.finite(max) && nrow(out) > max) {
    out = out[seq_len(max), , drop = FALSE]
    truncated = TRUE
  }
  rownames(out) = NULL
  attr(out, "root") = real_root
  attr(out, "truncated") = truncated
  attr(out, "invalid_names") = invalid
  out
}
