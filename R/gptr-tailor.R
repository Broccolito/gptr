# gptr-tailor.R -- gptr_tailor() and the harness object: a function called like peter() that
# carries fixed peter() arguments, the person's rules and coaching data (note, skills, review,
# rules), the call rewrite, the coaching checks, its hash, rule matching and the factory that
# registers it all (08 sections 3.1 and 3.2). Plan P29, layer L6.

#' Build a harness: peter with your own fixed arguments and coaching
#'
#' A harness is a function you call exactly like [peter()]. `gptr_tailor()` makes one from `peter`
#' or from another harness, without calling any model: it fixes `peter()` arguments such as
#' `mode`, `model`, `tools` or `extensions`, it can carry your own hard rules, and it can carry
#' *coaching*, plain data that gptr itself turns into a note added to peter's instructions, skills
#' peter can open, a review that asks peter to check its work once or twice before it stops, and
#' hard rules. Each call of the harness is the
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
#' @param rules `NULL` to keep your rules of `x`, else your own hard rules, which no coaching
#'   changes: `list(never, require)`. `never` holds up to 8 `list(rule, why)`: a call that matches
#'   `rule` is refused in every mode, also in sub-agents, with "denied by your rule". `require`
#'   holds up to 4 `list(id, any, contains, text)` or `list(id, made, text)`: when peter is about to
#'   finish without a matching call in that run, `text` is sent to it, at most twice, and the run
#'   ends with a notice naming `id`. A rule or an `any` pattern is a permission rule (see
#'   [gptr_permissions()]) of the kind `r(fn:name)`, `r(category:name)`, `r(sh:glob)`,
#'   `r(sql:keyword)` or a path glob such as `write(data/raw/**)`; it matches when any call in the
#'   code does, and `fn:` names every function the code calls. A `require` pattern names only
#'   functions or categories rated below level 3. `contains` is text the call's code must hold;
#'   `made` is `"plot"` or `"file:<glob>"` (a file inside the project changed during the run).
#'   `list()` drops your rules.
#' @param coaching `NULL` to keep the coaching of `x`, else `list(note, skills, review, rules)`:
#'   `note` one string of at most 8,000 characters; `skills` a list of
#'   `list(name, description, text)` with names such as `"survey-weights"`, descriptions of at most
#'   1,024 characters and 64 KiB in all; `review` `list(text, rounds)` with at most 2,000
#'   characters and 0 to 2 rounds (default 1); `rules` as `rules` above, refused with "denied by
#'   the coaching rule". The texts may not hold control or hidden characters, tags of gptr's own
#'   prompt blocks, or gptr's wording for a message from you or an extension.
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
  if (!is.null(rules)) spec$rules = rules
  if (!is.null(coaching)) spec$coaching = coaching
  spec$record = NULL
  spec$id = id_new("", 12L)
  spec$gptr = as.character(utils::packageVersion("gptr"))
  h = harness_from_spec(spec)
  args = spec$args
  loud = args[!vapply(args, harness_plain, NA)]
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
#' registry filters, valid rules of the person, valid coaching (`fresh` as coaching_validate())
#' @noRd
harness_spec_check = function(spec, fresh = TRUE) {
  args = if (is.list(spec)) spec$args %||% list() else NULL
  nms = names(args)
  if (!is.list(args) || (length(args) && (is.null(nms) || !all(nms %in% harness_formals()))) ||
        !rlang::is_string(spec$id)) {
    gptr_abort("This is not a valid harness: its fixed arguments or id are damaged.",
               "invalid_argument", arg = "x", expected = "a harness made by gptr_tailor()")
  }
  harness_plugins_check(args[["plugins"]])
  list(args = args, rules = coaching_rules(spec$rules, "Your"),
       coaching = coaching_validate(spec$coaching, fresh = fresh), record = spec$record,
       id = spec$id, gptr = spec$gptr)
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
    v = if (nm %in% harness_idents) {
      harness_ident(e, nm, caller, function() ...elt(i))
    } else if (identical(nm, "agents")) {
      resolve_agents(e, caller)
    } else {
      ...elt(i)
    }
    out[nm] = list(v)
  }
  out
}

#' The `peter()` arguments that resolve as identifiers (contract 6.1.3)
#' @noRd
harness_idents = c("model", "mode", "skills", "plugins", "extensions", "tools")

#' An identifier argument resolved in `caller` as peter() resolves it; `force()` gives its value
#' when the expression must be evaluated
#' @noRd
harness_ident = function(e, nm, caller, force) {
  if (ident_force_needed(e, nm, caller)) ident_value(force(), nm, e) else
    resolve_identifier(e, nm, caller)
}

#' A call's arguments with each `...` written out from the caller's dots: identifiers resolved as
#' peter() resolves them (it reads no `..i`), every other one as `..i`
#' @noRd
harness_expand = function(args, dots, envir) {
  exprs = as.list(eval(quote(substitute(list(...))), envir))[-1L]
  nms = names(exprs) %||% rep("", length(exprs))
  el = lapply(seq_along(exprs), function(i) {
    if (!nms[i] %in% harness_idents) return(as.name(paste0("..", i)))
    harness_ident(exprs[[i]], nms[i], envir, function() eval(call("...elt", i), envir))
  })
  names(el) = nms
  do.call(c, lapply(seq_along(args), function(i) if (dots[i]) el else args[i]))
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
#' for the document recorder (08 sections 3.1 and 3.6). An argument a wrapper forwards through
#' `...` counts as given; the dots are written out only when such an argument must combine.
#' @noRd
harness_call = function(fn, call, envir) {
  spec = harness_spec_check(harness_spec(fn), fresh = FALSE)
  factory = harness_factory(spec)
  args = as.list(call)[-1L]
  dots = vapply(args, identical, NA, quote(...))
  # ...names() forces no argument
  fwd = if (any(dots)) eval(quote(...names()), envir)
  join = c(intersect(names(spec$args), harness_listlike), if (!is.null(factory)) "extensions")
  if (any(fwd %in% join)) {
    args = harness_expand(args, dots, envir)
    fwd = NULL
  }
  for (nm in setdiff(names(spec$args), fwd)) {
    v = spec$args[[nm]]
    if (!nm %in% names(args)) {
      args[nm] = list(v)
    } else if (identical(nm, ".opts")) {
      args[[nm]] = as.call(list(harness_opts, v, args[[nm]]))
    } else if (nm %in% harness_listlike) {
      args[[nm]] = as.call(list(as.name("c"), v, args[[nm]]))
    }
  }
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
      "your rules: ", harness_rules_count(spec$rules), "\n",
      "coaching: note ", nchar(co$note), " characters, ", length(co$skills), " skill(s), review ",
      review, ", rules ", harness_rules_count(co$rules), "\n",
      "record: ", harness_record_text(spec$record), "\n", sep = "")
  invisible(x)
}

#' "none", or the number of never and require rules
#' @noRd
harness_rules_count = function(rules) {
  if (is.null(rules)) return("none")
  paste0(length(rules$never), " never, ", length(rules$require), " require")
}

#' Rules for people to read (HARNESS.md, RULES.md): one line per rule, or "None."
#' @noRd
harness_rules_lines = function(rules) {
  if (is.null(rules)) return("None.")
  c(vapply(rules$never, function(n) paste0("- never `", n$rule, "`: ", n$why), ""),
    vapply(rules$require, function(q) {
      what = if (is.null(q$made)) paste0("`", paste(q$any, collapse = "`, `"), "`") else
        paste0("made ", q$made)
      if (!is.null(q$contains)) what = paste0(what, ", contains \"", q$contains, "\"")
      paste0("- require ", q$id, " (", what, "): ", q$text)
    }, ""))
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

#' Is a fixed argument plain data: NULL, text, numbers, logicals and lists of them, with no
#' attribute but names? Anything else can carry code (a function, a spec, a provider, a formula)
#' @noRd
harness_plain = function(v) {
  if (length(setdiff(names(attributes(v)), "names"))) return(FALSE)
  if (is.list(v)) return(all(vapply(v, harness_plain, NA)))
  is.null(v) || is.character(v) || is.numeric(v) || is.logical(v)
}

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
    "## Your rules", "", harness_rules_lines(spec$rules)))
  write_atomic(file.path(dir, "NOTE.md"), co$note)
  write_atomic(file.path(dir, "REVIEW.md"), if (is.null(co$review)) "No review." else review)
  write_atomic(file.path(dir, "RULES.md"), harness_rules_lines(co$rules))
  for (s in co$skills) {
    d = file.path(dir, "skills", s$name)
    dir.create(d, showWarnings = FALSE)
    head = sub("\n$", "", yaml::as.yaml(list(name = s$name, description = s$description)))
    write_atomic(file.path(d, "SKILL.md"), c("---", head, "---", s$text))
  }
  invisible(dir)
}

# ------------------------------------------------------------------ the coaching (3.2)

#' Signals gptr_error_coaching naming the part (of the coaching, or with `who = "Your"` of the
#' person's rules)
#' @noRd
coaching_abort = function(part, why, who = "The coaching's") {
  gptr_abort(paste0(who, " ", part, " ", why, "."), "coaching", part = part)
}

#' Checks and normalises coaching to `list(note, skills, review, rules)`, texts redacted; with
#' `surface`, the parts outside it must equal those of `base`; `fresh = FALSE` skips the skill name
#' check of a harness being called, which passed when it was made or loaded
#' @noRd
coaching_validate = function(coaching, surface = NULL, base = NULL, fresh = TRUE) {
  co = coaching %||% list()
  parts = c("note", "skills", "review", "rules")
  nms = names(co)
  if (!is.list(co) || is.object(co) ||
        (length(co) && (is.null(nms) || !all(nms %in% parts) || anyDuplicated(nms)))) {
    gptr_abort("The coaching must be a list with the parts note, skills, review and rules.",
               "coaching", part = "coaching")
  }
  out = list(note = coaching_text(co$note %||% "", "note", 8000L),
             skills = coaching_skills(co$skills %||% list(), fresh),
             review = coaching_review(co$review), rules = coaching_rules(co$rules))
  if (is.null(surface)) return(out)
  if (!is.character(surface) || !all(surface %in% parts)) {
    gptr_abort("The coaching surface names parts among note, skills, review and rules.",
               "coaching", part = "surface")
  }
  base = coaching_validate(base)
  for (p in setdiff(parts, surface)) {
    if (!identical(out[[p]], base[[p]])) coaching_abort(p, "is outside the surface and changed")
  }
  out
}

#' One text part: a valid UTF-8 string of at most `max` characters, without control, format
#' (bidi, zero-width, tag), line or paragraph separator characters (newline and tab allowed), tags
#' of gptr's blocks or gptr's wordings; returned redacted
#' @noRd
coaching_text = function(x, part, max, who = "The coaching's") {
  bad = function(why) coaching_abort(part, why, who)
  if (!rlang::is_string(x)) bad("must be one string")
  x = as_utf8(x)
  if (!validUTF8(x)) bad("is not valid UTF-8 text")
  if (nchar(x) > max) bad(paste0("is longer than ", format(max, big.mark = ","), " characters"))
  flat = gsub("\n", "", x, fixed = TRUE)
  # literal characters, not \x{}: ASCII text with an ASCII pattern leaves PCRE out of UTF mode
  hidden = "[\\p{Cf}\\p{Zl}\\p{Zp}\U000E0000-\U000E007F]"
  if (!identical(ui_escape(flat), flat) || grepl(hidden, flat, perl = TRUE)) {
    bad("contains control, bidirectional or zero-width characters")
  }
  tags = paste0("(?i)<\\s*/?\\s*(", paste(coaching_tags(), collapse = "|"),
                "|coaching_\\w*)(?=[\\s/>])")
  if (grepl(tags, x, perl = TRUE)) bad("contains a tag of one of gptr's blocks")
  if (any(vapply(coaching_wordings, grepl, NA, x = tolower(x), fixed = TRUE))) {
    bad("imitates gptr's wording for a message from the user or an extension")
  }
  redact_hook(x, "persist")
}

#' The skills part: `list(name, description, text)` each, names unique and, with `fresh`, not
#' the name of a registered skill or of any SKILL.md gptr finds, synced or not; 64 KiB in all
#' @noRd
coaching_skills = function(skills, fresh = TRUE) {
  if (!is.list(skills) || is.object(skills)) {
    coaching_abort("skills", "must be a list of list(name, description, text)")
  }
  taken = if (fresh && length(skills)) c(registry_names("skill"), skill_discover()$name)
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

#' The rules part (or, with `who = "Your"`, the person's rules): NULL when empty, else
#' `list(never = list(list(rule, why)), require = list(list(id, any | made, contains?, text)))`,
#' with up to 8 never and 4 require rules
#' @noRd
coaching_rules = function(rules, who = "The coaching's") {
  bad = function(why) coaching_abort("rules", why, who)
  text = function(x, max) coaching_text(x, "rules", max, who)
  if (is.null(rules)) return(NULL)
  lists = function(x) is.list(x) && !is.object(x) && is.null(names(x))
  if (!is.list(rules) || is.object(rules) || (length(rules) && (is.null(names(rules)) ||
        !all(names(rules) %in% c("never", "require")) || anyDuplicated(names(rules))))) {
    bad("must be list(never, require); there are no allow or ask lists")
  }
  never = rules$never %||% list()
  need = rules$require %||% list()
  if (!lists(never) || length(never) > 8L) bad("need `never` as a list of at most 8 rules")
  if (!lists(need) || length(need) > 4L) bad("need `require` as a list of at most 4 rules")
  never = lapply(never, function(n) {
    if (!is.list(n) || length(n) != 2L || !setequal(names(n), c("rule", "why"))) {
      bad("need never rules of the form list(rule, why)")
    }
    list(rule = coaching_pattern(n$rule, FALSE, who), why = text(n$why, 300L))
  })
  need = lapply(need, function(q) {
    keys = if (is.list(q)) names(Filter(Negate(is.null), q))
    if (is.null(keys) || anyDuplicated(keys) || !all(c("id", "text") %in% keys) ||
          !all(keys %in% c("id", "any", "made", "contains", "text")) ||
          sum(c("any", "made") %in% keys) != 1L) {
      bad("need require rules of the form list(id, any or made, contains, text)")
    }
    out = list(id = text(q$id, 200L))
    if (!grepl("^[a-z0-9][a-z0-9-]*\\z", out$id, perl = TRUE)) {
      bad("need require ids that match ^[a-z0-9][a-z0-9-]*$")
    }
    pats = if (lists(q$any)) unlist(Filter(rlang::is_string, q$any)) else q$any
    if (is.null(q$any)) {
      out$made = coaching_made(q$made, who)
    } else if (!is.character(pats) || !length(pats) || length(pats) != length(q$any) ||
                 sum(nchar(pats)) > 200L) {
      bad("need `any` patterns of at most 200 characters in all")
    } else {
      out$any = vapply(pats, coaching_pattern, "", require = TRUE, who = who, USE.NAMES = FALSE)
    }
    if (!is.null(q$contains)) out$contains = text(q$contains, 100L)
    out$text = text(q$text, 500L)
    out
  })
  if (anyDuplicated(vapply(need, function(q) q$id, ""))) bad("need unique require ids")
  if (!length(never) && !length(need)) return(NULL)
  list(never = never, require = need)
}

#' One rule pattern of at most 200 characters that parses with rule_parse() as fn:, category:,
#' sh:, sql: or a path glob and can match: no `pkg::` in fn:, only categories the classifier
#' knows. A require pattern must not match an action of level 3 or above, tested conservatively
#' on the risk tables: each function it names, and each table row of each category it names, is
#' below level 3 there, and no function runs a command or a statement it is given; sh:, sql: and
#' path globs are refused, as their level comes from the command, the statement or the path.
#' Arguments can still raise a matching call to level 3, so such a call keeps counting in a
#' coaching run's risk (child_ended()).
#' @noRd
coaching_pattern = function(rule, require, who) {
  bad = function(why) coaching_abort("rules", why, who)
  rule = coaching_text(rule, "rules", 200L, who)
  p = tryCatch(rule_parse(rule), error = function(e) NULL)
  if (is.null(p) || !p$kind %in% c("fn", "category", "sh", "sql", "glob")) {
    bad(paste("need patterns such as r(fn:name), r(category:install), r(sh:cmd *), r(sql:drop)",
              "or write(data/**), never level<=, secret: or a whole tool"))
  }
  if (p$kind == "fn" && any(grepl("::", p$value, fixed = TRUE))) {
    bad("name functions in fn: without pkg::, which never matches")
  }
  fns = risk_table("functions")
  cmds = risk_table("commands")
  if (p$kind == "category" && !all(p$value %in% c(fns$category, cmds$category, "unlisted"))) {
    bad("name only categories the classifier knows")
  }
  if (require) {
    lv = switch(p$kind,
      fn = c(fns$level[fns[["function"]] %in% p$value],
             if (any(p$value %in% c(perm_shell_fns, perm_sql_fns))) 3L),
      category = c(fns$level[fns$category %in% p$value], cmds$level[cmds$category %in% p$value]),
      3L)
    if (max(0L, lv) >= 3L) {
      bad("have a require pattern that can match an action of level 3 or above")
    }
  }
  rule
}

#' A require rule's `made`: "plot", or "file:" and a glob relative to the project, without `..`
#' @noRd
coaching_made = function(made, who) {
  if (identical(made, "plot")) return(made)
  glob = if (rlang::is_string(made) && startsWith(made, "file:")) substring(made, 6L) else ""
  if (!nzchar(glob) || grepl("^(~|/|[A-Za-z]:)|\\\\|(^|/)\\.\\.(/|$)", glob) ||
        is.null(tryCatch(rule_glob_re(glob), error = function(e) NULL))) {
    coaching_abort("rules", "need `made` as \"plot\" or \"file:<glob inside the project>\"", who)
  }
  coaching_text(made, "rules", 200L, who)
}

#' Does a parsed coaching rule match a call? As rule_hit() does for deny rules, widened by the
#' classifier's scan of `r` code (08 section 3.2): fn: matches every function the code calls, at
#' any level; a write or edit glob also the files R or shell code writes, deletes or downloads
#' to; category:network also a read from a URL. The person's settings rules keep rule_hit().
#' @noRd
coaching_hit = function(p, call) {
  risk = call$risk
  if (identical(call$name, "r") && inherits(risk, "gptr_risk")) {
    hit = switch(p$kind,
      fn = any(risk$calls %in% p$value),
      glob = p$tool %in% c("write", "edit", "*") &&
        any(grepl(rule_glob_re(p$value), risk$targets$files, perl = TRUE)),
      category = "network" %in% p$value && any(risk$flagged$path_class %in% "url"),
      FALSE)
    if (hit) return(TRUE)
  }
  isTRUE(rule_hit(p, call, "deny"))
}

#' Does a call meet a require rule's pattern: one of `any` matches (coaching_hit()) and its code,
#' the call's arguments as text, holds `contains`? A `made` rule has no pattern: its result is
#' checked instead (harness_made()). Never fails: an error is no match.
#' @noRd
harness_require_hit = function(q, call) {
  isTRUE(tryCatch({
    code = paste(as.character(unlist(call$input)), collapse = "\n")
    (is.null(q$any) || any(vapply(q$any, function(r) coaching_hit(rule_parse(r), call), NA))) &&
      (is.null(q$contains) || grepl(q$contains, code, fixed = TRUE))
  }, error = function(e) FALSE))
}

#' 8 hex of the sha256 of the coaching, skills sorted by name and texts normalised as
#' prompt_hash() does (text_norm(); 08 section 3.6); empty coaching has one constant hash
#' @noRd
coaching_hash = function(coaching) {
  co = coaching %||% list()
  skills = co$skills %||% list()
  skills = skills[order(vapply(skills, function(s) s$name, ""), method = "radix")]
  skills = lapply(skills, function(s) {
    list(name = s$name, description = text_norm(s$description), text = text_norm(s$text))
  })
  review = co$review
  if (!is.null(review)) {
    review = list(text = text_norm(review$text), rounds = as.integer(review$rounds))
  }
  x = list(schema = 1L, note = text_norm(co$note %||% ""), skills = skills, review = review,
           rules = co$rules)
  substr(hash_sha256(canonical_json(x)), 1L, 8L)
}

# ------------------------------------------------------------------ the coaching factory (3.2)

#' The keyed factory that registers a harness's coaching and the person's rules in the session it
#' is loaded for: the note section `coaching_<coaching hash>`, so two harnesses' notes never shadow
#' each other in one session, the skills, the `coaching` and `harness_rules` policies (policies all
#' apply, whatever their names) and the finish hook; NULL when there is nothing to register. The
#' key is the coaching hash and the hash of the person's rules, so a continuation loads it once
#' (gptr_gateway's gateway_key_loaded()).
#' @noRd
harness_factory = function(spec) {
  co = spec$coaching
  mine = spec$rules
  review = if (!is.null(co$review) && co$review$rounds > 0L) co$review
  need = c(mine$require, co$rules$require)
  if (!nzchar(co$note) && !length(co$skills) && is.null(review) && is.null(co$rules) &&
        is.null(mine)) {
    return(NULL)
  }
  hash = coaching_hash(co)
  structure(function(gptr) {
    if (nzchar(co$note)) {
      # a budget no 8,000-character note reaches: the character cap is the only limit
      gptr$register(gptr_prompt_section(paste0("coaching_", hash),
                                        paste0(coaching_first_line, "\n", co$note),
                                        tier = "T1", order = 790L, budget = 32768L))
    }
    for (s in co$skills) {
      gptr$register(gptr_spec("skill", s$name, description = s$description, text = s$text))
    }
    if (length(co$rules$never)) {
      gptr$register(gptr_policy("coaching", harness_policy(co$rules$never, "the coaching rule"),
                                "the coaching's never rules"))
    }
    if (length(mine$never)) {
      gptr$register(gptr_policy("harness_rules", harness_policy(mine$never, "your rule"),
                                "your never rules of this harness"))
    }
    if (!is.null(review) || length(need)) harness_finish_hooks(gptr, review, need)
  }, gptr_key = paste0("gptr_harness:", hash, ":", coaching_hash(list(rules = mine))))
}

#' A policy that only denies: a call matching a never rule (coaching_hit()) is "denied by <who>
#' <rule>: <why>"; it binds the sessions the harness session starts (registry ancestors)
#' @noRd
harness_policy = function(never, who) {
  pats = lapply(never, function(n) rule_parse(n$rule))
  function(call, ctx) {
    for (i in seq_along(never)) {
      if (coaching_hit(pats[[i]], call)) {
        return(list(decision = "deny", rule = never[[i]]$rule,
                    reason = paste0("denied by ", who, " ", never[[i]]$rule, ": ",
                                    never[[i]]$why)))
      }
    }
    NULL
  }
}

#' The start of a coaching denial's reason, which the finish hook does not count as a refusal
#' @noRd
harness_coaching_denial = "denied by the coaching rule "

#' The finish hook (08 section 3.2), in the harness's own session only. A call that returns without
#' error meets the requirements whose pattern its call matched, or whose `made` its result shows;
#' its id joins `run$require_met`, which a coaching run's risk tally skips (child_ended()). After a
#' final answer, the unmet requirements' texts and then the review go as one follow-up, at most
#' twice per run and the review at most `rounds` times; nothing at the turn limit, in a blocked
#' or aborted run, with `.opts$returns`, or after a refusal other than a coaching denial. At the
#' run's end the unmet ids are a notice and a `gptr.unmet` entry.
#' @noRd
harness_finish_hooks = function(gptr, review, need) {
  runs = new.env(parent = emptyenv())
  hits = new.env(parent = emptyenv())
  state = function(id) {
    if (is.null(runs[[id]])) {
      r = new.env(parent = emptyenv())
      r$start = Sys.time()
      r$met = rep(FALSE, length(need))
      r$sent = 0L
      r$refused = FALSE
      assign(id, r, envir = runs)
    }
    runs[[id]]
  }
  gptr$on("agent_start", function(event, ctx) {
    if (rlang::is_string(event$run)) state(event$run)
    NULL
  })
  gptr$on("tool_call", function(event, ctx) {
    id = event$tool_call_id
    if (length(need) && rlang::is_string(id) && !isTRUE(event$nested)) {
      call = list(name = event$tool_name, input = event$input, risk = event$risk)
      assign(id, vapply(need, harness_require_hit, NA, call = call), envir = hits)
    }
    NULL
  })
  gptr$on("tool_result", function(event, ctx) {
    id = event$tool_call_id
    hit = if (rlang::is_string(id)) get0(id, envir = hits, inherits = FALSE)
    if (is.null(hit)) return(NULL)
    rm(list = id, envir = hits)
    if (isTRUE(event$is_error) || !rlang::is_string(event$run)) return(NULL)
    r = state(event$run)
    for (i in which(hit & !vapply(need, function(q) is.null(q$made), NA))) {
      # a file requirement already met is not walked for again
      made = need[[i]]$made
      hit[i] = (made == "plot" || !r$met[i]) && harness_made(made, event$details, r$start)
    }
    r$met = r$met | hit
    run = ctx_run(ctx)
    if (any(hit) && identical(run$id, event$run)) run$require_met = c(run$require_met, id)
    NULL
  })
  gptr$on("tool_execution_end", function(event, ctx) {
    why = event$refused
    if (rlang::is_string(why) && rlang::is_string(event$run) &&
          !startsWith(why, harness_coaching_denial)) {
      r = state(event$run)
      r$refused = TRUE
    }
    NULL
  })
  gptr$on("turn_end", function(event, ctx) {
    id = event$run
    run = ctx_run(ctx)
    if (!rlang::is_string(id) || is.null(run) || !msg_final(event$message)) return(NULL)
    r = state(id)
    texts = c(vapply(need[!r$met], function(q) q$text, ""),
              if (!is.null(review) && r$sent < review$rounds) review$text)
    if (!length(texts) || r$sent >= 2L || r$refused || !is.null(run$opts$returns) ||
          !is.null(run$blocked) || isTRUE(run$signal$aborted) || loop_at_limit(run$loop)) {
      return(NULL)
    }
    r$sent = r$sent + 1L
    ctx$send(paste(texts, collapse = "\n\n"), as = "follow_up")
    NULL
  })
  gptr$on("agent_end", function(event, ctx) {
    id = event$run
    if (!rlang::is_string(id)) return(NULL)
    unmet = unique(vapply(need[!state(id)$met], function(q) q$id, ""))
    rm(list = id, envir = runs)
    # the calls refused before their result
    rm(list = ls(hits, all.names = TRUE), envir = hits)
    if (length(unmet)) {
      gptr_inform(paste0("This run finished without: ", paste(unmet, collapse = ", ")), "notice")
      session_append(ctx$session, list(type = "custom", custom_type = "gptr.unmet",
                                       data = list(ids = as.list(unmet))))
    }
    NULL
  })
}

#' Does a result show what a `made` requirement asks for: a plot, or a file matching the glob that
#' changed since the run started (walking at most 5,000 entries of the project)?
#' @noRd
harness_made = function(made, details, start) {
  if (identical(made, "plot")) {
    return(isTRUE(details$plots > 0L) || length(details$plot_files) > 0L)
  }
  root = project_root()
  w = tryCatch(walk_tree(root, gitignore = FALSE, max_entries = 5000L), error = function(e) NULL)
  rel = w$rel[!w$is_dir & grepl(rule_glob_re(substring(made, 6L)), w$rel, perl = TRUE)]
  any(as.numeric(file.mtime(file.path(root, rel))) >= floor(as.numeric(start)), na.rm = TRUE)
}
