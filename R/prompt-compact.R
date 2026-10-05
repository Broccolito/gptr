# Compaction: the threshold and the cold rule, the in-conversation checkpoint request, harness
# state extraction and the compaction entry (P07). Adapted from G4 section 5.5 (compaction.R):
# the checkpoint prompt is G4 section 3.6 verbatim; the harness, not the model, writes the
# user's messages, the objects with their creating code, decisions, files, skills and the plan.
# keep_recent = 0: the compaction entry replaces everything before it.

#' Compaction threshold (contract section 7.7; architecture section 6.11)
#'
#' @param window Context window in tokens (`NA`: unknown).
#' @param max_output Maximum output tokens of the model (`NA` counts as 0).
#' @param r_cap The `r` result budget (`gptr.r_output_tokens`).
#' @return `num(1)`: `min(window - min(max(30000, 0.10 * window), 0.25 * window), window -
#'   max(16384, max_output + 2 * r_cap), compact_at)`, where `compact_at` is the setting
#'   `compact_at` read through `setting_get()` (without P08's settings service: the option
#'   `gptr.compact_at`, default 200000). Settings are process-wide (contract 5:
#'   `gptr_config(.scope = "session")` is this R process), so no session is passed. A `null`
#'   setting disables the cap (contract 3.1 and 11.2: `num|null`); R options cannot hold `NULL`,
#'   so `Inf` or `NA` in the option disables it too. An unknown window gives the cap alone.
#' @noRd
compact_threshold = function(window, max_output, r_cap = 4000) {
  cap = setting_get("compact_at")
  cap = if (is.null(cap) || !length(cap) || is.na(cap[[1]])) Inf else as.numeric(cap[[1]])
  if (is.null(window) || !length(window) || is.na(window)) return(cap)
  mo = if (is.null(max_output) || !length(max_output) || is.na(max_output)) 0 else max_output
  min(window - min(max(30000, 0.10 * window), 0.25 * window),
      window - max(16384, mo + 2 * r_cap), cap)
}

# ---- harness state (G4 sections 4.4.2-4.4.3) ----------------------------------------------------

#' Names assigned by top-level expressions and the code that assigned them
#'
#' Handles `=`, the left arrow, the super-assignment arrow, `->` (parsed as the left arrow),
#' `assign("x", ...)`, replacement calls (`x$a = ...`, `names(x) = ...`) and data.table
#' `x[, y := ...]` (G4 section 5.5).
#'
#' @param code `chr(1)` R code.
#' @return Named list: object name -> the code as written (at most 100 characters), oldest
#'   assignment first (a name assigned again takes the newest place and code).
#' @noRd
compact_assigned_names = function(code) {
  exprs = tryCatch(parse(text = code, keep.source = TRUE), error = function(e) expression())
  src = lapply(attr(exprs, "srcref"), as.character)
  ops = c("=", paste0("<", "-"), paste0("<<", "-"))
  base_sym = function(e) {
    while (is.call(e)) e = e[[2]]
    if (is.symbol(e)) as.character(e) else NA_character_
  }
  out = list()
  for (i in seq_along(exprs)) {
    ex = exprs[[i]]
    nm = NA_character_
    if (is.call(ex)) {
      f = as.character(ex[[1]])[1]
      walrus = identical(f, "[") && length(ex) >= 4L && is.call(ex[[4]]) &&
        identical(as.character(ex[[4]][[1]]), ":=")
      if (f %in% ops || walrus) {
        nm = base_sym(ex[[2]])
      } else if (identical(f, "assign") && length(ex) >= 2L && is.character(ex[[2]])) {
        nm = ex[[2]]
      }
    }
    if (!is.na(nm)) {
      line = paste(trimws(src[[i]]), collapse = " ")
      code = if (nchar(line) > 100L) paste0(substr(line, 1L, 97L), "...") else line
      out = compact_object_set(out, nm, code)
    }
  }
  out
}

#' An empty harness state
#' @noRd
compact_state_empty = function() {
  list(user = character(), objects = list(), decisions = character(), read = character(),
       modified = character(), skills = character(), plan = NULL)
}

#' Record an assignment: the name takes the newest place, so lists stay oldest first
#' @noRd
compact_object_set = function(objs, nm, code) {
  objs[[nm]] = NULL
  objs[[nm]] = code
  objs
}

#' Merge a previous checkpoint's state `b` under the newer state `a`
#'
#' Every list stays oldest first (`b`'s entries, then `a`'s), so the budgets of the checkpoint
#' drop the oldest objects first; an object assigned again in `a` keeps `a`'s code. `b` may come
#' from the session file (JSON arrays read back as lists, a single string unboxed).
#' @noRd
compact_state_merge = function(a, b) {
  if (is.null(b)) return(a)
  a$user = c(as.character(unlist(b$user)), a$user)
  a$decisions = c(as.character(unlist(b$decisions)), a$decisions)
  objs = list()
  for (nm in names(b$objects)) {
    objs = compact_object_set(objs, nm, as.character(unlist(b$objects[[nm]])))
  }
  for (nm in names(a$objects)) objs = compact_object_set(objs, nm, a$objects[[nm]])
  a$objects = objs
  a$read = union(as.character(unlist(b$read)), a$read)
  a$modified = union(as.character(unlist(b$modified)), a$modified)
  a$read = setdiff(a$read, a$modified)
  a$skills = union(as.character(unlist(b$skills)), a$skills)
  # `[<-` with list(): `$<-` with NULL would drop the field (contract 7.7 lists all seven)
  a["plan"] = list(a$plan %||% b$plan)
  a
}

#' Harness state for the checkpoint (contract section 7.7)
#'
#' Files and skills come from the assistant's `read`, `write` and `edit` calls (and from
#' `skill_content` blocks), in transcript order; a call whose result (same `tool_call_id`) is an
#' error (failed, denied, blocked or not executed) contributes nothing. A call without a result
#' counts.
#'
#' @param entries Entries of the active path (R shape), root to leaf.
#' @return `list(user, objects, decisions, read, modified, skills, plan)`: the user's messages
#'   (prompts and steering, in order), objects assigned by successful `r` calls with their code
#'   (oldest assignment first: an object assigned again moves to the end), `note` decisions,
#'   files read and modified, active skills and the latest complete proposed plan, merged with
#'   the state of the latest compaction entry (iterative compaction).
#' @noRd
extract_state = function(entries) {
  is_cmp = vapply(entries, function(e) identical(e$type, "compaction"), NA)
  start = 1L
  prev = NULL
  if (any(is_cmp)) {
    k = max(which(is_cmp))
    prev = entries[[k]]$gptr$state
    start = k + 1L
  }
  st = compact_state_empty()
  user_sources = c("prompt", "pipe", "steer", "follow_up", "repl", "parent", "replay",
                   "imported")
  relay = "^The user sent this message while you were working: "
  plan_re = "(?s)<proposed_plan>.*</proposed_plan>"
  file_kinds = c(read = "read", write = "modified", edit = "modified")
  # file and skill operations in transcript order; a call stays open until its result arrives
  f_id = character()
  f_what = character()
  f_value = character()
  f_open = logical()
  f_ok = logical()
  todo = if (start <= length(entries)) entries[start:length(entries)] else list()
  for (e in todo) {
    # steering relays: the session kernel's shape (P06) and the flat Pi shape
    op = prompt_entry_operator(e)
    if (!is.null(op)) {
      if (identical(op$kind, "steer_relay")) {
        st$user = c(st$user, op$origin_text %||% sub(relay, "", prompt_operator_text(op)))
      }
      next
    }
    if (!identical(e$type, "message")) next
    m = e$message
    if (identical(m$role, "user")) {
      txt = msg_text(m)
      if (nzchar(txt) && isTRUE((m$source %||% "prompt") %in% user_sources)) {
        st$user = c(st$user, txt)
      }
      for (b in m$content) {
        nm = b$attrs$name
        if (identical(b$type, "context") && identical(b$kind, "skill_content") &&
            is.character(nm) && length(nm) == 1L) {
          f_id = c(f_id, NA_character_)
          f_what = c(f_what, "skills")
          f_value = c(f_value, nm)
          f_open = c(f_open, FALSE)
          f_ok = c(f_ok, TRUE)
        }
      }
    } else if (identical(m$role, "assistant")) {
      for (b in m$content) {
        if (identical(b$type, "tool_call")) {
          p = b$arguments$path
          what = if (is.character(b$name) && length(b$name) == 1L) file_kinds[b$name] else NA
          what = unname(what)
          if (!is.na(what) && is.character(p) && length(p) == 1L && !is.na(p)) {
            if (identical(what, "read") && startsWith(p, "skill:")) {
              what = "skills"
              p = sub("^skill:([^/]+).*$", "\\1", p)
            }
            f_id = c(f_id, as.character(b$id %||% NA_character_))
            f_what = c(f_what, what)
            f_value = c(f_value, p)
            f_open = c(f_open, TRUE)
            f_ok = c(f_ok, TRUE)
          }
        }
        if (identical(b$type, "text") && grepl(plan_re, b$text, perl = TRUE)) {
          st$plan = sub("(?s).*(<proposed_plan>.*</proposed_plan>).*", "\\1", b$text, perl = TRUE)
        }
      }
    } else if (identical(m$role, "tool_result")) {
      id = m$tool_call_id
      if (is.character(id) && length(id) == 1L) {
        hit = which(f_open & !is.na(f_id) & f_id == id)
        f_open[hit] = FALSE
        f_ok[hit] = !isTRUE(m$is_error)
      }
      if (!identical(m$tool_name, "r") || isTRUE(m$is_error)) next
      dt = m$details
      ok = is.null(dt$status) || identical(dt$status, "ok")
      if (ok && is.character(dt$code)) {
        a = compact_assigned_names(dt$code)
        for (nm in names(a)) st$objects = compact_object_set(st$objects, nm, a[[nm]])
      }
      if (is.character(dt$note) && nzchar(dt$note)) st$decisions = c(st$decisions, dt$note)
    }
  }
  for (what in c("read", "modified", "skills")) {
    st[[what]] = unique(f_value[f_ok & f_what == what])
  }
  st$read = setdiff(st$read, st$modified)
  compact_state_merge(st, prev)
}

#' Cut one text to `budget` estimated tokens, the truncation notice included
#'
#' Keeps the head of the text. A single long line is cut by characters (`prompt_truncate()`
#' keeps whole lines only, so it would drop a one-line text entirely). `prefix` (a list marker)
#' is counted but not returned.
#' @noRd
compact_clip = function(text, budget, prefix = "") {
  if (prompt_est(paste0(prefix, text)) <= budget) return(text)
  notice = sprintf(prompt_text("block_truncated"), as.integer(max(0, floor(budget))))
  lo = 0L
  hi = nchar(text)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (prompt_est(paste0(prefix, substr(text, 1L, mid), "\n", notice)) <= budget) {
      lo = mid
    } else {
      hi = mid - 1L
    }
  }
  paste0(sub("\\s+$", "", substr(text, 1L, lo)), "\n", notice)
}

#' Estimated tokens of a line of a list: its estimate plus its line feed
#'
#' The sum over lines bounds the estimate of the joined list (the estimate rounds up per text).
#' @noRd
compact_line_cost = function(x) prompt_est(x) + 1

#' The user's messages within a token budget: the first and the newest, then the newest that fit
#'
#' The whole list, line numbers and the omission line included, stays within `budget`
#' (architecture 12.2: user messages 2,000). When the first and the newest message do not fit
#' together, they are cut to shares of the budget (`compact_clip()`): a message within half the
#' budget stays whole and the other takes the rest, else each gets half.
#' @noRd
compact_user_messages = function(msgs, budget = 2000) {
  n = length(msgs)
  if (!n) return("(none)")
  lines = sprintf("%d. %s", seq_len(n), msgs)
  if (prompt_est(lines) <= budget) return(paste(lines, collapse = "\n"))
  omitted = function(k) sprintf("(%d earlier messages omitted)", k)
  avail = budget - if (n > 2L) compact_line_cost(omitted(n - 2L)) else 0
  ends = unique(c(1L, n))
  need = vapply(lines[ends], compact_line_cost, 0, USE.NAMES = FALSE)
  if (sum(need) > avail) {
    half = avail / length(ends)
    share = if (length(ends) == 1L) {
      avail
    } else if (need[1] <= half) {
      c(need[1], avail - need[1])
    } else if (need[2] <= half) {
      c(avail - need[2], need[2])
    } else {
      c(half, half)
    }
    for (j in seq_along(ends)) {
      prefix = sprintf("%d. ", ends[j])
      lines[ends[j]] = paste0(prefix, compact_clip(msgs[ends[j]], share[j] - 1, prefix))
    }
  }
  used = sum(vapply(lines[ends], compact_line_cost, 0, USE.NAMES = FALSE))
  keep = n
  while (keep > 2L && used + compact_line_cost(lines[keep - 1L]) <= avail) {
    keep = keep - 1L
    used = used + compact_line_cost(lines[keep])
  }
  out = lines[unique(c(1L, keep:n))]
  if (keep > 2L) out = append(out, omitted(keep - 2L), after = 1L)
  paste(out, collapse = "\n")
}

#' The `note` decisions within a token budget: the newest that fit, the oldest dropped first
#'
#' The newest decision is always shown, cut to the budget when it alone exceeds it; dropped
#' decisions are counted in a leading line.
#' @noRd
compact_decisions = function(decisions, budget = 300) {
  n = length(decisions)
  if (!n) return("(none)")
  lines = paste0("- ", decisions)
  if (prompt_est(lines) <= budget) return(paste(lines, collapse = "\n"))
  omitted = function(k) sprintf("(%d earlier decisions omitted)", k)
  avail = budget - if (n > 1L) compact_line_cost(omitted(n - 1L)) else 0
  if (compact_line_cost(lines[n]) > avail) {
    lines[n] = paste0("- ", compact_clip(decisions[n], avail - 1, "- "))
  }
  used = compact_line_cost(lines[n])
  keep = n
  while (keep > 1L && used + compact_line_cost(lines[keep - 1L]) <= avail) {
    keep = keep - 1L
    used = used + compact_line_cost(lines[keep])
  }
  out = lines[keep:n]
  if (keep > 1L) out = c(omitted(keep - 1L), out)
  paste(out, collapse = "\n")
}

#' Class and shape per object name from the session's last workspace snapshot (P09), if any
#'
#' P09's `env_snapshot()` never forces a promise or calls an active binding, so their rows have
#' no class (`NA`): those objects are left out (shown as `?`). A missing shape (`NA`) shows the
#' class alone.
#' @noRd
compact_shapes = function(s) {
  snap = if (is.null(s)) NULL else session_data(s)$snapshot
  if (!is.data.frame(snap) || !all(c("name", "class") %in% names(snap))) return(list())
  cls = as.character(snap$class)
  shape = if ("shape" %in% names(snap)) as.character(snap$shape) else rep("", nrow(snap))
  shape[is.na(shape)] = ""
  keep = !is.na(cls) & !is.na(snap$name)
  out = trimws(paste(cls[keep], shape[keep]))
  stats::setNames(as.list(out), as.character(snap$name[keep]))
}

#' One line per object, `name <class shape>: code`, oldest dropped first to fit the budget
#' @noRd
compact_objects = function(objs, shapes = list(), budget = 800) {
  if (!length(objs)) return("(none)")
  lines = vapply(names(objs), function(nm) {
    sh = shapes[[nm]] %||% "?"
    paste0(nm, " <", if (nzchar(sh)) sh else "?", ">: ", paste(objs[[nm]], collapse = " "))
  }, "")
  while (length(lines) > 1L && prompt_est(lines, "code") > budget) lines = lines[-1L]
  paste(unname(lines), collapse = "\n")
}

#' The body of the <checkpoint> block (G4 section 3.6)
#' @noRd
compact_checkpoint_body = function(summary, st, shapes = list()) {
  tag = function(name, body) paste0("<", name, ">\n", body, "\n</", name, ">")
  files = paste0("read: ", if (length(st$read)) paste(st$read, collapse = ", ") else "(none)",
                 "\nmodified: ",
                 if (length(st$modified)) paste(st$modified, collapse = ", ") else "(none)")
  paste0(prompt_text("checkpoint_intro"), "\n\n",
         tag("summary", trimws(summary)), "\n\n",
         tag("user_messages", compact_user_messages(st$user)), "\n\n",
         tag("r_objects", compact_objects(st$objects, shapes)), "\n\n",
         tag("decisions", compact_decisions(st$decisions)), "\n\n",
         tag("files", files),
         if (length(st$skills)) {
           paste0("\n\n", tag("active_skills", paste(st$skills, collapse = ", ")))
         },
         if (!is.null(st$plan)) paste0("\n\n", st$plan))
}
