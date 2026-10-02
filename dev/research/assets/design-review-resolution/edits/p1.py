from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
("""`04-interface-contract.md` (the interface contract: every exported and cross-plan function, record, class, file
format, option and test helper; its §13 lists the reconciliation edits made here), then the plan. Every code
sample uses `=` and `|>` (S-9).""",
"""`04-interface-contract.md` (the interface contract: every exported and cross-plan function, record, class, file
format, option and test helper; its §13 lists the reconciliation edits made here), then the plan. The review round
of 2026-09-30 (`06-review-resolution.md`; contract §15, IC-32..IC-73) amended the scopes and acceptance checks
below; each plan's "Review amendments" bullet lists what it must add. Every code sample uses `=` and `|>` (S-9)."""),
("""  file mirroring each R file it owns (`tests/testthat/test-<area>-<topic>.R`). Exceptions are named in the
  plan. No plan adds an Import (conventions §8): P01 writes the final Imports and Suggests once.""",
"""  file mirroring each R file it owns (`tests/testthat/test-<area>-<topic>.R`). Exceptions are named in the
  plan. No plan adds an Import (conventions §8): P01 writes the final Imports (now including `ps`, IC-59) and
  Suggests once; P25 adds `VignetteBuilder: knitr` with the vignettes (IC-72), the one named DESCRIPTION exception."""),
("""  `on_load(ext_declare_builtin("<name>", builtin_<name>))` (P01's `on_load()` registry, P02's declaration
  table); gateway routes (classifier, team, fan-out, document, console) are registry records contributed by
  their owning plans. So later plans never edit an earlier plan's file.""",
"""  `on_load(ext_declare_builtin("<name>", builtin_<name>))` (P01's `on_load()` registry in `R/aaa-state.R`, which
  collates first so that top-level `on_load()` calls work at install time, IC-32; P02's declaration table);
  gateway routes (classifier, team, fan-out, document, console), services (owned by their built-in, IC-34), prompt
  sections and `r_session` fragments (IC-68) are registry records contributed by their owning plans. So later
  plans never edit an earlier plan's file."""),
("""  `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`, whose
  expected result is 0 errors, 0 warnings and at most the "New submission" NOTE, on the CI matrix of P01.""",
"""  `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`, whose
  expected result is 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the
  maintainer (gptr 0.7.0 is on CRAN, so 1.0.0 is an update and gets no "New submission" NOTE; IC-72), on the CI
  matrix of P01. Tests that spawn processes call `skip_on_cran()`, and every child-process pool is capped at 2
  under check (IC-60)."""),
("""| M0 Foundation | P01-P04 | skeleton, utilities, registry and extension API, secrets, reactor and process engine | reactor INFRA-01/05/06/21/23 on the mock server; registry conformance; redaction properties; `--as-cran` clean on macOS, Windows, Linux, oldrel-4, no-suggests, `LC_ALL=C` |""",
"""| M0 Foundation | P01-P04 | skeleton, utilities, registry and extension API, secrets, reactor and process engine | `R CMD INSTALL` succeeds with top-level `on_load()` calls in later-collating files (IC-32); reactor INFRA-01/05/06/21/23 on the mock server; registry conformance; redaction properties; no connection left open; `--as-cran` clean on macOS, Windows, Linux, oldrel-4, no-suggests, `LC_ALL=C` |"""),
("""| M4 Interop and scale-out | P18-P21 | MCP client and server, OAuth, sub-agents, CLI providers, background sessions | NS-6 (inline + worker + fake CLI on one reactor), NS-9, NS-10 MCP; INFRA-16/19 |""",
"""| M4 Interop and scale-out | P18-P21 | MCP client and server, OAuth, sub-agents, CLI providers, background sessions | NS-6 (inline + worker + fake CLI on one reactor; the CLI leg in P20, IC-36) and its replay with zero requests, NS-9, NS-10 MCP; INFRA-16/19 |"""),
("""P08, P11 -> P14 ;  P08, P10 -> P15 ;  P11, P15 -> P16 ;  P08 -> P17""",
"""P08, P11 -> P14 ;  P08, P10 -> P15 ;  P11, P15 -> P16 ;  P08, P10 -> P17"""),
("""| P01 | Foundation | M0 | - | 14 |""", """| P01 | Foundation | M0 | - | 15 |"""),
("""| P17 | Skills, templates, agent files, plugins | M3 | P08 | 4 |""", """| P17 | Skills, templates, agent files, plugins | M3 | P08, P10 | 4 |"""),
]
apply(P, pairs)
