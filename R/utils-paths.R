# Paths, workspace locations, homes, atomic writes and the serialisation leaves
# (contract section 7.1; IC-51, IC-54, IC-60, IC-63; copy-safety rule R7).

#' Write bytes to a file through a binary connection (no CRLF translation on Windows)
#' @noRd
write_bytes = function(path, bytes) {
  con = file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(path)
}

#' Mockable file.rename() without warnings
#' @noRd
file_rename = function(from, to) {
  suppressWarnings(file.rename(from, to))
}

#' Write a file atomically (IC-51)
#'
#' `content` is a character vector (written as UTF-8 lines, each ending in LF) or a raw vector.
#' The bytes go to a temporary file in the same directory (with the permission bits of an
#' existing `path`, else `mode`), which is renamed over `path`; the rename is retried 3 times with
#' 100 ms pauses, then the file is written in place after an md5 check that nobody else changed it
#' meanwhile.
#' @noRd
write_atomic = function(path, content, mode = "0600") {
  check_string(path, "path")
  if (is.character(content)) {
    lines = as_utf8(content)
    bytes = if (length(lines)) charToRaw(paste0(paste(lines, collapse = "\n"), "\n")) else raw(0)
  } else if (is.raw(content)) {
    bytes = content
  } else {
    arg_abort(content, "content", "a character or raw vector")
  }
  dir = dirname(path)
  if (!dir.exists(dir)) {
    gptr_abort(
      paste0("Cannot write '", path, "': its directory does not exist."),
      "invalid_argument",
      arg = "path",
      expected = "a path in an existing directory"
    )
  }
  before = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  old = file.info(path, extra_cols = FALSE)$mode
  if (!is.na(old)) mode = old
  tmp = tempfile(".gptr-write-", tmpdir = dir)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  # Create an empty private file before writing any content; changing permissions after
  # write_bytes() would expose a private target's new content under an ordinary umask.
  if (!file.create(tmp, showWarnings = FALSE) ||
        !isTRUE(Sys.chmod(tmp, "0600", use_umask = FALSE))) {
    gptr_abort("Cannot create a private temporary file.", "doc_write", path = path,
               reason = "temporary permissions")
  }
  write_bytes(tmp, bytes)
  if (!isTRUE(Sys.chmod(tmp, mode, use_umask = FALSE))) {
    gptr_abort("Cannot preserve destination permissions.", "doc_write", path = path,
               reason = "destination permissions")
  }
  for (attempt in 1:4) {
    if (file_rename(tmp, path)) return(invisible(path))
    if (attempt < 4L) Sys.sleep(0.1)
  }
  now = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  if (!identical(before, now)) {
    gptr_abort(
      paste0("Cannot write '", path, "': the file changed while gptr was writing it."),
      "doc_write",
      path = path,
      reason = "concurrent change"
    )
  }
  write_bytes(path, bytes)
  invisible(path)
}

#' Mockable platform predicates
#' @noRd
is_windows = function() {
  identical(.Platform$OS.type, "windows")
}

#' @noRd
is_macos = function() {
  identical(Sys.info()[["sysname"]], "Darwin")
}

#' The Rscript binary of the running R, never a PATH lookup (IC-60)
#' @noRd
rscript_path = function() {
  file.path(R.home("bin"), if (is_windows()) "Rscript.exe" else "Rscript")
}

#' The user's home: USERPROFILE on Windows, else HOME, else path.expand("~") (IC-63)
#' @noRd
user_home = function() {
  home = if (is_windows()) Sys.getenv("USERPROFILE", unset = "") else ""
  if (!nzchar(home)) home = Sys.getenv("HOME", unset = "")
  if (!nzchar(home)) home = path.expand("~")
  gsub("\\", "/", home, fixed = TRUE)
}

#' An application's configuration directory (%APPDATA%, ~/Library/Application Support,
#' $XDG_CONFIG_HOME or ~/.config)
#' @noRd
app_config_dir = function(app) {
  check_string(app, "app")
  if (is_windows()) {
    base = Sys.getenv("APPDATA", unset = "")
    if (!nzchar(base)) base = file.path(user_home(), "AppData", "Roaming")
  } else if (is_macos()) {
    base = file.path(user_home(), "Library", "Application Support")
  } else {
    base = Sys.getenv("XDG_CONFIG_HOME", unset = "")
    if (!nzchar(base)) base = file.path(user_home(), ".config")
  }
  file.path(gsub("\\", "/", base, fixed = TRUE), app)
}

#' gptr's R_user_dir() folder; created only when `create = TRUE`
#' @noRd
gptr_user_dir = function(which = c("config", "cache", "data"), create = FALSE) {
  which = check_choice(which, c("config", "cache", "data"), "which")
  check_flag(create, "create")
  dir = tools::R_user_dir("gptr", which)
  if (create) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' Is each path absolute ("/x", "C:/x", "C:\\x", UNC)?
#' @noRd
is_abs_path = function(path) {
  grepl("^([/\\\\]|[A-Za-z]:[/\\\\])", path)
}

#' Normalise one path: absolute, forward slashes, symlinks resolved on the deepest existing
#' ancestor (macOS /var -> /private/var), "." and ".." removed from the rest
#' @noRd
path_norm_one = function(path) {
  # "~" is expanded before backslashes become slashes, so the result has forward slashes whatever
  # user_home() returns (CI-5, D-111)
  if (identical(path, "~") || grepl("^~[/\\\\]", path)) {
    path = paste0(user_home(), substring(path, 2L))
  }
  path = gsub("\\", "/", path, fixed = TRUE)
  if (!is_abs_path(path)) path = file.path(getwd(), path)
  rest = character()
  current = path
  while (!file.exists(current)) {
    parent = dirname(current)
    if (identical(parent, current)) break
    rest = c(basename(current), rest)
    current = parent
  }
  out = normalizePath(current, winslash = "/", mustWork = FALSE)
  for (part in rest) {
    if (part %in% c("", ".")) next
    if (identical(part, "..")) {
      out = dirname(out)
      next
    }
    out = if (endsWith(out, "/")) paste0(out, part) else paste0(out, "/", part)
  }
  if (nchar(out) > 1L && endsWith(out, "/") && !grepl("^[A-Za-z]:/$", out)) {
    out = substr(out, 1L, nchar(out) - 1L)
  }
  out
}

#' Does the last component of each path end in an extension? (R 4.6's rule, without basename())
#'
#' The extension is the ASCII alphanumeric run after the last dot, with at least one character
#' that is not a dot before that dot, so ".Rprofile" and "x." have none. "/" and "\\" separate
#' components. base R's `basename()` translates to the native encoding and stops on a marked
#' UTF-8 non-ASCII path in a non-UTF-8 locale; R >= 4.6's `tools::file_ext()` and
#' `tools::file_path_sans_ext()` call it (CI-5, D-111; IC-62).
#' @noRd
path_has_ext = function(path) {
  last = sub("(?s)^.*[/\\\\]", "", path, perl = TRUE)
  grepl("(?s)^(.*[^.].*)[.][[:alnum:]]+\\z", last, perl = TRUE)
}

#' File extensions without the dot ("" for none), in every locale (see `path_has_ext()`)
#' @noRd
path_ext = function(path) {
  out = rep("", length(path))
  has = path_has_ext(path)
  out[has] = sub("(?s)^.*[.]([[:alnum:]]+)\\z", "\\1", path[has], perl = TRUE)
  out
}

#' Paths without their extension, in every locale (see `path_has_ext()`)
#' @noRd
path_sans_ext = function(path) {
  has = path_has_ext(path)
  path[has] = sub("[.][[:alnum:]]+\\z", "", path[has], perl = TRUE)
  path
}

#' Normalised absolute paths (vectorised)
#' @noRd
path_norm = function(path) {
  check_strings(path, "path")
  vapply(path, path_norm_one, "", USE.NAMES = FALSE)
}

#' Key for comparing paths: normalised, lower-cased on Windows and macOS (IC-51)
#' @noRd
path_key = function(path) {
  key = path_norm(path)
  if (is_windows() || is_macos()) tolower(key) else key
}

#' Is each path equal to or inside `root`? (compares path keys)
#' @noRd
path_inside = function(path, root) {
  p = path_key(path)
  r = path_key(root)
  p == r | startsWith(p, if (endsWith(r, "/")) r else paste0(r, "/"))
}

#' Project root (contract section 1.2; IC-63)
#'
#' `options(gptr.project_root)` or the environment variable `GPTR_PROJECT_ROOT` override the
#' search; otherwise the nearest ancestor of `path` holding `.gptr/`, `DESCRIPTION`, `.git`,
#' `*.Rproj` or `_quarto.yml`, else `path` itself.
#' @noRd
project_root = function(path = getwd()) {
  override = getOption("gptr.project_root")
  if (is.null(override) || !nzchar(override)) override = Sys.getenv("GPTR_PROJECT_ROOT")
  if (nzchar(override)) return(path_norm(override))
  start = path_norm(path)
  dir = start
  repeat {
    if (is_project_dir(dir)) return(dir)
    parent = dirname(dir)
    if (identical(parent, dir)) break
    dir = parent
  }
  start
}

#' @noRd
is_project_dir = function(dir) {
  dir.exists(file.path(dir, ".gptr")) ||
    file.exists(file.path(dir, "DESCRIPTION")) ||
    file.exists(file.path(dir, ".git")) ||
    file.exists(file.path(dir, "_quarto.yml")) ||
    length(list.files(dir, pattern = "\\.Rproj$")) > 0L
}

#' The existing `.gptr/` directory of the project root of `path`, or NULL
#' @noRd
workspace_dir = function(path = getwd()) {
  ws = file.path(project_root(path), ".gptr")
  if (dir.exists(ws)) ws else NULL
}

#' The workspace root: `.gptr/` when it exists, else `tempdir()/gptr` (created lazily)
#' @noRd
workspace_root = function(create = TRUE) {
  ws = workspace_dir()
  if (!is.null(ws)) return(ws)
  root = file.path(tempdir(), "gptr")
  if (create && !dir.exists(root)) dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

#' A path inside the workspace root; its parent directory is created by default
#' @noRd
ws_path = function(..., create_parent = TRUE) {
  path = file.path(workspace_root(), ...)
  if (create_parent) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

#' The one saveRDS() of user data: always ascii = FALSE (copy-safety rule R7) (a leaf function)
#' @noRd
save_rds = function(object, file, compress = FALSE) {
  saveRDS(object, file, ascii = FALSE, compress = compress)
}

#' The one serialize() of user data: always ascii = FALSE (copy-safety rule R7) (a leaf function)
#' @noRd
serialize_leaf = function(object, xdr = TRUE) {
  serialize(object, NULL, ascii = FALSE, xdr = xdr)
}

#' Root-relative path when inside `root`, else the normalised absolute path
#' @noRd
path_rel = function(path, root = project_root()) {
  abs = path_norm(path)
  base = path_norm(root)
  inside = path_inside(abs, base)
  out = abs
  prefix = if (endsWith(base, "/")) base else paste0(base, "/")
  out[inside] = substring(abs[inside], nchar(prefix) + 1L)
  out[inside & !nzchar(out)] = "."
  out
}

#' Windows reserved device names (con, prn, aux, nul, com1-9, lpt1-9), with or without extension
#' @noRd
reserved_name = function(x) {
  grepl("^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\\..*)?$", x, ignore.case = TRUE)
}

#' Path class of each path (contract section 7.1; report 18 section 3.8; IC-54)
#'
#' One of `url`, `wildcard`, `control` (level 4), `critical`, `protected`, `instructions`
#' (level 3), `workspace`, `temp`, `outside`, or `unknown` (missing or empty). Relative paths are
#' resolved against `root`.
#' @noRd
path_class = function(path, root = project_root()) {
  if (!is.character(path)) arg_abort(path, "path", "a character vector")
  check_string(root, "root")
  context = path_class_context(root)
  vapply(path, path_class_one, "", context = context, USE.NAMES = FALSE)
}

#' Precomputed keys used by path_class_one()
#' @noRd
path_class_context = function(root) {
  env_target = function(name, default) {
    value = Sys.getenv(name, unset = "")
    if (nzchar(value)) value else default
  }
  home = user_home()
  list(
    root = root,
    root_key = path_key(root),
    home_key = path_key(home),
    temp_key = path_key(tempdir()),
    config_key = path_key(tools::R_user_dir("gptr", "config")),
    control_files = path_key(c(
      env_target("R_PROFILE_USER", file.path(home, ".Rprofile")),
      env_target("R_ENVIRON_USER", file.path(home, ".Renviron")),
      file.path(root, ".Renviron")
    )),
    makevars_key = path_key(file.path(home, ".R"))
  )
}

#' @noRd
path_class_one = function(path, context) {
  if (is.na(path) || !nzchar(path)) return("unknown")
  if (grepl("^(https?|ftps?|s3|gs)://", path, ignore.case = TRUE)) return("url")
  if (grepl("[*?]", path)) return("wildcard")
  expanded = gsub("\\", "/", path, fixed = TRUE)
  if (!is_abs_path(expanded) && !startsWith(expanded, "~")) {
    expanded = file.path(context$root, expanded)
  }
  key = path_key(expanded)
  resolved = path_class_key(key, context)
  # Both the requested pathname and its symlink target carry policy authority.
  lexical = path_lexical(expanded)
  if (is_windows() || is_macos()) lexical = tolower(lexical)
  requested = path_class_key(lexical, context)
  guarded = c("control", "critical", "protected", "instructions")
  ranks = match(c(requested, resolved), guarded)
  if (all(is.na(ranks))) return(resolved)
  guarded[min(ranks, na.rm = TRUE)]
}

#' Classify one absolute lexical or resolved path without resolving it again
#' @noRd
path_class_key = function(key, context) {
  has = function(pattern) grepl(pattern, key, ignore.case = TRUE, perl = TRUE)
  inside = function(base) key == base || startsWith(key, paste0(sub("/$", "", base), "/"))
  control = has("(^|/)\\.gptr/settings[^/]*\\.json$") ||
    has("(^|/)\\.gptr/mcp\\.json$") ||
    has("(^|/)\\.gptr/(extensions|plugins|agents)(/|$)") ||
    has("(^|/)\\.gptr/(system|append_system)\\.md$") ||
    has("(^|/)\\.git/hooks(/|$)") ||
    has("(^|/)\\.git/config$") ||
    has("(^|/)\\.rprofile$") ||
    has("(^|/)(rprofile|renviron)\\.site$") ||
    key %in% context$control_files ||
    inside(context$config_key) ||
    startsWith(tolower(key), paste0(tolower(context$makevars_key), "/makevars"))
  if (control) return("control")
  if (key %in% c("/", context$home_key, context$root_key, context$temp_key) ||
        grepl("^[a-z]:/?$", key, ignore.case = TRUE)) {
    return("critical")
  }
  protected = has("(^|/)\\.git(/|$)") ||
    has("(^|/)\\.renviron$") ||
    has("(^|/)\\.env([.][^/]*)?$") ||
    has("(^|/)[^/]+[.]env$") ||
    has("(^|/)\\.(secrets|ssh|codex|claude|aws|gnupg)(/|$)") ||
    has("(^|/)\\.netrc$") ||
    has("(^|/)renv\\.lock$")
  if (protected) return("protected")
  instructions = has("(^|/)(agents|claude)\\.md$") ||
    has("(^|/)\\.gptr/vignette\\.rmd$") ||
    has("(^|/)\\.gptr/(skills|prompts)(/|$)")
  if (instructions) return("instructions")
  if (inside(context$root_key)) return("workspace")
  if (inside(context$temp_key)) return("temp")
  "outside"
}

#' Normalise one path lexically, without the file system: "/" separators; ".." never climbs above
#' a root ("/", "C:/", "//server/share") and is kept at the start of a relative path ("" is ".")
#' @noRd
path_lexical = function(path) {
  path = gsub("\\", "/", as_utf8(path), fixed = TRUE)
  unc = startsWith(path, "//")
  prefix = if (unc) "//" else if (startsWith(path, "/")) "/" else ""
  floor = if (unc) 2L else if (grepl("^[A-Za-z]:/", path)) 1L else 0L
  out = character()
  for (piece in strsplit(path, "/", fixed = TRUE)[[1L]]) {
    if (piece %in% c("", ".")) next
    if (piece != "..") {
      out = c(out, piece)
    } else if (length(out) > floor && out[length(out)] != "..") {
      out = out[-length(out)]
    } else if (!nzchar(prefix) && !floor) {
      out = c(out, "..")
    }
  }
  out = paste0(prefix, paste(out, collapse = "/"))
  if (floor == 1L && !grepl("/", out, fixed = TRUE)) out = paste0(out, "/")
  if (nzchar(out)) out else "."
}
