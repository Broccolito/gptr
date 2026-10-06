# P09 Evaluator and Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate model-written R code in the live session with everything REQ-23 asks for (output, messages, warnings, errors with a traceback, plots) and describe the workspace compactly, without ever copying a user object.

**Architecture:** Eight "L4 svc" files (architecture section 3.2). `eval-core.R` is the hand-rolled evaluator `eval_r()` of architecture section 6.12 (report 12's `gptr_eval2.R` with the contract's amendments) plus the RNG swap `rng_swap()`; `eval-guard.R`, `eval-plots.R` and `eval-format.R` hold its static guard and `gptr::` shim, plot capture and replay to PNG, and the model-facing text within the token budget. `env-snapshot.R`, `env-describe.R`, `env-history.R` and `env-probe.R` introspect the workspace through leaf functions that return primitives only (snapshots, diffs, budgeted `gptr_describe()` descriptions, the user's top-level expressions, the installed-package probe) and register `builtin:workspace`: the `workspace`, `workspace_changes`, `attached` and `skill_content` context blocks, the `r_env` prompt section, the `evaluator` record `r` and the `eval.r` and `describe` services.

**Tech Stack:** base R (>= 4.2.0) with grDevices, graphics, methods, stats, utils; rlang (`obj_address()`, `env_binding_are_active()`, `env_binding_are_lazy()`); ps (core count and RAM for `<r_env>`); ragg when installed (Suggests); testthat 3e, withr and processx in tests; P01's `expect_no_copy()` for the fresh-process copy suite.

**Spec:** dev/spec/03-architecture.md (sections 2.2, 3.2, 6.4, 6.12, 7.3 `<r_env>`, 7.4, 7.5, 12.2), dev/spec/04-interface-contract.md (sections 1.1, 1.3, 2.1-2.2, 3.1, 4.1, 4.4, 5.8, 6.6 `gptr_describe()`, 7.0, 7.1, 7.6, 7.8 `call_value()`, 7.9, 10.2 kinds 13, 14, 34, 38, 10.3, 10.6 `ctx$eval()`/`ctx$describe()`, 12.2-12.3; section 15: IC-33, IC-34, IC-38, IC-61, IC-62, IC-67, IC-69, IC-71), dev/spec/05-plan-decomposition.md (P09).

**Depends on:** P08 (and through it P01-P07). **Milestone:** M2.

---


## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never the left arrow; `<<-` only for closure state), the native `|>` (never `%>%`), ASCII-only R sources, `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions (messages built by plain concatenation), no `:::` in `R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed global state restored with `on.exit(..., add = TRUE)`, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line the executing harness specifies, if it specifies one (conventions section 10). Plan-specific requirements, with the exact values of the specification:

- Owned files (05 P09): `R/eval-core.R`, `R/eval-plots.R`, `R/eval-guard.R`, `R/eval-format.R`, `R/env-snapshot.R`, `R/env-describe.R`, `R/env-history.R`, `R/env-probe.R`; their tests `tests/testthat/test-eval-core.R`, `test-eval-plots.R`, `test-eval-guard.R`, `test-eval-format.R`, `test-env-snapshot.R`, `test-env-describe.R`, `test-env-history.R`, `test-env-probe.R`; the copy suite `tests/testthat/test-copy-eval.R`; plus `NAMESPACE` and `man/gptr_describe.Rd` through `Rscript --vanilla -e 'devtools::document()'`.
- Layer (03 section 3.2, section 2.2; IC-33): all eight files are "L4 svc". They call L0 helpers, the extension API (`gptr_spec()`, `gptr_context_block()`, `gptr_prompt_section()`, `registry_get()`, `ext_declare_builtin()`), each other, the services of 04 section 7.0 (`skill.body`, `compact.should`) and the kernel SDK only: `session_data()` (read), `session_live()`, `session_home()`, `run_current()`, `call_value()`, `setting_get()`. They never call another L3 function by name (not `gptr_last()`, not `live_all()`).
- The one export (04 section 6.6): `gptr_describe(x, budget = 150L, ...)`, an S3 generic; `budget` "`int(1)` >= 20, estimated tokens (`est_tokens(, "describe")`)"; "Returns a character vector of lines, the first a header `<class> shape, size`, at most `budget` estimated tokens". Built-in methods: `default`, `data.frame`, `data.table`, `matrix`, `list`, `Date`, `POSIXct`, `factor`, `formula`, `lm`, `glm`, `environment`, `function`, `S4` (through `default` with `isS4()`), `dgCMatrix`, `ArrowTabular`, `Dataset`, `DBIConnection`, `Seurat`, `SingleCellExperiment`, `ggplot`. Methods "MUST follow [R4][leaf]: no promise forcing, no I/O (no `dbListTables()`, no `collect()`), no `str()` on the object"; methods for classes of packages outside Suggests "use only base generics, `methods::slot()`/`slotNames()`, `attr()` and `dim()` guarded by `isNamespaceLoaded()`, never `pkg::fun()`" (IC-71). Level-based: "a method may accept `level = 1:4` in `...`".
- Internal signatures (04 section 7.9), exactly: `eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE, max_images = gptr_opt("r_max_images"))`; `rng_swap(state, expr)`; `format_eval_result(res, budget_tokens)` -> `list(text = chr(1), images = list, truncated = lgl(1), out_id, spill)`; `eval_guard(exprs)` -> `list(blocked = chr, reason = chr(1) | NULL)`; `gptr_shim(exprs, envir)`; `plot_png(recorded, width = gptr.plot_width, height = gptr.plot_height, res = gptr.plot_res)`; `env_snapshot(envir, previous = NULL)` -> df `name`, `kind` (`value`, `promise`, `active`), `address`, `class`, `bytes`, `shape`, `fp`; `env_diff(old, new, assigned = character())` -> `list(added, modified, removed)`; `workspace_lines(snapshot, budget = 600L)`; `changes_lines(diff, snapshot, user_ran, budget = 300L)`; `describe_binding(name, envir, budget = 150L)`; `user_expr_log(since = NULL, n = 20L)`; `r_env_probe()` -> `chr(1)`; `builtin_workspace(gptr)`.
- `gptr_eval_result` (04 section 5.8): `structure(list(status, events, n_done, n_total, changes, elapsed, images, assigned, outputs, spill, out_id, interrupted_after), class = "gptr_eval_result")`; `status` in `ok`, `error`, `timeout`, `interrupt`, `blocked`, `parse_error`; `events` ordered `list(type = "source"|"output"|"message"|"warning"|"error"|"interrupt"|"plot", ...)`, "`plot` events carry the PNG path, never the recorded plot"; `changes` = `list(wd = chr(2)|NULL, options = chr, envvars = chr, attached = chr, loaded = chr, devices = list(from, to))` "names only"; "The value of an evaluation is never kept (R8)".
- Options owned (04 section 3.1): `gptr.r_timeout` (`3600`, "seconds for `r` when no human is present"), `gptr.r_output_tokens` (`4000L`, "`r` result budget (estimated tokens, images included)"), `gptr.r_max_images` (`3L`, "plot images attached per `r` result (IC-67)"), `gptr.plot_width`, `gptr.plot_height`, `gptr.plot_res` (`768L`, `512L`, `120L`, "PNG sent to the model"). Read through P01's `gptr_opt()`; their defaults live in P01's `gptr_option_defaults`.
- Evaluator rules (04 section 7.9, IC-67): parse with `srcfilecopy("<gptr>", code)`; "calling handlers created in a frame that does not hold `envir` [R2][R3]"; "per-expression `setTimeLimit(elapsed = timeout, transient = TRUE)` (`timeout = NULL`: none with a human present, else `gptr.r_timeout`)"; "symbols printed with `print(<sym>)` in `envir` and every `withVisible()` result cleared in place (`res[1L] = list(NULL)`)"; plots "on `pdf(NULL)` with the display list enabled when no device is open and no human sees one; the prior device restored" and "replayed to PNG, at most `max_images` attached (the rest kept in the session's out store)"; "stops at the first error"; `q` and `quit` "flagged in any position (a value, a `FUN` argument, `match.fun`, `get`, `do.call`, `base::`)"; "a literal `[secret:` marker is blocked with the `Sys.getenv()` hint".
- Model text (03 section 6.12, 04 section 7.9): "output, messages, warnings, error + trimmed traceback, `[plot N attached]`, state-change lines (`~ pbmc <Seurat> modified`, `+ markers <data.frame 4,211 x 7>`), a status line, head 40% / tail 60% truncation with the `peter$out(<id>)` notice; halves the budget when the session's context exceeds half the compaction threshold"; later plots "listed as `[plots 4-50 not attached: peter$plot(k)]`" (IC-67).
- RNG (IC-61): `rng_swap()` "saves `get0(".Random.seed", globalenv(), inherits = FALSE)`, assigns the agent's `c(10407L, <6 seeds>)`, evaluates, keeps the advanced vector in the agent's state, then restores the saved value or removes the variable. The six seeds come from 24 bytes of `sha256(<agent id>)` reduced modulo m1 = 4294967087 (three) and m2 = 4294944443 (three), stored as R integers (two's complement), or from an explicit `.opts$seed` hashed with the agent label". gptr never calls `set.seed()`, `RNGkind()`, `sample()` or `runif()`.
- Workspace texts (03 sections 7.4-7.5, 12.2): `<workspace>` "one line per object from `env_snapshot()` (name, class, shape, size), largest first, at most 12 lines and 600 tokens", then `(+ n smaller objects: use ls())`, never forcing promises or active bindings ("reported as `<promise>`/`<active>`"); `<workspace_changes>` "`+ name class shape size`, `~ name`, `- name`, `user ran: <expr>` from the task-callback log, last 20; only when non-empty; ... budget 300"; `<attached>` "`gptr_describe(x, budget = 150)` per context object (at most 300)"; `<skill_content>` "5,000 per skill, 10,000 re-injected after compaction"; `<r_env>` (T1) "about 399 [G4] | 450".
- `builtin:workspace` (04 section 7.9, IC-38): "registers context blocks `workspace` (`first`, order 500), `workspace_changes` (`turn`, order 100), `attached` (`both`, order 600), `skill_content` preloads (`both`, order 700) (IC-38), the prompt section `r_env` (T1, order 900), the `evaluator` record `r` and the `describe` and `eval.r` services"; declared with `on_load(ext_declare_builtin("workspace", builtin_workspace))`; services registered with `on_load(ext_service_set(<name>, <fun>, provided_by = "P09", builtin = "workspace"))` (IC-34). Service signatures (04 section 7.0): `eval.r` = "`eval_r()` through the `evaluator` kind (IC-69)", `describe` = `function(x, budget) chr`.
- Copy safety (03 section 6.4, 04 section 1.3): [R1] no user object held after return; [R2] a caller frame only in an environment binding reset to `NULL`; [R3] no closures, `tryCatch()` or `withCallingHandlers()` in a frame holding the home, never assign to a formal; [R4] introspection through leaf functions returning primitives, never `str()`; [R5] no binding locks; [R6] no `mget()` or list snapshots; [R8] as above. Every row of `test-copy-eval.R` runs in a fresh `Rscript --vanilla` through P01's `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` (skips on CRAN and without `capabilities("profmem")`).
- Conditions (04 section 2.2): argument checks signal `gptr_error_invalid_argument` (fields `arg`, `expected`; never the value). Evaluation failures never throw: they become events and a status.
- Tests use P01's environment (`tests/testthat/setup.R`: `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`, `GPTR_PROJECT_ROOT` a temporary project, redirected user directories) and P01's helpers `expect_no_copy()`, `tracemem_loader()` (the child's load line), `rscript_path()`; processes are started only under `skip_on_cran()`.


## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/eval-guard.R` | create (Task 1) | static guard `eval_guard()` (forbidden and interactive calls, `q`/`quit` in any position, stdin readers, secret markers), static assignment targets `eval_assign_targets()`, the `gptr::` shim `gptr_shim()` |
| `R/env-snapshot.R` | create (Task 2), extend (Task 10) | leaf facts (`env_shape()`, `env_snap_leaf()`, sizes, Seurat facts), `env_snapshot()`, `env_diff()`, `workspace_lines()`, `changes_lines()`; then `builtin:workspace`: the four context blocks, the `r_env` section, the `evaluator` record `r`, the hooks and the `eval.r`/`describe` services |
| `R/env-describe.R` | create (Task 3) | the exported generic `gptr_describe()` and its level-based methods, the budget harness `describe_value()`, `describe_binding()` |
| `R/env-history.R` | create (Task 4) | the task-callback log of the user's top-level expressions (last 20), `user_expr_log()` |
| `R/env-probe.R` | create (Task 5) | `r_env_probe()`: installed fast packages by category, installed but not loadable, missing, without loading namespaces |
| `R/eval-plots.R` | create (Task 6) | plot capture state, `pdf(NULL)` offscreen device, visual-change heuristics, replay to PNG (ragg when installed), `plot_png()` |
| `R/eval-core.R` | create (Task 7), extend (Task 8) | `rng_seeds()`, `rng_swap()`; then `eval_r()`: parse, guard, shim, sink capture, calling handlers, time limits, interrupts, restore, plots, state diff, the `gptr_eval_result` |
| `R/eval-format.R` | create (Task 9) | `format_eval_result()`: event lines, plot notices, state-change and status lines, pressure-halved budget, head/tail truncation |
| `tests/testthat/test-eval-guard.R` | create (Task 1) | guard, targets, shim |
| `tests/testthat/test-env-snapshot.R` | create (Task 2), extend (Task 10) | snapshots, diffs, workspace lines; blocks, factory, services, registry |
| `tests/testthat/test-env-describe.R` | create (Task 3), extend (Task 11) | G2's 98-fact fixture at 150 tokens, levels, promises, IC-71; the NAMESPACE entries |
| `tests/testthat/test-env-history.R` | create (Task 4) | callback, cut, since, registration |
| `tests/testthat/test-env-probe.R` | create (Task 5) | no namespace loaded, fake library, rendering, workers under check |
| `tests/testthat/test-eval-plots.R` | create (Task 6) | PNG blocks, offscreen capture, device mode, heuristics |
| `tests/testthat/test-eval-core.R` | create (Task 7), extend (Task 8) | RNG swap; report 12's torture cases, plots, shim, validation |
| `tests/testthat/test-eval-format.R` | create (Task 9) | text layout, truncation, image tokens, pressure |
| `tests/testthat/test-copy-eval.R` | create (Task 2), extend (Tasks 3, 8, 11) | fresh-process tracemem rows (acceptance 3 and 5) |
| `NAMESPACE`, `man/gptr_describe.Rd` | generated (Task 11) | `Rscript --vanilla -e 'devtools::document()'`: `export(gptr_describe)` and 20 `S3method(gptr_describe, <class>)` lines |

Tasks:

1. The static guard, assignment targets and the `gptr::` shim (`eval-guard.R`)
2. Workspace snapshots, diffs and workspace lines (`env-snapshot.R`)
3. `gptr_describe()` and the level-based describers (`env-describe.R`)
4. The user-expression log (`env-history.R`)
5. The `<r_env>` capability probe (`env-probe.R`)
6. Plot capture and replay to PNG (`eval-plots.R`)
7. Agent RNG streams: `rng_swap()` (`eval-core.R`)
8. The evaluator `eval_r()` (`eval-core.R`)
9. The model-facing text: `format_eval_result()` (`eval-format.R`)
10. `builtin:workspace`: context blocks, `r_env`, the evaluator record and the services (`env-snapshot.R`)
11. Documentation, lint, layering and plan acceptance

---


### Task 1: The static guard, assignment targets and the `gptr::` shim

**Files:** Create: `R/eval-guard.R`; Test: `tests/testthat/test-eval-guard.R`.

Adapted from report 12 section 5.1 (`.gptr_guard_rules`, `gptr_called_functions()`) with its verification log item 25 (`g = q; g()` was not blocked) and IC-67 (the symbols `q` and `quit` are flagged in any position). The guard walks the parsed code once and never evaluates anything. A local binding never hides a blocked call: R skips non-function bindings when it looks a function up, so `q = 1; q("no")` still calls `base::q()` and ends the user's session. A called name is therefore exempt only when the code defines a function of that name (`menu = function(...) 1`) or an enclosing function binds it (a formal or a local variable); `pkg::name` is always refused; a string passed to `do.call()`, `match.fun()`, `get()` and friends is exempt only for a function the code defines; and `q`/`quit` used as a value are exempt only when the code assigns a variable of that name (`q = quantile(x); q[2]`). `stdin()` calls count as standard-input reads. `eval_assign_targets()` is the static half of the state diff (04 section 5.8 `assigned`: replacement functions, `assign()`, `:=`, `set*()`, `<<-`; architecture section 6.12). `gptr_shim()` rewrites `peter(...)`, `peter$member(...)` and `gptr_return(...)` to `gptr::` when the symbols are not visible from the evaluation environment (for example a `new.env(parent = baseenv())` home), binding nothing there; the caller records the code the model sent, so recorded code keeps `peter$grep("x")` (P10 acceptance 4). The left arrow is spelled `paste0("<", "-")`, as P01's `helper-arch.R` does, so the sources and this plan stay free of the literal.

**Interfaces:**
- Consumes (P01, 04 section 7.1): `` `%||%` `` (`aaa-state.R`).
- Produces (04 section 7.9): `eval_guard(exprs)` -> `list(blocked = chr, reason = chr(1) | NULL)` (`blocked`: refused function names, `"stdin"`, `[secret:NAME]` markers; `reason`: the model-facing text starting `Not run: `); `gptr_shim(exprs, envir)` -> the expression vector with its `srcref` attribute kept; `eval_assign_targets(exprs)` -> chr (used by Task 8 for `gptr_eval_result$assigned`).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-eval-guard.R`:

```r
guard = function(code) eval_guard(parse(text = code, keep.source = FALSE))
arrow = paste0("<", "-")

test_that("session-ending and interactive calls are blocked before evaluation", {
  expect_equal(guard("q('no')")$blocked, "q")
  expect_equal(guard("quit(save = 'no')")$blocked, "quit")
  expect_equal(guard("x = readline('name? ')")$blocked, "readline")
  expect_equal(guard("menu(c('a', 'b'))")$blocked, "menu")
  expect_equal(guard("browser()")$blocked, "browser")
  expect_equal(guard("base::q()")$blocked, "q")
  expect_equal(guard("utils::edit(x)")$blocked, "edit")
  expect_match(guard("q()")$reason, "^Not run: the code calls or refers to q\\(\\)")
  expect_null(guard("x = 1; mean(1:3)")$reason)
  expect_equal(guard("x = 1; mean(1:3)")$blocked, character())
})

test_that("q and quit are flagged in any value position (IC-67)", {
  expect_equal(guard("g = q; g()")$blocked, "q")
  expect_equal(guard("f = quit; f()")$blocked, "quit")
  expect_equal(guard("do.call('q', list())")$blocked, "q")
  expect_equal(guard("match.fun('quit')()")$blocked, "quit")
  expect_equal(guard("get('q')()")$blocked, "q")
  expect_equal(guard("lapply(1, q)")$blocked, "q")
  expect_equal(guard("h = base::quit")$blocked, "quit")
})

test_that("local variables named q, member names and formulas are not flagged", {
  expect_equal(guard("q = quantile(1:10); q[2]")$blocked, character())
  expect_equal(guard("f = function(q) q + 1; f(2)")$blocked, character())
  expect_equal(guard("x = list(q = 1); x$q")$blocked, character())
  expect_equal(guard("peter$edit('a.R', list())")$blocked, character())
  expect_equal(guard("fit = lm(y ~ q, data = d)")$blocked, character())
  expect_equal(guard("e = quote(q())")$blocked, character())
})

test_that("a local binding never hides a call of q, quit or another blocked function", {
  expect_equal(guard("q = 1; q('no')")$blocked, "q")
  expect_equal(guard("q = 1; base::q('no')")$blocked, "q")
  expect_equal(guard("quit = base::quit; quit()")$blocked, "quit")
  expect_equal(guard("q = 1; do.call('q', list('no'))")$blocked, "q")
  expect_equal(guard("f = function(q) 1; q('no')")$blocked, "q")
  expect_equal(guard("edit = 1; edit(x)")$blocked, "edit")
  expect_equal(guard("x = readLines(stdin())")$blocked, "stdin")
})

test_that("functions the code defines and names local to a function are not flagged", {
  expect_equal(guard("menu = function(...) 1; menu()")$blocked, character())
  expect_equal(guard("menu = function(...) 1; do.call('menu', list())")$blocked, character())
  expect_equal(guard("f = function() { q = 2; q + 1 }; f()")$blocked, character())
  expect_equal(guard("x = function(quit) quit; x(2)")$blocked, character())
  expect_equal(guard("for (q in 1:3) print(q)")$blocked, character())
})

test_that("stdin readers and secret markers are refused with a hint", {
  expect_equal(guard("x = readLines('stdin')")$blocked, "stdin")
  expect_equal(guard("x = scan()")$blocked, "stdin")
  expect_equal(guard("x = scan(text = '1 2')")$blocked, character())
  g = guard("key = '[secret:OPENAI_API_KEY]'")
  expect_equal(g$blocked, "[secret:OPENAI_API_KEY]")
  expect_match(g$reason, "Sys.getenv(\"OPENAI_API_KEY\")", fixed = TRUE)
})

test_that("eval_assign_targets finds assignments, replacements, assign(), := and set*()", {
  at = function(code) sort(eval_assign_targets(parse(text = code, keep.source = FALSE)))
  expect_equal(at(sprintf("x = 1; y %s 2; 3 -> z", arrow)), c("x", "y", "z"))
  expect_equal(at("x[1] = 0; names(v)[2] = 'a'; l$a$b = 1; attr(m, 'k') = 2"),
               c("l", "m", "v", "x"))
  expect_equal(at("assign('w', 1); dt[, a := 1]; data.table::setkey(dt2, id)"),
               c("dt", "dt2", "w"))
  expect_equal(at("f = function() { inner = 1; outer <<- 2 }"), c("f", "outer"))
  expect_equal(at("for (i in 1:3) total = i"), c("i", "total"))
})

test_that("gptr_shim rewrites peter calls only when peter is not visible", {
  ex = parse(text = "r = peter('task', d); peter$grep('x'); gptr_return(r)", keep.source = FALSE)
  hidden = new.env(parent = baseenv())
  out = gptr_shim(ex, hidden)
  expect_equal(deparse(out[[1]]), "r = gptr::peter(\"task\", d)")
  expect_equal(deparse(out[[2]]), "gptr::peter$grep(\"x\")")
  expect_equal(deparse(out[[3]]), "gptr::gptr_return(r)")
  expect_equal(ls(hidden), character())
  visible = new.env(parent = baseenv())
  visible$peter = function(...) NULL
  visible$gptr_return = function(x) x
  expect_identical(gptr_shim(ex, visible), ex)
})

test_that("gptr_shim keeps the source references of the expression vector", {
  ex = parse(text = "x = 1\npeter('a')", keep.source = TRUE)
  out = gptr_shim(ex, new.env(parent = baseenv()))
  expect_false(is.null(attr(out, "srcref")))
  expect_equal(as.character(attr(out, "srcref")[[2]]), "peter('a')")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-guard")'
```

Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "eval_guard"` (or `"eval_assign_targets"`, `"gptr_shim"`).

- [ ] **Step 3: Write the implementation**

Create `R/eval-guard.R`:

```r
# eval-guard.R -- static guard, interactive traps, assignment targets and the gptr:: shim (P09).
#
# Adapted from report 12 section 5.1 (`.gptr_guard_rules`, `gptr_called_functions()`) with the
# fixes of its verification log (item 25: `g = q; g()` was not blocked) and IC-67: the symbols
# q and quit are flagged in any position (a value, a FUN argument, match.fun(), get(),
# do.call(), base::). A local binding never hides a blocked call: R skips non-function bindings
# when it looks up a function, so `q = 1; q("no")` still calls base::q(); only a function the
# code defines itself (`menu = function(...) ...`) or a formal or local variable of an enclosing
# function shadows a blocked name, and `pkg::name` is always refused. Standard-input readers are
# detected by argument, and a literal `[secret:NAME]` marker is refused with the Sys.getenv()
# hint (architecture section 6.5). The guard is advisory, not a sandbox: eval(parse(text = ...))
# evades it (P11's classifier and the permission gate handle risk).

#' Functions that end, pause or hang the user's R session: never evaluated
#' @noRd
eval_guard_blocked = c(
  "q", "quit", "browser", "debug", "debugonce", "undebug", "recover", "readline", "menu",
  "select.list", "file.choose", "askYesNo", "fix", "edit", "de", "data.entry", "dataentry",
  "locator", "identify", "setTimeLimit", "setSessionTimeLimit", "closeAllConnections",
  ".Internal", ".Primitive"
)

#' Assignment operators (the left arrow is spelled without its literal, as in helper-arch.R)
#' @noRd
eval_guard_assign_ops = c("=", paste0("<", "-"), "<<-")

#' Calls whose string arguments name functions
#' @noRd
eval_guard_indirect = c(
  "do.call", "match.fun", "get", "get0", "getExportedValue", "lapply", "sapply", "vapply",
  "Map", "mapply", "Reduce", "Filter", "Find", "Position", "apply", "tapply", "outer", "Recall"
)

#' Is `x` a `pkg::name` or `pkg:::name` call?
#' @noRd
eval_guard_is_ns = function(x) {
  is.call(x) && length(x) == 3L && is.symbol(x[[1L]]) &&
    as.character(x[[1L]]) %in% c("::", ":::") && is.symbol(x[[3L]])
}

#' Function name of a call head: `f`, `pkg::f` or `pkg:::f`; "" otherwise
#' @noRd
eval_guard_head_name = function(head) {
  if (is.symbol(head)) return(as.character(head))
  if (eval_guard_is_ns(head)) as.character(head[[3L]]) else ""
}

#' Does a call read standard input (readLines("stdin"), stdin(), scan() without text, ...)?
#' @noRd
eval_guard_reads_stdin = function(fname, e) {
  if (identical(fname, "stdin")) return(TRUE)
  readers = c("readLines", "readline", "file", "scan", "source", "read.table", "read.csv")
  if (fname %in% readers && length(e) >= 2L && identical(e[[2L]], "stdin")) return(TRUE)
  if (!identical(fname, "scan")) return(FALSE)
  args = as.list(e)[-1L]
  arg_names = names(args) %||% rep("", length(args))
  if ("text" %in% arg_names) return(FALSE)
  file_arg = ""
  if ("file" %in% arg_names) {
    file_arg = args[["file"]]
  } else if (length(args) && !nzchar(arg_names[1L])) {
    file_arg = args[[1L]]
  }
  identical(file_arg, "") || identical(file_arg, "stdin")
}

#' Names a function body binds (assignment roots and `for` variables), nested functions excluded
#' @noRd
eval_guard_fun_locals = function(x) {
  if (!is.call(x)) return(character())
  head = x[[1L]]
  if (identical(head, as.name("function"))) return(character())
  out = character()
  if (is.symbol(head) && as.character(head) %in% eval_guard_assign_ops && length(x) == 3L) {
    out = eval_guard_target_root(x[[2L]])
  }
  if (identical(head, as.name("for")) && is.symbol(x[[2L]])) out = as.character(x[[2L]])
  for (i in seq_along(x)[-1L]) {
    el = x[[i]]
    if (!missing(el)) out = c(out, eval_guard_fun_locals(el))
  }
  out
}

#' Names the code binds to a function it defines itself (`name = function(...) ...` at top level)
#' @noRd
eval_guard_fun_defs = function(exprs) {
  out = character()
  for (i in seq_along(exprs)) {
    e = exprs[[i]]
    while (eval_guard_head_name(if (is.call(e)) e[[1L]] else NULL) %in% eval_guard_assign_ops) {
      if (length(e) != 3L) break
      rhs = e[[3L]]
      is_fun = is.call(rhs) && identical(rhs[[1L]], as.name("function"))
      if (is.symbol(e[[2L]]) && is_fun) out = c(out, as.character(e[[2L]]))
      e = rhs
    }
  }
  unique(out)
}

#' Walk parsed code collecting called names, `pkg::name` references, function-name strings,
#' q/quit values, secret markers and stdin readers; `scope` holds the formals and local
#' variables of the enclosing functions
#' @noRd
eval_guard_walk = function(e, acc, scope = character()) {
  if (is.character(e)) {
    hit = regmatches(e, gregexpr("\\[secret:[A-Za-z0-9_.-]+\\]", e))
    acc$secrets = c(acc$secrets, unlist(hit))
    return(invisible())
  }
  if (is.symbol(e)) {
    nm = as.character(e)
    if (nm %in% c("q", "quit") && !(nm %in% scope)) acc$values = c(acc$values, nm)
    return(invisible())
  }
  if (!is.call(e)) return(invisible())
  head = e[[1L]]
  fname = ""
  if (is.symbol(head)) {
    fname = as.character(head)
    if (!(fname %in% scope)) acc$called = c(acc$called, fname)
  } else if (eval_guard_is_ns(head)) {
    acc$ns = c(acc$ns, as.character(head[[3L]]))
  } else {
    eval_guard_walk(head, acc, scope)
  }
  if (fname %in% c("~", "quote", "bquote", "expression")) return(invisible())
  if (identical(fname, "function")) {
    inner = c(scope, names(e[[2L]]), eval_guard_fun_locals(e[[3L]]))
    fm = e[[2L]]
    for (j in seq_along(fm)) {
      d = fm[[j]]
      if (!missing(d)) eval_guard_walk(d, acc, inner)
    }
    eval_guard_walk(e[[3L]], acc, inner)
    return(invisible())
  }
  if (fname %in% c("::", ":::")) {
    if (length(e) == 3L && is.symbol(e[[3L]])) acc$ns = c(acc$ns, as.character(e[[3L]]))
    return(invisible())
  }
  if (fname %in% c("$", "@")) {
    eval_guard_walk(e[[2L]], acc, scope)
    return(invisible())
  }
  if (eval_guard_reads_stdin(fname, e)) acc$stdin = TRUE
  indirect = fname %in% eval_guard_indirect
  start = if (fname %in% eval_guard_assign_ops && is.symbol(e[[2L]])) 3L else 2L
  for (i in seq_along(e)) {
    if (i < start) next
    el = e[[i]]
    if (missing(el)) next
    if (indirect && is.character(el) && length(el) == 1L) acc$strings = c(acc$strings, el)
    eval_guard_walk(el, acc, scope)
  }
  invisible()
}

#' Static guard over parsed code (04 section 7.9)
#'
#' A blocked name is refused when it is called (unless the code defines a function of that name
#' or an enclosing function binds it), named through `pkg::` (always), passed as a string to
#' do.call(), match.fun(), get() and friends (unless the code defines it), or, for q and quit,
#' used as a value (unless the code assigns a variable of that name).
#' @param exprs An expression vector (from parse()).
#' @return list(blocked = chr, reason = chr(1) or NULL). `blocked` holds the refused function
#'   names, `"stdin"` and `[secret:NAME]` markers; `reason` is the model-facing text.
#' @noRd
eval_guard = function(exprs) {
  acc = new.env(parent = emptyenv())
  acc$called = character()
  acc$ns = character()
  acc$strings = character()
  acc$values = character()
  acc$secrets = character()
  acc$stdin = FALSE
  for (i in seq_along(exprs)) eval_guard_walk(exprs[[i]], acc)
  funs = eval_guard_fun_defs(exprs)
  vars = eval_assign_targets(exprs)
  hits = c(setdiff(acc$called, funs), acc$ns, setdiff(acc$strings, funs),
           setdiff(acc$values, vars))
  fns = intersect(unique(hits), eval_guard_blocked)
  secrets = unique(acc$secrets)
  reasons = character()
  if (length(fns)) {
    reasons = c(reasons, paste0(
      "Not run: the code calls or refers to ", paste0(fns, "()", collapse = ", "),
      ", which would end, pause or hang the user's R session. Nothing was evaluated. ",
      "Use the ask tool to talk to the user."
    ))
  }
  if (acc$stdin) {
    reasons = c(reasons, paste(
      "Not run: the code reads standard input, which would hang the user's R session.",
      "Nothing was evaluated."
    ))
  }
  if (length(secrets)) {
    nm = sub("^\\[secret:(.*)\\]$", "\\1", secrets)
    reasons = c(reasons, paste0(
      "Not run: the code contains the marker ", paste(secrets, collapse = ", "),
      ". Read the value with ", paste0("Sys.getenv(\"", nm, "\")", collapse = ", "),
      " instead. Nothing was evaluated."
    ))
  }
  list(
    blocked = c(fns, if (acc$stdin) "stdin", secrets),
    reason = if (length(reasons)) paste(reasons, collapse = "\n") else NULL
  )
}

#' Root symbol of an assignment target: `x` from `x`, `x[1]`, `names(x)`, `x$a$b`, `attr(x, "k")`
#' @noRd
eval_guard_target_root = function(x) {
  while (is.call(x) && length(x) >= 2L) x = x[[2L]]
  if (is.symbol(x)) return(as.character(x))
  if (is.character(x) && length(x) == 1L) return(x)
  NULL
}

#' Does a `[` call contain a data.table `:=`?
#' @noRd
eval_guard_has_walrus = function(e) {
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && is.call(el) && identical(el[[1L]], as.name(":="))) return(TRUE)
  }
  FALSE
}

#' data.table functions that modify their first argument by reference
#' @noRd
eval_guard_set_funs = c(
  "set", "setnames", "setkey", "setkeyv", "setorder", "setorderv", "setattr", "setDT",
  "setDF", "setcolorder", "setindex", "setindexv"
)

#' Collect the assignment targets of one expression into acc$out
#' @noRd
eval_guard_targets_walk = function(e, acc, in_fun = FALSE) {
  if (!is.call(e)) return(invisible())
  fname = eval_guard_head_name(e[[1L]])
  target = NULL
  if (fname %in% eval_guard_assign_ops && length(e) == 3L) {
    if (!in_fun || identical(fname, "<<-")) target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "assign") && length(e) >= 2L) {
    if (is.character(e[[2L]])) target = e[[2L]]
  } else if (!in_fun && fname %in% eval_guard_set_funs && length(e) >= 2L) {
    target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "[") && length(e) >= 3L && eval_guard_has_walrus(e)) {
    target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "for") && is.symbol(e[[2L]])) {
    target = as.character(e[[2L]])
  }
  if (!is.null(target)) acc$out = c(acc$out, target)
  if (identical(fname, "function")) {
    if (length(e) >= 3L) eval_guard_targets_walk(e[[3L]], acc, in_fun = TRUE)
    return(invisible())
  }
  for (i in seq_along(e)) {
    el = e[[i]]
    if (!missing(el) && is.call(el)) eval_guard_targets_walk(el, acc, in_fun)
  }
  invisible()
}

#' Static assignment targets of parsed code (the `assigned` field of gptr_eval_result)
#'
#' `=`, the left arrow, `<<-` (inside function bodies only `<<-`), `assign("name", ...)`,
#' replacement calls (their root symbol), data.table `:=` and `set*()` calls, `for` variables.
#' @param exprs An expression vector.
#' @return Character vector of names, first occurrence order.
#' @noRd
eval_assign_targets = function(exprs) {
  acc = new.env(parent = emptyenv())
  acc$out = character()
  for (i in seq_along(exprs)) eval_guard_targets_walk(exprs[[i]], acc)
  unique(acc$out)
}

#' Rewrite one expression for gptr_shim()
#' @noRd
eval_guard_shim_rewrite = function(e, need_g, need_r) {
  if (!is.call(e)) return(e)
  head = e[[1L]]
  if (is.symbol(head)) {
    nm = as.character(head)
    if (need_g && identical(nm, "peter")) e[[1L]] = quote(gptr::peter)
    if (need_r && identical(nm, "gptr_return")) e[[1L]] = quote(gptr::gptr_return)
    if (need_g && nm %in% c("$", "[[") && length(e) >= 2L && identical(e[[2L]], quote(peter))) {
      e[[2L]] = quote(gptr::peter)
    }
  } else {
    e[[1L]] = eval_guard_shim_rewrite(head, need_g, need_r)
  }
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && is.call(el)) e[[i]] = eval_guard_shim_rewrite(el, need_g, need_r)
  }
  e
}

#' The rewrite loop, in a frame that does not bind the evaluation environment
#' @noRd
eval_guard_shim_all = function(exprs, need_g, need_r) {
  for (i in seq_along(exprs)) exprs[[i]] = eval_guard_shim_rewrite(exprs[[i]], need_g, need_r)
  exprs
}

#' Reach peter() and gptr_return() through gptr:: when they are not visible from `envir`
#'
#' Rewrites calls headed by `peter`, `peter$member(...)`, `peter[["member"]](...)` and
#' `gptr_return` to `gptr::` when the symbol is not visible from `envir` (for example a
#' `new.env(parent = baseenv())` home, or a session where gptr is loaded but not attached).
#' Binds nothing in `envir`; `exists()` never forces a promise. The caller records the code as
#' the model sent it, so recorded code keeps the original text (04 section 7.9).
#' @param exprs An expression vector (from parse()).
#' @param envir The evaluation environment.
#' @return The expression vector, rewritten where needed; attributes (srcref) are kept.
#' @noRd
gptr_shim = function(exprs, envir) {
  need_g = !exists("peter", envir = envir)
  need_r = !exists("gptr_return", envir = envir)
  if (!need_g && !need_r) return(exprs)
  eval_guard_shim_all(exprs, need_g, need_r)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-guard")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/eval-guard.R tests/testthat/test-eval-guard.R
git commit -m "feat(eval): add the static guard, assignment targets and the gptr:: shim"
```


### Task 2: Workspace snapshots, diffs and workspace lines

**Files:** Create: `R/env-snapshot.R`, `tests/testthat/test-copy-eval.R`; Test: `tests/testthat/test-env-snapshot.R`.

Adapted from report 12 section 5.2 (`gptr_introspect.R`: leaves, non-forcing detection with `rlang::env_binding_are_active()`/`env_binding_are_lazy()`, address-keyed sizes) and its verification log items 14-15, 17 and 19 (ALTREP `1:1e9` is 680 bytes, not the 3.7 GB `object.size()` claims), with the G3 fact-check fix: a function-frame home is held only in a box binding that is reset on exit, and the per-binding loop lives in a frame that never binds the home. `fingerprint()` is P01's (report 21 section 2.9). Helpers carry the `env_` prefix so no other plan's names collide (P01's `test-arch-layers.R` requires one home per function). The copy suite starts here with the two snapshot rows of acceptance 5; Tasks 3, 8 and 11 add the rest. A binding whose methods fail (a `length()` method that errors, such as a reticulate Python object without a length) is listed with its class and shape `?` (`env_snap_facts()`), so one odd object cannot make every snapshot, and with it every `r` call and the `<workspace>` block, fail.

The measured scratch runs behind this task (fresh `Rscript --vanilla` per row): snapshot of `globalenv()` and of a function frame holding a 40 MB vector, 0 copies each; the prototype variants with a `for` loop in the frame that binds the home, or a positional `ls(envir)`, copied once.

**Interfaces:**
- Consumes (P01, 04 section 7.1): `check_env(x, arg, null = FALSE)`, `check_number(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE)`, `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `est_tokens(x, class)`, `fingerprint(x)` [leaf]; test helper `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` (P01 `helper-tracemem.R`).
- Produces (04 section 7.9): `env_snapshot(envir, previous = NULL)` [R4] -> df `name`, `kind`, `address`, `class`, `bytes`, `shape`, `fp` (`.Random.seed` and `.Last.value` excluded); `env_diff(old, new, assigned = character())` -> `list(added, modified, removed)`; `workspace_lines(snapshot, budget = 600L)` -> chr; `changes_lines(diff, snapshot, user_ran, budget = 300L)` -> chr. Private helpers used by Tasks 3, 8 and 10: `env_snapshot_rows(envir, previous = NULL, sizes = TRUE)`, `env_tokens(lines, class = "describe")`, `env_fmt_bytes(b)`, `env_fmt_n(n)`, `env_compact_seq(x)`, `env_seurat_facts(x)`, `env_shape(x)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-env-snapshot.R`:

```r
# An environment for test-only S4 classes; its package name is created without the warning
s4_where = function() {
  e = new.env()
  withCallingHandlers(methods::getPackageName(e),
                      warning = function(w) invokeRestart("muffleWarning"))
  e
}

test_that("env_fmt_bytes and env_fmt_n give the workspace formats", {
  expect_equal(env_fmt_bytes(0), "0 B")
  expect_equal(env_fmt_bytes(3072), "3 KB")
  expect_equal(env_fmt_bytes(1.2 * 1024^2), "1.2 MB")
  expect_equal(env_fmt_bytes(96 * 1024^2), "96 MB")
  expect_equal(env_fmt_bytes(5.1 * 1024^3), "5.1 GB")
  expect_equal(env_fmt_bytes(NA), "")
  expect_equal(env_fmt_n(3012448), "3,012,448")
  expect_equal(env_fmt_n(c(4211L, 7L)), c("4,211", "7"))
})

test_that("env_snapshot lists bindings with facts and never forces promises", {
  e = new.env()
  e$df = data.frame(a = 1:3, b = letters[1:3])
  e$v = c(1.5, 2.5)
  e$f = function(x) x
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  e[[".Random.seed"]] = 1:3
  s = env_snapshot(e)
  expect_named(s, c("name", "kind", "address", "class", "bytes", "shape", "fp"))
  expect_equal(s$name, c("act", "df", "f", "lazy", "v"))
  expect_equal(s$kind, c("active", "value", "value", "promise", "value"))
  expect_equal(s$class[s$name == "df"], "data.frame")
  expect_equal(s$shape[s$name == "df"], "3 x 2")
  expect_equal(s$shape[s$name == "v"], "length 2")
  expect_true(is.na(s$bytes[s$name == "f"]))
  expect_gt(s$bytes[s$name == "df"], 0)
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("a binding whose methods fail is listed with its class and shape \"?\"", {
  e = new.env()
  e$py = structure(list(), class = "p09_nolen")
  registerS3method("length", "p09_nolen", function(x) stop("no len()"),
                   envir = environment(env_snapshot))
  s = env_snapshot(e)
  expect_equal(c(s$class, s$shape), c("p09_nolen", "?"))
  expect_false(is.na(s$address))
})

test_that("env_snapshot reuses sizes from the previous snapshot", {
  e = new.env()
  e$x = 1:10 + 0
  s1 = env_snapshot(e)
  s1$bytes[s1$name == "x"] = 12345
  s2 = env_snapshot(e, previous = s1)
  expect_equal(s2$bytes[s2$name == "x"], 12345)
  expect_error(env_snapshot(e, previous = "no"), class = "gptr_error_invalid_argument")
  expect_error(env_snapshot(list()), class = "gptr_error_invalid_argument")
})

test_that("a compact integer sequence is described without materialising it", {
  e = new.env()
  e$alt = 1:1e9
  t0 = proc.time()[["elapsed"]]
  s = env_snapshot(e)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_equal(s$shape, "length 1,000,000,000 (sequence)")
  expect_true(is.na(s$bytes))
})

test_that("env_diff reports added, modified, removed, assignment targets and forced promises", {
  e = new.env()
  e$a = 1
  e$b = 2
  delayedAssign("p", 42, assign.env = e)
  old = env_snapshot(e)
  e$a = 10
  e$c = 3
  rm("b", envir = e)
  force(e$p)
  new = env_snapshot(e)
  expect_equal(env_diff(old, new), list(added = "c", modified = "a", removed = "b"))
  expect_equal(env_diff(new, new, assigned = c("c", "zz"))$modified, "c")
})

test_that("workspace_lines aligns columns, sorts largest first and caps at 12 lines", {
  snap = data.frame(
    name = c("pbmc", "qc_tbl", "genes", "markers", "meta", "cfg"),
    kind = "value", address = NA_character_,
    class = c("Seurat", "data.table", "character", "data.frame", "data.frame", "list"),
    bytes = c(5.1 * 1024^3, 96 * 1024^2, 2.1 * 1024^2, 1.2 * 1024^2, 3 * 1024, 2 * 1024),
    shape = c("3,012,448 cells x 33,538 features", "3,012,448 x 5", "length 33,538",
              "4,211 x 7", "12 x 4", "length 6"),
    fp = NA_character_, stringsAsFactors = FALSE
  )
  expect_equal(workspace_lines(snap[c(3, 1, 6, 2, 5, 4), ]), c(
    "pbmc     Seurat      3,012,448 cells x 33,538 features  5.1 GB",
    "qc_tbl   data.table  3,012,448 x 5  96 MB",
    "genes    character   length 33,538  2.1 MB",
    "markers  data.frame  4,211 x 7  1.2 MB",
    "meta     data.frame  12 x 4  3 KB",
    "cfg      list        length 6  2 KB"
  ))
  e = new.env()
  for (i in 1:30) assign(sprintf("obj%02d", i), seq_len(i * 100) + 0, envir = e)
  lines = workspace_lines(env_snapshot(e))
  expect_length(lines, 13L)
  expect_equal(lines[13], "(+ 18 smaller objects: use ls())")
  expect_match(lines[1], "^obj30 ")
  tight = workspace_lines(env_snapshot(e), budget = 40L)
  expect_lt(length(tight), 13L)
  expect_match(tight[length(tight)], "smaller objects: use ls\\(\\)")
})

test_that("six objects cost at most 600 tokens and promises stay unforced", {
  e = new.env()
  e$a = mtcars
  e$b = iris
  e$c = letters
  e$d = list(x = 1, y = "z")
  e$m = matrix(0, 10, 10)
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  lines = workspace_lines(env_snapshot(e))
  expect_lte(env_tokens(lines), 600)
  expect_true(any(grepl("^lazy +<promise>$", lines)))
  expect_true(any(grepl("^act +<active>$", lines)))
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("changes_lines renders the workspace_changes grammar within budget", {
  snap = data.frame(name = c("markers", "pbmc"), kind = "value", address = NA_character_,
                    class = c("data.frame", "Seurat"), bytes = c(1.2 * 1024^2, NA),
                    shape = c("4,211 x 7", "3,000 cells x 200 features"), fp = NA_character_,
                    stringsAsFactors = FALSE)
  d = list(added = "markers", modified = "pbmc", removed = "old")
  expect_equal(changes_lines(d, snap, user_ran = "pbmc = subset(pbmc)"), c(
    "+ markers data.frame 4,211 x 7 1.2 MB", "~ pbmc", "- old", "user ran: pbmc = subset(pbmc)"
  ))
  none = list(added = character(), modified = character(), removed = character())
  expect_equal(changes_lines(none, snap, character()), character())
  many = list(added = character(), modified = sprintf("object_%03d", 1:200),
              removed = character())
  out = changes_lines(many, snap, character(), budget = 50L)
  expect_match(out[length(out)], "^\\(\\+ [0-9]+ more changes\\)$")
  expect_lte(env_tokens(out), 50)
})

test_that("Seurat shapes come from attributes only", {
  e = s4_where()
  methods::setClass("Assay5", methods::representation(features = "matrix", layers = "list"),
                    where = e)
  methods::setClass(
    "Seurat",
    methods::representation(assays = "list", meta.data = "data.frame",
                            active.assay = "character", active.ident = "factor",
                            reductions = "list"),
    where = e
  )
  withr::defer({
    methods::removeClass("Seurat", where = e)
    methods::removeClass("Assay5", where = e)
  })
  a = methods::new(methods::getClass("Assay5", where = e),
                   features = matrix(TRUE, 2000, 1), layers = list())
  s = methods::new(methods::getClass("Seurat", where = e), assays = list(RNA = a),
                   meta.data = data.frame(nCount = 1:300, row.names = paste0("c", 1:300)),
                   active.assay = "RNA", active.ident = factor(c("0", "1")),
                   reductions = list(pca = matrix(0, 300, 2)))
  expect_equal(env_shape(s), "300 cells x 2,000 features")
  f = env_seurat_facts(s)
  expect_equal(f$assays, "RNA")
  expect_equal(f$reductions, "pca")
  expect_equal(f$meta_cols, "nCount")
})
```

Create `tests/testthat/test-copy-eval.R`:

```r
# Copy-safety rows of the evaluator and the workspace introspection (architecture section 6.4,
# rules R1-R8; IC-67). Each row runs in a fresh Rscript through P01's expect_no_copy(): the
# user's next in-place edit after the action must not copy the 40 MB object. The child loads
# gptr without exporting internals, so internal functions are fetched from the namespace. The
# peter() form of the function-frame case is P10's (test-copy-tools.R).

ns_get = function(name) sprintf("%s = get('%s', envir = asNamespace('gptr'))", name, name)
with_ev = function(setup) paste(setup, ns_get("eval_r"), sep = "; ")

test_that("snapshots of globalenv and of a function frame leave the object in place (R4)", {
  setup = paste("big = runif(5e6)", ns_get("env_snapshot"), ns_get("workspace_lines"),
                sep = "; ")
  expect_no_copy(setup, "invisible(workspace_lines(env_snapshot(globalenv())))",
                 label = "workspace lines of globalenv")
  expect_no_copy(
    paste("big = runif(5e6)", ns_get("env_snapshot"), sep = "; "),
    "f = function(d) { force(d); s = env_snapshot(environment()); invisible(NULL) }; f(big)",
    label = "snapshot of a function frame"
  )
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-snapshot|copy-eval")'
```

Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 0 ]`: the ten tests of `test-env-snapshot.R` error with `could not find function` (`env_fmt_bytes`, `env_snapshot`, `workspace_lines`, `changes_lines`, `env_shape`), and both copy rows fail with `the script did not finish` (the child cannot find `env_snapshot`).

- [ ] **Step 3: Write the implementation**

Create `R/env-snapshot.R`:

```r
# env-snapshot.R -- copy-safe workspace snapshots, diffs and workspace lines (P09).
#
# Copy safety (architecture section 6.4, rules R1, R4, R6; report 12 section 2.C2 and its
# verification log items 14-15): only the leaf functions below bind a user object. Leaves call
# primitives and thin wrappers (typeof, inherits, attr, .subset, utils::object.size,
# rlang::obj_address, fingerprint()) and return fresh facts. Loops live in frames that address
# objects by name (get(name, envir) passed straight into a leaf). No closure, tryCatch() or list
# ever holds a user object, and a function-frame home is held only in a box binding that is
# reset on exit (verified with fresh-process tracemem runs, see test-copy-eval.R).

#' Format a byte count for model-facing text ("3 KB", "1.2 MB", "5.1 GB")
#' @noRd
env_fmt_bytes = function(b) {
  if (is.null(b) || length(b) != 1L || is.na(b)) return("")
  units = c("B", "KB", "MB", "GB", "TB")
  i = max(1L, min(length(units), floor(log(max(b, 1), 1024)) + 1L))
  v = b / 1024^(i - 1L)
  txt = if (i == 1L || v >= 10) sprintf("%.0f", v) else sub("\\.0$", "", sprintf("%.1f", v))
  paste(txt, units[i])
}

#' Format counts with thousands separators
#' @noRd
env_fmt_n = function(n) {
  format(n, big.mark = ",", scientific = FALSE, trim = TRUE)
}

#' Estimated tokens of description lines (content class "describe", G2 section 3.1)
#' @noRd
env_tokens = function(lines, class = "describe") {
  if (!length(lines)) return(0)
  est_tokens(paste(lines, collapse = "\n"), class)
}

#' Is x a compact-looking integer sequence (ALTREP 1:n)? (a leaf)
#'
#' Reads three elements through .subset(), which never materialises a compact sequence.
#' @noRd
env_compact_seq = function(x) {
  if (!is.integer(x) || !is.null(attributes(x))) return(FALSE)
  n = length(x)
  if (n < 1e6) return(FALSE)
  e = .subset(x, c(1L, 2L, n))
  !anyNA(e) && e[2L] - e[1L] == 1L && as.numeric(e[3L]) - e[1L] == n - 1
}

#' Facts of a Seurat object through attributes only (a leaf)
#'
#' SeuratObject is not in Suggests: attr(), .subset2() and primitives only, never
#' SeuratObject:: (IC-71). Handles v5 Assay5 (a `features` LogMap) and v3 Assay (a `data`
#' dgCMatrix).
#' @noRd
env_seurat_facts = function(x) {
  md = attr(x, "meta.data")
  assays = attr(x, "assays")
  active = attr(x, "active.assay")
  a = NULL
  if (length(assays)) {
    a = if (length(active) == 1L && active %in% names(assays)) {
      .subset2(assays, active)
    } else {
      .subset2(assays, 1L)
    }
  }
  feats = NA_real_
  if (!is.null(a)) {
    fd = attr(attr(a, "features"), "dim")
    dd = attr(attr(a, "data"), "Dim")
    if (length(fd)) feats = fd[1L] else if (length(dd)) feats = dd[1L]
  }
  idents = attr(x, "active.ident")
  list(
    cells = if (is.null(md)) NA_real_ else .row_names_info(md, 2L), features = feats,
    assays = names(assays), active = active, reductions = names(attr(x, "reductions")),
    meta_cols = names(md), meta_p = length(md), idents = length(attr(idents, "levels"))
  )
}

#' Shape text: "a x b", "n x p", "length n", "<c> cells x <f> features" (a leaf)
#' @noRd
env_shape = function(x) {
  if (inherits(x, "Seurat")) {
    f = env_seurat_facts(x)
    return(paste(env_fmt_n(f$cells), "cells x", env_fmt_n(f$features), "features"))
  }
  d = attr(x, "dim")
  if (is.null(d) && isS4(x)) d = attr(x, "Dim")
  if (length(d)) return(paste(env_fmt_n(d), collapse = " x "))
  if (inherits(x, "data.frame")) {
    return(paste(env_fmt_n(.row_names_info(x, 2L)), "x", env_fmt_n(length(x))))
  }
  if (is.function(x)) return("")
  if (is.environment(x)) return(paste(env_fmt_n(length(x)), "bindings"))
  s = paste("length", env_fmt_n(length(x)))
  if (env_compact_seq(x)) s = paste(s, "(sequence)")
  s
}

#' Snapshot facts of one binding value, without its size (a leaf)
#' @noRd
env_snap_leaf = function(x) {
  opaque = is.environment(x) || is.function(x)
  list(
    address = rlang::obj_address(x), class = class(x)[1L], shape = env_shape(x),
    fp = if (opaque) rlang::obj_address(x) else fingerprint(x)
  )
}

#' Facts of a value whose methods fail (a `length()` method that errors, for example a Python
#' object without a length): address and class, which never dispatch, and shape "?" (a leaf)
#' @noRd
env_snap_bare = function(x) {
  list(address = rlang::obj_address(x), class = class(x)[1L], shape = "?",
       fp = rlang::obj_address(x))
}

#' Facts of binding `name` of box$envir; a failing method gives env_snap_bare() facts
#' (the tryCatch() frame holds only the box, never the environment: rule R3)
#' @noRd
env_snap_facts = function(box, name) {
  force(box)
  force(name)
  tryCatch(env_snap_leaf(get(name, envir = box$envir, inherits = FALSE)),
           error = function(e) env_snap_bare(get(name, envir = box$envir, inherits = FALSE)))
}

#' Size in bytes of one binding value; NA for environments, functions, external pointers and
#' compact sequences (object.size() overstates them) (a leaf)
#' @noRd
env_snap_size = function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) == "externalptr" || env_compact_seq(x)) {
    return(NA_real_)
  }
  as.numeric(utils::object.size(x))
}

#' Snapshot rows; `sizes = FALSE` skips object.size() (the evaluator needs no sizes)
#'
#' `envir` may be a function-frame home: it is held only in a box binding reset on exit, and the
#' loop lives in env_snap_rows(), which never binds `envir` (a `for` loop in a frame binding a
#' function frame left that frame referenced; verified with tracemem).
#' @noRd
env_snapshot_rows = function(envir, previous = NULL, sizes = TRUE) {
  box = new.env(parent = emptyenv())
  box$envir = envir
  on.exit({
    box$envir = NULL
  }, add = TRUE)
  env_snap_rows(box, previous, sizes)
}

#' The snapshot loop; addresses objects by name through box$envir
#' @noRd
env_snap_rows = function(box, previous, sizes) {
  force(box)
  force(previous)
  force(sizes)
  # ls(envir = ): a positional ls(envir) binds `name` and runs tryCatch() on it, which pins a
  # function-frame home (verified with tracemem)
  nms = setdiff(ls(envir = box$envir, all.names = TRUE, sorted = TRUE),
                c(".Random.seed", ".Last.value"))
  n = length(nms)
  out = data.frame(
    name = nms, kind = rep("value", n), address = rep(NA_character_, n),
    class = rep(NA_character_, n), bytes = rep(NA_real_, n), shape = rep(NA_character_, n),
    fp = rep(NA_character_, n), stringsAsFactors = FALSE
  )
  if (!n) return(out)
  act = unname(rlang::env_binding_are_active(box$envir, nms))
  lazy = unname(rlang::env_binding_are_lazy(box$envir, nms))
  out$kind[act] = "active"
  out$kind[lazy & !act] = "promise"
  for (i in which(out$kind == "value")) {
    f = env_snap_facts(box, nms[i])
    out$address[i] = f$address
    out$class[i] = f$class
    out$shape[i] = f$shape
    out$fp[i] = f$fp
    if (!sizes) next
    j = if (is.null(previous)) NA_integer_ else match(nms[i], previous$name)
    reuse = !is.na(j) && identical(previous$address[j], f$address) &&
      identical(previous$class[j], f$class) && identical(previous$shape[j], f$shape)
    out$bytes[i] = if (reuse) {
      previous$bytes[j]
    } else {
      env_snap_size(get(nms[i], envir = box$envir, inherits = FALSE))
    }
  }
  out
}

#' Copy-safe snapshot of an environment (rule R4)
#'
#' One row per binding (`.Random.seed` and `.Last.value` excluded): `name`, `kind` (`value`,
#' `promise`, `active`), `address`, `class` (first element), `bytes` (reused from `previous`
#' when address, class and shape are unchanged: the address-keyed `object.size()` cache; `NA`
#' for environments, functions, external pointers and compact sequences), `shape` and `fp`
#' (`fingerprint()`). Never forces a promise or calls an active binding.
#' @param envir Environment to list.
#' @param previous An earlier snapshot of the same environment, or NULL.
#' @return A data frame.
#' @noRd
env_snapshot = function(envir, previous = NULL) {
  check_env(envir, "envir")
  if (!is.null(previous) && !is.data.frame(previous)) {
    gptr_abort("`previous` must be a snapshot data frame or NULL.", "invalid_argument",
               arg = "previous", expected = "a data frame or NULL")
  }
  env_snapshot_rows(envir, previous, sizes = TRUE)
}

#' TRUE where two character vectors are equal, NA matching NA
#' @noRd
env_same = function(a, b) {
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
}

#' Difference of two snapshots
#'
#' `modified`: kind, address or fingerprint changed, or a static assignment target in
#' `assigned`. A promise that was forced (promise -> value) is not a modification.
#' @param old,new Snapshots (env_snapshot()).
#' @param assigned Static assignment targets of the evaluated code.
#' @return list(added, modified, removed), each a radix-sorted character vector.
#' @noRd
env_diff = function(old, new, assigned = character()) {
  both = intersect(new$name, old$name)
  o = old[match(both, old$name), , drop = FALSE]
  n = new[match(both, new$name), , drop = FALSE]
  forced = o$kind == "promise" & n$kind == "value"
  same = forced | (o$kind == n$kind & env_same(o$address, n$address) & env_same(o$fp, n$fp))
  srt = function(x) sort(unique(as.character(x)), method = "radix")
  list(
    added = srt(setdiff(new$name, old$name)),
    modified = srt(c(both[!same], intersect(assigned, both))),
    removed = srt(setdiff(old$name, new$name))
  )
}

#' Left-aligned workspace columns: name, class, then "shape  size"
#' @noRd
env_align = function(name, cls, shape, size) {
  w1 = min(32L, max(nchar(name))) + 2L
  w2 = min(24L, max(nchar(cls))) + 2L
  tail = ifelse(nzchar(shape) & nzchar(size), paste0(shape, "  ", size),
                ifelse(nzchar(shape), shape, size))
  sub("\\s+$", "", paste0(formatC(name, width = -w1), formatC(cls, width = -w2), tail))
}

#' Lines of the `<workspace>` block
#'
#' At most 12 lines `name  class  shape  size`, largest first, within `budget` estimated
#' tokens, then `(+ n smaller objects: use ls())`. Promises and active bindings show as
#' `<promise>` and `<active>`.
#' @param snapshot An env_snapshot() data frame.
#' @param budget Estimated tokens (at least 20).
#' @return Character vector of lines.
#' @noRd
workspace_lines = function(snapshot, budget = 600L) {
  check_number(budget, "budget", min = 20)
  n = nrow(snapshot)
  if (!n) return(character())
  size = snapshot$bytes
  size[is.na(size)] = -1
  s = snapshot[order(-size, snapshot$name, method = "radix"), , drop = FALSE]
  value = s$kind == "value"
  cls = ifelse(value, s$class, paste0("<", s$kind, ">"))
  shape = ifelse(value, s$shape, "")
  size_txt = vapply(s$bytes, env_fmt_bytes, "")
  k = min(n, 12L)
  lines = env_align(s$name[seq_len(k)], cls[seq_len(k)], shape[seq_len(k)],
                    size_txt[seq_len(k)])
  rest = n - k
  more = function(r) if (r > 0L) sprintf("(+ %d smaller objects: use ls())", r) else NULL
  while (length(lines) > 1L && env_tokens(c(lines, more(rest))) > budget) {
    lines = lines[-length(lines)]
    rest = rest + 1L
  }
  c(lines, more(rest))
}

#' Lines of the `<workspace_changes>` block
#'
#' `+ name class shape size`, `~ name`, `- name`, `user ran: <expr>`, within `budget`.
#' @param diff An env_diff() result.
#' @param snapshot The newer snapshot (facts of added objects).
#' @param user_ran Character vector of the user's top-level expressions (user_expr_log()).
#' @param budget Estimated tokens (at least 20).
#' @return Character vector (empty when nothing changed).
#' @noRd
changes_lines = function(diff, snapshot, user_ran, budget = 300L) {
  check_number(budget, "budget", min = 20)
  i = match(diff$added, snapshot$name)
  added = character()
  if (length(i)) {
    added = paste("+", snapshot$name[i], snapshot$class[i], snapshot$shape[i],
                  vapply(snapshot$bytes[i], env_fmt_bytes, ""))
  }
  lines = sub("\\s+$", "", c(
    added,
    if (length(diff$modified)) paste("~", diff$modified),
    if (length(diff$removed)) paste("-", diff$removed),
    if (length(user_ran)) paste("user ran:", user_ran)
  ))
  lines = gsub(" {2,}", " ", lines)
  rest = 0L
  more = function(r) if (r > 0L) sprintf("(+ %d more changes)", r) else NULL
  while (length(lines) > 1L && env_tokens(c(lines, more(rest))) > budget) {
    lines = lines[-length(lines)]
    rest = rest + 1L
  }
  c(lines, more(rest))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-snapshot|copy-eval")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 47 ]` (45 in `test-env-snapshot.R`, 2 copy rows; the copy rows skip only without `capabilities("profmem")`).

- [ ] **Step 5: Commit**

```bash
git add R/env-snapshot.R tests/testthat/test-env-snapshot.R tests/testthat/test-copy-eval.R
git commit -m "feat(env): add copy-safe workspace snapshots, diffs and workspace lines"
```


### Task 3: `gptr_describe()` and the level-based describers

**Files:** Create: `R/env-describe.R`; Modify: `tests/testthat/test-copy-eval.R` (append); Test: `tests/testthat/test-env-describe.R`. (`NAMESPACE` and `man/gptr_describe.Rd` are generated in Task 11: until then the methods are found by lexical lookup from inside the namespace and its tests, which is all Tasks 3-10 need.)

Ported from report 12 section 5.2 (leaves and formatters) and G2 section 5.4 `describe2()` (levels chosen with the calibrated estimator, content class `describe` = 2.39 characters per token), with the gaps G2's fact-check 18 names closed: Dates keep their class, dgCMatrix dims and nnz, formula text, nested names, and the Seurat `meta.data` dimensions and columns in the first lines at 150 tokens ("a design requirement"). Leaves (`dsc_leaf_*()`) bind the object and return fresh facts; formatters (`dsc_fmt_*()`) never see it; methods for classes of packages outside Suggests read slots with `attr()`, `.subset2()` and `methods::slotNames()` only (IC-71), and the Arrow methods call `dim()`/`names()` only when `isNamespaceLoaded("arrow")`. The test rebuilds all 20 of G2's fixture objects (Matrix, SeuratObject, R6, tibble and data.table classes) from base R, so it needs no package outside Suggests. Measured in scratch: 92 of G2's 98 facts (93.9%; G2's own describe2 kept 90.8%) at 150 tokens, the largest description 130 tokens.

**Interfaces:**
- Consumes: Task 2's `env_tokens()`, `env_fmt_n()`, `env_fmt_bytes()`, `env_compact_seq()`, `env_seurat_facts()`; P01's `check_number()`, `check_string()`, `check_env()`.
- Produces: the export `gptr_describe(x, budget = 150L, ...)` (04 section 6.6) and its 20 S3 methods, each `function(x, budget = 150L, ..., level = NULL)`; `describe_binding(name, envir, budget = 150L)` [R4] (04 section 7.9: `<promise>`/`<active>`/`<not found>`, errors caught: a failing method falls back to the default method, and a one-line note only when that fails too); the private budget harness `describe_value(x, budget = 150L)` and `dsc_fit(lines, budget)` (Task 10's `describe` service and the `attached` block use them).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-env-describe.R`:

```r
# The 20 objects and 98 facts of G2 section 5.4 (G2/c_describe.R, with its final regexes that
# accept both spellings of ranges and types): objects of Matrix, SeuratObject, R6, tibble and
# data.table are rebuilt from base R classes, so the test needs no package outside Suggests.

# An environment for test-only S4 classes; its package name is created without the warning
s4_where = function() {
  e = new.env()
  withCallingHandlers(methods::getPackageName(e),
                      warning = function(w) invokeRestart("muffleWarning"))
  e
}

describe_fixture = function(e) {
  withr::local_seed(3)
  n = 1e5
  methods::setClass(
    "dgCMatrix",
    methods::representation(i = "integer", p = "integer", Dim = "integer", Dimnames = "list",
                            x = "numeric", factors = "list"),
    where = e
  )
  methods::setClass(
    "SeuratLike",
    methods::representation(assays = "list", meta.data = "data.frame", active.ident = "factor",
                            reductions = "list", project.name = "character",
                            version = "character"),
    where = e
  )
  obj = new.env()
  obj$num_vec = c(stats::rnorm(1e6, 50, 10), rep(NA, 2000))
  obj$chr_vec = sample(c("control", "treated", "placebo", "unknown"), n, TRUE)
  obj$fct = factor(sample(c("T cell", "B cell", "NK cell", "monocyte", "platelet"), n, TRUE,
                          prob = c(0.4, 0.2, 0.15, 0.2, 0.05)))
  obj$dates = as.Date("2021-01-01") + sample(0:1000, n, TRUE)
  obj$times = as.POSIXct("2024-03-01 08:00:00", tz = "UTC") + sample(0:86400, n, TRUE)
  obj$df = data.frame(id = seq_len(n), group = sample(c("a", "b", "c"), n, TRUE),
                      dose = round(stats::runif(n, 0, 10), 1),
                      response = c(stats::rnorm(n - 500), rep(NA, 500)),
                      visit = as.Date("2023-01-01") + sample(0:365, n, TRUE),
                      site = factor(sample(paste0("site", 1:12), n, TRUE)),
                      treated = sample(c(TRUE, FALSE), n, TRUE))
  obj$tbl = structure(obj$df, class = c("tbl_df", "tbl", "data.frame"))
  obj$dt = structure(obj$df, class = c("data.table", "data.frame"), sorted = c("site", "id"))
  obj$mat = matrix(stats::rnorm(1000 * 50), 1000, 50,
                   dimnames = list(paste0("gene", 1:1000), paste0("s", 1:50)))
  obj$sparse = methods::new(methods::getClass("dgCMatrix", where = e),
                            i = rep(0L, 6e5), p = rep(0L, 3001L), Dim = c(20000L, 3000L),
                            Dimnames = list(paste0("G", 1:20000), paste0("cell", 1:3000)),
                            x = numeric(6e5), factors = list())
  obj$lst = list(counts = 1:10, label = "run 7", table = mtcars,
                 params = list(alpha = 0.05, method = "BH"))
  samples = list(
    s1 = list(n = 812, qc = list(mt = 0.12, genes = 1850)),
    s2 = list(n = 640, qc = list(mt = 0.09, genes = 1703))
  )
  obj$nested = list(project = list(name = "pbmc", samples = samples),
                    settings = list(resolution = 0.8, dims = 30))
  obj$env = local({
    v = new.env()
    v$counter = 3L
    v$cache = list()
    v$log = function(msg) msg
    v$reset = function() NULL
    v
  })
  obj$fn = eval(parse(text = paste0("function(df, col, threshold = 0.5, na.rm = TRUE) {\n",
                                    "  x = df[[col]]\n  keep = !is.na(x) & x > threshold\n",
                                    "  df[keep, , drop = FALSE]\n}"), keep.source = TRUE))
  obj$fit_lm = stats::lm(mpg ~ wt + hp, data = mtcars)
  obj$fit_glm = stats::glm(am ~ wt, family = stats::binomial, data = mtcars)
  cells = paste0("cell", 1:3000)
  obj$seu = methods::new(methods::getClass("SeuratLike", where = e),
                         assays = list(RNA = obj$sparse), project.name = "pbmc3k",
                         version = "5.1.0",
                         meta.data = data.frame(orig.ident = "pbmc3k",
                                                nCount_RNA = stats::rpois(3000, 2000),
                                                nFeature_RNA = stats::rpois(3000, 800),
                                                percent.mt = stats::runif(3000, 0, 20),
                                                row.names = cells),
                         active.ident = factor(sample(0:8, 3000, TRUE)),
                         reductions = list(pca = matrix(0, 3000, 30)))
  obj$r6 = local({
    v = new.env()
    v$count = 0
    v$step = 1
    v$add = function(n = 1) NULL
    v$reset = function() NULL
    class(v) = c("Counter", "R6")
    v
  })
  obj$fml = y ~ x + log(dose) + (1 | subject)
  obj$altrep = 1:1e9
  obj
}

describe_facts = function() {
  big_n = "100,000|1e\\+05|100000"
  rng = "min|range|mean|[0-9]\\.\\.[-0-9]"
  types = "Date|factor|date|fct"
  list(
    num_vec = c(class = "numeric", length = "1,002,000|1002000", min = rng, median = "median",
                max = rng, na = "NA"),
    chr_vec = c(class = "character", length = big_n, unique = "4 unique|unique",
                example = "control|treated"),
    fct = c(class = "factor", length = big_n, nlevels = "5 levels", top = "T cell"),
    dates = c(class = "Date", length = big_n, range_min = "2021-01-0[1-9]",
              range_max = "2023-09-2[0-9]"),
    times = c(class = "POSIXct", length = big_n, range_min = "2024-03-01 08:0",
              range_max = "2024-03-02 0[78]:"),
    df = c(class = "data.frame", nrow = big_n, ncol = "x 7|7 col|7 var",
           colnames = "response.*visit.*site|response", types = types, stats = rng, na = "NA",
           key_col = "treated"),
    tbl = c(class = "tbl_df|tibble", nrow = big_n, ncol = "x 7|7 col|7 var|\u00d7 7",
            colnames = "response", types = types, stats = rng, na = "NA", key_col = "treated"),
    dt = c(class = "data.table", nrow = big_n, ncol = "x 7|7 col|7 var", colnames = "response",
           types = types, stats = rng, key = "key.*site", key_col = "treated"),
    mat = c(class = "matrix", dim = "1,000 x 50|1000 x 50", type = "double|num",
            rownames = "gene1", colnames = "s1", values = "[0-9]\\.[0-9]{2}"),
    sparse = c(class = "dgCMatrix", dim = "20,000 x 3,000|20000 x 3000",
               nnz = "600,000|6e\\+05|600000|density|non-zero|nnz", rownames = "G1",
               colnames = "cell1"),
    lst = c(class = "list", length = "length 4|list of 4|List of 4",
            names = "counts.*label.*table.*params|counts", elem_class = "data.frame"),
    nested = c(class = "list", top_names = "(?s)project.*settings", depth2 = "samples|name",
               leaf = "resolution|0\\.8", deep = "qc|mt"),
    env = c(class = "environment", n = "4 bindings|4 obj", fields = "counter", methods = "reset"),
    fn = c(class = "function", args = "df, col, threshold", defaults = "threshold = 0\\.5|0\\.5",
           body = "is.na"),
    fit_lm = c(class = "lm", formula = "mpg ~ wt \\+ hp", n = "32", coefs = "wt",
               fit_stat = "R\\^2|R-squared|r.squared"),
    fit_glm = c(class = "glm", formula = "am ~ wt", family = "binomial", coefs = "wt",
                fit_stat = "AIC|deviance"),
    seu = c(class = "SeuratLike", slots = "meta.data", meta_dim = "3,000|3000",
            meta_cols = "percent.mt", assay = "RNA", idents = "active.ident"),
    r6 = c(class = "Counter", fields = "count", methods = "add"),
    fml = c(class = "formula", text = "log\\(dose\\)|y ~ x"),
    altrep = c(class = "integer", length = "1,000,000,000|1e\\+09|1000000000",
               range = "1e\\+09|1,000,000,000|max")
  )
}

test_that("describers keep at least 90% of G2's facts at 150 tokens and stay in budget", {
  e = s4_where()
  obj = describe_fixture(e)
  withr::defer({
    methods::removeClass("dgCMatrix", where = e)
    methods::removeClass("SeuratLike", where = e)
  })
  facts = describe_facts()
  hit = 0L
  total = 0L
  for (nm in names(facts)) {
    d = describe_binding(nm, obj, budget = 150L)
    expect_lte(env_tokens(d), 150 + env_tokens(paste0(nm, ": ")))
    txt = paste(d, collapse = "\n")
    ok = vapply(facts[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
    hit = hit + sum(ok)
    total = total + length(ok)
  }
  expect_equal(total, 98L)
  expect_gte(hit / total, 0.9)
})

test_that("Seurat-like meta.data dims and columns, Dates, sparse dims, formulas, nested names", {
  e = s4_where()
  obj = describe_fixture(e)
  withr::defer({
    methods::removeClass("dgCMatrix", where = e)
    methods::removeClass("SeuratLike", where = e)
  })
  seu = paste(describe_value(obj$seu, 150L), collapse = "\n")
  expect_match(seu, "@meta.data <data.frame> 3,000 rows: orig.ident", fixed = TRUE)
  expect_match(seu, "percent.mt", fixed = TRUE)
  dates = paste(describe_value(obj$dates, 150L), collapse = "\n")
  expect_match(dates, "2021-01-0[1-9] to 2023")
  expect_match(describe_value(obj$sparse, 150L)[1],
               "<dgCMatrix> 20,000 x 3,000 sparse, 600,000 non-zero", fixed = TRUE)
  expect_equal(describe_value(obj$fml, 150L), "<formula> y ~ x + log(dose) + (1 | subject)")
  nested = paste(describe_value(obj$nested, 150L), collapse = "\n")
  expect_match(nested, "samples: <list> length 2", fixed = TRUE)
  expect_match(nested, "resolution: <numeric> length 1 = 0.8", fixed = TRUE)
})

test_that("ALTREP 1:1e9 is described without materialising", {
  x = 1:1e9
  t0 = proc.time()[["elapsed"]]
  d = gptr_describe(x)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_match(d[1], "<integer> length 1,000,000,000, <= 3.7 GB (compact sequence)", fixed = TRUE)
})

test_that("levels: a small budget gives the header, a large one more detail", {
  lo = gptr_describe(mtcars, budget = 20L)
  hi = gptr_describe(mtcars, budget = 600L)
  expect_equal(lo[1], "<data.frame> 32 x 11, 7 KB")
  expect_gt(length(hi), length(lo))
  expect_match(paste(hi, collapse = "\n"), "\\$ mpg <dbl> min 10.4, median 19.2, max 33.9; no NA")
  expect_equal(gptr_describe(mtcars, level = 1L), "<data.frame> 32 x 11, 7 KB")
  expect_error(gptr_describe(mtcars, budget = 5), class = "gptr_error_invalid_argument")
})

test_that("describe_value truncates a third-party method that ignores the budget", {
  x = structure(list(), class = "p09_chatty")
  chatty = function(x, budget = 150L, ...) sprintf("line %03d of a long description", 1:200)
  registerS3method("gptr_describe", "p09_chatty", chatty, envir = environment(gptr_describe))
  out = describe_value(x, 60L)
  expect_lte(env_tokens(out), 60)
  expect_match(out[length(out)], "more lines")
})

test_that("describe_binding never forces promises, catches errors and falls back to the default", {
  e = new.env()
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  e$bad = structure(list(), class = "p09_broken")
  e$worse = structure(list(), class = "p09_broken2")
  ns = environment(gptr_describe)
  boom = function(x, budget = 150L, ...) stop("boom")
  registerS3method("gptr_describe", "p09_broken", boom, envir = ns)
  registerS3method("gptr_describe", "p09_broken2", boom, envir = ns)
  registerS3method("length", "p09_broken2", function(x) stop("no length"), envir = ns)
  expect_equal(describe_binding("lazy", e), "lazy: <promise>")
  expect_equal(describe_binding("act", e), "act: <active>")
  expect_equal(describe_binding("nope", e), "nope: <not found>")
  bad = describe_binding("bad", e)
  expect_match(bad[1], "^bad: <p09_broken> length 0, [0-9]+ B$")
  expect_equal(bad[2], "  typeof list")
  expect_equal(describe_binding("worse", e), "worse: <?> (describe failed: boom)")
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("ggplot, DBI, Arrow and SingleCellExperiment describers need no package calls", {
  geom = structure(list(), class = c("GeomPoint", "Geom"))
  gg = structure(list(data = mtcars, layers = list(list(geom = geom)),
                      mapping = list(x = quote(wt), y = quote(mpg))), class = c("gg", "ggplot"))
  expect_equal(gptr_describe(gg, budget = 300L),
               c("<ggplot> 1 layers (GeomPoint)", "  data: 32 x 11; mapping: x, y"))
  tbl = structure(new.env(), class = c("Table", "ArrowTabular", "ArrowObject", "R6"))
  if (!isNamespaceLoaded("arrow")) {
    expect_equal(gptr_describe(tbl), "<Table/ArrowTabular> (arrow is not loaded)")
  }
  skip_if_not_installed("RSQLite")
  con = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  expect_match(gptr_describe(con), "^<SQLiteConnection> DBI connection; tables are not listed")
})

test_that("describer methods call no package outside Imports (IC-71)", {
  allowed = c("base", "methods", "utils", "stats", "rlang")
  ns = environment(gptr_describe)
  pkgs_of = function(e, acc) {
    if (!is.call(e)) return(invisible(acc))
    if (identical(e[[1L]], as.name("::"))) acc$pkgs = c(acc$pkgs, as.character(e[[2L]]))
    for (i in seq_along(e)) {
      el = e[[i]]
      if (!missing(el)) pkgs_of(el, acc)
    }
    invisible(acc)
  }
  for (nm in grep("^(gptr_describe|dsc_)", ls(ns), value = TRUE)) {
    fun = get(nm, envir = ns)
    if (!is.function(fun)) next
    acc = new.env()
    acc$pkgs = character()
    pkgs_of(body(fun), acc)
    expect_true(all(acc$pkgs %in% allowed), info = nm)
  }
})
```

Append to `tests/testthat/test-copy-eval.R`:

```r
test_that("describe_binding() leaves the object in place (R4)", {
  expect_no_copy(paste("big = runif(5e6)", ns_get("describe_binding"), sep = "; "),
                 'invisible(describe_binding("big", globalenv()))', label = "describe_binding")
  in_frame = paste0('f = function(d) { force(d); s = describe_binding("d", environment()); ',
                    "invisible(NULL) }; f(big)")
  expect_no_copy(paste("big = runif(5e6)", ns_get("describe_binding"), sep = "; "), in_frame,
                 label = "describe_binding in a function frame")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-describe|copy-eval")'
```

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 2 ]`: the eight tests of `test-env-describe.R` error (`could not find function "describe_binding"`, `object 'gptr_describe' not found`), the two new copy rows fail with `the script did not finish`; the two snapshot rows of Task 2 pass.

- [ ] **Step 3: Write the implementation**

Create `R/env-describe.R`:

```r
# env-describe.R -- budgeted, level-based object descriptions (P09).
#
# Ported from report 12 section 5.2 (leaves, formatters) and G2 section 5.4 describe2()
# (levels picked by the calibrated estimator, class "describe" = 2.39 characters per token),
# with G2's gap fixes: Dates re-attached, dgCMatrix dims and nnz, formula text, nested names,
# Seurat meta.data in the header (a design requirement, G2 fact-check 18).
# Discipline (03 section 6.4 R4): dsc_leaf_*() bind the object and return fresh facts; dsc_fmt_*()
# never see the object. Methods for classes of packages outside Suggests use attr(), .subset(),
# .subset2() and methods::slotNames() only, never pkg::fun() (IC-71).

#' Compact, budgeted description of an R object
#'
#' An S3 generic used for the `<attached>` and `<workspace>` context blocks, `peter$describe()`
#' and console mentions. Methods return successively richer levels of detail and the richest
#' level whose estimated size fits `budget` is returned. Methods never force promises, never do
#' I/O (no `dbListTables()`, no `collect()`) and never call `str()` on the object. Packages add
#' methods with a delayed `S3method(gptr::gptr_describe, <class>)`.
#'
#' @param x Any R object.
#' @param budget Estimated tokens, at least 20 (default 150).
#' @param ... Passed to methods; built-in methods accept `level` (1 = header only; larger values
#'   give more detail).
#' @return A character vector of lines; the first is a header `<class> shape, size`.
#' @examples
#' gptr_describe(mtcars, budget = 60)
#' gptr_describe(as.Date("2026-01-01") + 0:9)
#' @export
gptr_describe = function(x, budget = 150L, ...) {
  check_number(budget, "budget", min = 20)
  UseMethod("gptr_describe")
}

# ---------------------------------------------------------------- harness

#' Richest level that fits the budget; a forced `level` wins; else the first level cut by lines
#' @noRd
dsc_pick = function(levels, budget, level = NULL) {
  if (!is.null(level)) return(levels[[max(1L, min(as.integer(level), length(levels)))]])
  ok = vapply(levels, function(l) env_tokens(l) <= budget, NA)
  if (any(ok)) return(levels[[max(which(ok))]])
  dsc_fit(levels[[1L]], budget)
}

#' Truncate description lines to the budget with a "... (n more lines)" line
#' @noRd
dsc_fit = function(lines, budget) {
  lines = as.character(lines)
  if (env_tokens(lines) <= budget || length(lines) <= 1L) {
    if (length(lines) == 1L && env_tokens(lines) > budget) {
      keep = max(10L, floor(nchar(lines) * budget / env_tokens(lines)) - 4L)
      return(paste0(substr(lines, 1L, keep), " ..."))
    }
    return(lines)
  }
  k = length(lines)
  while (k > 1L && env_tokens(c(lines[seq_len(k)], "  ... (999 more lines)")) > budget) k = k - 1L
  c(lines[seq_len(k)], sprintf("  ... (%d more lines)", length(lines) - k))
}

#' The harness: describe a value within `budget`, trying levels 3, 2, 1 of methods that
#' overrun it, then cutting lines (rule R4)
#' @noRd
describe_value = function(x, budget = 150L) {
  out = as.character(gptr_describe(x, budget = budget))
  if (env_tokens(out) <= budget) return(out)
  for (lv in 3:1) {
    alt = as.character(gptr_describe(x, budget = budget, level = lv))
    if (env_tokens(alt) <= budget) return(alt)
  }
  dsc_fit(out, budget)
}

#' Describe a binding by name without forcing promises or calling active bindings
#'
#' @return Character lines; the first starts with `name: `.
#' @noRd
describe_binding = function(name, envir, budget = 150L) {
  check_string(name, "name")
  check_env(envir, "envir")
  check_number(budget, "budget", min = 20)
  if (!exists(name, envir = envir, inherits = FALSE)) return(paste0(name, ": <not found>"))
  if (bindingIsActive(name, envir)) return(paste0(name, ": <active>"))
  if (rlang::env_binding_are_lazy(envir, name)) return(paste0(name, ": <promise>"))
  box = new.env(parent = emptyenv())
  box$envir = envir
  box$name = name
  on.exit({
    box$envir = NULL
  }, add = TRUE)
  d = describe_boxed(box, budget)
  d[1L] = paste0(name, ": ", d[1L])
  d
}

#' tryCatch() lives in a frame that holds only the box, never `envir` (03 section 6.4 R2); a
#' method that fails falls back to the default method (04 section 7.9 "errors caught")
#' @noRd
describe_boxed = function(box, budget) {
  force(box)
  force(budget)
  tryCatch(describe_value(get(box$name, envir = box$envir, inherits = FALSE), budget),
           error = function(e) describe_default(box, budget, conditionMessage(e)))
}

#' The default method's description of a boxed binding, or a one-line note when it fails too
#' @noRd
describe_default = function(box, budget, why) {
  force(box)
  force(budget)
  force(why)
  tryCatch(
    dsc_fit(gptr_describe.default(get(box$name, envir = box$envir, inherits = FALSE),
                                  budget = budget), budget),
    error = function(e) paste0("<?> (describe failed: ", why, ")")
  )
}

# ---------------------------------------------------------------- leaves (bind the object)

#' Core facts of any object (a leaf)
#' @noRd
dsc_leaf_core = function(x) {
  env = is.environment(x)
  fun = is.function(x)
  df = inherits(x, "data.frame")
  list(class = class(x), type = typeof(x), length = length(x), dim = attr(x, "dim"),
       df = df, nrow = if (df) .row_names_info(x, 2L) else NA_integer_, s4 = isS4(x),
       env = env, fun = fun, atomic = is.atomic(x), compact = env_compact_seq(x),
       size = if (env || fun || typeof(x) == "externalptr") {
         NA_real_
       } else {
         as.numeric(utils::object.size(x))
       })
}

#' Evenly spaced sample indices (at most 1e5; report 12 section 3.5)
#' @noRd
dsc_idx = function(n, max_n = 1e5) {
  if (n <= max_n) seq_len(n) else unique(round(seq(1, n, length.out = max_n)))
}

#' Sampled values plus the attributes needed to re-attach the class (a leaf)
#' @noRd
dsc_leaf_sample = function(x, idx) {
  list(values = .subset(x, idx), levels = attr(x, "levels"), class = class(x),
       tzone = attr(x, "tzone"), units = attr(x, "units"))
}

#' Column facts of a data frame (sampled rows, at most 60 columns) (a leaf)
#' @noRd
dsc_leaf_df = function(x, idx, max_cols = 60L) {
  p = length(x)
  k = seq_len(min(p, max_cols))
  cols = vector("list", length(k))
  for (j in k) {
    col = .subset2(x, j)
    cols[[j]] = list(values = .subset(col, idx), levels = attr(col, "levels"),
                     class = class(col), tzone = attr(col, "tzone"), units = attr(col, "units"))
  }
  list(names = attr(x, "names"), cols = cols, p = p, key = attr(x, "sorted"))
}

#' First rows of the first columns of a data frame as plain values (a leaf)
#' @noRd
dsc_leaf_df_rows = function(x, k = 3L, max_cols = 12L) {
  rows = seq_len(min(k, .row_names_info(x, 2L)))
  cols = seq_len(min(max_cols, length(x)))
  out = vector("list", length(cols))
  for (j in cols) {
    col = .subset2(x, j)
    out[[j]] = list(values = .subset(col, rows), levels = attr(col, "levels"),
                    class = class(col), tzone = attr(col, "tzone"), units = attr(col, "units"))
  }
  list(names = attr(x, "names")[cols], cols = out)
}

#' Top-left corner and dimnames samples of a matrix (a leaf)
#' @noRd
dsc_leaf_matrix = function(x) {
  d = attr(x, "dim")
  dn = attr(x, "dimnames")
  list(corner = x[seq_len(min(3L, d[1L])), seq_len(min(5L, d[2L])), drop = FALSE],
       rn = utils::head(dn[[1L]], 3L), cn = utils::head(dn[[2L]], 3L))
}

#' Names and shapes of a nested list, depth first, at most `max_lines` lines (a leaf)
#'
#' Iterative (a stack of index paths; each element is reached from `x` with .subset2()):
#' a recursive walk passing elements to itself left the list referenced (verified with
#' tracemem), so the object never leaves this frame.
#' @noRd
dsc_leaf_walk = function(x, max_depth = 4L, max_lines = 40L) {
  lines = character()
  stack = as.list(rev(seq_len(min(length(x), 8L))))
  more = if (length(x) > 8L) length(x) - 8L else 0L
  lines_tail = if (more) sprintf("  ... %s more elements", env_fmt_n(more)) else NULL
  while (length(stack) && length(lines) < max_lines) {
    path = stack[[length(stack)]]
    stack[[length(stack)]] = NULL
    el = x
    nm = NULL
    for (k in path) {
      nm = attr(el, "names")[k]
      el = .subset2(el, k)
    }
    depth = length(path)
    label = if (is.null(nm) || is.na(nm) || !nzchar(nm)) sprintf("[[%d]]", path[depth]) else nm
    cls = oldClass(el)
    is_df = any(cls == "data.frame")
    len = length(el)
    shape = if (is_df) {
      paste(env_fmt_n(.row_names_info(el, 2L)), "x", env_fmt_n(len))
    } else {
      paste("length", env_fmt_n(len))
    }
    val = if (is.atomic(el) && len == 1L && is.null(cls)) {
      paste0(" = ", substr(as.character(el), 1L, 40L))
    } else {
      ""
    }
    pad = strrep("  ", depth)
    lines = c(lines, sprintf("%s%s: <%s> %s%s", pad, label, class(el)[1L], shape, val))
    if (is.list(el) && !is_df && depth < max_depth && len) {
      kids = rev(seq_len(min(len, 8L)))
      for (i in kids) stack[[length(stack) + 1L]] = c(path, i)
      if (len > 8L) lines = c(lines, sprintf("%s  ... %s more elements", pad, env_fmt_n(len - 8L)))
    }
  }
  el = NULL
  c(lines, lines_tail)
}

#' Facts of S4 slots through attr() (slots are attributes) (a leaf)
#' @noRd
dsc_leaf_s4 = function(x, slots) {
  out = vector("list", length(slots))
  for (i in seq_along(slots)) {
    v = attr(x, slots[i], exact = TRUE)
    df = inherits(v, "data.frame")
    nm = attr(v, "names")
    out[[i]] = list(class = class(v), length = length(v), dim = attr(v, "dim") %||% attr(v, "Dim"),
                    nrow = if (df) .row_names_info(v, 2L) else NA_integer_,
                    names = if (is.null(nm)) NULL else utils::head(nm, 8L))
  }
  out
}

#' Facts of a dgCMatrix through its slots (a leaf)
#' @noRd
dsc_leaf_sparse = function(x) {
  dn = attr(x, "Dimnames")
  list(dim = attr(x, "Dim"), nnz = length(attr(x, "x")),
       rn = utils::head(dn[[1L]], 3L), cn = utils::head(dn[[2L]], 3L))
}

#' Facts of an environment (reference object) without forcing promises (a leaf)
#' @noRd
dsc_leaf_env = function(x) {
  nms = ls(envir = x, all.names = TRUE, sorted = TRUE)
  act = if (length(nms)) unname(rlang::env_binding_are_active(x, nms)) else logical()
  lazy = if (length(nms)) unname(rlang::env_binding_are_lazy(x, nms)) else logical()
  fun = vapply(seq_along(nms), dsc_env_is_fun, NA, nms = nms, envir = x, skip = act | lazy)
  list(names = nms, act = act, lazy = lazy, fun = fun, label = environmentName(x))
}

#' Is binding i a function? (vapply() with a top-level function: no loop in the frame that
#' binds the environment)
#' @noRd
dsc_env_is_fun = function(i, nms, envir, skip) {
  !skip[i] && is.function(get(nms[i], envir = envir, inherits = FALSE))
}

#' Facts of a SummarizedExperiment/SingleCellExperiment through attributes (a leaf)
#' @noRd
dsc_leaf_sce = function(x) {
  cd = attr(x, "colData")
  rd = attr(x, "elementMetadata")
  assays = attr(attr(attr(x, "assays"), "data"), "listData")
  icd = attr(attr(x, "int_colData"), "listData")
  red = attr(icd[["reducedDims"]], "listData")
  list(nrow = attr(rd, "nrows") %||% NA_integer_, ncol = attr(cd, "nrows") %||% NA_integer_,
       assays = names(assays), coldata = names(attr(cd, "listData")), reduced = names(red))
}

#' Facts of a ggplot (list-based or S7-based ggplot2) (a leaf)
#' @noRd
dsc_leaf_gg = function(x) {
  get_part = if (is.list(x)) .subset2 else attr
  data = get_part(x, "data")
  layers = get_part(x, "layers")
  geoms = character(length(layers))
  for (i in seq_along(layers)) {
    g = .subset2(layers[[i]], "geom")
    geoms[i] = class(g)[1L]
  }
  list(nrow = if (inherits(data, "data.frame")) .row_names_info(data, 2L) else NA_integer_,
       ncol = if (inherits(data, "data.frame")) length(data) else NA_integer_,
       mapping = names(get_part(x, "mapping")), geoms = geoms)
}

# ---------------------------------------------------------------- formatters (facts only)

#' Header line `<class/..> shape, size`
#' @noRd
dsc_header = function(f) {
  force(f)
  shape = if (length(f$dim)) {
    paste(env_fmt_n(f$dim), collapse = " x ")
  } else if (isTRUE(f$df)) {
    paste(env_fmt_n(f$nrow), "x", env_fmt_n(f$length))
  } else {
    paste("length", env_fmt_n(f$length))
  }
  size = if (is.na(f$size)) {
    ""
  } else if (isTRUE(f$compact)) {
    paste0(", <= ", env_fmt_bytes(f$size), " (compact sequence)")
  } else {
    paste0(", ", env_fmt_bytes(f$size))
  }
  sprintf("<%s> %s%s", paste(f$class, collapse = "/"), shape, size)
}

#' Short type names for data frame columns
#' @noRd
dsc_abbr = function(cls) {
  ab = c(integer = "int", numeric = "dbl", character = "chr", logical = "lgl", factor = "fct",
         Date = "date", POSIXct = "dttm", list = "list", complex = "cplx")
  a = ab[cls[1L]]
  if (is.na(a)) cls[1L] else unname(a)
}

#' Summary of sampled values with the class re-attached (Dates stay dates)
#' @noRd
dsc_fmt_values = function(s, sampled) {
  force(s)
  force(sampled)
  v = s$values
  na = sum(is.na(v))
  na_txt = if (na) {
    sprintf("%s%.1f%% NA", if (sampled) "~" else "", 100 * na / max(1L, length(v)))
  } else if (sampled) {
    "no NA in sample"
  } else {
    "no NA"
  }
  if (!is.null(s$levels)) {
    v = structure(v, levels = s$levels, class = "factor")
    tb = sort(table(v), decreasing = TRUE)
    k = seq_len(min(3L, length(tb)))
    top = paste(sprintf("%s (%d)", names(tb)[k], as.integer(tb[k])), collapse = ", ")
    return(sprintf("%d levels, top: %s; %s", length(s$levels), top, na_txt))
  }
  if (any(c("Date", "POSIXct", "difftime") %in% s$class)) {
    v = structure(v, class = s$class, tzone = s$tzone, units = s$units)
    if (all(is.na(v))) return(na_txt)
    r = range(v, na.rm = TRUE)
    return(sprintf("%s to %s; %s", format(r[1L]), format(r[2L]), na_txt))
  }
  if (is.numeric(v) && any(!is.na(v))) {
    q = stats::quantile(v, c(0, 0.5, 1), na.rm = TRUE, names = FALSE)
    return(sprintf("min %s, median %s, max %s; %s", format(q[1L], digits = 4),
                   format(q[2L], digits = 4), format(q[3L], digits = 4), na_txt))
  }
  if (is.character(v)) {
    u = unique(v[!is.na(v)])
    ex = paste(encodeString(utils::head(u, 3L), quote = "\""), collapse = ", ")
    return(sprintf("%s%d unique, e.g. %s; %s", if (sampled) ">=" else "", length(u), ex, na_txt))
  }
  if (is.logical(v)) {
    return(sprintf("%s%d TRUE; %s", if (sampled) "~" else "", sum(v, na.rm = TRUE), na_txt))
  }
  paste(format(utils::head(v, 3L)), collapse = ", ")
}

#' Levels of an atomic vector
#' @noRd
dsc_fmt_atomic = function(f, s, n_sample) {
  force(f)
  force(s)
  h = dsc_header(f)
  sampled = n_sample < f$length
  body = paste0("  ", dsc_fmt_values(s, sampled),
                if (sampled) sprintf(" [sample of %s]", env_fmt_n(n_sample)) else "")
  list(h, c(h, body))
}

#' Levels of a data frame: header; types; per-column stats; plus three rows
#' @noRd
dsc_fmt_df = function(f, d, sampled, rows) {
  force(f)
  force(d)
  force(rows)
  h = dsc_header(f)
  if (length(d$key)) h = paste0(h, "; key: ", paste(d$key, collapse = ", "))
  cols = d$names[seq_along(d$cols)]
  types = vapply(d$cols, function(cj) dsc_abbr(cj$class), "")
  more = NULL
  if (d$p > length(d$cols)) {
    more = sprintf("  ... and %d more columns: %s", d$p - length(d$cols),
                   paste(utils::head(d$names[-seq_along(d$cols)], 20L), collapse = ", "))
  }
  l2 = c(h, paste0("  ", paste(sprintf("%s:%s", cols, types), collapse = " ")), more)
  stats = vapply(d$cols, dsc_fmt_values, "", sampled = sampled)
  l3 = c(h, sprintf("  $ %s <%s> %s", cols, types, stats), more)
  vals = lapply(rows$cols, function(cj) {
    structure(cj$values, levels = cj$levels, class = cj$class, tzone = cj$tzone, units = cj$units)
  })
  names(vals) = rows$names
  head_df = if (length(vals)) {
    as.data.frame(vals, stringsAsFactors = FALSE, optional = TRUE)
  } else {
    data.frame()
  }
  l4 = c(l3, paste0("  ", utils::capture.output(print(head_df, row.names = FALSE))))
  list(h, l2, l3, l4)
}

#' Levels of an S4 object: header with slot names; data slots; all slots
#' @noRd
dsc_fmt_s4 = function(f, slots, sl) {
  force(f)
  force(slots)
  force(sl)
  pkg = attr(f$class, "package")
  h = sprintf("<S4 %s%s>%s; slots: %s", f$class[1L],
              if (is.null(pkg)) "" else paste0(" from ", pkg),
              if (is.na(f$size)) "" else paste0(" ", env_fmt_bytes(f$size)),
              paste(slots, collapse = ", "))
  shape = vapply(sl, function(s) {
    if (length(s$dim)) {
      paste(env_fmt_n(s$dim), collapse = " x ")
    } else if (!is.na(s$nrow)) {
      paste(env_fmt_n(s$nrow), "rows")
    } else {
      paste("length", env_fmt_n(s$length))
    }
  }, "")
  nms = vapply(sl, function(s) {
    if (length(s$names)) paste0(": ", paste(s$names, collapse = ", ")) else ""
  }, "")
  cls = vapply(sl, function(s) s$class[1L], "")
  line = sprintf("  @%s <%s> %s%s", slots, cls, shape, nms)
  data_slot = vapply(sl, function(s) {
    length(s$dim) > 0L || !is.na(s$nrow) || s$length > 1L || length(s$names) > 0L
  }, NA)
  list(h, c(h, line[data_slot]), c(h, line))
}

# ---------------------------------------------------------------- methods

#' @rdname gptr_describe
#' @param level Built-in methods: the detail level to return (default: the richest that fits).
#' @export
gptr_describe.default = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  if (f$s4) return(dsc_describe_s4(x, f, budget, level))
  if (f$env) return(dsc_describe_env(x, f, budget, level))
  if (f$atomic && !length(f$dim)) {
    idx = dsc_idx(f$length)
    s = dsc_leaf_sample(x, idx)
    return(dsc_pick(dsc_fmt_atomic(f, s, length(idx)), budget, level))
  }
  dsc_pick(list(dsc_header(f), c(dsc_header(f), paste("  typeof", f$type))), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.factor = function(x, budget = 150L, ..., level = NULL) {
  gptr_describe.default(x, budget = budget, level = level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.Date = function(x, budget = 150L, ..., level = NULL) {
  gptr_describe.default(x, budget = budget, level = level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.POSIXct = function(x, budget = 150L, ..., level = NULL) {
  gptr_describe.default(x, budget = budget, level = level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.data.frame = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  idx = dsc_idx(f$nrow)
  d = dsc_leaf_df(x, idx)
  rows = dsc_leaf_df_rows(x)
  dsc_pick(dsc_fmt_df(f, d, length(idx) < f$nrow, rows), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.data.table = function(x, budget = 150L, ..., level = NULL) {
  gptr_describe.data.frame(x, budget = budget, level = level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.matrix = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  m = dsc_leaf_matrix(x)
  dsc_describe_matrix(f, m, budget, level)
}

#' Matrix levels from facts
#' @noRd
dsc_describe_matrix = function(f, m, budget, level) {
  force(f)
  force(m)
  h = dsc_header(f)
  l2 = c(h, sprintf("  %s; rownames %s; colnames %s", f$type,
                    if (is.null(m$rn)) "none" else paste(m$rn, collapse = ", "),
                    if (is.null(m$cn)) "none" else paste(m$cn, collapse = ", ")))
  l3 = c(l2, paste0("  ", utils::capture.output(print(unname(m$corner), digits = 4L))))
  dsc_pick(list(h, l2, l3), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.list = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  nm = attr(x, "names")
  walks = list(dsc_leaf_walk(x, max_depth = 2L), dsc_leaf_walk(x, max_depth = 3L),
               dsc_leaf_walk(x, max_depth = 4L))
  dsc_pick(dsc_fmt_list(f, nm, walks), budget, level)
}

#' Levels of a list: header; top names; nested names 2, 3 and 4 levels deep
#' @noRd
dsc_fmt_list = function(f, nm, walks) {
  force(f)
  force(nm)
  force(walks)
  h = dsc_header(f)
  top = if (length(nm)) paste0("  names: ", paste(utils::head(nm, 20L), collapse = ", ")) else NULL
  c(list(h, c(h, top)), lapply(walks, function(w) c(h, w)))
}

#' @rdname gptr_describe
#' @export
gptr_describe.environment = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  dsc_describe_env(x, f, budget, level)
}

#' Environment levels (reference objects: no copy concern)
#' @noRd
dsc_describe_env = function(x, f, budget, level) {
  e = dsc_leaf_env(x)
  h = sprintf("<%s>%s with %d bindings (%d functions, %d active, %d unevaluated promises)",
              paste(f$class, collapse = "/"),
              if (nzchar(e$label)) paste0(" '", e$label, "'") else "",
              length(e$names), sum(e$fun), sum(e$act), sum(e$lazy))
  fields = e$names[!e$fun]
  methods = e$names[e$fun]
  l2 = c(h,
         if (length(fields)) {
           paste0("  fields: ", paste(utils::head(fields, 30L), collapse = ", "))
         },
         if (length(methods)) {
           paste0("  methods: ", paste(utils::head(methods, 30L), collapse = ", "))
         })
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.function = function(x, budget = 150L, ..., level = NULL) {
  src = attr(x, "srcref")
  body_lines = if (!is.null(src)) as.character(src) else deparse(x)
  fm = formals(x)
  dflt = vapply(seq_along(fm), function(i) paste(deparse(fm[[i]]), collapse = ""), "")
  args = ifelse(nzchar(dflt), paste(names(fm), "=", dflt), names(fm))
  sig = sprintf("<function> function(%s); %d lines", paste(args, collapse = ", "),
                length(body_lines))
  dsc_pick(list(sig, c(sig, paste0("  ", utils::head(body_lines, 8L)))), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.formula = function(x, budget = 150L, ..., level = NULL) {
  dsc_pick(list(paste("<formula>", paste(deparse(x, width.cutoff = 500L), collapse = " "))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.lm = function(x, budget = 150L, ..., level = NULL) {
  cf = stats::coef(x)
  fml = paste(deparse(stats::formula(x), width.cutoff = 500L), collapse = " ")
  h = sprintf("<%s> %s; n = %d; %d coefficients", paste(class(x), collapse = "/"), fml,
              as.integer(stats::nobs(x)), length(cf))
  fit = if (inherits(x, "glm")) {
    sprintf("family %s(%s); deviance %.4g; AIC %.4g", x$family$family, x$family$link,
            x$deviance, x$aic)
  } else {
    s = summary(x)
    sprintf("R^2 %.3f, adj. R^2 %.3f, sigma %.4g", s$r.squared, s$adj.r.squared, s$sigma)
  }
  coefs = paste0("  coef: ", paste(sprintf("%s=%s", names(cf), format(cf, digits = 4L)),
                                   collapse = ", "))
  dsc_pick(list(h, c(h, paste0("  ", fit)), c(h, paste0("  ", fit), coefs)), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.glm = function(x, budget = 150L, ..., level = NULL) {
  gptr_describe.lm(x, budget = budget, level = level)
}

#' S4 dispatch through the default method (isS4())
#' @noRd
dsc_describe_s4 = function(x, f, budget, level) {
  slots = methods::slotNames(f$class)
  sl = dsc_leaf_s4(x, slots)
  dsc_pick(dsc_fmt_s4(f, slots, sl), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.dgCMatrix = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  sp = dsc_leaf_sparse(x)
  cells = prod(as.numeric(sp$dim))
  h = sprintf("<dgCMatrix> %s x %s sparse, %s non-zero (%.2f%%), %s", env_fmt_n(sp$dim[1L]),
              env_fmt_n(sp$dim[2L]), env_fmt_n(sp$nnz), if (cells) 100 * sp$nnz / cells else 0,
              env_fmt_bytes(f$size))
  l2 = c(h, sprintf("  rownames %s ...; colnames %s ...", paste(sp$rn, collapse = ", "),
                    paste(sp$cn, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.Seurat = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  s = env_seurat_facts(x)
  h = sprintf("<Seurat> %s cells x %s features, %s; assays: %s (active %s); reductions: %s",
              env_fmt_n(s$cells), env_fmt_n(s$features), env_fmt_bytes(f$size),
              paste(s$assays, collapse = ", "), paste(s$active, collapse = ""),
              if (length(s$reductions)) paste(s$reductions, collapse = ", ") else "none")
  meta = sprintf("  meta.data: %s x %s: %s", env_fmt_n(s$cells), env_fmt_n(s$meta_p),
                 paste(utils::head(s$meta_cols, 20L), collapse = ", "))
  idents = sprintf("  active.ident: %d levels", s$idents)
  dsc_pick(list(h, c(h, meta), c(h, meta, idents)), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.SingleCellExperiment = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  s = dsc_leaf_sce(x)
  h = sprintf("<%s> %s features x %s cells, %s; assays: %s", f$class[1L], env_fmt_n(s$nrow),
              env_fmt_n(s$ncol), env_fmt_bytes(f$size), paste(s$assays, collapse = ", "))
  l2 = c(h, sprintf("  colData: %s", paste(utils::head(s$coldata, 20L), collapse = ", ")),
         if (length(s$reduced)) sprintf("  reducedDims: %s", paste(s$reduced, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.ArrowTabular = function(x, budget = 150L, ..., level = NULL) {
  cls = paste(class(x)[1:2], collapse = "/")
  if (!isNamespaceLoaded("arrow")) return(sprintf("<%s> (arrow is not loaded)", cls))
  d = dim(x)
  nm = names(x)
  h = sprintf("<%s> %s x %s", cls, env_fmt_n(d[1L]), env_fmt_n(d[2L]))
  dsc_pick(list(h, c(h, paste0("  columns: ", paste(utils::head(nm, 40L), collapse = ", ")))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.Dataset = function(x, budget = 150L, ..., level = NULL) {
  cls = class(x)[1L]
  if (!isNamespaceLoaded("arrow")) return(sprintf("<%s> (arrow is not loaded)", cls))
  nm = names(x)
  h = sprintf("<%s> %d columns; rows not counted (no scan)", cls, length(nm))
  dsc_pick(list(h, c(h, paste0("  columns: ", paste(utils::head(nm, 40L), collapse = ", ")))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.DBIConnection = function(x, budget = 150L, ..., level = NULL) {
  h = sprintf("<%s> DBI connection; tables are not listed (no I/O): use DBI::dbListTables()",
              class(x)[1L])
  dsc_pick(list(h), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.ggplot = function(x, budget = 150L, ..., level = NULL) {
  g = dsc_leaf_gg(x)
  h = sprintf("<ggplot> %d layers (%s)", length(g$geoms), paste(g$geoms, collapse = ", "))
  l2 = c(h, sprintf("  data: %s x %s; mapping: %s", env_fmt_n(g$nrow), env_fmt_n(g$ncol),
                    paste(g$mapping, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-describe|copy-eval")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 98 ]` (94 in `test-env-describe.R`, 4 copy rows). Without RSQLite the DBI expectation skips (`SKIP 1`).

- [ ] **Step 5: Commit**

```bash
git add R/env-describe.R tests/testthat/test-env-describe.R tests/testthat/test-copy-eval.R
git commit -m "feat(env): add gptr_describe() and the level-based describers"
```


### Task 4: The user-expression log

**Files:** Create: `R/env-history.R`; Test: `tests/testthat/test-env-history.R`.

The `user ran: <expr>` lines of `<workspace_changes>` (architecture section 7.4) come from a task callback (report 12 section 2.C5, `exp_c19_taskcb.R`: the callback sees each successful top-level expression and does not copy the value it is handed; verification log item 18: the registering `peter()` call is logged first, so `peter()` calls are filtered). The callback is added while a session with a kept home is live (Task 10 starts it from the `workspace` block) and removed with the last such session or at unload. The log is process-level (the user's own typing, not run state) and keeps the last 20 entries of at most 120 characters.

**Interfaces:**
- Consumes (P01): `check_number()`, `on_load(expr)`, `on_unload(fun)`.
- Produces: `user_expr_log(since = NULL, n = 20L)` (04 section 7.9) -> chr, oldest first; private `user_log_start(session_id)`, `user_log_release(session_id)`, `user_log_stop()`, `user_log_push(expr)` (Task 10 and its tests use them).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-env-history.R`:

```r
local_history = function(.env = parent.frame()) {
  user_log_stop()
  withr::defer(user_log_stop(), envir = .env)
}

test_that("the callback logs successful user expressions and skips peter() calls", {
  local_history()
  user_log_callback(str2lang("x = 1"), 1, TRUE, FALSE)
  user_log_callback(str2lang("stop('no')"), NULL, FALSE, FALSE)
  user_log_callback(str2lang("s = peter('prompt', mtcars)"), NULL, TRUE, FALSE)
  user_log_callback(str2lang("mtcars |> gptr::peter('again')"), NULL, TRUE, FALSE)
  user_log_callback(str2lang("m[6000, 5000] = -1"), NULL, TRUE, FALSE)
  expect_equal(user_expr_log(), c("x = 1", "m[6000, 5000] = -1"))
})

test_that("entries are cut to 120 characters and only the last 20 are kept", {
  local_history()
  user_log_push(str2lang(paste0("f(", strrep("a", 200), ")")))
  expect_equal(nchar(user_expr_log()), 120L)
  expect_match(user_expr_log(), "\\.\\.\\.$")
  for (i in 1:30) user_log_push(str2lang(sprintf("x%d = %d", i, i)))
  log = user_expr_log()
  expect_length(log, 20L)
  expect_equal(log[20], "x30 = 30")
  expect_equal(user_expr_log(n = 2L), c("x29 = 29", "x30 = 30"))
})

test_that("since filters by time", {
  local_history()
  user_log_push(str2lang("a = 1"))
  t = as.numeric(Sys.time())
  user_log_state$time = t - 10
  user_log_push(str2lang("b = 2"))
  expect_equal(user_expr_log(since = t - 5), "b = 2")
  expect_equal(user_expr_log(since = NULL), c("a = 1", "b = 2"))
  expect_error(user_expr_log(since = "x"), class = "gptr_error_invalid_argument")
})

test_that("the task callback is registered per session and removed with the last one", {
  local_history()
  user_log_start("s0000000001")
  user_log_start("s0000000002")
  user_log_start("s0000000001")
  expect_true("gptr_history" %in% getTaskCallbackNames())
  user_log_release("s0000000001")
  expect_true("gptr_history" %in% getTaskCallbackNames())
  user_log_release("s0000000002")
  expect_false("gptr_history" %in% getTaskCallbackNames())
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-history")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "user_log_stop"`.

- [ ] **Step 3: Write the implementation**

Create `R/env-history.R`:

```r
# env-history.R -- the user's top-level expressions between agent turns (P09).
#
# A task callback (report 12 section 2.C5, exp_c19_taskcb.R: it sees each top-level expression
# and does not copy the value it is handed) registered while a session with a kept home is live
# and removed when the last such session shuts down or the package unloads. The callback never
# touches `value` (no closure or tryCatch in its frame). The first entry after registration is
# the registering peter() call itself (verifier note), so calls of peter() are filtered out.

#' Process-level log of the user's top-level expressions (not run state: the user's own
#' typing history, the last 20 entries)
#' @noRd
user_log_state = new.env(parent = emptyenv())
user_log_state$text = character()
user_log_state$time = numeric()
user_log_state$sessions = character()
user_log_state$active = FALSE

#' Does an expression call peter() (as `peter(...)`, `gptr::peter(...)` or through the pipe)?
#' @noRd
user_log_is_gptr = function(expr) {
  if (!is.call(expr)) return(FALSE)
  head = expr[[1L]]
  if (identical(head, quote(peter)) || identical(head, quote(gptr::peter))) return(TRUE)
  for (i in seq_along(expr)) {
    el = expr[[i]]
    if (!missing(el) && is.call(el) && user_log_is_gptr(el)) return(TRUE)
  }
  FALSE
}

#' Append one expression to the log (keeps the last 20)
#' @noRd
user_log_push = function(expr) {
  if (user_log_is_gptr(expr)) return(invisible())
  txt = paste(deparse(expr, width.cutoff = 500L, nlines = 1L), collapse = "")
  if (nchar(txt) > 120L) txt = paste0(substr(txt, 1L, 117L), "...")
  n = length(user_log_state$text)
  keep = if (n >= 20L) seq.int(n - 18L, n) else seq_len(n)
  user_log_state$text = c(user_log_state$text[keep], txt)
  user_log_state$time = c(user_log_state$time[keep], as.numeric(Sys.time()))
  invisible()
}

#' The task callback: logs successful top-level expressions; never touches `value`
#' @noRd
user_log_callback = function(expr, value, ok, visible) {
  if (isTRUE(ok)) user_log_push(expr)
  TRUE
}

#' Start logging for a session with a kept home (idempotent per session id)
#' @noRd
user_log_start = function(session_id) {
  user_log_state$sessions = union(user_log_state$sessions, session_id)
  if (!user_log_state$active) {
    addTaskCallback(user_log_callback, name = "gptr_history")
    user_log_state$active = TRUE
  }
  invisible()
}

#' Stop logging for a session; the callback is removed with the last session
#' @noRd
user_log_release = function(session_id) {
  user_log_state$sessions = setdiff(user_log_state$sessions, session_id)
  if (!length(user_log_state$sessions)) user_log_stop()
  invisible()
}

#' Remove the callback and clear the log (also run by .onUnload)
#' @noRd
user_log_stop = function() {
  if (user_log_state$active) removeTaskCallback("gptr_history")
  user_log_state$active = FALSE
  user_log_state$sessions = character()
  user_log_state$text = character()
  user_log_state$time = numeric()
  invisible()
}

on_load(on_unload(user_log_stop))

#' Top-level expressions the user evaluated since `since`
#'
#' @param since Epoch seconds (`as.numeric(Sys.time())`) or NULL for the whole log.
#' @param n Most recent entries to return.
#' @return Character vector, oldest first, each at most 120 characters.
#' @noRd
user_expr_log = function(since = NULL, n = 20L) {
  check_number(since, "since", null = TRUE)
  check_number(n, "n", min = 0, int = TRUE)
  keep = if (is.null(since)) rep(TRUE, length(user_log_state$text)) else user_log_state$time > since
  out = user_log_state$text[keep]
  utils::tail(out, n)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-history")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 12 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/env-history.R tests/testthat/test-env-history.R
git commit -m "feat(env): add the task-callback log of user expressions"
```

### Task 5: The `<r_env>` capability probe

**Files:** Create: `R/env-probe.R`; Test: `tests/testthat/test-env-probe.R`.

Adapted from report 19 section 5.12 (`proto_caps.R`) and its format (section 3.2; the `<r_env>` text of architecture section 7.3): `find.package()` plus `Meta/package.rds`, never `loadNamespace()`/`requireNamespace()` (report 19 section 2.5: `rlang::is_installed()` loads namespaces). "Installed but NOT loadable" is decided without loading: a hard dependency (Depends, Imports, LinkingTo) that is not installed; the prototype's out-of-process load probe (29 s) is not run. Cores and RAM come from ps (Imports, IC-59), never from the parallel package; under R CMD check (P01's `check_running()`, or `_R_CHECK_LIMIT_CORES_` set to anything but `false`, as the parallel package reads it) the advertised workers are 2 (IC-60). The body is cached per process because the section is frozen into the cached prompt. Measured on the development machine: 173 estimated tokens, 0.06 s.

**Interfaces:**
- Consumes (P01): `check_running()`; `est_tokens()` (tests only).
- Produces: `r_env_probe()` (04 section 7.9) -> chr(1), the body of `<r_env>` (Task 10 registers it as the T1 section `r_env`); private `env_probe_registry()`, `env_probe_packages(reg, lib = NULL)`, `env_probe_session()`, `env_probe_render(caps, sess)`, `env_probe_deps(field)`, `env_probe_cache`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-env-probe.R`:

```r
fake_lib = function(dir, pkg, version, imports = NA_character_) {
  path = file.path(dir, pkg)
  dir.create(file.path(path, "Meta"), recursive = TRUE)
  desc = c(Package = pkg, Version = version, Imports = imports)
  writeLines(sprintf("Package: %s\nVersion: %s\n", pkg, version), file.path(path, "DESCRIPTION"))
  saveRDS(list(DESCRIPTION = desc), file.path(path, "Meta", "package.rds"))
  path
}

test_that("r_env_probe leaves loadedNamespaces() unchanged and is cached", {
  env_probe_cache$text = NULL
  withr::defer({
    env_probe_cache$text = NULL
  })
  loadNamespace("ps")  # an Import of gptr, loaded on first use of ps::
  before = loadedNamespaces()
  txt = r_env_probe()
  expect_setequal(loadedNamespaces(), before)
  expect_type(txt, "character")
  expect_length(txt, 1L)
  expect_match(txt, "^R [0-9]+\\.[0-9]+\\.[0-9]+, ")
  expect_match(txt, "cores \\(use <= [0-9]+ workers\\)")
  expect_identical(r_env_probe(), txt)
  expect_lte(est_tokens(txt, "prose"), 450)
})

test_that("the registry has the 36 steered packages of report 19", {
  reg = env_probe_registry()
  expect_equal(nrow(reg), 36L)
  expect_equal(reg$repo[reg$pkg == "BPCells"], "GitHub")
  expect_equal(reg$repo[reg$pkg == "SingleCellExperiment"], "Bioc")
})

test_that("env_probe_packages reads versions and missing dependencies without loading", {
  lib = withr::local_tempdir()
  fake_lib(lib, "p09fastpkg", "1.2.3-4")
  fake_lib(lib, "p09brokenpkg", "0.9", imports = "p09nothere (>= 1.0), stats")
  reg = data.frame(pkg = c("p09fastpkg", "p09brokenpkg", "p09absent"), cat = c("io", "io", "sc"),
                   repo = c("CRAN", "CRAN", "Bioc"), stringsAsFactors = FALSE)
  caps = env_probe_packages(reg, lib = lib)
  expect_equal(caps$version, c("1.2.3-4", "0.9", NA))
  expect_equal(caps$missing, c(NA, "p09nothere", NA))
  sess = list(r = "4.4.3", platform = "aarch64-apple-darwin20", utf8 = TRUE, cores = 8L,
              workers = 7L, ram_gb = 24)
  expect_equal(strsplit(env_probe_render(caps, sess), "\n", fixed = TRUE)[[1]], c(
    "R 4.4.3, aarch64-apple-darwin20, UTF-8 locale; 8 cores (use <= 7 workers); RAM 24 GB",
    "Installed: io: p09fastpkg 1.2.3",
    paste("Installed but NOT loadable (do not library() them):",
          "p09brokenpkg (missing dependency p09nothere)"),
    "Not installed (ask before installing; Bioc = BiocManager, GitHub = remotes): p09absent[Bioc]"
  ))
})

test_that("R CMD check limits the advertised workers to 2", {
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "TRUE")
  expect_equal(env_probe_session()$workers, 2L)
  deps = env_probe_deps("R (>= 4.2.0), jsonlite,\n  cli (>= 3.6), utils")
  expect_equal(deps, c("jsonlite", "cli"))
})

test_that("_R_CHECK_LIMIT_CORES_=false outside R CMD check does not limit the workers", {
  withr::local_envvar(`_R_CHECK_LIMIT_CORES_` = "false", `_R_CHECK_PACKAGE_NAME_` = NA)
  s = env_probe_session()
  expect_equal(s$workers, if (is.na(s$cores)) 1L else max(1L, as.integer(s$cores) - 1L))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-probe")'
```

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `object 'env_probe_cache' not found` and `could not find function "env_probe_registry"` (`"env_probe_packages"`, `"env_probe_session"`).

- [ ] **Step 3: Write the implementation**

Create `R/env-probe.R`:

```r
# env-probe.R -- installed-package capability probe for the `<r_env>` section (P09).
#
# Adapted from report 19 section 5.12 (proto_caps.R) and its format spec (section 3.2):
# find.package() plus Meta/package.rds, never loadNamespace()/requireNamespace()
# (rlang::is_installed() loads namespaces, report 19 section 2.5). "Installed but NOT loadable"
# is detected without loading: a hard dependency (Depends/Imports/LinkingTo) that is not
# installed. The out-of-process load probe of the prototype (29 s) is not run. Cores come from
# ps (Imports), never from the parallel package; total RAM is shown, free RAM is left out because
# the section is frozen into the cached system prompt (architecture section 7.3 example).

#' Per-process cache of the rendered body
#' @noRd
env_probe_cache = new.env(parent = emptyenv())

#' Steered packages (report 19 section 3.3): name, category, repository
#' @noRd
env_probe_registry = function() {
  pkgs = c("data.table", "vroom", "arrow", "readr", "nanoparquet", "duckdb", "duckplyr",
           "collapse", "dplyr", "dtplyr", "tidytable", "matrixStats", "kit", "stringi",
           "stringr", "qs2", "fst", "Matrix", "bigmemory", "DelayedArray", "HDF5Array",
           "BPCells", "mirai", "future", "future.apply", "crew", "BiocParallel", "targets",
           "bench", "profvis", "ggplot2", "scattermore", "ggrastr", "Seurat", "SeuratObject",
           "SingleCellExperiment")
  category = c("io+wrangle", "io", "io+disk", "io", "io", "disk", "disk", "wrangle", "wrangle",
               "wrangle", "wrangle", "stats", "stats", "strings", "strings", "serialize",
               "serialize", "matrix", "matrix", "matrix", "matrix", "matrix", "parallel",
               "parallel", "parallel", "parallel", "parallel", "pipeline", "profile", "profile",
               "plot", "plot", "plot", "sc", "sc", "sc")
  repo = rep("CRAN", length(pkgs))
  repo[pkgs %in% c("DelayedArray", "HDF5Array", "BiocParallel", "SingleCellExperiment")] = "Bioc"
  repo[pkgs == "BPCells"] = "GitHub"
  data.frame(pkg = pkgs, cat = category, repo = repo, stringsAsFactors = FALSE)
}

#' Package names of a DESCRIPTION dependency field ("R" and base packages dropped)
#' @noRd
env_probe_deps = function(field) {
  if (is.null(field) || is.na(field) || !nzchar(field)) return(character())
  x = trimws(sub("\\(.*$", "", strsplit(gsub("\\s+", " ", field), ",", fixed = TRUE)[[1L]]))
  base = c("R", "base", "compiler", "datasets", "graphics", "grDevices", "grid", "methods",
           "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils")
  setdiff(x[nzchar(x)], base)
}

#' Installed version and missing hard dependencies of each package, without loading any
#' @noRd
env_probe_packages = function(reg, lib = NULL) {
  paths = find.package(reg$pkg, lib.loc = lib, quiet = TRUE)
  names(paths) = basename(paths)
  n = nrow(reg)
  reg$version = NA_character_
  reg$missing = NA_character_
  for (i in seq_len(n)) {
    path = unname(paths[reg$pkg[i]])
    if (is.na(path)) next
    meta = tryCatch(readRDS(file.path(path, "Meta", "package.rds")), error = function(e) NULL)
    d = meta$DESCRIPTION
    if (is.null(d)) next
    reg$version[i] = unname(d["Version"])
    deps = unique(c(env_probe_deps(d["Depends"]), env_probe_deps(d["Imports"]),
                    env_probe_deps(d["LinkingTo"])))
    if (!length(deps)) next
    found = basename(find.package(deps, lib.loc = lib, quiet = TRUE))
    miss = setdiff(deps, found)
    if (length(miss)) reg$missing[i] = paste(miss, collapse = ", ")
  }
  reg
}

#' R version, platform, locale, cores, workers and RAM of this session
#'
#' Under R CMD check (P01's check_running(), or `_R_CHECK_LIMIT_CORES_` set to anything but
#' "false", as R's parallel package reads it) the advertised workers are 2 (IC-60).
#' @noRd
env_probe_session = function() {
  cores = tryCatch(ps::ps_cpu_count(logical = TRUE), error = function(e) NA_integer_)
  limit = tolower(Sys.getenv("_R_CHECK_LIMIT_CORES_"))
  workers = if (check_running() || !(limit %in% c("", "false"))) {
    2L
  } else if (is.na(cores)) {
    1L
  } else {
    max(1L, as.integer(cores) - 1L)
  }
  ram = tryCatch(ps::ps_system_memory()[["total"]], error = function(e) NA_real_)
  list(r = as.character(getRversion()), platform = R.version$platform,
       utf8 = isTRUE(l10n_info()[["UTF-8"]]), cores = cores, workers = workers,
       ram_gb = if (is.na(ram)) NA_real_ else round(ram / 1024^3))
}

#' Render the `<r_env>` body (section 3.2 of report 19; at most four lines)
#' @noRd
env_probe_render = function(caps, sess) {
  short = function(v) sub("^(\\d+\\.\\d+(\\.\\d+)?).*$", "\\1", gsub("-", ".", v))
  have = caps[!is.na(caps$version) & is.na(caps$missing), , drop = FALSE]
  broken = caps[!is.na(caps$version) & !is.na(caps$missing), , drop = FALSE]
  absent = caps[is.na(caps$version), , drop = FALSE]
  first = sprintf("R %s, %s, %s locale; %s cores (use <= %d workers)%s", sess$r, sess$platform,
                  if (sess$utf8) "UTF-8" else "NON-UTF-8",
                  if (is.na(sess$cores)) "?" else as.character(sess$cores), sess$workers,
                  if (is.na(sess$ram_gb)) "" else sprintf("; RAM %d GB", as.integer(sess$ram_gb)))
  cats = unique(caps$cat)
  by_cat = split(paste(have$pkg, short(have$version)), factor(have$cat, levels = cats))
  by_cat = by_cat[lengths(by_cat) > 0L]
  lines = c(first,
            if (length(by_cat)) {
              paste0("Installed: ", paste(sprintf("%s: %s", names(by_cat),
                                                  vapply(by_cat, paste, "", collapse = ", ")),
                                          collapse = "; "))
            },
            if (nrow(broken)) {
              paste0("Installed but NOT loadable (do not library() them): ",
                     paste(sprintf("%s (missing dependency %s)", broken$pkg, broken$missing),
                           collapse = "; "))
            },
            if (nrow(absent)) {
              paste0("Not installed (ask before installing; Bioc = BiocManager, ",
                     "GitHub = remotes): ",
                     paste(ifelse(absent$repo == "CRAN", absent$pkg,
                                  sprintf("%s[%s]", absent$pkg, absent$repo)), collapse = ", "))
            })
  paste(lines, collapse = "\n")
}

#' Body of the `<r_env>` prompt section, computed without loading namespaces
#'
#' Cached for the process (the section is frozen per session).
#' @return chr(1).
#' @noRd
r_env_probe = function() {
  if (is.null(env_probe_cache$text)) {
    caps = env_probe_packages(env_probe_registry())
    env_probe_cache$text = env_probe_render(caps, env_probe_session())
  }
  env_probe_cache$text
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-probe")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/env-probe.R tests/testthat/test-env-probe.R
git commit -m "feat(env): add the r_env capability probe"
```

### Task 6: Plot capture and replay to PNG

**Files:** Create: `R/eval-plots.R`; Test: `tests/testthat/test-eval-plots.R`.

Adapted from report 12 section 5.1 (device-following capture; evaluate 1.0.5's `non_visual_calls` and display-list prefix heuristics, verification log item 6) with IC-67: when no device is open and no human can see one, plots go to `grDevices::pdf(NULL)` with `dev.control(displaylist = "enable")`, so no `Rplots.pdf` appears in `getwd()` and no screen device opens under `_R_CHECK_SCREEN_DEVICE_=stop`; the prior device is restored. Recorded plots are replayed to 768x512 PNGs at res 120 (532 Anthropic tokens, G2 (g)) through ragg when installed, else `grDevices::png()` (cairo on Linux), and dropped once rendered. Low-level additions in later top-level expressions (`plot(x)`, then `abline(...)`, then `lines(...)`) replace the recording of the page this evaluation already captured, as knitr's default `fig.keep = "high"` does with evaluate's per-expression snapshots: the model sees the finished page as one image instead of every intermediate state, each costing 532 tokens, with the finished page past the `max_images` cut. Task 8 wires the capture into `eval_r()`; `plot_png()` is also used by `peter$plot()` (P10).

**Interfaces:**
- Consumes (P01): `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)` (raw data is base64-encoded without newlines), `ws_path(..., create_parent = TRUE)`, `id_new(prefix, n)`, `gptr_opt()`, `check_class()`, `check_number()`.
- Produces: `plot_png(recorded, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"), res = gptr_opt("plot_res"))` (04 section 7.9) -> an image block or `NULL`; private `plot_begin(mode, human, ...)`, `plot_enable_new(ps)`, `plot_capture(ps, incomplete = FALSE)`, `plot_close(ps)`, `plot_render_all(ps, max_render = 50L, ...)`, `plot_block(file, width, height)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-eval-plots.R`:

```r
record_scatter = function() {
  grDevices::pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  dev = grDevices::dev.cur()
  withr::defer(grDevices::dev.off(dev))
  graphics::plot(1:10)
  grDevices::recordPlot()
}

test_that("plot_png renders a recorded plot to a 768x512 PNG image block", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  p = record_scatter()
  b = plot_png(p)
  expect_equal(b$mime, "image/png")
  expect_equal(b$source, "plot")
  expect_equal(c(b$width, b$height), c(768L, 512L))
  expect_match(b$data, "^iVBORw0KGgo")
  expect_false(grepl("\n", b$data, fixed = TRUE))
  big = plot_png(p, width = 1000L, height = 700L)
  expect_equal(c(big$width, big$height), c(1000L, 700L))
  expect_error(plot_png("not a plot"), class = "gptr_error_invalid_argument")
})

test_that("offscreen capture uses pdf(NULL), writes no Rplots.pdf and restores the device", {
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  before = grDevices::dev.cur()
  ps = plot_begin("auto", human = FALSE)
  expect_false(is.null(ps$our_dev))
  graphics::plot(1:3)
  expect_true(plot_capture(ps))
  graphics::plot(3:1)
  expect_true(plot_capture(ps, incomplete = TRUE))
  expect_false(plot_capture(ps, incomplete = TRUE))
  plot_close(ps)
  plot_close(ps)
  expect_equal(grDevices::dev.cur(), before)
  expect_equal(ps$n, 2L)
  files = plot_render_all(ps)
  expect_length(files, 2L)
  expect_true(all(file.exists(files)))
  expect_length(ps$recorded, 0L)
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
})

test_that("device mode records the user's open device and ignores its earlier plot", {
  grDevices::pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  user_dev = grDevices::dev.cur()
  withr::defer(if (user_dev %in% grDevices::dev.list()) grDevices::dev.off(user_dev))
  graphics::plot(1:5)
  ps = plot_begin("auto", human = FALSE)
  expect_null(ps$our_dev)
  expect_false(plot_capture(ps, incomplete = TRUE))
  graphics::plot(5:1)
  expect_true(plot_capture(ps, incomplete = TRUE))
  plot_close(ps)
  expect_equal(grDevices::dev.cur(), user_dev)
})

test_that("mode none records nothing but still avoids Rplots.pdf", {
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  ps = plot_begin("none", human = FALSE)
  graphics::plot(1:3)
  expect_false(plot_capture(ps, incomplete = TRUE))
  plot_close(ps)
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
})

test_that("the visual-change and prefix heuristics follow evaluate", {
  p = record_scatter()
  dl = p[[1L]]
  expect_true(plot_visual_change(dl))
  expect_true(plot_is_prefix(dl[1], dl))
  expect_false(plot_is_prefix(dl, dl[1]))
})

test_that("low-level additions update the captured page instead of adding a plot", {
  ps = plot_begin("capture", human = FALSE)
  withr::defer(plot_close(ps))
  graphics::plot(1:10)
  expect_true(plot_capture(ps))
  graphics::abline(h = 5)
  expect_false(plot_capture(ps, incomplete = TRUE))
  expect_equal(ps$n, 1L)
  expect_length(ps$recorded[[1L]][[1L]], length(grDevices::recordPlot()[[1L]]))
  graphics::plot(3:1)
  expect_true(plot_capture(ps, incomplete = TRUE))
  expect_equal(ps$n, 2L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-plots")'
```

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `could not find function "plot_png"` (`"plot_begin"`, `"plot_visual_change"`).

- [ ] **Step 3: Write the implementation**

Create `R/eval-plots.R`:

```r
# eval-plots.R -- plot capture during an evaluation and replay to PNG (P09).
#
# Adapted from report 12 section 5.1 (device-following capture; evaluate 1.0.5's visual-change
# and display-list prefix heuristics; replay to PNG) with the IC-67 amendments: when no device
# is open and no human can see one, plots go to pdf(NULL) with the display list enabled (no
# Rplots.pdf in getwd(); no screen device under _R_CHECK_SCREEN_DEVICE_=stop) and the prior
# device is restored; PNGs are 768x512 at res 120 (532 Anthropic tokens, G2 (g)), through ragg
# when installed. Recorded plots are held only until they are rendered: events carry PNG paths,
# never recorded plots (04 section 5.8).

#' Open a PNG device of `width` x `height` pixels; TRUE when one was opened
#' @noRd
plot_open_png = function(file, width, height, res) {
  if (requireNamespace("ragg", quietly = TRUE)) {
    ragg::agg_png(file, width = width, height = height, units = "px", res = res)
    return(TRUE)
  }
  linux = identical(Sys.info()[["sysname"]], "Linux")
  if (linux && isTRUE(capabilities("cairo"))) {
    grDevices::png(file, width = width, height = height, units = "px", res = res,
                   type = "cairo")
    return(TRUE)
  }
  if (isTRUE(capabilities("png"))) {
    grDevices::png(file, width = width, height = height, units = "px", res = res)
    return(TRUE)
  }
  FALSE
}

#' Replay a recorded plot into a PNG file; the path, or NULL when no PNG device is available
#' @noRd
plot_render = function(recorded, file, width, height, res) {
  prev = grDevices::dev.cur()
  if (!plot_open_png(file, width, height, res)) return(NULL)
  dev = grDevices::dev.cur()
  on.exit({
    if (dev %in% grDevices::dev.list()) grDevices::dev.off(dev)
    if (prev > 1L && prev %in% grDevices::dev.list()) grDevices::dev.set(prev)
  }, add = TRUE)
  suppressWarnings(grDevices::replayPlot(recorded))
  file
}

#' Image block of a PNG file (04 section 4.1; base64 without newlines)
#' @noRd
plot_block = function(file, width, height) {
  bytes = readBin(file, "raw", n = file.size(file))
  block_image(bytes, mime = "image/png", source = "plot", width = as.integer(width),
              height = as.integer(height))
}

#' A new PNG path in the workspace's spill directory (cache/tmp)
#' @noRd
plot_file = function() {
  ws_path("cache", "tmp", paste0("gptr-plot-", id_new("", 12L), ".png"))
}

#' Render a recorded plot to a PNG image block
#'
#' Used by the evaluator and by `peter$plot()` (P10) and `.opts$images` (P08, IC-44).
#' @param recorded A `recordedplot` (grDevices::recordPlot()).
#' @param width,height Pixels (defaults `gptr.plot_width`, `gptr.plot_height`).
#' @param res Resolution in pixels per inch (default `gptr.plot_res`).
#' @return An image block (04 section 4.1), or NULL when no PNG device is available.
#' @noRd
plot_png = function(recorded, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"),
                    res = gptr_opt("plot_res")) {
  check_class(recorded, "recordedplot", "recorded")
  width = check_number(width, "width", min = 16, int = TRUE)
  height = check_number(height, "height", min = 16, int = TRUE)
  res = check_number(res, "res", min = 16, int = TRUE)
  file = plot_render(recorded, plot_file(), width, height, res)
  if (is.null(file)) return(NULL)
  plot_block(file, width, height)
}

#' evaluate's heuristic: does a display list draw something? (report 12 section 5.1)
#' @noRd
plot_visual_change = function(dl) {
  non_visual = c("C_clip", "C_layout", "C_par", "C_plot_window", "C_strHeight", "C_strWidth",
                 "palette", "palette2")
  for (item in dl) {
    x = item[[2L]][[1L]]
    if (utils::hasName(x, "name")) {
      if (!(x$name %in% non_visual)) return(TRUE)
    } else if (is.call(x)) {
      if (!identical(as.character(x[[1L]]), "requireNamespace")) return(TRUE)
    }
  }
  FALSE
}

#' Is display list x a prefix of y? (`x[]` turns a pairlist into a list)
#' @noRd
plot_is_prefix = function(x, y) {
  length(x) <= length(y) && identical(x[], y[seq_along(x)])
}

#' Start plot capture for an evaluation; returns the plot state environment
#'
#' `mode`: "auto" draws on the user's device when one is open or a human is present, else on
#' pdf(NULL); "capture" always draws on pdf(NULL); "none" records nothing (pdf(NULL) is still
#' opened when no device is open and no human is present, so no Rplots.pdf is written).
#' @noRd
plot_begin = function(mode, human, width = gptr_opt("plot_width"),
                      height = gptr_opt("plot_height"), res = gptr_opt("plot_res")) {
  ps = new.env(parent = emptyenv())
  ps$record = !identical(mode, "none")
  ps$dev_start = grDevices::dev.cur()
  ps$devs0 = grDevices::dev.list()
  ps$our_dev = NULL
  ps$last_dl = list()
  ps$last_k = list()
  ps$recorded = list()
  ps$n = 0L
  ps$closed = FALSE
  offscreen = identical(mode, "capture") || (ps$dev_start == 1L && !isTRUE(human))
  if (offscreen) {
    grDevices::pdf(file = NULL, width = width / res, height = height / res)
    grDevices::dev.control(displaylist = "enable")
    ps$our_dev = grDevices::dev.cur()
  } else if (ps$dev_start > 1L && ps$record) {
    try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
    base = tryCatch(grDevices::recordPlot(), error = function(e) NULL)
    if (!is.null(base)) ps$last_dl[[as.character(ps$dev_start)]] = base[[1L]]
  }
  ps
}

#' Enable the display list on a device the evaluated code opened itself
#' @noRd
plot_enable_new = function(ps) {
  d = grDevices::dev.cur()
  fresh = d > 1L && !(d %in% c(ps$devs0, ps$our_dev)) && is.null(ps$last_dl[[as.character(d)]])
  if (fresh) try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
  invisible()
}

#' Record the current page when it is complete and new; TRUE when a new plot was captured
#'
#' Low-level additions to a page this evaluation already captured (`abline()`, `lines()`,
#' `points()` in later top-level expressions) replace that plot's recording instead of adding
#' one, as knitr's `fig.keep = "high"` does: the model sees the finished page once, not each
#' intermediate state (each image costs 532 tokens and at most `max_images` are attached).
#' @noRd
plot_capture = function(ps, incomplete = FALSE) {
  if (!ps$record) return(FALSE)
  d = grDevices::dev.cur()
  if (d == 1L) return(FALSE)
  if (!is.null(ps$our_dev) && d != ps$our_dev && d %in% ps$devs0) return(FALSE)
  if (!incomplete && !isTRUE(graphics::par("page"))) return(FALSE)
  p = tryCatch(grDevices::recordPlot(), error = function(e) NULL)
  if (is.null(p) || !length(p[[1L]]) || !plot_visual_change(p[[1L]])) return(FALSE)
  key = as.character(d)
  old = ps$last_dl[[key]]
  same_page = !is.null(old) && plot_is_prefix(old, p[[1L]])
  if (same_page && !plot_visual_change(p[[1L]][-seq_along(old)])) return(FALSE)
  ps$last_dl[[key]] = p[[1L]]
  k = ps$last_k[[key]]
  if (same_page && !is.null(k)) {
    ps$recorded[[k]] = p
    return(FALSE)
  }
  ps$n = ps$n + 1L
  ps$recorded[[ps$n]] = p
  ps$last_k[[key]] = ps$n
  TRUE
}

#' Close the private device and restore the prior one; idempotent
#' @noRd
plot_close = function(ps) {
  if (is.null(ps) || isTRUE(ps$closed)) return(invisible())
  ps$closed = TRUE
  if (!is.null(ps$our_dev) && ps$our_dev %in% grDevices::dev.list()) {
    grDevices::dev.off(ps$our_dev)
  }
  if (ps$dev_start > 1L && ps$dev_start %in% grDevices::dev.list()) {
    grDevices::dev.set(ps$dev_start)
  }
  invisible()
}

#' Render the captured plots (at most `max_render`) to PNG files and drop the recordings
#'
#' @return Character vector of PNG paths (NA where rendering failed), one per captured plot up
#'   to `max_render`.
#' @noRd
plot_render_all = function(ps, max_render = 50L, width = gptr_opt("plot_width"),
                           height = gptr_opt("plot_height"), res = gptr_opt("plot_res")) {
  n = min(ps$n, max_render)
  files = rep(NA_character_, n)
  for (k in seq_len(n)) {
    f = tryCatch(plot_render(ps$recorded[[k]], plot_file(), width, height, res),
                 error = function(e) NULL)
    if (!is.null(f)) files[k] = f
  }
  ps$recorded = list()
  files
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-plots")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 32 ]` (without ragg and without `capabilities("png")` the first test skips).

- [ ] **Step 5: Commit**

```bash
git add R/eval-plots.R tests/testthat/test-eval-plots.R
git commit -m "feat(eval): add plot capture on pdf(NULL) and replay to 768x512 PNG"
```


### Task 7: Agent RNG streams: `rng_swap()`

**Files:** Create: `R/eval-core.R`; Test: `tests/testthat/test-eval-core.R`.

IC-61: each inline agent draws from its own L'Ecuyer-CMRG stream, swapped in around its evaluations, so the user's `.Random.seed` is identical before and after. The seeds are derived from `hash_sha256()` bits, never from R's generator, and the swap assigns `.Random.seed` with `env[[".Random.seed"]] =` and removes it with `rm(list = ...)`, the forms P01's lint rule allows inside `rng_swap()` and `with_seed_preserved()` only. The state environment holds `seed` (the advanced vector, `NULL` before the first swap) and `id` (the agent id, or `"<.opts$seed>:<agent label>"` when a reproducible stream is requested; P19 builds it as `run$opts$rng_state`). R keeps its generator kind internally and `set.seed()` keeps the kind in force, so removing `.Random.seed` after the swap (the user had none) would leave L'Ecuyer-CMRG in force: the user's next `set.seed(42); runif(1)` gives 0.1738 instead of 0.9148 (measured in scratch, R 4.4.3). Without `RNGkind()` (IC-61 forbids it), `rng_swap()` reads the kind code before the swap and puts it back afterwards through `stats::rbinom(1L, 0L, 0.5)`, which makes R load and store its state without drawing a number, then removes the stored variable again. This task creates `eval-core.R` with the file header and the two RNG functions; Task 8 appends the evaluator.

**Interfaces:**
- Consumes (P01): `hash_sha256(x)`, `check_env()`, `` `%||%` ``.
- Produces (04 section 7.9): `rng_swap(state, expr)` [leaf] -> the value of `expr`; private `rng_seeds(key)` -> `c(10407L, <6 seeds>)`. Consumers: `eval_r(rng =)` (Task 8), P19.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-eval-core.R`:

```r
test_that("rng_seeds derives a valid L'Ecuyer vector from a key without the RNG", {
  env = globalenv()
  before = get0(".Random.seed", envir = env, inherits = FALSE)
  s = rng_seeds("s0123456789")
  expect_type(s, "integer")
  expect_length(s, 7L)
  expect_equal(s[1], 10407L)
  expect_identical(rng_seeds("s0123456789"), s)
  expect_false(identical(rng_seeds("s0123456789:b"), s))
  expect_identical(get0(".Random.seed", envir = env, inherits = FALSE), before)
})

test_that("rng_swap keeps the user's .Random.seed and advances the agent's stream", {
  withr::local_seed(42)
  env = globalenv()
  before = get(".Random.seed", envir = env)
  st1 = new.env()
  st1$id = "s0123456789"
  x1 = rng_swap(st1, stats::runif(3))
  expect_identical(get(".Random.seed", envir = env), before)
  expect_equal(st1$seed[1], 10407L)
  st2 = new.env()
  st2$id = "s0123456789"
  expect_identical(rng_swap(st2, stats::runif(3)), x1)
  expect_false(identical(rng_swap(st2, stats::runif(3)), x1))
  expect_identical(stats::runif(1), withr::with_seed(42, stats::runif(1)))
})

test_that("rng_swap removes .Random.seed again when the user had none", {
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  withr::defer({
    if (!is.null(saved)) env[[".Random.seed"]] = saved
  })
  if (!is.null(saved)) rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s1"
  x = rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  expect_true(is.numeric(x))
  expect_equal(st$seed[1], 10407L)
  expect_error(rng_swap(list(), 1), class = "gptr_error_invalid_argument")
})

test_that("rng_swap leaves R's generator kind as it found it when the user had no seed", {
  env = globalenv()
  withr::local_preserve_seed()
  set.seed(42)
  ref = stats::runif(1)
  rm(list = ".Random.seed", envir = env)
  st = new.env()
  st$id = "s2"
  rng_swap(st, stats::runif(1))
  expect_false(exists(".Random.seed", envir = env, inherits = FALSE))
  set.seed(42)
  expect_identical(stats::runif(1), ref)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-core")'
```

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `could not find function "rng_seeds"` (`"rng_swap"`).

- [ ] **Step 3: Write the implementation**

Create `R/eval-core.R`:

```r
# eval-core.R -- the hand-rolled evaluator eval_r() and the RNG swap rng_swap() (P09).
#
# Adapted from report 12 section 5.1 (gptr_eval2.R: anonymous-file sink, calling handlers,
# per-expression time limits, trimmed tracebacks, plot hooks, harness options) with the fixes of
# its verification log (items 3, 4, 9, 10, 25), the contract's amendments (04 section 7.9;
# IC-61, IC-67) and the G3 fact-check fix for function-frame homes. Frame layout, verified with
# fresh-process tracemem runs (test-copy-eval.R):
#   eval_r()        binds `envir`; creates no closure, no tryCatch() and no loop; stores `envir`
#                   in the state environment `st` and resets st$envir to NULL on exit (R2).
#   eval_run(), eval_loop(), eval_loop_catch(), eval_one()
#                   hold only `st`; eval_one() creates the calling handlers and the restart.
#                   Every helper forces its arguments on entry (R3).
#   eval_top(), eval_frame()
#                   closure-free leaves that reach `envir` through st$envir; every withVisible()
#                   result is cleared in place with res[1L] = list(NULL) (R8, IC-67).
# The value of an evaluation is never kept. Known limit (R itself, not gptr): an error unwinds
# the frames between the failing call and the restart without releasing what they reference, so
# an object the failing code passed through a function (or a home frame the failing code forced)
# copies once on its next in-place edit, exactly as after try() in user code.

#' L'Ecuyer-CMRG seed vector from a key (IC-61)
#'
#' 24 bytes of sha256(key): three 32-bit words reduced modulo m1 = 4294967087 and three modulo
#' m2 = 4294944443, stored as R integers (two's complement) after the kind code 10407L. Uses no
#' random number generator.
#' @noRd
rng_seeds = function(key) {
  h = hash_sha256(as.character(key)[[1L]])
  hex = substring(h, seq(1L, 41L, by = 8L), seq(8L, 48L, by = 8L))
  v = as.numeric(paste0("0x", hex))
  v = v %% c(rep(4294967087, 3L), rep(4294944443, 3L))
  if (all(v[1:3] == 0)) v[1L] = 1
  if (all(v[4:6] == 0)) v[4L] = 1
  v = ifelse(v > 2147483647, v - 4294967296, v)
  c(10407L, as.integer(v))
}

#' Evaluate `expr` with an agent's L'Ecuyer stream in .Random.seed (a leaf)
#'
#' Saves the user's `.Random.seed` of the global environment (or its absence), assigns
#' `state$seed` (derived with rng_seeds(state$id) when unset: `id` is the agent id, or
#' `"<.opts$seed>:<agent label>"` for reproducible streams, IC-61), evaluates, keeps the
#' advanced vector in `state$seed` and restores or removes the user's value. With
#' with_seed_preserved() the only code that assigns .Random.seed. R also keeps its generator
#' kind internally, and set.seed() keeps the kind in force: removing the variable alone would
#' leave L'Ecuyer-CMRG in force, so the user's next `set.seed(42)` would draw other numbers.
#' When the user had no seed, the kind code is therefore read before the swap and put back
#' after it: `stats::rbinom(1L, 0L, 0.5)` makes R load (or initialise) and store its state
#' without drawing a number (size 0 returns 0), and the variable it stores is removed again.
#' @param state An environment: `seed` (the vector, or NULL) and `id`.
#' @param expr The expression to evaluate (lazily, inside the swap).
#' @return The value of `expr`.
#' @noRd
rng_swap = function(state, expr) {
  check_env(state, "state")
  seed = state$seed %||% rng_seeds(state$id %||% "gptr")
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  kind = NULL
  if (is.null(saved)) {
    invisible(stats::rbinom(1L, 0L, 0.5))
    now = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(now)) rm(list = ".Random.seed", envir = env)
    kind = if (is.integer(now) && length(now)) now[1L] else 10403L
  }
  env[[".Random.seed"]] = seed
  on.exit({
    state$seed = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(saved)) {
      env[[".Random.seed"]] = saved
    } else {
      env[[".Random.seed"]] = kind
      invisible(stats::rbinom(1L, 0L, 0.5))
      if (exists(".Random.seed", envir = env, inherits = FALSE)) {
        rm(list = ".Random.seed", envir = env)
      }
    }
  }, add = TRUE)
  expr
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-core")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 17 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/eval-core.R tests/testthat/test-eval-core.R
git commit -m "feat(eval): add hash-derived L'Ecuyer agent streams with rng_swap()"
```

### Task 8: The evaluator `eval_r()`

**Files:** Modify: `R/eval-core.R` (append), `tests/testthat/test-eval-core.R` (append), `tests/testthat/test-copy-eval.R` (append).

The hand-rolled evaluator of architecture section 6.12, adapted from report 12 section 5.1 (`gptr_eval2.R`) with the fixes of its verification log (item 3: a sink the model leaves open is recovered; item 4: rlang errors keep their class; item 10: `setTimeLimit()` is best effort and reset to `Inf` after every expression; item 25: the guard) and of the review round (IC-67, IC-61, G3 fact-check):

- Frame layout for copy safety. `eval_r()` binds `envir` but creates no closure, no `tryCatch()` and no loop; it stores `envir` in the state environment `st` and resets `st$envir` to `NULL` on exit inside `suspendInterrupts()` [R2]. `eval_run()`, `eval_loop()` and `eval_one()` hold only `st` and force their arguments on entry; `eval_one()` creates the calling handlers and the `gptr_stop` restart [R3]. `eval_top()` and `eval_frame()` reach `envir` through `st$envir`; a symbol is printed as `print(<sym>)` in `envir`, assignments and other invisible heads never pass through `withVisible()`, and every `withVisible()` result is cleared in place with `res[1L] = list(NULL)` before the frame returns [R8, IC-67]. The object snapshots use Task 2's box pattern.
- Capture. Output goes to an anonymous-file sink (`file("", "w+b")`, split to the console when `tee`), messages and warnings are recorded by the calling handlers in order and muffled unless teed (under `options(warn = 2)` R turns the warning into an error), errors stop at the first failing expression with a traceback of the user frames between `eval_frame()` and the handler, cut to 20 frames of 120 characters with `at <gptr>#<line>` locations. The traceback is computed as text (`eval_traceback()`), so no call object that `do.call()` may have filled with values stays in the frame the restart unwinds. An infinite recursion leaves a calling handler almost no stack (measured: a `tryCatch()` inside the handler fails again with "evaluation nested too deeply", and the error escaped `eval_r()`), so a condition of class `stackOverflowError` (R >= 4.2.0) unwinds through the restart first and is recorded afterwards by `eval_overflow()`, without a traceback. CR LF and CR line ends are normalised before parsing (the parser rejects a bare CR).
- Session hygiene. Harness options (`max.print`, `width`, `rlang_interactive`, `cli.dynamic`, `cli.num_colors`, and an `askYesNo` trap for package code) are set and restored; hooks, sinks, the time limit and the plot device are restored on every path; outside a run an interrupt is caught and gives status `interrupt` (inside a run it propagates to the run's interrupt policy). Changes of the working directory, options, environment variables (names only), attached and loaded packages and devices are reported by name; a newly set `TZDIR` is not, because R sets it itself the first time a time is formatted on macOS (gptr's own ids do that while rendering plots). Only calls that are always invisible skip `withVisible()`: `options("digits")`, `library()` and `suppressPackageStartupMessages(x)` print their visible values as at the console.
- Plots. Task 6's capture; at most `max_images` plots are attached, fewer when their image tokens would take more than 60% of the budget; the paths of the others go into one entry of the running session's out store (the process store outside a run) for `peter$plot(k)` (P10). The session is found through the run: 04 section 7.6 types `gptr_run$session` as an id and the kernel SDK has no id-to-session accessor, so `eval_session()` reads the run's `shell` binding defensively and falls back to the process store (see the self-review).
- Known limit (R itself): an error unwinds the frames between the failing call and the restart without releasing what they reference, so an object that failing code passed through a function (or a function-frame home it forced) copies once on its next in-place edit, exactly as after `try()` in user code. An error at top level after reading an object leaves it in place (copy row below).

Measured in scratch (fresh `Rscript --vanilla` per row, 40 MB vector): all 13 copy rows of this task report 0 copies (the S4 row 1 copy, the same as R's own `x@v[1] = 0` without gptr); removing `res[1L] = list(NULL)` makes the `(x)` row copy once (negative control).

**Interfaces:**
- Consumes: Tasks 1, 2, 6 and 7 (`eval_guard()`, `eval_assign_targets()`, `gptr_shim()`, `env_snapshot_rows()`, `env_diff()`, `plot_begin()`, `plot_enable_new()`, `plot_capture()`, `plot_close()`, `plot_render_all()`, `plot_block()`, `rng_swap()`); P01 (04 section 7.1): `check_string()`, `check_env()`, `check_choice()`, `check_number()`, `check_flag()`, `as_utf8()`, `gptr_has_human()`, `gptr_opt()`, `raw_to_utf8(x, fallback = "CP1252")`, `clean_terminal(x)` (returns lines), `est_image_tokens(width, height, api = "anthropic")`, `out_put(text, stream = "stdout", meta = list(), session = NULL)` (`session`: `NULL` or a session's live record); P06 kernel SDK (IC-33): `run_current()`, `session_live(s)`; test helpers `expect_no_copy()`, `tracemem_loader()`, `rscript_path()` (P01) and `out_get(id, stream, lines, session)` (P01).
- Produces (04 section 7.9, section 5.8): `eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE, max_images = gptr_opt("r_max_images"))` -> `gptr_eval_result` with `changes$objects = list(added, modified, removed, lines)` (the object diff and its `+`/`~`/`-` lines, read by Task 9 and P10) and `plot` events `list(type = "plot", index, path, attached, out_id)`; private `eval_session()` (Task 9).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-eval-core.R`:

```r
ev_types = function(res) vapply(res$events, function(e) e$type, "")
ev_of = function(res, type) Filter(function(e) identical(e$type, type), res$events)

test_that("eval_r evaluates in envir, prints like the console and keeps no value", {
  e = new.env()
  res = eval_r("x = 1:3\nx\ny = x * 2; invisible(y)\nsum(y)", e)
  expect_s3_class(res, "gptr_eval_result")
  expect_named(res, c("status", "events", "n_done", "n_total", "changes", "elapsed", "images",
                      "assigned", "outputs", "spill", "out_id", "interrupted_after"))
  expect_equal(res$status, "ok")
  expect_equal(c(res$n_done, res$n_total), c(5L, 5L))
  expect_equal(e$y, c(2, 4, 6))
  out = paste(vapply(ev_of(res, "output"), function(ev) ev$text, ""), collapse = "")
  expect_equal(out, "[1] 1 2 3\n[1] 12\n")
  expect_equal(res$outputs, list(character(), "[1] 1 2 3", character(), character(), "[1] 12"))
  expect_setequal(res$assigned, c("x", "y"))
  expect_equal(res$changes$objects$added, c("x", "y"))
  expect_equal(res$changes$objects$lines, c("+ x <integer length 3>", "+ y <numeric length 3>"))
  expect_equal(ev_of(res, "source")[[2]]$text, "x")
})

test_that("warnings and messages are captured in order and muffled without tee", {
  e = new.env()
  code = paste("message('m1')", "f = function() warning('w1'); f()", "cat('o1\\n')",
               "message('m2')", sep = "\n")
  expect_silent({
    res = eval_r(code, e, tee = FALSE)
  })
  types = ev_types(res)
  expect_equal(types[types != "source"], c("message", "warning", "output", "message"))
  w = ev_of(res, "warning")[[1]]
  expect_equal(w$text, "w1")
  expect_equal(w$call, "f()")
})

test_that("an error stops at the first failing expression with a trimmed traceback", {
  e = new.env()
  code = "a1 = 1\nh = function(v) stop('boom: ', v)\ng = function(v) h(v)\ng('z')\na2 = 2"
  res = eval_r(code, e)
  expect_equal(res$status, "error")
  expect_equal(c(res$n_done, res$n_total), c(3L, 5L))
  expect_equal(e$a1, 1)
  expect_false(exists("a2", envir = e, inherits = FALSE))
  err = ev_of(res, "error")[[1]]
  expect_equal(err$message, "boom: z")
  expect_equal(err$call, "h(v)")
  expect_equal(err$line, 4L)
  tb = err$traceback
  expect_match(tb[1], "^ 1: g\\(\"z\"\\)")
  expect_match(tb[2], "^ 2: h\\(v\\) at <gptr>#3")
  expect_match(tb[3], "^ 3: stop\\(\"boom: \", v\\) at <gptr>#2")
  expect_false(any(grepl("eval_frame|withCallingHandlers|handleSimpleError", tb)))
})

test_that("options(warn = 2) turns a model warning into an error result", {
  e = new.env()
  withr::local_options(warn = 0)
  res = eval_r("options(warn = 2); as.integer('x')", e)
  expect_equal(res$status, "error")
  expect_match(ev_of(res, "error")[[1]]$message, "converted from warning")
  expect_equal(res$changes$options, "warn")
})

test_that("q(), readline() and g = q; g() are refused without evaluation", {
  e = new.env()
  codes = c("done = TRUE; q('no')", "done = TRUE; x = readline('?')", "done = TRUE; g = q; g()")
  for (code in codes) {
    res = eval_r(code, e)
    expect_equal(res$status, "blocked")
    expect_equal(res$n_done, 0L)
    expect_false(exists("done", envir = e, inherits = FALSE))
    expect_match(ev_of(res, "error")[[1]]$message, "^Not run: ")
  }
})

test_that("parse errors evaluate nothing", {
  res = eval_r("x = c(1, 2\ny = ]", new.env())
  expect_equal(res$status, "parse_error")
  expect_match(ev_of(res, "error")[[1]]$message, "<gptr>:")
})

test_that("CR LF line ends parse, and query calls print like the console", {
  e = new.env()
  withr::local_options(digits = 7)
  res = eval_r("x = 1\r\ny = 2\r\nx + y", e)
  expect_equal(res$status, "ok")
  expect_equal(res$outputs[[3]], "[1] 3")
  res = eval_r("options('digits')\nsuppressPackageStartupMessages(1 + 1)", e)
  expect_equal(res$outputs, list(c("$digits", "[1] 7"), "[1] 2"))
})

test_that("an infinite recursion becomes an error result instead of escaping", {
  e = new.env()
  res = eval_r("f = function(n) f(n + 1)\nf(1)\nafter = 1", e)
  expect_equal(res$status, "error")
  expect_equal(c(res$n_done, res$n_total), c(1L, 3L))
  err = ev_of(res, "error")[[1]]
  expect_true("stackOverflowError" %in% err$class)
  expect_equal(err$line, 2L)
  expect_false(exists("after", envir = e, inherits = FALSE))
})

test_that("sinks, options, hooks and the time limit are restored after errors and interrupts", {
  e = new.env()
  n_sink = sink.number()
  width = getOption("width")
  hooks = length(getHook("before.plot.new"))
  conns = nrow(showConnections())
  res1 = eval_r("sink(tempfile()); cat('into user sink\\n'); stop('after sink')", e)
  expect_equal(res1$status, "error")
  res2 = eval_r("sink(); cat('after pop\\n')", e)
  expect_match(ev_of(res2, "output")[[1]]$text, "after pop")
  interrupt = "signalCondition(structure(class = c('interrupt', 'condition'), list()))"
  res3 = eval_r(paste0("a1 = 1\n", interrupt, "\na2 = 2"), e)
  expect_equal(res3$status, "interrupt")
  expect_true(is.numeric(res3$interrupted_after))
  expect_true(exists("a1", envir = e, inherits = FALSE))
  expect_false(exists("a2", envir = e, inherits = FALSE))
  expect_true("interrupt" %in% ev_types(res3))
  expect_equal(sink.number(), n_sink)
  expect_equal(getOption("width"), width)
  expect_length(getHook("before.plot.new"), hooks)
  expect_equal(nrow(showConnections()), conns)
})

test_that("session-state changes are reported by name, never by value", {
  e = new.env()
  withr::local_dir(getwd())
  withr::local_envvar(GPTR_P09_TEST = NA)
  withr::local_options(digits = 7)
  wd = getwd()
  code = sprintf("options(digits = 3); setwd('%s'); Sys.setenv(GPTR_P09_TEST = 'sekret')",
                 gsub("\\\\", "/", tempdir()))
  res = eval_r(code, e)
  expect_equal(res$changes$options, "digits")
  expect_equal(unname(res$changes$wd["from"]), wd)
  expect_equal(res$changes$envvars, "GPTR_P09_TEST")
  expect_false(grepl("sekret", paste(unlist(res$changes), collapse = " ")))
})

test_that("R's lazily set TZDIR is not reported as a change", {
  a = list(wd = "/a", options = list(), envvars = c(HOME = "/h"), search = "x", ns = "base",
           devices = NULL)
  b = a
  b$envvars = c(HOME = "/h", TZDIR = "/usr/share/zoneinfo")
  expect_equal(eval_state_diff(a, b)$envvars, character())
  b$envvars = c(HOME = "/h2")
  expect_equal(eval_state_diff(a, b)$envvars, "HOME")
})

test_that("a timeout stops a busy loop with status timeout", {
  res = eval_r("i = 0\nrepeat { i = i + 1 }", new.env(), timeout = 1)
  expect_equal(res$status, "timeout")
  expect_lt(res$elapsed, 10)
  expect_match(ev_of(res, "error")[[1]]$message, "^Timed out after 1s")
})

test_that("a plot yields one 768x512 PNG image block and no Rplots.pdf", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  dev = grDevices::dev.cur()
  res = eval_r("plot(1:10)", new.env())
  expect_length(res$images, 1L)
  expect_equal(c(res$images[[1]]$width, res$images[[1]]$height), c(768L, 512L))
  expect_equal(res$images[[1]]$mime, "image/png")
  expect_equal(res$images[[1]]$source, "plot")
  p = ev_of(res, "plot")[[1]]
  expect_true(p$attached)
  expect_true(file.exists(p$path))
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
  expect_equal(grDevices::dev.cur(), dev)
})

test_that("a 50-plot loop attaches 3 images and keeps the rest in one out entry", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("for (i in 1:50) plot(i)", new.env())
  expect_length(res$images, 3L)
  plots = ev_of(res, "plot")
  expect_length(plots, 50L)
  expect_equal(sum(vapply(plots, function(p) isTRUE(p$attached), NA)), 3L)
  ids = unique(vapply(plots[4:50], function(p) p$out_id, ""))
  expect_length(ids, 1L)
  stored = out_get(ids)
  expect_length(stored, 47L)
  expect_match(stored[1], "^plot 4: .*gptr-plot-[0-9a-f]+\\.png$")
})

test_that("a plot finished by low-level calls in later expressions is one image", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("plot(1:10)\nabline(h = 5)\nlines(10:1)\npoints(3, 3)", new.env())
  expect_length(res$images, 1L)
  expect_length(ev_of(res, "plot"), 1L)
})

test_that("a plotting evaluation under Rscript leaves no Rplots.pdf in the working directory", {
  skip_on_cran()
  dir = withr::local_tempdir()
  script = file.path(dir, "plot.R")
  writeLines(c(
    tracemem_loader(),
    "ev = get('eval_r', envir = asNamespace('gptr'))",
    "res = ev('plot(1:10); hist(rnorm(5))', new.env())",
    "cat(res$status, length(res$images), '\\n')"
  ), script)
  libs = paste(.libPaths(), collapse = .Platform$path.sep)
  out = processx::run(rscript_path(), c("--vanilla", script), wd = dir, error_on_status = FALSE,
                      env = c("current", R_LIBS = libs))
  expect_equal(out$status, 0L)
  expect_match(out$stdout, "ok 2")
  expect_false(file.exists(file.path(dir, "Rplots.pdf")))
})

test_that("the gptr shim reaches gptr:: when gptr is not visible from envir", {
  e = new.env(parent = baseenv())
  res = eval_r("r = gptr_return(5)", e)
  expect_equal(res$status, "ok")
  expect_equal(e$r, 5)
})

test_that("an evaluation with an agent stream leaves .Random.seed identical (IC-61)", {
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  st1 = new.env()
  st1$id = "s0123456789"
  e1 = new.env()
  res = eval_r("x = stats::runif(3)", e1, rng = st1)
  expect_equal(res$status, "ok")
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  st2 = new.env()
  st2$id = "s0123456789"
  e2 = new.env()
  eval_r("x = stats::runif(3)", e2, rng = st2)
  expect_identical(e1$x, e2$x)
})

test_that("arguments are validated", {
  expect_error(eval_r(1, new.env()), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", list()), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", new.env(), plots = "maybe"), class = "gptr_error_invalid_argument")
  expect_error(eval_r("1", new.env(), rng = list()), class = "gptr_error_invalid_argument")
})
```

Append to `tests/testthat/test-copy-eval.R`:

```r
test_that("evaluation at top level and in globalenv() from a function edits in place", {
  expect_no_copy(with_ev("big = runif(5e6)"),
                 'invisible(eval_r("n = 1L; length(big)", globalenv()))', label = "top level")
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    'f = function(d) { eval_r("n = 1L; length(big)", globalenv()); invisible(NULL) }; f(big)',
    label = "globalenv from a function"
  )
})

test_that("evaluation in a function-frame home edits in place (G3 fact-check, IC-67)", {
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    'f = function(d) { eval_r("n = 1L; length(d)", environment()); invisible(NULL) }; f(big)',
    label = "function-frame home"
  )
  rich = paste0("head(d); summary(d); x = d[1:5]; plot(d[1:10]); message(length(d)); ",
                "warning('w'); d")
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    sprintf('f = function(d) { eval_r("%s", environment()); invisible(NULL) }; f(big)', rich),
    label = "function-frame home: print, plot, message, warning"
  )
  expect_no_copy(
    with_ev("big = runif(5e6); st = new.env(); st$id = 'agent'"),
    paste0('f = function(d) { eval_r("x = stats::runif(2) + length(d)", environment(), ',
           "rng = st); invisible(NULL) }; f(big)"),
    label = "function-frame home with an agent RNG stream"
  )
})

test_that("results aliasing a user object are cleared in place (R8, IC-67)", {
  expect_no_copy(with_ev("big = runif(5e6)"), 'invisible(eval_r("big", globalenv()))',
                 label = "symbol printed by name")
  expect_no_copy(with_ev("big = runif(5e6)"), 'invisible(eval_r("(big)", globalenv()))',
                 label = "(x)")
  expect_no_copy(with_ev("big = runif(5e6)"),
                 "invisible(eval_r('get(\"big\")', globalenv()))", label = "get(\"x\")")
  expect_no_copy(with_ev("L = list(a = runif(5e6))"), 'invisible(eval_r("L$a", globalenv()))',
                 edit = "L$a[1] = 0", object = "L$a", label = "L$a")
  expect_no_copy(with_ev("x = list(a = runif(5e6))"),
                 "invisible(eval_r('x[[\"a\"]]', globalenv()))",
                 edit = "x[['a']][1] = 0", object = "x[['a']]", label = "x[[\"a\"]]")
})

test_that("an S4 slot result adds no copy to R's own slot-edit copy", {
  setup = with_ev("setClass('B', representation(v = 'numeric')); x = new('B', v = runif(5e6))")
  base = expect_no_copy(setup, "invisible(NULL)", edit = "x@v[1] = 0", object = "x@v",
                        allow = 1L, label = "x@slot baseline")
  expect_no_copy(setup, "invisible(eval_r('x@v', globalenv()))", edit = "x@v[1] = 0",
                 object = "x@v", allow = base, label = "x@slot")
})

test_that("an error at top level after reading the object leaves it in place", {
  expect_no_copy(with_ev("big = runif(5e6)"),
                 "invisible(eval_r(\"n = length(big); stop('boom')\", globalenv()))",
                 label = "error after reading")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-core|copy-eval")'
```

Expected: `[ FAIL 35 | WARN 0 | SKIP 0 | PASS 23 ]`: in `test-eval-core.R` the 19 new tests fail (17 error with `could not find function "eval_r"` or `"eval_state_diff"`, the argument test records 4 failures, the Rscript test 2 failures) while the 17 RNG expectations and the Rplots check pass; in `test-copy-eval.R` 12 new rows fail with `the script did not finish` while the 4 earlier rows and the S4 baseline pass.

- [ ] **Step 3: Write the implementation**

Append to `R/eval-core.R`:

```r
#' Top-level calls whose value is always invisible: evaluated without withVisible(). Calls whose
#' query form prints at the console (options("digits"), library(), suppress*(x)) are not listed.
#' @noRd
eval_invisible_heads = c(
  "=", paste0("<", "-"), "<<-", "invisible", "for", "while", "repeat", "require", "print",
  "cat", "message", "set.seed", "rm", "setwd", "stopifnot"
)

#' Graphics hooks used for plot capture
#' @noRd
eval_hook_names = c("before.plot.new", "before.grid.newpage", "persp")

#' Monotonic seconds (04 section 1.2)
#' @noRd
eval_now = function() {
  as.numeric(proc.time()[["elapsed"]])
}

#' Evaluate model-written R code in the live session
#'
#' The built-in `evaluator` record `r` (IC-69). Parses `code` with `srcfilecopy("<gptr>", ...)`,
#' applies the static guard and the `gptr::` shim, evaluates the top-level expressions one by
#' one in `envir` with output, message, warning and error capture, plot capture and a time
#' limit, stops at the first error and returns a `gptr_eval_result` (04 section 5.8). Never
#' keeps the value of an evaluation (R8). Copy-safety: rules R1, R2, R3 and R8.
#' @param code R code: one string, possibly several expressions.
#' @param envir The evaluation environment (the run's `run_eval_env()`).
#' @param timeout Seconds, or NULL: none with a human present, else `gptr.r_timeout`.
#' @param plots "auto", "capture" or "none" (see plot_begin()).
#' @param tee Also show the output to the user (split sink).
#' @param budget_tokens Output budget; image tokens count against it (IC-67).
#' @param guard Apply eval_guard().
#' @param rng NULL, or an environment with the agent's L'Ecuyer state (see rng_swap()).
#' @param record Collect the printed output of each top-level expression (`outputs`).
#' @param max_images Plots attached as images; the rest go to the out store (IC-67).
#' @return A `gptr_eval_result`.
#' @noRd
eval_r = function(code, envir, timeout = NULL, plots = c("auto", "capture", "none"),
                  tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"),
                  guard = TRUE, rng = NULL, record = TRUE,
                  max_images = gptr_opt("r_max_images")) {
  check_string(code, "code", empty = TRUE)
  check_env(envir, "envir")
  plot_mode = check_choice(plots, c("auto", "capture", "none"), "plots")
  check_number(timeout, "timeout", min = 0, null = TRUE)
  check_flag(tee, "tee")
  check_number(budget_tokens, "budget_tokens", min = 1)
  check_flag(guard, "guard")
  check_env(rng, "rng", null = TRUE)
  check_flag(record, "record")
  check_number(max_images, "max_images", min = 0, int = TRUE)
  st = eval_state_new(as_utf8(code), timeout, plot_mode, tee, budget_tokens, guard, record,
                      max_images)
  st$envir = envir
  on.exit(eval_close(st), add = TRUE)
  state0 = eval_session_state()
  if (is.null(rng)) eval_run(st) else rng_swap(rng, eval_run(st))
  eval_result(st, state0)
}

#' The mutable state of one evaluation (holds `envir` only in the binding st$envir)
#' @noRd
eval_state_new = function(code, timeout, plots, tee, budget, guard, record, max_images) {
  st = new.env(parent = emptyenv())
  human = gptr_has_human()
  st$code = code
  st$human = human
  st$timeout = if (is.null(timeout)) (if (human) Inf else gptr_opt("r_timeout")) else timeout
  st$t0 = eval_now()
  st$deadline = if (is.finite(st$timeout)) st$t0 + st$timeout else Inf
  st$plots = plots
  st$tee = tee
  st$budget = budget
  st$guard = guard
  st$record = record
  st$max_images = as.integer(max_images)
  st$events = list()
  st$status = "ok"
  st$n_done = 0L
  st$n_total = 0L
  st$outputs = list()
  st$assigned = character()
  st$images = list()
  st$objects = NULL
  st$interrupted_after = NULL
  st$line = NA_integer_
  st$catch_interrupt = is.null(run_current())
  st$restored = FALSE
  st
}

#' Append an event
#' @noRd
eval_push = function(st, type, ...) {
  st$events[[length(st$events) + 1L]] = list(type = type, ...)
  invisible()
}

#' Parse with source references under the file name "<gptr>" (CR LF and CR line ends become LF);
#' an error object on failure
#' @noRd
eval_parse = function(code) {
  code = gsub("\r\n?", "\n", code)
  lines = strsplit(code, "\n", fixed = TRUE)[[1L]]
  tryCatch(parse(text = code, keep.source = TRUE, srcfile = srcfilecopy("<gptr>", lines)),
           error = function(e) e)
}

#' Parse, guard, shim, evaluate, restore; results land in `st`
#' @noRd
eval_run = function(st) {
  force(st)
  parsed = eval_parse(st$code)
  if (inherits(parsed, "error")) {
    eval_push(st, "error", message = conditionMessage(parsed), call = NULL,
              class = "parse_error", line = NA_integer_, timeout = FALSE,
              traceback = character())
    st$status = "parse_error"
    return(invisible(st))
  }
  st$n_total = length(parsed)
  st$outputs = rep(list(character()), st$n_total)
  if (!st$n_total) return(invisible(st))
  if (st$guard) {
    g = eval_guard(parsed)
    if (!is.null(g$reason)) {
      eval_push(st, "error", message = g$reason, call = NULL, class = "gptr_blocked",
                line = NA_integer_, timeout = FALSE, traceback = character())
      st$status = "blocked"
      return(invisible(st))
    }
  }
  exprs = gptr_shim(parsed, st$envir)
  st$assigned = eval_assign_targets(exprs)
  snap0 = env_snapshot_rows(st$envir, NULL, sizes = FALSE)
  eval_open(st)
  if (st$catch_interrupt) eval_loop_catch(st, exprs) else eval_loop(st, exprs)
  eval_finish(st)
  snap1 = env_snapshot_rows(st$envir, NULL, sizes = FALSE)
  st$objects = eval_objects(snap0, snap1, st$assigned)
  invisible(st)
}

#' Harness options, the anonymous-file sink and plot capture (undone by eval_restore())
#' @noRd
eval_open = function(st) {
  force(st)
  st$old_opts = options(max.print = 1000L, width = 100L, rlang_interactive = FALSE,
                        cli.dynamic = FALSE, cli.num_colors = 1L, askYesNo = eval_no_ask)
  st$con = file("", "w+b")
  sink(st$con, split = st$tee)
  st$sink_n = sink.number()
  st$old_try = options(try.outFile = st$con)
  st$ps = plot_begin(st$plots, st$human)
  st$hook = eval_plot_hook(st)
  for (h in eval_hook_names) setHook(h, st$hook, "append")
  invisible(st)
}

#' The askYesNo option during an evaluation: the agent cannot ask through askYesNo() (a trap
#' for package code such as install.packages())
#' @noRd
eval_no_ask = function(...) {
  stop("askYesNo() is not available to the agent; use the ask tool.", call. = FALSE)
}

#' The plot hook; a closure that holds only `st`
#' @noRd
eval_plot_hook = function(st) {
  force(st)
  function(...) eval_on_plot_new(st)
}

#' Hook body: enable the display list on new devices, capture the finished page
#' @noRd
eval_on_plot_new = function(st) {
  plot_enable_new(st$ps)
  eval_capture_plot(st, FALSE)
}

#' Capture a plot and record its event after the output printed before it
#' @noRd
eval_capture_plot = function(st, incomplete) {
  if (is.null(st$ps) || !plot_capture(st$ps, incomplete)) return(invisible(FALSE))
  eval_flush(st)
  eval_push(st, "plot", index = st$ps$n, path = NULL, attached = FALSE, out_id = NULL)
  invisible(TRUE)
}

#' Read what the sink captured since the last read (recovers a popped sink or a closed file)
#' @noRd
eval_read_sink = function(st) {
  if (is.null(st$con)) return(NULL)
  if (!tryCatch(isOpen(st$con), error = function(e) FALSE)) {
    st$con = file("", "w+b")
    options(try.outFile = st$con)
  }
  if (sink.number() < st$sink_n) {
    sink(st$con, split = st$tee)
    st$sink_n = sink.number()
  }
  bytes = raw()
  repeat {
    b = readBin(st$con, "raw", n = 65536L)
    if (!length(b)) break
    bytes = c(bytes, b)
  }
  if (!length(bytes)) return(NULL)
  raw_to_utf8(bytes[bytes != as.raw(0L)])
}

#' Move captured output into an `output` event (merged with a preceding output event)
#' @noRd
eval_flush = function(st) {
  txt = eval_read_sink(st)
  if (is.null(txt) || !nzchar(txt)) return(invisible())
  n = length(st$events)
  if (n && identical(st$events[[n]]$type, "output")) {
    st$events[[n]]$text = paste0(st$events[[n]]$text, txt)
  } else {
    eval_push(st, "output", text = txt)
  }
  invisible()
}

#' Evaluate the expressions in order; stop at the first failure
#' @noRd
eval_loop = function(st, exprs) {
  force(st)
  force(exprs)
  srcrefs = attr(exprs, "srcref")
  for (i in seq_along(exprs)) {
    res = eval_one(st, exprs[[i]], i, srcrefs[[i]])
    if (!isTRUE(res)) {
      st$status = res
      break
    }
    st$n_done = i
  }
  invisible(st)
}

#' Outside a run nobody else handles interrupts: catch them here (status "interrupt")
#' @noRd
eval_loop_catch = function(st, exprs) {
  force(st)
  force(exprs)
  tryCatch(eval_loop(st, exprs), interrupt = function(cnd) eval_interrupted(st))
}

#' Record an interrupt that ended the evaluation
#' @noRd
eval_interrupted = function(st) {
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (is.null(st$interrupted_after)) st$interrupted_after = eval_now() - st$t0
  st$status = "interrupt"
  invisible(st)
}

#' Evaluate one top-level expression with calling handlers created here (this frame holds `st`,
#' never `envir`); TRUE, or "error"/"timeout" through the gptr_stop restart
#' @noRd
eval_one = function(st, expr, i, sref) {
  force(st)
  force(expr)
  force(i)
  force(sref)
  st$line = if (is.null(sref)) NA_integer_ else as.integer(sref[1L])
  eval_push(st, "source", text = paste(as.character(sref), collapse = "\n"), line = st$line)
  start = length(st$events)
  if (is.finite(st$deadline)) {
    remaining = st$deadline - eval_now()
    if (remaining <= 0) {
      eval_push(st, "error",
                message = sprintf("Timed out after %gs before expression %d of %d.",
                                  st$timeout, i, st$n_total),
                call = NULL, class = "gptr_timeout", line = st$line, timeout = TRUE,
                traceback = character())
      return("timeout")
    }
    setTimeLimit(elapsed = remaining, transient = TRUE)
  }
  res = withRestarts(
    withCallingHandlers(
      eval_one_body(st, expr),
      message = function(cnd) eval_on_message(st, cnd),
      warning = function(cnd) eval_on_warning(st, cnd),
      error = function(cnd) eval_on_error(st, cnd),
      interrupt = function(cnd) eval_on_interrupt(st)
    ),
    gptr_stop = function(why) why
  )
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (inherits(res, "condition")) res = eval_overflow(st, res)
  if (st$record) st$outputs[[i]] = eval_outputs_since(st, start)
  res
}

#' Evaluate, then capture a finished plot and the printed output; TRUE
#' @noRd
eval_one_body = function(st, expr) {
  eval_top(expr, st)
  eval_capture_plot(st, FALSE)
  eval_flush(st)
  TRUE
}

#' The traceback marker: user frames start after this frame
#' @noRd
eval_frame = function(expr, st) {
  eval(expr, st$envir)
}

#' Evaluate one expression and print it like the console; returns the visibility only
#'
#' A symbol is printed by name (`print(<sym>)` evaluated in the environment), assignments and
#' other invisible heads never pass through withVisible(), and a withVisible() result is
#' cleared in place before this frame returns (R8, IC-67).
#' @noRd
eval_top = function(expr, st) {
  if (is.symbol(expr)) {
    eval_frame(call("print", expr), st)
    return(TRUE)
  }
  invisible_head = is.call(expr) && is.symbol(expr[[1L]]) &&
    as.character(expr[[1L]]) %in% eval_invisible_heads
  if (invisible_head) {
    eval_frame(expr, st)
    return(FALSE)
  }
  res = withVisible(eval_frame(expr, st))
  vis = res$visible
  if (vis) eval_print(res$value)
  res[1L] = list(NULL)
  vis
}

#' Print a visible value (S4 objects through show())
#' @noRd
eval_print = function(value) {
  if (isS4(value)) methods::show(value) else print(value)
  invisible(NULL)
}

#' Message handler: record; muffle unless the output is teed to the user
#' @noRd
eval_on_message = function(st, cnd) {
  eval_flush(st)
  eval_push(st, "message", text = conditionMessage(cnd))
  if (!st$tee) tryInvokeRestart("muffleMessage")
  invisible()
}

#' Warning handler: record; under options(warn = 2) R turns the warning into an error next
#' @noRd
eval_on_warning = function(st, cnd) {
  w = getOption("warn", 0)
  if (w >= 2 || w < 0) return(invisible())
  eval_flush(st)
  eval_push(st, "warning", text = conditionMessage(cnd),
            call = eval_call_text(conditionCall(cnd)))
  if (!st$tee) tryInvokeRestart("muffleWarning")
  invisible()
}

#' Error handler: traceback first (as text), record, stop through gptr_stop
#'
#' An infinite recursion leaves a handler almost no stack (a tryCatch() inside it fails again
#' with "evaluation nested too deeply"), so a stack overflow unwinds first and is recorded by
#' eval_overflow() at the normal depth.
#' @noRd
eval_on_error = function(st, cnd) {
  if (inherits(cnd, "stackOverflowError")) invokeRestart("gptr_stop", cnd)
  tb = eval_traceback()
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  eval_capture_plot(st, TRUE)
  eval_flush(st)
  to = eval_is_timeout(st, cnd)
  msg = if (to) {
    sprintf("Timed out after %gs (limit set by the harness).", st$timeout)
  } else {
    conditionMessage(cnd)
  }
  eval_push(st, "error", message = msg, call = eval_call_text(conditionCall(cnd)),
            class = class(cnd), line = st$line, timeout = to,
            traceback = if (to) character() else tb)
  invokeRestart("gptr_stop", if (to) "timeout" else "error")
}

#' Record a stack overflow after the restart unwound the recursion (R >= 4.2 classes); "error"
#' @noRd
eval_overflow = function(st, cnd) {
  eval_flush(st)
  eval_push(st, "error", message = conditionMessage(cnd), call = NULL, class = class(cnd),
            line = st$line, timeout = FALSE, traceback = character())
  "error"
}

#' Interrupt handler: record and decline, so the run's interrupt policy decides
#' @noRd
eval_on_interrupt = function(st) {
  if (is.null(st$interrupted_after)) st$interrupted_after = eval_now() - st$t0
  eval_flush(st)
  eval_push(st, "interrupt", message = "Interrupted by the user.",
            seconds = st$interrupted_after)
  invisible()
}

#' Is `cl` the evaluator's own `eval(expr, st$envir)` call? (source references ignored)
#' @noRd
eval_is_own_call = function(cl) {
  is.call(cl) && identical(as.call(as.list(cl)), quote(eval(expr, st$envir)))
}

#' Deparsed condition call, or NULL for the evaluator's own eval() call
#' @noRd
eval_call_text = function(cl) {
  if (is.null(cl) || eval_is_own_call(cl)) return(NULL)
  paste(deparse(cl, nlines = 1L, width.cutoff = 500L), collapse = "")
}

#' Did the harness time limit end the expression?
#' @noRd
eval_is_timeout = function(st, cnd) {
  if (!is.finite(st$deadline) || !inherits(cnd, "simpleError")) return(FALSE)
  msgs = unique(c("reached elapsed time limit", "reached CPU time limit",
                  gettext("reached elapsed time limit", domain = "R"),
                  gettext("reached CPU time limit", domain = "R")))
  any(vapply(msgs, grepl, NA, x = conditionMessage(cnd), fixed = TRUE))
}

#' Traceback lines of the current error: the user frames after eval_frame(), before the handler
#'
#' Returns text only, so no call object (which may carry values inlined by do.call()) is left in
#' the handler frame that the restart unwinds.
#' @noRd
eval_traceback = function() {
  calls = sys.calls()
  n = length(calls)
  mark = 0L
  hand = n
  for (k in seq_len(n)) {
    fn = sys.function(k)
    if (identical(fn, eval_frame)) mark = k
    if (mark > 0L && identical(fn, eval_on_error)) {
      hand = k
      break
    }
  }
  if (!mark || hand - 2L <= mark) return(character())
  calls = calls[seq.int(mark + 1L, hand - 2L)]
  while (length(calls) && eval_is_own_call(calls[[1L]])) calls = calls[-1L]
  while (length(calls) && eval_is_internal(calls[[length(calls)]])) {
    calls = calls[-length(calls)]
  }
  eval_format_calls(calls)
}

#' Is `cl` a condition-system frame (trimmed from the end of a traceback)?
#' @noRd
eval_is_internal = function(cl) {
  internal = c(".handleSimpleError", ".signalSimpleWarning", "signalCondition", "withRestarts",
               "withOneRestart", "doWithOneRestart", "signal_abort", "withCallingHandlers")
  f = if (is.call(cl)) cl[[1L]] else NULL
  nm = ""
  if (is.symbol(f)) {
    nm = as.character(f)
  } else if (is.call(f) && length(f) == 3L) {
    nm = as.character(f[[3L]])
  }
  nm %in% internal
}

#' Traceback lines: at most 20 frames (the first 5, the last 15), 120 characters each, with
#' "at <gptr>#<line>" locations from source references
#' @noRd
eval_format_calls = function(calls, max_calls = 20L, width = 120L) {
  n = length(calls)
  if (!n) return(character())
  keep = if (n > max_calls) c(seq_len(5L), seq.int(n - max_calls + 6L, n)) else seq_len(n)
  out = character()
  for (i in keep) {
    cl = calls[[i]]
    txt = paste(deparse(cl, width.cutoff = 500L, nlines = 2L), collapse = " ")
    if (nchar(txt) > width) txt = paste0(substr(txt, 1L, width - 3L), "...")
    sr = attr(cl, "srcref")
    loc = ""
    if (!is.null(sr)) {
      sf = attr(sr, "srcfile")
      fname = if (!is.null(sf$filename) && nzchar(sf$filename)) basename(sf$filename) else "<code>"
      loc = sprintf(" at %s#%d", fname, sr[1L])
    }
    out[length(out) + 1L] = sprintf("%2d: %s%s", i, txt, loc)
    if (n > max_calls && i == 5L) {
      out[length(out) + 1L] = sprintf("    ... %d frames omitted ...", n - max_calls)
    }
  }
  out
}

#' Printed output lines of the events after position `start` (cleaned, empty lines dropped)
#' @noRd
eval_outputs_since = function(st, start) {
  ev = st$events
  if (length(ev) <= start) return(character())
  txt = character()
  for (k in seq.int(start + 1L, length(ev))) {
    if (identical(ev[[k]]$type, "output")) txt = c(txt, ev[[k]]$text)
  }
  if (!length(txt)) return(character())
  out = clean_terminal(paste(txt, collapse = ""))
  out[nzchar(out)]
}

#' Final capture, restore the session, render the plots (normal and restart paths)
#' @noRd
eval_finish = function(st) {
  eval_capture_plot(st, TRUE)
  eval_flush(st)
  eval_restore(st)
  eval_plots_done(st)
  invisible(st)
}

#' Undo everything eval_open() did; idempotent, safe on every exit path
#' @noRd
eval_restore = function(st) {
  if (isTRUE(st$restored)) return(invisible())
  st$restored = TRUE
  setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
  if (!is.null(st$hook)) {
    for (h in eval_hook_names) {
      hs = getHook(h)
      keep = !vapply(hs, identical, NA, st$hook)
      setHook(h, hs[keep], "replace")
    }
    st$hook = NULL
  }
  if (!is.null(st$con)) {
    while (sink.number() >= st$sink_n && sink.number() > 0L) sink()
    if (!is.null(st$old_try)) options(st$old_try)
    if (tryCatch(isOpen(st$con), error = function(e) FALSE)) close(st$con)
    st$con = NULL
  }
  if (!is.null(st$old_opts)) options(st$old_opts)
  plot_close(st$ps)
  invisible()
}

#' on.exit() of eval_r(): restore with interrupts suspended and drop the home reference (R2)
#' @noRd
eval_close = function(st) {
  suspendInterrupts({
    eval_restore(st)
    st$envir = NULL
  })
  invisible()
}

#' The session whose run is evaluating, or NULL
#'
#' 04 section 7.6 types `gptr_run$session` as an id and the kernel SDK has no id-to-session
#' accessor; the run's `shell` binding (the session object, when P06 provides it) is read
#' defensively. Without it the process out store is used and no context pressure is assumed.
#' @noRd
eval_session = function() {
  run = run_current()
  if (!is.environment(run)) return(NULL)
  s = get0("shell", envir = run, inherits = FALSE)
  if (inherits(s, "gptr_session")) s else NULL
}

#' The out store of the running session (its live record), or NULL for the process store
#' @noRd
eval_out_target = function() {
  s = eval_session()
  if (is.null(s)) return(NULL)
  live = session_live(s)
  if (is.environment(live) && exists("out", envir = live, inherits = FALSE)) live else NULL
}

#' Render the captured plots; attach the first ones and store the rest in one out entry
#'
#' At most `max_images` plots are attached, and fewer when their image tokens would take more
#' than 60% of the output budget (IC-67); the paths of the others are kept in the session's out
#' store for `peter$plot(k)` (P10), one entry for the whole evaluation.
#' @noRd
eval_plots_done = function(st) {
  if (is.null(st$ps) || !st$ps$n) return(invisible())
  w = gptr_opt("plot_width")
  h = gptr_opt("plot_height")
  files = plot_render_all(st$ps, 50L, w, h, gptr_opt("plot_res"))
  per = est_image_tokens(w, h)
  k_max = min(st$max_images, max(1L, floor(0.6 * st$budget / per)))
  stored = integer()
  for (j in seq_along(st$events)) {
    ev = st$events[[j]]
    if (!identical(ev$type, "plot")) next
    f = if (ev$index <= length(files)) files[ev$index] else NA_character_
    if (is.na(f)) next
    ev$path = f
    if (length(st$images) < k_max) {
      st$images[[length(st$images) + 1L]] = plot_block(f, w, h)
      ev$attached = TRUE
    } else {
      stored = c(stored, j)
    }
    st$events[[j]] = ev
  }
  if (length(stored)) {
    idx = vapply(st$events[stored], function(e) e$index, 1L)
    paths = vapply(st$events[stored], function(e) e$path, "")
    id = out_put(sprintf("plot %d: %s", idx, paths), meta = list(
      kind = "plots", index = idx, path = paths, width = w, height = h
    ), session = eval_out_target())
    for (j in stored) st$events[[j]]$out_id = id
  }
  invisible()
}

#' Object changes of an evaluation with their model-facing lines
#' @noRd
eval_objects = function(old, new, assigned) {
  d = env_diff(old, new, assigned)
  i = match(d$added, new$name)
  add = character()
  if (length(i)) add = sprintf("+ %s <%s>", d$added, trimws(paste(new$class[i], new$shape[i])))
  j = match(d$modified, new$name)
  mod = character()
  if (length(j)) {
    cls = ifelse(is.na(new$class[j]), new$kind[j], new$class[j])
    mod = sprintf("~ %s <%s> modified", d$modified, cls)
  }
  rem = if (length(d$removed)) sprintf("- %s removed", d$removed) else character()
  c(d, list(lines = c(add, mod, rem)))
}

#' Session-wide state compared before and after an evaluation (kept in memory only)
#' @noRd
eval_session_state = function() {
  list(wd = getwd(), options = options(), envvars = Sys.getenv(), search = search(),
       ns = loadedNamespaces(), devices = grDevices::dev.list())
}

#' Differences of eval_session_state(): option and variable names (never values), the working
#' directory, attached and loaded packages, devices. `TZDIR` appearing is not reported: R sets
#' it itself the first time a time is formatted (macOS), also during gptr's own plot handling.
#' @noRd
eval_state_diff = function(a, b) {
  on = union(names(a$options), names(b$options))
  opt = on[!vapply(on, function(n) identical(a$options[[n]], b$options[[n]]), NA)]
  en = union(names(a$envvars), names(b$envvars))
  env = en[!vapply(en, function(n) identical(a$envvars[n], b$envvars[n]), NA)]
  if (!("TZDIR" %in% names(a$envvars))) env = setdiff(env, "TZDIR")
  wd = if (identical(a$wd, b$wd)) NULL else c(from = a$wd, to = b$wd)
  devices = NULL
  if (!identical(a$devices, b$devices)) {
    devices = list(from = names(a$devices), to = names(b$devices))
  }
  list(wd = wd, options = opt, envvars = env, attached = setdiff(b$search, a$search),
       loaded = setdiff(b$ns, a$ns), devices = devices)
}

#' Assemble the gptr_eval_result (04 section 5.8); `changes$objects` carries the object diff
#' @noRd
eval_result = function(st, state0) {
  ch = eval_state_diff(state0, eval_session_state())
  ch$objects = st$objects %||%
    list(added = character(), modified = character(), removed = character(),
         lines = character())
  structure(
    list(status = st$status, events = st$events, n_done = st$n_done, n_total = st$n_total,
         changes = ch, elapsed = eval_now() - st$t0, images = st$images,
         assigned = st$assigned, outputs = st$outputs, spill = NULL, out_id = NULL,
         interrupted_after = st$interrupted_after),
    class = "gptr_eval_result"
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-core|copy-eval")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 133 ]` (116 in `test-eval-core.R`, 17 copy rows). The plot tests skip without ragg and `capabilities("png")`; the copy rows skip without `capabilities("profmem")`.

- [ ] **Step 5: Commit**

```bash
git add R/eval-core.R tests/testthat/test-eval-core.R tests/testthat/test-copy-eval.R
git commit -m "feat(eval): add the hand-rolled evaluator eval_r()"
```


### Task 9: The model-facing text: `format_eval_result()`

**Files:** Create: `R/eval-format.R`; Test: `tests/testthat/test-eval-format.R`.

The layout of report 12 section 3.4 with the contract's notices (04 section 7.9, IC-67): the events in order (output and messages cleaned by P01's `clean_terminal()`, `Warning in <call>: ...`, `Error in <call>: ...  [expression at line n]` with `Traceback (outermost first):`, `[interrupted by the user after s s; side effects may have occurred]` (the wording of architecture section 6.12), `[plot N attached]`), then `[plots 4-50 not attached: peter$plot(k)]`, at most 12 object-change lines (`+ markers <data.frame 4,211 x 7>`, `~ pbmc <Seurat> modified`, `- x removed`), the session changes by name and, unless the status is `ok`, a status line. The text is cut by P01's `truncate_output()` (head 40% / tail 60% by lines, the full text in the out store and a spill file, the notice `[... n lines omitted; all: peter$out("<id>")]`) to the budget minus the image tokens; the budget is halved (at least 200) when the running session's last request is above half the compaction threshold, asked through P07's `compact.should` service (G4 section 4.4.5).

**Interfaces:**
- Consumes: Task 8's `eval_session()` and `eval_r()` (tests); P01: `check_class()`, `check_number()`, `clean_terminal()`, `est_image_tokens()`, `truncate_output(text, budget_tokens, class = "r_output", head = 0.4, id_prefix = "o")`, `ext_service_has()`, `ext_service_get()`, `out_get()` (tests); P06 kernel SDK: `session_data(s)` (`$usage`, the 04 section 4.3 rows); P07 service `compact.should` = `function(s, tokens, idle_s) lgl(1)` (absent: no halving).
- Produces (04 section 7.9): `format_eval_result(res, budget_tokens)` -> `list(text = chr(1), images = list, truncated = lgl(1), out_id = chr(1) | NULL, spill = chr(1) | NULL)` (P10's `r` tool); private `eval_budget(budget_tokens, pressure = eval_pressure())`, `eval_pressure(s = eval_session())`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-eval-format.R`:

```r
fake_result = function(events, status = "ok", n_done = 1L, n_total = 1L, changes = list(),
                       images = list()) {
  none = list(added = character(), modified = character(), removed = character(),
              lines = character())
  ch = utils::modifyList(list(wd = NULL, options = character(), envvars = character(),
                              attached = character(), loaded = character(), devices = NULL,
                              objects = none),
                         changes)
  structure(list(status = status, events = events, n_done = n_done, n_total = n_total,
                 changes = ch, elapsed = 0.12, images = images, assigned = character(),
                 outputs = list(), spill = NULL, out_id = NULL, interrupted_after = NULL),
            class = "gptr_eval_result")
}

test_that("events render in order with warnings, errors and a trimmed traceback", {
  events = list(
    list(type = "source", text = "f()", line = 1L),
    list(type = "output", text = "hello\n\033[31mred\033[0m\n"),
    list(type = "message", text = "note\n"),
    list(type = "warning", text = "careful", call = "f()"),
    list(type = "error", message = "boom", call = "g(v)", line = 3L, timeout = FALSE,
         traceback = c(" 1: f()", " 2: g(v) at <gptr>#2"))
  )
  res = fake_result(events, status = "error", n_done = 2L, n_total = 3L)
  out = format_eval_result(res, 4000L)
  expect_equal(strsplit(out$text, "\n", fixed = TRUE)[[1]], c(
    "hello", "red", "note", "Warning in f(): careful",
    "Error in g(v): boom  [expression at line 3]",
    "Traceback (outermost first):", " 1: f()", " 2: g(v) at <gptr>#2",
    "[status: error; 2 of 3 top-level expressions completed; 0.12s]"
  ))
  expect_false(out$truncated)
  expect_null(out$out_id)
})

test_that("plots, object changes and session changes are listed after the events", {
  plots = lapply(1:5, function(k) {
    list(type = "plot", index = k, path = sprintf("p%d.png", k), attached = k <= 3,
         out_id = if (k > 3) "o1")
  })
  changes = list(
    wd = c(from = "/a", to = "/b"), options = "digits", envvars = "X",
    attached = "package:stats4",
    objects = list(added = "m", modified = "pbmc", removed = character(),
                   lines = c("+ m <data.frame 4,211 x 7>", "~ pbmc <Seurat> modified"))
  )
  out = format_eval_result(fake_result(plots, changes = changes), 4000L)
  expect_equal(strsplit(out$text, "\n")[[1]], c(
    "[plot 1 attached]", "[plot 2 attached]", "[plot 3 attached]",
    "[plots 4-5 not attached: peter$plot(k)]", "+ m <data.frame 4,211 x 7>",
    "~ pbmc <Seurat> modified", "[working directory changed: /a -> /b]",
    "[options changed: digits]", "[environment variables changed: X]",
    "[attached: package:stats4]"
  ))
})

test_that("an interrupt notes that side effects may have occurred", {
  ev = list(list(type = "interrupt", message = "Interrupted by the user.", seconds = 2.34))
  res = fake_result(ev, status = "interrupt", n_done = 1L, n_total = 3L)
  expect_equal(strsplit(format_eval_result(res, 4000L)$text, "\n", fixed = TRUE)[[1]], c(
    "[interrupted by the user after 2.3 s; side effects may have occurred]",
    "[status: interrupt; 1 of 3 top-level expressions completed; 0.12s]"
  ))
})

test_that("blocked and empty results have short texts", {
  err = list(type = "error", message = "Not run: q()", call = NULL, line = NA_integer_,
             timeout = FALSE, traceback = character())
  blocked = fake_result(list(err), status = "blocked", n_done = 0L)
  expect_equal(format_eval_result(blocked, 4000L)$text,
               "Error: Not run: q()\n[status: blocked; nothing was evaluated]")
  expect_equal(format_eval_result(fake_result(list()), 4000L)$text, "[no output]")
})

test_that("long output keeps head and tail with a peter$out() notice", {
  res = eval_r("invisible(lapply(1:5000, function(i) cat('line', i, '\\n')))", new.env())
  out = format_eval_result(res, 400L)
  expect_true(out$truncated)
  expect_true(is.character(out$out_id))
  expect_match(out$text, "^line 1 ")
  expect_match(out$text, "line 5000\\s*$")
  expect_match(out$text, "peter$out(", fixed = TRUE)
  expect_lte(est_tokens(out$text, "r_output"), 420)
  expect_length(out_get(out$out_id), 5000L)
})

test_that("image tokens count against the budget", {
  img = list(type = "image", mime = "image/png", data = "x", source = "plot", width = 768L,
             height = 512L)
  lines = paste(rep("0123456789 abcdefghij", 100), collapse = "\n")
  with_images = format_eval_result(
    fake_result(list(list(type = "output", text = lines)), images = list(img, img)), 1500L
  )
  without = format_eval_result(fake_result(list(list(type = "output", text = lines))), 1500L)
  expect_true(with_images$truncated)
  expect_false(without$truncated)
  expect_length(with_images$images, 2L)
})

test_that("the budget is halved under context pressure", {
  expect_equal(eval_budget(4000L, pressure = TRUE), 2000L)
  expect_equal(eval_budget(4000L, pressure = FALSE), 4000L)
  expect_equal(eval_budget(300L, pressure = TRUE), 200)
  expect_false(eval_pressure(NULL))
})

test_that("format_eval_result validates its arguments", {
  expect_error(format_eval_result(list(), 10), class = "gptr_error_invalid_argument")
  expect_error(format_eval_result(fake_result(list()), 0), class = "gptr_error_invalid_argument")
})

test_that("a 50-plot evaluation lists 3 attached plots and the stored rest", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("for (i in 1:50) plot(i)", new.env())
  out = format_eval_result(res, 4000L)
  lines = strsplit(out$text, "\n", fixed = TRUE)[[1]]
  expect_equal(lines[1:3], c("[plot 1 attached]", "[plot 2 attached]", "[plot 3 attached]"))
  expect_true("[plots 4-50 not attached: peter$plot(k)]" %in% lines)
  expect_length(out$images, 3L)
})

test_that("blank lines of printed output are kept", {
  res = fake_result(list(list(type = "output", text = "a\n\nb\n")))
  expect_equal(format_eval_result(res, 4000L)$text, "a\n\nb")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-format")'
```

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `could not find function "format_eval_result"` (`"eval_budget"`), and the validation test records its two failed `expect_error()` calls.

- [ ] **Step 3: Write the implementation**

Create `R/eval-format.R`:

```r
# eval-format.R -- the model-facing text of an evaluation (P09).
#
# The format of report 12 section 3.4 with the contract's notices (04 section 7.9, IC-67):
# output, messages, warnings, the error with its trimmed traceback, `[plot N attached]`,
# `[plots 4-50 not attached: peter$plot(k)]`, state-change lines (`~ pbmc <Seurat> modified`,
# `+ markers <data.frame 4,211 x 7>`), a status line, then head 40% / tail 60% truncation
# through P01's truncate_output() with the `peter$out(<id>)` notice (about 26 tokens, G5
# fact-check 13). Image tokens count against the budget, and the budget is halved once the
# session's context passes half the compaction threshold (G4 section 4.4.5).

#' Cleaned lines of captured text (ANSI/OSC removed, carriage returns collapsed)
#' @noRd
eval_clean_lines = function(text) {
  if (is.null(text) || !length(text)) return(character())
  lines = clean_terminal(paste(text, collapse = ""))
  if (length(lines) && !nzchar(lines[length(lines)])) lines = lines[-length(lines)]
  lines
}

#' Model-facing lines of one event
#' @noRd
eval_event_text = function(e) {
  type = e$type
  if (type %in% c("output", "message")) return(eval_clean_lines(e$text))
  if (identical(type, "warning")) {
    where = if (is.null(e$call)) "" else paste0(" in ", e$call)
    return(paste0("Warning", where, ": ", paste(eval_clean_lines(e$text), collapse = "\n")))
  }
  if (identical(type, "error")) {
    where = if (is.null(e$call)) "" else paste0(" in ", e$call)
    at = ""
    if (!is.null(e$line) && !is.na(e$line)) at = sprintf("  [expression at line %d]", e$line)
    head = paste0("Error", where, ": ", paste(eval_clean_lines(e$message), collapse = "\n"), at)
    tb = if (length(e$traceback)) c("Traceback (outermost first):", e$traceback) else NULL
    return(c(head, tb))
  }
  if (identical(type, "interrupt")) {
    return(sprintf("[interrupted by the user after %.1f s; side effects may have occurred]",
                   e$seconds %||% 0))
  }
  if (identical(type, "plot") && isTRUE(e$attached)) {
    return(sprintf("[plot %d attached]", e$index))
  }
  character()
}

#' Model-facing lines of the evaluation events, in order
#' @noRd
eval_event_lines = function(res) {
  out = character()
  for (e in res$events) out = c(out, eval_event_text(e))
  out
}

#' Plot notices, state-change lines and the status line appended after the events
#' @noRd
eval_tail_lines = function(res) {
  out = character()
  plots = Filter(function(e) identical(e$type, "plot"), res$events)
  stored = vapply(plots, function(e) !isTRUE(e$attached) && !is.null(e$path), NA)
  if (any(stored)) {
    k = vapply(plots[stored], function(e) as.integer(e$index), 1L)
    out = c(out, if (length(k) == 1L) {
      sprintf("[plot %d not attached: peter$plot(%d)]", k, k)
    } else {
      sprintf("[plots %d-%d not attached: peter$plot(k)]", min(k), max(k))
    })
  }
  lost = vapply(plots, function(e) is.null(e$path), NA)
  if (any(lost)) out = c(out, sprintf("[%d plots not rendered]", sum(lost)))
  obj = res$changes$objects$lines %||% character()
  if (length(obj) > 12L) {
    obj = c(obj[1:12], sprintf("(+ %d more object changes)", length(obj) - 12L))
  }
  out = c(out, obj)
  ch = res$changes
  if (length(ch$wd)) {
    out = c(out, sprintf("[working directory changed: %s -> %s]", ch$wd[["from"]],
                         ch$wd[["to"]]))
  }
  if (length(ch$options)) {
    out = c(out, sprintf("[options changed: %s]", paste(ch$options, collapse = ", ")))
  }
  if (length(ch$envvars)) {
    out = c(out, sprintf("[environment variables changed: %s]",
                         paste(ch$envvars, collapse = ", ")))
  }
  if (length(ch$attached)) {
    out = c(out, sprintf("[attached: %s]", paste(ch$attached, collapse = ", ")))
  }
  if (!identical(res$status, "ok")) {
    out = c(out, if (res$status %in% c("blocked", "parse_error")) {
      sprintf("[status: %s; nothing was evaluated]", res$status)
    } else {
      sprintf("[status: %s; %d of %d top-level expressions completed; %.2fs]", res$status,
              res$n_done, res$n_total, res$elapsed)
    })
  }
  out
}

#' Is the running session's context above half of the compaction threshold?
#'
#' Uses the session's last request (input, cache and output tokens of its last usage row) and
#' the `compact.should` service (P07) at twice that size; FALSE when there is no running
#' session or no service.
#' @noRd
eval_pressure = function(s = eval_session()) {
  if (is.null(s) || !ext_service_has("compact.should")) return(FALSE)
  u = session_data(s)$usage
  if (!is.data.frame(u) || !nrow(u)) return(FALSE)
  last = u[nrow(u), , drop = FALSE]
  tokens = sum(last$input, last$cache_read, last$cache_write_5m, last$cache_write_1h,
               last$output, na.rm = TRUE)
  isTRUE(ext_service_get("compact.should")(s, 2 * tokens, 0))
}

#' The budget in force: halved above half the compaction threshold (at least 200 tokens)
#' @noRd
eval_budget = function(budget_tokens, pressure = eval_pressure()) {
  if (isTRUE(pressure)) max(200, budget_tokens %/% 2) else budget_tokens
}

#' Model text of an evaluation within the token budget (04 section 7.9)
#'
#' @param res A `gptr_eval_result` (04 section 5.8).
#' @param budget_tokens Estimated tokens for the text and the images together.
#' @return list(text = chr(1), images = list of image blocks, truncated = lgl(1),
#'   out_id = chr(1) or NULL, spill = chr(1) or NULL).
#' @noRd
format_eval_result = function(res, budget_tokens) {
  check_class(res, "gptr_eval_result", "res")
  check_number(budget_tokens, "budget_tokens", min = 1)
  budget = eval_budget(budget_tokens)
  image_tokens = 0
  for (b in res$images) {
    image_tokens = image_tokens + est_image_tokens(b$width %||% 768L, b$height %||% 512L)
  }
  lines = c(eval_event_lines(res), eval_tail_lines(res))
  if (!length(lines)) lines = "[no output]"
  parts = strsplit(lines, "\n", fixed = TRUE)
  lines = unlist(lapply(parts, function(x) if (length(x)) x else ""))
  tr = truncate_output(lines, max(200, budget - image_tokens), class = "r_output")
  list(text = tr$text, images = res$images, truncated = isTRUE(tr$truncated),
       out_id = tr$out_id, spill = tr$spill)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval-format")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 27 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/eval-format.R tests/testthat/test-eval-format.R
git commit -m "feat(eval): add the budgeted model text of an evaluation"
```

### Task 10: `builtin:workspace`: context blocks, `r_env`, the evaluator record and the services

**Files:** Modify: `R/env-snapshot.R` (append), `tests/testthat/test-env-snapshot.R` (append).

The built-in of 04 section 7.9 and section 10.3 as amended by IC-38 (`attached` and `skill_content` have `placement = "both"`, so `peter("x", mtcars)` sends `<attached name="mtcars">` after `<workspace>` in its first request) and IC-69/IC-34 (the `evaluator` record `r`; the `eval.r` and `describe` services owned by `builtin:workspace`, so filtering the built-in removes them). Block providers follow the `context_block` contract (04 section 10.2 kind 13): `provide(ctx, budget)` returns `NULL`, a string or `list(text, attrs)`; `ctx$input` is `list(call, turn, prompt, placement, last_hash, opts)`; `.opts$context` `"names"` lists names only and `"none"` omits the blocks. The workspace snapshot of the last block is kept in an environment inside `ctx$state()` (an environment is never JSON-able, so it is not persisted: snapshot addresses mean nothing in another process); an `agent_end` hook refreshes it (only once the workspace block has run, so a `.opts$context = "none"` session pays for no snapshot) so the next `<workspace_changes>` shows only what the user changed between requests; without a session label the `env` attribute is `globalenv` for the global environment and `<environment>` otherwise (04 section 5.1 `home_label`); `session_shutdown` releases the session's history log. Context items are read with P08's `call_value()` [leaf]; a failing describer becomes a one-line note.

**Interfaces:**
- Consumes: Tasks 2-5 and 8 (`env_snapshot()`, `env_diff()`, `workspace_lines()`, `changes_lines()`, `env_tokens()`, `gptr_describe()`, `describe_value()`, `dsc_fit()`, `user_expr_log()`, `user_log_start()`, `user_log_release()`, `r_env_probe()`, `eval_r()`); P01: `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_has(name)`, `ext_service_get(name)`, `setting_get(key, session = NULL, default = NULL)`; P02 (04 sections 6.8, 7.2, 10.5): `gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"), budget = 300L, order = 650L)`, `gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`, `gptr_spec(kind, name, ...)`, `registry_get(kind, name, session = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, the API object's `gptr$register(spec)` and `gptr$on(event, handler, matcher = NULL)`, `gptr_registry(kind = NULL, diagnostics = FALSE)` (tests); P06 kernel SDK: `session_home(s)`, `session_data(s)` (`$id`, `$home_label`); P08 kernel SDK: `call_value(call, i)` on the `gptr_call` bindings `context` (items `list(label, kind, name, slot, facts)`), `envir`, `values`, `ids$skills`; P17 service `skill.body` = `function(name) list(text, dir)` (absent before P17: no block).
- Produces: `builtin_workspace(gptr)` (04 section 7.9); context blocks `workspace` (`first`, order 500, budget 600), `workspace_changes` (`turn`, order 100, budget 300), `attached` (`both`, order 600, budget 1200: 150 per object, at least 60), `skill_content` (`both`, order 700, budget 10000: 5,000 per skill); prompt section `r_env` (T1, order 900, budget 450); `evaluator` record `r` with `eval = eval_r`; services `eval.r` = `function(code, envir, ...)` (the evaluator named by setting `evaluator`, default `"r"`) and `describe` = `function(x, budget = 150L)`; hooks on `agent_end` and `session_shutdown`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-env-snapshot.R`:

```r
# ---------------------------------------------------------------- builtin:workspace

fake_ctx = function(envir = NULL, call = NULL, opts = list()) {
  state = new.env()
  list(session = NULL, envir = envir, state = function() state,
       input = list(call = call, turn = 1L, prompt = "p", placement = "first",
                    last_hash = NULL, opts = opts))
}

fake_call = function(envir, ...) {
  labels = c(...)
  items = lapply(labels, function(l) {
    list(label = l, kind = "symbol", name = l, slot = NULL, facts = list())
  })
  cl = new.env()
  cl$context = items
  cl$envir = envir
  cl$values = new.env()
  cl$ids = list()
  class(cl) = "gptr_call"
  cl
}

test_that("the workspace block lists the environment within its budget", {
  e = new.env()
  e$mt = mtcars
  e$v = 1:10 + 0
  b = env_block_workspace(fake_ctx(e), 600L)
  expect_equal(b$attrs, list(env = "<environment>", objects = "2"))
  expect_equal(env_block_workspace(fake_ctx(globalenv()), 600L)$attrs$env, "globalenv")
  lines = strsplit(b$text, "\n")[[1]]
  expect_equal(lines[1], "mt  data.frame  32 x 11  7 KB")
  expect_match(lines[2], "^v   numeric     length 10  [0-9]+ B$")
  names_only = env_block_workspace(fake_ctx(e, opts = list(context = "names")), 600L)
  expect_equal(names_only$text, "mt, v")
  expect_null(env_block_workspace(fake_ctx(e, opts = list(context = "none")), 600L))
  expect_null(env_block_workspace(fake_ctx(NULL), 600L))
})

test_that("workspace_changes reports what changed since the last block", {
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$a = 1
  e$b = 2
  ctx = fake_ctx(e)
  env_block_workspace(ctx, 600L)
  expect_null(env_block_changes(ctx, 300L))
  e$a = 10
  e$c = data.frame(x = 1:3)
  rm("b", envir = e)
  user_log_push(str2lang("c = data.frame(x = 1:3)"))
  lines = strsplit(env_block_changes(ctx, 300L), "\n")[[1]]
  expect_match(lines[1], "^\\+ c data.frame 3 x 1 [0-9]+ B$")
  expect_equal(lines[-1], c("~ a", "- b", "user ran: c = data.frame(x = 1:3)"))
  expect_null(env_block_changes(ctx, 300L))
})

test_that("the agent_end hook resets the baseline of workspace_changes", {
  e = new.env()
  e$a = 1
  ctx = fake_ctx(e)
  env_block_workspace(ctx, 600L)
  e$made_by_agent = 2
  expect_null(env_on_agent_end(list(type = "agent_end"), ctx))
  expect_null(env_block_changes(ctx, 300L))
  quiet = fake_ctx(e, opts = list(context = "none"))
  expect_null(env_on_agent_end(list(type = "agent_end"), quiet))
  expect_null(env_memory(quiet)$snapshot)
})

test_that("the attached block describes each context object by label", {
  e = new.env()
  e$mt = mtcars
  e$v = c(1.5, 2.5)
  one = env_block_attached(fake_ctx(e, call = fake_call(e, "mt")), 1200L)
  expect_equal(one$attrs, list(name = "mt"))
  expect_match(one$text, "^<data.frame> 32 x 11, 7 KB")
  two = env_block_attached(fake_ctx(e, call = fake_call(e, "mt", "v")), 1200L)
  expect_equal(two$attrs, list(name = "mt, v"))
  expect_match(two$text, "^mt: <data.frame> 32 x 11, 7 KB")
  expect_match(two$text, "\nv: <numeric> length 2")
  names_ctx = fake_ctx(e, call = fake_call(e, "mt"), opts = list(context = "names"))
  hdr = env_block_attached(names_ctx, 1200L)
  expect_equal(hdr$text, "<data.frame> 32 x 11, 7 KB")
  expect_null(env_block_attached(fake_ctx(e, call = fake_call(e)), 1200L))
})

test_that("preloaded skills come from the skill.body service", {
  e = new.env()
  cl = fake_call(e)
  cl$ids = list(skills = "high-performance-r")
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  expect_null(env_block_skills(fake_ctx(e, call = cl), 10000L))
  local_mocked_bindings(
    ext_service_has = function(name) identical(name, "skill.body"),
    ext_service_get = function(name) {
      function(nm) list(text = "# Skill\nUse data.table.", dir = ".")
    }
  )
  b = env_block_skills(fake_ctx(e, call = cl), 10000L)
  expect_equal(b, list(text = "# Skill\nUse data.table.",
                       attrs = list(name = "high-performance-r")))
})

test_that("builtin_workspace registers the blocks, the section, the evaluator and two hooks", {
  got = new.env()
  got$specs = list()
  got$events = character()
  api = list(
    register = function(spec) {
      got$specs[[length(got$specs) + 1L]] = spec
      invisible(NULL)
    },
    on = function(event, handler, matcher = NULL) {
      got$events = c(got$events, event)
      invisible(NULL)
    }
  )
  builtin_workspace(api)
  kinds = vapply(got$specs, function(s) s$kind, "")
  names = vapply(got$specs, function(s) s$name, "")
  blocks = got$specs[kinds == "context_block"]
  expect_equal(names[kinds == "context_block"],
               c("workspace", "workspace_changes", "attached", "skill_content"))
  expect_equal(vapply(blocks, function(s) s$placement, ""), c("first", "turn", "both", "both"))
  expect_equal(vapply(blocks, function(s) as.integer(s$order), 1L), c(500L, 100L, 600L, 700L))
  section = got$specs[[which(kinds == "prompt_section")]]
  expect_equal(c(section$name, section$tier), c("r_env", "T1"))
  expect_equal(as.integer(c(section$order, section$budget)), c(900L, 450L))
  expect_identical(got$specs[[which(kinds == "evaluator")]]$eval, eval_r)
  expect_equal(got$events, c("agent_end", "session_shutdown"))
})

test_that("the eval.r and describe services are registered by builtin:workspace", {
  expect_true(ext_service_has("eval.r"))
  expect_true(ext_service_has("describe"))
  e = new.env()
  res = ext_service_get("eval.r")("z = 2 + 2", envir = e)
  expect_s3_class(res, "gptr_eval_result")
  expect_equal(e$z, 4)
  expect_equal(ext_service_get("describe")(mtcars, 60L)[1], "<data.frame> 32 x 11, 7 KB")
})

test_that("the loaded registry holds the workspace records (P02)", {
  reg = gptr_registry()
  mine = reg[reg$source == "builtin:workspace", , drop = FALSE]
  expect_true(all(c("workspace", "workspace_changes", "attached", "skill_content") %in%
                    mine$name[mine$kind == "context_block"]))
  expect_true("r_env" %in% mine$name[mine$kind == "prompt_section"])
  expect_true("r" %in% mine$name[mine$kind == "evaluator"])
  expect_identical(registry_get("evaluator", "r")$eval, eval_r)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-snapshot")'
```

Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 45 ]`: six new tests error with `could not find function` (`env_block_workspace`, `env_block_attached`, `env_block_skills`, `builtin_workspace`), the service test records two failures and then errors with `gptr_error_not_available` ("The gptr service 'eval.r' is not available"), and the registry test records four failures; the 45 earlier expectations pass.

- [ ] **Step 3: Write the implementation**

Append to `R/env-snapshot.R`:

```r
# ---------------------------------------------------------------- builtin:workspace
# Context blocks of architecture section 7.4-7.5 (IC-38), the `r_env` section, the `evaluator`
# record `r` and the `eval.r` and `describe` services (IC-69, IC-34).

#' The context mode of the call: "summary" (default), "names" or "none" (`.opts$context`)
#' @noRd
env_context_mode = function(ctx) {
  mode = ctx$input$opts$context
  if (is.character(mode) && length(mode) == 1L && mode %in% c("summary", "names", "none")) {
    return(mode)
  }
  "summary"
}

#' The environment the workspace blocks list: the kept home, else the run's environment
#' @noRd
env_home = function(ctx) {
  s = ctx$session
  home = if (is.null(s)) NULL else session_home(s)
  home %||% ctx$envir
}

#' Per-session workspace memory: an environment inside ctx$state(), so it is never persisted
#' (snapshot addresses mean nothing in another process)
#' @noRd
env_memory = function(ctx) {
  st = ctx$state()
  if (!is.environment(st$gptr_workspace)) st$gptr_workspace = new.env(parent = emptyenv())
  st$gptr_workspace
}

#' Remember the snapshot and the time for the next `<workspace_changes>`; start the history
#' log for a session with a kept home (env-history.R)
#' @noRd
env_remember = function(ctx, snap) {
  mem = env_memory(ctx)
  mem$snapshot = snap
  mem$since = as.numeric(Sys.time())
  s = ctx$session
  if (!is.null(s) && !is.null(session_home(s))) user_log_start(session_data(s)$id)
  invisible()
}

#' Names-only workspace listing (`.opts$context = "names"`)
#' @noRd
env_names_lines = function(snap, budget) {
  if (!nrow(snap)) return(character())
  dsc_fit(paste(snap$name, collapse = ", "), budget)
}

#' `<workspace env=".." objects="n">`: one line per object, largest first (first message)
#' @noRd
env_block_workspace = function(ctx, budget) {
  mode = env_context_mode(ctx)
  envir = env_home(ctx)
  if (identical(mode, "none") || is.null(envir)) return(NULL)
  snap = env_snapshot(envir, env_memory(ctx)$snapshot)
  env_remember(ctx, snap)
  lines = if (identical(mode, "names")) {
    env_names_lines(snap, budget)
  } else {
    workspace_lines(snap, budget)
  }
  if (!length(lines)) lines = "(no objects)"
  label = if (is.null(ctx$session)) NULL else session_data(ctx$session)$home_label
  if (is.null(label)) label = if (identical(envir, globalenv())) "globalenv" else "<environment>"
  list(text = paste(lines, collapse = "\n"),
       attrs = list(env = label, objects = as.character(nrow(snap))))
}

#' `<workspace_changes>`: objects the user added, changed or removed and the expressions they
#' ran since the last request (turn messages; NULL when nothing changed)
#' @noRd
env_block_changes = function(ctx, budget) {
  envir = env_home(ctx)
  if (identical(env_context_mode(ctx), "none") || is.null(envir)) return(NULL)
  mem = env_memory(ctx)
  old = mem$snapshot
  new = env_snapshot(envir, old)
  ran = user_expr_log(since = mem$since)
  env_remember(ctx, new)
  d = if (is.null(old)) {
    list(added = character(), modified = character(), removed = character())
  } else {
    env_diff(old, new)
  }
  lines = changes_lines(d, new, ran, budget)
  if (!length(lines)) return(NULL)
  paste(lines, collapse = "\n")
}

#' Description of context item i of the call; an error becomes a one-line note
#'
#' The tryCatch() frame holds the gptr_call, whose `envir` binding the gateway resets at
#' settlement (architecture section 6.4 R2), never a user object.
#' @noRd
env_attached_one = function(call, i, budget, label, prefix, header_only) {
  force(call)
  force(i)
  force(budget)
  force(label)
  force(prefix)
  force(header_only)
  d = tryCatch(
    if (header_only) {
      gptr_describe(call_value(call, i), budget = 20L, level = 1L)
    } else {
      describe_value(call_value(call, i), budget)
    },
    error = function(e) paste0("<?> (describe failed: ", conditionMessage(e), ")")
  )
  if (prefix) d[1L] = paste0(label, ": ", d[1L])
  paste(d, collapse = "\n")
}

#' `<attached name="..">`: gptr_describe() of the call's context objects (first message and
#' turns, placement "both", IC-38); 150 tokens per object, at least 60 when many share the
#' block budget
#' @noRd
env_block_attached = function(ctx, budget) {
  call = ctx$input$call
  mode = env_context_mode(ctx)
  if (is.null(call) || identical(mode, "none") || !length(call$context)) return(NULL)
  n = length(call$context)
  per = as.integer(min(150L, max(60L, budget %/% n)))
  labels = vapply(call$context, function(it) as.character(it$label %||% ""), "")
  parts = character(n)
  for (i in seq_len(n)) {
    parts[i] = env_attached_one(call, i, per, labels[i], n > 1L, identical(mode, "names"))
  }
  list(text = paste(parts, collapse = "\n"), attrs = list(name = paste(labels, collapse = ", ")))
}

#' `<skill_content name="..">`: bodies of the skills preloaded with `skills =` (5,000 tokens per
#' skill; P17's `skill.body` service; NULL before P17 is loaded)
#' @noRd
env_block_skills = function(ctx, budget) {
  call = ctx$input$call
  skills = if (is.null(call)) NULL else call$ids$skills
  if (!length(skills) || !ext_service_has("skill.body")) return(NULL)
  body = ext_service_get("skill.body")
  per = as.integer(max(200L, min(5000L, budget %/% length(skills))))
  parts = character(length(skills))
  for (k in seq_along(skills)) {
    b = body(skills[k])
    txt = if (is.list(b)) b$text else b
    lines = strsplit(as.character(txt %||% ""), "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 1L && env_tokens(lines, "prose") > per) lines = lines[-length(lines)]
    parts[k] = paste(c(if (length(skills) > 1L) sprintf("[skill: %s]", skills[k]), lines),
                     collapse = "\n")
  }
  list(text = paste(parts, collapse = "\n\n"),
       attrs = list(name = paste(skills, collapse = ", ")))
}

#' The `eval.r` service: eval_r() through the `evaluator` record named by the `evaluator`
#' setting (default "r"; IC-69)
#' @noRd
env_eval_service = function(code, envir, ...) {
  name = setting_get("evaluator", default = "r") %||% "r"
  ev = registry_get("evaluator", name)
  if (is.null(ev)) ev = registry_get("evaluator", "r")
  fun = if (is.null(ev) || !is.function(ev$eval)) eval_r else ev$eval
  fun(code, envir, ...)
}

#' The `describe` service: gptr_describe() within the budget (ctx$describe())
#' @noRd
env_describe_service = function(x, budget = 150L) {
  describe_value(x, budget)
}

#' agent_end hook: remember the workspace, so the next `<workspace_changes>` shows only what the
#' user changed between requests; only for sessions whose workspace block ran (a session with
#' `.opts$context = "none"` pays for no snapshot)
#' @noRd
env_on_agent_end = function(event, ctx) {
  envir = env_home(ctx)
  old = env_memory(ctx)$snapshot
  if (!is.null(envir) && !is.null(old)) env_remember(ctx, env_snapshot(envir, old))
  NULL
}

#' session_shutdown hook: release the history log of the session
#' @noRd
env_on_shutdown = function(event, ctx) {
  if (is.character(event$session) && length(event$session) == 1L) {
    user_log_release(event$session)
  }
  NULL
}

#' The built-in `workspace` extension (architecture sections 7.4-7.5; 04 section 7.9)
#'
#' Context blocks `workspace` (first, order 500, 600 tokens), `workspace_changes` (turn, order
#' 100, 300 tokens), `attached` (both, order 600) and `skill_content` (both, order 700) (IC-38);
#' the T1 prompt section `r_env` (order 900, 450 tokens); the `evaluator` record `r` (IC-69);
#' hooks on `agent_end` and `session_shutdown`. The services `eval.r` and `describe` are
#' registered below, owned by this built-in (IC-34).
#' @noRd
builtin_workspace = function(gptr) {
  gptr$register(gptr_context_block("workspace", env_block_workspace, placement = "first",
                                   budget = 600L, order = 500L))
  gptr$register(gptr_context_block("workspace_changes", env_block_changes, placement = "turn",
                                   budget = 300L, order = 100L))
  gptr$register(gptr_context_block("attached", env_block_attached, placement = "both",
                                   budget = 1200L, order = 600L))
  gptr$register(gptr_context_block("skill_content", env_block_skills, placement = "both",
                                   budget = 10000L, order = 700L))
  gptr$register(gptr_prompt_section("r_env", function(ctx) r_env_probe(), tier = "T1",
                                    order = 900L, budget = 450L))
  gptr$register(gptr_spec("evaluator", "r", eval = eval_r))
  gptr$on("agent_end", env_on_agent_end)
  gptr$on("session_shutdown", env_on_shutdown)
  invisible(NULL)
}

on_load(ext_declare_builtin("workspace", builtin_workspace))
on_load(ext_service_set("eval.r", env_eval_service, provided_by = "P09", builtin = "workspace"))
on_load(ext_service_set("describe", env_describe_service, provided_by = "P09",
                        builtin = "workspace"))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-snapshot")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 85 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/env-snapshot.R tests/testthat/test-env-snapshot.R
git commit -m "feat(env): register builtin:workspace with its blocks, r_env and services"
```


### Task 11: Documentation, lint, layering and plan acceptance

**Files:** Modify: `tests/testthat/test-env-describe.R` (append), `tests/testthat/test-copy-eval.R` (append); Generated: `NAMESPACE`, `man/gptr_describe.Rd`.

`gptr_describe()` is the plan's one export (04 section 14.1). roxygen2 turns `@export` on the generic into `export(gptr_describe)` and `@export` on each method into an `S3method()` line; the `function` method is written `S3method(gptr_describe,"function")` (checked with roxygen2 on a scratch copy of the package: 20 `S3method` lines, no roxygen warning, `tools::checkRd()` clean). Until the methods are registered, `gptr_describe()` called from outside the namespace (the copy rows' child scripts, other packages, the console) finds no method (`no applicable method for 'gptr_describe'`, reproduced with a toy package loaded by `pkgload::load_all(export_all = FALSE)`), so the rows that call the export directly are added here. Both roxygen examples run offline and print `<data.frame> 32 x 11, 7 KB` plus the column types, and `<Date> length 10, 400 B` / `2026-01-01 to 2026-01-10; no NA`.

**Interfaces:**
- Consumes: the roxygen block of `gptr_describe()` and its methods (Task 3); P01's `expect_no_copy()`; P01's layering and lint tests (`test-arch-layers.R`, `test-lint-rules.R`) and `.lintr`.
- Produces: `export(gptr_describe)` and `S3method(gptr_describe, <class>)` for the 20 classes of 04 section 6.6 in `NAMESPACE`; `man/gptr_describe.Rd`; the evidence of 05 P09 acceptance 1-6.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-env-describe.R`:

```r
test_that("NAMESPACE exports gptr_describe() and registers its 20 methods", {
  nsfile = testthat::test_path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(nsfile), "the source NAMESPACE is not reachable from here")
  ns = readLines(nsfile, encoding = "UTF-8")
  expect_true("export(gptr_describe)" %in% ns)
  classes = c("\"function\"", "ArrowTabular", "DBIConnection", "Dataset", "Date", "POSIXct",
              "Seurat", "SingleCellExperiment", "data.frame", "data.table", "default",
              "dgCMatrix", "environment", "factor", "formula", "ggplot", "glm", "list", "lm",
              "matrix")
  registered = grep("^S3method\\(gptr_describe,", ns, value = TRUE)
  expect_setequal(sub("^S3method\\(gptr_describe,(.*)\\)$", "\\1", registered), classes)
})
```

Append to `tests/testthat/test-copy-eval.R`:

```r
test_that("the exported gptr_describe() leaves the object in place (R4)", {
  expect_no_copy("big = runif(5e6)", "invisible(gptr_describe(big))", label = "gptr_describe")
  expect_no_copy("L = list(a = runif(5e6), b = 1, c = list(d = 2))",
                 "invisible(gptr_describe(L, budget = 600L))",
                 edit = "L$a[1] = 0", object = "L$a", label = "gptr_describe(list)")
})

test_that("a data frame description adds no copy to R's own column-edit copy", {
  setup = "D = data.frame(a = runif(5e6), b = 1L)"
  base = expect_no_copy(setup, "invisible(NULL)", edit = "D$a[1] = 0", object = "D$a",
                        allow = 1L, label = "data frame baseline")
  expect_no_copy(setup, "invisible(gptr_describe(D, budget = 600L))", edit = "D$a[1] = 0",
                 object = "D$a", allow = base, label = "gptr_describe(data.frame)")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-describe|copy-eval")'
```

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 112 ]`: the NAMESPACE test records two failures (`"export(gptr_describe)" %in% ns is not TRUE` and the `expect_setequal()` of the registered classes), the three copy rows that call `gptr_describe()` in the child fail with `the script did not finish` (`could not find function "gptr_describe"`), and the data-frame baseline passes.

- [ ] **Step 3: Write the implementation**

Regenerate `NAMESPACE` and the Rd page, then list P09's entries:

```bash
Rscript --vanilla -e 'devtools::document()'
grep "gptr_describe" NAMESPACE
```

Expected output of the `grep` (roxygen's order):

```text
S3method(gptr_describe,"function")
S3method(gptr_describe,ArrowTabular)
S3method(gptr_describe,DBIConnection)
S3method(gptr_describe,Dataset)
S3method(gptr_describe,Date)
S3method(gptr_describe,POSIXct)
S3method(gptr_describe,Seurat)
S3method(gptr_describe,SingleCellExperiment)
S3method(gptr_describe,data.frame)
S3method(gptr_describe,data.table)
S3method(gptr_describe,default)
S3method(gptr_describe,dgCMatrix)
S3method(gptr_describe,environment)
S3method(gptr_describe,factor)
S3method(gptr_describe,formula)
S3method(gptr_describe,ggplot)
S3method(gptr_describe,glm)
S3method(gptr_describe,list)
S3method(gptr_describe,lm)
S3method(gptr_describe,matrix)
export(gptr_describe)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "env-describe|copy-eval")'
Rscript --vanilla -e 'devtools::test(filter = "eval|env-|copy-eval")'
Rscript --vanilla -e 'devtools::test(filter = "arch|lint")'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'
```

Expected: the first command prints `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 117 ]` (96 + 21); the second `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 457 ]` (guard 52, snapshot 85, describe 96, history 12, probe 16, plots 32, core 116, format 27, copy 21; skips appear only without ragg and `capabilities("png")`, RSQLite or `capabilities("profmem")`); the third shows `FAIL 0 | WARN 0` (P01's layering test finds no P09 call outside the layer table and the kernel SDK, every function has one home, and the literal service names `eval.r`, `describe`, `skill.body`, `compact.should` are declared; P01's lint rules find no hit in the eight files); the fourth prints no lints and exits 0. The namespace is loaded first, as in P01's acceptance A3: for an uninstalled development tree lintr's `object_usage_linter` cannot resolve internal functions through `getNamespace("gptr")` and would report every call to a P01, P02, P06, P08 or P09 internal helper as "no visible global function definition". This is a shell command, not package or test code, so IC-71's rule on `pkgload::load_all()` is not touched.

- [ ] **Step 5: Commit**

```bash
git add NAMESPACE man/gptr_describe.Rd tests/testthat/test-env-describe.R tests/testthat/test-copy-eval.R
git commit -m "docs(env): export gptr_describe() and register its methods"
```


## Plan acceptance

Run from the repository root after Task 11. Each check of 05 P09 (including its review amendments) and the test that proves it:

| # | Acceptance check (05 P09) | Proved by |
|---|---|---|
| 1 | `devtools::test(filter = "eval\|env-\|copy-eval")` is green | Task 11 Step 4: `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 457 ]` |
| 2a | sinks and `options()` restored after errors and interrupts | `test-eval-core.R` "sinks, options, hooks and the time limit are restored after errors and interrupts" (a sink left open, an error, a popped sink, an interrupt; `sink.number()`, `width`, hooks and connections unchanged) |
| 2b | warnings and messages captured in order | `test-eval-core.R` "warnings and messages are captured in order and muffled without tee" |
| 2c | an error stops at the first failing expression with a trimmed traceback | `test-eval-core.R` "an error stops at the first failing expression with a trimmed traceback" (3 of 5 done; `h(v) at <gptr>#3`; no evaluator frames); "an infinite recursion becomes an error result instead of escaping" |
| 2d | `q()` and `readline()` refused without evaluation | `test-eval-core.R` "q(), readline() and g = q; g() are refused without evaluation"; `test-eval-guard.R` "session-ending and interactive calls are blocked before evaluation", "a local binding never hides a call of q, quit or another blocked function" |
| 2e | a plot yields one 768x512 PNG block | `test-eval-core.R` "a plot yields one 768x512 PNG image block and no Rplots.pdf"; `test-eval-plots.R` "plot_png renders a recorded plot to a 768x512 PNG image block"; a plot finished by low-level calls is still one block: `test-eval-core.R` "a plot finished by low-level calls in later expressions is one image", `test-eval-plots.R` "low-level additions update the captured page instead of adding a plot" |
| 3a | evaluation at top level, in `globalenv()` from a function and in a function-frame home leaves the caller's 40 MB object editable in place | `test-copy-eval.R` "evaluation at top level and in globalenv() from a function edits in place", "evaluation in a function-frame home edits in place (G3 fact-check, IC-67)" |
| 3b | the rows `L$a`, `(x)`, `get("x")`, `x@slot`, `x[["a"]]` at top level leave it in place (IC-67) | `test-copy-eval.R` "results aliasing a user object are cleared in place (R8, IC-67)", "an S4 slot result adds no copy to R's own slot-edit copy" (R copies an S4 slot on `x@v[1] = 0` without gptr too: the row allows exactly the baseline's count) |
| 4a | describers keep at least 90% of G2's 98 facts at 150 tokens, incl. Seurat-like `meta.data` dims and columns, Dates, dgCMatrix dims and nnz, formula text, nested names | `test-env-describe.R` "describers keep at least 90% of G2's facts at 150 tokens and stay in budget" (98 facts, 92 kept in scratch), "Seurat-like meta.data dims and columns, Dates, sparse dims, formulas, nested names" |
| 4b | ALTREP `1:1e9` described without materialising | `test-env-describe.R` "ALTREP 1:1e9 is described without materialising"; `test-env-snapshot.R` "a compact integer sequence is described without materialising it" |
| 5a | `env-probe` leaves `loadedNamespaces()` unchanged | `test-env-probe.R` "r_env_probe leaves loadedNamespaces() unchanged and is cached" |
| 5b | `<workspace>` for six objects is at most 600 tokens and never forces a promise or an active binding | `test-env-snapshot.R` "six objects cost at most 600 tokens and promises stay unforced", "env_snapshot lists bindings with facts and never forces promises"; copy rows "snapshots of globalenv and of a function frame leave the object in place (R4)" |
| 6a | a plotting `r` call under Rscript leaves no `Rplots.pdf` in `getwd()` | `test-eval-core.R` "a plotting evaluation under Rscript leaves no Rplots.pdf in the working directory" (a fresh `Rscript --vanilla` with the working directory at a temporary directory) |
| 6b | a 50-plot loop attaches 3 images and lists the rest | `test-eval-core.R` "a 50-plot loop attaches 3 images and keeps the rest in one out entry"; `test-eval-format.R` "a 50-plot evaluation lists 3 attached plots and the stored rest" (`[plots 4-50 not attached: peter$plot(k)]`) |
| 6c | `.Random.seed` identical before and after an evaluation with an agent stream | `test-eval-core.R` "an evaluation with an agent stream leaves .Random.seed identical (IC-61)", "rng_swap keeps the user's .Random.seed and advances the agent's stream", "rng_swap removes .Random.seed again when the user had none", "rng_swap leaves R's generator kind as it found it when the user had no seed" (the user's next `set.seed()` draws the same numbers) |
| 6d | `g = q; g()` is blocked | `test-eval-guard.R` "q and quit are flagged in any value position (IC-67)"; `test-eval-core.R` "q(), readline() and g = q; g() are refused without evaluation" |
| RA | review amendments: R8 in place (IC-67); `pdf(NULL)` with the prior device restored; at most `gptr.r_max_images` images, the rest stored for `peter$plot(k)`, image tokens in the budget (IC-67); `rng_swap()` with hash-derived L'Ecuyer seeds (IC-61); `q`/`quit` in any position (IC-67); describers outside Suggests use slots and base generics only (IC-71); `attached` and preloaded `skill_content` with `placement = "both"` (IC-38); the `evaluator` record `r` and the `eval.r` and `describe` services (IC-69, IC-34) | 3b and the negative control of Task 8; `test-eval-plots.R` "offscreen capture uses pdf(NULL), writes no Rplots.pdf and restores the device"; 6b and `test-eval-format.R` "image tokens count against the budget"; 6c; 6d; `test-env-describe.R` "describer methods call no package outside Imports (IC-71)" and "ggplot, DBI, Arrow and SingleCellExperiment describers need no package calls"; `test-env-snapshot.R` "builtin_workspace registers the blocks, the section, the evaluator and two hooks", "the eval.r and describe services are registered by builtin:workspace", "the loaded registry holds the workspace records (P02)" |

Commands and expected results:

```bash
Rscript --vanilla -e 'devtools::test(filter = "eval|env-|copy-eval")'
Rscript --vanilla -e 'devtools::test(filter = "eval-core")'
Rscript --vanilla -e 'devtools::test(filter = "copy-eval")'
Rscript --vanilla -e 'devtools::test(filter = "env-describe|env-probe|env-snapshot")'
Rscript --vanilla -e 'devtools::test(filter = "arch|lint")'
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'
```

Expected, in order: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 457 ]`; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 116 ]`; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 21 ]`; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 197 ]` (96 + 16 + 85); the layering and lint tests with `FAIL 0 | WARN 0`; no lints and exit status 0 (the namespace is loaded first, as in P01's acceptance A3; after `R CMD INSTALL .` the bare `lintr::lint_package()` gives the same empty result). Skips appear only on machines without ragg and `capabilities("png")` (plot tests), RSQLite (one DBI expectation) or `capabilities("profmem")` (the copy rows). The image elision above provider limits (IC-67) is P06's projection (it appends `gptr.image_elision`, 04 section 4.6); P09 supplies the stored plots it points to.


## Self-review

**Spec coverage** (05 P09 scope, review amendments and acceptance -> task):

| Item | Task |
|---|---|
| `eval-core.R`: parse with `srcfilecopy()`, sink capture cleaned up in `suspendInterrupts()`, per-expression `setTimeLimit()` (none with a human), calling handlers created outside the frame holding the home, interruptions recorded, symbols printed by name, state diff | 8 |
| `eval-core.R`: `rng_swap()` with hash-derived L'Ecuyer seeds (IC-61) | 7 (and `rng =` in 8) |
| `eval-plots.R`: recorded device, PNG 768x512 res 120, ragg when installed, `pdf(NULL)` without a device and a human, prior device restored, `peter$plot()` support (`plot_png()`) | 6; attachment and storage in 8 |
| `eval-guard.R`: forbidden calls, interactive traps (the static list plus the `askYesNo` option trap of Task 8), `q`/`quit` anywhere, secret markers, the `gptr::` shim | 1 (trap in 8) |
| `eval-format.R`: 4,000-token budget, head 40% / tail 60%, state-change lines, `peter$out(id)` notices, tighter budget above half the compaction threshold, image tokens in the budget | 9 |
| `env-snapshot.R`: names, addresses, fingerprints, diff | 2 |
| `env-snapshot.R`: `builtin:workspace` with `workspace`, `workspace_changes`, `attached`, `skill_content` (IC-38), `r_env`, the `evaluator` record `r`, services `eval.r` and `describe` (IC-69, IC-34) | 10 |
| `env-describe.R`: `gptr_describe()` generic, level-based methods of 03 section 7.5, IC-71 | 3 (export and registration in 11) |
| `env-history.R`: task-callback log, last 20 | 4 |
| `env-probe.R`: capability probe for `<r_env>` without loading packages | 5 |
| `test-copy-eval.R` (acceptance 3) | 2, 3, 8, 11 |
| Acceptance 1-6 and the review amendments | the "Plan acceptance" table |

**Placeholder scan.** The plan was searched for the placeholder phrases of the writing-plans standard (to-be-decided markers, deferred implementation, unspecified error handling, references to another task's code instead of the code): none occurs. Every step shows the complete file or appended block, the command and the expected summary line, and every function a step calls is defined in this plan or in 04 for an earlier plan.

**Type and name consistency with 04.** Signatures copied from 04 section 7.9 and section 6.6 and checked against the code: `eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE, max_images = gptr_opt("r_max_images"))`, `rng_swap(state, expr)`, `format_eval_result(res, budget_tokens)`, `eval_guard(exprs)`, `gptr_shim(exprs, envir)`, `plot_png(recorded, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"), res = gptr_opt("plot_res"))`, `env_snapshot(envir, previous = NULL)`, `env_diff(old, new, assigned = character())`, `workspace_lines(snapshot, budget = 600L)`, `changes_lines(diff, snapshot, user_ran, budget = 300L)`, `describe_binding(name, envir, budget = 150L)`, `user_expr_log(since = NULL, n = 20L)`, `r_env_probe()`, `builtin_workspace(gptr)`, `gptr_describe(x, budget = 150L, ...)`. The `gptr_eval_result` has the twelve fields of 04 section 5.8 in that order (a test asserts `names()`); statuses, event types, option names (`gptr.r_timeout`, `gptr.r_output_tokens`, `gptr.r_max_images`, `gptr.plot_width`, `gptr.plot_height`, `gptr.plot_res`), block names, placements and orders, the section name, tier and order, the kind names `context_block`, `prompt_section`, `evaluator`, the event names `agent_end` and `session_shutdown`, the service names and the condition class `gptr_error_invalid_argument` match 04. Consumed functions use their 04 signatures (P01 section 7.1, P02 sections 6.8/7.2, P06 section 7.6, P08 section 7.8); P01's code was read from `dev/plan/P01-foundation.md` (its `clean_terminal()` returns lines and `out_put()` takes a session's live record, and the code here follows that).

**Contract ambiguities and the reading chosen.**

1. 04 section 7.6 types `gptr_run$session` as an id and the kernel SDK (IC-33) has no id-to-session accessor, while 04 section 7.9 asks `eval_r()` to keep extra plots "in the session's out store" and `format_eval_result()` to halve the budget by "the session's context". `eval_session()` reads the run's `shell` binding when it holds a `gptr_session` (the name P06's draft uses) and otherwise falls back to the process out store, which `out_get()` searches as well (IC-71), with no halving. P06 should expose the shell as a documented run field or add an SDK accessor.
2. 04 section 5.8 lists `changes` without the object diff, while architecture section 6.12 puts "added, modified, removed" in `changes` and `format_eval_result(res, budget_tokens)` must print the state-change lines from `res` alone. `eval_r()` adds `changes$objects = list(added, modified, removed, lines)`; the listed fields are unchanged.
3. 04 section 10.3's built-in table gives `attached (600, turn)` and omits `skill_content`; section 7.9 and IC-38 give `attached` and `skill_content` `placement = "both"` (orders 600 and 700). IC-38 (section 15) wins.
4. The block budgets of `attached` and `skill_content` are not fixed in 04; architecture section 12.2 gives 150 per object (300 maximum) and 5,000 per skill (10,000 after compaction): the blocks use 1,200 (150 per object, at least 60 when many objects share it) and 10,000 (5,000 per skill).
5. "`plot` events carry the PNG path": the field is named `path` (with `index`, `attached`, `out_id`); P10's draft reads `e$path`.
6. The `rng` state environment's fields are not named in 04 (section 7.6: "environment holding the child's `c(10407L, <6 seeds>)`"): `state$seed` holds the vector (advanced in place) and `state$id` the hash key (agent id, or `"<.opts$seed>:<agent label>"`). P19 must build `run$opts$rng_state` with these names.
7. `.d$snapshot` (04 section 5.1) has no writer among the kernel SDK verbs; the workspace snapshot lives in an environment inside `ctx$state()` (never JSON-able, so never persisted).
8. 04 section 7.0 lists no `the` field for P09, but the task-callback log and the probe cache are process-level by nature (neither is run state, INFRA-15): they are the package-level environments `user_log_state` and `env_probe_cache`.
9. Acceptance 5 ("`loadedNamespaces()` unchanged"): the probe reads cores and RAM through ps, an Import (IC-59) that R loads on first use; the test loads ps first, and the probe never loads a probed package.
10. The `eval.r` service signature is "`eval_r()` through the `evaluator` kind"; P02's draft `ctx$eval()` calls `f(code, envir = where)`, so the service is `function(code, envir, ...)`.
11. `changes_lines()` keeps 04's signature without a default for `user_ran`; callers pass `character()`.
12. IC-44 says `.opts$images` plots are rendered with `plot_png()` (P09, L4) while P08 (L6) may not call an L4 function by name; P08's plan renders them itself. Not P09's file; noted for the reviewers of P08.
13. R semantics, not a contract point: an error unwinds frames without releasing their references, so an object passed through a failing function (or a function-frame home the failing code forced) copies once on its next edit, as with `try()` in user code. 05's copy rows cover only non-failing code; the error row at top level after reading the object is in place and tested.
14. 04 section 7.9 says "per-expression `setTimeLimit(elapsed = timeout, transient = TRUE)`"; the `r` tool's `timeout` is "Seconds; best effort" for the call (P10). `eval_r()` keeps one deadline for the whole call and gives each top-level expression the remaining time as its per-expression `setTimeLimit()`, so a 10-expression call cannot run 10 times the limit; an expression that starts after the deadline is not run (status `timeout`).
15. 04 section 7.9 says `describe_binding()` has "errors caught (default method)": a failing class method falls back to `gptr_describe.default()`, and only when that fails too does the line become `<?> (describe failed: <the method's message>)`. The `attached` block keeps its one-line note (04 asks nothing more of blocks; P02 omits a block whose provider fails).
16. IC-61 forbids `RNGkind()`, yet R keeps the generator kind internally and `set.seed()` keeps it in force, so a swap for a user without `.Random.seed` must restore the kind some other way: `rng_swap()` reads and restores the kind code through `stats::rbinom(1L, 0L, 0.5)`, which loads and stores R's state without drawing (size 0). `rbinom()` is not on the lint list of 04 section 12.3 (`set.seed(`, `sample(`, `runif(`, `RNGkind(`) and draws nothing from any stream.

**Executed validation** (scratch directory `work/plans/P09/v2`, R 4.4.3, testthat 3.3.2, lintr 3.3.0.1, roxygen2 installed):

- Every `r` code block of this plan (25 blocks) was extracted and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse. The plan contains no left-arrow assignment and no `%>%` in code (grep).
- P01's 15 R files were extracted from `dev/plan/P01-foundation.md` and loaded with scratch stand-ins for `gptr_spec()`, `gptr_context_block()`, `gptr_prompt_section()`, `registry_get()`, `ext_declare_builtin()` (P02), `run_current()`, `session_data()`, `session_home()`, `session_live()` (P06) and P08's `call_value()` (copied from the P08 plan); P09's eight files were then loaded and every test file run with `testthat::test_file()`: guard 39, snapshot 76 (+ the P02 registry test, which needs `gptr_registry()`), describe 92, history 12, probe 15, plots 26, core 97 (+ the shim test, which needs P08's `gptr_return()` in a loaded `gptr` namespace, and the Rscript test, run as an equivalent script: no `Rplots.pdf`, 2 images), format 26, all passing. The red phase of Tasks 1-10 was simulated by leaving the task's code out; the failure counts above are the measured ones, adjusted for the tests that cannot run in scratch.
- The 21 rows of `test-copy-eval.R` ran in fresh `Rscript --vanilla` processes through a scratch `expect_no_copy()` with P01's counting rule: 0 copies, except the S4 and data-frame rows, which equal their R baselines (1 copy each without gptr). Negative control: without `res[1L] = list(NULL)` the `(x)` row copies once. Prototype variants were checked the same way: a `for` loop in the frame that binds a function-frame home copies once, a positional `ls(envir)` copies once, the box pattern does not.
- `lintr::lint_package()` with the repository `.lintr` on a scratch package: no lints in the P09 files and tests other than `object_usage_linter` "no visible global function" notes for functions that the scratch stand-ins define outside lintr's view (every name listed exists in P01, P02, P06, P08 or P09). These notes are the uninstalled-namespace lookup failure of P01's A3 note, which is why Task 11 Step 4 and the Plan acceptance run `pkgload::load_all(quiet = TRUE)` before `lintr::lint_package()` and stop on any lint. P01's `lint_scan()` rules over the eight files: 0 hits. P01's layering check (`arch_fun_map()`, `arch_edges()`, `arch_check()`, the factory rule, `arch_service_calls()`) over P01's files, the stand-ins placed in their owners' files and P09's files: 0 violations, no duplicated function names, all service names declared.
- `roxygen2::roxygenise()` on the scratch package: `export(gptr_describe)` and the 20 `S3method` lines listed in Task 11, no warnings; `tools::checkRd()` clean; the two examples print the outputs quoted in Task 11.
- Describer facts: 92 of G2's 98 at 150 tokens (93.9%), the longest description 130 tokens. `r_env_probe()` on the development machine: 173 estimated tokens, 0.06 s.
- Review re-run after the fixes of the review log below (scratch `work/plans/review-P09/v3`): the 25 `r` blocks re-extracted from this file and parsed; the eight R files and nine test files assembled from the blocks, built into a scratch package with P01's 15 extracted R files and stand-ins for P02, P06 and P08, `roxygen2::roxygenise()` and `devtools::test()`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 457 ]` (guard 52, snapshot 85, describe 96, history 12, probe 16, plots 32, core 116, format 27, copy 21, including every fresh-process copy row at 0 copies or its R baseline); P01's `lint_scan()` rules: 0 hits; `lintr::lint()` with the repository `.lintr` over the 17 files: no lints apart from `object_usage_linter` notes for stand-in functions; no left-arrow `LEFT_ASSIGN` token (`getParseData()`) and no `%>%` in any block. Probes run before the fixes: `q = 1; q('no')`, `q = 1; base::q('no')`, `quit = base::quit; quit()`, `f = function(q) 1; q('no')` and `q = 1; do.call('q', list('no'))` passed the guard; `set.seed(42); runif(1)` after a swap without a user seed gave 0.1738 instead of 0.9148; `options('digits')`, `library()` and `suppressPackageStartupMessages(1 + 1)` printed nothing; `f = function(n) f(n + 1); f(1)` made `eval_r()` itself throw "evaluation nested too deeply"; `plot(1:10)`, `abline()`, `lines()`, `points()` in four expressions gave four images with the finished page not attached; CR LF code was a parse error; the first plot of a session reported `[environment variables changed: TZDIR]`.


## Plan review log

Adversarial review of 2026-10-01 against 05 P09, 04 (sections 5.8, 6.6, 7.0, 7.1, 7.6, 7.9, 10.2-10.6, 12.3; IC-33, IC-34, IC-38, IC-60, IC-61, IC-67, IC-69, IC-71), 03 sections 6.4, 6.12, 7.3-7.5, 12.2, the P01, P02, P06, P08 and P10 plans and report 12 (verification log). Every finding was reproduced in scratch before it was fixed; the fixed code is the code above, re-extracted, built and run (Self-review, "Review re-run").

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 1, `eval_guard()` | Local names exempted blocked functions everywhere: `q = 1; q('no')`, `q = 1; base::q('no')`, `quit = base::quit; quit()`, `f = function(q) 1; q('no')` and `q = 1; do.call('q', list('no'))` passed the guard and would end the user's R session (R skips non-function bindings when it looks up a function, and formals were exempt outside their function). IC-67 and acceptance 2 require refusal | applied | The walk tracks scopes (formals and local variables of enclosing functions); a call is exempt only for a function the code defines or a name an enclosing function binds; `pkg::name` is always refused; a string passed to `do.call()`/`match.fun()`/`get()` is exempt only for a code-defined function; `q`/`quit` as values only for assigned names; `stdin()` counts as a stdin read; `for` variables are assignment targets. Two new tests (12 expectations) and one `eval_assign_targets()` expectation |
| 2 | major | Task 7, `rng_swap()` | When the user had no `.Random.seed`, removing it left L'Ecuyer-CMRG as R's internal kind: the user's next `set.seed(42); runif(1)` gave 0.1738 instead of 0.9148. The roxygen claimed the kind resets at the next `set.seed()`, which is false (`set.seed()` keeps the kind). IC-61 and acceptance 6 are about leaving the user's RNG as it was | applied | The kind code is read before the swap and restored after it through `stats::rbinom(1L, 0L, 0.5)` (loads and stores R's state without drawing; `RNGkind()` stays unused), the stored variable is removed; new test "rng_swap leaves R's generator kind as it found it when the user had no seed"; ambiguity 16 |
| 3 | major | Task 8, `eval_on_error()` | An infinite recursion (`f = function(n) f(n + 1); f(1)`) made `eval_r()` itself throw "evaluation nested too deeply": the calling handler has almost no stack left and its traceback, flush and `tryCatch()` calls overflow again. Tools must never throw (conventions section 5) and an error must stop at the first failing expression (acceptance 2) | applied | A `stackOverflowError` (R >= 4.2.0 class) invokes the `gptr_stop` restart first; `eval_overflow()` records the error event at the normal depth; new test "an infinite recursion becomes an error result instead of escaping" |
| 4 | major | Task 8, `eval_invisible_heads` | `options`, `library` and `suppressPackageStartupMessages` were treated as always invisible, so `options("digits")`, `library()` and `suppressPackageStartupMessages(1 + 1)` printed nothing although the console prints them (REQ-23 output capture) | applied | The three heads are removed (they go through `withVisible()`, cleared in place as before); new test "CR LF line ends parse, and query calls print like the console" |
| 5 | major | Task 6, `plot_capture()` | Low-level additions in later top-level expressions were captured as new plots: `plot(1:10)`, `abline()`, `lines()`, `points()` gave four images (4 x 532 tokens) and the finished page, the fourth, was not attached (`max_images` 3). S-12 token costs and acceptance 2 ("a plot yields one ... PNG block") | applied | A same-page addition replaces the recording of the page already captured in this evaluation (`ps$last_k`), as knitr's `fig.keep = "high"`; new tests in `test-eval-plots.R` and `test-eval-core.R` |
| 6 | minor | Task 8, `eval_parse()` | Code with CR LF line ends was a `parse_error` ("unexpected invalid token") | applied | CR LF and CR become LF before parsing; covered by the new test of finding 4 |
| 7 | minor | Task 8, `eval_state_diff()` | R sets `TZDIR` the first time a time is formatted (macOS), and gptr's own plot ids format the time, so the first plot of a session reported `[environment variables changed: TZDIR]` to the model | applied | A newly appearing `TZDIR` is not reported; new test "R's lazily set TZDIR is not reported as a change" |
| 8 | minor | Task 2, `env_snap_rows()` | A binding whose `length()` method errors (for example a Python object without a length) made `env_snapshot()` throw, so every `eval_r()` call and the `<workspace>` block failed while the object existed | applied | `env_snap_facts()` (its `tryCatch()` frame holds only the box, R3) falls back to `env_snap_bare()`: address, class and shape `?`; new test; the copy rows still report 0 copies |
| 9 | minor | Task 3, `describe_binding()` | 04 section 7.9 says "errors caught (default method)", but a failing method gave only `<?> (describe failed: ...)` | applied | `describe_default()` falls back to `gptr_describe.default()`; the note remains for a second failure; test updated; ambiguity 15 |
| 10 | minor | Task 5, `env_probe_session()` | Workers were capped for any non-empty `_R_CHECK_LIMIT_CORES_`, including `false`, and not under P01's `check_running()`, the predicate IC-60 names | applied | `check_running()` or a value other than `""`/`false` caps the workers at 2; new test |
| 11 | minor | Task 10, `env_block_workspace()` | Without a session label every environment got `env="globalenv"` | applied | `globalenv` only for the global environment, else `<environment>` (04 section 5.1 `home_label` values); test updated |
| 12 | minor | Task 10, `env_on_agent_end()` | The hook snapshotted the home (an `object.size()` per binding) and started the task-callback log for sessions whose workspace block never ran (`.opts$context = "none"`) | applied | The baseline is refreshed only when one exists; test extended |
| 13 | minor | Task 9, `eval_event_text()` | The interrupt line lacked architecture section 6.12's "side effects may have occurred" | applied | `[interrupted by the user after 2.3 s; side effects may have occurred]`; new test |
| 14 | minor | Self-review | The per-call deadline of `eval_r()` (each expression gets the remaining time) differs from 04 section 7.9's literal "per-expression `setTimeLimit(elapsed = timeout)`" and was not recorded | applied | Recorded as ambiguity 14; the code is kept (a call cannot run n times its limit) |
| 15 | minor | Steps 2 and 4 of Tasks 1-3 and 5-11, Plan acceptance | Counts changed with the fixes | applied | Every red and green count recomputed and the green ones measured (457 in all) |
| 16 | minor | Task 10, `changes_lines()` | `user ran:` lines are not redacted before reaching the model | rejected | 04 section 7.9 gives P09 no redaction duty; model-bound text is redacted by its assemblers (tool results with the `context` profile by P06, 04 section 4.4; context assembly by P07), so redacting here would apply the hook twice |
| 17 | minor | Task 8, interrupts inside a run | An interrupt inside a run propagates out of `eval_r()` without a result | rejected | By design (03 section 6.12, 04 section 7.0 `console.interrupt_policy`): inside a run the run's interrupt policy decides and P06's dispatcher makes the tool result; outside a run `eval_r()` returns status `interrupt` (tested) |
| 18 | minor | Task 2, `env_compact_seq()` | The ALTREP test is a heuristic (first, second and last element of a long attribute-free integer vector) and can call an ordinary vector with sequence endpoints a "sequence" (size not shown) | rejected | Base R has no ALTREP predicate outside `.Internal()`, and reading the whole vector would materialise `1:1e9` (acceptance 4); the false positive only hides one size |
| 19 | minor | `test-env-snapshot.R`, `test-env-describe.R` | `s4_where()` is defined in both files | rejected | P09 owns no `helper-*.R` file (P01 does); each test file stays self-contained |
| 20 | minor | Task 10, `env_attached_one()` | In `"names"` mode a third-party describer that ignores `budget = 20L` is not cut | rejected | P02 truncates every block to its `budget` (04 section 10.2 kind 13), and cutting the header line at 20 tokens would also cut the longer built-in headers (Seurat) |


## Cross-plan consolidation log

Cross-plan check of 2026-10-01 against 04 (IC-71), 05 P01 acceptance 3 and P09 acceptance, 00-conventions (lint section) and P01 (acceptance A3 and its note, contract-ambiguity 5). The two findings below describe the same defect from two lenses and share one change.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | obligations | minor | Task 11 Step 4 command block and Plan acceptance commands | applied | A bare `Rscript --vanilla -e 'lintr::lint_package()'` on the uninstalled development tree reports `object_usage_linter` "no visible global function definition" for every internal helper (P09's own executed validation saw these notes; P01's A3 note explains the `getNamespace("gptr")` lookup failure). Both blocks now run `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'`, P01's A3 command, so the check fails with a non-zero exit on any lint. The expected-output text of both places says "no lints and exit 0"; the Self-review's executed-validation bullet links the notes to the change. 05's bare `lintr::lint_package()` is satisfied (same empty result after `R CMD INSTALL .`); a shell command is neither package nor test code, so IC-71's `pkgload::load_all()` rule is respected. No R code or test count changes (457 green, 117 in Task 11). Checked in scratch (`work/consolidate/P09`): a two-file package whose `helper_b()` calls `helper_a()` gave one `object_usage_linter` lint with the bare command and "No lints found", exit 0, with the new one; the 25 `r` blocks re-extracted and parsed, no left-arrow or `%>%` token |
| 2 | trace | minor | Task 11 Step 4 and Plan acceptance commands | applied | Same defect and same change as row 1 |
