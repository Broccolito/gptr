# A stand-in for a CLI child of gptr (Codex speaking Streamable HTTP MCP): it reads its bearer
# token from GPTR_MCP_TOKEN, POSTs each JSON-RPC message given on the command line to the URL
# and prints one JSON line per response: {"status": <int>, "body": <text>}.
# Usage: Rscript --vanilla client.R <url> <json> [<json> ...]
args = commandArgs(trailingOnly = TRUE)
url = args[1L]
token = Sys.getenv("GPTR_MCP_TOKEN")
session = NULL
for (body in args[-1L]) {
  msg = jsonlite::fromJSON(body, simplifyVector = FALSE)
  h = curl::new_handle(followlocation = FALSE)
  hdr = list(`Content-Type` = "application/json", Accept = "application/json, text/event-stream",
             Authorization = paste("Bearer", token))
  ver = msg$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]]
  if (!is.null(ver)) {
    hdr[["MCP-Protocol-Version"]] = ver
    hdr[["Mcp-Method"]] = msg$method
  }
  if (!is.null(session)) hdr[["Mcp-Session-Id"]] = session
  curl::handle_setheaders(h, .list = hdr)
  curl::handle_setopt(h, copypostfields = body)
  r = tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  if (is.null(r)) {
    cat(jsonlite::toJSON(list(status = 0L, body = ""), auto_unbox = TRUE), "\n", sep = "")
    next
  }
  sid = curl::parse_headers_list(r$headers)[["mcp-session-id"]]
  if (!is.null(sid)) session = sid
  out = list(status = r$status_code, body = rawToChar(r$content))
  cat(jsonlite::toJSON(out, auto_unbox = TRUE), "\n", sep = "")
}
