# P33 Undo of large objects: one capture rule, one undo setting (2026-11-17)

**Goal:** Undo of workspace objects keeps the old value by reference and never writes an image
before a call. One deterministic rule decides what is kept, in every front end. Memory and disk
stay within limits the user sets in one place, `gptr_config(undo = ...)`. A change made after a
turn is never silently overwritten when gptr can see it. Every count and every "cannot undo"
message is true, and each message names the limit to raise. The maintainer: "do that in the
current 1.1.0 version ... make sure that all the setting parameters are documented in the doc and
cheat sheet ... with the default values set at a reasonable value ... easily modifiable by the
users in a consistent settings ux".

The survey of 2026-11-17 (main 5cf591cd; scratch results summarised in memory
`gptr-undo-large-objects`) found four defects, confirmed end to end through `peter()` with the
fake provider:

| Defect | Cause |
|---|---|
| Undo overwrites a user's in-place edit made after the turn (`x[1] = 99` on a value restored from disk or a copy) | `ckpt_expect_ok()` compares addresses only, while `?gptr_rewind` says such changes are kept |
| A list holding an environment edited through it is reported "restored" | the image shares the environment; documented nowhere |
| `gptr_checkpoints()` counts images the turn-end budget dropped as restorable | `ckpt_turn_counts()` reads the fragment's `restorable` only |
| A computed-name change to an object over `gptr.undo_capture_max` gets no pre-run line | `ckpt_note()` lists predicted targets only |

The benchmark (128 GB Mac, R 4.6.1, load 25-300): with a reference held, an edit copies only what
it touches (a data-frame column, 38 MB of 440 MB; a list element or a small S4 slot, 0; an atomic
vector or matrix, all of it, in about 0.01 s). `data.table` `:=` and `set()` mutate through a held
reference, so a table needs `data.table::copy()`, which it already gets. The eager disk image
before a predicted in-place edit is the 2.84 s stall of the T03 row (dev/HANDOFF.md, P32 live
pass). Streamed `unserialize(con)` restores with 1x the object's RAM against 2x for
`unserialize(readBin())`. gzip costs about 30 s per 430 MB and is not used.

**Authority:** this plan amends, in place:

| D | Rule | Amends |
|---|---|---|
| D-368 | one capture rule: every object up to `undo.capture_max` and every predicted target up to `undo.memory` is held by reference, nothing is written before a call; the budget runs after every call and at the turn end; disk holds spilled images only, at most `undo.disk` bytes per session, sized by their files; restore streams | G7 §3.4 step 3 (the eager disk image), §3.7; `04` §3.1 undo rows; `03` §6.16 |
| D-369 | the 3-way rule compares fingerprints (which include the address), not addresses | G7 §3.6; `04` §7.16 text on conflicts |
| D-370 | the four `gptr.undo_*` options become the core setting `undo` (`capture_max`, `memory`, `disk`, `turns`) with the dotted options `gptr.undo.<field>` as its option layer, as `subagents` has | `04` §3.1 and §11.2 |

Next free decision: D-371.

**Depends on:** P32 (main 5cf591cd). **Milestone:** 1.1.0 (not yet submitted; the version stays
1.1.0).

## Global constraints

`dev/plan/00-conventions.md` applies in full: `=` and `|>`, simplicity first (section 11), pure R,
no compiled code, no new Imports or Suggests, offline tests with the fake provider, nothing left
changed, copy-safety rules R2-R6. The only new user-facing name is the setting `undo`; the four
old options are removed, not aliased (NEWS says so). No new exported function. No test asserts a
wall-clock time; times are recorded in `dev/progress/P33.md` from `dev/bench/undo/run.R`.

## Design

### 1. The `undo` setting (D-370)

`settings_core()` gains

```r
rec("undo", list(capture_max = 1e8, memory = 1e9, disk = 2e9, turns = 20L), "object",
    "Undo limits for objects: bytes kept by reference, in memory and on disk; turns kept.",
    fields = list(capture_max = "num_or_null", memory = "num_or_null", disk = "num_or_null",
                  turns = "int"))
```

`gptr_option_defaults` replaces `undo_capture_max`, `undo_max_bytes`, `undo_spill_max` and
`undo_turns` with `undo.capture_max = 1e8`, `undo.memory = 1e9`, `undo.disk = 2e9` and
`undo.turns = 20L`, as it does for `subagents.*`. `ckpt_limits()` reads each field with
`setting_get("undo.<field>")`, so the layers are the usual ones: package default, user file,
project file (trusted), `options(gptr.undo = list(...))`, `options(gptr.undo.<field> = )`, the
session scope. The defaults keep 1.0.0's values: 100 MB (any object), 1 GB in memory, 2 GB on
disk, 20 turns.

| Field | Default | Meaning |
|---|---|---|
| `capture_max` | `1e8` | every object up to this many bytes is kept by reference before a call that runs R code |
| `memory` | `1e9` | an object the code is predicted to change is kept up to this size; the images of a session hold at most this many bytes in memory |
| `disk` | `2e9` | bytes of images spilled to disk per session |
| `turns` | `20` | images older than this many turns are dropped |

### 2. One capture rule (D-368)

```r
ckpt_capture_how = function(bytes, predicted, mode, lim) {
  bytes[is.na(bytes)] = 0
  how = ifelse(bytes <= lim$capture_max | (predicted != "none" & bytes <= lim$memory), "ref",
               "skip")
  how[mode == "copy"] = "copy"
  how[mode == "none"] = "none"
  how
}
```

Deleted: `ckpt_capture_disk()`, the disk loop of `ckpt_objects_before()`, the disk branches of
`ckpt_settle_row()` (every kept image is held in memory and sized by `ckpt_unshared_bytes()`), and
the `spill_ok` argument. `ckpt_spill_allowed()` only chooses the spill directory when the session
starts. Fragments written by 1.0.x with `how = "disk"` still restore through the
earlier-process path. The `gptr_preimage()` budget is `lim$memory`.

A skipped object's reason names its limit: `"larger than undo.memory"` for a predicted target,
`"not predicted to change; larger than undo.capture_max"` otherwise. The reason flows unchanged
into `ckpt_note()`, the model's notes and `/undo`. `ckpt_note()` also lists the objects over
`undo.capture_max` when the code's targets are unknown (`tg$unknown`): such code may change any of
them.

### 3. Budget after every call; disk cap; streamed restore (D-368)

`ckpt_objects_after()` calls `ckpt_objects_budget(ck, token$turn, envir)` before it returns, and
the `agent_end` call stays (it covers redo images left by `/undo`). The budget:

1. drops images older than `undo.turns` turns;
2. while the memory images exceed `undo.memory`: spills the largest one when there is a spill
   directory and it fits `undo.disk`, else drops the oldest memory image;
3. while the disk images exceed `undo.disk`: drops the oldest disk image (its file is deleted).

A spilled row's `bytes` is its file's size. A row of the current fragment whose image the budget
dropped is written `restorable = FALSE` with the reason `"dropped to stay within undo.memory and
undo.disk"`; a spilled one is written `where = "disk"`. An older row whose image is gone says
`"not restored (no pre-image: dropped to stay within the undo limits, or made in another R
process)"`.

Restore from disk reads through a connection (`ckpt_read_image()`: `file(f, "rb")`,
`unserialize(con)`, closed on exit). The spill writer keeps the raw-vector route
(`serialize_leaf()`), the fastest for string-heavy data.

### 4. Fingerprint 3-way rule (D-369)

`ckpt_fp(envir, name)` returns NA for an absent binding, else the snapshot fingerprint of its
value through the same safe path as `env_snap_facts()` (a failing method gives the address), and
never keeps the value. `fingerprint()` already hashes the address, so a rebind is detected as
before. Every `expect` that held an address holds this fingerprint instead: `ckpt_settle()`,
`ckpt_settle_row()`, the created rows' `ckpt_mark()` (`post$fp`), `ckpt_restore()` (repoint and
redo row), `ckpt_spill()` (compares the binding's and the image's fingerprints before it defuses
the image), and `now` in `ckpt_objects_undo()` and `ckpt_objects_redo()`. `ckpt_expect_ok()` keeps
its form. Rows of another R process keep the `post_address` fallback, which never equals a
fingerprint: they conflict unless `force = TRUE`, as now. The fragment keeps `pre_address` and
`post_address` (contract 4.6 unchanged).

Documented limit: `fingerprint()` samples at most 64 values of an atomic vector, so an in-place
edit of an unsampled element (`x[37] = 0` of 1e6) after the turn is not seen. While an image is
held in memory every such edit copies and moves the address, so the limit concerns values restored
from disk or a copy.

### 5. Honest counts

`ckpt_turn_counts()` counts a changed or removed object row as restorable only while this
process's index holds its image key, or its image file exists in the store directory. Created rows
stay restorable (their undo needs no image).

### 6. Documentation

`?gptr_rewind` (rule, limits, RAM cost, conflicts, environments inside restored containers keep
their current state, in-memory images do not outlive the R process), `?gptr_options` (the four
`gptr.undo.*` entries), the settings list wherever the core settings are documented,
`?gptr_security` (object images, in memory or spilled, are full unredacted copies), the
configuration and execution-model vignettes (`.Rmd.orig` and `.Rmd`), the cheat sheet
(`pkgdown/assets/cheatsheet.html`: one row for `gptr_config(undo = list(memory = 4e9))`), NEWS
1.1.0, contract `04` §3.1 and §11.2, `03` §6.16, DEVIATIONS D-368 to D-370, `dev/progress/P33.md`,
PROGRESS, HANDOFF, `00-index.md`.

## Tasks

Each task: the failing test first (shown red), then the code, then green; lint on the changed
files; one commit with the message given; a D entry and a progress section in the conventions'
formats.

- **T1 The `undo` setting** (`R/gptr-config.R`, `R/utils-options.R`, `R/ckpt-objects.R`
  `ckpt_limits()`, `tests/testthat/test-gptr-config.R`, `test-utils-options.R`, every test that
  sets the old options). Failing tests: `gptr_config(undo = list(memory = 5), .scope =
  "session")` gives `ckpt_limits()$memory == 5` with the other fields at their defaults;
  `options(gptr.undo.memory = 7)` gives 7; a negative `memory` is an `invalid_argument` error;
  `gptr_config()` prints `undo` with its layer. Commit `feat(config): the undo setting holds the
  object undo limits`.
- **T2 One capture rule** (design 2; `R/ckpt-objects.R`, `tests/testthat/test-ckpt-objects.R`,
  `test-ckpt-rewind.R`, `test-copy-ckpt.R`). Failing tests: the plan of every binding is the same
  with and without a store directory; a predicted `df$a[1] = 0` on a data frame over
  `undo.capture_max` is `"ref"`, writes no file and holds less than half the frame; the two skip
  reasons; `ckpt_note()` for code with unknown targets lists a binding over `undo.capture_max`.
  Commit `perf(undo): one capture rule, no image written before a call`.
- **T3 Budget after every call, disk cap, streamed restore** (design 3; same files). Failing
  tests: two calls in one turn with a small `undo.memory`: with a spill directory the larger image
  is spilled and its row's bytes equal its file's size; without one the older image is dropped and
  the newer call's undo restores; a row dropped in its own call is not restorable and says so;
  disk images over `undo.disk` are dropped oldest first and their files deleted; a value restored
  from disk is identical to the original and its next in-place edit keeps its address. Commit
  `feat(undo): memory and disk limits hold after every call`.
- **T4 Fingerprint 3-way rule** (design 4; same files). Failing tests: after a restore from disk,
  the user's `x[1] = 99` and `L$b[1] = 0` make the next undo or redo a conflict that keeps the
  current value, and `force = TRUE` restores; the rebind and "spilling an image the binding holds
  again" tests still pass; one test records the documented `x[37]` limit. Commit `fix(undo): a
  change made after the turn is a conflict, not overwritten`.
- **T5 Honest counts** (design 5; `R/ckpt-rewind.R`, `test-ckpt-rewind.R`). Failing test:
  `gptr_checkpoints()` lowers the restorable count of a turn whose image the budget dropped.
  Commit `fix(undo): checkpoint counts include only images still held`.
- **T6 Documentation** (design 6). `devtools::document()`, the vignettes' `.Rmd` from their
  `.Rmd.orig`, `inst/WORDLIST`, spelling. Commit `docs(undo): the undo setting and rule`.
- **T7 Measurements** (`dev/bench/undo/run.R` (new), `dev/progress/P33.md`). At 0.5 GB, against
  main in a child `Rscript --vanilla` each: before, eval, after and undo seconds, held and disk MB
  and peak RSS for a string-heavy list, a data-frame column edit, a numeric matrix edit and a
  rebind; plus `dev/bench/perf/run.R --check --only=PERF-4,PERF-6,PERF-8`. Commit `test(bench):
  undo of large objects`.
- **T8 Live pass** (RStudio first, then a terminal console): a fake-provider and a real-model
  session that edit a 0.5-1 GB object, `/undo`, `/redo`, `/checkpoints`, the setting changed with
  `gptr_config()`; record in `dev/progress/P33.md`. Fixes found get their own commits.

## Plan acceptance

Every test named above passes; the rewind fixture and the decision battery are unchanged except
the reason texts; `devtools::test()` passes in full, lint is clean, `R CMD check --as-cran` gives
0 errors, 0 warnings, 0 notes; every CI job is green; no image is written before a call; the
interactive T03-like row has no disk-image line.
