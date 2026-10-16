test_that("held-token protocol admits only the exact completed utility window", {
  records = paste("GPTR_HELD", c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY",
    "B TOKEN_EXACT", "END BODY", "END TOKEN_RESTORED", "END HANDLE_CLOSED"), "1")
  seen = character()
  for (line in records) {
    value = token_held_line(line, seen)
    expect_type(value, "list")
    expect_identical(value$value, 1L)
    seen = c(seen, value$key)
  }
  decoded = token_held_decode(records)
  expect_true(decoded$disabled_exact)
  expect_true(decoded$body_finished)
  expect_true(decoded$restored_exact)
  expect_true(decoded$handle_closed)
  expect_false(decoded$individual_privilege_identified)
  expect_false(decoded$restored_privilege_denial_proved)
  expect_null(token_held_line("GPTR_ABSENCE_STAGE 4"))
})

test_that("held-token protocol rejects ineffective missing and conflicting proofs", {
  records = paste("GPTR_HELD", c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY",
    "B TOKEN_EXACT", "END BODY", "END TOKEN_RESTORED", "END HANDLE_CLOSED"), "1")
  before = serialize(records, NULL, version = 2)
  for (i in seq_along(records)) {
    changed = records
    changed[[i]] = sub(" 1$", " 2", changed[[i]])
    expect_error(token_held_decode(changed))
    expect_error(token_held_decode(records[-i]))
    changed = records
    changed[[i]] = "GPTR_HELD END UNKNOWN 1"
    expect_error(token_held_decode(changed))
  }
  expect_error(token_held_decode(rev(records)))
  expect_error(token_held_decode(c(records, records[[1L]])))
  expect_error(token_held_line(records[[2L]], character()))
  expect_error(token_held_line(records[[1L]], "PRIVATE"))
  expect_error(token_held_line(paste0(records[[1L]], strrep(" ", 97L))))
  expect_error(token_held_line(NA_character_))
  expect_error(token_held_decode(list(records)))
  expect_identical(serialize(records, NULL, version = 2), before)
})
