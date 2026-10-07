# Copy-safe workspace snapshots, diffs and workspace lines (P09; architecture 6.4 R1, R4, R6).
# Only the leaves bind a user object and return fresh facts; loops address objects by name, no
# closure, tryCatch() or list holds one, and a function-frame home lives only in a box binding
# reset on exit (fresh-process tracemem runs, test-copy-eval.R).

#' Format a byte count for model-facing text ("3 KB", "1.2 MB", "5.1 GB")
#' @noRd
env_fmt_bytes = function(b) {
  if (is.null(b) || length(b) != 1L || is.na(b)) return("")
  units = c("B", "KB", "MB", "GB", "TB")
  i = max(1L, min(length(units), floor(log(max(b, 1), 1024)) + 1L))
  v = b / 1024^(i - 1L)
  txt = if (i == 1L || v >= 10) sprintf("%.0f", v) else sub("\\.0$", "", sprintf("%.1f", v))
  paste(txt, units[i])
}

#' Format counts with thousands separators (the decimal mark fixed, whatever `OutDec` says)
#' @noRd
env_fmt_n = function(n) {
  format(n, big.mark = ",", decimal.mark = ".", scientific = FALSE, trim = TRUE)
}

#' Display text of names, classes, shapes and expressions: UTF-8, with the bytes of invalid
#' strings shown as `<xx>` (an object name need not be valid UTF-8; IC-62)
#' @noRd
env_text = function(x) {
  x = as_utf8(as.character(x))
  bad = which(!is.na(x) & !validUTF8(x))
  if (length(bad)) x[bad] = iconv(x[bad], "UTF-8", "UTF-8", sub = "byte")
  x
}

#' Is x a compact-looking integer sequence (ALTREP 1:n)? (a leaf)
#' Reads three elements through .subset(), which never materialises a compact sequence.
#' @noRd
env_compact_seq = function(x) {
  if (!is.integer(x) || !is.null(attributes(x))) return(FALSE)
  n = length(x)
  if (n < 1e6) return(FALSE)
  e = .subset(x, c(1L, 2L, n))
  !anyNA(e) && e[2L] - e[1L] == 1L && as.numeric(e[3L]) - e[1L] == n - 1
}

#' Facts of a Seurat object through attributes only (a leaf; not in Suggests, IC-71)
#' Handles v5 Assay5 (a `features` LogMap) and v3 Assay (a `data` dgCMatrix).
#' @noRd
env_seurat_facts = function(x) {
  md = attr(x, "meta.data")
  assays = attr(x, "assays")
  active = attr(x, "active.assay")
  a = NULL
  if (length(assays)) {
    a = if (length(active) == 1L && active %in% names(assays)) {
      .subset2(assays, active)
    } else {
      .subset2(assays, 1L)
    }
  }
  feats = NA_real_
  if (!is.null(a)) {
    fd = attr(attr(a, "features"), "dim")
    dd = attr(attr(a, "data"), "Dim")
    if (length(fd)) feats = fd[1L] else if (length(dd)) feats = dd[1L]
  }
  idents = attr(x, "active.ident")
  list(
    cells = if (is.null(md)) NA_real_ else .row_names_info(md, 2L), features = feats,
    assays = names(assays), active = active, reductions = names(attr(x, "reductions")),
    meta_cols = names(md), meta_p = length(md), idents = length(attr(idents, "levels"))
  )
}

#' Shape text: "a x b", "n x p", "length n", "<c> cells x <f> features" (a leaf)
#' @noRd
env_shape = function(x) {
  if (inherits(x, "Seurat")) {
    f = env_seurat_facts(x)
    return(paste(env_fmt_n(f$cells), "cells x", env_fmt_n(f$features), "features"))
  }
  d = attr(x, "dim")
  if (is.null(d) && isS4(x)) d = attr(x, "Dim")
  if (length(d)) return(paste(env_fmt_n(d), collapse = " x "))
  if (inherits(x, "data.frame")) {
    return(paste(env_fmt_n(.row_names_info(x, 2L)), "x", env_fmt_n(length(x))))
  }
  if (is.function(x)) return("")
  if (is.environment(x)) return(paste(env_fmt_n(length(x)), "bindings"))
  s = paste("length", env_fmt_n(length(x)))
  if (env_compact_seq(x)) s = paste(s, "(sequence)")
  s
}

#' Snapshot facts of one binding value, without its size (a leaf)
#' @noRd
env_snap_leaf = function(x) {
  opaque = is.environment(x) || is.function(x)
  list(
    address = rlang::obj_address(x), class = class(x)[1L], shape = env_shape(x),
    fp = if (opaque) rlang::obj_address(x) else fingerprint(x)
  )
}

#' Facts of a value whose methods fail (a `length()` method that errors, for example a Python
#' object without a length): address and class, which never dispatch, and shape "?" (a leaf)
#' @noRd
env_snap_bare = function(x) {
  list(address = rlang::obj_address(x), class = class(x)[1L], shape = "?",
       fp = rlang::obj_address(x))
}

#' Does binding `name` of box$envir hold R's missing argument? (a leaf; D-040)
#' .subset2() returns it unevaluated where get() throws; a forced default is a value. Never called
#' on a promise or an active binding.
#' @noRd
env_snap_missing = function(box, name) {
  identical(.subset2(box$envir, name), quote(expr = ))
}

#' Facts of binding `name` of box$envir; a failing method gives env_snap_bare() facts
#' The missing argument is class `<missing>`, checked first so get() never fails with the home on
#' its frame; the tryCatch() frame holds only the box (R3).
#' @noRd
env_snap_facts = function(box, name) {
  force(box)
  force(name)
  if (env_snap_missing(box, name)) {
    return(list(address = NA_character_, class = "<missing>", shape = "", fp = NA_character_))
  }
  tryCatch(env_snap_leaf(get(name, envir = box$envir, inherits = FALSE)),
           error = function(e) env_snap_bare(get(name, envir = box$envir, inherits = FALSE)))
}

#' Size in bytes of one binding value; NA for environments, functions, external pointers and
#' compact sequences (object.size() overstates them) (a leaf)
#' @noRd
env_snap_size = function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) == "externalptr" || env_compact_seq(x)) {
    return(NA_real_)
  }
  as.numeric(utils::object.size(x))
}

#' Snapshot rows; `sizes = FALSE` skips object.size() (the evaluator needs no sizes)
#' `envir` is held only in a box binding reset on exit: a loop in a frame binding a function-frame
#' home left it referenced (tracemem), so the loop is in env_snap_rows().
#' @noRd
env_snapshot_rows = function(envir, previous = NULL, sizes = TRUE) {
  box = new.env(parent = emptyenv())
  box$envir = envir
  on.exit({
    box$envir = NULL
  }, add = TRUE)
  env_snap_rows(box, previous, sizes)
}

#' The snapshot loop; addresses objects by name through box$envir
#' Fills vectors and builds the data frame once (cell assignment copied a column: quadratic).
#' @noRd
env_snap_rows = function(box, previous, sizes) {
  force(box)
  force(previous)
  force(sizes)
  # Named `envir =`: a positional ls(envir) runs tryCatch() on it and pins a frame home (tracemem)
  nms = setdiff(ls(envir = box$envir, all.names = TRUE, sorted = TRUE),
                c(".Random.seed", ".Last.value"))
  n = length(nms)
  kind = rep("value", n)
  address = rep(NA_character_, n)
  cls = rep(NA_character_, n)
  bytes = rep(NA_real_, n)
  shape = rep(NA_character_, n)
  fp = rep(NA_character_, n)
  if (n) {
    act = unname(rlang::env_binding_are_active(box$envir, nms))
    lazy = unname(rlang::env_binding_are_lazy(box$envir, nms))
    kind[act] = "active"
    kind[lazy & !act] = "promise"
  }
  prev = if (is.null(previous)) rep(NA_integer_, n) else match(nms, previous$name)
  for (i in which(kind == "value")) {
    f = env_snap_facts(box, nms[i])
    address[i] = f$address
    cls[i] = f$class
    shape[i] = f$shape
    fp[i] = f$fp
    if (!sizes || is.na(f$address)) next
    j = prev[i]
    reuse = !is.na(j) && identical(previous$address[j], f$address) &&
      identical(previous$class[j], f$class) && identical(previous$shape[j], f$shape)
    bytes[i] = if (reuse) {
      previous$bytes[j]
    } else {
      env_snap_size(get(nms[i], envir = box$envir, inherits = FALSE))
    }
  }
  data.frame(name = nms, kind = kind, address = address, class = cls, bytes = bytes,
             shape = shape, fp = fp, stringsAsFactors = FALSE)
}

#' Copy-safe snapshot of an environment, forcing no promise and calling no active binding (R4)
#' One row per binding: name, kind (value, promise, active), address, class, bytes (reused from
#' `previous` while address, class and shape hold), shape, fp; missing arguments are `<missing>`.
#' @noRd
env_snapshot = function(envir, previous = NULL) {
  check_env(envir, "envir")
  if (!is.null(previous) && !is.data.frame(previous)) {
    gptr_abort("`previous` must be a snapshot data frame or NULL.", "invalid_argument",
               arg = "previous", expected = "a data frame or NULL")
  }
  env_snapshot_rows(envir, previous, sizes = TRUE)
}

#' TRUE where two character vectors are equal, NA matching NA
#' @noRd
env_same = function(a, b) {
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
}

#' Difference of two snapshots: list(added, modified, removed) in radix order of display text
#' `modified`: kind, address or fingerprint changed, or a static assignment target in `assigned`;
#' a forced promise is not a modification.
#' @noRd
env_diff = function(old, new, assigned = character()) {
  both = intersect(new$name, old$name)
  o = old[match(both, old$name), , drop = FALSE]
  n = new[match(both, new$name), , drop = FALSE]
  forced = o$kind == "promise" & n$kind == "value"
  same = forced | (o$kind == n$kind & env_same(o$address, n$address) & env_same(o$fp, n$fp))
  # The radix key is the display text: R's radix sort refuses a non-ASCII string of unknown
  # encoding, which is what ls() returns for a name such as `donn<e9>es` parsed from code
  srt = function(x) {
    x = unique(as.character(x))
    x[order(env_text(x), method = "radix")]
  }
  list(
    added = srt(setdiff(new$name, old$name)),
    modified = srt(c(both[!same], intersect(assigned, both))),
    removed = srt(setdiff(old$name, new$name))
  )
}

#' Left-aligned workspace columns: name, class, then "shape  size"
#' @noRd
env_align = function(name, cls, shape, size) {
  w1 = min(32L, max(nchar(name))) + 2L
  w2 = min(24L, max(nchar(cls))) + 2L
  tail = ifelse(nzchar(shape) & nzchar(size), paste0(shape, "  ", size),
                ifelse(nzchar(shape), shape, size))
  sub("\\s+$", "", paste0(formatC(name, width = -w1), formatC(cls, width = -w2), tail))
}

#' Lines of the `<workspace>` block within `budget` estimated tokens
#' At most 12 lines `name  class  shape  size`, largest first, then `(+ n smaller objects: use
#' ls())`; promises and active bindings show as `<promise>` and `<active>`.
#' @noRd
workspace_lines = function(snapshot, budget = 600L) {
  check_number(budget, "budget", min = 20)
  n = nrow(snapshot)
  if (!n) return(character())
  size = snapshot$bytes
  size[is.na(size)] = -1
  s = snapshot[order(-size, snapshot$name, method = "radix"), , drop = FALSE]
  value = s$kind == "value"
  cls = ifelse(value, s$class, paste0("<", s$kind, ">"))
  shape = ifelse(value, s$shape, "")
  size_txt = vapply(s$bytes, env_fmt_bytes, "")
  k = min(n, 12L)
  top = seq_len(k)
  lines = env_align(env_text(s$name[top]), env_text(cls[top]), env_text(shape[top]),
                    size_txt[top])
  more = function(m) if (n - k + m > 0L) sprintf("(+ %d smaller objects: use ls())", n - k + m)
  shown = utils::head(lines, max(1L, lines_fit(lines, budget, "describe", more)))
  c(shown, more(k - length(shown)))
}

#' Lines of the `<workspace_changes>` block within `budget` (empty when nothing changed)
#' `+ name class shape size`, `~ name`, `- name`, `user ran: <expr>` (user_expr_log()).
#' @noRd
changes_lines = function(diff, snapshot, user_ran, budget = 300L) {
  check_number(budget, "budget", min = 20)
  i = match(diff$added, snapshot$name)
  added = character()
  if (length(i)) {
    added = paste("+", env_text(snapshot$name[i]), env_text(snapshot$class[i]),
                  env_text(snapshot$shape[i]), vapply(snapshot$bytes[i], env_fmt_bytes, ""))
  }
  lines = sub("\\s+$", "", c(
    added,
    if (length(diff$modified)) paste("~", env_text(diff$modified)),
    if (length(diff$removed)) paste("-", env_text(diff$removed)),
    if (length(user_ran)) paste("user ran:", env_text(user_ran))
  ))
  lines = gsub(" {2,}", " ", lines)
  more = function(m) if (m > 0L) sprintf("(+ %d more changes)", m)
  shown = utils::head(lines, max(1L, lines_fit(lines, budget, "describe", more)))
  c(shown, more(length(lines) - length(shown)))
}

# ---------------------------------------------------------------- builtin:workspace

#' The context mode of the call: "summary" (default), "names" or "none" (`.opts$context`)
#' @noRd
env_context_mode = function(ctx) {
  mode = ctx$input$opts$context
  if (is.character(mode) && length(mode) == 1L && mode %in% c("summary", "names", "none")) {
    return(mode)
  }
  "summary"
}

#' The environment the workspace blocks list: the kept home, else the run's environment
#' @noRd
env_home = function(ctx) {
  s = ctx$session
  home = if (is.null(s)) NULL else session_home(s)
  home %||% ctx$envir
}

#' Per-session workspace memory, never persisted (snapshot addresses are per process)
#' Kept in the live record's `memo`, shared by the block providers and the agent_end hook (D-112);
#' without a live session inside `ctx$state()`, else a fresh environment (nothing is kept).
#' @noRd
env_memory = function(ctx) {
  s = ctx$session
  live = if (inherits(s, "gptr_session")) session_live(s) else NULL
  holder = if (is.null(live)) ctx$state() else live$memo
  if (!is.environment(holder)) return(new.env(parent = emptyenv()))
  mem = get0("gptr_workspace", envir = holder, inherits = FALSE)
  if (!is.environment(mem)) {
    mem = new.env(parent = emptyenv())
    assign("gptr_workspace", mem, envir = holder)
  }
  mem
}

#' Remember the snapshot and the time for the next `<workspace_changes>`; start the history
#' log for a session with a kept home (env-history.R). A preview (`gptr_prompt()`, P07's
#' `input$preview`) changes neither (D-112).
#' @noRd
env_remember = function(ctx, snap) {
  if (isTRUE(ctx$input$preview)) return(invisible())
  mem = env_memory(ctx)
  mem$snapshot = snap
  mem$since = as.numeric(Sys.time())
  s = ctx$session
  if (!is.null(s) && !is.null(session_home(s))) user_log_start(session_data(s)$id)
  invisible()
}

#' Names-only workspace listing (`.opts$context = "names"`)
#' @noRd
env_names_lines = function(snap, budget) {
  if (!nrow(snap)) return(character())
  dsc_fit(paste(snap$name, collapse = ", "), budget)
}

#' `<workspace env=".." objects="n">`: one line per object, largest first (first message)
#' @noRd
env_block_workspace = function(ctx, budget) {
  mode = env_context_mode(ctx)
  envir = env_home(ctx)
  if (identical(mode, "none") || is.null(envir)) return(NULL)
  snap = env_snapshot(envir, env_memory(ctx)$snapshot)
  env_remember(ctx, snap)
  lines = if (identical(mode, "names")) {
    env_names_lines(snap, budget)
  } else {
    workspace_lines(snap, budget)
  }
  if (!length(lines)) lines = "(no objects)"
  # P06's home_label is "<none>" for a session without a home (the run's environment is listed)
  label = if (is.null(ctx$session)) NULL else session_data(ctx$session)$home_label
  if (!is.character(label) || length(label) != 1L || is.na(label) || label == "<none>") {
    label = if (identical(envir, globalenv())) "globalenv" else "<environment>"
  }
  list(text = paste(lines, collapse = "\n"),
       attrs = list(env = label, objects = as.character(nrow(snap))))
}

#' `<workspace_changes>`: objects the user added, changed or removed and the expressions they
#' ran since the last request (turn messages; NULL when nothing changed)
#' @noRd
env_block_changes = function(ctx, budget) {
  envir = env_home(ctx)
  if (identical(env_context_mode(ctx), "none") || is.null(envir)) return(NULL)
  mem = env_memory(ctx)
  old = mem$snapshot
  new = env_snapshot(envir, old)
  ran = user_expr_log(since = mem$since)
  env_remember(ctx, new)
  d = if (is.null(old)) {
    list(added = character(), modified = character(), removed = character())
  } else {
    env_diff(old, new)
  }
  lines = changes_lines(d, new, ran, budget)
  if (!length(lines)) return(NULL)
  paste(lines, collapse = "\n")
}

#' Description of context item i of the call; an error becomes a one-line note
#' The tryCatch() frame holds the gptr_call, whose `envir` the gateway resets at settlement (R2).
#' @noRd
env_attached_one = function(call, i, budget, label, prefix, header_only) {
  force(call)
  force(i)
  force(budget)
  force(label)
  force(prefix)
  force(header_only)
  d = tryCatch(
    if (header_only) {
      gptr_describe(call_value(call, i), budget = 20L, level = 1L)
    } else {
      describe_value(call_value(call, i), budget)
    },
    error = function(e) paste0("<?> (describe failed: ", conditionMessage(e), ")")
  )
  if (prefix) d[1L] = paste0(label, ": ", d[1L])
  paste(d, collapse = "\n")
}

#' `<attached name="..">`: gptr_describe() of the call's context objects (first message and
#' turns, placement "both", IC-38); 150 tokens per object, at least 60 when many share the
#' block budget
#' @noRd
env_block_attached = function(ctx, budget) {
  call = ctx$input$call
  mode = env_context_mode(ctx)
  if (is.null(call) || identical(mode, "none") || !length(call$context)) return(NULL)
  n = length(call$context)
  per = as.integer(min(150L, max(60L, budget %/% n)))
  labels = vapply(call$context, function(it) as.character(it$label %||% ""), "")
  parts = character(n)
  for (i in seq_len(n)) {
    parts[i] = env_attached_one(call, i, per, labels[i], n > 1L, identical(mode, "names"))
  }
  list(text = paste(parts, collapse = "\n"), attrs = list(name = paste(labels, collapse = ", ")))
}

#' `<skill_content name="..">`: bodies of the skills preloaded with `skills =` (5,000 tokens per
#' skill; P17's `skill.body` service, whose canonical names label them; NULL before P17 is loaded)
#' @noRd
env_block_skills = function(ctx, budget) {
  call = ctx$input$call
  skills = if (is.null(call)) NULL else call$ids$skills
  if (!length(skills) || !ext_service_has("skill.body")) return(NULL)
  body = ext_service_get("skill.body")
  per = as.integer(max(200L, min(5000L, budget %/% length(skills))))
  parts = character(length(skills))
  for (k in seq_along(skills)) {
    b = body(skills[k])
    if (is.list(b)) {
      skills[k] = b$name %||% skills[k]
      b = b$text
    }
    lines = strsplit(as.character(b %||% ""), "\n", fixed = TRUE)[[1L]]
    lines = utils::head(lines, max(1L, lines_fit(lines, per, "prose")))
    parts[k] = paste(c(if (length(skills) > 1L) sprintf("[skill: %s]", skills[k]), lines),
                     collapse = "\n")
  }
  list(text = paste(parts, collapse = "\n\n"),
       attrs = list(name = paste(skills, collapse = ", ")))
}

#' The `eval.r` service: eval_r() through the `evaluator` record named by the `evaluator`
#' setting (default "r"; IC-69); an unknown name falls back to the record `r`, then to eval_r()
#' @noRd
env_eval_service = function(code, envir, ...) {
  ev = registry_get("evaluator", setting_get("evaluator", default = "r")) %||%
    registry_get("evaluator", "r")
  fun = if (is.function(ev$eval)) ev$eval else eval_r
  fun(code, envir, ...)
}

#' agent_end hook: remember the workspace, so the next `<workspace_changes>` shows only what the
#' user changed between requests; only for sessions whose workspace block ran (a session with
#' `.opts$context = "none"` pays for no snapshot)
#' @noRd
env_on_agent_end = function(event, ctx) {
  envir = env_home(ctx)
  old = env_memory(ctx)$snapshot
  if (!is.null(envir) && !is.null(old)) env_remember(ctx, env_snapshot(envir, old))
  NULL
}

#' session_shutdown hook: release the history log of the session
#' @noRd
env_on_shutdown = function(event, ctx) {
  if (is.character(event$session) && length(event$session) == 1L) {
    user_log_release(event$session)
  }
  NULL
}

#' The built-in `workspace` extension (architecture sections 7.4-7.5; 04 section 7.9)
#' Context blocks (IC-38), the T1 section `r_env`, the `evaluator` record `r` (IC-69) and two
#' hooks; the `eval.r` and `describe` services below are owned by this built-in (IC-34).
#' @noRd
builtin_workspace = function(gptr) {
  gptr$register(gptr_context_block("workspace", env_block_workspace, placement = "first",
                                   budget = 600L, order = 500L))
  gptr$register(gptr_context_block("workspace_changes", env_block_changes, placement = "turn",
                                   budget = 300L, order = 100L))
  gptr$register(gptr_context_block("attached", env_block_attached, placement = "both",
                                   budget = 1200L, order = 600L))
  gptr$register(gptr_context_block("skill_content", env_block_skills, placement = "both",
                                   budget = 10000L, order = 700L))
  gptr$register(gptr_prompt_section("r_env", function(ctx) r_env_probe(), tier = "T1",
                                    order = 900L, budget = 450L))
  gptr$register(gptr_spec("evaluator", "r", eval = eval_r))
  gptr$on("agent_end", env_on_agent_end)
  gptr$on("session_shutdown", env_on_shutdown)
  invisible(NULL)
}

on_load(ext_declare_builtin("workspace", builtin_workspace))
on_load(ext_service_set("eval.r", env_eval_service, provided_by = "P09", builtin = "workspace"))
on_load(ext_service_set("describe", describe_value, provided_by = "P09", builtin = "workspace"))
