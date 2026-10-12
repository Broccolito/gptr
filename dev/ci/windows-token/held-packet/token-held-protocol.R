# State admission only. Existing executor independently proves utility death.
token_held_line = function(line, seen = character()) {
  reject = function() stop("Invalid held-token diagnostic", call. = FALSE)
  expected = c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY", "B TOKEN_EXACT",
    "END BODY", "END TOKEN_RESTORED", "END HANDLE_CLOSED")
  if (!is.character(line) || length(line) != 1L || is.na(line) ||
      nchar(line, type = "bytes") > 96L) reject()
  if (!startsWith(line, "GPTR_HELD")) return(NULL)
  if (!is.character(seen) || anyNA(seen) || length(seen) >= length(expected) ||
      !identical(seen, expected[seq_along(seen)]) ||
      !grepl("^GPTR_HELD (B|END) [A-Z_]+ 1$", line)) reject()
  key = sub(" 1$", "", sub("^GPTR_HELD ", "", line))
  if (!identical(key, expected[[length(seen) + 1L]])) reject()
  list(key = key, value = 1L, label = line)
}

token_held_decode = function(lines) {
  expected = c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY", "B TOKEN_EXACT",
    "END BODY", "END TOKEN_RESTORED", "END HANDLE_CLOSED")
  stopifnot(is.character(lines), length(lines) == length(expected), !anyNA(lines))
  seen = character()
  for (line in lines) {
    record = token_held_line(line, seen)
    stopifnot(is.list(record))
    seen = c(seen, record$key)
  }
  list(disabled_exact = TRUE, body_finished = TRUE, restored_exact = TRUE,
    handle_closed = TRUE, individual_privilege_identified = FALSE,
    restored_privilege_denial_proved = FALSE)
}
