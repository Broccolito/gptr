# Immutable artifact and CRAN diagnostics resumed, 2026-10-10

This lane resumed from committed `68017d0`. The maintainer's dirty DESCRIPTION roxygen
preference and AGENTS file are preserved. The exact immutable archive gate has not run yet:
first, hosted CI exposed the native MCP recording fix's two IC-33 layer violations.

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

## Pending immutable artifact gate

After the coordinator commits the reviewed correction, export that exact commit, run normal
`R CMD build`, retain archive SHA256/bytes/listing and all 14 built HTML guides, then check
that same archive with `R CMD check --as-cran` including manual/incoming checks. Record actual
severity, installation/section/example/test/vignette timings, installed `du -k` and directories,
and owned process-family resources. Required source docs/files/lint/offline-example gates
remain to be run sequentially. No archive bytes, current-artifact check or installed-size
result is claimed here.

The available local R is 4.5.0. A successful local diagnostic does not replace checks of the
same exact archive on current release/R-devel or Windows. Existing hosted results rebuilt
their checkout and are not byte-identical upload-artifact proof. No CRAN submission is part
of this lane. See [current CRAN readiness review](cran-readiness-20261010.md) for primary
policy links and thresholds; those thresholds are unchanged.
