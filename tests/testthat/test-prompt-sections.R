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

# P09 registers the skill_content block, whose 10,000-token re-injection budget alone overruns
# the tiny window's threshold: the floor tests below hide that block, so the skills budget is 0
# and the floor varies with the project instructions only
local_no_skill_block = function(.env = parent.frame()) {
  real = registry_get
  local_mocked_bindings(registry_get = function(kind, name, session = NULL) {
    if (identical(kind, "context_block") && identical(name, "skill_content")) return(NULL)
    real(kind, name, session)
  }, .env = .env)
}

test_that("the floor counts the project instructions the frozen audience will be sent (IC-52)", {
  local_project(files = list("AGENTS.md" = rep("- Always check the data dictionary.", 900)))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  local_tiny_model()
  local_no_skill_block()
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
  local_no_skill_block()
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

# ---- Task 8: tool additions and section patches -------------------------------------------------

trials_tool = function() {
  gptr_tool("trials", "Search ClinicalTrials.gov by condition.",
            parameters = list(type = "object", required = I("condition"),
                              properties = list(condition = list(type = "string"))),
            execute = function(input, ctx) "12 trials")
}

test_that("session_add_tools declares tools by value when the adapter supports it (IC-69)", {
  s = p07_session()
  before = prompt_freeze(s, list(interactive = FALSE))$tools_json
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  expect_identical(session_add_tools(s, trials_tool()), s)
  expect_false(is.null(registry_get("tool", "trials", session = session_data(s)$id)))
  q = pending_of(s)
  expect_identical(q[[1]]$kind, "tool_change")
  expect_identical(q[[1]]$tool_add[[1]]$name, "trials")
  expect_identical(q[[1]]$tool_add[[1]]$input_schema$required, I("condition"))
  expect_identical(msg_text(q[[1]]), "New tools are available from now on: trials.")
  expect_identical(session_data(s)$frozen$tools_json, before)
})

test_that("without tool_addition the tools become namespaced r members with a note", {
  s = p07_session()
  prompt_freeze(s, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s, list(trials_tool()))
  sid = session_data(s)$id
  # namespaced tools are registry records keyed "<namespace>/<name>" (P02 spec_key())
  reg = registry_get("tool", "tools/trials", session = sid)
  expect_identical(reg$exposure, "r")
  expect_identical(reg$namespace, "tools")
  expect_true(is.function(reg$fun))
  q = pending_of(s)
  expect_null(q[[1]]$tool_add)
  expect_match(msg_text(q[[1]]), "gptr$tools$trials(condition: string)", fixed = TRUE)
})

test_that("a spec that already is a gptr$ member keeps its name when added", {
  s = p07_session()
  prompt_freeze(s, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s, gptr_tool("rows_of", "Rows of a data frame.", fun = function(name) 1L))
  q = pending_of(s)
  expect_match(msg_text(q[[1]]), "gptr$rows_of(name: string)", fixed = TRUE)
  expect_null(registry_get("tool", "tools/rows_of", session = session_data(s)$id))
})

test_that("session.add_tools is P07's service", {
  expect_identical(ext_service_get("session.add_tools"), session_add_tools)
})

test_that("section patches are queued as operator messages (Pi's wording)", {
  s = p07_session()
  prompt_section_patch(s, "r_env", "R 4.5.0")
  prompt_section_patch(s, "mcp")
  q = pending_of(s)
  expect_identical(q[[1]]$kind, "section_patch")
  expect_identical(msg_text(q[[1]]),
                   "Updated system prompt section \"r_env\":\n\n<r_env>\nR 4.5.0\n</r_env>")
  expect_identical(msg_text(q[[2]]), "Removed system prompt section \"mcp\".")
})

# The adapters send an operator message's declarations only when the adapter declares
# tool_addition and the model's own capability does not refuse it (P12 adp_model_cap(model,
# "tool_addition", TRUE); the Responses adapter also needs tool_call), so P07 announces tools by
# value under the same rule; otherwise the declarations would be dropped and the tool lost.
test_that("tools are declared by value only when the adapter and the model take them (IC-74)", {
  s = p07_session()
  expect_true(prompt_tool_addition(s))
  rec = model_resolve("fake/fake-1", strict = FALSE)
  with_model = function(m) {
    local_mocked_bindings(prompt_model = function(ref) m)
    prompt_tool_addition(s)
  }
  no_cap = rec
  no_cap$capabilities$tool_addition = FALSE
  expect_false(with_model(no_cap))
  unset = rec
  unset$capabilities$tool_addition = NULL
  expect_true(with_model(unset))
  no_tools = rec
  no_tools$tool_call = FALSE
  expect_false(with_model(no_tools))
  # a model that claims tool_addition behind an adapter that does not declare it
  completions = rec
  completions$api = "openai-completions"
  expect_false(isTRUE(adapter_get("openai-completions")$capabilities$tool_addition))
  expect_false(with_model(completions))
  unknown_api = rec
  unknown_api$api = "p07-no-such-api"
  expect_false(with_model(unknown_api))
  expect_false(with_model(NULL))
})

test_that("hidden specs are never announced; namespaced and fun-only members stay members", {
  s = p07_session()
  prompt_freeze(s, list(interactive = FALSE))
  sid = session_data(s)$id
  ok = function(input, ctx) "ok"
  hidden = gptr_tool("p07_hidden", "Internal.", execute = ok, exposure = "hidden")
  cohort = gptr_tool("p07_cohort", "Cohort size.", fun = function(id) 1L, exposure = "r",
                     namespace = "p07lab")
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, list(hidden, cohort, trials_tool()))
  expect_identical(registry_get("tool", "p07_hidden", session = sid)$exposure, "hidden")
  expect_false(is.null(registry_get("tool", "p07lab/p07_cohort", session = sid)))
  q = pending_of(s)
  expect_length(q, 2L)
  expect_identical(vapply(q[[1]]$tool_add, function(x) x$name, ""), "trials")
  expect_identical(msg_text(q[[1]]), "New tools are available from now on: trials.")
  expect_null(q[[2]]$tool_add)
  expect_match(msg_text(q[[2]]), "gptr$p07lab$p07_cohort(id: string)", fixed = TRUE)
  s2 = p07_session()
  prompt_freeze(s2, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s2, list(hidden))
  expect_null(registry_get("tool", "tools/p07_hidden", session = session_data(s2)$id))
  expect_length(pending_of(s2) %||% list(), 0L)
})

test_that("a spec that cannot be added is skipped with a diagnostic; the others are announced", {
  s = p07_session()
  prompt_freeze(s, list(interactive = FALSE))
  sid = session_data(s)$id
  bad = gptr_tool("p07_bad", "Broken schema.", parameters = function(ctx) stop("no schema"),
                  execute = function(input, ctx) "x")
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, list(bad, trials_tool()))
  expect_null(registry_get("tool", "p07_bad", session = sid))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(msg_text(q[[1]]), "New tools are available from now on: trials.")
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("Tool 'p07_bad' was not added: no schema", msg, fixed = TRUE)))
  expect_error(session_add_tools(s, list("trials")), class = "gptr_error_invalid_argument")
})

test_that("a tool made a member keeps the spec's other fields", {
  rend = function(call, result, width) "rendered"
  sp = gptr_spec("tool", "p07_rend", description = "Rendered.", render = rend,
                 execute = function(input, ctx) "ok", snippet = "Render it")
  m = prompt_member_spec(sp)
  expect_identical(m$render, rend)
  expect_identical(m$snippet, "Render it")
  expect_identical(c(m$exposure, m$namespace), c("r", "tools"))
  expect_true(is.function(m$fun))
})

# P06's run_freeze() runs the session_start hooks (which may call ctx$add_tools()) before the
# freeze, and the freeze declares a session's direct tools, so a message would declare them twice.
test_that("tools added before the first freeze join the frozen prompt, not a message", {
  s = p07_session()
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, trials_tool())
  expect_length(pending_of(s) %||% list(), 0L)
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_true("trials" %in% fr$tool_names)
  expect_true("trials" %in% vapply(json_decode(fr$tools_json), function(x) x$name, ""))
  session_add_tools(s, gptr_tool("p07_later", "Later.", execute = function(input, ctx) "x"))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(msg_text(q[[1]]), "New tools are available from now on: p07_later.")
  # a session that will be frozen anew (an IC-52 refreeze) does not announce either
  d = session_data(s)
  d$frozen = NULL
  d$refreeze = TRUE
  session_add_tools(s, gptr_tool("p07_again", "Again.", execute = function(input, ctx) "x"))
  expect_length(pending_of(s), 1L)
})

# Review round 1 (finding 1): before the freeze, only the tools the frozen array declares itself
# (prompt_tools_always()) stay unannounced; any other tool becomes a member as after the freeze, so
# the model learns of every added tool whenever it was added. Review round 2 (finding 2): that
# includes namespaced r members, since whether the frozen prompt lists them (P10's plugins
# section) depends on the preset, the run options and the session_start overrides of the freeze.
test_that("tools added before the freeze that it does not declare are announced", {
  s = p07_session()
  sid = session_data(s)$id
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  f = function(input, ctx) "x"
  session_add_tools(s, list(
    gptr_tool("p07_nsd", "Namespaced direct.", execute = f, namespace = "p07lab"),
    gptr_tool("p07_mem", "Plain member.", fun = function(a) 1L, exposure = "r"),
    gptr_tool("p07_cat", "Catalogued.", fun = function(id) 1L, exposure = "r",
              namespace = "p07lab")
  ))
  nsd = registry_get("tool", "p07lab/p07_nsd", session = sid)
  expect_identical(c(nsd$exposure, nsd$namespace), c("r", "p07lab"))
  expect_true(is.function(nsd$fun))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_null(q[[1]]$tool_add)
  lines = c("gptr$p07lab$p07_nsd()  # Namespaced direct.",
            "gptr$p07_mem(a: string)  # Plain member.",
            "gptr$p07lab$p07_cat(id: string)  # Catalogued.")
  expect_identical(msg_text(q[[1]]),
                   sprintf(prompt_text("members_added"), paste(lines, collapse = "\n")))
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_false(any(c("p07_nsd", "p07_mem", "p07_cat") %in% fr$tool_names))
})

# Review round 1 (finding 2): the model already has the declarations of the frozen array and of
# earlier additions, so the same tool is not declared again (P08 passes the registry's own spec
# on a continuation), and a changed declaration under a declared name is refused: the frozen
# array never changes, and a rank-0 tie would keep running the first spec (P02).
test_that("a tool the model already has is not declared again; a changed one is refused", {
  s = p07_session()
  sid = session_data(s)$id
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, gptr_tool("p07_arr", "In array.", execute = function(input, ctx) "x"))
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_true("p07_arr" %in% fr$tool_names)
  session_add_tools(s, registry_get("tool", "p07_arr", session = sid))
  session_add_tools(s, gptr_tool("p07_arr", "In array.", execute = function(input, ctx) "y"))
  expect_length(pending_of(s) %||% list(), 0L)
  # the declaration is unchanged, so the latest implementation runs
  expect_identical(tool_lookup("p07_arr", sid)$execute(list(), NULL), "y")
  changed = gptr_tool("p07_arr", "Changed schema.",
                      parameters = list(type = "object",
                                        properties = list(q = list(type = "string"))),
                      execute = function(input, ctx) "z")
  session_add_tools(s, changed)
  session_add_tools(s, gptr_tool("p07_arr", "In array.", execute = function(input, ctx) "h",
                                 exposure = "hidden"))
  expect_length(pending_of(s) %||% list(), 0L)
  expect_identical(tool_lookup("p07_arr", sid)$description, "In array.")
  expect_identical(tool_lookup("p07_arr", sid)$execute(list(), NULL), "y")
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_identical(sum(grepl("Tool 'p07_arr' was not added: ", msg, fixed = TRUE)), 2L)
  session_add_tools(s, trials_tool())
  session_add_tools(s, list(trials_tool(), trials_tool()))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(msg_text(q[[1]]), "New tools are available from now on: trials.")
  # members: the same signature is not announced again; a changed one is re-registered and
  # announced with its new signature
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  m1 = gptr_tool("p07_m", "Member one.", fun = function(a) 1L, exposure = "r")
  session_add_tools(s, m1)
  session_add_tools(s, m1)
  session_add_tools(s, gptr_tool("p07_tr", "Trials again.", execute = function(input, ctx) "t"))
  session_add_tools(s, gptr_tool("p07_tr", "Trials again.", execute = function(input, ctx) "t"))
  expect_length(pending_of(s), 3L)
  session_add_tools(s, gptr_tool("p07_m", "Member two.", fun = function(a, b) 2L,
                                 exposure = "r"))
  q = pending_of(s)
  expect_length(q, 4L)
  expect_match(msg_text(q[[4]]), "gptr$p07_m(a: string, b: string)  # Member two.", fixed = TRUE)
  expect_identical(registry_get("tool", "p07_m", session = sid)$description, "Member two.")
  # after the queue is flushed into the transcript, what it announced still counts: trials is not
  # declared again (while the model takes tool additions, review round 2 finding 3), and the
  # member one signature is announced again only because the newest line of p07_m is the member
  # two signature
  prompt_pending_flush(s)
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, trials_tool())
  expect_length(pending_of(s) %||% list(), 0L)
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s, gptr_tool("p07_tr", "Trials again.", execute = function(input, ctx) "t"))
  expect_length(pending_of(s) %||% list(), 0L)
  session_add_tools(s, m1)
  q = pending_of(s)
  expect_length(q, 1L)
  expect_match(msg_text(q[[1]]), "gptr$p07_m(a: string)  # Member one.", fixed = TRUE)
  expect_identical(registry_get("tool", "p07_m", session = sid)$description, "Member one.")
})

test_that("a tool another rank-0 record of the session wins over is refused, not announced", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_freeze(s, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  registry_add(gptr_tool("p07_px", "From an extension.", execute = function(input, ctx) "ext"),
               source = "plugin:p07ext", rank = 0L, session = sid)
  session_add_tools(s, gptr_tool("p07_px", "Mine.", execute = function(input, ctx) "mine"))
  expect_length(pending_of(s) %||% list(), 0L)
  expect_identical(tool_lookup("p07_px", sid)$execute(list(), NULL), "ext")
  expect_length(registry_candidates("tool", "p07_px", sid), 1L)
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("Tool 'p07_px' was not added: Another record of the session provides",
                        msg, fixed = TRUE)))
})

# Review round 2 (finding 1): P08's continuation enables `plugins =` at rank 0 for the session
# (P17's plugin.enable, source "plugin:<name>") and then passes registry_get() of each new tool to
# session.add_tools. The tool that runs is the one passed, so it is announced, not refused, and it
# is not registered a second time.
test_that("a tool another rank-0 record of the session already provides is announced", {
  f = function(input, ctx) "plug"
  plug = function(s, suffix) {
    sid = session_data(s)$id
    registry_add(gptr_tool(paste0("p07_plug", suffix), "From a plugin.", execute = f),
                 source = "plugin:p07x", rank = 0L, session = sid)
    registry_add(gptr_tool(paste0("p07_plugm", suffix), "Plugin member.", fun = function(id) 1L,
                           exposure = "r", namespace = "p07x"),
                 source = "plugin:p07x", rank = 0L, session = sid)
    list(registry_get("tool", paste0("p07_plug", suffix), session = sid),
         registry_get("tool", paste0("p07x/p07_plugm", suffix), session = sid))
  }
  s = p07_session()
  sid = session_data(s)$id
  prompt_freeze(s, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, plug(s, "1"))
  q = pending_of(s)
  expect_length(q, 2L)
  expect_identical(vapply(q[[1]]$tool_add, function(x) x$name, ""), "p07_plug1")
  expect_identical(msg_text(q[[2]]),
                   sprintf(prompt_text("members_added"),
                           "gptr$p07x$p07_plugm1(id: string)  # Plugin member."))
  expect_length(registry_candidates("tool", "p07_plug1", sid), 1L)
  expect_length(registry_candidates("tool", "p07x/p07_plugm1", sid), 1L)
  expect_identical(tool_lookup("p07_plug1", sid)$execute(list(), NULL), "plug")
  # without tool additions the plugin's direct tool becomes the member gptr$tools$<name>()
  s2 = p07_session()
  prompt_freeze(s2, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s2, plug(s2, "2"))
  q2 = pending_of(s2)
  expect_length(q2, 1L)
  lines = c("gptr$tools$p07_plug2()  # From a plugin.",
            "gptr$p07x$p07_plugm2(id: string)  # Plugin member.")
  expect_identical(msg_text(q2[[1]]),
                   sprintf(prompt_text("members_added"), paste(lines, collapse = "\n")))
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_false(any(grepl("'p07_plugm?[12]'", msg)))
})

# Review round 2 (finding 2): the minimal preset has no plugins section, so a namespaced member
# added before the freeze is announced by the member note.
test_that("namespaced members added before the freeze are announced under any preset", {
  s = p07_session(preset = "minimal")
  sid = session_data(s)$id
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, gptr_tool("p07_min", "Catalogued.", fun = function(id) 1L, exposure = "r",
                                 namespace = "p07min"))
  expect_false(is.null(registry_get("tool", "p07min/p07_min", session = sid)))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_identical(msg_text(q[[1]]),
                   sprintf(prompt_text("members_added"),
                           "gptr$p07min$p07_min(id: string)  # Catalogued."))
  fr = prompt_freeze(s, list(interactive = FALSE))
  expect_identical(fr$preset, "minimal")
  expect_false("plugins" %in% fr$sections$name)
})

# Review round 2 (finding 3): an adapter that does not take tool additions drops the declarations
# of earlier tool_change messages, so after a switch to such a model only the frozen array counts
# as declared, and a tool that an earlier message declared is offered again as a member.
test_that("after a switch to a model without tool additions, re-added tools become members", {
  s = p07_session()
  sid = session_data(s)$id
  local_mocked_bindings(prompt_tool_addition = function(s) TRUE)
  session_add_tools(s, gptr_tool("p07_arr2", "In array.", execute = function(input, ctx) "x"))
  prompt_freeze(s, list(interactive = FALSE))
  session_add_tools(s, trials_tool())
  expect_length(pending_of(s), 1L)
  prompt_pending_flush(s)
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  session_add_tools(s, registry_get("tool", "p07_arr2", session = sid))
  expect_length(pending_of(s) %||% list(), 0L)
  session_add_tools(s, registry_get("tool", "trials", session = sid))
  q = pending_of(s)
  expect_length(q, 1L)
  expect_null(q[[1]]$tool_add)
  expect_match(msg_text(q[[1]]), "gptr$tools$trials(condition: string)", fixed = TRUE)
  expect_false(is.null(registry_get("tool", "tools/trials", session = sid)))
})

# Review round 2 (finding 4): the member signature is built before the spec is registered, so a
# schema it cannot read leaves the tool out entirely (D-075 item 5).
test_that("a member whose signature cannot be built is not registered", {
  s = p07_session()
  sid = session_data(s)$id
  prompt_freeze(s, list(interactive = FALSE))
  local_mocked_bindings(prompt_tool_addition = function(s) FALSE)
  bad = gptr_tool("p07_badsig", "Bad signature.",
                  parameters = function(ctx) list(type = "object", properties = list(a = "x")),
                  execute = function(input, ctx) "x")
  session_add_tools(s, list(bad, trials_tool()))
  expect_null(registry_get("tool", "tools/p07_badsig", session = sid))
  q = pending_of(s)
  expect_length(q, 1L)
  line = "gptr$tools$trials(condition: string)  # Search ClinicalTrials.gov by condition."
  expect_identical(msg_text(q[[1]]), sprintf(prompt_text("members_added"), line))
  msg = gptr_registry(diagnostics = TRUE)$message
  expect_true(any(grepl("Tool 'p07_badsig' was not added: ", msg, fixed = TRUE)))
})

# ---- Task 9: gptr_prompt() ----------------------------------------------------------------------

test_that("gptr_prompt() previews a preset without a session", {
  v = gptr_prompt(preset = "minimal")
  expect_s3_class(v, "gptr_prompt_view")
  expect_named(v, c("system", "tools_json", "first_message", "sections", "total_tokens"))
  expect_identical(attr(v, "preset"), "minimal")
  expect_true(startsWith(v$system$t0, prompt_text("preamble_short")))
  expect_identical(names(v$system), c("t0", "t1"))
  expect_identical(names(v$sections), c("name", "tier", "tokens"))
  expect_true(is.numeric(v$total_tokens) && v$total_tokens > 0)
  expect_match(v$first_message, "<environment>", fixed = TRUE)
  expect_true(all(is.na(gptr_prompt(preset = "minimal", tokens = FALSE)$sections$tokens)))
})

test_that("gptr_prompt() shows a session's frozen prompt and first message", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE))
  session_append(s, list(type = "message",
                         message = msg_user(list(block_context("environment", "Date: x"),
                                                 block_text("hello")))))
  v = gptr_prompt(s)
  expect_identical(v$system$t0, fr$t0)
  expect_identical(v$tools_json, fr$tools_json)
  expect_identical(v$first_message, "<environment>\nDate: x\n</environment>\n\nhello")
  expect_identical(attr(gptr_prompt(s, preset = "minimal"), "preset"), "minimal")
})

test_that("gptr_prompt() validates its arguments", {
  expect_error(gptr_prompt(preset = "nope"), class = "gptr_error_invalid_argument")
  expect_error(gptr_prompt(x = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_prompt(tokens = NA), class = "gptr_error_invalid_argument")
})

test_that("printing a prompt view shows each part and returns it invisibly", {
  v = gptr_prompt(preset = "minimal")
  vis = NULL
  # print() writes through P01's msg_verbatim(), i.e. cli::cli_verbatim(), whose output
  # utils::capture.output() does not see inside testthat; cli::cli_fmt() collects it
  out = paste(cli::cli_fmt({
    vis = withVisible(print(v))
  }), collapse = "\n")
  expect_match(out, "system block T0", fixed = TRUE)
  expect_match(out, "tool array", fixed = TRUE)
  expect_match(out, "first user message", fixed = TRUE)
  expect_match(out, prompt_text("preamble_short"), fixed = TRUE)
  expect_false(vis$visible)
  expect_identical(vis$value, v)
})

# A session whose .d$frozen is empty but whose active path holds a gptr.frozen entry freezes by
# restoring that entry (prompt_freeze(), Task 7), so the view shows the restored prompt rather
# than a fresh composition, and leaves .d$frozen and the transcript as they were.
test_that("gptr_prompt() shows a prompt kept only in gptr.frozen and writes nothing", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE, preset = "minimal"))
  d = session_data(s)
  d$frozen = NULL
  n = length(d$entries)
  v = gptr_prompt(s)
  expect_identical(attr(v, "preset"), "minimal")
  expect_identical(v$system$t0, fr$t0)
  expect_identical(v$system$t1, fr$t1)
  expect_identical(v$tools_json, fr$tools_json)
  expect_identical(attr(v, "tool_names"), fr$tool_names)
  expect_null(session_data(s)$frozen)
  expect_length(session_data(s)$entries, n)
})

# A session with a pending refreeze (a foreign file resumed under IC-52: rebuild_fill() leaves
# .d$frozen empty and sets .d$refreeze) freezes a fresh composition at its next run and never
# restores the gptr.frozen entry on its path, so the view shows that composition.
test_that("gptr_prompt() of a session with a pending refreeze shows the fresh composition", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE, preset = "minimal"))
  d = session_data(s)
  d$frozen = NULL
  d$refreeze = TRUE
  n = length(d$entries)
  v = gptr_prompt(s)
  expect_identical(attr(v, "preset"), "standard")
  expect_false(identical(v$system$t0, fr$t0))
  expect_null(session_data(s)$frozen)
  expect_true(session_data(s)$refreeze)
  expect_length(session_data(s)$entries, n)
  nx = prompt_freeze(s, list(interactive = FALSE, refreeze = TRUE))
  expect_identical(nx$preset, "standard")
  expect_identical(v$system$t0, nx$t0)
  expect_identical(v$system$t1, nx$t1)
  expect_identical(v$tools_json, nx$tools_json)
  expect_identical(attr(v, "tool_names"), nx$tool_names)
})

# A preview of a session's first message neither consumes a pending plan nor queues the
# operator-authority blocks the real first message would queue as reminders.
test_that("a preview of a session queues no operator message and stores nothing", {
  off = gptr_register(gptr_context_block("p07_note", function(ctx, budget) "Note.",
                                         placement = "first", authority = "operator"))
  withr::defer(off())
  s = p07_session()
  v = gptr_prompt(s)
  expect_false(grepl("p07_note", v$first_message, fixed = TRUE))
  expect_length(pending_of(s) %||% list(), 0L)
  expect_null(session_data(s)$frozen)
  expect_length(session_data(s)$entries, 0L)
  context_first_message(s, list(turn = 1L, prompt = "x"))
  expect_length(pending_of(s), 1L)
})

# preset = is validated against the presets the session sees, its own rank-0 records included
# (IC-69), as the composition resolves them.
test_that("gptr_prompt() accepts a session's own rank-0 preset (IC-69)", {
  s = p07_session()
  sid = session_data(s)$id
  id = registry_add(gptr_spec("preset", "p07_own", tools = c("read", "r")), "session", 0L,
                    session = sid)
  withr::defer(registry_remove(id))
  expect_identical(attr(gptr_prompt(s, preset = "p07_own"), "preset"), "p07_own")
  expect_error(gptr_prompt(preset = "p07_own"), class = "gptr_error_invalid_argument")
})
