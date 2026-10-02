
---

## 4. Exported API

62 exported names: `gptr` plus 61 `gptr_*` names (D-28). None collides with the export index G1 scanned
(592 installed packages, 37 CRAN LLM packages, r-universe) [G1 §4.7]; unprefixed proposals (`decide`,
`classify`, `artifact`, `mcp_tools`, `tools`, `agent`, `sh`, `py`, `sql`) are namespace members, mask aliases
or internal. S3 methods are registered, not exported names. Every export has roxygen docs with `@return` and
an example that runs offline through `gptr_fake_provider()` or `envir = new.env()` [13 C-47]; related
exports share Rd pages (`@rdname`) to keep the manual small. The interface contract (04) gives full behaviour.

### 4.1 `gptr()`, the gateway

```r
gptr = function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                choices = NULL, levels = NULL, threshold = 0.5,
                min_confidence = NULL, uncertain = NULL,
                prompt = NULL, envir = parent.frame(), background = FALSE,
                budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                .stdin = FALSE)
```

`gptr` is a closure with class `c("gptr_gateway", "function")` and S3 methods `$`, `[[`, `.DollarNames`,
`$<-` (refuses) and `print`: calling it runs the agent, `gptr$name` reaches the namespace (§4.2). The pattern
passes `R CMD check --as-cran` codoc and S3 registration [G5 toy check; J-req verified dispatch]. All formals
follow `...`, so they match only by exact name and a context object named `mod` is never swallowed by
`model` [05 §4.1].

**Arguments.** `...`: at most one leading session (continuation), the prompt, context objects (unnamed ones
labelled by their expression, named ones by name). `model`, `mode`, `skills`, `plugins`, `extensions`,
`tools` take bare identifiers (§4.1.3); `tools` also takes `"+grep"`/`"-write"` modifiers, a preset name
(`"minimal"`, `"standard"`, `"readonly"`, `"extended"`) or `gptr_tool()` specs (rank 0). `agents`: named list
of agent definitions (`agent()` is bound to `gptr_agent()` inside it). `parallel = n`: fan a list/vector/data
frame context out over `n` concurrent sub-agents. `choices`, `levels`, `threshold`, `min_confidence`,
`uncertain`: System 1 answer shape and abstention (§4.1.5). `envir`: where code runs and objects persist
(D-04). `background = TRUE`: experimental, returns the running session at once (needs `later`). `budget =
list(tokens =, cost =, turns =)`. `replay`: document replay mode (`"auto"`, `"replay"`, `"live"`, `"record"`).
`.opts`: rare switches: `thinking`, `max_turns`, `context` (`"summary"`, `"names"`, `"none"`), `record`,
`interpolate`, `timeout`, `output = "factor"`, `system` (string replaces preamble/tools/rules; named list
overrides sections), `preset`, `returns` (a JSON Schema list: structured final answer that coexists with tools,
INFRA-25), `max_active`, `backend`. `.run = FALSE`: build the session with the prompt queued (SDK).
`.stdin = TRUE`: drive the console from piped standard input [18 §4.2].

#### 4.1.1 Dispatch

```text
1  Capture   (base R, copy-safe, §6.4 R3): dot expressions via match.call(expand.dots = FALSE);
             dot facts (is a gptr_session? string literal? length-1 character? spec object?) computed in
             leaf functions reached through ...elt(i) in a while loop; context objects are never copied.
             Evaluating a call among the dots (the inner gptr() of a pipe) runs it once.
2  Prompt    prompt= if given; else the first unnamed string literal; else the first unnamed length-1
             character value that is not a session [12 §2.D3]; two unnamed literals -> warning.
             Literal prompts get {identifier} interpolation (4.1.4).
3  Resolve   model, mode, skills, plugins, extensions, tools, agents (4.1.3).
4  Route     (first match; routes are registry records contributed by built-ins, so the gateway never
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
                                                   runs next as ordinary R [14 §4.4]
   f  a session was piped in                    -> running: gptr_steer(s, prompt); return invisible(s) at once
                                                   idle / error / aborted / interrupted: follow-up turn on s
   g  otherwise                                 -> new session
5  Run       .run = FALSE -> return s with the prompt queued; background = TRUE -> register with the
             background pump (experimental, 6.2); else run to settlement on the reactor under the
             interrupt policy; write the document block; return s.
```

Return visibility: the session is returned invisibly when its answer was already streamed to the console,
visibly otherwise (Rscript, knitr, programmatic use) [18 §4.5]. Interactive `gptr()` returns the session
invisibly on `/exit`, so `s = gptr()` keeps the conversation. A programmatic interrupt persists the partial
turn, keeps the session reachable through `gptr_last()` and re-signals the interrupt so loops stop [15 §4.7].
Provider failures after retries give `status = "error"` and a classed `gptr_error_provider` carrying the
session as `cnd$session`.

#### 4.1.2 Call shapes (every north-star spelling)

| Call | Route | Returns |
|---|---|---|
| `gptr()` | c: console on a new session | the session, invisibly on `/exit` |
| `s \|> gptr()` | c: console on `s` | `s`, invisibly |
| `gptr("prompt", mice)` | g; context `mice` described by name | new session |
| `mice \|> gptr("prompt")` | g (data-first pipe: the first dot is not a session) | new session |
| `gptr("a") \|> gptr("b") \|> gptr("c", model = opus)` | f twice; model switch with hand-off | the same session |
| `qc \|> gptr("Use 15% ...")` | f: follow-up if idle, steering if running | `qc` |
| `gptr_fork(qc) \|> gptr("Try 10%")` | f on the fork | the fork |
| `gptr("Is ...?", abstracts, model = jev)` | a | `gptr_decision` vector |
| `gptr(q, samples$description, model = jev, choices = c(...))` | a | `gptr_choice` vector |
| `s \|> gptr("Did it succeed?", model = jev)` | a on `as_state(s)` | `gptr_decision` |
| `gptr(task, model = if (hard) opus else haiku, mode = auto)` | g; model expression in the alias mask | session |
| `gptr("Review ...", agents = list(stats = agent(model = opus), ...))` | d: team | team session (`reviews$stats`) |
| `gptr("Summarise this cohort", cohorts, parallel = 4)` | d: fan-out | fan-out session |
| `res = gptr("task", data, model = gemini)` inside `r` | b | child session |
| `gptr("Clean up the data directory", mode = plan)` then `gptr("Go ahead with that plan", mode = auto)` | g, g with the pending plan attached once (§6.8.5) | sessions |

#### 4.1.3 Identifier resolution (D-07)

Capture is base R (§6.4 R3; G3 t2b verified including forwarded dots). Resolution order:

| Expression | Result |
|---|---|
| `NULL` | the default from settings |
| string literal (`"opus"`) | itself |
| symbol that is a **known identifier** (catalog alias, registered provider/model/router, mode, preset, skill, plugin, extension, agent) | the name: **the known identifier wins over a same-named variable**, as `library(pkg)` does, so packages exporting `claude`, `codex` or `plan` cannot hijack it [12 §2.D1, 10 Q4]; a once-per-session notice when a character variable of that name holds a different value ("used the alias; write !!sonnet") |
| `!!x` | the value of `x` (explicit escape for a shadowed alias) |
| `I(x)` | the value of `x` |
| other symbol, bound where the call's promise is evaluated | the formal's promise is forced in a leaf: a character value is used; a spec object (`gptr_fake_provider()`, `gptr_tool()`, `gptr_agent()`) is registered at rank 0; any other class is a classed error naming the class ("`mice` is a data.frame, not a model name") |
| unknown unbound symbol | the literal name, validated later with `adist()` suggestions [09] |
| `c(a, "b")`, `+name`, `-name` | element-wise |
| other calls (`if (hard) opus else haiku`) | evaluated in an alias mask (known names bound to strings, parent = the caller); the mask's parent is reset to `emptyenv()` after evaluation (§6.4 R3) |

Model references containing a decimal typed as a symbol (`gpt5.1`) are echoed once; documents always receive
quoted canonical ids [09 §4.9].

#### 4.1.4 Prompt interpolation (NS-11)

Only literal prompts are interpolated, and only `{identifier}` where `identifier` is a syntactic name bound in
`envir` to an atomic vector of 1-50 elements (joined with `", "`, cut at 1,000 characters). `{{`/`}}` are
literal braces; code, JSON and unbound names are untouched; variables and `glue` objects are never
re-interpolated; `.opts$interpolate = FALSE` or `options(gptr.interpolate = FALSE)` disables it. The console
echoes the interpolated prompt; documents keep the template. Report 12 §2.D4 advised against automatic
interpolation; this narrow rule is the one all three proposals converged on. Token effect: about 10 tokens
instead of 60-120 for attaching `cl` and `top` as context [P-C §4.1.4].

#### 4.1.5 System 1 route (D-06)

Batch rule [04 §4.7]: an atomic vector gives one state per element (names kept); an unnamed list, one per
element; a data frame, one per row; a named list, one state; `I(x)`, exactly one state (the idiom for a
data-frame condition in `while()`, documented in the error hint). A piped session gives one state built by
`as_state(s)`: its last answer (at most 2,000 characters) plus value facts; no turn is added and a
`gptr.decision` custom entry is appended [G3 (12)]. Question type: `choices` -> choice, `levels` -> score,
else a boolean (wire name `noul`, never the public `bool` [04a]). Results: `gptr_decision` (logical),
`gptr_choice` (classed character; a factor only when `choices` is a factor or `.opts$output = "factor"`),
`gptr_score` (double), probabilities as attributes (§5.6). Choice labels that `if()` would read as logical
(`"TRUE"`, `"T"`, `"false"`) are rejected at request time [04 verification]. `threshold` (0.5) turns P(yes)
into TRUE/FALSE; abstention is **off by default**. `min_confidence` defines an uncertain band; `uncertain`
says what happens inside it: `NA`, `TRUE`, `FALSE`, `"stop"` (classed error) or `function(state, answer)`
(escalate, e.g. to a System 2 model or `ask`); this pair implements INFRA-18's `na_below`/`stop_below`.
Emulation through a System 2 model is opt-in only (`gptr_config(system1 = "emulate:<model>")`), never silent
and never offered non-interactively, and marks results uncalibrated [J-cran D-06].

#### 4.1.6 Sub-agents from the gateway

`agents =` is evaluated in a mask where `agent` is `gptr_agent` [15 §4.3]. `backend = "auto"` everywhere:
inline, except `cli` for CLI-only models (`claude_code`, `codex`) [15 verifier resolved]. `parallel = n` runs
one inline child per element, `n` at a time, each reading its element in place (`cohorts[["A"]]` by name, no
copy). Team and fan-out sessions are sessions (`kind = "team"`/`"fanout"`): `$text` joins the children's
reports under `### <name> (<model>)` headings, `$value` is the named list of child values, `$<name>` and
`[[` return child sessions, and piping the team continues it with the reports attached as a user-role
`<agent_reports>` block (sub-agent output is data) [P-A §6.12, P-C §5.1].

### 4.2 The gateway namespace `gptr$...`

Members are tool specs with `exposure = "r"` whose R function is written by hand or generated from the JSON
Schema. Model-written code and user code call them identically; calls made from model code pass the
permission gate as nested calls (§6.8.4); the `$` method has no side effects (connections happen lazily on
call, never on member access) [J-req graft]. When model code runs where the symbol `gptr` is not visible
(the user wrote `gptr::gptr()`), the evaluator rewrites calls headed by `gptr`/`gptr_return` to `gptr::` before
evaluation without binding anything in the user's environment; recorded code keeps the original text.

| Member | Signature | Returns / prints (budget) |
|---|---|---|
| `read` | `gptr$read(path, offset = NULL, limit = NULL)` | `gptr_lines` (character + attributes); Pi-format print |
| `write` | `gptr$write(path, content)` | path, invisibly |
| `edit` | `gptr$edit(path, edits, replace_all = FALSE)` | `gptr_patch` (message; diff in `details`) |
| `grep` | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"))` | `gptr_matches` data frame (file, line, text); print within 1,500 tokens |
| `find` | `gptr$find(pattern, path = ".", sort = c("path", "mtime", "size"), type = "file", limit = 1000L)` | `gptr_files` data frame (path, size, mtime) |
| `ls` | `gptr$ls(path = ".", sort = c("name", "mtime", "size"), long = FALSE)` | `gptr_files` |
| `sh` | `gptr$sh(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE, max_tokens = NULL)` | `gptr_cmd` (`$stdout`, `$stderr`, `$status`, `$ok`); head+tail print within 1,500 tokens [G5] |
| `script` | `gptr$script(path, args = character(), interpreter = NULL, ...)` | `gptr_cmd` |
| `bg`, `jobs` | `gptr$bg(cmd, name = NULL, stdin = FALSE, merge = TRUE)`, `gptr$jobs(kill = FALSE)` | `gptr_job` environment (`$read()`, `$wait(timeout, until)`, `$write()`, `$kill()`, `$status()`) |
| `out` | `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)` | full text of a truncated result (ids appear in truncation notices) |
| `py` | `gptr$py(code, name = NULL, max_rows = 10L)` | `gptr_py` (`$value` converts to R); reticulate (Suggests) |
| `sql` | `gptr$sql(query, name = NULL, con = NULL, n = 10L)` | data frame (all rows); prints dims + `n` rows; duckdb registration of named frames, else the DBI connection in scope |
| `knit` | `gptr$knit(engine, code)` | output of any knitr engine |
| `app` | `gptr$app(id, data = character(), title = NULL, kind = c("shiny", "html"), check = TRUE, launch = interactive())` | `gptr_artifact`; URL, checks, screenshot image for the model |
| `help` | `gptr$help(name, package = NULL, budget = 800L)` | tool schema (`"<server>/<tool>"`, member names) or R help text via `tools::Rd2txt`, budgeted |
| `search` | `gptr$search(words, limit = 8L)` | BM25 over members, plugin and MCP tools and skills |
| `describe` | `gptr$describe(x, budget = 150L)` | same as `gptr_describe()` |
| `plot` | `gptr$plot(width = 1000L, height = 700L)` | attaches the current plot at a larger size (about 900 tokens) |
| `mcp` | `gptr$mcp$<server>$<tool>(...)` | R values (lists, data frames); lazy connect |

Plugins add members with `gptr_tool(..., exposure = "r", namespace = "<pkg>")` reached as
`gptr$<pkg>$<tool>()`; one signature line each enters the frozen `<mcp>`/plugin catalog within its budget.

### 4.3 The other exports

**Setup and status** (9)

```r
gptr_init(path, instructions = TRUE, gitignore = TRUE)
gptr_config(..., .scope = c("session", "project", "user"))
gptr_env(path = ".env", aliases = NULL, set_env = TRUE, override = FALSE, quiet = FALSE)
gptr_trust(path = ".", trust = NULL)
gptr_login(provider, method = c("auto", "oauth", "key"))
gptr_logout(provider)
gptr_providers(check = FALSE)
gptr_models(query = NULL, provider = NULL, refresh = FALSE)
gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL,
                 scope = c("session", "project", "user"))
```

`gptr_init()` has no default path: a missing `path` asks "Create .gptr/ in <root>?" when a human is present
and errors otherwise [13 §2.3-2.4]; it writes `.gptr/` (vignette.Rmd template, settings.json, `.gitignore`,
`skills/`, `agents/`, `prompts/`) and *offers* (never silently writes) `^\.gptr$` for `.Rbuildignore` in a
package source. Creating `.gptr/` is consent to write there; it is not trust (`gptr_trust()` records trust
separately, §6.10). `gptr_config(model = sonnet, mode = manual)` takes bare identifiers; project scope may only
tighten security settings. `gptr_env()` maps `jev-key`, `JEV_KEY`, `JEV_API_KEY` and `TYPESAFE_KEY` to
`TYPESAFE_API_KEY`, registers every value in the vault, exports canonical names only and never prints values
[G6 §1.2]. `gptr_login()` covers MCP servers (`"mcp:<name>"`), OpenRouter PKCE and masked key entry into the
credential store. `gptr_providers()` shows credential sources as names and fingerprints only, CLI versions,
plan status and egress acknowledgements; `check = TRUE` makes cheap reachability checks.

**Discovery and MCP** (7)

```r
gptr_skills(scope = c("all", "project", "user", "packages"))
gptr_agents(scope = c("all", "project", "user", "packages"))
gptr_plugins(installed = FALSE)
gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)
gptr_mcp_add(name, command = NULL, args = character(), url = NULL, env = NULL, headers = NULL,
             exposure = "r", timeout = 60, scope = c("user", "project"))
gptr_mcp_remove(name, scope = c("user", "project"))
gptr_mcp_serve(tools = c("r", "read", "edit", "write"), envir = parent.frame(), port = NULL,
               stop = FALSE)
```

Listings are data frames with a token-cost column. `gptr_mcp()` lists gptr's own servers and those configured
for Claude Code, Claude Desktop, Codex, Cursor, VS Code and Pi (read-only; imported into gptr's `mcp.json` only
by `gptr_mcp_add()` or an explicit import), with era, status and tool counts. `gptr_mcp_serve()` serves the
live session over loopback Streamable HTTP (127.0.0.1, random port, 192-bit bearer token, Origin check,
permission gate; httpuv, later and openssl in Suggests) and returns a handle with `$url`, `$token_env`,
`$config` (client snippets) and `$stop()`.

**Documents and artifacts** (5)

```r
gptr_doc(path = NULL, format = NULL)
gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)
gptr_blocks(file)
gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp"))
gptr_artifacts(id = NULL, open = FALSE, stop = FALSE, version = NULL)
```

`gptr_doc()` binds the console session to a document (explicit consent to write it) or shows the binding.
`gptr_source()` regenerates stale or live blocks without executing the old block, which base `source()`
cannot do [14 §4.4.2]. `gptr_blocks()` lists blocks (id, prompt hash, fresh/stale/user-edited/undone, model,
date, tokens, cost). `gptr_artifacts()` without `id` is a data frame; with `id` it returns a `gptr_artifact`
handle, opening (`open = TRUE`), relaunching a `version`, or stopping (`stop = TRUE`) it.

**Session SDK** (15)

```r
gptr_step(s, turns = 1L)
gptr_wait(x, timeout = Inf)
gptr_steer(s, text, as = c("steer", "follow_up"))
gptr_cancel(x)
gptr_fork(s, at = NULL, envir = c("overlay", "shared"))
gptr_on(s, event, handler, matcher = NULL)
gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
gptr_map(.x, prompt, ..., model = NULL, agent = NULL, max_active = 4L, backend = "auto")
gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame())
gptr_last()
gptr_jobs(kill = FALSE)
gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)
gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"),
            force = FALSE, preview = FALSE)
gptr_checkpoints(s, all = FALSE)
```

`gptr_steer()` is the one enqueue function behind the pipe, the pause menu and `ctx$send()`. `gptr_fork()`
creates a new session whose store file copies the path to `at` (default: the last closed boundary) and whose
workspace is an overlay `new.env(parent = s$envir)` by default: reads are zero-copy, writes stay in the fork,
and nothing live (listeners, queues, connections, processes, locks, usage) is shared (INFRA-14) [G3 (6),
P-B §4.2]. `gptr_rewind()` is G7's branch-in-place on the same object (§6.16). `gptr_usage(detail = TRUE)`
returns the per-request token ledger. `gptr_parallel()` and `gptr_map()` return team and fan-out sessions.

**Agent-side and introspection** (6)

```r
gptr_return(x)
gptr_describe(x, budget = 150L, ...)
gptr_prob(x, what = c("prob", "confidence", "probabilities"))
gptr_risk(code, envir = NULL, root = NULL)
gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)
gptr_redact(x, profile = c("persist", "stream", "context", "code", "user_data"))
```

`gptr_return()` designates the run's result under the value policy of §5.1 and errors outside a run.
`gptr_describe()` is the S3 generic for compact descriptions (methods from any package through delayed
`S3method(gptr::gptr_describe, cls)`). `gptr_risk()` is the advisory static classifier; it never evaluates and
is documented as not a security boundary. `gptr_prompt()` shows a session's frozen system blocks, tool array
and first message with per-section token estimates.

**Extension API** (8)

```r
gptr_api()
gptr_register(spec)
gptr_registry(kind = NULL, diagnostics = FALSE)
gptr_reload()
gptr_check(x, error = FALSE)
gptr_fake_provider(script, name = "fake")
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
gptr_spec(kind, name, ...)
```

`gptr_api()` returns `list(version = package_version("1.0"), features = <character>)`. `gptr_register()`
registers at process lifetime (rank "user") and returns an unregister function invisibly; session scope is
`gptr(..., tools = list(spec))` (rank 0); inside a factory the verb is `gptr$register(spec)`. `gptr_registry()`
lists records with kind, name, source, rank, state (lazy, active, overridden, disabled) and an estimated
`tokens` column. `gptr_fake_provider()` returns a provider spec usable directly as `model = <spec>` or through
`gptr_register()`; every manual example uses it.

**Spec constructors** (11; the other kinds use `gptr_spec(kind, name, ...)`; contracts in §11.1)

```r
gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL,
          exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL,
          execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL,
          guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE,
          available = NULL, annotations = list())
gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
              type = c("chat", "classifier", "cli"), headers = list(), discover = NULL)
gptr_adapter(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"),
             build, parse = NULL, stream = NULL, classify = NULL, capabilities = list())
gptr_router(name, route, description = NULL)
gptr_hook(event, handler, matcher = NULL)
gptr_policy(name, check, description = NULL)
gptr_agent(name = NULL, description = NULL, model = NULL, tools = NULL, skills = NULL,
           system = NULL, backend = c("auto", "inline", "worker", "cli"), preset = "minimal",
           max_turns = NULL, mode = NULL, objects = NULL, export = NULL, returns = NULL, file = NULL)
gptr_command(name, handler, description = NULL, complete = NULL)
gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L)
gptr_context_block(name, provide, placement = c("turn", "first"),
                   authority = c("data", "operator"), budget = 300L)
gptr_backend(name, start, poll = NULL, cancel, capabilities = list())
```

### 4.4 Export summary

| Group | Count | Names |
|---|---|---|
| Gateway | 1 | `gptr` |
| Setup and status | 9 | `gptr_init`, `gptr_config`, `gptr_env`, `gptr_trust`, `gptr_login`, `gptr_logout`, `gptr_providers`, `gptr_models`, `gptr_permissions` |
| Discovery and MCP | 7 | `gptr_skills`, `gptr_agents`, `gptr_plugins`, `gptr_mcp`, `gptr_mcp_add`, `gptr_mcp_remove`, `gptr_mcp_serve` |
| Documents and artifacts | 5 | `gptr_doc`, `gptr_source`, `gptr_blocks`, `gptr_cache`, `gptr_artifacts` |
| Session SDK | 15 | `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_fork`, `gptr_on`, `gptr_parallel`, `gptr_map`, `gptr_sessions`, `gptr_resume`, `gptr_last`, `gptr_jobs`, `gptr_usage`, `gptr_rewind`, `gptr_checkpoints` |
| Agent-side | 6 | `gptr_return`, `gptr_describe`, `gptr_prob`, `gptr_risk`, `gptr_prompt`, `gptr_redact` |
| Extension API | 8 | `gptr_api`, `gptr_register`, `gptr_registry`, `gptr_reload`, `gptr_check`, `gptr_fake_provider`, `gptr_tool_result`, `gptr_spec` |
| Constructors | 11 | `gptr_tool`, `gptr_provider`, `gptr_adapter`, `gptr_router`, `gptr_hook`, `gptr_policy`, `gptr_agent`, `gptr_command`, `gptr_prompt_section`, `gptr_context_block`, `gptr_backend` |
