# One redactor with sink profiles: registered values and their derived forms, then the rule layer.
# Adapted from dev/research/G6-secrets-redaction-end-to-end.md section 5.0 (redact(),
# redact_tree(), stream_cut(), redact_stream()) and section 5.6 (code_for_history()), with the
# verification-log fix "PRIVATE KEY(?: BLOCK)?" applied to every PEM expression. Rule shapes are
# gitleaks-derived (MIT; inst/COPYRIGHTS). House style: "=" and "|>" (S-9).

redact_profiles = c("persist", "stream", "context", "code", "user_data")
# Header and settings keys whose values structural redaction blanks (Pi bug-report.ts, MIT).
sensitive_key_re = paste0("(?:^|[-_])(api[-_]?key|secret|token|password|passwd|credential|",
                          "authorization|cookie)(?:$|[-_])")
pem_begin_re = "-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----"
pem_end_re = "-----END[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----"

#' The 12 built-in redaction rules (G6 section 3.5), as redaction_rule spec fields
#' @noRd
redact_rules_builtin = function() {
  all = c("stream", "code", "context", "persist")
  text = c("context", "persist")
  auth_re = paste0("(\\b(?:[Bb]earer|BEARER|Basic|BASIC)[ \\t]+)(?:(?=[A-Za-z._~+/=-]*[0-9])",
                   "[A-Za-z0-9._~+/=-]{16,}|",
                   "[A-Za-z0-9._~+/=-]+\\[secret:[^\\]]+\\][A-Za-z0-9._~+/=-]*|",
                   "\\[secret:[^\\]]+\\][A-Za-z0-9._~+/=-]+)")
  named_re = paste0("(?<![A-Za-z0-9_])([A-Z][A-Z0-9_]*(?:API_?KEY|ACCESS_?KEY|SECRET|TOKEN|",
                    "PASSWORD|PASSWD|PASSPHRASE|CREDENTIALS?|PRIVATE_?KEY)[A-Z0-9_]*)",
                    "([ \\t]*[=:][ \\t]*|[ \\t]{2,})([\"']?)(?=[A-Za-z._~+/=-]*[0-9])",
                    "([A-Za-z0-9._~+/=-]{12,})")
  list(
    list(name = "private-key", anchor = "PRIVATE KEY", marker = "private-key", profiles = all,
         pattern = paste0(pem_begin_re, "[\\s\\S]*?", pem_end_re)),
    list(name = "anthropic-key", anchor = "sk-ant-", marker = "anthropic-key", profiles = all,
         pattern = "(?<![A-Za-z0-9_-])sk-ant-[a-z]{2,8}[0-9]{2}-[A-Za-z0-9_-]{16,}"),
    list(name = "openai-key", anchor = "sk-", marker = "api-key", profiles = all,
         pattern = "(?<![A-Za-z0-9_-])sk-(?:proj-|svcacct-|admin-|or-v1-)?[A-Za-z0-9_-]{20,}"),
    list(name = "google-api-key", anchor = "AIza", marker = "google-api-key", profiles = all,
         pattern = "(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}(?![A-Za-z0-9_-])"),
    list(name = "github-token", anchor = c("ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_"),
         marker = "github-token", profiles = all,
         pattern = "(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})"),
    list(name = "slack-token", anchor = c("xox", "xapp-"), marker = "slack-token", profiles = all,
         pattern = paste0("(?<![A-Za-z0-9])(?:xox[abpers]-[A-Za-z0-9-]{10,}|",
                          "xapp-[0-9]-[A-Za-z0-9-]{10,})")),
    list(name = "huggingface-token", anchor = "hf_", marker = "hf-token", profiles = all,
         pattern = "(?<![A-Za-z0-9_])hf_[A-Za-z0-9]{30,}"),
    list(name = "aws-access-key", anchor = c("AKIA", "ASIA"), marker = "aws-access-key",
         profiles = all, pattern = "(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z2-7]{16}(?![A-Z0-9])"),
    list(name = "jwt", anchor = "eyJ", marker = "jwt", profiles = all,
         pattern = paste0("(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{10,}\\.eyJ[A-Za-z0-9_-]{10,}",
                          "\\.[A-Za-z0-9_-]*")),
    list(name = "auth-header", anchor = c("Bearer", "bearer", "BEARER", "Basic", "BASIC"),
         marker = "auth-header", profiles = all, replace = "\\1[secret:auth-header]",
         pattern = auth_re),
    list(name = "url-password", anchor = "://", marker = "url-password", profiles = all,
         replace = "\\1[secret:url-password]\\2",
         pattern = "(\\b[A-Za-z][A-Za-z0-9+.-]*://[^/\\s:@\\[]+:)[^/\\s@\\[]{3,}(@)"),
    list(name = "named-secret", marker = "named-secret", profiles = text,
         anchor = c("KEY", "TOKEN", "SECRET", "PASSW", "PASSPHRASE", "CREDENTIAL"),
         replace = "\\1\\2\\3[secret:\\1]", pattern = named_re)
  )
}

#' Compile redaction_rule specs (kind_check_redaction_rule() validated them at registration)
#' @noRd
rules_compile = function(rules) {
  lapply(unname(rules), function(r) {
    list(name = r$name, re = r$pattern, repl = r$replace %||% paste0("[secret:", r$marker, "]"),
         anchor = as.character(r$anchor), profiles = r$profiles)
  })
}

#' The compiled rules for the current registry (the built-ins when the registry has none)
#' @noRd
rules_current = function() {
  st = secrets_state()
  if (isTRUE(st$in_rules)) return(st$rules %||% list())
  reg = registry_env()
  # registry_all() changes only with the registry, its version or the built-in table
  key = list(reg, reg$version, the$builtins)
  if (!is.null(st$rules) && identical(key, st$rules_key)) return(st$rules)
  st$in_rules = TRUE
  on.exit({
    st$in_rules = FALSE
  }, add = TRUE)
  src = tryCatch(registry_all("redaction_rule"), error = function(e) NULL)
  if (is.null(src)) key = NULL   # a failed read is retried on the next call
  if (!length(src)) src = redact_rules_builtin()
  if (is.null(st$rules) || !identical(src, st$rules_src)) {
    rules = rules_compile(src)
    anchors = unique(unlist(lapply(rules, function(r) r$anchor), use.names = FALSE))
    st$anchor_all = any(vapply(rules, function(r) !length(r$anchor), NA))
    st$anchor_re = paste(re_escape(anchors), collapse = "|")
    st$rules = rules
    st$rules_src = src
    st$known = NULL
  }
  st$rules_key = key
  st$rules
}

#' Redact registered values (and derived forms) and, except for user_data, the rule layer
#' @noRd
redact = function(x, profile = "persist") {
  if (is.list(x)) return(redact_tree(x, profile))
  if (!is.character(x) || !length(x)) return(x)
  profile = check_choice(profile, redact_profiles, "profile")
  st = secrets_state()
  na = is.na(x)
  y = as.character(x)
  y[na] = ""
  ub = !validUTF8(y)
  if (identical(profile, "code") && length(st$lits) && any(!ub)) {
    i = which(!ub)
    y[i] = vapply(y[i], function(s) code_rewrite_literals(s)$code, "", USE.NAMES = FALSE)
  }
  if (length(st$lits)) {
    if (any(!ub)) y[!ub] = redact_literals(y[!ub], st)
    if (any(ub)) y[ub] = redact_literals(y[ub], st, use_bytes = TRUE)
  }
  if (!identical(profile, "user_data") && isTRUE(gptr_opt("redact_patterns"))) {
    rules = rules_current()
    cand = if (isTRUE(st$anchor_all)) {
      rep(TRUE, length(y))
    } else {
      grepl(st$anchor_re, y, perl = TRUE, useBytes = TRUE)
    }
    if (any(cand)) {
      for (r in rules) {
        if (!(profile %in% r$profiles)) next
        hit = cand
        if (length(r$anchor)) {
          hit = cand & Reduce(`|`, lapply(r$anchor, function(a) {
            grepl(a, y, fixed = TRUE, useBytes = TRUE)
          }))
        }
        if (any(hit & !ub)) y[hit & !ub] = gsub(r$re, r$repl, y[hit & !ub], perl = TRUE)
        if (any(hit & ub)) {
          y[hit & ub] = gsub(r$re, r$repl, y[hit & ub], perl = TRUE, useBytes = TRUE)
        }
      }
    }
    y = redact_pem_lines(y)
  }
  y[na] = NA_character_
  attributes(y) = attributes(x)
  y
}

#' Replace literal values and derived forms: long literals as fixed strings, then the alternations
#' @noRd
redact_literals = function(y, st, use_bytes = FALSE) {
  for (k in st$lits_long) {
    y = redact_literal_group(y, st$lits[k], st, fixed = TRUE, use_bytes = use_bytes)
  }
  for (re in st$lit_re) y = redact_literal_group(y, re, st, use_bytes = use_bytes)
  y
}

#' Replace literal matches outside complete secret markers, including bytewise input
#' @noRd
redact_literal_group = function(y, pattern, st, fixed = FALSE, use_bytes = FALSE) {
  encodings = Encoding(y)
  if (use_bytes) Encoding(y) = "bytes"
  matches = gregexpr(pattern, y, perl = !fixed, fixed = fixed, useBytes = use_bytes)
  values = regmatches(y, matches)
  if (!any(lengths(values))) {
    Encoding(y) = encodings
    return(y)
  }
  markers = gregexpr(secret_marker_re, y, perl = TRUE, useBytes = use_bytes)
  marker_values = regmatches(y, markers)
  known = redact_known_markers(st)
  for (i in seq_along(values)) {
    if (!length(values[[i]])) next
    starts = matches[[i]]
    ends = starts + attr(starts, "match.length")
    protected = markers[[i]]
    protected_ends = protected + attr(protected, "match.length")
    trusted = marker_values[[i]] %in% known
    protected = protected[trusted]
    protected_ends = protected_ends[trusted]
    inside = vapply(seq_along(starts), function(j) {
      any(protected > 0L & starts[j] >= protected & ends[j] <= protected_ends)
    }, logical(1))
    replace = st$marks[match(values[[i]], st$lits)]
    replace[inside] = values[[i]][inside]
    values[[i]] = replace
  }
  regmatches(y, matches) = values
  if (use_bytes) Encoding(y) = encodings
  y
}

#' Marker metadata the redactor knows from vault entries and configured rules
#' @noRd
redact_known_markers = function(st = secrets_state()) {
  if (!is.null(st$known)) return(st$known)
  builtins = vapply(redact_rules_builtin(), function(r) r$marker, "")
  replacements = vapply(st$rules %||% list(), function(r) r$repl, "")
  rule_markers = regmatches(replacements, gregexpr(secret_marker_re, replacements, perl = TRUE))
  st$known = unique(c(st$marks, paste0("[secret:", builtins, "]"),
                      unlist(rule_markers, use.names = FALSE)))
  st$known
}

#' Does a string contain any registered literal (a value or a derived form)?
#' @noRd
lits_present = function(x, st) {
  for (k in st$lits_long) if (grepl(st$lits[k], x, fixed = TRUE)) return(TRUE)
  for (re in st$lit_re) if (grepl(re, x, perl = TRUE)) return(TRUE)
  FALSE
}

#' A PEM block split over line elements: BEGIN becomes the marker, body lines become ""
#' @noRd
redact_pem_lines = function(y) {
  if (!any(grepl("-----BEGIN", y, fixed = TRUE, useBytes = TRUE))) return(y)
  b = grep(pem_begin_re, y, perl = TRUE, useBytes = TRUE)
  if (!length(b)) return(y)
  e = grep(pem_end_re, y, perl = TRUE, useBytes = TRUE)
  for (i in b) {
    j = e[e > i][1]
    terminated = !is.na(j)
    if (!terminated) j = length(y)
    y[i] = sub(paste0("(?s)", pem_begin_re, ".*$"), "[secret:private-key]", y[i],
               perl = TRUE, useBytes = TRUE)
    if (j > i) {
      tail_j = if (terminated) {
        sub(paste0("(?s)^.*", pem_end_re), "", y[j], perl = TRUE, useBytes = TRUE)
      } else {
        ""
      }
      if (j - 1L > i) y[(i + 1L):(j - 1L)] = ""
      y[j] = tail_j
    }
  }
  y
}

#' The name of the latest active secret whose value is exactly v, or NULL
#' @noRd
secret_name_of = function(v) {
  hit = NULL
  for (e in secrets_state()$reg) {
    if (isTRUE(e$active) && identical(get(e$id, envir = vault_env(), inherits = FALSE), v)) {
      hit = e$name
    }
  }
  hit
}

#' Rewrite string literals whose value is a registered secret to Sys.getenv("NAME")
#' @noRd
code_rewrite_literals = function(code) {
  st = secrets_state()
  none = list(code = code, needs = character())
  if (!length(st$lits) || !lits_present(code, st)) return(none)
  exprs = tryCatch(parse(text = code, keep.source = TRUE), error = function(e) NULL)
  pd = if (is.null(exprs)) NULL else utils::getParseData(exprs)
  if (is.null(pd)) return(none)
  s = pd[pd$token == "STR_CONST" & pd$line1 == pd$line2, c("id", "line1", "col1", "col2", "text")]
  if (!nrow(s)) return(none)
  # getParseData() abbreviates a string constant over 1,000 characters to "[N chars quoted with
  # ...]"; getParseText() reads the full token back from the source
  s$text = utils::getParseText(pd, s$id)
  s = s[order(s$line1, s$col1, decreasing = TRUE), , drop = FALSE]
  lines = strsplit(code, "\n", fixed = TRUE)[[1]]
  needs = character()
  for (i in seq_len(nrow(s))) {
    v = tryCatch(parse(text = s$text[i], keep.source = FALSE)[[1]], error = function(e) NULL)
    if (!is.character(v) || length(v) != 1L) next
    nm = secret_name_of(v)
    # only an environment-variable name replays through Sys.getenv(); any other name (for
    # example "auth:openrouter") is left to the marker, which flags the block
    if (is.null(nm) || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", nm)) next
    # A replay name containing a registered value would itself be redacted on
    # the next pass. Keep the flagged marker instead of emitting a broken call.
    if (lits_present(nm, st)) next
    ln = lines[s$line1[i]]
    call = paste0("Sys.getenv(\"", nm, "\")")
    if (identical(substr(ln, s$col1[i], s$col2[i]), s$text[i])) {
      ln = paste0(substr(ln, 1L, s$col1[i] - 1L), call, substr(ln, s$col2[i] + 1L, nchar(ln)))
    } else {
      # In a non-UTF-8 locale the parser reports positions of an escaped copy of the line;
      # rewrite only when the literal occurs exactly once on the line.
      at = gregexpr(s$text[i], ln, fixed = TRUE)[[1]]
      if (length(at) != 1L || at[1] < 0L) next
      ln = paste0(substr(ln, 1L, at[1] - 1L), call,
                  substr(ln, at[1] + nchar(s$text[i]), nchar(ln)))
    }
    lines[s$line1[i]] = ln
    needs = c(needs, nm)
  }
  out = paste(lines, collapse = "\n")
  if (endsWith(code, "\n")) out = paste0(out, "\n")
  list(code = out, needs = unique(needs))
}

#' Should structural redaction blank this value (a sensitive key; its own marker is kept)?
#' @noRd
structural_blank = function(k, v) {
  if (!nzchar(k) || !rlang::is_string(v) || identical(v, paste0("[secret:", k, "]"))) return(FALSE)
  key = gsub("([a-z0-9])([A-Z])", "\\1_\\2", k)
  grepl(sensitive_key_re, key, ignore.case = TRUE, perl = TRUE)
}

#' Redact a nested list: every string leaf in one vectorised pass; opaque fields untouched
#' @noRd
redact_tree = function(x, profile = "persist", structural = FALSE) {
  if (is.character(x)) return(redact(x, profile))
  if (!is.list(x)) return(x)
  cls = oldClass(x)
  x = unclass(x)
  vals = character()
  paths = list()
  sets = list()
  collect = function(node, path, skip, preserve_replay = TRUE) {
    nm = names(node)
    type = node[["type"]]
    if (!rlang::is_string(type)) type = ""
    fields = if (preserve_replay) switch(type,
      text = c("signature", "text_signature", "textSignature"),
      thinking = c("signature", "thinking_signature", "thinkingSignature", "encrypted_content"),
      tool_call = c("thought_signature", "thoughtSignature"),
      toolCall = c("thought_signature", "thoughtSignature"),
      opaque = "json", character()) else character()
    replay = preserve_replay && (identical(type, "redacted_thinking") ||
      (identical(type, "thinking") && isTRUE(node[["redacted"]])))
    for (i in seq_along(node)) {
      k = if (is.null(nm)) "" else nm[i]
      if (k %in% fields || k %in% skip) next
      if (replay && identical(k, "data")) next
      if (preserve_replay && identical(type, "image") && identical(k, "data")) next
      v = node[[i]]
      if (structural && structural_blank(k, v)) {
        sets[[length(sets) + 1L]] <<- list(path = c(path, i), value = paste0("[secret:", k, "]"))
      } else if (is.character(v) && length(v) == 1L) {
        vals[length(vals) + 1L] <<- v
        paths[[length(paths) + 1L]] <<- c(path, i)
      } else if (is.character(v) && length(v) > 1L) {
        sets[[length(sets) + 1L]] <<- list(path = c(path, i), value = redact(v, profile))
      } else if (is.list(v)) {
        # Ordinary inputs and metadata are not replay content, even if they
        # contain fields shaped like a provider block.
        generic = k %in% c("input", "arguments", "raw_arguments", "details", "params", "attrs",
                           "headers", "settings", "env")
        collect(v, c(path, i), if (replay && identical(k, "gptr")) "data" else character(),
                preserve_replay && !generic)
      }
    }
  }
  collect(x, integer(), character())
  if (length(vals)) {
    red = redact(vals, profile)
    same = (is.na(red) & is.na(vals)) | (!is.na(red) & !is.na(vals) & red == vals)
    for (j in which(!same)) {
      nv = red[j]
      attributes(nv) = attributes(x[[paths[[j]]]])
      x[[paths[[j]]]] = nv
    }
  }
  for (s in sets) x[[s$path]] = s$value
  if (!is.null(cls)) class(x) = cls
  x
}

#' Redact secrets from text or from a nested list
#'
#' Replaces the values of registered secrets (and their URL-encoded, JSON-escaped and base64
#' forms) with markers such as `[secret:TYPESAFE_API_KEY]` and, except for the `user_data`
#' profile, applies the pattern layer (provider key shapes, bearer tokens, URL passwords,
#' private keys, `NAME=value` lines). gptr applies the same redactor at every sink; plugins
#' and users call it for their own logs. Redaction is idempotent and never fails on invalid
#' UTF-8 (it then matches bytewise). Opaque replay fields of messages (signatures, encrypted
#' reasoning) are never modified.
#'
#' @param x A character vector, or a list (redacted recursively).
#' @param profile The sink profile: `"persist"` (files), `"stream"` (console and events),
#'   `"context"` (text sent to a model), `"code"` (R code for a history document: a string
#'   literal whose value is a registered secret becomes `Sys.getenv("NAME")`) or `"user_data"`
#'   (registered values only).
#' @return `x` with secrets replaced by markers; the same type and attributes as `x`.
#' @section Options:
#' `gptr.redact_min_chars` (8): shortest value that is value-redacted.
#' `gptr.redact_patterns` (`TRUE`): the pattern layer; values are always redacted.
#' `gptr.stream_hold_max` (4096): streaming hold-back cap in characters.
#' `gptr.env_export` (`TRUE`): default of `gptr_env(set_env =)`.
#' `gptr.prompt_secrets` (`"redact"`): secret-looking text in prompts, `"redact"` or `"ask"`.
#' `gptr.secret_guard` (`TRUE`): guarded secret reads ask even in `auto` mode.
#' @export
#' @examples
#' gptr_redact("Authorization: Bearer abcdef0123456789abcdef")
#' gptr_redact(list(note = "db at postgres://analyst:hunter2x@db.example.test/prod"))
gptr_redact = function(x, profile = c("persist", "stream", "context", "code", "user_data")) {
  profile = check_choice(profile, redact_profiles, "profile")
  if (is.null(x)) return(NULL)
  if (is.list(x)) return(redact_tree(x, profile))
  if (!is.character(x)) {
    gptr_abort("`x` must be a character vector or a list.", "invalid_argument",
               arg = "x", expected = "a character vector or a list")
  }
  redact(x, profile)
}

on_load(redactor_set(redact))


#' Where a pending stream buffer may be cut without splitting a secret (G6 section 3.6)
#' @noRd
stream_cut = function(s) {
  n = nchar(s)
  if (!n) return(1L)
  st = secrets_state()
  rules = rules_current()
  cut = n + 1L
  m = regexpr(paste0("[", token_class, "]+$"), s, perl = TRUE)          # (a) trailing token run
  if (m > 0L) cut = as.integer(m)
  lo = max(1L, cut - 64L)                                               # (b) keyword before it
  pre = substr(s, lo, cut - 1L)
  k = regexpr("(?:[Bb]earer|BEARER|Basic|BASIC|[A-Z][A-Z0-9_]{2,})[ \\t]*[:=]?[ \\t\"']*$", pre,
              perl = TRUE)
  if (k > 0L) cut = lo + as.integer(k) - 1L
  u = regexpr("[A-Za-z][A-Za-z0-9+.-]*:(?:/(?:/[^/\\s@]*)?)?$", s, perl = TRUE)  # (c) scheme://u:p
  if (u > 0L) cut = min(cut, as.integer(u))
  h = regexpr("(?<![A-Za-z0-9-])-{1,5}(?:B(?:E(?:G(?:I(?:N[ A-Z0-9_-]{0,120})?)?)?)?)?$", s,
              perl = TRUE)                                              # (d) partial PEM header
  if (h > 0L) cut = min(cut, as.integer(h))
  b = gregexpr(pem_begin_re, s, perl = TRUE)[[1]]                       # (e) unterminated PEM
  if (b[1] > 0L) {
    last = b[length(b)]
    if (!grepl(pem_end_re, substr(s, last, n), perl = TRUE)) cut = min(cut, as.integer(last))
  }
  protected_literals = unique(c(st$lits_odd, redact_known_markers(st)))
  if (length(protected_literals)) {                                    # (f) odd literals/markers
    len = min(n, max(nchar(protected_literals)) - 1L)
    while (len >= 1L) {
      if (any(startsWith(protected_literals, substr(s, n - len + 1L, n)))) {
        cut = min(cut, n - len + 1L)
        break
      }
      len = len - 1L
    }
  }
  check_rules = cut <= n && length(rules) > 0L                          # (g) never cut a match
  if (check_rules && !isTRUE(st$anchor_all)) {
    check_rules = grepl(st$anchor_re, s, perl = TRUE, useBytes = TRUE)
  }
  if (check_rules) {
    for (r in rules) {
      anchored = vapply(r$anchor, grepl, NA, x = s, fixed = TRUE, useBytes = TRUE)
      if (length(r$anchor) && !any(anchored)) next
      g = gregexpr(r$re, s, perl = TRUE)[[1]]
      if (g[1] < 0L) next
      en = g + attr(g, "match.length") - 1L
      inside = g < cut & en >= cut
      if (any(inside)) cut = min(g[inside])
    }
  }
  cut
}

#' A streaming redactor: push(chunk) returns redacted text that is safe to emit now
#' @noRd
redact_stream = function(profile = "stream") {
  profile = check_choice(profile, redact_profiles, "profile")
  hold_max = check_number(gptr_opt("stream_hold_max"), "gptr.stream_hold_max",
                          min = 1, int = TRUE)
  rs = new.env(parent = emptyenv())
  rs$pending = ""
  rs$last = ""   # the last raw character emitted: left context for look-behinds
  rs$failed = FALSE
  # D-010: past the cap the stream fails closed, drops what it holds and stays failed
  guard = function(held = 0L) {
    if (!rs$failed && held <= hold_max) return(invisible())
    rs$failed = TRUE
    rs$pending = ""
    rs$last = ""
    gptr_abort("Streaming redaction exceeded its holding limit.", "redaction_limit",
               limit = hold_max)
  }
  emit = function(raw) {
    if (!nzchar(raw)) return("")
    if (!validUTF8(raw)) {
      rs$last = ""
      return(redact(raw, profile))
    }
    r = redact(paste0(rs$last, raw), profile)
    keep_all = !nzchar(rs$last) || !startsWith(r, rs$last)
    out = if (keep_all) r else substr(r, nchar(rs$last) + 1L, nchar(r))
    rs$last = substr(raw, nchar(raw), nchar(raw))
    out
  }
  rs$push = function(chunk) {
    guard()
    if (!length(chunk)) return("")
    rs$pending = paste0(rs$pending, paste(chunk, collapse = ""))
    if (!validUTF8(rs$pending)) {
      # a multi-byte character split across chunks: wait for the rest, within the cap
      guard(nchar(rs$pending, type = "bytes"))
      return("")
    }
    cut = stream_cut(rs$pending)
    guard(nchar(rs$pending) - cut + 1L)
    raw = substr(rs$pending, 1L, cut - 1L)
    rs$pending = substr(rs$pending, cut, nchar(rs$pending))
    emit(raw)
  }
  rs$flush = function() {
    raw = rs$pending
    guard(if (validUTF8(raw)) nchar(raw) - stream_cut(raw) + 1L else nchar(raw, type = "bytes"))
    rs$pending = ""
    emit(raw)
  }
  rs$held = function() nchar(rs$pending, type = "bytes")
  rs
}


#' Recorded code for a history document: literal secrets become Sys.getenv("NAME")
#' @noRd
code_for_history = function(code) {
  check_strings(code, "code")
  needs = attr(code, "needs", exact = TRUE) %||% character()
  check_strings(needs, "attr(code, \"needs\")")
  if (any(!grepl("\\A[A-Za-z_][A-Za-z0-9_]*\\z", needs, perl = TRUE))) {
    gptr_abort("The `needs` attribute must contain environment-variable names.",
               "invalid_argument", arg = "attr(code, \"needs\")",
               expected = "environment-variable names")
  }
  flag = "# gptr: block needs secrets that are not recorded"
  rw = code_rewrite_literals(paste(code, collapse = "\n"))
  out = redact(rw$code, "code")
  if (grepl("[secret:", out, fixed = TRUE) && !startsWith(out, flag)) {
    out = paste0(flag, "\n", out)
  }
  structure(out, needs = unique(c(needs, rw$needs)))
}


#' Files gptr_scrub() examines by default, without granting authority to transcript text
#' @noRd
scrub_default_paths = function() {
  root = workspace_root(create = FALSE)
  if (!dir.exists(root)) return(character())
  if (!is.null(workspace_dir()) && !path_inside(root, project_root())) return(character())
  dirs = file.path(root, c("sessions", "cache", "plans", "transcripts"))
  dirs = dirs[dir.exists(dirs) & path_inside(dirs, root)]
  session_dir = file.path(root, "sessions")
  docs = if (session_dir %in% dirs) scrub_bound_documents(session_dir) else character()
  c(dirs, docs)
}

#' Documents named by exact custom gptr.doc_block records, restricted to safe project paths
#' @noRd
scrub_bound_documents = function(dir) {
  docs = character()
  for (f in scrub_walk(dir)) {
    if (!endsWith(f, ".jsonl")) next
    txt = scrub_text(f, readBin(f, "raw", file.size(f)))
    if (is.null(txt)) next
    for (ln in strsplit(txt, "\n", fixed = TRUE)[[1L]]) {
      rec = tryCatch(json_decode(ln), error = function(e) NULL)
      if (!is.list(rec) || !identical(rec[["type"]], "custom") ||
          !identical(rec[["customType"]], "gptr.doc_block")) next
      data = rec[["data"]]
      d = if (is.list(data)) data[["doc"]] else NULL
      if (!rlang::is_string(d) || !nzchar(d)) next
      lexical = gsub("\\", "/", d, fixed = TRUE)
      if (grepl("^(/|~|[A-Za-z]:)|(^|/)\\.\\.(/|$)|[[:cntrl:]]", lexical)) next
      path = file.path(project_root(), lexical)
      if (file.exists(path) && !dir.exists(path) && path_inside(path, project_root()) &&
          !scrub_guarded(path)) {
        docs = c(docs, path)
      }
    }
  }
  unique(docs)
}

#' Guard configuration, credential and writer-lock metadata in default discovery
#' @noRd
scrub_guarded = function(path) {
  guarded = path_class(path) %in% c("protected", "critical", "control", "instructions")
  pattern = "(^|/)[^/]+[.]lock(/|$)|(^|/)[.]gptr/locks(/|$)"
  guarded | grepl(pattern, path, ignore.case = TRUE) |
    grepl(pattern, path_key(path), ignore.case = TRUE)
}

#' Expand a directory without escaping its resolved root or revisiting a symlink cycle
#' @noRd
scrub_walk = function(root) {
  if (!dir.exists(root)) return(root[utils::file_test("-f", root)])
  pending = root
  visited = character()
  out = character()
  while (length(pending)) {
    dir = pending[1L]
    pending = pending[-1L]
    key = path_key(dir)
    if (key %in% visited || !path_inside(dir, root)) next
    visited = c(visited, key)
    entries = list.files(dir, all.files = TRUE, full.names = TRUE, no.. = TRUE)
    entries = entries[path_inside(entries, root)]
    is_dir = dir.exists(entries)
    descend = is_dir & !endsWith(tolower(basename(entries)), ".lock")
    pending = c(pending, entries[descend])
    out = c(out, entries[!is_dir & utils::file_test("-f", entries)])
  }
  out
}

#' Expand authorized paths to regular files; explicit paths override the default scope
#' @noRd
scrub_files = function(paths) {
  default = is.null(paths)
  if (default) {
    paths = scrub_default_paths()
  } else if (!all(file.exists(paths))) {
    gptr_abort("Every element of `paths` must be an existing file or directory.",
               "invalid_argument", arg = "paths", expected = "existing files or directories")
  }
  out = unlist(lapply(paths, scrub_walk), use.names = FALSE)
  if (!length(out)) return(character())
  if (default) {
    out = out[!scrub_guarded(out)]
  }
  unique(normalizePath(out, winslash = "/", mustWork = TRUE))
}

#' Read a file as UTF-8 text, or NULL for binary content (NUL bytes or invalid UTF-8)
#' @noRd
scrub_text = function(f, raw) {
  if (!length(raw) || any(raw == as.raw(0L))) return(NULL)
  txt = rawToChar(raw)
  if (!validUTF8(txt)) return(NULL)
  Encoding(txt) = "UTF-8"
  txt
}

#' Text segments outside complete known markers (unknown marker-like text stays searchable)
#' @noRd
scrub_unmarked = function(txt, st) {
  m = gregexpr(secret_marker_re, txt, perl = TRUE)[[1L]]
  if (m[1L] < 0L) return(txt)
  known = regmatches(txt, list(m))[[1L]] %in% redact_known_markers(st)
  if (!any(known)) return(txt)
  starts = m[known]
  ends = starts + attr(m, "match.length")[known]
  substring(txt, c(1L, ends), c(starts - 1L, nchar(txt)))
}

#' Occurrences of registered values and derived forms per file and secret name
#' @noRd
scrub_scan = function(files) {
  st = secrets_state()
  out = data.frame(file = character(), secret = character(), count = integer(),
                   stringsAsFactors = FALSE)
  if (!length(files) || !length(st$lits)) return(out)
  names_of = sub("^\\[secret:(.*)\\]$", "\\1", st$marks)
  rows = list()
  for (f in files) {
    size = file.size(f)
    if (is.na(size) || size == 0) next
    raw = readBin(f, "raw", size)
    txt = scrub_text(f, raw)
    hits = character()
    if (is.null(txt)) {
      for (k in seq_along(st$lits)) {
        n = length(grepRaw(charToRaw(st$lits[k]), raw, fixed = TRUE, all = TRUE))
        hits = c(hits, rep(names_of[k], n))
      }
    } else {
      txt = scrub_unmarked(txt, st)
      for (k in st$lits_long) {                 # long literals first, as redact_literals() does
        n = sum(unlist(gregexpr(st$lits[k], txt, fixed = TRUE), use.names = FALSE) > 0L)
        if (n) {
          hits = c(hits, rep(names_of[k], n))
          txt = unlist(strsplit(txt, st$lits[k], fixed = TRUE), use.names = FALSE)
        }
      }
      for (re in st$lit_re) {
        m = unlist(regmatches(txt, gregexpr(re, txt, perl = TRUE)), use.names = FALSE)
        hits = c(hits, names_of[match(m, st$lits)])
      }
    }
    if (!length(hits)) next
    tab = table(hits)
    rows[[length(rows) + 1L]] = data.frame(file = f, secret = names(tab),
                                           count = as.integer(tab), stringsAsFactors = FALSE)
  }
  if (length(rows)) out = do.call(rbind, rows)
  rownames(out) = NULL
  out
}

#' Is this text a gptr session file (its first line is the session header)?
#' @noRd
scrub_is_session = function(txt) {
  first = regmatches(txt, regexpr("^[^\n]*", txt))
  identical(tryCatch(json_decode(first)[["type"]], error = function(e) NULL), "session")
}

#' Append the gptr.scrub custom entry (04 section 4.6) to a session file's text
#' @noRd
scrub_append_entry = function(txt, rows) {
  lines = strsplit(txt, "\n", fixed = TRUE)[[1]]
  lines = lines[nzchar(lines)]
  entries = lapply(lines, function(ln) tryCatch(json_decode(ln), error = function(e) NULL))
  entry_id = function(rec) {
    id = if (is.list(rec)) rec[["id"]] else NULL
    if (rlang::is_string(id)) id else character()
  }
  last = entries[[length(entries)]]
  parent = if (is.list(last) && !identical(last[["type"]], "session") &&
               length(entry_id(last))) entry_id(last) else NULL
  taken = unlist(lapply(entries, entry_id), use.names = FALSE)
  now = Sys.time()
  entry = list(type = "custom", id = id_entry(taken), parentId = parent,
               timestamp = format(now, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
               customType = "gptr.scrub",
               data = list(date = format(now, "%Y-%m-%d", tz = "UTC"),
                           secrets = I(redact_literals(sort(unique(rows$secret)), secrets_state())),
                           count = sum(rows$count)))
  paste0(txt, if (!endsWith(txt, "\n")) "\n", json_encode(entry), "\n")
}

#' Exclusively hold the P06 and P15 writer locks; never reclaim another owner's lock
#' @noRd
scrub_lock = function(f) {
  root = workspace_root(create = FALSE)
  lock_root = file.path(root, "locks")
  links = Sys.readlink(c(root, lock_root))
  if (any(!is.na(links) & nzchar(links)) || !path_inside(lock_root, root)) return(NULL)
  locks = c(paste0(f, ".lock"), file.path(lock_root, cli::hash_sha1(path_key(f))))
  owned = character()
  complete = FALSE
  on.exit(if (!complete) unlink(owned, recursive = TRUE), add = TRUE)
  created = format(as.numeric(ps::ps_create_time(ps::ps_handle())), digits = 17)
  for (i in seq_along(locks)) {
    lock = locks[i]
    dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
    if (!dir.create(lock, showWarnings = FALSE)) return(NULL)
    owned = c(owned, lock)
    # P06 uses two lines and the pid file's 24-hour heartbeat; P15 uses one line.
    stamp = if (i == 1L) c(as.character(Sys.getpid()), created) else paste(Sys.getpid(), created)
    write_atomic(file.path(lock, "pid"), stamp)
  }
  complete = TRUE
  owned
}

#' Rewrite one file while holding both writer locks and using its fresh on-disk contents
#' @noRd
scrub_rewrite_file = function(f) {
  locks = scrub_lock(f)
  if (is.null(locks)) return(FALSE)
  on.exit(unlink(locks, recursive = TRUE), add = TRUE)
  raw = readBin(f, "raw", file.size(f))
  txt = scrub_text(f, raw)
  if (is.null(txt)) return(FALSE)
  rows = scrub_scan(f)
  if (!nrow(rows)) return(TRUE)
  new = redact_literals(txt, secrets_state())
  if (scrub_is_session(txt)) new = scrub_append_entry(new, rows)
  # Cooperating writers are locked; an intervening external edit is left intact.
  if (!identical(readBin(f, "raw", file.size(f)), raw)) return(FALSE)
  write_atomic(f, charToRaw(new))
  TRUE
}

#' Rewrite listed text files; binary, externally changed and locked files remain untouched
#' @noRd
scrub_rewrite = function(found) {
  files = unique(found$file)
  skipped = files[!vapply(files, scrub_rewrite_file, logical(1))]
  if (length(skipped)) {
    gptr_inform(c(paste0("gptr_scrub() did not rewrite ", length(skipped),
                         " file(s) (binary content, changed files, or existing writer locks):"),
                  paste0("  ", skipped),
                  "Close writers and resolve stale locks, then run gptr_scrub() again."),
                "notice")
  }
  invisible(NULL)
}

#' Find, and optionally remove, registered secrets in persisted files
#'
#' Secrets are redacted when they enter a transcript, a cache or a document, but a value that
#' reached a file before it was registered (for example a key pasted into a prompt and only
#' later loaded with `gptr_env()`) stays there. `gptr_scrub()` scans persisted files for the
#' values of every registered secret and their derived forms and reports where they occur.
#' With `dry_run = FALSE` it rewrites those files, replacing each occurrence with a
#' `[secret:NAME]` marker; this is the only sanctioned rewrite of append-only session files,
#' each of which then gets a `gptr.scrub` entry. A key that reached a model or a commit must
#' still be rotated.
#'
#' @param paths `NULL` for the workspace's sessions, caches, spill files, plans, transcripts
#'   and safe relative document paths bound in this project. An explicit character vector of
#'   files and directories overrides that scope; directory traversal stays within each root.
#'   Binary files and files with existing writer locks (including stale locks) are reported
#'   but not rewritten.
#' @param dry_run If `TRUE` (the default), only report; if `FALSE`, rewrite the files.
#' @param error If `TRUE`, signal an error of class `gptr_error_secret_found` when any file
#'   contains a registered secret (for pre-commit hooks and CI).
#' @return A data frame with columns `file`, `secret` (the variable name) and `count`; never
#'   values. Returned visibly for a dry run, invisibly after a rewrite.
#' @export
#' @examples
#' d = tempfile("proj")
#' dir.create(d)
#' writeLines("nothing secret here", file.path(d, "notes.txt"))
#' gptr_scrub(d)
gptr_scrub = function(paths = NULL, dry_run = TRUE, error = FALSE) {
  check_strings(paths, "paths", null = TRUE)
  check_flag(dry_run, "dry_run")
  check_flag(error, "error")
  found = scrub_scan(scrub_files(paths))
  if (!dry_run && nrow(found)) scrub_rewrite(found)
  if (error && nrow(found)) {
    gptr_abort(c(paste0("Registered secrets were found",
                        " in ", length(unique(found$file)), " file(s):"),
                 paste0("  ", found$file, " (", found$secret, ": ", found$count, ")"),
                 if (dry_run) "Run gptr_scrub(dry_run = FALSE), then rotate the keys." else
                   "Rotate the keys that were exposed."),
               "secret_found", findings = found)
  }
  if (dry_run) found else invisible(found)
}
