from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
# P01
("""  - Rewrite `DESCRIPTION`: Package gptr, Version 0.99.0.9000, Title "Language Model Agents Inside the Live 'R'
    Session", one-paragraph Description per 13 §3 (software names single-quoted), `Authors@R` unchanged,
    `License: MIT + file LICENSE` (year 2026 in `LICENSE`), `Depends: R (>= 4.2.0)`, the final Imports
    (jsonlite, curl, processx, callr, rlang, cli, yaml, methods, stats, tools, utils, grDevices, graphics) and
    Suggests (architecture §9.2) with floors, `SystemRequirements`, `Config/testthat/edition: 3`,
    `Encoding: UTF-8`, `Roxygen: list(markdown = TRUE)`.""",
"""  - Rewrite `DESCRIPTION`: Package gptr, Version 0.99.0.9000, Title "Language Model Agents Inside the Live 'R'
    Session", one-paragraph Description per 13 §3 (software names single-quoted), `Authors@R` with the current
    maintainer in roles `aut`, `cre`, `cph` plus `person("Mario", "Zechner", role = c("ctb", "cph"), comment =
    "Author of 'pi' (MIT), from which tool texts and templates are derived")`, `Copyright: file inst/COPYRIGHTS`,
    `URL`, `BugReports`, `Language: en-US`, `License: MIT + file LICENSE` (year 2026 in `LICENSE`, plus
    `LICENSE.md`), `Depends: R (>= 4.2.0)`, the final Imports (jsonlite, curl, processx, callr, rlang, cli, yaml,
    ps, methods, stats, tools, utils, grDevices, graphics) and Suggests (architecture §9.2) with floors,
    `SystemRequirements`, `Config/testthat/edition: 3`, `Encoding: UTF-8`, `Roxygen: list(markdown = TRUE)`; no
    `VignetteBuilder` (P25 adds it) (IC-72)."""),
("""  - `.lintr` with `assignment_linter(operator = "=")`, `line_length_linter(100)`, `object_name_linter("snake_case")`;
    `.Rbuildignore` (`^dev$`, `^\\.github$`, `^\\.lintr$`, `^cran-comments\\.md$`, `^CRAN-SUBMISSION$`,
    `^_pkgdown\\.yml$`, `^vignettes/.*\\.Rmd\\.orig$`, `^\\.gptr$`, `^README\\.Rmd$`, `^LICENSE\\.md$`, Rproj
    entries); `.gitignore`; `dev/style.R` (`gptr_style()`, conventions §4).""",
"""  - `.lintr` with `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`,
    `object_name_linter(styles = "snake_case", regexes = c(s3 = "^(\\\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\\\.[a-z0-9_]+$"))`
    (IC-72); `.Rbuildignore` (`^dev$`, `^\\.github$`, `^\\.lintr$`, `^cran-comments\\.md$`, `^CRAN-SUBMISSION$`,
    `^_pkgdown\\.yml$`, `^vignettes/.*\\.Rmd\\.orig$`, `^\\.gptr$`, `^README\\.Rmd$`, `^LICENSE\\.md$`, `^CLAUDE\\.md$`,
    `^AGENTS\\.md$`, `^\\.claude$`, Rproj entries); `.gitignore`; `dev/style.R` (`gptr_style()`, conventions §4)."""),
("""    oldrel-1), oldrel-4, `_R_CHECK_FORCE_SUGGESTS_=false` no-suggests job, an `LC_ALL=C` job, and a
    copy-safety job running `devtools::test(filter = "copy")` on R-release and R-devel.""",
"""    oldrel-1), oldrel-4, `_R_CHECK_FORCE_SUGGESTS_=false` no-suggests job, an `LC_ALL=C` job, a
    copy-safety job running `devtools::test(filter = "copy")` on R-release and R-devel, a job running
    `devtools::test()` with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true` (IC-59), and a `bench` job that installs
    rtiktoken and runs `Rscript --vanilla dev/bench/tokens/run.R --check` once P07 adds the runner (IC-73)."""),
("""  - R files: `utils-conditions.R`, `utils-hash.R`, `utils-encoding.R`, `utils-options.R`, `utils-paths.R`,
    `utils-text.R`, `utils-tokens.R`, `json-encode.R`, `json-partial.R`, `json-schema.R`,
    `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` (architecture §3.2).""",
"""  - R files: `aaa-state.R` (collates first: `the`, `on_load()`, `on_unload()`, the bootstrap service table, the
    redaction hook, the internal `%||%`; IC-32, IC-34), `utils-conditions.R`, `utils-hash.R`, `utils-encoding.R`,
    `utils-options.R`, `utils-paths.R`, `utils-text.R`, `utils-tokens.R`, `json-encode.R`, `json-partial.R`,
    `json-schema.R`, `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` (architecture §3.2)."""),
("""  - `on_load(expr)` registry in `utils-options.R`, run by `.onLoad` in `zzz.R`; `.onUnload` calls registered
    cleanups; the service table `ext_service_set()`/`ext_service_get()`/`ext_service_has()` and
    `setting_get()` (contract IC-09, §7.0-7.1), through which earlier plans reach services of later ones.""",
"""  - `on_load(expr)` registry in `aaa-state.R`, run by `.onLoad` in `zzz.R`; `.onUnload` calls registered
    cleanups; the service table `ext_service_set()`/`ext_service_get()`/`ext_service_has()` (services owned by
    built-ins, IC-34) and `setting_get()` (contract IC-09, §7.0-7.1), through which earlier plans reach services
    of later ones.
  - Review amendments (contract §15): `gptr_can_prompt()` (IC-43), `supervise_default()` (IC-60), `as_utf8()`
    applied at every ingress (IC-62), `rscript_path()` (IC-60), `user_home()`, `app_config_dir()`,
    `project_root()` honouring `gptr.project_root`/`GPTR_PROJECT_ROOT` (IC-63), `path_key()` and the
    `write_atomic()` rename fallback (IC-51), `path_class()` classes `control` and `instructions` (IC-54),
    `with_seed_preserved()` and `port_candidates()` (IC-61), the per-session `out` store (IC-71),
    `redactor_set()`/`redact_hook()` (IC-34); `setup.R` redirects `HOME`, `USERPROFILE`, `APPDATA`,
    `LOCALAPPDATA`, `XDG_CONFIG_HOME` and sets `GPTR_PROJECT_ROOT`; `expect_no_copy(in_run_edit =)` (IC-41);
    `local_mock_server()` returns an `offline = TRUE` provider, answers only token paths and gains a `redirect`
    scenario (IC-45, IC-64, IC-71); `helper-arch.R` parses `R/` and holds the kernel SDK allowlist (IC-33);
    `test-lint-rules.R` gains the IC-72 rules and detects `<-` through `getParseData()`."""),
("""  5. `helper-tracemem.R` self-test: `str(big)` is reported as COPY and `big[1] = 0` alone as in place.
  6. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`: 0
     errors, 0 warnings; the CI matrix (incl. Windows, oldrel-4, no-suggests, `LC_ALL=C`) is green.""",
"""  5. `helper-tracemem.R` self-test: `str(big)` is reported as COPY and `big[1] = 0` alone as in place.
  6. `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`: 0
     errors, 0 warnings, no NOTE apart from the maintainer line; the CI matrix (incl. Windows, oldrel-4,
     no-suggests, `LC_ALL=C`, connections-left-open) is green.
  7. Review additions: `R CMD INSTALL` of the package succeeds with a test file collating after `utils-*.R` that
     calls `on_load()` at top level (IC-32); a DESCRIPTION assertion test checks `Authors@R` roles (`cph` for the
     maintainer, `ctb`/`cph` for Mario Zechner), `Copyright`, `URL`, `BugReports`, `Language`, `ps` in Imports
     and no `VignetteBuilder`; `as_utf8("caf\\xc3\\xa9")` keeps the bytes under `LC_ALL=C` while `enc2utf8()` would
     not (IC-62); `lintr::lint_package()` passes on fixtures defining `.DollarNames.gptr_session`,
     `knit_print.gptr_session`, `vec_proxy.gptr_s1` and a closure using `<<-`; `.Random.seed` is unchanged by
     `with_seed_preserved(httpuv::randomPort())` (skip without httpuv); `user_home()` equals `USERPROFILE` in a
     mocked Windows test."""),
# P02
("""  policies and hooks), diagnostics and a generation counter; the 30 kinds of `ext-specs.R` and their validators
  (architecture §11.1 minus `interpreter`, plus `route`; contract IC-02 and §10.2); `ctx` members bound through
  P01's service table (contract IC-09, §7.0); `gptr_spec()` and the 11 exported""",
"""  policies and hooks), diagnostics and a generation counter; the 37 kinds of `ext-specs.R` and their validators
  (architecture §11.1 minus `interpreter`, plus `route`, `preset`, `risk_rule`, `service`, `renderer`,
  `search_source`, `store`, `evaluator`; contract IC-02, IC-34, IC-69 and §10.2); `ctx` members bound lazily through
  P01's service table (contract IC-09, IC-34, §7.0); `gptr_spec()` and the 11 exported"""),
("""  `gptr_check()` conformance for specs and factories; `gptr_api()`; the built-in declaration table filled by
  `on_load(ext_declare_builtin(...))` and loaded in dependency order.""",
"""  `gptr_check()` conformance for specs and factories; `gptr_api()`; the built-in declaration table filled by
  `on_load(ext_declare_builtin(...))` and loaded in dependency order.
- **Review amendments (contract §15).** Overrides are per `(kind, name)`; a whole built-in is disabled only by an
  explicit filter (IC-69); no filter disables `builtin:permissions`, `builtin:plan` or the guards, and filters that
  remove policies or hooks are refused inside a run (IC-53); `ext_load(..., session =)` and session-scoped hooks
  and lazy activation (IC-69); the constructor signatures of IC-35 (adapter validation per transport, provider
  fields `status`, `aliases`, `local`, `offline`, `rate`, router `timeout`, section `parent`, context-block
  `placement = "both"` and `order`); `gptr_agent()` stores raw expressions (IC-34); the `ctx` members of IC-69
  (`set_model`, `add_tools`, `tokens`, `eval`, `describe`) and `ctx$send()` with `source = "extension"` (IC-55);
  the `request_params` event; `gptr_check(tokens =)` (IC-69); context blocks with `authority = "operator"` only from
  rank >= 3 (IC-52)."""),
("""  4. Registering 100 lazy manifests takes under 50 ms (G1 measured 8-16 ms).""",
"""  4. Registering 100 lazy manifests takes under 50 ms (G1 measured 8-16 ms).
  5. Review additions: every §6.8 example of the contract runs; a user `read` override leaves `edit` and the
     `gptr$grep` member working; a factory loaded with `session = <id>` is invisible to another session and removed
     at its shutdown; a `-builtin:permissions` filter from user settings, a call and `gptr_config()` is refused; a
     plugin `service` record replaces a built-in service and disappears with its plugin; an `operator` context block
     registered at rank 1 is refused."""),
]
apply(P, pairs)
