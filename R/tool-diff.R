# Line diff in pure base R (P10; research 11 section 5.5, contract 7.10): common prefix/suffix
# trim, patience anchors (unique lines, longest increasing subsequence), Myers O(ND) on the gaps
# capped at D = 256 (a gap beyond the cap is reported as replaced, still a valid edit script), and
# GNU-style unified rendering.

diff_max_d = 256L

#' Indices of a longest strictly increasing subsequence of `x` (patience sort, O(n log n))
#' Piles are found by binary search: findInterval() re-checks sortedness on every call, which made
#' a moved block in a long file quadratic.
#' @noRd
diff_lis = function(x) {
  n = length(x)
  if (n <= 1L || !is.unsorted(x, strictly = TRUE)) return(seq_len(n))
  tails_val = numeric(n)
  tails_idx = integer(n)
  prev = integer(n)
  len = 0L
  for (i in seq_len(n)) {
    xi = x[i]
    if (len == 0L || xi > tails_val[len]) {
      k = len
      len = len + 1L
    } else {
      k = 0L
      hi = len - 1L
      while (k < hi) {
        mid = (k + hi + 1L) %/% 2L
        if (tails_val[mid] < xi) k = mid else hi = mid - 1L
      }
    }
    prev[i] = if (k > 0L) tails_idx[k] else 0L
    tails_val[k + 1L] = xi
    tails_idx[k + 1L] = i
  }
  out = integer(len)
  j = tails_idx[len]
  for (p in rev(seq_along(out))) {
    out[p] = j
    j = prev[j]
  }
  out
}

#' Length of the common run a[x + 1 ..], b[y + 1 ..]: eight scalar steps, then doubling vector
#' blocks
#' @noRd
diff_snake = function(a, b, x, y) {
  len_max = min(length(a) - x, length(b) - y)
  k = 0L
  while (k < len_max && k < 8L) {
    if (a[x + k + 1L] != b[y + k + 1L]) return(k)
    k = k + 1L
  }
  blk = 64L
  while (k < len_max) {
    len = min(blk, len_max - k)
    i = seq_len(len)
    neq = which(a[x + k + i] != b[y + k + i])
    if (length(neq)) return(k + neq[1L] - 1L)
    k = k + len
    blk = blk * 2L
  }
  len_max
}

#' Myers greedy forward pass: matched pairs `list(a, b)`, or NULL when the distance exceeds `max_d`
#' Round d keeps only its window -d .. d of `v` for the backtrack: memory O(D^2), not O(D(n + m)).
#' @noRd
diff_myers = function(a, b, max_d = diff_max_d) {
  n = length(a)
  m = length(b)
  dmax = as.integer(min(n + m, max_d))
  off = dmax + 2L
  v = integer(2L * off + 1L)
  trace = vector("list", dmax + 1L)
  for (d in 0:dmax) {
    trace[[d + 1L]] = v[off + seq.int(-d, d)]
    for (k in seq.int(-d, d, by = 2L)) {
      down = k == -d || (k != d && v[off + k - 1L] < v[off + k + 1L])
      x = if (down) v[off + k + 1L] else v[off + k - 1L] + 1L
      y = x - k
      if (x < n && y < m && a[x + 1L] == b[y + 1L]) {
        s = diff_snake(a, b, x, y)
        x = x + s
        y = y + s
      }
      v[off + k] = x
      if (x >= n && y >= m) return(diff_myers_back(trace, d, n, m))
    }
  }
  NULL
}

#' Backtrack a finished Myers pass into matched index pairs (snakes recorded as ranges: linear time)
#' `trace[[dd + 1]]` holds diagonals -dd .. dd of `v` before round dd (diagonal k at k + dd + 1).
#' @noRd
diff_myers_back = function(trace, d, n, m) {
  ra = integer(0)
  rb = integer(0)
  rl = integer(0)
  x = n
  y = m
  for (dd in rev(seq_len(d))) {
    vv = trace[[dd + 1L]]
    w = dd + 1L
    kk = x - y
    down = kk == -dd || (kk != dd && vv[w + kk - 1L] < vv[w + kk + 1L])
    pk = if (down) kk + 1L else kk - 1L
    px = vv[w + pk]
    py = px - pk
    len = min(x - px, y - py)
    if (len > 0L) {
      ra = c(ra, x - len + 1L)
      rb = c(rb, y - len + 1L)
      rl = c(rl, len)
    }
    x = px
    y = py
  }
  if (x > 0L && y > 0L) {
    len = min(x, y)
    ra = c(ra, x - len + 1L)
    rb = c(rb, y - len + 1L)
    rl = c(rl, len)
  }
  if (!length(rl)) return(list(a = integer(0), b = integer(0)))
  o = order(ra)
  idx = sequence(rl[o]) - 1L
  list(a = rep(ra[o], rl[o]) + idx, b = rep(rb[o], rl[o]) + idx)
}

#' Match vector: element i is the index of `b` matched to `a[i]` (0 = deleted); matches increase
#' Ranges still to diff are a stack of four integer vectors (`top` its height): pops copy nothing.
#' @noRd
diff_match = function(a, b, max_d = diff_max_d) {
  u = unique(c(a, b))
  ta = match(a, u)
  tb = match(b, u)
  m = integer(length(a))
  s_a0 = 1L
  s_a1 = length(a)
  s_b0 = 1L
  s_b1 = length(b)
  top = 1L
  while (top > 0L) {
    a0 = s_a0[top]
    a1 = s_a1[top]
    b0 = s_b0[top]
    b1 = s_b1[top]
    top = top - 1L
    if (a0 > a1 || b0 > b1) next
    k = min(a1 - a0, b1 - b0) + 1L
    neq = which(ta[a0:(a0 + k - 1L)] != tb[b0:(b0 + k - 1L)])
    p = if (length(neq)) neq[1L] - 1L else k
    if (p > 0L) {
      m[a0:(a0 + p - 1L)] = b0:(b0 + p - 1L)
      a0 = a0 + p
      b0 = b0 + p
    }
    if (a0 > a1 || b0 > b1) next
    k = min(a1 - a0, b1 - b0) + 1L
    neq = which(ta[a1:(a1 - k + 1L)] != tb[b1:(b1 - k + 1L)])
    s = if (length(neq)) neq[1L] - 1L else k
    if (s > 0L) {
      m[(a1 - s + 1L):a1] = (b1 - s + 1L):b1
      a1 = a1 - s
      b1 = b1 - s
    }
    if (a0 > a1 || b0 > b1) next
    ra = ta[a0:a1]
    rb = tb[b0:b1]
    ua = !duplicated(ra) & !duplicated(ra, fromLast = TRUE)
    ub = !duplicated(rb) & !duplicated(rb, fromLast = TRUE)
    pa = which(ua)
    pb = match(ra[pa], rb)
    ok = !is.na(pb)
    pa = pa[ok]
    pb = pb[ok]
    ok = ub[pb]
    pa = pa[ok]
    pb = pb[ok]
    if (length(pa)) {
      keep = diff_lis(pb)
      pa = pa[keep] + a0 - 1L
      pb = pb[keep] + b0 - 1L
      m[pa] = pb
      lo_a = c(a0, pa + 1L)
      hi_a = c(pa - 1L, a1)
      lo_b = c(b0, pb + 1L)
      hi_b = c(pb - 1L, b1)
      gap = which(lo_a <= hi_a & lo_b <= hi_b)
      if (length(gap)) {
        at = top + seq_along(gap)
        s_a0[at] = lo_a[gap]
        s_a1[at] = hi_a[gap]
        s_b0[at] = lo_b[gap]
        s_b1[at] = hi_b[gap]
        top = top + length(gap)
      }
      next
    }
    my = diff_myers(ra, rb, max_d)
    if (!is.null(my) && length(my$a)) m[my$a + a0 - 1L] = my$b + b0 - 1L
  }
  m
}

#' Edit script `data.frame(op = "=" | "-" | "+", a = line of a or NA, b = line of b or NA)` in file
#' order
#' @noRd
diff_ops = function(a, b, max_d = diff_max_d) {
  m = diff_match(a, b, max_d)
  matched_a = m > 0L
  mb = logical(length(b))
  mb[m[matched_a]] = TRUE
  ca = cumsum(matched_a)
  cb = cumsum(mb)
  del = which(!matched_a)
  ins = which(!mb)
  eq = which(matched_a)
  op = c(rep("-", length(del)), rep("+", length(ins)), rep("=", length(eq)))
  ia = c(del, rep(NA_integer_, length(ins)), eq)
  ib = c(rep(NA_integer_, length(del)), ins, m[eq])
  grp = c(ca[del] + 1L, cb[ins] + 1L, ca[eq])
  typ = c(rep(1L, length(del)), rep(2L, length(ins)), rep(3L, length(eq)))
  o = order(grp, typ, c(del, ins, eq), method = "radix")
  data.frame(op = op[o], a = ia[o], b = ib[o], stringsAsFactors = FALSE)
}

#' Unified hunks (`@@ -a,b +c,d @@` and " ", "-", "+" lines) of an edit script, vectorised
#' An empty range names the line before it (GNU: `-5,0`); `context` is clamped to the script.
#' @noRd
diff_hunks = function(a, b, ops, context = 3L, a_final_nl = TRUE, b_final_nl = TRUE) {
  op = ops$op
  ia = ops$a
  ib = ops$b
  nr = length(op)
  ch = which(op != "=")
  if (!length(ch)) return(character())
  context = min(context, nr)
  brk = c(TRUE, diff(ch) > 2 * context + 1)
  starts = as.integer(pmax(1, ch[brk] - context))
  ends = as.integer(pmin(nr, ch[c(brk[-1L], TRUE)] + context))
  size = ends - starts + 1L
  rows = sequence(size, from = starts)
  hunk = rep(seq_along(starts), size)
  has_a = !is.na(ia)
  has_b = !is.na(ib)
  a_before = c(0L, cumsum(has_a))[starts]
  b_before = c(0L, cumsum(has_b))[starts]
  a_n = tabulate(hunk[has_a[rows]], nbins = length(starts))
  b_n = tabulate(hunk[has_b[rows]], nbins = length(starts))
  rng = function(s, n) ifelse(n == 1L, sprintf("%d", s), sprintf("%d,%d", s, n))
  header = sprintf("@@ -%s +%s @@", rng(a_before + (a_n > 0L), a_n),
                   rng(b_before + (b_n > 0L), b_n))
  o_op = op[rows]
  o_a = ia[rows]
  o_b = ib[rows]
  text = character(length(rows))
  text[!is.na(o_a)] = a[o_a[!is.na(o_a)]]
  text[o_op == "+"] = b[o_b[o_op == "+"]]
  body = paste0(c("=" = " ", "-" = "-", "+" = "+")[o_op], text)
  nonl = (!a_final_nl & !is.na(o_a) & o_a == length(a) & o_op != "+") |
    (!b_final_nl & !is.na(o_b) & o_b == length(b) & o_op != "-")
  body = as.vector(rbind(body, ifelse(nonl, "\\ No newline at end of file", NA_character_)))
  body_hunk = rep(hunk, each = 2L)
  keep = !is.na(body)
  out = c(header, body[keep])
  o = order(c(seq_along(header), body_hunk[keep]), c(integer(length(header)), seq_len(sum(keep))),
            method = "radix")
  utf8_mark(unname(out[o]))
}

#' Cut diff lines to a token budget, ending with a notice (alone below about 12 tokens)
#' @noRd
diff_budget = function(lines, max_tokens) {
  if (!length(lines) || est_tokens(lines, "code") <= max_tokens) return(lines)
  lo = 0L
  hi = length(lines)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (est_tokens(lines[seq_len(mid)], "code") + 12 <= max_tokens) lo = mid else hi = mid - 1L
  }
  c(lines[seq_len(lo)], paste0("[diff truncated: ", length(lines) - lo, " more lines]"))
}

#' Unified diff of two line vectors (contract section 7.10): hunk lines without file headers
#' `character()` when equal; `max_tokens` caps the estimated tokens (`Inf`: no cap).
#' @noRd
diff_lines = function(old, new, context = 3L, max_tokens = 400L) {
  check_strings(old, "old")
  check_strings(new, "new")
  context = check_number(context, "context", min = 0, int = TRUE)
  check_number(max_tokens, "max_tokens", min = 1)
  old = as_utf8(old)
  new = as_utf8(new)
  out = diff_hunks(old, new, diff_ops(old, new), context = context)
  if (is.finite(max_tokens)) out = diff_budget(out, max_tokens)
  out
}

#' Lines of a text and whether it ends with a newline ("a\nb\n" -> c("a", "b"), TRUE)
#' @noRd
diff_split = function(x) {
  x = as_utf8(x)
  if (!nzchar(x)) return(list(lines = character(), final_nl = TRUE))
  l = utf8_mark(strsplit(paste0(x, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
  nl = l[length(l)] == ""
  if (nl) l = l[-length(l)]
  list(lines = l, final_nl = nl)
}

#' Full unified diff of two texts: `--- a/<path>`, `+++ b/<path>`, hunks and "\ No newline" markers
#' A last line without its newline gets its negated code, so a final-newline change is a change.
#' @noRd
diff_unified = function(path, old, new, context = 3L) {
  check_string(path, "path")
  check_string(old, "old", empty = TRUE)
  check_string(new, "new", empty = TRUE)
  context = check_number(context, "context", min = 0, int = TRUE)
  a = diff_split(old)
  b = diff_split(new)
  u = unique(c(a$lines, b$lines))
  ka = match(a$lines, u)
  kb = match(b$lines, u)
  if (!a$final_nl && length(ka)) ka[length(ka)] = -ka[length(ka)]
  if (!b$final_nl && length(kb)) kb[length(kb)] = -kb[length(kb)]
  hunks = diff_hunks(a$lines, b$lines, diff_ops(ka, kb), context = context,
                     a_final_nl = a$final_nl, b_final_nl = b$final_nl)
  if (!length(hunks)) return(character())
  c(paste0("--- a/", path), paste0("+++ b/", path), hunks)
}
