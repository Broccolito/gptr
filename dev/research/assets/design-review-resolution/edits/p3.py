from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
# P03
("""  billing-switch removal; `builtin:secrets` registering the secret sources, redaction rules, env aliases and
  child-env profiles as specs.""",
"""  billing-switch removal; `builtin:secrets` registering the secret sources, redaction rules, env aliases and
  child-env profiles as specs.
- **Review amendments (contract §15).** `child_env()` returns complete vectors without removed names (processx
  rejects `NA`) and `child_env_callr()` gives the callr form; every profile gets the empty
  `R_ENVIRON_USER`/`R_PROFILE_USER` files and drops `R_ENVIRON` (IC-60); the CLI profiles follow G6 §3.7 verbatim
  (enclosing-agent variables, `ANTHROPIC_PROFILE`, `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`,
  `CODEX_MANAGED_*`, `CODEX_SANDBOX*`; IC-65); `redact()` is installed with `redactor_set()` (IC-34);
  `gptr_scrub()` (exported) and the `secret_late` warning of `secret_register()` (IC-70); the `secret.lookup`
  service."""),
("""  5. `auth.json` is created with mode `0600` on Unix; the store round-trips a keyring reference.""",
"""  5. `auth.json` is created with mode `0600` on Unix; the store round-trips a keyring reference.
  6. Review additions: an Rscript child started through `proc_spawn()` with the `mcp` and `helper` profiles and a
     `.Renviron` defining a fake key does not see it (skip_on_cran); `child_env()` contains no `NA` and
     `processx::process$new(env = child_env("helper"))` starts; the claude profile removes `CLAUDECODE` and
     `ANTHROPIC_PROFILE` and keeps `CLAUDE_CONFIG_DIR`; `gptr_scrub()` finds a value registered after it was
     written, rewrites it with `dry_run = FALSE` and `error = TRUE` signals `gptr_error_secret_found`."""),
# P04
("""  `http-retry.R` (classes, bounded backoff with time jitter, Retry-After cap, spend-cap rule, per-provider
  limiter).""",
"""  `http-retry.R` (classes, bounded backoff with time jitter, Retry-After cap, spend-cap rule, per-provider
  limiter).
- **Review amendments (contract §15).** Processes created with `encoding = "UTF-8"`; non-blocking `write_all()`
  drained by the reactor with `gptr.stdin_timeout` (IC-60); `supervise_default()`; tree markers under
  `R_user_dir("gptr", "cache")/procs/` and a mandatory orphan sweep at load; job-table `stop_requested`
  (IC-60); `pid_alive()` with ps and creation times (IC-59); `gptr_jobs()` moves here (IC-36); reactor depth,
  the `allow_runs` default inside a run and `later::run_now(0)` only in the outermost pump or for a served CLI
  child (IC-57); `followlocation = 0L` and the `redirect` class (IC-64); the SSE splitter per the specification
  (CR/LF/CRLF, BOM, last `event:` wins) (IC-64); locale-independent `parse_http_date()` and static provider
  rates in the limiter (IC-64); every child pool capped at 2 under check (IC-60); per-session wire logs written
  open-append-close (IC-59, IC-65)."""),
("""  6. Process engine: under `LC_ALL=C` a child printing `"café"` and a CJK string is decoded byte-exact;
     a 2 MB stdin payload arrives complete; `kill_all()` leaves no descendant; a `.cmd` argument containing
     `&` is refused with `gptr_error_invalid_argument` (logic test on every OS).""",
"""  6. Process engine: under `LC_ALL=C` a child printing `"café"` and a CJK string is decoded byte-exact, both
     through redirected files and through the pipe path read by `reactor_proc()`; a 2 MB stdin payload arrives
     complete, and a 4 MB payload to a child that echoes each line completes without deadlock; `kill_all()` leaves
     no descendant; a `.cmd` argument containing `&` is refused with `gptr_error_invalid_argument` (logic test on
     every OS).
  8. Review additions: a parent killed with SIGTERM leaves children that the next load's sweep removes; the
     redirect mock receives no key bytes and the transfer fails with `gptr_error_redirect`; `test-http-sse.R`
     covers CRLF, CR-only, split-CRLF, a BOM and duplicate `event:` fields; `retry-after` as an HTTP-date under
     `LC_ALL=de_DE.UTF-8` and `retry-after: soon` fall back correctly; a nested pump started inside a FIFO tool
     never runs a sibling's queued tool and never calls `later::run_now(0)`; `pid_alive()` is FALSE for a reused
     pid with another creation time; `nrow(showConnections())` is unchanged after the wire log wrote 100 lines."""),
# P06
("""  gating entry point; `perm_check()`: the combination of `policy` records, `permission_request` hooks, the UI
  and the non-interactive stop, contract IC-04; with no policy registered everything is allowed).""",
"""  gating entry point; `perm_check()`: the combination of `policy` records, `permission_request` hooks, the UI
  and the non-interactive stop, contract IC-04; with no `mode` policy registered the gate asks, fail closed,
  IC-53).
- **Review amendments (contract §15).** The store appends open-append-close, recovers torn lines at resume, skips
  unparsable lines, and locks with pid, creation time and a 10-minute heartbeat (IC-59); `the$last` is strong
  (IC-71); the replay functions `session_replay_apply()`, `session_replay_new()`, `session_replay_bind()`,
  `replay_lookup()` and `gptr_resume(block =, child =)`, with fresh overlays for rebuilt forks and reconstructed
  histories (IC-46); `perm_check()` with `ask_human`, a single modify re-check, the run's safety snapshot and mode
  inheritance for every call made during a run (IC-53); relays and queue items by source (IC-55); budgets with the
  default ceiling, root charging, `gptr.max_nested_calls` (IC-66); router calls before each request through
  `router.call` (IC-69); the `ctx.kernel` service (IC-34); per-session `out` stores (IC-71); image elision entries
  (IC-67); the `store` kind's built-in record (IC-69); re-classification of worker-forwarded permission requests
  (IC-53)."""),
("""  7. G3 analogues: `identical(s |> step, s)`; `$<-` refused; an unreferenced settled session is finalised and
     its lock removed; a same-process duplicate continues with `gptr_error_split_brain`.""",
"""  7. G3 analogues: `identical(s |> step, s)`; `$<-` refused; an unreferenced settled session is finalised and
     its lock removed (except the one `gptr_last()` holds); a same-process duplicate continues with
     `gptr_error_split_brain`.
  8. Review additions: `nrow(showConnections())` is unchanged after `gptr()` returns, errors or is interrupted, and
     after 300 sessions kept in a list; SIGKILL mid-append, resume, three appends: all present and the tree
     connected; `gptr_last()` survives `gc()`; with no policy registered a mutating tool asks (and is `blocked`
     without a UI); a hook answering allow to an `ask_human` is ignored; an option changed by model code mid-run
     does not change the run's gate; a budget of 5 USD on a root stops its children; `session_replay_apply()` keeps
     `identical()` along a replayed pipe chain."""),
# P07
("""  `prompt-cache.R` (request assembly by concatenation, per-provider breakpoint plans, gap-based tail TTL, prefix
  guard with `cache_break`); `prompt-compact.R` (threshold formula, cold rule, in-conversation checkpoint with
  G4's verbatim prompt, harness state extraction, `builtin:compaction`).""",
"""  `prompt-cache.R` (request assembly by concatenation, per-provider breakpoint plans, gap-based tail TTL, prefix
  guard with `cache_break`); `prompt-compact.R` (threshold formula, cold rule, in-conversation checkpoint with
  G4's verbatim prompt, harness state extraction, `builtin:compaction`).
- **Review amendments (contract §15).** Context placement `both` and turn-block deduplication (IC-38); the four
  `preset` records and `preset_tools()` from them (IC-69), with `ask` kept in non-interactive `manual` runs and
  the manual suffix (IC-68); `<rules>` composed from the active tools' guidelines plus P07's closing lines and
  `<r_session>` from P07's core plus fragments; P07 no longer owns `documents`, `artifacts`, `system1` (IC-68);
  the `str()`-free texts and the `trusted="false"` sentence (IC-67, IC-52); `project_instructions` rendered
  `trusted="false"` in untrusted projects and omitted non-interactively in `auto`/`edits` (IC-52);
  `session_add_tools()` and the `session.add_tools` and `ctx.input` services (IC-69, IC-34); the compaction floor
  check (IC-71); shipped `tools.presets` defaults for Gemini 3 and Haiku 4.5 (IC-73); the golden-transcript runner
  `dev/bench/tokens/run.R` with the NS-2 and NS-3 fixtures (IC-73)."""),
("""- **Owns.** The five R files and tests; `test-context-prefix.R`; `test-bench-context.R`;
  `tests/testthat/fixtures/bench/prefix-baseline.json`.""",
"""- **Owns.** The five R files and tests; `test-context-prefix.R`; `test-bench-context.R`;
  `tests/testthat/fixtures/bench/prefix-baseline.json`; `dev/bench/tokens/run.R` and the NS-2/NS-3 golden
  transcripts (IC-73)."""),
("""  2. Rendered sections are byte-identical to architecture §7.3; each section is within its budget; the
     preset estimates are within 5% of `prefix-baseline.json` (initial values: 1,299 / 2,385 / 2,818 / 2,980
     measured o200k tokens, stored with the estimator's figures).""",
"""  2. P07-owned rendered sections are byte-identical to architecture §7.3 as amended (the other owners' texts are
     compared in their plans and composed in P24); each section is within its budget; with a fixed T1 fixture
     (`<r_env>` plus the two built-in skills, 542 tokens) standing in for P09's and P17's sections, the preset
     estimates are within 5% of `prefix-baseline.json` (initial values: 1,271 / 2,360 / 2,844 / 2,987 measured
     o200k tokens, stored with the estimator's figures; IC-68); no shipped text mentions `str(` (IC-67)."""),
("""  5. The tail TTL switches to 1 h after a simulated 241 s gap and not after 239 s.""",
"""  5. The tail TTL switches to 1 h after a simulated 241 s gap and not after 239 s.
  6. Review additions: the first request of `gptr("x", mtcars)` contains `<attached name="mtcars">` after
     `<workspace>` (with a stub `attached` block until P09); an unchanged plugin turn block is sent once; the
     `readonly` preset has no edit or write rules; a session in an untrusted project renders
     `<project_instructions trusted="false">`; a model with an 8K window and a large project block is refused for
     the standard preset with the suggestion; `Rscript --vanilla dev/bench/tokens/run.R --check` passes on NS-2 and
     NS-3."""),
]
apply(P, pairs)
