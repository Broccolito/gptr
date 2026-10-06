# MCP client for both protocol eras: legacy (2025-11-25 and earlier) and modern (2026-07-28)
# (REQ-30, D-14; architecture 6.14; contract 7.18).
#
# Adapted from dev/research/16-mcp-skills-plugins.md 5.3 (stdio client), 5.9 (HTTP client) and
# 5.14 (tools as R functions) and dev/research/06-pi-subagents-mcp-codemode.md 4.5.3 (argument
# coercion by schema), moved onto P04's process engine and reactor instead of blocking polls and
# httr2. Report 16's verification-log fixes are applied: the stdio probe falls back to the
# legacy handshake on any non-modern answer or a timeout (#3), a legacy HTTP cancel is a SHOULD
# (#5), stdout is read line by line through the reactor (#22). Server stderr is read by gptr and
# appended redacted to tempdir()/gptr/mcp-logs/ unless options(gptr.mcp_debug = TRUE) (IC-70).

# ---- wire helpers (pure) -------------------------------------------------------------------

mcp_k_ver = "io.modelcontextprotocol/protocolVersion"
mcp_k_caps = "io.modelcontextprotocol/clientCapabilities"
mcp_k_cinfo = "io.modelcontextprotocol/clientInfo"
mcp_k_sinfo = "io.modelcontextprotocol/serverInfo"

#' Protocol versions gptr speaks, newest first per era
#' @noRd
mcp_versions = function() {
  list(modern = "2026-07-28", legacy = c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"))
}

#' JSON text with every non-ASCII character written as a \\u escape (surrogate pairs above the
#' BMP), so servers in a C locale or a Windows code page read it intact (report 16 section 2.17)
#' @noRd
json_ascii = function(s) {
  s = as_utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)
  cp = utf8ToInt(s)
  if (anyNA(cp)) return(s)
  hi = which(cp > 127L)
  out = intToUtf8(cp, multiple = TRUE)
  v = cp[hi]
  esc = character(length(v))
  bmp = v < 65536L
  esc[bmp] = sprintf("\\u%04x", v[bmp])
  a = v[!bmp] - 65536L
  esc[!bmp] = sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] = esc
  paste(out, collapse = "")
}

#' ASCII-only JSON of an R value
#' @noRd
mcp_json = function(x) json_ascii(json_encode(x))

#' The 2026-07-28 header value encoding of Mcp-Name and Mcp-Param-* ("=?base64?...?=")
#' @noRd
mcp_header_value = function(x) {
  x = as_utf8(as.character(x)[1L])
  plain = !grepl("[^\\x20-\\x7e]", x, perl = TRUE, useBytes = TRUE) &&
    !grepl("^\\s|\\s$", x) && !(startsWith(x, "=?base64?") && endsWith(x, "?="))
  if (plain) return(x)
  paste0("=?base64?", gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(x))), "?=")
}

#' Syntactic R name of an MCP tool or server name (report 06 section 4.5.3)
#' @noRd
mcp_r_name = function(x) {
  y = gsub("[^A-Za-z0-9_.]", "_", x)
  y = ifelse(grepl("^[A-Za-z]", y), y, paste0("t_", y))
  reserved = c("if", "else", "repeat", "while", "function", "for", "next", "break", "TRUE",
               "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_character_",
               "NA_complex_", "in")
  ifelse(y %in% reserved, paste0(y, "_"), y)
}

#' Registry and wire name of an MCP tool: mcp__<server>__<tool>, at most 64 characters
#' @noRd
mcp_wire_name = function(server, tool) {
  clean = function(x) gsub("[^A-Za-z0-9_-]", "_", x)
  nm = paste0("mcp__", clean(server), "__", clean(tool))
  if (nchar(nm) > 64L) nm = paste0(substr(nm, 1L, 55L), "_", substr(hash_sha256(nm), 1L, 8L))
  nm
}

#' First sentence of a description, at most n characters
#' @noRd
mcp_first_sentence = function(d, n = 120L) {
  d = first_sentence(gsub("\\s+", " ", trimws(as.character(d %||% ""))))
  if (nchar(d) > n) d = paste0(substr(d, 1L, n - 3L), "...")
  d
}

#' Abort for an argument that does not fit the tool's schema
#' @noRd
mcp_arg_error = function(path, what) {
  gptr_abort(paste0(path, " must be ", what, "."), "invalid_argument", arg = path, expected = what)
}

#' One scalar converted by conv(); NA becomes NULL (the field is omitted), and a value conv()
#' cannot turn into one non-missing scalar ("abc" for a number) is an argument error
#' @noRd
mcp_scalar = function(x, conv, what, path) {
  if (length(x) != 1L) mcp_arg_error(path, what)
  if (is.list(x)) x = x[[1L]]
  if (is.atomic(x) && length(x) == 1L && is.na(x)) return(NULL)
  v = suppressWarnings(conv(x))
  if (length(v) != 1L || is.na(v)) mcp_arg_error(path, what)
  v
}

#' A finite number for json_encode(): a whole number beyond the integer range, up to 2^53 - 1
#' (RFC 8259 section 6), becomes verbatim JSON with every digit, because json_encode() keeps 15
#' significant digits (1759600000000123 would be sent as 1.75960000000012e+15); any other
#' number is returned as it is
#' @noRd
mcp_number = function(v) {
  big = abs(v) > .Machine$integer.max && abs(v) <= 2^53 - 1 && v == round(v)
  if (big) json_verbatim(sprintf("%.0f", v)) else v
}

#' A value without schema guidance: factors become strings, data frames arrays of rows
#' @noRd
mcp_plain = function(x) {
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE])))
  x
}

#' An R value made JSON-ready by a JSON Schema: arrays stay arrays at length 1, objects need
#' names and an empty one is {}, integers must be whole, NA and NULL fields are omitted (report
#' 06's coerce_to_schema() in gptr's json_encode(auto_unbox = TRUE) world)
#' @noRd
mcp_coerce = function(x, schema, path = "args") {
  if (is.null(x) || (is.atomic(x) && length(x) == 1L && is.na(x))) return(NULL)
  if (!is.list(schema) || !length(schema)) return(mcp_plain(x))
  variants = schema$anyOf %||% schema$oneOf
  if (!is.null(variants)) {
    for (v in variants) {
      r = tryCatch(mcp_coerce(x, v, path), gptr_error = function(e) NULL)
      if (!is.null(r)) return(r)
    }
    return(mcp_plain(x))
  }
  type = schema$type
  if (is.list(type) || length(type) > 1L) type = setdiff(as.character(unlist(type)), "null")[1L]
  if (is.null(type) || is.na(type)) {
    type = if (!is.null(schema$properties)) {
      "object"
    } else if (!is.null(schema$items)) {
      "array"
    } else {
      "any"
    }
  }
  if (is.factor(x)) x = as.character(x)
  whole = function(v) {
    if (!is.numeric(v) || !is.finite(v) || v != round(v)) mcp_arg_error(path, "a whole number")
    if (abs(v) > 2^53 - 1) mcp_arg_error(path, "a whole number of at most 2^53 - 1 in magnitude")
    if (abs(v) <= .Machine$integer.max) as.integer(v) else mcp_number(v)
  }
  number = function(v) {
    v = as.numeric(v)
    if (is.finite(v)) mcp_number(v) else NA_real_
  }
  switch(type,
    string = mcp_scalar(x, as.character, "a single string", path),
    number = mcp_scalar(x, number, "a single number", path),
    integer = mcp_scalar(x, whole, "a single whole number", path),
    boolean = mcp_scalar(x, as.logical, "TRUE or FALSE", path),
    array = {
      if (is.data.frame(x)) x = lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
      lapply(seq_along(x), function(i) {
        mcp_coerce(x[[i]], schema$items, sprintf("%s[[%d]]", path, i))
      })
    },
    object = {
      if (!is.list(x)) x = as.list(x)
      if (length(x) && (is.null(names(x)) || any(!nzchar(names(x))))) {
        mcp_arg_error(path, "a named list")
      }
      props = schema$properties %||% list()
      out = lapply(names(x), function(n) mcp_coerce(x[[n]], props[[n]], paste0(path, "$", n)))
      names(out) = names(x)
      out = out[!vapply(out, is.null, NA)]
      if (length(out)) out else json_obj()
    },
    mcp_plain(x))
}

#' A tool of tools/list in gptr's shape: list(name, title, description, input_schema,
#' annotations, output_schema)
#' @noRd
mcp_tool_norm = function(t) {
  schema = t$inputSchema
  if (!is.list(schema)) schema = list(type = "object")
  list(name = as.character(t$name), title = t$title,
       description = as_utf8(as.character(t$description %||% "")), input_schema = schema,
       annotations = t$annotations %||% list(), output_schema = t$outputSchema)
}

#' A tools/call result as list(content, structured, is_error, text, images, elapsed); the text
#' is what a model sees: text blocks verbatim, other blocks as short placeholders
#' @noRd
mcp_result_parse = function(res, elapsed = NA_real_) {
  blocks = res$content %||% list()
  texts = character()
  images = list()
  for (b in blocks) {
    type = as.character(b$type %||% "")
    if (identical(type, "text")) {
      texts = c(texts, as_utf8(as.character(b$text %||% "")))
    } else if (identical(type, "image") && is.character(b$data)) {
      images[[length(images) + 1L]] = block_image(b$data, mime = b$mimeType %||% "image/png",
                                                  source = "mcp")
      texts = c(texts, paste0("[image ", b$mimeType %||% "", "]"))
    } else if (identical(type, "resource")) {
      r = b$resource %||% list()
      texts = c(texts, if (is.character(r$text)) {
        as_utf8(r$text)
      } else {
        paste0("[resource ", r$uri %||% "", "]")
      })
    } else if (identical(type, "resource_link")) {
      texts = c(texts, paste0("[resource_link ", b$uri %||% "", "]"))
    } else {
      texts = c(texts, paste0("[", type, " ", b$mimeType %||% "block", "]"))
    }
  }
  list(content = blocks, structured = res$structuredContent, is_error = isTRUE(res$isError),
       text = paste(texts, collapse = "\n"), images = images, elapsed = elapsed)
}

#' The R value of a result (contract 9.4): structuredContent simplified by jsonlite (arrays of
#' objects become data frames; the one place gptr parses with simplifyVector = TRUE), else text.
#' parse_json() simplifies as fromJSON() does but never reads its input as a file name or URL.
#' @noRd
mcp_value = function(res) {
  if (!is.null(res$structured)) {
    return(jsonlite::parse_json(json_encode(res$structured), simplifyVector = TRUE))
  }
  res$text
}

#' A JSON-RPC success response
#' @noRd
mcp_rpc_ok = function(id, result) list(jsonrpc = "2.0", id = id, result = result)

#' A JSON-RPC error response
#' @noRd
mcp_rpc_err = function(id, code, message, data = NULL) {
  err = list(code = as.integer(code), message = message)
  if (!is.null(data)) err$data = data
  list(jsonrpc = "2.0", id = id, error = err)
}

#' clientCapabilities gptr declares: form elicitation (the ask UI) and roots
#' @noRd
mcp_client_caps = function() {
  list(elicitation = list(form = json_obj()), roots = list(listChanged = FALSE))
}

#' clientInfo gptr sends
#' @noRd
mcp_client_info = function() {
  list(name = "gptr", version = as.character(utils::packageVersion("gptr")))
}

#' The per-request _meta fields of 2026-07-28
#' @noRd
mcp_meta_fields = function(version) {
  stats::setNames(list(version, mcp_client_caps(), mcp_client_info()),
                  c(mcp_k_ver, mcp_k_caps, mcp_k_cinfo))
}

#' file:// URI of a local directory
#' @noRd
mcp_file_uri = function(path) {
  p = normalizePath(path, winslash = "/", mustWork = FALSE)
  paste0("file://", if (!startsWith(p, "/")) "/", utils::URLencode(p))
}

# ---- process state, caches and logs ----------------------------------------------------------

#' P18's process state `the$mcp_conns`: live connections, P18's registry ids of tool specs and
#' configured servers, the config stamp, the catalog's last-use times and the weak index of the
#' sessions builtin:mcp saw start (so a service called with a session id can find the session)
#' @noRd
mcp_state = function() {
  st = the$mcp_conns
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$conns = new.env(parent = emptyenv())
    st$specs = new.env(parent = emptyenv())
    st$servers = new.env(parent = emptyenv())
    st$lru = new.env(parent = emptyenv())
    st$sessions = new.env(parent = emptyenv())
    st$stamp = NULL
    the$mcp_conns = st
  }
  st
}

#' Transport of a server spec: "stdio", "http", "sse" (refused) or another declared type
#' @noRd
mcp_transport = function(spec) {
  if (identical(spec$type, "sse") || identical(spec$transport, "sse")) return("sse")
  t = spec$transport
  if (is.character(t) && length(t) == 1L && !is.na(t)) return(t)
  if (!is.null(spec$command)) "stdio" else if (!is.null(spec$url)) "http" else NA_character_
}

#' Cache key of a server: sha256 of its command and args, or of its URL origin and path
#' (contract 11.9)
#' @noRd
mcp_cache_key = function(spec) {
  if (!is.null(spec$url)) return(hash_sha256(canonical_json(list(url = url_for_log(spec$url)))))
  hash_sha256(canonical_json(list(command = as.character(spec$command),
                                  args = I(as.character(unlist(spec$args) %||% character())))))
}

#' A cache file under R_user_dir("gptr", "cache")/<kind>/ (directories only created to write)
#' @noRd
mcp_cache_path = function(kind, spec, create = FALSE) {
  dir = file.path(gptr_user_dir("cache", create = create), kind)
  if (create) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0(mcp_cache_key(spec), ".json"))
}

#' Read a small JSON cache file; NULL when absent, unreadable or not a JSON object
#' @noRd
mcp_cache_read = function(path) {
  if (!file.exists(path)) return(NULL)
  x = tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
  if (!is.list(x) || is.null(names(x))) return(NULL)
  x
}

#' The cached era of a server, NULL when absent, older than 7 days, or when its era is not
#' "modern" or "legacy" or its date not one string (fields read exactly, never partially)
#' @noRd
mcp_era_get = function(spec) {
  x = mcp_cache_read(mcp_cache_path("mcp-era", spec))
  one = function(v) is.character(v) && length(v) == 1L && !is.na(v)
  if (!one(x[["era"]]) || !one(x[["date"]]) || !(x[["era"]] %in% c("modern", "legacy"))) {
    return(NULL)
  }
  when = as.POSIXct(x[["date"]], format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(when) || difftime(Sys.time(), when, units = "days") > 7) return(NULL)
  x
}

#' Cache the era of a server for 7 days
#' @noRd
mcp_era_put = function(spec, era, version) {
  write_atomic(mcp_cache_path("mcp-era", spec, create = TRUE),
               json_encode(list(era = era, version = version,
                                date = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))))
}

#' Forget the cached era of a server
#' @noRd
mcp_era_forget = function(spec) invisible(unlink(mcp_cache_path("mcp-era", spec)))

#' The cached tool list of a server: list(tools, fetched_at, ttl_ms, cache_scope), or NULL
#' @noRd
mcp_tools_cache_get = function(spec) mcp_cache_read(mcp_cache_path("mcp-tools", spec))

#' Cache a tool list (the credentials are always the user's own, so cacheScope "private" is
#' cached too; contract 11.9)
#' @noRd
mcp_tools_cache_put = function(spec, tools, ttl_ms = NULL, cache_scope = NULL) {
  write_atomic(mcp_cache_path("mcp-tools", spec, create = TRUE),
               json_encode(list(tools = tools, fetched_at = as.numeric(Sys.time()) * 1000,
                                ttl_ms = ttl_ms, cache_scope = cache_scope)))
}

#' Is a cached tool list fresh? Modern servers: within ttlMs; legacy servers: 24 hours
#' @noRd
mcp_tools_cache_fresh = function(x) {
  if (is.null(x$fetched_at)) return(FALSE)
  num = function(v) if (is.numeric(v) && length(v) == 1L) v else NA_real_
  age = as.numeric(Sys.time()) * 1000 - num(x$fetched_at)
  ttl = if (is.null(x$ttl_ms)) 24 * 3600 * 1000 else num(x$ttl_ms)
  isTRUE(age <= ttl)
}

#' The redacted stderr log of a server: tempdir()/gptr/mcp-logs/ unless gptr.mcp_debug, then
#' the user cache (IC-70)
#' @noRd
mcp_log_path = function(name) {
  dir = if (isTRUE(gptr_opt("mcp_debug"))) {
    file.path(gptr_user_dir("cache", create = TRUE), "mcp-logs")
  } else {
    file.path(tempdir(), "gptr", "mcp-logs")
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0(gsub("[^A-Za-z0-9_-]", "_", name), ".log"))
}

#' Append already-redacted text to a log (open, append, close; 5 MB rotation; IC-59). The older
#' generation is removed first: file.rename() does not replace an existing file on Windows.
#' @noRd
mcp_log_append = function(path, txt) {
  txt = paste(txt, collapse = "")
  if (is.null(path) || !nzchar(txt)) return(invisible(NULL))
  if (isTRUE(file.size(path) > 5e6)) {
    unlink(paste0(path, ".1"))
    file.rename(path, paste0(path, ".1"))
  }
  con = file(path, open = "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(as_utf8(txt)), con)
  invisible(NULL)
}

#' One line of server output for the log, through the connection's persist-profile redactor
#' @noRd
mcp_log = function(conn, line) {
  if (is.null(conn$rs)) return(invisible(NULL))
  mcp_log_append(conn$log_path, conn$rs$push(paste0(line, "\n")))
}

# ---- placeholders (expanded at connect time, contract 11.7) -----------------------------------

#' Expand ${VAR}, ${VAR:-default}, ${env:VAR}, ${workspaceFolder} and ${userHome} (IC-63) in a
#' character vector or list; an unset variable without a default becomes ""
#' @noRd
mcp_expand = function(x, project = project_root()) {
  if (is.null(x)) return(NULL)
  if (is.list(x)) return(lapply(x, mcp_expand, project = project))
  if (!is.character(x)) return(x)
  out = vapply(x, mcp_expand1, "", project = project, USE.NAMES = FALSE)
  names(out) = names(x)
  out
}

#' The placeholder pattern (PCRE): `${NAME}`, `${env:NAME}`, `${NAME:-default}`; a default may
#' hold balanced braces, and so nested placeholders
#' @noRd
mcp_placeholder_re = paste0("\\$\\{(?:env:)?[A-Za-z_][A-Za-z0-9_]*",
                            "(?::-(?<d>(?:[^{}]++|\\{(?&d)\\})*))?\\}")

#' Expand the placeholders of one string in one left-to-right pass: the value of a variable is
#' spliced in literally (a value that itself contains `${...}` is never expanded again); only a
#' default, which is config text, is expanded in turn
#' @noRd
mcp_expand1 = function(s, project) {
  if (is.na(s)) return(NA_character_)
  s = as_utf8(s)
  m = gregexpr(mcp_placeholder_re, s, perl = TRUE)
  found = regmatches(s, m)[[1L]]
  if (!length(found)) return(s)
  vals = vapply(found, mcp_placeholder_value, "", project = project, USE.NAMES = FALSE)
  regmatches(s, m) = list(vals)
  as_utf8(s)
}

#' The value of one placeholder `${...}`: ${userHome} (= user_home(), IC-63),
#' ${workspaceFolder}, else the environment variable (`env:` prefix optional), its expanded `:-`
#' default when it is unset, else ""
#' @noRd
mcp_placeholder_value = function(m, project) {
  inner = substr(m, 3L, nchar(m) - 1L)
  if (identical(inner, "userHome")) return(as_utf8(user_home()))
  if (identical(inner, "workspaceFolder")) return(as_utf8(as.character(project %||% "")[1L]))
  if (startsWith(inner, "env:")) inner = substr(inner, 5L, nchar(inner))
  var = regmatches(inner, regexpr("^[A-Za-z_][A-Za-z0-9_]*", inner))
  rest = substr(inner, nchar(var) + 1L, nchar(inner))
  val = Sys.getenv(var, unset = NA_character_)
  if (!is.na(val)) return(as_utf8(val))
  if (startsWith(rest, ":-")) mcp_expand1(substr(rest, 3L, nchar(rest)), project) else ""
}

#' Is a header or environment variable name secret-like?
#' @noRd
mcp_secret_name = function(x) grepl("(?i)(key|token|secret|pass|auth|cred|cookie)", x, perl = TRUE)

#' A config map (env, headers) as a named character vector: each number or logical becomes its
#' JSON text (8080 -> "8080", TRUE -> "true"), so child_env() and headers get strings; names are
#' kept and NULL stays NULL. Not mcp_chr(): that name belongs to Task 6 (R/mcp-config.R), which
#' drops names.
#' @noRd
mcp_map_chr = function(x) {
  if (is.null(x)) return(NULL)
  text = function(v) {
    if (is.logical(v)) return(ifelse(v, "true", "false"))
    if (is.numeric(v)) return(vapply(v, json_encode, ""))
    v
  }
  y = unlist(if (is.list(x)) lapply(x, text) else text(x))
  stats::setNames(as.character(y), names(y))
}

#' The connect-time view of a spec: placeholders expanded; values that came from a placeholder
#' under a secret-like name, or that look secret, are registered in the vault at once (env
#' entries by their name; `${VAR}` placeholders of args and the URL by the variable's name)
#' @noRd
mcp_expand_spec = function(spec, project = project_root()) {
  raw_args = as.character(unlist(spec$args) %||% character())
  raw = mcp_map_chr(spec$env)
  ex = list(command = mcp_expand(spec$command, project),
            args = mcp_expand(raw_args, project),
            env = mcp_expand(raw, project), cwd = mcp_expand(spec$cwd, project),
            url = mcp_expand(spec$url, project),
            headers = mcp_expand(mcp_map_chr(spec$headers), project))
  keys = names(ex$env) %||% rep("", length(ex$env))
  for (i in seq_along(ex$env)) {
    k = keys[[i]]
    v = ex$env[[i]]
    if (is.na(k) || !nzchar(k) || is.na(v)) next
    from_var = grepl("${", raw[[i]], fixed = TRUE)
    if (nchar(v) >= 8L && ((from_var && mcp_secret_name(k)) || !identical(redact(v), v))) {
      secret_register(v, k, source = "mcp")
    }
  }
  refs = unlist(regmatches(c(raw_args, spec$url), gregexpr("\\$\\{(env:)?[A-Za-z_][A-Za-z0-9_]*",
                                                          c(raw_args, spec$url))))
  for (var in unique(sub("^\\$\\{(env:)?", "", refs))) {
    v = Sys.getenv(var, unset = "")
    if (nchar(v) >= 8L && mcp_secret_name(var)) secret_register(as_utf8(v), var, source = "mcp")
  }
  ex
}
