# Anthropic prompt-cache simulator (plan P24; architecture 12.7 row "Cache economics"), adapted
# from G4 section 5.8 with its fact-check: input tokens only, every request at Opus 5.5 prices.
# Documented rules: a prefix hash over tools -> system -> messages at block granularity; writes
# only at breakpoints; reads look back at most 20 blocks from each breakpoint; entries are
# model-scoped, readable until their TTL expires and refreshed by each read; a minimum cacheable
# prefix (512 tokens on the 5.x models, 4,096 on Haiku 4.5). `tok` is any function chr -> int.

sim_prices = c(input = 4, w5m = 5, w1h = 8, read = 0.20) # USD per million tokens

sim_new_cache = function() {
  e = new.env(parent = emptyenv())
  e$store = list()
  e
}

# The block view of one request: tools, T0, T1, then one block per message; breakpoints on T0
# and on the first message (`ttl_anchor`), and on the last block (the tail, `tail_ttl`).
sim_blocks = function(tools_json, t0, t1, messages, ttl_anchor = 3600, tail_ttl = 300) {
  blocks = c(tools_json, t0, t1, messages)
  n = length(blocks)
  bp = integer(n)
  ttl = numeric(n)
  bp[[2L]] = 1L
  ttl[[2L]] = ttl_anchor
  if (n >= 4L) {
    bp[[4L]] = 1L
    ttl[[4L]] = ttl_anchor
  }
  bp[[n]] = 1L
  if (ttl[[n]] == 0) ttl[[n]] = tail_ttl
  list(blocks = blocks, bp = bp, ttl = ttl)
}

# One request: returns c(total, read, write5m, write1h, uncached, cost).
sim_request = function(cache, sb, tok, model, time, min_tokens = 512L, price = sim_prices) {
  k = tok(sb$blocks)
  cum = cumsum(k)
  h = vapply(seq_along(sb$blocks), function(i) rlang::hash(c(model, sb$blocks[seq_len(i)])), "")
  alive = function(key) !is.null(cache$store[[key]]) && cache$store[[key]]$exp >= time
  bps = which(sb$bp == 1L)
  read_pos = 0L
  for (b in bps) {
    for (j in b:max(1L, b - 19L)) {
      if (alive(h[[j]]) && cum[[j]] >= min_tokens) {
        read_pos = max(read_pos, j)
        break
      }
    }
  }
  if (read_pos > 0L) {
    cache$store[[h[[read_pos]]]]$exp = time + cache$store[[h[[read_pos]]]]$ttl
  }
  w5 = 0
  w1 = 0
  prev = read_pos
  for (b in bps[bps > read_pos]) {
    if (cum[[b]] < min_tokens) next
    seg = sum(k[(prev + 1L):b])
    if (sb$ttl[[b]] >= 3600) w1 = w1 + seg else w5 = w5 + seg
    cache$store[[h[[b]]]] = list(exp = time + sb$ttl[[b]], ttl = sb$ttl[[b]])
    prev = b
  }
  read = if (read_pos > 0L) cum[[read_pos]] else 0
  uncached = sum(k) - read - w5 - w1
  cost = (uncached * price[["input"]] + w5 * price[["w5m"]] + w1 * price[["w1h"]] +
            read * price[["read"]]) / 1e6
  c(total = sum(k), read = read, write5m = w5, write1h = w1, uncached = uncached, cost = cost)
}

# The tail TTL of the gap rule (architecture 6.11): 1 h after a gap over gptr.cache_gap, else 5 min.
sim_tail_ttl = function(gap, cache_gap = 240) ifelse(gap > cache_gap, 3600, 300)

# Simulates requests (each list(model, time, min_tokens, blocks = a sim_blocks() result) on one
# cache; one row per request, labelled with the strategy.
sim_session = function(requests, tok, label) {
  cache = sim_new_cache()
  rows = lapply(seq_along(requests), function(i) {
    r = requests[[i]]
    c(i = i, time = r$time, sim_request(cache, r$blocks, tok, r$model, r$time, r$min_tokens))
  })
  d = as.data.frame(do.call(rbind, rows))
  d$strategy = label
  d
}

# The requests scenario.R recorded -> simulator inputs for one TTL strategy: 20 s between
# requests plus the 12-minute pause; the gap rule keeps 1 h once a gap exceeded gptr.cache_gap
# (as P07's prompt_cache_ttl_next() does). Messages are the elements gptr's Anthropic adapter
# sends, without cache_control markers (G4 section 5.8 renders and hashes them so).
cache_sim_requests = function(sc, ttl_anchor = 3600, tail = "gap") {
  turn = vapply(sc$requests, function(r) r$turn, 0L)
  idle = turn == sc$idle_turn & c(0L, turn[-length(turn)]) < sc$idle_turn
  times = cumsum(20 + 720 * idle)
  tail_ttl = switch(tail, gap = sim_tail_ttl(cummax(c(0, diff(times)))), "5m" = 300, "1h" = 3600)
  tail_ttl = rep_len(tail_ttl, length(times))
  lapply(seq_along(sc$requests), function(i) {
    r = sc$requests[[i]]
    msgs = anthropic_elements(list(), r$messages, list(), anchors = character())$elements
    list(model = r$model, time = times[[i]],
         min_tokens = if (startsWith(r$model, "simhaiku")) 4096L else 512L,
         blocks = sim_blocks(sc$tools_json, r$system$t0, r$system$t1, msgs,
                             ttl_anchor = ttl_anchor, tail_ttl = tail_ttl[[i]]))
  })
}

cache_sim_summary = function(d) {
  s = stats::aggregate(cbind(total, read, write5m, write1h, uncached, cost) ~ strategy, data = d,
                       FUN = sum)
  s$hit_rate = round(s$read / s$total, 3)
  s$cost = round(s$cost, 6)
  s[order(s$strategy), , drop = FALSE]
}
