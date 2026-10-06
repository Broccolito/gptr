# P02 Extension API and Registry Implementation Plan

> **Design amendment IC-74 (2026-10-03):** Read
> [`../spec/07-local-ollama.md`](../spec/07-local-ollama.md), especially the
> canonical classifier records and ownership matrix. Fake classifier answers
> and adapter validation must match the amended contract. Older literal code
> and PASS counts require reconciliation before implementation.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the one public, versioned extension API (S-11, REQ-41) on which every gptr capability and every built-in registers: the registry keyed by `(kind, name)` with ranks, filters, diagnostics and a generation counter, the 37 kinds of `ext-specs.R` with their validators and the 11 exported constructors, the event catalogue and its dispatch semantics, the factory API object and `ctx`, transactional and lazy loading, the built-in declaration table, and the `gptr_check()` conformance suites.

**Architecture:** Everything lives in L0 files `R/ext-*.R`: a registry environment (`gptr_registry_env`) holds classed spec records indexed by kind, by `(kind, key)` and by event, and resolves them at call time by rank, session scope and filters, so later plans find capabilities only through `registry_get()`/`registry_all()`/`ev_dispatch()` and never by function name. Factories `function(gptr)` receive a read-only API object whose registrations are staged and committed only when the factory returns; handlers receive a per-session `ctx` whose members fetch their implementations at call time through registry `service` records and P01's bootstrap service table, so members whose plan is not loaded signal `gptr_error_not_available`. The prototype is report G1's verified host package (G1 §5.1-5.5), converted to `=`/`|>`, without binding locks, and with the review amendments of contract §15.

**Tech Stack:** base R (>= 4.2.0); `jsonlite` through P01's `json_encode()`/`json_decode()`; `ps` (child processes in `gptr_check()`); `utils`, `stats`, `tools`; testthat 3e, withr and processx in tests only.

**Spec:** dev/spec/03-architecture.md (§2.1-2.2, §3.2 `ext-*` rows, §5.4, §5.10, §6.3, §6.4 R3/R4/R5, §11.1-11.4, §12.3), dev/spec/04-interface-contract.md (§1.1, §1.4, §2.1-2.2, §3.1 `gptr.deprecations`, §4.4-4.5, §5.4-5.7, §5.11, §5.13, §6.7, §6.8, §7.0, §7.2, §8.1, §9.1, §9.4, §10.1-10.9, §11.7, §11.12, §12.2; §15: IC-26, IC-32, IC-34, IC-35, IC-37, IC-42, IC-52, IC-53, IC-55, IC-69, IC-71), dev/spec/05-plan-decomposition.md (P02).

**Depends on:** P01 (Foundation). **Milestone:** M0.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only to update state of an enclosing function), the native `|>` (never `%>%`), ASCII-only R sources, `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions with messages built by concatenation (never glue-interpolated), no `:::` in `R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed global state restored with `on.exit(..., add = TRUE)`, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, lines of at most 100 characters, one commit per task whose message ends with the attribution line required by the executing harness (conventions §10). Plan-specific requirements, copied from the specification:

- Owned files (05 P02): `R/ext-registry.R`, `R/ext-specs.R`, `R/ext-api.R`, `R/ext-events.R`, `R/ext-load.R`, `R/ext-check.R`, `R/ext-builtins.R` and their tests `tests/testthat/test-ext-registry.R`, `test-ext-specs.R`, `test-ext-api.R`, `test-ext-events.R`, `test-ext-load.R`, `test-ext-check.R`, `test-ext-builtins.R`; plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`. No `DESCRIPTION` change (conventions §8: "A plan may not add an Import or a Suggests entry").
- Layer (03 §2.2, §3.2): every `ext-*.R` file is **L0**: it "may call base R, Imports, L0" and talks upward "only through return values; callbacks registered by upper layers". Later plans are reached only through the service table (IC-09, IC-34) and registry records. "Nothing below L5 prints" except `print()` methods of P02's own classes.
- Exports (04 §14.1, 18 names): `gptr_api`, `gptr_register`, `gptr_registry`, `gptr_reload`, `gptr_check`, `gptr_tool_result`, `gptr_spec`, `gptr_tool`, `gptr_provider`, `gptr_adapter`, `gptr_router`, `gptr_hook`, `gptr_policy`, `gptr_agent`, `gptr_command`, `gptr_prompt_section`, `gptr_context_block`, `gptr_backend`. Exact signatures (04 §6.7, §6.8, IC-35):
  - `gptr_api()`; `gptr_register(spec)`; `gptr_registry(kind = NULL, diagnostics = FALSE)`; `gptr_reload()`; `gptr_check(x, error = FALSE, tokens = FALSE)`; `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`; `gptr_spec(kind, name, ...)`.
  - `gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL, exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL, execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL, guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE, available = NULL, annotations = list())`
  - `gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat", "classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)`
  - `gptr_adapter(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"), build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())`
  - `gptr_router(name, route, description = NULL, timeout = 2)`; `gptr_hook(event, handler, matcher = NULL)`; `gptr_policy(name, check, description = NULL)`
  - `gptr_agent(name = NULL, description = NULL, model = NULL, tools = NULL, skills = NULL, system = NULL, backend = c("auto", "inline", "worker", "cli"), preset = "minimal", max_turns = NULL, mode = NULL, objects = NULL, export = NULL, returns = NULL, file = NULL)`
  - `gptr_command(name, handler, description = NULL, complete = NULL)`; `gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`; `gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"), budget = 300L, order = 650L)`; `gptr_backend(name, start, poll = NULL, cancel, capabilities = list())`
- Internal signatures (04 §7.2): `registry_add(spec, source, rank, session = NULL, state = "active")`, `registry_remove(id)`, `registry_get(kind, name, session = NULL)`, `registry_all(kind, session = NULL)`, `registry_names(kind, session = NULL)`, `registry_generation()`, `registry_filters_set(filters, scope = c("session", "user", "project"))`, `registry_diagnostic(source, event, class, message)`; `kind_define(name, validate, resolve = c("first", "all"), fields = chr, order_field = NULL, experimental = FALSE, source = "builtin")`, `kind_get(name)`, `kind_names()`, `spec_new(kind, name, ...)`, `as_tool_result(x)`; `ev_dispatch(event, payload, session = NULL, ctx = NULL)`, `ev_catalogue()`, `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)`, `hook_remove(id)`; `ext_api_new(source, dir = NULL, manifest = NULL)`, `ctx_new(session, run = NULL)`; `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)`, `ext_activate(source)`; `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `ext_load_builtins()`; `check_spec(spec)`, `check_factory(factory)`, `check_package(pkg)` (each returns the rows of a `gptr_check`; optional trailing arguments `tokens`, `adapter_check` and, for factories, `manifest`).
- Ranks and sources (04 §10.1): "call arguments ... | 0 | `session`"; "trusted project ... | 1 | `project`"; "user: `gptr_register()` ... | 3 | `user`"; "plugins ... | 5 | `plugin:<name>`"; "built-ins ... | 6 | `builtin:<name>`". "Same `(kind, name)`: the lowest rank wins; ties: the first registered, with a `collision` diagnostic." "A lower-rank record shadows **only** the record with the same `(kind, name)`; a whole built-in is disabled only by an explicit `-builtin:<name>` filter" (IC-69).
- Record shape (04 §5.5): `list(id = chr(1), kind, name, spec, rank = int(1), source = chr(1), state = chr(1) ("lazy", "active", "overridden", "disabled"), generation = int(1), tokens = num(1), session = chr(1) | NULL, order = int(1))`. `gptr_registry()` returns `c("gptr_registry", "data.frame")` with columns `kind`, `name`, `source`, `rank`, `state`, `tokens`, `experimental`; with `diagnostics = TRUE` `c("gptr_diagnostics", "data.frame")` with `time`, `source`, `event`, `class`, `message` (redacted).
- Filters (04 §10.1, IC-53): `-builtin:<name>`, `-plugin:<name>`, `-<kind>:<name>`, and `+...` to undo. "filters from a *project* settings file never disable `policy` or `hook` records of the user or of built-ins; filters from **no** source (project, user, call, `gptr_config()`) disable `builtin:permissions`, `builtin:plan`, the `critical_guard` and `secret_guard` policies or `builtin:secrets`, and inside a run filters that would remove `policy` or `hook` records are refused". The settings key is `filters` (04 §11.2, owner P02): P02 owns its meaning and `registry_filters_set(filters, scope)`; the settings layer (P08, the only code that knows which layer a value came from) passes the user file's `filters` with `scope = "user"`, the project file's with `scope = "project"`, and `gptr_config()`/call filters with `scope = "session"` (the `settings.get` service returns merged values only, so P02 cannot split layers itself).
- Kinds (04 §10.2): 38 in all, "P02 defines 37, P22 adds `interpreter`". Resolve `all`: `hook`, `policy` (order field `order`, default `500`), `context_block` (`order`, default `650`), `prompt_section` (`order`), `secret_source`, `redaction_rule`, `env_alias`, `checkpointer`, `route` (`order`, num), `risk_rule`, `search_source`; every other kind resolves `first`. Experimental kinds: `artifact_type`, `frontend`, `checkpointer`, `route`, `service`, `renderer`, `search_source`, `store`, `evaluator` (and plugin-defined kinds). "Validators accept unknown fields (forward compatibility) and reject wrong types of known fields with `gptr_error_invalid_spec`." Every spec has `kind`, `name` and `api_version` (IC-23) and class `c("gptr_<kind>", "gptr_spec")`.
- Tool rules (04 §9.1, IC-37): name `^[a-zA-Z0-9_-]{1,64}$`; "direct tools at most 400 estimated tokens (`gptr_check()`)"; "`parameters` ... `NULL` = derived from `fun`'s formals (all `string`, required when no default)"; "a plugin spec with `exposure = "r"` MUST set `namespace`; a namespace equal to a reserved or existing member name is `gptr_error_invalid_spec` at registration"; reserved member names (04 §9.4): `read`, `write`, `edit`, `grep`, `find`, `ls`, `help`, `search`, `describe`, `plot`, `out`, `sh`, `script`, `bg`, `jobs`, `py`, `sql`, `knit`, `app`, `mcp`.
- Other kind rules: provider id `^[a-z0-9][a-z0-9-]*$`; skill description "<= 1,024 chars"; adapters "`http_*` and `process_jsonl` need `build` and `parse`, `inprocess` needs `stream`, classifier adapters need `classify`" (IC-35); "A `gptr_context_block()` with `authority = "operator"` is accepted only from records of rank >= 3" (IC-52); `gptr_agent()` "stores the raw captured expressions (symbol names or literals)" (IC-34); agent names equal to a session accessor are rejected (IC-71); a redaction rule "must not match its own marker"; a policy "must return within 10 ms".
- Events (04 §10.4, D-25, IC-03): 46 catalogued events plus `<plugin>:<topic>` channels; semantics notify, collect, transform chain, decision (`tool_call`, **error = block**), first decision (`permission_request`: **error = deny**), patch chain (`tool_result`, `request_params`), block + patch (`document_write`, **error = block**). "Hook-injected context (returned `blocks`, `text` of transforms) is capped at 10,000 characters per dispatch." "Every event payload passes `redact_tree(profile = "stream")` before dispatch" (through P01's `redact_hook()`). Claude/Codex names are refused with a hint.
- API object and `ctx` (04 §5.6, §10.5, §10.6, IC-26): environments of class `gptr_extension_api` and `gptr_ctx`; "No binding is locked ... `$<-` and `[[<-` methods refuse assignment (`gptr_error_readonly`) except re-assigning `state` to the identical environment". "After `gptr_reload()` or the plugin's unload, every method signals `gptr_error_stale_api`." `ctx` "is created once per session (`ctx_new()`), never per dispatch; members are closures that fetch their service at call time".
- API version (04 §6.7, §10.9): `gptr_api()$version` is `package_version("1.0")`; features `kind.<name>`, `event.<name>`, `lazy_activation`, `declarations`, `ctx.decide`, `ctx.secret`, `route`, `services`. Requirements: `"1.2"` is caret (`>= 1.2, < 2`), otherwise comma-separated `op version` with `op` in `>=, >, <=, <, ==`; one-component versions become `"x.0"` (G1 §3.5, verification row 25).
- Option (04 §3.1): `gptr.deprecations` (`chr(1)`, default `"warn"`, owner P02): `"warn"` or `"error"`; "a deprecated member warns once per session (`gptr_warning_deprecated`; `options(gptr.deprecations = "error")` for plugin CI)".
- Conditions (04 §2.2): `gptr_error_invalid_spec` (`kind`, `name`, `field`, `problem`), `gptr_error_unknown_kind` (parent `invalid_spec`; `kind`), `gptr_error_api_version` (`plugin`, `required`, `available`), `gptr_error_stale_api` (`plugin`, `generation`), `gptr_error_conformance` (`results`), `gptr_error_not_available` (`member`, `provided_by`), `gptr_error_readonly` (`object`, `field`), `gptr_error_unknown_member` (`name`, `available`), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_permission` (`action`, `tool`, `risk`, `how_to_allow`, `session`), `gptr_error_tool` (`tool`, `status`); warnings `gptr_warning_deprecated` and `gptr_warning_plugin` (field `diagnostic`).
- Package state (04 §7.0): P02 owns `the$registry`, `the$kinds`, `the$hooks`, `the$builtins`, `the$diagnostics` ("registry env; kind table; event index; built-in declarations; diagnostics log"). No run state (INFRA-15).
- Control exports (IC-53 point 3): `gptr_register` and `gptr_reload` "called from model code during a run ... signal `gptr_error_permission` unless the dispatcher approved exactly that call through an `ask_human` (a one-shot token on the run)".
- Copy safety (03 §6.4): no `lockBinding()`/`unlockBinding()` (R5); `gptr_agent()` is a capture site obeying R3 (never forces or assigns its identifier formals); `ctx` holds the session shell only, never frames or user objects (R1, R2, R10).
- Tests (conventions §7, 04 §12.2): test helpers local to each P02 test file (`local_registry()`, `local_builtins()`, `local_service()`), P01's `gptr_fake_provider()` and `rscript_path()`; processes only under `skip_on_cran()`; no wall-clock assertion tighter than 5 seconds.

### Interfaces used from P01

These are the 04 §2.1, §7.0 and §7.1 signatures as `dev/plan/P01-foundation.md` defines them (the review assembled P01's plan code with this plan's code and ran every P02 test against it):

| From | Signature | Used for |
|---|---|---|
| `aaa-state.R` | `the`; `` `%||%` ``; `on_unload(fun)`; `redact_hook(x, profile = "persist")`; `ext_service_set(name, fun, provided_by, builtin = NULL)`; `ext_service_get(name)`; `ext_service_has(name)` | state, the unload cleanup of package-unload hooks, redaction of payloads and diagnostics, bootstrap services; P01's `ext_service_get()` consults `registry_get("service", name)` first and lists `gptr_registry()` to decide built-in ownership on every lookup (IC-34), which is why `gptr_registry()` caches its full listing (Task 4) |
| `zzz.R` | `.onLoad` runs the `on_load()` expressions, then `ext_load_builtins()` | built-in loading |
| `utils-conditions.R` | `gptr_abort(message, class, ..., .data = NULL, call = NULL)`; `gptr_warn(message, class, ..., .data = NULL, .once = NULL)`; `gptr_deprecated(what, since, instead = NULL)`; `msg_verbatim(x, stream = c("stdout", "stderr"))`; `check_string()`, `check_strings()`, `check_flag()`, `check_number()`, `check_choice()`, `check_function()`, `check_list()`, `check_class()` | conditions, argument checks |
| `utils-options.R` | `gptr_opt(name)` | `gptr.r_output_tokens`, `gptr.helper_output_tokens`, `gptr.deprecations` |
| `utils-text.R` | `truncate_output(text, budget_tokens, class = "r_output", head = 0.4, id_prefix = "o")` | the generated `execute()` of `fun`-only direct tools |
| `utils-tokens.R` | `est_tokens(x, class)` | the `tokens` column, `ctx$tokens()`, `gptr_check()` budgets |
| `json-encode.R` | `json_encode(x, pretty = FALSE)`, `json_decode(text)`, `json_obj()` | declarations, manifests |
| `json-schema.R` | `schema_validate(schema, input)`, `schema_signature(name, schema, description = NULL, prefix = "")`, `schema_problems(schema)` | tool checks, signatures |
| `provider-message.R` | `block_text(text, signature = NULL)`, `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)` | `gptr_tool_result()` |
| `provider-fake.R`, `utils-paths.R` (tests) | `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`; `rscript_path()` | provider spec validation; the backend process check |

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/ext-events.R` | create (Task 1), extend (Task 8) | the event catalogue of 04 §10.4 with semantics and hints; `ev_dispatch()` with the §10.7 algorithms, fail-closed events, stream redaction, the 10,000-character cap, run/tool tracking for IC-53; `hook_add()`, `hook_remove()`; the fail-closed policy evaluator `ext_policy_decide()` |
| `R/ext-registry.R` | create (Task 2), extend (Tasks 4, 5) | the registry environment and its binding to `the`; records, indexes, resolution by rank, session and filters; diagnostics; the IC-53 control guard; `gptr_register()`, `gptr_registry()`; filters |
| `R/ext-specs.R` | create (Task 2), extend (Tasks 3, 4) | the kind table (37 kinds) and validators, `kind_define()`/`kind_get()`/`kind_names()`, the spec engine `spec_new()`, `gptr_spec()`, spec printing; the 11 constructors, `gptr_tool_result()`, `as_tool_result()`; kinds defined by `kind` records |
| `R/ext-api.R` | create (Task 6), extend (Task 7) | the factory API object (`register`, `register_<kind>`, `on`, `require`, `has`, `state`, staging) and `ctx` (service-bound members, the `none` UI, read-only methods) |
| `R/ext-check.R` | create (Task 6), extend (Task 11) | `gptr_api()`, the API deprecation helper, and `gptr_check()` with its spec, factory and package suites |
| `R/ext-load.R` | create (Task 9) | `ext_load()` (stage, commit, rollback, requirements), lazy placeholders and declarations, activation, session scope, `ext_unload()`, unload watching, `gptr_reload()` |
| `R/ext-builtins.R` | create (Task 10) | `the$builtins`, `ext_declare_builtin()`, dependency order, `ext_load_builtins()` |
| `tests/testthat/test-ext-events.R` | create (Task 1), extend (Task 8) | catalogue, names, every dispatch semantics, fail-closed events, redaction, tracking, policies |
| `tests/testthat/test-ext-specs.R` | create (Task 2), extend (Task 3) | kind table, validators, every 04 §6.8 example, constructors, tool results |
| `tests/testthat/test-ext-registry.R` | create (Task 4), extend (Task 5) | precedence, per-record overrides, admission rules, listings, diagnostics, filters and the IC-53 rules |
| `tests/testthat/test-ext-api.R` | create (Task 6), extend (Task 7) | API object, requirement grammar, stale objects, `ctx` members and services |
| `tests/testthat/test-ext-check.R` | create (Task 6), extend (Task 11) | `gptr_api()`, deprecations, every `gptr_check()` suite |
| `tests/testthat/test-ext-load.R` | create (Task 9) | transactions, rollbacks, lazy activation, reload, session scope, unload, timing |
| `tests/testthat/test-ext-builtins.R` | create (Task 10) | declarations, load order, filters on built-ins |
| `NAMESPACE`, `man/*.Rd` | regenerate (Tasks 2, 3, 4, 6, 7, 9, 11) | the 18 exports and the S3 methods, through `devtools::document()` |

Tasks:

1. Event catalogue (`ext-events.R`)
2. Registry state, kind table and spec engine (`ext-registry.R`, `ext-specs.R`)
3. Spec constructors and tool results (`ext-specs.R`)
4. Records, resolution, `gptr_register()` and `gptr_registry()` (`ext-registry.R`, `ext-specs.R`)
5. Filters (`ext-registry.R`)
6. Factory API object, `gptr_api()` and deprecations (`ext-api.R`, `ext-check.R`)
7. `ctx` and services (`ext-api.R`)
8. Event dispatch, hooks and policies (`ext-events.R`)
9. Transactional and lazy loading, session scope, unload, `gptr_reload()` (`ext-load.R`)
10. Built-in declarations and load order (`ext-builtins.R`)
11. `gptr_check()` conformance suites (`ext-check.R`)

---

### Task 1: Event catalogue

**Files:**
- Create: `R/ext-events.R`
- Test: `tests/testthat/test-ext-events.R` (create)

**Interfaces:**
- Consumes: P01 `gptr_abort(message, class, ..., .data = NULL, call = NULL)`.
- Produces: `ev_catalogue()` -> `data.frame(event, semantics, fail_closed, payload, returns, origin)` (04 §7.2), one row per event of 04 §10.4 (46 events); internal `ev_table` (the same data frame), `ev_semantics(event)` -> `"notify"`, `"collect"`, `"transform"`, `"decision"`, `"first_decision"`, `"patch"`, `"block_patch"` or `NULL` (channels `"<plugin>:<topic>"` are `"notify"`), `ev_is_channel(event)` -> `lgl(1)`, `ev_hint(event)` -> `chr(1) | NULL`, `ev_check_name(event, arg = "event")` (signals `gptr_error_invalid_argument` with a hint for Claude/Codex, pre-IC-03 and unported Pi names).

The catalogue is the D-25 table of 04 §10.4 (Pi names where the semantics match, IC-03); report G1's verification log (row 16) notes that the prototype's uncatalogued `compaction` event must not exist, so the hint table sends it to `session_compact`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-events.R`:

```r
test_that("the catalogue lists the 46 events of contract 10.4 with their semantics", {
  cat = ev_catalogue()
  expect_named(cat, c("event", "semantics", "fail_closed", "payload", "returns", "origin"))
  expect_equal(nrow(cat), 46L)
  expect_equal(anyDuplicated(cat$event), 0L)
  expect_setequal(cat$event[cat$fail_closed],
                  c("tool_call", "permission_request", "document_write"))
  expect_true(all(cat$semantics %in% c("notify", "collect", "transform", "decision",
                                       "first_decision", "patch", "block_patch")))
  expect_true(all(cat$origin %in% c("pi", "gptr")))
  expect_equal(cat$origin[cat$event == "request_params"], "gptr")
  expect_equal(cat$origin[cat$event == "tool_call"], "pi")
  expect_equal(ev_semantics("tool_call"), "decision")
  expect_equal(ev_semantics("tool_result"), "patch")
  expect_equal(ev_semantics("request_params"), "patch")
  expect_equal(ev_semantics("input"), "transform")
  expect_equal(ev_semantics("session_start"), "collect")
  expect_equal(ev_semantics("resources_discover"), "collect")
  expect_equal(ev_semantics("permission_request"), "first_decision")
  expect_equal(ev_semantics("project_trust"), "first_decision")
  expect_equal(ev_semantics("document_write"), "block_patch")
  expect_equal(ev_semantics("myplugin:done"), "notify")
  expect_null(ev_semantics("PreToolUse"))
})

test_that("Claude, Codex, pre-IC-03 and unported names are refused with a hint", {
  err = expect_error(ev_check_name("PreToolUse"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "did you mean 'tool_call'?", fixed = TRUE)
  expect_equal(err$arg, "event")
  err = expect_error(ev_check_name("session_end"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "session_shutdown", fixed = TRUE)
  err = expect_error(ev_check_name("context"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "not ported", fixed = TRUE)
  err = expect_error(ev_check_name("Tool_Call"), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(err), "did you mean 'tool_call'?", fixed = TRUE)
  expect_error(ev_check_name("no_such_event"), class = "gptr_error_invalid_argument")
  expect_error(ev_check_name(NA_character_), class = "gptr_error_invalid_argument")
  expect_error(ev_check_name(c("a", "b")), class = "gptr_error_invalid_argument")
  expect_equal(ev_check_name("tool_call"), "tool_call")
  expect_equal(ev_check_name("myplugin:done"), "myplugin:done")
  expect_true(ev_is_channel("my.plugin:topic-1"))
  expect_false(ev_is_channel("tool_call"))
  expect_false(ev_is_channel("a:b:c"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-events")'`
Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 0 ]`, from errors such as `could not find function "ev_catalogue"` and `could not find function "ev_check_name"`.

- [ ] **Step 3: Write the implementation**

Create `R/ext-events.R`:

```r
# ext-events.R -- the event catalogue (contract 10.4) and dispatch (contract 7.2, 10.7).
# Event names follow D-25 / IC-03: Pi names where the semantics match, gptr names otherwise.
# Claude and Codex hook names are refused with a hint (report G1 3.2; the v1.x importer maps
# them). Semantics are encoded as notify, collect, transform (chain), decision, first_decision,
# patch (chain) and block_patch.

#' One row of the event catalogue
#' @noRd
ev_row = function(event, semantics, payload, returns = "", origin = "pi", fail_closed = FALSE) {
  data.frame(event = event, semantics = semantics, fail_closed = fail_closed, payload = payload,
             returns = returns, origin = origin, stringsAsFactors = FALSE)
}

#' The event catalogue of contract 10.4 (46 events)
#' @noRd
ev_table = rbind(
  ev_row("project_trust", "first_decision", "cwd, changed",
         "list(decision = \"yes\" | \"no\", remember)"),
  ev_row("resources_discover", "collect", "cwd, reason",
         "list(skill_paths, prompt_paths, agent_paths)"),
  ev_row("session_start", "collect", "reason", "list(sections, blocks)"),
  ev_row("session_before_fork", "first_decision", "source, at", "list(cancel = TRUE, reason)"),
  ev_row("session_shutdown", "notify", "reason"),
  ev_row("input", "transform", "text, source",
         "list(action = \"continue\" | \"transform\" | \"handled\", text)"),
  ev_row("agent_start", "notify", ""),
  ev_row("agent_end", "notify", "status, reason, usage, doc, turns"),
  ev_row("turn_start", "notify", ""),
  ev_row("turn_end", "notify", "message, results"),
  ev_row("before_request", "notify", "provider, model, request_id, view, tokens_est",
         origin = "gptr"),
  ev_row("request_params", "patch", "provider, model, params", "list(params)", origin = "gptr"),
  ev_row("message_start", "notify", "role"),
  ev_row("message_update", "notify", "role, index, kind, delta"),
  ev_row("message_end", "notify", "role, message"),
  ev_row("tool_call", "decision",
         "tool_name, tool_call_id, input, nested, parent_tool_call_id, risk",
         "NULL, list(decision = \"block\", reason) or list(decision = \"modify\", input)",
         fail_closed = TRUE),
  ev_row("permission_request", "first_decision", "the permission request record (contract 7.11)",
         "list(decision = \"allow\" | \"deny\", reason)", origin = "gptr", fail_closed = TRUE),
  ev_row("tool_execution_start", "notify", "tool_call_id, tool_name, input"),
  ev_row("tool_execution_update", "notify", "tool_call_id, tool_name, text"),
  ev_row("tool_execution_end", "notify", "tool_call_id, tool_name, is_error, elapsed, details"),
  ev_row("tool_result", "patch", "tool_name, tool_call_id, input, content, details, is_error",
         "list(content, details, is_error)"),
  ev_row("queue_update", "notify", "steer, follow_up"),
  ev_row("retry_start", "notify", "attempt, delay, class", origin = "gptr"),
  ev_row("retry_end", "notify", "attempt, ok", origin = "gptr"),
  ev_row("session_before_compact", "first_decision", "reason, tokens",
         "list(cancel = TRUE) or list(result)"),
  ev_row("session_compact", "notify", "strategy, tokens_before, summary_tokens"),
  ev_row("session_before_tree", "first_decision", "from, to, plan", "list(cancel = TRUE, reason)"),
  ev_row("session_tree", "notify", "from, to, report"),
  ev_row("document_write", "block_patch", "path, format, kind, block_id, lines",
         "list(block = TRUE, reason) or list(lines)", origin = "gptr", fail_closed = TRUE),
  ev_row("decision", "notify", "model, question, type, n, summary, cached", origin = "gptr"),
  ev_row("route", "notify", "route, router, model, reason", origin = "gptr"),
  ev_row("model_select", "notify", "from, to, reason"),
  ev_row("subagent_start", "notify", "child, agent, backend, model", origin = "gptr"),
  ev_row("subagent_end", "notify", "child, agent, backend, model, status, usage",
         origin = "gptr"),
  ev_row("artifact_start", "notify", "id, url, version", origin = "gptr"),
  ev_row("artifact_stop", "notify", "id, url, version, reason", origin = "gptr"),
  ev_row("usage", "notify", "row", origin = "gptr"),
  ev_row("budget_near", "notify", "kind, budget, used", origin = "gptr"),
  ev_row("budget_exceeded", "notify", "kind, budget, used", origin = "gptr"),
  ev_row("cache_break", "notify", "provider, model, first_diff, entry, culprit", origin = "gptr"),
  ev_row("bridge_call", "notify",
         "bridge, id, cmd, level, status, seconds, bytes_out, bytes_err, spill, digest",
         origin = "gptr"),
  ev_row("checkpoint", "notify", "tool_call_id, objects, files, restorable", origin = "gptr"),
  ev_row("secret_registered", "notify", "name, source, count", origin = "gptr"),
  ev_row("mcp_servers_change", "notify", "added, removed"),
  ev_row("mcp_serve_start", "notify", "url", origin = "gptr"),
  ev_row("mcp_serve_stop", "notify", "url", origin = "gptr")
)

#' Hints for names that are not gptr events (Claude/Codex, pre-IC-03 and unported Pi names)
#' @noRd
ev_hints = c(
  PreToolUse = "did you mean 'tool_call'?", PostToolUse = "did you mean 'tool_result'?",
  UserPromptSubmit = "did you mean 'input'?", SessionStart = "did you mean 'session_start'?",
  SessionEnd = "did you mean 'session_shutdown'?", Stop = "did you mean 'agent_end'?",
  SubagentStart = "did you mean 'subagent_start'?", SubagentStop = "did you mean 'subagent_end'?",
  PreCompact = "did you mean 'session_before_compact'?",
  PostCompact = "did you mean 'session_compact'?",
  PermissionRequest = "did you mean 'permission_request'?",
  session_end = "did you mean 'session_shutdown'?",
  pre_compact = "did you mean 'session_before_compact'?",
  post_compact = "did you mean 'session_compact'?", compaction = "did you mean 'session_compact'?",
  before_agent_start = "not ported from Pi; use 'session_start'",
  agent_settled = "not ported from Pi; use 'agent_end'",
  agent_before_settle = "not ported from Pi; use 'agent_end'",
  context = "not ported from Pi; use a compactor, context_block or request_params record",
  context_with_system = "not ported from Pi; use a prompt_section or context_block record",
  before_provider_request = "not ported from Pi; use 'before_request' or 'request_params'",
  before_provider_headers = "not ported from Pi; use 'request_params'",
  after_provider_response = "not ported from Pi; use 'usage'",
  provider_stream_event = "not ported from Pi; use 'message_update'",
  session_before_switch = "not ported from Pi", session_compact_failed = "not ported from Pi",
  session_info_changed = "not ported from Pi", thinking_level_select = "not ported from Pi",
  ui_prompt_start = "not ported from Pi", ui_prompt_end = "not ported from Pi",
  user_bash = "not ported from Pi (gptr has no bash tool)"
)

#' The event catalogue as a data frame (contract 7.2)
#' @noRd
ev_catalogue = function() {
  ev_table[, c("event", "semantics", "fail_closed", "payload", "returns", "origin")]
}

#' Is `event` a plugin channel name ("<plugin>:<topic>")?
#' @noRd
ev_is_channel = function(event) {
  is.character(event) && length(event) == 1L && !is.na(event) &&
    grepl("^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$", event, perl = TRUE)
}

#' Dispatch semantics of an event; channels notify; NULL for unknown names
#' @noRd
ev_semantics = function(event) {
  i = match(event, ev_table$event)
  if (!is.na(i)) return(ev_table$semantics[[i]])
  if (ev_is_channel(event)) return("notify")
  NULL
}

#' A hint for an unknown event name, or NULL
#' @noRd
ev_hint = function(event) {
  if (!is.character(event) || length(event) != 1L || is.na(event)) return(NULL)
  h = ev_hints[event]
  if (!is.na(h)) return(unname(h))
  i = match(tolower(event), tolower(ev_table$event))
  if (!is.na(i)) return(paste0("did you mean '", ev_table$event[[i]], "'?"))
  NULL
}

#' Validate an event name for hook registration (contract 7.2 hook_add)
#' @noRd
ev_check_name = function(event, arg = "event") {
  ok = is.character(event) && length(event) == 1L && !is.na(event) &&
    (event %in% ev_table$event || ev_is_channel(event))
  if (ok) return(invisible(event))
  label = if (is.character(event) && length(event) == 1L && !is.na(event)) event else "?"
  hint = ev_hint(event)
  gptr_abort(paste0("Unknown gptr event '", label, "'",
                    if (is.null(hint)) "" else paste0("; ", hint),
                    ". Events are listed by gptr_api()$features; plugin channels are named ",
                    "'<plugin>:<topic>'."),
             "invalid_argument", arg = arg,
             expected = "a catalogued event name or a <plugin>:<topic> channel")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-events")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 36 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-events.R tests/testthat/test-ext-events.R
git commit -m "feat(ext): add the event catalogue"
```

---

### Task 2: Registry state, kind table and spec engine

**Files:**
- Create: `R/ext-registry.R`, `R/ext-specs.R`
- Modify: `NAMESPACE`, `man/gptr_spec.Rd` (generated)
- Test: `tests/testthat/test-ext-specs.R` (create)

**Interfaces:**
- Consumes: P01 `the`, `` `%||%` ``, `gptr_abort()`, `check_string(x, arg, null = FALSE, empty = FALSE)`, `check_strings()`, `check_function(x, arg, null = FALSE, args = NULL)`, `check_flag()`, `check_choice(x, choices, arg)`, `json_obj()`, `truncate_output(text, budget_tokens, ...)`, `gptr_opt(name)`; Task 1 `ev_table`, `ev_is_channel()`, `ev_hint()`; `gptr_fake_provider()` in the test.
- Produces (04 §5.4, §5.13, §7.2, §6.7): the registry environment of class `gptr_registry_env` (`registry_new()`, `registry_env()`, `registry_scratch()`, `registry_swap(reg)` -> the previous registry invisibly, `registry_bind(reg)`, which points `the$registry`, `the$kinds`, `the$hooks` and `the$diagnostics` at it; `registry_touch(reg)`, called by every change of records, filters or kinds so that Task 4's cached `gptr_registry()` listing is rebuilt); `ext_session_id(session)` -> `chr(1) | NULL` (a session id string or anything with an `id`); `ext_api_version` (`"1.0"`); `kind_define(name, validate, resolve = c("first", "all"), fields = character(), order_field = NULL, experimental = FALSE, source = "builtin")`; `kind_get(name)` -> the kind record `list(name, validate, resolve, fields, order_field, experimental, source, record, staged)` or `gptr_error_unknown_kind` (a `gptr_error_invalid_spec`); `kind_names()` -> sorted chr; `kind_user_validate(validate)`; `spec_new(kind, name, ...)`; `spec_finish(spec, k)`; `spec_abort(spec, field, problem)`; the exported `gptr_spec(kind, name, ...)`; `format.gptr_spec()` and `print.gptr_spec()` (functions shown as `<fn>`).

`ext-specs.R` defines the 37 kinds of 04 §10.2 (all but `interpreter`, which P22 adds through the `kind` kind). Two helpers are defined here for later tasks: `spec_tool_execute()` (the generated `execute()` of a direct tool that has only `fun`) and `spec_tool_fun()` (the generated `fun()` of an `r` member that has only `execute`), whose body calls `ctx_default()` from Task 7 when it runs; nothing in Tasks 2 to 6 calls it.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-specs.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("a scratch registry can be swapped in and out; the fields of `the` follow it", {
  before = registry_env()
  reg = local_registry()
  expect_s3_class(reg, "gptr_registry_env")
  expect_false(identical(reg, before))
  expect_identical(the$registry, reg)
  expect_identical(the$kinds, reg$kinds)
  expect_identical(the$hooks, reg$hooks)
  expect_identical(the$diagnostics, reg$diag)
  expect_equal(reg$generation, 1L)
})

test_that("ext_session_id() accepts ids, session-like objects and NULL", {
  expect_null(ext_session_id(NULL))
  expect_equal(ext_session_id("s123"), "s123")
  e = new.env()
  e$id = "s456"
  expect_equal(ext_session_id(e), "s456")
  expect_null(ext_session_id(42))
  expect_null(ext_session_id(NA_character_))
})

test_that("the kind table holds the 37 kinds of contract 10.2 (interpreter is P22's)", {
  local_registry()
  kinds = c("adapter", "agent", "artifact_type", "backend", "cache_policy", "checkpointer",
            "child_env", "command", "compactor", "context_block", "doc_format", "env_alias",
            "estimator", "evaluator", "frontend", "hook", "kind", "mcp_server", "model", "policy",
            "preset", "prompt_section", "prompt_template", "provider", "redaction_rule",
            "renderer", "risk_rule", "route", "router", "search_source", "secret_source",
            "service", "setting", "skill", "store", "tool", "ui")
  expect_equal(kind_names(), kinds)
  all_kinds = kinds[vapply(kinds, function(k) kind_get(k)$resolve == "all", NA)]
  expect_setequal(all_kinds, c("checkpointer", "context_block", "env_alias", "hook", "policy",
                               "prompt_section", "redaction_rule", "risk_rule", "route",
                               "search_source", "secret_source"))
  expect_equal(kind_get("policy")$order_field, "order")
  expect_equal(kind_get("route")$order_field, "order")
  expect_equal(kind_get("context_block")$order_field, "order")
  expect_null(kind_get("hook")$order_field)
  exp = kinds[vapply(kinds, function(k) isTRUE(kind_get(k)$experimental), NA)]
  expect_setequal(exp, c("artifact_type", "checkpointer", "evaluator", "frontend", "renderer",
                         "route", "search_source", "service", "store"))
})

test_that("gptr_spec() builds a classed spec carrying api_version", {
  local_registry()
  s = gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
  expect_s3_class(s, c("gptr_env_alias", "gptr_spec"), exact = TRUE)
  expect_equal(s$kind, "env_alias")
  expect_equal(s$api_version, "1.0")
  expect_equal(s$aliases, "slack-token")
  err = expect_error(gptr_spec("widget", "w"), class = "gptr_error_unknown_kind")
  expect_s3_class(err, "gptr_error_invalid_spec")
  expect_equal(err$kind, "widget")
  expect_error(gptr_spec(1, "w"), class = "gptr_error_invalid_argument")
})

test_that("validators name the failing field and accept unknown fields", {
  local_registry()
  err = expect_error(gptr_spec("router", "r1", route = "not a function"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "route")
  expect_equal(err$kind, "router")
  expect_equal(err$name, "r1")
  err = expect_error(gptr_spec("router", "r1"), class = "gptr_error_invalid_spec")
  expect_equal(err$problem, "is required")
  err = expect_error(gptr_spec("policy", "p", check = function(call) NULL),
                     class = "gptr_error_invalid_spec")
  expect_match(err$problem, "accepting (call, ctx)", fixed = TRUE)
  expect_equal(gptr_spec("command", "x", handler = function(args, ctx) NULL, colour = "b")$colour,
               "b")
  expect_error(gptr_spec("command", "x", handler = function(args, ctx) NULL, name = "y"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "", handler = function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "x", function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
})

test_that("defaults are filled and whole numbers become integers", {
  local_registry()
  b = gptr_spec("context_block", "lab", provide = function(ctx, budget) "x", order = 700)
  expect_equal(b$placement, "turn")
  expect_equal(b$authority, "data")
  expect_identical(b$budget, 300L)
  expect_identical(b$order, 700L)
  expect_error(gptr_spec("context_block", "lab", provide = function(ctx, budget) "x",
                         order = 7.5), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("policy", "p", check = function(call, ctx) NULL)$order, 500L)
  expect_equal(gptr_spec("prompt_section", "s", text = "x")$tier, "T0")
  expect_equal(gptr_spec("router", "r", route = function(request, ctx) "m")$timeout, 2)
})

test_that("provider specs: id rules, and the fake provider of P01 validates", {
  local_registry()
  p = gptr_spec("provider", "corp", api = "openai-completions")
  expect_equal(p$id, "corp")
  expect_equal(p$type, "chat")
  expect_false(p$offline)
  expect_false(p$local)
  err = expect_error(gptr_spec("provider", "Bad_Name", api = "x"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "id")
  expect_error(gptr_spec("provider", "corp", api = "x", models = list(list(context = 1))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("provider", "corp", api = "x", rate = list(rpm = 1)),
               class = "gptr_error_invalid_spec")
  fake = spec_finish(gptr_fake_provider(list("hi")), kind_get("provider"))
  expect_s3_class(fake, "gptr_provider")
  expect_true(fake$offline)
})

test_that("adapter specs are validated per transport (IC-35)", {
  local_registry()
  expect_error(gptr_spec("adapter", "wire", transport = "http_sse",
                         build = function(model, context, opts) NULL),
               class = "gptr_error_invalid_spec")
  a = gptr_spec("adapter", "wire", transport = "http_sse",
                build = function(model, context, opts) NULL, parse = function(model, opts) NULL)
  expect_equal(a$api, "wire")
  err = expect_error(gptr_spec("adapter", "gen", transport = "inprocess"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "stream")
  cls = gptr_spec("adapter", "cls", transport = "inprocess",
                  classify = list(run = function(model, state, questions, opts) NULL))
  expect_true(is.function(cls$classify$run))
  err = expect_error(gptr_spec("adapter", "cls", transport = "http_json",
                               classify = list(build = function(...) NULL)),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "classify")
  expect_error(gptr_spec("adapter", "x", api = "y", transport = "inprocess",
                         stream = function(model, context, opts) NULL),
               class = "gptr_error_invalid_spec")
})

test_that("model specs are keyed provider/id", {
  local_registry()
  m = gptr_spec("model", "corp/corp-large", context = 128000, release_date = NA_character_)
  expect_equal(m$provider, "corp")
  expect_equal(m$id, "corp-large")
  expect_equal(m$ref, "corp/corp-large")
  expect_error(gptr_spec("model", "corp-large"), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("model", "corp/a", id = "b"), class = "gptr_error_invalid_spec")
})

test_that("hook specs accept catalogued events and plugin channels only", {
  local_registry()
  expect_equal(gptr_spec("hook", "tool_result", event = "tool_result",
                         handler = function(event, ctx) NULL)$event, "tool_result")
  expect_equal(gptr_spec("hook", "x:y", event = "x:y", handler = function(event, ctx) NULL)$event,
               "x:y")
  err = expect_error(gptr_spec("hook", "PreToolUse", event = "PreToolUse",
                               handler = function(event, ctx) NULL),
                     class = "gptr_error_invalid_spec")
  expect_match(err$problem, "tool_call", fixed = TRUE)
})

test_that("tool specs: name rule, execute or fun, schema from formals, fun matching the schema", {
  local_registry()
  expect_error(gptr_spec("tool", "bad name", description = "d",
                         execute = function(input, ctx) NULL), class = "gptr_error_invalid_spec")
  err = expect_error(gptr_spec("tool", "t", description = "d"), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "execute")
  t = gptr_spec("tool", "paste2", description = "Paste two strings", exposure = "r",
                fun = function(a, b = "x") paste(a, b))
  expect_equal(t$parameters$properties, list(a = list(type = "string"), b = list(type = "string")))
  expect_equal(as.character(t$parameters$required), "a")
  expect_null(t$execute)
  expect_error(gptr_spec("tool", "t2", description = "d", fun = function(x) x,
                         parameters = list(type = "object", properties = list(y = list()))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t3", description = "d", fun = function(x, y) x,
                         parameters = list(type = "object", properties = list(x = list()))),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t4", description = "d", fun = function(x) x,
                         parameters = list(type = "array")), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("tool", "t5", description = "d", fun = function(x) x,
                         namespace = "1bad"), class = "gptr_error_invalid_spec")
  a = gptr_spec("tool", "look", description = "d", execute = function(input, ctx) "x",
                annotations = list(readOnlyHint = TRUE))
  expect_true(a$annotations$read_only)
  expect_equal(a$exposure, "direct")
  expect_equal(a$execution, "sequential")
  expect_true(a$record)
  dyn = gptr_spec("tool", "dyn", description = "d", execute = function(input, ctx) "x",
                  parameters = function(ctx) list(type = "object"))
  expect_true(is.function(dyn$parameters))
})

test_that("kind-specific rules: skill, command, setting, redaction, alias, risk, ui, preset", {
  local_registry()
  expect_error(gptr_spec("skill", "Bad", description = "d"), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("skill", "ok", description = strrep("x", 1025L)),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("command", "/rows", handler = function(args, ctx) NULL),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("setting", "Panel Size", default = 3L), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("setting", "panel.size", default = 3L)$scope, "both")
  expect_error(gptr_spec("redaction_rule", "anything", pattern = ".*", marker = "X"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("redaction_rule", "broken", pattern = "(", marker = "X"),
               class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("redaction_rule", "mrn", pattern = "MRN[0-9]{8}", marker = "MRN")$profiles,
               c("persist", "context", "stream", "code", "user_data"))
  expect_error(gptr_spec("env_alias", "JEV", aliases = character()),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("child_env", "strict", drop = "("), class = "gptr_error_invalid_spec")
  rows = data.frame(package = "pkg", `function` = "f", level = 3L, check.names = FALSE)
  expect_equal(gptr_spec("risk_rule", "mine", rows = rows)$target, "function")
  rows$level = 7L
  expect_error(gptr_spec("risk_rule", "mine", rows = rows), class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("risk_rule", "cmds", target = "command",
                         rows = data.frame(package = "x", level = 1L)),
               class = "gptr_error_invalid_spec")
  ui = gptr_spec("ui", "yes", has_ui = function() TRUE, select = function(title, choices, ...) 1L)
  expect_equal(ui$permission(list(tool = "r"))$decision, "allow")
  expect_true(is.na(ui$input("Name?")))
  expect_true(ui$questions(list())$cancelled)
  no = gptr_spec("ui", "broken", has_ui = function() TRUE,
                 select = function(title, choices, ...) stop("dialog crashed"))
  expect_equal(no$permission(list(tool = "r"))$decision, "deny")
  expect_equal(gptr_spec("preset", "tiny", tools = c("read", "r"))$preamble, "standard")
  expect_error(gptr_spec("preset", "odd", tools = function(human) "r"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("mcp_server", "old", url = "https://x", type = "sse"),
               class = "gptr_error_invalid_spec")
  expect_error(gptr_spec("mcp_server", "none"), class = "gptr_error_invalid_spec")
  expect_equal(gptr_spec("mcp_server", "off", enabled = FALSE)$enabled, FALSE)
})

test_that("plugin kinds: kind_define() and validators that throw", {
  local_registry()
  kind_define("reviewer", validate = function(spec) spec, resolve = "all", source = "plugin:p")
  expect_true("reviewer" %in% kind_names())
  expect_equal(gptr_spec("reviewer", "stats", focus = "statistics")$focus, "statistics")
  expect_error(kind_define("reviewer", validate = identity, source = "plugin:other"),
               class = "gptr_error_invalid_spec")
  expect_error(kind_define("Bad Kind", validate = identity), class = "gptr_error_invalid_argument")
  kind_define("strict", validate = kind_user_validate(function(spec) stop("no")),
              source = "plugin:p")
  err = expect_error(gptr_spec("strict", "a"), class = "gptr_error_invalid_spec")
  expect_match(err$problem, "no", fixed = TRUE)
  kind_define("lazy_bad", validate = kind_user_validate(function(spec) "not a list"),
              source = "plugin:p")
  expect_error(gptr_spec("lazy_bad", "a"), class = "gptr_error_invalid_spec")
})

test_that("format() shows fields and never function bodies", {
  local_registry()
  s = gptr_spec("command", "hello", handler = function(args, ctx) "secret-body-text",
                description = "Say hi")
  out = format(s)
  expect_equal(out[[1]], "<gptr_command hello>")
  expect_true("  handler: <fn>" %in% out)
  expect_true("  description: Say hi" %in% out)
  expect_false(any(grepl("secret-body-text", out, fixed = TRUE)))
  expect_output(print(s), "<gptr_command hello>", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-specs")'`
Expected: errors such as `could not find function "registry_env"`, `could not find function "ext_session_id"` and `could not find function "registry_swap"`, until testthat stops with `Maximum number of failures exceeded; quitting.`

- [ ] **Step 3: Write the implementation**

Create `R/ext-registry.R`:

```r
# ext-registry.R -- the registry keyed by (kind, name) with ranks, filters, diagnostics and a
# generation counter (contract 5.5, 7.2, 10.1; architecture 5.10, 11.1). Adapted from the verified
# G1 prototype (report G1 5.1) with its verification-log fixes: every regex on a registration or
# dispatch path uses perl = TRUE (row 9), overrides are per record (IC-69), filters are applied at
# resolution time (G1 pitfall 8), and no binding is ever locked (IC-26, rule R5).

#' A fresh registry environment holding all P02 state (contract 5.13 `gptr_registry_env`)
#'
#' `recs` maps record ids to records (contract 5.5); `by_kind`, `by_key` and `hooks` index them;
#' `exts` holds one environment per loaded extension and `states` the `gptr$state` environments;
#' `runs` and `executing` mirror the active runs and executing tools seen through ev_dispatch();
#' `grants` holds one-shot approvals of control exports (IC-53); `builtins_loaded` names the
#' built-ins already loaded into this registry and `watched` the packages whose unload is watched;
#' `version` counts changes that can alter gptr_registry() and `listing` caches its full listing.
#' @noRd
registry_new = function() {
  reg = new.env(parent = emptyenv())
  reg$recs = new.env(parent = emptyenv())
  reg$by_kind = new.env(parent = emptyenv())
  reg$by_key = new.env(parent = emptyenv())
  reg$hooks = new.env(parent = emptyenv())
  reg$exts = new.env(parent = emptyenv())
  reg$states = new.env(parent = emptyenv())
  reg$diag = new.env(parent = emptyenv())
  reg$diag$rows = list()
  reg$kinds = kinds_new()
  reg$filters = list(user = character(), project = character(), session = character())
  reg$eff = character()
  reg$runs = character()
  reg$executing = character()
  reg$grants = list()
  reg$builtins_loaded = character()
  reg$watched = character()
  reg$generation = 1L
  reg$seq = 0L
  reg$ext_seq = 0L
  reg$version = 0L
  reg$listing = NULL
  reg$listing_key = NULL
  reg$current_ext = NULL
  reg$ctx0 = NULL
  class(reg) = "gptr_registry_env"
  reg
}

#' Note a change that can alter gptr_registry() (records, filters, kinds); the cached listing
#' is rebuilt on its next call
#' @noRd
registry_touch = function(reg = registry_env()) {
  reg$version = reg$version + 1L
  invisible(NULL)
}

#' Make `reg` the process registry and point the P02 fields of `the` at it (contract 7.0)
#' @noRd
registry_bind = function(reg) {
  the$registry = reg
  the$kinds = reg$kinds
  the$hooks = reg$hooks
  the$diagnostics = reg$diag
  invisible(reg)
}

#' The process registry, created on first use
#' @noRd
registry_env = function() {
  reg = the$registry
  if (is.null(reg)) {
    reg = registry_new()
    registry_bind(reg)
  }
  reg
}

#' A scratch registry holding only the built-in kinds (gptr_check() and tests)
#' @noRd
registry_scratch = function() registry_new()

#' Swap the process registry; returns the previous one invisibly
#' @noRd
registry_swap = function(reg) {
  old = registry_env()
  registry_bind(reg)
  invisible(old)
}

#' The session id of a session object (anything with an `id` string), an id string, or NULL
#' @noRd
ext_session_id = function(session) {
  if (is.null(session)) return(NULL)
  if (is.character(session) && length(session) == 1L && !is.na(session)) return(session)
  if (!is.environment(session) && !is.list(session)) return(NULL)
  id = tryCatch(session$id, error = function(e) NULL)
  if (is.character(id) && length(id) == 1L && !is.na(id)) id else NULL
}
```

Create `R/ext-specs.R`:

```r
# ext-specs.R -- the kind table, the spec engine and its validators (contract 5.4, 7.2, 10.2).
# 37 kinds are defined here: architecture 11.1 minus `interpreter` (P22 adds it through the `kind`
# kind), plus route, preset, risk_rule, service, renderer, search_source, store and evaluator
# (IC-02, IC-34, IC-69). Validators accept unknown fields (forward compatibility) and reject wrong
# types of known fields with gptr_error_invalid_spec naming the field (contract 10.2). Fields are
# read with [[ ]] so that a missing field never partially matches another one.

#' The extension API version (contract 10.9)
#' @noRd
ext_api_version = "1.0"

# ---- validation helpers -----------------------------------------------------------------------

#' Signal gptr_error_invalid_spec for one field of a spec
#' @noRd
spec_abort = function(spec, field, problem) {
  kind = spec[["kind"]]
  name = spec[["name"]]
  kind = if (is.character(kind) && length(kind) == 1L && !is.na(kind)) kind else "?"
  name = if (is.character(name) && length(name) == 1L && !is.na(name)) name else "?"
  gptr_abort(paste0("Invalid ", kind, " spec '", name, "': field '", field, "' ", problem, "."),
             "invalid_spec", kind = kind, name = name, field = field, problem = problem)
}

#' A field rule of a kind: `type` is one type or several joined with "|"
#' @noRd
kind_field = function(type, null = TRUE, default = NULL, values = NULL, args = NULL) {
  list(type = type, null = null, default = default, values = values, args = args)
}

#' Does function `f` accept the positional arguments `args`?
#' @noRd
spec_fn_accepts = function(f, args) {
  if (is.null(args)) return(TRUE)
  fa = names(formals(args(f)))
  "..." %in% fa || length(fa) >= length(args)
}

#' Is value `v` of the rule type `type`?
#' @noRd
spec_field_ok = function(v, type, rule) {
  switch(type,
    chr1 = is.character(v) && length(v) == 1L && !is.na(v),
    chrna = is.character(v) && length(v) == 1L,
    chr = is.character(v) && !anyNA(v),
    lgl1 = is.logical(v) && length(v) == 1L && !is.na(v),
    nlgl = is.logical(v) && !anyNA(v) && (!length(v) || !is.null(names(v))),
    num1 = is.numeric(v) && length(v) == 1L && !is.na(v),
    numna = length(v) == 1L && (is.numeric(v) || (is.logical(v) && is.na(v))),
    int1 = is.numeric(v) && length(v) == 1L && !is.na(v) && v == round(v),
    enum = is.character(v) && length(v) == 1L && !is.na(v) && v %in% rule$values,
    enums = is.character(v) && !anyNA(v) && all(v %in% rule$values),
    fn = is.function(v) && spec_fn_accepts(v, rule$args),
    list = is.list(v) && !is.data.frame(v),
    nlist = is.list(v) && !is.data.frame(v) &&
      (!length(v) || (!is.null(names(v)) && all(nzchar(names(v))))),
    df = is.data.frame(v),
    ref = (is.character(v) && !anyNA(v)) || is.name(v) || is.call(v) || inherits(v, "gptr_spec"),
    any = TRUE,
    FALSE
  )
}

#' Problem text for a failed rule
#' @noRd
spec_field_problem = function(rule) {
  one = function(type) {
    fn_text = if (is.null(rule$args)) {
      "a function"
    } else {
      paste0("a function accepting (", paste(rule$args, collapse = ", "), ")")
    }
    switch(type,
      chr1 = "a string", chrna = "a string or NA", chr = "a character vector",
      lgl1 = "TRUE or FALSE", nlgl = "a named logical vector", num1 = "a number",
      numna = "a number or NA", int1 = "a whole number",
      enum = paste0("one of ", paste(rule$values, collapse = ", ")),
      enums = paste0("a subset of ", paste(rule$values, collapse = ", ")), fn = fn_text,
      list = "a list", nlist = "a named list", df = "a data frame",
      ref = "a string, a bare identifier or a spec",
      "valid"
    )
  }
  types = strsplit(rule$type, "|", fixed = TRUE)[[1]]
  paste0("must be ", paste(vapply(types, one, ""), collapse = " or "))
}

#' Check and normalise one field (whole numbers of an int1 rule become integers)
#' @noRd
spec_field_check = function(spec, field, v, rule) {
  types = strsplit(rule$type, "|", fixed = TRUE)[[1]]
  ok = vapply(types, function(t) spec_field_ok(v, t, rule), NA)
  if (!any(ok)) spec_abort(spec, field, spec_field_problem(rule))
  if (identical(types[ok][[1]], "int1")) v = as.integer(v)
  v
}

#' Validate a spec against named field rules, then an optional kind-specific check
#' @noRd
spec_validate = function(spec, rules, check = NULL) {
  for (field in names(rules)) {
    rule = rules[[field]]
    v = spec[[field]]
    if (is.null(v)) {
      if (!is.null(rule$default)) {
        spec[[field]] = rule$default
      } else if (!isTRUE(rule$null)) {
        spec_abort(spec, field, "is required")
      }
      next
    }
    spec[[field]] = spec_field_check(spec, field, v, rule)
  }
  if (!is.null(check)) spec = check(spec)
  spec
}

#' Does a PCRE pattern compile?
#' @noRd
spec_regex_ok = function(pattern) {
  isTRUE(tryCatch({
    grepl(pattern, "", perl = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE))
}

# ---- tool helpers (contract 6.8, 9.1) -----------------------------------------------------------

#' A JSON Schema derived from a function's formals (all strings; required without a default)
#' @noRd
spec_schema_from_formals = function(fun) {
  fa = formals(args(fun))
  fa = fa[names(fa) != "..."]
  props = lapply(names(fa), function(n) list(type = "string"))
  names(props) = names(fa)
  if (!length(props)) props = json_obj()
  req = names(fa)[vapply(fa, function(d) identical(d, quote(expr = )), NA)]
  out = list(type = "object", properties = props)
  if (length(req)) out$required = I(req)
  out
}

#' MCP annotation names mapped to gptr's (contract 9.1)
#' @noRd
spec_annotations = function(a) {
  map = c(readOnlyHint = "read_only", destructiveHint = "destructive",
          idempotentHint = "idempotent", openWorldHint = "open_world")
  if (!length(a)) return(a)
  hit = names(a) %in% names(map)
  names(a)[hit] = map[names(a)[hit]]
  a
}

#' The execute() generated for a direct tool that has only `fun` (contract 6.8): calls `fun`
#' with the validated input and returns its printed value within `output_tokens`
#' @noRd
spec_tool_execute = function(fun, output_tokens) {
  force(fun)
  force(output_tokens)
  function(input, ctx) {
    value = do.call(fun, as.list(input))
    lines = utils::capture.output(print(value))
    tr = truncate_output(lines, output_tokens %||% gptr_opt("r_output_tokens"))
    res = gptr_tool_result(tr$text, value = value)
    res$truncated = isTRUE(tr$truncated)
    res["out_id"] = list(tr$out_id)
    res["spill"] = list(tr$spill)
    res
  }
}

#' The fun() generated for an `r` member that has only `execute` (contract 6.8): formals from
#' the schema (required properties first, optional ones default NULL); an error result becomes
#' gptr_error_tool; the result's `value` (else its text) is returned
#' @noRd
spec_tool_fun = function(execute, parameters, name) {
  force(execute)
  force(name)
  if (!is.list(parameters)) {
    return(function(...) {
      res = as_tool_result(execute(list(...), ctx_default(NULL)))
      if (isTRUE(res$is_error)) gptr_abort(format(res), "tool", tool = name, status = "error")
      if (is.null(res$value)) format(res) else res$value
    })
  }
  props = names(parameters[["properties"]])
  req = as.character(unlist(parameters[["required"]]))
  req = req[req %in% props]
  props = c(req, setdiff(props, req))
  f = function() {
    input = list()
    for (nm in names(formals(sys.function()))) {
      v = eval(as.name(nm))
      if (!is.null(v)) input[[nm]] = v
    }
    res = as_tool_result(execute(input, ctx_default(NULL)))
    if (isTRUE(res$is_error)) gptr_abort(format(res), "tool", tool = name, status = "error")
    if (is.null(res$value)) format(res) else res$value
  }
  fmls = rep(list(NULL), length(props))
  names(fmls) = props
  for (p in req) fmls[p] = list(quote(expr = ))
  formals(f) = fmls
  f
}

#' The permission() method built from select() for UI backends without one (contract 10.2):
#' "Yes" allows; any other answer, a cancelled dialog or a failing dialog denies
#' @noRd
spec_ui_permission = function(select) {
  force(select)
  function(request) {
    tool = if (is.character(request[["tool"]])) request[["tool"]][[1]] else "this tool"
    i = tryCatch(select(paste0("Allow ", tool, "?"), c("Yes", "No")),
                 error = function(e) NA_integer_)
    ok = identical(suppressWarnings(as.integer(i)), 1L)
    list(decision = if (ok) "allow" else "deny", remember = NULL, feedback = NULL)
  }
}

# ---- kind-specific checks ------------------------------------------------------------------------

#' @noRd
kind_check_provider = function(spec) {
  if (is.null(spec[["id"]])) spec$id = spec[["name"]]
  if (!identical(spec[["id"]], spec[["name"]])) spec_abort(spec, "id", "must equal the spec name")
  if (!grepl("^[a-z0-9][a-z0-9-]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "id", "must match ^[a-z0-9][a-z0-9-]*$")
  }
  for (m in spec[["models"]]) {
    if (!is.list(m) || !is.character(m[["id"]]) || length(m[["id"]]) != 1L) {
      spec_abort(spec, "models", "must be a list of model records, each with an `id` string")
    }
  }
  for (h in spec[["headers"]]) {
    if (!is.character(h) || length(h) != 1L) spec_abort(spec, "headers", "must hold strings")
  }
  rate = spec[["rate"]]
  for (f in names(rate)) {
    if (!(f %in% c("requests_per_s", "tokens_per_s")) || !is.numeric(rate[[f]])) {
      spec_abort(spec, "rate", "must be list(requests_per_s = <num>, tokens_per_s = <num>)")
    }
  }
  spec
}

#' Adapters are validated per transport (IC-35)
#' @noRd
kind_check_adapter = function(spec) {
  if (is.null(spec[["api"]])) spec$api = spec[["name"]]
  if (!identical(spec[["api"]], spec[["name"]])) spec_abort(spec, "api", "must equal the spec name")
  transport = spec[["transport"]]
  cl = spec[["classify"]]
  if (!is.null(cl)) {
    need = if (identical(transport, "inprocess")) "run" else c("build", "parse")
    for (f in need) {
      if (!is.function(cl[[f]])) spec_abort(spec, "classify", paste0("needs a `", f, "` function"))
    }
    return(spec)
  }
  need = if (identical(transport, "inprocess")) "stream" else c("build", "parse")
  for (f in need) {
    if (!is.function(spec[[f]])) {
      spec_abort(spec, f, paste0("is required for transport ", transport))
    }
  }
  spec
}

#' Model specs are keyed "<provider>/<id>"
#' @noRd
kind_check_model = function(spec) {
  name = spec[["name"]]
  parts = regmatches(name, regexpr("/", name, fixed = TRUE), invert = TRUE)[[1]]
  if (length(parts) != 2L || !nzchar(parts[[1]]) || !nzchar(parts[[2]])) {
    spec_abort(spec, "name", "must be <provider>/<id>")
  }
  if (is.null(spec[["provider"]])) spec$provider = parts[[1]]
  if (is.null(spec[["id"]])) spec$id = parts[[2]]
  if (is.null(spec[["ref"]])) spec$ref = name
  if (!identical(paste0(spec[["provider"]], "/", spec[["id"]]), name)) {
    spec_abort(spec, "id", "must agree with the spec name <provider>/<id>")
  }
  spec
}

#' @noRd
kind_check_router = function(spec) {
  if (spec[["timeout"]] <= 0) spec_abort(spec, "timeout", "must be positive")
  spec
}

#' Tools: name rule, execute or fun, schema from formals, generated execute or fun (contract 6.8)
#' @noRd
kind_check_tool = function(spec) {
  if (!grepl("^[a-zA-Z0-9_-]{1,64}$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-zA-Z0-9_-]{1,64}$")
  }
  fun = spec[["fun"]]
  if (is.null(spec[["execute"]]) && is.null(fun)) {
    spec_abort(spec, "execute", "or `fun` is required")
  }
  ns = spec[["namespace"]]
  if (!is.null(ns) && !grepl("^[A-Za-z][A-Za-z0-9_.]*$", ns, perl = TRUE)) {
    spec_abort(spec, "namespace", "must be an R-style name")
  }
  if (is.null(spec[["parameters"]])) {
    spec$parameters = if (is.function(fun)) {
      spec_schema_from_formals(fun)
    } else {
      list(type = "object", properties = json_obj())
    }
  }
  params = spec[["parameters"]]
  if (is.list(params) && !identical(params[["type"]], "object")) {
    spec_abort(spec, "parameters", "must be a JSON Schema with type \"object\"")
  }
  if (is.function(fun) && is.list(params)) {
    fa = formals(args(fun))
    props = names(params[["properties"]])
    if (!("..." %in% names(fa)) && !all(props %in% names(fa))) {
      spec_abort(spec, "fun", "must have formals matching the schema properties")
    }
    no_default = names(fa)[vapply(fa, function(d) identical(d, quote(expr = )), NA)]
    if (!all(setdiff(no_default, "...") %in% props)) {
      spec_abort(spec, "fun", "has formals without defaults that the schema does not define")
    }
  }
  spec$annotations = spec_annotations(spec[["annotations"]])
  if (is.null(spec[["execute"]]) && identical(spec[["exposure"]], "direct")) {
    spec$execute = spec_tool_execute(fun, spec[["output_tokens"]])
  }
  if (is.null(fun) && identical(spec[["exposure"]], "r")) {
    spec$fun = spec_tool_fun(spec[["execute"]], params, spec[["name"]])
  }
  spec
}

#' MCP servers (contract 11.7): stdio `command` or HTTP `url`; "sse" is refused
#' @noRd
kind_check_mcp_server = function(spec) {
  if (identical(spec[["type"]], "sse")) {
    spec_abort(spec, "type", "'sse' is not supported; use the server's streamable HTTP url")
  }
  if (!isFALSE(spec[["enabled"]]) && (is.null(spec[["command"]]) == is.null(spec[["url"]]))) {
    spec_abort(spec, "command", "or `url` is required (exactly one of them)")
  }
  spec
}

#' Skills (contract 11.13): the name is the directory name
#' @noRd
kind_check_skill = function(spec) {
  if (!grepl("^[a-z0-9][a-z0-9-]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-z0-9][a-z0-9-]*$")
  }
  if (nchar(spec[["description"]], type = "chars") > 1024L) {
    spec_abort(spec, "description", "must be at most 1,024 characters")
  }
  spec
}

#' @noRd
kind_check_command = function(spec) {
  if (!grepl("^[^/[:space:]][^[:space:]]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must not start with '/' or contain spaces")
  }
  spec
}

#' Hooks subscribe to a catalogued event or a "<plugin>:<topic>" channel
#' @noRd
kind_check_hook = function(spec) {
  ev = spec[["event"]]
  if (!(ev %in% ev_table$event) && !ev_is_channel(ev)) {
    hint = ev_hint(ev)
    extra = if (is.null(hint)) "" else paste0(" (", hint, ")")
    spec_abort(spec, "event", paste0("is not a gptr event", extra))
  }
  spec
}

#' @noRd
kind_check_context_block = function(spec) {
  if (spec[["budget"]] < 1L) spec_abort(spec, "budget", "must be at least 1")
  spec
}

#' @noRd
kind_check_prompt_section = function(spec) {
  if (is.function(spec[["text"]]) && !spec_fn_accepts(spec[["text"]], "ctx")) {
    spec_abort(spec, "text", "must be a string or a function(ctx)")
  }
  if (spec[["budget"]] < 1L) spec_abort(spec, "budget", "must be at least 1")
  spec
}

#' UI backends: absent methods get fail-closed defaults (a missing dialog is never an approval)
#' @noRd
kind_check_ui = function(spec) {
  if (is.null(spec[["input"]])) {
    spec$input = function(prompt, default = "", secret = FALSE) NA_character_
  }
  if (is.null(spec[["questions"]])) {
    spec$questions = function(qs) list(answers = json_obj(), cancelled = TRUE)
  }
  if (is.null(spec[["notify"]])) spec$notify = function(text, level = "info") invisible(NULL)
  if (is.null(spec[["permission"]])) spec$permission = spec_ui_permission(spec[["select"]])
  spec
}

#' Settings are dotted lower-case keys such as subagents.max_depth
#' @noRd
kind_check_setting = function(spec) {
  if (!grepl("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must be a dotted lower-case key such as subagents.max_depth")
  }
  spec
}

#' Redaction rules compile and never match their own marker
#' @noRd
kind_check_redaction_rule = function(spec) {
  pattern = spec[["pattern"]]
  if (!spec_regex_ok(pattern)) spec_abort(spec, "pattern", "must be a valid PCRE pattern")
  if (grepl(pattern, paste0("[secret:", spec[["marker"]], "]"), perl = TRUE)) {
    spec_abort(spec, "pattern", "must not match its own marker")
  }
  spec
}

#' @noRd
kind_check_env_alias = function(spec) {
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must be the canonical environment-variable name")
  }
  if (!length(spec[["aliases"]])) spec_abort(spec, "aliases", "must name at least one alias")
  spec
}

#' @noRd
kind_check_child_env = function(spec) {
  for (d in spec[["drop"]]) {
    if (!spec_regex_ok(d)) spec_abort(spec, "drop", "must hold valid PCRE patterns")
  }
  spec
}

#' Agent names that equal a session accessor are refused (IC-71): children stay reachable by name
#' @noRd
kind_check_agent = function(spec) {
  accessors = c("text", "value", "values", "usage", "cost", "history", "messages", "model", "mode",
                "status", "reason", "id", "kind", "file", "turns", "envir", "children", "ext",
                "plan", "last_rewind", "editor_text")
  if (spec[["name"]] %in% accessors) {
    spec_abort(spec, "name", "equals a session accessor name; choose another agent name")
  }
  spec
}

#' @noRd
kind_check_kind = function(spec) {
  if (!grepl("^[a-z][a-z0-9_]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-z][a-z0-9_]*$")
  }
  spec
}

#' @noRd
kind_check_preset = function(spec) {
  if (is.function(spec[["tools"]]) && !spec_fn_accepts(spec[["tools"]], c("human", "model"))) {
    spec_abort(spec, "tools", "must be a character vector or a function(human, model, mode)")
  }
  if (is.function(spec[["sections"]]) && !spec_fn_accepts(spec[["sections"]], "name")) {
    spec_abort(spec, "sections", "must be a named logical vector or a function(name)")
  }
  spec
}

#' Risk rules: rows of risk-functions.csv (target "function") or risk-commands.csv ("command")
#' @noRd
kind_check_risk_rule = function(spec) {
  rows = spec[["rows"]]
  need = if (identical(spec[["target"]], "command")) {
    c("command", "level")
  } else {
    c("package", "function", "level")
  }
  miss = setdiff(need, names(rows))
  if (length(miss)) {
    spec_abort(spec, "rows", paste0("needs columns ", paste(miss, collapse = ", ")))
  }
  lv = rows[["level"]]
  if (!is.numeric(lv) || anyNA(lv) || any(lv != round(lv)) || any(lv < 0 | lv > 4)) {
    spec_abort(spec, "rows", "needs whole `level` values from 0 to 4")
  }
  spec
}

# ---- the kind table ----------------------------------------------------------------------------

#' A kind definition record
#' @noRd
kind_record = function(name, validate, resolve, fields, order_field, experimental, source) {
  list(name = name, validate = validate, resolve = resolve, fields = fields,
       order_field = order_field, experimental = experimental, source = source,
       record = NULL, staged = NULL)
}

#' A fresh kind table holding the 37 built-in kinds
#' @noRd
kinds_new = function() {
  k = new.env(parent = emptyenv())
  kinds_install(k)
  k
}

#' The kind table of the current registry
#' @noRd
kinds_env = function() registry_env()$kinds

#' Install the built-in kinds into a kind table (contract 10.2 rows 1-5 and 7-38)
#' @noRd
kinds_install = function(k) {
  def = function(name, rules, check = NULL, resolve = "first", order_field = NULL,
                 experimental = FALSE) {
    force(rules)
    force(check)
    validate = function(spec) spec_validate(spec, rules, check)
    rec = kind_record(name, validate, resolve, names(rules), order_field, experimental,
                      "builtin")
    assign(name, rec, envir = k)
  }
  f = kind_field
  fn = function(..., null = TRUE) kind_field("fn", null = null, args = c(...))
  req_fn = function(...) kind_field("fn", null = FALSE, args = c(...))
  exposures = c("direct", "r", "deferred", "hidden")
  transports = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess")
  profiles = c("persist", "context", "stream", "code", "user_data")
  def("provider", list(
    id = f("chr1"), api = f("chr1", null = FALSE), base_url = f("chr1"),
    auth = f("chr|fn"), models = f("list"), compat = f("nlist", default = list()),
    type = f("enum", default = "chat", values = c("chat", "classifier", "cli")),
    headers = f("nlist", default = list()), discover = fn(), status = fn(),
    aliases = f("chr", default = character()), local = f("lgl1", default = FALSE),
    offline = f("lgl1", default = FALSE), rate = f("nlist")
  ), kind_check_provider)
  def("adapter", list(
    api = f("chr1"), transport = f("enum", null = FALSE, values = transports),
    build = fn("model", "context", "opts"), parse = fn("model", "opts"),
    stream = fn("model", "context", "opts"), classify = f("nlist"),
    capabilities = f("nlist", default = list())
  ), kind_check_adapter)
  def("model", list(
    ref = f("chr1"), provider = f("chr1"), id = f("chr1"), label = f("chr1"),
    family = f("chr1"), api = f("chr1"),
    type = f("enum", values = c("chat", "classifier", "cli")),
    release_date = f("chrna|numna"), context = f("numna"), max_output = f("numna"),
    reasoning = f("lgl1"), thinking_levels = f("chr"), thinking = f("chr1"), input = f("chr"),
    tool_call = f("lgl1"), structured_output = f("lgl1"), prices = f("df"),
    cache_min = f("numna"), capabilities = f("nlist"), aliases = f("chr"),
    status = f("enum", values = c("active", "deprecated", "preview")), local = f("lgl1")
  ), kind_check_model)
  def("router", list(
    route = req_fn("request", "ctx"), description = f("chr1"), timeout = f("num1", default = 2)
  ), kind_check_router)
  def("tool", list(
    description = f("chr1", null = FALSE), parameters = f("list|fn"),
    execute = fn("input", "ctx"), fun = fn(),
    exposure = f("enum", default = "direct", values = exposures), namespace = f("chr1"),
    execution = f("enum", default = "sequential", values = c("sequential", "concurrent")),
    risk = fn("input", "ctx"), snippet = f("chr1"), guidelines = f("chr"),
    signature = f("chr1"), output_tokens = f("int1"), record = f("lgl1", default = TRUE),
    render = fn("call", "result", "width"), available = fn("ctx"),
    annotations = f("nlist", default = list())
  ), kind_check_tool)
  def("mcp_server", list(
    command = f("chr1"), url = f("chr1"), type = f("chr1"), args = f("chr|list"),
    env = f("nlist|chr"), headers = f("nlist|chr"), cwd = f("chr1"), timeout = f("num1"),
    protocol = f("enum", values = c("auto", "modern", "legacy")),
    exposure = f("enum", values = exposures), toolExposure = f("nlist|chr"),
    enabled = f("lgl1"), trusted = f("lgl1"), oauth = f("nlist"), transport = f("chr1"),
    source = f("chr1"), also_in = f("chr")
  ), kind_check_mcp_server)
  def("skill", list(
    description = f("chr1", null = FALSE), path = f("chr1"), dir = f("chr1"),
    source = f("chr1"), disable_model_invocation = f("lgl1", default = FALSE),
    allowed_tools = f("chr"), tokens = f("num1")
  ), kind_check_skill)
  def("prompt_template", list(
    text = f("chr1", null = FALSE), description = f("chr1"), argument_hint = f("chr1"),
    source = f("chr1")
  ))
  def("command", list(
    handler = req_fn("args", "ctx"), description = f("chr1"), complete = fn("prefix", "ctx")
  ), kind_check_command)
  def("hook", list(
    event = f("chr1", null = FALSE), handler = req_fn("event", "ctx"), matcher = f("chr1|fn")
  ), kind_check_hook, resolve = "all")
  def("policy", list(
    check = req_fn("call", "ctx"), description = f("chr1"), order = f("int1", default = 500L)
  ), resolve = "all", order_field = "order")
  def("context_block", list(
    provide = req_fn("ctx", "budget"),
    placement = f("enum", default = "turn", values = c("turn", "first", "both")),
    authority = f("enum", default = "data", values = c("data", "operator")),
    budget = f("int1", default = 300L), order = f("int1", default = 650L)
  ), kind_check_context_block, resolve = "all", order_field = "order")
  def("prompt_section", list(
    text = f("chr1|fn", null = FALSE), tier = f("enum", default = "T0", values = c("T0", "T1")),
    order = f("int1", default = 500L), budget = f("int1", default = 300L), parent = f("chr1")
  ), kind_check_prompt_section, resolve = "all", order_field = "order")
  def("compactor", list(should = req_fn("session", "ctx"), compact = req_fn("session", "ctx")))
  def("cache_policy", list(plan = req_fn("parts", "caps", "session")))
  def("estimator", list(
    estimate = req_fn("x", "class"), calibrate = fn("state", "estimated", "reported")
  ))
  def("doc_format", list(
    ext = f("chr", null = FALSE), locate = req_fn("text", "site"),
    render = req_fn("block", "site"), upsert = req_fn("text", "site", "lines", "block_id"),
    inert = req_fn("lines")
  ))
  def("artifact_type", list(
    build = req_fn("id", "dir", "data", "ctx"), check = req_fn("dir", "ctx"),
    launch = req_fn("version_dir", "ctx"), stop = req_fn("handle")
  ), experimental = TRUE)
  def("backend", list(
    start = req_fn("spec", "ctx"), poll = fn(), cancel = req_fn("handle"),
    capabilities = f("nlist", default = list())
  ))
  def("agent", list(
    description = f("chr1"), model = f("ref"), tools = f("chr|list"), skills = f("ref"),
    system = f("chr1"), backend = f("chr1", default = "auto"),
    preset = f("chr1", default = "minimal"), max_turns = f("int1"),
    mode = f("enum", values = c("plan", "manual", "edits", "auto")), objects = f("chr"),
    export = f("chr"), returns = f("list"), file = f("chr1")
  ), kind_check_agent)
  def("ui", list(
    has_ui = req_fn(), select = req_fn(), input = fn(), questions = fn(), notify = fn(),
    permission = fn("request")
  ), kind_check_ui)
  def("frontend", list(run = req_fn("session")), experimental = TRUE)
  def("setting", list(
    default = f("any"), description = f("chr1"),
    scope = f("enum", default = "both", values = c("both", "user")),
    validate = fn("value"), tighten = f("chr")
  ), kind_check_setting)
  def("secret_source", list(
    resolve = req_fn("name", "ctx"), list = req_fn("ctx"), store = fn(), forget = fn()
  ), resolve = "all")
  def("redaction_rule", list(
    pattern = f("chr1", null = FALSE), anchor = f("chr"), marker = f("chr1", null = FALSE),
    profiles = f("enums", default = profiles, values = profiles)
  ), kind_check_redaction_rule, resolve = "all")
  def("env_alias", list(aliases = f("chr", null = FALSE)), kind_check_env_alias,
      resolve = "all")
  def("child_env", list(
    base = f("enum", default = "inherit", values = c("inherit", "allowlist")),
    keep = f("chr", default = character()), drop = f("chr", default = character()),
    set = f("nlist|chr"), billing = f("nlist")
  ), kind_check_child_env)
  def("checkpointer", list(
    scope = f("enum", null = FALSE, values = c("objects", "files", "state", "artifacts", "other")),
    before = req_fn("call", "ctx"), after = req_fn("call", "ctx", "token"),
    undo = req_fn("fragment", "ctx", "force"), redo = req_fn("fragment", "ctx", "force"),
    prune = fn("live_keys", "ctx"), describe = fn("fragment")
  ), resolve = "all", experimental = TRUE)
  def("kind", list(
    validate = req_fn("spec"), resolve = f("enum", default = "first", values = c("first", "all")),
    fields = f("chr", default = character()), order_field = f("chr1"),
    experimental = f("lgl1", default = TRUE)
  ), kind_check_kind)
  def("route", list(
    order = f("num1", null = FALSE), match = req_fn("call"), run = req_fn("call"),
    description = f("chr1")
  ), resolve = "all", order_field = "order", experimental = TRUE)
  def("preset", list(
    tools = f("chr|fn", null = FALSE), sections = f("nlgl|fn"),
    preamble = f("enum", default = "standard", values = c("standard", "short"))
  ), kind_check_preset)
  def("risk_rule", list(
    rows = f("df", null = FALSE),
    target = f("enum", default = "function", values = c("function", "command")),
    lower = f("lgl1", default = FALSE)
  ), kind_check_risk_rule, resolve = "all")
  def("service", list(fun = req_fn()), experimental = TRUE)
  def("renderer", list(
    render = req_fn("entry", "width", "ctx"), doc = fn("entry", "format")
  ), experimental = TRUE)
  def("search_source", list(docs = req_fn("ctx")), resolve = "all", experimental = TRUE)
  def("store", list(open = req_fn(), append = req_fn(), read = req_fn(), fork = req_fn()),
      experimental = TRUE)
  def("evaluator", list(eval = req_fn()), experimental = TRUE)
  invisible(k)
}

#' Define a kind (P02's own kinds use kinds_install(); plugins and P22 go through the `kind`
#' kind, which calls this; contract 7.2)
#' @noRd
kind_define = function(name, validate, resolve = c("first", "all"), fields = character(),
                       order_field = NULL, experimental = FALSE, source = "builtin") {
  check_string(name, "name")
  check_function(validate, "validate")
  resolve = check_choice(resolve, c("first", "all"), "resolve")
  check_strings(fields, "fields")
  check_string(order_field, "order_field", null = TRUE)
  check_flag(experimental, "experimental")
  check_string(source, "source")
  if (!grepl("^[a-z][a-z0-9_]*$", name, perl = TRUE)) {
    gptr_abort("A kind name must match ^[a-z][a-z0-9_]*$.", "invalid_argument", arg = "name",
               expected = "a lower-case kind name")
  }
  k = kinds_env()
  old = get0(name, envir = k, inherits = FALSE)
  if (!is.null(old) && !identical(old$source, source)) {
    gptr_abort(paste0("Kind '", name, "' is already defined by ", old$source, "."),
               "invalid_spec", kind = "kind", name = name, field = "name",
               problem = "is already defined")
  }
  rec = kind_record(name, validate, resolve, fields, order_field, experimental, source)
  assign(name, rec, envir = k)
  registry_touch()
  invisible(name)
}

#' The definition of a kind, or gptr_error_unknown_kind (a gptr_error_invalid_spec)
#' @noRd
kind_get = function(name) {
  ok = is.character(name) && length(name) == 1L && !is.na(name)
  k = if (ok) get0(name, envir = kinds_env(), inherits = FALSE)
  if (is.null(k)) {
    label = if (ok) name else "?"
    gptr_abort(paste0("Unknown capability kind '", label,
                      "'; registered kinds are listed by gptr_api()$features."),
               c("unknown_kind", "invalid_spec"), kind = label, name = "?", field = "kind",
               problem = "is not a registered kind")
  }
  k
}

#' Names of the registered kinds, sorted
#' @noRd
kind_names = function() sort(ls(kinds_env()), method = "radix")

#' Wrap a plugin kind's validate() so that failures become gptr_error_invalid_spec
#' @noRd
kind_user_validate = function(validate) {
  force(validate)
  function(spec) {
    out = tryCatch(validate(spec),
                   gptr_error_invalid_spec = function(e) stop(e),
                   error = function(e) {
                     spec_abort(spec, "(validate)", paste0("was rejected: ", conditionMessage(e)))
                   })
    if (!is.list(out)) spec_abort(spec, "(validate)", "must return the spec")
    out
  }
}

# ---- the spec engine ---------------------------------------------------------------------------

#' Finish a spec: common checks, the kind validator, the class (contract 5.4)
#' @noRd
spec_finish = function(spec, k) {
  spec = unclass(spec)
  nms = names(spec)
  if (is.null(nms) || !all(nzchar(nms))) spec_abort(spec, "(unnamed)", "is not allowed")
  if (anyDuplicated(nms)) spec_abort(spec, nms[[anyDuplicated(nms)]], "is given twice")
  nm = spec[["name"]]
  if (!is.character(nm) || length(nm) != 1L || is.na(nm) || !nzchar(nm)) {
    spec_abort(spec, "name", "must be a non-empty string")
  }
  spec$kind = k$name
  if (is.null(spec[["api_version"]])) spec$api_version = ext_api_version
  av = spec[["api_version"]]
  if (!is.character(av) || length(av) != 1L || is.na(av)) {
    spec_abort(spec, "api_version", "must be a version string such as \"1.0\"")
  }
  spec = unclass(k$validate(spec))
  spec$kind = k$name
  class(spec) = c(paste0("gptr_", k$name), "gptr_spec")
  spec
}

#' Build and validate a spec of a registered kind (the engine behind gptr_spec())
#' @noRd
spec_new = function(kind, name, ...) {
  if (!is.character(kind) || length(kind) != 1L || is.na(kind)) {
    gptr_abort("`kind` must be the name of a registered kind.", "invalid_argument", arg = "kind",
               expected = "a kind name")
  }
  k = kind_get(kind)
  spec_finish(list(kind = kind, name = name, ...), k)
}

#' Build a spec of any registered kind
#'
#' The general constructor behind the eleven spec constructors: it builds a spec of `kind` from its
#' fields and validates it with the kind's validator. Use it for kinds without a constructor
#' (`env_alias`, `setting`, `service`, `preset`, ...) and for kinds defined by plugins. Unknown
#' fields are kept (forward compatibility); a wrong type of a known field is an error naming the
#' field.
#'
#' @param kind The kind name, one of the `kind.<name>` features of [gptr_api()].
#' @param name The record name within the kind.
#' @param ... The kind's fields, named.
#' @return A spec: a list of class `c("gptr_<kind>", "gptr_spec")`.
#' @examples
#' gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
#' gptr_spec("setting", "panel.size", default = 3L, description = "Reviewers per panel")
#' @export
gptr_spec = function(kind, name, ...) spec_new(kind, name, ...)

#' A one-line label of a spec field value (functions are never shown)
#' @noRd
spec_field_label = function(v) {
  if (is.function(v)) return("<fn>")
  if (is.null(v)) return("NULL")
  if (is.environment(v)) return("<env>")
  if (is.data.frame(v)) return(paste0("<data.frame ", nrow(v), " x ", ncol(v), ">"))
  if (is.list(v)) return(paste0("<list of ", length(v), ">"))
  if (is.name(v)) return(as.character(v))
  if (is.call(v)) return("<call>")
  if (is.atomic(v)) {
    x = gsub("[\r\n\t]+", " ", as.character(utils::head(v, 5L)), perl = TRUE)
    x = ifelse(nchar(x) > 60L, paste0(substr(x, 1L, 57L), "..."), x)
    return(paste0(paste(x, collapse = ", "), if (length(v) > 5L) ", ..." else ""))
  }
  paste0("<", class(v)[[1]], ">")
}

#' Format a spec: one header line and one line per non-NULL field; functions show as <fn>
#' @export
#' @noRd
format.gptr_spec = function(x, ...) {
  fields = setdiff(names(x), c("kind", "name"))
  fields = fields[!vapply(fields, function(f) is.null(x[[f]]), NA)]
  c(paste0("<gptr_", x[["kind"]], " ", x[["name"]], ">"),
    unname(vapply(fields, function(f) paste0("  ", f, ": ", spec_field_label(x[[f]])), "")))
}

#' Print a spec
#' @export
#' @noRd
print.gptr_spec = function(x, ...) {
  cat(paste0(format(x), "\n"), sep = "")
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'` (writes `export(gptr_spec)`, `S3method(format,gptr_spec)`, `S3method(print,gptr_spec)` and `man/gptr_spec.Rd`), then `Rscript --vanilla -e 'devtools::test(filter = "ext-specs")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 123 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-registry.R R/ext-specs.R tests/testthat/test-ext-specs.R NAMESPACE man/gptr_spec.Rd
git commit -m "feat(ext): add the registry state, kind table and spec engine"
```

---

### Task 3: Spec constructors and tool results

**Files:**
- Modify: `R/ext-specs.R` (append), `NAMESPACE`, `man/` (generated: `gptr_tool.Rd`, `gptr_provider.Rd`, `gptr_adapter.Rd`, `gptr_router.Rd`, `gptr_hook.Rd`, `gptr_policy.Rd`, `gptr_agent.Rd`, `gptr_command.Rd`, `gptr_prompt_section.Rd`, `gptr_context_block.Rd`, `gptr_backend.Rd`, `gptr_tool_result.Rd`)
- Test: `tests/testthat/test-ext-specs.R` (append)

**Interfaces:**
- Consumes: Task 2 `spec_new()`, `spec_abort()`, `kind_get()`; P01 `block_text(text, signature = NULL)`, `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)`, `check_strings()`, `check_list()`, `check_flag()`, `msg_verbatim()`.
- Produces: the 11 exported constructors with the exact 04 §6.8 / IC-35 signatures (Global Constraints); `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)` -> `structure(list(content, details, is_error, value, spill = NULL, out_id = NULL, truncated = FALSE, terminate = FALSE), class = "gptr_tool_result")` (04 §5.7); `as_tool_result(x)` (a `gptr_tool_result`, a character vector, `list(text, images, value, is_error, details)` or `NULL` -> `"(no output)"`); `format.gptr_tool_result()` (text blocks and `[image]`), `print.gptr_tool_result()` (through `msg_verbatim()`).

Constructors use the first element of a choice vector when the argument is left at its default and hand any other value to the kind validator, so a wrong `exposure` or `placement` is `gptr_error_invalid_spec` naming the field (04 §6.8). `gptr_agent()` keeps `model` and `skills` as the raw expressions `substitute()` returns (IC-34), never forcing them (rule R3); with only a name or a file it loads a definition through the `agent_def.get` service (P17) and otherwise signals `gptr_error_not_available`; that branch calls `ext_service_try()` from Task 7.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ext-specs.R`:

```r
test_that("every example of contract 6.8 runs and returns its class (IC-35)", {
  local_registry()
  specs = list(
    gptr_tool("nrow_of", "Number of rows of a data frame in the session",
              parameters = list(type = "object", required = I("name"),
                                properties = list(name = list(type = "string"))),
              fun = function(name) nrow(get(name, envir = globalenv())), exposure = "r",
              namespace = "demo"),
    gptr_provider("corp", api = "openai-completions", base_url = "https://llm.corp.example/v1",
                  auth = "CORP_LLM_KEY", models = list(list(id = "corp-large", context = 128000))),
    gptr_adapter("echo", transport = "inprocess",
                 stream = function(model, context, opts) {
                   state = new.env()
                   state$done = FALSE
                   function() {
                     if (state$done) return(NULL)
                     state$done = TRUE
                     list(events = list())
                   }
                 }),
    gptr_router("cheapest", route = function(request, ctx) "anthropic/claude-haiku-4-5"),
    gptr_hook("tool_result", function(event, ctx) NULL, matcher = "r"),
    gptr_policy("no_installs", check = function(call, ctx) {
      if (identical(call$name, "r") && grepl("install.packages", call$input$code, fixed = TRUE)) {
        list(decision = "deny", reason = "installs are not allowed here")
      } else {
        NULL
      }
    }),
    gptr_agent("stats", description = "Statistical reviewer", model = "anthropic/claude-opus-5-5",
               skills = "statistics"),
    gptr_command("rows", function(args, ctx) paste("rows:", nrow(mtcars)),
                 description = "Show rows"),
    gptr_prompt_section("house_rules", "Use SI units in every table.", tier = "T1", order = 780L),
    gptr_context_block("lab_notebook", function(ctx, budget) "Experiment 12: cohort B only.",
                       placement = "first", order = 650L),
    gptr_backend("echo", start = function(spec, ctx) NULL, cancel = function(handle) NULL)
  )
  kinds = vapply(specs, function(s) s$kind, "")
  expect_equal(kinds, c("tool", "provider", "adapter", "router", "hook", "policy", "agent",
                        "command", "prompt_section", "context_block", "backend"))
  for (s in specs) expect_s3_class(s, c(paste0("gptr_", s$kind), "gptr_spec"), exact = TRUE)
  expect_equal(specs[[1]]$namespace, "demo")
  expect_true(is.function(specs[[1]]$fun))
  expect_equal(specs[[2]]$auth, "CORP_LLM_KEY")
  expect_equal(specs[[3]]$transport, "inprocess")
  expect_equal(specs[[3]]$stream(NULL, NULL, NULL)(), list(events = list()))
  expect_equal(specs[[4]]$timeout, 2)
  expect_equal(specs[[5]]$name, "tool_result")
  expect_equal(specs[[5]]$matcher, "r")
  expect_equal(specs[[6]]$check(list(name = "r", input = list(code = "install.packages('x')")),
                                NULL)$decision, "deny")
  expect_equal(specs[[8]]$handler("", NULL), "rows: 32")
  expect_equal(specs[[9]]$tier, "T1")
  expect_identical(specs[[9]]$order, 780L)
  expect_equal(specs[[10]]$placement, "first")
})

test_that("constructors pick the first choice and report missing or wrong arguments", {
  local_registry()
  t = gptr_tool("t", "A tool", execute = function(input, ctx) "x")
  expect_equal(t$exposure, "direct")
  expect_equal(t$execution, "sequential")
  expect_equal(gptr_adapter("a", build = function(model, context, opts) NULL,
                            parse = function(model, opts) NULL)$transport, "http_sse")
  expect_equal(gptr_provider("p", api = "x")$type, "chat")
  expect_equal(gptr_prompt_section("s", "text")$tier, "T0")
  expect_equal(gptr_context_block("b", function(ctx, budget) NULL)$placement, "turn")
  expect_equal(gptr_context_block("b", function(ctx, budget) NULL)$authority, "data")
  expect_equal(gptr_agent("a", description = "d")$backend, "auto")
  expect_equal(gptr_agent("a", description = "d")$preset, "minimal")
  err = expect_error(gptr_tool("t"), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "description")
  expect_error(gptr_router("r"), class = "gptr_error_invalid_spec")
  expect_error(gptr_provider("p"), class = "gptr_error_invalid_spec")
  expect_error(gptr_backend("b", start = function(spec, ctx) NULL),
               class = "gptr_error_invalid_spec")
  err = expect_error(gptr_tool("t", "d", execute = function(input, ctx) NULL, exposure = "public"),
                     class = "gptr_error_invalid_spec")
  expect_equal(err$field, "exposure")
  expect_error(gptr_context_block("b", function(ctx, budget) NULL, placement = "system"),
               class = "gptr_error_invalid_spec")
})

test_that("gptr_agent() stores the raw captured expressions (IC-34)", {
  local_registry()
  a = gptr_agent("rev", description = "Reviewer", model = opus, skills = c(stats, plots))
  expect_identical(a$model, quote(opus))
  expect_identical(a$skills, quote(c(stats, plots)))
  b = gptr_agent("rev", description = "Reviewer", model = "anthropic/claude-opus-5-5",
                 mode = "plan", max_turns = 5)
  expect_equal(b$model, "anthropic/claude-opus-5-5")
  expect_identical(b$max_turns, 5L)
  expect_error(gptr_agent(description = "no name"), class = "gptr_error_invalid_spec")
  expect_error(gptr_agent("rev", description = "d", mode = "yolo"),
               class = "gptr_error_invalid_spec")
  err = expect_error(gptr_agent("text", description = "d"), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "name")
})

test_that("gptr_tool_result() builds text, image, details and value", {
  r = gptr_tool_result(c("3 rows", "2 cols"), details = list(n = 3L), value = 3L)
  expect_s3_class(r, "gptr_tool_result")
  expect_named(r, c("content", "details", "is_error", "value", "spill", "out_id", "truncated",
                    "terminate"))
  expect_equal(r$content[[1]]$type, "text")
  expect_equal(r$content[[1]]$text, "3 rows\n2 cols")
  expect_equal(r$value, 3L)
  expect_false(r$is_error)
  expect_false(r$terminate)
  png = withr::local_tempfile(fileext = ".png")
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47, rep(0, 80))), png)
  r = gptr_tool_result("plot", images = list(png, as.raw(c(1, 2, 3))))
  expect_length(r$content, 3L)
  expect_equal(r$content[[2]]$type, "image")
  expect_equal(r$content[[2]]$mime, "image/png")
  expect_equal(r$content[[2]]$source, "file")
  expect_false(grepl("\n", r$content[[2]]$data, fixed = TRUE))
  expect_equal(format(r), "plot\n[image]\n[image]")
  expect_error(gptr_tool_result(images = list(42)), class = "gptr_error_invalid_argument")
  expect_error(gptr_tool_result(details = list(1)), class = "gptr_error_invalid_argument")
  expect_error(gptr_tool_result(is_error = NA), class = "gptr_error_invalid_argument")
  expect_error(gptr_tool_result(text = 1), class = "gptr_error_invalid_argument")
  expect_invisible(print(gptr_tool_result("")))
})

test_that("as_tool_result() normalises the shapes execute() may return (contract 5.7)", {
  expect_equal(format(as_tool_result(NULL)), "(no output)")
  expect_equal(format(as_tool_result(list())), "(no output)")
  expect_equal(format(as_tool_result(c("a", "b"))), "a\nb")
  r = as_tool_result(list(text = "done", value = 1:3, is_error = TRUE))
  expect_true(r$is_error)
  expect_equal(r$value, 1:3)
  expect_equal(format(as_tool_result(list(value = 2))), "(no output)")
  x = gptr_tool_result("same")
  expect_identical(as_tool_result(x), x)
  expect_error(as_tool_result(data.frame(a = 1)), class = "gptr_error_invalid_argument")
  expect_error(as_tool_result(list(text = "x", colour = "red")),
               class = "gptr_error_invalid_argument")
})

test_that("a direct tool with only fun gets an execute() printing the value in budget", {
  local_registry()
  t = gptr_tool("paste2", "Paste two strings", fun = function(a, b = "x") paste(a, b))
  res = t$execute(list(a = "hello", b = "world"), NULL)
  expect_s3_class(res, "gptr_tool_result")
  expect_equal(res$value, "hello world")
  expect_match(format(res), "hello world", fixed = TRUE)
  expect_false(res$truncated)
  big = gptr_tool("seq_of", "A long sequence", fun = function(n) seq_len(as.integer(n)),
                  output_tokens = 50L)
  res = big$execute(list(n = "5000"), NULL)
  expect_true(res$truncated)
  expect_lt(nchar(format(res)), 2000L)
  expect_length(res$value, 5000L)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-specs")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 123 ]`, from errors such as `could not find function "gptr_tool"`, `could not find function "gptr_agent"` and `could not find function "gptr_tool_result"`.

- [ ] **Step 3: Write the implementation**

Append to `R/ext-specs.R`:

```r
# ---- the exported spec constructors (contract 6.8; IC-35) ---------------------------------------

#' The first element of a choice vector when the argument was left at its default; a wrong value
#' is passed on so that the kind validator reports it as gptr_error_invalid_spec
#' @noRd
spec_arg_first = function(x, choices) if (identical(x, choices)) choices[[1]] else x

#' gptr_error_invalid_spec for a required constructor argument that is missing
#' @noRd
spec_missing = function(kind, name, field) {
  label = if (is.character(name) && length(name) == 1L && !is.na(name)) name else "?"
  spec_abort(list(kind = kind, name = label), field, "is required")
}

#' Define a tool
#'
#' A tool is one capability the model can use: declared directly in the request's tool array
#' (`exposure = "direct"`), callable from R code as `peter$<namespace>$<name>()` (`"r"`, one
#' signature line in the prompt), found through `peter$search()` (`"deferred"`) or callable only by
#' gptr code (`"hidden"`). Give `execute` (`function(input, ctx)`, the direct-tool form), `fun` (an
#' R function whose formals match the schema properties, the member form), or both. A direct tool
#' with only `fun` gets a generated `execute` that prints the value within `output_tokens`; an `r`
#' member with only `execute` gets a generated `fun`.
#'
#' @param name Tool name, `^[a-zA-Z0-9_-]{1,64}$`.
#' @param description Model-facing description; direct tools stay under 400 estimated tokens.
#' @param parameters A JSON Schema list with `type = "object"`, a `function(ctx)` evaluated once
#'   when a session freezes its prompt, or `NULL` to derive the schema from `fun`'s formals.
#' @param execute `function(input, ctx)` returning a [gptr_tool_result()], text, a list or `NULL`.
#' @param fun The R-callable form of the tool.
#' @param exposure One of `"direct"`, `"r"`, `"deferred"`, `"hidden"`.
#' @param namespace Namespace of an `r` member (plugins must set it to their package name).
#' @param execution `"sequential"` (tools that evaluate R or write files) or `"concurrent"`.
#' @param risk `function(input, ctx)` returning a risk level, or `NULL`.
#' @param snippet One line shown in the prompt's tool list (direct tools).
#' @param guidelines Bullet lines added to the prompt's rules (direct tools).
#' @param signature Catalog line for `r` members; `NULL` derives it from the schema.
#' @param output_tokens Budget for printed results; `NULL` uses the gptr defaults.
#' @param record Keep calls of this member in recorded code.
#' @param available `function(ctx)` deciding at freeze whether a direct tool is offered.
#' @param annotations Named list: `read_only`, `destructive`, `idempotent`, `open_world`,
#'   `requires_user` (MCP `readOnlyHint`-style names are mapped).
#' @return A spec of class `c("gptr_tool", "gptr_spec")`.
#' @examples
#' gptr_tool("nrow_of", "Number of rows of a data frame in the session",
#'           parameters = list(type = "object", required = I("name"),
#'                             properties = list(name = list(type = "string"))),
#'           fun = function(name) nrow(get(name, envir = globalenv())), exposure = "r",
#'           namespace = "demo")
#' @export
gptr_tool = function(name, description, parameters = NULL, execute = NULL, fun = NULL,
                     exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL,
                     execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL,
                     guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE,
                     available = NULL, annotations = list()) {
  if (missing(description)) spec_missing("tool", name, "description")
  spec_new("tool", name, description = description, parameters = parameters, execute = execute,
           fun = fun, exposure = spec_arg_first(exposure, c("direct", "r", "deferred", "hidden")),
           namespace = namespace,
           execution = spec_arg_first(execution, c("sequential", "concurrent")), risk = risk,
           snippet = snippet, guidelines = guidelines, signature = signature,
           output_tokens = output_tokens, record = record, available = available,
           annotations = annotations)
}

#' Define a model provider
#'
#' A provider is data: an id, the wire `api` its adapter implements, a base URL, how to find a
#' credential and its models. `auth` names environment variables (or is a function returning a
#' secret handle) and is resolved per request.
#'
#' @param id Provider id, `^[a-z0-9][a-z0-9-]*$`.
#' @param api Wire api (the name of an adapter), for example `"openai-completions"`.
#' @param base_url Endpoint base URL.
#' @param auth Character vector of environment-variable names, a function, or `NULL`.
#' @param models List of model records (each with at least `id`).
#' @param compat Named list of compatibility switches for the adapter.
#' @param type `"chat"`, `"classifier"` (System 1) or `"cli"`.
#' @param headers Named list of non-secret header strings.
#' @param discover `function()` listing models on request, or `NULL`.
#' @param status `function()` reporting cached provider status, or `NULL`.
#' @param aliases Alternative names of the provider.
#' @param local `TRUE` for a loopback server (unknown model ids allowed, no egress question).
#' @param offline `TRUE` when no remote model is called (test providers).
#' @param rate `list(requests_per_s, tokens_per_s)` static limits, or `NULL`.
#' @return A spec of class `c("gptr_provider", "gptr_spec")`.
#' @examples
#' gptr_provider("corp", api = "openai-completions", base_url = "https://llm.corp.example/v1",
#'               auth = "CORP_LLM_KEY", models = list(list(id = "corp-large", context = 128000)))
#' @export
gptr_provider = function(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
                         type = c("chat", "classifier", "cli"), headers = list(), discover = NULL,
                         status = NULL, aliases = character(), local = FALSE, offline = FALSE,
                         rate = NULL) {
  if (missing(api)) spec_missing("provider", id, "api")
  spec_new("provider", id, id = id, api = api, base_url = base_url, auth = auth, models = models,
           compat = compat, type = spec_arg_first(type, c("chat", "classifier", "cli")),
           headers = headers, discover = discover, status = status, aliases = aliases,
           local = local, offline = offline, rate = rate)
}

#' Define a wire adapter
#'
#' An adapter turns gptr's request context into one provider's wire format and its stream back
#' into gptr events. HTTP and process adapters give `build()` and `parse()`; `inprocess` adapters
#' give `stream()`, a generator factory; classifier adapters give `classify`.
#'
#' @param api The wire api this adapter implements (the name providers bind to).
#' @param transport `"http_sse"`, `"http_ndjson"`, `"http_json"`, `"process_jsonl"` or
#'   `"inprocess"`.
#' @param build `function(model, context, opts)` returning a request spec.
#' @param parse `function(model, opts)` returning a stream normaliser.
#' @param stream `function(model, context, opts)` returning a generator (`inprocess`).
#' @param classify Named list of functions for classifier adapters (`build` and `parse`, or
#'   `run` for `inprocess`).
#' @param capabilities Named list of adapter capabilities.
#' @return A spec of class `c("gptr_adapter", "gptr_spec")`.
#' @examples
#' gptr_adapter("echo", transport = "inprocess",
#'              stream = function(model, context, opts) {
#'                state = new.env()
#'                state$done = FALSE
#'                function() {
#'                  if (state$done) return(NULL)
#'                  state$done = TRUE
#'                  list(events = list())
#'                }
#'              })
#' @export
gptr_adapter = function(api, transport = c("http_sse", "http_ndjson", "http_json",
                                           "process_jsonl", "inprocess"),
                        build = NULL, parse = NULL, stream = NULL, classify = NULL,
                        capabilities = list()) {
  choices = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess")
  spec_new("adapter", api, api = api, transport = spec_arg_first(transport, choices),
           build = build, parse = parse, stream = stream, classify = classify,
           capabilities = capabilities)
}

#' Define a model router
#'
#' A router is a virtual model: `route(request, ctx)` runs before every request of a session whose
#' model is the router's name and returns a model reference, or
#' `list(model, thinking = NULL, state = NULL)`. A router that errors or exceeds `timeout` falls
#' back to the default model.
#'
#' @param name Router name, usable as `model = <name>`.
#' @param route `function(request, ctx)`.
#' @param description One line for listings.
#' @param timeout Seconds allowed per call.
#' @return A spec of class `c("gptr_router", "gptr_spec")`.
#' @examples
#' gptr_router("cheapest", route = function(request, ctx) "anthropic/claude-haiku-4-5")
#' @export
gptr_router = function(name, route, description = NULL, timeout = 2) {
  if (missing(route)) spec_missing("router", name, "route")
  spec_new("router", name, route = route, description = description, timeout = timeout)
}

#' Define an event hook
#'
#' A hook runs `handler(event, ctx)` for one event of the catalogue (see `gptr_api()$features`) or
#' for a plugin channel named `"<plugin>:<topic>"`. What the handler may return depends on the
#' event: patches for `tool_result`, a decision for `tool_call`, nothing for notifications.
#' Handlers of `tool_call`, `permission_request` and `document_write` fail closed: an error blocks
#' or denies, and a `tool_call` answer with an unknown `decision` (anything but `"block"`,
#' `"modify"` with an `input` list, or `"allow"`; for example `"deny"`) blocks.
#'
#' @param event Event name.
#' @param handler `function(event, ctx)`.
#' @param matcher `NULL`, a tool-name glob such as `"mcp__*"`, or `function(event)` returning
#'   `TRUE` for events the handler wants.
#' @return A spec of class `c("gptr_hook", "gptr_spec")`, named after its event.
#' @examples
#' gptr_hook("tool_result", function(event, ctx) NULL, matcher = "r")
#' @export
gptr_hook = function(event, handler, matcher = NULL) {
  ok = is.character(event) && length(event) == 1L && !is.na(event) && nzchar(event)
  label = if (ok) event else "hook"
  if (missing(handler)) spec_missing("hook", label, "handler")
  spec_new("hook", label, event = event, handler = handler, matcher = matcher)
}

#' Define a permission policy
#'
#' `check(call, ctx)` sees every tool call before it runs and returns `NULL` (no opinion) or
#' `list(decision = "allow" | "deny" | "ask" | "ask_human" | "modify", reason, input)`.
#' Decisions combine as deny > ask_human > ask > modify > allow; only a person answers an
#' `ask_human`, never a hook; a policy that errors denies. Keep checks under 10 ms.
#'
#' @param name Policy name.
#' @param check `function(call, ctx)`.
#' @param description One line for listings.
#' @return A spec of class `c("gptr_policy", "gptr_spec")`.
#' @examples
#' gptr_policy("no_installs", check = function(call, ctx) {
#'   if (identical(call$name, "r") && grepl("install.packages", call$input$code, fixed = TRUE)) {
#'     list(decision = "deny", reason = "installs are not allowed here")
#'   } else {
#'     NULL
#'   }
#' })
#' @export
gptr_policy = function(name, check, description = NULL) {
  if (missing(check)) spec_missing("policy", name, "check")
  spec_new("policy", name, check = check, description = description)
}

#' Define a sub-agent
#'
#' An agent definition names a specialist for `peter(agents = ...)`: its model, tools, skills,
#' system text, backend, preset and limits. `model` and `skills` may be bare identifiers; they are
#' stored unevaluated (as written) and resolved by the gateway. `gptr_agent("name")` alone (or
#' with only `file`) loads a saved definition. Package code should pass strings.
#'
#' @param name Agent name.
#' @param description One line describing the specialist.
#' @param model Model reference: a string, a bare identifier or a provider spec.
#' @param tools Tool names (or specs) the agent may use.
#' @param skills Skills to preload.
#' @param system System text of the agent.
#' @param backend `"auto"`, `"inline"`, `"worker"`, `"cli"` or a registered backend name.
#' @param preset Tool preset of the agent's session.
#' @param max_turns Turn limit, or `NULL`.
#' @param mode Permission mode (`"plan"`, `"manual"`, `"edits"`, `"auto"`), or `NULL` to inherit.
#' @param objects Names of objects the agent may see.
#' @param export Names of objects the agent returns.
#' @param returns JSON Schema of a structured answer, or `NULL`.
#' @param file Path of an agent definition file.
#' @return A spec of class `c("gptr_agent", "gptr_spec")`.
#' @examples
#' gptr_agent("stats", description = "Statistical reviewer", model = "anthropic/claude-opus-5-5",
#'            skills = "statistics")
#' @export
gptr_agent = function(name = NULL, description = NULL, model = NULL, tools = NULL, skills = NULL,
                      system = NULL, backend = c("auto", "inline", "worker", "cli"),
                      preset = "minimal", max_turns = NULL, mode = NULL, objects = NULL,
                      export = NULL, returns = NULL, file = NULL) {
  model_expr = substitute(model)
  skills_expr = substitute(skills)
  only_ref = missing(description) && missing(model) && missing(tools) && missing(skills) &&
    missing(system) && missing(backend) && missing(preset) && missing(max_turns) &&
    missing(mode) && missing(objects) && missing(export) && missing(returns)
  if (only_ref) {
    if (is.null(name) && is.null(file)) {
      gptr_abort("gptr_agent() needs a name, a file, or the fields of a definition.",
                 "invalid_argument", arg = "name", expected = "an agent name or file")
    }
    load = ext_service_try("agent_def.get")
    if (is.null(load)) {
      gptr_abort(paste0("gptr_agent() with only a name loads a saved agent definition, which ",
                        "needs the agent loader (plan P17); give the definition's fields instead."),
                 "not_available", member = "agent_def.get", provided_by = "P17")
    }
    return(load(name, file = file))
  }
  spec_new("agent", name, description = description, model = model_expr, tools = tools,
           skills = skills_expr, system = system,
           backend = spec_arg_first(backend, c("auto", "inline", "worker", "cli")),
           preset = preset, max_turns = max_turns, mode = mode, objects = objects,
           export = export, returns = returns, file = file)
}

#' Define a slash command
#'
#' A console command `/name args`: `handler(args, ctx)` gets the raw text after the name and
#' returns `NULL`, a character vector (printed) or `list(prompt = "...")` (sent as a prompt).
#'
#' @param name Command name without the leading `/`.
#' @param handler `function(args, ctx)`.
#' @param description One line for `/help`.
#' @param complete `function(prefix, ctx)` returning completions, or `NULL`.
#' @return A spec of class `c("gptr_command", "gptr_spec")`.
#' @examples
#' gptr_command("rows", function(args, ctx) paste("rows:", nrow(mtcars)), description = "Show rows")
#' @export
gptr_command = function(name, handler, description = NULL, complete = NULL) {
  if (missing(handler)) spec_missing("command", name, "handler")
  spec_new("command", name, handler = handler, description = description, complete = complete)
}

#' Define a system-prompt section
#'
#' A section of the frozen system prompt, rendered once per session in ascending `order`: `T0`
#' sections form the stable prefix, `T1` sections follow. `text` may be a function of `ctx`;
#' `parent` makes the section a fragment of another section.
#'
#' @param name Section name (the tag it is wrapped in).
#' @param text A string or `function(ctx)` returning a string or `NULL`.
#' @param tier `"T0"` or `"T1"`.
#' @param order Position among sections.
#' @param budget Token budget of the section.
#' @param parent Name of the section this fragment belongs to, or `NULL`.
#' @return A spec of class `c("gptr_prompt_section", "gptr_spec")`.
#' @examples
#' gptr_prompt_section("house_rules", "Use SI units in every table.", tier = "T1", order = 780L)
#' @export
gptr_prompt_section = function(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L,
                               parent = NULL) {
  if (missing(text)) spec_missing("prompt_section", name, "text")
  spec_new("prompt_section", name, text = text, tier = spec_arg_first(tier, c("T0", "T1")),
           order = order, budget = budget, parent = parent)
}

#' Define a context block
#'
#' A block of context the model receives in user messages: `provide(ctx, budget)` returns text (or
#' `NULL` to skip). `placement` puts it in the first message, in later turns, or both; turn blocks
#' equal to their previous text are skipped. `authority = "operator"` is accepted only from user,
#' plugin and built-in records.
#'
#' @param name Block name (the tag it is wrapped in).
#' @param provide `function(ctx, budget)`.
#' @param placement `"turn"`, `"first"` or `"both"`.
#' @param authority `"data"` or `"operator"`.
#' @param budget Token budget; longer text is truncated.
#' @param order Position among blocks.
#' @return A spec of class `c("gptr_context_block", "gptr_spec")`.
#' @examples
#' gptr_context_block("lab_notebook", function(ctx, budget) "Experiment 12: cohort B only.",
#'                    placement = "first", order = 650L)
#' @export
gptr_context_block = function(name, provide, placement = c("turn", "first", "both"),
                              authority = c("data", "operator"), budget = 300L, order = 650L) {
  if (missing(provide)) spec_missing("context_block", name, "provide")
  spec_new("context_block", name, provide = provide,
           placement = spec_arg_first(placement, c("turn", "first", "both")),
           authority = spec_arg_first(authority, c("data", "operator")), budget = budget,
           order = order)
}

#' Define a sub-agent backend
#'
#' A backend runs child sessions: `start(spec, ctx)` returns a handle the reactor can poll,
#' `cancel(handle)` stops it and every process it started. Backends never block the reactor for
#' more than 50 ms.
#'
#' @param name Backend name, usable as `backend = <name>`.
#' @param start `function(spec, ctx)`.
#' @param poll `function(handle)` or `NULL`.
#' @param cancel `function(handle)`.
#' @param capabilities Named list: `parallel`, `live_objects`, `ask`.
#' @return A spec of class `c("gptr_backend", "gptr_spec")`.
#' @examples
#' gptr_backend("echo", start = function(spec, ctx) NULL, cancel = function(handle) NULL)
#' @export
gptr_backend = function(name, start, poll = NULL, cancel, capabilities = list()) {
  if (missing(start)) spec_missing("backend", name, "start")
  if (missing(cancel)) spec_missing("backend", name, "cancel")
  spec_new("backend", name, start = start, poll = poll, cancel = cancel,
           capabilities = capabilities)
}

# ---- tool results (contract 5.7) -----------------------------------------------------------------

#' Image blocks from image blocks, image file paths or raw PNG vectors
#' @noRd
spec_result_images = function(images) {
  if (is.character(images)) images = as.list(images)
  if (is.raw(images)) images = list(images)
  expected = "image blocks, PNG file paths or raw PNG vectors"
  if (!is.list(images)) {
    gptr_abort(paste0("`images` must be a list of ", expected, "."), "invalid_argument",
               arg = "images", expected = expected)
  }
  mimes = c(png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif",
            webp = "image/webp")
  b64 = function(raw) gsub("[\r\n]", "", jsonlite::base64_enc(raw), perl = TRUE)
  lapply(images, function(im) {
    if (is.list(im) && identical(im[["type"]], "image")) return(im)
    if (is.raw(im)) return(block_image(b64(im), mime = "image/png", source = "plot"))
    ext = if (is.character(im) && length(im) == 1L) tolower(tools::file_ext(im)) else ""
    if (nzchar(ext) && ext %in% names(mimes) && file.exists(im)) {
      raw = readBin(im, "raw", n = file.info(im)$size)
      return(block_image(b64(raw), mime = unname(mimes[ext]), source = "file"))
    }
    gptr_abort("An element of `images` is neither an image block, an image file nor raw PNG.",
               "invalid_argument", arg = "images", expected = expected)
  })
}

#' Build a tool result
#'
#' What a tool's `execute()` returns: text and images for the model, `details` kept in the
#' transcript but never sent to a model, and `value`, the R object handed to R callers of the
#' member (kept in memory only, never persisted).
#'
#' @param text Character vector, joined with newlines into one text block, or `NULL`.
#' @param images List of image blocks, PNG file paths or raw PNG vectors, or `NULL`.
#' @param details Named list of details, or `NULL`.
#' @param is_error `TRUE` when the result reports a failure.
#' @param value Any R value returned to R callers.
#' @return A `gptr_tool_result` list with `content`, `details`, `is_error`, `value`, `spill`,
#'   `out_id`, `truncated` and `terminate`.
#' @examples
#' gptr_tool_result("3 rows", details = list(n = 3L), value = 3L)
#' @export
gptr_tool_result = function(text = NULL, images = NULL, details = NULL, is_error = FALSE,
                            value = NULL) {
  check_strings(text, "text", null = TRUE)
  check_list(details, "details", null = TRUE)
  if (length(details) && (is.null(names(details)) || !all(nzchar(names(details))))) {
    gptr_abort("`details` must be a named list.", "invalid_argument", arg = "details",
               expected = "a named list")
  }
  check_flag(is_error, "is_error")
  content = list()
  if (!is.null(text)) content = list(block_text(paste(text, collapse = "\n")))
  if (!is.null(images)) content = c(content, spec_result_images(images))
  structure(list(content = content, details = details, is_error = is_error, value = value,
                 spill = NULL, out_id = NULL, truncated = FALSE, terminate = FALSE),
            class = "gptr_tool_result")
}

#' Normalise what a tool's execute() returned (contract 5.7)
#' @noRd
as_tool_result = function(x) {
  if (inherits(x, "gptr_tool_result")) return(x)
  if (is.null(x)) return(gptr_tool_result("(no output)"))
  if (is.character(x)) return(gptr_tool_result(x))
  known = c("text", "images", "value", "is_error", "details")
  fields_ok = !length(x) || (!is.null(names(x)) && all(names(x) %in% known))
  if (is.list(x) && !is.object(x) && fields_ok) {
    text = x[["text"]]
    if (is.null(text) && is.null(x[["images"]])) text = "(no output)"
    return(gptr_tool_result(text = text, images = x[["images"]], details = x[["details"]],
                            is_error = isTRUE(x[["is_error"]]), value = x[["value"]]))
  }
  gptr_abort(paste0("A tool returned an object of class '", class(x)[[1]], "'; return a ",
                    "gptr_tool_result, text, list(text, images, value, is_error, details) ",
                    "or NULL."),
             "invalid_argument", arg = "x",
             expected = "a gptr_tool_result, a character vector, a list or NULL")
}

#' Format a tool result: its text blocks, with `[image]` for images
#' @export
#' @noRd
format.gptr_tool_result = function(x, ...) {
  parts = vapply(x$content, function(b) {
    if (identical(b[["type"]], "image")) return("[image]")
    paste(as.character(b[["text"]] %||% ""), collapse = "")
  }, "")
  paste(parts, collapse = "\n")
}

#' Print a tool result through msg_verbatim() (untrusted text is never a format string)
#' @export
#' @noRd
print.gptr_tool_result = function(x, ...) {
  msg_verbatim(format(x))
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'`, then `Rscript --vanilla -e 'devtools::test(filter = "ext-specs")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 207 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-specs.R tests/testthat/test-ext-specs.R NAMESPACE man/gptr_tool.Rd \
  man/gptr_provider.Rd man/gptr_adapter.Rd man/gptr_router.Rd man/gptr_hook.Rd \
  man/gptr_policy.Rd man/gptr_agent.Rd man/gptr_command.Rd man/gptr_prompt_section.Rd \
  man/gptr_context_block.Rd man/gptr_backend.Rd man/gptr_tool_result.Rd
git commit -m "feat(ext): add the spec constructors and gptr_tool_result()"
```

---

### Task 4: Records, resolution, `gptr_register()` and `gptr_registry()`

**Files:**
- Modify: `R/ext-registry.R` (append), `R/ext-specs.R` (append), `NAMESPACE`, `man/gptr_register.Rd`, `man/gptr_registry.Rd` (generated)
- Test: `tests/testthat/test-ext-registry.R` (create)

**Interfaces:**
- Consumes: Tasks 2-3 (`spec_finish()`, `kind_get()`, `kind_record()`, `kind_user_validate()`, the constructors); P01 `redact_hook(x, profile)`, `est_tokens(x, class)`, `schema_signature(name, schema, description = NULL, prefix = "")`, `json_encode()`, `check_class()`, `check_number()`.
- Produces (04 §7.2): `registry_add(spec, source, rank, session = NULL, state = "active")` -> record id (`"r<n>"`); `registry_remove(id)` -> `invisible(lgl(1))`; `registry_get(kind, name, session = NULL)` -> the winning spec or `NULL`; `registry_all(kind, session = NULL)` -> named list of specs (all-kinds: every enabled record ordered by the kind's order field, else rank then registration; first-kinds: the winner per name, sorted by name; lazy records are activated first, except `tool` placeholders, which are returned unactivated because their manifest declarations feed the frozen prompt's catalogs, 04 §10.8); `registry_names(kind, session = NULL)`; `registry_generation()`; `registry_diagnostic(source, event, class, message)` (redacted with `redact_hook(x, "persist")`, last 1,000 rows); `registry_session_drop(sid)` (removes a session's records, makes its extensions stale and forgets them); `ext_forget(info, reg)` (an extension record leaves `reg$exts`, releases its factory and its per-load state, so no factory closure, and no frame it captured, outlives the session or the failed, unloaded or reloaded load: rule R10); `registry_check_source(source)`; `registry_member_names(reg)`; `spec_key(spec)` (`"<namespace>/<name>"` for namespaced tools); `spec_tokens(spec)`; `ext_reserved_members`; `ext_control_guard(what)` and `ext_control_grant(run, what)` (IC-53 point 3: P06 or P11 calls `ext_control_grant()` after an `ask_human` approval of a control export); the exports `gptr_register(spec)` -> unregister function invisibly (the function passes the same `ext_control_guard("gptr_register")`, so model code cannot remove a user's policy through an `off()` closure kept in its evaluation environment) and `gptr_registry(kind = NULL, diagnostics = FALSE)` (the full listing, `kind = NULL`, is cached in `reg$listing` until `registry_touch()` or a change of the protected built-ins; P01's `service_builtin_active()` lists the registry on every service lookup, and without the cache every `ctx` member call cost two full listings, about 14 ms with 320 records, above the 10 ms policy budget); `kind_from_spec()`, `kind_undefine()` (a `kind` record defines its kind; removing it undefines it).

`registry_rec_filtered()` is defined here and reads the effective filters (`reg$eff`) that Task 5 sets; until Task 5 there are none. `registry_get()` and `registry_all()` call `ext_activate_record()` (Task 9) for lazy placeholders, which exist only once Task 9 registers them.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-registry.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

test_that("the lowest rank wins per (kind, name): session < project < user < plugin < builtin", {
  local_registry()
  registry_add(cmd("hi", "builtin"), "builtin:console", 6L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "builtin")
  registry_add(cmd("hi", "plugin"), "plugin:p", 5L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "plugin")
  registry_add(cmd("hi", "user"), "user", 3L)
  registry_add(cmd("hi", "project"), "project", 1L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "project")
  registry_add(cmd("hi", "session"), "session", 0L, session = "s1")
  expect_equal(registry_get("command", "hi", session = "s1")$handler("", NULL), "session")
  expect_equal(registry_get("command", "hi", session = "s2")$handler("", NULL), "project")
  expect_null(registry_get("command", "nope"))
  expect_error(registry_add(cmd("x"), "somewhere", 3L), class = "gptr_error_invalid_argument")
})

test_that("ties go to the first registration with a collision diagnostic", {
  local_registry()
  registry_add(cmd("hi", "first"), "plugin:a", 5L)
  registry_add(cmd("hi", "second"), "plugin:b", 5L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "first")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "collision" & d$source == "plugin:b"))
})

test_that("overrides are per record: a user read leaves the built-in edit and grep (IC-69)", {
  local_registry()
  tool = function(name, text) {
    force(text)
    gptr_tool(name, paste("Built-in", name), execute = function(input, ctx) text,
              fun = function(path = ".") text)
  }
  for (nm in c("read", "edit", "grep")) registry_add(tool(nm, nm), "builtin:tools", 6L)
  off = gptr_register(tool("read", "user-read"))
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "user-read")
  expect_equal(registry_get("tool", "edit")$execute(list(), NULL), "edit")
  expect_equal(registry_get("tool", "grep")$fun(), "grep")
  expect_true("grep" %in% registry_member_names(registry_env()))
  r = gptr_registry("tool")
  expect_equal(r$state[r$name == "read" & r$source == "builtin:tools"], "overridden")
  expect_equal(r$state[r$name == "edit"], "active")
  off()
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "read")
})

test_that("registry_all() orders all-kinds by their order field and returns winners otherwise", {
  local_registry()
  pol = function(name, order) {
    gptr_spec("policy", name, check = function(call, ctx) NULL, order = order)
  }
  registry_add(pol("late", 900L), "builtin:permissions", 6L)
  registry_add(pol("early", 100L), "user", 3L)
  registry_add(pol("middle", 500L), "plugin:p", 5L)
  expect_equal(names(registry_all("policy")), c("early", "middle", "late"))
  registry_add(cmd("a", "builtin"), "builtin:console", 6L)
  registry_add(cmd("b"), "user", 3L)
  registry_add(cmd("a", "user"), "user", 3L)
  all_cmd = registry_all("command")
  expect_equal(names(all_cmd), c("a", "b"))
  expect_equal(all_cmd$a$handler("", NULL), "user")
  expect_equal(registry_names("command"), c("a", "b"))
  expect_equal(registry_names("policy"), c("late", "early", "middle"))
  expect_error(registry_all("widget"), class = "gptr_error_unknown_kind")
})

test_that("registry_remove() drops a record; a kind record defines and undefines its kind", {
  local_registry()
  id = registry_add(cmd("x"), "user", 3L)
  expect_true(registry_remove(id))
  expect_false(registry_remove(id))
  expect_null(registry_get("command", "x"))
  kid = registry_add(gptr_spec("kind", "reviewer", validate = function(spec) spec,
                               resolve = "all"), "plugin:p", 5L)
  expect_true("reviewer" %in% kind_names())
  expect_true(kind_get("reviewer")$experimental)
  expect_equal(kind_get("reviewer")$source, "plugin:p")
  registry_add(gptr_spec("reviewer", "stats", model = "opus"), "plugin:p", 5L)
  expect_equal(names(registry_all("reviewer")), "stats")
  expect_error(registry_add(gptr_spec("kind", "reviewer", validate = function(spec) spec),
                            "plugin:q", 5L), class = "gptr_error_invalid_spec")
  expect_equal(nrow(gptr_registry("kind")), 1L)
  registry_remove(kid)
  expect_false("reviewer" %in% kind_names())
})

test_that("registration rules that depend on the source: operator blocks and namespaces", {
  local_registry()
  blk = gptr_context_block("orders", function(ctx, budget) "x", authority = "operator")
  err = expect_error(registry_add(blk, "project", 1L), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "authority")
  expect_error(registry_add(blk, "session", 0L, session = "s1"), class = "gptr_error_invalid_spec")
  expect_true(is.character(registry_add(blk, "user", 3L)))
  member = gptr_tool("search", "Search", fun = function(q) q, exposure = "r")
  err = expect_error(registry_add(member, "plugin:trials", 5L), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "namespace")
  mcp = gptr_tool("search", "Search", fun = function(q) q, exposure = "r", namespace = "mcp")
  expect_error(registry_add(mcp, "plugin:trials", 5L), class = "gptr_error_invalid_spec")
  registry_add(gptr_tool("panel", "P", fun = function() 1, exposure = "r"), "user", 3L)
  clash = gptr_tool("x", "X", fun = function() 1, exposure = "r", namespace = "panel")
  expect_error(registry_add(clash, "plugin:p", 5L), class = "gptr_error_invalid_spec")
  ok = gptr_tool("search", "Search", fun = function(q) q, exposure = "r", namespace = "trials")
  registry_add(ok, "plugin:trials", 5L)
  expect_equal(registry_get("tool", "trials/search")$name, "search")
})

test_that("gptr_register() adds a user record, re-validates, and returns an unregister function", {
  local_registry()
  off = gptr_register(gptr_command("hello", function(args, ctx) "hi"))
  expect_true(is.function(off))
  expect_equal(registry_get("command", "hello")$handler("", NULL), "hi")
  off()
  expect_null(registry_get("command", "hello"))
  expect_error(gptr_register(list(kind = "command")), class = "gptr_error_invalid_argument")
  bad = gptr_command("hello", function(args, ctx) "hi")
  bad$handler = "not a function"
  expect_error(gptr_register(bad), class = "gptr_error_invalid_spec")
})

test_that("gptr_register() is refused from model code during a run unless granted (IC-53)", {
  reg = local_registry()
  off_policy = gptr_register(gptr_policy("no_installs", function(call, ctx) NULL))
  reg$executing = c(c7 = "u1")
  err = expect_error(gptr_register(cmd("x")), class = "gptr_error_permission")
  expect_equal(err$action, "gptr_register")
  expect_null(registry_get("command", "x"))
  # the unregister function a user kept in the evaluation environment is guarded too
  expect_error(off_policy(), class = "gptr_error_permission")
  expect_length(registry_all("policy"), 1L)
  ext_control_grant("u1", "gptr_register")
  gptr_register(cmd("x"))
  expect_false(is.null(registry_get("command", "x")))
  expect_length(reg$grants, 0L)
  expect_error(gptr_register(cmd("y")), class = "gptr_error_permission")
  reg$executing = character()
  gptr_register(cmd("y"))
  expect_false(is.null(registry_get("command", "y")))
  off_policy()
  expect_length(registry_all("policy"), 0L)
})

test_that("gptr_registry() lists records with the tokens and experimental columns", {
  local_registry()
  gptr_register(gptr_tool("add", "Add two numbers",
                          parameters = list(type = "object", required = I(c("a", "b")),
                                            properties = list(a = list(type = "number"),
                                                              b = list(type = "number"))),
                          execute = function(input, ctx) input$a + input$b))
  gptr_register(gptr_spec("service", "describe", fun = function(x, budget) "d"))
  registry_add(cmd("mine"), "session", 0L, session = "s1")
  r = gptr_registry()
  expect_s3_class(r, c("gptr_registry", "data.frame"), exact = TRUE)
  expect_named(r, c("kind", "name", "source", "rank", "state", "tokens", "experimental"))
  expect_equal(r$name, c("describe", "add"))
  expect_gt(r$tokens[r$name == "add"], 0)
  expect_true(r$experimental[r$kind == "service"])
  expect_false(r$experimental[r$kind == "tool"])
  expect_equal(nrow(gptr_registry("command")), 0L)
  expect_error(gptr_registry("widget"), class = "gptr_error_unknown_kind")
  expect_output(print(r), "<gptr_registry> 2 record(s)", fixed = TRUE)
  member = gptr_tool("rows", "Rows of a data frame.", fun = function(name) 1L, exposure = "r",
                     namespace = "demo")
  expect_gt(spec_tokens(member), 0)
  expect_equal(spec_tokens(gptr_tool("h", "Hidden.", fun = function() 1, exposure = "hidden")), 0)
})

test_that("the full listing is cached until records or kinds change", {
  reg = local_registry()
  registry_add(cmd("a"), "user", 3L)
  first = gptr_registry()
  expect_identical(reg$listing, first)
  expect_identical(gptr_registry(), first)
  id = registry_add(cmd("b"), "user", 3L)
  expect_equal(nrow(gptr_registry()), 2L)
  registry_remove(id)
  expect_equal(gptr_registry()$name, "a")
  kind_define("reviewer", validate = function(spec) spec, source = "plugin:p")
  registry_add(gptr_spec("reviewer", "stats"), "plugin:p", 5L)
  expect_true("reviewer" %in% gptr_registry()$kind)
  expect_equal(nrow(gptr_registry("command")), 1L)
})

test_that("diagnostics are redacted, capped and listed", {
  local_registry()
  old = the$redactor
  withr::defer(assign("redactor", old, envir = the))
  redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  registry_diagnostic("plugin:p", "load", "boom", "failed with sk-abc123")
  d = gptr_registry(diagnostics = TRUE)
  expect_s3_class(d, c("gptr_diagnostics", "data.frame"), exact = TRUE)
  expect_named(d, c("time", "source", "event", "class", "message"))
  expect_equal(d$message, "failed with [secret:KEY]")
  expect_output(print(d), "<gptr_diagnostics> 1 row(s)", fixed = TRUE)
  for (i in 1:1005) registry_diagnostic("x", "e", "c", "m")
  expect_equal(nrow(gptr_registry(diagnostics = TRUE)), 1000L)
})

test_that("registry_session_drop() removes only that session's records", {
  local_registry()
  registry_add(cmd("mine"), "session", 0L, session = "s1")
  registry_add(cmd("theirs"), "session", 0L, session = "s2")
  registry_session_drop("s1")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_false(is.null(registry_get("command", "theirs", session = "s2")))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-registry")'`
Expected: errors such as `could not find function "registry_add"`, `could not find function "gptr_register"` and `could not find function "registry_diagnostic"`, until testthat stops with `Maximum number of failures exceeded; quitting.`

- [ ] **Step 3: Write the implementation**

Append to `R/ext-registry.R`:

```r
# ---- records (contract 5.5, 7.2, 10.1) ----------------------------------------------------------

#' Append an id to an index entry
#' @noRd
registry_index_push = function(env, key, id) {
  assign(key, c(get0(key, envir = env, inherits = FALSE), id), envir = env)
  invisible(NULL)
}

#' Drop an id from an index entry
#' @noRd
registry_index_drop = function(env, key, id) {
  ids = get0(key, envir = env, inherits = FALSE)
  if (is.null(ids)) return(invisible(NULL))
  ids = ids[ids != id]
  if (length(ids)) assign(key, ids, envir = env) else rm(list = key, envir = env)
  invisible(NULL)
}

#' Records for a vector of ids
#' @noRd
registry_recs = function(reg, ids) {
  if (!length(ids)) return(list())
  lapply(ids, function(id) get(id, envir = reg$recs, inherits = FALSE))
}

#' Order records by rank, then registration
#' @noRd
registry_sort = function(recs) {
  if (length(recs) < 2L) return(recs)
  rank = vapply(recs, function(r) r$rank, 0L)
  ord = vapply(recs, function(r) r$order, 0L)
  recs[order(rank, ord)]
}

#' Is a record visible to a session (process records, or that session's own)?
#' @noRd
registry_visible = function(rec, sid) is.null(rec$session) || identical(rec$session, sid)

#' Registry key of a spec: tools with a namespace are "<namespace>/<name>" (contract 10.2)
#' @noRd
spec_key = function(spec) {
  ns = spec[["namespace"]]
  if (identical(spec[["kind"]], "tool") && is.character(ns) && length(ns) == 1L) {
    return(paste0(ns, "/", spec[["name"]]))
  }
  spec[["name"]]
}

#' Declaration cost of a spec in estimated tokens (the `tokens` column; report G1 4.8)
#' @noRd
spec_tokens = function(spec) {
  n = tryCatch({
    if (isTRUE(spec[["lazy"]])) {
      d = spec[["declaration"]]
      if (is.null(d)) 0 else est_tokens(paste(d$signature %||% "", d$description %||% ""), "code")
    } else if (identical(spec$kind, "tool")) {
      params = if (is.list(spec[["parameters"]])) spec[["parameters"]] else json_obj()
      if (identical(spec[["exposure"]], "direct")) {
        est_tokens(json_encode(list(name = spec$name, description = spec[["description"]],
                                    input_schema = params)), "json")
      } else if (identical(spec[["exposure"]], "r")) {
        ns = spec[["namespace"]]
        prefix = if (is.null(ns)) "peter$" else paste0("peter$", ns, "$")
        sig = spec[["signature"]] %||%
          schema_signature(spec$name, params, spec[["description"]], prefix = prefix)
        est_tokens(sig, "code")
      } else {
        0
      }
    } else if (identical(spec$kind, "prompt_section")) {
      text = spec[["text"]]
      if (is.character(text)) est_tokens(text, "prose") else as.numeric(spec[["budget"]])
    } else if (identical(spec$kind, "context_block")) {
      as.numeric(spec[["budget"]])
    } else if (identical(spec$kind, "skill")) {
      spec[["tokens"]] %||% est_tokens(paste(spec$name, spec[["description"]] %||% ""), "prose")
    } else {
      0
    }
  }, error = function(e) 0)
  as.numeric(n)
}

#' Member and namespace names reserved for built-ins and MCP (IC-37, contract 9.4)
#' @noRd
ext_reserved_members = c("read", "write", "edit", "grep", "find", "ls", "help", "search",
                         "describe", "plot", "out", "sh", "script", "bg", "jobs", "py", "sql",
                         "knit", "app", "mcp")

#' Names of un-namespaced, non-hidden tool records with a `fun` (the peter$ members, IC-37)
#' @noRd
registry_member_names = function(reg) {
  recs = registry_recs(reg, get0("tool", envir = reg$by_kind, inherits = FALSE))
  keep = vapply(recs, function(r) {
    s = r$spec
    is.null(s[["namespace"]]) && is.function(s[["fun"]]) && !identical(s[["exposure"]], "hidden")
  }, NA)
  unique(vapply(recs[keep], function(r) r$name, ""))
}

#' Source- and rank-dependent registration rules (IC-37, IC-52)
#' @noRd
registry_admit = function(spec, source, rank, reg) {
  operator = identical(spec[["kind"]], "context_block") &&
    identical(spec[["authority"]], "operator")
  if (operator && rank < 3L) {
    spec_abort(spec, "authority",
               paste0("'operator' is accepted only from records of rank 3 or more (user, ",
                      "plugin, built-in); this record has rank ", rank))
  }
  if (identical(spec$kind, "tool")) {
    ns = spec[["namespace"]]
    if (startsWith(source, "plugin:") && identical(spec[["exposure"]], "r") && is.null(ns)) {
      spec_abort(spec, "namespace", "is required for plugin members with exposure 'r'")
    }
    if (!is.null(ns)) {
      if (ns %in% ext_reserved_members) spec_abort(spec, "namespace", "is a reserved member name")
      if (ns %in% registry_member_names(reg)) {
        spec_abort(spec, "namespace", "equals an existing peter$ member name")
      }
    }
  }
  invisible(TRUE)
}

#' Record a collision diagnostic for a tie at the same rank (contract 10.1)
#' @noRd
registry_collision = function(rec, reg) {
  if (identical(rec$state, "lazy")) return(invisible(NULL))
  k = kind_get(rec$kind)
  if (!identical(k$resolve, "first")) return(invisible(NULL))
  ids = get0(paste(rec$kind, rec$name, sep = "\r"), envir = reg$by_key, inherits = FALSE)
  for (other in registry_recs(reg, setdiff(ids, rec$id))) {
    tie = identical(other$rank, rec$rank) && identical(other$session, rec$session) &&
      !identical(other$source, rec$source) && !identical(other$state, "lazy")
    if (tie) {
      registry_diagnostic(rec$source, "register", "collision",
                          paste0(rec$kind, " '", rec$name, "' from ", rec$source, " ties with ",
                                 other$source, " at rank ", rec$rank,
                                 "; the first registered record wins"))
      break
    }
  }
  invisible(NULL)
}

#' Check a registry source string (contract 10.1): session, project, user, builtin:<name> or
#' plugin:<name>
#' @noRd
registry_check_source = function(source) {
  check_string(source, "source")
  if (!grepl("^(session|project|user|builtin:.+|plugin:.+)$", source, perl = TRUE)) {
    gptr_abort("`source` must be session, project, user, builtin:<name> or plugin:<name>.",
               "invalid_argument", arg = "source", expected = "a registry source string")
  }
  invisible(source)
}

#' Store a validated spec as a registry record; returns its id (contract 7.2). Lazy placeholders
#' (state "lazy", made by ext_load()) are stored unvalidated and may name a kind that their
#' factory defines on activation.
#' @noRd
registry_add = function(spec, source, rank, session = NULL, state = "active") {
  check_class(spec, "gptr_spec", "spec")
  registry_check_source(source)
  rank = check_number(rank, "rank", min = 0, max = 99, int = TRUE)
  state = check_choice(state, c("active", "lazy"), "state")
  reg = registry_env()
  rank = as.integer(rank)
  sid = ext_session_id(session)
  if (identical(state, "active")) {
    spec = spec_finish(unclass(spec), kind_get(spec$kind))
    registry_admit(spec, source, rank, reg)
  }
  key = spec_key(spec)
  reg$seq = reg$seq + 1L
  id = paste0("r", reg$seq)
  if (identical(spec$kind, "kind") && identical(state, "active")) kind_from_spec(spec, source, id)
  rec = list(id = id, kind = spec$kind, name = key, spec = spec, rank = rank, source = source,
             state = state, generation = reg$generation, tokens = spec_tokens(spec),
             session = sid, order = reg$seq, ext = reg$current_ext)
  assign(id, rec, envir = reg$recs)
  registry_index_push(reg$by_kind, spec$kind, id)
  registry_index_push(reg$by_key, paste(spec$kind, key, sep = "\r"), id)
  if (identical(spec$kind, "hook")) registry_index_push(reg$hooks, spec[["event"]] %||% key, id)
  registry_touch(reg)
  registry_collision(rec, reg)
  id
}

#' Remove one record (contract 7.2)
#' @noRd
registry_remove = function(id) {
  reg = registry_env()
  rec = get0(id, envir = reg$recs, inherits = FALSE)
  if (is.null(rec)) return(invisible(FALSE))
  rm(list = id, envir = reg$recs)
  registry_index_drop(reg$by_kind, rec$kind, id)
  registry_index_drop(reg$by_key, paste(rec$kind, rec$name, sep = "\r"), id)
  if (identical(rec$kind, "hook")) {
    registry_index_drop(reg$hooks, rec$spec[["event"]] %||% rec$name, id)
  }
  if (identical(rec$kind, "kind")) kind_undefine(rec$spec[["name"]], id)
  registry_touch(reg)
  invisible(TRUE)
}

#' Enabled records of (kind, key) visible to a session, winner first
#' @noRd
registry_candidates = function(kind, key, sid, reg = registry_env()) {
  ids = get0(paste(kind, key, sep = "\r"), envir = reg$by_key, inherits = FALSE)
  recs = registry_recs(reg, ids)
  recs = recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                     NA)]
  registry_sort(recs)
}

#' The winning spec for (kind, name) or NULL; a lazy winner is activated first (contract 7.2)
#' @noRd
registry_get = function(kind, name, session = NULL) {
  check_string(kind, "kind")
  check_string(name, "name")
  sid = ext_session_id(session)
  reg = registry_env()
  for (attempt in seq_len(10L)) {
    recs = registry_candidates(kind, name, sid, reg)
    if (!length(recs)) return(NULL)
    win = recs[[1]]
    if (!identical(win$state, "lazy")) return(win$spec)
    ext_activate_record(win)
  }
  NULL
}

#' Specs of a kind: every record of an `all` kind, ordered; the winner per name otherwise. Lazy
#' records are activated first, except `tool` placeholders, whose manifest declarations feed the
#' frozen prompt's catalogs before activation (contract 10.8)
#' @noRd
registry_all = function(kind, session = NULL) {
  check_string(kind, "kind")
  k = kind_get(kind)
  sid = ext_session_id(session)
  reg = registry_env()
  pick = function() {
    recs = registry_recs(reg, get0(kind, envir = reg$by_kind, inherits = FALSE))
    recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                NA)]
  }
  recs = pick()
  if (!identical(kind, "tool")) {
    lazy = recs[vapply(recs, function(r) identical(r$state, "lazy"), NA)]
    if (length(lazy)) {
      for (r in lazy) ext_activate_record(r)
      recs = pick()
      recs = recs[!vapply(recs, function(r) identical(r$state, "lazy"), NA)]
    }
  }
  if (identical(k$resolve, "all")) {
    recs = registry_sort(recs)
    of = k$order_field
    if (!is.null(of) && length(recs) > 1L) {
      o = vapply(recs, function(r) as.numeric(r$spec[[of]] %||% 500), 0)
      recs = recs[order(o, seq_along(recs))]
    }
  } else {
    recs = registry_sort(recs)
    keys = vapply(recs, function(r) r$name, "")
    recs = recs[!duplicated(keys)]
    recs = recs[order(vapply(recs, function(r) r$name, ""), method = "radix")]
  }
  specs = lapply(recs, function(r) r$spec)
  names(specs) = vapply(recs, function(r) r$name, "")
  specs
}

#' Names with an enabled record, lazy placeholders included (contract 7.2)
#' @noRd
registry_names = function(kind, session = NULL) {
  check_string(kind, "kind")
  sid = ext_session_id(session)
  reg = registry_env()
  recs = registry_recs(reg, get0(kind, envir = reg$by_kind, inherits = FALSE))
  recs = recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                     NA)]
  unique(vapply(recs, function(r) r$name, ""))
}

#' The registry generation (bumped by gptr_reload())
#' @noRd
registry_generation = function() registry_env()$generation

#' Append a redacted diagnostic row (contract 7.2); keeps the last 1,000 rows
#' @noRd
registry_diagnostic = function(source, event, class, message) {
  reg = registry_env()
  row = list(time = Sys.time(), source = as.character(source)[1],
             event = as.character(event)[1], class = as.character(class)[1],
             message = redact_hook(paste(as.character(message), collapse = " "), "persist"))
  rows = reg$diag$rows
  rows[[length(rows) + 1L]] = row
  if (length(rows) > 1000L) rows = rows[seq.int(length(rows) - 999L, length(rows))]
  reg$diag$rows = rows
  invisible(NULL)
}

#' Forget an extension record: its API objects turn stale, its factory (and every frame the
#' factory closes over) is released, and a per-load `gptr$state` goes with it (rule R10). Plugin
#' and built-in state, keyed by source, lives for the process (contract 10.5)
#' @noRd
ext_forget = function(info, reg = registry_env()) {
  info$unloaded = TRUE
  info$factory = NULL
  info$stage = list()
  for (env in list(reg$exts, reg$states)) {
    if (exists(info$id, envir = env, inherits = FALSE)) rm(list = info$id, envir = env)
  }
  invisible(NULL)
}

#' Drop a session's records and forget its extensions (at its session_shutdown; IC-69)
#' @noRd
registry_session_drop = function(sid) {
  reg = registry_env()
  for (id in ls(reg$recs)) {
    rec = get(id, envir = reg$recs, inherits = FALSE)
    if (identical(rec$session, sid)) registry_remove(id)
  }
  for (eid in ls(reg$exts)) {
    info = get(eid, envir = reg$exts, inherits = FALSE)
    if (identical(info$session, sid)) {
      info$status = "unloaded"
      ext_forget(info, reg)
    }
  }
  invisible(NULL)
}

# ---- control exports (IC-53 point 3) ------------------------------------------------------------

#' Refuse a gptr configuration export called from model code during a run (IC-53)
#'
#' A tool is executing when ev_dispatch() has seen its tool_execution_start and not yet its
#' tool_execution_end (or its run's agent_end). Inside a tool, the call passes only with a
#' one-shot grant recorded by ext_control_grant() after an ask_human approval; an unused grant
#' ends with the top-level call it was granted in (ev_track(), Task 8).
#' @noRd
ext_control_guard = function(what) {
  reg = registry_env()
  if (!length(reg$executing)) return(invisible(TRUE))
  runs = unique(unname(reg$executing))
  for (i in seq_along(reg$grants)) {
    g = reg$grants[[i]]
    if (identical(g$what, what) && g$run %in% runs) {
      reg$grants = reg$grants[-i]
      return(invisible(TRUE))
    }
  }
  gptr_abort(paste0(what, "() changes gptr's configuration and cannot be called from model code ",
                    "while a run executes a tool, unless the user approved that call."),
             "permission", action = what, tool = "r", risk = 4L,
             how_to_allow = paste0("run ", what, "() yourself at the R console"), session = NULL)
}

#' Record a one-shot approval of `what` (an export name) for a run (called after ask_human)
#' @noRd
ext_control_grant = function(run, what) {
  check_string(run, "run")
  check_string(what, "what")
  reg = registry_env()
  reg$grants[[length(reg$grants) + 1L]] = list(run = run, what = what)
  invisible(TRUE)
}

# ---- exported registration and listing ----------------------------------------------------------

#' The unregister closure returned by gptr_register(). Removing a record reconfigures gptr as much
#' as adding one, and users keep this closure in the environment model code evaluates in
#' (`off = gptr_register(gptr_policy(...))`), so it passes the same IC-53 guard
#' @noRd
registry_unregister_fn = function(id) {
  force(id)
  function() {
    ext_control_guard("gptr_register")
    invisible(registry_remove(id))
  }
}

#' Register a capability spec
#'
#' Registers a spec made by [gptr_spec()] or one of the spec constructors at top level: rank 3,
#' source `"user"`, for the lifetime of the R process. Sessions frozen before the call are not
#' changed; the next session sees the record. A user record overrides a built-in record of the same
#' kind and name only (the built-in's other records keep working).
#'
#' Called from model code while a run executes a tool, `gptr_register()` and the function it
#' returns signal `gptr_error_permission` unless the user approved that call.
#'
#' @param spec A spec (class `gptr_spec`).
#' @return A function that removes the record again, invisibly.
#' @examples
#' off = gptr_register(gptr_command("hello", function(args, ctx) "hi"))
#' off()
#' @export
gptr_register = function(spec) {
  check_class(spec, "gptr_spec", "spec")
  ext_control_guard("gptr_register")
  id = registry_add(spec, source = "user", rank = 3L)
  invisible(registry_unregister_fn(id))
}

#' State of a record for listings: lazy, disabled, overridden or active
#' @noRd
registry_rec_state = function(rec, reg) {
  if (identical(rec$state, "lazy")) return("lazy")
  if (registry_rec_filtered(rec, reg)) return("disabled")
  k = kind_get(rec$kind)
  if (identical(k$resolve, "first")) {
    win = registry_candidates(rec$kind, rec$name, rec$session, reg)
    if (length(win) && !identical(win[[1]]$id, rec$id)) return("overridden")
  }
  "active"
}

#' List the extension registry
#'
#' One row per process-level record (session-scoped records are not listed): its kind, name,
#' source (`builtin:<name>`, `plugin:<name>`, `user`, `project`), rank, state (`lazy`, `active`,
#' `overridden`, `disabled`), the estimated tokens its declaration costs, and whether the kind is
#' experimental. With `diagnostics = TRUE`, the redacted diagnostics log instead.
#'
#' @param kind `NULL` for every kind, or a character vector of kind names.
#' @param diagnostics `TRUE` to return the diagnostics log.
#' @return A `gptr_registry` data frame (columns `kind`, `name`, `source`, `rank`, `state`,
#'   `tokens`, `experimental`), or a `gptr_diagnostics` data frame (columns `time`, `source`,
#'   `event`, `class`, `message`).
#' @examples
#' gptr_registry("tool")
#' gptr_registry(diagnostics = TRUE)
#' @export
gptr_registry = function(kind = NULL, diagnostics = FALSE) {
  check_strings(kind, "kind", null = TRUE)
  check_flag(diagnostics, "diagnostics")
  reg = registry_env()
  if (diagnostics) return(registry_diag_df(reg))
  key = list(reg$version, registry_protected_builtins())
  if (is.null(kind) && identical(reg$listing_key, key)) return(reg$listing)
  kinds = kind %||% kind_names()
  rows = list()
  for (k in kinds) {
    def = kind_get(k)
    recs = registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))
    recs = recs[vapply(recs, function(r) is.null(r$session), NA)]
    for (r in recs) {
      rows[[length(rows) + 1L]] = list(kind = k, name = r$name, source = r$source,
                                       rank = r$rank, state = registry_rec_state(r, reg),
                                       tokens = r$tokens, experimental = isTRUE(def$experimental))
    }
  }
  col = function(f, type) if (length(rows)) vapply(rows, function(r) r[[f]], type) else type[0]
  df = data.frame(kind = col("kind", ""), name = col("name", ""), source = col("source", ""),
                  rank = col("rank", 0L), state = col("state", ""), tokens = col("tokens", 0),
                  experimental = col("experimental", NA), stringsAsFactors = FALSE)
  out = structure(df, class = c("gptr_registry", "data.frame"))
  if (is.null(kind)) {
    reg$listing = out
    reg$listing_key = key
  }
  out
}

#' The diagnostics log as a data frame
#' @noRd
registry_diag_df = function(reg) {
  rows = reg$diag$rows
  col = function(f) if (length(rows)) vapply(rows, function(r) r[[f]], "") else character()
  time = if (length(rows)) do.call(c, lapply(rows, function(r) r$time)) else Sys.time()[0]
  df = data.frame(time = time, source = col("source"), event = col("event"),
                  class = col("class"), message = col("message"), stringsAsFactors = FALSE)
  structure(df, class = c("gptr_diagnostics", "data.frame"))
}

#' Print a registry listing
#' @export
#' @noRd
print.gptr_registry = function(x, ...) {
  cat("<gptr_registry> ", nrow(x), " record(s)\n", sep = "")
  if (nrow(x)) print(structure(x, class = "data.frame"), row.names = FALSE)
  invisible(x)
}

#' Print the diagnostics log
#' @export
#' @noRd
print.gptr_diagnostics = function(x, ...) {
  cat("<gptr_diagnostics> ", nrow(x), " row(s)\n", sep = "")
  if (nrow(x)) print(structure(x, class = "data.frame"), row.names = FALSE)
  invisible(x)
}

# ---- filter state read at resolution time (contract 10.1; IC-53) --------------------------------

#' Built-ins that no filter may disable: the permission kernel, secrets, and every built-in
#' declared with replaceable = FALSE (IC-53, contract 7.2 ext_declare_builtin)
#' @noRd
registry_protected_builtins = function() {
  b = the$builtins %||% list()
  fixed = vapply(b, function(x) isFALSE(x$replaceable), NA)
  unique(c("permissions", "plan", "secrets", names(b)[fixed]))
}

#' Records of these sources are immune to every filter (IC-53)
#' @noRd
registry_source_protected = function(source) {
  source %in% c("builtin:permissions", "builtin:plan", "builtin:secrets")
}

#' Is a record disabled by the effective filters (by default the registry's own)?
#' @noRd
registry_rec_filtered = function(rec, reg = registry_env(), eff = reg$eff) {
  if (!length(eff)) return(FALSE)
  src = rec$source
  if (registry_source_protected(src)) return(FALSE)
  keys = paste0(rec$kind, ":", rec$name)
  if (startsWith(src, "plugin:")) keys = c(keys, src)
  if (startsWith(src, "builtin:") && !(substring(src, 9L) %in% registry_protected_builtins())) {
    keys = c(keys, src)
  }
  hit = eff[names(eff) %in% keys]
  if (!length(hit)) return(FALSE)
  kept_from_project = identical(src, "user") || startsWith(src, "builtin:")
  if (rec$kind %in% c("policy", "hook") && kept_from_project) hit = hit[hit != "project"]
  length(hit) > 0L
}
```

Append to `R/ext-specs.R`:

```r
# ---- kinds defined by `kind` records (contract 10.2 row 30) -------------------------------------

#' A kind record for a `kind` spec
#' @noRd
kind_record_from_spec = function(spec, source) {
  kind_record(spec[["name"]], kind_user_validate(spec[["validate"]]), spec[["resolve"]],
              spec[["fields"]], spec[["order_field"]], spec[["experimental"]], source)
}

#' Define the kind described by a `kind` spec; `id` is its registry record
#' @noRd
kind_from_spec = function(spec, source, id) {
  k = kinds_env()
  old = get0(spec[["name"]], envir = k, inherits = FALSE)
  staged_here = !is.null(old) && !is.null(old$staged) &&
    identical(old$staged, registry_env()$current_ext)
  if (!is.null(old) && !staged_here) {
    spec_abort(spec, "name", paste0("names a kind already defined by ", old$source))
  }
  rec = kind_record_from_spec(spec, source)
  rec$record = id
  assign(spec[["name"]], rec, envir = k)
  registry_touch()
  invisible(spec[["name"]])
}

#' Undefine the kind created by registry record `id`
#' @noRd
kind_undefine = function(name, id) {
  k = kinds_env()
  d = get0(name, envir = k, inherits = FALSE)
  if (!is.null(d) && identical(d$record, id)) {
    rm(list = name, envir = k)
    registry_touch()
  }
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'`, then `Rscript --vanilla -e 'devtools::test(filter = "ext-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 80 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-registry.R R/ext-specs.R tests/testthat/test-ext-registry.R NAMESPACE \
  man/gptr_register.Rd man/gptr_registry.Rd
git commit -m "feat(ext): add registry records, resolution, gptr_register() and gptr_registry()"
```

---

### Task 5: Filters

**Files:**
- Modify: `R/ext-registry.R` (append)
- Test: `tests/testthat/test-ext-registry.R` (append)

**Interfaces:**
- Consumes: Task 4 (`registry_rec_filtered()`, `registry_protected_builtins()`, `registry_source_protected()`, `registry_recs()`, `registry_diagnostic()`), `kind_names()`; `the$builtins` (Task 10 fills it).
- Produces: `registry_filters_set(filters, scope = c("session", "user", "project"))` -> the effective filter keys invisibly with attribute `refused` (04 §7.2, IC-53); `registry_filters_effective(filters)`; `registry_drops_guard(reg, eff)` -> `lgl(1)` (would `eff` disable a `policy` or `hook` record that is enabled now?); `registry_source_filtered(source)` -> `lgl(1)` (a whole `builtin:`/`plugin:` source disabled; used by `ext_load()` and `ext_load_builtins()`).

Scopes apply in the order user, project, session; `+<key>` in a later scope removes a key an earlier scope set. A `+builtin:<name>` filter calls `ext_load_builtins()` (Task 10) when built-ins are declared, so a built-in skipped at load comes back. Setting a scope replaces its filters, so inside a run two paths could remove a policy or hook: a new `-` filter (refused per filter) and dropping a `+` filter that undid an earlier scope's `-` (the dropped `+` is kept and reported in `refused`; IC-53). A malformed filter is `gptr_error_invalid_argument`; a well-formed filter whose prefix is neither `builtin`, `plugin` nor a registered kind is kept with a `filter_unknown_kind` diagnostic, because a kind that a lazy plugin defines on activation does not exist yet when the settings layer applies the user's filters (an error there would break every `peter()` call of that user).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ext-registry.R`:

```r
local_builtins = function(env = parent.frame()) {
  old = the$builtins
  withr::defer(assign("builtins", old, envir = the), envir = env)
  the$builtins = list()
  invisible(NULL)
}

test_that("-kind:name hides a record and +kind:name restores it", {
  local_registry()
  local_builtins()
  registry_add(cmd("grep"), "builtin:tools", 6L)
  expect_equal(gptr_registry()$state, "active")
  registry_filters_set("-command:grep", "session")
  expect_null(registry_get("command", "grep"))
  expect_equal(gptr_registry("command")$state, "disabled")
  expect_equal(gptr_registry()$state, "disabled")
  registry_filters_set("+command:grep", "session")
  expect_false(is.null(registry_get("command", "grep")))
  expect_equal(gptr_registry()$state, "active")
})

test_that("a later scope's + undoes an earlier scope's -", {
  local_registry()
  local_builtins()
  registry_add(cmd("grep"), "builtin:tools", 6L)
  registry_filters_set("-command:grep", "user")
  expect_null(registry_get("command", "grep"))
  out = registry_filters_set("+command:grep", "session")
  expect_false("command:grep" %in% out)
  expect_false(is.null(registry_get("command", "grep")))
})

test_that("-builtin:<name> and -plugin:<name> disable every record of that source", {
  local_registry()
  local_builtins()
  registry_add(cmd("a"), "builtin:mcp", 6L)
  registry_add(cmd("b"), "plugin:panel", 5L)
  registry_filters_set(c("-builtin:mcp", "-plugin:panel"), "user")
  expect_null(registry_get("command", "a"))
  expect_null(registry_get("command", "b"))
  expect_true(registry_source_filtered("builtin:mcp"))
  expect_true(registry_source_filtered("plugin:panel"))
  registry_filters_set(character(), "user")
  expect_false(is.null(registry_get("command", "a")))
})

test_that("no filter from user settings, a call or gptr_config() disables the kernel (IC-53)", {
  local_registry()
  local_builtins()
  registry_add(gptr_policy("mode", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_policy("critical_guard", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_policy("plan", function(call, ctx) NULL), "builtin:plan", 6L)
  bad = c("-builtin:permissions", "-builtin:plan", "-policy:critical_guard",
          "-policy:secret_guard", "-builtin:secrets")
  for (scope in c("user", "session", "project")) {
    out = registry_filters_set(bad, scope)
    expect_setequal(attr(out, "refused"), bad)
    expect_length(out, 0L)
  }
  registry_filters_set("-policy:mode", "user")
  expect_length(registry_all("policy"), 3L)
  expect_false(registry_source_filtered("builtin:permissions"))
  d = gptr_registry(diagnostics = TRUE)
  expect_equal(sum(d$class == "filter_refused"), 15L)
})

test_that("project filters never disable user or built-in policies and hooks", {
  local_registry()
  local_builtins()
  registry_add(gptr_policy("mine", function(call, ctx) NULL), "user", 3L)
  registry_add(gptr_policy("theirs", function(call, ctx) NULL), "plugin:p", 5L)
  registry_add(gptr_hook("tool_call", function(event, ctx) NULL), "builtin:audit", 6L)
  registry_filters_set(c("-policy:mine", "-policy:theirs", "-builtin:audit"), "project")
  expect_equal(names(registry_all("policy")), "mine")
  expect_length(registry_all("hook"), 1L)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_limited"))
  registry_filters_set("-policy:mine", "user")
  expect_length(registry_all("policy"), 0L)
})

test_that("inside a run, filters that remove policies or hooks are refused (IC-53)", {
  reg = local_registry()
  local_builtins()
  registry_add(gptr_policy("no_installs", function(call, ctx) NULL), "user", 3L)
  registry_add(cmd("x"), "user", 3L)
  reg$runs = "u1"
  out = registry_filters_set(c("-policy:no_installs", "-command:x"), "session")
  expect_equal(attr(out, "refused"), "-policy:no_installs")
  expect_length(registry_all("policy"), 1L)
  expect_null(registry_get("command", "x"))
  reg$runs = character()
  registry_filters_set("-policy:no_installs", "session")
  expect_length(registry_all("policy"), 0L)
})

test_that("inside a run, dropping a + that keeps a policy enabled is refused (IC-53)", {
  reg = local_registry()
  local_builtins()
  registry_add(gptr_policy("audit", function(call, ctx) NULL), "user", 3L)
  registry_add(cmd("x"), "user", 3L)
  registry_filters_set("-policy:audit", "user")
  registry_filters_set(c("+policy:audit", "+command:x"), "session")
  expect_length(registry_all("policy"), 1L)
  reg$runs = "u1"
  out = registry_filters_set(character(), "session")
  expect_equal(attr(out, "refused"), "+policy:audit")
  expect_length(registry_all("policy"), 1L)
  expect_equal(reg$filters$session, "+policy:audit")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_refused" & grepl("+policy:audit", d$message, fixed = TRUE)))
  reg$runs = character()
  registry_filters_set(character(), "session")
  expect_length(registry_all("policy"), 0L)
})

test_that("malformed filters are an invalid argument", {
  local_registry()
  expect_error(registry_filters_set("builtin:mcp", "user"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set("-Tool:x", "user"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set("-tool:grep", "global"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set(NA_character_, "user"), class = "gptr_error_invalid_argument")
})

test_that("a filter on a kind not defined yet is kept with a diagnostic (plugin kinds)", {
  local_registry()
  local_builtins()
  out = registry_filters_set("-reviewer:stats", "user")
  expect_equal(as.character(out), "reviewer:stats")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_unknown_kind" & grepl("reviewer", d$message, fixed = TRUE)))
  kind_define("reviewer", validate = function(spec) spec, source = "plugin:panel")
  registry_add(gptr_spec("reviewer", "stats"), "plugin:panel", 5L)
  registry_add(gptr_spec("reviewer", "style"), "plugin:panel", 5L)
  expect_equal(registry_names("reviewer"), "style")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-registry")'`
Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 81 ]`, from errors such as `could not find function "registry_filters_set"` (the first new test's opening `gptr_registry()` expectation passes before its `registry_filters_set()` call fails).

- [ ] **Step 3: Write the implementation**

Append to `R/ext-registry.R`:

```r
# ---- setting filters (contract 7.2 registry_filters_set, 10.1; IC-53) ---------------------------

#' The form of a filter string: a sign, a prefix (builtin, plugin or a kind) and a name
#' @noRd
registry_filter_rx = "^[+-][a-z][a-z0-9_]*:[^[:space:]]+$"

#' The effective filters: names are filter keys, values the scope that set them. Scopes apply in
#' the order user, project, session; "+key" removes a key set by an earlier scope
#' @noRd
registry_filters_effective = function(filters) {
  eff = character()
  for (scope in c("user", "project", "session")) {
    for (f in filters[[scope]]) {
      key = substring(f, 2L)
      if (!startsWith(f, "-")) {
        eff = eff[names(eff) != key]
      } else if (!(key %in% names(eff)) || identical(eff[[key]], "project")) {
        eff[key] = scope
      }
    }
  }
  eff
}

#' Is a whole source (builtin:<name>, plugin:<name>) disabled by a filter?
#' @noRd
registry_source_filtered = function(source, reg = registry_env()) {
  if (registry_source_protected(source)) return(FALSE)
  if (startsWith(source, "builtin:") && substring(source, 9L) %in% registry_protected_builtins()) {
    return(FALSE)
  }
  source %in% names(reg$eff)
}

#' Does a filter key match an enabled policy or hook record?
#' @noRd
registry_filter_hits_policy = function(key, reg) {
  for (k in c("policy", "hook")) {
    for (r in registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))) {
      if (registry_source_protected(r$source) || registry_rec_filtered(r, reg)) next
      if (identical(key, paste0(r$kind, ":", r$name)) || identical(key, r$source)) return(TRUE)
    }
  }
  FALSE
}

#' Would the effective filters `eff` disable a policy or hook record that is enabled now?
#' @noRd
registry_drops_guard = function(reg, eff) {
  for (k in c("policy", "hook")) {
    for (r in registry_recs(reg, get0(k, envir = reg$by_kind, inherits = FALSE))) {
      if (!registry_rec_filtered(r, reg) && registry_rec_filtered(r, reg, eff)) return(TRUE)
    }
  }
  FALSE
}

#' Why a filter is refused, or NULL (IC-53)
#' @noRd
registry_filter_refusal = function(f, reg) {
  if (!startsWith(f, "-")) return(NULL)
  key = substring(f, 2L)
  protected = c(paste0("builtin:", registry_protected_builtins()), "policy:critical_guard",
                "policy:secret_guard")
  if (key %in% protected) {
    return("the permission kernel and non-replaceable built-ins cannot be disabled by filters")
  }
  if (length(reg$runs) && registry_filter_hits_policy(key, reg)) {
    return("filters that remove policy or hook records are refused while a run is active")
  }
  NULL
}

#' Set the filters of one scope (contract 7.2; IC-53). Returns the effective filter keys
#' invisibly, with attribute "refused" naming the refused filters
#' @noRd
registry_filters_set = function(filters, scope = c("session", "user", "project")) {
  check_strings(filters, "filters")
  scope = check_choice(scope, c("session", "user", "project"), "scope")
  reg = registry_env()
  ok_form = grepl(registry_filter_rx, filters, perl = TRUE)
  if (!all(ok_form)) {
    gptr_abort(paste0("Invalid filter; use -builtin:<name>, -plugin:<name> or -<kind>:<name>, ",
                      "and a leading + to undo one."),
               "invalid_argument", arg = "filters",
               expected = "filters of the form -builtin:<name>, -plugin:<name>, -<kind>:<name>")
  }
  # A kind that a lazy plugin defines on activation does not exist yet when the settings layer
  # applies the user's filters: keep the filter (it applies once the kind exists) and note it
  prefix = sub("^[+-]([a-z][a-z0-9_]*):.*$", "\\1", filters, perl = TRUE)
  for (f in filters[!(prefix %in% c("builtin", "plugin", kind_names()))]) {
    registry_diagnostic(paste0("filters:", scope), "filter", "filter_unknown_kind",
                        paste0(f, " names a kind that is not registered (yet)"))
  }
  keep = character()
  refused = character()
  for (f in filters) {
    why = registry_filter_refusal(f, reg)
    if (is.null(why)) {
      keep = c(keep, f)
    } else {
      refused = c(refused, f)
      registry_diagnostic(paste0("filters:", scope), "filter", "filter_refused",
                          paste0(f, " refused: ", why))
    }
  }
  if (identical(scope, "project")) {
    for (f in keep[startsWith(keep, "-")]) {
      if (registry_filter_hits_policy(substring(f, 2L), reg)) {
        registry_diagnostic("filters:project", "filter", "filter_limited",
                            paste0(f, " does not apply to user or built-in policy and hook ",
                                   "records"))
      }
    }
  }
  if (length(reg$runs)) {
    old = reg$filters[[scope]]
    dropped = setdiff(old[startsWith(old, "+")], keep)
    retained = character()
    for (f in dropped) {
      trial = reg$filters
      trial[[scope]] = c(keep, setdiff(dropped, f))
      if (registry_drops_guard(reg, registry_filters_effective(trial))) {
        retained = c(retained, f)
        registry_diagnostic(paste0("filters:", scope), "filter", "filter_refused",
                            paste0("dropping ", f, " refused: it keeps a policy or hook record ",
                                   "enabled while a run is active"))
      }
    }
    keep = c(keep, retained)
    refused = c(refused, retained)
  }
  reg$filters[[scope]] = keep
  reg$eff = registry_filters_effective(reg$filters)
  registry_touch(reg)
  if (any(startsWith(keep, "+builtin:")) && length(the$builtins)) ext_load_builtins()
  out = names(reg$eff) %||% character()
  attr(out, "refused") = refused
  invisible(out)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-registry")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 124 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-registry.R tests/testthat/test-ext-registry.R
git commit -m "feat(ext): add registry filters"
```

---

### Task 6: Factory API object, `gptr_api()` and deprecations

**Files:**
- Create: `R/ext-api.R`, `R/ext-check.R`
- Modify: `NAMESPACE`, `man/gptr_api.Rd` (generated)
- Test: `tests/testthat/test-ext-api.R` (create), `tests/testthat/test-ext-check.R` (create)

**Interfaces:**
- Consumes: Tasks 1-5 (`registry_add()`, `registry_remove()`, `kind_names()`, `gptr_spec()`, `gptr_hook()`, `ev_table`, `ext_api_version`); P01 `gptr_deprecated(what, since, instead = NULL)`, `check_list()`.
- Produces: `ext_api_new(source, dir = NULL, manifest = NULL)` -> a `gptr_extension_api` (04 §5.6, §10.5): members `name`, `dir`, `state`, `register(spec)` (staged while `info$status == "loading"`, else committed; returns an unregister function invisibly), `register_<kind>(...)` for every registered kind, `on(event, handler, matcher = NULL)`, `require(requires)`, `has(feature)`; `$<-`/`[[<-` refuse with `gptr_error_readonly`; `ext_info_new(source, dir = NULL, manifest = NULL)` (the extension record: `id`, `source`, `dir`, `manifest`, `rank`, `session`, `status`, `stage`, `ids`, `placeholders`, `factory`, `lazy`, `lazy_origin`, `api`, `unloaded`); `api_build(info, reg)`; `ext_commit_one(info, spec)`; `ext_register(info, spec)`; `api_satisfies(requires, provided = package_version(ext_api_version), plugin = "?")`, `api_require(requires, plugin)`, `api_parse_requires(requires, plugin = "?")` (an unparsable requirement is `gptr_error_api_version` naming the requiring plugin); `ext_state(info)`; the export `gptr_api()` -> `gptr_api` list (`version`, `features`); `ext_deprecations()` (empty in API 1.0) and `ext_warn_deprecated(object, name)`.

`ext_register()` calls `kind_stage()` from Task 9 only while a factory is loading; before Task 9 API objects only exist outside factories.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-api.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("the API object exposes name, dir, state and the verbs; it refuses assignment", {
  local_registry()
  api = ext_api_new("plugin:demo", dir = tempdir())
  expect_s3_class(api, "gptr_extension_api")
  expect_equal(api$name, "plugin:demo")
  expect_equal(api$dir, tempdir())
  api$state$n = 1L
  expect_equal(api$state$n, 1L)
  expect_identical(ext_api_new("plugin:demo")$state, api$state)
  err = expect_error({
    api$register = NULL
  }, class = "gptr_error_readonly")
  expect_equal(err$field, "register")
  expect_error({
    api[["newthing"]] = 1
  }, class = "gptr_error_readonly")
  err = expect_error(api$register_widget, class = "gptr_error_unknown_member")
  expect_true("register_tool" %in% err$available)
  expect_output(print(api), "<gptr_extension_api 1.0> plugin:demo", fixed = TRUE)
})

test_that("register() commits outside a factory and returns an unregister function", {
  local_registry()
  api = ext_api_new("user")
  off = api$register(gptr_command("hi", function(args, ctx) "hi"))
  expect_equal(registry_get("command", "hi")$handler("", NULL), "hi")
  expect_equal(gptr_registry("command")$source, "user")
  off()
  expect_null(registry_get("command", "hi"))
  expect_error(api$register(list(kind = "command")), class = "gptr_error_invalid_spec")
})

test_that("register_<kind>() is gptr_spec() sugar for every kind, including plugin kinds", {
  local_registry()
  api = ext_api_new("plugin:demo")
  for (k in kind_names()) expect_true(is.function(api[[paste0("register_", k)]]))
  api$register_tool("add", description = "Add numbers", fun = function(a, b) a + b)
  expect_equal(registry_get("tool", "add")$fun(1, 2), 3)
  api$register_adapter("wire", api = "wire", transport = "inprocess",
                       stream = function(model, context, opts) function() NULL)
  expect_equal(registry_get("adapter", "wire")$transport, "inprocess")
  api$register_env_alias("JEV_API_KEY", aliases = "jev-key")
  expect_equal(registry_get("env_alias", "JEV_API_KEY")$aliases, "jev-key")
  api$register_kind("reviewer", validate = function(spec) spec, resolve = "all")
  api$register_reviewer("stats", focus = "statistics")
  expect_equal(registry_all("reviewer")$stats$focus, "statistics")
  api$on("myplugin:done", function(event, ctx) NULL)
  expect_length(registry_all("hook"), 1L)
  expect_equal(registry_all("hook")[[1]]$event, "myplugin:done")
})

test_that("require() uses caret semantics and has() tests features", {
  local_registry()
  api = ext_api_new("plugin:demo")
  expect_true(api$require("1.0")) # nolint: object_usage_linter.
  expect_true(api$require(">= 1.0, < 2")) # nolint: object_usage_linter.
  err = expect_error(api$require(">= 2.0"), # nolint: object_usage_linter.
                     class = "gptr_error_api_version")
  expect_equal(err$plugin, "plugin:demo")
  expect_equal(err$required, ">= 2.0")
  expect_equal(err$available, "1.0")
  expect_error(api$require("1.9"), class = "gptr_error_api_version") # nolint: object_usage_linter.
  err = expect_error(api$require("one"), # nolint: object_usage_linter.
                     class = "gptr_error_api_version")
  expect_equal(err$plugin, "plugin:demo")
  expect_true(api$has("kind.router"))
  expect_true(api$has("event.tool_call"))
  expect_false(api$has("kind.widget"))
})

test_that("api_satisfies() implements the requirement grammar (report G1 3.5)", {
  expect_true(api_satisfies("1"))
  expect_true(api_satisfies("1.0"))
  expect_false(api_satisfies("1.2"))
  expect_false(api_satisfies("0.9"))
  expect_true(api_satisfies("== 1.0"))
  expect_false(api_satisfies("< 1"))
  expect_false(api_satisfies(">= 1.0, < 1.0"))
  expect_true(api_satisfies("> 0.9"))
  expect_true(api_satisfies("<= 1.0"))
})

test_that("an API object bound to a replaced registry is stale", {
  local_registry()
  api = ext_api_new("plugin:demo")
  local_registry()
  err = expect_error(api$has("kind.tool"), class = "gptr_error_stale_api")
  expect_equal(err$plugin, "plugin:demo")
  expect_equal(err$generation, 1L)
})

test_that("gptr$state is shared by a plugin source and private to each user-level load", {
  local_registry()
  a = ext_api_new("user")
  b = ext_api_new("user")
  a$state$n = 1L
  expect_null(b$state$n)
  expect_identical(ext_api_new("builtin:demo")$state, ext_api_new("builtin:demo")$state)
})
```

Create `tests/testthat/test-ext-check.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("gptr_api() reports version 1.0 and the kind, event and named features", {
  local_registry()
  api = gptr_api()
  expect_s3_class(api, "gptr_api")
  expect_identical(api$version, package_version("1.0"))
  expect_true(all(paste0("kind.", kind_names()) %in% api$features))
  expect_true(all(paste0("event.", ev_catalogue()$event) %in% api$features))
  expect_true(all(c("lazy_activation", "declarations", "ctx.decide", "ctx.secret", "route",
                    "services") %in% api$features))
  expect_true("kind.router" %in% api$features)
  expect_false("kind.interpreter" %in% api$features)
  expect_output(print(api), "<gptr_api 1.0>", fixed = TRUE)
  kind_define("interpreter", validate = function(spec) spec, source = "builtin:bridges")
  expect_true("kind.interpreter" %in% gptr_api()$features)
})

test_that("a deprecated API member warns once, or errors for plugin CI (contract 10.9)", {
  local_registry()
  withr::defer(rm(list = grep("^warning:deprecated:", ls(the$once), value = TRUE),
                  envir = the$once))
  expect_false(ext_warn_deprecated("api", "register"))
  local_mocked_bindings(ext_deprecations = function() {
    list(api = list(has = list(since = "1.1", instead = "gptr$require()"),
                    require = list(since = "1.1", instead = "gptr$has()")),
         ctx = list())
  })
  api = ext_api_new("plugin:old")
  expect_warning(api$has("kind.tool"), class = "gptr_warning_deprecated")
  expect_no_warning(api$has("kind.tool"))
  withr::local_options(gptr.deprecations = "error")
  err = expect_error(api$require("1.0"), # nolint: object_usage_linter.
                     class = "gptr_error_deprecated")
  expect_match(conditionMessage(err), "gptr$require", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-api|ext-check")'`
Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 0 ]`, from errors such as `could not find function "ext_api_new"`, `could not find function "api_satisfies"` and `could not find function "gptr_api"`.

- [ ] **Step 3: Write the implementation**

Create `R/ext-api.R`:

```r
# ext-api.R -- the factory API object (contract 5.6, 10.5) and the ctx object handlers receive
# (contract 5.6, 10.6). Both are classed environments. No binding is locked (IC-26, rule R5): the
# `$<-` and `[[<-` methods refuse assignment instead. Shapes follow the verified G1 prototype
# (report G1 3.3, 5.1 api_new() and session_ctx(), 5.3), minus its binding locks, with the
# verification-log fix of row 25 (one-component requirements such as "2" become "2.0").

# ---- the factory API object (contract 5.6, 10.5) ------------------------------------------------

#' A new extension record (one per ext_load() or ext_api_new() call)
#'
#' `ids` are the committed record ids, `placeholders` the ids of lazy placeholders, `stage` the
#' registrations staged while the factory runs; `unloaded = TRUE` makes its API object stale.
#' @noRd
ext_info_new = function(source, dir = NULL, manifest = NULL) {
  reg = registry_env()
  reg$ext_seq = reg$ext_seq + 1L
  info = new.env(parent = emptyenv())
  info$id = paste0("e", reg$ext_seq)
  info$source = source
  info$dir = dir
  info$manifest = manifest
  info$rank = ext_source_rank(source)
  info$session = NULL
  info$status = "active"
  info$stage = list()
  info$ids = character()
  info$placeholders = character()
  info$factory = NULL
  info$lazy = FALSE
  info$lazy_origin = FALSE
  info$api = NULL
  info$unloaded = FALSE
  assign(info$id, info, envir = reg$exts)
  info
}

#' Rank of a source string (contract 10.1)
#' @noRd
ext_source_rank = function(source) {
  if (startsWith(source, "builtin:")) return(6L)
  if (startsWith(source, "plugin:")) return(5L)
  switch(source, session = 0L, project = 1L, user = 3L, 3L)
}

#' The process-lifetime state environment behind `gptr$state` (contract 10.5): one per plugin or
#' built-in source; extensions loaded as session, user or project code get one per load
#' @noRd
ext_state = function(info) {
  key = if (info$source %in% c("session", "user", "project")) info$id else info$source
  reg = registry_env()
  st = get0(key, envir = reg$states, inherits = FALSE)
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    assign(key, st, envir = reg$states)
  }
  st
}

#' Signal gptr_error_stale_api unless the API object is still current
#' @noRd
api_alive = function(info, reg, gen) {
  current = identical(the$registry, reg) && identical(reg$generation, gen) && !isTRUE(info$unloaded)
  if (!current) {
    gptr_abort(paste0("This extension API object of ", info$source, " is stale: the registry was ",
                      "reloaded or the extension was unloaded. Use the API object passed to the ",
                      "current factory call."),
               "stale_api", plugin = info$source, generation = gen)
  }
  invisible(TRUE)
}

#' Commit one spec for an extension; returns the record id
#' @noRd
ext_commit_one = function(info, spec) {
  reg = registry_env()
  prev = reg$current_ext
  reg$current_ext = info$id
  on.exit({
    reg$current_ext = prev
  }, add = TRUE)
  id = registry_add(spec, source = info$source, rank = info$rank, session = info$session)
  info$ids = c(info$ids, id)
  id
}

#' The unregister closure of one registration (cancels it while staged)
#' @noRd
ext_item_unregister = function(item) {
  force(item)
  function() {
    if (is.null(item$id)) item$cancelled = TRUE else registry_remove(item$id)
    invisible(TRUE)
  }
}

#' The register() verb: staged while the factory runs, committed directly afterwards (10.5)
#' @noRd
ext_register = function(info, spec) {
  if (!inherits(spec, "gptr_spec")) {
    gptr_abort("register() needs a spec made by gptr_spec() or a gptr_*() constructor.",
               "invalid_spec", kind = "?", name = "?", field = "spec",
               problem = "is not a gptr_spec")
  }
  item = new.env(parent = emptyenv())
  item$spec = spec
  item$id = NULL
  item$cancelled = FALSE
  if (identical(info$status, "loading")) {
    if (identical(spec$kind, "kind")) kind_stage(spec, info$id, info$source)
    info$stage = c(info$stage, list(item))
  } else {
    item$id = ext_commit_one(info, spec)
  }
  invisible(ext_item_unregister(item))
}

#' Parse an API requirement: "1.2" is caret (>= 1.2, < 2); otherwise comma-separated
#' "op version" with op in >=, >, <=, <, == (report G1 3.5; "2" is normalised to "2.0")
#' @noRd
api_parse_requires = function(requires, plugin = "?") {
  parts = trimws(strsplit(requires, ",", fixed = TRUE)[[1]])
  lapply(parts, function(p) {
    m = regmatches(p, regexec("^(>=|<=|==|>|<)?\\s*([0-9]+(\\.[0-9]+)*)$", p, perl = TRUE))[[1]]
    if (!length(m)) {
      gptr_abort(paste0("Cannot parse the API requirement '", p, "'."), "api_version",
                 plugin = plugin, required = requires, available = ext_api_version)
    }
    v = if (grepl(".", m[[3]], fixed = TRUE)) m[[3]] else paste0(m[[3]], ".0")
    list(op = if (nzchar(m[[2]])) m[[2]] else "^", v = package_version(v))
  })
}

#' Does this API satisfy a requirement string? (`plugin` names the requirer in parse errors)
#' @noRd
api_satisfies = function(requires, provided = package_version(ext_api_version), plugin = "?") {
  for (cn in api_parse_requires(requires, plugin)) {
    ok = switch(cn$op,
                ">=" = provided >= cn$v, ">" = provided > cn$v, "<=" = provided <= cn$v,
                "<" = provided < cn$v, "==" = provided == cn$v,
                "^" = provided >= cn$v && provided$major == cn$v$major)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

#' gptr$require(): signal gptr_error_api_version when unmet
#' @noRd
api_require = function(requires, plugin) {
  check_string(requires, "requires")
  if (!api_satisfies(requires, plugin = plugin)) {
    gptr_abort(paste0(plugin, " requires gptr extension API ", requires, ", but this gptr ",
                      "provides API ", ext_api_version, "."),
               "api_version", plugin = plugin, required = requires, available = ext_api_version)
  }
  invisible(TRUE)
}

#' The register_<kind>() sugar: gptr$register(gptr_spec("<kind>", ...)) (contract 10.5)
#' @noRd
api_sugar = function(api, kind) {
  force(api)
  force(kind)
  function(...) api$register(gptr_spec(kind, ...))
}

#' Member names of an API object
#' @noRd
api_members = function(x) {
  c("name", "dir", "state", "register", paste0("register_", kind_names()), "on", "require", "has")
}

#' Build the API object of an extension record
#' @noRd
api_build = function(info, reg) {
  gen = reg$generation
  api = new.env(parent = emptyenv())
  api$name = info$source
  api$dir = info$dir
  api$state = ext_state(info)
  api$register = function(spec) {
    api_alive(info, reg, gen)
    ext_register(info, spec)
  }
  api$on = function(event, handler, matcher = NULL) {
    api_alive(info, reg, gen)
    ext_register(info, gptr_hook(event, handler, matcher))
  }
  api$require = function(requires) {
    api_alive(info, reg, gen)
    api_require(requires, info$source)
  }
  api$has = function(feature) {
    api_alive(info, reg, gen)
    check_string(feature, "feature")
    feature %in% gptr_api()$features
  }
  class(api) = "gptr_extension_api"
  info$api = api
  api
}

#' The API object handed to a factory (contract 7.2)
#' @noRd
ext_api_new = function(source, dir = NULL, manifest = NULL) {
  check_string(source, "source")
  check_string(dir, "dir", null = TRUE)
  check_list(manifest, "manifest", null = TRUE)
  info = ext_info_new(source, dir, manifest)
  api_build(info, registry_env())
}

#' Get an API member; register_<kind> sugar exists for every registered kind
#' @export
#' @noRd
`$.gptr_extension_api` = function(x, name) {
  ext_warn_deprecated("api", name)
  if (exists(name, envir = x, inherits = FALSE)) return(get(name, envir = x, inherits = FALSE))
  if (startsWith(name, "register_") && substring(name, 10L) %in% kind_names()) {
    return(api_sugar(x, substring(name, 10L)))
  }
  gptr_abort(paste0("The gptr extension API ", ext_api_version, " has no member '", name,
                    "'; test with gptr$has() or require a newer API."),
             "unknown_member", name = name, available = api_members(x))
}

#' Get an API member by name
#' @export
#' @noRd
`[[.gptr_extension_api` = function(x, i, ...) `$.gptr_extension_api`(x, i)

#' The API object is read-only except for re-assigning its own state environment (IC-26)
#' @export
#' @noRd
`$<-.gptr_extension_api` = function(x, name, value) {
  if (identical(name, "state") && identical(value, get("state", envir = x, inherits = FALSE))) {
    return(x)
  }
  gptr_abort(paste0("The gptr extension API object is read-only; '", name, "' cannot be ",
                    "assigned. Keep extension state in gptr$state."),
             "readonly", object = "gptr_extension_api", field = name)
}

#' The API object is read-only (IC-26)
#' @export
#' @noRd
`[[<-.gptr_extension_api` = function(x, i, value) `$<-.gptr_extension_api`(x, i, value)

#' Print an API object: its version, source and members
#' @export
#' @noRd
print.gptr_extension_api = function(x, ...) {
  cat("<gptr_extension_api ", ext_api_version, "> ", get("name", envir = x), "\n", sep = "")
  cat("members: ", paste(api_members(x), collapse = ", "), "\n", sep = "")
  invisible(x)
}
```

Create `R/ext-check.R`:

```r
# ext-check.R -- the extension API version and features (contract 6.7 gptr_api()), the
# deprecation helper for API members (contract 10.9; architecture 3.2, 11.4) and the gptr_check()
# conformance suites for specs, factories and installed plugin packages (contract 6.7, 7.2;
# IC-42, IC-69). No network: adapter fixture replay is the `check.adapter` service of P12.

#' Extension API version and features
#'
#' The version of gptr's public extension API (independent of the package version) and the
#' features this build offers: `kind.<name>` for every registered kind, `event.<name>` for every
#' catalogued event, and the named features `lazy_activation`, `declarations`, `ctx.decide`,
#' `ctx.secret`, `route` and `services`. Plugins test features instead of comparing versions.
#'
#' @return A `gptr_api` list with `version` (a `package_version`) and `features` (character).
#' @examples
#' gptr_api()$version
#' "kind.router" %in% gptr_api()$features
#' @export
gptr_api = function() {
  structure(list(version = package_version(ext_api_version),
                 features = c(paste0("kind.", kind_names()), paste0("event.", ev_table$event),
                              "lazy_activation", "declarations", "ctx.decide", "ctx.secret",
                              "route", "services")),
            class = "gptr_api")
}

#' Print the API version and the number of features
#' @export
#' @noRd
print.gptr_api = function(x, ...) {
  cat("<gptr_api ", format(x$version), "> ", length(x$features), " features\n", sep = "")
  invisible(x)
}

#' Deprecated members of the API object ("api") and of ctx ("ctx"): member -> list(since,
#' instead). Extension API 1.0 deprecates nothing; a MINOR release adds entries here and keeps the
#' member for at least one MINOR release and six months (contract 10.9)
#' @noRd
ext_deprecations = function() list(api = list(), ctx = list())

#' Warn once per session about a deprecated member (an error with
#' options(gptr.deprecations = "error")); FALSE when the member is not deprecated
#' @noRd
ext_warn_deprecated = function(object, name) {
  dep = ext_deprecations()[[object]][[name]]
  if (is.null(dep)) return(invisible(FALSE))
  prefix = if (identical(object, "api")) "gptr$" else "ctx$"
  gptr_deprecated(paste0(prefix, name), dep$since, dep$instead)
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'`, then `Rscript --vanilla -e 'devtools::test(filter = "ext-api|ext-check")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 98 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-api.R R/ext-check.R tests/testthat/test-ext-api.R tests/testthat/test-ext-check.R \
  NAMESPACE man/gptr_api.Rd
git commit -m "feat(ext): add the extension API object and gptr_api()"
```

---

### Task 7: `ctx` and services

**Files:**
- Modify: `R/ext-api.R` (append), `NAMESPACE` (generated)
- Test: `tests/testthat/test-ext-api.R` (append)

**Interfaces:**
- Consumes: P01 `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_get(name)`, `ext_service_has(name)`, `redact_hook(x, profile)`, `est_tokens()`; Task 4 `registry_get()`; Task 6 `ext_warn_deprecated()`; the services of 04 §7.0 `ctx.kernel` (P06), `ctx.input`, `session.add_tools` (P07), `ui.get`, `risk.classify` (P11), `secret.lookup` (P03), `eval.r`, `describe` (P09), `s1.decide` (P13), `agent_def.get` (P17).
- Produces (04 §5.6, §10.6): `ctx_new(session, run = NULL)` -> `gptr_ctx` with every member of 04 §10.6 and IC-11/IC-69 (`session`, active bindings `envir`, `run`, `input`; `mode()`, `model()`, `has_ui()`, `ui()`, `risk(code, kind = "r")`, `redact(x, profile = "persist")`, `secret(name)`, `execute_tool(name, input)`, `send(text, as = c("steer", "follow_up"))`, `set_model(ref, thinking = NULL, reason = "plugin")`, `add_tools(specs)`, `tokens(x, class = "prose")`, `eval(code, envir = NULL)`, `describe(x, budget = 150L)`, `append_entry(type, data)`, `abort(reason)`, `aborted()`, `update(text)`, `decide(question, x, ...)`, `usage()`, `state()`, `emit(channel, data)`, `get(kind, name)`); `ext_service_try(name, session = NULL)` -> the function of a `service` record (session-scoped first) or of P01's table (one `ext_service_get()` lookup), or `NULL`; `ctx_default(session)`; `ctx_source(ctx)`, `ctx_with_source(ctx, source, fun)` (the source a handler runs for, or `NULL`); `ctx_ui_none()` (the `none` UI: `has_ui()` is `FALSE`, `select()` answers `NA`, `permission()` denies).
- The `ctx.kernel` contract P06 implements (`ctx_kernel()` in P06's `agent-run.R`): `function() named list` whose functions are called as `impl(ctx, ...)` with positional arguments: `envir(ctx)`, `run(ctx)`, `mode(ctx)`, `model(ctx)`, `execute_tool(ctx, name, input)`, `send(ctx, text, as[, extension])`, `set_model(ctx, ref, thinking, reason)`, `append_entry(ctx, type, data[, extension])`, `abort(ctx, reason)`, `aborted(ctx)`, `update(ctx, text)`, `usage(ctx)`, `state(ctx[, extension])`. The optional last argument of the three plugin-scoped members is the source of the handler that called the member (`ctx_source(ctx)`, for example `"plugin:panel"`); it is passed positionally and only inside a handler, so P06's default (`extension = NULL`, labelled `"plugin"`) applies otherwise. This is exactly what `dev/plan/P06-session-kernel-agent-loop.md` implements: its `ctx_kernel()` names the argument `extension`, derives the label with `ctx_ext_label()` (`"plugin:panel"` -> `"panel"`), labels `extension` queue items with it (IC-55) and keys `gptr.ext` state and `customType` `"<label>.<type>"` by it.

`ctx$emit()` calls `ev_dispatch()` from Task 8.

Tests that assert a "not available" fallback or a member's behaviour without a kernel call `local_no_bootstrap_services()` after `local_registry()`: later plans register their services in P01's bootstrap table from `on_load()`, and an empty scratch registry makes P01's `service_builtin_active()` count every built-in as active, so these tests would otherwise fail in the full suite once P06 (`ctx.kernel`), P07, P09, P11, P13 or P17 is loaded (self-review item 28).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ext-api.R`:

```r
local_service = function(name, fun, env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), "user", 3L)
  withr::defer(registry_remove(id), envir = env)
  invisible(id)
}

local_bootstrap_service = function(name, fun, env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = env)
  ext_service_set(name, fun, provided_by = "P02-test")
}

# Hide P01's bootstrap service table for one test (as P01's local_services() does). Later plans
# register services there from on_load() (ctx.kernel P06, session.add_tools P07, describe and
# eval.r P09, risk.classify P11, s1.decide P13, agent_def.get P17, ...), and with the empty scratch
# registry of local_registry() P01's service_builtin_active() counts every built-in as active, so a
# test of a "not available" fallback must empty the table itself to hold in the full suite.
local_no_bootstrap_services = function(env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = env)
  assign("services", list(), envir = the)
  invisible(NULL)
}

test_that("ctx members whose plan is not loaded signal gptr_error_not_available", {
  local_registry()
  local_no_bootstrap_services()
  ctx = ctx_new(NULL)
  expect_s3_class(ctx, "gptr_ctx")
  err = expect_error(ctx$mode(), class = "gptr_error_not_available")
  expect_equal(err$member, "ctx$mode()")
  expect_equal(err$provided_by, "P06")
  expect_error(ctx$execute_tool("read", list(path = "x")), class = "gptr_error_not_available")
  expect_error(ctx$abort("stop"), class = "gptr_error_not_available")
  expect_error(ctx$send("note"), class = "gptr_error_not_available")
  expect_equal(expect_error(ctx$risk("x = 1"))$provided_by, "P11")
  expect_equal(expect_error(ctx$describe(1))$provided_by, "P09")
  expect_equal(expect_error(ctx$eval("1"))$provided_by, "P09")
  expect_equal(expect_error(ctx$decide("Is it?", 1))$provided_by, "P13")
  expect_equal(expect_error(ctx$add_tools(list()))$provided_by, "P07")
  expect_null(ctx$session)
  expect_null(ctx$envir)
  expect_null(ctx$run)
  expect_null(ctx$input)
  expect_null(ctx$secret("ANTHROPIC_API_KEY"))
  expect_false(ctx$has_ui())
  expect_equal(ctx$ui()$name, "none")
  expect_true(is.na(ctx$ui()$select("Pick", c("a", "b"))))
  expect_equal(ctx$ui()$permission(list(tool = "r"))$decision, "deny")
})

test_that("ctx members call the P06 kernel with the ctx first, lazily at call time", {
  local_registry()
  local_no_bootstrap_services()
  s = new.env()
  s$id = "s1"
  ctx = ctx_new(s, run = "u7")
  expect_identical(ctx$session, s)
  expect_equal(ctx$run, "u7")
  log = new.env()
  # the argument names and defaults of P06's ctx_kernel(): the handler's source is optional and
  # last (`extension`), and P06 labels it as P06's ctx_ext_label() does ("plugin:panel" -> "panel")
  label = function(extension) {
    if (is.null(extension)) "plugin" else sub("^[A-Za-z_]+:", "", extension)
  }
  local_service("ctx.kernel", function() {
    list(mode = function(ctx) "auto", model = function(ctx) "fake/fake-1",
         envir = function(ctx) globalenv(), run = function(ctx) "u8",
         execute_tool = function(ctx, name, input) paste(name, input$path),
         send = function(ctx, text, as = c("steer", "follow_up"), extension = NULL) {
           log$send = c(text, as, extension %||% "none")
         },
         set_model = function(ctx, ref, thinking = NULL, reason = "plugin") {
           log$model = c(ref, reason)
         },
         append_entry = function(ctx, type, data, extension = NULL) {
           paste0(label(extension), ".", type)
         },
         abort = function(ctx, reason = "plugin") log$abort = reason,
         aborted = function(ctx) TRUE, update = function(ctx, text) log$update = text,
         usage = function(ctx) data.frame(),
         state = function(ctx, extension = NULL) {
           log$state_of = label(extension)
           log
         })
  })
  expect_equal(ctx$mode(), "auto")
  expect_equal(ctx$model(), "fake/fake-1")
  expect_identical(ctx$envir, globalenv())
  expect_equal(ctx$run, "u8")
  expect_equal(ctx$execute_tool("read", list(path = "a.R")), "read a.R")
  ctx$send("use TPM")
  expect_equal(log$send, c("use TPM", "steer", "none"))
  ctx_with_source(ctx, "plugin:panel", function() ctx$send("note", as = "follow_up"))
  expect_equal(log$send, c("note", "follow_up", "plugin:panel"))
  expect_error(ctx$send("x", as = "later"), class = "gptr_error_invalid_argument")
  ctx$set_model("fake/fake-2")
  expect_equal(log$model, c("fake/fake-2", "plugin"))
  expect_equal(ctx$append_entry("note", list()), "plugin.note")
  expect_equal(ctx_with_source(ctx, "plugin:panel", function() ctx$append_entry("note", list())),
               "panel.note")
  ctx$abort("enough")
  expect_equal(log$abort, "enough")
  expect_true(ctx$aborted())
  ctx$update("50%")
  expect_equal(log$update, "50%")
  expect_identical(ctx$state(), log)
  expect_equal(log$state_of, "plugin")
  ctx_with_source(ctx, "builtin:documents", function() ctx$state())
  expect_equal(log$state_of, "documents")
  expect_s3_class(ctx$usage(), "data.frame")
})

test_that("ctx services: ui, risk, secret, tokens, eval, describe, decide, add_tools, input", {
  local_registry()
  local_no_bootstrap_services()
  ctx = ctx_new("s1")
  expect_null(ctx$session)
  local_service("ui.get", function(session = NULL) {
    gptr_spec("ui", "scripted", has_ui = function() TRUE, select = function(...) 1L)
  })
  expect_true(ctx$has_ui())
  expect_equal(ctx$ui()$name, "scripted")
  local_service("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    list(level = 2L, kind = kind)
  })
  expect_equal(ctx$risk("x = 1", kind = "r")$level, 2L)
  local_service("secret.lookup", function(name) paste0("<secret ", name, ">"))
  expect_equal(ctx$secret("JEV"), "<secret JEV>")
  expect_equal(ctx$tokens("abcdefgh"), est_tokens("abcdefgh", "prose"))
  registry_add(gptr_spec("estimator", "default", estimate = function(x, class) 42),
               "plugin:est", 5L)
  expect_equal(ctx$tokens("abc"), 42)
  local_service("eval.r", function(code, envir, ...) list(code = code, envir = envir))
  e = new.env()
  expect_identical(ctx$eval("1 + 1", envir = e)$envir, e)
  expect_error(ctx$eval("1"), class = "gptr_error_invalid_argument")
  local_service("describe", function(x, budget) paste("described", budget))
  expect_equal(ctx$describe(1), "described 150")
  local_service("s1.decide", function(question, x, ...) TRUE)
  expect_true(ctx$decide("Is it?", 1))
  local_service("session.add_tools", function(s, specs) NULL)
  expect_null(ctx$add_tools(list()))
  local_service("ctx.input", function(ctx) list(turn = 1L))
  expect_equal(ctx$input, list(turn = 1L))
  expect_equal(ctx$redact("abc"), "abc")
  expect_null(ctx$get("command", "nope"))
  registry_add(gptr_command("mine", function(args, ctx) "x"), "session", 0L, session = "s1")
  expect_equal(ctx$get("command", "mine")$name, "mine")
  expect_null(ctx_new("s2")$get("command", "mine"))
})

test_that("ctx refuses assignment, reports unknown members and prints", {
  local_registry()
  ctx = ctx_new(NULL)
  expect_error({
    ctx$mode = function() "auto"
  }, class = "gptr_error_readonly")
  expect_error({
    ctx[["x"]] = 1
  }, class = "gptr_error_readonly")
  err = expect_error(ctx$nope, class = "gptr_error_unknown_member")
  expect_true("decide" %in% err$available)
  expect_output(print(ctx), "<gptr_ctx> session none", fixed = TRUE)
  expect_identical(ctx_default(NULL), ctx_default(NULL))
})

test_that("a service record replaces the bootstrap service of the same name (IC-34)", {
  local_registry()
  local_bootstrap_service("p02.test.echo", function() "bootstrap")
  expect_equal(ext_service_try("p02.test.echo")(), "bootstrap")
  expect_equal(ext_service_get("p02.test.echo")(), "bootstrap")
  local_service("p02.test.echo", function() "record")
  expect_equal(ext_service_try("p02.test.echo")(), "record")
  expect_equal(ext_service_get("p02.test.echo")(), "record")
  expect_null(ext_service_try("p02.test.absent"))
  registry_add(gptr_spec("service", "p02.test.session", fun = function() "mine"), "session", 0L,
               session = "s1")
  expect_equal(ext_service_try("p02.test.session", "s1")(), "mine")
  expect_null(ext_service_try("p02.test.session", "s2"))
})

test_that("generated member functions call execute() with the process ctx", {
  local_registry()
  m = gptr_tool("double", "Double a number", exposure = "r",
                parameters = list(type = "object", required = I("x"),
                                  properties = list(x = list(type = "number"),
                                                    note = list(type = "string"))),
                execute = function(input, ctx) {
                  if (input$x < 0) {
                    gptr_tool_result("negative", is_error = TRUE)
                  } else {
                    gptr_tool_result("ok", value = 2 * input$x)
                  }
                })
  expect_equal(names(formals(m$fun)), c("x", "note"))
  expect_null(formals(m$fun)$note)
  expect_equal(m$fun(4), 8)
  err = expect_error(m$fun(-1), class = "gptr_error_tool")
  expect_equal(err$tool, "double")
  expect_match(conditionMessage(err), "negative", fixed = TRUE)
  dyn = gptr_tool("echo", "Echo", exposure = "r", parameters = function(ctx) list(type = "object"),
                  execute = function(input, ctx) gptr_tool_result(input$text))
  expect_equal(dyn$fun(text = "hi"), "hi")
})

test_that("gptr_agent(name) loads a definition through agent_def.get, else not available", {
  local_registry()
  local_no_bootstrap_services()
  err = expect_error(gptr_agent("reviewer"), class = "gptr_error_not_available")
  expect_equal(err$provided_by, "P17")
  expect_error(gptr_agent(), class = "gptr_error_invalid_argument")
  local_service("agent_def.get", function(name, file = NULL) {
    gptr_agent(name, description = "loaded from a file")
  })
  expect_equal(gptr_agent("reviewer")$description, "loaded from a file")
})

test_that("a deprecated ctx member warns through the same helper (contract 10.9)", {
  local_registry()
  withr::defer(rm(list = grep("^warning:deprecated:", ls(the$once), value = TRUE),
                  envir = the$once))
  local_mocked_bindings(ext_deprecations = function() {
    list(api = list(), ctx = list(usage = list(since = "1.1", instead = "gptr_usage()")))
  })
  ctx = ctx_new(NULL)
  expect_warning(ctx$usage, class = "gptr_warning_deprecated")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-api")'`
Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 91 ]`, from errors such as `could not find function "ctx_new"` and `could not find function "ext_service_try"`.

- [ ] **Step 3: Write the implementation**

Append to `R/ext-api.R`:

```r
# ---- ctx (contract 5.6, 10.6) --------------------------------------------------------------------
# ctx members fetch their services lazily, at call time, through the registry `service` kind and
# P01's service table (IC-09, IC-34); a member whose service has not arrived signals
# gptr_error_not_available. Members marked P06 in contract 10.6 are implemented by the
# `ctx.kernel` service: a named list of functions called as impl(ctx, ...).

# ---- services and ctx --------------------------------------------------------------------------

#' A service function or NULL: a `service` registry record first (it may be session-scoped),
#' then P01's bootstrap table (IC-34), looked up once
#' @noRd
ext_service_try = function(name, session = NULL) {
  spec = registry_get("service", name, session)
  if (!is.null(spec)) return(spec[["fun"]])
  tryCatch(ext_service_get(name), gptr_error_not_available = function(e) NULL)
}

#' gptr_error_not_available for a ctx member whose provider plan is not loaded
#' @noRd
ctx_unavailable = function(member, plan) {
  gptr_abort(paste0(member, " is not available: its provider (plan ", plan, ") is not loaded or ",
                    "is disabled."),
             "not_available", member = member, provided_by = plan)
}

#' A required service for a ctx member
#' @noRd
ctx_service = function(ctx, name, member, plan) {
  f = ext_service_try(name, get(".sid", envir = ctx, inherits = FALSE))
  if (is.null(f)) ctx_unavailable(member, plan)
  f
}

#' The P06 implementation of a ctx member from the `ctx.kernel` service, or NULL
#' @noRd
ctx_kernel_impl = function(ctx, member) {
  k = ext_service_try("ctx.kernel", get(".sid", envir = ctx, inherits = FALSE))
  if (is.null(k)) return(NULL)
  impl = k()[[member]]
  if (is.function(impl)) impl else NULL
}

#' Call a kernel member: impl(ctx, ...) (P06 implementations take the ctx first)
#' @noRd
ctx_call = function(ctx, member, ...) {
  impl = ctx_kernel_impl(ctx, member)
  if (is.null(impl)) ctx_unavailable(paste0("ctx$", member, "()"), "P06")
  impl(ctx, ...)
}

#' The `none` UI used before a UI backend is registered (contract 10.6): nobody answers
#' @noRd
ctx_ui_none = function() {
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    NA_integer_
  }
  permission = function(request) list(decision = "deny", remember = NULL, feedback = NULL)
  gptr_spec("ui", "none", has_ui = function() FALSE, select = select, permission = permission)
}

#' The extension source a handler runs for (set by ev_dispatch() around each handler)
#' @noRd
ctx_source = function(ctx) get0(".source", envir = ctx, inherits = FALSE)

#' Call a plugin-scoped kernel member: the handler's source (`"plugin:panel"`) is passed last,
#' positionally, and only when the member runs for a handler, so the kernel's default applies
#' otherwise (P06 names that argument `extension` and derives the label "panel" itself)
#' @noRd
ctx_call_plugin = function(ctx, member, ...) {
  src = ctx_source(ctx)
  if (is.null(src)) ctx_call(ctx, member, ...) else ctx_call(ctx, member, ..., src)
}

#' Run `fun()` with the ctx attributed to `source`, restoring the previous source
#' @noRd
ctx_with_source = function(ctx, source, fun) {
  if (is.null(ctx)) return(fun())
  old = ctx_source(ctx)
  assign(".source", source, envir = ctx)
  on.exit(assign(".source", old, envir = ctx), add = TRUE)
  fun()
}

#' Member names of a ctx (contract 10.6)
#' @noRd
ctx_members = c("session", "envir", "run", "input", "mode", "model", "has_ui", "ui", "risk",
                "redact", "secret", "execute_tool", "send", "set_model", "add_tools", "tokens",
                "eval", "describe", "append_entry", "abort", "aborted", "update", "decide",
                "usage", "state", "emit", "get")

#' The ctx of a session (one per session; contract 7.2, 10.6)
#'
#' `session` is a session object, a session id, or NULL for process-level dispatch; `run` is the
#' run (or run id) whose tool is executing. Members marked P06 in contract 10.6 call the
#' `ctx.kernel` implementations as impl(ctx, ...); send(), append_entry() and state() add the
#' source of the handler that called them as their last argument (ctx_call_plugin()).
#' @noRd
ctx_new = function(session, run = NULL) {
  ctx = new.env(parent = emptyenv())
  ctx$session = if (is.character(session)) NULL else session
  ctx$.sid = ext_session_id(session)
  ctx$.run = if (is.character(run) && length(run) == 1L) run else ext_session_id(run)
  ctx$.source = NULL
  sid = function() get(".sid", envir = ctx, inherits = FALSE)
  makeActiveBinding("envir", function() {
    impl = ctx_kernel_impl(ctx, "envir")
    if (is.null(impl)) NULL else impl(ctx)
  }, ctx)
  makeActiveBinding("run", function() {
    impl = ctx_kernel_impl(ctx, "run")
    if (is.null(impl)) get(".run", envir = ctx, inherits = FALSE) else impl(ctx)
  }, ctx)
  makeActiveBinding("input", function() {
    f = ext_service_try("ctx.input", sid())
    if (is.null(f)) NULL else f(ctx)
  }, ctx)
  ctx$mode = function() ctx_call(ctx, "mode")
  ctx$model = function() ctx_call(ctx, "model")
  ctx$ui = function() {
    f = ext_service_try("ui.get", sid())
    if (is.null(f)) ctx_ui_none() else f(get("session", envir = ctx, inherits = FALSE))
  }
  ctx$has_ui = function() {
    ui = ctx$ui()
    isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))
  }
  ctx$risk = function(code, kind = "r") {
    ctx_service(ctx, "risk.classify", "ctx$risk()", "P11")(code, envir = ctx$envir, kind = kind)
  }
  ctx$redact = function(x, profile = "persist") redact_hook(x, profile)
  ctx$secret = function(name) {
    check_string(name, "name")
    f = ext_service_try("secret.lookup", sid())
    if (is.null(f)) NULL else f(name)
  }
  ctx$execute_tool = function(name, input) ctx_call(ctx, "execute_tool", name, input)
  ctx$send = function(text, as = c("steer", "follow_up")) {
    check_strings(text, "text")
    as = check_choice(as, c("steer", "follow_up"), "as")
    ctx_call_plugin(ctx, "send", text, as)
    invisible(NULL)
  }
  ctx$set_model = function(ref, thinking = NULL, reason = "plugin") {
    ctx_call(ctx, "set_model", ref, thinking, reason)
    invisible(NULL)
  }
  ctx$add_tools = function(specs) {
    f = ctx_service(ctx, "session.add_tools", "ctx$add_tools()", "P07")
    f(get("session", envir = ctx, inherits = FALSE), specs)
    invisible(NULL)
  }
  ctx$tokens = function(x, class = "prose") {
    est = registry_get("estimator", "default", sid())
    if (is.null(est)) est_tokens(x, class) else est$estimate(x, class)
  }
  ctx$eval = function(code, envir = NULL) {
    f = ctx_service(ctx, "eval.r", "ctx$eval()", "P09")
    where = envir %||% ctx$envir
    if (is.null(where)) {
      gptr_abort("ctx$eval() needs `envir` when the session has no evaluation environment.",
                 "invalid_argument", arg = "envir", expected = "an environment")
    }
    f(code, envir = where)
  }
  ctx$describe = function(x, budget = 150L) {
    ctx_service(ctx, "describe", "ctx$describe()", "P09")(x, budget)
  }
  ctx$append_entry = function(type, data) {
    check_string(type, "type")
    ctx_call_plugin(ctx, "append_entry", type, data)
  }
  ctx$abort = function(reason) ctx_call(ctx, "abort", reason)
  ctx$aborted = function() isTRUE(ctx_call(ctx, "aborted"))
  ctx$update = function(text) ctx_call(ctx, "update", text)
  ctx$decide = function(question, x, ...) {
    ctx_service(ctx, "s1.decide", "ctx$decide()", "P13")(question, x, ...)
  }
  ctx$usage = function() ctx_call(ctx, "usage")
  ctx$state = function() ctx_call_plugin(ctx, "state")
  ctx$emit = function(channel, data) {
    if (!ev_is_channel(channel)) {
      gptr_abort("ctx$emit() needs a channel named '<plugin>:<topic>'.", "invalid_argument",
                 arg = "channel", expected = "a <plugin>:<topic> channel name")
    }
    ev_dispatch(channel, list(data = data), session = get("session", envir = ctx) %||% sid(),
                ctx = ctx)
    invisible(NULL)
  }
  ctx$get = function(kind, name) registry_get(kind, name, sid())
  class(ctx) = "gptr_ctx"
  ctx
}

#' The ctx used for a dispatch whose caller passed none: the process ctx for session-less
#' dispatch, else a ctx for that session (sessions pass their own ctx; contract 10.6)
#' @noRd
ctx_default = function(session) {
  if (!is.null(session)) return(ctx_new(session))
  reg = registry_env()
  if (is.null(reg$ctx0)) reg$ctx0 = ctx_new(NULL)
  reg$ctx0
}

#' Get a ctx member; unknown names signal gptr_error_unknown_member
#' @export
#' @noRd
`$.gptr_ctx` = function(x, name) {
  ext_warn_deprecated("ctx", name)
  if (exists(name, envir = x, inherits = FALSE)) return(get(name, envir = x, inherits = FALSE))
  gptr_abort(paste0("ctx has no member '", name, "'."), "unknown_member", name = name,
             available = ctx_members)
}

#' Get a ctx member by name
#' @export
#' @noRd
`[[.gptr_ctx` = function(x, i, ...) `$.gptr_ctx`(x, i)

#' ctx is read-only (IC-26)
#' @export
#' @noRd
`$<-.gptr_ctx` = function(x, name, value) {
  gptr_abort(paste0("ctx is read-only; '", name, "' cannot be assigned. Keep per-session state in ",
                    "ctx$state()."),
             "readonly", object = "gptr_ctx", field = name)
}

#' ctx is read-only (IC-26)
#' @export
#' @noRd
`[[<-.gptr_ctx` = function(x, i, value) `$<-.gptr_ctx`(x, i, value)

#' Print a ctx: its session id and members
#' @export
#' @noRd
print.gptr_ctx = function(x, ...) {
  sid = get(".sid", envir = x, inherits = FALSE)
  cat("<gptr_ctx> session ", sid %||% "none", "\n", sep = "")
  cat("members: ", paste(ctx_members, collapse = ", "), "\n", sep = "")
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'` (adds the `$`, `[[`, `$<-`, `[[<-` and `print` methods of `gptr_ctx`), then `Rscript --vanilla -e 'devtools::test(filter = "ext-api")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 172 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-api.R tests/testthat/test-ext-api.R NAMESPACE
git commit -m "feat(ext): add ctx and service binding"
```

---

### Task 8: Event dispatch, hooks and policies

**Files:**
- Modify: `R/ext-events.R` (append)
- Test: `tests/testthat/test-ext-events.R` (append)

**Interfaces:**
- Consumes: Task 1 (`ev_table`, `ev_semantics()`, `ev_check_name()`, `ev_is_channel()`), Task 4 (`registry_add()`, `registry_remove()`, `registry_recs()`, `registry_visible()`, `registry_sort()`, `registry_rec_filtered()`, `registry_diagnostic()`, `registry_session_drop()`, `ext_session_id()`), Task 7 (`ctx_default()`, `ctx_with_source()`, `ctx_new()` in tests); P01 `redact_hook()`.
- Produces (04 §7.2, §10.7): `ev_dispatch(event, payload, session = NULL, ctx = NULL)` returning `NULL` (notify), the merged list (collect), `list(action, text)` (transform), `list(decision = "allow" | "block" | "modify", reason, input)` (`tool_call`; a handler error or an answer with an unknown `decision`, such as `"deny"`, blocks with a `malformed_decision` diagnostic for the latter), the first non-empty list answer or `NULL` (first decision; non-list returns such as the value of a logging assignment have no opinion; a failing `permission_request` handler answers `list(decision = "deny", reason)`), the patched payload (patch chain; `tool_result` patches only `content`, `details`, `is_error`; `request_params` only `params`, whose keys are merged so that a handler can add a declared key that is unset, while P06's `run_request_params()` drops keys the adapter does not declare), `list(block, reason, lines)` (`document_write`); handlers see `type`, `session`, `ts` and a copy redacted with the `stream` profile (opaque replay fields untouched); `session_shutdown` drops the session's records after its handlers ran (IC-69); `agent_start`/`agent_end` and `tool_execution_start`/`tool_execution_end` update the run and executing-tool mirrors that Tasks 4-5 read (IC-53); the `tool_execution_end` of a top-level call (a `tool_call_id` without `/`; nested calls are `<outer>/<k>`) also drops the run's unused `ext_control_grant()` grants, so the one-shot approval covers exactly the approved call, as P06's `tool_execute_frame()` clears `run$signal$control` when the call ends. `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)` -> id; `hook_remove(id)`; `ext_policy_decide(spec, call, ctx = NULL)` -> `NULL` or `list(decision, reason, input)` (the single-policy fail-closed evaluator of 04 §10.2 row 12, the G1 check "a throwing policy denies": an error or a malformed answer denies; P06's `perm_policies()` evaluates and combines policies itself, IC-04, so no later plan depends on this helper); `ext_policy_ok(r)` (the well-formedness test that `gptr_check()`'s policy matrix uses: decision `allow`, `deny`, `ask`, `ask_human` (IC-53 item 6; 04 §7.6 combines deny > ask_human > ask > modify > allow, and P11's built-in policies answer it) or `modify` with an input list; `ext_policy_decide()` returns an `ask_human` unchanged).

Handlers run in order: session listeners (rank 0), then hooks by rank and registration (04 §10.7); a matcher is `NULL`, a tool-name glob (converted with `utils::glob2rx()` and matched with `perl = TRUE`, G1 verification row 9) or a predicate. `ev_hooks()` activates lazy hook placeholders through `ext_activate_record()` (Task 9).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ext-events.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("notify runs listeners then hooks by rank; a handler error is a diagnostic", {
  local_registry()
  log = new.env()
  log$seen = character()
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "builtin"), rank = 6L,
           source = "builtin:demo")
  hook_add("turn_end", function(event, ctx) stop("hook bug"), rank = 3L, source = "user")
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "session"), rank = 0L,
           source = "session", session = "s1")
  hook_add("turn_end", function(event, ctx) log$seen = c(log$seen, "other"), rank = 0L,
           source = "session", session = "s2")
  expect_null(ev_dispatch("turn_end", list(message = NULL), session = "s1"))
  expect_equal(log$seen, c("session", "builtin"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "user" & d$event == "turn_end" & grepl("hook bug", d$message)))
})

test_that("events without handlers return the neutral result of their semantics", {
  local_registry()
  expect_null(ev_dispatch("agent_start", list()))
  expect_equal(ev_dispatch("session_start", list(reason = "new")), list())
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt")),
               list(action = "continue", text = "hi"))
  expect_equal(ev_dispatch("tool_call", list(tool_name = "r", input = list(code = "1"))),
               list(decision = "allow", reason = NULL, input = list(code = "1")))
  expect_null(ev_dispatch("permission_request", list(tool = "r")))
  expect_equal(ev_dispatch("document_write", list(lines = c("a", "b"))),
               list(block = FALSE, reason = NULL, lines = c("a", "b")))
  expect_error(ev_dispatch("PreToolUse", list()), class = "gptr_error_invalid_argument")
})

test_that("collect merges named lists (earlier wins) and concatenates the rest, capped", {
  local_registry()
  hook_add("session_start", function(event, ctx) {
    list(sections = list(house = "A", keep = NULL), blocks = list(list(text = "x")))
  }, rank = 0L, source = "session", session = "s1")
  hook_add("session_start", function(event, ctx) {
    list(sections = list(house = "B", extra = "C"), blocks = list(list(text = "y")))
  })
  res = ev_dispatch("session_start", list(reason = "new"), session = "s1")
  expect_equal(res$sections$house, "A")
  expect_equal(res$sections$extra, "C")
  expect_true("keep" %in% names(res$sections))
  expect_length(res$blocks, 2L)
  hook_add("session_start", function(event, ctx) {
    list(blocks = list(list(text = strrep("z", 9000L)), list(text = strrep("w", 2000L))))
  })
  res = ev_dispatch("session_start", list(reason = "new"), session = "s1")
  total = sum(vapply(res$blocks, function(b) nchar(b$text), 0))
  expect_lte(total, 10000)
  expect_true(any(gptr_registry(diagnostics = TRUE)$class == "context_cap"))
})

test_that("the input transform chain replaces text and stops at handled", {
  local_registry()
  hook_add("input", function(event, ctx) list(action = "transform", text = toupper(event$text)))
  hook_add("input", function(event, ctx) list(action = "transform", text = paste(event$text, "!")))
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt")),
               list(action = "transform", text = "HI !"))
  hook_add("input", function(event, ctx) list(action = "handled"), rank = 0L, source = "session",
           session = "s1")
  expect_equal(ev_dispatch("input", list(text = "hi", source = "prompt"), session = "s1")$action,
               "handled")
})

test_that("tool_call: modify flows on, block stops, and a throwing hook blocks (fail closed)", {
  local_registry()
  hook_add("tool_call", function(event, ctx) {
    list(decision = "modify", input = list(code = paste0(event$input$code, " + 1")))
  })
  res = ev_dispatch("tool_call", list(tool_name = "r", tool_call_id = "c1",
                                      input = list(code = "1")))
  expect_equal(res$decision, "modify")
  expect_equal(res$input, list(code = "1 + 1"))
  hook_add("tool_call", function(event, ctx) stop("hook bug"), source = "plugin:bad", rank = 5L)
  res = ev_dispatch("tool_call", list(tool_name = "r", tool_call_id = "c1",
                                      input = list(code = "1")))
  expect_equal(res$decision, "block")
  expect_match(res$reason, "plugin:bad failed: hook bug", fixed = TRUE)
})

test_that("tool_call: an unknown decision blocks; a non-list return has no opinion", {
  local_registry()
  log = new.env()
  hook_add("tool_call", function(event, ctx) log$seen = event$tool_name)
  call = list(tool_name = "r", tool_call_id = "c1", input = list(code = "1"))
  expect_equal(ev_dispatch("tool_call", call)$decision, "allow")
  expect_equal(log$seen, "r")
  hook_add("tool_call", function(event, ctx) list(decision = "deny", reason = "no installs"),
           source = "plugin:guard", rank = 5L)
  res = ev_dispatch("tool_call", call)
  expect_equal(res$decision, "block")
  expect_match(res$reason, "unknown decision", fixed = TRUE)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "malformed_decision" & d$source == "plugin:guard"))
  local_registry()
  hook_add("tool_call", function(event, ctx) list(decision = "modify", input = "x = 1"))
  expect_equal(ev_dispatch("tool_call", call)$decision, "block")
})

test_that("a throwing permission_request hook denies; the first answer wins", {
  local_registry()
  hook_add("permission_request", function(event, ctx) stop("reviewer down"))
  res = ev_dispatch("permission_request", list(tool = "r", tier = "ask"))
  expect_equal(res$decision, "deny")
  expect_match(res$reason, "reviewer down", fixed = TRUE)
  local_registry()
  hook_add("permission_request", function(event, ctx) NULL)
  hook_add("permission_request", function(event, ctx) list(decision = "allow", reason = "ok"))
  hook_add("permission_request", function(event, ctx) list(decision = "deny", reason = "late"))
  expect_equal(ev_dispatch("permission_request", list(tool = "r"))$reason, "ok")
})

test_that("a failing first-decision handler of another event is skipped", {
  local_registry()
  hook_add("session_before_fork", function(event, ctx) stop("bug"))
  hook_add("session_before_fork", function(event, ctx) list(cancel = TRUE, reason = "no"))
  expect_equal(ev_dispatch("session_before_fork", list(source = "s1", at = "e1"))$reason, "no")
})

test_that("first decision: non-list and empty returns have no opinion", {
  local_registry()
  log = new.env()
  log$n = 0L
  hook_add("session_before_compact", function(event, ctx) log$n = log$n + 1L)
  hook_add("session_before_compact", function(event, ctx) list())
  hook_add("session_before_compact", function(event, ctx) list(cancel = TRUE))
  res = ev_dispatch("session_before_compact", list(reason = "manual", tokens = 10))
  expect_equal(res, list(cancel = TRUE))
  expect_equal(log$n, 1L)
  local_registry()
  hook_add("permission_request", function(event, ctx) "yes")
  expect_null(ev_dispatch("permission_request", list(tool = "r")))
})

test_that("tool_result patches content, details and is_error only", {
  local_registry()
  hook_add("tool_result", function(event, ctx) {
    list(content = list(list(type = "text", text = "[patched]")), status = "ignored")
  })
  hook_add("tool_result", function(event, ctx) {
    expect_equal(event$content[[1]]$text, "[patched]")
    list(is_error = TRUE)
  })
  res = ev_dispatch("tool_result", list(tool_name = "r", tool_call_id = "c1", input = list(),
                                        content = list(list(type = "text", text = "raw")),
                                        details = NULL, is_error = FALSE))
  expect_equal(res$content[[1]]$text, "[patched]")
  expect_true(res$is_error)
  expect_null(res$status)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "patch_ignored" & grepl("status", d$message)))
})

test_that("request_params patches only `params`; unset declared keys can be added (IC-69)", {
  local_registry()
  hook_add("request_params", function(event, ctx) {
    list(params = list(service_tier = "flex", metadata = list(team = "lab")), model = "other")
  })
  hook_add("request_params", function(event, ctx) {
    expect_equal(event$params$service_tier, "flex")
    list(params = "not a list")
  })
  # P06 sends only the declared keys that are set: here service_tier, not metadata
  res = ev_dispatch("request_params", list(provider = "openai", model = "gpt",
                                           params = list(service_tier = "auto")))
  expect_equal(res$params, list(service_tier = "flex", metadata = list(team = "lab")))
  expect_equal(res$model, "gpt")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "patch_ignored" & grepl("model", d$message, fixed = TRUE)))
  expect_true(any(d$class == "patch_ignored" & grepl("named list", d$message, fixed = TRUE)))
})

test_that("document_write: lines patch, block stops, a throwing hook blocks", {
  local_registry()
  hook_add("document_write", function(event, ctx) list(lines = c(event$lines, "# footer")))
  res = ev_dispatch("document_write", list(path = "a.R", lines = "x = 1"))
  expect_false(res$block)
  expect_equal(res$lines, c("x = 1", "# footer"))
  hook_add("document_write", function(event, ctx) stop("disk policy bug"))
  res = ev_dispatch("document_write", list(path = "a.R", lines = "x = 1"))
  expect_true(res$block)
  expect_match(res$reason, "disk policy bug", fixed = TRUE)
})

test_that("matchers filter by tool-name glob or predicate", {
  local_registry()
  log = new.env()
  log$n = 0L
  hook_add("tool_execution_start", function(event, ctx) log$n = log$n + 1L, matcher = "mcp__*")
  hook_add("tool_execution_start", function(event, ctx) log$n = log$n + 10L,
           matcher = function(event) identical(event$tool_name, "r"))
  ev_dispatch("tool_execution_start", list(tool_name = "mcp__github__search", tool_call_id = "1"))
  ev_dispatch("tool_execution_start", list(tool_name = "r", tool_call_id = "2"))
  ev_dispatch("tool_execution_start", list(tool_name = "read", tool_call_id = "3"))
  expect_equal(log$n, 11L)
})

test_that("handlers see a stream-redacted copy with type and ts; opaque fields untouched", {
  local_registry()
  old = the$redactor
  withr::defer(assign("redactor", old, envir = the))
  redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  log = new.env()
  hook_add("message_end", function(event, ctx) log$ev = event)
  content = list(
    list(type = "text", text = "key sk-abc123"),
    list(type = "thinking", thinking = "t", signature = "sk-keepme1", redacted = TRUE,
         data = "sk-keepme2")
  )
  msg = list(role = "assistant", content = content)
  ev_dispatch("message_end", list(type = "message_end", role = "assistant", message = msg),
              session = "s9")
  expect_equal(log$ev$type, "message_end")
  expect_equal(names(log$ev)[[1]], "type")
  expect_equal(log$ev$session, "s9")
  expect_true(is.numeric(log$ev$ts))
  expect_equal(log$ev$message$content[[1]]$text, "key [secret:KEY]")
  expect_equal(log$ev$message$content[[2]]$signature, "sk-keepme1")
  expect_equal(log$ev$message$content[[2]]$data, "sk-keepme2")
})

test_that("handlers run with ctx attributed to their source; channels reach listeners", {
  local_registry()
  log = new.env()
  hook_add("myplugin:done", function(event, ctx) {
    log$data = event$data
    log$source = ctx_source(ctx)
  }, rank = 5L, source = "plugin:listener")
  ctx = ctx_new(NULL)
  ctx$emit("myplugin:done", list(n = 3L))
  expect_equal(log$data, list(n = 3L))
  expect_equal(log$source, "plugin:listener")
  expect_null(ctx_source(ctx))
  expect_error(ctx$emit("not a channel", 1), class = "gptr_error_invalid_argument")
})

test_that("session_shutdown drops the session's records after its handlers ran (IC-69)", {
  local_registry()
  log = new.env()
  hook_add("session_shutdown", function(event, ctx) log$reason = event$reason, rank = 0L,
           source = "session", session = "s1")
  registry_add(gptr_command("mine", function(args, ctx) "x"), source = "session", rank = 0L,
               session = "s1")
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
  ev_dispatch("session_shutdown", list(reason = "gc"), session = "s1")
  expect_equal(log$reason, "gc")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_length(get0("session_shutdown", envir = registry_env()$hooks), 0L)
})

test_that("runs and executing tools are tracked from agent and tool events (IC-53)", {
  reg = local_registry()
  ev_dispatch("agent_start", list(run = "u1"))
  ev_dispatch("agent_start", list(run = "u2"))
  expect_setequal(reg$runs, c("u1", "u2"))
  ev_dispatch("tool_execution_start", list(run = "u1", tool_call_id = "c1", tool_name = "r"))
  expect_error(gptr_register(gptr_command("x", function(args, ctx) NULL)),
               class = "gptr_error_permission")
  ev_dispatch("tool_execution_end", list(run = "u1", tool_call_id = "c1", tool_name = "r"))
  expect_length(reg$executing, 0L)
  ev_dispatch("tool_execution_start", list(run = "u2", tool_call_id = "c2", tool_name = "r"))
  ext_control_grant("u2", "gptr_reload")
  ev_dispatch("agent_end", list(run = "u2", status = "aborted"))
  expect_length(reg$executing, 0L)
  expect_length(reg$grants, 0L)
  expect_equal(reg$runs, "u1")
})

test_that("an unused control grant ends with the top-level call it was granted in (IC-53)", {
  reg = local_registry()
  ev_dispatch("agent_start", list(run = "u3"))
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c3", tool_name = "r"))
  ext_control_grant("u3", "gptr_register")
  # a nested call (id "<outer>/<k>") ends inside the approved call and keeps the grant
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c3/1", tool_name = "read"))
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c3/1", tool_name = "read"))
  expect_length(reg$grants, 1L)
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c3", tool_name = "r"))
  expect_length(reg$grants, 0L)
  # a later, unapproved call of the same run cannot use the approval
  ev_dispatch("tool_execution_start", list(run = "u3", tool_call_id = "c4", tool_name = "r"))
  err = expect_error(ext_control_guard("gptr_register"), class = "gptr_error_permission")
  expect_equal(err$action, "gptr_register")
  ev_dispatch("tool_execution_end", list(run = "u3", tool_call_id = "c4", tool_name = "r"))
  ev_dispatch("agent_end", list(run = "u3", status = "done"))
  expect_length(reg$runs, 0L)
})

test_that("hook_add validates names; hook_remove removes", {
  local_registry()
  expect_error(hook_add("PreToolUse", function(event, ctx) NULL),
               class = "gptr_error_invalid_argument")
  id = hook_add("turn_start", function(event, ctx) NULL)
  expect_true(hook_remove(id))
  expect_false(hook_remove(id))
})

test_that("a throwing policy denies; malformed answers deny; NULL has no opinion", {
  local_registry()
  call = list(id = "c1", name = "r", input = list(code = "1"))
  bad = gptr_policy("buggy", function(call, ctx) stop("policy bug"))
  res = ext_policy_decide(bad, call)
  expect_equal(res$decision, "deny")
  expect_match(res$reason, "policy 'buggy' failed: policy bug", fixed = TRUE)
  expect_true(any(gptr_registry(diagnostics = TRUE)$source == "policy:buggy"))
  expect_equal(ext_policy_decide(gptr_policy("odd", function(call, ctx) "yes"), call)$decision,
               "deny")
  expect_null(ext_policy_decide(gptr_policy("quiet", function(call, ctx) NULL), call))
  mod = gptr_policy("mod", function(call, ctx) list(decision = "modify", input = list(code = "2")))
  expect_equal(ext_policy_decide(mod, call)$input, list(code = "2"))
  ok = gptr_policy("ok", function(call, ctx) list(decision = "allow"))
  expect_equal(ext_policy_decide(ok, call), list(decision = "allow", reason = "",
                                                 input = list(code = "1")))
  # IC-53 item 6: the ask_human tier of the guards is a well-formed answer, kept unchanged
  human = gptr_policy("human", function(call, ctx) {
    list(decision = "ask_human", reason = "control")
  })
  expect_equal(ext_policy_decide(human, call), list(decision = "ask_human", reason = "control",
                                                    input = list(code = "1")))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-events")'`
Expected: errors such as `could not find function "hook_add"` and `could not find function "ev_dispatch"`, until testthat stops with `Maximum number of failures exceeded; quitting.`

- [ ] **Step 3: Write the implementation**

Append to `R/ext-events.R`:

```r
# ---- dispatch (contract 7.2, 10.7) --------------------------------------------------------------

#' Hook-injected context is capped at 10,000 characters per dispatch (contract 10.7)
#' @noRd
ev_cap = 10000L

#' Fields never redacted: byte-exact replay data (signatures, encrypted reasoning, opaque JSON)
#' @noRd
ev_opaque = c("signature", "thinking_signature", "thought_signature", "thoughtSignature",
              "text_signature", "textSignature", "encrypted_content", "json")

#' Does a block carry opaque binary or replay `data` (images, redacted thinking)?
#' @noRd
ev_opaque_data = function(x) {
  typ = x[["type"]]
  if (!is.character(typ) || length(typ) != 1L) return(FALSE)
  typ %in% c("image", "redacted_thinking") || (typ == "thinking" && isTRUE(x[["redacted"]]))
}

#' Redact every string of a payload with a profile, leaving opaque replay fields untouched
#' @noRd
ev_redact_payload = function(x, profile = "stream") {
  if (is.character(x)) return(redact_hook(x, profile))
  if (!is.list(x)) return(x)
  skip_data = ev_opaque_data(x)
  nms = names(x)
  for (i in seq_along(x)) {
    nm = if (is.null(nms)) "" else nms[[i]]
    if (nm %in% ev_opaque || (skip_data && identical(nm, "data"))) next
    v = x[[i]]
    if (is.character(v) || is.list(v)) x[i] = list(ev_redact_payload(v, profile))
  }
  x
}

#' The event record a handler sees: type first, session and ts filled, stream-redacted
#' @noRd
ev_view = function(event, payload, sid) {
  x = payload[setdiff(names(payload) %||% character(), "type")]
  x = c(list(type = event), x)
  if (is.null(x[["session"]])) x["session"] = list(sid)
  if (is.null(x[["ts"]])) x$ts = as.numeric(Sys.time())
  ev_redact_payload(x, "stream")
}

#' The result of an event without handlers
#' @noRd
ev_default = function(sem, payload) {
  switch(sem,
    collect = list(),
    transform = list(action = "continue", text = payload[["text"]]),
    decision = list(decision = "allow", reason = NULL, input = payload[["input"]]),
    patch = payload,
    block_patch = list(block = FALSE, reason = NULL, lines = payload[["lines"]]),
    NULL
  )
}

#' Mirror active runs and executing tools from the events P06 dispatches (IC-53): agent_start
#' and agent_end bracket a run; tool_execution_start and tool_execution_end bracket a tool. The
#' one-shot grants of a run (ext_control_grant()) end with the top-level call they were granted
#' in (a tool_call_id without "/"; nested calls are "<outer>/<k>"), as P06's tool_execute_frame()
#' clears run$signal$control, so an unused approval never reaches a later call
#' @noRd
ev_track = function(reg, event, payload) {
  run = payload[["run"]]
  run = if (is.character(run) && length(run) == 1L && !is.na(run)) run else NULL
  drop_grants = function() {
    keep = vapply(reg$grants, function(g) !identical(g$run, run), NA)
    reg$grants = reg$grants[keep]
  }
  if (identical(event, "agent_start") && !is.null(run)) reg$runs = union(reg$runs, run)
  if (identical(event, "agent_end") && !is.null(run)) {
    reg$runs = setdiff(reg$runs, run)
    reg$executing = reg$executing[reg$executing != run]
    drop_grants()
  }
  id = payload[["tool_call_id"]]
  if (is.character(id) && length(id) == 1L && !is.na(id)) {
    key = paste0(run %||% "", "\r", id)
    if (identical(event, "tool_execution_start")) reg$executing[[key]] = run %||% ""
    if (identical(event, "tool_execution_end")) {
      reg$executing = reg$executing[names(reg$executing) != key]
      if (!is.null(run) && !grepl("/", id, fixed = TRUE)) drop_grants()
    }
  }
  invisible(NULL)
}

#' Is a record a lazy placeholder?
#' @noRd
ev_lazy = function(rec) identical(rec$state, "lazy")

#' Hook records for an event: session listeners (rank 0) first, then by rank; lazy ones activated
#' @noRd
ev_hooks = function(reg, event, sid) {
  pick = function() {
    recs = registry_recs(reg, get0(event, envir = reg$hooks, inherits = FALSE))
    recs[vapply(recs, function(r) registry_visible(r, sid) && !registry_rec_filtered(r, reg),
                NA)]
  }
  recs = pick()
  lazy = recs[vapply(recs, ev_lazy, NA)]
  if (length(lazy)) {
    for (r in lazy) ext_activate_record(r)
    recs = pick()
    recs = recs[!vapply(recs, ev_lazy, NA)]
  }
  registry_sort(recs)
}

#' Does a hook's matcher accept the event (NULL, a tool-name glob, or a predicate)?
#' @noRd
ev_matches = function(matcher, ev) {
  if (is.null(matcher)) return(TRUE)
  if (is.function(matcher)) return(isTRUE(matcher(ev)))
  tool = ev[["tool_name"]]
  is.character(tool) && length(tool) == 1L && grepl(utils::glob2rx(matcher), tool, perl = TRUE)
}

#' Sentinel returned for a handler whose matcher did not match
#' @noRd
ev_skip = structure(list(), class = "gptr_ev_skip")

#' Call one hook handler with the ctx attributed to its source
#' @noRd
ev_call = function(rec, ev, ctx) {
  if (!ev_matches(rec$spec[["matcher"]], ev)) return(ev_skip)
  ctx_with_source(ctx, rec$source, function() rec$spec[["handler"]](ev, ctx))
}

#' Call a handler; an error becomes a diagnostic and the value `on_error` (or its result)
#' @noRd
ev_try = function(rec, ev, ctx, event, on_error = NULL) {
  tryCatch(ev_call(rec, ev, ctx), error = function(e) {
    registry_diagnostic(rec$source, event, class(e)[[1]], conditionMessage(e))
    if (is.function(on_error)) on_error(conditionMessage(e)) else on_error
  })
}

#' Is a handler return usable (a list, not the skip sentinel)?
#' @noRd
ev_usable = function(r) is.list(r) && !inherits(r, "gptr_ev_skip")

#' The reason a handler gave, as one string
#' @noRd
ev_reason = function(r, source) {
  paste(as.character(r[["reason"]] %||% paste0("blocked by a hook from ", source)), collapse = " ")
}

#' Merge a collect result: named lists merge with earlier handlers winning, others concatenate
#' @noRd
ev_merge = function(acc, r) {
  for (k in names(r)) {
    if (!nzchar(k)) next
    v = r[[k]]
    named = is.list(v) && length(v) && !is.null(names(v)) && all(nzchar(names(v)))
    if (named) {
      old = acc[[k]] %||% list()
      add = setdiff(names(v), names(old))
      old[add] = v[add]
      acc[[k]] = old
    } else if (!is.null(v)) {
      acc[[k]] = c(acc[[k]], v)
    }
  }
  acc
}

#' Cap hook-injected context blocks at ev_cap characters in total
#' @noRd
ev_cap_blocks = function(blocks, event) {
  if (!length(blocks)) return(blocks)
  size = function(b) {
    nchar(paste(as.character(if (is.list(b)) b[["text"]] else b), collapse = ""), type = "chars")
  }
  keep = cumsum(vapply(blocks, size, 0)) <= ev_cap
  if (!all(keep)) {
    registry_diagnostic("dispatch", event, "context_cap",
                        paste0("hook-injected blocks cut at ", ev_cap, " characters"))
  }
  blocks[keep]
}

#' Merge a handler's `params` patch into the current params (request_params, IC-69). The payload
#' holds only the declared request_params that are set, so a handler may add a declared key that
#' is unset (`metadata`, `user`); which keys the adapter accepts is known only to the emitter,
#' P06's run_request_params(), which drops undeclared keys with its own diagnostic
#' @noRd
ev_params_patch = function(old, new, rec, event) {
  old = old %||% list()
  ok = is.list(new) && !is.data.frame(new) &&
    (!length(new) || (!is.null(names(new)) && all(nzchar(names(new)))))
  if (!ok) {
    registry_diagnostic(rec$source, event, "patch_ignored", "params must be a named list")
    return(old)
  }
  for (k in names(new)) old[k] = list(new[[k]])
  old
}

#' notify: call every handler, ignore the returns
#' @noRd
ev_run_notify = function(hooks, ev, ctx, event, payload) {
  for (h in hooks) ev_try(h, ev, ctx, event)
  NULL
}

#' collect: merge the returned lists (injected blocks are capped)
#' @noRd
ev_run_collect = function(hooks, ev, ctx, event, payload) {
  acc = list()
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (ev_usable(r)) acc = ev_merge(acc, r)
  }
  if (!is.null(acc$blocks)) acc$blocks = ev_cap_blocks(acc$blocks, event)
  acc
}

#' transform chain: text flows through; "transform" replaces it, "handled" stops the chain
#' @noRd
ev_run_transform = function(hooks, ev, ctx, event, payload) {
  text = payload[["text"]]
  changed = FALSE
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (!ev_usable(r)) next
    if (identical(r[["action"]], "handled")) {
      if (is.character(r[["text"]])) text = paste(r[["text"]], collapse = "\n")
      return(list(action = "handled", text = text))
    }
    if (identical(r[["action"]], "transform") && is.character(r[["text"]])) {
      text = paste(r[["text"]], collapse = "\n")
      changed = TRUE
      ev$text = redact_hook(text, "stream")
    }
  }
  if (changed && nchar(text, type = "chars") > ev_cap) {
    text = substr(text, 1L, ev_cap)
    registry_diagnostic("dispatch", event, "context_cap",
                        paste0("transformed text cut at ", ev_cap, " characters"))
  }
  list(action = if (changed) "transform" else "continue", text = text)
}

#' decision (tool_call): the first block wins; modify patches the input; an error or an unknown
#' decision blocks (fail closed: list(decision = "deny") must not mean allow)
#' @noRd
ev_run_decision = function(hooks, ev, ctx, event, payload) {
  input = payload[["input"]]
  modified = FALSE
  for (h in hooks) {
    fail = function(msg) {
      list(decision = "block",
           reason = paste0("a ", event, " hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = fail)
    if (!ev_usable(r)) next
    d = r[["decision"]]
    if (identical(d, "block")) {
      return(list(decision = "block", reason = ev_reason(r, h$source), input = input))
    }
    if (identical(d, "modify") && is.list(r[["input"]])) {
      input = r[["input"]]
      modified = TRUE
      ev$input = ev_redact_payload(input, "stream")
    } else if (!is.null(d) && !identical(d, "allow")) {
      why = paste0("a ", event, " hook from ", h$source, " returned an unknown decision; return ",
                   "NULL, list(decision = \"block\", reason) or list(decision = \"modify\", input)")
      registry_diagnostic(h$source, event, "malformed_decision", why)
      return(list(decision = "block", reason = why, input = input))
    }
  }
  list(decision = if (modified) "modify" else "allow", reason = NULL, input = input)
}

#' first decision: the first non-empty list returned wins; a failing permission_request handler
#' denies. Returns are lists (contract 10.4); a non-list return (the value of a logging
#' assignment such as `log$n = log$n + 1`) has no opinion, so it neither hides the handlers after
#' it nor reaches emitters that read `res$cancel`
#' @noRd
ev_run_first = function(hooks, ev, ctx, event, payload) {
  for (h in hooks) {
    deny = function(msg) {
      if (!identical(event, "permission_request")) return(NULL)
      list(decision = "deny",
           reason = paste0("a permission_request hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = deny)
    if (!ev_usable(r) || !length(r)) next
    return(r)
  }
  NULL
}

#' patch chain: each handler sees the payload patched by the previous ones
#' @noRd
ev_run_patch = function(hooks, ev, ctx, event, payload) {
  cur = payload
  allowed = switch(event,
    tool_result = c("content", "details", "is_error"),
    request_params = "params",
    NULL
  )
  sid = ev[["session"]]
  for (h in hooks) {
    r = ev_try(h, ev, ctx, event)
    if (!ev_usable(r) || !length(r)) next
    fields = names(r) %||% character()
    if (!is.null(allowed)) {
      extra = setdiff(fields, allowed)
      if (length(extra)) {
        registry_diagnostic(h$source, event, "patch_ignored",
                            paste0("ignored fields: ", paste(extra, collapse = ", ")))
      }
      fields = intersect(fields, allowed)
    }
    if (identical(event, "request_params") && "params" %in% fields) {
      r$params = ev_params_patch(cur[["params"]], r[["params"]], h, event)
    }
    for (f in fields) cur[f] = list(r[[f]])
    ev = ev_view(event, cur, sid)
  }
  cur
}

#' block + patch (document_write): the first block wins; lines patch; an error blocks
#' @noRd
ev_run_block_patch = function(hooks, ev, ctx, event, payload) {
  lines = payload[["lines"]]
  for (h in hooks) {
    fail = function(msg) {
      list(block = TRUE, reason = paste0("a ", event, " hook from ", h$source, " failed: ", msg))
    }
    r = ev_try(h, ev, ctx, event, on_error = fail)
    if (!ev_usable(r)) next
    if (isTRUE(r[["block"]])) {
      return(list(block = TRUE, reason = ev_reason(r, h$source), lines = lines))
    }
    if (!is.null(r[["lines"]])) {
      lines = r[["lines"]]
      ev$lines = ev_redact_payload(lines, "stream")
    }
  }
  list(block = FALSE, reason = NULL, lines = lines)
}

#' Dispatch an event to session listeners, then registry hooks by rank (contract 7.2, 10.7)
#'
#' Returns NULL (notify), the merged list (collect), list(action, text) (transform),
#' list(decision, reason, input) (tool_call), the first answer or NULL (first decision), the
#' patched payload (patch) or list(block, reason, lines) (document_write). A session_shutdown
#' removes the session's records after its handlers ran (IC-69).
#' @noRd
ev_dispatch = function(event, payload, session = NULL, ctx = NULL) {
  check_string(event, "event")
  sem = ev_semantics(event)
  if (is.null(sem)) ev_check_name(event)
  payload = payload %||% list()
  reg = registry_env()
  sid = ext_session_id(session)
  ev_track(reg, event, payload)
  if (identical(event, "session_shutdown") && !is.null(sid)) {
    on.exit(registry_session_drop(sid), add = TRUE)
  }
  hooks = ev_hooks(reg, event, sid)
  if (!length(hooks)) return(ev_default(sem, payload))
  ctx = ctx %||% ctx_default(session)
  run = switch(sem,
    collect = ev_run_collect,
    transform = ev_run_transform,
    decision = ev_run_decision,
    first_decision = ev_run_first,
    patch = ev_run_patch,
    block_patch = ev_run_block_patch,
    ev_run_notify
  )
  run(hooks, ev_view(event, payload, sid), ctx, event, payload)
}

#' Register a hook record (contract 7.2); returns its id
#' @noRd
hook_add = function(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL) {
  ev_check_name(event)
  registry_add(gptr_hook(event, handler, matcher), source = source, rank = rank, session = session)
}

#' Remove a hook record (contract 7.2)
#' @noRd
hook_remove = function(id) registry_remove(id)

# ---- policies (contract 10.2 row 12) ------------------------------------------------------------

#' A well-formed policy decision: allow, deny, ask, ask_human (IC-53 item 6, combined as deny >
#' ask_human > ask > modify > allow by P06's perm_check(), 04 section 7.6), or modify with an
#' input list
#' @noRd
ext_policy_ok = function(r) {
  if (!is.list(r)) return(FALSE)
  d = r[["decision"]]
  known = c("allow", "deny", "ask", "ask_human", "modify")
  if (!is.character(d) || length(d) != 1L || !(d %in% known)) {
    return(FALSE)
  }
  !identical(d, "modify") || is.list(r[["input"]])
}

#' Evaluate one policy on a call, failing closed: NULL (no opinion) or list(decision, reason,
#' input); an error or a malformed answer denies (contract 10.2 row 12; P06's perm_policies()
#' applies the same rule while combining policies)
#' @noRd
ext_policy_decide = function(spec, call, ctx = NULL) {
  deny = function(why) {
    list(decision = "deny", reason = paste0("policy '", spec[["name"]], "' ", why),
         input = call[["input"]])
  }
  r = tryCatch(spec[["check"]](call, ctx), error = function(e) e)
  if (inherits(r, "error")) {
    registry_diagnostic(paste0("policy:", spec[["name"]]), "policy", class(r)[[1]],
                        conditionMessage(r))
    return(deny(paste0("failed: ", conditionMessage(r))))
  }
  if (is.null(r)) return(NULL)
  if (!ext_policy_ok(r)) return(deny("returned a malformed decision"))
  input = if (identical(r[["decision"]], "modify")) r[["input"]] else call[["input"]]
  reason = paste(as.character(r[["reason"]] %||% ""), collapse = " ")
  list(decision = r[["decision"]], reason = reason, input = input)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-events")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 123 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-events.R tests/testthat/test-ext-events.R
git commit -m "feat(ext): add event dispatch, hooks and policies"
```

---

### Task 9: Transactional and lazy loading, session scope, unload, `gptr_reload()`

**Files:**
- Create: `R/ext-load.R`
- Modify: `NAMESPACE`, `man/gptr_reload.Rd` (generated)
- Test: `tests/testthat/test-ext-load.R` (create)

**Interfaces:**
- Consumes: Tasks 2-8 (`ext_info_new()`, `api_build()`, `ext_commit_one()`, `api_require()`, `kind_record_from_spec()`, `kinds_env()`, `registry_add(..., state = "lazy")`, `registry_remove()`, `registry_check_source()`, `registry_source_filtered()`, `registry_recs()`, `registry_diagnostic()`, `registry_touch()`, `ext_forget()`, `ext_control_guard()`, `ev_dispatch()` in tests); P01 `gptr_warn(..., .once = )`, `on_unload(fun)`, `check_function()`, `check_list()`, `ext_service_set()`/`ext_service_get()` in tests.
- Produces (04 §7.2, §10.8): `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)` -> `lgl(1)`; `ext_activate(source)` -> `lgl(1)`; `ext_activate_record(rec)`; `ext_unload(source)` -> number of records removed (the package-unload path); `ext_watch_unload(pkg, source = paste0("plugin:", pkg))` (`setHook(packageEvent(pkg, "onUnload"), ...)`, once per package and registry, removed again by an `on_unload()` cleanup when gptr unloads) and `ext_unhook(hook, fun)`; failed, unloaded, reloaded and session-scoped extensions are forgotten with `ext_forget()` (Task 4); `kind_stage(spec, ext_id, source)`, `kinds_unstage(ext_id)`; `ext_provides(manifest)`; `ext_placeholder(kind, name, source, declaration = NULL)`; the export `gptr_reload()` -> the new generation invisibly.
- Manifests are the parsed `plugin.json` of 04 §11.12 (`json_decode()` shape: `extension$provides` is kind -> list of names, hooks by event name; `extension$declarations` is name -> `list(signature, description)`; `extension$activation` `"lazy"` or `"eager"`; `gptr$api` the requirement). Lazy placeholders are specs of class `c("gptr_<kind>", "gptr_spec")` with `lazy = TRUE`, `source` and `declaration`, stored with state `"lazy"`: `registry_all("tool")` returns tool placeholders unactivated so P07/P10 can put declarations into the frozen prompt before activation, while `registry_get()` and `registry_all()` of any other kind activate them.
- Declarative-resource owners (P17 skills, prompts, agents; P18 MCP configurations) key their discovery caches on `registry_generation()`, which `gptr_reload()` increments; that is how `gptr_reload()` makes them re-discover (04 §6.7) without a P02 -> P17 call.

The factory's registrations are staged (Task 6's `ext_register()`) and committed only when it returns, `kind` specs first so later specs of the factory validate; an error, an unmet requirement (manifest `gptr.api`, the factory attribute `gptr_api`, or `gptr$require()`), a missing API member or an invalid spec at commit rolls every staged and committed record back, removes staged kinds, records a diagnostic and warns once per source with class `gptr_warning_plugin` (report G1 5.1 `ext_load()`/`commit()`; §4.4 rule 4 for provided names a factory forgot).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-load.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

# A plugin manifest (contract 11.12) as json_decode() returns it
manifest = function(provides, declarations = NULL, api = NULL, activation = "lazy") {
  m = list(name = "demo", version = "0.1.0",
           extension = list(entry = "demo::gptr_plugin", activation = activation,
                            provides = lapply(provides, as.list)))
  if (!is.null(declarations)) m$extension$declarations = declarations
  if (!is.null(api)) m$gptr = list(api = api)
  m
}

test_that("a factory's registrations are committed together when it returns", {
  local_registry()
  seen = new.env()
  ok = ext_load(function(gptr) {
    gptr$register(cmd("one"))
    seen$staged = registry_get("command", "one")
    gptr$register_command("two", handler = function(args, ctx) "2")
  }, source = "plugin:demo", rank = 5L)
  expect_true(ok)
  expect_null(seen$staged)
  expect_equal(registry_get("command", "two")$handler("", NULL), "2")
  expect_equal(unique(gptr_registry("command")$source), "plugin:demo")
})

test_that("a factory that errors after two registrations is rolled back (G1 check)", {
  reg = local_registry()
  ok = NULL
  expect_warning({
    ok = ext_load(function(gptr) {
      gptr$register(cmd("a"))
      gptr$register(cmd("b"))
      stop("factory bug")
    }, source = "plugin:broken1", rank = 5L)
  }, class = "gptr_warning_plugin")
  expect_false(ok)
  expect_null(registry_get("command", "a"))
  expect_null(registry_get("command", "b"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "plugin:broken1" & grepl("factory bug", d$message, fixed = TRUE)))
  expect_length(ls(reg$exts), 0L)
})

test_that("an unmet API requirement disables only that factory (G1 check)", {
  local_registry()
  expect_warning(
    ext_load(function(gptr) {
      gptr$register(cmd("early"))
      gptr$require(">= 2.0") # nolint: object_usage_linter.
      gptr$register(cmd("late"))
    }, source = "plugin:future", rank = 5L),
    class = "gptr_warning_plugin"
  )
  expect_true(ext_load(function(gptr) gptr$register(cmd("fine")), "plugin:present", 5L))
  expect_null(registry_get("command", "early"))
  expect_null(registry_get("command", "late"))
  expect_false(is.null(registry_get("command", "fine")))
  expect_warning(
    expect_false(ext_load(function(gptr) gptr$register(cmd("m")), "plugin:manifest-api", 5L,
                          manifest = manifest(list(command = "m"), api = ">= 3"))),
    class = "gptr_warning_plugin"
  )
  expect_null(registry_get("command", "m"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "plugin:future" & d$class == "gptr_error_api_version"))
})

test_that("a missing API method and an invalid spec roll back too", {
  local_registry()
  expect_warning(ext_load(function(gptr) {
    gptr$register(cmd("x"))
    gptr$register_widget("w")
  }, source = "plugin:oldapi", rank = 5L), class = "gptr_warning_plugin")
  expect_null(registry_get("command", "x"))
  expect_warning(ext_load(function(gptr) {
    gptr$register(cmd("y"))
    gptr$register(gptr_tool("search", "Search", fun = function(q) q, exposure = "r"))
  }, source = "plugin:nons", rank = 5L), class = "gptr_warning_plugin")
  expect_null(registry_get("command", "y"))
})

test_that("a factory can define a kind and use it; a rollback removes the kind", {
  local_registry()
  expect_true(ext_load(function(gptr) {
    gptr$register_kind("reviewer", validate = function(spec) spec, resolve = "all")
    gptr$register_reviewer("stats", focus = "statistics")
  }, source = "plugin:panel", rank = 5L))
  expect_equal(registry_all("reviewer")$stats$focus, "statistics")
  expect_warning(ext_load(function(gptr) {
    gptr$register_kind("auditor", validate = function(spec) spec)
    stop("late failure")
  }, source = "plugin:audit", rank = 5L), class = "gptr_warning_plugin")
  expect_false("auditor" %in% kind_names())
})

test_that("an unregister function returned while staging cancels the registration", {
  local_registry()
  ext_load(function(gptr) {
    off = gptr$register(cmd("temp"))
    off()
    gptr$register(cmd("kept"))
  }, source = "plugin:cancel", rank = 5L)
  expect_null(registry_get("command", "temp"))
  expect_false(is.null(registry_get("command", "kept")))
})

test_that("lazy manifests register placeholders and declarations; first use activates", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  factory = function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(gptr_tool("search", "Search ClinicalTrials.gov for recruiting trials",
                            fun = function(condition) paste("trials for", condition),
                            exposure = "r", namespace = "trials"))
    gptr$register(cmd("panel"))
    gptr$on("tool_result", function(event, ctx) NULL)
  }
  decl = list(`trials/search` = list(signature = "search(condition: string)",
                                     description = "Search ClinicalTrials.gov"))
  m = manifest(list(tool = "trials/search", command = "panel", hook = "tool_result"), decl)
  expect_true(ext_load(factory, "plugin:trials", 5L, manifest = m, lazy = TRUE))
  expect_equal(runs$n, 0L)
  r = gptr_registry()
  expect_equal(r$state, rep("lazy", 3L))
  expect_gt(r$tokens[r$name == "trials/search"], 0)
  placeholder = registry_all("tool")[["trials/search"]]
  expect_true(placeholder$lazy)
  expect_equal(placeholder$declaration$signature, "search(condition: string)")
  expect_equal(registry_names("command"), "panel")
  expect_equal(registry_get("tool", "trials/search")$fun("asthma"), "trials for asthma")
  expect_equal(runs$n, 1L)
  expect_false(any(gptr_registry()$state == "lazy"))
  expect_false(is.null(registry_get("command", "panel")))
  expect_equal(runs$n, 1L)
})

test_that("registry_all() activates lazy records of every kind but tool", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  ext_load(function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(gptr_spec("model", "corp/lazy-1", context = 1000))
  }, "plugin:models", 5L, manifest = manifest(list(model = "corp/lazy-1")), lazy = TRUE)
  expect_equal(runs$n, 0L)
  m = registry_all("model")
  expect_equal(runs$n, 1L)
  expect_equal(m[["corp/lazy-1"]]$id, "lazy-1")
  expect_null(m[["corp/lazy-1"]]$lazy)
})

test_that("the first dispatch of a provided event activates a lazy plugin", {
  local_registry()
  seen = new.env()
  m = manifest(list(hook = "turn_end"))
  ext_load(function(gptr) gptr$on("turn_end", function(event, ctx) seen$hit = TRUE),
           "plugin:audit", 5L, manifest = m, lazy = TRUE)
  expect_null(seen$hit)
  ev_dispatch("turn_end", list(message = NULL))
  expect_true(seen$hit)
})

test_that("an activation that fails or forgets a provided name removes the placeholder", {
  local_registry()
  expect_true(ext_load(function(gptr) stop("broken on first use"), "plugin:lazybad", 5L,
                       manifest = manifest(list(command = "late")), lazy = TRUE))
  expect_warning(expect_null(registry_get("command", "late")), class = "gptr_warning_plugin")
  expect_false("late" %in% registry_names("command"))
  ext_load(function(gptr) gptr$register(cmd("other")), "plugin:liar", 5L,
           manifest = manifest(list(command = c("promised", "other"))), lazy = TRUE)
  expect_null(registry_get("command", "promised"))
  expect_false(is.null(registry_get("command", "other")))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "missing_provided" & grepl("promised", d$message, fixed = TRUE)))
})

test_that("eager activation in the manifest runs the factory at load", {
  local_registry()
  ext_load(function(gptr) gptr$register(cmd("now")), "plugin:eager", 5L,
           manifest = manifest(list(command = "now"), activation = "eager"), lazy = TRUE)
  expect_equal(gptr_registry("command")$state, "active")
})

test_that("a stale API object raises gptr_error_stale_api after gptr_reload() (G1 check)", {
  reg = local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$register(cmd("hi"))
  }, "plugin:keeper", 5L)
  gen = gptr_reload()
  expect_equal(gen, 2L)
  expect_equal(registry_generation(), 2L)
  err = expect_error(keep$api$register(cmd("again")), class = "gptr_error_stale_api")
  expect_equal(err$plugin, "plugin:keeper")
  expect_false(is.null(registry_get("command", "hi")))
})

test_that("gptr_reload() re-declares lazily activated plugins", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  ext_load(function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(cmd("panel"))
  }, "plugin:relazy", 5L, manifest = manifest(list(command = "panel")), lazy = TRUE)
  registry_get("command", "panel")
  expect_equal(runs$n, 1L)
  gptr_reload()
  expect_equal(gptr_registry("command")$state, "lazy")
  registry_get("command", "panel")
  expect_equal(runs$n, 2L)
})

test_that("gptr_reload() is refused from model code during a run (IC-53)", {
  reg = local_registry()
  reg$executing = c(c1 = "u1")
  expect_error(gptr_reload(), class = "gptr_error_permission")
  expect_equal(registry_generation(), 1L)
})

test_that("a factory loaded with session = <id> is invisible to other sessions (IC-69)", {
  reg = local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$state$n = 1L
    gptr$register(cmd("mine"))
    gptr$on("turn_end", function(event, ctx) NULL)
  }, "session", 0L, session = "s1")
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
  expect_null(registry_get("command", "mine", session = "s2"))
  expect_null(registry_get("command", "mine"))
  expect_length(registry_all("hook", session = "s2"), 0L)
  ev_dispatch("session_shutdown", list(reason = "exit"), session = "s1")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_length(registry_all("hook", session = "s1"), 0L)
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
  expect_error(keep$api$register(cmd("again")), class = "gptr_error_stale_api")
})

test_that("a session's extension releases its factory and captured frames (R10)", {
  reg = local_registry()
  load_in_frame = function() {
    big = numeric(1e6)
    ext_load(function(gptr) gptr$register(cmd("n", length(big))), "session", 0L,
             session = "s1")
  }
  load_in_frame()
  info = get(ls(reg$exts), envir = reg$exts)
  expect_true(is.function(info$factory))
  ev_dispatch("session_shutdown", list(reason = "gc"), session = "s1")
  expect_null(info$factory)
  expect_true(info$unloaded)
})

test_that("a plugin service record replaces a built-in service and leaves with its plugin", {
  local_registry()
  old = the$services
  withr::defer(assign("services", old, envir = the))
  ext_service_set("p02.demo", function() "bootstrap", provided_by = "P02-test")
  ext_load(function(gptr) gptr$register_service("p02.demo", fun = function() "builtin"),
           "builtin:demo", 6L)
  expect_equal(ext_service_get("p02.demo")(), "builtin")
  ext_load(function(gptr) gptr$register_service("p02.demo", fun = function() "plugin"),
           "plugin:better", 5L)
  expect_equal(ext_service_get("p02.demo")(), "plugin")
  expect_equal(ext_unload("plugin:better"), 1L)
  expect_equal(ext_service_get("p02.demo")(), "builtin")
})

test_that("unloading a plugin removes its records and makes its API objects stale", {
  local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$register(cmd("a"))
    gptr$register(cmd("b"))
  }, "plugin:gone", 5L)
  expect_equal(ext_unload("plugin:gone"), 2L)
  expect_null(registry_get("command", "a"))
  expect_error(keep$api$register(cmd("c")), class = "gptr_error_stale_api")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "unloaded" & d$source == "plugin:gone"))
  expect_length(ls(registry_env()$exts), 0L)
})

test_that("package unload is watched once through packageEvent(pkg, 'onUnload')", {
  local_registry()
  hook = packageEvent("tools", "onUnload")
  before = getHook(hook)
  withr::defer(setHook(hook, before, action = "replace"))
  old_unload = the$on_unload
  withr::defer(assign("on_unload", old_unload, envir = the))
  expect_true(ext_watch_unload("tools"))
  expect_false(ext_watch_unload("tools"))
  after = getHook(hook)
  expect_length(after, length(before) + 1L)
  gptr_register(cmd("x"))
  ext_load(function(gptr) gptr$register(cmd("fromtools")), "plugin:tools", 5L)
  after[[length(after)]]("tools", "tools")
  expect_null(registry_get("command", "fromtools"))
  expect_false(is.null(registry_get("command", "x")))
  expect_length(the$on_unload, length(old_unload) + 1L)
  the$on_unload[[length(the$on_unload)]]()
  expect_length(getHook(hook), length(before))
})

test_that("filtered sources are not loaded; argument errors are classed", {
  local_registry()
  registry_filters_set("-plugin:blocked", "user")
  expect_false(ext_load(function(gptr) gptr$register(cmd("z")), "plugin:blocked", 5L))
  expect_null(registry_get("command", "z"))
  expect_error(ext_load("not a function", "plugin:x", 5L), class = "gptr_error_invalid_argument")
  expect_error(ext_load(function(gptr) NULL, "elsewhere", 5L),
               class = "gptr_error_invalid_argument")
  expect_false(ext_activate("plugin:none"))
})

test_that("100 lazy manifests register quickly (acceptance 4; timed precisely in the plan)", {
  local_registry()
  f = function(gptr) NULL
  elapsed = system.time(for (i in seq_len(100L)) {
    ext_load(f, paste0("plugin:lazy", i), 5L, lazy = TRUE,
             manifest = manifest(list(tool = paste0("t", i), command = paste0("c", i)),
                                 stats::setNames(list(list(signature = paste0("t", i, "(x)"),
                                                           description = "A tool.")),
                                                 paste0("t", i))))
  })[["elapsed"]]
  expect_equal(nrow(gptr_registry()), 200L)
  expect_lt(elapsed, 5)
})

test_that("ext_activate(source) runs a lazy extension's factory on request", {
  local_registry()
  ext_load(function(gptr) gptr$register(cmd("soon")), "plugin:ondemand", 5L,
           manifest = manifest(list(command = "soon")), lazy = TRUE)
  expect_true(ext_activate("plugin:ondemand"))
  expect_equal(gptr_registry("command")$state, "active")
  expect_false(ext_activate("plugin:ondemand"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-load")'`
Expected: errors such as `could not find function "ext_load"`, until testthat stops with `Maximum number of failures exceeded; quitting.`

- [ ] **Step 3: Write the implementation**

Create `R/ext-load.R`:

```r
# ext-load.R -- transactional factory loading (stage, commit, rollback), API requirements, lazy
# activation from manifests with declarations, session-scoped extensions, package unload and
# gptr_reload() (contract 7.2, 10.8; IC-69; architecture 11.2). Adapted from the verified G1
# prototype (report G1 5.1 ext_load(), commit(), ext_declare_lazy(), ext_activate(),
# plugin_watch_unload(); checks 5.2 and 5.5) with the verification-log fixes: requirement strings
# of one component are normalised (row 25) and a factory's kinds are committed before the specs
# that use them.

#' The API requirement of an extension: the manifest's `gptr.api`, else the factory attribute
#' `gptr_api` (report G1 3.5); NULL when none is declared
#' @noRd
ext_requirement = function(factory, manifest) {
  req = manifest[["gptr"]][["api"]] %||% attr(factory, "gptr_api", exact = TRUE)
  if (is.character(req) && length(req) == 1L && !is.na(req) && nzchar(req)) req else NULL
}

#' Signal gptr_error_api_version unless the requirement `req` (or NULL) is met
#' @noRd
ext_check_requirement = function(req, source) {
  if (!is.null(req)) api_require(req, source)
  invisible(TRUE)
}

#' The `provides` table of a manifest as kind -> character vector of names
#' @noRd
ext_provides = function(manifest) {
  p = manifest[["extension"]][["provides"]]
  if (!is.list(p) || !length(p) || is.null(names(p))) return(list())
  out = lapply(p, function(x) as.character(unlist(x, use.names = FALSE)))
  out[lengths(out) > 0L]
}

#' Is the manifest's activation lazy (anything but "eager")?
#' @noRd
ext_manifest_lazy = function(manifest) {
  eager = identical(manifest[["extension"]][["activation"]], "eager")
  !eager && length(ext_provides(manifest)) > 0L
}

#' A lazy placeholder spec for one provided name (contract 10.8). Placeholders carry
#' `lazy = TRUE`, the `source` and the manifest `declaration` (list(signature, description) or
#' NULL), so catalogs can list a lazy capability before its factory runs; hooks are provided by
#' event name
#' @noRd
ext_placeholder = function(kind, name, source, declaration = NULL) {
  spec = list(kind = kind, name = name, lazy = TRUE, source = source, declaration = declaration,
              api_version = ext_api_version)
  if (identical(kind, "hook")) spec$event = name
  structure(spec, class = c(paste0("gptr_", kind), "gptr_spec"))
}

#' Remove an extension's lazy placeholders
#' @noRd
ext_drop_placeholders = function(info) {
  for (id in info$placeholders) registry_remove(id)
  info$placeholders = character()
  invisible(NULL)
}

#' Undefine the kinds staged by an extension whose load failed
#' @noRd
kinds_unstage = function(ext_id) {
  k = kinds_env()
  for (nm in ls(k)) {
    d = get(nm, envir = k, inherits = FALSE)
    if (identical(d$staged, ext_id)) rm(list = nm, envir = k)
  }
  registry_touch()
  invisible(NULL)
}

#' Define a kind while its factory runs, so later registrations of the factory can use it; the
#' commit replaces the staged definition, a rollback removes it (kinds_unstage())
#' @noRd
kind_stage = function(spec, ext_id, source) {
  k = kinds_env()
  old = get0(spec[["name"]], envir = k, inherits = FALSE)
  if (!is.null(old) && !identical(old$staged, ext_id)) {
    spec_abort(spec, "name", paste0("names a kind already defined by ", old$source))
  }
  rec = kind_record_from_spec(spec, source)
  rec$staged = ext_id
  assign(spec[["name"]], rec, envir = k)
  registry_touch()
  invisible(spec[["name"]])
}

#' Roll an extension back: drop staged kinds, staged and committed records, forget the extension
#' (its factory is released); record a diagnostic and warn once per source (class
#' gptr_warning_plugin with field `diagnostic`)
#' @noRd
ext_fail = function(info, err) {
  kinds_unstage(info$id)
  info$stage = list()
  for (id in info$ids) registry_remove(id)
  info$ids = character()
  ext_drop_placeholders(info)
  info$status = "failed"
  ext_forget(info)
  msg = conditionMessage(err)
  registry_diagnostic(info$source, "load", class(err)[[1]], msg)
  gptr_warn(paste0("The gptr extension ", info$source, " was disabled: ", msg), "plugin",
            diagnostic = msg, .once = paste0("plugin:", info$source))
  FALSE
}

#' Commit the staged registrations: kinds first, then the rest in registration order; a failing
#' commit rolls everything back
#' @noRd
ext_commit = function(info) {
  items = Filter(function(it) !isTRUE(it$cancelled), info$stage)
  is_kind = vapply(items, function(it) identical(it$spec$kind, "kind"), NA)
  items = c(items[is_kind], items[!is_kind])
  info$stage = list()
  err = tryCatch({
    for (it in items) it$id = ext_commit_one(info, it$spec)
    NULL
  }, error = function(e) e)
  if (!is.null(err)) return(ext_fail(info, err))
  TRUE
}

#' Diagnostics for provided names the factory did not register (report G1 4.4 rule 4)
#' @noRd
ext_check_provided = function(info) {
  reg = registry_env()
  provides = ext_provides(info$manifest)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      if (identical(kind, "hook")) {
        ids = get0(nm, envir = reg$hooks, inherits = FALSE)
      } else {
        ids = get0(paste(kind, nm, sep = "\r"), envir = reg$by_key, inherits = FALSE)
      }
      recs = registry_recs(reg, ids)
      mine = vapply(recs, function(r) identical(r$ext, info$id) && !identical(r$state, "lazy"), NA)
      if (!any(mine)) {
        registry_diagnostic(info$source, "activate", "missing_provided",
                            paste0(info$source, " declares ", kind, " '", nm,
                                   "' in its manifest but its factory did not register it"))
      }
    }
  }
  invisible(NULL)
}

#' Run an extension's factory transactionally: stage, then commit or roll back (contract 7.2)
#' @noRd
ext_run_factory = function(info) {
  reg = registry_env()
  ext_drop_placeholders(info)
  info$lazy = FALSE
  req_ok = tryCatch({
    ext_check_requirement(ext_requirement(info$factory, info$manifest), info$source)
    NULL
  }, error = function(e) e)
  if (!is.null(req_ok)) return(ext_fail(info, req_ok))
  info$status = "loading"
  info$stage = list()
  api = api_build(info, reg)
  err = tryCatch({
    info$factory(api)
    NULL
  }, error = function(e) e)
  if (!is.null(err)) return(ext_fail(info, err))
  if (!ext_commit(info)) return(FALSE)
  info$status = "active"
  ext_check_provided(info)
  if (startsWith(info$source, "plugin:")) {
    pkg = substring(info$source, 8L)
    if (isNamespaceLoaded(pkg)) ext_watch_unload(pkg, info$source)
  }
  TRUE
}

#' Register the placeholders and declarations of a lazy extension (contract 10.8)
#' @noRd
ext_declare_lazy = function(info) {
  reg = registry_env()
  provides = ext_provides(info$manifest)
  decl = info$manifest[["extension"]][["declarations"]] %||% list()
  info$status = "lazy"
  info$lazy = TRUE
  prev = reg$current_ext
  reg$current_ext = info$id
  on.exit({
    reg$current_ext = prev
  }, add = TRUE)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      spec = ext_placeholder(kind, nm, info$source, decl[[nm]])
      id = registry_add(spec, source = info$source, rank = info$rank, session = info$session,
                        state = "lazy")
      info$placeholders = c(info$placeholders, id)
    }
  }
  TRUE
}

#' Load an extension factory (contract 7.2)
#'
#' Stages every registration of `factory(gptr)` and commits them only when it returns; a thrown
#' error, an unmet API requirement or a missing method rolls the extension back with a diagnostic
#' (and a `plugin` warning once). With `lazy = TRUE` and a manifest that provides capabilities,
#' only placeholders and declarations are registered and the factory runs on the first
#' registry_get() of a provided name or the first dispatch of a provided event. With `session`
#' (a session or its id) every record is scoped to that session and removed at its
#' session_shutdown. Returns TRUE when the extension is loaded or declared.
#' @noRd
ext_load = function(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE,
                    session = NULL) {
  check_function(factory, "factory")
  registry_check_source(source)
  rank = check_number(rank, "rank", min = 0, max = 99, int = TRUE)
  check_string(dir, "dir", null = TRUE)
  check_list(manifest, "manifest", null = TRUE)
  check_flag(lazy, "lazy")
  if (registry_source_filtered(source)) {
    registry_diagnostic(source, "load", "filtered", paste0(source, " is disabled by a filter"))
    return(FALSE)
  }
  info = ext_info_new(source, dir, manifest)
  info$rank = rank
  info$session = ext_session_id(session)
  info$factory = factory
  if (lazy && ext_manifest_lazy(manifest)) {
    req = tryCatch({
      ext_check_requirement(ext_requirement(factory, manifest), source)
      NULL
    }, error = function(e) e)
    if (!is.null(req)) return(ext_fail(info, req))
    info$lazy_origin = TRUE
    return(ext_declare_lazy(info))
  }
  ext_run_factory(info)
}

#' Activate the lazy extensions of a source (contract 7.2); TRUE when one was activated
#' @noRd
ext_activate = function(source) {
  check_string(source, "source")
  reg = registry_env()
  done = FALSE
  for (eid in ls(reg$exts)) {
    info = get(eid, envir = reg$exts, inherits = FALSE)
    if (identical(info$source, source) && identical(info$status, "lazy")) {
      done = ext_run_factory(info) || done
    }
  }
  done
}

#' Activate the extension behind a lazy placeholder record; a placeholder whose extension is gone
#' is removed
#' @noRd
ext_activate_record = function(rec) {
  info = get0(rec$ext %||% "", envir = registry_env()$exts, inherits = FALSE)
  if (is.null(info) || !identical(info$status, "lazy")) {
    registry_remove(rec$id)
    return(FALSE)
  }
  ext_run_factory(info)
}

#' Remove every record of a source and make its API objects stale (package unload, contract
#' 10.8); returns the number of records removed
#' @noRd
ext_unload = function(source) {
  check_string(source, "source")
  reg = registry_env()
  n = 0L
  for (id in ls(reg$recs)) {
    rec = get0(id, envir = reg$recs, inherits = FALSE)
    if (!is.null(rec) && identical(rec$source, source)) {
      registry_remove(id)
      n = n + 1L
    }
  }
  for (eid in ls(reg$exts)) {
    info = get(eid, envir = reg$exts, inherits = FALSE)
    if (identical(info$source, source)) {
      info$status = "unloaded"
      info$ids = character()
      info$placeholders = character()
      ext_forget(info, reg)
    }
  }
  registry_diagnostic(source, "unload", "unloaded",
                      paste0(source, " was unloaded; ", n, " record(s) removed"))
  invisible(n)
}

#' Remove one function from a hook list
#' @noRd
ext_unhook = function(hook, fun) {
  keep = Filter(function(h) !identical(h, fun), getHook(hook))
  setHook(hook, if (length(keep)) keep else NULL, action = "replace")
  invisible(NULL)
}

#' Remove a plugin package's records when its namespace unloads (contract 10.8); the hook is
#' removed again when gptr itself unloads (P01's on_unload()), so no hook outlives gptr
#' @noRd
ext_watch_unload = function(pkg, source = paste0("plugin:", pkg)) {
  check_string(pkg, "pkg")
  reg = registry_env()
  if (pkg %in% reg$watched) return(invisible(FALSE))
  reg$watched = c(reg$watched, pkg)
  hook = packageEvent(pkg, "onUnload")
  fun = function(...) ext_unload(source)
  setHook(hook, fun)
  on_unload(function() ext_unhook(hook, fun))
  invisible(TRUE)
}

#' Reload extensions
#'
#' Bumps the registry generation, so that extension API objects captured by old code signal
#' `gptr_error_stale_api`, and re-declares lazily activated plugins from their manifests (their
#' factories run again on first use). Discovery of declarative resources (skills, prompts, agents,
#' MCP configurations, plugin manifests) is keyed on the generation, so it runs again on next
#' use. Sessions whose prompt is already frozen are not changed. Refused from model code while a
#' run executes a tool, unless the user approved that call.
#'
#' @return The new registry generation (an integer), invisibly.
#' @examples
#' gptr_reload()
#' @export
gptr_reload = function() {
  ext_control_guard("gptr_reload")
  reg = registry_env()
  reg$generation = reg$generation + 1L
  for (eid in ls(reg$exts)) {
    info = get(eid, envir = reg$exts, inherits = FALSE)
    redeclare = isTRUE(info$lazy_origin) && identical(info$status, "active") &&
      !isTRUE(info$unloaded)
    if (!redeclare) next
    for (id in info$ids) registry_remove(id)
    info$ids = character()
    info$status = "reloaded"
    fresh = ext_info_new(info$source, info$dir, info$manifest)
    fresh$rank = info$rank
    fresh$session = info$session
    fresh$factory = info$factory
    fresh$lazy_origin = TRUE
    ext_forget(info, reg)
    ext_declare_lazy(fresh)
  }
  invisible(reg$generation)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'`, then `Rscript --vanilla -e 'devtools::test(filter = "ext-load")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 103 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-load.R tests/testthat/test-ext-load.R NAMESPACE man/gptr_reload.Rd
git commit -m "feat(ext): add transactional and lazy extension loading"
```

---

### Task 10: Built-in declarations and load order

**Files:**
- Create: `R/ext-builtins.R`
- Test: `tests/testthat/test-ext-builtins.R` (create)

**Interfaces:**
- Consumes: Task 9 `ext_load()`; Task 5 `registry_source_filtered()`, `registry_filters_set()` (tests); Task 4 `registry_diagnostic()`; P01 `the`, `check_*()`; P01's `.onLoad`, which calls `ext_load_builtins()` after evaluating every `on_load()` expression (IC-32).
- Produces (04 §7.2, §10.3): `the$builtins` (name -> `list(name, factory, after, replaceable)`); `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` -> name invisibly; `ext_builtin_order(builtins = the$builtins %||% list())` -> names in dependency order; `ext_load_builtins()` -> names loaded now, invisibly. Every later plan declares its built-in with `on_load(ext_declare_builtin("<name>", builtin_<name>))` in its own file (P03 `secrets` with `replaceable = FALSE`, P05 `fake` and `providers`, P08 `gateway` with `replaceable = FALSE`, ...).

`replaceable = FALSE` feeds `registry_protected_builtins()` (Task 4), so `-builtin:<name>` is refused for that built-in; `builtin:permissions`, `builtin:plan` and `builtin:secrets` are protected whatever their declaration says (IC-53).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ext-builtins.R`:

```r
local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

local_builtins = function(env = parent.frame()) {
  old = the$builtins
  withr::defer(assign("builtins", old, envir = the), envir = env)
  the$builtins = list()
  invisible(NULL)
}

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

test_that("ext_declare_builtin() records declarations; a second declaration replaces the first", {
  local_builtins()
  f = function(gptr) NULL
  expect_equal(ext_declare_builtin("demo", f), "demo")
  expect_equal(names(the$builtins), "demo")
  expect_true(the$builtins$demo$replaceable)
  ext_declare_builtin("demo", f, after = "core", replaceable = FALSE)
  expect_length(the$builtins, 1L)
  expect_equal(the$builtins$demo$after, "core")
  expect_false(the$builtins$demo$replaceable)
  expect_error(ext_declare_builtin("Bad Name", f), class = "gptr_error_invalid_argument")
  expect_error(ext_declare_builtin("demo", "f"), class = "gptr_error_invalid_argument")
})

test_that("built-ins load in dependency order given by `after`", {
  local_registry()
  local_builtins()
  log = new.env()
  log$order = character()
  mk = function(nm) {
    force(nm)
    function(gptr) {
      log$order = c(log$order, nm)
      gptr$register(cmd(nm))
    }
  }
  ext_declare_builtin("tools", mk("tools"), after = c("prompt", "missing-one"))
  ext_declare_builtin("prompt", mk("prompt"), after = "core")
  ext_declare_builtin("core", mk("core"))
  ext_declare_builtin("console", mk("console"))
  expect_equal(ext_builtin_order(), c("core", "console", "prompt", "tools"))
  expect_equal(ext_load_builtins(), c("core", "console", "prompt", "tools"))
  expect_equal(log$order, c("core", "console", "prompt", "tools"))
  r = gptr_registry("command")
  expect_equal(r$source[r$name == "tools"], "builtin:tools")
  expect_true(all(r$rank == 6L))
  expect_equal(ext_load_builtins(), character())
  expect_equal(log$order, c("core", "console", "prompt", "tools"))
})

test_that("a dependency cycle is a diagnostic and loads in declaration order", {
  local_registry()
  local_builtins()
  ext_declare_builtin("a", function(gptr) NULL, after = "b")
  ext_declare_builtin("b", function(gptr) NULL, after = "a")
  expect_equal(ext_builtin_order(), c("a", "b"))
  expect_true(any(gptr_registry(diagnostics = TRUE)$class == "cycle"))
})

test_that("-builtin:<name> skips a replaceable built-in; +builtin:<name> loads it", {
  local_registry()
  local_builtins()
  ext_declare_builtin("mcp", function(gptr) gptr$register(cmd("mcp")))
  registry_filters_set("-builtin:mcp", "user")
  expect_equal(ext_load_builtins(), character())
  expect_null(registry_get("command", "mcp"))
  registry_filters_set(character(), "user")
  registry_filters_set("+builtin:mcp", "session")
  expect_false(is.null(registry_get("command", "mcp")))
})

test_that("non-replaceable built-ins cannot be filtered out (IC-53)", {
  local_registry()
  local_builtins()
  ext_declare_builtin("gateway", function(gptr) gptr$register(cmd("continue")),
                      replaceable = FALSE)
  out = registry_filters_set("-builtin:gateway", "user")
  expect_equal(attr(out, "refused"), "-builtin:gateway")
  ext_load_builtins()
  expect_false(is.null(registry_get("command", "continue")))
})

test_that("a failing built-in is rolled back without stopping the others", {
  local_registry()
  local_builtins()
  ext_declare_builtin("broken-demo", function(gptr) {
    gptr$register(cmd("half"))
    stop("built-in bug")
  })
  ext_declare_builtin("fine", function(gptr) gptr$register(cmd("fine")))
  loaded = NULL
  expect_warning({
    loaded = ext_load_builtins()
  }, class = "gptr_warning_plugin")
  expect_equal(loaded, "fine")
  expect_null(registry_get("command", "half"))
})

test_that("a user record overrides one record of a built-in, not the whole built-in (IC-69)", {
  local_registry()
  local_builtins()
  ext_declare_builtin("tools", function(gptr) {
    for (nm in c("read", "edit", "grep")) {
      gptr$register_tool(nm, description = paste("Built-in", nm),
                         execute = function(input, ctx) "builtin",
                         fun = function(path = ".") "builtin")
    }
  })
  ext_load_builtins()
  off = gptr_register(gptr_tool("read", "My read", execute = function(input, ctx) "mine"))
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "mine")
  expect_equal(registry_get("tool", "edit")$execute(list(), NULL), "builtin")
  expect_equal(registry_get("tool", "grep")$fun(), "builtin")
  expect_true("grep" %in% registry_member_names(registry_env()))
  off()
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-builtins")'`
Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`, from errors such as `could not find function "ext_declare_builtin"`.

- [ ] **Step 3: Write the implementation**

Create `R/ext-builtins.R`:

```r
# ext-builtins.R -- the built-in declaration table and its load order (contract 7.2, 10.3;
# architecture 2.2 rule 3, 3.2). Each built-in is declared from its own file with
# on_load(ext_declare_builtin("<name>", builtin_<name>)); P01's .onLoad evaluates the on_load()
# expressions and then calls ext_load_builtins(), which loads every declared built-in through
# ext_load(source = "builtin:<name>", rank = 6L), so later plans never edit a shared list (IC-32).

the$builtins = list()

#' Declare a built-in extension (contract 7.2)
#'
#' `after` names built-ins that must be loaded first; `replaceable = FALSE` means no
#' `-builtin:<name>` filter can disable it (contract 10.3, IC-53, IC-69). Declaring a name again
#' replaces the earlier declaration.
#' @noRd
ext_declare_builtin = function(name, factory, after = character(), replaceable = TRUE) {
  check_string(name, "name")
  check_function(factory, "factory")
  check_strings(after, "after")
  check_flag(replaceable, "replaceable")
  if (!grepl("^[a-z0-9][a-z0-9-]*$", name, perl = TRUE)) {
    gptr_abort("A built-in name must match ^[a-z0-9][a-z0-9-]*$.", "invalid_argument",
               arg = "name", expected = "a lower-case built-in name")
  }
  b = the$builtins %||% list()
  b[[name]] = list(name = name, factory = factory, after = after, replaceable = replaceable)
  the$builtins = b
  invisible(name)
}

#' Built-in names in load order: every built-in after the declared built-ins it names in `after`
#' (names that are not declared are ignored); a cycle is reported and loaded in declaration order
#' @noRd
ext_builtin_order = function(builtins = the$builtins %||% list()) {
  pending = names(builtins)
  done = character()
  while (length(pending)) {
    ready = pending[vapply(pending, function(n) {
      all(intersect(builtins[[n]]$after, names(builtins)) %in% done)
    }, NA)]
    if (!length(ready)) {
      registry_diagnostic("builtins", "load", "cycle",
                          paste0("circular `after` among built-ins ",
                                 paste(pending, collapse = ", "),
                                 "; they are loaded in declaration order"))
      ready = pending
    }
    done = c(done, ready)
    pending = setdiff(pending, ready)
  }
  done
}

#' Load the declared built-ins into the current registry in dependency order (contract 7.2)
#'
#' Skips built-ins already loaded into this registry and built-ins disabled by a
#' `-builtin:<name>` filter; called by .onLoad and again when a `+builtin:<name>` filter
#' re-enables one. Returns the names loaded now, invisibly.
#' @noRd
ext_load_builtins = function() {
  b = the$builtins %||% list()
  reg = registry_env()
  loaded = character()
  for (nm in ext_builtin_order(b)) {
    src = paste0("builtin:", nm)
    if (nm %in% reg$builtins_loaded || registry_source_filtered(src)) next
    reg$builtins_loaded = c(reg$builtins_loaded, nm)
    if (ext_load(b[[nm]]$factory, source = src, rank = 6L)) loaded = c(loaded, nm)
  }
  invisible(loaded)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-builtins")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 29 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-builtins.R tests/testthat/test-ext-builtins.R
git commit -m "feat(ext): add built-in declarations and load order"
```

---

### Task 11: `gptr_check()` conformance suites

**Files:**
- Modify: `R/ext-check.R` (append), `NAMESPACE`, `man/gptr_check.Rd` (generated)
- Test: `tests/testthat/test-ext-check.R` (append)

**Interfaces:**
- Consumes: Tasks 2-10 (`spec_finish()`, `kind_get()`, `registry_scratch()`, `registry_swap()`, `registry_add()`, `registry_remove()`, `registry_recs()`, `registry_index_push()`, `registry_rec_filtered()`, `spec_tokens()`, `ctx_new()`, `ext_policy_ok()`, `ext_load()`, `ext_provides()`, `api_satisfies()`, `as_tool_result()`); P01 `schema_problems()`, `schema_validate()`, `est_tokens()`, `json_decode()`, `ext_service_has()`/`ext_service_get()`; `ps::ps_children()`, `ps::ps_handle()`, `ps::ps_pid()`; the service `check.adapter` (P12): `function(adapter, fixtures = NULL) <gptr_check>`.
- Produces (04 §6.7, §5.11, §7.2): the export `gptr_check(x, error = FALSE, tokens = FALSE)` -> `c("gptr_check", "data.frame")` with columns `target`, `check`, `ok`, `message`, or `gptr_error_conformance` (field `results`) with `error = TRUE`; the row builders `check_spec(spec, tokens = FALSE, adapter_check = NULL)`, `check_factory(factory, manifest = NULL, tokens = FALSE, adapter_check = NULL)`, `check_package(pkg, tokens = FALSE, adapter_check = NULL)` (the names and leading arguments of 04 §7.2; each returns the rows of a `gptr_check` as a list of one-row data frames that `gptr_check()` binds), `check_row()`, `check_rows()`; `print.gptr_check()`; `ext_bare_identifiers(objects)` (IC-42).

Check names: `spec.class`, `spec.fields` (the failing field in the message: `field '<name>' <problem>`), `tool.schema`, `tool.description_tokens` (direct tools, at most 400), `tool.empty_input`, `section.budget`, `policy.matrix`, `policy.speed` (median at most 10 ms), `backend.start`, `backend.cancel`, `backend.processes`, the rows of the `check.adapter` service (when P12 is loaded), `tokens.declaration`, `tokens.example.<i>`, `factory.load`, `factory.registers`, `factory.no_action`, `provides.<kind>:<name>`, `package.installed`, `manifest.present`, `manifest.valid`, `api.declared`, `api.satisfied`, `factory.exported`, `tokens.declarations`, `code.identifiers`. Checks run in a scratch registry that copies the current registry's non-P02 kinds and its enabled, active process-level records (G1 5.1 `with_scratch_registry()`, extended): plugin kinds validate, bootstrap services owned by loaded built-ins stay available (P01's `ext_service_get()` treats a built-in without records in a non-empty registry as filtered out, so an empty-but-for-the-check scratch made `ctx$risk()` "not available" inside the policy matrix), a plugin namespace that clashes with a live member fails as it would live, and nothing leaks into the live registry. `check_policy()` registers its scripted `ctx.kernel` at rank 0 so it wins over a mirrored one. The package helpers `ext_pkg_path()`, `ext_pkg_factory()`, `ext_pkg_description()` and `ext_pkg_objects()` wrap `system.file()`, `getExportedValue()`, `utils::packageDescription()` and the namespace, so tests replace them with `testthat::local_mocked_bindings()` instead of installing a package.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ext-check.R`:

```r
# One valid spec of every kind P02 defines (contract 10.2 rows 1-5 and 7-38)
valid_specs = function() {
  empty_docs = data.frame(id = character(), text = character(), kind = character())
  risk_rows = data.frame(package = "pkg", `function` = "f", level = 1L, check.names = FALSE)
  list(
    gptr_provider("corp", api = "openai-completions"),
    gptr_adapter("wire", transport = "inprocess",
                 stream = function(model, context, opts) function() NULL),
    gptr_spec("model", "corp/corp-large", context = 128000),
    gptr_router("cheap", route = function(request, ctx) "corp/corp-large"),
    gptr_tool("add", "Add two numbers",
              parameters = list(type = "object", required = I(c("a", "b")),
                                properties = list(a = list(type = "number"),
                                                  b = list(type = "number"))),
              fun = function(a, b) a + b, exposure = "r", namespace = "demo"),
    gptr_spec("mcp_server", "files", command = "mcp-server-files", args = list("--root", ".")),
    gptr_spec("skill", "statistics", description = "Statistical review of analyses"),
    gptr_spec("prompt_template", "review", text = "Review $1"),
    gptr_command("hello", function(args, ctx) "hi"),
    gptr_hook("tool_result", function(event, ctx) NULL),
    gptr_policy("quiet", function(call, ctx) NULL),
    gptr_context_block("lab", function(ctx, budget) "Experiment 12"),
    gptr_prompt_section("rules", "Use SI units."),
    gptr_spec("compactor", "none", should = function(session, ctx) FALSE,
              compact = function(session, ctx) NULL),
    gptr_spec("cache_policy", "default", plan = function(parts, caps, session) list()),
    gptr_spec("estimator", "default", estimate = function(x, class) 1),
    gptr_spec("doc_format", "org", ext = "org", locate = function(text, site) list(),
              render = function(block, site) "",
              upsert = function(text, site, lines, block_id) text, inert = function(lines) lines),
    gptr_spec("artifact_type", "html", build = function(id, dir, data, ctx) NULL,
              check = function(dir, ctx) list(ok = TRUE), launch = function(version_dir, ctx) NULL,
              stop = function(handle) NULL),
    gptr_backend("echo", start = function(spec, ctx) NULL, cancel = function(handle) NULL),
    gptr_agent("stats", description = "Reviewer", model = "corp/corp-large"),
    gptr_spec("ui", "quiet", has_ui = function() FALSE,
              select = function(title, choices, ...) NA_integer_),
    gptr_spec("frontend", "echo", run = function(session, ...) session),
    gptr_spec("setting", "panel.size", default = 3L),
    gptr_spec("secret_source", "vault", resolve = function(name, ctx) NULL,
              list = function(ctx) character()),
    gptr_spec("redaction_rule", "mrn", pattern = "MRN[0-9]{8}", marker = "mrn"),
    gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token"),
    gptr_spec("child_env", "strict", base = "allowlist", keep = "PATH"),
    gptr_spec("checkpointer", "noop", scope = "other", before = function(call, ctx) NULL,
              after = function(call, ctx, token) NULL,
              undo = function(fragment, ctx, force) character(),
              redo = function(fragment, ctx, force) character()),
    gptr_spec("kind", "reviewer", validate = function(spec) spec),
    gptr_spec("route", "echo", order = 90, match = function(call) FALSE,
              run = function(call) NULL),
    gptr_spec("preset", "tiny", tools = c("read", "r")),
    gptr_spec("risk_rule", "mine", rows = risk_rows),
    gptr_spec("service", "p02.check", fun = function() NULL),
    gptr_spec("renderer", "panel.note", render = function(entry, width, ctx) "note"),
    gptr_spec("search_source", "corpus", docs = function(ctx) empty_docs),
    gptr_spec("store", "memory", open = function(...) NULL, append = function(...) NULL,
              read = function(...) list(), fork = function(...) NULL),
    gptr_spec("evaluator", "echo", eval = function(code, envir, ...) NULL)
  )
}

test_that("gptr_check() passes a valid spec of every kind (acceptance 3)", {
  local_registry()
  specs = valid_specs()
  expect_setequal(vapply(specs, function(s) s$kind, ""), kind_names())
  for (s in specs) {
    res = gptr_check(s)
    expect_s3_class(res, c("gptr_check", "data.frame"), exact = TRUE)
    expect_named(res, c("target", "check", "ok", "message"))
    timed = res$check == "policy.speed"
    expect_true(all(res$ok[!timed]), label = paste(s$kind, s$name))
    expect_equal(res$target[[1]], paste0(s$kind, ":", s$name))
  }
})

test_that("an invalid spec fails and names the failing field; error = TRUE signals", {
  local_registry()
  s = gptr_command("hello", function(args, ctx) "hi")
  s$handler = "not a function"
  res = gptr_check(s)
  row = res[res$check == "spec.fields", ]
  expect_false(row$ok)
  expect_match(row$message, "field 'handler'", fixed = TRUE)
  err = expect_error(gptr_check(s, error = TRUE), class = "gptr_error_conformance")
  expect_s3_class(err$results, "gptr_check")
  expect_false(gptr_check(list(kind = "command", name = "x"))$ok)
  u = s
  u$kind = "widget"
  expect_match(gptr_check(u)$message[[2]], "field 'kind'", fixed = TRUE)
  expect_error(gptr_check(42), class = "gptr_error_invalid_argument")
})

test_that("a direct tool description over 400 tokens fails (acceptance 3)", {
  local_registry()
  long = gptr_tool("long", paste(rep("word", 600), collapse = " "),
                   execute = function(input, ctx) "x")
  res = gptr_check(long)
  expect_false(res$ok[res$check == "tool.description_tokens"])
  short = gptr_tool("short", "A short description.", execute = function(input, ctx) "x")
  expect_true(all(gptr_check(short)$ok))
  member = gptr_tool("long_member", paste(rep("word", 600), collapse = " "),
                     fun = function() 1, exposure = "r", namespace = "demo")
  expect_false("tool.description_tokens" %in% gptr_check(member)$check)
})

test_that("tools: schema problems and empty-input handling are checked", {
  local_registry()
  bad_schema = gptr_tool("bad", "Bad schema",
                         parameters = list(type = "object",
                                           properties = list(a = list(type = "strng"))),
                         execute = function(input, ctx) "x")
  expect_false(gptr_check(bad_schema)$ok[gptr_check(bad_schema)$check == "tool.schema"])
  raw = gptr_tool("raw", "Fails on empty input", execute = function(input, ctx) stop("boom"))
  res = gptr_check(raw)
  expect_false(res$ok[res$check == "tool.empty_input"])
  expect_match(res$message[res$check == "tool.empty_input"], "boom", fixed = TRUE)
  classed = gptr_tool("classed", "Classed failure", execute = function(input, ctx) {
    gptr_abort("needs a path", "invalid_argument", arg = "path", expected = "a path")
  })
  expect_true(all(gptr_check(classed)$ok))
})

test_that("prompt sections must fit their budget", {
  local_registry()
  big = gptr_prompt_section("big", paste(rep("word", 500), collapse = " "), budget = 50L)
  res = gptr_check(big)
  expect_false(res$ok[res$check == "section.budget"])
  dyn = gptr_prompt_section("dyn", function(ctx) "x")
  expect_true(all(gptr_check(dyn)$ok))
})

test_that("policies are run over the modes x report 18 matrix", {
  local_registry()
  plan_guard = gptr_policy("plan_guard", function(call, ctx) {
    if (ctx$mode() == "plan" && call$risk$level > 0) list(decision = "deny", reason = "plan")
  })
  res = gptr_check(plan_guard)
  expect_true(all(res$ok[res$check != "policy.speed"]))
  expect_match(res$message[res$check == "policy.speed"], "^median [0-9.]+ ms$")
  expect_match(res$message[res$check == "policy.matrix"], "40 calls", fixed = TRUE)
  odd = gptr_policy("odd", function(call, ctx) list(decision = "maybe"))
  expect_false(gptr_check(odd)$ok[gptr_check(odd)$check == "policy.matrix"])
  # IC-53 item 6: the guards' ask_human tier (P11's mode and critical_guard) is well formed
  human = gptr_policy("human", function(call, ctx) {
    if (call$risk$level >= 4L) list(decision = "ask_human", reason = "level 4")
  })
  expect_true(gptr_check(human)$ok[gptr_check(human)$check == "policy.matrix"])
  thrower = gptr_policy("thrower", function(call, ctx) stop("policy bug"))
  res = gptr_check(thrower)
  expect_match(res$message[res$check == "policy.matrix"], "policy bug", fixed = TRUE)
})

test_that("backends: cancel must leave no child process", {
  skip_on_cran()
  local_registry()
  procs = new.env()
  start = function(spec, ctx) {
    p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"))
    procs$p = p
    list(proc = p)
  }
  withr::defer(if (!is.null(procs$p)) procs$p$kill())
  leaky = gptr_backend("leaky", start = start, cancel = function(handle) NULL)
  res = gptr_check(leaky)
  expect_false(res$ok[res$check == "backend.processes"])
  procs$p$kill()
  tidy = gptr_backend("tidy", start = start, cancel = function(handle) handle$proc$kill())
  expect_true(all(gptr_check(tidy)$ok))
})

test_that("adapters are replayed through the check.adapter service when it exists", {
  local_registry()
  # P12 registers check.adapter from on_load(); with the empty scratch registry every built-in
  # counts as active, so the "no service" case needs an empty bootstrap table in the full suite
  old = the$services
  withr::defer(assign("services", old, envir = the))
  assign("services", list(), envir = the)
  wire = gptr_adapter("wire", transport = "inprocess",
                      stream = function(model, context, opts) function() NULL)
  expect_equal(gptr_check(wire)$check, c("spec.class", "spec.fields"))
  ext_service_set("check.adapter", function(adapter, fixtures = NULL) {
    check_rows(list(check_row("adapter:wire", "adapter.golden_events", TRUE),
                    check_row("adapter:wire", "adapter.tool_choice", FALSE, "list tool_choice")))
  }, provided_by = "P12")
  res = gptr_check(wire)
  expect_equal(res$check, c("spec.class", "spec.fields", "adapter.golden_events",
                            "adapter.tool_choice"))
  expect_false(res$ok[[4]])
})

test_that("factories: load, register, no action at load, and every registered spec passes", {
  local_registry()
  res = gptr_check(function(gptr) {
    gptr$register(gptr_command("panel", function(args, ctx) "ok"))
    gptr$register(gptr_tool("long", paste(rep("word", 600), collapse = " "),
                            execute = function(input, ctx) "x"))
  })
  expect_true(all(res$ok[res$check %in% c("factory.load", "factory.registers",
                                          "factory.no_action")]))
  expect_true("command:panel" %in% res$target)
  expect_false(res$ok[res$target == "tool:long" & res$check == "tool.description_tokens"])
  expect_equal(nrow(gptr_registry()), 0L)
  broken = gptr_check(function(gptr) stop("factory bug"))
  expect_false(broken$ok[broken$check == "factory.load"])
  expect_match(broken$message[broken$check == "factory.load"], "factory bug", fixed = TRUE)
  empty = gptr_check(function(gptr) NULL)
  expect_false(empty$ok[empty$check == "factory.registers"])
  withr::defer(Sys.unsetenv("GPTR_P02_ACTION"))
  noisy = gptr_check(function(gptr) {
    Sys.setenv(GPTR_P02_ACTION = "1")
    gptr$register(gptr_command("x", function(args, ctx) NULL))
  })
  expect_false(noisy$ok[noisy$check == "factory.no_action"])
  expect_match(noisy$message[noisy$check == "factory.no_action"], "env", fixed = TRUE)
  withr::local_options(gptr.p02_action = NULL)
  optioned = gptr_check(function(gptr) {
    options(gptr.p02_action = TRUE)
    gptr$register(gptr_command("y", function(args, ctx) NULL))
  })
  expect_match(optioned$message[optioned$check == "factory.no_action"], "options", fixed = TRUE)
})

test_that("installed plugin packages: manifest, API, provides and bare identifiers (IC-42)", {
  local_registry()
  root = withr::local_tempdir()
  dir.create(file.path(root, "gptr"))
  decl = list(`trials/search` = list(signature = "search(condition: string)",
                                     description = "Search ClinicalTrials.gov"))
  provides = list(tool = list("trials/search"), command = list("panel", "missing"))
  man = list(name = "gptrpanel", version = "0.1.0", gptr = list(api = ">= 1.0, < 2"),
             extension = list(entry = "gptrpanel::gptr_plugin", activation = "lazy",
                              provides = provides, declarations = decl))
  writeLines(json_encode(man), file.path(root, "gptr", "plugin.json"))
  factory = function(gptr) {
    gptr$require(">= 1.0, < 2") # nolint: object_usage_linter.
    gptr$register(gptr_tool("search", "Search ClinicalTrials.gov for recruiting trials",
                            fun = function(condition) condition, exposure = "r",
                            namespace = "trials"))
    gptr$register(gptr_command("panel", function(args, ctx) "panel"))
  }
  objects = list(
    gptr_plugin = factory,
    panel_review = function(file) gptr::peter(paste("Review", file), model = opus),
    with_arg = function(m, file) peter(file, model = m, mode = "auto"),
    with_local = function(file) {
      judge = "jev"
      gptr_agent("judge", description = "Judge", model = judge)
    }
  )
  local_mocked_bindings(
    ext_pkg_path = function(pkg, ...) if (length(list(...))) file.path(root, ...) else root,
    ext_pkg_factory = function(pkg, fun) objects[[fun]],
    ext_pkg_objects = function(pkg) objects,
    ext_pkg_description = function(pkg, field) NA_character_
  )
  res = gptr_check("gptrpanel", tokens = TRUE)
  ok = stats::setNames(res$ok, res$check)
  expect_true(all(ok[c("package.installed", "manifest.present", "manifest.valid", "api.declared",
                       "api.satisfied", "factory.exported", "factory.load",
                       "provides.tool:trials/search", "provides.command:panel",
                       "tokens.declarations")]))
  expect_false(ok[["provides.command:missing"]])
  expect_false(ok[["code.identifiers"]])
  msg = res$message[res$check == "code.identifiers"]
  expect_match(msg, "panel_review: model = opus", fixed = TRUE)
  # peter() forces a local in its caller's frame; gptr_agent() stores it unevaluated (IC-34)
  expect_match(msg, "with_local: model = judge", fixed = TRUE)
  expect_false(grepl("with_arg", msg, fixed = TRUE))
  local_mocked_bindings(ext_pkg_path = function(pkg, ...) "")
  res = gptr_check("notinstalled")
  expect_equal(res$check, "package.installed")
  expect_false(res$ok)
})

test_that("tokens = TRUE reports declaration costs and the printed cost of examples", {
  local_registry()
  member = gptr_spec("tool", "rows", description = "Rows of a data frame.",
                     fun = function(n = "5") seq_len(as.integer(n)), exposure = "r",
                     namespace = "demo", output_tokens = 30L,
                     examples = list(list(n = "3"), list(n = "500")))
  res = gptr_check(member, tokens = TRUE)
  expect_true(res$ok[res$check == "tokens.declaration"])
  expect_true(res$ok[res$check == "tokens.example.1"])
  expect_false(res$ok[res$check == "tokens.example.2"])
  expect_match(res$message[res$check == "tokens.example.2"], "budget 30", fixed = TRUE)
})

test_that("gptr_check() output prints one line per check", {
  local_registry()
  res = gptr_check(gptr_command("hello", function(args, ctx) "hi"))
  expect_output(print(res), "<gptr_check> 2 check(s), 0 failed", fixed = TRUE)
  expect_output(print(res), "ok    command:hello  spec.fields", fixed = TRUE)
})

test_that("the contract 6.7 example passes", {
  local_registry()
  res = gptr_check(gptr_tool("add", "Add two numbers",
                             parameters = list(type = "object", required = I(c("a", "b")),
                                               properties = list(a = list(type = "number"),
                                                                 b = list(type = "number"))),
                             fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
  expect_true(all(res$ok))
})

test_that("checks see the live registry's records and services but never change them", {
  reg = local_registry()
  old = the$services
  withr::defer(assign("services", old, envir = the))
  ext_service_set("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    list(level = 0L)
  }, provided_by = "P11", builtin = "permissions")
  registry_add(gptr_policy("mode", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_tool("panel", "Panel", fun = function() 1, exposure = "r"), "user", 3L)
  registry_add(gptr_command("mine", function(args, ctx) "x"), "session", 0L, session = "s1")
  before = gptr_registry()
  uses_risk = gptr_policy("uses_risk", function(call, ctx) {
    ctx$risk(call$input$code %||% "")
    NULL
  })
  res = gptr_check(uses_risk)
  expect_true(res$ok[res$check == "policy.matrix"])
  clash = gptr_check(function(gptr) {
    gptr$register(gptr_tool("x", "X", fun = function() 1, exposure = "r", namespace = "panel"))
  })
  expect_false(clash$ok[clash$check == "factory.load"])
  expect_match(clash$message[clash$check == "factory.load"], "existing peter$ member",
               fixed = TRUE)
  expect_identical(gptr_registry(), before)
  expect_identical(registry_env(), reg)
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
})

test_that("the identifier scan knows arrow assignments and for-loop variables (IC-42)", {
  arrowed = function(file) NULL
  body(arrowed) = call("{", call(ext_binding_heads[[2]], as.name("judge"), "jev"),
                       quote(peter(file, model = judge)))
  looped = function(files) {
    for (m in c("a", "b")) peter(files, model = m)
  }
  bare = function(file) gptr_agent("x", description = "d", skills = statistics)
  expect_equal(ext_bare_identifiers(list(arrowed = arrowed, looped = looped)), character())
  expect_equal(ext_bare_identifiers(list(bare = bare)), "bare: skills = statistics")
  stored = function(m) gptr_agent("x", description = "d", model = m, backend = m)
  valued = function(m) gptr_agent("x", description = "d", model = I(m))
  expect_equal(ext_bare_identifiers(list(stored = stored, valued = valued)), "stored: model = m")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ext-check")'`
Expected: errors such as `could not find function "gptr_check"`, until testthat stops with `Maximum number of failures exceeded; quitting.`

- [ ] **Step 3: Write the implementation**

Append to `R/ext-check.R`:

```r
# ---- conformance (contract 6.7 gptr_check(), 7.2; architecture 11.4) ----------------------------
# Adapted from the verified G1 prototype (report G1 5.1 check.R: check_row(),
# with_scratch_registry(), the tool, policy, factory and package suites) and its checks 5.2/5.5.

#' One conformance row (contract 5.11: target, check, ok, message)
#' @noRd
check_row = function(target, check, ok, message = "") {
  data.frame(target = as.character(target), check = as.character(check), ok = isTRUE(ok),
             message = paste(as.character(message), collapse = "; "), stringsAsFactors = FALSE)
}

#' Bind rows into a `gptr_check` data frame
#' @noRd
check_rows = function(rows) {
  df = if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(target = character(), check = character(), ok = logical(), message = character(),
               stringsAsFactors = FALSE)
  }
  rownames(df) = NULL
  structure(df, class = c("gptr_check", "data.frame"))
}

#' Rows of a gptr_check data frame as a list of one-row frames
#' @noRd
check_as_rows = function(df, target) {
  lapply(seq_len(nrow(df)), function(i) {
    check_row(target, df$check[[i]], df$ok[[i]], df$message[[i]] %||% "")
  })
}

#' Run `fun()` in a scratch registry that mirrors the current one: its plugin kinds and its
#' enabled, active process-level records (never session records or lazy placeholders). Without
#' the records, P01's ext_service_get() would treat every bootstrap service owned by a loaded
#' built-in as filtered out (the scratch lists records but none of that built-in), so a policy
#' calling ctx$risk() would fail its matrix, and a plugin namespace clashing with a live member
#' would pass. Checks register only into the scratch, so nothing leaks into the live registry
#' @noRd
check_in_scratch = function(fun) {
  live = registry_env()
  scratch = registry_scratch()
  for (nm in ls(live$kinds)) {
    d = get(nm, envir = live$kinds, inherits = FALSE)
    fresh = is.null(get0(nm, envir = scratch$kinds, inherits = FALSE))
    if (!identical(d$source, "builtin") && fresh) {
      assign(nm, d, envir = scratch$kinds)
    }
  }
  scratch$seq = live$seq
  for (id in ls(live$recs)) {
    rec = get(id, envir = live$recs, inherits = FALSE)
    keep = is.null(rec$session) && identical(rec$state, "active") &&
      !is.null(get0(rec$kind, envir = scratch$kinds, inherits = FALSE)) &&
      !registry_rec_filtered(rec, live)
    if (!keep) next
    rec$ext = NULL
    assign(id, rec, envir = scratch$recs)
    registry_index_push(scratch$by_kind, rec$kind, id)
    registry_index_push(scratch$by_key, paste(rec$kind, rec$name, sep = "\r"), id)
    if (identical(rec$kind, "hook")) {
      registry_index_push(scratch$hooks, rec$spec[["event"]] %||% rec$name, id)
    }
  }
  old = registry_swap(scratch)
  on.exit(registry_swap(old), add = TRUE)
  fun()
}

#' Child process ids of this R process (for "no action at load" and backend cancel checks)
#' @noRd
check_children = function() {
  kids = tryCatch(ps::ps_children(ps::ps_handle()), error = function(e) list())
  sort(vapply(kids, function(p) as.integer(ps::ps_pid(p)), 0L))
}

#' Tools: schema validity, direct description at most 400 tokens, empty-input handling
#' @noRd
check_tool = function(spec, target) {
  rows = list()
  params = spec[["parameters"]]
  if (is.list(params)) {
    probs = schema_problems(params)
    rows = c(rows, list(check_row(target, "tool.schema", !length(probs), probs)))
  } else {
    rows = c(rows, list(check_row(target, "tool.schema", TRUE,
                                  "a function of ctx, evaluated when a session freezes")))
  }
  if (identical(spec[["exposure"]], "direct")) {
    n = est_tokens(spec[["description"]], "prose")
    rows = c(rows, list(check_row(target, "tool.description_tokens", n <= 400,
                                  paste0(n, " tokens (a direct tool allows at most 400)"))))
  }
  c(rows, list(check_tool_empty(spec, target)))
}

#' Empty input: rejected by the schema, or answered with a result or a classed gptr condition
#' @noRd
check_tool_empty = function(spec, target) {
  params = spec[["parameters"]]
  required = if (is.list(params)) as.character(unlist(params[["required"]])) else character()
  if (length(required)) {
    rejected = !isTRUE(schema_validate(params, json_obj())$ok)
    return(check_row(target, "tool.empty_input", rejected,
                     if (rejected) "empty input fails schema validation before execute()" else
                       "the schema requires properties but accepts empty input"))
  }
  run = if (is.function(spec[["execute"]])) {
    function() as_tool_result(spec[["execute"]](json_obj(), ctx_new(NULL)))
  } else {
    function() spec[["fun"]]()
  }
  res = tryCatch({
    run()
    NULL
  }, gptr_error = function(e) NULL, error = function(e) e)
  check_row(target, "tool.empty_input", is.null(res),
            if (is.null(res)) "" else paste0("empty input raised an unclassed error: ",
                                             conditionMessage(res)))
}

#' Prompt sections: a fixed text fits its token budget
#' @noRd
check_section = function(spec, target) {
  text = spec[["text"]]
  if (!is.character(text)) {
    return(list(check_row(target, "section.budget", TRUE, "rendered when a session freezes")))
  }
  n = est_tokens(text, "prose")
  list(check_row(target, "section.budget", n <= spec[["budget"]],
                 paste0(n, " tokens (budget ", spec[["budget"]], ")")))
}

#' Synthetic tool calls of report 18 section 4.7 (contract 4.4 call records): tool, input, level
#' @noRd
check_policy_calls = function() {
  rows = list(
    list("read", list(path = "R/analysis.R"), 0L, "read"),
    list("read", list(path = "/etc/hosts"), 1L, "read"),
    list("read", list(path = "~/.ssh/id_rsa"), 2L, "secret"),
    list("write", list(path = "R/analysis.R", content = "x = 1"), 2L, "file_write"),
    list("edit", list(path = ".Rprofile", edits = list()), 3L, "control"),
    list("r", list(code = "summary(x)"), 0L, "read"),
    list("r", list(code = "y = x + 1"), 1L, "object_write"),
    list("r", list(code = "write.csv(x, 'x.csv')"), 2L, "file_write"),
    list("r", list(code = "unlink('data', recursive = TRUE)"), 3L, "file_delete"),
    list("r", list(code = "rm(list = ls())"), 4L, "critical")
  )
  lapply(seq_along(rows), function(i) {
    r = rows[[i]]
    list(id = paste0("check_", i), name = r[[1]], input = r[[2]], raw = NULL, tool = NULL,
         nested = FALSE, parent_id = NULL, outer_level = NULL,
         risk = list(level = r[[3]], categories = r[[4]], paths = character()))
  })
}

#' Policies: every verdict over the modes x report 18 matrix is NULL or a valid decision, no
#' call throws, and the median call takes at most 10 ms (contract 10.2 row 12)
#' @noRd
check_policy = function(spec, target) {
  cell = new.env(parent = emptyenv())
  cell$mode = "manual"
  kernel = function() list(mode = function(ctx) cell$mode, model = function(ctx) "check/check-1")
  # rank 0 (a process-wide record of the scratch registry) wins over any mirrored ctx.kernel
  id = registry_add(gptr_spec("service", "ctx.kernel", fun = kernel), "session", 0L)
  on.exit(registry_remove(id), add = TRUE)
  ctx = ctx_new(NULL)
  bad = character()
  times = numeric()
  for (mode in c("plan", "manual", "edits", "auto")) {
    cell$mode = mode
    for (call in check_policy_calls()) {
      t0 = proc.time()[["elapsed"]]
      v = tryCatch(spec[["check"]](call, ctx), error = function(e) e)
      times = c(times, proc.time()[["elapsed"]] - t0)
      why = if (inherits(v, "error")) {
        paste0("error: ", conditionMessage(v))
      } else if (!is.null(v) && !ext_policy_ok(v)) {
        "malformed decision"
      }
      if (!is.null(why)) bad = c(bad, paste0(mode, "/", call$name, " level ", call$risk$level,
                                             ": ", why))
    }
  }
  med = stats::median(times)
  list(
    check_row(target, "policy.matrix", !length(bad),
              if (length(bad)) utils::head(bad, 3L) else paste(length(times), "calls")),
    check_row(target, "policy.speed", med <= 0.01, paste0("median ", round(med * 1000, 2), " ms"))
  )
}

#' Backends: start() and cancel() of a probe succeed and cancel leaves no child process
#' @noRd
check_backend = function(spec, target) {
  before = check_children()
  probe = list(name = "gptr-check", prompt = "conformance probe", model = NULL,
               tools = character())
  h = tryCatch(spec[["start"]](probe, ctx_new(NULL)), error = function(e) e)
  rows = list(check_row(target, "backend.start", !inherits(h, "error"),
                        if (inherits(h, "error")) conditionMessage(h) else ""))
  if (inherits(h, "error")) return(rows)
  cancelled = tryCatch({
    spec[["cancel"]](h)
    NULL
  }, error = function(e) e)
  rows = c(rows, list(check_row(target, "backend.cancel", is.null(cancelled),
                                if (is.null(cancelled)) "" else conditionMessage(cancelled))))
  t0 = proc.time()[["elapsed"]]
  repeat {
    extra = setdiff(check_children(), before)
    if (!length(extra) || proc.time()[["elapsed"]] - t0 > 2) break
    Sys.sleep(0.05)
  }
  c(rows, list(check_row(target, "backend.processes", !length(extra),
                         if (length(extra)) paste("still running after cancel: pid", extra) else
                           "")))
}

#' Adapters: fixture replay through the `check.adapter` service (P12) when it is available. The
#' name check_adapter() belongs to P12's service implementation (04 section 7.12)
#' @noRd
check_adapter_rows = function(spec, target, adapter_check) {
  if (is.null(adapter_check)) return(list())
  res = tryCatch(adapter_check(spec), error = function(e) e)
  if (inherits(res, "error")) {
    return(list(check_row(target, "adapter.replay", FALSE, conditionMessage(res))))
  }
  check_as_rows(res, target)
}

#' Token costs (IC-69): the declaration, and the printed result of each of a member's `examples`
#' (a list of argument lists)
#' @noRd
check_tokens = function(spec, target) {
  rows = list(check_row(target, "tokens.declaration", TRUE,
                        paste0(spec_tokens(spec), " tokens")))
  examples = spec[["examples"]]
  if (!identical(spec$kind, "tool") || !is.list(examples) || !is.function(spec[["fun"]])) {
    return(rows)
  }
  budget = spec[["output_tokens"]] %||% gptr_opt("helper_output_tokens")
  for (i in seq_along(examples)) {
    out = tryCatch(utils::capture.output(print(do.call(spec[["fun"]], as.list(examples[[i]])))),
                   error = function(e) e)
    row = if (inherits(out, "error")) {
      check_row(target, paste0("tokens.example.", i), FALSE, conditionMessage(out))
    } else {
      n = est_tokens(out, "r_output")
      check_row(target, paste0("tokens.example.", i), n <= budget,
                paste0(n, " tokens printed (budget ", budget, ")"))
    }
    rows = c(rows, list(row))
  }
  rows
}

#' The conformance rows of a spec (contract 6.7)
#' @noRd
check_spec = function(spec, tokens = FALSE, adapter_check = NULL) {
  kind = if (is.list(spec)) spec[["kind"]] else NULL
  name = if (is.list(spec)) spec[["name"]] else NULL
  ok_kind = is.character(kind) && length(kind) == 1L && !is.na(kind)
  ok_name = is.character(name) && length(name) == 1L && !is.na(name)
  target = paste0(if (ok_kind) kind else "?", ":", if (ok_name) name else "?")
  ok_class = inherits(spec, "gptr_spec") && ok_kind && ok_name
  rows = list(check_row(target, "spec.class", ok_class,
                        if (ok_class) "" else "not a gptr_spec with a kind and a name"))
  if (!ok_class) return(rows)
  valid = tryCatch(spec_finish(unclass(spec), kind_get(kind)), error = function(e) e)
  if (inherits(valid, "error")) {
    msg = if (inherits(valid, "gptr_error_invalid_spec") && is.character(valid$field)) {
      paste0("field '", valid$field, "' ", valid$problem)
    } else {
      conditionMessage(valid)
    }
    return(c(rows, list(check_row(target, "spec.fields", FALSE, msg))))
  }
  rows = c(rows, list(check_row(target, "spec.fields", TRUE)))
  rows = c(rows, switch(kind,
    tool = check_tool(valid, target),
    prompt_section = check_section(valid, target),
    policy = check_policy(valid, target),
    backend = check_backend(valid, target),
    adapter = check_adapter_rows(valid, target, adapter_check),
    list()
  ))
  if (tokens) rows = c(rows, check_tokens(valid, target))
  rows
}

#' What a factory may not change while it loads: working directory, search path, environment
#' variables, options, the random-number state and child processes ("no action at load",
#' contract 6.7; IC-61)
#' @noRd
check_snapshot = function() {
  list(wd = getwd(), search = search(), env = Sys.getenv(), options = options(),
       seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
       children = check_children())
}

#' The conformance rows of a factory, loaded eagerly in the (scratch) registry (contract 6.7)
#' @noRd
check_factory = function(factory, manifest = NULL, tokens = FALSE, adapter_check = NULL) {
  source = "plugin:gptr-check"
  target = "factory"
  before = check_snapshot()
  ok = withCallingHandlers(
    ext_load(factory, source = source, rank = 5L, manifest = manifest),
    gptr_warning_plugin = function(w) invokeRestart("muffleWarning")
  )
  after = check_snapshot()
  reg = registry_env()
  recs = Filter(function(r) identical(r$source, source) && !identical(r$state, "lazy"),
                registry_recs(reg, ls(reg$recs)))
  recs = recs[order(vapply(recs, function(r) r$order, 0L))]
  d = reg$diag$rows
  mine = Filter(function(r) identical(r$source, source), d)
  why = if (length(mine)) mine[[length(mine)]]$message else ""
  same = vapply(names(before), function(n) identical(before[[n]], after[[n]]), NA)
  changed = names(before)[!same]
  rows = list(
    check_row(target, "factory.load", ok, if (isTRUE(ok)) "" else why),
    check_row(target, "factory.registers", length(recs) > 0L, paste(length(recs), "record(s)")),
    check_row(target, "factory.no_action", !length(changed),
              if (length(changed)) paste("changed at load:", paste(changed, collapse = ", ")) else
                "")
  )
  provides = ext_provides(manifest)
  for (kind in names(provides)) {
    for (nm in provides[[kind]]) {
      got = vapply(recs, function(r) {
        identical(r$kind, kind) && (identical(r$name, nm) || identical(r$spec[["event"]], nm))
      }, NA)
      rows = c(rows, list(check_row(target, paste0("provides.", kind, ":", nm), any(got),
                                    if (any(got)) "" else "declared but not registered")))
    }
  }
  for (r in recs) rows = c(rows, check_spec(r$spec, tokens, adapter_check))
  rows
}

#' A file of an installed package ("" when absent); mockable in tests
#' @noRd
ext_pkg_path = function(pkg, ...) system.file(..., package = pkg)

#' An exported function of a package (loads its namespace); mockable in tests
#' @noRd
ext_pkg_factory = function(pkg, fun) getExportedValue(pkg, fun)

#' A DESCRIPTION field of an installed package (NA when absent); mockable in tests
#' @noRd
ext_pkg_description = function(pkg, field) {
  v = suppressWarnings(utils::packageDescription(pkg, fields = field))
  if (is.character(v) && length(v) == 1L) v else NA_character_
}

#' The objects of a package namespace as a named list; mockable in tests
#' @noRd
ext_pkg_objects = function(pkg) {
  ns = asNamespace(pkg)
  nms = ls(ns, all.names = TRUE)
  out = lapply(nms, function(n) get0(n, envir = ns, inherits = FALSE))
  names(out) = nms
  out
}

#' Is element `i` of a call's parts the empty (missing) argument?
#' @noRd
ext_is_empty = function(parts, i) identical(parts[[i]], quote(expr = ))

#' Call `visit(call)` for every call inside an expression
#' @noRd
ext_walk_calls = function(expr, visit) {
  if (!is.call(expr)) return(invisible(NULL))
  visit(expr)
  parts = as.list(expr)
  for (i in seq_along(parts)) {
    if (!ext_is_empty(parts, i)) ext_walk_calls(parts[[i]], visit)
  }
  invisible(NULL)
}

#' Name of a called function, with the gptr:: prefix removed ("" for other heads)
#' @noRd
ext_call_name = function(call) {
  h = call[[1L]]
  if (is.name(h)) return(as.character(h))
  if (is.call(h) && identical(h[[1L]], as.name("::")) && identical(h[[2L]], as.name("gptr"))) {
    return(as.character(h[[3L]]))
  }
  ""
}

#' The assignment operators and `for` (the arrows are written as \u escapes, so that no arrow
#' appears in gptr's own source)
#' @noRd
ext_binding_heads = c("=", "\u003c-", "\u003c\u003c-", "for")

#' Names a function binds locally: its formals, assignment targets and for-loop variables
#' @noRd
ext_local_names = function(f) {
  acc = new.env(parent = emptyenv())
  acc$names = names(formals(f))
  ext_walk_calls(body(f), function(call) {
    head = ext_call_name(call)
    if (head %in% ext_binding_heads && length(call) >= 2L && is.name(call[[2L]])) {
      acc$names = c(acc$names, as.character(call[[2L]]))
    }
  })
  unique(acc$names)
}

#' Bare identifiers passed to gptr's identifier arguments in package code (IC-42): a symbol that
#' is neither local nor a binding of the package or base makes R CMD check report "no visible
#' binding" and should be a string. gptr_agent() stores `model` and `skills` unevaluated (IC-34)
#' and the gateway resolves them in the frame of a later peter() call, where the package
#' function's locals and objects are not visible, so every bare symbol there is reported (use a
#' string, or I(x) for a variable's value)
#' @noRd
ext_bare_identifiers = function(objects) {
  args = c("model", "mode", "preset", "skills", "agents", "tools", "plugins", "extensions",
           "backend")
  heads = c("peter", "gptr_agent", "gptr_parallel")
  known = names(objects)
  acc = new.env(parent = emptyenv())
  acc$found = character()
  for (fn in names(objects)) {
    f = objects[[fn]]
    if (!is.function(f) || is.primitive(f)) next
    local = ext_local_names(f)
    ext_walk_calls(body(f), function(call) {
      head = ext_call_name(call)
      if (!(head %in% heads)) return(NULL)
      nms = names(call)
      for (i in seq_along(nms)) {
        if (!(nms[[i]] %in% args) || ext_is_empty(as.list(call), i)) next
        v = call[[i]]
        if (!is.name(v)) next
        sym = as.character(v)
        raw = identical(head, "gptr_agent") && nms[[i]] %in% c("model", "skills")
        if (!raw && (sym %in% c(local, known) || exists(sym, envir = baseenv()))) next
        acc$found = c(acc$found, paste0(fn, ": ", nms[[i]], " = ", sym))
      }
      NULL
    })
  }
  unique(acc$found)
}

#' The conformance rows of an installed plugin package (contract 6.7, 11.12; IC-42)
#' @noRd
check_package = function(pkg, tokens = FALSE, adapter_check = NULL) {
  target = paste0("package:", pkg)
  installed = nzchar(ext_pkg_path(pkg))
  rows = list(check_row(target, "package.installed", installed))
  if (!installed) return(rows)
  path = ext_pkg_path(pkg, "gptr", "plugin.json")
  present = nzchar(path) && file.exists(path)
  rows = c(rows, list(check_row(target, "manifest.present", present, "inst/gptr/plugin.json")))
  man = NULL
  if (present) {
    man = tryCatch(json_decode(paste(readLines(path, encoding = "UTF-8", warn = FALSE),
                                     collapse = "\n")), error = function(e) e)
    valid = is.list(man) && !inherits(man, "error") && is.character(man[["name"]]) &&
      length(man[["name"]]) == 1L
    rows = c(rows, list(check_row(target, "manifest.valid", valid,
                                  if (inherits(man, "error")) conditionMessage(man) else "")))
    if (!valid) man = NULL
  }
  req = man[["gptr"]][["api"]]
  if (is.null(req)) {
    desc = ext_pkg_description(pkg, "Config/gptr/api")
    if (!is.na(desc)) req = desc
  }
  rows = c(rows, list(check_row(target, "api.declared", !is.null(req), req %||% "")))
  if (!is.null(req)) {
    ok = isTRUE(tryCatch(api_satisfies(req), error = function(e) FALSE))
    rows = c(rows, list(check_row(target, "api.satisfied", ok,
                                  paste0("requires ", req, "; this gptr provides ",
                                         ext_api_version))))
  }
  entry = man[["extension"]][["entry"]]
  if (is.character(entry) && length(entry) == 1L) {
    factory = tryCatch(ext_pkg_factory(pkg, sub("^.*::", "", entry)), error = function(e) e)
    exported = is.function(factory)
    rows = c(rows, list(check_row(target, "factory.exported", exported, entry)))
    if (exported) rows = c(rows, check_factory(factory, man, tokens, adapter_check))
  }
  if (tokens && !is.null(man)) {
    decl = man[["extension"]][["declarations"]] %||% list()
    n = sum(vapply(decl, function(d) {
      est_tokens(paste(d[["signature"]] %||% "", d[["description"]] %||% ""), "code")
    }, 0))
    rows = c(rows, list(check_row(target, "tokens.declarations", TRUE,
                                  paste0(n, " tokens in ", length(decl), " declaration(s)"))))
  }
  bare = ext_bare_identifiers(ext_pkg_objects(pkg))
  hint = if (length(bare)) paste("use strings for", paste(bare, collapse = ", ")) else ""
  c(rows, list(check_row(target, "code.identifiers", !length(bare), hint)))
}

#' Check an extension for conformance
#'
#' Runs gptr's conformance suite, offline, in a scratch registry. For a spec: its fields and kind
#' validator, schema validity, direct tool descriptions of at most 400 tokens, prompt-section
#' budgets, empty-input handling of tools, the permission matrix for policies, start and cancel
#' for backends, and wire-fixture replay for adapters when the adapter checker is available. For
#' a factory `function(gptr)`: it loads, registers something, takes no action at load, and each
#' registered spec passes. For an installed package name: its `inst/gptr/plugin.json` manifest,
#' API requirement, factory, every provided capability, and bare gptr identifiers in its code.
#'
#' @param x A spec, a factory `function(gptr)`, or the name of an installed plugin package.
#' @param error `TRUE` to signal `gptr_error_conformance` when a check fails.
#' @param tokens `TRUE` to also report declaration costs and the printed cost of each member's
#'   `examples`.
#' @return A `gptr_check` data frame with columns `target`, `check`, `ok` and `message`.
#' @examples
#' gptr_check(gptr_tool("add", "Add two numbers",
#'                      parameters = list(type = "object", required = I(c("a", "b")),
#'                                        properties = list(a = list(type = "number"),
#'                                                          b = list(type = "number"))),
#'                      fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
#' @export
gptr_check = function(x, error = FALSE, tokens = FALSE) {
  check_flag(error, "error")
  check_flag(tokens, "tokens")
  adapter_check = if (ext_service_has("check.adapter")) ext_service_get("check.adapter") else NULL
  rows = check_in_scratch(function() {
    if (is.list(x) && !is.data.frame(x)) {
      check_spec(x, tokens, adapter_check)
    } else if (is.function(x)) {
      check_factory(x, NULL, tokens, adapter_check)
    } else if (is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)) {
      check_package(x, tokens, adapter_check)
    } else {
      gptr_abort("`x` must be a spec, a factory function(gptr) or an installed package name.",
                 "invalid_argument", arg = "x",
                 expected = "a gptr_spec, a function(gptr) or a package name")
    }
  })
  out = check_rows(rows)
  if (error && !all(out$ok)) {
    gptr_abort(paste0("gptr_check() found ", sum(!out$ok), " failing check(s): ",
                      paste(unique(out$check[!out$ok]), collapse = ", "), "."),
               "conformance", results = out)
  }
  out
}

#' Print conformance results: one line per check
#' @export
#' @noRd
print.gptr_check = function(x, ...) {
  cat("<gptr_check> ", nrow(x), " check(s), ", sum(!x$ok), " failed\n", sep = "")
  for (i in seq_len(nrow(x))) {
    msg = x$message[[i]]
    cat(if (x$ok[[i]]) "  ok    " else "  FAIL  ", x$target[[i]], "  ", x$check[[i]],
        if (nzchar(msg)) paste0(": ", msg) else "", "\n", sep = "")
  }
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::document()'`, then `Rscript --vanilla -e 'devtools::test(filter = "ext-check")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 224 ]`

- [ ] **Step 5: Commit**

```sh
git add R/ext-check.R tests/testthat/test-ext-check.R NAMESPACE man/gptr_check.Rd
git commit -m "feat(ext): add gptr_check() conformance suites"
```

---

## Plan acceptance

Every acceptance check of 05 P02, including its review amendments, with the task and test that prove it. Run from the repository root after Task 11.

| # | Check (05 P02) | Proven by | Command and expected result |
|---|---|---|---|
| 1 | `devtools::test(filter = "ext")` is green | all tasks | `Rscript --vanilla -e 'devtools::test(filter = "ext")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS n ]`, where n is the 982 expectations of the seven `test-ext-*.R` files plus those of P01's `test-utils-text.R`, which the pattern `"ext"` also selects; P02's files alone: `Rscript --vanilla -e 'devtools::test(filter = "^ext-")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 982 ]`. Under R CMD check on CRAN (`NOT_CRAN` unset) the backend-process test skips: `SKIP 1`. |
| 2a | ported G1 check: precedence by rank | Task 4, `test-ext-registry.R` "the lowest rank wins per (kind, name): session < project < user < plugin < builtin", "ties go to the first registration with a collision diagnostic" | as row 1 |
| 2b | filters | Task 5, `test-ext-registry.R` "-kind:name hides a record and +kind:name restores it", "a later scope's + undoes an earlier scope's -", "-builtin:<name> and -plugin:<name> disable every record of that source" | as row 1 |
| 2c | a replaceable built-in overridden by a user spec | Task 4 "overrides are per record: a user read leaves the built-in edit and grep (IC-69)"; Task 10 `test-ext-builtins.R` "a user record overrides one record of a built-in, not the whole built-in (IC-69)" | as row 1 |
| 2d | rollback of a factory that errors after two registrations | Task 9, `test-ext-load.R` "a factory that errors after two registrations is rolled back (G1 check)" | as row 1 |
| 2e | unmet API requirement disables only that factory | Task 9 "an unmet API requirement disables only that factory (G1 check)" | as row 1 |
| 2f | stale API object raises `gptr_error_stale_api` after `gptr_reload()` | Task 9 "a stale API object raises gptr_error_stale_api after gptr_reload() (G1 check)" | as row 1 |
| 2g | a throwing `policy` and a throwing `permission_request` hook both deny | Task 8, `test-ext-events.R` "a throwing policy denies; malformed answers deny; NULL has no opinion", "a throwing permission_request hook denies; the first answer wins" | as row 1 |
| 2h | a throwing `document_write` hook blocks | Task 8 "document_write: lines patch, block stops, a throwing hook blocks" (and "tool_call: modify flows on, block stops, and a throwing hook blocks (fail closed)") | as row 1 |
| 2i | a notify hook error becomes a diagnostic | Task 8 "notify runs listeners then hooks by rank; a handler error is a diagnostic" | as row 1 |
| 2j | a plugin-defined kind is registered and resolved | Task 4 "registry_remove() drops a record; a kind record defines and undefines its kind"; Task 6 "register_<kind>() is gptr_spec() sugar for every kind, including plugin kinds"; Task 9 "a factory can define a kind and use it; a rollback removes the kind" | as row 1 |
| 3 | `gptr_check()` passes a valid spec of every kind, names the failing field of an invalid one, and fails a direct tool description over 400 tokens | Task 11, `test-ext-check.R` "gptr_check() passes a valid spec of every kind (acceptance 3)", "an invalid spec fails and names the failing field; error = TRUE signals", "a direct tool description over 400 tokens fails (acceptance 3)" | as row 1 |
| 4 | registering 100 lazy manifests takes under 50 ms (G1 measured 8-16 ms) | Task 9 "100 lazy manifests register quickly" (the test bound is 5 s, conventions §7) and this benchmark (a warm-up pass, then a fresh registry): `Rscript --vanilla -e 'devtools::load_all(quiet = TRUE); m = function(i) list(name = paste0("p", i), extension = list(activation = "lazy", provides = list(tool = list(paste0("t", i))), declarations = stats::setNames(list(list(signature = paste0("t", i, "(x)"), description = "A tool.")), paste0("t", i)))); run = function() { old = registry_swap(registry_scratch()); on.exit(registry_swap(old)); system.time(for (i in 1:100) ext_load(function(gptr) NULL, paste0("plugin:p", i), 5L, manifest = m(i), lazy = TRUE))[["elapsed"]] }; invisible(run()); cat(sprintf("100 lazy manifests: %.0f ms\n", 1000 * run()))'` | prints `100 lazy manifests: <t> ms` with t below 50 (measured 13-14 ms; 11-12 ms with the installed, byte-compiled package; the first, cold pass under `load_all()` also compiles the functions and took 48-51 ms, which is why the benchmark warms up) |
| 5a | every §6.8 example of the contract runs (IC-35) | Task 3 "every example of contract 6.8 runs and returns its class (IC-35)"; the roxygen examples | as row 1; `Rscript --vanilla -e 'devtools::run_examples(document = FALSE)'` finishes without an error |
| 5b | a user `read` override leaves `edit` and the `peter$grep` member working | Task 4 and Task 10 (rows 2c) | as row 1 |
| 5c | a factory loaded with `session = <id>` is invisible to another session and removed at its shutdown | Task 9 "a factory loaded with session = <id> is invisible to other sessions (IC-69)"; Task 8 "session_shutdown drops the session's records after its handlers ran (IC-69)" | as row 1 |
| 5d | a `-builtin:permissions` filter from user settings, a call and `gptr_config()` is refused | Task 5 "no filter from user settings, a call or gptr_config() disables the kernel (IC-53)" (scopes `user`, `session` and `project`; P08's `gptr_config(filters =)` and call arguments reach the registry only through `registry_filters_set()`); Task 10 "non-replaceable built-ins cannot be filtered out (IC-53)" | as row 1 |
| 5e | a plugin `service` record replaces a built-in service and disappears with its plugin | Task 9 "a plugin service record replaces a built-in service and leaves with its plugin"; Task 7 "a service record replaces the bootstrap service of the same name (IC-34)" | as row 1 |
| 5f | an `operator` context block registered at rank 1 is refused | Task 4 "registration rules that depend on the source: operator blocks and namespaces" | as row 1 |

Further review amendments in scope (05 P02 "Review amendments"), each covered: IC-69 overrides per record (rows 2c, 5b); IC-53 filters inside a run (Task 5 "inside a run, filters that remove policies or hooks are refused (IC-53)", "inside a run, dropping a + that keeps a policy enabled is refused (IC-53)") and control exports (Task 4 "gptr_register() is refused from model code during a run unless granted (IC-53)", Task 9 "gptr_reload() is refused from model code during a run (IC-53)", Task 8 "runs and executing tools are tracked from agent and tool events (IC-53)", "an unused control grant ends with the top-level call it was granted in (IC-53)"); `ext_load(..., session =)` (row 5c; Task 9 "a session's extension releases its factory and captured frames (R10)"); IC-35 signatures (Task 3 "constructors pick the first choice and report missing or wrong arguments", `test-ext-specs.R` "adapter specs are validated per transport (IC-35)"); IC-34 `gptr_agent()` raw expressions (Task 3 "gptr_agent() stores the raw captured expressions (IC-34)"); the IC-69 `ctx` members and IC-55 `ctx$send()` source (Task 7 "ctx members call the P06 kernel with the ctx first, lazily at call time", "ctx services: ui, risk, secret, tokens, eval, describe, decide, add_tools, input"); the `request_params` event (Task 8 "request_params patches only `params`; unset declared keys can be added (IC-69)"); `gptr_check(tokens =)` (Task 11 "tokens = TRUE reports declaration costs and the printed cost of examples", and the package test's `tokens.declarations` row); IC-52 (row 5f).

Also run:

- `Rscript --vanilla -e 'devtools::test(filter = "lint|arch")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS n ]`: P01's `test-lint-rules.R` and `test-arch-layers.R` pass with the seven `ext-*.R` files in `R/` (no `:::`, no `<-`, ASCII only, no `lockBinding`, no `withr::`, no literal-free `cli_*()` calls; every `ext-*.R` callee is L0).
- `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'` -> no lint; exit 0 (P01 acceptance A3's command: loading the namespace first lets `object_usage_linter` see the package's internal functions on the uninstalled development tree). Test lines that call the API member `require()` with a string carry `# nolint: object_usage_linter.`, because lintr reads any `require("x")` call as loading package `x`.
- `Rscript --vanilla -e 'devtools::document()'` -> `NAMESPACE` exports the 18 P02 names of 04 §14.1 (plus P01's `gptr_fake_provider`) and registers the S3 methods `$`, `[[`, `$<-`, `[[<-` and `print` for `gptr_ctx` and `gptr_extension_api`, `format` and `print` for `gptr_spec` and `gptr_tool_result`, and `print` for `gptr_registry`, `gptr_diagnostics`, `gptr_api` and `gptr_check`.

## Self-review

**Spec coverage (05 P02 scope -> task).**

| Scope item | Task |
|---|---|
| registry keyed by (kind, name) with ranks 0/1/3/5/6, diagnostics, generation counter | 2 (state), 4 (records, resolution, diagnostics), 9 (generation bump) |
| filters `-builtin:`, `-<kind>:`, `+...`; project filters cannot disable user or built-in policies and hooks | 5 |
| `gptr_register()`, `gptr_registry()` with the `tokens` column | 4 |
| the 37 kinds and their validators (IC-02, IC-34, IC-69, §10.2) | 2 (table), 4 (`kind` records), 3 (constructors) |
| `ctx` members bound lazily through P01's service table (IC-09, IC-34, §7.0) | 7 |
| `gptr_spec()` and the 11 exported constructors; `gptr_tool_result()` | 2, 3 |
| the factory API object: `register()`, `register_<kind>()` for every kind, `on()`, `require()`, `has()`, `state` | 6 |
| the `ctx` object and its members; "not available" before their plan | 7 |
| the event catalogue with notify, transform, patch, first decision, block; fail-closed `tool_call`, `permission_request`, `document_write` | 1, 8 |
| transactional factory loading (stage, commit, rollback), lazy activation with `declarations`, API requirements, `gptr_reload()` with stale-API errors | 6, 9 |
| `gptr_check()` conformance for specs and factories (and packages); `gptr_api()` | 11, 6 |
| the built-in declaration table filled by `on_load(ext_declare_builtin(...))`, loaded in dependency order | 10 |
| review amendments: IC-69 overrides, IC-53 filters and control exports, `ext_load(session =)`, IC-35 signatures, IC-34 agents, IC-69/IC-55 `ctx` members, `request_params`, `gptr_check(tokens =)`, IC-52 operator blocks | 3, 4, 5, 7, 8, 9, 11 (Plan acceptance lists the tests) |
| option `gptr.deprecations`, warning class `deprecated` (04 §3.1, §2.2 owner P02) | 6 (API members), 7 (`ctx` members) |
| copy safety (03 §6.4 R1, R2, R5, R10): no binding locks; `ctx` holds the session shell only; failed, unloaded, reloaded and session-scoped extensions release their factories and per-load state (`ext_forget()`) | 4, 6, 7, 9 |
| the 10 ms policy budget and cheap `ctx` members: the cached `gptr_registry()` listing behind P01's service lookups | 4, 7 |

Every acceptance check of 05 P02 maps to a named test in "Plan acceptance".

**Placeholder scan.** The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task" and "write tests for the above": none occur. Every step that changes code shows the complete code. Functions called before the task that defines them (`ext_activate_record()` in Tasks 4 and 8, `kind_stage()` in Task 6, `ctx_default()` and `ext_service_try()` in Tasks 2-3, `ev_dispatch()` in Task 7, `ext_load_builtins()` in Task 5) are named in each task's notes and are reached only by code paths that the earlier tasks' tests do not exercise.

**Type and name consistency with 04.** Signatures of the 18 exports match 04 §6.7, §6.8 and IC-35 exactly (Global Constraints); internal signatures match 04 §7.2 (`registry_add`, `registry_remove`, `registry_get`, `registry_all`, `registry_names`, `registry_generation`, `registry_filters_set`, `registry_diagnostic`, `kind_define`, `kind_get`, `kind_names`, `spec_new`, `as_tool_result`, `ev_dispatch`, `ev_catalogue`, `hook_add`, `hook_remove`, `ext_api_new`, `ctx_new`, `ext_load`, `ext_activate`, `ext_declare_builtin`, `ext_load_builtins`), including `check_spec(spec)`, `check_factory(factory)` and `check_package(pkg)` (optional trailing arguments `tokens`, `adapter_check` and, for factories, `manifest`; each returns the rows of a `gptr_check` as a list that `gptr_check()` binds; no other plan calls them). The adapter rows come from the private `check_adapter_rows(spec, target, adapter_check)`: the name `check_adapter()` belongs to P12 (04 §7.12, `check_adapter(adapter, fixtures = NULL)` in `R/provider-anthropic.R`, the `check.adapter` service), so no P02 file defines a function of that name (a second top-level definition would be replaced silently by the later-collating file and fail P01's "every function one home" test). Classes: `gptr_<kind>`/`gptr_spec`, `gptr_tool_result`, `gptr_registry`, `gptr_diagnostics`, `gptr_extension_api`, `gptr_ctx`, `gptr_check`, `gptr_api`, `gptr_registry_env` (04 §5.4-5.7, §5.11, §5.13). Condition classes and fields are those of 04 §2.2 listed in Global Constraints. Event names, semantics and handler returns are 04 §10.4 and §10.7; kind names, resolve modes and order fields are 04 §10.2; the service names used (`ctx.kernel`, `ctx.input`, `ui.get`, `risk.classify`, `secret.lookup`, `eval.r`, `describe`, `s1.decide`, `session.add_tools`, `agent_def.get`, `check.adapter`) are all in 04 §7.0, so P01's architecture test maps them.

**Contract ambiguities (resolved as stated, implemented, and tested).**

1. 04 §6.8 says "Arguments not listed in §10.2 for the kind signal `gptr_error_invalid_spec`", but the §6.8 signatures have no `...`, so an unknown constructor argument is R's "unused argument" error; fields that a constructor does not take (`render` of a tool, `examples`) are set with `gptr_spec()`, whose validators keep unknown fields (§10.2 forward compatibility). Wrong values of known fields are `gptr_error_invalid_spec` naming the field.
2. The `model` kind: §4.9's display `name` collides with the spec name, which §10.2 fixes as `provider/id`; the display name is the field `label`.
3. IC-53 point 3 asks `gptr_register()` and `gptr_reload()` to check `run_current()` (P06), which an L0 file cannot call. P02 mirrors active runs and executing tools from the `agent_start`/`agent_end` and `tool_execution_start`/`tool_execution_end` events that P06 dispatches through `ev_dispatch()`; the one-shot approval is recorded by P06/P11 with `ext_control_grant(run, what)` after the `ask_human` approval. "Exactly that call": a grant is consumed by its first use, and an unused one is dropped at the `tool_execution_end` of the top-level call it was granted in (a `tool_call_id` without `/`; P06's nested calls are `<outer>/<k>` and end inside it), the same lifetime P06's `tool_execute_frame()` gives `run$signal$control`; `agent_end` drops whatever remains.
4. 04 §7.0 gives `ctx.kernel` as "`function() named list` of the §10.6 member implementations" without a calling convention. Task 7 calls `impl(ctx, ...)` with positional arguments and, for `send`, `append_entry` and `state`, adds the handler's source (`ctx_source(ctx)`, e.g. `"plugin:panel"`) as an optional last positional argument only inside a handler. This is the convention `dev/plan/P06-session-kernel-agent-loop.md` implements (`send(ctx, text, as, extension = NULL)`, `append_entry(ctx, type, data, extension = NULL)`, `state(ctx, extension = NULL)`, the label `"panel"` derived by P06's `ctx_ext_label()`); passing it positionally keeps P02 independent of the argument's name.
5. `registry_all("tool")` returns lazy placeholders (`lazy = TRUE`, `declaration`, `source`) without activating them, so catalogs can use declarations before activation (§10.8 declarations are signature lines of `r` members and direct tools); `registry_get()` and `registry_all()` of every other kind activate first, so consumers such as P05's `catalog_model_specs()` (`registry_all("model")`) never see a placeholder without the kind's fields.
6. `gptr_reload()` "re-discovers declarative resources", which P17 and P18 own and 04 §7.0 gives no service for; P02 increments `registry_generation()`, which those owners use as their cache key.
7. `gptr_check(tokens = TRUE)` reports "the printed-result cost of each member on its examples"; §9.1 has no examples field. Reading: an optional tool field `examples` (a list of argument lists), kept by the validator as an unknown field.
8. "a backend (cancel leaves no process)": `gptr_check()` starts the backend with a probe spec (`name`, `prompt`, `model = NULL`, `tools`), cancels it, and compares the R process's children (`ps`) for up to 2 s.
9. 05 acceptance 4 (100 lazy manifests under 50 ms) against conventions §7 ("No wall-clock assertions tighter than 5 seconds"): the test asserts 5 s and the 50 ms target is the separate benchmark of Plan acceptance row 4.
10. IC-69 validates `backend` against `registry_names("backend")` plus `"auto"`; agents can be defined before the built-in that registers their backend is loaded, so `gptr_agent()` accepts any string and the check belongs where the agent runs (P19).
11. §7.2 "payload redacted with `stream` first": handlers see the redacted copy; the patched payload `ev_dispatch()` returns is built from the unredacted payload, so the kernel never receives stream-redacted data back from a dispatch.
12. `gptr$state` is "an environment private to the extension, process lifetime": one per `plugin:`/`builtin:` source; for the shared source strings `session`, `user` and `project` one per load.
13. `ev_dispatch()` called with a session but without a ctx builds one for that call; sessions (P06) pass their own ctx, which 04 §10.6 creates once per session. Caching a ctx per session inside the registry would keep sessions alive (R10).
14. `-builtin:<name>` for a built-in declared with `replaceable = FALSE` is refused like the permission kernel's (04 §7.2 "`replaceable` now only decides whether a `-builtin:<name>` filter may disable it"); its individual records can still be filtered with `-<kind>:<name>`, except records of `builtin:permissions`, `builtin:plan` and `builtin:secrets`.
15. A `context_block` with `authority = "operator"` is refused by `registry_add()` for ranks below 3 (the constructor cannot know the rank).
16. `gptr_hook()` names its spec after its event (hooks resolve `all`, so several hooks of one event coexist).
17. P02 uses the 04 names of P01 exactly as `dev/plan/P01-foundation.md` defines them, and was validated against code assembled from that plan (see below). P01's `service_builtin_active()` decides built-in ownership of bootstrap services by listing `gptr_registry()` on every `ext_service_get()`/`ext_service_has()`; P02 therefore caches the full listing (`reg$listing`, keyed on `registry_touch()`'s counter and the protected built-ins), which took a `ctx` member call from about 14 ms to 0.1 ms with 320 records.
18. The settings key `filters` (04 §11.2) is P02's, but only the settings layer knows which layer a value came from (`settings.get` returns merged values): P08 passes each layer's `filters` to `registry_filters_set()` with `scope = "user"`, `"project"` or `"session"`, and P02 enforces the IC-53 and project rules per scope.
19. "decision (`tool_call`) ... error = block" (04 §10.7) says nothing about answers that are not `NULL`, `block` or `modify`. A list whose `decision` is anything else (for example `"deny"`, the policy word) blocks with a `malformed_decision` diagnostic, as a malformed policy answer denies (§10.2 row 12); non-list returns (the value of a logging assignment) have no opinion.
20. Setting a filter scope replaces its filters. Inside a run, dropping a `+key` that undid an earlier scope's `-key` would remove a policy or hook without any `-` filter; such a `+key` is kept and reported in `refused` (IC-53 "filters that would remove `policy` or `hook` records are refused").
21. "first decision: the first non-`NULL` return wins" (04 §10.7) is read together with the "Handler may return" column of §10.4, which lists only lists: a non-list return (the value of `log$n = log$n + 1`) and an empty list have no opinion. Otherwise a logging hook would hide every later handler and hand emitters a number where they read `res$cancel` (P07's `isTRUE(dec$cancel)` fails with "$ operator is invalid for atomic vectors").
22. `request_params` (IC-69): only the emitter knows the adapter's declared `capabilities$request_params`, and P06's `run_request_params()` sends only the declared keys that are set. P02 therefore lets handlers patch `params` only (other top-level fields are ignored with a `patch_ignored` diagnostic) and merges its keys, so a handler can add a declared key that is unset (`metadata`, `user`); P06 drops undeclared keys with its own `ignored_patch` diagnostic. Dropping keys absent from the payload in P02 made those params impossible to set.
23. Filters naming a kind that is not registered yet are kept with a `filter_unknown_kind` diagnostic: a kind defined by a lazy plugin's factory does not exist when the settings layer applies user filters at session start.
24. `gptr_check()`'s scratch registry mirrors the live registry's enabled, active process-level records as well as its plugin kinds: with an otherwise empty scratch, P01's `service_builtin_active()` reports every built-in-owned bootstrap service as filtered out.
25. IC-42's bare-identifier scan treats `gptr_agent()`'s `model` and `skills` differently from `peter()`'s identifier arguments: `gptr_agent()` stores them unevaluated (IC-34) for a later `peter()` call to resolve in its own frame, so even a local symbol there is reported (use a string or `I(x)`).
26. IC-53 point 3 names `gptr_register()`; the unregister function it returns is guarded the same way, because users keep it in the environment model code evaluates in and removing a policy reconfigures gptr as much as adding one. The unregister functions of `gptr$register()` (plugin code) are not guarded.
27. Policy decisions: 04 §10.2 row 12 lists `allow`, `deny`, `ask`, `modify`; 04 §7.6 (`perm_check()` combines every policy's answer as deny > ask_human > ask > modify > allow) and §15 IC-53 item 6 (the `ask_human` tier of the guards), which win, add `ask_human`, and P11's built-in policies (`mode`, `critical_guard`, `secret_guard`, `plan`) answer it. `ext_policy_ok()` therefore accepts the five decisions, `ext_policy_decide()` returns an `ask_human` unchanged, and `gptr_check()`'s `policy.matrix` passes a policy that answers it.
28. Tests of a "not available" fallback (the `ctx` members, `gptr_agent(name)`, `gptr_check()` without `check.adapter`) hide P01's bootstrap service table for their duration (`local_no_bootstrap_services()`, or the same three lines inline in `test-ext-check.R`), as P01's `local_services()` does: later plans register `ctx.kernel`, `session.add_tools`, `describe`, `eval.r`, `risk.classify`, `s1.decide`, `agent_def.get` and `check.adapter` there from `on_load()`, and with the empty scratch registry of `local_registry()` P01's `service_builtin_active()` counts every built-in as active, so without the isolation these tests fail in the full suite from P06 on (P06 review row 14).

**Executed validation (author 2026-09-30; re-run by the review 2026-10-01; R 4.4.3, macOS, testthat 3.3.2, lintr 3.3.0.1).**

- Every `r` block of this plan was extracted (26 blocks) and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse, all ASCII, no line over 100 characters. `getParseData()` finds no `LEFT_ASSIGN` token (no `<-` and no `<<-`) and no `%>%` in any block; the only arrow character sequences in code are the names of the replacement methods `` `$<-.gptr_ctx` ``, `` `[[<-.gptr_ctx` ``, `` `$<-.gptr_extension_api` `` and `` `[[<-.gptr_extension_api` `` that 04 §5.6 requires (IC-72 notes that a text regex flags such names, which is why P01's lint test reads tokens); the assignment operators that `gptr_check()` looks for in package code are written as `\u` escapes.
- The review assembled a scratch package from the code blocks of `dev/plan/P01-foundation.md` (its `R/` files, `setup.R`, `helper-fake.R`, `helper-tracemem.R`, `helper-mock-server.R`) and this plan's blocks in task order. Each task was run red (its implementation blocks left out) and green with the exact commands of Steps 2 and 4; every summary line quoted in the tasks is the observed one.
- `devtools::test(filter = "^ext-")`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 975 ]` (events 117, specs 207, registry 124, api 172, load 103, builtins 29, check 223; after the fixes of the Plan review log, re-run 2026-10-01 against code assembled from the current `dev/plan/P01-foundation.md`). With P01's `test-lint-rules.R` (its scanner inserted as P01 Task 20 says), `helper-arch.R`, `test-arch-layers.R` and the lint fixture: `devtools::test(filter = "lint|arch")` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]`.
- `devtools::run_examples(document = FALSE)`: every example runs offline.
- `lintr::lint()` of the seven `R/ext-*.R` and seven `test-ext-*.R` files with P01's `.lintr` linters and `object_usage_linter = NULL` (it needs an installed gptr): 0 lints.
- Probes in the scratch package, before and after the review fixes (320 records from 8 built-ins): `ctx$mode()` through a built-in-owned bootstrap `ctx.kernel` 14.4 ms -> 0.1 ms, `ext_service_get()` 7.3 ms -> 0.2 ms; a session-scoped factory closing over a 40 MB frame stayed in `reg$exts` after `session_shutdown` -> released; a `tool_call` hook answering `list(decision = "deny")` allowed the call -> blocks; inside a run, `registry_filters_set(character(), "session")` dropped a `+policy:audit` and disabled the policy -> refused.
- Second review pass, probes before and after its fixes: a `session_before_compact` hook returning the value of `log$n = log$n + 1` won the first decision (`ev_dispatch()` returned the number 1, hiding a later `list(cancel = TRUE)`) -> the later list wins; a policy calling `ctx$risk()` failed `gptr_check()`'s `policy.matrix` with a `risk.classify` service owned by a loaded `builtin:permissions` ("ctx$risk() is not available") -> passes; `builtin_fake()` of P01 loads through `ext_load()` and its two adapters validate. After the fixes, Steps 2 and 4 of Tasks 4, 5, 7, 8, 9 and 11 were re-run red and green (every quoted summary line is the observed one), `devtools::test(filter = "lint|arch")` gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]`, `lintr` 0 lints, `devtools::run_examples(document = FALSE)` exit 0, and `codetools::checkUsage()` over every `ext-*.R` function reported nothing.
- Tests never assert the `policy.speed` row (median at most 10 ms), so no test depends on a wall-clock bound tighter than 5 s (conventions §7); the 100-manifest test uses 5 s.
- The lazy-manifest benchmark of Plan acceptance row 4: 13-14 ms (author), 20 ms (review, loaded machine), 25 ms (second review pass, loaded machine), warm under `load_all()`.
- Cross-plan consolidation (2026-10-01): every `r` block re-extracted and parsed; a scratch package assembled from the current `dev/plan/P01-foundation.md` and this plan gave `devtools::test(filter = "^ext-")` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 982 ]` (api 172, builtins 29, check 224, events 123, load 103, registry 124, specs 207), and P01 A3's `pkgload::load_all(quiet = TRUE); lints = lintr::lint_package()` with P01's `.lintr` gave 0 lints. The same package plus a file simulating later plans (bootstrap services `ctx.kernel`, `session.add_tools`, `ctx.input`, `describe`, `eval.r`, `risk.classify`, `ui.get`, `secret.lookup`, `s1.decide`, `agent_def.get` signalling `invalid_argument` as P17's does, and `check.adapter`, all registered from `on_load()`, plus P12's top-level `check_adapter(adapter, fixtures = NULL)` in `R/provider-anthropic.R`) also gave `PASS 982`, FAIL 0; with the consolidation fixes reverted it gave FAIL 30 and 3 errors in 9 tests (the four `ctx`/`gptr_agent` tests, "gptr_check() passes a valid spec of every kind" with `unused argument (adapter_check)`, the policy matrix, the adapter replay test, the grant-lifetime test and the policy evaluator test).

## Plan review log

Adversarial review against `dev/plan/00-conventions.md`, 04 (with §15), 05 P02, 03 §11, report G1 and its verification log, and the dependent plans already written (P01, P03, P05, P06, P07, P08, P11). Rows E1-E8 were applied by the first pass of this review (2026-10-01, before its validation summary above); rows F1-F10 and R1-R6 by the second pass, which re-extracted every block, assembled it with the current `dev/plan/P01-foundation.md` and confirmed each defect with a probe before fixing it.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| E1 | blocker | Task 8 `ev_run_decision()` | A `tool_call` hook answering `list(decision = "deny")` (the policy word) was treated as no opinion, so the call ran: fail-open on a fail-closed event | applied | Any decision other than `NULL`, `allow`, `block` or `modify` with an input list blocks with a `malformed_decision` diagnostic; test "an unknown decision blocks" |
| E2 | major | Task 11 row builders | 04 §7.2 names `check_spec()`, `check_factory()`, `check_package()`; the plan defined `check_*_rows()` | applied | Renamed; self-review consistency paragraph updated |
| E3 | major | Task 4 `gptr_registry()` | P01's `service_builtin_active()` lists `gptr_registry()` on every `ext_service_get()`, so each `ctx` member call cost two full listings (14 ms with 320 records, above the 10 ms policy budget) | applied | Full listing cached in `reg$listing`, keyed on `registry_touch()`'s counter and the protected built-ins (0.1 ms) |
| E4 | major | Tasks 4, 9 (R10) | A session-scoped factory and the frames it closed over stayed in `reg$exts` after `session_shutdown`, as did failed, unloaded and reloaded loads | applied | `ext_forget()` releases the factory, staged items and per-load state; test "a session's extension releases its factory and captured frames (R10)" |
| E5 | major | Task 5 `registry_filters_set()` | Inside a run, replacing a scope's filters could drop a `+policy:x` that undid an earlier `-policy:x`, disabling a policy without any `-` filter (IC-53) | applied | Such a `+` is kept and reported in `refused`; test "inside a run, dropping a + that keeps a policy enabled is refused" |
| E6 | major | Task 7 `ctx` | The plugin-scoped kernel members were called with a named argument that P06's `ctx_kernel()` did not have ("unused argument") | applied, then refined by F5 | Positional last argument |
| E7 | minor | Task 11 `check_snapshot()` | "No action at load" ignored `options()` and `.Random.seed` (IC-61) | applied | Both are in the snapshot; test with `options(gptr.p02_action = TRUE)` |
| E8 | minor | Self-review | Validation had been run against a P01 build, not P01's plan code | applied | Re-validated against blocks assembled from `dev/plan/P01-foundation.md` |
| F1 | major | Task 8 `ev_run_first()` | First-decision events returned any non-`NULL` value: a logging hook (`log$n = log$n + 1` returns a number) won, hid later handlers, and gave emitters a number where they read `res$cancel` (P07's `isTRUE(dec$cancel)` errors "$ operator is invalid for atomic vectors"); probe: `ev_dispatch("session_before_compact", ...)` returned `1` | applied | Non-list and empty returns have no opinion (`ev_usable()`), as for the other semantics; test "first decision: non-list and empty returns have no opinion"; self-review item 21 |
| F2 | major | Task 11 `check_in_scratch()` | The scratch registry held only kinds, so P01's `service_builtin_active()` (non-empty registry without the owning built-in's records) reported every built-in-owned bootstrap service as filtered out: a policy calling `ctx$risk()` failed `policy.matrix` although P11 was loaded (probe), and a plugin namespace clashing with a live member passed | applied | The scratch mirrors the live registry's enabled, active process-level records (no session records, no placeholders, ids kept, `ext` cleared); `check_policy()` registers its kernel at rank 0; test "checks see the live registry's records and services but never change them"; item 24 |
| F3 | major | Task 8 `ev_params_patch()` | `request_params` kept only keys already in the payload, but P06's `run_request_params()` sends only the declared keys that are set, so a hook could never set an unset declared param (`service_tier`, `metadata`, `user`), the event's purpose (IC-69) | applied | Handlers patch `params` only (other top-level fields ignored with `patch_ignored`); its keys merge; undeclared keys are dropped by the emitter, which alone knows `capabilities$request_params`; test rewritten; item 22 |
| F4 | major | Task 4 `registry_unregister_fn()` | The `off()` closure returned by `gptr_register()` removed records without the IC-53 guard; users keep it in the environment model code evaluates in (`off = gptr_register(gptr_policy(...))`), so model code could remove a user policy mid-run | applied | The closure calls `ext_control_guard("gptr_register")`; roxygen and Interfaces updated; test expectations added; item 26 |
| F5 | minor | Task 7 `ctx_call_plugin()`, Interfaces, item 4 | The plan passed the stripped plugin name and described P06's argument as `name`/`plugin`; the current P06 plan names it `extension`, documents "P02 passes `extension = ctx_source(ctx)`" and strips the prefix itself (`ctx_ext_label()`) | applied | The handler's source is passed positionally; `ctx_plugin()` removed; the test's mock kernel now mirrors P06's signatures; texts updated |
| F6 | minor | Task 5 `registry_filters_set()` | A filter on a kind not registered yet was `gptr_error_invalid_argument`; kinds defined by lazy plugins do not exist when the settings layer applies user filters, so every `peter()` call would fail | applied | Kept with a `filter_unknown_kind` diagnostic; malformed filters still error; new test; item 23 |
| F7 | minor | Task 4 `registry_all()` | First-resolving kinds returned lazy placeholders without the kind's fields for every kind; P05's `catalog_model_specs()` (`registry_all("model")`) would read placeholders as models | applied | Only `tool` placeholders (whose declarations feed catalogs, 04 §10.8) stay unactivated; every other kind activates first; Task 9 test "registry_all() activates lazy records of every kind but tool"; item 5 |
| F8 | minor | Task 11 `ext_bare_identifiers()` | IC-42's scan exempted local symbols passed to `gptr_agent(model =, skills =)`, which `gptr_agent()` stores unevaluated (IC-34) for a later `peter()` frame where the local does not exist | applied | Every bare symbol in those two arguments of `gptr_agent()` is reported (strings or `I(x)` pass); tests extended; item 25 |
| F9 | minor | Task 8 `ext_policy_decide()` docs | Described as "the evaluation step of P06's `perm_check()`", but P06's `perm_policies()` evaluates policies itself | applied | Docs say what it is (the 04 §10.2 row 12 single-policy evaluator behind the G1 check) and that no later plan depends on it |
| F10 | minor | Step 2/4 counts, Plan acceptance, Executed validation | Counts changed with the fixes | applied | Re-run red and green: Task 4 80, Task 5 red `FAIL 9 PASS 81` / green 124, Task 8 117, Task 9 103, Task 11 223, total 975 |
| R1 | minor | Tests of `print()` methods | Conventions §7 say printed output is tested with `expect_snapshot()` | rejected | Snapshot files under `tests/testthat/_snaps/` are not among P02's owned files (05), a first run records "Adding new snapshot" warnings that contradict the `WARN 0` lines, and fixed-substring `expect_output()` checks of these short headers are deterministic |
| R2 | minor | Task 5 scopes | Call-level filters (`plugins = "-builtin:x"`) reach the process-wide `session` scope | rejected | 04 §7.2 defines `registry_filters_set(filters, scope)` without a session; P08 records the same reading (its ambiguity 9); per-session filters would be a contract change |
| R3 | minor | Test files | `local_registry()` is repeated in each test file | rejected | P02 owns no `helper-*.R` file (05 "Owns"), and testthat evaluates each test file in its own environment |
| R4 | minor | Task 4 `registry_admit()` | Reserved-namespace check also applies to built-in sources and might block P18 | rejected | `peter$mcp$<server>$<tool>` is the `mcp` member resolved by P18 (04 §9.4), not tool records with `namespace = "mcp"`; built-ins register un-namespaced members |
| R5 | minor | Task 11 `tool.empty_input` | The check calls a tool's `execute()` with empty input, which may have side effects | rejected | 04 §6.7 requires "empty-input handling for tools"; tools with required properties are checked through schema validation only, never executed |
| R6 | major | P06 `perm_policies()` (not a P02 file) | A policy returning a non-list (for example `"yes"`) makes `res$decision` error outside P06's `tryCatch()`, so `perm_check()` throws instead of denying | rejected (out of scope) | P02 may edit only its own plan; P02's own evaluator `ext_policy_decide()` already denies malformed answers; reported for P06's review |

## Cross-plan consolidation log

Issues raised by the cross-plan checkers (lenses ownership, interfaces, shared-names, obligations, trace) on 2026-10-01, verified against 04 (with §15), 05 P02 and the related plans (P01, P06, P07, P09, P11, P12, P13, P17). Each fix was confirmed on a scratch package assembled from the current P01 plan and this plan, alone and with a file that simulates the later plans' bootstrap services and P12's `check_adapter()` (Executed validation, last bullet).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| C1 | ownership | blocker | Task 11 `R/ext-check.R`: private `check_adapter(spec, target, adapter_check)` and its call in `check_spec()` | applied | 04 §7.12 gives `check_adapter(adapter, fixtures = NULL)` to P12 (`R/provider-anthropic.R`, service `check.adapter`), which collates later and replaced P02's helper (probe: `gptr_check()` on the `wire` adapter failed with `unused argument (adapter_check)`). Renamed to `check_adapter_rows()` (definition and its one call in `check_spec()`); its roxygen line names the 04 owner; `kind_check_adapter()` unchanged; no count changes |
| C2 | interfaces | blocker | same as C1 | applied | Same change as C1; the self-review's "Type and name consistency" paragraph now says the adapter rows come from the private `check_adapter_rows()` and that `check_adapter()` belongs to P12 (04 §7.12) |
| C3 | interfaces | major | Task 7 `test-ext-api.R`: "ctx members whose plan is not loaded signal gptr_error_not_available", "gptr_agent(name) loads a definition through agent_def.get, else not available" | applied | New test helper `local_no_bootstrap_services()` (P01's `local_services()` pattern: save `the$services`, defer the restore, empty it) called right after `local_registry()` in both tests; `local_service("agent_def.get", ...)` still works because it registers a registry `service` record. The simulation showed two more Task 7 tests that rely on the absence of `ctx.kernel` ("ctx members call the P06 kernel with the ctx first, lazily at call time" reads the stored run `"u7"` before its mock kernel is registered; "ctx services: ..." expects `ctx$eval("1")` to fail for want of an `envir`); both call the helper too. Task 7 note and self-review item 28 added; no expectations added, so the Task 7 counts are unchanged |
| C4 | shared-names | blocker | same as C1 | applied | Same change as C1 |
| C5 | shared-names | major | Task 7 tests as in C3; Task 11 `test-ext-check.R` "adapters are replayed through the check.adapter service when it exists" | applied | Task 7: as C3. Task 11: the save and deferred restore of `the$services` moved above the first `gptr_check(wire)` and followed by `assign("services", list(), envir = the)`, so the "no service" rows (`spec.class`, `spec.fields`) hold once P12 registers `check.adapter` (P12 adds `adapter.replay` for an inprocess adapter). The other `test-ext-*.R` tests either register their own registry `service` records, which win, or passed with the simulated services |
| C6 | obligations | blocker | same as C1, plus the self-review consistency paragraph | applied | Same change as C1 and C2 |
| C7 | obligations | major | Task 8 `ext_policy_ok()` (decision set) and its roxygen | applied | 04 §7.6 (`perm_check()`: deny > ask_human > ask > modify > allow over every policy's answer) and §15 IC-53 item 6 win over §10.2 row 12, and P11's built-in policies answer `ask_human`. `ext_policy_ok()` accepts `ask_human`; roxygen of `ext_policy_ok()` and of the exported `gptr_policy()` and Task 8 Produces updated; Task 8 test "a throwing policy denies; ..." asserts that `ext_policy_decide()` returns `ask_human` unchanged (+1); Task 11 test "policies are run over the modes x report 18 matrix" asserts that a policy answering `ask_human` passes `policy.matrix` (+1); self-review item 27 |
| C8 | obligations | major | Task 7 test "ctx members whose plan is not loaded signal gptr_error_not_available" | applied (other form) | The proposed fix removes a fixed list of service names from `the$services`; the plan empties the table for the test instead (C3), as P01's `local_services()` does, so a service a later plan adds cannot leak into the fallback assertions; the expectations are the same |
| C9 | obligations | minor | Task 8 `ev_track()` (one-shot control grants) | applied | IC-53 item 3 approves "exactly that call"; an unused grant lived until `agent_end`, so a later unapproved `r` call of the same run could use it. `ev_track()` now drops the run's grants at the `tool_execution_end` of a top-level call (a `tool_call_id` without `/`; P06's nested ids are `<outer>/<k>`), the lifetime P06's `tool_execute_frame()` gives `run$signal$control`; P06 grants inside `dispatch_one()`, between that call's `tool_execution_start` and `tool_execution_end`. New Task 8 test "an unused control grant ends with the top-level call it was granted in (IC-53)" (+5); `ext_control_guard()` roxygen, Task 8 Produces, Plan acceptance amendments paragraph and self-review item 3 updated |
| C10 | obligations | minor | Plan acceptance "Also run", lint bullet | applied | Replaced `lintr::lint_package()` (which reports every internal call on an uninstalled tree) with P01 A3's `pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)` -> no lint, exit 0 (measured: 0 lints on the assembled P01 + P02 package with P01's `.lintr`); the installed-gptr caveat is gone |
| C11 | trace | minor | same as C10 | applied | Same change as C10 |
| C12 | (counts) | minor | Task 8 Step 4, Task 11 Step 4, Plan acceptance row 1, Executed validation | applied | Measured on the assembled package: `ext-events` 117 -> 123, `ext-check` 223 -> 224, `^ext-` total 975 -> 982; the other files are unchanged (api 172, builtins 29, load 103, registry 124, specs 207) |
