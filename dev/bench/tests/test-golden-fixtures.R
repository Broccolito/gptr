# The golden transcripts that P07's dev/bench/tokens/run.R replays (plan P24; IC-73). Every
# fixture in dev/bench/tokens/fixtures/ must have the fields the runner reads, and together they
# must cover NS-1..NS-11 (architecture 12.7 row "Golden transcripts").

fixture_dir = file.path(bench_root(), "dev", "bench", "tokens", "fixtures")
fixture_files = sort(list.files(fixture_dir, pattern = "[.]json$", full.names = TRUE))
read_fixture = function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)
# The user-message sources of contract section 4.2.
message_sources = c("prompt", "pipe", "steer", "follow_up", "repl", "parent", "replay",
                    "extension", "agent", "imported")
p24_ids = c("ns01-console", "ns02c-describers", "ns05-routing", "ns09-setup", "ns11-workflow")

test_that("every golden transcript has the fields P07's runner reads", {
  expect_gte(length(fixture_files), 1L)
  ids = character()
  for (f in fixture_files) {
    fx = read_fixture(f)
    info = basename(f)
    expect_identical(paste0(fx$id, ".json"), basename(f), info = info)
    ids = c(ids, fx$id)
    expect_true(fx$north_star %in% 1:12, info = info)
    expect_true(fx$mode %in% c("plan", "manual", "edits", "auto"), info = info)
    expect_true(is.logical(fx$human) && length(fx$human) == 1L, info = info)
    expect_true(length(fx$models) >= 1L && all(grepl("^[a-z0-9-]+/", unlist(fx$models))),
                info = info)
    expect_true(is.character(fx$environment) && nzchar(fx$environment), info = info)
    expect_true(is.list(fx$turns) && length(fx$turns) >= 1L, info = info)
    for (turn in fx$turns) {
      expect_true(is.character(turn$prompt) && nzchar(turn$prompt), info = info)
      expect_true(turn$source %in% message_sources, info = info)
      for (o in turn$context) expect_true(is.character(o$label) && is.character(o$class),
                                          info = info)
      expect_gte(length(turn$steps), 1L)
      for (st in turn$steps) {
        expect_true(is.null(st$text) || is.character(st$text), info = info)
        for (cl in st$calls) {
          expect_true(all(c("id", "name", "input", "result") %in% names(cl)), info = info)
          for (im in cl$images) expect_length(im, 2L)
        }
      }
    }
  }
  expect_false(anyDuplicated(ids) > 0L)
})

test_that("the golden transcripts cover every north-star example NS-1..NS-11", {
  ns = vapply(fixture_files, function(f) as.integer(read_fixture(f)$north_star), 0L)
  missing = setdiff(1:11, ns)
  expect_identical(missing, integer(), info = paste("missing:", paste(missing, collapse = ", ")))
})

test_that("P24's fixtures build their objects in base R and end every turn with an answer", {
  for (id in p24_ids) {
    f = file.path(fixture_dir, paste0(id, ".json"))
    expect_true(file.exists(f), info = id)
    if (!file.exists(f)) next
    fx = read_fixture(f)
    for (nm in names(fx$objects)) {
      v = eval(parse(text = fx$objects[[nm]]), envir = new.env(parent = baseenv()))
      expect_false(is.null(v), info = paste(id, nm))
    }
    ids = character()
    for (turn in fx$turns) {
      last = turn$steps[[length(turn$steps)]]
      expect_length(last$calls, 0L)
      expect_true(is.character(last$text) && nzchar(last$text), info = id)
      for (st in turn$steps) for (cl in st$calls) {
        ids = c(ids, cl$id)
        expect_true(cl$name %in% c("r", "read", "edit", "write", "ask"), info = id)
      }
    }
    expect_false(anyDuplicated(ids) > 0L, info = id)
  }
})

test_that("the describer fixture attaches every object it lists facts for", {
  fx = read_fixture(file.path(fixture_dir, "ns02c-describers.json"))
  labels = vapply(fx$turns[[1L]]$context, function(o) o$label, "")
  expect_setequal(labels, names(fx$objects))
  expect_true(all(labels %in% unlist(fx$facts)))
  expect_gte(length(fx$facts), 20L)
})
