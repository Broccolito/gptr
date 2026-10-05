# Live test of the native Ollama System One adapter (plan P13, IC-74; 07-local-ollama.md section
# 6). It runs only with GPTR_LIVE_TESTS=true and a local Ollama server (0.35.1 or later) on which
# Clef Flash (and, for its own test, Clef) is already installed. It never starts, installs or
# updates Ollama and never downloads a model; it sends only synthetic text and images, needs no
# key and reads no project data. A pass shows the API works from gptr, not that the decisions are
# accurate or calibrated.

source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

# The prepared model (P05's discovery on the loopback server), or a skip naming why not
skip_unless_ollama = function(ref) {
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "GPTR_LIVE_TESTS is not true")
  model = tryCatch(model_prepare(ref), error = function(e) e)
  if (inherits(model, "error")) skip(paste0(ref, " is not available: ", conditionMessage(model)))
  model
}

# A synthetic 64 x 64 PNG of one rectangle in `colour`, as a System 1 image record
live_png = function(colour) {
  path = tempfile(fileext = ".png")
  on.exit(unlink(path), add = TRUE)
  ok = tryCatch({
    grDevices::png(path, width = 64, height = 64)
    graphics::plot.new()
    graphics::rect(0.1, 0.1, 0.9, 0.9, col = colour, border = NA)
    grDevices::dev.off()
    TRUE
  }, error = function(e) FALSE)
  if (!ok) skip("no PNG graphics device")
  list(data = readBin(path, "raw", file.size(path)), mime = "image/png")
}

# Ollama's confidence of a probability vector: 1 - H(p) / log(N)
live_conf = function(p) {
  q = p[p > 0] / sum(p)
  1 - (-sum(q * log(q))) / log(length(p))
}

test_that("Clef Flash answers yes/no, choice and fractional score questions (live)", {
  skip_unless_ollama("ollama/clef-flash")
  s1_fresh()
  local_s1_ollama_adapter()
  live = list(replay = "live")
  q = "Does this request need R code to answer it?"
  yes = ollama_call(q, text = "Fit a linear model to mtcars and plot the residuals.", args = live)
  no = ollama_call(q, text = "Write a four-line poem about the sea.", args = live)
  expect_true(all(is.finite(c(gptr_prob(yes), gptr_prob(no)))))
  expect_gt(gptr_prob(yes), gptr_prob(no))
  m = attr(yes, "meta")
  expect_identical(m[c("provider", "api", "execution", "locality")],
                   list(provider = "ollama", api = "ollama-system-one", execution = "native",
                        locality = "local"))
  expect_true(is.character(m$model_digest) && nzchar(m$model_digest))
  expect_identical(m$calibrated, NA)
  ch = ollama_call("Which kind of work is this request?",
                   text = "Summarise the mean and standard deviation of each column of iris.",
                   args = c(live, list(choices = c(analysis = "Data analysis", writing = "Prose",
                                                   admin = "Administration"))))
  p = gptr_prob(ch, "probabilities")
  expect_identical(colnames(p), c("analysis", "writing", "admin"))
  expect_equal(sum(p), 1, tolerance = 0.02)
  expect_equal(unname(gptr_prob(ch, "confidence")), live_conf(p[1, ]), tolerance = 0.01)
  sc = ollama_call("How ready is this plan to run?",
                   text = "Load the data, fit the model, check the residuals, write the report.",
                   args = c(live, list(levels = c("not ready", "partly ready", "ready"))))
  v = unname(as.double(sc))
  expect_true(v >= 0 && v <= 2)
  expect_equal(v, sum((0:2) * gptr_prob(sc, "probabilities")[1, ]), tolerance = 0.01)
})

test_that("Clef Flash tells paired synthetic images apart and refuses invalid ones (live)", {
  model = skip_unless_ollama("ollama/clef-flash")
  if (!isTRUE(model$decision$images)) skip("the server reports no vision support for Clef Flash")
  s1_fresh()
  local_s1_ollama_adapter()
  ask = function(image) {
    ollama_call("Which colour is the rectangle in the image?", text = "One rectangle.",
                args = list(replay = "live", choices = c("red", "blue"),
                            opts = list(system1_images = list(image))))
  }
  expect_identical(as.character(ask(live_png("blue"))), "blue")
  expect_identical(as.character(ask(live_png("red"))), "red")
  expect_error(ask(list(data = charToRaw("not an image"), mime = "image/png")),
               class = "gptr_error_invalid_argument")
})

test_that("Clef answers on its own when it is installed (live)", {
  skip_unless_ollama("ollama/clef")
  s1_fresh()
  local_s1_ollama_adapter()
  d = ollama_call("Does this request need R code to answer it?",
                  text = "Fit a linear model to mtcars.", model = "ollama/clef",
                  args = list(replay = "live"))
  expect_true(is.finite(gptr_prob(d)))
  expect_identical(attr(d, "meta")$locality, "local")
})
