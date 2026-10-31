# Independent manual CRAN review — 2026-10-31

Scope: current working tree on `codex/cran-consent-readiness`, based on
`769dea874fb77afab1525294147712a6939f9806`, including uncommitted changes being
coordinated by the parent agent. This ledger is excluded by `^dev$` in
`.Rbuildignore`. This reviewer changed no package source, installed library,
credentials, Git branch, remote repository, or submission form.

This is source review and targeted offline evidence, not a new full check and not
a prediction of CRAN acceptance. The earlier baseline check/test reports concern
the previous tarball. The changed candidate still needs its own completed
validation and exact-tarball evidence.

## Confirmed findings and minimal fixes

1. **Declared cli minimum was too old.** The original `cli (>= 3.6.0)`
   permitted cli 3.6.0/3.6.1, but `R/console-commands.R` calls
   `cli::ansi_string()` in command help, background exit messages, and compact
   status. The tagged v3.6.0 NAMESPACE does not export this function; the official
   cli changelog records its export in 3.6.2. The parent has now changed DESCRIPTION
   to `cli (>= 3.6.2)`. This resolves the identified version-floor mismatch
   without introducing another dependency or changing command behavior.
   Sources: [cli NEWS](https://cli.r-lib.org/news/index.html),
   [cli v3.6.0 NAMESPACE](https://github.com/r-lib/cli/blob/v3.6.0/NAMESPACE).

2. **Older supported processx versions changed the user's RNG.** The original
   `processx (>= 3.8.0)` permitted versions whose process constructor calls
   `get_id()`, which uses `sample()`. In gptr,
   `R/proc-spawn.R` calls `processx::process$new()` without wrapping the
   constructor in `with_seed_preserved()`. Thus even a shell/worker launch
   could advance or create `.Random.seed` on the previously permitted
   versions. The official processx changelog records the RNG fix in 3.8.6.
   The parent has now changed DESCRIPTION to `processx (>= 3.8.6)`.
   Sources: [constructor, v3.8.0](https://github.com/r-lib/processx/blob/v3.8.0/R/initialize.R#L129),
   [helper, v3.8.0](https://github.com/r-lib/processx/blob/v3.8.0/R/utils.R#L195-L201),
   [processx NEWS](https://processx.r-lib.org/news/index.html).
   The exact historical helper was executed in a fresh Rscript process and
   reported `historical_helper_advances_seed=TRUE`; no older package was
   installed. This is an execution of the helper plus source tracing of its
   caller, not a complete historical gptr integration run.

3. **Previously known context-none consent gap.** The original gateway omitted
   `egress_check()` for `context = "none"`, despite retaining project
   instructions and R environment metadata. The runtime owner has now changed
   `gateway_guards()` to call `egress_check(..., context = ...)`
   unconditionally. I verified this source change. The runtime owner's targeted
   tests and the parent release check establish validation; this reviewer does
   not claim to have rerun those tests. Documentation and reviewer comments must
   describe the final behavior consistently.

The historical namespace evidence for all six strong external dependencies with
successfully fetched tagged NAMESPACE files is retained below. A subsequent independent
request-path review also reproduced unacknowledged router fallback, in-run model-switch and
manual-compaction requests using scripted adapters only. The runtime fix now checks the existing
consent and replay gates during model preparation and before compaction requests. Native Ollama
decision-model preparation also checks consent before live discovery. The gateway, sub-agent,
typed-decision and coaching gates remain in place. Public CRAN-listed regressions cover these
paths, and independent probes now observe zero requests on refusal. The confirmation renderer,
saved provider approvals, request payloads and local/offline exemptions are retained.

The historical namespace evidence for all six strong external dependencies with
successfully fetched tagged NAMESPACE files is retained in
`../manual-policy-evidence/dependency-minima-evidence.json` relative to the
visualization root's project directory. Every directly referenced export of
ps 1.8.0, processx 3.8.0, curl 6.0.0, rlang 1.1.0, and jsonlite 1.8.8 was present;
cli's only missing referenced export was `ansi_string`. This does not prove
every argument/semantic detail across all dependency versions. The attempted
yaml 2.3.0 GitHub tag fetch failed; no historical-namespace assertion is made
for yaml.

A suspected `cli::hash_sha1()` floor mismatch was disproved: the function
arrived in 3.6.0, matching even the old minimum. No fix was requested for it.

## Other source reviewed; no additional confirmed defect found

- **Load/unload.** `.onLoad()` saves/restores the temporary callr option and
  runs internal registrations. Its intentional exception is `proc_sweep()`.
  The sweep reads only canonical marker filenames under gptr's own user cache
  (temporary storage in checked examples), preserves uncertain parent identity,
  creation-time mismatches and self records, and authorizes cleanup only for
  owned orphan identities. Unload paths stop recorded jobs, HTTP transfers,
  owned children and timers. The earlier isolated load probe found no new files,
  changed options/environment/working directory/RNG/workspace, or load errors.
  This ownership-based cleanup remains worth describing to reviewers; the
  source audit did not establish an unsafe unrelated-process kill.
- **Process fixture.** The old processx standalone `env = "current"`
  incompatibility was confined to the marker-family test fixture; production
  inheritance passes `c("current", NAMED_MARKER = "YES")`. The parent's
  `env = NULL` fixture correction is independent of the RNG dependency
  floor. Earlier scratch validation with processx 3.8.6 gave 81 passes, zero
  failures/warnings/skips, while the controlled sentinel proved the original
  inheritance defect. Those artifacts remain in the original audit directory.
- **Global state.** Option changes in the evaluator, console, plot capture,
  parsing helpers and optional bridges have restoration paths; mutable namespace
  state is private. The only deliberate main-process RNG assignments are
  preservation/swapping helpers. Generated code runs in the explicitly selected
  user environment and can modify it; the permission classifier is advisory.
  This is documented behavior, not proof of sandboxing. Child bootstrap
  `quit()` calls terminate the separate child, not the host R session.
- **Network.** No startup catalog download or telemetry path was found.
  Catalog refresh/discovery, OAuth, optional CLI adapters, MCP servers and
  providers are invoked by selected features. HTTP handles retain libcurl's TLS
  verification defaults; no source option disables certificate/host verification.
  Catalog requests have bounded responses/timeouts and informative failure
  paths. This review made no provider call.
- **Filesystem.** Settings/auth/trust/cache paths use
  `tools::R_user_dir("gptr", ...)`; explicit project/document features have
  consent/path checks. The catalog is replaced rather than accumulated; MCP
  stderr defaults to temporary files and uses rotation when persisted by an
  explicit debug setting; recovery files have byte and structure limits.
  Recorded analyses and project caches are user-directed durable artifacts,
  not install-time downloads. No additional unsolicited write was demonstrated.
- **Dependencies/API.** DESCRIPTION declares a single named maintainer, R >=4.2,
  public CRAN dependencies and optional external programs. The source uses public
  namespaced APIs, delayed public S3 registration, and hooks; the previous AST
  audit found no actual `:::` or `.Internal()` call in gptr's R code.
  There is no compiled source, configure/download-on-install script or mandatory
  local model/CLI/browser service. New cli/processx floors address the concrete
  compatibility defects above.
- **License/source/size.** The Apache-2.0 license and MIT-to-Apache change are
  explicit. `inst/COPYRIGHTS` preserves third-party notices for pi, models.dev,
  gitleaks and system-one-adapter-python. Vignette HTML is built from shipped
  readable Rmd; executable originals are in the repository and excluded from the
  tarball, a special build arrangement already disclosed in cran-comments.
  The earlier tarball inspection found no executable binary or excluded secret,
  Git, dev or machine-specific material. The approximately 3.1 MB source tarball,
  1.3 MB installed documentation and absence of data do not establish a policy
  size violation merely because installed byte-compiled R code totals about
  6 MB. A final candidate inventory must be checked after rebuilding.
- **Examples/tests/cores.** Examples use scripted offline providers; only the
  coaching example is in donttest, and interactive guards are restricted to
  sign-in and listening-server features. Fifteen shipped vignette sources contain
  no executable chunks. Checked pools are capped at two and tests set
  `OMP_THREAD_LIMIT=2`. A per-pool cap is not a proof about every arbitrary
  generated program's aggregate CPU use, but this audit found no measured
  check-farm violation. The fixed CRAN test list and broader CI suite are
  disclosed. The optional coaching runtime and complete check budget still need
  the parent's final measurement; earlier host-specific notes must not be
  relabeled as new-candidate results.

## Primary guidance and remaining submission facts

Re-read the current [CRAN Repository Policy](https://stat.ethz.ch/CRAN/web/packages/policies.html)
(revision 6985) and [submission checklist](https://stat.ethz.ch/CRAN/web/packages/submission_checklist.html).
Relevant requirements concern contributor rights and preserved notices, accurate
dependencies, source availability, minimal size/check cost, restricted state and
filesystem side effects, user confirmation before session disclosure, and public
APIs. Two simultaneous cores is the check-farm maximum. Updates must explain
license changes, assess reverse dependencies, use a current-R source build, and
check the exact uploaded tarball; significant unexplained check notes can prompt
revision. R-hub supplements these checks and does not certify CRAN acceptance.

The maintainer must personally substantiate contributor agreement/relicensing
authority, control and receipt of the maintainer mailbox, absence of another
pending submission, and any required notification of affected reverse
maintainers. Source code and automated checks cannot verify those assertions.
The parent must refresh reverse-dependency data and validation for the final
artifact rather than carry forward the prior tarball's dates or result counts.

No additional confirmed runtime or manual-policy blocker was identified in the
other areas reviewed above. This conclusion is limited to the inspected source
and available evidence; it is not a warranty of legal rights or acceptance.
