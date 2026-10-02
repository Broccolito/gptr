# G7 - Checkpoints, undo and rewind for file edits and R-environment changes under copy-safety and an append-only transcript

Research date: 2026-09-29. Track: G7 (gap report). R 4.4.3 on macOS (Apple M2, 24 GB RAM), `Rscript --vanilla`,
private library for profmem, lobstr, rtiktoken and rlang 1.1.7. Load average 5-23 during the runs (other agents);
absolute times vary by up to 3x between runs, so every timing is given as the range over all runs, and the design
relies only on orders of magnitude and on within-run comparisons. The adversarial verification (one full re-run of
`run_all.sh` plus two extra samples of the disputed timings, load 7-17) widened several ranges; the ranges in
sections 1-4 include those runs. Section 5 embeds the original final run unchanged. See the Verification log. Scratch: `scratchpad/work/G7/`; every prototype
in section 5 was re-run from scratch by `run_all.sh` and its output is embedded verbatim.

Evidence labels: **VERIFIED** (executed here, or read first-hand in source/docs with a pointer), **LIKELY**
(strong inference, not executed), **UNCERTAIN** (plausible, unconfirmed). House style: `=` for assignment and `|>`
for pipes in all code (S-9); `<<-` appears only for closure state, as the conventions allow.

Builds on (not repeated here): 18 §4.8 (`/undo`, `gptr.undo_max_bytes`, `gptr.protect_size`), 12 C2-C5 and §3.8
(sticky references, snapshots, fingerprints, task-callback log), 21 §2.9-2.10 (fingerprints, hashing), 11 (atomic
writes, stale files, hard links), 20 §2.11 and §4.3 (Claude checkpointing, pre-edit copies), 02 §2.11/§3.4/§4.6
(session tree, entries), 14 §3.1-§4.5 (blocks, replay, transcript), 15 (binding guard, reference objects), 17
(artifact `vNNN`), 13 (consented write locations), G1 (registry, events, names), G4 (context placement, prefix
guard, caching).

---

## 1. Executive summary

1. **The critic's finding holds, and it is worse than stated.** Report 18 §4.8 proposed `snap = mget(overwrites,
   envir)` and claimed it "costs no copy". Two costs were measured:
   - While the snapshot is held, the agent's in-place edit copies the whole object (critic's check, reproduced;
     case c02).
   - After the snapshot is **dropped and garbage-collected**, the user's next in-place edit copies the whole object
     again (c03). The list left a permanent extra reference count on the object.

   Mechanism (VERIFIED in R 4.4.3 source): reference counts are decremented only when a field or binding is
   *replaced* (`FIX_REFCNT` in `memory.c` 1281-1302, `SET_VECTOR_ELT` 4174). `rm()` goes through `RemoveFromList`,
   which overwrites the binding cell (`envir.c` 789-820). The garbage collector never adjusts reference counts. So
   a list that ever held the object leaves the count raised; an environment binding removed with `rm()` does not.
   18 §4.8's `mget()` snapshot and its "no copy" claim are therefore **superseded** by this report.

2. **Copy-safe pre-images.** The rules:
   - Hold every pre-image as a *binding in a private environment*, never in a list.
   - Release it with `rm()`.
   - Before dropping a list or S4 pre-image, *defuse* it: take it out of the store, then overwrite its elements in
     place, which releases children shared with the user's current object (c12, c12d; the obvious in-store variant
     does not work, v1).
   - Register a finalizer that does the same when a session is dropped.

   With these rules every case in the 24-line tracemem matrix behaves as intended (section 5.2):
   - A captured but untouched object stays editable in place.
   - Restores and spills leave the user's object editable in place.

   A useful side effect: while a pre-image is held, a value-semantics object cannot be modified in place without
   R duplicating it. So **"address changed" is an exact change detector** for captured objects. It closes the
   sampled-fingerprint blind spot of 12 C4 and 21 §2.9 for everything except by-reference types.

3. **The copy penalty is inherent, minimal and bounded.** Keeping the old value of an object the agent edits *in
   place* needs exactly one copy of the modified leaf. For a 1 GB vector that is 1,000 MB allocated, 0.11-0.26 s,
   and about 954 MB held until the image is spilled or dropped. Rebinding (`x = f(x)`) and removal cost **no** copy;
   they only keep the old value alive. The by-reference capture itself costs 1-2 ms.

   On a 368 MB Seurat object the pre-image held back very little:

   | Agent verb | Held back (lobstr) |
   |---|---|
   | metadata / `Idents()` | 0.00 MB |
   | `NormalizeData()` | 0.80 MB |
   | `subset()` | 362 MB (the old object) |

   There was no copy penalty in any of the three cases. Structural sharing through S4 slots and list elements
   makes by-reference capture cheap exactly where multi-GB objects live.

4. **Strategies compared at 10 MB and 1 GB** (sections 2.4, 5.3). Each cell is capture / penalty on the agent's
   in-place edit / held memory / restore:

   | Strategy | 1 GB |
   |---|---|
   | none | nothing restorable |
   | by-reference | 1 ms / 1 GB copy / 954 MB / 1-4 ms |
   | by-reference, spilled at turn end | 1 ms / 1 GB copy / 0 MB after a 0.28-0.92 s spill / 0.14-0.71 s |
   | eager `serialize(ascii = FALSE, xdr = FALSE)` | 0.29-0.70 s / none / 0 / 0.13-0.60 s |
   | eager `saveRDS(compress = FALSE)` | 0.77-1.66 s / none / 0 / 0.66-1.78 s |
   | recompute | 0 / none / 0 / 0.66-6.2 s for `runif()`, minutes for a real pipeline |

   At 10 MB every strategy costs at most 14 ms.

   Recommendation:
   - Capture by reference for everything within budget.
   - Capture eagerly to disk for predicted *in-place* edits of objects above the in-memory cap.
   - At turn end, spill held images that are over budget.
   - Offer a recompute *recipe* (a backward slice of the recorded code; prototyped, identical result) when no image
     exists.

5. **New pitfall (VERIFIED):** `base::serialize(x, con)` without an explicit `ascii =` leaves a sticky reference.
   Its `missing(ascii)` branch calls `summary(connection)` while `object` is still an unforced promise. `saveRDS()`
   and `serialize(x, con, ascii = FALSE, xdr = FALSE)` do not leave one. Any gptr code that serialises user
   objects must pass `ascii = FALSE`.

6. **What cannot be restored, and how it is reported.**
   - Environments, R6 and RefClass objects: the by-reference pre-image *is* the live object (c14).
   - data.table modified with `:=`/`set()` (c13): restorable only through an eager `data.table::copy()` when the
     static predictor sees a by-reference call.
   - External pointers: `serialize()` restores `<pointer: 0x0>` (c15).
   - Loaded namespaces (never unloaded), devices and connections closed by the turn, network, database and process
     side effects.

   Restorable side state, each with a 3-way check (VERIFIED, section 5.5): options, environment variables (values
   kept in memory only), working directory, attached packages, devices and connections the turn opened, RNG state
   (the undone draws disappear from the stream), locale (reported only). Unrestorable items appear in the rewind
   report and, when the model's picture would otherwise be wrong, in a 25-87-token note.

7. **Files: a pure-R content-addressed store plus a walk after each mutating call.**
   - The store: `blobs/<2 hex>/<XXH128>[.gz]`, gzip level 1 (2.6x smaller at the cost of a raw copy), deduplicated
     across turns and sessions.
   - A baseline of small source-like files at the first mutating call, then a pruned walk after every mutating
     tool call.
   - Coverage: `edit`, `write` and `apply_patch`, **and files written by model R code and child processes**, which
     Claude Code does not track ("Bash command changes not tracked").
   - Restores are 3-way: a file the user changed after the turn is left alone and reported. Claude Code's rewind
     overwrites such changes (LIKELY: inferred from its docs, which describe no conflict check; not tested).

   Measured on the 2,125-file Pi tree:
   - baseline 1.1-1.9 s once (23 MB tracked, stored as 8.6 MB); 0.21-0.38 s in later sessions (dedupe);
   - 0.10-0.21 s per mutating call;
   - undo of three steps (scenario project) 65-104 ms.

   On a 4,167-file tree with many directories a walk takes 0.7-1.3 s and a no-change step 0.7-1.4 s, so scanning
   must be adaptive (§3.5). Nothing is ever written into the user's `.git`: Codex removed its experimental `/undo`
   because "its design caused problems for many users" (maintainer statement, 2026-01-21); a later user comment in
   the same discussion attributes those problems to ghost commits written into users' own repositories (#8214).

8. **Rewind is a branch-in-place on the one S-8 session object; forking stays explicit.**
   `gptr_rewind(s, turn)` does four things:
   - undoes the checkpoint records between the leaf and the target, newest first (and redoes records when the
     target is on another branch);
   - appends a `gptr.rewind` custom entry whose parent is the target;
   - hands back the undone prompt;
   - returns **the same object**, so `s |> gptr_rewind(2) |> gptr("try X")` reads as ordinary R.

   Verified in section 5.6:
   - the JSONL stays byte-append-only;
   - the leaf is durable on reload (Pi rule: last entry in file order);
   - the next request's prefix is byte-identical to the earlier request at that point, so the prompt cache can
     be reused (byte identity VERIFIED; whether a provider actually hits depends on where earlier requests placed
     cache writes, G4 - LIKELY);
   - redo onto the abandoned branch restores its objects and files;
   - `gptr_fork()` remains the only way to get a second session object.

9. **History document.** Undone turns become inert: `#~ ` prefix, `status=undone` in the block header. `source()`
   of the regenerated transcript reproduced the rewound workspace (VERIFIED). Report 14's replay table gains an
   "undone" row. `gptr_rewind()` written into a script is a workspace no-op in replay mode.

10. **Token efficiency (S-12).**
    - Checkpointing is invisible to the model: 0 tokens per turn.
    - A 25-token notice is added only when an object could not be captured.
    - A fully restored rewind costs 0 tokens and keeps the prefix byte-identical (cache reuse LIKELY, see item 8).
    - A partial rewind costs one `<workspace_changes>` block (87 tokens for three unrestored items).
    - Letting the model revert one file itself costs 4,349 tokens plus a round trip, and it cannot revert an
      in-memory object at all.

11. **Everything is a plugin (S-11).** One new registry kind, `checkpointer` (contract in §4.6). Built-ins: files,
    objects, state, artifacts. There is also an S3 generic `gptr_preimage()` so packages can teach gptr how to
    capture their reference classes, three events, and settings. A shadow-git backend (never the user's `.git`)
    is an optional plugin. Two new exports, `gptr_rewind()` and `gptr_checkpoints()`, collide with nothing in 662
    installed packages. No new non-base Imports (rlang and jsonlite are already proposed); the base package
    `methods` is added to Imports (§4.8, §6), and base `tools`/`utils` are used. No Rcpp: the per-call object
    operations cost milliseconds. File walks cost 0.1-1.4 s per call; they were not profiled for an Rcpp case, and
    REQ-01 requires a benchmark before one is considered (adaptive scanning, §3.5, is the first remedy).

---

## 2. Findings with evidence

### 2.1 What existed, and the three collisions

| Fragment | Where | Problem found here |
|---|---|---|
| `/undo` via `snap = mget(overwrites, envir)`, restore with `list2env()`, budget `gptr.undo_max_bytes = 1e9`, `gptr.protect_size = 100e6` (overwriting bigger objects is risk level 3) | 18 §4.8, table at lines 879-880, A.13 | The list keeps the old value alive, which is correct. But it (a) forces a full copy on the agent's in-place edit and (b) leaves a sticky reference after it is dropped: the user's next edit copies again (c02, c03). "+4 MB, no copy" in A.13 measured only the snapshot step, never the next edit. |
| Pre-edit copies under `.gptr/sessions/<id>/snapshots/` | 20 §4.3 (lines 942-946) | Covers only the edit tools. Per-session paths defeat deduplication. No location when there is no `.gptr/` (13). |
| Stale-file detection as an open question | 11 lines 588, 3753 | Needs a per-session read registry, which the checkpoint tracker provides. A rewind must also roll back what the model "has read". |
| Copy-safety: never hold references to user objects between turns | 12 C2, 21 §2.9 item (4) | An undo *must* hold the old value. Resolution: hold only displaced values (pre-images), as environment bindings, released with `rm()`, and only for bindings that actually changed (§2.3). |
| Append-only transcript (preserved thinking, caches) | 07; G4 §4.1 principle 3 | A rewind cannot edit history. Resolution: an appended `gptr.rewind` entry parented at the target (§2.8). |
| Consented write locations | 13 (digest: `.gptr/` only via `gptr_init(path)` or consent, else tempdir) | Blob store under `.gptr/checkpoints/` or `tempdir()`; never `.git`, never `R_user_dir` for blobs (§4.2). |

### 2.2 How other harnesses do it (VERIFIED from primary sources, fetched 2026-09-29)

| Harness | Mechanism | Coverage | Conflict handling | Retention |
|---|---|---|---|---|
| Claude Code | Pre-edit file snapshots in `~/.claude/file-history/<session>/`; a checkpoint per prompt that starts a turn; `/rewind` or Esc Esc offers "Restore code and conversation", "Restore conversation", "Restore code", "Summarize from here", "Summarize up to here"; the prompt text returns to the input | Only its file-editing tools. "Checkpointing does not track files modified by Bash commands". Sub-agent edits not restored. Symlinked and hard-linked paths skipped ("Restored the code, but skipped N files") | External changes "normally not captured, unless they happen to modify the same files as the current session", i.e. overwritten on restore | 100 most recent checkpoints per session; deleted in the retention sweep about 30 days later (`cleanupPeriodDays`); `fileCheckpointingEnabled` toggle |
| Codex CLI | Formerly `Feature::GhostCommit` ("ghost snapshots") with `/undo`. **Removed**: "We previously exposed an experimental `/undo` command. It didn't get much use, and its design caused problems for many users, so we removed it." (etraut-openai, 2026-01-21). A later user comment (S2thend, 2026-08-21) says the ghost commits were dangling commit objects written into the user's own repository and that restore touched the user's index (#8214). The same comment attributes 102 GB of orphan objects on a 5.7 GB project (#29388) to Codex **Desktop's** `refs/codex/turn-diffs/` checkpoints, not to the CLI `/undo` (UNCERTAIN, user report) | Compatibility-only config retained (`config/mod.rs:233-250`, defaults: ignore untracked files over 10 MiB and directories over 200 files, lines 225-226, clone 8ea2c0e) | - | - |
| Gemini CLI | Shadow git repository `~/.gemini/history/<project_hash>` plus conversation JSON; `/restore` reverts files, restores the conversation and re-proposes the tool call | File-modifying tools; **disabled by default** | - | - |
| opencode | Snapshots in "a separate internal Git object database under its data directory", taken before each model call and at step end; `/undo`, `/redo` | Tracked files in the active directory plus non-ignored untracked files up to 2 MiB each; not ignored files, not files outside the active directory, not other shell side effects (services, processes, network, databases, Git state). That shell-made edits to covered files are restored is LIKELY (inferred from directory-state snapshots; the page does not say so explicitly) | - | not documented |
| Aider | "/undo: Undo the last git commit if it was done by aider" | Its own auto-commits | git | git |
| Pi | Conversation tree only (`/tree` moves the leaf, `/fork` new file, `/clone`); leaving a branch can summarise it (`branch_summary`). File restore only via the example extension `git-checkpoint.ts` (`git stash create` per turn, offered on fork) | Conversation, or files via an extension | - | - |

Lessons adopted:
- Checkpoint per turn with per-call records (Claude).
- Restore menu with the same four actions (Claude).
- Never write into the user's repository (Codex).
- Cover shell- and code-made changes by snapshotting the tree, with a size cap for untracked files (opencode).
- Treat checkpoints as a plugin category (Pi's extension).
- Refuse to write through links (Claude).
- Be *better* than all of them on conflicts (3-way) and on in-memory state, which none of them has.

### 2.3 Reference counts and pre-images (VERIFIED: section 5.2, 24 verdict lines; R source)

- **Mechanism.**
  - `FIX_REFCNT` decrements the old value only when a field is replaced (`memory.c` 1281-1302; `SET_VECTOR_ELT`
    at 4174).
  - `rm()` reaches `RemoveFromList`, which sets the cell to `R_UnboundValue` and fixes the count (`envir.c`
    789-820).
  - No reference-count update happens when the collector frees a node. In `memory.c`, `DECREMENT_REFCNT`
    appears only inside the `FIX_REFCNT_EX` macro (1282-1297; `FIX_REFCNT` defined at 1298-1302), whose `FIX_REFCNT`/`FIX_BINDING_REFCNT` uses are
    all in setters (`SET_*`, lines 3814-4535); in the argument-list cleanup (4327-4328); and in the exported
    function wrapper `DECREMENT_REFCNT()` (3869, an API entry point). None is in `TryToReleasePages` (1052),
    `ReleaseLargeFreeVectors` (1143) or `R_gc_internal` (3174). `rm()` reaches `RemoveFromList` through
    `do_remove` → `RemoveVariable` (envir.c 1936-1976, 2011), directly or via `R_HashDelete` for hashed
    environments such as the global environment (394-409).
  - Hence: list snapshot = sticky; binding + `rm()` = clean.
- **Matrix results** (fresh process per case; `ckpt_*` byte-compiled). Each is VERIFIED.
  - c01 baseline: edits in place.
  - c02 `mget()` held: the agent edit copies.
  - c03 `mget()` dropped + `gc()`: the user's edit copies. **This is the 18 §4.8 defect.**
  - c04 env pre-image held: the agent edit copies (inherent); afterwards the user's edits are in place.
  - c05 captured, unchanged, released with `rm()`: in place.
  - c06 store garbage-collected without `rm()`: copy. A finalizer fixes it (`p1_finalizer.txt`: in place).
  - c07 the agent rebinds `x = x * 2`: the user's edit of the new `x` is in place.
  - c08 and c08b: restore, with or without keeping the redo image: in place.
  - c09 the user changed `x` after the turn: restore refused ("conflict").
  - c10 spill to disk and restore from disk: in place.
  - c11 `saveRDS(get())` by name: in place.
- **Structural sharing.**
  - c12: the agent's `L$new = 1` makes a new list sharing columns with the pre-image. The user's in-place edit of
    a shared column copies it while the pre-image is held.
  - After dropping *without* defuse it copied too (first run); with defuse it is in place (c12, c12d).
  - Plain R does not copy here (c12b), so the extra copy is ours and defuse removes it.
  - The in-store form `slots[[key]][[j]] = FALSE` duplicates the container and does **not** release (v1 in
    `p1_defuse_variants.txt`). Taking the image out first works, compiled or not (v4, v5).
- **S4 (Seurat-like).**
  - c12c: a metadata edit on an 8 MB S4 object keeps 128 bytes unshared; the big slot stays shared.
  - c12e: S4 slot edits copy in plain R anyway (confirms 12 C2), so no extra penalty from gptr.
- **Attributes.** c17: an attribute edit with a pre-image held duplicates the vector. It is in the same class as
  in-place element edits.
- **Promises and active bindings are never captured.** c16: the kinds come from
  `rlang::env_binding_are_active/lazy`, and the promise stays lazy.

### 2.4 Object strategies: measurements (VERIFIED; section 5.3)

One fresh process per (size, strategy, operation). Allocation is measured with `Rprofmem()` switched on and off at
top level, so no wrapper adds references. "Penalty" is the extra allocation the checkpoint causes during the
agent's operation, compared with `none`.

| 1 GB (`runif(1.25e8)`) | capture | agent `x[1] = 0` (penalty) | agent `x = x + 1` | held after turn | restore | disk |
|---|---|---|---|---|---|---|
| none | - | 0 MB, 0 s | 1,000 MB (the op itself) | 0 | impossible | 0 |
| by-reference | 0-2 ms | **1,000 MB, 0.11-0.26 s** | 1,000 MB (no penalty) | 954 MB | 1-4 ms | 0 |
| by-reference + spill at turn end | 0-2 ms | 1,000 MB, 0.11-0.22 s | 1,000 MB | 0 (spill 0.28-0.92 s) | 0.14-0.71 s | 1,000 MB |
| eager `serialize(ascii = FALSE, xdr = FALSE)` | 0.29-0.70 s | 0 | 1,000 MB | 0 | 0.13-0.60 s | 1,000 MB |
| eager `saveRDS(compress = FALSE)` | 0.77-1.66 s | 0 | 1,000 MB | 0 | 0.66-1.78 s | 1,000 MB |
| recompute (`set.seed(1); runif(n)` replayed) | 0 | 0 | 1,000 MB | 0 | 0.66-6.2 s | 0 |

- At 10 MB every capture takes at most 14 ms, every restore at most 12 ms, and the by-reference penalty on an
  in-place edit is 10 MB (1-2 ms).
- All allocation and retention figures (0 / 10 / 1,000 MB allocated, 954 MB held, 0 MB on the user's next edit)
  reproduced exactly in the verification re-run; only the times vary with load.
- `rm(x)` under by-reference keeps the old 954 MB alive (retained 0 vs -954 MB for `none`).
- The user's next in-place edit after the turn allocated 0 MB in **every** strategy: no residual stickiness.
- The first `serialize` run (without `ascii`) showed a 1,000 MB penalty on the agent's in-place edit; this is how
  pitfall 5 was found. Corrected rows: `p2_disk_ser_fixed.txt`, final matrix.

Seurat 5.4.0, synthetic object of 20,000 genes x 30,000 cells, 3e7 non-zeros, `object.size` 368 MB (VERIFIED):

| Agent code | op alloc none / by-ref | held by pre-image: estimator / lobstr | restore |
|---|---|---|---|
| `pbmc$cluster = ...; Idents(pbmc) = 'cluster'` | 0 / 0 MB | 2.04 / 0.00 MB | 0-1 ms |
| `pbmc = NormalizeData(pbmc)` | 1,680 / 1,680 MB | 0.36 / 0.80 MB | 0-1 ms |
| `pbmc = subset(pbmc, cells = 15,000)` | 360 / 360 MB | 362.64 / 362.29 MB | 1 ms |

The estimator `ckpt_unshared_bytes()` (closure-free recursion over list elements and S4 slots, depth 4) takes 1 ms.
It is conservative: `object.size()` counts shared strings, which explains 2.04 vs 0.00 MB.

Capture everything by reference (500 bindings, 1.03 GB, VERIFIED):
- binding kinds 0-1 ms, sizes 13-16 ms, capture 2-3 ms, settle 4-7 ms, unshared estimate 1-2 ms;
- the untouched 1 GB object stays editable in place;
- the residual cost: a data.frame column shared with a held pre-image (the agent added a column) is copied once
  on the user's next in-place edit.

### 2.5 `serialize()` stickiness (VERIFIED; `p1_serialize.txt`)

`base::serialize` (R 4.4.3, printed in 5.2): `if (missing(ascii)) ascii <- summary(connection)$text == "text"`
runs S3 dispatch while `object` is still an unforced promise in the frame, so the frame leaks (12 C2 pattern).

| Call | User's next in-place edit |
|---|---|
| `serialize(x, con, xdr = FALSE)` at top level | COPY |
| same with `ascii = FALSE` | in place |
| by-name wrapper without `ascii` | COPY |
| by-name wrapper with `ascii = FALSE` | in place |
| by-name `saveRDS(..., compress = FALSE)` | in place |

Rule: every gptr serialisation of user data passes `ascii = FALSE` explicitly, and the tracemem regression suite
(12 §5.4) gets this case.

### 2.6 Objects and state that cannot be restored (VERIFIED unless noted)

| Kind | Why | Detection | Report / fallback |
|---|---|---|---|
| environment, R6, RefClass, proto | mutation keeps the address; the pre-image *is* the live object (c14: pre-image `v` = 2) | `typeof == "environment"`, `inherits(x, "R6")`, S4 + environment | "not restored (reference object)"; a `gptr_preimage()` method may deep-clone (for example R6 `$clone(deep = TRUE)`), opt-in per class |
| data.table after `:=`, `set*()` | modifies in place regardless of reference count (c13: pre-image has the new column, `a[1] = -1`; settle by address says "unchanged") | static predictor `byref` (VERIFIED for `[ , :=]`, `set`, `setnames`, ...) | eager `data.table::copy()` within budget; unpredicted by-reference edits made inside functions are invisible (21 §2.9 gap) |
| external pointers (DB connections, arrow, torch, reticulate, xgboost, BPCells) | state lives outside R; `serialize()` restores `<pointer: 0x0>` (c15) | `typeof == "externalptr"` | "not restorable (external resource)" |
| objects above the undo budget | policy | sizes from the per-turn snapshot (12 §3.8) | manual/edits: the permission prompt says so and offers "spill first"; auto: 25-token notice; recompute recipe (§2.9) |
| promises, active bindings | never forced or called (c16) | `rlang::env_binding_are_lazy/active` | reported only if rebound |
| ALTREP compact sequences (`1:1e9`) | `object.size()` reports 3.7 GB for 680 B (12 C3), so a spurious "over budget" | no exported base test (UNCERTAIN) | treat as capturable; documented risk |
| loaded namespaces | unloading is unsafe (DLLs, dependents) | `loadedNamespaces()` diff | "stays loaded" |
| attached packages | restorable | `search()` diff | `detach()` / `attachNamespace()` (VERIFIED) |
| options, env vars, working directory | restorable (3-way) | snapshot diff, 10-13 ms | restored; env-var **values never leave memory** (secrets, D-22) |
| devices opened / closed by the turn | opened: can be closed; closed: gone | `dev.list()` diff | default: leave opened devices open (the user may be looking at the plot), report; closed: "cannot be reopened" |
| connections opened / closed | opened: closed on undo; closed: gone | `showConnections()` diff | as for devices |
| RNG state | restorable when `envir` is the global environment (where `.Random.seed` lives) | `.Random.seed` identity | restored with the 3-way check. VERIFIED: after the undo the stream continues as if the undone draws never happened. This keeps the runnable document reproducible |
| files outside the project; network, DB, e-mail, processes | irreversible | classifier categories (18: network/system/process), `ckpt_targets()$process`, literal paths outside the root | "external side effects are not undone" in the tool result and the rewind report |

### 2.7 Files: store, walk, capture, restore (VERIFIED; section 5.4)

- **Hashing** (2,081 Pi files, 27 MB):
  - `rlang::hash_file` 0.21-0.23 s, `tools::md5sum` 0.10-0.13 s, `cli::hash_file_sha256` 0.20-0.25 s;
  - one 100 MB file: rlang 11-14 ms against md5 190-280 ms.
  - rlang's XXH128 is streaming and vectorised over paths (rlang 1.1.7 docs). Use it; md5 is the base fallback.
    Note that on this corpus of ~2,000 small files md5 was about 2x *faster* than rlang (cause not profiled,
    presumably per-file overhead); rlang wins clearly only on large files.
- **Store ingest** of the same corpus:
  - raw copy 0.41-0.56 s → 27.0 MB;
  - gzip level 1: 0.53-0.86 s → 10.5 MB;
  - gzip level 6: 0.78-1.49 s → 9.4 MB.
  - Level 1 up to 8 MB per file; already-compressed formats (`.rds`, `.parquet`, `.png`, `.zip`, ...) stored raw.
- **Walk**: pruned breadth-first, one `list.files` + `file.info` + `Sys.readlink` per directory, never following
  links, always pruning `.git`, `.gptr`, `node_modules`, `renv/library`, ... (report 11's list).
  - Pi tree: 0.116-0.24 s.
  - 4,167-file, 1,000+-directory library tree: 0.73-1.27 s.
- **Baseline** (source-like files first, at most 1 MB each, 100 MB total):
  - Pi: 2,123 files, 23.3 MB → 8.6 MB stored, 1.08-1.87 s;
  - a second session against the populated store: 0.21-0.38 s, no new blobs;
  - no-change step 0.10-0.21 s (Pi), 0.66-1.40 s (library tree).
- **Scenario** (`test_files.R`, 9/9 PASS):
  - an edit-tool atomic write;
  - model R code that creates `out.csv`, overwrites `data/big.csv` in place with `write.csv()`, deletes
    `notes.md`, and patches an untracked 30.6 MB file;
  - a child process (`Rscript -e writeLines`) rewrites `R/b.R`;
  - the user then edits `R/b.R`.

  Undo of all steps (65-104 ms):
  - the created file is removed, the deleted file restored, and the in-place overwrite undone;
  - `R/b.R` is left alone as a conflict (the user's edit wins), and `huge.bin` is reported as having no
    pre-image;
  - the symlink is never written through.

  Also verified: forced undo, dedupe (rewriting identical content adds no blob), and pruning (unreferenced blobs
  deleted, live ones kept).
- **Racy-clean rule** (git): same size and mtime but mtime within 2 s of the previous walk means the content hash
  is compared. It covers coarse mtime clocks (FAT: 2 s).

### 2.8 Session tree and rewind (VERIFIED; Pi source; section 5.6)

- **Pi semantics** (commit `1b34779`):
  - `branch(id)` moves the leaf in memory only (`session-manager.ts:1579-1584`); `resetLeaf()` sets it to null
    (1591-1593).
  - `branchWithSummary()` moves the leaf and appends a `branch_summary` entry parented at the target, with
    `fromId` = old leaf (1600-1625).
  - On load the leaf is the **last entry in file order** (02 §2.11; `session-manager.ts:1107-1111`). A rewind that
    appends nothing is therefore *lost on reload*.
  - `navigateTree()` puts a selected user message's text back in the editor and sets the leaf to its parent
    (`agent-session.ts:3990-4005`). Summaries are optional and cost a model call.
  - The model receives `branch_summary` with a fixed prefix (`messages.ts:19-24`, 21 o200k tokens plus the
    summary).
- **gptr prototype results** (`test_session.R`, 13/13 PASS):
  - The pipe drives three turns on one object.
  - `gptr_rewind(s, 1)` undoes turns 3 and 2 in 0.12-0.17 s.
  - It returns the identical object (`identical(s2, s)`).
  - Objects are back to the end of turn 1: `pca` and `seed_draw` gone, the in-place column edit undone. The file
    edit is undone, and turn 1's file is kept.
  - The reference object `cfg` is reported "not restored".
  - The JSONL prefix bytes are unchanged and one entry was appended.
  - `startsWith(request_turn2, view_after_rewind)` is TRUE: the provider cache prefix survives.
  - The undone prompt is handed back.
  - After a new turn on the new branch, `gptr_rewind(s, to = <old leaf>)` redoes the abandoned branch: objects
    (including creations and removals) and files come back. The reference object is reported "not redoable".
  - Reload: the last entry is the `gptr.rewind` marker, parented at the target (durable leaf).

### 2.9 History document and recompute recipe (VERIFIED; sections 5.6, 5.7)

- `render_transcript()` projects the whole tree in file order:
  - live turns as ordinary blocks (report 14 grammar);
  - abandoned turns kept for the record but inert (`#~ gptr("...")`, `status=undone`, `#~ ` code);
  - each rewind as a comment line.
- A fresh `Rscript` sourcing the transcript with a replay stub produced objects `cfg counts`, with `counts` equal
  to `log1p` of the data, which is the live rewound state.
- The one divergence is exactly what the rewind report lists: `cfg$alpha` (a reference object) is 0.01 live and
  0.05 on replay.
- Recipe: `ckpt_recipe()` takes the backward slice of recorded statements (static targets plus free variables).
  It rebuilt `norm` identically while running 5 of 7 statements; unresolved free names are listed.

### 2.10 Token accounting (VERIFIED with rtiktoken o200k_base as the proxy, as in G4)

| Model-facing item | Tokens | When |
|---|---|---|
| checkpoint records, snapshots, stores | 0 | never sent |
| per-call notice "note: pbmc (5.1 GB) was overwritten without an undo copy (over the 1 GB undo budget)." | 25 | only when a mutated object could not be captured |
| rewind, everything restored | 0 | the context equals the target's context byte for byte (VERIFIED); a cache hit within TTL is LIKELY and depends on where earlier requests placed cache writes (G4) |
| rewind, 3 items not restored (`<workspace_changes since=... reason="rewind">`) | 87 | only then |
| Pi `branch_summary` wrapper (if `summarize = TRUE`) | 21 + summary + a summarisation call | opt-in |
| model-driven revert of one 200-line file (prompt + re-read + edit call) | 4,349 + output + a round trip | the alternative Codex recommends; impossible for in-memory objects |

---

## 3. Exact specifications

### 3.1 Checkpoint record (Pi v3 `custom` entry, appended after each mutating tool result)

```json
{"type":"custom","id":"c902b3ce","parentId":"<toolResult id>","timestamp":"2026-09-29T23:15:02.113Z",
 "customType":"gptr.checkpoint",
 "data":{
  "turn":3, "tool_call":"call_7f3a21", "tool":"run_r", "by":"run_r",
  "objects":[{"name":"counts","env":"R_GlobalEnv","status":"changed","image":"pre000007","where":"memory",
              "held_bytes":0, "pre_address":"0x13a8","post_address":"0x13f0","restorable":true,"reason":""},
             {"name":"cfg","status":"changed","restorable":false,"reason":"reference object (environment/R6/external pointer)"}],
  "files":[{"path":"R/clean.R","status":"modified","pre":"a739721e21820f120c74aeb3001c8c4b","post":"<xxh128>",
            "mode":420,"post_size":42,"post_mtime":1790745302.1,"restorable":true,"reason":""}],
  "state":{"options":["digits"],"envvars":["NEW_VAR"],"wd":false,"attached":["package:tools"],"rng":true,
           "devices_opened":[2],"devices_closed":[],"loaded":["tools"]},
  "artifacts":[{"id":"marker-explorer","current_before":2,"current_after":3}],
  "external":["process"],
  "workspace":"<compact snapshot id: name/class/bytes/fp table of the turn end (12 section 3.8)>"}}
```

Rules:
- Environment-variable **values**, option values and object data never enter the JSONL; only names, hashes,
  addresses and sizes do.
- In-memory images are keyed by `image` (valid only in the R process that made them). Spilled images carry
  `"where":"disk","file":"objects/<key>.rdsx"`.

### 3.2 Rewind entry

```json
{"type":"custom","id":"71a62c58","parentId":"<target entry id or null>","customType":"gptr.rewind",
 "data":{"from":"<old leaf id>","to":"<target id>","keep":1,"restore":"all",
         "report":["object seed_draw: removed (created by the turn)","file R/clean.R: restored",
                   "object cfg: not restored (reference object ...)"]}}
```

- Appended after the undo and redo work. It becomes the leaf, so the rewind survives a reload.
- It is not part of the model context (Pi: `custom` entries are extension state, 02 §3.4).
- With `summarize = TRUE`, a Pi `branch_summary` entry (parented at the target, `fromId` = old leaf) follows it.

### 3.3 On-disk layout

```
<root>/checkpoints/                      root = <project>/.gptr   (consented workspace, 13)
                                              file.path(tempdir(), "gptr")   (no workspace)
  blobs/<2 hex>/<xxh128>[.gz]            file contents, shared by all sessions of the project
  objects/<session id>/<key>.rdsx        spilled object images (serialize, ascii = FALSE, xdr = FALSE)
  index.json                             blob -> last-referenced timestamp (for pruning); rebuilt if missing
<root>/sessions/<ts>_<id>.jsonl          checkpoint and rewind records live in the session log
```

- `.gptr/.gitignore` gains `checkpoints/` (report 14 §3.7 lists `sessions/` and `cache/tmp/`).
- Never `.git`, never `tools::R_user_dir()` (blobs are project data; `R_user_dir` must stay small, CRAN).

### 3.4 Object capture algorithm (per mutating `run_r`/`agent`/MCP call; sequential tools, 02/15)

1. `names = ls(envir, all.names = TRUE)` minus `.Random.seed` and `.Last.value`, then
   `kinds = ckpt_binding_kind()` (promises and active bindings skipped). Sizes and addresses come from the per-turn
   snapshot (12 §3.8; sizes cached by address).
2. `tg = ckpt_targets(code)`. One parse walk is shared with the risk classifier `gptr_risk()` (18). It yields
   `assign`, `modify` (left-hand side is a call: in-place edit), `byref`, `remove`, `super`, `files`, `unknown`
   and `process`.
3. Plan per binding:
   - value semantics and `bytes <= gptr.undo_capture_max`: capture by reference;
   - value semantics, predicted target (`assign`/`remove`/`super`), `bytes <= gptr.undo_max_bytes`, not in
     `modify`: capture by reference;
   - value semantics, in `modify`, `bytes > gptr.undo_capture_max`, `bytes <= gptr.undo_spill_max`, disk budget
     available: **eager disk image** (`serialize(ascii = FALSE, xdr = FALSE)`, about 0.3-0.7 s/GB), because
     by-reference would double memory at the edit;
   - data.table in `byref`, within budget: `data.table::copy()` (eager; memory = size);
   - anything else predicted to change: *not undoable*, which feeds the permission prompt (manual/edits) or the
     notice (auto).
4. Evaluate the code (report 12 evaluator).
5. `ckpt_settle()`:
   - address unchanged: release with `rm()`;
   - changed or removed: keep, and compute `held = ckpt_unshared_bytes()`;
   - bindings present now but not before: `created` (undo removes them and keeps a redo image);
   - uncaptured bindings whose address moved, or predicted by-reference mutation of reference types: record
     `restorable = FALSE` with a reason.
6. At turn end, enforce budgets: while `sum(held) > gptr.undo_max_bytes`, spill the largest held image if spilling
   is allowed and it is at most `gptr.undo_spill_max`; otherwise drop the oldest (defuse + `rm()`) and mark its
   record "image dropped (budget)". Images older than `gptr.undo_turns` turns are dropped.
7. Session end or garbage collection of the store: the finalizer defuses and removes every image.

### 3.5 File capture algorithm

1. First mutating call of a session: `ckpt_baseline()` walks and ingests files within the tracking caps.
2. Start of every mutating call: `ckpt_file_step(by = "external")` absorbs edits made outside gptr since the last
   walk. They update the tracker but are **never undone** by a rewind.
3. Before the call: predicted literal paths (`tg$files`) that are not tracked and are at most
   `gptr.checkpoint_capture_max` get their current content ingested.
4. After the call: walk and diff against the tracker (size, mtime, racy-clean hash check), giving created,
   modified and deleted paths. Post-images are ingested (at most `gptr.checkpoint_capture_max`) and pre-images come
   from the tracker. Links are recorded as not restorable, and files without a pre-image as not restorable.
5. Adaptive scanning: if a walk exceeds `gptr.checkpoint_scan_budget` (250 ms), switch that session to scanning
   once per turn plus the predicted paths, and say so once.
6. `edit`, `write` and `apply_patch` already hold the old bytes. They ingest the pre-image directly (no walk
   needed for their own paths), within the same cap.

### 3.6 Undo, redo and the 3-way rule

- **Object**: restore only if the current binding's address equals the recorded post address. Otherwise
  "conflict, kept" unless `force = TRUE`.
- **Created object**: remove only if unchanged since.
- **Removed object**: restore only if still absent.
- **File**: restore only if the current hash equals `post` (or, over the cap, size and mtime equal
  `post_size`/`post_mtime`). A deleted file is restored only if still absent. A created file is removed only if
  unchanged, and its content stays in the store.
- **State items**: restore each only if its current value equals its post value.
- **Redo** is the mirror image: apply post-images (redo images for objects, `post` blobs for files) when the
  current state equals the pre state.
- **Order**: records between the leaf and the lowest common ancestor are undone newest first. Records between
  the lowest common ancestor and the target are redone oldest first.

### 3.7 Settings (registered as `gptr_setting()` specs, G1 kind 21; values via `gptr_config()`)

| Setting | Default | Meaning |
|---|---|---|
| `gptr.checkpoint` | `"on"` (`"files"`, `"off"`) | master switch; `plan` mode forces conversation-only |
| `gptr.undo_max_bytes` | `1e9` | held in-memory image bytes (unshared) per session (18's name and default kept) |
| `gptr.undo_capture_max` | `1e8` (= 18's `gptr.protect_size`) | objects up to this size are captured even when not predicted |
| `gptr.undo_spill_max` | `2e9` | largest object image written to disk (eager or at turn end) |
| `gptr.undo_turns` | `20` | object images older than this many turns are dropped |
| `gptr.checkpoint_disk_bytes` | `2e9` (workspace) / `1e9` (tempdir) | blobs plus spilled images; LRU pruning over sessions |
| `gptr.checkpoint_days` | `30` | age-based retention (Claude Code's default) |
| `gptr.checkpoint_turns` | `100` | file checkpoints per session (Claude Code's count) |
| `gptr.checkpoint_track_file_max` | `1e6` | baseline per-file cap (opencode tracks non-ignored untracked files up to 2 MiB each; Codex ignored untracked files over 10 MiB) |
| `gptr.checkpoint_track_total` | `1e8` | baseline total |
| `gptr.checkpoint_capture_max` | `5e7` | pre-images of predicted paths and post-images |
| `gptr.checkpoint_scan_budget` | `0.25` s | switch to per-turn scanning above this walk time |
| `gptr.checkpoint_rng` | `TRUE` | restore `.Random.seed` (3-way) when `envir` is the global environment |
| `gptr.checkpoint_close_devices` | `FALSE` | close devices opened by an undone turn |

### 3.8 Document grammar additions (report 14 §3.1)

- Header key `status=undone` (and optionally `rewind=<entry id>`). In `.R` and in agent code of console
  transcripts, every body line gets the prefix `#~ `, and in console transcripts the prompt line does too.
- Rmd/qmd agent chunks: add the chunk option `eval=FALSE` (`#| eval: false`) and keep the code visible.
- ipynb: `metadata.gptr.status = "undone"` plus `#~ ` source lines.
- A rewind in a console transcript becomes a comment line:
  `# /rewind 1 (keep turns 1-1): 5 items restored or removed, 1 not restored (session log 71a62c58)`.
- New row for 14 §4.4.2:

| block state | `auto` | `replay` | `live` | `record` |
|---|---|---|---|---|
| undone (`status=undone`) | skip, zero tokens, one message "block undone by /rewind; edit or delete the prompt, or run live to regenerate" | skip | run, no write | regenerate in place (the block becomes live) |

### 3.9 Model-facing text

- Notice appended to a tool result (only when needed):
  `note: <name> (<size>) was <overwritten|modified|removed> without an undo copy (<reason>).`
- After a partial rewind, the leading block of the next user message uses G4 §3.5's `<workspace_changes>`,
  computed as the diff between the snapshot recorded at the target and now, plus file lines:

```
<workspace_changes since="turn 3" reason="rewind">
~ pbmc <Seurat> 3,012,448 x 33,538, 5.1 GB (not restored: over the undo budget; current value is from turn 5)
~ cfg <environment> (not restored: reference object)
file data/huge.bin (not restored: over the checkpoint size cap)
</workspace_changes>
```

---

## 4. Recommended design for gptr

### 4.1 Where checkpoints hook in

- **Tool dispatcher** (G1 `tool` kind, report 02 loop). For every tool whose spec is not `annotations$read_only`,
  it calls every registered `checkpointer` in registry order:
  - `before(call, ctx)` returns a token;
  - `after(call, ctx, token)` returns a record fragment;
  - the fragments are merged into one `gptr.checkpoint` entry appended after the tool result.

  Built-in checkpointers: `objects`, `files`, `state`, `artifacts`.
- **Session store**. Records are tree nodes (§3.1). `gptr_rewind()` walks the tree and calls
  `undo(record, ctx)` / `redo(record, ctx)` on the checkpointer that wrote each fragment.
- **Context assembler (G4)**:
  - After a rewind, the next request is the path to the target plus the new user message.
  - The prefix guard (G4 §4.3.5) uses as its reference the last request whose element view ends at or before the
    target, and it resets on the `session_tree` event, so a rewind is not counted as a `cache_break`.
  - Partial rewinds add the `<workspace_changes reason="rewind">` block.
- **Document writer (14)**. On `session_tree` it rewrites the affected blocks (§4.4) through the atomic,
  md5-checked `doc_write()`. Under Rscript the write is deferred (14 §4.3).
- **Read registry (11 stale files)**. Entries are stamped with their entry id; a rewind drops entries recorded
  after the target, so the model must re-read before editing on the new branch.

### 4.2 Public API (two new exports; D-28 prefix; no collision in 662 installed packages, `p7_names.txt`)

```r
# Rewind the ONE session object (S-8): a branch-in-place, never an edit, never a new object.
gptr_rewind(s, turn = -1L, to = NULL,
            restore = c("all", "conversation", "workspace"),
            force = FALSE, preview = FALSE, summarize = FALSE)
#   turn    : integer. Negative = relative (-1 = undo the last turn); 0 = before the first turn;
#             positive k = keep turns 1..k of the active path.
#   to      : an entry id (from gptr_checkpoints(s)): any node, including abandoned branches (redo),
#             or a tool-call boundary inside a turn.
#   restore : Claude Code's three actions. "workspace" = undo files, objects and state but keep
#             the conversation (Claude "Restore code").
#   force   : also restore items changed by someone else since (3-way conflicts).
#   preview : return the plan (what would be restored or not, bytes, time estimate); change nothing.
#   summarize : append a Pi-style branch_summary written by a model (costs one call; default FALSE).
# Returns s invisibly. s$last_rewind holds the report; s$editor_text holds the undone prompt.
# Signals gptr_warning_rewind_partial when some items were not restored.
# Signals gptr_error_busy when s is running (background) and gptr_error_rewind_range when out of range.

gptr_checkpoints(s, all = FALSE)
#   data.frame: turn, id, time, prompt (truncated), objects (changed/restorable), files (changed/restorable),
#   held_mb (memory), disk_mb, branch ("active" | "abandoned"; all = TRUE lists abandoned ones).
#   print() is compact; the console /checkpoints shows it.

# Existing export, semantics fixed here: an explicit new session object (S-8 fork).
gptr_fork(s, turn = NULL, restore = FALSE)
#   turn = NULL forks at the leaf; restore = TRUE also rewinds the SHARED workspace to that turn
#   (this affects s too, so it asks in interactive use). The fork's workspace undo starts at the fork point:
#   object images belong to s.
```

Console (`gptr()` REPL, report 18):

| Command | Action |
|---|---|
| `/undo` | `gptr_rewind(s, -1)`. Shows the preview first when anything is not restorable. The undone prompt is printed and pushed to history (`utils::timestamp()`, 18), so Up recalls it (`readline()` cannot pre-fill). |
| `/redo` | `gptr_rewind(s, to = <from of the last gptr.rewind>)` |
| `/rewind` | Menu via `gptr_ui` select (18 §4.9): the turns of the active path with prompt and change counts. Then Claude's actions: "Restore code and conversation", "Restore conversation", "Restore code", "Summarize from here" (Pi summary), "Never mind". |
| `/rewind 3` | `gptr_rewind(s, 3)` |
| `/checkpoints` | `print(gptr_checkpoints(s))` |

Examples in house style:

```r
s = gptr("Normalise pbmc and run PCA", pbmc)
s |> gptr("Regress out percent.mt while scaling")
s |> gptr_rewind() |> gptr("Do not regress anything out; keep 30 PCs")    # undo, then steer

gptr_checkpoints(s)
s |> gptr_rewind(to = "a4c67d61")                                          # redo the abandoned branch

# a System 1 judge decides whether to keep the agent's last turn
imp = gptr("Impute the missing values in mice", mice)
ok = gptr("Do the imputed columns keep the original distributions?",
          gptr_describe(mice), model = jev)
if (!ok) {
  imp |> gptr_rewind() |> gptr("Mean imputation was rejected; use predictive mean matching")
}

alt = gptr_fork(s, turn = 1)                                               # explicit second session
alt |> gptr("Try SCTransform instead of LogNormalize")
```

### 4.3 Semantics of `/undo`, `/rewind <turn>` and `gptr_rewind(s, turn)`

- **Turn.** One `gptr()` call on the session: the prompt plus all agent actions until it settles. Steering
  messages delivered mid-run belong to the running turn, as in Claude Code ("Messages sent mid-turn not
  checkpointed"). Records exist per tool call, so `to =` can target a tool-call boundary.
- **Target.** Keeping turns `1..k` means the target is the parent of turn `k + 1`'s user message (Pi: selecting a
  user message sets the leaf to its parent). `turn = 0` means a null target (a new root).
- **Workspace.** Undo, newest first, the records on the path from the leaf up to the lowest common ancestor.
  Redo, oldest first, the records from the lowest common ancestor down to the target (for `to =` on another
  branch). Displaced current values become redo images, so undo and redo swap values by reference and never copy.
- **Conversation.** Append `gptr.rewind` (parent = target), which is the new leaf. Nothing is deleted.
  - The model's next request is the path to the target plus the new prompt.
  - With a full restore the model is told nothing: that costs 0 tokens and keeps the prefix byte-identical, so
    the cache can be reused (LIKELY; G4 decides where cache writes go).
  - With a partial restore, the `<workspace_changes reason="rewind">` block is added.
- **Same object.** Every binding that refers to `s` sees the rewound session (D-05 reference semantics). The
  abandoned branch stays in `s` (`gptr_checkpoints(s, all = TRUE)`) and in the JSONL. A second session object
  exists only through `gptr_fork()`, so continuing never silently forks (S-8).
- **Several sessions on one workspace.** The 3-way rule protects objects and files another session or the user
  changed after the turn; each session undoes only what it recorded.
- **After an R restart.** Files are restorable from blobs. Objects are restorable only from spilled images and only
  with `force = TRUE`, because the post address can no longer be checked. In-memory images are gone, and this is
  reported.
- **Non-interactive.** No prompts. `gptr_rewind()` does what it is asked, and a partial restore raises the classed
  warning; `preview = TRUE` lets scripts decide.
- **Plan mode.** Conversation-only, because plan mode never changed the workspace (18: code runs in a child
  environment, edits denied).
- **Artifacts (17).** The record stores `artifact.json$current` before and after. Undo resets `current` and
  restarts the previous version on the same port if it was running. `vNNN/` directories are immutable and kept
  for redo, and they are pruned with the retention settings.
- **Sub-agents (15).**
  - Inline sub-agents write into `new.env(parent = envir)`. Their exports into the parent's environment happen
    inside the parent's `agent` tool call, so the parent's record covers them.
  - Worker and CLI sub-agents' file changes are caught by the walk after the call.
  - Child sessions are history and are not rewound.
- **Compaction (G4).** Rewinding past a compaction entry returns the uncompacted path. If that exceeds G4's
  trigger, compaction runs before the next request, and the cache may be cold.
- **Caches (14).** The S2 answer cache entry of an undone block is pruned by `gptr_cache("prune")`, because its
  block is no longer live. S1 caches are unaffected.

### 4.4 How rewinds appear in the runnable history document

- **Console transcripts** (14 §3.4, generated by gptr). The file is a projection of the tree.
  - Normally gptr only appends.
  - On a rewind it rewrites the file once, atomically, with the md5 conflict check: undone turns become inert
    (`#~ gptr("...")`, `status=undone`, `#~ ` code), and a `# /rewind ...` comment line is appended.
  - `source()` then replays the rewound state and never re-asks an undone prompt (VERIFIED, 5.6).
  - A redo makes the blocks live again.
- **User-authored scripts, Rmd, qmd and ipynb**. The user's `gptr()` statements are never touched. Only the owned
  agent blocks of undone turns change: marked `status=undone` and made inert, following the §3.8 row.
  - A `gptr_rewind()` call the user wrote into the script stays as written. In replay it moves the reconstructed
    session's leaf and is a workspace no-op, because the blocks it undid are already inert.
  - In a first live run the call really restores, and it then marks the blocks.
  - Either way the final state of a `source()` equals the live state, apart from the items the rewind report lists
    as not restored.
- **Machine form (D-09).** The JSONL stays byte-append-only (VERIFIED): the rewind is data, not an edit.

### 4.5 Defaults and budgets per permission mode (D-11)

| | `plan` | `manual` | `edits` | `auto` | non-interactive (`Rscript`, knitr, CI) |
|---|---|---|---|---|---|
| object capture | off (child env) | on | on | on | on; spill only with a consented `.gptr/`, otherwise memory only |
| file checkpoints | off (edits denied) | on | on | on | on (tempdir without `.gptr/`) |
| predicted change that cannot be captured (over budget, reference object, extptr) | n/a | the permission prompt adds "cannot be undone" and offers "spill first (~0.3-0.7 s per GB)" when spillable | same as manual (R code still asks) | runs; 25-token notice; logged; level-4 guard unchanged (18) | runs; notice; logged |
| `gptr.undo_max_bytes` | - | 1e9 | 1e9 | 1e9 | 1e9 (5e8 suggested for knitr renders) |
| scan cadence | - | after every mutating call (adaptive) | same | same | per turn |
| `/undo`, `/rewind` | conversation only | full | full | full | `gptr_rewind()` only |

Why these defaults:
- Capture by reference costs milliseconds (§2.4). A copy is paid only for in-place edits of objects of at most
  100 MB (≤ 0.03 s, estimated from 0.11-0.26 s/GB) or of predicted targets within the budget.
- 18's budget keeps held memory at most 1 GB.
- Everything above the budget is surfaced *before* it happens in manual and edits modes, which is what makes
  the 5 GB Seurat case safe.

### 4.6 Extension API (S-11): checkpoints are plugins

```r
# New registry kind (G1 section 3.1 row 24), registered by the built-ins exactly like third parties:
gptr_checkpointer(
  name,                         # "files", "objects", "state", "artifacts", "git" (optional plugin)
  scope = c("files", "objects", "state", "artifacts", "other"),
  before = function(call, ctx) NULL,             # token (e.g. predicted targets, eager images)
  after  = function(call, ctx, token) NULL,      # record fragment (JSON-able list; big data by key)
  undo   = function(fragment, ctx, force) character(),   # report lines
  redo   = function(fragment, ctx, force) character(),
  prune  = function(live_keys, ctx) NULL,
  describe = function(fragment) character())     # one line per item for previews and /checkpoints
# Contract: never throws into the loop (a failing checkpointer marks its fragment "not restorable");
# before/after run inside the tool's permission-approved window; sequential tools only (02, 15).

# S3 generic for class-directed capture (same mechanism as gptr_describe(), G1 row 13):
gptr_preimage = function(x, name, ctx, ...) UseMethod("gptr_preimage")
#   default: value semantics -> "by_reference"; environment/externalptr -> gptr_unrestorable("reason")
#   gptr_preimage.data.table: data.table::copy(x) when ctx$predicted_byref, else "by_reference"
#   packages may add methods (e.g. an R6 class with a deep clone) with gptr in Suggests (delayed registration)

# Events (G1 section 3.2): Pi names where the semantics match
#   checkpoint            (gptr, notify)      payload: turn, tool_call_id, summary counts
#   session_before_tree   (Pi, cancel/patch)  payload: plan (preview); a handler may cancel or supply a summary
#   session_tree          (Pi, notify)        payload: from, to, report
```

- Pi precedent: the `git-checkpoint.ts` example is a 53-line extension on `turn_start` / `session_before_fork`.
- A **shadow-git plugin** (`git --git-dir=.gptr/checkpoints/git --work-tree=.`) is an optional backend for very
  large trees (git's stat cache and delta compression). It is optional because the git binary is not guaranteed
  on Windows (REQ-01/REQ-03). It is never pointed at the user's `.git`. Not measured (UNCERTAIN performance).

### 4.7 Token-efficiency statement (S-12)

| Choice | Token cost | Alternative |
|---|---|---|
| harness-side checkpoints, records never in context | 0 per turn | a "todo/undo" tool the model manages: schema tokens every request plus calls |
| restore in R instead of asking the model to revert | 0 | 4,349 tokens per file, impossible for objects |
| full restore: silent, byte-identical prefix | 0; cache reuse within TTL LIKELY (depends on cache-write placement, G4) | Pi summary: 21 + summary + a call |
| partial restore note (G4 diff format) | 87 for 3 items | none |
| notice for uncapturable changes | 25, rare | none |
| recompute recipe | printed to the user, not sent | the model re-deriving the pipeline |

### 4.8 Positions on the decision register and cross-track amendments

- **D-05 / S-8.**
  - Rewind is an explicit branch-in-place on the same object.
  - `gptr_fork(s, turn, restore)` is the explicit fork, and its recording in the history document is a comment
    line plus a new transcript for the fork.
  - `gptr_rewind()` returns `s` invisibly for pipes.
- **D-09.** The checkpoint index is part of the machine form (custom entries). Blobs live in a project store;
  object images are process-local unless spilled.
- **D-10.** `.gptr/checkpoints/` or tempdir. No blobs in `R_user_dir` and nothing in `.git`.
- **D-11.** The §4.5 table. "Cannot be undone" becomes part of the permission prompt.
- **D-02.** Stores and records are environments (S3 plus environments); records must be mutable for undo and redo
  annotations (VERIFIED in the prototype).
- **Conflict 18 (copy-safety).** Amend: gptr may hold (a) pre-images of bindings the agent changed, as environment
  bindings, within `gptr.undo_max_bytes`, released with `rm()` and defused; (b) nothing else. Add c03, c06, c12
  and the serialize case to the tracemem suite.
- **Report 18 §4.8.** Replaced by §3.4 here. 18 A.13's "no copy" is wrong for the next edit.
- **Report 20 §4.3.** Pre-edit copies go to the shared store (§3.3), not per-session directories.
- **Report 11.** The stale-file registry is provided by the tracker and rolled back on rewind. Hard links: never
  written through (Claude parity) unless `atomic = FALSE`.
- **Report 14.** Add the undone row and the grammar key (§3.8). Console transcripts are append-only except at
  rewinds.
- **G4.** Reset the prefix guard on `session_tree`; add `reason="rewind"` to `<workspace_changes>`.
- **Report 17.** Artifact records (§4.3).
- **Report 21.** Pre-images make change detection exact for captured value objects; sampled fingerprints remain
  for uncaptured objects above the capture cap.
- **Conventions.** Add an area prefix `ckpt` (R/ckpt-objects.R, ckpt-files.R, ckpt-state.R, ckpt-rewind.R).
  Target prediction lives with the risk classifier in `perm`. Add `methods` to Imports: a base package, needed for
  `methods::slotNames()`.

---

## 5. Verified R prototypes

All files are in `scratchpad/work/G7/`. `run_all.sh` re-ran every script below in fresh `Rscript --vanilla`
processes (with `R_LIBS` pointing at the private library) and wrote `out/final/*.txt`. The outputs embedded here
are those files, verbatim. The load average at the end of the final run was `23:20  up 7 days, 19:48, 1 user, load averages: 22.94 14.79 11.89`.

### 5.0 Driver

```sh
#!/bin/sh
# run_all.sh -- re-run every G7 prototype in fresh Rscript --vanilla processes; outputs in out/final/
set -e
W=/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7
export R_LIBS=/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib
O=$W/out/final; rm -rf $O; mkdir -p $O
cd $W/p1
Rscript --vanilla run_cases.R > $O/p1_cases.txt 2>&1
for v in v1 v4 v5; do for c in 0 1; do Rscript --vanilla dbg_ref3.R $v $c; done; done > $O/p1_defuse_variants.txt 2>&1
for v in top_default top_ascii byname_default byname_ascii byname_saverds; do Rscript --vanilla dbg_ser.R $v; done > $O/p1_serialize.txt 2>&1
Rscript --vanilla c06b_finalizer.R 2>&1 | grep -v '^NULL$' > $O/p1_finalizer.txt
cd $W/p2
for sz in 10 1000; do for s in none byref byref_spill disk_ser disk_rds recompute; do for o in inplace replace remove; do
  Rscript --vanilla measure.R $sz $s $o; done; done; done > $O/p2_matrix.txt 2>&1
for o in meta normalize subset; do for s in none byref; do Rscript --vanilla seurat.R $s $o 2>&1 | grep '^seurat'; done; done > $O/p2_seurat.txt
Rscript --vanilla capture_all.R > $O/p2_capture_all.txt 2>&1
cd $W/p3
Rscript --vanilla bench_hash.R > $O/p3_bench_hash.txt 2>&1
Rscript --vanilla test_files.R > $O/p3_test_files.txt 2>&1
Rscript --vanilla bench_tree.R > $O/p3_bench_tree.txt 2>&1
cd $W/p4
Rscript --vanilla test_state.R > $O/p4_state.txt 2>&1
cd $W/p5
Rscript --vanilla test_session.R > $O/p5_session.txt 2>&1
cd $W/p7
Rscript --vanilla tokens.R > $O/p7_tokens.txt 2>&1
Rscript --vanilla recipe.R > $O/p7_recipe.txt 2>&1; rm -f Rplots.pdf
cd /private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/design/critic
Rscript --vanilla undo_copy.R 2>&1 | sed -E 's/0x[0-9a-f]+/0x…/g' > $O/p0_critic_undo_copy.txt
uptime > $O/load.txt
echo done
```

### 5.1 The critic's check, reproduced

`scratchpad/work/design/critic/undo_copy.R` (the critic's file, unchanged):

```r
e = new.env()
local({ x = runif(1e6) }, envir = e)
invisible(tracemem(e$x))
cat("in-place edit without snapshot:\n")
local({ x[1] = 0 }, envir = e)
snap = mget("x", envir = e)          # /undo snapshot as proposed in report 18
cat("in-place edit after mget() snapshot:\n")
local({ x[2] = 0 }, envir = e)
cat("old value kept in snapshot:", snap$x[2] != 0, "\n")
```

Output (addresses masked):

```text
in-place edit without snapshot:
in-place edit after mget() snapshot:
tracemem[0x… -> 0x…]: eval eval eval eval eval.parent local 
old value kept in snapshot: TRUE 
```

### 5.2 P1: copy-safe object pre-images

Library `p1/ckpt_obj.R`:

```r
# ckpt_obj.R -- G7 prototype: R-object pre-images for gptr checkpoints.
# Base R + rlang (obj_address). House style: "=" for assignment, "|>" for pipes.
#
# Design rules (report 12 C2 "leaf / formatter / by-name", extended for checkpoints):
#   * Pre-images are held as BINDINGS in a private environment (store$slots), never in a list.
#     A binding is released with rm(), which lowers the reference count again; a list that is
#     dropped is not (this file's test p1/run_cases.R, cases c03 vs c05).
#   * Every function that touches an object addresses it by name (envir + name) and passes
#     get(...) straight into assign() or into a thin .Call wrapper (rlang::obj_address).
#   * While a pre-image is held, a value-semantics object cannot be modified in place: any
#     modification duplicates it. So "address changed" <=> "modified or rebound" (exact change
#     detection for captured objects). By-reference mutation (environments, R6, data.table
#     set()/:=, external pointers) is the exception and is classified separately.

ckpt_store = function(dir = NULL) {
  s = new.env(parent = emptyenv())
  s$slots = new.env(parent = emptyenv())   # key -> object (pre-image or redo image)
  s$index = data.frame(key = character(), name = character(), role = character(),
                       bytes = numeric(), where = character(), file = character(),
                       stringsAsFactors = FALSE)
  s$seq = 0L
  s$dir = dir                              # spill directory (NULL = no spilling)
  s
}

.ckpt_key = function(store, prefix) {
  store$seq = store$seq + 1L
  sprintf("%s%06d", prefix, store$seq)
}

# Kind of a binding without forcing promises or calling active bindings.
ckpt_binding_kind = function(envir, names) {
  act = rlang::env_binding_are_active(envir, names)
  lazy = rlang::env_binding_are_lazy(envir, names)
  ifelse(act, "active", ifelse(lazy, "promise", "value"))
}

# Leaf: reference semantics? (environment, R6, RefClass, external pointer, data.table)
.ckpt_leaf_semantics = function(x) {
  t = typeof(x)
  if (t %in% c("environment", "externalptr", "weakref", "bytecode")) return("reference")
  if (isS4(x) && is.environment(x)) return("reference")        # RefClass objects (S4 + env)
  if (inherits(x, "data.table")) return("by_ref_capable")      # value unless set()/:= is used
  if (inherits(x, "R6")) return("reference")
  "value"
}
ckpt_semantics = function(envir, name) .ckpt_leaf_semantics(get(name, envir = envir, inherits = FALSE))

# Capture by reference: bind the current value of each name into store$slots.
# Returns the pending table used by ckpt_settle(). No copy is made here.
ckpt_capture = function(store, envir, names) {
  n = length(names)
  keys = character(n); addr = character(n)
  for (i in seq_len(n)) {
    k = .ckpt_key(store, "pre")
    assign(k, get(names[i], envir = envir, inherits = FALSE), envir = store$slots)
    keys[i] = k
    addr[i] = rlang::obj_address(get(k, envir = store$slots, inherits = FALSE))
  }
  data.frame(name = names, key = keys, address = addr, stringsAsFactors = FALSE)
}

# After the tool call: release pre-images of unchanged bindings (refcount goes back down),
# keep the others. Returns one row per captured name with its status.
ckpt_settle = function(store, envir, pending) {
  status = character(nrow(pending)); post = rep(NA_character_, nrow(pending))
  for (i in seq_len(nrow(pending))) {
    nm = pending$name[i]
    if (!exists(nm, envir = envir, inherits = FALSE)) {
      status[i] = "removed"
    } else {
      post[i] = rlang::obj_address(get(nm, envir = envir, inherits = FALSE))
      status[i] = if (identical(post[i], pending$address[i])) "unchanged" else "changed"
    }
    if (status[i] == "unchanged") rm(list = pending$key[i], envir = store$slots)
  }
  keep = status != "unchanged"
  if (any(keep)) {
    store$index = rbind(store$index, data.frame(
      key = pending$key[keep], name = pending$name[keep], role = "pre",
      bytes = NA_real_, where = "memory", file = NA_character_, stringsAsFactors = FALSE))
  }
  data.frame(name = pending$name, key = pending$key, status = status,
             pre_address = pending$address, post_address = post, stringsAsFactors = FALSE)
}

# Bytes of a pre-image that are NOT shared with the current value (structural sharing through
# list elements / data.frame columns and S4 slots), depth-limited. Closure-free recursion:
# top-level functions whose frames bind at most one node and are cleaned on return (report 12
# C2); accumulators live in emptyenv()-parented environments, never in lists.
.ckpt_leaf_children = function(x) {                      # "list", "s4" or "leaf"
  if (is.environment(x)) return("leaf")
  if (isS4(x)) return("s4")
  if (is.list(x)) return("list")
  "leaf"
}
.ckpt_addr_collect = function(x, d, seen) {
  assign(rlang::obj_address(x), TRUE, envir = seen)
  if (d <= 0L) return(invisible())
  k = .ckpt_leaf_children(x)
  if (k == "list") for (j in seq_len(length(x))) .ckpt_addr_collect(.subset2(x, j), d - 1L, seen)
  if (k == "s4") for (sl in methods::slotNames(class(x)))
    .ckpt_addr_collect(attr(x, sl, exact = TRUE), d - 1L, seen)
  invisible()
}
.ckpt_unshared_walk = function(x, d, seen, acc) {
  if (exists(rlang::obj_address(x), envir = seen, inherits = FALSE)) return(invisible())
  k = .ckpt_leaf_children(x)
  if (d <= 0L || k == "leaf") {
    acc$bytes = acc$bytes + as.numeric(utils::object.size(x))
    return(invisible())
  }
  acc$bytes = acc$bytes + 64                              # container header (approximate)
  if (k == "list") for (j in seq_len(length(x))) .ckpt_unshared_walk(.subset2(x, j), d - 1L, seen, acc)
  if (k == "s4") for (sl in methods::slotNames(class(x)))
    .ckpt_unshared_walk(attr(x, sl, exact = TRUE), d - 1L, seen, acc)
  invisible()
}
ckpt_unshared_bytes = function(store, key, envir, name, depth = 4L) {
  seen = new.env(parent = emptyenv()); acc = new.env(parent = emptyenv()); acc$bytes = 0
  if (exists(name, envir = envir, inherits = FALSE))
    .ckpt_addr_collect(get(name, envir = envir, inherits = FALSE), depth, seen)
  .ckpt_unshared_walk(get(key, envir = store$slots, inherits = FALSE), depth, seen, acc)
  acc$bytes
}

# Spill one held image to disk and release it from memory.
ckpt_spill = function(store, key, xdr = FALSE) {
  stopifnot(!is.null(store$dir))
  f = file.path(store$dir, paste0(key, ".rdsx"))
  con = file(f, "wb")
  serialize(get(key, envir = store$slots, inherits = FALSE), con, ascii = FALSE, xdr = xdr)  # explicit ascii: see p1_serialize.txt
  close(con)
  rm(list = key, envir = store$slots)
  i = match(key, store$index$key)
  store$index$where[i] = "disk"; store$index$file[i] = f
  invisible(f)
}

# Restore `name` from image `key` (memory or disk). The displaced current value becomes a
# redo image (by reference; no copy). `expect` is the post-image address recorded at settle
# time: if the binding changed since (user or another session), refuse unless force = TRUE.
ckpt_restore = function(store, envir, name, key, expect = NULL, force = FALSE) {
  i = match(key, store$index$key)
  if (is.na(i)) return(list(ok = FALSE, reason = "no pre-image"))
  now = if (exists(name, envir = envir, inherits = FALSE))
    rlang::obj_address(get(name, envir = envir, inherits = FALSE)) else NA_character_
  if (!force && !is.null(expect) && !identical(now, expect))
    return(list(ok = FALSE, reason = "conflict: changed after the checkpoint"))
  redo = NA_character_
  if (!is.na(now)) {
    redo = .ckpt_key(store, "redo")
    assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
    store$index = rbind(store$index, data.frame(key = redo, name = name, role = "redo",
      bytes = NA_real_, where = "memory", file = NA_character_, stringsAsFactors = FALSE))
  }
  if (store$index$where[i] == "memory") {
    assign(name, get(key, envir = store$slots, inherits = FALSE), envir = envir)
    rm(list = key, envir = store$slots)
  } else {
    con = file(store$index$file[i], "rb")
    assign(name, unserialize(con), envir = envir)
    close(con)
  }
  store$index = store$index[-i, , drop = FALSE]
  list(ok = TRUE, redo = redo)
}

# Undo of a creation: remove the binding, keep the value as a redo image.
ckpt_uncreate = function(store, envir, name) {
  redo = .ckpt_key(store, "redo")
  assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
  rm(list = name, envir = envir)
  store$index = rbind(store$index, data.frame(key = redo, name = name, role = "redo",
    bytes = NA_real_, where = "memory", file = NA_character_, stringsAsFactors = FALSE))
  redo
}

# Drop images (budget eviction or session end). rm() releases the references.
ckpt_drop = function(store, keys) {
  mem = intersect(keys, ls(store$slots, all.names = TRUE))
  for (k in mem) ckpt_defuse(store, k)                  # defuse = release children, then unbind
  files = store$index$file[store$index$key %in% keys & store$index$where == "disk"]
  if (length(files)) unlink(files)
  store$index = store$index[!store$index$key %in% keys, , drop = FALSE]
  invisible(keys)
}

# Release the children of a held list / S4 pre-image before dropping it. When R frees a list
# by garbage collection it does not decrement its elements' reference counts, so elements
# still shared with the user's current object would stay "sticky" (one extra copy on the
# user's next in-place edit; test c12). Take the image out of the store (its only reference
# then is the local binding), then overwrite each element in place: SET_VECTOR_ELT and
# attribute replacement decrement the old child. Complex assignment through the store
# (slots[[key]][[j]] = ...) does NOT work: it duplicates the container first (dbg_ref3.R v1).
ckpt_defuse = function(store, key) {
  v = get(key, envir = store$slots, inherits = FALSE)
  rm(list = key, envir = store$slots)
  k = .ckpt_leaf_children(v)
  if (k == "list") {
    n = length(v)
    for (j in seq_len(n)) v[[j]] = FALSE
  } else if (k == "s4") {
    for (sl in methods::slotNames(class(v))) attr(v, sl) = FALSE
  }
  invisible(key)
}
```

Copy-safety matrix `p1/run_cases.R`:

```r
# run_cases.R -- G7 copy-safety matrix. Each case runs in a FRESH Rscript --vanilla process.
# A case prints "EDIT <label>: in place" or "EDIT <label>: COPY" for a top-level in-place edit
# (address before vs after, confirmed by tracemem output). All ckpt_* functions are
# byte-compiled first (compiler::cmpfun), as they would be in an installed package.
# House style: "=" and "|>".
here = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p1"
lib = file.path(here, "ckpt_obj.R")

prelude = sprintf('
suppressMessages({ source("%s") })
for (f in ls(pattern = "^[.]?ckpt_", all.names = TRUE)) assign(f, compiler::cmpfun(get(f)))
A = rlang::obj_address
# the agent evaluator: top-level expressions of model code, values never kept (report 12 A12)
agent = function(code, envir) {
  for (e in parse(text = code, keep.source = FALSE)) eval(e, envir)
  invisible(NULL)
}
agent = compiler::cmpfun(agent)
edit_check = function(label, before, after) cat(sprintf("EDIT %%-44s %%s\\n", label,
  if (identical(before, after)) "in place" else "COPY"))
', lib)

cases = list(
  c01_baseline = '
x = runif(1e6); invisible(tracemem(x))
a0 = A(x); x[1] = 0; edit_check("user edit, no gptr involvement", a0, A(x))
agent("x[2] = 0", globalenv()); a1 = A(x); x[3] = 0; edit_check("user edit after agent edit (no snapshot)", a1, A(x))',

  c02_mget_held = '
x = runif(1e6); invisible(tracemem(x))
snap = mget("x", envir = globalenv())               # report 18 section 4.8 snapshot
a0 = A(x); agent("x[2] = 0", globalenv()); edit_check("agent edit while mget() snapshot held", a0, A(x))
cat("old value kept in snapshot:", snap$x[2] != 0, "\n")',

  c03_mget_released = '
x = runif(1e6); invisible(tracemem(x))
snap = mget("x", envir = globalenv()); rm(snap); invisible(gc())
a0 = A(x); x[1] = 0; edit_check("user edit after mget() snapshot dropped + gc", a0, A(x))
a1 = A(x); x[2] = 0; edit_check("second user edit", a1, A(x))',

  c04_env_held = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
a0 = A(x); agent("x[2] = 0", globalenv()); edit_check("agent edit while env pre-image held", a0, A(x))
r = ckpt_settle(st, globalenv(), p); cat("settle status:", r$status, "\n")
a1 = A(x); x[3] = 0; edit_check("user edit after settle (pre-image kept)", a1, A(x))',

  c05_env_released = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
agent("y = sum(x)", globalenv())                     # agent reads x only
r = ckpt_settle(st, globalenv(), p); cat("settle status:", r$status, "\n")
a0 = A(x); x[1] = 0; edit_check("user edit after capture + release (rm)", a0, A(x))',

  c06_env_gc_only = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
rm(st, p); invisible(gc())                           # store dropped WITHOUT rm() of the slot
a0 = A(x); x[1] = 0; edit_check("user edit after store garbage-collected", a0, A(x))',

  c07_replace = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
agent("x = x * 2", globalenv())
r = ckpt_settle(st, globalenv(), p); cat("settle status:", r$status, "\n")
a0 = A(x); x[1] = 0; edit_check("user edit of the NEW x (old kept)", a0, A(x))',

  c08_restore = '
x = runif(1e6); invisible(tracemem(x)); x0 = x[5]
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
agent("x = x * 2", globalenv())
r = ckpt_settle(st, globalenv(), p)
res = ckpt_restore(st, globalenv(), "x", r$key, expect = r$post_address)
cat("restored:", res$ok, " value back:", identical(x[5], x0), "\n")
ckpt_drop(st, res$redo)                              # redo image released
a0 = A(x); x[1] = 0; edit_check("user edit after restore + redo dropped", a0, A(x))
res2 = ckpt_restore(st, globalenv(), "x", "pre999999"); cat("missing image:", res2$reason, "\n")',

  c08b_restore_redo_kept = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
agent("x = x * 2", globalenv()); r = ckpt_settle(st, globalenv(), p)
res = ckpt_restore(st, globalenv(), "x", r$key, expect = r$post_address)
a0 = A(x); x[1] = 0; edit_check("user edit after restore (redo image kept)", a0, A(x))',

  c09_conflict = '
x = runif(1e6)
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
agent("x = x * 2", globalenv()); r = ckpt_settle(st, globalenv(), p)
x = x + 1                                            # the USER changes x after the turn
res = ckpt_restore(st, globalenv(), "x", r$key, expect = r$post_address)
cat("restore after user change:", res$ok, "-", res$reason, "\n")',

  c10_spill = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(dir = tempdir()); p = ckpt_capture(st, globalenv(), "x")
agent("x[2] = 0", globalenv()); r = ckpt_settle(st, globalenv(), p)
f = ckpt_spill(st, r$key)
cat("spilled bytes:", file.size(f), "\n")
a0 = A(x); x[3] = 0; edit_check("user edit after pre-image spilled", a0, A(x))
res = ckpt_restore(st, globalenv(), "x", r$key, expect = A(x), force = TRUE)
cat("restored from disk, x[2] != 0:", x[2] != 0, "\n")
ckpt_drop(st, res$redo)
a1 = A(x); x[4] = 0; edit_check("user edit after restore from disk", a1, A(x))',

  c11_saverds_direct = '
x = runif(1e6); invisible(tracemem(x))
save_pre = compiler::cmpfun(function(name, envir, file) saveRDS(get(name, envir = envir), file, compress = FALSE))
save_pre("x", globalenv(), tempfile())
a0 = A(x); x[1] = 0; edit_check("user edit after saveRDS(get()) by name", a0, A(x))',

  c12_list_sharing = '
L = list(a = runif(1e6), b = runif(1e6)); invisible(tracemem(L$a))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "L")
agent("L$new = 1", globalenv())                      # adds an element: shallow copy
r = ckpt_settle(st, globalenv(), p)
cat("settle:", r$status, " unshared bytes held:", ckpt_unshared_bytes(st, r$key, globalenv(), "L"), "\n")
a0 = A(L$a); L$a[1] = 0; edit_check("user edit of column shared with pre-image", a0, A(L$a))
a1 = A(L$b); ckpt_drop(st, r$key); L$b[1] = 0; edit_check("user edit of shared column after drop", a1, A(L$b))',

  c12d_list_defuse = '
L = list(a = runif(1e6), b = runif(1e6)); invisible(tracemem(L$b))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "L")
agent("L$new = 1", globalenv()); r = ckpt_settle(st, globalenv(), p)
ckpt_drop(st, r$key)
a1 = A(L$b); L$b[1] = 0; edit_check("user edit of shared column after defuse+drop", a1, A(L$b))
a2 = A(L$a); L$a[1] = 0; edit_check("user edit of other shared column", a2, A(L$a))',

  c12e_s4_defuse = '
setClass("Big", representation(counts = "numeric", meta = "data.frame"))
obj = new("Big", counts = runif(1e6), meta = data.frame(id = 1:10))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "obj")
agent("obj@meta$cluster = rep(1:2, 5)", globalenv()); r = ckpt_settle(st, globalenv(), p)
ckpt_drop(st, r$key)
a1 = A(obj@counts); obj@counts[1] = 0; edit_check("S4 slot edit after defuse+drop", a1, A(obj@counts))
obj2 = new("Big", counts = runif(1e6), meta = data.frame(id = 1:10))
a2 = A(obj2@counts); obj2@counts[1] = 0; edit_check("S4 slot edit, plain R baseline", a2, A(obj2@counts))',

  c17_attr_edit = '
x = runif(1e6); invisible(tracemem(x))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
a0 = A(x); agent(paste0("attr(x, ", dQuote("unit", FALSE), ") = 1"), globalenv())
edit_check("agent attribute edit while pre-image held", a0, A(x))
r = ckpt_settle(st, globalenv(), p); cat("settle:", r$status, "\n")',

  c12b_list_baseline = '
L = list(a = runif(1e6), b = runif(1e6))
agent("L$new = 1", globalenv())                      # same agent edit, NO checkpoint at all
a1 = A(L$b); L$b[1] = 0; edit_check("user edit of column after L$new (no gptr)", a1, A(L$b))
M = list(a = runif(1e6), b = runif(1e6))
agent("M$a[1] = 0", globalenv())
a2 = A(M$b); M$b[1] = 0; edit_check("user edit of column after M$a[1] (no gptr)", a2, A(M$b))',

  c12c_s4_slot = '
setClass("Big", representation(counts = "numeric", meta = "data.frame"))
obj = new("Big", counts = runif(1e6), meta = data.frame(id = 1:10))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "obj")
agent("obj@meta$cluster = rep(1:2, 5)", globalenv())  # Seurat-style metadata change
r = ckpt_settle(st, globalenv(), p)
cat("settle:", r$status, "| unshared bytes held:", ckpt_unshared_bytes(st, r$key, globalenv(), "obj"),
    "| full object.size:", as.numeric(object.size(obj)), "\n")
cat("counts slot shared with pre-image:", identical(A(obj@counts), A(get(r$key, envir = st$slots)@counts)), "\n")',

  c13_datatable = '
suppressMessages(library(data.table))
dt = data.table(a = runif(1e6))
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "dt")
pre_addr = p$address
agent("dt[, b := a * 2]; set(dt, 1L, \\"a\\", -1)", globalenv())
held = get(p$key, envir = st$slots)
cat("pre-image is the same object:", identical(A(held), A(dt)), "| pre-image has b:", "b" %in% names(held),
    "| pre-image a[1]:", held$a[1], "\n")
rm(held); r = ckpt_settle(st, globalenv(), p); cat("settle status by address:", r$status, "\n")',

  c14_env_r6 = '
e1 = new.env(); e1$v = 1
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "e1")
agent("e1$v = 2", globalenv())
held_v = get(p$key, envir = st$slots)$v
r = ckpt_settle(st, globalenv(), p)
cat("environment: pre-image v =", held_v, "| settle status by address:", r$status,
    "| semantics:", ckpt_semantics(globalenv(), "e1"), "\n")',

  c15_extptr = '
con = file(tempfile(), "w"); p = attr(con, "conn_id")   # a live external pointer
f = tempfile(); saveRDS(p, f); q = readRDS(f)
cat("typeof:", typeof(p), "| identical after serialize:", identical(p, q), "| restored:",
    capture.output(print(q)), "| semantics:", ckpt_semantics(globalenv(), "p"), "\n")
close(con)',

  c16_promise_active = '
delayedAssign("lazy", {cat("FORCED\n"); 1:3}); makeActiveBinding("act", function() {cat("CALLED\n"); 1}, globalenv())
x = 1
k = ckpt_binding_kind(globalenv(), c("lazy", "act", "x")); cat("kinds:", k, "\n")
st = ckpt_store(); p = ckpt_capture(st, globalenv(), c("x")[k[3] == "value"])
cat("promise still lazy:", rlang::env_binding_are_lazy(globalenv(), "lazy"), "\n")'
)

out = character()
for (nm in names(cases)) {
  f = file.path(here, paste0(nm, ".R"))
  writeLines(c(prelude, cases[[nm]]), f)
  res = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = TRUE, stderr = TRUE,
                env = "R_LIBS=/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib")
  n_tm = sum(grepl("^tracemem\\[", res))               # duplications reported by tracemem
  res = res[!grepl("^tracemem\\[", res)]
  out = c(out, paste0("-- ", nm, "  (tracemem duplication events: ", n_tm, ")"), res)
}
writeLines(out)
```

Output:

```text
-- c01_baseline  (tracemem duplication events: 0)
EDIT user edit, no gptr involvement               in place
EDIT user edit after agent edit (no snapshot)     in place
-- c02_mget_held  (tracemem duplication events: 1)
EDIT agent edit while mget() snapshot held        COPY
old value kept in snapshot: TRUE 
-- c03_mget_released  (tracemem duplication events: 1)
EDIT user edit after mget() snapshot dropped + gc COPY
EDIT second user edit                             in place
-- c04_env_held  (tracemem duplication events: 1)
EDIT agent edit while env pre-image held          COPY
settle status: changed 
EDIT user edit after settle (pre-image kept)      in place
-- c05_env_released  (tracemem duplication events: 0)
settle status: unchanged 
EDIT user edit after capture + release (rm)       in place
-- c06_env_gc_only  (tracemem duplication events: 1)
EDIT user edit after store garbage-collected      COPY
-- c07_replace  (tracemem duplication events: 0)
settle status: changed 
EDIT user edit of the NEW x (old kept)            in place
-- c08_restore  (tracemem duplication events: 0)
restored: TRUE  value back: TRUE 
EDIT user edit after restore + redo dropped       in place
missing image: no pre-image 
-- c08b_restore_redo_kept  (tracemem duplication events: 0)
EDIT user edit after restore (redo image kept)    in place
-- c09_conflict  (tracemem duplication events: 0)
restore after user change: FALSE - conflict: changed after the checkpoint 
-- c10_spill  (tracemem duplication events: 1)
spilled bytes: 8000034 
EDIT user edit after pre-image spilled            in place
restored from disk, x[2] != 0: TRUE 
EDIT user edit after restore from disk            in place
-- c11_saverds_direct  (tracemem duplication events: 0)
EDIT user edit after saveRDS(get()) by name       in place
-- c12_list_sharing  (tracemem duplication events: 1)
settle: changed  unshared bytes held: 64 
EDIT user edit of column shared with pre-image    COPY
EDIT user edit of shared column after drop        in place
-- c12d_list_defuse  (tracemem duplication events: 0)
EDIT user edit of shared column after defuse+drop in place
EDIT user edit of other shared column             in place
-- c12e_s4_defuse  (tracemem duplication events: 0)
EDIT S4 slot edit after defuse+drop               COPY
EDIT S4 slot edit, plain R baseline               COPY
-- c17_attr_edit  (tracemem duplication events: 0)
EDIT agent attribute edit while pre-image held    COPY
settle: changed 
-- c12b_list_baseline  (tracemem duplication events: 0)
EDIT user edit of column after L$new (no gptr)    in place
EDIT user edit of column after M$a[1] (no gptr)   in place
-- c12c_s4_slot  (tracemem duplication events: 0)
settle: changed | unshared bytes held: 128 | full object.size: 8001728 
counts slot shared with pre-image: TRUE 
-- c13_datatable  (tracemem duplication events: 0)
pre-image is the same object: TRUE | pre-image has b: TRUE | pre-image a[1]: -1 
settle status by address: unchanged 
-- c14_env_r6  (tracemem duplication events: 0)
environment: pre-image v = 2 | settle status by address: unchanged | semantics: reference 
-- c15_extptr  (tracemem duplication events: 0)
typeof: externalptr | identical after serialize: FALSE | restored: <pointer: 0x0> | semantics: reference 
-- c16_promise_active  (tracemem duplication events: 0)
kinds: promise active value 
promise still lazy: TRUE 
```

Defuse variants `p1/dbg_ref3.R` (why the image is taken out of the store first):

```r
ref_of_b = function() NULL
variants = list(
  v1 = function(slots, key) { n = length(slots[[key]]); for (j in seq_len(n)) slots[[key]][[j]] = FALSE; invisible() },
  v4 = function(slots, key) { v = slots[[key]]; rm(list = key, envir = slots); for (j in seq_along(v)) v[[j]] = FALSE; invisible() },
  v5 = function(slots, key) { v = get(key, envir = slots, inherits = FALSE); rm(list = key, envir = slots)
         n = length(v); for (j in seq_len(n)) v[[j]] = FALSE; invisible() }
)
args = commandArgs(TRUE); vn = args[1]; comp = args[2] == "1"
f = variants[[vn]]; if (comp) f = compiler::cmpfun(f)
L = list(a = runif(1e5), b = runif(1e5))
st = new.env(parent = emptyenv()); assign("k", L, envir = st)
L$new = 1
f(st, "k"); if (exists("k", envir = st)) rm("k", envir = st); invisible(gc())
a0 = rlang::obj_address(L$b); L$b[1] = 0
cat(sprintf("%s compiled=%s: user edit of shared column after defuse: %s\n", vn, comp,
    if (identical(a0, rlang::obj_address(L$b))) "in place" else "COPY"))
```

```text
v1 compiled=FALSE: user edit of shared column after defuse: COPY
v1 compiled=TRUE: user edit of shared column after defuse: COPY
v4 compiled=FALSE: user edit of shared column after defuse: in place
v4 compiled=TRUE: user edit of shared column after defuse: in place
v5 compiled=FALSE: user edit of shared column after defuse: in place
v5 compiled=TRUE: user edit of shared column after defuse: in place
```

`serialize()` stickiness `p1/dbg_ser.R`:

```r
v = commandArgs(TRUE)[1]
A = rlang::obj_address
f = tempfile()
fns = list(
  top_default  = NULL,
  top_ascii    = NULL,
  byname_default = compiler::cmpfun(function(nm, env, f) { con = file(f, "wb"); on.exit(close(con)); serialize(get(nm, envir = env), con, xdr = FALSE); invisible() }),
  byname_ascii   = compiler::cmpfun(function(nm, env, f) { con = file(f, "wb"); on.exit(close(con)); serialize(get(nm, envir = env), con, ascii = FALSE, xdr = FALSE); invisible() }),
  byname_saverds = compiler::cmpfun(function(nm, env, f) { saveRDS(get(nm, envir = env), f, compress = FALSE); invisible() })
)
x = runif(1e6)
if (v == "top_default") { con = file(f, "wb"); serialize(x, con, xdr = FALSE); close(con) }
if (v == "top_ascii") { con = file(f, "wb"); serialize(x, con, ascii = FALSE, xdr = FALSE); close(con) }
if (grepl("^byname", v)) fns[[v]]("x", globalenv(), f)
a0 = A(x); x[1] = 0
cat(sprintf("%-16s user edit after serialising: %s\n", v, if (identical(a0, A(x))) "in place" else "COPY"))
```

```text
top_default      user edit after serialising: COPY
top_ascii        user edit after serialising: in place
byname_default   user edit after serialising: COPY
byname_ascii     user edit after serialising: in place
byname_saverds   user edit after serialising: in place
```

Store finalizer `p1/c06b_finalizer.R`:

```r
suppressMessages(source("ckpt_obj.R"))
A = rlang::obj_address
x = runif(1e6)
st = ckpt_store(); p = ckpt_capture(st, globalenv(), "x")
reg.finalizer(st, function(e) for (k in ls(e$slots, all.names = TRUE)) ckpt_defuse(e, k), onexit = TRUE)
rm(st, p); invisible(gc()); invisible(gc())
a0 = A(x); x[1] = 0
cat("user edit after the session store was dropped (finalizer releases pre-images):", if (identical(a0, A(x))) "in place" else "COPY", "\n")
```

```text
user edit after the session store was dropped (finalizer releases pre-images): in place 
```

`base::serialize` as printed by R 4.4.3 (abridged after the first branch; source of the pitfall):

```text
function (object, connection, ascii = FALSE, xdr = TRUE, version = NULL,
    refhook = NULL)
{
    if (!is.null(connection)) {
        if (!inherits(connection, "connection"))
            stop("'connection' must be a connection")
        if (missing(ascii))
            ascii <- summary(connection)$text == "text"
    }
    ...
```

### 5.3 P2: strategies at 10 MB and 1 GB, Seurat, and capture-all

`p2/measure.R`:

```r
# measure.R <size_mb> <strategy> <op> -- one measurement in a fresh process (G7, P2).
# strategy: none | byref | byref_spill | disk_ser | disk_rds | recompute
# op: inplace (x[1] = 0) | replace (x = x + 1) | remove (rm(x))
# Allocation is measured with Rprofmem() switched on and off at TOP LEVEL (no wrapper
# function around the measured code, so nothing adds references to x).
# House style: "=" and "|>".
here = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7"
suppressMessages(source(file.path(here, "p1/ckpt_obj.R")))
for (f in ls(pattern = "^[.]?ckpt_", all.names = TRUE)) assign(f, compiler::cmpfun(get(f)))
agent = compiler::cmpfun(function(code, envir) {
  for (e in parse(text = code, keep.source = FALSE)) eval(e, envir)
  invisible(NULL)
})
a = commandArgs(TRUE); size_mb = as.numeric(a[1]); strategy = a[2]; op = a[3]
n = size_mb * 1e6 / 8
pf = tempfile(fileext = ".prof")
alloc_mb = function() {                    # sum of allocations > threshold in the last Rprofmem window
  if (!file.exists(pf)) return(0)
  l = readLines(pf, warn = FALSE)
  b = suppressWarnings(as.numeric(sub("^([0-9]+) :.*", "\\1", l)))
  unlink(pf); sum(b, na.rm = TRUE) / 1e6
}
used_mb = function() sum(gc()[, 2])
now = function() proc.time()[[3]]
code = switch(op, inplace = "x[1] = 0", replace = "x = x + 1", remove = "rm(x)")
res = list(size_mb = size_mb, strategy = strategy, op = op)

# warm-up: load rlang and JIT-compile the ckpt path on a small object (an installed package
# would already have rlang loaded as an Import)
w = 1:10; wst = ckpt_store(dir = tempdir()); wp = ckpt_capture(wst, globalenv(), "w")
w[1] = 0L; wr = ckpt_settle(wst, globalenv(), wp); ckpt_drop(wst, wr$key); rm(w, wst, wp, wr)
set.seed(1); x = runif(n); x_5 = x[5]
m0 = used_mb()
disk_file = file.path(tempdir(), "pre.bin")

# ---- 1. capture (before the agent's tool call)
Rprofmem(pf, threshold = 1e5); t0 = now()
if (strategy %in% c("byref", "byref_spill")) {
  st = ckpt_store(dir = tempdir()); pend = ckpt_capture(st, globalenv(), "x")
} else if (strategy == "disk_ser") {
  con = file(disk_file, "wb"); serialize(x, con, ascii = FALSE, xdr = FALSE); close(con)
} else if (strategy == "disk_rds") {
  saveRDS(x, disk_file, compress = FALSE)
}
t1 = now(); Rprofmem(NULL)
res$capture_s = t1 - t0; res$capture_alloc_mb = alloc_mb()
res$disk_mb = if (file.exists(disk_file)) file.size(disk_file) / 1e6 else 0

# ---- 2. the agent's code
Rprofmem(pf, threshold = 1e5); t0 = now()
agent(code, globalenv())
t1 = now(); Rprofmem(NULL)
res$op_s = t1 - t0; res$op_alloc_mb = alloc_mb()

# ---- 3. settle (release or keep) and, for byref_spill, spill the kept pre-image
t0 = now()
if (strategy %in% c("byref", "byref_spill")) {
  r = ckpt_settle(st, globalenv(), pend)
  if (strategy == "byref_spill" && r$status != "unchanged") ckpt_spill(st, r$key)
}
t1 = now(); res$settle_s = t1 - t0
if (strategy == "byref_spill") res$disk_mb = sum(file.size(st$index$file), na.rm = TRUE) / 1e6
res$retained_mb = round(used_mb() - m0, 1)

# ---- 4. the user's next in-place edit (after the turn)
if (exists("x", inherits = FALSE)) {
  Rprofmem(pf, threshold = 1e5); t0 = now()
  x[2] = 0
  t1 = now(); Rprofmem(NULL)
  res$user_edit_s = t1 - t0; res$user_edit_alloc_mb = alloc_mb()
} else { res$user_edit_s = NA; res$user_edit_alloc_mb = NA }

# ---- 5. restore (undo)
t0 = now()
if (strategy %in% c("byref", "byref_spill")) {
  if (r$status == "removed") {
    ok = ckpt_restore(st, globalenv(), "x", r$key)$ok
  } else {
    ok = ckpt_restore(st, globalenv(), "x", r$key, force = TRUE)$ok   # force: the user edited x in step 4
  }
  for (k in st$index$key[st$index$role == "redo"]) ckpt_drop(st, k)
} else if (strategy == "disk_ser") {
  con = file(disk_file, "rb"); x = unserialize(con); close(con); ok = TRUE
} else if (strategy == "disk_rds") {
  x = readRDS(disk_file); ok = TRUE
} else if (strategy == "recompute") {
  set.seed(1); x = runif(n); ok = TRUE       # replay of the recorded creating code (seed recorded)
} else ok = FALSE
t1 = now()
res$restore_s = if (strategy == "none") NA else t1 - t0
res$restored_ok = isTRUE(ok) && exists("x", inherits = FALSE) && identical(x[5], x_5)
res$peak_note = ""
unlink(disk_file)
cat(paste(names(res), unlist(lapply(res, function(v) if (is.numeric(v)) format(round(v, 4), scientific = FALSE) else v)),
          sep = "=", collapse = " "), "\n")
```

Output: 36 runs, one fresh process each; the 1 GB rows ran while the load was rising to about 23:

```text
size_mb=10 strategy=none op=inplace capture_s=0 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=NA restored_ok=FALSE peak_note= 
size_mb=10 strategy=none op=replace capture_s=0 capture_alloc_mb=0 disk_mb=0 op_s=0.001 op_alloc_mb=10 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=NA restored_ok=FALSE peak_note= 
size_mb=10 strategy=none op=remove capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-9.5 user_edit_s=NA user_edit_alloc_mb=NA restore_s=NA restored_ok=FALSE peak_note= 
size_mb=10 strategy=byref op=inplace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.001 op_alloc_mb=10 settle_s=0.001 retained_mb=9.6 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.001 restored_ok=TRUE peak_note= 
size_mb=10 strategy=byref op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.002 op_alloc_mb=10 settle_s=0 retained_mb=9.6 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.001 restored_ok=TRUE peak_note= 
size_mb=10 strategy=byref op=remove capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.002 restored_ok=TRUE peak_note= 
size_mb=10 strategy=byref_spill op=inplace capture_s=0.001 capture_alloc_mb=0 disk_mb=10 op_s=0.001 op_alloc_mb=10 settle_s=0.004 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.004 restored_ok=TRUE peak_note= 
size_mb=10 strategy=byref_spill op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=10 op_s=0.001 op_alloc_mb=10 settle_s=0.003 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.003 restored_ok=TRUE peak_note= 
size_mb=10 strategy=byref_spill op=remove capture_s=0.001 capture_alloc_mb=0 disk_mb=10 op_s=0 op_alloc_mb=0 settle_s=0.004 retained_mb=-9.5 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.004 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_ser op=inplace capture_s=0.003 capture_alloc_mb=0 disk_mb=10 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.002 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_ser op=replace capture_s=0.005 capture_alloc_mb=0 disk_mb=10 op_s=0.001 op_alloc_mb=10 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.002 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_ser op=remove capture_s=0.004 capture_alloc_mb=0 disk_mb=10 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-9.5 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.003 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_rds op=inplace capture_s=0.009 capture_alloc_mb=0 disk_mb=10 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.008 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_rds op=replace capture_s=0.008 capture_alloc_mb=0 disk_mb=10 op_s=0.001 op_alloc_mb=10 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.007 restored_ok=TRUE peak_note= 
size_mb=10 strategy=disk_rds op=remove capture_s=0.011 capture_alloc_mb=0 disk_mb=10 op_s=0 op_alloc_mb=0 settle_s=0.001 retained_mb=-9.5 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.007 restored_ok=TRUE peak_note= 
size_mb=10 strategy=recompute op=inplace capture_s=0 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.007 restored_ok=TRUE peak_note= 
size_mb=10 strategy=recompute op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.001 op_alloc_mb=10 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.007 restored_ok=TRUE peak_note= 
size_mb=10 strategy=recompute op=remove capture_s=0 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-9.5 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.006 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=none op=inplace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=NA restored_ok=FALSE peak_note= 
size_mb=1000 strategy=none op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.251 op_alloc_mb=1000 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=NA restored_ok=FALSE peak_note= 
size_mb=1000 strategy=none op=remove capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-953.7 user_edit_s=NA user_edit_alloc_mb=NA restore_s=NA restored_ok=FALSE peak_note= 
size_mb=1000 strategy=byref op=inplace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.114 op_alloc_mb=1000 settle_s=0 retained_mb=953.6 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.002 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=byref op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.179 op_alloc_mb=1000 settle_s=0.001 retained_mb=953.6 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.001 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=byref op=remove capture_s=0 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.002 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=byref_spill op=inplace capture_s=0 capture_alloc_mb=0 disk_mb=1000 op_s=0.133 op_alloc_mb=1000 settle_s=0.415 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.71 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=byref_spill op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=1000 op_s=0.14 op_alloc_mb=1000 settle_s=0.344 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.44 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=byref_spill op=remove capture_s=0.001 capture_alloc_mb=0 disk_mb=1000 op_s=0 op_alloc_mb=0 settle_s=0.414 retained_mb=-953.7 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.154 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_ser op=inplace capture_s=0.32 capture_alloc_mb=0 disk_mb=1000 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.305 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_ser op=replace capture_s=0.337 capture_alloc_mb=0 disk_mb=1000 op_s=0.115 op_alloc_mb=1000 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.22 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_ser op=remove capture_s=0.329 capture_alloc_mb=0 disk_mb=1000 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-953.7 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.146 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_rds op=inplace capture_s=0.769 capture_alloc_mb=0 disk_mb=1000 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.658 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_rds op=replace capture_s=0.799 capture_alloc_mb=0 disk_mb=1000 op_s=0.111 op_alloc_mb=1000 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=0.704 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=disk_rds op=remove capture_s=1 capture_alloc_mb=0 disk_mb=1000 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-953.7 user_edit_s=NA user_edit_alloc_mb=NA restore_s=0.89 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=recompute op=inplace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.001 op_alloc_mb=0 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=1.064 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=recompute op=replace capture_s=0.001 capture_alloc_mb=0 disk_mb=0 op_s=0.303 op_alloc_mb=1000 settle_s=0 retained_mb=0 user_edit_s=0 user_edit_alloc_mb=0 restore_s=3.178 restored_ok=TRUE peak_note= 
size_mb=1000 strategy=recompute op=remove capture_s=0.006 capture_alloc_mb=0 disk_mb=0 op_s=0 op_alloc_mb=0 settle_s=0 retained_mb=-953.7 user_edit_s=NA user_edit_alloc_mb=NA restore_s=6.163 restored_ok=TRUE peak_note= 
```

`p2/seurat.R`:

```r
# seurat.R <strategy> <op> -- Seurat-object pre-image cost (G7, P2). Fresh process per run.
# strategy: none | byref ; op: meta | normalize | subset
# House style: "=" and "|>".
here = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7"
suppressMessages({ source(file.path(here, "p1/ckpt_obj.R")); library(Seurat) })
for (f in ls(pattern = "^[.]?ckpt_", all.names = TRUE)) assign(f, compiler::cmpfun(get(f)))
agent = compiler::cmpfun(function(code, envir) {
  for (e in parse(text = code, keep.source = FALSE)) eval(e, envir)
  invisible(NULL)
})
a = commandArgs(TRUE); strategy = a[1]; op = a[2]
pf = tempfile()
alloc_mb = function() { l = readLines(pf, warn = FALSE); unlink(pf)
  sum(suppressWarnings(as.numeric(sub("^([0-9]+) :.*", "\\1", l))), na.rm = TRUE) / 1e6 }
used_mb = function() sum(gc()[, 2])
now = function() proc.time()[[3]]

# synthetic counts: 20,000 genes x 30,000 cells, 1,000 non-zeros per cell (3e7 non-zeros)
ng = 20000L; nc = 30000L; k = 1000L
m = new("dgCMatrix", i = rep(seq(0L, by = 20L, length.out = k), nc), p = seq(0L, by = k, length.out = nc + 1L),
        x = as.numeric(rep_len(1:7, k * nc)), Dim = c(ng, nc),
        Dimnames = list(sprintf("g%05d", seq_len(ng)), sprintf("c%05d", seq_len(nc))))
pbmc = suppressWarnings(CreateSeuratObject(counts = m, min.cells = 0, min.features = 0))
rm(m)
w = 1:10; wst = ckpt_store(); wp = ckpt_capture(wst, globalenv(), "w"); w[1] = 0L
wr = ckpt_settle(wst, globalenv(), wp); ckpt_drop(wst, wr$key); rm(w, wst, wp, wr)
size_mb = as.numeric(object.size(pbmc)) / 1e6
code = switch(op,
  meta = "pbmc$cluster = rep_len(1:10, ncol(pbmc)); Idents(pbmc) = 'cluster'",
  normalize = "pbmc = NormalizeData(pbmc, verbose = FALSE)",
  subset = "pbmc = subset(pbmc, cells = colnames(pbmc)[seq_len(15000)])")
m0 = used_mb()
t0 = now()
if (strategy == "byref") { st = ckpt_store(); pend = ckpt_capture(st, globalenv(), "pbmc") }
cap_s = now() - t0
Rprofmem(pf, threshold = 1e6); t0 = now()
agent(code, globalenv())
op_s = now() - t0; Rprofmem(NULL); op_alloc = alloc_mb()
un = NA; lob = NA
if (strategy == "byref") {
  r = ckpt_settle(st, globalenv(), pend)
  t0 = now(); un = ckpt_unshared_bytes(st, r$key, globalenv(), "pbmc") / 1e6; un_s = now() - t0
}
retained = used_mb() - m0
if (strategy == "byref") {
  pre = get(r$key, envir = st$slots)
  lob = as.numeric(lobstr::obj_sizes(pbmc, pre))[2] / 1e6     # bytes of pre not shared with pbmc
  t0 = now(); rm(pre); res = ckpt_restore(st, globalenv(), "pbmc", r$key, expect = r$post_address)
  restore_s = now() - t0
}
cat(sprintf(paste0("seurat op=%-9s strategy=%-5s object=%.0f MB | capture %.3f s | op %.2f s, alloc %.0f MB",
                   " | retained %+.0f MB | unshared est %s MB (%s s), lobstr %s MB | restore %s\n"),
  op, strategy, size_mb, cap_s, op_s, op_alloc, retained,
  if (is.na(un)) "-" else sprintf("%.2f", un), if (is.na(un)) "-" else sprintf("%.3f", un_s),
  if (is.na(lob)) "-" else sprintf("%.2f", lob),
  if (strategy == "byref") sprintf("%s in %.3f s", res$ok, restore_s) else "-"))
```

```text
seurat op=meta      strategy=none  object=368 MB | capture 0.001 s | op 0.03 s, alloc 0 MB | retained +0 MB | unshared est - MB (- s), lobstr - MB | restore -
seurat op=meta      strategy=byref object=368 MB | capture 0.002 s | op 0.02 s, alloc 0 MB | retained +0 MB | unshared est 2.04 MB (0.001 s), lobstr 0.00 MB | restore TRUE in 0.001 s
seurat op=normalize strategy=none  object=368 MB | capture 0.001 s | op 3.04 s, alloc 1680 MB | retained +344 MB | unshared est - MB (- s), lobstr - MB | restore -
seurat op=normalize strategy=byref object=368 MB | capture 0.001 s | op 2.27 s, alloc 1680 MB | retained +345 MB | unshared est 0.36 MB (0.001 s), lobstr 0.80 MB | restore TRUE in 0.001 s
seurat op=subset    strategy=none  object=368 MB | capture 0.001 s | op 0.40 s, alloc 360 MB | retained -173 MB | unshared est - MB (- s), lobstr - MB | restore -
seurat op=subset    strategy=byref object=368 MB | capture 0.001 s | op 0.38 s, alloc 360 MB | retained +173 MB | unshared est 362.64 MB (0.001 s), lobstr 362.29 MB | restore TRUE in 0.001 s
```

`p2/capture_all.R`:

```r
# capture_all.R -- cost of capturing every value binding by reference around one tool call (G7 P2)
w = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7"
suppressMessages(source(file.path(w, "p1/ckpt_obj.R")))
for (f in ls(pattern = "^[.]?ckpt_", all.names = TRUE)) assign(f, compiler::cmpfun(get(f)))
ws = new.env()
for (i in 1:497) assign(sprintf("obj%03d", i), runif(100), envir = ws)
assign("df", data.frame(a = runif(1e6), b = sample(letters, 1e6, TRUE)), envir = ws)
assign("big", runif(1.25e8), envir = ws)                     # 1 GB
assign("L", replicate(2e4, list(a = 1, b = "x"), simplify = FALSE), envir = ws)
tm = function(expr) { t0 = proc.time()[[3]]; value = expr; structure(proc.time()[[3]] - t0, value = value) }  # value in attr
nm = ls(ws)
w0 = 1:3; st0 = ckpt_store(); p0 = ckpt_capture(st0, environment(), "w0"); invisible(ckpt_settle(st0, environment(), p0))
t_kind = tm(ckpt_binding_kind(ws, nm)); k = attr(t_kind, "value")
t_size = tm(vapply(nm, function(n) as.numeric(utils::object.size(get(n, envir = ws))), 0)); sz = attr(t_size, "value")
st = ckpt_store()
t_cap = tm(ckpt_capture(st, ws, nm)); p = attr(t_cap, "value")
eval(quote({ obj001[1] = 0; df$c = 1; rm(obj002); newobj = 1 }), ws)   # agent code: small edits only
t_set = tm(ckpt_settle(st, ws, p)); r = attr(t_set, "value")
kept = r$key[r$status != "unchanged"]
t_un = tm(vapply(kept, function(k) ckpt_unshared_bytes(st, k, ws, st$index$name[st$index$key == k]), 0)); un = attr(t_un, "value")
cat(sprintf("%d bindings (%.2f GB): kinds %.4f s, sizes %.4f s, capture %.4f s, settle %.4f s, unshared %.4f s\n",
  length(nm), sum(sz) / 1e9, t_kind, t_size, t_cap, t_set, t_un))
cat("settle statuses:", paste(names(table(r$status)), table(r$status), sep = "=", collapse = " "), "| kept:",
    paste(r$name[r$status != "unchanged"], collapse = ","), "| unshared MB:", paste(round(un / 1e6, 3), collapse = ","), "\n")
a0 = rlang::obj_address(ws$big); eval(quote({ big[1] = 0 }), ws)
cat("user edit of the untouched 1 GB object after settle:", if (identical(a0, rlang::obj_address(ws$big))) "in place" else "COPY", "\n")
a1 = rlang::obj_address(ws$df$a); eval(quote({ df$a[1] = 0 }), ws)
cat("user edit of df$a (df was shallow-copied by the agent; pre-image held):", if (identical(a1, rlang::obj_address(ws$df$a))) "in place" else "COPY (column shared with the pre-image)", "\n")
```

```text
500 bindings (1.03 GB): kinds 0.0000 s, sizes 0.0150 s, capture 0.0030 s, settle 0.0060 s, unshared 0.0020 s
settle statuses: changed=2 removed=1 unchanged=497 | kept: df,obj001,obj002 | unshared MB: 0,0.001,0.001 
user edit of the untouched 1 GB object after settle: in place 
user edit of df$a (df was shallow-copied by the agent; pre-image held): COPY (column shared with the pre-image) 
```

### 5.4 P3: file checkpoints

`p3/bench_hash.R`:

```r
# bench_hash.R -- hashing, copying and compression costs for the file checkpoint store (G7 P3)
pi_root = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
f = list.files(pi_root, recursive = TRUE, full.names = TRUE)
f = f[!grepl("/(\\.git|node_modules)/", f)]
sz = file.size(f); cat(sprintf("corpus: %d files, %.1f MB\n", length(f), sum(sz) / 1e6))
tm = function(expr) { t0 = proc.time()[[3]]; value = expr; structure(proc.time()[[3]] - t0, value = value) }  # value in attr
invisible(rlang::hash_file(f[1:5]))
cat(sprintf("file.info (size+mtime):   %.3f s\n", tm(file.info(f, extra_cols = FALSE))))
t_h = tm(rlang::hash_file(f)); h = attr(t_h, "value")
cat(sprintf("rlang::hash_file (XXH128): %.3f s\n", t_h))
cat(sprintf("tools::md5sum:             %.3f s\n", tm(tools::md5sum(f))))
cat(sprintf("cli::hash_file_sha256:     %.3f s\n", tm(cli::hash_file_sha256(f))))
cat("rlang::hash_file vectorised, first hash:", h[1], " n unique:", length(unique(h)), "of", length(h), "\n")
# copy all files into a content-addressed store: raw copy vs gzip level 1 vs gzip level 6
dst = file.path(tempdir(), "cas"); unlink(dst, recursive = TRUE); dir.create(dst)
u = !duplicated(h)
t_raw = tm(for (i in which(u)) file.copy(f[i], file.path(dst, h[i])))
raw_mb = sum(file.size(file.path(dst, h[u]))) / 1e6
gz = function(level) {
  d = file.path(tempdir(), paste0("casgz", level)); unlink(d, recursive = TRUE); dir.create(d)
  t = tm(for (i in which(u)) {
    b = readBin(f[i], "raw", sz[i]); con = gzfile(file.path(d, paste0(h[i], ".gz")), "wb", compression = level)
    writeBin(b, con); close(con) })
  c(t, sum(file.size(file.path(d, paste0(h[u], ".gz")))) / 1e6)
}
g1 = gz(1); g6 = gz(6)
cat(sprintf("CAS ingest raw copy: %.2f s, %.1f MB (%d unique of %d files)\n", t_raw, raw_mb, sum(u), length(u)))
cat(sprintf("CAS ingest gzip -1:  %.2f s, %.1f MB\n", g1[1], g1[2]))
cat(sprintf("CAS ingest gzip -6:  %.2f s, %.1f MB\n", g6[1], g6[2]))
# a single 100 MB binary-ish file
big = file.path(tempdir(), "big.bin"); con = file(big, "wb"); writeBin(as.raw(sample(0:255, 1e8, TRUE)), con); close(con)
cat(sprintf("100 MB file: hash_file %.3f s, md5sum %.3f s, file.copy %.3f s\n",
  tm(rlang::hash_file(big)), tm(tools::md5sum(big)), tm(file.copy(big, paste0(big, ".copy")))))
```

```text
corpus: 2081 files, 27.0 MB
file.info (size+mtime):   0.005 s
rlang::hash_file (XXH128): 0.234 s
tools::md5sum:             0.122 s
cli::hash_file_sha256:     0.233 s
rlang::hash_file vectorised, first hash: a739721e21820f120c74aeb3001c8c4b  n unique: 2070 of 2081 
CAS ingest raw copy: 0.49 s, 27.0 MB (2070 unique of 2081 files)
CAS ingest gzip -1:  0.86 s, 10.5 MB
CAS ingest gzip -6:  1.49 s, 9.4 MB
100 MB file: hash_file 0.014 s, md5sum 0.278 s, file.copy 0.038 s
```

Library `p3/ckpt_files.R`:

```r
# ckpt_files.R -- G7 prototype: content-addressed file checkpoints for gptr.
# Base R + rlang (hash_file, XXH128). House style: "=" and "|>".
#
# Model:
#   * A per-project blob store <root>/blobs/<2 hex>/<hash>[.gz], shared by all sessions of the
#     project (dedupe across turns and sessions). <root> = .gptr/checkpoints when the workspace
#     was consented, else file.path(tempdir(), "gptr-checkpoints") (report 13).
#   * A tracker (in memory) holds path -> (size, mtime, hash) for "tracked" files: files the
#     harness has captured content for (baseline ingest at the first mutating call, files the
#     read tool returned, and every post-image). Tracked files are restorable.
#   * Each mutating tool call is bracketed: the walk after the call is diffed against the
#     tracker's stat view; changed paths get post-images; pre-images come from the tracker.
#     This covers edit/write/apply_patch AND files written by model R code or child processes.

ckpt_prune_dirs = c(".git", ".gptr", "node_modules", ".Rproj.user", "packrat", ".venv",
                    "__pycache__", ".ipynb_checkpoints", ".quarto", ".svn", ".hg")
ckpt_prune_rel = c("renv/library", "renv/staging", "renv/sandbox")

# Pruned breadth-first walk (report 11: one list.files() + one file.info() per directory;
# never follow symbolic links). Returns path (relative), size, mtime (numeric), mode, link.
ckpt_walk = function(root, prune = ckpt_prune_dirs, prune_rel = ckpt_prune_rel, max_files = 50000L) {
  root = normalizePath(root, winslash = "/", mustWork = TRUE)
  todo = ""; out = vector("list", 0L); n = 0L
  while (length(todo)) {
    rel = todo[1L]; todo = todo[-1L]
    d = if (nzchar(rel)) file.path(root, rel) else root
    ents = list.files(d, all.files = TRUE, no.. = TRUE)
    if (!length(ents)) next
    relp = if (nzchar(rel)) paste(rel, ents, sep = "/") else ents
    full = file.path(root, relp)
    info = file.info(full, extra_cols = FALSE)
    link = nzchar(Sys.readlink(full))
    isdir = !is.na(info$isdir) & info$isdir & !link
    keep_dir = isdir & !(ents %in% prune) & !(relp %in% prune_rel)
    todo = c(todo, relp[keep_dir])
    f = (!isdir & !is.na(info$size)) | link                 # keep links, even dangling ones
    if (any(f)) {
      n = n + 1L
      out[[n]] = data.frame(path = relp[f], size = ifelse(is.na(info$size[f]), 0, info$size[f]),
                            mtime = ifelse(is.na(info$mtime[f]), 0, as.numeric(info$mtime[f])),
                            mode = as.integer(info$mode[f]), link = link[f], stringsAsFactors = FALSE)
    }
    if (sum(vapply(out, nrow, 1L)) > max_files) break
  }
  if (!n) return(data.frame(path = character(), size = numeric(), mtime = numeric(),
                            mode = integer(), link = logical(), stringsAsFactors = FALSE))
  w = do.call(rbind, out)
  w[order(w$path, method = "radix"), , drop = FALSE]
}

# ---------------------------------------------------------------- blob store
ckpt_cas = function(root, compress_max = 8e6, no_compress = "\\.(gz|bz2|xz|zip|zst|rds|rda|RData|qs2?|parquet|feather|arrow|png|jpe?g|gif|pdf|xlsx|docx|pptx)$") {
  dir.create(file.path(root, "blobs"), recursive = TRUE, showWarnings = FALSE)
  list(root = root, compress_max = compress_max, no_compress = no_compress)
}
.cas_path = function(cas, h, gz) file.path(cas$root, "blobs", substr(h, 1L, 2L), paste0(h, if (gz) ".gz" else ""))
cas_has = function(cas, h) file.exists(.cas_path(cas, h, TRUE)) | file.exists(.cas_path(cas, h, FALSE))

# Store the current content of files (absolute paths). Returns their hashes. Existing blobs
# are not rewritten (dedupe). New blobs are written to a temp name and renamed into place.
cas_put = function(cas, files, hashes = rlang::hash_file(files)) {
  for (i in seq_along(files)) {
    h = hashes[i]
    if (cas_has(cas, h)) next
    sz = file.size(files[i])
    gz = sz <= cas$compress_max && !grepl(cas$no_compress, files[i], ignore.case = TRUE)
    dest = .cas_path(cas, h, gz)
    dir.create(dirname(dest), showWarnings = FALSE)
    tmp = paste0(dest, ".tmp-", Sys.getpid())
    if (gz) {
      con = gzfile(tmp, "wb", compression = 1L); writeBin(readBin(files[i], "raw", sz), con); close(con)
    } else file.copy(files[i], tmp, overwrite = TRUE)
    file.rename(tmp, dest)
  }
  hashes
}
cas_bytes = function(cas, h) {
  gz = .cas_path(cas, h, TRUE)
  if (file.exists(gz)) { con = gzfile(gz, "rb"); on.exit(close(con)); return(readBin(con, "raw", 2^31 - 1)) }
  p = .cas_path(cas, h, FALSE)
  if (!file.exists(p)) return(NULL)
  readBin(p, "raw", file.size(p))
}
# Atomic restore of one file from a blob (temp file in the same directory + rename, report 11).
cas_restore = function(cas, h, dest, mode = NA) {
  b = cas_bytes(cas, h)
  if (is.null(b)) return(FALSE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp = file.path(dirname(dest), paste0(".", basename(dest), ".gptr-restore-", Sys.getpid()))
  con = file(tmp, "wb"); writeBin(b, con); close(con)
  if (!is.na(mode)) Sys.chmod(tmp, as.octmode(mode), use_umask = FALSE)
  ok = file.rename(tmp, dest)
  if (!ok) { unlink(tmp); con = file(dest, "wb"); writeBin(b, con); close(con) }  # in-place fallback
  TRUE
}

# ---------------------------------------------------------------- tracker
ckpt_tracker = function(project, cas, track_file_max = 1e6, track_total_max = 100e6,
                        capture_max = 50e6) {
  t = new.env(parent = emptyenv())
  t$project = normalizePath(project, winslash = "/"); t$cas = cas
  t$track_file_max = track_file_max; t$track_total_max = track_total_max
  t$capture_max = capture_max                     # post-images of changed files up to this size
  t$stat = NULL                                   # last walk: path size mtime mode link
  t$hash = character()                            # named: path -> content hash (tracked files)
  t$walk_time = NA_real_
  t
}

# Baseline: walk once and ingest small files (source-like first) within the total budget.
ckpt_baseline = function(tr) {
  w = ckpt_walk(tr$project); tr$walk_time = as.numeric(Sys.time())
  tr$stat = w
  src = grepl("\\.(R|r|Rmd|qmd|Rnw|md|ya?ml|json|txt|csv|tsv|ipynb|py|sql|sh|toml|Rprofile)$", w$path)
  cand = w[!w$link & w$size <= tr$track_file_max, , drop = FALSE]
  cand = cand[order(!src[match(cand$path, w$path)], cand$size, method = "radix"), , drop = FALSE]
  cand = cand[cumsum(cand$size) <= tr$track_total_max, , drop = FALSE]
  if (nrow(cand)) {
    h = cas_put(tr$cas, file.path(tr$project, cand$path))
    tr$hash[cand$path] = h
  }
  invisible(list(files = nrow(w), tracked = nrow(cand), bytes = sum(cand$size)))
}

# Diff the current walk against the tracker's stat view.
# "Racily clean" rule (git): same size and mtime but mtime within `racy` seconds of the previous
# walk -> compare content hashes for tracked files.
ckpt_scan = function(tr, racy = 2) {
  w = ckpt_walk(tr$project); now = as.numeric(Sys.time())
  old = tr$stat
  created = setdiff(w$path, old$path); deleted = setdiff(old$path, w$path)
  both = intersect(w$path, old$path)
  o = old[match(both, old$path), ]; n = w[match(both, w$path), ]
  changed = both[o$size != n$size | o$mtime != n$mtime]
  racy_p = both[o$size == n$size & o$mtime == n$mtime & n$mtime >= tr$walk_time - racy & both %in% names(tr$hash)]
  if (length(racy_p)) {
    hh = rlang::hash_file(file.path(tr$project, racy_p))
    changed = c(changed, racy_p[hh != tr$hash[racy_p]])
  }
  list(walk = w, time = now, created = created, deleted = deleted, modified = changed)
}

# Record one mutating step (a tool call, or "external" at a turn start). Returns a data.frame
# of file change records: path, status, pre (hash or NA), post (hash or NA), mode, restorable.
ckpt_file_step = function(tr, by = "tool") {
  s = ckpt_scan(tr)
  paths = c(s$created, s$modified, s$deleted)
  status = rep(c("created", "modified", "deleted"), c(length(s$created), length(s$modified), length(s$deleted)))
  k = length(paths)
  rec = data.frame(path = paths, status = status, by = rep(by, k),
                   pre = unname(tr$hash[paths]), post = rep(NA_character_, k), mode = rep(NA_integer_, k),
                   post_size = rep(NA_real_, k), post_mtime = rep(NA_real_, k),
                   restorable = rep(TRUE, k), reason = rep("", k), stringsAsFactors = FALSE)
  keep = s$walk$path %in% paths & s$walk$path %in% c(s$created, s$modified)
  cur = s$walk[keep, , drop = FALSE]
  cap = cur$path[!cur$link & cur$size <= tr$capture_max]
  if (length(cap)) {
    h = cas_put(tr$cas, file.path(tr$project, cap))
    rec$post[match(cap, rec$path)] = h
    tr$hash[cap] = h
  }
  big = setdiff(cur$path, cap)                              # changed but too large (or a link)
  tr$hash = tr$hash[setdiff(names(tr$hash), c(s$deleted, big))]
  rec$mode = tr$stat$mode[match(rec$path, tr$stat$path)]     # PRE mode, restored with the content
  rec$post_size[match(cur$path, rec$path)] = cur$size        # stat of the post state, used by the
  rec$post_mtime[match(cur$path, rec$path)] = cur$mtime      # 3-way check when no post hash exists
  # restorability of the PRE state: created files are restorable by deletion; others need a pre-image
  miss = rec$status != "created" & is.na(rec$pre)
  rec$restorable[miss] = FALSE
  rec$reason[miss] = "no pre-image (file was not tracked: over size cap or outside the baseline)"
  lnk = rec$path %in% s$walk$path[s$walk$link]
  rec$restorable[lnk] = FALSE; rec$reason[lnk] = "symbolic link (never restored through)"
  tr$stat = s$walk; tr$walk_time = s$time
  rec
}

# Undo a set of file records (apply in reverse order). A file is restored only if its current
# content is still the recorded post-image (3-way check); otherwise it is a conflict and is
# left alone unless force = TRUE. Created files are removed (their content stays in the store,
# so a redo can bring them back).
ckpt_file_undo = function(tr, rec, force = FALSE) {
  res = data.frame(path = rec$path, action = rep("", nrow(rec)), stringsAsFactors = FALSE)
  for (i in rev(seq_len(nrow(rec)))) {
    p = rec$path[i]; full = file.path(tr$project, p)
    exists_now = file.exists(full)
    now_h = if (exists_now) rlang::hash_file(full) else NA_character_
    expect_ok = if (rec$status[i] == "deleted") !exists_now
      else if (!is.na(rec$post[i])) identical(now_h, rec$post[i])
      else exists_now && isTRUE(file.size(full) == rec$post_size[i]) &&
        isTRUE(as.numeric(file.mtime(full)) == rec$post_mtime[i])
    if (!rec$restorable[i]) { res$action[i] = paste("skipped:", rec$reason[i]); next }
    if (!expect_ok && !force) { res$action[i] = "conflict: changed after the checkpoint (kept current)"; next }
    if (rec$status[i] == "created") {
      if (exists_now) { cas_put(tr$cas, full); unlink(full) }
      tr$hash = tr$hash[names(tr$hash) != p]; res$action[i] = "removed (created by the step)"
    } else {
      ok = cas_restore(tr$cas, rec$pre[i], full, rec$mode[i])
      if (ok) tr$hash[p] = rec$pre[i]
      res$action[i] = if (ok) "restored" else "failed: blob missing"
    }
  }
  tr$stat = ckpt_walk(tr$project); tr$walk_time = as.numeric(Sys.time())
  res
}

# Retention: delete blobs no live record references, then (if still above max_bytes)
# the caller drops the oldest sessions' records and calls again.
cas_prune = function(cas, live_hashes) {
  f = list.files(file.path(cas$root, "blobs"), recursive = TRUE, full.names = TRUE)
  f = f[!grepl("\\.tmp-", f)]
  h = sub("\\.gz$", "", basename(f))
  dead = !(h %in% live_hashes)
  unlink(f[dead])
  list(deleted = sum(dead), kept = sum(!dead), bytes = sum(file.size(f[!dead])))
}
```

Scenario `p3/test_files.R`:

```r
# test_files.R -- end-to-end file checkpoint scenario (G7 P3). House style: "=" and "|>".
here = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p3"
source(file.path(here, "ckpt_files.R"))
ok = function(cond, msg) cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n")
proj = file.path(tempdir(), "proj"); unlink(proj, recursive = TRUE)
dir.create(file.path(proj, "R"), recursive = TRUE); dir.create(file.path(proj, "data"))
dir.create(file.path(proj, ".git")); dir.create(file.path(proj, "node_modules", "x"), recursive = TRUE)
writeLines(c("f = function(x) x + 1", "g = function(x) x * 2"), file.path(proj, "R", "a.R"))
writeLines("h = function() 'b'", file.path(proj, "R", "b.R"))
writeLines("# Notes\nkeep me", file.path(proj, "notes.md"))
write.csv(data.frame(id = 1:2e5, v = sqrt(1:2e5)), file.path(proj, "data", "big.csv"), row.names = FALSE)
con = file(file.path(proj, "data", "huge.bin"), "wb"); writeBin(as.raw(rep(1:255, 12e4)), con); close(con)  # 30.6 MB
writeLines("ignored", file.path(proj, ".git", "HEAD")); writeLines("ignored", file.path(proj, "node_modules", "x", "i.js"))
invisible(file.symlink(file.path(proj, "notes.md"), file.path(proj, "link.md")))
hash_all = function() { w = ckpt_walk(proj); w = w[!w$link, ]; setNames(rlang::hash_file(file.path(proj, w$path)), w$path) }
state0 = hash_all()

cas = ckpt_cas(file.path(tempdir(), "gptr-checkpoints"))          # no consented .gptr/: tempdir
tr = ckpt_tracker(proj, cas, track_file_max = 5e6, capture_max = 20e6)
t0 = proc.time()[[3]]; b = ckpt_baseline(tr); t_base = proc.time()[[3]] - t0
cat(sprintf("baseline: %d files seen, %d tracked (%.1f MB) in %.3f s; pruned .git and node_modules: %s\n",
            b$files, b$tracked, b$bytes / 1e6, t_base, !any(grepl("^(\\.git|node_modules)/", tr$stat$path))))
steps = list()

# step 1: the edit tool rewrites R/a.R atomically (temp file + rename)
tmp = file.path(proj, "R", ".a.R.tmp"); writeLines(c("f = function(x) x + 10", "g = function(x) x * 2"), tmp)
invisible(file.rename(tmp, file.path(proj, "R", "a.R")))
steps[[1]] = ckpt_file_step(tr, by = "edit")
# step 2: model R code (run_r): create, overwrite in place, delete, and touch the untracked huge file
local({
  write.csv(data.frame(id = 1:3), file.path(proj, "out.csv"), row.names = FALSE)
  write.csv(data.frame(id = 1:10), file.path(proj, "data", "big.csv"), row.names = FALSE)   # truncating in-place write
  file.remove(file.path(proj, "notes.md"))
  con = file(file.path(proj, "data", "huge.bin"), "r+b"); seek(con, 0, rw = "write"); writeBin(as.raw(0), con); close(con)
})
steps[[2]] = ckpt_file_step(tr, by = "run_r")
# step 3: a child process (as system2()/processx would run it) rewrites R/b.R
system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(sprintf("writeLines('h = function() \"child\"', '%s')", file.path(proj, "R", "b.R")))))
steps[[3]] = ckpt_file_step(tr, by = "run_r:child")
for (i in 1:3) { cat(sprintf("step %d records:\n", i)); print(steps[[i]][, c("path", "status", "by", "restorable")], row.names = FALSE) }
ok(steps[[2]]$reason[steps[[2]]$path == "data/huge.bin"] != "", "huge.bin (30.6 MB > 5 MB tracking cap) flagged not restorable")

# between turns: the USER edits R/b.R in their editor (external change)
Sys.sleep(1.1); writeLines("h = function() 'user'", file.path(proj, "R", "b.R"))
ext = ckpt_file_step(tr, by = "external")
ok(nrow(ext) == 1 && ext$path == "R/b.R", "external edit detected at the next turn start")

# rewind all three agent steps (newest first); the external change must win for R/b.R
t0 = proc.time()[[3]]
u = rbind(ckpt_file_undo(tr, steps[[3]]), ckpt_file_undo(tr, steps[[2]]), ckpt_file_undo(tr, steps[[1]]))
t_undo = proc.time()[[3]] - t0
print(u, row.names = FALSE)
state1 = hash_all()
same = intersect(names(state0), names(state1))
diffs = same[state0[same] != state1[same]]
ok(setequal(diffs, c("R/b.R", "data/huge.bin")), sprintf("after undo only R/b.R (user edit kept) and huge.bin (untracked) differ from the start: %s", paste(diffs, collapse = ", ")))
ok(!file.exists(file.path(proj, "out.csv")), "file created by the agent removed")
ok(file.exists(file.path(proj, "notes.md")) && readLines(file.path(proj, "notes.md"))[2] == "keep me", "deleted file restored")
ok(nrow(read.csv(file.path(proj, "data", "big.csv"))) == 2e5, "in-place overwrite by write.csv undone")
cat(sprintf("undo time: %.3f s\n", t_undo))

# redo with force for the conflicting file: the child's version comes back from the store
f = ckpt_file_undo(tr, ext, force = TRUE)
ok(readLines(file.path(proj, "R", "b.R")) == "h = function() \"child\"", "forced undo of the external change restores the child's version")

# dedupe: writing the original content again adds no blob
nb = function() length(list.files(file.path(cas$root, "blobs"), recursive = TRUE))
n0 = nb(); writeLines(c("f = function(x) x + 10", "g = function(x) x * 2"), file.path(proj, "R", "a.R"))
s4 = ckpt_file_step(tr, by = "edit"); ok(nb() == n0, "identical content stored once (dedupe)")
# retention: keep only the hashes referenced by steps 1-2; unreferenced blobs are deleted
live = unique(na.omit(c(steps[[1]]$pre, steps[[1]]$post, steps[[2]]$pre, steps[[2]]$post)))
pr = cas_prune(cas, live)
cat(sprintf("prune: deleted %d blobs, kept %d (%.2f MB on disk)\n", pr$deleted, pr$kept, pr$bytes / 1e6))
ok(all(cas_has(cas, live)), "live blobs survive pruning")
```

```text
baseline: 6 files seen, 4 tracked (4.7 MB) in 0.075 s; pruned .git and node_modules: TRUE
step 1 records:
  path   status   by restorable
 R/a.R modified edit       TRUE
step 2 records:
          path   status    by restorable
       out.csv  created run_r       TRUE
  data/big.csv modified run_r       TRUE
 data/huge.bin modified run_r      FALSE
       link.md modified run_r      FALSE
      notes.md  deleted run_r       TRUE
step 3 records:
  path   status          by restorable
 R/b.R modified run_r:child       TRUE
PASS huge.bin (30.6 MB > 5 MB tracking cap) flagged not restorable 
PASS external edit detected at the next turn start 
          path
         R/b.R
       out.csv
  data/big.csv
 data/huge.bin
       link.md
      notes.md
         R/a.R
                                                                              action
                               conflict: changed after the checkpoint (kept current)
                                                       removed (created by the step)
                                                                            restored
 skipped: no pre-image (file was not tracked: over size cap or outside the baseline)
                                     skipped: symbolic link (never restored through)
                                                                            restored
                                                                            restored
PASS after undo only R/b.R (user edit kept) and huge.bin (untracked) differ from the start: R/b.R, data/huge.bin 
PASS file created by the agent removed 
PASS deleted file restored 
PASS in-place overwrite by write.csv undone 
undo time: 0.066 s
PASS forced undo of the external change restores the child's version 
PASS identical content stored once (dedupe) 
prune: deleted 3 blobs, kept 6 (1.98 MB on disk)
PASS live blobs survive pruning 
```

Tree costs `p3/bench_tree.R`:

```r
# bench_tree.R -- per-turn cost of file checkpoints on real trees (G7 P3)
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p3/ckpt_files.R")
tm = function(expr) { t0 = proc.time()[[3]]; value = expr; structure(proc.time()[[3]] - t0, value = value) }  # value in attr
trees = c(pi = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi",
          rlib = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib")
invisible(rlang::hash_file(tempfile() |> (\(f) { writeLines("x", f); f })()))
for (nm in names(trees)) {
  cas = ckpt_cas(file.path(tempdir(), paste0("cas-", nm)))
  tr = ckpt_tracker(trees[[nm]], cas, track_file_max = 1e6, track_total_max = 100e6)
  t_walk = tm(ckpt_walk(trees[[nm]], max_files = 1e6)); w = attr(t_walk, "value")
  t_base = tm(ckpt_baseline(tr)); b = attr(t_base, "value")
  store_mb = sum(file.size(list.files(cas$root, recursive = TRUE, full.names = TRUE))) / 1e6
  t_scan0 = tm(ckpt_file_step(tr)); r0 = attr(t_scan0, "value")                       # nothing changed
  t_scan0b = tm(ckpt_file_step(tr)); r0b = attr(t_scan0b, "value")
  cat(sprintf("%-4s: %6d files %7.1f MB | walk %.3f s | baseline %.2f s: %d tracked, %.1f MB -> store %.1f MB | no-change step %.3f s, %.3f s (%d records)\n",
    nm, nrow(w), sum(w$size) / 1e6, t_walk, t_base, b$tracked, b$bytes / 1e6, store_mb, t_scan0, t_scan0b, nrow(r0) + nrow(r0b)))
}
# second session of the same project: the store already holds every blob (dedupe)
cas = ckpt_cas(file.path(tempdir(), "cas-pi"))
tr2 = ckpt_tracker(trees[["pi"]], cas, track_file_max = 1e6, track_total_max = 100e6)
t2 = tm(ckpt_baseline(tr2)); b2 = attr(t2, "value")
cat(sprintf("pi  : second-session baseline against a populated store: %.2f s (%d tracked, no new blobs)\n", t2, b2$tracked))
```

```text
pi  :   2125 files    27.2 MB | walk 0.119 s | baseline 1.28 s: 2123 tracked, 23.3 MB -> store 8.6 MB | no-change step 0.169 s, 0.145 s (0 records)
rlib:   4167 files   426.2 MB | walk 0.863 s | baseline 4.59 s: 4128 tracked, 84.3 MB -> store 46.2 MB | no-change step 0.982 s, 0.916 s (0 records)
pi  : second-session baseline against a populated store: 0.33 s (2123 tracked, no new blobs)
```

### 5.5 P4: side state and static target prediction

Library `p4/ckpt_state.R`:

```r
# ckpt_state.R -- G7 prototype: session side-state checkpoints and static target prediction.
# Base R only. House style: "=" and "|>".

# ---------------------------------------------------------------- side state
# Snapshot of process-global state an R tool call can change. Kept in memory only: env var
# VALUES never leave the process (they may be secrets, REQ-13/D-22); records persist names only.
ckpt_state_snapshot = function(envir) {
  list(
    options = options(),
    wd = getwd(),
    envvars = as.list(Sys.getenv()),
    locale = Sys.getlocale(),
    search = search(),
    loaded = loadedNamespaces(),
    devices = grDevices::dev.list(),
    connections = as.integer(rownames(showConnections(all = FALSE))),
    seed = if (identical(envir, globalenv()) && exists(".Random.seed", envir = envir, inherits = FALSE))
      get(".Random.seed", envir = envir, inherits = FALSE) else NULL,
    rng_kind = RNGkind()
  )
}

# Harness-owned options are restored by the evaluator itself (report 12 A8) and ignored here.
ckpt_harness_options = c("max.print", "width", "warn", "rlang_interactive", "cli.dynamic",
                         "cli.num_colors", "askYesNo", "try.outFile")

ckpt_state_diff = function(pre, post) {
  on = union(names(pre$options), names(post$options))
  on = setdiff(on, ckpt_harness_options)
  opt = on[!vapply(on, function(n) identical(pre$options[[n]], post$options[[n]]), TRUE)]
  en = union(names(pre$envvars), names(post$envvars))
  env = en[!vapply(en, function(n) identical(pre$envvars[[n]], post$envvars[[n]]), TRUE)]
  list(
    options = opt, envvars = env,
    wd = !identical(pre$wd, post$wd), locale = !identical(pre$locale, post$locale),
    attached = setdiff(post$search, pre$search), detached = setdiff(pre$search, post$search),
    loaded = setdiff(post$loaded, pre$loaded),
    dev_opened = setdiff(post$devices, pre$devices), dev_closed = setdiff(pre$devices, post$devices),
    con_opened = setdiff(post$connections, pre$connections), con_closed = setdiff(pre$connections, post$connections),
    rng = !identical(pre$seed, post$seed) || !identical(pre$rng_kind, post$rng_kind)
  )
}

# Undo side state with the same 3-way rule as objects and files: an item is put back only
# if its current value is still the post-step value. Returns one line per item.
ckpt_state_undo = function(pre, post, d, envir, close_devices = FALSE) {
  now = ckpt_state_snapshot(envir); out = character()
  for (n in d$options) {
    if (!identical(now$options[[n]], post$options[[n]])) { out = c(out, sprintf("option %s: conflict, kept", n)); next }
    options(stats::setNames(list(pre$options[[n]]), n)); out = c(out, sprintf("option %s: restored", n))
  }
  for (n in d$envvars) {
    if (!identical(now$envvars[[n]], post$envvars[[n]])) { out = c(out, sprintf("env var %s: conflict, kept", n)); next }
    if (is.null(pre$envvars[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, stats::setNames(list(pre$envvars[[n]]), n))
    out = c(out, sprintf("env var %s: restored (value not shown)", n))
  }
  if (d$wd) {
    if (identical(now$wd, post$wd)) { setwd(pre$wd); out = c(out, "working directory: restored") }
    else out = c(out, "working directory: conflict, kept")
  }
  if (d$locale) out = c(out, "locale: changed; restore with Sys.setlocale() (reported only)")
  for (p in grep("^package:", d$attached, value = TRUE)) {
    if (p %in% search()) { detach(p, character.only = TRUE); out = c(out, sprintf("%s: detached", p)) }
  }
  for (p in grep("^package:", d$detached, value = TRUE)) {
    ok = suppressPackageStartupMessages(requireNamespace(sub("^package:", "", p), quietly = TRUE))
    if (ok) { attachNamespace(sub("^package:", "", p)); out = c(out, sprintf("%s: re-attached", p)) }
  }
  if (length(d$loaded)) out = c(out, sprintf("namespaces %s: stay loaded (unloading is unsafe)", paste(d$loaded, collapse = ", ")))
  if (length(d$dev_opened)) {
    if (close_devices) { for (dv in d$dev_opened) if (dv %in% grDevices::dev.list()) grDevices::dev.off(dv)
      out = c(out, "devices opened by the step: closed") }
    else out = c(out, sprintf("devices %s opened by the step: left open", paste(d$dev_opened, collapse = ", ")))
  }
  if (length(d$dev_closed)) out = c(out, sprintf("devices %s closed by the step: cannot be reopened", paste(d$dev_closed, collapse = ", ")))
  for (cn in d$con_opened) if (cn %in% as.integer(rownames(showConnections()))) {
    close(getConnection(cn)); out = c(out, sprintf("connection %d opened by the step: closed", cn)) }
  if (length(d$con_closed)) out = c(out, "connections closed by the step: cannot be reopened")
  if (d$rng) {
    if (!is.null(pre$seed) && identical(now$seed, post$seed)) {
      assign(".Random.seed", pre$seed, envir = envir)        # only when envir is the global env (see snapshot)
      out = c(out, "RNG state: restored")
    } else out = c(out, "RNG state: changed, not restored")
  }
  out
}

# ---------------------------------------------------------------- static target prediction
# Walk the parse tree of the agent's code. Returns object targets (rebinding), by-reference
# targets, removals, superassignments, literal file paths written or removed, and flags for
# anything the walk cannot resolve (dynamic names, load(), source(), eval(parse()), processes).
.ckpt_root_sym = function(e) {
  while (is.call(e)) {
    if (identical(e[[1L]], as.name("::")) || identical(e[[1L]], as.name(":::"))) return(NULL)
    if (length(e) < 2L) return(NULL)
    e = e[[2L]]
  }
  if (is.name(e)) as.character(e) else if (is.character(e) && length(e) == 1L) e else NULL
}
.ckpt_fn_name = function(head) {
  if (is.name(head)) return(as.character(head))
  if (is.call(head) && (identical(head[[1L]], as.name("::")) || identical(head[[1L]], as.name(":::"))))
    return(as.character(head[[3L]]))
  if (is.character(head) && length(head) == 1L) return(head)
  ""
}
ckpt_dt_byref = c("set", "setnames", "setkey", "setkeyv", "setorder", "setorderv", "setattr",
                  "setDT", "setDF", "setcolorder", "setindex", "setindexv", "setlevels", "alloc.col")
ckpt_file_writers = list(                 # function -> argument name (or position) holding the path
  write.csv = c("file", 2L), write.csv2 = c("file", 2L), write.table = c("file", 2L),
  writeLines = c("con", 2L), saveRDS = c("file", 2L), save = c("file", NA), cat = c("file", NA),
  sink = c("file", 1L), ggsave = c("filename", 1L), png = c("filename", 1L), pdf = c("file", 1L),
  jpeg = c("filename", 1L), svg = c("filename", 1L), file.create = c("...", 1L),
  file.copy = c("to", 2L), file.rename = c("to", 2L), file.remove = c("...", 1L),
  unlink = c("x", 1L), fwrite = c("file", 2L), write_csv = c("file", 2L), write_rds = c("file", 2L),
  write_parquet = c("sink", 2L), writeBin = c("con", 2L), download.file = c("destfile", 2L),
  file.append = c("file1", 1L), dir.create = c("path", 1L), qsave = c("file", 2L), qs_save = c("file", 2L))
ckpt_dynamic = c("load", "source", "sys.source", "list2env", "attach", "eval", "evalq", "do.call",
                 "local", "with", "within", "sys.function", "attachNamespace", "makeActiveBinding",
                 "delayedAssign", "environment<-")
ckpt_process = c("system", "system2", "shell", "run", "process", "r_bg", "r_session", "callr", "mcparallel")

ckpt_targets = function(code) {
  acc = new.env(parent = emptyenv())
  acc$assign = character(); acc$byref = character(); acc$remove = character()
  acc$super = character(); acc$files = character(); acc$unknown = character(); acc$process = FALSE
  acc$modify = character()
  add = function(field, v) assign(field, unique(c(get(field, envir = acc), v)), envir = acc)
  walk = function(e, local = FALSE) {        # local = inside a function body (own frame)
    if (!is.call(e)) return(invisible())
    f = .ckpt_fn_name(e[[1L]])
    if (f == "function") { walk(e[[3L]], local = TRUE); return(invisible()) }
    if (f == "for" && !local) add("assign", as.character(e[[2L]]))   # top-level loop variable
    if (f %in% c("<-", "=", "<<-") && length(e) == 3L) {
      r = .ckpt_root_sym(e[[2L]])
      if (!is.null(r) && (f == "<<-" || !local)) add(if (f == "<<-") "super" else "assign", r)
      if (!is.null(r) && f != "<<-" && !local && is.call(e[[2L]])) add("modify", r)   # x[i] = v: in-place edit
      walk(e[[3L]], local); if (is.call(e[[2L]])) for (a in as.list(e[[2L]])[-1L]) if (!missing(a)) walk(a, local)
      return(invisible())
    }
    if (f == "assign") {
      nm = e[[2L]]; if (is.character(nm)) add("assign", nm) else add("unknown", "assign(<computed name>)")
      if (!is.null(names(e)) && any(names(e) %in% c("envir", "pos"))) add("unknown", "assign(envir =)")
    }
    if (f == "rm" || f == "remove") {
      args = as.list(e)[-1L]; nms = names(args); if (is.null(nms)) nms = rep("", length(args))
      for (i in seq_along(args)) {
        if (nms[i] == "list") {
          l = args[[i]]
          if (is.call(l) && identical(l[[1L]], as.name("c")) && all(vapply(as.list(l)[-1L], is.character, TRUE)))
            add("remove", unlist(as.list(l)[-1L]))
          else if (is.character(l)) add("remove", l)
          else add("unknown", "rm(list = <computed>)")
        } else if (nms[i] == "" && (is.name(args[[i]]) || is.character(args[[i]]))) add("remove", as.character(args[[i]]))
      }
    }
    if (f == ":=") { add("byref", "<data.table in the enclosing [ ]>") }
    if (f == "[" && length(e) >= 3L) {                       # dt[ , a := ...]
      has_walrus = any(vapply(as.list(e)[-(1:2)], function(a) is.call(a) && identical(a[[1L]], as.name(":=")), TRUE))
      if (has_walrus) { r = .ckpt_root_sym(e[[2L]]); if (!is.null(r)) add("byref", r) }
    }
    if (f %in% ckpt_dt_byref && length(e) >= 2L) { r = .ckpt_root_sym(e[[2L]]); if (!is.null(r)) add("byref", r) }
    if (f %in% names(ckpt_file_writers)) {
      spec = ckpt_file_writers[[f]]; args = as.list(e)[-1L]; nms = names(args); if (is.null(nms)) nms = rep("", length(args))
      val = if (spec[1L] %in% nms) args[[match(spec[1L], nms)]]
            else if (!is.na(spec[2L])) { pos = which(nms == ""); if (length(pos) >= as.integer(spec[2L])) args[[pos[as.integer(spec[2L])]]] else NULL }
            else NULL
      if (is.character(val)) add("files", val)
      else if (!is.null(val) || f %in% c("save", "cat")) add("unknown", sprintf("%s(<computed path>)", f))
    }
    if (f %in% ckpt_dynamic) add("unknown", sprintf("%s()", f))
    if (f %in% ckpt_process) acc$process = TRUE
    for (a in as.list(e)[-1L]) if (!missing(a)) walk(a, local)
    invisible()
  }
  exprs = tryCatch(parse(text = code, keep.source = FALSE), error = function(err) NULL)
  if (is.null(exprs)) return(list(parse_error = TRUE))
  for (x in exprs) walk(x)
  acc$byref = setdiff(acc$byref, "<data.table in the enclosing [ ]>")
  list(assign = acc$assign, modify = acc$modify, byref = acc$byref, remove = acc$remove, super = acc$super,
       files = acc$files, unknown = acc$unknown, process = acc$process, parse_error = FALSE)
}
```

`p4/test_state.R`:

```r
# test_state.R -- side-state undo and target prediction (G7 P4). House style: "=" and "|>".
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p4/ckpt_state.R")
ok = function(cond, msg) cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n")
agent = function(code, envir) { for (e in parse(text = code, keep.source = FALSE)) eval(e, envir); invisible(NULL) }
env = globalenv()
set.seed(42); invisible(runif(1))
options(digits = 7); Sys.setenv(GPTR_TEST_KEY = "secret-value"); wd0 = getwd()
t0 = proc.time()[[3]]; pre = ckpt_state_snapshot(env); t_snap = proc.time()[[3]] - t0
agent(paste(sep = "\n",
  "options(digits = 3, gptr.demo = TRUE)",
  "Sys.setenv(GPTR_TEST_KEY = 'changed'); Sys.setenv(NEW_VAR = '1')",
  "setwd(tempdir())",
  "suppressPackageStartupMessages(library(tools))",
  "invisible(requireNamespace('compiler'))",
  "pdf(NULL); plot(1)",
  "zz = file(tempfile(), 'w')",
  "u = runif(3)"), env)
post = ckpt_state_snapshot(env)
d = ckpt_state_diff(pre, post)
cat("diff: options", paste(d$options, collapse = ","), "| envvars", paste(d$envvars, collapse = ","),
    "| wd", d$wd, "| attached", paste(d$attached, collapse = ","), "| loaded", paste(d$loaded, collapse = ","),
    "| devices", paste(d$dev_opened, collapse = ","), "| connections", length(d$con_opened), "| rng", d$rng, "\n")
Sys.setenv(NEW_VAR = "user-set")                           # the user touches one item after the step
lines = ckpt_state_undo(pre, post, d, env, close_devices = TRUE)
writeLines(paste("  ", lines))
ok(getOption("digits") == 7 && is.null(getOption("gptr.demo")), "options restored (changed and added)")
ok(Sys.getenv("GPTR_TEST_KEY") == "secret-value" && Sys.getenv("NEW_VAR") == "user-set", "env vars restored; user-changed var kept (3-way)")
ok(identical(getwd(), wd0), "working directory restored")
ok(!"package:tools" %in% search(), "package attached by the step detached")
ok(is.null(grDevices::dev.list()), "device opened by the step closed (close_devices = TRUE)")
cat(sprintf("state snapshot: %.4f s; %d options, %d env vars\n", t_snap, length(pre$options), length(pre$envvars)))

# ---- RNG restore check in a clean sequence
set.seed(7); a1 = runif(1); s_pre = ckpt_state_snapshot(env)
agent("invisible(runif(1000))", env); s_post = ckpt_state_snapshot(env)
invisible(ckpt_state_undo(s_pre, s_post, ckpt_state_diff(s_pre, s_post), env))
b1 = runif(1); set.seed(7); invisible(runif(1)); b2 = runif(1)
ok(identical(b1, b2), "RNG stream continues as if the undone step never drew numbers")

# ---- target prediction
cases = c(
  "pbmc = FindClusters(pbmc, resolution = 0.8)",
  "x[1] = 0; names(y) = letters[1:3]; z$a$b = 1; attr(w, 'u') = 1",
  "dt[, b := a * 2]; data.table::set(dt2, 1L, 'a', 0); setnames(dt3, 'a', 'b')",
  "rm(a, 'b'); rm(list = c('c1', 'c2')); rm(list = ls())",
  "counter <<- counter + 1",
  "assign('m1', 1); assign(nm, 2)",
  "write.csv(df, 'out/results.csv'); saveRDS(fit, file = 'fit.rds'); ggplot2::ggsave('p.png', p); unlink('tmp', recursive = TRUE)",
  "load('ws.RData'); source('helpers.R'); eval(parse(text = s))",
  "system2('bash', 'run.sh'); processx::run('python', 'x.py')",
  "for (i in 1:3) res[[i]] = f(i); out = lapply(xs, function(v) { tmp = v; tmp })")
for (cd in cases) {
  t = ckpt_targets(cd)
  cat(sprintf("%-60s -> assign={%s} modify={%s} byref={%s} remove={%s} super={%s} files={%s} unknown={%s} process=%s\n",
    substr(cd, 1, 60), paste(t$assign, collapse = ","), paste(t$modify, collapse = ","), paste(t$byref, collapse = ","), paste(t$remove, collapse = ","),
    paste(t$super, collapse = ","), paste(t$files, collapse = ","), paste(t$unknown, collapse = ","), t$process))
}
big = paste(rep("x1 = x1 + 1; dt[, k := k + 1]; write.csv(d, 'a.csv')", 500), collapse = "\n")
t0 = proc.time()[[3]]; invisible(ckpt_targets(big)); cat(sprintf("prediction on 1,500 statements: %.3f s\n", proc.time()[[3]] - t0))
```

```text
diff: options digits,gptr.demo | envvars GPTR_TEST_KEY,NEW_VAR | wd TRUE | attached package:tools | loaded tools | devices 2 | connections 1 | rng TRUE 
   option digits: restored
   option gptr.demo: restored
   env var GPTR_TEST_KEY: restored (value not shown)
   env var NEW_VAR: conflict, kept
   working directory: restored
   package:tools: detached
   namespaces tools: stay loaded (unloading is unsafe)
   devices opened by the step: closed
   connection 3 opened by the step: closed
   RNG state: restored
PASS options restored (changed and added) 
PASS env vars restored; user-changed var kept (3-way) 
PASS working directory restored 
PASS package attached by the step detached 
PASS device opened by the step closed (close_devices = TRUE) 
state snapshot: 0.0130 s; 73 options, 95 env vars
PASS RNG stream continues as if the undone step never drew numbers 
pbmc = FindClusters(pbmc, resolution = 0.8)                  -> assign={pbmc} modify={} byref={} remove={} super={} files={} unknown={} process=FALSE
x[1] = 0; names(y) = letters[1:3]; z$a$b = 1; attr(w, 'u') = -> assign={x,y,z,w} modify={x,y,z,w} byref={} remove={} super={} files={} unknown={} process=FALSE
dt[, b := a * 2]; data.table::set(dt2, 1L, 'a', 0); setnames -> assign={} modify={} byref={dt,dt2,dt3} remove={} super={} files={} unknown={} process=FALSE
rm(a, 'b'); rm(list = c('c1', 'c2')); rm(list = ls())        -> assign={} modify={} byref={} remove={a,b,c1,c2} super={} files={} unknown={rm(list = <computed>)} process=FALSE
counter <<- counter + 1                                      -> assign={} modify={} byref={} remove={} super={counter} files={} unknown={} process=FALSE
assign('m1', 1); assign(nm, 2)                               -> assign={m1} modify={} byref={} remove={} super={} files={} unknown={assign(<computed name>)} process=FALSE
write.csv(df, 'out/results.csv'); saveRDS(fit, file = 'fit.r -> assign={} modify={} byref={} remove={} super={} files={out/results.csv,fit.rds,p.png,tmp} unknown={} process=FALSE
load('ws.RData'); source('helpers.R'); eval(parse(text = s)) -> assign={} modify={} byref={} remove={} super={} files={} unknown={load(),source(),eval()} process=FALSE
system2('bash', 'run.sh'); processx::run('python', 'x.py')   -> assign={} modify={} byref={} remove={} super={} files={} unknown={} process=TRUE
for (i in 1:3) res[[i]] = f(i); out = lapply(xs, function(v) -> assign={i,res,out} modify={res} byref={} remove={} super={} files={} unknown={} process=FALSE
prediction on 1,500 statements: 0.043 s
```

### 5.6 P5 and P6: rewind on one session object, redo, reload, runnable transcript

Library `p5/ckpt_session.R`:

```r
# ckpt_session.R -- G7 prototype: checkpoints as nodes of an append-only session tree, rewind
# as a branch-in-place on ONE session object (S-8), redo, and the runnable transcript.
# Depends on p1/ckpt_obj.R, p3/ckpt_files.R, p4/ckpt_state.R; jsonlite for JSONL.
# House style: "=" and "|>".

.id8 = local({ n = 0L; function() { n <<- n + 1L                   # ids without .Random.seed
  substr(cli_free_hash(paste(Sys.time(), Sys.getpid(), n)), 1L, 8L) } })
cli_free_hash = function(x) rlang::hash(x)

# ---------------------------------------------------------------- session object (environment)
new_session = function(envir, project, dir, undo_max_bytes = 1e9, capture_all_max = 1e8) {
  s = new.env(parent = emptyenv())
  class(s) = "gptr_session"
  s$envir = envir; s$project = project
  s$file = file.path(dir, "session.jsonl")
  s$entries = list(); s$leaf = NULL; s$turn_of = character()   # entry id -> turn number
  s$obj = ckpt_store(dir = dir); s$files = NULL
  s$records = list()                                                # entry id -> checkpoint record (in memory)
  s$undo_max_bytes = undo_max_bytes; s$capture_all_max = capture_all_max
  s$requests = list()                                               # serialised provider requests (for the cache test)
  hdr = list(type = "session", version = 3L, id = .id8(), timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"))
  .jsonl_append(s$file, hdr)
  s
}
.jsonl_append = function(file, x) {
  con = file(file, open = "ab"); on.exit(close(con))
  line = jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, dataframe = "rows")
  suspendInterrupts(writeLines(enc2utf8(as.character(line)), con, sep = "\n", useBytes = TRUE))
}
.append = function(s, type, ..., turn = NA_integer_) {
  e = list(type = type, id = .id8(), parentId = s$leaf, ...)
  if (is.null(e$parentId)) e["parentId"] = list(NULL)
  s$entries[[e$id]] = e; s$leaf = e$id
  s$turn_of[e$id] = as.character(turn)
  .jsonl_append(s$file, e)
  e$id
}
.path_to = function(s, id) { p = character(); while (!is.null(id)) { p = c(id, p); id = s$entries[[id]]$parentId }; p }

# Provider context = messages on the root-to-leaf path; custom entries are not sent (Pi).
# Each entry is serialised once, and the request body is a concatenation (G4 4.1 rule 3).
.provider_view = function(s, extra = NULL) {
  p = .path_to(s, s$leaf)
  msg = Filter(function(e) e$type == "message", s$entries[p])
  parts = vapply(msg, function(e) as.character(jsonlite::toJSON(e$message, auto_unbox = TRUE)), "")
  paste(c(parts, extra), collapse = ",")
}

# ---------------------------------------------------------------- one agent turn (fake model)
# The "model" answers with one run_r call whose code is given; the harness brackets the call
# with object, file and side-state checkpoints and appends a gptr.checkpoint custom entry.
turn = function(s, prompt, code, answer = "done") {
  k = max(c(0L, suppressWarnings(as.integer(s$turn_of[.path_to(s, s$leaf)]))), na.rm = TRUE) + 1L
  .append(s, "message", message = list(role = "user", content = prompt), turn = k)
  s$requests[[length(s$requests) + 1L]] = .provider_view(s)       # request 1 of the turn
  call_id = paste0("call_", .id8())
  .append(s, "message", message = list(role = "assistant", tool = "run_r", id = call_id, code = code), turn = k)
  rec = run_r_checkpointed(s, code)
  .append(s, "message", message = list(role = "toolResult", id = call_id, text = "ok"), turn = k)
  cid = .append(s, "custom", customType = "gptr.checkpoint",
                data = list(turn = k, tool_call = call_id, objects = rec$objects[, c("name", "status", "restorable", "reason")],
                            files = rec$files[, c("path", "status", "pre", "post", "restorable")],
                            state = rec$state_names), turn = k)
  s$records[[cid]] = as_record_env(rec)
  s$requests[[length(s$requests) + 1L]] = .provider_view(s)       # request 2 of the turn
  .append(s, "message", message = list(role = "assistant", content = answer), turn = k)
  invisible(s)
}

run_r_checkpointed = function(s, code) {
  env = s$envir
  owd = setwd(s$project); on.exit(setwd(owd), add = TRUE)       # the project root is the tool's working directory
  if (is.null(s$files)) { s$files = ckpt_tracker(s$project, ckpt_cas(file.path(dirname(s$file), "cas"))); ckpt_baseline(s$files) }
  else invisible(ckpt_file_step(s$files, by = "external"))   # absorb edits made outside gptr: never undone by a rewind
  tg = ckpt_targets(code)
  nm = ls(env, all.names = TRUE); nm = setdiff(nm, c(".Random.seed", ".Last.value"))
  kind = if (length(nm)) ckpt_binding_kind(env, nm) else character()
  nm = nm[kind == "value"]
  sizes = vapply(nm, function(n) as.numeric(utils::object.size(get(n, envir = env))), 0)  # cached by address in gptr
  addr0 = vapply(nm, function(n) rlang::obj_address(get(n, envir = env)), "")
  sem = vapply(nm, function(n) ckpt_semantics(env, n), "")
  predicted = union(union(tg$assign, tg$remove), tg$super)
  cap = nm[sem == "value" & (sizes <= s$capture_all_max | (nm %in% predicted & sizes <= s$undo_max_bytes))]
  deep = nm[sem == "by_ref_capable" & nm %in% tg$byref & sizes <= s$undo_max_bytes]
  pend = ckpt_capture(s$obj, env, cap)
  for (d in deep) {                                                   # data.table := / set(): eager deep copy
    k = .ckpt_key(s$obj, "pre"); assign(k, data.table::copy(get(d, envir = env)), envir = s$obj$slots)
    pend = rbind(pend, data.frame(name = d, key = k, address = "deep-copy", stringsAsFactors = FALSE))
  }
  st_pre = ckpt_state_snapshot(env)
  eval_ok = tryCatch({ for (e in parse(text = code, keep.source = FALSE)) eval(e, env); TRUE }, error = function(e) FALSE)
  st_post = ckpt_state_snapshot(env)
  settled = ckpt_settle(s$obj, env, pend)
  # deep copies: "unchanged" by address does not mean unchanged content; keep them if the fingerprint moved
  settled$restorable = TRUE; settled$reason = ""
  created = setdiff(setdiff(ls(env, all.names = TRUE), c(".Random.seed", ".Last.value")), nm)
  uncaptured = setdiff(nm, c(cap, deep))
  moved = vapply(uncaptured, function(n) !exists(n, envir = env, inherits = FALSE) ||
      !identical(rlang::obj_address(get(n, envir = env)), unname(addr0[n])), TRUE)
  mutated_ref = sem[uncaptured] != "value" & uncaptured %in% c(predicted, tg$byref)   # same address, new content
  changed_unc = uncaptured[moved | mutated_ref]
  objs = rbind(
    settled[settled$status != "unchanged", c("name", "status", "key", "post_address", "restorable", "reason")],
    if (length(created)) data.frame(name = created, status = "created", key = NA_character_,
      post_address = vapply(created, function(n) rlang::obj_address(get(n, envir = env)), ""), restorable = TRUE, reason = "",
      stringsAsFactors = FALSE),
    if (length(changed_unc)) data.frame(name = changed_unc, status = "changed", key = NA_character_, post_address = NA_character_,
      restorable = FALSE, reason = ifelse(sem[changed_unc] == "reference", "reference object (environment/R6/external pointer)",
                                          "over the undo budget: not captured"), stringsAsFactors = FALSE))
  rownames(objs) = NULL
  objs$redo = rep(NA_character_, nrow(objs))
  files = ckpt_file_step(s$files, by = "run_r")
  d = ckpt_state_diff(st_pre, st_post)
  list(objects = objs, files = files, state_pre = st_pre, state_post = st_post, state_diff = d,
       state_names = list(options = d$options, envvars = d$envvars, wd = d$wd, attached = d$attached, rng = d$rng),
       ok = eval_ok)
}
`%||%` = function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------- rewind / redo
# gptr_rewind(s, turn): keep turns 1..turn of the active path (negative = relative; 0 = start),
# or move to any entry id (redo onto an abandoned branch). Undo the checkpoint records between
# the current leaf and the target (newest first), redo the ones between the common ancestor
# and the target, append a gptr.rewind custom entry whose parent is the target (the new leaf,
# durable on reload), and return the SAME session object invisibly (pipe-friendly, S-8).
gptr_rewind = function(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"), force = FALSE) {
  restore = match.arg(restore)
  cur = .path_to(s, s$leaf)
  if (is.null(to)) {
    turns = suppressWarnings(as.integer(s$turn_of[cur])); last = max(c(0L, turns), na.rm = TRUE)
    keep = if (turn < 0L) last + turn else as.integer(turn)
    if (keep < 0L || keep > last) stop("turn out of range")
    firsts = cur[!is.na(turns) & turns == keep + 1L]
    target = if (length(firsts)) s$entries[[firsts[1L]]]$parentId else s$leaf
    prompt = if (length(firsts)) s$entries[[firsts[1L]]]$message$content else NULL
  } else { target = to; prompt = NULL }
  tpath = .path_to(s, target)
  lca = if (is.null(target)) character() else intersect(cur, tpath)
  undo_ids = rev(setdiff(cur, lca)); redo_ids = setdiff(tpath, lca)
  report = character()
  if (restore != "conversation") {
    for (id in undo_ids[undo_ids %in% names(s$records)]) report = c(report, .undo_record(s, s$records[[id]], force))
    for (id in redo_ids[redo_ids %in% names(s$records)]) report = c(report, .redo_record(s, s$records[[id]], force))
  }
  if (restore != "workspace") {
    s$leaf = target
    .append(s, "custom", customType = "gptr.rewind",
            data = list(from = cur[length(cur)], to = target, keep = if (is.null(to)) keep else NULL,
                        restore = restore, report = report))
  }
  attr(s, "rewind_report") = report
  attr(s, "editor_text") = prompt
  invisible(s)
}

.undo_record = function(s, rec, force) {
  out = character(); o = rec$objects; env = s$envir
  for (i in rev(seq_len(nrow(o)))) {
    nm = o$name[i]
    if (!o$restorable[i]) { out = c(out, sprintf("object %s: not restored (%s)", nm, o$reason[i])); next }
    if (o$status[i] == "created") {
      now = if (exists(nm, envir = env, inherits = FALSE)) rlang::obj_address(get(nm, envir = env)) else NA
      if (!force && !identical(now, o$post_address[i])) { out = c(out, sprintf("object %s: conflict, kept", nm)); next }
      k = ckpt_uncreate(s$obj, env, nm); rec$objects$redo[i] = k; out = c(out, sprintf("object %s: removed (created by the turn)", nm))
    } else {
      r = ckpt_restore(s$obj, env, nm, o$key[i], expect = if (o$status[i] == "removed") NA_character_ else o$post_address[i], force = force)
      if (isTRUE(r$ok)) rec$objects$redo[i] = r$redo
      out = c(out, sprintf("object %s: %s", nm, if (isTRUE(r$ok)) "restored" else r$reason))
    }
  }
  fu = ckpt_file_undo(s$files, rec$files, force = force)
  out = c(out, sprintf("file %s: %s", fu$path, fu$action))
  out = c(out, sprintf("state: %s", ckpt_state_undo(rec$state_pre, rec$state_post, rec$state_diff, env)))
  rec$undone = TRUE
  out
}
# Redo: put the displaced post-images back (objects from redo images, files from post blobs).
.redo_record = function(s, rec, force) {
  out = character(); o = rec$objects; env = s$envir
  for (i in seq_len(nrow(o))) {
    if (o$status[i] == "removed") {                                  # redo of a removal: remove again
      if (exists(o$name[i], envir = env, inherits = FALSE)) {
        pk = .ckpt_key(s$obj, "pre"); assign(pk, get(o$name[i], envir = env), envir = s$obj$slots)
        s$obj$index = rbind(s$obj$index, data.frame(key = pk, name = o$name[i], role = "pre", bytes = NA_real_,
          where = "memory", file = NA_character_, stringsAsFactors = FALSE)); rec$objects$key[i] = pk
        rm(list = o$name[i], envir = env); out = c(out, sprintf("object %s: removed again", o$name[i]))
      }
      next
    }
    k = o$redo[i] %||% NA_character_
    if (is.na(k) || !k %in% s$obj$index$key) { out = c(out, sprintf("object %s: not redoable (no redo image)", o$name[i])); next }
    if (exists(o$name[i], envir = env, inherits = FALSE)) {
      pk = .ckpt_key(s$obj, "pre"); assign(pk, get(o$name[i], envir = env), envir = s$obj$slots)
      s$obj$index = rbind(s$obj$index, data.frame(key = pk, name = o$name[i], role = "pre", bytes = NA_real_,
        where = "memory", file = NA_character_, stringsAsFactors = FALSE)); rec$objects$key[i] = pk
    }
    assign(o$name[i], get(k, envir = s$obj$slots), envir = env); ckpt_drop(s$obj, k)
    rec$objects$post_address[i] = rlang::obj_address(get(o$name[i], envir = env))
    out = c(out, sprintf("object %s: redone", o$name[i]))
  }
  f = rec$files
  for (i in seq_len(nrow(f))) {
    full = file.path(s$project, f$path[i])
    if (f$status[i] == "deleted") { unlink(full); out = c(out, sprintf("file %s: deleted again", f$path[i])); next }
    if (!is.na(f$post[i]) && cas_restore(s$files$cas, f$post[i], full)) out = c(out, sprintf("file %s: redone", f$path[i]))
    else out = c(out, sprintf("file %s: not redoable", f$path[i]))
  }
  s$files$stat = ckpt_walk(s$project); s$files$walk_time = as.numeric(Sys.time())
  rec$undone = FALSE
  out
}

# Checkpoint records are environments so undo/redo can annotate them in place.
as_record_env = function(rec) { e = list2env(rec, parent = emptyenv()); e }

# ---------------------------------------------------------------- runnable transcript (report 14 3.4)
# Projection of the WHOLE tree in file order: turns on the active path are live blocks; turns
# on abandoned branches are kept for the record but made inert ("#~ " prefix, status=undone),
# so source() of the transcript reproduces the rewound workspace and never re-asks an undone
# prompt. The rewind itself is a comment line.
render_transcript = function(s) {
  active = .path_to(s, s$leaf); out = c("# gptr session transcript (prototype)", "library(gptr)", "")
  ids = names(s$entries)
  for (id in ids) {
    e = s$entries[[id]]
    if (e$type == "message" && identical(e$message$role, "user")) {
      live = id %in% active
      k = s$turn_of[id]; code = s$entries[[ids[match(id, ids) + 1L]]]$message$code
      bid = substr(rlang::hash(id), 1L, 6L)
      head = sprintf("# >>> gptr:%s model=fake/1 prompt=%s%s", bid, substr(rlang::hash(e$message$content), 1L, 12L),
                     if (live) "" else " status=undone")
      body = strsplit(code, "\n", fixed = TRUE)[[1L]]
      call = sprintf("gptr(%s)", encodeString(e$message$content, quote = "\""))
      out = c(out, if (live) call else paste0("#~ ", call), head, if (live) body else paste0("#~ ", body),
              sprintf("# <<< gptr:%s", bid), "")
    }
    if (e$type == "custom" && identical(e$customType, "gptr.rewind")) {
      nr = sum(grepl("not restored|conflict", e$data$report))
      dest = if (!is.null(e$data$keep)) sprintf("%d (keep turns 1-%d)", e$data$keep, e$data$keep)
             else sprintf("entry %s (redo)", if (is.null(e$data$to)) "start" else e$data$to)
      out = c(out, sprintf("# /rewind %s: %d items restored or removed, %d not restored (session log %s)",
                           dest, length(e$data$report) - nr, nr, id), "")
    }
  }
  out
}
```

`p5/test_session.R`:

```r
# test_session.R -- rewind as a branch on one session object; append-only log; cache prefix;
# redo; reload; runnable transcript replay (G7 P5 + P6). House style: "=" and "|>".
w = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7"
for (f in c("p1/ckpt_obj.R", "p3/ckpt_files.R", "p4/ckpt_state.R", "p5/ckpt_session.R")) source(file.path(w, f))
ok = function(cond, msg) cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n")
root = file.path(tempdir(), "g7s"); unlink(root, recursive = TRUE)
proj = file.path(root, "proj"); dir.create(file.path(proj, "R"), recursive = TRUE)
sdir = file.path(root, "gptr-session"); dir.create(sdir)
writeLines("clean = function(d) d[complete.cases(d), ]", file.path(proj, "R", "clean.R"))
ws = new.env()                                             # the user's workspace (envir)
assign("counts", matrix(runif(2e6), 2000), envir = ws)     # 16 MB user object
assign("cfg", new.env(), envir = ws); ws$cfg$alpha = 0.05   # a reference object
s = new_session(ws, proj, sdir, undo_max_bytes = 1e9, capture_all_max = 1e8)

# three turns, steered with the pipe on ONE session object (S-8)
s |>
  turn("normalise the counts", "counts = log1p(counts); writeLines('normalised', 'log.txt')") |>
  turn("scale in place and tighten alpha", "counts[, 1] = 0; cfg$alpha = 0.01; pca = prcomp(counts[, 1:5])") |>
  turn("edit the cleaner and drop pca", "writeLines('clean = function(d) na.omit(d)', 'R/clean.R'); rm(pca); seed_draw = runif(2)")
invisible(lapply(s$records, function(r) { cat("checkpoint: objects\n"); print(r$objects[, c("name", "status", "restorable", "reason")], row.names = FALSE) }))
after3 = list(counts = ws$counts[1:3, 1:2], files = readLines(file.path(proj, "R", "clean.R")))
bytes_before = readBin(s$file, "raw", file.size(s$file))

# rewind to the end of turn 1 (undo turns 3 and 2), piping straight into a new prompt
t0 = proc.time()[[3]]
s2 = gptr_rewind(s, 1)
t_rw = proc.time()[[3]] - t0
writeLines(paste("  ", attr(s2, "rewind_report")))
ok(identical(s2, s), "gptr_rewind() returns the same session object (reference semantics, no silent fork)")
ok(isTRUE(all.equal(ws$counts[1:3, 1:2], log1p(ws$counts[1:3, 1:2] |> expm1()))) && !exists("pca", envir = ws) && !exists("seed_draw", envir = ws), "objects back to the end of turn 1 (pca and seed_draw gone)")
ok(ws$counts[1, 1] != 0, "in-place column edit undone")
ok(ws$cfg$alpha == 0.01, "reference object: NOT restored (alpha stays 0.01) and reported")
ok(readLines(file.path(proj, "R", "clean.R")) == "clean = function(d) d[complete.cases(d), ]", "file edit undone")
ok(file.exists(file.path(proj, "log.txt")), "turn-1 file kept")
bytes_after = readBin(s$file, "raw", file.size(s$file))
ok(identical(bytes_after[seq_along(bytes_before)], bytes_before) && length(bytes_after) > length(bytes_before), "session JSONL is append-only (old bytes unchanged, a rewind entry appended)")
view = .provider_view(s)
ok(startsWith(s$requests[[3]], view), "next request's prefix is byte-identical to turn 2's first request prefix (cache-friendly)")
ok(identical(attr(s, "editor_text"), "scale in place and tighten alpha"), "the undone prompt is handed back for editing (Pi /tree, Claude /rewind)")
cat(sprintf("rewind of 2 turns: %.3f s\n", t_rw))

# continue on the new branch, then redo onto the abandoned branch
old_leaf = names(s$entries)[which(vapply(s$entries, function(e) identical(e$customType, "gptr.checkpoint"), TRUE))[3]]
old_leaf = names(s$entries)[match(old_leaf, names(s$entries)) + 1L]        # final answer of the old turn 3
s |> turn("use a z-score instead", "counts = scale(counts)")
z_branch = ws$counts[1:2, 1:2]
s |> gptr_rewind(to = old_leaf)
writeLines(paste("   redo:", attr(s, "rewind_report")))
ok(isTRUE(all.equal(ws$counts[1:3, 1:2], after3$counts)) && identical(readLines(file.path(proj, "R", "clean.R")), after3$files), "redo onto the abandoned branch restores its objects and files")
ok(exists("seed_draw", envir = ws) && !exists("pca", envir = ws), "redo re-applies creations and removals of the abandoned turns")

# reload: the leaf on disk is the last entry, whose parent is the rewind target
lines = readLines(s$file); ents = lapply(lines[-1], jsonlite::fromJSON, simplifyVector = FALSE)
last = ents[[length(ents)]]
ok(identical(last$customType, "gptr.rewind") && identical(last$parentId, old_leaf), "reload: last entry is the rewind marker hanging off the target (durable leaf)")

# P6: the runnable transcript of this session replays to the live workspace
s |> gptr_rewind(1)
tx = render_transcript(s)
writeLines(tx, file.path(root, "transcript.R")); cat(tx, sep = "\n")
chk = file.path(root, "replay.R")
writeLines(c(
  "gptr = function(...) invisible(NULL)                    # stub: replay mode, never runs a model",
  "library = function(...) invisible(NULL)",
  sprintf("setwd('%s'); unlink(c('log.txt'))", file.path(root, "replay_proj")),
  "set.seed(1); counts = matrix(runif(2e6), 2000); cfg = new.env(); cfg$alpha = 0.05",
  sprintf("source('%s', local = TRUE)", file.path(root, "transcript.R")),
  "cat('replayed objects:', paste(sort(setdiff(ls(), c('gptr', 'library', 'counts0'))), collapse = ' '), '\\n')",
  "cat('replayed counts[1,1] = log1p(x):', isTRUE(all.equal(counts[1, 1], log1p(local({set.seed(1); runif(1)})))), '\\n')"), chk)
dir.create(file.path(root, "replay_proj", "R"), recursive = TRUE)
out = system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", chk), stdout = TRUE, stderr = TRUE)
writeLines(paste("   replay:", out))
ok(any(grepl("replayed objects: cfg counts", out)) && any(grepl("log1p\\(x\\): TRUE", out)), "source() of the transcript reproduces the rewound workspace (undone turns inert)")
live = sort(setdiff(ls(ws), character()))
cat("live workspace objects:", paste(live, collapse = " "), "\n")
```

```text
checkpoint: objects
   name  status restorable reason
 counts changed       TRUE       
checkpoint: objects
   name  status restorable                                             reason
 counts changed       TRUE                                                   
    pca created       TRUE                                                   
    cfg changed      FALSE reference object (environment/R6/external pointer)
checkpoint: objects
      name  status restorable reason
       pca removed       TRUE       
 seed_draw created       TRUE       
   object seed_draw: removed (created by the turn)
   object pca: restored
   file R/clean.R: restored
   object cfg: not restored (reference object (environment/R6/external pointer))
   object pca: removed (created by the turn)
   object counts: restored
PASS gptr_rewind() returns the same session object (reference semantics, no silent fork) 
PASS objects back to the end of turn 1 (pca and seed_draw gone) 
PASS in-place column edit undone 
PASS reference object: NOT restored (alpha stays 0.01) and reported 
PASS file edit undone 
PASS turn-1 file kept 
PASS session JSONL is append-only (old bytes unchanged, a rewind entry appended) 
PASS next request's prefix is byte-identical to turn 2's first request prefix (cache-friendly) 
PASS the undone prompt is handed back for editing (Pi /tree, Claude /rewind) 
rewind of 2 turns: 0.151 s
   redo: object counts: restored
   redo: object counts: redone
   redo: object pca: redone
   redo: object cfg: not redoable (no redo image)
   redo: object pca: removed again
   redo: object seed_draw: redone
   redo: file R/clean.R: redone
PASS redo onto the abandoned branch restores its objects and files 
PASS redo re-applies creations and removals of the abandoned turns 
PASS reload: last entry is the rewind marker hanging off the target (durable leaf) 
# gptr session transcript (prototype)
library(gptr)

gptr("normalise the counts")
# >>> gptr:f4355e model=fake/1 prompt=7969cf0150bf
counts = log1p(counts); writeLines('normalised', 'log.txt')
# <<< gptr:f4355e

#~ gptr("scale in place and tighten alpha")
# >>> gptr:bd76b5 model=fake/1 prompt=33bb08766792 status=undone
#~ counts[, 1] = 0; cfg$alpha = 0.01; pca = prcomp(counts[, 1:5])
# <<< gptr:bd76b5

#~ gptr("edit the cleaner and drop pca")
# >>> gptr:ac7b3a model=fake/1 prompt=35db9347fc9b status=undone
#~ writeLines('clean = function(d) na.omit(d)', 'R/clean.R'); rm(pca); seed_draw = runif(2)
# <<< gptr:ac7b3a

# /rewind 1 (keep turns 1-1): 5 items restored or removed, 1 not restored (session log ebdade2b)

#~ gptr("use a z-score instead")
# >>> gptr:826d8b model=fake/1 prompt=7d7d38276e69 status=undone
#~ counts = scale(counts)
# <<< gptr:826d8b

# /rewind entry 1502e14d (redo): 7 items restored or removed, 0 not restored (session log bd2d9c2e)

# /rewind 1 (keep turns 1-1): 5 items restored or removed, 1 not restored (session log d22938c9)

   replay: replayed objects: cfg counts 
   replay: replayed counts[1,1] = log1p(x): TRUE 
PASS source() of the transcript reproduces the rewound workspace (undone turns inert) 
live workspace objects: cfg counts 
```

### 5.7 P7: tokens, recompute recipe, export-name scan

`p7/tokens.R`:

```r
# tokens.R -- token cost of the model-facing parts of checkpoints and rewinds (o200k proxy; G7)
tok = function(x) rtiktoken::get_token_count(paste(x, collapse = "\n"), "o200k_base")
notice = "note: pbmc (5.1 GB) was overwritten without an undo copy (over the 1 GB undo budget)."
rewind_note = c(
  "<workspace_changes since=\"turn 3\" reason=\"rewind\">",
  "~ pbmc <Seurat> 3,012,448 x 33,538, 5.1 GB (not restored: over the undo budget; current value is from turn 5)",
  "~ cfg <environment> (not restored: reference object)",
  "file data/huge.bin (not restored: over the checkpoint size cap)",
  "</workspace_changes>")
pi_prefix = "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n</summary>"
full_restore = character()                                     # nothing to tell: context == turn 3
# model-driven revert instead of a harness rewind (what Codex recommends, discussion 9618):
# the model re-reads a 200-line R file and emits a reverting edit.
src = readLines("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p3/ckpt_files.R")[1:200]
read_result = src
revert_edit = c('{"path":"R/clean.R","old_text":"', src[40:70], '","new_text":"', src[40:70], '"}')
ask = "Undo your last change to R/clean.R and restore pbmc as it was before turn 4."
cat(sprintf("per-call notice when an object is not undoable:         %4d tokens (only when it happens)\n", tok(notice)))
cat(sprintf("rewind note (3 unrestored items, workspace-diff format):  %4d tokens\n", tok(rewind_note)))
cat(sprintf("rewind with everything restored:                          %4d tokens\n", tok(full_restore)))
cat(sprintf("Pi branch_summary wrapper alone (plus a model-written summary): %d tokens\n", tok(pi_prefix)))
cat(sprintf("model-driven revert of one file: prompt %d + read result %d + edit call %d = %d tokens (plus output tokens and a round trip)\n",
  tok(ask), tok(read_result), tok(revert_edit), tok(ask) + tok(read_result) + tok(revert_edit)))
cat("model-driven revert of an in-memory object: not possible without the old value (it must be recomputed or reloaded)\n")
```

```text
per-call notice when an object is not undoable:           25 tokens (only when it happens)
rewind note (3 unrestored items, workspace-diff format):    87 tokens
rewind with everything restored:                             0 tokens
Pi branch_summary wrapper alone (plus a model-written summary): 21 tokens
model-driven revert of one file: prompt 21 + read result 3300 + edit call 1028 = 4349 tokens (plus output tokens and a round trip)
model-driven revert of an in-memory object: not possible without the old value (it must be recomputed or reloaded)
```

`p7/recipe.R`:

```r
# recipe.R -- "recompute from recorded code": backward slice over the recorded history (G7).
# Given the live blocks of the runnable document up to turn k (report 14: user statements and
# recorded agent code, in order), return the minimal ordered statements that rebuild `name`.
# Printed as a suggestion; never executed automatically (it may take minutes and re-read data).
# House style: "=" and "|>".
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G7/p4/ckpt_state.R")

ckpt_recipe = function(history, name) {
  # history: data.frame(source, code), one row per top-level statement, in execution order
  ex = lapply(history$code, function(cd) parse(text = cd, keep.source = FALSE)[[1L]])
  tg = lapply(history$code, function(cd) { t = ckpt_targets(cd); unique(c(t$assign, t$byref, t$super)) })
  rhs_vars = lapply(ex, function(e) {
    v = all.names(e, functions = FALSE)
    if (is.call(e) && as.character(e[[1L]]) %in% c("=", "<-")) v = c(all.names(e[[3L]], functions = FALSE),
      if (is.call(e[[2L]])) all.names(e[[2L]], functions = FALSE))       # x[i] = v also reads x
    unique(v)
  })
  need = name; keep = logical(length(ex))
  for (i in rev(seq_along(ex))) {
    if (length(intersect(tg[[i]], need))) {
      keep[i] = TRUE
      need = union(setdiff(need, if (is.call(ex[[i]]) && is.name(ex[[i]][[2L]])) tg[[i]] else character()), rhs_vars[[i]])
    }
  }
  structure(history[keep, , drop = FALSE], unresolved = setdiff(need, unlist(tg[keep])))
}

history = data.frame(source = c("analysis.R:3 (user)", "analysis.R:4 (user)", "gptr:7f3a21 (turn 1)",
                                "gptr:7f3a21 (turn 1)", "gptr:9c01d2 (turn 2)", "gptr:9c01d2 (turn 2)", "gptr:a41b0e (turn 3)"),
  code = c("raw = read.csv('counts.csv')", "meta = read.csv('meta.csv')",
           "counts = as.matrix(raw[, -1])", "lib = colSums(counts)",
           "norm = t(t(counts) / lib) * 1e4", "plot(density(lib))", "norm[, 1] = 0"))
r = ckpt_recipe(history, "norm")
cat("recipe to rebuild `norm` as of turn 3:\n"); writeLines(sprintf("  %-34s # %s", r$code, r$source))
cat("unresolved free names (must come from outside the history):", paste(attr(r, "unresolved"), collapse = ", "), "\n")

# check: running the recipe in a fresh environment rebuilds the same object
d = tempfile(); dir.create(d); owd = setwd(d)
write.csv(data.frame(g = paste0("g", 1:5), a = 1:5, b = 6:10), "counts.csv", row.names = FALSE)
write.csv(data.frame(s = c("a", "b")), "meta.csv", row.names = FALSE)
full = new.env(); for (cd in history$code) eval(parse(text = cd), full)
grDevices::dev.off() |> invisible()
part = new.env(); for (cd in r$code) eval(parse(text = cd), part)
setwd(owd)
cat("recipe result identical to the full run:", identical(full$norm, part$norm),
    "| statements run:", nrow(r), "of", nrow(history), "\n")
```

```text
recipe to rebuild `norm` as of turn 3:
  raw = read.csv('counts.csv')       # analysis.R:3 (user)
  counts = as.matrix(raw[, -1])      # gptr:7f3a21 (turn 1)
  lib = colSums(counts)              # gptr:7f3a21 (turn 1)
  norm = t(t(counts) / lib) * 1e4    # gptr:9c01d2 (turn 2)
  norm[, 1] = 0                      # gptr:a41b0e (turn 3)
unresolved free names (must come from outside the history):  
recipe result identical to the full run: TRUE | statements run: 5 of 7 
```

Export-name scan (explicit exports of 662 installed packages, plus the namespaces of the 45 packages that use
`exportPattern`), run inline:

```r
libs = .libPaths(); pk = unique(unlist(lapply(libs, function(l) list.dirs(l, recursive = FALSE, full.names = FALSE))))
cand = c("gptr_rewind", "gptr_checkpoints", "gptr_checkpointer", "gptr_undo", "gptr_redo", "gptr_restore", "rewind", "checkpoints", "undo")
hits = setNames(vector("list", length(cand)), cand); n = 0; pat_pk = character()
for (p in pk) { ns = tryCatch(parseNamespaceFile(p, dirname(system.file(package = p))), error = function(e) NULL)
  if (is.null(ns)) next; n = n + 1
  for (cn in intersect(cand, ns$exports)) hits[[cn]] = c(hits[[cn]], p)
  if (length(ns$exportPatterns)) pat_pk = c(pat_pk, p) }
for (p in pat_pk) { e = tryCatch(suppressMessages(suppressWarnings(asNamespace(p))), error = function(e) NULL); if (is.null(e)) next
  for (cn in cand) if (exists(cn, envir = e, inherits = FALSE)) hits[[cn]] = c(hits[[cn]], paste0(p, "(pattern)")) }
cat("packages scanned:", n, "(", length(pat_pk), "with exportPattern, namespaces inspected )\n")
for (cn in cand) cat(sprintf("%-18s %s\n", cn, if (length(hits[[cn]])) paste(hits[[cn]], collapse = ", ") else "-"))
```

```text
packages scanned: 662 ( 45 with exportPattern, namespaces inspected )
gptr_rewind        -
gptr_checkpoints   -
gptr_checkpointer  -
gptr_undo          -
gptr_redo          -
gptr_restore       -
rewind             -
checkpoints        -
undo               -
```

Prototype simplifications that the implementation must not copy:
- `ckpt_session.R` deep-copies predicted data.table targets and then keeps them without a fingerprint comparison.
- It stores records only in memory; the JSONL carries a subset.
- `render_transcript()` regenerates the whole file.
- `ckpt_walk()` lacks the canonical-path cycle guard for Windows junctions (§6).
- `ckpt_targets()` is a compact walker; the real one is shared with `gptr_risk()` (report 18, 101/101 cases).

---

## 6. CRAN and cross-platform (Windows) considerations

- **Write locations (CRAN policy; 13).**
  - Blobs, spilled images and records go only under a consented `.gptr/` or under `tempdir()`.
  - Pruning by age (30 days) and bytes (2 GB / 1 GB) is the "actively managed" requirement (policy text quoted in
    17's verification log).
  - Nothing is written in `~`, `.git` or `R_user_dir` for blobs.
- **Global environment.**
  - Objects are restored through the captured `envir` (usually `globalenv()` via `parent.frame()`), never by
    naming `.GlobalEnv`.
  - `.Random.seed` is restored with `assign(".Random.seed", seed, envir = envir)` only when `envir` is the global
    environment, so R CMD check's literal-`.GlobalEnv` detection (12 B2) is not triggered (LIKELY; no check run
    here).
  - Document in `?gptr_rewind` that RNG state is restored; `gptr.checkpoint_rng = FALSE` opts out.
- **Tests.**
  - The copy-safety cases (c02-c17, the serialize and finalizer cases) as fresh-process tracemem tests guarded by
    `skip_if_not(capabilities("profmem"))`.
  - Tests over 100 MB under `skip_on_cran()`.
  - File tests in `withr::local_tempdir()`.
  - Ids from `rlang::hash()` of time, pid and a counter: `.Random.seed` is untouched (the prototype never calls
    `sample()`; note that report 11's `write_bytes_atomic()` temp name uses `sample()` and must change).
- **Dependencies.** rlang (`hash_file`, `obj_address`, `env_binding_are_*`) and jsonlite are already proposed
  Imports; add the base package `methods`. data.table stays in Suggests (method body guarded).
- **Windows** (not executed here; from 11, 13 and 02 findings and R docs):
  - `file.rename()` onto a file locked by Excel or antivirus retries 10 x 500 ms and then fails (11). The restore
    falls back to an in-place write. If that fails too, the report says "could not be updated", like Claude's "No
    files were restored", and the blob stays available.
  - Junctions are invisible to `Sys.readlink` (11), so the walker needs a `normalizePath()` cycle guard.
  - `Sys.chmod` only toggles read-only.
  - NTFS mtime is 100 ns, FAT and SMB 2 s: the racy-clean window covers them.
  - JSONL uses binary `"ab"` connections (no CRLF, 02).
  - Blob paths stay short (`.gptr/checkpoints/blobs/ab/<32 hex>.gz`, about 60 characters under the project root)
    for MAX_PATH.
  - Case-insensitive names: the tracker uses on-disk names from the walk; a case-only rename is a delete plus a
    create.
  - `tempdir()` lives under `%LOCALAPPDATA%\Temp`.
  - Memory behaviour (reference counts) is the same R code on all platforms (LIKELY).

---

## 7. Risks and open questions

Risks:
1. **Dependence on R internals.** The design relies on "rm() decrements, garbage collection does not", on
   `SET_VECTOR_ELT` decrementing, and on `serialize()`'s argument handling. These are observable behaviours of
   R 4.4.3, not documented API. The regression suite must run on R-release and R-devel.
2. **Structural sharing.** While a list or data.frame pre-image is held, the user's first in-place edit of each
   shared column copies that column once (capture-all: `df$a`). This is bounded by `gptr.undo_turns` and removed
   by defuse on drop.
3. **Unpredicted by-reference mutation.** A user function that calls `data.table::set()`, or modifies an
   environment, corrupts a by-reference pre-image silently. It is detected only by sampled fingerprints (21 §2.9
   gap), and the rewind then reports "restored" for a changed object. Mitigation: mark every data.table and
   environment "not verified" unless deep-copied.
4. **Walk cost on big trees.** 0.7-1.4 s per call on a 4k-file, many-directory tree (measured); monorepos are
   worse. Adaptive scanning (§3.5) is designed but not prototyped.
5. **Background child processes** that keep writing after the tool call returns are attributed to "external" at
   the next turn and are never undone.
6. **ALTREP size estimates** can wrongly exclude cheap objects from capture (UNCERTAIN).
7. **Spilled images after a restart** can only be restored with `force = TRUE`.
8. **Irreversible external effects** (network, databases, processes, files outside the project) are reported, not
   undone. Users may still over-trust `/undo`, so the docs must say it plainly, as Claude and opencode do.
9. **Windows, Linux, RStudio, Positron and Jupyter were not executed.**
10. **Timings** were taken at load 5-23; absolute times vary 2-3x between runs.

Open questions for the design lead and maintainer:
1. Default for devices opened by an undone turn: close them (consistent state) or leave them open (the user may be
   looking)? Proposed: leave open.
2. Should `!code` typed in the REPL (direct R, no model) be checkpointed as "user steps", so that `/undo` can
   revert it? Claude Code does not checkpoint `!` commands.
3. Should the memory budget be relative to RAM? That needs `ps::ps_system_memory()`; ps is already in the
   processx closure but would have to be declared.
4. Should spilled images in `.gptr/` survive R restarts by default (disk cost) or be deleted at session end?
5. Should a rewind summarise the abandoned branch for the model by default (Pi offers it; Claude does not)?
   Proposed: no.
6. `turn =` numbering in scripts with nested or looped `gptr()` calls on one session: should turns be counted per
   session (proposed) or per document block?
7. Ship the shadow-git checkpointer as an example plugin (like Pi's `git-checkpoint.ts`) or leave it to third
   parties?

---

## 8. Sources

Local reports (dev/research/; verification logs override bodies):
- 18 §4.8, lines 879-880 and 986, A.13 (`h1_snapshot.R`), verification row 28.
- 12 A8, B2, C2-C5, §3.8, §5.2.
- 21 §2.9-§2.10.
- 11 lines 29, 157, 588, 1899-1928, 3737, 3753.
- 20 line 254 (`codex features list`: `undo` removed), line 484 (Claude checkpointing), §4.3 lines 942-946.
- 02 §2.11, §3.4, §4.6.
- 14 §3.1, §3.4, §3.7, §4.3-§4.5.
- 13 (digest: consent, tempdir, pruning).
- 15 (digest: binding guard, reference objects).
- 17 lines 339-353 (`artifact.json`, `current`).
- G1 §3.1-§3.3, §4.7.
- G4 §3.5, §4.1-§4.3.5.

Pi source (clone `1b34779`, 2026-09-29):
- `packages/coding-agent/src/core/session-manager.ts` 1103-1122, 1579-1625;
- `.../agent-session.ts` 3866-4060;
- `.../messages.ts` 19-24;
- `docs/sessions.md`;
- `examples/extensions/git-checkpoint.ts`.

R 4.4.3 source (fetched 2026-09-29):
- `https://raw.githubusercontent.com/wch/r-source/tags/R-4-4-3/src/main/memory.c` (1281-1302, 4165-4178, 1023);
- `.../src/main/envir.c` (394-409, 789-820);
- `base::serialize` printed in the session.

Codex:
- clone `8ea2c0e` `codex-rs/core/src/config/mod.rs:225-250`;
- `https://github.com/openai/codex/discussions/9618` (maintainer statement 2026-01-21);
- issues #9203, #9280 (requests to restore `/undo`).

Claude Code docs (fetched 2026-09-29):
- `https://code.claude.com/docs/en/checkpointing.md`;
- `https://code.claude.com/docs/en/errors.md` (rewind section);
- `https://code.claude.com/docs/en/claude-directory.md` (`file-history/`);
- `https://code.claude.com/docs/en/settings-reference.md` (`fileCheckpointingEnabled`, `cleanupPeriodDays`).

Other harnesses:
- Gemini CLI: `https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/checkpointing.md`.
- opencode: `https://opencode.ai/v2/docs/snapshots/`.
- Aider: `https://aider.chat/docs/usage/commands.html`.

Packages:
- rlang 1.1.7 `?hash` (XXH128, streaming, `hash_file()` vectorised);
- Seurat and SeuratObject 5.4.0, data.table 1.18.2.1, profmem, lobstr 1.2.0, rtiktoken (o200k_base) from the
  private library.

---

## Verification log

Adversarial fact-check, 2026-09-29. Method: every prototype in section 5 was copied to
`scratchpad/work/verify-G7/g7/` (paths rewritten, code otherwise unchanged; all 20 embedded code blocks were first
confirmed byte-identical to the G7 scratch files) and re-run with `run_all.sh` in fresh `Rscript --vanilla`
processes (R 4.4.3, private library), plus two extra samples of the disputed timings (load 7-17). Sources were
re-read first-hand (Pi clone `1b347794`, Codex clone `8ea2c0e`, R 4.4.3 source, vendor docs via WebFetch).
Body text has been corrected where noted; section 5 still embeds the original final run.

| # | Claim | Verdict | Source / evidence |
|---|---|---|---|
| 1 | Reference counts fall only when a field or binding is replaced; `rm()` reaches `RemoveFromList`; the collector never decrements (§1.1, §2.3) | VERIFIED; wording CORRECTED | `memory.c`: `DECREMENT_REFCNT` appears only in `FIX_REFCNT_EX` (1282-1297, line 1292), the argument cleanup (4327-4328) and the exported wrapper at 3869 (the report had called all sites "setters" and omitted 3869); no site in `TryToReleasePages`/`ReleaseLargeFreeVectors`/`R_gc_internal`; `SET_VECTOR_ELT` uses `FIX_REFCNT` at 4174. `envir.c`: `do_remove` → `RemoveVariable` (1936-1976) → `R_HashDelete` (394-409, global env is hashed) or `RemoveFromList` (789). Function bodies cross-checked against `raw.githubusercontent.com/wch/r-source/tags/R-4-4-3/src/main/envir.c` |
| 2 | Copy-safety matrix: `mget()` snapshot copies on the agent edit (c02) and leaves a sticky reference after drop + `gc()` (c03); env binding + `rm()` is clean (c05); store GC without `rm()` is sticky (c06) and a finalizer fixes it; defuse needed for list/S4 images (c12, c12d); 24 EDIT verdict lines over 22 cases | VERIFIED | `p1_cases.txt`, `p1_finalizer.txt` re-run: byte-identical to the report |
| 3 | In-store defuse (v1) does not release; take-out-then-overwrite (v4, v5) does, compiled or not | VERIFIED | `p1_defuse_variants.txt` byte-identical |
| 4 | `serialize(x, con)` without `ascii =` leaves a sticky reference via `missing(ascii)` → `summary(connection)`; explicit `ascii = FALSE` and `saveRDS()` do not | VERIFIED | `p1_serialize.txt` byte-identical; `print(base::serialize)` in R 4.4.3 shows the branch exactly as quoted |
| 5 | 1 GB strategy matrix: by-reference penalty 1,000 MB on in-place edit, 954 MB held, 0 MB on the user's next edit in every strategy; restore ok | VERIFIED (allocations exact) | `p2_matrix.txt` re-run: every `*_alloc_mb`/`retained_mb`/`restored_ok` value identical |
| 6 | Timing ranges "over all runs" (eager serialize 0.29-0.44 s capture / 0.13-0.34 s restore, spill 0.31-0.81 s, spill op 0.13-0.14 s, 10 MB ≤ 13 ms / ≤ 10 ms, "0.3-0.4 s/GB" in the permission prompt) | CORRECTED | Re-runs measured eager serialize capture 0.30-0.70 s and restore 0.23-0.60 s, spill 0.28-0.92 s, spill-case op 0.11-0.22 s, 10 MB capture up to 14 ms (`saveRDS`) and restore up to 12 ms (recompute). Ranges in §1, §2.4, §3.4, §4.5 widened; orders of magnitude and the design are unaffected |
| 7 | Seurat 368 MB object: pre-image holds 0.00 / 0.80 / 362.29 MB (lobstr) for meta / `NormalizeData` / `subset`; estimator 2.04 / 0.36 / 362.64 MB; no copy penalty | VERIFIED | `p2_seurat.txt` re-run: all MB figures identical; Seurat/SeuratObject 5.4.0, data.table 1.18.2.1, lobstr 1.2.0 confirmed in the library |
| 8 | Capture-all of 500 bindings (1.03 GB) costs milliseconds; untouched 1 GB object stays editable in place; shared `df` column copies once | VERIFIED; timings widened slightly | `p2_capture_all.txt`: statuses and verdicts identical; sizes 16 ms, settle 7 ms (report 13-15 / 4-6 ms) |
| 9 | File scenario 9/9 PASS: created file removed, deleted file restored, in-place `write.csv` undone, user edit kept as conflict, untracked 30.6 MB file and symlink skipped, dedupe, pruning | VERIFIED; undo time widened | `p3_test_files.txt` identical except timings; undo 73-104 ms in re-runs (report 65-78 ms) |
| 10 | Tree costs: Pi walk 0.116-0.121 s, baseline 1.08-1.28 s, no-change step 0.10-0.17 s; library tree walk 0.73-0.86 s, step 0.66-0.98 s | CORRECTED | Re-runs: Pi walk 0.118-0.242 s, baseline 1.34-1.87 s, step 0.12-0.21 s, second session 0.32-0.38 s; library walk 0.81-1.27 s, step 0.97-1.40 s. §1.7, §2.7, §7 risk 4 updated. Blob counts/sizes (8.6 MB, 46.2 MB) identical |
| 11 | Hashing: rlang 11-14 ms vs md5 190-280 ms on 100 MB; rlang XXH128 streaming and vectorised | VERIFIED; caveat ADDED | `p3_bench_hash.txt` (12 ms vs 238 ms); rlang 1.1.7 `?hash`. The same output shows md5 ~2x faster than rlang on the 2,081 small files; note added in §2.7 |
| 12 | Side-state undo (options, env vars 3-way, wd, attach, devices, connections) and RNG stream continuity; target prediction table | VERIFIED | `p4_state.txt` identical (73 options, 95 env vars; all PASS) |
| 13 | Rewind on one session object, 13/13 PASS: same object, JSONL byte-append-only, next request prefix byte-identical, redo, durable leaf on reload, transcript replay | VERIFIED; time widened; cache claim DOWNGRADED | `p5_session.txt` identical modulo random ids; rewind 0.146-0.173 s (report text said 0.12-0.13 s while its own embedded output showed 0.151 s). The test proves byte identity only, so "the prompt cache survives" is now LIKELY in §1.8, §1.10, §2.10, §4.3, §4.7 |
| 14 | Token costs 25 / 87 / 0 / 21 / 4,349 (o200k proxy) | VERIFIED | `p7_tokens.txt` identical (rtiktoken 0.0.7) |
| 15 | Recompute recipe rebuilds `norm` identically running 5 of 7 statements | VERIFIED | `p7_recipe.txt` identical |
| 16 | `gptr_rewind`, `gptr_checkpoints`, `gptr_checkpointer` and 6 other names collide with nothing in 662 packages (45 with `exportPattern`) | VERIFIED | Inline scan re-run: same counts, no hits |
| 17 | Pi: `branch()` 1579-1584, `resetLeaf()` 1591-1593, `branchWithSummary()` 1600-1625 (`fromId` = old leaf), leaf on load = last entry in file order (1107-1111), `navigateTree()` puts user text in the editor and sets leaf to parent (3990-4005), branch-summary prefix in `messages.ts`, `git-checkpoint.ts` 53 lines on `turn_start`/`session_before_fork`, `/clone` exists | VERIFIED | Pi clone `1b347794`. Detail: the example also listens on `tool_result` and clears its map on `agent_settled` |
| 18 | Claude Code: checkpoint per turn-starting prompt; 100 most recent checkpoints; retention ~30 days via `cleanupPeriodDays`; Bash changes, subagent edits, mid-turn messages not checkpointed; symlinks/hard links skipped; menu actions; prompt returns to input; `file-history/<session>/`; `fileCheckpointingEnabled` | VERIFIED; "rewind overwrites external changes" DOWNGRADED to LIKELY (the docs describe no conflict check but do not say so) | `code.claude.com/docs/en/checkpointing.md`, `settings-reference.md`, `claude-directory.md` (fetched 2026-09-29) |
| 19 | Codex removed `/undo` (maintainer quote, 2026-01-21); "after ghost commits polluted users' repositories (maintainer statement)"; "102 GB of orphan objects in a 5.7 GB repository" | Quote VERIFIED; attribution CORRECTED | Discussion #9618: the maintainer said only that the design "caused problems for many users". The ghost-commit pollution description and the 102 GB figure come from a user comment (S2thend, 2026-08-21), and the 102 GB concerns Codex Desktop's `refs/codex/turn-diffs/` checkpoints (#29388), not the CLI `/undo`. §1.7 and §2.2 fixed |
| 20 | Codex compatibility-only ghost-snapshot config with defaults 10 MiB / 200 files | VERIFIED | Clone `8ea2c0e`, `codex-rs/core/src/config/mod.rs` 225-226 (constants), 233-250 (struct and `Default`) |
| 21 | Gemini CLI: shadow git in `~/.gemini/history/<project_hash>`, conversation JSON, `/restore` re-proposes the tool call, disabled by default | VERIFIED | `gemini-cli/docs/cli/checkpointing.md` |
| 22 | opencode: internal Git object DB under its data directory; snapshots before each model call and at step end; untracked files under 2 MiB; "including changes made by shell commands to them" | Partly VERIFIED; shell-edit coverage DOWNGRADED to LIKELY | `opencode.ai/v2/docs/snapshots/`: "Non-ignored untracked files up to 2 MiB each". The page never states that shell edits to covered files are restored; its Safety note lists shell effects on ignored output, Git state and files outside the directory as not reversed. §2.2 and §3.7 reworded |
| 23 | Aider `/undo` quote | VERIFIED | `aider.chat/docs/usage/commands.html` |
| 24 | ALTREP `1:1e9`: `object.size()` 3.7 GB for 680 B | VERIFIED | Re-run: `object.size` 3.7 Gb, `lobstr::obj_size` 680 B |
| 25 | §1.11 "No new Imports" vs §4.8/§6 "add `methods` to Imports" | CORRECTED (internal inconsistency) | §1.11 now says no new non-base Imports; `methods` is added |

Not verifiable here (left as stated, with their existing labels): all Windows behaviour in §6 (`file.rename` retries,
junctions, `Sys.chmod`, MAX_PATH); RStudio, Positron and Jupyter; whether a provider cache actually hits after a
rewind (byte identity only); R CMD check's reaction to `assign(".Random.seed", ...)` (LIKELY); adaptive scanning
and the shadow-git backend (not prototyped); the historical "first run" of c12 without defuse (not in the final
outputs).
