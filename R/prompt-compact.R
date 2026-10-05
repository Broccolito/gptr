# Compaction: the threshold and cold rule, the in-conversation checkpoint request, harness state
# extraction and the compaction entry (P07; G4 5.5, checkpoint prompt G4 3.6). The harness, not
# the model, writes the user's messages, objects with their code, decisions, files, skills and
# the plan. keep_recent = 0: the compaction entry replaces everything before it.

#' Compaction threshold (contract section 7.7; architecture section 6.11)
#' The cap is setting `compact_at` (process-wide, contract 5: no session); null, `NA` or `Inf`
#' disables it (contract 11.2). An unknown window gives the cap alone.
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

#' Names assigned by top-level expressions -> their code (at most 100 characters), oldest first
#' Handles `=`, the arrows, `assign("x", ...)`, replacement calls and data.table `:=` (G4 5.5).
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

#' Merge a previous checkpoint's state `b` under the newer state `a`, every list oldest first
#' `b` may come from the session file (JSON arrays as lists); a `b` that is not a list is ignored.
#' @noRd
compact_state_merge = function(a, b) {
  if (is.null(b) || !is.list(b)) return(a)
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

#' The sources of the user messages that count as the user's requests (`extract_state()`, and
#' the latest request the continuation line repeats)
#' @noRd
compact_user_sources = c("prompt", "pipe", "steer", "follow_up", "repl", "parent", "replay",
                         "imported")

#' Harness state for the checkpoint (contract 7.7), merged with the latest compaction's state
#' Files and skills come from `read`/`write`/`edit` calls and `skill_content` blocks in order; a
#' call whose result is an error contributes nothing (one without a result counts).
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
      if (nzchar(txt) && isTRUE((m$source %||% "prompt") %in% compact_user_sources)) {
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
#' Keeps the head, cut by characters (`prompt_truncate()` would drop a one-line text); `prefix` is
#' counted, not returned.
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

#' Estimated tokens of a list line plus its line feed (the sum bounds the joined list's estimate)
#' @noRd
compact_line_cost = function(x) prompt_est(x) + 1

#' The user's messages within a token budget: the first and the newest, then the newest that fit
#' (architecture 12.2). Ends that do not fit are clipped: one within half the budget stays whole
#' and the other takes the rest, else each gets half.
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
#' The newest is always shown (clipped if needed); a leading line counts the dropped ones.
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
#' Rows without a class (unforced promises, active bindings) are left out (shown as `?`).
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

# ---- trigger ------------------------------------------------------------------------------------

#' The model record compaction runs against, or NULL when none resolves
#' The run's resolved model (P06 routed at the boundary, IC-69); a router session asks
#' `router.call` on `"overflow"` or without a run model; others resolve through the catalog.
#' @noRd
compact_target = function(s, reason = NULL) {
  ref = session_data(s)$model
  router = is.character(ref) && length(ref) == 1L && !is.na(ref) && startsWith(ref, "router:")
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  m = if (is.environment(run)) run$model else NULL
  have = is.list(m) && !is.null(m[["api"]]) && (router || identical(run$model_key, ref))
  if (router && (!have || identical(reason, "overflow"))) {
    rec = compact_route(s)
    if (!is.null(rec)) return(rec)
  }
  if (have) return(m)
  if (router) return(NULL)
  prompt_model(ref)
}

#' The model record the session's router gives for a compaction (`router.call`, reason
#' "compaction"), or NULL when there is no router service or no answer that resolves
#' @noRd
compact_route = function(s) {
  if (!ext_service_has("router.call")) return(NULL)
  res = tryCatch(ext_service_get("router.call")(s, "compaction"), error = function(e) NULL)
  ref = if (is.list(res)) res[["model"]] else res
  if (is.list(ref) && !is.null(ref[["api"]])) return(ref)
  if (!is.character(ref)) return(NULL)
  prompt_model(ref)
}

#' The session's current run (the live record's `run`), or NULL outside a run
#' Read once when a compaction starts: P06's `run_settle()` clears it.
#' @noRd
compact_live_run = function(s) {
  live = session_live(s)
  if (is.null(live)) NULL else live$run
}

#' Is `run` (the run a compaction started under, or anything else) aborted or settled?
#' @noRd
compact_run_halted = function(run) {
  is.environment(run) && (isTRUE(run$settled) || isTRUE(run$signal$aborted))
}

#' The latest compaction entry on the active path, or NULL
#' @noRd
compact_last = function(s) {
  for (e in rev(prompt_path(s))) if (identical(e$type, "compaction")) return(e)
  NULL
}

#' The selected compactor spec (setting `compactor`, default "checkpoint")
#' @noRd
compact_compactor = function(s) {
  sid = prompt_sid(s)
  name = setting_get("compactor", session = s, default = "checkpoint")
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    name = "checkpoint"
  }
  sp = tryCatch(registry_get("compactor", name, session = sid), error = function(e) NULL)
  sp %||% registry_get("compactor", "checkpoint", session = sid) %||%
    list(name = "checkpoint", should = compact_checkpoint_should, compact = compact_checkpoint)
}

#' Should the session compact now? (the compact.should service, `lgl(1)`, contract 7.0)
#' The compactor's `should()` decides (an error: diagnostic, FALSE); TRUE's `reason` is also kept
#' in the memo, as P06 calls compact.run(s, "threshold") for every TRUE.
#' @noRd
compact_should = function(s, tokens, idle_s) {
  comp = compact_compactor(s)
  ctx = prompt_ctx(s)
  res = tryCatch(with_prompt_input(ctx, list(tokens = tokens, idle_s = idle_s),
                                   function() comp$should(s, ctx)),
                 error = function(e) {
                   registry_diagnostic(paste0("compactor:", comp$name %||% "checkpoint"),
                                       "should", class(e)[1], conditionMessage(e))
                   FALSE
                 })
  hit = isTRUE(res)
  reason = if (hit) attr(res, "reason") else NULL
  if (hit && !isTRUE(reason %in% c("threshold", "cold"))) reason = "threshold"
  memo = prompt_memo(s)
  if (!is.null(memo)) assign("prompt_should", reason, envir = memo)
  if (hit) structure(TRUE, reason = reason) else FALSE
}

#' The checkpoint compactor's trigger: the threshold (waiting for 20% growth of the window
#' after a threshold compaction, IC-71) or the cold rule (idle beyond the tail TTL with at
#' least `gptr.compact_cold_min` tokens); an unknown count or idle time is no evidence (IC-74)
#' @noRd
compact_checkpoint_should = function(session, ctx) {
  num = function(x) suppressWarnings(as.numeric(x %||% NA_real_))[1]
  inp = ctx$input
  tokens = num(inp$tokens)
  idle = num(inp$idle_s)
  if (is.na(tokens)) return(FALSE)
  m = compact_target(session)
  if (is.null(m)) return(FALSE)
  window = num(m[["context"]])
  thr = compact_threshold(window, num(m[["max_output"]]), gptr_opt("r_output_tokens"))
  if (tokens >= thr) {
    last = compact_last(session)
    after = num(last$details$tokens_after)
    if (is.na(after)) after = 0
    waits = !is.null(last) && identical(last$details$reason, "threshold") && !is.na(window)
    if (!waits || tokens >= after + 0.2 * window) return(structure(TRUE, reason = "threshold"))
  }
  ttl = if (identical(prompt_cache_gap_state(session)$ttl, "1h")) 3600 else 300
  if (!is.na(idle) && idle > ttl && tokens >= gptr_opt("compact_cold_min")) {
    return(structure(TRUE, reason = "cold"))
  }
  FALSE
}

# ---- the checkpoint request and entry -----------------------------------------------------------

#' The <compaction_request> text with an optional focus line (G4 section 3.6)
#' @noRd
compact_request_text = function(focus = NULL) {
  ok = length(focus) && !is.na(focus[1]) && nzchar(focus[1])
  f = if (ok) paste0("\nFocus: ", focus[1]) else ""
  sub("{focus}", f, prompt_text("compaction_request"), fixed = TRUE)
}

#' An event of the session with the contract 4.5 envelope (current run, else NULL and "main")
#' @noRd
compact_event = function(s, type, ...) {
  d = session_data(s)
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  ev_new(type, session = d$id, run = if (is.null(run)) NULL else run[["id"]],
         agent = if (is.null(run)) "main" else run[["opts"]][["agent"]] %||% "main",
         turn = d$turns, ...)
}

#' Send one checkpoint request in-conversation (a cache read); its reply or NULL
#' Guarded, then the model's stored view is put back; the run's safety record goes along (IC-74);
#' the nested pump runs no tool (IC-57) and ends on abort or settle, cancelling the transfer.
#' @noRd
compact_ask_once = function(s, target, text, run = compact_live_run(s)) {
  d = session_data(s)
  live = session_live(s)
  req = request_build(s, target, extra = msg_user(text, source = "prompt"))
  memo = prompt_memo(s)
  key = prompt_view_key(target)
  prev = if (is.null(memo)) NULL else get0(key, envir = memo, inherits = FALSE)
  restore = function() {
    if (is.null(memo)) return(invisible(NULL))
    if (!is.null(prev)) {
      assign(key, prev, envir = memo)
    } else if (exists(key, envir = memo, inherits = FALSE)) {
      rm(list = key, envir = memo)
    }
    invisible(NULL)
  }
  tryCatch(prefix_guard(s, target, req$view), finally = restore())
  context = req$context
  context$params$max_tokens = 2048L
  context$params$returns = NULL
  box = new.env(parent = emptyenv())
  box$msg = NULL
  box$done = FALSE
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  signal$reason = NULL
  opts = list(signal = signal, state = live$adapter, memo = live$memo, session = d$id,
              run = NULL)
  safety = if (is.null(run)) NULL else run[["opts"]][["safety"]]
  if (!is.null(safety)) opts$safety = safety
  box$refused = FALSE
  id = tryCatch(provider_stream(target, context, opts, emit = function(ev) NULL,
                                done = function(msg) {
                                  box$msg = msg
                                  box$done = TRUE
                                  invisible(NULL)
                                }),
                error = function(e) {
                  registry_diagnostic("builtin:compaction", "compact", class(e)[1],
                                      paste0("The checkpoint request was not sent: ",
                                             conditionMessage(e)))
                  box$refused = TRUE
                  NA_character_
                })
  if (isTRUE(box$refused)) return(NULL)
  on.exit({
    started = is.character(id) && length(id) == 1L && !is.na(id)
    if (!isTRUE(box$done) && started) {
      signal$aborted = TRUE
      reactor_cancel(id)
    }
  }, add = TRUE)
  reactor_pump(until = function() isTRUE(box$done) || compact_run_halted(run),
               allow_runs = character())
  box$msg
}

#' The checkpoint reply, `list(msg, usage)`: a tool call, a length stop or no text is asked
#' again once, an error reply or a halted run is not; `usage` sums every reply received
#' @noRd
compact_ask = function(s, target, text, run = compact_live_run(s)) {
  usages = list()
  for (i in seq_len(2L)) {
    msg = compact_ask_once(s, target, text, run)
    # `[<-` with list(): a reply without usage stays in the list as NULL (unknown, IC-74)
    if (!is.null(msg)) usages[length(usages) + 1L] = list(msg$usage)
    if (is.null(msg) || isTRUE(msg$stop_reason %in% c("error", "aborted", "refusal")) ||
        compact_run_halted(run)) {
      return(list(msg = NULL, usage = compact_usage_sum(usages)))
    }
    calls = any(vapply(msg$content, function(b) identical(b$type, "tool_call"), NA))
    usable = !calls && !identical(msg$stop_reason, "length") && nzchar(trimws(msg_text(msg)))
    if (usable) return(list(msg = msg, usage = compact_usage_sum(usages)))
  }
  list(msg = NULL, usage = compact_usage_sum(usages))
}

#' The sum of usage records (contract 4.3), field by field; an NA or a missing record makes the
#' sum unknown (IC-74); none gives NULL
#' @noRd
compact_usage_sum = function(usages) {
  if (!length(usages)) return(NULL)
  if (length(usages) == 1L) return(usages[[1L]])
  rec = lapply(usages, function(u) tryCatch(usage_as(u), error = function(e) usage_as(NULL)))
  total = function(get) sum(vapply(rec, function(u) as.numeric(get(u) %||% NA_real_), 0))
  fields = c(usage_fields, "total")
  args = stats::setNames(lapply(fields, function(k) total(function(u) u[[k]])), fields)
  parts = c("input", "output", "cache_read", "cache_write", "total")
  args$cost = stats::setNames(lapply(parts, function(k) total(function(u) u$cost[[k]])), parts)
  args$estimated = any(vapply(rec, function(u) isTRUE(u$estimated), NA))
  do.call(usage_new, args)
}

#' The reused header blocks (project instructions and environment) of the current first message
#' @noRd
compact_header = function(path) {
  kinds = c("project_instructions", "environment")
  pick = function(blocks) {
    Filter(function(b) identical(b$type, "context") && isTRUE(b$kind %in% kinds), blocks)
  }
  for (e in rev(path)) {
    if (identical(e$type, "compaction")) return(pick(e$gptr$blocks %||% list()))
  }
  for (e in path) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      return(pick(e$message$content))
    }
  }
  list()
}

#' The newest skill_content block per skill name on the path, within the re-injection budgets
#' @noRd
compact_skills = function(path, budget_total = 10000, budget_each = 5000) {
  seen = list()
  for (e in path) {
    blocks = NULL
    if (identical(e$type, "compaction")) blocks = e$gptr$blocks
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      blocks = e$message$content
    }
    for (b in blocks) {
      if (identical(b$type, "context") && identical(b$kind, "skill_content")) {
        seen[[b$attrs$name %||% "skill"]] = b
      }
    }
  }
  out = list()
  used = 0
  for (b in seen) {
    n = prompt_est(b$text)
    if (n > budget_each || used + n > budget_total) next
    out[[length(out) + 1L]] = b
    used = used + n
  }
  out
}

#' The images of the latest request, which the continuation line repeats, oldest first
#' Walking back: user images up to the newest message with text; a compaction ends the walk with
#' its images, a steering relay with none.
#' @noRd
compact_request_images = function(path) {
  is_image = function(b) is.list(b) && identical(b[["type"]], "image")
  out = list()
  for (e in rev(path)) {
    if (identical(e$type, "compaction")) {
      return(c(Filter(is_image, e$gptr$blocks %||% list()), out))
    }
    op = prompt_entry_operator(e)
    if (!is.null(op)) {
      if (identical(op$kind, "steer_relay")) return(out)
      next
    }
    m = if (identical(e$type, "message")) e$message else NULL
    if (!identical(m$role, "user") ||
        !isTRUE((m$source %||% "prompt") %in% compact_user_sources)) {
      next
    }
    out = c(Filter(is_image, m$content), out)
    if (nzchar(msg_text(m))) return(out)
  }
  out
}

#' The <mode> block of the new first message: the registered `mode` block, else P07's text
#' @noRd
compact_mode_block = function(s) {
  blocks = context_block_by_name(s, "mode", list(placement = "first"))
  if (length(blocks)) return(blocks)
  d = session_data(s)
  human = d$frozen$human %||% gptr_can_prompt()
  deny = identical(gptr_opt("noninteractive_ask"), "deny")
  list(block_context("mode", context_mode_body(d$mode, human, deny), attrs = list(name = d$mode)))
}

#' The built-in checkpoint compactor (kind `compactor`, name "checkpoint")
#' Blocks: reused header, checkpoint, mode, workspace, skills, the latest request's images and a
#' continuation line repeating it whole. NULL when the run halted meanwhile.
#' @noRd
compact_checkpoint = function(session, ctx) {
  inp = ctx$input
  target = inp$target %||% compact_target(session)
  if (is.null(target)) {
    gptr_abort("Compaction needs a resolvable model.", "internal", detail = "no target")
  }
  run0 = compact_live_run(session)
  ask = compact_ask(session, target, compact_request_text(inp$focus), run0)
  if (compact_run_halted(run0)) return(NULL)
  reply = ask$msg
  summary = if (is.null(reply)) {
    registry_diagnostic("builtin:compaction", "compact", "no_summary",
                        "The checkpoint request returned no usable reply; harness state only.")
    prompt_text("checkpoint_no_summary")
  } else {
    msg_text(reply)
  }
  d = session_data(session)
  path = prompt_path(session)
  st = extract_state(path)
  n = sum(vapply(path, function(e) identical(e$type, "compaction"), NA)) + 1L
  turns = sum(vapply(path, function(e) {
    identical(e$type, "message") && identical(e$message$role, "user") &&
      isTRUE((e$message$source %||% "prompt") %in% c("prompt", "pipe", "repl", "replay"))
  }, NA))
  tok = suppressWarnings(as.numeric(inp$tokens %||% NA_real_))
  if (length(tok) != 1L || is.na(tok)) {
    tok = prompt_request_estimate(prompt_request_context(session, target), target[["api"]],
                                  d$id)$total
  }
  tb = format(round(tok), big.mark = ",", scientific = FALSE)
  cp = block_context("checkpoint", compact_checkpoint_body(summary, st, compact_shapes(session)),
                     attrs = list(n = as.character(n), turns = paste0("1-", max(1L, turns)),
                                  tokens_before = tb))
  reinject = d$frozen$reinject %||% list()
  budget_project = as.numeric(reinject$project %||% Inf)
  budget_skills = as.numeric(reinject$skills %||% 10000)
  hdr = list()
  used = 0
  # dropped project blocks (IC-71) keep their stored hash: re-announced only when the file changes
  dropped = compact_last(session)$details$dropped %||% list()
  for (b in compact_header(path)) {
    if (identical(b$kind, "project_instructions")) {
      k = prompt_est(b$text)
      if (used + k > budget_project) {
        dropped[[b$attrs$path %||% "project"]] = context_text_hash(b$text)
        next
      }
      used = used + k
    }
    hdr[[length(hdr) + 1L]] = b
  }
  ws = context_block_by_name(session, "workspace", list(placement = "first"))
  skills = compact_skills(path, budget_total = budget_skills)
  # keep_recent = 0: the latest request (often unanswered) is repeated whole, images included
  last_user = if (length(st$user)) st$user[length(st$user)] else "(none)"
  cont = block_text(paste0(prompt_text("checkpoint_continue"), last_user))
  imgs = compact_request_images(path)
  list(blocks = c(hdr, list(cp), compact_mode_block(session), ws, skills, imgs, list(cont)),
       summary = summary, state = st, first_kept_entry_id = NULL,
       usage = ask$usage,
       details = list(request_id = reply$request_id,
                      dropped = if (length(dropped)) dropped))
}

#' The section name of a `section_patch` operator text, or NA
#' @noRd
compact_patch_key = function(txt) {
  for (tmpl in c(prompt_text("section_updated"), prompt_text("section_removed"))) {
    pre = strsplit(tmpl, "%s", fixed = TRUE)[[1L]][1L]
    if (startsWith(txt, pre)) return(sub("(?s)\".*$", "", substring(txt, nchar(pre) + 1L),
                                         perl = TRUE))
  }
  NA_character_
}

#' The tool additions and section patches a compaction drops, as operator messages to re-append
#' The newest declaration per name, member line per key and patch per section; items at or after
#' `keep` (the first kept entry) stay visible and are left out.
#' @noRd
compact_operator_state = function(path, keep = NA_integer_) {
  decls = list()
  lines = character()
  patches = list()
  at = list(decls = integer(), lines = integer(), patches = integer())
  for (i in seq_along(path)) {
    op = prompt_entry_operator(path[[i]])
    if (is.null(op)) next
    txt = prompt_operator_text(op)
    if (identical(op$kind, "tool_change") && length(op$tool_add)) {
      for (x in op$tool_add) {
        nm = if (is.list(x)) x[["name"]] else NULL
        if (is.character(nm) && length(nm) == 1L && !is.na(nm) && nzchar(nm)) {
          decls[[nm]] = x
          at$decls[[nm]] = i
        }
      }
    } else if (identical(op$kind, "tool_change")) {
      for (ln in strsplit(txt, "\n", fixed = TRUE)[[1L]]) {
        key = prompt_member_key(ln)
        if (!is.na(key)) {
          lines[[key]] = ln
          at$lines[[key]] = i
        }
      }
    } else if (identical(op$kind, "section_patch")) {
      key = compact_patch_key(txt)
      if (is.na(key)) key = paste0("\r", length(patches) + 1L)
      patches[[key]] = NULL
      patches[[key]] = txt
      at$patches[[key]] = i
    }
  }
  if (!is.na(keep)) {
    decls = decls[at$decls[names(decls)] < keep]
    lines = lines[at$lines[names(lines)] < keep]
    patches = patches[at$patches[names(patches)] < keep]
  }
  out = list()
  if (length(decls)) {
    out[[length(out) + 1L]] = msg_operator("tool_change",
                                           sprintf(prompt_text("tools_added"),
                                                   paste(names(decls), collapse = ", ")),
                                           tool_add = unname(decls))
  }
  if (length(lines)) {
    out[[length(out) + 1L]] = msg_operator("tool_change",
                                           sprintf(prompt_text("members_added"),
                                                   paste(lines, collapse = "\n")))
  }
  for (txt in patches) out[[length(out) + 1L]] = msg_operator("section_patch", txt)
  out
}

#' Is `res` a usable compactor result (a non-empty list of content blocks)?
#' @noRd
compact_result_ok = function(res) {
  blocks = if (is.list(res)) res[["blocks"]] else NULL
  is.list(blocks) && length(blocks) > 0L &&
    all(vapply(blocks, function(b) is.list(b) && is.character(b[["type"]]), NA))
}

#' Compact a session (the compact.run service)
#' A `session_before_compact` result, else the compactor's (checkpoint fallback), becomes the
#' entry; dropped operator state is re-appended; a halted run records nothing.
#' @noRd
compact_run = function(s, reason, focus = NULL) {
  reason = check_choice(reason, c("threshold", "cold", "overflow", "manual"), "reason")
  check_string(focus, "focus", null = TRUE, empty = TRUE)
  run0 = compact_live_run(s)
  d = session_data(s)
  ctx = prompt_ctx(s)
  memo = prompt_memo(s)
  if (!is.null(memo)) {
    why = get0("prompt_should", envir = memo, inherits = FALSE)
    if (identical(reason, "threshold") && identical(why, "cold")) reason = "cold"
    assign("prompt_should", NULL, envir = memo)
  }
  target = compact_target(s, reason)
  # an unknown count stays NA (IC-74): the events carry NA and the entry omits tokensBefore
  tokens = NA_real_
  if (!is.null(target)) {
    tokens = prompt_request_estimate(prompt_request_context(s, target), target[["api"]],
                                     d$id)$total
  }
  dec = ev_dispatch("session_before_compact",
                    compact_event(s, "session_before_compact", reason = reason, tokens = tokens),
                    session = s, ctx = ctx)
  if (!is.list(dec)) dec = NULL
  if (isTRUE(dec$cancel)) return(invisible(s))
  res = dec$result
  strategy = "hook"
  if (!is.null(res) && !compact_result_ok(res)) {
    registry_diagnostic("session_before_compact", "result", "malformed_result",
                        paste0("A session_before_compact handler supplied a result without ",
                               "content blocks; the compactor runs instead."))
    res = NULL
  }
  if (is.null(res)) {
    comp = compact_compactor(s)
    strategy = comp$name %||% "checkpoint"
    input = list(reason = reason, focus = focus, tokens = tokens, target = target)
    run = function(f, name) {
      out = tryCatch(with_prompt_input(ctx, input, function() f(s, ctx)), error = function(e) {
        registry_diagnostic(paste0("compactor:", name), "compact", class(e)[1],
                            conditionMessage(e))
        NULL
      })
      if (!is.null(out) && !compact_result_ok(out)) {
        registry_diagnostic(paste0("compactor:", name), "compact", "malformed_result",
                            "The compactor returned no content blocks.")
        out = NULL
      }
      out
    }
    res = run(comp$compact, strategy)
    if (is.null(res) && !compact_run_halted(run0) &&
        !identical(comp$compact, compact_checkpoint)) {
      strategy = "checkpoint"
      res = run(compact_checkpoint, strategy)
    }
  }
  if (compact_run_halted(run0)) return(invisible(s))
  if (!compact_result_ok(res)) {
    gptr_abort(paste0("Compaction failed: no compactor produced a checkpoint ",
                      "(see gptr_registry(diagnostics = TRUE))."), "internal",
               detail = "compaction")
  }
  summary = if (is.character(res$summary)) {
    paste(res$summary[!is.na(res$summary)], collapse = "\n")
  } else {
    ""
  }
  # the path now holds what the checkpoint request flushed from the queue (request_build())
  path = prompt_path(s)
  state = res$state
  if (!is.null(state) && !is.list(state)) {
    src = if (identical(strategy, "hook")) "session_before_compact" else
      paste0("compactor:", strategy)
    registry_diagnostic(src, "result", "malformed_state",
                        "The compaction result's state is not a list; the harness state is kept.")
    state = extract_state(path)
  }
  ids = vapply(path, function(e) as.character(e$id %||% NA_character_), "")
  first = res$first_kept_entry_id
  keep = if (is.character(first) && length(first) == 1L) match(first, ids) else NA_integer_
  ops = compact_operator_state(path, keep)
  op_tokens = function(m) {
    prompt_est(msg_text(m), "prose", d$id) +
      if (length(m$tool_add)) prompt_est(json_encode(m$tool_add), "json", d$id) else 0
  }
  # images (the latest request's, or a result's own) count as P07's request estimate counts them
  imgs = Filter(function(b) identical(b$type, "image"), res$blocks)
  img_tokens = if (length(imgs)) {
    prompt_request_estimate(list(tools_json = "",
                                 messages = list(list(role = "user", content = imgs))),
                            target[["api"]], d$id)$components[["images"]]
  } else {
    0
  }
  after = sum(vapply(res$blocks, function(b) prompt_est(b$text %||% "", "prose", d$id), 0)) +
    img_tokens + prompt_static_tokens(d$frozen, d$id) + sum(vapply(ops, op_tokens, 0))
  n = sum(vapply(path, function(e) identical(e$type, "compaction"), NA)) + 1L
  details = if (is.list(res$details)) Filter(Negate(is.null), res$details) else list()
  details$reason = reason
  details$strategy = strategy
  details$tokens_after = after
  session_append(s, list(type = "compaction", summary = summary,
                         first_kept_entry_id = res$first_kept_entry_id,
                         tokens_before = if (!is.na(tokens)) tokens, details = details,
                         usage = if (is.list(res$usage)) res$usage else NULL,
                         gptr = list(blocks = res$blocks, state = state, n = n)))
  for (m in ops) session_append(s, prompt_operator_entry(m))
  ev_dispatch("session_compact",
              compact_event(s, "session_compact", strategy = strategy, tokens_before = tokens,
                            summary_tokens = prompt_est(summary, "prose", d$id)),
              session = s, ctx = ctx)
  invisible(s)
}

#' The built-in `compaction` extension (contract section 10.3)
#' @noRd
builtin_compaction = function(gptr) {
  gptr$register(gptr_spec("compactor", "checkpoint", should = compact_checkpoint_should,
                          compact = compact_checkpoint))
  invisible(NULL)
}

on_load({
  ext_declare_builtin("compaction", builtin_compaction, after = "prompt")
  ext_service_set("compact.should", compact_should, provided_by = "P07", builtin = "compaction")
  ext_service_set("compact.run", compact_run, provided_by = "P07", builtin = "compaction")
})
