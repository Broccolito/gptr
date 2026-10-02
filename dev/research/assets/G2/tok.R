# G2 shared helpers: token counting with rtiktoken (oracle) and the proposed estimator.
# House style: "=" for assignment, "|>" for pipes.
G2 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2"
RLIB = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))
suppressPackageStartupMessages(library(rtiktoken))

# rtiktoken 0.0.7 rebuilds its BPE encoder on every call (about 0.3-0.4 s per call on this machine,
# independent of text length), so counts are memoised in an on-disk cache keyed by a hash of the text.
.tokcache_file = file.path(G2, "tokcache.rds")
.tokcache = if (file.exists(.tokcache_file)) readRDS(.tokcache_file) else new.env(hash = TRUE)
reg.finalizer(environment(), function(e) saveRDS(.tokcache, .tokcache_file), onexit = TRUE)
tok_count = function(x, enc) {
  x = enc2utf8(paste(x, collapse = "\n"))
  if (!nzchar(x)) return(0L)
  key = paste0(enc, ":", rlang::hash(x))
  v = .tokcache[[key]]
  if (is.null(v)) {
    v = get_token_count(x, enc)
    assign(key, v, envir = .tokcache)
  }
  v
}
tok_o200k = function(x) tok_count(x, "o200k_base")
tok_cl100k = function(x) tok_count(x, "cl100k_base")
tok_save = function() saveRDS(.tokcache, .tokcache_file)
chars = function(x) nchar(paste(x, collapse = "\n"), "chars")
j = function(x, pretty = FALSE) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = pretty))
}
fmt_row = function(...) cat(sprintf(...), "\n", sep = "")
