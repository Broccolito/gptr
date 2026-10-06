# Token cost of the 20 ladder apps (plan P24): the HTML/JS-to-Shiny ratio per level and overall
# (G2 a_tokens.R) and the output cost of revising each app with edits versus a full rewrite
# (G2 a_revisions.R). The edits are derived from a line diff of apps/ against revised/ (one
# exact-match edit per changed hunk, widened by context lines until its oldText is unique, Pi's
# edit semantics). Tracked, not gated; from the repository root:
#   Rscript --vanilla dev/bench/shiny-html/tokens.R     # writes dev/bench/shiny-html/results.csv

source(file.path("dev", "bench", "common.R"), local = TRUE)

# Longest-common-subsequence line matching; returns the hunks as index ranges.
lcs_hunks = function(a, b) {
  n = length(a)
  m = length(b)
  lcs = matrix(0L, n + 1L, m + 1L)
  for (i in rev(seq_len(n))) for (j in rev(seq_len(m))) {
    lcs[i, j] = if (a[[i]] == b[[j]]) {
      lcs[i + 1L, j + 1L] + 1L
    } else {
      max(lcs[i + 1L, j], lcs[i, j + 1L])
    }
  }
  i = 1L
  j = 1L
  keep_a = logical(n)
  keep_b = logical(m)
  while (i <= n && j <= m) {
    if (a[[i]] == b[[j]]) {
      keep_a[[i]] = TRUE
      keep_b[[j]] = TRUE
      i = i + 1L
      j = j + 1L
    } else if (lcs[i + 1L, j] >= lcs[i, j + 1L]) {
      i = i + 1L
    } else {
      j = j + 1L
    }
  }
  hunks = list()
  ia = 1L
  ib = 1L
  while (ia <= n || ib <= m) {
    if (ia <= n && ib <= m && keep_a[[ia]] && keep_b[[ib]]) {
      ia = ia + 1L
      ib = ib + 1L
      next
    }
    sa = ia
    sb = ib
    while (ia <= n && !keep_a[[ia]]) ia = ia + 1L
    while (ib <= m && !keep_b[[ib]]) ib = ib + 1L
    hunks[[length(hunks) + 1L]] = list(a = c(sa, ia - 1L), b = c(sb, ib - 1L))
  }
  hunks
}

count_fixed = function(x, pat) {
  m = gregexpr(pat, x, fixed = TRUE)[[1L]]
  if (m[[1L]] == -1L) 0L else length(m)
}

# Exact-match edits turning lines a into lines b, each oldText unique in the original.
derive_edits = function(a, b) {
  text_a = paste(a, collapse = "\n")
  lapply(lcs_hunks(a, b), function(h) {
    ctx = 0L
    repeat {
      lo_a = max(1L, h$a[[1L]] - ctx)
      hi_a = min(length(a), h$a[[2L]] + ctx)
      lo_b = max(1L, h$b[[1L]] - ctx)
      hi_b = min(length(b), h$b[[2L]] + ctx)
      old = paste(a[seq(lo_a, hi_a, length.out = max(0L, hi_a - lo_a + 1L))], collapse = "\n")
      new = paste(b[seq(lo_b, hi_b, length.out = max(0L, hi_b - lo_b + 1L))], collapse = "\n")
      if (nzchar(old) && count_fixed(text_a, old) == 1L) break
      ctx = ctx + 1L
      if (ctx > length(a)) break
    }
    list(oldText = old, newText = new)
  })
}

if (sys.nframe() == 0L) quit(save = "no", status = bench_run(function() {
  base = file.path("dev", "bench", "shiny-html")
  j = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  rows = list()
  for (lv in paste0("L", 1:5)) for (impl in c("shiny_a", "shiny_b", "html_a", "html_b")) {
    rel = file.path(lv, paste0(impl, if (startsWith(impl, "shiny")) ".R" else ".html"))
    a = readLines(file.path(base, "apps", rel), warn = FALSE, encoding = "UTF-8")
    b = readLines(file.path(base, "revised", rel), warn = FALSE, encoding = "UTF-8")
    x = paste(a, collapse = "\n")
    edits = derive_edits(a, b)
    rows[[length(rows) + 1L]] = data.frame(
      level = lv, impl = impl, side = if (startsWith(impl, "shiny")) "shiny" else "html",
      lines = length(a), o200k = tok_count(x),
      write_arg = tok_count(j(list(path = rel, content = x))),
      n_edits = length(edits), edit_tok = tok_count(j(list(path = rel, edits = edits))),
      rewrite_tok = tok_count(j(list(path = rel, content = paste(b, collapse = "\n")))),
      stringsAsFactors = FALSE)
  }
  d = do.call(rbind, rows)
  bench_write_csv(d, file.path(base, "results.csv"))
  tot = function(col, side) sum(d[[col]][d$side == side])
  message(sprintf("html/shiny o200k ratio: %.2f (G2: 2.35)", tot("o200k", "html") /
                    tot("o200k", "shiny")))
  for (lv in unique(d$level)) {
    s = d$o200k[d$level == lv & d$side == "shiny"]
    h = d$o200k[d$level == lv & d$side == "html"]
    message(sprintf("  %s shiny %6.1f html %6.1f ratio %.2f", lv, mean(s), mean(h),
                    mean(h) / mean(s)))
  }
  message(sprintf("rewrite/edit: shiny %.1fx, html %.1fx (G2: 3.9x, 6.1x)",
                  tot("rewrite_tok", "shiny") / tot("edit_tok", "shiny"),
                  tot("rewrite_tok", "html") / tot("edit_tok", "html")))
}))
