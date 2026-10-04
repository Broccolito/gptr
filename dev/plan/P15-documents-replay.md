# P15 Documents and Replay Implementation Plan

> **Design amendment IC-74 (2026-10-03):** Read
> [`../spec/07-local-ollama.md`](../spec/07-local-ollama.md), especially the
> ownership and acceptance matrix in section 6, before executing this plan.
> Mixed Ollama chat/decision models, image decisions, model-level dispatch,
> locality and calibration rules override conflicting code examples below.
> The original task count and exact PASS counts predate this amendment;
> reconcile the affected steps before implementation. No implementation has
> been performed as part of this design update.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the user's script, R Markdown, Quarto or Jupyter document both the harness and the history (REQ-24-26): every top-level `gptr()` call gets an agent block of the code it ran, re-sourcing replays recorded blocks with zero model calls, and stale or live blocks regenerate in place without running the old code.

**Architecture:** Six files of area `doc`: `doc-blocks.R` (block grammar, hashes, the call scanner and ownership, the recorded block content and the writer `doc_upsert()`), `doc-io.R` (raw-byte atomic I/O keeping EOL/BOM/final newline, document locks, the user-level project file, deferred Rscript writes with a crash sidecar, Jupyter pending blocks, the rstudioapi/Positron backend), `doc-formats.R` (the `r`, `rmd`, `qmd`, `ipynb` and `transcript` `doc_format` specs, gptr's own nbformat serializer, inert blocks, `builtin:documents`), `doc-locate.R` (the locator of architecture 6.9.3), `doc-replay.R` (write consent, the replay decision, the S2 answer cache, the `document` route, the `doc.*` services and hooks, `gptr_doc()`, `gptr_blocks()`, `gptr_cache()`, `gptr_source()`) and `doc-knitr.R` (`knit_print` methods and the scoped knitr label hook). The first five are L4 (built-in capability `builtin:documents`), `doc-knitr.R` is L5; they reach the kernel only through the kernel SDK of IC-33 (`session_replay_*()`, `session_append()`, `run_current()`, `replay_mode()`, `route_pass()`, `settings_write()`, ...) and the registry, and write a block only from the `agent_end` hook of a settled top-level run.

**Tech Stack:** base R (>= 4.2.0: `utils::getParseData()`, `srcfilecopy()`, `reg.finalizer(onexit = TRUE)`, `tools::md5sum()`); jsonlite through P01's `json_decode()`; cli (`hash_sha1()` for lock and sidecar names, `cli_verbatim()` through `msg_verbatim()`); ps (process creation times); knitr and rstudioapi (Suggests, guarded); testthat 3e, withr and processx in tests; Quarto CLI optional (tests skip without it).

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2, §6.4, §6.5, §6.9.1, §6.9.3, §7.3 `<documents>`, §10.5, §11.1, §12.7), dev/spec/04-interface-contract.md (§1.1-1.5, §2.2, §3.1-3.2, §4.6, §5.1, §5.2, §5.12, §6.4, §7.0, §7.15, §10.2 rows 18 and 31, §10.3, §10.4 `document_write`, §10.7, §11.1, §11.3, §11.5, §11.9, §12; §15: IC-33, IC-34, IC-39, IC-45..IC-53, IC-68, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P15).

**Depends on:** P08, P10 (and through them P01-P07, P09). The end-to-end tasks (17, 18) run on the M2 package (P11 and P13 exist when M3 starts) but need neither: they set `gptr.unsafe_no_permissions` and skip the plan-mode check without P11. **Milestone:** M3.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never the left arrow; `<<-` only for closure
state), the native `|>` (never `%>%`), ASCII-only R sources (non-ASCII as `\u` escapes), `pkg::fun()` calls,
`gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions (messages built by plain concatenation), no `:::` in
`R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed option restored with `on.exit(..., add = TRUE)`,
`readLines(encoding = "UTF-8")` for every text read in `R/`, testthat 3e, no network in tests, `Rscript --vanilla`
from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution
line required by the executing harness (conventions §10). Plan-specific requirements, copied from the
specification:

- Owned files (05 P15): `R/doc-locate.R`, `R/doc-blocks.R`, `R/doc-io.R`, `R/doc-formats.R`, `R/doc-replay.R`,
  `R/doc-knitr.R`; one test file per R file (`tests/testthat/test-doc-locate.R`, `test-doc-blocks.R`,
  `test-doc-io.R`, `test-doc-formats.R`, `test-doc-replay.R`, `test-doc-knitr.R`); `tests/testthat/fixtures/docs/`;
  `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`; the exception 05 names in P15
  acceptance 6 (IC-73): "P15's NS-7 fixture is added to `dev/bench/tokens/`" (`dev/bench/tokens/fixtures/ns07-script-history.json`
  and its row of `dev/bench/tokens/baseline.csv`, written by P07's runner).
- Layers (03 §3.2): `doc-locate.R`, `doc-blocks.R`, `doc-io.R`, `doc-formats.R`, `doc-replay.R` are L4 (`doc-formats.R`
  registers `builtin:documents`), `doc-knitr.R` is L5. They call L0 helpers, the record constructors
  (`provider-message.R`), their own area `doc`, the §7.0 services and the kernel SDK of IC-33: "`session_data()`
  (read), `session_live()`, ... `session_append()`, ..., `session_replay_apply()`, `session_replay_new()`,
  `session_replay_bind()`, `replay_lookup()`, ..., `run_current()`, ..., `route_pass()`, `gateway_run()`, ...,
  `replay_mode()`, `replay_guard()`, ..., `setting_get()`, `settings_effective()`, `settings_write()`, ...". They
  never call another L4 area by name (the `edit` tool is reached through `registry_get("tool", "edit")`).
- Exports (04 §14.1, P15's four names), exact signatures:
  `gptr_doc(path = NULL, format = NULL, sync = FALSE)`;
  `gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)`;
  `gptr_blocks(file)`;
  `gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp"))`.
- Listings (04 §5.12): `gptr_blocks` = `id`, `lines` (chr `"12-18"`), `prompt`, `status` (`fresh`, `stale`,
  `user-edited`, `undone`), `model`, `date`, `tokens`, `cost`, `session`; `gptr_cache_info` = `kind`, `entries`,
  `bytes`, `oldest`, `path`; both built by `new_listing(df, class, footer = NULL)` (P01). `gptr_source()` returns
  `invisible(<gptr_blocks>)` "with an extra `action` column (`replayed`, `regenerated`, `ran`, `skipped`)".
- Internal functions with contract signatures (04 §7.15): `builtin_documents(gptr)`, `doc_locate(call)`,
  `doc_decide(site, prompt_hash, args_hash, mode)`, `doc_block_lines(session, turn, site, call_ordinal)`,
  `doc_upsert(site, block_lines, block_id = NULL)` (returns `list(action, block_id, lines, backend)`),
  `prompt_hash(template)` ("12 hex of sha256 of the normalised template (trimws, CRLF -> LF, whitespace around
  newlines removed)"), `args_hash(interp)` ("8 hex of sha256 of the sorted interpolated `name=value` pairs, `NULL`
  without interpolation"), `s2_get(key)`, `s2_put(key, record)`.
- The site of `doc_locate()` (04 §7.15): "`list(kind = "srcref" | "source_frame" | "knitr" | "quarto" | "jupyter" |
  "rscript" | "ide" | "console", path, format, stmt = int(2) | NULL, expr = call | NULL, occurrence = int(1),
  ordinal = int(1), backend = chr(1), top_level = lgl(1), in_block = chr(1) | NULL, ide_id = chr(1) | NULL, defer
  = lgl(1))`", precedence "validated srcref (text must contain this prompt; reject `.active-rstudio-document`) >
  `source()`/`sys.source()` frame (... read inside `tryCatch` with an off switch) > knitr/Quarto
  (`QUARTO_DOCUMENT_PATH`) > IRkernel (`JPY_SESSION_NAME`, then content) > `Rscript --file=` > IDE (rstudioapi,
  guarded) > console" (03 §6.9.3); "Calls are matched by content and ordinal, never stale line numbers".
- Block grammar (04 §11.5), verbatim: `BLOCK_OPEN  = ^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$`,
  `BLOCK_CLOSE = ^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$`,
  `HEADER_KV   = ([A-Za-z_][A-Za-z0-9_.]*)=("([^"\\]|\\.)*"|[^ \t]+)`; header keys in the order `model`, `date`,
  `prompt`, `sha` ("first 8 hex of sha256 of the body lines as last written"), `call`, `tokens`, `cost`, `session`,
  `turn`, `value`, `fork` (`<parent session id>:<turn>`), `plan`, `status` (`undone`), `args`, `kind` (`team` or
  `fanout`), `children` (`"<name>:<session id>,..."`, quoted); block ids from P01's `id_block()` (6 hex with a letter,
  grown on collision, RNG-free).
- Block body (04 §11.5, IC-48, IC-49): "the code of each successful `r` call with `record = TRUE`, verbatim except
  that top-level `gptr_return()` calls and calls of `record = FALSE` members are dropped and top-level `<-` is
  rewritten to `=` where safe"; "`## Steer: <text>` and `## Follow-up: <text>` lines ... (excluded from `prompt` and
  `sha`)"; outputs "as `#> ` lines (at most `gptr.doc_output_lines` lines of 76 characters, then `#> ... (N more
  lines)`), not in Rmd/qmd"; "`## Decision: <note>` lines"; bridge digests; artifact references (`#> [app] ...`,
  `#> [plot] <path>`); "a block whose code needed a secret gets `# gptr: block needs secrets that are not
  recorded`"; "Code passes `code_for_history()`"; "a plan-mode turn gives one `## Plan: <plans path>` line";
  overlay forks "wrapped `local({ ... }, envir = gptr_resume(block = "<block id>")$envir)`"; team and fan-out
  blocks: one `## Agent <name> (<model>): <first line>` per child, exported children wrapped
  `local({ ... }, envir = gptr_resume(block = "<id>", child = "<name>")$envir)` plus
  `<export> = gptr_resume(block = "<id>", child = "<name>")$envir$<export>`. `record = FALSE` members: `out`, `plot`,
  `help`, `search`, `describe`. Ownership: "the run of blocks starting at the first non-blank line after the
  statement ...; the k-th call owns the block whose `prompt=` matches, else the one with `call=k` (then stale).
  Only top-level calls own blocks (not inside `function`, `\(x)`, `for`, `while`, `repeat`, `if`, `{}`, or an agent
  block)".
- Formats (04 §11.5): `.Rmd` "a separate chunk `` ```{r gptr-<id>} `` directly after the owning chunk (fence and
  prefix copied), body with the markers, no `#>` lines"; `.qmd` "a chunk `` ```{r} `` whose first line is
  `#| label: gptr-<id>`"; `.ipynb` "a code cell `{"cell_type": "code", "execution_count": null, "id": "gptr-<id>",
  "metadata": {"gptr": {...}}, "outputs": [], "source": [...]}` after the calling cell; keys sorted; indentation
  copied from the file (Jupyter: 1 space); floats in Python repr; only `source` and `metadata.gptr` change on
  rewrite; never written while the notebook is open"; transcript `.gptr/transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R`
  with "a header comment (`# gptr session <id> -- started <time>`, `# machine log: <jsonl path>`, `# source() this
  file to replay ...`), `library(gptr)`, then the first prompt as `s_<6 hex> = gptr("...")` and later prompts as
  `s_<6 hex> |> gptr("...")`"; slash commands as comments (`# /model opus`); direct R lines under
  `# direct R (no model)`. Undone blocks (G7 §3.8): `status=undone`, body lines prefixed `#~ `, Rmd/qmd chunks get
  `eval=FALSE` (`#| eval: false`), ipynb `metadata.gptr.status = "undone"`; System 1 one-line blocks
  `#> gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0, 2026-09-29)` (`gptr_choice: liver 8, lung 5, other 2 (...)`,
  `gptr_score: mean 1.4 (...)`).
- Replay modes (03 §6.9.3): "`auto` (default: a fresh recorded block is replayed, a missing or stale one runs),
  `replay` (never call models; a missing block errors `gptr_error_not_recorded`), `live` (ask afresh and
  regenerate), `record` (regenerate stale blocks)"; "under base `source()`/Rscript, `live` and stale regeneration
  downgrade to replay with a warning"; G7 §3.8 undone row: `auto` skip with one message, `replay` skip, `live` run
  with no write, `record` regenerate. The mode is P08's `replay_mode(arg = NULL)`: "`arg` > `gptr.replay` >
  `GPTR_REPLAY` > settings > `"auto"`; `"replay"` is forced when `check_running()` and `Sys.getenv("TESTTHAT") !=
  "true"`". Freshness (IC-45): "A block is fresh only when `prompt=` and `args=` both match"; "A stale block under
  `replay` errors `gptr_error_stale_block`".
- Write consent (IC-45), checked only in `doc_upsert()`: "`gptr_doc(path)` in this process ..., `options(gptr.record =
  "auto")`, user-scope setting `record = "auto"`, or an interactive yes (remembered per document in the user-level
  project file, IC-52). `record` is a tighten-type setting, so a project can only turn it off". "Replay needs no
  write consent."
- The route (IC-39, IC-45): `document`, order 50; it "matches a **top-level** call located in a document ... that
  **contains a block owned by this call** ... Without a block it sets `call$doc` when write consent exists and
  passes"; replay of a fresh block (IC-46): the piped session through `session_replay_apply(s, block, header, text =
  NULL)`, otherwise `session_replay_new(block, header, envir, doc)`, fork blocks bound with
  `session_replay_bind(block, s, child = NULL)`; block-nested calls replay from S2 "under `(doc, block,
  "n<ordinal>")` in `auto` and `replay` (... a miss under `replay` errors `not_recorded`) and run live only in
  `live`" (IC-47).
- The `documents` prompt section (04 §9.3, IC-68): T0, order 500, budget 250, "a history document is bound
  (`ctx$input$document` non-NULL, from the `doc.site` service)", text of 03 §7.3 byte for byte (P07 replaces
  `{s1}`).
- Services (04 §7.0), owned by `builtin:documents` (IC-34): `doc.site` = `function(session) list(path, format) or
  NULL`; `doc.edit` = `function(path, edits, session) <gptr_tool_result> or NULL` ("NULL: not a bound document");
  `doc.s1_block` = `function(call, summary) invisible(NULL)`; `doc.replay` = `function(call) <session> or NULL`
  ("the replayed team or fan-out session for a fresh block, else `NULL`").
- Event (04 §10.4): `document_write`, "block + patch, **error = block**", payload `path`, `format`, `kind`
  (`block`, `transcript`, `inert`), `block_id`, `lines`; returns `list(block = TRUE, reason)` or `list(lines)`.
  JSONL entry (04 §4.6): `gptr.doc_block` = `{doc, format, block, action: "insert"|"replace"|"stale-regenerate"|
  "undone", prompt, sha, lines: [from, to], backend: "file"|"deferred"|"rstudio"|"positron"|"vscode"|"transcript"}`
  (P15 also writes `backend = "pending"` for Jupyter, IC-50).
- Files (04 §11.1, §11.3, §11.9): document locks `<root>/locks/<sha1 of path_key>` (a `mkdir` lock with a `pid`
  file holding pid and process creation time; stale when `pid_alive()` is `FALSE`); S2 answers
  `<root>/cache/s2/<2hex>/<sha256>.json`, key `hash_sha256(canonical_json(list(schema = 2L, doc = <path relative to
  root>, block = <id>, part = <"" | child name | "n<ordinal>">, prompt = <prompt hash>, args = <args hash or "">)))`,
  value `{"block", "doc", "part", "prompt", "model", "answer" (redacted final text), "usage", "cost", "session",
  "turn", "date"}`; deferred and pending writes `<root>/cache/tmp/pending-<sha1(path_key(doc path))>.rds` =
  `list(doc, base_md5, upserts = list(list(block_id, lines, site)), session, pid, time)`, "never pruned
  automatically"; the user-level project file `R_user_dir("gptr", "config")/projects/<first 16 hex of
  sha256(path_key(project root))>.json` with `"transcript": {"target": ...}` and `"record": {"analysis.R":
  "auto"}`, written through `settings_write("user_project", patch)` (P08). `<root>` is `workspace_root()` (`.gptr/`
  or `tempdir()/gptr`).
- Durable writes (IC-51): the sidecar "is flushed after each settled top-level call (so SIGTERM loses at most one
  call) and is applied at exit by the finalizer; the next `gptr()`, `gptr_blocks()` or `gptr_doc()` touching that
  document in any process re-applies unapplied upserts of a dead pid through the normal md5 and re-locate path and
  reports conflicts instead of overwriting"; "Under a document lock held by another live pid (array jobs) nothing is
  recorded and a notice is printed"; P01's `write_atomic()` does the rename retries and the in-place fallback.
- Jupyter (IC-50): "With `front_end() == "jupyter"` gptr never writes the open notebook: the block is shown as the
  cell's output (a fenced R code block) and recorded as a pending `gptr.doc_block` entry (`backend = "pending"`)
  plus a pending sidecar"; `gptr_doc(path, sync = TRUE)` applies them "when the notebook is closed or headless".
- Transcript targets (IC-52): "must lie inside the project root, have extension `.R`, `.Rmd`, `.qmd` or `.ipynb`,
  and not be a `control` or protected path"; remembered in the user-level project file.
- Options (04 §3.1): `gptr.replay` (settings, `"auto"`), `gptr.record` (settings, `"ask"`: "`"auto"`, `"ask"`,
  `"off"`"), `gptr.doc_output_lines` (`12L`), `gptr.doc_source_frames` (`TRUE`, "off switch for reading `source()`
  frames (CRAN grey zone)"), `gptr.spill_days` (`7`). Settings keys `record`, `replay`, `transcript`, `doc`
  (`{outputs: true, output_lines: 12}`) are registered by P08 (04 §11.2); P15 reads them with `setting_get()`.
  Environment variables read: `GPTR_REPLAY` (through `replay_mode()`), `QUARTO_DOCUMENT_PATH`,
  `QUARTO_DOCUMENT_FILE`, `JPY_SESSION_NAME`, `RSTUDIO`, `POSITRON`, `TERM_PROGRAM` (through `front_end()`).
- Conditions (04 §2.2): errors `gptr_error_not_recorded` (`document`, `prompt`), `gptr_error_stale_block` (parent
  `not_recorded`; `document`, `block`), `gptr_error_doc_write` (`path`, `reason`), `gptr_error_invalid_argument`
  (`arg`, `expected`), `gptr_error_permission` (`action`, `tool`, `risk`, `how_to_allow`, `session`); warnings
  `gptr_warning_replay_downgraded`, `gptr_warning_doc_conflict`; message `gptr_message_notice`.
- Control category (IC-53 item 3): `gptr_doc` and `gptr_cache` (prune, clear) "called from model code during a run
  ... signal `gptr_error_permission` unless the dispatcher approved exactly that call through an `ask_human` (a
  one-shot token on the run)"; the token is the function name in `run$signal$control`, as P08 reads it.
- Package state (04 §7.0): `the$doc_binding` ("console document binding") and `the$doc_pending` ("deferred Rscript
  writes"); nothing else global. Copy safety (03 §6.4, R1/R2): P15 keeps sites (lists of strings and integers),
  never a user frame; `call$envir` is passed straight to P06's replay functions.
- Tests (04 §12): P01's helpers with their exact names (`local_project(files = list(), gptr = TRUE, trust = FALSE,
  .env = parent.frame())`, `local_gptr_options(..., .env = parent.frame())`, `local_fake_provider(script, name =
  "fake", type = "chat", .env = parent.frame())`, `fake_text(text, ...)`, `fake_tool(name, ..., .text = NULL, .id =
  NULL)`, `fake_requests(spec)`); child `Rscript` processes are started with `rscript_path()` and load gptr with the
  line P01's `helper-tracemem.R` builds (`tracemem_loader()`), so `pkgload::load_all()` appears only inside generated
  script text (IC-71); `setup.R` sets `GPTR_REPLAY=replay`, so tests that record pass `replay = "auto"` through
  `local_gptr_options()`.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/doc-blocks.R` | create (Task 1), extend (Tasks 2, 3, 9) | block grammar and header key=values, `prompt_hash()`, `args_hash()`, body sha and block status, rendering and splicing; P15's process state (`doc_state()`); the `gptr()` call scanner (with a parse memo), anchors (content + ordinal) and block ownership; the recorded block content `doc_block_lines()` (team, fork, steer, plan and secret rules); the writer `doc_upsert()` with the `document_write` event, md5 retries, the `gptr.doc_block` entry and the S2 answers |
| `R/doc-io.R` | create (Task 4), extend (Tasks 8, 10, 11) | raw-byte reads and atomic writes keeping EOL/BOM/final newline, md5 conflict detection, document locks, the user-level project file; IDE queries; deferred Rscript writes, Jupyter pending blocks, the sidecar, its recovery and `gptr_doc(sync = TRUE)`; the IDE edit backend and transcript appends |
| `R/doc-formats.R` | create (Task 5), extend (Tasks 6, 13) | the `r`, `rmd`, `qmd` and `transcript` formats (chunks, agent chunks, console statements), inert (undone) blocks; gptr's nbformat serializer and the `ipynb` format; the format registry; `doc_set_inert()`; `builtin:documents` and the `documents` section |
| `R/doc-replay.R` | create (Task 7), extend (Tasks 12-15) | write consent, the control guard, the S2 cache; `doc_decide()` and replaying fresh blocks (pipes, forks, block-nested calls, teams); the `document` route, the `doc.*` services, the `agent_end` and `session_tree` hooks and the console channels `console:command`/`console:direct`; `gptr_doc()`, `gptr_blocks()`, `gptr_cache()`, `gptr_source()` |
| `R/doc-locate.R` | create (Task 8) | `doc_locate()`: srcref, `source()` frame, knitr/Quarto, Jupyter, Rscript and IDE sites, anchors, drivers; the console transcript target |
| `R/doc-knitr.R` | create (Task 16) | `knit_print` methods for sessions and System 1 vectors (lazy registration) and the scoped knitr label hook |
| `tests/testthat/test-doc-blocks.R` | create (Task 1), extend (Tasks 2, 3, 9) | grammar, hashes, scanner, ownership, block content, writer |
| `tests/testthat/test-doc-io.R` | create (Task 4), extend (Tasks 10, 11, 18) | raw I/O and fixtures, locks, project file, deferred/pending writes and recovery, IDE backend, Rscript end to end |
| `tests/testthat/test-doc-formats.R` | create (Task 5), extend (Tasks 6, 13) | Rmd/qmd/r/transcript formats, inert blocks, notebook serializer, registry, `builtin:documents` |
| `tests/testthat/test-doc-replay.R` | create (Task 7), extend (Tasks 12-15, 17) | consent, S2, decisions, replay, route, services, hooks, exports, end-to-end acceptance |
| `tests/testthat/test-doc-locate.R` | create (Task 8) | the locator precedence and the transcript target |
| `tests/testthat/test-doc-knitr.R` | create (Task 16), extend (Task 18) | `knit_print`, the label hook, knitr and Quarto record/replay |
| `tests/testthat/fixtures/docs/crlf-bom.R`, `crlf-bom.expected.R` | create (Task 4) | CRLF + BOM + no final newline, before and after a block insert |
| `tests/testthat/fixtures/docs/report.Rmd`, `report.expected.Rmd`, `report.qmd`, `report.expected.qmd` | create (Task 5) | R Markdown (four-backtick fence) and Quarto documents before and after an agent chunk |
| `tests/testthat/fixtures/docs/floats.ipynb` | create (Task 6) | a notebook byte-identical to Python's nbformat writer (Plotly-style floats, `</table>`, tab, non-ASCII) |
| `dev/bench/tokens/fixtures/ns07-script-history.json`, `dev/bench/tokens/baseline.csv` (one row) | create, update (Task 19) | the NS-7 golden transcript (IC-73) |
| `NAMESPACE`, `man/gptr_doc.Rd`, `man/gptr_source.Rd`, `man/gptr_blocks.Rd`, `man/gptr_cache.Rd` | generated (Task 19) | `Rscript --vanilla -e 'devtools::document()'` |

## Tasks (overview)

1. Block grammar, hashes and rendering (`doc-blocks.R`)
2. The call scanner, anchors and block ownership (`doc-blocks.R`)
3. The recorded block content: `doc_block_lines()` (`doc-blocks.R`)
4. Raw document I/O, locks and the user-level project file (`doc-io.R`, CRLF/BOM fixtures)
5. The `r`, `rmd`, `qmd` and `transcript` formats and inert blocks (`doc-formats.R`, Rmd/qmd fixtures)
6. The notebook serializer, the `ipynb` format and the format registry (`doc-formats.R`, notebook fixture)
7. Write consent, the control guard and the S2 answer cache (`doc-replay.R`)
8. Locating the calling statement: `doc_locate()` (`doc-locate.R`, IDE queries in `doc-io.R`)
9. The writer: `doc_upsert()` (`doc-blocks.R`)
10. Deferred Rscript writes, Jupyter pending blocks and sidecar recovery (`doc-io.R`)
11. The IDE backend and transcript appends (`doc-io.R`)
12. Replay decisions and replaying fresh blocks (`doc-replay.R`)
13. `builtin:documents`: the route, the section, the hooks and the services (`doc-formats.R`, `doc-replay.R`)
14. `gptr_doc()`, `gptr_blocks()` and `gptr_cache()` (`doc-replay.R`)
15. `gptr_source()` (`doc-replay.R`)
16. knitr integration (`doc-knitr.R`)
17. End-to-end record and replay through `gptr()` (`test-doc-replay.R`)
18. Rscript, knitr and Quarto end to end (`test-doc-io.R`, `test-doc-knitr.R`)
19. The NS-7 golden transcript, documentation, NAMESPACE and plan acceptance

---

### Task 1: Block grammar, hashes and rendering

**Files:**
- Create: `R/doc-blocks.R`
- Test: `tests/testthat/test-doc-blocks.R` (create)

**Interfaces:**
- Consumes (P01, 04 §7.1): `as_utf8(x)`, `hash_sha256(x)`, `` `%||%` ``.
- Produces (04 §7.15, §11.5): `prompt_hash(template)` -> chr(1) 12 hex; `args_hash(interp)` -> chr(1) 8 hex or
  `NULL` (`interp` is P08's character vector of `name=value` pairs, or a named list of values); and the helpers every
  later task uses: the marker regexes `doc_re_open`, `doc_re_close`, `doc_re_kv`, `doc_re_steer`, the body
  placeholder `doc_block_token` (`"@@GPTR_BLOCK@@"`, replaced by the block id when the block is written),
  `doc_header_keys`, `doc_one_line(x)`, `doc_str_literal(x)`, `doc_parse_kv(s)` -> named list of strings,
  `doc_format_kv(x)` -> chr(1), `doc_find_blocks(lines)` -> df(`id`, `start`, `end`, `indent`, `header` (list
  column)) with attribute `malformed`, `doc_block_body(lines, block)`, `doc_body_sha(body)` -> 8 hex (steer and
  follow-up lines excluded, IC-49), `doc_block_status(header, body, ph = NULL, ah = NULL)` -> `"undone"`,
  `"user-edited"`, `"stale"` or `"fresh"`, `doc_render_block(id, header = list(), body = character(), indent = "")`,
  `doc_indent_lines(x, indent = "")`, `doc_splice(lines, from, to, new)`.

The grammar is report 14 §3.1 and 04 §11.5 (prototype `proto/gptrdoc.R` of report 14 §5.0: `parse_kv`,
`format_kv`, `doc_find_blocks`, `doc_render_block`, `prompt_hash`), with two additions from the contract: the `args`
key joins `prompt` in freshness (IC-45), and the body sha ignores `## Steer:`/`## Follow-up:` lines (IC-49). The
report's verification log confirms the `prompt_hash()` values used in the test (item 32) and asks for radix
sorting wherever keys are ordered (item 33), which `args_hash()` follows.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-doc-blocks.R`:

```r
# Tests for R/doc-blocks.R (plan P15): grammar, hashes, scanner, ownership, block content, writer.

test_that("header key=value pairs round-trip in contract order with quoting", {
  x = list(turn = 2L, model = "fake/fake-1", prompt = "3b1c9a0e77d2", value = "a b",
           children = "stats:s1,code:s2", date = "2026-09-29", extra = "z")
  s = doc_format_kv(x)
  expect_identical(s, paste0("model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2 turn=2 ",
                             "value=\"a b\" children=\"stats:s1,code:s2\" extra=z"))
  back = doc_parse_kv(s)
  expect_identical(back$value, "a b")
  expect_identical(back$turn, "2")
  expect_identical(back$children, "stats:s1,code:s2")
  expect_identical(doc_parse_kv(""), list())
  expect_identical(doc_parse_kv("k=\"q\\\"uote\""), list(k = "q\"uote"))
  expect_identical(doc_format_kv(list(model = NULL, v = "")), "v=\"\"")
})

test_that("blocks are found with ids, ranges, indentation and headers; bad markers flagged", {
  lines = c("x = 1", "gptr(\"a\")", "# >>> gptr:7f3a21 model=m date=d prompt=p", "y = 2",
            "# <<< gptr:7f3a21", "  # >>> gptr:0b1c2d model=m", "  z = 3", "  # <<< gptr:0b1c2d")
  b = doc_find_blocks(lines)
  expect_identical(b$id, c("7f3a21", "0b1c2d"))
  expect_identical(b$start, c(3L, 6L))
  expect_identical(b$end, c(5L, 8L))
  expect_identical(b$indent, c("", "  "))
  expect_identical(b$header[[1]]$prompt, "p")
  expect_false(attr(b, "malformed"))
  expect_identical(doc_block_body(lines, b[2, ]), "z = 3")
  expect_true(attr(doc_find_blocks(c("# >>> gptr:7f3a21 model=m", "y = 2")), "malformed"))
  nested = c("# >>> gptr:aaaaaa", "# >>> gptr:bbbbbb", "# <<< gptr:bbbbbb", "# <<< gptr:aaaaaa")
  expect_true(attr(doc_find_blocks(nested), "malformed"))
  expect_true(attr(doc_find_blocks(c("x", "# <<< gptr:cccccc")), "malformed"))
  expect_identical(nrow(doc_find_blocks(character())), 0L)
})

test_that("prompt_hash() reproduces report 14's values and args_hash() is order-free", {
  expect_identical(prompt_hash("step one"), "52831d1d544e")
  expect_identical(prompt_hash("step two"), "078c44630410")
  expect_identical(prompt_hash("count letters in this prompt"), "3848b6ef5cca")
  expect_identical(prompt_hash("fit mpg on weight"), "be76e50bf356")
  expect_identical(prompt_hash("  a multi-line\r\n   prompt "), prompt_hash("a multi-line\nprompt"))
  expect_null(args_hash(NULL))
  expect_null(args_hash(character()))
  expect_identical(args_hash(c("b=2", "a=1")), args_hash(c("a=1", "b=2")))
  expect_identical(args_hash(list(gene = "CD3E")), args_hash("gene=CD3E"))
  expect_false(identical(args_hash("gene=CD3E"), args_hash("gene=MS4A1")))
  expect_match(args_hash("gene=CD3E"), "^[0-9a-f]{8}$")
})

test_that("the body sha ignores steering lines and drives user-edited detection", {
  body = c("n = 1", "## Steer: use TPM", "#> [1] 1")
  expect_identical(doc_body_sha(body), doc_body_sha(c("n = 1", "#> [1] 1")))
  h = list(prompt = "p", sha = doc_body_sha(body))
  expect_identical(doc_block_status(h, body, "p", NULL), "fresh")
  expect_identical(doc_block_status(h, body, "q", NULL), "stale")
  expect_identical(doc_block_status(c(h, args = "abcd1234"), body, "p", "abcd1234"), "fresh")
  expect_identical(doc_block_status(c(h, args = "abcd1234"), body, "p", "00000000"), "stale")
  expect_identical(doc_block_status(h, body, "p", "abcd1234"), "stale")
  expect_identical(doc_block_status(h, c("n = 2", "#> [1] 1"), "p", NULL), "user-edited")
  expect_identical(doc_block_status(c(h, status = "undone"), body, "q", NULL), "undone")
  expect_identical(doc_block_status(list(prompt = "p"), "anything", "p", NULL), "fresh")
  expect_identical(doc_block_status(h, body), "fresh")
})

test_that("rendering indents body lines, keeps empty lines and splices in place", {
  out = doc_render_block("7f3a21", list(model = "m", prompt = "p"), c("x = 1", "", "y = 2"), "  ")
  expect_identical(out, c("  # >>> gptr:7f3a21 model=m prompt=p", "  x = 1", "", "  y = 2",
                          "  # <<< gptr:7f3a21"))
  expect_identical(doc_render_block("aaaaaa"), c("# >>> gptr:aaaaaa", "# <<< gptr:aaaaaa"))
  expect_identical(doc_splice(letters[1:5], 2L, 3L, c("X", "Y", "Z")),
                   c("a", "X", "Y", "Z", "d", "e"))
  expect_identical(doc_splice(letters[1:3], 3L, 3L, "Z"), c("a", "b", "Z"))
  expect_identical(doc_str_literal("caf\u00e9 \"q\"\n"), "\"caf\u00e9 \\\"q\\\"\\n\"")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`, starting with ``Error in `doc_format_kv(x)`: could not find function "doc_format_kv"``.

- [ ] **Step 3: Write the implementation**

Create `R/doc-blocks.R`:

```r
# doc-blocks.R -- history-document blocks (plan P15; contract 7.15, 11.5; IC-45..IC-49): the block
# grammar, prompt and args hashes, the gptr() call scanner, block ownership, stale and user-edited
# detection, the recorded block content and the writer doc_upsert(). Layer L4: it calls L0
# helpers, the record constructors, the kernel SDK (session_data(), session_append()) and its
# own area only. Adapted from report 14 section 5.0 (proto/gptrdoc.R: doc_find_blocks,
# doc_scan_calls, doc_blocks_after, doc_owned_block, doc_render_block, prompt_hash, parse_kv,
# format_kv) with the verification-log fixes (radix ordering; sys.source frames) and G3 (11).

doc_re_open = "^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$"
doc_re_close = "^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$"
doc_re_kv = "([A-Za-z_][A-Za-z0-9_.]*)=(\"([^\"\\\\]|\\\\.)*\"|[^ \t]+)"
doc_re_steer = "^[ \t]*## (Steer|Follow-up): "
doc_block_token = "@@GPTR_BLOCK@@"
doc_header_keys = c("model", "date", "prompt", "sha", "call", "tokens", "cost", "session", "turn",
                    "value", "fork", "plan", "status", "args", "kind", "children")
doc_quoted_keys = "children"

#' Collapse text to one comment-safe line
#' @noRd
doc_one_line = function(x) {
  x = as_utf8(paste(as.character(x), collapse = " "))
  trimws(gsub("[\r\n\t]+", " ", x))
}

#' An R string literal that keeps non-ASCII characters (encodeString() escapes them in a C locale)
#' @noRd
doc_str_literal = function(x) {
  x = as_utf8(as.character(x))
  x = gsub("\\", "\\\\", x, fixed = TRUE)
  x = gsub("\"", "\\\"", x, fixed = TRUE)
  x = gsub("\n", "\\n", x, fixed = TRUE)
  x = gsub("\r", "\\r", x, fixed = TRUE)
  x = gsub("\t", "\\t", x, fixed = TRUE)
  paste0("\"", x, "\"")
}

#' Parse the key=value pairs of a block header into a named list of strings
#' @noRd
doc_parse_kv = function(s) {
  if (is.null(s) || !length(s) || is.na(s) || !nzchar(trimws(s))) return(list())
  kv = regmatches(s, gregexpr(doc_re_kv, s, perl = TRUE))[[1L]]
  if (!length(kv)) return(list())
  keys = sub("=.*$", "", kv)
  vals = sub("^[^=]*=", "", kv)
  quoted = startsWith(vals, "\"")
  vals[quoted] = vapply(vals[quoted], function(v) {
    out = tryCatch(str2lang(v), error = function(e) v)
    if (is.character(out) && length(out) == 1L) out else v
  }, "", USE.NAMES = FALSE)
  stats::setNames(as.list(as_utf8(vals)), keys)
}

#' Format header fields in the key order of contract 11.5 (unknown keys last)
#' @noRd
doc_format_kv = function(x) {
  x = x[!vapply(x, function(v) is.null(v) || !length(v), NA)]
  if (!length(x)) return("")
  known = intersect(doc_header_keys, names(x))
  x = x[c(known, setdiff(names(x), known))]
  vals = vapply(names(x), function(k) {
    v = as.character(x[[k]])[1L]
    if (is.na(v)) v = "NA"
    if (k %in% doc_quoted_keys || !nzchar(v) || grepl("[ \t\"=\\\\]", v)) doc_str_literal(v) else v
  }, "")
  paste0(names(x), "=", vals, collapse = " ")
}

#' The agent blocks of a text: df(id, start, end, indent, header (list column)); attribute
#' `malformed` flags unterminated, nested or orphan markers. Only lines holding "gptr:" are
#' matched against the marker patterns.
#' @noRd
doc_find_blocks = function(lines) {
  lines = as_utf8(as.character(lines))
  hit = which(grepl("gptr:", lines, fixed = TRUE))
  om = regmatches(lines[hit], regexec(doc_re_open, lines[hit], perl = TRUE))
  cm = regmatches(lines[hit], regexec(doc_re_close, lines[hit], perl = TRUE))
  is_open = lengths(om) > 0L
  is_close = lengths(cm) > 0L
  opens = hit[is_open]
  open_m = om[is_open]
  closes = hit[is_close]
  close_ids = vapply(cm[is_close], function(m) m[3L], "")
  ids = character()
  starts = integer()
  ends = integer()
  indents = character()
  headers = list()
  bad = FALSE
  for (k in seq_along(opens)) {
    i = opens[k]
    m = open_m[[k]]
    id = m[3L]
    j = closes[closes > i & close_ids == id]
    nxt = opens[opens > i]
    if (!length(j) || (length(nxt) && nxt[1L] < j[1L])) {
      bad = TRUE
      next
    }
    ids = c(ids, id)
    starts = c(starts, i)
    ends = c(ends, j[1L])
    indents = c(indents, m[2L])
    headers[[length(headers) + 1L]] = doc_parse_kv(m[4L])
  }
  if (anyDuplicated(ids) || length(setdiff(closes, ends))) bad = TRUE
  res = data.frame(id = ids, start = starts, end = ends, indent = indents,
                   stringsAsFactors = FALSE)
  res$header = headers
  attr(res, "malformed") = bad
  res
}

#' Body lines of one row of doc_find_blocks(), without the block's indentation
#' @noRd
doc_block_body = function(lines, block) {
  if (block$end - block$start < 2L) return(character())
  body = lines[(block$start + 1L):(block$end - 1L)]
  ind = block$indent
  if (nzchar(ind)) body = ifelse(startsWith(body, ind), substring(body, nchar(ind) + 1L), body)
  body
}

#' First 8 hex of sha256 of the body as written, without steering lines (IC-49)
#' @noRd
doc_body_sha = function(body) {
  body = as_utf8(as.character(body))
  body = body[!grepl(doc_re_steer, body)]
  substr(hash_sha256(paste(body, collapse = "\n")), 1L, 8L)
}

#' 12 hex of sha256 of the normalised prompt template (contract 7.15): trimws, CRLF -> LF,
#' whitespace around newlines removed
#' @noRd
prompt_hash = function(template) {
  p = as_utf8(paste(as.character(template), collapse = "\n"))
  p = gsub("[ \t]*\r?\n[ \t]*", "\n", trimws(p))
  substr(hash_sha256(p), 1L, 12L)
}

#' 8 hex of sha256 of the sorted interpolated `name=value` pairs, NULL without interpolation
#' (IC-45). `interp` is P08's character vector of pairs or a named list of values.
#' @noRd
args_hash = function(interp) {
  if (is.null(interp) || !length(interp)) return(NULL)
  if (is.list(interp) || (!is.null(names(interp)) && all(nzchar(names(interp))))) {
    vals = vapply(interp, function(v) paste(as.character(v), collapse = ", "), "")
    interp = paste0(names(interp), "=", vals)
  }
  x = sort(as_utf8(as.character(interp)), method = "radix")
  substr(hash_sha256(paste(x, collapse = "\n")), 1L, 8L)
}

#' Status of a block: undone > user-edited (sha) > stale (prompt or args) > fresh. With
#' `ph = NULL` only undone and user-edited are detected.
#' @noRd
doc_block_status = function(header, body, ph = NULL, ah = NULL) {
  if (identical(header$status, "undone")) return("undone")
  if (!is.null(header$sha) && !identical(header$sha, doc_body_sha(body))) return("user-edited")
  if (!is.null(ph)) {
    if (!identical(header$prompt, ph)) return("stale")
    if (!identical(header$args %||% "", ah %||% "")) return("stale")
  }
  "fresh"
}

#' Render a marker block (contract 11.5): header, indented non-empty body lines, footer
#' @noRd
doc_render_block = function(id, header = list(), body = character(), indent = "") {
  kv = doc_format_kv(header)
  head = paste0(indent, "# >>> gptr:", id, if (nzchar(kv)) paste0(" ", kv) else "")
  c(head, doc_indent_lines(as.character(body), indent), paste0(indent, "# <<< gptr:", id))
}

#' Prefix the non-empty lines with an indentation string
#' @noRd
doc_indent_lines = function(x, indent = "") {
  if (!nzchar(indent %||% "")) return(x)
  x[nzchar(x)] = paste0(indent, x[nzchar(x)])
  x
}

#' Replace lines from..to of a text by `new`
#' @noRd
doc_splice = function(lines, from, to, new) {
  c(lines[seq_len(from - 1L)], new, if (to < length(lines)) lines[(to + 1L):length(lines)])
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 44 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-blocks.R tests/testthat/test-doc-blocks.R
git commit -m "feat(doc): add the history-block grammar, prompt and args hashes and rendering"
```

---

### Task 2: The call scanner, anchors and block ownership

**Files:**
- Modify: `R/doc-blocks.R` (append)
- Test: `tests/testthat/test-doc-blocks.R` (append)

**Interfaces:**
- Consumes: Task 1 (`doc_find_blocks()`, `prompt_hash()`, `doc_block_status()`, `doc_block_body()`); P01
  `the`, `as_utf8()`, `hash_sha256()`; base `parse()`, `utils::getParseData()`, `utils::getParseText()`.
- Produces: P15's process state `doc_state()` (04 §7.0 `the$doc_pending`: `docs`, `held`, `finalizer`, `sources`,
  `knitr_skip`, `knitr_hooked`, `counters`, `in_edit`, and the scanner memo `scan`/`scan_keys`), used by every later
  task; `doc_scan_calls(lines, fun = "gptr", line_offset = 0L)` -> df(`line1`, `col1`, `line2`, `col2`, `stmt1`,
  `stmt2`, `nested`, `prompt`, `n_in_stmt`, `text`) (a text that does not parse gives no calls and the attribute
  `parse_error`); `doc_calls(lines, blocks = doc_find_blocks(lines))` adds `block` (the agent block holding the
  call), `n_in_block` (ordinal among the block's direct calls), `ph` (prompt hash) and `th` (call-text hash);
  `doc_calls_have(calls, ph, call0)`; the anchor of a call `list(ph, th, j, block, label)` from
  `doc_anchor_of(calls, t)`, re-located by `doc_match_anchor(calls, anchor)`; `doc_blocks_after(lines, stmt_end,
  blocks)`; `doc_run_owner(headers, ph, k = 1L, taken = integer())` -> `list(index, stale)` or `NULL` (the 04 §11.5
  ownership rule, shared by every format; `taken` = ordinals of the statement's other calls with the same prompt,
  whose blocks are never matched by prompt alone); `doc_same_ordinals(calls, hit)`; `doc_owned_block(lines, hit, ph,
  blocks, taken = integer())`; `doc_text_locate(text, site, calls)` -> the
  `locate()` result of the marker formats: `list(stmt, blocks, hit, owned = list(id, header, status, start, end) |
  NULL, insert_after, top_level, in_block, ordinal, indent)`; `doc_stmt_by_expr(lines, expr, k = 1L)`.

Calls are found by content, never by stale line numbers (report 14 §1 items 2-4 and §4.2): a call is the
`SYMBOL_FUNCTION_CALL` `gptr` of the parse data, nested when an ancestor expression is a `function`, `\(x)`, `for`,
`while`, `repeat`, `if` or `{` (report 14 `doc_scan_calls`), and its prompt is `prompt =` or the first unnamed
string literal (contract 6.1.1 step 2). An anchor is the prompt hash (or, for computed prompts, the hash of the call
text) plus the ordinal among identical calls outside blocks, so it survives blocks inserted above it. Every `gptr()` call of a script locates itself,
so the scanner keeps the parse of the 16 most recently used texts of 20 lines or more (keyed by their sha256) and
looks parse ids up through id-indexed vectors (data-frame row names would make a 2,000-line script cost seconds per
call).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-blocks.R`:

```r
test_that("the scanner finds top-level and nested calls, prompts and pipeline ordinals", {
  lines = c("x = 1:3", "gptr(\"count the letters\")", "res = gptr(", "  \"a multi-line",
            "   prompt\"", ")", "x |> gptr(\"piped prompt\")",
            "gptr(\"step one\") |> gptr(\"step two\")",
            "f = function() gptr(\"inside a function\")", "for (i in 1:2) gptr(\"in a loop\")",
            "if (TRUE) {", "  gptr(\"inside if braces\")", "}", "g = \\(x) gptr(\"lambda\")",
            "gptr::gptr(\"ns\")", "gptr(model = \"m\", \"the prompt\")",
            "gptr(prompt = \"named\", x)", "gptr(paste(\"dyn\", x))", "while (FALSE) gptr(\"w\")",
            "repeat {", "  gptr(\"r\")", "  break", "}")
  calls = doc_scan_calls(lines)
  top = calls$prompt[!calls$nested]
  expect_identical(top, c("count the letters", "a multi-line\n   prompt", "piped prompt",
                          "step one", "step two", "ns", "the prompt", "named", NA))
  expect_setequal(calls$prompt[calls$nested], c("inside a function", "in a loop",
                                                "inside if braces", "lambda", "w", "r"))
  pipe = calls[calls$prompt %in% c("step one", "step two"), ]
  expect_identical(pipe$n_in_stmt, c(1L, 2L))
  expect_identical(unique(pipe$stmt1), 8L)
  ml = calls[calls$prompt %in% "a multi-line\n   prompt", ]
  expect_identical(c(ml$stmt1, ml$stmt2), c(3L, 6L))
  bad = doc_scan_calls(c("gptr(\"x\"", ""))
  expect_identical(nrow(bad), 0L)
  expect_true(nzchar(attr(bad, "parse_error")))
  expect_identical(nrow(doc_scan_calls(character())), 0L)
})

test_that("calls know their block, block-nested ordinal, prompt hash and identity", {
  lines = c("gptr(\"outer\")", "# >>> gptr:7f3a21 model=m prompt=p", "sub = gptr(\"inner\")",
            "for (i in 1) gptr(\"deep\")", "sub2 = gptr(\"inner two\")", "# <<< gptr:7f3a21",
            "gptr(paste(\"dyn\", x))")
  calls = doc_calls(lines)
  expect_identical(calls$block, c(NA, "7f3a21", "7f3a21", "7f3a21", NA))
  expect_identical(calls$n_in_block, c(NA, 1L, NA, 2L, NA))
  expect_identical(calls$ph[1], prompt_hash("outer"))
  expect_match(calls$th[1], "^[0-9a-f]{12}$")
  expect_identical(doc_calls_have(calls, prompt_hash("inner"), NULL), 2L)
  expect_identical(doc_calls_have(calls, NA_character_, quote(gptr(paste("dyn", x)))), 5L)
  expect_identical(doc_calls_have(calls[0, ], prompt_hash("outer"), NULL), integer())
})

test_that("ownership picks the block by prompt, else by call ordinal (stale), else inserts", {
  lines = c("gptr(\"step one\") |> gptr(\"step two\")",
            "# >>> gptr:aaaaaa model=m prompt=52831d1d544e", "a = 1", "# <<< gptr:aaaaaa", "",
            "# >>> gptr:bbbbbb model=m prompt=0000000000ff call=2", "b = 2", "# <<< gptr:bbbbbb",
            "z = 3")
  calls = doc_calls(lines)
  one = doc_owned_block(lines, calls[1, ], prompt_hash("step one"))
  expect_identical(one$block$id, "aaaaaa")
  expect_false(one$stale)
  two = doc_owned_block(lines, calls[2, ], prompt_hash("step two"))
  expect_identical(two$block$id, "bbbbbb")
  expect_true(two$stale)
  expect_identical(two$insert_after, 8L)
  plain = c("gptr(\"x\")", "y = 1")
  none = doc_owned_block(plain, doc_calls(plain)[1, ], prompt_hash("x"))
  expect_null(none$block)
  expect_identical(none$insert_after, 1L)
})

test_that("a prompt repeated in one pipeline never takes another call's block", {
  ph = prompt_hash("improve it")
  lines = c("gptr(\"draft\") |> gptr(\"improve it\") |> gptr(\"improve it\")",
            paste0("# >>> gptr:aaaaaa model=m prompt=", prompt_hash("draft")), "a = 1",
            "# <<< gptr:aaaaaa",
            paste0("# >>> gptr:bbbbbb model=m prompt=", ph, " call=2"), "b = 2",
            "# <<< gptr:bbbbbb")
  calls = doc_calls(lines)
  expect_identical(doc_same_ordinals(calls, calls[3, ]), 2L)
  third = doc_text_locate(lines, list(anchor = doc_anchor_of(calls, calls[3, ]), prompt_hash = ph))
  expect_null(third$owned)
  expect_identical(third$insert_after, 7L)
  second = doc_text_locate(lines, list(anchor = doc_anchor_of(calls, calls[2, ]),
                                       prompt_hash = ph))
  expect_identical(second$owned$id, "bbbbbb")
  expect_null(doc_run_owner(list(list(prompt = ph, call = "2")), ph, 3L, taken = 2L))
  expect_identical(doc_run_owner(list(list(prompt = ph, call = "2")), ph, 1L)$index, 1L)
})

test_that("anchors re-locate a call by content after lines move", {
  lines = c("x = 1", "gptr(\"same\")", "gptr(\"same\")", "gptr(\"other\")")
  calls = doc_calls(lines)
  a = doc_anchor_of(calls, calls[2, ])
  expect_identical(a$j, 2L)
  moved = c("# a new comment", "", lines[1:2], "# >>> gptr:aaaaaa model=m prompt=p", "k = 1",
            "# <<< gptr:aaaaaa", lines[3:4])
  hit = doc_match_anchor(doc_calls(moved), a)
  expect_identical(hit$line1, 8L)
  site = list(anchor = a, prompt_hash = prompt_hash("same"), args_hash = NULL)
  loc = doc_text_locate(moved, site)
  expect_identical(loc$stmt, c(8L, 8L))
  expect_true(loc$top_level)
  expect_null(loc$owned)
  expect_identical(loc$insert_after, 8L)
  expect_null(doc_match_anchor(doc_calls(lines[1:2]), a))
})

test_that("doc_text_locate() reports the owned block's status and block-nested calls", {
  ph = prompt_hash("count rows")
  body = "n = nrow(mtcars)"
  lines = c("  gptr(\"count rows\")",
            paste0("  # >>> gptr:abc123 model=m prompt=", ph, " sha=", doc_body_sha(body)),
            paste0("  ", body), "  sub = gptr(\"inner\")", "  # <<< gptr:abc123")
  calls = doc_calls(lines)
  site = list(anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = ph, args_hash = NULL)
  loc = doc_text_locate(lines, site)
  expect_identical(loc$owned$id, "abc123")
  expect_identical(loc$owned$status, "user-edited")
  expect_identical(loc$indent, "  ")
  inner = list(anchor = doc_anchor_of(calls, calls[2, ]), prompt_hash = prompt_hash("inner"))
  loc2 = doc_text_locate(lines, inner)
  expect_identical(loc2$in_block, "abc123")
  expect_identical(loc2$ordinal, 1L)
  expect_false(loc2$top_level)
  looped = c(lines[1:4], "  for (i in 1:2) gptr(\"deep\")", lines[5])
  calls3 = doc_calls(looped)
  deep = list(anchor = doc_anchor_of(calls3, calls3[3, ]), prompt_hash = prompt_hash("deep"))
  loc3 = doc_text_locate(looped, deep)
  expect_null(loc3$in_block)
  expect_false(loc3$top_level)
})

test_that("doc_stmt_by_expr() finds the k-th identical top-level expression", {
  lines = c("x = 1", "gptr(\"a\")", "y = 2", "gptr(\"a\")")
  expect_identical(doc_stmt_by_expr(lines, quote(gptr("a")), 2L), c(4L, 4L))
  expect_null(doc_stmt_by_expr(lines, quote(gptr("b"))))
  expect_null(doc_stmt_by_expr("x = (", quote(x)))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 44 ]`, the new tests failing with ``Error in `doc_scan_calls(lines)`: could not find function "doc_scan_calls"`` and the like.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-blocks.R`:

```r
# ---- the gptr() call scanner, anchors and block ownership (report 14 sections 3.1 and 4.2) ----

#' P15's process state `the$doc_pending` (contract 7.0): deferred and pending upserts by
#' document key (`docs`), document locks held until exit (`held`), whether the exit finalizer is
#' registered, gptr_source() frames, the knitr chunks to skip, Rscript call counters, the
#' doc.edit re-entrancy flag and the parse memo of doc_scan_calls() (`scan`, `scan_keys`)
#' @noRd
doc_state = function() {
  st = the$doc_pending
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$docs = list()
    st$held = list()
    st$finalizer = FALSE
    st$sources = list()
    st$knitr_skip = character()
    st$knitr_hooked = FALSE
    st$counters = list()
    st$in_edit = FALSE
    st$scan = new.env(parent = emptyenv())
    st$scan_keys = character()
    the$doc_pending = st
  }
  st
}

#' An empty call table (the columns of doc_scan_calls())
#' @noRd
doc_calls_empty = function() {
  data.frame(line1 = integer(), col1 = integer(), line2 = integer(), col2 = integer(),
             stmt1 = integer(), stmt2 = integer(), nested = logical(), prompt = character(),
             n_in_stmt = integer(), text = character(), stringsAsFactors = FALSE)
}

#' The gptr() calls of an R text: positions, statement range, nesting, prompt literal, ordinal
#' within the statement (report 14 doc_scan_calls, with `prompt =` and named-argument handling).
#' A text that does not parse gives no calls and the attribute `parse_error`. Texts of 20 lines
#' or more are remembered (the 16 most recently used), so every gptr() call of a long script
#' locates through one parse.
#' @noRd
doc_scan_calls = function(lines, fun = "gptr", line_offset = 0L) {
  lines = as_utf8(as.character(lines))
  if (!length(lines)) return(doc_calls_empty())
  if (length(lines) < 20L) return(doc_scan_parse(lines, fun, line_offset))
  st = doc_state()
  key = hash_sha256(paste(c(fun, line_offset, lines), collapse = "\n"))
  res = get0(key, envir = st$scan, inherits = FALSE)
  if (is.null(res)) {
    res = doc_scan_parse(lines, fun, line_offset)
    assign(key, res, envir = st$scan)
  }
  st$scan_keys = c(setdiff(st$scan_keys, key), key)
  if (length(st$scan_keys) > 16L) {
    rm(list = st$scan_keys[1L], envir = st$scan)
    st$scan_keys = st$scan_keys[-1L]
  }
  res
}

#' The parse behind doc_scan_calls(): ids are looked up through vectors indexed by parse-data id
#' @noRd
doc_scan_parse = function(lines, fun, line_offset) {
  empty = doc_calls_empty()
  exprs = tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) {
    attr(empty, "parse_error") = conditionMessage(exprs)
    return(empty)
  }
  pd = utils::getParseData(exprs, includeText = TRUE)
  if (is.null(pd) || !nrow(pd)) return(empty)
  sym = which(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == fun)
  if (!length(sym)) return(empty)
  parent = integer(max(pd$id))
  parent[pd$id] = pd$parent
  row = integer(max(pd$id))
  row[pd$id] = seq_len(nrow(pd))
  nest = c("FUNCTION", "'\\\\'", "FOR", "WHILE", "REPEAT", "IF", "'{'")
  nesting = unique(pd$parent[pd$token %in% nest])
  rows = vector("list", length(sym))
  for (i in seq_along(sym)) {
    call_id = parent[parent[pd$id[sym[i]]]]
    anc = call_id
    nested = FALSE
    repeat {
      p = parent[anc]
      if (p <= 0L) break
      if (p %in% nesting) nested = TRUE
      anc = p
    }
    top = row[anc]
    cl = row[call_id]
    rows[[i]] = data.frame(line1 = pd$line1[cl], col1 = pd$col1[cl], line2 = pd$line2[cl],
                           col2 = pd$col2[cl], stmt1 = pd$line1[top], stmt2 = pd$line2[top],
                           nested = nested, prompt = doc_call_prompt(pd, call_id),
                           n_in_stmt = NA_integer_, text = utils::getParseText(pd, call_id),
                           stringsAsFactors = FALSE)
  }
  res = do.call(rbind, rows)
  res = res[order(res$line1, res$col1, method = "radix"), , drop = FALSE]
  shift = as.integer(line_offset)
  res$line1 = res$line1 + shift
  res$line2 = res$line2 + shift
  res$stmt1 = res$stmt1 + shift
  res$stmt2 = res$stmt2 + shift
  res$n_in_stmt = as.integer(stats::ave(res$line1, res$stmt1, FUN = seq_along))
  rownames(res) = NULL
  res
}

#' The prompt literal of a call: `prompt =` wins, else the first unnamed string literal
#' @noRd
doc_call_prompt = function(pd, call_id) {
  ch = pd[pd$parent == call_id, , drop = FALSE]
  ch = ch[order(ch$line1, ch$col1, method = "radix"), , drop = FALSE]
  named = NULL
  positional = NULL
  pending = NULL
  seen_fun = FALSE
  for (k in seq_len(nrow(ch))) {
    tok = ch$token[k]
    if (identical(tok, "SYMBOL_SUB")) {
      pending = ch$text[k]
      next
    }
    if (!identical(tok, "expr")) next
    if (!seen_fun) {
      seen_fun = TRUE
      next
    }
    arg = pd[pd$parent == ch$id[k], , drop = FALSE]
    val = NULL
    if (nrow(arg) == 1L && identical(arg$token, "STR_CONST")) {
      val = tryCatch(str2lang(utils::getParseText(pd, arg$id)), error = function(e) NULL)
      if (!is.character(val)) val = NULL
    }
    if (is.null(pending)) {
      if (is.null(positional) && !is.null(val)) positional = val
    } else if (identical(pending, "prompt") && !is.null(val)) {
      named = val
    }
    pending = NULL
  }
  as_utf8(named %||% positional %||% NA_character_)
}

#' All gptr() calls of an R text with their block, ordinal inside the block, prompt hash (`ph`)
#' and call-text hash (`th`, the identity of calls with a computed prompt)
#' @noRd
doc_calls = function(lines, blocks = doc_find_blocks(lines)) {
  calls = doc_scan_calls(lines)
  n = nrow(calls)
  calls$block = rep(NA_character_, n)
  calls$n_in_block = rep(NA_integer_, n)
  calls$ph = rep(NA_character_, n)
  calls$th = rep(NA_character_, n)
  if (n) {
    lit = !is.na(calls$prompt)
    calls$ph[lit] = vapply(calls$prompt[lit], prompt_hash, "", USE.NAMES = FALSE)
    calls$th = substr(hash_sha256(calls$text), 1L, 12L)
    if (nrow(blocks)) {
      calls$block = vapply(calls$line1, function(l) {
        k = which(l > blocks$start & l < blocks$end)
        if (length(k)) blocks$id[k[1L]] else NA_character_
      }, "")
    }
    inb = !is.na(calls$block) & !calls$nested
    if (any(inb)) {
      calls$n_in_block[inb] = as.integer(stats::ave(seq_len(sum(inb)), calls$block[inb],
                                                    FUN = seq_along))
    }
  }
  attr(calls, "blocks") = blocks
  calls
}

#' Rows of a call table that contain the call: by prompt hash, else (computed prompts, whose
#' template is the prompt text) by identity of the call (`call0`, without attributes)
#' @noRd
doc_calls_have = function(calls, ph, call0) {
  if (!nrow(calls)) return(integer())
  if (!is.na(ph)) {
    k = which(calls$ph %in% ph)
    if (length(k) || is.null(call0)) return(k)
  }
  if (is.null(call0)) return(integer())
  which(is.na(calls$ph) & vapply(calls$text, function(t) {
    identical(tryCatch(str2lang(t), error = function(e) NULL), call0)
  }, NA, USE.NAMES = FALSE))
}

#' Calls that share an anchor's identity (prompt hash, else call-text hash)
#' @noRd
doc_same_calls = function(calls, ph, th = NA_character_) {
  keep = if (!is.na(ph)) calls$ph %in% ph else calls$th %in% th
  calls[keep, , drop = FALSE]
}

#' The anchor of call row `t` (IC-51: calls are re-located by content and ordinal, never by line)
#' @noRd
doc_anchor_of = function(calls, t) {
  cls = if (is.na(t$block)) calls[is.na(calls$block), , drop = FALSE] else
    calls[calls$block %in% t$block, , drop = FALSE]
  label = t$label %||% NA_character_
  if (!is.na(label) && !is.null(cls$label)) cls = cls[cls$label %in% label, , drop = FALSE]
  same = doc_same_calls(cls, t$ph, t$th)
  j = which(same$line1 == t$line1 & same$col1 == t$col1)
  list(ph = t$ph, th = t$th, j = if (length(j)) j[1L] else 1L, block = t$block, label = label)
}

#' Re-locate an anchored call in a (possibly edited) text; NULL when it is gone
#' @noRd
doc_match_anchor = function(calls, anchor) {
  if (is.null(anchor) || !nrow(calls)) return(NULL)
  cls = if (is.na(anchor$block)) calls[is.na(calls$block), , drop = FALSE] else
    calls[calls$block %in% anchor$block, , drop = FALSE]
  if (!is.na(anchor$label %||% NA_character_) && !is.null(cls$label)) {
    cls = cls[cls$label %in% anchor$label, , drop = FALSE]
  }
  same = doc_same_calls(cls, anchor$ph, anchor$th)
  if (nrow(same) < anchor$j) return(NULL)
  same[anchor$j, , drop = FALSE]
}

#' The run of blocks directly after a statement (blank lines allowed between blocks)
#' @noRd
doc_blocks_after = function(lines, stmt_end, blocks) {
  out = integer()
  pos = stmt_end
  repeat {
    k = pos + 1L
    while (k <= length(lines) && !nzchar(trimws(lines[k]))) k = k + 1L
    b = which(blocks$start == k)
    if (!length(b)) break
    out = c(out, b[1L])
    pos = blocks$end[b[1L]]
  }
  blocks[out, , drop = FALSE]
}

#' Which block of a statement's run the k-th call owns (contract 11.5): the block whose
#' `prompt=` matches (preferring `call=k`), else the one with `call=k` (then stale); `headers` is
#' the list of block headers in run order. `taken` holds the ordinals of the statement's other
#' calls with the same prompt: their blocks are never matched by prompt alone (a pipeline that
#' repeats a prompt, `... |> gptr("improve it") |> gptr("improve it")`). Returns list(index,
#' stale) or NULL.
#' @noRd
doc_run_owner = function(headers, ph, k = 1L, taken = integer()) {
  if (!length(headers)) return(NULL)
  hdr = function(f) vapply(headers, function(h) as.character(h[[f]] %||% NA_character_), "")
  ord = suppressWarnings(as.integer(hdr("call")))
  ord[is.na(ord)] = 1L
  exact = which(hdr("prompt") %in% ph & ord == k)
  if (!length(exact)) exact = which(hdr("prompt") %in% ph & !(ord %in% taken))
  if (length(exact)) return(list(index = exact[1L], stale = FALSE))
  pos = which(ord == k)
  if (length(pos)) return(list(index = pos[1L], stale = TRUE))
  NULL
}

#' The block owned by the k-th call of a statement (doc_run_owner() over the run of blocks after
#' the statement) and where a new block of that call goes: after the run, or after the blocks
#' of earlier calls of a pipeline; `taken` as in doc_run_owner()
#' @noRd
doc_owned_block = function(lines, hit, ph, blocks = doc_find_blocks(lines), taken = integer()) {
  run = doc_blocks_after(lines, hit$stmt2, blocks)
  k = hit$n_in_stmt
  if (!nrow(run)) return(list(block = NULL, stale = FALSE, run = run, insert_after = hit$stmt2))
  own = doc_run_owner(run$header, ph, k, taken)
  if (!is.null(own)) {
    return(list(block = run[own$index, , drop = FALSE], stale = own$stale, run = run,
                insert_after = run$end[nrow(run)]))
  }
  ord = suppressWarnings(as.integer(vapply(run$header, function(h) {
    as.character(h$call %||% NA_character_)
  }, "")))
  ord[is.na(ord)] = 1L
  before = which(ord < k)
  list(block = NULL, stale = FALSE, run = run,
       insert_after = if (length(before)) run$end[max(before)] else hit$stmt2)
}

#' Ordinals of the other calls of a hit's statement that share its prompt hash (doc_run_owner())
#' @noRd
doc_same_ordinals = function(calls, hit) {
  if (is.na(hit$ph)) return(integer())
  keep = calls$stmt1 == hit$stmt1 & calls$ph %in% hit$ph & is.na(calls$block) &
    !calls$nested & calls$n_in_stmt != hit$n_in_stmt
  as.integer(calls$n_in_stmt[keep])
}

#' Locate an anchored call and its owned block in an R text (the `r` and `transcript` formats):
#' list(stmt, blocks, hit, owned = list(id, header, status, start, end) | NULL, insert_after,
#' top_level, in_block, ordinal, indent)
#' @noRd
doc_text_locate = function(text, site, calls = doc_calls(text)) {
  blocks = attr(calls, "blocks")
  out = list(stmt = NULL, blocks = blocks[0L, , drop = FALSE], hit = NULL, owned = NULL,
             insert_after = NULL, top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "")
  hit = doc_match_anchor(calls, site$anchor)
  if (is.null(hit)) return(out)
  out$hit = hit
  out$stmt = c(hit$stmt1, hit$stmt2)
  out$indent = sub("^([ \t]*).*$", "\\1", text[hit$stmt1])
  if (isTRUE(hit$nested)) return(out)
  if (!is.na(hit$block)) {
    out$in_block = hit$block
    out$ordinal = hit$n_in_block
    return(out)
  }
  out$ordinal = hit$n_in_stmt
  out$top_level = TRUE
  own = doc_owned_block(text, hit, site$prompt_hash, blocks, doc_same_ordinals(calls, hit))
  out$blocks = own$run
  out$insert_after = own$insert_after
  if (!is.null(own$block)) {
    b = own$block
    status = doc_block_status(b$header[[1L]], doc_block_body(text, b), site$prompt_hash,
                              site$args_hash)
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = b$id, header = b$header[[1L]], status = status, start = b$start,
                     end = b$end)
  }
  out
}

#' Line range of the k-th top-level expression identical to `expr` (source() frames)
#' @noRd
doc_stmt_by_expr = function(lines, expr, k = 1L) {
  p_src = tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) NULL)
  if (is.null(p_src)) return(NULL)
  p_val = parse(text = lines, keep.source = FALSE)
  srs = attr(p_src, "srcref")
  hits = which(vapply(seq_along(p_val), function(j) identical(p_val[[j]], expr), NA))
  if (length(hits) < k) return(NULL)
  sr = srs[[hits[k]]]
  c(sr[1L], sr[3L])
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 90 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-blocks.R tests/testthat/test-doc-blocks.R
git commit -m "feat(doc): find gptr() calls by content and resolve the blocks they own"
```

---

### Task 3: The recorded block content: `doc_block_lines()`

**Files:**
- Modify: `R/doc-blocks.R` (append)
- Test: `tests/testthat/test-doc-blocks.R` (append)

**Interfaces:**
- Consumes: Tasks 1-2; P01 `msg_text(msg)`, `as_utf8()`, `gptr_opt()`, `setting_get(key, session = NULL, default =
  NULL)`; P02 `registry_get(kind, name, session = NULL)` (the `record` field of a member's tool spec, IC-48); P03
  `code_for_history(code)` (chr(1) with attribute `needs`; it prefixes `# gptr: block needs secrets that are not
  recorded` when a marker stays) and `redact(x, profile = "persist")`; P06 `session_data(s)` (read: `id`, `kind`,
  `mode`, `model`, `entries`, `leaf`, `turns`, `children`, `fork_of`, `home_label`, `last_text`, `exports`,
  `created`). Entry shapes (04 §4.6, P06 `entry_message()`/`entry_custom()`): `list(type = "message", message,
  gptr = list(turn))` (P06 stamps every user message with the turn it opened), `list(type = "custom_message",
  custom_type = "gptr.operator", message = <operator msg>)` (a steer relay has `kind = "steer_relay"` and
  `origin_text`), `list(type = "custom", custom_type, data)` (`gptr.value` `{turn, mode, name}`; `gptr.plan`
  `{path, ...}`, P11); ids `id`/`parent_id`. The `r` tool result `details` (P09/P10): `code`, `status` (`"ok"`),
  `outputs` (chr, or a list of printed output per top-level expression, 04 §5.8), `record`, `note`, `value`, and the
  optional `bridge` (digests) and `artifacts` (paths); the call's `arguments` hold `code`, `record`, `note`. A user
  message's `plan` context block carries `attrs$from` (the session whose pending plan was consumed, P07/P11).
- Produces (04 §7.15): `doc_block_lines(session, turn, site, call_ordinal)` -> chr body lines (the block id inside
  wrapped code is `doc_block_token`) with attributes `header` (the §11.5 keys: `model`, `date`, `prompt`, `call`,
  `tokens`, `cost`, `session`, `turn`, `value`, `fork`, `plan`, `args`; teams add `kind`, `children`), `session`
  (the session), `answer` (the final text) and `children` (named list `list(text, session, model, turn, sent)` per
  S2 part: `n<k>` for the child session that answered the k-th direct `gptr()` call of the block body, with `sent`
  the prompt hash of that child's first prompt; child names for team members, IC-47); helpers
  `doc_code_clean(code)` (attribute `kept`), `doc_history_code(lines)`, `doc_output_lines(outputs, max_lines = NULL,
  width = 76L)`, `doc_wrap_local(body, child = NULL)`, `doc_path_entries(session)`, `doc_turn_entries(session,
  turn)`, `doc_turn_body(ents, with_out = TRUE, plan_mode = FALSE)`, `doc_turn_children(session, ents)`,
  `doc_nested_parts(body, kids)`, `doc_session_code(session)`, `doc_team_block_lines(team, site, call_ordinal)`,
  `doc_secret_flag`.

The body follows 04 §11.5 and IC-47..IC-49. `doc_code_clean()` drops, at top-level-expression granularity
(`getParseData()`/srcrefs of each recorded chunk), `gptr_return()`/`gptr::gptr_return()` and calls of `record =
FALSE` members (the tool spec's `record`, else `out`, `plot`, `help`, `search`, `describe`), cutting only the
dropped bytes when a line holds several expressions, and rewrites a `LEFT_ASSIGN` that is a top-level expression or
a direct child of a `{` list to `=` (never inside call arguments; the superassignment, the right arrow and pipes stay;
IC-48). The output of a dropped expression is dropped with it when the outputs are per expression. Entries are
redacted at ingress (P06), so recorded code holds secret markers: a literal that is exactly `"[secret:NAME]"`
becomes `Sys.getenv("NAME")` and anything that stays a marker flags the block (G6 §5.6, P03). Plan-mode turns give
one `## Plan: <path>` line (IC-48); steers and follow-ups delivered during the turn give `## Steer:`/`## Follow-up:`
lines (IC-49); an overlay fork's body is wrapped `local({ ... }, envir = gptr_resume(block = "<id>")$envir)` and
its header gets `fork=<parent>:<turn>` (IC-46); team and fan-out sessions give one `## Agent` line per child in name
order plus overlay code and export assignments for children with exports (IC-47).

Two facts of the dependency plans shape the rest. P10's `r` tool flattens `details$outputs` into one character vector
(`r_doc_outputs()`, 04 §4.4 "`outputs` chr"), so the output of a dropped expression can be dropped only when an
evaluator returns outputs per expression (a list, as P09's `gptr_eval_result$outputs` is); with P10's flat vector the
printed text of, say, `gptr$out(id, lines = 1)` stays in the block as a harmless `#>` comment. And the S2 parts of
block-nested calls (IC-47) must follow the calls the locator will see on re-source: the k-th *direct* `gptr()` call of
the block body (not inside a loop, function or braces) owns part `n<k>`, answered by the child whose first prompt has
that call's prompt hash (a computed or interpolated prompt takes the next child no literal call claims). Children of
calls inside loops or functions get no part, so a loop that made sub-calls before a direct call can never shift the
mapping; each part records `sent`, which replay compares with the prompt of the call it answers (Task 12).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-blocks.R`:

```r
# A session with recorded turns, built the way P06 records them: the turn counter moves first,
# then the turn's entries are appended (user messages carry their turn number)
doc_test_session = function(turns, mode = "auto", kind = "chat", home = new.env()) {
  s = session_new("fake/fake-1", mode, home = home, kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, note = NULL, outputs = character(), status = "ok", record = TRUE,
                         prompt = "count rows", answer = "There are 32 rows.", value = NULL,
                         id = "call_1") {
  usage = function(i, o) {
    list(input = i, output = o, cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
         cost = list(total = 0))
  }
  args = list(code = code)
  if (!is.null(note)) args$note = note
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call(id, "r", args)), api = "fake", provider = "fake",
      model = "fake-1", usage = usage(100, 20), stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      id, "r", "[1] 32", is_error = !identical(status, "ok"),
      details = list(code = code, record = record, note = note, status = status,
                     outputs = outputs, value = value))),
    list(type = "message", message = msg_assistant(
      answer, api = "fake", provider = "fake", model = "fake-1", usage = usage(150, 10)))
  )
}

test_that("recorded code drops gptr_return() and record = FALSE members and rewrites arrows", {
  arrow = paste0("<", "-")
  code = c(paste("fit", arrow, "lm(mpg ~ wt, data = mtcars)"), "gptr_return(fit)",
           "gptr$out(\"o1a2b3\")", "hits = gptr$grep(\"mtcars\")",
           paste0("x ", arrow, " \"a ", arrow, " b\"; gptr::gptr_return(x)"),
           paste0("f(y ", arrow, " 1)"), "{", paste0("  z ", arrow, " 2"), "}",
           paste0("g = function() { w ", arrow, " 3 }"), paste0("a <", arrow, " 1"), "dt[, b := 2]",
           paste("p", arrow, "q", arrow, "4"), paste0("if (TRUE) v ", arrow, " 5"))
  out = doc_code_clean(code)
  expect_identical(as.character(out), c(
    "fit = lm(mpg ~ wt, data = mtcars)", "hits = gptr$grep(\"mtcars\")",
    paste0("x = \"a ", arrow, " b\""), paste0("f(y ", arrow, " 1)"), "{", "  z = 2", "}",
    paste0("g = function() { w ", arrow, " 3 }"), paste0("a <", arrow, " 1"), "dt[, b := 2]",
    paste("p = q", arrow, "4"), paste0("if (TRUE) v ", arrow, " 5")))
  expect_identical(attr(out, "kept"), c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE,
                                        TRUE, TRUE, TRUE, TRUE))
  expect_identical(as.character(doc_code_clean("gptr_return(fit)")), character())
  expect_identical(as.character(doc_code_clean("x = 1 +")), "x = 1 +")
  expect_null(attr(doc_code_clean("x = 1 +"), "kept"))
  expect_identical(as.character(doc_code_clean(c("", "x = 1", ""))), "x = 1")
})

test_that("printed output becomes at most gptr.doc_output_lines #> lines of 76 characters", {
  out = doc_output_lines(as.character(1:20), max_lines = 12L)
  expect_length(out, 13L)
  expect_identical(out[13], "#> ... (8 more lines)")
  expect_identical(doc_output_lines(strrep("x", 100), max_lines = 12L)[1],
                   paste0("#> ", strrep("x", 76)))
  expect_identical(doc_output_lines(character()), character())
  expect_identical(doc_output_lines("a\nb"), c("#> a", "#> b"))
  expect_identical(doc_output_lines(list(character(), "[1] 4", c("x", "y"))),
                   c("#> [1] 4", "#> x", "#> y"))
  local_gptr_options(doc_output_lines = 1L)
  expect_identical(doc_output_lines(c("a", "b")), c("#> a", "#> ... (1 more lines)"))
})

test_that("turn entries follow P06's turn stamps", {
  s = doc_test_session(list(doc_test_turn("a = 1", prompt = "one"),
                            doc_test_turn("b = 2", prompt = "two")))
  expect_length(doc_path_entries(s), 8L)
  t2 = doc_turn_entries(s, 2L)
  expect_length(t2, 4L)
  expect_identical(msg_text(t2[[1]]$message), "two")
  expect_identical(doc_turn_entries(s, 3L), list())
})

test_that("a turn's block holds recorded code, outputs, decision, value and header facts", {
  arrow = paste0("<", "-")
  s = doc_test_session(list(doc_test_turn(paste("n_rows", arrow, "nrow(mtcars)\nn_rows"),
                                          note = "count rows", outputs = "[1] 32",
                                          value = "n_rows")))
  site = list(format = "r", prompt_hash = prompt_hash("count rows"), args_hash = NULL,
              template = "count rows")
  lines = doc_block_lines(s, 1L, site, 1L)
  expect_identical(as.character(lines), c("n_rows = nrow(mtcars)", "n_rows", "#> [1] 32",
                                          "## Decision: count rows"))
  h = attr(lines, "header")
  expect_identical(h$model, "fake/fake-1")
  expect_identical(h$prompt, prompt_hash("count rows"))
  expect_identical(h$value, "n_rows")
  expect_identical(h$turn, 1L)
  expect_identical(h$tokens, "250/30")
  expect_identical(h$session, session_data(s)$id)
  expect_null(h$call)
  expect_identical(attr(lines, "answer"), "There are 32 rows.")
  rmd = doc_block_lines(s, 1L, utils::modifyList(site, list(format = "rmd")), 1L)
  expect_false(any(grepl("^#>", rmd)))
  expect_identical(attr(doc_block_lines(s, 1L, site, 2L), "header")$call, 2L)
})

test_that("the output of a dropped expression is dropped with it when outputs are per expression", {
  code = "fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\ngptr$out(\"o1a2b3c\", lines = 1)"
  s = doc_test_session(list(doc_test_turn(code, outputs = list(character(), character(),
                                                                "[1] \"line\""))))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), "fit = lm(mpg ~ wt, data = mtcars)")
  # P10 flattens outputs into one character vector: the code is still dropped, the printed
  # line stays as a #> comment (it cannot be told apart)
  flat = doc_test_session(list(doc_test_turn(code, outputs = "[1] \"line\"")))
  flat_lines = doc_block_lines(flat, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(flat_lines),
                   c("fit = lm(mpg ~ wt, data = mtcars)", "#> [1] \"line\""))
})

test_that("child answers map to the block's direct gptr() calls by prompt, not creation order", {
  code = paste0("subs = lapply(1:2, function(i) gptr(paste(\"part\", i)))\n",
                "total = gptr(\"Summarise the parts\")")
  s = doc_test_session(list(doc_test_turn(code)))
  kid = function(prompt, text) {
    k = doc_test_session(list(doc_test_turn("x = 1", prompt = prompt, answer = text)))
    kd = session_data(k)
    kd$last_text = text
    k
  }
  sd = session_data(s)
  sd$children = list(a = kid("part 1", "one"), b = kid("part 2", "two"),
                     c = kid("Summarise the parts", "both"))
  parts = attr(doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L),
               "children")
  expect_named(parts, "n1")
  expect_identical(parts$n1$text, "both")
  expect_identical(parts$n1$sent, prompt_hash("Summarise the parts"))
  expect_identical(doc_nested_parts(character(), sd$children), list())
})

test_that("failed and unrecorded calls are left out and plan-mode turns give one Plan line", {
  s = doc_test_session(list(doc_test_turn("stop('x')", status = "error", id = "c1"),
                            doc_test_turn("head(mtcars)", record = FALSE, id = "c2",
                                          prompt = "b")))
  site = list(format = "r", template = "count rows")
  expect_identical(as.character(doc_block_lines(s, 1L, site, 1L)), character())
  expect_identical(as.character(doc_block_lines(s, 2L, site, 1L)), character())
  plan = doc_test_turn("x = 1")
  plan = c(plan, list(list(type = "custom", custom_type = "gptr.plan",
                           data = list(path = ".gptr/plans/2026-09-29-tidy.md"))))
  p = doc_test_session(list(plan), mode = "plan")
  expect_identical(as.character(doc_block_lines(p, 1L, site, 1L)),
                   "## Plan: .gptr/plans/2026-09-29-tidy.md")
})

test_that("steers and follow-ups delivered during the turn are recorded as comment lines", {
  turn = doc_test_turn("x = 1")
  relay = list(type = "custom_message", message = msg_operator(
    "steer_relay", "The user sent this message while you were working: use TPM",
    origin_text = "use TPM"))
  follow = list(type = "message", message = msg_user("and plot it", source = "follow_up"))
  early = list(type = "message", message = msg_user("use log scale", source = "steer"))
  s = doc_test_session(list(c(turn[1], list(early), turn[2:3], list(relay), turn[4],
                              list(follow))))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), c("## Steer: use log scale", "x = 1", "## Steer: use TPM",
                                          "## Follow-up: and plot it"))
  expect_identical(attr(lines, "header")$turn, 1L)
})

test_that("secret markers become Sys.getenv() and an unreplayable one flags the block", {
  # entries are redacted at ingress (P06), so recorded code holds markers, never values
  s = doc_test_session(list(doc_test_turn("k = \"[secret:DOC_TEST_KEY]\"\nn = nchar(k)")))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), c("k = Sys.getenv(\"DOC_TEST_KEY\")", "n = nchar(k)"))
  s2 = doc_test_session(list(doc_test_turn("h = \"Bearer [secret:DOC_TEST_KEY]\"")))
  flagged = doc_block_lines(s2, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(flagged), c("# gptr: block needs secrets that are not recorded",
                                            "h = \"Bearer [secret:DOC_TEST_KEY]\""))
  expect_identical(doc_history_code(character()), list(lines = character(), secrets = FALSE))
})

test_that("an overlay fork's block is wrapped in local() on its gptr_resume(block =) home", {
  home = new.env()
  overlay = new.env(parent = home)
  attr(overlay, "gptr_overlay") = "overlay of s0123456789"
  f = doc_test_session(list(), home = overlay)
  d = session_data(f)
  d$fork_of = list(id = "s0123456789", entry = "9f3a1c2b", turn = 1L)
  d$home_label = "overlay of s0123456789"
  d$turns = 1L
  d$turns = d$turns + 1L
  for (e in doc_test_turn("qc_flags = 2", prompt = "Try 10%")) session_append(f, e)
  lines = doc_block_lines(f, 2L, list(format = "r", template = "Try 10%"), 1L)
  expect_identical(as.character(lines),
                   c("local({", "  qc_flags = 2",
                     paste0("}, envir = gptr_resume(block = \"", doc_block_token, "\")$envir)")))
  expect_identical(attr(lines, "header")$fork, "s0123456789:1")
})

test_that("a team block has one line per child, child overlays and export assignments", {
  team = doc_test_session(list(), kind = "team")
  td = session_data(team)
  kid = function(name, model, text, exports = character(), code = NULL) {
    k = doc_test_session(if (is.null(code)) list() else list(doc_test_turn(code)))
    kd = session_data(k)
    kd$model = model
    kd$last_text = text
    kd$exports = exports
    k
  }
  td$children = list(stats = kid("stats", "anthropic/claude-opus-5-5", "Looks fine.\nMore."),
                     code = kid("code", "openai/gpt-5.5", "Two bugs.", "fixed",
                                "fixed = TRUE"))
  lines = doc_block_lines(team, 1L, list(format = "r", template = "Review"), 1L)
  code_id = session_data(td$children$code)$id
  stats_id = session_data(td$children$stats)$id
  expect_identical(as.character(lines), c(
    "## Agent code (openai/gpt-5.5): Two bugs.", "local({", "  fixed = TRUE",
    paste0("}, envir = gptr_resume(block = \"", doc_block_token, "\", child = \"code\")$envir)"),
    paste0("fixed = gptr_resume(block = \"", doc_block_token, "\", child = \"code\")$envir$fixed"),
    "## Agent stats (anthropic/claude-opus-5-5): Looks fine."))
  h = attr(lines, "header")
  expect_identical(h$kind, "team")
  expect_identical(h$children, paste0("code:", code_id, ",stats:", stats_id))
  expect_named(attr(lines, "children"), c("code", "stats"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 90 ]`, the new tests failing with ``Error in `doc_code_clean(code)`: could not find function "doc_code_clean"`` and ``could not find function "doc_block_lines"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-blocks.R`:

```r
# ---- recorded block content (contract 11.5 body; IC-47, IC-48, IC-49) --------------------------

# gptr$ members that are never recorded when no tool spec says otherwise (IC-48)
doc_unrecorded_members = c("out", "plot", "help", "search", "describe")

#' Is a gptr$ member recorded? The tool spec's `record` field, else the IC-48 default list
#' @noRd
doc_member_recorded = function(name) {
  spec = tryCatch(registry_get("tool", name), error = function(e) NULL)
  if (!is.null(spec)) return(!isFALSE(spec$record))
  !name %in% doc_unrecorded_members
}

#' Should a top-level expression of recorded code be dropped: gptr_return() or a call of a
#' `record = FALSE` gptr$ member (IC-48)
#' @noRd
doc_drop_expr = function(e) {
  if (!is.call(e)) return(FALSE)
  head = e[[1L]]
  if (identical(head, quote(gptr_return)) || identical(head, quote(gptr::gptr_return))) {
    return(TRUE)
  }
  if (is.call(head) && length(head) == 3L &&
      (identical(head[[1L]], as.name("$")) || identical(head[[1L]], as.name("[["))) &&
      (identical(head[[2L]], quote(gptr)) || identical(head[[2L]], quote(gptr::gptr)))) {
    return(!doc_member_recorded(as.character(head[[3L]])))
  }
  FALSE
}

#' Remove the source ranges of dropped expressions; on a line shared with kept expressions only
#' the dropped expression's bytes are cut
#' @noRd
doc_drop_ranges = function(lines, drop, keep) {
  keep_lines = unique(unlist(lapply(keep, function(sr) seq(sr[1L], sr[3L]))))
  remove = logical(length(lines))
  cuts = list()
  for (sr in drop) {
    rng = seq(sr[1L], sr[3L])
    if (!any(rng %in% keep_lines)) {
      remove[rng] = TRUE
      next
    }
    if (sr[1L] == sr[3L]) {
      key = as.character(sr[1L])
      cuts[[key]] = c(cuts[[key]], list(c(sr[2L], sr[4L])))
    }
  }
  for (key in names(cuts)) {
    l = as.integer(key)
    r = charToRaw(lines[l])
    rs = cuts[[key]]
    rs = rs[order(-vapply(rs, function(x) as.numeric(x[1L]), 1), method = "radix")]
    for (x in rs) r = c(r[seq_len(x[1L] - 1L)], r[-seq_len(x[2L])])
    s = rawToChar(r)
    Encoding(s) = "UTF-8"
    s = sub("^([ \t]*);[ \t]*", "\\1", s)
    s = sub("[ \t]*;[ \t]*$", "", s)
    s = gsub(";[ \t]*;", ";", s)
    lines[l] = s
    if (!nzchar(trimws(s))) remove[l] = TRUE
  }
  lines[!remove]
}

#' Best-effort S-9 rewrite of the left arrow to `=` (IC-48): LEFT_ASSIGN tokens whose assignment
#' is a top-level expression or a direct child of a `{` list, never inside call arguments; `->`,
#' the superassignment and pipes are left alone. Lines with multi-line tokens are skipped.
#' @noRd
doc_rewrite_assign = function(lines) {
  exprs = tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) NULL)
  if (is.null(exprs) || !length(exprs)) return(lines)
  pd = utils::getParseData(exprs, includeText = TRUE)
  if (is.null(pd) || !nrow(pd)) return(lines)
  rownames(pd) = pd$id
  arrow = paste0("<", "-")
  la = pd[pd$token == "LEFT_ASSIGN" & pd$text == arrow, , drop = FALSE]
  if (!nrow(la)) return(lines)
  kids = split(pd$token, pd$parent)
  allowed = function(p) {
    repeat {
      if (is.na(p) || p <= 0L) return(TRUE)
      if (!("'{'" %in% kids[[as.character(p)]])) return(FALSE)
      p = pd[as.character(p), "parent"]
    }
  }
  ok = vapply(la$parent, function(a) allowed(pd[as.character(a), "parent"]), NA)
  la = la[ok, , drop = FALSE]
  if (!nrow(la)) return(lines)
  term = pd[pd$terminal, , drop = FALSE]
  for (l in unique(la$line1)) {
    toks = term[term$line1 <= l & term$line2 >= l, , drop = FALSE]
    if (!nrow(toks) || any(toks$line1 != toks$line2)) next
    toks = toks[order(toks$col1, method = "radix"), , drop = FALSE]
    txt = lines[l]
    pos = 1L
    hits = integer()
    failed = FALSE
    for (k in seq_len(nrow(toks))) {
      tt = if (identical(toks$token[k], "STR_CONST")) {
        utils::getParseText(pd, toks$id[k])
      } else {
        toks$text[k]
      }
      m = regexpr(tt, substring(txt, pos), fixed = TRUE)
      if (m < 0L) {
        failed = TRUE
        break
      }
      start = pos + as.integer(m) - 1L
      if (toks$id[k] %in% la$id) hits = c(hits, start)
      pos = start + nchar(tt)
    }
    if (failed || !length(hits)) next
    for (h in rev(hits)) txt = paste0(substr(txt, 1L, h - 1L), "=", substring(txt, h + 2L))
    lines[l] = txt
  }
  lines
}

#' Recorded code of one r call: drop gptr_return() and record = FALSE members, rewrite the left
#' arrow, trim blank edges (IC-48). Attribute `kept`: one logical per top-level expression (NULL
#' when the code does not parse; such code is kept as written).
#' @noRd
doc_code_clean = function(code) {
  lines = strsplit(as_utf8(paste(code, collapse = "\n")), "\n", fixed = TRUE)[[1L]]
  if (!length(lines)) return(character())
  exprs = tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) NULL)
  kept = NULL
  if (!is.null(exprs) && length(exprs)) {
    srcs = attr(exprs, "srcref")
    drop = vapply(seq_along(exprs), function(i) doc_drop_expr(exprs[[i]]), NA)
    if (any(drop)) lines = doc_drop_ranges(lines, srcs[drop], srcs[!drop])
    lines = doc_rewrite_assign(lines)
    kept = !drop
  }
  while (length(lines) && !nzchar(trimws(lines[1L]))) lines = lines[-1L]
  while (length(lines) && !nzchar(trimws(lines[length(lines)]))) lines = lines[-length(lines)]
  structure(lines, kept = kept)
}

#' The flag line of a block whose code holds a secret that cannot be replayed (contract 11.5)
#' @noRd
doc_secret_flag = "# gptr: block needs secrets that are not recorded"

#' Recorded code made safe for a document (G6 5.6): a string literal that is exactly a secret
#' marker of an environment variable (entries are redacted at ingress) becomes Sys.getenv("NAME"),
#' then P03's code_for_history() rewrites literal values and flags what stays a marker.
#' Returns list(lines, secrets) where `secrets` tells that the flag line is needed.
#' @noRd
doc_history_code = function(lines) {
  if (!length(lines)) return(list(lines = character(), secrets = FALSE))
  code = paste(lines, collapse = "\n")
  code = gsub("([\"'])\\[secret:([A-Za-z_][A-Za-z0-9_]*)\\]\\1", "Sys.getenv(\"\\2\")", code,
              perl = TRUE)
  out = strsplit(as.character(code_for_history(code)), "\n", fixed = TRUE)[[1L]]
  secrets = length(out) > 0L && identical(out[1L], doc_secret_flag)
  if (secrets) out = out[-1L]
  list(lines = out, secrets = secrets)
}

#' Lines recorded per execution: gptr.doc_output_lines when set, else setting doc$output_lines
#' @noRd
doc_max_output_lines = function() {
  opt = getOption("gptr.doc_output_lines")
  if (!is.null(opt)) return(as.integer(opt))
  doc = tryCatch(setting_get("doc", default = list()), error = function(e) list())
  as.integer((if (is.list(doc)) doc$output_lines) %||% gptr_opt("doc_output_lines"))
}

#' Printed output (a character vector, or P09's list of output per top-level expression) as
#' `#> ` lines of at most 76 characters, then `#> ... (N more lines)`
#' @noRd
doc_output_lines = function(outputs, max_lines = NULL, width = 76L) {
  out = as.character(unlist(outputs, use.names = FALSE))
  out = unlist(strsplit(as_utf8(out), "\n", fixed = TRUE), use.names = FALSE)
  if (!length(out)) return(character())
  max_lines = max_lines %||% doc_max_output_lines()
  extra = length(out) - max_lines
  if (extra > 0L) out = out[seq_len(max_lines)]
  out = paste0("#> ", substr(out, 1L, width))
  if (extra > 0L) out = c(out, paste0("#> ... (", as.integer(extra), " more lines)"))
  out
}

#' Wrap body lines for an overlay fork or a team child (IC-46, IC-47); the block id is filled in
#' when the block is written (doc_block_token)
#' @noRd
doc_wrap_local = function(body, child = NULL) {
  if (!length(body)) return(character())
  target = if (is.null(child)) {
    paste0("gptr_resume(block = \"", doc_block_token, "\")")
  } else {
    paste0("gptr_resume(block = \"", doc_block_token, "\", child = \"", child, "\")")
  }
  c("local({", ifelse(nzchar(body), paste0("  ", body), body), paste0("}, envir = ", target,
                                                                      "$envir)"))
}

#' Entries on the active branch of a session, root first (the leaf's parent chain)
#' @noRd
doc_path_entries = function(session) {
  d = session_data(session)
  ents = d$entries
  if (!length(ents)) return(list())
  ids = vapply(ents, function(e) as.character(e$id %||% NA_character_), "")
  parents = vapply(ents, function(e) as.character(e$parent_id %||% NA_character_), "")
  cur = d$leaf %||% ids[length(ids)]
  idx = integer()
  while (length(cur) == 1L && !is.na(cur) && nzchar(cur)) {
    k = match(cur, ids)
    if (is.na(k) || k %in% idx) break
    idx = c(k, idx)
    cur = parents[k]
  }
  ents[idx]
}

#' The prompt turn of a user-message entry: P06's `gptr$turn` stamp, else counted
#' @noRd
doc_entry_turn = function(e, previous) {
  t = suppressWarnings(as.integer(e$gptr$turn %||% NA_integer_))
  if (!is.na(t)) return(t)
  src = e$message$source %||% "prompt"
  if (src %in% c("steer", "follow_up", "extension", "agent")) previous else previous + 1L
}

#' Entries of prompt turn `turn` on the active branch (from its first user message to the entry
#' before the next turn's first user message)
#' @noRd
doc_turn_entries = function(session, turn) {
  ents = doc_path_entries(session)
  start = NA_integer_
  end = length(ents)
  prev = 0L
  for (i in seq_along(ents)) {
    e = ents[[i]]
    if (!identical(e$type, "message") || !identical(e$message$role, "user")) next
    t = doc_entry_turn(e, prev)
    if (is.na(start) && identical(t, as.integer(turn))) start = i
    if (!is.na(start) && t > turn) {
      end = i - 1L
      break
    }
    prev = t
  }
  if (is.na(start)) return(list())
  ents[start:end]
}

#' Child sessions created during a turn (after the turn's first message), in creation order
#' (block-nested replay, IC-47)
#' @noRd
doc_turn_children = function(session, ents) {
  kids = session_data(session)$children
  if (!length(kids) || !length(ents)) return(list())
  first = ents[[1L]]$message$timestamp
  t0 = if (is.numeric(first)) first / 1000 - 0.001 else -Inf
  created = vapply(kids, function(k) as.numeric(session_data(k)$created %||% 0), 0)
  keep = which(created >= t0)
  kids[keep[order(created[keep], method = "radix")]]
}

#' S2 parts of the children a turn created (IC-47): the k-th direct gptr() call of the block body
#' (not inside a loop, function or braces) owns part "n<k>" and the first unused child whose first
#' prompt has that call's prompt hash; a computed or interpolated prompt takes the next unused
#' child that no literal call claims. Children of deeper calls get no part (those calls run live
#' on re-source). `sent` (the child's prompt hash) lets replay check the call it answers.
#' @noRd
doc_nested_parts = function(body, kids) {
  out = list()
  if (!length(kids) || !length(body)) return(out)
  calls = doc_calls(as.character(body))
  direct = calls[!calls$nested, , drop = FALSE]
  if (!nrow(direct)) return(out)
  sent = vapply(kids, function(k) {
    for (e in doc_path_entries(k)) {
      if (identical(e$type, "message") && identical(e$message$role, "user")) {
        return(prompt_hash(msg_text(e$message)))
      }
    }
    NA_character_
  }, "", USE.NAMES = FALSE)
  literal = direct$ph[!is.na(direct$ph)]
  used = logical(length(kids))
  for (k in seq_len(nrow(direct))) {
    ph = direct$ph[k]
    hit = if (is.na(ph)) integer() else which(!used & sent %in% ph)
    if (!length(hit)) hit = which(!used & !is.na(sent) & !(sent %in% literal))
    if (!length(hit)) next
    i = hit[1L]
    used[i] = TRUE
    cd = session_data(kids[[i]])
    out[[paste0("n", k)]] = list(text = cd$last_text %||% NA_character_, session = cd$id,
                                 model = cd$model, turn = cd$turns %||% 1L, sent = sent[i])
  }
  out
}

#' Body lines, value, plan facts, last assistant message, tokens and cost of one turn
#' @noRd
doc_turn_body = function(ents, with_out = TRUE, plan_mode = FALSE) {
  results = list()
  for (e in ents) {
    m = if (identical(e$type, "message")) e$message else NULL
    if (!is.null(m) && identical(m$role, "tool_result")) results[[m$tool_call_id]] = m
  }
  out = list(body = character(), secrets = FALSE, value = NULL, plan_path = NULL,
             plan_from = NULL, last = NULL, tokens = c(0, 0), cost = 0)
  for (i in seq_along(ents)) {
    e = ents[[i]]
    m = e$message
    if (identical(e$type, "custom_message") && identical(m$kind, "steer_relay")) {
      out$body = c(out$body, paste0("## Steer: ", doc_one_line(m$origin_text %||% "")))
    } else if (identical(e$type, "message") && identical(m$role, "user")) {
      for (blk in m$content) {
        if (identical(blk$type, "context") && identical(blk$kind, "plan")) {
          out$plan_from = blk$attrs$from %||% out$plan_from
        }
      }
      if (i == 1L) next
      src = m$source %||% "prompt"
      if (identical(src, "follow_up")) {
        out$body = c(out$body, paste0("## Follow-up: ", doc_one_line(msg_text(m))))
      } else if (identical(src, "steer")) {
        out$body = c(out$body, paste0("## Steer: ", doc_one_line(msg_text(m))))
      }
    } else if (identical(e$type, "message") && identical(m$role, "assistant")) {
      out = doc_turn_assistant(out, m, results, with_out, plan_mode)
    } else if (identical(e$type, "custom")) {
      ct = e$custom_type %||% ""
      if (identical(ct, "gptr.value") && !is.null(e$data$name) &&
          !identical(e$data$mode, "box")) {
        out$value = e$data$name
      }
      if (identical(ct, "gptr.plan")) out$plan_path = e$data$path %||% out$plan_path
    }
  }
  out
}

#' Add one assistant message (its successful recorded r calls) to a turn body
#' @noRd
doc_turn_assistant = function(out, m, results, with_out, plan_mode) {
  out$last = m
  u = m$usage
  if (!is.null(u)) {
    tin = sum(unlist(u[c("input", "cache_read", "cache_write_5m", "cache_write_1h")]),
              na.rm = TRUE)
    out$tokens = out$tokens + c(tin, sum(u$output %||% 0, na.rm = TRUE))
    out$cost = out$cost + sum(u$cost$total %||% 0, na.rm = TRUE)
  }
  for (b in m$content) {
    if (!identical(b$type, "tool_call") || !identical(b$name, "r")) next
    res = results[[b$id]]
    if (is.null(res) || isTRUE(res$is_error)) next
    det = res$details %||% list()
    if (!identical(det$status %||% "ok", "ok")) next
    if (!is.null(det$value)) out$value = det$value
    if (plan_mode || isFALSE(det$record) || isFALSE(b$arguments$record)) next
    chunk = doc_code_clean(det$code %||% b$arguments$code %||% "")
    kept = attr(chunk, "kept")
    chunk = as.character(chunk)
    safe = doc_history_code(chunk)
    hist = safe$lines
    if (safe$secrets) out$secrets = TRUE
    outs = det$outputs
    if (is.list(outs) && length(kept) && length(outs) == length(kept)) outs = outs[kept]
    lines = hist
    if (with_out) lines = c(lines, doc_output_lines(outs))
    if (length(det$bridge)) {
      dig = as_utf8(as.character(det$bridge))
      lines = c(lines, ifelse(startsWith(dig, "#>"), dig, paste0("#> ", dig)))
    }
    if (length(det$artifacts)) {
      art = as_utf8(as.character(det$artifacts))
      tag = ifelse(basename(art) == "app.R", "#> [app] ", "#> [plot] ")
      lines = c(lines, paste0(tag, art))
    }
    note = det$note %||% b$arguments$note
    if (length(note) && nzchar(doc_one_line(note))) {
      lines = c(lines, paste0("## Decision: ", doc_one_line(note)))
    }
    out$body = c(out$body, lines)
  }
  out
}

#' Recorded code of every turn of a (child) session, without outputs or comments (team blocks)
#' @noRd
doc_session_code = function(session) {
  code = character()
  for (k in seq_len(session_data(session)$turns %||% 0L)) {
    tb = doc_turn_body(doc_turn_entries(session, k), with_out = FALSE)
    code = c(code, tb$body[!grepl("^#", tb$body)])
  }
  code
}

#' Header facts common to every block
#' @noRd
doc_header_common = function(site, call_ordinal, model) {
  list(model = model, date = format(Sys.Date(), "%Y-%m-%d"),
       prompt = site$prompt_hash %||% prompt_hash(site$template %||% ""),
       call = if (isTRUE(call_ordinal > 1L)) as.integer(call_ordinal) else NULL,
       args = site$args_hash)
}

#' The lines of the block of a session turn (contract 7.15): chr with attributes `header` (named
#' list of 11.5 keys), `session`, `answer` (final text) and `children` (S2 parts to cache)
#' @noRd
doc_block_lines = function(session, turn, site, call_ordinal) {
  d = session_data(session)
  if (d$kind %in% c("team", "fanout")) return(doc_team_block_lines(session, site, call_ordinal))
  ents = doc_turn_entries(session, turn)
  fmt = site$format %||% "r"
  doc_set = tryCatch(setting_get("doc", default = list()), error = function(e) list())
  with_out = !fmt %in% c("rmd", "qmd") && !isFALSE(if (is.list(doc_set)) doc_set$outputs)
  plan_mode = identical(d$mode, "plan")
  tb = doc_turn_body(ents, with_out = with_out, plan_mode = plan_mode)
  body = tb$body
  if (plan_mode) body = paste0("## Plan: ", tb$plan_path %||% "none")
  if (tb$secrets) body = c(doc_secret_flag, body)
  fork = NULL
  if (!is.null(d$fork_of)) {
    fork = paste0(d$fork_of$id, ":", d$fork_of$turn %||% 0L)
    if (startsWith(d$home_label %||% "", "overlay of")) body = doc_wrap_local(body)
  }
  body = redact(body, "persist")
  last = tb$last
  model = if (!is.null(last)) paste0(last$provider, "/", last$model) else d$model
  header = doc_header_common(site, call_ordinal, model)
  if (any(tb$tokens > 0)) header$tokens = paste0(round(tb$tokens[1L]), "/", round(tb$tokens[2L]))
  if (tb$cost > 0) header$cost = format(round(tb$cost, 4L), scientific = FALSE)
  header$session = d$id
  header$turn = as.integer(turn)
  header$value = tb$value
  header$fork = fork
  header$plan = tb$plan_from
  children = doc_nested_parts(body, doc_turn_children(session, ents))
  answer = if (!is.null(last)) msg_text(last) else NA_character_
  structure(as.character(body), header = header, session = session, answer = answer,
            children = children)
}

#' The lines of a team or fan-out block (IC-47): one `## Agent` line per child in name order;
#' children with exports get their code in a child overlay plus one assignment per export
#' @noRd
doc_team_block_lines = function(team, site, call_ordinal) {
  d = session_data(team)
  kids = d$children
  nms = sort(names(kids), method = "radix")
  body = character()
  children = list()
  ids = character()
  for (nm in nms) {
    cd = session_data(kids[[nm]])
    txt = cd$last_text %||% NA_character_
    first = if (length(txt) && !is.na(txt[1L])) {
      strsplit(as_utf8(txt[1L]), "\n", fixed = TRUE)[[1L]][1L]
    } else {
      ""
    }
    body = c(body, paste0("## Agent ", nm, " (", cd$model, "): ", doc_one_line(first %||% "")))
    exports = as.character(cd$exports %||% character())
    if (length(exports)) {
      body = c(body, doc_wrap_local(doc_session_code(kids[[nm]]), child = nm))
      body = c(body, paste0(exports, " = gptr_resume(block = \"", doc_block_token,
                            "\", child = \"", nm, "\")$envir$", exports))
    }
    children[[nm]] = list(text = paste(txt, collapse = "\n"), session = cd$id, model = cd$model,
                          turn = cd$turns %||% 1L)
    ids = c(ids, cd$id)
  }
  model = if (length(nms)) session_data(kids[[nms[1L]]])$model else d$model
  header = doc_header_common(site, call_ordinal, model)
  header$session = d$id
  header$turn = 1L
  header$kind = d$kind
  header$children = paste0(nms, ":", ids, collapse = ",")
  structure(as.character(redact(body, "persist")), header = header, session = team,
            answer = d$last_text %||% NA_character_, children = children)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 138 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-blocks.R tests/testthat/test-doc-blocks.R
git commit -m "feat(doc): render the recorded block of a session turn"
```

---

### Task 4: Raw document I/O, locks and the user-level project file

**Files:**
- Create: `R/doc-io.R`
- Create: `tests/testthat/fixtures/docs/crlf-bom.R`, `tests/testthat/fixtures/docs/crlf-bom.expected.R`
- Test: `tests/testthat/test-doc-io.R` (create)

**Interfaces:**
- Consumes: Task 2 `doc_state()`; (P01, 04 §7.1) `the`, `as_utf8()`, `utf8_mark(x)`, `read_utf8(path)` (`$text`), `write_atomic(path,
  content)` (temp file + rename with retries and an md5-checked in-place fallback, IC-51), `path_norm()`,
  `path_key()`, `path_rel(path, root = project_root())`, `project_root()`, `workspace_root(create = TRUE)`,
  `gptr_user_dir(which, create = FALSE)`, `hash_sha256()`, `json_decode()`, `gptr_abort()`; P04 `pid_alive(pid,
  create_time = NULL)` (`create_time` in seconds since the epoch); P08 (kernel SDK) `settings_write(scope, patch)`
  with scope `"user_project"` (the user-level project file of IC-52, under P08's short lock); `cli::hash_sha1()`,
  `ps::ps_create_time()`, `tools::md5sum()`.
- Produces: the `gptr_source()` frame stack `doc_source_push(path)`,
  `doc_source_pop(depth)`, `doc_source_log(path, block_id, action)`; paths `doc_root()` (the workspace root, never
  created by a read), `doc_rel(path)`, `doc_abs(path)`, `doc_format_of(path)` -> `"r"`, `"rmd"`, `"qmd"`,
  `"ipynb"` or `NULL`; raw I/O `doc_read(path)` -> `gptr_doc_text` `list(path, lines, eol, bom, final_nl, md5)`
  (signals `gptr_error_doc_write` with `reason` `"missing"` or `"encoding"`), `doc_read_or_new(path)`,
  `doc_serialize(lines, eol, bom, final_nl)`, `doc_write(doc, lines, check = TRUE)` (signals
  `gptr_error_doc_write` with `reason = "conflict"` when the md5 changed); locks `doc_create_time()`,
  `doc_lock_stamp()`, `doc_lock_stale(dir)`, `doc_lock_acquire(dir, tries = 10L)`, `doc_lock_dir(path)`,
  `doc_lock(path)` -> `list(dir, own)` or `NULL`, `doc_unlock(lock)`, `doc_lock_hold(path)`,
  `doc_lock_release_all()`; the user-level project file `doc_project_file()`, `doc_project_get()`,
  `doc_project_remember(rel, answer)`, `doc_project_transcript(target)`.

Adapted from report 14 §5.0 (`doc_read`, `doc_write`, `doc_serialize`: read raw bytes, strip and remember the BOM,
detect CRLF, remember the final newline, write back identically) and §4.3 (locks: an atomic `dir.create()` per
document; P15 adds the pid and process creation time so a lock of a dead process is broken at once, IC-71). Writes
go through P01's `write_atomic()`, which retries `file.rename()` and falls back to an md5-checked in-place write
(IC-51). The verification log of report 14 re-ran the CRLF/BOM prototype (item 31).

- [ ] **Step 1: Write the failing test**

Create the two fixtures: save this code to a scratch file outside the repository (for example
`$TMPDIR/p15-fixtures-4.R`) and run `Rscript --vanilla "$TMPDIR/p15-fixtures-4.R"` from the repository root:

```r
# Fixtures of P15 Task 4 (run from the repository root): CRLF line ends, a UTF-8 byte-order mark
# and no final newline, before and after one block is inserted below the call
dir = file.path("tests", "testthat", "fixtures", "docs")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
bom = as.raw(c(0xef, 0xbb, 0xbf))
call = "gptr(\"hi \u00e9t\u00e9\")"
writeBin(c(bom, charToRaw(paste0("x = 1\r\n", call, "\r\ny = 2"))),
         file.path(dir, "crlf-bom.R"))
writeBin(c(bom, charToRaw(paste0("x = 1\r\n", call, "\r\n# >>> gptr:abc123 model=m\r\n",
                                 "z = 3\r\n# <<< gptr:abc123\r\ny = 2"))),
         file.path(dir, "crlf-bom.expected.R"))
```

Create `tests/testthat/test-doc-io.R`:

```r
# Tests for R/doc-io.R (plan P15): raw I/O, locks, the user-level project file, deferred and
# pending writes, IDE backends.

test_that("CRLF, BOM and a missing final newline survive a read-modify-write", {
  local_project()
  f = file.path(getwd(), "crlf.R")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ngptr(\"hi\")\r\ny = 2")), f)
  doc = doc_read(f)
  expect_identical(doc$lines, c("x = 1", "gptr(\"hi\")", "y = 2"))
  expect_identical(doc$eol, "\r\n")
  expect_true(doc$bom)
  expect_false(doc$final_nl)
  doc_write(doc, append(doc$lines, c("# >>> gptr:abc123 model=m", "z = 3", "# <<< gptr:abc123"),
                        after = 2L))
  expect_identical(readBin(f, "raw", 200), c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(
    "x = 1\r\ngptr(\"hi\")\r\n# >>> gptr:abc123 model=m\r\nz = 3\r\n# <<< gptr:abc123\r\n",
    "y = 2"))))
  g = file.path(getwd(), "plain.R")
  writeLines(c("a", "b"), g)
  d2 = doc_read(g)
  expect_true(d2$final_nl)
  expect_false(d2$bom)
  doc_write(d2, d2$lines)
  expect_identical(readLines(g), c("a", "b"))
  expect_identical(doc_read_or_new(file.path(getwd(), "new.R"))$lines, character())
})

test_that("the byte fixtures round-trip exactly", {
  local_project()
  src = testthat::test_path("fixtures", "docs", "crlf-bom.R")
  f = file.path(getwd(), "crlf-bom.R")
  file.copy(src, f)
  doc = doc_read(f)
  doc_write(doc, append(doc$lines, c("# >>> gptr:abc123 model=m", "z = 3", "# <<< gptr:abc123"),
                        after = 2L))
  expected = testthat::test_path("fixtures", "docs", "crlf-bom.expected.R")
  expect_identical(readBin(f, "raw", 1000), readBin(expected, "raw", 1000))
})

test_that("a concurrent edit is detected by md5 and non-UTF-8 documents are refused", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  doc = doc_read(f)
  writeLines("x = 2", f)
  cnd = expect_error(doc_write(doc, "x = 3"), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "conflict")
  expect_identical(readLines(f), "x = 2")
  writeBin(as.raw(c(0x78, 0xe9, 0x0a)), f)
  expect_identical(expect_error(doc_read(f), class = "gptr_error_doc_write")$reason, "encoding")
  expect_identical(expect_error(doc_read("nope.R"), class = "gptr_error_doc_write")$reason,
                   "missing")
})

test_that("document locks exclude a live holder and break a dead one", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  lock = doc_lock(f)
  expect_true(lock$own)
  expect_true(file.exists(file.path(lock$dir, "pid")))
  expect_match(lock$dir, "[.]gptr/locks/[0-9a-f]{40}$")
  expect_null(doc_lock(f))
  doc_unlock(lock)
  expect_false(dir.exists(lock$dir))
  dir.create(lock$dir, recursive = TRUE)
  writeLines("999999999 1", file.path(lock$dir, "pid"))
  testthat::local_mocked_bindings(pid_alive = function(pid, create_time = NULL) FALSE)
  again = doc_lock(f)
  expect_true(again$own)
  doc_unlock(again)
})

test_that("a held lock is reused by this process and released at the end", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  withr::defer(doc_lock_release_all())
  expect_true(doc_lock_hold(f))
  l2 = doc_lock(f)
  expect_false(l2$own)
  doc_unlock(l2)
  expect_true(dir.exists(l2$dir))
  doc_lock_release_all()
  expect_false(dir.exists(l2$dir))
})

test_that("the user-level project file remembers record answers and the transcript target", {
  local_project()
  expect_identical(doc_project_get(), list())
  doc_project_remember("a.R", "auto")
  doc_project_remember("b.R", "off")
  doc_project_transcript(".gptr/transcripts/gptr-session-1.R")
  pf = doc_project_get()
  expect_identical(pf$record$a.R, "auto")
  expect_identical(pf$record$b.R, "off")
  expect_identical(pf$transcript$target, ".gptr/transcripts/gptr-session-1.R")
  expect_match(doc_project_file(), "projects/[0-9a-f]{16}[.]json$")
  expect_false(startsWith(doc_project_file(), getwd()))
})

test_that("paths, formats and the root are derived without writing anything", {
  root = local_project(gptr = FALSE)
  expect_identical(doc_format_of("x.Rmd"), "rmd")
  expect_identical(doc_format_of("x.R"), "r")
  expect_identical(doc_format_of("x.ipynb"), "ipynb")
  expect_null(doc_format_of("x.txt"))
  expect_null(doc_format_of(NULL))
  expect_identical(doc_rel(file.path(root, "sub", "a.R")), "sub/a.R")
  expect_identical(doc_abs("sub/a.R"), file.path(root, "sub", "a.R"))
  expect_identical(doc_root(), file.path(tempdir(), "gptr"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 0 ]`, starting with ``Error in `doc_read(f)`: could not find function "doc_read"``.

- [ ] **Step 3: Write the implementation**

Create `R/doc-io.R`:

```r
# doc-io.R -- document I/O (plan P15; contract 7.15, 11.1, 11.3, 11.9; IC-50, IC-51, IC-52): raw
# byte reads and atomic writes that keep the EOL, BOM and final newline, md5 conflict checks,
# document locks (pid + creation time), the user-level project file, deferred Rscript writes with
# a crash sidecar and their recovery, Jupyter pending blocks, and the rstudioapi/Positron edit
# backends. Layer L4. Adapted from report 14 section 5.0 (doc_read, doc_write, doc_serialize)
# and section 4.3 (backends, range arithmetic, locks).

#' Push a gptr_source() frame (document key, blocks to skip, action log); returns its depth
#' @noRd
doc_source_push = function(path) {
  st = doc_state()
  st$sources[[length(st$sources) + 1L]] = list(key = path_key(path), skip = character(),
                                               log = list())
  length(st$sources)
}

#' Pop gptr_source() frames down to `depth - 1`
#' @noRd
doc_source_pop = function(depth) {
  st = doc_state()
  st$sources = st$sources[seq_len(depth - 1L)]
  invisible(NULL)
}

#' Record a block action in the innermost gptr_source() frame when it sources `path`
#' @noRd
doc_source_log = function(path, block_id, action) {
  st = doc_state()
  n = length(st$sources)
  if (!n || is.null(block_id) || !identical(st$sources[[n]]$key, path_key(path))) {
    return(invisible(NULL))
  }
  fr = st$sources[[n]]
  fr$log[[block_id]] = action
  st$sources[[n]] = fr
  invisible(NULL)
}

#' The root of P15's files (cache/s2, cache/tmp sidecars, locks); never created by a read
#' @noRd
doc_root = function() {
  workspace_root(create = FALSE)
}

#' A document path relative to the project root when inside it, else absolute
#' @noRd
doc_rel = function(path) {
  if (is.null(path) || !length(path)) return(NA_character_)
  as.character(tryCatch(path_rel(path), error = function(e) path))
}

#' The absolute path of a document path stored relative to the project root
#' @noRd
doc_abs = function(path) {
  if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", path)) path_norm(path) else
    path_norm(file.path(project_root(), path))
}

#' Format name from a file extension: "r", "rmd", "qmd", "ipynb" or NULL
#' @noRd
doc_format_of = function(path) {
  if (is.null(path) || !length(path) || is.na(path[1L])) return(NULL)
  switch(tolower(tools::file_ext(path[1L])), r = "r", rmd = "rmd", qmd = "qmd", ipynb = "ipynb",
         NULL)
}

#' Read a document as lines, keeping its EOL, BOM, final newline and md5 (report 14 doc_read).
#' Signals gptr_error_doc_write (reason "missing" or "encoding").
#' @noRd
doc_read = function(path) {
  full = path_norm(path)
  size = file.info(full)$size
  if (is.na(size)) {
    gptr_abort(paste0("Document not found: ", full), "doc_write", path = full, reason = "missing")
  }
  raw = if (size > 0) readBin(full, "raw", n = size) else raw()
  bom = length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  if (bom) raw = raw[-(1:3)]
  txt = rawToChar(raw)
  Encoding(txt) = "UTF-8"
  if (!validUTF8(txt)) {
    gptr_abort(paste0("The document is not valid UTF-8: ", full), "doc_write", path = full,
               reason = "encoding")
  }
  eol = if (grepl("\r\n", txt, fixed = TRUE)) "\r\n" else "\n"
  final_nl = !nzchar(txt) || endsWith(txt, "\n")
  lines = character()
  if (nzchar(txt)) {
    l = strsplit(paste0(txt, "\001"), "\r?\n")[[1L]]
    l[length(l)] = sub("\001$", "", l[length(l)])
    lines = if (final_nl) l[-length(l)] else l
  }
  structure(list(path = full, lines = utf8_mark(lines), eol = eol, bom = bom, final_nl = final_nl,
                 md5 = unname(tools::md5sum(full))), class = "gptr_doc_text")
}

#' An empty document record for a file that does not exist yet (transcripts)
#' @noRd
doc_read_or_new = function(path) {
  if (file.exists(path)) return(doc_read(path))
  structure(list(path = path_norm(path), lines = character(), eol = "\n", bom = FALSE,
                 final_nl = TRUE, md5 = NA_character_), class = "gptr_doc_text")
}

#' Serialise lines to bytes with the document's EOL, BOM and final newline
#' @noRd
doc_serialize = function(lines, eol = "\n", bom = FALSE, final_nl = TRUE) {
  txt = paste(as_utf8(as.character(lines)), collapse = eol)
  if (final_nl && length(lines)) txt = paste0(txt, eol)
  r = charToRaw(as_utf8(txt))
  if (bom) r = c(as.raw(c(0xef, 0xbb, 0xbf)), r)
  r
}

#' Atomic write with an md5 conflict check (report 14 doc_write; write_atomic() of P01 retries
#' the rename and falls back to an in-place write, IC-51). Signals gptr_error_doc_write with
#' reason "conflict" when the file changed since `doc` was read.
#' @noRd
doc_write = function(doc, lines, check = TRUE) {
  path = doc$path
  if (check) {
    now = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
    if (!identical(now, doc$md5)) {
      gptr_abort(paste0("The document changed on disk since it was read: ", path), "doc_write",
                 path = path, reason = "conflict")
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_atomic(path, doc_serialize(lines, doc$eol, doc$bom, doc$final_nl))
  doc$lines = lines
  doc$md5 = unname(tools::md5sum(path))
  invisible(doc)
}

#' Creation time of this R process in seconds since the epoch (pid-reuse guard, IC-71)
#' @noRd
doc_create_time = function() {
  tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA_real_)
}

#' "<pid> <process creation time>" of this process (IC-71)
#' @noRd
doc_lock_stamp = function() {
  paste(Sys.getpid(), format(doc_create_time(), digits = 15))
}

#' Is a lock directory stale: its pid is dead (pid + creation time, P04's pid_alive()), or it
#' has had no pid file for 30 s (contract 11.1, IC-71)
#' @noRd
doc_lock_stale = function(dir) {
  pf = file.path(dir, "pid")
  if (!file.exists(pf)) {
    age = as.numeric(difftime(Sys.time(), file.info(dir)$mtime, units = "secs"))
    return(is.na(age) || age > 30)
  }
  parts = strsplit(trimws(read_utf8(pf)$text), " ", fixed = TRUE)[[1L]]
  pid = suppressWarnings(as.integer(parts[1L]))
  ct = suppressWarnings(as.numeric(parts[2L]))
  if (is.na(pid)) return(TRUE)
  !isTRUE(tryCatch(pid_alive(pid, create_time = if (is.na(ct)) NULL else ct),
                   error = function(e) FALSE))
}

#' Take a mkdir lock; NULL when another live process holds it after `tries` x 100 ms
#' @noRd
doc_lock_acquire = function(dir, tries = 10L) {
  dir.create(dirname(dir), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(tries)) {
    if (dir.create(dir, showWarnings = FALSE)) {
      write_atomic(file.path(dir, "pid"), doc_lock_stamp())
      return(dir)
    }
    if (doc_lock_stale(dir)) {
      unlink(dir, recursive = TRUE, force = TRUE)
      next
    }
    Sys.sleep(0.1)
  }
  NULL
}

#' The lock directory of a document: `<root>/locks/<sha1 of path_key>` (contract 11.1)
#' @noRd
doc_lock_dir = function(path) {
  file.path(workspace_root(), "locks", cli::hash_sha1(path_key(path)))
}

#' Lock a document for one write: list(dir, own) or NULL; a lock this process holds for its
#' deferred writes is reused (own = FALSE, so doc_unlock() keeps it)
#' @noRd
doc_lock = function(path) {
  key = path_key(path)
  st = doc_state()
  if (!is.null(st$held[[key]])) return(list(dir = st$held[[key]], own = FALSE))
  dir = doc_lock_acquire(doc_lock_dir(path))
  if (is.null(dir)) NULL else list(dir = dir, own = TRUE)
}

#' Release a lock taken by doc_lock()
#' @noRd
doc_unlock = function(lock) {
  if (!is.null(lock) && isTRUE(lock$own)) unlink(lock$dir, recursive = TRUE, force = TRUE)
  invisible(NULL)
}

#' Hold a document's lock until this process exits (deferred Rscript writes, IC-51): FALSE when
#' another live process holds it (array jobs)
#' @noRd
doc_lock_hold = function(path) {
  key = path_key(path)
  st = doc_state()
  if (!is.null(st$held[[key]])) return(TRUE)
  dir = doc_lock_acquire(doc_lock_dir(path))
  if (is.null(dir)) return(FALSE)
  st$held[[key]] = dir
  TRUE
}

#' Release the locks held for deferred writes
#' @noRd
doc_lock_release_all = function() {
  st = doc_state()
  for (dir in st$held) unlink(dir, recursive = TRUE, force = TRUE)
  st$held = list()
  invisible(NULL)
}

#' Path of the user-level project file (contract 11.3, IC-52)
#' @noRd
doc_project_file = function() {
  file.path(gptr_user_dir("config"), "projects",
            paste0(substr(hash_sha256(path_key(project_root())), 1L, 16L), ".json"))
}

#' The user-level project file as a named list (empty when absent or unreadable)
#' @noRd
doc_project_get = function() {
  f = doc_project_file()
  if (!file.exists(f)) return(list())
  x = tryCatch(json_decode(read_utf8(f)$text), error = function(e) list())
  if (is.list(x)) x else list()
}

#' Remember a per-document record answer ("auto" or "off") in the user-level project file
#' @noRd
doc_project_remember = function(rel, answer) {
  rec = doc_project_get()$record
  if (!is.list(rec)) rec = list()
  rec[[rel]] = answer
  settings_write("user_project", list(record = rec))
  invisible(answer)
}

#' Remember the console transcript target ("off" or a project-relative path)
#' @noRd
doc_project_transcript = function(target) {
  settings_write("user_project", list(transcript = list(target = target)))
  invisible(target)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 41 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-io.R tests/testthat/test-doc-io.R tests/testthat/fixtures/docs/crlf-bom.R \
  tests/testthat/fixtures/docs/crlf-bom.expected.R
git commit -m "feat(doc): add byte-preserving document I/O, document locks and the project file"
```

---

### Task 5: The `r`, `rmd`, `qmd` and `transcript` formats and inert blocks

**Files:**
- Create: `R/doc-formats.R`
- Create: `tests/testthat/fixtures/docs/report.Rmd`, `report.expected.Rmd`, `report.qmd`, `report.expected.qmd`
- Test: `tests/testthat/test-doc-formats.R` (create)

**Interfaces:**
- Consumes: Tasks 1-2 (`doc_find_blocks()`, `doc_calls()`, `doc_match_anchor()`, `doc_run_owner()`,
  `doc_block_status()`, `doc_block_body()`, `doc_text_locate()`, `doc_render_block()`, `doc_indent_lines()`,
  `doc_splice()`, `doc_parse_kv()`, `doc_str_literal()`, `doc_re_open`); Task 4 (`doc_read()`, tests); P01
  `as_utf8()`, `gptr_abort()`.
- Produces: the `doc_format` functions of 04 §10.2 row 18 for the marker formats: `locate(text, site)` ->
  `doc_text_locate()`'s list, `render(block, site)` -> chr, `upsert(text, site, lines, block_id)` -> chr, `inert(lines)`
  -> chr; namely `doc_r_locate()`, `doc_r_render()`, `doc_r_upsert()`, `doc_rmd_locate()`,
  `doc_rmd_upsert_fn(style)` (`"rmd"` or `"qmd"`), `doc_transcript_locate()`, `doc_transcript_upsert()`,
  `doc_marker_inert()`; helpers `doc_rmd_chunks(lines)` -> df(`start`, `end`, `engine`, `label`, `prefix`, `fence`,
  `params`) (an unlabelled chunk gets knitr's default label `unnamed-chunk-<k>`, k counting the unlabelled chunks of
  every engine, so the label `knitr::opts_current$get("label")` reports while the chunk runs locates it; verified
  with knitr 1.51), `doc_rmd_calls(lines)`, `doc_rmd_append_chunk(text, code)`, `doc_rmd_chunk_eval(text, id, inert,
  style)`, `doc_inert_marker_lines(seg, inert = TRUE)`, `doc_console_statement(text, site)` (`s_<6 hex> =
  gptr(...)`, then `s_<6 hex> |> gptr(...)`, IC-49), `doc_transcript_header(text, site)`. A site handed to
  `upsert()` carries `anchor`, `prompt_hash`, `args_hash`, `path`, and for console turns `console = TRUE`,
  `session_id`, `session_file`, `template`, `context_labels`.

Adapted from report 14 §5.0 (`proto/rmd.R`: chunk scanning with fence lengths, agent chunks after the owning chunk,
the `{r gptr-<id>}` and `#| label: gptr-<id>` headers) and §3.4 (console transcripts), with the IC-49 statement form
and the G7 §3.8 inert grammar (`status=undone`, `#~ ` lines, `eval=FALSE` / `#| eval: false`). The report verified
that knitr and Quarto render documents changed this way (item 31) and that an Rmd agent chunk must not carry `#>`
lines, which render twice (§3.2).

- [ ] **Step 1: Write the failing test**

Create the four fixtures: save this code to a scratch file outside the repository (for example
`$TMPDIR/p15-fixtures-5.R`) and run `Rscript --vanilla "$TMPDIR/p15-fixtures-5.R"` from the repository root:

```r
# Fixtures of P15 Task 5 (run from the repository root): an R Markdown and a Quarto report before
# and after an agent chunk is added after the chunk that calls gptr()
dir = file.path("tests", "testthat", "fixtures", "docs")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
put = function(name, lines) {
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), file.path(dir, name))
}
rmd = c("---", "title: \"Report\"", "---", "", "```{r setup}", "x = 1", "```", "",
        "````{r ask}", "cat(\"```not a fence end```\\n\")",
        "gptr(\"count letters in this prompt\")", "````", "", "Some prose.")
put("report.Rmd", rmd)
put("report.expected.Rmd", c(
  rmd[1:12], "", "````{r gptr-3fdfa0}",
  "# >>> gptr:3fdfa0 model=fake/fake-1 date=2026-09-29 prompt=3848b6ef5cca",
  "n = nchar(\"count letters in this prompt\")", "n * 2", "## Decision: stub.",
  "# <<< gptr:3fdfa0", "````", rmd[13:14]))
qmd = c("---", "title: \"Report\"", "---", "", "```{r}", "#| label: ask",
        "gptr(\"count letters in this prompt\")", "```")
put("report.qmd", qmd)
put("report.expected.qmd", c(
  qmd, "", "```{r}", "#| label: gptr-9fbc33",
  "# >>> gptr:9fbc33 model=fake/fake-1 date=2026-09-29 prompt=3848b6ef5cca", "n = 1",
  "# <<< gptr:9fbc33", "```"))
```

Create `tests/testthat/test-doc-formats.R`:

```r
# Tests for R/doc-formats.R (plan P15): Rmd/qmd chunks, the r and transcript formats, inert
# blocks, the notebook serializer, the format registry and builtin:documents.

doc_fixture = function(name) testthat::test_path("fixtures", "docs", name)

doc_fixture_bytes = function(name) {
  f = doc_fixture(name)
  readBin(f, "raw", n = file.info(f)$size)
}

# A site anchored on the call with this prompt (as doc_locate() builds it)
doc_test_site = function(path, text, prompt, format) {
  calls = if (format %in% c("rmd", "qmd")) doc_rmd_calls(text) else doc_calls(text)
  k = which(calls$ph %in% prompt_hash(prompt))[1]
  list(kind = "srcref", path = path, format = format, backend = "file",
       anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = prompt_hash(prompt),
       args_hash = NULL, template = prompt)
}

test_that("Rmd chunks are parsed with labels, prefixes and long fences", {
  ch = doc_rmd_chunks(doc_read(doc_fixture("report.Rmd"))$lines)
  expect_identical(ch$label, c("setup", "ask"))
  expect_identical(ch$fence, c("```", "````"))
  expect_identical(ch$start, c(5L, 9L))
  expect_identical(ch$end, c(7L, 12L))
  calls = doc_rmd_calls(doc_read(doc_fixture("report.Rmd"))$lines)
  expect_identical(calls$line1, 11L)
  expect_identical(calls$label, "ask")
  # knitr labels unlabelled chunks unnamed-chunk-<k>, counting every engine
  un = doc_rmd_chunks(c("```{r}", "gptr(\"a\")", "```", "```{python}", "x = 1", "```",
                        "```{r named}", "y = 2", "```", "```{r, echo=FALSE}", "gptr(\"b\")", "```"))
  expect_identical(un$label, c("unnamed-chunk-1", "unnamed-chunk-2", "named", "unnamed-chunk-3"))
})

test_that("Rmd agent chunks follow the owning chunk and keep the fence", {
  text = doc_read(doc_fixture("report.Rmd"))$lines
  site = doc_test_site("report.Rmd", text, "count letters in this prompt", "rmd")
  loc = doc_rmd_locate(text, site)
  expect_true(loc$top_level)
  expect_null(loc$owned)
  upsert = doc_rmd_upsert_fn("rmd")
  rendered = doc_r_render(list(id = "3fdfa0", header = list(
    model = "fake/fake-1", date = "2026-09-29",
    prompt = prompt_hash("count letters in this prompt")),
    body = c("n = nchar(\"count letters in this prompt\")", "n * 2", "## Decision: stub.")), site)
  new = upsert(text, site, rendered, "3fdfa0")
  expect_identical(new, doc_read(doc_fixture("report.expected.Rmd"))$lines)
  loc2 = doc_rmd_locate(new, site)
  expect_identical(loc2$owned$id, "3fdfa0")
  expect_identical(loc2$owned$status, "fresh")
  expect_identical(upsert(new, site, rendered, "3fdfa0"), new)
})

test_that("the same prompt in two chunks is anchored within its own chunk", {
  text = c("```{r one}", "gptr(\"same\")", "```", "", "```{r two}", "gptr(\"same\")", "```")
  calls = doc_rmd_calls(text)
  a = doc_anchor_of(calls, calls[2, ])
  expect_identical(a$label, "two")
  expect_identical(a$j, 1L)
  expect_identical(doc_match_anchor(calls, a)$line1, 6L)
})

test_that("qmd agent chunks carry a #| label line", {
  text = doc_read(doc_fixture("report.qmd"))$lines
  site = doc_test_site("report.qmd", text, "count letters in this prompt", "qmd")
  rendered = doc_r_render(list(id = "9fbc33", header = list(
    model = "fake/fake-1", date = "2026-09-29",
    prompt = prompt_hash("count letters in this prompt")),
    body = "n = 1"), site)
  new = doc_rmd_upsert_fn("qmd")(text, site, rendered, "9fbc33")
  expect_identical(new, doc_read(doc_fixture("report.expected.qmd"))$lines)
  expect_identical(doc_rmd_chunks(new)$label[2], "gptr-9fbc33")
})

test_that("the r format inserts below the statement with its indentation and replaces by id", {
  text = c("f = 1", "  gptr(\"count rows\")", "z = 2")
  site = doc_test_site("a.R", text, "count rows", "r")
  block = doc_render_block("abc123", list(model = "m"), "n = 1")
  new = doc_r_upsert(text, site, block, "abc123")
  expect_identical(new, c("f = 1", "  gptr(\"count rows\")", "  # >>> gptr:abc123 model=m",
                          "  n = 1", "  # <<< gptr:abc123", "z = 2"))
  again = doc_r_upsert(new, site, doc_render_block("abc123", list(model = "m"), "n = 2"), "abc123")
  expect_identical(again[4], "  n = 2")
  expect_error(doc_r_upsert(c("x = 1"), site, block, "def456"), class = "gptr_error_doc_write")
  bad = c("gptr(\"count rows\")", "# >>> gptr:aaaaaa model=m")
  expect_error(doc_r_upsert(bad, site, block, "abc123"), class = "gptr_error_doc_write")
})

test_that("undone blocks become inert in R, Rmd and qmd and can be revived", {
  body = c("x = 1", "y = 2")
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  dead = doc_inert_marker_lines(seg, TRUE)
  expect_identical(dead, c(paste0("# >>> gptr:abc123 model=m prompt=p sha=", doc_body_sha(body),
                                  " status=undone"), "#~ x = 1", "#~ y = 2", "# <<< gptr:abc123"))
  expect_identical(doc_inert_marker_lines(dead, FALSE), seg)
  expect_identical(doc_marker_inert(seg), dead)
  rmd = doc_read(doc_fixture("report.expected.Rmd"))$lines
  rmd_dead = doc_rmd_chunk_eval(rmd, "3fdfa0", TRUE, "rmd")
  expect_true("````{r gptr-3fdfa0, eval=FALSE}" %in% rmd_dead)
  expect_identical(doc_rmd_chunk_eval(rmd_dead, "3fdfa0", FALSE, "rmd"), rmd)
  qmd = doc_read(doc_fixture("report.expected.qmd"))$lines
  qmd_dead = doc_rmd_chunk_eval(qmd, "9fbc33", TRUE, "qmd")
  expect_true("#| eval: false" %in% qmd_dead)
  expect_identical(doc_rmd_chunk_eval(qmd_dead, "9fbc33", FALSE, "qmd"), qmd)
})

test_that("console transcripts record the first prompt as an assignment and later ones as pipes", {
  site = list(console = TRUE, session_id = "sab12cd3456", template = "fit mpg on weight",
              session_file = ".gptr/sessions/20260929T183000_sab12cd3456.jsonl")
  block = doc_render_block("a1b2c3", list(model = "m", prompt = prompt_hash("fit mpg on weight")),
                           "fit = lm(mpg ~ wt, data = mtcars)")
  t1 = doc_transcript_upsert(character(), site, block, "a1b2c3")
  expect_match(t1[1], "^# gptr session sab12cd3456 -- started ")
  expect_identical(t1[2], "# machine log: .gptr/sessions/20260929T183000_sab12cd3456.jsonl")
  expect_identical(t1[5], "library(gptr)")
  expect_identical(t1[6:7], c("", "s_ab12cd = gptr(\"fit mpg on weight\")"))
  site2 = utils::modifyList(site, list(template = "add \"predictions\"\nnow",
                                       context_labels = "mtcars"))
  t2 = doc_transcript_upsert(t1, site2, doc_render_block("d4e5f6", list(model = "m"), "p = 1"),
                             "d4e5f6")
  expect_identical(t2[length(t1) + 2L],
                   "s_ab12cd |> gptr(\"add \\\"predictions\\\"\\nnow\", mtcars)")
  expect_identical(sum(grepl("^# gptr session", t2)), 1L)
  expect_identical(parse(text = t2, keep.source = FALSE)[[2]][[1]], as.name("="))
  expect_identical(doc_transcript_locate(t2, site)$insert_after, length(t2))
  rmd = doc_rmd_upsert_fn("rmd")(c("# Notes"), site, block, "a1b2c3")
  expect_identical(rmd[1:6], c("# Notes", "", "```{r}", "s_ab12cd = gptr(\"fit mpg on weight\")",
                               "```", ""))
  expect_identical(rmd[7], "```{r gptr-a1b2c3}")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`, starting with ``Error in `doc_rmd_chunks(doc_read(doc_fixture("report.Rmd"))$lines)`: could not find function "doc_rmd_chunks"``.

- [ ] **Step 3: Write the implementation**

Create `R/doc-formats.R`:

```r
# doc-formats.R -- document formats (plan P15; contract 7.15, 10.2 row 18, 11.5): `r`, `rmd`,
# `qmd`, `ipynb` (gptr's own nbformat serializer) and `transcript` as `doc_format` specs, inert
# (undone) blocks, and builtin:documents (formats, the `document` route, the `documents` prompt
# section, the agent_end/session_tree hooks, the handlers of P14's console:command and
# console:direct channels and the doc.* services; IC-34, IC-47, IC-68).
# Layer L4. The Rmd/qmd chunk functions and the notebook serializer are report 14 section 5.0
# (proto/rmd.R; proto/ipynb.R with the verifier's corrected json_num()).

doc_rmd_begin = "^([\t >]*)(`{3,})\\s*\\{([a-zA-Z0-9_]+)( *[ ,].*)?\\}\\s*$"
doc_rmd_end = "^([\t >]*)(`{3,})\\s*$"

#' Chunk label from an Rmd chunk header's option string
#' @noRd
doc_rmd_header_label = function(params) {
  if (!nzchar(params)) return(NULL)
  first = trimws(strsplit(params, ",", fixed = TRUE)[[1L]][1L])
  if (grepl("=", first, fixed = TRUE)) {
    m = regmatches(params, regexec("label\\s*=\\s*['\"]([^'\"]+)['\"]", params))[[1L]]
    return(if (length(m)) m[2L] else NULL)
  }
  gsub("^['\"]|['\"]$", "", first)
}

#' Code chunks of an Rmd/qmd text: df(start, end, engine, label, prefix, fence, params); fence
#' lengths are tracked and YAML front matter is skipped. A chunk without a label gets knitr's
#' default `unnamed-chunk-<k>` (k counts the unlabelled chunks of every engine, as knitr does), so
#' the label knitr reports for the running chunk finds it.
#' @noRd
doc_rmd_chunks = function(lines) {
  lines = as_utf8(as.character(lines))
  n = length(lines)
  i = 1L
  if (n && grepl("^---\\s*$", lines[1L])) {
    j = which(grepl("^(---|\\.\\.\\.)\\s*$", lines))[-1L]
    if (length(j)) i = j[1L] + 1L
  }
  res = list()
  unnamed = 0L
  while (i <= n) {
    m = regmatches(lines[i], regexec(doc_rmd_begin, lines[i]))[[1L]]
    if (!length(m)) {
      i = i + 1L
      next
    }
    fence = m[3L]
    j = i + 1L
    while (j <= n) {
      e = regmatches(lines[j], regexec(doc_rmd_end, lines[j]))[[1L]]
      if (length(e) && nchar(e[3L]) >= nchar(fence)) break
      j = j + 1L
    }
    params = trimws(sub("^[ ,]*", "", m[5L]))
    body = if (j - i > 1L) lines[(i + 1L):(j - 1L)] else character()
    label = doc_rmd_header_label(params)
    yl = grep("^#\\|\\s*label:\\s*", body, value = TRUE)
    if (length(yl)) label = trimws(sub("^#\\|\\s*label:\\s*", "", yl[1L]))
    if (is.null(label) || !nzchar(label)) {
      unnamed = unnamed + 1L
      label = paste0("unnamed-chunk-", unnamed)
    }
    res[[length(res) + 1L]] = data.frame(start = i, end = j, engine = m[4L],
                                         label = label %||% NA_character_, prefix = m[2L],
                                         fence = fence, params = params,
                                         stringsAsFactors = FALSE)
    i = j + 1L
  }
  if (!length(res)) {
    return(data.frame(start = integer(), end = integer(), engine = character(),
                      label = character(), prefix = character(), fence = character(),
                      params = character(), stringsAsFactors = FALSE))
  }
  do.call(rbind, res)
}

#' gptr() calls of the R chunks of an Rmd/qmd text, with document line numbers, chunk index and
#' label; attributes `blocks` (marker blocks) and `chunks`
#' @noRd
doc_rmd_calls = function(lines) {
  ch = doc_rmd_chunks(lines)
  blocks = doc_find_blocks(lines)
  out = list()
  for (k in seq_len(nrow(ch))) {
    if (!ch$engine[k] %in% c("r", "R") || ch$end[k] - ch$start[k] < 2L) next
    body = lines[(ch$start[k] + 1L):(ch$end[k] - 1L)]
    calls = doc_calls(body)
    if (!nrow(calls)) next
    shift = ch$start[k]
    calls$line1 = calls$line1 + shift
    calls$line2 = calls$line2 + shift
    calls$stmt1 = calls$stmt1 + shift
    calls$stmt2 = calls$stmt2 + shift
    calls$chunk = rep(k, nrow(calls))
    calls$label = rep(ch$label[k], nrow(calls))
    out[[length(out) + 1L]] = calls
  }
  res = if (length(out)) {
    do.call(rbind, out)
  } else {
    empty = doc_calls(character())
    empty$chunk = integer()
    empty$label = character()
    empty
  }
  attr(res, "blocks") = blocks
  attr(res, "chunks") = ch
  res
}

#' Lines strictly between two line numbers
#' @noRd
doc_lines_between = function(text, a, b) {
  if (b - a < 2L) character() else text[(a + 1L):(b - 1L)]
}

#' The rmd/qmd formats' locate(): the calling chunk and the agent chunks after it
#' @noRd
doc_rmd_locate = function(text, site) {
  calls = doc_rmd_calls(text)
  ch = attr(calls, "chunks")
  blocks = attr(calls, "blocks")
  out = list(stmt = NULL, blocks = blocks[0L, , drop = FALSE], hit = NULL, owned = NULL,
             insert_after = NULL, top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "")
  hit = doc_match_anchor(calls, site$anchor)
  if (is.null(hit)) return(out)
  out$hit = hit
  out$stmt = c(hit$stmt1, hit$stmt2)
  if (isTRUE(hit$nested)) return(out)
  if (!is.na(hit$block)) {
    out$in_block = hit$block
    out$ordinal = hit$n_in_block
    return(out)
  }
  out$ordinal = hit$n_in_stmt
  out$top_level = TRUE
  k = hit$chunk
  last_end = ch$end[k]
  kk = k + 1L
  run = blocks[0L, , drop = FALSE]
  while (kk <= nrow(ch) && grepl("^gptr-", ch$label[kk] %||% "") &&
         all(!nzchar(trimws(doc_lines_between(text, last_end, ch$start[kk]))))) {
    run = rbind(run, blocks[blocks$start > ch$start[kk] & blocks$end < ch$end[kk], ,
                            drop = FALSE])
    last_end = ch$end[kk]
    kk = kk + 1L
  }
  out$blocks = run
  out$insert_after = last_end
  own = doc_run_owner(run$header, site$prompt_hash, hit$n_in_stmt, doc_same_ordinals(calls, hit))
  if (!is.null(own)) {
    b = run[own$index, , drop = FALSE]
    status = doc_block_status(b$header[[1L]], doc_block_body(text, b), site$prompt_hash,
                              site$args_hash)
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = b$id, header = b$header[[1L]], status = status, start = b$start,
                     end = b$end)
  }
  out
}

#' Append a prompt chunk holding a console statement (Rmd/qmd transcripts)
#' @noRd
doc_rmd_append_chunk = function(text, code) {
  while (length(text) && !nzchar(trimws(text[length(text)]))) text = text[-length(text)]
  c(text, "", "```{r}", code, "```")
}

#' The rmd/qmd formats' upsert(): replace inside an agent chunk, else add an agent chunk after
#' the owning chunk (fence and prefix copied); console sites append a prompt chunk first
#' @noRd
doc_rmd_upsert_fn = function(style) {
  force(style)
  function(text, site, lines, block_id) {
    blocks = doc_find_blocks(text)
    if (isTRUE(attr(blocks, "malformed"))) {
      gptr_abort("The document has malformed gptr markers.", "doc_write", path = site$path,
                 reason = "malformed")
    }
    hit = which(blocks$id == block_id)
    if (length(hit)) {
      return(doc_splice(text, blocks$start[hit], blocks$end[hit],
                        doc_indent_lines(lines, blocks$indent[hit])))
    }
    if (isTRUE(site$console)) {
      text = doc_rmd_append_chunk(text, site$statement %||% doc_console_statement(text, site))
      after = length(text)
      prefix = ""
      fence = "```"
    } else {
      loc = doc_rmd_locate(text, site)
      if (is.null(loc$stmt) || !isTRUE(loc$top_level)) {
        gptr_abort("The calling chunk was not found.", "doc_write", path = site$path,
                   reason = "not found")
      }
      ch = doc_rmd_chunks(text)
      k = loc$hit$chunk
      after = loc$insert_after
      prefix = ch$prefix[k]
      fence = ch$fence[k]
    }
    label = paste0("gptr-", block_id)
    header = if (identical(style, "qmd")) {
      c(paste0(prefix, fence, "{r}"), paste0(prefix, "#| label: ", label))
    } else {
      paste0(prefix, fence, "{r ", label, "}")
    }
    append(text, c("", header, paste0(prefix, lines), paste0(prefix, fence)), after = after)
  }
}

#' Add or remove eval=FALSE (`#| eval: false`) on the agent chunk of a block (G7 section 3.8)
#' @noRd
doc_rmd_chunk_eval = function(text, id, inert, style) {
  ch = doc_rmd_chunks(text)
  k = which(ch$label %in% paste0("gptr-", id))
  if (!length(k)) return(text)
  k = k[1L]
  if (identical(style, "qmd")) {
    body_idx = seq.int(ch$start[k] + 1L, length.out = max(0L, ch$end[k] - ch$start[k] - 1L))
    has = body_idx[grepl("^#\\|\\s*eval:\\s*false\\s*$", text[body_idx])]
    if (inert && !length(has)) {
      lab = body_idx[grepl("^#\\|\\s*label:", text[body_idx])]
      text = append(text, "#| eval: false", after = if (length(lab)) lab[1L] else ch$start[k])
    }
    if (!inert && length(has)) text = text[-has]
    return(text)
  }
  h = text[ch$start[k]]
  if (inert && !grepl("eval\\s*=\\s*FALSE", h)) h = sub("\\}\\s*$", ", eval=FALSE}", h)
  if (!inert) h = sub(",\\s*eval\\s*=\\s*FALSE", "", h)
  text[ch$start[k]] = h
  text
}

#' Make a marker block inert (`#~ ` body, status=undone) or live again (G7 section 3.8)
#' @noRd
doc_inert_marker_lines = function(seg, inert = TRUE) {
  open = regmatches(seg[1L], regexec(doc_re_open, seg[1L], perl = TRUE))[[1L]]
  if (!length(open)) return(seg)
  indent = open[2L]
  hdr = doc_parse_kv(open[4L])
  hdr$status = if (inert) "undone" else NULL
  n = length(seg)
  body = if (n > 2L) seg[2:(n - 1L)] else character()
  if (nzchar(indent)) {
    body = ifelse(startsWith(body, indent), substring(body, nchar(indent) + 1L), body)
  }
  body = if (inert) {
    ifelse(startsWith(body, "#~ ") | !nzchar(body), body, paste0("#~ ", body))
  } else {
    sub("^#~ ", "", body)
  }
  doc_render_block(open[3L], hdr, body, indent)
}

#' The marker formats' inert(): the lines of one block made inert
#' @noRd
doc_marker_inert = function(lines) {
  doc_inert_marker_lines(lines, TRUE)
}

#' The r, rmd, qmd and transcript formats' render(): a marker block
#' @noRd
doc_r_render = function(block, site) {
  doc_render_block(block$id, block$header, block$body)
}

#' The r format's locate()
#' @noRd
doc_r_locate = function(text, site) {
  doc_text_locate(text, site)
}

#' The r format's upsert(): replace a block in place, else insert it after the owned run
#' @noRd
doc_r_upsert = function(text, site, lines, block_id) {
  blocks = doc_find_blocks(text)
  if (isTRUE(attr(blocks, "malformed"))) {
    gptr_abort("The document has malformed gptr markers.", "doc_write", path = site$path,
               reason = "malformed")
  }
  hit = which(blocks$id == block_id)
  if (length(hit)) {
    return(doc_splice(text, blocks$start[hit], blocks$end[hit],
                      doc_indent_lines(lines, blocks$indent[hit])))
  }
  loc = doc_text_locate(text, site)
  if (is.null(loc$stmt) || !isTRUE(loc$top_level)) {
    gptr_abort("The calling statement was not found.", "doc_write", path = site$path,
               reason = "not found")
  }
  append(text, doc_indent_lines(lines, loc$indent), after = loc$insert_after)
}

#' The transcript statement of a console turn (IC-49): `s_<6 hex> = gptr(...)` for the
#' session's first prompt in this text, `s_<6 hex> |> gptr(...)` afterwards
#' @noRd
doc_console_statement = function(text, site) {
  var = paste0("s_", substr(sub("^s", "", site$session_id %||% "s000000"), 1L, 6L))
  args = paste(c(doc_str_literal(site$template %||% ""), site$context_labels), collapse = ", ")
  first = !any(startsWith(sub("^#~ ", "", text), paste0(var, " = gptr(")))
  if (first) paste0(var, " = gptr(", args, ")") else paste0(var, " |> gptr(", args, ")")
}

#' Header lines of a transcript session (contract 11.5 transcript row), once per session id
#' @noRd
doc_transcript_header = function(text, site) {
  id = site$session_id %||% "unknown"
  if (any(startsWith(text, paste0("# gptr session ", id, " ")))) return(character())
  head = c(paste0("# gptr session ", id, " -- started ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
           paste0("# machine log: ", site$session_file %||% "(none)"))
  if (!length(text)) {
    head = c(head, "# source() this file to replay the recorded code without calling a model;",
             "# options(gptr.replay = \"live\") re-asks the model.", "library(gptr)")
  }
  c(if (length(text)) "", head)
}

#' The transcript format's upsert(): replace by id, else append the header, statement and block
#' @noRd
doc_transcript_upsert = function(text, site, lines, block_id) {
  blocks = doc_find_blocks(text)
  hit = which(blocks$id == block_id)
  if (length(hit)) {
    return(doc_splice(text, blocks$start[hit], blocks$end[hit],
                      doc_indent_lines(lines, blocks$indent[hit])))
  }
  c(text, doc_transcript_header(text, site), "",
    site$statement %||% doc_console_statement(text, site), lines)
}

#' The transcript format's locate(): console turns are appended, never located
#' @noRd
doc_transcript_locate = function(text, site) {
  list(stmt = NULL, blocks = doc_find_blocks(text)[0L, , drop = FALSE], hit = NULL, owned = NULL,
       insert_after = length(text), top_level = TRUE, in_block = NULL, ordinal = 1L, indent = "")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 39 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-formats.R tests/testthat/test-doc-formats.R tests/testthat/fixtures/docs/report.Rmd \
  tests/testthat/fixtures/docs/report.expected.Rmd tests/testthat/fixtures/docs/report.qmd \
  tests/testthat/fixtures/docs/report.expected.qmd
git commit -m "feat(doc): add the r, Rmd, qmd and transcript formats and inert blocks"
```

---

### Task 6: The notebook serializer, the `ipynb` format and the format registry

**Files:**
- Modify: `R/doc-formats.R` (append)
- Create: `tests/testthat/fixtures/docs/floats.ipynb`
- Test: `tests/testthat/test-doc-formats.R` (append)

**Interfaces:**
- Consumes: Tasks 1-2, 5; P01 `json_decode()` (jsonlite `parse_json()`, which keeps `3` integer and `3.0`
  double), `as_utf8()`, `gptr_abort()`; P02 `gptr_spec(kind, name, ...)` (kind `doc_format`: fields `ext`, `locate`,
  `render`, `upsert`, `inert`, 04 §10.2 row 18), `registry_get()`, `registry_names()`.
- Produces: `nb_json_escape(s)`, `nb_json_num(x)` (Python `repr()` of a double), `nb_json_write(x, indent, level)`,
  `nb_parse(lines)` (attribute `indent`), `nb_serialize(nb)`, `nb_source_split(code)`, `nb_cell_lines(cell)`,
  `nb_cell_ids(nb)`, `nb_find_call_cell(nb, ph, call0 = NULL, j = 1L)`, `nb_call_ordinal(nb, cell, ph, call0 =
  NULL)`, `nb_meta(id, header)`, `nb_code_cell(code, id, meta)`, `nb_inert_text(text, ids, inert = TRUE)`; the `ipynb`
  format functions `doc_ipynb_locate()` (the calling cell found by content: the `j`-th code cell calling `gptr()` with
  the anchor's prompt hash, or its `call0` for a computed prompt; the anchor's `cell` index is informational only),
  `doc_ipynb_render()` (the body with the cell metadata as attribute `meta`),
  `doc_ipynb_upsert()`, `doc_ipynb_inert()`; the registry `doc_formats_builtin()` (the five `doc_format` specs `r`,
  `rmd`, `qmd`, `ipynb`, `transcript`), `doc_format_get(name)` (the registered spec, else the built-in before
  `builtin:documents` is loaded, `NULL` when a registry exists without it), `doc_inert_text(lines, fmt, ids, inert =
  TRUE, transcript = FALSE)`.

Report 14 §1 item 11 and §5.3: a notebook round-trips byte for byte only with gptr's own serializer, because
`jsonlite::toJSON()` escapes `</` and prints `3.0` as `3`; nbformat writes `json.dumps(indent=1, sort_keys=True,
separators=(",", ": "), ensure_ascii=False)` plus a final newline. The verification log (item 23) replaced the
first number formatter: `nb_json_num()` takes the shortest of `sprintf("%.<k>e")` that jsonlite parses back to the
same double (jsonlite's parser is correctly rounded; base `as.numeric()` is not, item 22) and lays it out as Python
does (`1e+16`, `1e-05`, `0.0001`, `3.0`). The fixture below was checked against Python 3: reading it with
`json.loads()` and writing it with nbformat's arguments gives the same bytes, and so does the notebook after the
upsert of this task's third test. Only `source` and `metadata.gptr` change on a rewrite; `outputs` and
`execution_count` stay (04 §11.5).

- [ ] **Step 1: Write the failing test**

Create the notebook fixture: save this code to a scratch file outside the repository (for example
`$TMPDIR/p15-fixtures-6.R`) and run `Rscript --vanilla "$TMPDIR/p15-fixtures-6.R"` from the repository root:

```r
# Fixture of P15 Task 6 (run from the repository root): a notebook exactly as Python's nbformat
# writes it (indent 1, sorted keys, ensure_ascii = False, a final newline), with floats that
# need 16-17 significant digits, 1e15/1e22 forms, an integer, "</table>", a tab and non-ASCII text
dir = file.path("tests", "testthat", "fixtures", "docs")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
nb = c(
  "{", " \"cells\": [", "  {", "   \"cell_type\": \"markdown\",", "   \"id\": \"a1b2c3d4\",",
  "   \"metadata\": {},", "   \"source\": [",
  "    \"# Caf\u00e9 analysis \U0001F600\\n\",", "    \"Some </table> text\\twith a tab.\"",
  "   ]", "  },", "  {", "   \"cell_type\": \"code\",", "   \"execution_count\": null,",
  "   \"id\": \"0badf00d\",", "   \"metadata\": {},", "   \"outputs\": [],", "   \"source\": [",
  "    \"x = mtcars\\n\",", "    \"summary(x$mpg)\"", "   ]", "  },", "  {",
  "   \"cell_type\": \"code\",", "   \"execution_count\": 3,", "   \"id\": \"c0ffee01\",",
  "   \"metadata\": {", "    \"gptr_test\": 0.3333333333333333,", "    \"scrolled\": true",
  "   },", "   \"outputs\": [", "    {", "     \"data\": {",
  "      \"application/vnd.plotly.v1+json\": {", "       \"x\": [",
  "        0.3333333333333333,", "        0.6666666666666666,", "        0.7999999999999999,",
  "        1000000000000000.0,", "        1e+22,", "        1e-07,", "        3.0,",
  "        0.5,", "        12", "       ]", "      },", "      \"text/plain\": [",
  "       \"<Figure>\"", "      ]", "     },", "     \"metadata\": {},",
  "     \"output_type\": \"display_data\"", "    },", "    {", "     \"name\": \"stdout\",",
  "     \"output_type\": \"stream\",", "     \"text\": [", "      \"[1] 20.09062\\n\"",
  "     ]", "    }", "   ],", "   \"source\": [",
  "    \"gptr(\\\"summarise the mpg column\\\")\"", "   ]", "  },", "  {",
  "   \"cell_type\": \"code\",", "   \"execution_count\": null,", "   \"id\": \"d00dfeed\",",
  "   \"metadata\": {},", "   \"outputs\": [],", "   \"source\": []", "  }", " ],",
  " \"metadata\": {", "  \"kernelspec\": {", "   \"display_name\": \"R\",",
  "   \"language\": \"R\",", "   \"name\": \"ir\"", "  },", "  \"language_info\": {",
  "   \"name\": \"R\"", "  }", " },", " \"nbformat\": 4,", " \"nbformat_minor\": 5", "}")
writeBin(charToRaw(paste0(paste(nb, collapse = "\n"), "\n")), file.path(dir, "floats.ipynb"))
```

Append to `tests/testthat/test-doc-formats.R`:

```r
test_that("numbers are written as Python's repr() and strings as json.dumps()", {
  cases = list(list(1 / 3, "0.3333333333333333"), list(2 / 3, "0.6666666666666666"),
               list(0.1 + 0.7, "0.7999999999999999"), list(1e15, "1000000000000000.0"),
               list(1e16, "1e+16"), list(1e22, "1e+22"), list(1e-7, "1e-07"),
               list(1e-4, "0.0001"), list(1e-5, "1e-05"), list(0.5, "0.5"), list(3, "3.0"),
               list(-0, "-0.0"), list(5L, "5"), list(123456.789, "123456.789"),
               list(-2.5e-8, "-2.5e-08"))
  for (cs in cases) expect_identical(nb_json_num(cs[[1]]), cs[[2]])
  expect_error(nb_json_num(Inf), class = "gptr_error_doc_write")
  esc = nb_json_escape(paste0("</table> a\tb \"q\" ", "\u00e9", "\001"))
  expect_identical(charToRaw(esc), charToRaw(paste0("\"</table> a\\tb \\\"q\\\" ", "\u00e9",
                                                    "\\u0001\"")))
})

test_that("a Python-written notebook round-trips byte for byte", {
  f = withr::local_tempfile(fileext = ".ipynb")
  file.copy(doc_fixture("floats.ipynb"), f)
  doc = doc_read(f)
  nb = nb_parse(doc$lines)
  expect_identical(attr(nb, "indent"), " ")
  expect_identical(nb_serialize(nb), doc$lines)
  doc_write(doc, nb_serialize(nb))
  expect_identical(readBin(f, "raw", n = file.info(f)$size), doc_fixture_bytes("floats.ipynb"))
  expect_error(nb_parse(c("{\"nbformat\": 3, \"cells\": []}")), class = "gptr_error_doc_write")
})

test_that("an agent cell is inserted after the calling cell, idempotently, keeping outputs", {
  text = doc_read(doc_fixture("floats.ipynb"))$lines
  nb = nb_parse(text)
  ph = prompt_hash("summarise the mpg column")
  cell = nb_find_call_cell(nb, ph)
  expect_identical(cell, 3L)
  site = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = cell),
              prompt_hash = ph, args_hash = NULL)
  lines = doc_ipynb_render(list(id = "7f3a21", header = list(
    model = "fake/fake-1", prompt = ph, date = "2026-09-29"),
    body = c("mean(x$mpg)", "#> [1] 20.09062", "## Decision: mean")), site)
  new = doc_ipynb_upsert(text, site, lines, "7f3a21")
  nb2 = nb_parse(new)
  expect_length(nb2$cells, length(nb$cells) + 1L)
  expect_identical(nb2$cells[-4], nb$cells)
  added = nb2$cells[[4]]
  expect_identical(added$id, "gptr-7f3a21")
  expect_identical(names(added), sort(names(added), method = "radix"))
  expect_identical(unlist(added$source), c("mean(x$mpg)\n", "#> [1] 20.09062\n",
                                           "## Decision: mean"))
  expect_identical(added$metadata$gptr$id, "7f3a21")
  end3 = which(text == "  },")[3]
  expect_identical(new[seq_len(end3)], text[seq_len(end3)])
  expect_identical(utils::tail(new, length(text) - end3), utils::tail(text, length(text) - end3))
  expect_identical(doc_ipynb_upsert(new, site, lines, "7f3a21"), new)
  loc = doc_ipynb_locate(new, site)
  expect_identical(loc$owned$id, "7f3a21")
  expect_identical(loc$insert_after, 4L)
  nb3 = nb2
  nb3$cells[[4]]$execution_count = 7L
  nb3$cells[[4]]$outputs = list(list(name = "stdout", output_type = "stream", text = list("x\n")))
  rewritten = doc_ipynb_upsert(nb_serialize(nb3), site,
                               structure("median(x$mpg)", meta = attr(lines, "meta")), "7f3a21")
  cell4 = nb_parse(rewritten)$cells[[4]]
  expect_identical(cell4$execution_count, 7L)
  expect_identical(cell4$outputs[[1]]$text[[1]], "x\n")
  expect_identical(unlist(cell4$source), "median(x$mpg)")
})

test_that("notebook anchors follow content, so an agent cell inserted above does not move them", {
  text = doc_read(doc_fixture("floats.ipynb"))$lines
  nb = nb_parse(text)
  extra = list(cell_type = "code", execution_count = NULL, id = "abcd0001",
               metadata = structure(list(), names = character()), outputs = list(),
               source = list("gptr(\"summarise the mpg column\")"))
  nb$cells = append(nb$cells, list(extra), after = 3L)
  two = nb_serialize(nb)
  ph = prompt_hash("summarise the mpg column")
  expect_identical(nb_call_ordinal(nb_parse(two), 4L, ph), 2L)
  s1 = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
            prompt_hash = ph, args_hash = NULL)
  s2 = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 2L, cell = 4L),
            prompt_hash = ph, args_hash = NULL)
  one = doc_ipynb_upsert(two, s1, structure("a = 1", meta = list(id = "aaaaaa")), "aaaaaa")
  both = doc_ipynb_upsert(one, s2, structure("b = 2", meta = list(id = "bbbbbb")), "bbbbbb")
  expect_identical(nb_cell_ids(nb_parse(both))[3:6],
                   c("c0ffee01", "gptr-aaaaaa", "abcd0001", "gptr-bbbbbb"))
})

test_that("notebook blocks become inert through metadata and #~ lines", {
  text = doc_read(doc_fixture("floats.ipynb"))$lines
  ph = prompt_hash("summarise the mpg column")
  site = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
              prompt_hash = ph, args_hash = NULL)
  with_cell = doc_ipynb_upsert(text, site, structure("mean(x$mpg)", meta = list(id = "7f3a21")),
                               "7f3a21")
  dead = nb_inert_text(with_cell, "7f3a21", TRUE)
  nb_dead = nb_parse(dead)
  expect_identical(nb_dead$cells[[4]]$metadata$gptr$status, "undone")
  expect_identical(unlist(nb_dead$cells[[4]]$source), "#~ mean(x$mpg)")
  expect_identical(nb_inert_text(dead, "7f3a21", FALSE), with_cell)
  expect_identical(doc_inert_text(dead, "ipynb", "7f3a21", FALSE), with_cell)
})

test_that("doc_inert_text() handles transcripts, Rmd and qmd", {
  seg = doc_render_block("abc123", list(model = "m", prompt = "p"), c("x = 1", "y = 2"))
  tr = c("library(gptr)", "", "s_ab12cd = gptr(\"first\")", seg)
  tr_dead = doc_inert_text(tr, "r", "abc123", TRUE, transcript = TRUE)
  expect_identical(tr_dead[3], "#~ s_ab12cd = gptr(\"first\")")
  expect_identical(tr_dead[5], "#~ x = 1")
  expect_identical(doc_inert_text(tr_dead, "r", "abc123", FALSE, transcript = TRUE), tr)
  rmd = doc_read(doc_fixture("report.expected.Rmd"))$lines
  rmd_dead = doc_inert_text(rmd, "rmd", "3fdfa0", TRUE)
  expect_true("````{r gptr-3fdfa0, eval=FALSE}" %in% rmd_dead)
  expect_identical(doc_inert_text(rmd_dead, "rmd", "3fdfa0", FALSE), rmd)
  expect_identical(doc_inert_text(rmd, "rmd", "zzzzzz", TRUE), rmd)
})

test_that("doc_format_get() returns the registered specs, else the built-ins", {
  for (nm in c("r", "rmd", "qmd", "ipynb", "transcript")) {
    spec = doc_format_get(nm)
    expect_s3_class(spec, "gptr_doc_format")
    expect_true(all(vapply(spec[c("locate", "render", "upsert", "inert")], is.function, NA)))
  }
  expect_null(doc_format_get(NULL))
  expect_null(doc_format_get("docx"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 39 ]`, the new tests failing with ``Error in `nb_json_num(cs[[1]])`: could not find function "nb_json_num"`` and the like.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-formats.R`:

```r
# ---- the notebook format: gptr's own nbformat 4 serializer (report 14 proto/ipynb.R, with the
# verification log's corrected number formatting) -----------------------------------------------

#' Escape a string as Python's json.dumps(ensure_ascii = False) does
#' @noRd
nb_json_escape = function(s) {
  s = as_utf8(s)
  s = gsub("\\", "\\\\", s, fixed = TRUE)
  s = gsub("\"", "\\\"", s, fixed = TRUE)
  s = gsub("\n", "\\n", s, fixed = TRUE)
  s = gsub("\r", "\\r", s, fixed = TRUE)
  s = gsub("\t", "\\t", s, fixed = TRUE)
  s = gsub("\b", "\\b", s, fixed = TRUE)
  s = gsub("\f", "\\f", s, fixed = TRUE)
  ctl = gregexpr("[\001-\037]", s, perl = TRUE)
  if (any(unlist(ctl) > 0L)) {
    regmatches(s, ctl) = lapply(regmatches(s, ctl), function(ch) {
      vapply(ch, function(c) sprintf("\\u%04x", utf8ToInt(c)), "", USE.NAMES = FALSE)
    })
  }
  paste0("\"", s, "\"")
}

#' Python repr() of a number: the shortest significand that parses back to the same double
#' (report 14 verification log, item 23)
#' @noRd
nb_json_num = function(x) {
  if (is.integer(x)) return(as.character(x))
  if (!is.finite(x)) gptr_abort("A notebook number is not finite.", "doc_write", path = NA,
                                reason = "number")
  if (x == 0) return(if (1 / x < 0) "-0.0" else "0.0")
  cand = sprintf(paste0("%.", 0:16, "e"), x)
  back = unlist(json_decode(paste0("[", paste(cand, collapse = ","), "]")))
  s = cand[which(back == x)[1L]]
  neg = startsWith(s, "-")
  digits = sub("0+$", "", gsub(".", "", sub("e.*$", "", sub("^-", "", s)), fixed = TRUE))
  decpt = as.integer(sub("^.*e", "", s)) + 1L
  nd = nchar(digits)
  out = if (decpt > -4L && decpt <= 16L) {
    if (decpt <= 0L) {
      paste0("0.", strrep("0", -decpt), digits)
    } else if (decpt >= nd) {
      paste0(digits, strrep("0", decpt - nd), ".0")
    } else {
      paste0(substr(digits, 1L, decpt), ".", substr(digits, decpt + 1L, nd))
    }
  } else {
    paste0(substr(digits, 1L, 1L), if (nd > 1L) paste0(".", substr(digits, 2L, nd)),
           "e", sprintf("%+03d", decpt - 1L))
  }
  if (neg) paste0("-", out) else out
}

#' Serialise a parsed notebook value like nbformat (indent unit, ", " and ": " separators)
#' @noRd
nb_json_write = function(x, indent = " ", level = 0L) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    nms = names(x)
    is_obj = !is.null(nms)
    if (!length(x)) return(if (is_obj) "{}" else "[]")
    pad = strrep(indent, level)
    pad1 = strrep(indent, level + 1L)
    items = vapply(seq_along(x), function(i) nb_json_write(x[[i]], indent, level + 1L), "")
    if (is_obj) items = paste0(nb_json_escape(nms), ": ", items)
    open = if (is_obj) "{" else "["
    close = if (is_obj) "}" else "]"
    return(paste0(open, "\n", paste0(pad1, items, collapse = ",\n"), "\n", pad, close))
  }
  if (length(x) != 1L) {
    gptr_abort("A notebook value is not a scalar.", "doc_write", path = NA, reason = "notebook")
  }
  if (is.na(x)) return("null")
  if (is.logical(x)) return(if (x) "true" else "false")
  if (is.numeric(x)) return(nb_json_num(x))
  nb_json_escape(as.character(x))
}

#' Parse notebook lines (nbformat 4 only); attribute `indent` is the file's indentation unit
#' @noRd
nb_parse = function(lines) {
  txt = paste(as_utf8(as.character(lines)), collapse = "\n")
  nb = json_decode(txt)
  if (!identical(as.integer(nb$nbformat), 4L)) {
    gptr_abort("Only nbformat 4 notebooks are supported.", "doc_write", path = NA,
               reason = "notebook")
  }
  second = regmatches(txt, regexpr("\n[ \t]+", txt))
  attr(nb, "indent") = if (length(second)) sub("^\n", "", second) else " "
  nb
}

#' Serialise a notebook to lines (the final newline is kept by doc_serialize())
#' @noRd
nb_serialize = function(nb) {
  indent = attr(nb, "indent") %||% " "
  attr(nb, "indent") = NULL
  strsplit(nb_json_write(nb, indent), "\n", fixed = TRUE)[[1L]]
}

#' Split code into nbformat source lines (each line but the last ends with a newline)
#' @noRd
nb_source_split = function(code) {
  s = paste(as_utf8(as.character(code)), collapse = "\n")
  if (!nzchar(s)) return(list())
  parts = strsplit(paste0(s, "\001"), "\n", fixed = TRUE)[[1L]]
  parts[length(parts)] = sub("\001$", "", parts[length(parts)])
  n = length(parts)
  out = paste0(parts, c(rep("\n", n - 1L), ""))
  as.list(out[nzchar(out)])
}

#' Source lines of a notebook cell
#' @noRd
nb_cell_lines = function(cell) {
  src = paste0(unlist(cell$source), collapse = "")
  if (!nzchar(src)) return(character())
  strsplit(src, "\n", fixed = TRUE)[[1L]]
}

#' Cell ids of a notebook
#' @noRd
nb_cell_ids = function(nb) {
  vapply(nb$cells, function(c) as.character(c$id %||% NA_character_), "")
}

#' Index of the j-th code cell (not an agent cell) calling gptr() with this prompt hash, or an
#' identical call for computed prompts; NA when none
#' @noRd
nb_find_call_cell = function(nb, ph, call0 = NULL, j = 1L) {
  found = 0L
  for (i in seq_along(nb$cells)) {
    cell = nb$cells[[i]]
    if (!identical(cell$cell_type, "code") || startsWith(cell$id %||% "", "gptr-")) next
    calls = doc_calls(nb_cell_lines(cell))
    hit = length(doc_calls_have(calls, ph %||% NA_character_, call0)) > 0L
    if (hit) {
      found = found + 1L
      if (found == j) return(i)
    }
  }
  NA_integer_
}

#' Ordinal of calling cell `cell` among the code cells that call gptr() with the same prompt
#' hash (or the same call, for computed prompts): the `j` of a notebook anchor
#' @noRd
nb_call_ordinal = function(nb, cell, ph, call0 = NULL) {
  j = 1L
  repeat {
    k = nb_find_call_cell(nb, ph, call0, j)
    if (is.na(k) || k >= cell) return(j)
    j = j + 1L
  }
}

#' Agent-cell metadata `metadata.gptr` from a block header (contract 11.5), keys sorted
#' @noRd
nb_meta = function(id, header) {
  meta = c(list(id = id), header[!vapply(header, is.null, NA)])
  meta = lapply(meta, function(v) if (is.numeric(v) && !is.integer(v)) as.character(v) else v)
  meta[order(names(meta), method = "radix")]
}

#' A new agent cell with nbformat's sorted keys
#' @noRd
nb_code_cell = function(code, id, meta) {
  list(cell_type = "code", execution_count = NULL, id = paste0("gptr-", id),
       metadata = list(gptr = meta), outputs = list(), source = nb_source_split(code))
}

#' The ipynb format's locate(): the calling cell and the agent cells after it
#' @noRd
doc_ipynb_locate = function(text, site) {
  nb = nb_parse(text)
  a = site$anchor
  # by content and ordinal (IC-51), never by the cell index seen at locate time: agent cells
  # inserted above (earlier pending blocks of the same sync) move the calling cells down
  cell = nb_find_call_cell(nb, a$ph %||% NA_character_, a$call0, a$j %||% 1L)
  out = list(stmt = NULL, blocks = NULL, hit = NULL, owned = NULL, insert_after = NULL,
             top_level = FALSE, in_block = NULL, ordinal = 1L, indent = "", cell = cell)
  if (is.na(cell) || cell > length(nb$cells)) return(out)
  out$stmt = c(cell, cell)
  out$top_level = TRUE
  k = cell + 1L
  run = integer()
  while (k <= length(nb$cells) && startsWith(nb$cells[[k]]$id %||% "", "gptr-")) {
    run = c(run, k)
    k = k + 1L
  }
  out$insert_after = if (length(run)) run[length(run)] else cell
  metas = lapply(run, function(k) nb$cells[[k]]$metadata$gptr %||% list())
  own = doc_run_owner(metas, site$prompt_hash, 1L)
  if (!is.null(own)) {
    k = run[own$index]
    meta = metas[[own$index]]
    status = doc_block_status(meta, nb_cell_lines(nb$cells[[k]]), site$prompt_hash,
                              site$args_hash)
    if (isTRUE(own$stale) && identical(status, "fresh")) status = "stale"
    out$owned = list(id = meta$id %||% sub("^gptr-", "", nb$cells[[k]]$id), header = meta,
                     status = status, start = k, end = k)
  }
  out
}

#' The ipynb format's render(): body lines with the cell metadata as attribute `meta`
#' @noRd
doc_ipynb_render = function(block, site) {
  structure(as.character(block$body), meta = nb_meta(block$id, block$header))
}

#' The ipynb format's upsert(): only `source` and `metadata.gptr` change on a rewrite
#' @noRd
doc_ipynb_upsert = function(text, site, lines, block_id) {
  nb = nb_parse(text)
  cid = paste0("gptr-", block_id)
  meta = attr(lines, "meta") %||% list(id = block_id)
  hit = match(cid, nb_cell_ids(nb))
  if (!is.na(hit)) {
    cell = nb$cells[[hit]]
    cell$metadata$gptr = meta
    cell$source = nb_source_split(as.character(lines))
    nb$cells[[hit]] = cell
  } else {
    loc = doc_ipynb_locate(text, site)
    if (is.null(loc$stmt)) {
      gptr_abort("The calling cell was not found in the notebook.", "doc_write",
                 path = site$path %||% NA, reason = "not found")
    }
    nb$cells = append(nb$cells, list(nb_code_cell(as.character(lines), block_id, meta)),
                      after = loc$insert_after)
  }
  nb_serialize(nb)
}

#' The ipynb format's inert(): `#~ ` source lines
#' @noRd
doc_ipynb_inert = function(lines) {
  ifelse(startsWith(lines, "#~ ") | !nzchar(lines), lines, paste0("#~ ", lines))
}

#' Undo or revive agent cells of a notebook (G7 section 3.8: metadata.gptr.status = "undone")
#' @noRd
nb_inert_text = function(text, ids, inert = TRUE) {
  nb = nb_parse(text)
  cids = nb_cell_ids(nb)
  for (id in ids) {
    k = match(paste0("gptr-", id), cids)
    if (is.na(k)) next
    cell = nb$cells[[k]]
    src = nb_cell_lines(cell)
    src = if (inert) doc_ipynb_inert(src) else sub("^#~ ", "", src)
    meta = cell$metadata$gptr %||% list()
    meta$status = if (inert) "undone" else NULL
    cell$metadata$gptr = meta[order(names(meta), method = "radix")]
    cell$source = nb_source_split(src)
    nb$cells[[k]] = cell
  }
  nb_serialize(nb)
}

# ---- the format registry -------------------------------------------------------------------------

#' The five built-in doc_format specs (contract 7.15, 10.2 row 18)
#' @noRd
doc_formats_builtin = function() {
  list(
    r = gptr_spec("doc_format", "r", ext = c("R", "r"), locate = doc_r_locate,
                  render = doc_r_render, upsert = doc_r_upsert, inert = doc_marker_inert),
    rmd = gptr_spec("doc_format", "rmd", ext = c("Rmd", "rmd"), locate = doc_rmd_locate,
                    render = doc_r_render, upsert = doc_rmd_upsert_fn("rmd"),
                    inert = doc_marker_inert),
    qmd = gptr_spec("doc_format", "qmd", ext = "qmd", locate = doc_rmd_locate,
                    render = doc_r_render, upsert = doc_rmd_upsert_fn("qmd"),
                    inert = doc_marker_inert),
    ipynb = gptr_spec("doc_format", "ipynb", ext = "ipynb", locate = doc_ipynb_locate,
                      render = doc_ipynb_render, upsert = doc_ipynb_upsert,
                      inert = doc_ipynb_inert),
    transcript = gptr_spec("doc_format", "transcript", ext = c("R", "r"),
                           locate = doc_transcript_locate, render = doc_r_render,
                           upsert = doc_transcript_upsert, inert = doc_marker_inert)
  )
}

#' A doc_format spec by name: the registered one, else the built-in (before builtin:documents
#' is loaded); NULL when builtin:documents is filtered out and nothing else provides it
#' @noRd
doc_format_get = function(name) {
  if (is.null(name)) return(NULL)
  spec = tryCatch(registry_get("doc_format", name), error = function(e) NULL)
  if (!is.null(spec)) return(spec)
  if (length(tryCatch(registry_names("doc_format"), error = function(e) character()))) {
    return(NULL)
  }
  doc_formats_builtin()[[name]]
}

#' Text of a document with the given blocks made inert or live again (G7 sections 3.8, 4.4);
#' in transcripts the owning `s_<hex>` statement line is prefixed too
#' @noRd
doc_inert_text = function(lines, fmt, ids, inert = TRUE, transcript = FALSE) {
  if (identical(fmt, "ipynb")) return(nb_inert_text(lines, ids, inert))
  for (id in ids) {
    b = doc_find_blocks(lines)
    k = which(b$id == id)
    if (!length(k)) next
    rng = b$start[k[1L]]:b$end[k[1L]]
    lines[rng] = doc_inert_marker_lines(lines[rng], inert)
    if (transcript) {
      p = b$start[k[1L]] - 1L
      while (p >= 1L && !nzchar(trimws(lines[p]))) p = p - 1L
      if (p >= 1L && grepl("^(#~ )?s_[0-9a-f]{6} (=|\\|>) gptr\\(", lines[p])) {
        lines[p] = if (inert) sub("^(#~ )?", "#~ ", lines[p]) else sub("^#~ ", "", lines[p])
      }
    }
    if (fmt %in% c("rmd", "qmd")) lines = doc_rmd_chunk_eval(lines, id, inert, fmt)
  }
  lines
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 99 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-formats.R tests/testthat/test-doc-formats.R tests/testthat/fixtures/docs/floats.ipynb
git commit -m "feat(doc): add the byte-exact notebook serializer and the format registry"
```

---

### Task 7: Write consent, the control guard and the S2 answer cache

**Files:**
- Create: `R/doc-replay.R`
- Test: `tests/testthat/test-doc-replay.R` (create)

**Interfaces:**
- Consumes: Task 4 (`doc_project_get()`, `doc_project_remember()`, `doc_rel()`, `doc_abs()`, `doc_root()`); P01
  `the`, `path_key()`, `setting_get()`, `gptr_can_prompt()`, `gptr_confirm(question, default = FALSE)` (asks through
  the mockable `gptr_readline()`), `hash_sha256()`, `canonical_json(x)`, `json_encode()`, `json_decode()`,
  `read_utf8()`, `write_atomic()`, `workspace_root()`, `as_utf8()`, `gptr_abort()`; P03 `redact(x, profile =
  "persist")`; P06 `run_current()` and the `gptr_run` fields `session` and `signal` (environment; P08 and P11 put a
  one-shot approval token, the function name, in `signal$control`, IC-53).
- Produces: `doc_consent(path, ask = TRUE)` -> lgl(1) (IC-45: the process binding `the$doc_binding`, `record =
  "auto"` from the option or a settings layer, a remembered per-document answer or the remembered transcript target
  in the user-level project file, else an interactive yes, remembered); `doc_consent_possible(path)` (consent exists
  or could still be asked); `doc_control_guard(what)` (IC-53; signals `gptr_error_permission` with `action`, `tool =
  "r"`, `risk = 4L`, `how_to_allow`, `session`); the S2 cache of 04 §11.9: `s2_key(doc, block, part = "", prompt =
  "", args = "")`, `s2_path(key)`, `s2_get(key)` -> the record or `NULL`, `s2_put(key, record)` (the answer redacted
  with the `persist` profile at ingress).

Consent is checked only when a block is written (IC-45): replay never asks. A `record` value of `"auto"` can only
come from the option or the user layer, because P08's settings layers let a project tighten `record` but never
loosen it. The S2 key includes the args hash and the part (`""`, a child name, or `n<ordinal>` for block-nested
calls), so a parameterised report never replays another parameter's answer (IC-45, IC-47).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-doc-replay.R`:

```r
# Tests for R/doc-replay.R (plan P15): consent, S2, decisions, the route, services, hooks, the
# exports, and the end-to-end record/replay acceptance of 05 P15.

# Bind a document for the calling test (restores the previous binding)
local_doc_binding = function(path, format = "r", .env = parent.frame()) {
  old = the$doc_binding
  the$doc_binding = list(path = path_norm(path), format = format)
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  invisible(path)
}

test_that("write consent comes from the binding, record = auto, a remembered answer or a yes", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines("x = 1", f)
  local_gptr_options(record = NULL, interactive = FALSE)
  expect_false(doc_consent(f))
  expect_false(doc_consent_possible(f))
  local({
    local_doc_binding(f)
    expect_true(doc_consent(f))
  })
  expect_false(doc_consent(f))
  local({
    local_gptr_options(record = "auto")
    expect_true(doc_consent(f))
  })
  local({
    local_gptr_options(record = "off")
    local_doc_binding(f)
    expect_true(doc_consent(f))
  })
  doc_project_remember("a.R", "auto")
  expect_true(doc_consent(f))
  doc_project_remember("a.R", "off")
  expect_false(doc_consent(f))
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  doc_project_transcript(".gptr/transcripts/t.R")
  expect_true(doc_consent(t))
})

test_that("an interactive yes is asked once and remembered per document", {
  proj = local_project()
  g = file.path(proj, "b.R")
  writeLines("y = 1", g)
  local_gptr_options(record = NULL, interactive = TRUE)
  expect_true(doc_consent_possible(g))
  asked = new.env()
  asked$n = 0L
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") {
    asked$n = asked$n + 1L
    "y"
  })
  expect_true(doc_consent(g))
  expect_identical(doc_project_get()$record$b.R, "auto")
  expect_true(doc_consent(g))
  expect_identical(asked$n, 1L)
})

test_that("model code cannot call a control export during a run unless approved (IC-53)", {
  expect_invisible(doc_control_guard("gptr_doc"))
  run = new.env()
  run$session = "s0123456789"
  run$signal = new.env()
  testthat::local_mocked_bindings(run_current = function() run)
  cnd = expect_error(doc_control_guard("gptr_doc"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_doc")
  run$signal$control = "gptr_doc"
  expect_invisible(doc_control_guard("gptr_doc"))
  expect_error(doc_control_guard("gptr_doc"), class = "gptr_error_permission")
})

test_that("S2 answers round-trip under keys that include the args hash and part", {
  local_project()
  k1 = s2_key("a.R", "abc123", "", "p", "")
  k2 = s2_key("a.R", "abc123", "", "p", "aaaa1111")
  k3 = s2_key("a.R", "abc123", "n1", "p", "")
  expect_false(identical(k1, k2))
  expect_false(identical(k1, k3))
  expect_identical(s2_key("a.R", "abc123", "", "p", NULL), k1)
  expect_match(k1, "^[0-9a-f]{64}$")
  s2_put(k1, list(block = "abc123", doc = "a.R", part = "", answer = "It is 32."))
  expect_identical(s2_get(k1)$answer, "It is 32.")
  expect_null(s2_get(k2))
  expect_identical(s2_path(k1), file.path(workspace_dir(), "cache", "s2", substr(k1, 1, 2),
                                          paste0(k1, ".json")))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`, starting with ``Error in `doc_consent(f)`: could not find function "doc_consent"``.

- [ ] **Step 3: Write the implementation**

Create `R/doc-replay.R`:

```r
# doc-replay.R -- replay (plan P15; contract 6.4, 7.15, 11.9; IC-45..IC-52): write consent, the
# replay decision per mode (report 14 section 4.4.2 table, G7 section 3.8 undone row, IC-45
# args=), the S2 answer cache, the `document` route, replaying fresh blocks (IC-46, IC-47), the
# doc.* services, the agent_end/session_tree hooks, the console:command/console:direct handlers
# and the exports gptr_doc(), gptr_source(), gptr_blocks() and gptr_cache(). The replay mode is
# P08's replay_mode(). Layer L4.

#' Write consent for a document (IC-45): the gptr_doc() binding of this process, `record =
#' "auto"` (option or user setting; `record` only tightens in a project), a remembered answer or
#' transcript target in the user-level project file, or an interactive yes (remembered)
#' @noRd
doc_consent = function(path, ask = TRUE) {
  key = path_key(path)
  b = the$doc_binding
  if (!is.null(b$path) && identical(path_key(b$path), key)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off")) return(FALSE)
  if (identical(rec, "auto")) return(TRUE)
  pf = doc_project_get()
  rel = doc_rel(path)
  remembered = if (is.list(pf$record)) pf$record[[rel]] else NULL
  if (identical(remembered, "auto")) return(TRUE)
  if (identical(remembered, "off")) return(FALSE)
  target = pf$transcript$target
  if (is.character(target) && !identical(target, "off") &&
      identical(path_key(doc_abs(target)), key)) {
    return(TRUE)
  }
  if (!ask || !gptr_can_prompt()) return(FALSE)
  yes = isTRUE(gptr_confirm(paste0("Record gptr blocks into ", rel, "?")))
  doc_project_remember(rel, if (yes) "auto" else "off")
  yes
}

#' Could consent still be given for a document (without asking now)? Consent exists, or a human
#' can answer and nothing refuses it (decides whether the route keeps a site for recording)
#' @noRd
doc_consent_possible = function(path) {
  if (doc_consent(path, ask = FALSE)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off") || !gptr_can_prompt()) return(FALSE)
  pf = doc_project_get()
  remembered = if (is.list(pf$record)) pf$record[[doc_rel(path)]] else NULL
  !identical(remembered, "off")
}

#' Refuse a control-category export called from model code during a run unless the dispatcher
#' approved exactly this call (IC-53; the one-shot token in `run$signal$control`, as P08's
#' control_check() reads it)
#' @noRd
doc_control_guard = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  sig = run$signal
  ok = if (is.environment(sig)) sig$control %||% character() else character()
  i = match(what, ok)
  if (!is.na(i)) {
    sig$control = ok[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0(what, "() changes what gptr records and was called from model code ",
                      "during a run."),
               "Only you can make this change: call it yourself outside the run."),
             "permission", action = what, tool = "r", risk = 4L,
             how_to_allow = "call it yourself outside gptr(), or approve the r call when asked",
             session = run$session)
}

#' The S2 cache key of contract 11.9 (IC-45, IC-47)
#' @noRd
s2_key = function(doc, block, part = "", prompt = "", args = "") {
  hash_sha256(canonical_json(list(schema = 2L, doc = doc, block = block, part = part %||% "",
                                  prompt = prompt %||% "", args = args %||% "")))
}

#' The S2 file of a key: `<root>/cache/s2/<2 hex>/<sha256>.json`
#' @noRd
s2_path = function(key) {
  file.path(doc_root(), "cache", "s2", substr(key, 1L, 2L), paste0(key, ".json"))
}

#' Read an S2 record (NULL on a miss)
#' @noRd
s2_get = function(key) {
  f = s2_path(key)
  if (!file.exists(f)) return(NULL)
  tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
}

#' Write an S2 record: `{block, doc, part, prompt, model, answer, usage, cost, session, turn,
#' date}`; the answer is redacted with the persist profile at ingress
#' @noRd
s2_put = function(key, record) {
  record$answer = redact(as_utf8(record$answer %||% ""), "persist")
  f = file.path(workspace_root(), "cache", "s2", substr(key, 1L, 2L), paste0(key, ".json"))
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  write_atomic(f, json_encode(record))
  invisible(f)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 26 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-replay.R tests/testthat/test-doc-replay.R
git commit -m "feat(doc): add write consent, the control guard and the S2 answer cache"
```

---

### Task 8: Locating the calling statement: `doc_locate()`

**Files:**
- Create: `R/doc-locate.R`
- Modify: `R/doc-io.R` (append: IDE queries)
- Test: `tests/testthat/test-doc-locate.R` (create)

**Interfaces:**
- Consumes: Tasks 1-2, 4-6 (`doc_calls()`, `doc_calls_have()`, `doc_anchor_of()`, `doc_stmt_by_expr()`,
  `prompt_hash()`, `args_hash()`, `doc_read()`, `doc_format_of()`, `doc_state()`, `doc_rel()`, `doc_abs()`,
  `doc_project_get()`, `doc_project_transcript()`, `doc_rmd_calls()`, `nb_parse()`, `nb_find_call_cell()`,
  `doc_format_get()`); P01 `path_norm()`, `path_key()`, `path_class(path, root = project_root())`,
  `project_root()`, `workspace_dir()`, `gptr_opt("doc_source_frames")`, `gptr_is_interactive()`,
  `gptr_can_prompt()`, `gptr_confirm()`, `front_end()`, `setting_get("transcript")`, `ext_service_has()`,
  `ext_service_get()` (the `ui.get` service of P11, optional); P06 `session_data()`; the `gptr_call` record of P08
  (04 §7.8): `template`, `prompt`, `interp`, `context`, `session`, `sys_call` ("`sys.call()` of the `gptr()` frame
  (with its srcref)"), `nframe`, and `top_level` ("set by P15's locator"); knitr (`current_input()`,
  `opts_current`) and rstudioapi (`isAvailable()`, `hasFun()`, `getSourceEditorContext()`, `documentId()`), both
  guarded.
- Produces (04 §7.15): `doc_locate(call)` -> the site `list(kind, path, format, stmt, expr, occurrence, ordinal,
  backend, top_level, in_block, ide_id, defer, prompt_hash, args_hash, template, block, anchor, indent, label,
  driver)` (a console site adds `console = TRUE`, `session_id`, `session_file`, `context_labels`), or `NULL`; it
  assigns `call$top_level`. `block` is the owned block `list(id, header, status, start, end)` or `NULL`; `backend`
  is `"file"`, `"deferred"` (Rscript), `"pending"` (Jupyter), `"rstudio"`, `"positron"`, `"vscode"` or
  `"transcript"`; `driver` is `"gptr_source"`, `"knitr"`, `"ide"`, `"jupyter"`, `"console"` or `"base"` (base
  `source()`/Rscript, which cannot skip an old block). Also `doc_transcript_target(ask = FALSE)`,
  `doc_console_site(session_id = NULL, template = NULL, context_labels = character(), ask = FALSE, session_file =
  NULL)`, `doc_target_valid(path)`, `doc_driver(site)`, the finders `doc_site_srcref()`,
  `doc_site_source_frame()`, `doc_site_knitr()`, `doc_site_jupyter()`, `doc_site_rscript()`, `doc_site_ide()`, and
  in `doc-io.R` `doc_ide_available()`, `doc_ide_context()`, `doc_ide_console_focused()`, `doc_ide_backend()`.

The precedence is architecture §6.9.3 and report 14 §4.2 (prototype `gptr_where()` of §5.0). A srcref is accepted
only when its statement text contains this call (pipelines force the inner call inside the outer one, so its own
srcref can be misleading: report 14 §1 item 3), never for `.active-rstudio-document` and never inside gptr's own
`R/` sources (they carry srcrefs under `pkgload::load_all()`). `source()` and `sys.source()` frames (`ofile` or
`file`, `exprs`, `i`) are read inside `tryCatch()` and only while `gptr.doc_source_frames` is `TRUE` (CRAN grey zone,
report 14 §6); the verification log confirmed the `sys.source()` variant (item 4) and that `sys.call()` is
`identical()` to the parsed call (item 8). knitr gives the chunk label, Quarto the document through
`QUARTO_DOCUMENT_PATH`/`QUARTO_DOCUMENT_FILE` (its `current_input()` is a temporary `*.rmarkdown`, item 10); IRkernel
`JPY_SESSION_NAME`, then a content search; `Rscript --file=` a per-(file, prompt) execution counter; IDEs the buffer
of the active editor (guarded with `isAvailable()`/`hasFun()`, never gated on versions: VS Code reports `0`). A call
in no document goes to the console transcript target (IC-49, IC-52): the `gptr_doc()` binding, the remembered target,
the `transcript` setting (`"off"`, `"file"`, `"active-document"`), or, once per project in an interactive session,
the user's choice; targets must be inside the project root, `.R`/`.Rmd`/`.qmd`/`.ipynb`, and not a control,
protected, critical or instructions path.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-doc-locate.R`:

```r
# Tests for R/doc-locate.R (plan P15): the precedence of architecture 6.9.3 and the console
# transcript target. A stand-in `gptr()` defined in the sourcing environment builds the call
# record the way P08 does (template, sys_call, nframe) and returns doc_locate()'s site.

# Bind a document for the calling test (restores the previous binding)
local_doc_binding = function(path, format = "r", .env = parent.frame()) {
  old = the$doc_binding
  the$doc_binding = list(path = path_norm(path), format = format)
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  invisible(path)
}

doc_probe_env = function() {
  e = new.env()
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_locate(call)
  }
  e
}

test_that("a sourced top-level call is located through its srcref and owns its block", {
  proj = local_project()
  f = file.path(proj, "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("x = 1", "site = gptr(\"count rows\")",
               paste0("# >>> gptr:abc123 model=m prompt=", ph), "n = 1", "# <<< gptr:abc123",
               "f = function() gptr(\"inner\")", "inner = f()"), f)
  e = doc_probe_env()
  source(f, local = e, keep.source = TRUE)
  s = e$site
  expect_identical(s$kind, "srcref")
  expect_identical(s$path, path_norm(f))
  expect_identical(s$format, "r")
  expect_identical(s$stmt, c(2L, 2L))
  expect_true(s$top_level)
  expect_identical(s$block$id, "abc123")
  expect_identical(s$block$status, "fresh")
  expect_identical(s$backend, "file")
  expect_identical(s$driver, "base")
  expect_identical(s$prompt_hash, ph)
  expect_false(e$inner$top_level %||% FALSE)
})

test_that("without srcrefs the source() frame locates the statement, unless switched off", {
  proj = local_project()
  f = file.path(proj, "analysis.R")
  writeLines(c("x = 1", "site = gptr(\"count rows\")", "y = 2", "site2 = gptr(\"count rows\")"), f)
  e = doc_probe_env()
  source(f, local = e, keep.source = FALSE)
  expect_identical(e$site$kind, "source_frame")
  expect_identical(e$site$stmt, c(2L, 2L))
  expect_identical(e$site2$stmt, c(4L, 4L))
  expect_true(e$site2$top_level)
  local_gptr_options(doc_source_frames = FALSE)
  e2 = doc_probe_env()
  source(f, local = e2, keep.source = FALSE)
  expect_null(e2$site)
})

test_that("pipelines, block-nested calls and dynamic prompts are told apart", {
  proj = local_project()
  f = file.path(proj, "a.R")
  ph = prompt_hash("outer")
  writeLines(c("chain = gptr(\"step one\") |> gptr(\"step two\")",
               "dyn = gptr(paste(\"dy\", \"n\"))",
               "outer = gptr(\"outer\")", paste0("# >>> gptr:abc123 model=m prompt=", ph),
               "nested = gptr(\"inner\")", "# <<< gptr:abc123"), f)
  e = doc_probe_env()
  e$gptr = function(x, prompt = NULL, ...) {
    if (is.null(prompt)) prompt = x
    call = new.env(parent = emptyenv())
    call$template = if (is.character(prompt)) prompt else NULL
    call$prompt = prompt
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    site = doc_locate(call)
    if (is.list(x) && !is.null(x$kind)) c(list(first = x), site) else site
  }
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$chain$ordinal, 2L)
  expect_identical(e$chain$first$ordinal, 1L)
  expect_identical(e$dyn$stmt, c(2L, 2L))
  expect_true(is.na(e$dyn$anchor$ph))
  expect_identical(e$nested$in_block, "abc123")
  expect_false(e$nested$top_level)
})

test_that("Quarto and Jupyter locations come from their environment variables", {
  proj = local_project()
  q = file.path(proj, "report.qmd")
  writeLines(c("```{r}", "#| label: ask", "gptr(\"count rows\")", "```"), q)
  withr::local_options(knitr.in.progress = TRUE)
  withr::local_envvar(QUARTO_DOCUMENT_PATH = proj, QUARTO_DOCUMENT_FILE = "report.qmd")
  raw = doc_site_knitr(NULL, prompt_hash("count rows"), NULL)
  expect_identical(raw$kind, "quarto")
  expect_identical(raw$path, path_norm(q))
  withr::local_options(knitr.in.progress = NULL, jupyter.in_kernel = TRUE)
  nb = file.path(proj, "analysis.ipynb")
  file.copy(testthat::test_path("fixtures", "docs", "floats.ipynb"), nb)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  call = new.env(parent = emptyenv())
  call$template = "summarise the mpg column"
  call$sys_call = quote(gptr("summarise the mpg column"))
  call$nframe = 0L
  site = doc_locate(call)
  expect_identical(site$kind, "jupyter")
  expect_identical(site$backend, "pending")
  expect_identical(site$anchor$cell, 3L)
  expect_identical(site$anchor$j, 1L)
  expect_true(site$top_level)
  expect_true(call$top_level)
  # a call in an unlabelled chunk: knitr reports unnamed-chunk-<k>, which the anchor matches
  un = c("```{r}", "x = 1", "```", "", "```{r}", "gptr(\"count rows\")", "```")
  a = doc_anchor(list(format = "rmd"), list(kind = "knitr", label = "unnamed-chunk-2"), un,
                 prompt_hash("count rows"), NULL)
  expect_identical(a$label, "unnamed-chunk-2")
  expect_identical(doc_match_anchor(doc_rmd_calls(un), a)$line1, 6L)
})

test_that("calls in no document go to the console transcript target, if any", {
  proj = local_project()
  call = new.env(parent = emptyenv())
  call$template = "first prompt"
  call$sys_call = quote(gptr("first prompt"))
  call$nframe = 0L
  call$context = list(list(label = "mtcars", kind = "symbol", name = "mtcars"))
  expect_null(doc_locate(call))
  expect_false(call$top_level)
  tf = file.path(proj, ".gptr", "transcripts", "t.R")
  local_doc_binding(tf)
  site = doc_locate(call)
  expect_identical(site$kind, "console")
  expect_identical(site$format, "transcript")
  expect_identical(site$backend, "transcript")
  expect_identical(site$context_labels, "mtcars")
  expect_true(site$console)
})

test_that("transcript targets follow the setting and are validated (IC-52)", {
  proj = local_project()
  local_gptr_options(transcript = "off")
  expect_null(doc_transcript_target())
  local_gptr_options(transcript = "file")
  t1 = doc_transcript_target()
  expect_match(t1, "[.]gptr/transcripts/gptr-session-[0-9]{8}-[0-9]{6}[.]R$")
  expect_identical(doc_abs(doc_project_get()$transcript$target), t1)
  expect_identical(doc_transcript_target(), t1)
  doc_project_transcript("../outside.R")
  local_gptr_options(transcript = "ask", interactive = FALSE)
  expect_null(doc_transcript_target(ask = TRUE))
  expect_false(doc_target_valid(file.path(proj, ".gptr", "vignette.Rmd")))
  expect_false(doc_target_valid(file.path(dirname(proj), "x.R")))
  expect_true(doc_target_valid(file.path(proj, "analysis.R")))
})

test_that("an interactive console asks once where to record and remembers the answer", {
  proj = local_project()
  local_gptr_options(transcript = "ask", interactive = TRUE)
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") "y")
  t1 = doc_transcript_target(ask = TRUE)
  expect_match(t1, "gptr-session-")
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") stop("asked twice"))
  expect_identical(doc_transcript_target(ask = TRUE), t1)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-locate")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`, starting with ``Error in `doc_locate(call)`: could not find function "doc_locate"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-io.R`:

```r
# ---- IDE queries (report 14 sections 2.1.4-2.1.6; rstudioapi is a Suggests package) ------------

#' Is the rstudioapi document API usable (RStudio, Positron's shim, VS Code sess)?
#' @noRd
doc_ide_available = function() {
  requireNamespace("rstudioapi", quietly = TRUE) &&
    isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)) &&
    isTRUE(tryCatch(rstudioapi::hasFun("getSourceEditorContext"), error = function(e) FALSE))
}

#' The active source editor context list(id, path, contents, selection), or NULL
#' @noRd
doc_ide_context = function() {
  tryCatch(rstudioapi::getSourceEditorContext(), error = function(e) NULL)
}

#' Is the console the focused editor ("#console" in RStudio and Positron)?
#' @noRd
doc_ide_console_focused = function() {
  identical(tryCatch(rstudioapi::documentId(allowConsole = TRUE), error = function(e) NULL),
            "#console")
}

#' The IDE backend name of this front end
#' @noRd
doc_ide_backend = function() {
  switch(front_end(), positron = "positron", vscode = "vscode", "rstudio")
}
```

Create `R/doc-locate.R`:

```r
# doc-locate.R -- locating the calling statement (plan P15; contract 7.15; architecture 6.9.3):
# a validated srcref > a source()/sys.source() frame (read inside tryCatch, off switch
# gptr.doc_source_frames; CRAN grey zone) > knitr/Quarto > IRkernel > `Rscript --file=` > IDE >
# console. Calls are matched by content and ordinal through an anchor (prompt hash or call-text
# hash, ordinal, block), never by stale line numbers. Also the console transcript target (IC-49,
# IC-52). Layer L4. Adapted from report 14 sections 4.2 and 5.0 (gptr_where, doc_match_call).

#' A call without attributes (srcrefs), for identity tests
#' @noRd
doc_strip_call = function(x) {
  if (is.null(x)) return(NULL)
  attributes(x) = NULL
  x
}

#' The R/ directory of gptr's own sources when they carry srcrefs (pkgload::load_all()), or NULL
#' @noRd
doc_own_sources = function() {
  ns = topenv(environment(doc_own_sources))
  if (!isNamespace(ns)) return(NULL)
  path_norm(file.path(getNamespaceInfo(ns, "path"), "R"))
}

#' Absolute path of a srcfile when it is an existing user file: not RStudio's
#' .active-rstudio-document and not gptr's own sources (whose srcrefs exist under load_all())
#' @noRd
doc_srcfile_path = function(sf) {
  if (is.null(sf) || !is.environment(sf) || !isTRUE(sf$isFile)) return(NULL)
  fn = sf$filename %||% ""
  if (!nzchar(fn) || identical(basename(fn), ".active-rstudio-document")) return(NULL)
  full = if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", fn)) {
    path.expand(fn)
  } else {
    file.path(sf$wd %||% getwd(), fn)
  }
  if (!file.exists(full)) return(NULL)
  full = path_norm(full)
  own = doc_own_sources()
  if (!is.null(own) && startsWith(path_key(full), paste0(path_key(own), "/"))) return(NULL)
  full
}

#' Site from a validated srcref of the call or of a calling frame (report 14 section 4.2 step 1):
#' the statement's text must contain this call
#' @noRd
doc_site_srcref = function(call, ph, call0) {
  n = call$nframe %||% 0L
  if (is.na(n)) n = 0L
  cands = list(call$sys_call)
  for (k in rev(seq_len(max(0L, n - 1L)))) cands[[length(cands) + 1L]] = sys.call(k)
  for (cl in cands) {
    sr = attr(cl, "srcref")
    if (is.null(sr) || length(sr) < 8L) next
    sf = attr(sr, "srcfile")
    path = doc_srcfile_path(sf)
    if (is.null(path)) next
    pl = if (!is.null(sf$lines)) as_utf8(sf$lines) else doc_read(path)$lines
    rng = c(sr[7L], sr[8L])
    if (rng[2L] > length(pl)) next
    k = doc_calls_have(doc_calls(pl[rng[1L]:rng[2L]]), ph, call0)
    if (!length(k)) next
    return(list(kind = "srcref", path = path, stmt_at_parse = rng, lines_at_parse = pl))
  }
  NULL
}

#' Site from a source()/sys.source() frame (`ofile` or `file`, `exprs`, `i`); best effort and
#' switched off by options(gptr.doc_source_frames = FALSE)
#' @noRd
doc_site_source_frame = function(call, ph, call0) {
  if (!isTRUE(gptr_opt("doc_source_frames"))) return(NULL)
  n = call$nframe %||% 0L
  if (is.na(n)) n = 0L
  for (k in rev(seq_len(max(0L, n - 1L)))) {
    fn = sys.function(k)
    is_src = identical(fn, base::source)
    is_sys = identical(fn, base::sys.source)
    if (!is_src && !is_sys) next
    e = sys.frame(k)
    file = get0(if (is_src) "ofile" else "file", envir = e, inherits = FALSE)
    exprs = get0("exprs", envir = e, inherits = FALSE)
    i = get0("i", envir = e, inherits = FALSE)
    if (!is.character(file) || length(file) != 1L || !file.exists(file) || !is.expression(exprs) ||
        !is.numeric(i) || length(i) != 1L || i > length(exprs)) next
    target = exprs[[i]]
    occ = sum(vapply(seq_len(i), function(m) identical(exprs[[m]], target), NA))
    return(list(kind = "source_frame", path = path_norm(file), expr = doc_strip_call(target),
                occurrence = occ))
  }
  NULL
}

#' Site under knitr or Quarto: QUARTO_DOCUMENT_PATH/FILE, else knitr::current_input(); the label
#' @noRd
doc_site_knitr = function(call, ph, call0) {
  if (!isTRUE(getOption("knitr.in.progress")) || !requireNamespace("knitr", quietly = TRUE)) {
    return(NULL)
  }
  qdir = Sys.getenv("QUARTO_DOCUMENT_PATH")
  qfile = Sys.getenv("QUARTO_DOCUMENT_FILE")
  quarto = nzchar(qfile)
  path = if (quarto && nzchar(qdir)) {
    file.path(qdir, qfile)
  } else {
    tryCatch(knitr::current_input(dir = TRUE), error = function(e) NULL)
  }
  if (is.null(path) || !file.exists(path)) return(NULL)
  list(kind = if (quarto) "quarto" else "knitr", path = path_norm(path),
       label = tryCatch(knitr::opts_current$get("label"), error = function(e) NULL) %||%
         NA_character_)
}

#' Site in IRkernel: JPY_SESSION_NAME, else a content match over the notebooks in getwd()
#' @noRd
doc_site_jupyter = function(call, ph, call0) {
  if (!isTRUE(getOption("jupyter.in_kernel"))) return(NULL)
  jpy = Sys.getenv("JPY_SESSION_NAME")
  cands = if (nzchar(jpy) && file.exists(jpy)) {
    jpy
  } else {
    list.files(getwd(), pattern = "[.]ipynb$", full.names = TRUE)
  }
  for (p in cands) {
    cell = tryCatch(nb_find_call_cell(nb_parse(doc_read(p)$lines), ph, call0),
                    error = function(e) NA_integer_)
    if (!is.na(cell)) return(list(kind = "jupyter", path = path_norm(p), cell = cell))
  }
  NULL
}

#' Site of a call under `Rscript file.R` (writes are deferred to exit, IC-51)
#' @noRd
doc_site_rscript = function(call, ph, call0) {
  if (gptr_is_interactive()) return(NULL)
  fa = grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (!length(fa)) return(NULL)
  f = sub("^--file=", "", fa[1L])
  if (!file.exists(f) || !identical(doc_format_of(f), "r")) return(NULL)
  list(kind = "rscript", path = path_norm(f))
}

#' Site of a call run from an IDE editor (RStudio, Positron, VS Code with sess)
#' @noRd
doc_site_ide = function(call, ph, call0) {
  if (!gptr_is_interactive() || !doc_ide_available()) return(NULL)
  ctx = doc_ide_context()
  if (is.null(ctx) || !nzchar(ctx$path %||% "") || is.null(doc_format_of(ctx$path))) return(NULL)
  contents = as_utf8(as.character(ctx$contents))
  if (doc_ide_console_focused() && !length(doc_calls_have(doc_calls(contents), ph, call0))) {
    return(NULL)
  }
  cursor = tryCatch(ctx$selection[[1L]]$range$start[["row"]], error = function(e) NA_integer_)
  list(kind = "ide", path = path_norm(ctx$path), ide_id = ctx$id, contents = contents,
       cursor = cursor, backend = doc_ide_backend())
}

#' Next Rscript execution ordinal for a (document, call identity) pair
#' @noRd
doc_counter_next = function(path, key) {
  st = doc_state()
  k = paste(path_key(path), key)
  st$counters[[k]] = (st$counters[[k]] %||% 0L) + 1L
  st$counters[[k]]
}

#' The anchor of the located call in the text available at locate time (NULL: not found)
#' @noRd
doc_anchor = function(site, raw, text, ph, call0) {
  if (site$format %in% c("rmd", "qmd")) {
    calls = doc_rmd_calls(text)
    cand = calls[doc_calls_have(calls, ph, call0), , drop = FALSE]
    if (!is.na(raw$label %||% NA_character_)) cand = cand[cand$label %in% raw$label, , drop = FALSE]
    if (identical(raw$kind, "ide") && !is.na(raw$cursor %||% NA)) {
      above = cand[cand$line1 <= raw$cursor, , drop = FALSE]
      if (nrow(above)) cand = above[nrow(above), , drop = FALSE]
    }
    if (!nrow(cand)) return(NULL)
    return(doc_anchor_of(calls, cand[1L, , drop = FALSE]))
  }
  if (identical(site$format, "ipynb")) {
    cell = raw$cell %||% NA_integer_
    if (is.na(cell)) return(NULL)
    j = nb_call_ordinal(nb_parse(text), cell, ph, call0)
    return(list(ph = ph, th = NA_character_, j = j, block = NA_character_, cell = cell,
                call0 = if (is.na(ph)) call0 else NULL))
  }
  if (identical(raw$kind, "srcref")) {
    calls = doc_calls(raw$lines_at_parse)
    rng = raw$stmt_at_parse
    inside = calls[calls$line1 >= rng[1L] & calls$line2 <= rng[2L], , drop = FALSE]
    t = inside[doc_calls_have(inside, ph, call0), , drop = FALSE]
    return(if (nrow(t)) doc_anchor_of(calls, t[1L, , drop = FALSE]) else NULL)
  }
  calls = doc_calls(text)
  if (identical(raw$kind, "source_frame")) {
    rng = doc_stmt_by_expr(text, raw$expr, raw$occurrence %||% 1L)
    if (is.null(rng)) return(NULL)
    inside = calls[calls$line1 >= rng[1L] & calls$line2 <= rng[2L], , drop = FALSE]
    t = inside[doc_calls_have(inside, ph, call0), , drop = FALSE]
    return(if (nrow(t)) doc_anchor_of(calls, t[1L, , drop = FALSE]) else NULL)
  }
  cand = calls[doc_calls_have(calls, ph, call0), , drop = FALSE]
  if (!nrow(cand)) return(NULL)
  if (identical(raw$kind, "rscript")) {
    k = doc_counter_next(raw$path, if (!is.na(ph)) ph else cand$th[1L])
    if (k > nrow(cand)) return(NULL)
    return(doc_anchor_of(calls, cand[k, , drop = FALSE]))
  }
  if (identical(raw$kind, "ide") && !is.na(raw$cursor %||% NA)) {
    above = cand[cand$line1 <= raw$cursor, , drop = FALSE]
    if (nrow(above)) return(doc_anchor_of(calls, above[nrow(above), , drop = FALSE]))
  }
  doc_anchor_of(calls, cand[1L, , drop = FALSE])
}

#' The execution driver of a site, which decides whether a regeneration can skip the old block:
#' "knitr", "ide", "jupyter", "console", "gptr_source" or "base" (source()/Rscript)
#' @noRd
doc_driver = function(site) {
  if (site$kind %in% c("knitr", "quarto")) return("knitr")
  if (site$kind %in% c("ide", "jupyter", "console")) return(site$kind)
  st = doc_state()
  n = length(st$sources)
  if (n && identical(st$sources[[n]]$key, path_key(site$path))) return("gptr_source")
  "base"
}

#' Is a document or transcript target allowed: a known format inside the project root, not a
#' control or protected path (IC-52)
#' @noRd
doc_target_valid = function(path) {
  if (is.null(path) || is.null(doc_format_of(path))) return(FALSE)
  root = path_key(project_root())
  if (!startsWith(path_key(path), paste0(sub("/$", "", root), "/"))) return(FALSE)
  cls = tryCatch(path_class(path), error = function(e) "unknown")
  !any(cls %in% c("control", "protected", "critical", "instructions", "url", "wildcard"))
}

#' A new transcript file under .gptr/transcripts/ (only in an existing workspace), remembered
#' @noRd
doc_new_transcript = function() {
  ws = workspace_dir()
  if (is.null(ws)) return(NULL)
  target = file.path(ws, "transcripts",
                     paste0("gptr-session-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".R"))
  doc_project_transcript(doc_rel(target))
  target
}

#' The IDE's active document when it is a valid target
#' @noRd
doc_active_document = function() {
  if (!doc_ide_available()) return(NULL)
  p = doc_ide_context()$path %||% ""
  if (nzchar(p) && doc_target_valid(path_norm(p))) path_norm(p) else NULL
}

#' Ask where to record the console session: "document", "file" or "none" (the UI's select()
#' when a UI backend is registered, else a yes/no question for a new transcript)
#' @noRd
doc_ask_transcript = function() {
  choices = c(document = "The active document", file = "A new transcript in .gptr/transcripts/",
              none = "Nowhere")
  if (is.null(doc_active_document())) choices = choices[-1L]
  ui = if (ext_service_has("ui.get")) {
    tryCatch(ext_service_get("ui.get")(NULL), error = function(e) NULL)
  } else {
    NULL
  }
  if (is.function(ui$select)) {
    k = tryCatch(ui$select("Record this console session into", unname(choices)),
                 error = function(e) NA_integer_)
    return(if (length(k) && !is.na(k[1L])) names(choices)[k[1L]] else "none")
  }
  if (gptr_confirm("Record this console session into a transcript in .gptr/transcripts/?")) {
    "file"
  } else {
    "none"
  }
}

#' Where console turns are recorded (IC-49, IC-52): the gptr_doc() binding, the remembered
#' target, the `transcript` setting, or (interactively, once per project) the user's choice
#' @noRd
doc_transcript_target = function(ask = FALSE) {
  b = the$doc_binding
  if (!is.null(b$path)) return(b$path)
  mode = tryCatch(setting_get("transcript", default = "ask"), error = function(e) "ask") %||%
    "ask"
  if (identical(mode, "off")) return(NULL)
  remembered = doc_project_get()$transcript$target
  if (identical(remembered, "off")) return(NULL)
  if (is.character(remembered) && length(remembered) == 1L) {
    full = doc_abs(remembered)
    if (doc_target_valid(full)) return(full)
  }
  if (identical(mode, "file")) return(doc_new_transcript())
  if (identical(mode, "active-document")) return(doc_active_document())
  if (!ask || !gptr_can_prompt()) return(NULL)
  choice = doc_ask_transcript()
  target = switch(choice, file = doc_new_transcript(), document = doc_active_document(), NULL)
  if (is.null(target)) {
    doc_project_transcript("off")
  } else {
    doc_project_transcript(doc_rel(target))
  }
  target
}

#' The console site of a call or REPL turn: the transcript target as a document whose turns are
#' appended (`format` "transcript" for .R targets); NULL when there is no target
#' @noRd
doc_console_site = function(session_id = NULL, template = NULL, context_labels = character(),
                            ask = FALSE, session_file = NULL) {
  target = doc_transcript_target(ask = ask)
  if (is.null(target)) return(NULL)
  fmt = doc_format_of(target)
  if (is.null(fmt) || identical(fmt, "ipynb")) return(NULL)
  list(kind = "console", path = path_norm(target),
       format = if (identical(fmt, "r")) "transcript" else fmt, stmt = NULL, expr = NULL,
       occurrence = 1L, ordinal = 1L, backend = "transcript", top_level = TRUE, in_block = NULL,
       ide_id = NULL, defer = FALSE, console = TRUE, driver = "console",
       prompt_hash = prompt_hash(template %||% ""), args_hash = NULL, template = template,
       session_id = session_id, session_file = session_file,
       context_labels = as.character(context_labels), block = NULL, anchor = NULL, indent = "")
}

#' Finish a raw location into the site of contract 7.15 (format, backend, driver, anchor,
#' statement, ownership); NULL when the call is not found in that document
#' @noRd
doc_site_finish = function(raw, call, ph, call0) {
  fmt = doc_format_of(raw$path)
  if (is.null(fmt)) return(NULL)
  site = list(kind = raw$kind, path = raw$path, format = fmt, stmt = NULL, expr = raw$expr,
              occurrence = raw$occurrence %||% 1L, ordinal = 1L, backend = "file",
              top_level = FALSE, in_block = NULL, ide_id = raw$ide_id,
              defer = identical(raw$kind, "rscript"), prompt_hash = ph,
              args_hash = args_hash(call$interp),
              template = call$template %||% call$prompt, block = NULL, anchor = NULL,
              indent = "", label = raw$label %||% NA_character_)
  site$backend = switch(raw$kind, jupyter = "pending", rscript = "deferred",
                        ide = raw$backend %||% "rstudio", "file")
  site$driver = doc_driver(site)
  text = if (identical(raw$kind, "ide")) raw$contents else doc_read(site$path)$lines
  site$anchor = doc_anchor(site, raw, text, ph, call0)
  if (is.null(site$anchor)) return(NULL)
  loc = doc_format_get(fmt)$locate(text, site)
  site$stmt = loc$stmt
  site$top_level = isTRUE(loc$top_level)
  site$in_block = loc$in_block
  site$ordinal = loc$ordinal %||% 1L
  site$block = loc$owned
  site$indent = loc$indent %||% ""
  site
}

#' Locate the calling statement of a gptr() call record (contract 7.15): a site list, the
#' console site when the call is in no document, or NULL. Sets `call$top_level`.
#' @noRd
doc_locate = function(call) {
  template = call$template %||% call$prompt
  ph = if (is.character(template) && length(template) == 1L && !is.na(template)) {
    prompt_hash(template)
  } else {
    NA_character_
  }
  call0 = doc_strip_call(call$sys_call)
  site = NULL
  finders = list(doc_site_srcref, doc_site_source_frame, doc_site_knitr, doc_site_jupyter,
                 doc_site_rscript, doc_site_ide)
  for (f in finders) {
    raw = tryCatch(f(call, ph, call0), error = function(e) NULL)
    if (is.null(raw)) next
    site = tryCatch(doc_site_finish(raw, call, ph, call0), error = function(e) NULL)
    if (!is.null(site)) break
  }
  if (is.null(site)) {
    labels = vapply(call$context %||% list(), function(x) {
      if (identical(x$kind, "symbol")) x$name %||% "" else ""
    }, "")
    s = call$session
    site = doc_console_site(session_id = if (is.null(s)) NULL else session_data(s)$id,
                            template = template, context_labels = labels[nzchar(labels)])
  }
  if (is.environment(call)) assign("top_level", isTRUE(site$top_level), envir = call)
  site
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-locate")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 49 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-locate.R R/doc-io.R tests/testthat/test-doc-locate.R
git commit -m "feat(doc): locate the calling statement in scripts, documents, notebooks and IDEs"
```

---

### Task 9: The writer: `doc_upsert()`

**Files:**
- Modify: `R/doc-blocks.R` (append)
- Test: `tests/testthat/test-doc-blocks.R` (append)

**Interfaces:**
- Consumes: Tasks 1-8 (`doc_format_get()` and the formats' `locate`/`render`/`upsert`, `doc_consent()`,
  `doc_read_or_new()`, `doc_write()`, `doc_lock()`, `doc_unlock()`, `doc_rel()`, `doc_transcript_target()`,
  `doc_console_site()`, `doc_source_log()`, `s2_key()`, `s2_put()`, `nb_parse()`, `nb_cell_ids()`,
  `nb_cell_lines()`); P01 `id_block(taken = character())`, `gptr_inform(..., .once = NULL)`, `gptr_warn()`; P02
  `ev_dispatch(event, payload, session = NULL, ctx = NULL)` (the `document_write` event: "block + patch, error =
  block", returns `list(block, reason, lines)`), `registry_diagnostic(source, event, class, message)`; P06
  `session_append(s, entry)`, `session_data()`.
- Produces (04 §7.15): `doc_upsert(site, block_lines, block_id = NULL)` -> `invisible(list(action, block_id, lines,
  backend))` with `action` in `insert`, `replace`, `stale-regenerate`, `unchanged`, `user-edited`, `blocked`,
  `not-found`, `locked`, `conflict`, `failed`, `none` (no consent or no site); helpers `doc_event(path, format, kind,
  block_id, lines, session = NULL)`, `doc_existing_ids(format, text)`, `doc_existing_status(format, text, id)`,
  `doc_block_range(format, text, id)`, `doc_prepare(fmt, site, up, text, taken = character())` -> `list(id, rendered,
  action, sha, prompt)` or `list(skip, id)`, `doc_file_upsert(fmt, site, up)`, `doc_upsert_fallback(site, up,
  backend)`, `doc_after_write(site, res, block_lines)`. Each written block appends `gptr.doc_block` `{doc, format,
  block, action, prompt, sha, lines, backend}` to the session and caches the answer under part `""` and each child
  text under its part in S2 (IC-47). A site with `regenerate = TRUE` and `block_id` replaces that block even when it
  was edited by hand; otherwise a hand-edited block is kept (`user-edited`).

`doc_upsert()` checks consent first (IC-45; without it nothing is written and a once-per-document notice says how to
enable recording), then dispatches by backend: `"file"` and `"transcript"` go through `doc_file_upsert()` under the
document lock with an md5 check, re-locate and three attempts (then the warning `doc_conflict`; IC-51); `"deferred"`
and `"pending"` call `doc_pending_add()` (Task 10) and the IDE backends `doc_ide_upsert()` (Task 11). Tests of this
task use file sites only. A format error writes nothing to the document and records the block in the console
transcript instead when there is one (04 §10.2 row 18).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-blocks.R`:

```r
# A located site for the first call with this prompt in an .R document
doc_file_site = function(path, prompt = "count rows") {
  calls = doc_calls(readLines(path, encoding = "UTF-8"))
  k = which(calls$ph %in% prompt_hash(prompt))[1]
  list(kind = "srcref", path = path_norm(path), format = "r", backend = "file",
       anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = prompt_hash(prompt),
       args_hash = NULL, template = prompt)
}

test_that("doc_upsert() writes nothing without consent and inserts, replaces and is idempotent", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines(c("library(gptr)", "gptr(\"count rows\")", "z = 1"), f)
  site = doc_file_site(f)
  hdr = list(model = "fake/fake-1", date = "2026-09-29", prompt = prompt_hash("count rows"))
  lines = structure(c("n = nrow(mtcars)", "#> [1] 32"), header = hdr)
  local_gptr_options(record = "off")
  expect_identical(doc_upsert(site, lines)$action, "none")
  expect_identical(readLines(f), c("library(gptr)", "gptr(\"count rows\")", "z = 1"))
  local_gptr_options(record = "auto")
  res = doc_upsert(site, lines)
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "file")
  expect_match(res$block_id, "^[0-9a-f]{6}$")
  txt = readLines(f)
  expect_identical(txt[3], paste0("# >>> gptr:", res$block_id, " model=fake/fake-1 ",
                                  "date=2026-09-29 prompt=", prompt_hash("count rows"), " sha=",
                                  doc_body_sha(c("n = nrow(mtcars)", "#> [1] 32"))))
  expect_identical(txt[4:7], c("n = nrow(mtcars)", "#> [1] 32", paste0("# <<< gptr:", res$block_id),
                               "z = 1"))
  expect_identical(res$lines, c(3L, 6L))
  md5 = tools::md5sum(f)
  again = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines,
                     block_id = res$block_id)
  expect_identical(again$action, "unchanged")
  expect_identical(tools::md5sum(f), md5)
  rep = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)),
                   structure("n = 32", header = hdr), block_id = res$block_id)
  expect_identical(rep$action, "replace")
  expect_identical(readLines(f)[4], "n = 32")
  expect_identical(nrow(doc_find_blocks(readLines(f))), 1L)
})

test_that("a hand-edited block is kept unless regenerating, and hooks can block or patch", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "n = 1"
  head = paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count rows"), " sha=",
                doc_body_sha(body))
  writeLines(c("gptr(\"count rows\")", head, "n = 1 # edited by hand", "# <<< gptr:abc123"), f)
  site = doc_file_site(f)
  lines = structure("n = 2", header = list(model = "m", prompt = prompt_hash("count rows")))
  expect_identical(doc_upsert(site, lines, block_id = "abc123")$action, "user-edited")
  expect_identical(readLines(f)[3], "n = 1 # edited by hand")
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(block = TRUE, reason = "frozen")
  }))
  res = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines, block_id = "abc123")
  off()
  expect_identical(res$action, "blocked")
  expect_identical(readLines(f)[3], "n = 1 # edited by hand")
  off2 = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(lines = c(event$lines[1], "# reviewed", event$lines[-1]))
  }))
  res2 = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines, block_id = "abc123")
  off2()
  expect_identical(res2$action, "replace")
  expect_identical(readLines(f)[3:4], c("# reviewed", "n = 2"))
})

test_that("a successful write appends gptr.doc_block and caches the answers in S2", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  site = doc_file_site(f)
  lines = doc_block_lines(s, 1L, site, 1L)
  attr(lines, "children") = list(n1 = list(text = "child text", session = "s1111111111",
                                           model = "fake/fake-1", turn = 1L))
  res = doc_upsert(site, lines)
  ents = session_data(s)$entries
  last = ents[[length(ents)]]
  expect_identical(last$custom_type, "gptr.doc_block")
  expect_identical(last$data$block, res$block_id)
  expect_identical(last$data$action, "insert")
  expect_identical(last$data$doc, "a.R")
  expect_identical(last$data$backend, "file")
  ph = prompt_hash("count rows")
  rec = s2_get(s2_key("a.R", res$block_id, "", ph, ""))
  expect_identical(rec$answer, "There are 32 rows.")
  expect_identical(rec$session, session_data(s)$id)
  expect_identical(s2_get(s2_key("a.R", res$block_id, "n1", ph, ""))$answer, "child text")
})

test_that("a document that keeps changing gives up after three attempts with a warning", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  site = doc_file_site(f)
  testthat::local_mocked_bindings(doc_write = function(doc, lines, check = TRUE) {
    gptr_abort("changed", "doc_write", path = doc$path, reason = "conflict")
  })
  res = NULL
  expect_warning({
    res = doc_upsert(site, structure("n = 1", header = list(model = "m")))
  }, class = "gptr_warning_doc_conflict")
  expect_identical(res$action, "conflict")
})

test_that("a lock held by another live process records nothing", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  dir = doc_lock_dir(f)
  dir.create(dir, recursive = TRUE)
  writeLines(doc_lock_stamp(), file.path(dir, "pid"))
  res = NULL
  expect_message({
    res = doc_upsert(doc_file_site(f), structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "locked")
  expect_identical(readLines(f), "gptr(\"count rows\")")
})

test_that("a format error writes nothing and falls back to the console transcript", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "# >>> gptr:aaaaaa model=m"), f)
  doc_project_transcript(".gptr/transcripts/t.R")
  s = doc_test_session(list(doc_test_turn("n = 1")))
  lines = doc_block_lines(s, 1L, doc_file_site(f), 1L)
  res = doc_upsert(doc_file_site(f), lines)
  expect_identical(res$backend, "transcript")
  expect_identical(readLines(f), c("gptr(\"count rows\")", "# >>> gptr:aaaaaa model=m"))
  tr = readLines(file.path(getwd(), ".gptr", "transcripts", "t.R"))
  expect_true("n = 1" %in% tr)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 138 ]`, the new tests failing with ``Error in `doc_upsert(site, lines)`: could not find function "doc_upsert"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-blocks.R`:

```r
# ---- the writer (contract 7.15 doc_upsert(); IC-45, IC-47, IC-50, IC-51) ------------------------

#' Pass the fail-closed, patchable `document_write` event (contract 10.4); returns
#' list(block, reason, lines) with `lines` NULL when no handler changed them
#' @noRd
doc_event = function(path, format, kind, block_id, lines, session = NULL) {
  res = ev_dispatch("document_write", list(path = path, format = format, kind = kind,
                                           block_id = block_id, lines = as.character(lines)),
                    session = session)
  if (is.null(res)) return(list(block = FALSE, reason = NULL, lines = NULL))
  if (identical(as.character(res$lines), as.character(lines))) res$lines = NULL
  res
}

#' Ids of the agent blocks in a text of any format
#' @noRd
doc_existing_ids = function(format, text) {
  if (identical(format, "ipynb")) {
    ids = nb_cell_ids(nb_parse(text))
    return(sub("^gptr-", "", ids[!is.na(ids) & startsWith(ids, "gptr-")]))
  }
  doc_find_blocks(text)$id
}

#' Status of an existing block by id, ignoring prompts (user-edited or undone detection)
#' @noRd
doc_existing_status = function(format, text, id) {
  if (identical(format, "ipynb")) {
    nb = nb_parse(text)
    k = match(paste0("gptr-", id), nb_cell_ids(nb))
    if (is.na(k)) return(NA_character_)
    cell = nb$cells[[k]]
    return(doc_block_status(cell$metadata$gptr %||% list(), nb_cell_lines(cell)))
  }
  b = doc_find_blocks(text)
  k = which(b$id == id)
  if (!length(k)) return(NA_character_)
  doc_block_status(b$header[[k[1L]]], doc_block_body(text, b[k[1L], , drop = FALSE]))
}

#' Line range of a block in a text (a cell index for notebooks), or NULL
#' @noRd
doc_block_range = function(format, text, id) {
  if (identical(format, "ipynb")) {
    k = match(paste0("gptr-", id), nb_cell_ids(nb_parse(text)))
    return(if (is.na(k)) NULL else c(k, k))
  }
  b = doc_find_blocks(text)
  k = which(b$id == id)
  if (length(k)) c(b$start[k[1L]], b$end[k[1L]]) else NULL
}

#' Choose the block id, fill it into the body, render, and pass the document_write event:
#' list(id, rendered, action, sha, prompt) or list(skip = <reason>, id)
#' @noRd
doc_prepare = function(fmt, site, up, text, taken = character()) {
  loc = fmt$locate(text, site)
  existing = doc_existing_ids(site$format, text)
  id = up$block_id
  replace = !is.null(id) && id %in% existing
  if (is.null(id) && !is.null(loc$owned) && isTRUE(site$regenerate)) {
    id = loc$owned$id
    replace = TRUE
  }
  if (!replace && (is.null(loc$stmt) || !isTRUE(loc$top_level)) && !isTRUE(site$console)) {
    return(list(skip = "not-found", id = id))
  }
  if (replace && !isTRUE(site$regenerate) &&
      identical(doc_existing_status(site$format, text, id), "user-edited")) {
    return(list(skip = "user-edited", id = id))
  }
  if (!replace) id = id_block(c(existing, taken))
  body = gsub(doc_block_token, id, as.character(up$lines), fixed = TRUE)
  header = up$header
  header$sha = doc_body_sha(body)
  rendered = fmt$render(list(id = id, header = header, body = body), site)
  kind = if (isTRUE(site$console)) "transcript" else "block"
  ev = doc_event(site$path, site$format, kind, id, rendered, up$session)
  if (isTRUE(ev$block)) return(list(skip = "blocked", id = id, reason = ev$reason))
  if (!is.null(ev$lines)) {
    patched = as.character(ev$lines)
    attributes(patched) = attributes(rendered)
    rendered = patched
  }
  status = if (replace && !is.null(loc$owned) && identical(loc$owned$id, id)) loc$owned$status
  action = if (!replace) "insert" else if (identical(status, "stale")) "stale-regenerate" else
    "replace"
  list(id = id, rendered = rendered, action = action, sha = header$sha, prompt = header$prompt)
}

#' Insert or replace a call's block through the site's backend (contract 7.15): checks write
#' consent first (IC-45; otherwise nothing is written), passes `document_write` (fail closed,
#' patchable), md5 conflict checks with re-locate and retry, deferred Rscript writes, pending
#' notebook blocks, IDE buffers. Returns list(action, block_id, lines, backend) invisibly.
#' @noRd
doc_upsert = function(site, block_lines, block_id = NULL) {
  none = list(action = "none", block_id = NULL, lines = NULL, backend = NULL)
  if (is.null(site) || is.null(site$path)) return(invisible(none))
  fmt = doc_format_get(site$format %||% doc_format_of(site$path))
  if (is.null(fmt)) return(invisible(none))
  if (!doc_consent(site$path)) {
    rel = doc_rel(site$path)
    gptr_inform(paste0("gptr did not record into ", rel, ": no write consent. Call gptr_doc(\"",
                       rel, "\") or set options(gptr.record = \"auto\") to record."), "notice",
                .once = paste0("doc_consent:", path_key(site$path)))
    return(invisible(none))
  }
  up = list(block_id = block_id %||% site$block_id, lines = as.character(block_lines),
            header = attr(block_lines, "header") %||% list(),
            session = attr(block_lines, "session"))
  backend = site$backend %||% "file"
  res = tryCatch({
    if (backend %in% c("pending", "deferred")) {
      doc_pending_add(fmt, site, up, backend)
    } else if (backend %in% c("rstudio", "positron", "vscode")) {
      doc_ide_upsert(fmt, site, up)
    } else {
      doc_file_upsert(fmt, site, up)
    }
  }, error = function(e) {
    registry_diagnostic("builtin:documents", "document_write", class(e)[1L],
                        conditionMessage(e))
    doc_upsert_fallback(site, up, backend)
  })
  if (!is.null(res$block_id) && res$action %in% c("insert", "replace", "stale-regenerate")) {
    doc_after_write(site, res, block_lines)
  }
  invisible(res)
}

#' A format error writes nothing to the document and records the block in the console
#' transcript instead, when there is one (contract 10.2 row 18)
#' @noRd
doc_upsert_fallback = function(site, up, backend) {
  failed = list(action = "failed", block_id = NULL, lines = NULL, backend = backend)
  if (isTRUE(site$console)) return(failed)
  target = tryCatch(doc_transcript_target(ask = FALSE), error = function(e) NULL)
  if (is.null(target) || identical(path_key(target), path_key(site$path)) ||
      !identical(doc_format_of(target), "r")) {
    return(failed)
  }
  s = up$session
  tsite = doc_console_site(session_id = if (is.null(s)) NULL else session_data(s)$id,
                           template = site$template)
  if (is.null(tsite)) return(failed)
  up$block_id = NULL
  tryCatch(doc_file_upsert(doc_format_get("transcript"), tsite, up), error = function(e) failed)
}

#' Disk upsert under the document lock with md5 conflict checks and three attempts (IC-51)
#' @noRd
doc_file_upsert = function(fmt, site, up) {
  path = site$path
  backend = if (isTRUE(site$console)) "transcript" else "file"
  lock = doc_lock(path)
  if (is.null(lock)) {
    gptr_inform(paste0("Another R process is writing ", doc_rel(path),
                       "; this block was not recorded."), "notice")
    return(list(action = "locked", block_id = NULL, lines = NULL, backend = backend))
  }
  on.exit(doc_unlock(lock), add = TRUE)
  prep = NULL
  for (attempt in 1:3) {
    doc = doc_read_or_new(path)
    prep = doc_prepare(fmt, site, up, doc$lines)
    if (!is.null(prep$skip)) {
      return(list(action = prep$skip, block_id = prep$id, lines = NULL, backend = backend))
    }
    new = fmt$upsert(doc$lines, site, prep$rendered, prep$id)
    if (identical(new, doc$lines)) {
      return(list(action = "unchanged", block_id = prep$id, lines = NULL, backend = backend))
    }
    ok = tryCatch({
      doc_write(doc, new)
      TRUE
    }, gptr_error_doc_write = function(e) {
      if (identical(e$reason, "conflict")) FALSE else stop(e)
    })
    if (ok) {
      return(list(action = prep$action, block_id = prep$id, backend = backend,
                  lines = doc_block_range(site$format, new, prep$id), sha = prep$sha,
                  prompt = prep$prompt))
    }
  }
  gptr_warn(paste0("The document ", doc_rel(path), " kept changing on disk; block ", prep$id,
                   " was not written (the session log has it)."), "doc_conflict")
  list(action = "conflict", block_id = NULL, lines = NULL, backend = backend)
}

#' After a write: the `gptr.doc_block` entry, the S2 answers (the block's and its children's,
#' IC-47) and the gptr_source() log
#' @noRd
doc_after_write = function(site, res, block_lines) {
  header = attr(block_lines, "header") %||% list()
  s = attr(block_lines, "session")
  rel = doc_rel(site$path)
  if (!is.null(s)) {
    data = list(doc = rel, format = site$format, block = res$block_id, action = res$action,
                prompt = header$prompt, sha = res$sha,
                lines = if (length(res$lines)) I(as.integer(res$lines)) else NULL,
                backend = res$backend)
    tryCatch(session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                                    data = data[!vapply(data, is.null, NA)])),
             error = function(e) NULL)
  }
  ph = header$prompt %||% ""
  ah = header$args %||% ""
  answer = attr(block_lines, "answer")
  if (length(answer) && !is.na(answer[1L])) {
    s2_put(s2_key(rel, res$block_id, "", ph, ah),
           list(block = res$block_id, doc = rel, part = "", prompt = ph, model = header$model,
                answer = answer[1L], usage = header$tokens, cost = header$cost,
                session = header$session, turn = header$turn, date = header$date))
  }
  kids = attr(block_lines, "children") %||% list()
  for (nm in names(kids)) {
    k = kids[[nm]]
    rec = list(block = res$block_id, doc = rel, part = nm, prompt = ph, model = k$model,
               answer = k$text %||% "", session = k$session, turn = k$turn %||% 1L,
               date = header$date, sent = k$sent)
    s2_put(s2_key(rel, res$block_id, nm, ph, ah), rec[!vapply(rec, is.null, NA)])
  }
  doc_source_log(site$path, res$block_id, if (isTRUE(site$regenerate)) "regenerated" else "ran")
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-blocks")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 173 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-blocks.R tests/testthat/test-doc-blocks.R
git commit -m "feat(doc): write blocks idempotently with consent, events, locks and md5 retries"
```

---

### Task 10: Deferred Rscript writes, Jupyter pending blocks and sidecar recovery

**Files:**
- Modify: `R/doc-io.R` (append)
- Test: `tests/testthat/test-doc-io.R` (append)

**Interfaces:**
- Consumes: Tasks 4, 6, 9 (`doc_state()`, `doc_root()`, `doc_rel()`, `doc_read_or_new()`, `doc_write()`,
  `doc_lock()`, `doc_unlock()`, `doc_lock_hold()`, `doc_lock_release_all()`, `doc_create_time()`,
  `doc_format_get()`, `doc_format_of()`, `doc_prepare()`, `doc_existing_status()`); P01 `save_rds(object, file,
  compress = FALSE)` (the one `saveRDS()`, `ascii = FALSE`), `msg_verbatim(x)`, `path_key()`, `gptr_inform()`,
  `gptr_warn()`, `gptr_abort()`; P04 `pid_alive()`; P06 `session_data()`; `cli::hash_sha1()`.
- Produces: `doc_sidecar_path(path)` (`<root>/cache/tmp/pending-<sha1(path_key(path))>.rds`, 04 §11.9),
  `doc_sidecar_read(path)`, `doc_sidecar_write(rec)` (removes the file when no upsert is left), `doc_sidecar_live(rec)`,
  `doc_pending_new(path, kind, session_id = NULL)` -> `list(doc, base_md5, upserts = list(), session, pid,
  create_time, time, kind)` (the IC-51 record plus `create_time` against pid reuse and `kind`: `"deferred"` or
  `"pending"`), `doc_finalizer_ensure()`, `doc_pending_add(fmt, site, up, kind)` (called by `doc_upsert()` for
  backends `"deferred"` and `"pending"`), `doc_apply_upserts(rec)` -> `list(applied, conflicts)` or `NULL` (locked),
  `doc_keep_conflicts(rec, res)`, `doc_pending_flush_all()` (the exit finalizer), `doc_recover(path, defer = FALSE)`
  (consumed by Tasks 13-15), `doc_notebook_attached(path)`, `doc_sync(path)` (consumed by `gptr_doc(sync = TRUE)`,
  Task 14).

Report 14 §2.1.2 (verified, items 6 and 7): rewriting a script that `Rscript` is running corrupts the run, so an
Rscript site queues its blocks and `reg.finalizer(onexit = TRUE)` writes them at exit (the finalizer runs at normal
exit, after an uncaught error and after `quit(runLast = FALSE)`). IC-51 adds the sidecar, written after each queued
upsert so a SIGTERM (which skips finalizers) loses at most the running call; the document is locked for the whole run
so array jobs that share a script record nothing. The next touch from any process applies a dead process's upserts
through the md5 and re-locate path: an upsert whose block the user edited, or whose call cannot be found, is a
conflict that stays in the sidecar (warning `doc_conflict`, never pruned automatically); an upsert whose call already
owns a fresh block is superseded; a later Rscript run of the same document adopts the dead upserts and writes them at
its own exit. A Jupyter site (IC-50) shows the block as a fenced code block in the cell output and keeps it pending;
only `doc_sync()` writes it, and never into the notebook this kernel has open.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-io.R`:

```r
# A located site for the first call with this prompt (as doc_locate() builds it)
doc_io_site = function(path, prompt, backend = "file") {
  fmt = doc_format_of(path)
  text = doc_read(path)$lines
  ph = prompt_hash(prompt)
  if (identical(fmt, "ipynb")) {
    anchor = list(ph = ph, th = NA_character_, j = 1L, block = NA_character_,
                  cell = nb_find_call_cell(nb_parse(text), ph))
  } else {
    calls = doc_calls(text)
    anchor = doc_anchor_of(calls, calls[which(calls$ph %in% ph)[1], ])
  }
  list(kind = "rscript", path = path_norm(path), format = fmt, backend = backend, anchor = anchor,
       prompt_hash = ph, args_hash = NULL, template = prompt, top_level = TRUE)
}

# Forget this process's pending documents and held locks when the test ends
local_doc_pending = function(.env = parent.frame()) {
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  }, envir = .env)
  invisible(st)
}

test_that("deferred blocks wait in a sidecar and are written when the process exits", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("library(gptr)", "gptr(\"count rows\")", "z = 1"), f)
  site = doc_io_site(f, "count rows", backend = "deferred")
  res = doc_upsert(site, structure("n = nrow(mtcars)", header = list(
    model = "fake/fake-1", date = "2026-09-29", prompt = prompt_hash("count rows"))))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "deferred")
  expect_identical(readLines(f), c("library(gptr)", "gptr(\"count rows\")", "z = 1"))
  side = doc_sidecar_path(f)
  expect_match(side, "[.]gptr/cache/tmp/pending-[0-9a-f]{40}[.]rds$")
  rec = readRDS(side)
  expect_identical(rec$pid, Sys.getpid())
  expect_identical(rec$kind, "deferred")
  expect_identical(rec$doc, path_norm(f))
  expect_identical(rec$upserts[[1]]$block_id, res$block_id)
  expect_true(isTRUE(st$finalizer))
  expect_true(dir.exists(doc_lock_dir(f)))
  doc_pending_flush_all()
  expect_identical(readLines(f)[3:5], c(paste0("# >>> gptr:", res$block_id, " model=fake/fake-1 ",
                                               "date=2026-09-29 prompt=",
                                               prompt_hash("count rows"), " sha=",
                                               doc_body_sha("n = nrow(mtcars)")),
                                        "n = nrow(mtcars)", paste0("# <<< gptr:", res$block_id)))
  expect_false(file.exists(side))
  expect_false(dir.exists(doc_lock_dir(f)))
})

test_that("a dead process's sidecar is recovered without overwriting a user edit (IC-51)", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  ph1 = prompt_hash("first")
  writeLines(c("gptr(\"first\")", paste0("# >>> gptr:aaaaaa model=m prompt=", ph1, " sha=0000aaaa"),
               "edited = TRUE", "# <<< gptr:aaaaaa", "gptr(\"second\")"), f)
  s1 = doc_io_site(f, "first")
  s2 = doc_io_site(f, "second")
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = 999999999L
  rec$upserts = list(
    list(block_id = "aaaaaa", lines = doc_render_block("aaaaaa", list(model = "m", prompt = ph1),
                                                       "x = 1"), site = s1),
    list(block_id = "bbbbbb", lines = doc_render_block("bbbbbb", list(
      model = "m", prompt = prompt_hash("second")), "y = 2"), site = s2))
  doc_sidecar_write(rec)
  expect_warning(expect_true(doc_recover(f)), class = "gptr_warning_doc_conflict")
  txt = readLines(f)
  expect_identical(txt[3], "edited = TRUE")
  expect_identical(txt[6:8], c(paste0("# >>> gptr:bbbbbb model=m prompt=", prompt_hash("second")),
                               "y = 2", "# <<< gptr:bbbbbb"))
  left = doc_sidecar_read(f)
  expect_identical(vapply(left$upserts, function(u) u$block_id, ""), "aaaaaa")
  rec$pid = Sys.getpid()
  doc_sidecar_write(rec)
  expect_false(doc_recover(f))
})

test_that("a run of the same document under Rscript adopts a dead sidecar until exit", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "aaaaaa", lines = doc_render_block("aaaaaa", list(
    model = "m", prompt = prompt_hash("first")), "x = 1"), site = doc_io_site(f, "first")))
  doc_sidecar_write(rec)
  expect_true(doc_recover(f, defer = TRUE))
  expect_identical(readLines(f), c("gptr(\"first\")", "gptr(\"second\")"))
  expect_identical(doc_sidecar_read(f)$pid, Sys.getpid())
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  doc_pending_flush_all()
  b = doc_find_blocks(readLines(f))
  expect_identical(b$id, c("aaaaaa", res$block_id))
  expect_null(doc_sidecar_read(f))
})

test_that("an open notebook is never written; its blocks wait for gptr_doc(sync = TRUE) (IC-50)", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(getwd(), "analysis.ipynb")
  file.copy(testthat::test_path("fixtures", "docs", "floats.ipynb"), nb)
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  site = doc_io_site(nb, "summarise the mpg column", backend = "pending")
  lines = doc_ipynb_render(list(id = "ignored", header = list(
    model = "fake/fake-1", prompt = prompt_hash("summarise the mpg column")),
    body = c("mean(x$mpg)", "## Decision: mean")), site)
  res = NULL
  out = cli::cli_fmt({
    res = doc_upsert(site, structure(as.character(lines), header = list(
      model = "fake/fake-1", prompt = prompt_hash("summarise the mpg column"))))
  })
  expect_identical(res$backend, "pending")
  expect_identical(out, c("```r", "mean(x$mpg)", "## Decision: mean", "```"))
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  expect_false(doc_recover(nb))
  expect_error(doc_sync(nb), class = "gptr_error_invalid_argument")
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  cells = nb_parse(doc_read(nb)$lines)$cells
  expect_identical(cells[[4]]$id, paste0("gptr-", res$block_id))
  expect_identical(unlist(cells[[4]]$source), c("mean(x$mpg)\n", "## Decision: mean"))
  expect_null(doc_sidecar_read(nb))
})

test_that("a deferred document locked by another live process records nothing", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("gptr(\"count rows\")", f)
  dir = doc_lock_dir(f)
  dir.create(dir, recursive = TRUE)
  writeLines(doc_lock_stamp(), file.path(dir, "pid"))
  withr::defer(unlink(dir, recursive = TRUE))
  res = NULL
  expect_message({
    res = doc_upsert(doc_io_site(f, "count rows", backend = "deferred"),
                     structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "locked")
  expect_null(doc_sidecar_read(f))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 45 ]`; the deferred upsert reaches the missing `doc_pending_add()`, falls back, and the first failure is ``Expected `res$action` to be identical to "insert"`` (`"failed"`), the other new tests fail on the missing `doc_sidecar_path()`, `doc_pending_new()` and `doc_sync()`.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-io.R`:

```r
# ---- deferred Rscript writes, Jupyter pending blocks and their sidecars (IC-50, IC-51) ----------

#' The sidecar of a document's deferred or pending upserts (contract 11.9):
#' `<root>/cache/tmp/pending-<sha1(path_key(doc path))>.rds`
#' @noRd
doc_sidecar_path = function(path) {
  file.path(doc_root(), "cache", "tmp", paste0("pending-", cli::hash_sha1(path_key(path)), ".rds"))
}

#' Read a document's sidecar record, or NULL
#' @noRd
doc_sidecar_read = function(path) {
  f = doc_sidecar_path(path)
  if (!file.exists(f)) return(NULL)
  rec = tryCatch(readRDS(f), error = function(e) NULL)
  if (is.list(rec) && is.list(rec$upserts)) rec else NULL
}

#' Write a sidecar record `list(doc, base_md5, upserts = list(list(block_id, lines, site)),
#' session, pid, create_time, time, kind)` (IC-51), or remove the file when no upsert is left
#' @noRd
doc_sidecar_write = function(rec) {
  f = doc_sidecar_path(rec$doc)
  if (!length(rec$upserts)) {
    if (file.exists(f)) unlink(f)
    return(invisible(NULL))
  }
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  save_rds(rec, f)
  invisible(f)
}

#' Does a sidecar belong to this process or to another live one?
#' @noRd
doc_sidecar_live = function(rec) {
  pid = suppressWarnings(as.integer(rec$pid))
  if (identical(pid, Sys.getpid())) return(TRUE)
  isTRUE(pid_alive(pid, create_time = rec$create_time))
}

#' A new pending record for a document
#' @noRd
doc_pending_new = function(path, kind, session_id = NULL) {
  list(doc = path, base_md5 = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_,
       upserts = list(), session = session_id, pid = Sys.getpid(),
       create_time = doc_create_time(), time = Sys.time(), kind = kind)
}

#' Register the exit finalizer that applies deferred writes (report 14 section 2.1.2: it runs at
#' normal exit, after an uncaught error and after quit(runLast = FALSE))
#' @noRd
doc_finalizer_ensure = function() {
  st = doc_state()
  if (!isTRUE(st$finalizer)) {
    reg.finalizer(st, function(e) doc_pending_flush_all(), onexit = TRUE)
    st$finalizer = TRUE
  }
  invisible(NULL)
}

#' Queue an upsert of a deferred (Rscript) or pending (Jupyter) document: the block is prepared
#' against the current text, kept in `the$doc_pending` and flushed to the sidecar at once
#' (IC-51: SIGTERM loses at most the call that was running); a deferred document is locked
#' until exit and a dead process's unapplied upserts are adopted first; a pending block is shown
#' as a fenced code block in the cell output (IC-50)
#' @noRd
doc_pending_add = function(fmt, site, up, kind) {
  st = doc_state()
  path = site$path
  key = path_key(path)
  none = list(action = "locked", block_id = NULL, lines = NULL, backend = kind)
  if (identical(kind, "deferred") && !doc_lock_hold(path)) {
    gptr_inform(paste0("Another R process is recording into ", doc_rel(path),
                       "; blocks of this run are not recorded."), "notice",
                .once = paste0("doc_locked:", key))
    return(none)
  }
  rec = st$docs[[key]]
  if (is.null(rec)) {
    sid = if (is.null(up$session)) NULL else session_data(up$session)$id
    rec = doc_pending_new(path, kind, sid)
    old = doc_sidecar_read(path)
    if (!is.null(old) && identical(old$kind, kind) && !doc_sidecar_live(old)) {
      rec$upserts = old$upserts
    }
  }
  doc = doc_read_or_new(path)
  taken = vapply(rec$upserts, function(u) u$block_id, "")
  prep = doc_prepare(fmt, site, up, doc$lines, taken = taken)
  if (!is.null(prep$skip)) {
    return(list(action = prep$skip, block_id = prep$id, lines = NULL, backend = kind))
  }
  same = vapply(rec$upserts, function(u) identical(u$block_id, prep$id), NA)
  rec$upserts = c(rec$upserts[!same],
                  list(list(block_id = prep$id, lines = prep$rendered, site = site)))
  rec$time = Sys.time()
  st$docs[[key]] = rec
  doc_sidecar_write(rec)
  if (identical(kind, "deferred")) doc_finalizer_ensure()
  if (identical(kind, "pending")) msg_verbatim(c("```r", as.character(prep$rendered), "```"))
  list(action = prep$action, block_id = prep$id, lines = NULL, backend = kind, sha = prep$sha,
       prompt = prep$prompt)
}

#' Apply queued upserts to the document under its lock, through the md5 check and re-locate
#' path (three attempts): a user-edited block or a call that cannot be found is a conflict and
#' is never overwritten; an upsert whose call already owns a fresh block is superseded. Returns
#' list(applied, conflicts), or NULL when another live process holds the lock.
#' @noRd
doc_apply_upserts = function(rec) {
  path = rec$doc
  ups = rec$upserts
  ids = vapply(ups, function(u) u$block_id, "")
  if (!length(ups)) return(list(applied = character(), conflicts = character()))
  fname = ups[[1L]]$site$format %||% doc_format_of(path)
  fmt = doc_format_get(fname)
  if (is.null(fmt)) return(list(applied = character(), conflicts = ids))
  lock = doc_lock(path)
  if (is.null(lock)) return(NULL)
  on.exit(doc_unlock(lock), add = TRUE)
  for (attempt in 1:3) {
    doc = doc_read_or_new(path)
    text = doc$lines
    applied = character()
    conflicts = character()
    for (u in ups) {
      status = doc_existing_status(fname, text, u$block_id)
      if (identical(status, "user-edited")) {
        conflicts = c(conflicts, u$block_id)
        next
      }
      if (is.na(status)) {
        loc = tryCatch(fmt$locate(text, u$site), error = function(e) NULL)
        if (!is.null(loc$owned) && identical(loc$owned$status, "fresh")) {
          applied = c(applied, u$block_id)
          next
        }
      }
      new = tryCatch(fmt$upsert(text, u$site, u$lines, u$block_id),
                     gptr_error_doc_write = function(e) NULL)
      if (is.null(new)) {
        conflicts = c(conflicts, u$block_id)
      } else {
        text = new
        applied = c(applied, u$block_id)
      }
    }
    if (identical(text, doc$lines)) return(list(applied = applied, conflicts = conflicts))
    ok = tryCatch({
      doc_write(doc, text)
      TRUE
    }, gptr_error_doc_write = function(e) {
      if (identical(e$reason, "conflict")) FALSE else stop(e)
    })
    if (ok) return(list(applied = applied, conflicts = conflicts))
  }
  list(applied = character(), conflicts = ids)
}

#' Keep only the conflicting upserts of a record in its sidecar (they are never pruned
#' automatically, IC-51) and warn about them once per document and set of blocks
#' @noRd
doc_keep_conflicts = function(rec, res) {
  rec$upserts = Filter(function(u) u$block_id %in% res$conflicts, rec$upserts)
  doc_sidecar_write(rec)
  if (length(res$conflicts)) {
    gptr_warn(paste0("gptr did not overwrite ", doc_rel(rec$doc), ": block(s) ",
                     paste(res$conflicts, collapse = ", "), " changed or their call was not ",
                     "found. They stay in ", doc_rel(doc_sidecar_path(rec$doc)),
                     "; see gptr_cache(\"info\")."), "doc_conflict",
              .once = paste0("doc_conflict:", path_key(rec$doc), ":",
                             paste(res$conflicts, collapse = ",")))
  }
  invisible(rec)
}

#' Apply this process's deferred writes and release its document locks (the exit finalizer)
#' @noRd
doc_pending_flush_all = function() {
  st = doc_state()
  for (key in names(st$docs)) {
    rec = st$docs[[key]]
    if (!identical(rec$kind, "deferred")) next
    res = tryCatch(doc_apply_upserts(rec), error = function(e) NULL)
    if (!is.null(res)) doc_keep_conflicts(rec, res)
    st$docs[[key]] = NULL
  }
  doc_lock_release_all()
  invisible(NULL)
}

#' Recover the deferred upserts a dead process left in a document's sidecar (IC-51): applied
#' now through the md5 and re-locate path, or, when this process runs the document under Rscript
#' (`defer = TRUE`), adopted into this process's deferred writes. Pending notebook blocks are
#' applied only by gptr_doc(path, sync = TRUE).
#' @noRd
doc_recover = function(path, defer = FALSE) {
  rec = doc_sidecar_read(path)
  if (is.null(rec) || !identical(rec$kind, "deferred") || doc_sidecar_live(rec)) {
    return(invisible(FALSE))
  }
  if (defer) {
    if (!doc_lock_hold(path)) return(invisible(FALSE))
    st = doc_state()
    key = path_key(path)
    own = st$docs[[key]] %||% doc_pending_new(path, "deferred", rec$session)
    own_ids = vapply(own$upserts, function(u) u$block_id, "")
    adopted = Filter(function(u) !u$block_id %in% own_ids, rec$upserts)
    own$upserts = c(adopted, own$upserts)
    st$docs[[key]] = own
    doc_sidecar_write(own)
    doc_finalizer_ensure()
    return(invisible(TRUE))
  }
  res = doc_apply_upserts(rec)
  if (is.null(res)) return(invisible(FALSE))
  doc_keep_conflicts(rec, res)
  invisible(TRUE)
}

#' Is this notebook open in the Jupyter kernel of this process? (IC-50: never written then)
#' @noRd
doc_notebook_attached = function(path) {
  jpy = Sys.getenv("JPY_SESSION_NAME")
  isTRUE(getOption("jupyter.in_kernel")) && nzchar(jpy) &&
    identical(path_key(jpy), path_key(path))
}

#' Apply the pending (Jupyter) and unapplied deferred upserts of a document now
#' (`gptr_doc(path, sync = TRUE)`); returns the number of blocks applied, invisibly
#' @noRd
doc_sync = function(path) {
  st = doc_state()
  key = path_key(path)
  rec = st$docs[[key]] %||% doc_sidecar_read(path)
  if (is.null(rec) || !length(rec$upserts)) return(invisible(0L))
  if (doc_notebook_attached(path)) {
    gptr_abort(c(paste0(doc_rel(path), " is the notebook this Jupyter kernel runs; gptr never ",
                        "writes an open notebook."),
                 paste0("Close it and run gptr_doc(\"", doc_rel(path), "\", sync = TRUE) from ",
                        "another R session.")), "invalid_argument", arg = "sync",
               expected = "a notebook that is not open in this kernel")
  }
  res = doc_apply_upserts(rec)
  if (is.null(res)) {
    gptr_inform(paste0("Another R process is writing ", doc_rel(path), "; nothing was synced."),
                "notice")
    return(invisible(0L))
  }
  doc_keep_conflicts(rec, res)
  st$docs[[key]] = NULL
  invisible(length(res$applied))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 77 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-io.R tests/testthat/test-doc-io.R
git commit -m "feat(doc): defer Rscript writes to exit with a recoverable sidecar; keep notebook blocks pending"
```

---

### Task 11: The IDE backend and transcript appends

**Files:**
- Modify: `R/doc-io.R` (append)
- Test: `tests/testthat/test-doc-io.R` (append)

**Interfaces:**
- Consumes: Tasks 4, 7-9 (`doc_ide_context()`, `doc_read()`, `doc_read_or_new()`, `doc_write()`, `doc_lock()`,
  `doc_unlock()`, `doc_rel()`, `doc_consent()`, `doc_event()`, `doc_prepare()`, `doc_file_upsert()`,
  `doc_block_range()`, `doc_format_of()`); P01 `path_norm()`, `path_key()`, `as_utf8()`, `gptr_inform()`;
  rstudioapi (Suggests; report 14 §3.9 signatures: `document_range(start, end = NULL)`, `document_position(row,
  column)`, `modifyRange(location = NULL, text = NULL, id = NULL)`, `documentSave(id = NULL)`,
  `setCursorPosition(position, id = NULL)`, `hasFun(name, ...)`).
- Produces: `doc_ide_edit_range(old, new)` -> `list(start = c(row, col), end = c(row, col), text)`,
  `doc_ide_modify(edit, id)`, `doc_ide_save(id)`, `doc_ide_cursor(row, id)`, `doc_ide_upsert(fmt, site, up)` (called
  by `doc_upsert()` for backends `"rstudio"`, `"positron"`, `"vscode"`), `doc_transcript_append(path, lines, session =
  NULL)` (consumed by Task 13's `session_tree` hook and console-channel handlers).

Report 14 §4.3: RStudio and VS Code (sess) edit a buffer by document id through `modifyRange()` (undoable), save it
when it was clean and move the cursor past the block, so the next Ctrl+Enter does not re-run code the agent already
ran; Positron's shims accept only `id = NULL` (the active editor, which may be the console since positron#16063), so
a clean Positron buffer is written on disk (Positron reloads clean editors) and a dirty one is edited only after the
context is re-checked; a `"#console"` context or another file is never edited. The range arithmetic of the report
(verified against a mock of rstudioapi's range semantics, item 31) is generalised to the smallest replacement turning
the buffer into the new text; the test applies every edit with those semantics.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-io.R`:

```r
# rstudioapi range semantics on a buffer (1-based rows and columns; Inf clamps to the line end,
# a row past the end clamps to the end of the buffer): replace the range with `text`
doc_apply_range = function(buffer, edit) {
  txt = paste(buffer, collapse = "\n")
  starts = cumsum(c(1L, nchar(buffer) + 1L))
  offset = function(pos) {
    row = min(pos[1L], max(1L, length(buffer)))
    if (!length(buffer)) return(0L)
    line_len = nchar(buffer[row])
    col = if (is.infinite(pos[2L])) line_len + 1L else min(pos[2L], line_len + 1L)
    if (pos[1L] > length(buffer)) col = line_len + 1L
    as.integer(starts[row] + col - 2L)
  }
  a = offset(edit$start)
  b = offset(edit$end)
  out = paste0(substr(txt, 1L, a), edit$text, substring(txt, b + 1L))
  parts = strsplit(paste0(out, "\001"), "\n", fixed = TRUE)[[1L]]
  sub("\001$", "", parts)
}

# A fake editor holding one buffer; the rstudioapi wrappers of doc-io.R are mocked onto it
local_fake_editor = function(path, contents, id = "doc1", .env = parent.frame()) {
  ed = new.env()
  ed$buffer = contents
  ed$saved = character()
  ed$cursor = NA_integer_
  ed$ids = list()
  testthat::local_mocked_bindings(
    doc_ide_context = function() {
      list(id = id, path = path, contents = ed$buffer, selection = list())
    },
    doc_ide_modify = function(edit, id) {
      ed$ids = c(ed$ids, list(id))
      ed$buffer = doc_apply_range(ed$buffer, edit)
      invisible(TRUE)
    },
    doc_ide_save = function(id) {
      ed$saved = c(ed$saved, if (is.null(id)) "<active>" else id)
      writeLines(ed$buffer, path)
      invisible(NULL)
    },
    doc_ide_cursor = function(row, id) {
      ed$cursor = as.integer(row)
      invisible(NULL)
    },
    .env = .env)
  ed
}

doc_ide_site = function(path, prompt, backend) {
  calls = doc_calls(readLines(path, encoding = "UTF-8"))
  ph = prompt_hash(prompt)
  list(kind = "ide", path = path_norm(path), format = "r", backend = backend,
       anchor = doc_anchor_of(calls, calls[which(calls$ph %in% ph)[1], ]), prompt_hash = ph,
       args_hash = NULL, template = prompt, top_level = TRUE)
}

test_that("the IDE range arithmetic reproduces every edit", {
  cases = list(
    list(c("a", "b", "c"), c("a", "X", "Y", "b", "c")),
    list(c("a", "b", "c"), c("a", "b", "c", "X")),
    list(c("a", "b", "c"), c("X", "a", "b", "c")),
    list(c("a", "b", "c"), c("a", "c")),
    list(c("a", "b", "c"), c("a", "b")),
    list(c("a", "b", "c"), c("a", "Q", "c")),
    list(c("a"), c("a", "b")),
    list(character(), c("a", "b")),
    list(c("a", "b"), c("a", "b")))
  for (cs in cases) {
    edit = doc_ide_edit_range(cs[[1]], cs[[2]])
    expect_identical(doc_apply_range(cs[[1]], edit), cs[[2]])
  }
})

test_that("RStudio buffers are edited by id, saved when clean, the cursor moved past the block", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("x = 1", "gptr(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), readLines(f))
  res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"),
                   structure("n = nrow(mtcars)", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "rstudio")
  expect_identical(ed$buffer[3:5], c(paste0("# >>> gptr:", res$block_id, " model=m sha=",
                                            doc_body_sha("n = nrow(mtcars)")),
                                     "n = nrow(mtcars)", paste0("# <<< gptr:", res$block_id)))
  expect_identical(ed$ids[[1]], "doc1")
  expect_identical(ed$saved, "doc1")
  expect_identical(ed$cursor, 6L)
  expect_identical(readLines(f), ed$buffer)
})

test_that("Positron writes a clean buffer on disk and edits only the active editor", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), readLines(f), id = "")
  res = doc_upsert(doc_ide_site(f, "count rows", "positron"),
                   structure("n = 1", header = list(model = "m")))
  expect_identical(res$backend, "file")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f)[3], "n = 1")
  ed$buffer = c("# unsaved edit", readLines(f))
  res2 = doc_upsert(utils::modifyList(doc_ide_site(f, "count rows", "positron"),
                                      list(regenerate = TRUE)),
                    structure("n = 2", header = list(model = "m")), block_id = res$block_id)
  expect_identical(res2$backend, "positron")
  expect_null(ed$ids[[1]])
  expect_identical(ed$buffer[4], "n = 2")
  expect_length(ed$saved, 0L)
})

test_that("a console-focused or foreign editor is never edited", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  ed = local_fake_editor(path_norm(f), readLines(f), id = "#console")
  res = NULL
  expect_message({
    res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"), structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "none")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f), "gptr(\"count rows\")")
})

test_that("transcript appends need consent and pass the document_write event", {
  proj = local_project()
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  local_gptr_options(record = "off")
  expect_false(doc_transcript_append(t, "# /model opus"))
  expect_false(file.exists(t))
  local_gptr_options(record = "auto")
  expect_true(doc_transcript_append(t, "# /model opus"))
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    if (identical(event$kind, "transcript")) list(lines = toupper(event$lines)) else NULL
  }))
  expect_true(doc_transcript_append(t, c("# direct R (no model)", "x = 1")))
  off()
  expect_identical(readLines(t), c("# /model opus", "# DIRECT R (NO MODEL)", "X = 1"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 77 ]`, starting with ``Error in `doc_ide_edit_range(cs[[1]], cs[[2]])`: could not find function "doc_ide_edit_range"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-io.R`:

```r
# ---- the IDE backend (report 14 section 4.3: RStudio and VS Code by id, Positron's active
# editor) and transcript appends ----------------------------------------------------------------

#' The smallest line-range replacement turning buffer `old` into `new`, in rstudioapi
#' coordinates: list(start = c(row, col), end = c(row, col), text) (report 14 section 4.3 range
#' arithmetic; `Inf` columns clamp to the end of a line)
#' @noRd
doc_ide_edit_range = function(old, new) {
  n_old = length(old)
  n_new = length(new)
  p = 0L
  while (p < n_old && p < n_new && identical(old[p + 1L], new[p + 1L])) p = p + 1L
  s = 0L
  while (s < n_old - p && s < n_new - p && identical(old[n_old - s], new[n_new - s])) s = s + 1L
  ins = if (n_new - s > p) new[(p + 1L):(n_new - s)] else character()
  from = p + 1L
  to = n_old - s
  joined = paste(ins, collapse = "\n")
  if (to >= from) {
    if (to < n_old) {
      return(list(start = c(from, 1), end = c(to + 1L, 1),
                  text = if (length(ins)) paste0(joined, "\n") else ""))
    }
    if (length(ins) || from == 1L) {
      return(list(start = c(from, 1), end = c(n_old, Inf), text = joined))
    }
    return(list(start = c(from - 1L, Inf), end = c(n_old, Inf), text = ""))
  }
  if (!length(ins)) return(list(start = c(1, 1), end = c(1, 1), text = ""))
  if (n_old == 0L) return(list(start = c(1, 1), end = c(1, 1), text = joined))
  if (p < n_old) return(list(start = c(from, 1), end = c(from, 1), text = paste0(joined, "\n")))
  list(start = c(n_old, Inf), end = c(n_old, Inf), text = paste0("\n", joined))
}

#' Apply an edit range through rstudioapi (`id = NULL`: the active editor, Positron's only target)
#' @noRd
doc_ide_modify = function(edit, id) {
  loc = rstudioapi::document_range(rstudioapi::document_position(edit$start[1L], edit$start[2L]),
                                   rstudioapi::document_position(edit$end[1L], edit$end[2L]))
  rstudioapi::modifyRange(loc, edit$text, id = id)
  invisible(TRUE)
}

#' Save an IDE buffer when the API supports it
#' @noRd
doc_ide_save = function(id) {
  if (isTRUE(tryCatch(rstudioapi::hasFun("documentSave"), error = function(e) FALSE))) {
    tryCatch(rstudioapi::documentSave(id), error = function(e) NULL)
  }
  invisible(NULL)
}

#' Move the cursor past a written block, so the next Ctrl+Enter does not re-run code the agent
#' already ran (report 14 section 4.3)
#' @noRd
doc_ide_cursor = function(row, id) {
  if (isTRUE(tryCatch(rstudioapi::hasFun("setCursorPosition"), error = function(e) FALSE))) {
    tryCatch(rstudioapi::setCursorPosition(rstudioapi::document_position(row, 1), id = id),
             error = function(e) NULL)
  }
  invisible(NULL)
}

#' Upsert through the editor buffer: RStudio and VS Code edit by document id and save a buffer
#' that was clean; Positron edits only the active editor, so a clean buffer is written on disk
#' (Positron reloads it) and the console context ("#console") is never edited
#' @noRd
doc_ide_upsert = function(fmt, site, up) {
  backend = site$backend
  ctx = doc_ide_context()
  if (is.null(ctx) || identical(ctx$id, "#console") || !nzchar(ctx$path %||% "") ||
      !identical(path_key(path_norm(ctx$path)), path_key(site$path))) {
    gptr_inform(paste0("gptr could not reach ", doc_rel(site$path), " in the editor; save it and ",
                       "run the call again to record its block."), "notice",
                .once = paste0("doc_ide:", path_key(site$path)))
    return(list(action = "none", block_id = NULL, lines = NULL, backend = backend))
  }
  buffer = as_utf8(as.character(ctx$contents))
  disk = if (file.exists(site$path)) doc_read(site$path)$lines else NULL
  clean = identical(buffer, disk)
  if (clean && identical(backend, "positron")) {
    site$backend = "file"
    return(doc_file_upsert(fmt, site, up))
  }
  prep = doc_prepare(fmt, site, up, buffer)
  if (!is.null(prep$skip)) {
    return(list(action = prep$skip, block_id = prep$id, lines = NULL, backend = backend))
  }
  new = fmt$upsert(buffer, site, prep$rendered, prep$id)
  if (identical(new, buffer)) {
    return(list(action = "unchanged", block_id = prep$id, lines = NULL, backend = backend))
  }
  id = if (identical(backend, "positron")) NULL else ctx$id
  doc_ide_modify(doc_ide_edit_range(buffer, new), id)
  if (clean) doc_ide_save(id)
  rng = doc_block_range(site$format, new, prep$id)
  if (length(rng)) doc_ide_cursor(rng[2L] + 1L, id)
  list(action = prep$action, block_id = prep$id, lines = rng, backend = backend, sha = prep$sha,
       prompt = prep$prompt)
}

#' Append lines to a console transcript (direct R lines, slash commands, rewind notes) under
#' write consent, the `document_write` event (kind "transcript") and the document lock
#' @noRd
doc_transcript_append = function(path, lines, session = NULL) {
  if (!doc_consent(path, ask = FALSE)) return(invisible(FALSE))
  ev = doc_event(path, doc_format_of(path) %||% "r", "transcript", NULL, lines, session)
  if (isTRUE(ev$block)) return(invisible(FALSE))
  lines = ev$lines %||% lines
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lock = doc_lock(path)
  if (is.null(lock)) return(invisible(FALSE))
  on.exit(doc_unlock(lock), add = TRUE)
  doc = doc_read_or_new(path)
  doc_write(doc, c(doc$lines, as.character(lines)))
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 109 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-io.R tests/testthat/test-doc-io.R
git commit -m "feat(doc): write blocks through the RStudio, VS Code and Positron editors; append transcripts"
```

---

### Task 12: Replay decisions and replaying fresh blocks

**Files:**
- Modify: `R/doc-replay.R` (append)
- Test: `tests/testthat/test-doc-replay.R` (append)

**Interfaces:**
- Consumes: Tasks 1-9 (`doc_block_status()`, `doc_rel()`, `doc_read()`, `doc_find_blocks()`, `doc_block_body()`,
  `nb_parse()`, `nb_cell_ids()`, `nb_cell_lines()`, `doc_state()`, `doc_source_log()`, `s2_key()`, `s2_get()`); P01
  `check_choice()`, `gptr_abort()`, `gptr_warn()`, `gptr_can_prompt()`, `gptr_confirm()`; P06 (kernel SDK,
  IC-46): `session_replay_apply(s, block, header, text = NULL)` ("advances the piped session in place: `gptr.replay`
  entry, `seen`, `turns`, the `value=` name, `last_text`; returns `s`"), `session_replay_new(block, header, envir,
  doc)` ("the live session with the header's id, else a `replayed` session adopting the recorded id, from the JSONL
  or reconstructed from the document"; `header` is the parsed block header plus `doc` and `mode`, `doc` is
  `list(path, format, template, code, output, text)`), `session_replay_bind(block, s, child = NULL)`; P08 (kernel
  SDK) `route_pass()`; the `gptr_call` bindings `session`, `envir`, `template`, `prompt`, `doc` (P08). Task 16's
  `doc_knitr_skip(label)` is called by name for knitr drivers only (both files are area `doc`).
- Produces (04 §7.15): `doc_decide(site, prompt_hash, args_hash, mode)` -> `"replay"`, `"run"`, `"regenerate"` or
  `"skip"`, or signals `gptr_error_not_recorded` (`document`, `prompt`) / `gptr_error_stale_block` (`document`,
  `block`), with the warning `gptr_warning_replay_downgraded` where base `source()`/Rscript cannot skip the old block;
  `doc_skip_old(site)`, `doc_block_text(site, block_id)`, `doc_replay_doc(site, call, block_id, text = NULL)`,
  `doc_replay_header(header, site, mode)`, `doc_replay_call(call, site, mode = "replay")` -> the session (IC-46),
  `doc_run_block_nested(call, site, mode)` -> a replayed session from S2 or `route_pass()` (IC-47),
  `doc_replay_team(call, site, mode)` -> the replayed team or fan-out session (IC-47).

The decision table is architecture §6.9.3 (`live` = "ask afresh and regenerate", `record` = "regenerate stale
blocks"), report 14 §4.4.2 (a user-edited block wins in `auto` and `replay`, and asks before it is overwritten) and
the undone row of G7 §3.8; a block is fresh only when both `prompt=` and `args=` match (IC-45). `gptr()` never runs
a recorded block: replay returns a session with zero requests and the document's own code runs next (report 14
§4.4.1). Team and fan-out replay builds one replayed child per `children=` entry from its S2 text, each in a fresh
overlay of the caller's environment (so `local({...}, envir = gptr_resume(block =, child =)$envir)` never writes the
caller's frame), binds them with `session_replay_bind(block, child, child = name)`, then replays the team session
itself and binds it to the block.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-replay.R`:

```r
# A located site whose call owns a block in the given state (as doc_locate() builds it)
doc_decide_site = function(status = "fresh", driver = "base", prompt = "p", args = NULL) {
  header = list(model = "fake/fake-1", prompt = prompt_hash(prompt), args = args)
  header = header[!vapply(header, is.null, NA)]
  if (identical(status, "undone")) header$status = "undone"
  list(path = file.path(getwd(), "a.R"), format = "r", driver = driver, template = prompt,
       block = list(id = "abc123", header = header, status = status))
}

# A file with one top-level call and its block; returns the located site of that call
doc_replay_fixture = function(prompt = "count rows", header = list(), body = "n = nrow(mtcars)") {
  f = file.path(getwd(), "a.R")
  h = utils::modifyList(list(model = "fake/fake-1", date = "2026-09-29",
                             prompt = prompt_hash(prompt), session = "s0a1b2c3d4e", turn = 1L),
                        header)
  writeLines(c(paste0("res = gptr(\"", prompt, "\")"), doc_render_block("abc123", h, body)), f)
  calls = doc_calls(readLines(f))
  site = list(kind = "srcref", path = path_norm(f), format = "r", backend = "file",
              driver = "base", template = prompt, prompt_hash = prompt_hash(prompt),
              args_hash = NULL, anchor = doc_anchor_of(calls, calls[1, ]))
  loc = doc_text_locate(readLines(f), site)
  site$block = loc$owned
  site$top_level = TRUE
  site
}

# A call record as P08 builds it (only the bindings P15 reads)
doc_test_call = function(session = NULL, envir = new.env(), prompt = "count rows") {
  call = new.env(parent = emptyenv())
  call$session = session
  call$envir = envir
  call$template = prompt
  call$prompt = prompt
  call$args = list(replay = NULL)
  call$doc = NULL
  call
}

test_that("doc_decide() follows the replay table, the args hash and the undone row", {
  local_project()
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "auto"), "replay")
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "replay"), "replay")
  expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "record"), "replay")
  expect_identical(doc_decide(doc_decide_site(driver = "gptr_source"), prompt_hash("p"), NULL,
                              "live"), "regenerate")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "live"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  expect_identical(doc_decide(doc_decide_site(driver = "knitr"), prompt_hash("q"), NULL, "auto"),
                   "regenerate")
  expect_error(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "replay"),
               class = "gptr_error_stale_block")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "auto"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  expect_warning(expect_identical(doc_decide(doc_decide_site(), prompt_hash("q"), NULL, "record"),
                                  "replay"), class = "gptr_warning_replay_downgraded")
  a = doc_decide_site(args = "aaaa1111")
  expect_identical(doc_decide(a, prompt_hash("p"), "aaaa1111", "auto"), "replay")
  expect_error(doc_decide(a, prompt_hash("p"), "bbbb2222", "replay"),
               class = "gptr_error_stale_block")
  none = doc_decide_site()
  none$block = NULL
  expect_identical(doc_decide(none, prompt_hash("p"), NULL, "auto"), "run")
  cnd = expect_error(doc_decide(none, prompt_hash("p"), NULL, "replay"),
                     class = "gptr_error_not_recorded")
  expect_identical(cnd$prompt, "p")
  u = doc_decide_site("undone", driver = "gptr_source")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "auto"), "skip")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "replay"), "skip")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "live"), "run")
  expect_identical(doc_decide(u, prompt_hash("p"), NULL, "record"), "regenerate")
  e = doc_decide_site("user-edited", driver = "gptr_source")
  expect_identical(doc_decide(e, prompt_hash("p"), NULL, "auto"), "replay")
  local_gptr_options(interactive = FALSE)
  expect_warning(expect_identical(doc_decide(e, prompt_hash("p"), NULL, "record"), "replay"),
                 class = "gptr_warning_replay_downgraded")
  expect_error(doc_decide(none, prompt_hash("p"), NULL, "sometimes"),
               class = "gptr_error_invalid_argument")
})

test_that("a piped session is advanced in place; identical() holds along a replayed chain", {
  local_project()
  site = doc_replay_fixture()
  s = session_new("fake/fake-1", "auto", home = new.env())
  call = doc_test_call(session = s)
  out = doc_replay_call(call, site)
  expect_identical(out, s)
  expect_identical(session_data(s)$seen, "abc123")
  expect_identical(session_data(s)$turns, 1L)
  expect_null(call$doc)
  again = doc_replay_call(doc_test_call(session = s), site)
  expect_identical(again, s)
  expect_identical(session_data(s)$turns, 1L)
})

test_that("without a piped session the replayed session is reconstructed from the document", {
  local_project()
  site = doc_replay_fixture(header = list(value = "n"),
                            body = c("n = nrow(mtcars)", "#> [1] 32", "## Decision: count"))
  rel = doc_rel(site$path)
  s2_put(s2_key(rel, "abc123", "", prompt_hash("count rows"), ""),
         list(block = "abc123", doc = rel, part = "", answer = "There are 32 rows."))
  env = new.env()
  s = doc_replay_call(doc_test_call(envir = env), site)
  d = session_data(s)
  expect_identical(d$id, "s0a1b2c3d4e")
  expect_identical(d$last_text, "There are 32 rows.")
  expect_identical(d$history_source, "reconstructed")
  msgs = lapply(Filter(function(e) identical(e$type, "message"), d$entries), function(e) e$message)
  expect_identical(msg_text(msgs[[1]]), "count rows")
  expect_identical(msgs[[2]]$content[[1]]$arguments$code, "n = nrow(mtcars)")
  expect_identical(msg_text(msgs[[3]]), "[1] 32")
  expect_identical(msg_text(msgs[[4]]), "There are 32 rows.")
  env$n = 32L
  expect_identical(s$value, 32L)
})

test_that("a fork block is bound to its id for gptr_resume(block =)", {
  local_project()
  site = doc_replay_fixture(header = list(fork = "s0a1b2c3d4e:1", session = "s9f8e7d6c5b"))
  home = new.env()
  s = doc_replay_call(doc_test_call(envir = home), site)
  expect_identical(gptr_resume(block = "abc123"), s)
  expect_false(identical(gptr_resume(block = "abc123")$envir, home))
  expect_identical(parent.env(gptr_resume(block = "abc123")$envir), home)
})

test_that("block-nested calls replay from S2 and miss with not_recorded only under replay", {
  local_project()
  f = file.path(getwd(), "a.R")
  ph = prompt_hash("outer")
  writeLines(c("gptr(\"outer\")", paste0("# >>> gptr:abc123 model=m prompt=", ph),
               "sub = gptr(\"inner\")", "# <<< gptr:abc123"), f)
  site = list(path = path_norm(f), format = "r", in_block = "abc123", ordinal = 1L,
              template = "inner")
  expect_s3_class(doc_run_block_nested(doc_test_call(), site, "auto"), "gptr_route_pass")
  expect_error(doc_run_block_nested(doc_test_call(), site, "replay"),
               class = "gptr_error_not_recorded")
  s2_put(s2_key("a.R", "abc123", "n1", ph, ""),
         list(block = "abc123", doc = "a.R", part = "n1", model = "fake/fake-1",
              answer = "inner answer", session = "s1111111111", turn = 1L))
  s = doc_run_block_nested(doc_test_call(), site, "replay")
  expect_identical(session_data(s)$last_text, "inner answer")
  expect_identical(session_data(s)$id, "s1111111111")
  s2_put(s2_key("a.R", "abc123", "n1", ph, ""),
         list(block = "abc123", doc = "a.R", part = "n1", model = "fake/fake-1",
              answer = "inner answer", session = "s1111111111", turn = 1L,
              sent = prompt_hash("inner")))
  again = doc_run_block_nested(doc_test_call(prompt = "inner"), site, "replay")
  expect_identical(session_data(again)$last_text, "inner answer")
  expect_error(doc_run_block_nested(doc_test_call(prompt = "another prompt"), site, "replay"),
               class = "gptr_error_not_recorded")
  expect_s3_class(doc_run_block_nested(doc_test_call(), site, "live"), "gptr_route_pass")
})

test_that("a team block replays its children from S2 into overlays, with zero requests", {
  local_project()
  site = doc_replay_fixture(prompt = "Review", header = list(
    kind = "team", session = "s7777777777", children = "code:s2222222222,stats:s3333333333"))
  ph = prompt_hash("Review")
  s2_put(s2_key("a.R", "abc123", "code", ph, ""),
         list(block = "abc123", doc = "a.R", part = "code", model = "openai/gpt-5.5",
              answer = "Two bugs.", session = "s2222222222", turn = 1L))
  s2_put(s2_key("a.R", "abc123", "stats", ph, ""),
         list(block = "abc123", doc = "a.R", part = "stats", model = "anthropic/claude-opus-5-5",
              answer = "Looks fine.", session = "s3333333333", turn = 1L))
  env = new.env()
  team = doc_replay_team(doc_test_call(envir = env, prompt = "Review"), site, "replay")
  code = gptr_resume(block = "abc123", child = "code")
  expect_identical(session_data(code)$last_text, "Two bugs.")
  expect_identical(parent.env(code$envir), env)
  expect_identical(session_data(gptr_resume(block = "abc123", child = "stats"))$id, "s3333333333")
  expect_identical(gptr_resume(block = "abc123"), team)
  expect_match(session_data(team)$last_text, "### code (openai/gpt-5.5)\nTwo bugs.", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 26 ]`, the new tests failing with ``Error in `doc_decide(doc_decide_site(), prompt_hash("p"), NULL, "auto")`: could not find function "doc_decide"`` and the like.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-replay.R`:

```r
# ---- replay decisions and replaying fresh blocks (IC-45, IC-46, IC-47) -------------------------

#' The replay decision for a located call (contract 7.15): "replay", "run", "regenerate" or
#' "skip", or signals `not_recorded`/`stale_block`. The table of architecture 6.9.3 and report 14
#' section 4.4.2 with the undone row of G7 section 3.8: a block is fresh only when its `prompt=`
#' and `args=` both match (IC-45). Regeneration needs a driver that can skip the old block
#' (gptr_source(), knitr, an IDE, Jupyter); under base source()/Rscript it downgrades to replay
#' with the warning `replay_downgraded` in every mode (architecture 6.9.3: "under base
#' source()/Rscript, live and stale regeneration downgrade to replay with a warning").
#' @noRd
doc_decide = function(site, prompt_hash, args_hash, mode) {
  mode = check_choice(mode, c("auto", "replay", "live", "record"), "mode")
  b = site$block
  rel = doc_rel(site$path)
  state = if (is.null(b)) {
    "none"
  } else if ((b$status %||% "") %in% c("undone", "user-edited")) {
    b$status
  } else {
    doc_block_status(b$header[setdiff(names(b$header), "sha")], character(), prompt_hash,
                     args_hash)
  }
  can_regen = !identical(site$driver %||% "base", "base")
  regen = function() {
    if (can_regen) return("regenerate")
    gptr_warn(paste0("Block ", b$id, " of ", rel, " was not regenerated: under source() or ",
                     "Rscript the recorded code runs anyway, so it was replayed. Use ",
                     "gptr_source() or run the call interactively to regenerate it."),
              "replay_downgraded")
    "replay"
  }
  switch(state,
    none = {
      if (identical(mode, "replay")) {
        gptr_abort(c(paste0("The gptr() call in ", rel, " has no recorded block and replay mode ",
                            "is on."), "Run it once with replay = \"auto\" to record it."),
                   "not_recorded", document = site$path,
                   prompt = substr(site$template %||% "", 1L, 60L))
      }
      "run"
    },
    undone = switch(mode, auto = , replay = "skip", live = "run", record = regen()),
    `user-edited` = {
      if (mode %in% c("auto", "replay")) return("replay")
      question = paste0("Block ", b$id, " of ", rel, " was edited by hand. Overwrite it?")
      if (gptr_can_prompt() && isTRUE(gptr_confirm(question))) return(regen())
      gptr_warn(paste0("Block ", b$id, " of ", rel, " was edited by hand and was not ",
                       "regenerated; the edited code ran."), "replay_downgraded")
      "replay"
    },
    stale = {
      if (identical(mode, "replay")) {
        gptr_abort(c(paste0("Block ", b$id, " of ", rel, " is stale: its prompt or interpolated ",
                            "values changed since it was recorded."),
                     "Run with replay = \"auto\" or \"record\" to regenerate it."), "stale_block",
                   document = site$path, block = b$id)
      }
      regen()
    },
    if (identical(mode, "live")) regen() else "replay")
}

#' Skip the old block of a regenerated call in the running driver: gptr_source() skips its
#' top-level expressions, knitr its chunk (scoped label hook)
#' @noRd
doc_skip_old = function(site) {
  id = site$block$id
  if (is.null(id)) return(invisible(NULL))
  if (identical(site$driver, "gptr_source")) {
    st = doc_state()
    n = length(st$sources)
    fr = st$sources[[n]]
    fr$skip = union(fr$skip, id)
    st$sources[[n]] = fr
  } else if (identical(site$driver, "knitr")) {
    doc_knitr_skip(paste0("gptr-", id))
  }
  invisible(NULL)
}

#' Body lines of a block as written in the document (empty when it cannot be read)
#' @noRd
doc_block_text = function(site, block_id) {
  tryCatch({
    text = doc_read(site$path)$lines
    if (identical(site$format, "ipynb")) {
      nb = nb_parse(text)
      k = match(paste0("gptr-", block_id), nb_cell_ids(nb))
      if (is.na(k)) character() else nb_cell_lines(nb$cells[[k]])
    } else {
      b = doc_find_blocks(text)
      k = which(b$id == block_id)
      if (length(k)) doc_block_body(text, b[k[1L], , drop = FALSE]) else character()
    }
  }, error = function(e) character())
}

#' What a replayed session reconstructs its history from (IC-46; P06's `doc` argument):
#' list(path, format, template, code, output, text)
#' @noRd
doc_replay_doc = function(site, call, block_id, text = NULL) {
  body = doc_block_text(site, block_id)
  outs = grepl("^[ \t]*#>", body)
  list(path = site$path, format = site$format,
       template = site$template %||% call$template %||% call$prompt,
       code = body[!outs & !grepl("^[ \t]*#", body) & nzchar(trimws(body))],
       output = sub("^[ \t]*#> ?", "", body[outs]), text = text)
}

#' The header P06's replay functions receive: the block header plus `doc` and `mode`
#' @noRd
doc_replay_header = function(header, site, mode) {
  utils::modifyList(header, list(doc = doc_rel(site$path), mode = mode))
}

#' Replay a fresh block (IC-46): the piped session advanced in place, else a replayed session
#' (the live one holding the header's id, the JSONL cut at the recorded turn, or the history
#' reconstructed from the document); a fork block is bound to its id for gptr_resume(block =)
#' @noRd
doc_replay_call = function(call, site, mode = "replay") {
  b = site$block
  h = b$header
  rel = doc_rel(site$path)
  rec = s2_get(s2_key(rel, b$id, "", h$prompt %||% "", h$args %||% ""))
  header = doc_replay_header(h, site, mode)
  s = if (!is.null(call$session)) {
    session_replay_apply(call$session, b$id, header, text = rec$answer)
  } else {
    session_replay_new(b$id, header, call$envir,
                       doc = doc_replay_doc(site, call, b$id, rec$answer))
  }
  if (!is.null(h$fork)) session_replay_bind(b$id, s)
  doc_source_log(site$path, b$id, "replayed")
  assign("doc", NULL, envir = call)
  s
}

#' A gptr() statement directly inside an agent block (IC-47): replayed from S2 under (document,
#' block, "n<ordinal>") in `auto`, `record` and `replay` (a miss under `replay` errors
#' `not_recorded`), run live otherwise; it is never recorded. A cached answer whose `sent`
#' prompt hash differs from this call's prompt is a miss.
#' @noRd
doc_run_block_nested = function(call, site, mode) {
  assign("doc", NULL, envir = call)
  if (identical(mode, "live")) return(route_pass())
  rel = doc_rel(site$path)
  parent = tryCatch({
    b = doc_find_blocks(doc_read(site$path)$lines)
    k = which(b$id == site$in_block)
    if (length(k)) b$header[[k[1L]]] else list()
  }, error = function(e) list())
  rec = s2_get(s2_key(rel, site$in_block, paste0("n", site$ordinal), parent$prompt %||% "",
                      parent$args %||% ""))
  asked = call$prompt %||% call$template %||% site$template
  if (!is.null(rec$sent) && is.character(asked) && length(asked) == 1L &&
      !identical(rec$sent, prompt_hash(asked))) {
    rec = NULL
  }
  if (is.null(rec)) {
    if (identical(mode, "replay")) {
      gptr_abort(c(paste0("The gptr() call inside block ", site$in_block, " of ", rel,
                          " has no cached answer and replay mode is on."),
                   "Run the document once with replay = \"auto\" to cache it."), "not_recorded",
                 document = site$path, prompt = substr(site$template %||% "", 1L, 60L))
    }
    return(route_pass())
  }
  header = list(model = rec$model, session = rec$session, turn = as.character(rec$turn %||% 1L),
                doc = rel, mode = mode)
  doc = list(path = site$path, format = site$format, template = site$template,
             code = character(), output = character(), text = rec$answer)
  if (!is.null(call$session)) {
    return(session_replay_apply(call$session, paste0(site$in_block, "/n", site$ordinal), header,
                                text = rec$answer))
  }
  session_replay_new(paste0(site$in_block, "/n", site$ordinal), header, call$envir, doc = doc)
}

#' Replay a fresh team or fan-out block (IC-47): one replayed child per `children=` entry, with
#' its cached S2 text, in a fresh overlay of the caller's environment, bound to (block, child)
#' for gptr_resume(block =, child =); then the team session itself, bound to the block. Zero
#' requests.
#' @noRd
doc_replay_team = function(call, site, mode) {
  b = site$block
  h = b$header
  rel = doc_rel(site$path)
  pairs = strsplit(strsplit(h$children %||% "", ",", fixed = TRUE)[[1L]], ":", fixed = TRUE)
  texts = character()
  for (kv in pairs) {
    if (length(kv) != 2L) next
    rec = s2_get(s2_key(rel, b$id, kv[1L], h$prompt %||% "", h$args %||% ""))
    child_header = list(model = rec$model %||% h$model, session = kv[2L],
                        turn = as.character(rec$turn %||% 1L), doc = rel, mode = mode)
    overlay = new.env(parent = call$envir)
    child = session_replay_new(paste0(b$id, "/", kv[1L]), child_header, overlay,
                               doc = list(path = site$path, format = site$format,
                                          template = site$template, code = character(),
                                          output = character(), text = rec$answer))
    session_replay_bind(b$id, child, child = kv[1L])
    texts = c(texts, paste0("### ", kv[1L], " (", rec$model %||% h$model, ")\n",
                            rec$answer %||% ""))
  }
  team = session_replay_new(b$id, doc_replay_header(h, site, mode), call$envir,
                            doc = doc_replay_doc(site, call, b$id,
                                                 paste(texts, collapse = "\n\n")))
  session_replay_bind(b$id, team)
  doc_source_log(site$path, b$id, "replayed")
  assign("doc", NULL, envir = call)
  team
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 80 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-replay.R tests/testthat/test-doc-replay.R
git commit -m "feat(doc): decide replay per mode and replay fresh blocks, forks, nested calls and teams"
```

---

### Task 13: `builtin:documents`: the route, the section, the hooks and the services

**Files:**
- Modify: `R/doc-replay.R` (append: route, services, hooks)
- Modify: `R/doc-formats.R` (append: `doc_set_inert()`, the section, `builtin_documents()` and its declarations)
- Test: `tests/testthat/test-doc-replay.R` (append), `tests/testthat/test-doc-formats.R` (append)

**Interfaces:**
- Consumes: Tasks 1-12; P01 `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`,
  `ext_service_has()`, `gptr_can_prompt()`, `redact()`; P02 `ext_declare_builtin(name, factory, after = character(),
  replaceable = TRUE)`, the factory API object (`gptr$register(spec)`, `gptr$on(event, handler, matcher = NULL)`,
  04 §10.5), `gptr_spec("route", "document", order, match, run, description)` (kind `route`: "`order`; `match`
  `function(call)` -> lgl(1); `run` `function(call)` -> value or `route_pass()`"), `gptr_prompt_section(name, text,
  tier, order, budget, parent = NULL)`, `gptr_tool_result(text, ..., details, is_error)`, `registry_get("tool",
  "edit")` (P10's edit tool, IC-37: `execute(input, ctx)`), `registry_diagnostic()`; P06 `session_live(s)` (`run`,
  `ctx`), `session_append()`, `run_current()` (a `gptr_run`; its read-only `opts$doc` is the running call's site);
  P08 `replay_mode(arg = NULL)`, `route_pass()`. Event payloads (04 §10.4): `agent_end` `status`, `reason`, `usage`,
  `doc` (the run's `opts$doc`, i.e. the site), `turns`; `session_tree` `from`, `to`, `report`. P14's notify channels
  for transcript writers (04 §10.4 `<plugin>:<topic>` channels; P14 Global Constraints "Events emitted", Task 6
  `console_command()`, Task 5 `repl_passthrough()` and its ambiguities 3-4): `console:command` with `data =
  list(text)` (a slash command line that passed the `input` event, source `repl`, unhandled and is still a command;
  its text after any transform) and `console:direct` with `data = list(code, output, status, noted)` (a direct R
  line `!expr` after it ran, `output` its printed lines). P14 dispatches the 04 §10.4 `input` event (sources `repl`
  and `passthrough`) before each of them; P15 does not record from `input` (ambiguity 11). The handler's
  `ctx$session` is the session (P02).
- Produces (04 §7.15, §7.0): `builtin_documents(gptr)` (formats, route `document` order 50, section `documents`,
  hooks on `agent_end`, `session_tree`, `console:command`, `console:direct`), declared with
  `on_load(ext_declare_builtin("documents", builtin_documents))`; the services `doc.site` =
  `doc_site_service(session)`, `doc.edit` = `doc_edit_service(path, edits, session)`, `doc.s1_block` =
  `doc_s1_block_service(call, summary)`, `doc.replay` = `doc_replay_service(call)`, each `ext_service_set(...,
  provided_by = "P15", builtin = "documents")` (IC-34); the route functions `doc_route_match(call)`,
  `doc_route_run(call)`; the hooks `doc_on_agent_end(event, ctx)`, `doc_on_session_tree(event, ctx)`,
  `doc_on_console_command(event, ctx)`, `doc_on_console_direct(event, ctx)`; helpers `doc_console_append(lines,
  session = NULL)`, `doc_edit_blocks()`, `doc_refresh_headers()`, `doc_s1_summary(x)`, `doc_ancestors()`,
  `doc_set_inert(path, ids, inert = TRUE, session = NULL, transcript = NULL)`, `doc_section_body`,
  `doc_section_text(ctx)`.

The route runs for every `gptr()` call that reaches order 50 (IC-39). `match()` locates the call (never for calls
made from model code, `run_current()` non-`NULL`), asks once per project where to record a console session when a
human can answer, recovers a dead process's deferred writes for that document (IC-51) and keeps the site in
`call$doc`. `run()` replays a fresh block (no consent needed), skips an undone one with a notice, marks a stale or
re-asked one for regeneration (the old block is skipped by `gptr_source()` or knitr), and otherwise passes with
`call$doc` set only when the call may be recorded (consent exists or can be asked, and the mode is not `replay`).
P08's `gateway_run()` hands `call$doc` to the run as `opts$doc`, P06 returns it in the `agent_end` payload, and the
hook writes the block of a run that ended `idle`. `doc.edit` routes an `edit` of the bound document through the
registered edit tool (answering `NULL` while that tool runs, so it is not re-entered), refuses to change a block the
user edited, and refreshes the date and sha of the blocks the agent changed (04 §7.10: P15 consumes the edit; the
documents section asks the model to edit earlier blocks). `doc.site` answers the session's replayed document, the
site of its run, and, when called without a session (P10's `gptr$edit()` member passes `session = NULL`), the site of
the innermost running call (`run_current()$opts$doc`), then the `gptr_doc()` binding (ignored once its directory no
longer exists). `doc.s1_block` writes the one-line block of a top-level System 1 call. `doc.replay` lets P19's `team`
and `fanout` routes (orders 15, 16) replay a fresh team block (IC-47). The `session_tree` hook makes the blocks of
abandoned turns inert and revives redone ones (G7 §3.8, §4.4), appending `gptr.doc_block` entries with action
`undone`/`replace` (a console transcript's `s_<hex>` statement is made inert with its block). The handlers of P14's
`console:command` and `console:direct` channels append slash commands as comments and direct R lines under
`# direct R (no model)` with their `#>` output to the console transcript (IC-49, 04 §11.5 transcript row).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-formats.R`:

```r
test_that("builtin:documents registers the formats, the route, the section and the services", {
  for (nm in c("r", "rmd", "qmd", "ipynb", "transcript")) {
    expect_s3_class(registry_get("doc_format", nm), "gptr_doc_format")
  }
  route = registry_get("route", "document")
  expect_identical(route$order, 50)
  expect_true(is.function(route$match) && is.function(route$run))
  sec = registry_get("prompt_section", "documents")
  expect_identical(sec$tier, "T0")
  expect_identical(sec$order, 500L)
  expect_identical(sec$budget, 250L)
  for (svc in c("doc.site", "doc.edit", "doc.s1_block", "doc.replay")) {
    expect_true(ext_service_has(svc))
  }
})

test_that("the documents section is the text of architecture 7.3 and needs a bound document", {
  expect_null(doc_section_text(list(input = list(document = NULL))))
  txt = doc_section_text(list(input = list(document = list(path = "a.R", format = "r"))))
  expect_identical(txt, paste0(
    "Code from successful r calls is written into the user's document (named in <environment>) ",
    "in a block below the gptr() call that asked for it, so the document re-runs from top to ",
    "bottom. Therefore:\n- Make recorded code the clean final version: named objects, no ",
    "exploratory prints. Pass record = false for throwaway checks (head(), summaries, tests).\n",
    "- Record key modelling decisions with note (one line, written as \"## Decision: ...\"); key ",
    "printed outputs are added as #> comments automatically.\n- To change code you wrote earlier, ",
    "edit that block in the document instead of appending a second version.\n- In the document, ",
    "prompts are quoted strings in gptr(\"...\"), and System 1 decisions are gptr(..., model = ",
    "{s1}) inside if, for or while. Add such calls only when the user asks for an agent step in ",
    "the script."))
})

test_that("blocks are made inert on disk and revived, through the document_write event", {
  local_project()
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  writeLines(c("gptr(\"p\")", seg), f)
  local_gptr_options(record = "off")
  expect_false(doc_set_inert(f, "abc123"))
  local_gptr_options(record = "auto")
  hits = new.env()
  hits$kinds = character()
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    hits$kinds = c(hits$kinds, event$kind)
    NULL
  }))
  expect_true(doc_set_inert(f, "abc123"))
  expect_identical(readLines(f)[3], "#~ x = 1")
  expect_match(readLines(f)[2], "status=undone")
  expect_true(doc_set_inert(f, "abc123", inert = FALSE))
  expect_identical(readLines(f), c("gptr(\"p\")", seg))
  off()
  expect_identical(hits$kinds, c("inert", "inert"))
  # a console transcript kept in an ordinary .R file: its s_<hex> statement goes inert too
  g = file.path(getwd(), "console.R")
  writeLines(c("s_ab12cd = gptr(\"p\")", seg), g)
  expect_true(doc_set_inert(g, "abc123", transcript = TRUE))
  expect_identical(readLines(g)[1], "#~ s_ab12cd = gptr(\"p\")")
})
```

Append to `tests/testthat/test-doc-replay.R`:

```r
# A session with recorded turns, built the way P06 records them: the turn counter moves first,
# then the turn's entries are appended (user messages carry their turn number)
doc_test_session = function(turns, mode = "auto", kind = "chat", home = new.env()) {
  s = session_new("fake/fake-1", mode, home = home, kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, outputs = character(), prompt = "count rows",
                         answer = "There are 32 rows.", id = "call_1") {
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call(id, "r", list(code = code))), api = "fake", provider = "fake",
      model = "fake-1", stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      id, "r", "ok", details = list(code = code, status = "ok", outputs = outputs))),
    list(type = "message", message = msg_assistant(answer, api = "fake", provider = "fake",
                                                   model = "fake-1"))
  )
}

# An environment whose gptr() builds the call record as P08 does and runs only the document
# route: it returns the route's value, or list(pass = TRUE, doc = <call$doc>) when it passes
doc_route_env = function(session = NULL) {
  e = new.env()
  e$gptr = function(prompt, ..., replay = NULL) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = session
    call$envir = parent.frame()
    call$args = list(replay = replay)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (!doc_route_match(call)) return(list(pass = TRUE, matched = FALSE, doc = NULL))
    res = doc_route_run(call)
    if (inherits(res, "gptr_route_pass")) return(list(pass = TRUE, matched = TRUE, doc = call$doc))
    res
  }
  e
}

test_that("the route replays a fresh block, passes a new call with its site, skips nested ones", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("fresh = gptr(\"count rows\")",
               paste0("# >>> gptr:abc123 model=fake/fake-1 prompt=", ph,
                      " session=s0a1b2c3d4e turn=1"),
               "n = 32", "# <<< gptr:abc123", "new = gptr(\"plot it\")",
               "f = function() gptr(\"inside\")", "inner = f()"), f)
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_s3_class(e$fresh, "gptr_session")
  expect_identical(session_data(e$fresh)$id, "s0a1b2c3d4e")
  expect_identical(e$n, 32)
  expect_true(e$new$pass)
  expect_identical(e$new$doc$path, path_norm(f))
  expect_identical(e$new$doc$prompt_hash, prompt_hash("plot it"))
  expect_false(e$inner$matched)
})

test_that("without consent or under replay the route keeps no site; replay needs no consent", {
  local_project()
  local_gptr_options(record = "off", interactive = FALSE, replay = "auto")
  f = file.path(getwd(), "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("fresh = gptr(\"count rows\")",
               paste0("# >>> gptr:abc123 model=fake/fake-1 prompt=", ph), "n = 32",
               "# <<< gptr:abc123", "new = gptr(\"plot it\")"), f)
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_s3_class(e$fresh, "gptr_session")
  expect_true(e$new$pass)
  expect_null(e$new$doc)
  local_gptr_options(record = "auto", replay = "replay")
  e2 = doc_route_env()
  source(f, local = e2, keep.source = TRUE)
  expect_null(e2$new$doc)
})

test_that("a stale block regenerates under gptr_source() and errors under replay", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("s = gptr(\"count rows again\")",
               paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count rows")),
               "n = 32", "# <<< gptr:abc123"), f)
  e = doc_route_env()
  withr::with_options(list(gptr.replay = "replay"), {
    expect_error(source(f, local = e, keep.source = TRUE), class = "gptr_error_stale_block")
  })
  depth = doc_source_push(f)
  withr::defer(doc_source_pop(depth))
  local_gptr_options(replay = "auto")
  source(f, local = e, keep.source = TRUE)
  expect_true(e$s$pass)
  expect_true(e$s$doc$regenerate)
  expect_identical(e$s$doc$block_id, "abc123")
  expect_identical(doc_state()$sources[[depth]]$skip, "abc123")
})

test_that("calls made from model code never match the route", {
  local_project()
  f = file.path(getwd(), "analysis.R")
  writeLines("x = gptr(\"count rows\")", f)
  testthat::local_mocked_bindings(run_current = function() new.env())
  e = doc_route_env()
  source(f, local = e, keep.source = TRUE)
  expect_false(e$x$matched)
})

test_that("agent_end writes the block of an idle run with a document site", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)", outputs = "[1] 32")))
  calls = doc_calls(readLines(f))
  site = list(kind = "srcref", path = path_norm(f), format = "r", backend = "file",
              anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = prompt_hash("count rows"),
              args_hash = NULL, template = "count rows", ordinal = 1L)
  doc_on_agent_end(list(status = "error", doc = site, turns = 1L), list(session = s))
  expect_identical(readLines(f), "gptr(\"count rows\")")
  doc_on_agent_end(list(status = "idle", doc = site, turns = 1L), list(session = s))
  txt = readLines(f)
  expect_identical(txt[3:4], c("n = nrow(mtcars)", "#> [1] 32"))
  expect_match(txt[2], paste0("session=", session_data(s)$id, " turn=1"), fixed = TRUE)
  doc_on_agent_end(list(status = "idle", doc = NULL, turns = 1L), list(session = s))
  expect_identical(readLines(f), txt)
})

test_that("console turns become one steered session in the transcript (IC-49)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  s = doc_test_session(list(doc_test_turn("fit = lm(mpg ~ wt, data = mtcars)", prompt = "fit"),
                            doc_test_turn("p = predict(fit)", prompt = "predict")))
  for (k in 1:2) {
    site = doc_console_site(session_id = session_data(s)$id,
                            template = c("fit", "predict")[k])
    doc_on_agent_end(list(status = "idle", doc = site, turns = k), list(session = s))
  }
  tr = readLines(file.path(proj, ".gptr", "transcripts", "t.R"))
  hex = substr(sub("^s", "", session_data(s)$id), 1, 6)
  expect_true(paste0("s_", hex, " = gptr(\"fit\")") %in% tr)
  expect_true(paste0("s_", hex, " |> gptr(\"predict\")") %in% tr)
  expect_identical(sum(grepl("^# >>> gptr:", tr)), 2L)
})

test_that("doc.site answers the session's run site, else the gptr_doc() binding", {
  local_project()
  expect_null(doc_site_service(NULL))
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  bound = file.path(getwd(), "a.R")
  the$doc_binding = list(path = bound, format = "r")
  expect_identical(doc_site_service(NULL), list(path = bound, format = "r"))
  the$doc_binding = list(path = file.path(getwd(), "gone", "a.R"), format = "r")
  expect_null(doc_site_service(NULL))
  run = new.env()
  run$opts = list(doc = list(path = "/p/b.Rmd", format = "rmd"))
  testthat::local_mocked_bindings(session_live = function(s) list(run = run))
  s = doc_test_session(list())
  expect_identical(doc_site_service(s), list(path = "/p/b.Rmd", format = "rmd"))
  # P10's gptr$edit() member passes no session: the running call's site answers
  outer = new.env()
  outer$opts = list(doc = list(path = "/p/c.R", format = "r"))
  testthat::local_mocked_bindings(run_current = function() outer)
  expect_identical(doc_site_service(NULL), list(path = "/p/c.R", format = "r"))
})

test_that("doc.edit goes through the edit tool, refreshes headers and protects hand edits", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  h = list(model = "m", date = "2020-01-01", prompt = "p", sha = doc_body_sha(body))
  writeLines(c("gptr(\"p\")", doc_render_block("abc123", h, body), "y = 2"), f)
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = list(path = path_norm(f), format = "r")
  hits = new.env()
  hits$seen = character()
  edit_exec = function(input, ctx) {
    hits$seen = c(hits$seen, "execute")
    inner = doc_edit_service(input$path, input$edits, NULL)
    if (!is.null(inner)) return(inner)
    txt = readLines(input$path)
    for (e in input$edits) txt = sub(e$oldText, e$newText, txt, fixed = TRUE)
    writeLines(txt, input$path)
    gptr_tool_result("Successfully replaced text.")
  }
  off = gptr_register(gptr_spec("tool", "edit", description = "A test edit tool",
                                execute = edit_exec))
  withr::defer(off())
  expect_null(doc_edit_service(file.path(getwd(), "other.R"), list(), NULL))
  res = doc_edit_service(f, list(list(oldText = "x = 1", newText = "x = 2")), NULL)
  expect_false(res$is_error)
  expect_identical(hits$seen, "execute")
  b = doc_find_blocks(readLines(f))
  expect_identical(b$header[[1]]$sha, doc_body_sha("x = 2"))
  expect_identical(b$header[[1]]$date, format(Sys.Date(), "%Y-%m-%d"))
  txt = readLines(f)
  txt[3] = "x = 99 # mine"
  writeLines(txt, f)
  res2 = doc_edit_service(f, list(list(oldText = "x = 99", newText = "x = 3")), NULL)
  expect_true(res2$is_error)
  expect_identical(readLines(f)[3], "x = 99 # mine")
})

test_that("doc.s1_block writes one #> line below a top-level System 1 call, idempotently", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("is_rct = gptr(\"Is this an RCT?\", abstracts, model = jev)", "table(is_rct)"), f)
  x = structure(c(TRUE, FALSE, TRUE), class = c("gptr_decision", "gptr_s1", "logical"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  e = new.env()
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_s1_block_service(call, x)
    x
  }
  source(f, local = e, keep.source = TRUE)
  txt = readLines(f)
  expect_identical(txt[3], "#> gptr_decision: 2 TRUE / 1 FALSE (jev-1.13.0, 2026-09-29)")
  expect_match(txt[2], "model=jev-1.13.0 date=2026-09-29", fixed = TRUE)
  source(f, local = e, keep.source = TRUE)
  expect_identical(readLines(f), txt)
  expect_identical(doc_s1_summary(structure(c("liver", "lung", "liver"),
                                            class = c("gptr_choice", "gptr_s1", "character"),
                                            meta = list(model = "jev", date = "2026-09-29"))),
                   "gptr_choice: liver 2, lung 1 (jev, 2026-09-29)")
})

test_that("doc.replay returns the replayed team of a fresh block and NULL otherwise (IC-47)", {
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  f = file.path(getwd(), "a.R")
  ph = prompt_hash("Review")
  writeLines(c("reviews = gptr(\"Review\")", paste0("# >>> gptr:abc123 model=m prompt=", ph,
                                                    " session=s7777777777 turn=1 kind=team",
                                                    " children=\"code:s2222222222\""),
               "## Agent code (openai/gpt-5.5): Two bugs.", "# <<< gptr:abc123",
               "again = gptr(\"Review two\")"), f)
  s2_put(s2_key("a.R", "abc123", "code", ph, ""),
         list(block = "abc123", doc = "a.R", part = "code", model = "openai/gpt-5.5",
              answer = "Two bugs.", session = "s2222222222", turn = 1L))
  e = new.env()
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$args = list(replay = NULL)
    call$envir = parent.frame()
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    list(out = doc_replay_service(call), doc = call$doc)
  }
  source(f, local = e, keep.source = TRUE)
  expect_identical(session_data(e$reviews$out)$id, "s7777777777")
  expect_identical(session_data(gptr_resume(block = "abc123", child = "code"))$last_text,
                   "Two bugs.")
  expect_null(e$again$out)
  expect_identical(e$again$doc$prompt_hash, prompt_hash("Review two"))
})

test_that("a rewind makes abandoned blocks inert and notes it in the console transcript", {
  proj = local_project()
  local_gptr_options(record = "auto")
  f = file.path(proj, "a.R")
  body = "x = 1"
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  writeLines(c("gptr(\"p\")", seg), f)
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  doc_project_transcript(".gptr/transcripts/t.R")
  dir.create(dirname(t), recursive = TRUE)
  writeLines("library(gptr)", t)
  s = doc_test_session(list(doc_test_turn("x = 1", prompt = "p")))
  root = session_data(s)$leaf
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = "a.R", format = "r", block = "abc123", action = "insert",
                                     backend = "file")))
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = ".gptr/transcripts/t.R", format = "transcript",
                                     block = "def456", action = "insert",
                                     backend = "transcript")))
  from = session_data(s)$leaf
  doc_on_session_tree(list(from = from, to = root, report = c("restored x", "y not restored")),
                      list(session = s))
  expect_identical(readLines(f)[3], "#~ x = 1")
  expect_identical(utils::tail(readLines(t), 1),
                   paste0("# /rewind: 1 items restored or removed, 1 not restored (session log ",
                          root, ")"))
  ents = session_data(s)$entries
  expect_identical(ents[[length(ents)]]$data$action, "undone")
})

test_that("direct R lines and slash commands of the console enter the transcript", {
  proj = local_project()
  local_gptr_options(record = "auto")
  doc_project_transcript(".gptr/transcripts/t.R")
  # the payloads of P14's console:direct and console:command channels
  expect_null(doc_on_console_direct(list(data = list(
    code = "summary(fit)$r.squared", output = "[1] 0.7528", status = "ok", noted = TRUE)),
    list(session = NULL)))
  expect_null(doc_on_console_command(list(data = list(text = "/model opus")),
                                     list(session = NULL)))
  doc_on_console_command(list(data = list(text = "  ")), list(session = NULL))
  doc_on_console_direct(list(data = list(code = "", output = character())), list(session = NULL))
  expect_identical(readLines(file.path(proj, ".gptr", "transcripts", "t.R")),
                   c("", "# direct R (no model)", "summary(fit)$r.squared", "#> [1] 0.7528",
                     "# /model opus"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats|doc-replay")'`

Expected: `[ FAIL 29 | WARN 0 | SKIP 0 | PASS 179 ]` (the two files together), starting with ``Expected `registry_get("doc_format", nm)` to be an S3 object`` and ``could not find function "doc_route_match"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-replay.R`:

```r
# ---- the `document` route (IC-45..IC-47) ------------------------------------------------------

#' The route's match(): a call located in a document (top-level, or directly inside an agent
#' block), or a console call with a transcript target; never a call made from model code.
#' Recovers a dead process's deferred writes for that document first (IC-51) and keeps the site
#' in `call$doc` for run().
#' @noRd
doc_route_match = function(call) {
  if (!is.null(run_current())) return(FALSE)
  site = doc_locate(call)
  if (is.null(site) && gptr_can_prompt()) {
    s = call$session
    labels = vapply(call$context %||% list(), function(x) {
      if (identical(x$kind, "symbol")) x$name %||% "" else ""
    }, "")
    site = doc_console_site(session_id = if (is.null(s)) NULL else session_data(s)$id,
                            template = call$template %||% call$prompt,
                            context_labels = labels[nzchar(labels)], ask = TRUE)
  }
  if (is.null(site) || is.null(site$path)) return(FALSE)
  if (!isTRUE(site$top_level) && is.null(site$in_block)) return(FALSE)
  doc_recover(site$path, defer = identical(site$backend, "deferred"))
  assign("doc", site, envir = call)
  TRUE
}

#' The route's run(): replay a fresh block (no write consent needed), skip an undone one,
#' regenerate a stale one, or pass with `call$doc` set when the call may be recorded (IC-45)
#' @noRd
doc_route_run = function(call) {
  site = call$doc
  mode = replay_mode(call$args$replay)
  keep = function(s) {
    ok = !is.null(s) && !identical(mode, "replay") && doc_consent_possible(s$path)
    assign("doc", if (ok) s else NULL, envir = call)
    route_pass()
  }
  if (isTRUE(site$console)) return(keep(site))
  if (!is.null(site$in_block)) return(doc_run_block_nested(call, site, mode))
  if (is.null(site$block)) return(keep(site))
  decision = doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (identical(decision, "replay")) return(doc_replay_call(call, site, mode))
  if (identical(decision, "skip")) {
    gptr_inform(paste0("Block ", site$block$id, " of ", doc_rel(site$path), " was undone by ",
                       "/rewind; edit or delete the prompt, or run live to regenerate it."),
                "notice")
    doc_source_log(site$path, site$block$id, "skipped")
    assign("doc", NULL, envir = call)
    return(invisible(call$session))
  }
  if (identical(decision, "regenerate")) {
    site$regenerate = TRUE
    site$block_id = site$block$id
    doc_skip_old(site)
    return(keep(site))
  }
  assign("doc", NULL, envir = call)
  route_pass()
}

# ---- services (contract 7.0; owned by builtin:documents, IC-34) --------------------------------

#' doc.site: the document a session records into (its replayed block's document, the site of
#' its current run; without a session, as P10's gptr$edit() member calls it, the site of the
#' innermost running call), else the process binding of gptr_doc() while its directory exists,
#' as list(path, format), or NULL
#' @noRd
doc_site_service = function(session) {
  if (!is.null(session)) {
    d = session_data(session)
    if (!is.null(d$doc$path)) return(list(path = d$doc$path, format = d$doc$format))
    run = session_live(session)$run
    site = if (is.null(run)) NULL else run$opts$doc
    if (!is.null(site$path)) return(list(path = site$path, format = site$format))
  } else {
    run = run_current()
    site = if (is.null(run)) NULL else run$opts$doc
    if (!is.null(site$path)) return(list(path = site$path, format = site$format))
  }
  b = the$doc_binding
  if (is.null(b$path) || !dir.exists(dirname(b$path))) return(NULL)
  list(path = b$path, format = b$format)
}

#' Ids of the blocks whose lines an edit's `oldText` touches
#' @noRd
doc_edit_blocks = function(lines, blocks, edits) {
  if (!nrow(blocks) || !is.list(edits)) return(character())
  joined = paste(lines, collapse = "\n")
  starts = cumsum(c(1L, nchar(lines) + 1L))
  hit = character()
  for (e in edits) {
    old = as_utf8(e$oldText %||% "")
    if (!nzchar(old)) next
    pos = regexpr(old, joined, fixed = TRUE)
    if (pos < 0L) next
    first = findInterval(as.integer(pos), starts)
    last = findInterval(as.integer(pos) + nchar(old) - 1L, starts)
    k = which(blocks$end >= first & blocks$start <= last)
    hit = c(hit, blocks$id[k])
  }
  unique(hit)
}

#' Refresh `date` and `sha` of the blocks whose body an agent edit changed, so the edit is not
#' later taken for a user edit
#' @noRd
doc_refresh_headers = function(lines, old_blocks, old_lines) {
  blocks = doc_find_blocks(lines)
  for (k in seq_len(nrow(blocks))) {
    b = blocks[k, , drop = FALSE]
    body = doc_block_body(lines, b)
    o = which(old_blocks$id == b$id)
    if (length(o) &&
        identical(body, doc_block_body(old_lines, old_blocks[o[1L], , drop = FALSE]))) {
      next
    }
    h = b$header[[1L]]
    h$date = format(Sys.Date(), "%Y-%m-%d")
    h$sha = doc_body_sha(body)
    lines[b$start] = paste0(b$indent, "# >>> gptr:", b$id, " ", doc_format_kv(h))
  }
  lines
}

#' doc.edit: an `edit` of the session's bound document goes through the registered edit tool
#' (the service answers NULL while that tool runs, so it is not re-entered), refuses to change
#' a block the user edited by hand, and refreshes the headers of the blocks it changed; NULL for
#' any other file (contract 7.0, 7.10)
#' @noRd
doc_edit_service = function(path, edits, session) {
  st = doc_state()
  if (isTRUE(st$in_edit)) return(NULL)
  full = path_norm(path)
  site = doc_site_service(session)
  if (is.null(site) || !identical(path_key(site$path), path_key(full)) || !file.exists(full) ||
      identical(site$format, "ipynb")) {
    return(NULL)
  }
  spec = registry_get("tool", "edit")
  if (is.null(spec) || !is.function(spec$execute)) return(NULL)
  before = doc_read(full)
  blocks = doc_find_blocks(before$lines)
  for (id in doc_edit_blocks(before$lines, blocks, edits)) {
    if (identical(doc_existing_status("r", before$lines, id), "user-edited")) {
      return(gptr_tool_result(paste0("Block ", id, " of ", doc_rel(full), " was edited by hand; ",
                                     "it was left unchanged. Ask the user before rewriting it."),
                              details = list(path = full, document = TRUE), is_error = TRUE))
    }
  }
  st$in_edit = TRUE
  on.exit({
    st$in_edit = FALSE
  }, add = TRUE)
  ctx = if (is.null(session)) NULL else session_live(session)$ctx
  res = spec$execute(list(path = path, edits = edits), ctx)
  if (isTRUE(res$is_error)) return(res)
  after = doc_read(full)
  new = doc_refresh_headers(after$lines, blocks, before$lines)
  if (!identical(new, after$lines)) doc_write(after, new)
  res
}

#' One-line summary of a System 1 vector (contract 11.5): `gptr_decision: 14 TRUE / 6 FALSE
#' (jev-1.13.0, 2026-09-29)`, `gptr_choice: liver 8, lung 5, other 2 (...)`, `gptr_score: mean
#' 1.4 (...)`
#' @noRd
doc_s1_summary = function(x) {
  meta = attr(x, "meta") %||% list()
  tail = paste0(" (", meta$model %||% "unknown", ", ", meta$date %||% format(Sys.Date()), ")")
  v = unclass(x)
  attributes(v) = NULL
  if (inherits(x, "gptr_decision")) {
    parts = c(paste(sum(v %in% TRUE), "TRUE"), paste(sum(v %in% FALSE), "FALSE"))
    if (any(is.na(v))) parts = c(parts, paste(sum(is.na(v)), "NA"))
    return(paste0("gptr_decision: ", paste(parts, collapse = " / "), tail))
  }
  if (inherits(x, "gptr_choice")) {
    tab = table(as.character(v), useNA = "ifany")
    ord = order(-as.integer(tab), names(tab), method = "radix")
    items = paste(names(tab)[ord], as.integer(tab)[ord])
    return(paste0("gptr_choice: ", paste(items, collapse = ", "), tail))
  }
  if (inherits(x, "gptr_score")) {
    m = mean(as.numeric(v), na.rm = TRUE)
    return(paste0("gptr_score: mean ", format(signif(m, 3L)), tail))
  }
  paste0(class(x)[1L], ": ", length(v), " values", tail)
}

#' doc.s1_block: the one-line block of a top-level System 1 call (contract 11.5); nothing in
#' replay mode, for nested calls or for calls in no document
#' @noRd
doc_s1_block_service = function(call, summary) {
  if (!is.null(run_current()) || identical(replay_mode(call$args$replay), "replay")) {
    return(invisible(NULL))
  }
  site = tryCatch(doc_locate(call), error = function(e) NULL)
  if (is.null(site) || !isTRUE(site$top_level) || is.null(site$stmt) || isTRUE(site$console)) {
    return(invisible(NULL))
  }
  txt = if (inherits(summary, "gptr_s1")) doc_s1_summary(summary) else as.character(summary)[1L]
  meta = attr(summary, "meta") %||% list()
  header = list(model = meta$model %||% "unknown", date = meta$date %||% format(Sys.Date()),
                prompt = site$prompt_hash, args = site$args_hash)
  if (!is.null(site$block)) {
    site$block_id = site$block$id
    site$regenerate = TRUE
  }
  tryCatch(doc_upsert(site, structure(paste0("#> ", doc_one_line(txt)), header = header)),
           error = function(e) {
             registry_diagnostic("builtin:documents", "doc.s1_block", class(e)[1L],
                                 conditionMessage(e))
           })
  invisible(NULL)
}

#' doc.replay: the replayed team or fan-out session of a fresh (or undone) block, else NULL with
#' `call$doc` set when the statement may be recorded (IC-47; called by the team and fanout
#' routes, which run before `document`)
#' @noRd
doc_replay_service = function(call) {
  if (!is.null(run_current())) return(NULL)
  site = tryCatch(doc_locate(call), error = function(e) NULL)
  if (is.null(site) || is.null(site$path) || !isTRUE(site$top_level) || is.null(site$stmt) ||
      isTRUE(site$console)) {
    return(NULL)
  }
  mode = replay_mode(call$args$replay)
  if (is.null(site$block)) {
    ok = !identical(mode, "replay") && doc_consent_possible(site$path)
    assign("doc", if (ok) site else NULL, envir = call)
    return(NULL)
  }
  decision = doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (decision %in% c("replay", "skip")) return(doc_replay_team(call, site, mode))
  if (identical(decision, "regenerate")) {
    site$regenerate = TRUE
    site$block_id = site$block$id
    doc_skip_old(site)
    assign("doc", if (doc_consent_possible(site$path)) site else NULL, envir = call)
    return(NULL)
  }
  assign("doc", NULL, envir = call)
  NULL
}

# ---- hooks --------------------------------------------------------------------------------------

#' agent_end: write the block of a settled top-level run whose run options carry a document site
#' (contract 7.15); only runs that ended `idle` are recorded
#' @noRd
doc_on_agent_end = function(event, ctx) {
  site = event$doc
  s = ctx$session
  if (is.null(site) || is.null(site$path) || is.null(s)) return(NULL)
  if (!identical(event$status %||% "idle", "idle")) return(NULL)
  d = session_data(s)
  if (isTRUE(site$console)) {
    site$session_id = d$id
    site$session_file = if (is.null(d$file)) NULL else doc_rel(d$file)
  }
  turn = if (d$kind %in% c("team", "fanout")) 1L else as.integer(event$turns %||% d$turns)
  lines = doc_block_lines(s, turn, site, site$ordinal %||% 1L)
  doc_upsert(site, lines, block_id = site$block_id)
  NULL
}

#' Ancestors (inclusive) of an entry id in a list of entries
#' @noRd
doc_ancestors = function(ents, id) {
  ids = vapply(ents, function(e) as.character(e$id %||% NA_character_), "")
  parents = vapply(ents, function(e) as.character(e$parent_id %||% NA_character_), "")
  out = character()
  cur = id
  while (length(cur) == 1L && !is.na(cur) && nzchar(cur) && !(cur %in% out)) {
    k = match(cur, ids)
    if (is.na(k)) break
    out = c(out, cur)
    cur = parents[k]
  }
  out
}

#' session_tree: the blocks of turns a rewind abandoned become inert, the blocks of turns a redo
#' brings back become live again, and console transcripts get a `# /rewind` line (G7 3.8, 4.4)
#' @noRd
doc_on_session_tree = function(event, ctx) {
  s = ctx$session
  if (is.null(s)) return(NULL)
  ents = session_data(s)$entries
  from = doc_ancestors(ents, event$from)
  to = doc_ancestors(ents, event$to)
  recs = Filter(function(e) {
    identical(e$type, "custom") && identical(e$custom_type, "gptr.doc_block")
  }, ents)
  pick = function(ids) Filter(function(e) e$id %in% ids, recs)
  mark = function(chosen, inert) {
    docs = unique(vapply(chosen, function(e) as.character(e$data$doc %||% ""), ""))
    for (doc in docs[nzchar(docs)]) {
      mine = Filter(function(e) identical(e$data$doc, doc), chosen)
      blocks = unique(vapply(mine, function(e) as.character(e$data$block), ""))
      tr = any(vapply(mine, function(e) identical(e$data$backend, "transcript"), NA))
      if (doc_set_inert(doc_abs(doc), blocks, inert = inert, session = s,
                        transcript = if (tr) TRUE else NULL)) {
        for (b in blocks) {
          session_append(s, list(type = "custom", custom_type = "gptr.doc_block", data = list(
            doc = doc, format = doc_format_of(doc) %||% "r", block = b,
            action = if (inert) "undone" else "replace",
            backend = if (tr) "transcript" else "file")))
        }
      }
    }
  }
  mark(pick(setdiff(from, to)), TRUE)
  mark(pick(setdiff(to, from)), FALSE)
  rep = as.character(event$report %||% character())
  bad = sum(grepl("not restored|conflict", rep))
  note = paste0("# /rewind: ", length(rep) - bad, " items restored or removed, ", bad,
                " not restored (session log ", event$to %||% "start", ")")
  tdocs = unique(vapply(Filter(function(e) identical(e$data$backend, "transcript"), recs),
                        function(e) as.character(e$data$doc), ""))
  for (doc in tdocs) doc_transcript_append(doc_abs(doc), note, session = s)
  NULL
}

#' console:direct (P14, after the line ran): a direct R line (`!expr`) of the console enters the
#' transcript under `# direct R (no model)` with its printed output as `#>` lines (IC-49,
#' contract 11.5 transcript row)
#' @noRd
doc_on_console_direct = function(event, ctx) {
  data = event$data %||% list()
  code = as_utf8(paste(as.character(data$code %||% character()), collapse = "\n"))
  if (!length(code) || !nzchar(trimws(code))) return(NULL)
  lines = c("", "# direct R (no model)", strsplit(code, "\n", fixed = TRUE)[[1L]],
            doc_output_lines(as.character(data$output %||% character())))
  doc_console_append(lines, ctx$session)
}

#' console:command (P14): a slash command of the console enters the transcript as a comment
#' (`# /model opus`, contract 11.5 transcript row)
#' @noRd
doc_on_console_command = function(event, ctx) {
  txt = as_utf8(as.character(event$data$text %||% ""))
  if (!length(txt) || is.na(txt[1L]) || !nzchar(trimws(txt[1L]))) return(NULL)
  doc_console_append(paste0("# ", doc_one_line(txt[1L])), ctx$session)
}

#' Append console lines to the console transcript target (an .R transcript), redacted with the
#' persist profile; always NULL (notify channels)
#' @noRd
doc_console_append = function(lines, session = NULL) {
  target = doc_transcript_target(ask = FALSE)
  if (!is.null(target) && identical(doc_format_of(target), "r")) {
    doc_transcript_append(target, redact(lines, "persist"), session = session)
  }
  NULL
}
```

Append to `R/doc-formats.R`:

```r
# ---- inert blocks on disk (G7 section 3.8) -------------------------------------------------------

#' Make blocks of a document inert (undone) or live again, under write consent, the document
#' lock, the `document_write` event (kind "inert") and the md5 check; TRUE when written.
#' `transcript` (NULL: a file under .gptr/transcripts/) also makes the owning `s_<hex>` statement
#' of a console turn inert, wherever the transcript lives (an IDE's active document).
#' @noRd
doc_set_inert = function(path, ids, inert = TRUE, session = NULL, transcript = NULL) {
  if (!file.exists(path) || !length(ids) || !doc_consent(path, ask = FALSE)) {
    return(invisible(FALSE))
  }
  fmt = doc_format_of(path)
  if (is.null(fmt)) return(invisible(FALSE))
  transcript = transcript %||% startsWith(doc_rel(path), ".gptr/transcripts/")
  lock = doc_lock(path)
  if (is.null(lock)) return(invisible(FALSE))
  on.exit(doc_unlock(lock), add = TRUE)
  for (attempt in 1:3) {
    doc = doc_read(path)
    new = doc_inert_text(doc$lines, fmt, ids, inert, transcript)
    if (identical(new, doc$lines)) return(invisible(FALSE))
    ev = doc_event(path, fmt, "inert", paste(ids, collapse = ","), new, session)
    if (isTRUE(ev$block)) return(invisible(FALSE))
    ok = tryCatch({
      doc_write(doc, ev$lines %||% new)
      TRUE
    }, gptr_error_doc_write = function(e) {
      if (identical(e$reason, "conflict")) FALSE else stop(e)
    })
    if (ok) return(invisible(TRUE))
  }
  invisible(FALSE)
}

# ---- builtin:documents (contract 7.15, 10.3; IC-34, IC-68) -------------------------------------

#' The `documents` prompt section text (architecture 7.3, byte for byte; P07 replaces `{s1}`)
#' @noRd
doc_section_body = paste(c(
  paste0("Code from successful r calls is written into the user's document (named in ",
         "<environment>) in a block below the gptr() call that asked for it, so the document ",
         "re-runs from top to bottom. Therefore:"),
  paste0("- Make recorded code the clean final version: named objects, no exploratory prints. ",
         "Pass record = false for throwaway checks (head(), summaries, tests)."),
  paste0("- Record key modelling decisions with note (one line, written as \"## Decision: ...\"); ",
         "key printed outputs are added as #> comments automatically."),
  paste0("- To change code you wrote earlier, edit that block in the document instead of ",
         "appending a second version."),
  paste0("- In the document, prompts are quoted strings in gptr(\"...\"), and System 1 decisions ",
         "are gptr(..., model = {s1}) inside if, for or while. Add such calls only when the user ",
         "asks for an agent step in the script.")
), collapse = "\n")

#' The `documents` section (contract 9.3: T0, order 500, budget 250): only when a history
#' document is bound (`ctx$input$document`, from the doc.site service)
#' @noRd
doc_section_text = function(ctx) {
  if (is.null(ctx$input$document)) return(NULL)
  doc_section_body
}

#' builtin:documents: the five doc formats, the route `document` (order 50), the `documents`
#' prompt section, the agent_end and session_tree hooks and the handlers of P14's
#' console:command and console:direct channels; the doc.* services are registered below with
#' `builtin = "documents"`, so filtering the built-in removes them too
#' @noRd
builtin_documents = function(gptr) {
  for (spec in doc_formats_builtin()) gptr$register(spec)
  gptr$register(gptr_spec("route", "document", order = 50, match = doc_route_match,
                          run = doc_route_run,
                          description = paste("a call located in a history document: replay",
                                              "its fresh block or record its new one")))
  gptr$register(gptr_prompt_section("documents", doc_section_text, tier = "T0", order = 500L,
                                    budget = 250L))
  gptr$on("agent_end", doc_on_agent_end)
  gptr$on("session_tree", doc_on_session_tree)
  gptr$on("console:command", doc_on_console_command)
  gptr$on("console:direct", doc_on_console_direct)
  invisible(NULL)
}

on_load(ext_declare_builtin("documents", builtin_documents))
on_load(ext_service_set("doc.site", doc_site_service, provided_by = "P15", builtin = "documents"))
on_load(ext_service_set("doc.edit", doc_edit_service, provided_by = "P15", builtin = "documents"))
on_load(ext_service_set("doc.s1_block", doc_s1_block_service, provided_by = "P15",
                        builtin = "documents"))
on_load(ext_service_set("doc.replay", doc_replay_service, provided_by = "P15",
                        builtin = "documents"))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-formats|doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 254 ]` (the two files together).

- [ ] **Step 5: Commit**

```bash
git add R/doc-replay.R R/doc-formats.R tests/testthat/test-doc-replay.R tests/testthat/test-doc-formats.R
git commit -m "feat(doc): register builtin:documents with the document route, section, hooks and services"
```

---

### Task 14: `gptr_doc()`, `gptr_blocks()` and `gptr_cache()`

**Files:**
- Modify: `R/doc-replay.R` (append)
- Test: `tests/testthat/test-doc-replay.R` (append)

**Interfaces:**
- Consumes: Tasks 1-13 (`doc_control_guard()`, `doc_format_of()`, `doc_recover()`, `doc_sync()`, `doc_read()`,
  `doc_find_blocks()`, `doc_calls()`, `doc_rmd_calls()`, `doc_anchor_of()`, `doc_format_get()`,
  `doc_block_status()`, `doc_block_body()`, `nb_parse()`, `nb_cell_lines()`, `doc_root()`, `doc_abs()`,
  `doc_existing_ids()`, `doc_sidecar_path()`); P01 `the`, `path_norm()`, `path_class()`, `check_flag()`,
  `check_string()`, `check_choice()`, `new_listing(df, class, footer = NULL)`, `gptr_opt("spill_days")`,
  `gptr_user_dir("cache")`, `json_decode()`, `read_utf8()`.
- Produces (04 §6.4): the exports `gptr_doc(path = NULL, format = NULL, sync = FALSE)` (`path = NULL`: the binding
  `list(path, format)` or `NULL`, visibly; a path binds every `gptr()` call of this R process and is consent to write
  it; `FALSE` unbinds; returns the previous binding invisibly; `invalid_argument` for other files, control,
  critical, protected or instructions paths and missing directories; `gptr_error_permission` from model code,
  IC-53), `gptr_blocks(file)` (the `gptr_blocks` listing, read only apart from recovering a dead process's sidecar),
  `gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp"))` (`info`: the
  `gptr_cache_info` listing with a `sidecar` row; `prune`/`clear`: the number of files removed, invisibly); helpers
  `doc_block_row()`, `doc_blocks_text()`, `doc_blocks_ipynb()`, `doc_cache_files(kind)`, `doc_cache_info(kinds)`,
  `doc_cache_remove(kind, prune = TRUE)`, `doc_s2_live(file)`, `doc_catalog_prune()`.

`gptr_cache("prune")` removes "S2 entries of deleted blocks, S1 entries unused for 90 days (mtime touched on hit),
`cache/tmp` files older than `gptr.spill_days`, the refreshed catalog cache beyond the newest" (04 §6.4); the
checkpoint blobs that 04 also lists belong to P16's retention (P16 depends on P15, see the self-review). Sidecars
are listed but never removed: "Sidecars are never pruned automatically; `gptr_cache("info")` lists them" (IC-51).
The S1 cache's `salt` file is not a cache entry and is kept. The examples run offline: they write only under
`tempdir()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-replay.R`:

```r
test_that("gptr_doc() binds, shows and unbinds the document of this process", {
  local_project()
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the))
  the$doc_binding = NULL
  f = file.path(getwd(), "analysis.R")
  writeLines("library(gptr)", f)
  expect_null(gptr_doc())
  expect_invisible(gptr_doc(f))
  expect_identical(gptr_doc(), list(path = path_norm(f), format = "r"))
  expect_true(doc_consent(f, ask = FALSE))
  prev = gptr_doc(FALSE)
  expect_identical(prev$path, path_norm(f))
  expect_null(gptr_doc())
  expect_identical(gptr_doc(f, format = "transcript"), NULL)
  expect_identical(gptr_doc()$format, "transcript")
  expect_error(gptr_doc(file.path(getwd(), "notes.txt")), class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), ".gptr", "settings.json")),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(file.path(getwd(), "missing", "a.R")),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_doc(f, sync = NA), class = "gptr_error_invalid_argument")
  run = new.env()
  run$session = "s0123456789"
  run$signal = new.env()
  testthat::local_mocked_bindings(run_current = function() run)
  expect_error(gptr_doc(f), class = "gptr_error_permission")
  expect_identical(gptr_doc()$format, "transcript")
})

test_that("gptr_blocks() lists fresh, stale, user-edited and undone blocks", {
  local_project()
  f = file.path(getwd(), "a.R")
  ok = "x = 1"
  writeLines(c(
    "gptr(\"one\")",
    doc_render_block("aaaaaa", list(model = "m", date = "2026-09-29", prompt = prompt_hash("one"),
                                    sha = doc_body_sha(ok), tokens = "10/2", cost = "0.01",
                                    session = "s0123456789"), ok),
    "gptr(\"two, edited prompt\")",
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("two")), "y = 2"),
    "gptr(\"three\")",
    doc_render_block("cccccc", list(model = "m", prompt = prompt_hash("three"),
                                    sha = doc_body_sha(ok)), "z = 3 # changed"),
    "gptr(\"four\")",
    doc_render_block("dddddd", list(model = "m", prompt = prompt_hash("four"),
                                    status = "undone"), "#~ w = 4")), f)
  b = gptr_blocks(f)
  expect_s3_class(b, "gptr_blocks")
  expect_s3_class(b, "gptr_listing")
  expect_named(b, c("id", "lines", "prompt", "status", "model", "date", "tokens", "cost",
                    "session"))
  expect_identical(b$id, c("aaaaaa", "bbbbbb", "cccccc", "dddddd"))
  expect_identical(b$status, c("fresh", "stale", "user-edited", "undone"))
  expect_identical(b$lines[1], "2-4")
  expect_identical(b$prompt[1], "one")
  expect_identical(b$cost[1], 0.01)
  expect_identical(b$tokens[1], "10/2")
  expect_identical(b$session[1], "s0123456789")
  expect_error(gptr_blocks(file.path(getwd(), "a.txt")), class = "gptr_error_invalid_argument")
})

test_that("gptr_blocks() reads Rmd chunks and notebook cells", {
  local_project()
  rmd = testthat::test_path("fixtures", "docs", "report.expected.Rmd")
  b = gptr_blocks(rmd)
  expect_identical(b$id, "3fdfa0")
  expect_identical(b$status, "fresh")
  expect_identical(b$prompt, "count letters in this prompt")
  nb = file.path(getwd(), "a.ipynb")
  text = doc_read(testthat::test_path("fixtures", "docs", "floats.ipynb"))$lines
  ph = prompt_hash("summarise the mpg column")
  site = list(path = nb, format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
              prompt_hash = ph, args_hash = NULL)
  writeLines(doc_ipynb_upsert(text, site, structure("mean(x$mpg)", meta = nb_meta(
    "7f3a21", list(model = "m", prompt = ph, sha = doc_body_sha("mean(x$mpg)")))), "7f3a21"), nb)
  nbb = gptr_blocks(nb)
  expect_identical(nbb$id, "7f3a21")
  expect_identical(nbb$lines, "cell 4")
  expect_identical(nbb$status, "fresh")
})

test_that("gptr_cache() lists, prunes and clears, and never removes sidecars", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines(c("gptr(\"one\")", doc_render_block("aaaaaa", list(model = "m"), "x = 1")), f)
  s2_put(s2_key("a.R", "aaaaaa", "", "p", ""), list(block = "aaaaaa", doc = "a.R", answer = "a"))
  s2_put(s2_key("a.R", "gone00", "", "p", ""), list(block = "gone00", doc = "a.R", answer = "b"))
  tmp = file.path(proj, ".gptr", "cache", "tmp")
  writeLines("old", file.path(tmp, "gptr-output-o111111.txt"))
  Sys.setFileTime(file.path(tmp, "gptr-output-o111111.txt"), Sys.time() - 30 * 86400)
  writeLines("new", file.path(tmp, "gptr-output-o222222.txt"))
  rec = doc_pending_new(path_norm(f), "pending", NULL)
  rec$upserts = list(list(block_id = "bbbbbb", lines = "x", site = list(format = "r")))
  doc_sidecar_write(rec)
  info = gptr_cache()
  expect_s3_class(info, "gptr_cache_info")
  expect_named(info, c("kind", "entries", "bytes", "oldest", "path"))
  expect_identical(info$kind, c("s1", "s2", "tmp", "sidecar"))
  expect_identical(info$entries, c(0L, 2L, 2L, 1L))
  expect_identical(gptr_cache("prune", "s2"), 1L)
  expect_identical(gptr_cache("prune", "tmp"), 1L)
  expect_identical(gptr_cache("clear", "tmp"), 1L)
  expect_identical(gptr_cache()$entries, c(0L, 1L, 0L, 1L))
  expect_identical(gptr_cache("clear"), 1L)
  expect_true(file.exists(doc_sidecar_path(f)))
  expect_error(gptr_cache("purge"), class = "gptr_error_invalid_argument")
  testthat::local_mocked_bindings(run_current = function() {
    run = new.env()
    run$signal = new.env()
    run
  })
  expect_error(gptr_cache("clear"), class = "gptr_error_permission")
  expect_s3_class(gptr_cache(), "gptr_cache_info")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 130 ]`, the new tests failing with ``Error in `gptr_doc()`: could not find function "gptr_doc"`` and the like.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-replay.R`:

```r
# ---- exports: gptr_doc(), gptr_blocks(), gptr_cache() (contract 6.4) ---------------------------

#' Bind this R process to a history document
#'
#' `gptr_doc(path)` binds every `gptr()` call of this R process, at the console and in scripts,
#' to a history document, and is your explicit consent that gptr writes agent blocks into it.
#' Nothing is written until a block is recorded. `gptr_doc(FALSE)` removes the binding and
#' `gptr_doc()` shows it. `sync = TRUE` writes the blocks that were recorded while the document
#' could not be written: a Jupyter notebook that was open, or the deferred writes of an `Rscript`
#' run that was killed.
#'
#' @param path `NULL` to return the current binding, `FALSE` to remove it, or the path of an
#'   `.R`, `.Rmd`, `.qmd` or `.ipynb` document.
#' @param format `NULL` (from the file extension) or one of `"r"`, `"rmd"`, `"qmd"`, `"ipynb"`,
#'   `"transcript"`.
#' @param sync `TRUE` applies the pending blocks of the document now.
#' @return With `path = NULL`, the binding `list(path, format)` or `NULL`, visibly. Otherwise the
#'   previous binding, invisibly.
#' @section Options:
#' Options of history documents (`?gptr_options` collects every option):
#' `gptr.record` (settings, `"ask"`): `"auto"` records into documents without asking, `"off"`
#' never records; also the settings key `record`, which a project can only tighten.
#' `gptr.replay` (settings, `"auto"`): the replay mode `"auto"`, `"replay"`, `"live"` or
#' `"record"` (also the `GPTR_REPLAY` environment variable); a call's `replay =` argument wins.
#' `gptr.doc_output_lines` (`12`): `#>` output lines recorded per execution.
#' `gptr.doc_source_frames` (`TRUE`): `FALSE` stops gptr from reading `source()` frames to find
#' calls in scripts sourced without srcrefs.
#' `gptr.spill_days` (`7`): `gptr_cache("prune")` removes temporary files older than this.
#' @export
#' @examples
#' f = tempfile(fileext = ".R"); writeLines("library(gptr)", f)
#' gptr_doc(f)
#' gptr_doc()
#' gptr_doc(FALSE)
gptr_doc = function(path = NULL, format = NULL, sync = FALSE) {
  check_flag(sync, "sync")
  if (is.null(path)) return(the$doc_binding)
  old = the$doc_binding
  doc_control_guard("gptr_doc")
  if (isFALSE(path)) {
    the$doc_binding = NULL
    return(invisible(old))
  }
  check_string(path, "path")
  full = path_norm(path)
  fmt = if (is.null(format)) {
    doc_format_of(full)
  } else {
    check_choice(format, c("r", "rmd", "qmd", "ipynb", "transcript"), "format")
  }
  if (is.null(fmt)) {
    gptr_abort("gptr_doc() binds .R, .Rmd, .qmd or .ipynb documents.", "invalid_argument",
               arg = "path", expected = "a .R, .Rmd, .qmd or .ipynb file")
  }
  cls = path_class(full)
  if (cls %in% c("control", "critical", "protected", "instructions", "url", "wildcard")) {
    gptr_abort(paste0("gptr_doc() cannot bind a ", cls, " path."), "invalid_argument",
               arg = "path", expected = "a document outside control and protected paths")
  }
  if (!dir.exists(dirname(full))) {
    gptr_abort("The directory of the document does not exist.", "invalid_argument",
               arg = "path", expected = "a path in an existing directory")
  }
  the$doc_binding = list(path = full, format = fmt)
  if (file.exists(full)) doc_recover(full)
  if (sync) doc_sync(full)
  invisible(old)
}

#' List the agent blocks of a document
#'
#' Reads an `.R`, `.Rmd`, `.qmd` or `.ipynb` document and lists its gptr blocks with their
#' status: `fresh` (the owning call's prompt matches), `stale` (the prompt or its interpolated
#' values changed, or no call owns the block), `user-edited` (the body no longer matches its
#' `sha`) or `undone` (made inert by a rewind). It reads the document; the only write is that
#' blocks an `Rscript` run queued before it was killed are applied first (never over your edits).
#'
#' @param file Path of the document.
#' @return A `gptr_blocks` data frame with columns `id`, `lines`, `prompt`, `status`, `model`,
#'   `date`, `tokens`, `cost`, `session`.
#' @export
#' @examples
#' f = tempfile(fileext = ".R")
#' writeLines(c('gptr("add one")',
#'              "# >>> gptr:7f3a21 model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2",
#'              "x = 1 + 1", "# <<< gptr:7f3a21"), f)
#' gptr_blocks(f)
gptr_blocks = function(file) {
  check_string(file, "file")
  path = path_norm(file)
  fmt = doc_format_of(path)
  if (is.null(fmt)) {
    gptr_abort("gptr_blocks() reads .R, .Rmd, .qmd or .ipynb documents.", "invalid_argument",
               arg = "file", expected = "a .R, .Rmd, .qmd or .ipynb file")
  }
  doc_recover(path)
  text = doc_read(path)$lines
  rows = if (identical(fmt, "ipynb")) doc_blocks_ipynb(text) else doc_blocks_text(text, fmt)
  df = data.frame(id = character(), lines = character(), prompt = character(),
                  status = character(), model = character(), date = character(),
                  tokens = character(), cost = numeric(), session = character(),
                  stringsAsFactors = FALSE)
  if (length(rows)) df = do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  new_listing(df, "gptr_blocks")
}

#' One row of a gptr_blocks listing
#' @noRd
doc_block_row = function(id, lines, prompt, status, h) {
  list(id = id, lines = lines, prompt = prompt, status = status,
       model = h$model %||% NA_character_, date = h$date %||% NA_character_,
       tokens = h$tokens %||% NA_character_,
       cost = suppressWarnings(as.numeric(h$cost %||% NA_character_)),
       session = h$session %||% NA_character_)
}

#' Rows of gptr_blocks() for R, Rmd and qmd texts: each block is owned by the top-level call
#' whose run of blocks holds it (a block nobody owns is stale)
#' @noRd
doc_blocks_text = function(text, fmt) {
  blocks = doc_find_blocks(text)
  if (!nrow(blocks)) return(list())
  styled = fmt %in% c("rmd", "qmd")
  calls = if (styled) doc_rmd_calls(text) else doc_calls(text, blocks)
  spec = doc_format_get(if (styled) fmt else "r")
  owner = rep(NA_character_, nrow(blocks))
  owner_ph = rep(NA_character_, nrow(blocks))
  top = calls[is.na(calls$block) & !calls$nested, , drop = FALSE]
  for (k in seq_len(nrow(top))) {
    site = list(anchor = doc_anchor_of(calls, top[k, , drop = FALSE]), prompt_hash = top$ph[k],
                args_hash = NULL)
    loc = spec$locate(text, site)
    run = loc$blocks
    if (is.null(run) || !nrow(run)) next
    idx = match(run$id, blocks$id)
    free = !is.na(idx) & is.na(owner[idx])
    owner[idx[free]] = top$prompt[k]
    owner_ph[idx[free]] = top$ph[k]
  }
  lapply(seq_len(nrow(blocks)), function(k) {
    b = blocks[k, , drop = FALSE]
    h = b$header[[1L]]
    status = doc_block_status(h, doc_block_body(text, b),
                              if (is.na(owner_ph[k])) "" else owner_ph[k], h$args)
    doc_block_row(b$id, paste0(b$start, "-", b$end), substr(owner[k], 1L, 60L), status, h)
  })
}

#' Rows of gptr_blocks() for a notebook: agent cells are owned by the calling cell before them
#' @noRd
doc_blocks_ipynb = function(text) {
  nb = nb_parse(text)
  rows = list()
  owner = NA_character_
  for (i in seq_along(nb$cells)) {
    cell = nb$cells[[i]]
    meta = cell$metadata$gptr
    if (is.null(meta) || !startsWith(cell$id %||% "", "gptr-")) {
      calls = if (identical(cell$cell_type, "code")) doc_calls(nb_cell_lines(cell)) else NULL
      if (!is.null(calls) && nrow(calls)) owner = calls$prompt[1L]
      next
    }
    ph = if (is.na(owner)) "" else prompt_hash(owner)
    status = doc_block_status(meta, nb_cell_lines(cell), ph, meta$args)
    rows[[length(rows) + 1L]] = doc_block_row(meta$id %||% sub("^gptr-", "", cell$id),
                                              paste0("cell ", i), substr(owner, 1L, 60L),
                                              status, meta)
  }
  rows
}

#' Inspect, prune or clear gptr's caches
#'
#' `info` lists the System 1 answer cache, the System 2 answer cache used for replay, temporary
#' spill files and unapplied document sidecars (deferred or pending blocks; they are never
#' removed here: apply them with `gptr_doc(path, sync = TRUE)`). `prune` removes System 2 answers
#' whose block no longer exists in its document, System 1 answers unused for 90 days, temporary
#' files older than `getOption("gptr.spill_days", 7)` days and older refreshed model catalogs;
#' `clear` removes a kind entirely.
#'
#' @param action `"info"`, `"prune"` or `"clear"`.
#' @param kind `"all"`, `"s1"`, `"s2"` or `"tmp"`.
#' @return `info`: a `gptr_cache_info` data frame with columns `kind`, `entries`, `bytes`,
#'   `oldest`, `path`. `prune` and `clear`: the number of files removed, invisibly.
#' @export
#' @examples
#' gptr_cache()
#' gptr_cache("prune", "tmp")
gptr_cache = function(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp")) {
  action = check_choice(action, c("info", "prune", "clear"), "action")
  kind = check_choice(kind, c("all", "s1", "s2", "tmp"), "kind")
  kinds = if (identical(kind, "all")) c("s1", "s2", "tmp") else kind
  if (identical(action, "info")) return(doc_cache_info(kinds))
  doc_control_guard("gptr_cache")
  prune = identical(action, "prune")
  n = 0L
  for (k in kinds) n = n + doc_cache_remove(k, prune = prune)
  if (identical(kind, "all") && prune) n = n + doc_catalog_prune()
  invisible(n)
}

#' Files of one cache kind under the workspace root (`sidecar`: the unapplied document sidecars)
#' @noRd
doc_cache_files = function(kind) {
  cache = file.path(doc_root(), "cache")
  f = switch(kind,
             s1 = list.files(file.path(cache, "s1"), pattern = "[.]json$", recursive = TRUE,
                             full.names = TRUE),
             s2 = list.files(file.path(cache, "s2"), pattern = "[.]json$", recursive = TRUE,
                             full.names = TRUE),
             tmp = setdiff(list.files(file.path(cache, "tmp"), full.names = TRUE),
                           doc_cache_files("sidecar")),
             sidecar = list.files(file.path(cache, "tmp"), pattern = "^pending-.*[.]rds$",
                                  full.names = TRUE),
             character())
  f[file.exists(f) & !dir.exists(f)]
}

#' The gptr_cache_info listing (one row per kind plus the sidecars)
#' @noRd
doc_cache_info = function(kinds) {
  cache = file.path(doc_root(), "cache")
  rows = lapply(c(kinds, "sidecar"), function(k) {
    f = doc_cache_files(k)
    info = file.info(f)
    data.frame(kind = k, entries = length(f), bytes = sum(info$size, na.rm = TRUE),
               oldest = if (length(f)) min(info$mtime, na.rm = TRUE) else as.POSIXct(NA),
               path = file.path(cache, if (identical(k, "sidecar")) "tmp" else k),
               stringsAsFactors = FALSE)
  })
  new_listing(do.call(rbind, rows), "gptr_cache_info")
}

#' Remove the files of a cache kind; `prune = TRUE` keeps what is still in use
#' @noRd
doc_cache_remove = function(kind, prune = TRUE) {
  f = doc_cache_files(kind)
  if (!length(f)) return(0L)
  if (prune) {
    age = as.numeric(difftime(Sys.time(), file.info(f)$mtime, units = "days"))
    keep = switch(kind,
                  s1 = age <= 90,
                  tmp = age <= as.numeric(gptr_opt("spill_days") %||% 7),
                  s2 = vapply(f, doc_s2_live, NA, USE.NAMES = FALSE),
                  rep(TRUE, length(f)))
    f = f[!keep]
  }
  as.integer(sum(file.remove(f)))
}

#' Does an S2 record still belong to a block of an existing document?
#' @noRd
doc_s2_live = function(file) {
  rec = tryCatch(json_decode(read_utf8(file)$text), error = function(e) NULL)
  if (is.null(rec$doc) || is.null(rec$block)) return(FALSE)
  path = doc_abs(rec$doc)
  if (!file.exists(path)) return(FALSE)
  text = tryCatch(doc_read(path)$lines, error = function(e) character())
  rec$block %in% tryCatch(doc_existing_ids(doc_format_of(path) %||% "r", text),
                          error = function(e) character())
}

#' Remove refreshed model catalogs other than the newest from the user cache directory
#' @noRd
doc_catalog_prune = function() {
  dir = gptr_user_dir("cache")
  f = list.files(dir, pattern = "^models.*[.]json$", full.names = TRUE)
  if (length(f) < 2L) return(0L)
  old = f[order(file.info(f)$mtime, decreasing = TRUE)][-1L]
  as.integer(sum(file.remove(old)))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 174 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-replay.R tests/testthat/test-doc-replay.R
git commit -m "feat(doc): add gptr_doc(), gptr_blocks() and gptr_cache()"
```

---

### Task 15: `gptr_source()`

**Files:**
- Modify: `R/doc-replay.R` (append)
- Test: `tests/testthat/test-doc-replay.R` (append)

**Interfaces:**
- Consumes: Tasks 1-14 (`doc_format_of()`, `doc_recover()`, `doc_read()`, `doc_find_blocks()`, `doc_state()`,
  `doc_source_push()`, `doc_source_pop()`, `gptr_blocks()`; through the route: `doc_locate()` (driver
  `"gptr_source"` while the frame is pushed), `doc_decide()`, `doc_skip_old()`, `doc_source_log()`); P01
  `check_string()`, `check_choice()`, `check_env()`, `check_flag()`, `path_norm()`, `msg_verbatim()`,
  `gptr_abort()`; base `srcfilecopy()`, `parse(keep.source = TRUE, srcfile =)`.
- Produces (04 §6.4): the export `gptr_source(file, replay = getOption("gptr.replay", "auto"), envir =
  parent.frame(), echo = FALSE)` -> `invisible(<gptr_blocks>)` with the extra column `action` (`replayed`,
  `regenerated`, `ran`, `skipped`, or `NA`); conditions `invalid_argument` (a file that is not `.R`, a bad `replay`),
  `not_recorded`, `stale_block` (replay mode) and whatever the sourced code signals. Copy safety [R1][R2]: it holds
  `envir` only in its own frame and never stores it.

Report 14 §4.4.2: base `source()` has parsed the old block before `gptr()` runs, so it cannot regenerate without
running the old code; `gptr_source()` parses the file once (keeping srcrefs, so every call is located through its
srcref), evaluates it expression by expression, and skips the top-level expressions of a block the route marked for
regeneration (`doc_skip_old()` adds the block id to the frame's skip set before the old block is reached). The
replay mode applies to every call in the file through `options(gptr.replay = replay)`, restored on exit; a call's own
`replay =` argument still wins (P08's `replay_mode(arg)`).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-replay.R`:

```r
# An environment whose gptr() stands in for the gateway: the document route first, then (when it
# passes) a scripted "run" that evaluates `code` in the caller's frame as the agent's r call and
# writes the block through the agent_end hook, as the real run does
doc_source_env = function(code = "n = 99", log = new.env()) {
  e = new.env()
  log$runs = 0L
  e$log = log
  e$gptr = function(prompt, ..., replay = NULL) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$envir = parent.frame()
    call$args = list(replay = replay)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(res)
    }
    log$runs = log$runs + 1L
    log$site = call$doc
    eval(parse(text = code), call$envir)
    s = doc_test_session(list(doc_test_turn(code, prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    s
  }
  e
}

test_that("gptr_source() replays fresh blocks, regenerates stale ones and skips their old code", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "analysis.R")
  fresh_body = "a = 1"
  writeLines(c(
    "fresh = gptr(\"first step\")",
    doc_render_block("aaaaaa", list(model = "m", prompt = prompt_hash("first step"),
                                    sha = doc_body_sha(fresh_body)), fresh_body),
    "stale = gptr(\"second step, reworded\")",
    doc_render_block("bbbbbb", list(model = "m", prompt = prompt_hash("second step")),
                     "old_ran = TRUE"),
    "after = a + 1"), f)
  e = doc_source_env(code = "n = 99")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(e$log$runs, 1L)
  expect_identical(e$log$site$kind, "srcref")
  expect_identical(e$log$site$driver, "gptr_source")
  expect_identical(e$a, 1)
  expect_identical(e$n, 99)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(e$after, 2)
  expect_identical(out$id, c("aaaaaa", "bbbbbb"))
  expect_identical(out$action, c("replayed", "regenerated"))
  expect_identical(out$status, c("fresh", "fresh"))
  b = doc_find_blocks(readLines(f))
  expect_identical(doc_block_body(readLines(f), b[2, ]), "n = 99")
  expect_identical(b$header[[2]]$prompt, prompt_hash("second step, reworded"))
  expect_null(getOption("gptr.replay"))
})

test_that("a call without a block runs and is recorded; replay mode refuses a stale block", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "analysis.R")
  writeLines(c("x = gptr(\"count rows\")", "y = 2"), f)
  e = doc_source_env(code = "n = nrow(mtcars)")
  out = gptr_source(f, replay = "auto", envir = e)
  expect_identical(out$action, "ran")
  expect_identical(e$n, 32L)
  again = gptr_source(f, replay = "replay", envir = e)
  expect_identical(again$action, "replayed")
  expect_identical(e$log$runs, 1L)
  txt = readLines(f)
  txt[1] = "x = gptr(\"count the rows\")"
  writeLines(txt, f)
  expect_error(gptr_source(f, replay = "replay", envir = e), class = "gptr_error_stale_block")
  expect_null(getOption("gptr.replay"))
  expect_length(doc_state()$sources, 0L)
})

test_that("gptr_source() validates its arguments and runs plain scripts", {
  local_project()
  f = file.path(getwd(), "plain.R")
  writeLines(c("x = 1", "y = x + 1"), f)
  e = new.env()
  out = gptr_source(f, replay = "replay", envir = e)
  expect_identical(e$y, 2)
  expect_identical(nrow(out), 0L)
  expect_named(out, c("id", "lines", "prompt", "status", "model", "date", "tokens", "cost",
                      "session", "action"))
  expect_error(gptr_source(f, replay = "sometimes"), class = "gptr_error_invalid_argument")
  rmd = file.path(getwd(), "r.Rmd")
  writeLines("x", rmd)
  expect_error(gptr_source(rmd), class = "gptr_error_invalid_argument")
  echoed = cli::cli_fmt(gptr_source(f, envir = e, echo = TRUE))
  expect_identical(echoed, c("> x = 1", "> y = x + 1"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 174 ]`, the new tests failing with ``Error in `gptr_source(f, replay = "auto", envir = e)`: could not find function "gptr_source"``.

- [ ] **Step 3: Write the implementation**

Append to `R/doc-replay.R`:

```r
# ---- gptr_source() (contract 6.4; report 14 section 4.4.2) -------------------------------------

#' Source a history document, regenerating stale blocks without running the old code
#'
#' Evaluates `file` top-level expression by expression in `envir`, like [source()] with
#' `keep.source = TRUE`. A `gptr()` call whose block is fresh replays without calling a model
#' and the block's code then runs as ordinary R. A call whose block is stale (its prompt or the
#' values interpolated into it changed), or every call under `replay = "live"`, asks the model
#' again and rewrites its block in place, and the old block is skipped, which base `source()`
#' cannot do.
#'
#' @param file Path of an `.R` document.
#' @param replay Replay mode for the calls in the file: `"auto"`, `"replay"`, `"live"` or
#'   `"record"`. A call's own `replay =` argument wins.
#' @param envir Environment in which the expressions are evaluated.
#' @param echo `TRUE` prints each expression before it is evaluated.
#' @return Invisibly, the `gptr_blocks` listing of the file after the run with an extra column
#'   `action`: `replayed`, `regenerated`, `ran`, `skipped`, or `NA` for blocks no call touched.
#' @export
#' @examples
#' f = tempfile(fileext = ".R")
#' writeLines(c("x = 1", "y = x + 1"), f)
#' gptr_source(f, replay = "replay", envir = new.env())
gptr_source = function(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(),
                       echo = FALSE) {
  check_string(file, "file")
  replay = check_choice(replay, c("auto", "replay", "live", "record"), "replay")
  check_env(envir, "envir")
  check_flag(echo, "echo")
  path = path_norm(file)
  if (!identical(doc_format_of(path), "r")) {
    gptr_abort("gptr_source() runs .R documents; knit .Rmd and .qmd documents instead.",
               "invalid_argument", arg = "file", expected = "an .R file")
  }
  doc_recover(path)
  doc = doc_read(path)
  srcfile = srcfilecopy(path, doc$lines, file.mtime(path), isFile = TRUE)
  exprs = parse(text = doc$lines, keep.source = TRUE, srcfile = srcfile)
  srcs = attr(exprs, "srcref")
  blocks = doc_find_blocks(doc$lines)
  owner = vapply(srcs, function(sr) {
    k = which(sr[1L] > blocks$start & sr[3L] < blocks$end)
    if (length(k)) blocks$id[k[1L]] else NA_character_
  }, "")
  st = doc_state()
  depth = doc_source_push(path)
  on.exit(doc_source_pop(depth), add = TRUE)
  old = options(gptr.replay = replay)
  on.exit(options(old), add = TRUE)
  for (i in seq_along(exprs)) {
    if (!is.na(owner[i]) && owner[i] %in% st$sources[[depth]]$skip) next
    if (echo) msg_verbatim(paste0("> ", as.character(srcs[[i]])))
    eval(exprs[i], envir)
  }
  acts = st$sources[[depth]]$log
  out = gptr_blocks(path)
  out$action = vapply(out$id, function(id) acts[[id]] %||% NA_character_, "", USE.NAMES = FALSE)
  invisible(out)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 200 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/doc-replay.R tests/testthat/test-doc-replay.R
git commit -m "feat(doc): add gptr_source() to regenerate stale blocks without running the old code"
```

---

### Task 16: knitr integration

**Files:**
- Create: `R/doc-knitr.R`
- Test: `tests/testthat/test-doc-knitr.R` (create)

**Interfaces:**
- Consumes: Tasks 3, 4, 13 (`doc_turn_entries()`, `doc_turn_body()`, `doc_state()`, `doc_s1_summary()`; the route
  through the stand-in gateway of the tests); P01 `on_load()`, `s3_register(generic, class, method = NULL)`
  ("Delayed S3 registration for generics of Suggests packages"); P06 `session_data()`, the session accessor `$text`
  (04 §5.1: teams join their children's reports); knitr (Suggests): `knitr::asis_output()`, `knitr::opts_hooks`,
  `knitr::knit_hooks`.
- Produces (IC-07: "`knit_print` methods (sessions, System 1 vectors) exist only in `doc-knitr.R` (P15)"):
  `knit_print.gptr_session(x, ...)` and `knit_print.gptr_s1(x, ...)`, registered lazily with
  `on_load(s3_register("knitr::knit_print", "<class>"))` (not exported, no `NAMESPACE` entry); `doc_knit_code(s)`;
  `doc_knitr_skip(label)` (called by `doc_skip_old()` for the knitr driver) and `doc_knitr_unhook(old_label,
  old_doc)`.

Report 14 §4.6 and §2.1.3 (verified, item 9): a `knit_print` method prints the answer as Markdown and, for a turn
that ran live, also the code it ran, so the first render is complete although the new agent chunk only runs from the
next render on; a scoped `knitr::opts_hooks` label hook, chained to any existing one, sets `eval = FALSE` for the
stale agent chunk of a block regenerated during the knit, and a `knit_hooks` `document` hook removes it at the end
(the hook otherwise persists after `knit()`). The tests drive the real knitr with a stand-in `gptr()` that runs the
`document` route and writes the block through the `agent_end` hook; Task 18 repeats record and replay through the
real `gptr()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-doc-knitr.R`:

```r
# Tests for R/doc-knitr.R (plan P15): knit_print methods, the scoped label hook, and knitr and
# Quarto record/replay through the document route with a stand-in gptr().

# A session with recorded turns, built the way P06 records them
doc_test_session = function(turns, kind = "chat") {
  s = session_new("fake/fake-1", "auto", home = new.env(), kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, prompt = "count rows", answer = "There are 32 rows.") {
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call("call_1", "r", list(code = code))), api = "fake", provider = "fake",
      model = "fake-1", stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      "call_1", "r", "ok", details = list(code = code, status = "ok"))),
    list(type = "message", message = msg_assistant(answer, api = "fake", provider = "fake",
                                                   model = "fake-1"))
  )
}

# The stand-in gateway of a knit: the document route, then a scripted run that evaluates `code`
# in the caller's frame and writes its block through the agent_end hook
doc_knit_env = function(code = "n = 32") {
  e = new.env()
  e$runs = 0L
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$envir = parent.frame()
    call$args = list(replay = NULL)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(invisible(res))
    }
    e$runs = e$runs + 1L
    eval(parse(text = code), call$envir)
    s = doc_test_session(list(doc_test_turn(code, prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    invisible(s)
  }
  e
}

test_that("sessions knit as their answer, plus the code of a live turn", {
  skip_if_not_installed("knitr")
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  d = session_data(s)
  d$last_text = "There are 32 rows."
  out = knit_print.gptr_session(s)
  expect_s3_class(out, "knit_asis")
  expect_identical(as.character(out),
                   "There are 32 rows.\n\n```r\nn = nrow(mtcars)\n```")
  r = doc_test_session(list(doc_test_turn("n = 1")), kind = "replayed")
  dr = session_data(r)
  dr$last_text = "There are 32 rows."
  expect_identical(as.character(knit_print.gptr_session(r)), "There are 32 rows.")
  x = structure(c(TRUE, TRUE, FALSE), class = c("gptr_decision", "gptr_s1", "logical"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  expect_identical(as.character(knit_print.gptr_s1(x)),
                   "`gptr_decision: 2 TRUE / 1 FALSE (jev-1.13.0, 2026-09-29)`\n")
})

test_that("the label hook skips a chunk for one knit and is removed afterwards", {
  skip_if_not_installed("knitr")
  local_project()
  rmd = file.path(getwd(), "skip.Rmd")
  writeLines(c("```{r first}", "doc_knitr_skip(\"gptr-abc123\")", "a = 1", "```", "",
               "```{r gptr-abc123}", "b = 2", "```", "", "```{r last}", "c = 3", "```"), rmd)
  e = new.env(parent = environment(doc_knitr_skip))
  knitr::knit(rmd, output = file.path(getwd(), "skip.md"), envir = e, quiet = TRUE)
  expect_identical(e$a, 1)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(e$c, 3)
  expect_null(knitr::opts_hooks$get("label"))
  expect_false(doc_state()$knitr_hooked)
})

test_that("knitr records an agent chunk on the first knit and replays it on the second", {
  skip_if_not_installed("knitr")
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  rmd = file.path(getwd(), "report.Rmd")
  file.copy(testthat::test_path("fixtures", "docs", "report.Rmd"), rmd)
  e = doc_knit_env(code = "n = nchar(\"count letters in this prompt\")")
  e$doc_knitr_skip = doc_knitr_skip
  out = file.path(getwd(), "report.md")
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  expect_identical(e$runs, 1L)
  ch = doc_rmd_chunks(readLines(rmd))
  expect_match(ch$label[3], "^gptr-[0-9a-f]{6}$")
  expect_identical(ch$fence[3], "````")
  md5 = tools::md5sum(rmd)
  e2 = doc_knit_env()
  knitr::knit(rmd, output = out, envir = e2, quiet = TRUE)
  expect_identical(e2$runs, 0L)
  expect_identical(e2$n, 28L)
  expect_identical(tools::md5sum(rmd), md5)
})

test_that("a stale agent chunk is regenerated during the knit without running the old code", {
  skip_if_not_installed("knitr")
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  rmd = file.path(getwd(), "report.Rmd")
  writeLines(c("```{r ask}", "gptr(\"count the letters, reworded\")", "```", "",
               "```{r gptr-abc123}",
               paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count the letters")),
               "old_ran = TRUE", "# <<< gptr:abc123", "```"), rmd)
  e = doc_knit_env(code = "n = 7")
  knitr::knit(rmd, output = file.path(getwd(), "report.md"), envir = e, quiet = TRUE)
  expect_identical(e$runs, 1L)
  expect_identical(e$n, 7)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  b = doc_find_blocks(readLines(rmd))
  expect_identical(b$id, "abc123")
  expect_identical(doc_block_body(readLines(rmd), b[1, ]), "n = 7")
  expect_null(knitr::opts_hooks$get("label"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-knitr")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 2 ]`, starting with ``Error in `knit_print.gptr_session(s)`: could not find function "knit_print.gptr_session"``.

- [ ] **Step 3: Write the implementation**

Create `R/doc-knitr.R`:

```r
# doc-knitr.R -- knitr integration (plan P15; contract 5.1, 5.2, IC-07; report 14 section 4.6):
# the knit_print methods for sessions and System 1 vectors, registered lazily for the Suggests
# generic knitr::knit_print with P01's s3_register(), and the scoped label hook that skips the
# stale agent chunk of a block regenerated during the knit (report 14 section 2.1.3: an
# opts_hooks label hook disables a later chunk; it persists after knit() unless a knit_hooks
# document hook removes it). Layer L5.

#' knit_print method for sessions: the answer as Markdown; for a turn that ran live in this
#' process also the code it ran, so the first render is complete before the new agent chunk
#' exists (its chunk runs from the next render on)
#' @noRd
knit_print.gptr_session = function(x, ...) {
  txt = x$text %||% NA_character_
  out = if (length(txt) && !all(is.na(txt))) paste(txt[!is.na(txt)], collapse = "\n\n") else ""
  code = doc_knit_code(x)
  if (length(code)) out = c(out, "", "```r", code, "```")
  knitr::asis_output(paste(out, collapse = "\n"))
}

#' knit_print method for System 1 vectors: the one-line summary of their document block
#' @noRd
knit_print.gptr_s1 = function(x, ...) {
  knitr::asis_output(paste0("`", doc_s1_summary(x), "`\n"))
}

#' Recorded code of a session's last turn when it ran live (replayed sessions, teams and
#' fan-outs show none: their code is in the agent chunk)
#' @noRd
doc_knit_code = function(s) {
  d = session_data(s)
  if (isTRUE(d$replayed) || d$kind %in% c("team", "fanout", "replayed")) return(character())
  n = as.integer(d$turns %||% 0L)
  if (!n) return(character())
  tb = doc_turn_body(doc_turn_entries(s, n), with_out = FALSE)
  tb$body[!grepl("^#", tb$body)]
}

#' Skip the chunk with this label for the rest of the knit: a label hook (chaining any existing
#' one) sets eval = FALSE for skipped labels, and a document hook restores both hooks at the end
#' @noRd
doc_knitr_skip = function(label) {
  if (!requireNamespace("knitr", quietly = TRUE)) return(invisible(FALSE))
  st = doc_state()
  st$knitr_skip = union(st$knitr_skip, label)
  if (isTRUE(st$knitr_hooked)) return(invisible(TRUE))
  old_label = knitr::opts_hooks$get("label")
  old_doc = knitr::knit_hooks$get("document")
  knitr::opts_hooks$set(label = function(options) {
    if (is.function(old_label)) options = old_label(options)
    if (isTRUE(options$label %in% doc_state()$knitr_skip)) options$eval = FALSE
    options
  })
  knitr::knit_hooks$set(document = function(x) {
    doc_knitr_unhook(old_label, old_doc)
    if (is.function(old_doc)) old_doc(x) else x
  })
  st$knitr_hooked = TRUE
  invisible(TRUE)
}

#' Restore the label and document hooks that doc_knitr_skip() replaced
#' @noRd
doc_knitr_unhook = function(old_label, old_doc) {
  if (is.function(old_label)) {
    knitr::opts_hooks$set(label = old_label)
  } else {
    knitr::opts_hooks$delete("label")
  }
  if (is.function(old_doc)) {
    knitr::knit_hooks$set(document = old_doc)
  } else {
    knitr::knit_hooks$delete("document")
  }
  st = doc_state()
  st$knitr_skip = character()
  st$knitr_hooked = FALSE
  invisible(NULL)
}

on_load(s3_register("knitr::knit_print", "gptr_session"))
on_load(s3_register("knitr::knit_print", "gptr_s1"))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-knitr")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 21 ]` (the tests skip without knitr).

- [ ] **Step 5: Commit**

```bash
git add R/doc-knitr.R tests/testthat/test-doc-knitr.R
git commit -m "feat(doc): add knit_print methods and the scoped knitr label hook"
```

---

### Task 17: End-to-end record and replay through `gptr()`

**Files:**
- Test: `tests/testthat/test-doc-replay.R` (append)

**Interfaces:**
- Consumes: everything of Tasks 1-16 through the real gateway; P08 `gptr()` (call shapes, `.opts`, pipes,
  interpolation of `{gene}`), `gptr_trust(path = ".", trust = NULL)`, `replay_mode()`, `settings_write()`; P06
  `gptr_fork()`, `gptr_resume(block =)`, `gptr_last()`, `last_set()`, `session_enqueue(s, text, as, source)` (the
  pause-menu steer, source `"pause_menu"`), `session_data()`; P01 `gptr_fake_provider()`, `local_fake_provider()`,
  `fake_text()`, `fake_tool()`, `fake_requests()` (a script may be a `function(request)` reading `request$n` and
  `request$last_results`, 04 §12.1), `local_project()`, `local_gptr_options()`, `msg_text()`; P02
  `gptr_register()`; P11's `plan.pending` service (the plan-mode test skips without it); knitr.
- Produces: the end-to-end evidence of 05 P15 acceptance 2 (record then replay under `source()` with zero model
  calls, `keep.source = FALSE`, `gptr_source(replay = "record")` regeneration without running the old block,
  `.Random.seed` unchanged), 3, 4, 5 and the in-process items of 6.

Every recording uses the fake provider (offline, so `replay_guard()` lets it run when a test pins `replay =
"auto"`), mode `auto` and `gptr.unsafe_no_permissions` (the r calls run whether or not P11's mode policies are
loaded; IC-53 documents the switch for sandboxed runs). Calls that must look like console or Jupyter calls are built
with `as.call()` and a pasted prompt, so no frame's srcref points into this test file with the same prompt (the
locator would otherwise find the test file first, as it should for real scripts). The checks are those of 05 P15:
the fresh-clone rows copy only the document (and the S2 cache where the row says so) into a new project without
`sessions/`, release the recording session (`last_set(NULL)`, `gc()`), and assert that nothing is requested and no
block runs twice; NS-3 is re-sourced twice with the main line and the fork's overlay compared each time (IC-46); the
parameterised row knits one Rmd with two values of `{gene}` (IC-45); the console row binds a transcript with
`gptr_doc(format = "transcript")`, steers turn two through `session_enqueue(source = "pause_menu")` and re-sources
the transcript as one session (IC-49).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-replay.R`:

```r
# ---- end to end through gptr() and the fake provider (05 P15 acceptance 2-6) --------------------

# A temporary project where gptr() records with the fake provider: replies are scripted, the
# model is fake/fake-1, mode auto (no human is asked), recording consent by option, replay auto.
# gptr.unsafe_no_permissions keeps the scripted r calls running when no mode policy is loaded
# (P11 is an M2 plan, but not a dependency of P15; IC-53 documents the switch for sandboxed runs)
local_doc_e2e = function(script, record = "auto", .env = parent.frame()) {
  root = local_project(.env = .env)
  local_gptr_options(record = record, replay = "auto", model = "fake/fake-1", mode = "auto",
                     unsafe_no_permissions = TRUE, .env = .env)
  fake = local_fake_provider(script, .env = .env)
  old = the$doc_binding
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  the$doc_binding = NULL
  list(root = root, fake = fake)
}

# A gptr() call built at run time, as the console and Jupyter evaluate it: the call carries no
# srcref and its prompt is not a literal of this test file, so the locator cannot mistake the
# test file for the document
doc_e2e_call = function(..., prompt) {
  as.call(c(list(as.name("gptr")), list(...), list(prompt)))
}

# Source a document into a fresh environment (whose parent finds gptr) and return it
doc_e2e_source = function(path, envir = new.env(parent = globalenv()), keep_source = TRUE) {
  source(path, local = envir, keep.source = keep_source)
  envir
}

test_that("a recorded block replays under source() with zero model calls (acceptance 2)", {
  x = local_doc_e2e(list(fake_tool("r", code = "n_rows = nrow(d)\nn_rows", note = "count"),
                         fake_text("There are 4 rows.")))
  f = file.path(x$root, "analysis.R")
  writeLines(c("res = gptr(\"Count the rows of d\", d)", "check = n_rows * 2"), f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(a = 1:4)
  doc_e2e_source(f, e1)
  expect_identical(length(fake_requests(x$fake)), 2L)
  txt = readLines(f)
  expect_match(txt[2], "^# >>> gptr:[0-9a-f]{6} model=fake/fake-1 date=")
  expect_identical(txt[3:6], c("n_rows = nrow(d)", "n_rows", "#> [1] 4", "## Decision: count"))
  expect_identical(e1$check, 8)
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(a = 1:4)
  doc_e2e_source(f, e2)
  expect_identical(length(fake_requests(x$fake)), 2L)
  expect_identical(e2$n_rows, 4L)
  expect_identical(e2$check, 8)
  expect_s3_class(e2$res, "gptr_session")
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_identical(readLines(f), txt)
  e3 = new.env(parent = globalenv())
  e3$d = data.frame(a = 1:4)
  doc_e2e_source(f, e3, keep_source = FALSE)
  expect_identical(e3$check, 8)
  expect_identical(length(fake_requests(x$fake)), 2L)
})

test_that("a stale prompt regenerates through gptr_source(replay = \"record\") (acceptance 2)", {
  x = local_doc_e2e(list(fake_tool("r", code = "old_ran = TRUE"), fake_text("old"),
                         fake_tool("r", code = "new_ran = TRUE"), fake_text("new")))
  f = file.path(x$root, "analysis.R")
  writeLines("res = gptr(\"Do the first thing\")", f)
  doc_e2e_source(f)
  id = doc_find_blocks(readLines(f))$id
  txt = readLines(f)
  txt[1] = "res = gptr(\"Do the second thing\")"
  writeLines(txt, f)
  e = new.env(parent = globalenv())
  out = gptr_source(f, replay = "record", envir = e)
  expect_identical(length(fake_requests(x$fake)), 4L)
  expect_true(e$new_ran)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  expect_identical(out$id, id)
  expect_identical(out$action, "regenerated")
  expect_identical(doc_block_body(readLines(f), doc_find_blocks(readLines(f))), "new_ran = TRUE")
})

test_that("replay is forced under R CMD check examples and blocks real models (acceptance 3)", {
  local_project()
  withr::local_options(gptr.replay = NULL)
  withr::local_envvar(GPTR_REPLAY = NA, `_R_CHECK_PACKAGE_NAME_` = "gptr", TESTTHAT = "false")
  expect_identical(replay_mode(), "replay")
  withr::local_envvar(TESTTHAT = "true")
  expect_identical(replay_mode(), "auto")
  withr::local_envvar(GPTR_REPLAY = "replay")
  online = gptr_fake_provider(list("never sent"), name = "online")
  online$offline = FALSE
  off = gptr_register(online)
  withr::defer(off())
  local_gptr_options(model = "online/online-1", mode = "auto", record = "auto")
  f = file.path(getwd(), "loop.R")
  writeLines(c("for (i in 1:2) {", "  x = gptr(\"Summarise step {i}\")", "}"), f)
  expect_error(doc_e2e_source(f), class = "gptr_error_not_recorded")
  expect_length(fake_requests(online), 0L)
})

test_that("value= replays by name and no document gets a $value line (acceptance 4)", {
  x = local_doc_e2e(list(
    fake_tool("r", code = "markers = c(\"CD3E\", \"MS4A1\")\ngptr_return(markers)"),
    fake_text("Two markers.")))
  f = file.path(x$root, "analysis.R")
  writeLines("res = gptr(\"Find the markers\")", f)
  doc_e2e_source(f)
  txt = readLines(f)
  expect_match(txt[2], " value=markers", fixed = TRUE)
  expect_false(any(grepl("$value", txt, fixed = TRUE)))
  expect_false(any(grepl("gptr_return", txt, fixed = TRUE)))
  e = doc_e2e_source(f)
  expect_identical(e$res$value, c("CD3E", "MS4A1"))
  expect_length(fake_requests(x$fake), 2L)
})

test_that("documents are written only with consent; a project cannot grant it (acceptance 5)", {
  x = local_doc_e2e(function(request) {
    if (request$n %% 2L == 1L) fake_tool("r", code = "n = 1") else fake_text("one.")
  }, record = NULL)
  f = file.path(x$root, "analysis.R")
  writeLines("res = gptr(\"Set n\")", f)
  local_gptr_options(interactive = FALSE)
  doc_e2e_source(f)
  expect_identical(readLines(f), "res = gptr(\"Set n\")")
  writeLines("{\"version\": 1, \"record\": \"auto\"}",
             file.path(x$root, ".gptr", "settings.json"))
  gptr_trust(x$root, trust = TRUE)
  doc_e2e_source(f)
  expect_identical(readLines(f), "res = gptr(\"Set n\")")
  settings_write("user", list(record = "auto"))
  withr::defer(settings_write("user", list(record = NULL)))
  doc_e2e_source(f)
  expect_length(doc_find_blocks(readLines(f))$id, 1L)
})

test_that("a fresh clone without consent replays with zero calls and runs each block once (5)", {
  x = local_doc_e2e(list(fake_tool("r", code = "hits = hits + 1"), fake_text("Counted.")))
  f = file.path(x$root, "analysis.R")
  writeLines(c("hits = 0", "res = gptr(\"Count once\")"), f)
  doc_e2e_source(f)
  clone = withr::local_tempdir("gptr-clone-")
  file.copy(f, file.path(clone, "analysis.R"))
  withr::local_dir(clone)
  local_gptr_options(project_root = path_norm(clone), record = NULL, interactive = FALSE)
  e = doc_e2e_source(file.path(clone, "analysis.R"))
  expect_identical(e$hits, 1)
  expect_length(fake_requests(x$fake), 2L)
  expect_identical(readLines(file.path(clone, "analysis.R")), readLines(f))
})

test_that("gptr_return() and gptr$out() calls are dropped and the block re-sources (6)", {
  script = function(request) {
    if (request$n == 1L) {
      return(fake_tool("r", code = "cat(rep(\"line\", 400), sep = \"\\n\")", record = FALSE))
    }
    if (request$n == 2L) {
      txt = msg_text(request$last_results[[1L]])
      id = regmatches(txt, regexec("gptr\\$out\\(\"(o[0-9a-f]{6})\"", txt))[[1L]][2L]
      return(fake_tool("r", code = paste0("fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\n",
                                          "gptr$out(\"", id, "\", lines = 1)")))
    }
    fake_text("Fitted.")
  }
  x = local_doc_e2e(script)
  local_gptr_options(r_output_tokens = 200L)
  f = file.path(x$root, "analysis.R")
  writeLines("res = gptr(\"Fit mpg on weight\")", f)
  doc_e2e_source(f)
  body = doc_block_body(readLines(f), doc_find_blocks(readLines(f)))
  # the code of gptr_return() and gptr$out() is dropped; P10's flat `outputs` may keep the
  # printed line of gptr$out() as a #> comment, which re-sources as a comment
  expect_identical(body[!startsWith(body, "#>")], "fit = lm(mpg ~ wt, data = mtcars)")
  expect_match(readLines(f)[2], " value=fit", fixed = TRUE)
  e = doc_e2e_source(f)
  expect_s3_class(e$res$value, "lm")
  expect_length(fake_requests(x$fake), 3L)
})

test_that("re-sourcing NS-3 twice keeps the main line and the fork's overlay apart (IC-46)", {
  x = local_doc_e2e(list(
    fake_tool("r", code = "qc_flags = d$mt > 20\ngptr_return(qc_flags)"), fake_text("Flagged."),
    fake_tool("r", code = "qc_flags = d$mt > 15\ngptr_return(qc_flags)"), fake_text("Updated."),
    fake_tool("r", code = "qc_flags = d$mt > 10"), fake_text("Tried 10%.")))
  f = file.path(x$root, "ns3.R")
  writeLines(c("qc = gptr(\"Run QC on d and flag low-quality cells\", d)",
               "qc |> gptr(\"Use 15% as the cut-off instead of 20%\")",
               "gptr_fork(qc) |> gptr(\"Try a 10% cut-off as well\")"), f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(mt = c(5, 12, 18, 25))
  doc_e2e_source(f, e1)
  b = doc_find_blocks(readLines(f))
  expect_length(b$id, 3L)
  expect_match(readLines(f)[b$start[3]], " fork=s[0-9a-f]{10}:2", perl = TRUE)
  fork_body = doc_block_body(readLines(f), b[3, ])
  expect_identical(fork_body[1], "local({")
  expect_identical(fork_body[3], paste0("}, envir = gptr_resume(block = \"", b$id[3],
                                        "\")$envir)"))
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(mt = c(5, 12, 18, 25))
  for (pass in 1:2) {
    doc_e2e_source(f, e2)
    expect_identical(e2$qc_flags, c(FALSE, FALSE, TRUE, TRUE))
    expect_identical(e2$qc$value, c(FALSE, FALSE, TRUE, TRUE))
    overlay = gptr_resume(block = b$id[3])$envir
    expect_false(identical(overlay, e2))
    expect_identical(get("qc_flags", envir = overlay, inherits = FALSE), c(FALSE, TRUE, TRUE, TRUE))
  }
  expect_length(fake_requests(x$fake), 6L)
})

test_that("a replayed pipe chain is one session; a clone continues from its document (IC-46)", {
  x = local_doc_e2e(list(fake_tool("r", code = "a = 1"), fake_text("one."),
                         fake_tool("r", code = "b = 2"), fake_text("two."),
                         fake_text("three, live.")))
  f = file.path(x$root, "chain.R")
  writeLines("chain = gptr(\"step one\") |> gptr(\"step two\")", f)
  doc_e2e_source(f)
  b = doc_find_blocks(readLines(f))
  expect_match(readLines(f)[b$start[2]], " call=2", fixed = TRUE)
  clone = withr::local_tempdir("gptr-clone-")
  file.copy(f, file.path(clone, "chain.R"))
  # a clone that committed .gptr/cache (S2 answers) but not .gptr/sessions; file.copy() copies a
  # directory only into an existing directory
  dir.create(file.path(clone, ".gptr"))
  expect_true(file.copy(file.path(x$root, ".gptr", "cache"), file.path(clone, ".gptr"),
                        recursive = TRUE))
  expect_false(dir.exists(file.path(clone, ".gptr", "sessions")))
  withr::local_dir(clone)
  local_gptr_options(project_root = path_norm(clone))
  last_set(NULL)
  invisible(gc())
  e = doc_e2e_source(file.path(clone, "chain.R"))
  d = session_data(e$chain)
  expect_identical(sort(d$seen), sort(b$id))
  expect_identical(d$history_source, "reconstructed")
  expect_identical(e$chain$text, "two.")
  expect_length(fake_requests(x$fake), 4L)
  local_gptr_options(quiet = FALSE)
  expect_message(e$chain |> gptr("step three", .opts = list(context = "none")),
                 class = "gptr_message_notice")
  req = fake_requests(x$fake)[[5L]]
  texts = vapply(req$messages, function(m) msg_text(m), "")
  expect_true("step one" %in% texts)
})

test_that("two values of an interpolated {gene} never replay each other's block (IC-45)", {
  skip_if_not_installed("knitr")
  x = local_doc_e2e(list(fake_tool("r", code = "plotted = gene"), fake_text("Plotted.")))
  rmd = file.path(x$root, "report.Rmd")
  writeLines(c("```{r ask}", "gptr(\"Plot the expression of {gene}\")", "```"), rmd)
  for (g in c("CD3E", "MS4A1")) {
    e = new.env(parent = globalenv())
    e$gene = g
    knitr::knit(rmd, output = file.path(x$root, "report.md"), envir = e, quiet = TRUE)
    expect_identical(e$plotted, g)
  }
  expect_length(fake_requests(x$fake), 4L)
  b = doc_find_blocks(readLines(rmd))
  expect_length(b$id, 1L)
  expect_identical(b$header[[1]]$args, args_hash("gene=MS4A1"))
})

test_that("a two-turn console session with a menu steer re-sources as one session (IC-49)", {
  steer_once = new.env()
  script = function(request) {
    if (request$n == 3L && is.null(steer_once$done)) {
      steer_once$done = TRUE
      session_enqueue(gptr_last(), "use log scale", as = "steer", source = "pause_menu")
    }
    switch(as.character(request$n),
           "1" = fake_tool("r", code = "fit = lm(mpg ~ wt, data = mtcars)"),
           "2" = fake_text("Fitted."),
           "3" = fake_tool("r", code = "p = predict(fit)"),
           fake_text("Predicted on the log scale."))
  }
  x = local_doc_e2e(script)
  t = file.path(x$root, ".gptr", "transcripts", "console.R")
  dir.create(dirname(t), recursive = TRUE)
  gptr_doc(t, format = "transcript")
  e = new.env(parent = globalenv())
  s = eval(doc_e2e_call(prompt = paste("fit mpg on", "weight")), e)
  e$s = s
  eval(doc_e2e_call(as.name("s"), prompt = paste("add", "predictions")), e)
  tr = readLines(t)
  hex = substr(sub("^s", "", s$id), 1L, 6L)
  expect_true(paste0("s_", hex, " = gptr(\"fit mpg on weight\")") %in% tr)
  expect_true(paste0("s_", hex, " |> gptr(\"add predictions\")") %in% tr)
  expect_true("## Steer: use log scale" %in% tr)
  e2 = new.env(parent = globalenv())
  e2$library = function(...) invisible(NULL)
  local_gptr_options(replay = "replay")
  gptr_doc(FALSE)
  doc_e2e_source(t, e2)
  s2 = get(paste0("s_", hex), envir = e2)
  expect_identical(length(session_data(s2)$seen), 2L)
  expect_true(is.numeric(e2$p))
  expect_length(fake_requests(x$fake), 4L)
})

test_that("a plan-mode run records only its plan line (IC-48)", {
  skip_if_not(ext_service_has("plan.pending"), "plan mode (P11) is not loaded")
  x = local_doc_e2e(list(fake_tool("r", code = "x = 1"),
                         fake_text("Plan:\n1. Load the data\n2. Fit the model")))
  f = file.path(x$root, "plan.R")
  writeLines("p = gptr(\"Plan the analysis\", mode = \"plan\")", f)
  doc_e2e_source(f)
  b = doc_find_blocks(readLines(f))
  body = doc_block_body(readLines(f), b)
  expect_length(body, 1L)
  expect_match(body, "^## Plan: ")
})

test_that("a block with a nested sub-agent call replays with zero requests (IC-47)", {
  x = local_doc_e2e(list(fake_tool("r", code = "sub = gptr(\"Summarise d\")"),
                         fake_text("d has 4 rows."), fake_text("Done.")))
  f = file.path(x$root, "nested.R")
  writeLines("res = gptr(\"Analyse d with a helper\")", f)
  e1 = new.env(parent = globalenv())
  e1$d = data.frame(a = 1:4)
  doc_e2e_source(f, e1)
  expect_identical(doc_block_body(readLines(f), doc_find_blocks(readLines(f))),
                   "sub = gptr(\"Summarise d\")")
  n = length(fake_requests(x$fake))
  local_gptr_options(replay = "replay")
  e2 = new.env(parent = globalenv())
  e2$d = data.frame(a = 1:4)
  doc_e2e_source(f, e2)
  expect_length(fake_requests(x$fake), n)
  expect_identical(e2$sub$text, "d has 4 rows.")
})

test_that("an open notebook is never written; gptr_doc(sync = TRUE) applies it (IC-50)", {
  x = local_doc_e2e(list(fake_tool("r", code = "m = mean(mtcars$mpg)"), fake_text("20.09.")))
  nb = file.path(x$root, "analysis.ipynb")
  file.copy(testthat::test_path("fixtures", "docs", "floats.ipynb"), nb)
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  e = new.env(parent = globalenv())
  out = cli::cli_fmt(eval(doc_e2e_call(prompt = paste("summarise the", "mpg column")), e))
  expect_true("m = mean(mtcars$mpg)" %in% out)
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  withr::local_options(jupyter.in_kernel = NULL)
  withr::local_envvar(JPY_SESSION_NAME = NA)
  gptr_doc(nb, sync = TRUE)
  cells = nb_parse(doc_read(nb)$lines)$cells
  expect_match(cells[[4]]$id, "^gptr-[0-9a-f]{6}$")
  expect_identical(unlist(cells[[4]]$source), "m = mean(mtcars$mpg)")
})
```

- [ ] **Step 2: Run it to verify it fails**

These tests exercise code that Tasks 1-16 already wrote, so first prove that they catch a broken replay: in
`R/doc-replay.R`, temporarily add `return(route_pass())` as the first line of the body of `doc_route_run()`, then run:

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: failures in most rows, starting with ``Expected `length(fake_requests(x$fake))` to be identical to 2L.``
in "a recorded block replays under source() with zero model calls (acceptance 2)": every replay now asks the model
again (and records a second block).

- [ ] **Step 3: Write the implementation**

No new code: remove the temporary `return(route_pass())` line from `doc_route_run()`, so `R/doc-replay.R` is again
exactly the file of Tasks 7, 12-15.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 279 ]` with P11 loaded (without its `plan.pending` service the plan-mode
test skips: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 277 ]`).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-doc-replay.R
git commit -m "test(doc): record and replay end to end through gptr() and the fake provider"
```

---

### Task 18: Rscript, knitr and Quarto end to end

**Files:**
- Test: `tests/testthat/test-doc-io.R` (append), `tests/testthat/test-doc-knitr.R` (append)

**Interfaces:**
- Consumes: everything of Tasks 1-16; P01 `rscript_path()` ("`file.path(R.home("bin"), "Rscript")`", IC-60) and
  `tracemem_loader()` from P01's `tests/testthat/helper-tracemem.R` (the line that loads gptr in a child: the
  installed package under R CMD check, else `pkgload::load_all()` of the source tree, which appears only inside the
  generated script text, IC-71); P04 `pid_alive()`; processx (`run()`, `process$new()`); knitr; the Quarto CLI when
  installed (`QUARTO_R` points it at this R, so the dummy `Rscript` that R CMD check puts first on `PATH` is never
  used, IC-60).
- Produces: the evidence of 05 P15 acceptance 2 ("an Rscript run writes its blocks only at exit (sidecar survives a
  crash)", "knitr and Quarto record/replay") and 6 ("re-sources cleanly under `source()` and Rscript", "an Rscript
  run killed with SIGTERM after two calls leaves a sidecar whose upserts the next run applies without overwriting
  user edits").

The child scripts record with an offline fake provider and `gptr.unsafe_no_permissions`; the parent sets
`GPTR_PROJECT_ROOT` to the test project (the child cannot see the parent's `gptr.project_root` option) and the
replay mode through `GPTR_REPLAY`. The SIGTERM row skips on Windows (no SIGTERM); every child row skips on CRAN.
Report 14 §2.1.2 is the reason for the first row: the child checks that its own script is unchanged while it runs.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-doc-io.R`:

```r
# ---- Rscript runs end to end (05 P15 acceptance 2 and 6; IC-51) --------------------------------

# A script run by `Rscript`: gptr loaded as P01's copy harness loads it (tracemem_loader(): the
# installed package under R CMD check, else the source tree), an offline fake provider, consent
# to record by option, then `body`
doc_child_script = function(path, fake, body) {
  writeLines(c(tracemem_loader(),
               paste("options(gptr.model = \"fake/fake-1\", gptr.mode = \"auto\",",
                     "gptr.record = \"auto\", gptr.quiet = TRUE, gptr.r_output_tokens = 200L,",
                     "gptr.unsafe_no_permissions = TRUE)"),
               fake, "invisible(gptr_register(fake))", body), path)
  invisible(path)
}

# Run a script (or `args`) with Rscript in the project; GPTR_REPLAY sets the replay mode
doc_child_env = function(root, replay) {
  c("current", GPTR_PROJECT_ROOT = root, GPTR_REPLAY = replay,
    R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
}

doc_child_run = function(root, args, replay = "auto") {
  processx::run(rscript_path(), c("--vanilla", args), wd = root,
                env = doc_child_env(root, replay), error_on_status = FALSE, timeout = 300)
}

doc_two_steps = paste0("fake = gptr_fake_provider(list(",
                       "list(tool = 'r', input = list(code = 'n1 = 1')), 'one.', ",
                       "list(tool = 'r', input = list(code = 'n2 = n1 + 1')), 'two.'))")

test_that("an Rscript run writes its blocks only at exit and the next run replays them", {
  skip_on_cran()
  root = local_project()
  f = file.path(root, "job.R")
  doc_child_script(f, doc_two_steps, c(
    "path = sub('^--file=', '', grep('^--file=', commandArgs(FALSE), value = TRUE))",
    "md5 = unname(tools::md5sum(path))",
    "a = gptr('first step')",
    "cat('UNCHANGED', identical(unname(tools::md5sum(path)), md5), '\\n')",
    "b = gptr('second step')",
    "cat('REQUESTS', length(fake$log$requests), 'N2', n2, '\\n')"))
  res = doc_child_run(root, f)
  expect_identical(res$status, 0L)
  expect_match(res$stdout, "UNCHANGED TRUE", fixed = TRUE)
  expect_match(res$stdout, "REQUESTS 4 N2 2", fixed = TRUE)
  expect_length(doc_find_blocks(readLines(f))$id, 2L)
  expect_null(doc_sidecar_read(f))
  md5 = tools::md5sum(f)
  again = doc_child_run(root, f, replay = "replay")
  expect_identical(again$status, 0L)
  expect_match(again$stdout, "REQUESTS 0 N2 2", fixed = TRUE)
  expect_identical(tools::md5sum(f), md5)
})

test_that("SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)", {
  skip_on_cran()
  skip_on_os("windows")
  root = local_project()
  f = file.path(root, "job.R")
  doc_child_script(f, doc_two_steps, c("a = gptr('first step')", "b = gptr('second step')",
                                       "cat('READY\\n')", "Sys.sleep(300)"))
  before = readLines(f)
  p = processx::process$new(rscript_path(), c("--vanilla", f), wd = root,
                            env = doc_child_env(root, "auto"), stdout = "|", stderr = "|")
  withr::defer(if (p$is_alive()) p$kill())
  out = ""
  deadline = Sys.time() + 240
  while (!grepl("READY", out, fixed = TRUE) && p$is_alive() && Sys.time() < deadline) {
    p$poll_io(1000)
    out = paste0(out, p$read_output())
  }
  expect_match(out, "READY", fixed = TRUE)
  p$signal(tools::SIGTERM)
  p$wait(10000)
  expect_identical(readLines(f), before)
  rec = doc_sidecar_read(f)
  expect_length(rec$upserts, 2L)
  expect_false(pid_alive(rec$pid, rec$create_time))
  writeLines(c("# my notes", before, "z = 0"), f)
  gptr_blocks(f)
  txt = readLines(f)
  expect_identical(txt[1], "# my notes")
  expect_identical(txt[length(txt)], "z = 0")
  b = doc_find_blocks(txt)
  expect_setequal(b$id, vapply(rec$upserts, function(u) u$block_id, ""))
  expect_null(doc_sidecar_read(f))
})

test_that("gptr_return() and gptr$out() calls re-source cleanly under Rscript and source() (6)", {
  skip_on_cran()
  root = local_project()
  f = file.path(root, "fit.R")
  fake = r"---(fake = gptr_fake_provider(function(request) {
  if (request$n == 1L) {
    return(list(tool = "r", input = list(code = "cat(rep('line', 400), sep = '\n')",
                                         record = FALSE)))
  }
  if (request$n == 2L) {
    txt = paste(unlist(lapply(request$last_results[[1L]]$content, function(b) b$text)),
                collapse = "\n")
    id = regmatches(txt, regexec('gptr[$]out[(]"(o[0-9a-f]{6})"', txt))[[1L]][2L]
    code = paste0("fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\ngptr$out(\"", id,
                  "\", lines = 1)")
    return(list(tool = "r", input = list(code = code)))
  }
  "Fitted."
}))---"
  doc_child_script(f, fake, c("res = gptr('Fit mpg on weight')",
                              "stopifnot(inherits(res$value, 'lm'))",
                              "cat('REQUESTS', length(fake$log$requests), '\\n')"))
  rec = doc_child_run(root, f)
  expect_identical(rec$status, 0L)
  expect_match(rec$stdout, "REQUESTS 3", fixed = TRUE)
  txt = readLines(f)
  b = doc_find_blocks(txt)
  body = doc_block_body(txt, b)
  expect_identical(body[!startsWith(body, "#>")], "fit = lm(mpg ~ wt, data = mtcars)")
  expect_match(txt[b$start], " value=fit", fixed = TRUE)
  rs = doc_child_run(root, f, replay = "replay")
  expect_identical(rs$status, 0L)
  expect_match(rs$stdout, "REQUESTS 0", fixed = TRUE)
  driver = file.path(root, "driver.R")
  writeLines(sprintf("source('%s')", normalizePath(f, winslash = "/")), driver)
  src = doc_child_run(root, driver, replay = "replay")
  expect_identical(src$status, 0L)
  expect_match(src$stdout, "REQUESTS 0", fixed = TRUE)
})
```

Append to `tests/testthat/test-doc-knitr.R`:

```r
# ---- knitr and Quarto through gptr() and the fake provider (05 P15 acceptance 2) ---------------

test_that("knitr records an agent chunk through gptr() and replays it on the next knit", {
  skip_if_not_installed("knitr")
  root = local_project()
  local_gptr_options(record = "auto", replay = "auto", model = "fake/fake-1", mode = "auto",
                     unsafe_no_permissions = TRUE)
  fake = local_fake_provider(list(
    fake_tool("r", code = "n = nchar(\"count letters in this prompt\")"), fake_text("Counted.")))
  rmd = file.path(root, "report.Rmd")
  file.copy(testthat::test_path("fixtures", "docs", "report.Rmd"), rmd)
  out = file.path(root, "report.md")
  knitr::knit(rmd, output = out, envir = new.env(parent = globalenv()), quiet = TRUE)
  expect_length(fake_requests(fake), 2L)
  expect_match(doc_rmd_chunks(readLines(rmd))$label[3], "^gptr-[0-9a-f]{6}$")
  md = readLines(out)
  expect_true(any(grepl("Counted.", md, fixed = TRUE)))
  expect_true("n = nchar(\"count letters in this prompt\")" %in% md)
  md5 = tools::md5sum(rmd)
  e = new.env(parent = globalenv())
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  expect_length(fake_requests(fake), 2L)
  expect_identical(e$n, 28L)
  expect_identical(tools::md5sum(rmd), md5)
})

test_that("quarto render records a #| label agent chunk and the next render replays it", {
  skip_on_cran()
  quarto = Sys.which("quarto")
  skip_if(!nzchar(quarto), "quarto is not installed")
  root = local_project()
  qmd = file.path(root, "report.qmd")
  writeLines(c(
    "---", "title: \"Report\"", "format: md", "---", "", "```{r setup}", "#| include: false",
    tracemem_loader(),
    paste("options(gptr.model = \"fake/fake-1\", gptr.mode = \"auto\", gptr.record = \"auto\",",
          "gptr.quiet = TRUE, gptr.unsafe_no_permissions = TRUE)"),
    paste0("fake = gptr_fake_provider(list(list(tool = \"r\", input = list(code = \"n = 28L\")),",
           " \"Counted.\"))"),
    "invisible(gptr_register(fake))", "```", "", "```{r}", "#| label: ask",
    "gptr(\"count letters in this prompt\")", "```", "",
    "Requests: `r length(fake$log$requests)`"), qmd)
  render = function(replay) {
    processx::run(quarto, c("render", "report.qmd"), wd = root,
                  env = c("current", GPTR_PROJECT_ROOT = root, GPTR_REPLAY = replay,
                          QUARTO_R = R.home("bin"),
                          R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)),
                  error_on_status = FALSE, timeout = 600)
  }
  r1 = render("auto")
  expect_identical(r1$status, 0L)
  expect_true(any(grepl("^#\\| label: gptr-[0-9a-f]{6}$", readLines(qmd))))
  expect_true(any(grepl("Requests: 2", readLines(file.path(root, "report.md")), fixed = TRUE)))
  md5 = tools::md5sum(qmd)
  r2 = render("replay")
  expect_identical(r2$status, 0L)
  expect_true(any(grepl("Requests: 0", readLines(file.path(root, "report.md")), fixed = TRUE)))
  expect_identical(tools::md5sum(qmd), md5)
})
```

- [ ] **Step 2: Run it to verify it fails**

These tests exercise code that Tasks 1-16 already wrote, so first prove that they catch a broken deferred writer: in
`R/doc-io.R`, temporarily make `doc_finalizer_ensure()` return `invisible(NULL)` as its first line, then run:

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io|doc-knitr")'`

Expected: failures in "an Rscript run writes its blocks only at exit and the next run replays them", such as
``Expected `doc_find_blocks(readLines(f))$id` to have length 2`` (no finalizer, so nothing is written at exit) and
the replay run's ``Expected `again$stdout` to match regexp "REQUESTS 0 N2 2"``.

- [ ] **Step 3: Write the implementation**

No new code: remove the temporary first line of `doc_finalizer_ensure()`, so `R/doc-io.R` is again exactly the file
of Tasks 4, 8, 10 and 11.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-io|doc-knitr")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 161 ]` without Quarto on `PATH` (the Quarto test skips; with Quarto:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 167 ]`). The child rows take a few minutes; on Windows the SIGTERM row skips too.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-doc-io.R tests/testthat/test-doc-knitr.R
git commit -m "test(doc): Rscript deferred writes, SIGTERM recovery, knitr and Quarto end to end"
```

---

### Task 19: The NS-7 golden transcript, documentation, NAMESPACE and plan acceptance

**Files:**
- Create: `dev/bench/tokens/fixtures/ns07-script-history.json`
- Modify: `dev/bench/tokens/baseline.csv` (one row, written by the runner)
- Generate: `NAMESPACE`, `man/gptr_doc.Rd`, `man/gptr_source.Rd`, `man/gptr_blocks.Rd`, `man/gptr_cache.Rd`

**Interfaces:**
- Consumes: P07's golden-transcript runner `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]`
  (a fixture scripts one north-star session: `files`, `objects` (R expressions evaluated with `baseenv()` as
  parent, after the runner has set the working directory and `GPTR_PROJECT_ROOT` to the fixture's project),
  `environment`, `standins`, `turns` with `steps`; gates "prefix +2%, input and output totals +5%, requests and image
  tokens +0, catalog +5%, facts no loss"); rtiktoken (a development tool, not a dependency); Tasks 13-14 (the
  `documents` section appears when `doc.site` answers a binding; `gptr_doc()`).
- Produces: the NS-7 fixture and its baseline row (IC-73); the Rd files and `NAMESPACE` entries `export(gptr_doc)`,
  `export(gptr_source)`, `export(gptr_blocks)`, `export(gptr_cache)`.

NS-7 (02-north-star-examples.md §7; architecture §10.5) is NS-1's request recorded into `analysis.R`: the console
session is bound to the document, so the frozen prefix carries the `<documents>` section and the `r` schema variant
with `record` and `note` (IC-68), and the turn is the composed `r` call with a decision note. The runner has no
document field, so the fixture binds the document through its one code hook, an `objects` expression that calls
`gptr::gptr_doc()` (the object is named `.doc`, so the workspace listing ignores it); `doc.site` ignores the binding
once the runner deletes the fixture's project, so later fixtures are not affected.

- [ ] **Step 1: Write the failing test**

Check the development tool first: `Rscript --vanilla -e 'cat(requireNamespace("rtiktoken", quietly = TRUE), "\n")'`
must print `TRUE`. If it prints `FALSE`, stop and ask the maintainer to install rtiktoken (CRAN) into their library;
do not install it from a plan step (conventions §1).

Create `dev/bench/tokens/fixtures/ns07-script-history.json`:

```json
{
  "id": "ns07-script-history",
  "north_star": 7,
  "description": "gptr(\"cluster the cells ...\") at the console with analysis.R bound by gptr_doc(): the standard interactive prefix with the <documents> section and the r schema variant with record and note; one composed r call with a decision note, then the answer.",
  "mode": "manual",
  "human": true,
  "preset": null,
  "models": [
    "benchmain/benchmain-1"
  ],
  "standins": [
    "artifacts",
    "system1",
    "skills",
    "r_env"
  ],
  "environment": "Date: 2026-09-29\nWorking directory: /Users/me/project (project root)\nDocument: analysis.R\nFront end: interactive console (RStudio)\nR 4.4.3 on aarch64-apple-darwin20; RAM 24 GB (17 GB free)",
  "files": {
    "analysis.R": "library(gptr)\n\ngptr(\"cluster the cells and show me the markers for the three largest clusters\")",
    "AGENTS.md": "# AGENTS.md\n- Style: = for assignment, |> for pipes, snake_case.\n- Single-cell data: Seurat v5; keep pbmc as the main object."
  },
  "objects": {
    "pbmc": "data.frame(cell = sprintf('c%04d', 1:600), nCount_RNA = 1200 + (1:600) %% 97, percent.mt = round(1 + ((1:600) %% 13) / 2, 1), cluster = rep(0:4, 120))",
    ".doc": "gptr::gptr_doc(file.path(getwd(), 'analysis.R'))"
  },
  "facts": [
    "pbmc",
    "nCount_RNA",
    "cluster"
  ],
  "turns": [
    {
      "prompt": "cluster the cells and show me the markers for the three largest clusters",
      "source": "prompt",
      "context": [
        {
          "label": "pbmc",
          "class": "data.frame"
        }
      ],
      "steps": [
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_01",
              "name": "r",
              "input": {
                "code": "pbmc = FindNeighbors(pbmc, dims = 1:30)\npbmc = FindClusters(pbmc, resolution = 0.8)\nmarkers = FindAllMarkers(subset(pbmc, idents = 0:2), only.pos = TRUE)\nnrow(markers)",
                "note": "resolution 0.8 chosen because 0.4 merged the two monocyte groups."
              },
              "result": "[1] 4211\n[r] ~ pbmc <Seurat 2,700 cells x 13,714 features>, + markers <data.frame 4,211 x 7>\n[status: ok; 4 of 4 top-level expressions completed; 38.2s]",
              "details": {
                "code": "pbmc = FindNeighbors(pbmc, dims = 1:30)\npbmc = FindClusters(pbmc, resolution = 0.8)\nmarkers = FindAllMarkers(subset(pbmc, idents = 0:2), only.pos = TRUE)\nnrow(markers)",
                "status": "ok",
                "note": "resolution 0.8 chosen because 0.4 merged the two monocyte groups."
              }
            }
          ]
        },
        {
          "text": "Clustered at resolution 0.8 (0.4 merged the two monocyte groups) and found 4,211 marker genes for the three largest clusters; they are in `markers`, and the code is recorded in a block below your gptr() call in analysis.R.",
          "calls": []
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla dev/bench/tokens/run.R --check`

Expected: the run prints the static prefixes and one row per fixture, including `ns07-script-history`, then fails
with `gptr_error_token_regression`: `Token-efficiency regression:` and
`  ns07-script-history: no baseline row (run with --update ns07-script-history)`.

- [ ] **Step 3: Write the implementation**

Record the baseline row and generate the documentation:

```bash
Rscript --vanilla dev/bench/tokens/run.R --update ns07-script-history
Rscript --vanilla -e 'devtools::document()'
```

Expected: `baseline written: ns07-script-history`; `devtools::document()` writes `man/gptr_doc.Rd`,
`man/gptr_source.Rd`, `man/gptr_blocks.Rd`, `man/gptr_cache.Rd` and adds `export(gptr_blocks)`,
`export(gptr_cache)`, `export(gptr_doc)` and `export(gptr_source)` to `NAMESPACE` (the `knit_print` methods are
registered at load time by `s3_register()` and get no `NAMESPACE` entry). Check the new row: its `prefix` must be
larger than the `ns02-mixed-model` prefix by the `<documents>` section and the `record`/`note` schema difference
(about 186 + 51 o200k tokens, 03 §12.1 and IC-68: 2,750 -> 2,987).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla dev/bench/tokens/run.R --check`

Expected: the last line `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`, where `<n>`
is the number of files in `dev/bench/tokens/fixtures/`.

Run: `Rscript --vanilla -e 'devtools::test(filter = "doc-|lint-rules|arch-layers")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with `n` the skips of Tasks 17-18 (Quarto missing, the plan-mode
row without P11) and of P01's suites; `test-lint-rules.R` finds no left arrow, `:::`, `withr::`, `cat(`, `print(`
or non-ASCII byte in the six files, and `test-arch-layers.R` finds no call from the `doc` files outside L0, their
own area, the record files, the declared services and the kernel SDK.

Run: `Rscript --vanilla -e 'devtools::run_examples(run_donttest = TRUE, document = FALSE)'`

Expected: the examples of `gptr_doc()`, `gptr_source()`, `gptr_blocks()` and `gptr_cache()` run without error and
without network (they write only under `tempdir()`).

- [ ] **Step 5: Commit**

```bash
git add dev/bench/tokens/fixtures/ns07-script-history.json dev/bench/tokens/baseline.csv NAMESPACE \
  man/gptr_doc.Rd man/gptr_source.Rd man/gptr_blocks.Rd man/gptr_cache.Rd
git commit -m "docs(doc): document the document exports and add the NS-7 golden transcript"
```

---

## Plan acceptance

Every acceptance check of 05 P15 (including its review amendments), the task and test that prove it, and the command
with its expected result. Run from the repository root after Task 19. "green" means `[ FAIL 0 | WARN 0 | ... ]`.

| # | Check (05 P15) | Proved by | Command | Expected |
|---|---|---|---|---|
| 1 | `devtools::test(filter = "doc-")` is green (knitr/Quarto/IDE cases skip when unavailable) | Tasks 1-18 (the six test files) | `Rscript --vanilla -e 'devtools::test(filter = "doc-")'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 786 ]` without Quarto (the Quarto test skips); with Quarto `SKIP 0 \| PASS 792`; the IDE cases use a mocked editor and never skip; without P11 the plan-mode row skips too |
| 2a | record then replay under `source()` with zero model calls | Task 17, "a recorded block replays under source() with zero model calls (acceptance 2)"; Task 15 (stand-in), Task 13 "the route replays a fresh block ..." | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 2b | `keep.source = FALSE` | Task 17, same test (third pass, `keep.source = FALSE`); Task 8, "without srcrefs the source() frame locates the statement, unless switched off"; Task 18, the `source()` driver of "gptr_return() and gptr$out() calls re-source cleanly under Rscript and source() (6)" (Rscript's `keep.source` is `FALSE`) | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-locate\|doc-io")'` | green |
| 2c | an Rscript run writes its blocks only at exit (sidecar survives a crash) | Task 18, "an Rscript run writes its blocks only at exit and the next run replays them" (the child sees its script unchanged; the blocks exist after exit) and "SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)"; Task 10, "deferred blocks wait in a sidecar and are written when the process exits" | `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'` | green (the child rows skip on CRAN; SIGTERM skips on Windows) |
| 2d | a stale prompt regenerated through `gptr_source(replay = "record")` without executing the old block | Task 17, "a stale prompt regenerates through gptr_source(replay = \"record\") (acceptance 2)"; Task 15, "gptr_source() replays fresh blocks, regenerates stale ones and skips their old code" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 2e | CRLF, BOM and missing final newline preserved | Task 4, "CRLF, BOM and a missing final newline survive a read-modify-write" and "the byte fixtures round-trip exactly" | `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'` | green |
| 2f | a concurrent edit detected by md5 | Task 4, "a concurrent edit is detected by md5 and non-UTF-8 documents are refused"; Task 9, "a document that keeps changing gives up after three attempts with a warning" | `Rscript --vanilla -e 'devtools::test(filter = "doc-io\|doc-blocks")'` | green |
| 2g | `.Random.seed` unchanged | Task 17, "a recorded block replays under source() ..." (`.Random.seed` identical before and after a replay); block ids come from P01's RNG-free `id_block()` | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 2h | knitr and Quarto record/replay | Task 18, "knitr records an agent chunk through gptr() and replays it on the next knit" and "quarto render records a #\| label agent chunk and the next render replays it"; Task 16, "knitr records an agent chunk on the first knit and replays it on the second" and "a stale agent chunk is regenerated during the knit without running the old code" | `Rscript --vanilla -e 'devtools::test(filter = "doc-knitr")'` | green (Quarto skips without the CLI) |
| 2i | a Python-written ipynb round-trips byte for byte | Task 6, "a Python-written notebook round-trips byte for byte" and "an agent cell is inserted after the calling cell, idempotently, keeping outputs" (fixture checked against Python's `json.dumps()`, see Self-review) | `Rscript --vanilla -e 'devtools::test(filter = "doc-formats")'` | green |
| 3 | with `_R_CHECK_PACKAGE_NAME_` set and `TESTTHAT` unset, replay is forced; with `TESTTHAT=true` it is not; with `GPTR_REPLAY=replay`, a call nested in a loop raises `gptr_error_not_recorded` | Task 17, "replay is forced under R CMD check examples and blocks real models (acceptance 3)" (a non-offline provider; the nested call is never a document call, so P08's `replay_guard()` refuses it before any request) | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 4 | replay of a block with `value=markers` yields a session whose `$value` resolves `markers` by name; no generated document contains a `$value =` line | Task 17, "value= replays by name and no document gets a $value line (acceptance 4)"; Task 12, "without a piped session the replayed session is reconstructed from the document" | same | green |
| 5 | no document is written without `gptr_doc()`, `options(gptr.record = "auto")` or user-scope `record = "auto"`, or an interactive yes; a project `record = "auto"` is ignored (tighten-only); a fresh clone without any consent replays with zero model calls and executes no block twice (IC-45) | Task 17, "documents are written only with consent; a project cannot grant it (acceptance 5)" and "a fresh clone without consent replays with zero calls and runs each block once (5)"; Task 7, "write consent comes from the binding, record = auto, a remembered answer or a yes" and "an interactive yes is asked once and remembered per document"; Task 9, "doc_upsert() writes nothing without consent ..."; Task 13, "without consent or under replay the route keeps no site; replay needs no consent" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-blocks")'` | green |
| 6a | a block whose code called `gptr_return(fit)` and `gptr$out("o1")` re-sources cleanly under `source()` and Rscript and `$value` resolves `fit` (IC-48) | Task 17, "gptr_return() and gptr$out() calls are dropped and the block re-sources (6)"; Task 18, "gptr_return() and gptr$out() calls re-source cleanly under Rscript and source() (6)"; Task 3, "recorded code drops gptr_return() and record = FALSE members and rewrites arrows" and "the output of a dropped expression is dropped with it" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-io\|doc-blocks")'` | green |
| 6b | re-sourcing NS-3 twice leaves the main-line `qc_flags` and `qc$value` unchanged and the fork's objects only in its overlay (IC-46) | Task 17, "re-sourcing NS-3 twice keeps the main line and the fork's overlay apart (IC-46)"; Task 12, "a fork block is bound to its id for gptr_resume(block =)"; Task 3, "an overlay fork's block is wrapped in local() on its gptr_resume(block =) home" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-blocks")'` | green |
| 6c | a replayed pipe chain returns one object | Task 17, "a replayed pipe chain is one session; a clone continues from its document (IC-46)"; Task 12, "a piped session is advanced in place; identical() holds along a replayed chain" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 6d | in a fresh clone without `sessions/` a continuation replays from the reconstructed history | Task 17, same test (`history_source == "reconstructed"`, the notice, the live request carrying "step one") | same | green |
| 6e | a parameterised document rendered with two values of `{gene}` does not replay the first block for the second (IC-45) | Task 17, "two values of an interpolated {gene} never replay each other's block (IC-45)"; Task 12, `doc_decide()` args rows; Task 7, the S2 key with the args hash | same | green |
| 6f | a two-turn console session plus one menu steer produces a transcript that re-sources as one session (IC-49) | Task 17, "a two-turn console session with a menu steer re-sources as one session (IC-49)"; Task 13, "console turns become one steered session in the transcript (IC-49)"; Task 5, "console transcripts record the first prompt as an assignment and later ones as pipes"; Task 3, "steers and follow-ups delivered during the turn are recorded as comment lines" | same | green |
| 6g | a plan-mode run records no code | Task 17, "a plan-mode run records only its plan line (IC-48)" (skips without P11); Task 3, "failed and unrecorded calls are left out and plan-mode turns give one Plan line" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-blocks")'` | green |
| 6h | a block containing a nested sub-agent call (the `nested` route) replays under `GPTR_REPLAY=replay` with zero requests (IC-47) | Task 17, "a block with a nested sub-agent call replays with zero requests (IC-47)"; Task 12, "block-nested calls replay from S2 and miss with not_recorded only under replay" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay")'` | green |
| 6i | an Rscript run killed with SIGTERM after two calls leaves a sidecar whose upserts the next run applies without overwriting user edits (IC-51) | Task 18, "SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)"; Task 10, "a dead process's sidecar is recovered without overwriting a user edit (IC-51)" and "a run of the same document under Rscript adopts a dead sidecar until exit" | `Rscript --vanilla -e 'devtools::test(filter = "doc-io")'` | green (skips on CRAN and Windows) |
| 6j | a notebook is never written while `jupyter.in_kernel` is mocked, and `gptr_doc(path, sync = TRUE)` applies its pending blocks (IC-50) | Task 17, "an open notebook is never written; gptr_doc(sync = TRUE) applies it (IC-50)"; Task 10, "an open notebook is never written; its blocks wait for gptr_doc(sync = TRUE) (IC-50)" | `Rscript --vanilla -e 'devtools::test(filter = "doc-replay\|doc-io")'` | green |
| 6k | P15's NS-7 fixture is added to `dev/bench/tokens/` (IC-73) | Task 19 | `Rscript --vanilla dev/bench/tokens/run.R --check` | `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances` |

The contract's other P15 obligations are covered as well: the route `document` at order 50 and the four services
owned by `builtin:documents` (Task 13, "builtin:documents registers the formats, the route, the section and the
services"), the `documents` section text (Task 13), the `document_write` event blocking and patching (Task 9, "a
hand-edited block is kept unless regenerating, and hooks can block or patch"; Task 13, inert writes; Task 11,
transcript appends), the IDE backends (Task 11), undone blocks in every format (Tasks 5, 6, 13), team and fan-out
blocks (Task 3 and Task 12), `doc.edit` (Task 13), `doc.s1_block` (Task 13), `doc.replay` (Task 13),
`gptr_blocks()`/`gptr_cache()` (Task 14), the control category of IC-53 (Tasks 7 and 14), transcript targets (Task 8)
and the documented examples (Task 19).

---

## Self-review

### Spec coverage (05 P15 scope bullets and review amendments -> tasks)

| 05 P15 item | Tasks |
|---|---|
| `doc-locate.R`: precedence of architecture §6.9.3; content matching; `source()` frame reads in `tryCatch` with an off switch | 2 (scanner, anchors), 8 (`doc_locate()`, `gptr.doc_source_frames`) |
| `doc-blocks.R`: block grammar incl. `session`, `turn`, `value`, `fork`, `plan`, `status=undone`; ownership; idempotent upsert; stale and user-edited detection | 1 (grammar, keys, status), 2 (ownership), 3 (content and header keys), 9 (idempotent upsert, user-edited protection) |
| `doc-io.R`: raw-byte atomic writes preserving EOL/BOM, md5 conflict checks with re-locate and retry, deferred Rscript writes with a sidecar, rstudioapi and Positron backends, never writing an open notebook | 4 (I/O, md5, locks), 9 (re-locate and retry), 10 (deferred, sidecar, pending notebooks), 11 (IDE backends) |
| `doc-formats.R`: `r`, `rmd`, `qmd`, `ipynb` with gptr's serializer, `transcript`; `builtin:documents` with the `document_write` event and the gateway's "document" route | 5, 6, 9 (`document_write`), 13 (`builtin:documents`, route) |
| `doc-replay.R`: replay decisions per mode (from P08's `replay_mode()`, forced under check), the S2 cache, `gptr_doc()`, `gptr_source()`, `gptr_blocks()`, `gptr_cache()`, the console-transcript target question | 7 (S2, consent), 8 (transcript target question), 12 (`doc_decide()`), 14, 15, 17 (forced replay) |
| `doc-knitr.R`: `knit_print` methods for sessions and System 1 vectors registered lazily, the scoped label hook | 16 |
| IC-45: route on a located top-level call; replay needs no consent; consent only in `doc_upsert()`; `args=` and the S2 key; forced replay only outside testthat | 7, 9, 12, 13, 17 |
| IC-46: replay in place for piped sessions; replayed sessions from the JSONL or reconstructed; fork blocks bound and wrapped with `gptr_resume(block =)` | 3 (wrapper), 12, 17 |
| IC-47: team and fan-out blocks and block-nested calls replayed from S2 | 3, 9 (child texts in S2), 12, 13 (`doc.replay`), 17 |
| IC-48: dropping top-level `gptr_return()` and `record = FALSE` member calls, the best-effort arrow rewrite, no recording in plan mode | 3, 17, 18 |
| IC-49: console transcripts as pipe chains and `## Steer:`/`## Follow-up:` lines | 3, 5, 13, 17 |
| IC-50: Jupyter pending blocks and `gptr_doc(sync = TRUE)` | 10, 14, 17 |
| IC-51: the sidecar with recovery, rename retries with an in-place fallback (P01's `write_atomic()`), `path_key()` matching | 4, 10, 13 (recovery on touch), 14, 18 |
| IC-52: transcript targets validated and stored in the user-level project file | 4, 8 |
| IC-68, IC-34, IC-47: the `documents` section and the services owned by `builtin:documents`, incl. `doc.replay` | 13 |
| IC-53: `gptr_doc` and `gptr_cache` (prune, clear) refuse model code | 7, 14 |
| IC-73: the NS-7 fixture | 19 |
| Acceptance 1-6 | see Plan acceptance |

### Placeholder scan

The plan was searched for "TBD", "TODO", "implement later", "fill in", "similar to Task", "appropriate error
handling" and "edge cases": none occurs. Every step that changes code shows the complete code; the two test-only
tasks (17, 18) give the exact temporary change that demonstrates their red phase and its removal. Step 2 and Step 4
counts of Tasks 1-16 are the counts measured in the scratch reproduction described below; Task 17 and 18 counts were
derived by counting their executed expectations (79 including the two loops, 24 and 13), because those tests need the
assembled package.

### Type and name consistency with 04

- Exports: `gptr_doc(path = NULL, format = NULL, sync = FALSE)`, `gptr_source(file, replay =
  getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)`, `gptr_blocks(file)`,
  `gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp"))` - exactly 04 §6.4.
- Internal: `builtin_documents(gptr)`, `doc_locate(call)`, `doc_decide(site, prompt_hash, args_hash, mode)`,
  `doc_block_lines(session, turn, site, call_ordinal)`, `doc_upsert(site, block_lines, block_id = NULL)`,
  `prompt_hash(template)`, `args_hash(interp)`, `s2_get(key)`, `s2_put(key, record)` - exactly 04 §7.15.
- Classes `gptr_blocks` and `gptr_cache_info` with the 04 §5.12 columns in order; conditions `not_recorded`
  (`document`, `prompt`), `stale_block` (`document`, `block`), `doc_write` (`path`, `reason`), `invalid_argument`,
  `permission`; warnings `replay_downgraded`, `doc_conflict`; message `notice`; event `document_write` with `path`,
  `format`, `kind`, `block_id`, `lines`; entry `gptr.doc_block`; services `doc.site`, `doc.edit`, `doc.s1_block`,
  `doc.replay`; route `document` order 50; section `documents` T0/500/250; options `gptr.replay`, `gptr.record`,
  `gptr.doc_output_lines`, `gptr.doc_source_frames`, `gptr.spill_days`.
- Consumed names were checked against the dependency plans: P01 (`write_atomic()`, `path_key()`, `id_block()`,
  `json_decode()`, `canonical_json()`, `new_listing()`, `s3_register()`, `msg_verbatim()`, `gptr_inform(.once =)`,
  `gptr_can_prompt()`, `gptr_confirm()`, `front_end()`, `check_running()`, `save_rds()`, the helpers of 04 §12.2 and
  `tracemem_loader()`), P02 (`gptr_spec()`, `ext_declare_builtin()`, `registry_get()`, `registry_names()`,
  `ev_dispatch()`, `registry_diagnostic()`, the factory API's `register()`/`on()`), P03 (`redact()`,
  `code_for_history()`), P04 (`pid_alive()`), P06 (`session_replay_apply()`, `session_replay_new(block, header,
  envir, doc)` with `doc = list(path, format, template, code, output, text)`, `session_replay_bind()`,
  `gptr_resume(block =, child =)`, `session_append()`, `session_live()$run`/`$ctx`, the entry shapes and the turn
  stamp of `entry_prepare()`), P07 (`prompt_doc()` reads `doc.site`; `{s1}` substitution), P08 (`replay_mode()`,
  `route_pass()`, `settings_write("user_project", patch)`, the `gptr_call` bindings, `run$opts$doc`), P10 (the flat
  `details$outputs` of `r_doc_outputs()`; `gptr$edit()` calls `doc.edit(path, edits, NULL)`, the direct `edit` tool
  passes `ctx$session`), P11 (the `gptr.plan` entry and the plan block's `attrs$from`), P14 (the `console:command`
  and `console:direct` notify channels, `ev_dispatch(<channel>, list(data = ...))`).

### Executed validation

All in the scratch directory `.../scratchpad/work/plans/P15/v3/`, with `Rscript --vanilla` (R 4.4.3, testthat 3,
knitr 1.51, jsonlite 2.0.0, cli 3.6.6):

- The plan's sixteen implementation chunks (Tasks 1-16) were loaded on top of P01's real sources (extracted from
  `dev/plan/P01-foundation.md`: `aaa-state.R`, `utils-*.R`, `json-encode.R`, `provider-message.R`,
  `provider-events.R`, `provider-fake.R`) and stand-ins of the P02-P08 interfaces shaped after their plans (P06's
  replay functions and P04's `pid_alive()` copied, P03's `code_for_history()` contract); every test chunk of Tasks
  1-16 ran green with testthat (`doc-blocks` 173, `doc-io` 109, `doc-formats` 124,
  `doc-replay` 200, `doc-locate` 49, `doc-knitr` 21 expectations; re-measured after the review fixes), including real `knitr::knit()` runs of the knitr tests. The red phases were measured
  the same way with the implementation of the task removed (strict mocking, as `local_mocked_bindings()` does).
- The three fixture generators (Tasks 4-6) reproduce the verified fixtures byte for byte (`cmp`).
- Locator cost: 50 `gptr()` calls located in a 2,300-line sourced script took 13 s with the first scanner
  (data-frame row-name lookups, a re-parse after every 16 statements); with the id-indexed scanner, the LRU memo and
  the prefiltered marker scan of Tasks 1-2 they take 1.9 s (one 0.65 s parse, then about 25 ms per call).
- Python 3 check of the notebook serializer: the fixture, the fixture after the agent-cell upsert (with non-ASCII,
  quotes and `</b>` in the body) and the same notebook with the cell made inert all equal
  `json.dumps(json.loads(x), indent=1, sort_keys=True, ensure_ascii=False, separators=(",", ": ")) + "\n"`.
- Every ```` ```r ```` block of this plan was extracted and parsed with `parse(file = <f>)`; the plan contains no
  left-arrow assignment and no `%>%` in code; the R sources are ASCII-only and at most 100 characters per line.
- Not executed here (they need the assembled package, a Quarto installation or rtiktoken): the end-to-end tests of
  Tasks 17-18 and the NS-7 baseline row of Task 19.

### Contract ambiguities and decisions

1. 04 §7.15's example calls `doc_decide()` with three arguments; the signature has four
   (`site, prompt_hash, args_hash, mode`), which this plan implements.
2. `doc_decide()` follows 14 §4.4.2 for a missing block under `replay` (`not_recorded`), but the route consults it
   only when the call owns a block (IC-45: "Without a block it sets `call$doc` ... and passes"); a missing block under
   `replay` is then refused by P08's `replay_guard()`, which exempts offline test providers. This keeps examples and
   the fake provider working under forced replay and still stops every real model call (acceptance 3 uses a
   non-offline provider).
3. The route's `match()` returns `TRUE` for every located top-level or block-nested call and for console calls with a
   transcript target; `run()` replays, regenerates or passes. A site is kept in `call$doc` when consent exists or can
   still be asked (consent itself is checked only in `doc_upsert()`), and never in `replay` mode.
4. 03 §6.9.3 defines `live` as "ask afresh and regenerate" and `record` as "regenerate stale blocks"; report 14's
   table (`live` = run without writing) is older and is not followed. A user-edited block asks before it is
   overwritten in `live`/`record` and otherwise replays (user code wins). Under base `source()`/Rscript a stale or
   re-asked block downgrades to replay with the warning `replay_downgraded` in every mode, as 03 §6.9.3 says;
   report 14's "In `record` mode this is an error" is not followed (`replay` mode still errors `stale_block`, IC-45).
5. Only runs that end `idle` write a block; aborted, errored, blocked or budget-stopped runs write nothing.
6. 04 §7.10 lists P15 as a consumer of P10's `edit_file()`, but the layering test forbids an L4 call into another
   L4 area; `doc.edit` reaches the edit tool through `registry_get("tool", "edit")$execute()` and answers `NULL` while
   that tool runs (no re-entry).
7. P06's `session_replay_new()` cannot attach children to a team session; `doc.replay` binds every replayed child
   with `session_replay_bind(block, child, child = name)` and returns the replayed team session; P19 (which owns team
   sessions and depends on P15) attaches them when it needs `reviews$stats`.
8. 04 §11.5 names bridge digests and artifact references but no fields; P15 reads them from the `r` tool result's
   `details$bridge` (digest strings) and `details$artifacts` (paths). P10, P22 and P23 must fill them.
9. The `gptr.doc_block` entry uses `backend = "pending"` for Jupyter (IC-50), a value 04 §4.6's list does not name.
10. 04 §6.4 also lists checkpoint blobs under `gptr_cache("prune")`; their retention is P16's (G7), and P16 depends on
    P15, so `gptr_cache()` does not touch them here.
11. IC-49 and 04 §11.5 record direct R lines "with `#>` output" and slash commands as comments but name no event.
    P14 first dispatches the 04 §10.4 `input` event (source `repl` for a slash-command line, `passthrough` for
    `!expr`, before the line runs; a hook may handle or transform it), then the notify channels `console:command`
    (`data = list(text)`, a line that is still a command after any transform; handled lines are not announced) and
    `console:direct` (`data = list(code, output, status, noted)`, after the line ran) for transcript writers (P14
    ambiguities 3-4). P15 records from the two channels only: an `input` handler would also record lines a later
    hook handles, the text before a transform and no `#>` output, and subscribing to both would write each slash
    command twice.
12. The user-level project file's `record` and `transcript` keys are P15's; P08's settings layers read only
    `permissions` from that file. `settings_read()` is not in the kernel SDK, so P15 reads the file with P01 helpers
    and writes it with `settings_write("user_project", patch)`.
13. `gptr_doc()` accepts documents outside the project root (04's own example binds a `tempfile()`); the IC-52 inside-
    the-root rule is applied to remembered transcript targets.
14. IC-51 makes `gptr_blocks()` apply a dead process's sidecar ("the next `gptr()`, `gptr_blocks()` or `gptr_doc()`
    touching that document"), which writes the document although 04 §6.4 says `gptr_blocks()` "reads only"; IC-51 (§15)
    wins.
15. The sidecar record adds `create_time` (pid reuse) and `kind` (`deferred`/`pending`) to the IC-51 shape.
16. P06 redacts entries at ingress, so recorded code holds `[secret:NAME]` markers rather than values; P15 turns a
    literal that is exactly a marker of an environment variable into `Sys.getenv("NAME")` before P03's
    `code_for_history()`, which flags what stays a marker (G6 §5.6).
17. P07's golden-transcript runner has no document field, so the NS-7 fixture binds `analysis.R` through an `objects`
    expression calling `gptr::gptr_doc()`; `doc.site` ignores a binding whose directory no longer exists, so the
    binding cannot leak into later fixtures.
18. The `r` tool result `details` (`code`, `status`, `outputs`, `record`, `note`, `value`, `bridge`, `artifacts`)
    follow 04 §4.4 and P10's `r_tool_result()`. P10 flattens `outputs` into one character vector (`r_doc_outputs()`),
    so the printed output of a dropped expression (for example `gptr$out(id, lines = 1)`) cannot be told apart and
    stays as a `#>` comment; `doc_turn_assistant()` drops it only when an evaluator returns outputs per expression
    (a list). The IC-48 acceptance rows compare the code lines of the block.
19. The plan writes no `tests/testthat/helper-*.R` file (05 lists none for P15); the few test helpers are defined in
    each test file that needs them. Child processes reuse P01's `tracemem_loader()`.
20. The end-to-end tests set `gptr.unsafe_no_permissions` (IC-53's documented escape for sandboxed runs) because P11
    is not a dependency of P15; the plan-mode row skips without P11's `plan.pending` service.
21. `doc_locate()` ignores srcrefs that point into gptr's own `R/` sources (they exist under `pkgload::load_all()`),
    so package code that calls `gptr()` (P14's REPL) is never taken for a document.
22. `knit_print.gptr_s1()` prints the one-line block summary in backticks; 04 assigns the method but not its output.
23. A replayed team child gets a fresh overlay `new.env(parent = <caller environment>)` as its home. Documents run at
    top level (the global environment or a sourced environment), so this keeps no function frame; a team block
    replayed through `gptr_source(envir = <function frame>)` keeps that frame reachable from the replay table until
    the block is replayed again (P06's `the$replay_blocks` is replaced on re-source, IC-46).
24. A `gptr()` call nested in a loop or function inside an agent block is not block-nested: it runs live like a call
    in a user loop (IC-47 "Calls deeper inside block code (loops, functions) run live").
25. The S2 record of a block-nested part adds `sent` (the prompt hash of the child's first prompt) to the fields of
    04 §11.9, and `n<k>` is assigned to the child that answered the k-th *direct* `gptr()` call of the block body
    (matched by prompt hash), not to the k-th child created during the turn: children of calls inside loops or
    functions would otherwise shift the ordinals and replay one call's answer for another. A cached part whose
    `sent` differs from the replaying call's prompt is a miss.
26. knitr names an unlabelled chunk `unnamed-chunk-<k>` (k counts unlabelled chunks of every engine; verified with
    knitr 1.51) and `opts_current$get("label")` reports that name while the chunk runs; `doc_rmd_chunks()` gives
    unlabelled chunks the same default labels, so calls in unlabelled chunks are located. A user who changes
    `opts_knit$get("unnamed.chunk.label")` gets no location for such chunks (the call runs live and is not recorded).
27. Notebook anchors carry the prompt hash, the ordinal `j` among the code cells calling `gptr()` with it (and the
    call for a computed prompt); the cell index seen at locate time is informational, because earlier pending
    blocks applied by the same `gptr_doc(sync = TRUE)` insert agent cells above later calling cells.
28. 04 §11.5's ownership rule ("the k-th call owns the block whose `prompt=` matches, else the one with `call=k`")
    is ambiguous when a pipeline repeats a prompt (`gptr("draft") |> gptr("improve it") |> gptr("improve it")`):
    read literally, the third call would own the second call's block and replay it instead of running. A block whose
    `call=` ordinal belongs to another call of the same statement with the same prompt is never matched by prompt
    alone (`doc_run_owner(taken =)`), so each repeated step owns its own `call=k` block.

## Plan review log

Adversarial review of 2026-10-01 against 05 P15, 04 (§15 first), 03 §6.9, the dependency plans P01, P02, P06, P07,
P08, P10 and P14, and report 14. Every R block was re-extracted and parsed, the Task 1-16 tests were re-run in the
scratch harness (P01's real sources plus stand-ins of P02-P08) after the fixes, and every step count was re-measured.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 6 `doc_ipynb_locate()`, Task 8 `doc_anchor()` | Notebook anchors used the cell index seen at locate time (and always `j = 1`): when `gptr_doc(sync = TRUE)` applies two pending blocks, the first agent cell shifts the second calling cell down, so the second block is inserted into the first call's run (an orphaned block); two cells with the same prompt always resolved to the first | applied | `doc_ipynb_locate()` finds the calling cell by content (`nb_find_call_cell(nb, ph, call0, j)`); new `nb_call_ordinal()`; `doc_anchor()` stores the ordinal `j` and, for computed prompts, `call0`; new test "notebook anchors follow content ..."; ambiguity 27 |
| 2 | major | Task 3 `doc_block_lines()`, `doc_turn_children()`; Task 9 `doc_after_write()`; Task 12 `doc_run_block_nested()` | Block-nested S2 parts were keyed `n<k>` by the creation order of child sessions, while replay looks them up by the ordinal of the *direct* calls in the block: children of calls inside loops or functions (or of the previous turn, within the 1 s slack) shifted the mapping and a direct call silently replayed another call's answer | applied | new `doc_nested_parts()` maps the k-th direct call to the child whose first prompt has its prompt hash and records `sent`; replay treats a part whose `sent` differs from the call's prompt as a miss; slack cut to 1 ms; tests "child answers map to the block's direct gptr() calls ..." and the `sent` rows of "block-nested calls replay from S2 ..."; ambiguity 25 |
| 3 | major | Task 13 hooks (`doc_on_input()`), File Structure, Task 11 | Slash commands and direct R lines were taken from the `input` event, but P14 never fires `input` for slash commands and fires it before a direct line runs; P14 announces both on the `console:command` and `console:direct` channels and asks P15 to subscribe, so `# /model opus` lines and the `#>` output required by 04 §11.5 were never recorded | applied | `doc_on_input()` replaced by `doc_on_console_command()`, `doc_on_console_direct()` and `doc_console_append()`, registered with `gptr$on("console:command"/"console:direct")`; the direct line's output is written as `#>` lines; test rewritten with P14's payloads; ambiguity 11 rewritten |
| 4 | major | Task 5 `doc_rmd_chunks()` | Unlabelled Rmd/qmd chunks got an `NA` label, but knitr reports `unnamed-chunk-<k>` for them and `doc_anchor()` filters candidates by that label, so calls in unlabelled chunks (most chunks) were never located: no recording and no replay under knitr or Quarto | applied | unlabelled chunks get knitr's default `unnamed-chunk-<k>` (k counts unlabelled chunks of every engine; checked with knitr 1.51); tests in Task 5 and Task 8 (`doc_anchor()` with label `unnamed-chunk-2`); ambiguity 26 |
| 5 | major | Task 2 `doc_run_owner()`, `doc_owned_block()`, `doc_text_locate()`, Task 5 `doc_rmd_locate()` | The prompt-only fallback let the later of two identical prompts in one pipeline (`... \|> gptr("improve it") \|> gptr("improve it")`) own the earlier call's block: the step replayed the wrong block and was never run or recorded | applied | `doc_run_owner(headers, ph, k, taken)` never matches by prompt alone a block whose ordinal belongs to another same-prompt call of the statement; new `doc_same_ordinals()`; test "a prompt repeated in one pipeline never takes another call's block"; ambiguity 28 |
| 6 | major | Task 17 "a replayed pipe chain is one session; a clone continues ..." | `file.copy(<cache dir>, file.path(clone, ".gptr"), recursive = TRUE)` returns `FALSE` with two warnings because `clone/.gptr` does not exist, so the S2 answers never reach the clone and `e$chain$text == "two."` cannot hold (verified in R 4.4.3) | applied | the test creates `clone/.gptr` first and asserts the copy and the absence of `sessions/` |
| 7 | major | Task 17 and Task 18 IC-48 rows ("gptr_return() and gptr$out() calls ...") | Both expected a block body of exactly one code line, but P10's `r_doc_outputs()` flattens `details$outputs`, so the printed line of `gptr$out(id, lines = 1)` is recorded as a `#>` comment that P15 cannot attribute to the dropped expression; the rows could not pass | applied | both rows compare the code lines (`#>` excluded), which is what IC-48 requires; Task 3 adds the flat-output case; ambiguity 18 rewritten (P10 exists and its output shape is cited) |
| 8 | minor | Task 12 `doc_decide()` | In `record` mode a stale block under base `source()`/Rscript raised `stale_block`; 03 §6.9.3 says "under base source()/Rscript, live and stale regeneration downgrade to replay with a warning" (report 14's older table is superseded) | applied | the downgrade with `replay_downgraded` applies in every mode (`replay` mode still errors, IC-45); test row and ambiguity 4 updated |
| 9 | minor | Task 13 `doc_site_service()` | P10's `gptr$edit()` member calls `doc.edit(path, edits, NULL)`; without a session `doc.site` saw only the `gptr_doc()` binding, so an agent's edit of a located (not bound) document skipped the header refresh and the block later counted as user-edited | applied | without a session the service answers the innermost running call's site (`run_current()$opts$doc`, a read-only `gptr_run` field); test added |
| 10 | minor | Task 13 `doc_set_inert()`, `doc_on_session_tree()` | A rewind made console blocks inert but left their `s_<hex>` statement live unless the transcript lived under `.gptr/transcripts/` (an IDE's active document is a valid target); the `gptr.doc_block` entry said `backend = "file"` for transcript blocks | applied | `doc_set_inert(..., transcript = NULL)`; the hook passes `transcript = TRUE` and keeps `backend = "transcript"` for blocks recorded through the transcript backend; test added |
| 11 | minor | Task 14 `gptr_doc()` roxygen | 04 §3.1: "The owner plan documents the option in its roxygen `?gptr_options` section"; P15 owns `gptr.record`, `gptr.doc_output_lines`, `gptr.doc_source_frames`, `gptr.spill_days` (and co-owns `gptr.replay`) but documented none | applied | `@section Options:` added to `gptr_doc()` |
| 12 | minor | Task 14 `gptr_blocks()` roxygen | "It only reads the document" contradicts IC-51 (the function applies a dead process's sidecar) and ambiguity 14 | applied | wording states the one write |
| 13 | minor | Self-review counts, Plan acceptance row 1 | The Task 17 expectation count ignored the second iterations of two loops (75 stated, 77 executed before the fixes); every count changed with the fixes | applied | all Step 2/Step 4 counts of Tasks 2, 3, 5, 6, 8, 9, 12-15 and 17 re-measured or recounted; acceptance row 1 is `PASS 786` without Quarto and `PASS 792` with it |
| 14 | minor | Task 13 `doc_control_guard()` | Duplicates P08's `control_check()` (DRY) | rejected | `control_check()` lives in `gptr-config.R` (L6) and is not in IC-33's kernel SDK, so the L4 `doc` files may not call it; the copy keeps P08's token protocol (`run$signal$control`) |
| 15 | minor | Task 10 `doc_pending_add()` | A pending Jupyter block is printed from an L4 file (03 §2.2 rule 2: nothing below L5 prints) | rejected | IC-50 requires the block "shown as the cell's output"; it goes through P01's `msg_verbatim()` (an L0 helper for untrusted text that the layer matrix allows) and nothing else in the L4 files prints |
| 16 | minor | Task 8 `doc_locate()` console fallback | A call typed at the console inside a loop or function becomes a top-level transcript turn when a transcript target exists | rejected | P14's REPL prompts are gateway calls made deep inside P14's frames, so neither frame depth nor srcrefs separate them from loop bodies; IC-49 records console calls and the transcript stays re-sourceable (calls replay or run live) |
| 17 | minor | Task 12 `doc_replay_team()` | IC-47 says replay "returns a team or fan-out session of replayed children", the plan returns a `replayed` session whose children are reachable only through `gptr_resume(block =, child =)` | rejected | P06's `session_replay_new()` always makes kind `replayed`, and IC-33 gives L4 only read access to `session_data()`; recorded as ambiguity 7 (P19, which owns team sessions, attaches children) |

## Cross-plan consolidation log

Cross-plan consistency pass of 2026-10-01 against 04 (§10.4 `input` row and `<plugin>:<topic>` channels, §11.5
transcript row; IC-49), 03 §6.17 ("Commands are recorded as comments in transcripts") and the current text of P14
(Global Constraints "Events emitted" and "Transcripts", Task 5 `repl_passthrough()`, Task 6 `console_command()` and
its test "commands pass the input event (source repl): recorded, handled or transformed", ambiguities 3-4, and P14's
own cross-plan consolidation log, items 1-2, written in the same pass).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | major | Task 13 `doc_on_console_command()`, `builtin_documents()` (`gptr$on("console:command", ...)`), test "direct R lines and slash commands of the console enter the transcript", File Structure row, roxygen of `builtin_documents()`, ambiguity 11 | rejected (premise superseded); wording aligned | The issue rests on P14 no longer dispatching `console:command` (its review row 2). P14's consolidation pass (its log items 1-2, shared-names lens) restored the channel: `console_command()` now runs `ev_dispatch("input", ev_new("input", text = text, source = "repl"), session = session)` first and then, for a line that is still a command, `ev_dispatch("console:command", list(data = list(text = text)), session = session)`, and P14 names P15's `doc_on_console_command()` and `doc_on_console_direct()` as the subscribers everywhere. P14's log item 1 also rejects the proposed `doc_on_console_input()`. Switching P15 to an `input` handler would leave P14's channel without a subscriber, record lines a later hook handles and the text before a transform (P14 ambiguity 3), and double-record if both were kept. 04 does not say which event carries transcript lines: §10.4 lists `input` (source `repl`, emitted by P14, which it still is) and allows `<plugin>:<topic>` notify channels, and §11.5 only fixes the lines. Matching P14 therefore decides. No code, test or count changes. Wording updated to P14's final semantics: the Task 13 Interfaces (the `console:command` text is the line after any transform, handled lines are not announced, and P15 does not record from `input`), ambiguity 11 (the order `input` -> channel, and why P15 records from the channels only), and the stale "agent_end/session_tree/input hooks" in the `R/doc-formats.R` and `R/doc-replay.R` header comments (P15 registers no `input` hook). |
| 2 | obligations | major | Task 13 `builtin_documents()` hooks, `doc_on_console_command()`, ambiguity 11, review row 3 | rejected (premise superseded) | Same mismatch as item 1, from the obligations side: `# /model opus` comments (04 §11.5, 03 §6.17) are still written, because P14 now dispatches `console:command` after the `input` event (source `repl`) and P15 subscribes to it. P14's test registers a `console:command` hook with P15's payload shape (`event$data$text`) and checks `c("/mode auto", "/mode plan", "/model opus")`. P15's test feeds the same payload to `doc_on_console_command()`. The suggested wrapper (`doc_on_console_input()` calling `doc_on_console_command()`) would record each slash command twice next to P14's channel, or record unrun lines without it. The wording changes are listed under item 1. |
| 3 | finalize | minor | Task 5 `R/doc-formats.R`, `doc_rmd_calls()` | applied | `brace_linter` (consolidation lint `P15_L02536.R:96`, "Either both or neither branch in `if`/`else` should use curly braces"): `res = if (length(out)) do.call(rbind, out) else { ... }` now braces both branches (`if (length(out)) { do.call(rbind, out) } else { ... }`). Same value, no test or count change. |
| 4 | finalize | minor | Task 8 `R/doc-locate.R`, `doc_site_jupyter()` | applied | `brace_linter` (consolidation lint `P15_L03951.R:118`): `cands = if (nzchar(jpy) && file.exists(jpy)) jpy else { list.files(...) }` now braces both branches. Same value, no test or count change. |
| 5 | finalize | minor | Task 14 `R/doc-replay.R`, roxygen `@examples` of `gptr_blocks()` | applied | `commented_code_linter` (consolidation lint `P15_L07144.R:85`): the example line `#'              '# >>> gptr:7f3a21 ...',` is an example, not dead code, but with the leading `#` stripped it parses as a string followed by a comment, so lintr flags it. The marker and body strings of the example now use double quotes (`"# >>> gptr:7f3a21 model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2"`, `"x = 1 + 1"`, `"# <<< gptr:7f3a21"`); only `'gptr("add one")'` keeps single quotes because it contains double quotes. The file the example writes and its `gptr_blocks()` output are unchanged. |
| 6 | finalize | minor | Task 17 `tests/testthat/test-doc-replay.R`, helper `doc_e2e_source()` and its call in "a recorded block replays under source() with zero model calls (acceptance 2)" | applied | `object_name_linter` (consolidation lint `P15_L07961.R:26`): the helper argument `keep.source` is renamed `keep_source` (the helper still passes it to base `source(keep.source =)`), and the one caller is now `doc_e2e_source(f, e3, keep_source = FALSE)`. `doc_e2e_source()` is a P15 test helper: grep over `dev/plan/*.md` and the consolidation index (`work/consolidate/rerun/index.json`, one definition, P15 Task 17) find no other plan that defines or calls it, so no nolint is needed. Prose that names base R's `keep.source = FALSE` (Task 17 Interfaces, acceptance row 2b) is about `source()`/`Rscript` and stays. No test or count change. |
| 7 | finalize | minor | Task 5 Step 1 fixture script (`$TMPDIR/p15-fixtures-5.R`), `put()` | applied | `brace_linter` ("Wrap multi-line function bodies in curly braces"), found by the finalize re-lint of all 41 `r` blocks (the consolidation lint did not include the three fixture scripts of Tasks 4-6): `put()` now has a braced one-statement body. The fixture bytes it writes are unchanged. |

Validation (scratch `scratchpad/work/consolidate/P15/`): all 41 fenced `r` blocks were re-extracted and parsed with
`Rscript --vanilla` (`parse(text =)`). `getParseData()` finds no `LEFT_ASSIGN` token and no `%>%`, every block is
ASCII, and no line is longer than 100 characters. Only comment lines changed inside code blocks, so the Step 2/Step 4
counts and acceptance row 1 (`PASS 786`/`792`) stand.

Finalize validation (items 3-7, scratch `scratchpad/work/finalize/P15-lint/`): all 41 fenced `r` blocks were
re-extracted with the consolidation `extract.py` and linted with lintr 3.3.0.1 and P01's `.lintr` linters
(`indentation_linter = NULL`; `object_usage_linter = NULL` because plan blocks cannot be loaded): no lints remain.
Every block parses with `Rscript --vanilla`, `getParseData()` finds no `LEFT_ASSIGN` token and no `%>%`, every block
is ASCII, and no line is longer than 100 characters. No expectation was added or removed, so the Step 2/Step 4 counts
and acceptance row 1 (`PASS 786`/`792`) stand.
