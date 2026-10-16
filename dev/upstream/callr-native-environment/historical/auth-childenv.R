# Child-process environments (G6 sections 3.7 and 5.3; IC-60, IC-65). child_env() returns the
# COMPLETE environment for processx (removed names are absent: processx rejects NA);
# child_env_callr() converts it for callr, whose `env` only adds variables (removed names become
# NA, which unsets them). Every profile points R_ENVIRON_USER and R_PROFILE_USER at empty files
# and drops R_ENVIRON unless passed: an Rscript child otherwise re-reads keys from ~/.Renviron,
# and callr copies that file into tempdir() (G6 verification log, item 7). Allowlists follow the
# MCP TypeScript SDK and mcptools (MIT). House style: "=" and "|>" (S-9).

#' Variables every allowlist profile keeps (the MCP SDK defaults per platform)
#' @noRd
env_allow_base = function() {
  if (.Platform$OS.type == "windows") {
    c("APPDATA", "COMSPEC", "HOMEDRIVE", "HOMEPATH", "LOCALAPPDATA", "PATH", "PATHEXT",
      "PROCESSOR_ARCHITECTURE", "PROGRAMDATA", "PROGRAMFILES", "PROGRAMFILES(X86)",
      "PROGRAMW6432", "SYSTEMDRIVE", "SYSTEMROOT", "TEMP", "TMP", "USERNAME", "USERPROFILE",
      "WINDIR")
  } else {
    c("HOME", "LOGNAME", "PATH", "SHELL", "TERM", "USER", "TMPDIR")
  }
}

# Locale, proxy, certificate and XDG variables (mcptools' additions).
env_allow_common = c("TZ", "LANG", "LANGUAGE", "LC_ALL", "LC_COLLATE", "LC_CTYPE", "LC_MESSAGES",
                     "LC_MONETARY", "LC_NUMERIC", "LC_TIME", "HTTP_PROXY", "HTTPS_PROXY",
                     "NO_PROXY", "http_proxy", "https_proxy", "no_proxy", "SSL_CERT_FILE",
                     "SSL_CERT_DIR", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE",
                     "NODE_EXTRA_CA_CERTS", "JAVA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                     "XDG_DATA_HOME", "XDG_RUNTIME_DIR")
# What an R worker additionally needs. Only gptr variables that 04 section 3.2 defines; the
# others a worker needs (GPTR_WORKER, GPTR_PROJECT_ROOT) are passed by P19 through `set =`.
# R_ARCH: callr sets the child's variables in the parent while it starts the child, when processx
# may look up its supervisor under bin/R_ARCH (WIN-1).
env_allow_r = c("R_HOME", "R_ARCH", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE", "R_USER",
                "R_USER_CONFIG_DIR", "R_USER_DATA_DIR", "R_USER_CACHE_DIR", "GPTR_SUBAGENT_DEPTH")

#' The six built-in profiles as child_env spec fields (base, keep, drop, set, billing)
#' @noRd
child_env_profiles_builtin = function() {
  base = c(env_allow_base(), env_allow_common)
  none = structure(character(), names = character())     # an empty named chr
  no_billing = structure(list(), names = character())    # an empty named list
  claude_billing = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                     "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                     "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                     "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY")
  list(
    mcp = list(base = "allowlist", keep = base, drop = character(), set = none,
               billing = no_billing),
    worker = list(base = "allowlist", keep = c(base, env_allow_r), drop = character(), set = none,
                  billing = no_billing),
    `cli-claude` = list(
      base = "inherit",
      keep = c("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_GIT_BASH_PATH"),
      drop = "^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)", set = none,
      billing = list(vars = claude_billing)
    ),
    `cli-codex` = list(
      base = "inherit", keep = "CODEX_HOME", drop = "^(CODEX_MANAGED_|CODEX_SANDBOX)", set = none,
      billing = list(vars = c("OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN",
                              "OPENAI_BASE_URL"))
    ),
    helper = list(base = "inherit", keep = character(), drop = character(),
                  set = c(NO_COLOR = "1", TERM = "dumb", PAGER = "cat", GIT_PAGER = "cat",
                          GIT_TERMINAL_PROMPT = "0", PYTHONIOENCODING = "utf-8",
                          PYTHONUNBUFFERED = "1"),
                  billing = no_billing),
    artifact = list(base = "inherit", keep = character(), drop = character(), set = none,
                    billing = no_billing)
  )
}

#' A profile: the registered child_env spec, else the built-in table
#' @noRd
child_env_profile = function(profile) {
  spec = tryCatch(registry_get("child_env", profile), error = function(e) NULL)
  if (is.null(spec)) spec = child_env_profiles_builtin()[[profile]]
  if (is.null(spec)) {
    gptr_abort("`profile` must name a child-environment profile.", "invalid_argument",
               arg = "profile",
               expected = paste("mcp, worker, cli-claude, cli-codex, helper, artifact",
                                "or a child_env spec"))
  }
  spec
}

#' An empty file in tempdir() for R_ENVIRON_USER / R_PROFILE_USER (truncated if changed)
#' @noRd
child_env_empty_file = function(name) {
  dir = file.path(tempdir(), "gptr", "childenv")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  f = file.path(dir, name)
  if (!file.exists(f) || !identical(file.size(f), 0)) file.create(f, showWarnings = FALSE)
  if (!file.exists(f) || dir.exists(f) || !identical(file.size(f), 0)) {
    gptr_abort("Could not create an empty R startup file.", "io", operation = "write", path = f)
  }
  normalizePath(f, winslash = "/", mustWork = TRUE)
}

#' Validate environment names without echoing names or values
#' @noRd
child_env_names = function(nm, arg, unique = TRUE) {
  if (!is.character(nm) || anyNA(nm) || any(!nzchar(nm)) ||
      any(grepl("[=[:cntrl:]]", nm)) || (unique && anyDuplicated(toupper(nm)))) {
    gptr_abort("Environment names must be non-empty and contain no equals or control characters.",
               "invalid_argument", arg = arg, expected = "valid unique environment names")
  }
  invisible(nm)
}

#' Validate explicit values (named strings or handles) before any secret is materialised
#' @noRd
child_env_values = function(values) {
  if (!(is.character(values) || is.list(values)) || is.object(values) ||
      (length(values) && is.null(names(values)))) {
    gptr_abort("Environment values must be named strings or secret handles.", "invalid_argument",
               arg = "set", expected = "named strings or handles")
  }
  child_env_names(names(values) %||% character(), "set")
  valid = vapply(values, function(v) inherits(v, "gptr_secret") || rlang::is_string(v), NA)
  if (!all(valid)) {
    gptr_abort("Environment values must be single strings or secret handles.", "invalid_argument",
               arg = "set", expected = "named strings or handles")
  }
  invisible(values)
}

#' Put validated named values into an environment vector, replacing any case variant
#' @noRd
child_env_put = function(out, values) {
  for (nm in names(values)) {
    v = values[[nm]]
    if (inherits(v, "gptr_secret")) v = secret_value(v, secret_bound_origin(v))
    out = out[toupper(names(out)) != toupper(nm)]
    out[[nm]] = as_utf8(v)
  }
  out
}

#' The key a provider's worker needs, as a named character vector (empty when none is found)
#' @noRd
child_env_provider_key = function(provider) {
  spec = tryCatch(registry_get("provider", provider), error = function(e) NULL)
  if (is.null(spec)) {
    gptr_abort("`provider` must name a registered provider.", "invalid_argument",
               arg = "provider", expected = "a registered provider id")
  }
  if (is.function(spec[["auth"]])) {
    h = spec[["auth"]]()
    if (!inherits(h, "gptr_secret")) return(character())
    origin = spec[["base_url"]] %||% secret_bound_origin(h)
    return(stats::setNames(secret_value(h, origin), h[["name"]]))
  }
  for (nm in as.character(spec[["auth"]])) {
    h = secret_lookup(nm)
    if (!is.null(h)) {
      return(stats::setNames(secret_value(h, spec[["base_url"]] %||% secret_bound_origin(h)), nm))
    }
    v = Sys.getenv(nm)
    if (nzchar(v)) {
      v = as_utf8(v)
      h = secret_register(v, nm, source = "environment")
      return(stats::setNames(secret_value(h, spec[["base_url"]]), nm))
    }
  }
  character()
}

#' The complete environment of a child process for one profile (processx form, no NA)
#' @noRd
child_env = function(profile, pass = character(), set = character(), provider = NULL) {
  check_string(profile, "profile")
  check_strings(pass, "pass")
  check_string(provider, "provider", null = TRUE)
  child_env_names(pass, "pass")
  child_env_values(set)
  spec = child_env_profile(profile)
  child_env_values(spec[["set"]] %||% character())
  env = Sys.getenv()
  env = stats::setNames(as_utf8(as.character(env)), names(env))
  env = env[!duplicated(toupper(names(env)))]
  env = env[!startsWith(env, "()")]                   # exported shell functions
  nm = names(env)
  up = toupper(nm)                                    # Windows names are case-insensitive
  pass_up = toupper(pass)
  keep_up = toupper(as.character(spec[["keep"]] %||% character()))
  billing_up = toupper(as.character(spec[["billing"]][["vars"]] %||% character()))
  if (identical(spec[["base"]], "allowlist")) {
    take = up %in% keep_up
  } else {
    contaminated = vapply(env, lits_present, NA, st = secrets_state(), USE.NAMES = FALSE)
    drop = is_secret_name(nm) | contaminated
    for (re in as.character(spec[["drop"]] %||% character())) {
      drop = drop | grepl(re, nm, perl = TRUE, ignore.case = TRUE)
    }
    take = !(drop & !(up %in% keep_up))
  }
  explicit = toupper(c(names(spec[["set"]]), names(set)))
  # a billing variable the caller passes or sets explicitly is not reported as removed
  billing = up %in% billing_up & !(up %in% c(pass_up, explicit))
  gone = sort(nm[billing & nzchar(env)])
  if (length(gone)) {
    gptr_warn(paste0("Removed ", paste(gone, collapse = ", "), " from the environment of the ",
                     profile, " child: these variables switch the CLI to API billing or to ",
                     "another account."),
              "billing_env", variables = gone,
              .once = paste0("billing_env:", profile, ":", paste(gone, collapse = ",")))
  }
  take = (take & !billing) | up %in% pass_up
  take = take & !(up == "R_ENVIRON" & !(up %in% pass_up))
  out = env[take]
  out = child_env_put(out, as.list(spec[["set"]] %||% character()))
  out = child_env_put(out, as.list(set))
  if (!is.null(provider)) {
    out = child_env_put(out, as.list(child_env_values(child_env_provider_key(provider))))
  }
  # IC-60 overrides the plan snippet: every profile neutralises both user startup files,
  # including explicit `set`. Only R_ENVIRON has the documented explicit-pass exception.
  out = out[!startsWith(out, "()") &
              !(toupper(names(out)) == "R_ENVIRON" & !("R_ENVIRON" %in% pass_up))]
  out = child_env_put(out, list(R_ENVIRON_USER = child_env_empty_file("empty.Renviron"),
                                R_PROFILE_USER = child_env_empty_file("empty.Rprofile")))
  out
}

#' The callr form of a child_env() result: every other inherited variable set to NA (unset)
#' @noRd
child_env_callr = function(env) {
  check_strings(env, "env")
  child_env_names(names(env), "env")
  current = names(Sys.getenv())
  # callr merges into the parent environment. POSIX names are case-sensitive, so an
  # omitted variant must be explicitly unset even when an upper-case replacement exists.
  key = if (.Platform$OS.type == "windows") toupper else identity
  current = current[!duplicated(key(current))]
  drop = current[!(key(current) %in% key(names(env)))]
  c(env, stats::setNames(rep(NA_character_, length(drop)), drop))
}
