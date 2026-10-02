from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""wins and the difference is listed in §13 (and `03`/`05` were edited to agree). All code uses `=` for assignment
and `|>` for pipes (S-9); untrusted text is never a cli/glue format string (rule C1).""",
"""wins and the difference is listed in §13 (and `03`/`05` were edited to agree). The review amendments of §15
(IC-32..IC-73, 2026-09-30; issue-by-issue record in `06-review-resolution.md`) win over every earlier section of
this document; the sections they touch were edited in place. All code uses `=` for assignment and `|>` for pipes
(S-9); untrusted text is never a cli/glue format string (rule C1)."""),
("""| IC-31 | The classifier's parse walk `code_targets()` is P11's;""",
"""| IC-32..IC-73 | Review amendments (load order, layering allowlist, services, replay, safety kernel, store, processes, RNG, encoding, CLI routes, budgets, prompt composition, extension-API additions, release). | §15; `06-review-resolution.md`. |
| IC-31 | The classifier's parse walk `code_targets()` is P11's;"""),
# errors
("""| `noninteractive` | - | `what` | `gptr()` (P08), `gptr_init()` (P08), `gptr_login()` (P18) | needs a human and none is present |""",
"""| `noninteractive` | - | `what`, `questions` | `gptr()` (P08), `gptr_init()` (P08), `gptr_login()` (P18), the `ask` tool in a non-interactive `manual` run (P11; status `blocked`) | needs a human and none is present (`gptr_can_prompt()` FALSE) |"""),
("""| `network` | `provider` | + `curl_code` | P04 | connection failures after retries |""",
"""| `network` | `provider` | + `curl_code` | P04 | connection failures after retries |
| `redirect` | `provider` | + `location_origin` | P04 | a 3xx response (redirects are never followed, IC-64) |
| `billing` | `provider` | + `source` | P20 | the claude CLI reports an `apiKeySource` other than `"none"` on the plan route (IC-65) |"""),
("""| `not_in_run` | - | - | `gptr_return()` (P08) | called outside an active run |
""", ""),
("""| `stale_block` | `not_recorded` | `document`, `block` | P15 | `replay` mode and the block's prompt changed |""",
"""| `stale_block` | `not_recorded` | `document`, `block` | P15 | `replay` mode and the block's prompt or interpolated values changed |
| `replay_unbound` | `not_recorded` | `block`, `child` | P06 (`gptr_resume(block =)`) | no session is bound to that block in this process (IC-46) |
| `secret_found` | - | `findings` (df, no values) | P03 (`gptr_scrub(error = TRUE)`) | persisted files contain a registered secret (IC-70) |"""),
("""| `s1_batch` | `s1` | `n_states` | P13 | a vector of decisions where one was required (hint names `I()`) |
""", ""),
("""`readline_limit` (P14), `plugin` (P02/P17; a plugin was disabled; field `diagnostic`), `cache_break` (P07; only
when `options(gptr.check_prefix = "warn")`).""",
"""`readline_limit` (P14), `plugin` (P02/P17; a plugin was disabled; field `diagnostic`), `cache_break` (P07; only
when `options(gptr.check_prefix = "warn")`), `secret_late` (P03; a newly registered secret already occurs in live
session entries; field `counts`)."""),
("""Messages (`gptr_message_<name>`): `alias_shadowed` (P08), `plan_handoff` (P11), `egress_ack` (P05), `notice`""",
"""Messages (`gptr_message_<name>`): `alias_shadowed` (P08), `plan_handoff` (P11), `egress_ack` (P08, IC-71), `s1_split` (P13; once per
session when a data frame is split into several states, naming `I(x)`), `notice`"""),
# options
("""| `gptr.interactive` | `lgl(1) \\| NULL` | `NULL` | P01 | force the human-present decision (`gptr_has_human()`) |""",
"""| `gptr.interactive` | `lgl(1) \\| NULL` | `NULL` | P01 | force the human-present decisions (`gptr_has_human()` and `gptr_can_prompt()`, IC-43) |
| `gptr.project_root` | `chr(1) \\| NULL` | `NULL` | P01 | overrides `project_root()` (also `GPTR_PROJECT_ROOT`; tests set it, IC-63) |
| `gptr.unsafe_no_permissions` | `lgl(1)` | `FALSE` | P06 | set outside a run only: no permission gate (sandboxed CI); snapshotted at run start (IC-53) |"""),
("""| `gptr.record` | `chr(1) \\| NULL` | settings (`"ask"`) | P15 | `"auto"`, `"ask"`, `"off"`: may gptr write into documents |""",
"""| `gptr.record` | `chr(1) \\| NULL` | settings (`"ask"`) | P15 | `"auto"`, `"ask"`, `"off"`: may gptr write into documents (write consent, IC-45) |"""),
("""| `gptr.max_active` | `int(1)` | `8L` | P04 | concurrent HTTP transfers (global) |
| `gptr.max_active_cli` | `int(1)` | `4L` | P19 | concurrent CLI sub-agents |
| `gptr.max_workers` | `int(1) \\| NULL` | `NULL` | P19 | `NULL` = `min(4, cores - 1)`, and 2 whenever `_R_CHECK_PACKAGE_NAME_` is set |
| `gptr.max_tasks` | `int(1)` | `8L` | P19 | children per team/fan-out call |
| `gptr.max_depth` | `int(1)` | `1L` | P08 | nesting depth of child sessions (at most 2) |""",
"""| `gptr.max_active` | `int(1)` | `8L` | P04 | concurrent HTTP transfers (global); nothing else |
| `gptr.subagents.max_active` | `int(1)` | `8L` | P19 | concurrent inline children; default of `gptr_parallel(max_active =)` (IC-71) |
| `gptr.subagents.max_cli` | `int(1)` | `4L` | P19 | concurrent CLI sub-agents |
| `gptr.subagents.max_workers` | `int(1) \\| NULL` | `NULL` | P19 | `NULL` = `min(4, cores - 1)`; every child pool is capped at 2 whenever `check_running()` (IC-60) |
| `gptr.subagents.max_tasks` | `int(1)` | `8L` | P19 | children per team/fan-out call made from model code (depth >= 1, IC-39) |
| `gptr.subagents.max_depth` | `int(1)` | `1L` | P08 | nesting depth of child sessions (at most 2) |
| `gptr.max_nested_calls` | `int(1)` | `20L` | P06 | `gptr()` calls per `r` evaluation (IC-66) |"""),
("""| `gptr.wire_log` | `lgl(1) \\| chr(1)` | `FALSE` | P04 | `TRUE` = `<workspace root>/cache/tmp/wire.jsonl`; a path must be inside the workspace root or `tempdir()` |
| `gptr.supervise` | `lgl(1) \\| NULL` | `NULL` | P04 | callr/processx `supervise`; `NULL` = `interactive() && !check_running()` |""",
"""| `gptr.wire_log` | `lgl(1) \\| chr(1)` | `FALSE` | P04 | `TRUE` = `<workspace root>/cache/tmp/wire-<session id>.jsonl` (one file per session, IC-65); a path must be inside the workspace root or `tempdir()`; each line is written open-append-close |
| `gptr.supervise` | `lgl(1) \\| NULL` | `NULL` | P04 | callr/processx `supervise`, resolved by `supervise_default()`: `NULL` = `!check_running()` (IC-60) |
| `gptr.stdin_timeout` | `num(1)` | `60` | P04 | seconds to drain a pending stdin write to a child (IC-60) |
| `gptr.cli_path` | named list \\| `NULL` | `NULL` | P20 | explicit `claude`/`codex` paths (tests point them at the fake CLI, IC-65) |
| `gptr.cli_turn_timeout` | `num(1)` | `3600` | P20 | wall-clock seconds per CLI turn (IC-65) |"""),
("""| `gptr.r_output_tokens` | `int(1)` | `4000L` | P09 | `r` result budget (estimated tokens) |""",
"""| `gptr.r_output_tokens` | `int(1)` | `4000L` | P09 | `r` result budget (estimated tokens, images included) |
| `gptr.r_max_images` | `int(1)` | `3L` | P09 | plot images attached per `r` result (IC-67) |"""),
("""| `gptr.s1_state_max` | `int(1)` | `2000L` | P13 | characters of `as_state(<session>)` |""",
"""| `gptr.s1_state_max` | `int(1)` | `2000L` | P13 | characters of `as_state(<session>)` |
| `gptr.s1_max_elements` | `int(1)` | `10000L` | P13 | elements per System 1 call (IC-66) |"""),
("""| `gptr.mcp_probe_timeout` | `num(1)` | `5` | P18 | seconds for the era probe |""",
"""| `gptr.mcp_probe_timeout` | `num(1)` | `5` | P18 | seconds for the era probe |
| `gptr.mcp_debug` | `lgl(1)` | `FALSE` | P18 | keep redacted MCP server logs in the user cache instead of `tempdir()` (IC-70) |"""),
("""| `gptr.out_keep` | `int(1)` | `20L` | P01 | results kept in the `gptr$out()` store |""",
"""| `gptr.out_keep` | `int(1)` | `20L` | P01 | results kept per session in the `gptr$out()` store (IC-71) |"""),
]
apply(P, pairs)
