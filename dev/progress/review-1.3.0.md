# gptr 1.3.0 comprehensive review ledger (2026-11-27)

One review of `main..claude/v1.3.0` at `219b4e22` (memory `gptr-review-cadence`): nine lenses (bridge-r,
bridge-python, console, models, security, cran, simplicity, docs, tests-ci) on Sonnet, each finding
checked by an adversarial verifier and every blocker/high by a second skeptic (workflow
`wf_3c3af010-243`), plus the live checks of 2026-11-27 (R130-28, R130-29). No blocker or high finding
survived. The fix pass (workflow `wf_a7de6e39-4ae`: six Opus implementers on disjoint files, each checked by
Sonnet, no repair round needed) and the coordinator's integration recorded each disposition.

| ID | Sev. | Area | Where | Finding | Disposition |
|---|---|---|---|---|---|
| R130-01 | medium | providers | `R/provider-openai-completions.R:579` | Generic completions branch sends reasoning_effort to models whose data says no effort (xAI grok-4.20-0309-reasoning) | fixed (`01df722a`) |
| R130-02 | medium | cli | `R/cli-codex.R:614` | User's Codex provider env_key / env_http_headers variables never reach the codex child | fixed: the named variables go to the exec's environment (`child_env(set=)`), never argv (`5d7106e0`, `b9b8039b`) |
| R130-03 | medium | docs | `NEWS.md:1` | NEWS 1.3.0 has no intro paragraph and does not say what is breaking | fixed (`b7773440`) |
| R130-04 | medium | docs | `cran-comments.md:3` | cran-comments.md still describes the 1.1.0 resubmission | fixed (`55744e50`) |
| R130-05 | low | bridge-r | `R/mcp-server.R:27` | Instructions of an inspect-only server tell the client to change objects and to use r | fixed; the constant `inspect` description still says "use r for that" (left: a served-tools-dependent description adds more than it fixes) (`c80f3bc0`) |
| R130-06 | low | gptragent | `gptragent/src/gptragent/server.py:371` | Retry after rediscovery reuses the full time budget, so a call can outlast the 300 s tool timeout | fixed (`777d4747`) |
| R130-07 | low | gptragent | `gptragent/scripts/build_brxt.py:112` | Build does not check the bundled skill's metadata version | fixed: the bundled skill carries no version of its own (`b9890d63`) |
| R130-08 | low | gptragent | `gptragent/src/gptragent/discovery.py:439` | R probe runs a project .Renviron, so a repository can run code when `sessions` finds no session | fixed: the probe runs in a new empty temporary folder (works with HOME missing) (`5fdf4d87`, `04f39e52`, `cbb93cb3`) |
| R130-09 | low | cli | `R/cli-codex.R:121` | Codex -c override puts raw newlines into a TOML basic string (env_key_instructions) | fixed (`26ed86ce`) |
| R130-10 | low | cli | `R/cli-codex.R:152` | Codex provider table key is not quoted: an id with dot, equals, quote or newline mis-addresses or breaks the override | fixed: the id is quoted inside `model_providers={"<id>"=...}`; codex 0.157.1 keeps quotes in a dotted `-c` key literally, so the suggested `model_providers."<id>"=` form would break every route (`26ed86ce`) |
| R130-11 | low | bridge-r | `R/auth-secrets.R:466` | Discovery-record secret guard misses paths built from pieces, so serve-<pid>.json read via file.path is only level 1 | fixed (`6eeda432`, `67239d91`) |
| R130-12 | low | providers | `R/provider-anthropic.R:1002` | thinking_budget min/max are stored but never used; fixed budget table sent to budget models | fixed: `adp_budget()` clamps to the record's min/max (`3de71db5`, `cbb93cb3`) |
| R130-13 | low | docs | `pkgdown/assets/cheatsheet.html:351` | Cheat sheet footer still says 'gptr 1.1.0' (HTML and PDF) | fixed (`80e883e6`) |
| R130-14 | low | docs | `NEWS.md:53` | NEWS and the models vignette omit that Claude Code's model probe runs the user's SessionStart hooks | fixed (`89dbb505`, `f471ea3b`) |
| R130-15 | low | docs | `dev/spec/04-interface-contract.md:1535` | Contract 04 gptr_mcp_serve section is stale and D-373's contract edits are missing | fixed (`b46a7e08`) |
| R130-16 | low | console-ci | `tests/testthat/ci-shard.R:9` | test-mcp-advertise.R is missing from the CI shard table (about 21 s counted as 1 s) | fixed (`54ab9781`) |
| R130-17 | low (uncertain) | cli | `R/cli-codex.R:152` | Codex base_url / openai_base_url with embedded credentials goes onto the command line | fixed (`96218b7e`, `cbb93cb3`) |
| R130-18 | nit | gptragent | `.github/workflows/gptragent.yaml:4` | Workflow header comment is garbled | fixed (`b5ce0b51`) |
| R130-19 | nit | gptragent | `gptragent/src/gptragent/server.py:483` | tool_r resolves the session twice, so every r call scans discovery records twice | fixed (`48828091`) |
| R130-20 | nit | console-ci | `R/console-render.R:914` | Compact call row loses the tool name and cursor strip at very narrow widths | fixed (`11d551a7`) |
| R130-21 | nit | cli | `R/cli-common.R:567` | The CLI's own default model triggers the write-in notice 'does not list the model' | no change: intended, asserted by test-cli-discovery |
| R130-22 | nit | gptragent | `.github/workflows/gptragent.yaml:170` | Release job holds contents: write with mutable action tags and a job-wide write token | fixed (`66018ce0`) |
| R130-23 | nit | gptragent | `gptragent/src/gptragent/server.py:32` | DEFAULT_TIMEOUT and MAX_TIMEOUT are the same number | fixed (`2ad00827`) |
| R130-24 | nit | cli | `R/cli-common.R:696` | pcli_discovered() is a single-caller wrapper | fixed (`a6413f70`) |
| R130-25 | nit | providers | `R/catalog-models.R:1783` | ?gptr_models has a word the spell check flags: SessionStart not in code markup | fixed (`1765435b`) |
| R130-26 | nit | docs | `dev/spec/03-architecture.md:524` | Spec 03 still lists the deleted dev/catalog/build_models.R | fixed (`07e3f11c`) |
| R130-27 | nit | docs | `vignettes/interactive-console.Rmd.orig:220` | Vignette says a call's 'lines' are counted, but the contract counts non-blank lines | fixed (`b1215fbc`, `cbb93cb3`) |
| R130-28 | low | console-ci | `R/console-repl.R:1075` | The console banner shows claude-cli/default without naming the model it runs | fixed (`0b6eb2c4`, `cbb93cb3`) |
| R130-29 | low | cli | `R/cli-claude.R:648` | A Claude CLI error ends with '..' when the CLI's detail already ends in a period | fixed (`dc671a80`) |
| R130-30 | medium | console-ci | `R/console-commands.R:385` | `/calls` lists nothing on a CLI route: the calls the CLI makes to gptr's tools are no messages of the session | fixed (this commit) |

## Details

**R130-01** (medium; lenses: models). 1.3.0 removed the compat flag supports_reasoning_effort (xAI had it FALSE). completions_thinking() generic branch never reads model$thinking_effort and sends reasoning_effort whenever a level is set or 'none' for off. xAI's grok-4.20-0309-reasoning has thinking_effort FALSE, so thinking='high' sends reasoning_effort='high', likely an HTTP 400. Regression from 1.2.0; also wrong for future providers.

Fix: Gate the generic branch: `else if (!isFALSE(model$thinking_effort) && (on || none))`. Add a test.

**R130-02** (medium; lenses: security). D-392 forwards the user's model_providers table as -c overrides and the notice tells users to give a key through env_key or env_http_headers. The exec uses env_profile 'cli-codex' with no pass list and child_env() drops secret-named variables, so the named variable is absent and Codex sends an unauthenticated request (401). Failure is safe but the advice cannot work.

Fix: Have pcli_codex_route() return the variable names its table names (env_key, values of env_http_headers) and pass exactly those to the exec via child_env pass=, or drop the notice's env_key advice and state they are not forwarded.

**R130-03** (medium; lenses: docs). The 1.3.0 section jumps to '## Permissions'. It should open with 4-6 lines: the three campaigns (bridge and plugins with recorded served calls, compact tool calls, native model discovery and catalog); that the permission fix is a security fix; that unlike 1.2.0 this release is not purely additive (compact_calls on by default, codex/default runs the CLI's own model, aliases mean the newest model of a family e.g. gpt is gpt-6.2-sol and gemini is gemini-4-neon, supports_reasoning_effort ignored); and that 1.2.0 was not on CRAN so its section is also new to CRAN users.

Fix: Add the intro under '# gptr 1.3.0'.

**R130-04** (medium; lenses: docs). Still says 'This is a resubmission' of 1.1.0, 'minor update (1.0.0 -> 1.1.0)', names the archived 1.1.0 pretests and the gptr_1.1.0.tar.gz sha256. It omits the 1.2.0/1.3.0 changes a reviewer would look for: the discovery record under tools::R_user_dir, CLI probes at /model and run start, and the gptragent/ folder outside the package.

Fix: Rewrite for 1.1.0 -> 1.3.0 (1.2.0 not on CRAN), add discovery record and CLI probe to Consent and side effects, refresh archive name and sha256 after the final build.

**R130-05** (low; lenses: bridge-r). mcp_server_instructions() appends 'Change objects in place under their names...' and the refusal sentence unconditionally, so gptr_mcp_serve(tools='inspect') tells the client to change objects though no tool can. mcp_inspect_refusal() says 'Use r for it' without checking r is served.

Fix: Emit the 'Change objects in place' sentence only when any of r/edit/write is served; when r is not served, drop 'Use r for it' in mcp_inspect_refusal().

**R130-06** (low; lenses: bridge-python). `remaining` is computed once before the attempt loop; attempt 2 after resolve() rescan gets the undiminished budget, so total can exceed roughly 292 s plus attempt 1 and the rescan, past the 300 s client limit. Rare (server restart plus a very long call).

Fix: Compute `remaining = max(1.0, wait - (self._clock() - started))` inside the loop.

**R130-07** (low; lenses: bridge-python). check() compares seven version sources but not skills/*/SKILL.md, though version.py rewrites its `version:` line. A stale skill would ship in the .brxt and the release job would pass. It is 1.3.0 today.

Fix: Read metadata.version from each bundled SKILL.md in check(), or drop the skill's version line and its edit in version.py (simpler).

**R130-08** (low; lenses: security). probe_r runs Rscript with --no-site-file --no-init-file in the server's working directory (the project folder). R still reads ./.Renviron, which can set R_LIBS and R_DEFAULT_PACKAGES to load a repo-local package (running .onLoad) and R_USER_CACHE_DIR, which the bridge adds to its search dirs. Reproduced with plain Rscript. The docstring's claim that no user code runs is overstated. Narrow impact: fires only when no session is advertised in a project the user already trusts.

Fix: Pass cwd=home directory (or tempfile.gettempdir()) to subprocess.run in probe_r and keep the docstring honest.

**R130-09** (low; lenses: models). pcli_toml() escapes only backslash and double quote. env_key_instructions is free text on the allowlist; a value with a newline, tab or control character yields invalid TOML, so every codex run on that route fails to parse the -c override.

Fix: Drop env_key_instructions from pcli_codex_provider_keys (help text only), or escape \n, \r, \t and control characters in pcli_toml(). Shares the control-character fix with R130-10.

**R130-10** (low; lenses: security). The table override is built as paste0('model_providers.', id, '=', ...) with the id bare, while model_provider is quoted. An id like my.prov becomes nested tables, a=b an invalid assignment, so the exec refers to a provider the override did not define. Id comes from the user's own config: robustness only.

Fix: Use pcli_toml(id) for the key (model_providers."<id>"=) and have pcli_toml() escape control characters.

**R130-11** (low; lenses: security). Pre-existing in the 1.2.0 line, first on CRAN in 1.3.0. scan_env_file_re matches the record only as mcp-serve/serve-<pid>.json within one string, while .Renviron and auth.json match by basename. file.path(..., 'serve-4242.json') classifies L1 (auto without asking) versus L3 for the literal path, though the man page and NEWS say reading the record is treated as reading a secret.

Fix: Add `serve-[0-9]+\.json` basename alternative to scan_env_file_re, with a test.

**R130-12** (low; lenses: models). D-393 and gptr_provider docs say thinking_budget = list(min, max) governs a token-budget level and the snapshot converter keeps the range, but no adapter reads it. adp_budget() returns fixed 1024/2048/8192/16384, and google_budget() with per-model values was deleted. A model whose range excludes those values could get HTTP 400. Docs overstate.

Fix: Clamp the budget in adp_budget() to the record's min/max, or drop min/max from converter, record and docs and keep a boolean.

**R130-13** (low; lenses: docs). Both footers (lines 351, 543) and the PDF read gptr 1.1.0 although 1.3.0 edits and regenerates the cheat sheet. check-files.R does not catch it.

Fix: Change both footers to 1.3.0 and re-run dev/release/cheatsheet-pdf.R; optionally make a check fail when the footer differs from DESCRIPTION.

**R130-14** (low; lenses: docs). ?gptr_models says the probe runs SessionStart hooks, but NEWS and vignettes/language-models.Rmd.orig say only 'No prompt is sent and no tokens are spent', surprising users with logging or network hooks.

Fix: Add one clause to the NEWS bullet and the vignette paragraph: Claude Code's probe loads your settings, so your SessionStart hooks run.

**R130-15** (low; lenses: docs). D-373 lists contract-visible edits to 04 IC-58/IC-65 and 11.5, but 04 still shows the 1.1.0 signature and four-tool default, omits inspect, mode, advertise, the discovery record and recorded outside calls, and says 'dedicated session'.

Fix: Update the signature and add two sentences (inspect, mode, advertise; served r and inspect calls are recorded, D-373), or edit D-373's line to say 'not amended here'.

**R130-16** (low; lenses: tests-ci). The new file takes about 21 s (one test spawns Rscript and httpuv, 17 s) but has no row in ci_shard_seconds, so it is weighed at 1 s and a shard runs about 20 s over plan. Well inside the 20-minute budget. test-cli-discovery.R (about 10 s) is also unlisted.

Fix: Add a row "mcp-advertise,21,21,35" after mcp-namespace (and optionally cli-discovery).

**R130-17** (low; lenses: security). Whitelisted base_url, openai_base_url and model_catalog_url are passed verbatim, so https://user:password@host/ puts a credential in argv (visible in ps). Unusual config and the user's own value; real likelihood very low, nit-level hardening.

Fix: Treat a URL containing userinfo (://[^/]*@) as held: leave it off and name it in the existing notice.

**R130-18** (nit; lenses: bridge-python, tests-ci). 'Every job has a 20-minute limit, and its test and build steps shorter ones.' has no verb. Behavior it describes is correct.

Fix: Write: Every job has a 20-minute limit and its test and build steps have shorter ones.

**R130-19** (nit; lenses: bridge-python). tool_r calls resolve(pid) only to read rec.serves('r'), then _forward calls resolve(pid) again; each runs a full scan (up to 5 s per dead record on Windows). Redundant, not a correctness bug.

Fix: Drop the pre-check and let gptr refuse an unserved tool, or move the serves('r') check inside _forward after its single resolve.

**R130-20** (nit; lenses: console). The row is strtrimmed to width minus the '(+N more lines)' count, which can cut into the head. At 22 columns or fewer a multi-line r call shows only an ellipsis and the count. No overflow, approval still prints the code, no security impact; widths 40 and 80 fine.

Fix: Drop the count when it leaves less room than the head needs, or use max(width - nchar(more), head width + 4). Optional under the simplicity rule.

**R130-21** (nit; lenses: models). pcli_write_in() runs for a default run whose id came from discovery; if the configured model is not in the CLI list the user sees a write-in notice though they wrote nothing in. A test asserts this, so it is intended, but the wording contradicts D-392.

Fix: Return early in pcli_write_in() when model$id is 'default' and update the test expectation in test-cli-discovery.R.

**R130-22** (nit; lenses: security). checkout@v6 and astral-sh/setup-uv@v6 are pinned by mutable tag while upload-artifact is pinned by SHA; GH_TOKEN is set at job level so test and sync steps see the write token. Repo-wide convention, not a 1.3.0 regression.

Fix: Pin checkout and setup-uv to SHAs and move GH_TOKEN to the two steps that run gh.

**R130-23** (nit; lenses: simplicity). Both are 280.0, so _wait() defaults then clamps to the same value and the schema prints both. Merge into one TIMEOUT; behavior unchanged.

Fix: Delete DEFAULT_TIMEOUT, rename MAX_TIMEOUT to TIMEOUT, use it in _wait(), line 482 and the schema text (lines 74-75).

**R130-24** (nit; lenses: simplicity). One production caller, pcli_hook_start(), which discards the return value; it rederives the CLI name, re-checks discover and re-reads the cache. Not behavior-neutral to drop the is.function(discover) check since a test (test-cli-discovery.R:142) relies on it, so the simplification is debatable.

Fix: Inline into the hook: if (is.null(pcli_discovery(cli, path))) tryCatch(catalog_inventory(provider_get(...), refresh = TRUE), error = function(e) NULL); delete pcli_discovered() and adjust its tests.

**R130-25** (nit; lenses: docs). spelling reports SessionStart at gptr_models.Rd:68; inst/WORDLIST has no entry. Not a CRAN check failure.

Fix: Write `SessionStart` in backticks in the roxygen text and re-run roxygen (or add to inst/WORDLIST).

**R130-26** (nit; lenses: docs). D-394 replaced it with dev/release/catalog-snapshot.R; dev/README.md was updated, 03 was not.

Fix: Change the row to dev/release/catalog-snapshot.R (P36, D-394).

**R130-27** (nit; lenses: docs). IC-82 shows the first non-blank line and counts the other non-blank lines; the vignette and NEWS say 'the first line' and 'how many lines follow'. The 30-line example holds only without blank lines. Counting code not re-read.

Fix: Say 'non-blank lines' in the vignette sentence (and NEWS if it repeats it).

**R130-28** (low; lenses: live). Live pty, 2026-11-27: after gptr_models(provider='claude-cli', refresh=TRUE) had discovered the default, peter()'s banner read 'gptr 1.3.0 · claude-cli/default · manual · no .gptr/' while /model said 'Model: claude-cli/default (claude-opus-5-5)'. D-391 says pcli_default_model() names the default in /model, /status, the status line and gptr_models(). The banner should name it the same way when the default is already known, without starting a probe (first-run setup must not ask the egress question).

Fix: In repl_model() (or where the banner builds its model field) use the same 'default (<id>)' naming as /model when pcli_default_model() is known from the cache; never probe for it.

**R130-29** (low; lenses: live). Live pty: /model claude-cli/claude-sonnet-9-9-test then a prompt printed 'error: The claude CLI ended the turn: it reported an error: There's an issue with the selected model (claude-sonnet-9-9-test). It may not exist or you may not have access to it. Run --model to pick a different model..' (paste0(..., what, '.') after a detail that ends in '.').

Fix: Append the final period only when the text does not already end in sentence punctuation; add a test.

**R130-30** (medium; lens: live, RStudio 2026-11-27). On the default `claude-cli` route an `r` call
showed as a compact row with `(+3 more lines)`, and `/calls` then said "No tool call yet.": the
calls a CLI route makes to gptr's tools reach the console as tool events (`mcp_serve_call()`) but
never as `tool_call` blocks of the session's messages, which is all `/calls` read. The maintainer's
request was compact rows with the full calls available from the history.

Fix: `mcp_serve_call()` keeps each call of a live run in the session's live state
(`served_calls`), and `/calls` lists them after the messages' calls; D-383, NEWS, `?peter` and the
console article say so.
