bench_source_only("cache-sim", "run.R")

tok_chars = function(x) nchar(x)
big = function(ch, n = 600L) strrep(ch, n)

test_that("a repeated prefix is read from the cache and written only at breakpoints", {
  cache = sim_new_cache()
  sb = sim_blocks(big("T"), big("a"), big("b"), c(big("u"), big("v")))
  r1 = sim_request(cache, sb, tok_chars, "m", 0)
  expect_identical(unname(r1[["read"]]), 0)
  expect_identical(unname(r1[["write1h"]] + r1[["write5m"]]), unname(r1[["total"]]))
  sb2 = sim_blocks(big("T"), big("a"), big("b"), c(big("u"), big("v"), big("w")))
  r2 = sim_request(cache, sb2, tok_chars, "m", 20)
  expect_identical(unname(r2[["read"]]), 3000)
  expect_identical(unname(r2[["write5m"]]), 600)
})

test_that("entries expire with their TTL, are model-scoped and respect the minimum prefix", {
  sb = sim_blocks(big("T"), big("a"), big("b"), c(big("u"), big("v")), ttl_anchor = 300)
  cache = sim_new_cache()
  sim_request(cache, sb, tok_chars, "m", 0)
  expect_identical(unname(sim_request(cache, sb, tok_chars, "m", 301)[["read"]]), 0)
  cache = sim_new_cache()
  sim_request(cache, sb, tok_chars, "m", 0)
  expect_identical(unname(sim_request(cache, sb, tok_chars, "other", 10)[["read"]]), 0)
  small = sim_blocks("T", "a", "b", c("u", "v"))
  cache = sim_new_cache()
  r = sim_request(cache, small, tok_chars, "m", 0)
  expect_identical(unname(r[["write5m"]] + r[["write1h"]]), 0)
})

test_that("the gap-based tail TTL switches to 1 h after 241 s and not after 239 s", {
  expect_identical(sim_tail_ttl(241), 3600)
  expect_identical(sim_tail_ttl(239), 300)
})

test_that("the gptr strategy keeps the 1 h tail from the 12-minute pause on, as P07 does", {
  bench_test_load_gptr()
  reqs = lapply(c(5L, 6L, 6L), function(turn) {
    list(model = "m", turn = turn, system = list(t0 = "a", t1 = "b"), messages = list())
  })
  sc = list(requests = reqs, tools_json = "[]", idle_turn = 6L)
  rq = cache_sim_requests(sc)
  expect_identical(vapply(rq, function(r) r$time, 0), c(20, 760, 780))
  expect_identical(vapply(rq, function(r) r$blocks$ttl[[3L]], 0), c(300, 3600, 3600))
})

test_that("messages are priced as gptr's Anthropic adapter sends them, without record metadata", {
  bench_test_load_gptr()
  m = msg_assistant(list(block_text("Done.")), api = "fake", provider = "p", model = "p-1")
  sc = list(requests = list(list(model = "p/p-1", turn = 1L, system = list(t0 = "a", t1 = "b"),
                                 messages = list(m))),
            tools_json = "[]", idle_turn = 6L)
  expect_identical(cache_sim_requests(sc)[[1L]]$blocks$blocks[[4L]],
                   "{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Done.\"}]}")
})

test_that("costs follow the Opus 5.5 prices", {
  cache = sim_new_cache()
  sb = sim_blocks(big("T"), big("a"), big("b"), big("u"), ttl_anchor = 3600, tail_ttl = 300)
  r = sim_request(cache, sb, tok_chars, "m", 0)
  expect_equal(unname(r[["cost"]]), (1200 * 8 + 1200 * 8 + 0 * 5) / 1e6 + 0)
})
