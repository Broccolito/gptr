# Shared helpers of the P12 adapter tests. P12 owns tests/testthat/fixtures/sse/ and no
# helper-*.R file, so every test-provider-*.R and test-live-*.R file sources this file first
# (local = TRUE, through testthat::test_path()).

# The fixture directory of an api
sse_dir = function(api) testthat::test_path("fixtures", "sse", api)

# An event collector: log$emit(ev) appends to log$events
event_log = function() {
  log = new.env(parent = emptyenv())
  log$events = list()
  log$emit = function(ev) log$events[[length(log$events) + 1L]] = ev
  log
}

# The types of a list of events
types_of = function(events) vapply(events, function(e) e$type %||% "", "")

# Replay one fixture through a normaliser in the given chunk sizes (whole stream by default)
replay_case = function(api, parse, case, sizes = NULL) {
  dir = sse_dir(api)
  path = file.path(dir, paste0(case, ".sse"))
  bytes = readBin(path, "raw", file.size(path))
  adapter = list(api = api, transport = "http_sse", parse = parse)
  adp_replay(adapter, adp_fixture_model(api, dir), bytes, sizes %||% length(bytes))
}

# Compare x with a golden JSON file of the fixture directory (04 section 12.4)
expect_golden = function(x, api, file) {
  want = json_decode(read_utf8(file.path(sse_dir(api), file))$text)
  testthat::expect_equal(json_decode(json_encode(x)), want)
}

# The golden check of every case of an api: events and the final message
expect_all_golden = function(api, parse) {
  cases = sub("\\.sse$", "", list.files(sse_dir(api), pattern = "\\.sse$"))
  testthat::expect_gt(length(cases), 0L)
  for (case in cases) {
    r = replay_case(api, parse, case)
    testthat::expect_null(r$condition)
    expect_golden(lapply(r$events, adp_golden_event), api, paste0(case, ".events.json"))
    expect_golden(adp_golden_message(r$message), api, paste0(case, ".message.json"))
  }
}

# Byte-by-byte and three pseudo-random chunkings give the events of the whole stream (INFRA-23)
expect_chunk_invariant = function(api, parse, case) {
  whole = lapply(replay_case(api, parse, case)$events, adp_golden_event)
  for (sz in list(1L, adp_chunk_sizes("a"), adp_chunk_sizes("b"), adp_chunk_sizes("c"))) {
    got = lapply(replay_case(api, parse, case, sz)$events, adp_golden_event)
    testthat::expect_identical(got, whole)
  }
}

# Exactly one start event first and exactly one terminal event last
expect_one_terminal = function(events) {
  types = types_of(events)
  testthat::expect_identical(types[[1L]], "start")
  testthat::expect_identical(sum(types == "start"), 1L)
  testthat::expect_identical(sum(types %in% c("done", "error")), 1L)
  testthat::expect_true(types[[length(types)]] %in% c("done", "error"))
}

# A model record (04 section 4.9) for normaliser and request-builder tests
test_model = function(api, id = "fixture-1", provider = "fixture", ...) {
  m = adp_fixture_model(api)
  m$id = id
  m$provider = provider
  m$ref = paste0(provider, "/", id)
  over = list(...)
  for (k in names(over)) m[[k]] = over[[k]]
  m
}
