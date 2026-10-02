from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""```r
reactor_get()                                           # the process reactor
reactor_http(spec, on_headers, on_bytes, on_done, on_fail, run, provider)   # -> transfer id
reactor_proc(proc, on_line, on_exit, run)               # watch a processx child's pipes
reactor_timer(at, fn)                                   # retries, backoff, idle checks, first-byte timers
reactor_enqueue_tool(run, call)                         # FIFO: one R-evaluating tool at a time
reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL)
reactor_cancel(ids)                                     # multi_cancel; interrupt children, grace, kill_all
```""",
"""```r
reactor_get()                                           # the process reactor
reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL, retry = NULL)
reactor_proc(proc, on_line, on_exit, run = NULL, stream = "stdout", on_stderr = NULL)
reactor_timer(at, fn, run = NULL)                       # retries, backoff, idle checks, first-byte timers
reactor_enqueue_tool(run, fn)                           # FIFO: one R-evaluating tool at a time
reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)
reactor_cancel(ids)                                     # multi_cancel; interrupt children, grace, kill_all
```

(Indicative; the contract §8.2 fixes these signatures.)"""),
("""`curl::multi_run(timeout = 0)`; read ready pipes (at most 512 chunks each; lines reassembled up to 16 MiB);
fire due timers; if `later` is loaded, `later::run_now(0)` (services httpuv servers such as `gptr_mcp_serve()`
and OAuth callbacks; never `httpuv::service()` [16]); run at most one queued R tool whose run is in
`allow_runs` (all runs when `NULL`); loop. The reactor is the only blocking wait in gptr [15 §4.1-4.2].""",
"""`curl::multi_run(timeout = 0)`; read ready pipes (at most 512 chunks each; lines reassembled up to 16 MiB) and
drain pending stdin buffers; fire due timers; if `later` is loaded and the pump is the outermost one (or waits for
a CLI child served by gptr's MCP server), `later::run_now(0)` (services httpuv servers such as `gptr_mcp_serve()`
and OAuth callbacks; never `httpuv::service()` [16]); run at most one queued R tool whose run is in
`allow_runs` (all runs only when no run is on the stack [IC-57]); loop. The reactor is the only blocking wait in
gptr [15 §4.1-4.2]."""),
("""Every curl handle sets `pipewait = 0L` (since curl 6.1.0 PIPEWAIT serialises HTTP/1.1 streams on a shared
pool: 3.4 s vs 2.3 s [15 §2.2]), `connecttimeout = 20`, `low_speed_limit`/`low_speed_time` as a backstop, and
no total timeout;""",
"""Every curl handle sets `pipewait = 0L` (since curl 6.1.0 PIPEWAIT can serialise every HTTP/1.1 stream on a shared
pool: the fact-check measured 4.94-5.11 s for four 1.2 s streams with the default pool vs 1.25-1.36 s with the fix
[15 §2.2 and fact-check; IC-71]), `followlocation = 0L` (libcurl forwards custom key headers across origins on a
redirect; a 3xx is a classed error, never followed [IC-64]), `connecttimeout = 20`,
`low_speed_limit`/`low_speed_time` as a backstop, and no total timeout;"""),
("""**Rate limits** [10a INFRA-21]: `anthropic-ratelimit-*` and `x-ratelimit-*` headers feed a per-provider token
bucket that gates admission; a fan-out never sleeps inside an HTTP callback.""",
"""**Rate limits** [10a INFRA-21]: `anthropic-ratelimit-*` and `x-ratelimit-*` headers, and the provider record's
static `rate` (Jev sends no headers; 40 requests and 100K tokens per second [04 fact-check]; IC-64), feed a
per-provider token bucket that gates admission (System 1 admission is process-wide); a fan-out never sleeps inside
an HTTP callback. HTTP-date `retry-after` values are parsed locale-independently [02 fact-check]."""),
("""**Decoding** [10a INFRA-23, 21 §2.6]: SSE and NDJSON are split on raw bytes with `grepRaw()` boundaries,
carrying the incomplete tail;""",
"""**Decoding** [10a INFRA-23, 21 §2.6]: SSE and NDJSON are split on raw bytes with `grepRaw()` boundaries,
carrying the incomplete tail, following the SSE specification (LF, CRLF and lone CR line ends with a CR held across
chunks, BOM stripped, the last `event:` wins [21 fact-check; IC-64]);"""),
("""(plugins, hooks and sibling agents). Consumer: the loop polls at run start, after `turn_end` and after tool
preflight; a steer is delivered only after the **complete** tool-result message, as an operator relay "The user
sent this message while you were working: <text>"; follow-ups are taken one at a time when the agent would
otherwise stop.""",
"""(plugins, hooks and sibling agents). Consumer: the loop polls at run start, after `turn_end` and after tool
preflight; a steer is delivered only after the **complete** tool-result message. Only user sources (the pipe, the
pause menu, the REPL, `gptr_steer()` called outside a run) become the operator relay "The user sent this message
while you were working: <text>"; `ctx$send()` from a plugin becomes user-role data "Extension <name> sent this note
(not from the user): <text>", sibling and child agents' text arrives as `<agent_report>` data, and a send from
model code of the same session tree is refused [IC-55]. Follow-ups are taken one at a time when the agent would
otherwise stop."""),
("""`gptr(..., background = TRUE)` returns a running session at once;
`later` callbacks pump the reactor while the console is idle (timer polling every 50 ms; no `later_fd`, which
cannot watch processx pipes on Windows [15 verifier]).""",
"""`gptr(..., background = TRUE)` returns a running session at once;
`later` callbacks pump the reactor while the console is idle (timer polling every 50 ms; the pump is a no-op while
the reactor is already on the stack [IC-57]; no `later_fd`, which LIKELY cannot watch processx pipes on Windows,
inferred from its documentation and untested [15 verifier]). An ask raised by a background run never prompts from
a callback: the session moves to status `waiting` and the question is shown at the next blocking gptr call."""),
("""- **Principal classes:** `noninteractive`, `permission` (fields `action`, `how_to_allow`), `provider` (fields
  `status`, `request_id`, `session`), `timeout_first_byte`, `timeout_idle`, `budget_tokens`, `budget_cost`,
  `budget_turns`, `max_turns`, `split_brain`, `readonly`, `busy`, `stale_api`, `missing_package`, `no_key`,
  `egress`, `untrusted`, `not_recorded`, `s1_<kind>`, `token_regression`, `invalid_spec`; warnings
  `rewind_partial`, `deprecated`.""",
"""- **Principal classes** (the complete list is the contract's §2.2): `noninteractive`, `permission` (fields
  `action`, `how_to_allow`), `provider` (fields `status`, `request_id`, `session`; subclasses incl. `redirect`,
  `billing`), `timeout_first_byte`, `timeout_idle`, `budget_tokens`, `budget_cost`, `budget_turns`, `max_turns`,
  `split_brain`, `readonly`, `busy`, `stale_api`, `missing_package`, `no_key`, `egress`, `untrusted`,
  `not_recorded`, `replay_unbound`, `secret_found`, `s1_<kind>`, `token_regression`, `invalid_spec`; warnings
  `rewind_partial`, `deprecated`, `secret_late`."""),
("""| R3 | Gateway capture is base R: no rlang quosures in any frame that sees user frames; dots reach only leaf functions through `...elt(i)` in `while` loops;""",
"""| R3 | Gateway capture is base R: no rlang quosures in any frame that sees user frames; a plain-symbol dot is read by name through a `get0()` leaf and its promise is never forced (a forced promise keeps the value referenced by the gateway frame for the whole run, so an in-run edit copies [IC-41]); other dots reach only leaf functions through `...elt(i)` in `while` loops;"""),
("""| R4 | Introspection through leaf functions returning primitives only (class, dim, length, typeof, address, `object.size()` cached by address); gptr never calls `str()` on user objects (sticky [12 §2.C]); describers follow the same discipline. | 12 §2.C, §3.9 |""",
"""| R4 | Introspection through leaf functions returning primitives only (class, dim, length, typeof, address, `object.size()` cached by address); gptr never calls `str()` on user objects (sticky [12 §2.C]) and no shipped prompt or skill tells the model to (a P07 test checks the texts [IC-67]); describers follow the same discipline. | 12 §2.C, §3.9; `str(big)` re-verified to copy on the next edit |"""),
("""| R8 | The evaluator prints symbols with `print(<sym>)` evaluated in `envir`; assignments, loops and `invisible()` never pass through `withVisible()`; the value of an evaluation is never kept. | 12 §2.C2, §4.3 |""",
"""| R8 | The evaluator prints symbols with `print(<sym>)` evaluated in `envir`; assignments, loops and `invisible()` never pass through `withVisible()`; every `withVisible()` result is cleared in place (`res[1L] = list(NULL)`) before its frame returns, because a result aliasing a user object (`L$a`, `(x)`, `get("x")`) otherwise makes the next edit copy; the value of an evaluation is never kept. | 12 §2.C2, §4.3; review wv4/wv6 (1 copy before, 0 after) [IC-67] |"""),
("""| R10 | Package-level indexes (live sessions, `gptr_last()`) hold weak references keyed on session shells, which hold no frames. | G3 (2), p1 |""",
"""| R10 | The live-session index holds weak references keyed on session shells, which hold no frames; `gptr_last()` holds the most recent shell strongly (a weak one is collected at the first `gc()`, verified), which is copy-safe because shells hold no frames or user objects. | G3 (2), p1; [IC-71] |"""),
("""point: the gateway shapes of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded dots,
alias and `if/else` models, System 1 on data and on a session, fork, parallel, background, `saveRDS`), `$value`
reads, **tool code executed in a function-frame home** (the G3 fact-check case),""",
"""point: the gateway shapes of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded dots,
alias and `if/else` models, System 1 on data and on a session, fork, parallel, background, `saveRDS`), **in-run
edits of the attached object** (`gptr("x", big)`, `big |> gptr("x")`, `s |> gptr("x", big)` [IC-41]), evaluator
results aliasing user objects (`L$a`, `(x)`, `get("x")`, `x@slot`, `x[["a"]]` [IC-67]), `$value` reads, **tool code
executed in a function-frame home** (the G3 fact-check case),"""),
("""  key). Streaming uses a bounded hold-back (identical to whole-text redaction over 1,400 random chunkings).
  Redaction happens at ingress only; stored history is never rewritten (preserved thinking, caches). Value
  redaction cannot be disabled; the pattern layer can.""",
"""  key). Streaming uses a bounded hold-back (identical to whole-text redaction over 1,400 random chunkings).
  Redaction happens at ingress; stored history is not rewritten (preserved thinking, caches) except by the user's
  explicit `gptr_scrub(dry_run = FALSE)`, which cleans files that captured a secret before it was registered;
  `secret_register()` warns when a new value already occurs in live sessions [G6 §4.7; IC-70]. Child output (MCP
  stderr, artifact logs) is persisted only after gptr reads and redacts it; MCP logs live in `tempdir()` unless
  debugging is on. Value redaction cannot be disabled; the pattern layer can."""),
("""- **Child environments** (`auth-childenv.R`): `mcp` (strict allowlist plus the spec's env); `worker`
  (allowlist through `NA` unsets plus only its provider's key, `R_ENVIRON_USER` and `R_PROFILE_USER` pointing
  at empty files, `user_profile = FALSE`, never keys through callr `args` [G6 fact-check]); `cli-claude` and
  `cli-codex` (inherit minus secret-like names and registered values, minus the billing-switch variables
  `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_*`, `OPENAI_API_KEY`, `CODEX_API_KEY`, with a
  warning naming them); `helper` (bridges: inherit minus secrets, explicit `pass =`); `artifact`
  (secret-free, empty `R_ENVIRON_USER`, because the child runs model-written code).""",
"""- **Child environments** (`auth-childenv.R`), returned as complete vectors without the removed names (processx
  rejects `NA`; callr gets `child_env_callr()` with `NA` unsets) and with `R_ENVIRON_USER` and `R_PROFILE_USER`
  pointing at empty files and `R_ENVIRON` dropped in **every** profile, because any Rscript child otherwise re-reads
  keys from `~/.Renviron` [G6 fact-check; IC-60]: `mcp` (strict allowlist plus the spec's env); `worker` (allowlist
  plus only its provider's key, `user_profile = FALSE`, never keys through callr `args`); `cli-claude` and
  `cli-codex` (G6 §3.7 verbatim [IC-65]: inherit minus secret-like names, registered values and the enclosing-agent
  variables `CLAUDECODE`, `CLAUDE_CODE_*` (except the kept OAuth token, config dir and Git Bash path),
  `CLAUDE_AGENT_SDK_*`, `CLAUDE_PID`, `CODEX_MANAGED_*`, `CODEX_SANDBOX*`, and minus the billing-switch variables
  `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`, `CLAUDE_CODE_USE_*`, `OPENAI_API_KEY`,
  `OPENAI_BASE_URL`, `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, with a warning naming them); `helper` (bridges: inherit
  minus secrets, explicit `pass =`); `artifact` (secret-free, because the child runs model-written code)."""),
("""- **Test.** `test-secrets-e2e.R` pushes fake keys through print, message, warning, a spill-sized dump,
  `Sys.setenv`, a worker, an MCP child, a CLI stand-in, a 401 echo and a wrong-origin send, then greps every
  sink: 0 occurrences with redaction, a negative control finds them without it (G6: 0 vs 518).""",
"""- **Test.** `test-secrets-e2e.R` pushes fake keys through print, message, warning, a spill-sized dump,
  `Sys.setenv`, a worker, an MCP child (stderr), an artifact log, a CLI stand-in, a 401 echo, a wrong-origin send
  and a redirect to a second origin, then greps every sink including deferred-write sidecars and worker spec and
  result files: 0 occurrences with redaction, a negative control finds them without it (G6: 0 vs 518)."""),
("""All text that crosses a boundary is UTF-8 and marked: `Encoding(x) = "UTF-8"` before `jsonlite::fromJSON()`
and before `toJSON()` (both corrupt unmarked non-ASCII in a C locale [07 fact-check, 08]); JSONL is written as
bytes (`writeLines(enc2utf8(x), con, useBytes = TRUE)` on a binary connection, LF only);""",
"""All text that crosses a boundary is UTF-8 and marked: `as_utf8()` at every ingress (prompts, templates, labels,
file reads, child output, `.env` values, frontmatter, readline input) marks valid unknown-encoded UTF-8 and never
passes it through `enc2utf8()`, which rewrites it to `<c3><a9>` in a C locale (reproduced) [IC-62];
`Encoding(x) = "UTF-8"` before `jsonlite::fromJSON()` and before `toJSON()` (both corrupt unmarked non-ASCII in a C
locale [07 fact-check, 08]); every `readLines()` passes `encoding = "UTF-8"`; JSONL is written as bytes
(`writeLines(as_utf8(x), con, useBytes = TRUE)` on a binary connection, LF only);"""),
("""and environment strings for children pass through `os_bytes()`; child output is read from redirected files
and decoded by gptr as UTF-8 with a code-page fallback (the Windows fallback page is UNCERTAIN [G5 fact-check]).""",
"""and environment strings for children pass through `os_bytes()`; child output is read from redirected files, or
from pipes of processes created with `encoding = "UTF-8"` (processx otherwise drops non-ASCII bytes of piped output
in a C locale [08 §1.12; IC-60]), and decoded by gptr as UTF-8 with a code-page fallback (the Windows fallback page
is UNCERTAIN [G5 fact-check])."""),
("""  `on.exit(kill_all(p))`; stdin is the null device unless `input =` is given (large inputs always on stdin:
  32,767-character command-line limit); `write_all()` loops `write_input()`, which silently truncates above
  8 KB [08 fact-check].""",
"""  `on.exit(kill_all(p))`; stdin is the null device unless `input =` is given (large inputs always on stdin:
  32,767-character command-line limit); `write_all()` queues raw bytes that the reactor drains non-blockingly with
  `write_input()` (which writes at most about 8 KB per call [08 fact-check]), reading the child's stdout and stderr
  between attempts, so a bidirectional child can never deadlock the reactor [IC-60]."""),
("""- R children are started through callr (Rscript path, libpaths and `_R_CHECK_R_ON_PATH_` handled [13 §1 item
  14]); `supervise` follows `gptr.supervise` (FALSE in examples: supervisor fifos are a fatal check error
  [13 §2.10]); process tables are cleaned in `.onUnload` and by finalizers.""",
"""- R children are started through callr (Rscript path, libpaths and `_R_CHECK_R_ON_PATH_` handled [13 §1 item
  14]); every other R child (test helpers, fixture servers, fake CLIs) uses `rscript_path()`, never a PATH lookup,
  because R CMD check puts failing dummy `R`/`Rscript` scripts first on PATH [13 §2.10; IC-60]. `supervise` is
  `supervise_default()`: `TRUE` except under `check_running()` (supervisor fifos are a fatal check error
  [13 §2.10]); every long-lived child exits when the parent dies (workers on stdin EOF, EPIPE or a dead parent pid;
  artifacts through their watchdog; CLI children through supervision); tree markers under
  `R_user_dir("gptr", "cache")/procs/` feed a mandatory orphan sweep at the next load, since SIGTERM skips
  finalizers (verified); under check every child-process pool is capped at 2; a requested stop is recorded so a
  later non-zero exit reads `stopped`, not `error` (callr 3.8.0 exits 1 [17 fact-check]); process tables are
  cleaned in `.onUnload` and by finalizers."""),
]
apply(P, pairs)
