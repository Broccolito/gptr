from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""vectorised on the reactor, at most 8 concurrent, 3 bounded rounds; about 250-280 input tokens per request at $0.042/M; 20 requests in about 0.4 s [04, 04a] |""",
"""vectorised on the reactor, at most 8 concurrent, 3 bounded rounds, and a static rate of 40 requests and 100K tokens per second in the provider record (Jev sends no rate-limit headers) [IC-64]; about 250-280 input tokens per request at $0.042/M; 20 requests in about 0.4 s [04, 04a] |"""),
("""```text
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
       --tools "" --strict-mcp-config --setting-sources "" --disable-slash-commands
       --mcp-config <file> --permission-prompt-tool stdio --system-prompt-file <file> --model <full id>
```

Never `--bare`.""",
"""```text
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
       --tools "" --strict-mcp-config --setting-sources "" --disable-slash-commands
       --mcp-config <file> --permission-prompt-tool stdio --permission-mode default
       --allowedTools mcp__gptr__* --system-prompt-file <file> --model <full id>
       [--max-turns <remaining turns> --max-budget-usd <remaining cost>]
```

Never `--bare` (it never reads the subscription login [07]); a capability probe of `--help` and the version
detects a CLI whose `-p` defaults to bare and passes the documented opt-out or stops with `gptr_error_cli_version`
[15 §2.9 verifier; IC-65]. The binary is found through `gptr.cli_path`, PATH, then known install locations
(`~/.local/bin`, `/opt/homebrew/bin`, `%USERPROFILE%\\.local\\bin`, ...), because RStudio and Positron on macOS do not
source shell profiles [07 §6.3]; the npm `claude.cmd` shim is refused [07 §6.2], so the empty-string arguments
reach the native binary intact."""),
("""The minimum CLI version is probed (>= 2.0.0, the
Agent SDK's floor; 2.1.261 tested). Variables that silently switch plan billing to the API
(`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_USE_*`) are removed from the child environment
with a warning; profile and gateway precedence cases are documented as UNCERTAIN [G6 fact-check]. gptr's tools
reach the CLI through the in-process `sdk` MCP server over the control protocol (`mcp_message`), so Claude
evaluates R in the live session; `can_use_tool` requests go through `perm_check()`;""",
"""The minimum CLI version is probed (>= 2.0.0, the
Agent SDK's floor; 2.1.261 tested). Variables that silently switch plan billing to the API or leak an enclosing
agent's state are removed from the child environment with a warning, following G6 §3.7 verbatim (§6.5), including
`ANTHROPIC_PROFILE`, whose profile outranks the subscription login [07 fact-check]; after `system/init`, an
`apiKeySource` other than `"none"` aborts the turn with `gptr_error_billing` [07 line 503; IC-65]. gptr's tools
reach the CLI through the in-process `sdk` MCP server over the control protocol (`mcp_message`), so Claude
evaluates R in the live session; because `--allowedTools mcp__gptr__*` pre-allows them, the gate runs once, in the
`mcp_message` dispatch (a `can_use_tool` for anything else goes through the injected `opts$gate` and is denied);"""),
("""```text
codex exec --json --ignore-user-config
      -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp
      -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN
      -c mcp_servers.gptr.tool_timeout_sec=3600
      --sandbox <read-only | workspace-write> -
```""",
"""```text
codex exec --json --ignore-user-config --skip-git-repo-check -m <full id> -C <wd>
      -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp
      -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN
      -c mcp_servers.gptr.default_tools_approval_mode="approve"
      -c mcp_servers.gptr.required=true
      -c mcp_servers.gptr.tool_timeout_sec=3600
      --sandbox <read-only | workspace-write> -
codex exec resume <thread> --json ... -c sandbox_mode=<mode> -       (resume rejects -s and -C)
```

(`exec` refuses to run outside a git repository without `--skip-git-repo-check`, forces `approval_policy =
never`, and with `--ignore-user-config` would fall back to its built-in model without `-m` [08 §2.E, line 594-600
and fact-check 13, 16; IC-65]; gptr's gate stays the approval authority.)"""),
("""Authentication is the user's own Codex login; gptr never reads `~/.codex/auth.json`; `CODEX_API_KEY` and
`OPENAI_API_KEY` are removed from the child environment with a warning [08, G6]. Live R: `gptr_mcp_serve()`
starts automatically (loopback, random port, 192-bit token passed only in the child's environment) so Codex
evaluates R in the live session through the permission gate, which can prompt at the console because the
call arrives in R [08: in-session HTTP MCP verified listed and called by Codex].""",
"""Authentication is the user's own Codex login; gptr never reads `~/.codex/auth.json`; `CODEX_API_KEY`,
`CODEX_ACCESS_TOKEN`, `OPENAI_API_KEY`, `OPENAI_BASE_URL` and the enclosing-agent variables `CODEX_MANAGED_*` and
`CODEX_SANDBOX*` are removed from the child environment with a warning [08, G6 §3.7]. Live R: `gptr_mcp_serve()`
starts automatically (loopback, an RNG-free free port, a 192-bit token bound to this session and passed only in
the child's environment [IC-58]) so Codex evaluates R in the live session through the permission gate, which can
prompt at the console because the call arrives in R. (Evidence level: the in-session HTTP MCP route was verified
through app-server listing and calls without a model; the verified model-driven MCP call used
`default_tools_approval_mode = "approve"` and `required = true` [08 §2.G]; a `GPTR_LIVE_TESTS` test runs Codex in a
non-git temporary directory and requires it to call the gptr `r` tool.)"""),
("""the route works on files only, with a notice. Permission mapping (headless exec cannot prompt): `plan` ->
`--sandbox read-only`; `manual` -> read-only sandbox, R tools gated by gptr; `edits`/`auto` ->
`workspace-write`; never bypass the sandbox.""",
"""the route works on files only, with a notice. Permission mapping (headless exec cannot prompt) [IC-65]: `plan`,
`manual` and `edits` -> `--sandbox read-only`, so every file change goes through gptr's gated `write`/`edit` over
MCP (edits-mode approval and checkpoints apply); `auto` -> `workspace-write`, with the control files hashed before
each exec (changed ones are not loaded until the user confirms) and a files-checkpointer walk after it so `/undo`
covers Codex's edits; on native Windows the sandbox is probed and the route falls back to `read-only` with a warning
when it is not ready [08 line 2796]; never bypass the sandbox. The one-time notice says Codex runs its own shell
inside its sandbox. gptr counts Codex's turn events and cancels at the turn cap, with a wall-clock limit per exec."""),
("""### 9.1 Imports (7 non-base; dependency closure 9 packages, 10 with callr 3.8.0's otel)""",
"""### 9.1 Imports (8 non-base; dependency closure 9 packages, 10 with callr 3.8.0's otel)"""),
("""| yaml | 2.3.0 | SKILL.md, agent and template frontmatter | a hand parser lost 4 of 37 real skills to folded scalars [05] |""",
"""| yaml | 2.3.0 | SKILL.md, agent and template frontmatter (string keys keep their source text against YAML 1.1 coercion [05 fact-check; IC-71]) | a hand parser lost 4 of 37 real skills to folded scalars [05] |
| ps | 1.7.0 | `pid_alive()`: session and document locks, orphan sweep, watchdogs, the no-leftover-process tests, with a creation-time check against pid reuse [IC-59] | already in the closure through processx, so the closure does not grow; the base substitute `tools::pskill(pid, 0)` terminates the process on Windows; an undeclared `ps::` call is a check WARNING (reproduced) |"""),
("""Base packages imported: `methods` (G7 pre-image defusing of S4), `stats`, `tools`, `utils`, `grDevices`,
`graphics`. The closure (these plus R6 and ps via processx and callr) was verified with""",
"""Base packages imported: `methods` (G7 pre-image defusing of S4), `stats`, `tools`, `utils`, `grDevices`,
`graphics`; `parallel` is not needed (per-agent L'Ecuyer streams are seeded from hash bits and swapped by
`rng_swap()` [IC-61]). The closure (these plus R6 via processx and callr) was verified with"""),
]
apply(P, pairs)
