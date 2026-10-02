from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""function and every cross-plan interface; this document fixes names, signatures, structures and mechanisms.
Where the two differ, the contract wins; its §13 lists the reconciliation edits made to this document.""",
"""function and every cross-plan interface; this document fixes names, signatures, structures and mechanisms.
Where the two differ, the contract wins; its §13 lists the reconciliation edits made to this document. The review
round of 2026-09-30 (144 issues; `06-review-resolution.md`) is integrated here; its normative detail is the
contract's §15 (IC-32..IC-73), cited below as [IC-nn]. Signature blocks in this document are indicative; the
contract's signatures govern."""),
("""| P9 | **Consent before disk and network; trust before code** (REQ-02) | `.gptr/` only by `gptr_init()` or an interactive yes; writes only there, in `R_user_dir()` or `tempdir()`; first-use egress acknowledgement per provider; project-supplied executable configuration only after `gptr_trust()`. |
| P10 | **Fail closed** | A throwing policy denies; `tool_call`, `permission_request` and `document_write` hooks fail closed; an `ask` without a human stops the run with a classed error; untrusted text is never a format string. |""",
"""| P9 | **Consent before disk and network; trust before code** (REQ-02) | `.gptr/` only by `gptr_init()` or an interactive yes; writes only there, in `R_user_dir()`, in `tempdir()`, in documents the user named or confirmed, and through tool writes the permission mode approved; first-use egress acknowledgement per provider; project-supplied executable configuration and project instructions with command authority only after `gptr_trust()` [IC-52]. |
| P10 | **Fail closed** | A throwing policy denies; with no mode policy the gate asks; `tool_call`, `permission_request` and `document_write` hooks fail closed; an `ask` without a human stops the run with a classed error; model code cannot disable or reconfigure the permission kernel [IC-53]; untrusted text is never a format string. |"""),
("""| Agents | Inline, worker (callr) and CLI sub-agent backends; teams (`agents =`), fan-out (`parallel =`), `gptr_parallel()`, `gptr_map()` |""",
"""| Agents | Inline, worker (callr) and CLI sub-agent backends; teams (`agents =`), fan-out (`parallel =`), `gptr_parallel()` |"""),
("""| L1 (`provider`, `catalog`, `s1-types`, `cli-*` adapters) | L0 | INFRA-02 events via the `emit` callback |""",
"""| L1 (`provider`, `catalog`, `s1-types`, `cli-*` adapters) | L0 | INFRA-02 events via the `emit` callback; the run's gate, MCP dispatcher and tool-result builder arrive as injected `opts` callbacks [IC-33] |"""),
("""| L4 (built-in plugins: `tool`, `bridge`, `perm`, `ckpt`, `skill`, `mcp`, `subagent`, `s1`, `doc`, `artifact`, `eval`, `env`) | the extension API (`gptr$register()`, `ctx`), L0, their own area, and the declared services `eval-*`, `env-*`, `tool-walk`, `proc-*` | tool results, events, spec contracts |
| L5 (`console`) | SDK verbs, extension API (`ui`, `frontend` kinds), L0 | printed output (the only printing layer) |
| L6 (`gptr-*`) | L0-L3, registry lookups by kind (never an L4 function by name) | return values |""",
"""| L4 (built-in plugins: `tool`, `bridge`, `perm`, `ckpt`, `skill`, `mcp`, `subagent`, `s1`, `doc`, `artifact`, `eval`, `env`) | the extension API (`gptr$register()`, `ctx`), L0, their own area, the declared services `eval-*`, `env-*`, `tool-walk`, `proc-*`, the §7.0 service table of the contract, and the **kernel SDK** allowlist [IC-33] | tool results, events, spec contracts |
| L5 (`console`) | SDK verbs, extension API (`ui`, `frontend` kinds), the kernel SDK, L0 | printed output (the only printing layer) |
| L6 (`gptr-*`) | L0-L3, registry lookups by kind (never an L4 function by name), the kernel SDK | return values |

The **kernel SDK** is a function-level allowlist of session, run, dispatch and gateway functions (`session_data()`,
`session_append()`, `run_current()`, `run_eval_env()`, `dispatch_nested()`, `perm_check()`, `call_value()`,
`gateway_run()`, `replay_mode()`, `setting_get()`, `eval_r()`, ...; the full list is IC-33) that L4 and L5 code may
call directly; L0 and L3 files reach trust only through the `trust.get` service."""),
("""   (`registry_get("tool", "r")`, `registry_all("policy")`, `registry_route("classifier")`). This is what""",
"""   (`registry_get("tool", "r")`, `registry_all("policy")`, `registry_all("route")`). This is what"""),
("""   declared services. It is declared with `on_load(ext_declare_builtin("<name>", builtin_<name>))`, so later
   plans add built-ins in their own files without touching a shared list.""",
"""   declared services. It is declared with `on_load(ext_declare_builtin("<name>", builtin_<name>))`, so later
   plans add built-ins in their own files without touching a shared list. `on_load()` and the service table live
   in `R/aaa-state.R`, which collates first, because R evaluates top-level package code at install time in
   collation order [IC-32]."""),
("""4. **Enforcement.** `tests/testthat/test-arch-layers.R` walks every namespace function with
   `codetools::findGlobals()` (codetools in Suggests; skipped without it), maps each internal callee to its
   file's layer (the layer column of §3.2), and fails when a call crosses a boundary not allowed by the table in
   `helper-arch.R` [P-B §2.4]. `builtin_*` factories are checked against rule 3.""",
"""4. **Enforcement.** `tests/testthat/test-arch-layers.R` walks every namespace function with
   `codetools::findGlobals()` (codetools in Suggests; skipped without it), maps each internal callee to its
   file's layer by **parsing the files under `R/`** (installed packages carry no srcrefs; the test skips with a
   message when the sources cannot be found), and fails when a call crosses a boundary not allowed by the table
   and the kernel SDK allowlist in `helper-arch.R` [P-B §2.4; IC-33]. Literal `ext_service_get("<name>")` calls are
   mapped to the providing plan; an undeclared service name fails. `builtin_*` factories are checked against rule 3."""),
("""   children on unload), and weak indexes (live sessions, `gptr_last()`). Usage, queues, abort flags and every
   in-flight cache live in sessions and runs; `gptr_usage()` aggregates [G3 (2)].""",
"""   children on unload), the weak live-session index, the most recent session for `gptr_last()` (held strongly: a
   shell holds no frames or user objects [IC-71]) and the replay-block table [IC-46]. Usage, queues, abort flags,
   the `gptr$out()` store and every in-flight cache live in sessions and runs; `gptr_usage()` aggregates [G3 (2)]."""),
("""**Re-entrancy.** Model-written code in `r` may call `gptr("task", data, model = m)` (a sub-agent) or MCP tools
over HTTP. The nested call re-enters `reactor_pump(until, allow_runs = <the nested run>)` on the same pool: it
advances all transfers but executes queued R tools **only** of the runs in `allow_runs`, so sibling agents'
R tools never run inside another tool's evaluation [J-impl, P-B §6.2, P-C §6.2]. Nested runs are children of
the running session (depth + 1, mode inherited and only tightened, usage rolled up, no document block).""",
"""**Re-entrancy.** Model-written code in `r` may call `gptr("task", data, model = m)` (a sub-agent), System 1 or
MCP tools over HTTP. The nested call re-enters `reactor_pump(until, allow_runs = <the runs it waits for>)` on the
same pool: it advances all transfers but executes queued R tools **only** of the runs in `allow_runs` (which
defaults to none inside a run), so sibling agents' R tools never run inside another tool's evaluation [J-impl,
P-B §6.2, P-C §6.2]. The reactor tracks its depth: `later::run_now(0)` (httpuv servers, background timers) runs
only in the outermost pump, or in a nested pump that waits for a CLI child served by gptr's MCP server, whose
handler then refuses other sessions' requests with a retryable error; the background pump is a no-op while the
reactor is on the stack [IC-57]. Nested runs are children of the running session (depth + 1, mode inherited and
only tightened, usage and budget rolled up to the root, no document block)."""),
("""`R/<area>-<topic>.R`, one topic per file (conventions §3). Final areas, in layer order:""",
"""`R/<area>-<topic>.R`, one topic per file (conventions §3), plus `R/aaa-state.R`, which collates first [IC-32].
Final areas, in layer order:"""),
("""### 3.2 `R/` files (117 files)""", """### 3.2 `R/` files (118 files)"""),
("""| `utils-conditions.R` | L0 | `gptr_abort()/gptr_warn()/gptr_inform()` with the `gptr_error_<class>` scheme; `msg_verbatim()` (safe rendering of untrusted text); condition redaction hook | - | P01 |""",
"""| `aaa-state.R` | L0 | `the`, `on_load()`, `on_unload()`, the bootstrap service table (`ext_service_set/get/has()`), the redaction hook (`redactor_set()`, `redact_hook()`), the internal `%||%`; collates first [IC-32, IC-34] | - | P01 |
| `utils-conditions.R` | L0 | `gptr_abort()/gptr_warn()/gptr_inform()` with the `gptr_error_<class>` scheme; `msg_verbatim()` (safe rendering of untrusted text) | - | P01 |"""),
("""| `utils-hash.R` | L0 | sha256 via `cli::hash_sha256()`, `canonical_json()` (radix key order), RNG-free ids (session, entry, block), sampled fingerprints | - | P01 |
| `utils-encoding.R` | L0 | UTF-8 marking before every parse/serialise, `os_bytes()`, binary-connection text I/O, C-locale guards | - | P01 |
| `utils-options.R` | L0 | documented `gptr.*` option defaults; `gptr_has_human()`, front-end detection, verbosity; mockable `gptr_is_interactive()`, `gptr_readline()`, `gptr_confirm()`; `on_load()` registry; the service table (`ext_service_set/get/has()`) and `setting_get()` (contract IC-09) | - | P01 |
| `utils-paths.R` | L0 | project root, `gptr_user_dir(which)` = `tools::R_user_dir("gptr", which)`, workspace root (`.gptr` or `tempdir()/gptr`), atomic write (temp + `file.rename`), the leaf `save_rds()`/`serialize_leaf()` wrappers that always pass `ascii = FALSE` (R7), path classes, Windows reserved names | - | P01 |
| `utils-text.R` | L0 | head 40% / tail 60% truncation to a token budget, spill files, the `out(id)` store (last 20 results), ANSI/OSC and carriage-return cleanup, 400-char line caps | - | P01 |""",
"""| `utils-hash.R` | L0 | sha256 via `cli::hash_sha256()`, `canonical_json()` (radix key order), RNG-free ids (session, entry, block), sampled fingerprints, `with_seed_preserved()`, `port_candidates()` [IC-61] | - | P01 |
| `utils-encoding.R` | L0 | `as_utf8()` at every ingress [IC-62], UTF-8 marking before every parse/serialise, `os_bytes()`, binary-connection text I/O, C-locale guards | - | P01 |
| `utils-options.R` | L0 | documented `gptr.*` option defaults; `gptr_has_human()`, `gptr_can_prompt()` [IC-43], front-end detection, verbosity, `supervise_default()`; mockable `gptr_is_interactive()`, `gptr_readline()`, `gptr_confirm()`; `setting_get()` (contract IC-09) | - | P01 |
| `utils-paths.R` | L0 | project root (with the `gptr.project_root` override), `gptr_user_dir(which)` = `tools::R_user_dir("gptr", which)`, `user_home()`, `app_config_dir()` [IC-63], `path_key()`, `rscript_path()` [IC-60], workspace root (`.gptr` or `tempdir()/gptr`), atomic write (temp + `file.rename` with retries and an in-place fallback), the leaf `save_rds()`/`serialize_leaf()` wrappers that always pass `ascii = FALSE` (R7), path classes (incl. `control`, `instructions` [IC-54]), Windows reserved names | - | P01 |
| `utils-text.R` | L0 | head 40% / tail 60% truncation to a token budget, spill files, the `out(id)` store (per session, last 20 results each [IC-71]), ANSI/OSC and carriage-return cleanup, 400-char line caps | - | P01 |"""),
("""| `auth-redact.R` | L0 | one redactor with sink profiles; streaming hold-back; `gptr_redact()` | - | P03 |""",
"""| `auth-redact.R` | L0 | one redactor with sink profiles; streaming hold-back; `gptr_redact()`; `gptr_scrub()` [IC-70] | - | P03 |"""),
("""| `auth-childenv.R` | L0 | child-environment profiles (mcp, worker, cli-claude, cli-codex, helper, artifact); empty `R_ENVIRON_USER`/`R_PROFILE_USER` files | - | P03 |
| `proc-spawn.R` | L0 | G5 process engine: `processx::process$new` with file redirection, argv via `os_bytes()`, `.cmd`/`.bat` via `cmd.exe /d /c call` with metacharacter refusal, PowerShell `-EncodedCommand`, `write_all()`, line reader, UTF-8 decode with code-page fallback | - | P04 |
| `proc-supervise.R` | L0 | `kill_all()` (kill_tree, then Windows `taskkill /F /T`, then group kill), grace periods, process tables, orphan sweep | - | P04 |""",
"""| `auth-childenv.R` | L0 | child-environment profiles (mcp, worker, cli-claude, cli-codex, helper, artifact) as complete vectors, `child_env_callr()`; empty `R_ENVIRON_USER`/`R_PROFILE_USER` files for every profile [IC-60] | - | P03 |
| `proc-spawn.R` | L0 | G5 process engine: `processx::process$new` with `encoding = "UTF-8"` and file redirection, argv via `os_bytes()`, `.cmd`/`.bat` via `cmd.exe /d /c call` with metacharacter refusal, PowerShell `-EncodedCommand`, non-blocking `write_all()`, line reader, UTF-8 decode with code-page fallback | - | P04 |
| `proc-supervise.R` | L0 | `kill_all()` (kill_tree, then Windows `taskkill /F /T`, then group kill), grace periods, process tables, tree markers and the orphan sweep, `pid_alive()` (ps) [IC-59], `gptr_jobs()` [IC-36] | - | P04 |"""),
("""| `session-store.R` | L3 | Pi-v3-shaped JSONL tree writer/reader, crash-safe appends, fork files, `gptr_sessions()`, `gptr_resume()` | - | P06 |""",
"""| `session-store.R` | L3 | Pi-v3-shaped JSONL tree writer/reader, open-append-close crash-safe appends with torn-line recovery [IC-59], fork files, `gptr_sessions()`, `gptr_resume()` (incl. `block =`) | - | P06 |"""),
("""| `gptr-gateway.R` | L6 | `gptr()` dispatch and route lookup; routes `nested`, `continue`, `new` and core settings | gateway | P08 |""",
"""| `gptr-gateway.R` | L6 | `gptr()` dispatch and route lookup; the `gptr_gateway` methods `$`, `[[`, `.DollarNames`, `$<-`, `print` (through the `ns.resolve`/`ns.names` services [IC-36]); routes `nested`, `continue`, `new` and core settings | gateway | P08 |"""),
("""| `gptr-sdk.R` | L6 | `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()`, `gptr_prob()` | - | P08 |""",
"""| `gptr-sdk.R` | L6 | `gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()` | - | P08 |"""),
("""| `eval-core.R` | L4 svc | hand-rolled evaluator: parse, capture, per-expression time limit, interrupts, state diff [12 §4.3] | - | P09 |""",
"""| `eval-core.R` | L4 svc | hand-rolled evaluator: parse, capture, per-expression time limit, interrupts, state diff [12 §4.3]; `rng_swap()` [IC-61]; the `evaluator` record `r` | - | P09 |"""),
("""| `tool-namespace.R` | L4 | `gptr$` gateway methods (`$`, `[[`, `.DollarNames`, print), member resolution, generated closures, `gptr$help`, `gptr$search` (BM25), `gptr$describe`, `gptr$plot` | tools | P10 |""",
"""| `tool-namespace.R` | L4 | member resolution (the `ns.resolve`, `ns.names`, `search.sources` services), generated closures, `gptr$help`, `gptr$search` (BM25), `gptr$describe`, `gptr$plot`, `gptr$out`, tool guidelines and `r_session` fragments | tools | P10 |"""),
("""| `s1-types.R` | L1 | `gptr_decision`, `gptr_choice`, `gptr_score` and methods; delayed vctrs methods | - | P13 |""",
"""| `s1-types.R` | L1 | `gptr_decision`, `gptr_choice`, `gptr_score` and methods; delayed vctrs methods; `gptr_prob()` [IC-36] | - | P13 |"""),
("""| `subagent-team.R` | L4 | teams (`agents =`), fan-out (`parallel =`), `gptr_parallel()`, `gptr_map()` | - | P19 |""",
"""| `subagent-team.R` | L4 | teams (`agents =`), fan-out (`parallel =`, through the internal `gptr_map()`), `gptr_parallel()` | - | P19 |"""),
("""| `agent-background.R` | L3 | experimental background runs serviced by `later`; `gptr_jobs()` | - | P21 |
| `bridge-sh.R` | L4 | `gptr$sh/script/bg/jobs/out()`; the `interpreter` kind and built-in interpreters | bridges | P22 |""",
"""| `agent-background.R` | L3 | experimental background runs serviced by `later`; session rows of the job table | - | P21 |
| `bridge-sh.R` | L4 | `gptr$sh/script/bg/jobs()` (`gptr$out()` is P10's); the `interpreter` kind and built-in interpreters | bridges | P22 |"""),
("""inst/extdata/risk-functions.csv              R classifier table: package, function, level, category (P11)""",
"""inst/extdata/risk-functions.csv              R classifier table: package, function, level, category (incl. the
                                             `control` rows of gptr's own exports [IC-53]) and the risky-package
                                             list [IC-54] (P11)"""),
("""inst/gptr/fixtures/fake_cli.R                fake claude/codex CLI for tests and examples (P20)""",
"""inst/gptr/fixtures/fake_cli.R                fake claude/codex CLI for tests and examples, run through
                                             rscript_path() (P20)
inst/gptr/examples/jev-router.R              a tested complexity router factory, loadable with extensions =
                                             [IC-69] (P13)"""),
]
apply(P, pairs)
