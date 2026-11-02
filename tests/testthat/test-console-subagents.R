test_that("a terminal fanout keeps its roster, phases and the parent's composer", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 80L)",
    "kid = gptr_fake_provider(function(req) {",
    "  if (!length(req$last_results)) return(list(tool = 'r',",
    "    input = list(code = 'Sys.sleep(2); 1L')))",
    "  list(text = 'PRIVATE-CHILD-REPORT', delay = 4)",
    "}, name = 'kid')",
    "fake = gptr_fake_provider(function(req) {",
    "  if (req$n == 1L) return(list(tool = 'r', input = list(code = paste0(",
    "    'fan = peter(\"each\", list(alpha = 1, beta = 2, gamma = 3), ',",
    "    'model = kid, parallel = 2, .opts = list(backend = \"inline\")); 1L'))))",
    "  if (req$n > 2L) return(paste0('NEXT [', req$last_user, ']'))",
    "  ops = Filter(function(m) identical(m$role, 'operator'), req$messages)",
    "  if (!length(ops)) return('PARENT MISSING STEER')",
    "  text = sub('^.*working: ', '', gptr:::msg_text(ops[[1L]]))",
    "  paste0('PARENT STEER [', text, ']')",
    "})",
    "main = peter(model = fake, mode = 'auto', envir = new.env())",
    "ops = sum(vapply(kid$log$requests, function(req) sum(vapply(req$messages,",
    "  function(m) identical(m$role, 'operator'), NA)), 0L))",
    "cat('CHILD OPERATORS ', ops, '\\n', sep = '')",
    "cat('ROW CLEARED ', is.null(gptr:::the$live_row), '\\n', sep = '')"
  ), term = "xterm")
  utf8 = l10n_info()[["UTF-8"]]
  person = if (utf8) "\u203a" else ">>"
  sep = if (utf8) " \u00b7 " else " - "
  expect_true(pty$wait("peter[auto]> ", timeout = 120))
  pty$send("ONE\r")
  expect_true(pty$wait(paste0("sub-agents 0/3 done", sep, "2 active", sep, "1 queued")))
  expect_true(pty$wait("active  alpha (kid/kid-1), beta (kid/kid-1)"))
  expect_true(pty$wait("queued  gamma (kid/kid-1)"))
  expect_true(pty$wait("sub-agent alpha r"))
  expect_true(pty$wait("keys show when r returns"))
  # Typed during a child tool, then read while child models wait: it still steers the parent.
  pty$paste("use-median")
  expect_true(pty$wait(paste0(person, " use-median")))
  pty$send("\r")
  expect_true(pty$wait("1 queued"))
  pty$paste("next-draft")
  expect_true(pty$wait(paste0(person, " next-draft"), timeout = 5), info = pty$all)
  expect_true(pty$wait("PARENT STEER [use-median]", timeout = 20), info = pty$all)
  expect_true(pty$wait("peter[auto]> "))
  pty$send("\r")
  expect_true(pty$wait("NEXT [next-draft]", timeout = 5), info = pty$all)
  expect_true(pty$wait("peter[auto]> "))
  pty$send("/exit\r")
  expect_true(pty$wait("CHILD OPERATORS 0"))
  expect_true(pty$wait("ROW CLEARED TRUE"))
  expect_true(pty$wait("CHILD DONE"))
  expect_identical(pty$seen("PRIVATE-CHILD-REPORT"), 0L)
  expect_identical(pty$seen("PARENT STEER [use-median]"), 1L)
  expect_identical(pty$seen("NEXT [next-draft]"), 1L)
  rows = term_rows(pty$all)
  done = grep("sub-agent .* done", rows)
  expect_length(done, 3L)
  expect_true(any(grepl("sub-agents 2/3", rows, fixed = TRUE)))
})

test_that("a terminal direct fanout prints each report once and leaves no live row", {
  skip_on_cran()
  skip_on_os("windows")
  pty = local_pty_r(c(
    "options(gptr.interactive = TRUE, gptr.verbose = 2L, gptr.record = 'off',",
    "        gptr.history = FALSE, cli.num_colors = 1L, cli.width = 80L)",
    "kid = gptr_fake_provider(list(list(text = 'DIRECT-CHILD-REPORT', delay = 2)),",
    "                         name = 'direct-kid')"
  ), term = "xterm")
  expect_true(pty$wait("CHILD DONE", timeout = 120))
  expect_true(pty$wait("> "))
  # At R's actual prompt, so the normal autoprint path must display this visible result.
  pty$send(paste0("peter('each', list(alpha = 1, beta = 2, gamma = 3), model = kid, ",
                   "parallel = 2, mode = 'auto', .opts = list(backend = 'inline'))\r"))
  expect_true(pty$wait("active  alpha (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("beta (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("queued  gamma (direct-kid/direct-kid-1)"))
  expect_true(pty$wait("sub-agents 2/3"))
  expect_true(pty$wait("sub-agent gamma done (3/3)"))
  expect_true(pty$wait("DIRECT-CHILD-REPORT"))
  expect_true(pty$wait("> "))
  expect_identical(pty$seen("DIRECT-CHILD-REPORT"), 3L)
  expect_match(pty$all, "\r[^\r\n]*sub-agents 2/3[^\r\n]*\033\\[K")
  pty$send(paste0("cat('ROW CLEARED ', is.null(gptr:::the$live_row), '\\n', sep = ''); ",
                   "gptr:::reactor_pump(timeout = 1.2); cat('IDLE AGAIN\\n')\r"))
  expect_true(pty$wait("ROW CLEARED TRUE"))
  expect_true(pty$wait("IDLE AGAIN\r\n"))
  expect_false(grepl("sub-agents", pty$pending(), fixed = TRUE))
})
