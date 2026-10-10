# MCP configuration (contract 6.3, 11.7; architecture 6.14): gptr's own mcp.json (user; project
# when trusted) and the read-only discovery of the servers configured for Claude Code, Claude
# Desktop, Codex (a TOML subset), Cursor, VS Code and Pi, found under user_home() and
# app_config_dir() (IC-63). Adapted from dev/research/16-mcp-skills-plugins.md 5.11
# (mcp_config.R, verified after the fixture relocation fix) and 5.12 (toml_read.R, checked
# against RcppTOML: 36 of 39 values agree and the 3 differences are RcppTOML's). Foreign servers
# are imported on request (D-14): listed by gptr_mcp(), reachable by name, never advertised in
# the prompt catalog. gptr never writes another harness's file.

#' A TOML 1.0 reader for agent config files (base R); arrays of scalars become atomic vectors,
#' arrays of tables lists, dates stay text (report 16 section 5.12)
#' @noRd
mcp_toml_read = function(file = NULL, text = NULL) {
  if (is.null(text)) text = readLines(file, warn = FALSE, encoding = "UTF-8")
  text = as_utf8(paste(text, collapse = "\n"))
  bom = intToUtf8(65279L)
  if (startsWith(text, bom)) text = substring(text, 2L)
  ch = strsplit(gsub("\r\n", "\n", text, fixed = TRUE), "")[[1L]]
  n = length(ch)
  i = 1L
  root = structure(list(), names = character())
  cur_path = character()

  err = function(msg) {
    line = sum(ch[seq_len(min(i, n))] == "\n") + 1L
    gptr_abort(paste0("TOML parse error (line ", line, "): ", msg), "invalid_argument",
               arg = "file", expected = "valid TOML")
  }
  peek = function(k = 0L) if (i + k <= n) ch[i + k] else ""
  skip_ws = function() while (i <= n && ch[i] %in% c(" ", "\t")) i <<- i + 1L
  skip_comment = function() if (peek() == "#") while (i <= n && ch[i] != "\n") i <<- i + 1L
  skip_ws_nl_comments = function() {
    repeat {
      skip_ws()
      skip_comment()
      if (i <= n && ch[i] == "\n") {
        i <<- i + 1L
        next
      }
      break
    }
  }
  expect_eol = function() {
    skip_ws()
    skip_comment()
    if (i <= n && ch[i] != "\n") err(paste0("unexpected '", ch[i], "' after value"))
  }
  hex_char = function(len) {
    h = paste(ch[i:(i + len - 1L)], collapse = "")
    i <<- i + len
    intToUtf8(strtoi(h, 16L))
  }
  read_escape = function() {
    e = peek()
    i <<- i + 1L
    switch(e, b = "\b", t = "\t", n = "\n", f = "\f", r = "\r", `"` = "\"", `\\` = "\\",
           u = hex_char(4L), U = hex_char(8L), err(paste0("bad escape \\", e)))
  }
  read_basic = function() {
    out = character()
    repeat {
      if (i > n) err("unterminated string")
      c1 = ch[i]
      if (c1 == "\"") {
        i <<- i + 1L
        break
      }
      if (c1 == "\n") err("newline in basic string")
      if (c1 == "\\") {
        i <<- i + 1L
        out = c(out, read_escape())
      } else {
        out = c(out, c1)
        i <<- i + 1L
      }
    }
    paste(out, collapse = "")
  }
  read_ml_basic = function() {
    if (peek() == "\n") i <<- i + 1L
    out = character()
    repeat {
      if (i > n) err("unterminated multi-line string")
      if (ch[i] == "\"" && peek(1L) == "\"" && peek(2L) == "\"") {
        i <<- i + 3L
        while (peek() == "\"") {
          out = c(out, "\"")
          i <<- i + 1L
        }
        break
      }
      if (ch[i] == "\\") {
        j = i + 1L
        while (j <= n && ch[j] %in% c(" ", "\t")) j = j + 1L
        if (j <= n && ch[j] == "\n") {
          i <<- j
          while (i <= n && ch[i] %in% c(" ", "\t", "\n")) i <<- i + 1L
          next
        }
        i <<- i + 1L
        out = c(out, read_escape())
        next
      }
      out = c(out, ch[i])
      i <<- i + 1L
    }
    paste(out, collapse = "")
  }
  read_literal = function() {
    s = i
    while (i <= n && ch[i] != "'") {
      if (ch[i] == "\n") err("newline in literal string")
      i <<- i + 1L
    }
    if (i > n) err("unterminated literal string")
    v = paste(ch[seq.int(s, length.out = i - s)], collapse = "")
    i <<- i + 1L
    v
  }
  read_ml_literal = function() {
    if (peek() == "\n") i <<- i + 1L
    s = i
    while (i <= n && !(ch[i] == "'" && peek(1L) == "'" && peek(2L) == "'")) i <<- i + 1L
    if (i > n) err("unterminated multi-line literal string")
    e = i
    i <<- i + 3L
    extra = 0L
    while (peek() == "'" && extra < 2L) {
      extra = extra + 1L
      i <<- i + 1L
    }
    paste(c(ch[seq.int(s, length.out = e - s)], rep("'", extra)), collapse = "")
  }
  read_key = function() {
    parts = character()
    repeat {
      skip_ws()
      c1 = peek()
      if (c1 == "\"") {
        i <<- i + 1L
        parts = c(parts, read_basic())
      } else if (c1 == "'") {
        i <<- i + 1L
        parts = c(parts, read_literal())
      } else {
        s = i
        while (i <= n && grepl("^[A-Za-z0-9_-]$", ch[i])) i <<- i + 1L
        if (i == s) err("expected a key")
        parts = c(parts, paste(ch[s:(i - 1L)], collapse = ""))
      }
      skip_ws()
      if (peek() == ".") {
        i <<- i + 1L
        next
      }
      break
    }
    parts
  }
  radix = function(s, base) {
    d = match(strsplit(tolower(gsub("_", "", s)), "")[[1L]], c(0:9, letters[1:6])) - 1
    sum(d * base^rev(seq_along(d) - 1))
  }
  read_value = function() {
    skip_ws()
    c1 = peek()
    if (c1 == "\"") {
      if (peek(1L) == "\"" && peek(2L) == "\"") {
        i <<- i + 3L
        return(read_ml_basic())
      }
      i <<- i + 1L
      return(read_basic())
    }
    if (c1 == "'") {
      if (peek(1L) == "'" && peek(2L) == "'") {
        i <<- i + 3L
        return(read_ml_literal())
      }
      i <<- i + 1L
      return(read_literal())
    }
    if (c1 == "[") {
      i <<- i + 1L
      return(read_array())
    }
    if (c1 == "{") {
      i <<- i + 1L
      return(read_inline_table())
    }
    s = i
    while (i <= n && !(ch[i] %in% c(",", "]", "}", "\n", "#")) &&
           !(ch[i] %in% c(" ", "\t") &&
             !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", paste(ch[s:(i - 1L)], collapse = "")))) {
      i <<- i + 1L
    }
    tok = trimws(paste(ch[seq.int(s, length.out = i - s)], collapse = ""))
    if (tok == "true") return(TRUE)
    if (tok == "false") return(FALSE)
    if (grepl("^[+-]?(inf|nan)$", tok)) {
      return(if (grepl("nan", tok)) NaN else if (startsWith(tok, "-")) -Inf else Inf)
    }
    if (grepl("^0x[0-9A-Fa-f_]+$", tok)) return(radix(substring(tok, 3L), 16))
    if (grepl("^0o[0-7_]+$", tok)) return(radix(substring(tok, 3L), 8))
    if (grepl("^0b[01_]+$", tok)) return(radix(substring(tok, 3L), 2))
    if (grepl("^[+-]?[0-9][0-9_]*$", tok)) {
      v = as.numeric(gsub("_", "", tok))
      return(if (abs(v) <= .Machine$integer.max) as.integer(v) else v)
    }
    if (grepl("^[+-]?[0-9_]+(\\.[0-9_]+)?([eE][+-]?[0-9_]+)?$", tok)) {
      return(as.numeric(gsub("_", "", tok)))
    }
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{2}:[0-9]{2}", tok)) return(tok)
    err(paste0("invalid value '", tok, "'"))
  }
  simplify = function(x) {
    if (length(x) && all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, TRUE))) {
      cls = unique(vapply(x, function(e) class(e)[1L], ""))
      if (length(cls) == 1L || all(cls %in% c("integer", "numeric"))) return(unlist(x))
    }
    x
  }
  read_array = function() {
    out = list()
    repeat {
      skip_ws_nl_comments()
      if (peek() == "]") {
        i <<- i + 1L
        break
      }
      out[[length(out) + 1L]] = read_value()
      skip_ws_nl_comments()
      if (peek() == ",") {
        i <<- i + 1L
        next
      }
      if (peek() == "]") {
        i <<- i + 1L
        break
      }
      err("expected , or ] in array")
    }
    simplify(out)
  }
  read_inline_table = function() {
    tbl = structure(list(), names = character())
    skip_ws()
    if (peek() == "}") {
      i <<- i + 1L
      return(tbl)
    }
    repeat {
      key = read_key()
      skip_ws()
      if (peek() != "=") err("expected = in inline table")
      i <<- i + 1L
      tbl = set_in(tbl, key, read_value())
      skip_ws()
      if (peek() == ",") {
        i <<- i + 1L
        next
      }
      if (peek() == "}") {
        i <<- i + 1L
        break
      }
      err("expected , or } in inline table")
    }
    tbl
  }
  set_in = function(tbl, path, value) {
    if (length(path) == 1L) {
      tbl[[path]] = value
      return(tbl)
    }
    sub = tbl[[path[1L]]]
    if (is.null(sub)) sub = structure(list(), names = character())
    tbl[[path[1L]]] = set_in(sub, path[-1L], value)
    tbl
  }
  assign_rec = function(tbl, path, key, value) {
    if (!length(path)) return(set_in(tbl, key, value))
    p = path[1L]
    sub = tbl[[p]]
    if (is.null(sub)) sub = structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {
      k = length(sub)
      sub[[k]] = assign_rec(sub[[k]], path[-1L], key, value)
    } else {
      sub = assign_rec(sub, path[-1L], key, value)
    }
    tbl[[p]] = sub
    tbl
  }
  ensure_table = function(tbl, path, aot_append = FALSE) {
    p = path[1L]
    sub = tbl[[p]]
    if (length(path) == 1L) {
      if (aot_append) {
        if (is.null(sub)) sub = list()
        sub[[length(sub) + 1L]] = structure(list(), names = character())
      } else if (is.null(sub)) {
        sub = structure(list(), names = character())
      }
      tbl[[p]] = sub
      return(tbl)
    }
    if (is.null(sub)) sub = structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {
      k = length(sub)
      sub[[k]] = ensure_table(sub[[k]], path[-1L], aot_append)
    } else {
      sub = ensure_table(sub, path[-1L], aot_append)
    }
    tbl[[p]] = sub
    tbl
  }

  repeat {
    skip_ws_nl_comments()
    if (i > n) break
    if (peek() == "[") {
      aot = peek(1L) == "["
      i = i + if (aot) 2L else 1L
      path = read_key()
      skip_ws()
      if (aot) {
        if (peek() != "]" || peek(1L) != "]") err("expected ]]")
        i = i + 2L
      } else {
        if (peek() != "]") err("expected ]")
        i = i + 1L
      }
      root = ensure_table(root, path, aot_append = aot)
      cur_path = path
      expect_eol()
      next
    }
    key = read_key()
    skip_ws()
    if (peek() != "=") err("expected = after key")
    i = i + 1L
    val = read_value()
    root = assign_rec(root, cur_path, key, val)
    expect_eol()
  }
  root
}

# ---- reading the configurations --------------------------------------------------------------

#' Harness prefixes of foreign servers' `source` (gptr's own are "gptr:user", "gptr:project")
#' @noRd
mcp_harnesses = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi")

#' The config files gptr reads, in precedence order for a trusted project (earlier rows win)
#' @noRd
mcp_config_sources = function(project = project_root()) {
  home = user_home()
  codex_home = Sys.getenv("CODEX_HOME")
  if (!nzchar(codex_home)) codex_home = file.path(home, ".codex")
  src = function(harness, scope, path, format) {
    list(harness = harness, scope = scope, path = path, format = format)
  }
  list(
    src("gptr", "project", file.path(project, ".gptr", "mcp.json"), "mcpServers"),
    src("gptr", "user", file.path(gptr_user_dir("config"), "mcp.json"), "mcpServers"),
    src("claude-code", "local", file.path(home, ".claude.json"), "claude.local"),
    src("claude-code", "project", file.path(project, ".mcp.json"), "mcpServers"),
    src("claude-code", "user", file.path(home, ".claude.json"), "mcpServers"),
    src("claude-desktop", "user", file.path(app_config_dir("Claude"), "claude_desktop_config.json"),
        "mcpServers"),
    src("codex", "project", file.path(project, ".codex", "config.toml"), "codex"),
    src("codex", "user", file.path(codex_home, "config.toml"), "codex"),
    src("cursor", "project", file.path(project, ".cursor", "mcp.json"), "mcpServers"),
    src("cursor", "user", file.path(home, ".cursor", "mcp.json"), "mcpServers"),
    src("vscode", "project", file.path(project, ".vscode", "mcp.json"), "vscode"),
    src("vscode", "user", file.path(app_config_dir("Code"), "User", "mcp.json"), "vscode"),
    src("pi", "project", file.path(project, ".pi", "mcp.json"), "mcpServers"),
    src("pi", "user", file.path(home, ".pi", "agent", "mcp.json"), "mcpServers"))
}

#' One entry of any harness as the fields of gptr's `mcp_server` spec (contract 11.7) plus
#' `path`, `needs_input` (VS Code ${input:...}) and `startable` (FALSE for project entries of
#' an untrusted project). Fields are read exactly: `$` would read Codex's env_vars as env.
#' @noRd
mcp_entry_norm = function(name, e, harness, scope, path) {
  type = as.character(e[["type"]] %||% "")
  url = e[["url"]] %||% e[["httpUrl"]]
  transport = if (identical(type, "sse")) {
    "sse"
  } else if (type %in% c("http", "streamable-http", "streamableHttp")) {
    "http"
  } else if (!is.null(e[["command"]])) {
    "stdio"
  } else if (!is.null(url)) {
    "http"
  } else {
    NA_character_
  }
  env = e[["env"]]
  headers = e[["headers"]]
  tool_exposure = e[["toolExposure"]]
  timeout = e[["timeout"]]
  if (identical(harness, "codex")) {
    for (v in mcp_map_chr(e[["env_vars"]])) env[[v]] = paste0("${", v, "}")
    headers = c(headers, e[["http_headers"]])
    for (h in names(e[["env_http_headers"]])) {
      headers[[h]] = paste0("${", as.character(e[["env_http_headers"]][[h]]), "}")
    }
    if (!is.null(e[["bearer_token_env_var"]])) {
      headers[["Authorization"]] = paste0("Bearer ${", e[["bearer_token_env_var"]], "}")
    }
    timeout = e[["tool_timeout_sec"]]
    te = list()
    for (t in mcp_map_chr(e[["disabled_tools"]])) te[[t]] = "hidden"
    if (length(e[["enabled_tools"]])) {
      for (t in mcp_map_chr(e[["enabled_tools"]])) te[[t]] = "r"
      te[["*"]] = "hidden"
    }
    if (length(te)) tool_exposure = te
  }
  if (!is.null(timeout)) {
    # seconds in gptr's mcp.json (contract 11.7) and in Codex's tool_timeout_sec; milliseconds in
    # Claude Code's files; the other harnesses' values of 1000 or more are taken as milliseconds
    timeout = as.numeric(timeout)[1L]
    ms = identical(harness, "claude-code") ||
      (!harness %in% c("gptr", "codex") && isTRUE(timeout >= 1000))
    if (ms) timeout = timeout / 1000
  }
  exposure = mcp_map_chr(e[["exposure"]])
  if (!is.null(exposure) && !exposure[1L] %in% c("r", "direct", "deferred", "hidden")) {
    exposure = NULL
  }
  protocol = as.character(e[["protocol"]] %||% "auto")
  if (!protocol %in% c("auto", "modern", "legacy")) protocol = "auto"
  raw = json_encode(list(env = e[["env"]], headers = e[["headers"]], args = e[["args"]]))
  out = list(name = name, transport = transport, command = mcp_map_chr(e[["command"]])[1L],
             args = mcp_map_chr(e[["args"]]) %||% character(), env = mcp_map_chr(env),
             headers = mcp_map_chr(headers),
             cwd = mcp_map_chr(e[["cwd"]])[1L], url = mcp_map_chr(url)[1L], timeout = timeout,
             protocol = protocol, exposure = exposure[1L], toolExposure = tool_exposure,
             enabled = !isFALSE(e[["enabled"]]) && !isTRUE(e[["disabled"]]),
             trusted = identical(harness, "gptr") && identical(scope, "user") &&
               isTRUE(e[["trusted"]]),
             oauth = if (is.list(e[["oauth"]]) && length(e[["oauth"]])) e[["oauth"]],
             source = paste0(harness, ":", scope),
             path = path, also_in = character(), needs_input = grepl("${input:", raw, fixed = TRUE),
             startable = TRUE)
  out[!vapply(out, is.null, NA)]
}

#' Parse one config file into entries; a parse failure is a registry diagnostic, never an error
#' @noRd
mcp_read_source = function(src, project) {
  if (!file.exists(src$path)) return(list())
  x = tryCatch({
    if (identical(src$format, "codex")) {
      mcp_toml_read(src$path)
    } else {
      json_decode(read_utf8(src$path)$text)
    }
  }, error = function(e) {
    registry_diagnostic("builtin:mcp", "mcp_config", "parse",
                        paste0("cannot parse ", src$path, ": ", conditionMessage(e)))
    NULL
  })
  if (!is.list(x)) return(list())
  entries = switch(src$format,
    mcpServers = x$mcpServers,
    claude.local = {
      keys = as.character(names(x$projects))
      hit = keys[path_key(keys) == path_key(project)]
      if (length(hit)) x$projects[[hit[1L]]]$mcpServers else NULL
    },
    vscode = x$servers,
    codex = x$mcp_servers,
    NULL)
  defaults = if (identical(src$harness, "gptr") && is.list(x$defaults)) x$defaults else list()
  out = list()
  for (nm in names(entries)) {
    e = entries[[nm]]
    if (!is.list(e)) next
    for (k in intersect(names(defaults), c("exposure", "timeout", "protocol"))) {
      if (is.null(e[[k]])) e[[k]] = defaults[[k]]
    }
    out[[length(out) + 1L]] = mcp_entry_norm(nm, e, src$harness, src$scope, src$path)
  }
  out
}

#' Every configured server (contract 7.18): gptr's project file over gptr's user file (the other
#' way round in an untrusted project) over the harnesses of setting `mcp.import`. A server with
#' the same transport, command, args and url in several harnesses is listed once with `also_in`;
#' a foreign name collision is renamed `<harness>_<name>`; project entries of an untrusted
#' project get `startable = FALSE`.
#' @noRd
mcp_config_all = function(project = project_root()) {
  import = mcp_map_chr(setting_get("mcp.import", default = mcp_harnesses))
  trusted = trust_ok(project)
  srcs = mcp_config_sources(project)
  if (!trusted) srcs[1:2] = srcs[2:1]
  all = list()
  for (src in srcs) {
    if (!identical(src$harness, "gptr") && !src$harness %in% import) next
    for (s in mcp_read_source(src, project)) {
      if (identical(src$scope, "project")) s$startable = trusted
      all[[length(all) + 1L]] = s
    }
  }
  fp = vapply(all, function(s) {
    paste(s$transport, s$command %||% "", paste(s$args, collapse = " "), s$url %||% "", sep = "|")
  }, "")
  keep = list()
  seen_fp = character()
  seen_name = character()
  for (j in seq_along(all)) {
    s = all[[j]]
    own = startsWith(s$source, "gptr:")
    if (own && s$name %in% seen_name) next
    if (!own && fp[j] %in% seen_fp) {
      w = match(fp[j], seen_fp)
      keep[[w]]$also_in = c(keep[[w]]$also_in, s$source)
      next
    }
    if (s$name %in% seen_name) s$name = paste0(sub(":.*$", "", s$source), "_", s$name)
    keep[[length(keep) + 1L]] = s
    seen_fp = c(seen_fp, fp[j])
    seen_name = c(seen_name, s$name)
  }
  names(keep) = vapply(keep, function(s) s$name, "")
  keep
}

# ---- the registry view of the servers --------------------------------------------------------

#' Register the configured servers as `mcp_server` records: gptr:user at rank 3 (source
#' "user"), a trusted gptr:project at rank 1 (source "project"), every other entry at rank 6
#' (source "builtin:mcp"). The files are re-read only when their stamps, the trust state or the
#' import setting changed. Plugin and session records (P17) are never touched. Returns the
#' `mcp_server` specs visible to `session`, by name.
#' @noRd
mcp_sync = function(force = FALSE, session = NULL) {
  st = mcp_state()
  project = project_root()
  srcs = mcp_config_sources(project)
  info = file.info(vapply(srcs, function(s) s$path, ""))
  stamp = paste(c(project, info$size, as.numeric(info$mtime), trust_ok(project),
                  mcp_map_chr(setting_get("mcp.import"))), collapse = "|")
  if (!isTRUE(force) && identical(st$stamp, stamp)) return(mcp_servers_all(session))
  for (nm in ls(st$servers)) {
    registry_remove(get(nm, envir = st$servers))
    rm(list = nm, envir = st$servers)
  }
  for (s in mcp_config_all(project)) {
    own_project = identical(s$source, "gptr:project") && isTRUE(s$startable)
    own_user = identical(s$source, "gptr:user")
    spec = tryCatch(do.call(gptr_spec, c(list("mcp_server", s$name), s[setdiff(names(s), "name")])),
                    gptr_error = function(e) {
                      registry_diagnostic("builtin:mcp", "mcp_config", "invalid_spec",
                                          paste0("server ", s$name, " (", s$source, "): ",
                                                 conditionMessage(e)))
                      NULL
                    })
    if (is.null(spec)) next
    source = if (own_project) "project" else if (own_user) "user" else "builtin:mcp"
    rank = if (own_project) 1L else if (own_user) 3L else 6L
    id = registry_add(spec, source = source, rank = rank)
    assign(s$name, id, envir = st$servers)
  }
  # tool specs live as long as the server record they were built from (mcp_spec_ensure())
  for (k in ls(st$specs)) {
    rec = get(k, envir = st$specs)
    if (!identical(registry_get("mcp_server", rec$server$name, session = rec$sid), rec$server)) {
      registry_remove(rec$id)
      rm(list = k, envir = st$specs)
    }
  }
  st$stamp = stamp
  mcp_servers_all(session)
}

#' Every `mcp_server` spec visible to `session` (configured, registered with gptr_register(),
#' plugins), by name
#' @noRd
mcp_servers_all = function(session = NULL) {
  nms = registry_names("mcp_server", session = session)
  specs = lapply(nms, function(n) registry_get("mcp_server", n, session = session))
  names(specs) = nms
  specs[!vapply(specs, is.null, NA)]
}

#' Can a server be started and used?
#' @noRd
mcp_usable = function(s) {
  !isFALSE(s$enabled) && !isFALSE(s$startable) && !isTRUE(s$needs_input) &&
    isTRUE(mcp_transport(s) %in% c("stdio", "http"))
}

#' Does a server come from another harness's configuration (imported on request, D-14)?
#' @noRd
mcp_foreign = function(s) {
  src = s$source %||% ""
  any(startsWith(src, paste0(mcp_harnesses, ":")))
}

#' The canonical name of a server written as typed or as its syntactic R name
#' @noRd
mcp_server_resolve = function(name, session = NULL) {
  specs = mcp_sync(session = session)
  if (name %in% names(specs)) return(name)
  hit = names(specs)[mcp_r_name(names(specs)) == name]
  if (length(hit) == 1L) return(hit)
  gptr_abort(paste0("No MCP server named ", name, " is configured."), "unknown_member",
             name = name, available = mcp_r_name(names(Filter(mcp_usable, specs))))
}

#' A usable server spec, or the classed reason why it cannot be used
#' @noRd
mcp_server_get = function(name, session = NULL) {
  name = mcp_server_resolve(name, session)
  s = registry_get("mcp_server", name, session = session)
  if (isFALSE(s$enabled)) {
    gptr_abort(paste0("MCP server ", name, " is disabled in its configuration."),
               c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  if (isFALSE(s$startable)) {
    gptr_abort(paste0("MCP server ", name, " comes from a project you have not trusted; run ",
                      "gptr_trust() to use it."), "untrusted", what = "project MCP server",
               path = s$path %||% NA_character_, origin = NA_character_)
  }
  if (isTRUE(s$needs_input)) {
    gptr_abort(paste0("MCP server ", name, " uses VS Code ${input:...} values; add it to gptr ",
                      "with gptr_mcp_add()."), c("mcp_protocol", "mcp"), server = name,
               code = NA_integer_)
  }
  s$name = name
  s
}

#' The live connection of a server, connecting lazily (and again after an exit)
#' @noRd
mcp_conn_get = function(name, session = NULL) {
  conns = mcp_state()$conns
  conn = get0(name, envir = conns, inherits = FALSE)
  if (!is.null(conn) && isTRUE(conn$alive)) return(conn)
  conn = mcp_connect(mcp_server_get(name, session))
  assign(name, conn, envir = conns)
  conn
}

#' Tools known without connecting: the live connection's list, else the disk cache, else NULL
#' @noRd
mcp_tools_known = function(s) {
  conn = get0(s$name, envir = mcp_state()$conns, inherits = FALSE)
  if (!is.null(conn) && !is.null(conn$tools)) return(conn$tools)
  mcp_tools_cache_get(s)$tools
}

#' Exposure of one tool: the first matching toolExposure glob, else the server's exposure, else
#' the setting `mcp.exposure` ("r")
#' @noRd
mcp_tool_exposure = function(s, tool) {
  te = s$toolExposure
  for (g in names(te)) {
    if (grepl(glob_to_regex(g), tool, perl = TRUE)) return(as.character(te[[g]]))
  }
  as.character(s$exposure %||% setting_get("mcp.exposure", default = "r"))
}

#' The catalog line of a server whose tools are not known yet (nothing cached, never connected):
#' it says how to list them, since printing the server node connects (Task 7)
#' @noRd
mcp_unlisted_line = function(name) {
  paste0(mcp_r_name(name), ": tools not listed yet; print(peter$mcp$", mcp_r_name(name),
         ") lists them")
}

#' Catalog lines of one server: "<server>: <n> tools, <n> shown" and one signature per `r`
#' tool (`bare` = tools shown without their description)
#' @noRd
mcp_server_lines = function(s, tools = mcp_tools_known(s), bare = character(), exposures = "r") {
  if (is.null(tools)) return(mcp_unlisted_line(s$name))
  mine = Filter(function(t) mcp_tool_exposure(s, t$name) %in% exposures, tools)
  lines = paste0(mcp_r_name(s$name), ": ", length(mine), " tools, ", length(mine), " shown")
  for (t in mine) {
    d = if (t$name %in% bare) "" else mcp_first_sentence(t$description)
    lines = c(lines, paste0("  ", mcp_signature(t$name, t$input_schema, d)))
  }
  lines
}

# ---- writing gptr's mcp.json ------------------------------------------------------------------

#' Path of gptr's own mcp.json at a scope; the project scope needs a workspace
#' @noRd
mcp_config_path = function(scope) {
  if (identical(scope, "user")) {
    return(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"))
  }
  ws = workspace_dir()
  if (is.null(ws)) {
    gptr_abort("The project scope needs a .gptr/ workspace; run gptr_init() first.", "workspace",
               path = project_root())
  }
  file.path(ws, "mcp.json")
}

#' Read-modify-write gptr's mcp.json under the short mkdir lock (IC-71), atomically; unknown
#' keys are preserved, mcpServers stays a JSON object, a blank file reads as empty and one that
#' is not a JSON object is never replaced (as settings files)
#' @noRd
mcp_file_update = function(path, fun) {
  lock_with(path, function() {
    txt = if (file.exists(path)) read_utf8(path)$text else ""
    x = json_obj()
    if (nzchar(trimws(txt))) x = tryCatch(json_decode(txt), error = function(e) NULL)
    if (!is.list(x) || is.null(names(x))) {
      gptr_abort(paste0("gptr will not rewrite ", path, ", which is not a JSON object; fix or ",
                        "remove it."), "workspace", path = path)
    }
    x = fun(x)
    if (!length(x$mcpServers)) x$mcpServers = json_obj()
    write_atomic(path, json_encode(x, pretty = TRUE))
    invisible(x)
  })
}

#' Validate env/headers: a named character vector whose secret-looking values (a registered
#' value or a redaction pattern) must be ${VAR} placeholders (contract 6.3)
#' @noRd
mcp_check_kv = function(x, arg) {
  if (is.null(x)) return(NULL)
  check_strings(x, arg)
  if (is.null(names(x)) || any(!nzchar(names(x)))) {
    gptr_abort(paste0("`", arg, "` must be a named character vector."), "invalid_argument",
               arg = arg, expected = "a named character vector")
  }
  for (k in names(x)) {
    v = x[[k]]
    if (!grepl("${", v, fixed = TRUE) && !identical(redact(v), v)) {
      gptr_abort(paste0("The value of ", arg, "[[\"", k, "\"]] looks like a secret; write it as ",
                        "a ${VAR} placeholder and set VAR in the environment."),
                 "invalid_argument", arg = paste0(arg, "$", k),
                 expected = "a ${VAR} placeholder for secret values")
    }
  }
  x
}

#' Add or remove an MCP server in gptr's configuration
#'
#' `gptr_mcp_add()` writes a server into gptr's own `mcp.json`: the user file under
#' `tools::R_user_dir("gptr", "config")`, or `.gptr/mcp.json` of the project (used only when
#' you trust the project). It never edits another harness's files. Give exactly one of
#' `command` (a server started as a local process speaking stdio) and `url` (a Streamable HTTP
#' server). Secret values in `env` and `headers` must be `${VAR}` placeholders: they are
#' expanded from the environment when gptr connects and never stored. Nothing connects until a
#' tool is used.
#'
#' @param name Server name: 1-64 letters, digits, `_` or `-`. Its tools are reached as
#'   `peter$mcp$<name>$<tool>()` inside the `r` tool.
#' @param command,args The program and its arguments for a stdio server.
#' @param url The endpoint of a Streamable HTTP server.
#' @param env,headers Named character vectors: environment variables of a stdio server, HTTP
#'   headers of an HTTP server. Write secrets as `${VAR}` placeholders.
#' @param exposure How the model reaches the tools: `"r"` (R functions listed in the prompt),
#'   `"direct"` (declared as tools), `"deferred"` (found through `peter$search()`) or
#'   `"hidden"`.
#' @param timeout Seconds per request; progress notifications from the server extend it.
#' @param scope `"user"` (default) or `"project"`.
#' @return `gptr_mcp_add()` returns the server spec invisibly; `gptr_mcp_remove()` returns
#'   `TRUE` invisibly when a server was removed, else `FALSE`.
#' @examples
#' proj = tempfile("proj")
#' dir.create(proj)
#' old = options(gptr.project_root = proj)
#' gptr_init(proj)
#' gptr_mcp_add("fs", command = "npx",
#'              args = c("-y", "@modelcontextprotocol/server-filesystem", "."),
#'              scope = "project")
#' gptr_mcp_remove("fs", scope = "project")
#' options(old)
#' unlink(proj, recursive = TRUE)
#' @export
gptr_mcp_add = function(name, command = NULL, args = character(), url = NULL, env = NULL,
                        headers = NULL, exposure = "r", timeout = 60,
                        scope = c("user", "project")) {
  name = check_string(name, "name")
  if (!grepl("^[A-Za-z0-9_-]{1,64}$", name)) {
    gptr_abort("`name` must be 1-64 letters, digits, '_' or '-'.", "invalid_argument", arg = "name",
               expected = "a name matching ^[A-Za-z0-9_-]{1,64}$")
  }
  check_string(command, "command", null = TRUE)
  check_strings(args, "args")
  check_string(url, "url", null = TRUE)
  if (is.null(command) == is.null(url)) {
    gptr_abort(paste("Give exactly one of `command` (a stdio server) and `url` (a Streamable",
                     "HTTP server)."),
               "invalid_argument", arg = "command", expected = "exactly one of command and url")
  }
  env = mcp_check_kv(env, "env")
  headers = mcp_check_kv(headers, "headers")
  exposure = check_choice(exposure, c("r", "direct", "deferred", "hidden"), "exposure")
  timeout = check_number(timeout, "timeout", min = 1)
  scope = check_choice(scope, c("user", "project"), "scope")
  ext_control_guard("gptr_mcp_add")
  entry = if (!is.null(command)) list(command = command, args = I(args)) else list(url = url)
  if (!is.null(env)) entry$env = as.list(env)
  if (!is.null(headers)) entry$headers = as.list(headers)
  entry$exposure = exposure
  entry$timeout = timeout
  mcp_file_update(mcp_config_path(scope), function(x) {
    x$mcpServers[[name]] = entry
    x
  })
  mcp_forget_conn(name)
  mcp_sync(force = TRUE)
  ev_dispatch("mcp_servers_change", list(added = name, removed = character()))
  invisible(registry_get("mcp_server", name))
}

#' @rdname gptr_mcp_add
#' @export
gptr_mcp_remove = function(name, scope = c("user", "project")) {
  name = check_string(name, "name")
  scope = check_choice(scope, c("user", "project"), "scope")
  ext_control_guard("gptr_mcp_remove")
  path = mcp_config_path(scope)
  removed = FALSE
  if (file.exists(path)) {
    mcp_file_update(path, function(x) {
      removed <<- !is.null(x$mcpServers[[name]])
      x$mcpServers[[name]] = NULL
      x
    })
  }
  mcp_forget_conn(name)
  mcp_sync(force = TRUE)
  if (removed) ev_dispatch("mcp_servers_change", list(added = character(), removed = name))
  invisible(removed)
}

#' Close and forget the connection of a server
#' @noRd
mcp_forget_conn = function(name) {
  conns = mcp_state()$conns
  if (exists(name, envir = conns, inherits = FALSE)) {
    mcp_close(get(name, envir = conns))
    rm(list = name, envir = conns)
  }
  invisible(NULL)
}

# ---- gptr_mcp() ------------------------------------------------------------------------------

#' List MCP servers and their tools
#'
#' Without `tools`, lists gptr's servers (the user `mcp.json` and, in a trusted project,
#' `.gptr/mcp.json`) together with the servers configured for Claude Code, Claude Desktop,
#' Codex, Cursor, VS Code and Pi, which gptr reads but never edits. Nothing is started: the era
#' and the tool counts come from gptr's caches. With `tools = TRUE`, lists the tools of
#' `server` (or of every usable server) with their R signatures and catalog cost, from the
#' cache when it is fresh and otherwise by connecting (which starts stdio servers). Servers of
#' an untrusted project are listed but never started.
#'
#' @param server A server name, or `NULL` for all.
#' @param tools `TRUE` to list tools instead of servers.
#' @param refresh `TRUE` to reconnect and refresh the caches.
#' @return A `gptr_mcp_servers` data frame (`name`, `source`, `transport`, `era`, `status`,
#'   `tools`, `exposure`, `tokens`, `trusted`) or, with `tools = TRUE`, a data frame with
#'   `server`, `tool`, `signature`, `exposure` and `tokens`.
#' @seealso [gptr_mcp_add], [gptr_mcp_remove], [gptr_login], [gptr_mcp_serve];
#'   `vignette("mcp", package = "gptr")` for setup, authentication and tool calls.
#' @examples
#' gptr_mcp()
#' @export
gptr_mcp = function(server = NULL, tools = FALSE, refresh = FALSE) {
  check_string(server, "server", null = TRUE)
  tools = check_flag(tools, "tools")
  refresh = check_flag(refresh, "refresh")
  specs = mcp_sync(force = TRUE)
  if (!is.null(server)) server = mcp_server_resolve(server)
  targets = if (is.null(server)) specs else specs[server]
  rows = list()
  for (s in if (tools || refresh) targets) {
    if (!is.null(server)) mcp_server_get(s$name)
    if (!mcp_usable(s)) next
    if (refresh) {
      mcp_era_forget(s)
      mcp_forget_conn(s$name)
    }
    cached = if (!refresh) mcp_tools_cache_get(s)
    tl = if (!is.null(cached) && mcp_tools_cache_fresh(cached)) {
      cached$tools
    } else {
      # one server's failure is a diagnostic when every server is listed
      tryCatch(mcp_tools(mcp_conn_get(s$name), refresh = refresh), gptr_error = function(e) {
        if (!is.null(server)) stop(e)
        registry_diagnostic("builtin:mcp", "mcp_tools", class(e)[1L], conditionMessage(e))
      })
    }
    for (t in if (tools) tl) {
      sig = mcp_signature(t$name, t$input_schema, mcp_first_sentence(t$description))
      rows[[length(rows) + 1L]] = data.frame(server = s$name, tool = t$name, signature = sig,
                                             exposure = mcp_tool_exposure(s, t$name),
                                             tokens = est_tokens(sig, "code"),
                                             stringsAsFactors = FALSE)
    }
  }
  if (!tools) return(mcp_server_listing(specs))
  if (!length(rows)) {
    return(data.frame(server = character(), tool = character(), signature = character(),
                      exposure = character(), tokens = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' The gptr_mcp_servers listing (contract 5.12); no connection is made
#' @noRd
mcp_server_listing = function(specs) {
  conns = mcp_state()$conns
  rows = lapply(specs, function(s) {
    conn = get0(s$name, envir = conns, inherits = FALSE)
    tl = mcp_tools_known(s)
    status = if (isFALSE(s$enabled)) {
      "disabled"
    } else if (isFALSE(s$startable)) {
      "untrusted"
    } else if (identical(mcp_transport(s), "sse")) {
      "unsupported (sse)"
    } else if (isTRUE(s$needs_input)) {
      "needs input"
    } else if (!is.null(conn) && isTRUE(conn$alive)) {
      "connected"
    } else {
      "configured"
    }
    lines = mcp_server_lines(s, tl)
    data.frame(name = s$name, source = s$source %||% "registry", transport = mcp_transport(s),
               era = mcp_era_get(s)$era %||% NA_character_, status = status,
               tools = if (is.null(tl)) NA_integer_ else length(tl),
               exposure = s$exposure %||% setting_get("mcp.exposure", default = "r"),
               tokens = est_tokens(paste(lines, collapse = "\n"), "code"),
               trusted = !isFALSE(s$startable), stringsAsFactors = FALSE)
  })
  df = if (length(rows)) {
    do.call(rbind, unname(rows))
  } else {
    data.frame(name = character(), source = character(), transport = character(),
               era = character(), status = character(), tools = integer(), exposure = character(),
               tokens = numeric(), trusted = logical(), stringsAsFactors = FALSE)
  }
  rownames(df) = NULL
  new_listing(df, "gptr_mcp_servers",
              footer = paste("gptr_mcp(tools = TRUE) lists tools; gptr_mcp_add() adds a server to",
                             "gptr's mcp.json."))
}
