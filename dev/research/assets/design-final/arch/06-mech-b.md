
### 6.9 Persistence

#### 6.9.1 Locations

```text
<project>/.gptr/                       created only by gptr_init() or an interactive yes (D-10)
  vignette.Rmd                         project instructions (committed; read as text, never executed)
  settings.json                        project settings (committed; applied only when trusted; may only tighten)
  settings.local.json                  remembered permission answers, transcript target (gitignored)
  .gitignore                           sessions/, cache/s2/, cache/tmp/, checkpoints/, artifacts/*/v*/data/,
                                       artifacts/*/run/, *.lock/, settings.local.json
  skills/  agents/  prompts/  mcp.json project resources (code and MCP servers trust-gated)
  SYSTEM.md  APPEND_SYSTEM.md          optional prompt replacement/addendum (trust-gated)
  sessions/<YYYYmmddTHHMMSS>_<id>.jsonl  (+ <file>.lock/pid)
  cache/s1/<2hex>/<sha256>.json        System 1 answers keyed by input hash (committed by default; no inputs)
  cache/s2/                            System 2 answer text for replay (gitignored by default)
  cache/tmp/                           spill files (pruned after 7 days)
  checkpoints/blobs/<2hex>/<xxh128>[.gz], checkpoints/objects/   undo store (gitignored)
  artifacts/<id>/                      app.R + artifact.json committed; vNNN/data and run/ gitignored
  plans/<date>-<slug>.md               proposed plans
  transcripts/gptr-session-<ts>.R      console transcripts when no document is bound
tools::R_user_dir("gptr", "config")    settings.json, auth.json (0600), trust.json, mcp.json, egress acks
tools::R_user_dir("gptr", "cache")     refreshed model catalog (ETag), pruned by gptr_cache("prune")
tempdir()/gptr/                        sessions, artifacts, caches, checkpoints and plans without a workspace
```

Without a workspace nothing is written outside `tempdir()` except user-level settings the user sets
explicitly; the System 1 cache stays in memory [13 §2.4]. Tests redirect `R_USER_*_DIR` [13 C-44].

#### 6.9.2 Session store (INFRA-13) [02 §4.6, G3]

One kept-open `file(path, "ab")` connection per session; each entry is one line appended inside
`suspendInterrupts()` and flushed; ids from `utils-hash.R` never touch `.Random.seed`; the reader tolerates a
torn last line; a fork writes a new file lazily at its first own message with `parentSession` and
`gptr.forkOf = {id, entry, turn}`, re-chaining the copied path's entry ids [G3 (6); Pi `createBranchedSession`].
Resume rebuilds the context from leaf to root. Compaction, rewind and checkpoints are appended entries; the file
is never rewritten, because secrets are redacted at ingress (§6.5).

#### 6.9.3 History documents (D-08) [14 §3-4, G3 (11)]

Top-level calls only (not nested in functions, loops, `if` or braces, and not inside an agent block) own the
run of blocks immediately after their statement:

```r
gptr("cluster the cells and show me the markers for the three largest clusters")
# >>> gptr:7f3a21 model=anthropic/claude-sonnet-5-5 date=2026-09-29 prompt=3b1c9a0e77d2 session=s4c2e9a01b7 turn=1 value=markers
pbmc = FindNeighbors(pbmc, dims = 1:30)
pbmc = FindClusters(pbmc, resolution = 0.8)
markers = FindAllMarkers(subset(pbmc, idents = 0:2), only.pos = TRUE)
#> 4211 marker genes across 3 clusters
## Decision: resolution 0.8 chosen because 0.4 merged the two monocyte groups.
# <<< gptr:7f3a21
```

Header keys: `model`, `date`, `prompt` (12-hex hash of the prompt *template*), optional `sha` (body hash for
user-edit detection), `call` (k-th call of a pipeline), `tokens`, `cost`, `session`, `turn`, `value` (the
designated name), `fork=<parent>:<turn>`, `plan=<id>`, `status=undone`. The body holds successful
`record = TRUE` code verbatim, `#>` outputs (12 lines max), `## Decision:` notes, bridge digests (`#> sh git
status --porcelain: exit 0, 6 lines`) and artifact paths. Overlay-fork turns replay inside
`local({ ... }, envir = gptr_resume("<id>")$envir)` so they never clobber the workspace. Rmd/qmd get a
separate chunk labelled `gptr-<id>` after the owning chunk, without `#>` lines; ipynb gets a cell with id
`gptr-<id>` and `metadata.gptr`, written by gptr's own serializer (Python float repr, byte-identical round trip
[14 fact-check]) and never while the notebook is open. A top-level System 1 call gets a one-line block
(`#> gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0, 2026-09-29)`); System 1 calls inside control flow write
nothing (the user's control-flow code is the REQ-26(c) record). Undone turns become inert (`#~ ` prefix,
`status=undone`; `eval=FALSE` in Rmd/qmd) [G7].

**Locating and writing.** `doc_locate()` precedence: validated srcref (text must contain this prompt; reject
`.active-rstudio-document`) > `source()`/`sys.source()` frame (identical-expression match, read inside
`tryCatch` with an off switch: CRAN grey zone [14 fact-check]) > knitr/Quarto (`QUARTO_DOCUMENT_PATH`) >
IRkernel (`JPY_SESSION_NAME`, then content) > `Rscript --file=` > IDE (rstudioapi, guarded) > console. Calls
are matched by content and ordinal, never stale line numbers. Writes use raw bytes preserving EOL, BOM and the
final newline, a temp file in the same directory then `file.rename()`, an md5 conflict check with re-locate and
retry; IDE buffers go through rstudioapi with ids (Positron: disk write when the buffer is clean); under
Rscript writes are deferred to `reg.finalizer(onexit = TRUE)` with a crash sidecar. Every write passes the
`document_write` event (fail closed, patchable). gptr writes only documents the user designated or confirmed:
`gptr_doc()`, an interactive yes, or `record = "auto"` in trusted settings; non-interactive runs without a
workspace never write documents.

**Replay modes** (`replay =`, `options(gptr.replay)`, `GPTR_REPLAY`): `auto` (default: a fresh recorded block
is replayed, a missing or stale one runs), `replay` (never call models; a missing block errors
`gptr_error_not_recorded`), `live` (ask afresh and regenerate), `record` (regenerate stale blocks). `gptr()`
never executes a recorded block: in replay it returns a replayed session with zero tokens (answer text from
the S2 cache when present; conversation positioned at the recorded turn of the session file) and the
document's own code runs next. Live regeneration without double execution works under `gptr_source()`, knitr
(scoped label hook) and line-by-line IDE runs; under base `source()`/Rscript, `live` and stale regeneration
downgrade to replay with a warning. Replay is forced when `_R_CHECK_PACKAGE_NAME_` is set and in vignette
builds [13, 14 §4.4.2]. Nested calls have no block: they run live on re-source, or fail with "not recorded"
under `replay`.

**Console transcripts.** An interactive session without a bound document asks once per project where to record
(the IDE's active document, a new `.gptr/transcripts/gptr-session-<ts>.R`, or nowhere), remembered in
`settings.local.json`. Direct R lines (`!expr`) are recorded as `# direct R (no model)` with `#>` output.

**Caches.** S1: per element, key `sha256(canonical_json(endpoint, model, question, type, criteria, input))`,
stores the input hash and the answer, never the input; memory before `gptr_init()`. S2: answer text keyed by
(document, block, prompt hash), redacted at ingress, gitignored by default (privacy over Quarto-style
commit) [C-31]. `gptr_cache("prune")` removes entries of deleted blocks, S1 entries unused for 90 days and
`cache/tmp` older than 7 days (CRAN "actively managed" [17 fact-check]).

### 6.10 Consent, trust and egress (REQ-02)

- **Consent to write.** `.gptr/` only through `gptr_init()` or an interactive yes; documents only when
  designated or confirmed (§6.9.3); `R_user_dir()` small and pruned; everything else in `tempdir()`. Never
  name `.GlobalEnv`; evaluate only in the caller's frame or an explicit `envir`; examples pass
  `envir = new.env()` and use the fake provider [13 C-24].
- **Trust to execute** (separate from consent). `gptr_trust(path)` records a decision in
  `R_user_dir("gptr", "config")/trust.json` keyed by the normalised project path. A `.gptr/` that arrives by
  clone or copy is untrusted until the user confirms. Trust gates: project settings beyond tightening,
  project extensions and plugin code, project MCP servers (they run commands), `SYSTEM.md` and
  `APPEND_SYSTEM.md`, project `.env` auto-discovery, provider base-URL overrides and the tool and model fields
  of project agent files. Context files (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`) and skill texts are
  read as untrusted user-role data regardless [16 §7.1(3), 14 §4.8]. An interactive session in an untrusted
  project with such resources asks once; non-interactive runs ignore them with a notice.
- **Egress acknowledgement.** The first use of each provider (and each CLI route) shows what automatic context
  is sent (workspace listing, `<r_env>`, project instructions, attached-object descriptions) and records an
  acknowledgement at user scope; a non-interactive run needs a configured acknowledgement
  (`gptr_config(egress = list(anthropic = "ack"), .scope = "user")`) or `.opts$context = "none"`, otherwise it
  stops with `gptr_error_egress` [13 C-34, 13 §2.2 line 126]. No telemetry.
- **Network, processes, cores, RNG.** No network at load or in examples; catalog refresh only on request; no
  supervised processes or servers in examples; random loopback ports; `browseURL()` only when interactive; at
  most 2 workers when `_R_CHECK_PACKAGE_NAME_` is set; the user's `.Random.seed` is never touched (hash ids,
  time jitter, per-agent L'Ecuyer streams).

### 6.11 Caching and compaction (D-19) [G4]

**Layout.** The tool array and system prompt are frozen at session start and sent as two system blocks: T0
(static sections) and T1 (machine/project: skills and MCP catalogs, `<r_env>`, addendum). The first user
message is rendered once and reused byte for byte after compaction: `<project_instructions>` (AGENTS.md and
CLAUDE.md from root to cwd, then `.gptr/vignette.Rmd` last and additive), `<environment>`, `<mode>`, `<plan>`
(once), `<workspace>`, `<attached>`, `<skill_content>` for preloaded skills, then the prompt. Everything later
is appended in the newest turn: `<workspace_changes>` only when non-empty; skill activations; mode changes
(operator message where the provider supports mid-conversation system messages, else user text); steering
relays after tool results; section patches (Pi's diff semantics); tool additions (Anthropic `tool_addition`,
OpenAI `additional_tools`, elsewhere the R-function route with a note). Each entry is serialised once per
(entry, api, same-model flag); bodies are assembled by string concatenation with the growing array last.

**Breakpoints** [G4 §3.7, §4.3.1]: Anthropic BP1 at the end of T0 (1 h), BP2 on the project block (1 h),
top-level automatic caching for the tail; OpenAI Responses: developer message with explicit breakpoints on T0,
T1 and the project block, implicit tail, `prompt_cache_key = "gptr:" + 12 hex of the project root`; Gemini
implicit; OpenRouter `session_id` plus `cache_control` for anthropic/google models.

**Tail TTL: gap-based rule.** The tail uses the 5-minute TTL, switching to 1 hour after any inter-request gap
longer than 240 s. The adaptive rule of G4 §4.3.3 is rejected: its fact-check showed it costs 33% over the
best policy in a fast loop, while the gap rule is within 2.1% of the best there and cheaper than every fixed
policy in the long-compute regime [G4 fact-check; J-req]. The rule is a `cache_policy` spec, replaceable.

**Minimum prefix.** Models with a 4,096-token cache minimum (Haiku 4.5) cache only BP2 in the standard
preset; the `extended` preset exists for them (G4 §4.3.4; BP1 of extended is 4,053 o200k tokens, so even that
is UNCERTAIN [G4 fact-check]).

**Prefix guard.** Each request is compared with the previous one for the same (provider, model); a broken
byte prefix emits `cache_break` naming the first differing element and the culprit handler; the guard resets
on `session_tree` (rewind) [G4 §4.3.5, G7].

**Compaction** (`compactor` spec, replaceable) [G4 §4.4, G2]:
`threshold = min(window - min(max(30000, 0.10 * window), 0.25 * window), window - max(16384, max_output +
2 * r_cap), gptr.compact_at = 200000)`, plus the cold rule (idle beyond the tail TTL and context >= 100k:
compact first). Checks run between tool rounds, before a new prompt and after an overflow error (one
compact-and-retry, INFRA-26). The checkpoint request is sent in-conversation (a cache read; `max_tokens =
2048`; a tool-calling reply is rejected) with G4's verbatim `<compaction_request>` prompt; the compaction
entry holds the reused project and environment blocks, a `<checkpoint>` (model summary plus harness-extracted
state: user messages including steering, objects with class, shape and creating code, decisions, files,
active skills, the plan), the mode and a fresh workspace block; `keep_recent = 0`. No in-place
micro-compaction (+32% cost and 25 invalidated thinking blocks in G4's simulation). Tool output is bounded at
entry, with half the budget once the context exceeds half the threshold.

### 6.12 Evaluator [12 §3-4]

```r
eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = interactive(),
       budget_tokens = 4000L, guard = TRUE, rng = NULL, record = TRUE)
# -> gptr_eval_result: status (ok | error | timeout | interrupt | blocked | parse_error), events,
#    n_done, n_total, changes (added, modified, removed; wd, options, env var names, packages, devices),
#    elapsed, images, spill, assigned
format_eval_result(res, budget_tokens)
```

Hand-rolled, not `evaluate` (sink breakage, sticky references, options leak [12 §2.A2]): parse with
`srcfilecopy()`; static guard (`q()`, `quit()`, `readline()`, `menu()`, `browser()` and friends return an error
result without evaluation); `sink()` capture cleaned up in `suspendInterrupts()`; per-expression
`setTimeLimit(elapsed, transient = TRUE)` reset to `Inf` (no timeout when a human is present, the pause menu
instead; `gptr.r_timeout = 3600` otherwise) [J-cran graft]; messages and warnings through calling handlers
created in a frame that does not hold the home (§6.4 R2-R3); errors with a trimmed, redacted traceback;
interruptions recorded with `on.exit()` ("interrupted after 2.3 s; side effects may have occurred"); symbols
printed by name (R8); plots drawn on the user's device when one is open or a human is present and replayed to
PNG at 768x512, res 120 (532 Claude tokens; ragg when installed) [G2 (g)]; `gptr$plot()` sends a larger view;
state diff from snapshots before and after plus static assignment targets (replacement functions, `assign()`,
`:=`, `set*()`, `<<-`); checkpoint hooks around mutating evaluations (§6.16); `rng` swaps a per-agent L'Ecuyer
stream in for inline sub-agents. Model text: output, messages, warnings, error and traceback, "[plot N
attached]", state-change lines (`~ pbmc <Seurat> modified`, `+ markers <data.frame 4,211 x 7>`), a status
line, and, above the budget, head 40% / tail 60% by lines with the notice `[... n lines omitted; all:
gptr$out(<id>)]` (about 26 tokens vs 64 with a temp path [G5 fact-check]). Console output is teed with carriage
return progress collapsed.

### 6.13 Sub-agents and concurrency (D-12) [15]

| Backend | Process | Objects | Parallelism | Ask/permission |
|---|---|---|---|---|
| `inline` (default via `auto`) | same process, same reactor | zero-copy reads through the overlay `new.env(parent = envir)`; writes stay in the overlay; `export =` names written back on success; no binding locks | I/O interleaved; R tools serialised through the FIFO | queued to the parent UI one at a time |
| `worker` | `callr::r_bg(worker_main, package = TRUE, supervise = getOption("gptr.supervise"), cleanup_tree = TRUE, user_profile = FALSE, env = child_env("worker"))` | shipped by name in a spec file (`saveRDS(ascii = FALSE, compress = FALSE)`); results by `export =` | CPU-parallel | JSONL `permission_request`/`ask` forwarded to the parent over stdin/stdout |
| `cli` | the `cli-claude`/`cli-codex` adapter process | files; live R through gptr's MCP server (§8) | parallel processes | CLI permission mapping (§8.3) |

`auto` = inline, except `cli` for CLI-only models [15 verifier]. Limits: 8 tasks per call, 8 inline and 4 CLI
active, workers `min(4, cores - 1)`, 2 whenever `_R_CHECK_PACKAGE_NAME_` is set [13 C-40]; depth 1 by default
(`gptr.max_depth`, at most 2); 50 KB of child text returned per task [15 §3.7]. Inline children run the
`minimal` preset, inherit the parent's mode (only tightened), get their own RNG stream, and code containing
`<<-`, `assign(envir =)`, `:=` or `set*()` is level 2 (denied in parallel runs). `fork` and mirai/mori are
v1.x. Five inline agents with an R tool on a shared 381 MB vector took 5.2 s concurrently vs 14.0 s
sequentially, every agent seeing the same address [15 §2.3].

### 6.14 MCP (D-14) [16 §4, G1 §2.5]

- **Client** (`mcp-client.R`): speaks 2025-11-25 and 2026-07-28: `server/discover` probe (5 s), else legacy
  `initialize`; over HTTP the 400 body decides; the era is cached per server config. stdio through the process
  engine (with the `.cmd` shim rule) and the `mcp` child-env allowlist; Streamable HTTP on the reactor;
  pagination; progress re-arms the idle timer; timeouts and interrupts send `notifications/cancelled`; MRTR
  `input_required` at most 5 rounds (elicitation to the `ask` UI, roots answer the project directory,
  sampling refused). OAuth: RFC 9728 discovery, pre-registered > CIMD > DCR, PKCE S256, through
  `gptr_login("mcp:<name>")`; a tool call never opens a browser (a classed condition names the login call).
- **Exposure**: default `r`: `gptr$mcp$<server>$<tool>(...)` closures generated from the JSON Schema with
  argument coercion; one signature line each in the T1 `<mcp>` catalog within 1,500 tokens (least recently
  used descriptions trimmed first; overflow through `gptr$search()`); per-tool `direct`, `deferred`, `hidden`.
  Tool descriptions and results are marked as server content, not user instructions.
- **Config**: gptr's `mcp.json` (user; project when trusted); Claude Code, Claude Desktop, Codex (TOML
  subset), Cursor, VS Code and Pi configs listed read-only and imported on request; secrets in `env`/`headers`
  registered in the vault.
- **Server** (`mcp-server.R`): a dispatcher exposing the session's `r`, `read`, `edit` and `write` through the
  permission gate. Transports: the claude CLI's in-process `sdk` type over the control protocol
  (`mcp_message`; no port, no token), and loopback Streamable HTTP (`gptr_mcp_serve()`: 127.0.0.1, random port,
  192-bit bearer token in the child's environment, Origin validation, httpuv + later + openssl in Suggests;
  client configs set a tool timeout of at least 3,600 s because HTTP MCP clients apply a 60 s per-request
  timer [07 fact-check]).

### 6.15 Artifacts (D-17) [17 §4, G2 (a)]

The model `write`s `<root>/artifacts/<id>/app.R` (level 2) guided by the `shiny-bslib` skill, then calls
`gptr$app(id, data = c("markers"))` in `r` (level 3: launching model-written code). `gptr$app()` runs static
checks (parses; ends with `shinyApp()`; no `setwd()`, installs, `runApp()` or reads outside the snapshot),
writes the immutable snapshot `vNNN/` (app.R copy, `R/gptr_data.R` loader, `data/<name>.rds` through the leaf
`saveRDS(compress = FALSE, ascii = FALSE)` wrapper, capped by `gptr.artifact_max_bytes`), starts
`callr::r_bg(artifact_serve, package = TRUE, supervise, cleanup_tree = TRUE, env = child_env("artifact"))`;
the child picks a random 127.0.0.1 port and publishes it by atomic rename, with a parent-PID watchdog; the
parent polls the port file, checks HTTP 200 through the reactor, then (chromote installed) a headless session
check with a 1000x700 screenshot attached to the `r` result (about 900 tokens). Revisions are `edit` +
`gptr$app()` (vNNN+1, same port). The viewer opens only interactively; children stop through
`gptr_artifacts(id, stop = TRUE)`, `.onUnload` or R exit. Blocks record `gptr$app("marker-explorer", data =
"markers")` and `#> [app] .gptr/artifacts/marker-explorer/app.R`; replay relaunches only interactively.
`kind = "html"` wraps raw HTML/JS inside a Shiny app (S-5 fallback). Token cost: a 41-token prompt pointer plus
skill on demand instead of a 350-token tool and 360-token section [P-B PB-E2]; Shiny needs 2.35x fewer tokens
than HTML/JS for the same app (20 apps, 5 levels) and a full rewrite costs 3.9x an edit [G2 (a)].

### 6.16 Checkpoints, undo and rewind [G7]

- **Objects.** Per mutating tool call: capture every value binding up to `gptr.undo_capture_max` (1e8 bytes)
  by reference and predicted targets up to `gptr.undo_max_bytes` (1e9); for predicted in-place edits of larger
  objects write an eager disk image (`serialize(ascii = FALSE, xdr = FALSE)`, up to `gptr.undo_spill_max`,
  2e9, about 0.3-0.7 s per GB); deep-copy data.table targets of `:=`/`set()`; report reference objects
  (environments, R6, external pointers) as not restorable. Pre-images are bindings in a private environment,
  released with `rm()`; list and S4 pre-images are defused before dropping (R6). After the call, settle: an
  address change means modified; release the rest. At turn end spill the largest held images or drop the
  oldest (defuse + `rm()`), and drop images older than `gptr.undo_turns` (20).
- **Files.** A content-addressed store (XXH128 via rlang, gzip level 1, deduplicated), a baseline of small
  source-like files (1 MB each, 100 MB total) at the first mutating call, a pruned walk after each mutating
  call (per-turn scanning when a walk exceeds 250 ms), pre-capture of predicted literal paths; covers `edit`,
  `write`, files written by model R code and child processes. Restores are 3-way (user edits after the turn are
  kept); never through symlinks or hard links; never into `.git` or `R_user_dir()`.
- **Rewind.** `gptr_rewind(s, turn = -1L, ...)` undoes checkpoint records from the leaf to the lowest common
  ancestor (newest first), redoes those down to the target, appends `gptr.rewind` parented at the target (the
  durable leaf; the JSONL stays byte-append-only), hands back the undone prompt, returns `s` invisibly (so it
  pipes), warns `gptr_warning_rewind_partial` on a partial restore and errors `gptr_error_busy` on a running
  session. A full restore sends the model nothing (the next prefix is byte-identical; a cache hit is LIKELY);
  a partial one sends `<workspace_changes since=... reason="rewind">` (about 87 tokens). `gptr_fork()` stays the
  only way to get a second object.
- **Modes.** plan: conversation only; manual/edits: the permission detail view says "cannot be undone" when
  capture is impossible and offers "spill first"; auto: a 25-token notice. REPL: `/undo`, `/redo`, `/rewind`,
  `/rewind <k>`, `/checkpoints`. Plugins add `checkpointer` specs and `gptr_preimage()` S3 methods.

### 6.17 Console and front ends [18]

- **REPL** (`frontend` "console"): `readline()` when interactive, one persistent `file("stdin")` under
  `.stdin = TRUE`; input grammar: natural language, `/command`, `!expr` (evaluated in `envir`, added to the
  next prompt's context) and `!!expr` (not added), fenced ```` ```r ```` blocks, `"""` multi-line prompts,
  trailing backslash, `@file` and `@object` mentions; a warning near the readline line limit (4,095 bytes on
  R < 4.5, 8,190 on R >= 4.5 [18 fact-check]); optional history through `utils::timestamp()`
  (`gptr.history`). Banner: `gptr 1.0.0 | model ... | mode ... | .gptr/ found` plus the workspace summary.
- **Rendering**: chunk-invariant, width-aware markdown stream renderer; colours only when
  `cli::num_ansi_colors() > 1`; `\r` only on dynamic TTYs; spinner ticked from the reactor; `flush.console()`
  after deltas. Verbosity: 0 in knitr/testthat, 1 under Rscript (progress to stderr), 2 at the console.
- **Slash commands** (`command` specs): `/help`, `/exit`, `/model`, `/mode`, `/plan`, `/tools`, `/env`,
  `/compact [focus]`, `/cost`, `/context` (token ledger), `/status`, `/clear`, `/resume`, `/fork`, `/doc`,
  `/skills`, `/skill:<name>`, `/mcp`, `/undo`, `/redo`, `/rewind`, `/checkpoints`, `/retry`, plus prompt
  templates as `/<name> args`. Commands are recorded as comments in transcripts.
- **UI backends** (`ui` specs): `console`, `none`, `scripted` (tests), `rstudio` (dialogs; a timed-out dialog
  is a denial with a notice). The UI abstraction is how Shiny or RPC front ends replace the console.
- **Other front ends**: `knit_print` for sessions and System 1 vectors; the JSONL event sink (`frontend`
  "jsonl": redacted Pi-named events on a connection, used by worker children and by agentic layers written in
  other languages) [P-B graft].

### 6.18 INFRA-01..28 compliance (S-10) [10a §14]

| INFRA | Design element | Acceptance test (file; plan) |
|---|---|---|
| 01 own curl-multi transport, `pipewait = 0` | §6.1 `http-reactor.R`, `http-request.R` | first delta within 0.35 s of the mock writing it; 6 streams of 1.00-2.25 s finish within 10% of the slowest (`test-http-reactor.R`; P04) |
| 02 normalised event protocol, failures as events | §5.4, adapters, `provider-events.R` | golden event sequences per fixture; a server error and a truncated connection each yield exactly one `error` event with the partial (`test-provider-*.R`; P01, P12) |
| 03 interrupt-safe streaming: resume, steer, abort | §6.2, `console-interrupt.R`, `reactor_cancel()` | scripted SIGINT at TTFT, mid-body, mid-tool: continue resumes, steer delivered after the turn, abort closes the socket (mock logs the disconnect) and the partial equals what was received (`test-console-interrupt.R`, skip_on_cran; P14) |
| 04 honest partial/failed turns, projection | §5.2, `provider-transform.R`, `agent-dispatch.R` | a 401 is recorded but projected out; after abort every `tool_use` has exactly one truthful result (`test-provider-transform.R`; P05) |
| 05 layered timeouts, no total | §6.1 | mock holding headers -> `gptr_error_timeout_first_byte`; a 10-minute stream at 1 byte/10 s completes; a stall -> idle timeout (`test-http-request.R`; P04) |
| 06 bounded retry honouring Retry-After | §6.1 `http-retry.R`, `s1-client.R` | `retry-after: 2` retried after about 2 s; `3600` fails at once stating the delay; overload before the first delta retried; after deltas surfaced with the partial; spend-cap 429 never retried (`test-http-retry.R`; P04) |
| 07 message model with provenance, byte-exact opaque data, images in results | §5.2, `provider-message.R` | byte-identical re-serialisation of thinking/signature/redacted, encrypted reasoning with `fc_`/`call_` ids, Gemini thought signatures; PNG tool result sent as native image (`test-provider-anthropic.R` etc.; P12) |
| 08 cross-provider hand-off | `provider-transform.R` | Anthropic -> Responses -> Gemini bodies validate against schema fixtures and contain no foreign opaque fields (`test-provider-transform.R`; P05, fixtures P12) |
| 09 tool-call validation; no execution after `length`/`refusal` | `json-schema.R`, `json-partial.R`, `agent-dispatch.R` | `{"n":3}` without `code` -> error result, function not called; a `max_tokens` stop mid-call -> error result + `done(length)` (`test-agent-dispatch.R`; P06) |
| 10 never-throw dispatcher, source order, sequential `r` | `agent-dispatch.R` | property test with throw, interrupt, warn-as-error and a 30 s timeout inside tools; paired start/end events (`test-agent-dispatch.R`; P06) |
| 11 allow/deny/ask/modify hooks, modes, fail closed | §6.8, `perm-gate.R`, `ext-events.R` | 18's mode x risk matrix; `modify` visible in the transcript; denial with reason; throwing policy denies (`test-perm-gate.R`; P11) |
| 12 own loop with steering after tool results, `max_turns`, stepwise | `agent-loop.R`, §6.2 | report 02's 24 loop checks; a steer enqueued during a tool is on the wire after the tool-result message; `max_turns = 3` stops with `gptr_error_max_turns` status (`test-agent-loop.R`; P06) |
| 13 append-only JSONL tree, RNG-free ids, crash-safe | §6.9.2 `session-store.R` | SIGKILL mid-stream then resume: file parses, last complete message present, nothing duplicated; `.Random.seed` identical over 1,000 appends; fork replays to the source path's context (`test-session-store.R`; P06) |
| 14 session semantics for `\|>`; fork shares nothing | §5.1, `session-object.R` | `s2 = gptr_fork(s)`: a listener on `s2` never fires for `s`; different leaves; overlay writes do not reach `s$envir` (`test-session-object.R`; P06) |
| 15 no package-global run state | §2.2 rule 5 | two concurrent sessions with the same model: each usage equals its own requests; tool context correct in interleaved tools (`test-agent-run.R`; P06) |
| 16 one reactor for streams and children; background serviced by later | §6.1, §6.2, §6.13 | 15's `p10_mixed` shape: 2 inline + 2 worker + 1 CLI interleave within about the slowest agent's wall time; tools never overlap (`test-subagent-backends.R`; P19); background run progresses at an idle console (`test-agent-background.R`, manual/CI-only; P21) |
| 17 providers as data + closed adapter set, versioned interface | `provider-registry.R`, `gptr_provider()`, `gptr_adapter()` | Ollama added by data only; the fake provider and a plugin adapter pass `gptr_check()` (`test-provider-registry.R`; P05) |
| 18 System 1 first-class, typed, vectorised, abstention | §4.1.5, `s1-*.R` | `if (gptr(..., model = jev))` on the mocked `/systemone`; 100 items issue concurrent requests capped by `max_active`; `min_confidence` + `uncertain` behave per policy; `choices` returns classed character (`test-s1-route.R`; P13) |
| 19 subscription CLIs under processx; SIGINT then kill; own session ids | §8.3, `cli-*.R` | three concurrent fake-CLI agents stream into the reactor; abort leaves no process tree; usage populated (`test-cli-claude.R`, `test-cli-codex.R`; P20) |
| 20 usage and cost by route, TTL-split cache writes | §5.5, `provider-usage.R` | the 1 h cache-write fixture gives the documented dollar amount; per-agent sums equal the session total; route column present (`test-provider-usage.R`; P05) |
| 21 rate-limit awareness gating admission | §6.1 `http-retry.R` | with low remaining-request headers, a 20-agent fan-out never exceeds the budget and never sleeps in a callback (`test-http-retry.R`; P04) |
| 22 credentials never stored in transcripts; redaction everywhere | §6.5 | grep of JSONL, wire log, documents, caches, spill files and `format(request)`: zero key bytes; negative control (`test-secrets-e2e.R`; P24) |
| 23 byte-level linear decoding | §6.1 `http-sse.R` | 20,000 deltas consumed in < 1 s CPU; random re-chunking incl. splits inside multi-byte characters gives identical events (`test-http-sse.R`; P04) |
| 24 fake provider, mock server, fixtures, conformance | P01 helpers, `gptr_check()` | the INFRA suite runs offline under `--as-cran` in < 60 s (CI timing assertion outside CRAN; P24) |
| 25 structured output coexisting with tools | `.opts$returns` (adapter structured-output option; forced-tool fallback); S1 emulation | a run with tools plus `returns =` yields the typed `$value` and a transcript that still contains the tool calls (`test-agent-run.R`; P06 with P12 adapters) |
| 26 loop-owned context management, one overflow retry | §6.11, `agent-run.R`, `prompt-compact.R` | an overflow error triggers one compaction and one retry with a compaction entry; a second overflow surfaces as an error (`test-prompt-compact.R`; P07) |
| 27 rendering decoupled from transport | §2.2 rule 2, `console-render.R` | the same run gives byte-identical transcripts at verbosity 0, 1 and 2 (`test-console-render.R`; P14) |
| 28 observability | opt-in redacted JSONL wire log (`options(gptr.wire_log = TRUE)`); OpenTelemetry v1.x | one line per request and terminal event, no secrets (`test-http-reactor.R`; P04; secrets grep in P24) |
