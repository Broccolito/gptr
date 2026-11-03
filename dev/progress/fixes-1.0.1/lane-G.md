# gptr 1.0.1 fixes, lane G: notebooks, R Markdown, Quarto, replay

Branch `claude/fix-G` from `04dca16a`. 18 findings (3 high, 7 medium, 8 low), each confirmed by an
independent verifier or a live tester. Decisions: D-340..D-343. One fix per commit, test first.

## Fixed

| Finding (severity) | Commit | Test |
|---|---|---|
| Headless Jupyter (nbconvert, papermill, nbclient, Quarto's jupyter engine) hangs on any gptr question: record consent, project trust, approvals (3 high reports of one defect) | `a1044062` (D-340) | test-utils-options.R "a Jupyter request with allow_stdin = false asks nothing, said once (IC-43)" |
| A notebook found by content picks a look-alike copy (`-Copy1`, `nbconvert --output`) and ignores the `gptr_doc()` binding (2 medium) | `38c4a13d` (D-341) | test-doc-locate.R "a kernel without JPY_SESSION_NAME picks the bound notebook, else the one match" |
| R Markdown: a regenerated block's old, unrun chunk is echoed into the report (medium) | `b2c2e476` | test-doc-knitr.R "a stale agent chunk is regenerated during the knit without running the old code" (extended) |
| Console recording into .Rmd/.qmd does not replay: no `library(gptr)`, `!` lines dropped (medium) | `2c63f9f7` (D-342) | test-doc-replay.R "an R Markdown transcript loads gptr and keeps direct R lines as chunks that knit"; test-doc-io.R "transcript lines are appended raw to an .R transcript, as a chunk to Rmd and qmd" |
| System 1 vectors have no Jupyter repr: HTML drops p values and provenance, text/plain carries ANSI (medium) | `cbd85561` | test-doc-knitr.R "System 1 vectors show their probabilities and provenance in a notebook" |
| A fresh System 1 block cannot replay without `.gptr/`, and the error does not say why (medium) | `180b6e58` | test-gptr-config.R "replay_guard() refuses providers that call a remote model, in replay mode only" (extended) |
| Rmd/qmd: an object the agent made works in the calling chunk on the first render and fails on every re-render (medium) | `9cad7cab` (D-343) | test-doc-knitr.R "a calling chunk that uses the block's objects after the call is told so, once" |
| Jupyter shows a System 1 summary twice (low 10 part 2, low 17 part a) | `060d4a81` | test-s1-client.R "a summary the notebook already shows as the block is not said again"; test-doc-jupyter.R "a System 1 block shown in the cell output reports that it was shown" |
| First render fuses a plot and Peter's answer into one paragraph (low) | `3132a044` | test-doc-knitr.R "an answer after a plot the turn drew is its own Markdown paragraph" |
| A replayed report leaves an empty Quarto output div (low 13 part 1; part 2's docs sentence too) | `ccab3d68` | test-doc-knitr.R "sessions knit as their answer, plus the code of a live turn" (extended) |
| A console bound to an .ipynb records nothing and says nothing; `/doc` claims "Recording into" (low) | `e8c69d12` | test-doc-locate.R "a call in no document says once that a bound notebook takes no console turns"; test-console-commands.R "commands of later plans answer when their plan is absent" (extended) |
| `gptr_source()` on an existing .Rmd says "Not an existing .R file" (low) | `113b9fa3` | test-doc-replay.R (the `gptr_source()` argument checks, extended) |
| `gptr_blocks()` listing cuts the date at width 80 (low) | `7f53fdfb` | test-listing-print.R "a block listing at width 80 keeps its date whole and shortens free text first" |
| Export keeps the transcript's replay note (low 16 part a) | `879abfe7` | test-doc-export.R "a console transcript exports like a script, its later turns piping the handle" (extended) |
| Verifier: the replay-time D-343 notice is lost when the render fails (`rmarkdown::render()`, Quarto: `error = FALSE`) (low) | `88eef3ad` (D-343) | test-doc-knitr.R "a calling chunk that uses the block's objects after the call is told so, once" (extended: `error = FALSE`) |
| Verifier: a transcript chunk appended after an unterminated last chunk of an .Rmd/.qmd joins its body (low) | `a2d02cc8` (D-342) | test-doc-io.R "transcript lines are appended raw to an .R transcript, as a chunk to Rmd and qmd" (extended) |
| Verifier: the D-341 lookup decodes and parses every notebook in the folder on each call (low) | `9027f891` (D-341) | test-doc-locate.R "a kernel without JPY_SESSION_NAME picks the bound notebook, else the one match" (extended) |

Notes on the fixes:

- D-340 reads `allow_stdin` from the executor IRkernel 1.3.2 installs as `base::readline()`; only an
  explicit `false` says no, so JupyterLab, VS Code and a kernel without a request keep asking. The
  first time it says no, one notice explains the unattended answers; `options(gptr.interactive =
  FALSE)` in the notebook silences it.
- D-341: several matching notebooks with no binding record and replay nothing (one notice per
  folder), and the call is not taken as a console turn.
- D-342: direct R lines, slash commands and rewind notes become R chunks; `#>` output is left out,
  as agent chunks leave theirs.
- D-343 keeps IC-46 (replay never runs recorded code); the notice names the objects when the block
  is recorded (in the first report) and when it replays. knitr drops a failing chunk's messages
  unless the chunk has `error = TRUE`, so while knitting the replay's notice also goes to stderr,
  where the render's console shows it before "Quitting from ...".
- D-342: a document whose last chunk is unterminated takes no transcript chunk (one notice), as a
  console block's upsert already refused it.
- D-341: a notebook whose bytes lack an ASCII word of the call's strings is skipped before
  `doc_read()` and `nb_parse()`. With twenty 4 MB notebooks (the call in the first), three
  locates took 72 s on `5493f06e` and 4.2 s after (the matching notebook's own decode and parse
  are most of it).
- The `doc.s1_block` service now returns whether it showed the block (contract 7 services row).

## Tests

Follow-up head (after the verifier's three problems): `^(doc-|utils-options$|s1-client$|s1-route$|
gptr-config$|listing-print$|console-commands$|arch-layers$)`: FAIL 0, WARN 2, SKIP 3, PASS 5063 (the
two rewind warnings as before). `^(console-jupyter|console-repl|session-object|s1-|utils-|arch|perm|
trust|egress|gptr-gateway|ui-|knitr|sources)`: FAIL 1, WARN 0, SKIP 1, PASS 5910 (the one failure is
test-utils-paths.R:461, the same on `04dca16a`). Lint clean on the changed files; `document` leaves
no diff.

First pass. Focused filters, all green on the final head: `^utils-options$`, `^doc-` (all document files),
`^(s1-client|s1-route)$`, `^gptr-config$`, `^listing-print$`, `^console-commands$`,
`^arch-layers$`, `^doc-history-display$` (also with `repr` on the library path, which the dev library
lacks: 0 skips). A broad run of `^(doc-|s1-|utils-|listing|arch|gptr-config|console-commands|
console-jupyter|console-repl|session-object|gptr-gateway)`: FAIL 1, WARN 2, SKIP 4, PASS 8017. The one
failure (test-utils-paths.R:461, `ckpt_files_sync()`) and the two rewind warnings ("automatic scan
incomplete") fail the same way on `04dca16a` here (the file-checkpoint worker), as does
test-ckpt-rewind.R (34 failures on both); they are not lane G code. Lint is clean on every changed
file; `document` regenerated `man/gptr_blocks.Rd` and `man/gptr_doc.Rd` only;
`dev/release/precompute.R script-as-history` regenerated the vignette (its "wrote outside the session
temp directory" note is the same on `04dca16a`).

Live check (offline fake provider, isolated HOME and user dirs, the venv's Jupyter with IRkernel
1.3.2, this branch installed into a scratch library):

- `jupyter nbconvert --execute` of a `library(gptr)` / `peter("hi", model = gptr_fake_provider(...))`
  notebook finished in 2.8 s with the D-340 notice; before, it hung until the cell timeout.
- The same with `nb-executed.ipynb` beside it: the D-341 notice naming both notebooks, no question.
- A bound `nb.ipynb` beside `notebook-Copy1.ipynb` and `nb-Copy1.ipynb`, with a System 1 cell: the
  summary showed once (the pending block), the decision's HTML repr showed the p values and the
  footer, and `gptr_doc("nb.ipynb", sync = TRUE)` from another R process wrote 2 blocks into
  `nb.ipynb` only (the copies' md5 unchanged).
- A client that serves stdin (jupyter_client with `allow_stdin=True`) still got
  "Record gptr blocks into nb.ipynb? [y/N]".

## Deferred

- Low 10 part 1 (knitr auto-prints a System 1 vector as its one-line summary only): deliberate in
  plan P15 Task 16 and asserted by test-doc-knitr.R; showing the full vector in reports changes
  what every document shows and the vignettes' `render = knitr::normal_print` setup, a maintainer
  decision. Notebooks now show the full vector (`cbd85561`).
- Low 13 part 3 (hide the block markers when knitr echoes an agent chunk): an optional enhancement,
  not a defect; a knitr hook scoped to `gptr-*` labels is new machinery.
- Low 16 part b (raw export repeats a one-line prompt as `# Recorded prompt:`): deliberate,
  documented in `?gptr_export` ("only raw R adds prompt comments") and asserted in four tests.
- Low 17 part a, second half (send System 1 progress notices to stdout in a kernel through
  `console_progress()`): `s1-route.R` is L4 and `console-render.R` L5, so the call is a layering
  violation; moving the helper is more than this cosmetic stream choice needs.
- Low 17 part b (System 2 shows `gptr: done ...` and the session footer): shared with Rscript and
  specified by IC-77's verbosity-1 line; the verifier asks for one maintainer decision for Rscript
  and Jupyter together.
- D-342 limit: the `#~` switching of direct R lines after an undo stays `.R`-only; in an Rmd/qmd
  transcript a direct R line using an undone object fails on render.
