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

#' Compile redaction_rule specs; invalid rules and rules matching their own marker are skipped
#' @noRd
rules_compile = function(rules) {
  out = list()
  for (r in rules) {
    marker = r$marker %||% r$name
    ok = is.character(r$pattern) && length(r$pattern) == 1L && tryCatch({
      grepl(r$pattern, "", perl = TRUE)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (ok && grepl(r$pattern, paste0("[secret:", marker, "]"), perl = TRUE)) ok = FALSE
    if (!ok) {
      registry_diagnostic(paste0("redaction_rule:", r$name), "redaction_rule", "invalid_spec",
                          paste0("Redaction rule ", r$name, " was skipped: its pattern is not ",
                                 "valid PCRE or it matches its own marker."))
      next
    }
    out[[length(out) + 1L]] = list(
      name = r$name, re = r$pattern,
      repl = r$replace %||% paste0("[secret:", marker, "]"),
      anchor = as.character(r$anchor %||% character()),
      profiles = as.character(r$profiles %||% c("stream", "code", "context", "persist"))
    )
  }
  out
}

#' The compiled rules for the current registry (the built-ins when the registry has none)
#' @noRd
rules_current = function() {
  st = secrets_state()
  if (isTRUE(st$in_rules)) return(st$rules %||% list())
  st$in_rules = TRUE
  on.exit({
    st$in_rules = FALSE
  }, add = TRUE)
  src = tryCatch(registry_all("redaction_rule"), error = function(e) NULL)
  if (!length(src)) src = redact_rules_builtin()
  if (is.null(st$rules) || !identical(src, st$rules_src)) {
    rules = rules_compile(src)
    anchors = unique(unlist(lapply(rules, function(r) r$anchor), use.names = FALSE))
    st$anchor_all = any(vapply(rules, function(r) !length(r$anchor), NA))
    st$anchor_re = paste(re_escape(anchors), collapse = "|")
    st$rules = rules
    st$rules_src = src
  }
  st$rules
}

#' Redact registered values (and derived forms) and, except for user_data, the rule layer
#' @noRd
redact = function(x, profile = "persist") {
  if (is.list(x)) return(redact_tree(x, profile))
  if (!is.character(x) || !length(x)) return(x)
  if (!(is.character(profile) && length(profile) == 1L && profile %in% redact_profiles)) {
    gptr_abort("`profile` must be one of persist, stream, context, code, user_data.",
               "invalid_argument", arg = "profile", expected = "a redaction profile")
  }
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
  if (!identical(profile, "user_data") && isTRUE(secrets_opt("redact_patterns"))) {
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
  marker = "\\[secret:[^\\]\\[\\s\"'\\\\{}]{1,200}\\]"
  markers = gregexpr(marker, y, perl = TRUE, useBytes = use_bytes)
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
  builtins = vapply(redact_rules_builtin(), function(r) r$marker, "")
  replacements = vapply(st$rules %||% list(), function(r) r$repl, "")
  pattern = "\\[secret:[^\\]\\[\\s\"'\\\\{}]{1,200}\\]"
  rule_markers = regmatches(replacements, gregexpr(pattern, replacements, perl = TRUE))
  unique(c(st$marks, paste0("[secret:", builtins, "]"), unlist(rule_markers, use.names = FALSE)))
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

#' Should structural redaction blank this value (a sensitive key, not already a marker)?
#' @noRd
structural_blank = function(k, v) {
  if (!nzchar(k) || !is.character(v) || length(v) != 1L || is.na(v)) return(FALSE)
  st = secrets_state()
  displays = vapply(st$reg, function(e) paste0("<secret ", e$name, " #", e$fp, ">"), "")
  if (v %in% c(paste0("[secret:", k, "]"), redact_known_markers(st), displays)) return(FALSE)
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
    if (!is.character(type) || length(type) != 1L || is.na(type)) type = ""
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
