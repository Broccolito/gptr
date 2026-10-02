from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
# P18
("""  Streamable HTTP with bearer token and Origin validation; `gptr_mcp_serve()`); `auth-oauth.R` (PKCE S256,
  loopback or paste callback, locked refresh, RFC 9728 discovery for MCP, `gptr_login()`, `gptr_logout()`).""",
"""  Streamable HTTP with bearer token and Origin validation; `gptr_mcp_serve()`); `auth-oauth.R` (PKCE S256,
  loopback or paste callback, locked refresh, RFC 9728 discovery for MCP, `gptr_login()`, `gptr_logout()`).
- **Review amendments (contract §15).** One listening socket with a bearer token per client bound to its session
  (evaluation environment, mode, rules, budget) through `mcp.serve_ensure(session)` (IC-58); requests served only
  by the outermost pump or at an idle console, a busy JSON-RPC error for other sessions in a nested pump, denial
  instead of prompts from callbacks (IC-57); ports from `port_candidates()` (IC-61); stderr read and redacted, logs
  in `tempdir()` unless `gptr.mcp_debug` (IC-70); OAuth refuses metadata without S256 PKCE and validates `iss`
  (IC-71); foreign-harness configs and `${userHome}` through `user_home()`/`app_config_dir()` (IC-63); the
  fixture server's HTTP transport binds 127.0.0.1 through httpuv (IC-71); `mcp_dispatch_local()` is the single gate
  for the claude route (IC-65); `followlocation = 0L` on MCP HTTP (IC-64)."""),
("""  6. A `.cmd` MCP command is launched through `cmd.exe /d /c call` on Windows CI.""",
"""  6. A `.cmd` MCP command is launched through `cmd.exe /d /c call` on Windows CI.
  7. Review additions: an `r` call from a CLI child of a fork evaluates in the fork's overlay, and one from a
     child of a plan-mode parent is gated in plan mode; OAuth mock servers without `code_challenge_methods_supported`
     or with a wrong `iss` are refused; a Windows CI test plants `.claude.json` under a fake `USERPROFILE` and
     `gptr_mcp()` lists it; `.Random.seed` is unchanged by `gptr_mcp_serve()`; an MCP server's stderr containing a
     registered fake key is persisted redacted; P18's NS-10 fixture is added to `dev/bench/tokens/` (IC-73)."""),
# P19
("""  permission and ask forwarding, exports); `inst/gptr/skills/gptr-orchestration/`,
  `inst/gptr/agents/reviewer.md`, `explorer.md`.""",
"""  permission and ask forwarding, exports); `inst/gptr/skills/gptr-orchestration/`,
  `inst/gptr/agents/reviewer.md`, `explorer.md`.
- **Review amendments (contract §15).** Routes `team` (15) and `fanout` (16) precede `nested`, with nesting
  inherited inside a run; `max_tasks` only for model-issued teams and fan-outs, user fan-outs queue every element
  (IC-39); `gptr_map()` internal (IC-36); the worker spec carries the session's registry records, plugins and
  filters (IC-69); workers start with `supervise_default()`, `encoding = "UTF-8"`, `child_env_callr()` and exit on
  parent death (IC-60); the parent re-classifies forwarded permission requests (IC-53); child pools capped at 2 under
  check (IC-60); budgets charged to the root (IC-66); `rng_swap()` states for inline children (IC-61); team and
  fan-out session data P15 needs for their document blocks (IC-47); the sub-agent `r_session` fragment (IC-68);
  the `cli` backend's tests move to P20 (IC-36)."""),
("""  2. INFRA-16 shape: two inline fake agents, two workers and one fake `cli` backend interleave on one reactor
     within about the slowest agent's wall time; R tools never overlap.""",
"""  2. INFRA-16 shape: two inline fake agents and two workers interleave on one reactor within about the slowest
     agent's wall time; R tools never overlap (the fake-CLI leg is P20's acceptance 2, IC-36)."""),
("""  5. A worker started with a fake key in a temporary `~/.Renviron` does not see it; at most 2 workers run when
     `_R_CHECK_PACKAGE_NAME_` is set; `gptr_cancel()` leaves no process.""",
"""  5. A worker started with a fake key in a temporary `~/.Renviron` does not see it; at most 2 workers run when
     `_R_CHECK_PACKAGE_NAME_` is set; `gptr_cancel()` leaves no process.
  6. Review additions: `gptr("Summarise", x, parallel = 4)` over 20 elements runs all 20, four at a time; a team
     and a fan-out started inside an `r` evaluation become children of the running session; a plugin `r` member and
     a `gptr_fake_provider()` spec work inside a worker; an inline agent calling System 1 while a sibling has a
     queued tool does not run the sibling's tool inside its evaluation (IC-57); a worker whose parent is killed exits
     within 10 s; NS-6 replays with zero requests from its team block (with P15); P19's NS-6 fixture is added to
     `dev/bench/tokens/` (IC-73)."""),
# P20
("""- **Scope.** `cli-common.R` (discovery preferring native binaries, minimum-version probe, one-time notice,
  billing-switch scrub with warning, `builtin:cli`);""",
"""- **Scope.** `cli-common.R` (discovery through `gptr.cli_path`, PATH and known install locations, native
  binaries only for claude (the `claude.cmd` shim refused), minimum-version and capability probes, one-time notice,
  billing-switch scrub with warning, cached `status()` data, `builtin:cli`; IC-65);"""),
("""  `perm_check()`, interrupt, session continuity, usage as plan estimate); `cli-codex.R` (`codex exec --json
  --ignore-user-config` with MCP `-c` overrides pointing at `gptr_mcp_serve()`, prompt on stdin via
  `write_all()`, sandbox mapping, resume when supported, overhead notice); `inst/gptr/fixtures/fake_cli.R`;
  `fixtures/cli/`; gated live test.""",
"""  `perm_check()`, interrupt, session continuity, usage as plan estimate); `cli-codex.R` (`codex exec --json
  --ignore-user-config` with MCP `-c` overrides pointing at `gptr_mcp_serve()`, prompt on stdin via
  `write_all()`, sandbox mapping, resume when supported, overhead notice); `inst/gptr/fixtures/fake_cli.R`;
  `fixtures/cli/`; gated live test.
- **Review amendments (contract §15).** claude argv with `--permission-mode default`, `--allowedTools
  mcp__gptr__*` and, under a budget, `--max-turns`/`--max-budget-usd`; one gate through `opts$mcp_dispatch`;
  `opts$gate` for other `can_use_tool` requests; the `--bare` probe; the `apiKeySource` check and
  `gptr_error_billing`; G6 §3.7 environment lists; codex argv with `--skip-git-repo-check`, `-m`, `-C`,
  `default_tools_approval_mode="approve"`, `required=true`, resume with `-c sandbox_mode=`; sandbox mapping
  plan/manual/edits -> read-only, auto -> workspace-write with control-file hashing and a checkpointer walk; the
  Windows sandbox probe; the turn counter and `gptr.cli_turn_timeout`; per-session wire logs; per-session MCP tokens
  (IC-58, IC-65, IC-66); fake CLIs run through `rscript_path()` with `offline = TRUE` records (IC-60, IC-45); the
  CLI leg of INFRA-16 (IC-36)."""),
("""  2. With the fake CLI: the claude argv equals §8.3 exactly; an `mcp_message` round trip evaluates R in the live
     session; `can_use_tool` goes through the gate; a Ctrl-C sends the interrupt control request then
     `kill_all()`; three concurrent fake-CLI agents stream into the reactor and an abort leaves no process tree
     (INFRA-19); usage fields are populated.
  3. The codex invocation passes the MCP overrides and a 50 KB prompt on stdin intact; `ANTHROPIC_API_KEY`,
     `OPENAI_API_KEY` and `CODEX_API_KEY` are absent from the children's environment and a warning names them.""",
"""  2. With the fake CLI: the claude argv equals §8.3 exactly; an `mcp_message` round trip evaluates R in the live
     session and is gated once (no second prompt from `can_use_tool`); a Ctrl-C sends the interrupt control request
     then `kill_all()`; three concurrent fake-CLI agents stream into the reactor and an abort leaves no process tree
     (INFRA-19); usage fields are populated; a fake CLI joins two inline agents and two workers on one reactor
     within about the slowest agent's wall time (the INFRA-16 CLI leg, IC-36); an `init` line with
     `apiKeySource: "ANTHROPIC_API_KEY"` aborts the turn with `gptr_error_billing`.
  3. The codex invocation passes `--skip-git-repo-check`, `-m <full id>`, `-C`, the MCP overrides including
     `default_tools_approval_mode="approve"` and `required=true`, and a 50 KB prompt on stdin intact; the resume
     form uses `-c sandbox_mode=`; `edits` maps to `read-only`; `ANTHROPIC_API_KEY`, `ANTHROPIC_PROFILE`,
     `CLAUDECODE`, `OPENAI_API_KEY`, `CODEX_API_KEY` and `CODEX_SANDBOX` are absent from the children's environment and
     a warning names the billing ones; `gptr_providers()` spawns no process with `check = FALSE`; a `.cmd` fake claude
     is refused with the install hint; the gated live test runs Codex in a non-git temporary directory and requires a
     call of the gptr `r` tool."""),
("""  4. **M4 exit** (once P18-P21 are complete): NS-6 (two inline fakes, one worker and fake codex on one reactor), NS-9
     (`gptr_providers(check = TRUE)` with the fake CLIs) and NS-10 MCP pass; `devtools::check(args =
     c("--as-cran", "--no-manual"), error_on = "warning")` clean.""",
"""  4. **M4 exit** (once P18-P21 are complete): NS-6 (two inline fakes, one worker and fake codex on one reactor), NS-9
     (`gptr_config(model = sonnet, mode = manual)` writing project defaults after `gptr_init()`, and
     `gptr_providers(check = TRUE)` with the fake CLIs) and NS-10 MCP pass; `devtools::check(args =
     c("--as-cran", "--no-manual"), error_on = "warning")` clean."""),
# P21
("""- **Scope.** `agent-background.R`: registration of a running session with a `later`-driven pump (50 ms timer
  polling, no `later_fd`), idle-tick execution of R tools (`gptr.background_tools = "idle" | "wait"`), the pause
  menu's `[b]ackground` option, `gptr_jobs()` listing background sessions and bridge jobs, cleanup in
  `.onUnload`; documentation of the support matrix and the experimental status.""",
"""- **Scope.** `agent-background.R`: registration of a running session with a `later`-driven pump (50 ms timer
  polling, no `later_fd`; a no-op while the reactor is on the stack, IC-57), idle-tick execution of R tools
  (`gptr.background_tools = "idle" | "wait"`, with a notice when a tool changed user bindings at an idle tick),
  asks moving the session to `waiting` until the next blocking gptr call (IC-57), the pause menu's
  `[b]ackground` option, session rows in the job table that P04's `gptr_jobs()` lists (IC-36), cleanup in
  `.onUnload`; documentation of the support matrix and the experimental status."""),
# P22
("""- **Scope.** `bridge-sh.R` (`gptr$sh`, `gptr$script`, `gptr$bg`, `gptr$jobs`, `gptr$out` on the process engine;""",
"""- **Scope.** `bridge-sh.R` (`gptr$sh`, `gptr$script`, `gptr$bg`, `gptr$jobs` on the process engine (`gptr$out` is
  P10's, IC-36);"""),
("""  scope, `gptr$knit` for other engines; `builtin:lang`).""",
"""  scope, `gptr$knit` for other engines, whose shell engines run through `gptr$sh()` with the `helper` environment
  and a timeout (IC-67); `builtin:lang`).
- **Review amendments (contract §15).** The shell and languages `r_session` fragments (IC-68); bridge children
  through `proc_spawn()` with `encoding = "UTF-8"`, the complete `helper` environment and non-blocking stdin
  (IC-60); the pool cap of 2 under check (IC-60)."""),
("""  4. The copy row documents exactly one copy after `gptr$sql(name = df)` (duckdb registration) and none for
     `gptr$sh()`.""",
"""  4. The copy row documents exactly one copy after `gptr$sql(name = df)` (duckdb registration) and none for
     `gptr$sh()`.
  5. Review additions: `gptr$knit("bash", "sleep 999")` times out and kills the process, and its environment lacks a
     registered fake key; `-builtin:bridges` removes the shell line from `<r_session>`; P22's NS fixtures are added to
     `dev/bench/tokens/` (IC-73)."""),
# P23
("""  events, the artifacts `checkpointer`, `builtin:artifacts`); `artifact-registry.R` (`gptr_artifacts()`, open,
  relaunch a version, stop, lazy orphan sweep, `.onUnload` cleanup); `inst/gptr/skills/shiny-bslib/`.""",
"""  events, the artifacts `checkpointer`, `builtin:artifacts`); `artifact-registry.R` (`gptr_artifacts()`, open,
  relaunch a version, stop, lazy orphan sweep, `.onUnload` cleanup); `inst/gptr/skills/shiny-bslib/`.
- **Review amendments (contract §15).** The `artifacts` prompt section (IC-68); ids that are Windows reserved names
  refused and numbered data files with the mapping in `artifact.json` (IC-63); a per-launch access token in the URL
  (IC-71); ports from `port_candidates()` and `with_seed_preserved()` around chromote and shiny in the parent
  (IC-61); logs read and redacted by the parent (IC-70); `supervise_default()`, `encoding = "UTF-8"`,
  `child_env_callr()` and `stopped` (not `error`) after a requested stop (IC-60); `gptr$app(kind =)` accepts any
  registered `artifact_type` (IC-69); static checks flag reads of secret files (IC-71)."""),
("""  4. NS-8 on the fake provider writes `.gptr/artifacts/marker-explorer/app.R` and prints the NS-8 line.""",
"""  4. NS-8 on the fake provider writes `.gptr/artifacts/marker-explorer/app.R` and P14's renderer prints the NS-8
     line `artifact  marker-explorer  ->  <url>   (running in background)` on `artifact_start` (IC-71).
  5. Review additions: `gptr$app("con")` is refused; a data object named `a/b` snapshots as `data/001.rds`; a request
     without the token is rejected; `.Random.seed` is unchanged by `gptr$app(check = TRUE)`; a stopped artifact's
     status is `stopped`; P23's NS-8 fixture is added to `dev/bench/tokens/` (IC-73)."""),
# P24
("""  `tests/testthat/test-secrets-e2e.R`; `test-injection-e2e.R`; `test-northstar.R`; a CI step asserting the
  offline INFRA suite finishes in under 60 s.
- **Owns.** No R files. The `dev/bench/` tree and the three test files.""",
"""  `tests/testthat/test-secrets-e2e.R`; `test-injection-e2e.R`; `test-northstar.R`; a CI step asserting the
  offline INFRA suite finishes in under 60 s.
- **Review amendments (contract §15).** `tests/testthat/test-s11-conformance.R` (a fixture plugin registers one
  record of every kind; each is used at run time) (IC-73); every §12.7 gate in `run.R --check` (IC-73); the
  composed system prompt with every built-in loaded compared byte for byte with architecture §7.3 (IC-68); the
  secrets e2e sinks of IC-70 and the redirect mock (IC-64); the adversarial gate paths of IC-53 in
  `test-injection-e2e.R`; the NS-1 and remaining fixtures not added by earlier plans.
- **Owns.** No R files. The `dev/bench/` tree except P07's runner and fixtures (IC-73), and the four test files."""),
("""  3. `Rscript --vanilla -e 'devtools::test(filter = "secrets-e2e|injection-e2e|northstar")'` is green:
     zero key bytes across every sink with redaction on, a positive count in the negative control; no `{...}`
     payload evaluated through any printer or condition constructor; NS-1..NS-12 pass on the fake provider.""",
"""  3. `Rscript --vanilla -e 'devtools::test(filter = "secrets-e2e|injection-e2e|northstar|s11-conformance")'` is
     green: zero key bytes across every sink with redaction on (JSONL, wire logs, documents, caches, spill files,
     sidecars, MCP and artifact logs, worker spec and result files), a positive count in the negative control; no
     `{...}` payload evaluated through any printer or condition constructor; every IC-53 path an injected model tries
     ends in a human ask or `blocked`; NS-1..NS-12 pass on the fake provider; every kind's fixture record is used.
  4. `run.R --check` fails when a fixture's input or output total grows by more than 5%, its request count or image
     tokens by any amount, a catalog by more than 5%, or the describers lose a fact (IC-73)."""),
# P25
("""  `cran-comments.md` citing the consent design and precedents; `_pkgdown.yml`; `DESCRIPTION` Version set to
  1.0.0 (the only DESCRIPTION field this plan may change).""",
"""  `cran-comments.md` citing the consent design and precedents and recording
  `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on submission day; `_pkgdown.yml`;
  `DESCRIPTION` Version set to 1.0.0 and `VignetteBuilder: knitr` added with the vignettes (the only DESCRIPTION
  fields this plan may change; IC-72); the release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against
  one Anthropic and one OpenAI model and records request counts (within +2) and input tokens (within 20%) of the
  golden transcripts in `dev/bench/tokens/live-<date>.csv` (IC-73); the Security considerations page covers PHI in
  committed caches and the non-isolating worker backend (IC-70, IC-53)."""),
("""  1. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`
     gives 0 errors, 0 warnings and only the "New submission" NOTE on the full CI matrix (macOS, Windows,
     Ubuntu release/devel/oldrel-1, oldrel-4, no-suggests, `LC_ALL=C`).
  2. `devtools::check_win_devel()` result: Status OK apart from the new-submission NOTE.""",
"""  1. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`
     gives 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the maintainer (an
     update of gptr 0.7.0; IC-72) on the full CI matrix (macOS, Windows, Ubuntu release/devel/oldrel-1, oldrel-4,
     no-suggests, `LC_ALL=C`).
  2. `devtools::check_win_devel()` result: Status OK apart from the maintainer NOTE."""),
]
apply(P, pairs)
