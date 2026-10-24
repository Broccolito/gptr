# console-complete.R -- trigger-only completion at the gptr console (P28, layer L5, area console;
# IC-81, D-244): after @, !, !!, / and peter$ only, never on natural language. R's completion
# reaches it through the custom completer that the REPL's reader installs around its prompt reads,
# in terminal R, RStudio's console and Windows' consoles; the composer's Tab calls it directly.

#' Does R's completion in this console call R's custom completer, so the REPL completes after its
#' trigger characters (IC-81)? R's own Unix readline on a tty (console_readline_tty()), RStudio's
#' console (which consults it before its own engine) and Windows' Rgui and Rterm (utils'
#' .win32consoleCompletion()); not a piped REPL, not with R_COMPLETION=FALSE, and not Positron
#' (whose ark has a tty stdin), radian or R.app, whose completion gptr does not reach
#' @noRd
console_completes = function(stdin = FALSE) {
  if (isTRUE(stdin) || identical(Sys.getenv("R_COMPLETION"), "FALSE") ||
        front_end() == "positron") {
    return(FALSE)
  }
  console_readline_tty() || (gptr_is_interactive() && !nzchar(Sys.getenv("RADIAN_VERSION")) &&
                               (front_end() == "rstudio" ||
                                  (is_windows() && platform_gui() %in% c("Rgui", "RTerm"))))
}

#' The completions of the word before the cursor (`end`) in `line` (IC-81, D-244), as full words,
#' in a REPL whose reader completes (`rd$complete`) and only on a trigger word (console_trigger()):
#' on a line starting with ! or !!, R's own completion of the code (utils' .completeToken(),
#' which calls the custom completer a caller owns); after @obj$, the object's .DollarNames();
#' after @, the objects an @mention names (console_objects()), then the files and directories
#' under the working directory, a directory ending in /, names starting with a dot only when the
#' word does; after peter$, peter's members (the `ns.names` service); a first word starting with
#' /, the registered commands, plugin commands among them, and /skill:<name> for each skill
#' registered or listed by gptr_skills() (as /skills lists them, before the first prompt has
#' registered any). Anything else, and a failure, gives character(0).
#' @noRd
console_complete = function(line, end = nchar(line)) {
  line = substr(line, 1L, end)
  word = console_trigger(line)
  rs = console_repl_find()
  if (is.null(word) || !isTRUE(rs$reader$complete)) return(character())
  tryCatch({
    if (grepl("^\\s*!", line, perl = TRUE)) {
      u = function(f) utils::getFromNamespace(f, "utils")
      u(".assignLinebuffer")(line)
      u(".assignEnd")(nchar(line))
      token = u(".guessTokenFromLine")()
      u(".completeToken")()
      return(completion_shift(u(".retrieveCompletions")(), token, word))
    }
    env = repl_eval_env(rs)
    obj = regmatches(word, regexec("^@([^$]+)\\$[^$]*$", word))[[1L]]
    base = sub("^.*/", "", word)
    cands = if (length(obj)) {
      if (obj[[2L]] %in% console_objects(env)) {
        paste0("@", obj[[2L]], "$", utils::.DollarNames(get(obj[[2L]], envir = env), ""),
               recycle0 = TRUE)
      }
    } else if (startsWith(word, "@")) {
      hidden = grepl("^@?[.]", base)
      objs = console_objects(env, hidden)
      dir = sub("[^/]*$", "", substring(word, 2L))
      where = if (nzchar(dir)) path.expand(dir) else "."
      files = sort(list.files(where, all.files = hidden, no.. = TRUE), method = "radix")
      files = paste0(files, ifelse(dir.exists(file.path(where, files)), "/", ""))
      paste0("@", c(objs[make.names(objs) == objs], paste0(dir, files, recycle0 = TRUE)),
             recycle0 = TRUE)
    } else if (startsWith(word, "peter$")) {
      if (ext_service_has("ns.names")) {
        paste0("peter$", ext_service_get("ns.names")(""), recycle0 = TRUE)
      }
    } else {
      s = rs$session
      skills = unique(c(registry_names("skill", s), gptr::gptr_skills()$name))
      c(paste0("/", sort(registry_names("command", s), method = "radix"), recycle0 = TRUE),
        paste0("/skill:", sort(skills, method = "radix"), recycle0 = TRUE))
    }
    unique(cands[startsWith(cands, word)])
  }, error = function(e) character())
}

#' The custom completer R's completion calls (`custom.completer`, IC-81): it sets `fileName`
#' FALSE first, as a completion environment without it aborts the readline() call, then gives
#' console_complete() of the line before the cursor as completions of R's token (readline's word,
#' or utils' guess in RStudio and Windows), with the caller's completer `prev` (NULL when none) as
#' the custom one meanwhile, so R's completion of a ! line calls it. RStudio asks with `isConsole`
#' in its request's frame: its editor (FALSE), which shares the request while the prompt waits,
#' gets R's own completion (or the caller's); its console only the candidates that are syntactic
#' names, as RStudio inserts any other in backticks, and for none the token itself, as RStudio
#' shows its own completions for an empty result and none for the token alone
#' @noRd
console_completer = function(prev) {
  function(env) {
    env$fileName = FALSE
    env$comps = character()
    token = env$token
    line = substr(env$linebuffer, 1L, env$end)
    old = utils::rc.options(custom.completer = prev)
    on.exit(utils::rc.options(old), add = TRUE)
    console = dynGet("isConsole", ifnotfound = NA)
    if (isFALSE(console)) return(utils::getFromNamespace(".completeToken", "utils")())
    comps = completion_shift(console_complete(line), console_trigger(line) %||% "", token)
    if (isTRUE(console)) {
      comps = comps[make.names(comps) == comps]
      if (!length(comps)) comps = token
    }
    env$comps = comps
    invisible(NULL)
  }
}

#' Completions `cands` of `from` as completions of `to`, where both are tails of the line before
#' the cursor (a token R completes and gptr's word): the longer one's extra head is cut from each
#' or added to each
#' @noRd
completion_shift = function(cands, from, to) {
  n = nchar(from) - nchar(to)
  if (n >= 0L) substring(cands, n + 1L) else paste0(substr(to, 1L, -n), cands, recycle0 = TRUE)
}
