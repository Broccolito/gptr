# mcp_relay.R -- gptr's stdio MCP server for Codex (contract IC-65, IC-79). Base R only.
#
# Codex starts `Rscript --vanilla mcp_relay.R <dir> <seconds>`. Each JSON-RPC line on stdin goes
# to the live R session as the file <dir>/req; the session answers with <dir>/resp (an empty line
# for a notification), which goes to stdout. Both files appear by a rename, one message at a time.
# The relay exits at the end of stdin, when <dir> is gone (the session's turn is over), or when an
# answer takes longer than <seconds> (the R session died). --vanilla keeps a user profile from
# printing into the JSON-RPC stream; lines pass through as bytes.

args = commandArgs(trailingOnly = TRUE)
dir = args[[1L]]
limit = as.numeric(args[[2L]])
req = file.path(dir, "req")
resp = file.path(dir, "resp")
input = file("stdin", open = "r")
repeat {
  line = readLines(input, n = 1L, warn = FALSE)
  if (!length(line) || !dir.exists(dir)) break
  writeLines(line, paste0(req, ".tmp"), useBytes = TRUE)
  file.rename(paste0(req, ".tmp"), req)
  t0 = proc.time()[["elapsed"]]
  out = NULL
  while (is.null(out)) {
    if (!dir.exists(dir) || proc.time()[["elapsed"]] - t0 > limit) quit(save = "no", status = 1L)
    Sys.sleep(0.01)
    # a file just renamed can be locked for a moment on Windows: it is read at the next poll
    if (file.exists(resp)) {
      out = tryCatch(readLines(resp, warn = FALSE), error = function(e) NULL,
                     warning = function(w) NULL)
    }
  }
  unlink(resp)
  if (length(out) && nzchar(out[[1L]])) {
    writeLines(out, stdout(), useBytes = TRUE)
    flush(stdout())
  }
}
