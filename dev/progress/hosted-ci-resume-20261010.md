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
preexisting local archive. No workflow or dispatch has been created or changed remotely.

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
