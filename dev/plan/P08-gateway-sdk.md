# P08 Gateway and SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `gptr()` itself (copy-safe base-R capture, identifier resolution, `{identifier}` interpolation, routing through registry `route` records) together with the settings layers, trust, egress and replay controls and the session SDK verbs, so that the whole S-8 session contract of milestone M1 runs offline on the fake provider.

**Architecture:** Four layer-L6 files. `gptr-config.R` owns the settings layers of contract 11.2 (package defaults < user file < project file under the trust rules < user-level project file < `options(gptr.*)` < the session layer), `gptr_config()`, `gptr_init()`, `gptr_trust()` with trust fingerprints, the egress acknowledgement, `replay_mode()`/`replay_guard()` and the `settings.get`/`trust.get` services. `gptr-capture.R` turns one `gptr(...)` call into a `gptr_call` record without ever forcing a plain-symbol dot (rules R2-R3, IC-41), resolves bare identifiers (contract 6.1.3, IC-42) and interpolates literal prompts; `gptr-gateway.R` holds the classed closure `gptr`, walks the `route` records in `order` and registers the `builtin:gateway` routes `nested` (20), `continue` (60) and `new` (70), the core `setting` specs and the `router.call` service; `gptr-sdk.R` holds the verbs `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()` and `gptr_return()`. P08 reaches the kernel only through the kernel SDK of IC-33 and later plans only through services of contract 7.0 with their documented fallbacks.

**Tech Stack:** base R (>= 4.2.0); rlang (`obj_address()` only; no quosures, rule R3); jsonlite through P01's `json_encode()`/`json_decode()`; ps (lock owner creation times); grDevices (PNG rendering of `.opts$images` plots); testthat 3e, withr and processx in tests only.

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2, §4.1, §4.2, §5.1, §6.2, §6.3, §6.4, §6.8.5, §6.9.1, §6.10, §8.4, §11.1), dev/spec/04-interface-contract.md (§1.1-1.5, §2.1-2.2, §3.1-3.2, §4.2, §4.5, §5.1, §5.3, §5.11, §5.13, §6.1, §6.2 `gptr_init()`/`gptr_config()`/`gptr_trust()`, §6.5 `gptr_step()`/`gptr_wait()`/`gptr_steer()`/`gptr_cancel()`/`gptr_on()`, §6.6 `gptr_return()`, §7.0, §7.1, §7.2, §7.5, §7.6, §7.8, §8.2, §10.1-10.7, §11.1-11.3, §11.8, §11.16, §12; §15: IC-33, IC-34, IC-36, IC-39..IC-45, IC-48, IC-52, IC-53, IC-55, IC-57, IC-61, IC-62, IC-66, IC-69, IC-71), dev/spec/05-plan-decomposition.md (P08).

**Depends on:** P03, P07 (and through them P01, P02, P04, P05, P06). **Milestone:** M1 (P08 is the milestone's last plan: its acceptance includes the M1 exit check).

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only for closure state), the native `|>` (never `%>%`), ASCII-only R sources (non-ASCII as `\u` escapes), `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions (messages built by plain concatenation, never glue-interpolated), no `:::` in `R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed global state restored with `on.exit(..., add = TRUE)`, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line required by the executing harness (conventions §10). Plan-specific requirements, copied from the specification:

- Owned files (05 P08): `R/gptr-gateway.R`, `R/gptr-capture.R`, `R/gptr-sdk.R`, `R/gptr-config.R`, their tests `tests/testthat/test-gptr-gateway.R`, `test-gptr-capture.R`, `test-gptr-sdk.R`, `test-gptr-config.R`, the copy suite `tests/testthat/test-copy-gateway.R`, and `inst/templates/` (`vignette.Rmd`, `settings.json`, `gitignore`); plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`.
- Layers (03 §3.2): all four files are L6. They call L0-L3 functions, the kernel SDK of IC-33 (`session_data()`, `session_live()`, `session_home()`, `session_append()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`, `session_value_set()`, `session_run()`, `run_start()`, `run_wait()`, `run_abort()`, `run_current()`, `last_set()`, ...) and services only; P08 never calls a function of P09-P25 by name.
- Exports (04 §14.1: P08's 10 names), exact signatures:
  `gptr(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL, extensions = NULL, tools = NULL, agents = NULL, parallel = NULL, choices = NULL, levels = NULL, threshold = 0.5, min_confidence = NULL, uncertain = NULL, prompt = NULL, envir = parent.frame(), background = FALSE, budget = NULL, replay = NULL, .opts = list(), .run = TRUE, .stdin = FALSE)`;
  `gptr_init(path, instructions = TRUE, gitignore = TRUE)`; `gptr_config(..., .scope = NULL)`; `gptr_trust(path = ".", trust = NULL)`;
  `gptr_step(s, turns = 1L)`; `gptr_wait(x, timeout = Inf)`; `gptr_steer(s, text, as = c("steer", "follow_up"))`; `gptr_cancel(x)`; `gptr_on(s, event, handler, matcher = NULL)`; `gptr_return(x)`.
- Classes: `gptr` has `class(gptr) == c("gptr_gateway", "function")` with methods `$`, `[[`, `$<-`, `[[<-` (refuse, `gptr_error_readonly`), `.DollarNames` and `print` (04 §5.3); `gptr_config` is "named list of effective settings with attribute `sources` (named chr: key -> layer); `print` shows value and source per key" (04 §5.11); `gptr_call` is an environment (04 §5.13, §7.8).
- The `gptr_call` record (IC-13, 04 §7.8): bindings `id` (`c` + 8 hex), `prompt`, `template`, `session`, `context` (one `list(label, kind = "symbol" | "value" | "literal", name, slot, facts = list(class, dim, length, bytes, is_chr1))` per context dot), `values` (env, `.v1`, `.v2`, ...), `envir` (reset to `NULL` by `call_release()` [R2]), `ids` (`model`, `mode`, `skills`, `plugins`, `extensions`, `tools`, `agents`), `args` (`parallel`, `choices`, `levels`, `threshold`, `min_confidence`, `uncertain`, `background`, `budget`, `replay`, `opts`, `run`, `stdin`), `sys_call`, `nframe`, `top_level` (`NA` until P15's locator), `doc`; plus `interp` ("the sorted `name=value` pairs used", 04 §6.1.4).
- Internal functions with contract signatures (04 §7.8): `call_new(...)`, `call_release(call)`, `call_value(call, i)`, `route_pass()`, `gateway_defer(expr_fun)`, `gateway_run(call, s = NULL)`, `dot_facts(x)`, `resolve_identifier(expr, arg, envir)`, `identifier_known(name, arg)`, `interpolate_prompt(template, envir)`, `settings_get(key, session = NULL)`, `settings_effective()`, `settings_write(scope, patch)`, `trust_get(path = getwd())`, `home_address(envir)`, `replay_mode(arg = NULL)`, `replay_guard(model, what = "model call")`, `egress_check(provider_id)`.
- Services provided (04 §7.0): `settings.get` = `function(key, session = NULL) value`; `trust.get` = `function(path = getwd()) lgl(1)` (fallback `FALSE`); `identifier.resolve` = `function(expr, arg, envir) chr or spec`; `router.call` = `function(s, reason) list(model, thinking, state)`. Each is registered with `on_load(ext_service_set(<name>, <fun>, provided_by = "P08", builtin = "gateway"))`.
- Services consumed, with the fallback each consumer documents: `ns.resolve` (`$`/`[[` of `gptr`; `gptr_error_not_available` before P10), `ns.names` (`.DollarNames`; `character(0)` before P10), `context.first`/`context.turn`/`session.add_tools` (P07), `console.interrupt_policy` (P14; abort-only fallback), `skill.body` and `plugin.enable` (P17; `gptr_error_not_available`), `bg.register` (P21; `gptr_error_not_available`).
- Built-in (04 §10.3): `builtin:gateway` registers "routes `nested` (20), `continue` (60), `new` (70); core `setting` specs", not replaceable. Route orders (IC-39): `classifier` 10, `team` 15, `fanout` 16, `nested` 20, `console` 30, `document` 50, `continue` 60, `new` 70.
- Settings (04 §11.2): layers "package defaults < user `settings.json` < project `.gptr/settings.json` < the user-level project file `projects/<hash>.json` (IC-52) < `options(gptr.*)` < `gptr_config(.scope = "session")` < call arguments"; "An **untrusted** project contributes only changes that tighten `tighten`-type settings"; `egress` "is read only from the user file". Core keys and defaults exactly as the 04 §11.2 table (`version` 1, `model` null, `small_model` null, `system1` null, `mode` `"manual"` with tighten order `plan, manual, edits, auto`, `preset` `"standard"`, `tools` `{}`, `permissions` `{}`, `context` `"summary"` (`none, names, summary`), `record` `"ask"` (`off, ask, auto`), `replay` `"auto"`, `transcript` `"ask"`, `plugins` `[]`, `filters` `[]`, `skills` `{budget: 1500}`, `mcp` `{exposure: "r", budget: 1500, import: [...]}`, `subagents` `{max_depth: 1, max_active: 8, max_workers: null, max_cli: 4, max_tasks: 8}`, `output_tokens` null, `plot` `{width: 768, height: 512, res: 120}`, `budget` `{tokens: 2000000, cost: 5, turns: null}`, `cache` `{ttl: "gap"}`, `compactor` `"checkpoint"`, `compact_at` `200000`, `checkpoint` `"on"`, `doc` `{outputs: true, output_lines: 12}`, `cache_commit` `{s1: true, s2: false}`, `ui` null, `frontend` null, `store` `"jsonl"`, `evaluator` `"r"`, `providers` `{}`, `egress` `{}` user file only).
- Files: user settings `tools::R_user_dir("gptr", "config")/settings.json`; project settings `.gptr/settings.json`; user-level project file `R_user_dir("gptr", "config")/projects/<first 16 hex of sha256(path_key(project root))>.json` (`{"version": 1, "root": ..., "permissions": {...}, "transcript": {...}, "record": {...}}`); `trust.json` = `{"version": 1, "projects": {"<path_key of the project root>": {"trusted": true, "date": "2026-09-29", "fingerprint": "<sha256 of the trust-gated files>", "base_url_confirmed": {...}}}}`; trust-gated files (IC-52) `.gptr/settings.json`, `mcp.json`, `extensions/`, `plugins/`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `agents/`, an auto-discovered `.env`. All JSON "UTF-8 without BOM, LF, written atomically (`write_atomic()`)", "Unknown keys are preserved on rewrite"; read-modify-write "under a short `mkdir` lock (`<file>.lock/`, pid + creation time, 50 x 100 ms retries)" (IC-71).
- Templates (04 §11.16): `inst/templates/vignette.Rmd` "an R Markdown document with a YAML header (`title: "Project instructions"`, `output: html_document`), a first line `@AGENTS.md` comment hint (as an HTML comment), and sections "Data", "Conventions", "Do not" with placeholder bullets; it contains no executable chunks"; `inst/templates/settings.json` = `{"version": 1, "mode": "manual", "record": "ask"}`; `inst/templates/gitignore` = the ten lines of 04 §11.1 (`sessions/`, `cache/s2/`, `cache/tmp/`, `checkpoints/`, `artifacts/*/v*/data/`, `artifacts/*/run/`, `locks/`, `*.lock/`, `settings.local.json`, `transcripts/`).
- Options owned (04 §3.1): `gptr.model`, `gptr.mode`, `gptr.preset`, `gptr.system1`, `gptr.small_model` (option layer of the settings keys, default "settings"); `gptr.replay` (resolution; default settings `"auto"`); `gptr.interpolate` (`TRUE`); `gptr.subagents.max_depth` (`1L`; "nesting depth of child sessions (at most 2)"). Environment variables read: `GPTR_REPLAY` ("replay mode below the option") and `TESTTHAT` (`"true"` under testthat: no forced replay). Options consumed (owned elsewhere): `gptr.prompt_secrets` (owner P03, default `"redact"`, "secret-looking text in prompts: `"redact"` or `"ask"`"; P03 states that the gateway applies it: `gateway_prompt_secrets()`, Task 9) and `gptr.verbose` (through P01's `verbosity()`: the `interpolated` echo at verbosity >= 2, Task 8).
- Replay (IC-45): `replay_mode(arg)` = "`arg` > `gptr.replay` > `GPTR_REPLAY` > settings > `"auto"`; `"replay"` is forced when `check_running()` and `Sys.getenv("TESTTHAT") != "true"` (examples), unless `arg` is given"; `replay_guard()` "in replay mode, signals `gptr_error_not_recorded` before any request to a provider whose record is not `offline = TRUE`".
- Egress (IC-29, 03 §6.10): `egress_check(provider_id)` is "`invisible(TRUE)` if acknowledged (user settings `egress`), local or offline, or `.opts$context = "none"`; when `gptr_can_prompt()`: shows what automatic context is sent and records the acknowledgement at user scope (an `ask_human`, IC-53); otherwise `gptr_error_egress`" (fields `provider`, `how_to_ack`); the recorded acknowledgement is announced with the message class `egress_ack`.
- Control category (IC-53 item 3): `gptr_config`, `gptr_trust`, `gptr_init`, `gptr_on`, and `gptr_steer`/`gptr_cancel` "on a session other than the running one" (the pipe into another running session included) check `run_current()`: "called from model code during a run they signal `gptr_error_permission` unless the dispatcher approved exactly that call through an `ask_human` (a one-shot token on the run)". The token is the function name appended to `run$signal$control`, the slot P06's `perm_grant_control()` and P11's gate grant (see contract ambiguities). P08's check is `control_check(what)`, the name P06 and P11 cite for it ("the slot P08's `control_check()` consumes"); P06 named its own session-level check `session_control_check(what, s = NULL)` and P11 its `perm_control_guard(what)` so that the three never collide.
- Internal names unique across plans: P06 reserved `mode_tighter()` and `control_check()` for P08 (its own helpers are `run_mode_tighter()` and `session_control_check()`); P07 owns `context_items()`, so P08's context-item builder is `gateway_context_items()`. Two top-level definitions of one name in one package silently override each other, so every P08 helper name was checked against every plan in `dev/plan/` (P01-P07, P09-P11, P14, P17, P21): none is defined twice.
- Human predicates (IC-43): every question uses `gptr_can_prompt()` and `gptr_confirm()`; `gptr()` with no prompt, nobody to prompt and `.stdin = FALSE` signals `gptr_error_noninteractive` (fields `what`, `questions`).
- Conditions used (04 §2.2): `gptr_error_invalid_argument` (`arg`, `expected`; never the argument's value), `gptr_error_invalid_identifier` (parent `invalid_argument`; `arg`, `class`), `gptr_error_noninteractive`, `gptr_error_not_available` (`member`, `provided_by`), `gptr_error_readonly` (`object`, `field`), `gptr_error_unknown_member`, `gptr_error_workspace` (`path`), `gptr_error_egress` (`provider`, `how_to_ack`), `gptr_error_not_recorded` (`document`, `prompt`), `gptr_error_permission` (`action`, `tool`, `risk`, `how_to_allow`, `session`), `gptr_error_provider` (`provider`, `model`, `status`, `request_id`, `error_type`, `session`), `gptr_error_budget_<kind>` (`kind`, `budget`, `used`, `session`), `gptr_error_max_turns` (`max_turns`, `session`), `gptr_error_missing_package` (`package`, `feature`), `gptr_error_internal` (`detail`); warning `gptr_warning_two_prompts`; messages `gptr_message_alias_shadowed`, `gptr_message_egress_ack`, `gptr_message_interpolated`, `gptr_message_notice`. Terminal statuses (04 §6.1.2): "`error` signals `gptr_error_provider`; `blocked` signals `gptr_error_permission`; `budget` signals `gptr_error_budget_<kind>`; `max_turns` signals `gptr_error_max_turns`. Each condition carries the session as `cnd$session`"; R's `interrupt` is re-signalled unchanged.
- Events emitted (04 §6.1.5, §10.4): `route` (`route`, `router`, `model`, `reason`), `model_select` (`from`, `to`, `reason`), `input` (transform chain; `text`, `source`), `project_trust` (first decision; `cwd`, `changed`). `session_start` is P06's; so are the per-switch `model_change`/`gptr.router` entries and `route` events of router sessions (P06 `run_route()` records what P08's `router.call` returns).
- Terminal conditions: P06 stores the unsignalled condition of a terminal status in `session_data(s)$condition` ("read by P08", P06 self-review item 7); `gateway_signal()` signals that object with `$session` set to the session, and builds one only when none is stored.
- Copy safety (03 §6.4 R1-R3, IC-41, G3 verification log): no rlang quosures; "a plain-symbol dot is read by name through a `get0()` leaf and its promise is never forced"; other dots "reach only leaf functions through `...elt(i)` in `while` loops"; "no closures, `tryCatch`, `withCallingHandlers` or `match.arg` in a frame that holds `...` or the home; never assign to a formal"; alias masks get `parent.env<-` `emptyenv()` after use; "never put a user frame in a list or closure that can become garbage; hold it only in environment bindings that are explicitly reset".
- Tests (conventions §7, 04 §12): the fake provider and P01's helpers with their exact names (`gptr_fake_provider()`, `local_fake_provider(script, name = "fake", type = "chat", .env = parent.frame())`, `fake_text()`, `fake_tool()`, `fake_requests(spec)`, `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_gptr_options(..., .env = parent.frame())`, `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)`); `setup.R` sets `GPTR_REPLAY=replay`, `gptr.interactive = FALSE`, `gptr.quiet = TRUE` and redirects every user directory.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/gptr-config.R` | create (Task 1), extend (Tasks 2-4, 7) | settings files, scopes and short locks; the core `setting` specs; the control-category check; trust store, fingerprints and `gptr_trust()`; settings layers, `settings_get()`, `settings_effective()`, `print.gptr_config()`; `gptr_config()`; `gptr_init()`; `replay_mode()`, `replay_guard()`, `egress_check()`; services `settings.get`, `trust.get` |
| `inst/templates/vignette.Rmd`, `inst/templates/settings.json`, `inst/templates/gitignore` | create (Task 7) | the files `gptr_init()` writes |
| `R/gptr-capture.R` | create (Task 5), extend (Task 6) | dot facts and call-site symbols (leaves), labels, prompt selection, interpolation, `.opts` and value-argument validation, the `gptr_call` record; identifier resolution, alias masks, agents; service `identifier.resolve` |
| `R/gptr-gateway.R` | create (Task 8), extend (Task 9) | the classed closure `gptr` and its methods; route dispatch, `route_pass()`, `gateway_defer()`, `home_address()`; `gateway_run()` with session creation and continuation, input building, `.run = FALSE` queuing and pending run options, pumping and terminal conditions; `builtin:gateway`; service `router.call` |
| `R/gptr-sdk.R` | create (Task 10) | `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()` |
| `tests/testthat/test-gptr-config.R` | create (Task 1), extend (Tasks 2-4, 7) | settings, trust, `gptr_config()`, `gptr_init()`, replay, egress |
| `tests/testthat/test-gptr-capture.R` | create (Task 5), extend (Task 6) | capture leaves, prompt selection, interpolation, call record, identifiers |
| `tests/testthat/test-gptr-gateway.R`, `tests/testthat/_snaps/gptr-gateway.md` | create (Task 8), extend (Task 9) | capture through the gateway, call shapes on the fake provider, routes, methods, visibility, terminal conditions, routers; the `print(gptr)` snapshot |
| `tests/testthat/test-gptr-sdk.R` | create (Task 10) | the six verbs, steering order, control checks |
| `tests/testthat/test-copy-gateway.R` | create (Task 11) | the fresh-process tracemem rows of G3 t5 and IC-41 |
| `NAMESPACE`, `man/gptr.Rd`, `man/gptr_init.Rd`, `man/gptr_config.Rd`, `man/gptr_trust.Rd`, `man/gptr_step.Rd`, `man/gptr_wait.Rd`, `man/gptr_steer.Rd`, `man/gptr_cancel.Rd`, `man/gptr_on.Rd`, `man/gptr_return.Rd` | generated (Task 12) | `Rscript --vanilla -e 'devtools::document()'` |

## Tasks (overview)

1. Settings files, scopes, locks, the core setting specs and the control check (`gptr-config.R`)
2. Project trust: `trust.json`, fingerprints, `gptr_trust()` and the `trust.get` service (`gptr-config.R`)
3. Settings layers: `settings_get()`, `settings_effective()` and the `settings.get` service (`gptr-config.R`)
4. Replay mode, the replay guard and the egress acknowledgement (`gptr-config.R`)
5. Capture leaves, prompt selection, interpolation, argument validation and the call record (`gptr-capture.R`)
6. Identifier resolution and the `identifier.resolve` service (`gptr-capture.R`)
7. `gptr_config()`, `gptr_init()` and the templates (`gptr-config.R`, `inst/templates/`)
8. The gateway closure, route dispatch and the `gptr_gateway` methods (`gptr-gateway.R`)
9. `gateway_run()`, terminal conditions, `builtin:gateway` and the `router.call` service (`gptr-gateway.R`)
10. The session SDK verbs (`gptr-sdk.R`)
11. The gateway copy suite (`test-copy-gateway.R`)
12. Documentation, NAMESPACE, plan acceptance and the M1 exit check

---
### Task 1: Settings files, scopes, locks, the core setting specs and the control check

**Files:**
- Create: `R/gptr-config.R`
- Test: `tests/testthat/test-gptr-config.R` (create)

**Interfaces:**
- Consumes (P01, 04 §7.1): `gptr_user_dir(which, create = FALSE)`, `workspace_dir(path = getwd())`, `project_root(path = getwd())`, `path_key(path)`, `hash_sha256(x)`, `write_atomic(path, content)`, `read_utf8(path)`, `json_encode(x, pretty = FALSE)`, `json_decode(text)`, `json_obj()`, the checkers of 04 §1.1, `gptr_abort()`. (P02, 04 §7.2): `gptr_spec(kind, name, ...)`, `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)`, `registry_diagnostic(source, event, class, message)`. (P04, 04 §7.4): `pid_alive(pid, create_time = NULL)`. (P06, IC-33): `run_current()` and the `gptr_run` fields `session` and `signal`.
- Produces (04 §7.8): `settings_write(scope, patch)` (scopes `"session"`, `"project"`, `"user"` and `"user_project"`, the user-level project file of IC-52 that P11's `gptr_permissions(scope = "project")` writes), plus the helpers later P08 tasks and P11/P15 read: `settings_read(scope)`, `settings_path(scope, create = FALSE)`, `settings_spec(key)`, `settings_keys()`, `gateway_setting_specs()` (the core `setting` specs of IC-24, registered in Task 9), `file_lock(path)`/`file_unlock(lock)` (IC-71) and `control_check(what)` (IC-53; the name P06 and P11 cite; P06's own check is `session_control_check()`).

The settings files are plain JSON objects; unknown keys survive a rewrite, a `NULL` in a patch removes the key,
arrays of names stay arrays at length 1 (`I()`), and every read-modify-write takes the short `mkdir` lock of IC-71.
The process layer is `the$settings_session` (04 §7.0). `control_check()` is the IC-53 check shared by
`gptr_config()`, `gptr_trust()`, `gptr_init()`, `gptr_on()` and the SDK verbs: inside a run (`run_current()`
non-`NULL`) it refuses unless the dispatcher left a one-shot approval token (the function name) in
`run$signal$control`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-gptr-config.R` with the shared helpers and the first tests:

```r
# tests/testthat/test-gptr-config.R (Task 1: create)
# test-gptr-config.R -- settings files, scopes and layers, trust, gptr_config(), gptr_init(),
# replay and egress (plan P08).

# A temporary project (P01's local_project(): the working directory and the project root, with
# or without .gptr/) and a private user config directory; the process settings layer is restored
# when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A stand-in for the run that run_current() returns while model code runs.
fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

test_that("settings_write() and settings_read() round-trip every scope", {
  proj = local_gw()
  settings_write("session", list(mode = "plan"))
  expect_identical(settings_read("session")$mode, "plan")
  settings_write("session", list(mode = NULL))
  expect_null(settings_read("session")$mode)
  settings_write("user", list(preset = "minimal", plugins = "demo"))
  expect_identical(settings_read("user")$preset, "minimal")
  expect_identical(settings_read("user")$plugins, "demo")
  txt = paste(readLines(settings_path("user"), encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "\"plugins\": [", fixed = TRUE)
  settings_write("project", list(mode = "manual"))
  expect_identical(settings_read("project")$mode, "manual")
  settings_write("user_project", list(permissions = list(allow = "r(level<=1)")))
  up = settings_read("user_project")
  expect_identical(up$root, proj)
  expect_identical(up$permissions$allow, "r(level<=1)")
  expect_match(settings_path("user_project"), "projects/[0-9a-f]{16}[.]json$")
})

test_that("settings files keep unknown keys and a NULL removes a key", {
  local_gw()
  settings_write("user", list(zzz_plugin_key = list(a = 1L), preset = "minimal"))
  settings_write("user", list(preset = NULL))
  u = settings_read("user")
  expect_identical(u$zzz_plugin_key$a, 1L)
  expect_false("preset" %in% names(u))
})

test_that("the project scope needs a workspace", {
  local_gw(workspace = FALSE)
  expect_error(settings_write("project", list(mode = "plan")), class = "gptr_error_workspace")
  expect_error(settings_read("project"), class = "gptr_error_workspace")
})

test_that("file locks are released, and a lock of a dead process is broken (IC-71)", {
  local_gw()
  p = settings_path("user", create = TRUE)
  lock = file_lock(p)
  expect_true(dir.exists(lock))
  file_unlock(lock)
  expect_false(dir.exists(lock))
  dir.create(paste0(p, ".lock"))
  writeLines("999999999 1", file.path(paste0(p, ".lock"), "pid"))
  settings_write("user", list(preset = "minimal"))
  expect_false(dir.exists(paste0(p, ".lock")))
  expect_identical(settings_read("user")$preset, "minimal")
})

test_that("control_check() refuses model-code calls; an approval is one-shot (IC-53)", {
  local_gw()
  expect_invisible(control_check("gptr_config"))
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(control_check("gptr_config"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_config")
  run$signal$control = "gptr_config"
  expect_invisible(control_check("gptr_config"))
  expect_error(control_check("gptr_config"), class = "gptr_error_permission")
})

test_that("the core setting specs cover contract 11.2 and validate their values (IC-24)", {
  specs = gateway_setting_specs()
  names = vapply(specs, function(s) s$name, "")
  expect_setequal(names, c(
    "version", "model", "small_model", "system1", "mode", "preset", "tools", "permissions",
    "context", "record", "replay", "transcript", "plugins", "filters", "skills", "mcp",
    "subagents", "output_tokens", "plot", "budget", "cache", "compactor", "compact_at",
    "checkpoint", "doc", "cache_commit", "ui", "frontend", "store", "evaluator", "providers",
    "egress"))
  expect_true(all(vapply(specs, inherits, NA, what = "gptr_setting")))
  by_name = stats::setNames(specs, names)
  expect_identical(by_name$mode$validate("plan"), "plan")
  expect_identical(by_name$mode$tighten, c("plan", "manual", "edits", "auto"))
  expect_error(by_name$mode$validate("fast"), class = "gptr_error_invalid_argument")
  expect_error(by_name$budget$validate(3), class = "gptr_error_invalid_argument")
  expect_identical(by_name$plugins$validate(c("a", "b")), c("a", "b"))
  expect_identical(by_name$egress$scope, "user")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: the run stops with errors such as `could not find function "settings_write"` (`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`), because `R/gptr-config.R` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `R/gptr-config.R`:

```r
# R/gptr-config.R (Task 1: create)
# gptr-config.R -- settings files and layers, gptr_config(), gptr_init(), gptr_trust(), the egress
# acknowledgement, replay_mode() and replay_guard() (plan P08; contract sections 6.2, 7.8,
# 11.1-11.3, 11.8, 11.16; IC-45, IC-52, IC-53, IC-71). Layer L6: it calls L0-L3 functions, the
# kernel SDK and services only.

# ------------------------------------------------------------------ P08 state in `the`

#' P08's process state (`the$gateway`, see the plan's contract ambiguities): parsed settings
#' files, trust decisions taken in this process (with the fingerprint they were taken for),
#' trust fingerprints, the gateway_defer() depth, the pending run options of sessions built with
#' `.run = FALSE`, the call records held for them and the ids of the rank-0 records each session's
#' calls registered (all three keyed by session id; released by builtin:gateway's agent_end and
#' session_shutdown hooks, Task 9)
#' @noRd
gateway_state = function() {
  st = the$gateway
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$files = new.env(parent = emptyenv())
    st$trust = new.env(parent = emptyenv())
    st$fingerprints = new.env(parent = emptyenv())
    st$pending = new.env(parent = emptyenv())
    st$held = new.env(parent = emptyenv())
    st$specs = new.env(parent = emptyenv())
    st$defer = 0L
    the$gateway = st
  }
  st
}

# ------------------------------------------------------------------ core settings (contract 11.2)

#' The core settings of contract section 11.2 as plain records
#' @noRd
settings_core = function() {
  modes = c("plan", "manual", "edits", "auto")
  rec = function(name, default, type, description, choices = NULL, tighten = NULL,
                 scope = "both") {
    list(name = name, default = default, type = type, description = description,
         choices = choices, tighten = tighten, scope = scope)
  }
  list(
    rec("version", 1L, "int", "Settings file format version."),
    rec("model", NULL, "ident", "Default model reference (null: the first available route)."),
    rec("small_model", NULL, "ident", "Small model (null: the small sibling of model)."),
    rec("system1", NULL, "ident", "System 1 model (null: typesafe/jev-latest when a key exists)."),
    rec("mode", "manual", "choice", "Permission mode.", choices = modes, tighten = modes),
    rec("preset", "standard", "chr", "Tool and prompt preset."),
    rec("tools", json_obj(), "object", "Tool enable and disable lists and per-model presets."),
    rec("permissions", json_obj(), "object", "Permission rules: allow, ask, deny."),
    rec("context", "summary", "choice", "Automatic context sent with prompts.",
        choices = c("none", "names", "summary"), tighten = c("none", "names", "summary")),
    rec("record", "ask", "choice", "May gptr write recorded blocks into documents.",
        choices = c("off", "ask", "auto"), tighten = c("off", "ask", "auto")),
    rec("replay", "auto", "choice", "Document replay mode.",
        choices = c("auto", "replay", "live", "record")),
    rec("transcript", "ask", "choice", "Console transcript target.",
        choices = c("ask", "file", "active-document", "off")),
    rec("plugins", character(), "chrs", "Plugins enabled for every session."),
    rec("filters", character(), "chrs", "Registry filters such as -builtin:mcp."),
    rec("skills", list(budget = 1500L), "object", "Skill paths and catalog budget."),
    rec("mcp", list(exposure = "r", budget = 1500L,
                    import = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi")),
        "object", "MCP exposure, catalog budget and imported configurations."),
    rec("subagents", list(max_depth = 1L, max_active = 8L, max_workers = NULL, max_cli = 4L,
                          max_tasks = 8L), "object", "Sub-agent limits."),
    rec("output_tokens", NULL, "int_or_null", "Maximum output tokens per request."),
    rec("plot", list(width = 768L, height = 512L, res = 120L), "object",
        "Size of plots sent to the model."),
    rec("budget", list(tokens = 2000000, cost = 5, turns = NULL), "object",
        "Budget per top-level call; null disables a limit."),
    rec("cache", list(ttl = "gap"), "object", "Prompt-cache tail TTL policy."),
    rec("compactor", "checkpoint", "chr", "Compactor used at the threshold."),
    rec("compact_at", 200000, "num_or_null", "Compaction soft cap in tokens."),
    rec("checkpoint", "on", "choice", "Checkpoints for undo.", choices = c("on", "files", "off")),
    rec("doc", list(outputs = TRUE, output_lines = 12L), "object", "Recorded output lines."),
    rec("cache_commit", list(s1 = TRUE, s2 = FALSE), "object", "Which caches are committed."),
    rec("ui", NULL, "chr_or_null", "UI backend name."),
    rec("frontend", NULL, "chr_or_null", "Console front end name."),
    rec("store", "jsonl", "chr", "Session store."),
    rec("evaluator", "r", "chr", "R evaluator."),
    rec("providers", json_obj(), "object", "Provider overrides: base_url, models, headers."),
    rec("egress", json_obj(), "object", "Providers acknowledged for automatic context.",
        scope = "user"))
}

#' A validator for one core setting (the `validate` field of its `setting` spec)
#' @noRd
setting_validator = function(name, type, choices = NULL) {
  force(name)
  force(type)
  force(choices)
  function(value) {
    switch(type,
      int = as.integer(check_number(value, name, min = 0, int = TRUE)),
      int_or_null = if (is.null(value)) NULL else
        as.integer(check_number(value, name, min = 0, int = TRUE)),
      num_or_null = if (is.null(value)) NULL else check_number(value, name, min = 0),
      chr = check_string(value, name),
      chr_or_null = check_string(value, name, null = TRUE),
      ident = check_string(value, name, null = TRUE),
      choice = check_choice(value, choices, name),
      chrs = as.character(check_strings(value, name)),
      object = settings_check_object(value, name),
      value)
  }
}

#' Checks that a setting value is a JSON object (a named list, possibly empty)
#' @noRd
settings_check_object = function(value, name) {
  ok = is.list(value) && !is.object(value) &&
    (length(value) == 0L || (!is.null(names(value)) && all(nzchar(names(value)))))
  if (!ok) {
    gptr_abort(paste0("The setting `", name, "` takes a named list (a JSON object)."),
               "invalid_argument", arg = name, expected = "a named list")
  }
  value
}

#' The `setting` specs of the core keys, registered by builtin:gateway (IC-24)
#' @noRd
gateway_setting_specs = function() {
  lapply(settings_core(), function(x) {
    gptr_spec("setting", x$name, default = x$default, description = x$description,
              scope = x$scope, validate = setting_validator(x$name, x$type, x$choices),
              tighten = x$tighten)
  })
}

#' The spec of a setting: the registered record, else the core table entry, else NULL
#' @noRd
settings_spec = function(key) {
  sp = registry_get("setting", key)
  if (!is.null(sp)) return(sp)
  for (x in settings_core()) {
    if (identical(x$name, key)) {
      return(list(name = x$name, default = x$default, scope = x$scope, tighten = x$tighten,
                  validate = setting_validator(x$name, x$type, x$choices)))
    }
  }
  NULL
}

#' Every known setting name (core keys plus registered `setting` specs)
#' @noRd
settings_keys = function() {
  core = vapply(settings_core(), function(x) x$name, "")
  unique(c(core, registry_names("setting")))
}

# ------------------------------------------------------------------ settings files

#' Path of a scope's settings file. `user_project` is the user-level project file of IC-52
#' (`R_user_dir("gptr", "config")/projects/<16 hex>.json`), which gptr_permissions(scope =
#' "project") writes (P11)
#' @noRd
settings_path = function(scope, create = FALSE) {
  switch(scope,
    user = file.path(gptr_user_dir("config", create = create), "settings.json"),
    project = {
      ws = workspace_dir()
      if (is.null(ws)) {
        gptr_abort(c("No gptr workspace (.gptr/) exists in this project.",
                     "Create one with gptr_init(path)."), "workspace", path = project_root())
      }
      file.path(ws, "settings.json")
    },
    user_project = file.path(gptr_user_dir("config", create = create), "projects",
                             paste0(project_hash(project_root()), ".json")),
    gptr_abort(paste0("Unknown settings scope `", scope, "`."), "invalid_argument",
               arg = "scope", expected = "session, project, user or user_project"))
}

#' First 16 hex of sha256 of the path key of a project root (IC-52)
#' @noRd
project_hash = function(root) substr(hash_sha256(path_key(root)), 1L, 16L)

#' Unnamed JSON arrays of scalars become atomic vectors; objects stay named lists
#' @noRd
json_simplify = function(x) {
  if (!is.list(x) || !length(x)) return(x)
  if (is.null(names(x))) {
    scalar = vapply(x, function(e) is.atomic(e) && length(e) == 1L, NA)
    if (all(scalar) && length(unique(vapply(x, typeof, ""))) == 1L) {
      return(unlist(x, use.names = FALSE))
    }
  }
  lapply(x, json_simplify)
}

#' Reads a JSON settings file through a cache keyed by path, mtime and size
#' @noRd
settings_file_read = function(path, fresh = FALSE) {
  if (!file.exists(path)) return(list())
  st = gateway_state()
  info = file.info(path, extra_cols = FALSE)
  stamp = paste(format(as.numeric(info$mtime), digits = 15), info$size)
  hit = if (isTRUE(fresh)) NULL else get0(path, envir = st$files, inherits = FALSE)
  if (!is.null(hit) && identical(hit$stamp, stamp)) return(hit$value)
  value = settings_parse(path)
  assign(path, list(stamp = stamp, value = value), envir = st$files)
  value
}

#' Parses one settings file; a malformed file is a diagnostic and reads as empty
#' @noRd
settings_parse = function(path) {
  txt = read_utf8(path)$text
  if (!nzchar(trimws(txt))) return(list())
  value = tryCatch(json_decode(txt), error = function(e) {
    registry_diagnostic("builtin:gateway", "settings", "parse_error",
                        paste0("could not parse ", path, ": ", conditionMessage(e)))
    list()
  })
  if (!is.list(value) || (length(value) && is.null(names(value)))) return(list())
  json_simplify(value)
}

#' Keeps array-valued settings arrays at length 1 when written
#' @noRd
settings_arrays = function(x) {
  for (k in intersect(c("plugins", "filters"), names(x))) {
    if (!is.null(x[[k]])) x[[k]] = I(as.character(unlist(x[[k]])))
  }
  nested = list(permissions = c("allow", "ask", "deny"), skills = "paths",
                tools = c("enable", "disable"), mcp = "import")
  for (k in intersect(names(nested), names(x))) {
    if (!is.list(x[[k]])) next
    for (f in intersect(nested[[k]], names(x[[k]]))) {
      if (!is.null(x[[k]][[f]])) x[[k]][[f]] = I(as.character(unlist(x[[k]][[f]])))
    }
  }
  x
}

#' Writes a settings file atomically (UTF-8, LF, final newline) and drops its cache entry
#' @noRd
settings_file_write = function(path, value) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  text = if (length(value)) json_encode(settings_arrays(value), pretty = TRUE) else "{}"
  write_atomic(path, text)
  st = gateway_state()
  if (exists(path, envir = st$files, inherits = FALSE)) rm(list = path, envir = st$files)
  invisible(path)
}

#' Merges a patch at top level; a NULL value removes the key
#' @noRd
settings_merge_top = function(cur, patch) {
  for (k in names(patch)) {
    if (is.null(patch[[k]])) cur[[k]] = NULL else cur[k] = list(patch[[k]])
  }
  cur
}

# ------------------------------------------------------------------ short file locks (IC-71)

#' Takes a short `mkdir` lock next to `path` (pid + creation time; 50 x 100 ms retries)
#' @noRd
file_lock = function(path) {
  lock = paste0(path, ".lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(50L)) {
    if (dir.create(lock, showWarnings = FALSE)) {
      write_atomic(file.path(lock, "pid"), lock_stamp())
      return(lock)
    }
    if (lock_stale(lock)) unlink(lock, recursive = TRUE) else Sys.sleep(0.1)
  }
  gptr_abort(paste0("The file ", path, " is locked by another R process; try again."),
             "timeout", seconds = 5, what = "lock")
}

#' Releases a lock taken by file_lock()
#' @noRd
file_unlock = function(lock) invisible(unlink(lock, recursive = TRUE))

#' "<pid> <process creation time>" of this process
#' @noRd
lock_stamp = function() {
  ct = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA_real_)
  paste(Sys.getpid(), format(ct, digits = 15))
}

#' A lock is stale when its owner is dead (pid and creation time, P04's pid_alive()) or it has
#' had no pid file for 30 s
#' @noRd
lock_stale = function(lock) {
  pf = file.path(lock, "pid")
  if (!file.exists(pf)) {
    age = as.numeric(difftime(Sys.time(), file.info(lock)$mtime, units = "secs"))
    return(is.na(age) || age > 30)
  }
  parts = strsplit(trimws(read_utf8(pf)$text), " ", fixed = TRUE)[[1L]]
  pid = suppressWarnings(as.integer(parts[1L]))
  ct = suppressWarnings(as.numeric(parts[2L]))
  if (is.na(pid)) return(TRUE)
  !isTRUE(tryCatch(pid_alive(pid, create_time = if (is.na(ct)) NULL else ct),
                   error = function(e) FALSE))
}

# ------------------------------------------------------------------ settings I/O (contract 7.8)

#' The named list stored in one scope: `session` (this R process, `the$settings_session`),
#' `project` (.gptr/settings.json), `user`, `user_project` (IC-52). Read by P11 and P15.
#' @noRd
settings_read = function(scope) {
  scope = check_choice(scope, c("session", "project", "user", "user_project"), "scope")
  if (identical(scope, "session")) return(the$settings_session %||% list())
  settings_file_read(settings_path(scope, create = FALSE))
}

#' Merges `patch` at top level into a scope: an atomic file write under a short lock, or the
#' process layer; NULL values remove keys (contract 7.8)
#' @noRd
settings_write = function(scope, patch) {
  scope = check_choice(scope, c("session", "project", "user", "user_project"), "scope")
  check_list(patch, "patch", named = TRUE)
  if (identical(scope, "session")) {
    cur = settings_merge_top(the$settings_session %||% list(), patch)
    the$settings_session = cur
    return(invisible(cur))
  }
  path = settings_path(scope, create = TRUE)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  cur = settings_merge_top(settings_file_read(path, fresh = TRUE), patch)
  if (identical(scope, "user_project")) {
    cur$version = cur$version %||% 1L
    cur$root = cur$root %||% project_root()
  }
  settings_file_write(path, cur)
  invisible(cur)
}

# ------------------------------------------------------------------ control-category check (IC-53)

#' Refuses a configuration change made from model code during a run, unless the dispatcher
#' approved exactly this call through an ask_human: a one-shot token, the function name appended
#' to `run$signal$control` by P06's perm_grant_control() (P11's gate), consumed here. P06's
#' session_control_check() (gptr_fork(), gptr_resume()) and P11's perm_control_guard() read the
#' same slot.
#' @noRd
control_check = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  sig = run$signal
  ok = if (is.environment(sig)) sig$control %||% character() else character()
  i = match(what, ok)
  if (!is.na(i)) {
    sig$control = ok[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0(what, "() changes gptr's configuration and was called from model code ",
                      "during a run."),
               "Only you can make this change: run it outside the run, or approve it when asked."),
             "permission", action = what, tool = "r", risk = 4L,
             how_to_allow = "call it yourself outside gptr(), or approve the r call when asked",
             session = run$session)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 30 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-config.R tests/testthat/test-gptr-config.R
git commit -m "feat(gateway): add settings files, scopes, locks and the control check"
```

---

### Task 2: Project trust: `trust.json`, fingerprints, `gptr_trust()` and the `trust.get` service

**Files:**
- Modify: `R/gptr-config.R` (append the trust functions; replace `settings_write()`)
- Test: `tests/testthat/test-gptr-config.R` (append)

**Interfaces:**
- Consumes: Task 1 (`settings_file_read()`, `settings_file_write()`, `file_lock()`, `control_check()`, `gateway_state()`); P01 `path_rel(path, root)`, `gptr_can_prompt()`, `gptr_confirm(question, default = FALSE)`, `gptr_inform()`, `ev_new(type, ...)`, `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`; P02 `ev_dispatch(event, payload, session = NULL, ctx = NULL)` (event `project_trust`, first decision, 04 §10.4).
- Produces: the export `gptr_trust(path = ".", trust = NULL)` (04 §6.2); `trust_get(path = getwd())` (04 §7.8: "`TRUE` only when recorded and the trust fingerprint still matches (IC-52)") registered as the service `trust.get` (IC-33, fallback `FALSE` for its consumers P03, P07, P15, P17, P18); `trust_resolve(root)` (the first decision used by Task 9 and P17/P18 through `trust.get`), `trust_store(root, trusted)`, `trust_mark(root, decision)`, `trust_holds(root)`, `trust_fingerprint(root)` and `trust_resources_present(root)`.

`trust.json` follows 04 §11.8. The fingerprint (IC-52) is sha256 over the sorted root-relative paths and the
content hashes of the trust-gated files, cached by path, mtime and size; the per-file hashes are stored as well, so
that a later mismatch can list which files changed. gptr's own writes to a trusted project re-fingerprint it (the
replaced `settings_write()`). `trust_resolve()` decides once per process and fingerprint: the recorded decision,
else the first decision of `project_trust` handlers, else the interactive question, else "untrusted" with one
notice. A decision taken in this process is remembered with the fingerprint it was taken for (`trust_mark()`), so
a gated file changed later in the process (for example by model code) voids it, as IC-52 requires ("Control
files modified during the process are not loaded again without confirmation").

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-config.R`:

```r
# tests/testthat/test-gptr-config.R (Task 2: append)

test_that("gptr_trust() records a decision with a fingerprint (IC-52)", {
  proj = local_gw()
  expect_identical(gptr_trust(proj), NA)
  expect_false(trust_get(proj))
  expect_identical(gptr_trust(proj, TRUE), NA)
  expect_true(gptr_trust(proj))
  expect_true(trust_get(proj))
  store = json_decode(paste(readLines(trust_file(), encoding = "UTF-8"), collapse = "\n"))
  rec = store$projects[[path_key(proj)]]
  expect_true(rec$trusted)
  expect_match(rec$fingerprint, "^[0-9a-f]{64}$")
})

test_that("a changed trust-gated file makes the project untrusted again", {
  proj = local_gw()
  writeLines('{"preset": "extended"}', file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_true(trust_get(proj))
  writeLines('{"preset": "extended", "mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  expect_false(trust_get(proj))
  expect_true(gptr_trust(proj))
})

test_that("gptr's own writes to a trusted project re-fingerprint it", {
  proj = local_gw()
  gptr_trust(proj, TRUE)
  settings_write("project", list(preset = "minimal"))
  expect_true(trust_get(proj))
})

# The bootstrap entry only: ext_service_get() serves it once builtin:gateway is loaded (Task 9
# tests that), because P01's service_builtin_active() hides a service of a built-in that the
# registry does not list yet.
test_that("trust_get() is registered as the trust.get service of builtin:gateway (IC-33)", {
  proj = local_gw()
  entry = the$services[["trust.get"]]
  expect_identical(entry[c("provided_by", "builtin")],
                   list(provided_by = "P08", builtin = "gateway"))
  gptr_trust(proj, TRUE)
  expect_true(entry$fun(proj))
})

test_that("a trust decision taken in this process lapses when a gated file changes (IC-52)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) list(decision = "yes")))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  expect_true(trust_get(proj))
  writeLines('{"mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  expect_false(trust_get(proj))
})

test_that("untrusted project resources are ignored non-interactively, with one notice", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(quiet = FALSE)
  expect_message(trust_resolve(proj), class = "gptr_message_notice")
  expect_false(trust_resolve(proj))
})

test_that("a project_trust handler decides first and can remember (IC-71)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) {
    list(decision = "yes", remember = TRUE)
  }))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  expect_true(gptr_trust(proj))
})

test_that("with a human the question lists the files changed since trust was given", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  writeLines('{"mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(interactive = TRUE)
  box = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    TRUE
  })
  expect_true(trust_resolve(proj))
  expect_match(box$question, ".gptr/settings.json", fixed = TRUE)
  expect_true(trust_get(proj))
})

test_that("gptr_trust() is refused from model code during a run (IC-53)", {
  proj = local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_trust(proj, TRUE), class = "gptr_error_permission")
  expect_identical(gptr_trust(proj), NA)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: the new tests fail with `could not find function "gptr_trust"` and `could not find function "trust_get"`.

- [ ] **Step 3: Write the implementation**

Append to `R/gptr-config.R`:

```r
# R/gptr-config.R (Task 2: append)

# ------------------------------------------------------------- trust (contract 6.2, 11.8; IC-52)

#' Path of `trust.json` in the user config directory
#' @noRd
trust_file = function(create = FALSE) {
  file.path(gptr_user_dir("config", create = create), "trust.json")
}

#' The trust store: list(version, projects = named list keyed by path_key(root))
#' @noRd
trust_read = function(fresh = FALSE) {
  x = settings_file_read(trust_file(), fresh = fresh)
  if (!is.list(x$projects)) x$projects = list()
  x
}

#' The recorded trust entry of a project root, or NULL
#' @noRd
trust_record = function(root) trust_read()$projects[[path_key(root)]]

#' Existing trust-gated files of a project (IC-52): .gptr/settings.json, mcp.json, SYSTEM.md,
#' APPEND_SYSTEM.md, the files under extensions/, plugins/ and agents/, and an auto-discovered .env
#' @noRd
trust_gated_paths = function(root) {
  ws = file.path(root, ".gptr")
  files = c(file.path(ws, c("settings.json", "mcp.json", "SYSTEM.md", "APPEND_SYSTEM.md")),
            file.path(root, ".env"))
  found = files[file.exists(files) & !dir.exists(files)]
  for (d in file.path(ws, c("extensions", "plugins", "agents"))) {
    if (dir.exists(d)) {
      found = c(found, list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE))
    }
  }
  unique(found)
}

#' TRUE when the project holds anything the trust question is about (IC-52): trust-gated files,
#' AGENTS.md, CLAUDE.md, .gptr/skills/ or .gptr/agents/
#' @noRd
trust_resources_present = function(root) {
  length(trust_gated_paths(root)) > 0L ||
    any(file.exists(file.path(root, c("AGENTS.md", "CLAUDE.md")))) ||
    any(dir.exists(file.path(root, ".gptr", c("skills", "agents"))))
}

#' Trust fingerprint: sha256 over the sorted relative paths and content hashes of the gated files
#' (cached by path, mtime and size). Returns list(fp = chr(1), files = named chr of file hashes).
#' @noRd
trust_fingerprint = function(root) {
  paths = trust_gated_paths(root)
  info = file.info(paths, extra_cols = FALSE)
  stamp = paste(paths, format(as.numeric(info$mtime), digits = 15), info$size, collapse = "|")
  st = gateway_state()
  key = path_key(root)
  hit = get0(key, envir = st$fingerprints, inherits = FALSE)
  if (!is.null(hit) && identical(hit$stamp, stamp)) return(hit$value)
  rel = path_rel(paths, root = root)
  hashes = vapply(paths, function(p) hash_sha256(readBin(p, "raw", n = max(1, file.size(p)))), "")
  names(hashes) = rel
  hashes = hashes[order(rel, method = "radix")]
  fp = hash_sha256(paste(names(hashes), hashes, sep = " ", collapse = "\n"))
  value = list(fp = fp, files = hashes)
  assign(key, list(stamp = stamp, value = value), envir = st$fingerprints)
  value
}

#' Records a trust decision with the current fingerprint (atomic, under a short lock). The
#' per-file hashes are kept too, so a later mismatch can list the changed files.
#' @noRd
trust_store = function(root, trusted) {
  path = trust_file(create = TRUE)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  x = trust_read(fresh = TRUE)
  key = path_key(root)
  fp = trust_fingerprint(root)
  rec = x$projects[[key]] %||% list()
  rec$trusted = isTRUE(trusted)
  rec$date = format(Sys.Date())
  rec$fingerprint = fp$fp
  rec$files = as.list(fp$files)
  x$version = x$version %||% 1L
  x$projects[[key]] = rec
  settings_file_write(path, x)
  st = gateway_state()
  if (exists(key, envir = st$trust, inherits = FALSE)) rm(list = key, envir = st$trust)
  invisible(rec)
}

#' Remembers a trust decision taken in this process (a `project_trust` handler or the interactive
#' question) together with the fingerprint it was taken for: it holds only while the gated files
#' are unchanged (IC-52: "Control files modified during the process are not loaded again without
#' confirmation")
#' @noRd
trust_mark = function(root, decision) {
  assign(path_key(root), list(decision = isTRUE(decision), fp = trust_fingerprint(root)$fp),
         envir = gateway_state()$trust)
  invisible(decision)
}

#' Which trust holds for a project root now: `record` (trust.json says trusted and the
#' fingerprint matches) and `live` (a decision of this process whose fingerprint matches)
#' @noRd
trust_holds = function(root) {
  key = path_key(root)
  hit = get0(key, envir = gateway_state()$trust, inherits = FALSE)
  rec = trust_record(root)
  live = is.list(hit) && isTRUE(hit$decision)
  recorded = !is.null(rec) && isTRUE(rec$trusted)
  if (!live && !recorded) return(list(record = FALSE, live = FALSE))
  fp = trust_fingerprint(root)$fp
  list(record = recorded && identical(rec$fingerprint, fp), live = live && identical(hit$fp, fp))
}

#' TRUE only when the project is recorded as trusted, or a `project_trust` handler or the user
#' accepted it in this process, and the trust fingerprint still matches (the `trust.get`
#' service; IC-33, IC-52)
#' @noRd
trust_get = function(path = getwd()) {
  h = trust_holds(project_root(path))
  h$record || h$live
}

#' Decides trust for a project once per process and fingerprint: the recorded decision, else the
#' first decision of `project_trust` handlers, else the interactive question, else untrusted with
#' one notice. A changed gated file voids an earlier in-process decision (IC-52).
#' @noRd
trust_resolve = function(root) {
  if (isTRUE(trust_get(root))) return(TRUE)
  key = path_key(root)
  st = gateway_state()
  fp = trust_fingerprint(root)
  done = get0(key, envir = st$trust, inherits = FALSE)
  if (is.list(done) && identical(done$fp, fp$fp)) return(isTRUE(done$decision))
  if (!trust_resources_present(root)) return(FALSE)
  rec = trust_record(root)
  if (!is.null(rec) && !isTRUE(rec$trusted)) {
    trust_mark(root, FALSE)
    return(FALSE)
  }
  old = unlist(rec$files) %||% character()
  now = fp$files
  changed = names(now)[is.na(old[names(now)]) | old[names(now)] != now]
  changed = sort(unique(c(changed, setdiff(names(old), names(now)))), method = "radix")
  res = ev_dispatch("project_trust", ev_new("project_trust", cwd = root, changed = changed))
  if (is.list(res) && is.character(res$decision)) {
    decision = identical(res$decision, "yes")
    if (isTRUE(res$remember)) trust_store(root, decision)
  } else if (gptr_can_prompt()) {
    what = if (length(changed)) {
      paste0(" Changed since you last trusted it: ", paste(changed, collapse = ", "), ".")
    } else {
      ""
    }
    decision = isTRUE(gptr_confirm(paste0("Trust this project (its settings, extensions and MCP ",
                                          "servers)?", what)))
    trust_store(root, decision)
  } else {
    gptr_inform(paste0("Project resources in ", root, " were not loaded because the project is ",
                       "not trusted. Use gptr_trust() to trust it."), "notice",
                .once = paste0("trust:", key))
    decision = FALSE
  }
  trust_mark(root, decision)
  decision
}

#' Record or read whether a project is trusted
#'
#' Trust decides whether gptr applies or runs what a project directory contains: project
#' settings beyond tightening, `.gptr/extensions/` and project plugins, project MCP servers,
#' `SYSTEM.md` and `APPEND_SYSTEM.md`, project `.env` discovery, provider base-URL overrides, the
#' tool and model fields of project agent files, and the authority of project instructions. The
#' decision is kept in `tools::R_user_dir("gptr", "config")/trust.json` with a fingerprint of the
#' trust-gated files; when they change, the project counts as untrusted again until you confirm.
#' Called from model code during a run, recording a decision is refused.
#'
#' @param path A directory inside the project; its project root is used.
#' @param trust `NULL` to read the decision, `TRUE` or `FALSE` to record one.
#' @return With `trust = NULL`, the recorded decision: `TRUE`, `FALSE` or `NA` (undecided).
#'   Otherwise the previous decision, invisibly.
#' @examples
#' d = tempfile("proj")
#' dir.create(d)
#' gptr_trust(d)
#' unlink(d, recursive = TRUE)
#' @export
gptr_trust = function(path = ".", trust = NULL) {
  check_string(path, "path")
  check_flag(trust, "trust", null = TRUE)
  root = project_root(path)
  rec = trust_record(root)
  prev = if (is.null(rec)) NA else isTRUE(rec$trusted)
  if (is.null(trust)) return(prev)
  control_check("gptr_trust")
  trust_store(root, trust)
  invisible(prev)
}

on_load(ext_service_set("trust.get", trust_get, provided_by = "P08", builtin = "gateway"))
```

In `R/gptr-config.R`, replace the Task 1 definition of `settings_write()` (and its roxygen block) with this version, which re-fingerprints a trusted project after gptr's own write:

```r
# R/gptr-config.R (Task 2: replace settings_write())
#' Merges `patch` at top level into a scope: an atomic file write under a short lock, or the
#' process layer; NULL values remove keys (contract 7.8). A write to the settings of a trusted
#' project keeps the trust that held before it: a recorded trust gets the new fingerprint in
#' trust.json, a decision of this process gets it in memory (gptr's own writes re-fingerprint,
#' IC-52; an in-process decision is never turned into a recorded one).
#' @noRd
settings_write = function(scope, patch) {
  scope = check_choice(scope, c("session", "project", "user", "user_project"), "scope")
  check_list(patch, "patch", named = TRUE)
  if (identical(scope, "session")) {
    cur = settings_merge_top(the$settings_session %||% list(), patch)
    the$settings_session = cur
    return(invisible(cur))
  }
  path = settings_path(scope, create = TRUE)
  root = project_root()
  was = if (identical(scope, "project")) trust_holds(root) else list(record = FALSE, live = FALSE)
  lock = file_lock(path)
  on.exit(file_unlock(lock), add = TRUE)
  cur = settings_merge_top(settings_file_read(path, fresh = TRUE), patch)
  if (identical(scope, "user_project")) {
    cur$version = cur$version %||% 1L
    cur$root = cur$root %||% root
  }
  settings_file_write(path, cur)
  if (isTRUE(was$record)) trust_store(root, TRUE)
  if (isTRUE(was$live)) trust_mark(root, TRUE)
  invisible(cur)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 55 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-config.R tests/testthat/test-gptr-config.R
git commit -m "feat(gateway): add project trust, fingerprints and gptr_trust()"
```

---

### Task 3: Settings layers: `settings_get()`, `settings_effective()` and the `settings.get` service

**Files:**
- Modify: `R/gptr-config.R` (append)
- Test: `tests/testthat/test-gptr-config.R` (append)

**Interfaces:**
- Consumes: Tasks 1-2 (`settings_read()`, `settings_path()`, `settings_spec()`, `settings_keys()`, `settings_file_read()`, `trust_get()`); P01 `setting_get(key, session = NULL, default = NULL)` (which calls the `settings.get` service once it is registered), `gptr_inform()`.
- Produces (04 §7.8): `settings_get(key, session = NULL)` ("the effective value through the layers of §11.2"), registered as the service `settings.get` (`function(key, session = NULL) value`, consumed by every plan through P01's `setting_get()`); `settings_effective()` returning the `gptr_config` class of 04 §5.11 with its `print` method; the helper `settings_resolve(key)` -> `list(value, source)`.

Layers, lowest first (04 §11.2): defaults < user file < project file (IC-52: untrusted projects only tighten
`tighten`-type keys and add `permissions.deny`/`ask`; trusted projects add every key but still only tighten
`tighten`-type keys; a trusted project's legacy `.gptr/settings.local.json` adds deny/ask rules only) < the
user-level project file (permission rules) < `options(gptr.<key>)` < the session layer. `egress` is read from the
user file only. Objects merge key by key (`utils::modifyList()`); a dotted key such as `subagents.max_depth`
resolves inside its object, and its own option (`gptr.subagents.max_depth`, 04 §3.1) and session entry win.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-config.R`:

```r
# tests/testthat/test-gptr-config.R (Task 3: append)


test_that("settings_get() layers defaults, user file, options and the session", {
  local_gw()
  expect_identical(settings_get("mode"), "manual")
  settings_write("user", list(preset = "readonly"))
  expect_identical(settings_get("preset"), "readonly")
  withr::local_options(gptr.preset = "minimal")
  expect_identical(settings_get("preset"), "minimal")
  settings_write("session", list(preset = "extended"))
  expect_identical(settings_get("preset"), "extended")
})

test_that("an untrusted project only tightens (IC-52)", {
  proj = local_gw()
  writeLines(paste0('{"mode": "auto", "preset": "extended", "context": "names", ',
                    '"permissions": {"allow": ["write(**)"], "deny": ["r(fn:unlink)"]}}'),
             file.path(proj, ".gptr", "settings.json"))
  expect_identical(settings_get("mode"), "manual")
  expect_identical(settings_get("preset"), "standard")
  expect_identical(settings_get("context"), "names")
  p = settings_get("permissions")
  expect_identical(p$deny, "r(fn:unlink)")
  expect_null(p$allow)
})

test_that("a trusted project applies every key, but tighten-type keys only tighten", {
  proj = local_gw()
  writeLines('{"mode": "auto", "preset": "extended", "permissions": {"allow": ["write(**)"]}}',
             file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_identical(settings_get("preset"), "extended")
  expect_identical(settings_get("mode"), "manual")
  expect_identical(settings_get("permissions")$allow, "write(**)")
})

test_that("the user-level project file adds rules; egress comes from the user file only", {
  proj = local_gw()
  settings_write("user_project", list(permissions = list(allow = "r(level<=1)")))
  expect_identical(settings_get("permissions")$allow, "r(level<=1)")
  writeLines('{"egress": {"corp": "ack"}}', file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_null(settings_get("egress")$corp)
  settings_write("user", list(egress = list(corp = "ack")))
  expect_identical(settings_get("egress")$corp, "ack")
})

test_that("dotted keys read nested objects and their own options", {
  local_gw()
  expect_identical(settings_get("subagents.max_depth"), 1L)
  withr::local_options(gptr.subagents.max_depth = 2L)
  expect_identical(settings_get("subagents.max_depth"), 2L)
  expect_identical(setting_get("subagents.max_depth"), 2L)
})

test_that("settings_effective() reports each key with its layer and prints it", {
  proj = local_gw()
  writeLines('{"mode": "plan"}', file.path(proj, ".gptr", "settings.json"))
  cfg = settings_effective()
  expect_s3_class(cfg, "gptr_config")
  expect_identical(cfg$mode, "plan")
  expect_identical(unname(attr(cfg, "sources")["mode"]), "project")
  expect_output(print(cfg), "mode +plan +\\[project\\]")
})

# The bootstrap entry only: P01's setting_get() uses it once builtin:gateway is loaded (Task 9
# tests setting_get() end to end).
test_that("settings_get() is registered as the settings.get service of builtin:gateway", {
  local_gw()
  entry = the$services[["settings.get"]]
  expect_identical(entry[c("provided_by", "builtin")],
                   list(provided_by = "P08", builtin = "gateway"))
  settings_write("session", list(preset = "minimal"))
  expect_identical(entry$fun("preset"), "minimal")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: the new tests fail with `could not find function "settings_get"` and `could not find function "settings_effective"`.

- [ ] **Step 3: Write the implementation**

Append to `R/gptr-config.R`:

```r
# R/gptr-config.R (Task 3: append)

# ------------------------------------------------------------------ settings layers (contract 11.2)

#' Looks a key up in one layer: a flat key first (plugin keys such as "panel.size"), else a dotted
#' path into nested objects ("subagents.max_depth")
#' @noRd
settings_lookup = function(layer, key) {
  if (!is.list(layer) || !length(layer)) return(list(found = FALSE, value = NULL))
  if (key %in% names(layer)) {
    v = layer[[key]]
    return(list(found = !is.null(v), value = v))
  }
  parts = strsplit(key, ".", fixed = TRUE)[[1L]]
  if (length(parts) < 2L) return(list(found = FALSE, value = NULL))
  v = settings_dig(layer, parts)
  list(found = !is.null(v), value = v)
}

#' Walks a dotted path into nested named lists; NULL when a step is missing
#' @noRd
settings_dig = function(x, parts) {
  for (p in parts) {
    if (!is.list(x) || !p %in% names(x)) return(NULL)
    x = x[[p]]
  }
  x
}

#' Combines a lower and a higher layer: objects merge recursively, anything else is replaced
#' @noRd
settings_combine = function(lower, higher) {
  if (is.list(lower) && !is.object(lower) && is.list(higher) && !is.object(higher) &&
      !is.null(names(higher))) {
    return(utils::modifyList(lower, higher))
  }
  higher
}

#' Union of permission rule lists (only the lists named in `lists` are taken from `add`)
#' @noRd
settings_perm_union = function(base, add, lists) {
  out = if (is.list(base)) base else list()
  if (!is.list(add)) return(out)
  for (k in lists) {
    extra = as.character(unlist(add[[k]]))
    if (length(extra)) out[[k]] = unique(c(as.character(unlist(out[[k]])), extra))
  }
  out
}

#' The value a project settings file contributes (IC-52): tighten-type keys only tighten;
#' permissions add deny and ask rules (allow too when trusted); other keys apply only in a trusted
#' project
#' @noRd
settings_project_value = function(key, spec, current, new, trusted) {
  if (identical(key, "permissions")) {
    lists = if (trusted) c("allow", "ask", "deny") else c("ask", "deny")
    return(settings_perm_union(current, new, lists))
  }
  tighten = spec$tighten
  if (!is.null(tighten)) {
    if (!is.character(new) || length(new) != 1L || !new %in% tighten) return(current)
    now = match(if (is.character(current)) current[1L] else tighten[length(tighten)], tighten)
    if (is.na(now) || match(new, tighten) <= now) return(new)
    return(current)
  }
  if (!trusted) return(current)
  settings_combine(current, new)
}

#' Normalises a resolved value to its spec's type (JSON arrays of names become character vectors)
#' @noRd
settings_normalise = function(spec, value) {
  if (is.character(spec$default) && is.list(value) && is.null(names(value))) {
    return(as.character(unlist(value)))
  }
  value
}

#' The legacy `.gptr/settings.local.json` of a trusted project: only its permissions.deny and
#' permissions.ask entries count; other keys are ignored with one notice (IC-52)
#' @noRd
settings_local_permissions = function(ws, value) {
  path = file.path(ws, "settings.local.json")
  local = settings_file_read(path)
  if (!length(local)) return(value)
  ignored = c(intersect(names(local), c("record", "transcript")),
              if (length(unlist(local$permissions$allow))) "permissions.allow")
  if (length(ignored)) {
    gptr_inform(paste0("Ignored in ", path, ": ", paste(ignored, collapse = ", "),
                       " (only deny and ask rules are read from this file)."), "notice",
                .once = paste0("settings.local:", path_key(path)))
  }
  settings_perm_union(value, local$permissions, c("ask", "deny"))
}

#' A top-level key through every layer, lowest to highest: defaults < user file < project file
#' (trust rules) < user-level project file (permissions) < options(gptr.<key>) < session layer.
#' `egress` is read from the user file only.
#' @noRd
settings_layered = function(key) {
  spec = settings_spec(key)
  value = spec$default
  source = "default"
  u = settings_lookup(settings_file_read(settings_path("user")), key)
  if (u$found) {
    value = settings_combine(value, u$value)
    source = "user"
  }
  if (identical(key, "egress")) return(list(value = value, source = source))
  ws = workspace_dir()
  if (!is.null(ws)) {
    trusted = isTRUE(trust_get(project_root()))
    p = settings_lookup(settings_file_read(file.path(ws, "settings.json")), key)
    if (p$found) {
      nv = settings_project_value(key, spec, value, p$value, trusted)
      if (!identical(nv, value)) {
        value = nv
        source = "project"
      }
    }
    if (identical(key, "permissions") && trusted) {
      nv = settings_local_permissions(ws, value)
      if (!identical(nv, value)) {
        value = nv
        source = "project"
      }
    }
  }
  if (identical(key, "permissions")) {
    up = settings_lookup(settings_file_read(settings_path("user_project")), key)
    if (up$found) {
      value = settings_perm_union(value, up$value, c("allow", "ask", "deny"))
      source = "user_project"
    }
  }
  opt = getOption(paste0("gptr.", key))
  if (!is.null(opt)) {
    value = settings_combine(value, opt)
    source = "option"
  }
  ses = settings_lookup(the$settings_session %||% list(), key)
  if (ses$found) {
    value = settings_combine(value, ses$value)
    source = "session"
  }
  list(value = settings_normalise(spec, value), source = source)
}

#' A key and the layer it came from. A dotted key that is not registered itself resolves inside
#' its top-level object, then the option and session layers of the dotted name.
#' @noRd
settings_resolve = function(key) {
  parts = strsplit(key, ".", fixed = TRUE)[[1L]]
  if (length(parts) == 1L || !is.null(settings_spec(key)) || is.null(settings_spec(parts[1L]))) {
    return(settings_layered(key))
  }
  base = settings_layered(parts[1L])
  value = settings_dig(base$value, parts[-1L])
  source = base$source
  opt = getOption(paste0("gptr.", key))
  if (!is.null(opt)) {
    value = opt
    source = "option"
  }
  ses = settings_lookup(the$settings_session %||% list(), key)
  if (ses$found) {
    value = ses$value
    source = "session"
  }
  list(value = value, source = source)
}

#' The effective value of a setting through the layers of contract 11.2: the `settings.get`
#' service behind P01's setting_get(). `session` is accepted for the service signature; settings
#' are process-wide in 1.0.
#' @noRd
settings_get = function(key, session = NULL) {
  check_string(key, "key")
  settings_resolve(key)$value
}

#' The effective settings with the layer of each key (class `gptr_config`, contract 5.11)
#' @noRd
settings_effective = function() {
  keys = settings_keys()
  values = vector("list", length(keys))
  sources = character(length(keys))
  for (i in seq_along(keys)) {
    r = settings_resolve(keys[i])
    if (!is.null(r$value)) values[[i]] = r$value
    sources[i] = r$source
  }
  names(values) = keys
  names(sources) = keys
  structure(values, sources = sources, class = "gptr_config")
}

#' One-line rendering of a setting value
#' @noRd
settings_format_value = function(v) {
  if (is.null(v)) return("null")
  if (is.atomic(v) && length(v) == 1L) return(as.character(v))
  txt = json_encode(v)
  if (nchar(txt) > 60L) paste0(substr(txt, 1L, 57L), "...") else txt
}

#' @export
print.gptr_config = function(x, ...) {
  src = attr(x, "sources")
  keys = names(x)
  width = max(c(nchar(keys), 1L))
  lines = character(length(keys))
  for (i in seq_along(keys)) {
    layer = unname(src[keys[i]])
    if (is.na(layer)) layer = "default"
    lines[i] = paste0(formatC(keys[i], width = -width), "  ", settings_format_value(x[[i]]),
                      "  [", layer, "]")
  }
  cat(lines, sep = "\n")
  invisible(x)
}

on_load(ext_service_set("settings.get", settings_get, provided_by = "P08", builtin = "gateway"))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 79 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-config.R tests/testthat/test-gptr-config.R
git commit -m "feat(gateway): add the settings layers and the settings.get service"
```

---

### Task 4: Replay mode, the replay guard and the egress acknowledgement

**Files:**
- Modify: `R/gptr-config.R` (append)
- Test: `tests/testthat/test-gptr-config.R` (append)

**Interfaces:**
- Consumes: Tasks 1-3 (`settings_get()`, `settings_write()`, `settings_path()`, `settings_file_read()`); P01 `check_running()`, `gptr_can_prompt()`, `gptr_confirm()`, `gptr_inform()`; P05 `provider_get(id)`, `model_resolve(ref, strict = TRUE)`.
- Produces (04 §7.8, kernel SDK of IC-33): `replay_mode(arg = NULL)` -> `chr(1)` (consumers P13, P15, P19), `replay_guard(model, what = "model call")` -> `invisible(TRUE)` or `gptr_error_not_recorded` (consumers P13, P19; `model` is a model record, a provider spec or a reference), `egress_check(provider_id)` -> `invisible(TRUE)` or `gptr_error_egress` (consumers P13, P19; IC-29).

`replay_mode()` implements IC-45: an explicit argument always wins; otherwise `"replay"` is forced when R CMD check
runs outside testthat (examples), then the option, `GPTR_REPLAY`, the settings and `"auto"`. `replay_guard()`
refuses, in replay mode, any provider whose record is not `offline = TRUE`, so `GPTR_REPLAY=replay` in `setup.R`
blocks real models but never the fake provider (IC-30). `egress_check()` is the acknowledgement of 03 §6.10: local
and offline providers need none; a missing acknowledgement is asked once when someone can answer (an `ask_human`,
IC-53; recorded at user scope with the `egress_ack` message) and is `gptr_error_egress` otherwise. The
`.opts$context = "none"` exemption is applied by the gateway before it calls `egress_check()` (Task 9).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-config.R`:

```r
# tests/testthat/test-gptr-config.R (Task 4: append)


test_that("replay_mode() resolves argument, option, environment and default", {
  local_gw()
  withr::local_envvar(GPTR_REPLAY = NA, `_R_CHECK_PACKAGE_NAME_` = NA)
  withr::local_options(gptr.replay = NULL)
  expect_identical(replay_mode(), "auto")
  expect_identical(replay_mode("live"), "live")
  withr::local_envvar(GPTR_REPLAY = "replay")
  expect_identical(replay_mode(), "replay")
  withr::local_options(gptr.replay = "record")
  expect_identical(replay_mode(), "record")
  expect_error(replay_mode("never"), class = "gptr_error_invalid_argument")
})

test_that("replay is forced only when R CMD check runs outside testthat (IC-45)", {
  local_gw()
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr", TESTTHAT = "true", GPTR_REPLAY = NA)
  withr::local_options(gptr.replay = NULL)
  expect_identical(replay_mode(), "auto")
  withr::local_envvar(TESTTHAT = NA)
  expect_identical(replay_mode(), "replay")
  expect_identical(replay_mode("live"), "live")
})

test_that("replay_guard() refuses providers that call a remote model, in replay mode only", {
  local_gw()
  withr::local_envvar(GPTR_REPLAY = "replay", `_R_CHECK_PACKAGE_NAME_` = NA)
  withr::local_options(gptr.replay = NULL)
  expect_invisible(replay_guard(gptr_fake_provider(list("ok"))))
  corp = gptr_provider("corp", api = "openai-completions", base_url = "https://llm.corp.example/v1",
                       auth = "CORP_LLM_KEY",
                       models = list(list(id = "corp-large", context = 128000)))
  expect_error(replay_guard(corp), class = "gptr_error_not_recorded")
  withr::local_envvar(GPTR_REPLAY = "auto")
  expect_invisible(replay_guard(corp))
})

test_that("egress_check() passes local, offline and acknowledged providers", {
  local_gw()
  local_fake_provider(list("ok"))
  expect_invisible(egress_check("fake"))
  settings_write("user", list(egress = list(corp = "ack")))
  expect_invisible(egress_check("corp"))
})

test_that("a first non-interactive use without an acknowledgement is gptr_error_egress", {
  local_gw()
  cnd = expect_error(egress_check("corp"), class = "gptr_error_egress")
  expect_identical(cnd$how_to_ack,
                   paste0("gptr_config(egress = utils::modifyList(gptr_config()$egress, ",
                          "list(`corp` = \"ack\")), .scope = \"user\")"))
  # following the hint keeps the acknowledgements already given
  settings_write("user", list(egress = list(anthropic = "ack")))
  eval(parse(text = cnd$how_to_ack))
  expect_identical(settings_read("user")$egress, list(anthropic = "ack", corp = "ack"))
})

test_that("an interactive yes records the acknowledgement at user scope", {
  local_gw()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  expect_invisible(egress_check("corp"))
  expect_identical(settings_read("user")$egress$corp, "ack")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: the new tests fail with `could not find function "replay_mode"`, `"replay_guard"` and `"egress_check"`.

- [ ] **Step 3: Write the implementation**

Append to `R/gptr-config.R`:

```r
# R/gptr-config.R (Task 4: append)

# -------------------------------------------------------------- replay (contract 7.8; IC-30, IC-45)

#' The four replay modes
#' @noRd
replay_modes = function() c("auto", "replay", "live", "record")

#' The replay mode: `arg` > gptr.replay > GPTR_REPLAY > settings > "auto"; "replay" is forced when
#' R CMD check runs outside testthat (examples), unless `arg` is given (IC-45)
#' @noRd
replay_mode = function(arg = NULL) {
  if (!is.null(arg)) return(check_choice(arg, replay_modes(), "replay"))
  if (isTRUE(check_running()) && !identical(Sys.getenv("TESTTHAT"), "true")) return("replay")
  opt = getOption("gptr.replay")
  if (!is.null(opt)) return(check_choice(opt, replay_modes(), "gptr.replay"))
  env = Sys.getenv("GPTR_REPLAY", "")
  if (nzchar(env)) return(check_choice(env, replay_modes(), "GPTR_REPLAY"))
  set = settings_get("replay")
  if (is.character(set) && length(set) == 1L && set %in% replay_modes()) return(set)
  "auto"
}

#' The provider id of a model record, provider spec or reference
#' @noRd
replay_provider_id = function(model) {
  if (inherits(model, "gptr_provider")) return(model$id %||% model$name)
  if (is.list(model) && is.character(model$provider)) return(model$provider)
  if (is.character(model) && length(model) == 1L) {
    ref = sub(":.*$", "", model)
    if (grepl("/", ref, fixed = TRUE)) return(sub("/.*$", "", ref))
    m = model_resolve(ref, strict = FALSE)
    return(if (is.null(m)) ref else m$provider)
  }
  gptr_abort("replay_guard() needs a model record, a provider spec or a model reference.",
             "invalid_argument", arg = "model", expected = "a model record or reference")
}

#' In replay mode, refuses a request to any provider whose record is not `offline = TRUE`
#' (gptr_error_not_recorded); `invisible(TRUE)` otherwise
#' @noRd
replay_guard = function(model, what = "model call") {
  if (!identical(replay_mode(), "replay")) return(invisible(TRUE))
  pid = replay_provider_id(model)
  rec = if (inherits(model, "gptr_provider")) model else provider_get(pid)
  if (isTRUE(rec$offline)) return(invisible(TRUE))
  gptr_abort(c(paste0("Replay mode: gptr may not make a ", what, " to ", pid,
                      " because nothing is recorded for it."),
               "Unset GPTR_REPLAY or pass replay = \"auto\" to call the model."),
             "not_recorded", document = NA_character_, prompt = NA_character_)
}

# -------------------------------------------------------------- egress (6.10 of 03; IC-29, IC-53)

#' The question shown before the first automatic context goes to a provider (gptr_confirm()
#' appends the ` [y/N] ` hint itself)
#' @noRd
egress_question = function(id) {
  paste0("gptr sends your prompts to ", id, " together with automatic context: the workspace ",
         "listing (object names, classes and sizes), a description of the R environment, project ",
         "instructions and descriptions of the objects you attach. Allow this for ", id,
         " from now on?")
}

#' The acknowledgements stored in the user settings file
#' @noRd
egress_user_acks = function() {
  e = settings_file_read(settings_path("user"))$egress
  if (is.list(e) && !is.null(names(e))) e else list()
}

#' `invisible(TRUE)` when automatic context may go to `provider_id`: acknowledged in the user
#' settings, or a local or offline provider. With someone to ask it asks once (an ask_human) and
#' records the answer at user scope; otherwise gptr_error_egress (13 C-34)
#' @noRd
egress_check = function(provider_id) {
  check_string(provider_id, "provider_id")
  rec = provider_get(provider_id)
  if (!is.null(rec) && (isTRUE(rec$local) || isTRUE(rec$offline))) return(invisible(TRUE))
  acks = settings_get("egress")
  if (is.list(acks) && identical(acks[[provider_id]], "ack")) return(invisible(TRUE))
  # gptr_config() merges top-level keys only, so the hint keeps the acknowledgements already given
  how = paste0("gptr_config(egress = utils::modifyList(gptr_config()$egress, list(`", provider_id,
               "` = \"ack\")), .scope = \"user\")")
  if (gptr_can_prompt() && isTRUE(gptr_confirm(egress_question(provider_id)))) {
    acks = utils::modifyList(egress_user_acks(), stats::setNames(list("ack"), provider_id))
    settings_write("user", list(egress = acks))
    gptr_inform(paste0("Recorded that automatic context may go to ", provider_id, " (",
                       settings_path("user"), ")."), "egress_ack")
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0("gptr has not been told that it may send session context to ",
                      provider_id, "."),
               paste0("Acknowledge it once with ", how,
                      ", or pass .opts = list(context = \"none\").")),
             "egress", provider = provider_id, how_to_ack = how)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 97 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-config.R tests/testthat/test-gptr-config.R
git commit -m "feat(gateway): add replay_mode(), replay_guard() and the egress acknowledgement"
```

---

### Task 5: Capture leaves, prompt selection, interpolation, argument validation and the call record

**Files:**
- Create: `R/gptr-capture.R`
- Test: `tests/testthat/test-gptr-capture.R` (create)

**Interfaces:**
- Consumes: P01 `as_utf8(x)`, `id_new(prefix = "", n = 10L)`, `gptr_opt(name)`, `schema_problems(schema)`, the checkers of 04 §1.1; P02 `registry_names(kind, session = NULL)`, `registry_get(kind, name, session = NULL)`; Task 4 `replay_modes()`.
- Produces (04 §7.8): `dot_facts(x)` [leaf] -> `list(class, is_session, is_chr1, length, dim, bytes, text)`; `interpolate_prompt(template, envir)` -> `list(prompt = chr(1), interp = chr)` (the sorted `name=value` pairs; P14 echoes `prompt`, P15 hashes `interp` into `args=`); `call_new(...)` -> a `gptr_call`; `call_release(call)` -> `invisible(lgl(1))`; `call_value(call, i)` [leaf]; plus the gateway helpers used by Tasks 6-9: `dot_get()`, `binding_address()`, `dot_is_literal()`, `dot_sites()`, `dot_labels()`, `select_prompt()`, `gateway_context_items()` (not `context_items()`, which is P07's), `unmask_env()`, `name_norm()`, `gateway_modes()`, `gateway_presets()`, `gateway_builtin_tools()`, `gateway_interpolate()`, `gateway_opts()`, `gateway_args()`.

This task writes the copy-safe capture machinery of G3 (§3 "GATEWAY CAPTURE RULES", t2b, t5 and the verification
log) with IC-41 applied: a dot whose expression at the call site (`sys.call()`) is a plain symbol is read **by name**
from the caller frame through the leaf `dot_get()` (`get0()`), so its promise is never forced; literals are taken
from the expression; every other dot (a call such as the inner `gptr()` of a pipe, a forwarded `...`/`..n`, a value
spliced in by `do.call()`) is forced exactly once through `...elt(i)` in the gateway's `while` loop and parked in the
call record's `values` environment, which `call_release()` empties at settlement [R2]. `dot_sites()` maps each dot
to the symbol written at the call site, skipping arguments named after a formal that follows the dots; with more
than one forwarded `...` it gives up and returns `NA` for every dot, so they are all forced through `...elt()`.
Prompt selection is report 12 §2.D3: `prompt =` wins, else the first unnamed string literal, else the first unnamed
length-1 character value that is not a session; a leading unnamed session is the continuation target; two unnamed
literals warn `two_prompts` (Task 8 signals it). Interpolation is contract 6.1.4.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-gptr-capture.R`:

```r
# tests/testthat/test-gptr-capture.R (Task 5: create)
# test-gptr-capture.R -- dot facts, call sites, prompt selection, identifier resolution,
# interpolation and the gptr_call record (plan P08).

test_that("dot_facts() reads class, shape, size and small text only [leaf]", {
  f = dot_facts(mtcars)
  expect_identical(f$class, "data.frame")
  expect_identical(f$dim, c(32L, 11L))
  expect_false(f$is_chr1)
  expect_null(f$text)
  g = dot_facts("hello")
  expect_true(g$is_chr1)
  expect_identical(g$text, "hello")
  expect_false(dot_facts(NA_character_)$is_chr1)
  expect_null(dot_facts(strrep("a", 70000))$text)
})

test_that("dot_sites() marks call-site symbols and leaves forwarded dots to ...elt() (IC-41)", {
  g = function(...) dot_sites(sys.call(), ...length())
  expect_identical(g("x", big, 2 + 2), c(NA, "big", NA))
  w = function(...) g("x", ...)
  expect_identical(w(big, 2), rep(NA_character_, 3L))
  h = function(d) g("x", d, k = y)
  expect_identical(h(1), c(NA, "d", "y"))
})

test_that("select_prompt() picks the target session, the prompt and the context", {
  s = structure(new.env(), class = "gptr_session")
  sel = select_prompt(c("", "", ""), list(dot_facts(s), dot_facts("go"), dot_facts(mtcars)),
                      c("value", "literal", "symbol"), FALSE)
  expect_identical(sel$target, 1L)
  expect_identical(sel$prompt, 2L)
  expect_identical(sel$context, 3L)
  expect_true(sel$literal)
  two = select_prompt(c("", ""), list(dot_facts("a"), dot_facts("b")), c("literal", "literal"),
                      FALSE)
  expect_true(two$two)
  var = select_prompt(c("", ""), list(dot_facts(mtcars), dot_facts("q")), c("symbol", "symbol"),
                      FALSE)
  expect_identical(var$prompt, 2L)
  expect_false(var$literal)
  named = select_prompt(c("s", ""), list(dot_facts(s), dot_facts("q")), c("symbol", "literal"),
                        FALSE)
  expect_true(is.na(named$target))
})

test_that("name_norm() maps _ and . to - and lower-cases (IC-42)", {
  expect_identical(name_norm(c("single_cell", "High.Performance_R")),
                   c("single-cell", "high-performance-r"))
})

test_that("interpolate_prompt() fills {name} from short atomic vectors only (contract 6.1.4)", {
  e = new.env()
  e$cl = 3L
  e$top = c("CD3E", "CD4")
  e$many = 1:60
  e$fun = function() 1
  r = interpolate_prompt("Cluster {cl} has {top}; {missing} {many} {fun}", e)
  expect_identical(r$prompt, "Cluster 3 has CD3E, CD4; {missing} {many} {fun}")
  expect_identical(r$interp, c("cl=3", "top=CD3E, CD4"))
})

test_that("interpolation keeps literal braces, never re-interpolates and cuts long values", {
  e = new.env()
  e$cl = 3L
  e$inj = "{cl}"
  e$long = strrep("a", 2000)
  expect_identical(interpolate_prompt("{{cl}} and {{ }}", e)$prompt, "{cl} and { }")
  expect_identical(interpolate_prompt("v = {inj}", e)$prompt, "v = {cl}")
  expect_identical(nchar(interpolate_prompt("{long}", e)$prompt), 1000L)
  expect_identical(interpolate_prompt("no braces here", e)$interp, character())
  expect_identical(interpolate_prompt('{"json": 1}', e)$prompt, '{"json": 1}')
})

test_that("gateway_interpolate() honours .opts$interpolate and the option", {
  expect_true(gateway_interpolate(list()))
  expect_false(gateway_interpolate(list(interpolate = FALSE)))
  local_gptr_options(interpolate = FALSE)
  expect_false(gateway_interpolate(list()))
})

test_that("call_new(), call_value() and call_release() follow contract 7.8", {
  e = new.env()
  e$big = 1:10
  v = new.env(parent = emptyenv())
  assign(".v2", mtcars, envir = v)
  items = list(
    list(label = "big", kind = "symbol", name = "big", slot = NULL, address = NA_character_,
         facts = list()),
    list(label = "head(mtcars)", kind = "value", name = NULL, slot = ".v2", address = NULL,
         facts = list()))
  call = call_new(prompt = "p", context = items, values = v, envir = e)
  expect_s3_class(call, "gptr_call")
  expect_match(call$id, "^c[0-9a-f]{8}$")
  expect_identical(call$template, "p")
  expect_true(is.na(call$top_level))
  expect_identical(call_value(call, 1L), 1:10)
  expect_identical(call_value(call, 2L), mtcars)
  expect_true(call_release(call))
  expect_null(call$envir)
  expect_length(names(v), 0L)
  expect_error(call_value(call, 1L), class = "gptr_error_internal")
})

test_that("a held call record is left alone until its hold flag is cleared", {
  call = call_new(envir = new.env())
  call$hold = TRUE
  expect_false(call_release(call))
  expect_true(is.environment(call$envir))
  call$hold = FALSE
  expect_true(call_release(call))
  expect_null(call$envir)
})

test_that("unmask_env() replaces a magrittr mask by its parent", {
  e = new.env()
  mask = new.env(parent = e)
  assign(".", 1, envir = mask) # nolint: object_name_linter. magrittr's mask binds `.`.
  expect_identical(unmask_env(mask), e)
  expect_identical(unmask_env(e), e)
  expect_identical(unmask_env(globalenv()), globalenv())
})

test_that("gateway_args() validates the value arguments of gptr()", {
  a = gateway_args(NULL, c("x", "y"), NULL, 0.5, NULL, NA, FALSE, list(cost = 1), "live",
                   list(max_turns = 3), TRUE, FALSE)
  expect_identical(a$replay, "live")
  expect_identical(a$opts$max_turns, 3L)
  expect_identical(a$budget, list(cost = 1))
  expect_error(gateway_args(NULL, "x", NULL, 0.5, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 1, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 0.5, NULL, "maybe", FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 0.5, NULL, NULL, FALSE, list(dollars = 1), NULL,
                            list(), TRUE, FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(0, NULL, NULL, 0.5, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
})

test_that("gateway_opts() validates the core switches and plugin namespaces (IC-44)", {
  expect_identical(gateway_opts(list()), list())
  expect_identical(gateway_opts(list(context = "names"))$context, "names")
  expect_error(gateway_opts(list(context = "all")), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(nope = 1)), class = "gptr_error_invalid_argument")
  off = gptr_register(gptr_spec("setting", "panel.size", default = 1L, description = "Panel size",
                                scope = "both", validate = function(value) as.integer(value)))
  withr::defer(off())
  expect_identical(gateway_opts(list(panel = list(size = 3)))$panel$size, 3L)
  expect_error(gateway_opts(list(panel = list(colour = "red"))),
               class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(list(seed = 42))$seed, 42L)
  expect_identical(gateway_opts(list(thinking = "high"))$thinking, "high")
  expect_error(gateway_opts(list(frontend = "no-such-frontend")),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(images = list("no-such-file.png"))),
               class = "gptr_error_invalid_argument")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-capture")'
```

Expected: every test fails with `could not find function` (`dot_facts`, `dot_sites`, `select_prompt`, `name_norm`, `interpolate_prompt`, `gateway_interpolate`, `call_new`, `unmask_env`, `gateway_args`, `gateway_opts`).

- [ ] **Step 3: Write the implementation**

Create `R/gptr-capture.R`:

```r
# R/gptr-capture.R (Task 5: create)
# gptr-capture.R -- copy-safe base-R capture of gptr() calls (rules R2-R3; G3 section 3 "GATEWAY
# CAPTURE RULES", verified by G3 t2b and t5 and its fact-check; IC-41), identifier resolution
# (contract 6.1.3, IC-42), {identifier} interpolation (6.1.4), prompt selection, argument
# validation and the gptr_call record (7.8, IC-13). Plan P08, layer L6.
#
# Every helper that touches a user value is a leaf: it forces its arguments on entry, creates no
# closure, handler or match.arg() while it holds the value, and returns primitives only.

# ------------------------------------------------------------------ dot facts (leaves)

#' Facts about one dot value [leaf] (contract 7.8; G3 `.leaf_dot`)
#' @noRd
dot_facts = function(x) {
  chr = is.character(x)
  n = length(x)
  list(class = class(x),
       is_session = inherits(x, "gptr_session"),
       is_chr1 = chr && n == 1L && !is.na(x) && (!is.object(x) || inherits(x, c("glue", "AsIs"))),
       length = n,
       dim = dim(x),
       bytes = as.numeric(utils::object.size(x)),
       text = if (chr && n <= 65536L && sum(nchar(x, type = "bytes"), na.rm = TRUE) <= 65536L) {
         as_utf8(paste0(x))
       } else {
         NULL
       })
}

#' The value bound to a call-site symbol, read by name [leaf]; R's own error when it is unbound
#' @noRd
dot_get = function(name, envir) {
  if (!exists(name, envir = envir, inherits = TRUE)) {
    gptr_abort(paste0("object '", name, "' not found"), "invalid_argument", arg = name,
               expected = "an object that exists")
  }
  get0(name, envir = envir, inherits = TRUE)
}

#' Address of the object bound to `name` as seen from `envir`, or NA [leaf]
#' @noRd
binding_address = function(name, envir) {
  if (!exists(name, envir = envir, inherits = TRUE)) return(NA_character_)
  obj_address_leaf(get0(name, envir = envir, inherits = TRUE))
}

#' rlang::obj_address() of a forced value [leaf]
#' @noRd
obj_address_leaf = function(x) rlang::obj_address(x)

#' TRUE for a length-1 constant written at the call site (a literal)
#' @noRd
dot_is_literal = function(e) {
  (is.character(e) || is.numeric(e) || is.logical(e) || is.complex(e)) && length(e) == 1L &&
    is.null(attributes(e))
}

#' Names of gptr()'s formals after the dots (contract 6.1; test-gptr-gateway.R checks that they
#' equal `setdiff(names(formals(gptr)), "...")`)
#' @noRd
gateway_formal_names = function() {
  c("model", "mode", "skills", "plugins", "extensions", "tools", "agents", "parallel", "choices",
    "levels", "threshold", "min_confidence", "uncertain", "prompt", "envir", "background", "budget",
    "replay", ".opts", ".run", ".stdin")
}

#' For each dot, the symbol written at the call site when the dot is a plain symbol there, else NA.
#' Forwarded dots (`...`, `..1`) are NA: they are forced through ...elt(), never read by name,
#' because the caller frame is not where their promises evaluate (IC-41)
#' @noRd
dot_sites = function(sc, n) {
  sites = rep(NA_character_, n)
  if (!n) return(sites)
  args = as.list(sc)[-1L]
  nm = names(args)
  if (is.null(nm)) nm = rep("", length(args))
  nm[is.na(nm)] = ""
  formals_after = gateway_formal_names()
  toks = list()
  forwarded = 0L
  for (j in seq_along(args)) {
    if (nzchar(nm[j]) && nm[j] %in% formals_after) next
    e = args[[j]]
    if (identical(e, quote(...)) || (is.symbol(e) && grepl("^\\.\\.[0-9]+$", as.character(e)))) {
      toks[[length(toks) + 1L]] = NA
      forwarded = forwarded + 1L
    } else {
      toks[[length(toks) + 1L]] = list(e)
    }
  }
  if (forwarded > 1L) return(sites)
  width = n - (length(toks) - forwarded)
  pos = 1L
  for (t in toks) {
    if (pos > n) break
    if (!is.list(t)) {
      pos = pos + max(width, 0L)
      next
    }
    e = t[[1L]]
    if (is.symbol(e) && nzchar(as.character(e))) sites[pos] = as.character(e)
    pos = pos + 1L
  }
  sites
}

#' Context labels: the argument name, else the symbol, else the deparsed expression (60 chars);
#' values spliced in by do.call() are labelled `..i`
#' @noRd
dot_labels = function(exprs, nms) {
  if (!length(exprs)) return(character())
  out = character(length(exprs))
  for (i in seq_along(exprs)) {
    e = exprs[[i]]
    out[i] = if (nzchar(nms[i])) {
      nms[i]
    } else if (is.symbol(e)) {
      as.character(e)
    } else if (is.language(e) || dot_is_literal(e)) {
      d = paste(deparse(e, width.cutoff = 60L, nlines = 1L), collapse = "")
      if (nchar(d) > 60L) paste0(substr(d, 1L, 57L), "...") else d
    } else {
      paste0("..", i)
    }
  }
  as_utf8(out)
}

#' Chooses the continuation target, the prompt and the context dots from facts only (contract
#' 6.1.1 step 2; report 12 section 2.D3)
#' @noRd
select_prompt = function(nms, facts, kinds, have_prompt) {
  n = length(facts)
  named = nzchar(nms)
  is_s = vapply(facts, function(f) isTRUE(f$is_session), NA)
  chr1 = vapply(facts, function(f) isTRUE(f$is_chr1), NA)
  target = if (n >= 1L && !named[1L] && is_s[1L]) 1L else NA_integer_
  cand = setdiff(which(!named), target)
  lits = cand[kinds[cand] == "literal" & chr1[cand]]
  vals = cand[kinds[cand] != "literal" & chr1[cand] & !is_s[cand]]
  prompt = if (have_prompt) {
    NA_integer_
  } else if (length(lits)) {
    lits[1L]
  } else if (length(vals)) {
    vals[1L]
  } else {
    NA_integer_
  }
  context = setdiff(seq_len(n), c(target, prompt))
  list(target = target, prompt = prompt,
       literal = !is.na(prompt) && identical(kinds[prompt], "literal"),
       context = context, two = !have_prompt && length(lits) >= 2L)
}

#' Context items of the call record (contract 7.8): label, kind, name (symbols), slot (values and
#' literals in `values`), address (symbols; IC-40 visibility check) and facts. (Named apart from
#' P07's context_items() in R/prompt-context.R, which collates later and would replace it.)
#' @noRd
gateway_context_items = function(idx, kinds, sites, labels, facts, addrs) {
  out = vector("list", length(idx))
  for (k in seq_along(idx)) {
    j = idx[k]
    f = facts[[j]]
    sym = identical(kinds[j], "symbol")
    out[[k]] = list(label = labels[j], kind = kinds[j],
                    name = if (sym) sites[j] else NULL,
                    slot = if (sym) NULL else paste0(".v", j),
                    address = if (sym) addrs[j] else NULL,
                    facts = list(class = f$class, dim = f$dim, length = f$length, bytes = f$bytes,
                                 is_chr1 = f$is_chr1))
  }
  out
}

#' Replaces a magrittr mask (an environment whose only binding is `.`) by its parent
#' (report 12 section 2.B4). Uses the primitive names(): ls(<env>) runs tryCatch() internally, and
#' its garbage handler would keep a user frame referenced (rule R3; verified with tracemem).
#' @noRd
unmask_env = function(env) {
  if (!identical(env, globalenv()) && identical(names(env), ".")) return(parent.env(env))
  env
}


# ------------------------------------------------------------------ fixed vocabularies

#' `name_norm(x)`: lower case with `_` and `.` mapped to `-` (IC-42)
#' @noRd
name_norm = function(x) tolower(gsub("[._]", "-", x))

#' Modes, presets and built-in tool names known before their plans register them
#' @noRd
gateway_modes = function() c("plan", "manual", "edits", "auto")

#' The built-in preset names (P07 registers them as `preset` records)
#' @noRd
gateway_presets = function() c("minimal", "standard", "readonly", "extended")

#' The built-in tool names (P10 and P11 register them as `tool` records)
#' @noRd
gateway_builtin_tools = function() c("read", "edit", "write", "grep", "find", "ls", "r", "ask")

# ------------------------------------------------------------------ interpolation (6.1.4; IC-45)

#' Formats one interpolated value: an atomic vector of 1-50 elements, joined with ", ", cut at
#' 1,000 characters; anything else is not interpolated (NULL) [leaf]
#' @noRd
interp_format = function(x) {
  if (is.null(x) || !is.atomic(x) || length(x) < 1L || length(x) > 50L) return(NULL)
  v = paste(format(x, trim = TRUE, justify = "none"), collapse = ", ")
  if (nchar(v) > 1000L) v = substr(v, 1L, 1000L)
  as_utf8(v)
}

#' The interpolated text of `{name}`, or NULL when `name` is unbound or not a short atomic vector
#' @noRd
interp_value = function(name, envir) {
  interp_format(get0(name, envir = envir, inherits = TRUE))
}

#' `{identifier}` interpolation of a literal prompt (contract 6.1.4). `{{` and `}}` are literal
#' braces; values are never re-interpolated. Returns list(prompt, interp) where interp holds the
#' sorted `name=value` pairs used (hashed into the block header's `args=` key by P15). `envir` may
#' be a user frame: the loop is a `while` loop, because a `for` loop that calls a closure with a
#' local bound to a frame keeps that frame referenced (G3 cause 2, re-verified for P08).
#' @noRd
interpolate_prompt = function(template, envir) {
  check_string(template, "template")
  check_env(envir, "envir")
  hits = gregexpr("\\{\\{|\\}\\}|\\{[.A-Za-z][.A-Za-z0-9_]*\\}", template, perl = TRUE)[[1L]]
  if (hits[1L] == -1L) return(list(prompt = template, interp = character()))
  starts = as.integer(hits)
  lens = attr(hits, "match.length")
  out = character()
  pairs = character()
  pos = 1L
  k = 1L
  while (k <= length(starts)) {
    s = starts[k]
    e = s + lens[k] - 1L
    out = c(out, substr(template, pos, s - 1L))
    tok = substr(template, s, e)
    if (identical(tok, "{{")) {
      out = c(out, "{")
    } else if (identical(tok, "}}")) {
      out = c(out, "}")
    } else {
      nm = substr(tok, 2L, nchar(tok) - 1L)
      v = interp_value(nm, envir)
      if (is.null(v)) {
        out = c(out, tok)
      } else {
        out = c(out, v)
        pairs = c(pairs, paste0(nm, "=", v))
      }
    }
    pos = e + 1L
    k = k + 1L
  }
  out = c(out, substr(template, pos, nchar(template)))
  list(prompt = as_utf8(paste(out, collapse = "")),
       interp = sort(unique(pairs), method = "radix"))
}

#' TRUE unless `.opts$interpolate = FALSE` or `options(gptr.interpolate = FALSE)`
#' @noRd
gateway_interpolate = function(opts) {
  if (isFALSE(opts$interpolate)) return(FALSE)
  !isFALSE(gptr_opt("interpolate"))
}

# ------------------------------------------------------------------ argument validation (6.1)

#' The `.opts` names of contract 6.1
#' @noRd
gateway_opts_names = function() {
  c("thinking", "max_turns", "context", "record", "interpolate", "timeout", "output", "system",
    "preset", "returns", "max_active", "backend", "frontend", "images", "seed")
}

#' Validates `.opts`: the core switches, and entries named by a plugin namespace, validated by
#' that plugin's `setting` specs `<namespace>.<field>` (IC-44)
#' @noRd
gateway_opts = function(opts) {
  if (is.null(opts) || (is.list(opts) && !length(opts))) return(list())
  check_list(opts, ".opts", named = TRUE)
  out = opts
  settings = registry_names("setting")
  for (k in names(opts)) {
    v = opts[[k]]
    if (k %in% gateway_opts_names()) {
      out[k] = list(gateway_opt_check(k, v))
      next
    }
    fields = settings[startsWith(settings, paste0(k, "."))]
    if (!length(fields)) {
      gptr_abort(paste0("`.opts$", k, "` is not a known option or plugin namespace."),
                 "invalid_argument", arg = ".opts", expected = paste(gateway_opts_names(),
                                                                     collapse = ", "))
    }
    check_list(v, paste0(".opts$", k), named = TRUE)
    for (f in names(v)) {
      key = paste0(k, ".", f)
      if (!key %in% fields) {
        gptr_abort(paste0("`.opts$", k, "$", f, "` is not a setting of the `", k, "` plugin."),
                   "invalid_argument", arg = ".opts", expected = paste(fields, collapse = ", "))
      }
      spec = registry_get("setting", key)
      if (!is.null(v[[f]]) && is.function(spec$validate)) v[f] = list(spec$validate(v[[f]]))
    }
    out[k] = list(v)
  }
  out
}

#' Validates one core `.opts` entry
#' @noRd
gateway_opt_check = function(k, v) {
  arg = paste0(".opts$", k)
  switch(k,
    thinking = check_choice(v, c("off", "minimal", "low", "medium", "high", "xhigh", "max"), arg),
    max_turns = as.integer(check_number(v, arg, min = 1, int = TRUE)),
    context = check_choice(v, c("summary", "names", "none"), arg),
    record = check_flag(v, arg),
    interpolate = check_flag(v, arg),
    timeout = check_number(v, arg, min = 0),
    output = check_choice(v, "factor", arg),
    system = {
      if (!is.character(v)) check_list(v, arg, named = TRUE) else check_string(v, arg)
      v
    },
    preset = check_choice(v, unique(c(gateway_presets(), registry_names("preset"))), arg),
    returns = {
      check_list(v, arg, named = TRUE)
      bad = schema_problems(v)
      if (length(bad)) {
        gptr_abort(c("`.opts$returns` is not a valid JSON Schema:", bad), "invalid_argument",
                   arg = arg, expected = "a JSON Schema list")
      }
      v
    },
    max_active = as.integer(check_number(v, arg, min = 1, int = TRUE)),
    backend = check_choice(v, unique(c("auto", registry_names("backend"))), arg),
    frontend = check_choice(v, registry_names("frontend"), arg),
    images = gateway_images_check(v),
    seed = as.integer(check_number(v, arg, int = TRUE)),
    v)
}

#' `.opts$images`: image file paths, ggplot or recordedplot objects (IC-44)
#' @noRd
gateway_images_check = function(v) {
  items = if (is.character(v) || inherits(v, c("ggplot", "recordedplot"))) list(v) else v
  if (!is.list(items)) {
    gptr_abort("`.opts$images` takes image paths, ggplot objects or recorded plots.",
               "invalid_argument", arg = ".opts$images", expected = "a list of images")
  }
  for (x in items) {
    ok = (is.character(x) && length(x) == 1L && file.exists(x)) ||
      inherits(x, c("ggplot", "recordedplot"))
    if (!ok) {
      gptr_abort("Each image must be an existing PNG/JPEG path, a ggplot or a recordedplot.",
                 "invalid_argument", arg = ".opts$images", expected = "image paths or plots")
    }
  }
  items
}

#' Validates the value arguments of gptr(); forces each on entry [leaf]
#' @noRd
gateway_args = function(parallel, choices, lvls, threshold, min_confidence, uncertain, background,
                        budget, replay, opts, run, stdin) {
  force(parallel)
  force(choices)
  force(lvls)
  force(threshold)
  force(min_confidence)
  force(uncertain)
  force(background)
  force(budget)
  force(replay)
  force(opts)
  force(run)
  force(stdin)
  par_n = if (is.null(parallel)) NULL else
    as.integer(check_number(parallel, "parallel", min = 1, int = TRUE))
  if (!is.null(choices)) {
    labs = if (is.factor(choices)) levels(choices) else check_strings(choices, "choices")
    if (length(labs) < 2L || anyDuplicated(labs)) {
      gptr_abort("`choices` needs at least two unique labels.", "invalid_argument",
                 arg = "choices", expected = "two or more unique labels")
    }
  }
  if (!is.null(lvls)) {
    check_strings(lvls, "levels")
    if (length(lvls) < 2L) {
      gptr_abort("`levels` needs at least two level descriptions.", "invalid_argument",
                 arg = "levels", expected = "two or more levels")
    }
  }
  check_number(threshold, "threshold", min = 0, max = 1)
  if (threshold <= 0 || threshold >= 1) {
    gptr_abort("`threshold` must lie strictly between 0 and 1.", "invalid_argument",
               arg = "threshold", expected = "a number in (0, 1)")
  }
  check_number(min_confidence, "min_confidence", min = 0, max = 1, null = TRUE)
  ok_unc = is.null(uncertain) || is.function(uncertain) || identical(uncertain, "stop") ||
    (is.logical(uncertain) && length(uncertain) == 1L)
  if (!ok_unc) {
    gptr_abort("`uncertain` takes NA, TRUE, FALSE, \"stop\" or function(state, answer).",
               "invalid_argument", arg = "uncertain",
               expected = "NA, TRUE, FALSE, \"stop\" or a function")
  }
  check_flag(background, "background")
  check_flag(run, ".run")
  check_flag(stdin, ".stdin")
  if (!is.null(budget)) {
    check_list(budget, "budget", named = TRUE)
    bad = setdiff(names(budget), c("tokens", "cost", "turns"))
    if (length(bad)) {
      gptr_abort(paste0("Unknown budget field: ", paste(bad, collapse = ", "), "."),
                 "invalid_argument", arg = "budget", expected = "tokens, cost and turns")
    }
    for (k in names(budget)) check_number(budget[[k]], paste0("budget$", k), min = 0, null = TRUE)
  }
  rep_mode = if (is.null(replay)) NULL else check_choice(replay, replay_modes(), "replay")
  list(parallel = par_n, choices = choices, levels = lvls, threshold = threshold,
       min_confidence = min_confidence, uncertain = uncertain, background = background,
       budget = budget, replay = rep_mode, opts = gateway_opts(opts), run = run, stdin = stdin)
}

# ------------------------------------------------------------------ the gptr_call record (7.8)

#' Builds the gptr_call record (IC-13): an environment with the bindings of contract 7.8, plus
#' `interp` (the sorted `name=value` pairs of 6.1.4) and `hold` (TRUE while a started run still
#' needs the record after gptr() returned)
#' @noRd
call_new = function(prompt = NULL, template = NULL, interp = character(), session = NULL,
                    context = list(), values = NULL, envir = NULL, ids = list(), args = list(),
                    sys_call = NULL, nframe = NA_integer_) {
  call = new.env(parent = emptyenv())
  call$id = id_new("c", 8L)
  call$prompt = prompt
  call$template = template %||% prompt
  call$interp = interp
  call$session = session
  call$context = context
  call$values = values %||% new.env(parent = emptyenv())
  call$envir = envir
  call$ids = ids
  call$args = args
  call$sys_call = sys_call
  call$nframe = nframe
  call$top_level = NA
  call$doc = NULL
  call$hold = FALSE
  class(call) = "gptr_call"
  call
}

#' Releases a call record [R2]: rm() of its values, `envir` and `sys_call` set to NULL. Called on
#' every exit path of gptr(). A record whose `hold` flag is set (its run was started for later
#' pumping) is left alone; the listeners of call_hold() (Task 9) clear the flag and release it.
#' @noRd
call_release = function(call) {
  if (!inherits(call, "gptr_call")) return(invisible(FALSE))
  if (isTRUE(call$hold)) return(invisible(FALSE))
  v = call$values
  if (is.environment(v)) rm(list = names(v), envir = v)
  call$envir = NULL
  call$sys_call = NULL
  invisible(TRUE)
}

#' The value of context item `i` [leaf]: symbols by name from `envir`, others from `values`
#' @noRd
call_value = function(call, i) {
  it = call$context[[i]]
  if (is.null(it)) {
    gptr_abort(paste0("The call has no context item ", i, "."), "invalid_argument", arg = "i",
               expected = "an index of call$context")
  }
  if (identical(it$kind, "symbol")) {
    env = call$envir
    if (!is.environment(env)) {
      gptr_abort("The gateway call was already released; its context cannot be read.",
                 "internal", detail = "call_value() after call_release()")
    }
    return(get0(it$name, envir = env, inherits = TRUE))
  }
  get0(it$slot, envir = call$values, inherits = FALSE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-capture")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 65 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-capture.R tests/testthat/test-gptr-capture.R
git commit -m "feat(gateway): add copy-safe capture leaves, interpolation and the call record"
```

---

### Task 6: Identifier resolution and the `identifier.resolve` service

**Files:**
- Modify: `R/gptr-capture.R` (append)
- Test: `tests/testthat/test-gptr-capture.R` (append)

**Interfaces:**
- Consumes: Task 5 (`name_norm()`, `gateway_modes()`, `gateway_presets()`, `gateway_builtin_tools()`); P01 `as_utf8()`, `json_obj()`, `gptr_inform()`, `on_load()`, `ext_service_set()`; P02 `registry_names()`, `registry_get()`, `gptr_registry()`, `gptr_agent()` (which stores the raw captured `model`/`skills` expressions, IC-34); P05 `catalog_aliases()` -> chr (P05 ships `sonnet`, `opus`, `haiku`, `gemini`, `flash`, `gpt`, `jev`, `claude_code`).
- Produces (04 §7.8): `resolve_identifier(expr, arg, envir)` -> `NULL`, chr, a spec, or a list (`tools`/`extensions`), registered as the service `identifier.resolve` (consumers: `gptr_agent()` capture via P02 stores raw expressions, P17 agent files); `identifier_known(name, arg)` -> `lgl(1)`; plus the gateway helpers `ident_force_needed(expr, arg, envir)`, `ident_value(x, arg, expr)` [leaf], `ident_label(expr)`, `resolve_agents(expr, envir)` (with `agents_check_names()` and `agents_named_call()`: P02's `gptr_agent()` requires a `name`, so the list names of a literal `list(stats = agent(...))` are passed into the `agent()` calls before they are evaluated) and `session_accessor_names()` (IC-71).

The table of contract 6.1.3, in order: `NULL` -> the settings default; a string -> itself; a symbol that is a
**known identifier** for the argument (catalog aliases, registered provider/model/router ids and provider aliases
for `model`; the four modes; presets; tools; skills, plugins, extensions and agents compared after `name_norm()`,
IC-42) -> its canonical name, with a once-per-session `alias_shadowed` message when a character variable of that
name holds a different value; `!!x` and `I(x)` -> the value of `x`; another bound symbol -> its value, which must
be character or a spec of the right kind (`gptr_error_invalid_identifier` names the class otherwise); an unknown
unbound symbol -> the literal name (a decimal-looking model name such as `gpt5.1` is echoed once); `c(a, "b")`,
`+name`, `-name` -> element-wise; any other call -> evaluated in an alias mask whose parent is reset to `emptyenv()`
afterwards (rule R3). The gateway (Task 8) forces a formal's promise instead of reading a bound symbol by name
whenever `ident_force_needed()` says so: forcing evaluates in the promise's own environment, which is what makes
forwarded dots correct (G3 t2b: a wrapper's local `m` never wins).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-capture.R`:

```r
# tests/testthat/test-gptr-capture.R (Task 6: append)

test_that("resolve_identifier() follows the table of contract 6.1.3", {
  e = new.env()
  e$m = "haiku"
  e$hard = TRUE
  e$mice = data.frame(a = 1)
  expect_null(resolve_identifier(NULL, "model", e))
  expect_identical(resolve_identifier("opus", "model", e), "opus")
  expect_identical(resolve_identifier(quote(opus), "model", e), "opus")
  expect_identical(resolve_identifier(quote(m), "model", e), "haiku")
  bang = quote(!!m)
  expect_identical(resolve_identifier(bang, "model", e), "haiku")
  expect_identical(resolve_identifier(quote(I(m)), "model", e), "haiku")
  expect_identical(resolve_identifier(quote(if (hard) opus else haiku), "model", e), "opus")
  expect_identical(resolve_identifier(quote(gpt9), "model", e), "gpt9")
  expect_identical(resolve_identifier(quote(c(+grep, -write)), "tools", e), c("+grep", "-write"))
  expect_identical(resolve_identifier(quote(plan), "mode", e), "plan")
  expect_error(resolve_identifier(quote(mice), "model", e), class = "gptr_error_invalid_identifier")
  expect_error(resolve_identifier("fast", "mode", e), class = "gptr_error_invalid_argument")
  expect_error(resolve_identifier(quote(fast), "mode", e), class = "gptr_error_invalid_argument")
})

test_that("an alias shadowed by a character variable wins, with a message (contract 6.1.3)", {
  e = new.env()
  e$sonnet = "my-own-model"
  local_gptr_options(quiet = FALSE)
  expect_message(resolve_identifier(quote(sonnet), "model", e),
                 class = "gptr_message_alias_shadowed")
  expect_identical(suppressMessages(resolve_identifier(quote(sonnet), "model", e)), "sonnet")
  bang = quote(!!sonnet)
  expect_identical(resolve_identifier(bang, "model", e), "my-own-model")
})

test_that("skill names compare after name_norm() (IC-42)", {
  d = withr::local_tempdir()
  writeLines(c("---", "name: single-cell", "description: Single-cell analysis", "---"),
             file.path(d, "SKILL.md"))
  off = gptr_register(gptr_spec("skill", "single-cell", description = "Single-cell analysis",
                                path = file.path(d, "SKILL.md"), dir = d, source = "user"))
  withr::defer(off())
  e = new.env()
  expect_true(identifier_known("single_cell", "skills"))
  expect_identical(resolve_identifier(quote(single_cell), "skills", e), "single-cell")
  expect_identical(resolve_identifier(quote(c(single_cell, "other")), "skills", e),
                   c("single-cell", "other"))
})

test_that("an ambiguous normalised match lists the candidates", {
  local_mocked_bindings(identifier_pool = function(arg) c("single-cell", "single_cell"))
  cnd = expect_error(resolve_identifier(quote(single.cell), "skills", new.env()),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$candidates, c("single-cell", "single_cell"))
})

test_that("agents take their list names; model and skills resolve as identifiers (IC-34, IC-71)", {
  e = new.env()
  # the north-star form: no name and no description inside agent() (02 NS-6)
  a = resolve_agents(quote(list(stats = agent(model = opus, skills = statistics),
                                lit = agent(description = "Literature", model = "haiku"))), e)
  expect_s3_class(a$stats, "gptr_agent")
  expect_identical(a$stats$name, "stats")
  expect_identical(a$stats$model, "opus")
  expect_identical(a$stats$skills, "statistics")
  expect_identical(a$lit$name, "lit")
  expect_identical(a$lit$model, "haiku")
  expect_error(resolve_agents(quote(list(text = agent(description = "x"))), e),
               class = "gptr_error_invalid_argument")
  expect_error(resolve_agents(quote(list(agent(description = "x"))), e),
               class = "gptr_error_invalid_argument")
  expect_error(resolve_agents(quote(list(a = agent(model = opus), a = agent(model = haiku))), e),
               class = "gptr_error_invalid_argument")
})

# The bootstrap entry (ext_service_get() serves it once builtin:gateway is loaded, Task 9)
test_that("resolve_identifier() is registered as the identifier.resolve service", {
  entry = the$services[["identifier.resolve"]]
  expect_identical(entry$fun(quote(opus), "model", new.env()), "opus")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-capture")'
```

Expected: the new tests fail with `could not find function "resolve_identifier"`, `"identifier_known"` and `"resolve_agents"`, and the service test with `attempt to apply non-function` (no bootstrap entry `the$services[["identifier.resolve"]]` yet).

- [ ] **Step 3: Write the implementation**

Append to `R/gptr-capture.R`:

```r
# R/gptr-capture.R (Task 6: append)

# ------------------------------------------------------------------ identifiers (6.1.3, IC-42)

#' Aliases declared by registered provider records
#' @noRd
identifier_provider_aliases = function() {
  out = character()
  for (id in registry_names("provider")) {
    out = c(out, as.character(registry_get("provider", id)$aliases))
  }
  out
}

#' Names of plugins that have registry records (sources `plugin:<name>`)
#' @noRd
identifier_plugin_names = function() {
  src = unique(as.character(gptr_registry()$source))
  sub("^plugin:", "", src[startsWith(src, "plugin:")])
}

#' Known identifiers for an argument
#' @noRd
identifier_pool = function(arg) {
  switch(arg,
    model = , small_model = , system1 = unique(c(catalog_aliases(), registry_names("provider"),
                                                  registry_names("router"), registry_names("model"),
                                                  identifier_provider_aliases())),
    mode = gateway_modes(),
    preset = unique(c(gateway_presets(), registry_names("preset"))),
    tools = unique(c(registry_names("tool"), gateway_builtin_tools(), gateway_presets())),
    skills = registry_names("skill"),
    agents = registry_names("agent"),
    plugins = , extensions = identifier_plugin_names(),
    character())
}

#' Canonical names matching `name` for `arg` (skills, plugins, extensions and agents compare after
#' name_norm(); other kinds exactly)
#' @noRd
identifier_match = function(name, arg) {
  pool = identifier_pool(arg)
  if (!length(pool)) return(character())
  if (arg %in% c("skills", "agents", "plugins", "extensions")) {
    return(unique(pool[name_norm(pool) == name_norm(name)]))
  }
  if (name %in% pool) name else character()
}

#' `identifier_known(name, arg)`: TRUE when `name` is a known identifier for `arg` (contract 7.8)
#' @noRd
identifier_known = function(name, arg) length(identifier_match(name, arg)) > 0L

#' A noun for messages
#' @noRd
ident_noun = function(arg) {
  switch(arg, model = , small_model = , system1 = "model name", mode = "mode name",
         preset = "preset name", tools = "tool name", skills = "skill name",
         plugins = "plugin name", extensions = "extension name", agents = "agent name",
         paste(arg, "name"))
}

#' One-line deparse of an identifier expression
#' @noRd
ident_label = function(expr) paste(deparse(expr, width.cutoff = 60L, nlines = 1L), collapse = "")

#' Checks character identifiers (modes must be one of the four)
#' @noRd
ident_check_chr = function(x, arg) {
  if (anyNA(x) || any(!nzchar(x))) {
    gptr_abort(paste0("`", arg, "` contains an empty or missing name."), "invalid_argument",
               arg = arg, expected = "non-empty names")
  }
  if (identical(arg, "mode") && !all(x %in% gateway_modes())) {
    gptr_abort(paste0("`mode` must be one of plan, manual, edits or auto, not \"", x[1L], "\"."),
               "invalid_argument", arg = "mode", expected = "plan, manual, edits or auto")
  }
  x
}

#' Which spec classes an argument accepts
#' @noRd
ident_spec_ok = function(spec, arg) {
  switch(arg,
    model = , small_model = , system1 = inherits(spec, c("gptr_provider", "gptr_router")),
    tools = inherits(spec, "gptr_tool"),
    agents = inherits(spec, "gptr_agent"),
    extensions = TRUE,
    FALSE)
}

#' Accepts a resolved value: character (identifiers), a spec of the right kind, a factory for
#' `extensions`, or a list of those for `tools`/`extensions`; anything else is
#' gptr_error_invalid_identifier naming its class [leaf]
#' @noRd
ident_accept = function(value, arg, label) {
  if (inherits(value, "AsIs")) class(value) = setdiff(class(value), "AsIs")
  if (is.null(value)) return(NULL)
  if (is.character(value)) return(ident_check_chr(as_utf8(as.character(value)), arg))
  if (inherits(value, "gptr_spec") && ident_spec_ok(value, arg)) return(value)
  if (is.function(value) && identical(arg, "extensions")) return(value)
  if (is.list(value) && !is.object(value) && arg %in% c("tools", "extensions")) {
    return(ident_combine(lapply(value, ident_accept, arg = arg, label = label)))
  }
  gptr_abort(paste0("`", label, "` is a ", class(value)[1L], ", not a ", ident_noun(arg),
                    ". Quote the name (\"", label, "\") or pass a character value."),
             c("invalid_identifier", "invalid_argument"), arg = arg,
             .data = list(class = class(value)[1L]))
}

#' Combines element-wise results: all character -> a character vector, else a list
#' @noRd
ident_combine = function(parts) {
  parts = parts[!vapply(parts, is.null, NA)]
  if (!length(parts)) return(NULL)
  if (all(vapply(parts, is.character, NA))) return(unlist(parts, use.names = FALSE))
  out = list()
  for (p in parts) {
    if (is.character(p)) {
      out = c(out, as.list(p))
    } else if (inherits(p, "gptr_spec") || is.function(p)) {
      out = c(out, list(p))
    } else {
      out = c(out, p)
    }
  }
  out
}

#' The once-per-session `alias_shadowed` message: a known identifier won over a character variable
#' of the same name holding a different value
#' @noRd
ident_shadow_notice = function(nm, hit, arg, envir) {
  if (!exists(nm, envir = envir, inherits = TRUE)) return(invisible(NULL))
  v = get0(nm, envir = envir, inherits = TRUE)
  if (is.character(v) && !identical(as.character(v), hit)) {
    gptr_inform(paste0("`", nm, "` was read as the ", ident_noun(arg), " \"", hit, "\", not as ",
                       "your variable of the same name; write !!", nm, " to use the variable."),
                "alias_shadowed", .once = paste0("alias_shadowed:", arg, ":", nm))
  }
  invisible(NULL)
}

#' Echoes once a model name that looks like a decimal version (gpt5.1) and was taken literally
#' @noRd
ident_decimal_notice = function(nm, arg) {
  if (arg %in% c("model", "small_model", "system1") && grepl("[0-9][.][0-9]", nm)) {
    gptr_inform(paste0("The model name `", nm, "` was taken literally as \"", nm,
                       "\"; documents record it quoted."), "notice",
                .once = paste0("decimal:", nm))
  }
  invisible(NULL)
}

#' A symbol: known identifier > bound value > literal name
#' @noRd
ident_symbol = function(nm, arg, envir) {
  hit = identifier_match(nm, arg)
  if (length(hit) > 1L) {
    gptr_abort(paste0("`", nm, "` matches several ", ident_noun(arg), "s (",
                      paste(hit, collapse = ", "), "). Write the one you mean as a string."),
               c("invalid_identifier", "invalid_argument"), arg = arg,
               .data = list(class = "name", candidates = hit))
  }
  if (length(hit) == 1L) {
    ident_shadow_notice(nm, hit, arg, envir)
    return(hit)
  }
  if (exists(nm, envir = envir, inherits = TRUE)) {
    return(ident_accept(get0(nm, envir = envir, inherits = TRUE), arg, nm))
  }
  ident_decimal_notice(nm, arg)
  # a literal name is checked like a string (`mode = fast` is gptr_error_invalid_argument here,
  # not later inside the kernel)
  ident_check_chr(nm, arg)
}

#' Evaluates a call in the alias mask: known identifiers bound to their names, parent = the caller;
#' the mask's parent is reset to emptyenv() afterwards (rule R3)
#' @noRd
ident_mask = function(expr, arg, envir) {
  pool = identifier_pool(arg)
  vals = stats::setNames(as.list(pool), pool)
  if (arg %in% c("skills", "agents", "plugins", "extensions")) {
    alt = gsub("-", "_", pool, fixed = TRUE)
    extra = alt != pool
    vals = c(vals, stats::setNames(as.list(pool[extra]), alt[extra]))
  }
  if (!length(vals)) vals = json_obj()
  mask = list2env(vals, parent = envir)
  on.exit(`parent.env<-`(mask, emptyenv()), add = TRUE)
  ident_accept(eval(expr, mask), arg, ident_label(expr))
}

#' Resolves an identifier expression by the table of contract 6.1.3 (the `identifier.resolve`
#' service). Returns NULL, a character vector, a spec, or a list for `tools`/`extensions`.
#' @noRd
resolve_identifier = function(expr, arg, envir) {
  if (is.null(expr)) return(NULL)
  if (is.character(expr)) return(ident_check_chr(as_utf8(expr), arg))
  if (is.symbol(expr)) return(ident_symbol(as.character(expr), arg, envir))
  if (is.call(expr)) {
    head = expr[[1L]]
    if (identical(head, as.name("!")) && length(expr) == 2L && is.call(expr[[2L]]) &&
        identical(expr[[2L]][[1L]], as.name("!")) && length(expr[[2L]]) == 2L) {
      inner = expr[[2L]][[2L]]
      return(ident_accept(eval(inner, envir), arg, ident_label(inner)))
    }
    if (identical(head, as.name("I")) && length(expr) == 2L) {
      return(ident_accept(eval(expr[[2L]], envir), arg, ident_label(expr[[2L]])))
    }
    if (identical(head, as.name("c")) || identical(head, as.name("list"))) {
      items = as.list(expr)[-1L]
      parts = vector("list", length(items))
      i = 1L
      while (i <= length(items)) {
        parts[i] = list(resolve_identifier(items[[i]], arg, envir))
        i = i + 1L
      }
      return(ident_combine(parts))
    }
    if ((identical(head, as.name("+")) || identical(head, as.name("-"))) && length(expr) == 2L) {
      inner = resolve_identifier(expr[[2L]], arg, envir)
      if (!is.character(inner) || length(inner) != 1L) {
        gptr_abort(paste0("`", ident_label(expr), "` needs one name after ", as.character(head),
                          "."), c("invalid_identifier", "invalid_argument"), arg = arg,
                   .data = list(class = class(inner)[1L]))
      }
      return(paste0(as.character(head), inner))
    }
    return(ident_mask(expr, arg, envir))
  }
  ident_accept(expr, arg, ident_label(expr))
}

#' TRUE when the gateway must force the formal's promise to resolve it: an unknown symbol bound
#' where it is called, or an I() call (G3 t2b: forcing evaluates in the promise's own environment,
#' which is correct for forwarded dots)
#' @noRd
ident_force_needed = function(expr, arg, envir) {
  if (is.symbol(expr)) {
    nm = as.character(expr)
    if (!nzchar(nm) || identifier_known(nm, arg)) return(FALSE)
    return(exists(nm, envir = envir, inherits = TRUE))
  }
  is.call(expr) && identical(expr[[1L]], as.name("I"))
}

#' Forces a formal's promise and accepts its value [leaf]
#' @noRd
ident_value = function(x, arg, expr) {
  force(x)
  label = if (is.call(expr) && identical(expr[[1L]], as.name("I"))) expr[[2L]] else expr
  ident_accept(x, arg, ident_label(label))
}

#' Session accessor names that agent names may not take (IC-71)
#' @noRd
session_accessor_names = function() {
  c("text", "value", "values", "usage", "cost", "history", "messages", "model", "mode", "status",
    "reason", "id", "kind", "file", "turns", "envir", "children", "ext", "plan", "last_rewind",
    "editor_text")
}

#' Checks agent names: unique syntactic names that are not session accessors (contract 6.1, IC-71)
#' @noRd
agents_check_names = function(nms) {
  if (is.null(nms) || anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms) ||
      any(make.names(nms) != nms)) {
    gptr_abort("Agent names must be unique syntactic names, as in agents = list(stats = agent()).",
               "invalid_argument", arg = "agents", expected = "unique syntactic names")
  }
  clash = intersect(nms, session_accessor_names())
  if (length(clash)) {
    gptr_abort(paste0("Agent names may not equal session accessors: ",
                      paste(clash, collapse = ", "), "."), "invalid_argument", arg = "agents",
               expected = "names other than session accessors")
  }
  invisible(nms)
}

#' Gives every `agent(...)` element of a literal `list(name = agent(...))` its list name when the
#' call names none: gptr_agent() requires a name (P02 spec_finish), and contract 6.1 names agents
#' by their list names (`agents = list(stats = agent(model = opus))`, 02 NS-6)
#' @noRd
agents_named_call = function(expr) {
  nms = names(expr)
  if (is.null(nms)) return(expr)
  j = 2L
  while (j <= length(expr)) {
    a = expr[[j]]
    if (nzchar(nms[j]) && is.call(a) && identical(a[[1L]], as.name("agent"))) {
      an = names(a)
      if (is.null(an)) an = rep("", length(a))
      positional = length(a) >= 2L && !nzchar(an[2L])
      if (!("name" %in% an[-1L]) && !positional) {
        a$name = nms[j]
        expr[[j]] = a
      }
    }
    j = j + 1L
  }
  expr
}

#' Evaluates `agents =` in a mask where `agent` is gptr_agent() and resolves each definition's
#' captured `model` and `skills` expressions (IC-34, IC-71). A literal `list(...)` has its names
#' checked first and passed into its `agent()` calls.
#' @noRd
resolve_agents = function(expr, envir) {
  if (is.null(expr)) return(NULL)
  if (is.call(expr) && identical(expr[[1L]], as.name("list"))) {
    n0 = names(expr)
    agents_check_names(if (is.null(n0)) rep("", length(expr) - 1L) else n0[-1L])
    expr = agents_named_call(expr)
  }
  mask = new.env(parent = envir)
  assign("agent", gptr_agent, envir = mask)
  on.exit(`parent.env<-`(mask, emptyenv()), add = TRUE)
  val = eval(expr, mask)
  if (is.null(val)) return(NULL)
  if (!is.list(val) || inherits(val, "gptr_spec") || !length(val)) {
    gptr_abort("`agents` must be a named list, as in agents = list(stats = agent(model = opus)).",
               "invalid_argument", arg = "agents", expected = "a named list of agent definitions")
  }
  nms = names(val)
  agents_check_names(nms)
  out = vector("list", length(val))
  i = 1L
  while (i <= length(val)) {
    sp = val[[i]]
    if (!inherits(sp, "gptr_agent")) {
      gptr_abort(paste0("agents$", nms[i], " is not an agent definition; use agent(...)."),
                 "invalid_argument", arg = "agents", expected = "gptr_agent() definitions")
    }
    if (is.language(sp$model)) sp$model = resolve_identifier(sp$model, "model", envir)
    if (is.language(sp$skills)) sp$skills = resolve_identifier(sp$skills, "skills", envir)
    if (is.null(sp$name) || !nzchar(sp$name)) sp$name = nms[i]
    out[[i]] = sp
    i = i + 1L
  }
  names(out) = nms
  out
}

on_load(ext_service_set("identifier.resolve", resolve_identifier, provided_by = "P08",
                        builtin = "gateway"))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-capture")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 96 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-capture.R tests/testthat/test-gptr-capture.R
git commit -m "feat(gateway): add identifier resolution and the identifier.resolve service"
```

---

### Task 7: `gptr_config()`, `gptr_init()` and the templates

**Files:**
- Modify: `R/gptr-config.R` (append)
- Create: `inst/templates/vignette.Rmd`, `inst/templates/settings.json`, `inst/templates/gitignore`
- Test: `tests/testthat/test-gptr-config.R` (append)

**Interfaces:**
- Consumes: Tasks 1-4 (`settings_read()`, `settings_write()`, `settings_spec()`, `settings_keys()`, `settings_effective()`, `settings_file_read()`, `settings_path()`, `gateway_state()`, `control_check()`, `trust_store()`, `trust_get()`), Task 6 `resolve_identifier()`; P01 `workspace_dir()`, `project_root()`; P01 `path_norm()`, `write_atomic()`, `gptr_can_prompt()`, `gptr_confirm(question, default = FALSE)` (which appends the ` [y/N] ` hint itself, so P08's questions end with `?`); P02 `registry_filters_set(filters, scope = c("session", "user", "project"))`.
- Produces the exports (04 §6.2) `gptr_config(..., .scope = NULL)` and `gptr_init(path, instructions = TRUE, gitignore = TRUE)`, the helpers `template_file(name)` and `gateway_filters_sync()` (the user and project `filters` settings applied to the registry; called again by Task 9's `gateway_run()`) and the three template files of 04 §11.16.

`gptr_config()` without arguments returns `settings_effective()`. With named arguments it validates every key
against the registered `setting` specs (core keys plus plugin settings), resolves `model`, `small_model`,
`system1`, `mode` and `preset` as bare identifiers, refuses `egress` outside user scope, writes the patch into the
scope (IC-71: `.scope = NULL` is `"project"` when a workspace exists, else `"session"`) and returns the previous
values invisibly. Setting `filters` also hands the scope's new filter list to P02's
`registry_filters_set(filters, scope)` (04 §10.1 names `gptr_config(filters =)` as a filter path; P02 applies its
own safety rules, IC-53): the session list directly, the user and project files through `gateway_filters_sync()`.
That helper is how the settings key `filters` of the user file and of a trusted project's file (an untrusted
project contributes no `filters`, IC-52) reaches the registry at all, also after a restart: P02 relies on the
settings layer for it (P02 self-review item 18), and Task 9 calls it at the start of every top-level
`gateway_run()`. It re-applies a scope only when its list changed since the last application. `gptr_init()` has no default path: without `path` it asks when someone can answer and signals
`gptr_error_noninteractive` otherwise; it never overwrites an existing file, never writes `.Rbuildignore` (it
offers the `^\.gptr$` line), and asks the separate trust question only when someone can answer. Both are
control-category calls (IC-53).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-config.R`:

```r
# tests/testthat/test-gptr-config.R (Task 7: append)


test_that("gptr_config() without arguments returns the effective settings", {
  local_gw()
  cfg = gptr_config()
  expect_s3_class(cfg, "gptr_config")
  expect_identical(cfg$mode, "manual")
})

test_that("gptr_config() takes bare identifiers and returns the previous values", {
  local_gw(workspace = FALSE)
  old = gptr_config(mode = plan)
  expect_null(old$mode)
  expect_identical(gptr_config()$mode, "plan")
  expect_identical(settings_read("session")$mode, "plan")
  gptr_config(mode = old$mode)
  expect_identical(gptr_config()$mode, "manual")
})

test_that("gptr_config(.scope = NULL) writes the project file when a workspace exists (IC-71)", {
  local_gw()
  gptr_config(mode = manual)
  expect_identical(settings_read("project")$mode, "manual")
  expect_null(settings_read("session")$mode)
})

test_that("gptr_config() validates keys, scopes and values", {
  local_gw()
  expect_error(gptr_config(nope = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_config(egress = list(a = "ack"), .scope = "session"),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_config(mode = fast, .scope = "session"), class = "gptr_error_invalid_argument")
  expect_error(gptr_config(plot = 3, .scope = "session"), class = "gptr_error_invalid_argument")
  gptr_config(egress = list(corp = "ack"), .scope = "user")
  expect_identical(settings_get("egress")$corp, "ack")
})

test_that("gptr_config(filters = ) applies the scope's filters to the registry (04 10.1)", {
  local_gw(workspace = FALSE)
  box = new.env()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$args = list(filters = filters, scope = scope)
      invisible(filters)
    })
  gptr_config(filters = "-builtin:mcp", .scope = "session")
  expect_identical(box$args, list(filters = "-builtin:mcp", scope = "session"))
  gptr_config(filters = NULL, .scope = "session")
  expect_identical(box$args, list(filters = character(), scope = "session"))
})

test_that("user and trusted project filters reach the registry once per change (04 10.1)", {
  proj = local_gw()
  st = gateway_state()
  old = st$filters_applied
  withr::defer({
    st$filters_applied = old
  })
  st$filters_applied = NULL
  box = new.env()
  box$calls = list()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$calls = c(box$calls, list(list(filters = filters, scope = scope)))
      invisible(filters)
    })
  settings_write("user", list(filters = "-builtin:mcp"))
  settings_write("project", list(filters = "-plugin:panel"))
  gateway_filters_sync()
  # the project is untrusted, so its filters do not apply (IC-52)
  expect_identical(box$calls, list(list(filters = "-builtin:mcp", scope = "user")))
  gateway_filters_sync()
  expect_length(box$calls, 1L)
  gptr_trust(proj, TRUE)
  gateway_filters_sync()
  expect_identical(box$calls[[2L]], list(filters = "-plugin:panel", scope = "project"))
  gptr_config(filters = NULL, .scope = "user")
  expect_identical(box$calls[[3L]], list(filters = character(), scope = "user"))
  expect_length(box$calls, 3L)
})

test_that("gptr_config() is refused from model code during a run (IC-53)", {
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_config(mode = auto, .scope = "session"), class = "gptr_error_permission")
  expect_null(settings_read("session")$mode)
})

test_that("the run$signal$control token check (shared with P11) refuses model code (IC-53)", {
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(control_check("gptr_permissions"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_permissions")
})

test_that("a model-code gptr_permissions() call during a run is refused (IC-53, P11)", {
  skip_if_not(exists("gptr_permissions", mode = "function"), "gptr_permissions() arrives with P11")
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_permissions(allow = "r(level<=3)"), class = "gptr_error_permission")
})

test_that("gptr_init() is refused from model code during a run (IC-53)", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_init(d), class = "gptr_error_permission")
  expect_false(dir.exists(file.path(d, ".gptr")))
})

test_that("gptr_init() without a path needs someone to answer", {
  local_gw(workspace = FALSE)
  expect_error(gptr_init(), class = "gptr_error_noninteractive")
})

test_that("gptr_init(path) writes the templates once and never overwrites them", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  ws = gptr_init(d)
  expect_identical(ws, path_norm(file.path(d, ".gptr")))
  expect_setequal(list.files(ws, all.files = TRUE, no.. = TRUE),
                  c(".gitignore", "agents", "prompts", "settings.json", "skills", "vignette.Rmd"))
  settings = json_decode(paste(readLines(file.path(ws, "settings.json"), encoding = "UTF-8"),
                               collapse = "\n"))
  expect_identical(settings, list(version = 1L, mode = "manual", record = "ask"))
  expect_true("sessions/" %in% readLines(file.path(ws, ".gitignore"), encoding = "UTF-8"))
  writeLines("{}", file.path(ws, "settings.json"))
  gptr_init(d)
  expect_identical(readLines(file.path(ws, "settings.json"), encoding = "UTF-8"), "{}")
})

test_that("gptr_init() in a package source offers the .Rbuildignore line, never writes it", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  writeLines(c("Package: toy", "Version: 0.1.0"), file.path(d, "DESCRIPTION"))
  local_gptr_options(quiet = FALSE)
  expect_message(gptr_init(d), class = "gptr_message_notice")
  expect_false(file.exists(file.path(d, ".Rbuildignore")))
})

test_that("gptr_init() refuses a .gptr that is not a directory", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  writeLines("x", file.path(d, ".gptr"))
  expect_error(gptr_init(d), class = "gptr_error_workspace")
})

test_that("with a human, gptr_init() asks to create the workspace and then about trust", {
  proj = local_gw(workspace = FALSE)
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  ws = gptr_init()
  expect_true(dir.exists(file.path(proj, ".gptr")))
  expect_true(gptr_trust(proj))
  d = withr::local_tempdir()
  gptr_init(d)
  expect_true(isTRUE(trust_record(d)$trusted))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: the new tests fail with `could not find function "gptr_config"` and `could not find function "gptr_init"`.

- [ ] **Step 3: Write the implementation**

Create `inst/templates/settings.json` (one line):

```text
{"version": 1, "mode": "manual", "record": "ask"}
```

Create `inst/templates/gitignore` (written as `.gptr/.gitignore`; the lines of 04 §11.1):

```text
sessions/
cache/s2/
cache/tmp/
checkpoints/
artifacts/*/v*/data/
artifacts/*/run/
locks/
*.lock/
settings.local.json
transcripts/
```

Create `inst/templates/vignette.Rmd` (no executable chunks):

```text
---
title: "Project instructions"
output: html_document
---

<!-- gptr reads this file as project instructions: text only, nothing here is executed.
     Keep it short. To reuse an existing file, write its name on a line of its own: @AGENTS.md -->

## Data

- Where the main data sets live, how they are loaded and how large they are.

## Conventions

- Coding style, preferred packages, naming rules, units.

## Do not

- Things the agent must never do in this project.
```

Append to `R/gptr-config.R`:

```r
# R/gptr-config.R (Task 7: append)

# ------------------------------------------------------------------ gptr_config() (contract 6.2)

#' Settings keys that take bare identifiers
#' @noRd
settings_ident_keys = function() c("model", "small_model", "system1", "mode", "preset")

#' Resolves an identifier-valued setting; it must be one name
#' @noRd
settings_ident = function(expr, key, envir) {
  arg = if (key %in% c("small_model", "system1")) "model" else key
  v = resolve_identifier(expr, arg, envir)
  if (is.null(v)) return(NULL)
  if (!is.character(v) || length(v) != 1L) {
    gptr_abort(paste0("`", key, "` takes one name, as in gptr_config(", key, " = sonnet); ",
                      "register provider specs with gptr_register() and name them."),
               c("invalid_identifier", "invalid_argument"), arg = key,
               .data = list(class = class(v)[1L]))
  }
  v
}

#' Show or change gptr's settings
#'
#' With no arguments, returns the effective settings with the layer each value came from:
#' package defaults < user `settings.json` < project `.gptr/settings.json` (an untrusted project
#' only tightens `mode`, `context`, `record` and permissions) < the user-level project file <
#' `options(gptr.*)` < this R session. With named arguments, sets those keys in one scope.
#'
#' `model`, `small_model`, `system1`, `mode` and `preset` take bare names (`mode = plan`); `NULL`
#' removes a key from the scope. `egress` (the providers you allow automatic context to go to) is
#' accepted only at user scope. Called from model code during a run, it is refused.
#'
#' @param ... Named settings, e.g. `mode = manual`, `model = sonnet`, `budget = list(cost = 2)`.
#' @param .scope `NULL` (the project when a `.gptr/` workspace exists, else this session), or
#'   `"session"`, `"project"` or `"user"`.
#' @return Without arguments, a `gptr_config` list. Otherwise the previous values in that scope,
#'   invisibly (a named list; `NULL` where the key was unset).
#' @examples
#' old = gptr_config(mode = plan, .scope = "session")
#' gptr_config()$mode
#' gptr_config(mode = old$mode, .scope = "session")
#' @export
gptr_config = function(..., .scope = NULL) {
  scope = if (is.null(.scope)) {
    if (is.null(workspace_dir())) "session" else "project"
  } else {
    check_choice(.scope, c("session", "project", "user"), ".scope")
  }
  n = ...length()
  if (n == 0L) return(settings_effective())
  control_check("gptr_config")
  keys = ...names()
  if (is.null(keys) || anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys)) {
    gptr_abort(paste("Every setting passed to gptr_config() needs a unique name,",
                     "as in gptr_config(mode = manual)."),
               "invalid_argument", arg = "...", expected = "uniquely named settings")
  }
  exprs = as.list(substitute(list(...)))[-1L]
  caller = parent.frame()
  known = settings_keys()
  patch = list()
  i = 1L
  while (i <= n) {
    k = keys[i]
    if (!k %in% known) {
      gptr_abort(paste0("`", k, "` is not a registered setting."), "invalid_argument", arg = k,
                 expected = "a registered setting (see gptr_config())")
    }
    spec = settings_spec(k)
    if (identical(spec$scope, "user") && !identical(scope, "user")) {
      gptr_abort(paste0("`", k, "` can only be set at user scope: gptr_config(", k,
                        " = ..., .scope = \"user\")."), "invalid_argument", arg = ".scope",
                 expected = "\"user\"")
    }
    v = if (k %in% settings_ident_keys()) settings_ident(exprs[[i]], k, caller) else ...elt(i)
    if (!is.null(v) && is.function(spec$validate)) v = spec$validate(v)
    patch[k] = list(v)
    i = i + 1L
  }
  # previous values without a closure: this frame holds `...` (rule R3)
  cur = settings_read(scope)
  prev = vector("list", n)
  names(prev) = keys
  i = 1L
  while (i <= n) {
    if (!is.null(cur[[keys[i]]])) prev[keys[i]] = list(cur[[keys[i]]])
    i = i + 1L
  }
  settings_write(scope, patch)
  # 04 10.1: gptr_config(filters =) is a filter path; P02 applies its own refusals (IC-53). The
  # user and project files go through gateway_filters_sync(), which also applies them after a
  # restart and honours the trust rule of the project layer
  if ("filters" %in% keys) {
    if (identical(scope, "session")) {
      registry_filters_set(as.character(unlist(settings_read(scope)$filters)), scope = scope)
    } else {
      gateway_filters_sync()
    }
  }
  invisible(prev)
}

#' Applies the `filters` of the user settings file, and of the project settings file while the
#' project layer is in effect (a trusted project: `filters` is not a tighten-type key, so an
#' untrusted project contributes none, as in settings_layered()), to P02's registry with
#' registry_filters_set(scope = "user" / "project") (04 10.1; P02 self-review item 18: only the
#' settings layer knows which layer a value came from). A scope is applied only when its list
#' differs from the one applied last (`the$gateway$filters_applied`); the files are read through
#' the settings cache, which re-reads a changed file, so a file edited (or a project entered)
#' since the last call is picked up by the next one. Called by gptr_config() for the user and
#' project scopes and at the start of every top-level gateway_run(). A list that P02 rejects is
#' a diagnostic and a one-time notice, never an error.
#' @noRd
gateway_filters_sync = function() {
  st = gateway_state()
  applied = st$filters_applied %||% list()
  for (scope in c("user", "project")) {
    f = character()
    if (identical(scope, "user")) {
      f = as.character(unlist(settings_file_read(settings_path("user"))$filters))
    } else {
      ws = workspace_dir()
      if (!is.null(ws) && isTRUE(trust_get(project_root()))) {
        f = as.character(unlist(settings_file_read(file.path(ws, "settings.json"))$filters))
      }
    }
    if (identical(f, applied[[scope]] %||% character())) next
    applied[[scope]] = f
    tryCatch(registry_filters_set(f, scope = scope), error = function(e) {
      why = conditionMessage(e)
      registry_diagnostic("builtin:gateway", "settings", "filters_invalid",
                          paste0("the ", scope, " settings filters were not applied: ", why))
      gptr_inform(paste0("The filters of the ", scope, " settings file were not applied: ", why),
                  "notice", .once = paste0("filters_invalid:", scope, ":",
                                           paste(f, collapse = ",")))
    })
  }
  st$filters_applied = applied
  invisible(applied)
}

# ------------------------------------------------------------- gptr_init() (contract 6.2, 11.16)

#' The installed path of a file in inst/templates (empty string when missing)
#' @noRd
template_file = function(name) system.file("templates", name, package = "gptr")

#' Copies a template from inst/templates unless the target exists (never overwrites)
#' @noRd
template_copy = function(name, dest) {
  if (file.exists(dest)) return(invisible(FALSE))
  src = template_file(name)
  if (!nzchar(src)) {
    gptr_abort(paste0("The template ", name, " is missing from the installed package."),
               "internal", detail = paste("inst/templates", name))
  }
  write_atomic(dest, readBin(src, "raw", n = file.size(src)))
  invisible(TRUE)
}

#' Offers `^\.gptr$` for .Rbuildignore in a package source; never writes it silently (13 2.3)
#' @noRd
init_rbuildignore = function(dir) {
  desc = file.path(dir, "DESCRIPTION")
  if (!file.exists(desc)) return(invisible(FALSE))
  if (!any(grepl("^Package:", readLines(desc, warn = FALSE, encoding = "UTF-8")))) {
    return(invisible(FALSE))
  }
  rb = file.path(dir, ".Rbuildignore")
  lines = if (file.exists(rb)) readLines(rb, warn = FALSE, encoding = "UTF-8") else character()
  line = "^\\.gptr$"
  if (line %in% trimws(lines)) return(invisible(FALSE))
  # gptr_confirm() appends the " [y/N] " hint
  ask = paste0("Add ", line, " to .Rbuildignore?")
  if (gptr_can_prompt() && isTRUE(gptr_confirm(ask))) {
    write_atomic(rb, paste0(paste(c(lines, line), collapse = "\n"), "\n"))
    return(invisible(TRUE))
  }
  gptr_inform(paste0("This is a package source: add the line ", line, " to ", rb,
                     " so that R CMD build skips the workspace."), "notice")
  invisible(FALSE)
}

#' Create the project workspace `.gptr/`
#'
#' Creates `.gptr/` with `settings.json`, `skills/`, `agents/`, `prompts/`, and (by default) the
#' project-instructions file `vignette.Rmd` and `.gitignore`. Existing files are never
#' overwritten, so calling it again is safe. There is no default path: without `path` gptr asks
#' `Create .gptr/ in <project>? [y/N]` when you can answer, and signals an error otherwise.
#' Creating the workspace is consent to write there; it is not trust: gptr then asks separately
#' whether to trust the project (see [gptr_trust()]). In a package source it offers the
#' `^\.gptr$` line for `.Rbuildignore` and never writes it silently.
#'
#' @param path The project directory (it must exist).
#' @param instructions Write `vignette.Rmd` from the template when it is absent.
#' @param gitignore Write `.gptr/.gitignore` from the template when it is absent.
#' @return The absolute path of `.gptr/`, invisibly (`NULL` when you declined).
#' @examples
#' d = tempfile("proj")
#' dir.create(d)
#' gptr_init(d)
#' list.files(file.path(d, ".gptr"), all.files = TRUE)
#' unlink(d, recursive = TRUE)
#' @export
gptr_init = function(path, instructions = TRUE, gitignore = TRUE) {
  check_flag(instructions, "instructions")
  check_flag(gitignore, "gitignore")
  control_check("gptr_init")
  if (missing(path)) {
    root = project_root()
    if (!gptr_can_prompt()) {
      gptr_abort(c("gptr_init() needs `path` when nobody can answer a question.",
                   "gptr only writes to directories that you name: gptr_init(\"<project dir>\")."),
                 "noninteractive", what = "gptr_init", questions = character())
    }
    if (!isTRUE(gptr_confirm(paste0("Create .gptr/ in ", root, "?")))) {
      return(invisible(NULL))
    }
    proj = root
  } else {
    proj = check_string(path, "path")
  }
  if (!dir.exists(proj)) {
    gptr_abort(paste0("The directory ", proj, " does not exist."), "invalid_argument",
               arg = "path", expected = "an existing directory")
  }
  proj = path_norm(proj)
  ws = file.path(proj, ".gptr")
  if (file.exists(ws) && !dir.exists(ws)) {
    gptr_abort(paste0(ws, " exists and is not a directory."), "workspace", path = ws)
  }
  if (!dir.exists(ws) && !dir.create(ws, showWarnings = FALSE)) {
    gptr_abort(paste0("Could not create ", ws, "."), "workspace", path = ws)
  }
  for (sub in c("skills", "agents", "prompts")) {
    dir.create(file.path(ws, sub), showWarnings = FALSE)
  }
  template_copy("settings.json", file.path(ws, "settings.json"))
  if (instructions) template_copy("vignette.Rmd", file.path(ws, "vignette.Rmd"))
  if (gitignore) template_copy("gitignore", file.path(ws, ".gitignore"))
  init_rbuildignore(proj)
  if (gptr_can_prompt()) {
    answer = isTRUE(gptr_confirm(paste0("Trust this project (its settings, extensions and MCP ",
                                        "servers)?")))
    # `proj` itself: project_root(proj) returns the gptr.project_root / GPTR_PROJECT_ROOT override
    # whenever one is set (IC-63), which need not be the directory just initialised
    trust_store(proj, answer)
  }
  invisible(path_norm(ws))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 135 ]` (the skip is the `gptr_permissions()` leg, which runs once P11 exists).

- [ ] **Step 5: Commit**

```bash
git add R/gptr-config.R inst/templates/vignette.Rmd inst/templates/settings.json inst/templates/gitignore tests/testthat/test-gptr-config.R
git commit -m "feat(gateway): add gptr_config(), gptr_init() and the workspace templates"
```

---

### Task 8: The gateway closure, route dispatch and the `gptr_gateway` methods

**Files:**
- Create: `R/gptr-gateway.R`
- Test: `tests/testthat/test-gptr-gateway.R` (create)

**Interfaces:**
- Consumes: Tasks 5-6 (capture leaves, `select_prompt()`, `gateway_args()`, `interpolate_prompt()`, `resolve_identifier()`, `ident_force_needed()`, `ident_value()`, `resolve_agents()`, `call_new()`, `call_release()`), Task 1 `gateway_state()`; P01 `gptr_can_prompt()`, `gptr_warn()`, `gptr_inform()` and `verbosity()` (the `interpolated` echo of 04 §2.2 at verbosity >= 2), `ev_new()`, `ext_service_get()`, `ext_service_has()`; P02 `registry_all(kind, session = NULL)` (route records ordered by `order`), `registry_diagnostic()`, `ev_dispatch()`; P06 `run_current()` (the `gptr_run` field `mode`); P10 services `ns.resolve` (`function(path)`) and `ns.names` (`function(pattern)`).
- Produces: the export `gptr` (class `c("gptr_gateway", "function")`, 04 §6.1, §5.3) with the S3 methods `$.gptr_gateway`, `[[.gptr_gateway`, `$<-.gptr_gateway`, `[[<-.gptr_gateway`, `.DollarNames.gptr_gateway`, `print.gptr_gateway`; `route_pass()` (the sentinel for P13, P14, P15, P19), `gateway_defer(expr_fun)` (P19's `gptr_parallel()`), `home_address(envir)` -> chr(1) (P11), `mode_tighter(a, b)` (the name P06 reserved for P08; P06's own is `run_mode_tighter()`), `gateway_dispatch(call)`.

`gptr()` is dispatch steps 1-5 of contract 6.1.1. Its frame holds `...` and the caller frame, so it follows the
capture rules literally: no closure, handler or `match.arg()` in the frame, no assignment to a formal (new locals
only), plain-symbol dots read by name through leaves, every other dot forced once through `...elt(i)` in a `while`
loop. Identifier formals are resolved with `resolve_identifier()` on `substitute(<formal>)`, except that the
formal's own promise is forced (through the leaf `ident_value()`) when `ident_force_needed()` says the symbol is
bound and unknown, or the expression is `I(x)`. A literal prompt that `{identifier}` interpolation changed is
echoed at verbosity >= 2 as the message class `gptr_message_interpolated` (04 §2.2; silenced by `gptr.quiet`).
Routing walks `registry_all("route")` in ascending `order`: an error
in `match()` skips the route with a diagnostic, the first match emits `route` and runs, and `route_pass()` hands
the call to the next match. Inside a run the call's mode is tightened to the running mode before any route sees it
(IC-53). The record is released on every exit path (`on.exit()` in `gateway_dispatch()`, a frame that holds no
dots). `$`, `[[` and `.DollarNames` go through P10's services (IC-36) and have no side effects.

The tests use a probe route of order 1 that records what the gateway captured; the built-in routes arrive in
Task 9.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-gptr-gateway.R`:

```r
# tests/testthat/test-gptr-gateway.R (Task 8: create)
# test-gptr-gateway.R -- the gptr() gateway: capture, routing, the classed closure and its methods,
# the built-in routes on the fake provider, terminal statuses and routers (plan P08).

# A temporary project (P01's local_project(): working directory and project root) with a private
# user config directory; the process settings layer is restored when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A route of order 1 that records what the gateway captured and answers "probed".
local_probe = function(.env = parent.frame()) {
  box = new.env(parent = emptyenv())
  spec = gptr_spec("route", "test_probe", order = 1,
                   description = "test probe: records the gateway call",
                   match = function(call) TRUE,
                   run = function(call) {
                     box$prompt = call$prompt
                     box$template = call$template
                     box$interp = call$interp
                     box$ids = call$ids
                     box$args = call$args
                     box$session = call$session
                     box$labels = vapply(call$context, function(it) it$label, "")
                     box$kinds = vapply(call$context, function(it) it$kind, "")
                     box$classes = vapply(seq_along(call$context),
                                          function(i) class(call_value(call, i))[1L], "")
                     "probed"
                   })
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  box
}

fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

test_that("gptr('a', mice) and mice |> gptr('a') capture mice by name", {
  local_gw()
  box = local_probe()
  mice = data.frame(weight = c(20, 22, 25))
  expect_identical(gptr("a", mice), "probed")
  expect_identical(box$prompt, "a")
  expect_identical(box$labels, "mice")
  expect_identical(box$kinds, "symbol")
  expect_identical(mice |> gptr("a"), "probed")
  expect_identical(box$labels, "mice")
  expect_identical(box$classes, "data.frame")
})

test_that("named context, call values and do.call() values", {
  local_gw()
  box = local_probe()
  mice = data.frame(weight = 1:3)
  gptr("compare", a = mice, b = head(mtcars))
  expect_identical(box$labels, c("a", "b"))
  expect_identical(box$kinds, c("symbol", "value"))
  expect_identical(box$classes, c("data.frame", "data.frame"))
  do.call(gptr, list("p", mtcars))
  expect_identical(box$labels, "..2")
})

test_that("forwarded dots are forced once and keep their label", {
  local_gw()
  box = local_probe()
  w = function(...) gptr(...)
  mice = data.frame(weight = 1:3)
  w("describe", mice)
  expect_identical(box$prompt, "describe")
  expect_identical(box$labels, "mice")
  expect_identical(box$kinds, "value")
})

test_that("prompt selection: literal first, then a character value; two literals warn", {
  local_gw()
  box = local_probe()
  expect_warning(gptr("first", "second"), class = "gptr_warning_two_prompts")
  expect_identical(box$prompt, "first")
  expect_identical(box$labels, "\"second\"")
  task = "Summarise it"
  gptr(task)
  expect_identical(box$prompt, "Summarise it")
  expect_identical(box$template, "Summarise it")
  gptr(prompt = "explicit", "context string")
  expect_identical(box$prompt, "explicit")
})

test_that("literal prompts are interpolated from envir unless switched off (contract 6.1.4)", {
  local_gw()
  box = local_probe()
  cl = 4L
  top = c("CD3E", "CD4")
  gptr("Cluster {cl}: {top}")
  expect_identical(box$prompt, "Cluster 4: CD3E, CD4")
  expect_identical(box$template, "Cluster {cl}: {top}")
  expect_identical(box$interp, c("cl=4", "top=CD3E, CD4"))
  gptr("Cluster {cl}", .opts = list(interpolate = FALSE))
  expect_identical(box$prompt, "Cluster {cl}")
})

test_that("an interpolated prompt is echoed at verbosity 2 (gptr_message_interpolated, 04 2.2)", {
  local_gw()
  box = local_probe()
  local_gptr_options(verbose = 2L, quiet = FALSE)
  v = 7L
  cnd = expect_message(gptr("x is {v}"), class = "gptr_message_interpolated")
  expect_match(conditionMessage(cnd), "Interpolated prompt: x is 7", fixed = TRUE)
  expect_identical(box$prompt, "x is 7")
  expect_no_message(gptr("no braces here"), class = "gptr_message_interpolated")
  local_gptr_options(verbose = 1L)
  expect_no_message(gptr("x is {v}"), class = "gptr_message_interpolated")
})

test_that("identifiers through the gateway, including a wrapper with a local m (G3 t2b)", {
  local_gw()
  box = local_probe()
  m = "haiku"
  hard = TRUE
  gptr("p", model = opus)
  expect_identical(box$ids$model, "opus")
  gptr("p", model = m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = !!m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = I(m))
  expect_identical(box$ids$model, "haiku")
  w = function(...) {
    m = "WRONG-LOCAL"
    gptr("x", ...)
  }
  w(model = m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = if (hard) opus else haiku, mode = plan, tools = c(+grep, -write))
  expect_identical(box$ids$model, "opus")
  expect_identical(box$ids$mode, "plan")
  expect_identical(box$ids$tools, c("+grep", "-write"))
  mice = data.frame(a = 1)
  expect_error(gptr("p", model = mice), class = "gptr_error_invalid_identifier")
})

test_that("a leading session is the continuation target; a named session is context", {
  local_gw()
  box = local_probe()
  s0 = session_new("fake/fake-1", "manual", home = new.env())
  mice = data.frame(a = 1)
  s0 |> gptr("go on", mice)
  expect_identical(box$session, s0)
  expect_identical(box$labels, "mice")
  gptr("compare", earlier = s0)
  expect_null(box$session)
  expect_identical(box$labels, "earlier")
})

test_that("calls made during a run inherit the running mode, only tightened (IC-53)", {
  local_gw()
  box = local_probe()
  run = fake_run(mode = "plan")
  local_mocked_bindings(run_current = function() run)
  gptr("x", mode = auto)
  expect_identical(box$ids$mode, "plan")
  gptr("x")
  expect_identical(box$ids$mode, "plan")
})

test_that("gateway_defer() makes gptr() calls unstarted (.run = FALSE)", {
  local_gw()
  box = local_probe()
  gateway_defer(function() gptr("q"))
  expect_false(box$args$run)
  gptr("q")
  expect_true(box$args$run)
})

test_that("gptr() without a prompt needs a human", {
  local_gw()
  expect_error(gptr(), class = "gptr_error_noninteractive")
})

test_that("with a human but no console route, a no-prompt call is not_available", {
  skip_if(!is.null(registry_get("route", "console")), "the console route (P14) is loaded")
  local_gw()
  local_gptr_options(interactive = TRUE)
  expect_error(gptr(), class = "gptr_error_not_available")
})

test_that("unknown .opts names and a non-environment envir are refused", {
  local_gw()
  local_probe()
  expect_error(gptr("x", .opts = list(nope = 1)), class = "gptr_error_invalid_argument")
  expect_error(gptr("x", envir = list()), class = "gptr_error_invalid_argument")
})

test_that("gptr is a classed closure whose members come from the ns services (IC-36)", {
  expect_identical(class(gptr), c("gptr_gateway", "function"))
  expect_error({
    gptr$x = 1
  }, class = "gptr_error_readonly")
  expect_error({
    gptr[["x"]] = 1
  }, class = "gptr_error_readonly")
  local_mocked_bindings(
    ext_service_get = function(name) {
      switch(name, ns.resolve = function(path) paste("member", path),
             ns.names = function(pattern) c("read", "grep"))
    },
    ext_service_has = function(name) TRUE)
  expect_identical(gptr$read, "member read")
  expect_identical(gptr[["grep"]], "member grep")
  expect_identical(utils::.DollarNames(gptr, ""), c("read", "grep"))
})

test_that("before the namespace services exist, $ is not_available and completion is empty", {
  skip_if(ext_service_has("ns.resolve"), "P10 registers ns.resolve")
  expect_error(gptr$read, class = "gptr_error_not_available")
  expect_identical(utils::.DollarNames(gptr, ""), character(0))
})

test_that("print(gptr) shows the usage and the members hint", {
  local_reproducible_output(width = 80)
  expect_snapshot(print(gptr))
})

test_that("the capture helpers know gptr()'s formals after the dots", {
  expect_identical(gateway_formal_names(), setdiff(names(formals(gptr)), "..."))
})

test_that("routes run in order; route_pass() hands on; a failing match() is skipped", {
  local_gw()
  seen = new.env()
  seen$order = character()
  mk = function(name, order, result, match = function(call) TRUE) {
    gptr_spec("route", name, order = order, description = name, match = match,
              run = function(call) {
                seen$order = c(seen$order, name)
                result
              })
  }
  offs = list(gptr_register(mk("test_b", 3, "B")),
              gptr_register(mk("test_a", 2, route_pass())),
              gptr_register(mk("test_bad", 1, "never", match = function(call) stop("boom"))))
  withr::defer(for (off in offs) off())
  expect_identical(gptr("x"), "B")
  expect_identical(seen$order, c("test_a", "test_b"))
})

test_that("route_pass(), gateway_defer(), home_address() and mode_tighter()", {
  expect_s3_class(route_pass(), "gptr_route_pass")
  expect_false(gateway_deferring())
  expect_true(gateway_defer(function() gateway_deferring()))
  expect_false(gateway_deferring())
  expect_identical(home_address(globalenv()), rlang::obj_address(globalenv()))
  expect_identical(mode_tighter("auto", "plan"), "plan")
  expect_identical(mode_tighter(NULL, "edits"), "edits")
  expect_identical(mode_tighter("manual", "edits"), "manual")
})


test_that("a shadowed alias wins with a notice; skill names normalise (IC-42)", {
  local_gw()
  box = local_probe()
  # `gemini`, not `sonnet`: the notice is once per process and key, and test-gptr-capture.R
  # (which runs first in the same process) already used the `sonnet` key
  gemini = "my-own-model"
  local_gptr_options(quiet = FALSE)
  expect_message(gptr("p", model = gemini), class = "gptr_message_alias_shadowed")
  expect_identical(box$ids$model, "gemini")
  gptr("p", model = !!gemini)
  expect_identical(box$ids$model, "my-own-model")
  d = withr::local_tempdir()
  off = gptr_register(gptr_spec("skill", "single-cell", description = "Single-cell analysis",
                                path = file.path(d, "SKILL.md"), dir = d, source = "user"))
  withr::defer(off())
  gptr("p", skills = single_cell)
  expect_identical(box$ids$skills, "single-cell")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'
```

Expected: every test fails with `could not find function "gptr"` (or `object 'gptr' not found`).

- [ ] **Step 3: Write the implementation**

Create `R/gptr-gateway.R`:

```r
# R/gptr-gateway.R (Task 8: create)
# gptr-gateway.R -- gptr(): the one gateway (S-1), a classed closure whose `$` reaches the gptr$
# namespace; dispatch steps 1-6 of contract 6.1.1 with routes looked up in the registry; the
# built-in routes `nested`, `continue` and `new`, the core `setting` specs (builtin:gateway,
# IC-24), and the router.call service (IC-69). Plan P08, layer L6.

#' Run an agent in this R session
#'
#' `gptr()` is the single entry point. Give it a quoted prompt and, optionally, the objects the
#' agent should work on; it returns the agent session, which you can print, query (`$text`,
#' `$value`, `$usage`) and continue with the pipe. Models, modes, skills, plugins, extensions and
#' tools may be written as bare names.
#'
#' The dots take, in order: at most one leading session to continue, the prompt (the first
#' unnamed string literal, else the first unnamed length-1 character value), and context objects
#' (unnamed ones are labelled by their expression, named ones by name). Context objects are never
#' copied: gptr reads them by name where they live. Every other argument is matched by its exact
#' name only.
#'
#' A literal prompt gets `{name}` interpolation from `envir` (atomic vectors of 1 to 50 values;
#' `{{` and `}}` are literal braces); `.opts = list(interpolate = FALSE)` switches it off.
#'
#' Terminal statuses become conditions carrying the session as `$session`: `error` signals
#' `gptr_error_provider`, `blocked` `gptr_error_permission`, `budget` `gptr_error_budget_<kind>`
#' and `max_turns` `gptr_error_max_turns`. `gptr()` with no prompt opens the console when someone
#' can answer, and signals `gptr_error_noninteractive` otherwise.
#'
#' @usage
#' gptr(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
#'      extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
#'      choices = NULL, levels = NULL, threshold = 0.5,
#'      min_confidence = NULL, uncertain = NULL,
#'      prompt = NULL, envir = parent.frame(), background = FALSE,
#'      budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
#'      .stdin = FALSE)
#' @param ... A session to continue, the prompt, and context objects.
#' @param model A model name (`sonnet`, `"anthropic/claude-sonnet-5-5"`), a provider or router spec
#'   such as [gptr_fake_provider()], or `NULL` for the configured default.
#' @param mode One of `plan`, `manual`, `edits`, `auto`; `NULL` for the configured default.
#' @param skills,plugins,extensions Names (bare or quoted) of skills to preload, plugins and
#'   extensions to enable for this session; `extensions` also takes `function(gptr)` factories and
#'   file paths.
#' @param tools Tool names, `"+name"`/`"-name"` modifiers, a preset name, or [gptr_tool()] specs.
#' @param agents A named list of agent definitions for a team (`agent()` means [gptr_agent()]).
#' @param parallel Fan one list-like context object out over this many concurrent sub-agents.
#' @param choices,levels,threshold,min_confidence,uncertain System 1 answer shape and abstention.
#' @param prompt An explicit prompt; wins over positional selection.
#' @param envir Where the agent evaluates R code and creates objects.
#' @param background Experimental: return the running session at once (needs later).
#' @param budget `list(tokens =, cost =, turns =)` limits for this call.
#' @param replay Document replay mode: `"auto"`, `"replay"`, `"live"` or `"record"`.
#' @param .opts Rare switches such as `thinking`, `max_turns`, `context`, `returns`, `images`,
#'   `preset`, and entries named by a plugin namespace.
#' @param .run `FALSE` builds the session with the prompt queued and returns it (see
#'   [gptr_step()]).
#' @param .stdin Drive the console from piped standard input.
#' @return A `gptr_session` for agent work (invisibly when its answer was streamed to the
#'   console), or a typed System 1 vector for classifier models.
#' @examples
#' fake = gptr_fake_provider(list("The data has 32 rows."))
#' s = gptr("How many rows does the data have?", mtcars, model = fake, envir = new.env())
#' s$text
#' s |> gptr("And how many columns?")
#' identical(gptr_last(), s)
#' @export
gptr = structure(function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                          extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                          choices = NULL, levels = NULL, threshold = 0.5,
                          min_confidence = NULL, uncertain = NULL,
                          prompt = NULL, envir = parent.frame(), background = FALSE,
                          budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                          .stdin = FALSE) {
  # Capture rules R2-R3 (G3 section 3; IC-41). This frame holds `...` and the caller frame, so it
  # creates no closure, handler or match.arg() call and never assigns a formal (new locals only).
  # Plain-symbol dots are read by name through leaves; their promises are never forced. Calls and
  # forwarded dots reach leaves through ...elt() in a while loop.
  caller = parent.frame()
  env_given = !missing(envir)
  if (env_given) check_env(envir, "envir")
  sc = sys.call()
  nf = sys.nframe()
  n = ...length()
  exprs = as.list(substitute(list(...)))[-1L]
  nms = ...names()
  if (is.null(nms)) nms = rep("", n)
  nms[is.na(nms)] = ""
  sites = dot_sites(sc, n)
  facts = vector("list", n)
  kinds = character(n)
  addrs = rep(NA_character_, n)
  values = new.env(parent = emptyenv())
  i = 1L
  while (i <= n) {
    if (!is.na(sites[i])) {
      facts[[i]] = dot_facts(dot_get(sites[i], caller))
      kinds[i] = "symbol"
      addrs[i] = binding_address(sites[i], caller)
    } else if (dot_is_literal(exprs[[i]])) {
      facts[[i]] = dot_facts(exprs[[i]])
      kinds[i] = "literal"
      assign(paste0(".v", i), exprs[[i]], envir = values)
    } else {
      facts[[i]] = dot_facts(...elt(i))
      kinds[i] = "value"
      assign(paste0(".v", i), ...elt(i), envir = values)
    }
    i = i + 1L
  }
  p_arg = check_string(prompt, "prompt", null = TRUE)
  sel = select_prompt(nms, facts, kinds, !is.null(p_arg))
  args = gateway_args(parallel, choices, levels, threshold, min_confidence, uncertain, background,
                      budget, replay, .opts, .run, .stdin)
  args$run = isTRUE(args$run) && !gateway_deferring()
  args$envir_given = env_given
  target = NULL
  if (!is.na(sel$target)) {
    target = if (identical(kinds[sel$target], "symbol")) {
      dot_get(sites[sel$target], caller)
    } else {
      get(paste0(".v", sel$target), envir = values, inherits = FALSE)
    }
  }
  prompt_text = p_arg
  if (is.null(prompt_text) && !is.na(sel$prompt)) prompt_text = facts[[sel$prompt]]$text
  template = NULL
  interp = character()
  if (!is.null(prompt_text)) {
    prompt_text = as_utf8(prompt_text)
    literal = if (!is.null(p_arg)) is.character(substitute(prompt)) else isTRUE(sel$literal)
    if (literal) {
      template = prompt_text
      if (gateway_interpolate(args$opts)) {
        ip = interpolate_prompt(prompt_text, if (env_given) envir else caller)
        prompt_text = ip$prompt
        interp = ip$interp
        # 04 2.2: the interpolated prompt is echoed at verbosity >= 2 (message class
        # gptr_message_interpolated; gptr_inform() redacts it and honours gptr.quiet)
        if (length(interp) && verbosity() >= 2L) {
          gptr_inform(paste0("Interpolated prompt: ", prompt_text), "interpolated")
        }
      }
    }
  }
  if (isTRUE(sel$two)) {
    gptr_warn(c("gptr() got two unnamed strings: the first is the prompt, the second is context.",
                "Name the prompt (prompt = \"...\") to make this explicit."), "two_prompts")
  }
  e = substitute(model)
  id_model = if (ident_force_needed(e, "model", caller)) ident_value(model, "model", e) else
    resolve_identifier(e, "model", caller)
  e = substitute(mode)
  id_mode = if (ident_force_needed(e, "mode", caller)) ident_value(mode, "mode", e) else
    resolve_identifier(e, "mode", caller)
  e = substitute(skills)
  id_skills = if (ident_force_needed(e, "skills", caller)) ident_value(skills, "skills", e) else
    resolve_identifier(e, "skills", caller)
  e = substitute(plugins)
  id_plugins = if (ident_force_needed(e, "plugins", caller)) ident_value(plugins, "plugins", e) else
    resolve_identifier(e, "plugins", caller)
  e = substitute(extensions)
  id_ext = if (ident_force_needed(e, "extensions", caller)) {
    ident_value(extensions, "extensions", e)
  } else {
    resolve_identifier(e, "extensions", caller)
  }
  e = substitute(tools)
  id_tools = if (ident_force_needed(e, "tools", caller)) ident_value(tools, "tools", e) else
    resolve_identifier(e, "tools", caller)
  id_agents = resolve_agents(substitute(agents), caller)
  # an explicit `mode =` changes a continued session; a mode inherited from the running mode
  # (gateway_dispatch(), IC-53) only tightens the nested run (P06 run_new())
  args$mode_given = !is.null(id_mode)
  if (is.null(prompt_text) && !isTRUE(args$stdin) && !gptr_can_prompt()) {
    gptr_abort(c("gptr() without a prompt starts the interactive console and needs a human.",
                 paste("In scripts pass a prompt, gptr(\"...\"); to drive the console from piped",
                       "input use gptr(.stdin = TRUE).")),
               "noninteractive", what = "console", questions = character())
  }
  labels = dot_labels(exprs, nms)
  items = gateway_context_items(sel$context, kinds, sites, labels, facts, addrs)
  call = call_new(prompt = prompt_text, template = template, interp = interp, session = target,
                  context = items, values = values,
                  envir = unmask_env(if (env_given) envir else caller),
                  ids = list(model = id_model, mode = id_mode, skills = id_skills,
                             plugins = id_plugins, extensions = id_ext, tools = id_tools,
                             agents = id_agents),
                  args = args, sys_call = sc, nframe = nf)
  res = gateway_dispatch(call)
  if (isTRUE(res$visible)) res$value else invisible(res$value)
}, class = c("gptr_gateway", "function"))

#' Routes a call (contract 6.1.1 steps 5-6): route records in ascending `order`; the first whose
#' match() is TRUE runs; run() may return route_pass(). The call record is released on exit.
#' @noRd
gateway_dispatch = function(call) {
  on.exit(call_release(call), add = TRUE)
  cur = run_current()
  if (!is.null(cur)) call$ids$mode = mode_tighter(call$ids$mode %||% cur$mode, cur$mode)
  for (r in registry_all("route")) {
    if (!route_matches(r, call)) next
    ev_dispatch("route", ev_new("route", route = r$name, router = NULL,
                                model = gateway_model_label(call$ids$model), reason = "gateway"),
                session = call$session)
    res = withVisible(r$run(call))
    if (inherits(res$value, "gptr_route_pass")) next
    return(res)
  }
  if (is.null(call$prompt)) {
    gptr_abort(c("gptr() without a prompt opens the console, which is not loaded.",
                 "Pass a prompt, as in gptr(\"...\")."), "not_available",
               member = "route:console", provided_by = "builtin:console")
  }
  gptr_abort("No gateway route handled this call.", "internal", detail = "no route matched")
}

#' A route's match(); an error skips the route with a diagnostic. Both arguments are forced on
#' entry: the handler closure outlives this frame, and an unforced promise would keep the caller's
#' frame referenced (G3 fact-check cause 5)
#' @noRd
route_matches = function(route, call) {
  force(route)
  force(call)
  tryCatch(isTRUE(route$match(call)), error = function(e) {
    registry_diagnostic(paste0("route:", route$name), "route", "match_error", conditionMessage(e))
    FALSE
  })
}

#' A short label of the resolved model for the `route` event
#' @noRd
gateway_model_label = function(model) {
  if (is.null(model)) return(NA_character_)
  if (inherits(model, "gptr_spec")) return(as.character(model$id %||% model$name))
  as.character(model)[1L]
}

# ------------------------------------------------------------------ the gptr_gateway methods (5.3)

#' @export
`$.gptr_gateway` = function(x, name) ext_service_get("ns.resolve")(name)

#' @export
`[[.gptr_gateway` = function(x, i, ...) {
  check_string(i, "i")
  ext_service_get("ns.resolve")(i)
}

#' Refuses assignment into the gateway
#' @noRd
gateway_readonly = function(field) {
  gptr_abort(c("`gptr` is read-only.",
               paste("Add members by registering a tool:",
                     "gptr_register(gptr_tool(..., exposure = \"r\", namespace = \"<pkg>\")).")),
             "readonly", object = "gptr", field = as.character(field)[1L])
}

#' @export
`$<-.gptr_gateway` = function(x, name, value) gateway_readonly(name)

#' @export
`[[<-.gptr_gateway` = function(x, i, ..., value) gateway_readonly(i)

#' @exportS3Method utils::.DollarNames
.DollarNames.gptr_gateway = function(x, pattern = "") {
  if (!ext_service_has("ns.names")) return(character(0))
  ext_service_get("ns.names")(pattern)
}

#' @export
print.gptr_gateway = function(x, ...) {
  cat("<gptr gateway> gptr(\"prompt\", objects..., model =, mode =) runs an agent in this session",
      "members: gptr$<tab> (read, edit, write, grep, find, ls, ... when the tools are loaded)",
      sep = "\n")
  invisible(x)
}

# ------------------------------------------------------------------ routing helpers (7.8)

#' The sentinel a route's run() returns to let the next matching route handle the call
#' @noRd
route_pass = function() structure(list(), class = "gptr_route_pass")

#' Evaluates `expr_fun()` with deferral on: every gptr() call made meanwhile behaves as
#' `.run = FALSE` and returns its unstarted session (used by gptr_parallel(), P19)
#' @noRd
gateway_defer = function(expr_fun) {
  check_function(expr_fun, "expr_fun")
  st = gateway_state()
  st$defer = st$defer + 1L
  on.exit({
    st$defer = st$defer - 1L
  }, add = TRUE)
  expr_fun()
}

#' TRUE while gateway_defer() is active
#' @noRd
gateway_deferring = function() gateway_state()$defer > 0L

#' Address string of an environment for the pending-plan key [R2]: never a reference
#' @noRd
home_address = function(envir) {
  check_env(envir, "envir")
  rlang::obj_address(envir)
}

#' The strictest of two modes (plan < manual < edits < auto); NULL means "no constraint", and a
#' value that is not a mode never loosens the other (the name P06 reserved for P08; P06's own
#' helper is run_mode_tighter())
#' @noRd
mode_tighter = function(a, b) {
  if (is.null(a)) return(b)
  if (is.null(b)) return(a)
  modes = gateway_modes()
  ia = match(a, modes)
  ib = match(b, modes)
  if (is.na(ia)) return(b)
  if (is.na(ib)) return(a)
  if (ia <= ib) a else b
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'
```

Expected on the first run: `[ FAIL 0 | WARN 1 | SKIP 0 | PASS 74 ]`, the warning being testthat's "Adding new snapshot" for `print(gptr)`, which writes `tests/testthat/_snaps/gptr-gateway.md` with the two lines `<gptr gateway> gptr("prompt", objects..., model =, mode =) runs an agent in this session` and `members: gptr$<tab> (read, edit, write, grep, find, ls, ... when the tools are loaded)`. Run it again: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 74 ]` (testthat 3.3 counts the new snapshot as a pass on the first run, together with its warning; on CI, where `on_ci()` is true, a missing snapshot fails instead, so commit the `_snaps` file in this task). (Once P10 registers `ns.resolve`, the test "before the namespace services exist" skips.)

- [ ] **Step 5: Commit**

```bash
git add R/gptr-gateway.R tests/testthat/test-gptr-gateway.R tests/testthat/_snaps/gptr-gateway.md
git commit -m "feat(gateway): add the gptr() closure, route dispatch and its methods"
```

---

### Task 9: `gateway_run()`, terminal conditions, `builtin:gateway` and the `router.call` service

**Files:**
- Modify: `R/gptr-gateway.R` (append)
- Test: `tests/testthat/test-gptr-gateway.R` (append)

**Interfaces:**
- Consumes: Tasks 1-8 (including Task 7's `gateway_filters_sync()`); P01 `setting_get()`, `verbosity()`, `gptr_opt()` (`gptr.prompt_secrets`, owner P03, 04 §3.1), `gptr_can_prompt()`, `gptr_confirm(question, default = FALSE)`, `gptr_inform()`, `block_text()`, `block_image()`, `block_context()`, `msg_user(content, source = "prompt", timestamp = NULL)`, `msg_text()`, `ev_new()`, `project_root()`, `workspace_dir()`; P02 `registry_add(spec, source, rank, session = NULL, state = "active")`, `registry_remove(id)`, `registry_filters_set(filters, scope = c("session", "user", "project"))`, `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `gptr_hook(event, handler, matcher = NULL)` (the release hooks of `builtin:gateway`), `ev_dispatch()`; P03 `redact(x, profile = "persist")` (profile `context` for prompts); P04 `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_now()`, and in tests `reactor_timer(at, fn, run = NULL)` and `reactor_cancel(ids)`; P05 `model_resolve()`, `model_default(role = c("chat", "small", "system1"))`, `provider_get()`, `project_messages(entries, leaf, target)`; P06 `session_new(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL, opts = list())` (`parent` is the running session object), `session_data()`, `session_live()`, `session_home()`, `session_append()`, `session_set_model(s, ref, reason = "user")`, `session_set_mode(s, mode, source = "user")`, `session_enqueue(s, text, as, source, blocks)`, `run_start(s, input, opts = list())`, `run_wait(runs, timeout = Inf)`, `run_abort(run, reason = "user")`, `run_current()`, `live_all()`, `last_set(s)`, the `gptr_run` fields `id`, `session`, `status`, `mode`, `depth`, `opts`, `signal` and P06's `settled` flag (set by `run_settle()`), and the `.d` field `condition` (the unsignalled condition of the last terminal status, which P06 documents as read by P08); services `context.first`, `context.turn`, `session.add_tools` (P07), `skill.body`, `plugin.enable` (P17), `bg.register` (P21), `console.interrupt_policy` (P14).
- Produces (04 §7.8): `gateway_run(call, s = NULL)` (the default System 2 runner used by the `continue`, `new` and `nested` routes and by P13, P14, P15, P19), the `builtin:gateway` built-in (routes `nested` 20, `continue` 60, `new` 70; the core `setting` specs of Task 1), the `router.call` service `function(s, reason) list(model, thinking, state)` (IC-69, called by P06 before every request of a routed session), and the helpers `gateway_signal(s, run = NULL)`, `sdk_pump(runs, until = NULL, timeout = Inf)`, `run_foreground(run)`, `run_settled(run)`, `gateway_prompt_secrets(prompt)`, `call_hold(call, s)`, `gateway_release_held(sid)`, `gateway_control_other(s, what)`, `gateway_register_spec(spec, sid)`, `gateway_filters_apply(filters)`, `gateway_continue_envir(call, s)` and the pending run options (`gateway_pending_set()`, `gateway_pending_take()`, `gateway_pending_has()`) used by the SDK (Task 10).

`gateway_run()` is step 6 of contract 6.1.1 for System 2 calls. It first fixes the evaluation environment (a
continuation applies the IC-40 precedence: explicit `envir` > kept home > caller frame) and runs the IC-40
visibility check, so a hidden context symbol fails before anything changes. A new top-level session then settles
project trust (IC-52); every top-level call then applies the `filters` of the user and (trusted) project settings
files to the registry through Task 7's `gateway_filters_sync()` (04 §10.1; a no-op unless a file or the project
changed), so `"filters": ["-builtin:mcp"]` in `settings.json` holds after a restart; then `session_new()` with the resolved model reference (a provider spec's first
model, a registered provider's model, a router stored as `router:<name>` (IC-69), the settings default or
`model_default("chat")`), the mode (settings default `manual`; inside a run tightened to the running mode and made a
child of the running session with depth + 1, bounded by `gptr.subagents.max_depth`), the call's evaluation
environment as home (P06 keeps it only when it is not a function frame) and the call's rank-0 specs (a newer spec
of the same kind and name replaces the session's older one), extensions, plugins and filters (call-level filters
join the R-process filter layer, since P02 has no per-session scope; from model code they are a control-category
change). A continuation applies model and mode changes and new tools (`session.add_tools`). Both then set
`gptr_last()`, check egress (skipped for local/offline providers and `.opts$context = "none"`) and the replay
guard, apply `gptr.prompt_secrets` (04 §3.1, owner P03, applied here: a secret-looking value is replaced by a
`[secret:...]` marker with a notice under `"redact"`; under `"ask"` someone who can answer is asked first and a
no stops the call before anything is sent; P06 redacts at ingress anyway, so the original is never sent),
dispatch the `input` event (transform chain), build the user message from P07's context blocks, `skills =`
preloads, the prompt and `.opts$images`, and either queue it (`.run = FALSE`: the prompt waits in the session's
follow-up queue with its blocks, so `run_start(s, NULL, opts)` of any plan starts it, and the run options wait in
P08's pending store; status stays `idle`), start it
for the background pump (`bg.register`, P21), or run it to settlement under the interrupt policy
(`console.interrupt_policy` of P14, else abort-only) and signal the terminal status (contract 6.1.2) from the
condition P06 stored in `session_data(s)$condition`. A foreground run that the pause menu's `[b]ackground` hands
to P21 (`run$opts$background = TRUE`, 03 §6.2, 04 §7.14) ends the foreground wait as it does in P06's
`run_wait_foreground()`: `gptr()` then returns the still-running session invisibly and signals nothing. The call record is held past `gptr()` only for pending and
background runs, and released by `builtin:gateway`'s process-level `agent_end` and `session_shutdown` hooks when
the run settles, the session shuts down or it is garbage-collected [R2]. The `continue` route steers a running
session with the pipe as a user source (IC-55) and returns it invisibly at once; from model code it may steer only
the running session itself unless the gate approved a `gptr_steer` token (IC-53). `router.call` only chooses the
model (and checks egress and replay for it); P06's `run_route()` records each switch. A call with `parallel =` or `agents =` that reaches the built-in
routes (the `team` and `fanout` routes of P19, orders 15 and 16, are absent or filtered out) is refused with
`gptr_error_not_available` instead of silently running one session.

The tests below exercise the real routes on the fake provider; direct tools used in tests are registered with
`tools = list(<spec>)`, and runs that execute tools set `options(gptr.unsafe_no_permissions = TRUE)` because no
`mode` policy exists before P11 (the gate fails closed, IC-53).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-gateway.R`:

```r
# tests/testthat/test-gptr-gateway.R (Task 9: append)

# The text of every content block of a message, context blocks included
blocks_text = function(msg) {
  paste(vapply(msg$content, function(b) b$text %||% "", ""), collapse = "\n")
}

# A first-message context block listing the labels of the call's context objects (call$context)
local_labels_block = function(.env = parent.frame()) {
  off = gptr_register(gptr_spec(
    "context_block", "test_labels", placement = "first", authority = "data", budget = 300L,
    order = 650L,
    provide = function(ctx, budget) {
      labels = vapply(ctx$input$call$context, function(it) it$label, "")
      if (length(labels)) paste("labels:", paste(labels, collapse = ", ")) else NULL
    }))
  withr::defer(off(), envir = .env)
}

# A direct tool whose execute() runs `fun(ctx)` (tests only)
test_tool = function(name, fun) {
  gptr_tool(name, paste("Test tool", name),
            parameters = list(type = "object", properties = json_obj()),
            execute = function(input, ctx) fun(ctx))
}

test_that("builtin:gateway registers the routes nested, continue, new and the core settings", {
  routes = registry_all("route")
  nm = vapply(routes, function(r) r$name, "")
  expect_true(all(c("nested", "continue", "new") %in% nm))
  ord = vapply(routes, function(r) as.numeric(r$order), 0)
  expect_identical(unname(ord[match(c("nested", "continue", "new"), nm)]), c(20, 60, 70))
  expect_true(all(c("mode", "model", "budget", "egress") %in% registry_names("setting")))
})

test_that("with builtin:gateway loaded, P08's four services are served (IC-33, IC-34, IC-69)", {
  for (nm in c("settings.get", "trust.get", "identifier.resolve", "router.call")) {
    expect_true(ext_service_has(nm), label = nm)
  }
  local_gw()
  settings_write("session", list(preset = "minimal"))
  expect_identical(setting_get("preset"), "minimal")
  expect_identical(setting_get("no_such_key", default = 7L), 7L)
})

test_that("call-level filters join the session filter layer instead of replacing it", {
  local_gw()
  box = new.env()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$filters = filters
      box$scope = scope
      invisible(filters)
    })
  fake = local_fake_provider(list("ok"))
  settings_write("session", list(filters = "-builtin:checkpoints"))
  gptr("x", model = fake, plugins = "-builtin:mcp", envir = new.env())
  expect_identical(box$filters, c("-builtin:checkpoints", "-builtin:mcp"))
  expect_identical(box$scope, "session")
  expect_identical(settings_read("session")$filters, c("-builtin:checkpoints", "-builtin:mcp"))
  gptr("y", model = fake, plugins = "+builtin:mcp", envir = new.env())
  expect_identical(box$filters, c("-builtin:checkpoints", "+builtin:mcp"))
})

test_that("a top-level gptr() applies the filters of the user settings file (04 10.1)", {
  local_gw(workspace = FALSE)
  st = gateway_state()
  old = st$filters_applied
  withr::defer({
    st$filters_applied = old
  })
  st$filters_applied = NULL
  box = new.env()
  box$calls = list()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$calls = c(box$calls, list(list(filters = filters, scope = scope)))
      invisible(filters)
    })
  # as after a restart: the file holds filters that no gptr_config() call of this process set
  settings_file_write(settings_path("user", create = TRUE), list(filters = "-builtin:x"))
  fake = local_fake_provider(list("ok", "again"))
  gptr("x", model = fake, envir = new.env())
  expect_identical(box$calls, list(list(filters = "-builtin:x", scope = "user")))
  gptr("y", model = fake, envir = new.env())
  expect_length(box$calls, 1L)
})

test_that("a continuation's newer spec replaces the session's older spec of the same name", {
  local_gw()
  old = gptr_fake_provider(list("old answer"))
  new = gptr_fake_provider(list("new answer"))
  s = gptr("a", model = old, envir = new.env())
  s |> gptr("b", model = new)
  expect_identical(s$text, "new answer")
})

test_that("gptr('a', mice) and mice |> gptr('a') create sessions labelled mice", {
  local_gw()
  local_labels_block()
  fake = local_fake_provider(list("ok"))
  e = new.env()
  mice = data.frame(weight = c(20, 22, 25))
  s1 = gptr("a", mice, model = fake, envir = e)
  expect_s3_class(s1, "gptr_session")
  expect_identical(s1$text, "ok")
  s2 = mice |> gptr("a", model = fake, envir = e)
  expect_false(identical(s1, s2))
  expect_identical(gptr_last(), s2)
  req = fake_requests(fake)
  expect_length(req, 2L)
  for (r in req) expect_match(blocks_text(r$messages[[1L]]), "labels: mice", fixed = TRUE)
})

test_that("a pipe chain returns the same session and a model switch appends model_change", {
  local_gw()
  f1 = local_fake_provider(list("one", "two"), name = "fake1")
  f2 = local_fake_provider(list("three"), name = "fake2")
  local_gptr_options(model = "fake1/fake1-1")
  e = new.env()
  s = gptr("a", envir = e)
  r = s |> gptr("b") |> gptr("c", model = f2)
  expect_identical(r, s)
  expect_identical(s$turns, 3L)
  expect_identical(s$model, "fake2/fake2-1")
  expect_identical(s$text, "three")
  types = vapply(session_data(s)$entries, function(x) x$type, "")
  expect_true("model_change" %in% types)
})

test_that("a tool that pipes into its own running session enqueues a steer after the result", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  pipe_self = test_tool("pipe_self", function(ctx) {
    res = ctx$session |> gptr("use TPM")
    if (identical(res, ctx$session)) "piped" else "not piped"
  })
  fake = local_fake_provider(list(fake_tool("pipe_self"), "done"))
  s = gptr("normalise", model = fake, tools = list(pipe_self), envir = new.env())
  expect_identical(s$text, "done")
  msgs = s$messages
  roles = vapply(msgs, function(m) m$role, "")
  k = which(roles == "tool_result")
  expect_length(k, 1L)
  expect_identical(msg_text(msgs[[k]]), "piped")
  relay = msgs[[k + 1L]]
  expect_identical(relay$role, "operator")
  expect_identical(relay$kind, "steer_relay")
  expect_match(msg_text(relay), "The user sent this message while you were working: use TPM",
               fixed = TRUE)
})

test_that("a continuation evaluates in the kept home and fails fast on a hidden symbol (IC-40)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("start", model = fake, envir = globalenv())
  f = function(s, d) s |> gptr("filter d", d)
  cnd = expect_error(f(s, mtcars), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "d")
  g = function(s, d) s |> gptr("filter d", d, envir = environment())
  expect_identical(g(s, mtcars), s)
  expect_identical(s$turns, 2L)
})

test_that("a first remote use without an acknowledgement is refused, then replay guards", {
  local_gw()
  withr::local_envvar(GPTR_REPLAY = "replay")
  corp = gptr_provider("corp", api = "fake",
                       models = list(list(id = "corp-1", ref = "corp/corp-1")))
  expect_error(gptr("x", model = corp, envir = new.env()), class = "gptr_error_egress")
  expect_error(gptr("x", model = corp, envir = new.env(), .opts = list(context = "none")),
               class = "gptr_error_not_recorded")
})

test_that(".opts entries named by a plugin namespace reach ctx$input$opts (IC-44)", {
  local_gw()
  box = new.env()
  offs = list(
    gptr_register(gptr_spec("setting", "panel.size", default = 1L, description = "Panel size",
                            scope = "both", validate = function(value) as.integer(value))),
    gptr_register(gptr_spec("context_block", "test_panel", placement = "first",
                            authority = "data", budget = 300L, order = 650L,
                            provide = function(ctx, budget) {
                              box$panel = ctx$input$opts$panel
                              NULL
                            })))
  withr::defer(for (off in offs) off())
  fake = local_fake_provider(list("ok"))
  gptr("Review analysis.R", model = fake, envir = new.env(),
       .opts = list(panel = list(size = 3)))
  expect_identical(box$panel, list(size = 3L))
})

test_that("a secret-looking prompt is sent redacted, with a notice (gptr.prompt_secrets)", {
  local_gw(workspace = FALSE)
  local_gptr_options(quiet = FALSE)
  key = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
  txt = paste("Use the key", key, "for the API")
  fake = local_fake_provider(list("ok"))
  msgs = testthat::capture_messages(gptr(txt, model = fake, envir = new.env()))
  expect_true(any(grepl("replaced by a [secret:...] marker", msgs, fixed = TRUE)))
  expect_false(any(grepl(key, msgs, fixed = TRUE)))
  sent = blocks_text(fake_requests(fake)[[1L]]$messages[[1L]])
  expect_false(grepl(key, sent, fixed = TRUE))
  expect_match(sent, "[secret:anthropic-key]", fixed = TRUE)
})

test_that("gptr.prompt_secrets = \"ask\" asks first; a no sends nothing", {
  local_gw(workspace = FALSE)
  key = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
  txt = paste("Use the key", key, "for the API")
  box = new.env()
  box$answer = FALSE
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    box$default = default
    box$answer
  })
  local_gptr_options(prompt_secrets = "ask", interactive = TRUE)
  fake = local_fake_provider(list("ok"))
  cnd = expect_error(gptr(txt, model = fake, envir = new.env()),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "prompt")
  expect_false(grepl(key, conditionMessage(cnd), fixed = TRUE))
  expect_match(box$question, "secret-looking value", fixed = TRUE)
  expect_true(box$default)
  expect_length(fake_requests(fake), 0L)
  box$answer = TRUE
  s = gptr(txt, model = fake, envir = new.env())
  expect_identical(s$text, "ok")
  sent = blocks_text(fake_requests(fake)[[1L]]$messages[[1L]])
  expect_match(sent, "[secret:anthropic-key]", fixed = TRUE)
  # nobody to answer: "ask" behaves as "redact" (IC-43)
  box$question = NULL
  local_gptr_options(interactive = FALSE)
  fake2 = local_fake_provider(list("ok"), name = "fake2")
  gptr(txt, model = fake2, envir = new.env())
  expect_null(box$question)
  expect_length(fake_requests(fake2), 1L)
})

test_that("a provider failure signals gptr_error_provider carrying the session", {
  local_gw()
  fake = local_fake_provider(list(fake_error("bad request", status = 400L)))
  cnd = expect_error(gptr("x", model = fake, envir = new.env()), class = "gptr_error_provider")
  expect_s3_class(cnd$session, "gptr_session")
  expect_identical(cnd$session, gptr_last())
  expect_identical(cnd$session$status, "error")
})

test_that("the condition P06 stored is the one signalled, with the session attached", {
  local_gw()
  s = session_new("fake/fake-1", "manual", home = new.env())
  d = session_data(s)
  d$status = "error"
  d$condition = structure(class = c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error",
                                    "error", "condition"),
                          list(message = "429 after retries", call = NULL, provider = "fake",
                               session = d$id, retry_after = 30))
  cnd = expect_error(gateway_signal(s), class = "gptr_error_rate_limit")
  expect_identical(cnd$session, s)
  expect_identical(cnd$retry_after, 30)
})

test_that("gptr() leaves no connection open when it returns, errors or is interrupted (IC-59)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  n0 = nrow(showConnections())
  fake = local_fake_provider(list("ok", fake_error("bad request", status = 400L)))
  s = gptr("a", model = fake, envir = new.env())
  expect_error(s |> gptr("b"), class = "gptr_error_provider")
  expect_identical(nrow(showConnections()), n0)
  spin = test_tool("spin", function(ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "no"
  })
  fake2 = local_fake_provider(list(fake_tool("spin"), "never"), name = "spinner")
  res = tryCatch({
    gptr("go", model = fake2, tools = list(spin), envir = new.env())
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  expect_identical(gptr_last()$status, "aborted")
  expect_identical(nrow(showConnections()), n0)
})

test_that("model code may not pipe into another running session without approval (IC-53)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  other = gptr("x", model = fake, .run = FALSE, envir = new.env())
  d = session_data(other)
  d$status = "running"
  run = fake_run(session = "s9999999999")
  local_mocked_bindings(run_current = function() run)
  expect_error(other |> gptr("change course"), class = "gptr_error_permission")
  expect_length(d$queue$steer, 0L)
  run$signal$control = "gptr_steer"
  expect_identical(other |> gptr("change course"), other)
  expect_length(d$queue$steer, 1L)
  d$status = "idle"
})

test_that("a pending session collected without running releases its call record [R2]", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  sid = s$id
  call = get0(sid, envir = gateway_state()$pending, inherits = FALSE)$call
  expect_true(isTRUE(call$hold))
  rm(s)
  invisible(gptr("y", model = fake, envir = new.env()))
  invisible(gc())
  expect_false(isTRUE(call$hold))
  expect_null(call$envir)
  expect_false(gateway_pending_has(sid))
})

test_that("a run that reaches max_turns signals gptr_error_max_turns", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  again = test_tool("again", function(ctx) "again")
  fake = local_fake_provider(list(fake_tool("again")))
  cnd = expect_error(gptr("loop", model = fake, tools = list(again), envir = new.env(),
                          .opts = list(max_turns = 2L)), class = "gptr_error_max_turns")
  expect_identical(cnd$session$status, "max_turns")
})

test_that("blocked and budget statuses map to their conditions (contract 6.1.2)", {
  local_gw()
  s = session_new("fake/fake-1", "manual", home = new.env())
  d = session_data(s)
  d$status = "blocked"
  d$reason = "r: unlink('data')"
  cnd = expect_error(gateway_signal(s), class = "gptr_error_permission")
  expect_identical(cnd$session, s)
  d$status = "budget"
  session_append(s, list(type = "custom", custom_type = "gptr.budget",
                         data = list(kind = "cost", budget = 5, used = 5.2)))
  cnd = expect_error(gateway_signal(s), class = "gptr_error_budget_cost")
  expect_s3_class(cnd, "gptr_error_budget")
  expect_identical(cnd$used, 5.2)
  d$status = "idle"
  expect_invisible(gateway_signal(s))
})

test_that("the session is visible, invisible when streamed; .run = FALSE keeps the input", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  e = new.env()
  expect_visible(gptr("x", model = fake, envir = e))
  s = expect_invisible(gptr("later", model = fake, envir = e, .run = FALSE))
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 0L)
  expect_true(gateway_pending_has(s$id))
  queued = session_data(s)$queue$follow_up
  expect_length(queued, 1L)
  expect_identical(queued[[1L]]$text, "later")
  local_gptr_options(verbose = 2L)
  expect_invisible(gptr("x", model = fake, envir = e))
})

test_that("a gptr() call made during a run becomes a child session (route nested)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  sub = local_fake_provider(list("child answer"), name = "sub")
  box = new.env()
  spawn = test_tool("spawn", function(ctx) {
    box$child = gptr("sub task", model = sub, mode = auto)
    box$child$text
  })
  fake = local_fake_provider(list(fake_tool("spawn"), "parent done"), name = "main")
  s = gptr("delegate", model = fake, tools = list(spawn), envir = new.env(), mode = plan)
  child = box$child
  expect_identical(s$text, "parent done")
  expect_identical(session_data(child)$kind, "child")
  expect_identical(session_data(child)$parent_id, s$id)
  expect_identical(session_data(child)$depth, 1L)
  expect_identical(child$mode, "plan")
  expect_identical(child$text, "child answer")
})

test_that("a router model is stored as router:<name> and picks each request's model (IC-69)", {
  local_gw()
  local_fake_provider(list("routed"), name = "fake2")
  off = gptr_register(gptr_router("pick", route = function(request, ctx) "fake2/fake2-1"))
  withr::defer(off())
  s = gptr("x", model = pick, envir = new.env())
  expect_identical(session_data(s)$model, "router:pick")
  expect_identical(s$text, "routed")
  ents = session_data(s)$entries
  kinds = vapply(ents, function(x) if (identical(x$type, "custom")) x$custom_type else x$type, "")
  # one switch is recorded once (by P06's run_route(); router.call itself appends nothing)
  expect_identical(sum(kinds == "gptr.router"), 1L)
  mc = Filter(function(x) identical(x$type, "model_change"), ents)
  expect_length(mc, 1L)
  expect_identical(mc[[1L]]$gptr$reason, "router")
})

test_that("router.call returns the router's choice and appends nothing itself (IC-69)", {
  local_gw()
  local_fake_provider(list("x"), name = "fake2")
  off = gptr_register(gptr_router("keep", route = function(request, ctx) {
    list(model = "fake2/fake2-1", state = list(k = request$reason))
  }))
  withr::defer(off())
  s = session_new("router:keep", "manual", home = new.env())
  n = length(session_data(s)$entries)
  res = ext_service_get("router.call")(s, "turn")
  expect_identical(res$model, "fake2/fake2-1")
  expect_identical(res$state, list(k = "turn"))
  expect_length(session_data(s)$entries, n)
})

test_that("a failing router falls back to the default model", {
  local_gw()
  local_fake_provider(list("fallback"), name = "fake2")
  local_gptr_options(model = "fake2/fake2-1")
  off = gptr_register(gptr_router("broken", route = function(request, ctx) stop("no")))
  withr::defer(off())
  s = gptr("x", model = broken, envir = new.env())
  expect_identical(s$text, "fallback")
})

test_that("background = TRUE needs the bg.register service (P21)", {
  skip_if_not_installed("later")
  skip_if(ext_service_has("bg.register"), "P21 registers bg.register")
  local_gw()
  fake = local_fake_provider(list("ok"))
  expect_error(gptr("x", model = fake, envir = new.env(), background = TRUE),
               class = "gptr_error_not_available")
  expect_identical(gptr_last()$status, "idle")
})

test_that("a run sent to the background returns the session at once (pause menu [b]ackground)", {
  local_gw()
  fake = local_fake_provider(list(fake_text("a slow answer", chunk = 1L, gap = 0.05)))
  # what P21's bg.register does to a running foreground run when [b]ackground is chosen
  tid = reactor_timer(reactor_now() + 0.1, function() {
    for (x in live_all()) {
      r = session_live(x)$run
      if (!is.null(r)) r$opts$background = TRUE
    }
    NULL
  })
  withr::defer(reactor_cancel(tid))
  s = gptr("x", model = fake, envir = new.env())
  expect_identical(s$status, "running")
  run = session_live(s)$run
  expect_true(isTRUE(run$opts$background))
  run_wait(list(run), timeout = 10)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "a slow answer")
})

test_that(".opts$images sends image blocks with the first message (IC-44)", {
  local_gw()
  png = withr::local_tempfile(fileext = ".png")
  grDevices::png(png, width = 200, height = 200)
  graphics::plot.new()
  grDevices::dev.off()
  fake = local_fake_provider(list("a red square"))
  gptr("What is this?", model = fake, envir = new.env(), .opts = list(images = list(png)))
  first = fake_requests(fake)[[1L]]$messages[[1L]]
  types = vapply(first$content, function(b) b$type, "")
  expect_true("image" %in% types)
  img = first$content[[which(types == "image")[1L]]]
  expect_identical(img$mime, "image/png")
  expect_identical(img$source, "user")
})

test_that("the gateway emits route, model_select and input (contract 6.1.5)", {
  local_gw()
  seen = new.env()
  seen$events = character()
  hook = function(event, ctx) {
    seen$events = c(seen$events, event$type)
    NULL
  }
  offs = list(gptr_register(gptr_hook("route", hook)),
              gptr_register(gptr_hook("model_select", hook)),
              gptr_register(gptr_hook("input", hook)))
  withr::defer(for (off in offs) off())
  fake = local_fake_provider(list("ok"))
  gptr("x", model = fake, envir = new.env())
  expect_true(all(c("route", "model_select", "input") %in% seen$events))
})

test_that("parallel = and agents = need the sub-agent routes (P19)", {
  skip_if(!is.null(registry_get("route", "fanout")), "P19 registers the fanout route")
  local_gw()
  fake = local_fake_provider(list("ok"))
  cohorts = list(a = 1, b = 2)
  expect_error(gptr("Summarise", cohorts, model = fake, parallel = 2, envir = new.env()),
               class = "gptr_error_not_available")
  expect_error(gptr("Review", model = fake, envir = new.env(),
                    agents = list(stats = agent(description = "Statistics"))),
               class = "gptr_error_not_available")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'
```

Expected: the new tests fail: `builtin:gateway` registers no routes yet, so every `gptr()` call ends in `gptr_error_internal` ("No gateway route handled this call."), and `gateway_signal` / `gateway_pending_has` are not found.

- [ ] **Step 3: Write the implementation**

Append to `R/gptr-gateway.R`:

```r
# R/gptr-gateway.R (Task 9: append)

# ------------------------------------------------------------------ the default System 2 runner

#' A list view of an identifier value (NULL, a character vector, a spec, a function or a list)
#' @noRd
gateway_list = function(x) {
  if (is.null(x)) return(list())
  if (is.character(x)) return(as.list(x))
  if (inherits(x, "gptr_spec") || is.function(x)) return(list(x))
  if (is.list(x)) return(x)
  list(x)
}

#' The canonical model reference of a session: `provider/id[:thinking]`, or `router:<name>`
#' (IC-69). NULL means the settings default, then model_default("chat") (03 section 8.4).
#' @noRd
gateway_model_ref = function(model, thinking = NULL) {
  suffix = if (is.null(thinking)) "" else paste0(":", thinking)
  if (inherits(model, "gptr_router")) return(paste0("router:", model$name))
  if (inherits(model, "gptr_provider")) {
    m = model$models[[1L]]
    if (is.null(m)) {
      gptr_abort(paste0("The provider `", model$id, "` declares no model; pass model = \"",
                        model$id, "/<model id>\"."), "unknown_model", ref = model$id,
                 suggestions = character())
    }
    return(paste0(m$ref %||% paste0(model$id, "/", m$id), suffix))
  }
  if (is.null(model)) model = setting_get("model")
  if (is.null(model)) model = model_default("chat")
  if (is.null(model)) {
    gptr_abort(c("No model is configured and no provider key was found.",
                 "Load a key with gptr_env(), set gptr_config(model = ...), or pass model =."),
               "no_key", provider = NA_character_, variables = character())
  }
  if (!is.character(model) || length(model) != 1L) {
    gptr_abort("`model` must name one model.", "invalid_argument", arg = "model",
               expected = "one model name or spec")
  }
  if (!is.null(registry_get("router", model))) return(paste0("router:", model))
  base = sub(":.*$", "", model)
  if (is.null(thinking) && grepl(":", model, fixed = TRUE)) {
    suffix = paste0(":", sub("^[^:]*:", "", model))
  }
  pr = registry_get("provider", gateway_provider_id(base))
  if (!is.null(pr) && length(pr$models)) {
    id = if (grepl("/", base, fixed = TRUE)) sub("^[^/]*/", "", base) else pr$models[[1L]]$id
    for (m in pr$models) {
      if (identical(m$id, id)) return(paste0(m$ref %||% paste0(pr$id, "/", m$id), suffix))
    }
  }
  m = model_resolve(model, strict = TRUE)
  if (is.null(thinking) && !is.null(m$thinking)) suffix = paste0(":", m$thinking)
  paste0(m$ref, suffix)
}

#' The provider id of a canonical reference
#' @noRd
gateway_provider_id = function(ref) sub("/.*$", "", sub(":.*$", "", ref))

#' The provider record of a session's model, including the session's rank-0 records
#' @noRd
gateway_provider = function(s) {
  d = session_data(s)
  pid = gateway_provider_id(d$model)
  registry_get("provider", pid, session = d$id) %||% provider_get(pid)
}

#' The model record of a session's model (NULL when it cannot be found)
#' @noRd
gateway_model_record = function(s) {
  d = session_data(s)
  pr = gateway_provider(s)
  id = sub("^[^/]*/", "", sub(":.*$", "", d$model))
  if (!is.null(pr)) {
    for (m in pr$models) if (identical(m$id, id)) return(m)
  }
  model_resolve(sub(":.*$", "", d$model), strict = FALSE)
}

#' The preset asked for by the call (`.opts$preset`, or a preset name among `tools =`)
#' @noRd
gateway_preset = function(call) {
  p = call$args$opts$preset
  if (!is.null(p)) return(p)
  t = call$ids$tools
  if (is.character(t)) {
    hit = t[t %in% unique(c(gateway_presets(), registry_names("preset")))]
    if (length(hit)) return(hit[1L])
  }
  NULL
}

#' Tool modifiers for the preset: names and "+"/"-" modifiers, "+<name>" for rank-0 tool specs
#' @noRd
gateway_tool_mods = function(tools) {
  out = character()
  presets = unique(c(gateway_presets(), registry_names("preset")))
  for (t in gateway_list(tools)) {
    if (is.character(t) && !t %in% presets) out = c(out, t)
    if (inherits(t, "gptr_tool")) out = c(out, paste0("+", t$name))
  }
  out
}

#' The depth of a child session made during a run (gptr.subagents.max_depth, at most 2)
#' @noRd
gateway_child_depth = function(cur) {
  max_depth = min(as.integer(setting_get("subagents.max_depth", default = 1L)), 2L)
  depth = as.integer(cur$depth %||% 0L) + 1L
  if (depth > max_depth) {
    gptr_abort(paste0("gptr() calls made from model code may nest at most ", max_depth,
                      " level(s) deep (gptr.subagents.max_depth)."), "invalid_argument",
               arg = "depth", expected = paste("at most", max_depth, "nested levels"))
  }
  depth
}

#' The live session object with this id, or NULL
#' @noRd
gateway_session_by_id = function(id) {
  for (s in live_all()) if (identical(session_data(s)$id, id)) return(s)
  NULL
}

#' The factory in an extension file: its last expression must be function(gptr)
#' @noRd
gateway_extension_file = function(path) {
  exprs = parse(file = path, keep.source = FALSE, encoding = "UTF-8")
  env = new.env(parent = globalenv())
  value = NULL
  for (e in exprs) value = eval(e, env)
  if (!is.function(value)) {
    gptr_abort(paste0("The extension file ", path, " must end with a function(gptr) factory."),
               "invalid_argument", arg = "extensions",
               expected = "a file whose last expression is function(gptr)")
  }
  value
}

#' Registers one spec of a call at rank 0 for a session. A spec of the same kind and name that an
#' earlier call registered for the session is removed first: P02 keeps the first of two records
#' of equal rank (contract 10.1 "ties: the first registered"), so a continuation's newer spec
#' would otherwise be ignored. The ids are kept in `the$gateway$specs` until session_shutdown.
#' @noRd
gateway_register_spec = function(spec, sid) {
  st = gateway_state()
  ids = get0(sid, envir = st$specs, inherits = FALSE) %||% character()
  key = paste0(spec[["kind"]], ":", spec[["namespace"]] %||% "", "/", spec[["name"]])
  old = unname(ids[key])
  if (length(old) && !is.na(old)) registry_remove(old)
  ids[key] = registry_add(spec, source = "session", rank = 0L, session = sid)
  assign(sid, ids, envir = st$specs)
  invisible(ids[[key]])
}

#' Applies a call's registry filters (`plugins = "-builtin:x"`, `"+builtin:x"` to undo). P02 has
#' no per-session filter scope, so they join the R-process layer instead of replacing it: merged
#' into the session settings key `filters` (shown by gptr_config(), removed with
#' gptr_config(filters = NULL, .scope = "session")) and applied with registry_filters_set(scope =
#' "session"). From model code during a run this reconfigures gptr (IC-53 items 3-4): refused
#' unless approved.
#' @noRd
gateway_filters_apply = function(filters) {
  control_check("gptr_config")
  cur = as.character(unlist(settings_read("session")$filters))
  for (f in filters) {
    cur = cur[substring(cur, 2L) != substring(f, 2L)]
    cur = c(cur, f)
  }
  settings_write("session", list(filters = cur))
  registry_filters_set(cur, scope = "session")
  gptr_inform(paste0("The filters ", paste(filters, collapse = ", "), " apply to every later ",
                     "gptr() call of this R session; remove them with gptr_config(filters = NULL, ",
                     ".scope = \"session\")."), "notice",
              .once = paste0("call_filters:", paste(cur, collapse = ",")))
  invisible(cur)
}

#' Registers the call's specs at rank 0 for the session (providers, routers, tools, agents), loads
#' its extensions session-scoped, applies the call's registry filters and enables named plugins
#' (IC-69; contract 10.1)
#' @noRd
gateway_register = function(call, s) {
  id = session_data(s)$id
  specs = list()
  if (inherits(call$ids$model, "gptr_spec")) specs = c(specs, list(call$ids$model))
  for (t in gateway_list(call$ids$tools)) if (inherits(t, "gptr_spec")) specs = c(specs, list(t))
  for (a in call$ids$agents) specs = c(specs, list(a))
  for (sp in specs) gateway_register_spec(sp, id)
  for (ex in gateway_list(call$ids$extensions)) {
    if (is.function(ex)) {
      ext_load(ex, source = "session", rank = 0L, session = id)
    } else if (is.character(ex) && file.exists(ex)) {
      ext_load(gateway_extension_file(ex), source = "session", rank = 0L,
               dir = dirname(path_norm(ex)), session = id)
    } else if (is.character(ex)) {
      ext_service_get("plugin.enable")(ex, rank = 0L, session = id)
    }
  }
  pl = as.character(unlist(Filter(is.character, gateway_list(call$ids$plugins))))
  filters = pl[grepl("^[+-]", pl)]
  if (length(filters)) gateway_filters_apply(filters)
  enable = setdiff(pl, filters)
  if (length(enable)) {
    f = ext_service_get("plugin.enable")
    for (p in enable) f(p, rank = 0L, session = id)
  }
  invisible(specs)
}

#' Asks the project trust question once per process for a new top-level session (IC-52)
#' @noRd
gateway_trust_check = function() {
  root = project_root()
  if (!is.null(workspace_dir()) || trust_resources_present(root)) trust_resolve(root)
  invisible(TRUE)
}

#' Creates the session of a new call: resolved model and mode (tightened to the running mode
#' inside a run), the evaluation environment as home (P06 keeps it only when it is not a function
#' frame), kind `child` with depth + 1 and the running session as parent inside a run
#' @noRd
gateway_new_session = function(call, cur) {
  nested = !is.null(cur)
  ref = gateway_model_ref(call$ids$model, call$args$opts$thinking)
  mode = call$ids$mode %||% setting_get("mode", default = "manual")
  if (nested) mode = mode_tighter(mode, cur$mode)
  if (nested) gateway_child_depth(cur)
  parent = if (nested) gateway_session_by_id(cur$session) else NULL
  # P06's session_new() reads `thinking` from `opts` and derives the depth from `parent`
  # (gateway_child_depth() above only enforces gptr.subagents.max_depth); the tool modifiers,
  # `.opts$system` and the rest reach P06/P07 through `call$args$opts` and the run options
  # that gateway_run_opts() builds
  s = session_new(ref, mode, home = call$envir, kind = if (nested) "child" else "chat",
                  parent = parent, preset = gateway_preset(call),
                  opts = list(thinking = call$args$opts$thinking))
  gateway_register(call, s)
  ev_dispatch("model_select", ev_new("model_select", from = NULL, to = ref, reason = "gateway"),
              session = s)
  s
}

#' The IC-40 precedence for a continuation's evaluation environment: an explicit `envir =` (kept
#' in `call$envir`) > the session's kept home > the caller frame (already in `call$envir`)
#' @noRd
gateway_continue_envir = function(call, s) {
  if (!isTRUE(call$args$envir_given)) {
    home = session_home(s)
    if (!is.null(home)) call$envir = home
  }
  invisible(call)
}

#' Applies a continuation's changes: model changes, an explicit `mode =` (tightened to the
#' running mode inside a run, IC-53) and tools added through the session.add_tools service
#' (IC-69). A mode only inherited from the running mode is not written to the session: P06's
#' run_new() runs a nested run in the stricter of the two modes, and the user's session keeps its
#' own mode afterwards (IC-53 item 4).
#' @noRd
gateway_continue_session = function(call, s, cur) {
  d = session_data(s)
  before = registry_names("tool", session = d$id)
  gateway_register(call, s)
  if (!is.null(call$ids$model)) {
    ref = gateway_model_ref(call$ids$model, call$args$opts$thinking)
    if (!identical(ref, d$model)) session_set_model(s, ref, reason = "user")
  }
  mode = if (isTRUE(call$args$mode_given)) call$ids$mode else NULL
  if (!is.null(mode) && !is.null(cur)) mode = mode_tighter(mode, cur$mode)
  if (!is.null(mode) && !identical(mode, d$mode)) {
    session_set_mode(s, mode, source = if (is.null(cur)) "user" else "run")
  }
  added = setdiff(registry_names("tool", session = d$id), before)
  for (t in gateway_list(call$ids$tools)) {
    if (is.character(t) && startsWith(t, "-")) {
      gptr_inform(paste0("Tools cannot be removed from a running conversation (", t, "); start a ",
                         "new session to drop them."), "notice")
    } else if (is.character(t)) {
      added = c(added, sub("^[+]", "", t))
    } else if (inherits(t, "gptr_tool")) {
      added = c(added, t$name)
    }
  }
  specs = list()
  for (nm in unique(added)) {
    sp = registry_get("tool", nm, session = d$id)
    if (!is.null(sp)) specs = c(specs, list(sp))
  }
  if (length(specs)) ext_service_get("session.add_tools")(s, specs)
  invisible(s)
}

#' Fails fast when a context symbol is not the same object in the evaluation environment (IC-40).
#' A `while` loop: `env` may be a user frame, and a `for` loop calling closures with it pins the
#' frame (verified with tracemem: the wrapper f(big) copied `big` with a `for` loop here).
#' @noRd
gateway_check_visible = function(call) {
  env = call$envir
  items = call$context
  i = 0L
  while (i < length(items)) {
    i = i + 1L
    it = items[[i]]
    if (!identical(it$kind, "symbol")) next
    if (identical(binding_address(it$name, env), it$address)) next
    gptr_abort(c(paste0("`", it$name, "` is not visible from the environment this session ",
                        "evaluates in."),
                 paste0("Pass envir = the environment that holds `", it$name, "`, or pass it as ",
                        "a named value: gptr(..., ", it$name, " = force(", it$name, ")).")),
               "invalid_argument", arg = it$name,
               expected = "an object visible from the session's environment")
  }
  invisible(TRUE)
}

#' Egress acknowledgement and replay guard for the session's model (a router session is checked
#' per request by router_call())
#' @noRd
gateway_guards = function(call, s) {
  ref = session_data(s)$model
  if (startsWith(ref, "router:")) return(invisible(TRUE))
  pr = gateway_provider(s)
  context = call$args$opts$context %||% setting_get("context", default = "summary")
  local = !is.null(pr) && (isTRUE(pr$local) || isTRUE(pr$offline))
  if (!local && !identical(context, "none")) egress_check(gateway_provider_id(ref))
  replay_guard(if (is.null(pr)) ref else pr)
  invisible(TRUE)
}

#' <skill_content> preloads through the skill.body service (P17)
#' @noRd
gateway_skill_blocks = function(skills) {
  if (!length(skills)) return(list())
  body = ext_service_get("skill.body")
  out = list()
  for (nm in as.character(unlist(skills))) {
    b = body(nm)
    out = c(out, list(block_context("skill_content", b$text, attrs = list(name = nm))))
  }
  out
}

#' Base64 without line breaks
#' @noRd
gateway_b64 = function(raw) gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE)

#' Renders a ggplot or recordedplot to a PNG file at the gptr.plot_* size; restores the device
#' @noRd
gateway_render_png = function(x, file) {
  prev = grDevices::dev.cur()
  grDevices::png(file, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"),
                 res = gptr_opt("plot_res"))
  dev = grDevices::dev.cur()
  on.exit({
    grDevices::dev.off(dev)
    if (prev > 1L) grDevices::dev.set(prev)
  }, add = TRUE)
  if (inherits(x, "recordedplot")) grDevices::replayPlot(x) else print(x)
  invisible(file)
}

#' Image blocks for `.opts$images` (IC-44); the model must accept images
#' @noRd
gateway_image_blocks = function(images, s) {
  if (!length(images)) return(list())
  m = gateway_model_record(s)
  if (!is.null(m) && !is.null(m$input) && !"image" %in% m$input) {
    gptr_abort("`.opts$images` needs a model that accepts images.", "invalid_argument",
               arg = ".opts$images", expected = "a vision-capable model")
  }
  out = list()
  for (x in images) {
    if (is.character(x)) {
      ext = tolower(tools::file_ext(x))
      mime = switch(ext, png = "image/png", jpg = , jpeg = "image/jpeg", gif = "image/gif",
                    webp = "image/webp",
                    gptr_abort(paste0("Unsupported image type: ", x), "invalid_argument",
                               arg = ".opts$images", expected = "png, jpeg, gif or webp files"))
      raw = readBin(x, "raw", n = file.size(x))
      out = c(out, list(block_image(gateway_b64(raw), mime = mime, source = "user")))
    } else {
      f = tempfile(fileext = ".png")
      gateway_render_png(x, f)
      raw = readBin(f, "raw", n = file.size(f))
      unlink(f)
      out = c(out, list(block_image(gateway_b64(raw), mime = "image/png", source = "user",
                                    width = as.integer(gptr_opt("plot_width")),
                                    height = as.integer(gptr_opt("plot_height")))))
    }
  }
  out
}

#' Context blocks from P07's context.first / context.turn services (none when P07 is filtered out)
#' @noRd
gateway_context_blocks = function(s, inp, first) {
  name = if (first) "context.first" else "context.turn"
  if (!ext_service_has(name)) return(list())
  ext_service_get(name)(s, inp) %||% list()
}

#' Secret-looking text in a prompt (the option gptr.prompt_secrets of 04 3.1, which P03 documents
#' and leaves to the gateway): the prompt redacted with the `context` profile. P06 redacts every
#' entry at ingress anyway, so the original can never be sent; what the option chooses is how the
#' user hears of it: "redact" (the default, and "ask" when nobody can answer, IC-43) sends the
#' redacted prompt with a notice; "ask" asks first and, on no, stops the call before anything is
#' sent (gptr_error_invalid_argument, arg `prompt`, never the value).
#' @noRd
gateway_prompt_secrets = function(prompt) {
  if (is.null(prompt)) return(prompt)
  red = redact(prompt, "context")
  if (identical(red, prompt)) return(prompt)
  if (identical(gptr_opt("prompt_secrets"), "ask") && gptr_can_prompt()) {
    ok = isTRUE(gptr_confirm(paste0("The prompt contains a secret-looking value. Send it with the ",
                                    "value replaced by a [secret:...] marker?"), default = TRUE))
    if (!ok) {
      gptr_abort(c("Not sent: the prompt contains a secret-looking value.",
                   paste0("Load keys with gptr_env() and refer to them by name; model code ",
                          "reads them with Sys.getenv(\"NAME\").")),
                 "invalid_argument", arg = "prompt",
                 expected = "a prompt without secret values")
    }
    return(red)
  }
  gptr_inform(paste0("A secret-looking value in the prompt was replaced by a [secret:...] marker ",
                     "before sending (option gptr.prompt_secrets)."), "notice")
  red
}

#' The input of a turn: the `input` event (transform chain), context blocks, skill preloads, the
#' prompt and images. NULL when an `input` hook handled it. The prompt passes
#' gateway_prompt_secrets() first, so hooks and the provider see the redacted text.
#' @noRd
gateway_input = function(call, s, first, nested) {
  prompt = gateway_prompt_secrets(call$prompt)
  src = if (first) "prompt" else "pipe"
  ev = ev_dispatch("input", ev_new("input", text = prompt, source = src), session = s)
  if (is.list(ev)) {
    if (identical(ev$action, "handled")) return(NULL)
    if (identical(ev$action, "transform") && is.character(ev$text) && length(ev$text) == 1L) {
      prompt = as_utf8(ev$text)
    }
  }
  inp = list(call = call, turn = as.integer(session_data(s)$turns %||% 0L) + 1L, prompt = prompt,
             placement = if (first) "first" else "turn", last_hash = NULL,
             opts = call$args$opts %||% list())
  ctx = gateway_context_blocks(s, inp, first)
  skills = gateway_skill_blocks(call$ids$skills)
  images = gateway_image_blocks(call$args$opts$images, s)
  list(prompt = prompt, blocks = c(ctx, skills, images),
       content = c(ctx, skills, list(block_text(prompt)), images),
       source = if (nested) "parent" else if (first) "prompt" else "pipe")
}

#' Run options of contract 7.6 for this call
#' @noRd
gateway_run_opts = function(call, s, cur) {
  o = call$args$opts %||% list()
  d = session_data(s)
  ropts = list(max_turns = o$max_turns, budget = call$args$budget, doc = call$doc,
               returns = o$returns, context = o$context, timeout = o$timeout,
               interactive = gptr_can_prompt(), depth = as.integer(d$depth %||% 0L),
               parent_run = if (is.null(cur)) NULL else cur$id,
               agent = if (is.null(cur)) "main" else "nested",
               background = isTRUE(call$args$background), preset = gateway_preset(call),
               tools = gateway_tool_mods(call$ids$tools), call = call,
               root = if (is.null(cur)) d$id else (cur$opts$root %||% cur$session))
  ropts[!vapply(ropts, is.null, NA)]
}

# ------------------------------------------------------------------ pending runs (.run = FALSE)

#' Keeps the run options of a session built with `.run = FALSE` (its rendered input waits in the
#' session's follow-up queue) until gptr_step() or gptr_wait() starts it; keyed by session id in
#' `the$gateway$pending`. A run started elsewhere (P19, P21: `run_start(s, NULL, opts)`) uses its
#' own options, and the entry is dropped when that run settles (gateway_release_held()).
#' @noRd
gateway_pending_set = function(s, opts) {
  assign(session_data(s)$id, opts, envir = gateway_state()$pending)
  invisible(s)
}

#' Takes (and forgets) the pending run options of a session, or NULL
#' @noRd
gateway_pending_take = function(id) {
  st = gateway_state()
  v = get0(id, envir = st$pending, inherits = FALSE)
  if (!is.null(v)) rm(list = id, envir = st$pending)
  v
}

#' TRUE when a session has pending run options
#' @noRd
gateway_pending_has = function(id) exists(id, envir = gateway_state()$pending, inherits = FALSE)

#' Keeps a call record (and the frame in its `envir` binding) until the session's run settles or
#' the session shuts down [R2]: the record is listed under the session id in `the$gateway$held`,
#' and builtin:gateway's process-level `agent_end` and `session_shutdown` hooks
#' (gateway_release_hooks()) release it. Process-level hooks, so that no listener has to be
#' registered per session: both P06 events carry the session id (`event$session`), including the
#' `session_shutdown` that P06's finalizer dispatches when a pending session is collected.
#' @noRd
call_hold = function(call, s) {
  sid = session_data(s)$id
  call$hold = TRUE
  st = gateway_state()
  held = get0(sid, envir = st$held, inherits = FALSE) %||% list()
  assign(sid, c(held, list(call)), envir = st$held)
  invisible(call)
}

#' Releases every call record held for a session and forgets its pending run options [R2]
#' @noRd
gateway_release_held = function(sid) {
  if (!is.character(sid) || length(sid) != 1L || is.na(sid)) return(invisible(FALSE))
  st = gateway_state()
  held = get0(sid, envir = st$held, inherits = FALSE)
  if (!is.null(held)) {
    rm(list = sid, envir = st$held)
    k = 1L
    while (k <= length(held)) {
      held[[k]]$hold = FALSE
      call_release(held[[k]])
      k = k + 1L
    }
  }
  if (exists(sid, envir = st$pending, inherits = FALSE)) rm(list = sid, envir = st$pending)
  invisible(TRUE)
}

#' builtin:gateway's process-level hooks that release held call records when a run settles
#' (`agent_end`) or a session shuts down, is collected or the package unloads
#' (`session_shutdown`, which also forgets the ids of the session's rank-0 records: P02 drops the
#' records themselves); both payloads carry the session id as `event$session`
#' @noRd
gateway_release_hooks = function() {
  settled = function(event, ctx) {
    gateway_release_held(event$session)
    NULL
  }
  shutdown = function(event, ctx) {
    sid = event$session
    gateway_release_held(sid)
    st = gateway_state()
    if (is.character(sid) && length(sid) == 1L && !is.na(sid) &&
        exists(sid, envir = st$specs, inherits = FALSE)) {
      rm(list = sid, envir = st$specs)
    }
    NULL
  }
  list(gptr_hook("agent_end", settled), gptr_hook("session_shutdown", shutdown))
}

#' The default System 2 runner (contract 7.8) used by the `continue`, `new` and `nested` routes
#' and by other plans' routes: creates or continues the session, checks egress and replay, builds
#' the input, then queues it (`.run = FALSE`), starts it in the background, or runs it to
#' settlement under the interrupt policy and maps a terminal status to its condition
#' @noRd
gateway_run = function(call, s = NULL) {
  cur = run_current()
  first = is.null(s)
  nested = first && !is.null(cur)
  # IC-40 fails fast: the evaluation environment is fixed and checked before anything changes
  # (no session created, no spec registered, no model or mode switched)
  if (!first) gateway_continue_envir(call, s)
  gateway_check_visible(call)
  if (first && is.null(cur)) gateway_trust_check()
  # the `filters` of the user and (trusted) project settings files reach the registry before the
  # session is built (04 10.1; P02 item 18); a no-op unless a file or the project changed
  if (is.null(cur)) gateway_filters_sync()
  if (first) {
    s = gateway_new_session(call, cur)
  } else {
    gateway_continue_session(call, s, cur)
  }
  if (is.null(cur)) last_set(s)
  gateway_guards(call, s)
  input = gateway_input(call, s, first, nested)
  if (is.null(input)) return(invisible(s))
  ropts = gateway_run_opts(call, s, cur)
  msg = msg_user(input$content, source = input$source)
  if (!isTRUE(call$args$run)) {
    session_enqueue(s, input$prompt, as = "follow_up", source = "api_user",
                    blocks = input$blocks)
    call_hold(call, s)
    gateway_pending_set(s, ropts)
    return(invisible(s))
  }
  if (isTRUE(call$args$background)) {
    if (!requireNamespace("later", quietly = TRUE)) {
      gptr_abort("background = TRUE needs the later package.", "missing_package",
                 package = "later", feature = "background sessions")
    }
    register = ext_service_get("bg.register")
    call_hold(call, s)
    run_start(s, msg, ropts)
    register(s)
    return(invisible(s))
  }
  run = run_start(s, msg, ropts)
  run_foreground(run)
  # the pause menu's [b]ackground (03 6.2, 04 7.14): P21's bg.register marked the run
  # `opts$background`, so the call returns the session now and the run goes on under the
  # background pump; the record is held until the run settles [R2]
  if (!run_settled(run) && isTRUE(run$opts$background)) {
    call_hold(call, s)
    return(invisible(s))
  }
  gateway_signal(s, run)
  if (verbosity() >= 2L) invisible(s) else s
}

# ------------------------------------------------------------------ pumping runs (6.1.1 step 6)

#' TRUE once a run settled: P06's run_settle() sets `run$settled` and a terminal status (04 7.6:
#' the active statuses, then a terminal one). A run parked with status `waiting` by P21 is not
#' settled, so "not an active status" would mislead.
#' @noRd
run_settled = function(run) {
  if (is.null(run) || isTRUE(run$settled)) return(TRUE)
  terminal = c("idle", "blocked", "budget", "max_turns", "error", "aborted", "interrupted",
               "detached")
  isTRUE(run$status %in% terminal)
}

#' Aborts every unsettled run (the abort-only interrupt fallback)
#' @noRd
sdk_abort_all = function(runs) {
  for (r in runs) if (!run_settled(r)) run_abort(r, reason = "interrupt")
  invisible(NULL)
}

#' The blocking work of a pump: run_wait() for whole runs, else reactor_pump() until `until()`
#' (allow_runs limited to these runs inside another run, IC-57)
#' @noRd
sdk_work = function(runs, until, timeout) {
  force(runs)
  force(until)
  force(timeout)
  if (is.null(until)) return(function() run_wait(runs, timeout = timeout))
  allow = if (is.null(run_current())) NULL else vapply(runs, function(r) r$id, "")
  function() reactor_pump(until = until, slice_ms = 100L, allow_runs = allow, timeout = timeout)
}

#' Pumps runs under the console.interrupt_policy service (P14) when it is registered, else
#' abort-only: an interrupt aborts the runs (the partial turn is recorded) and propagates
#' unchanged (03 section 6.2)
#' @noRd
sdk_pump = function(runs, until = NULL, timeout = Inf) {
  work = sdk_work(runs, until, timeout)
  if (ext_service_has("console.interrupt_policy")) {
    return(invisible(ext_service_get("console.interrupt_policy")(work, runs, mode = "call")))
  }
  done = FALSE
  on.exit(if (!done) sdk_abort_all(runs), add = TRUE)
  out = work()
  done = TRUE
  invisible(out)
}

#' Runs one run in the foreground until it settles or is sent to the background: the pause
#' menu's [b]ackground makes P21 set `run$opts$background`, which ends the wait here as it ends
#' P06's run_wait_foreground() (03 6.2, 04 7.14)
#' @noRd
run_foreground = function(run) {
  force(run)
  sdk_pump(list(run), until = function() run_settled(run) || isTRUE(run$opts$background))
}

# ------------------------------------------------------------------ terminal statuses (6.1.2)

#' The last entry of a custom type on the session, or NULL
#' @noRd
gateway_last_custom = function(d, type) {
  for (e in rev(d$entries)) {
    if (identical(e$type, "custom") && identical(e$custom_type, type)) return(e$data)
  }
  NULL
}

#' The last failed assistant message, or NULL
#' @noRd
gateway_last_error = function(d) {
  for (e in rev(d$entries)) {
    m = e$message
    if (identical(e$type, "message") && identical(m$role, "assistant") &&
        identical(m$stop_reason, "error")) return(m)
  }
  NULL
}

#' Signals the condition of a terminal status (contract 6.1.2) with the session attached as
#' `$session`: the condition P06 stored unsignalled in `session_data(s)$condition` at settlement
#' (it keeps the precise class, e.g. gptr_error_rate_limit, and the fields status, request_id,
#' retry_after; a blocked `ask` stores gptr_error_noninteractive, IC-68), else one built from the
#' session's status and transcript. `run` is accepted for the run's max_turns.
#' @noRd
gateway_signal = function(s, run = NULL) {
  d = session_data(s)
  st = d$status
  if (!st %in% c("error", "blocked", "budget", "max_turns")) return(invisible(s))
  cnd = d$condition
  if (inherits(cnd, "condition")) {
    cnd$session = s
    stop(cnd)
  }
  reason = d$reason %||% st
  if (identical(st, "error")) {
    m = gateway_last_error(d)
    gptr_abort(c(paste0("The model call failed: ", m$error_message %||% reason),
                 "The session is attached as $session and is gptr_last()."),
               "provider", provider = m$provider %||% NA_character_,
               model = m$model %||% NA_character_, status = NA_integer_,
               request_id = m$request_id %||% NA_character_,
               error_type = m$raw_stop_reason %||% NA_character_, session = s)
  }
  if (identical(st, "blocked")) {
    gptr_abort(c(paste0("The run stopped because an action needs approval and nobody can answer: ",
                        reason),
                 paste("Allow it with mode = auto, a rule such as",
                       "gptr_permissions(allow = \"r(level<=1)\"), or run interactively.")),
               "permission", action = reason, tool = NA_character_, risk = NA_integer_,
               how_to_allow = paste("mode = auto, gptr_permissions(allow = ...),",
                                    "or an interactive session"),
               session = s)
  }
  if (identical(st, "budget")) {
    b = gateway_last_custom(d, "gptr.budget")
    kind = b$kind %||% "tokens"
    gptr_abort(paste0("The run stopped at its ", kind, " budget."),
               c(paste0("budget_", kind), "budget"), kind = kind, budget = b$budget,
               used = b$used, session = s)
  }
  mt = if (is.null(run)) d$max_turns else (run$opts$max_turns %||% d$max_turns)
  gptr_abort(paste0("The run stopped after its maximum number of turns (", mt %||% "?", ")."),
             "max_turns", max_turns = mt, session = s)
}

# ------------------------------------------------------------------ built-in routes (IC-24, IC-39)

#' Refuses a verb or pipe from model code that acts on a session other than the running one,
#' unless the dispatcher approved it (IC-53 item 3: gptr_steer()/gptr_cancel() and the pipe into
#' another running session are control-category actions)
#' @noRd
gateway_control_other = function(s, what) {
  cur = run_current()
  if (is.null(cur) || identical(cur$session, session_data(s)$id)) return(invisible(TRUE))
  control_check(what)
}

#' The `continue` route: a running (or waiting) session is steered with the pipe as a user source
#' (IC-55; the text redacted with the `context` profile through gateway_prompt_secrets(), which
#' applies gptr.prompt_secrets; from model code only the running session
#' itself, else an approved gptr_steer, IC-53); any other status continues with a turn
#' @noRd
route_continue = function(call) {
  route_needs_subagents(call)
  s = call$session
  if (session_data(s)$status %in% c("running", "waiting")) {
    gateway_control_other(s, "gptr_steer")
    session_enqueue(s, gateway_prompt_secrets(call$prompt), as = "steer", source = "pipe")
    return(invisible(s))
  }
  gateway_run(call, s)
}

#' Refuses, in the built-in routes, a call that only the sub-agent routes `team` (15) and `fanout`
#' (16) can serve: they run first when builtin:subagents (P19) is loaded, so reaching here means
#' it is absent or filtered out
#' @noRd
route_needs_subagents = function(call) {
  if (!is.null(call$args$parallel)) {
    gptr_abort("`parallel =` needs the fan-out route of builtin:subagents, which is not loaded.",
               "not_available", member = "route:fanout", provided_by = "builtin:subagents")
  }
  if (length(call$ids$agents)) {
    gptr_abort("`agents =` needs the team route of builtin:subagents, which is not loaded.",
               "not_available", member = "route:team", provided_by = "builtin:subagents")
  }
  invisible(TRUE)
}

#' The route specs of builtin:gateway: nested (20), continue (60), new (70)
#' @noRd
gateway_routes = function() {
  list(
    gptr_spec("route", "nested", order = 20,
              description = "A gptr() call made while a run is active becomes a child session.",
              match = function(call) {
                !is.null(run_current()) && is.null(call$session) && !is.null(call$prompt)
              },
              run = function(call) {
                route_needs_subagents(call)
                gateway_run(call, NULL)
              }),
    gptr_spec("route", "continue", order = 60,
              description = "A piped session is steered when running, else continued.",
              match = function(call) !is.null(call$session) && !is.null(call$prompt),
              run = route_continue),
    gptr_spec("route", "new", order = 70,
              description = "Any other call with a prompt starts a new session.",
              match = function(call) !is.null(call$prompt),
              run = function(call) {
                route_needs_subagents(call)
                gateway_run(call, NULL)
              }))
}

#' builtin:gateway: the routes nested, continue, new and the core setting specs (IC-24), plus the
#' two process-level hooks that release held call records [R2]
#' @noRd
builtin_gateway = function(gptr) {
  for (sp in gateway_routes()) gptr$register(sp)
  for (sp in gateway_setting_specs()) gptr$register(sp)
  for (sp in gateway_release_hooks()) gptr$register(sp)
  invisible(NULL)
}

on_load(ext_declare_builtin("gateway", builtin_gateway, replaceable = FALSE))

# ------------------------------------------------------------------ routers (IC-69)

#' The branch of a session, leaf first
#' @noRd
gateway_branch = function(d) {
  out = list()
  id = d$leaf
  while (!is.null(id)) {
    pos = get0(id, envir = d$index, inherits = FALSE)
    if (is.null(pos)) break
    e = d$entries[[pos]]
    out = c(out, list(e))
    id = e$parent_id
  }
  out
}

#' Text of the last user message on the branch
#' @noRd
gateway_last_prompt = function(d) {
  for (e in gateway_branch(d)) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      return(msg_text(e$message))
    }
  }
  NA_character_
}

#' Calls a router within its timeout; NULL (with a diagnostic) on error, timeout or a bad result.
#' setTimeLimit() cannot be read back and must be reset to Inf afterwards (report 12: limits are
#' soft and a leftover limit kills the next request), and that reset would also clear the limit
#' P09 arms around each top-level expression of an `r` evaluation. So the limit is armed only
#' outside tool evaluations (`run_current()` is NULL); a nested routed session (a gptr() call in
#' an `r` evaluation) gets a soft timeout: a router that took longer counts as failed.
#' @noRd
router_invoke = function(spec, request, ctx) {
  timeout = as.numeric(spec$timeout %||% 2)
  armed = is.null(run_current())
  t0 = reactor_now()
  if (armed) {
    setTimeLimit(elapsed = timeout, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf, transient = FALSE), add = TRUE)
  }
  out = tryCatch(spec$route(request, ctx), error = function(e) e)
  if (armed) setTimeLimit(elapsed = Inf, transient = FALSE)
  if (!inherits(out, "error") && reactor_now() - t0 > timeout) {
    out = simpleError(paste0("the router took longer than its timeout of ", timeout, " s"))
  }
  src = paste0("router:", spec$name)
  if (inherits(out, "error")) {
    registry_diagnostic(src, "router", "error", conditionMessage(out))
    return(NULL)
  }
  if (is.character(out) && length(out) == 1L && !is.na(out)) {
    return(list(model = out, thinking = NULL, state = NULL))
  }
  if (is.list(out) && is.character(out$model) && length(out$model) == 1L) {
    return(list(model = out$model, thinking = out$thinking, state = out$state))
  }
  registry_diagnostic(src, "router", "invalid_result",
                      "the router returned neither a model reference nor list(model = ...)")
  NULL
}

#' Egress acknowledgement and replay guard for the provider of a router's chosen model
#' @noRd
router_guards = function(m, sid) {
  pr = registry_get("provider", m$provider, session = sid) %||% provider_get(m$provider)
  if (!isTRUE(pr$local) && !isTRUE(pr$offline)) egress_check(m$provider)
  replay_guard(pr %||% m)
  invisible(TRUE)
}

#' Falls back to the default model after a router failure, with a diagnostic; the router's last
#' state is kept. The `route` event and the `model_change`/`gptr.router` entries of the switch are
#' P06's (run_route()), like those of every other switch.
#' @noRd
router_fallback = function(s, name, why, state = NULL) {
  registry_diagnostic(paste0("router:", name), "router", "fallback", why)
  ref = model_default("chat")
  if (is.null(ref)) {
    gptr_abort(paste0("The router `", name, "` failed (", why, ") and no default model is set."),
               "no_key", provider = NA_character_, variables = character())
  }
  sid = session_data(s)$id
  m = router_model(ref, sid)
  if (is.null(m)) {
    gptr_abort(paste0("The router `", name, "` failed (", why, ") and the default model `", ref,
                      "` is unknown."), "unknown_model", ref = ref, suggestions = character())
  }
  router_guards(m, sid)
  list(model = m$ref, thinking = m$thinking, state = state)
}

#' The model record a router chose: a provider registered for the session (rank 0 included) by
#' its first model, else the catalog; NULL when unknown
#' @noRd
router_model = function(ref, sid) {
  base = sub(":.*$", "", ref)
  thinking = if (grepl(":", ref, fixed = TRUE)) sub("^.*:", "", ref) else NULL
  pid = gateway_provider_id(base)
  pr = registry_get("provider", pid, session = sid)
  if (!is.null(pr) && length(pr$models)) {
    id = sub("^[^/]*/", "", base)
    for (m in pr$models) {
      if (identical(m$id, id) || !grepl("/", base, fixed = TRUE)) {
        m$ref = m$ref %||% paste0(pr$id, "/", m$id)
        m$provider = pr$id
        m$thinking = thinking
        return(m)
      }
    }
  }
  model_resolve(ref, strict = FALSE)
}

#' The `router.call` service (IC-69): picks the model of the next request of a session whose model
#' is `router:<name>` and returns `list(model, thinking, state)`. It builds the router's request
#' (the state and model of the branch's last `gptr.router` entry), calls the router within its
#' timeout and checks egress and replay for the chosen provider. It appends nothing and emits
#' nothing: P06's run_route() appends `model_change` (reason router) and `gptr.router` and emits
#' `route` for each switch, so doing it here too would record every switch twice.
#' @noRd
router_call = function(s, reason = "turn") {
  d = session_data(s)
  name = sub("^router:", "", d$model)
  spec = registry_get("router", name, session = d$id)
  if (is.null(spec)) return(router_fallback(s, name, "the router is not registered"))
  last = NULL
  for (e in gateway_branch(d)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.router")) {
      last = e$data
      break
    }
  }
  previous = last$model
  target = if (is.null(previous)) NULL else router_model(previous, d$id)
  messages = if (is.null(target)) list() else project_messages(d$entries, d$leaf, target)
  request = list(prompt = gateway_last_prompt(d), messages = messages, state = last$state,
                 previous = previous, reason = reason, session = s)
  out = router_invoke(spec, request, session_live(s)$ctx)
  if (is.null(out)) return(router_fallback(s, name, "the router failed", last$state))
  m = router_model(out$model, d$id)
  if (is.null(m)) {
    return(router_fallback(s, name, "the router chose an unknown model", last$state))
  }
  router_guards(m, d$id)
  list(model = m$ref, thinking = out$thinking %||% m$thinking, state = out$state)
}

on_load(ext_service_set("router.call", router_call, provided_by = "P08", builtin = "gateway"))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 192 ]` with later installed (without later, or once P21 registers `bg.register`, the `background` test skips: `SKIP 1 | PASS 190`).

- [ ] **Step 5: Commit**

```bash
git add R/gptr-gateway.R tests/testthat/test-gptr-gateway.R
git commit -m "feat(gateway): add gateway_run(), the built-in routes and the router.call service"
```

---

### Task 10: The session SDK verbs

**Files:**
- Create: `R/gptr-sdk.R`
- Test: `tests/testthat/test-gptr-sdk.R` (create)

**Interfaces:**
- Consumes: Tasks 5 and 9 (`call_new()`, `unmask_env()`, `ident_label()`, `call_hold()`, `gateway_pending_take()`, `gateway_session_by_id()`, `sdk_pump()`, `run_settled()`, `gateway_signal()`, `gateway_control_other()`), Tasks 1 and 4 (`control_check()`, `replay_mode()`); P01 checkers, `as_utf8()`, `gptr_inform()`; P02 `hook_add()` (validates event names: Claude/Codex names are `gptr_error_invalid_argument` with a hint), `hook_remove()`; P03 `redact(x, profile)`; P06 `session_live()`, `session_data()`, `session_home()`, `session_enqueue()`, `session_value_set(s, label, value, name = NULL, forced_home = NULL)`, `run_start()`, `run_abort()`, `run_current()`.
- Produces the exports of 04 §6.5-6.6: `gptr_step(s, turns = 1L)`, `gptr_wait(x, timeout = Inf)`, `gptr_steer(s, text, as = c("steer", "follow_up"))`, `gptr_cancel(x)`, `gptr_on(s, event, handler, matcher = NULL)`, `gptr_return(x)`; P14 (pause menu), P19 and P21 call `gptr_steer()`, `gptr_wait()` and `gptr_cancel()`.

Every verb takes the session first, so it composes with `|>`, and needs no internals beyond the kernel SDK (G1
§4.6). `gptr_step()` and `gptr_wait()` start a session's queued input (`run_start(s, NULL, opts)`: the run takes
the queue, which holds the rendered prompt of a `.run = FALSE` call, then steers and follow-ups) with the pending run
options of that call (Task 9), then pump: `gptr_step()` until `turns` `turn_end` events or
settlement, `gptr_wait()` until no session is `running` or `waiting` (P21 resumes `waiting` sessions from any
blocking pump) or the timeout; a single settled session signals its terminal condition. `gptr_steer()` redacts the
text with the `context` profile and enqueues it with source `api_user` (IC-55; P06 refuses a call from model code
of the same session tree). IC-53: `gptr_on()` always, and `gptr_steer()`/`gptr_cancel()` on a session other than
the running one, are control-category calls. `gptr_return()` outside a run returns `invisible(x)` with a
once-per-session notice that is silent in replay mode (IC-48); inside a run it passes the value and its expression
to `session_value_set()`, which applies the value policy of 03 §5.1.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-gptr-sdk.R`:

```r
# tests/testthat/test-gptr-sdk.R (Task 10: create)
# test-gptr-sdk.R -- the session SDK verbs on the fake provider (plan P08).

# A temporary project with a private user config directory; the process settings layer is
# restored when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A stand-in for the run that run_current() returns while model code runs.
fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

# A direct tool whose execute() runs `fun(ctx)` (tests only)
test_tool = function(name, fun) {
  gptr_tool(name, paste("Test tool", name),
            parameters = list(type = "object", properties = json_obj()),
            execute = function(input, ctx) fun(ctx))
}

test_that("gptr_step() starts a pending session; with nothing queued it is a no-op", {
  local_gw()
  fake = local_fake_provider(list("Plan: ..."))
  s = gptr("Plan the analysis", model = fake, .run = FALSE, envir = new.env())
  expect_identical(s$turns, 0L)
  expect_invisible(gptr_step(s))
  expect_identical(s$turns, 1L)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "Plan: ...")
  expect_false(gateway_pending_has(s$id))
  expect_invisible(gptr_step(s))
  expect_identical(s |> gptr_step(), s)
  expect_identical(s$turns, 1L)
  expect_length(fake_requests(fake), 1L)
})

test_that("gptr_step(turns = 1) stops after one turn; turns = Inf runs to settlement", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  noop = test_tool("noop", function(ctx) "ok")
  fake = local_fake_provider(list(fake_tool("noop"), fake_tool("noop"), "done"))
  s = gptr("go", model = fake, tools = list(noop), .run = FALSE, envir = new.env())
  gptr_step(s, turns = 1L)
  expect_identical(s$turns, 1L)
  expect_identical(s$status, "running")
  gptr_step(s, turns = Inf)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "done")
})

test_that("the call record of a pending session is held until its run settles [R2]", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  call = get0(s$id, envir = gateway_state()$pending, inherits = FALSE)$call
  expect_true(isTRUE(call$hold))
  expect_true(is.environment(call$envir))
  gptr_step(s)
  expect_false(isTRUE(call$hold))
  expect_null(call$envir)
})

test_that("gptr_wait() starts queued sessions and waits for all of them", {
  local_gw()
  fake = local_fake_provider(list("a"))
  runs = list(a = gptr("one", model = fake, .run = FALSE, envir = new.env()),
              b = gptr("two", model = fake, .run = FALSE, envir = new.env()))
  expect_invisible(gptr_wait(runs, timeout = 10))
  expect_identical(vapply(runs, function(x) x$status, ""), c(a = "idle", b = "idle"))
  expect_identical(vapply(runs, function(x) x$turns, 0L), c(a = 1L, b = 1L))
})

test_that("gptr_wait() on one failed session signals its condition", {
  local_gw()
  fake = local_fake_provider(list(fake_error("bad request", status = 400L)))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  cnd = expect_error(gptr_wait(s), class = "gptr_error_provider")
  expect_identical(cnd$session, s)
})

test_that("gptr_wait() returns at the timeout; gptr_cancel() then aborts the run", {
  local_gw()
  fake = local_fake_provider(list(list(hang = TRUE)))
  s = gptr("long task", model = fake, .run = FALSE, envir = new.env())
  expect_invisible(gptr_cancel(s))
  expect_identical(s$status, "idle")
  gptr_wait(s, timeout = 0.2)
  expect_identical(s$status, "running")
  expect_invisible(gptr_cancel(s))
  expect_identical(s$status, "aborted")
})

test_that("gptr_steer() queues a follow-up delivered when the agent would stop", {
  local_gw()
  fake = local_fake_provider(list("first", "second"))
  s = gptr("Summarise mtcars", model = fake, .run = FALSE, envir = new.env())
  expect_invisible(gptr_steer(s, "Use only the mpg column", as = "follow_up"))
  gptr_wait(s)
  users = Filter(function(m) identical(m$role, "user"), s$messages)
  expect_identical(vapply(users, msg_text, ""), c("Summarise mtcars", "Use only the mpg column"))
  expect_identical(s$text, "second")
})

test_that("gptr_steer() redacts with the context profile and queues an api_user item", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  box = new.env()
  local_mocked_bindings(redact = function(x, profile = "persist") {
    box$profile = profile
    "[redacted]"
  })
  gptr_steer(s, "the key is sk-test-123", as = "follow_up")
  queue = session_data(s)$queue$follow_up
  expect_length(queue, 2L)
  item = queue[[2L]]
  expect_identical(box$profile, "context")
  expect_identical(item$text, "[redacted]")
  expect_identical(item$source, "api_user")
})

test_that("the verbs validate their arguments", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  expect_error(gptr_steer(s, 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_steer(s, "x", as = "later"), class = "gptr_error_invalid_argument")
  expect_error(gptr_steer("s", "x"), class = "gptr_error_invalid_argument")
  expect_error(gptr_step(s, turns = 0), class = "gptr_error_invalid_argument")
  expect_error(gptr_step(s, turns = 1.5), class = "gptr_error_invalid_argument")
  expect_error(gptr_wait(list(1)), class = "gptr_error_invalid_argument")
  expect_error(gptr_cancel(NULL), class = "gptr_error_invalid_argument")
  expect_error(gptr_on(s, "turn_end", "not a function"), class = "gptr_error_invalid_argument")
})

test_that("model code may not steer or cancel another session, nor add listeners (IC-53)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  run = fake_run(session = "s9999999999")
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_steer(s, "x"), class = "gptr_error_permission")
  expect_error(gptr_cancel(s), class = "gptr_error_permission")
  expect_error(gptr_on(s, "turn_end", function(event, ctx) NULL), class = "gptr_error_permission")
  run$signal$control = "gptr_cancel"
  expect_invisible(gptr_cancel(s))
})

test_that("gptr_on() registers a session listener and returns its remover", {
  local_gw()
  # bound first: a local_*() helper called inside the `model =` expression would attach its
  # cleanup to the gateway's alias mask (it is evaluated there), not to this test
  fake = local_fake_provider(list("hello"))
  s = gptr("hi", model = fake, .run = FALSE, envir = new.env())
  log = new.env()
  log$roles = character()
  off = gptr_on(s, "message_end", function(event, ctx) {
    log$roles = c(log$roles, event$message$role)
    NULL
  })
  expect_true(is.function(off))
  gptr_step(s)
  expect_true("assistant" %in% log$roles)
  off()
  n = length(log$roles)
  s |> gptr("again")
  expect_length(log$roles, n)
  expect_error(gptr_on(s, "PreToolUse", function(event, ctx) NULL),
               class = "gptr_error_invalid_argument")
})

test_that("gptr_return() outside a run returns its argument invisibly (IC-48)", {
  expect_invisible(gptr_return(1:3))
  expect_identical(gptr_return(1:3), 1:3)
  local_gptr_options(quiet = FALSE)
  withr::local_envvar(GPTR_REPLAY = "replay")
  expect_silent(gptr_return("quiet while replaying"))
})

test_that("gptr_return() designates the run's value from R code during a run", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  designate = test_tool("designate", function(ctx) {
    gptr_return(c(a = 1, b = 2))
    "designated"
  })
  fake = local_fake_provider(list(fake_tool("designate"), "done"))
  s = gptr("designate it", model = fake, tools = list(designate), envir = new.env())
  expect_identical(s$value, c(a = 1, b = 2))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-sdk")'
```

Expected: every test fails with `could not find function` (`gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_on`, `gptr_return`).

- [ ] **Step 3: Write the implementation**

Create `R/gptr-sdk.R`:

```r
# R/gptr-sdk.R (Task 10: create)
# gptr-sdk.R -- the session SDK verbs gptr_step(), gptr_wait(), gptr_steer(), gptr_cancel(),
# gptr_on() and the agent-side gptr_return() (contract 6.5, 6.6; G1 section 4.6; IC-48, IC-53,
# IC-55). Every verb takes the session first so it composes with |>. Plan P08, layer L6.

#' The unsettled run of a session, or NULL
#' @noRd
sdk_run_of = function(s) {
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (is.null(run) || run_settled(run)) NULL else run
}

#' Starts the queued input of an idle session (the rendered prompt of `.run = FALSE`, queued steers
#' and follow-ups) with the pending run options of its `.run = FALSE` call, and returns the run;
#' returns the unsettled run of a running session; NULL when nothing is queued. A session without
#' pending options and without a kept home evaluates in `envir` (the verb's caller), held in a call
#' record released when the run settles [R2].
#' @noRd
sdk_start = function(s, envir = NULL) {
  run = sdk_run_of(s)
  if (!is.null(run)) return(run)
  d = session_data(s)
  opts = gateway_pending_take(d$id)
  queued = length(d$queue$steer) + length(d$queue$follow_up)
  if (!queued) return(NULL)
  if (is.null(opts)) {
    opts = list()
    if (is.null(session_home(s)) && is.environment(envir)) {
      call = call_new(envir = unmask_env(envir), args = list(run = TRUE))
      call_hold(call, s)
      opts$call = call
    }
  }
  run_start(s, NULL, opts)
}

#' A session listener counting `turn_end` events; returns list(n = function, off = function)
#' @noRd
sdk_turn_counter = function(s) {
  box = new.env(parent = emptyenv())
  box$n = 0L
  id = hook_add("turn_end", function(event, ctx) {
    box$n = box$n + 1L
    NULL
  }, rank = 0L, source = "session", session = session_data(s)$id)
  list(n = function() box$n, off = function() invisible(hook_remove(id)))
}

#' The stop condition of gptr_step(): `turns` turn_end events, or the run settled
#' @noRd
sdk_until_turns = function(run, counter, turns) {
  force(run)
  force(counter)
  force(turns)
  function() counter$n() >= turns || run_settled(run)
}

#' The stop condition of gptr_wait(): no session is running or waiting (a `waiting` session is
#' resumed by P21 from any blocking pump, so it does not count as settled)
#' @noRd
sdk_until_settled = function(ss) {
  force(ss)
  function() {
    all(vapply(ss, function(s) !session_data(s)$status %in% c("running", "waiting"), NA))
  }
}

#' Checks a session or a list of sessions; returns the list
#' @noRd
sdk_sessions = function(x, arg = "x") {
  ss = if (inherits(x, "gptr_session")) list(x) else x
  ok = is.list(ss) && !inherits(ss, "gptr_session") && length(ss) > 0L &&
    all(vapply(ss, inherits, NA, what = "gptr_session"))
  if (!ok) {
    gptr_abort(paste0("`", arg, "` must be a gptr session or a list of sessions."),
               "invalid_argument", arg = arg, expected = "a gptr_session or a list of them")
  }
  ss
}

#' Advance a session
#'
#' Starts the queued input of an idle session (built with `.run = FALSE`, or given a follow-up
#' with [gptr_steer()]) and pumps it until `turns` model turns have ended or the run settles. A
#' running session is advanced the same way.
#'
#' @param s A session.
#' @param turns The number of turns to advance (`Inf` for all).
#' @return `s`, invisibly. A run that settles in status `error`, `blocked`, `budget` or
#'   `max_turns` signals the condition documented in [gptr()].
#' @examples
#' s = gptr("Plan the analysis", model = gptr_fake_provider(list("Plan: ...")), .run = FALSE,
#'          envir = new.env())
#' gptr_step(s)
#' s$turns
#' @export
gptr_step = function(s, turns = 1L) {
  check_class(s, "gptr_session", "s")
  check_number(turns, "turns", min = 1)
  if (is.finite(turns) && turns != round(turns)) {
    gptr_abort("`turns` must be a whole number of turns or Inf.", "invalid_argument",
               arg = "turns", expected = "an integer >= 1 or Inf")
  }
  run = sdk_start(s, parent.frame())
  if (is.null(run)) return(invisible(s))
  counter = sdk_turn_counter(s)
  on.exit(counter$off(), add = TRUE)
  sdk_pump(list(run), until = sdk_until_turns(run, counter, turns))
  if (run_settled(run)) gateway_signal(s, run)
  invisible(s)
}

#' Wait for sessions to settle
#'
#' Starts idle sessions that have queued input, then pumps until no session is running or
#' waiting, or `timeout` seconds have passed. On timeout the sessions keep their `running` status
#' and no condition is raised.
#'
#' @param x A session or a list of sessions (a team or fan-out session counts as one).
#' @param timeout Seconds to wait.
#' @return `x`, invisibly. For a single session, a terminal status signals its condition.
#' @examples
#' fake = gptr_fake_provider(list("a"))
#' runs = list(a = gptr("one", model = fake, .run = FALSE, envir = new.env()),
#'             b = gptr("two", model = fake, .run = FALSE, envir = new.env()))
#' gptr_wait(runs, timeout = 10)
#' vapply(runs, function(x) x$status, "")
#' @export
gptr_wait = function(x, timeout = Inf) {
  ss = sdk_sessions(x)
  check_number(timeout, "timeout", min = 0)
  caller = parent.frame()
  runs = list()
  i = 0L
  while (i < length(ss)) {
    i = i + 1L
    r = sdk_start(ss[[i]], caller)
    if (!is.null(r)) runs = c(runs, list(r))
  }
  until = sdk_until_settled(ss)
  if (!until()) sdk_pump(runs, until = until, timeout = timeout)
  if (inherits(x, "gptr_session") && length(runs) && run_settled(runs[[1L]])) {
    gateway_signal(x, runs[[1L]])
  }
  invisible(x)
}

#' Steer a session
#'
#' The one enqueue function behind the pipe into a running session, the pause menu and
#' `ctx$send()`. A steer reaches the model after the current tool results, as "The user sent this
#' message while you were working: ..."; a follow-up when the agent would otherwise stop. On an
#' idle session the item is taken when the next run starts.
#'
#' @param s A session.
#' @param text The message (secrets are redacted before it is queued).
#' @param as `"steer"` or `"follow_up"`.
#' @return `s`, invisibly, at once.
#' @examples
#' s = gptr("Summarise mtcars", model = gptr_fake_provider(list("ok")), .run = FALSE,
#'          envir = new.env())
#' gptr_steer(s, "Use only the mpg column", as = "follow_up")
#' @export
gptr_steer = function(s, text, as = c("steer", "follow_up")) {
  check_class(s, "gptr_session", "s")
  check_string(text, "text")
  kind = check_choice(as, c("steer", "follow_up"), "as")
  gateway_control_other(s, "gptr_steer")
  session_enqueue(s, redact(as_utf8(text), "context"), as = kind, source = "api_user")
  invisible(s)
}

#' Cancel running sessions
#'
#' Aborts the run of a session (or of each session in a list): transfers are cancelled, child
#' processes stopped, the partial turn recorded as aborted, queued items moved to `dropped`, and
#' the status set to `aborted`. Idle sessions are left alone.
#'
#' @param x A session or a list of sessions.
#' @return `x`, invisibly.
#' @examples
#' s = gptr("long task", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
#'          envir = new.env())
#' gptr_cancel(s)
#' @export
gptr_cancel = function(x) {
  ss = sdk_sessions(x)
  for (s in ss) {
    gateway_control_other(s, "gptr_cancel")
    r = sdk_run_of(s)
    if (!is.null(r)) run_abort(r, reason = "user")
  }
  invisible(x)
}

#' Listen to a session's events
#'
#' Registers a session-scoped hook (rank 0) for one catalogued event (such as `message_end`,
#' `tool_call`, `turn_end`) or a plugin channel containing `:`. The handler is
#' `function(event, ctx)` and returns what the event allows. Forks never copy listeners.
#'
#' @param s A session.
#' @param event An event name; Claude and Codex hook names are refused with the gptr name.
#' @param handler `function(event, ctx)`.
#' @param matcher `NULL`, a tool-name glob for tool events, or `function(event)` returning a flag.
#' @return A function of no arguments that removes the hook, invisibly.
#' @examples
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
#' log = new.env()
#' log$roles = character()
#' off = gptr_on(s, "message_end", function(event, ctx) {
#'   log$roles = c(log$roles, event$message$role)
#'   NULL
#' })
#' gptr_step(s)
#' off()
#' log$roles
#' @export
gptr_on = function(s, event, handler, matcher = NULL) {
  check_class(s, "gptr_session", "s")
  check_string(event, "event")
  check_function(handler, "handler")
  if (!is.null(matcher) && !is.function(matcher)) check_string(matcher, "matcher")
  control_check("gptr_on")
  id = hook_add(event, handler, matcher = matcher, rank = 0L, source = "session",
                session = session_data(s)$id)
  invisible(sdk_off(id))
}

#' The remover returned by gptr_on()
#' @noRd
sdk_off = function(id) {
  force(id)
  function() invisible(hook_remove(id))
}

#' Designate the result of an agent run
#'
#' Called by R code the agent runs (or by you inside a tool) to designate the run's result, which
#' the session then returns as `$value`. Objects bound in the session's workspace are kept by name
#' when large (no copy), copied when small; other values are boxed. Outside a run it returns its
#' argument invisibly and does nothing else, so recorded code that still contains the call runs
#' cleanly.
#'
#' @param x The value; a bare name is recorded by name.
#' @return `NULL` invisibly during a run; `x` invisibly outside a run.
#' @examples
#' y = gptr_return(1:3)
#' y
#' @export
gptr_return = function(x) {
  run = run_current()
  if (is.null(run)) {
    if (!identical(replay_mode(), "replay")) {
      gptr_inform(paste("gptr_return() only designates a value while an agent runs;",
                        "here it returns its argument."),
                  "notice", .once = "gptr_return_outside_run")
    }
    return(invisible(x))
  }
  expr = substitute(x)
  s = gateway_session_by_id(run$session)
  if (is.null(s)) {
    gptr_abort("The running session is not registered in this process.", "internal",
               detail = "gptr_return() without a live session")
  }
  name = if (is.symbol(expr)) as.character(expr) else NULL
  session_value_set(s, ident_label(expr), x, name = name)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-sdk")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 55 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/gptr-sdk.R tests/testthat/test-gptr-sdk.R
git commit -m "feat(gateway): add the session SDK verbs"
```

---

### Task 11: The gateway copy suite

**Files:**
- Create: `tests/testthat/test-copy-gateway.R`

**Interfaces:**
- Consumes: P01's `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` (fresh `Rscript --vanilla` through `rscript_path()`; with `in_run_edit = TRUE` it defines `fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = <edit>)), 'done.'))` after the setup and counts copies from the start of the action); P02 `gptr_tool()`, `gptr_register()`; P06 `gptr_fork()`, `print`/`summary`/`str`/`format` of sessions and the value policy behind `session_value_set()`; everything of Tasks 5-10.
- Produces: the copy-safety evidence of 05 P08 acceptance 4 (the gateway rows of G3 t5 and the in-run edit rows of IC-41).

This is the headline copy-safety check of the gateway (03 §6.4, "Test"; 04 §12.3). The rows are G3 t5's gateway
rows (top level, pipe, continuation with context, wrapper with forwarded dots, alias and `if`/`else` models,
`$value` reads, print/summary/str/format of a session, fork, `saveRDS`), the G3 verification-log row for tool code
run in a function-frame home, the SDK paths added by this plan (`.run = FALSE` then `gptr_step()`/`gptr_wait()`,
`gptr_return()` outside a run, an interpolated prompt with `tools = c(...)` in a wrapper) and the three in-run edit
rows of IC-41 (`gptr("x", big)`, `big |> gptr("x")`, `s |> gptr("x", big)` with `in_run_edit = TRUE`). System 1,
parallel and background rows belong to `test-copy-s1.R` (P13), `test-copy-subagent.R` (P19) and P21. Before P10
there is no `r` tool, so the rows register a stand-in `r` spec through `tools = list(r_tool)`; it evaluates in
`ctx$envir`, the run's evaluation environment (P06).

While writing this plan every row was run in fresh processes against a scratch stand-in of P02-P07: all P08 paths
stayed in place, and the run exposed one real pin that the code of Tasks 5, 6, 9 and 10 now avoids: a `for` loop
that calls a closure with a local variable bound to a user frame keeps that frame referenced after the function
returns (G3 cause 2 in a new place: `gateway_check_visible()` with a `for` loop made the wrapper row `f(big)`
copy). Those loops are `while` loops.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-copy-gateway.R`:

```r
# tests/testthat/test-copy-gateway.R (Task 11: create)
# Fresh-process tracemem rows for every gateway entry point (G3 t5 and its verification log;
# IC-41; architecture 6.4). Each row runs its setup (creating the 40 MB `big`), starts
# tracemem(big), runs the gateway code and then the user's next in-place edit `big[1] = 0`: a
# `tracemem[` line after the action means gptr kept a reference and the edit copied the whole
# object. Rows with `in_run_edit = TRUE` also edit `big` inside the run, through an `r` tool call
# of the helper's fake provider (IC-41). expect_no_copy() (P01) skips on CRAN and without
# capabilities("profmem").

# M1 has no `r` tool (P10 adds it): a stand-in that evaluates the code where the run evaluates.
copy_r_tool = paste0(
  "r_tool = gptr_tool('r', 'Run R code (test stand-in).', ",
  "parameters = list(type = 'object', properties = list(code = list(type = 'string'))), ",
  "execute = function(input, ctx) { eval(parse(text = input$code), envir = ctx$envir); 'ok' })")

# A tool that designates `big` as the run's value with gptr_return() (IC-48), and a fake that
# calls it once.
copy_keep_tool = c(
  paste0("keep = gptr_tool('keep', 'Designates big.', parameters = list(type = 'object', ",
         "properties = structure(list(), names = character())), ",
         "execute = function(input, ctx) { gptr_return(big); 'kept' })"),
  paste0("fake_keep = gptr_fake_provider(list(list(tool = 'keep', ",
         "input = structure(list(), names = character())), 'done'), name = 'keep')"))

# Every row: `big`, a fake provider answering 'ok', no permission gate (no `mode` policy exists
# before P11 and the gate fails closed, IC-53) and the stand-in r tool.
copy_setup = c(
  "big = runif(5e6)",
  "fake = gptr_fake_provider(list('ok'))",
  "options(gptr.unsafe_no_permissions = TRUE)",
  copy_r_tool)

# label = list(extra setup, action, in_run_edit)
copy_rows = list(
  "top level: gptr('describe', big)" =
    list(character(), "s = gptr('describe', big, model = fake)", FALSE),
  "data-first pipe: big |> gptr('describe')" =
    list(character(), "s = big |> gptr('describe', model = fake)", FALSE),
  "continuation with context: s |> gptr('b', big)" =
    list(character(), "s = gptr('a', model = fake); s |> gptr('b', big)", FALSE),
  "named context: gptr('describe', data = big)" =
    list(character(), "s = gptr('describe', data = big, model = fake)", FALSE),
  "wrapper with forwarded dots: w('describe', big)" =
    list(character(), "w = function(...) gptr(...); s = w('describe', big, model = fake)", FALSE),
  "session created inside a function: f(big)" =
    list(character(), "f = function(d) gptr('describe', d, model = fake); s = f(big)", FALSE),
  "wrapper with a registered model name: model = fake" =
    list("invisible(gptr_register(fake))",
         "f = function(d) gptr('describe', d, model = fake); s = f(big)", FALSE),
  "wrapper with model = if (TRUE) fake else haiku" =
    list(character(),
         "f = function(d) gptr('describe', d, model = if (TRUE) fake else haiku); s = f(big)",
         FALSE),
  "wrapper with tools = c(grep, write) and an interpolated prompt" =
    list(character(),
         paste0("f = function(d) { cl = 3; gptr('cluster {cl}', d, model = fake, ",
                "tools = c(grep, write)) }; s = f(big)"), FALSE),
  "$value read, printed and assigned (gptr_return(big) by name)" =
    list(copy_keep_tool,
         paste0("s = gptr('designate big', model = fake_keep, tools = list(keep)); ",
                "print(head(s$value, 2)); x = s$value; rm(x)"), FALSE),
  "print, summary, str and format of a session" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake); print(s); invisible(summary(s)); ",
                "str(s); invisible(format(s))"), FALSE),
  "gptr_fork(s) and a fork turn" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake, envir = globalenv()); ",
                "f = gptr_fork(s); f |> gptr('read big')"), FALSE),
  "saveRDS(s) and readRDS()" =
    list(character(),
         paste0("s = gptr('describe', big, model = fake); p = tempfile(); saveRDS(s, p); ",
                "r = readRDS(p)"), FALSE),
  ".run = FALSE, then gptr_step()" =
    list(character(), "s = gptr('describe', big, model = fake, .run = FALSE); gptr_step(s)",
         FALSE),
  ".run = FALSE, then gptr_wait() on a list" =
    list(character(), "a = gptr('one', big, model = fake, .run = FALSE); gptr_wait(list(a))",
         FALSE),
  "gptr_return(big) outside a run" =
    list(character(), "invisible(gptr_return(big))", FALSE),
  "tool code run in a function-frame home (G3 verification log)" =
    list(paste0("fake = gptr_fake_provider(list(list(tool = 'r', ",
                "input = list(code = 'n = length(d)')), 'done'))"),
         "f = function(d) gptr('describe', d, model = fake, tools = list(r_tool)); s = f(big)",
         FALSE),
  "in-run edit: gptr('x', big) (IC-41)" =
    list(character(), "s = gptr('x', big, model = fake, tools = list(r_tool))", TRUE),
  "in-run edit: big |> gptr('x') (IC-41)" =
    list(character(), "s = big |> gptr('x', model = fake, tools = list(r_tool))", TRUE),
  "in-run edit: s |> gptr('x', big) (IC-41)" =
    list(c("fake0 = gptr_fake_provider(list('ok'), name = 'fake0')",
           "s = gptr('a', model = fake0, tools = list(r_tool))"),
         "s |> gptr('x', big, model = fake)", TRUE))

for (label in names(copy_rows)) {
  row = copy_rows[[label]]
  test_that(paste("no copy of big after", label), {
    expect_no_copy(c(copy_setup, row[[1L]]), row[[2L]], label = label, in_run_edit = row[[3L]])
  })
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-gateway")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]` (about 20 fresh processes; a few minutes). To see the suite catch a regression (the red phase of this test-only task), temporarily change the loop in `gateway_check_visible()` (`R/gptr-gateway.R`) to `for (it in call$context) {` with the body's first two lines unchanged and run the command again: the row `session created inside a function: f(big)` fails with `session created inside a function: f(big): 1 copies of `big` (allowed 0)`. Restore the `while` loop.

- [ ] **Step 3: Write the implementation**

No new package code: the implementation under test is Tasks 5-10. If a row fails, find the frame that keeps a reference with the rules of 03 §6.4 (a forced symbol dot, a closure or handler created in a frame that holds `...` or a user frame, a `for` loop calling closures with a frame-bound local, a list that held a frame, an assigned formal) and fix it in the owning file. For reference, the check that the red phase above toggles is:

```r
# R/gptr-gateway.R (reference: the loop of Task 9 that the red phase toggles; do not paste twice)
#' Fails fast when a context symbol is not the same object in the evaluation environment (IC-40).
#' A `while` loop: `env` may be a user frame, and a `for` loop calling closures with it pins the
#' frame (verified with tracemem: the wrapper f(big) copied `big` with a `for` loop here).
#' @noRd
gateway_check_visible = function(call) {
  env = call$envir
  items = call$context
  i = 0L
  while (i < length(items)) {
    i = i + 1L
    it = items[[i]]
    if (!identical(it$kind, "symbol")) next
    if (identical(binding_address(it$name, env), it$address)) next
    gptr_abort(c(paste0("`", it$name, "` is not visible from the environment this session ",
                        "evaluates in."),
                 paste0("Pass envir = the environment that holds `", it$name, "`, or pass it as ",
                        "a named value: gptr(..., ", it$name, " = force(", it$name, ")).")),
               "invalid_argument", arg = it$name,
               expected = "an object visible from the session's environment")
  }
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-gateway")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]`. On CRAN, or without `capabilities("profmem")`, every row skips (`SKIP 20`).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-copy-gateway.R
git commit -m "test(gateway): add the gateway copy-safety suite"
```

---

### Task 12: Documentation, NAMESPACE, plan acceptance and the M1 exit check

**Files:**
- Modify: `NAMESPACE`, `man/gptr.Rd`, `man/gptr_init.Rd`, `man/gptr_config.Rd`, `man/gptr_trust.Rd`, `man/gptr_step.Rd`, `man/gptr_wait.Rd`, `man/gptr_steer.Rd`, `man/gptr_cancel.Rd`, `man/gptr_on.Rd`, `man/gptr_return.Rd` (all generated by roxygen2)
- Test: `tests/testthat/test-gptr-gateway.R` (append)

**Interfaces:**
- Consumes: the roxygen blocks written in Tasks 2, 3, 7, 8 and 10 (every export has `@param`, `@return` and offline `@examples` on the fake provider; conventions §4).
- Produces: the NAMESPACE entries of P08's 10 exports (04 §14.1) and its 7 S3 methods, the Rd pages, and the M1 exit evidence (05 P08 acceptance 7).

roxygen2 turns `@export` on the S3 methods into `S3method()` lines (no `export()`), `@exportS3Method
utils::.DollarNames` into the delayed-free registration of the `utils` generic, and the explicit `@usage` of `gptr`
keeps the Rd usage identical to the formals although `gptr` is built with `structure(function(...), class = ...)`
(the pattern G5's toy package passed `R CMD check --as-cran` with, codoc included). Every example runs offline: the
fake provider is local and `offline = TRUE`, so neither the egress acknowledgement nor the replay mode that
`replay_mode()` forces while R CMD check runs examples (IC-45) stops it, sessions are stored under
`tempdir()/gptr`, and `gptr_init()`/`gptr_trust()` only touch `tempfile()` directories and read the (redirected)
user config.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-gptr-gateway.R`:

```r
# tests/testthat/test-gptr-gateway.R (Task 12: append)

test_that("NAMESPACE exports P08's ten names and registers its S3 methods", {
  nsfile = testthat::test_path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(nsfile), "the source NAMESPACE is not reachable from here")
  ns = readLines(nsfile, encoding = "UTF-8")
  exports = c("gptr", "gptr_init", "gptr_config", "gptr_trust", "gptr_step", "gptr_wait",
              "gptr_steer", "gptr_cancel", "gptr_on", "gptr_return")
  expect_true(all(paste0("export(", exports, ")") %in% ns))
  methods = c("\"\\$\"", "\"\\$<-\"", "\"\\[\\[\"", "\"\\[\\[<-\"", "print",
              "utils::\\.DollarNames")
  for (m in methods) {
    expect_true(any(grepl(paste0("^S3method\\(", m, ",gptr_gateway\\)$"), ns)), label = m)
  }
  expect_true("S3method(print,gptr_config)" %in% ns)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'
```

Expected: the new test's eight expectations fail (for example `all(paste0("export(", exports, ")") %in% ns) is not TRUE`) until roxygen has written the entries: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 192 ]`.

- [ ] **Step 3: Write the implementation**

Regenerate NAMESPACE and the Rd pages, then list P08's entries:

```bash
Rscript --vanilla -e 'devtools::document()'
grep -E "gptr_gateway|gptr_config\)|export\(gptr(_init|_config|_trust|_step|_wait|_steer|_cancel|_on|_return)?\)" NAMESPACE
```

Expected output of the `grep` (the order is roxygen's):

```text
S3method("$",gptr_gateway)
S3method("$<-",gptr_gateway)
S3method("[[",gptr_gateway)
S3method("[[<-",gptr_gateway)
S3method(print,gptr_config)
S3method(print,gptr_gateway)
S3method(utils::.DollarNames,gptr_gateway)
export(gptr)
export(gptr_cancel)
export(gptr_config)
export(gptr_init)
export(gptr_on)
export(gptr_return)
export(gptr_step)
export(gptr_steer)
export(gptr_trust)
export(gptr_wait)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "gptr-|copy-gateway")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 506 ]`: `test-gptr-config.R` 135 (the skip is the P11 leg of the `gptr_permissions()` test), `test-gptr-capture.R` 96, `test-gptr-gateway.R` 200, `test-gptr-sdk.R` 55, `test-copy-gateway.R` 20 (without later the `background` test skips as well: `SKIP 2 | PASS 504`).

Then run the acceptance commands of the next section, in this order (the last is the M1 exit check; it needs
P05-P07 complete):

```bash
Rscript --vanilla -e 'devtools::test()'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'
Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'
```

Expected: `devtools::test()` ends with `[ FAIL 0 | WARN 0 | ...` (skips only those named by P01-P08);
the lint command prints `No lints found.` and exits 0 (P01 acceptance A3: the namespace is loaded first, because
on the uninstalled tree lintr's `object_usage_linter` otherwise reports every call to an internal function);
`devtools::check()` reports `0 errors | 0 warnings | 1 note`, the note being
the incoming-feasibility NOTE naming the maintainer.

- [ ] **Step 5: Commit**

```bash
git add NAMESPACE man/ tests/testthat/test-gptr-gateway.R
git commit -m "docs(gateway): document the gateway and SDK exports"
```

---

## Plan acceptance

Every acceptance check of 05 P08 (including its review amendments), the task and test that prove it, and the
command with its expected result. Run from the repository root after Task 12.

| # | Check (05 P08) | Proved by | Command | Expected |
|---|---|---|---|---|
| 1 | `devtools::test(filter = "gptr-\|copy-gateway")` is green (copy tests skip on CRAN and without profmem) | Tasks 1-12 (all four test files and the copy suite) | `Rscript --vanilla -e 'devtools::test(filter = "gptr-\|copy-gateway")'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 506 ]` (skip: the P11 leg of the `gptr_permissions()` test; one more skip without later) |
| 2a | `gptr("a", mice)` and `mice \|> gptr("a")` create sessions with a `mice` context label | Task 9, test "gptr('a', mice) and mice \|> gptr('a') create sessions labelled mice" (the label reaches P07's context assembly through `ctx$input$call$context`); Task 8, test "gptr('a', mice) and mice \|> gptr('a') capture mice by name" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'` | green |
| 2b | `gptr("a") \|> gptr("b") \|> gptr("c", model = <second fake>)` returns the same object with three turns and a `model_change` entry | Task 9, test "a pipe chain returns the same session and a model switch appends model_change" | same | green |
| 2c | a test tool that pipes into its own running session enqueues a steer delivered after the tool result | Task 9, test "a tool that pipes into its own running session enqueues a steer after the result" (the relay `The user sent this message while you were working: use TPM` is the message right after the tool result) | same | green |
| 2d | `gptr()` non-interactively errors with `gptr_error_noninteractive` | Task 8, test "gptr() without a prompt needs a human" | same | green |
| 3 | identifier table: every row of 04 §6.1.3 including the wrapper `w = function(...) gptr("x", ...)` with a local `m` resolving to the caller's value (G3 t2b), an alias shadowed by a character variable (notice), `!!m`, `I(m)`, `if (hard) a else b` | Task 6, tests "resolve_identifier() follows the table of contract 6.1.3", "an alias shadowed by a character variable wins, with a message", "skill names compare after name_norm()", "an ambiguous normalised match lists the candidates"; Task 8, tests "identifiers through the gateway, including a wrapper with a local m (G3 t2b)" and "a shadowed alias wins with a notice; skill names normalise (IC-42)" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-capture\|gptr-gateway")'` | green |
| 4 | copy suite: every gateway row of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded dots, alias and if/else models, `$value` reads, print/summary/str of a session, fork, `saveRDS`) and the in-run edit rows of IC-41 (`gptr("x", big)`, `big \|> gptr("x")`, `s \|> gptr("x", big)` with `in_run_edit = TRUE`) report 0 copies | Task 11 (`test-copy-gateway.R`, 20 rows) | `Rscript --vanilla -e 'devtools::test(filter = "copy-gateway")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 20 ]` (every row `SKIP` on CRAN or without `capabilities("profmem")`) |
| 5a | `gptr_init()` without `path` errors non-interactively | Task 7, test "gptr_init() without a path needs someone to answer" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'` | green |
| 5b | with a path it creates the template files and does not touch `.Rbuildignore` | Task 7, tests "gptr_init(path) writes the templates once and never overwrites them" and "gptr_init() in a package source offers the .Rbuildignore line, never writes it" | same | green |
| 5c | a project without `gptr_trust()` ignores project settings beyond tightening | Task 3, test "an untrusted project only tightens (IC-52)"; Task 2, test "a changed trust-gated file makes the project untrusted again" | same | green |
| 5d | a non-interactive first use of a provider without an acknowledgement raises `gptr_error_egress` | Task 4, test "a first non-interactive use without an acknowledgement is gptr_error_egress"; Task 9, test "a first remote use without an acknowledgement is refused, then replay guards" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-config\|gptr-gateway")'` | green |
| 6a | `f = function(s, d) s \|> gptr("filter d", d)` with `s` homed in `globalenv()` evaluates where `d` is visible or fails fast naming `d` | Task 9, test "a continuation evaluates in the kept home and fails fast on a hidden symbol (IC-40)" (`cnd$arg == "d"`; with `envir = environment()` it runs) | `Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway")'` | green |
| 6b | `skills = single_cell` resolves to `single-cell` | Task 6, test "skill names compare after name_norm() (IC-42)"; Task 8, test "a shadowed alias wins with a notice; skill names normalise (IC-42)" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-capture\|gptr-gateway")'` | green |
| 6c | `gptr_return(x)` outside a run returns `x` invisibly | Task 10, test "gptr_return() outside a run returns its argument invisibly (IC-48)" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-sdk")'` | green |
| 6d | `gptr_config(mode = manual)` writes the project file when a workspace exists | Task 7, test "gptr_config(.scope = NULL) writes the project file when a workspace exists (IC-71)" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-config")'` | green |
| 6e | under `_R_CHECK_PACKAGE_NAME_` with `TESTTHAT=true` replay is not forced | Task 4, test "replay is forced only when R CMD check runs outside testthat (IC-45)" | same | green |
| 6f | a model-code call of `gptr_permissions(allow = "r(level<=3)")` during a run is refused with `gptr_error_permission` | Task 7, tests "the run$signal$control token check (shared with P11) refuses model code (IC-53)" (green now) and "a model-code gptr_permissions() call during a run is refused (IC-53, P11)" (skips until P11 defines `gptr_permissions()`, whose `perm_control_guard("gptr_permissions")` consumes the same `run$signal$control` token) | same | green, `SKIP 1` until P11 |
| 6g | `.opts = list(panel = list(size = 3))` reaches `ctx$input$opts$panel` when a `panel.size` setting is registered | Task 9, test ".opts entries named by a plugin namespace reach ctx$input$opts (IC-44)"; Task 5, test "gateway_opts() validates the core switches and plugin namespaces (IC-44)" | `Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway\|gptr-capture")'` | green |
| 7 | **M1 exit** (P05-P08 complete): `devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")` clean; every exported example runs offline on the fake provider (no example needs a later plan; IC-36) | Task 12 (roxygen, NAMESPACE, examples of Tasks 2, 3, 7, 8, 10) | `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'` | `0 errors \| 0 warnings \| 1 note` (the incoming-feasibility NOTE naming the maintainer) |

The contract's other P08 obligations are covered as well: route orders and route events (Task 9, "builtin:gateway
registers the routes ..." and "the gateway emits route, model_select and input"), terminal statuses (Task 9,
"a provider failure signals gptr_error_provider carrying the session", "a run that reaches max_turns ...",
"blocked and budget statuses map to their conditions"), visibility and `.run = FALSE` (Task 9), nested calls
(Task 9, "a gptr() call made during a run becomes a child session (route nested)"), routers (Task 9, two tests),
`.opts$images` (Task 9), the refusal of `parallel =`/`agents =` before P19 (Task 9), the SDK verbs (Task 10), trust fingerprints and `project_trust` (Task 2, including "a trust decision taken in this process lapses when a gated file changes"), the four services once `builtin:gateway` is loaded and call-level filters (Task 9, "with builtin:gateway loaded, P08's four services are served" and "call-level filters join the session filter layer instead of replacing it"), the
`filters` of the user and project settings files (Task 7, "user and trusted project filters reach the registry once
per change (04 10.1)"; Task 9, "a top-level gptr() applies the filters of the user settings file (04 10.1)"),
`gptr.prompt_secrets` (Task 9, "a secret-looking prompt is sent redacted, with a notice" and the `"ask"` test, "...
asks first; a no sends nothing"), the `interpolated` echo (Task 8, "an interpolated prompt is echoed at
verbosity 2"), the pause menu's `[b]ackground` (Task 9, "a run sent to the background returns the session at
once"), and the `gptr_gateway` methods (Task 8).

---

## Self-review

### Spec coverage (05 P08 scope bullets and review amendments -> tasks)

| Scope item (05 P08, 04) | Task |
|---|---|
| `gptr-gateway.R`: classed closure `gptr` with `$`, `[[`, `.DollarNames`, `$<-` refusal and `print` through `ns.resolve`/`ns.names` (IC-36) | 8 |
| dispatch steps 1-5 of 03 §4.1.1 with routes looked up in the registry; return visibility; registration point for routes of later plans (`route_pass()`, `gateway_run()`, `gateway_defer()`) | 8, 9 |
| `gptr-capture.R`: base-R capture under R2-R3, prompt selection, identifier resolution incl. `!!` and `I()`, `{identifier}` interpolation | 5, 6 |
| `gptr-sdk.R`: `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()` (`gptr_prob()` is P13's) | 10 |
| `gptr-config.R`: settings layers, `gptr_config()`, `gptr_init()` without a default path, `gptr_trust()`, egress acknowledgement, settings I/O for P11 (IC-06), `replay_mode()`, `replay_guard()` | 1, 2, 3, 4, 7 |
| `builtin:gateway` registering `nested`, `continue`, `new` and the core `setting` specs (IC-24) | 1 (specs), 9 (built-in) |
| `inst/templates/vignette.Rmd`, `settings.json`, `gitignore` | 7 |
| IC-41 plain-symbol dots through a `get0()` leaf without forcing | 5 (`dot_get()`), 8 (loop), 11 (copy rows) |
| IC-40 evaluation-environment precedence and visibility check | 9 |
| IC-42 identifier normalisation | 5 (`name_norm()`), 6, 8 |
| IC-44, IC-61, IC-69 namespaced `.opts`, `.opts$images`, `.opts$seed`, `.opts$frontend` | 5 (validation), 9 (images, `ctx$input$opts`) |
| IC-39 route orders | 9 |
| IC-53 mode and filter inheritance for calls made during a run; control-category checks in the setup exports | 8 (mode), 9 (continuations, children, call-level filters through `gateway_filters_apply()`), 1 (`control_check()`), 2, 7, 10 |
| 04 §10.1 settings key `filters` of the user and project files applied to the registry (P02 self-review item 18) | 7 (`gateway_filters_sync()`), 9 (top-level `gateway_run()`) |
| 04 §3.1 `gptr.prompt_secrets` (owner P03, applied by the gateway) | 9 (`gateway_prompt_secrets()` in `gateway_input()` and the `continue` route's steer) |
| 04 §2.2 message `interpolated` (echo of the interpolated prompt at verbosity >= 2) | 8 |
| 03 §6.2, 04 §7.14 the pause menu's `[b]ackground` returns the foreground `gptr()` call (P21 marks `run$opts$background`) | 9 (`run_foreground()`, `gateway_run()`) |
| IC-69 router models stored as `router:<name>`; the `router.call` service | 9 |
| IC-43 `gptr_can_prompt()` for the human check and questions | 2, 4, 7, 8 |
| IC-48 `gptr_return()` returns `invisible(x)` outside a run | 10 |
| IC-71 `gptr_config(.scope = NULL)` | 7 |
| IC-45 `replay_mode()` forcing replay only outside testthat; the `interp` record behind `args=` | 4; 5 and 8 (`call$interp`) |
| IC-52, IC-71 trust fingerprints (also for decisions taken in this process); `project_trust` as a first decision | 2 |
| IC-33, IC-34 the `trust.get` and `identifier.resolve` services (and `settings.get`, `router.call`) | 2, 3, 6 (bootstrap entries), 9 (served once `builtin:gateway` is loaded) |
| the egress acknowledgement as an `ask_human` | 4 |
| `test-copy-gateway.R` | 11 |
| M1 exit | 12 |

### Placeholder scan

The plan was searched for `TBD`, `TODO`, `implement later`, `fill in`, `appropriate error handling`, `handle edge
cases`, `similar to Task` and `NN`; none occurs in task text or code. Every function a code block calls is defined
in this plan or listed in 04 for P01-P07 (and the late services of P10, P14, P17, P21 are reached only through
`ext_service_get()`/`ext_service_has()`).

### Type and name consistency with 04

- Exports and signatures match 04 §6.1, §6.2, §6.5, §6.6 exactly (checked against the Global Constraints list):
  `gptr(...)` with all 21 formals after the dots (Task 8 test "the capture helpers know gptr()'s formals after the
  dots" guards the capture copy of the list), `gptr_init(path, instructions = TRUE, gitignore = TRUE)`,
  `gptr_config(..., .scope = NULL)`, `gptr_trust(path = ".", trust = NULL)`, `gptr_step(s, turns = 1L)`,
  `gptr_wait(x, timeout = Inf)`, `gptr_steer(s, text, as = c("steer", "follow_up"))`, `gptr_cancel(x)`,
  `gptr_on(s, event, handler, matcher = NULL)`, `gptr_return(x)`.
- Internal contract functions keep their 04 §7.8 signatures: `call_new(...)`, `call_release(call)`,
  `call_value(call, i)`, `route_pass()`, `gateway_defer(expr_fun)`, `gateway_run(call, s = NULL)`, `dot_facts(x)`,
  `resolve_identifier(expr, arg, envir)`, `identifier_known(name, arg)`, `interpolate_prompt(template, envir)`,
  `settings_get(key, session = NULL)`, `settings_effective()`, `settings_write(scope, patch)`,
  `trust_get(path = getwd())`, `home_address(envir)`, `replay_mode(arg = NULL)`,
  `replay_guard(model, what = "model call")`, `egress_check(provider_id)`.
- Classes: `c("gptr_gateway", "function")`, `gptr_config` (attribute `sources`), `gptr_call`, the sentinel class
  `gptr_route_pass`. Condition classes and fields as in 04 §2.2; message classes `alias_shadowed`, `egress_ack`,
  `interpolated`, `notice`; warning class `two_prompts`.
- Services: `settings.get`, `trust.get`, `identifier.resolve`, `router.call`, each `provided_by = "P08"`,
  `builtin = "gateway"`.
- Consumed names from 04: `run_start()`, `run_wait()`, `run_abort()`, `run_current()`, `session_new()`,
  `session_set_model()`, `session_set_mode()`, `session_enqueue()`, `session_value_set()`, `last_set()`,
  `live_all()`, `hook_add()`, `hook_remove()`, `registry_add()`, `registry_all()`, `registry_filters_set()`,
  `ext_load()`, `ext_declare_builtin()`, `ev_dispatch()`, `ev_new()`, `model_resolve()`, `model_default()`,
  `catalog_aliases()`, `provider_get()`, `project_messages()`, `redact()`, `reactor_pump()`, P01's helpers.

### Contract ambiguities (resolved as follows; also returned to the orchestrator)

1. **P08's process state.** 04 §7.0 gives P08 the fields `settings_session` and `interp` only. The settings-file
   cache, this process's trust decisions, the fingerprint cache, the `gateway_defer()` depth, the pending run
   options and held call records of `.run = FALSE` sessions and the ids of each session's rank-0 records live in
   one more P08 field, `the$gateway` (`gateway_state()`); `the$interp` is left unused. Nothing in it is run state.
2. **The IC-53 approval token.** 04 says the dispatcher approves "exactly that call through an `ask_human` (a
   one-shot token on the run)" without naming the field; `control_check(what)` consumes the function name from
   `run$signal$control` (a character vector), which P06's `perm_grant_control()` writes for P11's gate (and which
   P06's `session_control_check()` and P11's `perm_control_guard()` read too). P02 keeps a parallel grant list
   (`ext_control_grant()`) for its own `gptr_register()`/`gptr_reload()` guard; P06 fills both.
3. **Where the terminal condition is stored.** 04 §2.2 says the condition object "travels ... in the run";
   P06's `run_settle()` stores it in `session_data(s)$condition` (and `run$signal$condition`), and
   `gateway_signal()` reads `session_data(s)$condition`, otherwise building the condition from the session
   status, reason and transcript (`gptr.budget` entry, last failed assistant message).
4. **`session_new(parent =)`.** The gateway passes the running session **object** (found by id through
   `live_all()`), not its id.
5. **Queued input of `.run = FALSE`.** The rendered first message waits in the session's follow-up queue
   (`session_enqueue(s, prompt, as = "follow_up", source = "api_user", blocks = <context, skill and image
   blocks>)`), so `run_start(s, NULL, opts)` of any plan starts it (04 §7.21's `bg.register` example, P19 after
   `gateway_defer()`), read as "the input is the queued items" (04 §7.6); the call's run options wait in P08's
   pending store for `gptr_step()`/`gptr_wait()`. P06's IC-55 refusal of enqueues from model code must not apply
   to this first input of a session that has never run (nested `.run = FALSE` calls made by model code).
6. **Scope name of the user-level project file.** `settings_write()`/`settings_read()` call it `"user_project"`
   (04 names only session, project and user); P11's `gptr_permissions(scope = "project")` uses it.
7. **Holding a call record past `gptr()`.** `call_release(call)` keeps its one-argument signature; a record needed
   by a pending or background run carries `hold = TRUE` (`call_hold()`) and is released by `builtin:gateway`'s
   process-level `agent_end` and `session_shutdown` hooks, which see only the session id of the event.
8. **`interpolate_prompt()` returns `list(prompt, interp)`**; 04 fixes no return shape.
9. **Call-level filters** (`plugins = "-builtin:x"`). 04 has no per-session filter API and P02's
   `registry_filters_set(filters, scope)` replaces a scope's whole list, so `gateway_filters_apply()` merges the
   call's filters into the session settings key `filters` (a later `+x` replaces an earlier `-x`), applies the
   merged list with `registry_filters_set(scope = "session")`, says once that they stay in force for the R
   session, and treats the change as control-category when model code makes it (IC-53 items 3-4).
   `gptr_config(filters =)` applies its scope's list the same way (04 §10.1). The user and project `filters`
   settings are applied by P08 too (P02 self-review item 18: only the settings layer knows which layer a value
   came from): `gateway_filters_sync()` (Task 7) passes the user file's list with `scope = "user"` and a trusted
   project's list with `scope = "project"` (an untrusted project contributes no `filters`, IC-52), whenever a list
   differs from the one applied last, at the start of every top-level `gateway_run()` and after
   `gptr_config(filters =, .scope = "user" | "project")`. So all three scopes are P08's; a changed file is picked
   up by the next top-level call (the settings cache re-reads it), not by a hook inside the cache, which would
   give a read function a registry side effect.
10. **The egress question** uses `gptr_confirm()` whenever `gptr_can_prompt()` holds; no UI backend exists before
    P11, so the `ask_human` tier is honoured by never letting a hook answer it.
11. **`.opts$images` plots** are rendered by the gateway with `grDevices::png()` at the `gptr.plot_*` size;
    IC-44 names P09's `plot_png()`, which a P08 file may not call (P09 is later).
12. **`gptr_config()` without arguments during a run** only reads and is allowed; setting keys is the
    control-category action.
13. **"silent while a document is replayed"** (IC-48) is implemented as silent when `replay_mode()` is
    `"replay"`; 04 offers no other signal from P15.
14. **The `gptr_config()` example** passes `.scope = "session"` (04's example omits it) so that a check run inside a
    project with a `.gptr/` can never write the project file.
15. **P06 behaviour the tests rely on**, all from 04: `s$messages` lists operator messages (role `operator`, kind
    `steer_relay`); a test tool (not model-evaluated code) may pipe into its own running session (IC-55 refuses
    only model code: P06's `session_enqueue()` refuses only an `r` tool call of the same tree); `$turns` counts
    prompt turns, one per run (P06's `run_append_messages()` increments it at the run's first user message), so
    `gptr_step(turns = 1)` stops at the first `turn_end` while `$turns` is already 1; `.d$queue$follow_up` items
    carry `text` and `source`; model-change entries in R shape have `type = "model_change"` and `gptr$reason`;
    a `fake/fake-1` reference whose provider is registered only for a session resolves (P05's index of live fake
    engines), so `session_set_model()` accepts a continuation's session-scoped fake.
16. **`gptr_wait()` and `waiting`.** A `waiting` session counts as not settled (P21 ambiguity A10), so
    `gptr_wait()` keeps pumping until P21 resumes it or the timeout passes.
17. **`parallel =` and `agents =` before P19.** 04 says the sub-agent routes are simply absent before P19; the
    built-in routes then refuse such calls with `gptr_error_not_available` (`provided_by = "builtin:subagents"`)
    rather than run one session and ignore the argument.
18. **Dependency plans.** The plan was first written against 04 alone; the review of 2026-10-01 checked it against
    the P01-P07, P09-P11, P14, P17 and P21 plans now in `dev/plan/` (signatures of `local_project()`,
    `project_root()`, `setting_get()`, `ext_service_set()`/`service_builtin_active()`, `ev_dispatch()`, the
    `setting`/`route`/`agent` kind validators, `session_new()`, `session_enqueue()`, `run_start()`,
    `run_settle()`, `run_target()`, P05's catalog and P07's `context_input()`), see the Plan review log.
19. **`builtin:gateway` and the services before Task 9.** P01's `service_builtin_active()` hides a bootstrap
    service whose built-in the registry does not list, and `builtin:gateway` (04 §10.3: declared in
    `gptr-gateway.R`) exists only from Task 9. Tasks 2, 3 and 6 therefore test the bootstrap entries
    (`the$services[[name]]`), and Task 9 tests the four services end to end (`ext_service_has()`,
    `setting_get()`); until Task 9, `setting_get()` reads the option layer only, which no P08 code before Task 9
    relies on.
20. **Trust decided in this process** (a `project_trust` handler without `remember`, or the interactive
    answer) is kept with the fingerprint it was given for (`trust_mark()`); a gated file changed later in the
    process voids it (IC-52 "Control files modified during the process are not loaded again without
    confirmation"), and gptr's own project-settings writes carry it over without turning it into a recorded
    decision.
21. **Router timeout.** `setTimeLimit()` cannot be read back, so arming it inside a tool evaluation would clear
    the per-expression limit P09 set; a nested routed session gets a soft timeout (a slower router counts as
    failed) and a top-level one the armed limit.
22. **Run settlement** is read from P06's `run$settled` flag (or a terminal status); 04 §7.6 lists the run's
    status values but not the flag, and a `waiting` run (P21) is not settled.
23. **Rank-0 specs of one session.** P02 keeps the first of two records of equal rank, so
    `gateway_register_spec()` removes the session's earlier record of the same kind and name before it adds a
    continuation's newer spec; the ids are kept in `the$gateway$specs` and forgotten at `session_shutdown`.
24. **`gptr.prompt_secrets = "ask"`.** 04 §3.1 gives the values `"redact"` and `"ask"` only (G6's open question 1
    also considered moving the value into the vault). P06 redacts every entry at ingress and `session_enqueue()`
    redacts with the `context` profile, so the original value can never be sent: `"ask"` asks whether to send the
    prompt with the value replaced by a `[secret:...]` marker (default yes) and a no stops the call with
    `gptr_error_invalid_argument` (`arg = "prompt"`) before anything is sent; without someone to answer it acts as
    `"redact"` (IC-43), which sends the redacted prompt with a `notice` each time. The check covers gateway
    prompts (`gateway_input()` and the `continue` route's steer); `gptr_steer()` keeps its documented silent
    redaction.
25. **The `interpolated` echo and the console.** P08 signals `gptr_message_interpolated` (stderr) whenever a
    literal prompt was interpolated at verbosity >= 2 (04 §2.2). P14's `console_call()` also echoes the
    interpolated text on stdout at verbosity 2, so a console prompt with `{x}` shows both lines; P14 may drop its
    own echo or muffle the class (recorded for P14; P08 follows 04).
26. **`[b]ackground` from the pause menu.** `run_foreground()` ends its wait when `run$opts$background` is set (as
    P06's `run_wait_foreground()` does) and `gateway_run()` then returns the running session invisibly, holds the
    call record until the run settles and signals nothing (P21 ambiguities A3 and A17).

### Executed validation

- Every ` ```r ` block of this plan was extracted and parsed with `Rscript --vanilla -e 'invisible(parse(file =
  "<f>"))'`: all parse. A token check with `getParseData()` found no `LEFT_ASSIGN` (`<-`) and no `%>%` in any code
  block.
- First draft: the package code and tests of Tasks 1-10 were extracted and run with testthat 3e in a scratch
  harness (the P01 draft sources plus contract-shaped stand-ins of P02-P07, including a mini session kernel that
  plays fake-provider scripts): `test-gptr-config.R` 124 expectations and 1 skip, `test-gptr-capture.R` 90,
  `test-gptr-gateway.R` 136 (the `print(gptr)` snapshot included), `test-gptr-sdk.R` 53, all passing. (The
  counts stated in the tasks are the current ones; see the 2026-10-01 entry below.)
- The 20 rows of `test-copy-gateway.R` were run in fresh `Rscript --vanilla` processes against the same harness
  with tracemem: every row whose behaviour P08 owns reported 0 copies, including the three in-run edit rows of
  IC-41 and the function-frame tool row; the `$value`, `summary` and `gptr_fork()` rows depend on P06's value
  policy and methods, which the stand-in does not implement. The run found one real pin, fixed in this plan: a
  `for` loop that calls closures with a local bound to a user frame keeps the frame referenced
  (`gateway_check_visible()`, `interpolate_prompt()`, `resolve_agents()`, `resolve_identifier()`'s `c()` branch
  and `gptr_wait()` now use `while` loops).
- The regular expressions of the Task 12 NAMESPACE test were checked against the expected roxygen output.
- Review of 2026-10-01 (re-run after the fixes in the Plan review log): all 24 ` ```r ` blocks re-extracted and
  parsed; `getParseData()` finds no `LEFT_ASSIGN` and no `%>%`; no non-ASCII byte; no code line over 100
  characters. A scratch package was assembled from P01's plan code (`aaa-state.R`, the service table,
  `utils-conditions.R`, `utils-encoding.R`, `utils-options.R`, `utils-paths.R`, `json-encode.R`,
  `utils-hash.R`, `zzz.R`, `setup.R`, `helper-fake.R`), small stand-ins for the P02/P04/P05/P06 functions
  `gptr-config.R` and `gptr-capture.R` call, and this plan's four R files; `devtools::test()` with
  `NOT_CRAN=true` gave `test-gptr-config.R` 30 / 55 / 79 / 97 / 130 + 1 skip after Tasks 1 / 2 / 3 / 4 / 7 and
  `test-gptr-capture.R` 65 / 96 after Tasks 5 / 6 (exactly the counts stated above), Task 1's red phase
  `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]` and Task 5's 12 failing tests. A scratch test of the changed gateway
  helpers (`mode_tighter()` with a non-mode, `run_settled()` with `waiting`, `gateway_register_spec()`
  replacing an older spec, `gateway_filters_apply()` merging, `router_invoke()` armed at top level and soft
  inside a tool evaluation) passed 20 expectations. The gateway, SDK and copy-suite tests need the P06 kernel
  and were parse-checked only; testthat 3.3.2 was confirmed to count a new snapshot as a pass with one warning.
- Cross-plan consolidation of 2026-10-01 (see the log at the end): all 24 ` ```r ` blocks re-extracted and parsed
  with `Rscript --vanilla`; `getParseData()` finds no `LEFT_ASSIGN` and no `%>%`; no non-ASCII byte; no code line
  over 100 characters. The new helpers were run against stand-ins in a scratch script: `gateway_filters_sync()`
  (nothing applied for empty files; the user list applied once; an untrusted project's list ignored, a trusted
  one applied, an emptied or untrusted-again project re-applied as `character()`; a list P02 rejects gives one
  diagnostic and one notice and is not retried), `gateway_prompt_secrets()` (unchanged text passes silently;
  `"redact"` and `"ask"` without a human return the redacted text with a notice; `"ask"` with a human asks once,
  returns the redacted text on yes and on no signals `gptr_error_invalid_argument` with `arg = "prompt"` and no
  value in the message) and `run_foreground()` (its `until()` is true once the run settles or
  `run$opts$background` is set). The new gateway tests need the P06 kernel and were parse-checked only.

## Plan review log

Adversarial review of 2026-10-01 against `00-conventions.md`, 04 (with §15), 05 P08, 03 and the plans now in
`dev/plan/` (P01-P07, P09-P11, P14, P17, P21). Every fix was applied in place above; the counts in Tasks 2-4, 6-9
and 12 and in the Plan acceptance were recomputed (and re-run for `test-gptr-config.R` and
`test-gptr-capture.R` in a scratch package, see "Executed validation").

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | blocker | Tasks 2, 3, 6 (service tests); Task 9 | The services `trust.get`, `settings.get` and `identifier.resolve` are registered with `builtin = "gateway"`, but `builtin:gateway` is declared only in Task 9, and P01's `service_builtin_active()` hides a bootstrap service whose built-in the registry does not list. The tests "the trust.get service answers for other plans", "the settings.get service backs setting_get()" and "the identifier.resolve service is resolve_identifier()" could not pass in their own tasks (`gptr_error_not_available`). | applied | Tasks 2, 3 and 6 test the bootstrap entries `the$services[[name]]` (provider, built-in, function); Task 9 adds "with builtin:gateway loaded, P08's four services are served" (`ext_service_has()` for all four, `setting_get()` end to end). Moving the declaration to Task 1 was rejected because 04 §10.3 places `builtin:gateway` in `gptr-gateway.R`. Contract ambiguity 19. |
| 2 | major | Task 2 `trust_get()`/`trust_resolve()`, Task 2 `settings_write()` | A trust decision taken in this process (a `project_trust` handler without `remember`, or the interactive answer) was cached as a bare `TRUE` that `trust_get()` returned before any fingerprint check, so a gated file changed later in the process (for example by model code) stayed trusted, against IC-52 ("Control files modified during the process are not loaded again without confirmation"). `settings_write()` also turned such an in-process decision into a recorded one. | applied | `trust_mark()` stores the decision with its fingerprint; `trust_holds()` checks both the record and the in-process decision against the current fingerprint; `trust_resolve()` re-decides after a change; `settings_write()` carries a recorded trust to trust.json and an in-process one to memory only. New test "a trust decision taken in this process lapses when a gated file changes (IC-52)". Contract ambiguity 20. |
| 3 | major | Task 9 `gateway_register()`; Task 7 `gptr_config()` | A call-level filter (`plugins = "-builtin:mcp"`) went to `registry_filters_set(filters, "session")`, which replaces the whole R-process filter list: one call silently dropped earlier session filters and disabled the built-in for every later call; from model code it reconfigured gptr without the IC-53 control check. `gptr_config(filters =)` (a filter path of 04 §10.1) only wrote the settings file and never reached the registry. | applied | `gateway_filters_apply()` merges the call's filters into the session settings key `filters` (a later `+x` replaces an earlier `-x`), applies the merged list, prints a one-time notice and calls `control_check("gptr_config")`; `gptr_config()` hands the scope's filter list to `registry_filters_set()` after writing. New tests in Tasks 7 and 9 (with `registry_filters_set()` mocked). Contract ambiguity 9 rewritten. |
| 4 | major | Task 4 `egress_check()` | The `how_to_ack` hint `gptr_config(egress = list(<id> = "ack"), .scope = "user")` replaces the whole `egress` object (`gptr_config()` merges top-level keys only, 04 §6.2), so following it erased every earlier acknowledgement. | applied | The hint is `gptr_config(egress = utils::modifyList(gptr_config()$egress, list(<id> = "ack")), .scope = "user")`; the Task 4 test checks the string and that evaluating it keeps an earlier `anthropic` acknowledgement. |
| 5 | minor | Global Constraints; Tasks 1, 8; whole plan | The plan named its helpers `gateway_control_check()`/`gateway_mode_tighter()` "because P06 owns `control_check()` and `mode_tighter()`", which is false: P06 named its own `session_control_check()`/`run_mode_tighter()` and reserved `control_check()`/`mode_tighter()` for P08, and P06 and P11 cite "P08's `control_check()`". | applied | Renamed to `control_check()` and `mode_tighter()` everywhere; the rationale lines and roxygen comments now state the real ownership (P07 does own `context_items()`, so `gateway_context_items()` stays). Re-checked: no top-level name of this plan is defined by another plan. |
| 6 | minor | Task 9 `router_invoke()` | `setTimeLimit(elapsed = Inf, transient = FALSE)` after the router call clears any limit set by an enclosing `r` evaluation (P09 arms one per top-level expression; R cannot read it back), so a routed session nested in model code removed the `r` timeout for the rest of that expression. | applied | The limit is armed only when `run_current()` is `NULL`; inside a tool evaluation the router gets a soft timeout (a slower router counts as failed). Scratch-tested both paths. Contract ambiguity 21. |
| 7 | minor | Task 9 `gateway_run()` | The IC-40 visibility check ran after the session was created (or the continuation's specs registered and model/mode switched), so "fails fast" still left side effects. | applied | `gateway_continue_envir()` fixes the evaluation environment and `gateway_check_visible()` runs before any session, registration or switch. |
| 8 | minor | Task 9 `run_settled()` | Settlement was "status not in the active list", so a run parked as `waiting` (P21, IC-57) counted as settled and `gptr_step()`/`gptr_wait()` would signal or stop early. | applied | `run_settled()` reads P06's `run$settled` flag or a terminal status. Contract ambiguity 22. |
| 9 | minor | Task 9 `gateway_register()` | A continuation passing a newer spec with the name of one the session already had (`model = gptr_fake_provider(...)` twice, a revised tool) added a second rank-0 record; P02 keeps the first of equal rank, so the stale spec silently won. | applied | `gateway_register_spec()` removes the session's earlier record of the same kind and name (ids in `the$gateway$specs`, forgotten at `session_shutdown`); test "a continuation's newer spec replaces the session's older spec of the same name". Contract ambiguity 23. |
| 10 | minor | Tasks 4, 7 (`egress_question()`, `gptr_init()`, `init_rbuildignore()`) | Every question ended with `[y/N]` although P01's `gptr_confirm()` appends ` [y/N] ` itself: the prompts read `... [y/N]  [y/N]`. | applied | The question texts end with `?`; Task 7 Consumes notes the hint. |
| 11 | minor | Task 8 `gptr()` | `envir` was never validated (04 §1.1: every export validates its arguments); `gptr("x", envir = 1)` failed later with an unrelated error. | applied | `check_env(envir, "envir")` when `envir` is given (a formal, not a dot, so forcing it is copy-safe); test added. |
| 12 | minor | Task 6 `ident_symbol()`; Task 8 `mode_tighter()` | An unknown, unbound symbol such as `mode = fast` was returned unchecked, reaching `mode_tighter()` (where `match()` gives `NA` and `if (NA)` errors) or the kernel. | applied | The literal name goes through `ident_check_chr()` (invalid modes are `gptr_error_invalid_argument` at resolution); `mode_tighter()` never loosens on a non-mode. Test added in Task 6. |
| 13 | minor | Task 10 test "gptr_on() registers a session listener" | `model = local_fake_provider(...)` inside the `gptr()` call is evaluated in the gateway's alias mask, so withr attached the helper's cleanup to that evaluation and unregistered the provider at once; the test passed only because the spec was also registered at rank 0. | applied | The provider is bound first (`fake = local_fake_provider(...)`). |
| 14 | minor | Task 9 `gateway_new_session()` | `session_new(opts = list(tools, depth, thinking, system, frontend, background))`: P06 reads only `thinking`; the rest suggested behaviour that does not happen (`.opts$system` reaches P07 through `call$args$opts`). | applied | `opts = list(thinking = ...)` with a comment saying where the other values travel. |
| 15 | minor | Self-review (ambiguities 2, 3, 7, 15, 18), `call_hold()` roxygen | Stale statements: the token check named `control_check()` while the code used another name; `gateway_signal()` said to read `run$signal$condition` (it reads `session_data(s)$condition`); held records "released by session listeners" (they are process-level hooks); `$turns` "one per `turn_end`" (P06 counts one per run); "P01, P02, P07 absent"; "P06's finalizer dispatches `session_shutdown` with `session = NULL`" (it passes the id). | applied | Each statement corrected; ambiguities 19-23 added; "Executed validation" records this review's runs. |
| 16 | minor | Tasks 2, 3, 6 tests | Three new test lines exceeded the 100-character lint limit. | applied | Wrapped. |
| 17 | major | Task 9: session-scoped provider specs | Concern: `session_set_model()` and P06's `run_target()` resolve `d$model` with `model_resolve()`, whose catalog lists only process-level providers, so `model = <spec>` registered at rank 0 could not be resolved. | rejected | P05 resolves a session-scoped `fake/fake-1` through its index of live fake engines and `provider_stream()` looks up the session's records first (P05 self-review item 13); every P08 test and example uses fakes. Non-fake session-scoped providers are P05/P06's resolution concern; recorded in contract ambiguity 15. |
| 18 | minor | Task 5 `interpolate_prompt()` | `{pi}` or `{letters}` would interpolate base objects because the lookup inherits. | rejected | 04 §6.1.4 specifies `get0(inherits = TRUE)`. |
| 19 | minor | Task 2 `trust_fingerprint()` | The content-hash cache is keyed by path, mtime and size, so a same-size edit inside one mtime tick could reuse a stale hash. | rejected | Current file systems (APFS, NTFS, ext4) record sub-second mtimes; without the cache every `setting_get()` would rehash all gated files. |
| 20 | minor | Task 9 `.run = FALSE` | The queued first input becomes a user message with source `follow_up` (P06's `queue_item_message()`), not `prompt`. | rejected | The message source is P06's choice for queue items; contract ambiguity 5 documents the queue route that 04 §7.6 allows. |
| 21 | minor | Task 11 Step 2 | The red phase expects a pass. | rejected | A test-only task over code written in Tasks 5-10; Step 2 documents the regression toggle (`for` loop in `gateway_check_visible()`) that makes a row fail. |
| 22 | minor | Task 10 `gptr_step(turns = 1)` | The pump might run past the first `turn_end` within one reactor iteration. | rejected | P04's `reactor_pump()` checks `until()` before every iteration, and the next model request needs further iterations, so the run is still `running` when the pump returns. |

## Cross-plan consolidation log

Issues raised by the cross-plan checkers (2026-10-01), verified against 04 (§2.2 message classes, §3.1
`gptr.prompt_secrets`, §7.14, §10.1 filters, §11.2 project trust rule), 03 §6.2 (pause menu), G6 (option table and
open question 1), P01 (`verbosity()`, `gptr_inform()`, acceptance A3), P02 (self-review item 18,
`registry_filters_set()`), P03 (spec-coverage row: "`gptr.prompt_secrets` is applied by the gateway (P08)"), P06
(`run_wait_foreground()`, ingress redaction in `session_append()`/`session_enqueue()`), P14 (`console_call()` echo,
pause menu) and P21 (A3, A17). Counts changed: Task 7 130 -> 135; Task 8 69 -> 74; Task 9 167 -> 192 (165 -> 190
when the `background` test skips); Task 12 red phase `PASS 167` -> `PASS 192`; Task 12 and Plan acceptance 1
476 -> 506 (474 -> 504 without later).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| C1 | shared-names | minor | Task 8 `gptr()` interpolation block; Global Constraints (conditions) | applied | Valid: 04 §2.2 assigns `interpolated` to P08 ("echo of the interpolated prompt at verbosity >= 2") and no plan raised it. After `interp = ip$interp` the closure now calls `gptr_inform(paste0("Interpolated prompt: ", prompt_text), "interpolated")` when `length(interp) && verbosity() >= 2L` (no closure or handler in the frame, rule R3; the message passes P01's redaction hook and honours `gptr.quiet`). New Task 8 test "an interpolated prompt is echoed at verbosity 2 (gptr_message_interpolated, 04 2.2)" (5 expectations: the class, the text, the prompt, no echo without braces, none at verbosity 1). The test sits in Task 8 because the interpolation code is in Task 8's `gptr()`, not Task 6. P14's own stdout echo (`console_call()`) stays as P14 wrote it; the double echo at verbosity 2 in the console is recorded as contract ambiguity 25 for P14 (drop its echo or muffle the class). Task 8 Consumes, prose, self-review (message classes, spec coverage) updated |
| C2 | shared-names | minor | Task 9 `gateway_input()` | applied (in part) | Valid: nothing read `gptr.prompt_secrets`, although P03 leaves it to the gateway. New `gateway_prompt_secrets(prompt)` redacts with the `context` profile; on a change, `"redact"` (and `"ask"` with nobody to answer, IC-43) sends the redacted prompt with a `notice`, and `"ask"` with a human asks through `gptr_confirm(..., default = TRUE)`. Rejected part: "keep the original only on an explicit no". P06 redacts every entry at ingress (`session_append()`, `persist` profile) and every queued item (`session_enqueue()`, `context` profile), so the original can never reach the provider; keeping it would promise what cannot happen. A no therefore stops the call before anything is sent (as C5 proposes). The check runs before the `input` event, so hooks see the redacted text, and also on the `continue` route's steer. `.once = "prompt_secrets"` was not used: a notice per prompt that carried a secret is the "redact (with a message)" of G6. Tests in Task 9 use a pattern key built with `paste0()` (P03's convention), so no vault state is involved |
| C3 | obligations | major | Task 7 `gptr_config()`; Task 9 `gateway_run()`; contract ambiguity 9 | applied | Valid: 04 §10.1 makes the settings key `filters` a filter path, and P02 (self-review item 18) relies on P08 to pass the user and project lists with their scope; only `gptr_config()` reached the registry, so a `"filters": ["-builtin:mcp"]` in `settings.json` was ignored after a restart. New `gateway_filters_sync()` in `gptr-config.R` (Task 7): the user file's list with `scope = "user"`, the project file's list with `scope = "project"` only while the project is trusted (the rule `settings_layered()` applies to a non-tighten key, IC-52), each re-applied only when it differs from `the$gateway$filters_applied[[scope]]`; a list P02 rejects becomes a diagnostic and a one-time notice. `gptr_config(filters =)` uses it for the user and project scopes (the session scope still goes straight to `registry_filters_set()`), and `gateway_run()` calls it at the start of every top-level call, after the trust question of a new session and before the session is built. "After each settings-file cache reload" is met by that per-call comparison (the cache re-reads a changed file) rather than a hook inside `settings_file_read()`, which would give a read function a registry side effect. Ambiguity 9 now says P08 applies all three scopes. Tests: Task 7 "user and trusted project filters reach the registry once per change (04 10.1)" (5 expectations); Task 9 "a top-level gptr() applies the filters of the user settings file (04 10.1)" (2), both with `registry_filters_set()` mocked and `the$gateway$filters_applied` restored |
| C4 | obligations | minor | Task 9 `run_foreground()`, `gateway_run()` | applied | Valid: P21 marks `run$opts$background` for the pause menu's `[b]ackground` and P06's `run_wait_foreground()` honours it, but `run_foreground()` waited for settlement through `run_wait()`. It now pumps with `until = function() run_settled(run) \|\| isTRUE(run$opts$background)`; `gateway_run()` then, for a run that is not settled and is marked background, holds the call record (`call_hold()`, released at `agent_end` [R2], as the `background = TRUE` path does; the fix as proposed omitted this, and `gateway_dispatch()`'s `on.exit()` would otherwise release a record the still-running run uses) and returns the session invisibly without `gateway_signal()`. New Task 9 test "a run sent to the background returns the session at once (pause menu [b]ackground)" (4 expectations; a reactor timer marks the run during a slow fake stream; the run is drained with `run_wait()`). Ambiguity 26 added (P21 A3/A17) |
| C5 | obligations | minor | Task 9 `gateway_input()`; Global Constraints options | applied (merged with C2) | Same defect as C2; its semantics are the ones applied: `"redact"` notifies, `"ask"` asks and a no aborts with `gptr_error_invalid_argument` (`arg = "prompt"`), no human means `"redact"`. The option is now listed under "Options consumed" in the Global Constraints. The test is in Task 9 (where `gateway_input()` lives), not Task 8: "a secret-looking prompt is sent redacted, with a notice (gptr.prompt_secrets)" (4 expectations) and the `"ask"` test (10 expectations). Ambiguity 24 records the reading |
| C6 | obligations | minor | Task 12 Step 4 acceptance commands | applied | Valid: a bare `lintr::lint_package()` on the uninstalled tree reports every internal call (P01 decision 5, A3). Replaced with `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'`, expected `No lints found.` and exit 0 |
| C7 | trace | minor | Task 12 Step 4 acceptance commands | applied (same change as C6) | Duplicate of C6 |
| F1 | finalize | minor | Task 5 test "unmask_env() replaces a magrittr mask by its parent" (`object_name_linter` on `assign(".", 1, envir = mask)`) | applied | The binding name `.` is fixed by magrittr's pipe mask, which `unmask_env()` detects (`identical(names(env), ".")`), so it cannot be renamed; the line now carries ``# nolint: object_name_linter. magrittr's mask binds `.`.`` (no other code changes; test counts unchanged) |
| F2 | finalize | minor | Task 7 `R/gptr-config.R` section header before `template_file()` (`commented_code_linter`) | applied | `# --- gptr_init() (6.2, 11.16)` parsed as a call; it now reads `gptr_init() (contract 6.2, 11.16)` like the `gptr_config()` header, with five fewer dashes to stay within 100 characters |
| F3 | finalize | minor | Task 9 `gateway_new_session()` comment above `session_new()` (`commented_code_linter`) | applied | The comment line `# (gateway_run_opts())` parsed as code; the sentence now ends "through `call$args$opts` and the run options that gateway_run_opts() builds" (same meaning, prose only). Lint of all 24 P08 R blocks with P01's linters (`indentation_linter = NULL`, `object_usage_linter = NULL` for standalone blocks): 0 lints; every touched block parses under `Rscript --vanilla` |
