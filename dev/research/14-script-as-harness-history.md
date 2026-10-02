# Track 14 — Script-as-harness and script-as-history (.R, .Rmd, .qmd, .ipynb)

Requirements covered: REQ-24, REQ-25, REQ-26, REQ-27 (and constraints from REQ-02, REQ-03).
Decision-register items informed: D-08 (document harness), D-09 (session persistence), D-10 (workspace), D-27 (knitr/Quarto integration).
Date: 2026-09-29. Machine: macOS, R 4.4.3, knitr 1.51, rmarkdown 2.31, jsonlite 2.0.0, cli 3.6.6, rstudioapi 0.18.0, IRkernel 1.3.2, Quarto 1.10.18 (the copy bundled inside RStudio.app).
Scratch prototypes: `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/14/` (sub-folders `a/`, `k/`, `q/`, `web/` came from an interrupted earlier run; they were re-run or re-fetched here before being used. `p1/` and `proto/` are new).

Evidence tags: **VERIFIED** means I saw it myself (source line, command output or fetched document). **LIKELY** means strong indirect evidence that I could not execute here. **UNCERTAIN** means plausible but unconfirmed.

---

## 1. Executive summary

1. **Use statement-level srcrefs where they exist, and fall back to static parsing when they don't** (VERIFIED). With `keep.source = TRUE`, which is the default in interactive R, `attr(sys.call(), "srcref")` inside `gptr()` gives the line range of the **statement being evaluated**, not of the call itself. Its `srcfile` is a `srcfilecopy` holding `filename`, `wd`, `isFile = TRUE`, the file mtime, and **the lines as they were when parsed**. A call typed at the console has **no** srcref. So does a top-level statement under `Rscript`.
2. **srcref line numbers go stale during a single `source()` pass** (VERIFIED). Once an earlier `gptr()` inserts a block, every later line has moved. The call must therefore be found by content: take its ordinal among user-written `gptr()` calls in the parse-time text (`srcfilecopy$lines`), then pick the call with the same ordinal in the current text.
3. **Pipelines break naive srcref use** (VERIFIED). For `gptr("a") |> gptr("b")`, the inner call is a promise forced inside the outer function, so its srcref points somewhere else. In the original run it pointed at the driver script. In the verifier's re-runs it was either absent (under `Rscript`) or pointed at the statement inside the outer function's body that forced the promise (when that function had srcrefs). Accept a srcref only if its text contains a `gptr()` call with the same prompt; otherwise walk up `sys.calls()`.
4. **`source()` with `keep.source = FALSE` still works through the source frame** (VERIFIED on R 4.4.3). This covers `Rscript -e 'source("a.R")'` and `sys.source()`. That frame holds `ofile`, `exprs` and the loop index `i`. The k-th top-level expression that is `identical()` to `exprs[[i]]` identifies the statement. `sys.call()` is also `identical()` to the matching parsed call, including after pipe rewriting and with dynamic prompts. This relies on undocumented base-R internals, so treat it as best effort and validate the result. CRAN acceptability is also UNCERTAIN (§6). Note that the §5.0 `gptr_where()` prototype only looks at `source()` frames. The `sys.source()` variant, which uses `file` rather than `ofile`, was checked separately by the verifier: the `file`, `exprs` and `i` frame variables identified the statement, including a pipeline.
5. **Never rewrite a script that `Rscript` is running** (VERIFIED). `Rscript file.R` reads its file incrementally. Rewriting it mid-run produced `Error: unexpected string constant` because R read the grown tail. Writes must be deferred to exit with `reg.finalizer(env, f, onexit = TRUE)`. That finalizer ran at normal exit, after an uncaught error ("Execution halted") and after `quit(runLast = FALSE)`. `source()` and `knitr::knit()` parse the whole file first, so editing the file mid-run is safe and the new code does not run in that pass (VERIFIED for both, and for `quarto render`).
6. **knitr and Quarto** (VERIFIED). Detect knitr with `getOption("knitr.in.progress")`. Get the file from `knitr::current_input(dir = TRUE)` and the chunk from `knitr::opts_current$get("label"/"code")`. Under Quarto, `current_input()` returns the temporary `*.rmarkdown` file, so use `QUARTO_DOCUMENT_PATH` + `QUARTO_DOCUMENT_FILE` (or the JSON at `QUARTO_EXECUTE_INFO`). Quarto's `commandArgs()` contain `--file=.../rmd.R`, which must not be mistaken for the user's script.
7. **IDEs.**
   - **RStudio** (VERIFIED from the rstudioapi 0.18.0 docs and source): `rstudioapi::getSourceEditorContext(id)`, `insertText/modifyRange(location, text, id)`, `documentSave(id)`, `documentId(allowConsole)` (which can return the pseudo-id `"#console"`). The context contents are the editor buffer.
   - **Positron** (VERIFIED from ark source): the same shims live in `tools:rstudio`. `rstudioapi::isAvailable()` is overridden to `TRUE`. **`insertText`, `modifyRange`, `documentPath`, `documentSave` and `setSelectionRanges` all `stopifnot(is.null(id))`**, so only the last-active editor can be targeted. Since Positron PR #16063 (merged 2026-09-23, which pairs with ark#1408, merged 2026-09-18), that target can be the console when the console had focus.
   - **VS Code** (vscode-R's `sess` package, VERIFIED from source): patches the rstudioapi namespace, supports ids, and reports `getVersion()` as `0`.
8. **Jupyter/IRkernel** (VERIFIED). The kernel runs `R --slave -e IRkernel::main()`, so `interactive()` is `FALSE`. `Kernel$run()` sets `options(jupyter.in_kernel = TRUE)`. jupyter_server (≥ 2.0.7) exports `JPY_SESSION_NAME` = the notebook's full path when the kernel starts. The protocol itself never sends the path. Writing an `.ipynb` that is open in a Jupyter frontend conflicts with its autosave. Recommendation: no disk writes while the notebook is open; use outputs and, opt-in, a `set_next_input` payload.
9. **Block convention for `.R`** (VERIFIED by prototype):
   ```r
   gptr("prompt")
   # >>> gptr:7f3a21 model=... date=... prompt=<12hex> [sha= call= tokens= cost= session=]
   ...code the agent ran successfully...
   #> reprex-style key output
   ## Decision: rationale
   # <<< gptr:7f3a21
   ```
   Blocks are tied to a call by position: they form a run directly after the calling statement. A pipeline gets one block per call, in call order, with `call=k`. Association uses `prompt=` (hash of the normalised prompt). An edited prompt turns the block **stale** and it is regenerated **in place under the same id**. Inserting and updating are idempotent, and a replay pass left the file byte-identical (md5 unchanged).
10. **`.Rmd`/`.qmd`: the agent's code goes into a separate chunk after the prompt's chunk** (VERIFIED with knitr and with Quarto 1.10.18). Rmd header: `{r gptr-<id>}`. qmd header: `{r}` plus `#| label: gptr-<id>`. The chunk body is the same marker block, so one finder works on every text format. `knitr::purl()` output of such a document is itself a valid gptr `.R` script. knitr requires unique chunk labels, and `gptr-<id>` is unique by construction.
11. **`.ipynb` round-trips byte-for-byte with our own serializer, not `jsonlite::toJSON`** (VERIFIED). `toJSON` escapes `</` as `<\/`, prints the double `3.0` as `3`, and its pretty printers expand `{}`/`[]`. A short R serializer (`json_escape`/`json_num`/`json_write`, about 65 lines) reproduces Python's `json.dumps(indent=1, sort_keys=True, separators=(",", ": "), ensure_ascii=False)` plus a trailing newline, which is how nbformat writes notebooks. (Correction from verification: the first version's number formatter did **not** match Python for doubles that need 16 significant digits, such as `1/3`, or for 1e15 to 1e16. Plotly, Vega and widget outputs are full of such doubles, so untouched cells changed bytes. The `json_num()` in §5.0 has been replaced, and it now matches Python on 6,018 test doubles.) Results:
    - unchanged round trip: identical bytes;
    - inserting an agent cell: diff contains only the new cell;
    - repeating the upsert: identical bytes;
    - rewriting a cell: keeps its outputs and `execution_count`.
    The agent cell has `id = "gptr-<id>"` (valid under nbformat 4.5's `^[a-zA-Z0-9-_]+$`) and `metadata.gptr = {id, model, prompt}`.
12. **Replay semantics.** Modes are `auto` (default), `replay`, `live` and `record`, modelled on vcr's `once/none/new_episodes/all` and httptest2's `with_mock_dir`. Core invariant: **`gptr()` never executes a recorded block itself. The document executes it.** In replay, `gptr()` is a zero-token no-op that returns the cached answer, and the plain R code below it runs normally. That makes the script runnable history, like a reprex.
13. **Avoiding double execution when regenerating.**
    - Under `base::source()`/`Rscript`, the old block has already been parsed and will run anyway. So a stale block **replays with a warning**, and live regeneration goes through a gptr-aware runner, `gptr_source()`.
    - Under knitr, `gptr()` can suppress the old agent chunk with a `knitr::opts_hooks` hook on `label` (VERIFIED: it disables a later chunk). A `knit_hooks` `document` hook removes it at the end of the knit (VERIFIED). Cleanup is needed because the hook otherwise persists after `knit()` (VERIFIED).
    - In an IDE, move the cursor past the new block.
14. **System One decisions are cached, not written into the document.** One JSON file per decision under `.gptr/cache/s1/<2 hex>/<sha256>.json`. The key is the sha256 of canonical JSON: endpoint, model, question, type, choices, instructions and the input. It is vectorised and batches only the misses. The prototype confirmed: one API call per run of misses, zero calls on replay, an error on a miss in `replay` mode, and a new key when the question text changes.
15. **Console sessions** produce an append-only transcript. Each turn is either a `gptr("...")` line plus a block, or a direct `!` R line plus `#>` output. The file is `gptr-session-YYYYMMDD-HHMM.R` (under `.gptr/transcripts/` in package projects) and is written only with consent. Sourcing it in a fresh process rebuilt the analysis (VERIFIED). The JSONL session in `.gptr/sessions/` stays the exact-resume record, linked from block headers by `session=`.
16. **Workspace.**
    - `.gptr/` contains: `vignette.Rmd`, `settings.json`, `skills/`, `extensions/`, `agents/`, `prompts/`, `sessions/` (gitignored), `cache/{s1,s2}` (committed by default, following Quarto's advice to commit `_freeze`), `cache/tmp` (gitignored), `artifacts/`, `transcripts/`.
    - `vignette.Rmd` goes into the system prompt as **raw text**: YAML header and HTML comments stripped, chunks kept verbatim. It is **never executed**, because knitting it would run a repository's code.
    - Pi-compatible context files are loaded too: `AGENTS.override.md`/`AGENTS.md`/`CLAUDE.md` walking up from cwd, plus a user-level one.
    - `.gptr` is not in R's default build exclusions (`tools:::.hidden_file_exclusions`, VERIFIED), so in package projects `gptr_init()` must add `^\.gptr$` to `.Rbuildignore`.
17. **Dependencies** for this layer: `jsonlite` and `cli` (for `hash_sha256`) in Imports. Both are already in D-20. `rstudioapi`, `knitr`, `yaml` and `filelock` are Suggests. `this.path` is not needed; its techniques are reproduced in about 100 lines. CRAN points to watch:
    - no writes to user files without consent (the policy quote is in §6);
    - block ids must not touch `.Random.seed` (VERIFIED: ours use sha256, not RNG);
    - avoid `:::` (e.g. `knitr:::current_lines`);
    - guard every IDE call with `isAvailable()`/`hasFun()`.

---

## 2. Findings

### 2.1 Where is the call? Front-end by front-end (part A)

| Front end | Detect | Document path | Locate the `gptr()` call | Edit channel |
|---|---|---|---|---|
| Plain console (terminal R, Rgui, R.app) | `interactive()` and no srcref and no IDE | none | none: a top-level console call has no srcref (VERIFIED) | a gptr-owned transcript, with consent |
| `source("f.R")`, interactive | srcref on `sys.call()` whose `srcfile$isFile` is TRUE | `file.path(srcfile$wd, srcfile$filename)` | srcref gives the statement; content ordinal against `srcfile$lines` | disk: atomic write with md5 check (safe mid-source) |
| `source()` with `keep.source = FALSE` (`Rscript -e`), `sys.source()` | a `source`/`sys.source` frame on the stack | `ofile` (source) or `file` (sys.source) in that frame | `exprs[[i]]`: k-th identical top-level expression | disk |
| `Rscript f.R` | `!interactive()` and `commandArgs()` contains `--file=` (and not knitr/Quarto) | the `--file=` value | static match by expression identity or prompt, plus a per-file execution ordinal | **disk, deferred to exit** |
| knitr / `rmarkdown::render` | `getOption("knitr.in.progress")` | `knitr::current_input(dir = TRUE)` | chunk label `knitr::opts_current$get("label")` plus prompt within that chunk | disk (safe mid-knit) |
| Quarto, knitr engine | knitr as above, plus `QUARTO_DOCUMENT_FILE` set | `file.path(QUARTO_DOCUMENT_PATH, QUARTO_DOCUMENT_FILE)` | as for knitr | disk (safe mid-render) |
| Quarto, jupyter engine (IRkernel or ark) | `QUARTO_DOCUMENT_FILE` set, knitr not in progress | same env vars | static scan of the `.qmd` | disk (UNCERTAIN, not tested) |
| RStudio (Ctrl+Enter / console) | `Sys.getenv("RSTUDIO") == "1"`, `.Platform$GUI == "RStudio"` | `rstudioapi::getSourceEditorContext()$path` (`""` if untitled) | parse `ctx$contents` (the buffer); nearest matching call above the cursor row | `rstudioapi::modifyRange(..., id)` then `documentSave(id)` if the buffer was clean |
| RStudio "Source" button | srcref present | the real path, or `~/.active-rstudio-document` for unsaved buffers (LIKELY) | srcref | if the path is `.active-rstudio-document`, redirect to the IDE channel |
| Positron | `Sys.getenv("POSITRON") == "1"`, `.Platform$GUI == "Positron"` | `getSourceEditorContext()$path` (last active editor) | as RStudio | `insertText(id = NULL)` only; prefer a disk write when the buffer is clean |
| VS Code + vscode-R (`sess`) | `Sys.getenv("TERM_PROGRAM") == "vscode"` (+ `sess` attached) | `getSourceEditorContext()$path` | as RStudio | `insertText(..., id)` supported |
| Jupyter IRkernel | `isTRUE(getOption("jupyter.in_kernel"))` | `Sys.getenv("JPY_SESSION_NAME")`; else content match over `*.ipynb` in `getwd()` (this.path's method) | expression identity against cell sources | **no disk write while open**: show code in outputs; opt-in `set_next_input` |

#### 2.1.1 srcref behaviour (all VERIFIED; outputs in §5.1)

- `options("keep.source")` is `TRUE` in `R --interactive` and `FALSE` under `Rscript` (`keep.source at start: FALSE`).
- Call typed at the interactive top level: `has_srcref: FALSE`.
- Interactive braces `{ r2 <- gptr_stub("typed braces") }`: srcref `2 3 2 33 ...` with `srcfile_class: srcfilecopy`, `filename: ""`. The lines are relative to the typed input, so they are useless for file location.
- `source("script1.R", keep.source = TRUE)`:
  - srcref = the **statement**, e.g. `r1 <- gptr_stub("first prompt")`, `srcref_int: 2 1 2 31 1 31 2 2`;
  - `filename: "script1.R"` is **relative**, `wd` is the directory, `isFile: TRUE`, `timestamp` = file mtime;
  - a multi-line call spans `3 1 7 1`;
  - `for (i in 1:2) r4 <- gptr_stub("in a loop")` gives the srcref of the whole `for` statement (line 10) on both iterations;
  - a call inside a non-braced function body gives the srcref of the **function definition** (line 8), not of the calling line 9;
  - `if (TRUE) { r6 <- gptr_stub("in braces") }` gives the inner statement (`12 13 12 40`).
- `Rscript script2.R` after `options(keep.source = TRUE)`:
  - top-level statements still have **no** srcref (the file is parsed one expression at a time);
  - statements inside `{}` get srcrefs with `filename ""` and lines **relative to the brace expression** (`2 3 2 43`).
- R documents the `srcref` vector as `c(first_line, first_byte, last_line, last_byte, first_column, last_column, first_parsed, last_parsed)`. Use elements 7 and 8 (parsed lines) to index `srcfilecopy$lines` when `#line` directives may be present (R docs, `?srcfile`).
- `base::source()` internals on R 4.4.3 (VERIFIED by `deparse(base::source)`):
  - `ofile <- file` (line 28 of the deparse);
  - with `keep.source = TRUE`: `lines <- readLines(file)` and `srcfile <- srcfilecopy(filename, lines, file.mtime(filename)[1], isFile = TRUE)`;
  - otherwise `srcfile <- filename` and the file is parsed straight from the connection, so **there is no `lines` variable**;
  - loop `for (i in seq_len(Ne + echo)) { ... ei <- exprs[i] ...}`.
- `sys.source()` keeps `file`, `exprs` and `i`: `for (i in seq_along(exprs)) eval(exprs[i], envir)` (VERIFIED).
- **Positron hooks `source()`** (VERIFIED, ark `modules/positron/hooks_source.R`). When the file has breakpoints and only `file`/`echo`/`local` are given, Positron annotates the code and evaluates `parse(text = annotated, keep.source = TRUE)`, so srcrefs refer to the annotated text. Otherwise it falls back to the original `source`. gptr must validate srcref text (item 3 of §1) rather than trust it.
- Positron's debugger supports breakpoints for code run with Cmd/Ctrl+Enter ([Positron R debugging guide](https://github.com/posit-dev/positron-website/blob/main/guide-r-debugging.qmd)). This suggests editor-executed code may carry file srcrefs in Positron. **UNCERTAIN**: the design must work either way, which it does, because srcrefs are validated and IDE matching is the fallback.

#### 2.1.2 Rscript self-modification hazard (VERIFIED)

The script `p1/selfmod.R` inserts a line after itself and then continues:

```
line1 runs
line after insert point runs
last line runs
Error: unexpected string constant in:
"n")
cat(""
Execution halted
```

The same thing happened with a 16 KB file (re-run by the verifier: same error). R had buffered the old file, reached EOF, then read the bytes by which the file had grown and failed to parse them. The failure is not always loud. In a verifier variant where the shifted bytes landed inside trailing comment lines, `Rscript` exited 0 and silently skipped the inserted line. Deferring writes is the only safe option.

With `reg.finalizer(env, fun, onexit = TRUE)` deferring the write (`p1/deferred.R`), the result was: `exit=0`, `finalizer wrote file at exit`, and the second run executed the inserted line. Exit finalizers also ran after `stop("boom")` (exit status 1) and after `quit(save = "no", status = 3, runLast = FALSE)`.

In `source()` (`p1/srcmod.R`), the file was modified mid-run, the new line did **not** run in that pass, and the file was intact afterwards.

#### 2.1.3 knitr and Quarto (VERIFIED)

The prior-run probes were re-read, and `k/doc1.md` and `q/qdoc*.md` are their outputs:

- **knitr** (`knitr::knit`, non-interactive):
  - `current_input: doc1.Rmd`, and `current_input(dir=TRUE)` gives the absolute path;
  - `label: ask-one` (unlabelled chunks: `unnamed-chunk-1`);
  - `knitr.in.progress: TRUE`, `interactive: FALSE`, `has_srcref FALSE`;
  - `opts_current$get("code")` = the chunk's code lines;
  - `params.src: ask-one, echo=TRUE, fig.width=5`;
  - the call stack is `knitr::knit > process_file > ... > block_exec > eng_r > in_input_dir > ... > evaluate::evaluate > ... > eval`;
  - the internal `knitr:::current_lines()` returned `"30-36"`, but it is internal (`:::`), so it is not for CRAN code.
- **Quarto 1.10.18** (knitr engine):
  - `current_input: qdoc.rmarkdown` (a temporary intermediate);
  - `QUARTO_DOCUMENT_FILE = qdoc.qmd`, `QUARTO_DOCUMENT_PATH = <dir>`, `QUARTO_PROJECT_DIR`, `QUARTO_PROJECT_ROOT`, `QUARTO_EXECUTE_INFO = <tmp json>` (with keys `document-path`, the absolute `.qmd` path, and `format`), `QUARTO_BIN_PATH`, `QUARTO_ROOT`, `QUARTO_SHARE_PATH`, `QUARTO_DENO`. Correction: an earlier draft listed `QUARTO_R`. The verifier's re-run did not have it set, and Quarto documents it as a variable that Quarto *inspects* (the user sets it to choose `Rscript`), not one Quarto sets;
  - `quarto.version` opts_knit is set;
  - `commandArgs: .../exec/R | --no-echo | --no-restore | --file=/Applications/RStudio.app/.../quarto/share/rmd/rmd.R`: a `--file=` that is **not** the user's document;
  - call stack `.main > execute > rmarkdown::render > knitr::knit > ...`.
  - Quarto's documented variables are listed in the [environment-vars docs](https://quarto.org/docs/advanced/environment-vars.html): "`QUARTO_DOCUMENT_PATH` Directory of the document being rendered", "`QUARTO_DOCUMENT_FILE` Name of the file being rendered", "`QUARTO_EXECUTE_INFO` holds the path of a file containing a JSON object with execution information".
- **Writing the source document during knit/render is safe** (§5.4). The inserted agent chunk did not run in pass 1, and pass 2 replayed with the file unchanged (md5 equal), for both `knitr::knit("report.Rmd")` and `quarto render report.qmd`.
- A custom YAML cell option `#| gptr-custom-option: {id: abc123, model: "x/y"}` passed through Quarto into `knitr::opts_current$get()` as a list, with no warning in verbose output.
- knitr `opts_hooks` on `label` can disable evaluation of a later chunk (the stale block chunk printed its code but did not run). The hook **persists after `knit()` returns** (`label hook still set after knit(): TRUE`). A `knit_hooks$set(document = ...)` hook runs at the end of the knit and can delete it.
- A custom **knitr engine `gptr`** works in both knitr and Quarto. The chunk text is the prompt, and `#|` / header options such as `model` reach `options$model`. glue 1.8.1 shows the CRAN-accepted registration pattern: `knitr::knit_engines$set()` directly if knitr is loaded, else `setHook(packageEvent("knitr", "onLoad"), ...)` (VERIFIED by printing `glue:::.onLoad`).

#### 2.1.4 RStudio (rstudioapi 0.18.0; VERIFIED from installed docs and source)

- `rstudioapi::isAvailable()` is `identical(.Platform$GUI, "RStudio") && version_ok(...)`. Calls dispatch to `get(".rs.api.<name>", as.environment("tools:rstudio"))`.
- `getSourceEditorContext(id = NULL)` returns a `document_context`: `list(id, path, contents, selection)`. `path` is `""` for untitled documents. `selection[[1]]$range$start[["row"]]` is the 1-based cursor row. Passing `id` needs RStudio 2022.06.0+. RStudio's `getActiveDocumentContext()` reports the console (`id = "#console"`, `path = ""`) when the console input was the last editor to take focus. The check is "sticky", not live (LIKELY: this is the Positron developers' reading of RStudio's `Source.java` in the [positron#16063](https://github.com/posit-dev/positron/pull/16063) description and review thread; [rstudio#6805](https://github.com/rstudio/rstudio/issues/6805) is a closed regression report about exactly this behaviour). Use `documentId(allowConsole = TRUE)` for that test.
- `documentId(allowConsole = TRUE)`: "Allow the pseudo-id #console to be returned, if the R console is currently focused". Use this to tell typed-at-console calls from editor-executed ones. `documentId`/`documentPath` need RStudio ≥ 1.4.843; `documentSave`/`documentSaveAll` ≥ 1.1.287.
- `insertText(location, text, id)` and `modifyRange(...)` are synonyms, and `setDocumentContents(text, id)` is `insertText(document_range(c(1,1), c(Inf,1)), text, id)`. Positions are `document_position(row, column)`, 1-based, and `Inf` is clamped to the document end. `insertText(Inf, "# Hello\n")` appends. "`id` … When NULL or blank, the requested operation will apply to the currently open, or last focused, RStudio document."
- `setCursorPosition(position, id)` calls `setSelectionRanges`. `documentClose(id, save)` never prompts.
- `registerChunkCallback(callback)` gives a callback after a chunk runs in the Rmd editor. It returns HTML outputs only, so it is not useful for writing.
- When a file changes on disk and the buffer has **unsaved changes**, RStudio asks "The file … has changed on disk. Do you want to reload the file from disk and discard your unsaved changes?" ([rstudio#10504](https://github.com/rstudio/rstudio/issues/10504)). A silent reload for clean buffers is LIKELY.
- Unsaved or untitled documents are sourced as `source('~/.active-rstudio-document')` (LIKELY, [forum](https://forum.posit.co/t/source-active-rstudio-document/65723)). A srcref to that path must be mapped to the active editor, never written to.
- Ctrl+Enter sends code to the console, so the call has no srcref. RStudio's default moves the cursor to the next statement (LIKELY). So: match the call nearest **above** the cursor row, and after inserting a block move the cursor past it so the next Ctrl+Enter does not re-run code the agent already ran.

#### 2.1.5 Positron (VERIFIED from ark main, fetched 2026-09-29)

Files are under `crates/ark/src/modules/`.

- `positron/positron.R`: `if (Sys.getenv("POSITRON") == 1) { .Platform$GUI <- "Positron" }`, rebound in baseenv.
- `positron/init.R`: attaches `tools:rstudio` and sets a hook on `packageEvent("rstudioapi", "onLoad")` that does `body(ns$isAvailable) <- TRUE` (comment: "Override `rstudioapi::isAvailable()` so it thinks it's running under RStudio").
- `rstudio/document-api.R`:
  - `getSourceEditorContext(id = NULL)` requires `stopifnot(is.null(id))` and returns `list(id = context$id, path, contents, selection)` built from `.ps.ui.LastActiveEditorContext()`. The `id` field was added by ark PR #1408, merged 2026-09-18 ([GitHub API](https://api.github.com/repos/posit-dev/ark/pulls/1408)).
  - `insertText` and `modifyRange` have `# TODO: Support document IDs` and `stopifnot(is.null(id))`, then call `.ps.ui.modifyEditorSelections(ranges, text)`.
  - `documentSave(id = NULL)` also requires `stopifnot(is.null(id))` and runs `"workbench.action.files.save"` (the active editor).
  - `documentNew(type, code, row = 0, column = 0, execute = FALSE)` allows only `execute = FALSE` and a (0,0) position.
- Positron PR #16063 (merged 2026-09-23): `getActiveDocumentContext()`, `getSourceEditorContext()`, `insertText()` and `documentPath()` "now target the console when it has focus", with id `"#console"` and "sticky" focus semantics ([PR](https://github.com/posit-dev/positron/pull/16063)). **Consequence:** in Positron, `insertText(id = NULL)` after the user typed in the console may target the console input. gptr must check the context's `id != "#console"` and that the path matches before using the API, and otherwise edit the file on disk.
- Positron docs: "use `rstudioapi::hasFun()` to defensively check if a method is implemented" and "use `Sys.getenv("POSITRON")`" ([Positron docs](https://positron.posit.co/migrate-rstudio-settings-and-extensions.html)).
- Other env vars: `POSITRON_VERSION`, `POSITRON_MODE`, `POSITRON_LONG_VERSION` (ark `rstudio/rstudioapi.R`).

#### 2.1.6 VS Code with vscode-R (VERIFIED from `REditorSupport/vscode-R` main, `sess/R/rstudioapi.R`)

- The session watcher is now an R package, `sess` (version 3.0.1). `R/profile.R` calls `sess::connect(use_rstudioapi = as.logical(Sys.getenv("SESS_RSTUDIOAPI", "TRUE")), ...)`.
- `patch_rstudioapi()` rebinds these in the rstudioapi namespace: `getActiveDocumentContext`, `getSourceEditorContext`, `insertText`, `modifyRange`, `setSelectionRanges`, `setCursorPosition`, `documentSave`, `documentId`, `documentPath`, `documentSaveAll`, `documentNew`, `setDocumentContents`, `hasFun`, `findFun`, `isAvailable`, `getVersion` and others.
- `getSourceEditorContext <- getActiveDocumentContext`, which asks the client for the active editor. `documentSave(id)`, `insertText(..., id)` and `documentPath(id)` pass `id` to the client. `getVersion <- function() numeric_version("0")`, so **never gate on RStudio version numbers**.
- Wiki: emulation is "enabled by default when the session watcher is active". Setting: `r.session.emulateRStudioAPI`. Text "destined for the 'active document'" goes to the active or last active text editor ([wiki](https://github.com/REditorSupport/vscode-R/wiki/RStudio-addin-support)).
- Detection: `TERM_PROGRAM == "vscode"`, the same as Posit's btw package `which_ide()` ([btw utils-ide.R](https://github.com/posit-dev/btw/blob/main/R/utils-ide.R)). `which_ide()` tests `POSITRON == "1"` first, then `RSTUDIO == "1"`, then `TERM_PROGRAM`. Keep that order, because Positron is a VS Code fork.
- sess's `documentId(allowConsole = TRUE)` ignores `allowConsole` and returns the active document context's id (VERIFIED, `sess/R/rstudioapi.R`). The §4.2 step-7 test for `"#console"` is therefore only meaningful in RStudio and Positron.

#### 2.1.7 Jupyter / IRkernel (VERIFIED unless noted)

- The kernelspec shipped with IRkernel 1.3.2 is `{"argv": ["R", "--slave", "-e", "IRkernel::main()", "--args", "{connection_file}"], ...}`. `R --no-echo -e 'interactive()'` prints `FALSE`, so `interactive()` is FALSE in Jupyter.
- `Kernel$run` does `options(jupyter.in_kernel = TRUE)`; the default set at load is `FALSE`.
- `Executor$execute` evaluates with `evaluate(request$content$code, envir = .GlobalEnv, ...)` and replaces `base::readline` with a stdin-request version, so prompts work even though `interactive()` is FALSE.
- The `Executor` has a `payload` field that is reset per request and sent in `execute_reply`. `page()` appends `list(source = "page", ...)`.
- `jupyter_server/services/sessions/sessionmanager.py` `get_kernel_env()` returns `{**os.environ, "JPY_SESSION_NAME": path}` where `path = os.path.join(cwd, name)`. The CHANGELOG entry for 2.0.7 reads "Set JPY_SESSION_NAME to full notebook path." The value is set **at kernel start**, so it is stale after a rename. VERIFIED from source: `update_session()` does call `kernel_manager.update_env(...)` with the new path, but jupyter_client's `update_env` docstring says it takes effect "only after kernel restart".
- The messaging spec's `execute_request` content has `code, silent, store_history, user_expressions, allow_stdin, stop_on_error`, with no path. Payloads are "considered deprecated, though their replacement is not yet implemented". `set_next_input` has `"text"` and `"replace"` and is "used to create new cells in the notebook" ([jupyter-client docs](https://jupyter-client.readthedocs.io/en/latest/messaging.html)).
- this.path 2.8.0 finds a Jupyter notebook by listing `*.ipynb` in the initial working directory. It parses each notebook whose metadata says R and the current R version, and returns the first whose cell expressions are `identical()` to the executing call, found via `sys.frame(1L)[["kernel"]][["executor"]][["nframe"]]` ([this.path thispath.R](https://github.com/cran/this.path/blob/master/R/thispath.R), lines 408–470).
- Using `set_next_input` from R: append `list(source = "set_next_input", text = code, replace = FALSE)` to `sys.frame(1)$kernel$executor$payload`. **UNCERTAIN**: this uses IRkernel internals and could not be tested because Jupyter is not installed.

### 2.2 File formats and safe editing (part B)

#### 2.2.1 `.R` scripts: comment conventions that other tools interpret (VERIFIED from knitr 1.51 source unless noted)

- `knitr::spin()` defaults:
  - `doc = "^#+'[ ]?"`: `#'` lines become Markdown prose;
  - `inline = "^[{][{](.+)[}][}][ ]*$"`;
  - `comment = c("^[# ]*/[*]", "^.*[*]/ *$")`: `/* ... */` blocks are dropped.
- Chunk-header regex: `rc = "^(#|--)+(\\+| %%| ----+| @knitr)(.*?)\\s*-*\\s*$"`. So `#+ label, opts`, `# %% label`, `# ---- label ----` and `## @knitr label` all start chunks.
- **Lines starting with `#|` also start a new chunk** (`pipe_comment_start(block)`).
- Our markers `# >>> gptr:...` / `# <<< gptr:...` match none of these. Spin output keeps them as code comments inside the chunk (VERIFIED, §5.5).
- Spinning purl output with labelled `## ----label, opts----` headers gives `{rsetup, include=FALSE}` with the space missing (VERIFIED quirk; not our problem, but it means purl→spin is not a clean round trip).
- RStudio code sections: "Any comment line which includes at least four trailing dashes (-), equal signs (=), or pound signs (#)" ([Posit docs](https://docs.posit.co/ide/user/ide/guide/code/code-sections.html)). Our headers do not end with `----`, so they do not appear in the outline. An optional variant could append ` ----` to make blocks navigable; it stays spin-safe because it does not start with `# ----`.
- jupytext `percent` format: `# %% Optional title [cell type] key="value"`; Markdown cells are `# %% [markdown]`. `light` format: `# +` / `# -` ([jupytext scripts doc](https://github.com/mwouts/jupytext/blob/main/website/src/content/docs/formats/scripts.md)). We do not emit `# %%` in headers: spin would take the rest of the line as the chunk label and options, and `gptr:7f3a21 model=...` is not a valid chunk option string.
- roxygen `#'`: only meaningful in package `R/` files before objects. Inside blocks use `##` for rationale. Offer `#'` (spin prose) as an option.

#### 2.2.2 `.Rmd` / `.qmd` (VERIFIED)

- `knitr::all_patterns$md`: `chunk.begin = "^[\t >]*```+\\s*\\{([a-zA-Z0-9_]+( *[ ,].*)?)\\}\\s*$"`, `chunk.end = "^[\t >]*```+\\s*$"`, `inline.code = "(?<!(^``))(?<!(\n``))`r[ #]([^`]+)\\s*`"`.
- Our scanner also tracks fence length, so a ```` fence may contain ``` lines. The prototype handled `cat("```not a fence end```\n")` inside a four-backtick chunk.
- Labels: first unnamed item in the `{r label, ...}` header, or `label = "..."`, or `#| label: x` (Quarto style, also accepted by knitr ≥ 1.35). knitr parses headers with `xfun::csv_options()` (`knitr:::parse_params`).
- YAML front matter: the leading `---` up to the next `---` or `...`.

#### 2.2.3 `.ipynb` (nbformat 4.5; VERIFIED from `nbformat/v4/nbformat.v4.5.schema.json` and `nbjson.py`)

- Top-level required keys: `metadata, nbformat_minor, nbformat, cells`, with `nbformat_minor` minimum 5.
- `code_cell` requires `id, cell_type, metadata, source, outputs, execution_count`. `markdown_cell` and `raw_cell` require `id, cell_type, metadata, source` (plus optional `attachments`).
- `cell_id`: `"type":"string","pattern":"^[a-zA-Z0-9-_]+$","minLength":1,"maxLength":64`.
- Outputs:
  - `stream`: `output_type, name, text`;
  - `display_data`: `output_type, data, metadata`;
  - `execute_result`: adds `execution_count`;
  - `error`: `ename, evalue, traceback`.
- Notebook `metadata.kernelspec` requires `name, display_name`; `language_info` requires `name`.
- Writer (`JSONWriter.writes`): `indent=1, sort_keys=True, separators=(",", ": "), ensure_ascii` default `False`. Then `split_lines`:
  - a cell `source` string becomes `splitlines(True)`, so every element but the last ends with `\n`;
  - mimebundle values are split only for `text/*`, `application/javascript` and `image/svg+xml`; JSON mimetypes are left alone;
  - stream `text` is split.
- `strip_transient` drops `metadata.orig_nbformat`, `metadata.orig_nbformat_minor`, `metadata.signature` and cell `metadata.trusted`.
- `split_lines` uses Python's `str.splitlines(True)`, which also splits on `\r`, `\x0b`, `\x0c`, `\x1c`–`\x1e`, `\x85`, U+2028 and U+2029. The prototype's `nb_source_split()` splits only on `\n`. This does not matter for cells gptr leaves alone (their line lists are kept as read), but it can matter for new cells whose code contains those characters.
- `nbformat.write()` appends `"\n"` if missing.
- Readers accept either a string or a list of strings (`rejoin_lines`).

#### 2.2.4 jsonlite pitfalls for notebooks (VERIFIED)

`jsonlite::toJSON("</table> a/b", auto_unbox = TRUE)` gives `"<\/table> a/b"`; `prettify` shows the same. `toJSON(list(a = 3, ...), digits = NA)` gives `"a":3`, while the notebook had `3.0`. `fromJSON('{"a":3.0,"b":3,"c":10000000000}', simplifyVector = FALSE)` gives `num 3`, `int 3`, `num 1e+10`. So the integer/double distinction survives reading and can be honoured by a custom writer. Big integers become doubles, a small residual risk (§7). jsonlite's parser is correctly rounded: it returned the original double for all 6,000 `%.17g` strings the verifier tried. Base R's `as.numeric()` was **not** correctly rounded in R 4.4.3 on macOS arm64: 1,744 of those 6,000 came back as a different double. So never use `as.numeric()` as the round-trip oracle when formatting numbers. `toJSON(digits = NA)` writes only 15 significant digits (`1/3` gives `0.333333333333333`). A round trip through `toJSON(...) |> prettify(indent = 1)` changed 33 bytes: expanded `{}`/`[]` and `<\/`.

#### 2.2.5 Conversions

- `knitr::spin(hair, knit = FALSE, format = "Rmd"|"qmd")`: `.R` → `.Rmd`/`.qmd`.
- `knitr::purl(input, output, documentation = 1)`: `.Rmd` → `.R` with `## ----label, opts----` headers (VERIFIED; block markers are preserved).
- `quarto convert` (`.ipynb` ↔ `.qmd`): per jupytext's docs it "concatenat[es] consecutive Markdown cells and turn[s] raw cells into Markdown cells". This needs the Quarto CLI, so it is Suggests-only territory. It would work through `processx`/`system2` if `quarto` is on PATH.
- jupytext is Python-only and out of scope.

### 2.3 Precedents for replay and caching (part D)

| Precedent | Key / trigger | Modes / behaviour | Evidence |
|---|---|---|---|
| knitr cache | hash of chunk code and "all chunk options except `include`"; `cache.extra` adds keys; `dependson`/`autodep` | skipped chunk's side effects (`library()`, options) are lost | [yihui.org/knitr/demo/cache](https://yihui.org/knitr/demo/cache/) |
| Quarto freeze | `freeze: true` "should never be re-rendered during a global project render"; `auto` "re-render only when source changes" | "You should check the contents of `_freeze` into version control" | [quarto code-execution](https://quarto.org/docs/projects/code-execution.html) |
| targets | cues: `command`, `depend`, `format`, `repository`, `iteration`, `file`, `seed`; modes `thorough/always/never` | "never": does not run unless metadata is missing or the last run errored | [tar_cue](https://docs.ropensci.org/targets/reference/tar_cue.html) |
| memoise / cachem | `memoise(f, cache = cachem::cache_mem(max_size = 1024 * 1024^2), hash = function(x) rlang::hash(x))`; `cache_disk(max_size = 1GB, max_age = Inf, evict = c("lru","fifo"))` | size- and age-managed | `args()` on installed memoise 2.0.1 / cachem 1.1.0 (VERIFIED) |
| vcr | `once` "Replays recorded interactions, records new ones if no cassette exists, and errors on new requests if cassette exists"; `none` "Guarantees that no HTTP requests occur"; `new_episodes` "Replays recorded interactions and always records new ones"; `all` "Never replays recorded interactions, always recording new." | | [vcr use_cassette.R](https://github.com/ropensci/vcr/blob/main/R/use_cassette.R) |
| httptest2 | `with_mock_dir()`: "If the `tests/testthat/dir` folder doesn't exist, `capture_requests()` will be run to create mocks. If it exists, `with_mock_api()` will be run." | record-on-first-run | [httptest2](https://enpiar.com/httptest2/reference/with_mock_dir.html) |
| reprex | `comment = opt("#>")` | output-as-comments convention | `args(reprex::reprex)` (VERIFIED) |
| ellmer | `batch_chat(chat, prompts, path, wait, ignore_hash)`: "The file records a hash of the provider, the prompts, and the existing chat turns. If you attempt to reuse the same file with any of these being different, you'll get an error." `contents_record()`/`contents_replay()` serialise Turns | hash-mismatch-is-error | installed ellmer 0.4.0 Rd (VERIFIED) |

### 2.4 Pi: project context files and configuration (part F; VERIFIED from the local clone, commit `1b347794`)

- `packages/coding-agent/src/core/resource-loader.ts`:
  - lines 184–203: `loadContextFileFromDir(dir)` tries `["AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"]` in order and returns the first regular file (BOM stripped).
  - lines 232–270: `loadProjectContextFiles({cwd, agentDir})` takes the global file from `agentDir` first, then walks from cwd up to the filesystem root, prepending each directory's file so the root comes first. It de-duplicates paths and skips a worktree-shadowed main-repo file (lines 205–230).
  - lines 1201–1227: `SYSTEM.md` / `APPEND_SYSTEM.md` are taken from `<cwd>/.pi/` when the project is trusted, else from `agentDir`.
- `system-prompt.ts` lines 72–79 render context files as `"Project-specific instructions and guidelines:"` followed by `<project_instructions path="...">\n<content>\n</project_instructions>` blocks. Lines 163–170 order the sections as `addendum`, `project_context`, `skills`, `cwd`, each later wrapped in `<name>…</name>` (line 177).
- `docs/configuration.md` lines 3–47:
  - agent dir `~/.pi/agent` (env `PI_CODING_AGENT_DIR`) holds `settings.json, keybindings.json, mcp.json, models.json, auth.json, AGENTS/CLAUDE files, SYSTEM.md, APPEND_SYSTEM.md, extensions/, skills/, prompts/, themes/`;
  - project `.pi/` holds `settings.json, mcp.json, SYSTEM.md, APPEND_SYSTEM.md, extensions/, skills/, prompts/, themes/`;
  - "Context-file discovery does not require project trust."
- `docs/security.md` (project trust): trust gates `.pi/settings.json`, `.pi/mcp.json`, `.pi/extensions|skills|prompts|themes`, `SYSTEM.md`/`APPEND_SYSTEM.md` and project `.agents/skills`. "A bare `.pi` directory does not require project trust." "Treat instructions in a folder as untrusted input even when you decline project trust."
- `docs/session-format.md`:
  - sessions live in `~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl`;
  - the header is `{"type":"session","version":3,"id":"uuid","timestamp":...,"cwd":...}`;
  - entries have `id`/`parentId`;
  - `CustomEntry` is `{"type":"custom",...,"customType":"my-extension","data":{...}}`, which "Does NOT participate in LLM context". That is the natural carrier for document-block bookkeeping.

---

## 3. Exact specifications

### 3.1 Block grammar for R code (`.R`, and the body of agent chunks and cells)

```
BLOCK_OPEN  = ^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$
BLOCK_CLOSE = ^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$
HEADER_KV   = ([A-Za-z_][A-Za-z0-9_.]*)=("([^"\\]|\\.)*"|[^ \t]+)      # values with spaces are "quoted" (R escapes)
CONTINUATION (optional, reserved) = ^([ \t]*)# gptr: (key=value ...)$   # lines directly after BLOCK_OPEN
```

- **id**: 6 lowercase hex characters containing at least one letter a–f. On collision within the document, grow to 8, 10, … up to 16. Generate from `cli::hash_sha256(paste(time with µs, pid, counter, prompt))`. **Never** use `sample()`/`runif()`, which would change the user's `.Random.seed`.
- **Header keys:**

| key | required | meaning |
|---|---|---|
| `model` | yes | `provider/model` that produced the final code (e.g. `anthropic/claude-sonnet-5-5`); System One and routers record the physical model |
| `date` | yes | `YYYY-MM-DD` of the last (re)generation |
| `prompt` | yes | first 12 hex of sha256 of the normalised prompt (`trimws`, CRLF→LF, whitespace around newlines removed) |
| `sha` | recommended | first 8 hex of sha256 of the body lines as last written by gptr; a mismatch means the user edited the block |
| `call` | when the ordinal is > 1 | ordinal of the `gptr()` call inside the statement (pipelines) |
| `tokens` | optional | `<input>/<output>` totals for the turn |
| `cost` | optional | USD, plain number (`0.042`) |
| `session` | optional | short session id, the JSONL file in `.gptr/sessions/` |
| `value` | optional | name of the variable holding the agent-designated value (see §4.4.6) |

- **Body lines**, in order of emission:
  1. code of each **successful** `r`-tool execution marked `record = TRUE`, verbatim, never re-deparsed;
  2. after each recorded execution that printed something: its output as `#> ` lines, at most 12 lines of 76 characters, then `#> ... (N more lines)`;
  3. `## ` lines for rationale and decisions (`## Decision: ...`);
  4. artifacts referenced by path: `#> [plot] .gptr/artifacts/7f3a21/plot-1.png`, `#> [app] .gptr/artifacts/marker-explorer/app.R`.

  Failed executions are not recorded as code. Optionally they appear as `## (failed, not replayed): <first line>`.
- **Indentation**: the block takes the indentation of the calling statement's first line.
- **Ownership**: blocks belong to the statement ending at line `L` if they form a run starting at the first non-blank line after `L`, with only blank lines between consecutive blocks. The k-th call of a statement owns the block whose header `prompt=` matches. Otherwise it owns the block with `call=k` (then **stale**). Otherwise it owns none, and a new block is inserted after the owned blocks with smaller `call`.
- **Only top-level calls are recorded.** A call nested in `function`, `\(x)`, `for`, `while`, `repeat`, `if` or `{}` is never given a block (detected with `getParseData()`). A call **inside** an agent block (agent code calling gptr) is never recorded either.

Example (VERIFIED output of the prototype):

```r
gptr("step one") |> gptr("step two")
# >>> gptr:7214c2 model=stub/fake-1 date=2026-09-29 prompt=52831d1d544e
n_stepone <- nchar("step one")
n_stepone * 2
#> [1] 16
## Decision: doubled the count because the stub says so.
# <<< gptr:7214c2
# >>> gptr:3f96ef model=stub/fake-1 date=2026-09-29 prompt=078c44630410 call=2
n_steptwo <- nchar("step two")
n_steptwo * 2
#> [1] 16
## Decision: doubled the count because the stub says so.
# <<< gptr:3f96ef
```

### 3.2 Agent chunk in `.Rmd` / `.qmd`

````
```{r ask}                       <- user chunk containing gptr("...")
x <- 1
gptr("count letters in this prompt")
```

```{r gptr-3fdfa0}               <- .Rmd style: label in the header
# >>> gptr:3fdfa0 model=... prompt=3848b6ef5cca
n <- nchar("count letters in this prompt")
n * 2
## Decision: stub.
# <<< gptr:3fdfa0
```
````

- `.qmd` style: the header is `{r}` followed by `#| label: gptr-9fbc33`.
- Rules:
  - The fence copies the fence and prefix of the owning chunk.
  - The chunk goes directly after the owning chunk, separated by one blank line.
  - Multiple agent chunks for one chunk form a run.
  - Ownership: the chunk labels match `^gptr-` and the block header `prompt=` matches.
- The prototype's chunk headers carry only `model=` and `prompt=`. Real headers must also carry the keys that §3.1 marks required (`date=`).
- **Omit `#>` outputs inside chunks.** knitr renders real output, so recorded `#>` lines appear twice (VERIFIED in the knitted `report.md`). Keep `##` decisions.
- Optional prose answer after the agent chunk, wrapped so it can be rewritten:

  ```
  <!-- gptr:3fdfa0 answer -->
  ...markdown...
  <!-- /gptr:3fdfa0 -->
  ```

### 3.3 Agent cell in `.ipynb`

```json
{
 "cell_type": "code",
 "execution_count": null,
 "id": "gptr-7f3a21",
 "metadata": {
  "gptr": {
   "id": "7f3a21",
   "model": "anthropic/claude-sonnet-5-5",
   "prompt": "0f1e2d3c4b5a"
  }
 },
 "outputs": [],
 "source": [
  "mean(x$mpg)\n",
  "## Decision: arithmetic mean; no outliers removed."
 ]
}
```

- Inserted right after the cell whose source contains the call.
- Keys appear in sorted order.
- On rewrite, only `source` and `metadata.gptr` change. `outputs` and `execution_count` are preserved.
- The file is serialised as in §5.3, with the indent copied from the file (Jupyter uses 1 space).

### 3.4 Console transcript (`.R`)

```r
# gptr session 20260929T183000_7c1e2f -- started 2026-09-29 18:53:44
# machine log: .gptr/sessions/20260929T183000_7c1e2f.jsonl
# source() this file to replay the recorded code without calling a model;
# options(gptr.replay = "live") re-asks the model.
library(gptr)

gptr("fit mpg on weight")
# >>> gptr:a1b2c3 model=stub/fake-1 prompt=be76e50bf356 tokens=1520/210
fit <- lm(mpg ~ wt, data = mtcars)
round(coef(fit), 3)
#> (Intercept)          wt 
#>      37.285      -5.344 
## Decision: plain OLS; the residual plot showed no strong curvature.
# <<< gptr:a1b2c3

# direct R (! prefix, no model)
summary(fit)$r.squared
#> [1] 0.7528328
```

- Append-only.
- LF line endings, UTF-8, no BOM.
- Slash commands are recorded as comments (`# /model opus`), not as code.
- File name: `format(Sys.time(), "gptr-session-%Y%m%d-%H%M.R")`.

### 3.5 Cache files

- Path: `<root>/.gptr/cache/<kind>/<first 2 hex>/<sha256>.json`. `kind` is `s1` (System One decisions) or `s2` (System Two answers).
- **S1 key**: `cli::hash_sha256(canonical_json(list(schema = 1, endpoint, model, question, type, choices, instructions, input)))`. `canonical_json` sorts object keys recursively and uses `jsonlite::toJSON(auto_unbox = TRUE, digits = NA, null = "null")`. The key is vectorised per input element. Two verifier additions:
  - Sort with `order(names(v), method = "radix")`, which is C-locale byte order. The prototype's plain `order()` depends on the collation locale: `c("b","B","a","_z","Z")` sorts as `_z a b B Z` under en_US but `B Z _z a b` under C. Keys of named inputs, such as column names, would then hash differently on different machines.
  - `digits = NA` means 15 significant digits, so numeric inputs that differ only beyond 15 digits share a key. Use `digits = I(17)` if that matters.
- **S1 value** (VERIFIED file):

  ```json
  {"key": "...", "model": "...", "question": "...", "input_sha256": "...",
   "answer": false, "prob": 0.08, "date": "2026-09-29",
   "usage": {"input_tokens": 120, "output_tokens": 3}}
  ```

  The raw input is **not** stored (only its hash), so committed caches do not leak data.
- **S2 value** (recommended):

  ```json
  {"block": "7f3a21", "doc": "analysis.R", "prompt": "<12hex>", "model": "...",
   "answer": "<final assistant text>", "usage": {...}, "cost": 0.042,
   "session": "20260929T183000_7c1e2f", "date": "2026-09-29"}
  ```

  Key: `sha256(canonical_json(list(schema = 1, doc = <path relative to root>, block = id, prompt = hash)))`.

### 3.6 JSONL bookkeeping (Pi v3 `custom` entries)

```json
{"type":"custom","id":"k9l0m1n2","parentId":"...","timestamp":"2026-09-29T18:31:02.000Z",
 "customType":"gptr.doc_block",
 "data":{"doc":"analysis.R","format":"r","block":"7f3a21","action":"insert|replace|stale-regenerate",
         "prompt":"edaab5501df3","sha":"91c2e0a4","lines":[12,18],"backend":"file|rstudio|vscode|positron|deferred"}}
{"type":"custom",...,"customType":"gptr.replay","data":{"doc":"analysis.R","block":"7f3a21","mode":"replay"}}
```

### 3.7 Workspace tree

```
<project>/
  .gptr/
    vignette.Rmd        project instructions (REQ-27) -- commit
    settings.json       project settings -- commit, trust-gated
    mcp.json            project MCP servers -- commit, trust-gated (tracks 05/06)
    SYSTEM.md           optional full system-prompt replacement -- trust-gated (Pi parity)
    APPEND_SYSTEM.md    optional addendum -- trust-gated
    skills/<name>/SKILL.md
    extensions/<name>.R                 trust-gated
    agents/<name>.md                    sub-agent definitions (front matter: model, tools, skills)
    prompts/<name>.md                   prompt templates / slash commands
    sessions/<ts>_<id>.jsonl            exact-resume trees (+ .inbox.jsonl) -- gitignored
    transcripts/gptr-session-*.R        console transcripts in package projects
    cache/s1/..  cache/s2/..            replay caches -- commit by default
    cache/tmp/                          spill files, rendered-vignette cache -- gitignored
    artifacts/<name>/app.R + snapshot/  Shiny artifacts -- snapshot gitignored
    locks/                              advisory locks -- gitignored
    .gitignore
```

- `.gptr/.gitignore` (VERIFIED written by the prototype): `sessions/`, `cache/tmp/`, `artifacts/*/snapshot/`, `*.lock`, `*.tmp`.
- `.Rbuildignore` line for package projects: `^\.gptr$` (VERIFIED appended idempotently, respecting a missing final newline).
- User level, following D-10 and CRAN's `R_user_dir` rule:
  - `tools::R_user_dir("gptr", "config")`: `settings.json`, `AGENTS.md`, `skills/`, `extensions/`, `agents/`, `prompts/`, `mcp.json`, `trust.json`;
  - `tools::R_user_dir("gptr", "data")`: `sessions/--<encoded cwd>--/*.jsonl`, only for sessions without a project workspace and only with consent;
  - `tools::R_user_dir("gptr", "cache")`: model catalogue and similar.
  - Answers are **not** cached at user level.

### 3.8 Settings keys for this layer (`.gptr/settings.json`)

```json
{
  "version": 1,
  "record": "auto",          // "auto" | "ask" | "off"   -- may gptr write into documents?
  "replay": "auto",          // "auto" | "replay" | "live" | "record"
  "replay_key": ["prompt"],  // add "model", "context" for strict invalidation
  "transcript": "ask",       // "ask" | "file" | "active-document" | "off"
  "transcript_format": "R",  // "R" | "Rmd" | "qmd"
  "doc_outputs": true,       // write "#>" comments in .R documents
  "doc_notes": "##",         // "##" | "#'" (spin prose)
  "output_lines": 12,
  "vignette": "raw",         // "raw" | "rendered" (rendered only in trusted projects; cached by hash)
  "notebook_write": false    // allow writing .ipynb on disk (headless runs only)
}
```

The comments above are for this report only; the real file is plain JSON. Options and environment variables override the file: `options(gptr.replay =, gptr.record =, gptr.cache_dir =)` and `GPTR_REPLAY`.

### 3.9 Environment, options and APIs used for detection

| Signal | Value | Source |
|---|---|---|
| `getOption("keep.source")` | `interactive()` by default | VERIFIED |
| `getOption("knitr.in.progress")` | `TRUE` while knitting | VERIFIED |
| `knitr::current_input(dir = TRUE)` | absolute input path (Quarto: `*.rmarkdown` intermediate) | VERIFIED |
| `knitr::opts_current$get("label")`, `$get("code")`, `$get("params.src")` | chunk label, code lines, header | VERIFIED |
| `knitr::opts_knit$get("quarto.version")` | non-NULL under Quarto | VERIFIED |
| `QUARTO_DOCUMENT_PATH`, `QUARTO_DOCUMENT_FILE`, `QUARTO_EXECUTE_INFO`, `QUARTO_PROJECT_DIR` | dir, file name, JSON path, project | VERIFIED |
| `commandArgs(FALSE)` containing `--file=<path>` | Rscript / `R -f` (and Quarto's `rmd.R`!) | VERIFIED |
| `RSTUDIO=1`, `.Platform$GUI == "RStudio"` | RStudio | rstudioapi source (VERIFIED) |
| `POSITRON=1`, `.Platform$GUI == "Positron"`, `POSITRON_VERSION`, `POSITRON_MODE` | Positron | ark source (VERIFIED) |
| `TERM_PROGRAM=vscode`, `SESS_RSTUDIOAPI` | VS Code (+ sess) | vscode-R source (VERIFIED) |
| `getOption("jupyter.in_kernel")`, `JPY_SESSION_NAME` | IRkernel; notebook path | IRkernel 1.3.2, jupyter_server (VERIFIED) |

rstudioapi signatures (VERIFIED, rstudioapi 0.18.0):

```r
getSourceEditorContext(id = NULL); getActiveDocumentContext(); getConsoleEditorContext()
insertText(location = NULL, text = NULL, id = NULL); modifyRange(location = NULL, text = NULL, id = NULL)
setDocumentContents(text, id = NULL); setCursorPosition(position, id = NULL); setSelectionRanges(ranges, id = NULL)
documentId(allowConsole = TRUE); documentPath(id = NULL); documentSave(id = NULL); documentSaveAll()
documentNew(text, type = "r", position = document_position(0, 0), execute = FALSE)
documentOpen(path, line = -1L, col = -1L, moveCursor = TRUE); documentClose(id = NULL, save = TRUE)
document_position(row, column); document_range(start, end = NULL); isAvailable(version_needed = NULL, child_ok = FALSE); hasFun(name, version_needed = NULL, ...)
```

---

## 4. Recommended design for gptr

### 4.1 Components

```
R/doc-locate.R     doc_locate()                      where is the calling gptr() (§4.2)
R/doc-scan.R       doc_scan_calls(), doc_stmt_by_expr(), doc_calls_outside_blocks()
R/doc-blocks.R     doc_find_blocks(), doc_owned_block(), doc_render_block(), doc_upsert_block(),
                   doc_remove_block(), prompt_hash(), new_block_id(), format_output()
R/doc-io.R         doc_read(), doc_write() (atomic, md5-checked, EOL/BOM-preserving), doc_lock()
R/doc-rmd.R        rmd_chunks(), rmd_scan_calls(), rmd_owned_block(), rmd_upsert_chunk(), rmd_append_chunk()
R/doc-ipynb.R      nb_read(), nb_write(), json_write(), nb_find_call_cell(), nb_upsert_cell()
R/doc-ide.R        ide_kind(), ide_context(), ide_insert_lines_edit(), ide_replace_lines_edit(), ide_apply()
R/doc-backend.R    doc_backend(location) -> "file" | "file_deferred" | "ide" | "notebook_output" | "none"
R/replay.R         replay_mode(), replay_decide(), cache_get()/cache_put(), s1 cache
R/transcript.R     transcript_open()/transcript_append()/turn formatters
R/workspace.R      gptr_init(), gptr_find_root(), load_context_files(), vignette_as_instructions()
R/knitr.R          knit_print.gptr_result, opts_hooks skip, document-hook cleanup, eng_gptr
```

Exported, all under the `gptr_` prefix (D-28):

```r
gptr_init(path = ".", quiet = FALSE)                    # create .gptr/ (+ .Rbuildignore line in package projects)
gptr_doc(path)                                          # get/set the document this session records into;
                                                        # gptr_doc(FALSE) disables recording
gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)
gptr_blocks(path = gptr_doc())                          # data.frame: id, lines, model, date, status (fresh/stale/edited/orphan)
gptr_cache(action = c("info", "prune", "clear"), kind = c("s1", "s2"), older_than = NULL)
```

Model-visible surface (keeps D-03 minimal):
- The `r` tool gains `record` (boolean, default `true`: "set false for exploratory inspection that does not change state") and `note` (string: "one-line rationale recorded as a comment").
- The agent rewrites earlier blocks with the normal `edit` tool on the document path. The harness routes the write through the right backend (§4.3) and refreshes the header (`date`, `sha`).

### 4.2 Location algorithm (called at the start of `gptr()`, after forcing `...`)

```
doc_locate(call = sys.call(), prompt, calls = sys.calls()):
 0. strip attributes from `call` for identity tests: attributes(call0 <- call) <- NULL
 1. srcref candidates: attr(call, "srcref"), then each call in rev(calls)
      accept if srcfile$isFile && file exists && basename != ".active-rstudio-document"
             && the srcref's text (srcfile$lines[sr[7]:sr[8]]) contains a gptr() call with this prompt
             (or a call identical() to call0 when the prompt is dynamic)
      -> kind "srcref": path, stmt = c(sr[7], sr[8]), lines_at_parse = srcfile$lines
 2. source frames: for frames whose call head is source/sys.source (newest first):
      ofile (source) or file (sys.source), exprs, i  ->  kind "source_frame":
      target = exprs[[i]], occurrence = #identical among exprs[1:i]
 3. knitr.in.progress: kind "quarto" (if QUARTO_DOCUMENT_FILE non-empty) else "knitr";
      path from QUARTO_DOCUMENT_PATH/FILE or knitr::current_input(dir = TRUE); label, chunk code
 4. QUARTO_DOCUMENT_FILE set but knitr not in progress: kind "quarto_jupyter"
 5. jupyter.in_kernel: kind "jupyter": path JPY_SESSION_NAME or content search in getwd()
 6. !interactive() && "--file=" in commandArgs(FALSE): kind "rscript", defer_writes = TRUE
 7. IDE (rstudioapi::isAvailable() && hasFun("getSourceEditorContext")):
      ctx <- getSourceEditorContext(); if documentId(allowConsole = TRUE) == "#console" and the
      prompt is not found in ctx$contents -> console; else kind "ide" with id, path, contents,
      cursor row, selection range
 8. kind "console"
```

Static matching against the current text (verified in §5.1 and §5.2):
- Exclude calls inside agent blocks.
- With `stmt` + `lines_at_parse`: ordinal among same-prompt calls in the parse-time text, mapped to the same ordinal in the current text.
- With `expr` + `occurrence`: the k-th identical top-level expression outside blocks.
- In the IDE: nearest matching call at or above the cursor row. With a multi-line selection, calls inside the selection in order, using a per-execution counter.
- Rscript: a per-(file, prompt) execution counter.
- Identity key order: `identical(call0, parsed_call)` first (robust for dynamic prompts, VERIFIED), then the prompt literal.
- If the file does not parse (the user is mid-edit), tolerant fallback: find the line containing `encodeString(prompt, quote = '"')`, then grow `parse(text = lines[l1:lk])` until it succeeds to find the statement end.
- If nothing matches: record nothing, write to the transcript instead, and message once.

### 4.3 Write backends and conflict handling

| Location kind | Backend |
|---|---|
| srcref / source_frame / knitr / quarto | `file`: `doc_read()` then `doc_write()` (atomic temp-file rename in the same directory, md5 check, EOL/BOM/final-newline preserved; VERIFIED) |
| rscript | `file_deferred`: keep new lines in memory; one `reg.finalizer(onexit = TRUE)` writes all pending documents at exit (VERIFIED). Also write a sidecar `.gptr/cache/tmp/pending-<sha1(path)>.R` immediately, so a crash (kill -9) loses nothing; apply leftover sidecars at the next `gptr()` start |
| ide (RStudio, VS Code) | if `ctx$path` exists and the buffer equals the disk content (clean), apply the edit through `modifyRange(..., id)` so it is undoable, then `documentSave(id)`; if dirty, apply through the API and leave it unsaved; if untitled, API only |
| ide (Positron) | only if `ctx$id != "#console"` and `ctx$path` is the target: clean buffer means disk write (Positron reloads clean editors, LIKELY); dirty buffer means `insertText(location, text, id = NULL)` (active editor) after re-checking the context; else ask the user to save |
| jupyter | `notebook_output`: print the generated code as a markdown code block in the cell output; opt-in `set_next_input` payload (UNCERTAIN); `.ipynb` disk writes only when `notebook_write = TRUE` (headless runs) |
| console | transcript file (append) after consent; else only JSONL |

- **Concurrency.** Hold an advisory lock per document while reading and writing. Use `filelock::lock()` if installed. Otherwise use the atomic `dir.create()` lock-directory trick in `.gptr/locks/<sha1(path)>` (or `tempdir()` without a workspace), with a stale-lock timeout of 30 s.
- On an md5 mismatch, re-read, **re-locate by content** (never by old line numbers) and re-apply. All operations are anchored by call identity and block id, so they are safe to re-apply. After three failures, record into the transcript/JSONL and warn.
- After inserting or regenerating in an IDE, call `setCursorPosition(document_position(block_end + 1, 1), id)` where supported, so the user's next Ctrl+Enter does not re-run code the agent already executed.
- Range arithmetic for the API: `ide_insert_lines_edit(after, lines, n)` gives `location = c(after + 1, 1)` and `text = paste0(lines, "\n")`, or `c(n, Inf)` with a leading `"\n"` at end of file. `ide_replace_lines_edit(from, to, lines, n)` gives `c(from, 1, to + 1, 1)`, or `c(from, 1, to, Inf)` at end of file. This was VERIFIED equal to the vector implementation using a mock of rstudioapi range semantics, not in a real IDE.

### 4.4 Replay semantics

#### 4.4.1 Invariant

`gptr()` never executes a recorded block. In replay, `gptr()` returns immediately with zero tokens, and the document's own code (the block or agent chunk) runs next as ordinary R. A script with blocks is therefore runnable even where gptr has no model access, which is the reprex property. Replay returns `gptr_result(text = <cached answer or "(replayed gptr:7f3a21; answer not cached)">, replayed = TRUE, block = id, usage = zero, recorded_usage = <from cache>)`.

#### 4.4.2 Modes

`replay =` argument > `options(gptr.replay)` > `GPTR_REPLAY` env > `settings.json` > `"auto"`.

| block state ↓ / mode → | `auto` (default) | `replay` | `live` | `record` |
|---|---|---|---|---|
| fresh (prompt hash matches) | replay | replay | run model, no write | run model, rewrite in place |
| stale (prompt edited) | regenerate in place* | **error** "stale; run live" | run, no write | regenerate in place* |
| user-edited (`sha` mismatch) | replay (user code wins) | replay | run, no write | interactive: ask; non-interactive: refuse unless `force = TRUE` |
| none | run + insert† | **error** "not recorded" | run, no write | run + insert† |
| console (no document) | run (+ transcript†) | error | run | run (+ transcript†) |

\* "Regenerate in place" depends on the evaluation driver, to avoid running the old block too:
- **IDE line-by-line**: regenerate, rewrite, move the cursor past the block.
- **knitr/Quarto**: regenerate, rewrite, and skip the stale chunk in this pass with the scoped `opts_hooks` label hook, removed by a `knit_hooks` `document` hook. Show the executed code in this chunk's output through `knit_print.gptr_result`.
- **`gptr_source()`**: regenerate, rewrite, and skip the old block's top-level expressions (their line range comes from the pre-run parse).
- **`base::source()` / `Rscript`**: the old block was already parsed and will run, so **downgrade to replay with a warning**: "prompt for block 7f3a21 changed since recording; the recorded code ran. Re-run with gptr_source() or interactively to regenerate." In `record` mode this is an error pointing at `gptr_source()`.

† Writing needs permission (§4.4.4). Without it, the agent still runs, but nothing is written and a one-time message explains how to enable recording.

#### 4.4.3 Defaults by context

- Interactive console or IDE: `auto`. Recording permission is asked once per document with `utils::askYesNo()` and remembered in `settings.json`.
- `source()` interactively: `auto`.
- Non-interactive (`Rscript`, render, Quarto, CI): `auto`, but writes happen only if `.gptr/settings.json` has `"record": "auto"` (consent given at `gptr_init()`). CI can pin `GPTR_REPLAY=replay` to guarantee no model calls, like vcr `none`.
- Package tests and CRAN: tests set `options(gptr.replay = "replay")` and use `tempdir()` projects.
- Jupyter: `auto`; `jupyter.in_kernel` counts as "can ask", because readline works there.

#### 4.4.4 Permission to write

Documents are written only when at least one holds:
- the user called `gptr_init()` or `gptr_doc(path)`;
- they answered yes to the interactive prompt;
- `record = "auto"` is set in `.gptr/settings.json` or by option.

This follows the CRAN confirmation exception (§6). That exception is worded for interactive sessions; §6 has the caveat about non-interactive writes.

#### 4.4.5 Invalidation rules

- **S2 blocks**:
  - the default key is the normalised prompt only, so the code is script-like and stays valid when the model or data change;
  - `replay_key = c("prompt", "model")` also invalidates on model change;
  - `"context"` adds a cheap digest of the attached objects (class, dim, names; not full data);
  - a gptr version change does not invalidate;
  - a user-edited block is protected.
- **S1 decisions**: the key covers everything that changes the answer. Aliases such as `jev-latest` are cached under the alias string, which is reproducible but frozen. `gptr_cache("clear", "s1")` refreshes. Record the physical model if the API returns one (see track 04).
- **Cache schema**: `schema` is inside every key, so bumping it invalidates everything.
- **Pruning** ("actively managed", CRAN): `gptr_cache("prune")` deletes S2 entries whose block no longer exists in any document, S1 entries unused for N days (file mtime touched on hit with `Sys.setFileTime`), and `cache/tmp` older than 7 days.

#### 4.4.6 The designated value in replay

When the call is an assignment (`res <- gptr(...)`, detectable in parse data as `LEFT_ASSIGN`/`EQ_ASSIGN` with the call on the right) and the agent designated a value (D-05), the block ends with an assignment so replay reproduces it:

```r
res <- gptr("Fit the mixed model ...")
# >>> gptr:7f3a21 model=... value=fit
fit <- lme4::lmer(weight ~ diet + (1 | mouse), data = mice)
res$value <- fit
# <<< gptr:7f3a21
```

#### 4.4.7 Pipelines and continuation

Replayed results carry the session id from the block header. If a later call in the pipeline must run live, the conversation is restored from `.gptr/sessions/<id>.jsonl`. If sessions are gitignored or missing, a synthetic history is rebuilt from the document: prompt, block code, and the cached answer text from `cache/s2`.

#### 4.4.8 System One

- Calls inside control flow never write to the document.
- Every element is cached, and only misses are batched to the API (VERIFIED: 1 call for 3 misses, 1 call for 1 new element, 0 calls on replay).
- In `replay` mode a miss is an error.
- Before a workspace exists, the cache is in memory (session scope). `options(gptr.cache_dir)` can point elsewhere.

### 4.5 Interactive transcript (part E)

- **Choosing the target** when `gptr()` starts, or on the first programmatic call from the console:
  1. an explicit `gptr_doc()`;
  2. the IDE's active R/Rmd/qmd document, if the user opts in (asked once and remembered in `settings.json`, `transcript: "active-document"`);
  3. a new transcript at `<root>/gptr-session-YYYYMMDD-HHMM.R` (or `.gptr/transcripts/` in package projects, because top-level non-standard files break `R CMD check`);
  4. none (JSONL only).
- **Per turn:**
  - a user prompt becomes `gptr("<prompt>")` via `encodeString(prompt, quote = '"')`, then the block (successful `record = TRUE` executions, `#>` outputs, `##` notes);
  - `!code` becomes a comment line `# direct R (! prefix, no model)`, the code verbatim, then `#>` output;
  - a model switch shows in the next block's `model=`;
  - `/slash` commands become comments.
- **Append-only** writes (`file(path, "ab")`), so an editor showing the file only sees growth. If the transcript is the IDE's active document with unsaved changes, append through `insertText(Inf, text, id)` instead.
- `.Rmd`/`.qmd` transcripts: each turn is a prompt chunk, an agent chunk, and optionally the assistant's prose in `<!-- gptr:id answer -->` delimiters (`rmd_append_chunk()`, VERIFIED).
- **Replay check** (VERIFIED): the transcript was `source()`d in a fresh process with a stub `gptr` and gave `objects: fit gptr library mtcars` and `r.squared: 0.7528328 pred col: TRUE`.

### 4.6 knitr / Quarto integration (D-27)

1. `gptr()` inside R chunks is the primary interface. It uses the same machinery as `.R`, plus a separate agent chunk.
2. A `knit_print.gptr_result` S3 method, registered lazily in `.onLoad` for `knitr::knit_print`, prints the answer as Markdown (`knitr::asis_output`). In live mode it also prints the code the agent ran, so the first render is complete even though the new agent chunk only runs from the next render on.
3. Stale chunk skipping: a scoped `knitr::opts_hooks$set(label = ...)` that chains any existing label hook and only matches gptr-owned labels, plus `knitr::knit_hooks$set(document = ...)` for cleanup (both VERIFIED).
4. **Optional engine** ```` ```{gptr} ```` (VERIFIED in knitr and Quarto). The chunk text is the prompt, which reads naturally in prose documents, and the chunk options are `gptr()` arguments. Register it with glue's pattern. Decision S-2 (quoted prompts) is about R syntax, and an engine chunk is not R code, so the maintainer should confirm this surface is wanted. **Recommendation: offer it, off by default** (it needs `library(gptr)` in a setup chunk anyway).
5. `quarto preview` and render-on-save re-render when the source changes. A recording write therefore triggers one more render, which replays and writes nothing, so it terminates. Document this.

### 4.7 Jupyter

- Locate: `JPY_SESSION_NAME`, else content match (this.path's method), else `gptr_doc("x.ipynb")`.
- While a notebook is open, never write it:
  - show the code and answer in the output (`IRdisplay`/`repr` in Suggests, or plain `cat` with fences);
  - opt-in `set_next_input` via `sys.frame(1)$kernel$executor$payload` (internal API; `tryCatch`; UNCERTAIN);
  - record the blocks to JSONL, and offer `gptr_notebook_sync("analysis.ipynb")` to apply them with `nb_upsert_cell()` when the notebook is closed or in headless runs (papermill, nbconvert, Quarto's jupyter engine).
- Replay in Jupyter: identical to Rmd. The agent cell after the prompt cell carries `id = "gptr-<id>"` and `metadata.gptr.prompt`.

### 4.8 Project instructions injection (vignette.Rmd, AGENTS.md, CLAUDE.md)

- Order, most general first (as in Pi):
  1. `R_user_dir("gptr","config")/{AGENTS.override.md, AGENTS.md, AGENTS.MD, CLAUDE.md, CLAUDE.MD}` (first found);
  2. the same candidates from the filesystem root down to the cwd;
  3. `<root>/.gptr/vignette.Rmd`, last and most specific.
- Render them in Pi's `project_context` section format (`<project_instructions path="...">`).
- vignette.Rmd is text by default: drop the YAML front matter but keep `title`, drop `<!-- -->` comments (with `(?s)` so they span lines, VERIFIED fix), and keep prose and chunks **verbatim without executing them**.
- `vignette: "rendered"` (opt-in, trusted projects only) knits to Markdown in a clean environment, cached in `.gptr/cache/tmp/vignette-<sha>.md` and invalidated by the file hash.
- **Trust**: context files are read regardless of trust (Pi parity, VERIFIED docs) but are labelled untrusted input in the prompt. Settings, extensions, MCP and SYSTEM files are trust-gated. This is consistent with track 05.
- Open decision for the maintainer: does `vignette.Rmd` *replace* `AGENTS.md`/`CLAUDE.md` in the same project root, or add to them? The recommendation is **additive**, because teams already maintain those files for other agents.

### 4.9 Package choices (Imports vs Suggests)

| Package | Role | Recommendation |
|---|---|---|
| base R: `utils::getParseData`, `tools::md5sum`, `tools::R_user_dir`, `reg.finalizer`, `utils::askYesNo` | core | built in (R ≥ 4.0; recommend Depends R ≥ 4.2 for Windows UTF-8) |
| `jsonlite` | JSON reading, cache files, canonical JSON | **Imports** (already in D-20) |
| `cli` | `hash_sha256` (vectorised, VERIFIED), `hash_obj_sha256(x, serialize_version = 2)`, messages | **Imports** (already in D-20) |
| `rstudioapi` | IDE document API (RStudio, Positron shims, VS Code sess) | **Suggests**, guarded by `requireNamespace` + `isAvailable()` + `hasFun()` |
| `knitr` | engine, hooks, `current_input`, `opts_current` | **Suggests** (loaded when knitting anyway) |
| `yaml` | vignette front matter (title only; a regex fallback suffices) | Suggests |
| `filelock` | cross-process document locks | Suggests (fallback: `dir.create` lock) |
| `IRdisplay`/`repr` | rich Jupyter output | Suggests |
| `this.path` | not needed (techniques reimplemented) | none |
| `digest`, `rlang::hash` | not needed (cli covers hashing) | none |

---

## 5. Verified R prototypes

All code below was run with `Rscript --vanilla` on R 4.4.3 (macOS) unless stated. Files are in `.../scratchpad/work/14/proto/` and `.../work/14/p1/`.

### 5.0 Library code (final versions as run)

#### `proto/gptrdoc.R`: text I/O, scanner, blocks, locator

```r
`%||%` <- function(x, y) if (is.null(x)) y else x

doc_read <- function(path) {
  size <- file.info(path)$size
  raw <- if (size > 0) readBin(path, "raw", n = size) else raw()
  bom <- length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  if (bom) raw <- raw[-(1:3)]
  txt <- rawToChar(raw)
  Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) stop("file is not valid UTF-8: ", path, call. = FALSE)
  eol <- if (grepl("\r\n", txt, fixed = TRUE)) "\r\n" else "\n"
  final_nl <- !nzchar(txt) || endsWith(txt, "\n")
  # strsplit() silently drops trailing empty fields; a sentinel keeps them all
  lines <- if (nzchar(txt)) {
    l <- strsplit(paste0(txt, "\001"), "\r?\n")[[1]]
    l[length(l)] <- sub("\001$", "", l[length(l)])
    if (final_nl) l[-length(l)] else l
  } else character()
  structure(list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    lines = enc2utf8(lines), eol = eol, bom = bom, final_nl = final_nl,
    md5 = unname(tools::md5sum(path)), mtime = file.info(path)$mtime
  ), class = "gptr_doc_text")
}

doc_serialize <- function(lines, eol = "\n", bom = FALSE, final_nl = TRUE) {
  txt <- paste(enc2utf8(lines), collapse = eol)
  if (final_nl && length(lines)) txt <- paste0(txt, eol)
  r <- charToRaw(txt)
  if (bom) r <- c(as.raw(c(0xef, 0xbb, 0xbf)), r)
  r
}

doc_write <- function(doc, lines, check = TRUE) {
  path <- doc$path
  if (check && file.exists(path)) {
    now <- unname(tools::md5sum(path))
    if (!identical(now, doc$md5)) {
      stop("document changed on disk since it was read: ", path,
           " (re-read and re-apply the edit)", call. = FALSE)
    }
  }
  bytes <- doc_serialize(lines, doc$eol, doc$bom, doc$final_nl)
  tmp <- tempfile(pattern = ".gptr-", tmpdir = dirname(path), fileext = ".tmp")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  writeBin(bytes, tmp)
  ok <- file.rename(tmp, path)
  if (!ok) {                     # e.g. Windows file lock: fall back to in-place
    writeBin(bytes, path)
  }
  doc$lines <- lines
  doc$md5 <- unname(tools::md5sum(path))
  doc$mtime <- file.info(path)$mtime
  invisible(doc)
}

doc_scan_calls <- function(lines, fun = "gptr", line_offset = 0L) {
  empty <- data.frame(line1 = integer(), col1 = integer(), line2 = integer(),
                      col2 = integer(), stmt1 = integer(), stmt2 = integer(),
                      nested = logical(), prompt = character(),
                      n_in_stmt = integer(), stringsAsFactors = FALSE)
  exprs <- tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) {
    attr(empty, "parse_error") <- conditionMessage(exprs)
    return(empty)
  }
  pd <- utils::getParseData(exprs, includeText = TRUE)
  if (is.null(pd) || !nrow(pd)) return(empty)
  rownames(pd) <- pd$id
  sym <- pd[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == fun, , drop = FALSE]
  if (!nrow(sym)) return(empty)
  parent_of <- function(id) pd[as.character(id), "parent"]
  out <- lapply(seq_len(nrow(sym)), function(i) {
    fexpr <- parent_of(sym$id[i])
    call_id <- parent_of(fexpr)
    if (any(pd$parent == call_id & pd$token == "NS_GET")) call_id <- parent_of(call_id)
    call <- pd[as.character(call_id), ]
    anc <- call_id; nested <- FALSE; top <- call_id
    repeat {
      p <- parent_of(anc)
      if (is.na(p) || p <= 0) { top <- anc; break }
      kids <- pd$token[pd$parent == p]
      if (any(kids %in% c("FUNCTION", "'\\\\'", "FOR", "WHILE", "REPEAT", "IF", "'{'")))
        nested <- TRUE
      anc <- p
    }
    st <- pd[as.character(top), ]
    args <- pd[pd$parent == call_id & pd$token == "expr", , drop = FALSE]
    prompt <- NA_character_
    for (a in args$id) {
      k <- pd[pd$parent == a, , drop = FALSE]
      if (nrow(k) == 1L && k$token == "STR_CONST") {
        prompt <- eval(str2lang(k$text), baseenv()); break
      }
    }
    data.frame(line1 = call$line1, col1 = call$col1, line2 = call$line2,
               col2 = call$col2, stmt1 = st$line1, stmt2 = st$line2,
               nested = nested, prompt = prompt, n_in_stmt = NA_integer_,
               stringsAsFactors = FALSE)
  })
  res <- do.call(rbind, out)
  res <- res[order(res$line1, res$col1), , drop = FALSE]
  res$line1 <- res$line1 + line_offset; res$line2 <- res$line2 + line_offset
  res$stmt1 <- res$stmt1 + line_offset; res$stmt2 <- res$stmt2 + line_offset
  res$n_in_stmt <- stats::ave(res$line1, res$stmt1, FUN = seq_along)
  rownames(res) <- NULL
  res
}

BLOCK_OPEN  <- "^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$"
BLOCK_CLOSE <- "^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$"

parse_kv <- function(s) {
  if (is.na(s) || !nzchar(trimws(s))) return(list())
  m <- gregexpr('([A-Za-z_][A-Za-z0-9_.]*)=("([^"\\\\]|\\\\.)*"|[^ \t]+)', s, perl = TRUE)
  kv <- regmatches(s, m)[[1]]
  keys <- sub("=.*$", "", kv)
  vals <- sub("^[^=]*=", "", kv)
  q <- startsWith(vals, '"')
  vals[q] <- vapply(vals[q], function(v) eval(str2lang(v), baseenv()), "")
  stats::setNames(as.list(vals), keys)
}
format_kv <- function(x) {
  if (!length(x)) return("")
  v <- vapply(x, function(v) {
    v <- as.character(v)
    if (grepl('[ \t"=]', v) || !nzchar(v)) encodeString(v, quote = '"') else v
  }, "")
  paste0(names(x), "=", v, collapse = " ")
}

doc_find_blocks <- function(lines) {
  o <- regmatches(lines, regexec(BLOCK_OPEN, lines, perl = TRUE))
  c <- regmatches(lines, regexec(BLOCK_CLOSE, lines, perl = TRUE))
  opens <- which(lengths(o) > 0); closes <- which(lengths(c) > 0)
  rows <- list()
  for (i in opens) {
    id <- o[[i]][3]
    j <- closes[closes > i & vapply(c[closes], `[`, "", 3) == id]
    nxt_open <- opens[opens > i]
    if (!length(j)) { warning("unterminated gptr block ", id, " at line ", i); next }
    j <- j[1]
    if (length(nxt_open) && nxt_open[1] < j) {
      warning("nested/overlapping gptr block inside ", id, " at line ", nxt_open[1]); next
    }
    rows[[length(rows) + 1]] <- data.frame(
      id = id, start = i, end = j, indent = o[[i]][2],
      header = I(list(parse_kv(o[[i]][4]))), stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame(id = character(), start = integer(), end = integer(),
                                       indent = character(), header = I(list())))
  res <- do.call(rbind, rows)
  if (anyDuplicated(res$id)) warning("duplicate gptr block ids: ",
                                     paste(unique(res$id[duplicated(res$id)]), collapse = ", "))
  res
}

doc_blocks_after <- function(lines, stmt_end, blocks = doc_find_blocks(lines)) {
  out <- blocks[0, ]
  pos <- stmt_end
  repeat {
    k <- pos + 1L
    while (k <= length(lines) && !nzchar(trimws(lines[k]))) k <- k + 1L
    b <- blocks[blocks$start == k, , drop = FALSE]
    if (!nrow(b)) break
    out <- rbind(out, b); pos <- b$end
  }
  out
}

doc_render_block <- function(id, fields = list(), body = character(), indent = "") {
  head <- paste0(indent, "# >>> gptr:", id,
                 if (length(fields)) paste0(" ", format_kv(fields)) else "")
  body <- ifelse(nzchar(body), paste0(indent, body), body)
  c(head, body, paste0(indent, "# <<< gptr:", id))
}

doc_upsert_block <- function(lines, id, body, fields = list(), after_line = NULL,
                             indent = "") {
  blocks <- doc_find_blocks(lines)
  hit <- blocks[blocks$id == id, , drop = FALSE]
  if (nrow(hit)) {
    new <- doc_render_block(id, fields, body, hit$indent[1])
    return(append(lines[-(hit$start:hit$end)], new, after = hit$start - 1L))
  }
  if (is.null(after_line)) stop("new block needs `after_line`", call. = FALSE)
  append(lines, doc_render_block(id, fields, body, indent), after = after_line)
}

prompt_hash <- function(prompt) {
  p <- gsub("[ \t]*\r?\n[ \t]*", "\n", trimws(enc2utf8(prompt)))
  substr(cli::hash_sha256(p), 1L, 12L)
}

doc_owned_block <- function(lines, hit, ph = prompt_hash(hit$prompt)) {
  run <- doc_blocks_after(lines, hit$stmt2)
  k <- hit$n_in_stmt
  hdr <- function(field) vapply(run$header, function(h) h[[field]] %||% NA_character_, "")
  if (nrow(run)) {
    call_ord <- suppressWarnings(as.integer(hdr("call"))); call_ord[is.na(call_ord)] <- 1L
    exact <- which(hdr("prompt") %in% ph & call_ord == k)
    if (!length(exact)) exact <- which(hdr("prompt") %in% ph)
    if (length(exact)) return(list(block = run[exact[1], ], stale = FALSE))
    same_pos <- which(call_ord == k)
    if (length(same_pos)) return(list(block = run[same_pos[1], ], stale = TRUE))
    before <- which(call_ord < k)
    return(list(block = NULL, stale = FALSE,
                insert_after = if (length(before)) run$end[max(before)] else hit$stmt2))
  }
  list(block = NULL, stale = FALSE, insert_after = hit$stmt2)
}

doc_remove_block <- function(lines, id) {
  b <- doc_find_blocks(lines); b <- b[b$id == id, , drop = FALSE]
  if (!nrow(b)) return(lines)
  lines[-(b$start:b$end)]
}

.id_state <- new.env()
.id_state$counter <- 0L
new_block_id <- function(existing = character(), salt = "", n = 6L) {
  .id_state$counter <- .id_state$counter + 1L
  seed <- paste(format(Sys.time(), "%Y%m%d%H%M%OS6"), Sys.getpid(),
                .id_state$counter, salt, sep = "|")
  repeat {
    h <- cli::hash_sha256(seed)
    id <- substr(h, 1L, n)
    if (!id %in% existing && grepl("[a-f]", id)) return(id)
    seed <- paste0(seed, "+")
  }
}

format_output <- function(x, prefix = "#> ", max_lines = 12L, width = 76L) {
  out <- if (is.character(x) && is.null(attributes(x))) x else
    utils::capture.output(print(x), type = "output")
  out <- unlist(strsplit(out, "\n", fixed = TRUE))
  if (length(out) > max_lines) {
    out <- c(out[seq_len(max_lines)], sprintf("... (%d more lines)", length(out) - max_lines))
  }
  paste0(prefix, substr(out, 1L, width))
}

srcref_file <- function(sr) {
  sf <- attr(sr, "srcfile")
  if (is.null(sf) || !isTRUE(sf$isFile)) return(NULL)
  fn <- sf$filename %||% ""
  if (!nzchar(fn)) return(NULL)
  wd <- sf$wd %||% getwd()
  full <- if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", fn)) path.expand(fn) else file.path(wd, fn)
  if (file.exists(full)) normalizePath(full, winslash = "/") else NULL
}

gptr_where <- function(call = sys.call(-1L), prompt = NA_character_,
                       calls = sys.calls()) {
  cands <- c(list(call), rev(calls))
  for (cl in cands) {
    sr <- attr(cl, "srcref")
    if (is.null(sr)) next
    path <- srcref_file(sr)
    if (is.null(path)) next
    sf <- attr(sr, "srcfile")
    pl <- sf$lines %||% readLines(path, warn = FALSE)
    txt <- pl[sr[7]:sr[8]]
    found <- tryCatch(doc_scan_calls(txt), error = function(e) NULL)
    if (is.null(found) || !nrow(found)) next
    if (!is.na(prompt) && !any(found$prompt %in% prompt)) next
    return(list(kind = "srcref", path = path, stmt = c(sr[7], sr[8]),
                prompt = prompt, lines_at_parse = pl))
  }
  for (k in rev(seq_along(sys.frames()))) {
    e <- sys.frame(k)
    f1 <- tryCatch(deparse(sys.call(k)[[1]])[1], error = function(err) "")
    if (!f1 %in% c("source", "base::source")) next
    ofile <- get0("ofile", envir = e, inherits = FALSE)
    idx <- get0("i", envir = e, inherits = FALSE)
    if (is.character(ofile) && length(ofile) == 1L && file.exists(ofile) && is.numeric(idx)) {
      ex <- get0("exprs", envir = e, inherits = FALSE)
      if (!is.expression(ex) || idx > length(ex)) next
      target <- ex[[idx]]
      k <- sum(vapply(seq_len(idx), function(m) identical(ex[[m]], target), NA))
      return(list(kind = "srcref", via = "source-frame", path = normalizePath(ofile, winslash = "/"),
                  expr = target, occurrence = k, prompt = prompt))
    }
  }
  if (isTRUE(getOption("knitr.in.progress"))) {
    qdir <- Sys.getenv("QUARTO_DOCUMENT_PATH"); qfile <- Sys.getenv("QUARTO_DOCUMENT_FILE")
    path <- if (nzchar(qdir) && nzchar(qfile)) file.path(qdir, qfile) else
      knitr::current_input(dir = TRUE)
    return(list(kind = if (nzchar(qfile)) "quarto" else "knitr",
                path = normalizePath(path, winslash = "/", mustWork = FALSE),
                label = knitr::opts_current$get("label"),
                chunk_code = knitr::opts_current$get("code"), prompt = prompt))
  }
  jpy <- Sys.getenv("JPY_SESSION_NAME")
  if (isTRUE(getOption("jupyter.in_kernel")) || nzchar(jpy)) {
    return(list(kind = "jupyter", path = if (nzchar(jpy)) jpy else NA_character_,
                prompt = prompt))
  }
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa) && !interactive()) {
    f <- sub("^--file=", "", fa[1])
    if (file.exists(f)) return(list(kind = "rscript",
                                    path = normalizePath(f, winslash = "/"),
                                    prompt = prompt, defer_writes = TRUE))
  }
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)) &&
      isTRUE(tryCatch(rstudioapi::hasFun("getSourceEditorContext"), error = function(e) FALSE))) {
    ctx <- tryCatch(rstudioapi::getSourceEditorContext(), error = function(e) NULL)
    if (!is.null(ctx)) return(list(kind = "ide", id = ctx$id, path = ctx$path,
                                   contents = ctx$contents,
                                   cursor = ctx$selection[[1]]$range$start[["row"]],
                                   prompt = prompt))
  }
  list(kind = "console", path = NA_character_, prompt = prompt)
}

doc_stmt_by_expr <- function(lines, expr, k = 1L) {
  p_src <- tryCatch(parse(text = lines, keep.source = TRUE), error = function(e) NULL)
  if (is.null(p_src)) return(NULL)
  p_val <- parse(text = lines, keep.source = FALSE)
  srs <- attr(p_src, "srcref")
  b <- doc_find_blocks(lines)
  inside <- vapply(srs, function(sr) any(sr[1] >= b$start & sr[3] <= b$end), NA)
  hits <- which(!inside & vapply(seq_along(p_val), function(j) identical(p_val[[j]], expr), NA))
  if (length(hits) < k) return(NULL)
  sr <- srs[[hits[k]]]
  c(sr[1], sr[3])
}

doc_calls_outside_blocks <- function(lines) {
  calls <- doc_scan_calls(lines)
  b <- doc_find_blocks(lines)
  if (nrow(calls) && nrow(b)) {
    inb <- vapply(calls$line1, function(l) any(l >= b$start & l <= b$end), NA)
    calls <- calls[!inb, , drop = FALSE]
  }
  calls
}

doc_match_call <- function(lines, where, ordinal = NULL) {
  cur <- doc_calls_outside_blocks(lines)
  if (!nrow(cur)) return(NULL)
  same_prompt <- function(d) d[!is.na(d$prompt) & d$prompt == where$prompt, , drop = FALSE]
  if (!is.null(where$expr)) where$stmt <- doc_stmt_by_expr(lines, where$expr, where$occurrence)
  if (!is.null(where$expr) && is.null(where$stmt)) return(NULL)
  if (!is.null(where$stmt)) {
    old <- if (!is.null(where$lines_at_parse)) doc_calls_outside_blocks(where$lines_at_parse) else cur
    in_stmt <- old[old$line1 >= where$stmt[1] & old$line2 <= where$stmt[2], , drop = FALSE]
    if (!nrow(in_stmt))
      in_stmt <- old[old$stmt1 <= where$stmt[1] & old$stmt2 >= where$stmt[2], , drop = FALSE]
    if (!is.na(where$prompt)) in_stmt <- same_prompt(in_stmt)
    if (!nrow(in_stmt)) return(NULL)
    t <- in_stmt[1, ]
    so <- same_prompt(old)
    j <- which(so$line1 == t$line1 & so$col1 == t$col1)
    sc <- same_prompt(cur)
    if (length(j) == 1L && j <= nrow(sc)) return(sc[j, ])
    return(NULL)
  }
  hit <- same_prompt(cur)
  if (!nrow(hit)) return(NULL)
  if (!is.null(where$cursor)) {
    above <- hit[hit$line1 <= where$cursor, , drop = FALSE]
    if (nrow(above)) return(above[nrow(above), ])
  }
  if (!is.null(ordinal) && ordinal <= nrow(hit)) return(hit[ordinal, ])
  hit[1, ]
}
```

#### `proto/stub_gptr.R`: a fake `gptr()` that drives the document layer (no model)

```r
.stub <- new.env()
.stub$ordinal <- list()      # per file+prompt execution counter (Rscript path)
.stub$pending <- list()      # deferred writes (Rscript path)

gptr <- function(...) {
  args <- list(...)                               # forces pipeline inputs first
  prompt <- NA_character_
  for (a in args) if (is.character(a) && length(a) == 1L) { prompt <- a; break }
  where <- gptr_where(sys.call(), prompt, sys.calls())
  env <- parent.frame()
  res <- structure(list(prompt = prompt, where = where$kind), class = "gptr_stub_result")
  if (where$kind %in% c("knitr", "quarto")) return(invisible(stub_knitr(where, prompt, env, res)))
  if (!where$kind %in% c("srcref", "rscript")) {
    message("[gptr] no document (", where$kind, "): nothing recorded")
    return(invisible(res))
  }
  path <- where$path
  key <- paste(path, prompt)
  .stub$ordinal[[key]] <- (.stub$ordinal[[key]] %||% 0L) + 1L
  d <- doc_read(path)
  lines <- if (!is.null(.stub$pending[[path]])) .stub$pending[[path]] else d$lines
  hit <- doc_match_call(lines, where, ordinal = .stub$ordinal[[key]])
  if (is.null(hit)) { message("[gptr] call not found in ", basename(path)); return(invisible(res)) }
  if (hit$nested) {
    message("[gptr] call at line ", hit$line1, " is nested (loop/function/if): not recorded")
    return(invisible(res))
  }
  ph <- prompt_hash(prompt)
  own <- doc_owned_block(lines, hit, ph)
  if (!is.null(own$block) && !own$stale) {
    b <- own$block
    message(sprintf("[gptr] replay: block %s (lines %d-%d) exists; not calling a model",
                    b$id, b$start, b$end))
    res$replayed <- b$id
    return(invisible(res))
  }
  if (isTRUE(own$stale)) message("[gptr] block ", own$block$id,
                                 " is stale (prompt edited): regenerating in place")
  var <- paste0("n_", gsub("[^a-z]", "", tolower(substr(prompt, 1, 8))))
  code <- c(sprintf("%s <- nchar(%s)", var, encodeString(prompt, quote = '"')),
            sprintf("%s * 2", var))
  vals <- lapply(code, function(cl) withVisible(eval(str2lang(cl), env)))
  body <- c(code[1], code[2], format_output(vals[[2]]$value),
            "## Decision: doubled the count because the stub says so.")
  existing <- doc_find_blocks(lines)$id
  id <- if (isTRUE(own$stale)) own$block$id else new_block_id(existing, salt = prompt)
  fields <- list(model = "stub/fake-1", date = "2026-09-29", prompt = ph)
  if (hit$n_in_stmt > 1L) fields$call <- hit$n_in_stmt
  new <- doc_upsert_block(lines, id, body, fields, after_line = own$insert_after,
                          indent = sub("^([ \t]*).*$", "\\1", lines[hit$stmt1]))
  if (isTRUE(where$defer_writes)) {
    if (is.null(.stub$pending[[path]])) {
      reg.finalizer(.stub, function(e) {
        for (p in names(e$pending)) {
          d <- doc_read(p); doc_write(d, e$pending[[p]], check = FALSE)
          cat("[gptr] wrote deferred blocks to", basename(p), "at exit\n")
        }
      }, onexit = TRUE)
    }
    .stub$pending[[path]] <- new
    message("[gptr] recorded block ", id, " (deferred until exit)")
  } else {
    doc_write(d, new)
    message("[gptr] recorded block ", id, " after line ", hit$stmt2, " of ", basename(path))
  }
  res$recorded <- id
  invisible(res)
}

stub_knitr <- function(where, prompt, env, res) {
  path <- where$path
  d <- doc_read(path); lines <- d$lines
  calls <- rmd_scan_calls(lines)
  calls <- calls[!is.na(calls$prompt) & calls$prompt == prompt, , drop = FALSE]
  if (!is.null(where$label) && any(calls$label %in% where$label))
    calls <- calls[calls$label %in% where$label, , drop = FALSE]
  if (!nrow(calls)) { message("[gptr] call not found in ", basename(path)); return(res) }
  hit <- calls[1, ]
  if (hit$nested) { message("[gptr] nested call: not recorded"); return(res) }
  own <- rmd_owned_block(lines, hit$chunk, hit)
  if (!is.null(own$block)) {
    message("[gptr] replay: chunk gptr-", own$block$id, " exists; not calling a model")
    res$replayed <- own$block$id
    return(res)
  }
  code <- c(sprintf("n <- nchar(%s)", encodeString(prompt, quote = '"')), "n * 2")
  vals <- lapply(code, function(cl) withVisible(eval(str2lang(cl), env)))
  body <- c(code, format_output(vals[[2]]$value), "## Decision: stub.")
  id <- new_block_id(doc_find_blocks(lines)$id, salt = prompt)
  style <- if (grepl("[.]qmd$", path, ignore.case = TRUE)) "qmd" else "rmd"
  new <- rmd_upsert_chunk(lines, hit$chunk, id, body,
                          list(model = "stub/fake-1", prompt = prompt_hash(prompt)), style)
  doc_write(d, new)
  message("[gptr] recorded chunk gptr-", id, " after chunk '", hit$label, "' in ", basename(path))
  res$recorded <- id
  res
}
```

#### `proto/ipynb.R`: nbformat 4 read/modify/write

```r
nb_read <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  nb <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (!identical(as.integer(nb$nbformat), 4L)) stop("only nbformat 4 is supported")
  attr(nb, "gptr_md5") <- unname(tools::md5sum(path))
  second <- regmatches(txt, regexpr("\n[ \t]+", txt))
  attr(nb, "gptr_indent") <- if (length(second)) sub("^\n", "", second) else " "
  nb
}

json_escape <- function(s) {
  s <- enc2utf8(s)
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub("\"", "\\\"", s, fixed = TRUE)
  s <- gsub("\n", "\\n", s, fixed = TRUE)
  s <- gsub("\r", "\\r", s, fixed = TRUE)
  s <- gsub("\t", "\\t", s, fixed = TRUE)
  s <- gsub("\b", "\\b", s, fixed = TRUE)
  s <- gsub("\f", "\\f", s, fixed = TRUE)
  ctl <- gregexpr("[\001-\037]", s, perl = TRUE)
  if (any(unlist(ctl) > 0)) {
    regmatches(s, ctl) <- lapply(regmatches(s, ctl), function(ch)
      vapply(ch, function(c) sprintf("\\u%04x", utf8ToInt(c)), ""))
  }
  paste0("\"", s, "\"")
}
json_num <- function(x) {
  # CORRECTED by the verifier (see Verification log). The original 15-or-17-digit
  # formatC() version did not reproduce Python's repr(): 1/3 came out as
  # 0.33333333333333331 (Python: 0.3333333333333333) and 1e15 as 1e+15 (Python:
  # 1000000000000000.0), and its round-trip test used as.numeric(), which is not
  # correctly rounded in R 4.4.3 on macOS arm64 (1744 of 6000 %.17g strings parsed
  # to a different double). This version picks the shortest round-tripping
  # significand, checks it with jsonlite's parser (libc strtod), and applies
  # Python's fixed/scientific switch (fixed iff -4 < decimal-point position <= 16).
  if (is.integer(x)) return(as.character(x))
  if (!is.finite(x)) stop("non-finite number cannot be written as JSON")
  if (x == 0) return(if (1 / x < 0) "-0.0" else "0.0")
  cand <- sprintf(paste0("%.", 0:16, "e"), x)
  back <- unlist(jsonlite::parse_json(paste0("[", paste(cand, collapse = ","), "]")))
  s <- cand[which(back == x)[1L]]
  neg <- startsWith(s, "-")
  digits <- sub("0+$", "", gsub(".", "", sub("e.*$", "", sub("^-", "", s)), fixed = TRUE))
  decpt <- as.integer(sub("^.*e", "", s)) + 1L
  nd <- nchar(digits)
  out <- if (decpt > -4L && decpt <= 16L) {          # fixed: 0.0001, 100000.0
    if (decpt <= 0L) paste0("0.", strrep("0", -decpt), digits)
    else if (decpt >= nd) paste0(digits, strrep("0", decpt - nd), ".0")
    else paste0(substr(digits, 1L, decpt), ".", substr(digits, decpt + 1L, nd))
  } else {                                             # scientific: 1e-05, 1.5e+16
    paste0(substr(digits, 1L, 1L), if (nd > 1L) paste0(".", substr(digits, 2L, nd)),
           "e", sprintf("%+03d", decpt - 1L))
  }
  if (neg) paste0("-", out) else out
}
json_write <- function(x, indent = " ", level = 0L) {
  pad <- strrep(indent, level); pad1 <- strrep(indent, level + 1L)
  if (is.null(x)) return("null")
  if (is.list(x)) {
    nms <- names(x)
    is_obj <- !is.null(nms)
    if (!length(x)) return(if (is_obj) "{}" else "[]")
    items <- vapply(seq_along(x), function(i) json_write(x[[i]], indent, level + 1L), "")
    if (is_obj) items <- paste0(json_escape(nms), ": ", items)
    open <- if (is_obj) "{" else "["; close <- if (is_obj) "}" else "]"
    return(paste0(open, "\n", paste0(pad1, items, collapse = ",\n"), "\n", pad, close))
  }
  if (length(x) != 1L) stop("unexpected vector of length ", length(x))
  if (is.na(x)) return("null")
  if (is.logical(x)) return(if (x) "true" else "false")
  if (is.numeric(x)) return(json_num(x))
  json_escape(as.character(x))
}
nb_to_json <- function(nb, indent = attr(nb, "gptr_indent") %||% " ") {
  attr(nb, "gptr_md5") <- NULL; attr(nb, "gptr_indent") <- NULL
  paste0(json_write(nb, indent), "\n")
}

nb_write <- function(nb, path, check = TRUE) {
  if (check && file.exists(path) && !is.null(attr(nb, "gptr_md5")) &&
      !identical(unname(tools::md5sum(path)), attr(nb, "gptr_md5")))
    stop("notebook changed on disk since it was read", call. = FALSE)
  txt <- nb_to_json(nb)
  tmp <- tempfile(".gptr-", tmpdir = dirname(path), fileext = ".tmp")
  con <- file(tmp, open = "wb"); writeBin(charToRaw(txt), con); close(con)
  if (!file.rename(tmp, path)) { writeBin(charToRaw(txt), path); unlink(tmp) }
  invisible(path)
}

nb_source_split <- function(code) {
  s <- paste(code, collapse = "\n")
  if (!nzchar(s)) return(list())
  parts <- strsplit(paste0(s, "\001"), "\n", fixed = TRUE)[[1]]
  parts[length(parts)] <- sub("\001$", "", parts[length(parts)])
  n <- length(parts)
  out <- paste0(parts, c(rep("\n", n - 1L), ""))
  as.list(out[nzchar(out)])
}
nb_source_text <- function(cell) paste0(unlist(cell$source), collapse = "")
nb_cell_ids <- function(nb) vapply(nb$cells, function(c) c$id %||% NA_character_, "")

nb_code_cell <- function(code, id, gptr_meta = list()) {
  list(cell_type = "code",
       execution_count = NULL,
       id = id,
       metadata = if (length(gptr_meta)) list(gptr = gptr_meta) else structure(list(), names = character()),
       outputs = list(),
       source = nb_source_split(code))
}

nb_find_call_cell <- function(nb, prompt) {
  for (i in seq_along(nb$cells)) {
    c <- nb$cells[[i]]
    if (!identical(c$cell_type, "code")) next
    calls <- tryCatch(doc_scan_calls(strsplit(nb_source_text(c), "\n", fixed = TRUE)[[1]]),
                      error = function(e) NULL)
    if (!is.null(calls) && any(calls$prompt %in% prompt)) return(i)
  }
  NA_integer_
}

nb_upsert_cell <- function(nb, after, code, bid, gptr_meta) {
  cid <- paste0("gptr-", bid)
  ids <- nb_cell_ids(nb)
  cell <- nb_code_cell(code, cid, c(list(id = bid), gptr_meta))
  hit <- match(cid, ids)
  if (!is.na(hit)) {
    old <- nb$cells[[hit]]
    # NB: `x$a <- NULL` would DELETE the key; single-bracket keeps a JSON null
    cell["execution_count"] <- list(old$execution_count)
    cell["outputs"] <- list(old$outputs)
    nb$cells[[hit]] <- cell
  } else {
    nb$cells <- append(nb$cells, list(cell), after = after)
  }
  nb
}
```

#### `proto/rmd.R`: Rmd/qmd chunks

```r
RMD_BEGIN <- "^([\t >]*)(`{3,})\\s*\\{([a-zA-Z0-9_]+)( *[ ,].*)?\\}\\s*$"
RMD_END   <- "^([\t >]*)(`{3,})\\s*$"

rmd_yaml_range <- function(lines) {
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) return(NULL)
  j <- which(grepl("^(---|\\.\\.\\.)\\s*$", lines))[-1]
  if (length(j)) c(1L, j[1]) else NULL
}

rmd_chunks <- function(lines) {
  res <- list(); i <- 1L; n <- length(lines)
  y <- rmd_yaml_range(lines); if (!is.null(y)) i <- y[2] + 1L
  while (i <= n) {
    m <- regmatches(lines[i], regexec(RMD_BEGIN, lines[i]))[[1]]
    if (length(m)) {
      fence <- m[3]; j <- i + 1L
      while (j <= n) {
        e <- regmatches(lines[j], regexec(RMD_END, lines[j]))[[1]]
        if (length(e) && nchar(e[3]) >= nchar(fence)) break
        j <- j + 1L
      }
      params <- trimws(sub("^[ ,]*", "", m[5]))
      body <- if (j - i > 1L) lines[(i + 1L):(j - 1L)] else character()
      label <- rmd_header_label(params)
      yl <- grep("^#\\|\\s*label:\\s*", body, value = TRUE)
      if (length(yl)) label <- trimws(sub("^#\\|\\s*label:\\s*", "", yl[1]))
      res[[length(res) + 1L]] <- data.frame(
        start = i, end = j, engine = m[4], label = label %||% NA_character_,
        prefix = m[2], fence = fence, params = params, stringsAsFactors = FALSE)
      i <- j + 1L
    } else i <- i + 1L
  }
  if (!length(res)) return(data.frame(start = integer(), end = integer(), engine = character(),
                                      label = character(), prefix = character(),
                                      fence = character(), params = character()))
  do.call(rbind, res)
}

rmd_header_label <- function(params) {
  if (!nzchar(params)) return(NULL)
  first <- trimws(strsplit(params, ",", fixed = TRUE)[[1]][1])
  if (grepl("=", first, fixed = TRUE)) {
    m <- regmatches(params, regexec("label\\s*=\\s*['\"]([^'\"]+)['\"]", params))[[1]]
    return(if (length(m)) m[2] else NULL)
  }
  gsub("^['\"]|['\"]$", "", first)
}

rmd_scan_calls <- function(lines, fun = "gptr") {
  ch <- rmd_chunks(lines)
  out <- list()
  for (k in seq_len(nrow(ch))) {
    if (!ch$engine[k] %in% c("r", "R")) next
    if (ch$end[k] - ch$start[k] < 2L) next
    body <- lines[(ch$start[k] + 1L):(ch$end[k] - 1L)]
    calls <- doc_scan_calls(body, fun, line_offset = ch$start[k])
    if (nrow(calls)) { calls$chunk <- k; calls$label <- ch$label[k]; out[[length(out) + 1L]] <- calls }
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

rmd_upsert_chunk <- function(lines, k, id, body, fields = list(),
                             style = c("rmd", "qmd")) {
  style <- match.arg(style)
  blocks <- doc_find_blocks(lines)
  if (id %in% blocks$id) return(doc_upsert_block(lines, id, body, fields))
  ch <- rmd_chunks(lines)[k, ]
  label <- paste0("gptr-", id)
  header <- switch(style,
    rmd = paste0(ch$prefix, ch$fence, "{r ", label, "}"),
    qmd = c(paste0(ch$prefix, ch$fence, "{r}"), paste0(ch$prefix, "#| label: ", label)))
  chunk <- c("", header, paste0(ch$prefix, doc_render_block(id, fields, body)),
             paste0(ch$prefix, ch$fence))
  append(lines, chunk, after = ch$end)
}

rmd_append_chunk <- function(lines, code, label = NULL, style = c("rmd", "qmd")) {
  style <- match.arg(style)
  header <- switch(style,
    rmd = paste0("```{r", if (!is.null(label)) paste0(" ", label), "}"),
    qmd = c("```{r}", if (!is.null(label)) paste0("#| label: ", label)))
  while (length(lines) && !nzchar(trimws(lines[length(lines)]))) lines <- lines[-length(lines)]
  c(lines, "", header, code, "```")
}

rmd_owned_block <- function(lines, k, hit, ph = prompt_hash(hit$prompt)) {
  ch <- rmd_chunks(lines); blocks <- doc_find_blocks(lines)
  run <- blocks[0, ]; last_end <- ch$end[k]; kk <- k + 1L
  while (kk <= nrow(ch) && grepl("^gptr-", ch$label[kk]) &&
         all(!nzchar(trimws(lines[seq_len(ch$start[kk] - last_end - 1L) + last_end])))) {
    b <- blocks[blocks$start > ch$start[kk] & blocks$end < ch$end[kk], , drop = FALSE]
    run <- rbind(run, b); last_end <- ch$end[kk]; kk <- kk + 1L
  }
  hdr <- function(f) vapply(run$header, function(h) h[[f]] %||% NA_character_, "")
  if (nrow(run)) {
    ex <- which(hdr("prompt") %in% ph)
    if (length(ex)) return(list(block = run[ex[1], ], stale = FALSE))
  }
  list(block = NULL, stale = FALSE, chunk = k)
}
```

The remaining library files are in the scratch folder and were run as shown:
- `proto/workspace.R`: `gptr_init`, `add_ignore_line`, `load_context_files`, `vignette_as_instructions`, `render_project_context`, transcript functions.
- `proto/cache.R`: `canonical_json`, `s1_key`, `cache_get/put`, `s1_decide`.
- `proto/ide.R`: `ide_kind`, `ide_insert_lines_edit`, `ide_replace_lines_edit`, `mock_apply_edit`, `ide_apply`.

Their key parts are quoted in §4 and in the tests below.

### 5.1 Prototype 1: find the calling statement in a sourced file and insert a block after it

Test file `proto/analysis_template.R` (copied to `analysis.R`):

```r
x <- 1:3
gptr("count the letters")
res <- gptr(
  "a multi-line
   prompt"
)
x |> gptr("piped prompt")
gptr("step one") |> gptr("step two")
f <- function() gptr("inside a function")
invisible(f())
for (i in 1:2) gptr("in a loop")
if (TRUE) {
  gptr("inside if braces")
}
gptr("count the letters")
cat("script finished\n")
```

`proto/test1_source.R`:

```r
source("gptrdoc.R"); source("stub_gptr.R")
options(keep.source = TRUE)          # what an interactive session has by default
cat("===== FIRST source(): record\n")
source("analysis.R")
m1 <- unname(tools::md5sum("analysis.R"))
cat("===== file after first run\n"); cat(readLines("analysis.R"), sep = "\n")
cat("===== SECOND source(): replay (must not change the file)\n")
source("analysis.R")
m2 <- unname(tools::md5sum("analysis.R"))
cat("md5 unchanged after replay:", identical(m1, m2), "\n")
cat("blocks found:\n"); print(doc_find_blocks(readLines("analysis.R"))[, c("id","start","end")])
```

Observed output of the final run (executed: `Rscript --vanilla test1_source.R`):

```
===== FIRST source(): record
[gptr] recorded block a180fc after line 2 of analysis.R
[gptr] recorded block 8b9221 after line 12 of analysis.R
[gptr] recorded block d9c989 after line 19 of analysis.R
[gptr] recorded block 8f27e4 after line 26 of analysis.R
[gptr] recorded block 626e26 after line 26 of analysis.R
[gptr] call at line 39 is nested (loop/function/if): not recorded
[gptr] call at line 41 is nested (loop/function/if): not recorded
[gptr] call at line 41 is nested (loop/function/if): not recorded
[gptr] call at line 43 is nested (loop/function/if): not recorded
[gptr] recorded block 4bf881 after line 45 of analysis.R
===== SECOND source(): replay (must not change the file)
[gptr] replay: block a180fc (lines 3-8) exists; not calling a model
... (all five top-level blocks replayed; nested calls skipped)
[gptr] replay: block 4bf881 (lines 46-51) exists; not calling a model
md5 unchanged after replay: TRUE
```

The two "count the letters" calls got separate blocks (ordinal matching), and the pipeline got `call=2` on its second block. The file after the first run is the example in §3.1.

Bug found and fixed along the way (VERIFIED). The first version used the srcref directly. For `gptr("step one") |> gptr("step two")`, the inner call reported `call not found in test1_source.R`, because its srcref pointed at the statement `source("analysis.R")` in the driver script. Fixed by accepting a srcref only if its text contains this prompt, otherwise walking up `sys.calls()`.

Variant without srcrefs (`proto/test8_nokeepsource.R`: `Rscript` default `keep.source = FALSE`, then `source()` and `source(echo = TRUE)`):

```
keep.source = FALSE (Rscript default)
[gptr] recorded block 0d8a07 after line 2 of analysis2.R
...
[gptr] recorded block 2c125b after line 45 of analysis2.R
---- second pass (replay)
... replay ... unchanged: TRUE
---- also with echo=TRUE (what the RStudio Source-with-echo button runs)
... replay ... unchanged: TRUE
---- identical to the keep.source=TRUE result modulo ids?
same block structure: TRUE
```

In the verifier's re-run, the call inside `f <- function() gptr(...)`, reached through `invisible(f())`, printed `call not found in analysis2.R` instead of "nested", because the source frame's statement is `invisible(f())`. The outcome is the same: nothing is recorded. The first attempt at this variant read `lines` from the `source()` frame. That variable does not exist when `keep.source = FALSE`, so every call after the first insertion was "not found". The fix was expression identity (`exprs[[i]]`). Separately (`p1/ident.R`), `sys.call()` was shown to be `identical()` to the parsed call: `gptr(x, "piped")`, the inner `gptr("a")`, `gptr(gptr("a"), "b", model = opus)` and `gptr(paste("dyn", x))` each matched exactly one parsed call.

Rscript path (`proto/analysis_rs.R`; executed: `Rscript --vanilla analysis_rs.R`, twice):

```
===== Rscript run 1 (record, deferred)
[gptr] recorded block b9339c (deferred until exit)
[gptr] recorded block f731b3 (deferred until exit)
[gptr] recorded block fd325a (deferred until exit)
[gptr] call at line 23 is nested (loop/function/if): not recorded
[gptr] call at line 23 is nested (loop/function/if): not recorded
[gptr] recorded block f855d6 (deferred until exit)
script finished
[gptr] wrote deferred blocks to analysis_rs.R at exit
exit=0
===== Rscript run 2 (replay)
[gptr] replay: block b9339c (lines 4-9) exists; not calling a model
[1] 34
[gptr] replay: block f731b3 (lines 11-16) exists; not calling a model
[gptr] replay: block fd325a (lines 17-22) exists; not calling a model
[1] 16
[1] 16
...
[gptr] replay: block f855d6 (lines 25-30) exists; not calling a model
[1] 34
script finished
exit=0
file unchanged by replay run
```

In the second run the recorded code itself executed (Rscript auto-prints the `[1] 34` values), which is the invariant of §4.4.1. Scanner edge cases (`proto/test10_scan.R`): `\(x) gptr(...)`, `lapply(..., function(i) gptr(...))`, `{ gptr(...) }` and `while (...) gptr(...)` are nested. `gptr::gptr("ns")` and `res <- gptr("assigned", model = opus)` are top-level. `gptr(paste(...))` gives prompt `NA`.

### 5.2 Prototype 2: update an existing block idempotently (`proto/test2_update.R`)

```
===== (a) user edits a prompt -> stale block regenerated in place, same id
[gptr] block 04e296 is stale (prompt edited): regenerating in place
@@ 18,7 / 18,7 @@
  # <<< gptr:dd4817
< x |> gptr("piped prompt")
> x |> gptr("piped prompt, now counted twice")
< # >>> gptr:04e296 model=stub/fake-1 date=2026-09-29 prompt=7965d05bc571
> # >>> gptr:04e296 model=stub/fake-1 date=2026-09-29 prompt=b09f41c7961e
< n_pipedpr <- nchar("piped prompt")
> n_pipedpr <- nchar("piped prompt, now counted twice")
  n_pipedpr * 2
< #> [1] 24
> #> [1] 62
===== (b) doc_upsert_block idempotency on a fixed id
second upsert identical to first: TRUE
===== (c) CRLF + BOM + no final newline are preserved byte-for-byte
 $ eol     : chr "\r\n"
 $ bom     : logi TRUE
 $ final_nl: logi FALSE
round trip identical bytes: TRUE
[1] "\357\273\277x <- 1"  "gptr(\"hi \303\251t\303\251\")"  "# >>> gptr:abc123 model=m"  "z <- 3"  "# <<< gptr:abc123"  "y <- 2"
===== (d) conflict detection: file changed after read
[1] "document changed on disk since it was read: /private/var/.../file1810151555f3d.R (re-read and re-apply the edit)"
===== (e) block id generation does not touch .Random.seed
aa3959 a490ab ebe029 e35746 8cad79
seed untouched: TRUE
```

IDE range arithmetic (`proto/test9_ide.R`, mock of rstudioapi semantics; **not run in a real IDE**): insert mid-file `location 3 1`, identical TRUE. Insert at EOF, identical TRUE. Replace mid `location 3 1 7 1`, identical TRUE. Replace at EOF, identical TRUE.

### 5.3 Prototype 3: `.ipynb` round trip with minimal diff (`proto/test3_ipynb.R`, `proto/test3b.R`)

The input notebook was written by Python's stdlib `json.dumps(nb, indent=1, sort_keys=True, separators=(",", ": "), ensure_ascii=False) + "\n"`, exactly as nbformat does. It includes non-ASCII text, an emoji, a tab, `</table>`, `null` execution count, `{}`/`[]` and a float `0.5`. Results:

```
== 1. pure round trip (no change): byte identical?
TRUE  (sizes 1500 1500 )
== 2. insert an agent cell after the cell holding gptr("summarise the mpg column")
call cell index: 3
@@ 64,2 / 64,20 @@
     "execution_count": null,
>    "id": "gptr-7f3a21",
>    "metadata": {
>     "gptr": {
>      "id": "7f3a21",
>      "model": "anthropic/claude-sonnet-5-5",
>      "prompt": "0f1e2d3c4b5a"
>     }
>    },
>    "outputs": [],
>    "source": [
>     "mean(x$mpg)\n",
>     "#> [1] 20.09062\n",
>     "## Decision: arithmetic mean; no outliers removed."
>    ]
>   },
>   {
>    "cell_type": "code",
>    "execution_count": null,
     "id": "0badf00d",
== 3. upsert again with the same content -> identical file (idempotent)
TRUE
idempotent upsert leaves bytes identical: TRUE
cell count: 5
(after simulating Jupyter execution of the agent cell, then rewriting its code:)
@@ 82,5 / 82,4 @@
     "source": [
<     "mean(x$mpg)\n",
<     "#> [1] 20.09062\n",
<     "## Decision: arithmetic mean; no outliers removed."
>     "median(x$mpg)\n",
>     "#> [1] 19.2"
     ]
still valid JSON: TRUE
python sort_keys re-serialisation identical to R output: True
```

Two bugs were found during this work (both VERIFIED):
1. Rendering through `jsonlite::toJSON` + `prettify(indent = 1)` changed 33 bytes: `{}` became `{\n\n}` and `</table>` became `<\/table>`.
2. `cell$execution_count <- NULL` deletes the key. Use `cell["execution_count"] <- list(NULL)`.

A third bug was found by the verifier. The fixture above has only the float `0.5`. A second Python-written fixture (`nb/floats.ipynb`) added a `display_data` output with `application/vnd.plotly.v1+json` data `[1/3, 2/3, 0.1+0.7, 1e15, 1e22, 1e-7]` and a cell metadata value `1/3`. With the original `json_num()` the round trip was **not** byte-identical: `0.3333333333333333` became `0.33333333333333331`, and `1000000000000000.0` became `1e+15`. With the corrected `json_num()` now in §5.0, both fixtures round-trip byte-for-byte. The corrected function also matched Python's `json.dumps` on 6,018 test doubles, and tests 1–3 above still pass.

### 5.4 Prototype 4: add a chunk to `.Rmd`/`.qmd` during knit/render, then replay

`rmdtest/report.Rmd` was knitted twice (`knitr::knit`). Pass 1 inserted:

````
```{r gptr-3fdfa0}
# >>> gptr:3fdfa0 model=stub/fake-1 prompt=3848b6ef5cca
n <- nchar("count letters in this prompt")
n * 2
#> [1] 56
## Decision: stub.
# <<< gptr:3fdfa0
```
````

The knitted Markdown from pass 1 shows only `## [gptr] recorded chunk gptr-3fdfa0 after chunk 'ask' in report.Rmd`, so the new chunk did not run. Pass 2 printed `report.Rmd unchanged by replay knit` and `## [gptr] replay: chunk gptr-3fdfa0 exists; not calling a model`, followed by the chunk's code and `## [1] 56`. The four-backtick chunk containing ```` ``` ```` text stayed intact.

`knitr::purl("report.Rmd", documentation = 1)` produced `## ----gptr-3fdfa0----...` followed by the intact marker block. `doc_find_blocks()` on the purled `.R` found `3fdfa0` (lines 11–16), and `doc_scan_calls()` found the prompt call at line 7.

Quarto (`/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto render report.qmd`, version `1.10.18`): pass 1 inserted

````
```{r}
#| label: gptr-9fbc33
# >>> gptr:9fbc33 model=stub/fake-1 prompt=7d371d05f46c
...
```
````

Output showed `QUARTO_DOCUMENT_FILE = report.qmd ; current_input() = report.rmarkdown` and `custom option seen by knitr: abc123 x/y`. Pass 2 printed `report.qmd unchanged by replay render`, with the chunk list `2/7 [setup] … 4/7 [ask] … 6/7 [gptr-9fbc33]`.

Direct chunk operations (`proto/test11_rmd.R`): `rmd_chunks()` found `setup`, `ask`, `gptr-9fbc33`. `rmd_append_chunk(..., label = "turn-2", style = "qmd")` appended a `{r}` chunk with `#| label: turn-2`. Rewriting the block inside `gptr-9fbc33` was idempotent (`TRUE`), the diff touched only header and body lines, and `chunk structure unchanged: TRUE`.

knitr hook experiments (`proto/hooktest/`):
- a `label` opts_hook set in chunk `a` suppressed evaluation of chunk `gptr-abc123` (its code was shown, `STALE BLOCK RAN` never printed), and chunk `c` ran;
- `label hook still set after knit(): TRUE`;
- with a `document` knit hook doing `opts_hooks$delete("label")`: `[document hook ran at end of knit; cleaning up label hook]`, `label hook after knit: TRUE (TRUE = removed)`.

Engine (`proto/engine/eng.Rmd`, `eng.qmd`):

```r
knitr::knit_engines$set(gptr = function(options) {
  prompt <- paste(options$code, collapse = "\n")
  answer <- sprintf("(stub) I would answer: %s [label=%s, model=%s]", prompt, options$label, format(options$model))
  assign("last_prompt", prompt, envir = knitr::knit_global())
  options$comment <- ""
  knitr::engine_output(options, options$code, answer)
})
```

knitr output: `(stub) I would answer: Summarise mtcars: which variables\ncorrelate most with mpg? [label=ask-1, model=anthropic/claude-sonnet-5-5]`, and R saw the prompt. Quarto output: `(stub) answer to: Which variables correlate with mpg? | model option: openai/gpt-5`, with the `#|` lines stripped from the displayed code.

### 5.5 spin compatibility (`proto/spin_test.R`)

`knitr::spin(text = ..., knit = FALSE, format = "qmd")` turned the `#'` lines into prose (`# My analysis`, `Some prose.`). The block, including `# >>> gptr:c82895 ...`, `#> [1] 34`, `## Decision: ...` and `# <<< gptr:c82895`, stayed inside one ```` ```{r} ```` chunk.

### 5.6 Workspace, context files, transcript and cache

- `proto/test5_workspace.R`:
  - `package project: TRUE | created first: TRUE TRUE TRUE | created second: FALSE FALSE FALSE`;
  - `.Rbuildignore` went from `^renv$` (no final newline) to `^renv$` / `^\.gptr$`;
  - tree: `.gitignore agents artifacts cache cache/s1 cache/s2 cache/tmp extensions prompts sessions settings.json skills transcripts vignette.Rmd`;
  - context order `ws` (parent `AGENTS.md`), `mypkg` (`CLAUDE.md`), `.gptr` (`vignette.Rmd`), rendered as `<project_instructions path=...>` blocks, with the vignette's YAML and HTML comment removed after the `(?s)` fix.
- `proto/test6_transcript.R` + `replay_transcript.R`: the transcript in §3.4 was generated. Replay in a fresh process printed `[replay] fit mpg on weight`, `[replay] add predictions to mtcars`, `objects: fit gptr library mtcars`, `r.squared: 0.7528328  pred col: TRUE`.
- `proto/test7_cache.R`:

  ```
  run 1: api calls = 1 | answers = TRUE FALSE TRUE | cached = FALSE FALSE FALSE
  run 2: api calls = 2 | cached = TRUE TRUE TRUE FALSE
  run 3 (replay): answers identical to run 1: TRUE
  run 4 (replay, miss): 1 decision(s) not in the replay cache and mode = 'replay'
  run 5 (question changed -> new keys): api calls = 3
  cache files: 7
  works in if(): decision 1 is TRUE with prob 0.93
  ```

  (The model id `jev-2026-09-01` in this test is a made-up placeholder, not a real Jev id.)

### 5.7 Not run

- No real RStudio, Positron, VS Code or Jupyter session: the rstudioapi calls, Positron shims, `set_next_input` payloads and `JPY_SESSION_NAME` behaviour come from source and docs only.
- No Windows or Linux runs.
- No Quarto jupyter-engine run.
- No real LLM or Jev calls (by design).

---

## 6. CRAN and cross-platform considerations

- **File writes** (CRAN Repository Policy, [policies](https://cran.r-project.org/web/packages/policies.html)):
  - "Packages should not write in the user's home filespace (including clipboards), nor anywhere else on the file system apart from the R session's temporary directory …" and "Limited exceptions may be allowed in interactive sessions if the package obtains confirmation from the user."
  - "packages may store user-specific data, configuration and cache files in their respective user directories obtained from `tools::R_user_dir()`, provided that by default sizes are kept as small as possible and the contents are actively managed."
  - Hence: document writes, `.gptr/` creation and transcripts require explicit user action (`gptr_init()`, `gptr_doc()`) or `askYesNo()` consent. Non-interactive runs never create files unless consent was recorded in `.gptr/settings.json`. Examples and tests use `tempdir()`. `gptr_cache("prune")` provides "active management".
  - Caveat (verifier): the policy's exception is worded for "interactive sessions" only. Writing into a document during a non-interactive run (`Rscript`, render, CI), because consent was stored earlier, goes beyond the literal text. It is defensible because the user explicitly opted in for that project, but it is an interpretation, not policy (UNCERTAIN). CRAN's own checks must never meet a consent file: examples, tests and vignettes must run with `replay`/no-write.
- **RNG**: block ids come from sha256 of time/pid/counter, not `sample()`. VERIFIED: `.Random.seed` was unchanged after generating five ids. The policy has no RNG clause as such. The rule follows from "Packages should not modify the global environment (user's workspace)", which is where `.Random.seed` lives.
- **Global state**: knitr hooks are scoped and removed by the `document` hook. `options()` changes are reverted with `on.exit()`. Registering exit finalizers is a side effect but harmless and only happens when a write is pending.
- **No `:::`**: avoid `knitr:::current_lines()` and `tools:::` internals in package code. The `base::source` frame variables (`ofile`, `exprs`, `i`) and IRkernel's `executor$payload` are undocumented internals reached without `:::`. They must be wrapped in `tryCatch`, validated, and treated as optional; this.path takes the same approach. The policy text is stricter than "no `:::`". It says "`:::` should not be used to access undocumented/internal objects in base packages (nor should other means of access be employed)". Reading `source()`'s local frame variables is arguably such "other means". this.path (on CRAN, 2.8.0) does the same, which shows the practice is tolerated, not that it is permitted. **UNCERTAIN**: keep the source-frame path optional, so gptr degrades to srcref/static matching if CRAN objects.
- **R CMD check in users' packages**: `.gptr` is not in `tools:::.hidden_file_exclusions`, which is `.Renviron .Rprofile .Rproj.user .Rhistory .Rapp.history .tex .log .aux .pdf .png .backups .cvsignore .cproject .directory .dropbox .exrc .gdb.history .gitattributes .gitignore .gitmodules .hgignore .hgtags .htaccess .latex2html-init .project .seed .settings .tm_properties` (VERIFIED). So add `^\.gptr$` to `.Rbuildignore`, and keep transcripts out of the package root.
- **Windows specifics**:
  - **Line endings**: `doc_read()`/`doc_write()` work on raw bytes and preserve CRLF, BOM and missing final newlines (VERIFIED on macOS with a CRLF+BOM file). New gptr files use LF, written in binary mode, so Windows' text-mode `"\n"` → `"\r\n"` translation never applies.
  - **Encoding**: R ≥ 4.2 on Windows uses UTF-8 as the native encoding through UCRT ([R blog](https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/)). With the recommended `Depends: R (>= 4.2.0)`, `parse(text = lines)` on UTF-8-marked lines is safe. On R 4.1 on Windows, `enc2utf8()` and `parse(..., encoding = "UTF-8")` would be needed.
  - **Atomic rename**: `file.rename()` "will overwrite an existing element of 'to'" where permissions allow (R docs), but "renaming a file from a temporary directory to the user's filespace … will often fail". So the temp file is created **in the same directory** as the target. On Windows, antivirus or indexers can briefly lock files: retry `file.rename` up to 3 times with 100 ms sleeps before falling back to an in-place `writeBin()` (UNCERTAIN: not tested on Windows).
  - **Paths**:
    - `normalizePath(winslash = "/")` everywhere;
    - `srcfile$filename` can be relative (join with `srcfile$wd`) or contain backslashes;
    - `commandArgs()` `--file=` values use backslashes;
    - compare paths case-insensitively on Windows and macOS (`tolower()` after normalisation);
    - RStudio's `~/.active-rstudio-document` lives in the Documents folder on Windows.
  - **Rscript.exe** uses the same REPL file reader, so it is LIKELY equally unsafe to rewrite the running script. Defer to exit on all platforms.
  - **No POSIX shell** is used anywhere in this layer.
- **Encoding marks**: mark strings read from disk as UTF-8 (`Encoding<-`) and write with `useBytes = TRUE`/`writeBin`. Header values are ASCII-only by design; non-ASCII prompts appear only as the call's own string literal, which the user wrote.

---

## 7. Risks, pitfalls, open questions

1. **Double execution when regenerating under `base::source()`/`Rscript`.** The recorded block has already been parsed and will run. The design downgrades to replay plus a warning, and routes regeneration through `gptr_source()`, knitr hooks or the IDE. Users running `source()` with `options(gptr.replay = "live")` must understand the warning. The north-star text "Running it with `options(gptr.replay = "live")` asks the model afresh" holds only with `gptr_source()`, a knit, or line-by-line execution.
2. **Positron cannot target a document by id** (`stopifnot(is.null(id))`), and since 2026-09 an id-less `insertText` may hit the console. Prefer disk writes for clean buffers. For dirty buffers, re-check the active context immediately before inserting. Watch ark for id support and gate on `rstudioapi::hasFun()` plus a probe.
3. **Undocumented internals** (`source()`'s `ofile/exprs/i`, IRkernel `executor$payload`, Positron's `source` hook) can change between R, IRkernel and Positron versions. Validate everything and degrade to "transcript only".
4. **User-edited blocks**: the `sha=` header protects them from being overwritten. The user may delete the end marker; `doc_find_blocks()` then warns "unterminated". Policy: never write into a document whose markers are malformed; ask or append to the transcript instead.
5. **Duplicate prompts**: identical prompts on multiple top-level statements are handled by ordinal (VERIFIED). Reordering the statements swaps block association, which is only detectable if the prompt differs. This is acceptable; `gptr_blocks()` can report "orphan" blocks.
6. **Dynamic prompts** (`gptr(paste(...))`): the static prompt is NA, so matching uses expression identity (VERIFIED equal) and the prompt hash is computed from the runtime prompt. Replay is still keyed by the runtime prompt, so a changing data-dependent prompt makes the block stale on every run. Document that recordable prompts should be literals.
7. **Jupyter**: no safe write path to an open notebook. `set_next_input` is deprecated in the protocol (still the only mechanism) and untested from R. `JPY_SESSION_NAME` is stale after renames and absent outside jupyter_server (e.g. VS Code's Jupyter extension: UNCERTAIN).
8. **Quarto jupyter engine** and `quarto preview` loops: untested. Writes during preview trigger one extra render.
9. **`#>` in Rmd**: duplicated output. The design omits them inside chunks; decide whether `.R` output comments also need a size budget per block (proposed 12 lines per recorded execution).
10. **Big notebooks**: `json_write()` is recursive R. It is fine for typical notebooks but slow for 50 MB notebooks with embedded images. A fallback is to splice only the changed cell's text into the original bytes (possible because cells are serialised independently at a known indent). Not implemented.
11. **Numbers in notebooks**: integers beyond 2^31 are read as doubles and would be written as `10000000000.0`. Rare (not produced by Jupyter itself); UNCERTAIN impact. Doubles must be written with Python's shortest-repr rules. The original prototype did not do this, and it rewrote the bytes of untouched Plotly/Vega/widget outputs, producing spurious diffs (fixed in §5.0; see §5.3). Its `as.numeric()` check could also, in principle, accept a 15-digit string that does not round-trip. Its round-trip check must use a correctly rounded parser (jsonlite), not `as.numeric()`.
12. **Committed caches** could contain sensitive S2 answer text. Default: commit `cache/s1` (hashes and probabilities only). For `cache/s2`, the maintainer should decide: the recommendation is committed by default for reproducibility (Quarto `_freeze` precedent), with a documented opt-out.
13. **Open decisions for the maintainer or the design spec:**
    - Should the optional ```` ```{gptr} ```` engine ship (it relaxes S-2 in prose documents only)?
    - Does `vignette.Rmd` add to AGENTS.md/CLAUDE.md or replace them (recommended: add)?
    - Default transcript target: a new file or the active document?
    - Include `model` in the default S2 replay key?
    - Should RStudio edits of an open, clean document be saved automatically (recommended: yes, `documentSave(id)` only if the buffer was clean before the edit)?
14. **Not verified here**:
    - whether RStudio attaches srcrefs to Ctrl+Enter code (believed not);
    - whether Positron attaches file srcrefs to editor-executed code (possibly, given its debugger support);
    - RStudio's silent reload of clean buffers;
    - VS Code's handling of external changes.

    The design does not depend on any of these, because srcrefs are validated and IDE matching is the fallback.

---

## 8. Sources

Local (read-only):
- Pi clone `.../scratchpad/pi` (commit `1b347794`):
  - `packages/coding-agent/src/core/resource-loader.ts` (lines 184–203, 205–270, 1201–1227);
  - `packages/coding-agent/src/core/system-prompt.ts` (lines 72–79, 120–180);
  - `packages/coding-agent/src/config.ts` (lines 532–606);
  - `packages/coding-agent/src/core/settings-manager.ts` (lines 576–603);
  - `packages/coding-agent/docs/configuration.md`, `docs/security.md`, `docs/session-format.md`, `docs/sessions.md`.
- Installed packages (R 4.4.3 library): rstudioapi 0.18.0 (source and Rd), knitr 1.51 (`spin`, `all_patterns`, `parse_params`, `knit` bodies), IRkernel 1.3.2 (`main`, `Kernel`, `Executor` reference classes, `kernelspec/kernel.json`), ellmer 0.4.0 Rd (`contents_record`, `batch_chat`), glue 1.8.1 `.onLoad`, memoise 2.0.1 / cachem 1.1.0 / reprex 2.1.1 (`args`), base R `source`, `sys.source`, `?srcfile`, `?files`, `tools:::.hidden_file_exclusions`.
- Quarto 1.10.18 CLI bundled in `/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto`.

Web (fetched 2026-09-29):
- ark (Positron kernel) R modules: https://github.com/posit-dev/ark/tree/main/crates/ark/src/modules/rstudio (`document-api.R`, `stubs.R`, `rstudioapi.R`, `commands.R`) and https://github.com/posit-dev/ark/tree/main/crates/ark/src/modules/positron (`positron.R`, `init.R`, `frontend-methods.R`, `hooks_source.R`, `editor.R`, `srcref.R`)
- ark PR #1408: https://github.com/posit-dev/ark/pull/1408 (API: https://api.github.com/repos/posit-dev/ark/pulls/1408)
- Positron PR #16063: https://github.com/posit-dev/positron/pull/16063
- Positron docs: https://positron.posit.co/migrate-rstudio-settings-and-extensions.html ; release notes https://positron.posit.co/release-notes/release-2026-03.html ; debugging guide https://github.com/posit-dev/positron-website/blob/main/guide-r-debugging.qmd
- vscode-R: https://github.com/REditorSupport/vscode-R (`sess/R/rstudioapi.R`, `R/profile.R`, `R/install_sess.R`); wiki https://github.com/REditorSupport/vscode-R/wiki/RStudio-addin-support
- btw IDE utilities: https://github.com/posit-dev/btw/blob/main/R/utils-ide.R
- rstudioapi document manipulation: https://rstudio.github.io/rstudioapi/articles/document-manipulation.html
- RStudio issue "file changed on disk": https://github.com/rstudio/rstudio/issues/10504 ; `.active-rstudio-document`: https://forum.posit.co/t/source-active-rstudio-document/65723
- RStudio code sections: https://docs.posit.co/ide/user/ide/guide/code/code-sections.html
- this.path (2.8.0, 2026-04-10): https://cran.r-project.org/web/packages/this.path/readme/README.html ; source https://github.com/cran/this.path/blob/master/R/thispath.R
- jupyter_server session manager: https://github.com/jupyter-server/jupyter_server/blob/main/jupyter_server/services/sessions/sessionmanager.py ; CHANGELOG 2.0.7 entry (#1100)
- Jupyter messaging spec: https://jupyter-client.readthedocs.io/en/latest/messaging.html
- JupyterLab issue on notebook path: https://github.com/jupyterlab/jupyterlab/issues/16282
- nbformat: https://github.com/jupyter/nbformat/blob/main/nbformat/v4/nbjson.py , https://github.com/jupyter/nbformat/blob/main/nbformat/v4/rwbase.py , https://github.com/jupyter/nbformat/blob/main/nbformat/__init__.py , https://github.com/jupyter/nbformat/blob/main/nbformat/v4/nbformat.v4.5.schema.json
- jupytext formats: https://github.com/mwouts/jupytext/blob/main/website/src/content/docs/formats/scripts.md and `.../formats/markdown.md`
- Quarto env vars: https://quarto.org/docs/advanced/environment-vars.html ; freeze/cache: https://quarto.org/docs/projects/code-execution.html
- knitr cache: https://yihui.org/knitr/demo/cache/
- targets `tar_cue`: https://docs.ropensci.org/targets/reference/tar_cue.html
- vcr record modes: https://github.com/ropensci/vcr/blob/main/R/use_cassette.R ; HTTP testing book chapter: https://books.ropensci.org/http-testing/record-modes.html
- httptest2 `with_mock_dir`: https://enpiar.com/httptest2/reference/with_mock_dir.html
- CRAN Repository Policy: https://cran.r-project.org/web/packages/policies.html
- R on Windows UTF-8/UCRT: https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/ ; https://developer.r-project.org/Blog/public/2021/12/07/upcoming-changes-in-r-4.2-on-windows/index.html

---

## Verification log

An independent adversarial check was run on 2026-09-29 against R 4.4.3 (macOS arm64), knitr 1.51, jsonlite 2.0.0, cli 3.6.6, rstudioapi 0.18.0, IRkernel 1.3.2 and Quarto 1.10.18 (RStudio.app). The verifier's scratch files are in `.../scratchpad/work/verify-14/`. Every §5 prototype was re-run with `Rscript --vanilla` **from the code as printed in this report**: the §5.0 code blocks were extracted from this file, and apart from comments they were identical to `work/14/proto/`. Web sources were fetched on the same day.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | `attr(sys.call(), "srcref")` = statement srcref. `srcfilecopy` has `filename` (relative), `wd`, `isFile`, `timestamp`, `lines`. None at the console top level or at the `Rscript` top level (even after `options(keep.source = TRUE)`). Braces give relative lines. A `for` statement gives the whole statement. A non-braced function body gives the function definition. `if {}` gives the inner statement | confirmed | own probe (`verify-14/a/probe.R`, `s1.R`, `s2.R`) under `Rscript` and `R --interactive` |
| 2 | `keep.source` defaults to `interactive()`. srcref layout `c(first_line, first_byte, last_line, last_byte, first_column, last_column, first_parsed, last_parsed)` | confirmed | `?options`, `?srcfile` (Rd_db) |
| 3 | `base::source` internals: `ofile <- file` (deparse line 28), `lines`/`srcfilecopy` only with `keep.source`, `for (i in seq_len(Ne + echo))`, `ei <- exprs[i]`. `sys.source`: `for (i in seq_along(exprs)) eval(exprs[i], envir)` | confirmed | `deparse(base::source)`, `deparse(base::sys.source)` |
| 4 | Locating via the `sys.source()` frame (`file`, `exprs`, `i`) | confirmed, with a note added: the prototype implements only `source()` | own probe `verify-14/a/ss_run.R` |
| 5 | Pipeline inner call has a misleading srcref | confirmed; wording refined (absent, or points into the forcing function's body) | own probe `a/runpipe*.R` |
| 6 | Rewriting a running `Rscript` file gives `unexpected string constant` (small file and the 16 KB file) | confirmed; silent-skip variant added | re-ran `p1/selfmod.R`, rebuilt 16 KB `big16.R`, own tail-comment variant |
| 7 | `reg.finalizer(onexit = TRUE)` runs at normal exit, after `stop()` (exit 1) and after `quit(status = 3, runLast = FALSE)`. The deferred write works. Editing mid-`source()` is safe | confirmed | re-ran `p1/deferred.R`, `fin_err.R`, `fin_quit.R`, `srcmod.R` |
| 8 | `sys.call()` is `identical()` to the parsed call (pipe, nested, dynamic prompt) | confirmed | re-ran `p1/ident.R` |
| 9 | knitr: `knitr.in.progress`, `current_input(dir = TRUE)`, `opts_current$get("label"/"code"/"params.src")`, `unnamed-chunk-1`, `interactive()` FALSE | confirmed | own knit probe `verify-14/k/doc1.Rmd` |
| 10 | Quarto: `QUARTO_DOCUMENT_FILE/PATH`, `QUARTO_EXECUTE_INFO` JSON with `document-path`, `quarto.version`, `current_input()` = `*.rmarkdown`, `--file=.../rmd.R`, call stack | confirmed. **Corrected:** `QUARTO_R` is not set by Quarto (the docs list it under variables Quarto *inspects*); added `QUARTO_ROOT`, `QUARTO_SHARE_PATH`, `QUARTO_DENO` | own `quarto render` probe `verify-14/q/probe.qmd`; quarto.org environment-vars page |
| 11 | knitr `spin()` defaults, chunk regex `rc`, `pipe_comment_start`, `all_patterns$md`, `xfun::csv_options`, `#|` options since knitr 1.35; purl→spin label quirk | confirmed | `args(knitr::spin)`, deparse, knitr NEWS.md (GitHub), own spin run |
| 12 | rstudioapi 0.18.0 signatures, `isAvailable()` body, `.rs.api.` dispatch, `setDocumentContents` = `insertText(document_range(c(1,1), c(Inf,1)))`, version notes (1.1.287, 1.4.843, 2022.06.0), `id` NULL semantics | confirmed (`document_range(start, end = NULL)` has a default `end`) | installed package functions and Rd |
| 13 | RStudio `getActiveDocumentContext()` and console focus | UNCERTAIN upgraded to **LIKELY** (sticky console context) | positron#16063 body and review thread; rstudio#6805 (closed) |
| 14 | ark: `insertText`/`modifyRange`/`documentPath`/`getSourceEditorContext`/`setSelectionRanges`/`documentSave` `stopifnot(is.null(id))`; `.Platform$GUI <- "Positron"`; `body(ns$isAvailable) <- TRUE` hook; `POSITRON_VERSION`/`MODE`/`LONG_VERSION`; source hook `parse(text = annotated, keep.source = TRUE)` | confirmed | raw GitHub `posit-dev/ark` main (`document-api.R`, `positron.R`, `init.R`, `rstudioapi.R`, `hooks_source.R`) |
| 15 | ark#1408 merged 2026-09-18; positron#16063 merged 2026-09-23 with the quoted release note; "sticky" semantics | confirmed. **Corrected** §1 item 7: console targeting comes from positron#16063 (paired with ark#1408), not from ark#1408 alone | GitHub REST API (PR metadata, body, comments) |
| 16 | vscode-R `sess` 3.0.1, `SESS_RSTUDIOAPI`, `patch_rstudioapi()` list, `getVersion <- function() numeric_version("0")`, ids passed to the client, wiki quotes | confirmed; added that `documentId()` ignores `allowConsole` | raw GitHub `sess/R/rstudioapi.R`, `sess/DESCRIPTION`, `R/profile.R`; vscode-R wiki |
| 17 | btw `which_ide()` uses `TERM_PROGRAM == "vscode"` | confirmed; added the check order (POSITRON first) | raw GitHub `posit-dev/btw` `R/utils-ide.R` |
| 18 | IRkernel kernelspec argv `R --slave -e IRkernel::main() --args {connection_file}`; `options(jupyter.in_kernel = TRUE)` in `Kernel$run`, default FALSE; `Executor` `payload` reset and sent, `readline` replaced, `page()` payload; `R --no-echo -e 'interactive()'` is FALSE | confirmed | installed IRkernel 1.3.2 (`kernelspec/kernel.json`, reference-class methods, `jupyter_option_defaults`); shell |
| 19 | `JPY_SESSION_NAME` = `os.path.join(cwd, name)` from `get_kernel_env()`; CHANGELOG 2.0.7 entry; stale after rename | confirmed; staleness upgraded from LIKELY (update_env applies "only after kernel restart") | raw GitHub jupyter_server `sessionmanager.py`, `CHANGELOG.md`; jupyter_client `manager.py` |
| 20 | Messaging spec: `execute_request` fields, payloads "deprecated", `set_next_input` keys and purpose | confirmed | jupyter-client.readthedocs.io messaging page |
| 21 | nbformat 4.5 schema: required keys, `nbformat_minor` ≥ 5, `cell_id` pattern and length 1–64, output types, kernelspec/language_info; writer kwargs; `split_lines`; trailing newline | confirmed. **Corrected:** `strip_transient` also drops `orig_nbformat_minor`; added the `splitlines()` note | raw GitHub nbformat `nbformat.v4.5.schema.json`, `nbjson.py`, `rwbase.py`, `__init__.py` |
| 22 | jsonlite pitfalls (`<\/`, `3.0`→`3`, `prettify` expanding `{}`/`[]`, `fromJSON` num/int/num) | confirmed; added that `digits = NA` means 15 significant digits and that `as.numeric()` is not correctly rounded | own `verify-14/jl.R`, `jparse2.R` |
| 23 | "R serializer reproduces Python `json.dumps`" (§1 item 11, §5.3) | **corrected** (defect): the original `json_num()` gave `0.33333333333333331` for `1/3` and `1e+15` for `1e15`, so a Python-written notebook with Plotly-style floats did not round-trip. The replacement `json_num()` in §5.0 matched Python on 6,018 doubles; all §5.3 tests still pass | own `verify-14/jnum*.R`, `cmp2.py`, `nb/floats.ipynb`, `test_floats.R`, re-run `test3_ipynb.R`/`test3b.R` |
| 24 | `.gptr` not in `tools:::.hidden_file_exclusions` (list as printed); used by `R CMD build` | confirmed | R 4.4.3 `tools` namespace (`.build_packages`, `.check_packages`) |
| 25 | Pi `resource-loader.ts` 184–203 / 205–230 / 232–270 / 1201–1227; `system-prompt.ts` 72–79 / 163–170 / 177; `configuration.md`, `security.md`, `session-format.md` statements | confirmed ("Context-file discovery does not require project trust." is at line 47) | local Pi clone at commit `1b347794` |
| 26 | CRAN policy quotes (home filespace, interactive exception, `R_user_dir` "actively managed") | confirmed. Added caveats: the exception is interactive-only; base internals may not be reached by "other means" either; the RNG rule derives from "should not modify the global environment" | cran.r-project.org policies page (fetched) |
| 27 | Precedents: knitr cache, Quarto freeze and `_freeze` advice, `tar_cue` args and `never`, memoise/cachem defaults, vcr modes, httptest2 `with_mock_dir`, reprex `opt("#>")`, ellmer `batch_chat(chat, prompts, path, wait = TRUE, ignore_hash = FALSE)` and hash sentence | confirmed | yihui.org, quarto.org, docs.ropensci.org, raw GitHub vcr/httptest2, installed memoise 2.0.1/cachem 1.1.0/reprex 2.1.1/ellmer 0.4.0 |
| 28 | glue 1.8.1 `.onLoad` engine registration pattern | confirmed | `glue:::.onLoad` |
| 29 | this.path 2.8.0 (published 2026-04-10); Jupyter search at `thispath.R` 408–470 via `sys.frame(1L)[["kernel"]][["executor"]][["nframe"]]` | confirmed (it also scans non-`.ipynb` files after `*.ipynb`) | CRAN page; raw GitHub `cran/this.path` |
| 30 | RStudio code-section rule; rstudio#10504 dialog text; `file.rename` docs quotes; Positron migration-doc quotes; jupytext quotes | confirmed | docs.posit.co; GitHub API; `?files`; positron.posit.co; raw GitHub jupytext |
| 31 | Prototypes §5.1 (record/replay under `source()`, no-keep.source variant, Rscript deferred), §5.2 (stale regenerate, idempotent upsert, CRLF+BOM, conflict, seed), §5.4 (knitr and Quarto record/replay, purl, chunk ops, hooks, engine), §5.5 spin, §5.6 workspace/transcript/cache, IDE range mock | confirmed; block ids differ run to run (time-seeded), as expected. `test2_update.R` hard-codes the original run's block id `04e296`, so part (b) fails on a fresh run until the actual id is substituted; the library code is fine. Under `keep.source = FALSE` the function-body call reports "not found" rather than "nested" (note added) | re-ran all drivers in `verify-14/` |
| 32 | `prompt_hash()` values (`edaab5501df3`, `52831d1d544e`, `078c44630410`, `3848b6ef5cca`, `be76e50bf356`) and CRLF/whitespace normalisation | confirmed | own run; `shasum -a 256` |
| 33 | S1 cache key canonicalisation | **amended**: plain `order()` is locale-dependent (en_US vs C verified), so use `method = "radix"` | own run under `LC_ALL=en_US.UTF-8` and `LC_ALL=C` |
| 34 | D-20 already lists `jsonlite` and `cli` | confirmed | `dev/spec/01-decision-register.md` |

**Unverifiable here** (left as LIKELY/UNCERTAIN in the text):
- live behaviour in RStudio, Positron, VS Code and Jupyter (API edits, buffer reloads, whether editor-executed code carries srcrefs, `set_next_input` from R);
- `~/.active-rstudio-document` handling;
- the Quarto jupyter engine;
- Windows behaviour (rename retries, `Rscript.exe` incremental reading);
- whether CRAN accepts reading `source()`'s frame locals.
