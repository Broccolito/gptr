# Builds inst/extdata/models.json.gz at release time (P36, D-394): models.dev's api.json and
# decision list, converted and pruned by gptr's own converter, with gptr's reviewed data from
# dev/release/catalog-reviewed.json (corrections, aliases and per-provider defaults, each with its
# source; the sources stay in that file). Development only; nothing here runs on CRAN.
#
# From the repository root:
#   Rscript --vanilla dev/release/catalog-snapshot.R                       # download models.dev
#   Rscript --vanilla dev/release/catalog-snapshot.R api.json decision.json
args = commandArgs(trailingOnly = TRUE)
read_json = function(path) {
  txt = readLines(path, encoding = "UTF-8", warn = FALSE)
  jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = FALSE)
}
fetch_json = function(url) {
  path = tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  curl::curl_download(url, path, quiet = TRUE, handle = curl::new_handle(followlocation = 0L))
  read_json(path)
}
unsourced = function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x))) x = x[names(x) != "source"]
  lapply(x, unsourced)
}

pkgload::load_all(".", quiet = TRUE)
ns = asNamespace("gptr")
api = if (length(args)) read_json(args[[1]]) else fetch_json(ns$catalog_source_url)
decision = if (length(args) > 1L) read_json(args[[2]]) else fetch_json(ns$catalog_decision_url)
reviewed = unsourced(read_json(file.path("dev", "release", "catalog-reviewed.json")))
snap = ns$catalog_snapshot(api, decision, reviewed, generated = format(Sys.Date(), "%Y-%m-%d"))

# every family alias and every default must name a model of the snapshot
models = stats::setNames(snap$models, vapply(snap$models, function(m) {
  paste0(m$provider, "/", m$id)
}, ""))
idx = ns$catalog_index(models)
targets = vapply(snap$aliases, ns$catalog_alias_target, "", idx = idx)
defaults = unlist(lapply(names(snap$defaults), function(p) paste0(p, "/", snap$defaults[[p]])))
missing = c(names(targets)[is.na(targets)], setdiff(defaults, names(models)))
if (length(missing)) stop("no model in the snapshot for: ", paste(missing, collapse = ", "))

out = file.path("inst", "extdata", "models.json.gz")
con = gzfile(out, "wb", compression = 9)
writeLines(ns$json_encode(snap), con, useBytes = TRUE)
close(con)
per = table(vapply(snap$models, function(m) m$provider, ""))
cat(sprintf("wrote %s: %d models, %.1f KB, %s (%s)\n", out, length(snap$models),
            file.size(out) / 1024, snap$generated, snap$source))
cat(paste0("  ", names(per), " ", per, collapse = "\n"), "\n")
cat(paste0("  ", names(targets), " -> ", targets, collapse = "\n"), "\n")
cat(paste0("  default ", defaults, collapse = "\n"), "\n")
