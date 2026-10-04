# gptr's own .env parser and alias table (G6 sections 3.1-3.2 and 5.0; the parser replaces
# readRenviron(), which turns `export D=4` into a variable named "export D"). This is the only
# file in R/ that may call Sys.setenv() (test-lint-rules.R). House style: "=" and "|>" (S-9).

#' The built-in alias table: canonical name -> aliases (REQ-13)
#' @noRd
alias_builtin = function() {
  list(TYPESAFE_API_KEY = c("jev-key", "JEV_KEY", "JEV_API_KEY", "TYPESAFE_KEY"))
}

#' The alias table: built-in entries, then env_alias specs, then call-supplied entries
#' @noRd
alias_table = function(aliases = NULL) {
  out = alias_builtin()
  specs = tryCatch(registry_all("env_alias"), error = function(e) NULL)
  extra = c(lapply(specs, function(s) stats::setNames(list(s$aliases), s$name)), list(aliases))
  for (entries in extra) {
    if (is.null(entries)) next
    check_list(entries, "aliases", named = TRUE)
    if (!length(entries)) next
    dest = names(entries)
    valid_name = function(x) {
      is.character(x) && !anyNA(x) && all(grepl("^[A-Za-z_][A-Za-z0-9_.-]*$", x))
    }
    if (!valid_name(dest) || anyDuplicated(dest) ||
        !all(vapply(entries, valid_name, NA))) {
      gptr_abort("Aliases must map variable names to character vectors of variable names.",
                 "invalid_argument", arg = "aliases", expected = "valid environment aliases")
    }
    for (nm in dest) {
      canon = canon_name(nm)
      out[[canon]] = unique(c(out[[canon]], entries[[nm]]))
    }
  }
  out
}

#' Canonical variable names for .env names, through the alias table
#' @noRd
alias_resolve = function(names, aliases = NULL) {
  tab = alias_table(aliases)
  key = canon_name(names)
  out = key
  for (canon in names(tab)) out[key %in% canon_name(c(canon, tab[[canon]]))] = canon
  out
}

#' Decode the escapes of a double-quoted .env value in one pass
#' @noRd
dotenv_unescape = function(v) {
  m = gregexpr("\\\\.", v, perl = TRUE)
  regmatches(v, m) = lapply(regmatches(v, m), function(esc) {
    vapply(esc, function(e) {
      switch(substr(e, 2L, 2L), n = "\n", r = "\r", t = "\t", "\"" = "\"", "\\" = "\\",
             "$" = "$", e)
    }, "", USE.NAMES = FALSE)
  })
  v
}

#' Parse a .env file into data.frame(name, value, line); malformed line numbers in "bad_lines"
#' @noRd
dotenv_parse = function(path) {
  check_string(path, "path")
  if (!file.exists(path) || dir.exists(path)) {
    gptr_abort("`path` must name an existing .env file.", "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  raw = readBin(path, "raw", file.size(path))
  if (any(raw == as.raw(0L))) {
    gptr_abort("A .env file must be text, not binary data.", "invalid_argument",
               arg = "path", expected = "a text .env file")
  }
  txt = raw_to_utf8(raw)      # drops a UTF-8 BOM; text that is not UTF-8 is read as CP1252 (IC-62)
  lines = strsplit(gsub("\r\n?", "\n", txt, perl = TRUE), "\n", fixed = TRUE)[[1]]
  names = character()
  values = character()
  at = integer()
  bad = integer()
  i = 1L
  while (i <= length(lines)) {
    ln = sub("^[ \t]+", "", lines[i])
    start = i
    i = i + 1L
    if (!nzchar(ln) || startsWith(ln, "#")) next
    ln = sub("^export[ \t]+", "", ln)
    m = regmatches(ln, regexec("^([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*=(.*)$", ln))[[1]]
    if (length(m) != 3L) {
      bad = c(bad, start)
      next
    }
    v = if (grepl("^[ \t]+#", m[3])) "" else sub("^[ \t]+", "", m[3])
    q = substr(v, 1L, 1L)
    if (q %in% c("\"", "'")) {
      body = substr(v, 2L, nchar(v))
      close_re = if (q == "\"") {
        "^((?:[^\"\\\\]|\\\\.)*)\"[ \t]*(#.*)?$"
      } else {
        "^([^']*)'[ \t]*(#.*)?$"
      }
      end_re = if (q == "\"") "^(?:[^\"\\\\]|\\\\.)*\"" else "^[^']*'"
      while (!grepl(end_re, body, perl = TRUE) && i <= length(lines)) {
        body = paste0(body, "\n", lines[i])            # a multi-line quoted value
        i = i + 1L
      }
      if (!grepl(close_re, body, perl = TRUE)) {
        bad = c(bad, start)
        next
      }
      v = sub(close_re, "\\1", body, perl = TRUE)
      if (q == "\"") v = dotenv_unescape(v)
    } else {
      v = sub("[ \t]+#.*$", "", v)                       # ` #` starts a comment; `a#b` is data
      v = sub("[ \t]+$", "", v)
    }
    names = c(names, m[2])
    values = c(values, v)
    at = c(at, start)
  }
  res = data.frame(name = names, value = as_utf8(values), line = at, stringsAsFactors = FALSE)
  attr(res, "bad_lines") = bad
  res
}
