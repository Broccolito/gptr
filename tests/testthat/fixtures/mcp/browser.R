# A stand-in browser for gptr's OAuth tests: it opens the sign-in URL and follows the redirects
# to gptr's loopback listener, then prints the final status.
# Usage: Rscript --vanilla browser.R <url>
url = commandArgs(trailingOnly = TRUE)[1L]
r = tryCatch(curl::curl_fetch_memory(url, handle = curl::new_handle(followlocation = TRUE)),
             error = function(e) NULL)
cat(if (is.null(r)) "failed" else r$status_code, "\n")
