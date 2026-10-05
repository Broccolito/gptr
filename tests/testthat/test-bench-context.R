# P07 Task 15: static prefix budgets and baselines (architecture 12.1 and 12.7; IC-67, IC-68).
# The composition uses the stand-ins of prefix-baseline.json for texts other plans own, so the
# figures are P07's composition of the measured architecture 7.3 texts (the T1 fixture is
# `<r_env>` plus the two built-in skills, 542 o200k tokens).

# The stand-in helpers (shared with test-prompt-sections.R and dev/bench/tokens/run.R), bound
# here by name: the lint's object_usage_linter cannot see names that source() defines.
standins_env = local({
  source(test_path("fixtures", "bench", "standins.R"), local = TRUE)
  environment()
})
prefix_fixture = standins_env$prefix_fixture
prompt_standins_register = standins_env$prompt_standins_register

bench_compose = function(name, .env = parent.frame()) {
  pb = prefix_fixture()
  cs = pb$cases[[name]]
  local_fake_provider(list("ok"), .env = .env)
  s = session_new("fake/fake-1", cs$mode, home = new.env(), preset = cs$preset)
  prompt_standins_register(pb$standins, session_data(s)$id, sections = unlist(cs$sections),
                           exclusive = TRUE)
  doc = if (isTRUE(cs$document)) list(path = file.path(project_root(), "analysis.R"), format = "R")
  prompt_compose(s, list(interactive = cs$human, doc = doc))
}

prefix_estimate = function(fr) {
  prompt_est(fr$tools_json, "json") + prompt_est(fr$t0, "prose") + prompt_est(fr$t1, "prose")
}

wrap = function(name, x) paste0("<", name, ">\n", x, "\n</", name, ">")

test_that("each preset's estimated prefix is within 5% of prefix-baseline.json", {
  pb = prefix_fixture()
  expect_setequal(names(pb$estimate), names(pb$cases))
  for (nm in names(pb$cases)) {
    est = prefix_estimate(bench_compose(nm))
    base = pb$estimate[[nm]]
    expect_lte(abs(est - base) / base, 0.05, label = nm)
  }
})

test_that("the measured o200k baselines are the architecture 12.1 totals (IC-68)", {
  expect_identical(unlist(prefix_fixture()$preset),
                   c(minimal = 1271L, standard_core = 2360L, standard_all = 2844L,
                     standard_interactive = 2987L))
})

test_that("every section is within its budget", {
  st = prefix_fixture()$standins$sections
  budgets = vapply(st, function(x) as.numeric(x$budget), 0)
  names(budgets) = vapply(st, function(x) x$name, "")
  for (nm in c("minimal", "standard_all", "standard_interactive")) {
    fr = bench_compose(nm)
    for (i in seq_len(nrow(fr$sections))) {
      sec = fr$sections$name[i]
      budget = registry_get("prompt_section", sec)$budget
      if (sec %in% names(budgets)) budget = budgets[[sec]]
      expect_lte(fr$sections$tokens[i], budget, label = paste(nm, sec))
    }
  }
  s = bench_compose("standard_interactive")
  expect_lte(s$sections$tokens[s$sections$name == "r_performance"], 150)
  d = gptr_registry(diagnostics = TRUE)
  expect_false(any(grepl("was truncated", d$message, fixed = TRUE) &
                     grepl("Section '(preamble|tools|rules|r_session|r_performance|modes|context)'",
                           d$message)))
})

test_that("the standard composition is architecture 7.3 byte for byte (with stand-ins)", {
  rd = prefix_fixture()$expected$rendered
  fr = bench_compose("standard_interactive")
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
  fr = bench_compose("standard_interactive")
  jev = function(x) gsub("{s1}", "jev", x, fixed = TRUE)
  expect_identical(fr$t0, jev(paste(sp[1:t0_end], collapse = "\n")))
  expect_true(startsWith(fr$t1, paste(sp[sk[1]:sk[2]], collapse = "\n")))
})

test_that("no composed prompt or shipped skill mentions str( (IC-67)", {
  rx = "(^|[^A-Za-z0-9_.])str\\("
  for (nm in c("minimal", "standard_interactive")) {
    expect_false(grepl(rx, bench_compose(nm)$t0), label = nm)
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
