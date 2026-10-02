from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""With no rule arguments: returns a `gptr_permissions` data frame of all rules in effect (session, project
`settings.json` and `settings.local.json`, user).""",
"""With no rule arguments: returns a `gptr_permissions` data frame of all rules in effect (session, project
`settings.json`, the user-level project file, user)."""),
("""servers configured for Claude Code, Claude Desktop, Codex (TOML subset), Cursor, VS Code and Pi (read-only), with
era (from the era cache), status and tool counts; no connection is made.""",
"""servers configured for Claude Code, Claude Desktop, Codex (TOML subset), Cursor, VS Code and Pi (read-only; their
files are found under `user_home()` and `app_config_dir()`, never `path.expand("~")`, IC-63), with era (from the
era cache), status and tool counts; no connection is made."""),
("""Serves the live session over loopback Streamable HTTP (both MCP eras): binds `127.0.0.1` on `port` (`NULL` =
random free port), requires a 192-bit bearer token (`openssl::rand_bytes(24)`, hex), validates `Origin`, and runs
every call through the permission gate as a nested call of a dedicated session (`kind = "chat"`, label `mcp`)
whose home is `envir`.""",
"""Serves the live session over loopback Streamable HTTP (both MCP eras): binds `127.0.0.1` on `port` (`NULL` = a
free port from `port_candidates()`, never `httpuv::randomPort()`, IC-61), requires a 192-bit bearer token
(`openssl::rand_bytes(24)`, hex), validates `Origin`, and runs every call through the permission gate as a nested
call of a dedicated session (`kind = "chat"`, label `mcp`) whose home is `envir`. The listening socket is shared:
CLI children get their own tokens bound to their sessions through `mcp.serve_ensure(session)` (IC-58)."""),
("""Claude Code, Claude Desktop, Cursor with a tool timeout of at least 3,600 s), `$stop()`. One server per process:
calling again returns the running handle; `stop = TRUE` stops it and returns `invisible(NULL)`. Requests are served
while gptr pumps the reactor (`later::run_now(0)`) or at an idle console.""",
"""Claude Code, Claude Desktop, Cursor with a tool timeout of at least 3,600 s), `$stop()`. One server per process:
calling again returns the running handle; `stop = TRUE` stops it and returns `invisible(NULL)`. Requests are served
while the outermost reactor pump runs (`later::run_now(0)` at depth 1, IC-57) or at an idle console, where a
request that needs approval is denied with how to allow it (never a prompt from a callback)."""),
("""gptr_doc(path = NULL, format = NULL)
```

`path = NULL`: returns the current binding `list(path, format)` or `NULL`, visibly. A path binds console sessions
of this R process to that document (explicit consent to write it); `FALSE` unbinds.""",
"""gptr_doc(path = NULL, format = NULL, sync = FALSE)
```

`path = NULL`: returns the current binding `list(path, format)` or `NULL`, visibly. A path binds every `gptr()`
call of this R process (console and script) to that document, which is explicit consent to write it (IC-45);
`FALSE` unbinds. `sync = TRUE` applies the pending blocks recorded for that document (a Jupyter notebook that was
open while recording, or unapplied deferred-write sidecars) through the format's writer (IC-50, IC-51)."""),
("""`info` returns a `gptr_cache_info` data frame; `prune` removes S2 entries of deleted blocks,""",
"""`info` returns a `gptr_cache_info` data frame (including unapplied document sidecars, which are never pruned
automatically, IC-51); `prune` removes S2 entries of deleted blocks,"""),
("""`gptr_parallel()`: each `...` argument (named) is a `gptr()` call, forced under a dynamic flag so that it returns
an unstarted session, or a session created with `.run = FALSE`; `.list` is a named list of such sessions. All run
concurrently on one reactor (at most `max_active`, default `gptr.max_active`).""",
"""`gptr_parallel()`: each `...` argument (named) is a `gptr()` call, forced under a dynamic flag so that it returns
an unstarted session, or a session created with `.run = FALSE`; `.list` is a named list of such sessions. All run
concurrently on one reactor (at most `max_active`, default `gptr.subagents.max_active`, IC-71)."""),
("""`gptr_map()`: the function behind `parallel =`: one inline (or `backend`) child per element of `.x` (a list,
atomic vector or data frame rows), each receiving `prompt` and its element as context (read in place by name,
`.x[[i]]`), `...` further context; returns a **fan-out session** (`kind = "fanout"`; `$text` a named chr,
`[[i]]`/`$name` child sessions). `model`/`agent` are identifiers (§6.1.3). Copy-safety: [R1][R3] (elements are read
in place; `test-copy-subagent.R`).

```r
fake = gptr_fake_provider(function(req) "summary")
fs = gptr_map(list(a = 1:3, b = 4:6), "Summarise this", model = fake)
fs$text
```
""",
"""`gptr_map()` is **internal** (IC-36; S-1 keeps one gateway): the function behind `parallel =`, one inline (or
`backend`) child per element of `.x` (a list, atomic vector or data frame rows), each receiving the prompt and its
element as context (read in place by name, `.x[[i]]`); it returns a **fan-out session** (`kind = "fanout"`;
`$text` a named chr, `[[i]]`/`$name` child sessions). Users write `gptr("Summarise this", cohorts, parallel = 4)`.
Copy-safety: [R1][R3] (elements are read in place; `test-copy-subagent.R`).
"""),
("""#### `gptr_parallel()`, `gptr_map()` — P19, `subagent-team.R` [stable]

```r
gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
gptr_map(.x, prompt, ..., model = NULL, agent = NULL, max_active = 4L, backend = "auto")
```""",
"""#### `gptr_parallel()` — P19, `subagent-team.R` [stable]

```r
gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
```"""),
("""gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame())
gptr_last()
```""",
"""gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)
gptr_last()
```"""),
("""otherwise rebuilds the session from its JSONL (leaf = last entry; status `idle` when the tail is a final answer,
else `interrupted`) with home `envir`. A detached copy follows the split-brain rules of §5.1 of `03`
(`gptr_error_split_brain`). Conditions: `invalid_argument`, `split_brain`, `busy`.

`gptr_last()`: the most recently active session of this process (weak index), including one whose call was
interrupted before assignment, or `NULL`.""",
"""otherwise rebuilds the session from its JSONL (leaf = last entry; status `idle` when the tail is a final answer,
else `interrupted`) with home `envir`; a rebuilt **fork** always gets a fresh `new.env(parent = envir)` overlay
(IC-46). A file from another machine or tracked by git is rebuilt with a freshly frozen prompt and its user turns
marked `imported` (IC-52). A detached copy follows the split-brain rules of §5.1 of `03` (`gptr_error_split_brain`).
`block = "<id>"` (and `child = "<name>"` for team blocks) returns the session that replay bound to that document
block in this process, or signals `gptr_error_replay_unbound`; it never falls back to `envir` (IC-46). Conditions:
`invalid_argument`, `split_brain`, `busy`, `replay_unbound`.

`gptr_last()`: the most recently active session of this process, held **strongly** (IC-71), including one whose
call was interrupted before assignment, or `NULL`."""),
("""#### `gptr_jobs()` — P21, `agent-background.R` [stable]""",
"""#### `gptr_jobs()` — P04, `proc-supervise.R` (IC-36) [stable]"""),
("""Returns a `gptr_jobs` data frame of the job table (IC-12): background sessions, `gptr$bg()` jobs, artifacts, the
MCP server, workers and CLI children.""",
"""Returns a `gptr_jobs` data frame of the job table (IC-12): background sessions (rows added by P21, status
`waiting` when an ask is pending, IC-57), `gptr$bg()` jobs, artifacts, the MCP server, workers and CLI children."""),
("""and forces `x` in a leaf; the session stores it under the §5.1 value policy of `03` (symbol bound in a kept home and
below `gptr.value_copy_max`: deep copy; larger: name + address; anonymous or bound in a function-frame home: boxed),
capped by `gptr.values_max_bytes`, and appends a `gptr.value` entry. Returns `invisible(NULL)`. Outside a run:
`gptr_error_not_in_run`. Copy-safety: [R1][leaf] (`test-copy-tools.R` rows for the three cases).""",
"""and forces `x` in a leaf; the session stores it under the §5.1 value policy of `03` (symbol bound in a kept home and
below `gptr.value_copy_max`: deep copy; larger: name + address; anonymous or bound in a function-frame home: boxed),
capped by `gptr.values_max_bytes`, and appends a `gptr.value` entry. Returns `invisible(NULL)`. Outside a run it
returns `invisible(x)` and does nothing else (a once-per-session `notice`, silent while a document is replayed), so
recorded code that still contains the call re-sources cleanly (IC-48). Copy-safety: [R1][leaf] (`test-copy-tools.R`
rows for the three cases)."""),
("""Level-based: a method may accept `level = 1:4` in `...` and return
successively richer descriptions; the harness picks the richest that fits. Packages add methods with delayed
`S3method(gptr::gptr_describe, cls)`. Copy-safety: [R4].""",
"""Level-based: a method may accept `level = 1:4` in `...` and return
successively richer descriptions; the harness picks the richest that fits. Methods for classes of packages outside
Suggests (`dgCMatrix`, `ArrowTabular`, `Dataset`, `Seurat`, `SingleCellExperiment`, `ggplot`) use only base generics,
`methods::slot()`/`slotNames()`, `attr()` and `dim()` guarded by `isNamespaceLoaded()`, never `pkg::fun()`
(IC-71). Packages add methods with delayed `S3method(gptr::gptr_describe, cls)`. Copy-safety: [R4]."""),
("""#### `gptr_prob()` — P08, `gptr-sdk.R` [stable]""",
"""#### `gptr_prob()` — P13, `s1-types.R` (IC-36) [stable]"""),
("""```r
gptr_redact("Authorization: Bearer abcdef0123456789abcdef")
```
""",
"""```r
gptr_redact("Authorization: Bearer abcdef0123456789abcdef")
```

#### `gptr_scrub()` — P03, `auth-redact.R` (IC-70) [stable]

```r
gptr_scrub(paths = NULL, dry_run = TRUE, error = FALSE)
```

Audits (and, on request, cleans) persisted text for registered secrets that entered history before they were
registered. `paths`: `NULL` = the workspace's sessions, caches, spill files, plans, transcripts and the documents
bound in this project; or a chr of files and directories. Returns a data frame `file`, `secret` (the variable
name), `count` (never values), visibly with `dry_run = TRUE`. `error = TRUE` signals `gptr_error_secret_found` when
any row exists (pre-commit and CI use). `dry_run = FALSE` rewrites the listed files replacing values and derived
forms with `[secret:NAME]` markers (the only sanctioned rewrite of append-only files; each rewritten session file
gets a `gptr.scrub` entry) and returns the data frame invisibly. Called from model code during a run with
`dry_run = FALSE` it is a `control`-category action (IC-53). Conditions: `invalid_argument`, `secret_found`.

```r
d = tempfile("proj"); dir.create(d)
writeLines("nothing secret here", file.path(d, "notes.txt"))
gptr_scrub(d)
```
"""),
("""```r
gptr_fake_provider(script, name = "fake")
```

Returns a `<spec:provider>` (`id = name`, `api = "fake"`, `type = "chat"`, one model `name/<name>-1`) whose
engine plays `script`;""",
"""```r
gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))
```

Returns a `<spec:provider>` (`id = name`, `api = "fake"` or `"fake-classifier"`, `type`, one model `name/<name>-1`
or `name/<name>-s1`, `offline = TRUE`; IC-21, IC-35) whose engine plays `script`;"""),
("""gptr_check(x, error = FALSE)
```

Runs the conformance suite for `x`:""",
"""gptr_check(x, error = FALSE, tokens = FALSE)
```

`tokens = TRUE` also reports a plugin's declaration cost and the printed-result cost of each member on its examples
(IC-69); for an installed package it flags bare gptr identifiers in package code (IC-42). Runs the conformance
suite for `x`:"""),
("""installed package name (`chr(1)`: manifest, API requirement, factory), an adapter spec (fixture replay through
`gptr_check_adapter()`, P12 registers the fixture runner as a service:""",
"""installed package name (`chr(1)`: manifest, API requirement, factory), an adapter spec (fixture replay through
`check_adapter()`, which P12 registers as the `check.adapter` service; a list `tool_choice` sent while the model
capability `forced_tool_choice` is `FALSE` fails:"""),
("""gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
              type = c("chat", "classifier", "cli"), headers = list(), discover = NULL)
gptr_adapter(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"),
             build, parse = NULL, stream = NULL, classify = NULL, capabilities = list())
gptr_router(name, route, description = NULL)""",
"""gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
              type = c("chat", "classifier", "cli"), headers = list(), discover = NULL,
              status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)
gptr_adapter(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"),
             build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())
gptr_router(name, route, description = NULL, timeout = 2)"""),
("""gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L)
gptr_context_block(name, provide, placement = c("turn", "first"),
                   authority = c("data", "operator"), budget = 300L)""",
"""gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)
gptr_context_block(name, provide, placement = c("turn", "first", "both"),
                   authority = c("data", "operator"), budget = 300L, order = 650L)"""),
("""Notes that cross plans: `gptr_agent()` with only `name` (or `file`) loads the definition through the `agent_def.get`
service of P17 (`gptr_error_not_available` before P17); inside `gptr(agents = list(...))` `agent()` is this
function; `model` and `skills` accept bare identifiers resolved at the gateway (§6.1.3), so `gptr_agent()` stores
the captured expressions' names, not values (it is itself a capture site obeying [R3]).""",
"""Notes that cross plans: `gptr_adapter()` validates per transport (`http_*` and `process_jsonl` need `build` and
`parse`, `inprocess` needs `stream`, classifier adapters need `classify`; IC-35). `gptr_agent()` with only `name`
(or `file`) loads the definition through the `agent_def.get` service of P17 (`gptr_error_not_available` before
P17); inside `gptr(agents = list(...))` `agent()` is this function; `model` and `skills` accept bare identifiers,
and `gptr_agent()` stores the raw captured expressions (symbol names or literals), which the gateway resolves
(§6.1.3), so P02 never calls P08 (it is itself a capture site obeying [R3]; IC-34). A `gptr_context_block()` with
`authority = "operator"` is accepted only from records of rank >= 3 (IC-52). `gptr_prompt_section(parent =)` makes
the spec a fragment of the named section (IC-68)."""),
]
apply(P, pairs)
