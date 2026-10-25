# console-commands.R -- the slash commands of architecture 6.17 as `command` specs (P14, layer L5,
# area console; contract 10.2 kind 10). The console only dispatches: /undo, /redo, /rewind and
# /checkpoints are registered by P16 and prompt templates by P17 (IC-31). Exports of later plans
# (gptr_doc(), gptr_rewind(), gptr_skills(), gptr_mcp()) are reached through ns_fun(); exports of
# other layers are called as gptr::<name>() (plan ambiguity 1).

#' The command specs registered by builtin_console()
#' @noRd
console_commands = function() {
  list(
    gptr_command("help", cmd_help, "Show the commands and the input syntax: /help [command]"),
    gptr_command("exit", cmd_exit, "Leave the console; the session is returned invisibly"),
    gptr_command("quit", cmd_exit, "Leave the console (same as /exit)"),
    gptr_command("q", cmd_exit, "Leave the console (same as /exit)"),
    gptr_command("model", cmd_model, "Show or switch the model: /model [provider/model or alias]"),
    gptr_command("mode", cmd_mode,
                 "Show or switch the permission mode: /mode [plan|manual|edits|auto|yolo]"),
    gptr_command("plan", cmd_plan, "Switch to plan mode (read-only exploration, then a plan)"),
    gptr_command("tools", cmd_tools, "List the direct tools and the peter$ members"),
    gptr_command("env", cmd_env,
                 "List the objects, or those whose names contain text: /env [text]"),
    gptr_command("compact", cmd_compact, "Compact the conversation now: /compact [focus]"),
    gptr_command("cost", cmd_cost, "Tokens and cost of this session"),
    gptr_command("context", cmd_context, "Token ledger of the last request"),
    gptr_command("status", cmd_status, "Session, model, mode, document and queued messages"),
    gptr_command("clear", cmd_clear, "Start a new conversation; objects are kept"),
    gptr_command("resume", cmd_resume, "List stored sessions, or continue one: /resume [id]"),
    gptr_command("fork", cmd_fork, "Fork the session and continue on the fork"),
    gptr_command("doc", cmd_doc, "Show or bind the history document: /doc [path]"),
    gptr_command("skills", cmd_skills, "List the skills"),
    gptr_command("skill", cmd_skill, "Use a skill for the next prompt: /skill:<name> [request]"),
    gptr_command("mcp", cmd_mcp, "List the MCP servers"),
    gptr_command("permissions", cmd_permissions,
                 paste("Show or change the rules of this R session:",
                       "/permissions [<verb> <rule>] (allow, ask, deny or remove)")),
    gptr_command("retry", cmd_retry, "Undo the last turn and send its prompt again")
  )
}

#' Split a command line into list(name, args, full, rest); NULL when `text` is not a command
#'
#' "/a:b c" gives name "a" and args "b c" (the `/skill:<name> request` form), full "a:b" and rest
#' "c"; a command registered under the whole token (a plugin command `<plugin>:<cmd>`, contract
#' 11.12) is looked up first, with `rest` as its arguments.
#' @noRd
command_parse = function(text) {
  m = regmatches(text, regexec("^/([^[:space:]:]+)(:([^[:space:]]*))?[[:space:]]*(.*)$",
                               text))[[1L]]
  if (!length(m)) return(NULL)
  rest = trimws(m[[5L]])
  full = if (nzchar(m[[4L]])) paste0(m[[2L]], ":", m[[4L]]) else m[[2L]]
  list(name = m[[2L]], args = trimws(paste(m[[4L]], rest)), full = full, rest = rest)
}

#' Run one slash command line through its `command` spec
#'
#' The line first passes the `input` event with source "repl" (contract 10.4): a hook may handle
#' it or transform it (into another command, or a prompt sent through `send(text)`). A line that
#' is still a command goes out on the `console:command` channel (P15 records it as a comment). A
#' character result is printed escaped (a `cli_ansi_string`, whose untrusted parts its handler
#' escaped, with its styles), `list(prompt =)` is sent, and an error is reported on stderr (the
#' input counts as handled); where lines keep the margin a blank row follows what is printed, as
#' after a run's status line.
#' @return Invisibly "unknown", "error", "prompt" or "done".
#' @noRd
console_command = function(text, session = NULL, send = NULL) {
  if (is.null(command_parse(text))) return(invisible("unknown"))
  ev = ev_dispatch("input", ev_new("input", text = text, source = "repl"), session = session)
  if (identical(ev$action, "handled")) return(invisible("done"))
  text = trimws(ev$text)
  cmd = command_parse(text)
  if (is.null(cmd)) {
    if (!nzchar(text) || !is.function(send)) return(invisible("unknown"))
    send(text)
    return(invisible("prompt"))
  }
  ev_dispatch("console:command", list(data = list(text = text)), session = session)
  if (is.null(registry_get("command", cmd$full, session = session)) &&
      is.null(registry_get("command", cmd$name, session = session))) {
    console_templates_sync()
  }
  spec = registry_get("command", cmd$full, session = session)
  args = cmd$rest
  if (is.null(spec)) {
    spec = registry_get("command", cmd$name, session = session)
    args = cmd$args
  }
  say = function(...) {
    console_notice(...)
    if (nzchar(console_pad())) console_write("")
  }
  if (is.null(spec)) {
    say("Unknown command /", console_escape(cmd$full, FALSE), ". Type /help for the list.",
        .error = TRUE)
    return(invisible("unknown"))
  }
  ctx = (if (!is.null(session)) session_live(session)$ctx) %||% ctx_new(session)
  out = tryCatch(spec$handler(args, ctx), error = function(e) {
    say("Error in /", console_escape(spec$name, FALSE), ": ", console_escape(conditionMessage(e)),
        .error = TRUE)
    e
  })
  if (inherits(out, "error")) return(invisible("error"))
  if (is.list(out) && rlang::is_string(out$prompt) && nzchar(out$prompt)) {
    if (is.function(send)) send(out$prompt)
    return(invisible("prompt"))
  }
  if (is.character(out)) {
    lines = if (inherits(out, "cli_ansi_string")) {
      unlist(strsplit(out, "\n", fixed = TRUE))
    } else {
      console_lines(out)
    }
    say(paste(lines, collapse = "\n"))
  }
  invisible("done")
}

#' Register the prompt templates now (the `templates.sync` service, P17): a session registers
#' them when it starts, which in the console is after the first prompt (D-252)
#' @noRd
console_templates_sync = function() {
  if (ext_service_has("templates.sync")) ext_service_get("templates.sync")()
  invisible(NULL)
}

#' The history document `s` records into, or before the console's first prompt (`s` NULL) the
#' gptr_doc() binding or the transcript the project remembers (the `doc.site` service, P15), or
#' NULL
#' @noRd
cmd_doc_site = function(s) {
  if (!ext_service_has("doc.site")) return(NULL)
  tryCatch(ext_service_get("doc.site")(s), error = function(e) NULL)
}

#' `/help [command]`: the commands, the input syntax and the keys, which follow the console as the
#' banner's do (repl_banner()): enter, tab's follow-up and up where a composer reads keys (class T),
#' tab's completion where the REPL completes (after `! /` in RStudio, which would put a `$` or `@`
#' word in backticks), and what a line typed while peter works does there; in the banner's type,
#' names bold and keys lower case, every description starting lower case, in one column, wrapped
#' between a usage's, a key's and the last two words
#' @noRd
cmd_help = function(args, ctx) {
  s = ctx$session
  console_templates_sync()
  # a description starts as the Input and Keys ones do; an acronym (MCP) stays
  lower = function(x) sub("^([[:upper:]])(?=[[:lower:]])", "\\L\\1", x, perl = TRUE)
  if (nzchar(args)) {
    nm = sub("^/", "", args)
    spec = registry_get("command", nm, session = s)
    if (is.null(spec)) return(paste0("No command /", nm, "."))
    return(paste0("/", nm, "  ", lower(spec$description %||% "")))
  }
  nms = sort(registry_names("command", session = s), method = "radix")
  desc = vapply(nms, function(nm) registry_get("command", nm, session = s)$description %||% "",
                "", USE.NAMES = FALSE)
  # styled rows (cli_ansi_string, console_command()): a spec's name and description escaped
  nms = console_escape(nms, FALSE)
  desc = console_escape(desc, FALSE)
  # the descriptions wrap under one column at the content width (D-225), never inside a usage
  # (`/mode [plan|...]`), a key and its word or the last two words (bound by U+00A0 while wrapping)
  width = cli::console_width() - 2L * nchar(console_pad())
  nbsp = "\u00a0"
  bind = function(y) {
    m = gregexpr("/\\S+ \\[[^]]*\\]| [[:alpha:]]+[.)]?$", y, perl = TRUE)
    regmatches(y, m) = lapply(regmatches(y, m), function(u) gsub(" ", nbsp, u, fixed = TRUE))
    y
  }
  dl = function(x, y) {
    rows = formatDL(paste0("  ", x), bind(lower(y)), width = width, indent = 19L)
    paste0("  ", cli::style_bold(x), substring(gsub(nbsp, " ", rows, fixed = TRUE), nchar(x) + 3L))
  }
  keys = console_class() == "T"
  done = if (isTRUE(console_repl_find()$reader$complete)) {
    paste0("after ", if (front_end() == "rstudio") {
      "! or / (not $ or @ words)"
    } else {
      "@, !, !!, / or peter$"
    }, ", complete the word")
  }
  pause = paste0(if (console_menu_available()) {
    paste0("pause the answer: ", paste0(c("s", "f", "c", "a", "b"), nbsp,
                                         c("steer", "follow-up", "continue", "abort", "background"),
                                         collapse = ", "))
  } else {
    "stop the answer"
  }, "; twice at the prompt leaves")
  typed = if (keys) {
    "In other consoles a line typed while peter works is the next prompt."
  } else if (console_menu_available() && front_end() == "positron") {
    "Text typed while peter works waits as R code; ctrl-c, then s, to steer."
  } else if (console_class() == "D") {
    "A line typed while peter works is queued as type_ahead says: a steer, unless follow_up."
  } else {
    "A line typed while peter works is the next prompt."
  }
  cli::ansi_string(c("Commands:", dl(paste0("/", nms), desc),
    "Input:",
    dl(c("text", "!code", "!!code", "```r ... ```", "\"\"\" ... \"\"\""),
       c("a prompt; @file adds a file, @object attaches an object",
         "run R code here; the code and its output go with the next prompt",
         "run R code here; omit the code/output note for the next prompt",
         "a block of R code (like !)",
         "a multi-line prompt; a trailing \\ also continues a line")),
    "Keys:",
    dl(c(if (keys) "enter", if (keys || !is.null(done)) "tab", if (keys) "up",
         tolower(console_interrupt_key())),
       c(if (keys) {
         paste("send what you typed while peter works as a steer: the agent reads it at its next",
               "step")
       }, if (keys) {
         paste(c(paste("send it as a follow-up instead: the next prompt, once the answer ends",
                       "(type_ahead swaps the two)"), done), collapse = "; ")
       } else {
         done
       }, if (keys) "on an empty draft, take back the newest message not yet delivered", pause)),
    typed))
}

#' /exit, /quit, /q: with background sessions still running it says so, dim in the banner's words,
#' as their end is noticed at R's prompt (bg_release())
#' @noRd
cmd_exit = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/exit works inside the gptr console.")
  rs$exit = TRUE
  n = sum(job_list("session")$status == "running")
  if (!n) return(NULL)
  sym = console_style()
  cli::ansi_string(sym$dim(if (n == 1L) {
    paste0("1 background session still runs", sym$sep, "gptr_wait(gptr_last()) shows it")
  } else {
    paste0(n, " background sessions still run", sym$sep, "gptr_jobs() lists them")
  }))
}

#' The full id a built-in CLI gets for the reference `ref` to its `default` (contract 11.10), else
#' NULL: another CLI adapter decides what its `default` runs
#' @noRd
console_cli_default = function(ref) {
  m = model_canonical(ref)
  if (!identical(m$type, "cli") || !endsWith(m$ref, "/default")) return(NULL)
  api = registry_get("provider", sub("/.*$", "", m$ref))[["api"]]
  if (isTRUE(api %in% c("cli-claude", "cli-codex"))) pcli_default_model(api)
}

#' A model reference as /model and /status show it: a built-in CLI's `default` with the full id
#' the CLI gets (`claude-cli/default (claude-sonnet-5-5)`)
#' @noRd
cmd_model_label = function(ref) {
  id = console_cli_default(ref)
  if (is.null(id)) ref else paste0(ref, " (", id, ")")
}

#' `/model [ref]`: on a session from the next request; before the first prompt for that prompt,
#' checked now (IC-79) and kept as typed
#' @noRd
cmd_model = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (!nzchar(args)) {
    model = if (!is.null(rs)) repl_model(rs) else s$model
    return(paste0("Model: ", cmd_model_label(model %||% "the default model")))
  }
  if (!is.null(s)) {
    session_set_model(s, args, reason = "user")
    # the choice also outlives /clear (a new session starts with it)
    if (!is.null(rs)) rs$model = args
    return(paste0("Model: ", s$model, " (from the next request)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  if (is.null(registry_get("router", args))) model_canonical(args, strict = TRUE)
  rs$model = args
  paste0("Model: ", args, " (used from the first prompt)")
}

#' `/mode [mode]`: on a session from the next turn; before the first prompt for that prompt
#' @noRd
cmd_mode = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (!nzchar(args)) {
    return(paste0("Mode: ", if (!is.null(rs)) repl_mode(rs) else s$mode %||% "manual"))
  }
  if (!args %in% session_modes) {
    return(paste0("Unknown mode '", args, "': use plan, manual, edits, auto or yolo."))
  }
  if (!is.null(s)) {
    session_set_mode(s, args, source = "user")
    if (!is.null(rs)) rs$mode = args
    return(paste0("Mode: ", args, " (from the next turn)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  rs$mode = args
  mode_notice(args)
  paste0("Mode: ", args, " (used from the first prompt)")
}

#' @noRd
cmd_plan = function(args, ctx) {
  cmd_mode("plan", ctx)
}

#' @noRd
cmd_tools = function(args, ctx) {
  s = ctx$session
  direct = if (!is.null(s)) session_data(s)$frozen$tool_names
  members = character()
  for (nm in sort(registry_names("tool", session = s), method = "radix")) {
    spec = registry_get("tool", nm, session = s)
    if (is.function(spec$fun) && !identical(spec$exposure, "hidden")) {
      members = c(members, paste0("peter$", gsub("/", "$", nm, fixed = TRUE)))
    }
  }
  direct = if (length(direct)) paste(direct, collapse = ", ") else "(fixed at the first prompt)"
  c(paste0("Direct tools: ", direct),
    paste0("peter$ members: ", if (length(members)) paste(members, collapse = ", ") else "(none)"))
}

#' The names code in `env` reads, sorted: a fork overlay's, then each lower overlay's and the first
#' other environment's (/env, the banner)
#' @noRd
console_env_names = function(env) {
  nms = ls(env)
  while (!is.null(attr(env, "gptr_overlay", exact = TRUE))) {
    env = parent.env(env)
    nms = c(nms, ls(env))
  }
  sort(unique(nms), method = "radix")
}

#' The first `n` objects `env` reads whose names contain `text`, each described where it is bound,
#' without forcing promises (/env)
#' @noRd
console_env_lines = function(env, text = "", n = 30L) {
  nms = console_env_names(env)
  nms = nms[grepl(text, nms, fixed = TRUE)]
  lines = vapply(utils::head(nms, n), function(nm) {
    e = env
    while (!exists(nm, envir = e, inherits = FALSE)) e = parent.env(e)
    describe_binding(nm, e, budget = 40L)[[1L]]
  }, "", USE.NAMES = FALSE)
  c(lines, if (length(nms) > n) paste0("(+ ", length(nms) - n, " more)"))
}

#' `/env [text]`
#' @noRd
cmd_env = function(args, ctx) {
  rs = console_repl_find()
  env = if (!is.null(rs)) repl_eval_env(rs) else ctx$envir
  if (!is.environment(env)) return("No environment is attached to this console.")
  lines = console_env_lines(env, args)
  if (length(lines)) lines else "(no objects)"
}

#' `/compact [focus]`, under the interrupt policy (mode "repl": an abort returns NULL); it reports
#' the token counts of the new compaction entry, as the automatic notice does
#' (console_compacted()), dim in the status line's terms
#' @noRd
cmd_compact = function(args, ctx) {
  sym = console_style()
  say = function(...) cli::ansi_string(sym$dim(paste(c(...), collapse = sym$sep)))
  s = ctx$session
  if (is.null(s)) return(say("nothing to compact yet"))
  if (isTRUE(session_live(s)$compacting)) return(say("already compacting"))
  compact = ext_service_get("compact.run")
  compactions = function() {
    Filter(function(e) identical(e$type, "compaction"), session_data(s)$entries)
  }
  before = length(compactions())
  done = with_interrupt_policy(function() {
    compact(s, "manual", if (nzchar(args)) args)
    length(compactions()) > before
  }, list(), mode = "repl")
  if (identical(done, FALSE)) return(say("not compacted", "cancelled"))
  if (!isTRUE(done)) return(say("interrupted"))
  say(console_compacted(utils::tail(compactions(), 1L)[[1L]]))
}

#' /cost: the requests, input tokens and cost of the session and its children by agent, then
#' their total
#' @noRd
cmd_cost = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("No session yet.")
  u = s$usage
  agents = unique(u$agent)
  label = format(agents)
  c(vapply(seq_along(agents), function(i) {
    paste0("  ", label[[i]], "  ", format_usage(u[u$agent %in% agents[[i]], , drop = FALSE]))
  }, ""), paste0("Total: ", format_usage(u)))
}

#' /context: the token ledger of the last request, gptr's estimate of what it sent (its total marked
#' `(est.)`), and the context it left, as the run's status line says it from the reported counts
#' (console_context_left()); on a CLI route (`plan-cli`) instead what the CLI reported for
#' its turn, since it keeps its own transcript. After /compact the last request is the compaction
#' request (its `gptr.compaction_usage` record), which says so and adds the estimate of the next
#' request, the compaction entry's `tokens_after`, as a ledger row marked `~`, from which the
#' context left is then measured
#' @noRd
cmd_context = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("No session yet.")
  led = gptr::gptr_usage(s, detail = TRUE)
  if (!nrow(led)) return("No request yet.")
  id = led$request_id[[nrow(led)]]
  last = led[led$request_id == id, , drop = FALSE]
  u = session_data(s)$usage
  u = u[match(id, u$request_id), , drop = FALSE]
  entries = session_data(s)$entries
  at = Position(function(e) {
    identical(e$custom_type, "gptr.compaction_usage") && identical(e$data$row$request_id, id)
  }, entries)
  after = if (!is.na(at)) {
    Find(function(e) identical(e$type, "compaction"), entries[-seq_len(at)])$details$tokens_after
  }
  if (anyNA(after)) after = NULL
  left = console_context_left(u, after)
  fmt = function(n) format(round(n), big.mark = ",")
  c(paste0("Last request ", id, if (!is.na(at)) " (the compaction request)", ":"),
    sprintf("  %-14s %9s%s", last$component, fmt(last$tokens),
            ifelse(is.na(last$cached), "  (cache unknown)", ifelse(last$cached, "  (cached)", ""))),
    sprintf("  %-14s %9s", "total (est.)", fmt(sum(last$tokens))),
    if (!is.null(after)) sprintf("  %-14s %9s", "next request", paste0("~", fmt(after))),
    if (!is.na(left)) sprintf("  %-14s %9s", "context left", paste0(left, "%")),
    if (identical(u$route, "plan-cli")) {
      paste0("  The CLI keeps its own transcript; its last turn reported ",
             format_count(c(u$input, u$cache_read, u$cache_write_5m, u$cache_write_1h)),
             " input tokens over all its model calls.")
    })
}

#' @noRd
cmd_status = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (is.null(s)) {
    return(c("session   (none yet: the first prompt starts one)",
             paste0("model     ",
                    cmd_model_label(if (!is.null(rs)) repl_model(rs) else "the default model")),
             paste0("mode      ", if (!is.null(rs)) repl_mode(rs) else "manual"),
             paste0("document  ", cmd_doc_site(NULL)$path %||% "(none)")))
  }
  d = session_data(s)
  c(paste0("session   ", d$id, "  (", d$status, ", ", d$turns,
           if (d$turns == 1L) " turn)" else " turns)"),
    paste0("model     ", cmd_model_label(d$model)),
    paste0("mode      ", d$mode),
    paste0("document  ", cmd_doc_site(s)$path %||% "(none)"),
    paste0("queue     ", length(d$queue$steer), " steer, ", length(d$queue$follow_up),
           " follow-up"),
    paste0("file      ", d$file %||% "(not written yet)"))
}

#' /clear: a new conversation that keeps the model, its thinking level, the mode and the workspace
#' the old one evaluated in (a fork's overlay, a piped session's home)
#' @noRd
cmd_clear = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/clear works inside the gptr console.")
  s = rs$session
  if (!is.null(s)) {
    # keep the console call's (or /model's) model: a spec registered for the old session only
    # would not resolve from its model string in a new session; else the session's, its level as
    # the `:<level>` suffix (a router chooses its own)
    d = session_data(s)
    level = if (!is.null(d$thinking) && !startsWith(d$model, "router:")) paste0(":", d$thinking)
    rs$model = rs$model %||% paste0(d$model, level)
    rs$mode = s$mode
  }
  rs$envir = repl_eval_env(rs)
  rs$session = NULL
  rs$notes = character()
  rs$attach = character()
  "New conversation; the objects in the environment are kept."
}

#' @noRd
cmd_resume = function(args, ctx) {
  if (!nzchar(args)) return(print_lines(gptr::gptr_sessions()))
  rs = console_repl_find()
  if (is.null(rs)) return("Use gptr_resume() outside the console.")
  s = gptr::gptr_resume(args, envir = rs$envir)
  rs$session = s
  # the resumed session's kept home now decides where prompts and !code evaluate (IC-40)
  rs$envir_given = FALSE
  paste0("Resumed ", s$id, " (", s$turns, if (s$turns == 1L) " turn)." else " turns).")
}

#' @noRd
cmd_fork = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to fork yet.")
  f = gptr::gptr_fork(s)
  rs = console_repl_find()
  if (!is.null(rs)) {
    rs$session = f
    # the fork's overlay must win over an explicit console `envir` (IC-40)
    rs$envir_given = FALSE
  }
  paste0("Forked ", s$id, " into ", f$id, "; the fork's new objects stay in its overlay.")
}

#' @noRd
cmd_doc = function(args, ctx) {
  if (!nzchar(args)) {
    site = cmd_doc_site(ctx$session)
    if (is.null(site)) return("No document is bound.")
    return(paste0("Document: ", site$path, " (", site$format, ")"))
  }
  f = ns_fun("gptr_doc")
  if (is.null(f)) return("Binding a document needs gptr_doc(), which is not available.")
  f(args)
  paste0("Recording into ", args, ".")
}

#' @noRd
cmd_skills = function(args, ctx) {
  f = ns_fun("gptr_skills")
  if (is.null(f)) return("Skills are not available.")
  print_lines(f())
}

#' `/skill:<name> [request]`: the skill goes to the next prompt's `skills =`; the request is sent
#' @noRd
cmd_skill = function(args, ctx) {
  name = sub("[[:space:]].*$", "", args)
  if (!nzchar(name)) return("Name a skill: /skill:<name> [request].")
  if (!ext_service_has("skill.body")) return("Skills are not available.")
  rs = console_repl_find()
  if (is.null(rs)) return("/skill works inside the gptr console.")
  rs$next_skills = unique(c(rs$next_skills, name))
  request = trimws(substring(args, nchar(name) + 1L))
  list(prompt = if (nzchar(request)) request else paste0("Use the ", name, " skill."))
}

#' @noRd
cmd_mcp = function(args, ctx) {
  f = ns_fun("gptr_mcp")
  if (is.null(f)) return("MCP is not available.")
  print_lines(f())
}

#' `/permissions [allow|ask|deny|remove <rule>]`: the rules, or a change for this R session
#' (gptr_permissions() validates the rule)
#' @noRd
cmd_permissions = function(args, ctx) {
  if (!nzchar(args)) return(print_lines(gptr::gptr_permissions()))
  verb = sub("[[:space:]].*$", "", args)
  rule = trimws(substring(args, nchar(verb) + 1L))
  if (!verb %in% c("allow", "ask", "deny", "remove") || !nzchar(rule)) {
    return(paste("Use /permissions allow|ask|deny|remove <rule>,",
                 "e.g. /permissions allow r(fn:saveRDS)."))
  }
  do.call(gptr::gptr_permissions, stats::setNames(list(rule, "session"), c(verb, "scope")))
  if (identical(verb, "remove")) {
    paste0("Removed ", rule, ".")
  } else {
    paste0("Added ", verb, " rule ", rule, " for this R session.")
  }
}

#' /retry: undo the last turn (gptr_rewind(), P16) and send its prompt again, with the skills it
#' preloaded
#' @noRd
cmd_retry = function(args, ctx) {
  s = ctx$session
  if (is.null(s) || !isTRUE(s$turns >= 1L)) return("There is no answer to retry.")
  f = ns_fun("gptr_rewind")
  if (is.null(f)) return("/retry needs gptr_rewind(), which is not available.")
  before = s$last_rewind
  f(s, turn = -1L)
  # a session_before_tree handler may cancel the rewind; editor_text is then a stale prompt
  if (identical(s$last_rewind, before)) return("The last turn was not undone.")
  prompt = s$editor_text
  if (!rlang::is_string(prompt) || !nzchar(prompt)) {
    return("The last prompt could not be recovered.")
  }
  rs = console_repl_find()
  if (!is.null(rs)) rs$next_skills = s$last_rewind$skills
  list(prompt = prompt)
}
