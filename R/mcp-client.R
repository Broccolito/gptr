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

#' R signature of an MCP tool: its arguments under mcp_r_name(), the formals of its closure
#' @noRd
mcp_signature = function(name, schema, description, prefix = "") {
  if (length(schema$properties)) names(schema$properties) = mcp_r_name(names(schema$properties))
  schema$required = mcp_r_name(as.character(unlist(schema$required)))
  schema_signature(mcp_r_name(name), schema, description, prefix = prefix)
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

#' A config value as a character vector: numbers and logicals become their JSON text (8080 ->
#' "8080", TRUE -> "true"), names are kept and NULL stays NULL
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

# ---- connections: handshake, requests, cancellation, server requests -------------------------

#' Open a connection (contract 7.18): start the transport, then the era handshake (probe,
#' fallback, cache). Returns a `gptr_mcp_conn` environment.
#' @noRd
mcp_connect = function(spec) {
  check_list(spec, "spec", named = TRUE)
  name = as.character(spec$name %||% "server")
  transport = mcp_transport(spec)
  if (identical(transport, "sse")) {
    gptr_abort(paste0("MCP server ", name, " uses the old HTTP+SSE transport, which gptr does ",
                      "not support; use its Streamable HTTP endpoint (often the same URL ending ",
                      "in /mcp)."), c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  if (!isTRUE(transport %in% c("stdio", "http"))) {
    gptr_abort(paste0("MCP server ", name, " needs a command (stdio) or a url (Streamable HTTP)."),
               c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  conn = new.env(parent = emptyenv())
  conn$name = name
  conn$spec = spec
  conn$transport = transport
  conn$next_id = 0L
  conn$pending = new.env(parent = emptyenv())
  conn$cancelled = new.env(parent = emptyenv())
  conn$progress = new.env(parent = emptyenv())
  conn$requests = list()
  conn$alive = TRUE
  conn$era = NA_character_
  conn$version = NA_character_
  conn$tools = NULL
  conn$tools_stale = TRUE
  conn$era_from_cache = FALSE
  conn$timeout = as.numeric(spec$timeout %||% gptr_opt("mcp_timeout"))
  conn$project = project_root()
  conn$last_used = reactor_now()
  class(conn) = "gptr_mcp_conn"
  ok = FALSE
  on.exit(if (!ok) mcp_close(conn), add = TRUE)
  if (identical(transport, "stdio")) mcp_stdio_start(conn) else mcp_http_setup(conn)
  mcp_handshake(conn)
  ok = TRUE
  conn
}

#' The era handshake: a cached era skips the probe; otherwise `server/discover` with the modern
#' _meta, and on any other answer or a timeout the legacy initialize and
#' notifications/initialized (report 16 4.5 step 3)
#' @noRd
mcp_handshake = function(conn, use_cache = TRUE) {
  spec = conn$spec
  v = mcp_versions()
  want = as.character(spec$protocol %||% "auto")
  auto = identical(want, "auto")
  cached = if (use_cache && auto) mcp_era_get(spec)
  conn$era = NA_character_
  if (!is.null(cached)) {
    conn$era_from_cache = TRUE
    if (identical(cached$era, "modern")) {
      conn$era = "modern"
      conn$version = v$modern
      return(invisible(conn))
    }
    want = "legacy"
  }
  if (want %in% c("auto", "modern")) {
    probe = tryCatch(
      mcp_request(conn, "server/discover", json_obj(), timeout = gptr_opt("mcp_probe_timeout"),
                  modern = TRUE, raw = TRUE),
      gptr_error_timeout = function(e) list(error = list(code = NA_integer_, message = "timeout")))
    sup = as.character(unlist(probe$result$supportedVersions %||% probe$error$data$supported))
    if (!is.null(probe$result) && v$modern %in% sup) {
      conn$era = "modern"
      conn$version = v$modern
      conn$server_info = probe$result[["_meta"]][[mcp_k_sinfo]]
      conn$capabilities = probe$result$capabilities
      conn$instructions = probe$result$instructions
    } else if (identical(want, "modern") ||
                 isTRUE(probe$error$code == -32022L && v$modern %in% sup)) {
      if (!v$modern %in% sup) {
        gptr_abort(paste0("MCP server ", conn$name, " did not answer as a ", v$modern, " server."),
                   c("mcp_protocol", "mcp"), server = conn$name,
                   code = probe$error$code %||% NA_integer_)
      }
      conn$era = "modern"
      conn$version = v$modern
    }
  }
  if (is.na(conn$era)) {
    init = mcp_request(conn, "initialize",
                       list(protocolVersion = v$legacy[1L], capabilities = mcp_client_caps(),
                            clientInfo = mcp_client_info()), modern = FALSE)
    # NULL: the cached era was stale and mcp_request() completed a fresh handshake
    if (is.null(init)) return(invisible(conn))
    if (!isTRUE(init$protocolVersion %in% v$legacy)) {
      gptr_abort(paste0("MCP server ", conn$name, " chose protocol version ",
                        init$protocolVersion %||% "(none)", ", which gptr does not speak."),
                 c("mcp_protocol", "mcp"), server = conn$name, code = NA_integer_)
    }
    conn$era = "legacy"
    conn$version = init$protocolVersion
    conn$server_info = init$serverInfo
    conn$capabilities = init$capabilities
    conn$instructions = init$instructions
    mcp_notify(conn, "notifications/initialized")
  }
  if (auto) mcp_era_put(spec, conn$era, conn$version)
  invisible(conn)
}

#' Send a request and wait for its response on the reactor. Every request carries a progress
#' token whose notifications re-arm the soft deadline (`timeout`); the hard deadline is ten
#' times the timeout; a timeout or an interrupt cancels the request.
#' @noRd
mcp_request = function(conn, method, params = NULL, timeout = NULL, modern = NULL, raw = FALSE,
                       on_progress = NULL, retried = FALSE) {
  if (!isTRUE(conn$alive)) {
    gptr_abort(paste0("MCP server ", conn$name, " is not running."), c("mcp_protocol", "mcp"),
               server = conn$name, code = NA_integer_)
  }
  timeout = as.numeric(timeout %||% conn$timeout)
  conn$next_id = conn$next_id + 1L
  conn$last_used = reactor_now()
  id = conn$next_id
  key = as.character(id)
  modern = modern %||% identical(conn$era, "modern")
  params = params %||% json_obj()
  meta = params[["_meta"]] %||% json_obj()
  if (modern) {
    f = mcp_meta_fields(mcp_versions()$modern)
    for (k in names(f)) meta[[k]] = f[[k]]
  }
  tok = paste0("p", id)
  meta$progressToken = tok
  params[["_meta"]] = meta
  st = new.env(parent = emptyenv())
  st$deadline = reactor_now() + timeout
  st$hard = reactor_now() + 10 * timeout
  # a named closure, then assign(): lintr's object_usage_linter checks a function literal passed
  # to assign() on its own, without this function's arguments
  on_tick = function(p) {
    st$deadline = reactor_now() + timeout
    if (is.function(on_progress)) on_progress(p)
  }
  assign(tok, on_tick, envir = conn$progress)
  on.exit(if (exists(tok, envir = conn$progress, inherits = FALSE)) {
    rm(list = tok, envir = conn$progress)
  }, add = TRUE)
  msg = list(jsonrpc = "2.0", id = id, method = method, params = params)
  if (identical(conn$transport, "stdio")) {
    mcp_stdio_send(conn, msg)
  } else {
    mcp_http_send(conn, msg, st)
  }
  resp = mcp_await(conn, key, st, id, method, timeout)
  status = resp$http_status %||% NA_integer_
  if (identical(status, 401L)) {
    if (!isTRUE(retried) && !is.null(mcp_http_auth(conn, force = TRUE))) {
      return(mcp_request(conn, method, params, timeout, modern, raw, on_progress, TRUE))
    }
    mcp_auth_required(conn)
  }
  # a legacy session the server forgot: initialise again once
  if (identical(status, 404L) && !is.null(conn$session_id) && !isTRUE(retried)) {
    conn$session_id = NULL
    mcp_handshake(conn, use_cache = FALSE)
    return(mcp_request(conn, method, params, timeout, modern, raw, on_progress, TRUE))
  }
  if (raw) return(resp)
  if (!is.null(resp$error)) {
    code = suppressWarnings(as.integer(resp$error$code %||% NA_integer_))
    # over HTTP the status decides: P04 does not hand a non-2xx body (its JSON-RPC code) to on_fail
    stale = isTRUE(conn$era_from_cache) && !isTRUE(retried) &&
      isTRUE(code %in% c(-32600L, -32601L, -32602L) || status %in% c(400L, 404L))
    if (stale) {
      in_handshake = is.na(conn$era)
      conn$era_from_cache = FALSE
      mcp_era_forget(conn$spec)
      mcp_handshake(conn, use_cache = FALSE)
      # the handshake's own request is not replayed: the fresh handshake replaces it
      if (in_handshake) return(NULL)
      params[["_meta"]] = NULL
      return(mcp_request(conn, method, params, timeout, NULL, raw, on_progress, TRUE))
    }
    gptr_abort(paste0("MCP server ", conn$name, " answered ", method, " with error ",
                      format(code), ": ", as.character(resp$error$message %||% "")),
               c("mcp_protocol", "mcp"), server = conn$name, code = code)
  }
  resp$result %||% json_obj()
}

#' Pump the reactor until the response, a server request, a failed transfer, an exit or a
#' deadline
#' @noRd
mcp_await = function(conn, key, st, id, method, timeout) {
  done = function() {
    exists(key, envir = conn$pending, inherits = FALSE) || length(conn$requests) > 0L ||
      !isTRUE(conn$alive) || isTRUE(st$failed) || reactor_now() > min(st$deadline, st$hard)
  }
  # any unwind cancels, after the pump has unwound; an interrupt the pause menu resumes does not
  # unwind (G3)
  reason = "user interrupt"
  settled = FALSE
  on.exit(if (!settled) mcp_cancel(conn, id, st, reason), add = TRUE)
  repeat {
    left = min(st$deadline, st$hard) - reactor_now()
    reactor_pump(until = done, slice_ms = 50L, timeout = max(0.05, left))
    if (length(conn$requests)) {
      # an answer may wait for a person (elicitation); like progress, it re-arms the deadline
      mcp_answer_requests(conn)
      st$deadline = reactor_now() + timeout
    }
    if (exists(key, envir = conn$pending, inherits = FALSE)) {
      r = get(key, envir = conn$pending, inherits = FALSE)
      rm(list = key, envir = conn$pending)
      settled = TRUE
      return(r)
    }
    if (isTRUE(st$failed)) {
      settled = TRUE
      return(st$failure)
    }
    if (!isTRUE(conn$alive)) {
      settled = TRUE
      return(list(error = list(code = NA_integer_, message = "the server process exited"),
                  exited = TRUE))
    }
    if (reactor_now() > min(st$deadline, st$hard)) {
      reason = "timeout"
      gptr_abort(paste0("MCP server ", conn$name, " did not answer ", method, " within ",
                        format(timeout), " s."), "timeout", seconds = timeout,
                 what = paste("MCP", method))
    }
  }
}

#' Cancel an in-flight request: a late answer is dropped; stdio and legacy HTTP send
#' notifications/cancelled (queued, never awaited); modern HTTP closes the response stream,
#' which is the cancellation
#' @noRd
mcp_cancel = function(conn, id, st, reason) {
  assign(as.character(id), TRUE, envir = conn$cancelled)
  if (!is.null(st$transfer)) try(reactor_cancel(st$transfer), silent = TRUE)
  if (isTRUE(conn$alive) && (identical(conn$transport, "stdio") || identical(conn$era, "legacy"))) {
    msg = list(jsonrpc = "2.0", method = "notifications/cancelled",
               params = list(requestId = id, reason = reason))
    send = if (identical(conn$transport, "stdio")) mcp_stdio_send else mcp_http_send
    try(send(conn, msg), silent = TRUE)
  }
  invisible(NULL)
}

#' Send a notification
#' @noRd
mcp_notify = function(conn, method, params = NULL) {
  msg = list(jsonrpc = "2.0", method = method)
  if (!is.null(params)) msg$params = params
  mcp_reply(conn, msg)
}

#' Send a message that expects no answer (a notification or a response to a server request)
#' @noRd
mcp_reply = function(conn, msg) {
  if (identical(conn$transport, "stdio")) {
    mcp_stdio_send(conn, msg)
  } else {
    mcp_http_post_quiet(conn, msg)
  }
  invisible(NULL)
}

#' Route one incoming JSON-RPC message: responses by id (late answers to cancelled ids are
#' dropped), notifications to their handlers, server requests queued for mcp_answer_requests()
#' @noRd
mcp_on_message = function(conn, msg) {
  if (!is.list(msg)) return(invisible(NULL))
  id = msg$id
  if (!is.null(id) && (!is.null(msg$result) || !is.null(msg$error))) {
    k = as.character(id)
    if (exists(k, envir = conn$cancelled, inherits = FALSE)) {
      rm(list = k, envir = conn$cancelled)
      return(invisible(NULL))
    }
    assign(k, msg, envir = conn$pending)
    return(invisible(NULL))
  }
  method = msg$method
  if (is.null(method)) return(invisible(NULL))
  if (is.null(id)) {
    if (identical(method, "notifications/progress")) {
      cb = get0(as.character(msg$params$progressToken %||% ""), envir = conn$progress,
                inherits = FALSE)
      if (is.function(cb)) cb(msg$params)
    } else if (identical(method, "notifications/tools/list_changed")) {
      conn$tools_stale = TRUE
    } else if (identical(method, "notifications/message")) {
      mcp_log(conn, paste("[log]", msg$params$level %||% "info", json_encode(msg$params$data)))
    }
    return(invisible(NULL))
  }
  conn$requests[[length(conn$requests) + 1L]] = msg
  invisible(NULL)
}

#' Answer queued server requests (legacy era) outside reactor callbacks: ping, roots/list and
#' elicitation/create through the ask UI; sampling and everything else are refused
#' @noRd
mcp_answer_requests = function(conn) {
  while (length(conn$requests)) {
    req = conn$requests[[1L]]
    conn$requests = conn$requests[-1L]
    out = switch(as.character(req$method),
      ping = mcp_rpc_ok(req$id, json_obj()),
      `roots/list` = mcp_rpc_ok(req$id, mcp_roots(conn)),
      `elicitation/create` = mcp_rpc_ok(req$id, mcp_elicit(conn, req$params)),
      mcp_rpc_err(req$id, -32601L, paste("Method not supported by gptr:", req$method)))
    mcp_reply(conn, out)
  }
  invisible(NULL)
}

#' The roots gptr offers: the project directory
#' @noRd
mcp_roots = function(conn) {
  list(roots = list(list(uri = mcp_file_uri(conn$project), name = basename(conn$project))))
}

#' Answer an elicitation form through the ask UI; declined without a person (IC-43) and for the
#' URL mode
#' @noRd
mcp_elicit = function(conn, params) {
  if (!identical(params$mode %||% "form", "form") || !gptr_can_prompt()) {
    return(list(action = "decline"))
  }
  ui = if (ext_service_has("ui.get")) ext_service_get("ui.get")(NULL)
  if (is.null(ui) || !isTRUE(ui$has_ui())) return(list(action = "decline"))
  props = params$requestedSchema$properties %||% list()
  if (!length(props)) return(list(action = "accept", content = json_obj()))
  qs = lapply(seq_along(props), function(i) {
    p = props[[i]]
    lead = if (i == 1L) {
      paste0("MCP server ", conn$name, " asks: ", params$message %||% "", "\n")
    } else {
      ""
    }
    out = list(id = names(props)[i],
               question = paste0(lead, p$title %||% p$description %||% names(props)[i]),
               type = if (length(p$enum)) "single" else "text")
    if (length(p$enum)) out$options = as.character(unlist(p$enum))
    out
  })
  ans = ui$questions(qs)
  if (isTRUE(ans$cancelled)) return(list(action = "cancel"))
  content = lapply(names(props), function(nm) mcp_elicit_value(ans$answers[[nm]], props[[nm]]))
  names(content) = names(props)
  content = content[!vapply(content, is.null, NA)]
  list(action = "accept", content = if (length(content)) content else json_obj())
}

#' Convert one elicitation answer to the schema's primitive type
#' @noRd
mcp_elicit_value = function(x, p) {
  if (is.null(x) || !length(x)) return(NULL)
  x = as.character(unlist(x))
  switch(as.character(p$type %||% "string"),
    number = as.numeric(x[1L]),
    integer = as.integer(x[1L]),
    boolean = tolower(x[1L]) %in% c("true", "yes", "y", "1"),
    array = as.list(x),
    x[1L])
}

#' Answer the inputRequests of a modern input_required result (MRTR)
#' @noRd
mcp_fulfil = function(conn, requests) {
  out = lapply(names(requests), function(k) {
    r = requests[[k]]
    switch(as.character(r$method),
      `elicitation/create` = mcp_elicit(conn, r$params),
      `roots/list` = mcp_roots(conn),
      gptr_abort(paste0("MCP server ", conn$name, " asked for ", r$method,
                        "; gptr does not let servers call models or other client features."),
                 c("mcp_protocol", "mcp"), server = conn$name, code = -32601L))
  })
  names(out) = names(requests)
  if (length(out)) out else json_obj()
}

#' The paginated tool list (at most 100 pages), kept in memory and in the disk cache
#' @noRd
mcp_tools = function(conn, refresh = FALSE) {
  if (!isTRUE(refresh) && !isTRUE(conn$tools_stale) && !is.null(conn$tools)) return(conn$tools)
  tools = list()
  cursor = NULL
  ttl = NULL
  scope = NULL
  for (i in seq_len(100L)) {
    params = if (is.null(cursor)) json_obj() else list(cursor = cursor)
    res = mcp_request(conn, "tools/list", params)
    tools = c(tools, res$tools %||% list())
    ttl = res$ttlMs %||% ttl
    scope = res$cacheScope %||% scope
    cursor = res$nextCursor
    if (is.null(cursor)) break
  }
  tools = lapply(tools, mcp_tool_norm)
  if (identical(conn$transport, "http") && identical(conn$era, "modern")) {
    tools = Filter(mcp_tool_headers_ok, tools)
  }
  conn$tools = tools
  conn$tools_stale = FALSE
  mcp_tools_cache_put(conn$spec, tools, ttl, scope)
  tools
}

#' HTTP clients drop tools whose x-mcp-header annotations are invalid (2026-07-28)
#' @noRd
mcp_tool_headers_ok = function(tool) {
  h = lapply(tool$input_schema$properties, function(p) if (is.list(p)) p[["x-mcp-header"]])
  ok = function(x) is.null(x) || (rlang::is_string(x) && grepl("^[A-Za-z0-9-]+$", x))
  all(vapply(h, ok, NA))
}

#' The input schema of a tool (listing the tools first when needed)
#' @noRd
mcp_tool_schema = function(conn, tool) {
  find = function(tl) Filter(function(t) identical(t$name, tool), tl)
  hit = find(conn$tools %||% mcp_tools(conn))
  if (!length(hit)) hit = find(mcp_tools(conn, refresh = TRUE))
  if (!length(hit)) {
    gptr_abort(paste0("MCP server ", conn$name, " has no tool ", tool, "."),
               c("mcp_protocol", "mcp"),
               server = conn$name, code = -32602L)
  }
  hit[[1L]]$input_schema
}

#' Call a tool (contract 7.18): arguments coerced by the schema, progress re-arms the timer,
#' input_required rounds (MRTR) answered at most 5 times
#' @noRd
mcp_call = function(conn, tool, args, timeout = NULL, on_progress = NULL) {
  t0 = reactor_now()
  schema = mcp_tool_schema(conn, tool)
  obj = c(list(type = "object"), schema[setdiff(names(schema), "type")])
  params = list(name = tool, arguments = mcp_coerce(args %||% list(), obj, "args") %||% json_obj())
  rounds = 0L
  repeat {
    res = mcp_request(conn, "tools/call", params, timeout = timeout, on_progress = on_progress)
    if (!identical(res$resultType, "input_required")) break
    rounds = rounds + 1L
    if (rounds > 5L) {
      gptr_abort(paste0("MCP server ", conn$name, " asked for input more than 5 times in one ",
                        "call of ", tool, "."), c("mcp_protocol", "mcp"), server = conn$name,
                 code = NA_integer_)
    }
    params$inputResponses = mcp_fulfil(conn, res$inputRequests %||% list())
    if (!is.null(res$requestState)) params$requestState = res$requestState
  }
  mcp_result_parse(res, reactor_now() - t0)
}

#' Close a connection (contract 7.18): stdin closed, 2 s grace, then kill_all(); a legacy HTTP
#' session is deleted
#' @noRd
mcp_close = function(conn) {
  if (!inherits(conn, "gptr_mcp_conn")) return(invisible(FALSE))
  if (!is.null(conn$proc)) {
    p = conn$proc
    if (isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))) {
      write_close(p)
      reactor_pump(until = function() !p$is_alive(), slice_ms = 50L, timeout = 2)
      if (p$is_alive()) kill_all(p, grace = 0)
    }
    if (!is.null(conn$watch)) try(reactor_cancel(conn$watch), silent = TRUE)
  } else if (identical(conn$era, "legacy") && !is.null(conn$session_id)) {
    try(mcp_http_delete(conn), silent = TRUE)
  }
  if (!is.null(conn$rs)) mcp_log_append(conn$log_path, conn$rs$flush())
  conn$alive = FALSE
  invisible(TRUE)
}

#' Close every connection of this process (on unload and in tests)
#' @noRd
mcp_close_all = function() {
  st = mcp_state()
  for (nm in ls(st$conns)) {
    try(mcp_close(get(nm, envir = st$conns)), silent = TRUE)
    rm(list = nm, envir = st$conns)
  }
  invisible(NULL)
}

# ---- stdio transport -----------------------------------------------------------------------

#' Close the least recently used stdio connection while the stdio pool is full (IC-60: at most
#' 2 children under R CMD check, through P04's proc_pool_cap())
#' @noRd
mcp_stdio_make_room = function() {
  st = mcp_state()
  repeat {
    live = Filter(function(n) {
      x = get(n, envir = st$conns)
      identical(x$transport, "stdio") && isTRUE(x$alive)
    }, ls(st$conns))
    if (length(live) < proc_pool_cap(64L)) break
    used = vapply(live, function(n) get(n, envir = st$conns)$last_used, 0)
    victim = live[which.min(used)]
    mcp_close(get(victim, envir = st$conns))
    rm(list = victim, envir = st$conns)
  }
  invisible(NULL)
}

#' The program of a stdio server. A bare `Rscript` or `R` (the usual command of R MCP servers,
#' such as `Rscript -e "mcptools::mcp_server()"`) is this R's own binary: P04's proc_resolve()
#' refuses R by name, because R CMD check puts failing R and Rscript scripts first on PATH (IC-60)
#' @noRd
mcp_stdio_command = function(command) {
  if (!is.character(command) || length(command) != 1L) return(command)
  if (command %in% c("Rscript", "Rscript.exe")) return(rscript_path())
  if (command %in% c("R", "R.exe")) {
    return(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))
  }
  command
}

#' Start a stdio server through the process engine with the mcp child environment plus the
#' spec's expanded env (IC-60; `.cmd`/`.bat` shims run through cmd.exe /d /c call in
#' proc_spawn()); stdout and stderr lines are read by the reactor
#' @noRd
mcp_stdio_start = function(conn) {
  mcp_stdio_make_room()
  ex = mcp_expand_spec(conn$spec, conn$project)
  env = child_env("mcp", set = ex$env %||% character())
  conn$log_path = mcp_log_path(conn$name)
  conn$rs = redact_stream("persist")
  conn$proc = proc_spawn(mcp_stdio_command(ex$command), ex$args, env = env, wd = ex$cwd,
                         stdin = "|", stdout = "|", stderr = "|")
  conn$watch = reactor_proc(conn$proc,
    on_line = function(line) mcp_on_line(conn, line),
    on_exit = function(status) {
      conn$alive = FALSE
      conn$exit_status = status
    },
    stream = "stdout",
    on_stderr = function(line) mcp_log(conn, line))
  invisible(conn)
}

#' One stdout line of a stdio server (anything that is not JSON goes to the log)
#' @noRd
mcp_on_line = function(conn, line) {
  if (!nzchar(trimws(line))) return(invisible(NULL))
  msg = tryCatch(json_decode(line), error = function(e) NULL)
  if (is.null(msg)) {
    mcp_log(conn, paste("[stdout is not JSON]", substr(line, 1L, 200L)))
    return(invisible(NULL))
  }
  mcp_on_message(conn, msg)
}

#' Write one ASCII JSON line to a stdio server (non-blocking inside a pump; IC-60)
#' @noRd
mcp_stdio_send = function(conn, msg) {
  if (!isTRUE(tryCatch(conn$proc$is_alive(), error = function(e) FALSE))) {
    conn$alive = FALSE
    return(invisible(FALSE))
  }
  write_all(conn$proc, paste0(mcp_json(msg), "\n"))
  invisible(TRUE)
}

# ---- Streamable HTTP transport ---------------------------------------------------------------

#' HTTP setup: the expanded URL, its origin, the configured headers (values that came from a
#' placeholder, sit under a secret-like name or look secret travel as handles bound to the
#' server's origin) and the credential-store key "mcp:<name>"
#' @noRd
mcp_http_setup = function(conn) {
  ex = mcp_expand_spec(conn$spec, conn$project)
  conn$url = ex$url
  conn$origin = url_origin(ex$url)
  raw = mcp_map_chr(conn$spec$headers)
  hdr = list()
  for (k in names(ex$headers)) {
    v = ex$headers[[k]]
    secret = grepl("${", raw[[k]], fixed = TRUE) || mcp_secret_name(k) || !identical(redact(v), v)
    hdr[[k]] = if (secret && nzchar(v)) {
      nm = toupper(gsub("[^A-Za-z0-9]+", "_", paste("MCP", conn$name, k)))
      secret_register(v, nm, source = "mcp", origin = conn$origin)
    } else {
      v
    }
  }
  conn$headers = hdr
  conn$auth_key = paste0("mcp:", conn$name)
  invisible(conn)
}

#' The Authorization value of a connection: a configured header wins; otherwise the credential
#' store's (oauth_access(): an API key or an OAuth access token, refreshed under a lock, handed
#' only to the origin of the resource it was issued for), read per request so gptr_logout()
#' takes effect at once. NULL when there is none or the refresh failed (a registry diagnostic):
#' the server's 401 then asks the user to sign in again.
#' @noRd
mcp_http_auth = function(conn, force = FALSE) {
  if ("authorization" %in% tolower(names(conn$headers))) return(NULL)
  tryCatch(oauth_access(conn$auth_key, conn$origin, force = force),
           gptr_error = function(e) {
             registry_diagnostic("builtin:mcp", "mcp_auth", class(e)[1L], conditionMessage(e))
             NULL
           })
}

#' Headers of one request: Accept, content type, the configured headers, Authorization, and the
#' era headers (MCP-Protocol-Version, Mcp-Method, Mcp-Name, Mcp-Param-*, or the legacy version
#' and Mcp-Session-Id)
#' @noRd
mcp_http_headers = function(conn, msg) {
  h = c(list(Accept = "application/json, text/event-stream", `Content-Type` = "application/json"),
        conn$headers)
  auth = mcp_http_auth(conn)
  if (!is.null(auth)) h$Authorization = auth
  meta_ver = msg$params[["_meta"]][[mcp_k_ver]]
  if (!is.null(meta_ver)) {
    h[["MCP-Protocol-Version"]] = meta_ver
    h[["Mcp-Method"]] = msg$method
    if (isTRUE(msg$method %in% c("tools/call", "prompts/get"))) {
      h[["Mcp-Name"]] = mcp_header_value(msg$params$name)
    }
    if (identical(msg$method, "resources/read")) h[["Mcp-Name"]] = mcp_header_value(msg$params$uri)
    if (identical(msg$method, "tools/call")) h = c(h, mcp_param_headers(conn, msg$params))
  } else if (identical(conn$era, "legacy")) {
    h[["MCP-Protocol-Version"]] = conn$version
  }
  h[["Mcp-Session-Id"]] = conn$session_id
  h
}

#' Mcp-Param-<Name> headers for the arguments whose schema property carries x-mcp-header;
#' numbers and logicals are sent as their JSON text
#' @noRd
mcp_param_headers = function(conn, params) {
  tool = Filter(function(t) identical(t$name, params$name), conn$tools %||% list())
  if (!length(tool)) return(list())
  props = tool[[1L]]$input_schema$properties %||% list()
  out = list()
  for (p in names(props)) {
    h = if (is.list(props[[p]])) props[[p]][["x-mcp-header"]]
    v = params$arguments[[p]]
    if (is.character(h) && !is.null(v)) {
      out[[paste0("Mcp-Param-", h)]] = mcp_header_value(mcp_map_chr(v))
    }
  }
  out
}

#' POST one JSON-RPC message on the reactor (one attempt: a tool call must not run twice). JSON
#' and SSE bodies are routed through mcp_on_message(); a failed transfer, or a request answered
#' without its response, marks `st` failed with the HTTP status. The reactor's first-byte and
#' idle timers are set to the request's hard deadline: MCP keeps its own, progress-aware timer.
#' @noRd
mcp_http_send = function(conn, msg, st = new.env(parent = emptyenv())) {
  st$chunks = list()
  fail = function(message, status) {
    st$failure = list(error = list(code = NA_integer_, message = message), http_status = status)
    st$failed = TRUE
  }
  route = function(txt) mcp_on_message(conn, tryCatch(json_decode(txt), error = function(e) NULL))
  hard = if (is.null(st$hard)) 30 else max(1, st$hard - reactor_now())
  spec = list(url = conn$url, method = "POST", headers = mcp_http_headers(conn, msg),
              body = mcp_json(msg), first_byte_timeout = hard, idle_timeout = hard)
  st$transfer = reactor_http(spec,
    on_headers = function(status, headers) {
      ctype = hdr_value(headers, "Content-Type") %||% ""
      if (grepl("text/event-stream", ctype, fixed = TRUE)) st$sse = sse_splitter()
      sid = hdr_value(headers, "Mcp-Session-Id")
      if (identical(msg$method, "initialize")) conn$session_id = sid
    },
    on_bytes = function(raw) {
      if (is.null(st$sse)) {
        st$chunks[[length(st$chunks) + 1L]] = raw
      } else {
        for (ev in st$sse$push(raw)) route(ev$data)
      }
    },
    on_done = function(status, headers) {
      if (!is.null(st$sse)) {
        last = st$sse$flush()
        if (!is.null(last)) route(last$data)
      } else if (length(st$chunks)) {
        route(raw_to_utf8(do.call(c, st$chunks)))
      }
      st$done = TRUE
      if (!is.null(msg$id) && !exists(as.character(msg$id), envir = conn$pending)) {
        fail(paste0("HTTP ", status, " without a JSON-RPC answer"), as.integer(status))
      }
    },
    on_fail = function(cnd) {
      st$done = TRUE
      fail(conditionMessage(cnd), suppressWarnings(as.integer(cnd$status %||% NA_integer_)))
    },
    retry = list(max_attempts = 1L))
  invisible(st)
}

#' POST a notification or a response and wait (at most 10 s) until the server took it
#' @noRd
mcp_http_post_quiet = function(conn, msg) {
  st = mcp_http_send(conn, msg)
  reactor_pump(until = function() isTRUE(st$done), slice_ms = 50L, timeout = 10)
  invisible(st)
}

#' DELETE the legacy session
#' @noRd
mcp_http_delete = function(conn) {
  done = FALSE
  finish = function(...) done <<- TRUE
  reactor_http(list(url = conn$url, method = "DELETE", headers = mcp_http_headers(conn, list())),
               on_bytes = function(raw) NULL, on_done = finish, on_fail = finish,
               retry = list(max_attempts = 1L))
  reactor_pump(until = function() done, slice_ms = 50L, timeout = 5)
  invisible(NULL)
}

#' The server needs a sign-in. A tool call never opens a browser (architecture 6.14): the
#' condition names the login call.
#' @noRd
mcp_auth_required = function(conn) {
  login = paste0("gptr_login(\"", conn$auth_key, "\")")
  gptr_abort(paste0("MCP server ", conn$name, " needs a sign-in. Run ", login,
                    " at the R prompt, then retry."), c("mcp_auth_required", "mcp"),
             server = conn$name, login = login)
}
