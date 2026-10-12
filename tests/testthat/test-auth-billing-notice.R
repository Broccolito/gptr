# A successful protective removal is informational; genuine warnings keep their R semantics.
# The fake complete environment never reads caller credentials.

billing_notice_child = function(parent) {
  child = child_env
  environment(child) = list2env(list(
    Sys.getenv = function(...) parent,
    child_env_empty_file = function(name) paste0("/owned-test/", name)
  ), parent = environment(child))
  child
}

billing_notice_capture = function(expr, muffle = FALSE) {
  seen = new.env(parent = emptyenv())
  seen$cnd = NULL
  seen$warnings = list()
  out = utils::capture.output({
    err = utils::capture.output({
      seen$value = withCallingHandlers(expr,
        gptr_message_billing_env = function(cnd) {
          seen$cnd = cnd
          if (muffle) invokeRestart("muffleMessage")
        },
        gptr_warning_billing_env = function(cnd) {
          seen$warnings = c(seen$warnings, list(cnd))
          invokeRestart("muffleWarning")
        })
    }, type = "message")
  })
  list(value = seen$value, cnd = seen$cnd, warnings = seen$warnings, out = out, err = err)
}

local_billing_notice_once = function(.env = parent.frame()) {
  old = the$once
  the$once = new.env(parent = emptyenv())
  withr::defer({
    the$once = old
  }, envir = .env)
}

test_that("billing removal is a typed neutral notice with unchanged filtering and parent", {
  local_gptr_options(quiet = FALSE)
  local_billing_notice_once()
  before = Sys.getenv()
  for (profile in c("cli-claude", "cli-codex")) {
    vars = child_env_profiles_builtin()[[profile]]$billing$vars
    parent = c(PATH = "/owned-test/bin", MY_PLAIN_SETTING = "synthetic-safe",
      stats::setNames(rep("FAKE-BILLING-VALUE", length(vars)), vars))
    child = billing_notice_child(parent)
    x = billing_notice_capture(child(profile))
    expect_identical(x$warnings, list())
    expect_s3_class(x$cnd, "gptr_message_billing_env")
    expect_false(inherits(x$cnd, "warning"))
    expect_identical(x$cnd$variables, sort(vars))
    expect_identical(x$err, character())
    expect_length(x$out, 1L)
    expect_match(x$out, paste0("the ", profile, " child"), fixed = TRUE)
    expect_match(x$out, "switch the CLI to API billing or to another account", fixed = TRUE)
    expect_false(any(grepl("FAKE-BILLING-VALUE", x$out, fixed = TRUE)))
    expect_false(any(vars %in% names(x$value)))
    expect_identical(x$value[["MY_PLAIN_SETTING"]], "synthetic-safe")
    expect_identical(parent[vars], stats::setNames(rep("FAKE-BILLING-VALUE", length(vars)), vars))
  }
  expect_identical(Sys.getenv(), before)
})

test_that("billing notice remains once per removed set and respects explicit consent", {
  local_gptr_options(quiet = FALSE)
  local_billing_notice_once()
  parent = c(PATH = "/owned-test/bin", ANTHROPIC_API_KEY = "FAKE-API",
    ANTHROPIC_PROFILE = "FAKE-PROFILE")
  child = billing_notice_child(parent)
  first = billing_notice_capture(child("cli-claude"))
  again = billing_notice_capture(child("cli-claude"))
  expect_s3_class(first$cnd, "gptr_message_billing_env")
  expect_null(again$cnd)
  expect_identical(again$out, character())
  expect_identical(again$value, first$value)
  changed = billing_notice_capture(child("cli-claude", pass = "ANTHROPIC_API_KEY"))
  expect_identical(changed$cnd$variables, "ANTHROPIC_PROFILE")
  expect_identical(changed$value[["ANTHROPIC_API_KEY"]], "FAKE-API")
  consent = billing_notice_capture(child("cli-claude", pass = names(parent)))
  expect_null(consent$cnd)
  expect_identical(consent$value[names(parent)], parent)
  explicit = billing_notice_capture(child("cli-claude",
    set = c(ANTHROPIC_API_KEY = "FAKE-EXPLICIT", ANTHROPIC_PROFILE = "FAKE-EXPLICIT-PROFILE")))
  expect_null(explicit$cnd)
  expect_identical(explicit$value[["ANTHROPIC_API_KEY"]], "FAKE-EXPLICIT")
  expect_identical(explicit$value[["ANTHROPIC_PROFILE"]], "FAKE-EXPLICIT-PROFILE")
})

test_that("billing notice preserves caller muffling and the explicit quiet-message policy", {
  local_gptr_options(quiet = FALSE)
  local_billing_notice_once()
  child = billing_notice_child(c(PATH = "/owned-test/bin", ANTHROPIC_API_KEY = "FAKE-CLAUDE",
    OPENAI_API_KEY = "FAKE-CODEX"))
  x = billing_notice_capture(child("cli-claude"), muffle = TRUE)
  expect_s3_class(x$cnd, "gptr_message_billing_env")
  expect_identical(x$cnd$variables, "ANTHROPIC_API_KEY")
  expect_identical(x$out, character())
  expect_identical(x$err, character())
  local_gptr_options(quiet = TRUE)
  quiet = billing_notice_capture(child("cli-codex"))
  expect_null(quiet$cnd)
  expect_identical(quiet$out, character())
  expect_identical(quiet$warnings, list())
  expect_false("OPENAI_API_KEY" %in% names(quiet$value))
  local_gptr_options(quiet = FALSE)
  shown = billing_notice_capture(child("cli-codex"))
  expect_s3_class(shown$cnd, "gptr_message_billing_env")
  expect_identical(shown$value, quiet$value)
})

test_that("billing notices preserve protocol stdout reservation and genuine warning semantics", {
  local_gptr_options(quiet = FALSE)
  local_billing_notice_once()
  child = billing_notice_child(c(PATH = "/owned-test/bin", OPENAI_API_KEY = "FAKE-CODEX"))
  protocol = function() {
    .gptr_message_stream = "stderr"
    force(.gptr_message_stream)
    child("cli-codex")
  }
  x = billing_notice_capture(protocol())
  expect_s3_class(x$cnd, "gptr_message_billing_env")
  expect_identical(x$out, character())
  expect_length(x$err, 1L)
  expect_match(x$err, "Removed OPENAI_API_KEY", fixed = TRUE)
  withr::local_options(warn = 2L)
  expect_error(gptr_warn("synthetic genuine warning", "synthetic"),
    "synthetic genuine warning", fixed = TRUE)
  expect_error(warning("synthetic package warning"), "synthetic package warning", fixed = TRUE)
  original = simpleError("synthetic genuine error")
  expect_identical(tryCatch(stop(original), error = identity), original)
  out = utils::capture.output({
    err = utils::capture.output(cat("SYNTHETIC-NATIVE-STDERR\n", file = stderr()),
      type = "message")
  })
  expect_identical(out, character())
  expect_identical(err, "SYNTHETIC-NATIVE-STDERR")
})
