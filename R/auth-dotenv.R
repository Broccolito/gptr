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

#' Does an API-key-like value contain whitespace, control or non-ASCII characters?
#' @noRd
dotenv_bad_key_value = function(variable, value) {
  grepl("(API_?KEY|APIKEY|TOKEN)$", variable, perl = TRUE) &&
    (grepl("[[:space:][:cntrl:]]", value) || grepl("[^\\x01-\\x7f]", value, perl = TRUE))
}

#' Load keys from a .env file
#'
#' Reads a `.env` file with gptr's own parser (a UTF-8 byte-order mark, CRLF line ends,
#' `export` prefixes, single and double quotes, multi-line quoted values, ` #` comments and
#' hyphenated names such as `jev-key` are understood), maps aliases onto canonical variable
#' names (`jev-key`, `JEV_KEY`, `JEV_API_KEY` and `TYPESAFE_KEY` become `TYPESAFE_API_KEY`; a
#' line spelled exactly as the canonical name wins over an alias), registers secret values
#' in gptr's vault for redaction, and exports the canonical names with [Sys.setenv()]. Plain
#' configuration fields with suffixes such as `_URL` or `_PATH` are not registered as
#' secrets. It never prints, logs or returns a value.
#'
#' @param path Path of an existing `.env` file.
#' @param aliases `NULL`, or a named list of extra aliases, `canonical = c("alias", ...)`,
#'   added to the built-in table and to the registered `env_alias` specs.
#' @param set_env If `TRUE`, export the canonical names to the environment of this R process;
#'   if `FALSE`, keep the values in the vault only. Defaults to `getOption("gptr.env_export",
#'   TRUE)`.
#' @param override If `TRUE`, overwrite variables that are already set.
#' @param quiet If `TRUE`, do not report what was loaded.
#' @return Invisibly, a `gptr_env_report` data frame with columns `name` (as spelled in the
#'   file), `variable` (the canonical name), `secret`, `fingerprint` and `action` (`"set"`,
#'   `"registered"`, `"skipped"` or `"duplicate"`), and the attribute `bad_lines` (the numbers
#'   of malformed lines). It holds names and fingerprints, never values.
#' @export
#' @examples
#' f = tempfile(fileext = ".env")
#' writeLines("jev-key=example-not-a-real-key-123", f)
#' rep = gptr_env(f, set_env = FALSE)
#' rep$variable
#' unlink(f)
gptr_env = function(path = ".env", aliases = NULL, set_env = getOption("gptr.env_export", TRUE),
                    override = FALSE, quiet = FALSE) {
  check_string(path, "path")
  if (!file.exists(path) || dir.exists(path)) {
    gptr_abort("`path` must name an existing .env file.", "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  check_list(aliases, "aliases", named = TRUE, null = TRUE)
  check_flag(set_env, "set_env")
  check_flag(override, "override")
  check_flag(quiet, "quiet")
  kv = dotenv_parse(path)
  bad = attr(kv, "bad_lines")
  source = paste0("dotenv:", basename(path))
  kv$variable = alias_resolve(kv$name, aliases)
  exact = kv$name == kv$variable
  winner = logical(nrow(kv))
  for (v in unique(kv$variable)) {
    i = which(kv$variable == v)
    winner[if (any(exact[i])) max(i[exact[i]]) else max(i)] = TRUE
  }
  kv$secret = !grepl(nonsecret_suffix_re, kv$variable, perl = TRUE)
  kv$action = ifelse(winner, "registered", "duplicate")
  # A newer assignment from this file source supersedes its prior active values,
  # including when the new value is empty or invalid. Keep old values for redaction.
  st = secrets_state()
  selected = kv$variable[winner & kv$secret]
  for (id in names(st$reg)) {
    entry = st$reg[[id]]
    if (entry$name %in% selected && entry$source %in% c(source, paste0(source, ":shadowed"))) {
      st$reg[[id]]$active = FALSE
    }
  }
  reg = secret_register_batch(source, function() {
    fp = character(nrow(kv))
    invalid = logical(nrow(kv))
    # losing duplicates first, so a winner with the same value ends active and last
    for (i in c(which(!winner), which(winner))) {
      v = kv$value[i]
      if (!kv$secret[i] || !nzchar(v)) next
      invalid[i] = dotenv_bad_key_value(kv$variable[i], v)
      h = secret_register(v, kv$variable[i],
                          source = if (winner[i]) source else paste0(source, ":shadowed"),
                          active = winner[i] && !invalid[i])
      fp[i] = h$fp
    }
    list(fp = fp, invalid = invalid)
  })
  kv$fingerprint = reg$fp
  refused = reg$invalid & winner          # an API key with blanks or non-ASCII: never exported
  bad = c(bad, kv$line[refused])
  kv$action[refused] = "skipped"
  for (i in which(winner & !refused)) {
    if (!set_env) {
      if (!kv$secret[i] || !nzchar(kv$value[i])) kv$action[i] = "skipped"
      next
    }
    if (!override && nzchar(Sys.getenv(kv$variable[i]))) {
      kv$action[i] = "skipped"
    } else {
      do.call(Sys.setenv, stats::setNames(list(kv$value[i]), kv$variable[i]))
      kv$action[i] = "set"
    }
  }
  rep = data.frame(name = kv$name, variable = kv$variable, secret = kv$secret,
                   fingerprint = kv$fingerprint, action = kv$action, stringsAsFactors = FALSE)
  attr(rep, "bad_lines") = sort(unique(as.integer(bad)))
  class(rep) = c("gptr_env_report", "data.frame")
  if (!quiet) {
    lab = paste0(rep$variable, ifelse(nzchar(rep$fingerprint), paste0(" #", rep$fingerprint), ""),
                 ifelse(rep$name == rep$variable, "", paste0(" (from ", rep$name, ")")),
                 ifelse(rep$action == "set", "", paste0(" [", rep$action, "]")))
    gptr_inform(c(paste0("Loaded ", nrow(rep), " variable(s) from ", basename(path), ": ",
                         paste(lab, collapse = ", ")),
                  if (length(attr(rep, "bad_lines"))) {
                    paste0("Ignored malformed line(s): ",
                           paste(attr(rep, "bad_lines"), collapse = ", "), ".")
                  }), "notice")
  }
  invisible(rep)
}

#' @export
#' @noRd
format.gptr_env_report = function(x, ...) {
  if (!nrow(x)) return(character())
  sprintf("%-20s %-18s %-7s %-8s %s", x$variable, x$name, ifelse(x$secret, "secret", "plain"),
          ifelse(nzchar(x$fingerprint), paste0("#", x$fingerprint), ""), x$action)
}

#' @export
#' @noRd
print.gptr_env_report = function(x, ...) {
  cat(sprintf("%-20s %-18s %-7s %-8s %s", "variable", "from", "kind", "id", "action"), format(x),
      sep = "\n")
  bad = attr(x, "bad_lines")
  if (length(bad)) cat("malformed lines ignored: ", paste(bad, collapse = ", "), "\n", sep = "")
  invisible(x)
}

# ---- automatic .env discovery: trusted projects only, vault-only (03 section 6.5) ----------

#' Is the project trusted? The trust.get service (P08); untrusted when it is absent (IC-33)
#' @noRd
dotenv_trusted = function(root = project_root()) {
  if (!ext_service_has("trust.get")) return(FALSE)
  isTRUE(tryCatch(ext_service_get("trust.get")(root), error = function(e) FALSE))
}

#' The .env files automatic discovery reads, in precedence order: .gptr/.env, then .env
#' @noRd
dotenv_project_files = function(root = project_root()) {
  files = c(file.path(root, ".gptr", ".env"), file.path(root, ".env"))
  files[file.exists(files) & !dir.exists(files)]
}

#' Register the secrets of a trusted project's .env files without exporting them
#'
#' G6 section 4.5 step 5. One notice per file version names variables and fingerprints only.
#' Returns the number of secrets registered.
#' @noRd
dotenv_discover = function(root = project_root(), trusted = dotenv_trusted(root)) {
  if (!isTRUE(trusted)) return(0L)
  n = 0L
  for (f in rev(dotenv_project_files(root))) {
    rep = tryCatch(gptr_env(f, set_env = FALSE, quiet = TRUE), gptr_error = function(e) NULL)
    if (is.null(rep)) next
    hit = rep$secret & nzchar(rep$fingerprint) & rep$action == "registered"
    if (!any(hit)) next
    n = n + sum(hit)
    gptr_inform(paste0("Registered ", sum(hit), " secret(s) from ", f,
                       " for redaction (trusted project; not exported): ",
                       paste0(rep$variable[hit], " #", rep$fingerprint[hit], collapse = ", "),
                       "."),
                "notice", .once = paste("dotenv_discover", f, file.mtime(f), file.size(f)))
  }
  as.integer(n)
}

#' The dotenv secret source: a canonical variable of a trusted project's .env files, or NULL
#'
#' The value is registered at once (04 section 10.2, kind secret_source); .gptr/.env wins over
#' .env, and inside one file the canonical spelling wins over an alias.
#' @noRd
dotenv_source_resolve = function(name, root = project_root(), trusted = dotenv_trusted(root)) {
  if (!isTRUE(trusted)) return(NULL)
  check_string(name, "name")
  if (grepl(nonsecret_suffix_re, name, perl = TRUE)) return(NULL)
  for (f in dotenv_project_files(root)) {
    kv = tryCatch(dotenv_parse(f), gptr_error = function(e) NULL)
    if (is.null(kv) || !nrow(kv)) next
    i = which(alias_resolve(kv$name) == name)
    if (!length(i)) next
    exact = kv$name[i] == name
    v = kv$value[if (any(exact)) max(i[exact]) else max(i)]
    if (!nzchar(v)) return(NULL)
    valid = !dotenv_bad_key_value(name, v)
    secret_register(v, name, source = paste0("dotenv:", basename(f)), active = valid)
    if (!valid) return(NULL)
    return(v)
  }
  NULL
}

#' Canonical names of the secret entries of a trusted project's .env files
#' @noRd
dotenv_source_list = function(root = project_root(), trusted = dotenv_trusted(root)) {
  if (!isTRUE(trusted)) return(character())
  out = character()
  for (f in dotenv_project_files(root)) {
    kv = tryCatch(dotenv_parse(f), gptr_error = function(e) NULL)
    if (!is.null(kv) && nrow(kv)) out = c(out, alias_resolve(kv$name))
  }
  out = unique(out)
  out[!grepl(nonsecret_suffix_re, out, perl = TRUE)]
}
