from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""`the = new.env(parent = emptyenv())` is created in `utils-options.R` (P01). Each field has one owner; other plans
read it only through the owner's functions (INFRA-15: no run state here).""",
"""`the = new.env(parent = emptyenv())` is created in `aaa-state.R` (P01; collates first, IC-32). Each field has one
owner; other plans read it only through the owner's functions (INFRA-15: no run state here)."""),
("""| `on_load`, `on_unload`, `once`, `out`, `services` | P01 | load-time expressions; unload callbacks; once-keys of `gptr_warn(.once =)`; the `gptr$out()` store; the service table (IC-09) |""",
"""| `on_load`, `on_unload`, `once`, `out`, `services`, `redactor` | P01 | load-time expressions; unload callbacks; once-keys of `gptr_warn(.once =)`; the process-level `gptr$out()` store for user calls outside a run (sessions keep their own, IC-71); the bootstrap service table (IC-09, IC-34); the installed redaction hook |"""),
("""| `live`, `last` | P06 | weak index of live sessions `id -> weakref(key = shell, value = live)`; weak reference to the last session |""",
"""| `live`, `last`, `replay_blocks` | P06 | weak index of live sessions `id -> weakref(key = shell, value = live)`; the last session, held strongly (IC-71); block id -> the session replay bound to it (gptr-created sessions only, IC-46) |"""),
("""| `mcp_conns`, `mcp_server` | P18 | MCP connections; the running `gptr_mcp_serve()` server |""",
"""| `mcp_conns`, `mcp_server`, `mcp_tokens` | P18 | MCP connections; the running `gptr_mcp_serve()` server; bearer token -> session id (IC-58) |"""),
("""Services (IC-09) are named functions registered with `ext_service_set()` (P01, §7.1) by their provider plan in an
`on_load()` expression, and fetched with `ext_service_get(name)` (signals `gptr_error_not_available` naming the
providing plan when absent). The complete list:""",
"""Services (IC-09) are named functions registered with `ext_service_set(name, fun, provided_by, builtin)` (P01, §7.1)
by their provider plan in an `on_load()` expression, and fetched with `ext_service_get(name)` (signals
`gptr_error_not_available` naming the providing plan when absent or when the owning built-in is filtered out; once
P02 is loaded a `service` registry record of lower rank replaces the bootstrap entry, IC-34). The complete list:"""),
("""| `check.adapter` | P12 | `gptr_check()` (P02) | `function(adapter, fixtures = NULL) <gptr_check>` |""",
"""| `check.adapter` | P12 | `gptr_check()` (P02) | `function(adapter, fixtures = NULL) <gptr_check>` |
| `trust.get` | P08 | P03 (`.env` discovery), P07 (SYSTEM.md, instruction authority), P17, P18 (IC-33) | `function(path = getwd()) lgl(1)`; fallback `FALSE` |
| `identifier.resolve` | P08 | `gptr_agent()` capture (P02), agent files (P17) | `function(expr, arg, envir) chr or spec`; fallback: literal names |
| `secret.lookup` | P03 | `ctx$secret()` (P02) | `function(name) <handle> or NULL`; fallback `NULL` |
| `ctx.kernel` | P06 | `ctx_new()` (P02) | `function() named list` of the §10.6 member implementations marked P06 |
| `ctx.input` | P07 | `ctx$input` (P02) | `function(ctx) list or NULL` |
| `ns.names` | P10 | `.DollarNames.gptr_gateway` (P08) | `function(pattern) chr`; fallback `character(0)` |
| `eval.r` | P09 | `ctx$eval()` (P02), P18 server `r`, P14 `!expr` | `eval_r()` through the `evaluator` kind (IC-69) |
| `describe` | P09 | `ctx$describe()` (P02) | `function(x, budget) chr` |
| `router.call` | P08 | every request of a routed session (P06) | `function(s, reason) list(model, thinking, state)` (IC-69) |
| `session.add_tools` | P07 | `ctx$add_tools()`, `gateway_run()` continuations | `function(s, specs) invisible(s)` (IC-69) |
| `search.sources` | P10 | `gptr$search()` | `function(session) df(id, text, kind)` from `search_source` records (IC-69) |"""),
("""| `gptr_has_human()` | `lgl(1)`: `getOption("gptr.interactive")` if set, else `interactive()` and not knitting and not under testthat and not `check_running()` | P06, P08, P11, P14, P15 |""",
"""| `gptr_has_human()` | `lgl(1)`: `getOption("gptr.interactive")` if set, else `interactive()` and not knitting and not under testthat and not `check_running()`; decides streaming and verbosity only | P06, P08, P14, P15 |
| `gptr_can_prompt()` | `lgl(1)`: `getOption("gptr.interactive")` if set, else `interactive() \\|\\| isTRUE(getOption("jupyter.in_kernel"))`, excluding knitr, testthat and `check_running()`; decides every question (IC-43) | P06 (`perm_check()`), P08, P11, P14, P15 |"""),
("""| `gptr_confirm(question, default = FALSE)` | `lgl(1)`: `y`/`yes` (case-insensitive) is `TRUE`; empty input gives `default`; without a human returns `default` without asking; never `askYesNo()` | P08, P15 |""",
"""| `gptr_confirm(question, default = FALSE)` | `lgl(1)`: `y`/`yes` (case-insensitive) is `TRUE`; empty input gives `default`; when `gptr_can_prompt()` is `FALSE` returns `default` without asking; never `askYesNo()` | P08, P15 |"""),
("""| `on_load(expr)` | stores `substitute(expr)` and `parent.frame()`; `.onLoad` evaluates them in registration order after the namespace is loaded | all built-in declarations |
| `on_unload(fun)` | registers a zero-argument cleanup run by `.onUnload` (reverse order, each in `try()`) | P04, P18, P21, P23 |""",
"""| `on_load(expr)` (`aaa-state.R`, IC-32) | stores `substitute(expr)` and `parent.frame()`; `.onLoad` evaluates them in registration order after the namespace is loaded | all built-in declarations |
| `on_unload(fun)` (`aaa-state.R`) | registers a zero-argument cleanup run by `.onUnload` (reverse order, each in `try()`) | P04, P18, P21, P23 |
| `supervise_default()` | `lgl(1)`: `isTRUE(getOption("gptr.supervise"))` when set, else `!check_running()` (IC-60) | P04, P19, P23 |"""),
("""| `ext_service_set(name, fun, provided_by)` | registers a service (IC-09) in `the$services`; a second registration replaces the first (recorded as a diagnostic once P02 is loaded) | all service providers |""",
"""| `ext_service_set(name, fun, provided_by, builtin = NULL)` (`aaa-state.R`) | registers a service (IC-09) in `the$services`, owned by `builtin`; a second registration replaces the first (recorded as a diagnostic once P02 is loaded) | all service providers |
| `redactor_set(fun)`, `redact_hook(x, profile = "persist")` (`aaa-state.R`) | the redaction hook: identity until P03 installs `redact()` (IC-34) | P01, P02, P03 |
| `` `%||%` `` (`aaa-state.R`) | internal null default (base has it only from R 4.4) | all |"""),
("""**`utils-encoding.R`**: `utf8_mark(x)` (marks valid UTF-8 as UTF-8, leaves ASCII),""",
"""**`utils-encoding.R`**: `as_utf8(x)` (the ingress normaliser of IC-62: unknown-encoded valid UTF-8 is marked UTF-8,
other unknown strings go through `enc2utf8()`; the only place `enc2utf8()` may be called), `utf8_mark(x)` (marks valid UTF-8 as UTF-8, leaves ASCII),"""),
("""| `project_root(path = getwd())` | chr(1) (§1.2) | all |""",
"""| `project_root(path = getwd())` | chr(1) (§1.2); `options(gptr.project_root)` or `GPTR_PROJECT_ROOT` override it (IC-63) | all |
| `user_home()`, `app_config_dir(app)` | the user's home (`USERPROFILE` on Windows, else `HOME`, else `path.expand("~")`) and an application's config directory (`%APPDATA%`, `~/Library/Application Support`, `$XDG_CONFIG_HOME` or `~/.config`) (IC-63) | P17, P18 |
| `path_key(path)` | normalised path, lower-cased on Windows and macOS (IC-51) | P08, P11, P15 |
| `rscript_path()` | `file.path(R.home("bin"), "Rscript")` (`Rscript.exe` on Windows), never a PATH lookup (IC-60) | P04, P19, P20, tests |"""),
("""| `write_atomic(path, content)` | writes chr (UTF-8, LF) or raw to a temp file in the same directory, then `file.rename()` (3 retries on Windows); returns `invisible(path)` | all writers |""",
"""| `write_atomic(path, content)` | writes chr (UTF-8, LF) or raw to a temp file in the same directory, then `file.rename()` (3 retries with 100 ms sleeps, then an in-place `writeBin()` after an md5 re-check, IC-51); returns `invisible(path)` | all writers |"""),
("""| `path_class(path, root = project_root())` | chr: `workspace`, `temp`, `outside`, `protected`, `critical`, `url`, `wildcard`, `unknown` [18 §3.8] | P10, P11, P16 |""",
"""| `path_class(path, root = project_root())` | chr: `workspace`, `temp`, `outside`, `protected`, `control` (level 4, IC-54), `instructions` (level 3, IC-54), `critical`, `url`, `wildcard`, `unknown` [18 §3.8] | P10, P11, P16 |"""),
("""| `out_put(text, stream = "stdout", meta = list())` | chr(1) id `o<n>`; keeps the last `gptr.out_keep` entries | P09, P22 |
| `out_get(id, stream = c("stdout", "stderr"), lines = NULL)` | chr (lines) or `gptr_error_invalid_argument` for an unknown/evicted id | P10 (`gptr$out`) |""",
"""| `out_put(text, stream = "stdout", meta = list(), session = NULL)` | chr(1) id `o` + 6 hex (RNG-free); kept in the session's store (the process store when `session` is `NULL`), the last `gptr.out_keep` entries (IC-71) | P09, P22 |
| `out_get(id, stream = c("stdout", "stderr"), lines = NULL, session = NULL)` | chr (lines) from the session store, then the process store, then the spill file; `gptr_error_invalid_argument` when none has it | P10 (`gptr$out`) |"""),
("""**`utils-hash.R`**

| Function | Contract | Consumers |
|---|---|---|""",
"""**`utils-hash.R`**

| Function | Contract | Consumers |
|---|---|---|
| `with_seed_preserved(expr)` [leaf] | evaluates `expr` and restores (or removes) `.Random.seed` in the global environment afterwards; one of the two functions allowed to assign it (IC-61) | P18, P23 |
| `port_candidates(n = 20L)` | int: RNG-free ports in 49152-65535 from `id_new()` hash bits (IC-61) | P18, P23 |"""),
]
apply(P, pairs)
