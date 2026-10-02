# G2 (f): the proposed pure-R estimator. Sourced by f_calibrate.R, c2_describe.R and d_compose.R.
# estimate_tokens(x, class): ASCII characters / chars-per-token of the content class, plus a per-character
# weight for CJK and for other non-ASCII characters. Constants fitted on the training half of the G2
# corpora against o200k_base (f_calibrate.R prints the fit and the held-out error).
.cjk_rx = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]"
GPTR_CPT = c(prose = 4.35, code = 3.55, r_output = 2.05, str = 2.60, csv = 1.75, json = 2.35, error = 3.45)
GPTR_W_CJK = 0.70
GPTR_W_NONASCII = 0.75
estimate_tokens = function(x, class = "auto", cpt = GPTR_CPT, w_cjk = GPTR_W_CJK, w_other = GPTR_W_NONASCII) {
  x = enc2utf8(as.character(x))
  if (identical(class, "auto")) class = vapply(x, detect_class, "", USE.NAMES = FALSE)
  class = rep_len(class, length(x))
  n = nchar(x, "chars")
  ascii = nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), "chars")
  non = n - ascii
  cjk = if (any(non > 0)) n - nchar(gsub(.cjk_rx, "", x, perl = TRUE), "chars") else numeric(length(x))
  ceiling(ascii / cpt[class] + cjk * w_cjk + (non - cjk) * w_other)
}
# Fallback when the producer does not know the class (tool results normally carry it: r -> r_output,
# read of *.csv -> csv, *.json -> json, *.R -> code, *.md -> prose, error events -> error).
detect_class = function(x) {
  s = substr(x, 1, 4000)
  lines = strsplit(s, "\n", fixed = TRUE)[[1]]
  lines = lines[nzchar(trimws(lines))]
  if (!length(lines)) return("prose")
  if (grepl("^\\s*[\\[{]", s) && grepl("\"[^\"]+\"\\s*:", s)) return("json")
  if (grepl("^(Error|Warning)( in |:)|^Traceback|\n(Error|Warning)( in |:)", s)) return("error")
  commas = lengths(regmatches(lines, gregexpr(",", lines, fixed = TRUE)))
  if (length(lines) >= 3 && median(commas) >= 2 && mean(commas == median(commas)) > 0.8) return("csv")
  if (mean(grepl("^\\s*(\\$ |'data.frame'|List of|Classes|tibble \\[| - attr|Formal class| \\.\\.)", lines)) > 0.3) return("str")
  if (grepl("(function\\s*\\(|<-|\\|>|library\\()", s) && !grepl("^\\s*\\[1\\]", s)) return("code")
  alpha = nchar(gsub("[^A-Za-z]", "", s)) / max(1, nchar(s))
  if (alpha > 0.62) return("prose")
  "r_output"
}
