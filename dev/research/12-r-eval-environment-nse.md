# Track 12 — R evaluation tool, environment introspection, NSE, pipe semantics

Research date: 2026-09-29. Machine: macOS 26.6 (arm64), R 4.4.3 (`Rscript --vanilla`),
evaluate 1.0.5, knitr 1.51, rlang 1.1.7, ragg 1.5.2, R.utils 2.13.0, glue 1.8.1, magrittr 2.0.5,
data.table 1.18.2.1, Matrix 1.7-5, SeuratObject/Seurat 5.4.0, SummarizedExperiment 1.36.0,
IRkernel 1.3.2, arrow 23.0.1.1; from the private library: lobstr 1.2.0, duckdb 1.5.0,
xxhashlite 0.2.2. The sandbox runs in the `C` locale; UTF-8 tests were re-run with
`LANG=en_US.UTF-8`.

All scratch code and raw outputs:
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/12/`
(abbreviated below as `W12/`). Final prototypes: `W12/gptr_eval2.R` (evaluator),
`W12/gptr_introspect.R` (introspection), `W12/gptr_gateway.R` (gateway / NSE / pipe).

Prior work: an interrupted researcher left `W12/gptr_eval.R` and `W12/a1_compare.R` and no report.
Treated as unverified. Running `a1_compare.R` crashed immediately:
`Error: 'dev.displaylist' is not an exported object from 'namespace:grDevices'` (executed). That
draft also had four latent bugs that the torture suite below exposed and that are fixed in
`gptr_eval2.R`: traceback trimming dropped user functions named `h`; an interrupt landing between
two expressions escaped the evaluator; every plot was reported 2-3 times (display lists are
pairlists, so `identical(x, y[seq_along(x)])` was always FALSE; evaluate uses `x[]`); the
side-effect diff was computed before `on.exit()` restored the harness options.

Confidence tags: **VERIFIED** = I saw the evidence (source line, URL, or executed output);
**LIKELY** = strong inference, not executed; **UNCERTAIN** = open.

---

## 1. Executive summary

1. **Hand-roll the evaluator; do not Import evaluate.** evaluate 1.0.5 is well built (zero
   dependencies, used by knitr, IRkernel and btw) but has four defects that matter for gptr, all
   VERIFIED here. (a) If model code leaves a `sink()` open, evaluate's cleanup closes its own
   capture connection while that connection is still on the sink stack, and **every later console
   `cat()`/`print()` fails with "invalid connection"** until the dead sink is popped. (Verifier
   correction: one `try(sink(), silent = TRUE)` recovers. It errors once with "invalid connection"
   but still pops the dead sink. `closeAllConnections()` also errors once on it and is not needed.)
   (b) With `new_device = FALSE` it silently misses plots on a device that the code itself opens.
   (c) Every `x <- big_object` it evaluates keeps a sticky extra reference, so the user's next
   in-place edit copies the whole object. (d) It sets `options(rlang_trace_top_env =)` and never
   restores it. Timeouts, interrupts, tracebacks, a guard and truncation would have to be layered
   on top anyway. The reference implementation `W12/gptr_eval2.R` (about 540 lines, base R only)
   passes a 19-case torture suite and `R CMD check --as-cran` with no code NOTEs.
2. **In-memory safety is subtle, and it is the key new finding of this track.** R releases the
   references held by a function frame only if nothing else references that frame when the
   function returns (`R_CleanupEnvir`, R 4.4.3 `src/main/eval.c` lines 2137-2164). Several things
   leave a *sticky* reference on a user object, after which the next `x[1] <- 0` duplicates it:
   putting the object in a list (`withVisible()`, `list(...)`, `lobstr::obj_size()`),
   `utils::str()`, passing closures such as `tryCatch()` handlers or `lapply`/`vapply` `FUN` from a
   frame that binds the object, calling `table()`, `format()` or `rm()` from such a frame, and
   byte-compiled loops that call closures. **The same happens in plain R:** `str(x)` at the console
   also forces a copy on the next edit. gptr's evaluator, introspection and gateway are written so
   that none of this happens (a "leaf / formatter / by-name" structure), and 20 fresh-process
   tracemem checks prove it (§5.4).
3. For a 5 GB Seurat object the sticky-reference effect matters less than for plain objects. S4
   slot assignment and `data.frame` column assignment copy anyway in plain R (VERIFIED baseline),
   and data.table (`set()`, `:=`) and environments/R6 work by reference. Plain vectors, matrices,
   arrays and lists are the types that must stay copy-free.
4. **Plot capture that still shows plots to the user:** `plots = "auto"`. When a device is open,
   the session is interactive, or knitr is running, the model's code draws on the current device,
   so the user sees the plot in RStudio, Positron, a quartz/windows window, or the knitr/IRkernel
   document. The harness `recordPlot()`s each completed page (hooks `before.plot.new`,
   `before.grid.newpage`, `persp`, plus after each top-level expression) and replays it offscreen
   into a 768x512 PNG (ragg if installed, else `png()`) for the model. With no device open in a
   non-interactive run it opens a private recording device (`ragg::agg_record()` or
   `pdf(NULL)`), which avoids creating `Rplots.pdf`. VERIFIED, including inside `knitr::knit()`,
   where the figure lands in the document and the model gets the PNG.
5. **Timeouts:** `setTimeLimit(elapsed = remaining, transient = TRUE)` before each top-level
   expression, reset afterwards. It interrupts R-level loops within about 0.5 s. It does **not**
   interrupt C/BLAS code (`sort`, `solve`, `grepl`) or even a single long `Sys.sleep(3)` on this
   macOS build. `R.utils::withTimeout()` uses the same mechanism (also failed on `Sys.sleep`). No
   in-process hard timeout exists; document the timeout as "best effort".
6. **Interrupts:** Ctrl-C/Esc arrives as an `interrupt` condition. gptr catches it both inside user
   code (calling handler plus restart) and anywhere in harness code (outer `tryCatch`), returns the
   partial output with `status = "interrupt"`, and does not end the session (VERIFIED with a
   self-sent SIGINT).
7. **Session-killing and interactive calls:** a static AST guard blocks `q()`, `quit()` (including
   `do.call("q")` and `f <- quit`), `browser()`, `debug*()`, `readline()`, `menu()`,
   `select.list()`, `file.choose()`, `askYesNo()`, `setTimeLimit()`, `closeAllConnections()` and
   `.Internal()`. The CRAN policy itself says "Nor may R code call q()". Dynamic backstops are
   `options(askYesNo = <function that errors>)` and `options(rlang_interactive = FALSE)`, which
   makes `rlang::check_installed()` error instead of prompting (VERIFIED). The guard is advisory,
   not a security boundary.
8. **Target environment:** default `envir = parent.frame()`, the same as `load()`, `knitr::knit()`,
   `rmarkdown::render()`, `evaluate::evaluate()` and `targets::tar_load()`. At top level that is
   `globalenv()`, because the user asked for it. CRAN's automated check flags only
   `assign(..., envir = .GlobalEnv / globalenv() / pos = 1)` and unbound `<<-` (VERIFIED with a toy
   package). The policy line is "Packages should not modify the global environment (user's
   workspace)". btw 1.5.0 (CRAN, 2026-09-09) runs model code in `global_env()` via evaluate.
   **Never name `.GlobalEnv` in gptr code.**
9. **magrittr pitfall (VERIFIED):** under `x %>% f()`, `parent.frame()` is a temporary mask
   environment whose only binding is `.`, so objects created there are lost. gptr detects that case
   (an environment whose only binding is `.`) and uses its parent. `lapply(xs, gptr)` and
   `purrr::map` evaluate in transient frames by design; document `envir =`.
10. **Workspace introspection that is cheap and safe at 2 GB (VERIFIED):** a snapshot of 61
    bindings (a 915 MB matrix, a 2e6-element list, a 5e6-string vector, a 1e7-row data.frame, a
    data.table, 1:1e9 ALTREP, a dgCMatrix, Seurat, SummarizedExperiment, an arrow Table, a duckdb
    connection, R6, a promise and an active binding) takes 0.78 s cold and 0.09 s warm (sizes are
    cached by address). Per-object descriptions take ≤ 0.74 s. Peak extra R heap is 139 MB
    (sampling). No copies were made and the user's next in-place edits stayed in place. The
    promise was not forced and the active binding was not called.
11. Use **`utils::object.size()`, not `lobstr::obj_size()`**. lobstr is 6-30x slower on large lists
    and character vectors (1.46 s vs 0.23 s; 1.69 s vs 0.05 s) and leaves a sticky reference.
    object.size overstates ALTREP compact sequences (`1:1e9` shows 3.7 GB; lobstr says 680 B) and
    shared data. Label sizes as approximate.
12. **Change detection between turns:** combine the address (`rlang::obj_address()`) with a
    fingerprint. Objects ≤ 50 MB get a full `rlang::hash()` (VERIFIED at 3.7 GB/s for doubles and
    1.3 GB/s for strings or lists, with no copy). Larger objects get a sampled hash of attributes
    and 64 elements. In-place edits of large objects at unsampled positions (e.g. `m[i, j] <- v` on
    a 915 MB matrix, or `data.table::set()`) are not detected by sampling (VERIFIED). Complement it
    with **`addTaskCallback()`**, which records the exact top-level expressions the user ran between
    turns (VERIFIED in Rscript and interactive R, and it does not cause copies), and with static
    analysis of the agent's own code (assignment targets).
13. **Promises and active bindings:** detect them without forcing via
    `rlang::env_binding_are_lazy()` / `env_binding_are_active()`, or base `bindingIsActive()`.
    Base R has no promise test: `substitute(sym, env)` works only for non-global environments.
    `as.list(env)`, `mget()`, `eapply()` and `get()` all force (VERIFIED). knitr's `cache.lazy`
    uses `lazyLoad()` bindings, so cached documents are full of promises.
14. **Import rlang.** It is already a hard Import of httr2 (VERIFIED `packageDescription("httr2")`),
    so it costs nothing. It provides `obj_address`, `hash`, `env_binding_are_lazy/active`, and
    `enquo`/`enquos`. `enquos` is what makes the gateway correct for forwarded dots (base
    `substitute()` + `parent.frame()` resolved the wrong variable, VERIFIED) and copy-safe, because
    promises are never forced in gptr's frame.
15. **NSE rules for identifiers (VERIFIED prototype):** a string literal is taken as is; a bare
    symbol that is a known alias is taken as that name (the alias wins, as in `library()`); an
    unknown symbol bound in the caller takes the variable's value; an unknown unbound symbol is
    taken as a literal name. `c(a, b)` is resolved element-wise. `!!x` / `.env$x` force the
    variable. Any other call is evaluated in a mask where the aliases are bound, so
    `model = if (hard) opus else haiku` works.
16. **Prompt selection:** `prompt =` wins. Otherwise the first unnamed **string-literal**
    expression is the prompt, else the first unnamed length-1 character value. Everything else
    unnamed or named is context, labelled by its expression. This makes
    `abstract |> gptr("Is it an RCT?")` and `gptr(task, model = haiku)` both work (VERIFIED). A
    fully unquoted prompt is a syntax error ("unexpected symbol"). The nearest workable forms are
    the console REPL (`gptr()`), a knitr ```` ```{gptr} ```` chunk engine (prototype VERIFIED), and
    raw strings `r"(...)"`.
17. **Return object:** an S3 `gptr_result` (a list: `text`, `value`, `has_value`, `session`,
    `usage`, `model`, `streamed`), with `print` (answer plus a one-line footer), `format` and
    `as.character` (answer text). The first argument may be a `gptr_result` or a `gptr_session`,
    which continues that session, so `gptr("a") |> gptr("b") |> gptr("c", model = opus)` works
    (VERIFIED). The agent designates an R value by calling `gptr_return(obj)` inside its R code, so
    no extra model-visible tool is needed. `res$value` then holds it (VERIFIED with a mocked
    agent).

---

## 2. Findings

### 2.A The evaluation tool

#### A1. Anatomy of evaluate 1.0.5 (VERIFIED from the installed package; dump in `W12/evaluate_src.txt`)

- Signature (executed `args(evaluate::evaluate)`):
  `evaluate(input, envir = parent.frame(), enclos = NULL, debug = FALSE, stop_on_error = 0L, keep_warning = TRUE, keep_message = TRUE, log_echo = FALSE, log_warning = FALSE, new_device = TRUE, output_handler = NULL, filename = NULL, include_timing = FALSE)`.
  `new_output_handler(source, text, graphics, message, warning, error, value = render, calling_handlers = list())`.
- `stop_on_error`: 0 = continue, 1 = stop (return what was captured), 2 = rethrow
  (`check_stop_on_error`, dump lines 377-394).
- Output capture: `local_persistent_sink_connection()` opens `file("", "w+b")` (an anonymous temp
  file), sets `options(try.outFile = con)` and calls `sink(con, split = debug)`. Before each read it
  re-opens the connection if code ran `closeAllConnections()`, and re-sinks if code popped the sink
  (dump lines 197-221). Cleanup (`defer`) pops **one** sink only if `sink.number() >= sinkn`, and
  closes the connection.
- Plots: `local_new_device()` uses `ragg::agg_record()` when available, else `pdf(file = NULL)`,
  then `dev.control(displaylist = "enable")` (dump 169-183). Hooks `persp`, `before.plot.new` and
  `before.grid.newpage` call `capture_plot_and_output` (dump 186-195). `capture_plot()` only
  records when `dev.cur()` is the device that was current at start, the page is complete
  (`par("page")`), the display list makes a visual change (ignores `C_par`, `C_layout`,
  `C_clip`, `C_plot_window`, `C_strHeight`, `C_strWidth`, `palette`, `palette2`), and it is not a
  prefix-extension of the last plot (dump 29-49, 300-335).
- Printing: `render()` calls `methods::show()` for S4, else evaluates `print(value)` in
  `new.env(parent = envir)` so S3 methods defined in `envir` dispatch (dump 224-239).
- Errors: base condition objects carry only `message` and `call`. No traceback (executed:
  `names(err)` → `message call`; verifier re-run: for a top-level `stop()` only `message`, because
  the call is NULL). Errors from `rlang::abort()` keep rlang's own `trace` field
  (`message trace parent rlang`, re-run). A traceback can be collected through
  `output_handler$calling_handlers`, which run before evaluate's own handlers (withCallingHandlers
  calls the first-listed handler first, VERIFIED `exp_a1_evaluate.R`).
- `evaluate()` executes `if (is.null(getOption("rlang_trace_top_env"))) options(rlang_trace_top_env = envir)`
  with no restore (executed `print(evaluate::evaluate)`). After the call the option still holds
  `envir` (VERIFIED: "identical to env? TRUE").
- NEWS (https://raw.githubusercontent.com/r-lib/evaluate/main/NEWS.md): 1.0.4 "runs cleanup with
  interrupts suspended"; 1.0.5 is the current CRAN version (published 2025-08-27, CRAN page).

#### A2. evaluate defects that matter for gptr (all VERIFIED)

| Defect | Evidence |
|---|---|
| Code that leaves a sink open breaks the console | `W12/exp_a7_evaluate_sink_bug.R` prints `sink.number() after evaluate: 1`, `cat FAILED: invalid connection`, then `Error in sink() : invalid connection`. (Verifier correction, re-run: the first `sink()` call raises that error but pops the dead sink, and output then works. So `try(sink(), silent = TRUE)` recovers. `closeAllConnections()` also raises the same error on its first call and is not required.) |
| No plots from a device the code opens itself (`new_device = FALSE`) | `W12/exp_a8_devices.R` case (c'): `evaluate new_device=FALSE, no device at start → plots=0`, while the gptr evaluator reports 2 plots. |
| Sticky reference on assigned objects | `W12/out/copycheck_final.txt`: `evaluate::evaluate("v <- runif(5e6)")` then `v[1] <- 0` gives COPY; plain R gives "in place". |
| Option leak | `rlang_trace_top_env` left set to the evaluation environment (A1). |
| No timeouts, interrupts propagate out | By design. Wrapping with `tryCatch(interrupt =)` works (IRkernel does this; `W12/exp_a6_torture.R` evaluate backend). |
| No traceback | A1. |

Things evaluate gets right, and gptr copies: the anonymous-file sink, recovery from
`closeAllConnections()` and from a popped sink, the plot heuristics (`makes_visual_change`,
prefix test with `x[]`), printing in a child of `envir`, and `show()` for S4.

#### A3. Precedent: btw's run-R tool (Posit, CRAN 1.5.0, published 2026-09-09) (VERIFIED)

Source: https://github.com/posit-dev/btw/blob/main/R/tool-run.R (copy in
`W12/ext/btw_tool-run.R`).
- `btw_tool_run_r_impl(code, .envir = global_env(), show_last_value = TRUE)` (lines 121-125). It
  evaluates with `evaluate::evaluate(code, envir = .envir, stop_on_error = 1, new_device = TRUE, output_handler = handler)`
  (lines 232-238). evaluate is only in btw's **Suggests** (CRAN DESCRIPTION).
- "Working directory, options, envvar are restored" via `withr::local_dir(getwd())`,
  `withr::local_options()`, `withr::local_envvar()` (lines 165-168). **I found that two of these
  are incomplete (VERIFIED `W12/exp_a3_withr_restore.R`, withr 3.0.2):** with no arguments,
  `local_options()` restores changed *existing* options but not *new* ones (a new option stayed
  set). `local_envvar()` behaves the same way: it restores changed or unset *existing* variables
  but leaves *new* ones set. (Verifier correction: the original text said `local_envvar()` "restores
  nothing". A re-run with withr 3.0.2 showed a changed existing variable and an unset `LANG` both
  restored, while a new variable stayed set.)
- Plots: the last plot, or each plot that is not a prefix of the next, is replayed into
  `ragg::agg_png(..., scaling = 1.5)` or `png()`. The default is 768 px on the longest side, ratio
  3:2. The comment says this was chosen to match OpenAI's resize rule (lines 66-78, 143-161,
  304-316).
- The tool description forbids destructive actions and says "This code runs in a global
  environment" (lines 402-435). It is a good template for gptr's `r` tool text.
- Security note in the docs: "the code is executed in the global environment and does not have any
  sandboxing" (lines 9-15). The tool is off by default and must be enabled with
  `btw.run_r.enabled` or `BTW_RUN_R_ENABLED`.

#### A4. The hand-rolled evaluator (`W12/gptr_eval2.R`): torture results (VERIFIED)

`W12/exp_a6_torture.R` runs 19 cases against both backends (outputs
`W12/out/a6_torture.txt`, `W12/out/a6_torture_hand_final.txt`, UTF-8 locale). Hand-rolled results:

| Case | Outcome (hand-rolled) |
|---|---|
| multi-expression code, `print`, `cat` without newline, `message`, warning in a function, `invisible`, S4 `show`, S3 `print` method, error in a nested function | Output in console order. Warning shown as `Warning in f(): warn in f`. Stops at the first error: `Error in g(v): boom: z [expression at line 15]`, traceback `1: h("z") / 2: g(v) at <gptr>#14 / 3: stop("boom: ", v) at <gptr>#13`, `15 of 17 top-level expressions completed` |
| parse error | `Error: <gptr>:3:6: unexpected ']'` with context lines; nothing evaluated |
| 5 plots (base, loop of 2, `par(mfrow)` two-panel, ggplot, grid) | exactly 6 PNGs, the same count as evaluate |
| `sink(tempfile())` left open | no crash; `sink.number()` 0 afterwards; console fine |
| `sink()` pops our sink | recovered; later output captured |
| `closeAllConnections()` (guard off) | recovered |
| `options(warn = 2)` | `Error: (converted from warning) NAs introduced by coercion` |
| error inside a `print` method | `Error in print.bad(value): print failed`, traceback `print(value) / print.bad(value) / stop(...)` |
| `repeat {}` with timeout 1.5 s | `Timed out after 1.5s (limit set by the harness)`, returned after 1.51 s |
| `q('no')`, `f <- quit; f()`, `do.call('q', ...)` | blocked before evaluation, message tells the model to use the ask tool |
| `options(digits = 3); setwd(tempdir()); Sys.setenv(...)` | changes persist, reported as `[working directory changed: A -> B]`, `[options changed: digits]`, `[environment variables changed: GPTR_SECRET_TEST]` (names only) |
| 5000 lines of output | head 40% + tail 60% kept; full text spilled to `tempdir()` |
| UTF-8 `café 中文 λ`, `"ü"` | correct in a UTF-8 locale (in the C locale R's `print` escapes non-ASCII; that is locale behaviour, not capture) |
| `txtProgressBar` with `\r` | carriage returns collapsed |
| self-sent SIGINT | `[interrupted by the user]`, partial output kept, `1 of 4 top-level expressions completed` (verifier re-run: `2 of 4`; the count depends on when the asynchronous signal lands, so tests must not assert it) |
| `rlang::abort()` with bullets | message keeps the `ℹ` bullet; traceback `ff() / rlang::abort(...)` |
| `a1 <- 1; stop("mid"); a2 <- 2` | stops at `stop`; `a1` exists, `a2` does not |

Extra edge cases (`W12/exp_a10_sink_errors.R`): a user sink followed by an error cleans the sink
stack. Nested `capture.output()` works. `cli::cli_alert_success()` is captured (cli emits message
conditions). A user's `sink(type = "message")` does **not** receive `message()` output, because the
harness muffles messages first (evaluate behaves the same). `cat(file = stderr())` is **not**
captured; it goes straight to the console's stderr.

#### A5. Plots: showing to the user and capturing for the model (VERIFIED)

- `?dev.control` (the `dev2` Rd page): "Initially recording is on for screen devices, and off for
  print devices" (executed `Rd2txt`). `grDevices::dev.displaylist()` is internal and must not be used (CRAN:
  "::: should not be used to access undocumented/internal objects in base packages"). Just call
  `dev.control(displaylist = "enable")` on the device to be recorded. It is a no-op for screen
  devices and makes file devices recordable.
- Device-following capture (`W12/exp_a8_devices.R`, Rscript and `R --interactive`):
  (a) user device already open with an old plot: 2 new plots captured, the old one not
  re-reported, the user's device still current afterwards;
  (b) code does `png(f); plot(); dev.off()`: plot captured and file written;
  (c) no device at start, interactive (the default device opened lazily by the code): 2 plots
  captured, device left open for the user; non-interactive: private recording device, 2 plots,
  no `Rplots.pdf`.
- **knitr nesting** (`W12/knit/nested.Rmd` then `nested.md`): with `plots = "auto"` the model's plot
  appears in the document as `![plot of chunk agent](figure/agent-1.png)` directly after the chunk
  that called the agent, and the model also got the PNG. With `plots = "offscreen"` the document
  does not show it. IRkernel calls
  `evaluate(request$content$code, envir = .GlobalEnv, output_handler = oh, stop_on_error = 1L)`
  inside `tryCatch(interrupt = ...)` (executed: deparse of `IRkernel:::Executor` method `execute`),
  so the same device-following behaviour should put agent plots into Jupyter cells (**LIKELY**; not
  run, since no Jupyter is installed).
- Replay across devices works for base, grid and ggplot2 4.0.2 (`W12/out/a1_ragg_4.png` visually
  checked). ragg PNGs were about half the size of quartz `png()` PNGs (11 KB vs 19 KB).
- Image budget for the model: Anthropic charges `⌈width/28⌉ × ⌈height/28⌉` visual tokens. The long
  edge is limited to 1568 px (standard tier) or 2576 px (Claude 4.7+). Maximum 10 MB base64 per
  image on the Claude API (5 MB on Amazon Bedrock and Google Cloud), 8000x8000 px, and 2000 px when
  a request has more than 20 images (images inside `tool_result` blocks count toward the 20)
  (https://platform.claude.com/docs/en/build-with-claude/vision). A 768x512 PNG is
  28 × 19 = **532 visual tokens**. Keep btw's 768 px default.

#### A6. Timeouts (VERIFIED, `W12/exp_a5_timeout.R`, `W12/exp_a5b_interactive_sleep.R`)

Limit 0.5 s, Rscript on macOS:

| Operation | Result | Returned after |
|---|---|---|
| `Sys.sleep(3)` | **not enforced** | 3.01 s |
| R `while` busy loop | "reached elapsed time limit" | 0.51 s |
| `for (i in 1:5e7) s <- s + i` | enforced | 0.50 s |
| `sort(runif(3e7))` (C) | not enforced | 2.21 s |
| `solve(2500x2500)` (reference BLAS) | not enforced | 27.68 s |
| `vapply(1:2e6, function(i) i + 1, 0)` | enforced | 0.51 s |
| `grepl()` on 5e6 strings (C) | not enforced | 38.75 s |
| `R.utils::withTimeout(Sys.sleep(3), 0.5)` | error only after the sleep (verifier re-run: no error at all, returned `NULL`) | 3.22 s (re-run 3.04 s) |
| `setTimeLimit(cpu = 0.5)` busy loop | "reached CPU time limit" | 1.98 s (verifier re-run 0.55 s) |

- `R --interactive`: a single `Sys.sleep(3)` is still not enforced. `30 × Sys.sleep(0.1)` is
  enforced after 0.87 s. `?setTimeLimit` says limits are "checked whenever a user interrupt could
  occur ... frequently in R code and during Sys.sleep, but only at points in compiled C and Fortran
  code identified by the code author". The documentation's "during Sys.sleep" claim did not hold
  on this build (UNCERTAIN whether it holds on Linux or Windows).
- `transient = TRUE` limits "apply only to the rest of the current computation". Inside gptr the
  "computation" is the whole `gptr()` call, so the harness **must** reset to `Inf` after each
  expression, or the next HTTP request to the model would be killed.
- Timeout detection: an error whose message contains
  `gettext("reached elapsed time limit", domain = "R")` or `"reached CPU time limit"`. The class is
  plain `simpleError`.
- The only hard timeout is a separate process (callr), which defeats in-memory compute. Offer it
  only as an explicit "isolated" mode. Do not use `tools::pskill()` watchdogs: on Windows pskill
  terminates the process.

#### A7. Interrupts (VERIFIED `W12/exp_a4_basics.R`, torture "interrupt")

`tryCatch(..., interrupt = function(e) ...)` catches a self-sent SIGINT (`class interrupt/condition`).
A calling handler for `interrupt` can `invokeRestart()` (VERIFIED). The first prototype caught
interrupts only inside the per-expression handler. The SIGINT then landed in harness code between
expressions and escaped. The fix is an outer `tryCatch(interrupt =)` around the whole loop, plus
`suspendInterrupts()` around cleanup (as evaluate 1.0.4 does).

#### A8. Restoring session state

Policy recommendation (reasoned): the agent's code has the **same persistent effects as the user
typing it**. This is consistent with "the script is the history" (REQ-24/25), because replaying
the script must reproduce the state. Therefore:
- Restore only the *harness-owned* options: `max.print` (1000), `width` (100), `warn` (1),
  `rlang_interactive` (FALSE), `cli.dynamic` (FALSE), `cli.num_colors` (1), `askYesNo`, and
  `try.outFile`.
- **Report** everything else that changed. Report the working directory, *pre-existing* options
  that were changed or removed (options added by packages loaded during the call are
  `.onLoad` noise; e.g. `callr.condition_handler_cli_message` appeared, VERIFIED), environment
  variable **names only** (never values: secrets, REQ-13/D-22), attached packages, loaded
  namespaces, devices and new connections.
- Offer `isolate = TRUE` / `gptr.eval_restore` for btw-style reset. Implement it explicitly: remove
  new options with `options(setNames(vector("list", n), new_names))` and new env vars with
  `Sys.unsetenv()`. Do not rely on `withr::local_options()` / `local_envvar()` with no arguments
  (A3).
- `par()`: leave it alone in device mode (it is part of the user-visible plot state, like typing
  it). The private offscreen device is closed anyway.

#### A9. Session-killing and interactive functions (VERIFIED `W12/exp_a9_interactive_fns.R`)

Non-interactive behaviour with the guard off: `readline()` returns `""` immediately;
`menu()` errors "menu() cannot be used non-interactively"; `browser()` prints `Called from:` and
continues; `select.list()` errors; `readLines(file("stdin"))` returns `character(0)` when stdin
is `/dev/null`; `askYesNo()` errors through the `options(askYesNo=)` hook.
In an **interactive** console, `readline`, `menu`, `browser` and `debug*` would block the agent
waiting for keyboard input. Hence the static block list.
`options(rlang_interactive = FALSE)` makes `rlang::is_interactive()` FALSE while `interactive()`
stays TRUE, so `rlang::check_installed()` errors "The package ... is required." instead of
prompting (VERIFIED in `R --interactive`).
`q()` cannot be intercepted dynamically without modifying base (forbidden: "A package must not tamper
with the code already loaded into R", CRAN policy) or the global environment (`.Last`). Rejected.
The guard's dynamic-code category (`eval`, `parse`, `do.call`, `get`, ...) exists so the permission
layer can escalate: `eval(parse(text = "q()"))` evades the static guard.

#### A10. Output truncation

Pi's bash tool keeps the **last** 2000 lines or 50 KB and saves the full output to a temp file
(`packages/coding-agent/src/core/tools/truncate.ts` lines 11-13: `DEFAULT_MAX_LINES = 2000`,
`DEFAULT_MAX_BYTES = 50 * 1024`; `bash.ts` line 258 tool description; schema lines 40-43
`{command, timeout?}` with "no default timeout"). For R, head and tail are both informative: printed
headers at the top, errors at the bottom. Use **40% head + 60% tail** with a
`[... N lines omitted ...]` marker, a spill file in `tempdir()` (CRAN-safe), and Pi's limits
(2000 lines / 50 000 characters). Clean first: strip ANSI CSI and OSC 8 sequences, collapse `\r`
progress bars (VERIFIED on `txtProgressBar`), and set `options(max.print = 1000, width = 100)`
during evaluation.

### 2.B Target environment

#### B1. What `parent.frame()` is (VERIFIED `W12/exp_b1_parent_frame.R`)

| Call site | `parent.frame()` inside `gptr()` |
|---|---|
| top level (console, Rscript, `source(file)`) | `globalenv()` |
| inside `f()` | `f`'s frame |
| `local({...})` | the local environment |
| `source(file, local = TRUE)` inside `g()` | `g`'s frame |
| `"x" \|> gptr()` (native pipe: a syntax transform) | the caller (`globalenv()`) |
| `"x" %>% gptr()` (magrittr 2.0.5) | **anonymous mask env (only binding `.`), parent = caller** |
| `lapply(1, function(i) gptr())` | the anonymous function's frame |
| `lapply(1, gptr)`, `vapply`, `Map` | the internal frame of lapply/Map (parent `namespace:base`) |
| `purrr::map(1, gptr)` | purrr's internal frame |
| `do.call(gptr, list())` | caller |
| `tryCatch(gptr())`, `withCallingHandlers()`, `suppressWarnings()` | caller |
| `with(df, gptr())`, `dplyr::summarise(df, v = gptr())` | a data-mask environment |
| `eval(quote(gptr()), e)` | `e` |
| R6 method, S4 method, `testthat::test_that()` block | that frame |
| knitr chunk (`knitr::knit()` called at top level) | `globalenv()` (VERIFIED in `W12/knit/nested.Rmd`) |
| IRkernel cell | `globalenv()` (`evaluate(..., envir = .GlobalEnv)`) |

Objects created by the agent in a transient frame vanish when that frame ends. That is correct
for programmatic use inside functions and consistent with R semantics. The one surprising case is
magrittr: `mtcars %>% make_obj("x")` left `exists("x") == FALSE` (VERIFIED `W12/exp_b2_magrittr.R`).
The heuristic "if `envir` is not global and its only binding is `.`, use `parent.env(envir)`"
fixed it (VERIFIED).

#### B2. What CRAN forbids and what R CMD check detects

- Policy text (https://cran.r-project.org/web/packages/policies.html, revision 6875, VERIFIED):
  "Packages should not modify the global environment (user's workspace)." Nearby: "Nor may R
  code call q()"; "Packages should not send information about the R session to the
  maintainer's or third-party sites without obtaining confirmation from the user"; "::: should
  not be used to access undocumented/internal objects in base packages"; "Limited exceptions
  may be allowed in interactive sessions if the package obtains confirmation from the user" (said
  of file-system writes).
- Automated detection (executed `print(tools:::.check_package_code_assign_to_globalenv)`): a
  purely static search for `assign()` calls whose `envir` evaluates to `globalenv()` or whose `pos`
  maps to it (excluding `.Random.seed`). The message is "Found the following assignments to the
  global environment:". A companion check covers `data(..., envir = .GlobalEnv)`.
- Toy package results (`W12/toypkg`, `R CMD check --as-cran`, VERIFIED):
  `assign("x1", 1, envir = .GlobalEnv)` and `assign("x2", 1, envir = globalenv())` are reported;
  `x6 <<- 1` gives "no visible binding for '<<-' assignment". **Not** reported:
  `function(envir = parent.frame()) assign(..., envir = envir)`,
  `function(code, envir = parent.frame()) eval(parse(text = code), envir)`, `.GlobalEnv$x <- 1`,
  `eval(quote(x <- 1), globalenv())`, `list2env(..., envir = .GlobalEnv)`, and `utils::data()` with
  a namespace prefix. CRAN reviewers also grep manually, so the undetected forms are still policy
  violations if the package does them on its own initiative.
- A toy package containing the three final prototypes passes "checking R code for possible
  problems" with **no NOTE**. `sink`, `setHook`, `setTimeLimit`, `options`, `eval`, `parse`,
  `addTaskCallback`-free code and `requireNamespace("ragg")` with ragg in Suggests are all clean
  (VERIFIED `W12/toygptr.Rcheck/00check.log`; the only findings were undocumented objects and
  "unable to verify current time" from the offline sandbox).

#### B3. How other packages handle it (VERIFIED signatures, executed)

| Package / function | Default target | Notes |
|---|---|---|
| `base::load(file, envir = parent.frame())` | caller | the closest precedent |
| `base::source(local = FALSE)` | `globalenv()` | base R |
| `utils::data(envir = .GlobalEnv)` | `globalenv()` | base R only |
| `knitr::knit(envir = parent.frame())`, `rmarkdown::render(envir = parent.frame())` | caller | |
| `evaluate::evaluate(envir = parent.frame())` | caller | |
| `targets::tar_load(names, ..., envir = parent.frame())` | caller | "R environment in which to load target return values" (https://docs.ropensci.org/targets/reference/tar_load.html) |
| `shiny::loadSupport(appDir, renv = new.env(parent = globalenv()), globalrenv = globalenv())` | `global.R` into `globalenv()` | by design, on CRAN |
| `btw::btw_tool_run_r_impl(code, .envir = global_env())` | `globalenv()` | on CRAN 1.5.0, off by default |
| IRkernel | `.GlobalEnv` | |
| reprex | separate `callr` process | touches no workspace |
| testthat | child env of the test env | |

#### B4. Recommendation

`gptr(..., envir = parent.frame())`, with the magrittr fix. Never write `.GlobalEnv` or `globalenv()`
as an assignment target in package code. Proposed documentation wording (for `?gptr`, argument
`envir`):

> *The environment in which the agent evaluates R code and creates objects. Defaults to the
> environment `gptr()` is called from: at the top level of a session that is the global
> environment, so objects the agent creates are available to you afterwards, exactly as if you had
> run the code yourself. Inside a function they are created in that function's frame. Pass
> `envir = new.env()` to keep the agent's objects separate. gptr never modifies an environment you
> did not call it from.*

Tests and examples must pass `envir = new.env()` or run inside `local()`, and gate all live
behaviour behind `if (interactive())` or `\dontrun{}`. For the third-party data policy: the
per-turn workspace summary (object names, classes, dimensions, sampled values) *is* session
information sent to a provider. Justify it by the explicit user call. Document it, provide
`context = "none" / "names" / "summary"` (default `"summary"`), and on the first interactive use
print a one-time notice that describes what is sent. **UNCERTAIN (verifier):** the policy text
(revision 6875, re-read) asks for "obtaining confirmation from the user", not only a notice. Whether
an explicit `gptr()` call counts as that confirmation is a judgment for CRAN reviewers. The safer
reading is an explicit first-run opt-in (for example an interactive yes/no prompt, or an option or
environment variable that the user sets), with `context = "none"` until then in non-interactive
sessions.

### 2.C Introspection of large objects

#### C1. Non-forcing detection (VERIFIED `W12/exp_c1_promises.R`)

- Do not force: `ls()`, `exists()`, `bindingIsActive()`, `rlang::env_binding_are_lazy()`,
  `rlang::env_binding_are_active()`.
- Force a promise or call an active binding: `get()`, `get0()`, `mget()`, `as.list(env)`,
  `eapply()`, `rlang::env_get()`.
- A promise expression is readable with `eval(call("substitute", as.name(nm)), env)`, but **not
  for `globalenv()`**, where it returns the bare symbol (as documented in `?substitute`).
- `lazyLoad()` bindings (the mechanism behind knitr `cache.lazy = TRUE`) are detected as lazy.
  Forcing one loaded the data (heap +7.7 MB for a 1e6-double object).
- Base R has no function whose name mentions "promise" (executed
  `grep("romise", ls(baseenv(), all.names = TRUE))` → none). This is one reason to use rlang.

#### C2. Sticky references: the discipline (VERIFIED; many fresh-process tracemem runs)

Mechanism: `R_CleanupEnvir()` (R 4.4.3 `src/main/eval.c` lines 2137-2164,
https://github.com/wch/r-source/blob/tags/R-4-4-3/src/main/eval.c; copy in
`W12/ext/eval_R-4-4-3.c`) clears a returning closure's bindings and promises only when
`REFCNT(rho)` minus simple self-cycles (`countCycleRefs`, lines 2063-2090) is 0. Its
list-cleanup helper `cleanupEnvVector()` is disabled ("FIXME: Disabled for now", lines 2115-2135).
So a list that ever held the object leaves its reference count raised. Once a value's refcount is
above 1, `x[i] <- v` must duplicate it.

Plain R baselines (`W12/exp_c6_baselines.R`, `W12/out/copycheck_final.txt`):

| Operation (5e6 doubles unless noted) | Next in-place edit |
|---|---|
| `v[1] <- 0`, `m[1,1] <- 0`, `L[[1]][1] <- 0`, `L$a[1] <- 0`, `data.table::set()` | in place |
| `sp@x[1] <- 0` (S4 slot), `df$a[1] <- 0`, `f[1] <- "a"` (factor) | **copy anyway** in plain R (verifier re-run: S4 slot and factor copied on every edit; `df$a[k] <- 0` alternated copy, in place, copy, in place over 6 edits, so data.frame columns are not reliably in place rather than always copied) |
| after `str(v)` at the console | COPY (in plain interactive R too) |
| after `lobstr::obj_size(v)` | COPY |
| after `withVisible(v)` | COPY |
| after `utils::object.size(v)`, `rlang::hash(v)`, `rlang::obj_address(v)`, `head(v)`, `anyNA(v)`, `summary(v)` | in place |
| after the R REPL auto-prints `x` or evaluates `invisible(x)` (`R --interactive`) | in place |

Patterns that caused COPY inside a function binding the object (`W12/exp_c8`, `c11`–`c17`):
`tryCatch(dim(x), error = function(e) NULL)`; `try(...)`; `vapply(1:2, function(i) ..., 1)`
(even when the closure does not touch `x`); a byte-compiled `for` loop calling a closure whose
argument derives from `x`; `sort(table(...))` or `rm()` called later in the same frame; a
`new.env()` whose default parent is the frame. Patterns that were safe: primitives (`length`,
`dim`, `class`, `attr`, `attributes`, `names`, `[`, `[[`, `.subset`, `.subset2`, `isS4`,
`is.*`); thin `.Internal`/`.Call` wrappers (`typeof`, `inherits`, `utils::object.size`,
`.row_names_info`, `rlang::obj_address`, `rlang::hash`); loops using only those; and passing
the object into a closure-free leaf function.

The rule set adopted, called the **leaf / formatter / by-name** discipline:
1. Only *leaf* functions bind a user object. Leaves call primitives and thin wrappers only, and
   return fresh small facts (classes, lengths, a small `.subset()` sample).
2. *Formatters* turn facts into text using any R code. They never see the object, and they
   `force()` all their arguments first so that no unforced promise points back to a caller frame.
3. Loops, `tryCatch()` and `*apply` live only in frames that address objects **by name**
   (`get(name, envir = env)` passed directly as a leaf argument).
4. The evaluator never puts the value of `sym` or of an assignment into a list (A12).
5. The gateway never forces context promises. It uses `rlang::enquos()` and inspects by name (D2).
6. Every public entry point gets a fresh-process tracemem regression test (§5.4). Skip it when
   `!capabilities("profmem")`.

#### C3. Sizes (VERIFIED `W12/out/c2_bigobjects.txt`)

| Object | `object.size` time | `lobstr::obj_size` time | Sizes reported |
|---|---|---|---|
| `m` 12000×10000 double | 0.000 s | 0.000 s | 915.5 MB / 915.5 MB |
| `L` list of 2e6 length-4 doubles | 0.053 s | 1.689 s | 167.8 MB / 167.8 MB |
| `chr` 5e6 unique strings | 0.225 s | 1.462 s | 343.3 MB / 343.3 MB |
| `df` 1e7 × 4 | 0.000 s | 0.000 s | 190.7 MB / 190.7 MB |
| `alt <- 1:1e9` (ALTREP) | 0.000 s | 0.000 s | **3.7 GB** / **680 B** |
| `str(L, max.level = 1, list.len = 8)` | 1.768 s (and bumps the refcount) | | |

Neither function forces ALTREP materialisation of the compact sequence, but `sum(is.na(x))` would
allocate a 1e9 logical. **Verifier addition (VERIFIED, re-run):** `object.size()` is slow on ALTREP
*deferred-string* vectors (`as.character(<double>)`): 9.1 s for 5e6 elements and 2.6 s for 2e6
elements, against 1.7 s for `lobstr::obj_size()`. Treat that ALTREP class as a case for a size
budget or for skipping the size. Also, `rlang::hash(1:1e7)` differs from the hash of an equal
materialised vector, because the hash follows the serialised representation. A representation change
can therefore show up as "modified" without a value change.
Hence all value statistics use an evenly spaced sample of ≤ 1e5 elements via `.subset()`. Do not
use `anyNA()` on large ALTREP vectors from lazy readers such as vroom: it would materialise them
(LIKELY; not tested with vroom).

#### C4. 2 GB workspace run (VERIFIED `W12/exp_c18_bigworkspace.R`, output `W12/out/c18_bigworkspace.txt`)

Built in 27.8 s. Per-object `gptr_describe_binding()` with a cold size cache: m 0.034 s, L 0.311 s,
chr 0.736 s, df 0.203 s, dt 0.070 s, alt 0.051 s, sp 0.055 s, fit 0.026 s, Seurat 0.009 s,
SummarizedExperiment 0.004 s, arrow Table 0.045 s, duckdb 0.004 s, R6 0.006 s, promise and active
binding 0.000 s. Snapshot of 61 bindings: **0.78 s cold, 0.09 s warm**. Workspace summary: 0.02 s.
(Verifier re-run with the §5.2 code: built in 8.8 s; snapshot 0.26 s cold, 0.02 s warm; the same
139.2 MB peak, 0 copies, promise not forced, active binding not called. Timings vary between runs.)
gc "max used" rose **139 MB** during all introspection. **0 copies** on the user's next edits of
`m`, `L[[1]]` and `dt$a`. `lazy_big` was still a promise and the active binding was never called.
Example output (verbatim excerpts):

```
df: <data.frame> 10,000,000 x 4, 190.7 MB
  (column stats from an evenly spaced sample of 100,000 of 10,000,000 rows)
  $ a <numeric> min 4.955e-06, median 0.499, max 1; no NA in sample
  $ b <integer> min 1, median 50, max 100; no NA in sample
  $ f <factor> 26 levels, top: p (3963), z (3950), r (3913); no NA in sample
  $ l <logical> ~33337 TRUE; ~33.4% NA
seu: <S4 Seurat from SeuratObject> 396.1 KB
  @assays: <list> length 1; names: RNA
  @meta.data: <data.frame> 80 rows; names: orig.ident, nCount_RNA, nFeature_RNA, RNA_snn_res.0.8, letter.idents, groups, RNA_snn_res.1
  @reductions: <list> length 2; names: pca, tsne
lazy_big: <promise, not yet evaluated>
act: <active binding> (not evaluated)
---- format_gptr_env_diff() ----
+ new_obj <data.frame> 6 x 4, 3.2 KB
~ chr <character> length 5,000,000, 343.3 MB
- L
```

Known gaps in the same run: `m[6000, 5000] <- -1` (in place) and `set(dt, 12345L, "a", -1)` were
**not** reported as modified, because both objects are above 50 MB and the positions were not
sampled. The summary line for `sp` said "length 2,000,000,000", because `length()` of a dgCMatrix
is the product of its dimensions. Use the `Dim` slot for S4 matrices. The arrow Table was described
as an R6 environment (37 bindings); give `ArrowTabular` its own method (prototype below) so it
reports `num_rows` and the schema.

#### C5. Change detection

- Hash throughput (VERIFIED): `rlang::hash()` 0.25 s for the 916 MB matrix (3737 MB/s), 0.26 s for
  343 MB of character (1315 MB/s), 0.10 s for a 137 MB list. `xxhashlite::xxhash()` 0.13 s.
  `digest::digest(algo = "xxhash64")` 2.17 s (it serialises into memory first). `rlang::hash()`
  streams and did not raise the reference count. (Verifier re-run on the same objects: matrix
  0.15-0.33 s, i.e. 2.8-6.2 GB/s; character 0.24 s; list 0.10 s; xxhashlite 0.09 s; digest 1.15 s.
  The ranking is stable, but the absolute throughput varies, so budget with a margin.)
- Address semantics (VERIFIED c2/c18): copy-on-modify gives a new address (`chr[i] <- ...` on a
  shared vector, `df$a[i] <- ...`), but in-place edits keep it (`m[i, j] <- v` with refcount 1,
  `data.table::set()`).
- Recommended: fingerprint = full `rlang::hash()` when size ≤ `full_hash_max` (default 50 MB;
  adaptive up to 256 MB within a per-turn budget of about 1 s), else a hash of (class, length,
  dim, sampled attributes, 64 sampled elements; for lists, element addresses and three sample
  values). Plus:
- **`addTaskCallback()` history** (VERIFIED `W12/exp_c19_taskcb.R`): the callback receives each
  top-level expression the user runs (in Rscript and in interactive R) and did not cause a copy of
  the value it is handed. Registered only while a gptr session is active and removed with
  `removeTaskCallback()` in `on.exit()` and `.onUnload`. This gives the model "Since your last turn
  the user ran: `m[6000, 5000] <- -1`" and feeds REQ-25 (the script as history). Note (verifier
  re-run): the callback also fires for the top-level expression that registered it. When a
  `gptr()` call registers the callback, the first logged entry is that `gptr(...)` call itself,
  so filter it out.

#### C6. Describe as an extensible generic (VERIFIED)

An S3 method for an S4 superclass dispatches on S4 subclasses
(`f.SummarizedExperiment` was selected for a `RangedSummarizedExperiment`; executed). Packages and
skills can therefore register `gptr_describe.Seurat`, `gptr_describe.SingleCellExperiment` and so
on with `S3method(gptr::gptr_describe, Seurat)` or at run time (`registerS3method`), without gptr
depending on Bioconductor. Because S4 slot and `data.frame` column assignment copy anyway in plain
R, extension methods for those classes cannot make copying worse. Only methods for plain
vectors, matrices, arrays and lists need the leaf discipline.

### 2.D NSE and ergonomics

#### D1. Identifier rules (VERIFIED `W12/exp_de_gateway.R`)

Aliases known: `opus, sonnet, haiku, jev, gemini, codex, claude_code, gpt`. Caller variables:
`jev <- "a user variable..."`, `m <- "opus"`, `hard <- TRUE`, `mice <- data.frame(...)`.

| Call | Resolved `model` / `skills` |
|---|---|
| `model = jev` | `"jev"` (the alias wins over the variable, like `library(pkg)`) |
| `model = "opus"` | `"opus"` |
| `model = m` (`m` is not an alias) | `"opus"` (the variable's value) |
| `model = !!jev` | the variable's value (explicit injection) |
| `model = gpt5` (unknown, unbound) | `"gpt5"` (literal; validated later against the catalog) |
| `model = if (hard) opus else haiku` | `"opus"` (evaluated in the alias mask) |
| `skills = c(seurat, plotting)` | `c("seurat", "plotting")` |
| `skills = c(seurat, "my-skill")` | `c("seurat", "my-skill")` |
| `model = mice` (a data.frame variable) | error: `` `mice` is a variable of class <data.frame>, not a model/skill name. Quote the name ("mice") or pass a character value. `` |

A loop such as `for (mm in c("opus", "haiku")) gptr(task, model = mm)` works because `mm` is not an
alias. The only ambiguity is a variable named like an alias. The alias wins and `!!var` is the
documented escape.

#### D2. Why rlang `enquo()`/`enquos()` instead of base `substitute()` (VERIFIED)

- Forwarded dots: `w <- function(...) { v <- "WRAPPER-LOCAL"; g(...) }` with a global `v`. Base
  `substitute(list(...))` + `parent.frame()` resolved `v` to `WRAPPER-LOCAL v (wrong)`.
  `rlang::enquos(...)` + `quo_get_env()` resolved the correct `GLOBAL v`.
- Copy safety: a gateway that inspected `...elt(i)` in its own frame left sticky references
  (`gptr("describe", v)` then `v[1] <- 0` gave COPY). With `enquos()` plus by-name inspection, all
  five pipe and call forms were in place (§5.4). The residual case: if a *wrapper function binds the
  object as a named argument* (`w <- function(d) gptr("x", d)`), that wrapper's own promise holds it
  (COPY). This is inherent and documented.
- `!!x` is handled by `enquo()` at capture time, at no cost.
- Decision register D-07 said "base R only". This is **overturned with reason**: correctness for
  forwarded arguments, plus copy safety. The user-facing rules stay the simple ones in D1. rlang is
  already a hard dependency through httr2.

#### D3. Prompt selection and context labels (VERIFIED)

| Call | prompt | context labels |
|---|---|---|
| `gptr(task, model = haiku)` (`task` holds a string) | `task`'s value | – |
| `gptr("Is RCT?", abstracts, model = jev)` | "Is RCT?" | `abstracts` |
| `abstract \|> gptr("Is RCT?")` (a length-1 string on the LHS) | "Is RCT?" (the literal beats the value) | `abstract` |
| `mice \|> gptr("describe")` | "describe" | `mice` |
| `mice %>% gptr("describe")` | "describe" | `.` (magrittr hides the name; recommend `\|>`) |
| `gptr("compare", a = mice, b = head(mtcars))` | "compare" | `a`, `b` |
| `do.call(gptr, list("p", mtcars))` | "p" | `..2` (values, not code) |
| `gptr(prompt = "p", abstract)` | "p" | `abstract` |
| `gptr(glue::glue("n = {nrow(mice)}"))` | "n = 3" | – |
| `lapply(c("q1", "q2"), gptr)` | q1, q2 | – |
| `Map(gptr, prompts, model = "haiku")` | model haiku for each | – |
| `purrr::map(abstracts, gptr, "Is RCT?")` | **a1, a2, a3 (wrong)** | – |

The last row is inherent: purrr inlines each element as a constant, so it is indistinguishable
from a typed literal. Rule for programmatic use: **name the prompt** (`prompt = "..."`).

#### D4. Interpolation, raw strings, unquoted prompts

- **Do not auto-interpolate `{}`.** Prompts routinely contain code, JSON or LaTeX braces. Accept
  `glue` objects and `sprintf()`/`paste0()` output. glue is a transitive Import of httr2 but stays
  optional. An opt-in `gptr_prompt("... {nrow(df)} ...")` could evaluate in the caller if wanted.
- Raw strings `r"(...)"`, `r"[...]"`, `r"---(...)---"` (R ≥ 4.0) parse to ordinary constants, so
  they are detected as literals. Ordinary strings may also span lines (VERIFIED parse outputs).
- Unquoted natural language (executed `parse()`): `gptr(cluster the cells)` gives
  `unexpected symbol`, `gptr(it's broken)` gives `unexpected INCOMPLETE_STRING`, and
  `gptr(~ cluster the cells)` also fails. `gptr(hello)` parses, but as a symbol, and is useless.
  R's grammar gives juxtaposed symbols no meaning, so no function-level trick can accept prose.
  The nearest workable forms, in order:
  (1) the interactive console `gptr()`, which reads lines with `readline()` so the user types
  plain text;
  (2) a **knitr chunk engine**, where ```` ```{gptr} ```` blocks contain unquoted text with free
  quotes and braces (prototype VERIFIED in `W12/knit/engine.Rmd`; `glue` registers its engines the
  same way from `.onLoad`, VERIFIED `print(glue:::.onLoad)`);
  (3) an RStudio/Positron addin that wraps the current line in `gptr(r"(...)")`;
  (4) raw strings in scripts.

### 2.E Pipe semantics and the return object

VERIFIED (`W12/exp_de_gateway.R`):
- `gptr("p1") |> gptr("p2") |> gptr("p3", model = opus)`: one session, turn count 3, model
  switched on the last call. `gptr(session, "p4")` continues to turn 4.
- `gptr()` with no prompt, context or session: in a non-interactive session it errors with
  "gptr() without a prompt starts the interactive console and needs an interactive session."
- Designated value: the mocked agent code `fit <- lm(mpg ~ wt, data = mtcars); gptr_return(fit)`
  gives `class(res$value) == "lm"`, the print footer `<gptr_result> session s35, turn 1, model default, value: <lm>`,
  and `fit` also exists in the caller (created by the agent's code in `envir`).
- Copy safety of the gateway (§5.4): `gptr("describe", v)`, `v |> gptr("describe")`,
  `gptr("a") |> gptr("b", v, model = opus)` and forwarded dots all left `v` editable in place.

---

## 3. Exact specifications

### 3.1 Model-visible `r` tool (replaces Pi's `bash`; D-03, REQ-09)

Tool definition, provider-neutral JSON Schema. It mirrors Pi's bash schema `{command, timeout?}`
(`bash.ts` lines 40-43):

```json
{
  "name": "r",
  "description": "Run R code in the user's live R session. Objects you create persist in the user's workspace (by default the environment gptr() was called from) and are visible to later calls and to the user. Returns printed output, messages, warnings, errors (with a traceback) and plots (as images). Execution stops at the first error. Output is truncated to the first 40% and last 60% of 2000 lines / 50000 characters; the full text is saved to a temp file whose path is given. Rules: work in small steps; never re-load data that is already in memory; return values implicitly (write `x`, not `print(x)`) and prefer head()/str()-sized summaries; never call q(), quit(), readline(), menu(), browser() or install packages unless the user asked; to hand an R object back as the result of the request call gptr_return(obj).",
  "input_schema": {
    "type": "object",
    "properties": {
      "code":    { "type": "string", "description": "R code to evaluate. May contain several expressions." },
      "timeout": { "type": "number", "description": "Seconds (best effort: long-running C code cannot be interrupted). Default 300." }
    },
    "required": ["code"]
  }
}
```

Tool result for Anthropic-style APIs: `content = [ {type: "text", text: format(result)}, {type: "image", source: {type: "base64", media_type: "image/png", data: <png>}} ... ]`.
One image block per captured plot, in order, each preceded by the text marker
`[plot N attached as image]` in the text. Set `is_error = TRUE` when
`status %in% c("error", "timeout", "blocked", "parse_error")`. On `interrupt`, return the partial
result and **stop the agent loop**; control goes back to the user (REQ-38).

### 3.2 `gptr_eval_result` (S3, a list)

| Field | Type | Meaning |
|---|---|---|
| `status` | chr(1) | `"ok"`, `"error"`, `"timeout"`, `"interrupt"`, `"blocked"`, `"parse_error"` |
| `events` | list | ordered events (3.3) |
| `n_done`, `n_total` | int | top-level expressions completed / parsed |
| `changes` | list | `wd = c(from, to)`, `options` (chr names), `envvars` (chr **names only**), `attached`, `loaded`, `devices = list(from, to)`, `connections_opened` |
| `elapsed` | dbl | seconds |
| `value`, `visible` | NULL/FALSE | always NULL/FALSE. The evaluator never keeps the value (copy safety); results are designated with `gptr_return()`. |

### 3.3 Event types

- `source`: `text` (the source of one top-level expression), `line` (first line number).
- `output`: `text` (stdout, raw, possibly with ANSI or `\r`).
- `message`: `text`.
- `warning`: `text`, `call` (deparsed, or NULL).
- `error`: `message`, `call`, `class` (chr), `line`, `timeout` (lgl), `traceback` (chr lines).
- `interrupt`: `message`.
- `plot`: `plot` (a `recordedplot`), `index`, `device` (name), `file` (PNG path or NULL),
  `render_error`.

### 3.4 Model-facing text (`format.gptr_eval_result`)

```
<stdout, ANSI stripped, \r collapsed>
<message text>
Warning in f(): warn in f
Error in g(v): boom: z  [expression at line 15]
Traceback (outermost first):
 1: h("z")
 2: g(v) at <gptr>#14
 3: stop("boom: ", v) at <gptr>#13
[plot 1 attached as image]
[working directory changed: A -> B]
[options changed: digits]
[environment variables changed: GPTR_SECRET_TEST]
[attached: package:data.table]
[status: error; 15 of 17 top-level expressions completed; 0.12s]
[output truncated: 5000 lines, 285893 characters in total; full text in /tmp/.../gptr-output-1a2b.txt]
[no output]      <- only when nothing at all was produced
```

Traceback frames are trimmed to user code: everything up to and including the harness's
`.gptr_eval_frame` marker is dropped, leading `eval(expr, envir)` frames are dropped, and trailing
condition-system frames are dropped (`.handleSimpleError`, `.signalSimpleWarning`,
`signalCondition`, `withRestarts`, `withOneRestart`, `doWithOneRestart`, `signal_abort`,
`withCallingHandlers`, plus the handler frame itself). Beyond 20 frames it shows the first 5 and
the last 15. Each line is at most 120 characters. `at <file>#<line>` comes from the call's
`srcref` (code is parsed with `srcfilecopy("<gptr>", code)`).

### 3.5 Constants and defaults (recommended)

| Name | Default | Notes |
|---|---|---|
| timeout per `r` call | 300 s | best effort (A6) |
| `max.print` / `width` during eval | 1000 / 100 | restored afterwards |
| truncation | 2000 lines / 50 000 chars; head 40% / tail 60% | Pi uses 2000 lines / 50 KB tail-only |
| plot PNG | 768 px long side, ratio 1.5 (768x512), res 96 | 532 Anthropic visual tokens |
| plot device for PNG | `ragg::agg_png()` if installed, else `grDevices::png()` | on Linux without X11 use `type = "cairo"` when `capabilities("cairo")` |
| recording device (offscreen) | `ragg::agg_record()` else `pdf(file = NULL)` | the same as evaluate |
| value sample for statistics | 1e5 evenly spaced elements | `.subset()`; no full-length allocation |
| data.frame columns described | 60 | the rest listed by name |
| list elements described | first 6 (classes tallied over the first 1000) | |
| fingerprint | full `rlang::hash()` ≤ 50 MB; otherwise 64 samples + 8 head + 8 tail | |
| describe budget | 300 tokens per object; workspace summary 600 tokens | 3.5 chars per token heuristic |

### 3.6 Guard lists (`.gptr_guard_rules`, advisory)

- `block` (never evaluated): `q, quit, browser, debug, debugonce, undebug, recover, readline, menu, select.list, file.choose, askYesNo, fix, edit, de, data.entry, dataentry, locator, identify, setTimeLimit, setSessionTimeLimit, closeAllConnections, .Internal, .Primitive`.
  Also matched when called as `base::q`, via `do.call("q")`, `match.fun("q")`, `get("q")`,
  `lapply(x, "q")`, when the symbol `quit`/`q` is passed as FUN to `lapply`/`sapply`/`Map`/..., or
  when `quit` is bound (`f <- quit`). **Gap (verifier re-run):** binding `q` itself
  (`g <- q; g()`) is *not* blocked. The prototype flags a bare `quit` symbol anywhere, but not a
  bare `q`, because `q` is a common variable name. Fix it by flagging `q` on the right-hand side of
  `<-`/`=`/`assign()`.
  **TODO:** detect stdin readers by argument (`readLines("stdin")`, `file("stdin")`, `scan()` with
  no file); the pseudo-names in the prototype do not match anything.
- `session` (allowed, reported, permission-gated): `setwd, sink, options, Sys.setenv, Sys.unsetenv, Sys.setlocale, attach, detach, library, require, loadNamespace, unloadNamespace, graphics.off, dev.off, set.seed, rm, remove, assign, <<-`.
- `system` (outside the R process): `system, system2, shell, shell.exec, pipe, Sys.chmod, unlink, file.remove, file.rename, file.copy, writeLines, saveRDS, save, write.csv, fwrite, download.file, install.packages, remove.packages, update.packages, pskill, processx::run`.
- `dynamic` (can hide anything): `eval, evalq, parse, str2lang, str2expression, do.call, match.fun, get, get0, mget, getExportedValue, source, sys.source`.

### 3.7 Exact strings relied upon

- Timeout error message: `reached elapsed time limit` or `reached CPU time limit` (translated through
  `gettext(msg, domain = "R")`; class `simpleError`).
- Interrupt condition class: `c("interrupt", "condition")`.
- R CMD check: `Found the following assignments to the global environment:`;
  `no visible binding for '<<-' assignment to 'x6'`.
- CRAN policy: "Packages should not modify the global environment (user's workspace)."
  "Nor may R code call q()." "Packages should not send information about the R session to the
  maintainer's or third-party sites without obtaining confirmation from the user."

### 3.8 Workspace snapshot (`gptr_env_snapshot(envir, full_hash_max = 5e7)`) → data.frame

Columns: `name` (chr; all names, including dot-names; `.Random.seed` and `.Last.value` excluded),
`kind` (`"value"`, `"promise"`, `"active"`), `address` (chr, `rlang::obj_address`), `class` (chr,
`/`-joined), `bytes` (dbl, `object.size`, cached by `address|length|class`; NA for environments,
functions and external pointers), `shape` (`"12,000 x 10,000"`, `"10,000,000 x 4"`,
`"length 5"`), `fp` (chr fingerprint; for environments a hash of binding names and addresses; for
functions the address).
`gptr_env_diff(old, new)` returns `list(added, removed, modified)`. Modified means the kind,
address or fingerprint differs. `format_gptr_env_diff()` gives lines like `+ name <class> shape, size`,
`~ ...`, `- name`.

### 3.9 Describe contract

```r
gptr_describe(x, budget = 300L, ...)   # S3 generic; returns character lines; first line is a header
                                       # "<class/..> shape, size"
gptr_describe_binding(name, envir, budget = 300L)   # safe entry: no forcing, errors caught
gptr_workspace_summary(envir, budget = 600L, snapshot = gptr_env_snapshot(envir))
```

Built-in methods: `default` (atomic vectors, S4 fallback), `data.frame` (covers tibble and
data.table, and shows a data.table key), `matrix`, `list`, `environment`, `R6`, `function`
(signature, srcref location, first 6 lines), `lm`/`glm`, S4 (slots through `attr()`), plus in the
earlier prototype `dgCMatrix`, `ArrowTabular`, `DBIConnection` and `ggplot`. **Method contract for
extension authors:** return ≤ `budget` tokens of plain text; never force promises or call methods
that do I/O (no `dbListTables`, no `collect()`); for plain vectors, matrices and lists follow the
leaf discipline (C2).

### 3.10 Gateway signature and objects

```r
gptr(..., model = NULL, skills = NULL, extensions = NULL, plugins = NULL,
     prompt = NULL, mode = NULL, envir = parent.frame())
```

- Dots: at most one leading `gptr_result`/`gptr_session` (continuation), one prompt (selected as in
  D3), and the rest are context. Context is stored as **quosures** (expression + environment) with
  labels. Symbols are read by name when needed, and values of calls are fresh.
- `gptr_result` (a list; class `"gptr_result"`): `text` (chr, the final assistant text), `value`
  (whatever `gptr_return()` received, else NULL), `has_value` (lgl), `session` (a `gptr_session`
  environment), `usage` (`input_tokens`, `output_tokens`, `cost`), `model` (chr), `streamed` (lgl),
  and in the prototype `attr(, "turn")`. Methods: `print` (text plus a footer
  `<gptr_result> session s3, turn 2, model anthropic/claude-sonnet-5-5, value: <lm>`),
  `format` and `as.character` (return `text`).
- `gptr_session`: an environment with class `"gptr_session"`, fields `id`, `turns`, `envir`, plus
  (other tracks) the message history, model and config. Environments give reference semantics, so
  `r1` and `r2` in a pipe share one session.
- Visibility: return `invisible(res)` when the answer was already streamed to the console
  (interactive), otherwise visibly (knitr, Rscript and non-streamed calls print the answer).
- `gptr_return(value)`: errors unless called while a request is running. Stores into the running
  request (`the$current`). The returned object is shared with `envir`, not copied.

### 3.11 NSE resolution algorithm (`gptr_resolve_ids(expr, env, known)`)

```
NULL                       -> NULL
character constant         -> itself
symbol s:  s in known       -> "s"
           exists(s, env)   -> value, if character or gptr_id; else error "is a variable of class <..>"
           otherwise        -> "s"
call !!x                   -> as.character(eval(x, env))   (enquo already did this)
call c(...) / list(...)    -> unlist(lapply(args, resolve))
any other call             -> eval(expr, mask) with mask = list2env(setNames(as.list(known), known), parent = env),
                              mask$.env <- env   (so `.env$x` reaches the caller's variable)
```

`known` is the union of model aliases from the catalog (D-18), discovered skill, extension and
plugin names, and live session objects.

### 3.12 knitr engine

```r
# in .onLoad (the pattern glue uses; VERIFIED print(glue:::.onLoad))
if (isNamespaceLoaded("knitr")) register_gptr_engine() else
  setHook(packageEvent("knitr", "onLoad"), function(...) register_gptr_engine())
register_gptr_engine <- function() knitr::knit_engines$set(gptr = function(options) {
  prompt <- paste(options$code, collapse = "\n")
  res <- if (isTRUE(options$eval)) gptr(prompt = prompt, model = options$model, envir = knitr::knit_global())
  knitr::engine_output(options, options$code, if (is.null(res)) "" else format(res))
})
```

A chunk looks like ```` ```{gptr, model = "opus"} ```` and contains plain prose.

### 3.13 Image cost

Anthropic: `ceil(w/28) * ceil(h/28)` visual tokens; standard tier maximum long edge 1568 px or 1568
tokens; Claude 4.7+ maximum 2576 px or 4784 tokens; ≤ 10 MB base64 per image on the Claude API
(≤ 5 MB on Amazon Bedrock and Google Cloud); > 20 images in a request (tool-result images
included) forces ≤ 2000 px (https://platform.claude.com/docs/en/build-with-claude/vision).

---

## 4. Recommended design for gptr

### 4.1 Files and functions

| File | Contents |
|---|---|
| `R/eval.R` | `gptr_eval()` (internal, or exported for power users as `gptr_run_r()`), `.gptr_eval_core()`, `.gptr_eval_top()`, `.gptr_eval_frame()`, guard, devices, traceback, truncation, `format/print.gptr_eval_result` (start from `W12/gptr_eval2.R`) |
| `R/introspect.R` | leaves, formatters, the `gptr_describe()` generic (**exported** so extensions can add methods), `gptr_describe_binding()`, `gptr_env_snapshot()`, `gptr_env_diff()`, `gptr_workspace_summary()` (exported for users; start from `W12/gptr_introspect.R`) |
| `R/gateway.R` | `gptr()`, `gptr_resolve_ids()`, `.gptr_dot_facts()`, `gptr_target_env()`, `gptr_result` / `gptr_session` constructors and methods, `gptr_return()` (exported) (start from `W12/gptr_gateway.R`) |
| `R/history.R` | `.gptr_history_start(session)` → `addTaskCallback(cb, name = "gptr_history")`; `.gptr_history_stop()`; also called from `.onUnload` |
| `R/knitr.R` | engine registration (3.12) |

### 4.2 Per-turn workspace context (the part the model always sees)

At the start of every user turn in a session:

1. `snap <- gptr_env_snapshot(session$envir)`. Warm cost is about 0.1 s for 60 objects / 2 GB.
2. `d <- gptr_env_diff(session$last_snapshot, snap)`; `session$last_snapshot <- snap`.
3. Build a `<workspace>` block within about 1000 tokens:
   `gptr_workspace_summary()` (one line per object, largest first, 600 tokens),
   `format_gptr_env_diff(d)` ("changes since your last turn"), and the task-callback history
   ("the user ran: ...", last 20 expressions, 200 tokens), plus the attached context objects'
   `gptr_describe_binding()` (300 tokens each).
4. Anything deeper the model asks for itself through the `r` tool (`str(x)`, `head(x)`,
   `gptr_describe(x)`), so no extra model-visible tool is needed (D-03).
5. Respect `context =` (`"none"`, `"names"`, `"summary"`) and a one-time interactive notice (CRAN
   third-party data line, B4).

### 4.3 Evaluator algorithm (summary of `gptr_eval2.R`)

1. Parse with `srcfilecopy()`. Stop on a parse error.
2. Run the static guard. Blocked calls return immediately with a message that points to the ask
   tool.
3. Set the harness options (3.5), remembering the old values.
4. Open the capture: `con <- file("", "w+b")`; `sink(con, split = tee)`;
   `options(try.outFile = con)`. The reader recovers from a closed connection and from a popped
   sink. Cleanup runs inside `suspendInterrupts()` and pops **every** sink at or above ours.
5. Choose the plot mode (A5). Enable the display list on the recorded device. Take a baseline
   `recordPlot()`. Set hooks `before.plot.new`, `before.grid.newpage` and `persp`.
6. For each top-level expression: set `setTimeLimit(elapsed = remaining, transient = TRUE)`. Run
   `withRestarts(withCallingHandlers(.gptr_eval_top(...), message=, warning=, error=, interrupt=), gptr_stop=)`.
   The error handler records `sys.calls()` **first**. Reset the time limit.
7. Wrap the whole loop in `tryCatch(interrupt =)`.
8. Final snapshot and flush. Replay plots to PNG. Compute the state diff **after** cleanup.
9. `.gptr_eval_top()`: a symbol is printed as `print(<symbol>)` evaluated in `envir`; calls
   headed by `<-`, `=`, `<<-`, `invisible`, `for`, `while`, `repeat`, `library`, `require`,
   `print`, `cat`, `message`, `suppressPackageStartupMessages`, `set.seed`, `options`, `rm`,
   `setwd` or `stopifnot` are evaluated **without** `withVisible()`; anything else uses
   `withVisible()`. That is harmless for fresh values; the residual case is a visible passthrough
   such as `(x)` or `identity(x)` (§5.4).
10. `tee = interactive()`, so the user sees output live, is the recommended default for the console
    session. In knitr and Rscript use `tee = FALSE`.

### 4.4 Package choices

- **Imports:** `rlang (>= 1.1.0)` (already pulled in by httr2, and needed for `enquo`/`enquos`,
  `obj_address`, `hash`, `env_binding_are_lazy`/`active`), plus base `grDevices`, `graphics`,
  `methods`, `stats`, `utils`.
- **Suggests:** `ragg` (better and faster PNGs, and `agg_record`), `knitr` (engine), `glue`,
  `magrittr`, `purrr`, `Matrix`, `data.table`, `arrow`, `DBI` (tests and methods registered
  conditionally). Also `callr` for an optional isolated mode, owned by another track.
- **Not used:** `evaluate` (A2), `lobstr` (slow on lists, sticky references), `R.utils`
  (withTimeout adds nothing), `pryr` (archived), `digest` (slower than `rlang::hash`).
- Minimum R: 4.1.0 (native pipe) satisfies everything used here: `...elt` 3.5, `tryInvokeRestart`
  4.0, raw strings 4.0, `suspendInterrupts` 3.5. **Recommend R ≥ 4.2 on Windows** so the native
  encoding is UTF-8 (6.2).

### 4.5 Decision-register positions

- **D-03:** keep `r` as the only evaluation tool. Description, workspace and diff are context, not
  tools.
- **D-04:** confirmed: `envir = parent.frame()` + magrittr fix + explicit `envir`. Inline
  sub-agents get `new.env(parent = caller)`; per C2, create it with an explicit parent.
- **D-05:** confirmed: `gptr_result`; the value is designated via `gptr_return()`.
- **D-07:** amended: rlang `enquo`/`enquos` (reason: forwarded dots and copy safety), keeping the
  base-simple rules of D1.
- **D-19:** truncation spec 3.5.
- **D-20:** add rlang to Imports (zero marginal cost).
- **D-26:** `tee` live output; interrupt returns control.
- **D-27:** register a `gptr` knitr engine (cheap, the pattern glue uses).

---

## 5. Verified R prototypes

Everything below was executed with `Rscript --vanilla` on R 4.4.3 from `W12/`. The UTF-8 runs used
`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`. Outputs are copied from the terminal; the full outputs are
in `W12/out/`.

### 5.1 Evaluator: `W12/gptr_eval2.R` (final, complete)

```r
# gptr_eval2.R -- reference prototype of gptr's live-session R evaluator (Track 12)
# Base R only (grDevices, graphics, utils, methods); ragg used when installed.
# Hand-rolled, modelled on evaluate 1.0.5's watchout() but adding: device-following
# plot capture, timeouts, interrupts with partial results, traceback, guard,
# harness-option restore, side-effect report, output cleaning and truncation.

# ------------------------------------------------------------------ static guard
.gptr_guard_rules <- list(
  # would terminate or hang the user's session: never evaluated
  block = c("q", "quit", "browser", "debug", "debugonce", "undebug", "recover",
            "readline", "menu", "select.list", "file.choose", "askYesNo",
            "readLines_stdin", "scan_stdin", "fix", "edit", "de", "data.entry",
            "dataentry", "locator", "identify", "setTimeLimit",
            "setSessionTimeLimit", "closeAllConnections", ".Internal", ".Primitive"),
  # changes session-wide state; allowed but reported / subject to permission mode
  session = c("setwd", "sink", "options", "Sys.setenv", "Sys.unsetenv", "Sys.setlocale",
              "attach", "detach", "library", "require", "loadNamespace", "unloadNamespace",
              "graphics.off", "dev.off", "set.seed", "rm", "remove", "assign", "<<-"),
  # touches things outside the R process
  system = c("system", "system2", "shell", "shell.exec", "pipe", "Sys.chmod",
             "unlink", "file.remove", "file.rename", "file.copy", "writeLines", "saveRDS",
             "save", "write.csv", "fwrite", "download.file", "install.packages",
             "remove.packages", "update.packages", "pskill", "processx::run", "run"),
  dynamic = c("eval", "evalq", "parse", "str2lang", "str2expression", "do.call",
              "match.fun", "get", "get0", "mget", "getExportedValue", "source", "sys.source")
)

# Names of all functions called (or passed as FUN by name) in parsed code.
gptr_called_functions <- function(exprs) {
  out <- character()
  add <- function(x) out[length(out) + 1L] <<- x
  walk <- function(e) {
    if (is.call(e)) {
      f <- e[[1L]]
      if (is.symbol(f)) {
        add(as.character(f))
      } else if (is.call(f) && length(f) == 3L &&
                 (identical(f[[1L]], quote(`::`)) || identical(f[[1L]], quote(`:::`)))) {
        add(as.character(f[[3L]]))
      }
      fname <- if (is.symbol(f)) as.character(f) else ""
      # do.call("q"), match.fun("q"), get("q"), lapply(x, "q") ... string function names
      if (fname %in% c("do.call", "match.fun", "get", "get0", "getExportedValue",
                       "lapply", "sapply", "vapply", "Map", "mapply", "Reduce", "Filter")) {
        for (a in as.list(e)[-1L]) {
          if (is.character(a) && length(a) == 1L) add(a)
          if (is.symbol(a) && as.character(a) %in% c("q", "quit")) add(as.character(a))
        }
      }
      for (i in seq_along(e)[-1L]) {
        el <- e[[i]]
        if (!missing(el)) walk(el)
      }
      if (!is.symbol(f)) walk(f)
    } else if (is.expression(e) || is.list(e)) {
      for (i in seq_along(e)) { el <- e[[i]]; if (!missing(el)) walk(el) }
    } else if (is.pairlist(e)) {
      for (i in seq_along(e)) { el <- e[[i]]; if (!missing(el)) walk(el) }
    } else if (is.symbol(e) && identical(as.character(e), "quit")) {
      add("quit")      # `f <- quit; f()` style indirection
    }
    invisible()
  }
  walk(exprs)
  unique(out)
}

gptr_guard <- function(exprs) {
  called <- gptr_called_functions(exprs)
  lapply(.gptr_guard_rules, function(r) intersect(called, r))
}

# ------------------------------------------------------------------ devices
gptr_png_open <- function(file, px = 768L, ratio = 1.5, res = 96) {
  w <- if (ratio >= 1) px else round(px * ratio)
  h <- if (ratio >= 1) round(px / ratio) else px
  if (requireNamespace("ragg", quietly = TRUE)) {
    ragg::agg_png(file, width = w, height = h, units = "px", res = res)
    return("ragg")
  }
  if (isTRUE(capabilities("png"))) {
    grDevices::png(file, width = w, height = h, units = "px", res = res)
    return("png")
  }
  NULL
}

gptr_render_plot <- function(plot, file, px = 768L, ratio = 1.5) {
  prev <- grDevices::dev.cur()
  if (is.null(gptr_png_open(file, px, ratio))) return(NULL)
  dev <- grDevices::dev.cur()
  on.exit({
    if (dev %in% grDevices::dev.list()) grDevices::dev.off(dev)
    if (prev > 1L && prev %in% grDevices::dev.list()) grDevices::dev.set(prev)
  })
  suppressWarnings(grDevices::replayPlot(plot))
  file
}

gptr_open_recording_device <- function(px = 768L, ratio = 1.5, res = 96) {
  w <- (if (ratio >= 1) px else px * ratio) / res
  h <- (if (ratio >= 1) px / ratio else px) / res
  if (requireNamespace("ragg", quietly = TRUE) && exists("agg_record", asNamespace("ragg"))) {
    ragg::agg_record(width = w, height = h, units = "in", res = res)
  } else {
    grDevices::pdf(file = NULL, width = w, height = h)
  }
  grDevices::dev.control(displaylist = "enable")
  grDevices::dev.cur()
}

# evaluate 1.0.5's heuristics (graphics.R): ignore display lists that only set par/layout
.gptr_non_visual <- c("C_clip", "C_layout", "C_par", "C_plot_window", "C_strHeight",
                      "C_strWidth", "palette", "palette2")
gptr_makes_visual_change <- function(dl) {
  for (x in lapply(dl, function(x) x[[2]][[1]])) {
    if (utils::hasName(x, "name")) {
      if (!x$name %in% .gptr_non_visual) return(TRUE)
    } else if (is.call(x)) {
      if (!identical(as.character(x[[1]]), "requireNamespace")) return(TRUE)
    }
  }
  FALSE
}
gptr_is_prefix <- function(x, y) length(x) <= length(y) && identical(x[], y[seq_along(x)])  # x[]: pairlist -> list

# ------------------------------------------------------------------ traceback
.gptr_eval_frame <- function(expr, envir) eval(expr, envir)

# Top-level expressions whose value is invisible by construction. They are evaluated WITHOUT
# withVisible(): withVisible() puts the value in a list, which leaves a sticky extra reference on
# it, so the user's next in-place edit (x[1] <- 0) would duplicate the whole object.
.gptr_invisible_heads <- c("<-", "=", "<<-", "invisible", "for", "while", "repeat", "library",
                           "require", "print", "cat", "message", "suppressPackageStartupMessages",
                           "set.seed", "options", "rm", "setwd", "stopifnot")

# Evaluate one top-level expression and print it like the console. Returns only the visibility
# flag; the value never leaves this closure-free frame, so no reference to it survives.
.gptr_eval_top <- function(expr, envir, print_value) {
  if (is.symbol(expr)) {                                  # `x`: visible; print(<symbol>) in envir
    .gptr_eval_frame(call("print", expr), envir)
    return(TRUE)
  }
  if (is.call(expr) && is.symbol(expr[[1L]]) && as.character(expr[[1L]]) %in% .gptr_invisible_heads) {
    .gptr_eval_frame(expr, envir)
    return(FALSE)
  }
  res <- withVisible(.gptr_eval_frame(expr, envir))       # fresh values: the extra ref is harmless
  if (res$visible) print_value(res$value)
  res$visible
}

gptr_user_calls <- function() {
  # called from inside a calling handler: frames = [..., .gptr_eval_frame, eval, eval, <user frames>,
  # <condition-system frames>, <handler>, gptr_user_calls]
  calls <- sys.calls()
  n <- length(calls)
  funs <- lapply(seq_len(n), sys.function)
  mark <- which(vapply(funs, identical, logical(1), .gptr_eval_frame))
  if (!length(mark)) return(list())
  keep <- seq_len(n - 2L)                       # drop gptr_user_calls() and the handler frame
  calls <- calls[keep[keep > max(mark)]]
  while (length(calls) && identical(calls[[1L]], quote(eval(expr, envir)))) calls <- calls[-1L]
  internal <- c(".handleSimpleError", ".signalSimpleWarning", "signalCondition", "withRestarts",
                "withOneRestart", "doWithOneRestart", "signal_abort", "withCallingHandlers")
  is_internal <- function(cl) {
    f <- if (is.call(cl)) cl[[1L]] else NULL
    nm <- if (is.symbol(f)) as.character(f) else if (is.call(f) && length(f) == 3L) as.character(f[[3L]]) else ""
    nm %in% internal
  }
  while (length(calls) && is_internal(calls[[length(calls)]])) calls <- calls[-length(calls)]
  calls
}

gptr_format_calls <- function(calls, max_calls = 20L, width = 120L) {
  n <- length(calls)
  if (!n) return(character())
  keep <- if (n > max_calls) c(seq_len(5L), seq.int(n - max_calls + 6L, n)) else seq_len(n)
  out <- character()
  for (i in keep) {
    cl <- calls[[i]]
    txt <- paste(deparse(cl, width.cutoff = 500L, nlines = 2L), collapse = " ")
    if (nchar(txt) > width) txt <- paste0(substr(txt, 1L, width - 3L), "...")
    sr <- attr(cl, "srcref")
    loc <- ""
    if (!is.null(sr)) {
      sf <- attr(sr, "srcfile")
      fn <- if (!is.null(sf$filename) && nzchar(sf$filename)) basename(sf$filename) else "<code>"
      loc <- sprintf(" at %s#%d", fn, sr[1L])
    }
    out[length(out) + 1L] <- sprintf("%2d: %s%s", i, txt, loc)
    if (n > max_calls && i == 5L) out[length(out) + 1L] <- sprintf("    ... %d frames omitted ...", n - max_calls)
  }
  out
}

.gptr_print <- function(value) .gptr_eval_frame(quote(print(value)), environment())

# ------------------------------------------------------------------ text cleaning / truncation
gptr_clean_output <- function(x) {
  x <- gsub("\033\\[[0-9;?]*[ -/]*[@-~]", "", x, perl = TRUE)      # ANSI CSI
  x <- gsub("\033\\][^\a]*(\a|\033\\\\)", "", x, perl = TRUE)       # OSC hyperlinks
  lines <- strsplit(x, "\n", fixed = TRUE)[[1L]]
  lines <- vapply(lines, function(l) {                             # carriage returns
    if (!grepl("\r", l, fixed = TRUE)) return(l)
    parts <- strsplit(l, "\r", fixed = TRUE)[[1L]]
    parts <- parts[nzchar(parts)]
    if (length(parts)) parts[length(parts)] else ""
  }, "", USE.NAMES = FALSE)
  paste(lines, collapse = "\n")
}

gptr_truncate <- function(text, max_chars = 30000L, max_lines = 800L, head_frac = 0.4,
                          spill_dir = tempdir()) {
  text <- paste(text, collapse = "\n")
  n_chars <- nchar(text, type = "chars", allowNA = TRUE)
  if (is.na(n_chars)) { text <- iconv(text, "", "UTF-8", sub = "byte"); n_chars <- nchar(text) }
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  n_lines <- length(lines)
  if (n_lines <= max_lines && n_chars <= max_chars)
    return(structure(text, truncated = FALSE, n_chars = n_chars, n_lines = n_lines))
  spill <- tempfile("gptr-output-", tmpdir = spill_dir, fileext = ".txt")
  writeLines(text, spill, useBytes = TRUE)
  if (n_lines > max_lines) {
    nh <- floor(max_lines * head_frac); nt <- max_lines - nh
    lines <- c(lines[seq_len(nh)],
               sprintf("[... %d lines omitted ...]", n_lines - nh - nt),
               lines[seq.int(n_lines - nt + 1L, n_lines)])
  }
  out <- paste(lines, collapse = "\n")
  if (nchar(out) > max_chars) {
    nh <- floor(max_chars * head_frac); nt <- max_chars - nh; n2 <- nchar(out)
    out <- paste0(substr(out, 1L, nh), sprintf("\n[... %d characters omitted ...]\n", n2 - nh - nt),
                  substr(out, n2 - nt + 1L, n2))
  }
  out <- paste0(out, sprintf("\n[output truncated: %d lines, %d characters in total; full text in %s]",
                             n_lines, n_chars, spill))
  structure(out, truncated = TRUE, n_chars = n_chars, n_lines = n_lines, spill = spill)
}

# ------------------------------------------------------------------ session state snapshot
gptr_state <- function() {
  list(wd = getwd(), options = options(), envvars = Sys.getenv(), search = search(),
       ns = loadedNamespaces(), devices = grDevices::dev.list(), sinks = sink.number(),
       connections = rownames(showConnections(all = FALSE)))
}
gptr_state_diff <- function(a, b) {
  ch <- list()
  if (!identical(a$wd, b$wd)) ch$wd <- c(from = a$wd, to = b$wd)
  # only options that existed before and were changed or removed: options ADDED by packages
  # loaded during the call (their .onLoad defaults) are noise for the model
  on <- names(a$options)
  oc <- on[!vapply(on, function(n) identical(a$options[[n]], b$options[[n]]), logical(1))]
  if (length(oc)) ch$options <- oc
  en <- union(names(a$envvars), names(b$envvars))
  ec <- en[!vapply(en, function(n) identical(a$envvars[n], b$envvars[n]), logical(1))]
  if (length(ec)) ch$envvars <- ec            # names only -- never values (secrets)
  if (!identical(a$search, b$search)) ch$attached <- setdiff(b$search, a$search)
  nn <- setdiff(b$ns, a$ns); if (length(nn)) ch$loaded <- nn
  if (!identical(a$devices, b$devices)) ch$devices <- list(from = names(a$devices), to = names(b$devices))
  cn <- setdiff(b$connections, a$connections); if (length(cn)) ch$connections_opened <- cn
  ch
}

# ------------------------------------------------------------------ evaluator
gptr_eval <- function(code, envir = parent.frame(), ...) {
  force(envir)
  state0 <- gptr_state()
  res <- .gptr_eval_core(code, envir, ...)
  res$changes <- gptr_state_diff(state0, gptr_state())   # after the core's on.exit cleanup ran
  res
}

.gptr_eval_core <- function(code, envir, timeout = Inf,
                      plots = c("auto", "device", "offscreen", "none"),
                      plot_dir = file.path(tempdir(), "gptr-plots"), plot_px = 768L,
                      plot_ratio = 1.5, tee = FALSE, guard = TRUE, max_print = 1000L,
                      width = 100L, filename = "<gptr>") {
  plots <- match.arg(plots)
  force(envir)
  t0 <- proc.time()[["elapsed"]]
  events <- list()
  push <- function(type, ...) { events[[length(events) + 1L]] <<- list(type = type, ...); invisible() }
  devs0 <- grDevices::dev.list()
  finish <- function(status, value = NULL, visible = FALSE, n_done = 0L, n_total = 0L) {
    structure(list(status = status, events = events, value = value, visible = visible,
                   n_done = n_done, n_total = n_total, changes = list(),
                   elapsed = proc.time()[["elapsed"]] - t0), class = "gptr_eval_result")
  }

  # 1. parse ------------------------------------------------------------------
  srcfile <- srcfilecopy(filename, code)
  exprs <- tryCatch(parse(text = code, keep.source = TRUE, srcfile = srcfile),
                    error = function(e) e)
  if (inherits(exprs, "error")) {
    push("error", message = conditionMessage(exprs), call = NULL, traceback = character(),
         class = "parse_error")
    return(finish("parse_error"))
  }
  n_total <- length(exprs)
  if (!n_total) return(finish("ok"))

  # 2. static guard -------------------------------------------------------------
  if (isTRUE(guard)) {
    g <- gptr_guard(exprs)
    if (length(g$block)) {
      push("error", class = "gptr_blocked", call = NULL, traceback = character(),
           message = sprintf(paste("Not run: the code calls %s, which would end, pause or hang the",
                                   "user's R session. Nothing was evaluated. Use the ask tool to talk",
                                   "to the user."), paste0(g$block, "()", collapse = ", ")))
      return(finish("blocked", n_total = n_total))
    }
  }

  # 3. harness-owned options (restored afterwards; user code changes to others persist)
  old_opts <- options(max.print = max_print, width = width, warn = 1,
                      rlang_interactive = FALSE, cli.dynamic = FALSE, cli.num_colors = 1L,
                      askYesNo = function(...) stop("askYesNo() is not available to the agent", call. = FALSE))
  on.exit(options(old_opts), add = TRUE)
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)

  # 4. output capture: anonymous file sink (same technique as evaluate) ---------------
  con <- file("", "w+b")
  sink(con, split = isTRUE(tee))
  sink_n <- sink.number()
  old_try <- options(try.outFile = con)
  on.exit(suspendInterrupts({
    # pop every sink the code left above ours, then ours (if still there)
    while (sink.number() >= sink_n && sink.number() > 0L) sink()
    options(old_try)
    if (tryCatch(isOpen(con), error = function(e) FALSE)) close(con)
  }), add = TRUE)
  read_sink <- function() {
    if (!tryCatch(isOpen(con), error = function(e) FALSE)) {   # closeAllConnections()
      con <<- file("", "w+b"); options(try.outFile = con)
    }
    if (sink.number() < sink_n) {                               # code popped our sink
      sink(con, split = isTRUE(tee)); sink_n <<- sink.number()
    }
    bytes <- raw()
    repeat { b <- readBin(con, "raw", n = 65536L); if (!length(b)) break; bytes <- c(bytes, b) }
    if (!length(bytes)) return(NULL)
    txt <- rawToChar(bytes[bytes != as.raw(0L)])
    Encoding(txt) <- if (isTRUE(l10n_info()[["UTF-8"]])) "UTF-8" else "unknown"
    txt
  }
  flush_output <- function() {
    txt <- read_sink()
    if (!is.null(txt) && nzchar(txt)) {
      n <- length(events)
      if (n && identical(events[[n]]$type, "output")) events[[n]]$text <<- paste0(events[[n]]$text, txt)
      else push("output", text = txt)
    }
    invisible()
  }

  # 5. plots ------------------------------------------------------------------------
  if (plots == "auto") {
    plots <- if (interactive() || grDevices::dev.cur() > 1L || isTRUE(getOption("knitr.in.progress")))
      "device" else "offscreen"
  }
  if (plots == "device" && !interactive() && grDevices::dev.cur() == 1L) plots <- "offscreen"
  dev_start <- grDevices::dev.cur()
  our_dev <- NULL
  if (plots == "offscreen") {
    our_dev <- gptr_open_recording_device(plot_px, plot_ratio)
    on.exit({
      if (our_dev %in% grDevices::dev.list()) grDevices::dev.off(our_dev)
      if (dev_start > 1L && dev_start %in% grDevices::dev.list()) grDevices::dev.set(dev_start)
    }, add = TRUE)
  }
  last_dl <- list()           # last recorded display list per device number
  if (plots == "device" && dev_start > 1L)   # file devices (png/pdf) inhibit the display list by default
    try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
  if (dev_start > 1L) {       # baseline: do not report a plot that was already there
    b <- tryCatch(grDevices::recordPlot(), error = function(e) NULL)
    if (!is.null(b)) last_dl[[as.character(dev_start)]] <- b[[1L]]
  }
  n_plots <- 0L
  snapshot <- function(incomplete = FALSE) {
    if (plots == "none") return(invisible())
    d <- grDevices::dev.cur()
    if (d == 1L) return(invisible())
    if (!is.null(our_dev) && d != our_dev && d %in% devs0) return(invisible())  # never the user's devices
    if (!incomplete && !isTRUE(graphics::par("page"))) return(invisible())
    p <- tryCatch(grDevices::recordPlot(), error = function(e) NULL)
    if (is.null(p) || !length(p[[1L]]) || !gptr_makes_visual_change(p[[1L]])) return(invisible())
    key <- as.character(d); old <- last_dl[[key]]
    if (!is.null(old) && gptr_is_prefix(old, p[[1L]]) &&
        !gptr_makes_visual_change(p[[1L]][-seq_along(old)])) return(invisible())
    last_dl[[key]] <<- p[[1L]]
    n_plots <<- n_plots + 1L
    flush_output()
    push("plot", plot = p, index = n_plots, device = names(grDevices::dev.cur()))
    invisible()
  }
  # make sure devices opened by the code record a display list
  enable_dl <- function(...) {
    d <- grDevices::dev.cur()
    if (d > 1L && !(d %in% c(devs0, our_dev)) && is.null(last_dl[[as.character(d)]]))
      try(grDevices::dev.control(displaylist = "enable"), silent = TRUE)
  }
  hook <- function(...) { enable_dl(); snapshot(FALSE) }
  if (plots != "none") {
    for (h in c("before.plot.new", "before.grid.newpage", "persp")) setHook(h, hook, "append")
    on.exit(for (h in c("before.plot.new", "before.grid.newpage", "persp")) {
      hs <- getHook(h); hs[vapply(hs, identical, logical(1), hook)] <- NULL; setHook(h, hs, "replace")
    }, add = TRUE)
  }

  # 6. evaluate top-level expressions ----------------------------------------------
  print_value <- function(value) {
    if (isS4(value)) methods::show(value) else if (identical(topenv(envir), globalenv()) && identical(envir, globalenv())) {
      .gptr_print(value)                                     # dispatch finds methods in globalenv
    } else {                                                 # methods defined in a local envir
      print_env <- new.env(parent = envir); print_env$value <- value
      .gptr_eval_frame(quote(print(value)), print_env)
    }
  }
  deadline <- if (is.finite(timeout)) t0 + timeout else Inf
  timeout_msgs <- unique(c("reached elapsed time limit", "reached CPU time limit",
                           gettext("reached elapsed time limit", domain = "R"),
                           gettext("reached CPU time limit", domain = "R")))
  is_timeout <- function(cnd) is.finite(deadline) && inherits(cnd, "simpleError") &&
    any(vapply(timeout_msgs, grepl, logical(1), x = conditionMessage(cnd), fixed = TRUE))
  value <- NULL; visible <- FALSE; n_done <- 0L
  srcrefs <- attr(exprs, "srcref")
  on_interrupt <- function(cnd) {
    setTimeLimit(cpu = Inf, elapsed = Inf)
    push("interrupt", message = "Interrupted by the user (Ctrl-C / Esc).")
    "interrupt"
  }
  # the outer tryCatch catches an interrupt that lands anywhere, including in harness code
  # between two expressions; the inner calling handler catches it inside user code
  status <- tryCatch({
    st <- "ok"
    for (i in seq_len(n_total)) {
      expr <- exprs[[i]]
      line <- srcrefs[[i]][1L]
      push("source", text = paste(as.character(srcrefs[[i]]), collapse = "\n"), line = line)
      if (is.finite(deadline)) {
        remaining <- deadline - proc.time()[["elapsed"]]
        if (remaining <= 0) {
          push("error", class = "gptr_timeout", call = NULL, traceback = character(), line = line,
               message = sprintf("Timed out after %gs before expression %d of %d.", timeout, i, n_total))
          st <- "timeout"; break
        }
        setTimeLimit(elapsed = remaining, transient = TRUE)
      }
      ok <- withRestarts(
        withCallingHandlers({
          visible <- .gptr_eval_top(expr, envir, function(v) { snapshot(); flush_output(); print_value(v) })
          snapshot(); flush_output()
          TRUE
        },
        message = function(cnd) {
          snapshot(); flush_output()
          push("message", text = conditionMessage(cnd))
          tryInvokeRestart("muffleMessage")
        },
        warning = function(cnd) {
          if (getOption("warn") >= 2 || getOption("warn") < 0) return()
          snapshot(); flush_output()
          cl <- conditionCall(cnd)
          push("warning", text = conditionMessage(cnd),
               call = if (!is.null(cl) && !identical(cl, quote(eval(expr, envir))))
                 paste(deparse(cl, nlines = 1L), collapse = "") else NULL)
          tryInvokeRestart("muffleWarning")
        },
        error = function(cnd) {
          calls <- gptr_user_calls()          # FIRST: before any other frame is pushed
          setTimeLimit(cpu = Inf, elapsed = Inf)
          snapshot(TRUE); flush_output()
          to <- is_timeout(cnd)
          cl <- conditionCall(cnd)
          tb <- if (to) character() else gptr_format_calls(calls)
          push("error", class = class(cnd), line = line, timeout = to,
               message = if (to) sprintf("Timed out after %gs (limit set by the harness).", timeout)
                         else conditionMessage(cnd),
               call = if (!is.null(cl) && !identical(cl, quote(eval(expr, envir))))
                 paste(deparse(cl, nlines = 1L), collapse = "") else NULL,
               traceback = tb)
          invokeRestart("gptr_stop", if (to) "timeout" else "error")
        },
        interrupt = function(cnd) invokeRestart("gptr_stop", on_interrupt(cnd))),
        gptr_stop = function(why) why)
      setTimeLimit(cpu = Inf, elapsed = Inf)
      if (!isTRUE(ok)) { st <- ok; break }
      n_done <- i
    }
    st
  }, interrupt = on_interrupt)
  setTimeLimit(cpu = Inf, elapsed = Inf)
  status_final <- status
  status <- status_final
  tryCatch(flush_output(), error = function(e) NULL)
  snapshot(TRUE); flush_output()

  # 7. render captured plots to PNG for the model ------------------------------------
  pl <- which(vapply(events, function(e) identical(e$type, "plot"), logical(1)))
  if (length(pl)) {
    dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)
    for (k in pl) {
      f <- tempfile("plot-", tmpdir = plot_dir, fileext = ".png")
      events[[k]]$file <- tryCatch(gptr_render_plot(events[[k]]$plot, f, plot_px, plot_ratio),
                                   error = function(e) { events[[k]]$render_error <<- conditionMessage(e); NULL })
    }
  }
  finish(status, NULL, FALSE, n_done, n_total)
}

# ------------------------------------------------------------------ model-facing text
format.gptr_eval_result <- function(x, max_chars = 30000L, max_lines = 800L, echo = FALSE, ...) {
  out <- character()
  for (e in x$events) {
    out <- c(out, switch(e$type,
      source = if (echo) paste0("> ", gsub("\n", "\n+ ", e$text, fixed = TRUE)) else NULL,
      output = sub("\n$", "", gptr_clean_output(e$text)),
      message = sub("\n$", "", gptr_clean_output(e$text)),
      warning = paste0("Warning", if (!is.null(e$call)) paste0(" in ", e$call), ": ", gptr_clean_output(e$text)),
      error = c(paste0("Error", if (!is.null(e$call)) paste0(" in ", e$call), ": ", gptr_clean_output(e$message),
                       if (!is.null(e$line) && !is.na(e$line)) sprintf("  [expression at line %d]", e$line) else ""),
                if (length(e$traceback)) c("Traceback (outermost first):", e$traceback)),
      interrupt = "[interrupted by the user]",
      plot = sprintf("[plot %d attached as image%s]", e$index, if (is.null(e$file)) " -- render failed" else ""),
      NULL))
  }
  ch <- x$changes
  if (length(ch$wd)) out <- c(out, sprintf("[working directory changed: %s -> %s]", ch$wd[["from"]], ch$wd[["to"]]))
  if (length(ch$options)) out <- c(out, sprintf("[options changed: %s]", paste(ch$options, collapse = ", ")))
  if (length(ch$envvars)) out <- c(out, sprintf("[environment variables changed: %s]", paste(ch$envvars, collapse = ", ")))
  if (length(ch$attached)) out <- c(out, sprintf("[attached: %s]", paste(ch$attached, collapse = ", ")))
  if (x$status != "ok")
    out <- c(out, sprintf("[status: %s; %d of %d top-level expressions completed; %.2fs]",
                          x$status, x$n_done, x$n_total, x$elapsed))
  if (!length(out)) out <- "[no output]"
  gptr_truncate(out, max_chars, max_lines)
}
print.gptr_eval_result <- function(x, ...) { cat(format(x, ...), "\n", sep = ""); invisible(x) }
```

Implementer notes on this prototype: (1) raise the truncation defaults to 2000 lines / 50 000
characters (3.5); (2) the closures `push`, `snapshot` and the handlers capture `.gptr_eval_core`'s
frame. That is fine because the value never lives there (`.gptr_eval_top()`), but keep it that
way; (3) the `print_env` path for non-global `envir` puts the value in an environment (a sticky
reference, acceptable because it is rare); (4) `tee = interactive()` for the console.

### 5.2 Introspection: `W12/gptr_introspect.R` (final, complete)

```r
# gptr_introspect.R -- copy-safe workspace introspection for gptr (Track 12 reference prototype)
# Dependencies: base R + rlang (obj_address, hash, env_binding_are_lazy/active).
#
# WHY THE ODD STRUCTURE (all verified with tracemem, one fresh R process per case, R 4.4.3):
#   R releases the references held by a function's frame only if nothing else references the
#   frame when the function returns (eval.c: R_CleanupEnvir). If a frame that binds a user object
#   passes a closure somewhere (tryCatch handler, lapply/vapply FUN), puts the object in a list
#   (list(), withVisible(), a list subset), or calls a "frame-capturing" function (table(), format(),
#   match.arg()-based code, str(), lobstr::obj_size()) with an unforced promise, the frame leaks
#   and the object keeps a sticky reference: the user's NEXT in-place edit (x[1] <- 0) then
#   duplicates the whole object (a 5 GB Seurat object becomes a 10 GB peak).
#   Therefore:
#     * LEAF functions (.gptr_leaf_*) are the only frames that bind user objects. They call only
#       primitives and thin .Internal/.Call wrappers (typeof, inherits, object.size,
#       rlang::obj_address, rlang::hash) and return FRESH small values ("facts").
#     * FORMATTERS (.gptr_fmt_*) turn facts into text with any R code; they never see the object.
#     * Loops, tryCatch() and *apply live in frames that address objects BY NAME (envir + name).

.gptr_cache <- new.env(parent = emptyenv())
.gptr_cache$size <- new.env(parent = emptyenv())
`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------ small utilities (no objects)
gptr_fmt_bytes <- function(b) {
  if (is.null(b) || is.na(b)) return("? B")
  u <- c("B", "KB", "MB", "GB", "TB"); i <- max(1L, min(length(u), floor(log(max(b, 1), 1024)) + 1L))
  sprintf(if (i == 1L) "%.0f %s" else "%.1f %s", b / 1024^(i - 1L), u[i])
}
gptr_fmt_n <- function(n) format(n, big.mark = ",", scientific = FALSE, trim = TRUE)
gptr_fit <- function(lines, budget) {                 # budget in tokens (~3.5 chars/token)
  if (!length(lines)) return(lines)
  cum <- cumsum(ceiling((nchar(lines, allowNA = TRUE) + 1L) / 3.5))
  if (cum[length(cum)] <= budget) return(lines)
  keep <- max(1L, sum(cum <= budget - 8L))
  c(lines[seq_len(keep)], sprintf("  ... (%d more lines not shown)", length(lines) - keep))
}
gptr_sample_idx <- function(n, max_n = 1e5) if (n <= max_n) seq_len(n) else unique(round(seq(1, n, length.out = max_n)))

# ------------------------------------------------------------------ LEAVES (bind the object)
# Core facts for any object. Only primitives / thin wrappers. `size_key` avoids recomputing
# object.size() (O(n) for lists and character vectors) when the address has not changed.
.gptr_leaf_core <- function(x) {
  addr <- rlang::obj_address(x)
  env_like <- is.environment(x)
  fn <- is.function(x)
  ext <- typeof(x) == "externalptr"
  n <- length(x)
  key <- paste(addr, n, class(x)[1L])
  size <- if (env_like || fn || ext) NA_real_ else .gptr_cache$size[[key]]
  if (is.null(size)) { size <- as.numeric(utils::object.size(x)); assign(key, size, envir = .gptr_cache$size) }
  list(address = addr, class = class(x), type = typeof(x), length = n, dim = attr(x, "dim"),
       df = inherits(x, "data.frame"), nrow = if (inherits(x, "data.frame")) .row_names_info(x, 2L) else NA_integer_,
       s4 = isS4(x), env = env_like, fun = fn, size = size, names_n = length(attr(x, "names")))
}

# Sampled values of an atomic vector (by precomputed index): .subset() does not dispatch.
.gptr_leaf_sample <- function(x, idx) {
  list(values = .subset(x, idx), levels = attr(x, "levels"), class = class(x), n = length(x))
}

# Per-column samples of a data.frame (loop with primitives only).
.gptr_leaf_df <- function(x, idx, max_cols = 60L) {
  p <- length(x); k <- seq_len(min(p, max_cols))
  cols <- vector("list", length(k))
  for (j in k) {
    col <- .subset2(x, j)
    cols[[j]] <- list(class = class(col), values = .subset(col, idx), levels = attr(col, "levels"))
  }
  list(names = attr(x, "names"), cols = cols, p = p, key = attr(x, "sorted"))
}

# Shape of the first k elements of a list.
.gptr_leaf_list <- function(x, k = 6L, k_cls = 1000L) {
  n <- length(x); first <- seq_len(min(n, k_cls)); kk <- seq_len(min(n, k))
  cls <- character(length(first))
  for (i in first) cls[i] <- class(.subset2(x, i))[1L]
  kcls <- vector("list", length(kk)); klen <- numeric(length(kk)); kdim <- vector("list", length(kk))
  for (i in kk) { el <- .subset2(x, i); kcls[[i]] <- class(el); klen[i] <- length(el); kdim[i] <- list(attr(el, "dim")) }
  nm <- attr(x, "names")
  list(n = n, cls = cls, kcls = kcls, klen = klen, kdim = kdim,
       names = if (is.null(nm)) NULL else nm[seq_len(min(length(nm), 20L))])
}

# Top-left corner of a matrix.
.gptr_leaf_matrix <- function(x) {
  d <- attr(x, "dim")
  list(corner = x[seq_len(min(3L, d[1L])), seq_len(min(5L, d[2L])), drop = FALSE],
       rn = attr(x, "dimnames")[[1L]][seq_len(min(3L, d[1L]))], cn = attr(x, "dimnames")[[2L]][seq_len(min(3L, d[2L]))])
}

# S4 slots (slots are attributes; attr() is a primitive).
.gptr_leaf_s4 <- function(x, slots) {
  out <- vector("list", length(slots))
  for (i in seq_along(slots)) {
    v <- attr(x, slots[i], exact = TRUE)
    out[[i]] <- list(class = class(v), length = length(v), dim = attr(v, "dim"),
                     nrow = if (inherits(v, "data.frame")) .row_names_info(v, 2L) else NA_integer_,
                     names = { nm <- attr(v, "names"); if (is.null(nm)) NULL else nm[seq_len(min(length(nm), 8L))] })
  }
  out
}

# Fingerprint samples: attributes (sampled) + sampled elements; addresses of list elements.
.gptr_leaf_fp <- function(x, n_sample = 64L) {
  n <- length(x)
  idx <- if (n <= 2L * n_sample) seq_len(n) else unique(c(1:8, round(seq(1, n, length.out = n_sample)), (n - 7L):n))
  at <- attributes(x)
  for (a in names(at)) { v <- at[[a]]; if (length(v) > 2L * n_sample) at[[a]] <- .subset(v, idx[idx <= length(v)]) }
  if (is.list(x)) {
    addr <- character(length(idx)); len <- numeric(length(idx)); smp <- vector("list", length(idx))
    for (j in seq_along(idx)) {
      el <- .subset2(x, idx[j]); addr[j] <- rlang::obj_address(el); len[j] <- length(el)
      if (is.atomic(el)) { m <- length(el); smp[[j]] <- .subset(el, unique(c(1L, (m + 1L) %/% 2L, m))) }
    }
    list(n = n, attrs = at, addr = addr, len = len, smp = smp)
  } else if (is.atomic(x)) list(n = n, attrs = at, values = .subset(x, idx))
  else list(n = n, attrs = at)
}

# ------------------------------------------------------------------ FORMATTERS (facts only)
.gptr_fmt_header <- function(f) {
  shape <- if (length(f$dim)) paste(gptr_fmt_n(f$dim), collapse = " x ")
           else if (isTRUE(f$df)) sprintf("%s x %s", gptr_fmt_n(f$nrow), gptr_fmt_n(f$length))
           else paste0("length ", gptr_fmt_n(f$length))
  sprintf("<%s> %s%s", paste(f$class, collapse = "/"), shape, if (!is.na(f$size)) paste0(", ", gptr_fmt_bytes(f$size)) else "")
}

.gptr_fmt_values <- function(s, n, sampled) {
  force(s); force(n); force(sampled)
  v <- s$values
  if (!is.null(s$levels)) v <- structure(v, levels = s$levels, class = "factor")
  na <- sum(is.na(v))
  na_txt <- if (na) sprintf("%s%.1f%% NA", if (sampled) "~" else "", 100 * na / max(1L, length(v)))
            else if (sampled) "no NA in sample" else "no NA"
  body <- if (is.factor(v)) {
    tb <- sort(table(v), decreasing = TRUE); k <- seq_len(min(3L, length(tb)))
    sprintf("%d levels, top: %s", length(s$levels), paste(sprintf("%s (%d)", names(tb)[k], tb[k]), collapse = ", "))
  } else if (is.numeric(v) && any(!is.na(v))) {
    q <- stats::quantile(v, c(0, .5, 1), na.rm = TRUE, names = FALSE)
    sprintf("min %s, median %s, max %s", format(q[1], digits = 4), format(q[2], digits = 4), format(q[3], digits = 4))
  } else if (is.character(v)) {
    u <- unique(v[!is.na(v)])
    sprintf("%s%d unique, e.g. %s", if (sampled) ">=" else "", length(u), paste(encodeString(utils::head(u, 3), quote = "\""), collapse = ", "))
  } else if (is.logical(v)) sprintf("%s%d TRUE", if (sampled) "~" else "", sum(v, na.rm = TRUE))
  else paste(format(utils::head(v, 3)), collapse = ", ")
  paste0(body, "; ", na_txt)
}

# ------------------------------------------------------------------ the describe generic
# Built-in methods = leaf (binds x) + formatter (facts only). Extension methods for other classes
# (e.g. gptr_describe.Seurat) should follow the same pattern; gptr ships a test helper for it.
gptr_describe <- function(x, budget = 300L, ...) UseMethod("gptr_describe")

gptr_describe.default <- function(x, budget = 300L, ...) {
  f <- .gptr_leaf_core(x)
  if (f$s4) return(.gptr_describe_s4(x, f, budget))
  if (is.atomic(x) && !length(f$dim)) {
    idx <- gptr_sample_idx(f$length)
    s <- .gptr_leaf_sample(x, idx)
    return(.gptr_fmt_atomic(f, s, budget))
  }
  .gptr_fmt_other(f, budget)
}
.gptr_fmt_atomic <- function(f, s, budget) {
  force(f); force(s); force(budget)
  sampled <- length(s$values) < f$length
  gptr_fit(c(.gptr_fmt_header(f), paste0("  ", .gptr_fmt_values(s, f$length, sampled),
             if (sampled) sprintf(" [sampled %s of %s]", gptr_fmt_n(length(s$values)), gptr_fmt_n(f$length)) else "")), budget)
}
.gptr_fmt_other <- function(f, budget) { force(f); force(budget); gptr_fit(c(.gptr_fmt_header(f), sprintf("  typeof %s", f$type)), budget) }

gptr_describe.data.frame <- function(x, budget = 300L, ...) {
  f <- .gptr_leaf_core(x)
  idx <- gptr_sample_idx(f$nrow)
  d <- .gptr_leaf_df(x, idx)
  .gptr_fmt_df(f, d, length(idx) < f$nrow, budget)
}
.gptr_fmt_df <- function(f, d, sampled, budget) {
  force(f); force(d); force(sampled); force(budget)
  hdr <- .gptr_fmt_header(f)
  if (length(d$key)) hdr <- paste0(hdr, "; key: ", paste(d$key, collapse = ", "))
  cols <- character(length(d$cols))
  for (j in seq_along(d$cols)) {
    cj <- d$cols[[j]]
    cols[j] <- sprintf("  $ %s <%s> %s", d$names[j], cj$class[1L], .gptr_fmt_values(cj, f$nrow, sampled))
  }
  if (d$p > length(d$cols)) cols <- c(cols, sprintf("  ... and %d more columns: %s", d$p - length(d$cols),
                                                    paste(utils::head(d$names[-seq_along(d$cols)], 20), collapse = ", ")))
  note <- if (sampled) sprintf("  (column stats from an evenly spaced sample of 100,000 of %s rows)", gptr_fmt_n(f$nrow))
  gptr_fit(c(hdr, note, cols), budget)
}

gptr_describe.matrix <- function(x, budget = 300L, ...) {
  f <- .gptr_leaf_core(x); m <- .gptr_leaf_matrix(x)
  .gptr_fmt_matrix(f, m, budget)
}
.gptr_fmt_matrix <- function(f, m, budget) {
  force(f); force(m); force(budget)
  gptr_fit(c(.gptr_fmt_header(f),
             sprintf("  type %s; rownames: %s; colnames: %s", f$type,
                     if (is.null(m$rn)) "none" else paste(m$rn, collapse = ", "), if (is.null(m$cn)) "none" else paste(m$cn, collapse = ", ")),
             paste0("  ", utils::capture.output(print(unname(m$corner), digits = 4)))), budget)
}

gptr_describe.list <- function(x, budget = 300L, ...) {
  f <- .gptr_leaf_core(x); l <- .gptr_leaf_list(x)
  .gptr_fmt_list(f, l, budget)
}
.gptr_fmt_list <- function(f, l, budget) {
  force(f); force(l); force(budget)
  tab <- sort(table(l$cls), decreasing = TRUE)
  k <- seq_along(l$klen)
  lab <- if (is.null(l$names)) sprintf("[[%d]]", k) else ifelse(nzchar(l$names[k]), paste0("$", l$names[k]), sprintf("[[%d]]", k))
  shape <- vapply(k, function(i) if (length(l$kdim[[i]])) paste(l$kdim[[i]], collapse = " x ") else paste("length", gptr_fmt_n(l$klen[i])), "")
  cls <- vapply(l$kcls, paste, "", collapse = "/")
  lines <- c(.gptr_fmt_header(f),
             sprintf("  element classes%s: %s", if (l$n > 1000L) " (first 1000)" else "", paste(sprintf("%s x%d", names(tab), tab), collapse = ", ")),
             sprintf("  %s: <%s> %s", lab, cls, shape))
  if (l$n > length(k)) lines <- c(lines, sprintf("  ... %s more elements", gptr_fmt_n(l$n - length(k))))
  gptr_fit(lines, budget)
}

gptr_describe.environment <- function(x, budget = 300L, ...) {        # reference object: no copy issue
  nms <- ls(x, all.names = TRUE, sorted = TRUE)
  act <- if (length(nms)) rlang::env_binding_are_active(x, nms) else logical()
  lazy <- if (length(nms)) rlang::env_binding_are_lazy(x, nms) else logical()
  fun <- logical(length(nms))
  for (i in seq_along(nms)) if (!act[i] && !lazy[i]) fun[i] <- is.function(get(nms[i], envir = x, inherits = FALSE))
  lab <- environmentName(x)
  gptr_fit(c(sprintf("<%s>%s with %d bindings (%d functions, %d active, %d unevaluated promises)",
                     paste(class(x), collapse = "/"), if (nzchar(lab)) paste0(" '", lab, "'") else "",
                     length(nms), sum(fun), sum(act), sum(lazy)),
             if (any(!fun)) paste0("  fields: ", paste(utils::head(nms[!fun], 30), collapse = ", ")),
             if (any(fun)) paste0("  methods: ", paste(utils::head(nms[fun], 30), collapse = ", "))), budget)
}
gptr_describe.R6 <- function(x, budget = 300L, ...) gptr_describe.environment(x, budget, ...)

gptr_describe.function <- function(x, budget = 300L, ...) {           # small objects: copies are cheap
  src <- attr(x, "srcref")
  loc <- if (!is.null(src)) sprintf(" defined at %s:%d", basename(attr(src, "srcfile")$filename %||% "?"), src[1L]) else ""
  body_lines <- if (!is.null(src)) as.character(src) else deparse(x)
  gptr_fit(c(sprintf("<function> function(%s)%s; %d lines", paste(names(formals(x)), collapse = ", "), loc, length(body_lines)),
             paste0("  ", utils::head(body_lines, 6))), budget)
}

gptr_describe.lm <- function(x, budget = 300L, ...) {                 # model objects: never modified in place
  cf <- stats::coef(x)
  extra <- if (inherits(x, "glm")) sprintf("family %s(%s); deviance %.4g; AIC %.4g", x$family$family, x$family$link, x$deviance, x$aic)
           else { s <- summary(x); sprintf("R^2 %.3f, adj. R^2 %.3f, sigma %.4g", s$r.squared, s$adj.r.squared, s$sigma) }
  gptr_fit(c(sprintf("<%s> %s; n = %d; %d coefficients", paste(class(x), collapse = "/"),
                     paste(deparse(stats::formula(x)), collapse = " "), stats::nobs(x), length(cf)),
             paste0("  ", extra), paste0("  coef: ", paste(sprintf("%s=%s", names(cf), format(cf, digits = 4)), collapse = ", "))), budget)
}

.gptr_describe_s4 <- function(x, f, budget) {
  slots <- methods::slotNames(f$class)            # by class NAME: x never reaches methods:: internals
  sl <- .gptr_leaf_s4(x, slots)
  .gptr_fmt_s4(f, slots, sl, budget)
}
.gptr_fmt_s4 <- function(f, slots, sl, budget) {
  force(f); force(slots); force(sl); force(budget)
  pkg <- attr(f$class, "package")
  lines <- sprintf("<S4 %s%s>%s", f$class[1L], if (!is.null(pkg)) paste0(" from ", pkg) else "",
                   if (!is.na(f$size)) paste0(" ", gptr_fmt_bytes(f$size)) else "")
  for (i in seq_along(slots)) {
    s <- sl[[i]]
    shape <- if (length(s$dim)) paste(gptr_fmt_n(s$dim), collapse = " x ") else if (!is.na(s$nrow)) sprintf("%s rows", gptr_fmt_n(s$nrow)) else paste("length", gptr_fmt_n(s$length))
    lines <- c(lines, sprintf("  @%s: <%s> %s%s", slots[i], paste(s$class, collapse = "/"), shape,
                              if (length(s$names)) paste0("; names: ", paste(s$names, collapse = ", ")) else ""))
  }
  gptr_fit(lines, budget)
}

# ------------------------------------------------------------------ BY-NAME entry points
# These frames never bind the object, so tryCatch()/loops are safe here.
.gptr_describe_named <- function(name, envir, budget) gptr_describe(get(name, envir = envir, inherits = FALSE), budget = budget)

gptr_describe_binding <- function(name, envir, budget = 300L) {
  if (bindingIsActive(name, envir)) return(sprintf("%s: <active binding> (not evaluated)", name))
  if (rlang::env_binding_are_lazy(envir, name)) {
    expr <- if (!identical(envir, globalenv())) eval(call("substitute", as.name(name)), envir) else NULL
    return(sprintf("%s: <promise, not yet evaluated>%s", name,
                   if (!is.null(expr)) paste0(" = ", substr(paste(deparse(expr), collapse = " "), 1, 80)) else ""))
  }
  d <- tryCatch(.gptr_describe_named(name, envir, budget),
                error = function(e) sprintf("<?> (describe failed: %s)", conditionMessage(e)))
  d[1L] <- paste0(name, ": ", d[1L])
  d
}

# ------------------------------------------------------------------ snapshot + diff
.gptr_fp_hash <- function(core, fp, full_hash_max) {
  force(core); force(fp); force(full_hash_max)
  rlang::hash(list(core$class, core$length, core$dim, fp))
}
.gptr_snapshot_row_named <- function(name, envir, full_hash_max) {
  core <- .gptr_leaf_core(get(name, envir = envir, inherits = FALSE))
  small <- !is.na(core$size) && core$size <= full_hash_max && !core$env && !core$fun
  fp <- if (small) rlang::hash(get(name, envir = envir, inherits = FALSE))          # thin .Call wrapper
        else if (core$env || core$fun) core$address
        else .gptr_fp_hash(core, .gptr_leaf_fp(get(name, envir = envir, inherits = FALSE)), full_hash_max)
  list(core = core, fp = fp)
}

gptr_env_snapshot <- function(envir = globalenv(), full_hash_max = 5e7) {
  nms <- setdiff(ls(envir, all.names = TRUE, sorted = TRUE), c(".Random.seed", ".Last.value"))
  out <- data.frame(name = nms, kind = rep("value", length(nms)), address = NA_character_, class = NA_character_,
                    bytes = NA_real_, shape = NA_character_, fp = NA_character_, stringsAsFactors = FALSE)
  if (!length(nms)) return(out)
  act <- rlang::env_binding_are_active(envir, nms); lazy <- rlang::env_binding_are_lazy(envir, nms)
  out$kind[act] <- "active"; out$kind[lazy] <- "promise"
  for (i in which(!(act | lazy))) {
    r <- .gptr_snapshot_row_named(nms[i], envir, full_hash_max)
    out$address[i] <- r$core$address; out$class[i] <- paste(r$core$class, collapse = "/")
    out$bytes[i] <- r$core$size; out$fp[i] <- r$fp
    out$shape[i] <- sub("^<[^>]*> ", "", sub(",[^,]*$", "", .gptr_fmt_header(r$core)))
  }
  out
}

gptr_env_diff <- function(old, new) {
  both <- intersect(new$name, old$name)
  o <- old[match(both, old$name), , drop = FALSE]; n <- new[match(both, new$name), , drop = FALSE]
  eq <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  same <- o$kind == n$kind & eq(o$address, n$address) & eq(o$fp, n$fp)
  list(added = setdiff(new$name, old$name), removed = setdiff(old$name, new$name), modified = both[!same])
}

format_gptr_env_diff <- function(d, new) {
  row <- function(nm) { r <- new[new$name == nm, ]; sprintf("%s <%s> %s%s", nm, r$class, r$shape, if (!is.na(r$bytes)) paste0(", ", gptr_fmt_bytes(r$bytes)) else "") }
  c(if (length(d$added)) paste("+", vapply(d$added, row, "")),
    if (length(d$modified)) paste("~", vapply(d$modified, row, "")),
    if (length(d$removed)) paste("-", d$removed))
}

# One line per binding, largest first, within a token budget: the per-turn "workspace" context.
gptr_workspace_summary <- function(envir = globalenv(), budget = 600L, snapshot = gptr_env_snapshot(envir)) {
  s <- snapshot[order(-ifelse(is.na(snapshot$bytes), 0, snapshot$bytes)), , drop = FALSE]
  lines <- ifelse(s$kind == "value", sprintf("%s <%s> %s%s", s$name, s$class, s$shape,
                                              ifelse(is.na(s$bytes), "", paste0(", ", vapply(s$bytes, gptr_fmt_bytes, "")))),
                  sprintf("%s <%s, not evaluated>", s$name, s$kind))
  gptr_fit(lines, budget)
}
```

The earlier prototype `W12/gptr_describe.R` also has `dgCMatrix`, `ArrowTabular`,
`DBIConnection` and `ggplot` methods. Port them to the leaf/formatter pattern: `x@Dim`,
`length(x@x)`, `x$num_rows` and `x$schema$ToString()` are all cheap. **Known fix-ups:** in the
summary line use `attr(x, "Dim")` for S4 matrices; add an `ArrowTabular` method, otherwise arrow
Tables are described as R6 environments; add `names`/`nrow` handling for tibble list-columns.

### 5.3 Gateway: `W12/gptr_gateway.R` (final, complete)

```r
# gptr_gateway.R -- prototype of the single variadic gateway gptr(...) (Track 12, parts D + E)
# Base R + rlang (enquo/enquos). The "agent" is mocked: it records the call shape and can designate a value.

the <- new.env(parent = emptyenv())          # package-level state (in a package: the namespace)
the$sessions <- list(); the$current <- NULL
the$known_models <- c("opus", "sonnet", "haiku", "jev", "gemini", "codex", "claude_code", "gpt")
the$known_skills <- c("seurat", "plotting", "statistics", "single_cell")

# ------------------------------------------------------------------ identifier NSE (models, skills, ...)
# Rules (applied to the captured expression + its environment):
#   "opus"                 string literal            -> "opus"
#   opus                   bare symbol, known alias  -> "opus"   (library(pkg) semantics; alias wins)
#   m   (m <- "opus")      bare symbol, not an alias, bound in caller -> value of m (must be character / gptr id)
#   gpt5                   bare symbol, unknown, unbound -> "gpt5" (literal; validated later against the catalog)
#   c(seurat, plotting)    c()/list() -> each element resolved by the rules above
#   !!x  or  .env$x        explicit injection: evaluate x in the caller, bypassing aliases
#   if (hard) opus else haiku / paste0(...)   any other call: evaluated in a mask whose bindings are
#                          the known aliases (bound to their own names) and whose parent is the caller
gptr_resolve_ids <- function(expr, env, known) {
  if (is.null(expr)) return(NULL)
  if (is.character(expr)) return(expr)
  if (is.symbol(expr)) {
    nm <- as.character(expr)
    if (nm %in% known) return(nm)
    if (exists(nm, envir = env)) {
      v <- get(nm, envir = env)
      if (is.character(v) || inherits(v, "gptr_id")) return(as.character(v))
      stop(sprintf("`%s` is a variable of class <%s>, not a model/skill name. Quote the name (\"%s\") or pass a character value.",
                   nm, class(v)[1L], nm), call. = FALSE)
    }
    return(nm)
  }
  if (is.call(expr)) {
    head <- expr[[1L]]
    if (identical(head, quote(`!`)) && is.call(expr[[2L]]) && identical(expr[[2L]][[1L]], quote(`!`)))
      return(as.character(eval(expr[[2L]][[2L]], env)))                       # !!x
    if (identical(head, quote(c)) || identical(head, quote(list)))
      return(unlist(lapply(as.list(expr)[-1L], gptr_resolve_ids, env = env, known = known), use.names = FALSE))
    mask <- list2env(stats::setNames(as.list(known), known), parent = env)
    assign(".env", env, envir = mask)                                          # .env$x pronoun
    return(as.character(eval(expr, mask)))
  }
  as.character(expr)
}

# ------------------------------------------------------------------ result / session objects
new_gptr_session <- function(envir) {
  s <- new.env(parent = emptyenv())
  s$id <- paste0("s", length(the$sessions) + 1L); s$turns <- list(); s$envir <- envir
  class(s) <- "gptr_session"
  the$sessions[[s$id]] <- s
  s
}
new_gptr_result <- function(text, session, value = NULL, has_value = FALSE, usage = NULL, model = NULL, streamed = FALSE) {
  structure(list(text = text, value = value, has_value = has_value, session = session,
                 usage = usage %||% list(input_tokens = 0L, output_tokens = 0L, cost = 0),
                 model = model, streamed = streamed), class = "gptr_result")
}
`%||%` <- function(a, b) if (is.null(a)) b else a
print.gptr_result <- function(x, ...) {
  cat(x$text, "\n", sep = "")
  cat(sprintf("<gptr_result> session %s, turn %d, model %s%s\n", x$session$id, length(x$session$turns),
              x$model %||% "?", if (x$has_value) sprintf(", value: <%s>", paste(class(x$value), collapse = "/")) else ""))
  invisible(x)
}
as.character.gptr_result <- function(x, ...) x$text
format.gptr_result <- function(x, ...) x$text
print.gptr_session <- function(x, ...) { cat(sprintf("<gptr_session %s> %d turns\n", x$id, length(x$turns))); invisible(x) }

# The agent designates an R object as the result of the current request (called from r-tool code).
gptr_return <- function(value) {
  if (is.null(the$current)) stop("gptr_return() can only be called by the agent during a gptr() request", call. = FALSE)
  the$current$value <- value; the$current$has_value <- TRUE
  invisible(value)
}

# ------------------------------------------------------------------ target environment
gptr_target_env <- function(env) {
  # magrittr 2.x evaluates `lhs %>% f()` in a temporary child env whose only binding is `.`;
  # objects created there would be lost, so use its parent (the real caller).
  if (!identical(env, globalenv()) && identical(ls(env, all.names = TRUE), ".")) parent.env(env) else env
}

# ------------------------------------------------------------------ the gateway
# Dots and identifier arguments are captured with rlang::enquos()/enquo(): expression + the
# environment it came from, WITHOUT forcing the promise. Consequences (verified):
#   * forwarded dots (function(...) gptr(...)) resolve in the right environment (base
#     substitute() + parent.frame() gets this wrong);
#   * a large object passed as context is never bound in gptr()'s frame, so no sticky reference
#     is created (tracemem: next in-place edit stays in place);
#   * `!!x` injection works for free (rlang processes it at capture time).
.gptr_leaf_peek <- function(x) list(class = class(x), is_chr1 = is.character(x) && length(x) == 1L && !is.object(x))

.gptr_dot_facts <- function(q) {
  n <- length(q)
  out <- data.frame(label = character(n), kind = character(n), class1 = character(n),
                    is_session = logical(n), is_chr1 = logical(n), is_literal = logical(n), stringsAsFactors = FALSE)
  nms <- names(q) %||% rep("", n)
  for (i in seq_len(n)) {
    e <- rlang::quo_get_expr(q[[i]]); env <- rlang::quo_get_env(q[[i]])
    if (is.character(e) && length(e) == 1L) {                 # string literal (incl. raw strings)
      pk <- list(class = "character", is_chr1 = TRUE); out$kind[i] <- "literal"; out$is_literal[i] <- TRUE
    } else if (is.symbol(e) && exists(as.character(e), envir = env)) {
      pk <- .gptr_leaf_peek(get(as.character(e), envir = env)); out$kind[i] <- "binding"      # by name, promise untouched
    } else {
      pk <- .gptr_leaf_peek(rlang::eval_tidy(q[[i]])); out$kind[i] <- if (is.call(e)) "call" else "value"
    }
    out$class1[i] <- pk$class[1L]
    out$is_session[i] <- any(pk$class %in% c("gptr_result", "gptr_session"))
    out$is_chr1[i] <- pk$is_chr1 || "glue" %in% pk$class
    out$label[i] <- if (nzchar(nms[i])) nms[i] else if (is.symbol(e)) as.character(e)
                    else if (is.call(e)) gptr_label(e) else sprintf("..%d", i)
  }
  out$named <- nzchar(nms)
  out
}

gptr_resolve_quo <- function(q, known) gptr_resolve_ids(rlang::quo_get_expr(q), rlang::quo_get_env(q), known)

gptr <- function(..., model = NULL, skills = NULL, extensions = NULL, plugins = NULL,
                 prompt = NULL, mode = NULL, envir = parent.frame()) {
  envir <- gptr_target_env(envir)
  q <- rlang::enquos(...)
  model  <- gptr_resolve_quo(rlang::enquo(model), the$known_models)
  skills <- gptr_resolve_quo(rlang::enquo(skills), the$known_skills)
  f <- .gptr_dot_facts(q)
  unnamed <- !f$named
  cont <- which(f$is_session & unnamed)[1L]
  session <- if (!is.na(cont)) { s <- rlang::eval_tidy(q[[cont]]); if (inherits(s, "gptr_result")) s$session else s } else NULL
  cand <- unnamed & !f$is_session
  p_idx <- if (!is.null(prompt)) NA_integer_
           else if (any(cand & f$is_literal)) which(cand & f$is_literal)[1L]    # a string literal wins
           else if (any(cand & f$is_chr1)) which(cand & f$is_chr1)[1L]          # else first length-1 string
           else NA_integer_
  if (is.null(prompt) && !is.na(p_idx)) prompt <- as.character(rlang::eval_tidy(q[[p_idx]]))
  ctx <- setdiff(which(!f$is_session), p_idx)
  context <- q[ctx]                                     # quosures: expression + env, no values
  names(context) <- f$label[ctx]
  if (is.null(prompt) && !length(context) && is.null(session)) {
    if (!interactive()) stop("gptr() without a prompt starts the interactive console and needs an interactive session.", call. = FALSE)
    return(invisible(structure(list(kind = "interactive"), class = "gptr_stub")))
  }
  session <- session %||% new_gptr_session(envir)
  turn <- list(prompt = prompt, model = model, skills = skills, context = f$label[ctx],
               context_kind = f$kind[ctx], envir = if (identical(envir, globalenv())) "globalenv()" else format(envir))
  session$turns[[length(session$turns) + 1L]] <- turn
  req <- new.env(parent = emptyenv()); req$value <- NULL; req$has_value <- FALSE
  the$current <- req; on.exit(the$current <- NULL, add = TRUE)
  agent_code <- getOption("gptr.mock_agent_code")
  if (!is.null(agent_code)) eval(parse(text = agent_code), envir)            # stands in for the r tool
  res <- new_gptr_result(text = sprintf("[mock answer to: %s]", prompt %||% "<no prompt>"), session = session,
                         value = req$value, has_value = req$has_value, model = model %||% "default")
  attr(res, "turn") <- turn
  if (isTRUE(res$streamed)) invisible(res) else res
}

gptr_label <- function(e) {
  d <- paste(deparse(e, width.cutoff = 60L, nlines = 1L), collapse = "")
  if (nchar(d) > 60L) paste0(substr(d, 1L, 57L), "...") else d
}
```

Observed output of `W12/exp_de_gateway.R` is summarised in §2.D and §2.E. Full lines:
`gptr('p', model = if (hard) opus else haiku)  prompt="p" model=opus`;
`gptr('p1') |> gptr('p2') |> gptr('p3')  prompt="p3" model=opus ... session=s24 turn=3`;
`gptr(s, 'p4') [session object]  ... session=s24 turn=4`;
`purrr::map(abstracts, gptr, 'Is RCT?') [ambiguous]: prompts = a1 a2 a3`;
`class(res$value): lm | as.character(res): [mock answer to: Fit mpg on wt and return the model] | fit created in caller env: TRUE`.

### 5.4 Copy-safety regression (fresh R process per line; `W12/run_copycheck2.sh`; output `W12/out/copycheck_final.txt`)

Harness (each case writes and runs this script, then greps for a `tracemem[` line):

```bash
cat > /tmp/cc2_$$.R <<RS
suppressPackageStartupMessages({ source("gptr_eval2.R"); source("gptr_introspect.R"); source("gptr_gateway.R") })
$1                      # setup, e.g. v <- runif(5e6)
invisible($2)           # operation under test
invisible(tracemem($3)) # traced object
$4                      # the user's next in-place edit, e.g. v[1] <- 0
cat("END\n")
RS
```

```
[plain R] v <- runif(5e6); v[1] <- 0                           -> in place
[plain R] str(v)                                               -> COPY
[plain R] lobstr::obj_size(v)                                  -> COPY
[plain R] utils::object.size(v)                                -> in place
[plain R] rlang::hash(v)                                       -> in place
[plain R] withVisible(v)                                       -> COPY
[evaluate] evaluate::evaluate("v <- runif(5e6)")               -> COPY
[evaluate] evaluate::evaluate("v")                             -> COPY
[gptr] gptr_eval("v <- runif(5e6)")                            -> in place
[gptr] gptr_eval("v")                                          -> in place
[gptr] gptr_eval("print(v); summary(v); head(v)")              -> in place
[gptr] gptr_eval("(v)") (residual: visible passthrough)        -> COPY
[gptr] gptr_describe(v)                                        -> in place
[gptr] gptr_describe(m)                                        -> in place
[gptr] gptr_describe(L); L$a[1] <- 0                           -> in place
[gptr] gptr_env_snapshot() + gptr_workspace_summary()          -> in place
[gptr] gptr_env_snapshot(full_hash_max = 0) [sampled path]     -> in place
[gptr] gptr("describe", v)                                     -> in place
[gptr] v |> gptr("describe")                                   -> in place
[gptr] gptr("a") |> gptr("b", v, model = opus)                 -> in place
```

Also in place: `(function(...) gptr(...))("describe", v)` (forwarded dots). COPY for a wrapper that
binds the object as a named argument (inherent, §2.D2).

### 5.5 Other key experiments (scripts in `W12/`)

**evaluate sink bug** (`exp_a7_evaluate_sink_bug.R`):
```r
res <- evaluate::evaluate("sink(tempfile()); cat('into user sink\\n')", envir = new.env())
message("sink.number() after evaluate: ", sink.number())
r <- tryCatch({ cat("console output after evaluate\n"); "cat OK" }, error = function(e) paste("cat FAILED:", conditionMessage(e)))
message(r)
while (sink.number() > 0) sink()
```
Output: `sink.number() after evaluate: 1` / `cat FAILED: invalid connection` /
`Error in sink() : invalid connection` / `Execution halted`. (Verifier re-run: the same output. With
`try(sink(), silent = TRUE)` instead of the final loop, `sink.number()` becomes 0 and `cat()` works
again.)

**Promises and active bindings** (`exp_c1_promises.R`), output excerpt:
```
bindingIsActive('act', e)                        =>  TRUE
rlang::env_binding_are_lazy(e)                   =>  FALSE FALSE  TRUE
rlang::env_binding_are_active(e)                 =>  FALSE  TRUE FALSE
substitute(lazy_big, e) [non-global env]         =>  { cat("  !! PROMISE FORCED\n"); 1:10 }
rlang::env_binding_are_lazy(globalenv(), 'glazy') =>  TRUE
substitute(glazy, globalenv())                   =>  glazy
as.list(new.env w/ promise) forces?   !! as.list forced it
mget forces?                          !! mget forced it
eapply forces?                        !! eapply forced it
rlang::env_binding_are_lazy(e5)  [lazyLoad db]   =>  TRUE      (after get: FALSE; heap 37.7 -> 45.4 Mb)
```

**magrittr** (`exp_b2_magrittr.R`):
```
native pipe:   envir bindings: [make_obj]  is globalenv: TRUE
magrittr pipe: envir bindings: [.]  is globalenv: FALSE
exists from_native: TRUE  from_magrittr: FALSE  from_magrittr2: FALSE
with heuristic, exists fixed_magrittr: TRUE
```

**Task callback** (`exp_c19_taskcb.R`):
```r
log <- character()
id <- addTaskCallback(function(expr, value, ok, visible) {
  log[length(log) + 1L] <<- paste(deparse(expr, nlines = 1L), collapse = ""); TRUE
}, name = "gptr_history")
m <- runif(5e6); invisible(tracemem(m)); m[1] <- 0; x <- 1 + 1
removeTaskCallback("gptr_history"); print(log)
```
Output (Rscript and `R --interactive`, no tracemem line, so no copy), corrected after the verifier
re-run: the log starts with the registering expression itself,
`"id <- addTaskCallback(function(expr, value, ok, visible) {" "m <- runif(5e+06)" "invisible(tracemem(m))" "m[1] <- 0" "x <- 1 + 1"`.

**knitr engine** (`knit/engine.Rmd`): see 3.12. The rendered output was
```` ``` gptr ```` followed by the prose, then `## [mock answer to: Summarise the data frame `df`, it's the first rows of mtcars. / Use "quotes" and {braces} freely -- no escaping needed.]`.

**R CMD check toy packages:** `W12/toypkg` (globalenv patterns, results in B2) and `W12/toygptr`
(all three prototypes). The only code-level findings were the expected undocumented-object
warning and the offline time NOTE.

Not run: Windows (no Windows host); Jupyter/IRkernel end to end (no Jupyter; analysed from
IRkernel source); Positron's graphics device.

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN

- **Global environment:** default to `parent.frame()`; never `assign(..., .GlobalEnv)`, never
  `<<-` to an unbound name, never `.GlobalEnv$x <-`. Tests use `envir = new.env()` or
  `local()`. The task callback, graphics hooks and sinks are session state, so install them only
  during a user-initiated `gptr()` call or session and remove them on exit and in `.onUnload`.
  `setHook(packageEvent("knitr", "onLoad"), ...)` in `.onLoad` for the engine follows glue's
  precedent.
- **No `q()` calls** from package code (policy). The guard also prevents model code from calling
  them.
- **Files:** plot PNGs and spilled output live in `tempdir()` (allowed). Never let a default device
  open in a non-interactive session (it would write `Rplots.pdf` to the working directory). The
  offscreen recording device avoids this, VERIFIED.
- **Third-party data:** workspace summaries sent to an LLM are "information about the R session".
  Make it explicit (user call, `context =`, first-run notice). The policy wording is "without
  obtaining confirmation from the user", so a notice alone may not be enough (**UNCERTAIN**, see
  B4).
- **No internals:** no `grDevices:::dev.displaylist`, no `.Internal(inspect())`, no `:::` into
  base. Use rlang for promise detection (public API).
- **Examples and tests:** no network or LLM calls on CRAN (another track). The tracemem regression
  tests need `capabilities("profmem")` (TRUE on this macOS build, VERIFIED; CRAN's Windows and
  macOS binaries are built with memory profiling, **LIKELY**; Linux check flavours **UNCERTAIN**). Use `skip_if_not(capabilities("profmem"))` and `skip_on_cran()` for the
  slow big-object cases. Signal-based interrupt tests work only on Unix:
  `skip_on_os("windows")`.
- Byte-compilation stays on (the default). The copy-safety rules were verified with JIT on,
  `R_ENABLE_JIT` default. With the JIT off some results differ (`W12/exp_c12_loop.R` under
  `R_ENABLE_JIT=0`), so run the regression tests against the *installed* package.

### 6.2 Windows specifics

- **Encoding:** "From version 4.2.0 released in April 2022, R on Windows uses UTF-8 as the native
  encoding via UCRT" (https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/, VERIFIED), so bytes read from the
  anonymous sink are UTF-8. On R 4.1 on Windows the bytes are in the native code page. The
  prototype marks them `"unknown"` when `l10n_info()$UTF-8` is FALSE; convert with
  `enc2utf8()` before JSON. Recommend `Depends: R (>= 4.2)`, or at least test on 4.1 Windows
  (**UNCERTAIN** behaviour with CJK output on 4.1).
- **Devices:** the screen device is `windows()`; RStudio uses `RStudioGD`; both keep display lists
  (screen devices record by default, `?dev.control`). `png()` on Windows uses GDI and works
  headless; ragg is still preferred for identical output across platforms. `pdf(NULL)` works on
  all platforms (it is evaluate's fallback, used by knitr everywhere).
- **Interrupts:** Esc in Rgui, Ctrl-C in Rterm and the RStudio/Positron stop button all raise the
  R `interrupt` condition, so the same handlers apply (**LIKELY**; not tested on Windows).
  `tools::pskill(pid, SIGINT)` cannot be used on Windows (pskill terminates), so there is no
  watchdog interrupt there. Rely on `setTimeLimit()`.
- **`file("", "w+b")`** anonymous temp files work on Windows (evaluate relies on them on every
  platform; **LIKELY**).
- **Guard:** add `shell()` and `shell.exec()` (Windows-only) to the system list (present). There is
  no POSIX shell assumption anywhere in the evaluator.
- **Paths in messages:** `tempdir()` paths contain backslashes. JSON-escape them (jsonlite does).
- **Signals and `setTimeLimit`:** time limits are checked "whenever a user interrupt could occur"
  (`?setTimeLimit`), which on Windows is the same interrupt-check path (**LIKELY**). Behaviour on
  `Sys.sleep` is **UNCERTAIN** there too.

---

## 7. Risks, pitfalls, open questions

1. **Sticky references are a moving target.** They depend on R internals (bytecode, promise
   cleanup, the disabled `cleanupEnvVector`). A future R version may improve or change them. The
   tracemem regression suite (§5.4) must run in CI on R-release and R-devel. Extension `describe`
   methods written carelessly can cause one extra copy for plain vectors, matrices and lists
   (harmless for S4, data.frame, data.table and environments).
2. **Visible passthrough** (`(x)`, `identity(x)`, `x[]`) still bumps the refcount. Tell the model:
   "to show an object, write its name". Possible improvement: a static check for `(sym)` and
   `identity(sym)` to treat them like symbols.
3. **Timeouts cannot stop C code.** A `solve()` on a big matrix, a long `grepl()`, a single long
   `Sys.sleep()`, or a blocking socket read will run past the limit. The UI must offer Ctrl-C (the
   same limitation as the console), and the model should be told the timeout is best effort.
4. **Change detection misses in-place edits at unsampled positions** of objects above 50 MB (for
   example `m[i, j] <- v` and `data.table::set()`). Mitigations: the task-callback log (user code),
   static assignment-target analysis (agent code), and an adaptive full-hash budget. The residual
   risk is edits made by *functions* the user calls (e.g. a C++ routine modifying by reference).
5. **The guard is not a sandbox.** `eval(parse(text = ...))`, `get("q")()` with a computed string,
   `g <- q; g()` (in the current prototype, see 3.6),
   `system("kill ...")`, `tools::pskill(Sys.getpid())` and `rm(list = ls())` all evade or bypass
   the block list. Permission modes (D-11) must treat the `dynamic` and `system` categories as
   "ask" in manual mode. Proposed extra: flag `rm(list = ls(...))` as destructive.
6. **stderr is not captured.** `cat(file = stderr())` and C-level `REprintf` reach the user's
   console only. A dedicated `sink(type = "message")` is possible but risky (there is only one
   message sink and it cannot be split). Open question: accept the gap, or capture messages with
   `sink(type = "message")` only when no message sink exists (`sink.number(type = "message") == 2`)?
7. **Message semantics differ from the console:** messages are muffled, so a user's own message
   sink does not receive them during agent code. Same as evaluate. Acceptable.
8. **Prompt ambiguity** in programmatic mapping (`purrr::map(xs, gptr, "question")` when each `x` is
   a string). Mitigation: documentation plus a warning when two unnamed literal strings are
   present ("name the prompt argument").
9. **magrittr label:** context piped with `%>%` gets the label `.`. The native pipe is recommended.
   Recovering the LHS expression from magrittr internals is possible but fragile. Not recommended.
10. **Alias shadowing:** a user variable with an alias's name (`jev <- ...`) is ignored for
    `model = jev`. That is the library() convention and documented, with `!!jev` as the escape.
    Open question for the interface contract: should gptr warn when shadowing happens?
11. **ALTREP sizes** are overstated by `object.size()` (3.7 GB for `1:1e9`). Consider special-casing
    integer or double vectors whose first and last elements and length match a compact sequence,
    or ask the lobstr maintainers for a list-free API. Low priority.
12. **Plots in interactive sessions without a device:** the model's first plot opens a window
    (quartz, windows or X11) or the RStudio pane. That is the desired "show the user" behaviour,
    but `plots = "offscreen"` must be available (`gptr.plots` option) for users who find it
    intrusive.
13. **Positron and VS Code R** graphics devices were not tested (**UNCERTAIN**). `recordPlot()` should
    work, since they are regular R devices.
14. **Nested evaluation inside knitr and Jupyter:** agent code output is captured for the model and
    does **not** appear in the document (only plots do, device mode). Decide whether to echo the
    agent's code and output into the document (REQ-26 "key outputs recorded as comments"). The
    document writer (another track) should render the `events` list.
15. **`gptr_return()` sharing:** the returned object is the same SEXP as the agent's binding in
    `envir`, so the first in-place edit of either copies once. This is expected R semantics; worth
    one sentence in the docs.

---

## 8. Sources

Local (read or executed):
- evaluate 1.0.5 installed source (functions printed with `Rscript -e`): `W12/evaluate_src.txt`.
- Pi (commit 1b34779) `packages/coding-agent/src/core/tools/truncate.ts` lines 11-13;
  `packages/coding-agent/src/core/tools/bash.ts` lines 22-43, 258.
- R 4.4.3 help: `?dev.control`, `?setTimeLimit` (rendered with `tools::Rd2txt`).
- `tools:::.check_package_code_assign_to_globalenv`, `tools:::.check_package_code_data_into_globalenv`
  (printed).
- IRkernel 1.3.2 `Executor$execute` (deparsed); `glue:::.onLoad` (printed); `shiny::loadSupport`
  args; `knitr::knit`, `rmarkdown::render`, `base::load`, `base::source`, `utils::data`,
  `evaluate::evaluate` args (printed).
- All experiments: `W12/exp_*.R`, `W12/run_copycheck*.sh`, `W12/knit/*.Rmd`, `W12/toypkg`,
  `W12/toygptr`, outputs in `W12/out/`.

Web:
- CRAN Repository Policy, revision 6875: https://cran.r-project.org/web/packages/policies.html
- btw source (Posit): https://github.com/posit-dev/btw/blob/main/R/tool-run.R,
  https://github.com/posit-dev/btw/blob/main/R/tool-env.R, https://github.com/posit-dev/btw/blob/main/R/btw_this.R;
  CRAN page https://cran.r-project.org/web/packages/btw/index.html (1.5.0, published 2026-09-09).
- evaluate NEWS: https://raw.githubusercontent.com/r-lib/evaluate/main/NEWS.md; CRAN page
  https://cran.r-project.org/web/packages/evaluate/index.html (1.0.5, 2025-08-27).
- R blog, UTF-8 and UCRT on Windows since R 4.2.0: https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/
- R source `src/main/eval.c` at tag R-4-4-3 (R_CleanupEnvir, countCycleRefs, cleanupEnvVector):
  https://github.com/wch/r-source/blob/tags/R-4-4-3/src/main/eval.c
- targets `tar_load()` reference: https://docs.ropensci.org/targets/reference/tar_load.html
- Anthropic vision documentation (image limits and token formula):
  https://platform.claude.com/docs/en/build-with-claude/vision

---

## Verification log

Independent adversarial check, 2026-09-29. Same machine: R 4.4.3, `Rscript --vanilla`, with the
package versions in the header re-confirmed. lobstr, targets, duckdb and xxhashlite came from the
private library. Every prototype in §5.1-5.3 was extracted **from this report** (not from `W12/`)
into `work/verify-12/rep_*.R`. They are byte-identical to `W12/gptr_eval2.R`,
`W12/gptr_introspect.R` and `W12/gptr_gateway.R`, and all of them were run. Scripts and outputs are
in `scratchpad/work/verify-12/`.

| # | Claim | Verdict | Source / method |
|---|---|---|---|
| 1 | Pi `truncate.ts` l.11-13 `DEFAULT_MAX_LINES = 2000`, `DEFAULT_MAX_BYTES = 50 * 1024`; `bash.ts` l.40-43 schema `{command, timeout?}` "no default timeout"; l.258 description; tail truncation plus temp file | confirmed | Pi clone @1b34779 (`truncate.ts`, `bash.ts`, `output-accumulator.ts` uses `truncateTail`, `tmpdir()`) |
| 2 | `evaluate()` / `new_output_handler()` signatures; `rlang_trace_top_env` set and not restored; withCallingHandlers runs the first-listed handler first; `calling_handlers` see user frames | confirmed | `args()`, `deparse()`, executed |
| 3 | evaluate sink bug: console broken after the model leaves a sink open | confirmed; **corrected**: "only `closeAllConnections()` recovers" is wrong, since one `try(sink())` recovers | `v_sink*.R` |
| 4 | evaluate error conditions carry only `message`/`call` | **corrected** (rlang errors keep `trace`; top-level `stop()` has no call) | `v_eval2.R` |
| 5 | evaluate sticky reference (`evaluate("v <- runif(5e6)")`, then `v[1] <- 0` copies) and `new_device = FALSE` misses plots on a device the code opens | confirmed | tracemem in a fresh process; `v_nd.R` |
| 6 | evaluate 1.0.5 on CRAN, 2025-08-27, no Imports; NEWS 1.0.4 "runs cleanup with interrupts suspended"; plot heuristics (`non_visual_calls`, `x[]` prefix test) | confirmed | CRAN page, NEWS.md, printed internals |
| 7 | btw 1.5.0 on CRAN 2026-09-09, evaluate in Suggests; `btw_tool_run_r_impl(code, .envir = global_env(), ...)`; withr restore calls; `btw.run_r.enabled` / `BTW_RUN_R_ENABLED`; tool text and security note | confirmed | CRAN page; `R/tool-run.R` on main (identical to `W12/ext` copy) |
| 8 | withr `local_options()` / `local_envvar()` with no args | **corrected**: `local_envvar()` restores existing variables, only new ones leak | `v_withr*.R`, withr 3.0.2 |
| 9 | 19-case torture suite on `gptr_eval2.R` | confirmed; the interrupt count is nondeterministic (re-run gave `2 of 4`) | `my_torture.R`, UTF-8 locale |
| 10 | `setTimeLimit()`: not enforced for `Sys.sleep(3)`, `sort`, `solve`, `grepl`; enforced for R loops and `vapply`; message and class `simpleError` | confirmed (`solve` re-run at 1600x1600; `grepl` interrupt checks are commented out in R 4.4.3 `grep.c`); `R.utils::withTimeout(Sys.sleep)` gave no error at all on re-run; CPU-limit timing 0.55 s, not 1.98 s | `v_timeout.R`, `v_rutils.R`, `v_grepl.R`, `?setTimeLimit` |
| 11 | CRAN policy quotes (global env, `q()`, third-party sites, `:::`, limited exceptions), revision 6875 | confirmed; the "notice" recommendation was **downgraded to UNCERTAIN** (the policy says "confirmation") | policies.html fetched |
| 12 | R CMD check flags only `assign(..., .GlobalEnv/globalenv())` plus codetools `<<-`; exact messages; the three prototypes give no code NOTE | confirmed | toy packages rebuilt from report code, `R CMD check --as-cran` |
| 13 | `R_CleanupEnvir` l.2137-2164, `countCycleRefs` l.2063-2090, `cleanupEnvVector` disabled ("FIXME: Disabled for now") l.2115-2135 | confirmed | raw `eval.c` at tag R-4-4-3 |
| 14 | Plain-R copy baselines (`str`, `lobstr::obj_size`, `withVisible` copy; `object.size`, `hash`, `head`, `summary`, `anyNA`, `obj_address` do not) | confirmed; data.frame column nuance **added** (alternating copies) | `cc.sh`, fresh process per case |
| 15 | §5.4 gptr copy-safety regression (15 gptr cases including forwarded dots and the named-arg wrapper) | confirmed, all identical | `cc2.sh` with `rep_*.R` |
| 16 | NSE tables D1/D3, pipe chain, `gptr_return`, forwarded-dots rlang vs base, magrittr mask env and heuristic, B1 parent.frame table | confirmed | `v_gateway.R`, `v_b1.R` |
| 17 | Promise/active detection (C1): which functions force; `substitute` on globalenv; lazyLoad bindings lazy; no base "promise" function | confirmed | `v_c1.R`, `?substitute` |
| 18 | Task callback sees top-level expressions without copying | confirmed; §5.5 output **corrected** (the registering expression is logged first) | `v_taskcb.R`, Rscript and `R --interactive` |
| 19 | Sizes: `object.size` vs lobstr (ALTREP 3.7 GB vs 680 B; lobstr slower); hash ranking | confirmed; **added** the ALTREP deferred-string slowdown and representation-dependent hash | `v_sizes2.R`, `v_altrep.R` |
| 20 | 2 GB workspace run (C4) | confirmed qualitatively (0 copies, 139.2 MB, promise intact); timings differ | `my_c18.R` |
| 21 | Anthropic vision: `⌈w/28⌉×⌈h/28⌉`, 1568/2576 px, 1568/4784 tokens, 8000 px, >20 images → 2000 px; 768x512 = 532 tokens; tool_result `is_error` and image blocks | confirmed; **added** the 5 MB Bedrock/Vertex limit | vision.md, handle-tool-calls.md |
| 22 | Signatures: `load`, `source`, `data`, `knit`, `render`, `tar_load`, `loadSupport`; IRkernel `evaluate(..., envir = .GlobalEnv, stop_on_error = 1L)` in `tryCatch(interrupt=)`; glue `.onLoad` engine pattern; knitr engine prototype | confirmed | `args()`, deparse, knit of `engine.Rmd` |
| 23 | httr2 Imports rlang (>= 1.1.0) and glue; `rlang_interactive = FALSE` makes `check_installed()` error; non-interactive `readline`/`menu`/`select.list`/`browser` | confirmed | `packageDescription`, `v_a9.R`, `R --interactive` |
| 24 | Min R: `...elt` 3.5.0, `suspendInterrupts` 3.5.0, `tryInvokeRestart` 4.0.0, raw strings 4.0.0, `\|>` 4.1.0; R 4.2 Windows UTF-8 quote | confirmed | R `NEWS`, `NEWS.3`, R blog |
| 25 | Static guard coverage (3.6) | **corrected**: `g <- q; g()` is not blocked | `v_guard.R` |
| 26 | knitr nesting (plot in document and PNG for the model); offscreen mode writes no `Rplots.pdf`; JIT-dependent copy results; `capabilities("profmem")` TRUE; pryr archived | confirmed | `knit2/nested.Rmd`, `off/`, `my_c12.R` with `R_ENABLE_JIT=0`, CRAN page |

Not re-verified (left as stated, labels unchanged): Windows behaviour (§6.2, already LIKELY or
UNCERTAIN), Jupyter end-to-end, Positron devices, the `R --interactive` `Sys.sleep` loop timing, the
PNG file-size comparison (11 KB vs 19 KB), and the `cli_alert_success()` and `stderr` capture notes
in A4.
