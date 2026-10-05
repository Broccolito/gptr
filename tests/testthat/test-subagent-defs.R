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

# Task 8: agent discovery, gptr_agents(), the agent_def.get service, builtin:agents.

agent_text = function(...) paste(agent_lines(...), collapse = "\n")

test_that("gptr_agents lists project and user agents and the project wins", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/reviewer-x.md"]] = agent_text("reviewer-x", "Project reviewer",
                                                     "model: opus")
  files[[".claude/agents/review/deep.md"]] = agent_text("deep", "Nested Claude agent",
                                                        "tools: Read, Bash")
  p = local_project(trust = TRUE, files = files)
  ud = file.path(user_home(), ".claude", "agents")
  dir.create(ud, recursive = TRUE, showWarnings = FALSE)
  writeLines(agent_lines("reviewer-x", "User reviewer"), file.path(ud, "reviewer-x.md"))
  withr::defer(unlink(file.path(ud, "reviewer-x.md")))
  ag = gptr_agents()
  expect_s3_class(ag, "gptr_agents")
  expect_named(ag, c("name", "description", "model", "backend", "source", "path"))
  expect_identical(ag$source[ag$name == "reviewer-x"], c("project", "user"))
  expect_true("deep" %in% gptr_agents("project")$name)
  agent_sync()
  expect_identical(registry_get("agent", "reviewer-x")[["description"]], "Project reviewer")
  expect_identical(registry_get("agent", "deep")[["tools"]], c("read", "r"))
})

test_that("untrusted project agents lose model and tools and never shadow", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/helper-x.md"]] = agent_text("helper-x", "Project helper",
                                                   c("model: opus", "tools: Read, Bash"))
  files[[".gptr/agents/shadow-x.md"]] = agent_text("shadow-x", "Would shadow", body = "Evil.")
  p = local_project(trust = FALSE, files = files)
  ud = file.path(gptr_user_dir("config"), "agents")
  dir.create(ud, recursive = TRUE, showWarnings = FALSE)
  writeLines(agent_lines("shadow-x", "User agent", body = "Good."), file.path(ud, "shadow-x.md"))
  withr::defer(unlink(file.path(ud, "shadow-x.md")))
  agent_sync(mode = "manual")
  a = registry_get("agent", "helper-x")
  expect_null(a[["model"]])
  expect_null(a[["tools"]])
  expect_false(a[["trusted"]])
  expect_identical(registry_get("agent", "shadow-x")[["system"]], "Good.")
  expect_identical(gptr_agents("project")$source[1L], "project (untrusted)")
})

test_that("non-interactive auto and edits runs omit untrusted project agents (IC-52)", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/helper-y.md"]] = agent_text("helper-y", "Project helper")
  p = local_project(trust = FALSE, files = files)
  local_gptr_options(interactive = FALSE)
  agent_sync(mode = "auto")
  expect_null(registry_get("agent", "helper-y"))
  agent_sync(mode = "edits")
  expect_null(registry_get("agent", "helper-y"))
  expect_true("helper-y" %in% gptr_agents("project")$name)
  agent_sync(mode = "manual")
  expect_false(is.null(registry_get("agent", "helper-y")))
})

test_that("agent_def.get backs gptr_agent(name) and gptr_agent(file = )", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/stats-rev.md"]] = agent_text("stats-rev", "Statistical reviewer",
                                                    "model: opus", "Check assumptions.")
  p = local_project(trust = TRUE, files = files)
  get = ext_service_get("agent_def.get")
  a = get("stats_rev")
  expect_identical(a[["name"]], "stats-rev")
  expect_identical(a[["system"]], "Check assumptions.")
  expect_identical(get(file = file.path(p, ".gptr", "agents", "stats-rev.md"))[["model"]], "opus")
  expect_error(get("no-such-agent"), class = "gptr_error_invalid_argument")
  expect_identical(gptr_agent("stats-rev")[["description"]], "Statistical reviewer")
  expect_identical(gptr_agent(file = file.path(p, ".gptr", "agents", "stats-rev.md"))[["name"]],
                   "stats-rev")
})

test_that("a file of an untrusted project loses model and tools through gptr_agent(file =)", {
  files = list()
  files[[".gptr/agents/u.md"]] = agent_text("u-agent", "Untrusted",
                                            c("model: opus", "tools: Bash"))
  p = local_project(trust = FALSE, files = files)
  a = gptr_agent(file = file.path(p, ".gptr", "agents", "u.md"))
  expect_null(a[["model"]])
  expect_null(a[["tools"]])
})

test_that("builtin:agents syncs on session start and registers the service", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/hooked.md"]] = agent_text("hooked", "Synced by the hook")
  p = local_project(trust = TRUE, files = files)
  agents_on_session_start(list(type = "session_start"), list(session = NULL))
  expect_false(is.null(registry_get("agent", "hooked")))
  hooks = Filter(function(h) identical(h[["event"]], "session_start"), registry_all("hook"))
  expect_true(any(vapply(hooks, function(h) identical(h$handler, agents_on_session_start), NA)))
  expect_true(ext_service_has("agent_def.get"))
})

# Task 8 adaptations (D-134)

agent_session_start = function(depth, mode) {
  s = new.env(parent = emptyenv())
  d = new.env(parent = emptyenv())
  d$depth = depth
  d$mode = mode
  assign(".d", d, envir = s)
  agents_on_session_start(list(type = "session_start"), list(session = s))
}

test_that("agent_def.get re-syncs after trust, project or file changes", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/stale-a.md"]] = agent_text("stale-a", "Project agent",
                                                  c("model: opus", "tools: Read"), "One.")
  p = local_project(trust = TRUE, files = files)
  get = ext_service_get("agent_def.get")
  expect_identical(get("stale-a")[["model"]], "opus")
  gptr_trust(p, FALSE)
  expect_error(get("stale-a"), class = "gptr_error_untrusted")
  q = local_project(trust = TRUE)
  expect_error(get("stale-a"), class = "gptr_error_invalid_argument")
  ud = file.path(user_home(), ".claude", "agents")
  dir.create(ud, recursive = TRUE, showWarnings = FALSE)
  f = file.path(ud, "edit-a.md")
  withr::defer(unlink(f))
  writeLines(agent_lines("edit-a", "User agent", body = "Old."), f)
  expect_identical(get("edit-a")[["system"]], "Old.")
  writeLines(agent_lines("edit-a", "User agent", body = "Newer text."), f)
  expect_identical(get("edit-a")[["system"]], "Newer text.")
  unlink(f)
  expect_error(get("edit-a"), class = "gptr_error_invalid_argument")
})

test_that("an untrusted project agent never shadows an agent that other code registered", {
  withr::defer(res_prune("agents:", character()))
  off = gptr_register(gptr_agent("ext-x", description = "Registered by the user",
                                 system = "Good."))
  withr::defer(off())
  files = list()
  files[[".gptr/agents/ext-x.md"]] = agent_text("ext-x", "Project copy", body = "Evil.")
  files[[".gptr/agents/only-x.md"]] = agent_text("only-x", "Project only")
  p = local_project(trust = FALSE, files = files)
  agent_sync(mode = "manual")
  expect_identical(registry_get("agent", "ext-x")[["system"]], "Good.")
  expect_false(registry_get("agent", "only-x")[["trusted"]])
  later = gptr_register(gptr_agent("only-x", description = "Registered later", system = "Good."))
  withr::defer(later())
  expect_identical(registry_get("agent", "only-x")[["system"]], "Good.")
  expect_identical(gptr_agent("ext-x")[["system"]], "Good.")
  gptr_trust(p, TRUE)
  agent_sync(mode = "manual")
  expect_identical(registry_get("agent", "ext-x")[["system"]], "Evil.")
})

test_that("an untrusted project agent never shadows a name equal after normalisation (IC-42)", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/norm.md"]] = agent_text("norm_y", "Project copy", body = "Evil.")
  p = local_project(trust = FALSE, files = files)
  ud = file.path(gptr_user_dir("config"), "agents")
  dir.create(ud, recursive = TRUE, showWarnings = FALSE)
  writeLines(agent_lines("norm-y", "User agent", body = "Good."), file.path(ud, "norm-y.md"))
  withr::defer(unlink(file.path(ud, "norm-y.md")))
  agent_sync(mode = "manual")
  expect_null(registry_get("agent", "norm_y"))
  expect_identical(gptr_agent("norm_y")[["system"]], "Good.")
  expect_true("norm_y" %in% gptr_agents("project")$name)
})

test_that("only .pi agent directories are flat, wherever the project lies", {
  base = withr::local_tempdir()
  root = path_norm(file.path(base, ".pi", "proj"))
  dir.create(file.path(root, ".gptr", "agents", "sub"), recursive = TRUE)
  dir.create(file.path(root, ".pi", "agents", "sub"), recursive = TRUE)
  dir.create(file.path(root, ".pi", "agents", "dir.md"))
  writeLines(agent_lines("nested-g", "Nested gptr agent"),
             file.path(root, ".gptr", "agents", "sub", "n.md"))
  writeLines(agent_lines("flat-pi", "Flat Pi agent"), file.path(root, ".pi", "agents", "f.md"))
  writeLines(agent_lines("deep-pi", "Nested Pi agent"),
             file.path(root, ".pi", "agents", "sub", "d.md"))
  withr::local_dir(root)
  local_gptr_options(project_root = root)
  nm = gptr_agents("project")$name
  expect_true("nested-g" %in% nm)
  expect_true("flat-pi" %in% nm)
  expect_false("deep-pi" %in% nm)
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_false(any(grepl("dir.md", msgs, fixed = TRUE)))
  ud = file.path(user_home(), ".pi", "agent", "agents")
  dir.create(file.path(ud, "sub"), recursive = TRUE, showWarnings = FALSE)
  withr::defer(unlink(c(file.path(ud, "u.md"), file.path(ud, "sub")), recursive = TRUE))
  writeLines(agent_lines("pi-user", "Flat"), file.path(ud, "u.md"))
  writeLines(agent_lines("pi-user-deep", "Nested"), file.path(ud, "sub", "v.md"))
  nm = gptr_agents("user")$name
  expect_true("pi-user" %in% nm)
  expect_false("pi-user-deep" %in% nm)
})

test_that("a name lookup serves no untrusted project agent when nobody can confirm (IC-52)", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/omit-x.md"]] = agent_text("omit-x", "Project helper", body = "Do evil.")
  p = local_project(trust = FALSE, files = files)
  local_gptr_options(interactive = FALSE, mode = "manual")
  err = expect_error(gptr_agent("omit_x"), class = "gptr_error_untrusted")
  expect_identical(err$what, "agent")
  expect_identical(err$origin, "project")
  expect_identical(err$path, path_norm(file.path(p, ".gptr", "agents", "omit-x.md")))
  expect_error(gptr_agent("omit-y"), class = "gptr_error_invalid_argument")
  agent_session_start(0L, "manual")
  expect_false(registry_get("agent", "omit-x")[["trusted"]])
  expect_error(gptr_agent("omit-x"), class = "gptr_error_untrusted")
  expect_false("omit-x" %in% registry_names("agent"))
  local_gptr_options(interactive = TRUE)
  expect_false(gptr_agent("omit-x")[["trusted"]])
})

test_that("the session_start hook syncs top-level sessions in their own mode only", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/hook-u.md"]] = agent_text("hook-u", "Untrusted helper")
  p = local_project(trust = FALSE, files = files)
  agent_session_start(0L, "auto")
  expect_null(registry_get("agent", "hook-u"))
  agent_session_start(1L, "manual")
  expect_null(registry_get("agent", "hook-u"))
  agent_session_start(0L, "manual")
  expect_false(is.null(registry_get("agent", "hook-u")))
})

test_that("an untrusted project agent never shadows a registered agent after normalisation", {
  withr::defer(res_prune("agents:", character()))
  local_gptr_options(interactive = TRUE)
  off = gptr_register(gptr_agent("ext-x", description = "Registered by the user",
                                 system = "Good."))
  withr::defer(off())
  files = list()
  files[[".gptr/agents/ext.md"]] = agent_text("ext_x", "Project copy", body = "Evil.")
  p = local_project(trust = FALSE, files = files)
  agent_sync(mode = "manual")
  expect_null(registry_get("agent", "ext_x"))
  expect_identical(gptr_agent("ext_x")[["system"]], "Good.")
  expect_identical(gptr_agent("ext.x")[["system"]], "Good.")
  expect_true("ext_x" %in% gptr_agents("project")$name)
  off()
  expect_false(gptr_agent("ext_x")[["trusted"]])
  expect_identical(gptr_agent("ext_x")[["system"]], "Evil.")
  off = gptr_register(gptr_agent("ext-x", description = "Registered again", system = "Good."))
  expect_identical(gptr_agent("ext_x")[["system"]], "Good.")
  expect_null(registry_get("agent", "ext_x"))
})

test_that("omitting untrusted project agents gives one notice per project (IC-52)", {
  withr::defer(res_prune("agents:", character()))
  files = list()
  files[[".gptr/agents/note-x.md"]] = agent_text("note-x", "Project helper")
  p = local_project(trust = FALSE, files = files)
  local_gptr_options(interactive = FALSE, quiet = FALSE)
  expect_message(agent_sync(mode = "auto"), "not trusted", class = "gptr_message_notice")
  expect_null(registry_get("agent", "note-x"))
  expect_no_message(agent_sync(mode = "edits"))
})
