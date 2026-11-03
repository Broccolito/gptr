# An independent client: its parent must service the HTTP request while waiting for this child.
args = commandArgs(TRUE)
con = file("stdin", open = "r")
body = paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
close(con)
message = jsonlite::fromJSON(body, simplifyVector = FALSE)
handle = curl::new_handle(postfields = body, timeout = as.numeric(args[[2L]]))
curl::handle_setheaders(handle, .list = list(
  `Content-Type` = "application/json",
  Accept = "application/json, text/event-stream",
  Authorization = paste("Bearer", Sys.getenv("GPTR_MCP_TOKEN")),
  `MCP-Protocol-Version` = "2026-07-28",
  `Mcp-Method` = message$method
))
response = curl::curl_fetch_memory(args[[1L]], handle)
cat(rawToChar(response$content))
quit(status = if (response$status_code == 200L) 0L else 1L)
