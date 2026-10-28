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
#' /, the registered commands, plugin and template commands among them (registered now, as /help
#' does, D-252), and `/skill:` once where a skill is registered or listed by gptr_skills() (as
#' /skills lists them, before the first prompt has registered any), after which a word starting
#' /skill: completes /skill:<name>. Anything else, and a failure, gives character(0). No source
#' offers a word holding a control character (a file, object, command or skill name).
#' @noRd
console_complete = function(line, end = nchar(line)) {
  line = substr(line, 1L, end)
  word = console_trigger(line)
  rs = console_repl_find()
  if (is.null(word) || !isTRUE(rs$reader$complete)) return(character())
  cands = tryCatch({
    if (grepl("^\\s*!", line, perl = TRUE)) {
      u = function(f) utils::getFromNamespace(f, "utils")
      u(".assignLinebuffer")(line)
      u(".assignEnd")(nchar(line))
      token = u(".guessTokenFromLine")()
      u(".completeToken")()
      completion_shift(u(".retrieveCompletions")(), token, word)
    } else {
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
        if (startsWith(word, "/skill:")) {
          paste0("/skill:", sort(skills, method = "radix"), recycle0 = TRUE)
        } else {
          console_templates_sync()
          c(paste0("/", sort(registry_names("command", s), method = "radix"), recycle0 = TRUE),
            if (length(skills)) "/skill:")
        }
      }
      unique(cands[startsWith(cands, word)])
    }
  }, error = function(e) character())
  # readline would send what follows a line end as a line of its own, a ! line as R code
  cands[!grepl("[\\x01-\\x1f\\x7f]", cands, perl = TRUE, useBytes = TRUE)]
}

#' The custom completer R's completion calls (`custom.completer`, IC-81): it sets `fileName`
#' FALSE first, as a completion environment without it aborts the readline() call, and again after
#' console_complete(), so a string on a ! line never goes to readline's own file-name completion
#' (`rc.settings(quotes = FALSE)`), which would offer a name holding a line end; it gives
#' console_complete() of the line before the cursor as completions of R's token (readline's word,
#' or utils' guess in RStudio and Windows), with the caller's completer `prev` (NULL when none) as
#' the custom one meanwhile, so R's completion of a ! line calls it. RStudio asks with `isConsole`
#' in its request's frame: its editor (FALSE), which shares the request while the prompt waits,
#' gets the caller's completion or an error, on which RStudio's own engine answers (R's would give
#' whole words such as `fuel$mpg`, which RStudio inserts in backticks); its console only the
#' candidates that are syntactic names, as RStudio inserts any other in backticks, and for none the
#' token itself where it holds only letters, digits, . and _ (RStudio shows its own completions for
#' an empty result and none for such a token alone), else an error, on which RStudio's own engine
#' answers (it would insert the token in backticks: `3:`, `note:`). R's Unix readline, reading at
#' `prompt`, gets one completion, the candidates' common head, so it never lists them (its list
#' printed in the input band and paged a long one); where that adds nothing they are listed as the
#' composer lists them, one dim row at column 2 above the prompt's row, written again with the line
#' (completion_list()), and readline gets none
#' @noRd
console_completer = function(prev, prompt = NULL) {
  function(env) {
    env$fileName = FALSE
    env$comps = character()
    token = env$token
    line = substr(env$linebuffer, 1L, env$end)
    old = utils::rc.options(custom.completer = prev)
    on.exit(utils::rc.options(old), add = TRUE)
    console = dynGet("isConsole", ifnotfound = NA)
    if (isFALSE(console) && !is.function(prev)) stop("RStudio's own completion")
    if (isFALSE(console)) return(prev(env))
    word = console_trigger(line) %||% ""
    full = console_complete(line)
    # and again: R's completion of a ! line's string leaves it to readline's file-name completion
    # under rc.settings(quotes = FALSE), which no filter of gptr's reaches
    env$fileName = FALSE
    if (!is.null(prompt) && length(full) > 1L) {
      pre = full[[1L]]
      for (x in full[-1L]) while (!startsWith(x, pre)) pre = substr(pre, 1L, nchar(pre) - 1L)
      # several that add nothing are listed here and none goes to readline, whose next Tab would
      # list what it got
      if (nchar(pre) <= nchar(word)) completion_list(full, prompt, env$linebuffer, env$end)
      full = if (nchar(pre) > nchar(word)) pre else character()
    }
    comps = completion_shift(full, word, token)
    if (isTRUE(console)) {
      comps = comps[make.names(comps) == comps]
      if (!length(comps) && grepl("[^[:alnum:]._]", token)) stop("RStudio's own completion")
      if (!length(comps)) comps = token
    }
    env$comps = comps
    invisible(NULL)
  }
}

#' Completion candidates under readline's line: from the end of its row, the attributes reset (so a
#' scroll is not painted with the input band), one dim row at column 2 (live_candidates()), then
#' the prompt on the band and the whole line again, the cursor moved back to `end` with
#' backspaces, where readline holds it; readline, which lists nothing, draws its line there
#' @noRd
completion_list = function(cands, prompt, line, end) {
  sym = console_style()
  rest = substring(line, end + 1L)
  row = paste0("  ", sym$dim(live_candidates(cands, cli::console_width() - 3L)), "\033[K")
  console_cat(paste0("\033[0m\r\n", row, "\r\n", sym$band, prompt, if (nzchar(sym$band)) "\033[K",
                     line, strrep("\b", nchar(rest))))
}

#' Completions `cands` of `from` as completions of `to`, where both are tails of the line before
#' the cursor (a token R completes and gptr's word): the longer one's extra head is cut from each
#' or added to each
#' @noRd
completion_shift = function(cands, from, to) {
  n = nchar(from) - nchar(to)
  if (n >= 0L) substring(cands, n + 1L) else paste0(substr(to, 1L, -n), cands, recycle0 = TRUE)
}
