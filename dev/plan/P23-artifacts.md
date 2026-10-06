# P23 Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Artifacts are Shiny apps (S-5, REQ-39) that the model writes into `<root>/artifacts/<id>/app.R` and launches from the live session with `peter$app(id, data =)`, as immutable, token-protected versions served by supervised background R processes, validated by a parse, launch, HTTP and session ladder, and listed, relaunched and stopped with `gptr_artifacts()`.

**Architecture:** `R/artifact-app.R` holds the built-in `builtin:artifacts`: the artifact types `shiny` and `html` (static checks of the working copy, immutable `vNNN/` snapshots written through P01's leaf `save_rds()`, a self-contained child entry `artifact_serve()` started with `callr::r_bg()` in the secret-free `artifact` environment, behind a per-launch access token, on a loopback port published by atomic rename, with a parent-PID watchdog), the HTTP 200 check through P04's reactor, the optional chromote session check with a 1000x700 screenshot attached to the running `r` result, the `peter$app()` member, the `artifacts` prompt section and the `artifacts` checkpointer. `R/artifact-registry.R` holds the artifact process table (records, status, stop, run files, redacted logs, job-table rows, the `artifact_start`/`artifact_stop` events), the lazy orphan sweep, the `.onUnload` cleanup and the export `gptr_artifacts()`.

**Tech Stack:** base R (>= 4.2.0); Imports callr (`r_bg()`), processx and ps (through P04 and directly for creation times), jsonlite and cli (through P01), curl (through P04's reactor); Suggests shiny, httpuv and later (loaded only inside the child), openssl (the access token), chromote (the session check and screenshot); testthat 3e and withr in tests; rtiktoken only through P07's development runner `dev/bench/tokens/run.R`.

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2 rows `artifact-*`, §3.3 `shiny-bslib`, §5.7, §6.4, §6.5, §6.7, §6.15, §7.3 `<artifacts>`, §7.4 `<environment>`, §10.6, §12.2, §12.4, §12.7), dev/spec/04-interface-contract.md (§1.1-§1.5, §2.2 `artifact`/`artifact_too_large`, §3.1 `gptr.artifact_max_bytes`, §4.4, §4.6 `gptr.artifact`, §5.10 `gptr_artifact`, §5.12 `gptr_artifacts`, §6.4 `gptr_artifacts()`, §7.1, §7.3, §7.4, §7.6, §7.10, §7.14, §7.16, §7.23, §8.2, §9.3, §9.4 `app`, §10.2 rows 19 and 29, §10.3, §10.4, §11.1, §11.6, §12; §15 IC-33, IC-60, IC-61, IC-63, IC-68, IC-69, IC-70, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P23).

**Depends on:** P10, P11, P14, P16 (and through them P01-P09 and P15). **Milestone:** M5.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (`=` for assignment, never the left arrow; native `|>`; ASCII-only R sources; `pkg::fun()` calls; `gptr_abort()`/`gptr_warn()`/`gptr_inform()`; no `:::` in `R/`; no `.GlobalEnv`; `on.exit(..., add = TRUE)` right after any state change; testthat 3e; no network in tests; `Rscript --vanilla`; one commit per task). Plan-specific requirements, copied from the spec:

- Files and layer (03 §3.2): `artifact-app.R` | L4 | "`peter$app()`: working copy, immutable snapshots, callr child, validation ladder, screenshot" | builtin `artifacts`; `artifact-registry.R` | L4 | "`gptr_artifacts()`, stop, relaunch, lazy orphan sweep". L4 code "may call: the extension API (`gptr$register()`, `ctx`), L0, their own area, the declared services `eval-*`, `env-*`, `tool-walk`, `proc-*`, the §7.0 service table of the contract, and the **kernel SDK** allowlist [IC-33]"; the record constructors of `provider-message.R`/`provider-events.R` are callable from every layer (P01's `helper-arch.R`); `test-arch-layers.R` enforces it.
- Owned files (05 P23 "Owns"): "The two R files and tests; `test-copy-artifact.R`; `inst/gptr/skills/shiny-bslib/`", plus the NS-8 golden transcript and its baseline row under `dev/bench/tokens/` (IC-73: "P10, P13, P15, P18, P19, P22 and P23 each add their NS fixture and baseline rows"), plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`.
- Export (04 §6.4): `gptr_artifacts(id = NULL, open = FALSE, stop = FALSE, version = NULL)`: "Without `id`: a `gptr_artifacts` data frame (after a lazy orphan sweep). With `id`: the `gptr_artifact` handle; `open = TRUE` opens it in the viewer or browser (interactive only; relaunches a stopped artifact); `version = <int>` relaunches that immutable version; `stop = TRUE` stops its process (interrupt, 3 s grace, `kill_all()`). Conditions: `invalid_argument` (unknown id), `artifact`, `missing_package` (shiny). Emits `artifact_start`, `artifact_stop`." Example: `gptr_artifacts()  # an empty listing when no artifact exists`.
- Member (04 §9.4): `peter$app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` "(`kind`: a registered `artifact_type`, IC-69; ids that are Windows reserved names are refused, IC-63)"; returns "`gptr_artifact`; the `r` result gets its URL, checks and screenshot image"; risk level 3 (03 §6.15: "level 3: launching model-written code").
- Internal contract (04 §7.23): `builtin_artifacts(gptr)` "registers `artifact_type` specs `shiny` and `html`, the member `app` (§9.4), the `artifacts` prompt section (IC-68) and the `artifacts` checkpointer"; `artifact_serve(dir, port_file, parent_pid, token)` "runs inside the callr child: picks a free 127.0.0.1 port from `port_candidates()`, publishes it by atomic rename of `port_file`, starts a parent-PID watchdog, runs the app behind the `gptr_token` check (IC-71); stdout/stderr are read by the parent and appended redacted to `app-vNNN.log` (IC-70)".
- Handle (04 §5.10): `gptr_artifact` = "list(id, title, kind, version (int), url (with the `gptr_token` query, IC-71), path, status (`running`, `stopped`, `failed`), checks (list(parse, launch, http, session) of lgl|NA plus `messages`), screenshot (chr(1)|NULL), session (chr(1)|NULL))"; print: "`artifact  <id>  ->  <url>   (<status text>)`, where `running` reads `running in background` (NS-8; P14's renderer prints the same line on `artifact_start`)".
- Listing (04 §5.12): class `c("gptr_artifacts", "gptr_listing", "data.frame")` with columns `id`, `title`, `version`, `status`, `url`, `pid`, `bytes`, `path`, "built by `new_listing(df, class, footer = NULL)` (P01, `utils-text.R`)".
- Files (04 §11.6): `<root>/artifacts/<id>/app.R` "working copy (model-written; committed)"; `artifact.json` "metadata (committed)"; `vNNN/app.R` "immutable snapshot copy (NNN = 001, 002, ...)"; `vNNN/R/gptr_data.R` "loader: reads data/<file> for each name listed in artifact.json (IC-63)"; `vNNN/data/001.rds` "snapshots via save_rds(compress = FALSE), numbered (ignored)"; `run/run.json` "`{pid, port, url, version, started}` (ignored; the URL carries the token)"; `run/port` "the child's port, published by atomic rename (ignored)"; `run/app-vNNN.log` "child stdout/stderr read by the parent and appended with persist redaction (ignored; IC-70)". `artifact.json`: `{"id", "title", "kind": "shiny" | "html", "versions": [{"n", "created", "app_sha", "data": [{"name", "file", "class", "dim", "bytes"}], "session", "checks": {"parse", "launch", "http", "session"}}], "current": int, "port": int | null, "created", "updated"}` (this plan adds the unknown key `kind` to each version record, Self-review ambiguity 8). "Ids match `^[a-z0-9][a-z0-9-]{0,62}$` and are not a Windows reserved device name (`con`, `aux`, `nul`, `prn`, `com1`-`com9`, `lpt1`-`lpt9`; IC-63)". All JSON files are UTF-8 without BOM, LF, written atomically (04 §11).
- `<root>` (03 §5.7): "`.gptr` in a consented workspace (so NS-8's `.gptr/artifacts/marker-explorer/app.R` is literal), else `tempdir()/gptr`" (P01's `workspace_root()`); `.gptr/.gitignore` already ignores `artifacts/*/v*/data/` and `artifacts/*/run/` (04 §11.1, P08's template).
- Option (04 §3.1): `gptr.artifact_max_bytes` (`num(1)`, default `5e8`, owner P23): "snapshot cap"; read through `gptr_opt("artifact_max_bytes")`.
- Conditions (04 §2.2): `gptr_error_artifact` (fields `id`, `stage`, `log` (tail)): "a validation-ladder stage failed"; `gptr_error_artifact_too_large` (parent `artifact`; fields `bytes`, `max`): "snapshot above `gptr.artifact_max_bytes`"; `gptr_error_invalid_argument` (`arg`, `expected`; never the value); `gptr_error_missing_package` (`package`, `feature`). Stages used here: `parse`, `static`, `snapshot`, `launch`, `http`.
- Events (04 §10.4): `artifact_start`, `artifact_stop` (gptr, notify; payload `id`, `url`, `version`; stop: `reason`). Custom entry (04 §4.6): `gptr.artifact` `{id, version, url, status, checks}`. `r` tool details (04 §4.4): `artifacts` = "paths of artifacts written (`.gptr/artifacts/<id>/app.R`)" (P10 collects them from `artifact_start`).
- Prompt section (04 §9.3, IC-68): `artifacts` | T0 | order `600` | budget `150` | "shiny installed and `builtin:artifacts` enabled" | P23; text verbatim from 03 §7.3 (measured 124 o200k tokens, 03 §7.3 table).
- Kinds (04 §10.2): row 19 `artifact_type` [experimental] "`build` `function(id, dir, data, ctx)`; `check` `function(dir, ctx)` -> `list(ok, messages)`; `launch` `function(version_dir, ctx)` -> `list(url, pid, stop)`; `stop` `function(handle)`" ("failures become tool results with the stage and a log tail"); row 29 `checkpointer` [experimental] "`scope` (`objects`, `files`, `state`, `artifacts`, `other`); `before` `function(call, ctx)` -> token; `after` `function(call, ctx, token)` -> JSON-able fragment; `undo`/`redo` `function(fragment, ctx, force)` -> chr report lines; `prune` `function(live_keys, ctx)`; `describe` `function(fragment)` -> chr" ("never throws into the loop (a failure marks its fragment not restorable)").
- Children (IC-60): "`proc_spawn()` and every `callr::r_bg()` pass `encoding = "UTF-8"`"; `supervise = supervise_default()`; callr receives `child_env_callr(child_env("artifact"))` ("every profile ... points `R_ENVIRON_USER` and `R_PROFILE_USER` at gptr's empty files and drops `R_ENVIRON`"); "Every long-lived child exits when the parent dies: ... artifacts through their watchdog"; "A requested stop is recorded in the job table (`stop_requested`); any exit after it maps to status `stopped` (artifacts, bridges) ..., never `error` (callr 3.8.0 exits 1 with `callr_timeout_error`)"; "every process-spawning test calls `skip_on_cran()`".
- R children and R CMD check (Self-review ambiguity 13): passing `env =` to callr replaces its default `callr::rcmd_safe_env()`, so `artifact_child_env()` sets its three values `R_TESTS = ""`, `R_BROWSER = "false"`, `R_PDFVIEWER = "false"` (R CMD check runs tests with `R_TESTS=startup.Rs`, which R's base profile sources in every R child); test helpers that start `Rscript` children pass `env = c("current", R_TESTS = "")`.
- Child-only environment variable: `GPTR_ARTIFACT_PORTS` (comma-separated candidate ports, previous port first, set by `artifact_child_env()` only in the artifact child and read only by `artifact_serve()`; a child-only variable beside 04 §3.2's `GPTR_MCP_TOKEN`, `GPTR_SUBAGENT_DEPTH` and `GPTR_WORKER`, never set in the user's session and never read by gptr there). It carries the ports because 04 §7.23's signature `artifact_serve(dir, port_file, parent_pid, token)` is fixed and the self-contained child cannot call `port_candidates()` (Self-review ambiguity 1); Task 4's child-environment test asserts its value.
- Randomness (IC-61): "Ports come from `port_candidates()` (P01: RNG-free hash bits in 49152-65535)"; "`httpuv::randomPort()` is never called (it calls `sample()`, verified)"; `with_seed_preserved()` "around third-party calls that use R's RNG in the parent (`chromote::Chromote$new()`, loading shiny, httpuv helpers)"; "Tests assert an identical `.Random.seed` after ... `peter$app(check = TRUE)`".
- Logs (IC-70): "MCP stderr and artifact logs are read incrementally and appended through `redact_stream("persist")`; raw redirect files are deleted at process exit".
- Access (IC-71): "each launch gets a 128-bit token (`openssl::rand_bytes(16)`, else `/dev/urandom` on Unix; on Windows without openssl no token and a notice); the wrapper app rejects sessions whose URL lacks `gptr_token=<hex>`; the handle's URL carries it; static checks flag reads of `secret_file` paths at level 3".
- Paths and names (IC-63): "Artifact ids that are Windows reserved device names ... are rejected. Data snapshots are `data/001.rds`, `data/002.rds`, ... with the mapping in `artifact.json` (`data: [{name, file, class, dim, bytes}]`); the loader reads the file listed for each name."
- Ladder constants (report 17 §3.4 and its verification log): host `127.0.0.1`; launch timeout 30 s; stop grace 3 s then `kill_all()`; watchdog every 1 s; session check: "connected, no `shiny-busy`, 0 `.recalculating`, stable for 5x100 ms; timeout 20 s"; screenshot 1000x700 PNG ("about 900 tokens", 03 §6.15, §12.2: "artifact result | about 80 + about 900 screenshot").
- CRAN (13 C-42, C-43; report 17 §3.5): "Packages should not start external software (such as PDF viewers or browsers) during examples or tests unless that specific instance of the software is explicitly closed afterwards"; no fixed ports; the viewer opens only when a human is present; nothing is written by default in non-interactive runs (IC-45: artifacts live in a consented `.gptr/` or `tempdir()`).
- Copy safety (03 §6.4, 04 §1.3): user objects are read only through leaf functions returning primitives [R4], serialised only through `save_rds()` (`ascii = FALSE`) [R7], never held after return [R1]; the caller's frame is used during the call only [R2]; `test-copy-artifact.R` proves that "the snapshot leaves the source object editable in place" (05 P23 acceptance 3).
- Tests: the fake provider and helpers of 04 §12 (`local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_project()`, `local_gptr_options()`, `expect_no_copy()`); no plan-specific helper file (helpers live in the two test files); fake keys are assembled at run time with `paste0()` (no key-shaped literal in a source file, as in P03); process tests clean up with `withr::defer()`.

Test counts below are those of `devtools::test()` (which sets `NOT_CRAN=true`) on the development machine with shiny 1.13.0, bslib, httpuv, later, openssl, chromote and a Chrome binary installed. Without shiny, httpuv or later the launch tests skip; without chromote or a Chrome binary the two session-check tests of Task 6 skip (`SKIP 2`); without `capabilities("profmem")` the copy rows skip.

## File Structure

| File | Action (task) | Responsibility |
|---|---|---|
| `R/artifact-app.R` | create (Task 1), extend (Tasks 2, 3, 4, 6, 7, 8, 9) | package state, ids, paths, `artifact.json`, the `gptr_artifact` handle and its `format`/`print` methods; static checks; data snapshots and the `shiny`/`html` builds; the child entry `artifact_serve()` and the access token; the headless session check; the callr launch, port wait, HTTP check and the validation ladder `artifact_start()`; the `artifacts` checkpointer; `peter$app()` (`artifact_app()`, the member's `fun` and `execute`), the `artifacts` section and `builtin_artifacts()` |
| `R/artifact-registry.R` | create (Task 5), extend (Task 10) | the artifact process table (records, status, stop, run files, redacted logs, job-table rows, events, the handle builder), the lazy orphan sweep; `gptr_artifacts()`, the listing and the `.onUnload` cleanup |
| `tests/testthat/test-artifact-app.R` | create (Task 1), extend (Tasks 2, 3, 4, 6, 7, 8, 9, 11) | tests of `R/artifact-app.R` and of the shipped skill |
| `tests/testthat/test-artifact-registry.R` | create (Task 5), extend (Task 10) | tests of `R/artifact-registry.R` and NS-8 end to end on the fake provider |
| `tests/testthat/test-copy-artifact.R` | create (Task 9) | the copy-safety rows: `peter$app()` from user code and from model code leaves the snapshotted object editable in place |
| `inst/gptr/skills/shiny-bslib/SKILL.md` | create (Task 11) | the artifact house-style skill (03 §3.3, §7.3 catalog line) |
| `dev/bench/tokens/fixtures/ns08-marker-explorer.json` | create (Task 12) | the NS-8 golden transcript (IC-73) |
| `dev/bench/tokens/baseline.csv` | modify (Task 12, one row written by P07's runner) | the `ns08-marker-explorer` baseline row |
| `NAMESPACE`, `man/gptr_artifacts.Rd` | generated (Tasks 1, 10) | `Rscript --vanilla -e 'devtools::document()'`: `S3method(format,gptr_artifact)`, `S3method(print,gptr_artifact)`, `export(gptr_artifacts)` |

## Interfaces consumed (exact names; 04 is authoritative)

- P01: `the`, `` `%||%` ``, `on_load(expr)`, `on_unload(fun)`, `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`, `check_string(x, arg, null = FALSE, empty = FALSE)`, `check_strings(x, arg, null = FALSE)`, `check_flag(x, arg, null = FALSE)`, `check_number(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE)`, `gptr_opt(name)`, `gptr_has_human()`, `supervise_default()`, `workspace_root(create = TRUE)`, `path_norm(path)`, `path_rel(path, root = project_root())`, `save_rds(object, file, compress = FALSE)` [R7][leaf], `port_candidates(n = 20L)`, `with_seed_preserved(expr)` [leaf], `hash_sha256(x)`, `as_utf8(x)`, `raw_to_utf8(x, fallback = "CP1252")`, `read_utf8(path)` (`$text`), `write_utf8(path, text, eol = "\n", bom = FALSE, final_newline = TRUE)`, `json_encode(x, pretty = FALSE)`, `json_decode(text)`, `new_listing(df, class, footer = NULL)`, `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)` (`source = "screenshot"`), `ev_new(type, ...)`; tests: `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_gptr_options(..., .env = parent.frame())`, `local_fake_provider(script, name = "fake", type = "chat", .env = parent.frame())`, `fake_tool(name, ..., .text = NULL, .id = NULL)`, `fake_requests(spec)`, `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)`, `rscript_path()`.
- P02: `gptr_spec(kind, name, ...)`, `gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL, exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL, execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL, guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE, available = NULL, annotations = list())`, `gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`, `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)`, `ev_dispatch(event, payload, session = NULL, ctx = NULL)`; the factory API object's `gptr$register(spec)`; `ctx$session`, `ctx$envir`; tests: `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)`, `hook_remove(id)`.
- P03: `child_env(profile, pass = character(), set = character(), provider = NULL)` (profile `artifact`), `child_env_callr(env)`, `redact_stream(profile = "stream")` (`push(chunk)`, `flush()`), `secret_scan(code, tainted = character())` (`$findings` with `rule`, `name`; rule `secret_file`); tests: `secret_register(value, name, source = "user", active = TRUE, origin = NULL)` and `vault_reset()` (P03's reset of the secret vault, which every test that registers a secret calls first and defers, as P03, P14, P18 and P22 tests do).
- P04: `reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL, retry = NULL)` (spec fields `url`, `method`, `headers`, `connect_timeout`, `first_byte_timeout`, `idle_timeout`; `on_fail(cnd)` gets a classed condition whose `status` is the HTTP status of a non-2xx answer), `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)` (returns `TRUE` when `until()` held), `reactor_cancel(ids)`, `reactor_now()`, `kill_all(p, grace = 2)`, `job_add(kind, id, name, pid = NA, stop, status = function() "running")` (kind `artifact`), `job_remove(id)`, `pid_alive(pid, create_time = NULL)`; tests: `job_list(kind = NULL)`.
- P06 (kernel SDK, IC-33): `run_current()`, `run_eval_env(run)`, `run_emit(run, type, ...)`, `session_data(s)` (`$id`, `$entries`), `session_append(s, entry)` (an entry in R shape `list(type = "custom", custom_type, data)`); `dispatch_nested(name, input, ctx)` calls the member's `execute` for model code (validated input; an error result becomes `gptr_error_tool` inside the model's code); tests: `gptr_last()`.
- P08: the exported gateway object `peter` (`peter$app` through the `ns.resolve` service), `peter(...)` (tests).
- P10: the member closure of `peter$app` (`member_closure(spec)`: formals from the spec's `fun`; called by the user it evaluates `fun` in its own frame, called from model code it passes `dispatch_nested()`); the r-call marker of the `r` tool, a binding `gptr_r_call` of class `gptr_r_call` in the `r` tool's execute frame whose `images` (list of image blocks) and `dropped` (int) collect images for the running `r` result, capped at `gptr.r_max_images` (P10 Task 1; read here by data because `tool-namespace.R` is an L4 file outside this area, see Self-review ambiguity 3); the `r` tool's session hook on `artifact_start` that fills `details$artifacts`.
- P11: the risk table and `risk.classify` service read the member's `risk` (level 3 here); in `auto` mode level 3 runs without asking (03 §6.8.1).
- P14: the `builtin:console` hook on `artifact_start` that prints `artifact  <id>  ->  <url>   (running in background)` at verbosity >= 1 (stdout at 2).
- P16: the dispatcher-facing `checkpointer` contract above; report lines matching `not restored|not redone|conflict|failed` mark a rewind partial (P16 `ckpt_partial_re`).
- P17: nothing (P17 is outside P23's dependency closure, 05: P10, P11, P14, P16). Task 11's skill test reads the frontmatter with `yaml::yaml.load()` (yaml is an Import, 03 §9) instead of P17's `skill_parse()`; P17's discovery of `inst/gptr/skills/` finds the shipped `shiny-bslib` without a call from this plan.
- P07: `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]` and its fixture format (Task 12).

## Tasks

1. Package state, ids, metadata and the `gptr_artifact` handle
2. Static checks (validation ladder stage 1)
3. Data snapshots and the `shiny` and `html` builds
4. The child: `artifact_serve()` and the access token
5. The artifact process table: records, status, stop, logs, events and the orphan sweep
6. The headless session check and screenshot
7. Launch and the validation ladder
8. The `artifacts` checkpointer
9. `peter$app()`, the `artifacts` section, `builtin:artifacts` and the copy rows
10. `gptr_artifacts()`, relaunch, unload cleanup and NS-8 end to end
11. The `shiny-bslib` skill
12. The NS-8 golden transcript and baseline row

### Task 1: Package state, ids, metadata and the `gptr_artifact` handle

**Files:**
- Create: `R/artifact-app.R`
- Test: `tests/testthat/test-artifact-app.R` (create; Tasks 2, 3, 4, 6, 7, 8, 9 and 11 append)
- Generated: `NAMESPACE` (`S3method(format,gptr_artifact)`, `S3method(print,gptr_artifact)`)

**Interfaces:**
- Consumes: P01 `check_string(x, arg, null = FALSE, empty = FALSE)`, `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `workspace_root(create = TRUE)` (called with `create = FALSE`: nothing is created until a version is written), `read_utf8(path)`, `write_utf8(path, text, ...)` (atomic), `json_encode(x, pretty = FALSE)`, `json_decode(text)`, `hash_sha256(x)` (raw -> chr(1)), `path_rel(path, root = project_root())`, `as_utf8(x)`, `` `%||%` ``; P06 kernel SDK `session_data(s)` (`$id`); tests: P01 `local_project()`.
- Produces (internal, used by every later task): `artifact_state` (environment: `procs` = the process table, an environment id -> record; `browser`; `swept`), `artifact_reserved`, `artifact_launch_timeout` (30), `artifact_stop_grace` (3), `artifact_shot_size` (`c(width = 1000L, height = 700L)`), `artifact_id_check(id)`, `artifact_root()`, `artifact_dir(id)`, `artifact_version_dir(id, n)`, `artifact_working_file(dir, kind)`, `artifact_time()`, `artifact_session_id(ctx)`, `artifact_meta_path(id)`, `artifact_exists(id)`, `artifact_meta_read(id)`, `artifact_meta_write(id, meta)`, `artifact_meta_new(id, title = NULL, kind = "shiny")`, `artifact_version_record(meta, n)`, `artifact_set_current(id, n)`, `artifact_version_checks_set(id, n, checks)`, `artifact_checks(parse = NA, launch = NA, http = NA, session = NA, messages = character())`, `artifact_checks_json(checks)`, `artifact_checks_from_json(x)`, `artifact_file_sha(path)`, `artifact_dir_bytes(id)`, `new_gptr_artifact(id, title, kind, version, url = NA_character_, path, status = "stopped", checks = artifact_checks(), screenshot = NULL, session = NULL)` -> the 04 §5.10 handle (fields in contract order); S3 methods `format.gptr_artifact()` (the NS-8 line, then `checks: parse ok | launch ok | http ok | session skipped`, the messages and the screenshot path) and `print.gptr_artifact()`.

Report 17 §5.1 (`artifact_lib3.R`, verified) is the reference: ids, `artifact.json` written atomically, `vNNN` version directories. The contract changes its layout (04 §11.6: the working copy `app.R` next to `artifact.json`, numbered data files, `port` and `current` in `artifact.json`) and its id rules (IC-63). JSON `null` is written for a missing port and for checks that did not run (`NA`), and read back as `NA`. The handle prints on stdout with `writeLines()` (its messages are untrusted text, never a format string, rule C1), so an `r` evaluation captures the NS-8 line when the model prints the handle; an artifact that is not running shows its working copy instead of a URL.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-artifact-app.R`:

```r
# Tests of R/artifact-app.R (P23). Tests that start processes skip on CRAN and without shiny,
# httpuv and later; the headless session check also skips without chromote and a Chrome binary.

# A temporary project with a .gptr/ workspace; artifacts live in <project>/.gptr/artifacts
local_artifact_project = function(.env = parent.frame()) {
  local_project(.env = .env)
}

# Write a model-written working copy (app.R or page.html) of an artifact
write_working = function(id, lines, file = "app.R") {
  dir = artifact_dir(id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_utf8(file.path(dir, file), lines)
  file.path(dir, file)
}

ok_app = c(
  "library(shiny)",
  "ui = fluidPage(textInput('gene', 'Gene'), tableOutput('t'))",
  "server = function(input, output, session) {",
  "  output$t = renderTable(markers[grepl(input$gene, markers$gene, fixed = TRUE), ])",
  "}",
  "shinyApp(ui, server)"
)

test_that("artifact ids follow contract 11.6 and refuse Windows reserved names", {
  expect_identical(artifact_id_check("marker-explorer"), "marker-explorer")
  expect_identical(artifact_id_check(strrep("a", 63)), strrep("a", 63))
  bad = c("con", "aux", "nul", "prn", "com1", "lpt9", "Marker", "-x", "a b", "a/b", "a.b",
          strrep("a", 64), "")
  for (id in bad) expect_error(artifact_id_check(id), class = "gptr_error_invalid_argument")
  expect_error(artifact_id_check(1), class = "gptr_error_invalid_argument")
  cnd = expect_error(artifact_id_check("con"), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "id")
})

test_that("artifacts live under the workspace root", {
  root = local_artifact_project()
  expect_identical(artifact_dir("demo"), file.path(root, ".gptr", "artifacts", "demo"))
  expect_identical(basename(artifact_version_dir("demo", 2L)), "v002")
  expect_identical(basename(artifact_version_dir("demo", 1000L)), "v1000")
  expect_identical(basename(artifact_working_file(artifact_dir("demo"), "shiny")), "app.R")
  expect_identical(basename(artifact_working_file(artifact_dir("demo"), "html")), "page.html")
})

test_that("artifact.json round-trips versions, checks and a null port", {
  local_artifact_project()
  meta = artifact_meta_new("demo", "Demo")
  rec = list(name = "d", file = "data/001.rds", class = "data.frame", dim = I(c(3L, 2L)),
             bytes = 10)
  meta$versions = list(list(n = 1L, created = artifact_time(), app_sha = "ab",
                            data = list(rec), session = NULL,
                            checks = artifact_checks_json(artifact_checks(parse = TRUE))))
  meta$current = 1L
  artifact_meta_write("demo", meta)
  expect_true(artifact_exists("demo"))
  txt = paste(readLines(artifact_meta_path("demo"), encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "\"port\": null", fixed = TRUE)
  expect_match(txt, "\"launch\": null", fixed = TRUE)
  back = artifact_meta_read("demo")
  expect_identical(back$title, "Demo")
  expect_identical(back$kind, "shiny")
  expect_identical(as.integer(back$current), 1L)
  v = artifact_version_record(back, 1L)
  expect_equal(unlist(v$data[[1]]$dim), c(3, 2))
  expect_null(artifact_version_record(back, 2L))
  checks = artifact_checks_from_json(v$checks)
  expect_true(checks$parse)
  expect_true(is.na(checks$launch))
  artifact_version_checks_set("demo", 1L, artifact_checks(TRUE, TRUE, FALSE, NA))
  expect_false(artifact_meta_read("demo")$versions[[1]]$checks$http)
  artifact_set_current("demo", 0L)
  expect_identical(as.integer(artifact_meta_read("demo")$current), 0L)
  expect_null(artifact_meta_read("absent"))
})

test_that("the handle formats as the NS-8 line with its checks, and prints it", {
  root = local_artifact_project()
  h = new_gptr_artifact("marker-explorer", "Marker explorer", "shiny", 1L,
                        url = "http://127.0.0.1:4827/?gptr_token=00ff",
                        path = file.path(root, ".gptr", "artifacts", "marker-explorer", "app.R"),
                        status = "running",
                        checks = artifact_checks(TRUE, TRUE, TRUE, NA, "HTTP-only check"))
  expect_s3_class(h, "gptr_artifact")
  expect_named(h, c("id", "title", "kind", "version", "url", "path", "status", "checks",
                    "screenshot", "session"))
  line = paste0("artifact  marker-explorer  ->  http://127.0.0.1:4827/?gptr_token=00ff   ",
                "(running in background)")
  expect_identical(format(h), c(line, "checks: parse ok | launch ok | http ok | session skipped",
                                "  HTTP-only check"))
  expect_identical(utils::capture.output(print(h))[1], line)
  h$status = "stopped"
  h$url = NA_character_
  h$checks = artifact_checks()
  expect_identical(format(h), paste0("artifact  marker-explorer  ->  ",
                                     ".gptr/artifacts/marker-explorer/app.R   (stopped)"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`; the four tests error with `could not find function "artifact_id_check"` (and `"artifact_dir"`, `"artifact_meta_new"`, `"new_gptr_artifact"`).

- [ ] **Step 3: Write the implementation**

Create `R/artifact-app.R`:

```r
# Artifacts: Shiny apps launched from the live session in supervised background R processes
# (S-5, REQ-39; architecture 5.7 and 6.15; contract 5.10, 7.23, 9.4 and 11.6). The model writes
# <root>/artifacts/<id>/app.R and calls peter$app(id, data =) inside r: static checks of the
# working copy, an immutable vNNN/ snapshot (app.R, R/gptr_data.R, data/001.rds, ...), a callr
# child serving that version on a random loopback port behind a per-launch access token, the
# HTTP 200 check through the reactor and, with chromote, a headless session check with a
# 1000x700 screenshot. Adapted from report 17 sections 4-5 (the verified artifact_lib3.R and
# art_session_check.R) with the fixes of its verification log (items 6, 9, 12 and 42).

#' Package state of the artifact area: the process table (id -> record environment), the shared
#' headless browser and the once-per-process orphan-sweep flag (architecture 2.2 rule 5)
#' @noRd
artifact_state = new.env(parent = emptyenv())
artifact_state$procs = new.env(parent = emptyenv())
artifact_state$browser = NULL
artifact_state$swept = FALSE

#' Windows reserved device names, refused as artifact ids (IC-63)
#' @noRd
artifact_reserved = c("con", "aux", "nul", "prn", paste0("com", 1:9), paste0("lpt", 1:9))

#' Seconds a launch may take to publish its port and to answer HTTP (report 17 section 3.4)
#' @noRd
artifact_launch_timeout = 30

#' Seconds between the interrupt and the tree kill of a stop (report 17 section 2.2: 2 s was
#' exceeded once under load)
#' @noRd
artifact_stop_grace = 3

#' Size of the session-check screenshot (architecture 6.15: about 900 Claude tokens)
#' @noRd
artifact_shot_size = c(width = 1000L, height = 700L)

#' Validate an artifact id (contract 11.6, IC-63); returns it invisibly
#' @noRd
artifact_id_check = function(id) {
  check_string(id, "id")
  if (!grepl("^[a-z0-9][a-z0-9-]{0,62}$", id) || id %in% artifact_reserved) {
    gptr_abort(paste0("`id` must be 1-63 lower-case letters, digits or '-', start with a letter ",
                      "or a digit, and not be a Windows device name (con, aux, nul, prn, ",
                      "com1-com9, lpt1-lpt9)."),
               "invalid_argument", arg = "id",
               expected = "an artifact id such as \"marker-explorer\"")
  }
  invisible(id)
}

#' The artifacts directory: <workspace root>/artifacts (.gptr in a workspace, else
#' tempdir()/gptr; architecture 5.7). Nothing is created here.
#' @noRd
artifact_root = function() file.path(workspace_root(create = FALSE), "artifacts")

#' The directory of one artifact
#' @noRd
artifact_dir = function(id) file.path(artifact_root(), id)

#' The immutable directory of one version: v001, v002, ...
#' @noRd
artifact_version_dir = function(id, n) {
  file.path(artifact_dir(id), sprintf("v%03d", as.integer(n)))
}

#' The model-written working copy of a kind: app.R (shiny), page.html (html), else the directory
#' @noRd
artifact_working_file = function(dir, kind) {
  if (identical(kind, "shiny")) return(file.path(dir, "app.R"))
  if (identical(kind, "html")) return(file.path(dir, "page.html"))
  dir
}

#' ISO 8601 UTC time with milliseconds (contract 1.2)
#' @noRd
artifact_time = function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")

#' The id of the session behind a `ctx` (NULL for user calls, where `ctx` is NULL)
#' @noRd
artifact_session_id = function(ctx) {
  s = ctx$session
  if (is.null(s)) return(NULL)
  tryCatch(session_data(s)$id, error = function(e) NULL)
}

#' Path of artifact.json
#' @noRd
artifact_meta_path = function(id) file.path(artifact_dir(id), "artifact.json")

#' Does an artifact exist (has an artifact.json)?
#' @noRd
artifact_exists = function(id) file.exists(artifact_meta_path(id))

#' Read artifact.json (NULL when absent or unreadable)
#' @noRd
artifact_meta_read = function(id) {
  path = artifact_meta_path(id)
  if (!file.exists(path)) return(NULL)
  tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
}

#' Write artifact.json atomically (contract 11.6), stamping `updated`; unknown keys are kept
#' @noRd
artifact_meta_write = function(id, meta) {
  meta$updated = artifact_time()
  dir.create(artifact_dir(id), recursive = TRUE, showWarnings = FALSE)
  write_utf8(artifact_meta_path(id), json_encode(meta, pretty = TRUE))
  invisible(meta)
}

#' A new artifact.json record (`port` stays a JSON null until a launch publishes one)
#' @noRd
artifact_meta_new = function(id, title = NULL, kind = "shiny") {
  now = artifact_time()
  list(id = id, title = title %||% id, kind = kind, versions = list(), current = 0L,
       port = NULL, created = now, updated = now)
}

#' The version record numbered `n` of a metadata list, or NULL
#' @noRd
artifact_version_record = function(meta, n) {
  for (v in meta$versions) if (identical(as.integer(v$n), as.integer(n))) return(v)
  NULL
}

#' Set `current` in artifact.json
#' @noRd
artifact_set_current = function(id, n) {
  meta = artifact_meta_read(id)
  meta$current = as.integer(n)
  invisible(artifact_meta_write(id, meta))
}

#' Store the checks of version `n` in artifact.json
#' @noRd
artifact_version_checks_set = function(id, n, checks) {
  meta = artifact_meta_read(id)
  for (i in seq_along(meta$versions)) {
    if (identical(as.integer(meta$versions[[i]]$n), as.integer(n))) {
      meta$versions[[i]]$checks = artifact_checks_json(checks)
    }
  }
  invisible(artifact_meta_write(id, meta))
}

#' The checks of a handle: parse, launch, http and session (TRUE, FALSE or NA) plus messages
#' @noRd
artifact_checks = function(parse = NA, launch = NA, http = NA, session = NA,
                           messages = character()) {
  list(parse = as.logical(parse), launch = as.logical(launch), http = as.logical(http),
       session = as.logical(session), messages = as.character(messages))
}

#' The JSON form of checks: the four flags with NA written as null (messages are not stored)
#' @noRd
artifact_checks_json = function(checks) {
  flag = function(x) if (length(x) != 1L || is.na(x)) NULL else isTRUE(x)
  list(parse = flag(checks$parse), launch = flag(checks$launch), http = flag(checks$http),
       session = flag(checks$session))
}

#' Checks read back from artifact.json (null becomes NA)
#' @noRd
artifact_checks_from_json = function(x) {
  artifact_checks(parse = x$parse %||% NA, launch = x$launch %||% NA, http = x$http %||% NA,
                  session = x$session %||% NA)
}

#' SHA-256 of a file's bytes
#' @noRd
artifact_file_sha = function(path) hash_sha256(readBin(path, "raw", file.size(path)))

#' Bytes on disk of an artifact directory (versions, data snapshots and logs)
#' @noRd
artifact_dir_bytes = function(id) {
  files = list.files(artifact_dir(id), recursive = TRUE, full.names = TRUE, all.files = TRUE)
  sum(as.numeric(file.size(files)), na.rm = TRUE)
}

#' Build a gptr_artifact handle (contract 5.10)
#' @noRd
new_gptr_artifact = function(id, title, kind, version, url = NA_character_, path,
                             status = "stopped", checks = artifact_checks(), screenshot = NULL,
                             session = NULL) {
  structure(list(id = id, title = title, kind = kind, version = as.integer(version),
                 url = as.character(url), path = path, status = status, checks = checks,
                 screenshot = screenshot, session = session),
            class = "gptr_artifact")
}

#' Format an artifact handle
#'
#' The first line is the NS-8 line `artifact  <id>  ->  <url>   (<status text>)`, where
#' `running` reads `running in background` (contract 5.10, IC-71); an artifact that is not
#' running shows its working copy instead of a URL. Then the checks, their messages and the
#' screenshot path.
#' @param x A `gptr_artifact` handle.
#' @param ... Unused.
#' @return A character vector of lines.
#' @export
#' @noRd
format.gptr_artifact = function(x, ...) {
  status = if (identical(x$status, "running")) "running in background" else x$status
  running = length(x$url) == 1L && !is.na(x$url) && identical(x$status, "running")
  target = if (running) x$url else path_rel(x$path)
  out = paste0("artifact  ", x$id, "  ->  ", target, "   (", status, ")")
  ck = x$checks
  flags = c(parse = ck$parse, launch = ck$launch, http = ck$http, session = ck$session)
  if (length(flags) == 4L && !all(is.na(flags))) {
    word = ifelse(is.na(flags), "skipped", ifelse(flags, "ok", "FAILED"))
    out = c(out, paste0("checks: ", paste(names(flags), word, collapse = " | ")))
  }
  if (length(ck$messages)) out = c(out, paste0("  ", ck$messages))
  if (!is.null(x$screenshot)) out = c(out, paste0("screenshot: ", path_rel(x$screenshot)))
  out
}

#' Print an artifact handle as plain UTF-8 lines on stdout (its messages are untrusted text and
#' never a format string, rule C1; stdout so that an `r` evaluation captures it, like P10's
#' member prints)
#' @param x A `gptr_artifact` handle.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_artifact = function(x, ...) {
  writeLines(as_utf8(format(x)))
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `devtools::document()` adds `S3method(format,gptr_artifact)` and `S3method(print,gptr_artifact)` to `NAMESPACE` (no Rd file: the methods carry `@noRd`); the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 41 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R NAMESPACE
git commit -m "feat(artifact): add artifact ids, metadata and the gptr_artifact handle"
```

### Task 2: Static checks (validation ladder stage 1)

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Task 1 (`path_rel()` messages through `artifact_dir()`); P01 `as_utf8()`, `read_utf8()`, `` `%||%` ``; P03 `secret_scan(code, tainted = character())` (`$findings`, a df with `rule` and `name`; rule `secret_file` is the G6 §3.8 secret-file read, level 3).
- Produces: `artifact_static_check(code)` -> `list(ok = lgl(1), stage = "parse" | "static" | "ok", messages = chr, packages = chr)` (never evaluates the code); the `check` functions of the two built-in `artifact_type` specs (04 §10.2 row 19, `function(dir, ctx)` -> `list(ok, messages)` plus `stage`): `artifact_check_shiny(dir, ctx)` (static checks of `<dir>/app.R`) and `artifact_check_html(dir, ctx)` (`<dir>/page.html` exists and is not empty); helpers `artifact_forbidden_calls`, `artifact_read_calls`, `artifact_path_args`, `artifact_call_name(fn)`, `artifact_calls(exprs)`, `artifact_packages(calls)`, `artifact_outside_reads(calls)`, `artifact_secret_reads(code)`, `artifact_ends_with_app(exprs)`.

Report 17 §5.1 `art_static_check()` with the two defects of its verification log fixed (item 12: empty code crashed with "attempt to select less than one element"; a last expression `shiny::shinyApp(ui, server)` was rejected because `as.character(last[[1]])[1]` is `"::"`), extended with architecture 6.15's rules ("parses; ends with `shinyApp()`; no `setwd()`, installs, `runApp()` or reads outside the snapshot") and IC-71's "static checks flag reads of `secret_file` paths at level 3": such an app is refused (stage `static`), since the artifact process runs model-written code. A version directory holds only `app.R`, `R/gptr_data.R` and `data/`, so any literal path except one under `data/` names a file the running app cannot see; strings containing a newline are inline data (`fread("a,b\n1,2")`), not paths. Missing packages are found with `system.file()` without loading anything (loading shiny in the parent would touch the RNG, IC-61). The call walk skips empty arguments by index (as P03's `scan_strings()` does): binding the empty symbol to a variable would make that variable unusable.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

test_that("static checks accept a well-formed app, also ending in shiny::shinyApp()", {
  skip_if_not_installed("shiny")
  res = artifact_static_check(ok_app)
  expect_true(res$ok)
  expect_identical(res$stage, "ok")
  expect_identical(res$messages, character())
  expect_identical(res$packages, "shiny")
  expect_true(artifact_static_check(sub("^shinyApp", "shiny::shinyApp", ok_app))$ok)
  allowed = c(ok_app[1:3],
              "  up = reactive(read.csv(input$file$datapath))",
              "  extra = readRDS('data/001.rds')",
              "  inline = utils::read.csv(text = 'a,b\\n1,2')",
              ok_app[4:6])
  expect_true(artifact_static_check(allowed)$ok)
})

test_that("static checks reject empty code and parse errors at the parse stage", {
  for (code in list("", character(), "   \n  ")) {
    res = artifact_static_check(code)
    expect_false(res$ok)
    expect_identical(res$stage, "parse")
  }
  res = artifact_static_check("ui = fluidPage(")
  expect_identical(res$stage, "parse")
  expect_match(res$messages, "does not parse", fixed = TRUE)
  expect_identical(artifact_static_check("# only a comment")$messages, "app.R has no expressions")
})

test_that("static checks name each forbidden pattern", {
  skip_if_not_installed("shiny")
  with_line = function(line) c(ok_app[1:5], line, ok_app[6])
  msg = function(code) {
    res = artifact_static_check(code)
    expect_false(res$ok)
    expect_identical(res$stage, "static")
    paste(res$messages, collapse = "\n")
  }
  expect_match(msg(with_line("setwd(tempdir())")), "setwd", fixed = TRUE)
  expect_match(msg(with_line("install.packages('DT')")), "install.packages", fixed = TRUE)
  expect_match(msg(with_line("if (FALSE) shiny::runApp('.')")), "runApp", fixed = TRUE)
  expect_match(msg(with_line("library(notARealPkg)")), "package(s) not installed: notARealPkg",
               fixed = TRUE)
  expect_match(msg(with_line("x = notARealPkg2::f()")), "notARealPkg2", fixed = TRUE)
  expect_match(msg(with_line("extra = read.csv('markers.csv')")),
               "not in its snapshot: read.csv(\"markers.csv\")", fixed = TRUE)
  expect_match(msg(with_line("x = readRDS('/home/me/big.rds')")), "readRDS(\"/home/me/big.rds\")",
               fixed = TRUE)
  expect_match(msg(with_line("key = readLines('.env')")), "secret file (level 3): .env",
               fixed = TRUE)
  expect_match(msg(c(ok_app[1:5], "app = shinyApp(ui, server)", "app")), "last expression",
               fixed = TRUE)
})

test_that("the shiny and html type checks look at the working copy", {
  skip_if_not_installed("shiny")
  local_artifact_project()
  dir = artifact_dir("nothing")
  dir.create(dir, recursive = TRUE)
  res = artifact_check_shiny(dir, NULL)
  expect_false(res$ok)
  expect_identical(res$stage, "parse")
  expect_match(res$messages, ".gptr/artifacts/nothing/app.R", fixed = TRUE)
  write_working("nothing", ok_app)
  expect_true(artifact_check_shiny(dir, NULL)$ok)
  expect_false(artifact_check_html(dir, NULL)$ok)
  write_working("nothing", "<html><body>hi</body></html>", "page.html")
  expect_true(artifact_check_html(dir, NULL)$ok)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 41 ]`; the four new tests error with `could not find function "artifact_static_check"` (and `"artifact_check_shiny"`).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- validation ladder stage 1: static checks of the working copy -----------------------------

#' Calls an app.R must not make: the app runs in its own process and version directory
#' (architecture 6.15: "no setwd(), installs, runApp()")
#' @noRd
artifact_forbidden_calls = c("setwd", "runApp", "runGadget", "runExample", "shinyAppDir",
                             "install.packages", "remove.packages", "update.packages",
                             "install_github", "install_cran", "install_local", "install_version",
                             "pkg_install", "q", "quit")

#' File-reading functions whose literal path arguments are checked against the snapshot
#' @noRd
artifact_read_calls = c(
  "read.csv", "read.csv2", "read.table", "read.delim", "read.delim2", "readRDS", "readLines",
  "scan", "load", "source", "sys.source", "file", "gzfile", "bzfile", "xzfile", "readBin",
  "readChar", "readRenviron", "fread", "read_csv", "read_csv2", "read_tsv", "read_delim",
  "read_lines", "read_file", "read_rds", "read_excel", "read_xlsx", "read_xls", "read_json",
  "read_parquet", "read_feather", "read_csv_arrow", "open_dataset", "qs_read", "qd_read",
  "qread", "vroom", "includeHTML", "includeMarkdown", "includeText"
)

#' Argument names that carry a path in those functions (unnamed arguments count too)
#' @noRd
artifact_path_args = c("file", "con", "path", "description", "input", "x", "dsn", "filename")

#' Name of a called function: `f`, `pkg::f` or `pkg:::f` give "f"; anything else NA
#' @noRd
artifact_call_name = function(fn) {
  if (is.name(fn)) return(as.character(fn))
  if (is.call(fn) && length(fn) == 3L && as.character(fn[[1L]])[1L] %in% c("::", ":::")) {
    return(as.character(fn[[3L]]))
  }
  NA_character_
}

#' Every call inside a list of expressions, depth first (an empty argument such as the one in
#' `d[, 1]` is skipped by index: binding the empty symbol to a variable would make it unusable)
#' @noRd
artifact_calls = function(exprs) {
  out = list()
  walk = function(e) {
    if (!is.call(e)) return(invisible(NULL))
    out[[length(out) + 1L]] <<- e
    for (i in seq_along(e)) {
      if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
    }
    invisible(NULL)
  }
  for (e in as.list(exprs)) walk(e)
  out
}

#' Packages an app uses: library(), require() and loadNamespace() with a literal name, and every
#' `pkg::`/`pkg:::` prefix (report 17 section 5.1 `art_static_check()`)
#' @noRd
artifact_packages = function(calls) {
  pkgs = character()
  loads = c("library", "require", "loadNamespace")
  for (cl in calls) {
    head = cl[[1L]]
    if (is.call(head) && as.character(head[[1L]])[1L] %in% c("::", ":::")) {
      pkgs = c(pkgs, as.character(head[[2L]]))
    }
    fn = artifact_call_name(head)
    if (is.na(fn) || !(fn %in% loads) || length(cl) < 2L) next
    args = as.list(cl)[-1L]
    if (isTRUE(args$character.only)) next
    nms = names(args) %||% rep("", length(args))
    k = which(nms %in% c("package", "x"))
    k = if (length(k)) k[1L] else which(!nzchar(nms))[1L]
    if (is.na(k) || identical(args[[k]], quote(expr = ))) next
    first = args[[k]]
    if (is.name(first) || (is.character(first) && length(first) == 1L)) {
      pkgs = c(pkgs, as.character(first))
    }
  }
  unique(pkgs)
}

#' Literal paths an app reads that are not in its snapshot (architecture 6.15: no reads outside
#' the snapshot). A version directory holds only app.R, R/gptr_data.R and data/, so every literal
#' path except one under data/ names a file the running app cannot see. Strings with a newline
#' are inline data (fread("a,b\n1,2")), not paths.
#' @noRd
artifact_outside_reads = function(calls) {
  out = character()
  for (cl in calls) {
    fn = artifact_call_name(cl[[1L]])
    if (is.na(fn) || !(fn %in% artifact_read_calls)) next
    args = as.list(cl)[-1L]
    nms = names(args) %||% rep("", length(args))
    for (j in seq_along(args)) {
      if (nzchar(nms[j]) && !(nms[j] %in% artifact_path_args)) next
      a = args[[j]]
      if (!is.character(a) || length(a) != 1L || is.na(a) || !nzchar(a)) next
      if (grepl("\n", a, fixed = TRUE)) next
      if (grepl("^data/[^/]", gsub("\\", "/", a, fixed = TRUE))) next
      out = c(out, paste0(fn, "(\"", a, "\")"))
    }
  }
  unique(out)
}

#' Secret files the code reads: the secret classifier's `secret_file` rule (IC-71, G6 3.8)
#' @noRd
artifact_secret_reads = function(code) {
  f = tryCatch(secret_scan(code)$findings, error = function(e) NULL)
  if (!is.data.frame(f) || !nrow(f)) return(character())
  hits = as.character(f$name[f$rule == "secret_file"])
  hits[is.na(hits) | !nzchar(hits)] = "a secret file"
  unique(hits)
}

#' Is the last top-level expression shinyApp(...) or shiny::shinyApp(...)? (report 17
#' verification log item 12: the prototype rejected the qualified form)
#' @noRd
artifact_ends_with_app = function(exprs) {
  last = exprs[[length(exprs)]]
  is.call(last) && identical(artifact_call_name(last[[1L]]), "shinyApp")
}

#' Static checks of app.R code without evaluating it (validation ladder stage 1)
#'
#' Report 17 section 5.1 `art_static_check()` with the two defects of its verification log fixed
#' (empty code; `shiny::shinyApp()` as the last expression), plus the reads outside the snapshot
#' of architecture 6.15 and the secret-file reads of IC-71 (level 3: the app is refused).
#' @return `list(ok, stage = "parse" | "static" | "ok", messages, packages)`
#' @noRd
artifact_static_check = function(code) {
  code = as_utf8(paste(code, collapse = "\n"))
  fail = function(stage, messages) {
    list(ok = FALSE, stage = stage, messages = messages, packages = character())
  }
  if (!nzchar(trimws(code))) return(fail("parse", "app.R is empty"))
  exprs = tryCatch(parse(text = code, keep.source = FALSE), error = function(e) e)
  if (inherits(exprs, "error")) {
    return(fail("parse", paste("app.R does not parse:", conditionMessage(exprs))))
  }
  if (!length(exprs)) return(fail("parse", "app.R has no expressions"))
  calls = artifact_calls(exprs)
  called = vapply(calls, function(cl) artifact_call_name(cl[[1L]]), character(1))
  msgs = character()
  bad = intersect(unique(called[!is.na(called)]), artifact_forbidden_calls)
  if (length(bad)) {
    msgs = c(msgs, paste0("remove the call(s) to ", paste(bad, collapse = ", "),
                          ": the app runs in its own process and version directory"))
  }
  pkgs = artifact_packages(calls)
  missing_pkgs = pkgs[!vapply(pkgs, function(p) nzchar(system.file(package = p)), logical(1))]
  if (length(missing_pkgs)) {
    msgs = c(msgs, paste0("package(s) not installed: ", paste(missing_pkgs, collapse = ", ")))
  }
  reads = artifact_outside_reads(calls)
  if (length(reads)) {
    msgs = c(msgs, paste0("app.R reads files that are not in its snapshot: ",
                          paste(reads, collapse = ", "),
                          "; pass the objects it needs with data = instead"))
  }
  secret = artifact_secret_reads(code)
  if (length(secret)) {
    msgs = c(msgs, paste0("app.R reads a secret file (level 3): ", paste(secret, collapse = ", ")))
  }
  if (!artifact_ends_with_app(exprs)) {
    msgs = c(msgs, "the last expression of app.R must be shinyApp(ui, server)")
  }
  list(ok = !length(msgs), stage = if (length(msgs)) "static" else "ok", messages = msgs,
       packages = pkgs)
}

#' The `check` of the shiny artifact type (contract 10.2 row 19): static checks of <dir>/app.R
#' @return `list(ok, messages, stage)`
#' @noRd
artifact_check_shiny = function(dir, ctx) {
  path = file.path(dir, "app.R")
  if (!file.exists(path)) {
    return(list(ok = FALSE, stage = "parse",
                messages = paste0("there is no app.R: write ", path_rel(path), " first")))
  }
  res = artifact_static_check(read_utf8(path)$text)
  list(ok = res$ok, messages = res$messages, stage = res$stage)
}

#' The `check` of the html artifact type: <dir>/page.html exists and is not empty
#' @noRd
artifact_check_html = function(dir, ctx) {
  path = file.path(dir, "page.html")
  if (!file.exists(path) || !isTRUE(file.size(path) > 0)) {
    return(list(ok = FALSE, stage = "parse",
                messages = paste0("there is no page.html: write ", path_rel(path), " first")))
  }
  list(ok = TRUE, messages = character(), stage = "ok")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 107 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): add the static checks of app.R"
```

### Task 3: Data snapshots and the `shiny` and `html` builds

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Tasks 1-2; P01 `save_rds(object, file, compress = FALSE)` [R7][leaf], `gptr_opt("artifact_max_bytes")` (default `5e8`), `write_utf8()`, `gptr_abort()`, `path_rel()`; tests: P01 `local_gptr_options()`, withr `with_dir()`.
- Produces: `artifact_snapshot(vdir, data, envir, id = basename(dirname(vdir)))` -> the `data` records of `artifact.json` (`list(name, file, class, dim, bytes)` per object, files `data/001.rds`, `data/002.rds`, ...; IC-63) and the loader `R/gptr_data.R`; signals `gptr_error_artifact_too_large` (parent `artifact`; fields `id`, `stage = "snapshot"`, `log`, `bytes`, `max`) before anything is written, and `gptr_error_invalid_argument` (`arg = "data"`) for missing objects; `artifact_data_facts(name, envir)` [R4][leaf], `artifact_data_save(name, envir, file)` [R7][leaf], `artifact_mb(bytes)`, `artifact_loader_lines(records)`, `artifact_version_claim(id)` -> int (the next `vNNN`, claimed with `dir.create()`); the `build` functions of the built-in types (04 §10.2 row 19, `function(id, dir, data, ctx)`): `artifact_build_shiny()` (copies the working `app.R` into the version directory) and `artifact_build_html()` (copies `page.html` and writes the wrapper `app.R`); `artifact_html_wrapper(names)`.

Report 17 §5.1 `art_snapshot()` with the contract's numbering (IC-63: "Data snapshots are `data/001.rds`, `data/002.rds`, ... with the mapping in `artifact.json`; the loader reads the file listed for each name"), so a data object named `a/b` snapshots as `data/001.rds` and the loader binds it as `` `a/b` `` (05 P23 acceptance 5). Shiny sources `R/*.R` of the app directory before `app.R` (report 17 §2.2, verified for shiny 1.13.0 and 1.14.0 by its verification log item 3), so the objects exist under their names when `app.R` runs. User objects are read only through two leaves: `artifact_data_facts()` returns primitives (class, dim, `object.size()`) and `artifact_data_save()` hands the object straight to `save_rds()` (R4, R7); `envir` is never kept (R1, R2). The total size is checked against `gptr.artifact_max_bytes` before anything is written (NS-11: "`pbmc` exceeds `gptr.artifact_max_bytes`, so `peter$app()` errors with advice"). The `html` kind is report 17 §2.5 "A" (verified: iframe `srcdoc`, so the page's CSS and JS are isolated from Bootstrap), with the data as `window.GPTR_DATA.<name>` and `</` escaped inside the script.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

test_that("objects are snapshotted as numbered files with a loader that binds their names", {
  local_artifact_project()
  e = new.env()
  e[["a/b"]] = 1:3
  e$markers = data.frame(gene = c("CD14", "LYZ"), p = c(0.01, 0.2))
  vdir = artifact_version_dir("snap", 1L)
  dir.create(vdir, recursive = TRUE)
  recs = artifact_snapshot(vdir, c("a/b", "markers", "a/b"), e)
  expect_length(recs, 2L)
  expect_identical(vapply(recs, function(r) r$file, ""), c("data/001.rds", "data/002.rds"))
  expect_identical(recs[[1]]$name, "a/b")
  expect_identical(recs[[2]]$class, "data.frame")
  expect_identical(as.integer(recs[[2]]$dim), c(2L, 2L))
  expect_identical(as.integer(recs[[1]]$dim), 3L)
  expect_gt(recs[[2]]$bytes, 0)
  expect_true(all(file.exists(file.path(vdir, "data", c("001.rds", "002.rds")))))
  loader = readLines(file.path(vdir, "R", "gptr_data.R"), encoding = "UTF-8")
  expect_identical(loader[2:3], c("`a/b` = readRDS(\"data/001.rds\")",
                                  "markers = readRDS(\"data/002.rds\")"))
  out = new.env()
  withr::with_dir(vdir, sys.source(file.path("R", "gptr_data.R"), envir = out))
  expect_identical(get("a/b", envir = out), 1:3)
  expect_identical(out$markers, e$markers)
  expect_identical(artifact_snapshot(vdir, character(), e), list())
})

test_that("missing objects and oversized snapshots are refused before anything is written", {
  local_artifact_project()
  local_gptr_options(artifact_max_bytes = 1000)
  e = new.env()
  e$big = as.numeric(1:10000)
  vdir = artifact_version_dir("big", 1L)
  dir.create(vdir, recursive = TRUE)
  cnd = expect_error(artifact_snapshot(vdir, "nope", e), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "data")
  expect_error(artifact_snapshot(vdir, "", e), class = "gptr_error_invalid_argument")
  cnd = expect_error(artifact_snapshot(vdir, "big", e), class = "gptr_error_artifact_too_large")
  expect_s3_class(cnd, "gptr_error_artifact")
  expect_identical(cnd$stage, "snapshot")
  expect_identical(cnd$id, "big")
  expect_identical(cnd$max, 1000)
  expect_gt(cnd$bytes, 1000)
  expect_match(conditionMessage(cnd), "gptr.artifact_max_bytes", fixed = TRUE)
  expect_false(dir.exists(file.path(vdir, "data")))
})

test_that("builds copy app.R, and the html build wraps page.html and names the data", {
  local_artifact_project()
  write_working("plain", ok_app)
  vdir = artifact_version_dir("plain", 1L)
  dir.create(vdir)
  artifact_build_shiny("plain", vdir, list(), NULL)
  expect_identical(readLines(file.path(vdir, "app.R")), ok_app)
  dir.create(artifact_version_dir("plain", 2L))
  unlink(file.path(artifact_dir("plain"), "app.R"))
  expect_error(artifact_build_shiny("plain", artifact_version_dir("plain", 2L), list(), NULL),
               class = "gptr_error_artifact")
  write_working("wrap", "<html><head></head><body>x</body></html>", "page.html")
  vdir = artifact_version_dir("wrap", 1L)
  dir.create(vdir)
  artifact_build_html("wrap", vdir, list(list(name = "markers")), NULL)
  expect_true(file.exists(file.path(vdir, "page.html")))
  code = readLines(file.path(vdir, "app.R"), encoding = "UTF-8")
  expect_true("gptr_names = c(\"markers\")" %in% code)
  expect_true(artifact_ends_with_app(parse(text = code)))
  expect_true("gptr_names = character()" %in% artifact_html_wrapper(character()))
})

test_that("version directories are claimed in order and never reused", {
  local_artifact_project()
  dir.create(artifact_dir("vers"), recursive = TRUE)
  expect_identical(artifact_version_claim("vers"), 1L)
  expect_identical(artifact_version_claim("vers"), 2L)
  unlink(artifact_version_dir("vers", 1L), recursive = TRUE)
  expect_identical(artifact_version_claim("vers"), 3L)
  expect_true(dir.exists(artifact_version_dir("vers", 3L)))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 107 ]`; the four new tests error with `could not find function "artifact_snapshot"` (and `"artifact_build_shiny"`, `"artifact_version_claim"`).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- immutable versions: data snapshots and the shiny and html builds -------------------------

#' Facts about one data object, read in a leaf that returns primitives only [R4][leaf]; NULL when
#' the name is not visible from `envir`
#' @noRd
artifact_data_facts = function(name, envir) {
  if (!exists(name, envir = envir, inherits = TRUE)) return(NULL)
  obj = get(name, envir = envir, inherits = TRUE)
  d = dim(obj)
  list(class = class(obj)[1L], dim = as.integer(if (is.null(d)) length(obj) else d),
       size = as.numeric(utils::object.size(obj)))
}

#' Serialise one data object through the leaf save_rds() wrapper [R7][leaf]; returns its bytes
#' @noRd
artifact_data_save = function(name, envir, file) {
  save_rds(get(name, envir = envir, inherits = TRUE), file, compress = FALSE)
  as.numeric(file.size(file))
}

#' Megabytes for messages
#' @noRd
artifact_mb = function(bytes) paste0(format(round(bytes / 1e6, 1), nsmall = 1), " MB")

#' Snapshot the objects named in `data` into <vdir>/data/001.rds, 002.rds, ... and write the
#' loader R/gptr_data.R (contract 11.6, IC-63)
#'
#' Names are free-form (`a/b` becomes data/001.rds; the mapping is in artifact.json). The total
#' `object.size()` is checked against `gptr.artifact_max_bytes` before anything is written.
#' `envir` is read only through leaf functions and never kept [R1][R2].
#' @return The `data` records of artifact.json: list(name, file, class, dim, bytes) per object.
#' @noRd
artifact_snapshot = function(vdir, data, envir, id = basename(dirname(vdir))) {
  data = unique(as.character(data))
  if (!length(data)) return(list())
  if (any(!nzchar(data) | grepl("[[:cntrl:]]", data))) {
    gptr_abort("Every name in `data` must be a non-empty object name.", "invalid_argument",
               arg = "data", expected = "names of objects in the session")
  }
  facts = lapply(data, artifact_data_facts, envir = envir)
  gone = data[vapply(facts, is.null, logical(1))]
  if (length(gone)) {
    gptr_abort(paste0("Objects named in `data` were not found where peter$app() was called: ",
                      paste(gone, collapse = ", "), "."),
               "invalid_argument", arg = "data",
               expected = "names of objects visible from the calling environment")
  }
  total = sum(vapply(facts, function(f) f$size, numeric(1)))
  max_bytes = as.numeric(gptr_opt("artifact_max_bytes"))
  if (total > max_bytes) {
    gptr_abort(paste0("The data of artifact ", id, " is ", artifact_mb(total), " (limit ",
                      artifact_mb(max_bytes), ", option gptr.artifact_max_bytes). Snapshot a ",
                      "subset or a summary instead: the rows and columns the app shows."),
               c("artifact_too_large", "artifact"), id = id, stage = "snapshot",
               log = character(), bytes = total, max = max_bytes)
  }
  dir.create(file.path(vdir, "data"), recursive = TRUE, showWarnings = FALSE)
  records = vector("list", length(data))
  for (i in seq_along(data)) {
    file = sprintf("data/%03d.rds", i)
    bytes = artifact_data_save(data[[i]], envir, file.path(vdir, file))
    records[[i]] = list(name = data[[i]], file = file, class = facts[[i]]$class,
                        dim = I(facts[[i]]$dim), bytes = bytes)
  }
  dir.create(file.path(vdir, "R"), showWarnings = FALSE)
  write_utf8(file.path(vdir, "R", "gptr_data.R"), artifact_loader_lines(records))
  records
}

#' Lines of R/gptr_data.R: each object bound under its own name, read from its numbered file
#' (shiny sources R/*.R into the parent environment of app.R, report 17 section 2.2)
#' @noRd
artifact_loader_lines = function(records) {
  binds = vapply(records, function(r) {
    paste0(deparse(as.name(r$name), backtick = TRUE), " = readRDS(\"", r$file, "\")")
  }, character(1))
  c("# Generated by gptr: the data snapshot of this artifact version.", binds)
}

#' Claim the next version number; dir.create() is the lock (report 17 section 2.2, E11)
#' @noRd
artifact_version_claim = function(id) {
  have = list.files(artifact_dir(id), pattern = "^v[0-9]{3,}$")
  n = if (length(have)) max(as.integer(sub("^v", "", have))) + 1L else 1L
  while (!dir.create(artifact_version_dir(id, n), showWarnings = FALSE)) n = n + 1L
  n
}

#' The `build` of the shiny artifact type (contract 10.2 row 19): copy the working app.R into
#' the version directory `dir` (the working copy lives in its parent)
#' @noRd
artifact_build_shiny = function(id, dir, data, ctx) {
  if (!isTRUE(file.copy(file.path(dirname(dir), "app.R"), file.path(dir, "app.R")))) {
    gptr_abort(paste0("Could not copy app.R of artifact ", id, " into ", path_rel(dir), "."),
               "artifact", id = id, stage = "snapshot", log = character())
  }
  invisible(dir)
}

#' The generated app.R of the html kind: page.html inside an iframe `srcdoc`, with the snapshot
#' as `window.GPTR_DATA` (report 17 section 2.5 A, verified: CSS and JS isolated from Bootstrap)
#' @noRd
artifact_html_wrapper = function(names) {
  quoted = vapply(names, function(n) deparse(n), character(1))
  vec = if (length(names)) paste0("c(", paste(quoted, collapse = ", "), ")") else "character()"
  c("# Generated by gptr: page.html inside a Shiny app; the data is window.GPTR_DATA.<name>.",
    "library(shiny)",
    paste0("html = paste(readLines(\"page.html\", warn = FALSE, encoding = \"UTF-8\"), ",
           "collapse = \"\\n\")"),
    paste0("gptr_names = ", vec),
    paste0("gptr_json = jsonlite::toJSON(mget(gptr_names, inherits = TRUE), ",
           "dataframe = \"columns\", auto_unbox = FALSE, digits = NA)"),
    "gptr_json = gsub(\"</\", \"<\\\\/\", gptr_json, fixed = TRUE)",
    "gptr_script = paste0(\"<script>window.GPTR_DATA = \", gptr_json, \";</script>\")",
    paste0("html = if (grepl(\"<head>\", html, fixed = TRUE)) sub(\"<head>\", ",
           "paste0(\"<head>\", gptr_script), html, fixed = TRUE) else paste0(gptr_script, html)"),
    paste0("ui = fluidPage(style = \"padding:0\", tags$iframe(srcdoc = html, ",
           "style = \"border:0;width:100%;height:95vh\"))"),
    "server = function(input, output, session) {}",
    "shinyApp(ui, server)")
}

#' The `build` of the html artifact type: copy page.html and write the wrapper app.R
#' @noRd
artifact_build_html = function(id, dir, data, ctx) {
  if (!isTRUE(file.copy(file.path(dirname(dir), "page.html"), file.path(dir, "page.html")))) {
    gptr_abort(paste0("Could not copy page.html of artifact ", id, " into ", path_rel(dir), "."),
               "artifact", id = id, stage = "snapshot", log = character())
  }
  names = vapply(data, function(r) r$name, character(1))
  write_utf8(file.path(dir, "app.R"), artifact_html_wrapper(names))
  invisible(dir)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 140 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): snapshot data into numbered files and build versions"
```

### Task 4: The child: `artifact_serve()` and the access token

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Tasks 1-3; P01 `port_candidates(n = 20L)`, `gptr_inform(message, class, ..., .once = NULL)` (class `notice`), `` `%||%` ``; P03 `child_env("artifact", set = c(...))`, `child_env_callr(env)`; Suggests openssl (`rand_bytes()`), and inside the child only: shiny (`shinyAppDir()`, `parseQueryString()`, `isolate()`, `runApp()`, `stopApp()`), httpuv (`startServer()`, `stopServer()`), later (`later()`), ps (`ps_handle()`, `ps_is_running()`); tests: callr `r_bg()`, P04 `kill_all(p, grace = 2)`, P01 `rscript_path()`, processx, curl.
- Produces: `artifact_serve(dir, port_file, parent_pid, token)` (04 §7.23; the callr child's entry); `artifact_token()` -> chr(1) 32 lower-case hex digits, or `""` with a one-time `gptr_message_notice`; `artifact_has_openssl()`, `artifact_shiny_available()` (seams for tests); `artifact_ports(id)` -> int (the artifact's previous port first, then 20 `port_candidates()`); `artifact_child_env(ports)` -> the callr environment (the `artifact` profile plus `GPTR_ARTIFACT_PORTS`, `R_LIBS` and the three values of callr's own default environment `callr::rcmd_safe_env()`: `R_TESTS = ""`, `R_BROWSER = "false"`, `R_PDFVIEWER = "false"`).

The child entry is report 17 §5.1 `art_child_main()` (verified) with the contract's changes: no `httpuv::randomPort()` (IC-61: it calls `sample()`; the candidates come from P01's RNG-free `port_candidates()`), a per-launch token (IC-71) and a watchdog that stops the app instead of quitting (so the child reports and returns). It is self-contained (base R and `pkg::` calls only) and runs with `callr::r_bg(package = FALSE)`: the child never loads gptr, so it behaves the same under an installed gptr and under `devtools::load_all()` (report 17 §4.2 names this fallback; see Self-review ambiguity 1), and model-written code in the child cannot reach gptr internals. Because the signature of 04 §7.23 is fixed, the parent passes the candidate ports in the child's environment (`GPTR_ARTIFACT_PORTS`), previous port first, so a revision keeps its URL (report 17 E12: "v2 on the SAME URL"). In order, the child: builds the app with `shiny::shinyAppDir()`, which in shiny 1.13.0 evaluates `appObj()` eagerly (it reads `appObj()$options`), so `R/gptr_data.R` and `app.R` are sourced now and a broken UI ends the child before a port exists (stage `launch`); wraps the HTTP handler and the server function so that the page request and every Shiny session must carry `gptr_token=<token>` (403 for a page request without it; a session without it is closed; static assets carry no data); binds the first free candidate on `127.0.0.1` and publishes it by writing `<port_file>.tmp` and renaming it; starts the watchdog (`later`, every second; report 17 E2: "only SIGKILL without supervise/watchdog orphans the child"); runs `shiny::runApp()`. With the empty `R_PROFILE_USER` of IC-60, callr's own profile does not run in the child (so its error handler cannot print the error and the child does not inherit the parent's library paths through it): the child reports errors itself on stderr (`Error: <message>`) and the parent passes `R_LIBS`. Passing `env =` also replaces callr's default `callr::rcmd_safe_env()` (`R_TESTS = ""`, `R_BROWSER = "false"`, `R_PDFVIEWER = "false"`), so the parent sets those three itself: `R CMD check` runs the tests with `R_TESTS=startup.Rs`, a relative path that R's base profile sources in every R child, and a child started in its version directory halts with "cannot open file 'startup.Rs'" (reproduced in the review run with `R_TESTS=startup.Rs Rscript -e 'cat(1)'`: exit status 1), which would fail every launch under `devtools::check()` (it sets `NOT_CRAN=true`); `R_BROWSER = "false"` also keeps model-written code in the child from opening a browser (13 C-42). The token comes from `openssl::rand_bytes(16)`, else `/dev/urandom` opened with `raw = TRUE` (a plain `file()` warns "'raw = FALSE' but '/dev/urandom' is not a regular file", observed in this plan's scratch run), never from R's RNG.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

skip_if_cannot_launch = function() {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
}

tiny_app = c("library(shiny)", "ui = fluidPage('hi')", "server = function(input, output) {}",
             "shinyApp(ui, server)")

# A version directory built from app lines (and data objects of `envir`)
build_version = function(id, lines, data = character(), envir = new.env()) {
  write_working(id, lines)
  n = artifact_version_claim(id)
  vdir = artifact_version_dir(id, n)
  artifact_snapshot(vdir, data, envir, id = id)
  artifact_build_shiny(id, vdir, list(), NULL)
  vdir
}

# Run artifact_serve() in a callr child exactly as the launcher does; the child is killed when
# the calling test ends
serve_child = function(vdir, token, parent_pid = Sys.getpid(), .env = parent.frame()) {
  port_file = file.path(withr::local_tempdir(.local_envir = .env), "port")
  raw = withr::local_tempfile(fileext = ".log", .local_envir = .env)
  p = callr::r_bg(artifact_serve,
                  args = list(dir = vdir, port_file = port_file, parent_pid = parent_pid,
                              token = token),
                  stdout = raw, stderr = "2>&1", supervise = TRUE, package = FALSE,
                  user_profile = FALSE, system_profile = FALSE,
                  env = artifact_child_env(port_candidates(5L)), cleanup = TRUE,
                  cleanup_tree = TRUE, encoding = "UTF-8", wd = vdir)
  withr::defer(kill_all(p, grace = 0), envir = .env)
  deadline = Sys.time() + 30
  while (!file.exists(port_file) && p$is_alive() && Sys.time() < deadline) Sys.sleep(0.05)
  list(proc = p, port_file = port_file, raw = raw)
}

# Status of a GET (NA when nothing answers), polled until the app answers
http_status = function(url, wait = 15) {
  deadline = Sys.time() + wait
  repeat {
    h = curl::new_handle(followlocation = 0L)
    s = tryCatch(curl::curl_fetch_memory(url, handle = h)$status_code,
                 error = function(e) NA_integer_)
    if (!is.na(s) || Sys.time() > deadline) return(s)
    Sys.sleep(0.1)
  }
}

test_that("the access token is 128 random bits from openssl or /dev/urandom", {
  tok = artifact_token()
  expect_match(tok, "^[0-9a-f]{32}$")
  expect_false(identical(tok, artifact_token()))
  skip_on_os("windows")
  local_mocked_bindings(artifact_has_openssl = function() FALSE)
  expect_match(artifact_token(), "^[0-9a-f]{32}$")
})

test_that("ports come from port_candidates() after the artifact's previous port", {
  local_artifact_project()
  ports = artifact_ports("fresh")
  expect_length(ports, 20L)
  expect_true(all(ports >= 49152L & ports <= 65535L))
  meta = artifact_meta_new("old")
  meta$port = 51234L
  artifact_meta_write("old", meta)
  expect_identical(artifact_ports("old")[1], 51234L)
})

test_that("the child env is the artifact profile with ports, library paths and safe R vars", {
  withr::local_envvar(R_TESTS = "startup.Rs")
  env = artifact_child_env(c(50001L, 50002L))
  expect_identical(env[["GPTR_ARTIFACT_PORTS"]], "50001,50002")
  expect_identical(env[["R_LIBS"]], paste(.libPaths(), collapse = .Platform$path.sep))
  expect_true(nzchar(env[["R_PROFILE_USER"]]))
  expect_identical(unname(file.size(env[["R_PROFILE_USER"]])), 0)
  expect_identical(env[["R_TESTS"]], "")
  expect_identical(env[["R_BROWSER"]], "false")
})

test_that("artifact_serve() publishes a loopback port and serves only requests with the token", {
  skip_if_cannot_launch()
  local_artifact_project()
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  vdir = build_version("served", ok_app, "markers", e)
  tok = artifact_token()
  ch = serve_child(vdir, tok)
  expect_true(file.exists(ch$port_file))
  port = as.integer(readLines(ch$port_file))
  expect_true(port >= 49152L && port <= 65535L)
  base = sprintf("http://127.0.0.1:%d/", port)
  expect_identical(http_status(paste0(base, "?gptr_token=", tok)), 200L)
  expect_identical(http_status(base), 403L)
  expect_identical(http_status(paste0(base, "?gptr_token=", strrep("0", 32))), 403L)
  expect_identical(http_status(paste0(base, "shared/shiny.min.js")), 200L)
})

test_that("a broken app ends the child before a port exists, with its error on stderr", {
  skip_if_cannot_launch()
  local_artifact_project()
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  ch = serve_child(build_version("broken", broken), "")
  ch$proc$wait(10000)
  expect_false(ch$proc$is_alive())
  expect_false(file.exists(ch$port_file))
  log = readLines(ch$raw, warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("Error: .*no_such_object", log)))
})

test_that("the watchdog stops the app when the parent process is gone", {
  skip_if_cannot_launch()
  local_artifact_project()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  ch = serve_child(build_version("orphan", tiny_app), "", parent_pid = dead$get_pid())
  ch$proc$wait(15000)
  expect_false(ch$proc$is_alive())
  log = readLines(ch$raw, warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("parent R process is gone", log, fixed = TRUE)))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 140 ]`; the six new tests error with `could not find function "artifact_token"` (and `"artifact_ports"`, `"artifact_child_env"`); the two tests that go through `serve_child()` stop with `object 'artifact_serve' not found`.

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- the child process: artifact_serve() and the access token ---------------------------------

#' Is shiny installed? Checked without loading it (loading shiny touches the RNG, IC-61)
#' @noRd
artifact_shiny_available = function() nzchar(system.file(package = "shiny"))

#' Is openssl installed? (a seam for tests)
#' @noRd
artifact_has_openssl = function() requireNamespace("openssl", quietly = TRUE)

#' A per-launch 128-bit access token as 32 hex digits, or "" with a one-time notice (IC-71):
#' `openssl::rand_bytes(16)`, else /dev/urandom on Unix; never R's RNG (IC-61)
#' @noRd
artifact_token = function() {
  bytes = raw(0)
  if (artifact_has_openssl()) {
    bytes = openssl::rand_bytes(16L)
  } else if (.Platform$OS.type == "unix" && file.exists("/dev/urandom")) {
    con = file("/dev/urandom", open = "rb", raw = TRUE)
    on.exit(close(con), add = TRUE)
    bytes = readBin(con, "raw", 16L)
  }
  if (length(bytes) != 16L) {
    gptr_inform(paste0("Artifacts are served without an access token: install the openssl ",
                       "package so that other users of this computer cannot open them."),
                "notice", .once = "artifact_token")
    return("")
  }
  paste(sprintf("%02x", as.integer(bytes)), collapse = "")
}

#' Candidate ports of a launch: the artifact's previous port first (a revision keeps its URL,
#' report 17 section 2.2, E12), then RNG-free candidates (IC-61)
#' @noRd
artifact_ports = function(id) {
  prev = suppressWarnings(as.integer(artifact_meta_read(id)$port %||% NA_integer_))
  unique(c(if (length(prev) == 1L && !is.na(prev)) prev, port_candidates(20L)))
}

#' The secret-free `artifact` environment in callr form (IC-60, G6 3.7), with the candidate
#' ports and this process's library paths (the child gets no R profile that could set them)
#'
#' Passing `env =` to callr replaces its default `callr::rcmd_safe_env()`, so its three values
#' are set here: R CMD check runs tests with `R_TESTS=startup.Rs` (a relative path that R's base
#' profile sources in every R child: a child started in its version directory would halt), and
#' `R_BROWSER`/`R_PDFVIEWER = "false"` keep model-written code from opening a viewer.
#' @noRd
artifact_child_env = function(ports) {
  set = c(GPTR_ARTIFACT_PORTS = paste(ports, collapse = ","),
          R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
          R_TESTS = "", R_BROWSER = "false", R_PDFVIEWER = "false")
  child_env_callr(child_env("artifact", set = set))
}

#' Serve one artifact version; the entry point of the callr child (contract 7.23)
#'
#' Self-contained (base R and `pkg::` calls only): callr runs it with `package = FALSE`, so the
#' child never loads gptr and works the same under an installed gptr and under
#' `devtools::load_all()` (report 17 section 4.2 names this fallback). In order: a parent-PID
#' watchdog (`later`, every second; report 17 section 2.2, E2: with it no child outlives a
#' SIGKILLed parent) that stops the app when the parent is gone; `shiny::shinyAppDir()`, which
#' sources app.R and R/gptr_data.R now, so a broken UI ends the child before a port exists
#' (validation stage `launch`); the page request and every Shiny session are checked for
#' `gptr_token=<token>` (IC-71: a page request without it gets 403, a session without it is
#' closed; static assets carry no data); the first candidate port that binds on 127.0.0.1 (the
#' parent passes the previous port first, then `port_candidates()`, in `GPTR_ARTIFACT_PORTS`;
#' `httpuv::randomPort()` is never used, IC-61) is published by atomic rename of `port_file`;
#' then `shiny::runApp()`. The child reports its own errors on stderr ("Error: <message>") and
#' returns: with the empty `R_PROFILE_USER` of IC-60, callr's error handler in the child cannot
#' find its `tools:callr` environment and would print only that (verified with callr 3.7.6).
#' @param dir chr(1) the version directory.
#' @param port_file chr(1) where the chosen port is published.
#' @param parent_pid int(1) the gptr process; the app stops when it is gone.
#' @param token chr(1) the access token ("" = no token).
#' @noRd
artifact_serve = function(dir, port_file, parent_pid, token) {
  report = function(e) {
    message("Error: ", conditionMessage(e))
    invisible(NULL)
  }
  query_ok = function(query) {
    if (!nzchar(token)) return(TRUE)
    q = shiny::parseQueryString(if (is.null(query)) "" else query)
    identical(q$gptr_token, token)
  }
  parent = tryCatch(ps::ps_handle(as.integer(parent_pid)), error = function(e) NULL)
  watchdog = function() {
    up = !is.null(parent) && isTRUE(tryCatch(ps::ps_is_running(parent), error = function(e) FALSE))
    if (!up) {
      message("gptr: the parent R process is gone; stopping the app")
      shiny::stopApp()
      return(invisible(NULL))
    }
    later::later(watchdog, 1)
  }
  app = tryCatch(shiny::shinyAppDir(dir), error = function(e) e)
  if (inherits(app, "error")) return(report(app))
  inner_http = app$httpHandler
  inner_server = app$serverFuncSource
  app$httpHandler = function(req) {
    path = req$PATH_INFO
    if ((is.null(path) || path %in% c("", "/")) && !query_ok(req$QUERY_STRING)) {
      return(list(status = 403L, headers = list("Content-Type" = "text/plain; charset=UTF-8"),
                  body = "Forbidden: open this artifact with the URL that gptr printed.\n"))
    }
    inner_http(req)
  }
  app$serverFuncSource = function() {
    server = inner_server()
    function(input, output, session) {
      if (!query_ok(shiny::isolate(session$clientData$url_search))) {
        session$close()
        return(invisible(NULL))
      }
      args = list(input = input, output = output)
      if (any(c("session", "...") %in% names(formals(server)))) args$session = session
      do.call(server, args)
    }
  }
  ports = suppressWarnings(as.integer(strsplit(Sys.getenv("GPTR_ARTIFACT_PORTS"), ",",
                                               fixed = TRUE)[[1L]]))
  port = NA_integer_
  for (p in unique(ports[!is.na(ports)])) {
    srv = tryCatch(httpuv::startServer("127.0.0.1", p, list()), error = function(e) NULL)
    if (!is.null(srv)) {
      httpuv::stopServer(srv)
      port = p
      break
    }
  }
  if (is.na(port)) return(report(simpleError("no free loopback port among the candidates")))
  tmp = paste0(port_file, ".tmp")
  writeLines(as.character(port), tmp)
  if (!file.rename(tmp, port_file)) return(report(simpleError("could not publish the port")))
  later::later(watchdog, 1)
  res = tryCatch(shiny::runApp(app, port = port, host = "127.0.0.1", launch.browser = FALSE,
                               quiet = FALSE),
                 error = function(e) e)
  if (inherits(res, "error")) report(res)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 163 ]` (three R children start; a few seconds).

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): serve a version from a callr child behind an access token"
```

### Task 5: The artifact process table: records, status, stop, logs, events and the orphan sweep

**Files:**
- Create: `R/artifact-registry.R`
- Test: `tests/testthat/test-artifact-registry.R` (create; Task 10 appends)

**Interfaces:**
- Consumes: Tasks 1-4; P01 `read_utf8()`, `write_utf8()`, `json_encode()`, `json_decode()`, `raw_to_utf8()`, `as_utf8()`, `path_rel()`, `path_norm()`, `ev_new(type, ...)`, `gptr_abort()`; P02 `ev_dispatch(event, payload, session = NULL, ctx = NULL)`; P03 `redact_stream("persist")` (`push(chunk)` -> text safe to emit now, `flush()` -> the rest); P04 `pid_alive(pid, create_time = NULL)`, `job_add(kind, id, name, pid = NA, stop, status = function() "running")`, `job_remove(id)`; P06 kernel SDK `run_current()`, `run_emit(run, type, ...)`; ps `ps_handle()`, `ps_create_time()`, `ps_kill()`; tests: P02 `hook_add()`, `hook_remove()`, P03 `secret_register()`, `vault_reset()`, P04 `kill_all()`, `job_list(kind = NULL)`, P01 `rscript_path()`, processx.
- Produces: `artifact_proc_get(id)` -> record environment or `NULL`; `artifact_record_new(id, version, type, handle)` (fields `id`, `version`, `type`, `handle`, `url`, `pid`, `port`, `create_time`, `raw`, `offset`, `log`, `rs`, `stop_requested`, `checks`, `screenshot`, `started`); `artifact_status(id)` -> `"running"`, `"stopped"` or `"failed"` (IC-60: a requested stop never reads `failed`); `artifact_rec_alive(rec)`; `artifact_create_time(pid)`; `artifact_log_new(raw, log)`, `artifact_append(path, text)`, `artifact_log_sync(rec, final = FALSE)` (IC-70), `artifact_log_tail(log, n = 30L)`, `artifact_tail_text(tail, log)`; `artifact_run_write(rec)` (`run/run.json`: the contract's `pid`, `port`, `url`, `version`, `started` plus `create_time`, `parent_pid`, `parent_create_time` for the sweep), `artifact_run_clear(id)`; `artifact_emit(type, ...)` (through `run_emit()` inside a run, else `ev_dispatch()` with `session = NULL`); `artifact_job_id(id)` (`"artifact:<id>"`), `artifact_job_add(id, name, pid)`; `artifact_stop(id, reason = "user", emit = TRUE)` -> `invisible(lgl(1))` (emits `artifact_stop` with `id`, `url`, `version`, `reason` when a process was running); `artifact_handle(id)` -> `gptr_artifact` (signals `gptr_error_invalid_argument` for an unknown id); `artifact_sweep()` -> killed ids, invisibly; `artifact_sweep_once()`.

The table follows architecture 2.2 rule 5 ("the artifact and job process tables (to stop children on unload)") and report 17 §5.1 (`artifact_stop()`, `art_sweep_orphans()`, `artifacts()`), with the verification-log fixes: a stopped child's exit status is never read as a failure (item 9: callr 3.8.0 exits with status 1 after an interrupt; IC-60 maps any exit after a requested stop to `stopped`), and the sweep runs lazily, never at package load (item 42). A record holds the type spec and the handle that the type's `launch()` returned (closures over the child process only), never a user object or frame (R1, R2). Child output is persisted only through gptr (IC-70): the child writes to a raw file in `tempdir()`; `artifact_log_sync()` copies the new complete lines (bytes up to the last newline, so neither a UTF-8 sequence nor a secret is split) through `redact_stream("persist")` into `run/app-vNNN.log` (open, append, close; IC-59) and, at the end, flushes the redactor and deletes the raw file. The sweep reads every `run/run.json` of the workspace: a child is killed only when its owning R process is gone (pid and creation time) and its own pid still runs with the recorded creation time (report 17 verification log item 13: the PID-reuse guard spared a reused pid). Events go through the running run when there is one (`run_emit()`: session listeners such as the `r` tool's path collector first, then registry hooks such as P14's NS-8 line), else process-wide.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-artifact-registry.R`:

```r
# Tests of R/artifact-registry.R (P23). Tests that start processes skip on CRAN.

# A temporary project with a .gptr/ workspace; artifacts live in <project>/.gptr/artifacts
local_artifact_project = function(.env = parent.frame()) {
  local_project(.env = .env)
}

# An artifact.json with `n` versions (current = n); returns the id invisibly
seed_artifact = function(id, n = 1L, kind = "shiny") {
  meta = artifact_meta_new(id, paste("Title of", id), kind)
  meta$versions = lapply(seq_len(n), function(i) {
    dir.create(artifact_version_dir(id, i), recursive = TRUE, showWarnings = FALSE)
    list(n = i, created = artifact_time(), app_sha = NULL, data = list(), session = NULL,
         checks = artifact_checks_json(artifact_checks(parse = TRUE)))
  })
  meta$current = as.integer(n)
  artifact_meta_write(id, meta)
  invisible(id)
}

# A sleeping R child with a handle shaped like the launcher's (closures over the process only).
# R_TESTS is blanked: R CMD check sets it to a relative startup file that R's base profile
# sources in every R child, which would end the child at once (as callr::rcmd_safe_env() does)
sleeper_handle = function(.env = parent.frame()) {
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"),
                            env = c("current", R_TESTS = ""), cleanup = TRUE,
                            cleanup_tree = TRUE)
  withr::defer(kill_all(p, grace = 0), envir = .env)
  list(url = "http://127.0.0.1:50000/?gptr_token=ab", pid = p$get_pid(), port = 50000L,
       alive = function() p$is_alive(), stop = function() kill_all(p, grace = 1))
}

sleeper_type = list(stop = function(handle) handle$stop())

# Collect the payloads of an event for the calling test
local_events = function(event, .env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$events = list()
  id = hook_add(event, function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(id), envir = .env)
  seen
}

test_that("a record's status is running, then stopped after a requested stop (IC-60)", {
  skip_on_cran()
  local_artifact_project()
  seed_artifact("rec")
  stops = local_events("artifact_stop")
  expect_identical(artifact_status("rec"), "stopped")
  rec = artifact_record_new("rec", 1L, sleeper_type, sleeper_handle())
  assign("rec", rec, envir = artifact_state$procs)
  withr::defer(if (!is.null(artifact_proc_get("rec"))) artifact_stop("rec", emit = FALSE))
  expect_identical(artifact_status("rec"), "running")
  expect_false(is.na(rec$create_time))
  artifact_job_add("rec", "Title of rec", rec$pid)
  expect_identical(job_list("artifact")$id, "artifact:rec")
  expect_identical(job_list("artifact")$status, "running")
  expect_true(artifact_stop("rec"))
  expect_false(isTRUE(pid_alive(rec$pid, rec$create_time)))
  expect_identical(artifact_status("rec"), "stopped")
  expect_identical(nrow(job_list("artifact")), 0L)
  expect_length(stops$events, 1L)
  expect_identical(stops$events[[1]]$id, "rec")
  expect_identical(stops$events[[1]]$reason, "user")
  expect_identical(stops$events[[1]]$version, 1L)
  expect_false(artifact_stop("rec"))
})

test_that("a process that ends without a stop request reads failed", {
  skip_on_cran()
  local_artifact_project()
  seed_artifact("crash")
  h = sleeper_handle()
  rec = artifact_record_new("crash", 1L, sleeper_type, h)
  assign("crash", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("crash", emit = FALSE))
  ps::ps_kill(ps::ps_handle(h$pid))
  deadline = Sys.time() + 10
  while (h$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_identical(artifact_status("crash"), "failed")
})

test_that("child output reaches the log in complete lines, redacted, and the raw file goes", {
  local_artifact_project()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("sk-ant-", "api03-", strrep("FAKEartifact", 4L), "00AA")
  secret_register(fake, "GPTR_ARTIFACT_TEST_KEY", source = "test")
  raw = withr::local_tempfile(fileext = ".log")
  log = file.path(artifact_dir("logs"), "run", "app-v001.log")
  rec = artifact_log_new(raw, log)
  write_bytes = function(text) {
    con = file(raw, "ab")
    on.exit(close(con))
    writeBin(charToRaw(text), con)
  }
  write_bytes(paste0("Listening on http://127.0.0.1:5000\nkey=", fake, "\npartial"))
  artifact_log_sync(rec)
  got = readLines(log, encoding = "UTF-8")
  expect_identical(got[1], "Listening on http://127.0.0.1:5000")
  expect_false(any(grepl(fake, got, fixed = TRUE)))
  expect_false(any(grepl("partial", got, fixed = TRUE)))
  write_bytes(" line\nWarning: Error in f: boom\n")
  artifact_log_sync(rec, final = TRUE)
  got = readLines(log, encoding = "UTF-8")
  expect_true("partial line" %in% got)
  expect_identical(artifact_log_tail(log, 1L), "Warning: Error in f: boom")
  expect_false(file.exists(raw))
  expect_null(rec$raw)
  expect_identical(artifact_tail_text(character(), log), "")
  expect_match(artifact_tail_text("x", log), "Last lines of .gptr/artifacts/logs/run/app-v001.log",
               fixed = TRUE)
})

test_that("run.json carries the contract fields and the owner; the handle reads both tables", {
  skip_on_cran()
  local_artifact_project()
  seed_artifact("hand", n = 2L)
  expect_identical(artifact_handle("hand")$status, "stopped")
  expect_true(is.na(artifact_handle("hand")$url))
  rec = artifact_record_new("hand", 2L, sleeper_type, sleeper_handle())
  rec$checks = artifact_checks(TRUE, TRUE, TRUE, NA, "HTTP-only check")
  assign("hand", rec, envir = artifact_state$procs)
  withr::defer(artifact_stop("hand", emit = FALSE))
  artifact_run_write(rec)
  info = json_decode(read_utf8(file.path(artifact_dir("hand"), "run", "run.json"))$text)
  expect_true(all(c("pid", "port", "url", "version", "started") %in% names(info)))
  expect_identical(as.integer(info$parent_pid), Sys.getpid())
  h = artifact_handle("hand")
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "running")
  expect_identical(h$version, 2L)
  expect_identical(h$url, rec$url)
  expect_identical(h$title, "Title of hand")
  expect_identical(h$checks$messages, "HTTP-only check")
  expect_identical(basename(h$path), "app.R")
  artifact_stop("hand", emit = FALSE)
  expect_false(file.exists(file.path(artifact_dir("hand"), "run", "run.json")))
  expect_error(artifact_handle("absent"), class = "gptr_error_invalid_argument")
})

test_that("the orphan sweep kills children of dead owners and spares the rest", {
  skip_on_cran()
  local_artifact_project()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  plant = function(id, pid, create_time, owner) {
    seed_artifact(id)
    dir.create(file.path(artifact_dir(id), "run"), showWarnings = FALSE)
    write_utf8(file.path(artifact_dir(id), "run", "run.json"),
               json_encode(list(pid = pid, port = 50001L, url = "http://127.0.0.1:50001/",
                                version = 1L, started = artifact_time(),
                                create_time = create_time, parent_pid = owner)))
  }
  orphan = sleeper_handle()
  plant("orphan", orphan$pid, artifact_create_time(orphan$pid), dead$get_pid())
  reused = sleeper_handle()
  plant("reused", reused$pid, artifact_create_time(reused$pid) - 100, dead$get_pid())
  owned = sleeper_handle()
  owner = sleeper_handle()
  plant("owned", owned$pid, artifact_create_time(owned$pid), owner$pid)
  expect_identical(artifact_sweep(), "orphan")
  deadline = Sys.time() + 10
  while (orphan$alive() && Sys.time() < deadline) Sys.sleep(0.05)
  expect_false(orphan$alive())
  expect_true(reused$alive())
  expect_true(owned$alive())
  expect_false(file.exists(file.path(artifact_dir("orphan"), "run", "run.json")))
  expect_true(file.exists(file.path(artifact_dir("owned"), "run", "run.json")))
  expect_true(artifact_state$swept)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-registry")'
```

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`; the five tests error with `could not find function "artifact_status"` (and `"artifact_record_new"`, `"artifact_log_new"`, `"artifact_handle"`, `"artifact_create_time"`).

- [ ] **Step 3: Write the implementation**

Create `R/artifact-registry.R`:

```r
# The artifact process table (architecture 2.2 rule 5, 6.15; contract 5.10, 6.4, 11.6): one
# record per launched version, its status, stop, run files, redacted logs (IC-70), job-table
# rows (IC-12), the artifact_start/artifact_stop events (10.4), the handle builder and the lazy
# orphan sweep; Task 10 adds gptr_artifacts(). Adapted from report 17 section 5.1
# (artifact_stop(), art_sweep_orphans(), artifacts()).

#' The record of an artifact id in the process table, or NULL
#' @noRd
artifact_proc_get = function(id) get0(id, envir = artifact_state$procs, inherits = FALSE)

#' Creation time of a process in seconds since the epoch, NA when it cannot be read
#' @noRd
artifact_create_time = function(pid) {
  if (length(pid) != 1L || is.na(pid)) return(NA_real_)
  tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle(as.integer(pid)))),
           error = function(e) NA_real_)
}

#' Is the process of a record alive? (the handle's own probe when the type gives one, else the
#' pid with its creation time, so a reused pid never counts)
#' @noRd
artifact_rec_alive = function(rec) {
  probe = rec$handle$alive
  if (is.function(probe)) return(isTRUE(tryCatch(probe(), error = function(e) FALSE)))
  if (length(rec$pid) != 1L || is.na(rec$pid)) return(FALSE)
  isTRUE(pid_alive(rec$pid, rec$create_time))
}

#' A new record for a launched version (an environment: its log offset and flags change in
#' place)
#'
#' The record holds the type spec and the handle the type's `launch()` returned (closures over
#' the child process only), never a user object or frame [R1][R2].
#' @noRd
artifact_record_new = function(id, version, type, handle) {
  rec = new.env(parent = emptyenv())
  rec$id = id
  rec$version = as.integer(version)
  rec$type = type
  rec$handle = handle
  rec$url = as.character(handle$url %||% NA_character_)
  rec$pid = suppressWarnings(as.integer(handle$pid %||% NA_integer_))
  rec$port = suppressWarnings(as.integer(handle$port %||% NA_integer_))
  rec$create_time = artifact_create_time(rec$pid)
  rec$raw = handle$raw
  rec$offset = 0
  rec$log = handle$log %||% file.path(artifact_dir(id), "run",
                                      sprintf("app-v%03d.log", as.integer(version)))
  rec$rs = redact_stream("persist")
  rec$stop_requested = FALSE
  rec$checks = artifact_checks()
  rec$screenshot = NULL
  rec$started = artifact_time()
  rec
}

#' Status of an artifact: `running`; `stopped` (never started in this process, or stopped on
#' request: IC-60, a requested stop is never `failed`); `failed` (its launch or its process
#' failed without a stop request)
#' @noRd
artifact_status = function(id) {
  rec = artifact_proc_get(id)
  if (is.null(rec)) return("stopped")
  if (artifact_rec_alive(rec)) return("running")
  if (isTRUE(rec$stop_requested)) "stopped" else "failed"
}

#' A log record for raw child output: the raw file in tempdir(), the offset read so far, the
#' redacted log and its redaction stream
#' @noRd
artifact_log_new = function(raw, log) {
  rec = new.env(parent = emptyenv())
  rec$raw = raw
  rec$offset = 0
  rec$log = log
  rec$rs = redact_stream("persist")
  rec
}

#' Append text to a file: open, append, close (IC-59: no connection outlives the call)
#' @noRd
artifact_append = function(path, text) {
  text = paste(text, collapse = "")
  if (!nzchar(text)) return(invisible(path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con = file(path, "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(as_utf8(text)), con)
  invisible(path)
}

#' Move the new complete lines of a child's raw output into its redacted log (IC-70)
#'
#' `rec` holds `raw` (the child's stdout and stderr in tempdir()), `offset`, `log` and `rs` (a
#' `redact_stream("persist")`). Only bytes up to the last newline are taken, so neither a UTF-8
#' sequence nor a secret is split; `final = TRUE` takes the rest, flushes the redactor and
#' deletes the raw file.
#' @noRd
artifact_log_sync = function(rec, final = FALSE) {
  raw = rec$raw
  if (is.null(raw)) return(invisible(rec))
  size = if (file.exists(raw)) file.size(raw) else NA_real_
  if (!is.na(size) && size > rec$offset) {
    con = file(raw, "rb")
    on.exit(close(con), add = TRUE)
    seek(con, rec$offset)
    bytes = readBin(con, "raw", size - rec$offset)
    nl = which(bytes == as.raw(10L))
    take = if (final) length(bytes) else if (length(nl)) max(nl) else 0L
    if (take > 0L) {
      rec$offset = rec$offset + take
      artifact_append(rec$log, rec$rs$push(raw_to_utf8(bytes[seq_len(take)])))
    }
  }
  if (final) {
    artifact_append(rec$log, rec$rs$flush())
    unlink(raw)
    rec$raw = NULL
  }
  invisible(rec)
}

#' The last `n` non-empty lines of a redacted log
#' @noRd
artifact_log_tail = function(log, n = 30L) {
  if (is.null(log) || !file.exists(log)) return(character())
  lines = strsplit(read_utf8(log)$text, "\n", fixed = TRUE)[[1L]]
  utils::tail(lines[nzchar(trimws(lines))], n)
}

#' "Last lines of <log>:" for condition messages ("" without lines)
#' @noRd
artifact_tail_text = function(tail, log) {
  if (!length(tail)) return("")
  paste0("\nLast lines of ", path_rel(log), ":\n", paste(tail, collapse = "\n"))
}

#' Remove run/run.json and run/port of an artifact
#' @noRd
artifact_run_clear = function(id) {
  unlink(file.path(artifact_dir(id), "run", c("run.json", "port")))
  invisible(NULL)
}

#' Write run/run.json: the contract 11.6 fields (`pid`, `port`, `url`, `version`, `started`) plus
#' the creation times and owner the orphan sweep needs (report 17 section 3.1)
#' @noRd
artifact_run_write = function(rec) {
  opt = function(x) if (length(x) != 1L || is.na(x)) NULL else x
  info = list(pid = opt(rec$pid), port = opt(rec$port), url = rec$url, version = rec$version,
              started = rec$started, create_time = opt(rec$create_time),
              parent_pid = Sys.getpid(),
              parent_create_time = opt(artifact_create_time(Sys.getpid())))
  path = file.path(artifact_dir(rec$id), "run", "run.json")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_utf8(path, json_encode(info, pretty = TRUE))
}

#' Dispatch an artifact event (contract 10.4): through the running run when there is one
#' (session listeners such as the r tool's path collector, then registry hooks such as the
#' console's NS-8 line), else process-wide
#' @noRd
artifact_emit = function(type, ...) {
  run = run_current()
  if (!is.null(run)) return(invisible(run_emit(run, type, ...)))
  invisible(ev_dispatch(type, ev_new(type, ...), session = NULL))
}

#' The job-table id of an artifact (P04's table holds every kind of job)
#' @noRd
artifact_job_id = function(id) paste0("artifact:", id)

#' Add the job-table row of a running artifact (IC-12); the closures hold only the id
#' @noRd
artifact_job_add = function(id, name, pid) {
  job_add("artifact", artifact_job_id(id), name, pid = pid,
          stop = function() artifact_stop(id, reason = "jobs"),
          status = function() artifact_status(id))
}

#' Stop an artifact's process: the type's stop (for the built-in types: interrupt, 3 s grace,
#' kill_all()), then its run files, its log and its job row; emits `artifact_stop` when a
#' process was running (IC-60: a requested stop reads `stopped`, never `failed`)
#' @return invisible(TRUE) when there was a record, else invisible(FALSE)
#' @noRd
artifact_stop = function(id, reason = "user", emit = TRUE) {
  rec = artifact_proc_get(id)
  artifact_run_clear(id)
  if (is.null(rec)) return(invisible(FALSE))
  rec$stop_requested = TRUE
  was_running = artifact_rec_alive(rec)
  if (was_running) try(rec$type$stop(rec$handle), silent = TRUE)
  if (isTRUE(pid_alive(rec$pid, rec$create_time))) {
    try(ps::ps_kill(ps::ps_handle(rec$pid)), silent = TRUE)
  }
  artifact_log_sync(rec, final = TRUE)
  job_remove(artifact_job_id(id))
  rm(list = id, envir = artifact_state$procs)
  if (emit && was_running) {
    artifact_emit("artifact_stop", id = id, url = rec$url, version = rec$version,
                  reason = reason)
  }
  invisible(TRUE)
}

#' The gptr_artifact handle of an id, from artifact.json and the process table
#' @noRd
artifact_handle = function(id) {
  meta = artifact_meta_read(id)
  if (is.null(meta)) {
    gptr_abort("`id` does not name an existing artifact; see gptr_artifacts().",
               "invalid_argument", arg = "id", expected = "the id of an existing artifact")
  }
  current = as.integer(meta$current %||% 0L)
  vrec = artifact_version_record(meta, current)
  kind = vrec$kind %||% meta$kind %||% "shiny"
  rec = artifact_proc_get(id)
  if (!is.null(rec)) artifact_log_sync(rec, final = !artifact_rec_alive(rec))
  status = artifact_status(id)
  live = !is.null(rec) && identical(rec$version, current)
  new_gptr_artifact(
    id = id, title = meta$title %||% id, kind = kind, version = current,
    url = if (identical(status, "running")) rec$url else NA_character_,
    path = path_norm(artifact_working_file(artifact_dir(id), kind)), status = status,
    checks = if (live) rec$checks else artifact_checks_from_json(vrec$checks),
    screenshot = if (live) rec$screenshot else NULL, session = vrec$session
  )
}

#' Kill artifact children whose owning R process is gone (report 17 section 2.2, E11, with its
#' PID-reuse guard), then remove their run files
#'
#' A run/run.json is skipped when this process's table holds its child, or when its owner is
#' another live R process (pid and creation time). Otherwise the child is killed if its pid
#' still runs with the recorded creation time (a reused pid is never killed).
#' @return The ids whose child was killed, invisibly.
#' @noRd
artifact_sweep = function() {
  root = artifact_root()
  files = if (dir.exists(root)) Sys.glob(file.path(root, "*", "run", "run.json")) else character()
  killed = character()
  me = Sys.getpid()
  for (f in files) {
    id = basename(dirname(dirname(f)))
    info = tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
    pid = suppressWarnings(as.integer(info$pid %||% NA_integer_))
    rec = artifact_proc_get(id)
    if (!is.null(rec) && identical(rec$pid, pid)) next
    owner = suppressWarnings(as.integer(info$parent_pid %||% NA_integer_))
    other_owner = !is.na(owner) && !identical(owner, me) &&
      isTRUE(pid_alive(owner, info$parent_create_time))
    if (other_owner) next
    if (!is.na(pid) && !is.null(info$create_time) && isTRUE(pid_alive(pid, info$create_time))) {
      try(ps::ps_kill(ps::ps_handle(pid)), silent = TRUE)
      killed = c(killed, id)
    }
    unlink(file.path(dirname(f), c("run.json", "port")))
  }
  artifact_state$swept = TRUE
  invisible(killed)
}

#' The lazy orphan sweep: once per process, at the first peter$app() (report 17 verification log
#' item 42: never at package load)
#' @noRd
artifact_sweep_once = function() {
  if (!isTRUE(artifact_state$swept)) artifact_sweep()
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-registry")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 44 ]` (sleeping R children start and are killed; a few seconds).

- [ ] **Step 5: Commit**

```bash
git add R/artifact-registry.R tests/testthat/test-artifact-registry.R
git commit -m "feat(artifact): add the artifact process table, redacted logs and the orphan sweep"
```

### Task 6: The headless session check and screenshot

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Tasks 1-5 (`artifact_log_sync()`, `artifact_log_new()` in tests); P01 `with_seed_preserved(expr)` [leaf], `json_decode()`, `read_utf8()`, `` `%||%` ``; P04 `reactor_now()`, `reactor_pump(until, slice_ms, timeout)` (the 100 ms pause between state polls, so the wait never blocks other runs' transfers); Suggests chromote (`find_chrome()`, `Chromote$new()`, sessions with `Runtime`, `Page`, `wait_for()`, `captureScreenshot()`), jsonlite (`base64_dec()`); tests: Task 4's `serve_child()`, `build_version()`, `http_status()`, `ok_app`.
- Produces: `artifact_session_check(rec, png, width = 1000L, height = 700L, timeout = 20)` -> `list(ok = TRUE | FALSE | NA, messages = chr, screenshot = <png path> | NULL)` (`NA` = the check could not run: an HTTP-only check, which the messages say); `artifact_chromote_missing()` -> chr(1) reason or `NULL`; `artifact_browser()` (one headless browser per process) and `artifact_browser_close()`; `artifact_log_errors(log)` -> `list(errors, warnings)`; `artifact_log_messages(log)` -> chr; internal `artifact_session_browse()`, `artifact_session_run()`, `artifact_js_state`, `artifact_js_errors`, `artifact_js_validation`.

Report 17 §5.2 `art_session_check()` (verified; §2.3: HTTP 200 alone passes three broken apps, the session check catches all three and passes `validate(need())` messages) with its known gaps fixed: a warning's text is on the line after `Warning in ...` and is read with it; printed promises are silenced with `invisible()`; the load-event promise is registered before navigating (the first version raced). One headless browser per process (cold start about 3.4 s, later checks 1.1-2.1 s), closed by `artifact_browser_close()` (CRAN: "external software ... explicitly closed afterwards"). The screenshot is 1000x700 (03 §6.15, "about 900 tokens": `ceiling(1000/28) * ceiling(700/28)` = 900 Anthropic image tokens) instead of the report's 1100x750. The whole check runs inside `with_seed_preserved()`: `chromote::Chromote$new()` changes `.Random.seed` (report 17 verification log item 6; IC-61). Without chromote or a Chrome binary the check returns `ok = NA` with the message `HTTP-only check: <reason>; the page was not rendered` plus the server-log errors (report 17 §7 risk 4).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

skip_if_no_chrome = function() {
  skip_if_not_installed("chromote")
  skip_if(!is.null(artifact_chromote_missing()), "no Chrome or Chromium for chromote")
}

# A served version as a record the session check reads: its URL, its redacted log
served_record = function(id, lines, data = character(), envir = new.env(),
                         .env = parent.frame()) {
  tok = artifact_token()
  ch = serve_child(build_version(id, lines, data, envir), tok, .env = .env)
  port = as.integer(readLines(ch$port_file))
  rec = artifact_log_new(ch$raw, file.path(artifact_dir(id), "run", "app-v001.log"))
  rec$url = sprintf("http://127.0.0.1:%d/?gptr_token=%s", port, tok)
  expect_identical(http_status(rec$url), 200L)
  rec
}

test_that("server-log errors and warnings are read with the warning's text", {
  local_artifact_project()
  log = file.path(artifact_dir("log"), "app.log")
  dir.create(dirname(log), recursive = TRUE)
  writeLines(c("Listening on http://127.0.0.1:50000",
               "Warning in mean.default(x$revnue) :",
               "  argument is not numeric or logical: returning NA",
               "Warning: Error in xy.coords: 'x' and 'y' lengths differ",
               "  [No stack trace available]"), log)
  got = artifact_log_errors(log)
  expect_identical(got$errors, "Warning: Error in xy.coords: 'x' and 'y' lengths differ")
  expect_identical(got$warnings, paste("Warning in mean.default(x$revnue) :",
                                       "argument is not numeric or logical: returning NA"))
  expect_identical(artifact_log_messages(log)[1],
                   "server log: Warning: Error in xy.coords: 'x' and 'y' lengths differ")
  expect_identical(artifact_log_errors(file.path(dirname(log), "none.log")),
                   list(errors = character(), warnings = character()))
})

test_that("without chromote the check is HTTP-only: ok is NA and the messages say so", {
  local_artifact_project()
  local_mocked_bindings(artifact_chromote_missing = function() "chromote is not installed")
  rec = artifact_log_new(NULL, file.path(artifact_dir("none"), "run", "app-v001.log"))
  res = artifact_session_check(rec, tempfile(fileext = ".png"))
  expect_true(is.na(res$ok))
  expect_null(res$screenshot)
  expect_identical(res$messages,
                   "HTTP-only check: chromote is not installed; the page was not rendered")
})

test_that("the session check passes a working app and returns a 1000x700 screenshot", {
  skip_if_cannot_launch()
  skip_if_no_chrome()
  local_artifact_project()
  withr::defer(artifact_browser_close())
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  rec = served_record("good", ok_app, "markers", e)
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  png = file.path(artifact_dir("good"), "run", "shot.png")
  res = artifact_session_check(rec, png)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_true(res$ok)
  expect_identical(res$screenshot, png)
  bytes = readBin(png, "raw", 24L)
  expect_identical(bytes[1:4], as.raw(c(0x89, 0x50, 0x4e, 0x47)))
  expect_identical(c(readBin(bytes[17:20], "integer", endian = "big"),
                     readBin(bytes[21:24], "integer", endian = "big")), c(1000L, 700L))
})

test_that("the session check catches render errors and crashed servers but not validate()", {
  skip_if_cannot_launch()
  skip_if_no_chrome()
  local_artifact_project()
  withr::defer(artifact_browser_close())
  render_error = c("library(shiny)", "ui = fluidPage(plotOutput('p'))",
                   "server = function(input, output, session) {",
                   "  output$p = renderPlot(plot(1:3, 1:2))", "}", "shinyApp(ui, server)")
  res = artifact_session_check(served_record("render", render_error), tempfile(fileext = ".png"))
  expect_false(res$ok)
  expect_true(any(grepl("output error in p", res$messages, fixed = TRUE)))
  crash = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) undefined_helper()",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("crash", crash), tempfile(fileext = ".png"))
  expect_false(res$ok)
  expect_true(any(grepl("undefined_helper", res$messages, fixed = TRUE)))
  valid = c("library(shiny)", "ui = fluidPage(textOutput('t'))",
            "server = function(input, output, session) {",
            "  output$t = renderText(validate(need(FALSE, 'Pick a region')))", "}",
            "shinyApp(ui, server)")
  res = artifact_session_check(served_record("valid", valid), tempfile(fileext = ".png"))
  expect_true(res$ok)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 163 ]`; the four new tests error with `could not find function "artifact_log_errors"` (and `"artifact_session_check"`, `"artifact_chromote_missing"`).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- validation ladder stage 4: the headless session check and the screenshot ----------------

#' JavaScript: the Shiny connection state of the page (report 17 section 5.2)
#' @noRd
artifact_js_state = paste0(
  "(function(){var s = window.Shiny && Shiny.shinyapp; return JSON.stringify({",
  "connected: !!(s && s.isConnected && s.isConnected()), ",
  "busy: document.documentElement.classList.contains('shiny-busy'), ",
  "recalculating: document.querySelectorAll('.recalculating').length, ",
  "disconnected: !!document.getElementById('shiny-disconnected-overlay')});})()"
)

#' JavaScript: output errors that are not validate(need()) messages
#' @noRd
artifact_js_errors = paste0(
  "JSON.stringify(Array.from(document.querySelectorAll(",
  "'.shiny-output-error:not(.shiny-output-error-validation)')).map(function(e){",
  "return {id: e.id, message: e.textContent.trim()};}))"
)

#' JavaScript: validate(need()) messages (not errors)
#' @noRd
artifact_js_validation = paste0(
  "JSON.stringify(Array.from(document.querySelectorAll('.shiny-output-error-validation'))",
  ".map(function(e){return {id: e.id, message: e.textContent.trim()};}))"
)

#' Why the headless session check cannot run here, or NULL when it can
#' @noRd
artifact_chromote_missing = function() {
  if (!requireNamespace("chromote", quietly = TRUE)) return("chromote is not installed")
  chrome = tryCatch(chromote::find_chrome(), error = function(e) NULL)
  if (is.null(chrome) || !nzchar(chrome)) {
    return("no Chrome or Chromium was found (set CHROMOTE_CHROME)")
  }
  NULL
}

#' The process's headless browser, started once: the cold start costs about 3.4 s, later checks
#' 1.1-2.1 s (report 17 section 2.3)
#' @noRd
artifact_browser = function() {
  b = artifact_state$browser
  if (!is.null(b) && isTRUE(tryCatch(b$is_alive(), error = function(e) FALSE))) return(b)
  b = chromote::Chromote$new()
  artifact_state$browser = b
  b
}

#' Close the headless browser (CRAN: external software is closed explicitly, 13 C-42)
#' @noRd
artifact_browser_close = function() {
  b = artifact_state$browser
  artifact_state$browser = NULL
  if (!is.null(b)) try(b$close(), silent = TRUE)
  invisible(NULL)
}

#' Error and warning lines of a redacted server log; a warning's text is on its next line
#' (report 17 section 5.2, known gap)
#' @noRd
artifact_log_errors = function(log) {
  none = list(errors = character(), warnings = character())
  if (is.null(log) || !file.exists(log)) return(none)
  lines = strsplit(read_utf8(log)$text, "\n", fixed = TRUE)[[1L]]
  if (!length(lines)) return(none)
  err = grep("^(Warning: )?Error in|^Error", lines)
  warn = setdiff(grep("^Warning in|^Warning:", lines), err)
  warn_text = vapply(warn, function(i) {
    paste(trimws(c(lines[i], if (i < length(lines)) lines[i + 1L])), collapse = " ")
  }, character(1))
  list(errors = utils::tail(unique(lines[err]), 10L),
       warnings = utils::tail(unique(warn_text), 10L))
}

#' The server-log lines reported to the model
#' @noRd
artifact_log_messages = function(log) {
  logged = artifact_log_errors(log)
  c(if (length(logged$errors)) paste0("server log: ", logged$errors),
    if (length(logged$warnings)) paste0("server log warning: ", logged$warnings))
}

#' Load the page in headless Chrome; collect its state, errors and a PNG (base64)
#'
#' Report 17 section 5.2 `art_session_check()`: the load event is registered before navigating
#' (the first version raced), validate(need()) messages are not errors, the printed promises
#' are silenced with invisible(), and the session is closed on exit.
#' @noRd
artifact_session_browse = function(url, width, height, timeout) {
  b = artifact_browser()$new_session(width = width, height = height)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  seen = new.env(parent = emptyenv())
  seen$js = character()
  invisible(b$Runtime$enable())
  invisible(b$Runtime$exceptionThrown(callback_ = function(m) {
    d = m$exceptionDetails
    seen$js = c(seen$js, as.character(d$exception$description %||% d$text %||% "exception"))
  }))
  invisible(b$Runtime$consoleAPICalled(callback_ = function(m) {
    if (identical(m$type, "error")) {
      txt = vapply(m$args, function(a) as.character(a$value %||% a$description %||% ""),
                   character(1))
      seen$js = c(seen$js, paste(txt, collapse = " "))
    }
  }))
  loaded = b$Page$loadEventFired(wait_ = FALSE, timeout_ = timeout)
  invisible(b$Page$navigate(url, wait_ = FALSE))
  invisible(b$wait_for(loaded))
  eval_js = function(js) b$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  state = list()
  stable = 0L
  t0 = reactor_now()
  while (reactor_now() - t0 < timeout) {
    state = json_decode(eval_js(artifact_js_state))
    if (isTRUE(state$disconnected)) break
    idle = isTRUE(state$connected) && !isTRUE(state$busy) &&
      identical(as.integer(state$recalculating), 0L)
    stable = if (idle) stable + 1L else 0L
    if (stable >= 5L) break
    # the reactor is the only blocking wait (contract 8.2): other runs' transfers go on
    reactor_pump(until = function() FALSE, slice_ms = 50L, timeout = 0.1)
  }
  pairs = function(x) vapply(x, function(e) paste0(e$id, ": ", e$message), character(1))
  list(connected = isTRUE(state$connected), disconnected = isTRUE(state$disconnected),
       output_errors = pairs(json_decode(eval_js(artifact_js_errors))),
       validation = pairs(json_decode(eval_js(artifact_js_validation))),
       js_errors = unique(seen$js),
       png = b$Page$captureScreenshot(format = "png")$data)
}

#' The body of artifact_session_check()
#' @noRd
artifact_session_run = function(rec, png, width, height, timeout) {
  missing_why = artifact_chromote_missing()
  if (!is.null(missing_why)) {
    artifact_log_sync(rec)
    return(list(ok = NA, screenshot = NULL,
                messages = c(paste0("HTTP-only check: ", missing_why,
                                    "; the page was not rendered"),
                             artifact_log_messages(rec$log))))
  }
  res = tryCatch(artifact_session_browse(rec$url, width, height, timeout),
                 error = function(e) list(error = conditionMessage(e)))
  artifact_log_sync(rec)
  if (!is.null(res$error)) {
    return(list(ok = NA, screenshot = NULL,
                messages = c(paste0("the headless session check could not run: ", res$error),
                             artifact_log_messages(rec$log))))
  }
  logged = artifact_log_errors(rec$log)
  msgs = c(
    if (length(res$output_errors)) paste0("output error in ", res$output_errors),
    if (length(res$js_errors)) paste0("JavaScript error: ", res$js_errors),
    artifact_log_messages(rec$log),
    if (res$disconnected) "the Shiny session disconnected: the server function failed",
    if (!res$connected && !res$disconnected) {
      paste0("the Shiny session did not connect within ", timeout, " s")
    }
  )
  ok = res$connected && !res$disconnected && !length(res$output_errors) &&
    !length(res$js_errors) && !length(logged$errors)
  shot = NULL
  if (length(res$png) == 1L && nzchar(res$png)) {
    writeBin(jsonlite::base64_dec(res$png), png)
    shot = png
  }
  list(ok = ok, messages = msgs, screenshot = shot)
}

#' The headless session check with a 1000x700 screenshot (validation ladder stage 4)
#'
#' `ok` is NA when the check could not run (no chromote or no Chrome: an HTTP-only check, which
#' the messages say; report 17 section 7, risk 4), TRUE when the session connected with no
#' output, JavaScript or server-log errors, else FALSE. `.Random.seed` is preserved: chromote's
#' port picker calls sample() (report 17 verification log item 6; IC-61).
#' @return `list(ok, messages, screenshot = <png path> | NULL)`
#' @noRd
artifact_session_check = function(rec, png, width = artifact_shot_size[["width"]],
                                  height = artifact_shot_size[["height"]], timeout = 20) {
  with_seed_preserved(artifact_session_run(rec, png, width, height, timeout))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 184 ]` (four app children and one headless Chrome; about 15 s). Without chromote or a Chrome binary: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 170 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): add the headless session check and the screenshot"
```

### Task 7: Launch and the validation ladder

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Tasks 1-6; P01 `supervise_default()`, `path_norm()`, `gptr_has_human()`, `check_string()`, `gptr_abort()`; P02 `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)`; P04 `reactor_http(spec, on_bytes, on_done, on_fail, ..., retry = NULL)`, `reactor_pump(until, slice_ms, timeout)`, `reactor_cancel(ids)`, `reactor_now()`, `kill_all(p, grace)`; callr `r_bg()`; tests: P02 `hook_add()`, `hook_remove()`, P03 `secret_register()`, `vault_reset()`, P04 `job_list()`, ps `ps_environ()`, withr `local_envvar()`, `local_options()`, `local_seed()`.
- Produces: `artifact_launch_shiny(version_dir, ctx)` (the `launch` of both built-in types, 04 §10.2 row 19) -> `list(url, pid, stop)` plus `alive`, `port`, `token`, `raw`, `log`; signals `gptr_error_artifact` (stage `launch`, `log` = the redacted tail) when the child ends or publishes no port within 30 s, and `gptr_error_missing_package` (`package = "shiny"`, `feature = "artifacts"`); `artifact_stop_handle(handle)` (the `stop` of both types); `artifact_wait_port(proc, port_file, timeout = 30)`; `artifact_proc_fns(proc)`; `artifact_http_status(url, timeout = 3)` -> int or `NA`; `artifact_wait_http(url, alive, timeout = 30)` -> `list(ok, status, reason)`; `artifact_view(url)` -> `invisible(lgl(1))`; `artifact_type_get(kind, ctx = NULL)` -> the registered `artifact_type` spec (IC-69) or `gptr_error_invalid_argument` (`arg = "kind"`); `artifact_record_failed(id, version, type)`, `artifact_launch_failed(rec, checks)`; `artifact_start(id, version, type, ctx = NULL, session_check = FALSE)` -> the `gptr_artifact` handle (signals `gptr_error_artifact` with stage `launch` or `http`); `artifact_relaunch(id, version, ctx = NULL)`.

The launch is report 17 §5.1 `artifact_start()`/`art_wait()` (verified: v2 on the same URL; cleanup) with the contract's changes. The child is `callr::r_bg(artifact_serve, ..., supervise = supervise_default(), package = FALSE, user_profile = FALSE, system_profile = FALSE, env = artifact_child_env(...), cleanup = TRUE, cleanup_tree = TRUE, encoding = "UTF-8")` (IC-60; architecture 6.15) with the version directory as working directory, stdout and stderr in a raw file in `tempdir()` (IC-70). The parent pumps P04's reactor while it waits for the port file (no busy loop: the reactor sleeps between iterations) and checks HTTP 200 through the reactor (architecture 6.15: "checks HTTP 200 through the reactor"), one attempt per poll (`retry = list(max_attempts = 1L, committed = function() TRUE)`), so the wait never blocks other agents' transfers. The ladder: a child that ends before it publishes a port is the `launch` failure; an answer other than 200 is the `http` failure; both record the checks in `artifact.json`, leave the record with status `failed` and signal `gptr_error_artifact` whose message carries the redacted log tail, so the model sees the child's error (05 P23 acceptance 2); a failing session check is reported in the checks and messages, not raised (the model reads them with the screenshot). On success the run files, the port in `artifact.json` and the job row are written, `artifact_start` is emitted and, with a human present, the viewer opens (`getOption("viewer", utils::browseURL)`; 13 C-42: never outside an interactive session). The artifact's running process is stopped first and its port offered again, so a revision keeps its URL (the token changes with every launch).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

# The built-in shiny type as a record, before builtin:artifacts registers it (Task 9)
shiny_type = function() {
  list(build = artifact_build_shiny, check = artifact_check_shiny,
       launch = artifact_launch_shiny, stop = artifact_stop_handle)
}

# Collect the payloads of an event for the calling test
local_events = function(event, .env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$events = list()
  id = hook_add(event, function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(id), envir = .env)
  seen
}

# An artifact.json whose version 1 is `lines`, ready for artifact_start()
version_one = function(id, lines, data = character(), envir = new.env()) {
  vdir = build_version(id, lines, data, envir)
  meta = artifact_meta_new(id, paste("Title of", id))
  meta$versions = list(list(n = 1L, created = artifact_time(), data = list(), session = NULL,
                            checks = artifact_checks_json(artifact_checks(parse = TRUE))))
  meta$current = 1L
  artifact_meta_write(id, meta)
  vdir
}

test_that("the launcher serves a version on a random loopback port behind the token", {
  skip_if_cannot_launch()
  local_artifact_project()
  e = new.env()
  e$markers = data.frame(gene = c("CD14", "LYZ"))
  h = artifact_launch_shiny(build_version("hello", ok_app, "markers", e), NULL)
  withr::defer(h$stop())
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  expect_true(h$port >= 49152L && h$port <= 65535L)
  expect_true(h$alive())
  expect_identical(artifact_http_status(h$url), 200L)
  expect_identical(artifact_http_status(sprintf("http://127.0.0.1:%d/", h$port)), 403L)
  expect_true(artifact_wait_http(h$url, h$alive)$ok)
  expect_identical(basename(h$log), "app-v001.log")
  h$stop()
  expect_false(h$alive())
  expect_true(is.na(artifact_http_status(h$url, timeout = 1)))
})

test_that("the artifact child gets no registered secret in its environment", {
  skip_if_cannot_launch()
  local_artifact_project()
  vault_reset()
  withr::defer(vault_reset())
  fake = paste0("sk-ant-", "api03-", strrep("FAKEartifact", 4L), "00AA")
  withr::local_envvar(GPTR_ARTIFACT_TEST_KEY = fake, GPTR_TEST_PLAIN = fake)
  secret_register(fake, "GPTR_ARTIFACT_TEST_KEY", source = "test")
  h = artifact_launch_shiny(build_version("env-check", tiny_app), NULL)
  withr::defer(h$stop())
  env = tryCatch(ps::ps_environ(ps::ps_handle(h$pid)), error = function(e) NULL)
  skip_if(is.null(env), "ps cannot read the child's environment here")
  expect_false(any(grepl(fake, env, fixed = TRUE)))
  expect_false(any(c("GPTR_ARTIFACT_TEST_KEY", "GPTR_TEST_PLAIN") %in% names(env)))
})

test_that("a broken app fails at the launch stage with the child's error in the log tail", {
  skip_if_cannot_launch()
  local_artifact_project()
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  cnd = expect_error(artifact_launch_shiny(build_version("broken", broken), NULL),
                     class = "gptr_error_artifact")
  expect_identical(cnd$id, "broken")
  expect_identical(cnd$stage, "launch")
  expect_true(any(grepl("no_such_object", cnd$log, fixed = TRUE)))
  expect_match(conditionMessage(cnd), "no_such_object", fixed = TRUE)
  expect_true(file.exists(file.path(artifact_dir("broken"), "run", "app-v001.log")))
  expect_length(list.files(tempdir(), pattern = "^gptr-artifact-broken-"), 0L)
})

test_that("artifact_start() runs the ladder, records the run and keeps the port across versions", {
  skip_if_cannot_launch()
  local_artifact_project()
  starts = local_events("artifact_start")
  version_one("ladder", tiny_app)
  withr::defer(artifact_stop("ladder", emit = FALSE))
  h = artifact_start("ladder", 1L, shiny_type())
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "running")
  expect_identical(h$version, 1L)
  expect_identical(h$checks[c("parse", "launch", "http")],
                   list(parse = TRUE, launch = TRUE, http = TRUE))
  expect_true(is.na(h$checks$session))
  expect_identical(format(h)[1], paste0("artifact  ladder  ->  ", h$url,
                                        "   (running in background)"))
  run = json_decode(read_utf8(file.path(artifact_dir("ladder"), "run", "run.json"))$text)
  expect_identical(run$url, h$url)
  meta = artifact_meta_read("ladder")
  expect_identical(as.integer(meta$port), artifact_proc_get("ladder")$port)
  expect_true(meta$versions[[1]]$checks$http)
  expect_identical(job_list("artifact")$id, "artifact:ladder")
  expect_length(starts$events, 1L)
  expect_identical(starts$events[[1]]$url, h$url)
  write_working("ladder", sub("'hi'", "'v2'", tiny_app))
  dir.create(artifact_version_dir("ladder", 2L))
  artifact_build_shiny("ladder", artifact_version_dir("ladder", 2L), list(), NULL)
  port1 = artifact_proc_get("ladder")$port
  h2 = artifact_start("ladder", 2L, shiny_type())
  expect_identical(artifact_proc_get("ladder")$port, port1)
  expect_false(identical(h2$url, h$url))
  expect_identical(artifact_proc_get("ladder")$version, 2L)
})

test_that("an app whose page fails stops at the http stage with status failed", {
  skip_if_cannot_launch()
  local_artifact_project()
  bad_page = c("library(shiny)", "ui = function(req) stop('the page failed')",
               "server = function(input, output, session) {}", "shinyApp(ui, server)")
  version_one("page", bad_page)
  withr::defer(artifact_stop("page", emit = FALSE))
  cnd = expect_error(artifact_start("page", 1L, shiny_type()), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "http")
  expect_match(conditionMessage(cnd), "HTTP 500", fixed = TRUE)
  expect_identical(artifact_status("page"), "failed")
  expect_false(artifact_meta_read("page")$versions[[1]]$checks$http)
})

test_that("a launch that cannot start reads failed and keeps its checks", {
  local_artifact_project()
  version_one("nolaunch", tiny_app)
  broken_type = list(launch = function(version_dir, ctx) stop("no runtime"),
                     stop = function(handle) NULL)
  cnd = expect_error(artifact_start("nolaunch", 1L, broken_type), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "launch")
  expect_match(conditionMessage(cnd), "no runtime", fixed = TRUE)
  expect_identical(artifact_status("nolaunch"), "failed")
  expect_false(artifact_handle("nolaunch")$checks$launch)
  artifact_stop("nolaunch")
  expect_identical(artifact_status("nolaunch"), "stopped")
})

test_that("missing shiny is a missing_package error naming the feature", {
  local_artifact_project()
  local_mocked_bindings(artifact_shiny_available = function() FALSE)
  cnd = expect_error(artifact_launch_shiny(artifact_version_dir("x", 1L), NULL),
                     class = "gptr_error_missing_package")
  expect_identical(cnd$package, "shiny")
  expect_identical(cnd$feature, "artifacts")
})

test_that("the viewer opens only when a human is present (13 C-42)", {
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  withr::local_options(viewer = function(url) seen$urls = c(seen$urls, url))
  local_gptr_options(interactive = FALSE)
  expect_false(artifact_view("http://127.0.0.1:50000/"))
  local_gptr_options(interactive = TRUE)
  expect_true(artifact_view("http://127.0.0.1:50000/"))
  expect_false(artifact_view(NA_character_))
  expect_identical(seen$urls, "http://127.0.0.1:50000/")
})

test_that("the ladder with the session check leaves .Random.seed unchanged (IC-61)", {
  skip_if_cannot_launch()
  local_artifact_project()
  version_one("seed", tiny_app)
  withr::defer(artifact_stop("seed", emit = FALSE))
  withr::defer(artifact_browser_close())
  withr::local_seed(7)
  seed = get(".Random.seed", envir = globalenv())
  h = artifact_start("seed", 1L, shiny_type(), session_check = TRUE)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(h$status, "running")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 184 ]`; the nine new tests error with `could not find function "artifact_launch_shiny"` (and `"artifact_start"`, `"artifact_view"`; `shiny_type()` stops with `object 'artifact_launch_shiny' not found`).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- launch and the validation ladder (stages launch, http, session) -------------------------

#' Pump the reactor until the child publishes its port or exits; NA when there is no port
#' @noRd
artifact_wait_port = function(proc, port_file, timeout = artifact_launch_timeout) {
  published = function() file.exists(port_file) || !isTRUE(proc$is_alive())
  reactor_pump(until = published, slice_ms = 50L, timeout = timeout)
  if (!file.exists(port_file)) return(NA_integer_)
  port = suppressWarnings(as.integer(readLines(port_file, n = 1L, warn = FALSE,
                                               encoding = "UTF-8")))
  if (length(port) == 1L && !is.na(port)) port else NA_integer_
}

#' Closures over the child process only (a record never holds the launching frame)
#' @noRd
artifact_proc_fns = function(proc) {
  list(alive = function() isTRUE(tryCatch(proc$is_alive(), error = function(e) FALSE)),
       stop = function() kill_all(proc, grace = artifact_stop_grace))
}

#' The `launch` of the shiny and html artifact types (contract 10.2 row 19): a supervised callr
#' child serving the version (architecture 6.15)
#'
#' The child runs the self-contained artifact_serve() with `package = FALSE`, the secret-free
#' environment, `encoding = "UTF-8"`, `supervise = supervise_default()` and the version
#' directory as its working directory (IC-60); its stdout and stderr go to a raw file in
#' tempdir() that the parent copies, redacted, into run/app-vNNN.log (IC-70). A child that ends
#' before it publishes a port is the `launch` stage failure, reported with the log tail (a broken
#' UI shows the child's error).
#' @return `list(url, pid, stop)` (contract 10.2 row 19) plus `alive`, `port`, `token`, `raw`,
#'   `log`
#' @noRd
artifact_launch_shiny = function(version_dir, ctx) {
  if (!artifact_shiny_available()) {
    gptr_abort("Artifacts need the shiny package: install.packages(\"shiny\").",
               "missing_package", package = "shiny", feature = "artifacts")
  }
  id = basename(dirname(version_dir))
  run_dir = file.path(dirname(version_dir), "run")
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  port_file = file.path(run_dir, "port")
  unlink(port_file)
  log = file.path(run_dir, paste0("app-", basename(version_dir), ".log"))
  unlink(log)
  raw = tempfile(paste0("gptr-artifact-", id, "-"), fileext = ".log")
  token = artifact_token()
  proc = callr::r_bg(
    artifact_serve,
    args = list(dir = path_norm(version_dir), port_file = path_norm(port_file),
                parent_pid = Sys.getpid(), token = token),
    stdout = raw, stderr = "2>&1", supervise = supervise_default(), package = FALSE,
    user_profile = FALSE, system_profile = FALSE, env = artifact_child_env(artifact_ports(id)),
    cleanup = TRUE, cleanup_tree = TRUE, encoding = "UTF-8", wd = path_norm(version_dir)
  )
  port = artifact_wait_port(proc, port_file)
  if (is.na(port)) {
    reason = if (isTRUE(proc$is_alive())) {
      paste0("it did not publish a port within ", artifact_launch_timeout, " s")
    } else {
      "the app process exited"
    }
    kill_all(proc, grace = 1)
    artifact_log_sync(artifact_log_new(raw, log), final = TRUE)
    tail = artifact_log_tail(log)
    gptr_abort(paste0("Artifact ", id, " did not start (stage launch): ", reason, ".",
                      artifact_tail_text(tail, log)),
               "artifact", id = id, stage = "launch", log = tail)
  }
  url = sprintf("http://127.0.0.1:%d/", port)
  if (nzchar(token)) url = paste0(url, "?gptr_token=", token)
  fns = artifact_proc_fns(proc)
  list(url = url, pid = proc$get_pid(), stop = fns$stop, alive = fns$alive, port = port,
       token = token, raw = raw, log = log)
}

#' The `stop` of the built-in artifact types
#' @noRd
artifact_stop_handle = function(handle) handle$stop()

#' One GET through the reactor (architecture 6.15: "checks HTTP 200 through the reactor"); the
#' HTTP status, or NA when nothing answered. No retry and no redirect (IC-64).
#' @noRd
artifact_http_status = function(url, timeout = 3) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$status = NA_integer_
  finish = function(status) {
    st$status = suppressWarnings(as.integer(status %||% NA_integer_))
    st$done = TRUE
    invisible(NULL)
  }
  spec = list(url = url, method = "GET", headers = list(), connect_timeout = 1,
              first_byte_timeout = timeout, idle_timeout = timeout)
  id = reactor_http(spec, on_bytes = function(raw) NULL,
                    on_done = function(status, headers) finish(status),
                    on_fail = function(cnd) finish(cnd$status),
                    retry = list(max_attempts = 1L, committed = function() TRUE))
  if (!isTRUE(reactor_pump(until = function() st$done, slice_ms = 50L, timeout = timeout + 1))) {
    reactor_cancel(id)
  }
  st$status
}

#' Poll the app until it answers HTTP (validation ladder stage 3); ok only for 200
#' @noRd
artifact_wait_http = function(url, alive, timeout = artifact_launch_timeout) {
  deadline = reactor_now() + timeout
  repeat {
    if (!isTRUE(alive())) {
      return(list(ok = FALSE, status = NA_integer_, reason = "the app process exited"))
    }
    status = artifact_http_status(url)
    if (!is.na(status)) {
      return(list(ok = identical(status, 200L), status = status,
                  reason = paste0("it answered HTTP ", status)))
    }
    if (reactor_now() >= deadline) {
      return(list(ok = FALSE, status = NA_integer_,
                  reason = paste0("it did not answer within ", timeout, " s")))
    }
    reactor_pump(until = function() FALSE, slice_ms = 50L, timeout = 0.1)
  }
}

#' Open a URL in the IDE viewer or the browser, only when a human is present (13 C-42, C-43)
#' @noRd
artifact_view = function(url) {
  if (length(url) != 1L || is.na(url) || !gptr_has_human()) return(invisible(FALSE))
  viewer = getOption("viewer", utils::browseURL)
  viewer(url)
  invisible(TRUE)
}

#' The registered artifact type of a kind (IC-69: any registered `artifact_type`)
#' @noRd
artifact_type_get = function(kind, ctx = NULL) {
  check_string(kind, "kind")
  sid = artifact_session_id(ctx)
  spec = registry_get("artifact_type", kind, session = sid)
  if (is.null(spec)) {
    kinds = paste(registry_names("artifact_type", session = sid), collapse = ", ")
    gptr_abort(paste0("`kind` must name a registered artifact type (", kinds, ")."),
               "invalid_argument", arg = "kind", expected = "a registered artifact_type")
  }
  spec
}

#' A process-table record for a version whose launch failed before a process existed (its
#' status reads `failed`)
#' @noRd
artifact_record_failed = function(id, version, type) {
  rec = artifact_record_new(id, version, type, list())
  rec$log = file.path(artifact_dir(id), "run", sprintf("app-v%03d.log", as.integer(version)))
  rec
}

#' Mark a launched version as failed: stop its child (no stop request, so its status reads
#' `failed`), copy its output into the log and record the checks
#' @noRd
artifact_launch_failed = function(rec, checks) {
  if (artifact_rec_alive(rec)) try(rec$type$stop(rec$handle), silent = TRUE)
  artifact_log_sync(rec, final = TRUE)
  rec$checks = checks
  artifact_version_checks_set(rec$id, rec$version, checks)
  invisible(rec)
}

#' Launch one version and run the validation ladder: launch, HTTP 200, optional session check
#' (architecture 6.15)
#'
#' The artifact's running process is stopped first (its port is offered again, so the URL
#' stays). A failing `launch` or `http` stage records its checks in artifact.json and signals
#' `gptr_error_artifact` with the stage and the redacted log tail, so the model sees the child's
#' error; a failing session check is reported in the checks and messages, not raised. On
#' success the run files, the port and the job row are written, `artifact_start` is emitted and,
#' with a human present, the viewer opens.
#' @return The `gptr_artifact` handle.
#' @noRd
artifact_start = function(id, version, type, ctx = NULL, session_check = FALSE) {
  version = as.integer(version)
  artifact_stop(id, reason = "relaunch")
  meta = artifact_meta_read(id)
  parse_ok = artifact_version_record(meta, version)$checks$parse %||% NA
  checks = artifact_checks(parse = parse_ok)
  handle = tryCatch(type$launch(artifact_version_dir(id, version), ctx), error = function(e) e)
  if (inherits(handle, "error")) {
    checks$launch = FALSE
    artifact_version_checks_set(id, version, checks)
    failed = artifact_record_failed(id, version, type)
    failed$checks = checks
    assign(id, failed, envir = artifact_state$procs)
    if (inherits(handle, c("gptr_error_artifact", "gptr_error_missing_package"))) stop(handle)
    gptr_abort(paste0("Artifact ", id, " did not start (stage launch): ",
                      conditionMessage(handle)),
               "artifact", id = id, stage = "launch", log = character())
  }
  rec = artifact_record_new(id, version, type, handle)
  assign(id, rec, envir = artifact_state$procs)
  http = artifact_wait_http(rec$url, function() artifact_rec_alive(rec))
  checks$launch = artifact_rec_alive(rec)
  checks$http = isTRUE(http$ok)
  if (!checks$http) {
    stage = if (checks$launch) "http" else "launch"
    artifact_launch_failed(rec, checks)
    tail = artifact_log_tail(rec$log)
    gptr_abort(paste0("Artifact ", id, " v", sprintf("%03d", version), " failed at stage ",
                      stage, ": ", http$reason, ".", artifact_tail_text(tail, rec$log)),
               "artifact", id = id, stage = stage, log = tail)
  }
  artifact_run_write(rec)
  meta = artifact_meta_read(id)
  if (!is.na(rec$port)) meta$port = rec$port
  artifact_meta_write(id, meta)
  artifact_job_add(id, meta$title %||% id, rec$pid)
  if (session_check) {
    png = file.path(artifact_dir(id), "run", sprintf("screenshot-v%03d.png", version))
    sc = artifact_session_check(rec, png)
    checks$session = sc$ok
    checks$messages = sc$messages
    rec$screenshot = sc$screenshot
  } else {
    artifact_log_sync(rec)
    checks$messages = artifact_log_messages(rec$log)
  }
  rec$checks = checks
  artifact_version_checks_set(id, version, checks)
  artifact_emit("artifact_start", id = id, url = rec$url, version = version)
  artifact_view(rec$url)
  artifact_handle(id)
}

#' Relaunch a stored version with its kind's type and make it current (launch and HTTP checks
#' only: `gptr_artifacts(version =)`, `open = TRUE` and the checkpointer). The kind is the one the
#' version was built with (its record's `kind`), so an id that changed kind relaunches each
#' version with its own type.
#' @noRd
artifact_relaunch = function(id, version, ctx = NULL) {
  meta = artifact_meta_read(id)
  vrec = artifact_version_record(meta, version)
  if (is.null(vrec)) {
    gptr_abort("`version` is not a stored version of this artifact.", "invalid_argument",
               arg = "version", expected = "the number of a stored version (vNNN)")
  }
  type = artifact_type_get(vrec$kind %||% meta$kind %||% "shiny", ctx)
  artifact_set_current(id, version)
  artifact_start(id, as.integer(version), type, ctx = ctx, session_check = FALSE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 237 ]`. Without chromote or a Chrome binary: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 223 ]` (the ladder test with `session_check = TRUE` then records an HTTP-only check).

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): launch versions through the validation ladder"
```

### Task 8: The `artifacts` checkpointer

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Tasks 1-7 (`artifact_status()`, `artifact_stop()`, `artifact_set_current()`, `artifact_relaunch()`, `artifact_exists()`); P01 `json_decode()`, `json_encode()` (tests), `read_utf8()`, `` `%||%` ``.
- Produces: the five functions of the `checkpointer` spec `artifacts` (04 §10.2 row 29; registered by Task 9): `artifact_ckpt_before(call, ctx)` -> token (`current` and `running` per artifact id, for `r` and `app` calls; `NULL` for every other tool), `artifact_ckpt_after(call, ctx, token)` -> fragment (a list of `list(id, current_before, current_after, running_before, running_after)` for the artifacts whose `current` changed, or `NULL`), `artifact_ckpt_undo(fragment, ctx, force)` and `artifact_ckpt_redo(fragment, ctx, force)` -> chr report lines, `artifact_ckpt_prune(live_keys, ctx)`, `artifact_ckpt_describe(fragment)` -> chr; helpers `artifact_ckpt_state()`, `artifact_ckpt_move(fragment, side, running, ctx = NULL)`, `artifact_ckpt_unrestorable(fragment)`.

G7 §3.1 records "artifact `current` before/after" in the `gptr.checkpoint` entry (04 §4.6); P06's dispatcher calls every checkpointer's `before`/`after` around each sequential, non-read-only tool call and writes one container entry `{tool_call_id, fragments: {<checkpointer>: <fragment>}}`; P16's rewind calls `undo` newest first and `redo` oldest first. A `peter$app()` inside an `r` call creates a new immutable version, so undo only has to move `current` back and relaunch what was running (G7 §4.3: "The record stores `artifact.json$current` before and after. Undo resets `current` and restarts the previous version on the same port if it was running."); redo moves it forward again. Version directories are immutable and stay on disk: `prune` keeps them, because `artifact.json` lists them and `gptr_artifacts(version =)` relaunches them (G7 adds "they are pruned with the retention settings"; see Self-review ambiguity 6). Report lines follow P16's partial-rewind rule (`not restored|not redone|conflict|failed`): an artifact that no longer exists reads `not restored (it no longer exists)`, a relaunch that fails `(relaunch failed)`, and a fragment that P06 marked `list(restorable = FALSE, reason)` (its `after` failed) reads `artifacts: not restored (<reason>)`. Fragments are JSON-able (they round-trip through the session file).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

# An artifact.json with `n` versions (current = n); returns the id invisibly
seed_artifact = function(id, n = 1L, kind = "shiny") {
  meta = artifact_meta_new(id, paste("Title of", id), kind)
  meta$versions = lapply(seq_len(n), function(i) {
    dir.create(artifact_version_dir(id, i), recursive = TRUE, showWarnings = FALSE)
    list(n = i, created = artifact_time(), app_sha = NULL, data = list(), session = NULL,
         checks = artifact_checks_json(artifact_checks(parse = TRUE)))
  })
  meta$current = as.integer(n)
  artifact_meta_write(id, meta)
  invisible(id)
}

test_that("the checkpointer records current before and after an r call (G7 3.1)", {
  local_artifact_project()
  seed_artifact("ck", n = 1L)
  r_call = list(id = "c1", name = "r", input = list(code = "peter$app('ck')"))
  expect_null(artifact_ckpt_before(list(id = "c0", name = "write", input = list()), NULL))
  token = artifact_ckpt_before(r_call, NULL)
  expect_identical(token$ck, list(current = 1L, running = FALSE))
  expect_null(artifact_ckpt_after(r_call, NULL, token))
  seed_artifact("ck", n = 2L)
  seed_artifact("new", n = 1L)
  frag = artifact_ckpt_after(r_call, NULL, token)
  expect_identical(frag, list(
    list(id = "ck", current_before = 1L, current_after = 2L, running_before = FALSE,
         running_after = FALSE),
    list(id = "new", current_before = 0L, current_after = 1L, running_before = FALSE,
         running_after = FALSE)))
  expect_identical(artifact_ckpt_describe(frag),
                   c("artifact ck: v001 -> v002", "artifact new: (none) -> v001"))
  back = json_decode(json_encode(frag))
  expect_identical(artifact_ckpt_describe(back), artifact_ckpt_describe(frag))
  expect_null(artifact_ckpt_after(r_call, NULL, NULL))
})

test_that("undo and redo move current and report each artifact", {
  local_artifact_project()
  seed_artifact("ck", n = 2L)
  frag = list(list(id = "ck", current_before = 1L, current_after = 2L, running_before = FALSE,
                   running_after = FALSE),
              list(id = "gone", current_before = 0L, current_after = 1L,
                   running_before = FALSE, running_after = FALSE))
  rep = artifact_ckpt_undo(frag, NULL, FALSE)
  expect_identical(rep, c("artifact ck: current version 1",
                          "artifact gone: not restored (it no longer exists)"))
  expect_identical(as.integer(artifact_meta_read("ck")$current), 1L)
  expect_true(dir.exists(artifact_version_dir("ck", 2L)))
  expect_identical(artifact_ckpt_redo(frag[1], NULL, FALSE), "artifact ck: current version 2")
  expect_identical(as.integer(artifact_meta_read("ck")$current), 2L)
  expect_null(artifact_ckpt_prune(character(), NULL))
  failed = list(restorable = FALSE, reason = "boom")
  expect_identical(artifact_ckpt_undo(failed, NULL, FALSE), "artifacts: not restored (boom)")
  expect_identical(artifact_ckpt_describe(failed), "artifacts: not restored (boom)")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 237 ]`; the two new tests error with `could not find function "artifact_ckpt_before"` (and `"artifact_ckpt_undo"`).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- the artifacts checkpointer (contract 10.2 row 29; G7 sections 3.1 and 4.3) ---------------

#' `current` and the running state of every artifact of the workspace (names: ids)
#' @noRd
artifact_ckpt_state = function() {
  root = artifact_root()
  files = if (dir.exists(root)) Sys.glob(file.path(root, "*", "artifact.json")) else character()
  out = list()
  for (f in files) {
    id = basename(dirname(f))
    meta = tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
    out[[id]] = list(current = as.integer(meta$current %||% 0L),
                     running = identical(artifact_status(id), "running"))
  }
  out
}

#' Checkpointer `before`: the artifact state before a call that can run peter$app() or
#' gptr_artifacts(version =) (an `r` call, or `app` when a preset declares it directly); NULL
#' for every other tool
#' @noRd
artifact_ckpt_before = function(call, ctx) {
  if (!(call$name %in% c("r", "app"))) return(NULL)
  artifact_ckpt_state()
}

#' Checkpointer `after`: the artifacts whose `current` changed, as the `artifacts` fragment of G7
#' section 3.1 (`id`, `current_before`, `current_after`) plus whether each was running; NULL when
#' nothing changed
#' @noRd
artifact_ckpt_after = function(call, ctx, token) {
  if (is.null(token)) return(NULL)
  now = artifact_ckpt_state()
  changed = list()
  for (id in names(now)) {
    before = token[[id]]
    was = if (is.null(before)) 0L else as.integer(before$current)
    if (identical(was, now[[id]]$current)) next
    changed[[length(changed) + 1L]] = list(
      id = id, current_before = was, current_after = now[[id]]$current,
      running_before = isTRUE(before$running), running_after = isTRUE(now[[id]]$running)
    )
  }
  if (length(changed)) changed else NULL
}

#' The report line of a fragment that P06 marked not restorable (its `after` failed)
#' @noRd
artifact_ckpt_unrestorable = function(fragment) {
  paste0("artifacts: not restored (", fragment$reason %||% "the checkpoint failed", ")")
}

#' Move artifacts to one side of a fragment: stop, set `current`, relaunch on the same port what
#' was running there (G7 section 4.3); returns report lines (P16 reads "not restored" and
#' "failed" as a partial rewind). `ctx` resolves the version's `artifact_type` for the rewound
#' session, so a type registered for that session only is found too.
#' @noRd
artifact_ckpt_move = function(fragment, side, running, ctx = NULL) {
  if (isFALSE(fragment$restorable)) return(artifact_ckpt_unrestorable(fragment))
  report = character()
  for (r in fragment) {
    id = as.character(r$id)
    target = as.integer(r[[side]])
    if (!artifact_exists(id)) {
      report = c(report, paste0("artifact ", id, ": not restored (it no longer exists)"))
      next
    }
    artifact_stop(id, reason = "rewind")
    artifact_set_current(id, target)
    line = paste0("artifact ", id, ": current version ", target)
    if (target > 0L && isTRUE(r[[running]])) {
      ok = tryCatch({
        artifact_relaunch(id, target, ctx)
        TRUE
      }, error = function(e) FALSE)
      line = paste0(line, if (ok) " (relaunched)" else " (relaunch failed)")
    }
    report = c(report, line)
  }
  report
}

#' Checkpointer `undo`
#' @noRd
artifact_ckpt_undo = function(fragment, ctx, force) {
  artifact_ckpt_move(fragment, "current_before", "running_before", ctx)
}

#' Checkpointer `redo`
#' @noRd
artifact_ckpt_redo = function(fragment, ctx, force) {
  artifact_ckpt_move(fragment, "current_after", "running_after", ctx)
}

#' Checkpointer `prune`: version directories are immutable and stay (artifact.json lists them;
#' redo and gptr_artifacts(version =) use them)
#' @noRd
artifact_ckpt_prune = function(live_keys, ctx) invisible(NULL)

#' Checkpointer `describe`: one line per artifact
#' @noRd
artifact_ckpt_describe = function(fragment) {
  if (isFALSE(fragment$restorable)) return(artifact_ckpt_unrestorable(fragment))
  v = function(n) if (as.integer(n) > 0L) sprintf("v%03d", as.integer(n)) else "(none)"
  vapply(fragment, function(r) {
    paste0("artifact ", r$id, ": ", v(r$current_before), " -> ", v(r$current_after))
  }, character(1))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 252 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): add the artifacts checkpointer"
```

### Task 9: `peter$app()`, the `artifacts` section, `builtin:artifacts` and the copy rows

**Files:**
- Modify: `R/artifact-app.R` (append)
- Test: `tests/testthat/test-artifact-app.R` (append)
- Create: `tests/testthat/test-copy-artifact.R`

**Interfaces:**
- Consumes: Tasks 1-8; P01 `check_strings()`, `check_flag()`, `gptr_opt("r_max_images")`, `block_image(data, mime = "image/png", source = "screenshot", width, height)`, `on_load(expr)`; P02 `gptr_spec("artifact_type", ...)`, `gptr_spec("checkpointer", ...)`, `gptr_tool(...)`, `gptr_prompt_section(...)`, `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, the API object's `gptr$register(spec)`, `ctx$session`, `ctx$envir`; P06 kernel SDK `run_current()`, `run_eval_env(run)`, `session_append(s, entry)`; P10 the member closure (`member_closure(spec)`) and the r-call marker `gptr_r_call` (`images`, `dropped`); tests: P08's `peter` object (`peter$app`), P01 `expect_no_copy()`, `gptr_fake_provider()` (in the child script), `local_gptr_options()`.
- Produces: `artifact_app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = FALSE, envir = globalenv(), ctx = NULL)` -> `gptr_artifact` (the body of `peter$app()`); the member `app` (04 §9.4): `artifact_member_fun(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` (the spec's `fun`, the signature of 04 §9.4), `artifact_member_execute(input, ctx)` (the spec's `execute` for model code: appends the `gptr.artifact` entry `{id, version, url, status, checks}` and attaches the screenshot to the running `r` result), `artifact_risk(input, ctx)` -> `list(level = 3L, categories = "process", paths)`, `artifact_tool_spec()`; `artifact_entry(ctx, handle)`, `artifact_screenshot_block(handle)`, `artifact_attach_image(block)`, `artifact_tool_result(handle, block)`; the section text `artifact_section_text` (03 §7.3 verbatim) and `artifact_section(ctx)`; `builtin_artifacts(gptr)` (04 §7.23), declared with `on_load(ext_declare_builtin("artifacts", builtin_artifacts))`.

`peter$app()` (architecture 6.15) resolves the kind against the registry (IC-69: any registered `artifact_type`, so a plugin's `quarto` type works the same way), runs the lazy orphan sweep once per process, runs the type's `check` on the working directory (stage `parse`/`static` failures raise `gptr_error_artifact` with the messages in `log`, before any version exists), claims the next `vNNN`, snapshots the data, runs the type's `build`, records the version in `artifact.json` (`n`, `created`, `app_sha`, `data`, `session`, `checks`) and, with `launch = TRUE`, runs the ladder of Task 7 with the session check when `check = TRUE`. A version claimed by a call that fails before its build finished is removed again. The member is one tool spec with both forms (IC-37): `fun` for the user (objects are looked up in the frame that called `peter$app()`: P10's member closure evaluates `fun` in its own frame, so the caller is that closure's caller, found through `sys.parents()`; frame numbers only, never `sys.frames()`, rule R3; the frame is used during the call only, R2) and `execute` for model code, which reaches it through P06's `dispatch_nested()` with the validated input (`data` arrives as a list) and looks objects up in the run's evaluation environment (the plan-mode overlay when there is one). The screenshot reaches the `r` result through P10's r-call marker: the binding `gptr_r_call` of class `gptr_r_call` in the `r` tool's frame is found by walking `sys.frame(k)` outwards, and its `images` are capped at `gptr.r_max_images` like P10's own attachments (refused ones are counted in `dropped`, which P10's result names, IC-67). The `artifacts` section is a `function(ctx)` returning `NULL` when shiny is not installed (04 §9.3: "shiny installed and `builtin:artifacts` enabled"); disabling the built-in with `-builtin:artifacts` removes the member, the section, the types and the checkpointer together. The copy rows (05 P23 acceptance 3) run `peter$app()` on a 40 MB vector from user code and from model code in a fresh `Rscript` and count copies on the next in-place edit (03 §6.4 test list: "artifact snapshots").

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

test_that("builtin:artifacts registers the types, the member, the section and the checkpointer", {
  expect_true(is.function(builtin_artifacts))
  for (kind in c("shiny", "html")) {
    spec = registry_get("artifact_type", kind)
    expect_s3_class(spec, "gptr_artifact_type")
    expect_true(all(vapply(spec[c("build", "check", "launch", "stop")], is.function, NA)))
  }
  app = registry_get("tool", "app")
  expect_identical(app$exposure, "r")
  expect_true(is.function(app$fun) && is.function(app$execute))
  expect_identical(names(formals(app$fun)), c("id", "data", "title", "kind", "check", "launch"))
  fmls = formals(app$fun)
  expect_identical(fmls$data, quote(character()))
  expect_null(fmls$title)
  expect_identical(fmls$kind, "shiny")
  expect_true(fmls$check)
  expect_identical(fmls$launch, quote(interactive()))
  expect_identical(app$risk(list(id = "x"), NULL)$level, 3L)
  sec = registry_get("prompt_section", "artifacts")
  expect_identical(sec$tier, "T0")
  expect_identical(sec$order, 600L)
  expect_identical(sec$budget, 150L)
  ck = registry_get("checkpointer", "artifacts")
  expect_identical(ck$scope, "artifacts")
})

test_that("the artifacts section is architecture 7.3 verbatim and needs shiny", {
  expect_identical(artifact_section_text, paste0(
    "For an interactive view (filters, drill-down, dashboards) build a Shiny app, not HTML/JS: ",
    "write app.R in <artifacts>/<id>/ (the directory is named in <environment>), one file ",
    "ending in shinyApp(ui, server) that uses the objects listed in data by name, then launch ",
    "it in r with peter$app(\"<id>\", data = c(\"obj\")). Read the shiny-bslib skill first. ",
    "Revise app.R with edit and call peter$app() again; check the returned screenshot and errors ",
    "before saying it is done."))
  local_mocked_bindings(artifact_shiny_available = function() TRUE)
  expect_identical(artifact_section(NULL), artifact_section_text)
  local_mocked_bindings(artifact_shiny_available = function() FALSE)
  expect_null(artifact_section(NULL))
})

test_that("peter$app() refuses reserved ids, unknown kinds and a missing working copy", {
  local_artifact_project()
  expect_error(peter$app("con"), class = "gptr_error_invalid_argument")
  cnd = expect_error(peter$app("x", kind = "nope", launch = FALSE),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "kind")
  expect_match(conditionMessage(cnd), "html, shiny|shiny, html")
  cnd = expect_error(peter$app("nothing-yet", launch = FALSE), class = "gptr_error_artifact")
  expect_identical(cnd$stage, "parse")
  expect_match(conditionMessage(cnd), ".gptr/artifacts/nothing-yet/app.R", fixed = TRUE)
})

test_that("a second peter$app() after an edit creates v002 without touching v001", {
  skip_if_not_installed("shiny")
  local_artifact_project()
  markers = data.frame(gene = c("CD14", "LYZ"), p = c(0.01, 0.2))
  assign("a/b", 1:3) # nolint: object_name_linter. 05 P23 acceptance 5 names the object a/b.
  write_working("explorer", ok_app)
  h1 = peter$app("explorer", data = c("markers", "a/b"), title = "Explorer", launch = FALSE)
  expect_s3_class(h1, "gptr_artifact")
  expect_identical(h1$version, 1L)
  expect_identical(h1$status, "stopped")
  expect_identical(h1$checks$parse, TRUE)
  expect_true(is.na(h1$checks$launch))
  v1 = artifact_version_dir("explorer", 1L)
  expect_true(all(file.exists(file.path(v1, c("app.R", "R/gptr_data.R", "data/001.rds",
                                              "data/002.rds")))))
  md5_v1 = tools::md5sum(list.files(v1, recursive = TRUE, full.names = TRUE))
  meta = artifact_meta_read("explorer")
  expect_identical(meta$title, "Explorer")
  expect_identical(vapply(meta$versions[[1]]$data, function(d) d$name, ""), c("markers", "a/b"))
  expect_identical(meta$versions[[1]]$data[[2]]$file, "data/002.rds")
  expect_identical(meta$versions[[1]]$app_sha,
                   hash_sha256(readBin(file.path(v1, "app.R"), "raw", 1e5)))
  write_working("explorer", sub("'Gene'", "'Gene symbol'", ok_app))
  markers$p = markers$p / 2
  h2 = peter$app("explorer", data = "markers", launch = FALSE)
  expect_identical(h2$version, 2L)
  expect_identical(h2$title, "Explorer")
  expect_identical(tools::md5sum(names(md5_v1)), md5_v1)
  expect_true(any(grepl("Gene symbol", readLines(file.path(artifact_version_dir("explorer", 2L),
                                                           "app.R")))))
  expect_identical(readRDS(file.path(artifact_version_dir("explorer", 2L), "data", "001.rds")),
                   markers)
  expect_identical(as.integer(artifact_meta_read("explorer")$current), 2L)
})

test_that("failed static checks raise gptr_error_artifact and leave no version", {
  skip_if_not_installed("shiny")
  local_artifact_project()
  write_working("bad", c(ok_app[1:5], "setwd('/')", ok_app[6]))
  cnd = expect_error(peter$app("bad", launch = FALSE), class = "gptr_error_artifact")
  expect_identical(cnd$id, "bad")
  expect_identical(cnd$stage, "static")
  expect_match(cnd$log, "setwd", fixed = TRUE)
  expect_false(dir.exists(artifact_version_dir("bad", 1L)))
  expect_false(artifact_exists("bad"))
  h = peter$app("bad", check = FALSE, launch = FALSE)
  expect_true(is.na(h$checks$parse))
})

test_that("a failed snapshot removes the version it claimed", {
  local_artifact_project()
  write_working("snapfail", ok_app)
  expect_error(peter$app("snapfail", data = "no_such_object", check = FALSE, launch = FALSE),
               class = "gptr_error_invalid_argument")
  expect_false(dir.exists(artifact_version_dir("snapfail", 1L)))
})

test_that("kind = \"html\" wraps page.html in a Shiny app version", {
  local_artifact_project()
  markers = data.frame(gene = "CD14")
  write_working("page", "<html><head></head><body><div id='x'></div></body></html>", "page.html")
  h = peter$app("page", data = "markers", kind = "html", launch = FALSE)
  expect_identical(h$kind, "html")
  expect_identical(basename(h$path), "page.html")
  vdir = artifact_version_dir("page", 1L)
  expect_true(all(file.exists(file.path(vdir, c("app.R", "page.html", "data/001.rds")))))
  expect_identical(artifact_meta_read("page")$kind, "html")
  expect_identical(artifact_meta_read("page")$versions[[1]]$kind, "html")
})

test_that("the tool form returns the handle's lines and attaches the screenshot to the r call", {
  local_artifact_project()
  e = new.env()
  e$markers = data.frame(gene = "CD14")
  write_working("tool", ok_app)
  res = artifact_member_execute(list(id = "tool", data = list("markers"), check = FALSE,
                                     launch = FALSE),
                                list(session = NULL, envir = e))
  expect_s3_class(res, "gptr_tool_result")
  expect_s3_class(res$value, "gptr_artifact")
  expect_identical(res$content[[1]]$text, paste(format(res$value), collapse = "\n"))
  expect_identical(res$details$status, "stopped")
  expect_identical(res$details$path, ".gptr/artifacts/tool/app.R")
  expect_identical(length(res$content), 1L)
  png = file.path(artifact_dir("tool"), "shot.png")
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), png)
  block = artifact_screenshot_block(list(screenshot = png))
  expect_identical(block$source, "screenshot")
  expect_identical(c(block$width, block$height), c(1000L, 700L))
  expect_false(artifact_attach_image(block))
  gptr_r_call = structure(new.env(), class = "gptr_r_call")
  gptr_r_call$images = list()
  gptr_r_call$dropped = 0L
  local_gptr_options(r_max_images = 1L)
  attach_twice = function() c(artifact_attach_image(block), artifact_attach_image(block))
  expect_identical(attach_twice(), c(TRUE, FALSE))
  expect_length(gptr_r_call$images, 1L)
  expect_identical(gptr_r_call$dropped, 1L)
})

test_that("peter$app() launches through the ladder and keeps .Random.seed (IC-61)", {
  skip_if_cannot_launch()
  local_artifact_project()
  withr::defer(artifact_browser_close())
  markers = data.frame(gene = c("CD14", "LYZ"))
  write_working("live", ok_app)
  withr::local_seed(11)
  seed = get(".Random.seed", envir = globalenv())
  h = peter$app("live", data = "markers", launch = TRUE, check = TRUE)
  withr::defer(artifact_stop("live", emit = FALSE))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(h$status, "running")
  expect_true(h$checks$parse && h$checks$launch && h$checks$http)
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  pid = artifact_proc_get("live")$pid
  ct = artifact_create_time(pid)
  artifact_stop("live")
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_identical(artifact_handle("live")$status, "stopped")
})

test_that("undo relaunches the version that was running, on the same port", {
  skip_if_cannot_launch()
  local_artifact_project()
  write_working("rew", tiny_app)
  peter$app("rew", launch = TRUE, check = FALSE)
  withr::defer(artifact_stop("rew", emit = FALSE))
  port = artifact_proc_get("rew")$port
  token = artifact_ckpt_before(list(name = "r"), NULL)
  write_working("rew", sub("'hi'", "'v2'", tiny_app))
  peter$app("rew", launch = TRUE, check = FALSE)
  frag = artifact_ckpt_after(list(name = "r"), NULL, token)
  expect_identical(frag[[1]][c("current_before", "current_after", "running_before",
                               "running_after")],
                   list(current_before = 1L, current_after = 2L, running_before = TRUE,
                        running_after = TRUE))
  expect_identical(artifact_ckpt_undo(frag, NULL, FALSE),
                   "artifact rew: current version 1 (relaunched)")
  expect_identical(artifact_proc_get("rew")$version, 1L)
  expect_identical(artifact_proc_get("rew")$port, port)
  expect_identical(artifact_status("rew"), "running")
})
```

Create `tests/testthat/test-copy-artifact.R`:

```r
# Copy-safety rows of the artifact area (architecture 6.4 R1, R2, R4, R7; contract 1.3; 05 P23
# acceptance 3): snapshotting an object into an artifact leaves it editable in place, whether the
# user or model code calls peter$app(). Each row runs in a fresh Rscript through expect_no_copy()
# and stops unless the snapshot was written (so that zero copies cannot pass vacuously).

copy_setup = c(
  "big = runif(5e6)",
  "root = file.path(tempdir(), 'copy-artifact')",
  "dir.create(file.path(root, '.gptr', 'artifacts', 'big-view'), recursive = TRUE)",
  "writeLines(c('library(shiny)', 'ui = fluidPage(textOutput(\"n\"))',",
  "             'server = function(input, output, session) output$n = renderText(length(big))',",
  "             'shinyApp(ui, server)'),",
  "           file.path(root, '.gptr', 'artifacts', 'big-view', 'app.R'))",
  "options(gptr.project_root = root)",
  "snap = file.path(root, '.gptr', 'artifacts', 'big-view', 'v001', 'data', '001.rds')"
)

test_that("peter$app() called by the user snapshots big and leaves it editable in place", {
  skip_if_not_installed("shiny")
  expect_no_copy(setup = copy_setup,
                 action = c("a = peter$app(\"big-view\", data = \"big\", launch = FALSE)",
                            "stopifnot(file.exists(snap))"),
                 edit = "big[1] = 0", object = "big", allow = 0L,
                 label = "peter$app() snapshot by the user")
})

test_that("peter$app() called by model code snapshots big and leaves it editable in place", {
  skip_if_not_installed("shiny")
  action = c(
    "app_code = 'a = peter$app(\"big-view\", data = \"big\", launch = FALSE)'",
    "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = app_code)), 'done'))",
    "s = peter('Snapshot big into the app', model = fake, mode = 'auto', envir = globalenv())",
    "stopifnot(file.exists(snap))"
  )
  expect_no_copy(setup = copy_setup, action = action, edit = "big[1] = 0", object = "big",
                 allow = 0L, label = "peter$app() snapshot by model code")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app|copy-artifact")'
```

Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 252 ]`. In `test-artifact-app.R` the ten new tests error with `object 'builtin_artifacts' not found`, `object 'artifact_section_text' not found`, `could not find function "artifact_member_execute"` and, for every `peter$app()` call, `gptr_error_unknown_member` (the namespace has no `app` member yet); in `test-copy-artifact.R` both rows fail with `expect_no_copy(...): the script did not finish (status 1)`, because no snapshot `v001/data/001.rds` was written (the first row's script stops at `peter$app`, the second at `stopifnot(file.exists(snap))` after the run ends with the model's error result).

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-app.R`:

```r

# ---- peter$app(), the artifacts section and builtin:artifacts ---------------------------------

#' peter$app(): check, snapshot, build and optionally launch one new version (architecture 6.15)
#'
#' `envir` is where the objects named in `data` are looked up (the run's evaluation environment
#' for model code, the caller's frame for user calls); it is read only through leaf functions and
#' never kept [R1][R2]. A version directory claimed by a call that fails before its build
#' finished is removed again; a version that fails to launch stays (immutable) with its checks.
#' @return The `gptr_artifact` handle.
#' @noRd
artifact_app = function(id, data = character(), title = NULL, kind = "shiny", check = TRUE,
                        launch = FALSE, envir = globalenv(), ctx = NULL) {
  artifact_id_check(id)
  check_strings(data, "data")
  check_string(title, "title", null = TRUE)
  check_flag(check, "check")
  check_flag(launch, "launch")
  type = artifact_type_get(kind, ctx)
  artifact_sweep_once()
  dir = artifact_dir(id)
  if (!dir.exists(dir)) {
    gptr_abort(paste0("Artifact ", id, " has no working copy: write ",
                      path_rel(artifact_working_file(dir, kind)), " first."),
               "artifact", id = id, stage = "parse", log = character())
  }
  parse_ok = NA
  if (check) {
    st = type$check(dir, ctx)
    if (!isTRUE(st$ok)) {
      msgs = as.character(st$messages)
      gptr_abort(paste0("Artifact ", id, " failed its static checks:\n",
                        paste0("- ", msgs, collapse = "\n")),
                 "artifact", id = id, stage = st$stage %||% "static", log = msgs)
    }
    parse_ok = TRUE
  }
  meta = artifact_meta_read(id) %||% artifact_meta_new(id, title, kind)
  n = artifact_version_claim(id)
  vdir = artifact_version_dir(id, n)
  built = FALSE
  on.exit(if (!built) unlink(vdir, recursive = TRUE), add = TRUE)
  records = artifact_snapshot(vdir, data, envir, id = id)
  type$build(id, vdir, records, ctx)
  built = TRUE
  app_file = artifact_working_file(dir, kind)
  has_file = file.exists(app_file) && !dir.exists(app_file)
  meta$title = title %||% meta$title %||% id
  meta$kind = kind
  version = list(n = n, created = artifact_time(),
                 app_sha = if (has_file) artifact_file_sha(app_file),
                 data = records, session = artifact_session_id(ctx),
                 checks = artifact_checks_json(artifact_checks(parse = parse_ok)), kind = kind)
  meta$versions = c(meta$versions, list(version))
  meta$current = n
  artifact_meta_write(id, meta)
  if (launch) return(artifact_start(id, n, type, ctx = ctx, session_check = check))
  artifact_handle(id)
}

#' Append the `gptr.artifact` custom entry (contract 4.6) to the session of the calling run
#' @noRd
artifact_entry = function(ctx, handle) {
  s = ctx$session
  if (is.null(s)) return(invisible(NULL))
  data = list(id = handle$id, version = handle$version,
              url = if (is.na(handle$url)) NULL else handle$url, status = handle$status,
              checks = artifact_checks_json(handle$checks))
  invisible(session_append(s, list(type = "custom", custom_type = "gptr.artifact", data = data)))
}

#' The screenshot of a handle as an image block, or NULL
#' @noRd
artifact_screenshot_block = function(handle) {
  png = handle$screenshot
  if (is.null(png) || !file.exists(png)) return(NULL)
  block_image(readBin(png, "raw", file.size(png)), mime = "image/png", source = "screenshot",
              width = artifact_shot_size[["width"]], height = artifact_shot_size[["height"]])
}

#' Attach an image block to the result of the innermost running `r` call; FALSE outside one
#'
#' The `r` tool (P10) binds an r-call marker, the variable `gptr_r_call` of class
#' `gptr_r_call` whose `images` collect what members attach; it is found by walking frames with
#' sys.frame(k), never sys.frames() (rule R3), and capped at `gptr.r_max_images` like P10's own
#' attachments (the refused ones are counted in `dropped`, IC-67).
#' @noRd
artifact_attach_image = function(block) {
  k = sys.nframe() - 1L
  while (k > 0L) {
    rc = get0("gptr_r_call", envir = sys.frame(k), inherits = FALSE)
    if (inherits(rc, "gptr_r_call")) {
      if (length(rc$images) >= as.integer(gptr_opt("r_max_images"))) {
        rc$dropped = (rc$dropped %||% 0L) + 1L
        return(invisible(FALSE))
      }
      rc$images = c(rc$images, list(block))
      return(invisible(TRUE))
    }
    k = k - 1L
  }
  invisible(FALSE)
}

#' The tool result of peter$app(): the handle's lines, the screenshot, the handle as the value
#' @noRd
artifact_tool_result = function(handle, block = artifact_screenshot_block(handle)) {
  gptr_tool_result(text = format(handle), images = if (is.null(block)) NULL else list(block),
                   details = list(id = handle$id, version = handle$version,
                                  url = if (is.na(handle$url)) NULL else handle$url,
                                  status = handle$status,
                                  checks = artifact_checks_json(handle$checks),
                                  path = path_rel(handle$path)),
                   value = handle)
}

#' The member's R form `peter$app(id, data, title, kind, check, launch)`, called by the user
#'
#' Objects are looked up in the frame that called `peter$app()`: when this function runs inside
#' P10's member closure (class `gptr_member`), that is the closure's caller, found through
#' `sys.parents()` (frame numbers only, never `sys.frames()`, rule R3); called directly, its own
#' caller. The frame is used during the call only [R2].
#' @noRd
artifact_member_fun = function(id, data = character(), title = NULL, kind = "shiny",
                               check = TRUE, launch = interactive()) {
  k = sys.parent()
  envir = if (k > 0L && inherits(sys.function(k), "gptr_member")) {
    sys.frame(sys.parents()[k])
  } else {
    parent.frame()
  }
  artifact_app(id, data = data, title = title, kind = kind, check = check, launch = launch,
               envir = envir, ctx = NULL)
}

#' The member's tool form: model code calling peter$app() inside a run reaches it through P06's
#' dispatch_nested(); objects are looked up in the run's evaluation environment
#' @noRd
artifact_member_execute = function(input, ctx) {
  run = run_current()
  envir = if (is.null(run)) NULL else run_eval_env(run)
  envir = envir %||% ctx$envir %||% globalenv()
  handle = artifact_app(id = input$id, data = as.character(unlist(input$data)),
                        title = input$title, kind = input$kind %||% "shiny",
                        check = input$check %||% TRUE, launch = input$launch %||% interactive(),
                        envir = envir, ctx = ctx)
  artifact_entry(ctx, handle)
  block = artifact_screenshot_block(handle)
  if (!is.null(block)) artifact_attach_image(block)
  artifact_tool_result(handle, block)
}

#' Risk of peter$app(): level 3, launching model-written code (contract 9.4; architecture 6.15)
#' @noRd
artifact_risk = function(input, ctx) {
  id = input$id
  ok = is.character(id) && length(id) == 1L && !is.na(id)
  list(level = 3L, categories = "process",
       paths = if (ok) path_rel(artifact_dir(id)) else character())
}

#' The `app` member spec: a `fun` for user calls and an `execute` for model code (IC-37)
#' @noRd
artifact_tool_spec = function() {
  description = paste0(
    "Launch the Shiny app written in <artifacts>/<id>/app.R as a new immutable version, with ",
    "the session objects named in data snapshotted into it; returns the URL, the validation ",
    "checks and a screenshot."
  )
  properties = list(
    id = list(type = "string", description = "Artifact id: lower-case letters, digits and '-'."),
    data = list(type = "array", items = list(type = "string"),
                description = "Names of session objects the app uses by name."),
    title = list(type = "string", description = "Short title."),
    kind = list(type = "string", description = "A registered artifact type: shiny or html."),
    check = list(type = "boolean", description = "Run the static and session checks."),
    launch = list(type = "boolean", description = "Start the app (default: interactive()).")
  )
  gptr_tool("app", description = description,
            parameters = list(type = "object", required = I("id"), properties = properties),
            execute = artifact_member_execute, fun = artifact_member_fun, exposure = "r",
            execution = "sequential", risk = artifact_risk,
            record = TRUE,
            annotations = list(read_only = FALSE, destructive = FALSE, idempotent = FALSE,
                               open_world = FALSE))
}

#' The `artifacts` section text (architecture 7.3, verbatim; IC-68)
#' @noRd
artifact_section_text = paste0(
  "For an interactive view (filters, drill-down, dashboards) build a Shiny app, not HTML/JS: ",
  "write app.R in <artifacts>/<id>/ (the directory is named in <environment>), one file ending ",
  "in shinyApp(ui, server) that uses the objects listed in data by name, then launch it in r ",
  "with peter$app(\"<id>\", data = c(\"obj\")). Read the shiny-bslib skill first. Revise app.R ",
  "with edit and call peter$app() again; check the returned screenshot and errors before saying ",
  "it is done."
)

#' The `artifacts` section: present only when shiny is installed (contract 9.3)
#' @noRd
artifact_section = function(ctx) if (artifact_shiny_available()) artifact_section_text else NULL

#' builtin:artifacts (contract 7.23, 10.3): the artifact types `shiny` and `html`, the member
#' `app`, the `artifacts` section and the `artifacts` checkpointer
#' @noRd
builtin_artifacts = function(gptr) {
  gptr$register(gptr_spec("artifact_type", "shiny", build = artifact_build_shiny,
                          check = artifact_check_shiny, launch = artifact_launch_shiny,
                          stop = artifact_stop_handle))
  gptr$register(gptr_spec("artifact_type", "html", build = artifact_build_html,
                          check = artifact_check_html, launch = artifact_launch_shiny,
                          stop = artifact_stop_handle))
  gptr$register(artifact_tool_spec())
  gptr$register(gptr_prompt_section("artifacts", artifact_section, tier = "T0", order = 600L,
                                    budget = 150L))
  gptr$register(gptr_spec("checkpointer", "artifacts", scope = "artifacts",
                          before = artifact_ckpt_before, after = artifact_ckpt_after,
                          undo = artifact_ckpt_undo, redo = artifact_ckpt_redo,
                          prune = artifact_ckpt_prune, describe = artifact_ckpt_describe))
  invisible(NULL)
}

on_load(ext_declare_builtin("artifacts", builtin_artifacts))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app|copy-artifact")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 335 ]` (333 in `test-artifact-app.R`, 2 copy rows with 0 copies each).

- [ ] **Step 5: Commit**

```bash
git add R/artifact-app.R tests/testthat/test-artifact-app.R tests/testthat/test-copy-artifact.R
git commit -m 'feat(artifact): add peter$app(), the artifacts section and builtin:artifacts'
```

### Task 10: `gptr_artifacts()`, relaunch, unload cleanup and NS-8 end to end

**Files:**
- Modify: `R/artifact-registry.R` (append)
- Test: `tests/testthat/test-artifact-registry.R` (append)
- Generated: `NAMESPACE` (`export(gptr_artifacts)`), `man/gptr_artifacts.Rd`

**Interfaces:**
- Consumes: Tasks 1-9 (`artifact_handle()`, `artifact_proc_get()`, `artifact_status()`, `artifact_stop()`, `artifact_sweep()`, `artifact_relaunch()`, `artifact_view()`, `artifact_browser_close()`, `artifact_dir_bytes()`, `artifact_meta_read()`, `artifact_exists()`, `artifact_id_check()`); P01 `new_listing(df, class, footer = NULL)`, `check_string()`, `check_flag()`, `check_number(x, arg, min, int, null)`, `gptr_abort()`, `on_load(expr)`, `on_unload(fun)`; tests: P08 `peter(...)` and the `peter` object, P06 `gptr_last()`, `session_data()`, P01 `local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_gptr_options()`, P04 `pid_alive()`, `job_list()`; the P14 hook that prints the NS-8 line at verbosity 2 and P02 `ev_dispatch(event, payload, session = NULL, ctx = NULL)` (the NS-8 test re-dispatches the recorded payload); the P10 `r` tool (its `details$artifacts`).
- Produces: the export `gptr_artifacts(id = NULL, open = FALSE, stop = FALSE, version = NULL)` (04 §6.4); `artifact_list()` -> `c("gptr_artifacts", "gptr_listing", "data.frame")` with `id`, `title`, `version`, `status`, `url`, `pid`, `bytes`, `path` (04 §5.12; an artifact whose committed `artifact.json` cannot be read, for example after a merge conflict, is named in the listing's footer instead of failing the listing); `artifact_unload()`, registered with `on_load(on_unload(artifact_unload))`.

`gptr_artifacts()` is 04 §6.4: without `id` a listing of every `artifact.json` of the workspace after a sweep of orphaned children; with `id` the handle (`stop = TRUE` stops the process and returns the handle invisibly, now `stopped`; `version =` relaunches that stored version, makes it current and returns the handle invisibly; `open = TRUE` relaunches a stopped artifact and opens the viewer when a human is present). Invalid combinations (`open`, `stop` or `version` without `id`; `stop` with `open` or `version`) are `gptr_error_invalid_argument`. `artifact_unload()` stops every artifact of this process and closes the headless browser when the package unloads (architecture 6.15: "children stop through `gptr_artifacts(id, stop = TRUE)`, `.onUnload` or R exit"; report 17 §4.3: the shared browser must not outlive the package); it is not registered as an exit finalizer (closing chromote's websocket while R shuts down crashed R in the scratch run of the earlier draft), so at R exit supervision, processx's cleanup and the child's watchdog end the processes and the next session's sweep removes stale run files. The two NS-8 tests run the north-star example on the fake provider (02 §8; architecture 10.6): the model writes `.gptr/artifacts/marker-explorer/app.R`, launches it with `peter$app()` in `r` and `artifact_start` carries the id, version 1 and the tokenised loopback URL; P14's renderer prints `artifact  marker-explorer  ->  <url>   (running in background)` for that payload (05 P23 acceptance 4: because the event fires inside the model's `r` evaluation, whose output P09 captures, with `tee` only when a human is present, the test sends the recorded payload through the registered hooks again and captures what they print, instead of reading the console capture of the run), the `r` result carries the NS-8 line and the checks, its `details$artifacts` names the app, the session holds one `gptr.artifact` entry, and `gptr_artifacts(id, stop = TRUE)` leaves no process; a broken app returns the child's error to the model (acceptance 2).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-registry.R`:

```r

tiny_app = c("library(shiny)", "ui = fluidPage('hi')", "server = function(input, output) {}",
             "shinyApp(ui, server)")

# Write a model-written working copy of an artifact
write_working = function(id, lines, file = "app.R") {
  dir = artifact_dir(id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_utf8(file.path(dir, file), lines)
  file.path(dir, file)
}

skip_if_cannot_launch = function() {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
}

test_that("gptr_artifacts() lists nothing when no artifact exists", {
  local_artifact_project()
  out = gptr_artifacts()
  expect_s3_class(out, c("gptr_artifacts", "gptr_listing", "data.frame"))
  expect_identical(names(out), c("id", "title", "version", "status", "url", "pid", "bytes",
                                 "path"))
  expect_identical(nrow(out), 0L)
  expect_output(print(out), "# 0 rows", fixed = TRUE)
})

test_that("gptr_artifacts() lists every artifact of the workspace", {
  local_artifact_project()
  seed_artifact("alpha", n = 2L)
  seed_artifact("beta")
  writeLines("x", file.path(artifact_version_dir("alpha", 1L), "app.R"))
  dir.create(artifact_dir("conflicted"))
  writeLines(c("<<<<<<< HEAD", "{\"id\": \"conflicted\"}"), artifact_meta_path("conflicted"))
  out = gptr_artifacts()
  expect_match(attr(out, "footer"), "not readable (skipped): conflicted", fixed = TRUE)
  expect_identical(out$id, c("alpha", "beta"))
  expect_identical(out$title, c("Title of alpha", "Title of beta"))
  expect_identical(out$version, c(2L, 1L))
  expect_identical(out$status, c("stopped", "stopped"))
  expect_true(all(is.na(out$url)) && all(is.na(out$pid)))
  expect_true(all(out$bytes > 0))
  expect_identical(basename(out$path), c("app.R", "app.R"))
})

test_that("gptr_artifacts() validates its arguments", {
  local_artifact_project()
  seed_artifact("alpha")
  expect_error(gptr_artifacts("absent"), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("con"), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts(stop = TRUE), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts(version = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", stop = TRUE, version = 1),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", version = 1.5), class = "gptr_error_invalid_argument")
  expect_error(gptr_artifacts("alpha", version = 3), class = "gptr_error_invalid_argument")
  h = gptr_artifacts("alpha")
  expect_s3_class(h, "gptr_artifact")
  expect_identical(h$status, "stopped")
  expect_invisible(gptr_artifacts("alpha", stop = TRUE))
})

test_that("version = relaunches a stored version; stop = TRUE leaves no process", {
  skip_if_cannot_launch()
  local_artifact_project()
  stops = local_events("artifact_stop")
  write_working("rel", tiny_app)
  peter$app("rel", check = FALSE, launch = FALSE)
  write_working("rel", sub("'hi'", "'v2'", tiny_app))
  peter$app("rel", check = FALSE, launch = FALSE)
  withr::defer(artifact_stop("rel", emit = FALSE))
  h = gptr_artifacts("rel", version = 1)
  expect_identical(h$status, "running")
  expect_identical(h$version, 1L)
  expect_identical(as.integer(artifact_meta_read("rel")$current), 1L)
  out = gptr_artifacts()
  expect_identical(out$status, "running")
  expect_identical(out$url, h$url)
  pid = out$pid
  expect_true(is.integer(pid) && !is.na(pid))
  ct = artifact_create_time(pid)
  expect_identical(job_list("artifact")$status, "running")
  stopped = gptr_artifacts("rel", stop = TRUE)
  expect_identical(stopped$status, "stopped")
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_false(file.exists(file.path(artifact_dir("rel"), "run", "run.json")))
  expect_identical(nrow(job_list("artifact")), 0L)
  expect_identical(gptr_artifacts()$status, "stopped")
  expect_identical(vapply(stops$events, function(e) e$reason, ""), "user")
})

test_that("open = TRUE relaunches a stopped artifact; the viewer opens only for a human", {
  skip_if_cannot_launch()
  local_artifact_project()
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  withr::local_options(viewer = function(url) seen$urls = c(seen$urls, url))
  write_working("viewed", tiny_app)
  peter$app("viewed", check = FALSE, launch = FALSE)
  withr::defer(artifact_stop("viewed", emit = FALSE))
  local_gptr_options(interactive = FALSE)
  h = gptr_artifacts("viewed", open = TRUE)
  expect_identical(h$status, "running")
  expect_identical(seen$urls, character())
  local_gptr_options(interactive = TRUE)
  gptr_artifacts("viewed", open = TRUE)
  expect_identical(seen$urls, h$url)
  expect_identical(artifact_proc_get("viewed")$url, h$url)
})

test_that("unloading the package stops every artifact of the process", {
  skip_if_cannot_launch()
  local_artifact_project()
  write_working("unl", tiny_app)
  peter$app("unl", check = FALSE, launch = TRUE)
  pid = artifact_proc_get("unl")$pid
  ct = artifact_create_time(pid)
  artifact_unload()
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_null(artifact_proc_get("unl"))
  expect_null(artifact_state$browser)
})

# NS-8 (02-north-star-examples.md section 8; architecture 10.6) on the fake provider
explorer_app = c(
  "library(shiny)",
  "ui = fluidPage(",
  "  titlePanel('Marker explorer'),",
  "  sidebarLayout(sidebarPanel(textInput('gene', 'Gene search')),",
  "                mainPanel(plotOutput('volcano'), tableOutput('table')))",
  ")",
  "server = function(input, output, session) {",
  "  shown = reactive(markers[grepl(input$gene, markers$gene, ignore.case = TRUE), ])",
  "  output$volcano = renderPlot(plot(markers$avg_log2FC, -log10(markers$p_val_adj),",
  "                                   xlab = 'log2 fold change', ylab = '-log10 adjusted p'))",
  "  output$table = renderTable(head(shown(), 20))",
  "}",
  "shinyApp(ui, server)"
)

ns08_prompt = paste("Build me an explorer for the marker table with a gene search box and a",
                    "volcano plot")

ns08_markers = function() {
  data.frame(gene = c("S100A9", "LYZ", "CD14", "MS4A1", "CD79A"),
             avg_log2FC = c(2.41, 3.05, 1.87, 2.9, 2.2),
             p_val_adj = c(1e-280, 3.4e-276, 9.8e-247, 1e-120, 2e-98))
}

# The text of the last tool result the fake provider received before request `i`
result_text = function(fake, i) {
  res = fake_requests(fake)[[i]]$last_results[[1]]
  paste(vapply(res$content, function(b) b$text %||% "", ""), collapse = "\n")
}

test_that("NS-8: the agent writes app.R, peter$app() launches it, the renderer prints the line", {
  skip_if_cannot_launch()
  root = local_artifact_project()
  withr::defer(artifact_stop("marker-explorer", emit = FALSE))
  withr::defer(artifact_browser_close())
  starts = local_events("artifact_start")
  e = new.env()
  e$markers = ns08_markers()
  code = paste0("a = peter$app(\"marker-explorer\", data = \"markers\", ",
                "title = \"Marker explorer\", launch = TRUE)\na")
  fake = local_fake_provider(list(
    fake_tool("write", path = ".gptr/artifacts/marker-explorer/app.R",
              content = paste(explorer_app, collapse = "\n")),
    fake_tool("r", code = code),
    "The marker explorer is running."
  ))
  local_gptr_options(verbose = 2L)
  invisible(utils::capture.output(peter(prompt = ns08_prompt, model = fake, envir = e,
                                       mode = auto)))
  expect_true(file.exists(file.path(root, ".gptr", "artifacts", "marker-explorer", "app.R")))
  expect_length(starts$events, 1L)
  ev = starts$events[[1]]
  expect_identical(ev$id, "marker-explorer")
  expect_identical(ev$version, 1L)
  expect_match(ev$url, "^http://127\\.0\\.0\\.1:[0-9]+/\\?gptr_token=[0-9a-f]{32}$")
  line = paste0("artifact  marker-explorer  ->  ", ev$url, "   (running in background)")
  # The event fired inside the model's r evaluation, whose output P09 captures (tee only with a
  # human), so P14's line went to the r output, not to this capture: the payload the run
  # dispatched goes through the registered hooks again, where P14's renderer prints the line
  printed = utils::capture.output(invisible(ev_dispatch("artifact_start", ev)))
  expect_true(line %in% printed)
  seen = result_text(fake, 3L)
  expect_match(seen, line, fixed = TRUE)
  expect_match(seen, "checks: parse ok | launch ok | http ok", fixed = TRUE)
  entries = session_data(gptr_last())$entries
  r_results = Filter(function(x) {
    identical(x$type, "message") && identical(x$message$role, "tool_result") &&
      identical(x$message$tool_name, "r")
  }, entries)
  expect_identical(unlist(r_results[[1]]$message$details$artifacts),
                   ".gptr/artifacts/marker-explorer/app.R")
  art = Filter(function(x) identical(x$custom_type, "gptr.artifact"), entries)
  expect_length(art, 1L)
  expect_identical(art[[1]]$data$id, "marker-explorer")
  expect_identical(as.integer(art[[1]]$data$version), 1L)
  expect_identical(art[[1]]$data$status, "running")
  expect_s3_class(e$a, "gptr_artifact")
  pid = artifact_proc_get("marker-explorer")$pid
  ct = artifact_create_time(pid)
  gptr_artifacts("marker-explorer", stop = TRUE)
  expect_false(isTRUE(pid_alive(pid, ct)))
  expect_identical(gptr_artifacts()$status, "stopped")
})

test_that("a broken app returns the child's error to the model", {
  skip_if_cannot_launch()
  local_artifact_project()
  withr::defer(artifact_stop("broken", emit = FALSE))
  broken = c("library(shiny)", "ui = fluidPage(textOutput(no_such_object))",
             "server = function(input, output, session) {}", "shinyApp(ui, server)")
  fake = local_fake_provider(list(
    fake_tool("write", path = ".gptr/artifacts/broken/app.R",
              content = paste(broken, collapse = "\n")),
    fake_tool("r", code = "a = peter$app(\"broken\", launch = TRUE)"),
    "The app did not start."
  ))
  peter("Build an app", model = fake, envir = new.env(), mode = auto)
  seen = result_text(fake, 3L)
  expect_match(seen, "stage launch", fixed = TRUE)
  expect_match(seen, "no_such_object", fixed = TRUE)
  expect_identical(gptr_artifacts("broken")$status, "failed")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-registry")'
```

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 60 ]`; the eight new tests error with `could not find function "gptr_artifacts"` (and `"artifact_unload"`); the NS-8 test passes its 14 expectations up to its `gptr_artifacts(..., stop = TRUE)` call and the broken-app test its two up to `gptr_artifacts("broken")`.

- [ ] **Step 3: Write the implementation**

Append to `R/artifact-registry.R`:

```r

# ---- gptr_artifacts(), the listing and unload cleanup -----------------------------------------

#' The gptr_artifacts listing (contract 5.12): one row per artifact.json of the workspace
#'
#' artifact.json is committed, so a merge conflict or a hand edit can leave one unreadable; such
#' an artifact is named in the footer instead of failing the whole listing.
#' @noRd
artifact_list = function() {
  root = artifact_root()
  files = if (dir.exists(root)) Sys.glob(file.path(root, "*", "artifact.json")) else character()
  ids = basename(dirname(files))
  readable = vapply(ids, function(id) !is.null(artifact_meta_read(id)), NA, USE.NAMES = FALSE)
  footer = if (any(!readable)) {
    paste0("# artifact.json not readable (skipped): ", paste(ids[!readable], collapse = ", "))
  }
  rows = lapply(ids[readable], function(id) {
    h = artifact_handle(id)
    rec = artifact_proc_get(id)
    data.frame(id = id, title = h$title, version = h$version, status = h$status, url = h$url,
               pid = if (identical(h$status, "running")) rec$pid else NA_integer_,
               bytes = artifact_dir_bytes(id), path = h$path, stringsAsFactors = FALSE)
  })
  df = if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(id = character(), title = character(), version = integer(),
               status = character(), url = character(), pid = integer(), bytes = numeric(),
               path = character(), stringsAsFactors = FALSE)
  }
  new_listing(df, "gptr_artifacts", footer = footer)
}

#' List, open, relaunch and stop artifacts
#'
#' Artifacts are Shiny apps the agent builds from objects in your session. It writes
#' `.gptr/artifacts/<id>/app.R` and launches it with `peter$app("<id>", data = c("obj"))`, which
#' snapshots the named objects into an immutable version directory (`v001/`, `v002/`, ...) and
#' serves it from a supervised background R process on `127.0.0.1`, so the console stays free.
#' `gptr_artifacts()` lists the artifacts of the workspace (`.gptr/`, else a temporary
#' directory) and manages their processes.
#'
#' @param id `NULL` to list every artifact, or the id of one artifact.
#' @param open `TRUE` to open the artifact in the IDE viewer or the browser (only in an
#'   interactive session); a stopped artifact is relaunched first.
#' @param stop `TRUE` to stop the artifact's process (interrupt, a 3 s grace, then the process
#'   tree is killed).
#' @param version The number of a stored version (`2` for `v002/`) to relaunch and make current.
#' @return Without `id`, a `gptr_artifacts` data frame with the columns `id`, `title`, `version`
#'   (the current version), `status` (`running`, `stopped` or `failed`), `url`, `pid`, `bytes`
#'   (disk use of the artifact directory) and `path` (the working copy). With `id`, the
#'   `gptr_artifact` handle: a list with `id`, `title`, `kind`, `version`, `url` (it carries the
#'   launch's access token), `path`, `status`, `checks` (`parse`, `launch`, `http` and `session`,
#'   each `TRUE`, `FALSE` or `NA`, plus `messages`), `screenshot` and `session`; it is returned
#'   invisibly after `open`, `stop` or `version`.
#' @section Security considerations:
#' An artifact runs model-written code in a separate R process whose environment holds none of
#' your registered secrets. It listens only on `127.0.0.1`, and every launch gets a new 128-bit
#' access token that its URL carries (`?gptr_token=`); without the openssl package on Windows
#' there is no token and a notice says so. The data snapshot in `vNNN/data/` is a copy of the
#' objects named in `data`; the `.gptr/.gitignore` that `gptr_init()` writes keeps it and `run/`
#' out of git.
#' @section Options:
#' `gptr.artifact_max_bytes` (default `5e8`): the largest total `object.size()` of the objects
#' one version may snapshot; above it `peter$app()` signals `gptr_error_artifact_too_large`.
#' @examples
#' gptr_artifacts()                      # an empty listing when no artifact exists
#' @export
gptr_artifacts = function(id = NULL, open = FALSE, stop = FALSE, version = NULL) {
  check_string(id, "id", null = TRUE)
  check_flag(open, "open")
  check_flag(stop, "stop")
  version = check_number(version, "version", min = 1, int = TRUE, null = TRUE)
  if (is.null(id)) {
    if (open || stop || !is.null(version)) {
      gptr_abort("`open`, `stop` and `version` need an artifact `id`.", "invalid_argument",
                 arg = "id", expected = "an artifact id when open, stop or version is set")
    }
    artifact_sweep()
    return(artifact_list())
  }
  artifact_id_check(id)
  if (!artifact_exists(id)) {
    gptr_abort("`id` does not name an existing artifact; see gptr_artifacts().",
               "invalid_argument", arg = "id", expected = "the id of an existing artifact")
  }
  if (stop && (open || !is.null(version))) {
    gptr_abort("`stop = TRUE` cannot be combined with `open` or `version`.", "invalid_argument",
               arg = "stop", expected = "FALSE when open or version is set")
  }
  if (stop) {
    artifact_stop(id, reason = "user")
    return(invisible(artifact_handle(id)))
  }
  if (!is.null(version)) {
    artifact_relaunch(id, version)
  } else if (open && !identical(artifact_status(id), "running")) {
    current = as.integer(artifact_meta_read(id)$current %||% 0L)
    if (current < 1L) {
      gptr_abort("This artifact has no version yet: call peter$app() first.", "invalid_argument",
                 arg = "open", expected = "an artifact with at least one version")
    }
    artifact_relaunch(id, current)
  }
  handle = artifact_handle(id)
  if (open) artifact_view(handle$url)
  if (open || !is.null(version)) invisible(handle) else handle
}

#' Stop every artifact of this process and close the headless browser (.onUnload; report 17
#' section 4.3: the shared browser must not outlive the package). Not registered as an exit
#' finalizer: closing chromote's websocket while R shuts down crashed R in this plan's scratch run;
#' at exit, supervision, processx's cleanup and the child's watchdog end the processes, and the
#' next session's sweep removes stale run files.
#' @noRd
artifact_unload = function() {
  for (id in ls(artifact_state$procs, all.names = TRUE)) {
    try(artifact_stop(id, reason = "unload", emit = FALSE), silent = TRUE)
  }
  artifact_browser_close()
  invisible(NULL)
}

on_load(on_unload(artifact_unload))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "artifact-registry")'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); pkgload::dev_example("gptr_artifacts")'
```

Expected: `devtools::document()` adds `export(gptr_artifacts)` to `NAMESPACE` and writes `man/gptr_artifacts.Rd`; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 105 ]`; the example prints the call and `# 0 rows`; no `artifacts` directory is created (the listing reads `workspace_root(create = FALSE)`).

- [ ] **Step 5: Commit**

```bash
git add R/artifact-registry.R tests/testthat/test-artifact-registry.R NAMESPACE man/gptr_artifacts.Rd
git commit -m "feat(artifact): add gptr_artifacts(), relaunch and unload cleanup"
```

### Task 11: The `shiny-bslib` skill

**Files:**
- Create: `inst/gptr/skills/shiny-bslib/SKILL.md`
- Test: `tests/testthat/test-artifact-app.R` (append)

**Interfaces:**
- Consumes: Task 2 (`artifact_static_check()`); yaml `yaml::yaml.load()` (tests: the frontmatter's `name` and `description`; yaml is an Import, 03 §9). No P17 function is called: P17 is outside P23's dependency closure (05: P10, P11, P14, P16). P17's discovery of gptr's own `inst/gptr/skills/` (P17 Task 3: "P23 and P19 add `shiny-bslib` and `gptr-orchestration` to `inst/gptr/skills/`") picks the file up at run time without a code dependency in either direction.
- Produces: the shipped skill `shiny-bslib`, whose catalog line is exactly the one of 03 §7.3: `- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, cards, value boxes) for artifacts. [skill:shiny-bslib/SKILL.md]`.

The skill is the house style of report 17 §4.4 (verified bslib 0.10.0 signatures in §2.4; Posit's `shiny-bslib` skill rules: `page_sidebar()`, `layout_columns()`, `card(full_screen = TRUE)`, never nest `card()` or `page_*()`), rewritten for gptr's flow: the model writes `app.R` with `write`, launches it with `peter$app()` in `r`, revises with `edit` (an edit is 3.9x cheaper than a rewrite, G2 (a)) and reads the checks and the screenshot. It uses `=` and `|>` (S-9), recommends `peter$describe(x)`, `dim()` and `head()` and never `str(` (IC-67; P07's test scans shipped skills), is ASCII, and its one R example passes the static checks of Task 2. The frontmatter follows P17's `high-performance-r` skill (`name`, quoted `description`, `license`, `metadata`). The `html` fallback is one paragraph (S-5).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-artifact-app.R`:

```r

test_that("the shiny-bslib skill has its catalog line, house style and a valid example app", {
  f = system.file("gptr", "skills", "shiny-bslib", "SKILL.md", package = "gptr", mustWork = TRUE)
  # The frontmatter is read with yaml (an Import, 03 section 9), not P17's skill_parse(): P17 is
  # outside P23's dependency closure (05: P10, P11, P14, P16)
  lines = readLines(f, encoding = "UTF-8")
  end = which(lines == "---")[2L]
  s = yaml::yaml.load(paste(lines[2L:(end - 1L)], collapse = "\n"))
  expect_identical(s[["name"]], "shiny-bslib")
  expect_identical(paste0("- ", s[["name"]], ": ", s[["description"]], " [skill:", s[["name"]],
                          "/SKILL.md]"),
                   paste0("- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, ",
                          "cards, value boxes) for artifacts. [skill:shiny-bslib/SKILL.md]"))
  txt = paste(lines, collapse = "\n")
  expect_false(grepl("(^|[^A-Za-z0-9_.])str\\(", txt))
  expect_false(grepl("<\\-", txt))
  expect_true(all(utf8ToInt(txt) < 128L))
  expect_match(txt, "peter$app(\"<id>\", data = c(\"obj\"))", fixed = TRUE)
  open = which(lines == "```r")
  expect_length(open, 1L)
  close = which(lines == "```")
  code = lines[(open + 1L):(close[close > open][1L] - 1L)]
  expect_no_error(parse(text = code, keep.source = FALSE))
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  expect_true(artifact_static_check(code)$ok)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "artifact-app")'
```

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 333 ]`; the new test errors with `no file found` (from `system.file(..., mustWork = TRUE)`).

- [ ] **Step 3: Write the implementation**

Create `inst/gptr/skills/shiny-bslib/SKILL.md`:

````markdown
---
name: shiny-bslib
description: "Build Shiny apps with bslib layouts (page_sidebar, cards, value boxes) for artifacts."
license: MIT
metadata:
  source: "gptr research report 17, sections 2.4 and 4.4"
---

# Shiny artifacts with bslib

Write `<artifacts>/<id>/app.R` (id: lower-case letters, digits, `-`), then in r run
`a = peter$app("<id>", data = c("obj"))` and print `a`. Each call snapshots the objects into a new
version on the same URL. Fix what the checks, messages or screenshot show with edit (not a rewrite)
and call `peter$app()` again until no check reads FAILED.

Rules for app.R:
- One file ending in `shinyApp(ui, server)`; the objects in `data` exist under their names. Never
  read files or call `setwd()`, `runApp()` or `install.packages()`.
- Ship small data (the rows and columns shown); check it in r with `dim()` or `peter$describe(x)`.
- `page_sidebar()` with the inputs in `sidebar()`; KPIs as `value_box()` in `layout_columns()`;
  each chart or table in `card(card_header(), ..., full_screen = TRUE)`; never nest cards or pages.
- `renderPlot()` with ggplot2 and `theme_minimal()`; plotly, DT or leaflet only if `<r_env>` lists
  them. Filter once in `reactive()`; `req()` for empty inputs, `validate(need())` for empty
  results; no custom CSS or JS. Use `=` and `|>`.

```r
library(shiny)
library(bslib)
ui = page_sidebar(
  title = "Markers",
  sidebar = sidebar(textInput("gene", "Gene")),
  layout_columns(value_box("Markers shown", textOutput("n"))),
  card(card_header("Top markers"), tableOutput("top"), full_screen = TRUE)
)
server = function(input, output, session) {
  shown = reactive(markers[grepl(input$gene, markers$gene, ignore.case = TRUE), ])
  output$n = renderText(nrow(shown()))
  output$top = renderTable({
    validate(need(nrow(shown()) > 0, "No marker matches the search."))
    head(shown(), 20)
  })
}
shinyApp(ui, server)
```

Raw HTML only when truly required: write `<artifacts>/<id>/page.html` and call
`peter$app("<id>", data = c("obj"), kind = "html")`; the data is `window.GPTR_DATA.<name>`.
````

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact-app")'
Rscript --vanilla -e 'devtools::test(filter = "skill-discover|bench-context")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 342 ]` for `artifact-app` (the skill test needs no P17 function; it reads the frontmatter with yaml); P17's and P07's suites stay green (`FAIL 0`): gptr's own skills now include `shiny-bslib`, whose catalog line is the second line of 03 §7.3's `<skills>` catalog, and no shipped text mentions `str(` (IC-67). The second command is a regression cross-check only: in the numeric execution order P17 is already in `R/`, and if it were not, the filter would still select P07's `test-bench-context.R`.

- [ ] **Step 5: Commit**

```bash
git add inst/gptr/skills/shiny-bslib/SKILL.md tests/testthat/test-artifact-app.R
git commit -m "feat(artifact): add the shiny-bslib skill"
```

### Task 12: The NS-8 golden transcript and baseline row

**Files:**
- Create: `dev/bench/tokens/fixtures/ns08-marker-explorer.json`
- Modify: `dev/bench/tokens/baseline.csv` (one row, written by P07's runner with `--update`)

**Interfaces:**
- Consumes (P07, IC-73): `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]` and its fixture format (`id`, `north_star`, `description`, `mode`, `human`, `preset`, `models`, `standins`, `environment`, `files`, `objects`, `facts`, `turns` with `prompt`, `source`, `context`, `steps` of `text` and `calls` (`id`, `name`, `input`, `result`, `images`, `details`)); its metrics (`requests`, `prefix`, `input_total`, `output_total`, `image_tokens`, `catalog`, `facts`, `est_prefix`, `est_input_total`) and gates (prefix +2%, input and output totals +5%, requests and image tokens +0, catalog +5%, facts no loss; `gptr_error_token_regression`); the development package rtiktoken.
- Produces: the fixture `ns08-marker-explorer` and its row in `dev/bench/tokens/baseline.csv` (05 P23 acceptance 5: "P23's NS-8 fixture is added to `dev/bench/tokens/`"; P24 gates every row).

The fixture scripts NS-8 the way architecture 10.6 walks it: `markers` is attached (a 4,211 x 7 marker table built by deterministic code, no RNG), the `<artifacts>` section and the `shiny-bslib` catalog line steer the model, which reads the skill once (the result is Task 11's `SKILL.md`, 582 o200k tokens), writes `.gptr/artifacts/marker-explorer/app.R` (the bslib explorer below, which this plan's scratch run launched through the full ladder: parse, launch, HTTP 200 and the session check all ok), calls `peter$app()` in one `r` call whose result is the handle's three lines plus P09's state lines (111 o200k tokens) and one 1000x700 screenshot (900 image tokens, 03 §12.2 "artifact result | about 80 + about 900 screenshot"), and answers. The `<environment>` block names the artifacts directory (03 §7.4 `Artifacts: .gptr/artifacts`). The runner never runs the scripted code; the stand-ins are those of P07's fixtures (used only when no real spec is registered, so the real `artifacts` section and skills catalog are measured once their owners are loaded).

- [ ] **Step 1: Write the failing test**

Check the development tool first: `Rscript --vanilla -e 'cat(requireNamespace("rtiktoken", quietly = TRUE), "\n")'` must print `TRUE`. If it prints `FALSE`, stop and ask the maintainer to install rtiktoken (CRAN) into their library; do not install it from a plan step (conventions §1).

Create `dev/bench/tokens/fixtures/ns08-marker-explorer.json`:

````json
{
  "id": "ns08-marker-explorer",
  "north_star": 8,
  "description": "peter(\"Build me an explorer for the marker table with a gene search box and a volcano plot\", markers) at the console: standard preset, manual mode, a human present, no bound document; the model reads the shiny-bslib skill, writes .gptr/artifacts/marker-explorer/app.R, launches it with peter$app() in r (the result carries the NS-8 line, the checks and a 1000x700 screenshot), then answers.",
  "mode": "manual",
  "human": true,
  "preset": null,
  "models": ["benchmain/benchmain-1"],
  "standins": ["artifacts", "system1", "skills", "r_env"],
  "environment": "Date: 2026-09-29\nWorking directory: /Users/me/project (project root)\nArtifacts: .gptr/artifacts\nFront end: interactive console (RStudio)\nR 4.4.3 on aarch64-apple-darwin20; RAM 24 GB (17 GB free)",
  "files": {
    "AGENTS.md": "# AGENTS.md\n- Style: = for assignment, |> for pipes, snake_case.\n- `markers` is the FindAllMarkers() table of the PBMC clustering (one row per gene and cluster)."
  },
  "objects": {
    "markers": "data.frame(p_val = 10^-((1:4211) %% 300), avg_log2FC = round(0.25 + ((1:4211) %% 37) / 10, 2), pct.1 = round(0.3 + ((1:4211) %% 70) / 100, 2), pct.2 = round(0.05 + ((1:4211) %% 40) / 100, 2), p_val_adj = pmin(1, 10^-((1:4211) %% 300) * 2e4), cluster = factor((1:4211) %% 12), gene = paste0(\"G\", 1:4211))"
  },
  "facts": ["markers", "gene", "avg_log2FC", "p_val_adj", "cluster"],
  "turns": [
    {
      "prompt": "Build me an explorer for the marker table with a gene search box and a volcano plot",
      "source": "prompt",
      "context": [
        {
          "label": "markers",
          "class": "data.frame"
        }
      ],
      "steps": [
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_01",
              "name": "read",
              "input": {
                "path": "skill:shiny-bslib/SKILL.md"
              },
              "result": "---\nname: shiny-bslib\ndescription: \"Build Shiny apps with bslib layouts (page_sidebar, cards, value boxes) for artifacts.\"\nlicense: MIT\nmetadata:\n  source: \"gptr research report 17, sections 2.4 and 4.4\"\n---\n\n# Shiny artifacts with bslib\n\nWrite `<artifacts>/<id>/app.R` (id: lower-case letters, digits, `-`), then in r run\n`a = peter$app(\"<id>\", data = c(\"obj\"))` and print `a`. Each call snapshots the objects into a new\nversion on the same URL. Fix what the checks, messages or screenshot show with edit (not a rewrite)\nand call `peter$app()` again until no check reads FAILED.\n\nRules for app.R:\n- One file ending in `shinyApp(ui, server)`; the objects in `data` exist under their names. Never\n  read files or call `setwd()`, `runApp()` or `install.packages()`.\n- Ship small data (the rows and columns shown); check it in r with `dim()` or `peter$describe(x)`.\n- `page_sidebar()` with the inputs in `sidebar()`; KPIs as `value_box()` in `layout_columns()`;\n  each chart or table in `card(card_header(), ..., full_screen = TRUE)`; never nest cards or pages.\n- `renderPlot()` with ggplot2 and `theme_minimal()`; plotly, DT or leaflet only if `<r_env>` lists\n  them. Filter once in `reactive()`; `req()` for empty inputs, `validate(need())` for empty\n  results; no custom CSS or JS. Use `=` and `|>`.\n\n```r\nlibrary(shiny)\nlibrary(bslib)\nui = page_sidebar(\n  title = \"Markers\",\n  sidebar = sidebar(textInput(\"gene\", \"Gene\")),\n  layout_columns(value_box(\"Markers shown\", textOutput(\"n\"))),\n  card(card_header(\"Top markers\"), tableOutput(\"top\"), full_screen = TRUE)\n)\nserver = function(input, output, session) {\n  shown = reactive(markers[grepl(input$gene, markers$gene, ignore.case = TRUE), ])\n  output$n = renderText(nrow(shown()))\n  output$top = renderTable({\n    validate(need(nrow(shown()) > 0, \"No marker matches the search.\"))\n    head(shown(), 20)\n  })\n}\nshinyApp(ui, server)\n```\n\nRaw HTML only when truly required: write `<artifacts>/<id>/page.html` and call\n`peter$app(\"<id>\", data = c(\"obj\"), kind = \"html\")`; the data is `window.GPTR_DATA.<name>`.",
              "details": {
                "path": "skill:shiny-bslib/SKILL.md"
              }
            }
          ]
        },
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_02",
              "name": "write",
              "input": {
                "path": ".gptr/artifacts/marker-explorer/app.R",
                "content": "library(shiny)\nlibrary(bslib)\nlibrary(ggplot2)\n\nui = page_sidebar(\n  title = \"Marker explorer\",\n  sidebar = sidebar(\n    textInput(\"gene\", \"Gene search\", placeholder = \"e.g. CD14\"),\n    selectInput(\"cluster\", \"Cluster\", c(\"All\", sort(unique(as.character(markers$cluster))))),\n    sliderInput(\"padj\", \"Adjusted p-value below\", min = 0, max = 0.1, value = 0.05)\n  ),\n  layout_columns(\n    value_box(\"Significant markers\", textOutput(\"n\")),\n    value_box(\"Clusters shown\", textOutput(\"k\"))\n  ),\n  card(card_header(\"Volcano plot\"), plotOutput(\"volcano\"), full_screen = TRUE),\n  card(card_header(\"Markers\"), tableOutput(\"table\"), full_screen = TRUE)\n)\n\nserver = function(input, output, session) {\n  shown = reactive({\n    d = markers\n    if (!identical(input$cluster, \"All\")) d = d[as.character(d$cluster) == input$cluster, ]\n    if (nzchar(input$gene)) d = d[grepl(input$gene, d$gene, ignore.case = TRUE), ]\n    d\n  })\n  output$n = renderText(format(sum(shown()$p_val_adj < input$padj), big.mark = \",\"))\n  output$k = renderText(length(unique(shown()$cluster)))\n  output$volcano = renderPlot({\n    d = shown()\n    validate(need(nrow(d) > 0, \"No marker matches the search.\"))\n    d$significant = d$p_val_adj < input$padj\n    ggplot(d, aes(avg_log2FC, -log10(p_val_adj + 1e-300), colour = significant)) +\n      geom_point(alpha = 0.6) +\n      scale_colour_manual(values = c(`FALSE` = \"grey60\", `TRUE` = \"firebrick\")) +\n      labs(x = \"Average log2 fold change\", y = \"-log10 adjusted p-value\", colour = \"Significant\") +\n      theme_minimal()\n  })\n  output$table = renderTable({\n    d = shown()\n    cols = c(\"gene\", \"cluster\", \"avg_log2FC\", \"pct.1\", \"pct.2\", \"p_val_adj\")\n    head(d[order(d$p_val_adj), cols], 25)\n  })\n}\n\nshinyApp(ui, server)"
              },
              "result": "Successfully wrote to .gptr/artifacts/marker-explorer/app.R",
              "details": {
                "path": ".gptr/artifacts/marker-explorer/app.R",
                "bytes": 1734,
                "created": true
              }
            }
          ]
        },
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_03",
              "name": "r",
              "input": {
                "code": "a = peter$app(\"marker-explorer\", data = \"markers\", title = \"Marker explorer\")\na"
              },
              "result": "artifact  marker-explorer  ->  http://127.0.0.1:4827/?gptr_token=5385506dfcec7dae1f99162397a857c3   (running in background)\nchecks: parse ok | launch ok | http ok | session ok\nscreenshot: .gptr/artifacts/marker-explorer/run/screenshot-v001.png\n[r] + a <gptr_artifact>\n[status: ok; 2 of 2 top-level expressions completed; 6.8s]",
              "images": [
                [1000, 700]
              ],
              "details": {
                "code": "a = peter$app(\"marker-explorer\", data = \"markers\", title = \"Marker explorer\")\na",
                "status": "ok",
                "artifacts": [".gptr/artifacts/marker-explorer/app.R"]
              }
            }
          ]
        },
        {
          "text": "The marker explorer is running at http://127.0.0.1:4827/?gptr_token=5385506dfcec7dae1f99162397a857c3. Type a gene in the search box; the cluster menu and the adjusted p-value slider filter the volcano plot and the table of top markers. All four checks passed and the screenshot shows both cards. The app is .gptr/artifacts/marker-explorer/app.R with a snapshot of `markers` in v001/; `gptr_artifacts(\"marker-explorer\", stop = TRUE)` stops it.",
          "calls": []
        }
      ]
    }
  ]
}
````

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: P07's static-prefix table and one results row per fixture (including `ns08-marker-explorer`) are printed, then the run stops with the `gptr_error_token_regression` message:

```text
Error: Token-efficiency regression:
  ns08-marker-explorer: no baseline row (run with --update ns08-marker-explorer)
Execution halted
```

- [ ] **Step 3: Write the implementation**

Record the baseline row with P07's runner:

```bash
Rscript --vanilla dev/bench/tokens/run.R --update ns08-marker-explorer
```

Expected: the static-prefix and results tables, then `baseline written: ns08-marker-explorer`. Check the new row of `dev/bench/tokens/baseline.csv` against what the fixture scripts:

- `requests` is 4 (before the `read` call, before the `write` call, before the `r` call, before the answer);
- `prefix` and `catalog` equal those of the `ns02-mixed-model` row of the same run (the same composition: standard preset, a human, no document, the same stand-ins); with every built-in registered the prefix is the IC-68 total of 2,722 o200k tokens, of which the `<artifacts>` section is 124 and the `shiny-bslib` catalog line part of the 542-token T1 fixture;
- `output_total` is 781 (the `read` call 17, the `write` call with the app 613, the `r` call 29, the answer 122; a call counts its name plus the JSON of its input);
- `image_tokens` is 900 (`ceiling(1000 / 28) * ceiling(700 / 28)`, P01's `est_image_tokens(1000, 700, "anthropic")`);
- `facts` is the number of the five fixture facts (`markers`, `gene`, `avg_log2FC`, `p_val_adj`, `cluster`) found in the first message's `<attached name="markers">` block (P09's describer at its default budget);
- `input_total` is the sum over the four requests of the prefix and every message so far: `4 x prefix + 4 x <first user message> + 3 x (17 + 582) + 2 x (613 + 14) + (29 + 111 + 900)`, that is `4 x prefix + 4 x <first user message> + 4,091` (the first user message holds the project instructions, the pinned `<environment>`, the mode block, the workspace and the `<attached name="markers">` description).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: the last line `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`, where `<n>` is the number of files in `dev/bench/tokens/fixtures/`.

- [ ] **Step 5: Commit**

```bash
git add dev/bench/tokens/fixtures/ns08-marker-explorer.json dev/bench/tokens/baseline.csv
git commit -m "chore(bench): add the NS-8 artifact golden transcript and baseline row"
```

(`dev/bench/tokens/results.csv` is regenerated on every run and is not committed.)

## Plan acceptance

Every acceptance check of 05 P23, including its review amendments, the task and test that prove it, and the command with its expected result. Counts assume the environment stated under Global Constraints (shiny, httpuv, later, openssl, chromote and a Chrome binary installed, `NOT_CRAN=true` as `devtools::test()` sets it, `capabilities("profmem")` TRUE).

| # | Acceptance check (05 P23) | Proved by |
|---|---|---|
| 1 | `Rscript --vanilla -e 'devtools::test(filter = "artifact\|copy-artifact")'` is green (launch tests skip on CRAN and without shiny; the chromote step skips without chromote) | all tasks; `test-artifact-app.R` (342), `test-artifact-registry.R` (105), `test-copy-artifact.R` (2). Every process-starting test begins with `skip_on_cran()` through `skip_if_cannot_launch()` (shiny, httpuv, later) or calls `skip_on_cran()` itself; the two session-check tests of Task 6 call `skip_if_no_chrome()`; the copy rows skip on CRAN and without profmem inside `expect_no_copy()` |
| 2a | The validation ladder on a fixture app: parse, launch, HTTP 200, session check | Task 2 "static checks accept a well-formed app ..." (parse); Task 7 "artifact_start() runs the ladder, records the run and keeps the port across versions" (launch, HTTP 200, checks recorded); Task 6 "the session check passes a working app and returns a 1000x700 screenshot" and "the session check catches render errors and crashed servers but not validate()"; Task 9 "peter$app() launches through the ladder and keeps .Random.seed (IC-61)" (all four stages through `peter$app(check = TRUE)`) |
| 2b | A broken app returns the child's error to the model | Task 10 "a broken app returns the child's error to the model" (the fake provider's third request carries `stage launch` and `no_such_object`); Task 7 "a broken app fails at the launch stage with the child's error in the log tail"; Task 4 "a broken app ends the child before a port exists, with its error on stderr" |
| 2c | The child's environment contains no registered secret | Task 7 "the artifact child gets no registered secret in its environment" (`ps::ps_environ()` of the running child: neither the secret-named variable nor a plain variable holding the registered value) |
| 2d | The port is random and loopback | Task 4 "ports come from port_candidates() after the artifact's previous port" and "artifact_serve() publishes a loopback port and serves only requests with the token" (49152-65535 on 127.0.0.1); Task 7 "the launcher serves a version on a random loopback port behind the token" |
| 2e | `gptr_artifacts(id, stop = TRUE)` leaves no process | Task 10 "version = relaunches a stored version; stop = TRUE leaves no process" (pid with its creation time gone, `run.json` removed, no job row) and the NS-8 test |
| 3a | A second `peter$app()` after an edit creates `v002` without touching `v001` | Task 9 "a second peter$app() after an edit creates v002 without touching v001" (md5 of every `v001` file unchanged; `v002` holds the edited app and the changed data) |
| 3b | The snapshot leaves the source object editable in place (copy row) | Task 9 `test-copy-artifact.R`: user call and model-code call of `peter$app(data = "big")` on `runif(5e6)`, 0 copies on `big[1] = 0`, and the snapshot file exists |
| 4 | NS-8 on the fake provider writes `.gptr/artifacts/marker-explorer/app.R` and P14's renderer prints `artifact  marker-explorer  ->  <url>   (running in background)` on `artifact_start` (IC-71) | Task 10 "NS-8: the agent writes app.R, peter$app() launches it, the renderer prints the line" (the run emits one `artifact_start` with the id, version 1 and the tokenised loopback URL; P14's registered hook prints the exact line for that payload at verbosity 2; the `r` result carries the line and the checks; `details$artifacts` names the app; one `gptr.artifact` entry) |
| 5a | `peter$app("con")` is refused | Task 1 "artifact ids follow contract 11.6 and refuse Windows reserved names"; Task 9 "peter$app() refuses reserved ids, unknown kinds and a missing working copy" |
| 5b | A data object named `a/b` snapshots as `data/001.rds` | Task 3 "objects are snapshotted as numbered files with a loader that binds their names"; Task 9 (the mapping in `artifact.json`) |
| 5c | A request without the token is rejected | Task 4 "artifact_serve() publishes a loopback port and serves only requests with the token" (403 without and with a wrong token); Task 7 launcher test |
| 5d | `.Random.seed` is unchanged by `peter$app(check = TRUE)` | Task 9 "peter$app() launches through the ladder and keeps .Random.seed (IC-61)"; Task 7 "the ladder with the session check leaves .Random.seed unchanged (IC-61)"; Task 6 screenshot test |
| 5e | A stopped artifact's status is `stopped` | Task 5 "a record's status is running, then stopped after a requested stop (IC-60)"; Task 7 "a launch that cannot start reads failed and keeps its checks" (a requested stop turns `failed` into `stopped`); Task 10 stop test |
| 5f | P23's NS-8 fixture is added to `dev/bench/tokens/` (IC-73) | Task 12 (`ns08-marker-explorer.json`, its baseline row, `run.R --check` OK) |
| R1 | Review amendments: the `artifacts` prompt section (IC-68) | Task 9 "the artifacts section is architecture 7.3 verbatim and needs shiny" and the registration test (T0, order 600, budget 150) |
| R2 | Windows reserved ids refused; numbered data files with the mapping in `artifact.json` (IC-63) | rows 5a, 5b |
| R3 | A per-launch access token in the URL (IC-71) | Task 4 token and serve tests; Task 7 launcher (`?gptr_token=<32 hex>`); Task 9 (the handle's URL) |
| R4 | Ports from `port_candidates()`; `with_seed_preserved()` around chromote and shiny in the parent (IC-61) | row 2d; row 5d; shiny is never loaded in the parent (`system.file()` checks only, Tasks 2 and 4) |
| R5 | Logs read and redacted by the parent (IC-70) | Task 5 "child output reaches the log in complete lines, redacted, and the raw file goes" |
| R6 | `supervise_default()`, `encoding = "UTF-8"`, `child_env_callr()`, and `stopped` (not `error`) after a requested stop (IC-60) | Task 7 (`artifact_launch_shiny()` code and launcher test); Task 4 "the child env is the artifact profile with ports, library paths and safe R vars"; row 5e |
| R7 | `peter$app(kind =)` accepts any registered `artifact_type` (IC-69) | Task 9 "peter$app() refuses reserved ids, unknown kinds ..." (the message lists the registered kinds) and "kind = \"html\" wraps page.html in a Shiny app version"; Task 7 `artifact_type_get()` |
| R8 | Static checks flag reads of secret files (IC-71) | Task 2 "static checks name each forbidden pattern" (`readLines('.env')` refused as `secret file (level 3): .env`) |

Commands and expected results:

```bash
Rscript --vanilla -e 'devtools::test(filter = "artifact|copy-artifact")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 449 ]`. Without chromote or a Chrome binary: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 435 ]`. With `NOT_CRAN` unset (CRAN): every process-starting test and both copy rows skip.

```bash
Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers|lint-rules)$")'
```

Expected: P01's layering and lint suites (`test-arch-layers.R`, `test-lint-rules.R`; the anchored filter keeps out P10's `test-tool-search.R`, whose name contains `arch`) stay green: `artifact-app.R` and `artifact-registry.R` call only L0 files, the record constructors, the kernel SDK (`run_current()`, `run_eval_env()`, `run_emit()`, `session_data()`, `session_append()`) and their own area; no left-arrow assignment, no `:::`, `set.seed(`, `sample(`, `httpuv::randomPort(`, `tools::pskill(`, `withr::` or non-literal `cli_*()` first argument in `R/`.

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`.

```bash
Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'
```

Expected (milestone M5 run, P25 repeats it): 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the maintainer; the `gptr_artifacts()` example runs offline and writes nothing.

## Self-review

**Spec coverage.** 05 P23 scope, item by item: static checks -> Task 2; immutable `vNNN/` snapshots with the leaf `saveRDS` wrapper and size cap -> Task 3 (`save_rds()`, `gptr.artifact_max_bytes`, `gptr_error_artifact_too_large`); callr child with the `artifact` environment -> Tasks 4 and 7; random port file -> Task 4; parent-PID watchdog -> Task 4; HTTP 200 check -> Task 7 (through P04's reactor); optional chromote session check and 1000x700 screenshot -> Task 6, attached to the `r` result in Task 9; `html` kind -> Tasks 2, 3 and 9; `artifact_start/stop` events -> Tasks 5 and 7; the artifacts `checkpointer` -> Task 8; `builtin:artifacts` -> Task 9; `gptr_artifacts()`, open, relaunch a version, stop -> Tasks 5, 7 and 10; lazy orphan sweep -> Task 5 (first `peter$app()` per process, every listing); `.onUnload` cleanup -> Task 10; `inst/gptr/skills/shiny-bslib/` -> Task 11. Review amendments -> rows R1-R8 above. Acceptance checks 1-5 -> the table above. Contract items owned: export `gptr_artifacts()` (04 §6.4) -> Task 10; member `app` (04 §9.4) -> Task 9; `builtin_artifacts(gptr)` and `artifact_serve(dir, port_file, parent_pid, token)` (04 §7.23) -> Tasks 9 and 4; class `gptr_artifact` with `format`/`print` (04 §5.10) -> Task 1; listing `gptr_artifacts` (04 §5.12) -> Task 10; option `gptr.artifact_max_bytes` (04 §3.1) -> Task 3, documented in `?gptr_artifacts`; conditions `artifact`, `artifact_too_large` (04 §2.2) -> Tasks 2, 3, 7, 9; events `artifact_start`, `artifact_stop` (04 §10.4) -> Tasks 5, 7; custom entry `gptr.artifact` (04 §4.6) -> Task 9; file formats of 04 §11.6 -> Tasks 1, 3, 4, 5; `artifact_type` and `checkpointer` specs (04 §10.2 rows 19, 29) -> Tasks 2, 3, 7, 8, 9; prompt section `artifacts` (04 §9.3) -> Task 9; NS-8 golden transcript (IC-73) -> Task 12.

**Placeholder scan.** The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task" and for steps without code: none. Every function the tasks call is defined in this plan or named in 04 (or, for P10's member closure and r-call marker, P14's renderer hook and P07's runner, defined by those plans and listed under "Interfaces consumed").

**Type and name consistency with 04.** `gptr_artifacts(id = NULL, open = FALSE, stop = FALSE, version = NULL)`; `peter$app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` (the formals of `artifact_member_fun()`, which P10's member closure copies); `builtin_artifacts(gptr)`; `artifact_serve(dir, port_file, parent_pid, token)`; handle fields `id, title, kind, version, url, path, status, checks, screenshot, session` in that order, `checks` = `parse, launch, http, session` plus `messages`, statuses `running`, `stopped`, `failed`; listing columns `id, title, version, status, url, pid, bytes, path`; `artifact.json` keys of 04 §11.6; condition classes `gptr_error_artifact` (fields `id`, `stage`, `log`) and `gptr_error_artifact_too_large` (adds `bytes`, `max`), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_missing_package` (`package`, `feature`); events `artifact_start` (`id`, `url`, `version`) and `artifact_stop` (plus `reason`); section `artifacts` T0/600/150; spec functions with the formals P02's validators require (`build(id, dir, data, ctx)`, `check(dir, ctx)`, `launch(version_dir, ctx)`, `stop(handle)`; `before(call, ctx)`, `after(call, ctx, token)`, `undo/redo(fragment, ctx, force)`, `prune(live_keys, ctx)`, `describe(fragment)`).

**Contract ambiguities and the readings implemented.**

1. *callr `package =`.* 03 §6.15 writes `callr::r_bg(artifact_serve, package = TRUE, ...)`; 04 §7.23 fixes only the signature and says the child "picks a free 127.0.0.1 port from `port_candidates()`". With `package = TRUE` the child would load the installed gptr, which under `devtools::test()` may be absent or the CRAN 0.7.0. Reading: `artifact_serve()` is self-contained (base R and `pkg::` calls) and runs with `package = FALSE` (report 17 §4.2 names this fallback); the parent computes the candidates with `port_candidates()` and passes them, previous port first, in `GPTR_ARTIFACT_PORTS`, and passes `R_LIBS` because the empty `R_PROFILE_USER` of IC-60 stops callr's own profile from setting the child's library paths. Suggested contract edit: name `package = FALSE` and the environment variable in 04 §7.23.
2. *The token in printed URLs.* 02 §8 shows `http://127.0.0.1:4827` without a token; 04 §5.10 and IC-71 put the token in the handle's URL; 03 §10.6 says "the handle's URL also carries the access token". Reading: the `artifact_start` payload and therefore P14's NS-8 line carry the full URL (the user needs it to open the app; P14 prints `event$url`). The token is not registered as a secret (it would be replaced by a marker in the printed line); it is per launch, loopback-only, and persisted only in gitignored files (`run/run.json`, the session JSONL).
3. *Screenshot into the `r` result.* 04 §9.4 says "the `r` result gets its URL, checks and screenshot image" but defines no interface; P10 collects member images through its r-call marker (`gptr_r_call`, fields `images`, `dropped`, capped at `gptr.r_max_images`) and `r_call_attach_image()` in `tool-namespace.R`, an L4 file outside the artifact area that P01's layering test forbids P23 to call. Reading: `artifact_attach_image()` finds the marker by the same frame walk and appends to `images` with the same cap (a data coupling to P10's documented marker). Suggested contract edit: list `r_call_attach_image()` in the kernel SDK (IC-33) or as a service.
4. *`open = TRUE` without a human.* 04 §6.4: "opens it in the viewer or browser (interactive only; relaunches a stopped artifact)". Reading: `open = TRUE` relaunches a stopped artifact in any session and opens the viewer only when `gptr_has_human()` (13 C-42).
5. *`launch` default.* 04 §9.4 fixes `launch = interactive()`; the viewer decision uses `gptr_has_human()` (P01), so `interactive()` under testthat with `gptr.interactive = FALSE` launches but does not open a viewer.
6. *Version retention.* G7 §4.3 says `vNNN/` directories "are pruned with the retention settings"; 04 defines no retention for artifacts and `gptr_artifacts(version =)` must relaunch any stored version. Reading: the checkpointer's `prune` keeps version directories; their disk use is visible in the `bytes` column of `gptr_artifacts()`, and data snapshots are gitignored (04 §11.1).
7. *Validation stages.* 04 names the `stage` field but no values. Reading: `parse`, `static`, `snapshot`, `launch`, `http`; a failing session check is reported in `checks$session = FALSE` and `checks$messages`, not raised (the model reads it with the screenshot); `checks$session = NA` means the check could not run (no chromote or Chrome).
8. *`run.json` fields.* 04 §11.6 lists `{pid, port, url, version, started}`; the sweep also needs the creation times and the owner. Reading: `create_time`, `parent_pid`, `parent_create_time` are added (unknown keys are allowed, 04 §11). Likewise each version record of `artifact.json` carries the `kind` it was built with (an unknown key), so `artifact_relaunch()` and the handle use the version's own type when an id changes kind (for example a plugin's `quarto` type replacing `shiny`).
9. *`gptr.artifact` entry.* Appended only when `peter$app()` from model code succeeds; a failure reaches the transcript as the `r` call's error result (04 §10.2 row 19: "failures become tool results with the stage and a log tail").
10. *The `html` kind's check.* 04 §10.2 gives `check(dir, ctx)` for both types; the `html` type checks that `page.html` exists and is not empty (its generated wrapper is validated at launch).
11. *Test helpers.* 05 allows a plan only its R files, their test files and the files it names; no plan adds a helper file, so the few helpers both test files need (`local_artifact_project()`, `local_events()`, `skip_if_cannot_launch()`, `tiny_app`, `write_working()`) are defined in each file. The two tests that register a fake secret under the test-only name `GPTR_ARTIFACT_TEST_KEY` (Tasks 5 and 7) start with P03's `vault_reset()` and defer it, as P03's own tests and those of P14, P18 and P22 do (it is an internal of an earlier plan, not listed in 04, and tests run inside the namespace).
12. *Skill size.* 03 §10.6 estimates the skill read at "about 400 tokens"; the shipped `SKILL.md` measures 582 o200k tokens (rtiktoken 0.0.7, Task 12), mostly its example app; the golden transcript records the real figure.
13. *R children under R CMD check.* `R CMD check` runs the tests with `R_TESTS=startup.Rs`, a relative path that R's base profile (`R_HOME/library/base/R/Rprofile`) sources in every R process, so any R child started with the parent's environment and another working directory halts at startup (verified: `R_TESTS=startup.Rs Rscript -e 'cat(1)'` exits with status 1, also with `--vanilla`). callr's default `env = rcmd_safe_env()` blanks it, but the artifact launch passes its own `env =`. Reading: `artifact_child_env()` sets callr's three safe values (`R_TESTS = ""`, `R_BROWSER = "false"`, `R_PDFVIEWER = "false"`) and the test's sleeping R children pass `env = c("current", R_TESTS = "")`. Suggested contract edit: name these three values in the `artifact` profile of 04 §7.3 (they are not secrets, so `child_env()` keeps `R_TESTS` today).
14. *The NS-8 line inside an `r` evaluation (cross-plan note, P14 and P09).* `artifact_start` fires while the model's `r` code runs, and P14's hook writes the line with `cat()`, so P09's evaluation sink receives it: without a human (`tee = FALSE`) it reaches only the model's `r` output, and with a human it reaches the console and the `r` output, so the model reads the line twice when its code also prints the handle (about 40 tokens). P23 cannot route around the sink; suggested P14 change: write the artifact line to the console connection saved at `agent_start` (or as a progress message), never through the captured stdout. The NS-8 test therefore checks the dispatched payload and what P14's registered hook prints for it, separately.
15. *Risk of `gptr_artifacts()` from model code (cross-plan note, P11).* P11's R risk table lists `gptr::gptr_artifacts` at level 0 (`read`), although `gptr_artifacts(id, version =)` and `open = TRUE` relaunch model-written code, the risk `peter$app()` declares as level 3. P23 keeps exactly the registrations 04 §7.23 names for `builtin_artifacts()` (no `risk_rule`); suggested P11 change: level 3 (`process`) when the call passes `version` or `open`. Applied by P11's cross-plan consolidation (its log row 5): `flag_special()` rates `gptr_artifacts()` level 3 `process` when it passes `open = TRUE`, `version` or `stop = TRUE` (matched against the 04 §6.2 signature), so plan mode denies `gptr_artifacts('a', open = TRUE)`; the table row stays level 0 `read`.
16. *`expect_no_copy()` under R CMD check (cross-plan note, P01).* P01's helper starts its `Rscript` with `env = c("current", R_LIBS = ...)`, which keeps `R_TESTS=startup.Rs` under `R CMD check`, so its child halts and every copy row (the two of `test-copy-artifact.R` included) fails under `devtools::check()` (`NOT_CRAN=true`); `devtools::test()` is unaffected. Suggested P01 change: add `R_TESTS = ""` to that environment. Resolved without that change (P01 cross-plan consolidation, issue 7): testthat (>= 2.0.0) sets `R_TESTS = ""` in `local_test_directory()` for the whole `test_dir()`/`test_check()` run, so the helper's children inherit the blank value under `R CMD check` too, and P01's Task 1 environment test asserts it. This plan's own `R_TESTS = ""` settings stay: they also cover artifact children launched outside testthat.

**Executed validation (scratch directory `work/plans/P23/`).**

- A scratch package assembled from this plan's R code (the two files exactly as the task blocks give them), the P01, P03 and P04 functions it consumes extracted verbatim from those plans (conditions, checkers, paths, encoding, JSON, listings, ids, ports, `with_seed_preserved()`, `secret_scan()`, `pid_alive()`, `kill_all()`, the job table) and stand-ins for P02 (specs, registry, events), P06 (run and session SDK), P10 (member closure), P17 (`skill_parse()`) and P04's reactor (synchronous curl), installed into a private library, with shiny 1.13.0, bslib 0.10.0, httpuv 1.6.17, later 1.4.8, callr 3.7.6, processx 3.8.6, ps 1.9.3, openssl 2.3.5 and chromote with a local Chrome. `test-artifact-app.R` and `test-artifact-registry.R` (without the two NS-8 tests, which need the gateway) gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 424 ]` (339 + 85), with real Shiny children, real loopback HTTP and real headless Chrome screenshots. Every task's red and green summaries above were measured by rebuilding the package at each task boundary (Task 9's red count of `peter$app()` failures and the NS-8 and copy counts are derived from the expectations, since they need P06-P14).
- An earlier draft passed with two warnings (`'raw = FALSE' but '/dev/urandom' is not a regular file`); `artifact_token()` now opens it with `raw = TRUE`. An earlier draft's Task 7 tests referenced `artifact_launch_shiny` at the top level of the test file, so its red run stopped at one failure; `shiny_type()` is now a function.
- Copy safety: `peter$app("big-view", data = "big")` through a member closure on `runif(5e6)`, from the global environment and from a function frame: 0 `tracemem` copies on the next edit; the control (a list holding `big`) 1 copy.
- The NS-8 fixture's app was launched through the full ladder in the scratch package on the fixture's 4,211 x 7 table: `checks: parse ok | launch ok | http ok | session ok`; the 1000x700 screenshot was inspected (sidebar, two value boxes, volcano plot, table).
- `lintr::lint_dir()` with the repository's `.lintr` linters on both files: no lints except `object_usage_linter` for functions defined by other plans.
- o200k counts (rtiktoken 0.0.7): the `<artifacts>` text 116 (124 with its tags, as 03 §7.3 measures), `SKILL.md` 582, the fixture's outputs 17 + 613 + 29 + 122 = 781 and results 582, 14, 111.
- Review run (2026-10-01, scratch directory `work/plans/review-P23/`): the scratch package above rebuilt from this reviewed plan's blocks (the two R files and both test files; the review harness adds stand-ins for `vault_reset()` and `skill_parse()` and installs `SKILL.md`) gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 428 ]` (342 + 86, the NS-8 tests excluded) with real Shiny children and headless Chrome; per-test counts match every red and green summary above. `artifact_serve()` alone in a callr child with an empty `R_PROFILE_USER` and `R_ENVIRON_USER` answered 200 with the token, 403 without it and with a wrong one, 200 for `shared/shiny.min.js`; a broken UI ended the child before a port file with `Error: object 'no_such_object' not found`; the watchdog stopped a child whose parent was gone; an interrupt stopped the child in 0.03 s. A simulation of P10's member closure (`run(frame)` evaluating `member_fun(...)` in the closure's frame) confirmed that `artifact_member_fun()` finds the caller's frame from the global environment, a function frame, a `local()` block, an `eval()` environment and `peter$app` reached through a list.
- The NS-8 fixture parses with `jsonlite::fromJSON()`, its `read` result equals Task 11's `SKILL.md` byte for byte, its `write` content parses as R and ends with `shinyApp(ui, server)` (1,733 bytes; `details$bytes` is 1,734 with the final newline the write adds), and it is ASCII.
- Every R code block of this plan was extracted and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`; the plan contains no left-arrow assignment and no magrittr pipe in its code.

## Plan review log

Adversarial review of 2026-10-01 against 00-conventions, 04 (with §15), 05 P23, the dependency plans P01-P17 as written, report 17 and its verification log. Every R block was re-extracted and parsed; the plan's R code and both test files (the NS-8 tests excepted, which need the gateway) were rebuilt into a copy of the scratch package of `work/plans/P23/final/` (in `work/plans/review-P23/harness/`) and run with real Shiny children and headless Chrome (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 428 ]`, Self-review "Executed validation").

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 4 `artifact_child_env()`; Task 5 `sleeper_handle()` | Passing `env =` to callr replaces its default `callr::rcmd_safe_env()`, which blanks `R_TESTS`. `R CMD check` runs tests with `R_TESTS=startup.Rs` (relative) and R's base profile sources it in every R child, so under `devtools::check()` (which sets `NOT_CRAN=true`) every artifact child (working directory: its version directory) and every sleeping test child would halt at startup (reproduced: `R_TESTS=startup.Rs Rscript -e 'cat(1)'` exits 1), failing the launch tests and the M5 check. | applied | `artifact_child_env()` sets `R_TESTS = ""`, `R_BROWSER = "false"`, `R_PDFVIEWER = "false"` (callr's safe values; the browser ones also keep model code from opening a viewer, 13 C-42); the sleeping R children pass `env = c("current", R_TESTS = "")`; the child-environment test sets `R_TESTS=startup.Rs` and asserts the two values (+2 expectations); new Global Constraints line; Self-review ambiguity 13. |
| 2 | major | Task 10 NS-8 test, `expect_true(line %in% out)` | The assertion could not pass: `artifact_start` fires inside the model's `r` evaluation, whose stdout P09's `eval_r()` sinks (split to the console only when a human is present; tests set `gptr.interactive = FALSE`), so P14's `cat()` of the line lands in the `r` output, not in `capture.output(peter(...))`. | applied | The test checks the dispatched payload (id, version 1, tokenised URL) and then sends that payload through the registered hooks with `ev_dispatch()` under `capture.output()`, where P14's renderer prints the exact NS-8 line (same expectation count); Task 10 prose, interfaces and acceptance row 4 updated; the double line in the model's context is a cross-plan note (Self-review ambiguity 14). |
| 3 | minor | Tasks 5 and 7, tests that register a fake secret | The fake secret stayed in the process vault for the rest of the test run, unlike the tests of P03, P14, P18 and P22. | applied | Both tests start with `vault_reset()` and defer it; P03 `vault_reset()` listed under consumed interfaces; ambiguity 11 rewritten. |
| 4 | minor | Task 6 `artifact_session_browse()` | The state poll slept with `Sys.sleep(0.1)` for up to 20 s, blocking the reactor, although 04 §8.2 makes `reactor_pump()` "the only blocking wait" and the plan's own port and HTTP waits use it. | applied | The pause is `reactor_pump(until = function() FALSE, slice_ms = 50L, timeout = 0.1)`; Task 6 interfaces list it; the "did not connect" message uses the `timeout` argument instead of a hard-coded 20 s. |
| 5 | minor | Task 7 `artifact_wait_http()`, `artifact_launch_shiny()` | The failure reasons hard-coded "30 s" whatever the `timeout`. | applied | Built from `timeout` and `artifact_launch_timeout`. |
| 6 | minor | Tasks 5, 7, 9 (`artifact_handle()`, `artifact_relaunch()`, `artifact_app()`) | Relaunch and the handle used the artifact-level `kind`, so after an id changed kind (IC-69: any registered `artifact_type`, e.g. a plugin's `quarto`) older versions were relaunched with the wrong type's `launch`. | applied | Each version record stores the `kind` it was built with (an unknown key, allowed by 04 §11); `artifact_relaunch()` and `artifact_handle()` use it before the artifact-level `kind`; the html test asserts it (+1); Global Constraints and ambiguity 8 note it. |
| 7 | minor | Task 8 `artifact_ckpt_move()` | Undo and redo relaunched without the checkpointer's `ctx`, so an `artifact_type` registered for the rewound session only could not be resolved. | applied | `artifact_ckpt_move(fragment, side, running, ctx = NULL)` passes `ctx` to `artifact_relaunch()`; `undo`/`redo` forward their `ctx`. |
| 8 | minor | Task 10 `artifact_list()` | `artifact.json` is committed, so one unreadable file (merge conflict, hand edit) made `artifact_handle()` abort and `gptr_artifacts()` fail for every artifact. | applied | Unreadable files are skipped and named in the listing footer (`new_listing(footer =)`); the listing test plants a conflicted file (+1). |
| 9 | minor | Expected summaries of Tasks 4, 6-11 and Plan acceptance | The counts had to follow the added expectations. | applied | Re-measured per test in the review run: `test-artifact-app.R` 342 (Task 4 163, Task 6 184/170, Task 7 237/223, Task 8 252, Task 9 335 with the copy rows, Task 11 342), `test-artifact-registry.R` 105, totals 449 (435 without Chrome). |
| 10 | minor | Task 7 `artifact_relaunch()` in `artifact-app.R` | 03 §3.2 lists "relaunch" under `artifact-registry.R`. | rejected | Both files are P23's own area; the user-facing relaunch `gptr_artifacts(version =)` lives in `artifact-registry.R`, while the helper sits next to `artifact_start()` that it wraps and is needed by Tasks 8-9 before Task 10; moving it adds churn without changing behaviour. |
| 11 | minor | Task 1 `artifact_reserved` | Duplicates P01's `reserved_name()`. | rejected | P01's helper is not in 04 (not a consumable contract), and ids cannot contain `.`, so the exact list is equivalent. |
| 12 | minor | Task 2 `artifact_ends_with_app()` | `app = shinyApp(ui, server); app` is valid Shiny but is refused. | rejected | 03 §6.15 specifies "ends with `shinyApp()`" (report 17's ladder too); the message tells the model the one-line fix. |
| 13 | minor | Task 9, user calls at an interactive console | The NS-8 line appears twice (P14's hook on `artifact_start` and the autoprinted handle). | rejected | Both are contract behaviour (04 §5.10 print, 04 §7.14 renderer); only at an interactive console. |
| 14 | major (cross-plan) | P01 `expect_no_copy()` used by `test-copy-artifact.R` | The helper's `Rscript` child inherits `R_TESTS=startup.Rs` under `R CMD check` and halts, so every copy row fails under `devtools::check()`. | rejected (not P23's file) | Recorded with the suggested P01 change as Self-review ambiguity 16. |
| 15 | minor (cross-plan) | P11 risk table, `gptr_artifacts` at level 0 | `gptr_artifacts(id, version =)` and `open = TRUE` from model code relaunch model-written code (level 3 for `peter$app()`). | rejected (not P23's file) | 04 §7.23 fixes what `builtin_artifacts()` registers; recorded as Self-review ambiguity 15 with the suggested P11 change. |
| 16 | minor | Task 12 baseline figures | Checked rather than assumed. | no change | rtiktoken o200k counts re-measured in the review: `SKILL.md` 582, the section 116 (124 with tags), results 582 / 14 / 111, answer 122; the fixture is valid JSON, ASCII, and its `read` result equals `SKILL.md`. |

## Cross-plan consolidation log

Cross-plan consistency pass of 2026-10-01 against 04 (with §15), 03 §3.2 and §9, 05 (P23 dependencies P10, P11, P14, P16 and their closure P01-P11, P14-P16), P01, P10 and P17. After the changes every R block of this plan was re-extracted and parsed with `Rscript --vanilla` (no left-arrow assignment, no `%>%` in code), and Task 11's new frontmatter read was run with yaml 2.3.12 on this plan's `SKILL.md` (name and catalog line as expected).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | minor | Task 11 skill test and its Consumes line; Interfaces consumed (P17) | applied | P17 is outside P23's 05 dependency closure (P10, P11, P14, P16 reach P01-P11 and P14-P16, not P17), so the test no longer calls `skill_parse()`: it reads the frontmatter between the first two `---` lines with `yaml::yaml.load()` (yaml is an Import, 03 §9) and keeps the same expectations, so every count is unchanged (`artifact-app` 342). Task 11 Consumes and the Interfaces-consumed list now name yaml and say no P17 function is called; Task 11 Step 4 notes that P17's `skill-discover` suite is a regression cross-check only. The Self-review's "Executed validation" entries keep their historical mention of a `skill_parse()` stand-in, which the rebuilt test no longer needs. |
| 2 | shared-names | minor | Task 4 `artifact_child_env()` / `artifact_serve()`; Global Constraints | applied | No code change (04 §7.23's `artifact_serve(dir, port_file, parent_pid, token)` stays as written). Global Constraints now record `GPTR_ARTIFACT_PORTS` as a child-only variable beside 04 §3.2's `GPTR_MCP_TOKEN`, `GPTR_SUBAGENT_DEPTH` and `GPTR_WORKER`: set by `artifact_child_env()` only in the artifact child, read only by `artifact_serve()`, never set or read in the user's session. 04 §3.2 does not list it, and 04 §7.23 leaves open how the parent's `port_candidates()` reach the self-contained child, so this records a gap rather than deviating from 04. Task 4's existing child-environment test already asserts its value (`"50001,50002"`). |
| 3 | trace | minor | Plan acceptance, layering and lint command | applied | `arch\|lint` also matched P10's `test-tool-search.R` (`search` contains `arch`). The command is now `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers\|lint-rules)$")'`, the anchored form P06 and P13 use, and the expected text names the two P01 files. |
| F1 | finalize | minor | Task 9 test "a second peter$app() after an edit creates v002 without touching v001" (`object_name_linter` on `assign("a/b", 1:3)`, the only P23 row of the consolidation lint run) | applied | The object name `a/b` is fixed by 05 P23 acceptance 5 ("a data object named `a/b` snapshots as `data/001.rds`") and is what the test checks (`data/002.rds` in the version directory, the `name` field of the version's `data` records), so it cannot be renamed; the line now carries `# nolint: object_name_linter. 05 P23 acceptance 5 names the object a/b.` (P08's precedent for a binding name fixed outside the plan). No other code changed and every test count is unchanged. With P01's linters (`object_usage_linter = NULL`, `indentation_linter = NULL`) the 22 R blocks of the plan now give 0 lints; every R block was re-extracted and parses with `Rscript --vanilla` (no left-arrow assignment, no `%>%`, ASCII, lines <= 100 characters). |
