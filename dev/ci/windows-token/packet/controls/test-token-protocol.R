# These are unexecuted pure protocol controls, not native token/ACL proof.
# The nominated runner must source token-protocol.R into a private test environment.
token_trial_fixture = function() {
  phases = c("A1", "B", "A2")
  keys = c("BACKUP", "RESTORE", "CHANGE_NOTIFY", "FILE_LOOKUP", "PARENT_LOOKUP",
           "PROBE", "TOKEN_EXACT", "ACL_EXACT")
  state = rbind(c(2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L),
                c(1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L),
                c(2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L))
  lines = paste("GPTR_TOKEN", rep(phases, each = length(keys)),
                rep(keys, times = length(phases)), as.vector(t(state)))
  c(lines, "GPTR_TOKEN END TOKEN_RESTORED 1", "GPTR_TOKEN END HANDLE_CLOSED 1")
}

test_that("owned token evidence requires a closed nonvacuous A-B-A sequence", {
  x = token_trial_decode(token_trial_fixture())
  expect_identical(dim(x$records), c(3L, 8L))
  expect_true(x$group_contribution)
  expect_false(x$individual_privilege_identified)
  expect_false(x$feature_accepted)
})

test_that("owned token evidence refuses missing duplicate and reordered records", {
  x = token_trial_fixture()
  for (i in seq_along(x)) {
    expect_error(token_trial_decode(x[-i]), "Invalid owned-token diagnostic", fixed = TRUE)
    expect_error(token_trial_decode(c(x, x[[i]])),
                 "Invalid owned-token diagnostic", fixed = TRUE)
  }
  expect_error(token_trial_decode(x[c(2L, 1L, seq.int(3L, length(x)))]),
               "Invalid owned-token diagnostic", fixed = TRUE)
})

test_that("owned token evidence rejects arbitrary fields values and private text", {
  x = token_trial_fixture()
  for (bad in c("GPTR_TOKEN A1 SID 2", "GPTR_TOKEN A1 BACKUP 0",
    "GPTR_TOKEN A1 BACKUP 02", "GPTR_TOKEN A1 BACKUP NaN",
    "GPTR_TOKEN A1 BACKUP 2 ", "GPTR_TOKEN A1 BACKUP 2\r",
    "GPTR_TOKEN A1 BACKUP 2 PRIVATE-CANARY", strrep("X", 97L), NA_character_)) {
    y = x; y[[1L]] = bad
    expect_error(token_trial_decode(y), "Invalid owned-token diagnostic", fixed = TRUE)
  }
  for (bad in list(NULL, character(), list(x), c(x, x))) {
    expect_error(token_trial_decode(bad), "Invalid owned-token diagnostic", fixed = TRUE)
  }
})

test_that("owned token evidence refuses ineffective adjustment or uncertain restoration", {
  x = token_trial_fixture()
  for (i in c(1:3, 9:11, 17:19, 7:8, 15:16, 23:26)) {
    y = x
    old = sub(".* ", "", y[[i]])
    y[[i]] = sub(" [1-4]$", if (old == "1") " 2" else " 1", y[[i]])
    expect_error(token_trial_decode(y), "Invalid owned-token diagnostic", fixed = TRUE)
  }
  for (i in c(4:6, 12:14, 20:22)) {
    y = x; y[[i]] = sub(" [1-4]$", " 3", y[[i]])
    expect_error(token_trial_decode(y), "Invalid owned-token diagnostic", fixed = TRUE)
  }
})

test_that("unchanged denial outcomes do not identify a token contribution", {
  x = token_trial_fixture()
  x[12:14] = sub(" 1$", " 2", x[12:14])
  result = token_trial_decode(x)
  expect_false(result$group_contribution)
  expect_false(result$feature_accepted)
  x = token_trial_fixture()
  x[4:6] = sub(" 2$", " 1", x[4:6])
  expect_false(token_trial_decode(x)$group_contribution)
})

test_that("owned token streaming admission keeps every exact record in order", {
  lines = token_trial_fixture()
  seen = character()
  for (line in lines) {
    result = token_trial_line(line, seen)
    expect_type(result$value, "integer")
    seen = c(seen, result$key)
  }
  expect_length(seen, 26L)
  expect_null(token_trial_line("GPTR_ABSENCE_STAGE 7"))
  expect_error(token_trial_line(lines[[1L]], seen), "Invalid owned-token diagnostic",
    fixed = TRUE)
})

test_that("owned token streaming rejects unknown failure and ineffective state", {
  lines = token_trial_fixture()
  for (line in c("GPTR_TOKEN_FAILURE 1", "GPTR_TOKEN A1 BACKUP 1",
      "GPTR_TOKEN A1 BACKUP 0", "GPTR_TOKEN A1 BACKUP 02", "GPTR_TOKEN A1 SID 2",
      "GPTR_TOKEN A1 BACKUP 2 PRIVATE-CANARY", strrep("X", 97L))) {
    expect_error(token_trial_line(line), "Invalid owned-token diagnostic", fixed = TRUE)
  }
  expect_error(token_trial_line(lines[[2L]]), "Invalid owned-token diagnostic", fixed = TRUE)
})
