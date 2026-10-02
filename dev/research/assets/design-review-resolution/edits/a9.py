from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""   `/exit` fires `session_shutdown`, closes the store and returns the session invisibly.""",
"""   `/exit` fires `session_shutdown`, releases the store's lock (no connection was left open) and returns the
   session invisibly."""),
("""   line; nothing live is shared; its first request re-reads `qc`'s cached prefix (same model); the block header
   records `fork=<qc id>:<turn>` and replays inside `local({...}, envir = gptr_resume("<id>")$envir)`.""",
"""   line; nothing live is shared; its first request re-reads `qc`'s cached prefix (same model); the block header
   records `fork=<qc id>:<turn>` and its code is wrapped `local({...}, envir = gptr_resume(block = "<id>")$envir)`.
   On re-source, `gptr_fork(qc)` makes a fresh fork, the document route binds it to the block id, and the wrapper
   finds that fork, so the main-line `qc_flags` and `qc$value` stay unchanged [IC-46]."""),
("""5. `while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev))`: one request per
   iteration unless cached; if `diagnostics()` returns a data frame the batch rule would give one state per row
   and `while()` would error on a vector; the error hint names `I(diagnostics(fit))` [J-req verified].""",
"""5. `while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev))`: one request per
   iteration unless cached; if `diagnostics()` returns a data frame the batch rule gives one state per row and
   `while()` errors on a vector with R's own message; gptr cannot see that its value is a condition (verified), so
   it prints a once-per-session message naming `I(diagnostics(fit))` when it splits a data frame [IC-71]."""),
("""   child's environment, so Codex can evaluate R in the live session through gptr's gate; the review runs in
   Codex's read-only sandbox.""",
"""   child's environment (a token bound to the `code` child's session [IC-58]), so Codex can evaluate R in the live
   session through gptr's gate; the review runs in Codex's read-only sandbox (every non-`auto` mode maps to
   read-only [IC-65])."""),
("""   are serviced by `later::run_now(0)` inside the pump.""",
"""   are serviced by `later::run_now(0)` in the outermost pump [IC-57]. The statement owns one team block listing the
   three children, so re-sourcing replays the reviews with zero requests [IC-47]."""),
("""3. The console prints `artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)` and
   opens the viewer (interactive only);""",
"""3. The console renderer prints `artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)`
   on `artifact_start` (the handle's URL also carries the access token [IC-71]) and opens the viewer (interactive
   only);"""),
("""`gptr("Clean up the data directory", mode = plan)` runs the `readonly` preset; R runs in a scratch child
environment; the answer ends in a `<proposed_plan>` saved to `.gptr/plans/` and kept as the pending plan.""",
"""`gptr("Clean up the data directory", mode = plan)` runs the `readonly` preset; R runs in a scratch child
environment and only calls known to be read-only run (`targets::tar_destroy()` or `unlink()` would be denied
[IC-54]); the answer ends in a `<proposed_plan>` saved to `.gptr/plans/` and kept as the pending plan."""),
('''run. Allow it with mode = auto or gptr_permissions(allow = \\"r(fn:unlink)\\")."''',
'''run. Allow it with mode = auto or gptr_permissions(allow = \\"r(fn:unlink)\\")." If the agent needs an answer
instead, it calls `ask`, which stays declared in non-interactive `manual` runs, and the run stops with
`gptr_error_noninteractive` carrying the question [IC-68].'''),
("""Pi's expandability comes from one extension API that every feature uses. gptr matches and extends it: one
registry keyed by (kind, name), one registration verb, 31 kinds (a plugin can add more), per-kind contracts""",
"""Pi's expandability comes from one extension API that every feature uses. gptr matches and extends it: one
registry keyed by (kind, name), one registration verb, 38 kinds (a plugin can add more; the review added
`preset`, `risk_rule`, `service`, `renderer`, `search_source`, `store` and `evaluator` so that even the session
store, the evaluator and the service table are replaceable [IC-34, IC-69]), per-kind contracts"""),
("""as `builtin:<name>` (rank 6) and can be overridden or disabled with filters (`-builtin:<name>`,
`-<kind>:<name>`), except that project settings cannot disable user or built-in policies and hooks.""",
"""as `builtin:<name>` (rank 6). A lower-rank record shadows only the record with the same (kind, name), so
overriding `read` leaves `edit` and `gptr$grep` intact (Pi merges per tool); whole built-ins are disabled only with
explicit filters (`-builtin:<name>`, `-<kind>:<name>`) [IC-69]; no filter disables the permission kernel
(`builtin:permissions`, `builtin:plan`, the critical and secret guards) [IC-53]. Records passed as call arguments
(`tools =`, `extensions =`, `plugins =`) are scoped to their session and removed with it [IC-69]."""),
("""| Model routers | `router` (`gptr_router()`): `route(request, ctx)` returns a registered model within 50 ms; errors fall back to the default | none enabled; a Jev complexity router ships as a documented example | factory | cost-aware routing (`model = cheapest`) using `ctx$decide()` |""",
"""| Model routers | `router` (`gptr_router()`): `route(request, ctx)` with the projected messages, its per-branch state, the previous model and the reason (turn, compaction), returning a model (and optional thinking level and state) within `timeout` (2 s); called before every request; each switch is a `model_change` plus a `gptr.router` state entry; errors and timeouts fall back to the default [IC-69] | none enabled; `inst/gptr/examples/jev-router.R` (P13) is a tested Jev complexity router that plans on a strong model and hands off after the first successful edit, like Pi's | factory | cost-aware routing (`model = cheapest`) using `ctx$decide()` |"""),
("""| Tools | `tool` (`gptr_tool()`): schema, `execute(input, ctx)` or `fun`, `exposure` (`direct`, `r`, `deferred`, `hidden`), `namespace`, `execution`, `risk(input, ctx)`, `snippet`, `guidelines`, `signature`, `output_tokens`, `record`, `available()` |""",
"""| Tools | `tool` (`gptr_tool()`): schema (or a function of `ctx` evaluated at freeze), `execute(input, ctx)` and/or `fun`, `exposure` (`direct`, `r`, `deferred`, `hidden`: a default visibility [IC-37]), `namespace`, `execution`, `risk(input, ctx)`, `snippet`, `guidelines`, `signature`, `output_tokens`, `record`, `available()`, `render(call, result, width)` |"""),
("""| Context / environment describers | `context_block` (`gptr_context_block()`): `provide(ctx, budget)`, placement `first`/`turn`, authority `data`/`operator`; S3 generic `gptr_describe()` |""",
"""| Context / environment describers | `context_block` (`gptr_context_block()`): `provide(ctx, budget)`, placement `first`/`turn`/`both`, authority `data`/`operator` (operator only from rank >= 3 [IC-52]); unchanged turn blocks are skipped [IC-38]; S3 generic `gptr_describe()` |"""),
("""| System prompt sections | `prompt_section` (`gptr_prompt_section()`): text or `function(ctx)`, tier, order, budget | every section of §7.3 (`builtin:prompt`) | factory | house rules, a domain preamble |""",
"""| System prompt sections | `prompt_section` (`gptr_prompt_section()`): text or `function(ctx)`, tier, order, budget, `parent` (a fragment inside another section) | the sections of §7.3, each registered by the built-in that owns the capability (`builtin:prompt` for the core; tools, bridges, lang, subagents for `<r_session>` fragments; documents, artifacts, system1 for their sections) [IC-68] | factory | house rules, a domain preamble, a line in `<r_session>` for a toolkit |
| Presets | `preset`: direct tools, section predicates, preamble variant | `minimal`, `standard`, `readonly`, `extended` (`builtin:prompt`) | factory | a domain preset with its own tools and sections [IC-69] |"""),
("""| Document formats and history writers | `doc_format`: `ext`, `locate`, `render`, `write` | `r`, `rmd`, `qmd`, `ipynb`, `transcript` (`builtin:documents`) | factory | an Org-mode or `targets` writer |""",
"""| Document formats and history writers | `doc_format`: `ext`, `locate`, `render`, `upsert`, `inert` | `r`, `rmd`, `qmd`, `ipynb`, `transcript` (`builtin:documents`) | factory | an Org-mode or `targets` writer, which can also provide the `doc.*` services through `service` records [IC-34] |
| Custom-entry renderers | `renderer` [experimental]: `render(entry, width, ctx)`, `doc(entry, format)` | - | factory | show plugin state appended with `ctx$append_entry()` in the console and documents [IC-69] |
| Search sources | `search_source` [experimental]: `docs(ctx)` | members, MCP tools, skills | factory | a searchable domain corpus for `gptr$search()` [IC-69] |
| Session stores | `store` [experimental]: `open`, `append`, `read`, `fork` | the append-only JSONL store | factory | a SQLite or remote store [IC-69] |
| Evaluators | `evaluator` [experimental]: the `eval_r()` contract | `r` (the in-session evaluator) | factory | a remote or sandboxed evaluator for `r` [IC-69] |
| Services | `service` [experimental]: `fun` | every service of the contract's §7.0, owned by its built-in | factory | replace a built-in's service, e.g. document sites for a custom writer [IC-34] |
| Risk rules | `risk_rule`: additive classifier rows (highest level wins) | the shipped risk tables | factory | organisation- or domain-specific risk levels [IC-69] |"""),
("""| Artifact types | `artifact_type`: `build`, `check`, `launch`, `stop` | `shiny`, `html` (`builtin:artifacts`) | factory | Plumber APIs, Quarto dashboards |
| Sub-agent backends | `backend` (`gptr_backend()`): `start(spec, ctx)` -> handle with fds, `poll`, `cancel`; must not block the reactor for more than 50 ms; cancel kills the tree | `inline`, `worker`, `cli` (`builtin:subagents`) | factory | a mirai or HPC-cluster backend |""",
"""| Artifact types | `artifact_type`: `build`, `check`, `launch`, `stop` (`gptr$app(kind =)` accepts any registered one [IC-69]) | `shiny`, `html` (`builtin:artifacts`) | factory | Plumber APIs, Quarto dashboards |
| Sub-agent backends | `backend` (`gptr_backend()`): `start(spec, ctx)` -> handle with fds, `poll`, `cancel`; must not block the reactor for more than 50 ms; cancel kills the tree (`backend =` accepts any registered one [IC-69]) | `inline`, `worker`, `cli` (`builtin:subagents`) | factory | a mirai or HPC-cluster backend |"""),
("""| Front ends | `frontend`: `run(session, ...)` | `console` REPL, `jsonl` event sink; `knit_print` | factory | an RPC server or Shiny chat front end |""",
"""| Front ends | `frontend`: `run(session, ...)`; selected by setting `frontend` or `.opts$frontend` [IC-69] | `console` REPL, `jsonl` event sink; `knit_print` | factory | an RPC server or Shiny chat front end |"""),
("""                                       "provides": {"tool": ["trial_search"]},
                                       "declarations": {"trial_search": {"signature": "trial_search(condition)"}}}}""",
"""                                       "provides": {"tool": ["trials/search"]},
                                       "declarations": {"trials/search": {"signature": "search(condition)"}}}}"""),
("""A layer (orchestrator, review panel, workflow engine, domain agent) needs only exported verbs and the
constructors: `gptr(.run = FALSE)`, `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`,
`gptr_on()`, `gptr_fork()`, `gptr_parallel()`, `gptr_map()`, `gptr_usage()`, plus `ctx$decide()` (System 1
inside plugins), `ctx$execute_tool()` (nested calls through the same gate), `ctx$send()` (steering),
`ctx$state()` (per-session plugin state) and `ctx$emit()` (inter-plugin bus).""",
"""A layer (orchestrator, review panel, workflow engine, domain agent) needs only exported verbs and the
constructors: `gptr(.run = FALSE)`, `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`,
`gptr_on()`, `gptr_fork()`, `gptr_parallel()`, `gptr_usage()`, plus `ctx$decide()` (System 1 inside plugins),
`ctx$execute_tool()` (nested calls through the same gate), `ctx$send()` (notes to the session, delivered as data
[IC-55]), `ctx$set_model()`, `ctx$add_tools()`, `ctx$tokens()`, `ctx$eval()`, `ctx$describe()` [IC-69],
`ctx$state()` (per-session plugin state) and `ctx$emit()` (inter-plugin bus); per-call options arrive as
`.opts = list(<namespace> = list(...))` [IC-44]. Package code uses strings for identifiers (`model = "jev"`) and
`gptr::gptr_agent()`, so it passes R CMD check's global-variable analysis; bare identifiers are for scripts and the
console [IC-42]."""),
("""  ok = gptr::gptr("Do these reviews agree that the analysis is sound?", res$text,
                  model = jev)                             # System 1 judge""",
"""  ok = gptr::gptr("Do these reviews agree that the analysis is sound?", res$text,
                  model = "jev")                           # System 1 judge (a string in package code)"""),
("""- Deprecation: an internal `gptr_deprecated()` warns once per session (class `gptr_deprecated`;""",
"""- Deprecation: an internal `gptr_deprecated()` warns once per session (class `gptr_warning_deprecated`;"""),
("""- `artifact_type`, `frontend`, `interpreter`, `checkpointer` and plugin-defined kinds are marked experimental
  in API 1.0.""",
"""- `artifact_type`, `frontend`, `interpreter`, `checkpointer`, `route`, `service`, `renderer`, `search_source`,
  `store`, `evaluator` and plugin-defined kinds are marked experimental in API 1.0.
- `gptr_check(x, tokens = TRUE)` reports a plugin's declaration cost and the printed cost of its members on their
  examples; truncation policies and catalog formatters are v1.x kinds [IC-69]. Pi's `context` message transform
  is not ported (the transcript is append-only); `compactor`, `context_block` and `request_params` are the
  supported alternatives."""),
]
apply(P, pairs)
