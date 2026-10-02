obj = function(...) list(...)
str_prop = function(d) list(type = "string", description = d)
num_prop = function(d) list(type = "number", description = d)
bool_prop = function(d) list(type = "boolean", description = d)
defs = list(
  read = list(name = "read",
    description = paste("Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp).",
      "Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB",
      "(whichever is hit first). Use offset/limit for large files. When you need the full file,",
      "continue with offset until complete."),
    input_schema = obj(type = "object", required = I("path"), properties = obj(
      path = str_prop("Path to the file to read (relative or absolute)"),
      offset = num_prop("Line number to start reading from (1-indexed)"),
      limit = num_prop("Maximum number of lines to read")))),
  r = list(name = "r",
    description = paste("Run R code in the user's live R session. Objects persist between calls and belong to the",
      "user. Returns printed output, messages, warnings, errors with a traceback, and plots as",
      "images. Execution stops at the first error. Output beyond about 4000 tokens keeps the first 40%",
      "and last 60% and names a gptr$out(id) handle for the rest."),
    input_schema = obj(type = "object", required = I("code"), properties = obj(
      code = str_prop("R code to evaluate. May contain several expressions."),
      record = bool_prop(paste("Record this code in the user's document (default true).",
                               "Use false for throwaway inspection.")),
      note = str_prop("One-line decision or rationale, recorded as a '## Decision:' comment."),
      timeout = num_prop("Seconds; best effort. Default: none when the user is present, else 3600.")))),
  edit = list(name = "edit",
    description = paste("Edit a single file using exact text replacement. Every edits[].oldText must match a unique,",
      "non-overlapping region of the original file. If two changes affect the same block or nearby",
      "lines, merge them into one edit instead of emitting overlapping edits. Do not include large",
      "unchanged regions just to connect distant changes."),
    input_schema = obj(type = "object", required = I(c("path", "edits")), properties = obj(
      path = str_prop("Path to the file to edit (relative or absolute)"),
      edits = list(type = "array",
        items = obj(type = "object", required = I(c("oldText", "newText")), properties = obj(
          oldText = str_prop(paste("Exact text for one targeted replacement. It must be unique in the",
            "original file and must not overlap with any other edits[].oldText in the same call.")),
          newText = str_prop("Replacement text for this targeted edit."))),
        description = paste("One or more targeted replacements. Each edit is matched against the",
          "original file, not incrementally. Do not include overlapping or nested edits. If two",
          "changes touch the same block or nearby lines, merge them into one edit instead."))))),
  write = list(name = "write",
    description = paste("Write content to a file. Creates the file if it doesn't exist, overwrites if",
                        "it does. Automatically creates parent directories."),
    input_schema = obj(type = "object", required = I(c("path", "content")), properties = obj(
      path = str_prop("Path to the file to write (relative or absolute)"),
      content = str_prop("Content to write to the file")))),
  ask = list(name = "ask",
    description = paste("Ask the user one to four questions and wait for the answers, when a decision",
      "changes the result and cannot be inferred. The user may always type their own answer.",
      "Not for permission to run code: the harness asks for that itself."),
    input_schema = obj(type = "object", required = I("questions"), properties = obj(
      questions = list(type = "array", maxItems = 4L, items = obj(type = "object",
        required = I(c("id", "question")), properties = obj(
          id = list(type = "string"), question = list(type = "string"),
          type = list(enum = I(c("single", "multi", "text"))),
          options = list(type = "array", maxItems = 9L, items = list(type = "string")),
          default = list(type = "string"))))))))
j = function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)
writeLines(j(unname(defs[c("read", "r", "edit", "write")])), "tools_min.json")
writeLines(j(unname(defs[c("read", "r", "edit", "write", "ask")])), "tools_std.json")
writeLines(j(unname(defs["ask"])), "tool_ask.json")
writeLines(j(unname(defs["r"])), "tool_r.json")
