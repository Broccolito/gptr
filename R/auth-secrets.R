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
#'
#' A value with CRLF line ends also has its LF form: proc_echo() shows a child's CRLF as LF
#' (D-019), so a multi-line value written verbatim reaches the redactor with LF line ends.
#' The LF form is the value itself as the echo shows it, so it is kept whenever the value is
#' long enough to be redacted, even when dropping the CRs leaves it under `min_len`.
#' @noRd
secret_variants = function(v, min_len = 8L) {
  j = json_encode(v)
  lf = if (grepl("\r\n", v, fixed = TRUE)) gsub("\r\n", "\n", v, fixed = TRUE)
  out = c(v, utils::URLencode(v, reserved = TRUE), substr(j, 2L, nchar(j) - 1L))
  if (nchar(v) >= 12L) {
    for (o in 0:2) {
      b = gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(paste0(strrep("A", o), v))))
      drop_head = if (o == 0L) 0L else 4L
      frag = substr(b, drop_head + 1L, nchar(b) - 4L)
      out = c(out, frag, chartr("+/", "-_", frag))
    }
  }
  out = out[nchar(out) >= min_len]
  if (!is.null(lf) && nchar(v) >= min_len) out = c(out, lf)
  unique(out)
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

#' Register secret-looking environment variables and a trusted project's .env files (ambient
#' discovery at session start; the .env part is vault-only and needs project trust)
#' @noRd
secret_discover_env = function(env = Sys.getenv()) {
  nm = names(env)
  found = 0L
  if (length(nm)) {
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
    found = sum(hit)
  }
  from_files = tryCatch(dotenv_discover(), error = function(e) 0L)
  invisible(as.integer(found + from_files))
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

#' The known strings of a nested list: every character leaf at any depth, NA dropped
#'
#' Live entries hold NA wherever a value is unknown (IC-74: the usage and cost of an unpriced
#' model or of an aborted or truncated stream), and may hold non-text leaves (numbers, flags,
#' functions, environments). Only text can carry a secret, as in redact_tree(), so the late
#' check scans the character leaves alone; a non-text leaf neither coerces nor hides its
#' neighbours.
#' @noRd
secret_known_strings = function(x) {
  if (is.character(x)) {
    x = as.vector(unclass(x), "character")
    return(x[!is.na(x)])
  }
  if (!is.list(x)) return(character())
  out = unlist(lapply(unclass(x), secret_known_strings), use.names = FALSE)
  if (is.null(out)) character() else out
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
    txt = secret_known_strings(live[[id]])
    if (!length(txt)) next
    n = 0L
    for (f in forms) {
      n = n + sum(vapply(gregexpr(f, txt, fixed = TRUE, useBytes = TRUE),
                         function(m) sum(m > 0L), 0L))
    }
    if (isTRUE(n > 0L)) counts[[id]] = n
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

# ---- secret-access classifier (G6 sections 3.8 and 5.4; extends report 18's classifier) ----
# Levels and secret-guard flags per rule; P11's secret_guard policy and classifier read them.
scan_rules = data.frame(
  rule = c("secret_env_registered", "env_dump", "env_dump_process", "vault_access", "secret_env",
           "env_dynamic", "secret_file", "keyring", "env_write", "marker", "secret_to_network",
           "tainted_to_network"),
  level = c(3L, 3L, 3L, 3L, 3L, 3L, 3L, 3L, 2L, 3L, 4L, 4L),
  guard = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)
scan_secret_path_re = paste0(
  "(^|[/\\\\])([^/\\\\]*\\.env(\\.[A-Za-z0-9_-]+)?|\\.Renviron|\\.netrc|_netrc|\\.pgpass|",
  "auth\\.json|\\.credentials\\.json|credentials(\\.json)?|id_(rsa|dsa|ecdsa|ed25519)|",
  "[^/\\\\]+\\.(pem|key|p12|pfx))$|",
  "(^|[/\\\\])(\\.ssh|\\.aws|\\.codex|\\.claude|\\.gnupg|\\.docker|\\.kube|gcloud)([/\\\\]|$)|",
  "/proc/(self|[0-9]+)/environ"
)
scan_read_funs = c("readLines", "readRDS", "readChar", "readBin", "scan", "file", "read.table",
                   "read.csv", "read.delim", "readRenviron", "fromJSON", "read_json", "read_yaml",
                   "yaml.load_file", "fread", "read_csv", "read_lines", "read_file", "vroom",
                   "read.dcf", "source", "sys.source", "load_dot_env", "file.show", "read")
scan_net_funs = c("req_perform", "req_perform_parallel", "req_perform_connection",
                  "req_perform_stream", "curl_fetch_memory", "curl_fetch_disk",
                  "curl_fetch_stream", "curl_upload", "curl", "multi_add", "download.file", "url",
                  "socketConnection", "make.socket", "url.show", "GET", "POST", "PUT", "PATCH",
                  "DELETE", "VERB", "gh", "send", "smtp_send", "request", "write.socket",
                  "ws_send")
# The namespace operators and the assignment operators. The internal namespace operator and
# the arrows are assembled so that neither the triple-colon lint nor a text scan for the arrow
# ever matches this file.
scan_ns_ops = c("::", paste0("::", ":"))
scan_assign_ops = c("=", "assign", paste0("<", "-"), paste0("<<", "-"))
scan_net_pkgs = c("", "httr2", "httr", "curl", "utils", "base", "gh", "blastula", "websocket")
scan_ns_funs = c("getFromNamespace", "asNamespace", "getNamespace", "loadNamespace")
scan_proc_funs = c("system", "system2", "shell", "run", "process", "r_bg", "r", "run_process",
                   "exec_wait")
scan_dump_cmds = c("env", "printenv", "set", "export", "declare", "Get-ChildItem", "gci", "cat",
                   "type")

#' The function name of a call (`f()`, `pkg::f()`, `obj$f()`), or ""
#' @noRd
scan_call_name = function(e) {
  h = e[[1]]
  if (is.symbol(h)) return(as.character(h))
  if (is.character(h)) return(h)
  if (is.call(h) && as.character(h[[1]])[1] %in% scan_ns_ops) return(as.character(h[[3]]))
  if (is.call(h) && identical(as.character(h[[1]])[1], "$")) return(as.character(h[[3]]))
  ""
}

#' The package of a `pkg::f()` call, or ""
#' @noRd
scan_call_pkg = function(e) {
  h = e[[1]]
  if (is.call(h) && as.character(h[[1]])[1] %in% scan_ns_ops) as.character(h[[2]]) else ""
}

#' Every string constant inside a call (depth-limited)
#' @noRd
scan_strings = function(e, depth = 0L) {
  if (is.character(e)) return(e)
  if (!is.call(e) || depth > 6L) return(character())
  parts = as.list(e)
  out = character()
  for (i in seq_along(parts)) {
    if (!identical(parts[[i]], quote(expr = ))) out = c(out, scan_strings(parts[[i]], depth + 1L))
  }
  out
}

#' Literal environment-name vectors, or NULL when resolving them would need evaluation
#' @noRd
scan_env_literals = function(e) {
  if (is.character(e)) return(list(names = e))
  if (is.null(e)) return(list(names = character()))
  if (!is.call(e) || !(scan_call_pkg(e) %in% c("", "base"))) return(NULL)
  fn = scan_call_name(e)
  parts = as.list(e)[-1L]
  if (fn == "character" && (!length(parts) ||
      (length(parts) == 1L &&
       (identical(parts[[1L]], 0) || identical(parts[[1L]], 0L))))) {
    return(list(names = character()))
  }
  if (fn != "c") return(NULL)
  out = character()
  for (i in seq_along(parts)) {
    if (identical(parts[[i]], quote(expr = ))) return(NULL)
    one = scan_env_literals(parts[[i]])
    if (is.null(one)) return(NULL)
    out = c(out, one$names)
  }
  list(names = out)
}

#' Root symbol assigned by an ordinary or replacement assignment
#' @noRd
scan_assign_target = function(e) {
  if (is.symbol(e) || is.character(e)) return(as.character(e))
  if (is.call(e) && length(e) >= 2L && !identical(e[[2L]], quote(expr = ))) {
    return(scan_assign_target(e[[2L]]))
  }
  character()
}

#' Static secret-access rules for model-written R code (never evaluates it)
#' @noRd
secret_scan = function(code, tainted = character()) {
  check_strings(code, "code")
  check_strings(tainted, "tainted")
  code = paste(code, collapse = "\n")
  registered = secret_registered_names()
  found = list()
  add = function(rule, name = "") found[[length(found) + 1L]] <<- c(rule, name)
  assigned = character()
  uses = character()
  net = FALSE
  if (grepl("[secret:", code, fixed = TRUE)) add("marker", "[secret:")
  exprs = tryCatch(parse(text = code, keep.source = FALSE), error = function(e) NULL)
  walk = function(e) {
    if (is.symbol(e)) {
      s = as.character(e)
      if (s %in% c("Sys.getenv", "readRenviron", "key_get")) add("env_dynamic", s)
      uses <<- c(uses, s)
      return(invisible())
    }
    if (!is.call(e)) return(invisible())
    fn = scan_call_name(e)
    pkg = scan_call_pkg(e)
    args = as.list(e)[-1L]
    lits = scan_strings(e)
    if (fn %in% scan_assign_ops && length(args) >= 2L) {
      pos = 1L
      if (fn == "assign") {
        arg_names = names(args) %||% rep("", length(args))
        pos = match("x", arg_names)
        if (is.na(pos)) pos = match("", arg_names)
      }
      if (!is.na(pos) && !identical(args[[pos]], quote(expr = ))) {
        assigned <<- c(assigned, scan_assign_target(args[[pos]]))
      }
    }
    if (fn %in% scan_ns_ops && length(args) == 2L) {
      internal = fn == scan_ns_ops[2] || grepl("^(secret_|the$|vault)", as.character(args[[2]]))
      if (identical(as.character(args[[1]]), "gptr") && internal) add("vault_access", "gptr")
    }
    if (fn %in% scan_ns_funs && "gptr" %in% lits) add("vault_access", "gptr")
    if (fn == "Sys.getenv") {
      arg_names = names(args) %||% rep("", length(args))
      pos = match("x", arg_names)
      if (is.na(pos)) pos = match("", arg_names)
      known = if (is.na(pos)) list(names = character()) else if (
        identical(args[[pos]], quote(expr = ))
      ) NULL else scan_env_literals(args[[pos]])
      if (!is.null(known) && !length(known$names)) {
        add("env_dump", "Sys.getenv")
      } else if (!is.null(known)) {
        for (n in known$names) {
          if (n %in% registered) {
            add("secret_env_registered", n)
          } else if (is_secret_name(n)) {
            add("secret_env", n)
          }
        }
      } else {
        add("env_dynamic", "Sys.getenv")
      }
    }
    if (fn %in% c("do.call", "get", "match.fun", "exec", "Map", "lapply", "sapply", "vapply")) {
      syms = character()
      for (i in seq_along(args)) if (is.symbol(args[[i]])) syms = c(syms, as.character(args[[i]]))
      if (any(c("Sys.getenv", "readRenviron") %in% c(lits, syms))) add("env_dynamic", fn)
    }
    if (fn %in% scan_read_funs && length(lits)) {
      hit = lits[grepl(scan_secret_path_re, path.expand(lits), perl = TRUE, ignore.case = TRUE)]
      if (length(hit)) add("secret_file", hit[1])
    }
    if (fn %in% c("key_get", "key_list", "key_get_raw") || pkg == "keyring") add("keyring", fn)
    if (fn %in% scan_proc_funs && length(lits)) {
      dump_re = paste0("(^|[[:space:];|&])(env|printenv|set|export|declare)([[:space:];|&]|$)",
                        "|environ|\\.env\\b|(^|[[:space:];|&])(Get-ChildItem|gci)",
                        "[[:space:]]+(?:-Path[[:space:]]+)?['\"]?env:")
      dumps = any(tolower(lits) %in% tolower(scan_dump_cmds)) ||
        any(grepl(dump_re, lits, perl = TRUE, ignore.case = TRUE))
      if (dumps) add("env_dump_process", fn)
      net_re = paste0("(^|[[:space:];|&(/\\\\'\"])",
                       "(curl|wget|nc|ncat|scp|ssh|Invoke-WebRequest|iwr)",
                       "(?:\\.exe)?([[:space:];|&)'\"]|$)")
      if (any(grepl(net_re, lits, perl = TRUE, ignore.case = TRUE))) net <<- TRUE
    }
    if (fn %in% scan_net_funs && pkg %in% scan_net_pkgs) net <<- TRUE
    if (fn == "Sys.setenv") add("env_write", paste(names(args), collapse = ","))
    if (is.call(e[[1]])) walk(e[[1]])
    for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) walk(args[[i]])
    invisible()
  }
  for (e in exprs) walk(e)
  rules = vapply(found, function(f) f[1], "")
  sources = intersect(rules, c("env_dump", "secret_env", "secret_env_registered", "env_dynamic",
                               "secret_file", "keyring", "vault_access", "env_dump_process"))
  taint_hit = length(intersect(uses, tainted)) > 0L
  if (net && (length(sources) || taint_hit)) {
    add(if (length(sources)) "secret_to_network" else "tainted_to_network", "network")
  }
  if (!length(found)) {
    findings = data.frame(rule = character(), name = character(), level = integer(),
                          guard = logical(), stringsAsFactors = FALSE)
  } else {
    m = do.call(rbind, found)
    findings = data.frame(rule = m[, 1], name = m[, 2], stringsAsFactors = FALSE)
    findings = findings[!duplicated(findings), , drop = FALSE]
    i = match(findings$rule, scan_rules$rule)
    findings$level = scan_rules$level[i]
    findings$guard = scan_rules$guard[i]
    rownames(findings) = NULL
  }
  list(findings = findings,
       level = if (nrow(findings)) max(findings$level) else 0L,
       guard = any(findings$guard),
       assigned = if (length(sources) || taint_hit) unique(assigned) else character())
}


# ---- builtin:secrets (S-11: the built-ins register through the same API as plugins) ----

#' builtin:secrets: secret sources, redaction rules, env aliases and child-environment profiles
#' @noRd
builtin_secrets = function(gptr) {
  gptr$register(gptr_spec(
    "secret_source", "environment",
    resolve = function(name, ctx) {
      v = Sys.getenv(name, unset = "")
      if (!nzchar(v)) return(NULL)
      v = as_utf8(v)
      secret_register(v, name, source = "environment")
      v
    },
    list = function(ctx) {
      nm = names(Sys.getenv())
      nm[is_secret_name(nm)]
    }
  ))
  gptr$register(gptr_spec(
    "secret_source", "dotenv",
    resolve = function(name, ctx) dotenv_source_resolve(name),
    list = function(ctx) dotenv_source_list()
  ))
  gptr$register(gptr_spec(
    "secret_source", "auth",
    resolve = function(name, ctx) {
      rec = auth_store_read()[[name]]
      if (!is.list(rec)) return(NULL)
      v = auth_record_values(rec)[["key"]]
      if (!is.character(v) || length(v) != 1L || !nzchar(v)) return(NULL)
      secret_register(v, auth_secret_name(name, "key"), source = "auth.json")
      v
    },
    list = function(ctx) names(auth_store_read()),
    store = function(name, value, ctx) auth_store_set(name, list(type = "api_key", key = value)),
    forget = function(name, ctx) auth_store_remove(name)
  ))
  gptr$register(gptr_spec(
    "secret_source", "keyring",
    resolve = function(name, ctx) {
      if (!requireNamespace("keyring", quietly = TRUE)) return(NULL)
      v = tryCatch(keyring::key_get("gptr", name), error = function(e) NULL)
      if (!is.character(v) || length(v) != 1L || !nzchar(v)) return(NULL)
      secret_register(v, name, source = "keyring")
      v
    },
    list = function(ctx) {
      if (!requireNamespace("keyring", quietly = TRUE)) return(character())
      tryCatch(keyring::key_list("gptr")$username, error = function(e) character())
    }
  ))
  for (r in redact_rules_builtin()) {
    gptr$register(do.call(gptr_spec, c(list("redaction_rule"), r)))
  }
  aliases = alias_builtin()
  for (canon in names(aliases)) {
    gptr$register(gptr_spec("env_alias", canon, aliases = aliases[[canon]]))
  }
  profiles = child_env_profiles_builtin()
  for (p in names(profiles)) {
    gptr$register(do.call(gptr_spec, c(list("child_env", p), profiles[[p]])))
  }
  invisible(NULL)
}

on_load(ext_declare_builtin("secrets", builtin_secrets, replaceable = FALSE))
on_load(ext_service_set("secret.lookup", secret_lookup, provided_by = "P03", builtin = "secrets"))
