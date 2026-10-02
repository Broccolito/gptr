from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `setup.R` (P01) | §3.2 environment: redirected `R_USER_*_DIR`, blank keys, `GPTR_REPLAY=replay`, `OMP_THREAD_LIMIT=2`, `options(gptr.interactive = FALSE, gptr.quiet = TRUE)` |""",
"""| `setup.R` (P01) | §3.2 environment: redirected `R_USER_*_DIR`, `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME`, `GPTR_PROJECT_ROOT` (a temporary project, IC-63), blank keys, `GPTR_REPLAY=replay`, `OMP_THREAD_LIMIT=2`, `options(gptr.interactive = FALSE, gptr.quiet = TRUE)` |"""),
("""| `helper-tracemem.R` (P01) | `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL)`: writes a script that loads gptr (`library(gptr)` when installed, else `pkgload::load_all()` of the source tree), evaluates `setup` (chr: code creating `object`, e.g. `big = runif(5e6)`), `tracemem(object)` with output to a file, `action` (chr: the gptr code under test), then `edit`; runs it with `Rscript --vanilla` through processx;""",
"""| `helper-tracemem.R` (P01) | `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)`: writes a script that loads gptr (`library(gptr)` when installed, else `pkgload::load_all()` of the source tree; that call exists only in the generated script text, never as package or test code, IC-71), evaluates `setup` (chr: code creating `object`, e.g. `big = runif(5e6)`), `tracemem(object)` with output to a file, `action` (chr: the gptr code under test; with `in_run_edit = TRUE` the fake provider's `r` call runs `edit` inside the run, IC-41), then `edit`; runs it with `c(rscript_path(), "--vanilla", <script>)` through processx (IC-60);"""),
("""| `helper-mock-server.R` + `fixtures/mock_server.R` (P01) | `local_mock_server(scenario, ..., .env = parent.frame())` -> `list(url, port, log = function() df(time, method, path, headers (redacted), body, disconnected), stop = function())`; a base-R `serverSocket()`/`socketSelect()` server run with processx; skips on CRAN.""",
"""| `helper-mock-server.R` + `fixtures/mock_server.R` (P01) | `local_mock_server(scenario, ..., .env = parent.frame())` -> `list(url, port, log = function() df(time, method, path, headers (redacted), body, disconnected), stop = function(), provider = <spec:provider with offline = TRUE>)`; a base-R `serverSocket()`/`socketSelect()` server run with `rscript_path()` through processx; it listens on every interface (base R has no host argument), so it answers only paths carrying a per-run token and lives for one test; skips on CRAN (IC-71). The returned provider record is `offline = TRUE` so `GPTR_REPLAY=replay` does not block it (IC-45)."""),
("""`systemone` (JSON answers from `answers = function(body)`), `json` (a fixed body) |""",
"""`systemone` (JSON answers from `answers = function(body)`), `json` (a fixed body), `redirect` (a 307 to a second origin that logs any key bytes, IC-64) |"""),
("""| `helper-arch.R` (P01) | `arch_layer_table()` -> df(`file`, `layer`) from §3.2 of `03`; `arch_allowed()` -> the `03` §2.2 matrix; `arch_services()` -> the §7.0 service table (declared services a built-in may call) |""",
"""| `helper-arch.R` (P01) | `arch_layer_table()` -> df(`file`, `layer`) from §3.2 of `03`; `arch_fun_map()` -> df(`fun`, `file`) built by parsing the files under `R/` (found through `testthat::test_path("..", "..", "R")` or the check directory's `00_pkg_src`; the test skips with a message when absent); `arch_allowed()` -> the `03` §2.2 matrix; `arch_kernel_sdk()` -> the IC-33 allowlist; `arch_services()` -> the §7.0 service table (literal `ext_service_get("<name>")` calls are mapped to the providing plan; an undeclared name fails) |"""),
("""- **Lint rules** (`test-lint-rules.R`, P01): scans `R/` for `:::`, non-ASCII bytes, `rlang::enquo`/`enquos`/`quo`,
  `cli_*()`/`glue` calls with a non-literal first argument, `.GlobalEnv`, `lockBinding`/`unlockBinding`,
  `processx::run(`, `serialize(`/`saveRDS(` without `ascii = FALSE` outside `utils-paths.R`, `<-` assignments,
  `%>%`, calls to `askYesNo(`, `menu(` or `select.list(` (gptr's own prompts use the UI kind), `Sys.setenv(`
  outside `auth-dotenv.R`, and `set.seed(`, `sample(`, `runif(` anywhere (ids and jitter are RNG-free).""",
"""- **Lint rules** (`test-lint-rules.R`, P01): scans `R/` for `:::`, non-ASCII bytes, `rlang::enquo`/`enquos`/`quo`,
  `cli_*()`/`glue` calls with a non-literal first argument, `.GlobalEnv`, `lockBinding`/`unlockBinding`,
  `processx::run(`, `serialize(`/`saveRDS(` without `ascii = FALSE` outside `utils-paths.R`, `<-` assignments
  (found as `LEFT_ASSIGN` tokens through `getParseData()`, not by a text regex, IC-72), `<<-` outside closures
  updating enclosing-function state, `%>%`, calls to `askYesNo(`, `menu(` or `select.list(` (gptr's own prompts use
  the UI kind), `Sys.setenv(` outside `auth-dotenv.R`, `set.seed(`, `sample(`, `runif(`, `RNGkind(` anywhere (ids
  and jitter are RNG-free), `.Random.seed` assignment outside `rng_swap()` and `with_seed_preserved()`,
  `httpuv::randomPort(`, `tools::pskill(`, `enc2utf8(` outside `utils-encoding.R`, `withr::` in `R/`, and a bare
  `"R"` or `"Rscript"` command passed to `proc_spawn()`/`proc_run()` (IC-60, IC-61, IC-62, IC-72)."""),
("""| `fixtures/cli/claude-<case>.ndjson`, `codex-<case>.jsonl` | P20 | redacted CLI transcripts; `inst/gptr/fixtures/fake_cli.R` replays them as a fake `claude`/`codex` |""",
"""| `fixtures/cli/claude-<case>.ndjson`, `codex-<case>.jsonl` | P20 | redacted CLI transcripts; `inst/gptr/fixtures/fake_cli.R` replays them as a fake `claude`/`codex`, run as `c(rscript_path(), fake_cli)` through `gptr.cli_path` with `offline = TRUE` provider records (IC-60, IC-45) |
| `dev/bench/tokens/` NS-2 and NS-3 golden transcripts and runner | P07 (IC-73) | other NS fixtures added by P10, P13, P15, P18, P19, P22, P23, P24 |"""),
("""Not edited (outside this task's files; recorded as open issues): the Final decisions D-25 and D-28 of
`01-decision-register.md` (event names and the export count), and `dev/plan/00-conventions.md` §4, whose example
predicate `gptr_has_key("anthropic")` is not an export (examples use the fake provider or
`nzchar(Sys.getenv("ANTHROPIC_API_KEY"))`).""",
"""The review round of 2026-09-30 (§15, IC-32..IC-73) edited `03`, `05`, `01-decision-register.md` (D-28 now says
63 exports; a "Review amendments" block records the changed decisions) and `dev/plan/00-conventions.md` (the
former open issues: the `gptr_has_key()` predicate, `withr` in package code, the literal non-ASCII example, the
class-list pointer). `06-review-resolution.md` lists every change by issue. Main edits:

| Where | After | Decision |
|---|---|---|
| `03` §2.2, §3.2 | kernel SDK allowlist; `R/aaa-state.R` (P01); `gptr_prob()` in `s1-types.R`; gateway methods all P08; `out` only in P10; `gptr_jobs()` in `proc-supervise.R`; `gptr_scrub()` in `auth-redact.R`; 118 files | IC-32, IC-33, IC-36 |
| `03` §4 | `gptr_map()` internal, `gptr_scrub()` exported (63 exports); constructor signatures of IC-35; route order | IC-35, IC-36, IC-39 |
| `03` §5.1, §6.9.2 | store open-append-close, torn-line recovery, ps-based locks; `the$last` strong | IC-59, IC-71 |
| `03` §6.1-6.2 | reactor depth, `allow_runs` default, `later::run_now(0)` at depth 1; `followlocation = 0`; relays by source | IC-55, IC-57, IC-64 |
| `03` §6.4, §6.12 | R8 clears `withVisible()`; symbol dots not forced; `rng_swap()`; `pdf(NULL)`; image caps | IC-41, IC-61, IC-67 |
| `03` §6.5-6.7 | complete child environments, empty `R_ENVIRON_USER` everywhere, G6 CLI lists, `encoding = "UTF-8"`, `rscript_path()`, supervision default | IC-60, IC-65 |
| `03` §6.8, §6.10 | fail-closed gate, control category, `ask_human`, plan allowlist, control paths, trust-dependent instruction authority, user-level project file, trust fingerprint | IC-52, IC-53, IC-54 |
| `03` §6.9.3 | document route by located blocks, write consent, `args=`, replay in place, fork binding, team and block-nested recording, stripping, transcripts as pipe chains, Jupyter pending blocks, sidecar recovery, forced replay only in examples | IC-45..IC-51 |
| `03` §7, §12 | prompt composition by owners, `str()` removed, `r` schema variants, skill pseudo-paths, new measured totals, new cost rows | IC-67, IC-68, IC-73 |
| `03` §8.3 | claude and codex argv, sandbox mapping, billing checks | IC-65 |
| `03` §9.1 | `ps` in Imports | IC-59 |
| `03` §11 | 38 kinds; per-record overrides; session-scoped extensions; router contract; worker registry | IC-69 |
| `05` P01-P25 | scopes and acceptance per the decisions above; P17 depends on P10; P19's CLI leg moved to P20; P25 adds `VignetteBuilder` | IC-36, IC-72, IC-73 |"""),
("""| P01 | Foundation | M0 | - | `utils-*.R` (7), `json-*.R` (3), `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` |""",
"""| P01 | Foundation | M0 | - | `aaa-state.R`, `utils-*.R` (7), `json-*.R` (3), `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` |"""),
("""| P17 | Skills, templates, agent files and plugins | M3 | P08 | `skill-discover.R`, `skill-templates.R`, `subagent-defs.R`, `ext-plugins.R` |""",
"""| P17 | Skills, templates, agent files and plugins | M3 | P08, P10 | `skill-discover.R`, `skill-templates.R`, `subagent-defs.R`, `ext-plugins.R` |"""),
("""| P03 | `gptr_env`, `gptr_redact` |""",
"""| P03 | `gptr_env`, `gptr_redact`, `gptr_scrub` |
| P04 | `gptr_jobs` |"""),
("""| P08 | `gptr`, `gptr_init`, `gptr_config`, `gptr_trust`, `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_on`, `gptr_return`, `gptr_prob` |""",
"""| P08 | `gptr`, `gptr_init`, `gptr_config`, `gptr_trust`, `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_on`, `gptr_return` |"""),
("""| P11 | `gptr_permissions`, `gptr_risk` |""",
"""| P11 | `gptr_permissions`, `gptr_risk` |
| P13 | `gptr_prob` |"""),
("""| P19 | `gptr_parallel`, `gptr_map` |
| P21 | `gptr_jobs` |
| P23 | `gptr_artifacts` |

Total: 1 + 18 + 2 + 2 + 5 + 1 + 11 + 1 + 2 + 4 + 3 + 3 + 6 + 2 + 1 + 1 = 63 (P08's 11 names are `gptr` plus 10
`gptr_*`).""",
"""| P19 | `gptr_parallel` |
| P23 | `gptr_artifacts` |

Total (IC-36): 1 + 18 + 3 + 1 + 2 + 5 + 1 + 10 + 1 + 2 + 1 + 4 + 3 + 3 + 6 + 1 + 1 = 63 (P08's 10 names are
`gptr` plus 9 `gptr_*`; `gptr_map()` is internal, `gptr_scrub()` is new)."""),
]
apply(P, pairs)
