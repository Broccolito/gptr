# doc-locate.R -- locating the calling statement (plan P15; contract 7.15; architecture 6.9.3):
# a validated srcref > a source()/sys.source() frame (read inside tryCatch, off switch
# gptr.doc_source_frames; CRAN grey zone) > knitr/Quarto > IRkernel > `Rscript --file=` > IDE >
# console. Calls are matched by content and ordinal through an anchor (prompt hash or call-text
# hash, ordinal, block), never by stale line numbers. Also the console transcript target (IC-49,
# IC-52). Layer L4. Adapted from report 14 sections 4.2 and 5.0 (gptr_where, doc_match_call).

#' A call without attributes (srcrefs), for identity tests
#' @noRd
doc_strip_call = function(x) {
  if (is.null(x)) return(NULL)
  attributes(x) = NULL
  x
}

#' The R/ directory of gptr's own sources when they carry srcrefs (pkgload::load_all()), or NULL
#' @noRd
doc_own_sources = function() {
  ns = topenv(environment(doc_own_sources))
  if (!isNamespace(ns)) return(NULL)
  path_norm(file.path(getNamespaceInfo(ns, "path"), "R"))
}

#' Absolute path of a srcfile when it is an existing user file: not RStudio's
#' .active-rstudio-document and not gptr's own sources (whose srcrefs exist under load_all())
#' @noRd
doc_srcfile_path = function(sf) {
  if (is.null(sf) || !is.environment(sf) || !isTRUE(sf$isFile)) return(NULL)
  fn = sf$filename %||% ""
  if (!is.character(fn) || length(fn) != 1L || !nzchar(fn) ||
        identical(basename(fn), ".active-rstudio-document")) {
    return(NULL)
  }
  full = if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", fn)) {
    path.expand(fn)
  } else {
    file.path(sf$wd %||% getwd(), fn)
  }
  if (!file.exists(full)) return(NULL)
  full = path_norm(full)
  own = doc_own_sources()
  if (!is.null(own) && startsWith(path_key(full), paste0(path_key(own), "/"))) return(NULL)
  full
}

#' Site from a validated srcref of the call or of a calling frame (report 14 section 4.2 step 1):
#' the statement's text must contain this call. A pipeline forces its inner calls inside the
#' outer one, so an inner call's own srcref points into the forcing function; the frames below
#' it are searched for the statement that holds it.
#' @noRd
doc_site_srcref = function(call, ph, call0) {
  n = call$nframe %||% 0L
  if (is.na(n)) n = 0L
  cands = list(call$sys_call)
  for (k in rev(seq_len(max(0L, n - 1L)))) cands[[length(cands) + 1L]] = sys.call(k)
  for (cl in cands) {
    sr = attr(cl, "srcref")
    if (is.null(sr) || length(sr) < 8L) next
    sf = attr(sr, "srcfile")
    path = doc_srcfile_path(sf)
    if (is.null(path)) next
    pl = if (!is.null(sf$lines)) as_utf8(sf$lines) else doc_read(path)$lines
    rng = c(sr[7L], sr[8L])
    if (rng[1L] < 1L || rng[2L] > length(pl)) next
    k = doc_calls_have(doc_calls(pl[rng[1L]:rng[2L]]), ph, call0)
    if (!length(k)) next
    return(list(kind = "srcref", path = path, stmt_at_parse = rng, lines_at_parse = pl))
  }
  NULL
}

#' The script of a source()/sys.source() frame: its `file` as given, or NULL when that is no
#' existing file. Under chdir = TRUE both read the file and then change to its directory, keeping
#' the directory they were called from as `owd`: a relative `file` is relative to `owd`.
#' @noRd
doc_frame_file = function(file, owd) {
  if (!is.character(file) || length(file) != 1L || is.na(file) || !nzchar(file)) return(NULL)
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|~)", file) && is.character(owd) && length(owd) == 1L &&
        !is.na(owd) && nzchar(owd)) {
    file = file.path(owd, file)
  }
  if (file.exists(file)) file else NULL
}

#' Site from a source()/sys.source() frame (`ofile` or `file`, `exprs`, `i`); best effort and
#' switched off by options(gptr.doc_source_frames = FALSE). RStudio's sourced copy of an editor
#' buffer (.active-rstudio-document) is no document: the IDE finder locates the call in the
#' buffer itself.
#' @noRd
doc_site_source_frame = function(call, ph, call0) {
  if (!isTRUE(gptr_opt("doc_source_frames"))) return(NULL)
  n = call$nframe %||% 0L
  if (is.na(n)) n = 0L
  for (k in rev(seq_len(max(0L, n - 1L)))) {
    fn = sys.function(k)
    is_src = identical(fn, base::source)
    is_sys = identical(fn, base::sys.source)
    if (!is_src && !is_sys) next
    e = sys.frame(k)
    file = doc_frame_file(get0(if (is_src) "ofile" else "file", envir = e, inherits = FALSE),
                          get0("owd", envir = e, inherits = FALSE))
    exprs = get0("exprs", envir = e, inherits = FALSE)
    i = get0("i", envir = e, inherits = FALSE)
    if (is.null(file) || !is.expression(exprs) || !is.numeric(i) || length(i) != 1L ||
          i > length(exprs)) {
      next
    }
    if (identical(basename(file), ".active-rstudio-document")) return(NULL)
    target = exprs[[i]]
    occ = sum(vapply(seq_len(i), function(m) identical(exprs[[m]], target), NA))
    return(list(kind = "source_frame", path = path_norm(file), expr = doc_strip_call(target),
                occurrence = occ))
  }
  NULL
}

#' Site under knitr or Quarto: QUARTO_DOCUMENT_PATH/FILE, else knitr::current_input(); the label
#' @noRd
doc_site_knitr = function(call, ph, call0) {
  if (!isTRUE(getOption("knitr.in.progress")) || !requireNamespace("knitr", quietly = TRUE)) {
    return(NULL)
  }
  qdir = Sys.getenv("QUARTO_DOCUMENT_PATH")
  qfile = Sys.getenv("QUARTO_DOCUMENT_FILE")
  quarto = nzchar(qfile)
  path = if (quarto && nzchar(qdir)) {
    file.path(qdir, qfile)
  } else {
    tryCatch(knitr::current_input(dir = TRUE), error = function(e) NULL)
  }
  if (is.null(path) || !file.exists(path)) return(NULL)
  list(kind = if (quarto) "quarto" else "knitr", path = path_norm(path),
       label = tryCatch(knitr::opts_current$get("label"), error = function(e) NULL) %||%
         NA_character_)
}

#' Site in IRkernel: JPY_SESSION_NAME, else a content match over the notebooks in getwd()
#' @noRd
doc_site_jupyter = function(call, ph, call0) {
  if (!isTRUE(getOption("jupyter.in_kernel"))) return(NULL)
  jpy = Sys.getenv("JPY_SESSION_NAME")
  cands = if (nzchar(jpy) && file.exists(jpy)) {
    jpy
  } else {
    list.files(getwd(), pattern = "[.]ipynb$", full.names = TRUE)
  }
  for (p in cands) {
    cell = tryCatch(doc_nb_cell(nb_parse(doc_read(p)$lines), ph, call0),
                    error = function(e) NA_integer_)
    if (!is.na(cell)) return(list(kind = "jupyter", path = path_norm(p), cell = cell))
  }
  NULL
}

#' The command line of this R process (mockable wrapper of commandArgs(FALSE))
#' @noRd
doc_command_args = function() {
  commandArgs(FALSE)
}

#' The script of `Rscript file.R` as an absolute path, or NULL. A relative `--file=` is relative
#' to the launch directory: on Unix, R's sh front end exports it as PWD, which setwd() does not
#' change, so it is tried first; the working directory is the fallback (Windows, no absolute PWD)
#' @noRd
doc_rscript_file = function(f) {
  if (!is.character(f) || length(f) != 1L || is.na(f) || !nzchar(f)) return(NULL)
  cands = f
  pwd = Sys.getenv("PWD")
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|~)", f) && identical(.Platform$OS.type, "unix") &&
        startsWith(pwd, "/")) {
    cands = c(file.path(pwd, f), f)
  }
  for (p in cands) {
    if (file.exists(p) && identical(doc_format_of(p), "r")) return(path_norm(p))
  }
  NULL
}

#' The script this R process runs as `Rscript file.R` (an absolute path), or NULL
#' @noRd
doc_rscript_running = function() {
  if (gptr_is_interactive()) return(NULL)
  fa = grep("^--file=", doc_command_args(), value = TRUE)
  if (!length(fa)) return(NULL)
  doc_rscript_file(sub("^--file=", "", fa[1L]))
}

#' Site of a call under `Rscript file.R` (writes are deferred to exit, IC-51)
#' @noRd
doc_site_rscript = function(call, ph, call0) {
  f = doc_rscript_running()
  if (is.null(f)) return(NULL)
  list(kind = "rscript", path = f)
}

#' Site of a call run from an IDE editor (RStudio, Positron, VS Code with sess)
#' @noRd
doc_site_ide = function(call, ph, call0) {
  if (!gptr_is_interactive() || !doc_ide_available()) return(NULL)
  ctx = doc_ide_context()
  if (is.null(ctx) || !nzchar(ctx$path %||% "") || is.null(doc_format_of(ctx$path))) return(NULL)
  contents = as_utf8(as.character(ctx$contents))
  if (doc_ide_console_focused() && !length(doc_calls_have(doc_calls(contents), ph, call0))) {
    return(NULL)
  }
  cursor = tryCatch(ctx$selection[[1L]]$range$start[["row"]], error = function(e) NA_integer_)
  list(kind = "ide", path = path_norm(ctx$path), ide_id = ctx$id, contents = contents,
       cursor = cursor, backend = doc_ide_backend())
}

#' Next Rscript execution ordinal for a (document, call identity) pair
#' @noRd
doc_counter_next = function(path, key) {
  st = doc_state()
  k = paste(path_key(path), key)
  st$counters[[k]] = (st$counters[[k]] %||% 0L) + 1L
  st$counters[[k]]
}

#' The rows of a call table whose identity text is the evaluated call `call0` (as sys.call()
#' reports it, through doc_calls_have()), whatever their prompt hash
#' @noRd
doc_identity_rows = function(calls, call0) {
  if (!nrow(calls) || is.null(call0)) return(integer())
  rows = calls
  rows$ph = rep(NA_character_, nrow(rows))
  doc_calls_have(rows, NA_character_, call0)
}

#' Narrow candidate call rows that share a prompt hash to those that are the evaluated call
#' itself (`call0`, as sys.call() reports it): the steps of a pipeline that repeats a prompt,
#' `gptr("draft") |> gptr("again") |> gptr("again")`, differ only in their identity (contract
#' 11.5, plan self-review ambiguity 28). Unchanged without a call or when no row is that call.
#' @noRd
doc_by_identity = function(cand, call0) {
  if (nrow(cand) < 2L || is.null(call0)) return(cand)
  same = doc_identity_rows(cand, call0)
  if (length(same)) cand[same, , drop = FALSE] else cand
}

#' The rows of a call table that may hold the call (doc_calls_have()), except for a computed
#' prompt whose value equals a literal prompt of the table: doc_calls_have() prefers the rows
#' with that prompt hash, so `gptr(q)` with `q = "count rows"` would be found as
#' `gptr("count rows")`. When rows are the call `call0` itself and none of the prompt-hash rows
#' is, those rows are taken. A literal-prompt call keeps its rows: they are in both sets.
#' @noRd
doc_call_rows = function(calls, ph, call0) {
  k = doc_calls_have(calls, ph, call0)
  if (is.na(ph) || is.null(call0)) return(k)
  id = doc_identity_rows(calls, call0)
  if (length(id) && !any(k %in% id)) id else k
}

#' The candidate rows of a call in a call table, the call itself first (doc_call_rows(),
#' doc_by_identity())
#' @noRd
doc_call_cands = function(calls, ph, call0) {
  doc_by_identity(calls[doc_call_rows(calls, ph, call0), , drop = FALSE], call0)
}

#' The candidate rows of a call in a statement (line range `rng`)
#' @noRd
doc_stmt_calls = function(calls, rng, ph, call0) {
  doc_call_cands(calls[calls$line1 >= rng[1L] & calls$line2 <= rng[2L], , drop = FALSE], ph,
                 call0)
}

#' The calling cell of a notebook call, found as in a script: the cell of the first candidate
#' row among the calls of all code cells that are not agent cells (doc_call_cands()), so a
#' pipeline step is found in its own cell rather than in an earlier cell holding the same prompt
#' (contract 11.5; ambiguity 28); NA when no cell holds the call
#' @noRd
doc_nb_cell = function(nb, ph, call0) {
  cells = nb[["cells"]]
  agent = nb_is_agent(nb_cell_ids(nb))
  tabs = list()
  for (i in seq_along(cells)) {
    if (agent[i] || !identical(cells[[i]][["cell_type"]], "code")) next
    calls = doc_calls(nb_cell_lines(cells[[i]]))
    if (!nrow(calls)) next
    calls$cell = rep(i, nrow(calls))
    tabs[[length(tabs) + 1L]] = calls
  }
  if (!length(tabs)) return(NA_integer_)
  cand = doc_call_cands(do.call(rbind, tabs), ph, call0)
  if (nrow(cand)) cand$cell[1L] else NA_integer_
}

#' The anchor of a notebook call: the cell seen at locate time (informational), the call's prompt
#' hash as written in the cell (NA for a computed prompt), the call `call0` itself, which finds a
#' computed prompt and tells apart the steps of a pipeline that repeats a prompt in the cell
#' (doc_ipynb_locate() narrows the cell's rows to it), and the cell's ordinal `j` among the
#' calling cells (contract 11.5; ambiguities 27 and 28)
#' @noRd
doc_nb_anchor = function(raw, text, ph, call0) {
  cell = raw$cell %||% NA_integer_
  if (is.na(cell)) return(NULL)
  nb = nb_parse(text)
  if (cell > length(nb[["cells"]])) return(NULL)
  t = doc_call_cands(doc_calls(nb_cell_lines(nb[["cells"]][[cell]])), ph, call0)
  if (!nrow(t)) return(NULL)
  aph = t$ph[1L]
  list(ph = aph, th = NA_character_, j = nb_call_ordinal(nb, cell, aph, call0),
       block = NA_character_, cell = cell, call0 = call0)
}

#' The anchor of the located call in the text available at locate time (NULL: not found)
#' @noRd
doc_anchor = function(site, raw, text, ph, call0) {
  if (site$format %in% c("rmd", "qmd")) {
    calls = doc_rmd_calls(text)
    cand = calls[doc_call_rows(calls, ph, call0), , drop = FALSE]
    if (!is.na(raw$label %||% NA_character_)) cand = cand[cand$label %in% raw$label, , drop = FALSE]
    cand = doc_by_identity(cand, call0)
    if (identical(raw$kind, "ide") && !is.na(raw$cursor %||% NA)) {
      above = cand[cand$line1 <= raw$cursor, , drop = FALSE]
      if (nrow(above)) cand = above[nrow(above), , drop = FALSE]
    }
    if (!nrow(cand)) return(NULL)
    return(doc_anchor_of(calls, cand[1L, , drop = FALSE]))
  }
  if (identical(site$format, "ipynb")) return(doc_nb_anchor(raw, text, ph, call0))
  if (identical(raw$kind, "srcref")) {
    calls = doc_calls(raw$lines_at_parse)
    t = doc_stmt_calls(calls, raw$stmt_at_parse, ph, call0)
    return(if (nrow(t)) doc_anchor_of(calls, t[1L, , drop = FALSE]) else NULL)
  }
  calls = doc_calls(text)
  if (identical(raw$kind, "source_frame")) {
    rng = doc_stmt_by_expr(text, raw$expr, raw$occurrence %||% 1L)
    if (is.null(rng)) return(NULL)
    t = doc_stmt_calls(calls, rng, ph, call0)
    return(if (nrow(t)) doc_anchor_of(calls, t[1L, , drop = FALSE]) else NULL)
  }
  cand = doc_call_cands(calls, ph, call0)
  if (!nrow(cand)) return(NULL)
  if (identical(raw$kind, "rscript")) {
    # one counter per candidate set, keyed by the rows' own identity: the same literal prompt (or
    # the same pipeline step) in this file, or the same call text for a computed prompt, whose
    # rows have no prompt hash and whose runtime value differs between executions
    rph = cand$ph[1L]
    key = paste(c(if (is.na(rph)) "" else rph, sort(unique(cand$th))), collapse = " ")
    k = doc_counter_next(raw$path, key)
    if (k > nrow(cand)) return(NULL)
    return(doc_anchor_of(calls, cand[k, , drop = FALSE]))
  }
  if (identical(raw$kind, "ide") && !is.na(raw$cursor %||% NA)) {
    above = cand[cand$line1 <= raw$cursor, , drop = FALSE]
    if (nrow(above)) return(doc_anchor_of(calls, above[nrow(above), , drop = FALSE]))
  }
  doc_anchor_of(calls, cand[1L, , drop = FALSE])
}

#' The execution driver of a site, which decides whether a regeneration can skip the old block:
#' "knitr", "ide", "jupyter", "console", "gptr_source" or "base" (source()/Rscript)
#' @noRd
doc_driver = function(site) {
  if (site$kind %in% c("knitr", "quarto")) return("knitr")
  if (site$kind %in% c("ide", "jupyter", "console")) return(site$kind)
  st = doc_state()
  n = length(st$sources)
  if (n && identical(st$sources[[n]]$key, path_key(site$path))) return("gptr_source")
  "base"
}

#' Is a document or transcript target allowed (IC-52): one path with a document extension,
#' strictly inside the project root, and not a control, protected, critical or instructions path
#' @noRd
doc_target_valid = function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(FALSE)
  if (is.null(doc_format_of(path))) return(FALSE)
  full = tryCatch(path_norm(path), error = function(e) NULL)
  if (is.null(full)) return(FALSE)
  root = path_key(project_root())
  if (!startsWith(path_key(full), paste0(sub("/$", "", root), "/"))) return(FALSE)
  cls = tryCatch(path_class(full), error = function(e) "unknown")
  !any(cls %in% c("control", "protected", "critical", "instructions", "url", "wildcard"))
}

#' A new transcript file under .gptr/transcripts/ (only in an existing workspace), remembered
#' @noRd
doc_new_transcript = function() {
  ws = workspace_dir()
  if (is.null(ws)) return(NULL)
  target = path_norm(file.path(ws, "transcripts",
                               paste0("gptr-session-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".R")))
  doc_project_transcript(doc_rel(target))
  target
}

#' The IDE's active document when it is a valid target
#' @noRd
doc_active_document = function() {
  if (!doc_ide_available()) return(NULL)
  p = doc_ide_context()$path %||% ""
  if (is.character(p) && length(p) == 1L && nzchar(p) && doc_target_valid(path_norm(p))) {
    path_norm(p)
  } else {
    NULL
  }
}

#' Ask where to record the console session: "document", "file" or "none" (the UI's select()
#' when a UI backend is registered, else a yes/no question). NA when nothing can be offered (no
#' valid active document and no workspace), the UI cannot ask, or its dialog fails (a failing
#' dialog is not an answer, contract 10.2 row 22): nothing is remembered. A cancel (NA) is "none".
#' @noRd
doc_ask_transcript = function() {
  choices = c(document = "The active document", file = "A new transcript in .gptr/transcripts/",
              none = "Nowhere")
  active = doc_active_document()
  if (is.null(active)) choices = choices[names(choices) != "document"]
  if (is.null(workspace_dir())) choices = choices[names(choices) != "file"]
  if (identical(names(choices), "none")) return(NA_character_)
  ui = if (ext_service_has("ui.get")) {
    tryCatch(ext_service_get("ui.get")(NULL), error = function(e) NULL)
  } else {
    NULL
  }
  if (is.function(ui$select)) {
    if (!isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) return(NA_character_)
    k = tryCatch(ui$select("Record this console session into", unname(choices)),
                 error = function(e) NULL)
    if (is.null(k)) return(NA_character_)
    return(if (length(k) && !is.na(k[1L])) names(choices)[k[1L]] else "none")
  }
  if ("file" %in% names(choices)) {
    q = "Record this console session into a transcript in .gptr/transcripts/?"
    return(if (gptr_confirm(q)) "file" else "none")
  }
  if (gptr_confirm(paste0("Record this console session into ", doc_rel(active), "?"))) {
    "document"
  } else {
    "none"
  }
}

#' Where console turns are recorded (IC-49, IC-52): the gptr_doc() binding, the remembered
#' target (read through doc_remembered_target(), so a malformed or disallowed one is ignored),
#' the `transcript` setting, or (interactively, once per project) the user's choice
#' @noRd
doc_transcript_target = function(ask = FALSE) {
  b = the$doc_binding
  bound = if (is.list(b)) b[["path"]] else NULL
  if (is.character(bound) && length(bound) == 1L && !is.na(bound)) return(bound)
  mode = tryCatch(setting_get("transcript", default = "ask"), error = function(e) "ask") %||%
    "ask"
  if (identical(mode, "off")) return(NULL)
  pf = doc_project_get()
  if (identical(doc_project_entry(pf, "transcript", "target"), "off")) return(NULL)
  remembered = doc_remembered_target(pf)
  if (!is.null(remembered)) return(remembered)
  if (identical(mode, "file")) return(doc_new_transcript())
  if (identical(mode, "active-document")) return(doc_active_document())
  if (!ask || !gptr_can_prompt()) return(NULL)
  choice = doc_ask_transcript()
  if (is.na(choice)) return(NULL)
  target = switch(choice, file = doc_new_transcript(), document = doc_active_document(), NULL)
  if (is.null(target)) {
    doc_project_transcript("off")
  } else {
    doc_project_transcript(doc_rel(target))
  }
  target
}

#' The console site of a call or REPL turn: the transcript target as a document whose turns are
#' appended (`format` "transcript" for .R targets); NULL when there is no target
#' @noRd
doc_console_site = function(session_id = NULL, template = NULL, context_labels = character(),
                            ask = FALSE, session_file = NULL) {
  target = doc_transcript_target(ask = ask)
  if (is.null(target)) return(NULL)
  fmt = doc_format_of(target)
  if (is.null(fmt) || identical(fmt, "ipynb")) return(NULL)
  list(kind = "console", path = path_norm(target),
       format = if (identical(fmt, "r")) "transcript" else fmt, stmt = NULL, expr = NULL,
       occurrence = 1L, ordinal = 1L, backend = "transcript", top_level = TRUE, in_block = NULL,
       ide_id = NULL, defer = FALSE, console = TRUE, driver = "console",
       prompt_hash = prompt_hash(template %||% ""), args_hash = NULL, template = template,
       session_id = session_id, session_file = session_file,
       context_labels = as.character(context_labels), block = NULL, anchor = NULL, indent = "")
}

#' The site of a raw location before its statement is found (contract 7.15): format (NA for a
#' document gptr cannot record into), backend and driver; no statement, anchor or block, and not
#' top-level. Fields without a value stay in the list as NULL.
#' @noRd
doc_site_base = function(raw, call, ph) {
  site = list(kind = raw$kind, path = raw$path,
              format = doc_format_of(raw$path) %||% NA_character_, stmt = NULL,
              expr = raw$expr, occurrence = raw$occurrence %||% 1L, ordinal = 1L,
              backend = switch(raw$kind, jupyter = "pending", rscript = "deferred",
                               ide = raw$backend %||% "rstudio", "file"),
              top_level = FALSE, in_block = NULL, ide_id = raw$ide_id,
              defer = identical(raw$kind, "rscript"), prompt_hash = ph,
              args_hash = args_hash(call$interp),
              template = call$template %||% call$prompt, block = NULL, anchor = NULL,
              indent = "", label = raw$label %||% NA_character_)
  site$driver = doc_driver(site)
  site
}

#' Finish a raw location into the site of contract 7.15 (format, backend, driver, anchor,
#' statement, ownership); NULL when the call is not found in that document
#' @noRd
doc_site_finish = function(raw, call, ph, call0) {
  fmt = doc_format_of(raw$path)
  spec = doc_format_get(fmt)
  if (is.null(fmt) || is.null(spec)) return(NULL)
  site = doc_site_base(raw, call, ph)
  text = if (identical(raw$kind, "ide")) raw$contents else doc_read(site$path)$lines
  anchor = doc_anchor(site, raw, text, ph, call0)
  if (is.null(anchor)) return(NULL)
  site["anchor"] = list(anchor)
  loc = spec$locate(text, site)
  site["stmt"] = list(loc$stmt)
  site$top_level = isTRUE(loc$top_level)
  site["in_block"] = list(loc$in_block)
  site$ordinal = loc$ordinal %||% 1L
  site["block"] = list(loc$owned)
  site$indent = loc$indent %||% ""
  site
}

#' The context labels of a call's symbol context items (the names a transcript statement passes)
#' @noRd
doc_context_labels = function(context) {
  if (!is.list(context)) return(character())
  labels = vapply(context, function(x) {
    if (!is.list(x) || !identical(x[["kind"]], "symbol")) return("")
    name = x[["name"]]
    if (is.character(name) && length(name) == 1L && !is.na(name)) name else ""
  }, "", USE.NAMES = FALSE)
  labels[nzchar(labels)]
}

#' Locate the calling statement of a gptr() call record (contract 7.15): a site list, the
#' console site when the call is in no document, or NULL. Sets `call$top_level`.
#'
#' The first finder that sees a running document (a srcref, a source() frame, knitr or Quarto,
#' a notebook, `Rscript --file=`) decides. When none of that document's statements holds the
#' call (a call inside a function, a later pass of a top-level loop under Rscript, an evaluated
#' text), the call is nested there (architecture 6.9.3: no block): its site has no statement and
#' is not top-level, with or without srcrefs, and it is neither a console turn nor looked up in
#' the IDE's buffer. Only an IDE location that fails falls back to the console.
#' @noRd
doc_locate = function(call) {
  template = call$template %||% call$prompt
  ph = if (is.character(template) && length(template) == 1L && !is.na(template)) {
    prompt_hash(template)
  } else {
    NA_character_
  }
  call0 = doc_strip_call(call$sys_call)
  site = NULL
  nested = FALSE
  finders = list(doc_site_srcref, doc_site_source_frame, doc_site_knitr, doc_site_jupyter,
                 doc_site_rscript, doc_site_ide)
  for (f in finders) {
    raw = tryCatch(f(call, ph, call0), error = function(e) NULL)
    if (is.null(raw)) next
    site = tryCatch(doc_site_finish(raw, call, ph, call0), error = function(e) NULL)
    if (!is.null(site)) break
    if (!identical(raw$kind, "ide")) {
      nested = TRUE
      site = tryCatch(doc_site_base(raw, call, ph), error = function(e) NULL)
      break
    }
  }
  if (is.null(site) && !nested) {
    s = call$session
    sid = if (is.null(s)) NULL else tryCatch(session_data(s)$id, error = function(e) NULL)
    site = tryCatch(doc_console_site(session_id = sid,
                                     template = if (is.na(ph)) NULL else template,
                                     context_labels = doc_context_labels(call$context)),
                    error = function(e) NULL)
  }
  if (is.environment(call)) assign("top_level", isTRUE(site$top_level), envir = call)
  site
}
