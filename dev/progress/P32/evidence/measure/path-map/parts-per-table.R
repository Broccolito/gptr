# Parts one fread-like data.table costs in env_snap_size()'s sampling budget (env_size_budget)
pkgload::load_all("/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/path-map/src/gptr",
                  quiet = TRUE, helpers = FALSE, attach_testthat = FALSE)
ns = asNamespace("gptr")
data.table::setDTthreads(1)
f = tempfile(fileext = ".tsv")
writeLines(c("# gene-model: x", "gene_id\tgene_name\tgene_type\tunstranded\tstranded_first\tstranded_second\ttpm_unstranded\tfpkm_unstranded\tfpkm_uq_unstranded",
             paste("N_a", "", "", 1, 2, 3, "", "", "", sep = "\t"),
             sprintf("ENSG%05d\tG%d\tprotein_coding\t%d\t1\t1\t0.5\t0.5\t0.5", 1:2000, 1:2000, 1:2000)), f)
dt = data.table::fread(file = f, skip = "gene_id", header = TRUE, showProgress = FALSE)
cat("attributes:", paste(names(attributes(dt)), collapse = ", "), "\n")
st = new.env(parent = emptyenv()); st$seen = new.env(hash = TRUE, parent = emptyenv())
st$s7 = new.env(hash = TRUE, parent = emptyenv()); st$cls = FALSE; st$depth = 0L
get("env_size_reset", ns)(st, FALSE)
get("env_size_walk", ns)(dt, st)
cat("parts for one table (walk):", st$parts, " + 1 per list item in env_size_items\n")
per = st$parts + 1
cat("tables walked before the budget of", get("env_size_budget", ns), "parts:", ceiling(get("env_size_budget", ns) / per) + 1, "\n")
