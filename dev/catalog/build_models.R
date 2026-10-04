# Builds inst/extdata/models.json.gz: models.dev (MIT) pruned to gptr's providers, gptr's seed
# entries for the models the specification names, and gptr's reviewed overrides (plan P05;
# contract section 11.10; report 09 section 4.8). A maintainer tool: dev/ is excluded from the
# package build and nothing here runs on CRAN.
#
# Run from the repository root:
#   Rscript --vanilla dev/catalog/build_models.R                  # download models.dev
#   Rscript --vanilla dev/catalog/build_models.R --api api.json [--decision decision.json]
#   Rscript --vanilla dev/catalog/build_models.R --offline        # seed + overrides only
args = commandArgs(trailingOnly = TRUE)
arg_value = function(flag) {
  i = match(flag, args)
  if (is.na(i) || i == length(args)) NULL else args[[i + 1L]]
}
read_json_file = function(path) {
  txt = readLines(path, encoding = "UTF-8", warn = FALSE)
  jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = FALSE)
}
fetch_json = function(url) {
  path = tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  curl::curl_download(url, path, quiet = TRUE, handle = curl::new_handle(followlocation = 0L))
  read_json_file(path)
}

pkgload::load_all(".", quiet = TRUE)
ns = asNamespace("gptr")
if ("--offline" %in% args) {
  api = NULL
  decision = NULL
} else if (!is.null(arg_value("--api"))) {
  api = read_json_file(arg_value("--api"))
  decision_path = arg_value("--decision")
  decision = if (is.null(decision_path)) NULL else read_json_file(decision_path)
} else {
  api = fetch_json(get("catalog_source_url", envir = ns))
  decision = tryCatch(fetch_json(get("catalog_decision_url", envir = ns)),
                      error = function(e) NULL)
}
snap = get("catalog_snapshot", envir = ns)(api, decision,
                                           generated = format(Sys.Date(), "%Y-%m-%d"))
text = get("json_encode", envir = ns)(snap)
out = file.path("inst", "extdata", "models.json.gz")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
con = gzfile(out, "wb", compression = 9)
writeLines(text, con, useBytes = TRUE)
close(con)
cat(sprintf("wrote %s: %d models, %d providers, %d aliases, %.1f KB (%s)\n", out,
            length(snap$models), length(snap$providers), length(snap$aliases),
            file.size(out) / 1024, snap$source))
