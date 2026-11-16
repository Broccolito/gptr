# Digest of the gather phase (lead's synthesis; details and file:line in the JSON files beside this)

All numbers measured on the maintainer's Mac (arm64, R 4.6.1) unless marked AWS (the benchmark's host:
Linux x86, 2 vCPU, 16 GiB, R 4.3.3, 2.2-3.5x slower for the same sizing work). gptr source is
/Users/wgu/Desktop/gptr at 5e2992b, the commit the benchmark pinned.

## The headline

- T03 (gptr 1.0.1): A1 median 244 s vs Codex 226 s, with 3-4 vs 19-28 tool calls. gptr's own overhead is
  about 108 s per run. Without it A1 would be about 150 s, 34% faster than Codex (bench-data).
- About 92 s of that is one thing: **computing the exact byte size of the big `raw` object
  (env_snap_size: unique() over ~224M strings), 3-4 times per request, with no shared cache**.
  - twice per call in requests 2/3, in the risk classifier, because the code assigns to `raw` (even
    in a dead `if (!exists("raw"))` branch) and the classifier sizes every existing binding a call
    may overwrite; it runs twice per call (before the hook and again in perm_decide) on both routes.
    AWS: about 13 s each. Local: about 4 s each.
  - request 1: checkpoint_after sizes the new `raw` (AWS 13.9 s), then env_on_agent_end sizes it
    again because the workspace memory keeps its own separate snapshot cache (AWS ~15 s).
  - The general trigger is any assignment to an existing large string-heavy object (`obj = f(obj)`,
    `raw$x = ...`), not only dead branches. A modify call costs 4 walks (local 10.5 s outer, 14 s wall).
- In auto mode (the benchmark's mode) the size changes **no decision**. It matters for protect_size
  (asks before overwriting objects over gptr.protect_size = 1e8 in manual/edits modes), level 3 vs 2
  (level allow rules such as r(level<=2), nested-call level comparisons), and the size shown in the prompt.
- The size budget (env_size_budget, utils-size.R:46, "about 0.07 s") counts parts, not string elements:
  measured 4.2-5.6 s on T03-shaped lists.

## What-if experiments (full T03 size, 1,231 tables, served and native routes, 3 reps)

| Change | Gap around the call, req 2 / req 3 | Behaviour on the 72-row battery |
|---|---|---|
| baseline | 7.92 / 8.09 s (R work 1.0-1.3 s) | reference |
| classify once, reuse in perm_decide when input unchanged after hooks | 4.17 / 4.29 s | identical; a hook rewrite is re-classified |
| overwrite size from a shared cache keyed by address+class+shape+fingerprint | 0.42 / 0.52 s | identical |
| bounded lower bound that stops at protect_size | 0.46 / 0.60 s | identical decisions; size text shows a lower bound |
| skip the size | 0.41 / 0.49 s | NOT acceptable: overwrite level 3 -> 2, level rules flip deny -> allow |
| one size per object version shared by checkpointer + workspace memory | req 1 post-tool 4.29 -> 0.34 s | identical, rewind plans identical |
| everything combined (+ loop patches below) | 0.39 / 0.45 s; outer 9.2 -> 1.6 s; modify call wall 14.05 -> 3.45 s | identical |

Remaining after everything: about 0.34 s is the file-checkpoint scan of 1,231 project-root entries;
with checkpoints off the gap is 0.05-0.08 s. A modify/create of a big object still pays one cold walk in
checkpoint_after (3.3-4.5 s locally): no one has yet tested a bounded size inside the checkpointer.
Stale-cache caveat: a by-reference data.table edit (data.table::set adding columns) keeps address and
fingerprint, so a cached size goes stale (156.7 vs 178.5 MB); the existing env_snapshot reuse already has
this weakness.

## Fixed per-call and per-turn costs (small data, byte-compiled install)

- Native loop, empty workspace: about 135 ms of harness per turn (request rebuild 45-49 ms, response
  accounting 21 ms, dispatcher 35 ms around 21 ms of eval, reactor sleep ~22 ms). Loop patches (per-message
  JSON/token-estimate cache, settings memo, model_resolve memo, fast integer formatter, reactor) cut it to
  77 ms; with a 300-message history 267 -> 100 ms; with 1,000 small objects 265 -> 140 ms.
- Request building is O(history): every model request re-encodes, hashes and token-estimates every message
  (0.55 ms per message per turn: quadratic over a session).
- Every `r` call parses the same code 9-10 times and walks its syntax tree ~12 times (risk_scan x4,
  eval_guard x2, secret_scan x3-4), runs 6 policies (one re-reads up to 4 settings JSON files from disk),
  takes 4 workspace snapshots, 4 eval_session_state and 2 ckpt_state_snapshot. Served route small-data
  overhead outside execution: 0.27-0.31 s per call (load_all) / about 0.06-0.2 s installed.
- Many objects: +0.17 s per call at 1,000 bindings, +2.1-2.3 s at 10,000 (+7.3 s first call); the
  checkpoint settle loop is O(n^2) (match per binding) and env_snap_size walks the ~70-frame call stack per binding.
- File checkpoint scans: two full scans (before and after) per writing call until a single scan exceeds
  0.25 s, then once per request: a "valley" where 150-700 project entries cost +0.17-0.37 s per writing
  call (measured 0.44 s/call at 600 entries vs 0.06 at 0). On CLI routes ckpt_on_cli runs a full sync scan
  at every agent_start (0.31-0.49 s even for pure reads) plus a turn_end scan. Scans re-hash unchanged files
  (no stat-based skip).
- Interactive sessions (person present or .gptr/ exists): a predicted in-place modify of a 0.1-2 GB object
  writes a full disk image before every such call (0.9-3.4 s, ~0.7-1.4 GB written per call).
- peter(raw, "...") sizes each dot argument fresh (dot_facts, gptr-capture.R:18): one full walk per call.
- Transport (Codex CLI route): ~26 ms per call (20 ms session poll + 10 ms relay poll through a file
  mailbox), 0.75-0.9 s per request (new `codex exec` + new Rscript relay + MCP handshake). Claude route:
  12 ms per call, but a new claude child every request under the default --max-budget-usd (0.34 s + 0.3 s).
- Benchmark artifacts: the benchmark loads gptr with pkgload::load_all (no byte compilation): +1.7-2 s
  on the first request, ~10% slower steady state. CRAN users do not pay this.

## Codex for contrast

Codex never reads content: it tokenizes the command, matches prefix rules loaded once per session, runs a
small dangerous-command check, then starts the process under an OS sandbox (Seatbelt / bubblewrap+seccomp).
Measured: Seatbelt adds ~17.5 ms per spawn; `codex sandbox ... true` 63 ms total. C1 pays 0.63-0.78 s per
Rscript launch on AWS (start R, reload packages, re-read data each request). gptr's code-only checks are
already small and constant (parse+walk 0.03-0.05 s, secret scan 0.004 s, eval_guard <= 0.06 s); the only
data-dependent check is the overwrite size. gptr cannot sandbox in-process R (03-architecture.md:1562).

## Correctness gap found (affects any fix)

On the MCP route, call$risk keeps the classification made before the tool_call hook and before a policy
modify (mcp-server.R:269-299); only approved_level uses the final risk. The checkpointers read call$risk
(ckpt_pure_read / ckpt_file_free, ckpt-rewind.R:37-49), so a hook that rewrites the input into file-writing
code can skip the files checkpointer. The native route sets call$risk = dec$risk (agent-dispatch.R:100).
Also, tool_result hooks never run on the MCP route. A classify-once fix must bind the final risk on both
routes, and must re-check the bindings the risk depends on if a hook could change the session between
the two points.

## Not examined

Rewind/undo cost, worker/background agents (possible third classification), nested peter$ calls,
peter$sh, HTTP streaming per-delta redaction, compaction, document recording on large workspaces, Windows
(slower syscalls move the scan valley), why AWS is 2.2-3.5x slower (memory pressure from the +3.4-4.5 GB
transient each sizing allocates on a 16 GiB host is a candidate), T08's unexplained 1.7-2.75 s per-call gap
on AWS.
