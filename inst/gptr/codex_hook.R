# codex_hook.R -- gptr's Codex hook for coaching sessions (08 section 3.7).
#
# Codex runs `Rscript --vanilla codex_hook.R <mode> <log> <lib>` for its SessionStart and
# PreToolUse events, with the event's JSON on stdin. SessionStart appends a start line to <log>.
# PreToolUse allows a tool only in mode "run" and only when its name starts with mcp__gptr__.
# Anything else is denied: a line with the tool's name and the time is appended to <log>, the
# reason goes to stderr and the exit status is 2. The input is parsed with jsonlite, loaded from
# <lib>, and never evaluated; input that cannot be read is denied with no tool name, so a hook
# that cannot work fails closed.

args = commandArgs(trailingOnly = TRUE)
mode = args[1L]
input = tryCatch({
  loadNamespace("jsonlite", lib.loc = args[3L])
  jsonlite::fromJSON(paste(readLines(file("stdin"), warn = FALSE, encoding = "UTF-8"),
                           collapse = "\n"), simplifyVector = FALSE)
}, error = function(e) NULL)
field = function(name) {
  x = if (is.list(input)) input[[name]] else NULL
  if (is.character(x) && length(x) == 1L && !is.na(x)) x else NA_character_
}
event = field("hook_event_name")
tool = field("tool_name")
log_line = function(text) {
  try({
    con = file(args[2L], open = "ab")
    on.exit(close(con))
    writeLines(text, con, useBytes = TRUE)
  }, silent = TRUE)
}
time = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
if (identical(event, "SessionStart")) {
  log_line(paste0("{\"event\":\"start\",\"time\":\"", time, "\"}"))
  quit(save = "no", status = 0L)
}
if (identical(mode, "run") && identical(event, "PreToolUse") && !is.na(tool) &&
    startsWith(tool, "mcp__gptr__")) {
  quit(save = "no", status = 0L)
}
name = if (is.na(tool)) "null" else jsonlite::toJSON(substr(tool, 1L, 200L), auto_unbox = TRUE)
log_line(paste0("{\"event\":\"deny\",\"tool_name\":", name, ",\"time\":\"", time, "\"}"))
cat(if (identical(mode, "run")) "gptr: only gptr's own tools (mcp__gptr__*) may run here."
    else "gptr: this session has no tools.", "\n", file = stderr())
quit(save = "no", status = 2L)
