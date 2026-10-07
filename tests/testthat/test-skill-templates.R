# Tests of R/skill-templates.R (plan P17). Task 5: Pi's template grammar.

pi_oracle = function() {
  path = test_path("fixtures", "oracles", "pi-templates", "templates.json")
  json_decode(read_utf8(path)$text)
}

# Pi's `/name args` expansion for the oracle: Pi's command pattern (report 05 section 3.7) and a
# named list of template texts
template_expand_input = function(text, lookup) {
  mm = regmatches(text, regexec("^/([^\\s]+)(?:\\s+([\\s\\S]*))?$", text, perl = TRUE))[[1L]]
  if (!length(mm) || !(mm[2L] %in% names(lookup))) return(text)
  template_substitute(lookup[[mm[2L]]], template_args_parse(mm[3L]))
}

test_that("Pi's 67 template tests pass (report 05 section 5.1)", {
  o = pi_oracle()
  n = 0L
  for (case in o$substitute) {
    got = template_substitute(case$template, as.character(unlist(case$args)))
    expect_identical(charToRaw(got), charToRaw(case$expected),
                     label = paste("substitute:", case$template))
    n = n + 1L
  }
  for (case in o$parse) {
    got = template_args_parse(case$input)
    want = as.character(unlist(case$expected))
    expect_identical(lapply(got, charToRaw), lapply(want, charToRaw),
                     label = paste("parse:", case$input))
    n = n + 1L
  }
  for (case in o$expand) {
    got = template_expand_input(case$input, o$templates)
    expect_identical(charToRaw(got), charToRaw(case$expected), label = paste("expand:", case$input))
    n = n + 1L
  }
  expect_identical(n, 67L)
})

test_that("template_expand takes the raw argument string or a vector (contract example)", {
  expect_identical(template_expand("Review $1 for $ARGUMENTS", "analysis.R statistics"),
                   "Review analysis.R for analysis.R statistics")
  expect_identical(template_expand("$2", c("a b", "c")), "c")
  expect_identical(template_expand("Hi $1", NULL), "Hi ")
  expect_error(template_expand(NA_character_, "x"), class = "gptr_error_invalid_argument")
})

test_that("$ARGUMENTS[N] is Claude's 0-based index", {
  expect_identical(template_expand("$ARGUMENTS[0] and $ARGUMENTS[1]", "x y"), "x and y")
  expect_identical(template_expand("$ARGUMENTS[5]", "x"), "")
  expect_identical(template_expand("$ARGUMENTS", "x y"), "x y")
})

test_that("substitution keeps UTF-8 bytes in any locale", {
  cafe = paste0("caf", intToUtf8(0xE9L))
  kanji = intToUtf8(c(0x65E5L, 0x672CL))
  got = template_expand(paste(cafe, "$1"), kanji)
  expect_identical(charToRaw(got), charToRaw(paste(cafe, kanji)))
  expect_identical(Encoding(got), "UTF-8")
})

# Task 5 adaptations (D-084)

test_that("arguments split on the command pattern's ASCII whitespace in every locale (D-084)", {
  expect_identical(template_args_parse("a\vb\fc\rd"), c("a", "b", "c", "d"))
  for (cp in c(0x00A0L, 0x1680L, 0x2003L, 0x2028L, 0x3000L)) {
    word = paste0("x", intToUtf8(cp), "y")
    got = template_args_parse(paste(word, "z"))
    expect_identical(lapply(got, charToRaw), lapply(c(word, "z"), charToRaw),
                     label = sprintf("U+%04X", cp))
    got = template_expand_input(paste("/review", word), list(review = "<$1>"))
    expect_identical(charToRaw(got), charToRaw(paste0("<", word, ">")),
                     label = sprintf("/review with U+%04X", cp))
  }
})

test_that("a long pasted argument is split in linear time (D-084)", {
  long = strrep("x", 100000L)
  elapsed = system.time({
    got = template_args_parse(paste0("\"", long, "\" ", long))
  })
  expect_identical(nchar(got), c(100000L, 100000L))
  expect_lt(elapsed[["elapsed"]], 5)
})

# Task 5 review round 1

test_that("a latin1 argument string is converted before it is joined, in any locale", {
  withr::local_locale(c(LC_CTYPE = "C"))
  l1 = "caf\xe9 x"
  Encoding(l1) = "latin1"
  cafe = paste0("caf", intToUtf8(0xE9L))
  got = template_args_parse(l1)
  expect_identical(lapply(got, charToRaw), lapply(c(cafe, "x"), charToRaw))
  expect_identical(charToRaw(template_expand("$1", l1)), charToRaw(cafe))
  expect_identical(charToRaw(template_expand("$1", c(l1, "y"))), charToRaw(paste(cafe, "x")))
})

# Task 6: template files, commands, builtin:prompts.

test_that("template_parse reads description, argument-hint and the body", {
  root = withr::local_tempdir()
  f = file.path(root, "triage.md")
  writeLines(c("---", "description: Triage an issue", "argument-hint: \"<issue> [area]\"", "---",
               "Triage $1 in ${2:-the package}."), f)
  t = template_parse(f)
  expect_s3_class(t, "gptr_prompt_template")
  expect_identical(t[["name"]], "triage")
  expect_identical(t[["description"]], "Triage an issue")
  expect_identical(t[["argument_hint"]], "<issue> [area]")
  expect_identical(t[["text"]], "Triage $1 in ${2:-the package}.")
  g = file.path(root, "long.md")
  writeLines(c("", strrep("x", 70)), g)
  expect_identical(template_parse(g)[["description"]], paste0(strrep("x", 60), "..."))
})

test_that("template_sync registers templates and one command per template", {
  withr::defer(res_prune("prompts:", character()))
  p = local_project(trust = TRUE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines(c("---", "description: Triage an issue", "---", "Triage $1."),
             file.path(p, ".gptr", "prompts", "triage.md"))
  template_sync()
  expect_false(is.null(registry_get("prompt_template", "triage")))
  cmd = registry_get("command", "triage")
  expect_identical(cmd[["template"]], "triage")
  expect_identical(cmd[["description"]], "Triage an issue")
  expect_identical(cmd$handler("#12", NULL), list(prompt = "Triage #12."))
})

test_that("a template that code registers is a command unless a file template shadows it", {
  withr::defer(res_prune("prompts:", character()))
  withr::defer(res_prune("templates:", character()))
  ids = c(registry_add(gptr_spec("prompt_template", "p17-codet", text = "Code $1"),
                       source = "plugin:p17-tpl", rank = 5L),
          registry_add(gptr_spec("prompt_template", "p17-dupt", text = "Plugin $1"),
                       source = "plugin:p17-tpl", rank = 5L))
  withr::defer(for (id in ids) registry_remove(id))
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("File $1", file.path(user, "p17-dupt.md"))
  withr::defer(unlink(file.path(user, "p17-dupt.md")))
  template_sync()
  expect_identical(registry_get("command", "p17-codet")$handler("x", NULL),
                   list(prompt = "Code x"))
  expect_identical(registry_get("command", "p17-dupt")$handler("x", NULL),
                   list(prompt = "File x"))
  reg = gptr_registry()
  expect_identical(sum(reg$kind == "command" & reg$name == "p17-dupt"), 1L)
})

test_that("an untrusted project's templates are not registered", {
  withr::defer(res_prune("prompts:", character()))
  p = local_project(trust = FALSE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("Do something else with $1.", file.path(p, ".gptr", "prompts", "sneaky.md"))
  template_sync()
  expect_null(registry_get("prompt_template", "sneaky"))
  expect_null(registry_get("command", "sneaky"))
})

test_that("a template never shadows a command registered by something else", {
  withr::defer(res_prune("prompts:", character()))
  off = gptr_register(gptr_command("p17-busy", function(args, ctx) "real"))
  withr::defer(off())
  root = file.path(gptr_user_dir("config"), "prompts")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  writeLines("Template body $1", file.path(root, "p17-busy.md"))
  withr::defer(unlink(file.path(root, "p17-busy.md")))
  template_sync()
  expect_false(is.null(registry_get("prompt_template", "p17-busy")))
  expect_identical(registry_get("command", "p17-busy")$handler("", NULL), "real")
  msgs = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("/p17-busy is an existing command", msgs, fixed = TRUE)))
})

test_that("builtin:prompts ships /review and /explain as commands", {
  withr::defer(res_prune("prompts:", character()))
  template_sync()
  expect_match(registry_get("command", "review")$handler("analysis.R", NULL)$prompt,
               "^Review analysis.R for correctness, statistical validity and reproducibility.")
  expect_match(registry_get("command", "explain")$handler("fit", NULL)$prompt,
               "^Explain fit for someone who knows R")
  files = list.files(system.file("gptr", "prompts", package = "gptr"), full.names = TRUE)
  expect_setequal(basename(files), c("review.md", "explain.md"))
  txt = vapply(files, function(f) paste(readLines(f, encoding = "UTF-8"), collapse = "\n"), "")
  expect_false(any(grepl("(^|[^A-Za-z0-9_.])str\\(", txt)))
  expect_true(all(vapply(txt, function(x) all(utf8ToInt(x) < 128L), NA)))
})

test_that("Claude plugin commands are /<plugin>:<cmd>, also reachable as /<plugin> <cmd>", {
  root = withr::local_tempdir()
  dir.create(file.path(root, "commands"))
  writeLines(c("---", "description: Show the status", "---", "Status of $ARGUMENTS."),
             file.path(root, "commands", "status.md"))
  specs = template_command_specs(file.path(root, "commands"), list(name = "ops-kit"))
  ids = vapply(specs, function(s) paste(s[["kind"]], s[["name"]]), "")
  expect_identical(sort(ids, method = "radix"),
                   c("command ops-kit", "command ops-kit:status", "prompt_template ops-kit:status"))
  disp = specs[[match("command ops-kit", ids)]]
  expect_identical(disp$handler("status prod", NULL), list(prompt = "Status of prod."))
  expect_match(disp$handler("nope", NULL), "/ops-kit:status", fixed = TRUE)
  expect_identical(specs[[match("prompt_template ops-kit:status", ids)]][["source"]],
                   "plugin:ops-kit")
})

test_that("the session_start hook of builtin:prompts syncs top-level sessions only", {
  withr::defer(res_prune("prompts:", character()))
  res_prune("prompts:", character())
  expect_null(registry_get("command", "review"))
  prompts_on_session_start(list(type = "session_start"), list(session = NULL))
  expect_false(is.null(registry_get("command", "review")))
  hooks = Filter(function(h) identical(h[["event"]], "session_start"), registry_all("hook"))
  expect_true(any(vapply(hooks, function(h) identical(h$handler, prompts_on_session_start), NA)))
})

# Task 6 adaptations (D-133)

test_that("a command registered after the sync wins over same-named templates (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  p = local_project(trust = TRUE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("Project $1", file.path(p, ".gptr", "prompts", "p17-late.md"))
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("User $1", file.path(user, "p17-late.md"))
  withr::defer(unlink(file.path(user, "p17-late.md")))
  run = function() registry_get("command", "p17-late")$handler("x", NULL)
  template_sync()
  expect_identical(run(), list(prompt = "Project x"))
  off = gptr_register(gptr_command("p17-late", function(args, ctx) "real"))
  withr::defer(off())
  expect_identical(run(), "real")
  expect_false(is.null(registry_get("prompt_template", "p17-late")))
  template_sync()
  expect_identical(run(), "real")
})

test_that("a template gets its command once the command of its name is removed (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  off = gptr_register(gptr_command("p17-gone", function(args, ctx) "real"))
  withr::defer(off())
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("User $1", file.path(user, "p17-gone.md"))
  withr::defer(unlink(file.path(user, "p17-gone.md")))
  template_sync()
  expect_identical(registry_get("command", "p17-gone")$handler("x", NULL), "real")
  off()
  template_sync()
  cmd = registry_get("command", "p17-gone")
  expect_false(is.null(cmd))
  expect_identical(cmd[["template"]], "p17-gone")
})

test_that("a project template runs only while a sync would register it (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  p = local_project(trust = TRUE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("Project $1", file.path(p, ".gptr", "prompts", "p17-both.md"))
  writeLines("Project only $1", file.path(p, ".gptr", "prompts", "p17-only.md"))
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("User $1", file.path(user, "p17-both.md"))
  withr::defer(unlink(file.path(user, "p17-both.md")))
  template_sync()
  both = registry_get("command", "p17-both")
  only = registry_get("command", "p17-only")
  expect_identical(both$handler("x", NULL), list(prompt = "Project x"))
  expect_identical(only$handler("x", NULL), list(prompt = "Project only x"))
  gptr_trust(p, FALSE)
  expect_identical(both$handler("x", NULL), list(prompt = "User x"))
  out = only$handler("x", NULL)
  expect_true(is.character(out))
  expect_match(out, "/p17-only", fixed = TRUE)
  expect_null(registry_get("command", "p17-only"))
  expect_null(registry_get("prompt_template", "p17-only"))
})

test_that("a project template is not run from another trusted project (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  a = local_project(trust = TRUE)
  dir.create(file.path(a, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("From A $1", file.path(a, ".gptr", "prompts", "p17-from-a.md"))
  template_sync()
  cmd = registry_get("command", "p17-from-a")
  expect_identical(cmd$handler("x", NULL), list(prompt = "From A x"))
  b = local_project(trust = TRUE)
  expect_true(is.character(cmd$handler("x", NULL)))
  expect_null(registry_get("command", "p17-from-a"))
})

test_that("a plugin's code commands win over templates, its template commands do not (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  ids = c(registry_add(gptr_command("p17-code", function(args, ctx) "code"),
                       source = "plugin:p17-fake", rank = 5L),
          registry_add(gptr_command("p17-decl", function(args, ctx) "decl"),
                       source = "plugin:p17-fake", rank = 5L))
  withr::defer(for (id in ids) registry_remove(id))
  st = res_state()
  st$plugins[["p17-fake"]] = list(name = "p17-fake", kind = "directory", enabled = TRUE,
                                  failed = FALSE, session = NULL, ids = ids[2L],
                                  decl = "command:p17-decl",
                                  provides = c("command:p17-decl", "command:p17-code"))
  withr::defer({
    st$plugins[["p17-fake"]] = NULL
  })
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  for (f in c("p17-code.md", "p17-decl.md")) writeLines("Template $1", file.path(user, f))
  withr::defer(unlink(file.path(user, c("p17-code.md", "p17-decl.md"))))
  template_sync()
  expect_identical(registry_get("command", "p17-code")$handler("x", NULL), "code")
  expect_identical(registry_get("command", "p17-decl")$handler("x", NULL),
                   list(prompt = "Template x"))
})

test_that("the /<plugin> dispatcher splits on ASCII whitespace in every locale (D-133)", {
  root = withr::local_tempdir()
  dir.create(file.path(root, "commands"))
  writeLines("Status of $ARGUMENTS.", file.path(root, "commands", "status.md"))
  specs = template_command_specs(file.path(root, "commands"), list(name = "ops-kit"))
  disp = Filter(function(s) identical(s[["name"]], "ops-kit"), specs)[[1L]]
  expect_identical(disp$handler("\vstatus\fprod", NULL), list(prompt = "Status of prod."))
  for (cp in c(0x00A0L, 0x2003L, 0x3000L)) {
    out = disp$handler(paste0("status", intToUtf8(cp), "prod"), NULL)
    expect_true(is.character(out), label = sprintf("U+%04X", cp))
  }
})

test_that("only files are template files (D-133)", {
  root = withr::local_tempdir()
  dir.create(file.path(root, "dir.md"))
  writeLines("x", file.path(root, "a.md"))
  expect_identical(res_md_files(root), file.path(root, "a.md"))
})

# Task 6 review round 1 (D-133): ownership by record id; ASCII whitespace in template names

test_that("a filtered template command does not hide a later command (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  template_sync()
  expect_identical(registry_get("command", "review")[["template"]], "review")
  local_without_builtin("prompts")
  off = gptr_register(gptr_command("review", function(args, ctx) "real"))
  withr::defer(off())
  p = local_project(trust = TRUE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("Project review $1", file.path(p, ".gptr", "prompts", "review.md"))
  template_sync()
  expect_identical(registry_get("command", "review")$handler("x", NULL), "real")
  expect_true("review" %in% res_foreign_names("command"))
})

test_that("a filtered template command does not keep a user template running (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("User review $1", file.path(user, "review.md"))
  withr::defer(unlink(file.path(user, "review.md")))
  template_sync()
  expect_identical(registry_get("command", "review")$handler("x", NULL),
                   list(prompt = "User review x"))
  local_without_builtin("prompts")
  off = gptr_register(gptr_command("review", function(args, ctx) "real"))
  withr::defer(off())
  expect_identical(registry_get("command", "review")$handler("x", NULL), "real")
})

test_that("a template record removed elsewhere does not hide a later command (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  writeLines("User $1", file.path(user, "p17-unl.md"))
  withr::defer(unlink(file.path(user, "p17-unl.md")))
  template_sync()
  for (id in res_state()$groups[["prompts:user"]]$ids) registry_remove(id)
  off = gptr_register(gptr_command("p17-unl", function(args, ctx) "real"))
  withr::defer(off())
  p = local_project(trust = TRUE)
  dir.create(file.path(p, ".gptr", "prompts"), showWarnings = FALSE)
  writeLines("Project $1", file.path(p, ".gptr", "prompts", "p17-unl.md"))
  template_sync()
  expect_identical(registry_get("command", "p17-unl")$handler("x", NULL), "real")
})

test_that("a template name may not hold ASCII whitespace, in every locale (D-133)", {
  root = withr::local_tempdir()
  f = file.path(root, "x.md")
  writeLines("Body $1", f)
  for (cp in c(0x00A0L, 0x2003L, 0x3000L)) {
    nm = paste0("a", intToUtf8(cp), "b")
    t = template_parse(f, nm)
    expect_s3_class(t, "gptr_prompt_template")
    expect_identical(t[["name"]], nm, label = sprintf("U+%04X", cp))
  }
  for (ws in c(" ", "\t", "\v", "\f", "\r", "\n")) {
    expect_null(template_parse(f, paste0("a", ws, "b")))
  }
})

test_that("only enabled process-level commands of others hold a template's name (D-133)", {
  withr::defer(res_prune("prompts:", character()))
  old = registry_env()$filters$session
  withr::defer(registry_filters_set(old, "session"))
  ids = c(registry_add(gptr_command("p17-off", function(args, ctx) "code"),
                       source = "plugin:p17-off", rank = 5L),
          registry_add(gptr_command("p17-sess", function(args, ctx) "session"),
                       source = "session", rank = 0L, session = "p17-s1"))
  withr::defer(for (id in ids) registry_remove(id))
  registry_filters_set("-plugin:p17-off", "session")
  user = file.path(gptr_user_dir("config"), "prompts")
  dir.create(user, recursive = TRUE, showWarnings = FALSE)
  for (f in c("p17-off.md", "p17-sess.md")) writeLines("Template $1", file.path(user, f))
  withr::defer(unlink(file.path(user, c("p17-off.md", "p17-sess.md"))))
  template_sync()
  expect_false(any(c("p17-off", "p17-sess") %in% res_foreign_names("command")))
  expect_identical(registry_get("command", "p17-off")$handler("x", NULL),
                   list(prompt = "Template x"))
  expect_identical(registry_get("command", "p17-sess")$handler("x", NULL),
                   list(prompt = "Template x"))
  registry_filters_set(old, "session")
  expect_identical(registry_get("command", "p17-off")$handler("x", NULL), "code")
})
