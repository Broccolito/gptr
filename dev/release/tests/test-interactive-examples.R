# Read the real documentation, without sourcing either production implementation.
guard_examples_source = function(file, root) {
  lines = readLines(file.path(root, "R", file), warn = FALSE)
  start = which(grepl("^#' @examples", lines))
  stopifnot(length(start) == 1L)
  end = which(seq_along(lines) > start & lines == "#' @export")[[1L]]
  tag = sub("^#' ", "", lines[[start]])
  code = sub("^#' ?", "", lines[seq.int(start + 1L, end - 1L)])
  # Decode the original guard too, so baseline branch controls exercise its real predicate.
  if (startsWith(tag, "@examplesIf ")) {
    pred = sub("^@examplesIf ", "", tag)
    code = c(paste0("if (", pred, ") {"), code, "}")
  }
  list(tag = tag, code = code, exprs = parse(text = code, keep.source = FALSE))
}

test_that("login and MCP examples show their exact guards and original calls", {
  login = guard_examples_source("auth-oauth.R", gptr_root())
  mcp = guard_examples_source("mcp-server.R", gptr_root())
  expect_identical(login$tag, "@examples")
  expect_identical(mcp$tag, "@examples")
  expect_length(login$exprs, 1L)
  expect_length(mcp$exprs, 1L)
  login_expected = parse(text = c("if (interactive()) {",
    "gptr_login(\"openrouter\")", "gptr_logout(\"openrouter\")", "}"), keep.source = FALSE)
  mcp_expected = parse(text = c(
    "if (interactive() && rlang::is_installed(c(\"httpuv\", \"later\", \"openssl\"))) {",
    "h = gptr_mcp_serve(envir = new.env())", "h$config$codex", "gptr_mcp_serve(stop = TRUE)",
    "}"), keep.source = FALSE)
  expect_identical(login$exprs[[1L]], login_expected[[1L]])
  expect_identical(mcp$exprs[[1L]], mcp_expected[[1L]])
})

test_that("login example skips sign-in offline and keeps interactive call order", {
  ex = guard_examples_source("auth-oauth.R", gptr_root())
  run = function(human) {
    st = new.env(parent = emptyenv())
    st$calls = character()
    scope = new.env(parent = baseenv())
    scope$interactive = function() human
    scope$gptr_login = function(provider) {
      st$calls = c(st$calls, paste0("login:", provider))
      invisible(TRUE)
    }
    scope$gptr_logout = function(provider) {
      st$calls = c(st$calls, paste0("logout:", provider))
      invisible(TRUE)
    }
    eval(ex$exprs, scope)
    st$calls
  }
  expect_identical(run(FALSE), character())
  expect_identical(run(TRUE), c("login:openrouter", "logout:openrouter"))
})

test_that("MCP example skips listeners unless both exact prerequisites hold", {
  ex = guard_examples_source("mcp-server.R", gptr_root())
  run = function(human, installed) {
    st = new.env(parent = emptyenv())
    st$calls = character()
    st$checks = 0L
    testthat::local_mocked_bindings(is_installed = function(pkgs) {
      expect_identical(pkgs, c("httpuv", "later", "openssl"))
      st$checks = st$checks + 1L
      installed
    }, .package = "rlang")
    scope = new.env(parent = baseenv())
    scope$interactive = function() human
    scope$gptr_mcp_serve = function(envir = NULL, stop = FALSE) {
      if (stop) {
        expect_null(envir)
        st$calls = c(st$calls, "stop")
        return(invisible(NULL))
      }
      expect_true(is.environment(envir))
      expect_identical(parent.env(envir), scope)
      st$calls = c(st$calls, "start")
      list(config = list(codex = "controlled redacted configuration"))
    }
    eval(ex$exprs, scope)
    list(calls = st$calls, checks = st$checks,
         config = if (exists("h", envir = scope, inherits = FALSE)) scope$h$config$codex else NULL)
  }
  expect_identical(run(FALSE, FALSE), list(calls = character(), checks = 0L, config = NULL))
  expect_identical(run(FALSE, TRUE), list(calls = character(), checks = 0L, config = NULL))
  expect_identical(run(TRUE, FALSE), list(calls = character(), checks = 1L, config = NULL))
  expect_identical(run(TRUE, TRUE),
                   list(calls = c("start", "stop"), checks = 1L,
                        config = "controlled redacted configuration"))
})

test_that("release policy accepts visible guarded pages and requires honest guard wording", {
  login = guard_examples_source("auth-oauth.R", gptr_root())
  mcp = guard_examples_source("mcp-server.R", gptr_root())
  dir = toy_man(list(
    gptr_login = rd_page("gptr_login", aliases = c("gptr_login", "gptr_logout"),
                         examples = login$code),
    gptr_mcp_serve = rd_page("gptr_mcp_serve", examples = mcp$code)
  ))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_identical(rel_example_exceptions(), c("gptr_login", "gptr_mcp_serve"))
  expect_identical(docs_problems(rd_read_dir(dir),
    exports = c("gptr_login", "gptr_logout", "gptr_mcp_serve"),
    groups = list(gptr_login = c("gptr_login", "gptr_logout")), topics = list()), character())
  lines = readLines(file.path(gptr_root(), "cran-comments.md"), warn = FALSE)
  expect_identical(cran_comments_problems(lines), character())
  without_guard = gsub("visible `if` guards", "", lines, fixed = TRUE)
  expect_true("cran-comments.md: must mention visible `if` guards" %in%
                cran_comments_problems(without_guard))
})
