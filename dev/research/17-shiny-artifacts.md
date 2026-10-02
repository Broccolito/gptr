# Track 17 — Shiny as the artifact system (REQ-39)

Researcher: track-17 agent, 2026-09-29. Machine: macOS (Darwin 25.6, arm64), R 4.4.3, shiny 1.13.0,
bslib 0.10.0, httpuv 1.6.17, callr 3.7.6, processx 3.8.6, ps 1.9.3, later 1.4.8, htmlwidgets 1.6.4,
plotly 4.12.0, DT 0.34.0, ggplot2 4.0.2, ragg 1.5.2, svglite 2.2.2, rstudioapi 0.18.0, pandoc 3.11
(Homebrew). Private library (scratch, not the user library): chromote 0.5.1, shinytest2 0.5.1,
webshot2 0.1.2, shinylive 0.3.0, shinychat 0.3.0, reactable 0.4.5, leaflet 2.2.3, bsicons 0.1.2,
qs2 0.1.7, rtiktoken 0.0.7 (installed by me, binary from CRAN, for token counting).

**Version drift (added by the fact-check, 2026-09-29; CRAN index pages fetched):** the installed
versions above are *not* current CRAN. Current CRAN: **shiny 1.14.0 (2026-06-21)**, bslib 0.12.0
(2026-08-04), callr 3.8.0 (2026-06-05), processx 3.9.0 (2026-04-22), shinychat 0.5.0 (2026-09-09);
httpuv 1.6.17, later 1.4.8, chromote 0.5.1 and shinylive 0.5.0 are current. Changes that matter
here (all VERIFIED; shiny 1.14.0 and callr 3.8.0 were installed into a scratch library and run):
- shiny 1.14.0 **exports a public non-blocking `startApp()`** (see §2.1 option G). This overturns
  the "impossible with shiny's public API" finding below for shiny ≥ 1.14.0.
- shiny 1.14.0: "Loading shiny no longer creates `.Random.seed` in the global environment" (1.13.0
  does; re-checked: `library(shiny)` creates it on 1.13.0, not on 1.14.0).
- callr 3.8.0: `r_bg()` children "now exit with a non-zero status when the evaluated expression
  throws an error or is interrupted"; the `package` default is now `NULL` (same as `FALSE` for a
  plain function); callr now Imports otel.
- processx 3.9.0 adds `linux_pdeathsig` (Linux-only parent-death signal), a further orphan guard.
- bslib 0.11.0 gives `sidebar()` a new `resizable` argument (the formals in §2.4 are 0.10.0's).

Scratch directory with every script and output referenced below:
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/17/`
(below abbreviated `W17/`; my runs are in `W17/run2/`). A previous researcher left `W17/artifact_lib.R`,
`W17/proto1_run.R`, `W17/proto2_latency.R` with no saved output and no report. I re-ran both
(outputs now in `W17/run2/proto1_output.txt`, `W17/run2/proto2_output.txt`), confirmed them, and
built on them (lib v2, then the final reference implementation `W17/run2/artifact_lib3.R`).

Evidence tags: **VERIFIED** (I saw it: file:line, URL, or executed with output shown), **LIKELY**,
**UNCERTAIN**.

---

## 1. Executive summary

1. **Recommended architecture (VERIFIED end-to-end, E12):** every artifact is a directory
   `.gptr/artifacts/<id>/vNNN/{app.R, R/gptr_data.R, data/<obj>.rds}`, served by a
   **separate R process** started with `callr::r_bg()` that runs `shiny::runApp()`. The session
   objects the model names in `data` are snapshotted with `saveRDS(compress = FALSE)`, and shiny's
   own `R/` autoloader makes them visible to `app.R` under their original names. The parent
   session never loads shiny, the console stays free, and `artifact()` leaves the user's RNG
   stream untouched. **Caveat (fact-check, VERIFIED):** launching headless Chrome for the session
   check (`chromote::Chromote$new()`, via chromote's internal `with_random_port()` → `sample()`)
   *does* change the user's `.Random.seed`; wrap the browser launch in a save/restore of
   `.Random.seed` (verified to fix it).
2. **Startup latency (VERIFIED):** time to HTTP 200 was 0.39–0.45 s for a minimal app, 0.64–0.65 s
   for bslib `page_sidebar`, 0.94–1.12 s with plotly+DT, and 1.1–1.8 s with a custom `bs_theme`
   (Sass compile), all on a lightly loaded machine. Under heavy load (load average ~18, many agents
   running) it rose to 1.1–2.5 s. Spawning the child R process costs about 0.16–0.31 s.
3. **In-process Shiny without blocking: impossible with the public API of shiny ≤ 1.13.0, but
   possible with shiny ≥ 1.14.0 (CORRECTED by the fact-check).** In 1.13.0, `runApp()`/`runGadget()`
   sit in a `while (!.globals$stopped) serviceApp()` loop, and the then-internal
   `shiny:::startApp()` answers HTTP but reactive outputs never render until the internal
   `shiny:::serviceApp()` is pumped (E5 Q3). `runApp()` in a real interactive console blocked typed
   commands (E5b; still true in 1.14.0). **shiny 1.14.0 (current CRAN) exports `startApp()`**, which
   returns a `ShinyAppHandle` (`stop()`, `status()`, `url()`, `result()`) and services the app from
   the `later` event loop. Verified in a pty-driven interactive R: it returned in 0.05 s, reactive
   output rendered from a live object, and a later edit to the object showed up in a new session.
   Limits: requests stall while the console is busy, only **one** such app can run per R session
   (a second `startApp()` stops the first), and a synchronous HTTP request from the same R process
   deadlocks. See §2.1 option G. The callr child remains the recommended default.
4. **In-process `httpuv::startServer()` (public API) does serve live session objects without
   blocking (VERIFIED, E5 Q1),** but only while the console is idle at the prompt: a busy console
   stalls requests (E5 Q2). This is useful for plain HTML/JSON artifacts. For Shiny it needs
   shiny ≥ 1.14.0's `startApp()`, which has the same idle-console limit (item 3).
5. **Fork option (Unix only, VERIFIED E6):** `parallel::mcparallel()` + `runApp()` shared a
   183 MB data frame with zero copying and reached HTTP 200 in 0.76 s. The callr path took 6.06 s
   (saveRDS 1.27 s blocking the console, plus the child reading the file). It is an optional
   accelerator for huge objects on macOS/Linux terminals only. It is not available on Windows and
   is risky inside GUIs.
6. **Cleanup (VERIFIED matrix, E2):** processx's `cleanup = TRUE` finalizer kills the child on
   normal exit *and* on a top-level error exit. After a SIGKILL/crash of the parent, only
   `supervise = TRUE` or an in-child parent-PID watchdog (`ps` + `later`) prevents orphans. Use
   both. An orphan sweep driven by `run.json` with a PID-reuse guard also works (E11).
7. **Port handling (VERIFIED):** `httpuv::randomPort()` calls `sample()` and perturbs the user's
   `.Random.seed` (the same seed gave the same port 35053 twice). So the **child** picks the port
   and publishes it through an atomically renamed file. Re-binding the previous port for a revision
   works immediately, which gives a stable URL across versions (E11, E12).
8. **Validation ladder (VERIFIED, E3b):**
   - (1) `parse()` + static checks (packages installed, forbidden calls, ends with `shinyApp()`).
   - (2) Launch in a clean child: UI-construction errors kill the child and the log tail is returned.
   - (3) HTTP 200.
   - (4) Headless Chrome session via **chromote** (Suggests). This catches render errors
     (`.shiny-output-error`), server-function crashes (disconnect overlay), JS exceptions, and
     server-log `Error in` lines, and it returns a PNG screenshot.

   HTTP 200 alone misses render errors and server crashes. Chrome cold start is 3.4 s once per
   session; each check then takes 1.1–2.1 s.
9. **`shiny::testServer()` works in a clean callr process on an artifact dir (VERIFIED E4),** but
   inputs start as NULL (a browser would send UI defaults), so a naive run reports false errors
   ("argument is of length zero"). It is useful only when the model supplies inputs explicitly.
10. **Screenshots are the highest-value feedback (VERIFIED):** a 1100×750 PNG costs about 1,080
    Claude visual tokens and showed issues no check catches (e.g. axis titles rendered as
    `.data[[input$x]]`, E9b).
11. **Token efficiency (VERIFIED, E9/E9b):** across three functionally equivalent app pairs (all six
    verified working in headless Chrome), the HTML/JS versions cost **3.1–3.7× more tokens**
    (o200k_base) than the Shiny versions: 77 vs 268, 220 vs 686, and 251 vs 935 tokens. Inlining
    the 5,000-row data frame as JSON would cost 127,113 tokens; Shiny references it by name.
12. **Model quality evidence is thin (LIKELY):** I found no public Shiny-specific benchmark.
    - Posit's `are` R benchmark (29 problems) puts late-2025 frontier models at about 64–70% but
      reports no Shiny breakdown.
    - Posit publishes an official `shiny-bslib` agent skill, which implies that steering helps.
    - Plan on a validate→screenshot→fix loop, not one-shot correctness.
13. **House style for the system prompt:** bslib `page_sidebar()` + `sidebar()` +
    `layout_columns(value_box(...))` + `card(card_header(), output, full_screen = TRUE)`, with
    ggplot2 by default and plotly/DT/reactable/leaflet only if installed (list the installed ones
    dynamically). Keep it short: no custom CSS/JS, no modules, and use `edits` for revisions.
14. **HTML fallback (VERIFIED, E7):** gptr wraps model HTML in a 5-line Shiny `app.R` using
    `tags$iframe(srcdoc = html)` and injects the snapshot as `window.GPTR_DATA` (isolates CSS/JS
    from Bootstrap; 4/4 bars drawn, 0 JS errors). Serverless static variants also work (a single
    file with inlined JSON; or an in-process httpuv static server).
    `htmlwidgets::saveWidget(selfcontained = TRUE)` **requires pandoc** (VERIFIED in source).
15. **Sharing:** shinylive bundles **every non-hidden file in the app dir** (VERIFIED in
    `read_app_files` source), so the artifact layout exports unchanged. Runtime files (logs, port)
    must therefore live outside `vNNN/`, which lib3 does. I did not run an export because it
    downloads the web assets. CRAN shinylive is 0.5.0 (2026-06-08), and packages must exist as
    WebAssembly binaries. Quarto dashboards need the Quarto CLI (not assumable).
16. **shinychat front end:** feasible (`chat_append()` accepts strings, generators and promises),
    but it **Imports ellmer** (still true in CRAN 0.5.0, 2026-09-09). An in-process gadget blocks
    the console (with shiny ≥ 1.14.0, `startApp()` could avoid that, see item 3), and a background
    process loses the live objects. **Not in v1.** Revisit as an optional `gptr_app()` later.
17. **Static plots (VERIFIED, E8):** render to `ragg::agg_png(width = 1000, height = 700,
    res = 120)` (fallback `png()`). That is about 184 KB, about 900 Claude tokens (standard and
    high-res tiers) and about 845 GPT-5.x tokens, and it is fully legible. Never send SVG as text:
    a 5,000-point ggplot SVG is 754 KB, about 321,000 tokens. `recordPlot()` needs a display list
    (`pdf(NULL)` without `dev.control("enable")` replays a blank image). `evaluate::evaluate()`
    returns usable `recordedplot` objects.
18. **Dependencies:** Imports: callr, processx, ps, jsonlite, curl (all light, and most are already
    needed elsewhere in gptr). **shiny and bslib go in Suggests**, because only the child needs
    them. Suggests: chromote, ragg, svglite, htmlwidgets, shinylive, rstudioapi. Only public API is
    used; there are no `:::` calls.

---

## 2. Findings

### 2.1 Q1 — Launching an app from a live session without blocking the console

| Option | Public API? | Non-blocking? | Sees in-memory objects? | Cross-platform | Verdict |
|---|---|---|---|---|---|
| A. `callr::r_bg()` child + data snapshot (RDS) | yes | yes | snapshot (named objects) | Win/mac/Linux | **Recommended default** (VERIFIED E1/E12) |
| B. `shiny::runApp()` / `runGadget()` in-process | yes | **no**, blocks the prompt | live | all | Only for an explicitly blocking gadget |
| C. `shiny:::startApp()` + `later` | **no** (internal) | HTTP yes, but reactivity needs `shiny:::serviceApp()` | live | – | Rejected (CRAN; does not even work without pumping) |
| D. `httpuv::startServer()` in-process (non-Shiny) | yes | yes, while the console is idle | **live** | macOS VERIFIED, Linux LIKELY, Windows UNCERTAIN | Optional for HTML/JSON artifacts |
| E. `parallel::mcparallel()` fork + `runApp()` | yes (base) | yes | copy-on-write snapshot, zero copy | **Unix only** | Optional accelerator for huge objects |
| F. `rstudioapi::jobRunScript(importEnv = TRUE)` | yes | yes | copies the **whole** global env | RStudio only (Positron shims unverified) | Not recommended |
| G. `shiny::startApp()` (**shiny ≥ 1.14.0 only**) | yes (exported in 1.14.0) | yes, while the console is idle | **live** | macOS VERIFIED (fact-check); others UNCERTAIN | Optional; one app per session; not the default |

Evidence:

- **A, VERIFIED.**
  - `W17/run2/e1_output.txt` and `W17/run2/e12_output.txt`: `artifact()` returned in 1.86 s /
    2.84 s, the page was served, options in the page came from the shipped data ("All, East,
    North, South, West"), and the console continued working.
  - "shiny loaded in parent: FALSE | user RNG untouched: TRUE".
  - The previous researcher's proto1 reproduced: 1.20 s, HTTP 200, `<title>Sales explorer</title>`,
    and "has option North (proves data snapshot was loaded in child): TRUE"
    (`W17/run2/proto1_output.txt`).
- **B, VERIFIED.**
  - `shiny::runGadget()` source (printed in this session) ends with
    `shiny::runApp(app, port = port, launch.browser = viewer)`.
  - `runApp` has `.globals$stopped <- FALSE; while (!.globals$stopped) { ..stacktracefloor..(serviceApp()) ... }`
    (deparsed `shiny::runApp`, `W17/run2/inspect1.R`).
  - In a real interactive R console driven through a pseudo-terminal, `runApp()` served HTTP 200
    within 0.33 s, but a command typed at the console was **not executed** while it ran
    (`W17/run2/e5b_output.txt`).
  - In the original runs I could not stop the app by sending SIGINT or a tty Ctrl+C (0x03)
    through my pty harness (`e5b`, `e5c`). **Fact-check re-runs disagree:** in 3/3 re-runs of
    `e5b`/`e5c`, `p$interrupt()` (SIGINT) stopped `runApp()` (the app no longer answered; in 2 of
    them the queued typed command then ran). Treat pty interrupt behaviour as timing-dependent
    (UNCERTAIN); in IDEs the Stop button / Esc works, as documented by shiny.
- **C, VERIFIED** (`W17/run2/e5_output.txt`):
  ```
  == Q3 shiny INTERNALS (NOT CRAN-acceptable): shiny:::startApp without the runApp loop ==
  [1] "WebServer" "Server"    "R6"
  GET /           -> HTTP 200 after 0.04s: <!DOCTYPE html>
  browser: output 't' after 3 s with idle console: ''
  browser: output 't' after one manual shiny:::serviceApp(): 'rows in live object: 10'
  ```
  `serviceApp()` is `timerCallbacks$executeElapsed(); flushReact(); flushPendingSessions(); ...
  service(timeout); flushReact(); flushPendingSessions()` (printed from the shiny namespace). The
  reactive flush lives there, so the internals route would also need a `later`-driven pump of
  internal functions.
  CRAN policy: "CRAN packages should use only the public API... `:::` should not be used to access
  undocumented/internal objects in base packages". `R CMD check` also reports `:::` use
  (VERIFIED in `tools:::format.check_packages_used`: "Unexported objects imported by ':::' calls:"
  and "There are ::: calls to the package's namespace in its code").
  **Version note (fact-check):** this Q3 experiment is specific to shiny 1.13.0. In shiny 1.14.0
  `startApp` is the exported non-blocking API with a different signature
  (`startApp(appDir, port, launch.browser, host, ...)`), so the `shiny:::startApp(appobj, port,
  host, quiet)` call in §5.5 no longer means the same thing.
- **D, VERIFIED** (`W17/run2/e5_output.txt`, real interactive R in a pty, `interactive: TRUE`):
  ```
  idle console    -> HTTP 200 after 0.02s: live object: nrow(big)=100000 mean=-0.0014
  after user edit -> HTTP 200 after 0.03s: live object: nrow(big)=10 mean=-0.1202
  busy console    -> FAILED after 1.01s: Timeout was reached
  idle again      -> HTTP 200 after 0s: live object: nrow(big)=10 mean=-0.1202
  ```
  - httpuv runs I/O on a background thread and dispatches R handlers through `later`. The later
    docs say "scheduled operations only run when there is no other R code present on the execution
    stack; i.e., when R is sitting at the top-level prompt" (https://later.r-lib.org/reference/later.html).
  - Static files registered with `staticPaths` are served entirely on the background thread
    (VERIFIED indirectly: E9b served HTML to chromote from the same R process while R was blocked
    inside chromote's `wait_for`; also stated in the httpuv `startServer` Rd: files served this way
    use C++ code and "will not be blocked when R code is executing").
  - Windows Rterm behaviour of later's idle callbacks: UNCERTAIN; I found no docs.
- **E, VERIFIED** (`W17/run2/e6_output.txt`, 183.1 MB data frame, 2e6 rows):
  ```
  fork: HTTP 200 after 0.76 s; page says: rows (shared by fork): 2000000
  callr: saveRDS 1.27 s (console blocked), HTTP 200 after 6.06 s total; page says: rows (shipped): 2000000
  ```
  Caveats:
  - VERIFIED (`parallel` Rd `unix/mcfork.Rd`): the docs warn against using `mcparallel`/`mclapply`
    "in GUI or embedded environments" (several processes sharing one GUI "will likely cause
    chaos"); "some precautions" make it usable in R.app on macOS, and third-party front ends
    (RStudio, Positron) should be treated as unsafe.
  - macOS fork safety with Objective-C/Quartz is a known hazard.
  - Not available on Windows.
  - The snapshot is point-in-time. Kill with `tools::pskill()` + `parallel::mccollect(wait = FALSE)`
    (VERIFIED: child gone).
- **F, VERIFIED signature / LIKELY semantics.**
  - Signature: `jobRunScript(path, name = NULL, encoding = "unknown", workingDir = NULL,
    importEnv = FALSE, exportEnv = "")`; "importEnv: Whether to import the global environment into
    the job" (https://rstudio.github.io/rstudioapi/reference/jobRunScript.html).
  - It copies the whole global environment (a 5 GB Seurat object gets serialised) and exists only
    in RStudio.
  - Positron provides rstudioapi *shims*: "Since Positron does not provide a full implementation of
    all RStudio API methods, use `rstudioapi::hasFun()`..."
    (https://positron.posit.co/migrate-rstudio-settings-and-extensions.html, VERIFIED fetch).
    Whether `jobRunScript` is shimmed is UNCERTAIN.
  - The callr path is universal, so do not use jobs.
- **G, VERIFIED by the fact-check** (shiny 1.14.0 from CRAN in a scratch library;
  `verify-17/v10_startapp114.R`, `v11_rng114.R`, `v15_selfget.R`, interactive R in a pty):
  - Rd `startApp.Rd`: "Starts a Shiny application in non-blocking mode, returning a
    `ShinyAppHandle` immediately... The `later` event loop services the app, so the R console
    remains available". Stop it with `handle$stop()` (not `stopApp()`). "If another Shiny app is
    already running in this session when `startApp()` is called, the running app is stopped".
  - Observed:
    ```
    startApp returned to prompt after 0.05 s: STATUS running http://127.0.0.1:18134
    browser output 't' (idle console): 'rows in live object: 100000'
    console command ran while app is up: TRUE
    browser output 't' after live edit (new session): 'rows in live object: 10'
    GET / while console busy -> FAILED after 1.5s: Timeout was reached
    second startApp: H1 success H2 running        # the first app was stopped
    synchronous GET from the same R process: Timeout was reached (2.0s)
    async GET (curl multi interleaved with later::run_now): 200
    ```
  - With `port = NULL`, `startApp()` left the user's `.Random.seed` unchanged (shiny's private-seed
    port picker).
  - Consequences for gptr: it gives **live** objects (no snapshot), but it loads shiny into the
    user's session, runs model code in the user's process, allows one artifact at a time, stalls
    while the agent or user runs R code, and gptr's own readiness polling or session check must be
    asynchronous (curl multi + `later`), or it deadlocks. Keep the callr child as the default; G is
    an optional "live mode" gated on `packageVersion("shiny") >= "1.14.0"`.

**Viewer / browser (display only).**
- `rstudioapi::viewer()`: "Content can be served from static files in the R session temporary
  directory, or via a web application running on localhost". Recommended package pattern:
  `viewer <- getOption("viewer", default = utils::browseURL); viewer(url)`
  (https://rstudio.github.io/rstudioapi/reference/viewer.html, VERIFIED).
- Positron "shims the RStudio viewer pane", and Shiny apps open in its Viewer (search-result quote
  of Positron docs; LIKELY).
- RStudio Server/Workbench: `rstudioapi::translateLocalUrl(url, absolute = FALSE)` "Translates a
  local URL into an externally accessible URL on RStudio Server... Returns an unmodified URL on
  RStudio Desktop" (installed Rd, VERIFIED). The viewer does this automatically. For
  `browseURL`/links on Server, translate first.
- Terminal R: `utils::browseURL(url)` opens the system browser.
- Jupyter (IRkernel): display `<iframe src=url>` via IRdisplay. This works only when the notebook's
  browser can reach the kernel host's 127.0.0.1. Remote JupyterHub needs `jupyter-server-proxy`
  (`/proxy/<port>/`). UNCERTAIN (not testable here: jupyter not installed).

**Startup latency breakdown (VERIFIED, `W17/run2/proto2_output.txt`; quieter machine):**
```
callr::r(function() NULL)         : 0.311 0.246 0.16
  + library(shiny)                : 0.253 0.362 0.39
  + library(shiny); library(bslib): 0.403 0.268 0.273
  + shiny, bslib, ggplot2         : 0.903 1.522 1.1
  + shiny, bslib, plotly, DT      : 0.804 0.745 0.763
processx::run(Rscript --vanilla -e NULL): 0.115
minimal_shiny        artifact() wall time to HTTP 200 (3 runs): 0.45 0.41 0.39  (html 1923 bytes)
bslib_sidebar        artifact() wall time to HTTP 200 (3 runs): 0.65 0.64 0.65  (html 4436 bytes)
bslib_custom_theme   artifact() wall time to HTTP 200 (3 runs): 1.77 1.14 1.16  (html 4449 bytes)
plotly_dt            artifact() wall time to HTTP 200 (3 runs): 1.12 0.94 0.94  (html 5509 bytes)
```

Under heavy load (other agents; `vm.loadavg` 14.7–19) the interleaved old-vs-new launcher
comparison gave 1.35 s vs 1.25 s mean (`W17/run2/e1c_interleave.R`). `supervise = TRUE` adds
nothing measurable: spawn-to-child-start was 0.171 s vs 0.182 s (`W17/run2/e1b_timing.R`).

**Data shipping cost (VERIFIED, proto2 part C; data.frame of 2e6 rows, `object.size` 206 MB):**
```
saveRDS(compress=FALSE)      write 0.53s  read 0.97s  size 98.0 MB
saveRDS(default gzip)        write 4.65s  read 1.30s  size 40.5 MB
arrow::write_feather(lz4)    write 0.77s  read 0.04s  size 74.2 MB   (read is lazy ALTREP strings)
arrow::write_parquet         write 0.84s  read 0.04s  size 57.2 MB   (read is lazy ALTREP strings)
qs2::qs_save                 write 0.45s  read 0.76s  size 36.1 MB
callr::r(args = list(big)) round trip: 2.50s
```

Recommendation: use `saveRDS(compress = FALSE)` by default. It works for any R object, is
readable by webR/shinylive (LIKELY), and needs no dependency. qs2 is an opt-in accelerator (it is
not guaranteed to exist in webR). Enforce a size cap (`gptr.artifact.max_bytes`, default 1e9) and
tell the model to ship subsets or summaries (e.g., a UMAP coordinates + metadata data frame instead
of a whole Seurat object).

### 2.2 Q2 — Artifact lifecycle

**How the data reaches app.R (VERIFIED from shiny 1.13.0 source).** `shinyAppDir_appR` does:
```r
if (getOption("shiny.autoload.r", TRUE)) {
  sharedEnv <- new.env(parent = globalenv())
  loadSupport(appDir, renv = sharedEnv, globalrenv = NULL)
} else sharedEnv <- globalenv()
result <- sourceUTF8(fullpath, envir = new.env(parent = sharedEnv))
```
- For `app.R` apps, **`global.R` is not sourced** (`globalrenv = NULL`).
- `R/*.R` files are sourced (sorted) into `sharedEnv`, which is the parent of `app.R`'s
  environment. A generated `R/gptr_data.R` containing `sales <- readRDS("data/sales.rds")`
  therefore makes `sales` visible by name.
- Autoload is disabled by `options(shiny.autoload.r = FALSE)` or by a file
  `R/_disable_autoload.R`. The child runs with `user_profile = FALSE, system_profile = FALSE`, so
  user options cannot interfere.
- The layout is also a normal portable Shiny app directory: `shiny::runApp(".gptr/artifacts/<id>/v002")`
  works by hand, and shinylive bundles it.

**IDs (VERIFIED).**
- An ID is `<slug(title)>-<6 hex>`, where the hex comes from `basename(tempfile(""))`.
- `tempfile()` does not touch `.Random.seed`: "tempfile() touches RNG: FALSE"; "suffix: 8ff9c0 TRUE".
- The ID directory is claimed atomically with `dir.create()`, which returns FALSE if it already
  exists (E11: "first dir.create: TRUE second: FALSE"). The same trick locks version numbers when
  two sessions revise one artifact concurrently.

**Storage (final layout, VERIFIED in E12):**
```
.gptr/artifacts/<id>/artifact.json          metadata + version list (atomic tmp+rename writes)
.gptr/artifacts/<id>/v001/app.R             model-written code (UTF-8)
.gptr/artifacts/<id>/v001/R/gptr_data.R     generated loader
.gptr/artifacts/<id>/v001/data/<name>.rds   snapshot(s)
.gptr/artifacts/<id>/run/run.json           pid, create_time, port, url, version, parent_pid, started
.gptr/artifacts/<id>/run/port               port published by the child (atomic rename)
.gptr/artifacts/<id>/run/app-v001.log       child stdout+stderr
```
Runtime files are kept out of `vNNN/` because shinylive's `read_app_files()` bundles every
non-hidden file in the app dir (VERIFIED in source, §2.6). E12 checks "version dirs contain no
runtime files: TRUE".

**Versions.** Each revision creates `vNNN+1` with a fresh snapshot of `data` (so an updated live
object is picked up; E12 v2 showed the new `margin` column). `artifact.json$current` points at the
live one. Old versions stay for diff/rollback. A revision stops the old process and starts the new
one **on the same port** (stable URL):
```
v2 ok=TRUE url=http://127.0.0.1:34110/ (same as v1: TRUE) | HTTP 200 after 2.30s | old pid alive: FALSE
```
(`W17/run2/e12_output.txt`). E11 shows a re-bind of the same port 1.06 s after the stop, page `<h2>v2</h2>`.

**Alternative: in-place autoreload (VERIFIED with a caveat, E10).**
- The child ran with `options(shiny.autoreload = TRUE, shiny.autoreload.interval = 250)`,
  serving `<id>/live/`.
- An atomic `app.R` replacement reloaded the open browser tab in 0.2–0.4 s with **no process
  restart**. It also re-sourced `R/*.R`, which re-reads the data, because `loadSupport()` runs
  inside the `app.R`-keyed cache: "new session (Version A): nrow(d)=10".
- That succeeded in 4/4 runs with logging (`e10d_output.txt`, `e10d_rep1..3.txt`).
- However:
  - (a) Changing only `data/*.rds` or only `R/*.R` did **not** trigger a data refresh within
    10 s (`e10_output.txt`). `app.R` must be rewritten on every revision (stamp a header comment).
  - (b) One earlier run without logging (`e10c_output.txt`) showed the new UI with stale data.
    The cause is unexplained.
  - (c) shiny warns "Using legacy autoreload file watching. Please install watcher".
- **Conclusion:** keep restart-on-same-port as the robust default. Autoreload is an opt-in
  optimisation.

**Ports (VERIFIED).**
- `httpuv::randomPort` body: `valid_ports <- setdiff(seq.int(min, max), unsafe_ports); ...
  try_ports <- sample(valid_ports, n); for (port in try_ports) if (is_port_available(port, host)) return(port)`.
  `unsafe_ports` has 67 entries (includes 6000 and other browser-blocked ports).
- Calling it in the parent changes the user's random stream (proto2):
  ```
  runif after set.seed(42): 0.914806
  runif after set.seed(42) + randomPort(): 0.2712866  identical: FALSE
  two sessions with same seed choose port: 35053 35053
  ```
- shiny's own picker (when `port = NULL`) uses `p_randomInt(3000, 8000)` = `withPrivateSeed(...)`
  and skips 3659, 4045, 5060, 5061, 6000, 6566, 6665:6669, 6697 (deparsed `runApp`).
- Design: the **child** chooses the port. It tries the preferred port (the previous version's)
  with a test bind, otherwise `httpuv::randomPort(20000, 39999)`, then writes it to `run/port` via
  tmp + `file.rename`. The parent polls that file, then polls HTTP. There is no RNG side effect in
  the parent, and the child performs the only bind (a tiny test-bind race remains; handle it with
  a relaunch retry).

**Cleanup matrix (VERIFIED, `W17/run2/e2_output.txt`).** The parent is an Rscript that launches
an artifact and then (exit) falls off the end, (error) calls `stop()` at top level, or (kill)
receives SIGKILL:
```
 parent_end supervise watchdog child_alive_immediately child_alive_after_3s
       exit     FALSE    FALSE                   FALSE                FALSE
       exit     FALSE     TRUE                   FALSE                FALSE
       exit      TRUE    FALSE                   FALSE                FALSE
       exit      TRUE     TRUE                   FALSE                FALSE
      error     FALSE    FALSE                   FALSE                FALSE
      error     FALSE     TRUE                   FALSE                FALSE
      error      TRUE    FALSE                   FALSE                FALSE
      error      TRUE     TRUE                   FALSE                FALSE
       kill     FALSE    FALSE                    TRUE                 TRUE   <- orphan
       kill     FALSE     TRUE                    TRUE                FALSE
       kill      TRUE    FALSE                    TRUE                FALSE
       kill      TRUE     TRUE                    TRUE                FALSE
```
- processx docs: "'cleanup' Whether to kill the process when the 'process' object is garbage
  collected"; "'supervise' ... the supervisor will ensure that the process is killed when the R
  process exits"; `windows_detached_process = !cleanup` (installed Rd, VERIFIED).
- With `supervise = TRUE`, a `supervisor` process remains a child of the R session (E12:
  "remaining children of this R process: supervisor, Google Chrome").
- The whole E2 matrix was re-run by the fact-check with identical results (12/12 rows). processx
  3.9.0 (current CRAN, not tested here) adds `linux_pdeathsig`, a Linux-only extra safety net.
- Orphan sweep (E11): after a SIGKILLed parent with neither safety net, the orphan was alive.
  `art_sweep_orphans()` read `run/run.json`, saw the parent dead, checked the child's
  `ps_create_time` against the stored value (PID-reuse guard), and killed it: "art_sweep_orphans()
  killed: orphan-c8a674 | orphan alive now: FALSE".

**Stopping (VERIFIED).** `proc$interrupt()` (SIGINT on Unix; "On Windows, it is a CTRL+BREAK
keypress", processx Rd) makes `runApp()` return gracefully ("exit 0", "<interrupt: >" in the log,
**with callr 3.7.6**) in 0.06–0.40 s, and up to 1.05 s under load (`e12b_output.txt`,
`e12c_output.txt`). **Fact-check (VERIFIED, `verify-17/v17_interrupt.R`):** with current CRAN
callr 3.8.0 the same stop still ends the child in 0.08 s, but the exit status is **1** and the log
has no "<interrupt: >" line. gptr must not treat a non-zero exit after a requested stop as a crash. In E12 one
stop exceeded the 2 s grace and the `kill_tree()` fallback ended it (2.08 s). Use a 3 s grace,
then `kill_tree()`. After stop, "GET after stop -> Could not connect to server", the port is
re-bindable, and `run.json` is removed.

### 2.3 Q3 — Validating a generated app before showing it

Results on deliberately broken apps (`W17/run2/e3b_output.txt`; lib v2 + `art_session_check.R`):
```
Chrome cold start: 3.43 s
ok            launch ok, HTTP 200 in 2.29 s | session ok=TRUE  connected=TRUE  browser_start=0.31s total=2.10s
parse_error   REJECTED at stage: parse   message: <text>:4:1: unexpected symbol
missing_pkg   REJECTED at stage: static  message: package(s) not installed: notARealPkg
ui_error      REJECTED at stage: launch  message: process exited
              log tail: Error in eval(exprs, envir) : object 'no_such_data' not found
render_error  HTTP 200 | session ok=FALSE | output errors: p  'x' and 'y' lengths differ
              server log errors: Warning: Error in xy.coords: 'x' and 'y' lengths differ
              server log warnings: Warning in mean.default(sales$revnue) :
server_crash  HTTP 200 | session ok=FALSE connected=FALSE disconnected=TRUE
              server log errors: Warning: Error in undefined_helper: could not find function "undefined_helper"
validate_msg  HTTP 200 | session ok=TRUE | validation messages (not errors): t  Pick a region
js_error      HTTP 200 | session ok=FALSE | JS errors: ReferenceError: undefinedFn is not defined
```
Key facts:
- HTTP 200 alone passes the 3 broken apps that load (render_error, server_crash, js_error). The
  headless session check catches all 3 and correctly passes validate_msg.
- `validate(need())` messages carry class `shiny-output-error-validation`. They must not count as
  errors.
- A semantic bug (`mean(sales$revnue)` → NA with a warning) is only visible as a server-log
  warning or in the screenshot.
- Register the load-event promise **before** navigating. The first version raced and timed out
  with "Chromote: timed out waiting for event Page.loadEventFired".
- Reuse one `chromote::Chromote` per R session (cold start 3.4 s; later checks 1.1–2.1 s).
- chromote finds Chrome via `CHROMOTE_CHROME` env var, then per-OS lookup. On Windows the lookup
  is **only the registry key** `SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe`
  (VERIFIED `find_chrome_windows` body). Edge-only users must set `CHROMOTE_CHROME` to
  `msedge.exe` (chromote 0.5.1 also has `local_chrome_version()`/`with_chrome_version()`, which
  download a Chrome for Testing build; that is a network download, so it needs user consent).
- The screenshot comes straight out as base64 (`b$Page$captureScreenshot(format = "png")$data`),
  ready for an image content block. 1100×750 PNG is 24–43k base64 chars, about 1,080 Claude
  visual tokens.

`shiny::testServer()` (VERIFIED, `W17/run2/e4_output.txt`, run in a clean `callr::r` process on
the v2 dir):
```
 $ returned   : chr "NULL"                                   # testServer() returns NULL, not the expr value
 $ naive      : chr "ERROR: argument is of length zero"      # inputs are NULL in MockShinySession
 $ with_inputs: Named chr [1:3] "5,000" "5,472,587" "data:image/png;base64,"
 $ filtered   : chr "1,253"
```
`MockShinySession` keeps defined outputs in a private field (`outs`; public methods include
`getOutput`, `setInputs`, `flushReact`), so there is no public way to enumerate outputs. Output IDs
can be scraped from the served HTML: E12 regex result "output ids: n, rev, hist".

Optional alternatives (not needed): shinytest2 `AppDriver` (heavier; it launches its own R
process) and webshot2 `appshot()`. chromote alone is enough and is their common dependency.

### 2.4 Q4 — Building blocks for the system prompt

Verified signatures in bslib 0.10.0 (printed with `formals()`):
```
page_sidebar       ..., sidebar, title, fillable, fillable_mobile, theme, window_title, lang
page_navbar        ..., title, id, selected, sidebar, fillable, fillable_mobile, gap, padding, header, footer, navbar_options, fluid, theme, window_title, lang, position, bg, inverse, underline, collapsible
page_fillable      ..., padding, gap, fillable_mobile, title, theme, lang
sidebar            ..., width, position, open, id, title, bg, fg, class, max_height_mobile, gap, padding, fillable
card               ..., full_screen, height, max_height, min_height, fill, class, wrapper, id
card_header        ..., gap, class, container
value_box          title, value, ..., showcase, showcase_layout, full_screen, theme, height, max_height, min_height, fill, class, id, theme_color
layout_columns     ..., col_widths, row_heights, fill, fillable, gap, class, height, min_height, max_height
layout_column_wrap ..., width, fixed_width, heights_equal, fill, fillable, height, height_mobile, min_height, max_height, gap, class
nav_panel          title, ..., value, icon
bs_theme           version, preset, ..., brand, bg, fg, primary, secondary, success, info, warning, danger, base_font, code_font, heading_font, font_scale, bootswatch
input_dark_mode    ..., id, mode
builtin presets: shiny ; bootswatch: cerulean, cosmo, ..., zephyr (25)
```
(Re-printed by the fact-check: identical. Current CRAN bslib 0.12.0 differs: `sidebar()` gained
`resizable` in 0.11.0. The additions are backwards-compatible with the house style below.)
- shiny 1.13.0 **Imports bslib (>= 0.6.0)** (packageDescription), so bslib is always present when
  shiny is.
- Posit's official agent skill `posit-dev/skills/shiny/shiny-bslib/SKILL.md`
  (https://github.com/posit-dev/skills/blob/main/shiny/shiny-bslib/SKILL.md, VERIFIED by a second
  fetch during the fact-check) says:
  - Prefer `page_sidebar()` / `page_navbar()` / `page_fillable()` / `page_fluid()`.
  - Use `layout_column_wrap()` / `layout_columns()` "instead of fluidRow()/column()".
  - Use `card(full_screen = TRUE)`, `navset_card_underline()`, and bsicons for icons.
  - Avoid nesting `card()` inside `card()` and never nest `page_*()`.
  - It also mentions `thematic::thematic_shiny()`.
- Theming with Sass costs time: a custom `bs_theme()` added 0.5–1.1 s startup (proto2). The house
  style should therefore avoid themes unless asked.
- Installed widget packages vary by machine. Here plotly and DT are in the user library, while
  reactable, leaflet and bsicons are not (only in my private library). The static check flags
  `library(notInstalled)` and `pkg::` usages. The system prompt must list what is installed.

### 2.5 Q5 — HTML fallback and static artifacts (VERIFIED, `W17/run2/e7_output.txt`)

```
A) iframe srcdoc wrapper: ok = TRUE  startup 1.73 s
   session ok: TRUE  JS errors: 0  bars drawn inside iframe: 4
B) static file:// artifact: bars drawn = 4  size = 801 bytes
C) httpuv::startServer(staticPaths) in-process: HTTP 200  bytes 801
D) saveWidget selfcontained=TRUE (pandoc 3.11): 3.8 MB in 0.46 s; selfcontained=FALSE: 2.5 KB + lib/ 4.4 MB
```
- **A** is the recommended fallback. gptr saves the model's HTML as `page.html` and generates:
  ```r
  library(shiny)
  html <- paste(readLines("page.html", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  data_json <- jsonlite::toJSON(mget(c("sales"), inherits = TRUE), dataframe = "columns", auto_unbox = FALSE, digits = NA)
  html <- sub("<head>", paste0("<head><script>window.GPTR_DATA = ", data_json, ";</script>"), html, fixed = TRUE)
  ui <- fluidPage(style = "padding:0", tags$iframe(srcdoc = html, style = "border:0;width:100%;height:95vh"))
  server <- function(input, output, session) {}
  shinyApp(ui, server)
  ```
  `mget(..., inherits = TRUE)` finds the snapshot objects defined by `R/gptr_data.R`. `srcdoc`
  isolates the model's CSS/JS from Bootstrap. The same validation ladder and screenshot apply.
- **B**: a single self-contained HTML file with the data inlined. It needs no server and works
  from `file://`. RStudio's viewer only shows files under `tempdir()`, so copy the file there
  before calling `viewer()` (docs quote in §2.1).
- **C**: an in-process static server (public API, no child). It only answers while the console is
  idle.
- **D**: `htmlwidgets::saveWidget(selfcontained = TRUE)` calls `pandoc_self_contained_html()`
  (VERIFIED by deparsing `saveWidget`). Without pandoc, use `selfcontained = FALSE, libdir = "lib"`.
  `rmarkdown::render()` also needs pandoc. Quarto needs the CLI (not installed here).

### 2.6 Q6 — Sharing: shinylive and Quarto dashboards

- CRAN shinylive **0.5.0, published 2026-06-08**. Imports: archive, brio, cli, fs, gh, glue,
  httr2 (≥ 1.0.0), jsonlite, lifecycle, pkgdepends, rappdirs, renv, rlang (≥ 1.1.0), tools,
  whisker, withr (https://cran.r-project.org/web/packages/shinylive/index.html, VERIFIED via fetch).
- NEWS: 0.5.0 uses default assets v0.10.12 with webR v0.6.0; 0.4.0 uses assets v0.10.8; 0.3.0
  uses assets v0.9.1 and introduced `SHINYLIVE_WASM_PACKAGES`
  (https://cran.r-project.org/web/packages/shinylive/news/news.html, VERIFIED by the fact-check
  from the raw NEWS page). 0.4.0 also made `export(verbose =)` emit a deprecation warning (use
  `quiet`), and 0.4.1 added a guard so `assets_cache_dir()` errors during CRAN testing.
- The local 0.3.0 reports `assets_version()` 0.9.1 (VERIFIED).
- Signature (0.3.0, VERIFIED): `export(appdir, destdir, ..., subdir = "", quiet = ..., wasm_packages = NULL,
  package_cache = TRUE, max_filesize = NULL, assets_version = NULL, template_dir = NULL,
  template_params = list(), verbose = NULL)`. `max_filesize` defaults to "100M". The docs example
  serves the result with `httpuv::runStaticServer(out_dir)`.
- **Bundling (VERIFIED, `shinylive:::read_app_files` source):**
  - It recursively reads every file in `appdir` via `dir()`, which excludes hidden files.
  - Excluded directory names: `__pycache__`, `venv`, `.venv`, `rsconnect`.
  - Files are read as text or, failing that, raw binary.
  - So `app.R`, `R/gptr_data.R` and `data/*.rds` are bundled. Logs would be too, which is why
    runtime files live in `<id>/run/`.
- Packages must exist as WebAssembly binaries ("It is not possible to install packages from source
  in webR"; availability at https://repo.r-wasm.org/, https://posit-dev.github.io/r-shinylive/).
  One CRAN-side search summary says "18094 packages are built for wasm, with 10379 also having
  their dependencies available" (UNCERTAIN; secondary source).
- **Not executed:** the export cache `~/Library/Caches/shinylive` is empty, and `export()` would
  download the asset bundle from GitHub. I did not download it.
- Design: `artifact_export(id, dest, format = "shinylive")` is gated by `requireNamespace("shinylive")`
  and an interactive confirmation that a download will happen. Warn that data is shipped to
  whoever receives the site.
- Quarto dashboards (Quarto ≥ 1.4) are either static (`format: dashboard`) or interactive
  (`server: shiny`, with `#| context: setup` / `#| context: server` chunks, run by `quarto serve`)
  (https://quarto.org/docs/dashboards/, https://quarto.org/docs/dashboards/interactivity/shiny-r.html).
  They need the Quarto CLI, so they are an optional export format, not the core artifact.

### 2.7 Q7 — shinychat as a gptr front end

- Local shinychat 0.3.0 exports `chat_app, chat_append, chat_append_message, chat_clear, chat_mod_server,
  chat_mod_ui, chat_restore, chat_ui, contents_shinychat, markdown_stream, output_markdown_stream,
  update_chat_user_input`.
- It **Imports**: base64enc, bslib, cli, coro, **ellmer (>= 0.3.0)**, fastmap, htmltools, jsonlite,
  lifecycle, promises (>= 1.3.2), rlang (>= 1.1.0), S7, shiny (>= 1.10.0) (VERIFIED).
- `chat_append()`: "The 'response' can be a string, string generator, string promise, or string
  promise generator (as returned by the 'ellmer' package's 'chat', 'stream', 'chat_async', and
  'stream_async' methods)" (installed Rd, VERIFIED). gptr's own provider layer could feed a coro
  generator, so ellmer is not needed at runtime, although installing shinychat pulls ellmer in.
- The current CRAN release is shinychat **0.5.0, published 2026-09-09** (CORRECTED by the
  fact-check; the earlier "2026-09-15" came from the pkgdown site), which adds `page_chat()`
  (VERIFIED in the CRAN NEWS). 0.5.0 still **Imports ellmer (>= 0.4.1)**, plus bslib (>= 0.12.0)
  and R6 (https://cran.r-project.org/web/packages/shinychat/index.html).
- Feasibility:
  - A Shiny UI running **in-process** (`runGadget`) blocks the console but keeps the live objects,
    so the agent can eval in `globalenv()`. With shiny ≥ 1.14.0, `startApp()` keeps the live
    objects without blocking (§2.1 G), but the app stalls whenever R is busy, which includes every
    tool call the agent runs.
  - A UI in a **background process** loses the live objects, defeating gptr's core benefit (REQ-21/22).
  - Streaming plus tool execution inside Shiny's reactive loop needs promises/async in gptr's
    agent loop.
  - **Verdict: not in v1.** Keep the console (REQ-16) as the UI. Revisit an optional blocking
    `gptr_app()` gadget (Suggests: shinychat) after the agent loop is stable.

### 2.8 Q8 — Static plots for vision models (VERIFIED, `W17/run2/e8_output.txt`)

```
default png() type on this platform: quartz
      device        px res  secs  bytes b64_chars claude_tok claude47_tok gpt5_tok
 png_default   800x600  96 1.319 175223    233632        638          638      570
    ragg_png   800x600  96 0.509 135697    180932        638          638      570
    ragg_png  1000x700 120 0.220 184511    246016        900          900      845
    ragg_png 1400x1000 144 0.431 311604    415472       1518         1800     1690
    ragg_png 2000x1500 200 0.380 565853    754472       1564         3888     3554
   ragg_jpeg  1000x700 120 0.251 152451    203268        900          900      845
     svglite  1000x700 120 0.305 754455   1005940         NA           NA       NA
SVG as TEXT would cost 321047 o200k tokens (5000 points)
```
- My Claude estimator reproduces Anthropic's documented table exactly (2000×1500 → 1564 standard
  / 3888 high-res).
- The `gpt5_tok` column ignores OpenAI's resize budget: 2000×1500 is 2,961 patches, above the
  2,500-patch `high` budget, so with `detail = "high"` it would be downscaled to at most about
  3,000 tokens (2,500 × 1.2), not 3,554 (fact-check note; UNCERTAIN which budget `auto` uses).
  The table was re-run by the fact-check: identical bytes and token counts; timings vary with load.
- Tokens depend on pixel dimensions, not bytes, so JPEG saves bytes but not tokens. Prefer PNG for
  crisp text.
- The 1000×700 @ 120 dpi PNG is fully legible (inspected: title, axes, legend, 5,000 points).
  Default: `width = 1000, height = 700, res = 120`.
- Replay (`W17/run2/e8b_output.txt`):
  ```
  display list enabled=FALSE -> 3715 bytes, non-white pixel share 0.000      # blank!
  display list enabled=TRUE -> 100969 bytes, non-white pixel share 0.066
  evaluate::evaluate() captured recordedplot -> 95038 bytes, non-white share 0.062
  ```
  Screen devices enable the display list by default. Off-screen capture devices need
  `dev.control(displaylist = "enable")`.
- Rendering a ggplot object into `ragg::agg_png()` + `print()` + `dev.off()` leaves the user's
  device list unchanged ("user device list unchanged: TRUE").
- Anthropic block format (VERIFIED, printed):
  `{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo..."}}`.

### 2.9 Q9 — Is Shiny more token-efficient than HTML/JS? How well do models write Shiny?

**Token measurement (VERIFIED, `W17/run2/e9_output.txt`, rtiktoken o200k_base and cl100k_base):**
```
                file lines chars o200k cl100k
    1_hist_html.html    28   826   268    256
      1_hist_shiny.R     9   251    77     77
     2_sales_bslib.R    21   790   220    219
   2_sales_html.html    51  2341   686    662
 3_scatter_html.html    64  2950   935    913
   3_scatter_shiny.R    27   813   251    251
 1  shiny   77 tok | html  268 tok | html/shiny = 3.48x
 2  shiny  220 tok | html  686 tok | html/shiny = 3.12x
 3  shiny  251 tok | html  935 tok | html/shiny = 3.73x
Inlining the 5000-row 'sales' data frame as JSON rows: 372287 chars, 127113 o200k tokens (Shiny references it by name: 1 token)
```

**Functional equivalence (VERIFIED, `W17/run2/e9b_output.txt`).** All six apps run: the Shiny ones
through the artifact pipeline + session check, and the HTML ones in headless Chrome with CDN URLs
replaced by local copies from installed R packages (no network) plus DOM assertions:
```
1_hist_shiny.R       launch 1.76s | session ok=TRUE | output errors=0 | js errors=0 | log errors=0
2_sales_bslib.R      launch 3.96s | session ok=TRUE | output errors=0 | js errors=0 | log errors=0
3_scatter_shiny.R    launch 3.35s | session ok=TRUE | output errors=0 | js errors=0 | log errors=0
1_hist_html.html     functional check=TRUE | js errors=0
2_sales_html.html    functional check=TRUE | js errors=0
3_scatter_html.html  functional check=TRUE | js errors=0
```
Why HTML costs more:
- It needs explicit DOM markup, CDN tags, event wiring, and state updates.
- It re-implements statistics in JS (normal RNG, OLS fit, histogram data).
- It cannot reference R objects, so data must be inlined or fetched from an exported JSON file.

Caveats: n = 3; I wrote both versions (author bias toward concise code on both sides); o200k is
OpenAI's tokenizer (Claude's tokenizer is not public; relative ratios are LIKELY similar); the
count excludes the cost of fix-up iterations.

**Model quality (LIKELY):**
- Posit's R benchmark `are` has "29 rows and 7 columns" (https://vitals.tidyverse.org/reference/are.html).
- Posit's third evaluation post reports Claude Opus 4.5 at 70.1%, Claude Sonnet 4.5 66.7%, GPT-5
  66.7%, Claude Opus 4.1 64.4%, and Gemini 3 64.4%, with no Shiny-specific breakdown
  (https://posit.co/blog/r-llm-evaluation-03; scores re-confirmed by the fact-check; the page
  date was garbled in both fetches, so whether this is the *latest* post is UNCERTAIN).
- Posit's Shiny Assistant blog (2025-02-13) shows one runtime error ("arguments imply differing
  number of rows: 202, 200") fixed on the second attempt, and says "the work was not complete"
  (https://posit.co/blog/ai-powered-shiny-app-prototyping).
- The existence of Posit's `shiny-bslib` skill suggests models need steering toward modern bslib
  idioms.
- No dedicated Shiny generation benchmark was found (searches in §8).
- Implication: design for a validate → screenshot → edit loop, 1–3 iterations.

---

## 3. Exact specifications

### 3.1 Files (verbatim examples from runs)

`artifact.json` (`W17/run2/proj_e12/.gptr/artifacts/sales-explorer-35fc46/artifact.json`):
```json
{
  "schema": 1,
  "id": "sales-explorer-35fc46",
  "title": "Sales explorer",
  "created": "2026-09-29T19:05:58.137-0700",
  "versions": [
    { "version": 1, "created": "2026-09-29T19:05:58.183-0700",
      "data": [ { "name": "sales", "class": "data.frame", "dim": [5000, 5], "bytes": 183009 } ],
      "packages": ["shiny", "bslib"] },
    { "version": 2, "created": "2026-09-29T19:06:05.880-0700",
      "data": [ { "name": "sales", "class": "data.frame", "dim": [5000, 6], "bytes": 223031 } ],
      "packages": ["shiny", "bslib"] }
  ],
  "current": 2,
  "updated": "2026-09-29T19:06:05.880-0700",
  "last_port": 34110
}
```
Recommended additions for the real package: `code_sha256` per version (the prior prototype
computed it with `openssl::sha256`, but `digest`/`tools::md5sum` avoids the openssl dependency),
`kind` ("shiny" | "html"), `note` (the model's change summary), and `checks` (the last validation
result).

`run/run.json` (live while running; deleted on stop):
```json
{
  "pid": 25836,
  "create_time": 1790734108.76201,
  "port": 33971,
  "url": "http://127.0.0.1:33971/",
  "version": 1,
  "parent_pid": 25806,
  "started": "2026-09-29T19:08:30.116-0700"
}
```
`vNNN/R/gptr_data.R` (generated):
```r
# Generated by gptr: data snapshot for this artifact version.
sales <- readRDS("data/sales.rds")
```
Child log `run/app-v002.log` (shiny 1.13.0, `quiet = FALSE`):
```
Loading required package: shiny

Attaching package: 'bslib'

The following object is masked from 'package:utils':

    page


Listening on http://127.0.0.1:34110
```
Render errors are logged as `Warning: Error in <fn>: <msg>` (plus a stack trace), and server
crashes as `Warning: Error in ...` followed by `Error in <call> :`.

### 3.2 Model-facing tool definition (recommended)

```json
{
  "name": "artifact",
  "description": "Create or revise an interactive Shiny app (an artifact) that the user sees in their viewer or browser. The app runs in a separate R process. Objects named in `data` are copied (snapshotted) from the user's live R session and exist in app.R under the same names. Write ONE app.R that ends with shinyApp(ui, server). The result reports the URL, validation errors, and a screenshot of the running app.",
  "input_schema": {
    "type": "object",
    "properties": {
      "title":  {"type": "string", "description": "Short human-readable title (new artifacts)."},
      "code":   {"type": "string", "description": "Complete app.R source. Required for a new artifact; for a revision either `code` or `edits`."},
      "edits":  {"type": "array", "description": "Revisions only: exact-match replacements applied to the current app.R.",
                 "items": {"type": "object", "properties": {"old_text": {"type": "string"}, "new_text": {"type": "string"}},
                           "required": ["old_text", "new_text"]}},
      "data":   {"type": "array", "items": {"type": "string"}, "description": "Names of objects in the user's R session to ship into the app (small data frames or summaries, not huge objects)."},
      "id":     {"type": "string", "description": "Existing artifact id to revise. Omit to create a new artifact."},
      "kind":   {"type": "string", "enum": ["shiny", "html"], "default": "shiny", "description": "Use 'html' only when a raw HTML/JS page is truly required; the data is then available as window.GPTR_DATA.<name> (column-oriented JSON)."},
      "screenshot": {"type": "boolean", "default": true}
    },
    "required": []
  }
}
```
Tool result on success: a text block (JSON) plus an image block.
```json
{"ok": true, "id": "sales-explorer-35fc46", "version": 2, "url": "http://127.0.0.1:34110/",
 "startup_secs": 2.3, "outputs": ["n", "rev", "m", "hist"],
 "data": [{"name": "sales", "class": "data.frame", "dim": [5000, 6]}],
 "checks": {"static": "ok", "launch": "ok", "http": 200,
            "session": {"connected": true, "output_errors": [], "validation": [], "js_errors": [],
                        "log_errors": [], "log_warnings": []}}}
```
plus `{"type":"image","source":{"type":"base64","media_type":"image/png","data":"<screenshot>"}}`
(Anthropic shape; each provider adapter maps it).

On failure, `{"ok": false, "stage": "parse"|"static"|"launch"|"session", "error": "...",
"log_tail": ["..."], "output_errors": [...]}` plus the screenshot when the page loaded. Keep
`log_tail` to at most 30 lines.

### 3.3 Image token formulas (for plot/screenshot defaults)

- **Anthropic** (https://platform.claude.com/docs/en/build-with-claude/vision, VERIFIED fetch):
  - "Each patch is a 28×28-pixel block... An image, therefore, costs `⌈width / 28⌉ × ⌈height / 28⌉`
    visual tokens."
  - Tiers: "High-resolution | Claude 4.7 and later models | 2576 px | 4784"; "Standard | All other
    models | 1568 px | 1568". Larger images are downscaled.
  - Limits: max 8000×8000 px; "10 MB (base64-encoded) when using the Claude API directly"; "5 MB
    (base64-encoded) on Amazon Bedrock and Google Cloud"; more than 20 images per request → keep
    each at or below 2000 px; 100 images per request (200k-context models) or 600 (others);
    32 MB request limit. Formats: JPEG, PNG, GIF, WebP.
- **OpenAI** (https://developers.openai.com/api/docs/guides/images-vision, LIKELY via fetch
  summary):
  - Patch-based `patch_count = ceil(width/32)×ceil(height/32)` with multiplier 1.2× for the GPT-5.x
    family (gpt-5.2, 5.4, 5.5, 5.6 variants; the page also lists `gpt-6-astra`; 1.62× for
    gpt-4.1-mini). More than 30,000 patches is rejected.
  - `detail`: `low`, `high` (2,500-patch budget, 2048 px for 5.4/5.5/5.6), `original` (10,000
    patches, 6000 px for 5.4/5.5), `auto`.
  - Tile-based (base tokens + tile tokens per 512-px tile, after fitting 2048² and scaling the
    shortest side to 768): **85 + 170 for gpt-4o / gpt-4.1, 70 + 140 for gpt-5.1**, 2833 + 5667 for
    gpt-4o-mini (CORRECTED by the fact-check; the report previously gave 85/170 for gpt-5.1 too).
- **Gemini** (https://ai.google.dev/gemini-api/docs/image-understanding and /media-resolution,
  LIKELY via fetch):
  - "258 tokens if both dimensions <= 384 pixels. Larger images are tiled into 768x768 pixel tiles,
    each costing 258 tokens."
  - Gemini 3 `media_resolution`: low 280, medium 560, high 1120, ultra_high 2240, and unspecified
    (default) 1120.
  - Inline request total 20 MB.
- **Pi's normalisation defaults** (reference): max 2000×2000 px, 4.5 MB base64, JPEG quality 80
  (`pi/packages/coding-agent/src/utils/image-resize-core.ts:4-29`, VERIFIED).

### 3.4 Constants used by the reference implementation

| Constant | Value | Why |
|---|---|---|
| host | `127.0.0.1` | never expose on the LAN; no Windows firewall prompt (LIKELY) |
| child port range | 20000–39999 via `httpuv::randomPort` (skips 67 browser-unsafe ports) | avoids shiny's 3000–8000 range used by users' own apps |
| poll interval | 50 ms; curl `connecttimeout_ms = 250`, `timeout_ms = 3000` | fast detection |
| launch timeout | 30 s | ggplot2 + plotly + Sass can take several seconds under load |
| stop grace | 3 s (SIGINT/CTRL+BREAK) then `kill_tree()` | graceful exit measured 0.06–1.05 s |
| watchdog interval | 1 s (`later::later`) | parent-death detection |
| max snapshot | `getOption("gptr.artifact.max_bytes", 1e9)` via `utils::object.size` | block pathological copies |
| screenshot | 1100×750 PNG | about 1,080 Claude tokens |
| plot image | 1000×700, res 120, PNG via ragg | about 900 Claude / 845 GPT-5.x tokens |
| session-check idle criterion | connected, no `shiny-busy`, 0 `.recalculating`, stable for 5×100 ms; timeout 20 s | |

### 3.5 CRAN Repository Policy text that applies (https://cran.r-project.org/web/packages/policies.html, VERIFIED fetch)

- "Packages should not write in the user's home filespace (including clipboards), nor anywhere
  else on the file system apart from the R session's temporary directory ... Limited exceptions may
  be allowed in interactive sessions if the package obtains confirmation from the user."
- "packages may store user-specific data, configuration and cache files in their respective user
  directories obtained from `tools::R_user_dir()`, provided that by default sizes are kept as
  small as possible and the contents are actively managed (including removing outdated
  material)" (R ≥ 4.0). The proviso matters for data snapshots: prune old versions.
- "Packages should not start external software (such as PDF viewers or browsers) during examples
  or tests unless that specific instance of the software is explicitly closed afterwards."
- "If running a package uses multiple threads/cores it must never use more than two
  simultaneously".
- "CRAN packages should use only the public API."
- "Packages should not modify the global environment (user's workspace)."
- "Packages which use Internet resources should fail gracefully with an informative message".

---

## 4. Recommended design for gptr

### 4.1 User-facing R API

```r
artifact(code = NULL, title = NULL, data = character(), id = NULL, edits = NULL,
         kind = c("shiny", "html"), envir = parent.frame(),
         launch = interactive(), view = launch, check = c("session", "http", "none"),
         root = artifact_dir(), timeout = 30)
#> returns an S3 "gptr_artifact" list: ok, id, version, dir, url, port, pid, startup_secs,
#>   checks (list), screenshot (base64 or NULL); print() shows a one-line summary + URL

artifacts(root = artifact_dir(), running = FALSE)          # data.frame: id, title, versions, current, status, url, updated
artifact_open(id, version = NULL, view = TRUE, root = artifact_dir())   # (re)launch + show
artifact_stop(id = NULL, root = artifact_dir())            # NULL = stop all this session started
artifact_screenshot(id, file = NULL, width = 1100, height = 750)        # needs chromote
artifact_export(id, dest, format = c("app", "shinylive", "html"), version = NULL)
artifact_delete(id, root = artifact_dir())                 # asks for confirmation when interactive
artifact_dir()                                             # "<workspace>/.gptr/artifacts" or file.path(tempdir(), "gptr-artifacts")
plot_image(x = NULL, width = 1000, height = 700, res = 120, format = c("png", "jpeg"))
#> x = ggplot object | recordedplot | NULL (last plot captured by the R tool);
#> returns list(type = "image", media_type =, data = <base64>, width, height)
```

NSE (REQ-19): `artifact(data = c(sales, cars))` can accept bare names via
`rlang::enexprs`/`substitute`. The tool path always passes character.

### 4.2 Internal functions (map to `W17/run2/artifact_lib3.R`)

| gptr internal | lib3 prototype | Notes |
|---|---|---|
| `art_static_check(code)` | same | parse, getParseData, installed pkgs, forbidden calls, last expr `shinyApp()` |
| `art_snapshot(vdir, data, envir, max_bytes)` | same | saveRDS(compress = FALSE); writes `R/gptr_data.R` |
| `art_child_main(app_dir, port_file, preferred_port, parent_pid)` | same | runs in the child; watchdog; picks the port; `runApp()` |
| `art_start(id, version, ...)` | `artifact_start` | `callr::r_bg(..., supervise = TRUE, cleanup = TRUE, cleanup_tree = TRUE, stdout = log, stderr = "2>&1")` |
| `art_wait(proc, port_file, timeout)` | same | port-file then HTTP polling; returns html |
| `art_session_check(url, log, browser)` | `art_session_check.R` | chromote; reuse one `Chromote` per session |
| `art_sweep_orphans(root)` | same | run lazily on the first `artifact()`/`artifacts()` call of a session. (CORRECTED by the fact-check: the earlier `.onLoad` → `later::later()` plan needs `later` in Imports, which §4.5 does not list, and killing processes as a side effect of loading the package is surprising.) |
| `art_view(url)` | inline | `getOption("viewer", utils::browseURL)`; translateLocalUrl on RStudio Server |

In the package, pass the child entry to callr with **`package = "gptr"`** (callr Rd: "'pkg': set
the environment to the 'pkg' package namespace", VERIFIED). The child can then call gptr internals
without `:::`, which triggers an R CMD check NOTE even for one's own package (VERIFIED message
text in `tools`: "There are ::: calls to the package's namespace in its code"). callr 3.8.0
still documents `'pkg'` for `package` (its new default is `NULL`). Under
`devtools::load_all()` (package not installed), fall back to a self-contained anonymous function
(LIKELY issue).

### 4.3 Algorithms

**artifact() (create or revise):**
1. Resolve `code`: if `edits`, apply exact-match replacements (reuse the gptr edit engine,
   REQ-06) to the current version's `app.R`, and fail with the not-found `old_text` if one does not
   match.
2. If `kind = "html"`, save `page.html` and generate the iframe wrapper `app.R` (§2.5 A).
3. `art_static_check()`; on failure return `ok = FALSE, stage = "parse" | "static"`.
4. Claim the ID dir (new) or the next `vNNN` via `dir.create()` (the lock).
5. Write `app.R` (UTF-8; `writeLines(enc2utf8(code), useBytes = TRUE)`).
6. Snapshot `data`: check `object.size`, `saveRDS(compress = FALSE)`, write `R/gptr_data.R`.
7. Update `artifact.json` atomically.
8. In knitr (`isTRUE(getOption("knitr.in.progress"))`, VERIFIED option name in `knitr::knit`) or
   when `launch = FALSE`, stop here and return a static representation (see 4.6).
9. `art_start()`:
   - Stop the old process if one exists and remember its port.
   - `callr::r_bg(art_child_main)`.
   - Wait for the port file, then HTTP 200, within the timeout.
   - If the process exits, return `stage = "launch"` with the log tail.
10. On success, record `run.json` and `last_port`.
11. If `check == "session"` and chromote plus a Chrome binary are available, run
    `art_session_check()` to collect errors and a screenshot. Otherwise scan the log for
    `Error in` lines (an HTTP-only check).
12. If `view`, `art_view(url)`. Viewer calls from the tool path happen once per artifact id;
    a revision on the same URL refreshes the viewer via `viewer(url)`.
13. Record the call in the history document (REQ-24/25): a comment
    `# artifact <id> v<N>: <title> (.gptr/artifacts/<id>/v<N>/app.R)` plus the replayable
    `gptr::artifact_open("<id>")`.

**Child process:** watchdog `later::later(wd, 1)` → port choice (preferred, else random) → atomic
port file → `shiny::runApp(app_dir, port, host = "127.0.0.1", launch.browser = FALSE)`.

**Stop:** `interrupt()` → wait 3 s → `kill_tree()` → wait 2 s → remove `run/run.json` and
`run/port`.

**Session exit:** processx finalizers (verified for normal and error exits) plus `supervise = TRUE`
plus the child watchdog. Also register `reg.finalizer(.gptr_art, function(e) artifact_stop(), onexit = TRUE)`
in `.onLoad` so logs are flushed and `run.json` files removed (LIKELY fine), and close the shared
chromote browser (`chrome$close()`) in the same finalizer.

**Resource policy:** at most `getOption("gptr.artifact.max_running", 5)` concurrent servers; when
launching one more, stop the least recently used.

### 4.4 System-prompt section (house style; injected only when the artifact tool is enabled)

```
## Artifacts
Use the `artifact` tool when an interactive view helps (filters, drill-down, dashboards,
comparisons). For one static chart, run R code and show the plot instead.
app.R rules:
- One file. Start with library(shiny); library(bslib). End with shinyApp(ui, server).
- Objects listed in `data` already exist under their names. Never read files, call setwd(),
  runApp(), install.packages(), or modify objects outside the app.
- Layout: page_sidebar(title = "...", sidebar = sidebar(<inputs>), ...). KPIs:
  layout_columns(value_box("Label", textOutput("id")), ...). Each chart/table in
  card(card_header("..."), <output>, full_screen = TRUE). Use page_navbar(nav_panel(...)) only
  for several pages. Never nest card() in card() or page_*() in page_*().
- Charts: renderPlot() + ggplot2 with theme_minimal() and explicit labs(). Use plotly, DT,
  reactable or leaflet only if listed below.
- Compute filtered data once in reactive(); guard empty inputs with req(). Keep it short: no
  custom CSS/JS, no modules, no comments, no theme unless asked.
- To revise, pass `id` plus `edits` (exact old_text/new_text) instead of resending the file.
- Read the returned screenshot and errors; fix problems before telling the user it is done.
Installed: {shiny 1.13.0, bslib 0.10.0, ggplot2 4.0.2, plotly 4.12.0, DT 0.34.0}   # generated at runtime
```

The installed list is generated with `vapply(c("ggplot2", "plotly", "DT", "reactable", "leaflet",
"bsicons", "thematic"), function(p) nzchar(system.file(package = p)), NA)` plus
`packageVersion()`. It is cheap because nothing is loaded.

### 4.5 Package dependencies

| Package | Field | Reason |
|---|---|---|
| callr, processx, ps | Imports | child process, supervision, tree kill, PID checks (installed processx 3.8.6 Imports ps, R6, utils; callr 3.7.6 Imports processx, R6, utils; VERIFIED. Current CRAN callr 3.8.0 also Imports otel) |
| jsonlite, curl | Imports | metadata, HTTP polling (gptr needs both anyway for providers) |
| shiny (≥ 1.8), bslib | **Suggests** | loaded only in the child; check with `nzchar(system.file(package = "shiny"))` and give an informative error |
| later, httpuv | (via shiny) | used only in the child; no direct import needed |
| chromote | Suggests | session validation + screenshots |
| ragg, svglite | Suggests | plot capture (fallback `grDevices::png`) |
| htmlwidgets, rmarkdown | Suggests | static exports (pandoc needed for self-contained) |
| shinylive | Suggests | `artifact_export(format = "shinylive")` |
| rstudioapi | Suggests | `translateLocalUrl`, `hasFun`, viewer detection |
| qs2 | Suggests (optional) | faster snapshots when opted in |
| shinychat | not in v1 | pulls ellmer |

### 4.6 Environment matrix (display behaviour)

| Context | Detect | Behaviour |
|---|---|---|
| RStudio Desktop | `rstudioapi::isAvailable()` / `getOption("viewer")` | `viewer(url)` (Viewer pane) |
| RStudio Server / Workbench | `rstudioapi::versionInfo()$mode == "server"` | viewer handles proxying; for printed links use `translateLocalUrl(url, absolute = TRUE)` |
| Positron | `getOption("viewer")` set by Positron shims (LIKELY) | `viewer(url)` |
| Terminal R | no viewer option | `utils::browseURL(url)` (once per artifact id) and print the URL |
| Rscript / non-interactive | `!interactive()` | `launch = FALSE` by default: save files, return the path; the app would die with the script anyway |
| knitr/Quarto render | `getOption("knitr.in.progress")` | no server; emit screenshot (if chromote) via `knitr::include_graphics()` + app path + `eval = FALSE` code |
| Jupyter (IRkernel) | `getOption("jupyter.in_kernel")` (LIKELY) | `IRdisplay::display_html('<iframe src=...>')` (UNCERTAIN) |

---

## 5. Verified R prototypes

All were run with `Rscript --vanilla` on this machine. Private-library packages were loaded by
prepending `.../scratchpad/rlib` to `.libPaths()`.

### 5.1 Reference implementation — `W17/run2/artifact_lib3.R` (complete, as run)

```r
# gptr artifact reference implementation v3 (track 17). Pure R; parent uses only
# callr, processx, ps, jsonlite, curl (+ chromote optional). shiny is loaded only in the child.
#
# Layout:  <root>/<id>/artifact.json            metadata + version history (atomic writes)
#          <root>/<id>/v001/app.R               model-written app (portable, shinylive-exportable)
#          <root>/<id>/v001/R/gptr_data.R       generated loader (shiny sources R/*.R before app.R)
#          <root>/<id>/v001/data/<name>.rds     data snapshot of named session objects
#          <root>/<id>/run/{run.json,port,app.log}  runtime files, never inside a version dir

.gptr_art <- new.env(parent = emptyenv())
.gptr_art$procs <- list()

`%||%` <- function(a, b) if (is.null(a)) b else a
art_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")

art_root <- function(root = file.path(getwd(), ".gptr", "artifacts")) {
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  normalizePath(root, winslash = "/", mustWork = TRUE)
}
art_slug <- function(x, max = 32L) {
  x <- tolower(iconv(x, to = "ASCII//TRANSLIT", sub = ""))
  x <- gsub("(^-+|-+$)", "", gsub("[^a-z0-9]+", "-", x))
  if (is.na(x) || !nzchar(x)) "artifact" else substr(x, 1L, max)
}
art_new_id <- function(title, root) {           # tempfile() never touches .Random.seed
  repeat {
    s <- basename(tempfile(""))
    id <- paste0(art_slug(title), "-", substr(s, nchar(s) - 5L, nchar(s)))
    if (dir.create(file.path(root, id), showWarnings = FALSE)) return(id)   # atomic claim
  }
}
art_json_read <- function(path) jsonlite::read_json(path, simplifyVector = FALSE)
art_json_write <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) stop("could not write ", path, call. = FALSE)
  invisible(path)
}
art_meta <- function(root, id) art_json_read(file.path(root, id, "artifact.json"))

# ---- tier 1: static checks (no evaluation) --------------------------------------------------
art_static_check <- function(code) {
  exprs <- tryCatch(parse(text = code, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) return(list(ok = FALSE, stage = "parse", message = conditionMessage(exprs)))
  pd <- utils::getParseData(exprs)
  calls <- unique(pd$text[pd$token == "SYMBOL_FUNCTION_CALL"])
  lib <- unlist(lapply(exprs, function(e) if (is.call(e) && as.character(e[[1]])[1] %in% c("library", "require") &&
                                              length(e) >= 2) as.character(e[[2]])))
  pkgs <- unique(c(lib, pd$text[pd$token == "SYMBOL_PACKAGE"]))
  missing <- pkgs[!vapply(pkgs, function(p) nzchar(system.file(package = p)), logical(1))]
  bad <- intersect(calls, c("runApp", "runGadget", "install.packages", "setwd", "quit", "q"))
  last <- exprs[[length(exprs)]]
  msgs <- c(if (length(bad)) paste("remove call(s):", paste(bad, collapse = ", ")),
            if (length(missing)) paste("package(s) not installed:", paste(missing, collapse = ", ")),
            if (!(is.call(last) && identical(as.character(last[[1]])[1], "shinyApp")))
              "the last expression must be shinyApp(ui, server)")
  list(ok = !length(msgs), stage = "static", message = paste(msgs, collapse = "; "), packages = pkgs)
}

# ---- data snapshot ----------------------------------------------------------------------------
art_snapshot <- function(vdir, data, envir, max_bytes = getOption("gptr.artifact.max_bytes", 1e9)) {
  if (!length(data)) return(list())
  dir.create(file.path(vdir, "data"), showWarnings = FALSE); dir.create(file.path(vdir, "R"), showWarnings = FALSE)
  info <- list(); loader <- "# Generated by gptr: data snapshot for this artifact version."
  for (nm in data) {
    if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", nm)) stop("invalid object name: ", nm, call. = FALSE)
    if (!exists(nm, envir = envir)) stop("object not found: ", nm, call. = FALSE)
    obj <- get(nm, envir = envir)
    sz <- as.numeric(utils::object.size(obj))
    if (sz > max_bytes) stop(sprintf("'%s' is %.0f MB (limit %.0f MB); snapshot a subset or summary instead",
                                     nm, sz / 1e6, max_bytes / 1e6), call. = FALSE)
    f <- file.path(vdir, "data", paste0(nm, ".rds"))
    saveRDS(obj, f, compress = FALSE)
    info[[length(info) + 1L]] <- list(name = nm, class = class(obj)[1],
      dim = as.list(dim(obj) %||% length(obj)), bytes = unname(file.size(f)))
    loader <- c(loader, sprintf('%s <- readRDS("data/%s.rds")', nm, nm))
  }
  writeLines(loader, file.path(vdir, "R", "gptr_data.R"), useBytes = TRUE)
  info
}

# ---- child process entry point (serialised by callr; must be self-contained) -------------------
art_child_main <- function(app_dir, port_file, preferred_port, parent_pid) {
  ph <- tryCatch(ps::ps_handle(as.integer(parent_pid)), error = function(e) NULL)
  wd <- function() {                                   # exit when the parent session is gone
    if (is.null(ph) || !isTRUE(tryCatch(ps::ps_is_running(ph), error = function(e) FALSE))) quit(save = "no")
    later::later(wd, 1)
  }
  later::later(wd, 1)
  free <- function(p) !inherits(try(httpuv::stopServer(httpuv::startServer("127.0.0.1", p, list())), silent = TRUE), "try-error")
  port <- if (!is.null(preferred_port) && free(preferred_port)) preferred_port else
    httpuv::randomPort(min = 20000L, max = 39999L)      # RNG side effects stay in the child
  tmp <- paste0(port_file, ".tmp"); writeLines(as.character(port), tmp); file.rename(tmp, port_file)
  shiny::runApp(app_dir, port = port, host = "127.0.0.1", launch.browser = FALSE)
}

art_wait <- function(proc, port_file, timeout) {
  t0 <- Sys.time(); el <- function() as.numeric(Sys.time() - t0, units = "secs")
  h <- curl::new_handle(timeout_ms = 3000L, connecttimeout_ms = 250L); port <- NULL
  repeat {
    if (!proc$is_alive()) return(list(ok = FALSE, reason = "app process exited", elapsed = el()))
    if (is.null(port) && file.exists(port_file)) port <- as.integer(readLines(port_file, warn = FALSE)[1])
    if (!is.null(port)) {
      url <- sprintf("http://127.0.0.1:%d/", port)
      r <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
      if (!is.null(r)) return(list(ok = r$status_code == 200L, status = r$status_code, port = port, url = url,
                                   html = rawToChar(r$content), elapsed = el()))
    }
    if (el() > timeout) return(list(ok = FALSE, reason = "timeout", elapsed = el()))
    Sys.sleep(0.05)
  }
}

artifact_start <- function(id, version = NULL, root = art_root(), timeout = 30, browse = FALSE) {
  meta <- art_meta(root, id); version <- version %||% meta$current
  vdir <- file.path(root, id, sprintf("v%03d", version))
  preferred <- .gptr_art$procs[[id]]$port %||% meta$last_port        # stable URL across revisions
  if (!is.null(.gptr_art$procs[[id]])) artifact_stop(id, root = root)
  rdir <- file.path(root, id, "run"); dir.create(rdir, showWarnings = FALSE)
  port_file <- file.path(rdir, "port"); unlink(port_file)
  log <- file.path(rdir, sprintf("app-v%03d.log", version))
  proc <- callr::r_bg(art_child_main,
    args = list(app_dir = vdir, port_file = port_file, preferred_port = preferred, parent_pid = Sys.getpid()),
    stdout = log, stderr = "2>&1", supervise = TRUE, cleanup = TRUE, cleanup_tree = TRUE,
    user_profile = FALSE, system_profile = FALSE, env = c(callr::rcmd_safe_env(), GPTR_ARTIFACT = id))
  w <- art_wait(proc, port_file, timeout)
  if (!isTRUE(w$ok)) {
    if (proc$is_alive()) proc$kill_tree()
    return(list(ok = FALSE, stage = "launch", reason = w$reason %||% paste("HTTP", w$status),
                log = utils::tail(if (file.exists(log)) readLines(log, warn = FALSE) else character(), 30)))
  }
  .gptr_art$procs[[id]] <- list(proc = proc, port = w$port, url = w$url, version = version, log = log)
  art_json_write(list(pid = proc$get_pid(), create_time = as.numeric(ps::ps_create_time(ps::ps_handle(proc$get_pid()))),
                      port = w$port, url = w$url, version = version, parent_pid = Sys.getpid(), started = art_now()),
                 file.path(rdir, "run.json"))
  meta$last_port <- w$port; art_json_write(meta, file.path(root, id, "artifact.json"))
  if (isTRUE(browse)) { v <- getOption("viewer", utils::browseURL); v(w$url) }
  list(ok = TRUE, url = w$url, port = w$port, pid = proc$get_pid(), startup_secs = w$elapsed, html = w$html, log = log)
}

artifact <- function(title, code, data = character(), id = NULL, envir = parent.frame(),
                     root = art_root(), launch = TRUE, browse = FALSE, timeout = 30) {
  chk <- art_static_check(code)
  if (!chk$ok) return(structure(list(ok = FALSE, stage = chk$stage, message = chk$message), class = "gptr_artifact"))
  if (is.null(id)) {
    id <- art_new_id(title, root)
    meta <- list(schema = 1L, id = id, title = title, created = art_now(), versions = list())
  } else {
    meta <- art_meta(root, id); if (!missing(title)) meta$title <- title
  }
  version <- length(meta$versions) + 1L
  while (!dir.create(vdir <- file.path(root, id, sprintf("v%03d", version)), showWarnings = FALSE))
    version <- version + 1L                                           # dir.create() is the lock
  writeLines(code, file.path(vdir, "app.R"), useBytes = TRUE)
  dinfo <- art_snapshot(vdir, data, envir)
  meta$versions[[length(meta$versions) + 1L]] <- list(version = version, created = art_now(),
    data = dinfo, packages = as.list(chk$packages))
  meta$current <- version; meta$updated <- art_now()
  art_json_write(meta, file.path(root, id, "artifact.json"))
  out <- list(ok = TRUE, id = id, version = version, dir = vdir, title = meta$title)
  if (launch) out <- utils::modifyList(out, artifact_start(id, version, root, timeout, browse))
  structure(out, class = "gptr_artifact")
}

artifact_stop <- function(id = NULL, root = art_root(), grace = 2) {
  ids <- id %||% names(.gptr_art$procs); res <- character()
  for (i in ids) {
    h <- .gptr_art$procs[[i]]
    if (is.null(h)) { res[i] <- "not running"; next }
    p <- h$proc
    if (p$is_alive()) { p$interrupt(); p$wait(grace * 1000); if (p$is_alive()) p$kill_tree(); p$wait(2000) }
    res[i] <- if (p$is_alive()) "STILL ALIVE" else "stopped"
    .gptr_art$procs[[i]] <- NULL
    unlink(file.path(root, i, "run", c("run.json", "port")))
  }
  invisible(res)
}

art_sweep_orphans <- function(root = art_root()) {
  killed <- character()
  for (f in Sys.glob(file.path(root, "*", "run", "run.json"))) {
    r <- art_json_read(f); id <- basename(dirname(dirname(f)))
    if (r$parent_pid == Sys.getpid() && !is.null(.gptr_art$procs[[id]])) next
    if (r$parent_pid != Sys.getpid() &&
        isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(r$parent_pid))), error = function(e) FALSE))) next
    ch <- tryCatch(ps::ps_handle(as.integer(r$pid)), error = function(e) NULL)
    if (!is.null(ch) && isTRUE(tryCatch(ps::ps_is_running(ch), error = function(e) FALSE)) &&
        abs(as.numeric(ps::ps_create_time(ch)) - r$create_time) < 1) {    # PID-reuse guard
      try(ps::ps_kill(ch), silent = TRUE); killed <- c(killed, id)
    }
    unlink(f)
  }
  killed
}

artifacts <- function(root = art_root()) {
  ids <- basename(dirname(Sys.glob(file.path(root, "*", "artifact.json"))))
  if (!length(ids)) return(data.frame())
  do.call(rbind, lapply(ids, function(i) {
    m <- art_meta(root, i); h <- .gptr_art$procs[[i]]; up <- !is.null(h) && h$proc$is_alive()
    data.frame(id = i, title = m$title, versions = length(m$versions), current = m$current,
               status = if (up) "running" else "stopped", url = if (up) h$url else NA_character_,
               updated = m$updated, stringsAsFactors = FALSE)
  }))
}
```
Differences for the real package:
- The default root must follow `artifact_dir()` (tempdir unless a workspace exists).
- `grace` should be 3.
- Add `edits`/`kind`.
- Pass `package = "gptr"` to callr.
- `art_sweep_orphans()` should skip a `run.json` whose `parent_pid` is alive but belongs to a
  different machine (network shares; UNCERTAIN edge case). The lib3 sweep itself was checked by
  the fact-check on synthetic `run/run.json` files (`verify-17/v12_sweep_lib3.R`): it killed the
  true orphan, spared a live process whose `create_time` did not match (PID reuse), and skipped
  an entry whose parent was alive.
- **Defects found by the fact-check in `art_static_check()` (VERIFIED):**
  - Empty `code` crashes with "attempt to select less than one element" (`exprs[[0]]`). Guard with
    `if (!length(exprs))`.
  - A last expression written as `shiny::shinyApp(ui, server)` is wrongly rejected, because
    `as.character(last[[1]])[1]` is `"::"`. Accept both `shinyApp` and `shiny::shinyApp`.
- With callr 3.8.0 a stopped child exits with status 1 (§2.2). Do not read the exit status as
  failure after `artifact_stop()`.
- Save and restore `.Random.seed` around `chromote::Chromote$new()` (§1 item 1).

### 5.2 Headless session check — `W17/run2/art_session_check.R` (complete, as run)

```r
art_session_check <- function(url, log_file = NULL, width = 1100L, height = 750L,
                              timeout = 20, format = c("png", "jpeg"), quality = 80L,
                              browser = NULL) {
  format <- match.arg(format)
  if (!requireNamespace("chromote", quietly = TRUE)) {
    return(list(ok = NA, skipped = "chromote not installed"))
  }
  t0 <- Sys.time(); el <- function() as.numeric(Sys.time() - t0, units = "secs")
  # reuse one headless Chrome per R session (cold start is the dominant cost)
  b <- if (is.null(browser)) chromote::ChromoteSession$new(width = width, height = height)
       else browser$new_session(width = width, height = height)
  t_browser <- el()
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  js_errors <- character()
  b$Runtime$enable()
  b$Runtime$exceptionThrown(callback_ = function(m) {
    js_errors <<- c(js_errors, m$exceptionDetails$exception$description %||% m$exceptionDetails$text)
  })
  b$Runtime$consoleAPICalled(callback_ = function(m) {
    if (identical(m$type, "error"))
      js_errors <<- c(js_errors, paste(vapply(m$args, function(a) as.character(a$value %||% a$description %||% ""), ""), collapse = " "))
  })
  loaded <- b$Page$loadEventFired(wait_ = FALSE)   # register BEFORE navigating (avoids a race)
  b$Page$navigate(url, wait_ = FALSE)
  b$wait_for(loaded)
  ev <- function(js) b$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  state_js <- "(function(){
    var s = window.Shiny && Shiny.shinyapp;
    return JSON.stringify({
      connected: !!(s && s.isConnected && s.isConnected()),
      busy: document.documentElement.classList.contains('shiny-busy'),
      recalculating: document.querySelectorAll('.recalculating').length,
      disconnected: !!document.getElementById('shiny-disconnected-overlay')
    });})()"
  stable <- 0L; st <- NULL
  while (el() < timeout) {
    st <- jsonlite::fromJSON(ev(state_js))
    if (isTRUE(st$disconnected)) break
    if (isTRUE(st$connected) && !isTRUE(st$busy) && st$recalculating == 0) stable <- stable + 1L else stable <- 0L
    if (stable >= 5L) break                      # idle for ~0.5 s
    Sys.sleep(0.1)
  }
  output_errors <- jsonlite::fromJSON(ev("JSON.stringify(Array.from(document.querySelectorAll(
     '.shiny-output-error:not(.shiny-output-error-validation)')).map(function(e){
       return {id: e.id, message: e.textContent.trim()}; }))"))
  validation_msgs <- jsonlite::fromJSON(ev("JSON.stringify(Array.from(document.querySelectorAll(
     '.shiny-output-error-validation')).map(function(e){ return {id: e.id, message: e.textContent.trim()}; }))"))
  shot <- b$Page$captureScreenshot(format = format, quality = if (format == "jpeg") quality else NULL)$data
  log_errors <- character()
  if (!is.null(log_file) && file.exists(log_file)) {
    lg <- readLines(log_file, warn = FALSE)
    log_errors <- grep("^(Warning: )?Error in|^Error", lg, value = TRUE)
    log_warnings <- grep("^Warning in|^Warning:", setdiff(lg, log_errors), value = TRUE)
  } else log_warnings <- character()
  n_err <- NROW(output_errors) + length(js_errors) + length(log_errors) + isTRUE(st$disconnected)
  list(ok = n_err == 0 && isTRUE(st$connected), elapsed = el(), browser_start = t_browser,
       log_warnings = log_warnings, connected = isTRUE(st$connected),
       disconnected = isTRUE(st$disconnected), output_errors = output_errors,
       validation = validation_msgs, js_errors = unique(js_errors), log_errors = log_errors,
       screenshot_base64 = shot, screenshot_mime = paste0("image/", format))
}
```
Known gaps:
- `log_warnings` captures only the first line of a multi-line warning (the message is on the next
  line); take `line + 1`.
- The chromote event callbacks sometimes print "could not find function deregister_and_dec" (a
  chromote-internal warning seen once, harmless).
- Suppress the printed `<Promise>` / `$timestamp` values by wrapping calls in `invisible()`.

### 5.3 THE DELIVERABLE — `W17/run2/e12_final.R` (complete, as run) and its output

```r
run2 <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/17/run2"
.libPaths(c("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib", .libPaths()))
source(file.path(run2, "artifact_lib3.R")); source(file.path(run2, "art_session_check.R"))
proj <- file.path(run2, "proj_e12"); unlink(proj, recursive = TRUE); dir.create(proj); setwd(proj)
root <- art_root()

set.seed(1)                                            # the user's live session object
sales <- data.frame(region = sample(c("North", "South", "East", "West"), 5000, TRUE),
                    month = factor(sample(month.abb, 5000, TRUE), levels = month.abb),
                    units = rpois(5000, 40), price = round(runif(5000, 5, 50), 2))
sales$revenue <- sales$units * sales$price
seed_before <- .Random.seed

code <- r"--(library(shiny)
library(bslib)
ui <- page_sidebar(
  title = "Sales explorer",
  sidebar = sidebar(selectInput("region", "Region", c("All", sort(unique(sales$region)))),
                    sliderInput("bins", "Bins", 5, 50, 20)),
  layout_columns(value_box("Rows", textOutput("n")), value_box("Revenue", textOutput("rev"))),
  card(card_header("Revenue distribution"), plotOutput("hist")))
server <- function(input, output, session) {
  d <- reactive(if (input$region == "All") sales else sales[sales$region == input$region, ])
  output$n <- renderText(format(nrow(d()), big.mark = ","))
  output$rev <- renderText(format(round(sum(d()$revenue)), big.mark = ","))
  output$hist <- renderPlot(hist(d()$revenue, breaks = input$bins, main = NULL, xlab = "Revenue"))
}
shinyApp(ui, server))--"

cat("== 1. artifact(): snapshot + launch + poll ==\n")
t0 <- Sys.time()
a <- artifact("Sales explorer", code, data = "sales")
cat(sprintf("ok=%s id=%s v%d url=%s pid=%d | HTTP 200 after %.2fs | artifact() returned after %.2fs\n",
            a$ok, a$id, a$version, a$url, a$pid, a$startup_secs, as.numeric(Sys.time() - t0, units = "secs")))
cat("shiny loaded in parent:", "shiny" %in% loadedNamespaces(), "| user RNG untouched:", identical(seed_before, .Random.seed), "\n")
cat("files:\n"); print(sub(paste0(root, "/"), "", list.files(root, recursive = TRUE, full.names = TRUE), fixed = TRUE))

cat("\n== 2. fetch the page ==\n")
r <- curl::curl_fetch_memory(a$url); html <- rawToChar(r$content)
cat("status", r$status_code, "| bytes", nchar(html), "|", regmatches(html, regexpr("<title>[^<]*</title>", html)), "\n")
cat("options rendered from the shipped data:", paste(gsub('<option value="|"', "", regmatches(html, gregexpr('<option value="[A-Za-z]+"', html))[[1]]), collapse = ", "), "\n")
cat("output ids:", paste(gsub('.*id="([^"]+)".*', "\\1", regmatches(html, gregexpr('<[a-z]+ [^>]*class="[^"]*shiny-[a-z]+-output[^"]*"[^>]*>', html))[[1]]), collapse = ", "), "\n")

cat("\n== 3. headless session check + screenshot for the model ==\n")
sc <- art_session_check(a$url, log_file = a$log, width = 1100, height = 750)
cat(sprintf("session ok=%s connected=%s output_errors=%d js_errors=%d log_errors=%d | %.2fs | screenshot %d base64 chars (~%d Claude visual tokens)\n",
            sc$ok, sc$connected, NROW(sc$output_errors), length(sc$js_errors), length(sc$log_errors), sc$elapsed,
            nchar(sc$screenshot_base64), ceiling(1100 / 28) * ceiling(750 / 28)))
writeBin(base64enc::base64decode(sc$screenshot_base64), file.path(run2, "final_screenshot.png"))

cat("\n== 4. the console stays free: work on the live object while the app serves ==\n")
sales$margin <- sales$revenue * 0.3
print(round(tapply(sales$margin, sales$region, sum)))

cat("\n== 5. revise -> v2 on the SAME URL, with the updated object ==\n")
code2 <- sub('title = "Sales explorer"', 'title = "Sales explorer (with margin)"', code, fixed = TRUE)
code2 <- sub('value_box("Revenue", textOutput("rev"))', 'value_box("Revenue", textOutput("rev")), value_box("Margin", textOutput("m"))', code2, fixed = TRUE)
code2 <- sub("output$hist <-", "output$m <- renderText(format(round(sum(d()$margin)), big.mark = \",\"))\n  output$hist <-", code2, fixed = TRUE)
old_pid <- a$pid
a2 <- artifact(code = code2, data = "sales", id = a$id)
cat(sprintf("v%d ok=%s url=%s (same as v1: %s) | HTTP 200 after %.2fs | old pid alive: %s\n", a2$version, a2$ok, a2$url,
            identical(a2$url, a$url), a2$startup_secs,
            isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(old_pid)), error = function(e) FALSE))))
sc2 <- art_session_check(a2$url, log_file = a2$log)
cat("v2 session ok:", sc2$ok, "\n")
writeBin(base64enc::base64decode(sc2$screenshot_base64), file.path(run2, "final_screenshot_v2.png"))
print(artifacts())

cat("\n== 6. stop + confirm cleanup ==\n")
h <- .gptr_art$procs[[a2$id]]; pid <- h$proc$get_pid()
t0 <- Sys.time(); print(artifact_stop(a2$id)); cat(sprintf("stop took %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))
cat("server pid alive:", isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(pid)), error = function(e) FALSE)), "\n")
g <- tryCatch(curl::curl_fetch_memory(a2$url), error = function(e) conditionMessage(e))
cat("GET after stop ->", if (is.character(g)) substr(g, 1, 60) else g$status_code, "\n")
cat("remaining children of this R process:", paste(vapply(ps::ps_children(ps::ps_handle()), ps::ps_name, ""), collapse = ", "), "\n")
cat("run/ contents:", list.files(file.path(root, a$id, "run")), "\n")
cat("version dirs contain no runtime files:", !any(grepl("log|port|run", list.files(file.path(root, a$id, c("v001", "v002")), recursive = TRUE))), "\n")
print(artifacts())
```
Observed output (`W17/run2/e12_output.txt`, chromote noise lines filtered):
```
== 1. artifact(): snapshot + launch + poll ==
ok=TRUE id=sales-explorer-35fc46 v1 url=http://127.0.0.1:34110/ pid=22921 | HTTP 200 after 2.48s | artifact() returned after 2.84s
shiny loaded in parent: FALSE | user RNG untouched: TRUE
files:
[1] "sales-explorer-35fc46/artifact.json"
[2] "sales-explorer-35fc46/run/app-v001.log"
[3] "sales-explorer-35fc46/run/port"
[4] "sales-explorer-35fc46/run/run.json"
[5] "sales-explorer-35fc46/v001/R/gptr_data.R"
[6] "sales-explorer-35fc46/v001/app.R"
[7] "sales-explorer-35fc46/v001/data/sales.rds"
== 2. fetch the page ==
status 200 | bytes 7199 | <title>Sales explorer</title>
options rendered from the shipped data: All, East, North, South, West
output ids: n, rev, hist
== 3. headless session check + screenshot for the model ==
session ok=TRUE connected=TRUE output_errors=0 js_errors=0 log_errors=0 | 4.46s | screenshot 42636 base64 chars (~1080 Claude visual tokens)
== 4. the console stays free: work on the live object while the app serves ==
  East  North  South   West
388250 410026 431024 412476
== 5. revise -> v2 on the SAME URL, with the updated object ==
v2 ok=TRUE url=http://127.0.0.1:34110/ (same as v1: TRUE) | HTTP 200 after 2.30s | old pid alive: FALSE
v2 session ok: TRUE
                     id          title versions current  status
1 sales-explorer-35fc46 Sales explorer        2       2 running
                      url                      updated
1 http://127.0.0.1:34110/ 2026-09-29T19:06:05.880-0700
== 6. stop + confirm cleanup ==
sales-explorer-35fc46
            "stopped"
stop took 2.08s
server pid alive: FALSE
GET after stop -> Could not connect to server [127.0.0.1]:
Failed to connect t
remaining children of this R process: supervisor, Google Chrome
run/ contents: app-v001.log app-v002.log
version dirs contain no runtime files: TRUE
                     id          title versions current  status  url
1 sales-explorer-35fc46 Sales explorer        2       2 stopped <NA>
                       updated
1 2026-09-29T19:06:05.880-0700
```
Notes on this output:
- The v2 screenshot (`W17/run2/final_screenshot_v2.png`, inspected) shows the new title and three
  value boxes: Rows 5,000; Revenue 5,472,587; Margin 1,641,776. The Margin value comes from the
  column added to the live object after v1.
- The 4.46 s session check includes the Chrome cold start.
- The 2.08 s stop hit the 2 s grace; the fallback kill worked. Graceful stops were measured at
  0.06–1.05 s in `e12b`/`e12c`.
- "Google Chrome" remains a child because the session check's browser was not explicitly closed in
  this script. The real package must close it (see §4.3).
- Fact-check re-run (copies of lib3 and `art_session_check.R` in `verify-17/`, machine load
  average about 15–50): all lines reproduced (same data values, output ids, file layout, same-URL
  v2, cleanup), with HTTP 200 after 3.53 s / 1.95 s, a session check of 8.03 s including the Chrome
  cold start, and a stop of 0.19 s. The "user RNG untouched: TRUE" line is printed *before* the
  session check; Chrome's launch changes the seed afterwards (§1 item 1).

### 5.4 Cleanup matrix (E2) — complete code

`W17/run2/e2_parent.R` (uses lib v2 `W17/run2/artifact_lib2.R`, whose `artifact_start()` has
`supervise` and `watchdog` switches):
```r
a <- commandArgs(TRUE); sup <- as.logical(a[1]); wd <- as.logical(a[2]); mode <- a[3]; pidfile <- a[4]
run2 <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/17/run2"
source(file.path(run2, "artifact_lib2.R"))
proj <- tempfile("e2proj"); dir.create(proj); setwd(proj)
code <- 'library(shiny)\nui <- fluidPage("hi")\nserver <- function(input, output, session) {}\nshinyApp(ui, server)'
x <- artifact("cleanup test", code, launch = FALSE)
r <- artifact_start(x$id, supervise = sup, watchdog = wd)
writeLines(format(c(r$pid, as.numeric(ps::ps_create_time(ps::ps_handle(r$pid)))), digits = 15), pidfile)
if (mode == "sleep") Sys.sleep(60)
if (mode == "error") stop("simulated fatal error at top level")
# mode "exit": fall off the end of the script -> R exits normally
```
`W17/run2/e2_matrix.R`:
```r
run2 <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/17/run2"
alive <- function(pid, ct) { h <- tryCatch(ps::ps_handle(pid), error = function(e) NULL); !is.null(h) && isTRUE(tryCatch(ps::ps_is_running(h), error = function(e) FALSE)) && abs(as.numeric(ps::ps_create_time(h)) - ct) < 1 }
out <- data.frame()
for (mode in c("exit", "error", "kill")) for (sup in c(FALSE, TRUE)) for (wd in c(FALSE, TRUE)) {
  pf <- tempfile("pid")
  p <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", file.path(run2, "e2_parent.R"), sup, wd, if (mode == "kill") "sleep" else mode, pf), stdout = "|", stderr = "|")
  t0 <- Sys.time(); while (!file.exists(pf) && as.numeric(Sys.time() - t0, units = "secs") < 30) Sys.sleep(0.05)
  Sys.sleep(0.2); info <- readLines(pf); pid <- as.integer(info[1]); ct <- as.numeric(info[2])
  if (mode == "kill") { p$kill() } else p$wait(20000)   # SIGKILL: no finalizers can run
  a0 <- alive(pid, ct); Sys.sleep(3); a3 <- alive(pid, ct)
  if (a3) try(ps::ps_kill(ps::ps_handle(pid)), silent = TRUE)
  out <- rbind(out, data.frame(parent_end = mode, supervise = sup, watchdog = wd, child_alive_immediately = a0, child_alive_after_3s = a3))
}
print(out, row.names = FALSE)
```
The output is in §2.2.

### 5.5 In-process serving at an interactive console (E5) — code excerpt

`W17/run2/e5_inprocess.R` drives `R --vanilla --quiet --no-readline` through
`processx::process$new(..., pty = TRUE)`, synchronises on the `> ` prompt, and issues:
```r
big <- data.frame(x = rnorm(1e5)); s <- httpuv::startServer('127.0.0.1', 18123, list(call = function(req) list(status = 200L, headers = list('Content-Type' = 'text/plain'), body = sprintf('live object: nrow(big)=%d mean=%.4f', nrow(big), mean(big$x)))))
big <- big[1:10, , drop = FALSE]
Sys.sleep(3); cat('done sleeping\n')              # busy console while the parent issues GET
suppressPackageStartupMessages(library(shiny)); app <- shinyApp(fluidPage(textOutput('t')), function(input, output, session) output$t <- renderText(paste('rows in live object:', nrow(big))))
srv <- shiny:::startApp(shiny::as.shiny.appobj(app), 18124L, '127.0.0.1', quiet = TRUE); class(srv)
invisible(shiny:::serviceApp())
```
The parent GETs with curl and inspects `#t` with chromote. The full output is in §2.1. Runtime was
about 17 s.

### 5.6 Fork vs callr (E6) — abridged code (`W17/run2/e6_fork.R`; the `cat()` reporting lines are omitted)

```r
set.seed(1); n <- 2e6
big <- data.frame(g = sample(letters, n, TRUE), x = rnorm(n), y = runif(n), s = sprintf("k%07d", sample(n)))
cat("object.size:", format(object.size(big), units = "MB"), "\n")
wait_port <- function(pf, timeout = 60) { t0 <- Sys.time(); while (!file.exists(pf)) { if (as.numeric(Sys.time() - t0, units = "secs") > timeout) stop("timeout"); Sys.sleep(0.02) }; as.integer(readLines(pf)) }
wait_200 <- function(url, timeout = 60) { t0 <- Sys.time(); repeat { r <- tryCatch(curl::curl_fetch_memory(url), error = function(e) NULL); if (!is.null(r) && r$status_code == 200) return(rawToChar(r$content)); if (as.numeric(Sys.time() - t0, units = "secs") > timeout) stop("timeout"); Sys.sleep(0.05) } }
pf <- tempfile("port"); t0 <- Sys.time()
job <- parallel::mcparallel({
  port <- httpuv::randomPort(); writeLines(as.character(port), pf)
  ui <- shiny::fluidPage(shiny::h3(paste("rows (shared by fork):", nrow(big))))
  shiny::runApp(shiny::shinyApp(ui, function(input, output, session) NULL), port = port, launch.browser = FALSE, quiet = TRUE)
}, detached = FALSE, silent = TRUE)
port <- wait_port(pf); html <- wait_200(sprintf("http://127.0.0.1:%d/", port))
# ... report, then:
tools::pskill(job$pid, tools::SIGTERM); Sys.sleep(0.5); invisible(parallel::mccollect(job, wait = FALSE))
td <- tempfile("snap"); dir.create(td); pf2 <- tempfile("port"); t0 <- Sys.time()
saveRDS(big, file.path(td, "big.rds"), compress = FALSE)
p <- callr::r_bg(function(f, pf) {
  big <- readRDS(f); port <- httpuv::randomPort(); writeLines(as.character(port), pf)
  ui <- shiny::fluidPage(shiny::h3(paste("rows (shipped):", nrow(big))))
  shiny::runApp(shiny::shinyApp(ui, function(input, output, session) NULL), port = port, launch.browser = FALSE, quiet = TRUE)
}, args = list(f = file.path(td, "big.rds"), pf = pf2))
port <- wait_port(pf2); html <- wait_200(sprintf("http://127.0.0.1:%d/", port)); p$kill()
```
Output:
```
object.size: 183.1 Mb
fork: HTTP 200 after 0.76 s; page says: rows (shared by fork): 2000000
parent console free, child pid: 5161
child alive after pskill: FALSE
callr: saveRDS 1.27 s (console blocked), HTTP 200 after 6.06 s total; page says: rows (shipped): 2000000
```

### 5.7 Other executed prototypes (code in `W17/run2/`, outputs quoted in §2)

| Script | What it proves | Output file |
|---|---|---|
| `e1_deliverable.R` + `artifact_lib2.R` | first v2 deliverable; RNG untouched; shiny not loaded in parent | `e1_output.txt` |
| `e1b_timing.R`, `e1c_interleave.R` | supervise overhead nil; launcher latency under load | printed in §2.1 |
| `e3_validate.R`, `e3b_validate.R` | validation ladder on 8 apps (e3 shows the load-event race; e3b fixed) | `e3_output.txt`, `e3b_output.txt`, `shotb_*.png` |
| `e4_testserver.R` | testServer semantics | `e4_output.txt` |
| `e5b_runapp_blocks.R`, `e5c_ctrlc.R` | runApp blocks the console; pty interrupt inconclusive | `e5b_output.txt`, `e5c_output.txt` |
| `e7_html_fallback.R` | iframe srcdoc wrapper, file://, in-process static server, saveWidget | `e7_output.txt`, `shot_html_fallback.png` |
| `e8_plots.R`, `e8b_replay.R` | device sizes/tokens; display-list requirement | `e8_output.txt`, `e8b_output.txt`, `plot_ragg_1000x700_120.png` |
| `e9_tokens.R`, `e9b_equivalence.R`, `tok/*` | token ratios; all 6 apps functional | `e9_output.txt`, `e9b_output.txt`, `eq_*.png` |
| `e10*_autoreload.R` | in-place autoreload behaviour | `e10*_output.txt`, `e10d_rep*.txt` |
| `e11_lifecycle.R` | same-port restart, orphan sweep, dir.create lock | `e11_output.txt` |
| `e12b_stop.R`, `e12c_stop_plot.R` | graceful stop timings | `e12b_output.txt`, `e12c_output.txt` |

E11 output (verbatim):
```
== (1) same-port restart ==
v2 re-bound port 34140 right after v1 stopped: TRUE (1.06s); page shows: <h2>v2</h2>
== (2) orphan sweep after a parent crash ==
orphan server alive after parent SIGKILL: TRUE
[1] ".../proj_e11/.gptr/artifacts/orphan-c8a674/run.json"
art_sweep_orphans() killed: orphan-c8a674 | orphan alive now: FALSE
== (3) dir.create() as an atomic version lock ==
first dir.create: TRUE  second: FALSE
```
(E11 used lib v2, whose `run.json` sits at `<id>/run.json`. lib3 moved it to `<id>/run/run.json`.)

Could not run:
- `shinylive::export()`: it would download the asset bundle.
- Anything on Windows or Linux.
- RStudio/Positron viewer.
- Jupyter.
- Quarto CLI (not installed).

---

## 6. CRAN and cross-platform considerations

**CRAN.**
- Write artifacts only under `tempdir()` unless the user initialised a gptr workspace
  (REQ-27 `.gptr/`, created with interactive confirmation), or use `tools::R_user_dir("gptr", "data")`
  for a user-level store. Tests use `withr::local_tempdir()`.
- Examples: `@examplesIf interactive()` for anything that launches a process, opens a viewer, or
  starts Chrome. `R CMD check --as-cran` runs `\donttest{}` examples (VERIFIED: in
  `tools:::.check_packages`, `_R_CHECK_DONTTEST_EXAMPLES_` defaults to `as_cran`; R-ints documents
  the variable), so do not rely on `\donttest`.
- Tests: `skip_on_cran()` + `skip_if_not_installed("shiny")` + `skip_if(is.null(chromote::find_chrome()))`.
  Always `withr::defer(artifact_stop())`. Never leave Chrome running (policy quote in §3.5).
- Pure-R tests that need no process: `art_static_check()`, `art_snapshot()` + loader content, JSON
  round trips, ID/slug generation, the version lock, and the orphan sweep on synthetic `run.json`
  with dead PIDs.
- No `:::` to shiny. No assignment into `.GlobalEnv` in the parent. The child gets its data via
  shiny's `R/` autoload, so it does not need globalenv assignment either.
- Cores: one child per artifact. Nothing runs during check except guarded tests.
- Internet: none needed. shinylive export is explicitly user-triggered and fails gracefully offline.

**Windows specifics** (none executed; all LIKELY or UNCERTAIN unless noted):
- **Interrupt** is CTRL+BREAK (processx Rd, VERIFIED text). Whether `runApp()` in an Rterm child
  exits gracefully on it is UNCERTAIN. The 3 s grace + `kill_tree()` (TerminateProcess) fallback
  guarantees cleanup; `onStop` handlers may not run.
- **processx** sets `windows_detached_process = !cleanup` (VERIFIED signature). Keep `cleanup = TRUE`.
  The supervisor is designed to work on all platforms (LIKELY). `ps` supports Windows
  (`ps_handle`, `ps_create_time`, `ps_is_running`, `ps_kill`) (LIKELY).
- **Files open in another process cannot be renamed or deleted.** R docs: `file.rename` "Where
  file permissions allow this will overwrite an existing element of 'to'. This is subject to the
  limitations of the OS's corresponding system call" (VERIFIED).
  - Do not rewrite `app.R`/data of a *running* version; create a new `vNNN` (the design already
    does).
  - Delete version dirs and logs only after stop.
  - The port file is written by the child and only read by the parent (fine).
- **Paths:** always `normalizePath(winslash = "/")`. Spaces in user names (`C:/Users/Jane Doe/`)
  are handled by callr arg passing (LIKELY). Keep IDs short (32-char slug + 6 hex) to stay well
  under MAX_PATH 260.
- **Encoding:** write `app.R` as UTF-8 (`enc2utf8` + `useBytes = TRUE`). shiny reads it with
  `sourceUTF8` (VERIFIED in `shinyAppDir_appR`). R ≥ 4.2 on Windows uses UTF-8 as the native
  encoding (LIKELY).
- **Chrome discovery** is registry-only for Chrome (VERIFIED). For Edge, set
  `Sys.setenv(CHROMOTE_CHROME = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")`
  (path LIKELY). If neither is found, degrade to the HTTP + log check.
- **Firewall:** binding 127.0.0.1 (never 0.0.0.0) should not trigger the Windows Defender
  Firewall prompt (LIKELY).
- **Hyper-V/WSL excluded port ranges:** `httpuv::randomPort()` test-binds each candidate
  (`is_port_available`), so reserved ports are skipped (LIKELY). The preferred-port path also
  test-binds.
- **`later` idle callbacks in Rterm** (needed only for the optional in-process httpuv mode):
  UNCERTAIN. Do not ship that mode on Windows until tested.
- **Fork** (`mcparallel`) is unavailable on Windows (base R docs, LIKELY). Keep it Unix-only and
  opt-in.
- **Devices:** `png()` defaults differ (Windows GDI vs Cairo vs Quartz; here
  `getOption("bitmapType")` was "quartz"). Prefer `ragg::agg_png` for identical output on all
  platforms (Suggests; CRAN binaries exist for Windows/macOS, LIKELY).

---

## 7. Risks, pitfalls, open questions

**Risks and pitfalls:**
1. **Snapshot staleness.** Artifacts see a copy, not the live object. That is correct for
   isolation but surprising to users. Mitigations: the tool result says "snapshot of `sales` at
   v2"; `artifact(id = , data = )` re-snapshots; E12 v2 picked up a new column.
2. **Huge objects.** Snapshotting doubles memory in the child plus disk. For a 5 GB Seurat object,
   extrapolated from 0.53 s/100 MB uncompressed writes, it costs about 25 s (UNCERTAIN;
   extrapolated). Enforce `max_bytes`, and steer the model to derive a small data frame first. The
   Unix fork path is an optional accelerator.
3. **Security.**
   - Apps bind 127.0.0.1 with no authentication. On multi-user hosts (RStudio Server, shared Linux
     boxes) other local users can reach the port. Document this; a later mitigation could be an
     httpuv front proxy requiring a random token (not researched).
   - Model-written app code runs with user privileges in the child, so REQ-37 permission modes
     must treat "launch artifact" as code execution (approval in manual mode).
   - Data shipped via shinylive becomes public to anyone with the site.
4. **HTTP 200 is not "working".** Always run the session check when chromote and Chrome exist.
   Without them, report "HTTP-only check" to the model so it does not over-claim.
5. **testServer false positives** when inputs are not set. Do not run it automatically.
6. **Autoreload flakiness** (1 unexplained stale-data run of 5), and data/`R/` changes alone do not
   reload. Keep restart-on-same-port as the default.
7. **Chrome process lifetime.** Reuse one browser per session and close it in the onexit
   finalizer; E12 shows it otherwise lingers as a child.
8. **`httpuv::randomPort()` in the parent changes user results.** Never call it in the parent.
   This also applies to gptr's other tools (MCP HTTP servers, etc.). The same holds for
   `chromote::Chromote$new()` (its `with_random_port()` calls `sample()`; VERIFIED by the
   fact-check) and for `library(shiny)` on shiny ≤ 1.13.0 (creates `.Random.seed`). Wrap such calls
   in a `.Random.seed` save/restore.
9. **Viewer only accepts localhost URLs or files under `tempdir()`.** Static HTML artifacts must be
   copied to `tempdir()` for the RStudio viewer.
10. **Package drift.** bslib's API evolves. Generate the installed-package list plus versions into
    the prompt; the static check catches uninstalled packages but not wrong argument names
    (caught at launch or by the session check).
11. **Log growth.** Per-version logs in `run/` are small (162 bytes for a quiet app) but can grow
    with chatty apps. Rotate or truncate on each start.
12. **Grace timing under load.** A 2 s grace was exceeded once (E12). Use 3 s.

**Open questions for the maintainer or other tracks:**
- Revisions: restart on the same port (robust, 1–2.5 s, the user refreshes the tab or the viewer is
  re-called) versus autoreload (0.2–0.4 s, tabs refresh themselves, one unexplained failure)?
  I recommend restart for v1 and autoreload behind an option.
- (Added by the fact-check.) Should gptr offer a "live" mode on shiny ≥ 1.14.0 via the public
  `startApp()` (no snapshot; one app per session; stalls while R is busy; needs asynchronous
  polling)? Not researched beyond the checks in §2.1 G.
- Should `edits` (exact-match replacements) be the primary revision mode? It saves tokens roughly
  in proportion to app size (a whole app is 200–900 tokens; an edit is about 30–100).
- `kind = "html"` in v1, or Shiny-only? The fallback is about 10 lines on top of the Shiny path.
- The Jupyter display path and JupyterHub proxying need testing on a machine with Jupyter.
- Windows validation: interrupt semantics, the supervisor, later idle callbacks in Rterm, and
  Edge-via-`CHROMOTE_CHROME`.
- Should the R execution tool (REQ-23) share the chromote browser and the `plot_image()`
  defaults? Recommended yes: one "media" module.
- A shinychat gadget front end after v1?

---

## 8. Sources

Local source (read in this session; VERIFIED):
- shiny 1.13.0 namespace, deparsed in `W17/run2/inspect1.R` and ad-hoc `Rscript` calls:
  `shinyAppDir_appR`, `loadSupport`, `runApp` (port selection and `while (!.globals$stopped)`
  loop), `serviceApp`, `p_randomInt`, `runGadget`, `MockShinySession` public/private fields.
- httpuv 1.6.17: `randomPort` body; `unsafe_ports` (67 entries).
- processx 3.8.6 `process.Rd` (cleanup, cleanup_tree, supervise, interrupt, kill_tree,
  `windows_detached_process = !cleanup`). callr 3.7.6 `r.Rd` (`func`, `package`).
- chromote 0.5.1: `find_chrome`, `find_chrome_windows`. shinylive 0.3.0: `export.Rd`,
  `read_app_files`, `assets_cache_dir`. shinychat 0.3.0: exports, `chat_append.Rd`, DESCRIPTION
  Imports.
- htmlwidgets 1.6.4 `saveWidget` (pandoc). rstudioapi 0.18.0 `translateLocalUrl.Rd`, exports.
  knitr `knit` (sets `knitr.in.progress`). base `files.Rd` (`file.rename`). bslib 0.10.0
  `formals()`.
- Pi clone: `packages/coding-agent/src/utils/image-resize-core.ts:4-29` (image defaults),
  `src/utils/tool-result-images.ts` (image blocks in tool results),
  `packages/ai/src/types.ts:1073-1090` (`ModelImageResizeOptions` at 1073-1079, then
  `ModelImageInputLimits`/`ModelInputLimits`). Pi has no Shiny-like artifact system. In the user
  docs, "artifact" refers to session sharing
  (`packages/coding-agent/docs/usage.md:82`, `packages/coding-agent/docs/sessions.md:58`; path
  CORRECTED by the fact-check). Elsewhere it means build/plugin outputs ("TUI artifacts",
  `packages/coding-agent/src/experimental/services/README.md`) and release binaries.

Web (fetched 2026-09-29):
- https://platform.claude.com/docs/en/build-with-claude/vision — patch formula, tiers, limits (VERIFIED fetch)
- https://developers.openai.com/api/docs/guides/images-vision — patch/tile formulas (fetch summary; LIKELY)
- https://ai.google.dev/gemini-api/docs/image-understanding, https://ai.google.dev/gemini-api/docs/media-resolution (LIKELY)
- https://cran.r-project.org/web/packages/policies.html — CRAN policy quotes (VERIFIED fetch)
- https://cran.r-project.org/web/packages/shinylive/index.html, https://cran.r-project.org/web/packages/shinylive/news/news.html, https://posit-dev.github.io/r-shinylive/
- https://quarto.org/docs/dashboards/, https://quarto.org/docs/dashboards/interactivity/shiny-r.html
- https://posit-dev.github.io/shinychat/r/
- https://rstudio.github.io/rstudioapi/reference/viewer.html, https://rstudio.github.io/rstudioapi/reference/jobRunScript.html
- https://positron.posit.co/migrate-rstudio-settings-and-extensions.html (via search-result excerpt), https://github.com/posit-dev/positron/issues/1312
- https://later.r-lib.org/reference/later.html, https://later.r-lib.org/articles/later-cpp.html
- https://github.com/posit-dev/skills/blob/main/shiny/shiny-bslib/SKILL.md
- https://posit.co/blog/r-llm-evaluation-03, https://vitals.tidyverse.org/reference/are.html, https://posit.co/blog/ai-powered-shiny-app-prototyping
- Searches that found **no** Shiny-specific generation benchmark: "LLM benchmark Shiny app generation R code evaluation vitals are dataset Posit 2026"; "benchmark LLMs generating Shiny apps evaluation success rate bslib Shiny code generation study 2025 OR 2026".

Added by the fact-check (fetched 2026-09-29): CRAN index pages for shiny, bslib, callr, processx,
chromote, shinychat, shinylive, httpuv, later and ellmer; CRAN NEWS for shiny (1.14.0 `startApp()`),
bslib, callr, processx, shinylive and shinychat; https://quarto.org/docs/dashboards/interactivity/shiny-r.html;
https://posit.co/blog/ai-powered-shiny-app-prototyping; shiny 1.14.0 `startApp.Rd` (installed from
CRAN into a scratch library). Fact-check scripts and outputs:
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-17/`.

Executed experiments: all under `W17/run2/` (see the table in §5.7). Screenshots:
`final_screenshot.png`, `final_screenshot_v2.png`, `shotb_*.png`, `eq_*.png`,
`shot_html_fallback.png`, `plot_ragg_1000x700_120.png`.

---

## Verification log

Adversarial fact-check, 2026-09-29. Scripts and outputs are in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-17/`
(abbreviated `V/`). Every R check was run with `Rscript --vanilla`. The prototypes were re-run
from copies in `V/`, so no file under `W17/` was modified. shiny 1.14.0 and callr 3.8.0 were
installed from CRAN into scratch libraries `V/lib114` and `V/libcallr` (not the user library).
The machine's load average was about 15–50 during the re-runs, so latencies are higher than the
original figures.

| # | Claim | Verdict | Source / evidence |
|---|---|---|---|
| 1 | Installed versions (shiny 1.13.0, bslib 0.10.0, httpuv 1.6.17, callr 3.7.6, processx 3.8.6, ...) | confirmed (local); **corrected** as "current" | `V/v01_versions.R`; CRAN index pages: shiny 1.14.0, bslib 0.12.0, callr 3.8.0, processx 3.9.0 (header note added) |
| 2 | "In-process Shiny without blocking is impossible with shiny's public API" | **corrected** (true only for shiny ≤ 1.13.0) | shiny 1.14.0 NEWS and `startApp.Rd`; `V/v10_startapp114.R` (pty, interactive): non-blocking, live object, busy-console stall, one app per session; `V/v15_selfget.R` (same-process synchronous GET deadlocks) |
| 3 | `shinyAppDir_appR` autoload: `loadSupport(appDir, renv = sharedEnv, globalrenv = NULL)`, `global.R` not sourced, `R/_disable_autoload.R` | confirmed (1.13.0 and 1.14.0) | `V/v02_shiny_src.R` deparse; regex is case-insensitive `^_disable_autoload\.r$` |
| 4 | `runApp` loop `while (!.globals$stopped) serviceApp()`; `runGadget` ends in `runApp`; port picker `p_randomInt(3000, 8000)` = `withPrivateSeed`, with the skip list | confirmed | `V/v02_shiny_src.R` |
| 5 | `httpuv::randomPort()` perturbs `.Random.seed` (same seed gives port 35053); `unsafe_ports` has 67 entries; `tempfile()` does not touch the RNG | confirmed | `V/v03_rng.R`, `httpuv::randomPort` body |
| 6 | Parent RNG untouched by the artifact pipeline | **corrected** (caveat) | `V/v19_rng_chromote.R`: `artifact()` leaves the seed alone, but `chromote::Chromote$new()` changes it (`with_random_port()` → `sample()`); save/restore fixes it |
| 7 | processx Rd: `cleanup`, `supervise`, `windows_detached_process = !cleanup`, interrupt = CTRL+BREAK on Windows | confirmed | `V/v04_rd.R` (installed Rd, 3.8.6) |
| 8 | callr `package = "pkg"` sets the namespace environment | confirmed; default changed to `NULL` in 3.8.0 | `V/v04_rd.R`, `V/v16.R` (callr 3.8.0 Rd) |
| 9 | Interrupting the child: graceful stop, "exit 0" | **corrected** (exit status 1 on callr 3.8.0) | `V/v17_interrupt.R`: callr 3.7.6 exit 0 with "<interrupt: >"; callr 3.8.0 exit 1, no marker; both stop in about 0.08 s |
| 10 | Cleanup matrix E2 (only SIGKILL without supervise/watchdog orphans the child) | confirmed | re-ran `W17/run2/e2_matrix.R`: 12/12 rows identical (`V/e2_rerun_output.txt`) |
| 11 | lib3 + E12 deliverable (snapshot, same-URL v2, cleanup, no runtime files in version dirs) | confirmed (code blocks match the files; re-run reproduces) | `V/e12_rerun.R`, `V/e12_rerun_output.txt`, `V/final_screenshot_v2.png` (Margin 1,641,776) |
| 12 | lib3 `art_static_check()` is correct | **corrected** (2 defects) | `R -e`: empty code gives an unhandled error; `shiny::shinyApp(...)` as the last expression is falsely rejected (§5.1 notes) |
| 13 | lib3 orphan sweep with PID-reuse guard | confirmed (was only tested with lib2 before) | `V/v12_sweep_lib3.R` (synthetic run.json) |
| 14 | Validation ladder E3b (parse/static/launch rejections; render_error, server_crash and js_error caught; validate_msg passes) | confirmed | `V/e3b_rerun_output.txt` |
| 15 | `testServer()` returns NULL; naive run errors; explicit inputs work | confirmed | re-ran `e4_testserver.R` on a copy of `proj_e1` |
| 16 | runApp blocks typed commands (E5b); SIGINT could not stop it in the pty harness | first part confirmed; second **corrected** | `e5b`/`e5c` re-runs: blocked 3/3, but SIGINT stopped runApp 3/3 |
| 17 | In-process httpuv serves live objects only while the console is idle; internal `shiny:::startApp` needs `serviceApp()` pumping (1.13.0) | confirmed | re-ran `e5_inprocess.R` (`V/e5_rerun_output.txt`); httpuv `startServer` Rd on static paths |
| 18 | Fork vs callr (E6): fork shares 2e6 rows; callr ships via RDS | confirmed (timings higher under load: 1.39 s vs 9.51 s) | re-ran `e6_fork.R` |
| 19 | chromote Windows lookup is registry-only; `CHROMOTE_CHROME` first | confirmed; note added on `local_chrome_version()` | `find_chrome`, `find_chrome_windows` bodies (chromote 0.5.1 = current CRAN) |
| 20 | shinylive: CRAN 0.5.0 (2026-06-08), Imports list, assets versions per release, `read_app_files` excludes hidden files and 4 dir names, `max_filesize` "100M" | confirmed (NEWS upgraded LIKELY → VERIFIED) | CRAN index and NEWS pages; shinylive 0.3.0 source and Rd |
| 21 | shinychat Imports ellmer; `chat_append()` accepts string, generator or promise; v0.5.0 dated 2026-09-15 | Imports/Rd confirmed; date **corrected** to 2026-09-09 | CRAN index and NEWS pages; shinychat 0.3.0 Rd |
| 22 | bslib 0.10.0 formals; 25 bootswatch themes; shiny Imports bslib (>= 0.6.0) | confirmed; drift noted (0.11.0 `sidebar(resizable)`) | `V/v08.R`; bslib NEWS |
| 23 | `saveWidget(selfcontained = TRUE)` needs pandoc | confirmed | `htmlwidgets:::pandoc_self_contained_html` errors without pandoc |
| 24 | Anthropic vision: 28×28 patches, `⌈w/28⌉×⌈h/28⌉`, tiers 2576/4784 and 1568/1568, limits (8000 px, 10 MB/5 MB, >20 images → 2000 px, 100/600 images, 32 MB) | confirmed | WebFetch of https://platform.claude.com/docs/en/build-with-claude/vision |
| 25 | OpenAI image tokens: patch formula/multipliers; tile formula 85+170 "for gpt-4o / gpt-4.1 / gpt-5.1" | patch formula confirmed; tile values **corrected** (gpt-5.1 uses 70+140) | WebFetch of https://developers.openai.com/api/docs/guides/images-vision (two fetches) |
| 26 | Gemini: 258 tokens / 768-px tiles; `media_resolution` 280/560/1120/2240, default 1120; 20 MB inline | confirmed | WebFetch of the two ai.google.dev pages |
| 27 | Plot device sizes and token table (E8), replay needs a display list (E8b), token ratios 3.1–3.7× (E9) | confirmed (identical bytes and tokens) | re-ran `e8_plots.R`, `e8b_replay.R`, `e9_tokens.R`; `recordplot.Rd` ("Initially recording is on for screen devices, and off for print devices") |
| 28 | Startup latency and data-shipping costs (proto2) | confirmed qualitatively (same ordering and sizes; times 20–50% higher under load) | `V/proto2_rerun_output.txt` |
| 29 | HTML fallback (E7): iframe srcdoc, file://, in-process static server, saveWidget sizes | confirmed | `V/e7_rerun.R` output |
| 30 | Autoreload: data- or `R/`-only changes do not refresh; legacy watcher warning | confirmed (re-run) | re-ran `e10_autoreload.R`; `shiny:::initAutoReloadMonitor` source |
| 31 | CRAN policy quotes (home filespace, `R_user_dir`, external software, two cores, public API, global env, Internet) | confirmed; `R_user_dir` proviso added | raw policy HTML via curl, plus WebFetch |
| 32 | `R CMD check --as-cran` runs `\donttest`; `:::` triggers a NOTE | confirmed (upgraded from LIKELY) | `tools:::.check_packages` (`_R_CHECK_DONTTEST_EXAMPLES_` defaults to `as_cran`); `tools:::format.check_packages_used` messages |
| 33 | `mcfork` docs warn against GUI front ends; not available on Windows | confirmed (upgraded from LIKELY) | parallel Rd `unix/mcfork.Rd`, `unix/mcparallel.Rd` |
| 34 | rstudioapi `translateLocalUrl`, `viewer` (localhost or tempdir file), `jobRunScript(importEnv)`, `versionInfo()$mode` | confirmed | installed Rd (rstudioapi 0.18.0) |
| 35 | Positron shim quote | confirmed (upgraded to VERIFIED) | WebFetch of the Positron migration page |
| 36 | later docs quote (runs only at the top-level prompt) | confirmed | WebFetch of https://later.r-lib.org/reference/later.html |
| 37 | Posit `are` (29 rows × 7 columns); scores 70.1/66.7/66.7/64.4/64.4; Shiny Assistant blog (2025-02-13) quotes | confirmed; "latest post" softened to UNCERTAIN | WebFetch of vitals, posit.co blog pages |
| 38 | Posit `shiny-bslib` skill content | confirmed (upgraded to VERIFIED) | WebFetch of the GitHub SKILL.md |
| 39 | Quarto dashboards: `server: shiny`, `context: setup/server`, `quarto serve` | confirmed | WebFetch of the quarto.org page |
| 40 | Pi image defaults 2000×2000 px, 4.5 MB base64, JPEG 80 (`image-resize-core.ts:4-29`); `ModelImageResizeOptions` at `types.ts:1073` | confirmed | Pi clone, file:line |
| 41 | Pi "artifact" appears only for session sharing (`docs/usage.md:82`, `docs/sessions.md:58`) | **corrected** (path is `packages/coding-agent/docs/...`; the word is also used for build/plugin outputs) | `grep -rn artifact` in the Pi clone |
| 42 | `.onLoad` → `later::later(sweep)` with `later` not imported | **corrected** (design inconsistency; run the sweep lazily) | §4.2 vs §4.5 |

Not independently verifiable here (left with their original labels): Windows/Linux behaviour,
RStudio/Positron viewer behaviour, Jupyter display, `shinylive::export()` (downloads assets), the
wasm package counts, and absolute latency numbers on a lightly loaded machine.
