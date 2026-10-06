# P07 Task 15: static prefix budgets and baselines (architecture 12.1 and 12.7; IC-67, IC-68).
# The composition uses the stand-ins of prefix-baseline.json for texts other plans own, so the
# figures are P07's composition of the measured architecture 7.3 texts (the T1 fixture is
# `<r_env>` plus the two built-in skills, 542 o200k tokens).

prefix_estimate = function(fr) {
  prompt_est(fr$tools_json, "json") + prompt_est(fr$t0, "prose") + prompt_est(fr$t1, "prose")
}

test_that("each preset's estimated prefix is within 5% of prefix-baseline.json", {
  pb = prefix_fixture()
  expect_setequal(names(pb$estimate), names(pb$cases))
  for (nm in names(pb$cases)) {
    est = prefix_estimate(compose_case(nm))
    base = pb$estimate[[nm]]
    expect_lte(abs(est - base) / base, 0.05, label = nm)
  }
})

test_that("the measured o200k baselines are the architecture 12.1 totals (IC-68)", {
  expect_identical(unlist(prefix_fixture()$preset),
                   c(minimal = 1262L, standard_core = 2335L, standard_all = 2813L,
                     standard_interactive = 2956L))
})

test_that("every section is within its budget", {
  st = prefix_fixture()$standins$sections
  budgets = vapply(st, function(x) as.numeric(x$budget), 0)
  names(budgets) = vapply(st, function(x) x$name, "")
  for (nm in c("minimal", "standard_all", "standard_interactive")) {
    fr = compose_case(nm)
    for (i in seq_len(nrow(fr$sections))) {
      sec = fr$sections$name[i]
      budget = registry_get("prompt_section", sec)$budget
      if (sec %in% names(budgets)) budget = budgets[[sec]]
      expect_lte(fr$sections$tokens[i], budget, label = paste(nm, sec))
    }
  }
  s = compose_case("standard_interactive")
  expect_lte(s$sections$tokens[s$sections$name == "r_performance"], 150)
  d = gptr_registry(diagnostics = TRUE)
  expect_false(any(grepl("was truncated", d$message, fixed = TRUE) &
                     grepl("Section '(preamble|tools|rules|r_session|r_performance|modes|context)'",
                           d$message)))
})

test_that("the standard composition is architecture 7.3 byte for byte (with stand-ins)", {
  rd = prefix_fixture()$expected$rendered
  fr = compose_case("standard_interactive")
  st = prefix_fixture()$standins$sections
  names(st) = vapply(st, function(x) x$name, "")
  s1 = function(x) gsub("{s1}", "jev", x, fixed = TRUE)
  t0 = paste(prompt_text("preamble"), rd$tools_standard_ask, rd$rules_standard, rd$r_session,
             wrap("r_performance", prompt_text("r_performance")),
             wrap("documents", s1(st$documents$text)), wrap("artifacts", st$artifacts$text),
             wrap("system1", s1(st$system1$text)), wrap("modes", prompt_text("modes")),
             wrap("context", prompt_text("context")), sep = "\n\n")
  expect_identical(fr$t0, t0)
  expect_identical(fr$t1, paste(wrap("skills", st$skills$text), wrap("r_env", st$r_env$text),
                                sep = "\n\n"))
})

test_that("the composed T0 and skills equal the text block of architecture 7.3", {
  p = test_path("..", "..", "dev", "spec", "03-architecture.md")
  skip_if_not(file.exists(p), "dev/ is not available (built package)")
  a = readLines(p, encoding = "UTF-8", warn = FALSE)
  i = grep("^### 7.3 The system prompt", a)
  s = which(a == "```text")
  s = s[s > i][1]
  e = which(a == "```")
  e = e[e > s][1]
  sp = a[(s + 1L):(e - 1L)]
  t0_end = which(sp == "</context>")
  sk = c(which(sp == "<skills>"), which(sp == "</skills>"))
  fr = compose_case("standard_interactive")
  jev = function(x) gsub("{s1}", "jev", x, fixed = TRUE)
  expect_identical(fr$t0, jev(paste(sp[1:t0_end], collapse = "\n")))
  expect_true(startsWith(fr$t1, paste(sp[sk[1]:sk[2]], collapse = "\n")))
})

test_that("no composed prompt or shipped skill mentions str( (IC-67)", {
  rx = "(^|[^A-Za-z0-9_.])str\\("
  for (nm in c("minimal", "standard_interactive")) {
    expect_false(grepl(rx, compose_case(nm)$t0), label = nm)
  }
  skills = system.file("gptr", "skills", package = "gptr")
  files = if (nzchar(skills)) {
    list.files(skills, "SKILL[.]md$", recursive = TRUE, full.names = TRUE)
  } else {
    character()
  }
  for (f in files) {
    expect_false(any(grepl(rx, readLines(f, warn = FALSE, encoding = "UTF-8"))), label = f)
  }
})
