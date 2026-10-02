from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""| `setup.R` | redirect `R_USER_CONFIG_DIR`/`R_USER_DATA_DIR`/`R_USER_CACHE_DIR` to a temp dir; blank provider keys unless `GPTR_LIVE_TESTS=true`; `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`; `GPTR_REPLAY=replay`; `OMP_THREAD_LIMIT=2` [13 §4] | P01 |
| `helper-fake.R` | scripted fake-provider scenarios | P01 |
| `helper-tracemem.R` | `expect_no_copy()`: fresh `Rscript --vanilla` process, `tracemem()` on the user object, skip without `capabilities("profmem")` | P01 |
| `helper-mock-server.R` + `fixtures/mock_server.R` | base-R SSE mock (serverSocket/socketSelect) run with processx; scenarios slow, TTFT, overload, 401, 429, truncated, parallel tools; `skip_on_cran()` [10a INFRA-24, 15 §5.1] | P01 |
| `helper-arch.R` + `test-arch-layers.R` | layer table of §2.2 and the codetools layering test | P01 |""",
"""| `setup.R` | redirect `R_USER_CONFIG_DIR`/`R_USER_DATA_DIR`/`R_USER_CACHE_DIR`, `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME` to temp dirs and `GPTR_PROJECT_ROOT` to a temp project [IC-63]; blank provider keys unless `GPTR_LIVE_TESTS=true`; `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`; `GPTR_REPLAY=replay`; `OMP_THREAD_LIMIT=2` [13 §4] | P01 |
| `helper-fake.R` | scripted fake-provider scenarios | P01 |
| `helper-tracemem.R` | `expect_no_copy()`: fresh process started with `rscript_path()` [IC-60], `tracemem()` on the user object, an `in_run_edit` mode [IC-41], skip without `capabilities("profmem")` | P01 |
| `helper-mock-server.R` + `fixtures/mock_server.R` | base-R SSE mock (serverSocket/socketSelect) run with `rscript_path()` through processx, answering only token paths, its provider record `offline = TRUE` [IC-45]; scenarios slow, TTFT, overload, 401, 429, truncated, parallel tools, redirect; `skip_on_cran()` [10a INFRA-24, 15 §5.1] | P01 |
| `helper-arch.R` + `test-arch-layers.R` | layer table of §2.2, the kernel SDK allowlist, the function map parsed from `R/`, and the codetools layering test [IC-33] | P01 |"""),
("""| `test-injection-e2e.R` | `{...}` payloads in model, tool, MCP and error text through every printer and condition constructor; asserts nothing evaluated (rule C1) | P24 |
| `test-northstar.R` | NS-1..NS-12 end to end on the fake provider and scripted UI | P24 |""",
"""| `test-injection-e2e.R` | `{...}` payloads in model, tool, MCP and error text through every printer and condition constructor; asserts nothing evaluated (rule C1); an injected model tries every path of IC-53 to reconfigure the gate, and each ends in a human ask or `blocked` | P24 |
| `test-northstar.R` | NS-1..NS-12 end to end on the fake provider and scripted UI | P24 |
| `test-s11-conformance.R` | a fixture plugin registers one record of every kind; each is used at run time [IC-73] | P24 |"""),
("""| `.github/workflows/R-CMD-check.yaml` | r-lib check-standard (macOS, Windows, Ubuntu release/devel/oldrel-1) + oldrel-4 + no-suggests + `LC_ALL=C` job + copy-safety job on R-release and R-devel | P01 |""",
"""| `.github/workflows/R-CMD-check.yaml` | r-lib check-standard (macOS, Windows, Ubuntu release/devel/oldrel-1) + oldrel-4 + no-suggests + `LC_ALL=C` job + copy-safety job on R-release and R-devel + a job with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true` [IC-59] + a `bench` job running the token ratchet with rtiktoken [IC-73] | P01 |"""),
("""| `dev/bench/tokens/`, `dev/bench/polyglot/`, `dev/bench/shiny-html/`, `dev/bench/cache-sim/`, `dev/bench/perf/` | token-efficiency and performance benchmark suite (§12.6) | P24 |""",
"""| `dev/bench/tokens/run.R` and the NS-2/NS-3 golden transcripts | the token ratchet runner, from M1 [IC-73] | P07 (fixtures added by P10, P13, P15, P18, P19, P22, P23) |
| `dev/bench/tokens/` (other fixtures, `live.R`), `dev/bench/polyglot/`, `dev/bench/shiny-html/`, `dev/bench/cache-sim/`, `dev/bench/perf/` | token-efficiency and performance benchmark suite (§12.6) | P24 |"""),
("""63 exported names: `gptr` plus 62 `gptr_*` names (D-28, plus the `gptr_preimage()` generic added by the interface
contract, IC-01).""",
"""63 exported names: `gptr` plus 62 `gptr_*` names (D-28; the `gptr_preimage()` generic added by the interface
contract, IC-01; `gptr_scrub()` added and `gptr_map()` made internal by the review, IC-36, IC-70)."""),
("""`.opts`: rare switches: `thinking`, `max_turns`, `context` (`"summary"`, `"names"`, `"none"`), `record`,
`interpolate`, `timeout`, `output = "factor"`, `system` (string replaces preamble/tools/rules; named list
overrides sections), `preset`, `returns` (a JSON Schema list: structured final answer that coexists with tools,
INFRA-25), `max_active`, `backend`.""",
"""`.opts`: rare switches: `thinking`, `max_turns`, `context` (`"summary"`, `"names"`, `"none"`), `record`,
`interpolate`, `timeout`, `output = "factor"`, `system` (string replaces preamble/tools/rules; named list
overrides sections), `preset`, `returns` (a JSON Schema list: structured final answer that coexists with tools,
INFRA-25), `max_active`, `backend`, `frontend`, `images` (image files or plots sent to vision models), `seed`
(reproducible sub-agent RNG streams), and entries named by a plugin namespace, validated by that plugin's
settings [IC-44]. Named arguments to `gptr()` are always context objects."""),
("""1  Capture   (base R, copy-safe, §6.4 R3): dot expressions via match.call(expand.dots = FALSE);
             dot facts (is a gptr_session? string literal? length-1 character? spec object?) computed in
             leaf functions reached through ...elt(i) in a while loop; context objects are never copied.
             Evaluating a call among the dots (the inner gptr() of a pipe) runs it once.""",
"""1  Capture   (base R, copy-safe, §6.4 R3): dot expressions via match.call(expand.dots = FALSE);
             dot facts (is a gptr_session? string literal? length-1 character? spec object?) computed in
             leaf functions: a plain-symbol dot through a get0() leaf without forcing its promise, calls and
             forwarded dots through ...elt(i) in a while loop [IC-41]; context objects are never copied.
             Evaluating a call among the dots (the inner gptr() of a pipe) runs it once."""),
("""4  Route     (first match; routes are registry records contributed by built-ins, so the gateway never
             calls an L4 function by name):
   a  model resolves to a classifier provider  -> route "classifier" (builtin:system1): typed vector (4.1.5);
                                                  a piped session becomes the state via as_state(); no turn.
   b  a run is active on the call stack and no  -> child session of the running one (depth + 1, mode inherited
      session is being continued                   and only tightened, usage rolled up, no document block)
   c  no prompt                                 -> human present or .stdin = TRUE: frontend "console" on the
                                                   piped session or a new one; otherwise gptr_error_noninteractive
   d  agents = given                            -> route "team" (builtin:subagents): team session
      parallel = n with one list-like context   -> route "fanout": fan-out session
   e  top-level call with a document binding    -> route "document" (builtin:documents): doc_locate() the
                                                   statement; a fresh recorded block under replay returns a
                                                   replayed session (zero tokens) and the document's own code
                                                   runs next as ordinary R [14 §4.4]""",
"""4  Route     (first match in route order; routes are registry records contributed by built-ins, so the
             gateway never calls an L4 function by name) [IC-39]:
   a  model resolves to a classifier provider  -> route "classifier" (builtin:system1): typed vector (4.1.5);
                                                  a piped session becomes the state via as_state(); no turn.
   d  agents = given                            -> route "team" (builtin:subagents): team session
      parallel = n with one list-like context   -> route "fanout": fan-out session (both before b, so model
                                                   code can start teams and fan-outs as children)
   b  a run is active on the call stack and no  -> child session of the running one (depth + 1, mode inherited
      session is being continued                   and only tightened, usage and budget rolled up to the root,
                                                   no document block)
   c  no prompt                                 -> someone can be prompted (gptr_can_prompt()) or .stdin = TRUE:
                                                   frontend "console" on the piped session or a new one;
                                                   otherwise gptr_error_noninteractive
   e  a top-level call located in a document    -> route "document" (builtin:documents): a fresh recorded block
      that holds a block for it (no write          is replayed with zero tokens (the piped session advanced in
      consent needed to replay)                    place, else a replayed session) and the document's own code
                                                   runs next as ordinary R [14 §4.4; IC-45, IC-46]"""),
("""| symbol that is a **known identifier** (catalog alias, registered provider/model/router, mode, preset, skill, plugin, extension, agent) | the name:""",
"""| symbol that is a **known identifier** (catalog alias, registered provider/model/router, mode, preset, skill, plugin, extension, agent; skill, plugin, extension and agent names compared after mapping `_` and `.` to `-` and lower-casing, so `skills = single_cell` finds `single-cell` [IC-42]) | the name:"""),
("""Batch rule [04 §4.7]: an atomic vector gives one state per element (names kept); an unnamed list, one per
element; a data frame, one per row; a named list, one state; `I(x)`, exactly one state (the idiom for a
data-frame condition in `while()`, documented in the error hint).""",
"""Batch rule [04 §4.7]: an atomic vector gives one state per element (names kept); an unnamed list, one per
element; a data frame, one per row; a named list, one state; `I(x)`, exactly one state (the idiom for a
data-frame condition in `while()`; a function cannot see that it is a condition, so gptr prints a once-per-session
message naming `I(x)` when it splits a data frame into several states [IC-71])."""),
("""`agents =` is evaluated in a mask where `agent` is `gptr_agent` [15 §4.3]. `backend = "auto"` everywhere:
inline, except `cli` for CLI-only models (`claude_code`, `codex`) [15 verifier resolved]. `parallel = n` runs
one inline child per element, `n` at a time,""",
"""`agents =` is evaluated in a mask where `agent` is `gptr_agent` [15 §4.3]; agent names equal to a session
accessor are rejected. `backend = "auto"` everywhere: inline, except `cli` for CLI-only models (`claude_code`,
`codex`) [15 verifier resolved]. `parallel = n` runs one inline child per element, `n` at a time (every element is
queued; the 8-task cap applies only to fan-outs started by model code [IC-39]),"""),
("""Members are tool specs with `exposure = "r"` whose R function is written by hand or generated from the JSON
Schema.""",
"""Members are tool specs with a `fun` (any un-namespaced spec that is not `hidden`; `read`, `edit`, `write`, `grep`,
`find`, `ls` are one spec each with both a direct-tool and a member form [IC-37]) whose R function is written by
hand or generated from the JSON Schema."""),
("""| `grep` | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"))` | `gptr_matches` data frame (file, line, text); print within 1,500 tokens |
| `find` | `gptr$find(pattern, path = ".", sort = c("path", "mtime", "size"), type = "file", limit = 1000L)` | `gptr_files` data frame (path, size, mtime) |""",
"""| `grep` | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"), sort = c("path", "count", "mtime"))` | `gptr_matches` data frame (file, line, text); print within 1,500 tokens |
| `find` | `gptr$find(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"), type = "file", limit = 1000L)` | `gptr_files` data frame (path, size, mtime) |"""),
("""| `out` | `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)` | full text of a truncated result (ids appear in truncation notices) |""",
"""| `out` | `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)` | full text of a truncated result (ids appear in truncation notices; session store, then the spill file); `record = FALSE` |"""),
("""| `knit` | `gptr$knit(engine, code)` | output of any knitr engine |
| `app` | `gptr$app(id, data = character(), title = NULL, kind = c("shiny", "html"), check = TRUE, launch = interactive())` | `gptr_artifact`; URL, checks, screenshot image for the model |
| `help` | `gptr$help(name, package = NULL, budget = 800L)` | tool schema (`"<server>/<tool>"`, member names) or R help text via `tools::Rd2txt`, budgeted |
| `search` | `gptr$search(words, limit = 8L)` | BM25 over members, plugin and MCP tools and skills |
| `describe` | `gptr$describe(x, budget = 150L)` | same as `gptr_describe()` |
| `plot` | `gptr$plot(width = 1000L, height = 700L)` | attaches the current plot at a larger size (about 900 tokens) |""",
"""| `knit` | `gptr$knit(engine, code)` | output of a knitr engine; the shell engines run through `gptr$sh()` [IC-67] |
| `app` | `gptr$app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` | `gptr_artifact`; URL, checks, screenshot image for the model; `kind` is any registered `artifact_type` |
| `help` | `gptr$help(name, package = NULL, budget = 800L)` | tool schema (`"<server>/<tool>"`, member names) or R help text via `tools::Rd2txt`, budgeted; `record = FALSE` |
| `search` | `gptr$search(words, limit = 8L)` | BM25 over members, plugin and MCP tools, skills and `search_source` records; `record = FALSE` |
| `describe` | `gptr$describe(x, budget = 150L)` | same as `gptr_describe()`; `record = FALSE` |
| `plot` | `gptr$plot(which = NULL, width = 1000L, height = 700L)` | attaches the current (or a stored, [IC-67]) plot at a larger size (about 900 tokens); `record = FALSE` |"""),
("""Plugins add members with `gptr_tool(..., exposure = "r", namespace = "<pkg>")` reached as
`gptr$<pkg>$<tool>()`; one signature line each enters the frozen `<mcp>`/plugin catalog within its budget.""",
"""Plugins add members with `gptr_tool(..., exposure = "r", namespace = "<pkg>")` reached as
`gptr$<pkg>$<tool>()` (the namespace is required and may not be a reserved member name or `mcp` [IC-37]); one
signature line each enters the frozen `<mcp>`/plugin catalog within its budget."""),
("""**Setup and status** (9)

```r
gptr_init(path, instructions = TRUE, gitignore = TRUE)
gptr_config(..., .scope = c("session", "project", "user"))""",
"""**Setup and status** (10)

```r
gptr_init(path, instructions = TRUE, gitignore = TRUE)
gptr_config(..., .scope = NULL)"""),
("""gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL,
                 scope = c("session", "project", "user"))
```""",
"""gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL,
                 scope = c("session", "project", "user"))
gptr_scrub(paths = NULL, dry_run = TRUE, error = FALSE)
```"""),
("""separately, §6.10). `gptr_config(model = sonnet, mode = manual)` takes bare identifiers; project scope may only
tighten security settings.""",
"""separately, §6.10). `gptr_config(model = sonnet, mode = manual)` takes bare identifiers; `.scope = NULL` means
the project when a workspace exists (NS-9's "project defaults"), else this session; project scope may only
tighten security settings. `gptr_scrub()` audits persisted files for secrets registered too late and, with
`dry_run = FALSE`, rewrites them with markers [IC-70]."""),
("""gptr_doc(path = NULL, format = NULL)""", """gptr_doc(path = NULL, format = NULL, sync = FALSE)"""),
("""`gptr_doc()` binds the console session to a document (explicit consent to write it) or shows the binding.""",
"""`gptr_doc()` binds every `gptr()` call of the process to a document (explicit consent to write it), shows the
binding, or (`sync = TRUE`) applies pending blocks of a notebook that was open while recording [IC-45, IC-50]."""),
("""**Session SDK** (15)""", """**Session SDK** (14)"""),
("""gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
gptr_map(.x, prompt, ..., model = NULL, agent = NULL, max_active = 4L, backend = "auto")
gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame())""",
"""gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)"""),
("""returns the per-request token ledger. `gptr_parallel()` and `gptr_map()` return team and fan-out sessions.""",
"""returns the per-request token ledger. `gptr_parallel()` returns a team session; fan-outs come from
`gptr(prompt, x, parallel = n)` (the former `gptr_map()` is internal: one gateway, S-1 [IC-36]).
`gptr_resume(block = "<id>")` returns the session that replay bound to a document block [IC-46]."""),
("""`gptr_return()` designates the run's result under the value policy of §5.1 and errors outside a run.""",
"""`gptr_return()` designates the run's result under the value policy of §5.1; outside a run it returns
`invisible(x)` and does nothing else, so recorded code re-sources cleanly [IC-48]."""),
("""gptr_check(x, error = FALSE)
gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))""",
"""gptr_check(x, error = FALSE, tokens = FALSE)
gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))"""),
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
                   authority = c("data", "operator"), budget = 300L, order = 650L)""",
"""gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)
gptr_context_block(name, provide, placement = c("turn", "first", "both"),
                   authority = c("data", "operator"), budget = 300L, order = 650L)"""),
("""| Setup and status | 9 | `gptr_init`, `gptr_config`, `gptr_env`, `gptr_trust`, `gptr_login`, `gptr_logout`, `gptr_providers`, `gptr_models`, `gptr_permissions` |""",
"""| Setup and status | 10 | `gptr_init`, `gptr_config`, `gptr_env`, `gptr_trust`, `gptr_login`, `gptr_logout`, `gptr_providers`, `gptr_models`, `gptr_permissions`, `gptr_scrub` |"""),
("""| Session SDK | 15 | `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_fork`, `gptr_on`, `gptr_parallel`, `gptr_map`, `gptr_sessions`, `gptr_resume`, `gptr_last`, `gptr_jobs`, `gptr_usage`, `gptr_rewind`, `gptr_checkpoints` |""",
"""| Session SDK | 14 | `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_fork`, `gptr_on`, `gptr_parallel`, `gptr_sessions`, `gptr_resume`, `gptr_last`, `gptr_jobs`, `gptr_usage`, `gptr_rewind`, `gptr_checkpoints` |"""),
]
apply(P, pairs)
