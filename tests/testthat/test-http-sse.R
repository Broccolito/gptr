sse_all = function(chunks) {
  s = sse_splitter()
  out = list()
  for (ch in chunks) out = c(out, s$push(ch))
  fl = s$flush()
  if (!is.null(fl)) out = c(out, list(fl))
  out
}

split_at = function(bytes, cuts) {
  cuts = sort(unique(cuts[cuts > 0L & cuts < length(bytes)]))
  starts = c(1L, cuts + 1L)
  ends = c(cuts, length(bytes))
  lapply(seq_along(starts), function(i) bytes[starts[i]:ends[i]])
}

test_that("sse_splitter parses LF streams with event, data, id and retry", {
  b = charToRaw("event: ping\ndata: {\"a\":1}\nid: 7\nretry: 1500\n\ndata: x\n\n")
  ev = sse_all(list(b))
  expect_length(ev, 2L)
  expect_identical(ev[[1]]$event, "ping")
  expect_identical(ev[[1]]$data, "{\"a\":1}")
  expect_identical(ev[[1]]$id, "7")
  expect_identical(ev[[1]]$retry, 1500)
  expect_null(ev[[2]]$event)
  expect_identical(ev[[2]]$data, "x")
  expect_null(ev[[2]]$id)
  expect_null(ev[[2]]$retry)
})

test_that("CRLF, CR-only and a CRLF split across chunks give the LF result", {
  lf = sse_all(list(charToRaw("event: a\ndata: 1\n\nevent: b\ndata: 2\n\n")))
  crlf = sse_all(list(charToRaw("event: a\r\ndata: 1\r\n\r\nevent: b\r\ndata: 2\r\n\r\n")))
  cr = sse_all(list(charToRaw("event: a\rdata: 1\r\revent: b\rdata: 2\r\r")))
  whole = charToRaw("event: a\r\ndata: 1\r\n\r\nevent: b\r\ndata: 2\r\n\r\n")
  k = which(whole == as.raw(13L))[1]
  expect_identical(crlf, lf)
  expect_identical(cr, lf)
  expect_identical(sse_all(split_at(whole, k)), lf)
})

test_that("a leading BOM is stripped even when split across chunks", {
  b = c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("event: a\ndata: 1\n\n"))
  expect_identical(sse_all(list(b))[[1]]$event, "a")
  expect_identical(sse_all(split_at(b, c(1L, 2L)))[[1]]$event, "a")
})

test_that("the last event field wins, comments are dropped and data lines are joined", {
  b = charToRaw(": keep-alive\nevent: first\nevent: second\ndata: l1\ndata: l2\ndata:l3\n\n")
  ev = sse_all(list(b))
  expect_length(ev, 1L)
  expect_identical(ev[[1]]$event, "second")
  expect_identical(ev[[1]]$data, "l1\nl2\nl3")
})

test_that("events without data are not dispatched and flush returns the unterminated event", {
  s = sse_splitter()
  expect_length(s$push(charToRaw("event: only\n\ndata: tail")), 0L)
  fl = s$flush()
  expect_identical(fl$data, "tail")
  expect_null(fl$event)
  expect_null(s$flush())
  held = sse_splitter()
  expect_length(held$push(charToRaw("event: e\ndata: 1\n\r")), 0L)
  expect_identical(held$flush()$event, "e")
})

test_that("data stays byte-exact UTF-8 and is marked UTF-8", {
  txt = "caf\u00e9 \u65e5\u672c\u8a9e \U0001f600"
  ev = sse_all(list(charToRaw(paste0("data: ", txt, "\n\n"))))
  expect_identical(Encoding(ev[[1]]$data), "UTF-8")
  expect_identical(charToRaw(ev[[1]]$data), charToRaw(txt))
})

test_that("random re-chunking, including splits inside characters and CRLF pairs, is invariant", {
  txt = "caf\u00e9 \u65e5\u672c \U0001f600 na\u00efve"
  lines = character()
  for (i in 1:60) {
    eol = c("\n", "\r\n", "\r")[i %% 3L + 1L]
    head = if (i %% 7L == 0L) ": c" else paste0("event: e", i)
    lines = c(lines, paste0(head, eol, "event: last", i, eol, "data: ", i, " ", txt, eol,
                            "data: more", eol, eol))
  }
  bytes = charToRaw(paste(lines, collapse = ""))
  ref = sse_all(list(bytes))
  expect_length(ref, 60L)
  expect_identical(ref[[7]]$event, "last7")
  withr::with_seed(42L, {
    for (rep in 1:25) {
      cuts = sample.int(length(bytes) - 1L, sample.int(200L, 1L))
      expect_identical(sse_all(split_at(bytes, cuts)), ref)
    }
  })
  expect_identical(sse_all(split_at(bytes, seq_len(length(bytes) - 1L))), ref)
})

test_that("20,000 deltas are split, decoded and accumulated in under 1 s of CPU (INFRA-23)", {
  skip_on_cran()
  deltas = sprintf("tok%05d ", 1:20000)
  fmt = paste0("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,",
               "\"delta\":{\"type\":\"text_delta\",\"text\":\"%s\"}}\n\n")
  ev = c("event: message_start\ndata: {\"type\":\"message_start\"}\n\n", sprintf(fmt, deltas),
         "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
  bytes = charToRaw(paste(ev, collapse = ""))
  # one TCP segment (1,460 bytes) per chunk, as libcurl hands a fast stream over; the
  # invariance test above covers splits at every byte
  chunks = split_at(bytes, seq(1460L, length(bytes) - 1L, by = 1460L))
  # shared runners only add time: the best of three runs estimates the code's own cost (D-011)
  cpu = Inf
  for (run in 1:3) {
    gc()
    used = system.time({
      s = sse_splitter()
      parts = vector("list", 20100L)
      k = 0L
      for (ch in chunks) {
        for (e in s$push(ch)) {
          if (identical(e$event, "content_block_delta")) {
            d = json_decode(e$data)
            k = k + 1L
            parts[[k]] = d$delta$text
          }
        }
      }
      text = paste(unlist(parts[seq_len(k)]), collapse = "")
    })
    cpu = min(cpu, used[["user.self"]] + used[["sys.self"]])
  }
  expect_identical(k, 20000L)
  expect_identical(text, paste(deltas, collapse = ""))
  expect_lt(cpu, 1)
})

test_that("ndjson_splitter returns complete lines, strips CR and keeps the tail for flush", {
  s = ndjson_splitter()
  expect_identical(s$push(charToRaw("{\"a\":1}\r\n{\"b\"")), "{\"a\":1}")
  expect_identical(s$push(charToRaw(":2}\n\n{\"c\":3}")), "{\"b\":2}")
  expect_identical(s$flush(), "{\"c\":3}")
  expect_identical(s$flush(), character())
  u = ndjson_splitter()
  bytes = charToRaw("{\"t\":\"caf\u00e9\"}\n")
  out = c(u$push(bytes[1:12]), u$push(bytes[13:length(bytes)]))
  expect_identical(Encoding(out), "UTF-8")
  expect_identical(json_decode(out)$t, "caf\u00e9")
})

test_that("unsupported NUL data fails without silently changing provider bytes", {
  sse_bytes = c(charToRaw("data: ab"), as.raw(0), charToRaw("cd\n\n"))
  err = expect_error(sse_splitter()$push(sse_bytes), class = "gptr_error_provider")
  expect_match(conditionMessage(err), "NUL", fixed = TRUE)
  expect_false(grepl("abcd", conditionMessage(err), fixed = TRUE))
  json_bytes = c(charToRaw("{\"value\":\"ab"), as.raw(0), charToRaw("cd\"}\n"))
  expect_error(ndjson_splitter()$push(json_bytes), class = "gptr_error_provider")
  s = sse_splitter()
  expect_length(s$push(sse_bytes[seq_len(length(sse_bytes) - 2L)]), 0L)
  expect_error(s$flush(), class = "gptr_error_provider")
})

test_that("invalid retry fields leave the last valid numeric value intact", {
  s = sse_splitter()
  ev = s$push(charToRaw("retry: 1500\nretry: invalid\ndata: ok\n\n"))
  expect_identical(ev[[1L]]$retry, 1500)
  ev = s$push(charToRaw("retry: invalid\nretry: 2000\nretry: -1\ndata: ok\n\n"))
  expect_identical(ev[[1L]]$retry, 2000)
})
