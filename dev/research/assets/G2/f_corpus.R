# G2 (f): build per-class corpora of the text an R agent puts into its context. Output: f_corpus.rds,
# a named list class -> character vector of chunks (each chunk <= ~4000 chars, split at line ends).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
suppressPackageStartupMessages({ library(tibble) })
options(width = 100, cli.num_colors = 1, crayon.enabled = FALSE, pillar.bold = FALSE, digits = 7)
co = function(expr) paste(utils::capture.output(expr), collapse = "\n")
rd = function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chunk = function(x, size = 4000L) {                     # split long texts at line ends into ~size chunks
  out = character()
  for (t in x) {
    if (nchar(t) <= size) { out = c(out, t); next }
    lines = strsplit(t, "\n", fixed = TRUE)[[1]]
    cur = character(); n = 0L
    for (l in lines) {
      if (n + nchar(l) + 1L > size && length(cur)) { out = c(out, paste(cur, collapse = "\n")); cur = character(); n = 0L }
      cur = c(cur, l); n = n + nchar(l) + 1L
    }
    if (length(cur)) out = c(out, paste(cur, collapse = "\n"))
  }
  out[nzchar(trimws(out))]
}
ds_names = ls("package:datasets")
ds = lapply(setNames(ds_names, ds_names), function(n) get(n, "package:datasets"))
dfs = Filter(function(x) is.data.frame(x) && nrow(x) >= 5, ds)
set.seed(11)
extra = list(
  trials = data.frame(id = sprintf("P%04d", 1:300), arm = sample(c("placebo", "low dose", "high dose"), 300, TRUE),
                      start = as.Date("2022-01-01") + sample(0:700, 300, TRUE), age = round(rnorm(300, 55, 12)),
                      bmi = round(rnorm(300, 27, 4), 1), responder = sample(c(TRUE, FALSE, NA), 300, TRUE)),
  genes = data.frame(gene = paste0("ENSG", sprintf("%011d", sample(1e9, 400))), log2FC = round(rnorm(400, 0, 2), 3),
                     pval = signif(10^-runif(400, 0, 12), 3), padj = signif(10^-runif(400, 0, 10), 3), symbol = replicate(400, paste(sample(LETTERS, 4), collapse = ""))))
dfs = c(dfs, extra)
C = list()
C$print_df = chunk(vapply(dfs, function(d) co(print(utils::head(d, 60))), ""))
C$print_tibble = chunk(vapply(dfs, function(d) co(print(tibble::as_tibble(d), n = 25, width = 100)), ""))
C$str = chunk(c(vapply(ds, function(x) co(utils::str(x)), ""), vapply(extra, function(x) co(utils::str(x)), ""),
                co(utils::str(lm(mpg ~ ., mtcars))), co(utils::str(list(a = 1:3, b = list(c = "x", d = mtcars[1:3, ]))))))
num_dfs = Filter(function(d) sum(vapply(d, is.numeric, NA)) >= 3 && nrow(d) >= 10, dfs)
C$summary_lm = chunk(vapply(num_dfs, function(d) {
  nm = names(d)[vapply(d, is.numeric, NA)]
  f = stats::as.formula(paste0("`", nm[1], "` ~ ", paste0("`", utils::head(nm[-1], 5), "`", collapse = " + ")))
  co(print(summary(stats::lm(f, data = d))))
}, ""))
C$print_misc = chunk(c(co(print(summary(iris))), co(print(table(esoph$agegp, esoph$alcgp))), co(print(t.test(extra ~ group, sleep))),
                       co(print(round(cor(mtcars), 3))), co(print(quantile(rnorm(1e4), seq(0, 1, 0.05)))), co(print(anova(lm(mpg ~ wt * hp, mtcars)))),
                       co(print(aggregate(len ~ supp + dose, ToothGrowth, mean))), co(print(head(letters, 26))), co(print(seq(0.5, 60, by = 0.5))),
                       co(print(list(a = 1:5, b = "text", c = list(d = pi)))), co(print(summary(glm(am ~ wt, binomial, mtcars)))),
                       co(print(xtabs(~ cyl + gear, mtcars))), co(print(chisq.test(table(mtcars$cyl, mtcars$am)))), co(print(sessionInfo()))))
# errors, warnings and tracebacks as the r tool reports them (report 12 section 3.4 format)
errs = list(quote(log(-1:3, base = "e")), quote(sqrt("a")), quote(mean()), quote(lm(y ~ x, data = mtcars)), quote(solve(matrix(0, 2, 2))),
  quote(matrix(1:6, 4, 4)), quote(merge(mtcars, iris, by = "id")), quote(rbind(mtcars, iris)), quote(as.Date("2024-13-45")),
  quote(factor(1:3, levels = c(1, 1))), quote(seq(1, 10, by = -1)), quote(rep(1:3, times = -1)), quote(sample(5, 10)),
  quote(stats::quantile(c(1, NA))), quote(cor(mtcars$mpg, iris$Species)), quote(t.test(1)), quote(chol(matrix(-1))),
  quote(integrate(function(x) 1 / x, 0, 1)), quote(uniroot(function(x) x^2 + 1, c(0, 1))), quote(optim(1, function(p) NA)),
  quote(library(notapackage123)), quote(get("no_such_object_xyz")), quote(match.arg("z", c("a", "b"))), quote(stopifnot(all.equal(pi, 3.14))),
  quote(vapply(1:3, function(i) letters[i], numeric(1))), quote(do.call("nofun", list())), quote(strsplit(1:3, "")), quote(nchar(quote(x))),
  quote(mtcars[, "nonexistent"]), quote(mtcars[["nope"]][[1]]), quote(list(a = 1)$a$b), quote(new.env()$x()), quote(if (NA) 1),
  quote(if (c(TRUE, FALSE)) 1), quote(1:3 + 1:2), quote(as.integer("12abc")), quote(sum("a")), quote(read.csv("no/such/file.csv")),
  quote(readRDS("missing.rds")), quote(glm(am ~ wt, family = "binomal", data = mtcars)), quote(aov(len ~ nothere, ToothGrowth)),
  quote(predict(lm(mpg ~ wt, mtcars), newdata = data.frame(x = 1))), quote(nls(y ~ a * x, data = data.frame(x = 1:5, y = 1:5))),
  quote(apply(1:3, 1, sum)), quote(Reduce(`+`, list(1, "a"))), quote(regmatches("a", 1)), quote(setNames(1:3, c("a", "b"))),
  quote(data.frame(a = 1:3, b = 1:2)), quote(array(1:24, c(2, 3, 4))[3, 1, 1]), quote(environment(1)), quote(parse(text = "x <- (1 + ")),
  quote(eval(quote(zz_undefined + 1))), quote(UseMethod("print")), quote(as.numeric(list(1, 2:3))), quote(strtoi("zz", 36L) + "a"))
fmt_cond = function(e) {
  cl = conditionCall(e)
  sprintf("%s%s: %s", if (inherits(e, "error")) "Error" else "Warning", if (is.null(cl)) "" else paste0(" in ", paste(deparse(cl, width.cutoff = 60), collapse = " ")), conditionMessage(e))
}
err_txt = vapply(errs, function(ex) {
  msgs = character()
  r = withCallingHandlers(tryCatch({ eval(ex, new.env()); "" }, error = function(e) fmt_cond(e)),
                          warning = function(w) { msgs <<- c(msgs, fmt_cond(w)); invokeRestart("muffleWarning") })
  paste(c(sprintf("> %s", paste(deparse(ex), collapse = " ")), msgs, r, sprintf("[status: %s; 0 of 1 top-level expressions completed; 0.01s]", if (nzchar(r)) "error" else "ok")), collapse = "\n")
}, "")
tb = function(depth) {                                       # a real traceback through nested user functions
  calls = NULL
  fs = list()
  for (k in depth:1) local({ kk = k; nxt = if (kk == depth) NULL else fs[[kk + 1L]]
    fs[[kk]] <<- function(x) if (is.null(nxt)) stop("subscript out of bounds: column '", x, "' not found in `counts`") else nxt(paste0(x, kk)) })
  withCallingHandlers(tryCatch(fs[[1]]("gene"), error = function(e) NULL), error = function(e) calls <<- sys.calls())
  calls = calls[seq_len(max(0, length(calls) - 2))]
  paste(c(sprintf("Error in fs[[%d]](x): subscript out of bounds: column 'gene...' not found in `counts`", depth),
          "Traceback (outermost first):", sprintf(" %d: %s", seq_along(calls), vapply(calls, function(cl) substr(paste(deparse(cl), collapse = " "), 1, 120), ""))), collapse = "\n")
}
C$errors = chunk(c(err_txt, vapply(c(3, 5, 8, 12, 20), tb, "")), size = 3000L)
C$json = chunk(c(vapply(utils::head(dfs, 25), function(d) j(utils::head(d, 40)), ""),
                 vapply(utils::head(dfs, 10), function(d) j(utils::head(d, 40), pretty = TRUE), ""),
                 vapply(utils::head(list.files(file.path(G2, "mcp_corpus/github"), full.names = TRUE), 60), rd, "")))
C$csv = chunk(vapply(dfs, function(d) co(utils::write.csv(utils::head(d, 80), stdout(), row.names = FALSE)), ""))
r_files = c(list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto", "\\.R$", full.names = TRUE),
            list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/12", "^gptr_.*\\.R$", full.names = TRUE))
stats_fns = Filter(is.function, mget(utils::head(sort(ls(asNamespace("stats"))), 400), envir = asNamespace("stats")))
C$r_code = chunk(c(vapply(r_files, rd, ""), vapply(utils::head(stats_fns, 150), function(f) paste(deparse(f), collapse = "\n"), ""),
                   vapply(list.files(file.path(G2, "a_apps"), "\\.R$", recursive = TRUE, full.names = TRUE), rd, "")))
md_files = list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi/packages/coding-agent/docs", "\\.md$", full.names = TRUE)
C$markdown = chunk(vapply(md_files, rd, ""))
mo_strings = function(lang) {                              # report 21's .mo reader (converted to "=")
  f = list.files(file.path(R.home("library"), "translations", lang, "LC_MESSAGES"), pattern = "\\.mo$", full.names = TRUE)
  out = character()
  for (p in f) {
    r = readBin(p, "raw", file.size(p))
    u32 = function(o) sum(as.integer(r[o + 1:4]) * 256^(0:3))
    N = u32(8); tt = u32(16)
    for (i in seq_len(N) - 1) {
      len = u32(tt + 8 * i); off = u32(tt + 8 * i + 4)
      if (len > 0) { b = r[off + seq_len(len)]; b[b == as.raw(0)] = as.raw(10); out = c(out, rawToChar(b)) }
    }
  }
  Encoding(out) = "UTF-8"
  out[validUTF8(out) & !grepl("^Project-Id", out)]
}
C$cjk = chunk(c(paste(mo_strings("zh_CN"), collapse = "\n"), paste(mo_strings("ja"), collapse = "\n"), paste(mo_strings("ko"), collapse = "\n")))
cjk_df = data.frame(sample = sprintf("S%02d", 1:40), tissue = sample(c("肝脏", "肺", "脑", "血液"), 40, TRUE),
                    note = sample(c("正常", "异常值", "需要复查", "サンプル不足"), 40, TRUE), value = round(rnorm(40), 3))
C$cjk_mixed_output = chunk(c(co(print(cjk_df)), co(utils::str(cjk_df)), co(print(tibble::as_tibble(cjk_df), n = 40))))
for (k in names(C)) C[[k]] = enc2utf8(C[[k]])
saveRDS(C, file.path(G2, "f_corpus.rds"))
cat(sprintf("%-18s %5s %9s\n", "class", "chunks", "chars"))
for (k in names(C)) cat(sprintf("%-18s %5d %9d\n", k, length(C[[k]]), sum(nchar(C[[k]]))))
