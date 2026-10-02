
---

## 15. Review amendments (IC-32..IC-73, 2026-09-30)

An adversarial review of `03`, `04`, `05`, the register and the conventions raised 144 issues
(`dev/spec/06-review-resolution.md` lists each with its verdict). The decisions below are binding and **win over
every earlier section of this document** where they differ; the sections they touch were edited in place as well
(and `03`, `05`, the register and the conventions were edited to agree). Each decision names the review issues it
resolves by lens and number (`req-n`, `cran-n`, `cons-n`, `fid-n`, `plug-n`, `safe-n`, numbered in the order of
06's table). All code uses `=` and `|>` (S-9).

### 15.1 Package build and layering

**IC-32 Load order.** `R/aaa-state.R` (P01) holds `the`, `on_load()`, `on_unload()`, `ext_service_set()`,
`ext_service_get()`, `ext_service_has()`, the internal `%||%` (R >= 4.2 has no base `%||%`; fid-19) and
`redactor_set()` (IC-34). It is the one exception to the `<area>-<topic>.R` rule and collates first, so every
file may call `on_load(...)` at top level: R evaluates package code at install time in collation order, and
`utils-options.R` collates after every other area but `zzz.R` (a toy package failed to install with "could not
find function on_load"; cons-1). `on_load()` stores its expression unevaluated, so the stored
`ext_declare_builtin()` and `ext_service_set()` calls need not exist yet. P01 acceptance adds "`R CMD INSTALL`
succeeds with a later-collating file calling `on_load()` at top level". DESCRIPTION has no `Collate` field.

**IC-33 Layering test and the kernel SDK.** The area matrix of `03` §2.2 is replaced, for calls *into* kernel
functions, by a function-level allowlist (req-13, cons-2, req-32):

- *Kernel SDK* (callable from any layer L3-L6 and from L4 built-ins): `session_data()` (read), `session_live()`,
  `session_home()`, `session_append()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`,
  `session_value_set()`, `session_value_get()`, `session_replay_apply()`, `session_replay_new()`,
  `session_replay_bind()`, `replay_lookup()`, `session_run()`, `run_start()`, `run_wait()`, `run_abort()`,
  `run_current()`, `run_eval_env()`, `run_emit()`, `dispatch_nested()`, `perm_check()`,
  `tool_result_message()`, `store_read()`, `store_rebuild()`, `call_value()`, `route_pass()`, `gateway_run()`,
  `gateway_defer()`, `replay_mode()`, `replay_guard()`, `egress_check()`, `home_address()`, `setting_get()`,
  `settings_effective()`, `settings_write()`, `resolve_identifier()`, `interpolate_prompt()`,
  `describe_binding()`, `eval_r()`, `format_eval_result()`, `rule_parse()`, `last_set()`, `ckpt_store_put()`.
- L1 adapters never call L2+: `provider_stream()` injects `opts$gate(call)` (the run's `perm_check()`),
  `opts$mcp_dispatch(message)` (the `mcp.dispatch_local` service bound to the session) and
  `opts$tool_result(result, call)`; `cli-claude.R` uses only these.
- L0 and L3 files reach trust through the `trust.get` service (fallback `FALSE`, i.e. untrusted) instead of
  calling `trust_get()` (P08, L6).
- `helper-arch.R` builds its function-to-file map by **parsing the files under `R/`** (located with
  `testthat::test_path("..", "..", "R")`, else `file.path(Sys.getenv("R_PACKAGE_DIR"), "..", "00_pkg_src", "gptr", "R")`
  under check); the test is skipped with a message when the sources cannot be found, never passes vacuously.
  Literal `ext_service_get("<name>")` calls are mapped to the providing plan so service coupling is visible;
  a call to an undeclared service name fails the test.
- `arch_allowed()` = the `03` §2.2 layer matrix plus `arch_kernel_sdk()` (the list above); `arch_services()` =
  the §7.0 service names.

**IC-34 Services: completeness, ownership, the `service` kind.** (cons-3, cons-4, plug-3)

- `redactor_set(fun)` (P01, `aaa-state.R`) generalises `condition_redactor_set()`: identity until P03 installs
  `redact()`; `gptr_abort()`, `spill_write()`, `ev_dispatch()`, `registry_diagnostic()` and `ctx$redact()` call
  `redact_hook(x, profile)`, so P01/P02 never call P03.
- New services (§7.0): `trust.get` (P08; fallback `FALSE`), `identifier.resolve` (P08; fallback: symbols and
  strings are taken literally), `secret.lookup` (P03; fallback `NULL`), `ctx.kernel` (P06: a named list of the
  implementations behind the `ctx` members of §10.6 that are marked P06), `ctx.input` (P07), `ns.names` (P10;
  fallback `character(0)`), `eval.r` (P09: `eval_r()` through the `evaluator` kind), `describe` (P09),
  `router.call` (P08, IC-69), `session.add_tools` (P07, IC-69), `search.sources` (P10). `ctx_new()` (P02) is a
  thin shell whose members call `ext_service_get()` lazily at call time.
- `gptr_agent()` stores the raw captured expressions (symbol names or literals) and resolution happens at the
  gateway (no P02 -> P08 call). P06 obtains the preset's tool list only through `prompt.freeze` (and its
  documented fallback: the four core tools); it never calls `preset_tools()`.
- Every service is **owned by a built-in**: `ext_service_set(name, fun, provided_by, builtin)`; when that built-in
  is filtered out, `ext_service_get()` signals `gptr_error_not_available` (so `-builtin:documents` removes
  `doc.site`, `doc.edit` and `doc.s1_block` too). A new registry kind **`service`** [experimental] (resolve
  `first`, name = service name, field `fun`) lets a plugin provide or replace a service at a lower rank; once P02
  is loaded `ext_service_get()` consults the registry first, then the bootstrap table.

**IC-35 Constructor signatures.** (req-20, cons-5) §6.7 and §6.8 now read:
`gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`;
`gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"),
budget = 300L, order = 650L)`;
`gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL,
capabilities = list())` with the validator rule: `http_*` and `process_jsonl` need `build` and `parse`,
`inprocess` needs `stream`, classifier adapters need `classify`;
`gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat",
"classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE,
offline = FALSE, rate = NULL)`;
`gptr_router(name, route, description = NULL, timeout = 2)`;
`gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`.
P02 acceptance adds: every §6.8 example runs.

**IC-36 Ownership moves.** (cons-6, cons-7, cons-8, req-29, cons-15, req-31, cons-16, cons-23)

| Item | Before | After |
|---|---|---|
| `gptr_prob()` | P08 `gptr-sdk.R` (its example needed P13 at M1) | P13 `s1-types.R` |
| `$`, `[[`, `.DollarNames`, `print`, `$<-` of `gptr_gateway` | split P08/P10 | all P08; `$`/`[[` call the `ns.resolve` service, `.DollarNames` the `ns.names` service (fallbacks: `gptr_error_not_available` / `character(0)`); P10 only registers the services |
| member `out` | P10 and P22 | P10 only (`builtin:tools`); P22 keeps `sh`, `script`, `bg`, `jobs` |
| `gptr_map()` | export (P19) | internal: the function behind `parallel =` (S-1: one gateway); `gptr_parallel()` stays |
| `gptr_jobs()` | P21 `agent-background.R` | P04 `proc-supervise.R` (it reads the job table); P21 adds session rows |
| `inst/gptr/fixtures/fake_cli.R` and the CLI leg of the INFRA-16 test | used by P19 before P20 exists | P20 (acceptance 2 gains the interleave leg); P19 tests inline and worker only |
| dependency edges | P17 depends on P08 | P17 depends on P08 and P10 (the `plugins` section, `ns_catalog()`, `read` activation) |

New export (IC-70): `gptr_scrub()` (P03). The export count stays **63** (-1 `gptr_map`, +1 `gptr_scrub`).

### 15.2 Gateway, capture and routing

**IC-37 Tool identity and exposure.** (cons-9, plug-11) One tool spec per capability; `exposure` is a default
visibility, not an identity:

- A spec may carry both `execute` (the direct-tool form) and `fun` (the member form); the built-ins `read`,
  `edit`, `write`, `grep`, `find`, `ls` carry both.
- The tool array is built by the preset (IC-69 `preset` kind) from any spec with an `execute`; plugin specs with
  `exposure = "direct"` are always added.
- `$.gptr_gateway` resolves any spec **without** a namespace that has a `fun`, whatever its exposure, except
  `hidden`; `deferred` and `hidden` only exclude a spec from catalogs.
- Reserved member and namespace names: every built-in member name, `mcp`, and the names of the §9.4 table. A
  plugin spec with `exposure = "r"` MUST set `namespace`; a namespace equal to a reserved or existing member name
  is `gptr_error_invalid_spec` at registration.

**IC-38 Context placement.** (req-9, cons-10, plug-14) `context_block` `placement` accepts `"both"`:
`context_first_message()` renders `first` and `both` specs, `context_turn_blocks()` renders `turn` and `both`
specs, each in `order`. `builtin:workspace` registers `attached` (order 600) and `skill_content` preloads with
`placement = "both"`, so `gptr("x", mtcars)` sends `<attached name="mtcars">` after `<workspace>` in its first
request (P07/P09 acceptance). Turn blocks are **deduplicated**: a block whose text hash equals the last emitted
text of the same name in this session is skipped, and `ctx$input$last_hash` lets `provide()` return `NULL`
itself. The spec default placement stays `turn`; the extending-gptr vignette recommends `first` for constant
text.

**IC-39 Route order and nesting.** (cons-11, req-19) Route orders are: `classifier` 10, `team` 15, `fanout` 16,
`nested` 20, `console` 30, `document` 50, `continue` 60, `new` 70. `team` and `fanout` calls made while a run is
active create children of the running session (depth + 1, mode only tightened, usage rolled up, budget charged
to the root, IC-66). `gptr.subagents.max_tasks` (8) applies only to team and fan-out calls made at depth >= 1
(model code), with the classed error `gptr_error_invalid_argument` naming the limit; user-level fan-outs queue
every element and run `parallel`/`max_active` at a time (P19 acceptance: 20 elements, `parallel = 4`).

**IC-40 Where a continuation evaluates.** (req-10) Precedence for the run's evaluation environment: an explicit
`envir =` (detected with `missing(envir)` in the gateway frame) > the session's kept home (globalenv, an explicit
earlier `envir`, or a fork overlay) > the caller frame (`parent.frame()`). Context symbols of the call are read
from the call's frame; when a symbol label is not visible from the run's evaluation environment with the same
object address, the gateway fails fast with `gptr_error_invalid_argument` naming the object and suggesting
`envir =` or a named value. P08 test: `f = function(s, d) s |> gptr("filter d", d)`.

**IC-41 Capture without forcing symbol dots.** (req-4) For a dot whose expression in `sys.call()` is a plain
symbol (top level, data-first pipe, continuation with context), the gateway computes the facts with a leaf
`get0(name, envir = parent.frame(), inherits = TRUE)` and never forces the dot's promise; only calls and
forwarded `...`/`..n` dots are forced through `...elt(i)`. Documented: an object passed through a call or a
wrapper's formal is referenced by that frame for the run, so an in-place edit of it *during* the run copies once.
`expect_no_copy()` gains `in_run_edit = TRUE`: the fake provider issues an `r` call running `edit` inside the run;
rows for `gptr("x", big)`, `big |> gptr("x")` and `s |> gptr("x", big)` expect 0 copies.

**IC-42 Identifier normalisation.** (req-12) `identifier_known()`/`resolve_identifier()` compare skill, plugin,
extension and agent names after `name_norm(x) = tolower(gsub("[._]", "-", x))`, so `skills = single_cell`
resolves to `single-cell` and `skills = high_performance_r` to the built-in; an ambiguous match is
`gptr_error_invalid_identifier` listing the candidates. Package-facing documentation and `03` §11.3 use strings
(`model = "jev"`) and `gptr::gptr_agent()`; bare identifiers are for scripts and the console, and
`gptr_check(<package>)` flags bare gptr identifiers in package code (plug-13).

**IC-43 Human predicates.** (req-11, cran-6) `gptr_can_prompt()` (P01): the `gptr.interactive` option if set,
else `interactive() || isTRUE(getOption("jupyter.in_kernel"))`, excluding knitr, testthat and
`check_running()`. It decides every question: `perm_check()` asks, the `ask` tool, `gptr_confirm()`,
`gptr_init()`, the egress acknowledgement, the `console` route and the mode-block variant. `gptr_has_human()`
keeps deciding streaming and verbosity. `builtin_ui`'s resolution uses `gptr_can_prompt()`.

**IC-44 Namespaced call options.** (plug-8) `.opts` accepts entries named by a registered plugin namespace
(the prefix of its `setting` specs): `gptr("Review analysis.R", .opts = list(panel = list(size = 3)))` is
validated by the `panel.*` setting specs and reaches routes and handlers as `call$args$opts$panel` and
`ctx$input$opts$panel`; unknown names still signal `gptr_error_invalid_argument`. Named arguments to `gptr()`
are always context objects (documented). `.opts$images` (req-36): a list of PNG/JPEG paths, `ggplot` objects or
`recordedplot` objects sent as image blocks in the user message (vision-capable models only; rendered with
`plot_png()`, 532 tokens each at 768x512).

### 15.3 Documents and replay

**IC-45 The document route.** (req-7, safe-15, cran-3)

- `document` (order 50) matches a **top-level** call located in a document (any `doc_locate()` site with a
  path) that **contains a block owned by this call**. Replay needs no write consent. Without a block it sets
  `call$doc` when write consent exists and passes.
- **Write consent** is checked only in `doc_upsert()`: `gptr_doc(path)` in this process (binds that document for
  every `gptr()` call of the process, console or script), `options(gptr.record = "auto")`, user-scope setting
  `record = "auto"`, or an interactive yes (remembered per document in the user-level project file, IC-52).
  `record` is a tighten-type setting, so a project can only turn it off; the earlier "trusted `record = auto`"
  wording is deleted.
- **Freshness** also covers interpolated values: header key `args=<8 hex>` = the first 8 hex of sha256 of the
  sorted `name=value` pairs interpolated into the prompt (absent without interpolation). A block is fresh only
  when `prompt=` and `args=` both match; the S2 cache key includes the args hash. A stale block under `replay`
  errors `gptr_error_stale_block`.
- **Forced replay only in examples**: `replay_mode()` forces `"replay"` when `check_running()` and
  `Sys.getenv("TESTTHAT") != "true"`; an explicit `replay =` argument wins under tests. "In a vignette build" is
  deleted (vignettes are precomputed and run no gptr code). The mock-server and fake-CLI test helpers register
  their providers with `offline = TRUE` (no remote model is called), so `GPTR_REPLAY=replay` in `setup.R` does
  not block them.

**IC-46 Replaying fresh blocks.** (req-5, cons-22, req-2)

- **Piped session**: when `call$session` is non-NULL, `session_replay_apply(s, block, header)` (P06) advances
  that **same object**: appends `gptr.replay`, adds the block id to `.d$seen` (a block already in `seen` adds no
  turn), increments `turns`, sets the value by name from `value=` under the value policy, sets `last_text` from
  the S2 cache when present, and returns `s`. So `identical(chain_result, first_result)` holds for a replayed
  pipe chain.
- **No piped session**: `session_replay_new(block, header, envir)` returns a live session holding the header's
  `session=` id if one exists in this process; otherwise a `replayed` session that adopts the recorded id when
  no live session holds it. Its transcript comes from the session JSONL truncated at the recorded turn when the
  file exists, else it is **reconstructed** from the document (the template as the user message, the recorded
  code as the assistant's `r` call, the `#>` lines as its result, the S2 answer text if cached) with
  `.d$history = "reconstructed"`. A later live continuation of a reconstructed session prints a one-time notice
  that the history is reconstructed.
- **Fork blocks** (`fork=` header): the replay result is bound to the block id with `session_replay_bind(block,
  s)` in a process table `the$replay_blocks` (gptr-created sessions only, never user frames; replaced on
  re-source). Recorded fork turns are wrapped `local({ ... }, envir = gptr_resume(block = "<block id>")$envir)`;
  `gptr_resume(block =)` returns the bound session or signals `gptr_error_replay_unbound` ("source the
  statement that owns block <id> first"); it never falls back to `parent.frame()`. A fork rebuilt from JSONL
  always gets a fresh `new.env(parent = <parent's kept home>)`. P15 acceptance: re-source NS-3 twice; the
  main-line `qc_flags` and `qc$value` are unchanged and the fork's objects live only in its overlay.
- `gptr_resume()` gains `block = NULL, child = NULL` (§6.5).

**IC-47 Recording teams, fan-outs and block-nested calls.** (req-6)

- A top-level team or fan-out statement owns **one block**: header `kind=team|fanout`,
  `children="<name>:<session id>,..."`, `session=<team id>`, `turn`; body per child in name order:
  `## Agent <name> (<model>): <first line of its report>`; for a child with exports, its recorded code wrapped
  `local({ ... }, envir = gptr_resume(block = "<id>", child = "<name>")$envir)` followed by one
  `<export> = gptr_resume(block = "<id>", child = "<name>")$envir$<export>` line per exported name. Child texts
  are cached in S2 under `(doc, block, "<name>")`. Replay returns a team or fan-out session of replayed children
  with zero requests; the "team and fan-out calls own no document block" note is deleted.
- **Block-nested calls**: a `gptr()` statement located directly inside an agent block's body (`site$in_block`)
  is replayed from S2 under `(doc, block, "n<ordinal>")` in `auto` and `replay` (zero requests; a miss under
  `replay` errors `not_recorded`) and runs live only in `live`. When a block is written, the final texts of the
  child sessions its `r` calls created are cached in creation order. Calls deeper inside block code (loops,
  functions) run live, like calls in user loops. System 1 calls inside blocks use the S1 cache; a miss under
  `replay` errors `not_recorded`.
- P15/P19 acceptance: NS-6 and a block containing a sub-agent call replay under `GPTR_REPLAY=replay` with zero
  requests.

**IC-48 What recorded code contains.** (req-1, req-26, req-28)

- `gptr_return(x)` outside a run returns `invisible(x)` with a once-per-session `notice`, suppressed while a
  document is being replayed; `gptr_error_not_in_run` is removed.
- `doc_block_lines()` drops, at top-level-expression granularity (`getParseData()` of each recorded code chunk),
  calls to `gptr_return()`/`gptr::gptr_return()` and to members whose spec has `record = FALSE`; a chunk that
  becomes empty is omitted; the value stays in `value=`. `record = FALSE` is set for `out`, `plot`, `help`,
  `search`, `describe`; the `<r_session>` text tells the model to use them only with `record = false`.
- Plan-mode runs never record code (`record` forced `FALSE`); their block holds one `## Plan: <plans path>`
  comment.
- S-9 best effort: `doc_block_lines()` rewrites `<-` to `=` for `LEFT_ASSIGN` tokens whose assignment is a
  top-level expression of the chunk or a direct child of a `{` expression list, never inside call arguments;
  `->`, `<<-` and `%>%` are left alone.
- P15 acceptance: a block whose code called `gptr_return(fit)` and `gptr$out("o1")` re-sources cleanly under
  `source()` and Rscript, and `$value` resolves `fit`.

**IC-49 Console transcripts and steering in documents.** (req-8) The first REPL prompt of a session is recorded
as `s_<6 hex of the session id> = gptr("...")`, later REPL turns as `s_<hex> |> gptr("...")`. Steers and
follow-ups delivered during a block's turn (pause menu, `gptr_steer()`, pipe into a running session) are recorded
inside that block as `## Steer: <text>` / `## Follow-up: <text>` lines, excluded from the prompt hash and `sha`.
P15 acceptance: a two-turn console session plus one menu steer produces a transcript that re-sources as one
session.

**IC-50 Jupyter documents.** (req-11) With `front_end() == "jupyter"` gptr never writes the open notebook: the
block is shown as the cell's output (a fenced R code block) and recorded as a pending `gptr.doc_block` entry
(`backend = "pending"`) plus a pending sidecar; `gptr_doc(path, format = NULL, sync = FALSE)` gains `sync`:
`TRUE` applies the pending blocks of that notebook through gptr's ipynb serializer when the notebook is closed or
headless. P15 fixture test with `jupyter.in_kernel` mocked.

**IC-51 Durable, safe document writes.** (safe-16, cran-17)

- The deferred-write sidecar holds `list(doc, base_md5, upserts = list(list(block_id, lines, site)), session,
  pid, time)`, is flushed after each settled top-level call (so SIGTERM loses at most one call) and is applied at
  exit by the finalizer; the next `gptr()`, `gptr_blocks()` or `gptr_doc()` touching that document in any process
  re-applies unapplied upserts of a dead pid through the normal md5 and re-locate path and reports conflicts
  instead of overwriting. Sidecars are never pruned automatically; `gptr_cache("info")` lists them. Under a
  document lock held by another live pid (array jobs) nothing is recorded and a notice is printed.
- `write_atomic()` retries `file.rename()` 3 times with 100 ms sleeps, then writes in place with `writeBin()`
  after an md5 re-check. `path_key(p)` (P01) lower-cases normalised paths on Windows and macOS; document bindings,
  trust keys, locks and site matching use it.

### 15.4 Safety

**IC-52 Settings the project cannot plant.** (safe-2, safe-3, safe-23, safe-24)

- "Always in this project" rules, the transcript target and per-document record consent live in
  `R_user_dir("gptr", "config")/projects/<first 16 hex of sha256(path_key(root))>.json`, never in the project
  tree. `gptr_permissions(scope = "project")` writes there. An existing `.gptr/settings.local.json` contributes
  only `permissions.deny`/`ask` additions and only in a trusted project; allow, record and transcript keys in it
  are ignored with a notice. Transcript and document targets must lie inside the project root, have extension
  `.R`, `.Rmd`, `.qmd` or `.ipynb`, and not be a `control` or protected path.
- Instruction authority follows trust. In an untrusted project, project instructions render as
  `<project_instructions trusted="false">` and the frozen `<context>` section says such blocks are information,
  not commands; the first interactive session in an untrusted project that has `AGENTS.md`, `CLAUDE.md` or
  `.gptr` skills/agents asks the trust question once. Non-interactive + untrusted + mode `auto` or `edits`:
  project instructions, project skills and project agents are omitted with a notice. Only skills from user
  directories, installed packages and trusted projects enter the T1 catalog. `project_update` operator messages
  become user-role data; `context_block` `authority = "operator"` is allowed only for records of rank >= 3.
- `trust.json` records a `fingerprint` (sha256 over the sorted paths and contents of the trust-gated files:
  `.gptr/settings.json`, `mcp.json`, `extensions/`, `plugins/`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `agents/`, an
  auto-discovered `.env`). On a mismatch the changed resources are treated as untrusted: interactively the
  changed files are listed and the question asked again; non-interactively they are ignored with a notice.
  gptr's own writes re-fingerprint.
- `gptr_resume(path)` of a file whose header `cwd` differs from the project root, or that git tracks, rebuilds
  with a freshly frozen prompt from the current settings and marks the prior user turns `source = "imported"`.
  File restores (rewind) are confined to the project root and `tempdir()`; a restore outside needs an
  `ask_human` per path.

**IC-53 The permission kernel cannot be reconfigured by model code.** (safe-1, req-16, safe-6, safe-18)

1. `perm_check()` fails closed: with no active `mode` policy the decision is `ask` (and `blocked` without a
   human). `builtin:permissions`, `builtin:plan` and the `critical_guard` and `secret_guard` policies cannot be
   disabled by filters from any source; filters that would remove `policy` or `hook` records are refused inside a
   run. The only escape is `options(gptr.unsafe_no_permissions = TRUE)` set outside a run (documented for
   sandboxed CI).
2. `run_start()` snapshots `gptr.ui`, `gptr.interactive`, `gptr.critical_guard`, `gptr.secret_guard`,
   `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode` and `gptr.unsafe_no_permissions`; the run's gate
   reads only the snapshot.
3. `risk-functions.csv` gains category `control`, level 4, `ask_human`: `gptr_config`, `gptr_permissions`,
   `gptr_trust`, `gptr_init`, `gptr_env`, `gptr_register`, `gptr_reload`, `gptr_on`, `gptr_mcp_add`,
   `gptr_mcp_remove`, `gptr_mcp_serve`, `gptr_login`, `gptr_logout`, `gptr_doc`, `gptr_cache` (prune, clear),
   `gptr_scrub` (`dry_run = FALSE`), and `gptr_resume`, `gptr_fork`, `gptr_steer`, `gptr_cancel`, `gptr_rewind`
   on a session other than the running one; `options()` with `gptr.*` names, `Sys.setenv()`/`Sys.unsetenv()` of
   `GPTR_*` or provider key names, `setHook()`, `assignInNamespace()`. These exports also check `run_current()`:
   called from model code during a run they signal `gptr_error_permission` unless the dispatcher approved
   exactly that call through an `ask_human` (a one-shot token on the run).
4. Every gateway call made while `run_current()` is non-NULL (any route) inherits the running mode (only
   tightened) and filters; model code continuing an idle user session runs it in the stricter of the two modes.
5. The parent re-classifies the raw input carried in every forwarded worker `permission_request`; the worker
   backend is documented as not an isolation boundary.
6. Two ask tiers: `ask` (levels 1-3 without a guard) may be answered by `permission_request` hooks;
   `ask_human` (level 4, the secret guard, the `control` category and path class, first use of a CLI route, the
   egress acknowledgement) only by a UI backend whose `has_ui()` is `TRUE` in the run's snapshot. A hook
   returning allow for an `ask_human` is ignored with a diagnostic.
7. A `modify` decision is re-classified and re-checked once; a second `modify` denies. Only `r(secret:NAME)`
   rules pre-approve the secret guard.
8. Approval displays (console, rstudio dialogs, worker-forwarded requests) escape C0/C1 controls except TAB and
   bidi and zero-width characters as `<U+XXXX>`; the one-line prompt lists every flagged call and `+N more
   lines`.

P24's `test-injection-e2e.R` adds an injected model trying each path above; every attempt ends in a human ask
(interactive) or `blocked`.

**IC-54 Classifier defaults and protected paths.** (safe-4, safe-5)

- Level 0 means "known read-only". A call to a function outside base, stats, utils, methods, graphics, grDevices
  and tools that is not in the table is level 1 (asks in `manual` and `edits`). A shipped risky-package list
  (targets, usethis, devtools, renv, pak, remotes, fs, gert, git2r, gh, googledrive, pins, `aws.*`, `paws.*`, DBI
  write verbs `dbExecute`, `dbWriteTable`, `dbRemoveTable`, `dbSendStatement`, and request performers of httr,
  httr2 and curl) is at least level 2 (delete verbs 3). User and plugin `risk_rule` rows (IC-69) may lower
  levels explicitly.
- Plan mode evaluates an `r` call only when every call in it resolves to an allowlisted read-only function
  (level-0 `read` rows, base/stats/utils getters and summaries, describers, gptr read members); otherwise the
  call is denied with "not known to be read-only in plan mode".
- `path_class()` gains `control` (level 4, `ask_human`, never pre-approved by rules): `.gptr/settings*.json`,
  `.gptr/mcp.json`, `.gptr/extensions/`, `.gptr/plugins/`, `.gptr/SYSTEM.md`, `.gptr/APPEND_SYSTEM.md`,
  `.gptr/agents/`, all of `R_user_dir("gptr", "config")`, `.git/hooks/`, `.git/config`, `.Rprofile` anywhere,
  `Rprofile.site`, `Renviron.site`, the `R_PROFILE_USER`/`R_ENVIRON_USER` targets and `~/.R/Makevars`; and
  `instructions` (level 3): `AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`, `.gptr/skills/`, `.gptr/prompts/`.
  Both apply to the direct `write`/`edit` tools, `gptr$write`/`gptr$edit` and static path arguments in R code.
  Control files modified during the process are not loaded again without confirmation (IC-52 fingerprint).
- P11 acceptance adds 18 §2.5's blind-spot cases with the new levels and the control-category calls in `manual`
  and `plan`.

**IC-55 Steering relays by source.** (safe-7) Queue items carry `source` in `pipe`, `pause_menu`, `repl`,
`api_user` (`gptr_steer()` called outside any run), `extension` (`ctx$send()` from a plugin or hook) and `agent`
(a sibling or child). Only the user sources get the operator relay `The user sent this message while you were
working: <text>`. `extension` items are user-role data `Extension <name> sent this note (not from the user):
<text>`; `agent` items are delivered as `<agent_report from="<name>">...</agent_report>` user-role data, never
as steers. `ctx$send()` and `gptr_steer()` called from model-evaluated code of the same session tree are refused
with `gptr_error_permission`. Test: a child agent's text never appears in an operator message.

**IC-56 Pending-plan hand-off.** (safe-19) The plan is handed only to the **next** `gptr()` call of the same R
process and environment within one hour, and only when that call is top-level (not nested, not in a run, not in
a loop body); any other `gptr()` call in between discards it with a notice. The executing run prints the plan's
step list before its first action.

### 15.5 Reactor, processes and the store

**IC-57 Re-entrancy.** (req-17, safe-8)

- The reactor tracks its pump depth. A nested pump (depth > 1) runs FIFO tools only of the runs it was given in
  `allow_runs`; its default is `if (is.null(run_current())) NULL else character()`, so System 1 and MCP HTTP calls
  made from inside an `r` evaluation never run a sibling's R tool.
- `later::run_now(0)` is called only at depth 1, or at depth > 1 when `allow_runs` contains a CLI child served by
  the MCP server; in that case the MCP handler answers a request whose token is bound to a run outside
  `allow_runs` with a retryable JSON-RPC error (`-32002`, "gptr is busy; retry") instead of evaluating.
- The background pump is a no-op while the reactor is on the stack (depth > 0).
- Asks raised outside a blocking gptr call (background runs, `gptr_mcp_serve()` at an idle console) never
  prompt from a `later` callback: a background run moves to status `waiting` (a notice; `gptr_jobs()` shows it)
  and the ask is shown at the next `gptr_wait()`, `gptr()` or console turn; a served request that needs approval
  is denied with how to allow it and a console notice. Non-interactively both are `blocked`/denied.
- A background R tool that changed bindings in the user's environment at an idle tick prints one notice.
- P04/P19 acceptance: an inline agent calls System 1 while a sibling has a queued tool; the sibling's tool starts
  only after the first evaluation returns.

**IC-58 One MCP server, one token per client.** (req-18) `gptr_mcp_serve()` keeps one listening socket per
process but issues a separate 192-bit bearer token per client: `mcp.serve_ensure(session)` returns a handle whose
token is bound to that session (the CLI child's session). The server maps token -> session and evaluates each
request in that session's run evaluation environment (so a fork's CLI child evaluates in the fork overlay) with
its mode, rules, budget and usage roll-up; tokens are revoked when the child exits. The explicit user handle
keeps its dedicated session. P18/P20 tests cover a fork and a plan-mode parent.

**IC-59 Session store.** (cran-1, fid-3, safe-10, req-3, cran-2)

- **Open, append, close**: `store_append()` does `con = file(path, "ab"); on.exit(close(con), add = TRUE)`,
  writes and flushes inside `suspendInterrupts()`, per entry or per batch at a turn boundary. No R connection
  outlives a gptr call; the live record keeps the path and the lock only. The same rule holds for the wire log,
  the JSONL frontend (it writes to a connection its caller owns) and the `.stdin` REPL connection (closed on
  `/exit` and by `on.exit()`). R allows 125 user connections, and `--as-cran` examples fail with "connections left
  open" (both reproduced).
- **Torn-line recovery**: opening an existing file for a resume reads its last byte; when it is not LF, gptr
  appends `"\n"` and a `gptr.recovered` custom entry naming the torn byte range before any new entry.
  `store_read()` skips any unparsable line with a diagnostic and re-parents the children of missing ids to the
  nearest valid ancestor in projection.
- **Locks**: `<file>.lock/pid` holds the pid and the process creation time; a lock is stale when
  `pid_alive(pid, create_time)` is `FALSE` or its heartbeat is older than 24 h; the reactor touches the file every
  10 minutes while the session is live. `pid_alive()` (P04, `proc-supervise.R`) is
  `ps::ps_is_running(ps::ps_handle(pid))` plus a creation-time comparison against pid reuse. **ps joins Imports**
  (it is already in the dependency closure through processx; the closure does not grow). `tools::pskill()` is
  never used as a liveness probe (on Windows it always calls `TerminateProcess`; lint rule).
- Tests: `nrow(showConnections())` unchanged after `gptr()` returns, errors or is interrupted; 300 sessions kept in
  a list; CI runs `devtools::test()` with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true`; INFRA-13 extended: SIGKILL
  mid-append, resume, three appends, all present and the tree connected.

**IC-60 Child processes.** (cran-10, fid-4, fid-5, fid-6, fid-18, cran-11, safe-9, cran-19, fid-20)

- `rscript_path()` (P01) = `file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else
  "Rscript")`; every test helper, fixture server and fake CLI uses it (fake CLIs run as `c(rscript_path(),
  fake_cli)` through `options(gptr.cli_path)`); lint rejects a bare `"R"` or `"Rscript"` command in `proc_spawn()`
  and `proc_run()` (R CMD check puts failing dummy R and Rscript scripts first on PATH).
- `child_env()` returns a **complete** named character vector without the removed names (processx rejects `NA`
  in `env`); `child_env_callr(env)` converts it for callr (removed names as `NA`). Every profile (mcp, helper,
  cli-claude, cli-codex, worker, artifact) points `R_ENVIRON_USER` and `R_PROFILE_USER` at gptr's empty files and
  drops `R_ENVIRON` unless passed explicitly (an Rscript child otherwise re-reads keys from `~/.Renviron`).
- `proc_spawn()` and every `callr::r_bg()` pass `encoding = "UTF-8"` (processx drops non-ASCII bytes of piped
  output in a C locale); `write_all()` writes raw bytes (`charToRaw(as_utf8(x))`) and is **non-blocking**: the
  reactor keeps a per-child buffer, retries `write_input()` each iteration and drains stdout/stderr between
  attempts, with a deadline (`gptr.stdin_timeout`, 60 s) and `gptr_error_timeout`.
- `supervise_default()` = `getOption("gptr.supervise")` if set (`isTRUE()`), else `!check_running()`; used by
  `proc_spawn()`, workers and artifacts (passing `NULL` to processx errors). Every long-lived child exits when the
  parent dies: `worker_main()` on stdin EOF or EPIPE and a 5 s parent-pid check; artifacts through their watchdog;
  CLI children through supervision. `proc_spawn()` records a tree marker under `R_user_dir("gptr", "cache")/procs/`;
  the orphan sweep at the next load is mandatory (SIGTERM skips finalizers; verified). P04 acceptance kills the
  parent with SIGTERM and asserts no survivors after the next sweep.
- Under `check_running()` every child-process pool (CLI, MCP stdio, bridges, fixtures, workers) is capped at 2;
  every process-spawning test calls `skip_on_cran()`.
- A requested stop is recorded in the job table (`stop_requested`); any exit after it maps to status `stopped`
  (artifacts, bridges) or `aborted` (children), never `error` (callr 3.8.0 exits 1 with `callr_timeout_error`).

**IC-61 Randomness.** (req-3, cran-8, fid-9) gptr never calls `set.seed()`, `RNGkind()`, `sample()` or
`runif()`, and `parallel` is not imported. Per-agent L'Ecuyer streams are swapped in by one leaf,
`rng_swap(state, expr)` (P09, `eval-core.R`): it saves `get0(".Random.seed", globalenv(), inherits = FALSE)`,
assigns the agent's `c(10407L, <6 seeds>)`, evaluates, keeps the advanced vector in the agent's state, then
restores the saved value or removes the variable. The six seeds come from 24 bytes of `sha256(<agent id>)` reduced
modulo m1 = 4294967087 (three) and m2 = 4294944443 (three), stored as R integers (two's complement), or from an
explicit `.opts$seed` hashed with the agent label. `with_seed_preserved(expr)` (P01, `utils-hash.R`) saves and
restores `.Random.seed` around third-party calls that use R's RNG in the parent (`chromote::Chromote$new()`,
loading shiny, httpuv helpers). Ports come from `port_candidates()` (P01: RNG-free hash bits in 49152-65535),
retried through `httpuv::startServer()` up to 20 times; `httpuv::randomPort()` is never called (it calls
`sample()`, verified). These two functions are the only code that assigns `.Random.seed` (R CMD check exempts
it; the lint rule allows it only there). Tests assert an identical `.Random.seed` after inline sub-agents,
`gptr_mcp_serve()`, the OAuth loopback and `gptr$app(check = TRUE)`.

**IC-62 Encoding at ingress.** (cran-7) `as_utf8(x)` (P01): strings marked "unknown" that are valid UTF-8 are
marked UTF-8; other unknown strings go through `enc2utf8()`. It is applied at every ingress (prompts and
templates, context labels, file reads, child output, `.env` values, frontmatter, readline input). Every
`readLines()` passes `encoding = "UTF-8"`; bare `enc2utf8()` outside `utils-encoding.R` is a lint error
(`enc2utf8()` rewrites unmarked UTF-8 to `<c3><a9>` in a C locale, verified). End-to-end test: a script file with
a UTF-8 prompt literal under `LC_ALL=C Rscript --vanilla`; the bytes in the fake request log, the JSONL and the
document are exact.

**IC-63 Paths, homes and names.** (cran-5, cran-16, cran-20)

- `user_home()` (P01) = `USERPROFILE` on Windows, else `HOME`, else `path.expand("~")`, normalised with `/`;
  `app_config_dir(app)` resolves `%APPDATA%`, `~/Library/Application Support` or `$XDG_CONFIG_HOME` (else
  `~/.config`). Every foreign-harness path (Claude Code, Claude Desktop, Codex, Cursor, VS Code, Pi configs; `.claude`,
  `.agents`, `.pi` skill and agent directories) and `${userHome}` use them.
- `project_root()` honours `options(gptr.project_root)` and `GPTR_PROJECT_ROOT`. `setup.R` sets it to a temporary
  project and redirects `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA` and `XDG_CONFIG_HOME` to temporary
  directories. A Windows CI test plants `.claude.json` under a fake `USERPROFILE` and expects `gptr_mcp()` to list
  it.
- Artifact ids that are Windows reserved device names (`con`, `aux`, `nul`, `prn`, `com1`-`com9`,
  `lpt1`-`lpt9`) are rejected. Data snapshots are `data/001.rds`, `data/002.rds`, ... with the mapping in
  `artifact.json` (`data: [{name, file, class, dim, bytes}]`); the loader reads the file listed for each name.

**IC-64 HTTP details.** (safe-13, fid-11, fid-13, fid-12)

- Every provider, System 1, MCP, OAuth-token and catalog transfer sets `followlocation = 0L`; a 3xx is
  `gptr_error_provider` (class `redirect`) naming only the Location origin, never retried (libcurl forwards
  custom headers such as `x-api-key` across origins; reproduced). INFRA-22 and `test-secrets-e2e.R` add a
  redirecting mock that must receive no key bytes.
- `sse_splitter()` accepts LF, CRLF and lone CR line ends (a CR at a chunk end is held until the next chunk),
  strips a leading BOM, drops comment lines, joins `data:` lines with `"\n"`, lets the **last** `event:` field win
  and parses `id` and `retry`; `test-http-sse.R` and the INFRA-23 row add CRLF, CR-only, split-CRLF and
  duplicate-`event:` cases.
- `retry-after` HTTP-dates go through a locale-independent `parse_http_date()` (`month.abb`, UTC); an unparsable
  value falls back to exponential backoff (tests under `LC_ALL=de_DE.UTF-8` and `retry-after: soon`) [02
  fact-check].
- Provider records gain `rate = list(requests_per_s, tokens_per_s)` (the `typesafe` record: 40 and 1e5,
  overridable by settings and catalog); static rates feed the same token bucket as header-derived limits, and
  System 1 admission is process-wide.

### 15.6 Subscription CLI routes

**IC-65 CLI discovery and invocation.** (cran-9, cons-21, req-33, fid-7, fid-8, safe-12)

- `cli_find()`: `options(gptr.cli_path = list(claude =, codex =))`, then PATH, then per-OS known locations
  (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `%USERPROFILE%\.local\bin`,
  WinGet links, and for codex the npm prefix resolved to the vendored `codex.exe`); RStudio and Positron on macOS
  do not source shell profiles. The npm `claude.cmd` shim is **refused** with an install hint (07); native
  binaries run without a shell, so the empty-string arguments `--tools ""` and `--setting-sources ""` are safe.
  The providers' `status()` functions use only cached `Sys.which()` data unless `gptr_providers(check = TRUE)`;
  `check = FALSE` never spawns a process.
- **claude** argv adds `--permission-mode default` and `--allowedTools "mcp__gptr__*"`, so the CLI sends no
  `can_use_tool` for gptr's own tools and gating happens once, in the `mcp_message` dispatch (the handler still
  denies anything else). With a budget in force it adds `--max-turns <remaining turns>` and
  `--max-budget-usd <remaining cost>` [07 table]. The child environment follows G6 §3.7 verbatim: remove
  secret-like names, registered values, `^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)` and
  `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`; keep `CLAUDE_CODE_OAUTH_TOKEN`,
  `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`; `CLAUDE_CODE_USE_BEDROCK`/`VERTEX`/`FOUNDRY` are removed with the
  `billing_env` warning. A capability probe (`--help`, version) detects a CLI whose `-p` defaults to `--bare`
  (which never reads the subscription login [07]) and passes the documented opt-out or stops with
  `gptr_error_cli_version`. After `system/init`, an `apiKeySource` other than `"none"` aborts the turn with
  `gptr_error_billing`. The wire log is per session (`cache/tmp/wire-<session id>.jsonl`).
- **codex** argv per turn: `codex exec --json --ignore-user-config --skip-git-repo-check -m <full id> -C <wd>
  -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN
  -c mcp_servers.gptr.default_tools_approval_mode="approve" -c mcp_servers.gptr.required=true
  -c mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <mode> -`; resume: `codex exec resume <thread> --json ...
  -c sandbox_mode=<mode> -` (resume rejects `-s` and `-C`) [08 §2.E, line 594-600, fact-check 16]. gptr's gate
  stays the approval authority. The child environment removes `^(CODEX_MANAGED_|CODEX_SANDBOX)`, `CODEX_API_KEY`,
  `CODEX_ACCESS_TOKEN`, `OPENAI_API_KEY`, `OPENAI_BASE_URL` and keeps `CODEX_HOME`. The evidence note is corrected:
  the in-session HTTP MCP route was verified through app-server listing and calls without a model; the verified
  model-driven MCP call used `default_tools_approval_mode = "approve"` and `required = true` [08 §2.G].
- **Sandbox mapping**: `plan`, `manual` and `edits` -> `read-only` (file changes go through gptr's gated
  `write`/`edit` over MCP, so edits-mode approval and checkpoints apply); `auto` -> `workspace-write`. Before a
  `workspace-write` exec gptr hashes the `control` files (IC-54) and refuses to load changed ones until the user
  confirms; the files checkpointer walks after each exec so `/undo` covers Codex's edits. On native Windows the
  sandbox is probed and the route falls back to `read-only` with a warning when it is not ready [08 line 2796].
  The one-time notice says Codex runs its own shell inside its sandbox.
- Codex has no turn cap flag: gptr counts `turn.completed`/`item.completed` events and cancels at the cap; each
  exec has a wall-clock limit (`gptr.cli_turn_timeout`, 3600 s).
- Live tests (`GPTR_LIVE_TESTS=true`) run Codex in a non-git temporary directory and require it to call the gptr
  MCP `r` tool.

### 15.7 Budgets, evaluation and tokens

**IC-66 Budgets.** (safe-11) Settings default `budget = {cost: 5, tokens: 2000000, turns: null}` per top-level
call (per prompt at the console); `budget_near` at 80%; reaching it asks to extend by the same amount
(`ask_human`) interactively and stops with status `budget` otherwise; `null` set explicitly disables a limit.
Budgets are hierarchical: every request's check walks to the root session and charges the root, and children
start with `min(<their share>, <root remaining>)`. Caps: `gptr.max_nested_calls` (20 `gptr()` calls per `r`
evaluation; a team or fan-out counts as one) and `gptr.s1_max_elements` (10,000 elements per System 1 call; error
with a hint to chunk). Sourcing a document in `auto` prints one notice with the number and cost of live nested
calls and suggests `GPTR_REPLAY=replay`.

**IC-67 Evaluator details.** (fid-2, cran-15, plug-6, fid-15, fid-1, fid-16)

- R8 amended: the evaluator clears the `withVisible()` result in place (`res[1L] = list(NULL)`) before its frame
  returns and never stores it elsewhere (a result that aliases a user object, such as `L$a`, `(x)` or `get("x")`,
  otherwise makes the next edit copy; reproduced and fixed in place). `test-copy-eval.R` adds `L$a`, `(x)`,
  `get("x")`, `x@slot` and `x[["a"]]` rows.
- Plot capture: when `grDevices::dev.cur() == 1` and no human can see a device, the evaluator opens
  `grDevices::pdf(NULL)` with `dev.control(displaylist = "enable")`, closes it on exit and `dev.set()`s back to the
  prior device (no `Rplots.pdf` in `getwd()`; no screen device under `_R_CHECK_SCREEN_DEVICE_=stop`).
- Images: at most `gptr.r_max_images` (3) plots are attached per `r` result; later plots are kept in the session's
  out store and listed as `[plots 4-50 not attached: gptr$plot(k)]` (`gptr$plot(which = NULL, width, height)`).
  Image tokens count against `gptr.r_output_tokens`. When a request would exceed the provider's image count or
  byte limit (catalog `max_images`, 32 MB), older images are projected as `[image omitted: gptr$plot(<id>)]`,
  recorded by an appended `gptr.image_elision` entry (one stated cache break). P09 acceptance: a 50-plot loop
  attaches 3 images.
- `eval_guard()` flags the `q` and `quit` symbols in any position (as a value, a `FUN` argument, inside
  `match.fun`, `get`, `do.call`, `base::`) as level 4 [12 fact-check].
- No shipped prompt text or skill recommends `str()` (it leaves a sticky reference: every `str()` of a large
  object makes the next edit copy; re-verified); the texts recommend `gptr$describe(x)`, `dim()`, `head()`. A P07
  test fails when any shipped section or skill mentions `str(`; the high-performance-r skill states the cost.
- `gptr$knit()` routes the shell engines (`bash`, `sh`, `zsh`, `powershell`, `cmd`) through `gptr$sh()` with the
  `helper` environment and a timeout, and classifies the others like `gptr$script()` [G5 fact-check 7].

**IC-68 Prompt composition by owners.** (plug-2, plug-10, plug-15, req-25; measured with rtiktoken o200k in
`scratchpad/work/design/review-resolution/prompt/measure3.R`)

- `<rules>` = the `guidelines` of the active direct tools in array order (read: its line; r: the three R lines;
  edit: four lines; write: one line; plugin direct tools: theirs), then P07's three closing lines. With the
  standard tools this equals `03` §7.3; the `readonly` preset drops the edit and write lines (238 -> 123 tokens).
- `prompt_section` specs may set `parent = "<section>"`: a fragment rendered inside that section at the
  `{{fragments}}` marker, in `order`. `<r_session>` is P07's core text with fragments from `builtin:tools`
  (helpers, `out`), `builtin:bridges` (shell), `builtin:lang` (Python, SQL, knitr) and `builtin:subagents`
  (sub-agents); `-builtin:bridges` removes its line. `documents` is registered by P15, `artifacts` by P23 and
  `system1` by P13 (IC-27 amended). P07's acceptance compares P07-owned texts byte for byte; P24 compares the
  composed prompt with every built-in loaded.
- The `r` tool schema is frozen in one of four variants: `record` and `note` only when a document is bound at
  freeze, `timeout` (described "Seconds; best effort. Default 3600.") only when no human can answer. Measured:
  198 (old) -> 189 / 170 / 138 / 119 tokens.
- The skills catalog shows pseudo-paths `[skill:<name>/SKILL.md]` that `read` resolves (`skill:<name>/<path>`),
  never library paths (which cost more and leak the Windows user name): 152 -> 143 tokens for the two built-ins.
- `<context>` adds one sentence for `trusted="false"` blocks (106 -> 141). `<r_session>` drops the MCP sentence
  (the `<mcp>` section says it) and adds the `record = false` rule (443 -> 455).
- Non-interactive runs in `manual` mode keep `ask` declared (+145 tokens of schema); calling it stops the run
  with status `blocked` and `gptr_error_noninteractive` carrying the questions (NS-12). The manual suffix reads
  `No one can answer questions or approvals in this run: actions that need approval, and questions asked with the
  ask tool, stop the run. Ask only when no reasonable assumption lets you continue.`; other modes keep the
  earlier suffix.
- New static totals (o200k; `03` §12.1): minimal 615 + 656 = **1,271**; standard core non-interactive 615 + 1,203
  + 542 = **2,360**; standard non-interactive with every section and a document 666 + 1,636 + 542 = **2,844**;
  standard interactive with every section and a document 792 + 1,653 + 542 = **2,987**; without a document 2,750.
  These are `prefix-baseline.json`'s initial values.

**IC-69 Extension API additions.** (plug-1, plug-9, plug-7, req-35, plug-12, plug-4, plug-16, req-14, req-15)

- **Routers** (kind `router`): `route(request, ctx)` with `request = list(prompt, messages (projected, read-only),
  state (the router's state from its last `gptr.router` entry on this branch), previous (the previous request's
  model), reason = "turn" | "compaction" | "direct", session)` returns a model ref or `list(model, thinking =
  NULL, state = NULL)`. Dispatch: P08 stores `router:<name>` as the session's model when `model` resolves to a
  router; P06 calls the router (service `router.call`) before each request and at compaction, with a timeout of
  `timeout` seconds (default 2; `ctx$decide()` allowed), falling back to the default model with a diagnostic. Each
  switch appends `model_change` (reason `router`) and a `gptr.router` state entry and emits `route`; each switch
  costs one System 1 call and one cache miss (`03` §12.4). P13 ships `inst/gptr/examples/jev-router.R`, a tested
  complexity router loadable with `extensions =`; P13 acceptance: a fake-classifier router switches models after
  the first successful `edit`, with exactly one `model_change`.
- **`ctx` run control**: `ctx$set_model(ref, thinking = NULL, reason = "plugin")` (a `model_change` at the next
  request boundary; one cache miss), `ctx$add_tools(specs)` (P07 `session_add_tools()`: rank-0 registration; an
  operator `tool_change` message carrying the declarations when the adapter declares `tool_addition`, else the
  specs become `r` members announced in an operator note), `ctx$tokens(x, class = "prose")` (the `estimator`
  kind), `ctx$eval(code, envir = NULL)` (the `evaluator` kind; plugin code, not gated), `ctx$describe(x, budget
  = 150L)`. `gateway_run()` calls `session_add_tools()` for `tools =`, `plugins =` and `extensions =` on a
  continuation.
- Tool specs gain `render = function(call, result, width)` (console rendering) and `parameters` may be a
  `function(ctx)` evaluated once at freeze (the `r` schema variants). New kinds (P02 validates them): `preset`
  (stable: `tools` chr or `function(human, model)`, `sections` named lgl or `function(name)`, `preamble`
  `"standard" | "short"`; `builtin:prompt` registers `minimal`, `standard`, `readonly`, `extended`; section
  predicates test the preset record, not its name), `risk_rule` (stable, resolve `all`: rows of
  `risk-functions.csv` columns, concatenated; the highest level wins on duplicates), `renderer` [experimental]
  (`type` = a custom entry type, `render(entry, width, ctx)` -> chr, `doc(entry, format)` -> chr lines),
  `search_source` [experimental] (`docs(ctx)` -> df `id`, `text`, `kind`, indexed by `gptr$search()`), `store`
  [experimental] (`open`, `append`, `read`, `fork`; the JSONL store is its built-in, selected by setting `store`),
  `evaluator` [experimental] (the `eval_r()` contract; the built-in is `r`, selected by setting `evaluator`), and
  `service` (IC-34). 31 + 7 = **38 kinds**.
- New event `request_params` (patch chain): payload `params` limited to the fields the adapter declares non-prefix
  (`capabilities$request_params`, e.g. `service_tier`, `metadata`, `user`); a patch to any other field is ignored
  with a diagnostic.
- Arguments that name extensible records are validated against the registry, not fixed vectors: `backend`
  (`registry_names("backend")` plus `"auto"`), `gptr$app(kind =)` (`artifact_type`), `.opts$frontend` and setting
  `frontend` (`frontend`), `.opts$preset` (`preset`). `mode` stays the fixed four values (the permission model is
  defined on them; plugins add policies instead).
- **Overrides are per record**: a lower-rank record shadows only the record with the same `(kind, name)`; a
  whole built-in is disabled only by an explicit `-builtin:<name>` filter (Pi merges per tool:
  `agent-session.ts:3478-3481`). P02 test: a user `read` override leaves `edit` and `gptr$grep` working.
- **Session scope**: `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)`;
  the API object, lazy activation and `hook_add()` carry `session`, every staged `registry_add()` receives it,
  and the session's records are removed at `session_shutdown` and by its finalizer. P02/P17 test: a factory passed
  through `extensions =` is invisible to the next `gptr()` call.
- **Workers inherit the registry**: the worker spec gains `registry = list(specs = <rank-0 session specs and
  rank-3 user specs>, plugins = <enabled plugins with ranks>, filters = chr)`; `worker_main()` re-registers them
  first. Functions from package namespaces serialise by reference; closures from the global environment are shipped
  with their environments (documented); a spec that cannot be serialised makes an explicit `backend = "worker"`
  fail with `gptr_error_invalid_argument` naming it, and `auto` stays inline. P19 acceptance: a plugin `r` member
  and a `gptr_fake_provider()` spec work inside a worker.
- **Token extension points**: `gptr_check(x, error = FALSE, tokens = FALSE)`; `tokens = TRUE` reports a plugin's
  declaration cost and the printed-result cost of each member on its examples. Truncation policies and catalog
  formatters are recorded as v1.x kinds (§1.3 of `03`). The append-only transcript is why Pi's `context` message
  transform is not ported; `compactor`, `context_block` and `request_params` are the supported alternatives.

### 15.8 Secrets, caches and small items

**IC-70 Late secrets and child output.** (safe-14, safe-21)

- `gptr_scrub(paths = NULL, dry_run = TRUE, error = FALSE)` (P03, `auth-redact.R`, exported): scans the
  workspace's persisted text (sessions, caches, spill files, plans, transcripts, the documents bound in this
  project; `paths` overrides) for registered secret values and derived forms; returns a data frame (`file`,
  `secret`, `count`, no values); `error = TRUE` signals `gptr_error_secret_found` when anything is found (for
  pre-commit and CI); `dry_run = FALSE` rewrites the files with markers, the only sanctioned rewrite of
  append-only files, and appends a `gptr.scrub` entry to each rewritten session. `secret_register()` scans live
  sessions' in-memory entries and warns with counts and the `gptr_scrub()` call [G6 §4.7].
- Child output is persisted only through gptr: MCP stderr and artifact logs are read incrementally and appended
  through `redact_stream("persist")`; raw redirect files are deleted at process exit; MCP logs live in
  `tempdir()/gptr/mcp-logs/` unless `options(gptr.mcp_debug = TRUE)`. `test-secrets-e2e.R` greps these sinks, the
  deferred-write sidecars and the worker spec and result files.
- System 1 cache values store `question_sha256`, never the question, and `input_hash` = sha256 of a per-project
  salt (`.gptr/cache/s1/salt`, committed, RNG-free id bits) concatenated with the canonical input; the cache key
  includes the salt. `transcripts/` is gitignored by default. The Security considerations page mentions PHI.

**IC-71 Smaller contract fixes.**

| Item | Decision | Issues |
|---|---|---|
| out store | per session (`live$out`, cap `gptr.out_keep`); `out_put(..., session = NULL)`, `out_get(id, ..., session = NULL)` look in the session, then the process store, then the spill file; ids `o` + 6 hex (RNG-free) | req-27 |
| artifact line | `print.gptr_artifact` shows `(running in background)` for status `running`; P14's renderer prints `artifact  <id>  ->  <url>   (running in background)` on `artifact_start` (NS-8) | req-22 |
| `gptr_config()` | `.scope = NULL`: `"project"` when a workspace exists, else `"session"` (NS-9) | req-23 |
| System 1 in `while()` | the `I()` hint claim is dropped (a function cannot see that it is a condition, verified); `s1_batch` is removed; a once-per-session message `s1_split` names `I(x)` when a data frame is split into several states | req-24 |
| agent names | names equal to a session accessor (`text`, `value`, `values`, `usage`, `cost`, `history`, `messages`, `model`, `mode`, `status`, `reason`, `id`, `kind`, `file`, `turns`, `envir`, `children`, `ext`, `plan`, `last_rewind`, `editor_text`) are rejected; children stay reachable through `[[` and `$children` | cons-23 |
| REQ-08 sorting | `gptr$find(sort = c("path", "mtime", "size", "relevance"))` (fuzzy score); `gptr$grep(output = "files", sort = c("path", "count", "mtime"))` | req-30 |
| forced tool choice | model capability `forced_tool_choice` (`FALSE` for Anthropic 5.x); `returns =` uses `output_config.format` on Anthropic, elsewhere `auto` + instruction + validation; `gptr_check()` rejects adapters sending a list `tool_choice` when the capability is `FALSE` [07 §2.5-2.6] | fid-14 |
| OAuth | refuse AS metadata without `code_challenge_methods_supported` or without S256; validate `iss` (RFC 9207) when advertised; own callback reader keeping `iss`; state and redirect checks; negative mock cases in P18 [16 §4 item 8, fact-check] | fid-17 |
| frontmatter | scalars of the string keys (`name`, `description`, `version`, `model`, `tools`, `argument-hint`) keep their source text (YAML 1.1 turns `yes`/`on`/`1.0` into logicals and numbers; verified) | fid-19 |
| describers | methods for classes of packages outside Suggests (Matrix, SeuratObject, SingleCellExperiment, arrow, ggplot2) use only base generics, `methods::slot()`/`slotNames()`, `attr()`, `dim()`, guarded by `isNamespaceLoaded()`; never `pkg::fun()` | cran-21 |
| compaction floor | at freeze the post-compaction floor (static prefix + project instructions + re-injection budgets + 634) is compared with the threshold; if it is not below it, skill and project re-injection budgets are cut to 25% of the threshold, and if still not below, the model is refused for the preset with `gptr_error_invalid_argument` suggesting `preset = "minimal"` or `context = "names"`; after a threshold compaction, further threshold compactions wait until the context grew by 20% of the window | safe-20 |
| concurrent writers | read-modify-write of settings, trust, MCP and user-level project files under a short `mkdir` lock (`<file>.lock/`, pid + creation time, 50 x 100 ms retries); document locks add `pid_alive()`; checkpoint blob GC prunes only blobs unreferenced by every session file of the project and older than `gptr.checkpoint_days`, and skips while another live pid holds a session lock in the project | safe-17 |
| artifact access | each launch gets a 128-bit token (`openssl::rand_bytes(16)`, else `/dev/urandom` on Unix; on Windows without openssl no token and a notice); the wrapper app rejects sessions whose URL lacks `gptr_token=<hex>`; the handle's URL carries it; static checks flag reads of `secret_file` paths at level 3 | safe-22 |
| knobs | one knob per limit: options `gptr.subagents.max_depth`, `.max_active`, `.max_workers`, `.max_cli`, `.max_tasks` mirror the settings keys; `gptr.max_active` is HTTP transfers only; `gptr_parallel(max_active = NULL)` defaults to `gptr.subagents.max_active` | cons-20 |
| enums | message `source` in `prompt`, `pipe`, `steer`, `follow_up`, `repl`, `parent`, `replay`, `extension`, `agent`, `imported`; `child_env` resolves `first`; `project_trust` is a first decision everywhere and `gptr_trust()` emits nothing; the `egress_ack` message is P08's | cons-20 |
| names | `setting_get()` is the only reader; `settings_get()` is the `settings.get` implementation; `ns.resolve`; `check_adapter()`; `fake_classify(model, state, questions, opts)` | cons-17 |
| Suggests generics | `vctrs` methods registered lazily as before; `pkgload::load_all()` appears only inside the generated child-script text of `helper-tracemem.R`, never as package or test code | cons-23 |
| `gptr_last()` | `the$last` holds the most recent session **strongly** (a shell holds no frames or user objects, so this is copy-safe under R1/R2); the live index stays weak; a replaced session is released normally (a weak reference was collected at the first `gc()`, verified) | cons-12 |
| `03` drift | the signature blocks of `03` (reactor, evaluator, messages, tool result, session fields) point to this contract; `03`'s manifest example provides `"trials/search"`; `tool_call` fails closed with **block**; the deprecation class is `gptr_warning_deprecated`; the settings key is `tools.presets`; the experimental kinds include `route` | cons-18 |
| fixture servers | the base-R SSE mock stays on `serverSocket()` (it needs raw streaming; `serverSocket()` has no host argument and listens on every interface, reproduced), runs only under `skip_on_cran()` for one test, and answers only requests whose path carries a per-run token; the MCP fixture's HTTP transport and `gptr_mcp_serve()` bind `127.0.0.1` through httpuv | cran-18 |
| stale figures | the PIPEWAIT evidence is the fact-check's (default pool 4.94-5.11 s, streams fully serialised; fixes 1.25-1.36 s); "`later_fd` cannot watch processx pipes on Windows" is LIKELY (inferred, untested) [15 fact-check] | fid-21 |

**IC-72 DESCRIPTION, lint and conventions.** (cran-4, cons-14, cran-22, cons-13, cran-12, cran-13, cran-14, fid-10,
req-21, cons-19, cran-16)

- P01 writes, once: `Authors@R` with the maintainer (as in the current DESCRIPTION) in roles `aut`, `cre`, `cph`,
  plus `person("Mario", "Zechner", role = c("ctb", "cph"), comment = "Author of 'pi' (MIT), from which tool texts
  and templates are derived")`; `Copyright: file inst/COPYRIGHTS` (Pi, models.dev, the gitleaks-derived patterns);
  `URL`, `BugReports`, `Language: en-US`; `ps` in Imports. No `VignetteBuilder` before vignettes exist (a
  `VignetteBuilder` without vignettes gives a NOTE, verified): P25 adds `VignetteBuilder: knitr` together with the
  vignettes, a named exception to "Version is the only DESCRIPTION field P25 may change". P01 acceptance asserts
  these fields.
- Expected check result at every milestone: 0 errors, 0 warnings, and no NOTE apart from the incoming-feasibility
  NOTE naming the maintainer (gptr 0.7.0 is on CRAN, so 1.0.0 is an update and gets no "New submission" NOTE).
  P25 runs `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` on submission day and records the
  result in `cran-comments.md`.
- `.lintr`: `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`,
  `object_name_linter(styles = "snake_case", regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$"))`
  (lintr 3.3.0.1 flagged `<<-` and those S3 methods, verified). `test-lint-rules.R` finds `<-` through
  `getParseData()` `LEFT_ASSIGN` tokens, not a text regex (which would flag `` `$<-.gptr_session` ``), and adds the
  rules: bare `enc2utf8(` outside `utils-encoding.R`; `tools::pskill(`; `RNGkind(`; `.Random.seed` assignment
  outside `rng_swap()` and `with_seed_preserved()`; `httpuv::randomPort(`; `withr::` in `R/`; a bare `"R"` or
  `"Rscript"` command in `proc_spawn()`/`proc_run()`.
- `.Rbuildignore` adds `^CLAUDE\.md$`, `^AGENTS\.md$` and `^\.claude$`.
- Conventions: non-ASCII characters in R sources are written as `\u` escapes (for example `"\u00e9"`), which are
  marked UTF-8 in every locale, so `intToUtf8()` is not needed; `@examplesIf` predicates use the fake provider or
  `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` (there is no `gptr_has_key()`); package code restores state with
  `on.exit(..., add = TRUE)` right after the change and uses withr only in tests; `:::` is never used in `R/` and
  tests need none; the complete condition-class list is §2.2 of this contract; the layout lists `R/aaa-state.R`,
  `inst/templates/` and `inst/extdata/`; `LICENSE.md` is P01's; "files the package writes" adds documents the
  user named or confirmed and tool writes approved by the permission mode, and nothing by default in
  non-interactive runs.
- The register's D-28 says 63 exports.

**IC-73 Benchmarks and token accounting.** (plug-5, plug-7, plug-17, plug-18, req-34)

- P01's CI gains a `bench` job that installs rtiktoken (a development tool) and runs `Rscript --vanilla
  dev/bench/tokens/run.R --check` once the runner exists.
- The golden-transcript runner (`dev/bench/tokens/run.R`) and the NS-2/NS-3 fixtures move to P07 (M1); P10, P13,
  P15, P18, P19, P22 and P23 each add their NS fixture and baseline rows in their acceptance; P24 covers every
  gate of `03` §12.7 (prefix +2%, input and output +5%, request count and image tokens +0, describer facts no
  loss, catalogs +5%) and adds `tests/testthat/test-s11-conformance.R`: a fixture plugin registers one record of
  every kind and the test asserts that each is used at run time.
- P25's release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against one Anthropic and one OpenAI model
  and records request counts (within +2 of the golden transcript) and input tokens (within 20%) in
  `dev/bench/tokens/live-<date>.csv`; the golden transcripts script the agent, so they measure harness potential,
  and the live run measures behaviour.
- `tools.presets` ships defaults `{"google/gemini-3*": "extended", "anthropic/claude-haiku-4-5*": "extended"}`,
  applied only when the catalog's `cache_min` exceeds the projected standard prefix (o200k estimate times the
  provider prior) and the session is expected to pass break-even (interactive sessions and fan-out children).
- `03` §12.1 and §12.8 report o200k and projected Claude tokens (x1.35 prior, range 1.3-1.6); budgets are in
  o200k-estimated units scaled by the session multiplier. `03` §12.4 gains rows for every new cost of this
  section: `!expr` notes (budget 300, the `workspace_changes` rules), tool additions after a plan -> auto switch
  (the edit and write schemas as a `tool_addition`, about 480 tokens), router switches, `ask` in non-interactive
  manual runs (+145), the `trusted="false"` sentence (+35), the Claude-CLI route's own framing beyond gptr's
  frozen prompt (UNCERTAIN until the live suite measures it), and the gptr MCP schemas Codex receives (four tools,
  about 700 tokens per turn inside its 19-38K).
