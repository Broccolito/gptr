# G2 (b) tool definitions and prompt builders shared by b_presets.R and d_compose.R.
# Tool definitions are provider-neutral lists: list(name, description, parameters [JSON Schema]).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
P01 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto"
local({
  owd = setwd(P01); on.exit(setwd(owd))
  for (f in c("00-utils.R", "01-read-write.R", "02-edit.R", "03-search.R", "04-run.R", "05-registry.R")) {
    sys.source(f, envir = globalenv())
  }
})
T01 = builtin_tools(shell = list(name = "bash"))
tool = function(name, description, parameters) list(name = name, description = description, parameters = parameters)
from01 = function(n) tool(T01[[n]]$name, T01[[n]]$description, T01[[n]]$parameters)
obj = function(props, required = character()) {
  o = list(type = "object", properties = props)
  if (length(required)) o$required = I(required)
  o
}
str_ = function(d) list(type = "string", description = d)
num_ = function(d) list(type = "number", description = d)
bool_ = function(d) list(type = "boolean", description = d)

# ---- Pi (verbatim descriptions and schemas, report 01 sections 3.2-3.8) ----
pi_tools = list(
  read = tool("read", "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
              obj(list(path = str_("Path to the file to read (relative or absolute)"), offset = num_("Line number to start reading from (1-indexed)"),
                       limit = num_("Maximum number of lines to read")), "path")),
  bash = tool("bash", "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
              obj(list(command = str_("Shell command to execute"), timeout = num_("Timeout in seconds (optional, no default timeout)")), "command")),
  edit = from01("edit"),     # identical to Pi's edit (report 01 section 3.4)
  write = from01("write"))   # identical to Pi's write (report 01 section 3.3)

# ---- gptr tools ----
r_tool = tool("r", "Run R code in the user's live R session. Objects you create persist in the user's workspace (by default the environment gptr() was called from) and are visible to later calls and to the user. Returns printed output, messages, warnings, errors (with a traceback) and plots (as images). Execution stops at the first error. Output is truncated to the first 40% and last 60% of 2000 lines / 50000 characters; the full text is saved to a temp file whose path is given. Rules: work in small steps; never re-load data that is already in memory; return values implicitly (write `x`, not `print(x)`) and prefer head()/str()-sized summaries; never call q(), quit(), readline(), menu(), browser() or install packages unless the user asked; to hand an R object back as the result of the request call gptr_return(obj).",
              obj(list(code = str_("R code to evaluate. May contain several expressions."),
                       timeout = num_("Seconds (best effort: long-running C code cannot be interrupted). Default 300.")), "code"))
r_lean = tool("r", "Evaluate R code in the user's live R session; objects persist and are shared with the user. Returns output, messages, warnings, errors and plots (images); long output is cut (head+tail) with the full text in a spill file.",
              obj(list(code = str_("R code; several expressions allowed.")), "code"))
r_inspect = tool("r_inspect", "Describe objects in the live session and look up R documentation without running code (read-only, allowed in plan mode, never needs approval).",
                 obj(list(action = list(type = "string", enum = I(c("objects", "describe", "help", "search", "package", "vignette", "session")), description = "What to inspect"),
                          name = str_("Object name, help topic, package or search pattern"), package = str_("Package for help/vignette lookups"),
                          max_chars = num_("Upper bound on returned characters (default 4000)")), "action"))
ask = tool("ask", "Ask the user one to four questions and wait for the answers. Use it when a decision materially changes the result (which object, which method, which output format) and you cannot infer the answer from the session or files. Prefer options the user can pick; the user can always type their own answer instead. Do not use it for permission to run code: the harness asks for permission itself.",
           list(type = "object", additionalProperties = FALSE, required = I("questions"),
                properties = list(questions = list(type = "array", minItems = 1, maxItems = 4, items = list(
                  type = "object", additionalProperties = FALSE, required = I(c("id", "question")),
                  properties = list(id = str_("Short stable key for the answer, e.g. 'format'"),
                                    header = list(type = "string", maxLength = 16, description = "Very short label, e.g. 'Format'"),
                                    question = str_("The full question shown to the user"),
                                    type = list(type = "string", enum = I(c("single", "multi", "text")), description = "single = pick one option, multi = pick any number, text = free text"),
                                    options = list(type = "array", maxItems = 9, items = list(type = "object", additionalProperties = FALSE, required = I("label"),
                                                   properties = list(label = list(type = "string"), description = list(type = "string")))),
                                    allow_other = bool_("Let the user type an answer that is not an option (default true)"),
                                    default = str_("Label (or text) used if the user just presses Enter")))))))
agent = tool("agent", "Delegate a self-contained task to a sub-agent with its own context, model and tools. The sub-agent reads the parent's session objects; its final answer (and an R value when `returns` is given) comes back as the result. Use for parallel or specialised work; do not delegate trivial steps.",
             obj(list(description = str_("3-7 word summary shown to the user"), prompt = str_("The full task for the sub-agent"),
                      agent_type = str_("Name of a defined agent (optional)"), model = str_("Model id or alias (optional)"),
                      background = bool_("Run in the background and notify on completion (default false)"),
                      returns = list(type = "object", description = "JSON Schema of an R value to return (optional)")), c("description", "prompt")))
artifact = tool("artifact", "Create or revise an interactive Shiny app (an artifact) that the user sees in their viewer or browser. The app runs in a separate R process. Objects named in `data` are copied (snapshotted) from the user's live R session and exist in app.R under the same names. Write ONE app.R that ends with shinyApp(ui, server). The result reports the URL, validation errors, and a screenshot of the running app.",
                list(type = "object", required = I(character()), properties = list(
                  title = str_("Short human-readable title (new artifacts)."),
                  code = str_("Complete app.R source. Required for a new artifact; for a revision either `code` or `edits`."),
                  edits = list(type = "array", description = "Revisions only: exact-match replacements applied to the current app.R.",
                               items = list(type = "object", properties = list(old_text = list(type = "string"), new_text = list(type = "string")), required = I(c("old_text", "new_text")))),
                  data = list(type = "array", items = list(type = "string"), description = "Names of objects in the user's R session to ship into the app (small data frames or summaries, not huge objects)."),
                  id = str_("Existing artifact id to revise. Omit to create a new artifact."),
                  kind = list(type = "string", enum = I(c("shiny", "html")), default = "shiny", description = "Use 'html' only when a raw HTML/JS page is truly required; the data is then available as window.GPTR_DATA.<name> (column-oriented JSON)."),
                  screenshot = list(type = "boolean", default = TRUE))))
lark = "start: begin_patch hunk+ end_patch\nbegin_patch: \"*** Begin Patch\" LF\nend_patch: \"*** End Patch\" LF?\n\nhunk: add_hunk | delete_hunk | update_hunk\nadd_hunk: \"*** Add File: \" filename LF add_line+\ndelete_hunk: \"*** Delete File: \" filename LF\nupdate_hunk: \"*** Update File: \" filename LF change_move? change?\n\nfilename: /(.+)/\nadd_line: \"+\" /(.*)/ LF -> line\n\nchange_move: \"*** Move to: \" filename LF\nchange: (change_context | change_line)+ eof_line?\nchange_context: (\"@@\" | \"@@ \" /(.+)/) LF\nchange_line: (\"+\" | \"-\" | \" \") /(.*)/ LF\neof_line: \"*** End of File\" LF\n\n%import common.LF\n"
apply_patch_custom = list(type = "custom", name = "apply_patch",
  description = "The `apply_patch` tool can be used to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON.",
  format = list(type = "grammar", syntax = "lark", definition = lark))
apply_patch_fn = tool("apply_patch", "Edit files with a patch in the *** Begin Patch / *** End Patch envelope (Add File, Update File with @@ context and +/- lines, Delete File, Move to).",
                      obj(list(patch = str_("The full patch text")), "patch"))

gptr_tools = list(read = from01("read"), r = r_tool, edit = from01("edit"), write = from01("write"),
                  grep = from01("grep"), find = from01("find"), ls = from01("ls"),
                  r_inspect = r_inspect, ask = ask, agent = agent, artifact = artifact)
snippets = c(read = "Read file contents", r = "Evaluate R code in the live session (objects persist; plots are returned as images)",
             edit = "Make precise file edits with exact text replacement, including multiple disjoint edits in one call",
             write = "Create or overwrite files", grep = "Search file contents for patterns (respects .gitignore)",
             find = "Find files by glob pattern (respects .gitignore)", ls = "List directory contents",
             r_inspect = "Describe objects and look up R help without running code", ask = "Ask the user a question",
             agent = "Delegate a task to a sub-agent", artifact = "Create or revise a Shiny app artifact",
             apply_patch = "Edit files with a patch envelope", bash = "Execute bash commands (ls, grep, find, etc.)")

# ---- system prompts ----
rd = function(f) paste(readLines(file.path(G2, "prompts", f), warn = FALSE), collapse = "\n")
pi_prompt = rd("pi_default.txt")
pi_prompt_nodocs = sub("<docs>.*</docs>\n\n", "", pi_prompt)
gptr_prompt = function(tools, r_perf = TRUE, artifacts = FALSE, extra = NULL, cwd = "/Users/me/project") {
  rules = c("Use read to examine files instead of readLines() or cat() in r.",
            if ("r" %in% tools) c("Use r for computation and data inspection in the live session; do not shell out for things R can do",
                                  "Objects created with r stay in the user's session: do not re-load data that is already in memory, and print compact summaries (str(), head(), dim()) rather than whole objects"),
            if ("edit" %in% tools) T01$edit$promptGuidelines,
            if ("write" %in% tools) "Use write only for new files or complete rewrites.",
            "Be concise in your responses", "Show file paths clearly when working with files")
  txt = paste0("You are an expert R programming and data analysis assistant operating inside gptr, an agent harness that runs inside the user's live R session. You help users by inspecting and computing on the objects in their session, reading files, editing code, and writing new files.\n\n",
               "<tools>\n", paste(sprintf("- %s: %s", tools, snippets[tools]), collapse = "\n"),
               "\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.\n</tools>\n\n",
               "<rules>\n", paste("-", rules, collapse = "\n"), "\n</rules>")
  if (r_perf) txt = paste0(txt, "\n\n", rd("r_performance.txt"))
  if (artifacts) txt = paste0(txt, "\n\n<artifacts>\n", rd("artifacts.txt"), "\n</artifacts>")
  if (!is.null(extra)) txt = paste0(txt, "\n\n", extra)
  paste0(txt, "\n\n<cwd>\n", cwd, "\n</cwd>")
}

# ---- provider wire formats (the request fields a preset contributes) ----
strictify = function(s) {                         # OpenAI strict mode: every property required, optional ones nullable
  if (!is.list(s)) return(s)
  if (identical(s$type, "object") && !is.null(s$properties)) {
    req = unlist(s$required)
    for (p in names(s$properties)) {
      s$properties[[p]] = strictify(s$properties[[p]])
      if (!(p %in% req) && !is.null(s$properties[[p]]$type)) s$properties[[p]]$type = I(c(s$properties[[p]]$type, "null"))
    }
    s$required = I(names(s$properties)); s$additionalProperties = FALSE
  }
  if (identical(s$type, "array") && !is.null(s$items)) s$items = strictify(s$items)
  s
}
wire = function(tools, system, provider, namespace = NULL, strict = FALSE, extra_tools = list()) {
  if (provider == "anthropic") {
    body = list(system = system, tools = c(lapply(tools, function(t) list(name = t$name, description = t$description, input_schema = t$parameters)), extra_tools))
  } else if (provider == "responses") {
    fns = lapply(tools, function(t) {
      f = list(type = "function", name = t$name, description = t$description, parameters = if (strict) strictify(t$parameters) else t$parameters)
      if (strict) f$strict = TRUE
      f
    })
    fns = c(fns, extra_tools)
    if (!is.null(namespace)) fns = list(list(type = "namespace", name = namespace, description = "Tools acting on the user's live R session.", tools = fns))
    body = list(instructions = system, tools = fns)
  } else if (provider == "chat") {
    body = list(messages = list(list(role = "system", content = system)),
                tools = lapply(tools, function(t) list(type = "function", `function` = list(name = t$name, description = t$description, parameters = t$parameters))))
  } else if (provider == "gemini") {
    body = list(systemInstruction = list(parts = list(list(text = system))),
                tools = list(list(functionDeclarations = lapply(tools, function(t) list(name = t$name, description = t$description, parametersJsonSchema = t$parameters)))))
  }
  j(body)
}
