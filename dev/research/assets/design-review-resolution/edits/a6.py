from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""- **Trust to execute** (separate from consent). `gptr_trust(path)` records a decision in
  `R_user_dir("gptr", "config")/trust.json` keyed by the normalised project path. A `.gptr/` that arrives by
  clone or copy is untrusted until the user confirms. Trust gates: project settings beyond tightening,
  project extensions and plugin code, project MCP servers (they run commands), `SYSTEM.md` and
  `APPEND_SYSTEM.md`, project `.env` auto-discovery, provider base-URL overrides and the tool and model fields
  of project agent files. Context files (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`) and skill texts are
  read as untrusted user-role data regardless [16 §7.1(3), 14 §4.8]. An interactive session in an untrusted
  project with such resources asks once; non-interactive runs ignore them with a notice.""",
"""- **Trust to execute** (separate from consent). `gptr_trust(path)` records a decision in
  `R_user_dir("gptr", "config")/trust.json` keyed by the normalised project path (`path_key()`) together with a
  **fingerprint** of the trust-gated files; when a pull or a re-clone changes them, the changed resources are
  untrusted again until the user confirms the listed changes [IC-52]. A `.gptr/` that arrives by clone or copy is
  untrusted until the user confirms. Trust gates: project settings beyond tightening, project extensions and
  plugin code, project MCP servers (they run commands), `SYSTEM.md` and `APPEND_SYSTEM.md`, project `.env`
  auto-discovery, provider base-URL overrides, the tool and model fields of project agent files, and the
  **authority of project instructions** [IC-52]. Context files (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`)
  are read as user-role data [16 §7.1(3), 14 §4.8]; in an untrusted project they render as
  `<project_instructions trusted="false">`, which the frozen `<context>` section tells the model to treat as
  information, not commands; non-interactive runs in `auto` or `edits` mode in an untrusted project omit project
  instructions, skills and agents with a notice; only skills of user directories, installed packages and trusted
  projects enter the catalog. Nothing that decides permissions is read from the project tree: remembered answers
  live in the user-level project file. An interactive session in an untrusted project with such resources asks
  once; non-interactive runs ignore them with a notice. Session files from another machine or tracked by git are
  resumed with a freshly frozen prompt and their user turns marked imported; rewind restores stay inside the
  project root and `tempdir()`."""),
("""- **Network, processes, cores, RNG.** No network at load or in examples; catalog refresh only on request; no
  supervised processes or servers in examples; random loopback ports; `browseURL()` only when interactive; at
  most 2 workers when `_R_CHECK_PACKAGE_NAME_` is set; the user's `.Random.seed` is never touched (hash ids,
  time jitter, per-agent L'Ecuyer streams).""",
"""- **Network, processes, cores, RNG.** No network at load or in examples; catalog refresh only on request; no
  supervised processes or servers in examples; loopback ports chosen from RNG-free candidates (never
  `httpuv::randomPort()`, which calls `sample()`); `browseURL()` only when interactive; at most 2 child processes
  per pool when `_R_CHECK_PACKAGE_NAME_` is set; the user's random-number stream is never changed: hash ids, time
  jitter, per-agent L'Ecuyer streams swapped in and restored by `rng_swap()` (without `set.seed()`), and
  `with_seed_preserved()` around third-party code that draws from R's RNG (chromote, shiny, httpuv) [IC-61]."""),
("""**Minimum prefix.** Models with a 4,096-token cache minimum (Haiku 4.5) cache only BP2 in the standard
preset; the `extended` preset exists for them (G4 §4.3.4; BP1 of extended is 4,053 o200k tokens, so even that
is UNCERTAIN [G4 fact-check]).""",
"""**Minimum prefix.** Models with a 4,096-token cache minimum (Gemini 3.x and Haiku 4.5) cache only BP2 in the
standard preset; the `extended` preset exists for them (G4 §4.3.4; BP1 of extended is 4,053 o200k tokens, so even
that is UNCERTAIN [G4 fact-check]). `tools.presets` ships defaults selecting `extended` for `google/gemini-3*` and
`anthropic/claude-haiku-4-5*`, applied only when the catalog's `cache_min` exceeds the projected standard prefix
(o200k times the provider prior) and the session is expected to pass break-even [IC-73]."""),
("""active skills, the plan), the mode and a fresh workspace block; `keep_recent = 0`. No in-place
micro-compaction (+32% cost and 25 invalidated thinking blocks in G4's simulation). Tool output is bounded at
entry, with half the budget once the context exceeds half the threshold.""",
"""active skills, the plan), the mode and a fresh workspace block; `keep_recent = 0`. No in-place
micro-compaction (+32% cost and 25 invalidated thinking blocks in G4's simulation). Tool output is bounded at
entry, with half the budget once the context exceeds half the threshold. For small windows the post-compaction
floor (static prefix + project instructions + re-injection + checkpoint) is checked at freeze: re-injection
budgets shrink to 25% of the threshold, and a model whose floor still reaches the threshold is refused for that
preset; after a threshold compaction the next one waits until the context grew by 20% of the window [IC-71]."""),
("""```r
eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = interactive(),
       budget_tokens = 4000L, guard = TRUE, rng = NULL, record = TRUE)
# -> gptr_eval_result: status (ok | error | timeout | interrupt | blocked | parse_error), events,
#    n_done, n_total, changes (added, modified, removed; wd, options, env var names, packages, devices),
#    elapsed, images, spill, assigned
format_eval_result(res, budget_tokens)
```""",
"""```r
eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(),
       budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE,
       max_images = gptr_opt("r_max_images"))
# -> gptr_eval_result: status (ok | error | timeout | interrupt | blocked | parse_error), events,
#    n_done, n_total, changes (added, modified, removed; wd, options, env var names, packages, devices),
#    elapsed, images, spill, assigned            (contract §5.8, §7.9)
format_eval_result(res, budget_tokens)
```"""),
("""`srcfilecopy()`; static guard (`q()`, `quit()`, `readline()`, `menu()`, `browser()` and friends return an error
result without evaluation);""",
"""`srcfilecopy()`; static guard (`q()`, `quit()`, `readline()`, `menu()`, `browser()` and friends return an error
result without evaluation; `q` and `quit` are flagged in any position, as a value, a `FUN` argument or inside
`match.fun`, `get`, `do.call` [12 fact-check; IC-67]);"""),
("""interruptions recorded with `on.exit()` ("interrupted after 2.3 s; side effects may have occurred"); symbols
printed by name (R8); plots drawn on the user's device when one is open or a human is present and replayed to
PNG at 768x512, res 120 (532 Claude tokens; ragg when installed) [G2 (g)]; `gptr$plot()` sends a larger view;""",
"""interruptions recorded with `on.exit()` ("interrupted after 2.3 s; side effects may have occurred"); symbols
printed by name and `withVisible()` results cleared in place (R8); plots drawn on the user's device when one is
open or a human is present, otherwise on `pdf(NULL)` with the display list enabled (no `Rplots.pdf` in the
working directory; the prior device restored), and replayed to PNG at 768x512, res 120 (532 Claude tokens; ragg
when installed) [G2 (g); IC-67]; at most 3 plots are attached per result (`gptr.r_max_images`), the rest are
stored and listed for `gptr$plot(k)`, image tokens count against the output budget, and older images are
projected as omitted when a request would exceed the provider's image limits [IC-67]; `gptr$plot()` sends a
larger view;"""),
("""`:=`, `set*()`, `<<-`); checkpoint hooks around mutating evaluations (§6.16); `rng` swaps a per-agent L'Ecuyer
stream in for inline sub-agents.""",
"""`:=`, `set*()`, `<<-`); checkpoint hooks around mutating evaluations (§6.16); `rng_swap()` swaps a per-agent
L'Ecuyer stream in for inline sub-agents and restores the user's `.Random.seed` [IC-61]. The evaluator is the
built-in record `r` of the `evaluator` kind, so a plugin can supply a remote or sandboxed one [IC-69]."""),
("""| `worker` | `callr::r_bg(worker_main, package = TRUE, supervise = getOption("gptr.supervise"), cleanup_tree = TRUE, user_profile = FALSE, env = child_env("worker"))` | shipped by name in a spec file (`saveRDS(ascii = FALSE, compress = FALSE)`); results by `export =` | CPU-parallel | JSONL `permission_request`/`ask` forwarded to the parent over stdin/stdout |""",
"""| `worker` | `callr::r_bg(worker_main, package = TRUE, supervise = supervise_default(), cleanup_tree = TRUE, user_profile = FALSE, encoding = "UTF-8", env = child_env_callr(child_env("worker")))` | shipped by name in a spec file (`saveRDS(ascii = FALSE, compress = FALSE)`) together with the session's rank-0 and user registry records, enabled plugins and filters, which the worker re-registers [IC-69]; results by `export =` | CPU-parallel | JSONL `permission_request`/`ask` forwarded to the parent over stdin/stdout and re-classified there [IC-53] |"""),
("""`auto` = inline, except `cli` for CLI-only models [15 verifier]. Limits: 8 tasks per call, 8 inline and 4 CLI
active, workers `min(4, cores - 1)`, 2 whenever `_R_CHECK_PACKAGE_NAME_` is set [13 C-40]; depth 1 by default
(`gptr.max_depth`, at most 2); 50 KB of child text returned per task [15 §3.7].""",
"""`auto` = inline, except `cli` for CLI-only models [15 verifier]. Limits (settings `subagents.*`, options
`gptr.subagents.*` [IC-71]): 8 tasks per team or fan-out started by model code (user fan-outs queue every element
[IC-39]), 8 inline and 4 CLI active, workers `min(4, cores - 1)`, every child pool 2 whenever
`_R_CHECK_PACKAGE_NAME_` is set [13 C-40; IC-60]; depth 1 by default (`gptr.subagents.max_depth`, at most 2); at
most 20 `gptr()` calls per `r` evaluation; budgets charged to the root session [IC-66]; 50 KB of child text returned
per task [15 §3.7]."""),
("""  sampling refused). OAuth: RFC 9728 discovery, pre-registered > CIMD > DCR, PKCE S256, through
  `gptr_login("mcp:<name>")`; a tool call never opens a browser (a classed condition names the login call).""",
"""  sampling refused). OAuth: RFC 9728 discovery, pre-registered > CIMD > DCR, PKCE S256 (metadata without
  `code_challenge_methods_supported` or without S256 is refused, and `iss` is validated per RFC 9207 when advertised
  [16 §4 item 8 and fact-check; IC-71]), through `gptr_login("mcp:<name>")`; a tool call never opens a browser (a
  classed condition names the login call). Server stderr is read by gptr and kept redacted in `tempdir()` unless
  `gptr.mcp_debug` [IC-70]."""),
("""- **Config**: gptr's `mcp.json` (user; project when trusted); Claude Code, Claude Desktop, Codex (TOML
  subset), Cursor, VS Code and Pi configs listed read-only and imported on request; secrets in `env`/`headers`
  registered in the vault.""",
"""- **Config**: gptr's `mcp.json` (user; project when trusted); Claude Code, Claude Desktop, Codex (TOML
  subset), Cursor, VS Code and Pi configs listed read-only and imported on request, found under `user_home()` and
  `app_config_dir()` (on Windows R's `~` is the Documents folder [13 C-56; IC-63]); secrets in `env`/`headers`
  registered in the vault."""),
("""  (`mcp_message`; no port, no token), and loopback Streamable HTTP (`gptr_mcp_serve()`: 127.0.0.1, random port,
  192-bit bearer token in the child's environment, Origin validation, httpuv + later + openssl in Suggests;
  client configs set a tool timeout of at least 3,600 s because HTTP MCP clients apply a 60 s per-request
  timer [07 fact-check]).""",
"""  (`mcp_message`; no port, no token), and loopback Streamable HTTP (`gptr_mcp_serve()`: 127.0.0.1, an RNG-free
  free port, one listening socket with a separate 192-bit bearer token per client, each token bound to its
  session so a request evaluates in that session's environment with its mode, rules and budget [IC-58], Origin
  validation, httpuv + later + openssl in Suggests; client configs set a tool timeout of at least 3,600 s because
  HTTP MCP clients apply a 60 s per-request timer [07 fact-check]). Requests are served only by the outermost
  reactor pump or at an idle console, where a request needing approval is denied with how to allow it [IC-57]."""),
("""`callr::r_bg(artifact_serve, package = TRUE, supervise, cleanup_tree = TRUE, env = child_env("artifact"))`;
the child picks a random 127.0.0.1 port and publishes it by atomic rename, with a parent-PID watchdog; the""",
"""`callr::r_bg(artifact_serve, package = TRUE, supervise = supervise_default(), cleanup_tree = TRUE, encoding =
"UTF-8", env = child_env_callr(child_env("artifact")))`; the child picks a free 127.0.0.1 port from RNG-free
candidates and publishes it by atomic rename, with a parent-PID watchdog, and serves the app only to URLs carrying
a per-launch 128-bit token (multi-user hosts) [IC-71]; the"""),
("""  `write`, files written by model R code and child processes. Restores are 3-way (user edits after the turn are
  kept); never through symlinks or hard links; never into `.git` or `R_user_dir()`.""",
"""  `write`, files written by model R code and child processes. Restores are 3-way (user edits after the turn are
  kept); never through symlinks or hard links; never into `.git` or `R_user_dir()`; only inside the project root and
  `tempdir()` unless the user confirms each outside path [IC-52]. Blob garbage collection keeps every blob that any
  session file of the project references and skips while another live process holds a session lock [IC-71]."""),
("""- **UI backends** (`ui` specs): `console`, `none`, `scripted` (tests), `rstudio` (dialogs; a timed-out dialog
  is a denial with a notice). The UI abstraction is how Shiny or RPC front ends replace the console.""",
"""- **UI backends** (`ui` specs): `console`, `none`, `scripted` (tests), `rstudio` (dialogs; a timed-out dialog
  is a denial with a notice). The UI abstraction is how Shiny or RPC front ends replace the console. Whether anyone
  can be prompted is `gptr_can_prompt()`: true in IRkernel, where `interactive()` is false but `readline()` works
  [18 §2; IC-43]."""),
("""| 13 append-only JSONL tree, RNG-free ids, crash-safe | §6.9.2 `session-store.R` | SIGKILL mid-stream then resume: file parses, last complete message present, nothing duplicated; `.Random.seed` identical over 1,000 appends; fork replays to the source path's context (`test-session-store.R`; P06) |""",
"""| 13 append-only JSONL tree, RNG-free ids, crash-safe | §6.9.2 `session-store.R` | SIGKILL mid-stream then resume: file parses, last complete message present, nothing duplicated; SIGKILL mid-append, resume, three appends: all present and the tree connected; no connection left open; `.Random.seed` identical over 1,000 appends; fork replays to the source path's context (`test-session-store.R`; P06) |"""),
("""| 16 one reactor for streams and children; background serviced by later | §6.1, §6.2, §6.13 | 15's `p10_mixed` shape: 2 inline + 2 worker + 1 CLI interleave within about the slowest agent's wall time; tools never overlap (`test-subagent-backends.R`; P19); background run progresses at an idle console (`test-agent-background.R`, manual/CI-only; P21) |""",
"""| 16 one reactor for streams and children; background serviced by later | §6.1, §6.2, §6.13 | 15's `p10_mixed` shape: 2 inline + 2 worker interleave within about the slowest agent's wall time and tools never overlap (`test-subagent-backends.R`; P19); the CLI leg (a fake CLI joining them) in `test-cli-codex.R` (P20) [IC-36]; background run progresses at an idle console (`test-agent-background.R`, manual/CI-only; P21) |"""),
("""| 22 credentials never stored in transcripts; redaction everywhere | §6.5 | grep of JSONL, wire log, documents, caches, spill files and `format(request)`: zero key bytes; negative control (`test-secrets-e2e.R`; P24) |
| 23 byte-level linear decoding | §6.1 `http-sse.R` | 20,000 deltas consumed in < 1 s CPU; random re-chunking incl. splits inside multi-byte characters gives identical events (`test-http-sse.R`; P04) |""",
"""| 22 credentials never stored in transcripts; redaction everywhere | §6.5 | grep of JSONL, wire logs, documents, caches, spill files, sidecars, MCP and artifact logs, worker spec and result files and `format(request)`: zero key bytes; a redirecting mock receives no key bytes; negative control (`test-secrets-e2e.R`; P24) |
| 23 byte-level linear decoding | §6.1 `http-sse.R` | 20,000 deltas consumed in < 1 s CPU; random re-chunking incl. splits inside multi-byte characters and CRLF pairs, CR-only streams and duplicate `event:` fields gives identical events (`test-http-sse.R`; P04) |"""),
("""| 28 observability | opt-in redacted JSONL wire log (`options(gptr.wire_log = TRUE)`); OpenTelemetry v1.x | one line per request and terminal event, no secrets (`test-http-reactor.R`; P04; secrets grep in P24) |""",
"""| 28 observability | opt-in redacted JSONL wire log per session (`options(gptr.wire_log = TRUE)`); OpenTelemetry v1.x | one line per request and terminal event, no secrets (`test-http-reactor.R`; P04; secrets grep in P24) |"""),
]
apply(P, pairs)
