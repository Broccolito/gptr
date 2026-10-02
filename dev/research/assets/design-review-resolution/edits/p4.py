from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
# P08
("""- **Scope.** `gptr-gateway.R` (the classed closure `gptr` with `$`, `[[`, `.DollarNames`, `$<-` refusal and
  `print` methods; dispatch steps 1-5 of architecture §4.1.1 with routes looked up in the registry; return
  visibility; the registration point for routes contributed by later plans); `gptr-capture.R` (base-R capture
  under rules R2-R3, prompt selection, identifier resolution table §4.1.3 including `!!` and `I()`,
  `{identifier}` interpolation); `gptr-sdk.R` (`gptr_step()`, `gptr_wait()`, `gptr_steer()`,
  `gptr_cancel()`, `gptr_on()`, `gptr_return()`, `gptr_prob()`);""",
"""- **Scope.** `gptr-gateway.R` (the classed closure `gptr` with `$`, `[[`, `.DollarNames`, `$<-` refusal and
  `print` methods, `$`/`[[`/`.DollarNames` through the `ns.resolve`/`ns.names` services of P10 (IC-36); dispatch
  steps 1-5 of architecture §4.1.1 with routes looked up in the registry; return visibility; the registration point
  for routes contributed by later plans); `gptr-capture.R` (base-R capture under rules R2-R3, prompt selection,
  identifier resolution table §4.1.3 including `!!` and `I()`, `{identifier}` interpolation); `gptr-sdk.R`
  (`gptr_step()`, `gptr_wait()`, `gptr_steer()`, `gptr_cancel()`, `gptr_on()`, `gptr_return()`; `gptr_prob()` is
  P13's, IC-36);"""),
("""  (contract IC-24); `inst/templates/vignette.Rmd`, `settings.json`, `gitignore`.""",
"""  (contract IC-24); `inst/templates/vignette.Rmd`, `settings.json`, `gitignore`.
- **Review amendments (contract §15).** Plain-symbol dots read through a `get0()` leaf without forcing (IC-41);
  the evaluation-environment precedence and the visibility check for continuations (IC-40); identifier
  normalisation for skills, plugins, extensions and agents (IC-42); namespaced `.opts`, `.opts$images`,
  `.opts$seed`, `.opts$frontend` (IC-44, IC-61, IC-69); route orders (IC-39); mode and filter inheritance for
  every call made during a run (IC-53); router models stored as `router:<name>` and the `router.call` service
  (IC-69); `gptr_can_prompt()` for the human check and questions (IC-43); `gptr_return()` returning `invisible(x)`
  outside a run (IC-48); `gptr_config(.scope = NULL)` (IC-71); `replay_mode()` forcing replay only outside
  testthat (IC-45); trust fingerprints and `project_trust` as a first decision (IC-52, IC-71); the `trust.get`
  and `identifier.resolve` services (IC-33, IC-34); `control`-category run checks in the setup exports (IC-53);
  the egress acknowledgement as an `ask_human`; the `interp` record behind the `args=` header key (IC-45)."""),
("""  4. Copy suite: every gateway row of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded
     dots, alias and if/else models, `$value` reads, print/summary/str of a session, fork, `saveRDS`) is in
     place.""",
"""  4. Copy suite: every gateway row of G3 t5 (top level, pipe, continuation with context, wrapper with forwarded
     dots, alias and if/else models, `$value` reads, print/summary/str of a session, fork, `saveRDS`) is in
     place, and the in-run edit rows of IC-41 (`gptr("x", big)`, `big |> gptr("x")`, `s |> gptr("x", big)` with
     `in_run_edit = TRUE`) report 0 copies."""),
("""  6. **M1 exit** (once P05-P08 are complete): `devtools::check(args = c("--as-cran", "--no-manual"),
     error_on = "warning")` clean; every exported example runs offline on the fake provider.""",
"""  6. Review additions: `f = function(s, d) s |> gptr("filter d", d)` with `s` homed in `globalenv()` either
     evaluates where `d` is visible or fails fast naming `d`; `skills = single_cell` resolves to `single-cell`;
     `gptr_return(x)` outside a run returns `x` invisibly; `gptr_config(mode = manual)` writes the project file when a
     workspace exists; under `_R_CHECK_PACKAGE_NAME_` with `TESTTHAT=true` replay is not forced; a model-code call of
     `gptr_permissions(allow = "r(level<=3)")` during a run is refused with `gptr_error_permission`; `.opts =
     list(panel = list(size = 3))` reaches `ctx$input$opts$panel` when a `panel.size` setting is registered.
  7. **M1 exit** (once P05-P08 are complete): `devtools::check(args = c("--as-cran", "--no-manual"),
     error_on = "warning")` clean; every exported example runs offline on the fake provider (the `gptr_prob()`
     example is P13's, so none needs a later plan; IC-36)."""),
# P09
("""  generic, level-based methods listed in architecture §7.5); `env-history.R` (task-callback log, last 20);
  `env-probe.R` (capability probe for `<r_env>` without loading packages).""",
"""  generic, level-based methods listed in architecture §7.5); `env-history.R` (task-callback log, last 20);
  `env-probe.R` (capability probe for `<r_env>` without loading packages).
- **Review amendments (contract §15).** R8 clears every `withVisible()` result in place (IC-67); plots on
  `pdf(NULL)` when no device is open and no human sees one, the prior device restored; at most
  `gptr.r_max_images` images per result, the rest stored for `gptr$plot(k)`, image tokens in the budget, image
  elision above provider limits (IC-67); `rng_swap()` with hash-derived L'Ecuyer seeds (IC-61); `eval_guard()`
  flags `q`/`quit` in any position (IC-67); describers for packages outside Suggests use slots and base generics
  only (IC-71); `attached` and preloaded `skill_content` blocks with `placement = "both"` (IC-38); the `evaluator`
  record `r` and the `eval.r` and `describe` services (IC-69, IC-34)."""),
("""  3. Copy suite: evaluation at top level, in `globalenv()` from a function, and **in a function-frame home**
     (tool code `n = 1L` and `length(d)` in `f = function(d) gptr(..., d)`) leaves the caller's 40 MB object
     editable in place.""",
"""  3. Copy suite: evaluation at top level, in `globalenv()` from a function, and **in a function-frame home**
     (`eval_r("n = 1L; length(d)", <the frame of f>)` called inside `f = function(d) ...`) leaves the caller's 40 MB
     object editable in place; the rows `L$a`, `(x)`, `get("x")`, `x@slot` and `x[["a"]]` evaluated at top level
     leave it in place (IC-67). The `gptr()` form of the function-frame case is in `test-copy-tools.R` (P10)."""),
("""  5. `env-probe` leaves `loadedNamespaces()` unchanged; `<workspace>` for six objects is at most 600 tokens and
     never forces a promise or an active binding.""",
"""  5. `env-probe` leaves `loadedNamespaces()` unchanged; `<workspace>` for six objects is at most 600 tokens and
     never forces a promise or an active binding.
  6. Review additions: a plotting `r` call under Rscript leaves no `Rplots.pdf` in `getwd()`; a 50-plot loop
     attaches 3 images and lists the rest; `.Random.seed` is identical before and after an evaluation with an agent
     stream; `g = q; g()` is blocked."""),
# P10
("""  glob to PCRE, Pi's `**/` prefix rule); `tool-search.R` (`gptr$grep/find/ls` with raw prefilters, radix
  sorting, early stop, 1,500-token prints).""",
"""  glob to PCRE, Pi's `**/` prefix rule); `tool-search.R` (`gptr$grep/find/ls` with raw prefilters, radix
  sorting, early stop, 1,500-token prints).
- **Review amendments (contract §15).** P10 is the only owner of `gptr$out()` (IC-36); the gateway methods are
  P08's and P10 provides `ns.resolve`, `ns.names` and `search.sources` (IC-36, IC-69); one spec per capability for
  `read`, `edit`, `write`, `grep`, `find`, `ls` with both forms, reserved member names and required plugin
  namespaces (IC-37); `record = FALSE` for `out`, `plot`, `help`, `search`, `describe` (IC-48); the tools'
  `guidelines` for `<rules>` and the `r_session` fragments for helpers and `out` (IC-68); the `r` tool's
  `parameters` as a function giving the four schema variants (IC-68); `gptr$find(sort = "relevance")`,
  `gptr$grep(sort =)` (IC-71); `gptr$plot(which =)` (IC-67); `read` resolves `skill:<name>/<path>` pseudo-paths
  (IC-68); `edit`/`write` apply the `control` and `instructions` path classes (IC-54)."""),
("""  5. Value policy: a 12 MB bound object is held by name, a 200 KB one as a copy, an anonymous value boxed;
     `gptr_return()` outside a run errors; the copy rows for all three stay in place.""",
"""  5. Value policy: a 12 MB bound object is held by name, a 200 KB one as a copy, an anonymous value boxed;
     `gptr_return(x)` outside a run returns `x` invisibly and changes nothing (IC-48); the copy rows for all three
     stay in place, as does tool code `n = 1L` and `length(d)` in `f = function(d) gptr(..., d)` (moved from P09)."""),
("""  6. An edit whose `oldText` matched only through the fuzzy fallback returns the message plus a diff of at most
     400 tokens; an exact edit returns the message only.""",
"""  6. An edit whose `oldText` matched only through the fuzzy fallback returns the message plus a diff of at most
     400 tokens; an exact edit returns the message only.
  7. Review additions: a plugin member with `namespace = "grep"` or without a namespace is refused; `gptr$read` and
     the direct `read` tool come from one spec; `gptr$find("tst", sort = "relevance")` ranks `test.R` first; the
     `r` schema frozen without a document has no `record`/`note`; P10's NS fixture and baseline rows are added to
     `dev/bench/tokens/` (IC-73)."""),
# P11
("""  and its detail view; `builtin:ui`); `tool-ask.R` (trimmed schema, UI mapping, `builtin:ask`).""",
"""  and its detail view; `builtin:ui`); `tool-ask.R` (trimmed schema, UI mapping, `builtin:ask`).
- **Review amendments (contract §15).** Risk rows of category `control` for gptr's own configuration exports and
  options, the risky-package list, level 1 for unlisted functions of non-base packages, additive `risk_rule`
  records (IC-53, IC-54, IC-69); the plan-mode allowlist (IC-54); the `ask_human` tier and the policies'
  non-removability (IC-53); display sanitisation and the full flagged-call list in prompts (IC-53); rules
  remembered "in this project" go to the user-level project file, and a legacy `.gptr/settings.local.json` only
  tightens (IC-52); `gptr_can_prompt()` for UI resolution and the `ask` tool, `ask` declared in non-interactive
  `manual` runs and stopping the run when called (IC-43, IC-68); the pending-plan hand-off rules of IC-56."""),
("""  5. The scripted UI answers `[a]lways`, producing a session rule that covers exactly the flagged calls.""",
"""  5. The scripted UI answers `[a]lways`, producing a session rule that covers exactly the flagged calls.
  6. Review additions: 18 §2.5's blind-spot cases get the new levels (`targets::tar_destroy()` >= 2,
     `usethis::create_package(".")` >= 2) and are denied in plan mode; in `manual` and `plan`, model code calling
     `gptr_permissions(allow =)`, `gptr_trust(".", TRUE)`, `gptr_register(gptr_hook("permission_request", ...))`,
     `options(gptr.critical_guard = FALSE)` or writing `.gptr/extensions/x.R` needs a human (`blocked` without one);
     an ESC or bidi payload in code is escaped in the prompt; a cloned fixture with `settings.local.json` allow
     rules and an AGENTS.md instruction still asks; the pending plan is not handed to a call inside a loop or to a
     call after an intervening `gptr()`; with `jupyter.in_kernel = TRUE` mocked and a mocked `gptr_readline()`, an
     ask is answered."""),
# P12
("""  `.opts$returns` structured output (INFRA-25); wire fixtures under `tests/testthat/fixtures/sse/`; gated live
  tests.""",
"""  `.opts$returns` structured output (INFRA-25); wire fixtures under `tests/testthat/fixtures/sse/`; gated live
  tests.
- **Review amendments (contract §15).** The adapter capability `forced_tool_choice` (`FALSE` for Anthropic 5.x);
  `returns =` through `output_config.format` on Anthropic, else `auto` + instruction + validation; declared
  `request_params` fields; `check_adapter()` fails a list `tool_choice` sent while the capability is `FALSE`
  (IC-69, IC-71)."""),
]
apply(P, pairs)
