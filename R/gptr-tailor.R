# gptr-tailor.R -- gptr_tailor() and the harness object: a function called like peter() that
# carries fixed peter() arguments and coaching data (note, skills, review), the call rewrite, the
# coaching checks, its hash and the factory that registers it (08 sections 3.1 and 3.2). Plan P29,
# layer L6.

#' Build a harness: peter with your own fixed arguments and coaching
#'
#' A harness is a function you call exactly like [peter()]. `gptr_tailor()` makes one from `peter`
#' or from another harness, without calling any model: it fixes `peter()` arguments such as
#' `mode`, `model`, `tools` or `extensions`, and it can carry *coaching*, plain text that gptr
#' itself turns into a note added to peter's instructions, skills peter can open, and a review that
#' asks peter to check its work once or twice before it stops. Each call of the harness is the
#' same call as `peter()` with those arguments added, so objects, `envir`, `{name}`
#' interpolation, [gptr_last()], pipes, [lapply()] and [do.call()] behave as with `peter()`.
#'
#' Arguments you give in a call win over the fixed ones, except that `tools`, `extensions`,
#' `plugins` and `skills` add to the fixed values and `.opts` entries replace them by name. The
#' same rule applies when you tailor a harness again; `NULL` drops a fixed single value.
#'
#' To share a harness, save it with [saveRDS()]. Treat a harness from someone else like an R
#' script from them: functions among its fixed arguments run when you call it. Load it with
#' `gptr_tailor(readRDS(file))`, which rebuilds it, checks its coaching and shows any code it
#' carries.
#'
#' @param x `peter` or a harness to start from.
#' @param ... Named `peter()` arguments to fix, resolved now as `peter()` resolves them (so
#'   `mode = auto` is `"auto"`). `plugins` cannot hold `"+name"` or `"-name"` filters, which would
#'   change the whole R session.
#' @param rules Reserved for your own hard rules; not available yet, so it must be `NULL`.
#' @param coaching `NULL` to keep the coaching of `x`, else `list(note, skills, review)`: `note`
#'   one string of at most 8,000 characters; `skills` a list of `list(name, description, text)`
#'   with names such as `"survey-weights"`, descriptions of at most 1,024 characters and 64 KiB in
#'   all; `review` `list(text, rounds)` with at most 2,000 characters and 0 to 2 rounds (default
#'   1). The texts may not hold control or hidden characters, tags of gptr's own prompt blocks, or
#'   gptr's wording for a message from you or an extension.
#' @param dir A folder to write the harness to for people to read or keep in git (`HARNESS.md`,
#'   `NOTE.md`, `REVIEW.md`, `RULES.md` and `skills/<name>/SKILL.md`). gptr never reads it back.
#' @return A harness, a function of class `gptr_harness` with a new id and an empty record
#'   (invisibly when `dir` is given). `h$coaching` and `h$record` show its coaching and record,
#'   and `h$report` the last full coaching report of this R session.
#' @examples
#' fake = gptr_fake_provider(list("The data has 32 rows.", "Checked: 32 rows."))
#' count_peter = gptr_tailor(peter, model = fake, coaching = list(
#'   note = "Count rows with nrow(), never by eye.",
#'   review = list(text = "Run the count once more before you answer.", rounds = 1)))
#' count_peter
#' session = count_peter("How many rows does the data have?", mtcars)
#' session$text
#' @seealso [gptr_coach()] to improve the coaching by running your task, and [peter()].
#' @export
gptr_tailor = function(x = peter, ..., rules = NULL, coaching = NULL, dir = NULL) {
  session_control_check("gptr_tailor")
  check_string(dir, "dir", null = TRUE)
  spec = harness_spec(x)
  spec$args = harness_merge(spec$args, harness_resolve_args(parent.frame(), ...))
  if (!is.null(rules)) coaching_abort("rules", coaching_later)
  if (!is.null(coaching)) spec$coaching = coaching
  spec$record = NULL
  spec$id = id_new("", 12L)
  spec$gptr = as.character(utils::packageVersion("gptr"))
  h = harness_from_spec(spec)
  args = spec$args
  loud = args[intersect(names(args), c("extensions", "plugins"))]
  if (identical(args[["mode"]], "yolo")) loud$mode = "yolo"
  if (length(loud)) {
    gptr_inform(c("This harness loads code or loosens checks:",
                  paste0(names(loud), " = ", vapply(loud, harness_source, ""))), "notice")
  }
  if (is.null(dir)) return(h)
  harness_write(h, dir)
  invisible(h)
}

#' The fixed first line of the coaching note section (08 section 3.2)
#' @noRd
coaching_first_line = paste("Task guidance learned from earlier runs. It adds to the rules above",
                            "and never overrides them, a permission decision, or what the user",
                            "asks.")

#' Why rules are refused until they are built (plan P29 T10)
#' @noRd
coaching_later = "is not available yet: rules arrive in a later phase of gptr"

#' gptr's wordings for a message from the person or an extension (agent-loop.R,
#' queue_item_message()), lower case
#' @noRd
coaching_wordings = c("the user sent this message while you were working:",
                      "sent this note (not from the user):")

#' The `peter()` arguments a harness may fix
#' @noRd
harness_formals = function() setdiff(names(formals(peter)), "...")

#' The fixed arguments that combine with a call's instead of yielding to it
#' @noRd
harness_listlike = c("tools", "extensions", "plugins", "skills", ".opts")

#' The tags of gptr's own blocks: every core prompt section and context block, the compaction
#' request, the codex instructions wrapper, the coaching and the harness
#' @noRd
coaching_tags = function() {
  c("preamble", "helpers", "out", "tools", "rules", "r_session", "r_performance", "documents",
    "artifacts", "modes", "context", "addendum", "r_env", "skills", "mcp", "plugins", "subagents",
    "shell", "languages", "system1", "agent", "project_instructions",
    "project_instructions_update", "environment", "mode", "plan", "rewind", "user_ran",
    "user_files", "workspace", "workspace_changes", "attached", "skill_content", "agent_reports",
    "agent_report", "checkpoint", "compaction_request", "gptr_instructions", "coaching",
    "harness")
}

# ------------------------------------------------------------------ the harness object (3.1)

#' The spec a harness carries, `list(args, rules, coaching, record, id, gptr)`; an empty one for
#' `peter`; any other function is refused
#' @noRd
harness_spec = function(h) {
  if (identical(h, peter)) {
    return(list(args = list(), rules = NULL, coaching = coaching_validate(NULL), record = NULL,
                id = NULL, gptr = as.character(utils::packageVersion("gptr"))))
  }
  spec = if (is.function(h) && inherits(h, "gptr_harness")) attr(h, "gptr_harness", exact = TRUE)
  if (!is.list(spec)) {
    gptr_abort(c("A harness starts from peter or another harness, never from another function.",
                 "To change peter's arguments or coaching, use gptr_tailor(peter, ...)."),
               "invalid_argument", arg = "x", expected = "peter or a gptr_harness")
  }
  spec
}

#' A harness from a spec: the standard body in gptr's namespace, the spec checked
#' @noRd
harness_from_spec = function(spec) {
  h = utils::removeSource(function(...) harness_call(sys.function(), sys.call(), parent.frame()))
  environment(h) = topenv()
  structure(h, class = c("gptr_harness", "function"), gptr_harness = harness_spec_check(spec))
}

#' Checks a spec (made, loaded or called): fixed arguments are named peter() arguments without
#' registry filters, no rules yet, valid coaching
#' @noRd
harness_spec_check = function(spec) {
  args = if (is.list(spec)) spec$args %||% list() else NULL
  nms = names(args)
  if (!is.list(args) || (length(args) && (is.null(nms) || !all(nms %in% harness_formals()))) ||
        !rlang::is_string(spec$id)) {
    gptr_abort("This is not a valid harness: its fixed arguments or id are damaged.",
               "invalid_argument", arg = "x", expected = "a harness made by gptr_tailor()")
  }
  harness_plugins_check(args[["plugins"]])
  if (!is.null(spec$rules)) coaching_abort("rules", coaching_later)
  list(args = args, rules = NULL, coaching = coaching_validate(spec$coaching),
       record = spec$record, id = spec$id, gptr = spec$gptr)
}

#' Refuses registry filters among fixed plugins (they change the whole R process)
#' @noRd
harness_plugins_check = function(plugins) {
  p = as.character(unlist(Filter(is.character, gateway_list(plugins))))
  if (any(grepl("^[+-]", p))) {
    gptr_abort(c("A harness cannot fix plugin filters such as \"-name\" in `plugins`: they change",
                 "every later call of this R session. Pass them in a call instead."),
               "invalid_argument", arg = "plugins", expected = "plugin names without + or -")
  }
  invisible(plugins)
}

#' The fixed arguments of a gptr_tailor() call, resolved in the caller as peter() resolves them
#' @noRd
harness_resolve_args = function(caller, ...) {
  exprs = as.list(substitute(list(...)))[-1L]
  nms = ...names() %||% rep("", ...length())
  nms[is.na(nms)] = ""
  bad = nms[!nms %in% harness_formals()]
  if (length(bad)) {
    what = if (any(!nzchar(bad))) "an unnamed argument" else paste0("`", bad[1L], "`")
    gptr_abort(paste0("gptr_tailor() fixes named peter() arguments, not ", what, "."),
               "invalid_argument", arg = "...", expected = "named peter() arguments")
  }
  if (anyDuplicated(nms)) {
    gptr_abort(paste0("`", nms[anyDuplicated(nms)], "` is given more than once."),
               "invalid_argument", arg = "...", expected = "each argument once")
  }
  out = list()
  for (i in seq_along(nms)) {
    nm = nms[i]
    e = exprs[[i]]
    v = if (nm %in% c("model", "mode", "skills", "plugins", "extensions", "tools")) {
      if (ident_force_needed(e, nm, caller)) ident_value(...elt(i), nm, e) else
        resolve_identifier(e, nm, caller)
    } else if (identical(nm, "agents")) {
      resolve_agents(e, caller)
    } else {
      ...elt(i)
    }
    out[nm] = list(v)
  }
  out
}

#' Merges fixed arguments: list-like ones combine (`.opts` by name), single values are replaced,
#' and a NULL single value drops the fixed one
#' @noRd
harness_merge = function(old, new) {
  for (nm in names(new)) {
    v = new[[nm]]
    if (identical(nm, ".opts") && !is.null(old[[nm]])) {
      v = harness_opts(old[[nm]], v)
    } else if (nm %in% harness_listlike && !is.null(old[[nm]])) {
      v = ident_combine(list(old[[nm]], v))
    }
    old[nm] = list(v)
  }
  old[!vapply(old, is.null, NA)]
}

#' `.opts` entries of a call replace the fixed ones by name
#' @noRd
harness_opts = function(fixed, given) {
  fixed[names(given)] = given
  fixed
}

#' Calls `peter` as the person called the harness, with the fixed arguments and the coaching
#' factory added, in the person's frame; the call carries `gptr_harness = list(fn, hash, call)`
#' for the document recorder (08 sections 3.1 and 3.6)
#' @noRd
harness_call = function(fn, call, envir) {
  spec = harness_spec_check(harness_spec(fn))
  args = as.list(call)[-1L]
  for (nm in names(spec$args)) {
    v = spec$args[[nm]]
    if (!nm %in% names(args)) {
      args[nm] = list(v)
    } else if (identical(nm, ".opts")) {
      args[[nm]] = as.call(list(harness_opts, v, args[[nm]]))
    } else if (nm %in% harness_listlike) {
      args[[nm]] = as.call(list(as.name("c"), v, args[[nm]]))
    }
  }
  factory = harness_factory(spec)
  if (!is.null(factory)) {
    ext = args[["extensions"]]
    args[["extensions"]] = if (is.null(ext)) factory else as.call(list(as.name("c"), ext, factory))
  }
  new = as.call(c(list(peter), args))
  head = call[[1L]]
  fn_name = if (is.language(head)) paste(deparse_code(head, nlines = 1L), collapse = "") else NA
  attr(new, "gptr_harness") = list(fn = as.character(fn_name),
                                   hash = coaching_hash(spec$coaching), call = call)
  eval(new, envir)
}

#' @export
`$.gptr_harness` = function(x, name) {
  spec = harness_spec(x)
  switch(name,
    coaching = spec$coaching,
    record = spec$record,
    report = the$coach_reports[[spec$id]],
    gptr_abort(paste0("A harness has $coaching, $record and $report, not $", name, "."),
               "unknown_member", name = name, available = c("coaching", "record", "report")))
}

#' @export
`[[.gptr_harness` = function(x, i, ...) {
  check_string(i, "i")
  `$.gptr_harness`(x, i)
}

#' Refuses changing a harness in place
#' @noRd
harness_readonly = function(field) {
  gptr_abort(c("A harness is read-only.",
               paste0("Make a new one instead: gptr_tailor(h, ...) with the arguments or the ",
                      "coaching = list(...) you want.")),
             "readonly", object = "gptr_harness", field = as.character(field)[1L])
}

#' @export
`$<-.gptr_harness` = function(x, name, value) harness_readonly(name)

#' @export
`[[<-.gptr_harness` = function(x, i, ..., value) harness_readonly(i)

#' @export
print.gptr_harness = function(x, ...) {
  spec = harness_spec(x)
  co = spec$coaching
  args = spec$args
  fixed = if (length(args)) {
    paste0(names(args), " = ", vapply(args, harness_label, ""), collapse = ", ")
  } else {
    "none"
  }
  review = if (is.null(co$review)) "none" else paste0(co$review$rounds, " round(s)")
  cat("<gptr_harness ", spec$id, "> built on peter (gptr ", spec$gptr, ")\n",
      "fixed: ", fixed, "\n",
      "coaching: note ", nchar(co$note), " characters, ", length(co$skills), " skill(s), review ",
      review, "\n",
      "record: ", harness_record_text(spec$record), "\n", sep = "")
  invisible(x)
}

#' A short label of a fixed argument: functions as <function>, specs by kind and name
#' @noRd
harness_label = function(v) {
  if (is.function(v)) return("<function>")
  if (inherits(v, "gptr_spec")) return(paste0("<", v[["kind"]], " ", v[["name"]], ">"))
  if (!is.list(v)) return(paste(deparse_code(v, width.cutoff = 500L), collapse = " "))
  nm = names(v) %||% rep("", length(v))
  paste0("list(", paste0(ifelse(nzchar(nm), paste0(nm, " = "), ""), vapply(v, harness_label, ""),
                         collapse = ", "), ")")
}

#' A fixed argument as R source (functions in full)
#' @noRd
harness_source = function(v) paste(deparse_code(v), collapse = "\n")

#' One line for a harness record: none, or the decision with its reason and the number of runs
#' @noRd
harness_record_text = function(record) {
  if (is.null(record)) return("none")
  paste0(record$decision %||% "unknown",
         if (rlang::is_string(record$reason)) paste0(" (", record$reason, ")"),
         ", ", length(record$runs), " run(s)")
}

#' Writes the harness for people (never read back): HARNESS.md, NOTE.md, REVIEW.md, RULES.md and
#' skills/<name>/SKILL.md
#' @noRd
harness_write = function(h, dir) {
  spec = harness_spec(h)
  co = spec$coaching
  dir.create(file.path(dir, "skills"), recursive = TRUE, showWarnings = FALSE)
  args = spec$args
  fixed = paste0(names(args), " = ", vapply(args, harness_source, ""))
  review = c(paste0("Rounds: ", co$review$rounds), "", co$review$text)
  write_atomic(file.path(dir, "HARNESS.md"), c(
    paste0("# Harness ", spec$id), "",
    paste0("Built on peter with gptr ", spec$gptr, ". gptr never reads this folder back."), "",
    "## Fixed arguments", "", "```r", if (length(args)) fixed else "# none", "```", "",
    "## Your rules", "", "None.", "",
    "## Record", "", harness_record_text(spec$record)))
  write_atomic(file.path(dir, "NOTE.md"), co$note)
  write_atomic(file.path(dir, "REVIEW.md"), if (is.null(co$review)) "No review." else review)
  write_atomic(file.path(dir, "RULES.md"), "None.")
  for (s in co$skills) {
    d = file.path(dir, "skills", s$name)
    dir.create(d, showWarnings = FALSE)
    head = sub("\n$", "", yaml::as.yaml(list(name = s$name, description = s$description)))
    write_atomic(file.path(d, "SKILL.md"), c("---", head, "---", s$text))
  }
  invisible(dir)
}

# ------------------------------------------------------------------ the coaching (3.2)

#' Signals gptr_error_coaching naming the part
#' @noRd
coaching_abort = function(part, why) {
  gptr_abort(paste0("The coaching's ", part, " ", why, "."), "coaching", part = part)
}

#' Checks and normalises coaching to `list(note, skills, review, rules)`, texts redacted; with
#' `surface`, the parts outside it must equal those of `base`
#' @noRd
coaching_validate = function(coaching, surface = NULL, base = NULL) {
  co = coaching %||% list()
  parts = c("note", "skills", "review", "rules")
  nms = names(co)
  if (!is.list(co) || is.object(co) ||
        (length(co) && (is.null(nms) || !all(nms %in% parts) || anyDuplicated(nms)))) {
    gptr_abort("The coaching must be a list with the parts note, skills, review and rules.",
               "coaching", part = "coaching")
  }
  if (!is.null(co$rules)) coaching_abort("rules", coaching_later)
  out = list(note = coaching_text(co$note %||% "", "note", 8000L),
             skills = coaching_skills(co$skills %||% list()),
             review = coaching_review(co$review), rules = NULL)
  if (is.null(surface)) return(out)
  if (!is.character(surface) || !all(surface %in% parts)) {
    gptr_abort("The coaching surface names parts among note, skills, review and rules.",
               "coaching", part = "surface")
  }
  if ("rules" %in% surface) coaching_abort("rules", coaching_later)
  base = coaching_validate(base)
  for (p in setdiff(parts, surface)) {
    if (!identical(out[[p]], base[[p]])) coaching_abort(p, "is outside the surface and changed")
  }
  out
}

#' One text part: a valid UTF-8 string of at most `max` characters, without control, bidi or
#' zero-width characters (newline and tab allowed), tags of gptr's blocks or gptr's wordings;
#' returned redacted
#' @noRd
coaching_text = function(x, part, max) {
  if (!rlang::is_string(x)) coaching_abort(part, "must be one string")
  x = as_utf8(x)
  if (!validUTF8(x)) coaching_abort(part, "is not valid UTF-8 text")
  if (nchar(x) > max) {
    coaching_abort(part, paste0("is longer than ", format(max, big.mark = ","), " characters"))
  }
  flat = gsub("\n", "", x, fixed = TRUE)
  if (!identical(ui_escape(flat), flat)) {
    coaching_abort(part, "contains control, bidirectional or zero-width characters")
  }
  tags = paste0("(?i)<\\s*/?\\s*(", paste(coaching_tags(), collapse = "|"), ")(?=[\\s/>])")
  if (grepl(tags, x, perl = TRUE)) coaching_abort(part, "contains a tag of one of gptr's blocks")
  if (any(vapply(coaching_wordings, grepl, NA, x = tolower(x), fixed = TRUE))) {
    coaching_abort(part, "imitates gptr's wording for a message from the user or an extension")
  }
  redact_hook(x, "persist")
}

#' The skills part: `list(name, description, text)` each, names new and unique, 64 KiB in all
#' @noRd
coaching_skills = function(skills) {
  if (!is.list(skills) || is.object(skills)) {
    coaching_abort("skills", "must be a list of list(name, description, text)")
  }
  taken = if (length(skills)) registry_names("skill") else character()
  out = lapply(unname(skills), function(s) {
    if (!is.list(s) || length(s) != 3L || !setequal(names(s), c("name", "description", "text"))) {
      coaching_abort("skills", "must each be list(name, description, text)")
    }
    if (!rlang::is_string(s$name) || !grepl("^[a-z0-9][a-z0-9-]*\\z", s$name, perl = TRUE)) {
      coaching_abort("skills", "need names that match ^[a-z0-9][a-z0-9-]*$")
    }
    if (s$name %in% taken) coaching_abort("skills", paste0("reuse the skill name ", s$name))
    list(name = s$name, description = coaching_text(s$description, "skills", 1024L),
         text = coaching_text(s$text, "skills", 65536L))
  })
  nms = vapply(out, function(s) s$name, "")
  if (anyDuplicated(nms)) coaching_abort("skills", "need unique names")
  if (sum(nchar(unlist(out), type = "bytes")) > 65536L) {
    coaching_abort("skills", "exceed 64 KiB in all")
  }
  out
}

#' The review part: NULL, or `list(text, rounds)` with 0 to 2 rounds (default 1)
#' @noRd
coaching_review = function(review) {
  if (is.null(review)) return(NULL)
  if (!is.list(review) || is.object(review) || !all(names(review) %in% c("text", "rounds"))) {
    coaching_abort("review", "must be list(text, rounds)")
  }
  rounds = review$rounds %||% 1L
  if (!is.numeric(rounds) || length(rounds) != 1L || !rounds %in% 0:2) {
    coaching_abort("review", "needs rounds of 0, 1 or 2")
  }
  list(text = coaching_text(review$text, "review", 2000L), rounds = as.integer(rounds))
}

#' 8 hex of the sha256 of the coaching, skills sorted by name and texts normalised as
#' prompt_hash() does (08 section 3.6); empty coaching has one constant hash
#' @noRd
coaching_hash = function(coaching) {
  co = coaching %||% list()
  norm = function(x) gsub("[ \t]*\r?\n[ \t]*", "\n", trimws(as_utf8(x)))
  skills = co$skills %||% list()
  skills = skills[order(vapply(skills, function(s) s$name, ""), method = "radix")]
  skills = lapply(skills, function(s) {
    list(name = s$name, description = norm(s$description), text = norm(s$text))
  })
  review = co$review
  if (!is.null(review)) review = list(text = norm(review$text), rounds = as.integer(review$rounds))
  x = list(schema = 1L, note = norm(co$note %||% ""), skills = skills, review = review,
           rules = co$rules)
  substr(hash_sha256(canonical_json(x)), 1L, 8L)
}

# ------------------------------------------------------------------ the coaching factory (3.2)

#' The keyed factory that registers a harness's coaching in the session it is loaded for: the note
#' section, the skills and the review finish hook; NULL when there is nothing to register. The key
#' is the coaching hash, so a continuation loads it once (gptr_gateway's gateway_key_loaded()).
#' @noRd
harness_factory = function(spec) {
  co = spec$coaching
  if (!nzchar(co$note) && !length(co$skills) && is.null(co$review)) return(NULL)
  # T10 adds the `coaching` and `harness_rules` policies, the person's rules to the key, and the
  # `require` part of the finish hook
  structure(function(gptr) {
    if (nzchar(co$note)) {
      # a budget no 8,000-character note reaches: the character cap is the only limit
      gptr$register(gptr_prompt_section("coaching", paste0(coaching_first_line, "\n", co$note),
                                        tier = "T1", order = 790L, budget = 32768L))
    }
    for (s in co$skills) {
      gptr$register(gptr_spec("skill", s$name, description = s$description, text = s$text))
    }
    if (!is.null(co$review) && co$review$rounds > 0L) harness_review_hooks(gptr, co$review)
  }, gptr_key = paste0("gptr_harness:", coaching_hash(co)))
}

#' The review part of the finish hook: after a final answer, the review text as a follow-up, at
#' most `rounds` times per run; nothing at the turn limit, in a blocked or aborted run, in a run
#' with `.opts$returns`, or after a refused call (session records: only the harness's own session)
#' @noRd
harness_review_hooks = function(gptr, review) {
  sent = new.env(parent = emptyenv())
  refused = new.env(parent = emptyenv())
  gptr$on("tool_execution_end", function(event, ctx) {
    # T10: a denial by the coaching policy is no refusal
    if (rlang::is_string(event$refused) && rlang::is_string(event$run)) {
      assign(event$run, TRUE, envir = refused)
    }
    NULL
  })
  gptr$on("turn_end", function(event, ctx) {
    id = event$run
    run = ctx_run(ctx)
    if (!rlang::is_string(id) || is.null(run) || !msg_final(event$message)) return(NULL)
    n = get0(id, envir = sent, inherits = FALSE, ifnotfound = 0L)
    if (n >= review$rounds || exists(id, envir = refused, inherits = FALSE) ||
          !is.null(run$opts$returns) || !is.null(run$blocked) || isTRUE(run$signal$aborted) ||
          loop_at_limit(run$loop)) {
      return(NULL)
    }
    assign(id, n + 1L, envir = sent)
    ctx$send(review$text, as = "follow_up")
    NULL
  })
}
