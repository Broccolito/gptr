
---

## 6. Cross-cutting mechanisms

### 6.1 Reactor and transport (D-13; INFRA-01/05/06/16/21/23)

```r
reactor_get()                                           # the process reactor
reactor_http(spec, on_headers, on_bytes, on_done, on_fail, run, provider)   # -> transfer id
reactor_proc(proc, on_line, on_exit, run)               # watch a processx child's pipes
reactor_timer(at, fn)                                   # retries, backoff, idle checks, first-byte timers
reactor_enqueue_tool(run, call)                         # FIFO: one R-evaluating tool at a time
reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL)
reactor_cancel(ids)                                     # multi_cancel; interrupt children, grace, kill_all
```

One iteration: admit queued transfers while global (`max_active`, default 8) and per-provider slots allow;
`processx::poll(c(processx::curl_fds(curl::multi_fdset(pool)), <live pipes>), ms = min(next timer, slice))`;
`curl::multi_run(timeout = 0)`; read ready pipes (at most 512 chunks each; lines reassembled up to 16 MiB);
fire due timers; if `later` is loaded, `later::run_now(0)` (services httpuv servers such as `gptr_mcp_serve()`
and OAuth callbacks; never `httpuv::service()` [16]); run at most one queued R tool whose run is in
`allow_runs` (all runs when `NULL`); loop. The reactor is the only blocking wait in gptr [15 §4.1-4.2].

Every curl handle sets `pipewait = 0L` (since curl 6.1.0 PIPEWAIT serialises HTTP/1.1 streams on a shared
pool: 3.4 s vs 2.3 s [15 §2.2]), `connecttimeout = 20`, `low_speed_limit`/`low_speed_time` as a backstop, and
no total timeout; the reactor enforces a first-byte timer (default 120 s) and an idle timer (default 90 s)
with classed failures `gptr_error_timeout_first_byte`/`_idle` [10a INFRA-05]. Header values that are secret
handles are materialised only in `http-request.R`, only for the provider's configured origin (§6.5).

**Retry** [10a INFRA-06, 07 §4, 04 §2.16]: before any delta is committed, retry 408, 409, 429, 5xx, 529 and
network errors, and an overload event before the first delta; honour `retry-after-ms`, then `retry-after`,
capped by `max_retry_delay = 60` s (fail fast above it with the server's value in the error); otherwise
`0.5 s * 2^i` with time-derived jitter (never the RNG), capped at 8 s, at most 4 attempts; never retry
Anthropic's spend-cap 429 (`enforced_spend_limit_reached`). Waits are interruptible and emit
`retry_start/end`. Agent level: at most 2 retries (2 s, 4 s) of classified transient errors after committed
deltas [02 §2.8]. System 1: at most 3 bounded rounds resubmitting failed elements only [04 §4.7]. Nothing uses
`httr2::req_perform_parallel()`, which retries 429/503 without bound.

**Rate limits** [10a INFRA-21]: `anthropic-ratelimit-*` and `x-ratelimit-*` headers feed a per-provider token
bucket that gates admission; a fan-out never sleeps inside an HTTP callback.

**Decoding** [10a INFRA-23, 21 §2.6]: SSE and NDJSON are split on raw bytes with `grepRaw()` boundaries,
carrying the incomplete tail; each complete event is decoded with `rawToChar()`, marked UTF-8 and parsed; a
final unterminated event is flushed (httr2's `resp_stream_sse()` drops it [08 fact-check]); deltas accumulate
in preallocated lists joined once. Measured 23-29 us per event, 17x faster than `resp_stream_sse()`.

**Process-level, not per-call.** The reactor is one per R process because pools and fds are process resources
and experimental background runs must share it [G3 (5)]. It holds strong references only to active runs,
which drop out at settlement; run state lives in sessions (INFRA-15). Nested runs re-enter
`reactor_pump(allow_runs = <nested run>)` (§2.3).

### 6.2 Streaming, interrupts and steering (S-8, INFRA-03/12)

**One queue per session** with `steer` and `follow_up` FIFOs [G1 §4.6, G3 (4)]. Producers: the pipe into a
running session (gateway route f), the console pause menu, `gptr_steer()` (SDK and front ends), `ctx$send()`
(plugins, hooks and sibling agents). Consumer: the loop polls at run start, after `turn_end` and after tool
preflight; a steer is delivered only after the **complete** tool-result message, as an operator relay "The user
sent this message while you were working: <text>"; follow-ups are taken one at a time when the agent would
otherwise stop. Abort moves the queue to `dropped`. Enqueueing returns immediately. There is no file-inbox
channel in core (J-cran K-16); a front end that needs one is a plugin calling `gptr_steer()`.

**Interrupt policy** [18 §4.6, 02 §5.4, G3 (5)]. Runs execute inside
`tryCatch(withCallingHandlers(<run>, interrupt = pause_menu), interrupt = abort_run)`. The pause menu uses R's
`resume` restart: `[s]teer`, `[f]ollow-up`, `[c]ontinue`, `[a]bort`, and `[b]ackground` (foreground calls
only, experimental); a second Ctrl-C aborts. Menu output goes to stderr (the handler may run inside a tool's
stdout capture) and tools record interruption with `on.exit()`, never with an exiting `tryCatch(interrupt =)`
that would pre-empt the menu (G3 menu fixes). Where the resume restart is unavailable or unverified (Rgui,
IDE consoles), the policy falls back to abort-only. Abort: `curl::multi_cancel()`, interrupt then `kill_all()`
child trees after a grace period, record the partial with `stop_reason = "aborted"`; the REPL returns to its
prompt; programmatic calls re-signal the interrupt. While the menu waits streams are not polled, so
`continue` retries a request the provider dropped [18 risk].

**Background sessions (experimental)**. `gptr(..., background = TRUE)` returns a running session at once;
`later` callbacks pump the reactor while the console is idle (timer polling every 50 ms; no `later_fd`, which
cannot watch processx pipes on Windows [15 verifier]). A SIGINT inside a later callback reaches the same
calling handler, so the pause menu works [G3 p6]. Piping into the running session steers it; `gptr_wait()`,
`gptr_cancel()` and `gptr_jobs()` operate on it. R tools of background runs execute at idle ticks (the console
is busy for their duration; `options(gptr.background_tools = "wait")` defers them to `gptr_wait()`). Under
Rscript there is no idle console: background runs progress only inside blocking gptr calls. Support matrix
documented: terminal R verified [G3 t9]; RStudio, Positron, Jupyter and Windows consoles unverified. Requires
`later`; never used in examples or CRAN tests.

### 6.3 Errors and conditions

```r
gptr_abort(message, class, ..., .data = NULL, call = NULL)
# -> condition of class c(paste0("gptr_error_", class), "gptr_error", "error", "condition")
gptr_warn(message, class, ...)     # c("gptr_warning_<class>", "gptr_warning", "warning", "condition")
gptr_inform(message, class, ...)   # c("gptr_message_<class>", "gptr_message", "message", "condition");
                                   # suppressed by options(gptr.quiet = TRUE)
```

- **Rule C1 (format strings).** Untrusted text (model replies, provider error bodies, tool and MCP output,
  file contents, user object descriptions) is never used as a cli or glue format string. It is printed with
  `cli::cli_verbatim()` or passed as an interpolated variable (`cli::cli_text("{x}")`); `gptr_abort()`,
  `gptr_warn()`, `gptr_inform()` and `gptr_redact()` build condition messages by plain concatenation and never
  glue-interpolate them. J-cran reproduced `cli::cli_text(reply)` executing `Sys.setenv()` embedded in a reply
  [13 C-36; judge-cran/cli_inj.R]. Enforced by `test-injection-e2e.R` and a lint check that no `cli_*()` call
  in `R/` takes a non-literal first argument.
- **Never-throw boundaries.** Adapters turn failures after `start` into `error` events (INFRA-02); the tool
  dispatcher turns unknown tools, validation failures, denials, R errors, warnings under `warn = 2`, timeouts
  and interrupts into `is_error` results (INFRA-10); notify and patch hook errors become registry diagnostics;
  fail-closed hooks deny or block.
- **Principal classes:** `noninteractive`, `permission` (fields `action`, `how_to_allow`), `provider` (fields
  `status`, `request_id`, `session`), `timeout_first_byte`, `timeout_idle`, `budget_tokens`, `budget_cost`,
  `budget_turns`, `max_turns`, `split_brain`, `readonly`, `busy`, `stale_api`, `missing_package`, `no_key`,
  `egress`, `untrusted`, `not_recorded`, `s1_<kind>`, `token_regression`, `invalid_spec`; warnings
  `rewind_partial`, `deprecated`.
- Every message passes `redact()`; tracebacks shown to the model are trimmed and redacted.

### 6.4 Copy-safety invariant (headline benefit 1)

A multi-GB object must stay editable in place after any gptr call. R lowers reference counts only in setters
and `rm()`, never in garbage collection, and releases a function frame at return only if nothing references it
[G3 (8); G7 §1.1; R 4.4.3 and trunk identical]. So anything gptr keeps that points at a user object or a user
frame makes the user's next in-place edit copy the whole object. Rules:

| # | Rule | Evidence |
|---|---|---|
| R1 | Never hold a user object in a list, closure, attribute or environment gptr keeps. Designated values follow the value policy of §5.1 (large bound objects by name). | judge check `session_holds_value` -> COPY, `session_holds_name` -> in place |
| R2 | Never hold a user function frame beyond the active run, and never in a list, closure, attribute or weak reference (key or value). The home frame lives only in an environment binding of the run environment, reset to `NULL` at settlement before the run is dropped. Keep address strings, not frames (e.g. the pending-plan key). | [final/frame_hold_check.R]: weakref key COPY, list-then-drop COPY, address string and reset binding in place; G3 p2 and fact-check adv4/adv5 |
| R3 | Gateway capture is base R: no rlang quosures in any frame that sees user frames; dots reach only leaf functions through `...elt(i)` in `while` loops; no closures, `tryCatch`, `withCallingHandlers` or `match.arg` in a frame that holds `...` or the home; never assign to a formal (use new locals); helpers force their arguments on entry; adapters are called through `do.call()` with forced values; frames walked with `sys.frame(k)`, never `sys.frames()`; alias masks get `parent.env<-` `emptyenv()` after use. | [final/capture_check.R]: `enquos` COPY, `...elt` leaf in place; G3 p5b, p5i, p5n, p5o |
| R4 | Introspection through leaf functions returning primitives only (class, dim, length, typeof, address, `object.size()` cached by address); gptr never calls `str()` on user objects (sticky [12 §2.C]); describers follow the same discipline. | 12 §2.C, §3.9 |
| R5 | No binding locks anywhere (`lockBinding()`/`unlockBinding()` makes the next edit copy). | judge `lock` case, PB-E1, P-A exp |
| R6 | No `mget()` or list snapshots of user objects. Checkpoint pre-images are bindings in a private environment released with `rm()`; list and S4 pre-images are defused before dropping; a finalizer does the same for dropped sessions. | G7 §1.1 (c03) |
| R7 | Every `serialize()`/`saveRDS()` of user data passes `ascii = FALSE` explicitly (the default path leaves a sticky reference) through one leaf wrapper. | G7 §1.5 |
| R8 | The evaluator prints symbols with `print(<sym>)` evaluated in `envir`; assignments, loops and `invisible()` never pass through `withVisible()`; the value of an evaluation is never kept. | 12 §2.C2, §4.3 |
| R9 | Bridges that hand objects to other runtimes (reticulate, duckdb registration) cause one copy on the next edit; this is documented, and happens only for objects the model or user passes by name. | G5 fact-check 22 |
| R10 | Package-level indexes (live sessions, `gptr_last()`) hold weak references keyed on session shells, which hold no frames. | G3 (2), p1 |

**Test.** A fresh-process tracemem suite (`test-copy-*.R`, helper `expect_no_copy()`) covers every entry
point: the gateway shapes of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded dots,
alias and `if/else` models, System 1 on data and on a session, fork, parallel, background, `saveRDS`), `$value`
reads, **tool code executed in a function-frame home** (the G3 fact-check case), namespace members, checkpoint
pre-images, artifact snapshots and bridges. It runs on R-release and R-devel in CI and is skipped on CRAN and
without `capabilities("profmem")`.

### 6.5 Secrets and redaction (D-22; INFRA-22) [G6]

- **Vault and handles.** Secret values live only in a package-private vault. Sessions, requests, provider
  configs, sub-agent and MCP specs hold `gptr_secret` handles (name + 6-hex sha256 fingerprint). Only the
  innermost transport (`http-request.R`) and the child-environment builders call `secret_value(handle,
  origin)`. No function takes a secret value as an argument, so tracebacks and dumps show handles.
- **Origin binding.** A handle materialises only for its provider's configured base URL (built-in or
  user-level config, or an explicit argument). A project-level base-URL override needs trust plus a one-time
  confirmation; URLs coming from models, documents or MCP servers never receive credentials.
- **Sources.** Explicit `gptr_env()` (exports canonical names only); ambient discovery of secret-like
  environment variables at session start; `Sys.setenv()` of secret-like names inside `r` registered after the
  evaluation; automatic `.env` discovery is vault-only and only in trusted projects; the credential store
  `R_user_dir("gptr", "config")/auth.json` (mode 0600 on Unix, documented Windows ACL caveat, optional keyring
  references; access tokens in memory only). gptr never reads other harnesses' credential files
  (`~/.claude`, `~/.codex/auth.json`). Plugins add sources with `secret_source` specs.
- **One redactor at every sink** with profiles `persist` (JSONL, documents, caches, spill files, wire log,
  checkpoints), `context` (egress to providers), `stream` (console, events), `code` (a literal secret in
  recorded code becomes `Sys.getenv("NAME")`) and `user_data`. Registered values and derived forms
  (URL-encoded, JSON-escaped, base64 cores) plus 12 gitleaks-derived patterns (including `PRIVATE KEY(?:
  BLOCK)?` [G6 fact-check]) and a `NAME=value` rule; markers `[secret:NAME]` (6-10 tokens vs 26-104 for a real
  key). Streaming uses a bounded hold-back (identical to whole-text redaction over 1,400 random chunkings).
  Redaction happens at ingress only; stored history is never rewritten (preserved thinking, caches). Value
  redaction cannot be disabled; the pattern layer can.
- **Child environments** (`auth-childenv.R`): `mcp` (strict allowlist plus the spec's env); `worker`
  (allowlist through `NA` unsets plus only its provider's key, `R_ENVIRON_USER` and `R_PROFILE_USER` pointing
  at empty files, `user_profile = FALSE`, never keys through callr `args` [G6 fact-check]); `cli-claude` and
  `cli-codex` (inherit minus secret-like names and registered values, minus the billing-switch variables
  `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_*`, `OPENAI_API_KEY`, `CODEX_API_KEY`, with a
  warning naming them); `helper` (bridges: inherit minus secrets, explicit `pass =`); `artifact`
  (secret-free, empty `R_ENVIRON_USER`, because the child runs model-written code).
- **Classifier secret guard.** Reading a registered key, dumping the environment (`Sys.getenv()`,
  `env`/`printenv`) or touching the vault is level 3 with a guard that asks even in `auto` and denies without
  a UI; a secret source plus a network sink in one evaluation (or through a tainted variable later) is level
  4; a literal `[secret:` marker in code is rejected before evaluation with a `Sys.getenv()` hint.
- **Test.** `test-secrets-e2e.R` pushes fake keys through print, message, warning, a spill-sized dump,
  `Sys.setenv`, a worker, an MCP child, a CLI stand-in, a 401 echo and a wrong-origin send, then greps every
  sink: 0 occurrences with redaction, a negative control finds them without it (G6: 0 vs 518).

### 6.6 Encoding

All text that crosses a boundary is UTF-8 and marked: `Encoding(x) = "UTF-8"` before `jsonlite::fromJSON()`
and before `toJSON()` (both corrupt unmarked non-ASCII in a C locale [07 fact-check, 08]); JSONL is written as
bytes (`writeLines(enc2utf8(x), con, useBytes = TRUE)` on a binary connection, LF only); `canonical_json()`
sorts keys with `method = "radix"` (locale-independent cache keys [14 fact-check]); argv, working directory
and environment strings for children pass through `os_bytes()`; child output is read from redirected files
and decoded by gptr as UTF-8 with a code-page fallback (the Windows fallback page is UNCERTAIN [G5 fact-check]).
R sources are ASCII (conventions §4). `Depends: R (>= 4.2.0)` gives UTF-8 as the native encoding on current
Windows 10/11 [13 fact-check]; gptr warns once when `l10n_info()[["UTF-8"]]` is FALSE. The console renderer
receives UTF-8-marked strings (width checks fail otherwise [18 fact-check]). A CI job runs the suite under
`LC_ALL=C`.

### 6.7 Processes and Windows [G5; 16 §6.2; 13 §2]

- One process engine (`proc-spawn.R`) for bridges, MCP stdio servers and CLI providers:
  `processx::process$new()` with stdout/stderr redirected to temp files, never `processx::run()` (its
  `cat()`-based buffer corrupts non-ASCII output in a C locale and its interrupt handler calls
  `invokeRestart("abort")` [G5, J-impl prun.R]); a `p$wait(200)` loop with a hard timeout and
  `on.exit(kill_all(p))`; stdin is the null device unless `input =` is given (large inputs always on stdin:
  32,767-character command-line limit); `write_all()` loops `write_input()`, which silently truncates above
  8 KB [08 fact-check].
- `kill_all()`: `kill_tree()`, then on Windows `taskkill /F /T /PID` while the parent is alive, then
  `$kill()` (process group); `kill_tree()` alone misses SIP-protected binaries on macOS [G5 fact-check 3].
- Windows: argv form needs no shell; string commands resolve Git Bash (`ProgramFiles`, `ProgramW6432`,
  `LOCALAPPDATA`; never `System32\bash.exe`), then PowerShell (`-NoProfile -NonInteractive -ExecutionPolicy
  Bypass -EncodedCommand <base64 UTF-16LE>` with a `$LASTEXITCODE`-preserving postfix), then `cmd /d /s /c
  "chcp 65001 >nul & ..."`; `.cmd`/`.bat` shims (npx, uvx, npm CLIs) run as `cmd.exe /d /c call <shim> args`
  refusing `% ^ & | < > " !` CR LF in arguments (BatBadBut) instead of refusing shims; native `claude.exe` and
  `codex.exe` are preferred; WindowsApps Python stubs skipped (UNCERTAIN).
- Child environment adds `NO_COLOR=1`, `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`,
  `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1` to the `helper` profile.
- R children are started through callr (Rscript path, libpaths and `_R_CHECK_R_ON_PATH_` handled [13 §1 item
  14]); `supervise` follows `gptr.supervise` (FALSE in examples: supervisor fifos are a fatal check error
  [13 §2.10]); process tables are cleaned in `.onUnload` and by finalizers.

### 6.8 Permission model (D-11; INFRA-11) [18 §3.7-4.7]

#### 6.8.1 Modes and levels

| Level | Meaning (classifier) | plan | manual (default) | edits | auto |
|---|---|---|---|---|---|
| 0 | read-only R, reads inside the project, namespace reads | allow | allow | allow | allow |
| 1 | new objects, reads outside the project | R in a scratch child env (discarded); other tools deny | ask | ask | allow |
| 2 | overwriting objects, workspace file writes, network reads, reference mutation | deny | ask | allow `write`/`edit` inside the project, ask for R | allow |
| 3 | deletes, processes, installs, overwriting objects above `gptr.protect_size` (100 MB), dynamic code, secret reads, app launches | deny | ask | ask | allow (the secret guard still asks) |
| 4 | critical: `q()`, deleting home/root/project/top-level/drive roots or their parents, secret + network sink | deny | ask | ask | ask (blocked without a UI) |

`r` is classified per flagged call by `gptr_risk()` (tables in `inst/extdata/risk-functions.csv` and
`risk-commands.csv`, extendable by plugins); `gptr$sh/script/bg` by the command classifier; `gptr$py`/`sql`
by token and keyword classifiers [G5 §5]; MCP tools by server annotations (untrusted unless the server is
trusted: `readOnlyHint` 0, `destructiveHint = FALSE` 2, none 3); nested `gptr()` inherits and only tightens;
`ask` is level 0. The classifier is advisory and documented as not a security boundary; in-process R cannot
be sandboxed [18 §2.5].

#### 6.8.2 Gate order

`perm_check(call, run)` -> `list(decision = "allow" | "deny" | "ask" | "modify", reason, input, risk)`:
every `policy` record (deny > ask > modify > allow; a throwing policy denies) -> `permission_request` hooks
(first decision; a System 1 reviewer plugin may answer an ask) -> the UI backend. Built-in policies: `mode`,
`rules` (grammar `tool(spec)`, e.g. `write(results/**)`, `r(fn:write.csv)`, `r(level<=1)`, `r(sh:git
status*)`, `r(sql:select)`), `critical_guard`, `secret_guard`, `protect_size`. Allow rules never loosen plan
and never pre-approve level 4; project settings may only tighten; project filters cannot disable user or
built-in policies or hooks [G1 §3.6]. `modify` changes the arguments the tool sees and is recorded.

#### 6.8.3 The prompt

One line (NS-1): `allow? [y]es / [a]lways / [n]o / [?]`. `a` adds a session rule covering exactly the flagged
calls (`r(fn:FindNeighbors,FindClusters)`); `?` opens the detail view (code, flagged calls with levels, paths,
"cannot be undone" when no checkpoint is possible, and "always in this project", written to
`.gptr/settings.local.json`); `n` optionally takes feedback text that becomes the tool result; Ctrl-C aborts
the run. Never `askYesNo()`, `menu()` or `select.list()` for gptr's own prompts [18 §2.1].

#### 6.8.4 Nested gating

A `gptr$...` call made while an `r` evaluation runs enters `dispatch_nested()`: if the static analysis of the
outer code listed the same function at a level no higher than the level the user approved for the outer call,
it runs without a second prompt; otherwise it passes the gate. Computed commands are level 3 and re-checked at
run time. Nested calls are recorded in the outer result's `details$nested` (at most 20) [06 §4, G5 §5].

#### 6.8.5 Non-interactive runs and plan mode (NS-12)

An `ask` with no human stops the run with `status = "blocked"` and a classed `gptr_error_permission` stating
the action and how to allow it (`mode = auto`, a rule, or `gptr_permissions()`); the session is attached to
the condition. `options(gptr.noninteractive_ask = "deny")` returns a denial to the model instead [P-A §6.7].
Plan mode (`mode = plan`) uses the `readonly` preset: `read`, and `r` evaluated in a scratch
`new.env(parent = envir)` where level-1 code may run and nothing persists; writes are denied. The final answer
contains one `<proposed_plan>` block; it is saved to `<root>/plans/<date>-<slug>.md` and becomes the session's
**pending plan**. The next non-plan `gptr()` call in the same environment (matched by an address string, never
a reference, R2) within the same R process and one hour receives it once as a `<plan>` block, with the notice
"using the plan from session <id>", and its block header records `plan=<id>`. Interactively the plan run ends
with "Execute: [a]uto / [e]dits / [m]anual / [k]eep planning", which continues the same session.
`options(gptr.plan_handoff = FALSE)` disables the hand-off [P-C §9.4].
