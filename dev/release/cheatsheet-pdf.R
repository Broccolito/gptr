# Prints pkgdown/assets/cheatsheet.html to the gptr-cheatsheet.pdf the site serves next to it.
# Needs Google Chrome or Chromium. Usage, from the repository root:
#   Rscript --vanilla dev/release/cheatsheet-pdf.R [chrome]
args = commandArgs(trailingOnly = TRUE)
chrome = if (length(args)) args[1L] else
  Sys.getenv("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
assets = normalizePath(file.path("pkgdown", "assets"), mustWork = TRUE)
pdf = file.path(assets, "gptr-cheatsheet.pdf")
profile = tempfile("chrome-")
unlink(pdf)
status = system2(chrome, shQuote(c("--headless=new", "--disable-gpu", "--no-pdf-header-footer",
  paste0("--user-data-dir=", profile), paste0("--print-to-pdf=", pdf),
  paste0("file://", file.path(assets, "cheatsheet.html")))), stdout = FALSE, stderr = FALSE)
unlink(profile, recursive = TRUE)
if (!identical(status, 0L) || !file.exists(pdf)) stop("Chrome could not print the cheatsheet")
writeLines(sprintf("cheatsheet-pdf: wrote %s", pdf))
