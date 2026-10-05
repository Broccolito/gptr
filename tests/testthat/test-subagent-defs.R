# Tests of R/subagent-defs.R (plan P17). Task 7: the tool-name map and agent files.

agent_lines = function(name, desc, extra = character(), body = "System text.") {
  c("---", paste0("name: ", name), paste0("description: ", desc), extra, "---", "", body)
}

test_that("tool_name_map maps Claude and Pi names (contract example)", {
  expect_identical(tool_name_map(c("Read", "Bash", "Glob")), c("read", "r", "find"))
  expect_identical(tool_name_map(c("Write", "Edit", "MultiEdit", "PowerShell", "Grep", "LS")),
                   c("write", "edit", "r", "grep", "ls"))
  expect_identical(tool_name_map(c("Task", "Agent", "mcp__github__search_code")),
                   "mcp__github__search_code")
  m = tool_name_map(c("Bash(git diff *)", "NotebookEdit", "read", "ask"))
  expect_identical(as.character(m), c("r", "read", "ask"))
  expect_identical(attr(m, "unknown"), "NotebookEdit")
  expect_identical(tool_name_map("AskUserQuestion"), "ask")
  expect_identical(tool_name_map(character()), character())
})

test_that("agent_file_parse reads a Claude Code agent file (report 16 section 3.8)", {
  root = withr::local_tempdir()
  f = file.path(root, "stats.md")
  extra = c(
    "tools: [Read, Grep, Glob, \"Bash(Rscript *)\", mcp__github__search_code, NotebookEdit]",
    "model: opus", "maxTurns: 12", "permissionMode: plan", "skills: statistics, single-cell",
    "color: blue"
  )
  writeLines(agent_lines("stats-reviewer", "Reviews statistical methodology.", extra,
                         "You are a careful statistician."), f)
  a = agent_file_parse(f)
  expect_s3_class(a, "gptr_agent")
  expect_identical(a[["name"]], "stats-reviewer")
  expect_identical(a[["tools"]], c("read", "grep", "find", "r", "mcp__github__search_code"))
  expect_identical(a[["model"]], "opus")
  expect_identical(a[["max_turns"]], 12L)
  expect_identical(a[["mode"]], "plan")
  expect_identical(a[["skills"]], c("statistics", "single-cell"))
  expect_identical(a[["system"]], "You are a careful statistician.")
  expect_identical(a[["backend"]], "auto")
  expect_identical(a[["preset"]], "minimal")
  expect_identical(a[["file"]], path_norm(f))
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("unknown tools ignored: NotebookEdit", msgs, fixed = TRUE)))
})

test_that("model inherit, Pi tool names and Pi's mode: inline map correctly", {
  root = withr::local_tempdir()
  f = file.path(root, "scout.md")
  writeLines(agent_lines("scout", "Fast recon", c("tools: read, grep, find, ls, bash",
                                                  "model: inherit", "mode: inline"),
                         "Look first."), f)
  a = agent_file_parse(f)
  expect_null(a[["model"]])
  expect_identical(a[["tools"]], c("read", "grep", "find", "ls", "r"))
  expect_identical(a[["backend"]], "inline")
  expect_null(a[["mode"]])
})

test_that("documentation files are skipped silently; broken agent files are diagnosed", {
  root = withr::local_tempdir()
  writeLines("# Agents in this folder", file.path(root, "README.md"))
  writeLines(c("---", "description: no name", "---", "x"), file.path(root, "noname.md"))
  writeLines(c("---", "name: broken", "description: [unclosed", "---", "x"),
             file.path(root, "broken.md"))
  writeLines(c("---", "name: a:b", "description: colon", "---", "x"), file.path(root, "colon.md"))
  writeLines(c("---", "name: text", "description: an accessor name", "---", "x"),
             file.path(root, "text.md"))
  for (f in c("README.md", "noname.md", "broken.md", "colon.md", "text.md")) {
    expect_null(agent_file_parse(file.path(root, f)))
  }
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("broken.md", msgs, fixed = TRUE)))
  expect_true(any(grepl("invalid name", msgs, fixed = TRUE)))
  expect_true(any(grepl("session accessor name", msgs, fixed = TRUE)))
})

# Task 7 adaptations (D-086)

agent_probe = function(root, extra) {
  f = file.path(root, "probe.md")
  writeLines(agent_lines("probe-x", "Probe", extra), f)
  agent_file_parse(f)
}

test_that("a sequence as mode or permissionMode never throws", {
  root = withr::local_tempdir()
  modes = c("mode: [inline, plan]", "permissionMode: [plan, auto]")
  for (extra in modes) expect_no_error(agent_probe(root, extra))
  a = agent_probe(root, modes[[1L]])
  expect_s3_class(a, "gptr_agent")
  expect_identical(a[["backend"]], "auto")
  expect_null(a[["mode"]])
  expect_null(agent_probe(root, modes[[2L]])[["mode"]])
})

test_that("a sequence or a map as the turn limit never throws", {
  root = withr::local_tempdir()
  limits = c("max_turns: {a: [1, 2]}", "maxTurns: [[1, 2]]")
  for (extra in limits) expect_no_error(agent_probe(root, extra))
  for (extra in limits) {
    a = agent_probe(root, extra)
    expect_s3_class(a, "gptr_agent")
    expect_null(a[["max_turns"]])
  }
})

test_that("a turn limit is a positive whole number or its text", {
  root = withr::local_tempdir()
  turns = function(line) agent_probe(root, line)[["max_turns"]]
  expect_identical(turns("max_turns: \"12\""), 12L)
  expect_identical(turns("maxTurns: 3.0"), 3L)
  expect_null(turns("max_turns: 2.7"))
  expect_null(turns("maxTurns: true"))
  expect_null(turns("max_turns: {a: 1}"))
  expect_null(turns("max_turns: 0"))
  expect_null(turns("maxTurns: 1e12"))
})

test_that("Claude permission modes map to gptr modes next to Pi's backend mode", {
  expect_identical(agent_mode("default"), "manual")
  expect_identical(agent_mode("acceptEdits"), "edits")
  expect_identical(agent_mode("bypassPermissions"), "auto")
  expect_identical(agent_mode("dontAsk"), "auto")
  expect_null(agent_mode("yolo"))
  expect_null(agent_mode(NA_character_))
  root = withr::local_tempdir()
  a = agent_probe(root, c("mode: worker", "permissionMode: acceptEdits"))
  expect_identical(a[["backend"]], "worker")
  expect_identical(a[["mode"]], "edits")
})

# Task 7 review fixes (D-086)

test_that("permissionMode applies whenever mode is not a permission mode", {
  root = withr::local_tempdir()
  a = agent_probe(root, c("backend: worker", "mode: inline", "permissionMode: plan"))
  expect_identical(a[["backend"]], "worker")
  expect_identical(a[["mode"]], "plan")
  expect_identical(agent_probe(root, c("mode: bogus", "permissionMode: plan"))[["mode"]], "plan")
  a = agent_probe(root, c("mode: [inline, plan]", "permissionMode: plan"))
  expect_identical(a[["backend"]], "auto")
  expect_identical(a[["mode"]], "plan")
  expect_identical(agent_probe(root, c("mode: auto", "permissionMode: plan"))[["mode"]], "auto")
})

test_that("documentation files give no diagnostic", {
  root = withr::local_tempdir()
  writeLines("# Agents in this folder", file.path(root, "README.md"))
  writeLines(c("---", "description: no name", "---", "x"), file.path(root, "noname.md"))
  writeLines(c("---", "---", "Empty frontmatter."), file.path(root, "empty.md"))
  writeLines(c("---", "name: a:b", "description: control", "---", "x"),
             file.path(root, "control.md"))
  for (f in c("README.md", "noname.md", "empty.md", "control.md")) {
    expect_null(agent_file_parse(file.path(root, f)))
  }
  msgs = gptr_registry(diagnostics = TRUE)$message
  mine = msgs[grepl(basename(root), msgs, fixed = TRUE)]
  expect_length(mine, 1L)
  expect_match(mine, "control.md: invalid name", fixed = TRUE)
})

test_that("a tools value that is not a list of names is diagnosed, not dropped silently", {
  root = withr::local_tempdir()
  parse_tools = function(file, line) {
    f = file.path(root, file)
    writeLines(agent_lines("probe-x", "Probe", line), f)
    agent_file_parse(f)
  }
  nested = parse_tools("nested.md", "tools: [[Read, Grep]]")
  empty = parse_tools("empty.md", "tools: []")
  fine = parse_tools("fine.md", "tools: Read, Grep")
  expect_s3_class(nested, "gptr_agent")
  expect_null(nested[["tools"]])
  expect_null(empty[["tools"]])
  expect_identical(fine[["tools"]], c("read", "grep"))
  msgs = gptr_registry(diagnostics = TRUE)$message
  hit = function(file) {
    key = paste0(file.path(basename(root), file), ": tools must be a comma list or an array")
    any(grepl(key, msgs, fixed = TRUE))
  }
  expect_true(hit("nested.md"))
  expect_true(hit("empty.md"))
  expect_false(hit("fine.md"))
})
