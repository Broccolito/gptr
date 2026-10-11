# Immutable artifact and CRAN diagnostics resumed, 2026-10-10

This lane resumed from committed `68017d0`, corrected its hosted IC-33 failure, then built
and checked immutable `3d92b05782ea17ac708cfa3494794d146920c4a1` and, after the notice fix,
`89525673ae4d9e8c76da0526a134e59de03615d1`. Both exact local archives pass
`R CMD check --as-cran` on R 4.5.0 with zero errors, warnings and notes; required source
gates also pass. Current-release/R-devel/Windows checks of the newest exact bytes remain
pending. The maintainer's dirty DESCRIPTION roxygen preference and AGENTS file are preserved.

## Latest immutable 8952567 artifact

The follow-up build uses committed source `89525673ae4d9e8c76da0526a134e59de03615d1`,
including the independently reviewed notice/spinner fix. Its separate normal archive is
`dev/.validation/resume-20261010-68017d0/8952567/gptr_1.0.0.tar.gz`, **2,218,170 bytes**,
SHA256 `e22172a337fe8efd6383aa570675061aae193fc7b1c7bff5680490e85550c6a8`.
The earlier 3d92b05 archive and every earlier log remain intact.

Normal build exited zero in 20.226s, normal archive installation into this lane's separate
library exited zero in 13.868s, and exact `R CMD check --as-cran` exited zero in 427.438s
with exactly one **Status: OK** line: **ERROR 0 / WARNING 0 / NOTE 0**. The checker retained
incoming feasibility, all 14 vignette rebuilds, PDF/HTML manuals and detritus checks. It used
the same R 4.5.0, isolated paths, low priority, two-worker ceiling and single-thread numerical
libraries described below; `_R_CHECK_LOG_USE_INFO_=true` and `R_KEEP_PKG_SOURCE` unset
remain explicit environment qualifications.

The actual test reporter gives **PASS 22,645 / FAIL 0 / WARN 0 / SKIP 386**. The unchanged
skip inventory is 363 `On CRAN`, nine live-gated tests, 13 source-layout/C-locale cases and
one keyring-absence case. Section CPU/elapsed timings are incoming 3/20s, R code 35/35s,
examples 4/4s, tests 272/322s, vignette rebuilds 8/8s, PDF 4/4s and HTML 1/1s.
Size is **INFO 6.4Mb / R 5.1Mb**, not a NOTE in this explicitly qualified environment.
Normal installed size is 6,556 KiB (R 5,200, doc 596, help 496); the checker's independent
installation is 6,584 KiB. No size threshold or test budget was changed.

Actual archive layout is 663 entries, 624 regular files and 8,141,411 uncompressed logical
bytes. All 14 source Rmd guides, 14 shipped Rmd guides and 14 built HTML guides are present;
each installed HTML hash matches its archive member. `inst/doc/` is 555,401 logical bytes,
including 413,980 HTML bytes. Root development/site/pkgdown folders, credential/environment
files, `.orig` sources, AGENTS/CLAUDE and compiled/install-hook files are absent. Legitimate
`tests/testthat/fixtures/docs/` remains shipped. Eight external Imports and six base R modules
are unchanged, and all nine figure files match the committed export.

The build/install/check controller completed in 461.834s, sampled peak family RSS
1,975.1 MiB over 462 samples with zero sampling errors, and recorded no timeout or resource
stop. Minimum sampled disk free was 12.95 GiB; maximum owned output was 117,285,618 bytes.
Its guards remained 4 GiB free disk, 2 GiB owned outputs and a 3,900s outer deadline.

The following gates then ran sequentially against the same immutable export:

| Gate | Result | Profiled elapsed / peak family RSS |
| --- | --- | --- |
| Documentation | 0 problems | 0.475s; too short for useful RSS sampling |
| Shipped files (`all`) | 0 problems | 0.312s; too short for useful RSS sampling |
| Full-package lint | Zero lints | 85.375s / 1,054.5 MiB |
| Offline reference examples | 58 pages, 0 problems | 35.860s / 393.7 MiB |
| Guide precompute (`--check`) | All 14, 0 problems | 23.967s / 398.6 MiB |

The slowest example was `gptr_rewind` at 0.42s; all 14 guide knits totaled 9.9s. Every gate
exited zero with no deadline/resource stop or sampling error. The testthat R-build-version
startup advisory remains in raw logs, outside counted test warnings. No generated guide
outputs were rewritten. All 119 working R files still match the committed export, and
DESCRIPTION/AGENTS hashes match their before-run values. The sorted filename/SHA256 R
fingerprint is `aaa9c6a2ce5acd1e0b680df253ad7ae7c24990fd9d71b5e707b677c5c0c6f257`.

Evidence uses `8952567/summary-8952567.json`, `archive-layout-8952567.json`,
`archive-structure-8952567.json`, `source-R-sha256.json`, the complete `gptr.Rcheck/`,
`artifact-8952567-*`, `gates-8952567-*`, `source-gates-8952567.json` and
`completion-snapshot-8952567.json` under the same ignored validation directory.
The coordinator received the exact archive path/digest before installing its own library;
this lane did not overwrite that shared library. At 17:29 PDT, the host reported 55.75% CPU
idle, load 9.13/9.75/9.15, 5,145 MiB unused physical memory, 41,838.69 MiB used swap and
14 GiB free disk. No further compute job is running in this lane; the next compaction
investigation starts with source review. Current-release/R-devel/Windows exact-byte gates
remain separate from this installed-R diagnostic.

## Historical 3d92b05 certificate

The sections below retain the earlier successful archive, layer correction and resource
measurements. Their working-source comparisons refer to completion of that earlier run.

## Layer correction and focused evidence

The existing `r_doc_outputs()` formatter moved verbatim from `R/tool-r.R` into
`R/eval-format.R`, an existing evaluator-formatting service file. Both canonical R-tool and
native MCP recording callers keep one implementation. MCP now passes the same three-field
custom record directly to allowed `session_append()`; canonical entry redaction, IDs, parent,
time and persistence remain there. No SDK allowlist, layer test or behavior test was relaxed.
Independent source review found no blocker.

- RED `arch-layers`: 12 passing assertions, one failure, zero counted warnings/skips/errors.
  The failure names exactly `mcp_serve_r -> entry_custom` and `mcp_serve_r -> r_doc_outputs`.
  Profile: 18.260s, 19 samples, 514.9 MiB summed family RSS, zero sampling errors.
- GREEN `arch-layers|mcp-recording|tool-r|eval-format|doc-blocks`: 642 passing assertions,
  zero failures/errors/counted warnings/skips. Profile: 28.858s, 29 samples, 662.0 MiB,
  zero sampling errors.
- Three-file lint: zero lints; process exited zero.

The installed testthat build-version advisory (built under R 4.5.2, local R 4.5.0) remains
in raw output outside counted test warnings. These bounded jobs used low priority, at most
two test workers, numerical-library threads one, fake providers/CLIs only, isolated user
paths, and owned process-family cleanup. RSS excludes GPU/model-server memory and may count
shared pages twice or miss short-lived/reparented children.

Raw logs, assertion summaries, profiler CSV/JSON and formatter identity evidence are under
ignored `dev/.validation/resume-20261010-68017d0/` (`arch-red*`, `layer-green*`, `layer-lint*`,
`formatter-move.json`). The formatter's moved text SHA256 is
`265e3138c4a1384c9f87f96892c6e0ab4267f71b564a68b4fe914901de119729`.

## Exact immutable archive and installed contents

Read-only `git archive` exported the committed source into ignored
`dev/.validation/resume-20261010-68017d0/export-3d92b05`. Normal `R CMD build` produced
`3d92b05/gptr_1.0.0.tar.gz`: **2,216,695 bytes**, SHA256
`5ced56de6454cba771af7fff4a6459a22a5fb2258b351ee92ce678e0a9899d05`.
The build exited zero in 19.955s. The archive contains 623 regular files totaling 8,133,546
uncompressed logical bytes; that total is distinct from compressed archive size.

The actual archive has 14 shipped Rmd guides and 14 built HTML guides. All 14 installed HTML
hashes match those archive members. Archive `inst/doc/` totals 555,401 logical bytes, including
413,980 HTML bytes. Development/website/pkgdown outputs, credentials/environment files,
`.orig` sources and AGENTS/CLAUDE files are absent. Archive listing/layout evidence is
`3d92b05/archive-3d92b05.txt` and `3d92b05/archive-layout-3d92b05.json` beneath the ignored
validation directory. The actual archive retains eight fixed external Imports and six base R
modules, `NeedsCompilation: no`, optional `Enhances: repr` and both vignette builders. No
compiled/source-install-hook files are present; all nine figure files match the committed
export. All 119 working R source hashes still match the immutable export.

Normal `R CMD INSTALL` of that archive into a separate owned library exited zero in 13.430s.
Installed `du -k` is 6,592 KiB: R 5,236, doc 596, help 496 and remaining directories 264.
The checker independently installed it in 13s and measured 6,572 KiB. These are real normal
archive installations, unlike the earlier direct-source installation without built guides.
The coordinator received the archive path/digest before using its own development library;
this lane did not overwrite that shared library.

## Exact archive check

`R CMD check --as-cran gptr_1.0.0.tar.gz` retained incoming, vignette and PDF/HTML manual
checks. Actual environment: R 4.5.0, aarch64-apple-darwin20, macOS 26.7.1, UTF-8,
`_R_CHECK_TIMINGS_=0`, `_R_CHECK_ALWAYS_LOG_VIGNETTE_OUTPUT_=true`,
`_R_CHECK_LOG_USE_INFO_=true`, `_R_CHECK_LIMIT_CORES_=true`, numerical-library threads one,
test workers at most two, and `R_KEEP_PKG_SOURCE` unset. Package live tests stayed disabled
and private credentials/user/cache/project paths were isolated; incoming feasibility used
Internet access as a checker operation, not model inference.

The checker exited zero in 437.603s with exactly one **Status: OK** line:
**ERROR 0 / WARNING 0 / NOTE 0**. Installed size was **INFO 6.4Mb / R 5.1Mb**; the INFO setting
is retained here rather than relabeling the diagnostic or hiding size. Incoming feasibility,
load/unload, dependency/code/Rd checks, installed guide layout, rebuilt guides, manuals,
nonstandard files and temporary detritus all passed.

| Check section | CPU / elapsed seconds from checker |
| --- | --- |
| Incoming feasibility | 3 / 36 |
| Installation | 13 / 13 |
| R code possible problems | 35 / 35 |
| Examples | 4 / 4 |
| Tests | 266 / 314 |
| Vignette output rebuild | 7 / 7 |
| PDF manual | 3 / 3 |
| HTML manual | 1 / 1 |

The actual test reporter gives **PASS 22,603 / FAIL 0 / WARN 0 / SKIP 386**. Skips are retained:
363 `On CRAN`, nine explicitly gated live tests, 13 source-layout/C-locale cases and one
optional keyring-absence case. This CRAN-mode run does not claim to run
the cases deliberately skipped there; source/hosted coverage remains separate. The installed
testthat R-build-version startup advisory is in raw output, outside counted test warnings.

The build/install/check controller completed in 471.335s, with sampled peak summed family
RSS 2,002.1 MiB, 472 one-second samples and zero sampling errors. Minimum sampled disk free
was 12.24 GiB; maximum owned output was 65,024,617 bytes, well inside the 4 GiB free-disk and
2 GiB output stop guards. Jobs used low priority and scoped process-family cleanup. RSS may
count shared pages twice and miss short-lived/reparented processes; it does not measure GPU
or whole-machine unified-memory usage.

Raw `00check.log`, `testthat.Rout`, example timings, install logs and manual artifacts remain
under `3d92b05/gptr.Rcheck/`. `summary-3d92b05.json`, the normal installed-size log and
`artifact-3d92b05-{controller,resources}.json` record phase status, settings and resource limits.

## Sequential source gates

These commands ran against the same immutable export, with no shipping-input edits or
second overlapping job in this lane:

| Command | Result | Whole profiled elapsed / peak family RSS |
| --- | --- | --- |
| `Rscript --vanilla dev/release/check-docs.R` | 0 problems | 0.370s; too short for useful RSS sampling |
| `Rscript --vanilla dev/release/check-files.R all` | 0 problems | 0.262s; too short for useful RSS sampling |
| `Rscript --vanilla dev/ci/isolated-check.R lint` | Zero lints | 79.869s / 1,031.8 MiB |
| `Rscript --vanilla dev/release/check-examples.R` | 58 fresh-process pages, 0 problems | 35.265s / 434.2 MiB |
| `Rscript --vanilla dev/release/precompute.R --check` | All 14 guide sources, 0 problems | 23.004s / 399.8 MiB |

The slowest example was `gptr_rewind`, 0.42s. All 14 guide knits totaled 9.6s, below the existing
60s project gate. Example checks retained offline isolation, closed-port proxies and
connection/process/file cleanup checks. Guide source checks knitted scratch copies; committed
precomputed outputs were not rewritten. These release helpers install the immutable source in
their own temporary libraries; they do not substitute for the normal exact-archive check above.
Every gate exited zero without a deadline/resource stop or sampling error. Gate logs/profiles
and `source-gates-3d92b05.json` are in the same ignored validation directory. At completion,
all 119 R hashes still match the export. The 17:00 PDT host snapshot reports 57.1% CPU idle,
load 7.77/8.21/10.18, 33 GiB unused memory, 42,623.94 MiB used swap and 13 GiB available disk,
with no recorded thermal/performance warning. This does not authorize further concurrency;
no more local R jobs are planned in this lane.

## Policy interpretation and remaining gates

Primary policy was refreshed on 2026-10-10. The compressed archive is below the preferred
10 MB source-tarball guidance, and built guide content is below the general 5 MB documentation
guidance. CRAN asks for minimal checking CPU time and at most two simultaneous cores;
there is no universal five-minute total-check acceptance limit in that policy.
[CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html)

The installed total exceeds the checker's default 5,120 KiB size-reporting threshold. The
checker switches this diagnostic between INFO and NOTE according to its log-info setting;
this run explicitly used INFO. The R directory accounts for most of the installed size.
No size threshold, test timeout or release-tool budget was widened.
[R-devel checker](https://svn.r-project.org/R/trunk/src/library/tools/R/check.R)

This is a current-source local diagnostic on R 4.5.0, not a submission-ready upload gate.
The current primary release manual is R 4.6.1. CRAN asks for a normal build on current
release/R-patched and a check of the exact upload bytes on current R-devel (or an explained
current-release fallback), plus Windows and reverse-dependency verification. Earlier hosted
checkout rebuilds are not proof for this archive. A later workflow-produced current-release
archive must be adopted and checked by its own hash, not called byte-identical to this local
archive. Current-release/R-devel/Windows exact bytes, fresh reverse dependencies and final
submission comments/maintainer authorization remain pending. No upload/submission or system-R
replacement occurred in this lane.
[Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html),
[CRAN submission requirements](https://cran.r-project.org/web/packages/policies.html#Submission)
