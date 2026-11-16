# P32 prototype (design 1): env_snap_size() of main (R/utils-size.R, with and without its part
# budget) against b-size.R, whose walk reads at most B strings (default 1.25e7). From the
# repository root: B=1.25e7 Rscript --vanilla dev/bench/perf/p32/bench.R <N tables> <case ...>
suppressMessages(library(data.table)); setDTthreads(1)
serialize_leaf = function(object, xdr = TRUE) serialize(object, NULL, ascii = FALSE, xdr = xdr)
args = commandArgs(TRUE); N = as.integer(args[1]); which = args[-1]
set.seed(1)
ids = sprintf("ENSG%011d.%d", 1:60664, sample(1:20, 60664, TRUE))
nm = sprintf("GENE%d", sample(1:59400, 60664, TRUE)); ty = sample(sprintf("type_%02d", 1:40), 60664, TRUE)
num = lapply(1:6, function(i) if (i <= 3) sample.int(1e5, 60664, TRUE) else runif(60664))
mk = function() { d = c(list(gene_id = paste0(ids, ""), gene_name = paste0(nm, ""), gene_type = paste0(ty, "")), setNames(num, paste0("n", 1:6))); setDT(d); d }
cases = list(
  t03 = function() list(files = sprintf("f%04d.tsv", seq_len(N)), tables = lapply(seq_len(N), function(i) mk())),
  vec4e6 = function() paste0("id_", seq_len(4e6)),
  vec5e7 = function() paste0("id_", seq_len(5e7)),
  vecvar = function() { x = paste0("s", seq_len(3e7)); k = seq(1, 3e7, by = 7); x[k] = paste0(x[k], strrep("x", 200)); x },
  long3 = function() { n = 2.5e7; data.frame(id = paste0("g", seq_len(n)), ty = sample(sprintf("type_%02d", 1:40), n, TRUE), nm = paste0("n", sample.int(1e6, n, TRUE))) },
  skew = function() lapply(1:300, function(i) { n = if (i %% 10 == 0) 2e6 else 2e4; paste0("s", i, "_", seq_len(n)) }),
  grow = function() lapply(1:300, function(i) paste0("k", sample.int(i * 20000, 2e5, TRUE))),
  distinct = function() lapply(1:300, function(i) data.table(a = paste0("s", i, "_", 1:200000), b = runif(200000))),
  het = function() lapply(1:2000, function(i) { n = sample(c(100, 5000, 60664), 1); data.table(a = paste0(ids[1:n], i %% 7), b = runif(n)) }),
  small_many = function() lapply(1:5000, function(i) list(id = paste0("id", i), v = runif(5), tag = c("a", "b"))),
  big1str = function() c(strrep("a", 1e8), paste0("s", 1:1000))
)
env0 = new.env(); source("R/utils-size.R", local = env0); env0$serialize_leaf = serialize_leaf
envX = new.env(); source("R/utils-size.R", local = envX); envX$serialize_leaf = serialize_leaf; envX$env_size_budget = Inf
env1 = new.env(); source("dev/bench/perf/p32/b-size.R", local = env1); env1$serialize_leaf = serialize_leaf
for (nmc in which) {
  x = cases[[nmc]](); invisible(gc())
  r = function(e) { t0 = proc.time()[["elapsed"]]; b = e$env_snap_size(x); c(b, proc.time()[["elapsed"]] - t0) }
  o = r(env0); n1 = r(env1); n2 = r(env1); ex = if (nmc == "t03" && N > 400) o else r(envX)
  cat(sprintf("%-10s exact %.5g (%.2fs) | main %.5g (%+.2f%%, %.3fs) | new %.5g (%+.2f%%, %.3fs, rep %.3fs)\n", nmc, ex[1], ex[2], o[1], 100*(o[1]/ex[1]-1), o[2], n1[1], 100*(n1[1]/ex[1]-1), n1[2], n2[2]))
  if (nmc == "t03") { y = x; y$note = "x"; y$tables[[1]] = copy(y$tables[[1]]); a = proc.time()[["elapsed"]]; b = env1$env_snap_size(x, NULL, y); t = proc.time()[["elapsed"]] - a; a = proc.time()[["elapsed"]]; b0 = env0$env_snap_size(x, NULL, y); t0 = proc.time()[["elapsed"]] - a; cat(sprintf("   shared walk: main %.5g %.3fs | new %.5g %.3fs\n", b0, t0, b, t)) }
  rm(x); invisible(gc())
}
