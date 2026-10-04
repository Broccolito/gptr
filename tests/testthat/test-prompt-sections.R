# P07 prompt-sections.R: rendering input, helpers, presets, composition, freeze, tool additions
# and gptr_prompt().

p07_session = function(mode = "auto", preset = NULL, .env = parent.frame()) {
  local_fake_provider(list("ok"), .env = .env)
  session_new("fake/fake-1", mode, home = new.env(), preset = preset)
}

pending_of = function(s) get0("prompt_pending", envir = session_live(s)$memo, inherits = FALSE)

# ---- Task 2: rendering input and shared helpers -------------------------------------------------

# The ctx.input service is served (and ctx$input reaches it) only once builtin:prompt is
# declared in Task 3: P01's service_builtin_active() hides a bootstrap service whose built-in
# has no record in a non-empty registry. These tests read the stack directly through
# prompt_input_get(); Task 3 checks ctx$input end to end.
test_that("the rendering input is bound only while rendering, innermost first", {
  s = p07_session()
  ctx = prompt_ctx(s)
  expect_null(prompt_input_get(ctx))
  expect_identical(with_prompt_input(ctx, list(a = 1), function() prompt_input_get(ctx)$a), 1)
  inner = with_prompt_input(ctx, list(a = 1), function() {
    with_prompt_input(ctx, list(a = 2), function() prompt_input_get(ctx)$a)
  })
  expect_identical(inner, 2)
  expect_null(prompt_input_get(ctx))
  expect_length(prompt_frames$stack, 0L)
  # the input is per ctx (04 section 7.0): another session's ctx never sees it
  s2 = p07_session()
  ctx2 = prompt_ctx(s2)
  expect_null(with_prompt_input(ctx, list(a = 1), function() prompt_input_get(ctx2)))
  mixed = with_prompt_input(ctx, list(a = 1), function() {
    with_prompt_input(ctx2, list(a = 2), function() {
      list(prompt_input_get(ctx)$a, prompt_input_get(ctx2)$a)
    })
  })
  expect_identical(mixed, list(1, 2))
  expect_length(prompt_frames$stack, 0L)
})

test_that("an error inside a rendering still pops the input", {
  s = p07_session()
  ctx = prompt_ctx(s)
  expect_error(with_prompt_input(ctx, list(a = 1), function() stop("boom")), "boom")
  expect_length(prompt_frames$stack, 0L)
})

test_that("prompt_truncate cuts at a line boundary and appends the notice", {
  txt = paste(rep("alpha beta gamma delta epsilon zeta eta theta iota kappa", 40),
              collapse = "\n")
  out = prompt_truncate(txt, 60, "[cut]")
  expect_match(out, "\n\\[cut\\]$")
  kept = sub("\n\\[cut\\]$", "", out)
  expect_true(startsWith(txt, kept))
  expect_lte(prompt_est(out), 65)
  expect_identical(prompt_truncate("short", 60, "[cut]"), "short")
})

test_that("prompt_path walks from the root to the leaf", {
  s = p07_session()
  session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(i = 1L)))
  session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(i = 2L)))
  p = Filter(function(e) identical(e$custom_type, "gptr.test"), prompt_path(s))
  expect_identical(vapply(p, function(e) as.integer(e$data$i), 0L), c(1L, 2L))
})

test_that("prompt_path leaves sibling branches out and survives torn lines and cycles", {
  tests_of = function(s) {
    p = Filter(function(e) identical(e$custom_type, "gptr.test"), prompt_path(s))
    vapply(p, function(e) as.character(e$data$x), "")
  }
  add = function(s, x) {
    session_append(s, list(type = "custom", custom_type = "gptr.test", data = list(x = x)))
  }
  # a branch: B is a sibling of C once the leaf moves back to A (file order A, B, C)
  s = p07_session()
  a = add(s, "A")
  add(s, "B")
  d = session_data(s)
  d$leaf = a
  add(s, "C")
  expect_identical(tests_of(s), c("A", "C"))
  # a torn middle line (skipped at resume): the walk continues with the previous entry
  s = p07_session()
  add(s, "X")
  y = add(s, "Y")
  add(s, "Z")
  d = session_data(s)
  ids = vapply(d$entries, function(e) e$id, "")
  d$entries = d$entries[ids != y]
  expect_identical(tests_of(s), c("X", "Z"))
  # a parent cycle stops at the first repeated entry
  s = p07_session()
  p = add(s, "P")
  q = add(s, "Q")
  d = session_data(s)
  ids = vapply(d$entries, function(e) e$id, "")
  d$entries[[match(p, ids)]]$parent_id = q
  expect_identical(vapply(prompt_path(s), function(e) e$id, ""), c(p, q))
  # an unknown leaf has no path
  d$leaf = "no-such-id"
  expect_length(prompt_path(s), 0L)
})

test_that("prompt_read_file normalises line ends, the BOM and trailing newlines", {
  f = withr::local_tempfile(fileext = ".md")
  writeBin(charToRaw("\xef\xbb\xbf# Rules\r\n- one\r\n\r\n"), f)
  expect_identical(prompt_read_file(f), "# Rules\n- one")
})

test_that("prompt_specs keeps the winning record of each name, in order", {
  s = p07_session()
  sid = session_data(s)$id
  off1 = gptr_register(gptr_prompt_section("zz_late", "late", tier = "T1", order = 990L))
  off2 = gptr_register(gptr_prompt_section("aa_early", "early", tier = "T0", order = 50L))
  withr::defer({
    off1()
    off2()
  })
  registry_add(gptr_prompt_section("zz_late", "session override", tier = "T1", order = 990L),
               source = "session", rank = 0L, session = sid)
  specs = prompt_specs("prompt_section", sid)
  nm = vapply(specs, function(x) x$name, "")
  expect_identical(sum(nm == "zz_late"), 1L)
  expect_identical(specs[[which(nm == "zz_late")]]$text, "session override")
  ord = vapply(specs, function(x) as.numeric(x$order), 0)
  expect_false(is.unsorted(ord))
  expect_identical(nm[1], "aa_early")
  other = prompt_specs("prompt_section", NULL)
  hit = Filter(function(x) identical(x$name, "zz_late"), other)
  expect_identical(hit[[1]]$text, "late")
})

test_that("operator messages wait in the session memo until they are flushed", {
  s = p07_session()
  prompt_pending_add(s, msg_operator("reminder", "a note"))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(q[[1]]$kind, "reminder")
  e = prompt_operator_entry(q[[1]])
  expect_identical(e$type, "custom_message")
  expect_identical(e$custom_type, "gptr.operator")
  expect_identical(e$message, q[[1]])
  expect_identical(prompt_pending_flush(s), 1L)
  expect_length(pending_of(s), 0L)
  path = prompt_path(s)
  last = path[[length(path)]]
  expect_identical(last$custom_type, "gptr.operator")
  expect_identical(prompt_entry_operator(last)$kind, "reminder")
  # P06's store writes the kernel shape as the Pi custom_message line (contract section 4.6)
  line = json_decode(json_encode(entry_to_json(last)))
  expect_identical(line$customType, "gptr.operator")
  expect_identical(line$details$kind, "reminder")
  expect_identical(line$content[[1]]$text, "a note")
})

test_that("operator entries are read in the kernel shape and the flat Pi shape", {
  op = msg_operator("steer_relay", "relay text", origin_text = "use TPM")
  kernel = list(type = "custom_message", custom_type = "gptr.operator", message = op)
  expect_identical(prompt_entry_operator(kernel), op)
  flat = list(type = "custom_message", custom_type = "gptr.operator",
              content = list(block_text("a"), block_text("b")),
              details = list(kind = "mode", origin_text = NULL))
  got = prompt_entry_operator(flat)
  expect_identical(got$kind, "mode")
  expect_identical(prompt_operator_text(got), "a\n\nb")
  expect_null(prompt_entry_operator(list(type = "custom", custom_type = "gptr.test")))
  expect_null(prompt_entry_operator(list(type = "message", message = msg_user("x"))))
})

test_that("trust and the bound document fall back before P08 and P15 exist", {
  s = p07_session()
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  expect_false(prompt_trusted(tempdir()))
  expect_null(prompt_doc(s))
})

# ---- Task 3: presets ----------------------------------------------------------------------------

test_that("the four presets are registered records (IC-69)", {
  expect_true(all(c("minimal", "standard", "readonly", "extended") %in% registry_names("preset")))
  expect_identical(registry_get("preset", "minimal")$preamble, "short")
  expect_false(preset_includes(registry_get("preset", "minimal"), "r_session"))
  expect_true(preset_includes(registry_get("preset", "standard"), "r_session"))
  expect_true(preset_includes(registry_get("preset", "minimal"), "context"))
  expect_error(preset_record("nope"), class = "gptr_error_invalid_argument")
})

test_that("preset_tools follows the presets and the ask rule (NS-12, IC-68)", {
  expect_identical(preset_tools("minimal", human = TRUE), c("read", "r", "edit", "write"))
  expect_identical(preset_tools("standard", human = TRUE, mode = "auto"),
                   c("read", "r", "edit", "write", "ask"))
  expect_identical(preset_tools("standard", human = FALSE, mode = "manual"),
                   c("read", "r", "edit", "write", "ask"))
  expect_identical(preset_tools("standard", human = FALSE, mode = "auto"),
                   c("read", "r", "edit", "write"))
  expect_identical(preset_tools("readonly", human = FALSE, mode = "plan"), c("read", "r"))
  expect_identical(preset_tools("readonly", human = TRUE, mode = "plan"), c("read", "r", "ask"))
  expect_identical(preset_tools("extended", human = FALSE, mode = "auto"),
                   c("read", "r", "edit", "write", "grep", "find", "ls"))
})

test_that("modifiers and the tools setting add and remove tools in array order", {
  expect_identical(preset_tools("minimal", FALSE, modifiers = c("+grep", "-edit")),
                   c("read", "r", "write", "grep"))
  local_gptr_options(tools = list(enable = "ls", disable = "write"))
  expect_identical(preset_tools("minimal", FALSE), c("read", "r", "edit", "ls"))
  expect_identical(prompt_tool_order(c("mcp__gh__search", "zeta", "ask", "read", "alpha")),
                   c("read", "ask", "alpha", "zeta", "mcp__gh__search"))
})

test_that("the user's tools.presets maps a model glob to a preset", {
  local_gptr_options(tools = list(presets = list("fake/*" = "minimal")))
  expect_identical(preset_name(NULL, "fake/fake-1"), "minimal")
  expect_identical(preset_name("extended", "fake/fake-1"), "extended")
  expect_identical(preset_tools(NULL, FALSE, model = "fake/fake-1"),
                   c("read", "r", "edit", "write"))
})

test_that("the shipped extended default applies only past break-even (IC-73)", {
  haiku = list(provider = "anthropic", id = "claude-haiku-4-5", cache_min = 4096)
  ref = "anthropic/claude-haiku-4-5"
  expect_true(preset_shipped_applies(ref, haiku, 2000, TRUE, "chat"))
  expect_false(preset_shipped_applies(ref, haiku, 2000, FALSE, "chat"))
  expect_true(preset_shipped_applies(ref, haiku, 2000, FALSE, "child"))
  expect_false(preset_shipped_applies(ref, haiku, 5000, TRUE, "chat"))
  sonnet = list(provider = "anthropic", id = "claude-sonnet-5-5", cache_min = 512)
  expect_false(preset_shipped_applies("anthropic/claude-sonnet-5-5", sonnet, 2000, TRUE, "chat"))
  # the provider prior scales the o200k estimate: Claude 1.35 (3500 -> 4725), Gemini 1.10
  # (3500 -> 3850, 3800 -> 4180); an unknown estimate never applies the default
  expect_false(preset_shipped_applies(ref, haiku, 3500, TRUE, "chat"))
  gem = list(provider = "google", id = "gemini-3-flash", cache_min = 4096)
  expect_true(preset_shipped_applies("google/gemini-3-flash", gem, 3500, TRUE, "chat"))
  expect_false(preset_shipped_applies("google/gemini-3-flash", gem, 3800, TRUE, "chat"))
  expect_false(preset_shipped_applies(ref, haiku, NA_real_, TRUE, "chat"))
})

test_that("preset tools functions are called as P02 validates them (positional human, model)", {
  posn = registry_add(gptr_spec("preset", "p07_posn", tools = function(h, m) {
    c("read", if (isTRUE(h)) "ask", if (identical(m, "x/y")) "edit")
  }), "user", 3L)
  withr::defer(registry_remove(posn))
  # `...` takes `mode` as the third positional argument (a named `mode` would match `model`)
  dots = registry_add(gptr_spec("preset", "p07_dots", tools = function(human, model, ...) {
    c("read", if (identical(list(...)[[1L]], "manual")) "ask")
  }), "user", 3L)
  withr::defer(registry_remove(dots))
  third = registry_add(gptr_spec("preset", "p07_third", tools = function(h, m, md = NULL) {
    c("read", if (identical(md, "manual")) "ask")
  }), "user", 3L)
  withr::defer(registry_remove(third))
  expect_identical(preset_tools("p07_posn", TRUE, model = "x/y"), c("read", "edit", "ask"))
  expect_identical(preset_tools("p07_posn", FALSE), "read")
  expect_identical(preset_tools("p07_dots", FALSE, mode = "manual"), c("read", "ask"))
  expect_identical(preset_tools("p07_third", FALSE, mode = "manual"), c("read", "ask"))
  expect_identical(preset_tools("p07_third", FALSE, mode = "auto"), "read")
})

test_that("a session's rank-0 preset is found through preset_tools(session =) (IC-69)", {
  s = p07_session()
  sid = prompt_sid(s)
  id = registry_add(gptr_spec("preset", "p07_domain", tools = c("read", "r")), "session", 0L,
                    session = sid)
  withr::defer(registry_remove(id))
  expect_identical(preset_tools("p07_domain", FALSE, session = sid), c("read", "r"))
  expect_error(preset_tools("p07_domain", FALSE), class = "gptr_error_invalid_argument")
  cnd = expect_error(preset_record("nope", sid), class = "gptr_error_invalid_argument")
  expect_match(cnd$expected, "p07_domain", fixed = TRUE)
})

test_that("empty and NA modifiers name no tool", {
  base = c("read", "r", "edit", "write")
  expect_identical(preset_tools("minimal", FALSE, modifiers = ""), base)
  expect_identical(preset_tools("minimal", FALSE, modifiers = "+"), base)
  expect_identical(preset_tools("minimal", FALSE, modifiers = c("+", "+grep")), c(base, "grep"))
  expect_identical(preset_tools("minimal", FALSE, modifiers = NA_character_), base)
})

# builtin:prompt (declared below) owns the ctx.input service of Task 2: P01's
# service_builtin_active() serves it only once the registry lists a builtin:prompt record.
test_that("ctx$input reaches the ctx.input service once builtin:prompt is loaded", {
  s = p07_session()
  ctx = prompt_ctx(s)
  expect_identical(ext_service_get("ctx.input"), prompt_input_get)
  expect_identical(with_prompt_input(ctx, list(a = 1), function() ctx$input$a), 1)
  expect_null(ctx$input)
})

# ---- Task 4: the tool array and section composition ---------------------------------------------

# The stand-in helpers (shared with the bench tests and dev/bench/tokens/run.R), bound here by
# name: the lint's object_usage_linter cannot see names that source() defines.
standins_env = local({
  source(test_path("fixtures", "bench", "standins.R"), local = TRUE)
  environment()
})
prefix_fixture = standins_env$prefix_fixture
prompt_standins_register = standins_env$prompt_standins_register

# Compose one case of prefix-baseline.json with the stand-ins for other owners' texts.
compose_case = function(name, .env = parent.frame()) {
  pb = prefix_fixture()
  cs = pb$cases[[name]]
  s = p07_session(cs$mode, cs$preset, .env = .env)
  prompt_standins_register(pb$standins, session_data(s)$id, sections = unlist(cs$sections),
                           exclusive = TRUE)
  doc = if (isTRUE(cs$document)) list(path = file.path(project_root(), "analysis.R"), format = "R")
  prompt_compose(s, list(interactive = cs$human, doc = doc))
}

section_of = function(t0, name) {
  i = regexpr(paste0("<", name, ">\n"), t0, fixed = TRUE)
  j = regexpr(paste0("\n</", name, ">"), t0, fixed = TRUE)
  if (i < 0 || j < 0) return(NA_character_)
  substr(t0, i, j + nchar(name) + 3L)
}

wrap = function(name, x) paste0("<", name, ">\n", x, "\n</", name, ">")

test_that("rendered P07 sections are byte-identical to architecture 7.3 (with stand-ins)", {
  rd = prefix_fixture()$expected$rendered
  inter = compose_case("standard_interactive")
  expect_identical(section_of(inter$t0, "tools"), rd$tools_standard_ask)
  expect_identical(section_of(inter$t0, "rules"), rd$rules_standard)
  expect_identical(section_of(inter$t0, "r_session"), rd$r_session)
  expect_identical(section_of(inter$t0, "r_performance"),
                   wrap("r_performance", prompt_text("r_performance")))
  expect_identical(section_of(inter$t0, "modes"), wrap("modes", prompt_text("modes")))
  expect_identical(section_of(inter$t0, "context"), wrap("context", prompt_text("context")))
  expect_true(startsWith(inter$t0, paste0(prompt_text("preamble"), "\n\n<tools>\n")))
  expect_true(endsWith(inter$t0, "</context>"))
  expect_true(startsWith(inter$t1, "<skills>\n"))
  mini = compose_case("minimal")
  expect_true(startsWith(mini$t0, paste0(prompt_text("preamble_short"), "\n\n<tools>\n")))
  expect_identical(section_of(mini$t0, "tools"), rd$tools_minimal)
  expect_identical(section_of(mini$t0, "rules"), rd$rules_minimal)
  expect_true(is.na(section_of(mini$t0, "r_session")))
  expect_identical(mini$t1, "")
  expect_identical(names(mini$sections), c("name", "tier", "hash", "tokens"))
})

test_that("the readonly preset has no edit or write rules (IC-68)", {
  rd = prefix_fixture()$expected$rendered
  s = p07_session("plan", "readonly")
  prompt_standins_register(prefix_fixture()$standins, session_data(s)$id, exclusive = TRUE)
  fr = prompt_compose(s, list(interactive = TRUE))
  expect_identical(fr$tool_names, c("read", "r", "ask"))
  expect_identical(section_of(fr$t0, "rules"), rd$rules_readonly)
  expect_false(grepl("Use edit for precise changes", fr$t0, fixed = TRUE))
})

test_that("the extended preset uses the full r_performance text and the extra tools", {
  s = p07_session("auto", "extended")
  prompt_standins_register(prefix_fixture()$standins, session_data(s)$id, exclusive = TRUE)
  fr = prompt_compose(s, list(interactive = FALSE))
  expect_identical(fr$tool_names, c("read", "r", "edit", "write", "grep", "find", "ls"))
  expect_match(fr$t0, prompt_text("r_performance_full"), fixed = TRUE)
  expect_match(fr$t0, "- ls: List directory contents\n\nIn addition", fixed = TRUE)
})

test_that("the r schema is frozen in the variant for the document and the human (IC-68)", {
  arr = function(fr) {
    a = json_decode(fr$tools_json)
    names(a[[which(vapply(a, function(x) x$name, "") == "r")]]$input_schema$properties)
  }
  expect_identical(arr(compose_case("standard_interactive")), c("code", "record", "note"))
  expect_identical(arr(compose_case("standard_all")), c("code", "record", "note", "timeout"))
  expect_identical(arr(compose_case("standard_core")), c("code", "timeout"))
})

test_that("{s1} is replaced by the configured System 1 alias", {
  fr = compose_case("standard_all")
  expect_match(fr$t0, "System 1 decisions are gptr(..., model = jev)", fixed = TRUE)
  expect_false(grepl("{s1}", fr$t0, fixed = TRUE))
})

test_that("fragments are inserted at the marker, or the marker line is dropped", {
  core = prompt_text("r_session")
  none = prompt_insert_fragments(core, character())
  expect_false(grepl("{{fragments}}", none, fixed = TRUE))
  expect_false(grepl("\n\n", none, fixed = TRUE))
  two = prompt_insert_fragments(core, c("- one", "- two"))
  expect_match(two, "tool calls.\n- one\n- two\n- To hand a result", fixed = TRUE)
})

test_that("a section over its budget is truncated with a diagnostic", {
  s = p07_session()
  sid = session_data(s)$id
  registry_add(gptr_prompt_section("house", paste(rep("Use SI units in every table.", 40),
                                                  collapse = "\n"),
                                   tier = "T1", order = 780L, budget = 20L),
               source = "session", rank = 0L, session = sid)
  fr = prompt_compose(s, list(interactive = FALSE))
  expect_match(section_of(fr$t1, "house"), "[... section truncated to 20 tokens]", fixed = TRUE)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(grepl("Section 'house' was truncated", d$message, fixed = TRUE)))
})

test_that("SYSTEM text, .opts$system and session_start sections replace or remove sections", {
  s = p07_session()
  fr = prompt_compose(s, list(interactive = FALSE, system = "You are a terse assistant."))
  expect_true(startsWith(fr$t0, "You are a terse assistant.\n\n"))
  expect_false(grepl("<tools>", fr$t0, fixed = TRUE))
  expect_false(grepl("<rules>", fr$t0, fixed = TRUE))
  call = list(args = list(opts = list(system = list(modes = NULL))))
  fr2 = prompt_compose(s, list(interactive = FALSE, call = call))
  expect_false(grepl("<modes>", fr2$t0, fixed = TRUE))
  fr3 = prompt_compose(s, list(interactive = FALSE,
                               start = list(sections = list(context = "Custom context."))))
  expect_match(fr3$t0, "<context>\nCustom context.\n</context>", fixed = TRUE)
})

test_that("the user's SYSTEM.md replaces the core; the project's needs trust", {
  local_project(files = list(".gptr/SYSTEM.md" = "Project system prompt."))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  s = p07_session()
  expect_false(grepl("Project system prompt.", prompt_compose(s)$t0, fixed = TRUE))
  local_mocked_bindings(prompt_trusted = function(root) TRUE)
  expect_true(startsWith(prompt_compose(s)$t0, "Project system prompt.\n\n"))
})

test_that("the tool array skips unavailable and missing tools and adds plugin direct tools", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_standins_register(prefix_fixture()$standins, sid, exclusive = TRUE)
  registry_add(gptr_tool("needs_ui", "Needs a UI.", parameters = list(type = "object"),
                         execute = function(input, ctx) "ok",
                         available = function(ctx) FALSE),
               source = "session", rank = 0L, session = sid)
  registry_add(gptr_tool("zz_lookup", "Look up a term.",
                         parameters = list(type = "object", properties = json_obj()),
                         execute = function(input, ctx) "ok", exposure = "direct"),
               source = "session", rank = 0L, session = sid)
  fr = prompt_compose(s, list(interactive = FALSE, tools = c("+needs_ui", "+nope")))
  expect_identical(fr$tool_names, c("read", "r", "edit", "write", "zz_lookup"))
  arr = json_decode(fr$tools_json)
  expect_identical(vapply(arr, function(x) x$name, ""),
                   c("read", "r", "edit", "write", "zz_lookup"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(grepl("Tool 'nope' is not registered", d$message, fixed = TRUE)))
  fr2 = prompt_compose(s, list(interactive = FALSE, tools = "-zz_lookup"))
  expect_false("zz_lookup" %in% fr2$tool_names)
})

test_that("prompt_schema_formals marks arguments without defaults as required", {
  sch = prompt_schema_formals(function(name, n = 5L) NULL)
  expect_identical(unclass(sch$required), "name")
  expect_setequal(names(sch$properties), c("name", "n"))
  expect_identical(json_encode(prompt_schema_formals(NULL)),
                   "{\"type\":\"object\",\"properties\":{}}")
})

test_that("the default estimator is registered and keeps its prior when calibrating", {
  sp = registry_get("estimator", "default")
  expect_equal(sp$estimate("hello world", "prose"), est_tokens("hello world", "prose"))
  st = sp$calibrate(list(m = 1, n = 0L, prior = 1.35), 1000, 1300)
  expect_identical(st$prior, 1.35)
  expect_true(is.numeric(st$m))
})

# P06's session_new() stores the `preset` setting when the caller names no preset, so a session
# preset equal to the configured one is not an explicit choice: the user's tools.presets mapping
# and the shipped defaults (IC-73) apply to it; `opts$preset` and any other session preset win.
test_that("a session created without a preset gets tools.presets and the shipped default (IC-73)", {
  local_gptr_options(tools = list(presets = list("fake/*" = "minimal")))
  s = p07_session()
  expect_identical(session_data(s)$preset, "standard")
  expect_identical(prompt_compose(s, list(interactive = FALSE))$preset, "minimal")
  expect_identical(prompt_compose(s, list(interactive = FALSE, preset = "readonly"))$preset,
                   "readonly")
  r = p07_session(preset = "readonly")
  expect_identical(prompt_compose(r, list(interactive = FALSE))$preset, "readonly")
  # Haiku 4.5 (catalog cache_min 4096): extended past break-even only (a human can answer)
  h = session_new("anthropic/claude-haiku-4-5", "manual", home = new.env())
  prompt_standins_register(prefix_fixture()$standins, session_data(h)$id, exclusive = TRUE)
  fr = prompt_compose(h, list(interactive = TRUE))
  expect_identical(fr$preset, "extended")
  expect_identical(fr$tool_names, c("read", "r", "edit", "write", "ask", "grep", "find", "ls"))
  expect_identical(prompt_compose(h, list(interactive = FALSE))$preset, "standard")
  h2 = session_new("anthropic/claude-haiku-4-5", "manual", home = new.env(), preset = "minimal")
  expect_identical(prompt_compose(h2, list(interactive = TRUE))$preset, "minimal")
  # a configured preset other than standard is never replaced by the shipped default
  local_gptr_options(preset = "readonly")
  h3 = session_new("anthropic/claude-haiku-4-5", "manual", home = new.env())
  expect_identical(prompt_compose(h3, list(interactive = TRUE))$preset, "readonly")
})

test_that("the tools.disable setting also leaves out plugin direct tools", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_standins_register(prefix_fixture()$standins, sid, exclusive = TRUE)
  registry_add(gptr_tool("zz_lookup", "Look up a term.",
                         parameters = list(type = "object", properties = json_obj()),
                         execute = function(input, ctx) "ok", exposure = "direct"),
               source = "session", rank = 0L, session = sid)
  expect_true("zz_lookup" %in% prompt_compose(s, list(interactive = FALSE))$tool_names)
  local_gptr_options(tools = list(disable = "zz_lookup"))
  expect_identical(prompt_compose(s, list(interactive = FALSE))$tool_names,
                   c("read", "r", "edit", "write"))
})

test_that("a tool whose available() or parameters() fails is left out with a diagnostic", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_standins_register(prefix_fixture()$standins, sid, exclusive = TRUE)
  ok = function(input, ctx) "ok"
  add = function(spec) registry_add(spec, source = "session", rank = 0L, session = sid)
  add(gptr_tool("zz_params", "Broken schema.", parameters = function(ctx) stop("no schema"),
                execute = ok))
  add(gptr_tool("zz_avail", "Broken check.", parameters = list(type = "object"), execute = ok,
                available = function(ctx) stop("no ui")))
  add(gptr_tool("zz_array", "Not an object.", parameters = function(ctx) list(type = "array"),
                execute = ok))
  fr = prompt_compose(s, list(interactive = FALSE))
  expect_identical(fr$tool_names, c("read", "r", "edit", "write"))
  expect_identical(vapply(json_decode(fr$tools_json), function(x) x$name, ""),
                   c("read", "r", "edit", "write"))
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("Tool 'zz_params' is not declared: parameters() failed: no schema",
                        msg, fixed = TRUE)))
  expect_true(any(grepl("Tool 'zz_avail' is not declared: available() failed: no ui", msg,
                        fixed = TRUE)))
  expect_true(any(grepl("Tool 'zz_array' is not declared: its parameters are not a JSON Schema",
                        msg, fixed = TRUE)))
})

test_that("a session's own rank-0 preset composes with its tools (IC-69)", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_standins_register(prefix_fixture()$standins, sid, exclusive = TRUE)
  id = registry_add(gptr_spec("preset", "p07_domain", tools = c("read", "r")), "session", 0L,
                    session = sid)
  withr::defer(registry_remove(id))
  fr = prompt_compose(s, list(interactive = FALSE, preset = "p07_domain"))
  expect_identical(fr$preset, "p07_domain")
  expect_identical(fr$tool_names, c("read", "r"))
  expect_match(fr$t0, "<tools>\n- read: Read file contents\n- r: Run R code", fixed = TRUE)
})

# Pi's rule: a custom system prompt (SYSTEM.md or a string .opts$system) replaces the whole core
# (preamble, tools and rules) and is the user's text, so the preamble's 120-token budget does not
# cut it; a named `preamble` override is a section override and keeps the section's budget.
test_that("a custom system prompt replaces the core without the preamble's budget (Pi's rule)", {
  fx = prefix_fixture()$standins
  local_project()
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  s = p07_session()
  prompt_standins_register(fx, session_data(s)$id, exclusive = TRUE)
  lines = paste0("Rule ", 1:30, ": answer in short sentences and name every object, file and ",
                 "package you used.")
  txt = paste(lines, collapse = "\n")
  expect_gt(est_tokens(txt, "prose"), 500)
  whole = function(fr) {
    expect_true(startsWith(fr$t0, paste0(txt, "\n\n<r_session>\n")))
    expect_false(grepl("section truncated", fr$t0, fixed = TRUE))
    expect_identical(fr$sections$name[1], "preamble")
  }
  whole(prompt_compose(s, list(interactive = FALSE, system = txt)))
  user = file.path(gptr_user_dir("config", create = TRUE), "SYSTEM.md")
  writeLines(lines, user)
  whole(prompt_compose(s, list(interactive = FALSE)))
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_false(any(grepl("Section 'preamble' was truncated", msg, fixed = TRUE)))
  unlink(user)
  named = prompt_compose(s, list(interactive = FALSE, system = list(preamble = txt)))
  expect_match(named$t0, "[... section truncated to 120 tokens]", fixed = TRUE)
  expect_match(named$t0, "<tools>", fixed = TRUE)
})

test_that("an empty SYSTEM.md or .opts$system replaces nothing; an empty override omits", {
  fx = prefix_fixture()$standins
  local_project()
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  s = p07_session()
  prompt_standins_register(fx, session_data(s)$id, exclusive = TRUE)
  base = prompt_compose(s, list(interactive = FALSE))
  expect_true(startsWith(base$t0, paste0(prompt_text("preamble"), "\n\n<tools>\n")))
  expect_identical(prompt_compose(s, list(interactive = FALSE, system = ""))$t0, base$t0)
  expect_identical(prompt_compose(s, list(interactive = FALSE, system = " \n "))$t0, base$t0)
  writeLines(character(), file.path(gptr_user_dir("config", create = TRUE), "SYSTEM.md"))
  fr = prompt_compose(s, list(interactive = FALSE))
  expect_identical(fr$t0, base$t0)
  expect_identical(fr$sections$name, base$sections$name)
  fr2 = prompt_compose(s, list(interactive = FALSE, system = list(modes = " ")))
  expect_false(grepl("<modes>", fr2$t0, fixed = TRUE))
  expect_false("modes" %in% fr2$sections$name)
})

# An override changes a registered section's text; whether the section is included stays the
# preset record's decision, so an excluded section keeps out of the prompt (never a stray T0
# section that breaks the tiers).
test_that("an override of a section the preset excludes keeps it out of the prompt", {
  s = p07_session(preset = "minimal")
  prompt_standins_register(prefix_fixture()$standins, session_data(s)$id, sections = "r_env",
                           exclusive = TRUE)
  fr = prompt_compose(s, list(interactive = FALSE, system = list(r_env = "R 4.4 custom")))
  expect_false(grepl("<r_env>", fr$t0, fixed = TRUE))
  expect_identical(fr$t1, "")
  expect_false("r_env" %in% fr$sections$name)
  expect_true(endsWith(fr$t0, "</context>"))
  st = p07_session(preset = "standard")
  prompt_standins_register(prefix_fixture()$standins, session_data(st)$id, sections = "r_env",
                           exclusive = TRUE)
  fr2 = prompt_compose(st, list(interactive = FALSE, system = list(r_env = "R 4.4 custom")))
  expect_identical(fr2$t1, "<r_env>\nR 4.4 custom\n</r_env>")
  expect_identical(fr2$sections$tier[fr2$sections$name == "r_env"], "T1")
})

test_that("a named override replaces or removes an r_session fragment", {
  frags = prefix_fixture()$standins$fragments
  shell = frags[[which(vapply(frags, function(f) f$name, "") == "shell")]]$text
  s = p07_session()
  prompt_standins_register(prefix_fixture()$standins, session_data(s)$id, exclusive = TRUE)
  base = section_of(prompt_compose(s, list(interactive = FALSE))$t0, "r_session")
  expect_match(base, shell, fixed = TRUE)
  gone = prompt_compose(s, list(interactive = FALSE, system = list(shell = NULL)))
  expect_identical(section_of(gone$t0, "r_session"),
                   sub(paste0(shell, "\n"), "", base, fixed = TRUE))
  mine = "- Use the shell carefully."
  swap = prompt_compose(s, list(interactive = FALSE, system = list(shell = mine)))
  expect_identical(section_of(swap$t0, "r_session"), sub(shell, mine, base, fixed = TRUE))
  expect_false("shell" %in% swap$sections$name)
  expect_false(grepl("<shell>", swap$t0, fixed = TRUE))
  m = p07_session(preset = "minimal")
  prompt_standins_register(prefix_fixture()$standins, session_data(m)$id, exclusive = TRUE)
  fm = prompt_compose(m, list(interactive = FALSE, system = list(shell = mine)))
  expect_false(grepl(mine, fm$t0, fixed = TRUE))
  expect_false("shell" %in% fm$sections$name)
})

# ---- Task 7: freeze, the gptr.frozen entry and the compaction floor check -----------------------

test_that("prompt_freeze stores the frozen prompt once and appends gptr.frozen first", {
  s = p07_session()
  d = session_data(s)
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_identical(d$frozen, fr)
  expect_identical(fr$preset, "standard")
  expect_true(all(c("t0", "t1", "tools_json", "tool_names", "sections") %in% names(fr)))
  expect_identical(names(fr$sections), c("name", "tier", "hash", "tokens"))
  path = prompt_path(s)
  types = vapply(path, function(e) e$custom_type %||% e$type, "")
  expect_identical(sum(types == "gptr.frozen"), 1L)
  expect_false(any(types[seq_len(which(types == "gptr.frozen"))] == "message"))
  frozen = path[[which(types == "gptr.frozen")]]
  expect_identical(frozen$data$t0, fr$t0)
  expect_identical(frozen$data$toolsJson, fr$tools_json)
  expect_identical(frozen$data$preset, "standard")
  n = length(d$entries)
  expect_identical(prompt_freeze(s), fr)
  expect_length(d$entries, n)
  expect_identical(ext_service_get("prompt.freeze"), prompt_freeze)
})

test_that("a resumed session restores the frozen prompt from its gptr.frozen entry", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE))
  d = session_data(s)
  d$frozen = NULL
  back = prompt_freeze(s)
  expect_identical(back$t0, fr$t0)
  expect_identical(back$t1, fr$t1)
  expect_identical(back$tools_json, fr$tools_json)
  expect_identical(back$sections$hash, fr$sections$hash)
  expect_identical(back$human, FALSE)
  n = length(d$entries)
  again = prompt_freeze(s, list(refreeze = TRUE, interactive = FALSE))
  expect_length(d$entries, n + 1L)
  expect_identical(again$t0, fr$t0)
})

test_that("a model with an 8K window is refused for the standard preset (IC-71)", {
  local_project(files = list("AGENTS.md" = paste(rep("- Always check the data dictionary.", 400),
                                                 collapse = "\n")))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  # manual mode: the untrusted project's instructions are sent (not withheld), so they count
  s = p07_session("manual")
  local_mocked_bindings(prompt_model = function(ref) {
    list(ref = "tiny/tiny-8k", provider = "tiny", id = "tiny-8k", api = "fake", context = 8192,
         max_output = 1024)
  })
  expect_error(prompt_freeze(s, list(interactive = FALSE)), "preset = \"minimal\"",
               class = "gptr_error_invalid_argument")
  expect_null(session_data(s)$frozen)
  # refused before anything is stored: no gptr.frozen entry either
  expect_length(session_data(s)$entries, 0L)
})

test_that("the floor check cuts re-injection budgets before it refuses (IC-71)", {
  fr = list(model = "m", preset = "standard", tools_json = "",
            sections = data.frame(tokens = 3000))
  local_mocked_bindings(prompt_model = function(ref) list(context = 32768, max_output = 4096))
  ok = prompt_floor_check(fr, project_tokens = 500, skills_budget = 10000)
  expect_null(ok$reinject)
  cut = prompt_floor_check(fr, project_tokens = 9000, skills_budget = 10000)
  expect_equal(cut$reinject, list(project = 4096, skills = 4096))
  big = fr
  big$sections = data.frame(tokens = 16000)
  expect_error(prompt_floor_check(big, 500, 0), class = "gptr_error_invalid_argument")
})

test_that("a 200K window passes the floor check with the full re-injection budgets", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_identical(fr$reinject, list(project = Inf, skills = 10000))
})

# A 24,000-token window with 1,024 output tokens: threshold 24000 - max(16384, 1024 + 2 * 4000)
# = 7,616, so the re-injection budgets are cut to 1,904 when the floor reaches it. 900 lines of
# AGENTS.md (about 7,400 estimated tokens) put the floor over the threshold; 25% fits.
local_tiny_model = function(.env = parent.frame()) {
  local_mocked_bindings(prompt_model = function(ref) {
    list(ref = "tiny/tiny-24k", provider = "tiny", id = "tiny-24k", api = "fake", context = 24000,
         max_output = 1024)
  }, .env = .env)
}

block_kinds = function(blocks) vapply(blocks, function(b) b$kind %||% b$type, "")

test_that("the floor counts the project instructions the frozen audience will be sent (IC-52)", {
  local_project(files = list("AGENTS.md" = rep("- Always check the data dictionary.", 900)))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  local_tiny_model()
  # untrusted project, auto mode: a session frozen for a human (`interactive = TRUE`, as P06's
  # run_freeze() passes the run's audience) is sent the instructions, so the floor counts them,
  # whatever gptr_can_prompt() says (FALSE in the tests)
  s = p07_session("auto")
  fr = prompt_freeze(s, list(interactive = TRUE))
  expect_equal(fr$reinject, list(project = 1904, skills = 0))
  expect_true("project_instructions" %in% block_kinds(context_first_message(s, list())))
  # a non-interactive run withholds them (notice), so they are not part of the floor, whatever
  # gptr_can_prompt() says (TRUE here: the frozen audience, not the console, decides)
  local_gptr_options(quiet = FALSE)
  s2 = p07_session("auto")
  local_mocked_bindings(gptr_can_prompt = function() TRUE)
  expect_message(prompt_freeze(s2, list(interactive = FALSE)), "not trusted",
                 class = "gptr_message_notice")
  expect_identical(session_data(s2)$frozen$reinject, list(project = Inf, skills = 10000))
  expect_false("reinject" %in% names(prompt_path(s2)[[1]]$data))
  expect_false("project_instructions" %in% block_kinds(context_first_message(s2, list())))
})

test_that("cut re-injection budgets are recorded in gptr.frozen and survive a restore (IC-71)", {
  local_project(files = list("AGENTS.md" = rep("- Always check the data dictionary.", 900)))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  local_tiny_model()
  s = p07_session("manual")
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_equal(fr$reinject, list(project = 1904, skills = 0))
  expect_equal(prompt_path(s)[[1]]$data$reinject, list(project = 1904, skills = 0))
  # the store's JSON line (P06) keeps them; JSON reads the whole numbers back as integers
  line = json_encode(entry_to_json(prompt_path(s)[[1]]))
  stored = entry_from_json(json_decode(line))
  expect_identical(prompt_reinject_read(stored$data$reinject), list(project = 1904, skills = 0))
  d = session_data(s)
  d$frozen = NULL
  expect_equal(prompt_freeze(s)$reinject, fr$reinject)
  # full budgets (here: the instructions are withheld) are not recorded (Inf has no JSON
  # number) and restore as the defaults
  local_gptr_options(quiet = FALSE)
  s2 = p07_session("auto")
  expect_message(prompt_freeze(s2, list(interactive = FALSE)), class = "gptr_message_notice")
  d2 = session_data(s2)
  expect_false("reinject" %in% names(prompt_path(s2)[[1]]$data))
  d2$frozen = NULL
  expect_identical(prompt_freeze(s2)$reinject, list(project = Inf, skills = 10000))
})
