.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
tkx = function(x) length(rtiktoken::get_tokens(x, "o200k_base"))
tk = function(f) tkx(paste(readLines(f, warn = FALSE), collapse = "\n"))
source("tools.R")
enc = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
rv = function(props) { r = defs$r; r$input_schema$properties = r$input_schema$properties[props]; r }
rt = defs$r
t_short = "Seconds; best effort. Default 3600."
arr = function(r, ask = FALSE) { l = list(defs$read, r, defs$edit, defs$write); if (ask) l = c(l, list(defs$ask)); enc(l) }
r_full = rv(c("code", "record", "note", "timeout")); r_full$input_schema$properties$timeout$description = t_short
r_doc = rv(c("code", "record", "note"))
r_tmo = rv(c("code", "timeout")); r_tmo$input_schema$properties$timeout$description = t_short
r_min = rv("code")
cat("r variants: old", tkx(enc(list(defs$r))), " full", tkx(enc(list(r_full))), " doc+human", tkx(enc(list(r_doc))),
    " nodoc+nohuman", tkx(enc(list(r_tmo))), " human nodoc", tkx(enc(list(r_min))), "\n")
cat("arrays: old std", tkx(arr(defs$r)), " minimal(nohuman,nodoc)", tkx(arr(r_tmo)), " std human nodoc +ask", tkx(arr(r_min, TRUE)),
    " std human doc +ask", tkx(arr(r_doc, TRUE)), " std nohuman doc", tkx(arr(r_full)), " std nohuman nodoc", tkx(arr(r_tmo)), "\n")
fs = c("rules.txt", "rules_std.txt", "rules_ro.txt", "r_session.txt", "r_session_new.txt", "documents.txt", "documents_new.txt",
       "context.txt", "context_new.txt", "skills_hdr.txt", "skills_new.txt", "nonint_manual.txt", "nonint_other.txt",
       "preamble.txt", "preamble_min.txt", "tools.txt", "tools_min.txt", "rules_min_extra.txt", "r_performance.txt",
       "artifacts.txt", "system1.txt", "modes.txt")
print(vapply(fs, tk, integer(1)))
