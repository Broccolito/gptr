# JSON serialisation and parsing (conventions section 6; report 19 section 2.2).
# Objects are named lists, arrays unnamed lists; an empty object is json_obj(). Pieces that are
# already JSON text are wrapped with json_verbatim() and embedded unchanged, so an entry or a
# frozen tool array is serialised once and request bodies are assembled by concatenation.

#' Serialise to one JSON string (UTF-8 marked)
#' @noRd
json_encode = function(x, pretty = FALSE) {
  check_flag(pretty, "pretty")
  out = as.character(jsonlite::toJSON(
    json_utf8(x),
    auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE, pretty = pretty
  ))
  Encoding(out) = "UTF-8"
  out
}

#' Parse JSON text into lists (simplifyVector = FALSE)
#'
#' Uses jsonlite::parse_json(), which has the semantics of fromJSON(simplifyVector = FALSE) but
#' never treats its input as a file name or URL.
#' @noRd
json_decode = function(text) {
  text = as_utf8(as.character(text))
  if (length(text) != 1L) text = paste(text, collapse = "\n")
  jsonlite::parse_json(text, simplifyVector = FALSE)
}

#' Mark a string as JSON text to be embedded verbatim by json_encode()
#' @noRd
json_verbatim = function(text) {
  check_string(text, "text")
  structure(as_utf8(text), class = "json")
}

#' The empty JSON object
#' @noRd
json_obj = function() {
  structure(list(), names = character())
}

#' Mark every string (and name) of a nested list as UTF-8, with object keys in radix order when
#' `sort`; verbatim JSON is left alone
#' @noRd
json_utf8 = function(x, sort = FALSE) {
  if (is.character(x)) return(if (inherits(x, "json")) x else as_utf8(x))
  if (!is.list(x)) return(x)
  nms = names(x)
  if (!is.null(nms)) {
    names(x) = as_utf8(nms)
    if (sort) x = x[order(names(x), method = "radix")]
  }
  if (length(x)) x[] = lapply(x, json_utf8, sort = sort)
  x
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
