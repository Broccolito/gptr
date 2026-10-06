# tests/testthat/test-copy-subagent.R -- copy safety of sub-agents (plan P19; architecture 6.4,
# 6.13; contract 6.5 "Copy-safety: [R1][R3] (elements are read in place)"; P19 acceptance 4).
# Each row runs in a fresh Rscript through P01's expect_no_copy(), which skips on CRAN and
# without capabilities("profmem"). The fake scripts are plain functions (the child process has
# no test helpers); mode auto lets the scripted r calls run without a human.

# Code that defines `fake`: answers with an r call running `code` once, then "done"
subagent_copy_fake = function(code) {
  paste0("fake = gptr_fake_provider(function(request) if (length(request$last_results)) ",
         "'done' else list(tool = 'r', input = list(code = ", deparse(code), ")))")
}

subagent_copy_setup = function(code, object = "big = runif(5e6)") {
  c(object, "options(gptr.mode = 'auto', gptr.quiet = TRUE)", subagent_copy_fake(code))
}

test_that("inline children read a 40 MB object at its address, without a copy", {
  expect_no_copy(
    setup = subagent_copy_setup("addr = rlang::obj_address(big); s = sum(big)"),
    action = c("team = peter('Read big', model = fake,",
               "            agents = list(a = agent(model = fake), b = agent(model = fake)))",
               "stopifnot(identical(team$a$envir$addr, rlang::obj_address(big)))",
               "stopifnot(identical(team$b$envir$s, sum(big)))"),
    label = "team of two inline agents reading big")
})

test_that("a child's write stays in its overlay; the caller's object is untouched", {
  expect_no_copy(
    setup = subagent_copy_setup("big[1] = -1; first = big[1]"),
    action = c("team = peter('Change big', model = fake, agents = list(a = agent(model = fake)))",
               "stopifnot(identical(team$a$envir$first, -1), big[1] != -1)"),
    label = "a child writing big")
})

test_that("code with <<- is denied in parallel runs and the object stays editable", {
  expect_no_copy(
    setup = subagent_copy_setup("big <<- 0"),
    action = c("team = peter('Overwrite big', model = fake,",
               "            agents = list(a = agent(model = fake), b = agent(model = fake)))",
               "stopifnot(length(big) == 5e6)"),
    label = "two children trying big <<- 0")
})

test_that("fan-out elements are read in place (contract 6.5 [R1][R3])", {
  expect_no_copy(
    setup = subagent_copy_setup("n = length(cohorts[[1]])",
                                object = "cohorts = list(A = runif(5e6), B = runif(10))"),
    action = "fan = peter('Summarise this cohort', cohorts, model = fake, parallel = 2)",
    edit = "cohorts$A[1] = 0", object = "cohorts$A",
    label = "fan-out over cohorts")
})

test_that("a team started in a function frame does not keep the frame [R2]", {
  expect_no_copy(
    setup = c(subagent_copy_setup("s = sum(x)"),
              paste("f = function(x) peter('Sum x', x, model = fake,",
                    "agents = list(a = agent(model = fake)))")),
    action = "team = f(big)",
    label = "team in a function frame")
})

test_that("gptr_parallel() members read in place", {
  expect_no_copy(
    setup = subagent_copy_setup("s = sum(big)"),
    action = c("team = gptr_parallel(a = peter('Sum big', big, model = fake, envir = globalenv()),",
               "                     b = peter('Sum big', big, model = fake,",
               "                               envir = globalenv()))"),
    label = "gptr_parallel() over big")
})
