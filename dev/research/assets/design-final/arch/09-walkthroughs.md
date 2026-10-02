
---

## 10. Walkthroughs of the north-star examples

Token figures use §7's measured o200k counts and the estimator of §12.4; they are estimates (no paid calls).
Prices: Sonnet 5.5 at $2 input / $10 output per million tokens, 1-hour cache writes 2x input, reads 0.1x [07 §1].

### 10.1 NS-1: interactive session on a 5 GB object

1. `library(gptr)`: `.onLoad` runs the `on_load()` registry: built-in declarations (3-8 ms [G1 §2.4]) and
   lazy S3 registration; no disk, no network. `pbmc = readRDS(...)` is ordinary R.
2. `gptr()`: capture finds no dots and no prompt; `gptr_has_human()` is TRUE, so route c starts the `console`
   frontend on a new session with `envir = globalenv()` (the caller; never named by the package). Session
   creation: settings merge (trusted `.gptr/settings.json`: `model = sonnet`, `mode = manual`), ambient secret
   discovery, registry resolution, `session_start` hooks, the system prompt frozen (standard preset with
   `ask`, `<documents>` because the user bound `analysis.R` once, `<artifacts>`, `<r_env>`), `store_open()`
   appends the JSONL header in `.gptr/sessions/`, the task callback for user expressions is registered.
   Banner: `gptr 1.0.0 | model anthropic/claude-sonnet-5-5 | mode manual | .gptr/ found` and
   `pbmc <Seurat, 3,012,448 cells x 33,538 features, 5.1 GB>` from the shipped `gptr_describe.Seurat` method
   (S4 accessors, address-keyed size cache, no copy). First provider use: the egress acknowledgement was
   recorded earlier at user scope.
3. The prompt passes the `input` hook chain and becomes the first user message: `<project_instructions>`
   (vignette.Rmd, about 200), `<environment>` (76), `<mode name="manual">` (50), `<workspace>` (about 40 for
   one object), prompt (about 20). Request 1: T0 about 1,490 + tools 820 + T1 about 550 (`<r_env>`, skills) +
   about 390 = **about 3,250 tokens**, with 1-hour anchors on T0 and the project block.
4. SSE bytes -> splitter -> Anthropic decoder -> `message_update` deltas rendered by the console. The model
   sends one `r` call composing the three steps (the `<r_session>` composition rule), with `note =
   "resolution 0.8 because 0.4 merged the two monocyte groups"`.
5. Dispatcher: validation; `gptr_risk()` sees `pbmc` overwritten above `gptr.protect_size` -> level 3;
   `manual` -> ask; the console shows `r  pbmc = FindNeighbors(pbmc, dims = 1:30) ...  allow? [y]es / [a]lways
   / [n]o / [?]`; `?` would say "cannot be undone: pbmc 5.1 GB exceeds gptr.undo_spill_max" (no pre-image, so
   no copy). `y`.
6. FIFO -> `eval_r()` in `globalenv()`, teed to the console; Seurat mutates `pbmc` in memory with no gptr
   copy (the copy-safety suite pins this). Ctrl-C would open the pause menu; a steer typed there is delivered
   after this tool result. Result: collapsed progress output plus `~ pbmc <Seurat> modified` and `+ markers
   <data.frame 4,211 x 7>` (about 200 tokens). A checkpoint record lists `markers` (new) and `pbmc`
   (modified, not restorable).
7. Request 2 = cached prefix + about 350 new tokens; the answer streams (about 150 tokens). `agent_end`.
8. Document: `builtin:documents` renders the NS-7 block below the `gptr()` statement in `analysis.R` (or the
   session transcript), emitting `document_write` first. JSONL gets the assistant message, the tool result
   (with `details`), the checkpoint and a `gptr.doc_block` record.
9. `!dim(markers)` is evaluated in `envir`, printed, queued as a note for the next prompt and recorded as
   `# direct R (no model)`; `/mode auto` appends a mode operator entry at the next turn (no prompt rebuild);
   `/exit` fires `session_end`, closes the store and returns the session invisibly. `pbmc` (clustered) and
   `markers` stay in `globalenv()`. Nothing was reloaded.

Totals: about 6,850 input tokens (about 3,250 cache reads), about 300 output tokens plus thinking: roughly
$0.02. A script-and-Rscript harness would reload the 5 GB object on every run and pay its own 3-18K-token
prompt per request [07].

### 10.2 NS-3: the pipe steers one session

1. `gptr("Load ...") |> gptr("Now run a PCA ...") |> gptr("Plot ...", model = opus)` is nested calls; each
   `gptr()` evaluates its first dot first, so the innermost call runs first: route g creates session `s`
   (Sonnet), which loads `data/counts.csv` with `data.table::fread` because `<r_env>` lists it.
2. The middle call's first dot is an idle `gptr_session`: route f, a follow-up turn on the same object and
   file (plus `<workspace_changes>` only if something changed). The outer call resolves `opus` (a known
   alias, so a variable named `opus` cannot shadow it) to `anthropic/claude-opus-5-5`: a `model_change` entry;
   the hand-off transform keeps text and tool pairs and drops Sonnet's thinking signatures (INFRA-08); the
   first Opus request misses the cache (caches are model-scoped). The plot is shown on the user's device and
   returned to the model as a 768x512 PNG (532 tokens). The value of the chain is `s`; a top-level statement
   gets three blocks `call=1..3`, each with `session=` and `turn=`.
3. `qc = gptr("Run QC on pbmc ...", pbmc)`: new session with `<attached name="pbmc">` (about 150 tokens, no
   copy); the agent calls `gptr_return(qc_flags)`: `qc_flags` is a 12 MB logical bound in `globalenv()`, so
   the session stores its **name and address** (no reference).
4. `table(pbmc$percent.mt > 20)` is logged by the task callback. `qc |> gptr("Use 15% ...")`: route f on the
   idle `qc`; the next user message leads with `<workspace_changes>` (`user ran: table(...)`); the agent
   reassigns `qc_flags` and calls `gptr_return()` again; `qc$value` resolves the name, reflecting the steered
   state (reference semantics), and the user's later in-place edits of `qc_flags` stay copy-free.
5. `gptr_fork(qc) |> gptr("Try a 10% cut-off as well")`: a new session whose store file copies `qc`'s path to
   the last closed boundary with `parentSession` and `gptr.forkOf`; its workspace is an overlay
   `new.env(parent = globalenv())`, so the fork's `qc_flags` lands in the overlay and cannot clobber the main
   line; nothing live is shared; its first request re-reads `qc`'s cached prefix (same model); the block header
   records `fork=<qc id>:<turn>` and replays inside `local({...}, envir = gptr_resume("<id>")$envir)`.

### 10.3 NS-4: System 1 decisions inside control flow

1. `if (gptr("Is this abstract about a randomised controlled trial?", abstract, model = jev))`: the literal is
   the prompt, `abstract` the context; `jev` resolves to `typesafe/jev-latest`, a classifier provider, so
   route a applies and no session is created. One state `{"abstract": "<text>"}`, question `{type: "noul",
   instructions: "... The input is in abstract.", criteria: ...}`.
2. S1 cache lookup (memory before `gptr_init()`, else `.gptr/cache/s1/`, input hash only); a miss is one
   reactor request with the key materialised only for the TypeSafe origin; `noul: 0.97` ->
   `structure(TRUE, class = c("gptr_decision", "gptr_s1", "logical"), prob = 0.97, ...)` goes straight into
   `if()`; a `decision` event fires; nothing is written to the document (inside `if`). About 280 input tokens
   (about $0.00001).
3. `is_rct = gptr("...", abstracts, model = jev)`: 20 states, deduplicated; misses sent 8 at a time with at
   most 3 bounded rounds (20 requests in about 0.4 s [04a]); `table(is_rct)` and `attr(is_rct, "prob")` work;
   at top level the document gets `#> gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0, 2026-09-29)`.
4. `choices = c("liver", "lung", "brain", "other")` -> a `choice` question; probabilities re-keyed by option
   name (the API reorders them [04a]); a `gptr_choice` (classed character), so `tissue == "liver"` is a plain
   logical.
5. `while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev))`: one request per
   iteration unless cached; if `diagnostics()` returns a data frame the batch rule would give one state per row
   and `while()` would error on a vector; the error hint names `I(diagnostics(fit))` [J-req verified].
6. Twenty decisions cost about 6,000 System 1 tokens ($0.00025) against about 66,000 tokens ($0.13 uncached)
   for twenty System 2 judgements; G2 measured about 383 vs 2,174 input tokens per decision (with System 2
   emulation).

### 10.4 NS-6: sub-agents in parallel and across providers

1. `agents = list(stats = agent(model = opus, skills = statistics), code = agent(model = codex), biology =
   agent(model = gemini, skills = single_cell))` is evaluated in the mask binding `agent` to `gptr_agent`;
   identifiers resolve by the gateway rule. Route d: a team session `reviews` (kind `team`).
2. Backends by `auto`: `stats` and `biology` inline (minimal preset, about 1,300 static tokens each instead
   of about 2,900, with the skill preloaded as `<skill_content>`); `code` is `cli` (`codex`). Before spawning
   `codex exec --json`, `gptr_mcp_serve()` starts on 127.0.0.1 with a random port and a bearer token in the
   child's environment, so Codex can evaluate R in the live session through gptr's gate; the review runs in
   Codex's read-only sandbox.
3. One reactor: two HTTP streams and one pipe in one `processx::poll()`; inline R tools go through the FIFO,
   each in its overlay `new.env(parent = envir)` with its own RNG stream and **no binding guard**, so
   `analysis.R` objects are read at their addresses without copying (NS-6's promise); Codex's MCP calls into R
   are serviced by `later::run_now(0)` inside the pump.
4. `reviews$stats`, `reviews$code`, `reviews$biology` are child sessions; `reviews$text` joins the three
   reviews under `### <name> (<model>)` headings; `gptr_usage(reviews)` sums children with routes `api`,
   `plan-cli`, `api`. `reviews |> gptr("Reconcile these into one list of fixes")` continues the team session
   with the reports attached as `<agent_reports>`.
5. `summaries = gptr("Summarise this cohort", cohorts, parallel = 4)`: route d fan-out: one inline child per
   element, four at a time, each reading `cohorts[["<name>"]]` in place; `summaries$text` is a named character
   vector, `summaries[["A"]]` a child session.

### 10.5 NS-7: the script is the history

1. The block of 10.1 lands below the statement exactly as NS-7 shows (§6.9.3 grammar) with `session=` and
   `turn=` keys, `value=markers` when the agent designated it.
2. `source("analysis.R")` in a fresh session: `doc_locate()` matches the statement by content (srcref, else the
   `source()` frame inside `tryCatch`); the block is fresh (prompt hash matches) -> route e returns a replayed
   session with zero tokens (answer text from `.gptr/cache/s2` if kept); `source()` then runs the recorded code
   as ordinary R. gptr never executes the block itself.
3. `options(gptr.replay = "live")` asks afresh under `gptr_source()`, knitr or line-by-line IDE runs (the old
   block is skipped and rewritten); under plain `source()`/Rscript gptr warns and replays (C-17).
4. The agent rewrites an earlier block with `edit` on the document path, routed through the document backend
   (header `date`/`sha` refreshed); a block edited by hand (sha mismatch) is never overwritten in `auto`.
5. Rmd/qmd get a `gptr-<id>` chunk without `#>` lines, so figures render next to the prompt; ipynb gets a
   cell `id = "gptr-<id>"` from gptr's serializer, never while the notebook is open [14 §4.7]. Under Rscript
   writes are deferred to process exit with a crash sidecar.

### 10.6 NS-8: artifacts are Shiny apps

1. `markers` is described in `<attached>` (about 150 tokens); the `<artifacts>` section and the
   `shiny-bslib` skill in the catalog steer the model; it reads the skill once (about 400 tokens).
2. It `write`s `.gptr/artifacts/marker-explorer/app.R` (about 55 lines, about 650 output tokens; level 2),
   then calls `gptr$app("marker-explorer", data = "markers")` in `r` (level 3; `manual` asks and shows the
   code). `artifact-app.R` runs the static checks, snapshots `v001/` (app.R copy, `R/gptr_data.R`,
   `data/markers.rds` through the leaf `saveRDS(compress = FALSE, ascii = FALSE)`), starts the callr child with
   the secret-free `artifact` environment; the child publishes port 4827; the parent checks HTTP 200 and, with
   chromote, a headless session check and a 1000x700 screenshot attached to the result (about 900 tokens).
3. The console prints `artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)` and
   opens the viewer (interactive only); `gptr()` returns and the console is free. Revisions are `edit` +
   `gptr$app()` (v002, same port), edit-sized rather than full rewrites (3.9x cheaper [G2 (a)]).
4. The block records `gptr$app("marker-explorer", data = "markers")` and `#> [app]
   .gptr/artifacts/marker-explorer/app.R`; replay relaunches only when interactive. Shiny instead of HTML/JS
   saves 2.35x tokens; naming the data instead of inlining a 5,000-row frame avoids about 127k tokens [G2 (a)].

### 10.7 NS-11: a whole workflow that reads like R

First run (interactive, consented workspace, `source("workflow.R")`):

1. `prep = gptr(..., pbmc) |> gptr(...) |> gptr(...)`: one session, three turns (10.2), blocks `call=1..3`;
   `source()` parsed the file first, so writing blocks during the run is safe [14 §2.1.3].
2. Hand-written lines run as R; the next turn's `<workspace_changes>` would show `~ pbmc` from the snapshot
   diff.
3. In the loop, `gptr(..., top, model = jev, choices = c(...))` is System 1 in control flow: per-element
   cache, one request per miss, a `gptr_choice` compared with `==` (the `Ops` method returns a plain logical);
   nothing is written to the document.
4. For an unclear cluster, `"Cluster {cl} has ambiguous markers ({top}) ..."` is interpolated from the loop
   variables (§4.1.4) and runs as a two-turn session; being nested in `for`/`if`, it gets no block; the JSONL
   store has the full record.
5. `gptr("Build a Shiny app ...", pbmc)`: `pbmc` exceeds `gptr.artifact_max_bytes`, so `gptr$app()` errors
   with advice and the agent ships small summaries (UMAP coordinates, labels, top markers) by name; a block
   with the replayable `gptr$app(...)` call follows.

Second run: the `prep` blocks replay with zero tokens and their recorded code runs; the System 1 calls hit the
cache (same branches, zero requests); nested investigations of unclear clusters run live again (calls in loops
are program, not history; REQ-24 allows model non-determinism), and with `GPTR_REPLAY=replay` they fail with
`gptr_error_not_recorded`, which is how CI proves the script makes no model calls; the artifact relaunches only
interactively. First run, about 15 clusters and 2 unclear: about 12 System 2 requests (about 55k input tokens,
about 80% cache reads) and 15 Jev requests (about $0.0002).

### 10.8 NS-12: modes and the non-interactive stop

`gptr("Clean up the data directory", mode = plan)` runs the `readonly` preset; R runs in a scratch child
environment; the answer ends in a `<proposed_plan>` saved to `.gptr/plans/` and kept as the pending plan.
`gptr("Go ahead with that plan", mode = auto)` in the same environment receives it once as `<plan from="s12">`
with the notice "using the plan from session s12" and header `plan=s12`. The same script run with
`mode = manual` under Rscript reaches its first action that needs approval and stops with status `blocked` and
`gptr_error_permission`: "r would delete 3 files in data/ (level 3); nobody can approve in a non-interactive
run. Allow it with mode = auto or gptr_permissions(allow = \"r(fn:unlink)\")."
