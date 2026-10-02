from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `_R_CHECK_PACKAGE_NAME_`, `_R_CHECK_LIMIT_CORES_` | P01 `check_running()` | forced replay, 2 workers, no supervision |""",
"""| `_R_CHECK_PACKAGE_NAME_`, `_R_CHECK_LIMIT_CORES_` | P01 `check_running()` | forced replay outside testthat (examples; IC-45), child pools capped at 2, no supervision |
| `GPTR_PROJECT_ROOT` | P01 `project_root()` | overrides the project root (tests; IC-63) |
| `TESTTHAT` | P08 `replay_mode()` | `"true"` under testthat: no forced replay |
| `jupyter.in_kernel` (option) | P01 `gptr_can_prompt()` | IRkernel answers `readline()` (IC-43) |"""),
("""Set by gptr in child processes only (never in the user's session): `NO_COLOR=1`, `TERM=dumb`, `PAGER=cat`,
`GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1` (`helper` profile);
`R_ENVIRON_USER` and `R_PROFILE_USER` pointing at empty files (`worker`, `artifact`); `GPTR_MCP_TOKEN`,
`GPTR_SUBAGENT_DEPTH`, `GPTR_WORKER` as above. Removed from CLI children with a `billing_env` warning:
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_USE_BEDROCK`,
`CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY` (claude); `OPENAI_API_KEY`, `CODEX_API_KEY`,
`CODEX_ACCESS_TOKEN`, `OPENAI_BASE_URL` (codex) [G6 §3.7].

Tests set (`tests/testthat/setup.R`, P01): `R_USER_CONFIG_DIR`, `R_USER_DATA_DIR`, `R_USER_CACHE_DIR` to a
temporary directory, every provider key to `""` unless `GPTR_LIVE_TESTS=true`, `GPTR_REPLAY=replay`,
`OMP_THREAD_LIMIT=2`, and `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`.""",
"""Set by gptr in child processes only (never in the user's session): `NO_COLOR=1`, `TERM=dumb`, `PAGER=cat`,
`GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1` (`helper` profile);
`R_ENVIRON_USER` and `R_PROFILE_USER` pointing at empty files, and `R_ENVIRON` dropped unless passed explicitly,
in **every** profile (an Rscript child otherwise re-reads keys from `~/.Renviron`; IC-60); `GPTR_MCP_TOKEN`,
`GPTR_SUBAGENT_DEPTH`, `GPTR_WORKER` as above. Removed from CLI children (G6 §3.7 verbatim, IC-65): for claude,
secret-like names, registered values, `^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)` except the kept
`CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`, and with a `billing_env` warning
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`,
`ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`,
`CLAUDE_CODE_USE_FOUNDRY`; for codex, secret-like names, registered values, `^(CODEX_MANAGED_|CODEX_SANDBOX)`, and
with the warning `OPENAI_API_KEY`, `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, `OPENAI_BASE_URL` (`CODEX_HOME` kept).
`child_env()` returns the complete vector without removed names (processx form); callr receives
`child_env_callr()` (removed names as `NA`).

Tests set (`tests/testthat/setup.R`, P01): `R_USER_CONFIG_DIR`, `R_USER_DATA_DIR`, `R_USER_CACHE_DIR`, `HOME`,
`USERPROFILE`, `APPDATA`, `LOCALAPPDATA` and `XDG_CONFIG_HOME` to temporary directories, `GPTR_PROJECT_ROOT` to a
temporary project, every provider key to `""` unless `GPTR_LIVE_TESTS=true`, `GPTR_REPLAY=replay`,
`OMP_THREAD_LIMIT=2`, and `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`."""),
("""| `user` | `content` list of `text`/`image`/`context` blocks; `source` chr(1) in `prompt`, `pipe`, `follow_up`, `repl`, `parent`, `replay`, `extension`; `timestamp` num(1) ms | `{"role":"user","content":[…],"timestamp":…,"gptr":{"source":…}}` |""",
"""| `user` | `content` list of `text`/`image`/`context` blocks; `source` chr(1) in `prompt`, `pipe`, `steer`, `follow_up`, `repl`, `parent`, `replay`, `extension`, `agent`, `imported`; `timestamp` num(1) ms | `{"role":"user","content":[…],"timestamp":…,"gptr":{"source":…}}` |"""),
("""[G4 §3.5]. A steering relay's text is exactly `The user sent this message while you were working: <text>`.""",
"""[G4 §3.5]. A steering relay's text is exactly `The user sent this message while you were working: <text>`, and
only queue items from user sources (`pipe`, `pause_menu`, `repl`, `api_user`) become relays; `extension` items are
user-role text `Extension <name> sent this note (not from the user): <text>` and `agent` items user-role
`<agent_report from="<name>">` blocks (IC-55). Operator messages carry harness facts only; `project_update` is
user-role data (IC-52)."""),
("""| `status` | chr(1) | `idle`, `running`, `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`, `detached` |""",
"""| `status` | chr(1) | `idle`, `running`, `waiting` (a background or served run with an ask pending, IC-57), `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`, `detached` |"""),
("""| `queue` | list(steer = list, follow_up = list) | FIFO items `list(text, blocks, source, t)` |""",
"""| `queue` | list(steer = list, follow_up = list) | FIFO items `list(text, blocks, source, t)`; `source` in `pipe`, `pause_menu`, `repl`, `api_user`, `extension`, `agent` (IC-55) |
| `history` | chr(1) | `"store"` or `"reconstructed"` (a replayed session rebuilt from its document, IC-46) |"""),
("""0), `store` (`gptr_store`), `ctx` (`gptr_ctx`), `memo` (environment: serialised entry JSON by
`<entry id>|<api>|<same model>`), `adapter` (environment: per-provider live state, e.g. the claude child),
`background` (list or `NULL`), `lock` (chr path).""",
"""0), `store` (`gptr_store`: the file path and lock only; no open connection, IC-59), `ctx` (`gptr_ctx`), `memo`
(environment: serialised entry JSON by `<entry id>|<api>|<same model>`), `adapter` (environment: per-provider live
state, e.g. the claude child), `background` (list or `NULL`), `lock` (chr path), `out` (the session's `gptr$out()`
store, IC-71), `mcp_token` (the MCP bearer token bound to this session, IC-58)."""),
("""| `<child name>` | the child session (teams: agent names; fan-out: element names) |""",
"""| `<child name>` | the child session (teams: agent names; fan-out: element names); agent names equal to an accessor name are rejected at call time (IC-71) |"""),
("""| `$.gptr_gateway(x, name)`, `[[.gptr_gateway(x, i)` | P10 (stub in P08 returning `gptr_error_not_available` until P10 registers the `ns_resolve` service) | a member closure (tool spec with `exposure = "r"` and no namespace), or a `gptr_ns` node (`mcp`, plugin namespaces); no I/O, no connections (side-effect free); unknown -> `gptr_error_unknown_member` with the member list |
| `$<-.gptr_gateway`, `[[<-.gptr_gateway` | P08 | refuse |
| `.DollarNames.gptr_gateway(x, pattern)` | P10 | member and namespace names |""",
"""| `$.gptr_gateway(x, name)`, `[[.gptr_gateway(x, i)` | P08 (calls the `ns.resolve` service of P10; `gptr_error_not_available` before P10, IC-36) | a member closure (any un-namespaced tool spec with a `fun` that is not `hidden`, IC-37), or a `gptr_ns` node (`mcp`, plugin namespaces); no I/O, no connections (side-effect free); unknown -> `gptr_error_unknown_member` with the member list |
| `$<-.gptr_gateway`, `[[<-.gptr_gateway` | P08 | refuse |
| `.DollarNames.gptr_gateway(x, pattern)` | P08 (the `ns.names` service of P10; `character(0)` before P10) | member and namespace names |"""),
("""| `gptr_artifact` | P23 | list(id, title, kind, version (int), url, path, status (`running`, `stopped`, `failed`), checks (list(parse, launch, http, session) of lgl\\|NA plus `messages`), screenshot (chr(1)\\|NULL), session (chr(1)\\|NULL)) | `artifact  <id>  ->  <url>   (<status>)` |""",
"""| `gptr_artifact` | P23 | list(id, title, kind, version (int), url (with the `gptr_token` query, IC-71), path, status (`running`, `stopped`, `failed`), checks (list(parse, launch, http, session) of lgl\\|NA plus `messages`), screenshot (chr(1)\\|NULL), session (chr(1)\\|NULL)) | `artifact  <id>  ->  <url>   (<status text>)`, where `running` reads `running in background` (NS-8; P14's renderer prints the same line on `artifact_start`) |"""),
]
apply(P, pairs)
