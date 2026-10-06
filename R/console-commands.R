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
                 "Show or switch the permission mode: /mode [plan|manual|edits|auto]"),
    gptr_command("plan", cmd_plan, "Switch to plan mode (read-only exploration, then a plan)"),
    gptr_command("tools", cmd_tools, "List the direct tools and the peter$ members"),
    gptr_command("env", cmd_env, "List objects of the console environment: /env [pattern]"),
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
                       "/permissions [allow|ask|deny|remove <rule>]")),
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
#' character result is printed escaped, `list(prompt =)` is sent, and an error is reported on
#' stderr (the input counts as handled).
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
  spec = registry_get("command", cmd$full, session = session)
  args = cmd$rest
  if (is.null(spec)) {
    spec = registry_get("command", cmd$name, session = session)
    args = cmd$args
  }
  if (is.null(spec)) {
    console_notice("Unknown command /", console_escape(cmd$full, FALSE),
                   ". Type /help for the list.")
    return(invisible("unknown"))
  }
  ctx = (if (!is.null(session)) session_live(session)$ctx) %||% ctx_new(session)
  out = tryCatch(spec$handler(args, ctx), error = function(e) {
    console_notice("Error in /", console_escape(spec$name, FALSE), ": ",
                   console_escape(conditionMessage(e), FALSE))
    e
  })
  if (inherits(out, "error")) return(invisible("error"))
  if (is.list(out) && rlang::is_string(out$prompt) && nzchar(out$prompt)) {
    if (is.function(send)) send(out$prompt)
    return(invisible("prompt"))
  }
  if (is.character(out)) console_out(out)
  invisible("done")
}

#' The bound history document of `s` (the `doc.site` service, P15), or NULL
#' @noRd
cmd_doc_site = function(s) {
  if (is.null(s) || !ext_service_has("doc.site")) return(NULL)
  tryCatch(ext_service_get("doc.site")(s), error = function(e) NULL)
}

#' @noRd
cmd_help = function(args, ctx) {
  s = ctx$session
  if (nzchar(args)) {
    nm = sub("^/", "", args)
    spec = registry_get("command", nm, session = s)
    if (is.null(spec)) return(paste0("No command /", nm, "."))
    return(paste0("/", nm, "  ", spec$description %||% ""))
  }
  nms = sort(registry_names("command", session = s), method = "radix")
  lines = vapply(nms, function(nm) {
    sprintf("  /%-12s %s", nm, registry_get("command", nm, session = s)$description %||% "")
  }, "", USE.NAMES = FALSE)
  c("Commands:", lines,
    "Input:",
    "  text             a prompt; @file adds a file, @object attaches an object",
    "  !code            run R code here; the code and its output go with the next prompt",
    "  !!code           run R code here; not sent to the model",
    "  ```r ... ```     a block of R code (like !)",
    "  \"\"\" ... \"\"\"      a multi-line prompt; a trailing \\ also continues a line",
    paste0("Keys: ", console_interrupt_key(), " pauses a running answer (steer, follow-up, ",
           "continue, abort); twice at the prompt leaves."))
}

#' /exit, /quit, /q
#' @noRd
cmd_exit = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/exit works inside the gptr console.")
  rs$exit = TRUE
  NULL
}

#' /model [ref]: on a session from the next request; before the first prompt for that prompt
#' @noRd
cmd_model = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (!nzchar(args)) {
    model = if (!is.null(rs)) repl_model(rs) else s$model
    return(paste0("Model: ", model %||% "the default model"))
  }
  if (!is.null(s)) {
    session_set_model(s, args, reason = "user")
    # the choice also outlives /clear (a new session starts with it)
    if (!is.null(rs)) rs$model = args
    return(paste0("Model: ", s$model, " (from the next request)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  rs$model = args
  paste0("Model: ", args, " (used from the first prompt)")
}

#' /mode [mode]: on a session from the next turn; before the first prompt for that prompt
#' @noRd
cmd_mode = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (!nzchar(args)) {
    return(paste0("Mode: ", if (!is.null(rs)) repl_mode(rs) else s$mode %||% "manual"))
  }
  if (!args %in% c("plan", "manual", "edits", "auto")) {
    return(paste0("Unknown mode '", args, "': use plan, manual, edits or auto."))
  }
  if (!is.null(s)) {
    session_set_mode(s, args, source = "user")
    if (!is.null(rs)) rs$mode = args
    return(paste0("Mode: ", args, " (from the next turn)"))
  }
  if (is.null(rs)) return("There is no session to switch.")
  rs$mode = args
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

#' The first `n` objects of `env` whose names contain `pattern`, described without forcing
#' promises (/env and the console banner)
#' @noRd
console_env_lines = function(env, pattern = "", n = 30L) {
  nms = sort(ls(env), method = "radix")
  nms = nms[grepl(pattern, nms, fixed = TRUE)]
  lines = vapply(utils::head(nms, n), function(nm) {
    paste0("  ", describe_binding(nm, env, budget = 40L)[[1L]])
  }, "", USE.NAMES = FALSE)
  c(lines, if (length(nms) > n) paste0("  (+ ", length(nms) - n, " more)"))
}

#' /env [pattern]
#' @noRd
cmd_env = function(args, ctx) {
  rs = console_repl_find()
  env = if (!is.null(rs)) repl_eval_env(rs) else ctx$envir
  if (!is.environment(env)) return("No environment is attached to this console.")
  lines = console_env_lines(env, args)
  if (length(lines)) lines else "(no objects)"
}

#' /compact [focus], under the interrupt policy (mode "repl": an abort returns NULL)
#' @noRd
cmd_compact = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no conversation to compact yet.")
  compact = ext_service_get("compact.run")
  done = with_interrupt_policy(function() {
    compact(s, "manual", if (nzchar(args)) args)
    TRUE
  }, list(), mode = "repl")
  if (isTRUE(done)) "Conversation compacted." else "Compaction was interrupted."
}

#' @noRd
cmd_cost = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("No session yet.")
  c(utils::capture.output(print(gptr::gptr_usage(s))), paste0("Total: ", format_cost(s$cost)))
}

#' /context: the token ledger of the last request
#' @noRd
cmd_context = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("No session yet.")
  led = gptr::gptr_usage(s, detail = TRUE)
  if (!nrow(led)) return("No request yet.")
  last = led[led$request_id == led$request_id[[nrow(led)]], , drop = FALSE]
  c(paste0("Last request ", last$request_id[[1L]], ":"),
    sprintf("  %-14s %9s%s", last$component, format(round(last$tokens), big.mark = ","),
            ifelse(is.na(last$cached), "  (cache unknown)", ifelse(last$cached, "  (cached)", ""))),
    sprintf("  %-14s %9s", "total", format(round(sum(last$tokens)), big.mark = ",")))
}

#' @noRd
cmd_status = function(args, ctx) {
  rs = console_repl_find()
  s = ctx$session
  if (is.null(s)) {
    return(c("session   (none yet: the first prompt starts one)",
             paste0("model     ", if (!is.null(rs)) repl_model(rs) else "the default model"),
             paste0("mode      ", if (!is.null(rs)) repl_mode(rs) else "manual")))
  }
  d = session_data(s)
  c(paste0("session   ", d$id, "  (", d$status, ", ", d$turns, " turns)"),
    paste0("model     ", d$model),
    paste0("mode      ", d$mode),
    paste0("document  ", cmd_doc_site(s)$path %||% "(none)"),
    paste0("queue     ", length(d$queue$steer), " steer, ", length(d$queue$follow_up),
           " follow-up"),
    paste0("file      ", d$file %||% "(not written yet)"))
}

#' /clear: a new conversation that keeps the model and mode
#' @noRd
cmd_clear = function(args, ctx) {
  rs = console_repl_find()
  if (is.null(rs)) return("/clear works inside the gptr console.")
  s = rs$session
  if (!is.null(s)) {
    # keep the console call's (or /model's) model: a spec registered for the old session only
    # would not resolve from its model string in a new session
    rs$model = rs$model %||% s$model
    rs$mode = s$mode
  }
  rs$session = NULL
  rs$notes = character()
  rs$attach = character()
  "New conversation; the objects in the environment are kept."
}

#' @noRd
cmd_resume = function(args, ctx) {
  if (!nzchar(args)) return(utils::capture.output(print(gptr::gptr_sessions())))
  rs = console_repl_find()
  if (is.null(rs)) return("Use gptr_resume() outside the console.")
  s = gptr::gptr_resume(args, envir = rs$envir)
  rs$session = s
  # the resumed session's kept home now decides where prompts and !code evaluate (IC-40)
  rs$envir_given = FALSE
  paste0("Resumed ", s$id, " (", s$turns, " turns).")
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
  utils::capture.output(print(f()))
}

#' /skill:<name> [request]: the skill goes to the next prompt's `skills =`; the request is sent
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
  utils::capture.output(print(f()))
}

#' /permissions [allow|ask|deny|remove <rule>]: the rules, or a change for this R session
#' (gptr_permissions() validates the rule)
#' @noRd
cmd_permissions = function(args, ctx) {
  if (!nzchar(args)) return(utils::capture.output(print(gptr::gptr_permissions())))
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

#' /retry: undo the last turn (gptr_rewind(), P16) and send its prompt again
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
  list(prompt = prompt)
}
