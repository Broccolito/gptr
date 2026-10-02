fs = list.files("blocks", pattern = "_r_d[01]\\.txt$", full.names = TRUE)
res = list()
bad = 0L
for (f in fs) {
  txt = readLines(f, warn = FALSE, encoding = "UTF-8")
  nonascii = which(grepl("[^\x01-\x7F]", txt, useBytes = TRUE))
  ex = tryCatch(parse(text = txt, keep.source = TRUE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(ex, "error")) {
    cat("PARSE FAIL", basename(f), gsub("\n", " | ", conditionMessage(ex)), "\n")
    bad = bad + 1L
    next
  }
  pd = utils::getParseData(ex)
  la = if (is.null(pd)) integer() else pd$line1[pd$token == "LEFT_ASSIGN" & pd$text == "<-"]
  ra = if (is.null(pd)) integer() else pd$line1[pd$token == "RIGHT_ASSIGN"]
  mp = if (is.null(pd)) integer() else pd$line1[pd$token == "SPECIAL" & pd$text == "%>%"]
  long = which(nchar(txt, type = "bytes") > 100)
  if (length(la) || length(ra) || length(mp) || length(nonascii)) {
    bad = bad + 1L
    cat(basename(f), " <-:", paste(la, collapse = ","), " ->:", paste(ra, collapse = ","),
        " %>%:", paste(mp, collapse = ","), " nonascii lines:", paste(nonascii, collapse = ","), "\n")
  }
  if (length(long)) cat("LONG", basename(f), paste(long, collapse = ","), "\n")
}
cat(length(fs), "R blocks;", bad, "with parse/style problems\n")
