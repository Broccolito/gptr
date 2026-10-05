# doc-replay.R -- replay (plan P15; contract 6.4, 7.15, 11.9; IC-45..IC-52): write consent, the
# replay decision per mode (report 14 section 4.4.2 table, G7 section 3.8 undone row, IC-45
# args=), the S2 answer cache, the `document` route, replaying fresh blocks (IC-46, IC-47), the
# doc.* services, the agent_end/session_tree hooks, the console:command/console:direct handlers
# and the exports gptr_doc(), gptr_source(), gptr_blocks() and gptr_cache(). The replay mode is
# P08's replay_mode(). Layer L4.

#' Write consent for a document (IC-45): the gptr_doc() binding of this process, `record =
#' "auto"` (option or user setting; `record` only tightens in a project), a remembered answer or
#' transcript target in the user-level project file, or an interactive yes (remembered)
#' @noRd
doc_consent = function(path, ask = TRUE) {
  key = path_key(path)
  b = the$doc_binding
  if (!is.null(b$path) && identical(path_key(b$path), key)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off")) return(FALSE)
  if (identical(rec, "auto")) return(TRUE)
  pf = doc_project_get()
  rel = doc_rel(path)
  remembered = doc_project_entry(pf, "record", rel)
  if (identical(remembered, "auto")) return(TRUE)
  if (identical(remembered, "off")) return(FALSE)
  target = doc_remembered_target(pf)
  if (!is.null(target) && identical(path_key(target), key)) return(TRUE)
  if (!ask || !gptr_can_prompt()) return(FALSE)
  yes = isTRUE(gptr_confirm(paste0("Record gptr blocks into ", rel, "?")))
  doc_project_remember(rel, if (yes) "auto" else "off")
  yes
}

#' Could consent still be given for a document (without asking now)? Consent exists, or a human
#' can answer and nothing refuses it (decides whether the route keeps a site for recording)
#' @noRd
doc_consent_possible = function(path) {
  if (doc_consent(path, ask = FALSE)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off") || !gptr_can_prompt()) return(FALSE)
  remembered = doc_project_entry(doc_project_get(), "record", doc_rel(path))
  !identical(remembered, "off")
}

#' One entry of a top-level object (`record` or `transcript`) of the user-level project file
#' `pf`; NULL when that key is absent or is not a JSON object (doc_project_update() replaces
#' such a value, so a reader ignores it)
#' @noRd
doc_project_entry = function(pf, key, name) {
  obj = if (is.list(pf)) pf[[key]] else NULL
  if (!is.list(obj) || is.null(names(obj)) || length(name) != 1L || is.na(name)) return(NULL)
  obj[[name]]
}

#' The remembered console transcript target of the user-level project file `pf` as an absolute
#' path; NULL for none, `"off"`, or a target IC-52 does not allow: one outside the project root,
#' without a document extension, or on a control, protected, critical or instructions path (the
#' rule of P15 Task 8's doc_target_valid())
#' @noRd
doc_remembered_target = function(pf = doc_project_get()) {
  target = doc_project_entry(pf, "transcript", "target")
  if (!is.character(target) || length(target) != 1L || is.na(target) || !nzchar(target) ||
        identical(target, "off")) {
    return(NULL)
  }
  full = tryCatch(doc_abs(target), error = function(e) NULL)
  if (is.null(full) || is.null(doc_format_of(full))) return(NULL)
  root = path_key(project_root())
  if (!startsWith(path_key(full), paste0(sub("/$", "", root), "/"))) return(NULL)
  cls = tryCatch(path_class(full), error = function(e) "unknown")
  if (any(cls %in% c("control", "protected", "critical", "instructions", "url", "wildcard"))) {
    return(NULL)
  }
  full
}

#' Refuse a control-category export called from model code during a run unless the dispatcher
#' approved exactly this call (IC-53; the one-shot token in `run$signal$control`, as P08's
#' control_check() reads it). P08's control_check() is L6 and outside IC-33's kernel SDK, so
#' this L4 copy keeps its token protocol and, like it and P06's session_control_check(), names
#' the running tool (else "r") in the refusal.
#' @noRd
doc_control_guard = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  sig = run$signal
  ok = if (is.environment(sig)) sig$control %||% character() else character()
  i = match(what, ok)
  if (!is.na(i)) {
    sig$control = ok[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0(what, "() changes what gptr records and was called from model code ",
                      "during a run."),
               "Only you can make this change: call it yourself outside the run."),
             "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
             how_to_allow = "call it yourself outside gptr(), or approve the r call when asked",
             session = run$session)
}

#' The S2 cache key of contract 11.9 (IC-45, IC-47)
#' @noRd
s2_key = function(doc, block, part = "", prompt = "", args = "") {
  hash_sha256(canonical_json(list(schema = 2L, doc = doc, block = block, part = part %||% "",
                                  prompt = prompt %||% "", args = args %||% "")))
}

#' The S2 file of a key: `<root>/cache/s2/<2 hex>/<sha256>.json`
#' @noRd
s2_path = function(key) {
  file.path(doc_root(), "cache", "s2", substr(key, 1L, 2L), paste0(key, ".json"))
}

#' Read an S2 record (NULL on a miss, and for a file that is not a JSON object)
#' @noRd
s2_get = function(key) {
  f = s2_path(key)
  if (!file.exists(f)) return(NULL)
  x = tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
  if (is.list(x) && !is.null(names(x))) x else NULL
}

#' Write an S2 record: `{block, doc, part, prompt, model, answer, usage, cost, session, turn,
#' date}` plus any provenance the caller adds (IC-74: provider, model digest, locality, image
#' digests), kept as given; the answer is redacted with the persist profile at ingress
#' @noRd
s2_put = function(key, record) {
  record$answer = redact(as_utf8(record$answer %||% ""), "persist")
  f = s2_path(key)
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  write_atomic(f, json_encode(record))
  invisible(f)
}
