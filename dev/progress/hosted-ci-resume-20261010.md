# Hosted CI resume — 2026-10-10

## Scope and identity

Initially read-only remote investigation; no local build, test, install, live provider call
or Git mutation in this resumed lane. Root subsequently authorized an ignored
workflow draft, then the new `.github/workflows/Exact-tarball.yaml` after independent review.
Those two tracked files are this lane's entire edit scope. A granted short R slot was used
only to parse the two embedded R blocks; no expression, dependency setup or check was run.
Root later authorized cancellation of only the redundant f3e7c80 push check and download of
the exact-source artifact into ignored local validation storage; details are recorded below.
Credentials and raw workflow environment/command lines are not copied into this report.

At **23:38:27 UTC**, remote `main` was exactly
`68017d0bebc7b44adb564029fbc423e5dda65e9a`. The open PR inventory was empty.
Sources: [main commit](https://github.com/Broccolito/gptr/commit/68017d0bebc7b44adb564029fbc423e5dda65e9a),
[open PR inventory](https://github.com/Broccolito/gptr/pulls),
[exact-head workflow](https://github.com/Broccolito/gptr/actions/runs/38094110006).
The inventory and run statuses below are timestamped snapshots, not promises about later state.

## Exact-head run 38094110006

At **23:59 UTC**, the run was final: **3 successful gates and 10 failed jobs**.
Both Windows versions had completed; their completion fixture correction is verified below.

| Job | Verified state | Evidence |
| --- | --- | --- |
| copy-safety, release | completed / success | job 114336455891 |
| copy-safety, devel | completed / success | job 114336455958 |
| token benchmark | completed / success | job 114336456005 |
| Ubuntu release | completed / failure | [job 114336455946](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455946) |
| Ubuntu release, no Suggests | completed / failure | [job 114336455746](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455746) |
| Ubuntu release, LC_ALL=C | completed / failure | [job 114336455944](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455944) |
| Ubuntu devel | completed / failure | [job 114336455949](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455949) |
| Ubuntu oldrel-1 | completed / failure | [job 114336456016](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336456016) |
| Ubuntu oldrel-4 | completed / failure | [job 114336455979](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455979) |
| macOS release | completed / failure | [job 114336455955](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455955) |
| Windows release | completed / failure | [job 114336455862](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455862) |
| Windows oldrel-4 | completed / failure | [job 114336456021](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336456021) |
| connections left open | completed / failure | [job 114336455971](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455971) |

### New failure: native-MCP recording crosses two architecture boundaries

All nine R checks and the connection-gate suite fail only
`test-arch-layers.R:32`, which enforces IC-33:

```text
mcp_serve_r (mcp-server.R) -> entry_custom (session-object.R)
mcp_serve_r (mcp-server.R) -> r_doc_outputs (tool-r.R)
```

| Check | Pass | Fail | Counted warnings | Skips | Check status |
| --- | ---: | ---: | ---: | ---: | --- |
| Ubuntu release | 24,419 | 1 | 0 | 36 | 1 ERROR |
| Ubuntu no Suggests | 24,415 | 1 | 0 | 37 | 1 ERROR |
| Ubuntu LC_ALL=C | 24,389 | 1 | 0 | 42 | 1 ERROR |
| Ubuntu devel | 24,419 | 1 | 0 | 36 | 1 ERROR |
| Ubuntu oldrel-4 | 24,419 | 1 | 0 | 36 | 1 ERROR, 1 NOTE |
| macOS release | 24,450 | 1 | 0 | 31 | 1 ERROR, 1 NOTE |
| Ubuntu oldrel-1 | 24,419 | 1 | 0 | 36 | 1 ERROR |
| Windows release | 24,158 | 1 | 0 | 91 | 1 ERROR |
| Windows oldrel-4 | 24,158 | 1 | 0 | 91 | 1 ERROR, 1 NOTE |
| connections suite | 24,503 | 1 | 0 | 21 | suite gate failed |

The call sites are in
[mcp-server.R](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/R/mcp-server.R#L228).
The test and contract sources are
[test-arch-layers.R](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/tests/testthat/test-arch-layers.R#L27),
[helper-arch.R](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/tests/testthat/helper-arch.R#L137),
and [IC-33](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/dev/spec/04-interface-contract.md#L4221).

Static source review confirms both direct dependencies are outside the present kernel SDK
and the MCP area's declared contract edges. `entry_custom()` is a kernel entry constructor;
`r_doc_outputs()` is the R-tool area's output formatter. This is a real architecture-gate
regression introduced by the recording implementation. The logs do not establish a numerical
evaluation, permission, redaction, recording, replay, or connection-leak failure.

**Fix nomination:** architecture owner should retain the gate and negative controls, remove
the cross-area coupling or explicitly justify a narrowly documented boundary, then include
`arch-layers` with the affected MCP/recording checks before the next immutable artifact.
Do not disable the test, broaden all MCP dependencies, or call pending Windows checks passed.
Root assigned this fix to the architecture lane; this lane has not changed runtime or tests.
Independent review of the prepared three-file diff found no blocker: it moves the unchanged
`r_doc_outputs()` formatter into existing allowed service file `eval-format.R` and builds the
identical custom-entry list directly before the unchanged `session_append()` ingress.
The architecture test and allowlist remain unsuppressed. Local validation belongs to that lane;
these exact-head hosted failures remain failures until a replacement head is checked.

The connection gate's negative controls passed six assertions. Its full suite took 1,813.4s;
the only final gate diagnostic is `the test suite had 1 failed test(s)`. Source compares the
connection tables even after a failed suite and adds a distinct diagnostic for any difference.
That diagnostic is absent, so the failed job does not show a leaked R connection. It emits two
unhandled Chromote shutdown promise messages outside counted test warnings.
Sources: [connection job](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455971),
[gate implementation](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/dev/ci/check-connections.R).

### Temp ownership and Windows correction

All nine exact-head R checks report both `checking for non-standard things in the
check directory ... OK` and `checking for detritus in the temp directory ... OK`.

macOS's separate NOTE lists 16 Apple-service directories. The log does not establish package
ownership of those directories; none is a Chrome URL-fetcher or Rscript file. Its emitted
test output also contains five unhandled Chromote `Browser.close` promise-error messages,
then repeats those same five when the failed test log is displayed. These are outside the
counted test warnings; retain the qualification rather than calling the check silent.
Source: [macOS job](https://github.com/Broccolito/gptr/actions/runs/38094110006/job/114336455955).

Normal source-retention builds explicitly use `R_KEEP_PKG_SOURCE=yes`: macOS reports installed
size **INFO 9.6Mb / R8.3Mb**, Ubuntu devel and oldrel-1 **INFO 8.8Mb / R7.4Mb**, and
Ubuntu oldrel-4 **NOTE 8.8Mb / R7.4Mb** (units as printed by R). The oldrel size is its sole
NOTE; macOS's size is INFO and its NOTE is
the separate Apple-directory check. These are exact-head hosted installs, not the next final
built tarball or the maintainer's direct-source installed package.

The corrected Windows fixture is present in this head: seven native Unix positive cases skip
actual Windows before `.Platform` mocking or `rl_word_breaks` writes. The unsupported-mode
case retains 13 variants and compares the actual prior option without creating it. Root's
local Unix result was 71 passing assertions; it is separate from hosted Windows proof.
Hosted Windows release used R 4.6.1 and oldrel-4 used R 4.2.3. Both fail solely the two IC-33
edges above, with no `rl_word_breaks` deletion failure. Their seven native positive cases
appear in the Windows
skip list; the unsupported-mode guard is neither failed nor skipped. The test-owned directory
normalization case and Windows forced-child-kill witness are also neither failed nor skipped;
their four path assertions and seven kill/cleanup assertions therefore passed by inference
from the complete failure and skip reports, rather than separately logged per-case counts.
Release reports installed size INFO 8.7Mb / R7.4Mb and oldrel-4 reports its sole NOTE for
the same 8.7Mb / R7.4Mb size, with source retention. Both temp cleanup checks are OK.
Two HTTP-only browser cases skip after Chrome's debugging port fails
to open within ten seconds; this is a retained coverage qualification.
The checker reports `Duration: 35m 21.5s` for release and `Duration: 40m 55.6s` for oldrel-4.
Source: [completion fixture](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/tests/testthat/test-console-completion.R).

## Official R / CRAN baseline, checked during this resume

The current public R release is **4.6.1 (2026-06-24)**. R 4.5.3 is the previous-series
wrap-up release; R 4.6.2 is scheduled for 2026-10-29, with prereleases starting 2026-10-19.
Sources: [R Project news](https://www.r-project.org/),
[official source-release index](https://cran.r-project.org/src/base/R-4/).

CRAN asks for a source tarball built with current release/patched R and an `--as-cran` check
of that uploaded tarball with current R-devel, or an explained release/patched alternative.
Warnings and significant notes require elimination or explanation. Policy calls for minimum
necessary size, generally at most 5 MB each of data/documentation and, if possible, a source
tarball below 10 MB; it does **not** state a blanket 5 MB installed-package limit. Checks
should minimize CPU time and use no more than two simultaneous threads/cores.
Source: [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html).

The R manual describes `_R_CHECK_TIMINGS_=0` and `--timings` as ways to measure test,
example, vignette and install cost. Hosted source-retention sizes, a direct-source local
install, and the next built tarball must remain separate observations.
Source: [Writing R Extensions — check timing](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Check-timing).

No final rebuilt tarball or CRAN submission is verified by this remote investigation.
The current workflow deliberately passes `--no-manual` and disables CRAN incoming checks;
those omissions remain distinct from a submission check of the actual final source tarball.
Source: [workflow](https://github.com/Broccolito/gptr/blob/68017d0bebc7b44adb564029fbc423e5dda65e9a/.github/workflows/R-CMD-check.yaml).

## Replacement source and exact-tarball mechanism

At **23:50:00 UTC**, replacement source `3d92b05782ea17ac708cfa3494794d146920c4a1`
had [run 38096135973](https://github.com/Broccolito/gptr/actions/runs/38096135973) pending
behind the still-running 68017d0 Windows jobs. No replacement check is counted as passed.
At **23:59 UTC**, that replacement run had started: all 13 jobs were in progress and no
completed outcomes were available. The superseded 68017d0 run is retained with its final
failures and corrected Windows witnesses above.
At **00:04 UTC on 2026-10-11**, token benchmark was completed/success and the other 12
jobs remained in progress. The open PR inventory was empty again.
The root coordinator reported the normal local archive as 2,216,695 bytes, containing
14 rendered Rmd guides and 14 HTML guides, with SHA256
`5ced56de6454cba771af7fff4a6459a22a5fb2258b351ee92ce678e0a9899d05`.
That local build/check is coordinator evidence, not a build repeated by this lane.

### Actions-only draft for Q05's same-byte proof

Root explicitly rejected a release-based transfer: **no draft release, release asset or tag
is authorized**. The active proposal instead creates one archive inside Actions and adopts
those same bytes as a replacement local candidate. It does not claim equality with the
preexisting local archive. At that proposal checkpoint, no workflow or dispatch had been
created or changed remotely; the later authorized dispatches are recorded below.

Root authorized a concrete draft, then implementation only after independent review.
The retained draft is in ignored
[Exact-tarball.yaml](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/Exact-tarball.yaml).
Root then approved the implementation in
[.github/workflows/Exact-tarball.yaml](/Users/wgu/Desktop/gptr/.github/workflows/Exact-tarball.yaml).
The existing automatic push/PR gates remain unchanged; root owns commit, push and dispatch.

The draft adds one dispatch-only producer and one consumer matrix:
Architecture independently reviewed both the draft and final tracked workflow and found no
concrete blocker; no Actions or R job was launched during those reviews. It also enables timing and retained
vignette output, declares the check core limit and caps testthat workers at two.

1. A required full lowercase source SHA is validated before checkout, then compared against
   the actual checkout commit. A fresh Ubuntu/current-release runner uses the existing R/Pandoc
   setup actions plus TinyTeX and performs **one normal `R CMD build`**, outside the package
   checkout. No `--no-manual`, no `--no-build-vignettes`, and no source-resave override is used.
   The package's existing `.Rbuildignore` excludes local data, credentials, caches and `dev/`.
   The corrected producer assertion rejects package-root `dev/` and `docs/`, rejects
   `.secrets`, `.git` or `node_modules` components anywhere, and requires `DESCRIPTION`,
   `NAMESPACE` and `LICENSE`. Legitimate `tests/testthat/fixtures/docs/` remains allowed.
2. The producer requires one normal tarball with exactly 14 `inst/doc/*.Rmd` and 14
   `inst/doc/*.html` files, and records the source SHA, producer R version, basename, byte count,
   and SHA256. `upload-artifact@v4` stores that archive without recompression of its bytes.
3. Five consumers cover Windows release/devel, macOS release and Ubuntu release/devel, with
   fail-fast disabled, `max-parallel: 2`, `Ncpus: 2`, and BLAS/OpenMP threads capped at one.
   The producer has a 90-minute timeout; each consumer has a 180-minute timeout.
4. `download-artifact@v5` obtains the shared artifact. Each consumer validates the actual
   tarball's bytes and SHA256 against producer job outputs, as well as its manifest's source
   identity, **before** dependency setup or checks. The Actions artifact-container digest is
   not substituted for the tarball digest.
5. Only the archive's `DESCRIPTION` is copied to `metadata/gptr` for dependency discovery.
   `setup-r-dependencies` runs there with explicit `packages: deps::., any::sessioninfo`;
   the primary action creates a lockfile for dependency references and installs that lockfile.
   It does not build or install a checkout copy of gptr. The checker receives the original
   archive path directly and does not invoke `R CMD build` on a consumer.
6. `rcmdcheck(path = archive, args = "--as-cran", check_dir = "check", error_on = "never")`
   retains manual and incoming checks; a following assertion requires one actual `Status:`
   line and zero parsed errors/warnings. All notes remain counted and logged for review.
   `NOT_CRAN=true` preserves the existing full offline test behavior; live providers are
   explicitly disabled. This remains an Actions environment, not an assertion that it
   reproduces CRAN's every external environment setting.
7. Artifacts preserve producer diagnostics and all available consumer check/test/manual logs
   and provenance even after failures. Root then downloads the producer's `.tar.gz`, verifies
   its recorded digest and bytes locally, checks required docs/size/oracles, and performs a
   local check of **that replacement archive**. Until that happens, same-byte local proof is
   pending. There is no new account secret or Actions account setting; contents permission is
   read-only.

Static validation passed with the existing ignored notebook Python environment: YAML
`BaseLoader` retained the `on` key, five Bash blocks passed `bash -n`, two embedded Python
blocks passed AST parsing, and two extracted R blocks passed `Rscript --vanilla` parse-only
validation. `actionlint` is unavailable; no parser dependency was installed. No workflow,
build, dependency setup, model call or package check was executed during these validations.
Logs:
[static validation](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/workflow-static-validation.log),
[R parse](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/workflow-r-parse.log).

The coordinator separately reports the local R 4.5 check of the original 3d92b05 archive as
`Status: OK`, 22,603 passed assertions, zero failures/counted warnings, 386 skips, installed
size INFO 6.4Mb and 14 guides. Those are coordinator observations, not tests repeated here,
and do not certify the proposed Actions-produced replacement candidate.

Primary sources: [Actions artifact sharing and validation](https://docs.github.com/en/actions/tutorials/store-and-share-data),
[rcmdcheck tarball interface](https://rcmdcheck.r-lib.org/reference/rcmdcheck.html),
[dependency action inputs and implementation](https://github.com/r-lib/actions/blob/v2/setup-r-dependencies/action.yaml),
[R setup inputs](https://github.com/r-lib/actions/blob/v2/setup-r/action.yml),
[TinyTeX setup and manual-package requirements](https://github.com/r-lib/actions/blob/v2/setup-tinytex/README.md),
[R check timing/vignette-output/core settings](https://svn.r-project.org/R/trunk/src/library/tools/R/check.R),
[testthat worker-count precedence](https://github.com/r-lib/testthat/blob/main/R/parallel.R).

### Authorized dispatch and redundant-run cancellation

Root reviewed, committed and pushed the workflow/report as
`f3e7c80ed9ef1521f6db1afe9ae13aeb64f8b19d`, then dispatched
[Exact source tarball, run 38097167397](https://github.com/Broccolito/gptr/actions/runs/38097167397)
with `source_sha=3d92b05782ea17ac708cfa3494794d146920c4a1`.
The workflow's event SHA is f3e7c80; the producer's requested package-source SHA is 3d92b05.
At **00:05 UTC**, producer job 114345345087 was in progress and no
`exact-source-tarball` artifact was available yet. No produced-byte check is claimed.

Read-only `git diff --name-only 3d92b05 f3e7c80` confirmed exactly the new workflow and this
report changed; neither is included by the package's existing build rules. Root explicitly
authorized cancelling only the redundant f3e7c80 push run after that identity check.
Cancellation was requested for
[R-CMD-check push run 38097114653](https://github.com/Broccolito/gptr/actions/runs/38097114653),
and the API verified **completed/cancelled at 00:05:43 UTC**. The active 3d92b05 source checks
and exact-tarball dispatch were preserved. No other run was cancelled or modified.

When a successful replacement producer uploads the normal artifact, this lane will download
only `exact-source-tarball` to ignored `dev/.validation/ci-exact-tarball-20261010/remote-<runid>`,
verify the actual tarball
SHA256/bytes, source SHA and 14+14 rendered guides, then give root its path and fingerprint.
Only root will install or check those bytes locally.

### First producer failed a path assertion; package build succeeded

At **00:08 UTC**, the producer had failed and the consumer matrix was skipped. Its normal
`R CMD build` under R 4.6.1 had completed successfully, then the archive exclusion assertion
rejected the legitimate directory `gptr/tests/testthat/fixtures/docs`. The initial rule
incorrectly treated every `docs` component as the repository's excluded top-level website.
This lane introduced that overly broad workflow assertion and corrected it after root review.
This is not a package/check regression. The guide-count check had not been reached, no
manifest was generated, and **no normal-source artifact was uploaded or adopted locally**.

The failed run and its producer diagnostics artifact (ID 11686856078) are preserved.
The normal-build stdout is separately retained without environment/command lines in ignored
[producer build output](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/producer-38097167397-build-output.log).
Source: [producer job](https://github.com/Broccolito/gptr/actions/runs/38097167397/job/114345345087).

A tiny Python witness executes only the workflow's actual archive-path assertion loop against
19 synthetic names. Before the fix it passed 17 and failed the two legitimate fixture paths;
after restricting `dev` and `docs` to the package root it passed all 19. Negative cases retain
root dev/docs, private/git/node_modules paths at root and nested levels, traversal and wrong
package root. YAML BaseLoader, five Bash syntax checks and two Python AST parses passed again;
the two R blocks are byte-for-byte unchanged from the prior passed parse-only check. No R
or package check was executed for this path correction.
Logs: [red witness](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/archive-path-red.log),
[green witness](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/archive-path-green.log),
[static validation](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/workflow-pathfix-static.log).
Root owns commit/push and redispatch with the same requested 3d92b05 package-source SHA.

### Corrected producer uploaded verified replacement bytes

Root committed the narrow assertion correction as
`e3acf6d4b588a4d046b7bfff08d8a079eb486145` and dispatched
[run 38097885912](https://github.com/Broccolito/gptr/actions/runs/38097885912)
for the same full source SHA `3d92b05782ea17ac708cfa3494794d146920c4a1`.
Producer job 114347505407 completed successfully and uploaded `exact-source-tarball`
(artifact ID 11686381774) at **00:20:01 UTC on 2026-10-11**.

This lane downloaded only that named artifact and verified the actual archive against the
producer's printed manifest, not just against a locally supplied manifest:

- Archive: [gptr_1.0.0.tar.gz](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/remote-38097885912/gptr_1.0.0.tar.gz).
- Package-source SHA: `3d92b05782ea17ac708cfa3494794d146920c4a1`.
- Actual bytes: **2,222,427**.
- Actual SHA256: `b549b0952d5bab453aac189e00694500546704bf5e35cd9ab47e46c5ec905003`.
- Producer R: **R 4.6.1 (2026-06-24)**.
- Actual archive contents: **14 rendered Rmd guides and 14 HTML guides**, with required
  DESCRIPTION/NAMESPACE/LICENSE and the corrected package-root/private path checks passing.

The archive was inspected without extracting or executing package code. No install or
local package check was run by this lane. The manifest and
[local verification](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/remote-38097885912/local-verification.json)
are retained beside the immutable downloaded archive. These are replacement bytes; they
differ from the earlier local R 4.5 archive's digest and are not claimed to equal it.

At the **00:21 UTC** snapshot, both Windows consumers had completed byte verification and
were setting up dependencies; macOS and both Ubuntu consumers were queued under the
two-job cap. No consumer package-check result is passed yet. The original 3d92b05 push run
had four completed successes (copy-safety release/devel, token benchmark and Linux without
Suggests), nine jobs still running, and no completed failure.

The redundant e3acf6d push run 38097569106 was already **completed/cancelled** when this
lane read it. This lane made no cancellation call for it. Read-only source comparison
confirmed that 3d92b05..e3acf6d changed only the workflow and this report; the package R/test
sources were identical. New notice-fix source `8952567` and its pending push checks remain
separate from this 3d92b05 artifact proof and will need their own exact-archive checkpoint.

### Latest notice-fix producer bytes and completed 3d92b05 checks

Root dispatched [run 38098141085](https://github.com/Broccolito/gptr/actions/runs/38098141085)
for `89525673ae4d9e8c76da0526a134e59de03615d1`. Producer job 114348259468 succeeded and
uploaded artifact 11686673015 at **00:24:23 UTC**. This lane downloaded only
`exact-source-tarball` and verified its archive against the producer's printed manifest:

- [Archive path](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/remote-38098141085/gptr_1.0.0.tar.gz),
  **2,223,937 actual bytes**, SHA256
  `9907684a205ee21b48f667524151cec97a39c07dc1c78082a7798509ff4efe41`.
- Full source SHA matched; producer **R 4.6.1**; actual **14 Rmd + 14 HTML** guides;
  required package files and corrected path exclusions passed.
- [Local verification](/Users/wgu/Desktop/gptr/dev/.validation/ci-exact-tarball-20261010/remote-38098141085/local-verification.json)
  and original manifest retained. No package extraction, execution, install or local check.

At **00:26 UTC**, Windows release/devel consumers were setting up, with the other three
queued. These consumer checks and root's adoption/check of the downloaded 8952567 bytes
remain pending; the prior local 8952567 build has separate R/digest provenance.

New completed source-check outcomes from the original 3d92b05 push run:

| Job | Actual completed check evidence |
|---|---|
| [macOS release](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344316022) | R 4.6.1, PASS 24,476 / FAIL 0 / WARN 0 / SKIP 31; temp detritus OK. `Status: 1 NOTE` solely five Apple-service directories outside the check. Size INFO 9.6Mb (R 8.3Mb), `R_KEEP_PKG_SOURCE=yes`. |
| [Linux oldrel-4](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344316033) | R 4.2.3, PASS 24,445 / FAIL 0 / WARN 0 / SKIP 36; both directory checks OK. `Status: 1 NOTE` solely installed size 8.8Mb (R 7.4Mb), `R_KEEP_PKG_SOURCE=yes`. |
| [Linux without Suggests](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344315991) | R 4.6.1, PASS 24,441 / FAIL 0 / WARN 0 / SKIP 37; `Status: OK`; size INFO 6.0Mb (R 4.6Mb). |

The five macOS directory names are `com.apple.intelligenceflow.intelligencecontextd`,
`com.apple.proactiveeventtrackerd`, `com.apple.SafariLaunchAgent`,
`com.apple.secureelementservice`, and `contentlinkingd`. No Chrome/Rscript detritus is
reported by these completed checks. At **00:24 UTC**, the run had six successful jobs and
seven still running, including both Windows versions. The previously witnessed IC-33
failure was absent on the three completed package checks above; pending jobs are not passed.
### Additional `3d92b05` results at 00:33 UTC (2026-10-11)

The normal push matrix now has ten successful jobs, one failed job and two Windows jobs
still checking. These are source-checkout results, separate from the same-byte archive jobs.

| Completed job | Actual R / test summary | Check result |
|---|---|---|
| Linux release `114344315974` | 4.6.1; PASS 24445 / FAIL 0 / WARN 0 / SKIP 36 | Status OK; installed-size INFO 8.8 Mb / R 7.4 Mb |
| Linux oldrel-1 `114344316071` | 4.5.3; PASS 24445 / FAIL 0 / WARN 0 / SKIP 36 | Status OK; installed-size INFO 8.8 Mb / R 7.4 Mb |
| Linux devel `114344316149` | 2026-10-09 r90655; PASS 24445 / FAIL 0 / WARN 0 / SKIP 36 | Status OK; installed-size INFO 8.8 Mb / R 7.4 Mb |
| Connections `114344316066` | 4.6.1; PASS 24529 / FAIL 0 / WARN 0 / SKIP 21 | Successful connection-check workflow job; not an R CMD check Status claim |
| Linux release C locale `114344315988` | 4.6.1; PASS 24413 / FAIL 2 / WARN 0 / SKIP 42 | Status 1 ERROR, both failures in `test-console-spinner-width.R:60/61` |

All four newly completed package-check jobs report both temporary-detritus and check-directory
checks OK. The C-locale failure is concrete: a forced Unicode styled spinner expected 19
display columns but the captured native display has 57; the Unicode-label assertion also
fails. `console_spinner()` sizes before `cat()` expands unrepresentable text to `<U+...>`.
Nomination: use the existing listing display-copy rule (native conversion before sizing) and
retain a locale-aware content assertion; do not skip the whole test or weaken width bounds.
Root and the console owner were notified. [Run and job evidence](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344315988).

Both corrected exact-archive runs retain successful verified producers; each has actual
Windows release/devel archive checks running and three later OS checks queued at this
snapshot. Neither consumer matrix is counted passed. Downloaded immutable archive digests
remain those recorded above; the uncommitted storage repair is outside both source commits.

### Completed `3d92b05` Windows oldrel-4 at 00:40 UTC

[Job 114344316219](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344316219)
completed successfully on actual R 4.2.3 UCRT. Tests: **PASS 24184 / FAIL 0 / WARN 0 / SKIP 91**.
The check reports **Status: 1 NOTE**, solely installed size 8.7 Mb (R 7.4 Mb) in this
`R_KEEP_PKG_SOURCE=yes` environment. Both non-standard check-directory and temporary-detritus
checks are **OK**; no Rscript or Chrome detritus NOTE remains in this completed job. Native
Unix completion positives are intentionally skipped on Windows; the unsupported-mode guard
is still exercised. Windows release and all exact-archive consumers remain pending at this
snapshot, so this source-checkout result is not same-byte archive proof or full-matrix closure.

### Completed Windows and exact-archive update at 00:56 UTC

Normal source-checkout run [38096135973](https://github.com/Broccolito/gptr/actions/runs/38096135973)
is now final: 12 jobs succeeded and the already diagnosed C-locale spinner job failed. Windows
release [114344316125](https://github.com/Broccolito/gptr/actions/runs/38096135973/job/114344316125)
completed on actual R 4.6.1 UCRT with **PASS 24184 / FAIL 0 / WARN 0 / SKIP 91**, **Status: OK**.
Installed size is informational in its retained-source environment; both check-directory and
temporary-detritus checks are OK. This closes the corrected Windows fixture observation for
that source checkpoint, without rewriting the historical Linux C failure.

Exact `3d92b05` producer archive: Windows release
[114348035685](https://github.com/Broccolito/gptr/actions/runs/38097885912/job/114348035685)
completed successfully on R 4.6.1 UCRT, **Status: OK**, manual/incoming checks retained, both
detritus checks OK. Its installed size is **INFO 5.9 Mb / R 4.6 Mb**. The original downloaded
archive digest above binds this result; this is same-byte archive evidence, unlike a checkout
rebuild. Exact Windows devel
[114348035695](https://github.com/Broccolito/gptr/actions/runs/38097885912/job/114348035695)
completed with **Status: 1 ERROR**, solely reactor timing test 648: **PASS 24177 / FAIL 1 /
WARN 0 / SKIP 92**, actual R-devel 2026-10-09 r90655 UCRT. The diagnostic reports wall 2.498 s,
head spread 0.234 s, ends at 1.149/1.150/1.151/2.295/2.516/2.516 s; mock lateness
0.134/0.031/0.036/0.024/0.018/0.024 s and delivery delays
0.016/0.013/0.008/0.016/0.015/0.008 s. Both detritus checks, manual and vignette rebuilding
passed; installed size **INFO 5.9 Mb / R 4.6 Mb**. The timing gate remains unsuppressed; root
and the architecture lane received the full diagnostic. No local retry or cause claim was made.

Exact `3d92b05` Mac/Linux checks are now active or queued; exact `8952567` Windows checks
remain active and its Mac/Linux checks queued. These incomplete matrices are not passed.
Both producer artifacts remain intact; no GitHub mutation/cancellation was made in this update.
All these archives precede the current storage, locale and compaction edits.

### Exact `8952567` Windows results at 01:04 UTC (2026-10-11)

Both Windows consumers of the already downloaded, digest-verified `8952567` producer
archive completed successfully. Release
[114348782998](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348782998)
ran actual R 4.6.1 UCRT; devel
[114348783032](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348783032)
ran actual R-devel 2026-10-09 r90655 UCRT. Each reports **Status: OK** with manual PDF/HTML,
incoming and vignette checks retained, and both temporary-detritus/check-directory checks
**OK**. Both installed-size results are **INFO 5.9 Mb / R 4.6 Mb**. A passing assertion count
is not printed in these successful consumer job logs; the normal source-checkout counts
above are not substituted for archive test counts.

The consumed archive remains 2,223,937 bytes, SHA-256
`9907684a205ee21b48f667524151cec97a39c07dc1c78082a7798509ff4efe41`, built by the verified
R 4.6.1 producer. These are same-byte Windows results in the workflow's `NOT_CRAN=true`
coverage environment, not local-install claims. Mac/Linux were active or queued at this
snapshot. The historical exact `3d92b05` Windows devel timing failure remains failed;
the later `8952567` success does not erase it or establish a cause. No CI or Git mutation
was made, and no pending matrix member is counted passed.

### Exact `3d92b05` Mac/Linux release results at 01:20 UTC

Mac release [114348035668](https://github.com/Broccolito/gptr/actions/runs/38097885912/job/114348035668)
and Linux release [114348035696](https://github.com/Broccolito/gptr/actions/runs/38097885912/job/114348035696)
both completed successfully on actual R 4.6.1. Mac reports macOS Tahoe 26.6.2; Linux reports
Ubuntu 24.04.5 LTS. Each check has **zero errors/warnings and Status: 1 NOTE**, solely HTML
manual validation being skipped because of the runner's Tidy availability. Mac says its
`tidy` is insufficiently recent; Linux says no `tidy` command is found. This does not prove
HTML validation passed and is not a package HTML defect claim. Manual PDF and vignette
checks are retained. Both non-standard check-directory and temporary-detritus checks are
**OK**. Installed-size facts are **INFO 6.4 Mb / R 5.1 Mb** on Mac and **INFO 6.0 Mb / R 4.6 Mb**
on Linux, bound to the previously recorded `3d92b05` producer digest.

Nomination: establish a recent HTML Tidy in the hosted exact-consumer setup, preserve the
actual validation and NOTE reporting, then validate a later archive. The client source
audit lane received the exact messages and job IDs for a narrow primary-source setup review.
No workflow edit or rerun was made here. Exact `3d92b05` Linux devel was active; the earlier
Windows devel timing failure remains the run's observed failure. Exact `8952567` Mac/Linux
were still active/queued. These archives continue to precede current storage/console changes.

At **01:28 UTC**, the read-only GitHub API inventory reports **zero open PRs** and remote main
at `e28890208f81051ba2c3885860234e1cee80abef` (the reviewed compaction checkpoint). No remote
mutation or local Git synchronization was performed by this lane. The working storage and
console changes awaiting root's review are not claimed to be in that remote commit.

### Exact `8952567` consumer snapshot and Tidy setup repair at 01:33 UTC

Read-only GitHub job API plus completed-job logs establish this five-consumer snapshot
for [run 38098141085](https://github.com/Broccolito/gptr/actions/runs/38098141085):

| Consumer | Job | Observed result |
|---|---|---|
| Windows release | [114348782998](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348782998) | Completed successfully; previously recorded **Status: OK** |
| Windows devel | [114348783032](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348783032) | Completed successfully; previously recorded **Status: OK** |
| Mac release | [114348782941](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348782941) | R 4.6.1; **Status: 1 NOTE / errors 0 / warnings 0**, solely skipped HTML validation because Tidy was rejected as insufficiently recent |
| Linux release | [114348782961](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348782961) | R 4.6.1; **Status: 1 NOTE / errors 0 / warnings 0**, solely skipped HTML validation because Tidy was absent |
| Linux devel | [114348782987](https://github.com/Broccolito/gptr/actions/runs/38098141085/job/114348782987) | **In progress**; no final check result |

The archive remains the previously verified 2,223,937-byte producer artifact with SHA-256
`9907684a205ee21b48f667524151cec97a39c07dc1c78082a7798509ff4efe41`.
Skipped HTML validation is not a passed HTML check. The fifth consumer and entire matrix
remain incomplete; these results precede the current storage/console repairs.

The uncommitted **Tidy-only** change in `.github/workflows/Exact-tarball.yaml` installs
Ubuntu's `tidy` and macOS's `tidy-html5`, adds the Brew binary directory to `GITHUB_PATH`,
then requires `tools:::.find_tidy_cmd()` to accept the command before `rcmdcheck`.
It records R version, command, resolved path, version and failure reason in
`evidence/html-tidy.txt`. R's current implementation requires Tidy at least 5.0.0 plus
recognizable version output; the actual runner's acceptance is the gate.
[R implementation](https://svn.r-project.org/R/trunk/src/library/tools/R/utils.R)
[R macOS setup guidance](https://cran.r-project.org/doc/manuals/r-release/R-admin.html#Other-libraries)

`GITHUB_PATH` prepends the directory for the next step, so the separate preflight sees the
modern Mac executable. [GitHub PATH behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-system-path)
No HTML/manual/incoming checks, error/warning gates, archive digest logic, matrix entries,
worker limits or producer steps were changed. Static validation passed with installed
Ruby Psych 3.1.0, both added shell scripts passed `bash -n`, and removing the three added
steps reproduces the entire original workflow byte for byte. Available Python/Node lacked
YAML modules; no dependency was installed. Workflow SHA-256:
`489a97f4e94865367af9991cfa94fbdc221c77633fa02abd73cb9c56b9bec41e`.
No R job, local install, Git mutation or hosted rerun was performed. A future dispatched
archive must demonstrate actual HTML validation; this edit cannot change historical NOTES.

### Proposed six-stream timing fixture follow-up (preparation only)

The original `3d92b05` archive's `test-http-reactor.R:648` tests INFRA-01 concurrency,
not provider timeout. Both mock children were ready before requests started. Its 2.498 s
measurement exceeds 2.475 s by 23 ms; mock final-write lateness is removed, but the 0.234 s
cross-stream response-head spread remains. All streams completed, and reported end-delivery
latencies were 8-16 ms. The logs do not establish whether the head spread arose in the client,
socket handling or mock scheduling; no timeout/liveness defect or fix is established.

Do not relax the bound or independently normalize every head: either can hide serialized
requests. A proposed companion test would use a controlled clock to verify that six eligible
transfers are admitted before any completes. The bounded HTTP fixture could use one mock
with a six-request barrier, exact request identities, a common scheduled release and stream
lengths 4/4/4/9/9/9 at 0.25 s. All requests must arrive before release; preserve the 0.35 s
delivery/gap and 2.475 s completion bounds after release, with the existing 30 s outer bound.
A serialized client cannot pass the barrier. Include failing oracle cases for serialized
admission, delayed/batched delivery and mismatched identities, and record setup separately.
Changing this measurement requires an explicit D-016/D-063/spec clarification. No test,
fixture, source or plan was changed here; the historical Windows-devel failure remains failed.

### Exact `3d92b05` matrix completed (01:32 UTC)

The remaining Linux-devel consumer is now complete. Job
[114348035701](https://github.com/Broccolito/gptr/actions/runs/38097885912/job/114348035701)
used actual R-devel `2026-10-09 r90655` on Ubuntu 24.04.5 LTS and reports **Status: 1 NOTE**,
errors 0, warnings 0, notes 1. Its sole NOTE is `Skipping checking HTML validation: no command
'tidy' found.` Tests (11m CPU/15m elapsed), rebuilt vignettes, PDF manual and temp detritus
checks are OK. Installed-size output is informational: 6.0 Mb total, R 4.6 Mb. The job log
does not print a passing-assertion count; no checkout count is substituted.

This closes the older exact-source matrix with **four successful consumers and one failed
Windows-devel reactor timing consumer**. Mac and both Linux jobs retain their separately
documented Tidy qualification; Windows-release remains Status OK. No historical NOTE or
failed test is converted to a pass by the pending workflow setup repair. The source and
archive digest remain the verified `3d92b05` values above; these bytes predate the current
storage, compaction and console changes. The latest `8952567` matrix still had Linux-devel
in progress at this snapshot, with its other four consumers complete as previously recorded.

### Exact `03963e0` matrix snapshot (02:15 UTC)

Read-only inspection of [38102472275](https://github.com/Broccolito/gptr/actions/runs/38102472275)
confirms the producer succeeded and both Windows release/devel consumers verified the original
archive and supported HTML Tidy. Both are still checking; Mac release and both Linux consumers
remain queued. No final consumer result or matrix pass is available. This nominated archive
predates6501a64/ad4e6a9; its eventual result must not certify those newer changes. No hosted
rerun, local R job or package installation was performed for this status read.
