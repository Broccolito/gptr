from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""Same `(kind, name)`: the lowest rank wins; ties: the first registered, with a `collision` diagnostic.
`all`-resolving kinds keep every record, ordered by the kind's order field when it has one, else by rank then
registration. A *replaceable* built-in extension is disabled entirely when any capability it provides is
overridden by an enabled record of lower rank (Pi semantics [G1 §3.6]).""",
"""Same `(kind, name)`: the lowest rank wins; ties: the first registered, with a `collision` diagnostic.
`all`-resolving kinds keep every record, ordered by the kind's order field when it has one, else by rank then
registration. A lower-rank record shadows **only** the record with the same `(kind, name)`; a whole built-in is
disabled only by an explicit `-builtin:<name>` filter (Pi merges per tool, `agent-session.ts:3478-3481`; IC-69).
Rank-0 records passed as call arguments (`tools =`, `extensions =`, `plugins =`, `model = <spec>`) are scoped to
their session and removed with it."""),
("""disable `policy` or `hook` records of the user or of built-ins, and never disable `builtin:permissions`,
`builtin:secrets` or `builtin:plan`.""",
"""disable `policy` or `hook` records of the user or of built-ins; filters from **no** source (project, user,
call, `gptr_config()`) disable `builtin:permissions`, `builtin:plan`, the `critical_guard` and `secret_guard`
policies or `builtin:secrets`, and inside a run filters that would remove `policy` or `hook` records are refused
(IC-53)."""),
("""`resolve`: `first` (one winning record per name) or `all`. "Order" is the field that orders `all` kinds.""",
"""`resolve`: `first` (one winning record per name) or `all`. "Order" is the field that orders `all` kinds. Rows
32-38 were added by IC-69 and IC-34 (38 kinds in all; P02 defines 37, P22 adds `interpreter`)."""),
("""`headers` named list of non-secret strings, `discover` `function()` -> df\\|NULL, `status` `function()` -> named list\\|NULL, `aliases` chr, `local` lgl(1) (loopback server: unknown model ids allowed, no egress acknowledgement), `offline` lgl(1) (no model is called: exempt from `replay_guard()`; only fakes) | data; `auth` is evaluated per request (INFRA-22); `discover` runs only on request | P02 |""",
"""`headers` named list of non-secret strings, `discover` `function()` -> df\\|NULL, `status` `function()` -> named list\\|NULL (reads cached data only unless `check = TRUE`), `aliases` chr, `local` lgl(1) (loopback server: unknown model ids allowed, no egress acknowledgement), `offline` lgl(1) (no remote model is called: exempt from `replay_guard()`; the fake provider and the mock-server and fake-CLI test providers, IC-45), `rate` `list(requests_per_s, tokens_per_s)`\\|NULL (static limits feeding the token bucket, IC-64) | data; `auth` is evaluated per request (INFRA-22); `discover` runs only on request | P02 |"""),
("""| 4 | `router` | first | `route` `function(request, ctx)` -> chr(1) model ref; `description` | usable as `model = <name>`; `request` = `list(prompt, labels, mode, session)`; budget 50 ms (a slower router gets a diagnostic); an error or a non-registered result falls back to the default model with a diagnostic and a `route` event; System 1 only through `ctx$decide()` | P02 |""",
"""| 4 | `router` | first | `route` `function(request, ctx)` -> chr(1) model ref or `list(model, thinking = NULL, state = NULL)`; `description`; `timeout` num(1) (default 2 s) | usable as `model = <name>`; called by P06 before every request and at compaction (IC-69); `request` = `list(prompt, messages (projected, read-only), state, previous, reason = "turn" \\| "compaction" \\| "direct", session)`; a timeout, an error or a non-registered result falls back to the default model with a diagnostic and a `route` event; System 1 through `ctx$decide()`; each switch appends `model_change` and a `gptr.router` state entry | P02 |"""),
("""| 13 | `context_block` | all / `order` (int, default 650) | `provide` `function(ctx, budget)` -> `NULL`, chr(1) or `list(text, attrs)`; `placement` (`first`, `turn`); `authority` (`data`, `operator`); `budget` int(1); `order` | `ctx$input` gives `list(call, turn, prompt, placement)`;""",
"""| 13 | `context_block` | all / `order` (int, default 650) | `provide` `function(ctx, budget)` -> `NULL`, chr(1) or `list(text, attrs)`; `placement` (`first`, `turn`, `both`; IC-38); `authority` (`data`, `operator`: rank >= 3 only, IC-52); `budget` int(1); `order` | `ctx$input` gives `list(call, turn, prompt, placement, last_hash, opts)`; a turn block equal to its last emitted text is skipped;"""),
("""| 14 | `prompt_section` | all / `order` | `text` chr(1) or `function(ctx)` -> chr(1)\\|NULL (`NULL` omits); `tier` (`T0`, `T1`); `order` int(1); `budget` int(1) | rendered once at freeze; `ctx$input` gives `list(preset, tool_names, human, document, s1_alias, model, root)`; must be stable for the session; an error omits it with a diagnostic | P02 |""",
"""| 14 | `prompt_section` | all / `order` | `text` chr(1) or `function(ctx)` -> chr(1)\\|NULL (`NULL` omits); `tier` (`T0`, `T1`); `order` int(1); `budget` int(1); `parent` chr(1)\\|NULL (a fragment rendered inside the named section at its `{{fragments}}` marker, IC-68) | rendered once at freeze; `ctx$input` gives `list(preset (the preset record), tool_names, human, document, s1_alias, model, root, trusted)`; must be stable for the session; an error omits it with a diagnostic | P02 |"""),
("""| 28 | `child_env` | first (name = profile) | `base` (`inherit`, `allowlist`), `keep` chr, `drop` chr (regex), `set` named chr (values may be handles), `billing` named list | used by `child_env()` | P02 |""",
"""| 28 | `child_env` | first (name = profile) | `base` (`inherit`, `allowlist`), `keep` chr, `drop` chr (regex), `set` named chr (values may be handles), `billing` named list | used by `child_env()`; every profile gets the empty `R_ENVIRON_USER`/`R_PROFILE_USER` files (IC-60) | P02 |"""),
("""| 31 | `route` [experimental] (IC-02) | all / `order` (num) | `order`; `match` `function(call)` -> lgl(1); `run` `function(call)` -> value or `route_pass()`; `description` | §6.1.1 step 5; an error in `match` skips the route with a diagnostic; an error in `run` propagates to the caller | P02 |""",
"""| 31 | `route` [experimental] (IC-02) | all / `order` (num) | `order`; `match` `function(call)` -> lgl(1); `run` `function(call)` -> value or `route_pass()`; `description` | §6.1.1 step 5; an error in `match` skips the route with a diagnostic; an error in `run` propagates to the caller | P02 |
| 32 | `preset` | first | `tools` chr or `function(human, model, mode)` -> chr; `sections` named lgl or `function(name)` -> lgl; `preamble` (`"standard"`, `"short"`) | `builtin:prompt` registers `minimal`, `standard`, `readonly`, `extended`; section predicates read the preset record, never its name (IC-69) | P02 |
| 33 | `risk_rule` | all | the columns of `risk-functions.csv` (§11.15) as a data frame, or `kind = "command"` rows | rows are concatenated with the shipped tables; on a duplicate the highest level wins; user and plugin rows may lower a level only explicitly (`lower = TRUE`) | P02 |
| 34 | `service` [experimental] (IC-34) | first (name = service name) | `fun` | replaces the bootstrap service of the same name at a lower rank; owned by its source, so filtering the source removes it | P02 |
| 35 | `renderer` [experimental] | first (name = custom entry type) | `render` `function(entry, width, ctx)` -> chr; `doc` `function(entry, format)` -> chr lines | used by the console and the document writers for custom entries appended with `ctx$append_entry()` | P02 |
| 36 | `search_source` [experimental] | all | `docs` `function(ctx)` -> df(`id`, `text`, `kind`) | indexed by `gptr$search()` (BM25) | P02 |
| 37 | `store` [experimental] | first (selected by setting `store`, default `jsonl`) | `open`, `append`, `read`, `fork` functions with the `session-store.R` contracts of §7.6 | the built-in is the append-only JSONL store; a failing store stops the run with `gptr_error_internal` | P02 |
| 38 | `evaluator` [experimental] | first (selected by setting `evaluator`, default `r`) | `eval` with the `eval_r()` contract of §7.9 (returns a `gptr_eval_result`) | used by the `r` tool, `ctx$eval()` and the MCP server's `r`; copy-safety obligations [R1]-[R8] apply | P02 |"""),
("""| `builtin:prompt` | `prompt-sections.R` (P07) | the §9.3 sections it owns, the gap `cache_policy`, the default `estimator` | yes |""",
"""| `builtin:prompt` | `prompt-sections.R` (P07) | the §9.3 sections it owns, the four `preset` records, the gap `cache_policy`, the default `estimator`, the `session.add_tools` service | yes |"""),
("""| `builtin:tools`, `builtin:r` | `tool-namespace.R`, `tool-r.R` (P10) | direct tools `read`, `edit`, `write`, `grep`/`find`/`ls` (extended), `r`; members of §9.4 owned by P10; section `plugins` | yes |""",
"""| `builtin:tools`, `builtin:r` | `tool-namespace.R`, `tool-r.R` (P10) | one spec each for `read`, `edit`, `write`, `grep`, `find`, `ls` (direct and member forms, IC-37), `r`; the other members of §9.4 owned by P10 (incl. `out`); tool guidelines; `r_session` fragments; section `plugins`; `search_source` for members | yes |"""),
("""| `builtin:system1` | `s1-client.R` (P13) | provider `typesafe`, adapters, route `classifier` | yes |
| `builtin:console`, `builtin:jsonl` | `console-repl.R`, `console-jsonl.R` (P14) | frontends, route `console`, renderer hooks, commands | yes |
| `builtin:documents` | `doc-formats.R` (P15) | doc formats, route `document`, hooks | yes |""",
"""| `builtin:system1` | `s1-client.R` (P13) | provider `typesafe`, adapters, route `classifier`, section `system1` | yes |
| `builtin:console`, `builtin:jsonl` | `console-repl.R`, `console-jsonl.R` (P14) | frontends, route `console`, renderer hooks, commands | yes |
| `builtin:documents` | `doc-formats.R` (P15) | doc formats, route `document`, hooks, section `documents`, services `doc.*` | yes |"""),
("""| `builtin:subagents` | `subagent-backends.R` (P19) | backends, routes `team`, `fanout` | yes |""",
"""| `builtin:subagents` | `subagent-backends.R` (P19) | backends, routes `team`, `fanout`, the sub-agent `r_session` fragment | yes |"""),
("""| `builtin:bridges`, `builtin:lang` | `bridge-sh.R`, `bridge-lang.R` (P22) | kind `interpreter`, interpreters, members | yes |
| `builtin:artifacts` | `artifact-app.R` (P23) | artifact types, member `app`, checkpointer | yes |""",
"""| `builtin:bridges`, `builtin:lang` | `bridge-sh.R`, `bridge-lang.R` (P22) | kind `interpreter`, interpreters, members, `r_session` fragments | yes |
| `builtin:artifacts` | `artifact-app.R` (P23) | artifact types, member `app`, section `artifacts`, checkpointer | yes |"""),
("""Every factory calls only the API object, `ctx`, L0 helpers, its own area and the declared services (§2.2 rule 3 of
`03`); `test-arch-layers.R` enforces it.""",
"""Every factory calls only the API object, `ctx`, L0 helpers, its own area, the declared services and the kernel
SDK of IC-33 (§2.2 rule 3 of `03`); `test-arch-layers.R` enforces it."""),
("""| `project_trust` | pi | first decision | `cwd` | `list(decision = "yes" \\| "no", remember = lgl(1))` | P08 (first use of untrusted project resources) |""",
"""| `project_trust` | pi | first decision | `cwd`, `changed` (files whose trust fingerprint changed, IC-52) | `list(decision = "yes" \\| "no", remember = lgl(1))` | P08 (first use of untrusted project resources; `gptr_trust()` itself emits nothing) |"""),
("""| `input` | pi | transform chain | `text`, `source` (`prompt`, `pipe`, `repl`, `passthrough`, `steer`) | `list(action = "continue" \\| "transform" \\| "handled", text)` | P08, P14 |""",
"""| `input` | pi | transform chain | `text`, `source` (`prompt`, `pipe`, `repl`, `passthrough`, `steer`; `steer` = pause-menu input) | `list(action = "continue" \\| "transform" \\| "handled", text)` | P08, P14 |"""),
("""| `before_request` | gptr | notify, read-only | `provider`, `model`, `request_id`, `view`, `tokens_est` | - (a handler that changes the frozen prefix triggers `cache_break`) | P06 |""",
"""| `before_request` | gptr | notify, read-only | `provider`, `model`, `request_id`, `view`, `tokens_est` | - (a handler that changes the frozen prefix triggers `cache_break`) | P06 |
| `request_params` | gptr | patch chain | `provider`, `model`, `params` (only the adapter's `capabilities$request_params` fields, e.g. `service_tier`, `metadata`, `user`) | `list(params)`; patches to other fields are ignored with a diagnostic (IC-69) | P06 |"""),
("""| `route`, `model_select` | gptr, pi | notify | `route`, `router`, `model`; `from`, `to`, `reason` | - | P08, P06 |""",
"""| `route`, `model_select` | gptr, pi | notify | `route`, `router`, `model`, `reason`; `from`, `to`, `reason` | - | P08, P06 (router switches, IC-69) |"""),
("""Not ported from Pi (no equivalent in an append-only, R-console harness, or superseded): `context`,""",
"""Not ported from Pi (no equivalent in an append-only, R-console harness, or superseded; plugin authors use
`compactor`, `context_block` and `request_params` instead, IC-69): `context`,"""),
("""| `ctx$execute_tool(name, input)` | the tool's result value (a nested call through the same gate, `dispatch_nested()`) | P06 |
| `ctx$send(text, as = c("steer", "follow_up"))` | `invisible(NULL)`; `gptr_steer()` on the session | P06 |""",
"""| `ctx$execute_tool(name, input)` | the tool's result value (a nested call through the same gate, `dispatch_nested()`) | P06 |
| `ctx$send(text, as = c("steer", "follow_up"))` | `invisible(NULL)`; enqueues with `source = "extension"` (user-role data, never an operator relay; refused from model code, IC-55) | P06 |
| `ctx$set_model(ref, thinking = NULL, reason = "plugin")` | `invisible(NULL)`; a `model_change` at the next request boundary (one cache miss) | P06 (IC-69) |
| `ctx$add_tools(specs)` | `invisible(NULL)`; `session_add_tools()` | P07 (IC-69) |
| `ctx$tokens(x, class = "prose")` | num(1): the `estimator` kind's estimate | P01 (IC-69) |
| `ctx$eval(code, envir = NULL)` | a `gptr_eval_result` through the `evaluator` kind (plugin code; not gated) | `eval.r` (P09, IC-69) |
| `ctx$describe(x, budget = 150L)` | chr: `gptr_describe()` within the budget | `describe` (P09) |"""),
("""`ctx` is created once per session (`ctx_new()`), never per dispatch; members are closures; `$<-` refuses assignment.""",
"""`ctx` is created once per session (`ctx_new()`), never per dispatch; members are closures that fetch their service
at call time (`ctx.kernel`, `ctx.input`, ...; IC-34); `$<-` refuses assignment."""),
]
apply(P, pairs)
