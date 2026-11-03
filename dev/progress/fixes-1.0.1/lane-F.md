# 1.0.1 fixes, lane F: MCP serving (#103) and Jupyter MCP safety

Branch `claude/fix-F`, cut from `04dca16a`. Decisions D-335 to D-339. The lane has 19 findings:
one high, four medium (two of them the same defect) and fourteen low. The high and all medium
findings are fixed, and so are eleven low ones; the cheat sheet and test-coverage findings only in
part. Tests were written first, seen failing, then made to pass. Three low findings are left to
other lanes or deferred (D-339).

## Fixed

| Commit | Fix | Findings | Tests |
| --- | --- | --- | --- |
| `d0171a88` | Snippets have no rich repr (`repr_html`, `repr_markdown` and `repr_latex` return `NULL`), so Jupyter shows a snippet and `$config` only as the redacted text/plain of `print()`. `format()` and `str()` redact like `print()` (D-336). | live: bearer token in Jupyter's rich output of `h$config` (high). | test-mcp-server.R "snippets keep the token out of format(), str(), knitr and Jupyter's rich output". With repr 1.1.7 it failed for text/html, text/markdown and text/latex before the change. |
| `3048a1ff` | `/mcp serve` hands the chat's mode straight to the internal `mcp_serve_open()`, not through `options(gptr.mode)`, which a session-scope `gptr_config(mode =)` overrode (D-335). | review #103: plan chat to yolo server (correctness and design, two medium). Review #103 tests (low): the `ns_fun()` mock, the `gc()` line, the reuse path and the session-scope mode. | test-mcp-waits.R "MCP serving hands the chat's workspace and mode to R, never a looser session mode" (real server; reuse; no-session console). test-mcp-stop-rng.R now targets `mcp_serve_open()`. |
| `00716cf2` | An explicit `mode =` on a continued session applies when its console opens, as `/mode` does (D-335). | live #103: explicit mode on a resumed console ignored until the first turn (medium). | test-console-repl.R "an explicit mode = on a continued session applies when its console opens". |
| `fe9c2b20` | The help, both vignettes and IC-57 say that serving pauses at Peter's prompt in every console, and that Rscript, knitr, Quarto and a Jupyter kernel have no idle prompt (no answer between cells). A server started where `interactive()` is `FALSE` says so in a notice (D-337). | live #103: no answer between Jupyter cells, with no warning (medium). Review and live #103: docs name only R.app (two low). | test-mcp-server.R "a server started where R has no idle prompt says when it answers". |
| `3ef4dc61` | The cheat sheet's serve row says to keep R idle and names `/mcp serve`. The architecture lists `/mcp [serve]`. PDF regenerated, still 2 pages (D-337). | review #103: cheat sheet and architecture not updated (low). | dev/release/tests/test-pkgdown.R: PASS 22. |
| `4f745289` | An idle refusal's notice starts a row of its own. It shares `message_row()` with the background notices (D-337). | live #103: refusal notice printed onto the R prompt line (low). | test-mcp-server.R "an idle refusal's notice starts a row of its own below R's prompt". test-agent-background.R's row test passes through the helper. |
| `6c89f0c6` | Child waits pump in 20 ms slices, and still check the cap, timeout and echo every 200 ms (D-338). | review #103: 200 ms child-wait floor (correctness and design, two low). Live #103: about 0.4 s per HTTP request during a child wait (low). | test-proc-spawn.R "a child's exit ends a wait outside a pump within a short slice" (0.204 s after the spawn before the change). |
| `a51b5db7` | `proc_run(merge = TRUE)` replaces `bridge_run()`'s copy of the wait loop (D-338). | review #103: duplicated wait loop (low). | test-proc-spawn.R "proc_run(merge = TRUE) sends stderr into the stdout file". The merged-bridge cases in test-mcp-waits.R and test-bridge-sh.R also pass. |
| `0655121a` | `reactor_nested()` decides nesting for `reactor_pump()`'s default and for `run_wait()`, `sdk_work()` and `subagent_schedule()`. `s1_pump()` keeps only the default (D-338). | review #103: nested `peter()` or `gptr_wait()` inside an idle served tool runs sibling R tools (correctness and design, two low). | test-mcp-waits.R "a nested peter() inside an idle served tool runs no sibling R tool". |
| `24ef5e90` | The waits tests check `reactor_nested()` rather than the `tool_depth` counter, and cover the usage text of an unknown `/mcp` argument. | review #103 tests (low): pinned internal counters, untested `/mcp <other>`. | test-mcp-waits.R. |

## Follow-up after verification

An independent verifier re-ran the lane on `418f3a8f` and reported nine low problems. Six are
fixed below, D-337 now explains the undimmed refusal notice, one stays deferred with a corrected
reason and one is the coordinator's.

| Commit | Fix | Problem | Tests |
| --- | --- | --- | --- |
| `47e489b1` | The codex `$env` is a snippet too (still a named character vector that processx and withr take), and `$config` has class `c("gptr_mcp_config", "list")` with `format()` and `print()` methods. `format()` of a plain list unlisted the codex snippet and dropped its class (D-336, 04 section 5.11). | The token still showed in every print, format, str, knitr and repr path of `h$config$codex$env`, and in `format(h$config)`. | test-mcp-server.R "snippets keep the token out of ..." now covers `$config`, each snippet and `$env` through `format()`, `print()`, `str()`, knitr and every repr mimetype. It failed in 10 expectations before the change. |
| `f6b625d7` | `oauth_redirect_setup()` calls `reactor_nested()` instead of an inline copy (D-338). | `R/auth-oauth.R:517` kept the nesting test inline. | test-auth-setup.R sets the reactor's depth instead of mocking `reactor_depth()`. |
| `93b210ac` | The child-exit test's `proc_run()` child sleeps 50 ms. | `proc_run("true")` passed with the 200 ms slice, because the child exits before the first check. | Both halves now fail with `slice_ms = 200L` and pass with 20 ms. |
| `35d571c3` | The server reads `gptr_is_interactive()`, and the test mocks it both ways. | The notice test needed `interactive()` to be `FALSE`. | test-mcp-server.R "a server started where R has no idle prompt says when it answers". |
| `4ef9a1c3` | `session_set_mode(notice = FALSE)` when a console opens: the console gives the yolo notice after its banner, and the jsonl front end on stderr (D-335). | An explicit `mode = "yolo"` on a resumed console printed the notice before the banner. | test-console-repl.R "a continued console opened with mode = "yolo" says so after its banner" (failed 2 >= 1 before); test-console-jsonl.R "a jsonl frontend continued with mode = "yolo" gives the yolo notice on stderr" (fails without the jsonl line). |
| `8f94e42d` | The MCP article no longer says "re-entrantly"; precomputed. | The release spelling gate listed `entrantly (mcp.Rmd:218)`. | The spelling gate lists only words in files outside this lane. |
| records | D-337 says why the refusal notice is not dimmed: it asks the person to act, unlike the dim status line of a settled background session. | D-337 did not mention dimming. | none |

- Deferred, reason corrected: `peter$search` ranking. Lane E's branch does not fix it (it only
  ranks `api` rows after the others, D-330). The name-coverage rule edits the lines lane E rewrote,
  so it belongs in a follow-up on top of lane E's merge (D-339).
- Coordinator's: NEWS.md. This lane does not edit it. Suggested 1.0.1 bullets:
  "Client snippets of `gptr_mcp_serve()`, `$config` and the Codex `$env` no longer show the bearer
  token in Jupyter (IRkernel) or knitr output, or in `format()` and `str()`." and "An explicit
  `mode =` on a resumed chat (`s |> peter(mode = "plan")`) now applies when the console opens, so
  the banner, the prompt and `/mcp serve` use it."

## Deferred or left to other lanes (D-339)

- `peter$search` ranking for obvious queries (live, low): lane E's change does not fix it, and the
  name rule edits the lines lane E rewrote; a follow-up on top of lane E's merge.
- Long tool output in the console transcript (live, low): IC-82 and D-245 say the margin shows each
  printed line. A cap is a console design decision.
- Checkpoint notice reason for an empty project (live, low): lane A replaced the scan worker and
  fixed the time-limit notice (D-310 to D-314). A local fix was written, then dropped, since it
  edited the worker code that lane A deletes.
- The documented `peter$bg()` workaround (review tests, low) has no test.
- Refusal notice extras (live, low, parts 2 to 4): no prompt redraw (readline owns that row), no
  dimming (a refusal asks the person to act), and no suggested rule in the text.
- `kill_all()`'s tree sweep (about 150 ms per child at load 20) predates #103 and is kept.

## Validation

Load average 14 to 30 on 16 cores during the runs.

- `isolated-check.R test '^(mcp-.*|console-.*|proc-.*|bridge-.*|agent-background|agent-run|agent-dispatch|gptr-gateway|gptr-sdk|http-reactor.*|s1-.*|subagent-.*|arch-.*|lint-.*|perm-.*|injection-e2e|cli-common)$'`
  with repr 1.1.7 on the library path: FAIL 4 | WARN 1 | SKIP 28 | PASS 15683. The four failures
  and the warning are the checkpoint-scan cases below.
- Focused runs, each after its fix: `^mcp-waits$` FAIL 0 PASS 72; `^mcp-stop-rng$` FAIL 0 PASS 252;
  `^console-repl$` FAIL 0 PASS 397; `^proc-spawn$` FAIL 0 PASS 233;
  `^(mcp-waits|arch-layers|http-reactor.*|s1-.*|agent-run.*|subagent-team.*)$` FAIL 0 PASS 3195;
  `^(gptr-gateway|gptr-sdk|copy-gateway|console-wait|compaction-wait|agent-background|agent-dispatch)$`
  FAIL 0 PASS 1803; `^(arch-layers|lint-rules)$` FAIL 0 PASS 90.
- `^mcp-server$` fails 3 expectations in "a call served to a CLI route is checkpointed" (the scan
  stopped early, `cp$files` 0/0), and `^console-` failed 1 in test-console-ui.R:353 (the coverage
  notice took the row). Both come from the bounded checkpoint scan under load. The scan code is
  unchanged in this lane. On an untouched `04dca16a` worktree in the same conditions, `^mcp-server$`
  fails the same 3 expectations and `^ckpt-files$` fails 63. Lane A replaces this scan.
- `IRdisplay::prepare_mimebundle()` over every repr mimetype, for a running server's handle,
  `$config` and three snippets (repr 1.1.7, IRdisplay from the live tester's library): text/plain
  only, no token.
- Every changed R and test file lints clean. `isolated-check.R document` leaves no stray diff.
  `dev/release/check-docs.R`: 0 problems. `dev/release/precompute.R` regenerated `mcp` and
  `interactive-console`, and `--check` gives 0 problems.

Follow-up validation (head after the follow-up commits, load average 9 to 23):

- `isolated-check.R test '^(mcp-.*|console-.*|proc-.*|bridge-.*|auth-.*|session-object|agent-background|agent-run|agent-dispatch|gptr-gateway|gptr-sdk|http-reactor.*|s1-.*|subagent-.*|arch-.*|lint-.*|perm-.*|injection-e2e|cli-common)$'`
  with repr 1.1.7 on the library path: FAIL 4 | WARN 1 | SKIP 31 | PASS 17934. The failures and
  the warning are the same checkpoint-scan cases as before (test-mcp-server.R:284-289 and
  test-console-ui.R:353), which fail the same way on `04dca16a`.
- Each new or changed test was seen failing first: the redaction test (10 expectations), the
  yolo banner order (2 >= 1), the jsonl notice (without its line), the child-exit test (both
  halves with a 200 ms slice) and the idle-prompt notice (mocked interactive R).
- A probe with IRdisplay over `$config`, the codex snippet, `$env` and a JSON snippet gives
  text/plain only, without the token. `processx::run(env = c("current", h$config$codex$env))` and
  `withr::with_envvar(h$config$codex$env, ...)` still hand the token to the child.
- Every changed R and test file lints clean. `document` leaves no stray diff. `check-docs`: 0
  problems. `precompute.R mcp` regenerated the article, and `--check mcp interactive-console`
  gives 0 problems. Release self-tests test-docs, test-precompute, test-vignette-brand and
  test-examples pass. The spelling gate in test-gptr-release.R now lists only words outside this
  lane's files (NEWS.md, gptr_tool_result.Rd, gptr_plugins.Rd, gptr_options.Rd, gptr_rewind.Rd,
  teams-and-background.Rmd).
