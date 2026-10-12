# Protocol acceptance only. Utility death is proved outside this protocol.
token_trial_line = function(line, seen = character()) {
  reject = function() stop("Invalid owned-token diagnostic", call. = FALSE)
  phases = c("A1", "B", "A2")
  keys = c("BACKUP", "RESTORE", "CHANGE_NOTIFY", "FILE_LOOKUP", "PARENT_LOOKUP",
           "PROBE", "TOKEN_EXACT", "ACL_EXACT")
  expected = paste(rep(phases, each = length(keys)), rep(keys, times = length(phases)))
  expected = c(expected, "END TOKEN_RESTORED", "END HANDLE_CLOSED")
  if (!is.character(line) || length(line) != 1L || is.na(line) ||
      nchar(line, type = "bytes") > 96L) reject()
  if (!startsWith(line, "GPTR_TOKEN")) return(NULL)
  if (!is.character(seen) || anyNA(seen) || length(seen) >= length(expected) ||
      !identical(seen, expected[seq_along(seen)]) ||
      !grepl("^GPTR_TOKEN (A1|B|A2|END) [A-Z_]+ [1-4]$", line)) reject()
  fields = strsplit(sub("^GPTR_TOKEN ", "", line), " ", fixed = TRUE)[[1L]]
  key = paste(fields[[1L]], fields[[2L]])
  if (!identical(key, expected[[length(seen) + 1L]])) reject()
  value = as.integer(fields[[3L]])
  if (fields[[2L]] %in% keys[seq_len(3L)]) {
    wanted = if (fields[[1L]] == "B") 1L else 2L
    if (value != wanted) reject()
  } else if (fields[[2L]] %in% c("FILE_LOOKUP", "PARENT_LOOKUP", "PROBE")) {
    if (!value %in% 1:2) reject()
  } else if (value != 1L) {
    reject()
  }
  list(key = key, value = value, label = paste0("token-", tolower(gsub(" ", "-", key)),
    "-", value))
}

token_trial_decode = function(lines) {
  reject = function() stop("Invalid owned-token diagnostic", call. = FALSE)
  phases = c("A1", "B", "A2")
  keys = c("BACKUP", "RESTORE", "CHANGE_NOTIFY", "FILE_LOOKUP", "PARENT_LOOKUP",
           "PROBE", "TOKEN_EXACT", "ACL_EXACT")
  expected = paste(rep(phases, each = length(keys)), rep(keys, times = length(phases)))
  expected = c(expected, "END TOKEN_RESTORED", "END HANDLE_CLOSED")
  if (!is.character(lines) || length(lines) != length(expected) || anyNA(lines) ||
      any(nchar(lines, type = "bytes") > 96L) ||
      any(!grepl("^GPTR_TOKEN (A1|B|A2|END) [A-Z_]+ [1-4]$", lines))) reject()
  fields = strsplit(sub("^GPTR_TOKEN ", "", lines), " ", fixed = TRUE)
  names = vapply(fields, function(x) paste(x[[1L]], x[[2L]]), "")
  values = vapply(fields, function(x) as.integer(x[[3L]]), 1L)
  if (!identical(names, expected)) reject()
  records = matrix(values[seq_len(24L)], nrow = 3L, byrow = TRUE,
                   dimnames = list(phases, keys))
  # Admit only a real enabled -> disabled -> original-enabled intervention.
  target_states = matrix(c(rep(2L, 3L), rep(1L, 3L), rep(2L, 3L)), nrow = 3L,
                         byrow = TRUE)
  if (!identical(unname(records[, seq_len(3L), drop = FALSE]), target_states) ||
      any(records[, c("FILE_LOOKUP", "PARENT_LOOKUP")] > 2L) ||
      any(records[, "PROBE"] > 2L) ||
      any(records[, c("TOKEN_EXACT", "ACL_EXACT")] != 1L) ||
      any(utils::tail(values, 2L) != 1L)) reject()
  group_contribution = all(records["A1", c("FILE_LOOKUP", "PARENT_LOOKUP", "PROBE")] == 2L) &&
    all(records["B", c("FILE_LOOKUP", "PARENT_LOOKUP", "PROBE")] == 1L) &&
    all(records["A2", c("FILE_LOOKUP", "PARENT_LOOKUP", "PROBE")] == 2L)
  list(records = records, group_contribution = group_contribution,
       individual_privilege_identified = FALSE, feature_accepted = FALSE)
}
