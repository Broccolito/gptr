# Secrets: the vault, gptr_secret handles, ambient discovery and origin-bound materialisation.
# Adapted from dev/research/G6-secrets-redaction-end-to-end.md section 5.0 ("secrets.R") with the
# verification-log fixes applied. Secret values live only in the vault (`the$vault`); metadata and
# the compiled redaction state live in `the$secrets` (04 section 7.0; `the$redactor` stays P01's
# installed redaction hook). House style: "=" and "|>" (S-9).

# Secret-looking variable names (G6 section 3.3).
secret_name_re = paste0(
  "(API_?KEY|ACCESS_?KEY|SECRET|TOKEN|PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|",
  "PRIVATE_?KEY|COOKIE|(^|_)PAT$|(^|_)KEY$)"
)
nonsecret_suffix_re = paste0(
  "_(FILE|PATH|DIR|HOME|URL|URI|HOST|PORT|ID|USER|USERNAME|MODEL|REGION|LEVEL|SOCK)$"
)
nonsecret_names = c("SSH_AUTH_SOCK", "GPG_AGENT_INFO", "XAUTHORITY", "PWD", "OLDPWD")
# Characters that can occur inside a key or token (streaming hold-back, G6 section 3.6).
token_class = "A-Za-z0-9._~+/=-"

#' Canonical environment-variable spelling of a name
#' @noRd
canon_name = function(x) toupper(gsub("[^A-Za-z0-9]", "_", x))

#' Does a variable name look like it holds a secret?
#' @noRd
is_secret_name = function(x) {
  n = canon_name(x)
  grepl(secret_name_re, n, perl = TRUE) & !grepl(nonsecret_suffix_re, n, perl = TRUE) &
    !(n %in% nonsecret_names)
}

#' Is a name usable as a secret name (and inside a `[secret:NAME]` marker)?
#' @noRd
secret_name_ok = function(name) {
  is.character(name) && length(name) == 1L && !is.na(name) && nzchar(name) &&
    nchar(name) <= 200L && !grepl("[\\]\\[\\s\"'\\\\{}]", name, perl = TRUE)
}

#' A P03 option with its contract default (04 section 3.1)
#' @noRd
secrets_opt = function(name) {
  defaults = list(redact_min_chars = 8L, redact_patterns = TRUE, stream_hold_max = 4096L,
                  env_export = TRUE, prompt_secrets = "redact", secret_guard = TRUE)
  gptr_opt(name) %||% defaults[[name]]
}

#' The vault: id -> value, the only place secret values live
#' @noRd
vault_env = function() {
  if (!is.environment(the$vault)) the$vault = new.env(parent = emptyenv())
  the$vault
}

#' P03 metadata and compiled redaction state, created on first use
#' @noRd
secrets_state = function() {
  st = the$secrets
  if (is.environment(st)) return(st)
  st = new.env(parent = emptyenv())
  st$reg = list()            # per id: name, source, fingerprint, active, redact, origin
  st$lits = character()      # literals (values and derived forms), longest first
  st$marks = character()     # the marker of each literal
  st$lit_re = character()    # PCRE alternations of the escaped literals (lit_groups())
  st$lits_long = integer()   # indices (into lits) of literals too long for a group: fixed strings
  st$lits_odd = character()  # literals with characters outside token_class
  st$version = 0L            # bumped by every recompilation of the literals
  st$rules = NULL            # compiled redaction rules (auth-redact.R)
  st$rules_src = NULL        # the rule specs they were compiled from
  st$anchor_re = ""          # one alternation of every rule anchor
  st$anchor_all = FALSE      # a rule without anchors: every text is a candidate
  st$in_rules = FALSE        # re-entrancy guard of rules_current()
  st$quiet_events = FALSE    # batch registration emits one secret_registered event
  st$live_entries = NULL     # the session layer's callback (secret_live_entries_set())
  the$secrets = st
  st
}

#' Forget every registered secret and the compiled state (test isolation); the installed
#' live-entries callback survives
#' @noRd
vault_reset = function() {
  keep = if (is.environment(the$secrets)) the$secrets$live_entries else NULL
  the$vault = new.env(parent = emptyenv())
  the$secrets = NULL
  if (!is.null(keep)) {
    st = secrets_state()
    st$live_entries = keep
  }
  invisible(NULL)
}

#' Values of the registered secrets that are value-redacted (child-environment scrubbing)
#' @noRd
vault_values = function() {
  st = secrets_state()
  ids = names(st$reg)[vapply(st$reg, function(e) isTRUE(e$redact), NA)]
  if (!length(ids)) return(character())
  unlist(mget(ids, envir = vault_env()), use.names = FALSE)
}

#' The origin a handle is bound to: its own field, else the one it was registered with
#' @noRd
secret_bound_origin = function(handle) {
  handle$origin %||% secrets_state()$reg[[handle$id]]$origin
}

#' Normalised origin (scheme://host:port) of a URL, or NA
#' @noRd
origin_of = function(url) {
  if (!is.character(url) || length(url) != 1L || is.na(url) || !validUTF8(url) ||
      grepl("[[:cntrl:]\\\\]", url) ||
      !grepl("\\A[A-Za-z][A-Za-z0-9+.-]*://", url, perl = TRUE)) return(NA_character_)
  # Use libcurl's URL parser just like the transport, including abbreviated IPv4
  # and compressed IPv6 forms, without crossing the L0 -> HTTP layer boundary.
  parts = tryCatch(curl::curl_parse_url(url), error = function(e) NULL)
  if (is.null(parts) || is.null(parts$host) || !nzchar(parts$host)) return(NA_character_)
  scheme = tolower(parts$scheme)
  port = parts$port %||%
    switch(scheme, https = "443", wss = "443", http = "80", ws = "80", "")
  paste0(scheme, "://", tolower(parts$host), if (nzchar(port)) paste0(":", port) else "")
}

#' Derived forms of a value that commonly appear in output (G6 section 3.4)
#' @noRd
secret_variants = function(v, min_len = 8L) {
  j = json_encode(v)
  out = c(v, utils::URLencode(v, reserved = TRUE), substr(j, 2L, nchar(j) - 1L))
  if (nchar(v) >= 12L) {
    for (o in 0:2) {
      b = gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(paste0(strrep("A", o), v))))
      drop_head = if (o == 0L) 0L else 4L
      frag = substr(b, drop_head + 1L, nchar(b) - 4L)
      out = c(out, frag, chartr("+/", "-_", frag))
    }
  }
  unique(out[nchar(out) >= min_len])
}

#' Escape a literal for use inside a PCRE pattern
#' @noRd
re_escape = function(x) gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", x, perl = TRUE)

# PCRE2 refuses a pattern near 32,000 characters ("regular expression is too large"; reproduced
# with R 4.4.3 and PCRE2 10.44, where three registered private keys and their base64 forms were
# enough). An alternation therefore holds at most 200 literals and 16,000 pattern characters,
# and a literal longer than that is matched as a fixed string.
lit_group_max = 200L
lit_group_chars = 16000L

#' Split escaped literals (longest first) into alternations that PCRE can always compile
#' @noRd
lit_groups = function(esc) {
  if (!length(esc)) return(character())
  grp = integer(length(esc))
  g = 1L
  used = 0L
  n = 0L
  for (i in seq_along(esc)) {
    size = nchar(esc[i]) + 1L
    if (n >= lit_group_max || (n > 0L && used + size > lit_group_chars)) {
      g = g + 1L
      used = 0L
      n = 0L
    }
    grp[i] = g
    used = used + size
    n = n + 1L
  }
  unname(vapply(split(esc, grp), paste, "", collapse = "|"))
}

#' Recompile the literal table: bounded PCRE alternations, longest first; long literals fixed
#' @noRd
secret_compile = function() {
  st = secrets_state()
  min_len = secrets_opt("redact_min_chars")
  lits = character()
  marks = character()
  for (e in st$reg) {
    if (!isTRUE(e$redact)) next
    vv = secret_variants(get(e$id, envir = vault_env(), inherits = FALSE), min_len)
    lits = c(lits, vv)
    marks = c(marks, rep(paste0("[secret:", e$name, "]"), length(vv)))
  }
  keep = !duplicated(lits)
  lits = lits[keep]
  marks = marks[keep]
  o = order(nchar(lits), decreasing = TRUE)
  st$lits = lits[o]
  st$marks = marks[o]
  esc = re_escape(st$lits)
  long = nchar(esc) > lit_group_chars
  st$lits_long = which(long)
  st$lit_re = lit_groups(esc[!long])
  st$lits_odd = st$lits[grepl(paste0("[^", token_class, "]"), st$lits, perl = TRUE)]
  st$version = st$version + 1L
  invisible(NULL)
}

#' Register a secret value in the vault and return its handle (the only entry point for values)
#' @noRd
secret_register = function(value, name, source = "user", active = TRUE, origin = NULL) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    gptr_abort("A secret value must be one non-empty string.", "invalid_argument",
               arg = "value", expected = "a non-empty string")
  }
  if (!secret_name_ok(name)) {
    gptr_abort(paste("A secret name must have 1-200 characters and no blanks, quotes,",
                     "brackets or braces."),
               "invalid_argument", arg = "name", expected = "a variable-like name")
  }
  check_string(source, "source")
  check_flag(active, "active")
  check_string(origin, "origin", null = TRUE)
  if (!is.null(origin)) {
    origin = origin_of(origin)
    if (is.na(origin)) {
      gptr_abort("`origin` must be a URL such as https://api.anthropic.com.", "invalid_argument",
                 arg = "origin", expected = "a URL")
    }
  }
  value = as_utf8(value)
  st = secrets_state()
  fp = substr(hash_sha256(value), 1L, 6L)
  base_id = paste0(name, "#", fp)
  id = base_id
  collision = 0L
  # Display fingerprints are short; compare vault values before reusing an id so a
  # collision never replaces a credential or omits a value from redaction.
  vault = vault_env()
  while (exists(id, envir = vault, inherits = FALSE) &&
           !identical(get(id, envir = vault, inherits = FALSE), value)) {
    collision = collision + 1L
    id = paste0(base_id, "-", collision)
  }
  old = st$reg[[id]]
  n_chars = nchar(value, allowNA = TRUE)
  if (is.na(n_chars)) n_chars = nchar(value, type = "bytes")
  entry = list(id = id, name = name, source = source, fp = fp, active = active,
               redact = n_chars >= secrets_opt("redact_min_chars"),
               origin = origin %||% old$origin)
  st$reg[[id]] = NULL                  # re-registration moves the entry to the end
  st$reg[[id]] = entry
  if (is.null(old)) {
    assign(id, value, envir = vault_env())
    secret_compile()
    if (isTRUE(entry$redact)) secret_late_check(value, name)
    if (!isTRUE(st$quiet_events)) {
      ev_dispatch("secret_registered", list(name = name, source = source, count = 1L))
    }
  }
  structure(list(id = id, name = name, fp = fp, origin = entry$origin), class = "gptr_secret")
}

#' Run several registrations and emit one aggregated secret_registered event
#' @noRd
secret_register_batch = function(source, fun) {
  st = secrets_state()
  before = length(st$reg)
  outer = st$quiet_events
  st$quiet_events = TRUE
  on.exit({
    st$quiet_events = outer
  }, add = TRUE)
  out = fun()
  st$quiet_events = outer
  added = length(st$reg) - before
  if (added > 0L && !isTRUE(outer)) {
    ev_dispatch("secret_registered", list(name = NA_character_, source = source, count = added))
  }
  out
}

#' Materialise a handle for one origin; callers: http-request.R (P04) and auth-childenv.R only
#' @noRd
secret_value = function(handle, origin) {
  check_class(handle, "gptr_secret", "handle")
  # A looked-up unbound handle may be narrowed by an adapter, but changing its
  # fields cannot replace an origin restriction already recorded in the vault.
  bounds = unique(c(secrets_state()$reg[[handle$id]]$origin, secret_bound_origin(handle)))
  for (bound in bounds) {
    want = origin_of(bound)
    got = origin_of(origin)
    if (is.na(got) || !identical(want, got)) {
      gptr_abort(paste0("The credential ", handle$name, " is bound to ", want,
                        " and is never sent to ",
                        if (is.na(got)) "an unrecognised origin" else got, "."),
                 "untrusted", what = "secret", path = NULL,
                 origin = if (is.na(got)) NULL else got)
    }
  }
  value = get0(handle$id, envir = vault_env(), inherits = FALSE)
  if (is.null(value)) {
    gptr_abort(paste0("The credential ", handle$name, " is no longer in the vault."), "no_key",
               provider = NA_character_, variables = handle$name)
  }
  value
}

#' The latest active handle registered under a name, or NULL
#' @noRd
secret_lookup = function(name) {
  check_string(name, "name")
  hit = NULL
  for (e in secrets_state()$reg) if (identical(e$name, name) && isTRUE(e$active)) hit = e
  if (is.null(hit)) return(NULL)
  structure(list(id = hit$id, name = hit$name, fp = hit$fp, origin = hit$origin),
            class = "gptr_secret")
}

#' Names of every registered secret (the classifier's secret guard reads them)
#' @noRd
secret_registered_names = function() {
  reg = secrets_state()$reg
  if (!length(reg)) return(character())
  unique(unname(vapply(reg, function(e) e$name, "")))
}

#' Register secret-looking environment variables (ambient discovery at session start)
#' @noRd
secret_discover_env = function(env = Sys.getenv()) {
  nm = names(env)
  if (!length(nm)) return(invisible(0L))
  vals = as_utf8(unname(as.character(env)))
  min_len = secrets_opt("redact_min_chars")
  hit = is_secret_name(nm) & (nchar(vals, allowNA = TRUE) >= min_len) %in% TRUE &
    vapply(nm, secret_name_ok, NA, USE.NAMES = FALSE)
  proxies = which(nm %in% c("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy",
                            "https_proxy", "all_proxy"))
  secret_register_batch("environment", function() {
    for (i in which(hit)) secret_register(vals[i], nm[i], source = "environment")
    for (i in proxies) {
      m = regmatches(vals[i], regexec("^[A-Za-z][A-Za-z0-9+.-]*://[^/:@]+:([^/@]+)@",
                                      vals[i]))[[1]]
      if (length(m) == 2L && nchar(m[2]) >= 4L) {
        secret_register(m[2], paste0(toupper(nm[i]), "_PASSWORD"), source = "environment")
      }
    }
  })
  invisible(sum(hit))
}

#' Install the provider of live sessions' in-memory entries for the late-registration check
#'
#' L0 reaches sessions only through a callback registered by the upper layer (03 section 2.2):
#' the session kernel (P06) calls this from an on_load() expression with a zero-argument
#' function returning a named list, session id -> list of R-shape entries (04 section 4.6).
#' `NULL` removes it. Before P06 is loaded no session exists, so nothing is scanned.
#' @noRd
secret_live_entries_set = function(fun) {
  if (!is.null(fun) && !is.function(fun)) {
    gptr_abort("`fun` must be a function or NULL.", "invalid_argument",
               arg = "fun", expected = "a function or NULL")
  }
  st = secrets_state()
  st$live_entries = fun
  invisible(NULL)
}

#' Warn when a newly registered value already occurs in live sessions (IC-70, G6 section 4.7)
#' @noRd
secret_late_check = function(value, name) {
  fun = secrets_state()$live_entries
  if (!is.function(fun)) return(invisible(NULL))
  live = tryCatch(fun(), error = function(e) NULL)
  if (!is.list(live) || !length(live) || is.null(names(live))) return(invisible(NULL))
  forms = secret_variants(value, secrets_opt("redact_min_chars"))
  counts = integer()
  for (id in names(live)) {
    txt = unlist(live[[id]], use.names = FALSE)
    if (!is.character(txt) || !length(txt)) next
    n = 0L
    for (f in forms) {
      n = n + sum(vapply(gregexpr(f, txt, fixed = TRUE, useBytes = TRUE),
                         function(m) sum(m > 0L), 0L))
    }
    if (n > 0L) counts[[id]] = n
  }
  if (length(counts)) {
    gptr_warn(paste0(
      name, " was registered after it had reached ", length(counts), " live session(s) (",
      sum(counts), " occurrence(s)). What was already sent to a model cannot be withdrawn: ",
      "rotate the key, and run gptr_scrub() to find and clean files that captured it."
    ), "secret_late", counts = counts)
  }
  invisible(NULL)
}

#' @export
#' @noRd
format.gptr_secret = function(x, ...) paste0("<secret ", x$name, " #", x$fp, ">")

#' @export
#' @noRd
print.gptr_secret = function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

#' @export
#' @noRd
as.character.gptr_secret = function(x, ...) paste0("[secret:", x$name, "]")
