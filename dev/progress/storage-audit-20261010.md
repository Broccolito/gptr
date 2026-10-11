# Workspace storage audit (2026-10-10)

Scope: static review at `89525673ae4d9e8c76da0526a134e59de03615d1`, with one read-only
path-review child, followed by the authorized disposable offline regressions below.
No provider, installer, browser or package-check job was started.
The real repository `.gptr/`, credential files and user state were not read or changed.
Findings 1, 2, 3 and 5 have disposable offline witnesses below; private creation modes
remain a static review nomination. No executable RDS payload was used.
CodeGraph is absent. Conventions, architecture sections 6.9/6.10 and contract section 15
(especially IC-51/52/59/70/71) govern the expected behavior.

## Findings and proposed offline witnesses

1. **P1: cache/checkpoint cleanup can leave its owned directory through a directory symlink.**
   [doc_cache_files()](/Users/wgu/Desktop/gptr/R/doc-replay.R:1084) recursively lists S1/S2
   JSON files without checking resolved containment; [doc_cache_remove()](/Users/wgu/Desktop/gptr/R/doc-replay.R:1139)
   removes those returned paths. POSIX recursive `list.files()` follows directory symlinks,
   as documented in the [R manual](https://stat.ethz.ch/R-manual/R-devel/library/base/help/list.files.html).
   Thus a link `.gptr/cache/s1/aa -> outside` makes `clear` remove `outside/victim.json`.
   Witness: one genuine cache entry and an outside sentinel JSON; `info` must not count
   outside data, and `clear`/old-entry `prune` must preserve its bytes and existence. Repeat
   for S2 and a linked cache-kind root. The same unchecked recursive enumeration appears in
   [checkpoint GC](/Users/wgu/Desktop/gptr/R/ckpt-files.R:117), followed by `unlink()` of old
   unreferenced paths; include an aged outside blob sentinel in the witness.
   Nomination: validate each storage-kind root against the workspace before listing, then
   check each resolved candidate against that owned root before removal; retain the existing
   sidecar and live-lock rules.

2. **P1: automatic instruction discovery bypasses the guarded-include boundary.**
   [context_instruction_files()](/Users/wgu/Desktop/gptr/R/prompt-context.R:196) accepts linked
   AGENTS/CLAUDE/vignette files; [context_instruction_items()](/Users/wgu/Desktop/gptr/R/prompt-context.R:306)
   reads them directly. Unlike [@file includes](/Users/wgu/Desktop/gptr/R/prompt-context.R:258),
   neither resolved project containment nor `context_file_guarded()` is checked. Untrusted
   manual/plan calls still include project instructions, merely marked `trusted="false"`.
   Witness: each discovered project filename linked to an outside synthetic sentinel and an
   in-project synthetic `.env`; neither sentinel may reach first-message/update context.
   Ordinary instruction files, the separately selected user-level instruction file and safe
   includes must still work. Nomination: reuse the existing containment/guard rule for
   project-discovered files; preserve user-directory handling explicitly.

3. **P1 candidate on Windows: project sidecars are deserialized before provenance checks.**
   [doc_sidecar_trusted()](/Users/wgu/Desktop/gptr/R/doc-io.R:362) returns TRUE on Windows;
   [doc_sidecar_read()](/Users/wgu/Desktop/gptr/R/doc-io.R:405) then calls `readRDS()` before
   structural validation. [gptr_doc(existing)](/Users/wgu/Desktop/gptr/R/doc-replay.R:889)
   triggers recovery, as does the block-listing path. The source itself describes unsafe
   planted RDS data on older supported R versions; this review has not run an executable
   payload and does not infer an exploit on current release from that comment.
   Witness: instrument the reader with mocked Windows and a synthetic project sidecar;
   unproven project bytes must be rejected before deserialization. Retain valid own-process
   and dead-process recovery coverage. Nomination: fail closed when provenance cannot be
   established; evaluate a plain-data sidecar format rather than loading arbitrary R objects.

   Further static review: IC-51 requires a later process to recover a dead writer; live-PID
   records stay deferred, while re-running that script adopts dead upserts and writes at exit.
   Denying every Windows read or accepting only this process's PID would break legitimate
   recovery. Existing tests write dead/PID-reused/adopted records through the production writer
   (`test-doc-io.R:346` onward); only the private-mode provenance test skips Windows.
   [R Core's CVE patch reply](https://stat.ethz.ch/pipermail/r-devel/2024-April/083393.html)
   identifies the older-R backport, separately from any unrun gptr payload experiment.

   The initial child proposal relocated Windows sidecars to user storage. Root rejected that
   migration in favor of versioned plain-data JSON at the same project location, preserving
   cross-process recovery on every platform. The selected repair and its evidence are below.
   A reader spy returning only a benign object establishes zero legacy RDS reads on mocked
   Windows without an executable payload. JSON removes R object deserialization but does
   not authenticate supplied upserts or authorize executing generated document code.

4. **P2 candidate: private transcripts and compressed file pre-images inherit public umask.**
   New [session JSONL writes](/Users/wgu/Desktop/gptr/R/session-store.R:114) use `file(...,"wb")`
   without a private-mode creation step. Workspace/session parents use default directory
   modes ([init](/Users/wgu/Desktop/gptr/R/gptr-config.R:1461),
   [ws_path](/Users/wgu/Desktop/gptr/R/utils-paths.R:276)).
   [Compressed checkpoint blobs](/Users/wgu/Desktop/gptr/R/ckpt-files.R:58) similarly open an
   ordinary `gzfile()` temporary path. Under umask 022 in a readable shared project, session
   conversations and a private source file's compressed pre-image can become readable to
   other accounts. Git ignore rules do not provide filesystem confidentiality.
   Witness: disposable readable project, scoped umask 022, a synthetic private text file and
   fake transcript; new sensitive files must be private before bytes are written, and
   appending/resuming must preserve content and existing permissions. Windows needs an
   explicit ACL qualification rather than an octal-mode claim. No host mode was inspected.

5. **P2 candidate: a concurrent edit during temporary preparation can be overwritten.**
   [doc_write()](/Users/wgu/Desktop/gptr/R/doc-io.R:144) checks the original MD5 before calling
   `write_atomic()`. The [successful rename path](/Users/wgu/Desktop/gptr/R/utils-paths.R:63)
   returns without another comparison; the later MD5 comparison covers only rename failure.
   Witness: change a disposable target during temporary-file writing, permit the normal
   rename, and require a conflict preserving the new editor text. Nomination: check the
   destination immediately before replacement; do not claim this alone eliminates every
   operating-system race. Existing intentional overwrites through tool/user verbs remain.

Linked `.gptr/` or owned subdirectories are also accepted solely through `dir.exists()`
([workspace_dir](/Users/wgu/Desktop/gptr/R/utils-paths.R:257),
[gptr_init](/Users/wgu/Desktop/gptr/R/gptr-config.R:1457)). Internal appends can therefore go
outside the named project. This needs an explicit ownership decision: either reject an
escaped storage link or obtain consent to the resolved destination. A user intentionally
choosing a linked storage directory is not by itself an exploit. Test a linked workspace
and linked `sessions/` separately while preserving the outside sentinel directory.

## Expected tree and incremental-operation oracles

Only `gptr_init(project)` or an interactive affirmative creates project storage. Initial
creation has exactly `settings.json`, optional `vignette.Rmd`/`.gitignore`, and empty
`skills/`, `agents/`, `prompts/`; it must not populate a full analysis workspace. A second
init must preserve all existing file bytes. Trust and remembered answers belong at user
scope, not in this project tree. No-workspace operations use process memory or `tempdir()`.

| Operation in a disposable project | Expected incremental storage and invariants |
|---|---|
| Init, then init again | Only the initial template paths; repeat leaves edited settings/instructions/ignore bytes unchanged. No silent `.Rbuildignore` write. |
| Fake-provider prompt, continuation | One `sessions/<UTC>_<id>.jsonl` tree file; header plus append-only entries. Continuation appends to the same file, without exporting caller objects. |
| Session shutdown/resume/fork | Owned lock released on shutdown; resume rebuilds conversation, not the user's analysis objects. A fork creates its own file lazily and preserves the parent file. |
| File read / read-only R tool | Bounded result text enters the session; no obligatory dataset copy. Checkpoint bookkeeping may appear, so compare paths and recorded entries rather than assuming zero bytes. |
| File/object edit | Supported pre-images under `checkpoints/blobs/` or `checkpoints/objects/`; mode/content restored by guarded rewind. File tracker excludes storage/VCS and does not follow file links. |
| System 1 classification | Memory cache before init; afterward `cache/s1/salt` plus hash-sharded answers. No input or question text in cache records; salt and answers are committed by default. |
| Recorded R/Rmd/qmd call | Only the consented document block plus S2 answer cache/session record; procedural code, not mandatory full-data serialization. Preserve unrelated text/EOL/BOM/final newline. |
| Deferred script / open notebook | Private versioned `cache/tmp/pending-<hash>.json` persists upserts until exit/recovery or explicit notebook sync. Retained legacy `.rds` peers remain intact. An open notebook stays unchanged on disk. |
| Plan / console transcript | `plans/<date>-<slug>.md` or consented transcript target; unique plan filename, same-session transcript pipe, no control/protected/outside remembered target. |
| Artifact | `artifacts/<id>/app.R`, metadata and version directories; optional data snapshots and run logs are separate intentional storage costs. No automatic browser launch in unattended calls. |
| Cache prune/clear | S1 age 90 days; S2 removed only when its block/queue is known gone; tmp age `spill_days` (default 7). Sidecars remain. Foreign targets must remain untouched. |
| Checkpoint GC | Retain every session-referenced blob and skip another live session holder; only unreferenced old owned content is removed. Sessions/documents are not general cache garbage. |

The installed [gitignore template](/Users/wgu/Desktop/gptr/inst/templates/gitignore) excludes
sessions, S2/tmp caches, checkpoints, artifact data/run output, locks and transcripts.
S1 answers/salt, plans and artifact source remain commit-eligible and can reveal analytical
choices or quoted values. The security help documents this distinction; redaction covers
registered secrets, not all private scientific data. Sidecar retention is intentionally
unbounded until recovery/sync and must not be described as automatic age-based deletion.

Existing positive boundaries: [session_append()](/Users/wgu/Desktop/gptr/R/session-object.R:177)
redacts before in-memory/persisted ingress; JSONL appends close their own connection and
recover torn lines; hash/session IDs limit filename characters; remembered transcript
targets use resolved containment; [atomic writes](/Users/wgu/Desktop/gptr/R/utils-paths.R:49)
create private temporary files; [checkpoint walks](/Users/wgu/Desktop/gptr/R/ckpt-files.R:161)
do not follow symbolic links; scrub traversal checks roots and does not grant authority to
paths named in transcripts. These protections must remain in every proposed fix.

## Authorized offline containment repair

Root selected findings 1 and 2 and granted one serial, capped, low-priority offline R slot.
The new `test-storage-boundaries.R` uses disposable projects, synthetic JSON/blob/private
sentinels and the fake session helper; it never opens the real workspace or a credential.

The first witness produced 52 failures/26 passes; expanding it to temporary cache files
produced **62 failures/32 passes, zero counted warnings/skips**. The failures include actual
loss of foreign sentinel files and synthetic private text entering first/update and plan
context. Missing sentinels intentionally skip the subsequent byte-comparison assertion, so
GREEN's assertion total is larger.

The minimal repair uses existing `path_inside()` and `context_file_guarded()` only:

- Cache enumeration checks the cache/kind roots against the workspace before listing, then
  filters resolved candidates to that owned kind. Sidecars remain separate and unremoved.
- Checkpoint GC skips escaped store, session, blob or object roots, and escaped session files
  before reading them. It filters listed blob/spill/object candidates to their owned root;
  existing reference, age and live-lock retention rules are unchanged.
- Automatic project instruction discovery applies the same containment and protected-file
  guard as explicit vignette includes. Separately selected user-scope instructions and
  ordinary project files remain available.

Focused GREEN: **108 passes, zero failures/countable warnings/skips**, 1.2 s test context.
Positive witnesses cover cache-kind and blob-directory links resolving inside owned storage,
safe project instruction links and user-level instructions. The platform witness ran on
macOS with working symlink creation; Windows behavior remains hosted validation work.
The existing R/testthat built-version startup advisory is retained in logs outside counts.

Logs: `dev/.validation/ci-exact-tarball-20261010/storage-boundaries-red.log`,
`storage-boundaries-red-expanded.log`, `storage-boundaries-green.log`,
`storage-boundaries-affected.log`, `storage-boundaries-lint.log`. Affected contexts
`storage-boundaries|prompt-context|ckpt-files|doc-replay`: **922 passes, zero failures/countable
warnings/skips**, 13.4 s total test duration (601 document, 128 checkpoint, 85 instruction,
108 boundary assertions). Four edited/new R files: **zero lints**, exit 0; tracked runtime
whitespace check also passes. No timing/RSS profile was requested for these tiny witnesses.
These resolved-path checks address the reproduced
stable-link cases; they do not claim an atomic filesystem authorization boundary against a
concurrent link replacement. The private-mode and declared workspace-root ownership
candidates remain unpatched pending separate policy review. The sidecar and checked
document concurrent-edit repair is recorded below.
No real workspace cleanup is authorized. Root committed containment as `2e4b709`; previously
verified `8952567` source archives do not include it.

## Checked-document concurrent-edit repair

Root separately granted `R/doc-io.R`, the existing focused tests and the optional internal
`write_atomic()` expectation in `R/utils-paths.R`. Synthetic writer hooks edit the destination
while temporary bytes are prepared, including creation of a previously absent destination;
another fixture edits it between failed/successful rename attempts. Original source overwrote
the editor text: **RED 10 failures/392 passes, zero counted warnings/skips**, 24.2 s.

Checked `doc_write()` now passes the original document MD5 through to `write_atomic()`, which
checks it immediately before each rename. A mismatch is the existing `reason="conflict"`, so
the document rewrite path may re-read/re-locate; its final in-place-fallback conflict uses
the same reason. `NULL` means no document expectation; `NA_character_` requires absence.
Unconditional `check=FALSE` replacement remains intentional, and unrelated helper writers
keep their previous replacement/fallback behavior. The private temporary-file and existing
destination-mode logic is unchanged. This reduces the witnessed preparation/retry window;
it does not implement an OS-level atomic compare-and-replace.

`doc-io|utils-paths` GREEN: **511 passes, zero failures/countable warnings/skips**, 22.8 s
(402 document assertions, 109 path/writer assertions). Three-file lint: **zero lints**, exit 0;
tracked whitespace check passes. Logs are the ignored `doc-concurrent-{red,green,lint}.log`
under `dev/.validation/ci-exact-tarball-20261010/`; the known testthat built-version advisory
is preserved outside counts. No provider, installer, real document/state or credential was
used. Source review/commit and fresh archive validation belong to root.

## Same-location plain-data recovery sidecars

Root selected a closed version-1 JSON record at the existing document-hash path, with no
new import or public API. Root owns the corresponding IC-51/P15 documentation amendment.
[Path and codec](/Users/wgu/Desktop/gptr/R/doc-io.R:344) preserve the document identity,
base MD5, writer PID/creation time, session, pending kind, ordered upserts and supported
call-site anchors. Lines are explicit arrays even when empty or singleton. Nullable values
remain nullable; full-precision numbers and validated notebook numeric spelling survive
disk recovery. Stored call text is parsed only into one supported bare or gptr-qualified
`peter` call; it is never evaluated by the sidecar reader.

The root/upsert/site/anchor fields are closed and checked before recovery. Notebook
`metadata.gptr` keeps arbitrary extra keys when values are plain JSON primitives or nested
objects/arrays (maximum depth 32, maximum 10,000 visited values). Fields consumed as scalar
recording metadata retain scalar validation. Unsupported R objects, language, functions,
environments, attributed vectors or invalid numeric tokens cause a diagnostic before
replacing an existing record; no metadata is silently stripped. This is a supported
plain-data boundary, not arbitrary R object serialization.

The legacy reader is separate: POSIX only reads an existing private, owned record before
validating/normalizing it through the closed codec. Windows emits a pending-legacy notice
and performs **zero `readRDS()` calls**. Legacy bytes are never changed or deleted. Any
modern pathname, including invalid JSON or a broken symlink, is authoritative and prohibits
legacy fallback. Successful settlement with a legacy peer writes a valid empty JSON record,
so later recovery cannot replay old upserts; empty modern records without a legacy peer
retain the existing removal behavior. Presence checks use directory entries when a target
cannot be probed, because [Sys.readlink()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.readlink.html)
is not implemented on Windows; a portable fixture
models that unavailable target probe without requiring Windows link privileges. Cache
discovery lists both formats as retained sidecar files and excludes both from tmp pruning.
A listed file count is not a queued-work count.

The test-first witness uses benign legacy objects, filename-scoped reader spies and real
`doc_locate()` call sites. It covers dead/live/reused PID behavior already present, repeated
pipeline calls, computed versus literal notebook prompts, nullable anchors, disk-only sync,
inert notebook metadata, malformed fields, prior-record preservation and one-time legacy
settlement. The first runtime witness recorded **11 failures/418 passes**; preliminary
fixtures also had corrected reader-mock/return-shape harness errors and remain in the logs.
A later plain-metadata witness recorded **13 failures/508 passes/1 warning**: accepted
fractional metadata could not be rewritten by the notebook serializer, and malformed
consumed scalar metadata reached a second-upsert failure. The warning was a controlled
document conflict. Numeric/scalar validation now addresses those witnesses without dropping
extra metadata. A broken-modern-link witness reproduced one real fallback gap; its second
failure was an overly broad base reader spy, now scoped to the disposable legacy filename.

Before the final size-bound addition, `doc-io|doc-replay|storage-boundaries|secrets-e2e`
GREEN was **1,275 passes, zero failures, counted warnings or skips**, 56.2 s, exit 0. Four-file
package-context lint was **zero lints**, exit 0; owned whitespace check passed. The separate
stdout routing change required three existing output fixtures to capture actual stdout via
`utils::capture.output()`; their original exact content assertions are retained. Logs are
`doc-json-red-spy.log`, `doc-json-metadata-red.log`, `doc-json-modern-link-red.log`,
`doc-json-final-green.log` and `doc-json-final-lint.log` in ignored
`dev/.validation/ci-exact-tarball-20261010/`.

Root's resource review nominated a fixed private **16 MiB** modern-record cap. A small
mocked-boundary witness produced **RED 10 failures/537 passes, zero warnings/skips**, 26.2 s:
over-limit reads and writes were accepted, a growing-file read used only its stale stat size,
and a missing link-target probe missed a present modern entry. No 16 MiB test allocation
was needed. The reader now rejects missing/directory/over-limit records before decoding and
reads at most cap plus one byte, checking actual length, UTF-8 and NUL absence. The writer
checks existing string size before JSON allocation, then encoded byte length before creating
or replacing a durable record. Excessive code or plain metadata raises a `doc_write` error
and leaves previous bytes intact. Over-limit modern records remain exclusive; legacy bytes
are not read as fallback. Final affected validation for this addition is recorded next.

Size-bound affected GREEN: **1,291 passes, zero failures/countable warnings/skips**, 61.8 s,
exit 0, in `doc-json-size-green-loopback.log`. The first sandbox run preserved
`doc-json-size-green.log`: all codec cases passed, but two local mock-server/artifact launch
fixtures failed because loopback binding returned `operation not permitted` (1,281 passes,
two errors, zero counted warnings/skips). The authorized rerun allowed only these offline
local server fixtures; no external endpoint or model was used. The pre-fix witness is
`doc-json-size-red.log`. Final four-file package-context lint is recorded in
`doc-json-size-lint.log`: **zero lints**, exit 0. Owned runtime/test/report whitespace check
passes.

All witnesses ran on macOS with fake providers and disposable storage; Windows branches
were mocked, so actual Windows JSON recovery remains hosted proof. No credential, real
workspace state, model, installer or full package check was used. POSIX provenance, Windows
ACLs, private creation modes, concurrent symlink replacement and OS-level compare/replace
are distinct limits; this change does not claim to solve them. The known testthat
built-under-R-4.5.2 startup advisory is retained outside test counts. Parent review, commit
and fresh same-byte archive validation remain required. Earlier `8952567` archives exclude
this repair.

### Positive POSIX owner identity

Root's final reader review found that an unavailable effective UID previously counted as
ownership. A benign filename-scoped legacy-reader spy reproduced **RED 5 failures/554
passes, zero counted warnings/skips**: NA/NaN identities reached legacy deserialization,
and an empty identity raised an error rather than refusing the record. The predicate now
requires a numeric, finite, scalar, nonnegative effective UID matching the actual file UID
before either POSIX format is read. No executable RDS payload was used; legacy bytes remain
unchanged. Positive current-owner legacy recovery and Windows modern plain-JSON reads are
explicit controls alongside unknown/malformed identity rejection.

Focused current `doc-io` GREEN: **573 passes, zero failures/countable warnings/skips**,
29.7 s, exit 0. Two-file package-context lint: **zero lints**, exit 0. Logs are
`doc-json-owner-{red,green,lint}.log` in the same ignored directory. The known testthat
built-version startup advisory remains outside counts. Private JSONL/blob creation is a
separate prepared task; its tests have not yet run and its runtime has not been changed.

### Native dangling-entry presence

A final case-insensitive APFS witness created a differently cased, dangling `.JSON`
entry beside a valid private legacy record. The old presence helper checked exact
directory-entry spelling after `file.exists()` returned false, so it missed that entry and
deserialized legacy data. **RED: 3 failures/576 passes, zero counted warnings/skips,
23.6 s**, exit 1. The reader spy matched only the disposable legacy filename and delegated
all unrelated reads; the test used ordinary synthetic recovery data.

The helper now accepts a positive POSIX `Sys.readlink()` result before its existing portable
directory-entry fallback. This retains the Windows/readlink-unavailable path and avoids
guessing filesystem case rules. A present dangling modern entry remains authoritative:
reading returns no recovery record, legacy is not deserialized, queued in-memory work and
legacy bytes remain intact. The native casing witness runs on this Mac; case-sensitive
POSIX filesystems skip only that particular filesystem case. Existing ordinary dangling
link and portable directory-entry regressions remain enabled.

Final focused current `doc-io` **GREEN: 579 passes, zero failures/countable warnings/skips,
24.8 s**, exit 0, in `doc-json-case-green.log`; the pre-fix witness is
`doc-json-case-red.log`. The latest four-context affected result remains the earlier
**1,291 passes, zero failures/countable warnings/skips**; it predates only the scoped owner
and casing corrections, whose focused positive/negative controls were rerun here. This
does not claim actual Windows filesystem or ACL proof, safe handling of concurrent link
replacement, or atomic compare/replace. Private creation fixtures remain unexecuted and
private JSONL/blob creation runtime is unchanged.

Final four-file package-context lint (`doc-json-case-lint.log`) and owned-file whitespace
check both pass with **zero lints**, exit 0. The known testthat build-version advisory is
retained outside test counts. The sandbox also reports `nice: setpriority: Operation not
permitted`; no claim of successfully changed scheduling priority or valid performance
profiling is made. Only one thread-capped offline R process ran at a time, sequentially,
and the R lease was released after lint. No real workspace state or credentials were read.
