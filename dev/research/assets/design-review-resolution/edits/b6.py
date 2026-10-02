from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""Also in `utils-conditions.R` (P01): `condition_redactor_set(fun)` [internal] (P03 installs `redact`),""",
"""Also in P01: `redactor_set(fun)` [internal] (`aaa-state.R`; P03 installs `redact`; it replaces the earlier
`condition_redactor_set()`, IC-34),"""),
("""| `registry_get(kind, name, session = NULL)` | the winning **spec** for `(kind, name)` (lowest rank among enabled records; ties: first registered, with a `collision` diagnostic), after filters, including the session's rank-0 records; `NULL` if none. Lazy records trigger `ext_activate()` of their source first |
| `registry_all(kind, session = NULL)` | list of specs of an `all`-resolving kind (hook, policy, context_block, prompt_section, route, checkpointer, secret_source, redaction_rule, env_alias, child_env) ordered""",
"""| `registry_get(kind, name, session = NULL)` | the winning **spec** for `(kind, name)` (lowest rank among enabled records; ties: first registered, with a `collision` diagnostic), after filters, including the session's rank-0 records; `NULL` if none. A lower-rank record shadows only the record with the same `(kind, name)` (IC-69). Lazy records trigger `ext_activate()` of their source first |
| `registry_all(kind, session = NULL)` | list of specs of an `all`-resolving kind (hook, policy, context_block, prompt_section, route, checkpointer, secret_source, redaction_rule, env_alias, risk_rule) ordered"""),
("""| `registry_filters_set(filters, scope = c("session", "user", "project"))` | applies `-builtin:<name>`, `-plugin:<pkg>`, `-<kind>:<name>`, `+...`; project filters that would disable user or built-in `policy`/`hook` records are ignored with a diagnostic |""",
"""| `registry_filters_set(filters, scope = c("session", "user", "project"))` | applies `-builtin:<name>`, `-plugin:<pkg>`, `-<kind>:<name>`, `+...`; project filters that would disable user or built-in `policy`/`hook` records are ignored with a diagnostic; no filter from any source disables `builtin:permissions`, `builtin:plan`, `critical_guard` or `secret_guard`, and inside a run filters that remove `policy`/`hook` records are refused (IC-53) |"""),
("""**`ext-load.R`**: `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE)` -> `lgl(1)`:
stages every registration of the factory and commits only when it returns;""",
"""**`ext-load.R`**: `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)` ->
`lgl(1)`: with `session` (a session id) every staged record is scoped to that session and removed at its
`session_shutdown` or finalizer (IC-69); stages every registration of the factory and commits only when it returns;"""),
("""**`ext-builtins.R`**: `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (records a
built-in in `the$builtins`; called from `on_load()` expressions in the declaring files),""",
"""**`ext-builtins.R`**: `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (records a
built-in in `the$builtins`; called from `on_load()` expressions in the declaring files; `replaceable` now only
decides whether a `-builtin:<name>` filter may disable it, since overrides are per record, IC-69),"""),
("""| `child_env(profile, pass = character(), set = character(), provider = NULL)` | `auth-childenv.R` | named chr for processx/callr `env`; removed names are `NA` (callr semantics); `profile` in `mcp`, `worker`, `cli-claude`, `cli-codex`, `helper`, `artifact` or a registered `child_env` spec name; `worker` and `artifact` set `R_ENVIRON_USER`/`R_PROFILE_USER` to empty files | P04, P18, P19, P20, P22, P23 |""",
"""| `child_env(profile, pass = character(), set = character(), provider = NULL)` | `auth-childenv.R` | the **complete** named chr for processx `env` (removed names absent; processx rejects `NA`); `profile` in `mcp`, `worker`, `cli-claude`, `cli-codex`, `helper`, `artifact` or a registered `child_env` spec name; **every** profile sets `R_ENVIRON_USER`/`R_PROFILE_USER` to empty files and drops `R_ENVIRON` unless passed (IC-60); the CLI profiles follow G6 §3.7 verbatim (IC-65) | P04, P18, P19, P20, P22, P23 |
| `child_env_callr(env)` | `auth-childenv.R` | the callr form of a `child_env()` result: every variable of `Sys.getenv()` absent from `env` added as `NA` | P19, P23 |"""),
("""| `builtin_secrets(gptr)` | `auth-secrets.R` | registers `secret_source`, `redaction_rule`, `env_alias`, `child_env` specs | P02 load |""",
"""| `builtin_secrets(gptr)` | `auth-secrets.R` | registers `secret_source`, `redaction_rule`, `env_alias`, `child_env` specs | P02 load |
| `gptr_scrub()` | `auth-redact.R` | §6.6 (IC-70); `secret_register()` also scans live sessions' in-memory entries for a new value and warns `secret_late` with counts | users, P24 |"""),
("""| `proc_spawn(command, args = character(), env = NULL, wd = NULL, stdin = NULL, stdout = "\\|", stderr = "\\|", cleanup_tree = TRUE, supervise = gptr_opt("supervise"))` | a `processx::process`; `command` resolved with `Sys.which()`;""",
"""| `proc_spawn(command, args = character(), env = NULL, wd = NULL, stdin = NULL, stdout = "\\|", stderr = "\\|", cleanup_tree = TRUE, supervise = supervise_default())` | a `processx::process` created with `encoding = "UTF-8"` (IC-60) and a tree marker under `R_user_dir("gptr", "cache")/procs/` for the orphan sweep; `command` resolved with `Sys.which()` (R itself only through `rscript_path()`);"""),
("""| `write_all(p, data)` | writes chr or raw completely to the child's stdin (loops `write_input()`, which truncates above 8 KB) | P18, P19, P20 |""",
"""| `write_all(p, data)` | queues chr (as `charToRaw(as_utf8(x))`) or raw for the child's stdin; the reactor drains the buffer non-blockingly with `write_input()` (which writes at most about 8 KB per call), reading stdout/stderr between attempts, within `gptr.stdin_timeout` (`gptr_error_timeout` otherwise); outside the reactor it loops the same way (IC-60) | P18, P19, P20 |"""),
("""| `job_add(kind, id, name, pid = NA, stop, status = function() "running")` | adds a row to the job table (IC-12); `stop` is a zero-argument function | P18, P19, P20, P21, P22, P23 |
| `job_remove(id)`, `job_list(kind = NULL)` | job table maintenance; `job_list()` returns a df (`id`, `kind`, `name`, `pid`, `status`, `started`) | P21 |""",
"""| `job_add(kind, id, name, pid = NA, stop, status = function() "running")` | adds a row to the job table (IC-12); `stop` is a zero-argument function that also sets `stop_requested`, so a later non-zero exit maps to `stopped`/`aborted`, never `error` (IC-60) | P18, P19, P20, P21, P22, P23 |
| `job_remove(id)`, `job_list(kind = NULL)` | job table maintenance; `job_list()` returns a df (`id`, `kind`, `name`, `pid`, `status`, `started`) | P04 (`gptr_jobs()`), P21 |
| `pid_alive(pid, create_time = NULL)` | `lgl(1)`: `ps::ps_is_running(ps::ps_handle(pid))` and, when given, an equal process creation time (pid reuse); never `tools::pskill()` (IC-59) | P06, P15, P23 |
| `gptr_jobs()` | §6.5 (IC-36) | users |"""),
("""**`session-store.R`**: `store_open(s)` (opens `<workspace_root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl` with
`file(path, "ab")` lazily at the first entry, writes the header §4.7, creates the lock `<file>.lock/pid`),
`store_append(store, entry)` (one line: `json_encode()` of the §4.6 JSON shape, `flush()`), `store_read(path)` ->
`list(header, entries)` (tolerates a torn last line), `store_close(store)`, `store_fork(s, cut, new)`,
`store_rebuild(path, home)` -> `<session>`. Consumers: P06, P15 (replay positioning), P16.""",
"""**`session-store.R`** (IC-59): `store_open(s)` (resolves `<workspace_root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl`
lazily at the first entry, writes the header §4.7, creates the lock `<file>.lock/pid` with pid and process
creation time; on an existing file whose last byte is not LF it first appends `"\\n"` and a `gptr.recovered`
entry), `store_append(store, entries)` (one line per entry: `json_encode()` of the §4.6 JSON shape; the file is
opened with `file(path, "ab")`, written, flushed and closed through `on.exit()` inside `suspendInterrupts()`; no
connection outlives the call), `store_read(path)` -> `list(header, entries)` (skips any unparsable line with a
diagnostic; children of missing ids are re-parented to the nearest valid ancestor in projection), `store_close(store)`
(releases the lock), `store_fork(s, cut, new)`, `store_rebuild(path, home)` -> `<session>` (a fork gets a fresh
overlay `new.env(parent = home)`), `store_heartbeat(store)` (touches the lock every 10 minutes from a reactor
timer). Consumers: P06, P15 (replay), P16.

**Replay functions** (`session-object.R`, IC-46): `session_replay_apply(s, block, header, text = NULL)` (advances
the piped session in place: `gptr.replay` entry, `seen`, `turns`, the `value=` name, `last_text`; returns `s`),
`session_replay_new(block, header, envir, doc)` (the live session with the header's id, else a `replayed` session
adopting the recorded id, from the JSONL or reconstructed from the document with `history = "reconstructed"`),
`session_replay_bind(block, s, child = NULL)` and `replay_lookup(block, child = NULL)` (the `the$replay_blocks`
table behind `gptr_resume(block =)`). Consumers: P15, P19."""),
("""| `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api", blocks = list())` | the queue behind `gptr_steer()` | P08, P14, P19 |""",
"""| `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())` | the queue behind `gptr_steer()`; `source` in `pipe`, `pause_menu`, `repl`, `api_user`, `extension`, `agent`; only user sources become operator relays; a call from model code of the same session tree is refused (IC-55) | P08, P14, P19 |"""),
("""| `last_set(s)` | updates `the$last` | P06, P08 |""",
"""| `last_set(s)` | updates `the$last` (a strong reference, IC-71) | P06, P08 |"""),
("""| `run_start(s, input, opts = list())` | the non-blocking form: returns a `gptr_run` registered with the reactor (strong reference until settled) | P08 (`.run`, background), P19, P21 |""",
"""| `run_start(s, input, opts = list())` | the non-blocking form: returns a `gptr_run` registered with the reactor (strong reference until settled); snapshots the safety options of IC-53 into the run | P08 (`.run`, background), P19, P21 |"""),
("""| `perm_check(call, run)` (IC-04) | `list(decision = "allow" \\| "deny" \\| "ask" \\| "modify", reason = chr(1), input = named list, risk = <gptr_risk> \\| NULL, rule = chr(1) \\| NULL)`: every `policy` spec's `check(call, ctx)` (deny > ask > modify > allow; a throwing policy denies; no policy = allow); an `ask` goes to `permission_request` hooks (first decision; error = deny), then to `ui$permission()` when the UI has a human; without a human:""",
"""| `perm_check(call, run)` (IC-04, IC-53) | `list(decision = "allow" \\| "deny" \\| "ask" \\| "ask_human" \\| "modify", reason = chr(1), input = named list, risk = <gptr_risk> \\| NULL, rule = chr(1) \\| NULL)`: every `policy` spec's `check(call, ctx)` (deny > ask_human > ask > modify > allow; a throwing policy denies; **no active `mode` policy = ask**, fail closed, unless the run's snapshot has `gptr.unsafe_no_permissions`); a `modify` is re-classified and re-checked once (a second modify denies); an `ask` goes to `permission_request` hooks (first decision; error = deny), then to `ui$permission()` when `gptr_can_prompt()` holds in the run's snapshot; an `ask_human` skips the hooks; without anyone to prompt:"""),
]
apply(P, pairs)
