# P21 Background sessions (experimental) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `gptr(..., background = TRUE)` return a running session at once and keep it progressing at the idle R console, so that `s |> gptr("...")` steers a running session (S-8, REQ-18, REQ-38).

**Architecture:** One new L3 file, `R/agent-background.R`, provides `bg_register()` (the `bg.register` service that P08's gateway and P14's pause menu call), a `later` timer that runs one non-blocking iteration of P04's process reactor every 50 ms while no reactor pump is on the call stack, and bookkeeping that adds `session` rows to P04's job table. Asks never prompt from a `later` callback: during an idle tick, session-scoped wrappers of every `ui` record (and a `tool_call` hook for the `ask` tool) answer that approval is pending, the sweep after the tick stops the run and parks the session with status `waiting`, and the next blocking gptr call continues it from the denied call, so the model repeats the call and the normal gate asks the user. A `tool_result` hook of the new `builtin:background` prints one notice when an idle-tick `r` call changed workspace bindings.

**Tech Stack:** R (>= 4.2.0); later (Suggests, guarded with `requireNamespace()`); rlang (weak references in one test); testthat 3e and withr (tests only); P01's fake provider and test helpers.

**Spec:** dev/spec/03-architecture.md (§1.3, §2.2, §2.3, §3.2, §5.1, §6.1, §6.2, §6.4, §6.8.2, §9.2), dev/spec/04-interface-contract.md (§1.3, §2.1-2.2, §3.1, §4.2, §5.1, §5.12-5.13, §6.1, §6.5, §7.0, §7.1, §7.2, §7.4, §7.6, §7.11, §7.14, §7.21, §8.2, §10.2 kind 22 `ui`, §10.4, §10.5, §12.1-12.3, §15 IC-33, IC-34, IC-36, IC-53, IC-55, IC-57, IC-71), dev/spec/05-plan-decomposition.md (P21).

**Depends on:** P06, P14 (and through them P01-P05, P07, P08, P11). **Milestone:** M4.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only for closure state), native `|>` (never `%>%`), ASCII-only R sources, `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line required by the executing harness (conventions §10).

Plan-specific requirements (values copied from the spec):

- File and layer: `agent-background.R` | L3 | "experimental background runs serviced by `later`; session rows of the job table" | P21 (03 §3.2). Test file: `tests/testthat/test-agent-background.R` (05 P21).
- Contract row (04 §7.21): `bg_register(s)` (service `bg.register`) | `agent-background.R` | "requires later (`gptr_error_missing_package`); marks the run background, adds a `session` job, ensures the `later` pump (50 ms timer calling `reactor_pump(slice_ms = 0)`, a no-op while the reactor is on the stack, IC-57); R tools of background runs run at idle ticks (`gptr.background_tools = "idle"`) or wait for `gptr_wait()`; an ask moves the run to `waiting` and is shown at the next blocking gptr call; a tool that changed bindings at an idle tick prints one notice" | consumers P08, P14 (`[b]ackground`).
- Service table (04 §7.0): `bg.register` | P21 | `gptr(background = TRUE)` (P08), the pause menu (P14) | `function(session) invisible(session)`. Every service is owned by a built-in (IC-34): this plan declares `builtin:background`.
- Package state (04 §7.0): `the$bg` | P21 | background pump state.
- Option (04 §3.1): `gptr.background_tools` | `chr(1)` | `"idle"` | P21 | `"idle"` or `"wait"`; read with `gptr_opt("background_tools")`.
- Session status (04 §5.1): `waiting` = "a background or served run with an ask pending, IC-57". Live record field (04 §5.1): `background` (list or `NULL`); this plan stores `list(id, run, since, ui, dropped_n, ask, waiting, opts)` there (ids, numbers, flags and a whitelisted copy of the run options; never a session, run, frame or user object).
- Permission answers (04 §10.2 kind 22; P06 `perm_ask()`): an ask raised during an idle tick is answered `list(decision = "deny", remember = NULL, feedback = <pending text>)`, never `"abort"`: P06 turns `"abort"` into the tool result "Permission denied: the user aborted the run. The run stops here.", which the resumed run would show the model. The pending text is `bg_pending_text()`.
- Hooks (04 §10.4): `tool_call` ("decision, error = block"; a handler returns `NULL` or `list(decision = "block", reason)`; payload `tool_name`, `tool_call_id`, `input`, `nested`, `parent_tool_call_id`, `risk` plus `session`) and `tool_result` ("patch chain"; `NULL` = no patch; payload `tool_name`, `tool_call_id`, `input`, `content`, `details`, `is_error`). The `r` tool's `details$objects` is `list(added, modified, removed)` of chr (04 §4.4).
- IC-57: "The background pump is a no-op while the reactor is on the stack (depth > 0)."; "Asks raised outside a blocking gptr call (background runs, ...) never prompt from a `later` callback: a background run moves to status `waiting` (a notice; `gptr_jobs()` shows it) and the ask is shown at the next `gptr_wait()`, `gptr()` or console turn"; "A background R tool that changed bindings in the user's environment at an idle tick prints one notice."
- 03 §6.2: "timer polling every 50 ms; ... no `later_fd`, which LIKELY cannot watch processx pipes on Windows"; "A SIGINT inside a later callback reaches the same calling handler, so the pause menu works"; "Under Rscript there is no idle console: background runs progress only inside blocking gptr calls"; "Support matrix documented: terminal R verified [G3 t9]; RStudio, Positron, Jupyter and Windows consoles unverified. Requires `later`; never used in examples or CRAN tests."
- Job table (04 §7.4, §5.12, IC-36): `job_add(kind, id, name, pid = NA, stop, status = function() "running")`; `gptr_jobs()` (P04) lists columns `id`, `kind` (`session`, `bg`, `artifact`, `mcp_serve`, `worker`, `cli`), `name`, `pid`, `status`, `started`; P21 adds `kind = "session"` rows with `status` `running` or `waiting`.
- Condition (04 §2.2, §6.1.5): `gptr_error_missing_package` with fields `package`, `feature` ("background without later").
- Notices (04 §2.2): message class `gptr_message_notice` through `gptr_inform(message, "notice", .once = NULL)`; silenced by `options(gptr.quiet = TRUE)`; built by concatenation (rule C1).
- Steering relay text (04 §4.2, IC-55): `The user sent this message while you were working: <text>` for the user sources `pipe`, `pause_menu`, `repl`, `api_user`.
- Interrupt policy service (04 §7.0, §7.14): `console.interrupt_policy` = `function(expr_fun, runs, mode = c("call", "repl")) value`; "`mode = "call"` re-signals the interrupt after an abort". Idle ticks use `mode = "repl"`.
- Experimental status (03 §1.3): "`background = TRUE` ... opt-in, documented, excluded from examples and CRAN tests". Every test in the file calls `skip_on_cran()`; tests that need later also call `skip_if_not_installed("later")`. No example anywhere uses `background = TRUE`.
- Dependencies (conventions §8, 03 §9.2): later is a Suggests package ("experimental background sessions (later)"); P21 adds no Import or Suggests.
- Cleanup (04 §7.1): `on_unload(fun)` "registers a zero-argument cleanup run by `.onUnload` (reverse order, each in `try()`)".
- Copy safety (03 §6.4 R1, R2): P21 never holds a user object or a user frame; the job-table and UI closures hold the session id only, never the session.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/agent-background.R` | create | background state `the$bg`; `bg_register()` and the `bg.register` service; `builtin:background`; session-scoped `ui` wrappers; the 50 ms `later` timer and the idle tick; parking (`waiting`) and resume; job rows; change notices; unload cleanup; the `gptr-background` help topic |
| `tests/testthat/test-agent-background.R` | create | unit tests of the helpers and integration tests on the fake provider (all skipped on CRAN) |
| `man/gptr-background.Rd` | generated | by `devtools::document()` in Task 7 |
| `NAMESPACE` | unchanged | P21 exports nothing and registers no S3 method |

## Interfaces used from earlier plans

Exact signatures from `04`; the tasks call nothing else.

| Owner | Function or record | Used for |
|---|---|---|
| P01 `aaa-state.R` | `the`; `on_load(expr)`; `on_unload(fun)`; `ext_service_set(name, fun, provided_by, builtin = NULL)`; `ext_service_get(name)`; `ext_service_has(name)`; `` `%||%` `` | state, declarations, services |
| P01 `utils-options.R` | `gptr_opt(name)` | `gptr.background_tools` |
| P01 `utils-conditions.R` | `gptr_abort(message, class, ..., .data = NULL, call = NULL)`; `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`; `check_class(x, class, arg, null = FALSE)` | conditions, notices, validation |
| P01 `utils-encoding.R`, `provider-message.R` | `as_utf8(x)`; `msg_text(msg)` | notice text, job names |
| P01 tests | `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`; `local_gptr_options(..., .env = parent.frame())`; `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` | tests |
| P02 | `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`; `registry_add(spec, source, rank, session = NULL, state = "active")`; `registry_remove(id)`; `registry_get(kind, name, session = NULL)`; `registry_names(kind, session = NULL)`; `registry_diagnostic(source, event, class, message)`; `gptr_spec(kind, name, ...)`; `gptr_register(spec)`; `gptr_registry(kind = NULL, diagnostics = FALSE)`; API object `gptr$on(event, handler, matcher = NULL)` | built-in, UI wrappers, hook, diagnostics |
| P04 | `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`; `job_add(kind, id, name, pid = NA, stop, status = function() "running")`; `job_remove(id)`; `job_list(kind = NULL)`; `gptr_jobs(kill = FALSE)` | the tick, job rows |
| P06 | `session_data(s)` (`.d`: `id`, `status`, `reason`, `mode`, `turns`, `entries`, `queue`, `dropped`); `session_live(s)` (live: `run`, `background`); `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())`; `run_start(s, input, opts = list())` (run options of 04 §7.6: `max_turns`, `budget`, `returns`, `context`, `timeout`, `interactive`, `depth`, `parent_run`, `agent`, `background`, `rng_state`, `preset`, `tools`, `call`, `safety`, `root`); `run_abort(run, reason = "user")`; `run_current()`; `gptr_run` fields `id`, `opts` | kernel SDK (IC-33) |
| P08 | `gptr(..., background = FALSE, ...)` (calls `ext_service_get("bg.register")(s)`); `gptr_wait(x, timeout = Inf)`; `gptr_cancel(x)`; `gptr_steer(s, text, as = c("steer", "follow_up"))` | entry points, tests |
| P11 | kind `ui` fields `has_ui`, `select(title, choices, default = NULL, details = NULL, multiple = FALSE, allow_other = FALSE)`, `input(prompt, default = "", secret = FALSE)`, `questions(qs)`, `notify(text, level = "info")`, `permission(request)` -> `list(decision = "allow" \| "deny" \| "abort", remember, feedback)`; the `ui.get` service; test helper `local_scripted_ui(answers = list(), .env = parent.frame())` | UI wrappers, waiting tests |
| P14 | service `console.interrupt_policy` `function(expr_fun, runs, mode = c("call", "repl"))`; the pause menu's `[b]ackground` calls `bg.register` | idle ticks under the pause menu |

What this plan produces for later plans: the `bg.register` service (`function(session) invisible(session)`), `builtin:background` (a `tool_call` hook with matcher `ask` and a `tool_result` hook with matcher `r`), `session` rows in the job table (status `running` or `waiting`), the `waiting` session status, the help topic `gptr-background`, and the live-record field `background`.

## How the pieces fit

```text
gptr("job", background = TRUE)                                   (P08 gateway)
  run_start(s, input, opts(background = TRUE)) -> ext_service_get("bg.register")(s)
bg_register(s)        later? -> mark run -> hold s in the$bg -> job row -> ui wrappers -> timer
later timer (50 ms) -> bg_callback()                            (re-armed on exit, always)
  reactor pump on the stack?  yes -> bg_sweep(resume = TRUE): release settled, resume waiting
                              no  -> bg_tick(): ticking = TRUE; reactor_pump(until = bg_once(),
                                     slice_ms = 0, allow_runs = background runs or none)
                                     under console.interrupt_policy (mode "repl"); change notices
                                  -> bg_sweep(resume = FALSE): stop asked runs, park them as
                                     waiting, release settled
ask during an idle tick -> session ui wrapper answers "deny" with the pending text (an `ask`
  call is blocked by the tool_call hook with the same text); the ask is recorded
  -> bg_sweep: run_abort(reason "waiting"), status "waiting", dropped queue items re-queued,
     one notice
next blocking gptr call pumps the reactor -> later::run_now(0) at depth 1 -> bg_callback (busy)
  -> bg_resume(): run_start(s, NULL, kept options) continues after the denied call; the model
     repeats it and the gate asks the user through the real UI
```

---

## Tasks

### Task 1: Background state and pure helpers

**Files:**
- Create: `R/agent-background.R`
- Create: `tests/testthat/test-agent-background.R`

**Interfaces:**
- Consumes: `the`, `` `%||%` `` (P01 `aaa-state.R`); `gptr_opt(name)` (P01); `as_utf8(x)` (P01); `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)` (P04, only compared by identity); test helper `local_gptr_options(..., .env = parent.frame())` (P01).
- Produces (internal, `@noRd`): `bg_state()` (creates `the$bg`: `sessions` env, `cancel`, `ticking`, `ticks`, `changed`), `bg_has_later()`, `bg_get(id)`, `bg_has(id)`, `bg_is_id(id)`, `bg_ids()`, `bg_count()`, `bg_ticking()`, `bg_once()`, `bg_tools_mode()`, `bg_reactor_busy()`, `bg_clean(x)`, `bg_cut(x, n)`, `bg_names_text(nm, max = 6L)`, `bg_request_summary(request)`, the constant `bg_interval = 0.05`.

Why these helpers: IC-57 makes the background pump a no-op while any reactor pump is on the stack; 04 names no accessor for P04's pump depth, so `bg_reactor_busy()` looks for `reactor_pump` itself among the functions of the call stack (frame identity, no frame is kept). `reactor_pump(slice_ms = 0)` with the default `until` would never return, so `bg_once()` stops it after exactly one non-blocking iteration (P04's loop checks `until()` before each iteration: FALSE, one iteration, TRUE). `bg_clean()` blanks C0/C1 controls, bidi and zero-width characters (the IC-53 display rule) through code points, so it gives the same result in a C locale and in UTF-8 locales.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-agent-background.R`:

```r
# test-agent-background.R -- P21 background sessions (experimental; never run on CRAN).

test_that("bg_state() creates the background state once", {
  skip_on_cran()
  old = the$bg
  withr::defer({
    the$bg = old
  })
  the$bg = NULL
  st = bg_state()
  expect_true(is.environment(st))
  expect_identical(bg_state(), st)
  expect_identical(bg_ids(), character())
  expect_identical(bg_count(), 0L)
  expect_false(bg_ticking())
  expect_false(bg_has("s0123456789"))
  expect_false(bg_has(""))
  expect_null(bg_get(NA_character_))
})

test_that("bg_once() stops reactor_pump() after exactly one iteration", {
  skip_on_cran()
  until = bg_once()
  expect_false(until())
  expect_true(until())
  expect_true(until())
})

test_that("bg_clean() and bg_cut() make one safe line in any locale", {
  skip_on_cran()
  x = paste0("a\tb", intToUtf8(0x202e), "c", intToUtf8(0x200b), "d\u0007e")
  expect_identical(bg_clean(x), "a b c d e")
  expect_identical(bg_clean(NA_character_), "")
  expect_identical(bg_clean(character()), character())
  cafe = intToUtf8(c(99L, 97L, 102L, 233L))
  expect_identical(charToRaw(bg_clean(cafe)), charToRaw(cafe))
  expect_identical(bg_cut("  load   the\ncounts ", 40L), "load the counts")
  expect_identical(bg_cut(strrep("x", 50), 10L), "xxxxxxx...")
})

test_that("bg_names_text() and bg_request_summary() build notice text", {
  skip_on_cran()
  expect_identical(bg_names_text(c("a", "b", "a")), "a, b")
  expect_identical(bg_names_text(letters[1:8]), "a, b, c, d, e, f and 2 more")
  expect_identical(bg_names_text(character()), "")
  expect_identical(bg_request_summary(list(tool = "r", summary = c("", "x = 1"))), "r: x = 1")
  expect_identical(bg_request_summary(list(tool = "write", reason = "level 2")), "write: level 2")
  expect_identical(bg_request_summary(list()), "tool: an action")
})

test_that("bg_tools_mode() reads gptr.background_tools", {
  skip_on_cran()
  local_gptr_options(background_tools = NULL)
  expect_identical(bg_tools_mode(), "idle")
  local_gptr_options(background_tools = "wait")
  expect_identical(bg_tools_mode(), "wait")
  local_gptr_options(background_tools = "sometimes")
  expect_identical(bg_tools_mode(), "idle")
})

test_that("bg_reactor_busy() is TRUE only inside a reactor pump", {
  skip_on_cran()
  expect_false(bg_reactor_busy())
  probe = new.env()
  probe$busy = NA
  reactor_pump(until = function() {
    probe$busy = bg_reactor_busy()
    TRUE
  }, slice_ms = 0L, timeout = 5)
  expect_true(probe$busy)
})
```

Note for the test writer: the bidi and zero-width characters are built with `intToUtf8()` so that the test source shows their code points (U+202E, U+200B) and stays ASCII; a `\u202e` escape in a string literal would also parse (checked with R 4.4.3), but never paste the raw characters into a source or plan file.

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`, each test erroring with `could not find function "bg_state"` (and `"bg_once"`, `"bg_clean"`, `"bg_names_text"`, `"bg_tools_mode"`, `"bg_reactor_busy"`).

- [ ] **Step 3: Write the implementation**

Create `R/agent-background.R`:

```r
# agent-background.R -- experimental background sessions (P21; contract 04 section 7.21, IC-57).
#
# gptr(..., background = TRUE) returns a running session at once. A `later` timer pumps the
# process reactor every 50 ms while the console is idle: one non-blocking reactor iteration per
# tick, and nothing at all while any reactor pump is on the call stack (IC-57). There is no
# later_fd(): it LIKELY cannot watch processx pipes on Windows (report 15 section 2.5 and its
# verifier; IC-71). The mechanism was verified in terminal R by report G3 (5), t8, t9 and p6.
# Asks never prompt from a later callback: during an idle tick a session-scoped wrapper of every
# `ui` record answers a denial that tells the model approval is pending (an `ask` call is blocked
# the same way), the sweep after the tick stops the run and parks the session with status
# `waiting`, and the next blocking gptr call continues it, where the gate asks the user.

#' Seconds between two background ticks (04 section 7.21)
#' @noRd
bg_interval = 0.05

#' The background pump state `the$bg` (owned by P21, 04 section 7.0), created on first use
#' @noRd
bg_state = function() {
  st = the$bg
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$sessions = new.env(parent = emptyenv())
    st$cancel = NULL
    st$ticking = FALSE
    st$ticks = 0L
    st$changed = list()
    the$bg = st
  }
  st
}

#' Is the later package available? (mocked in tests)
#' @noRd
bg_has_later = function() {
  requireNamespace("later", quietly = TRUE)
}

#' The background session with id `id`, or NULL
#' @noRd
bg_get = function(id) {
  if (!bg_is_id(id)) return(NULL)
  get0(id, envir = bg_state()$sessions, inherits = FALSE)
}

#' Is `id` a registered background session?
#' @noRd
bg_has = function(id) {
  bg_is_id(id) && exists(id, envir = bg_state()$sessions, inherits = FALSE)
}

#' Is `id` a usable session id string?
#' @noRd
bg_is_id = function(id) {
  is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
}

#' Ids of the registered background sessions, sorted
#' @noRd
bg_ids = function() {
  ls(bg_state()$sessions, sorted = TRUE)
}

#' Number of registered background sessions
#' @noRd
bg_count = function() {
  length(bg_ids())
}

#' Is an idle tick pumping the reactor right now?
#' @noRd
bg_ticking = function() {
  isTRUE(bg_state()$ticking)
}

#' An `until` function for reactor_pump() that allows exactly one non-blocking iteration
#' @noRd
bg_once = function() {
  n = new.env(parent = emptyenv())
  n$i = 0L
  function() {
    n$i = n$i + 1L
    n$i > 1L
  }
}

#' The `gptr.background_tools` mode: "wait" or "idle" (anything else reads as "idle")
#' @noRd
bg_tools_mode = function() {
  if (identical(gptr_opt("background_tools"), "wait")) "wait" else "idle"
}

#' Is a reactor pump on the call stack? (IC-57: the background pump is then a no-op)
#' @noRd
bg_reactor_busy = function() {
  n = sys.nframe()
  i = 1L
  while (i < n) {
    if (identical(sys.function(i), reactor_pump)) return(TRUE)
    i = i + 1L
  }
  FALSE
}

#' Replace C0/C1 controls, bidi and zero-width characters by spaces (locale independent)
#' @noRd
bg_clean = function(x) {
  x = as_utf8(as.character(x))
  vapply(x, function(s) {
    if (is.na(s)) return("")
    cp = utf8ToInt(s)
    if (anyNA(cp)) return(s)
    bad = cp < 32L | (cp >= 127L & cp <= 159L) | (cp >= 0x200bL & cp <= 0x200fL) |
      (cp >= 0x202aL & cp <= 0x202eL) | (cp >= 0x2066L & cp <= 0x2069L) | cp == 0xfeffL
    cp[bad] = 32L
    intToUtf8(cp)
  }, "", USE.NAMES = FALSE)
}

#' One line of at most `n` characters, whitespace collapsed, cut with an ASCII ellipsis
#' @noRd
bg_cut = function(x, n) {
  x = paste(bg_clean(x), collapse = " ")
  x = gsub("[[:space:]]+", " ", trimws(x))
  if (nchar(x) > n) x = paste0(substr(x, 1L, n - 3L), "...")
  x
}

#' Object names for a notice: at most `max` names, then "and N more"
#' @noRd
bg_names_text = function(nm, max = 6L) {
  nm = unique(bg_clean(nm))
  nm = nm[nzchar(trimws(nm))]
  if (!length(nm)) return("")
  shown = paste(nm[seq_len(min(length(nm), max))], collapse = ", ")
  if (length(nm) > max) shown = paste0(shown, " and ", length(nm) - max, " more")
  shown
}

#' One line describing a permission request for the waiting notice
#' @noRd
bg_request_summary = function(request) {
  lines = c(request$summary, request$reason)
  lines = lines[nzchar(trimws(lines %||% ""))]
  first = if (length(lines)) lines[[1L]] else "an action"
  bg_cut(paste0(request$tool %||% "tool", ": ", first), 100L)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 28 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): add background-session state and helpers"
```

---

### Task 2: Session-scoped UI wrappers that never prompt during an idle tick

**Files:**
- Modify: `R/agent-background.R` (append)
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: `registry_get(kind, name, session = NULL)`, `registry_names(kind, session = NULL)`, `registry_add(spec, source, rank, session = NULL, state = "active")`, `registry_remove(id)`, `gptr_spec(kind, name, ...)`, `gptr_register(spec)` (P02); `session_live(s)` (P06); `gptr_abort()` (P01); in tests `run_start(s, input, opts = list())`, `run_abort(run, reason = "user")` (P06), `gptr()` with `.run = FALSE` (P08) and `gptr_fake_provider()` (P01).
- Produces (internal): `bg_pending_text(what = "approval")` (the text the model reads when an ask could not be shown), `bg_park(id, what, summary)` (records `live$background$ask = list(what, summary, t)`; the first ask wins; it never stops the run), `bg_ui_target(name)`, `bg_ui_spec(name, id)` (a `gptr_ui` spec with the six `ui` methods of 04 §10.2 kind 22), `bg_install_ui(id)` (-> chr of registry record ids).

How it works: `ui.get` (P11) resolves the run's UI by name through the registry, and `registry_get(kind, name, session)` lets a rank-0 record scoped to one session shadow the global record of the same name for that session only (04 §7.2, §10.1). `bg_install_ui()` registers such a wrapper for every registered `ui` name. Outside an idle tick every method delegates to the global record, so a background session asks exactly like a foreground one inside blocking calls. During an idle tick (`the$bg$ticking`) no method prompts: `permission()` records the ask and answers `list(decision = "deny", remember = NULL, feedback = bg_pending_text("approval"))`; `questions()`, `select()` and `input()` record the ask and return a cancelled answer. The answer is a denial, never `"abort"`: P06's `perm_ask()` turns `"abort"` into the tool result "Permission denied: the user aborted the run. The run stops here." and the tool-call message stays complete (only a streaming partial is marked aborted), so a resumed run would tell the model that the user aborted, the model would not repeat the call, and the user would never be asked. The pending text tells the model that nothing ran, that nobody declined, and to call the tool again when the session continues. The wrappers never stop the run themselves (they run inside P06's dispatcher, in the middle of a call); the sweep after the tick does (Task 4), and Task 5 turns the stopped run into a `waiting` session.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
bg_fixture = function(.env = parent.frame()) {
  s = gptr("background fixture", model = gptr_fake_provider(list("ok")), .run = FALSE,
           envir = new.env())
  id = s$id
  assign(id, s, envir = bg_state()$sessions)
  live = session_live(s)
  live$background = list(id = id, run = NULL, ui = character(), dropped_n = 0L, ask = NULL,
                         waiting = FALSE, opts = list(background = TRUE))
  withr::defer({
    the$bg = NULL
  }, envir = .env)
  s
}

bg_recording_ui = function(calls, .env = parent.frame()) {
  permission = function(request) {
    calls$n = calls$n + 1L
    list(decision = "allow", remember = NULL, feedback = NULL)
  }
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    1L
  }
  spec = gptr_spec("ui", "bgtest", has_ui = function() TRUE, select = select,
                   input = function(prompt, default = "", secret = FALSE) "typed",
                   questions = function(qs) list(answers = list(q1 = "yes"), cancelled = FALSE),
                   notify = function(text, level = "info") invisible(NULL),
                   permission = permission)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(off)
}

test_that("a session UI wrapper delegates outside idle ticks and never prompts during them", {
  skip_on_cran()
  calls = new.env()
  calls$n = 0L
  bg_recording_ui(calls)
  s = bg_fixture()
  ui = bg_ui_spec("bgtest", s$id)
  req = list(tool = "r", summary = "x = 1", reason = "level 1", session = s$id, turn = 1L)
  expect_s3_class(ui, "gptr_ui")
  expect_true(ui$has_ui())
  expect_identical(ui$permission(req)$decision, "allow")
  expect_identical(ui$input("name?"), "typed")
  expect_identical(calls$n, 1L)
  st = bg_state()
  st$ticking = TRUE
  ans = ui$permission(req)
  expect_true(ui$questions(list())$cancelled)
  expect_identical(ui$select("pick", c("a", "b")), NA_integer_)
  expect_identical(ui$input("name?"), NA_character_)
  st$ticking = FALSE
  expect_identical(ans$decision, "deny")
  expect_match(ans$feedback, "runs in the background", fixed = TRUE)
  expect_match(ans$feedback, "call the tool again with the same input", fixed = TRUE)
  expect_identical(calls$n, 1L)
  ask = session_live(s)$background$ask
  expect_identical(ask$what, "permission")
  expect_identical(ask$summary, "r: x = 1")
})

test_that("bg_install_ui() shadows every ui record for that session only", {
  skip_on_cran()
  calls = new.env()
  calls$n = 0L
  bg_recording_ui(calls)
  s = bg_fixture()
  ids = bg_install_ui(s$id)
  expect_true(length(ids) >= 1L)
  expect_identical(length(ids), length(registry_names("ui")))
  global = registry_get("ui", "bgtest")
  wrapped = registry_get("ui", "bgtest", session = s$id)
  expect_false(identical(wrapped, global))
  expect_identical(wrapped$permission(list(tool = "r", summary = "y = 2"))$decision, "allow")
  expect_identical(calls$n, 1L)
  for (rid in ids) registry_remove(rid)
  expect_identical(registry_get("ui", "bgtest", session = s$id), global)
})

test_that("bg_park() records the first ask only and never stops the run itself", {
  skip_on_cran()
  s = bg_fixture()
  run = run_start(s, NULL, opts = list())
  withr::defer(run_abort(run))
  expect_true(bg_park(s$id, "input", "Which file?"))
  expect_true(bg_park(s$id, "permission", "second"))
  ask = session_live(s)$background$ask
  expect_identical(ask$what, "input")
  expect_identical(ask$summary, "Which file?")
  expect_identical(s$status, "running")
  expect_false(bg_park("s_not_a_background_session", "input", "x"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 28 ]`; the three new tests error with `could not find function "bg_ui_spec"`, `could not find function "bg_install_ui"` and `could not find function "bg_park"`.

- [ ] **Step 3: Write the implementation**

Append to `R/agent-background.R`:

```r
#' The text the model reads when an ask could not be shown at an idle tick (IC-57)
#'
#' P06 wraps a permission denial as "Permission denied: <this>. ..." and a blocked tool call as
#' "Tool execution was blocked: <this>", so the model learns that nothing ran, that nobody
#' declined, and that repeating the call later reaches the user.
#' @noRd
bg_pending_text = function(what = "approval") {
  paste0("the user could not be asked for ", what, " because this session runs in the ",
         "background; the session now waits for the user, and when it continues, call the tool ",
         "again with the same input and the user will be asked")
}

#' Record that the background session `id` needs a human (the first ask wins)
#'
#' Called from the dispatcher during an idle tick, so it never stops the run itself: the sweep
#' after the tick aborts the run before it can make another request (Tasks 4 and 5).
#' @noRd
bg_park = function(id, what, summary) {
  s = bg_get(id)
  if (is.null(s)) return(invisible(FALSE))
  live = session_live(s)
  if (is.null(live) || is.null(live$background)) return(invisible(FALSE))
  bg = live$background
  if (is.null(bg$ask)) {
    bg$ask = list(what = what, summary = bg_cut(summary, 100L), t = as.numeric(Sys.time()))
    live$background = bg
  }
  invisible(TRUE)
}

#' The global `ui` record `name` (the target of a session wrapper)
#' @noRd
bg_ui_target = function(name) {
  ui = registry_get("ui", name)
  if (is.null(ui)) {
    gptr_abort(paste0("The UI backend '", name, "' is no longer registered."), "not_available",
               member = name, provided_by = "P11")
  }
  ui
}

#' A session-scoped wrapper of the `ui` record `name`: delegates, but never prompts in a tick
#'
#' During an idle tick `permission()` answers a denial whose feedback says that approval is
#' pending (never "abort": P06 would tell the model that the user aborted the run), and
#' `select()`, `input()` and `questions()` answer "cancelled". Each records the ask.
#' @noRd
bg_ui_spec = function(name, id) {
  force(name)
  force(id)
  gptr_spec("ui", name,
    has_ui = function() isTRUE(bg_ui_target(name)$has_ui()),
    select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                      allow_other = FALSE) {
      if (bg_ticking()) {
        bg_park(id, "select", title)
        return(NA_integer_)
      }
      bg_ui_target(name)$select(title, choices, default = default, details = details,
                                multiple = multiple, allow_other = allow_other)
    },
    input = function(prompt, default = "", secret = FALSE) {
      if (bg_ticking()) {
        bg_park(id, "input", prompt)
        return(NA_character_)
      }
      bg_ui_target(name)$input(prompt, default = default, secret = secret)
    },
    questions = function(qs) {
      if (bg_ticking()) {
        bg_park(id, "questions", "a question from the agent")
        return(list(answers = structure(list(), names = character()), cancelled = TRUE))
      }
      bg_ui_target(name)$questions(qs)
    },
    notify = function(text, level = "info") {
      bg_ui_target(name)$notify(text, level = level)
    },
    permission = function(request) {
      if (bg_ticking()) {
        bg_park(id, "permission", bg_request_summary(request))
        return(list(decision = "deny", remember = NULL, feedback = bg_pending_text("approval")))
      }
      bg_ui_target(name)$permission(request)
    }
  )
}

#' Register a session-scoped wrapper for every registered `ui` record; returns the record ids
#' @noRd
bg_install_ui = function(id) {
  ids = character()
  for (nm in registry_names("ui")) {
    ids = c(ids, registry_add(bg_ui_spec(nm, id), source = "session", rank = 0L, session = id))
  }
  ids
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 54 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): add session-scoped UI wrappers that never prompt at idle ticks"
```

---

### Task 3: `bg_register()`, the `bg.register` service, `builtin:background` and job rows

**Files:**
- Modify: `R/agent-background.R` (append)
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: `on_load(expr)`, `on_unload(fun)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_has(name)`, `ext_service_get(name)` and the rule of P01's `service_builtin_active()` (a built-in that has no record in a non-empty registry counts as filtered out, so its bootstrap services are hidden), `check_class(x, class, arg, null = FALSE)`, `gptr_inform()`, `msg_text(msg)` (P01); `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, the API object's `gptr$on(event, handler, matcher = NULL)` with the `tool_call` event (04 §10.4: "decision, error = block"; a handler returns `NULL` or `list(decision = "block", reason)`), and in tests `gptr_registry()`, `registry_get(kind, name, session = NULL)` (P02); `job_add(kind, id, name, pid = NA, stop, status = function() "running")`, `job_remove(id)`, `job_list(kind = NULL)`, `gptr_jobs(kill = FALSE)` (P04); `session_data(s)`, `session_live(s)`, `run_start(s, input, opts = list())`, `run_abort(run, reason = "user")` (P06); `gptr(..., background = TRUE)` (P08, which calls the service).
- Produces: service `bg.register` = `bg_register(s)` -> `invisible(s)` (04 §7.0, §7.21); `builtin:background` (declared with `ext_declare_builtin("background", builtin_background)`; it owns the service, IC-34, and from this task on its factory registers the `tool_call` hook `gptr$on("tool_call", bg_on_tool_call, matcher = "ask")`, so a record of source `builtin:background` exists whenever the built-in is loaded and P01's `service_builtin_active()` keeps `bg.register` visible; the service itself stays a bootstrap entry, never a `service` record, so a test stub set with `ext_service_set()`, as P14's pause-menu test does, still replaces it); `bg_on_tool_call(event, ctx)` (during an idle tick a background session's `ask` call is blocked with `bg_pending_text("answers")` and the ask is recorded; Task 5 parks the session); internal `bg_has_queued(d)`, `bg_keep_opts` (chr), `bg_run_opts(run)` (the whitelisted run options plus `background = TRUE`), `bg_mark(run)` (sets `run$opts$background = TRUE`), `bg_track(s, run, title)`, `bg_job_fns(id)`, `bg_job_status(id)`, `bg_title(s)`, `bg_stop(id)`, `bg_release(id, notice)`, `bg_notice_done(s)`, `bg_shutdown()` (registered with `on_unload()`); job rows `kind = "session"`, `id` = the session id, `name` = the first prompt (40 characters), `status` = the session status.

Behaviour of `bg_register(s)`, in order: a non-session or a detached copy is `gptr_error_invalid_argument`; without later it signals `gptr_error_missing_package` (`package = "later"`, `feature = "background sessions"`) and first aborts a run that P08 started for the background (`run$opts$background` already `TRUE`), so nothing is left unpumped; a live run (P08's background start, or a foreground run sent to the background from the pause menu) is marked with `run$opts$background = TRUE`, which is what lets P06's foreground wait return for `[b]ackground`; an idle session with queued input (the `.run = FALSE` example of 04 §7.21) is started with `run_start(s, NULL, opts = list(background = TRUE))`; an idle session with nothing queued is `gptr_error_invalid_argument`. It then holds the session in `the$bg$sessions` (a running session is held by the reactor anyway; P21 releases it at settlement), records `live$background` (including `opts = bg_run_opts(run)`: `max_turns`, `budget`, `returns`, `context`, `timeout`, `preset`, `tools`, `root`, `agent` and `depth` of the background run, so a run resumed after waiting keeps the call's limits; never `call`, which holds the caller's frame [R2], nor `safety`, which is snapshotted again at resume, IC-53), adds the job row, installs the UI wrappers and prints the one-time experimental notice. Task 4 adds the timer.

Why the factory registers a record already in this task: P01's `service_builtin_active()` treats a built-in without any record in a non-empty registry as filtered out (every built-in of 04 §10.3 registers at least one record), so a factory that registered nothing would hide `bg.register` (`ext_service_has()` FALSE, `ext_service_get()` signalling `gptr_error_not_available`, and `gptr(background = TRUE)` failing with that class instead of `gptr_error_missing_package`). The record is the `ask` hook that the final built-in has anyway (04 §10.3 reading A6), not a `service` record: built-ins own their services through the bootstrap table (IC-34), and a built-in `service` record would shadow the stub that P14's test "[b]ackground hands a foreground run to bg.register (P21) and resumes" sets with `ext_service_set()`. Until Task 5 parks sessions, the Task 4 sweep stops a run whose `ask` call was blocked, as it stops any run with a recorded ask.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
test_that("bg.register is a service provided by P21 and owned by builtin:background", {
  skip_on_cran()
  expect_true("builtin:background" %in% gptr_registry()$source)
  expect_null(registry_get("service", "bg.register"))
  expect_true(ext_service_has("bg.register"))
  expect_true(is.function(ext_service_get("bg.register")))
})

test_that("an ask tool call at an idle tick is blocked and recorded, never shown", {
  skip_on_cran()
  s = bg_fixture()
  ev = list(type = "tool_call", session = s$id, tool_name = "ask", tool_call_id = "c1",
            input = list())
  expect_null(bg_on_tool_call(ev, NULL))
  st = bg_state()
  st$ticking = TRUE
  out = bg_on_tool_call(ev, NULL)
  other = bg_on_tool_call(list(type = "tool_call", session = "s_other", tool_name = "ask"), NULL)
  st$ticking = FALSE
  expect_identical(out$decision, "block")
  expect_match(out$reason, "call the tool again with the same input", fixed = TRUE)
  expect_null(other)
  expect_identical(session_live(s)$background$ask$what, "questions")
})

test_that("without later, background runs fail with gptr_error_missing_package", {
  skip_on_cran()
  local_mocked_bindings(bg_has_later = function() FALSE)
  fake = gptr_fake_provider(list("ok"))
  s = gptr("idle job", model = fake, .run = FALSE, envir = new.env())
  cnd = expect_error(bg_register(s), class = "gptr_error_missing_package")
  expect_identical(cnd$package, "later")
  expect_identical(cnd$feature, "background sessions")
  expect_identical(s$status, "idle")
  expect_error(gptr("x", model = fake, envir = new.env(), background = TRUE),
               class = "gptr_error_missing_package")
  expect_false(bg_has(s$id))
})

test_that("bg_run_opts() keeps the options a resumed run needs, never a frame or a snapshot", {
  skip_on_cran()
  run = list(opts = list(max_turns = 5L, budget = list(tokens = 100), call = new.env(),
                         safety = list(can_prompt = TRUE), doc = list(path = "a.R"),
                         background = FALSE, timeout = 30))
  expect_identical(bg_run_opts(run), list(max_turns = 5L, budget = list(tokens = 100),
                                          timeout = 30, background = TRUE))
  expect_identical(bg_run_opts(list(opts = NULL)), list(background = TRUE))
})

test_that("bg_register() starts a queued session in the background (contract 7.21 example)", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = gptr("long job", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
           envir = new.env())
  res = withVisible(ext_service_get("bg.register")(s))
  expect_false(res$visible)
  expect_identical(res$value, s)
  expect_identical(s$status, "running")
  expect_true(isTRUE(session_live(s)$run$opts$background))
  expect_true(bg_has(s$id))
  expect_true(length(session_live(s)$background$ui) >= 1L)
  expect_true(isTRUE(session_live(s)$background$opts$background))
  jobs = gptr_jobs()
  row = jobs[jobs$id == s$id, , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(row$kind, "session")
  expect_match(row$name, "long job", fixed = TRUE)
  expect_identical(row$status, "running")
})

test_that("bg_register() marks a running foreground run (the pause menu's [b]ackground)", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = gptr("foreground", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
           envir = new.env())
  run = run_start(s, NULL, opts = list())
  expect_false(isTRUE(run$opts$background))
  bg_register(s)
  expect_true(isTRUE(run$opts$background))
  expect_identical(session_live(s)$background$run, run$id)
})

test_that("an idle session without queued input cannot run in the background", {
  skip_on_cran()
  skip_if_not_installed("later")
  s = gptr("done already", model = gptr_fake_provider(list("ok")), envir = new.env())
  expect_identical(s$status, "idle")
  expect_error(bg_register(s), class = "gptr_error_invalid_argument")
  expect_error(bg_register("not a session"), class = "gptr_error_invalid_argument")
})

test_that("gptr_jobs(kill = TRUE) and bg_shutdown() stop background sessions", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  hang = gptr_fake_provider(list(list(hang = TRUE)))
  a = gptr("first", model = hang, .run = FALSE, envir = new.env())
  b = gptr("second", model = hang, .run = FALSE, envir = new.env())
  bg_register(a)
  bg_register(b)
  gptr_jobs(kill = TRUE)
  expect_identical(a$status, "aborted")
  expect_false(bg_has(a$id))
  expect_false(a$id %in% gptr_jobs()$id)
  expect_identical(b$status, "aborted")
  c1 = gptr("third", model = hang, .run = FALSE, envir = new.env())
  bg_register(c1)
  bg_shutdown()
  expect_identical(c1$status, "aborted")
  expect_null(the$bg)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: the 54 expectations of Tasks 1-2 pass and the eight new tests fail: `"builtin:background" %in% gptr_registry()$source is not TRUE`, `ext_service_has("bg.register") is not TRUE`, `gptr_error_not_available` from `ext_service_get("bg.register")`, `could not find function "bg_on_tool_call"`, `could not find function "bg_run_opts"`, and `could not find function "bg_register"` / `could not find function "bg_shutdown"` in the others (the summary line shows `FAIL` greater than 0).

- [ ] **Step 3: Write the implementation**

Append to `R/agent-background.R`:

```r
on_load(ext_declare_builtin("background", builtin_background))
on_load(ext_service_set("bg.register", bg_register, provided_by = "P21",
                        builtin = "background"))
on_load(on_unload(bg_shutdown))

#' The `builtin:background` factory: owns the bg.register service, blocks idle-tick `ask` calls
#'
#' The hook is also the built-in's record: P01's service_builtin_active() hides the bootstrap
#' services of a built-in that registered nothing (IC-34). The service stays a bootstrap entry.
#' @noRd
builtin_background = function(gptr) {
  gptr$on("tool_call", bg_on_tool_call, matcher = "ask")
  invisible(NULL)
}

#' `tool_call` hook (matcher "ask"): during an idle tick, a background session's `ask` call is
#' blocked with the pending text instead of reaching ui$questions(), and the ask is recorded
#' @noRd
bg_on_tool_call = function(event, ctx) {
  if (!bg_ticking()) return(NULL)
  id = event$session %||% ""
  if (!bg_has(id)) return(NULL)
  bg_park(id, "questions", "a question from the agent")
  list(decision = "block", reason = bg_pending_text("answers"))
}

#' Run a session in the background (service `bg.register`, 04 section 7.21) [experimental]
#' @noRd
bg_register = function(s) {
  check_class(s, "gptr_session", "s")
  live = session_live(s)
  if (is.null(live)) {
    gptr_abort(c("A detached copy cannot run in the background.",
                 "Continue it with gptr_resume() first."),
               "invalid_argument", arg = "s", expected = "a live session")
  }
  run = live$run
  if (!bg_has_later()) {
    if (!is.null(run) && isTRUE(run$opts$background)) run_abort(run, reason = "missing_package")
    gptr_abort(c("Background sessions need the 'later' package.",
                 "Install it with install.packages(\"later\"),",
                 "or call gptr() without background = TRUE."),
               "missing_package", package = "later", feature = "background sessions")
  }
  title = bg_title(s)
  if (is.null(run)) {
    if (!bg_has_queued(session_data(s))) {
      gptr_abort("The session is not running and has no queued input to run in the background.",
                 "invalid_argument", arg = "s",
                 expected = "a running session or a session with queued input (.run = FALSE)")
    }
    run = run_start(s, NULL, opts = list(background = TRUE))
  }
  bg_mark(run)
  bg_track(s, run, title)
  invisible(s)
}

#' Does the session data hold queued steers or follow-ups?
#' @noRd
bg_has_queued = function(d) {
  q = d$queue
  (length(q$steer) + length(q$follow_up)) > 0L
}

#' Run options (04 section 7.6) that a resumed background run keeps: never `call` (it holds the
#' caller's frame, rule R2), `safety` (re-snapshotted at resume, IC-53), `doc`, `parent_run`,
#' `interactive` or `rng_state`
#' @noRd
bg_keep_opts = c("max_turns", "budget", "returns", "context", "timeout", "preset", "tools",
                 "root", "agent", "depth")

#' The options of a run to start again for the same background session
#' @noRd
bg_run_opts = function(run) {
  o = run$opts %||% list()
  o = o[intersect(names(o), bg_keep_opts)]
  o$background = TRUE
  o
}

#' Mark a run as a background run (`run$opts$background`, 04 section 7.6)
#' @noRd
bg_mark = function(run) {
  opts = run$opts %||% list()
  opts$background = TRUE
  run$opts = opts
  invisible(run)
}

#' Hold the session, record its live `background` handle, add its job row, install UI wrappers
#'
#' The handle is `list(id, run, since, ui, dropped_n, ask, waiting, opts)`: the session id, the id
#' of the background run, the start time, the ids of the session UI records, the length of
#' `.d$dropped` when the run started, the pending ask, the waiting flag and the run options kept
#' for a resumed run. It holds no session, run, frame or user object.
#' @noRd
bg_track = function(s, run, title) {
  d = session_data(s)
  id = d$id
  live = session_live(s)
  if (bg_has(id) && !is.null(live$background)) {
    bg = live$background
    bg$run = run$id
    bg$ask = NULL
    bg$waiting = FALSE
    bg$dropped_n = length(d$dropped)
    live$background = bg
    return(invisible(FALSE))
  }
  assign(id, s, envir = bg_state()$sessions)
  live$background = list(id = id, run = run$id, since = as.numeric(Sys.time()),
                         ui = bg_install_ui(id), dropped_n = length(d$dropped),
                         ask = NULL, waiting = FALSE, opts = bg_run_opts(run))
  fns = bg_job_fns(id)
  job_add("session", id, title, pid = NA_integer_, stop = fns$stop, status = fns$status)
  gptr_inform(c("Background sessions are experimental.",
                "See help(\"gptr-background\") for the consoles where they are supported."),
              "notice", .once = "background_experimental")
  invisible(TRUE)
}

#' The job-table closures of a background session; they hold the id only (never the session)
#' @noRd
bg_job_fns = function(id) {
  force(id)
  list(stop = function() bg_stop(id), status = function() bg_job_status(id))
}

#' The job-table status of a background session: its session status
#' @noRd
bg_job_status = function(id) {
  s = bg_get(id)
  if (is.null(s)) return("done")
  session_data(s)$status %||% "running"
}

#' A short job name: the first prompt of the session
#' @noRd
bg_title = function(s) {
  d = session_data(s)
  txt = NULL
  for (e in d$entries) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      txt = msg_text(e$message)
      break
    }
  }
  if (is.null(txt)) {
    q = c(d$queue$follow_up, d$queue$steer)
    if (length(q)) txt = q[[1L]]$text
  }
  if (is.null(txt) || !nzchar(trimws(txt))) txt = d$id
  bg_cut(txt, 40L)
}

#' Stop a background session (the job table's `stop`, gptr_jobs(kill = TRUE))
#' @noRd
bg_stop = function(id) {
  s = bg_get(id)
  if (is.null(s)) return(invisible(FALSE))
  live = session_live(s)
  if (!is.null(live) && !is.null(live$run)) {
    run_abort(live$run, reason = "user")
  } else if (identical(session_data(s)$status, "waiting")) {
    d = session_data(s)
    d$status = "aborted"
    d$reason = "cancelled while waiting for approval"
  }
  bg_release(id, notice = FALSE)
  invisible(TRUE)
}

#' Forget a background session: job row, UI wrappers, live handle, strong reference
#' @noRd
bg_release = function(id, notice) {
  s = bg_get(id)
  if (!is.null(s)) {
    live = session_live(s)
    if (!is.null(live) && !is.null(live$background)) {
      for (rid in live$background$ui %||% character()) registry_remove(rid)
      live$background = NULL
    }
    if (isTRUE(notice)) bg_notice_done(s)
  }
  if (id %in% job_list(kind = "session")$id) job_remove(id)
  st = bg_state()
  if (exists(id, envir = st$sessions, inherits = FALSE)) rm(list = id, envir = st$sessions)
  invisible(NULL)
}

#' The notice printed when a background session settles at an idle console
#' @noRd
bg_notice_done = function(s) {
  d = session_data(s)
  status = d$status %||% "idle"
  if (identical(status, "idle")) {
    turns = as.integer(d$turns %||% 0L)
    gptr_inform(paste0("Background session ", d$id, " finished (", turns,
                       if (identical(turns, 1L)) " turn)." else " turns)."), "notice")
  } else {
    why = d$reason %||% ""
    why = if (nzchar(why)) paste0(": ", bg_cut(why, 120L)) else ""
    gptr_inform(paste0("Background session ", d$id, " stopped with status ", status, why, "."),
                "notice")
  }
  invisible(NULL)
}

#' Unload cleanup (registered with on_unload()): cancel the timer, stop every session
#' @noRd
bg_shutdown = function() {
  st = the$bg
  if (is.null(st)) return(invisible(NULL))
  if (!is.null(st$cancel)) try(st$cancel(), silent = TRUE)
  st$cancel = NULL
  for (id in ls(st$sessions)) try(bg_stop(id), silent = TRUE)
  the$bg = NULL
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 94 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): register background sessions through the bg.register service"
```

---

### Task 4: The `later` pump, the idle tick and release at settlement

**Files:**
- Modify: `R/agent-background.R` (edit `bg_register()`, append)
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: `later::later(func, delay = 0)` (returns a cancel function), `later::run_now(timeoutSecs = 0L, all = TRUE)` (tests); `reactor_pump()` (P04); `registry_diagnostic(source, event, class, message)`, `ext_service_has()`, `ext_service_get("console.interrupt_policy")` (P01/P02, service of P14); `run_abort()` (P06); `gptr_wait()`, `gptr_cancel()`, `gptr_steer()` through the pipe (P08); `gptr_jobs()` (P04).
- Produces (internal): `bg_ensure_pump()`, `bg_guard(event, expr)`, `bg_callback()`, `bg_runs()`, `bg_tick()`, `bg_with_policy(fun, runs)`, `bg_sweep(idle)` (Task 5 replaces it with `bg_sweep(idle, resume)`).

How it works: `bg_ensure_pump()` arms one `later::later(bg_callback, 0.05)` while background sessions exist; it never creates `the$bg`, so a callback that fires after `bg_shutdown()` cannot revive the state. `bg_callback()` first cancels any other armed handle (so a manual call never leaves two timer chains) and re-arms through `on.exit()`, so neither an error nor an interrupt can stop the chain while sessions exist; then it either runs an idle tick (no reactor pump on the stack) or does bookkeeping only (a blocking gptr call is pumping; IC-57). The idle tick sets `the$bg$ticking`, runs `reactor_pump(until = bg_once(), slice_ms = 0L, allow_runs = <ids>)` under P14's interrupt policy in `"repl"` mode (abort-only when P14 is absent), where `<ids>` are the background runs with `gptr.background_tools = "idle"` and `character()` with `"wait"` (explicit ids also keep a suspended foreground run's queued tools waiting); a session with a recorded ask is not ticked again. The tick and the sweep are guarded separately by `bg_guard()`: an error never escapes the callback (`later::run_now()` would re-raise it at the console) and becomes a `builtin:background` diagnostic, and a failing tick never skips the sweep. The sweep first aborts (reason `"waiting"`) any run of a session with a recorded ask, so a denied call is never retried at the next tick (Task 5 then parks such a session instead of releasing it), and releases sessions whose run settled: job row removed, UI wrappers removed, `live$background` cleared, the strong reference dropped (so an unreferenced settled session can be collected), and a notice when the settlement was seen at the idle console.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
bg_pump_until = function(cond, timeout = 20) {
  t0 = Sys.time()
  while (!isTRUE(cond()) && as.numeric(difftime(Sys.time(), t0, units = "secs")) < timeout) {
    later::run_now(0.05)
  }
  isTRUE(cond())
}

bg_has_assistant = function(s) {
  "assistant" %in% vapply(s$messages, function(m) m$role, "")
}

test_that("a background run progresses while the test pumps later::run_now()", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_gptr_options(background_tools = "idle")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "x = 1"), delay = 0.1),
                                 list(text = "done", delay = 0.1)))
  e = new.env()
  s = gptr("long job", model = fake, mode = "auto", envir = e, background = TRUE)
  expect_s3_class(s, "gptr_session")
  expect_identical(s$status, "running")
  expect_true(s$id %in% gptr_jobs()$id)
  expect_true(bg_pump_until(function() !identical(s$status, "running")))
  expect_identical(s$status, "idle")
  expect_identical(s$text, "done")
  expect_identical(e$x, 1)
  expect_identical(length(fake$log$requests), 2L)
  expect_true(bg_state()$ticks > 0L)
  expect_true(bg_pump_until(function() !bg_has(s$id)))
  expect_false(s$id %in% gptr_jobs()$id)
})

test_that("the background tick is a no-op while a reactor pump is on the stack", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = gptr("hang", model = gptr_fake_provider(list(list(hang = TRUE))), envir = new.env(),
           background = TRUE)
  st = bg_state()
  before = st$ticks
  reactor_pump(until = function() {
    bg_callback()
    TRUE
  }, slice_ms = 0L, timeout = 5)
  expect_identical(st$ticks, before)
  bg_callback()
  expect_identical(st$ticks, before + 1L)
  expect_identical(s$status, "running")
})

test_that("a pipe into a running background session steers it after the tool result", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_gptr_options(background_tools = "wait")
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "y = 2")), "used TPM"))
  e = new.env()
  s = gptr("normalise the counts", model = fake, mode = "auto", envir = e, background = TRUE)
  expect_true(bg_pump_until(function() bg_has_assistant(s)))
  expect_identical(s$status, "running")
  expect_null(e$y)
  res = withVisible(s |> gptr("Use TPM, not CPM"))
  expect_false(res$visible)
  expect_identical(res$value, s)
  expect_identical(s$status, "running")
  expect_identical(length(session_data(s)$queue$steer), 1L)
  gptr_wait(s, timeout = 20)
  expect_identical(s$status, "idle")
  expect_identical(e$y, 2)
  expect_identical(s$text, "used TPM")
  msgs = fake$log$requests[[2]]$messages
  roles = vapply(msgs, function(m) m$role, "")
  texts = vapply(msgs, msg_text, "")
  i_result = max(which(roles == "tool_result"))
  i_steer = which(grepl("Use TPM, not CPM", texts, fixed = TRUE))
  expect_identical(i_steer, i_result + 1L)
  expect_match(texts[[i_steer]],
               "The user sent this message while you were working: Use TPM, not CPM",
               fixed = TRUE)
})

test_that("gptr_cancel() aborts a background session and releases its job", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  fake = gptr_fake_provider(list(list(hang = TRUE)))
  s = gptr("long task", model = fake, envir = new.env(), background = TRUE)
  expect_true(bg_pump_until(function() length(fake$log$requests) >= 1L))
  gptr_cancel(s)
  expect_identical(s$status, "aborted")
  expect_true(bg_pump_until(function() !bg_has(s$id)))
  expect_false(s$id %in% gptr_jobs()$id)
})

test_that("an unreferenced settled background session is collected", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  s = gptr("short job", model = gptr_fake_provider(list("done")), envir = new.env(),
           background = TRUE)
  w = rlang::new_weakref(s)
  id = s$id
  expect_true(bg_pump_until(function() !bg_has(id)))
  expect_identical(rlang::wref_key(w)$status, "idle")
  gptr("replace the last session", model = gptr_fake_provider(list("ok")), envir = new.env())
  rm(s)
  invisible(gc())
  invisible(gc())
  expect_null(rlang::wref_key(w))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: the 94 earlier expectations pass; the new tests fail: `could not find function "bg_callback"`, and `bg_pump_until(...) is not TRUE` after the 20 s timeouts because nothing pumps the background runs yet (the red run takes about 80 s).

- [ ] **Step 3: Write the implementation**

Replace the whole definition of `bg_register()` (from its roxygen title `#' Run a session in the background ...` to its closing brace) with this version, which arms the timer before returning (the only change is the `bg_ensure_pump()` line):

```r
#' Run a session in the background (service `bg.register`, 04 section 7.21) [experimental]
#' @noRd
bg_register = function(s) {
  check_class(s, "gptr_session", "s")
  live = session_live(s)
  if (is.null(live)) {
    gptr_abort(c("A detached copy cannot run in the background.",
                 "Continue it with gptr_resume() first."),
               "invalid_argument", arg = "s", expected = "a live session")
  }
  run = live$run
  if (!bg_has_later()) {
    if (!is.null(run) && isTRUE(run$opts$background)) run_abort(run, reason = "missing_package")
    gptr_abort(c("Background sessions need the 'later' package.",
                 "Install it with install.packages(\"later\"),",
                 "or call gptr() without background = TRUE."),
               "missing_package", package = "later", feature = "background sessions")
  }
  title = bg_title(s)
  if (is.null(run)) {
    if (!bg_has_queued(session_data(s))) {
      gptr_abort("The session is not running and has no queued input to run in the background.",
                 "invalid_argument", arg = "s",
                 expected = "a running session or a session with queued input (.run = FALSE)")
    }
    run = run_start(s, NULL, opts = list(background = TRUE))
  }
  bg_mark(run)
  bg_track(s, run, title)
  bg_ensure_pump()
  invisible(s)
}
```

Then append to `R/agent-background.R`:

```r
#' Arm the 50 ms later timer when background sessions exist and none is armed
#'
#' Never creates `the$bg`: after bg_shutdown() a late callback must not revive the state.
#' @noRd
bg_ensure_pump = function() {
  st = the$bg
  if (is.null(st) || !is.null(st$cancel) || !length(ls(st$sessions))) return(invisible(FALSE))
  st$cancel = later::later(bg_callback, bg_interval)
  invisible(TRUE)
}

#' Evaluate `expr`; an error becomes a `builtin:background` diagnostic (later::run_now() would
#' re-raise it at the console)
#' @noRd
bg_guard = function(event, expr) {
  tryCatch(expr, error = function(e) {
    registry_diagnostic("builtin:background", event, class(e)[1L], conditionMessage(e))
    invisible(NULL)
  })
}

#' The later callback: an idle tick, or bookkeeping only while a reactor pump is on the stack
#'
#' The timer is re-armed on exit, even after an interrupt, so the chain never stops while
#' background sessions exist; the tick and the sweep are guarded separately, so a failing tick
#' never skips the sweep that stops a run with a pending ask.
#' @noRd
bg_callback = function() {
  st = bg_state()
  pending = st$cancel
  st$cancel = NULL
  if (!is.null(pending)) pending()
  on.exit(bg_ensure_pump(), add = TRUE)
  idle = !bg_reactor_busy()
  if (idle) bg_guard("tick", bg_tick())
  bg_guard("sweep", bg_sweep(idle = idle))
  invisible(NULL)
}

#' Live runs of the background sessions (a session with a recorded ask is not ticked again)
#' @noRd
bg_runs = function() {
  out = list()
  for (id in bg_ids()) {
    live = session_live(bg_get(id))
    if (is.null(live) || is.null(live$run) || !is.null(live$background$ask)) next
    out[[length(out) + 1L]] = live$run
  }
  out
}

#' One idle tick: one non-blocking reactor iteration under the interrupt policy
#' @noRd
bg_tick = function() {
  runs = bg_runs()
  if (!length(runs)) return(invisible(FALSE))
  st = bg_state()
  allow = character()
  if (identical(bg_tools_mode(), "idle")) allow = vapply(runs, function(r) r$id, "")
  st$ticking = TRUE
  on.exit({
    st$ticking = FALSE
  }, add = TRUE)
  st$ticks = st$ticks + 1L
  bg_with_policy(function() {
    reactor_pump(until = bg_once(), slice_ms = 0L, allow_runs = allow)
  }, runs)
  invisible(TRUE)
}

#' Run `fun` under the console interrupt policy (P14) in "repl" mode, else abort-only
#' @noRd
bg_with_policy = function(fun, runs) {
  if (ext_service_has("console.interrupt_policy")) {
    return(ext_service_get("console.interrupt_policy")(fun, runs, mode = "repl"))
  }
  tryCatch(fun(), interrupt = function(cnd) {
    for (run in runs) run_abort(run, reason = "user")
    invisible(NULL)
  })
}

#' Bookkeeping after a tick or inside a blocking pump: stop asked runs, release settled sessions
#' @noRd
bg_sweep = function(idle) {
  for (id in bg_ids()) {
    live = session_live(bg_get(id))
    if (is.null(live) || is.null(live$background)) {
      bg_release(id, notice = FALSE)
      next
    }
    if (!is.null(live$run) && !is.null(live$background$ask)) {
      run_abort(live$run, reason = "waiting")
    }
    if (is.null(live$run)) bg_release(id, notice = idle)
  }
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 127 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): pump background sessions from a later timer at the idle console"
```

---

### Task 5: Asks at an idle tick park the session as `waiting`; the next blocking call resumes it

**Files:**
- Modify: `R/agent-background.R` (replace `bg_callback()` and `bg_sweep()`, append)
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: `session_data(s)` (writes `status` and `reason` for the `waiting` transition that 04 §7.21 and IC-57 assign to P21), `session_live(s)`, `session_enqueue(s, text, as = "follow_up", source, blocks)`, `run_start(s, input, opts = list())`, `run_abort()`, `run_current()` (P06); `gptr_inform()` (P01); `registry_diagnostic()` (P02); Task 3's `bg_on_tool_call()` (the `tool_call` hook that `builtin:background` registers with matcher `ask`); test helpers `local_scripted_ui(answers = list(), .env = parent.frame())` (P11) and `bg_fixture()` (Task 2).
- Produces (internal): `bg_sweep(idle, resume)`, `bg_wait_label(ask)`, `bg_park_session(s)`, `bg_resume(s)` (`builtin:background` keeps Task 3's factory, whose `tool_call` hook records an idle-tick `ask` call that this task now parks); the session status `waiting` with `reason = "waiting for approval: <tool>: <first line>"` (or `"waiting for an answer: ..."` for `ask`, `select`, `input` and `questions`); job status `waiting`.

How it works: during an idle tick a UI wrapper (Task 2) answered a denial with the pending text and recorded the ask; an `ask` tool call is blocked earlier, by Task 3's `tool_call` hook, with the same text (P06 shows it as "Tool execution was blocked: ..."), because a cancelled `questions()` answer would only tell the model that the user dismissed the questions. Right after the tick, `bg_sweep()` aborts the run with reason `"waiting"` (whichever run of the session asked: the background run, or a run that `gptr_wait()` or `gptr_step()` started on it), so the model never sees the denial at an idle tick and makes no further request. `bg_park_session()` then re-queues as follow-ups the queue items that this abort moved to `.d$dropped` (so a steer piped in meanwhile is not lost; items without text are skipped), sets `.d$status = "waiting"` and `.d$reason`, and prints one notice. Idle ticks never resume a waiting session. When a blocking gptr call pumps the reactor (`gptr()`, `gptr_wait()`, `gptr_step()`, a console turn), P04's outermost pump calls `later::run_now(0)`, `bg_callback()` sees the pump on the stack and, when no run is executing a tool (`run_current()` is `NULL`), `bg_resume()` starts a run with `run_start(s, NULL, opts = <kept options>)`. P06 continues from the leaf: the transcript ends with the denied (or blocked) call and its result, so the model reads the pending text and repeats the call, and the gate now asks through the real UI inside the blocking call (one more model request). A run that `gptr_wait()` or `gptr_step()` starts on a waiting session with queued input supersedes the ask; a pipe into a waiting session queues a steer (P08 treats `waiting` like `running`), which that run or the resumed run receives; a session whose status someone else changed is released; `gptr_jobs(kill = TRUE)` sets a waiting session to `aborted`. A waiting session that cannot continue (for example a transcript that ends with a final answer, so `run_start()` has nothing to run) is set to `aborted` with one diagnostic and released, never left waiting.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
bg_capture_notices = function(fun) {
  log = new.env()
  log$m = character()
  withCallingHandlers(fun(), gptr_message_notice = function(m) {
    log$m = c(log$m, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  log$m
}

test_that("an ask at an idle tick parks the run as waiting until a blocking pump", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  ui = local_scripted_ui(answers = list("y"))
  local_gptr_options(background_tools = "idle", record = "off", verbose = 0L)
  reply = list(tool = "r", input = list(code = "z = 3"))
  fake = gptr_fake_provider(list(reply, reply, "done"))
  e = new.env()
  s = gptr("set z", model = fake, mode = "manual", envir = e, background = TRUE)
  expect_true(bg_pump_until(function() identical(s$status, "waiting")))
  expect_identical(nrow(ui$log), 0L)
  expect_null(e$z)
  jobs = gptr_jobs()
  expect_identical(jobs$status[jobs$id == s$id], "waiting")
  for (i in 1:5) later::run_now(0.06)
  expect_identical(s$status, "waiting")
  reactor_pump(until = function() !(s$status %in% c("running", "waiting")), slice_ms = 50L,
               timeout = 20)
  expect_identical(s$status, "idle")
  expect_identical(e$z, 3)
  expect_identical(ui$log$method, "permission")
  texts = vapply(fake$log$requests[[2L]]$messages, msg_text, "")
  expect_true(any(grepl("call the tool again with the same input", texts, fixed = TRUE)))
  expect_true(bg_pump_until(function() !bg_has(s$id)))
})

test_that("gptr_jobs(kill = TRUE) cancels a waiting background session", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  ui = local_scripted_ui(answers = list())
  local_gptr_options(background_tools = "idle", record = "off", verbose = 0L)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "w = 1")), "done"))
  s = gptr("set w", model = fake, mode = "manual", envir = new.env(), background = TRUE)
  expect_true(bg_pump_until(function() identical(s$status, "waiting")))
  gptr_jobs(kill = TRUE)
  expect_identical(s$status, "aborted")
  expect_false(bg_has(s$id))
  expect_identical(nrow(ui$log), 0L)
})

test_that("parking prints one waiting notice naming the action", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_scripted_ui(answers = list())
  local_gptr_options(background_tools = "idle", record = "off", verbose = 0L, quiet = FALSE)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "v = 1")), "done"))
  notes = bg_capture_notices(function() {
    s = gptr("set v", model = fake, mode = "manual", envir = new.env(), background = TRUE)
    bg_pump_until(function() identical(s$status, "waiting"))
  })
  expect_length(grep("is waiting for approval: r", notes, fixed = TRUE), 1L)
})

test_that("a waiting session that cannot continue is aborted and released", {
  skip_on_cran()
  s = gptr("finished", model = gptr_fake_provider(list("ok")), envir = new.env())
  assign(s$id, s, envir = bg_state()$sessions)
  withr::defer({
    the$bg = NULL
  })
  live = session_live(s)
  live$background = list(id = s$id, run = NULL, ui = character(), dropped_n = 0L,
                         ask = list(what = "permission", summary = "r: x = 1"), waiting = TRUE,
                         opts = list(background = TRUE))
  d = session_data(s)
  d$status = "waiting"
  expect_null(bg_resume(s))
  expect_identical(s$status, "aborted")
  expect_match(s$reason, "could not continue after waiting", fixed = TRUE)
  expect_false(bg_has(s$id))
  expect_null(session_live(s)$background)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: the 127 earlier expectations pass; the three integration tests fail with `bg_pump_until(function() identical(s$status, "waiting")) is not TRUE` (the Task 4 sweep aborts the asked run and releases the session with status `aborted` instead of parking it) and `grep("is waiting for approval: r", notes, fixed = TRUE)` of length 0 instead of 1; the unit test errors with `could not find function "bg_resume"`.

- [ ] **Step 3: Write the implementation**

Replace the whole definition of `bg_callback()` (from its roxygen title `#' The later callback: ...` to its closing brace) with:

```r
#' The later callback: an idle tick, or bookkeeping only while a reactor pump is on the stack
#'
#' The timer is re-armed on exit, even after an interrupt, so the chain never stops while
#' background sessions exist; the tick and the sweep are guarded separately, so a failing tick
#' never skips the sweep that stops a run with a pending ask. Waiting sessions are resumed only
#' inside a blocking pump and only while no tool executes (`run_current()` is NULL).
#' @noRd
bg_callback = function() {
  st = bg_state()
  pending = st$cancel
  st$cancel = NULL
  if (!is.null(pending)) pending()
  on.exit(bg_ensure_pump(), add = TRUE)
  idle = !bg_reactor_busy()
  resume = !idle && !isTRUE(st$ticking) && is.null(run_current())
  if (idle) bg_guard("tick", bg_tick())
  bg_guard("sweep", bg_sweep(idle = idle, resume = resume))
  invisible(NULL)
}
```

Replace the whole definition of `bg_sweep()` (from its roxygen title `#' Bookkeeping after a tick ...` to its closing brace) with:

```r
#' Bookkeeping after a tick or inside a blocking pump: stop, park, resume, release
#'
#' A run with a recorded ask (whichever run it is) is aborted before it can make another request;
#' a session whose run was stopped for an ask is parked as `waiting`; a new run on a waiting
#' session (gptr_wait() or gptr_step() started its queued input) supersedes the ask; a waiting
#' session is resumed only when `resume` is TRUE; everything else that settled is released.
#' @noRd
bg_sweep = function(idle, resume) {
  for (id in bg_ids()) {
    s = bg_get(id)
    live = session_live(s)
    if (is.null(live) || is.null(live$background)) {
      bg_release(id, notice = FALSE)
      next
    }
    bg = live$background
    run = live$run
    if (!is.null(run) && !is.null(bg$ask) && !isTRUE(bg$waiting)) {
      run_abort(run, reason = "waiting")
      run = live$run
    }
    if (!is.null(run)) {
      if (isTRUE(bg$waiting)) {
        bg$ask = NULL
        bg$waiting = FALSE
        bg$run = run$id
        bg$dropped_n = length(session_data(s)$dropped)
        live$background = bg
      }
      next
    }
    if (!is.null(bg$ask) && !isTRUE(bg$waiting)) bg_park_session(s)
    if (isTRUE(live$background$waiting)) {
      if (!identical(session_data(s)$status, "waiting")) {
        bg_release(id, notice = FALSE)
      } else if (isTRUE(resume)) {
        bg_resume(s)
      }
      next
    }
    bg_release(id, notice = idle)
  }
  invisible(NULL)
}
```

Append to `R/agent-background.R` (`builtin_background()` and `bg_on_tool_call()` stay as written in Task 3):

```r
#' "approval" for a permission ask, "an answer" for the other asks
#' @noRd
bg_wait_label = function(ask) {
  if (identical(ask$what, "permission")) "approval" else "an answer"
}

#' Park a background session whose run was stopped for an ask: status `waiting` (IC-57)
#'
#' Queue items that this abort moved to `.d$dropped` (a steer piped in meanwhile) are queued again
#' as follow-ups with their source, so the resumed run receives them.
#' @noRd
bg_park_session = function(s) {
  d = session_data(s)
  live = session_live(s)
  bg = live$background
  n0 = bg$dropped_n %||% 0L
  dropped = d$dropped %||% list()
  if (length(dropped) > n0) {
    for (it in dropped[seq.int(n0 + 1L, length(dropped))]) {
      txt = it$text
      if (!is.character(txt) || length(txt) != 1L || is.na(txt) || !nzchar(txt)) next
      session_enqueue(s, txt, as = "follow_up", source = it$source %||% "api_user",
                      blocks = it$blocks %||% list())
    }
  }
  bg$dropped_n = length(d$dropped)
  bg$waiting = TRUE
  live$background = bg
  label = bg_wait_label(bg$ask)
  d$status = "waiting"
  d$reason = paste0("waiting for ", label, ": ", bg$ask$summary)
  gptr_inform(c(paste0("Background session ", d$id, " is waiting for ", label, ": ",
                       bg$ask$summary, "."),
                "It continues at your next gptr_wait(), gptr() call or console turn;",
                "gptr_jobs() lists it."),
              "notice")
  invisible(s)
}

#' Continue a waiting session inside a blocking gptr call, where its gate can ask the user
#'
#' The new run continues from the leaf (the denied or blocked call and its result), so the model
#' repeats the call and the gate asks through the real UI. A session that cannot continue is
#' aborted and released (one diagnostic), never left waiting.
#' @noRd
bg_resume = function(s) {
  d = session_data(s)
  live = session_live(s)
  bg = live$background
  run = tryCatch(run_start(s, NULL, opts = bg$opts %||% list(background = TRUE)),
                 error = function(e) e)
  if (inherits(run, "error")) {
    registry_diagnostic("builtin:background", "resume", class(run)[1L], conditionMessage(run))
    if (identical(d$status, "waiting")) {
      d$status = "aborted"
      d$reason = paste0("could not continue after waiting: ", conditionMessage(run))
    }
    bg_release(d$id, notice = FALSE)
    return(invisible(NULL))
  }
  bg_mark(run)
  bg$ask = NULL
  bg$waiting = FALSE
  bg$run = run$id
  bg$dropped_n = length(d$dropped)
  live$background = bg
  invisible(run)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 147 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): park idle-tick asks as waiting and resume at the next blocking call"
```

---

### Task 6: One notice when an idle-tick `r` call changed workspace bindings

**Files:**
- Modify: `R/agent-background.R` (replace `builtin_background()` and `bg_tick()`, append)
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: the API object's `gptr$on(event, handler, matcher = NULL)` (P02); the `tool_result` event (04 §10.4: patch chain, payload `tool_name`, `tool_call_id`, `input`, `content`, `details`, `is_error`; handlers return `NULL` for no patch) and the `r` tool's `details$objects = list(added, modified, removed)` (04 §4.4, P10); `gptr_registry()` (P02).
- Produces (internal): `builtin:background` now registers two hooks, `gptr$on("tool_call", bg_on_tool_call, matcher = "ask")` (Task 3) and `gptr$on("tool_result", bg_on_tool_result, matcher = "r")`; `bg_on_tool_result(event, ctx)`; `bg_flush_changes()`; the notice `Background session <id> changed <names> in your workspace.`

How it works: the hook only records (never prints: it runs inside the dispatcher, where output could land in a tool's capture), and only during an idle tick, only for a background session, and never for plan mode (plan mode evaluates in a scratch overlay, not the user's workspace). After the tick's pump returns, `bg_flush_changes()` prints one notice per recorded `r` result. Foreground calls never produce the notice.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
test_that("an r tool that changed bindings at an idle tick prints one notice", {
  skip_on_cran()
  skip_if_not_installed("later")
  withr::defer(bg_shutdown())
  local_gptr_options(background_tools = "idle", quiet = FALSE)
  fake = gptr_fake_provider(list(list(tool = "r", input = list(code = "made_in_bg = 1")), "ok"))
  e = new.env()
  notes = bg_capture_notices(function() {
    s = gptr("make it", model = fake, mode = "auto", envir = e, background = TRUE)
    bg_pump_until(function() !bg_has(s$id))
  })
  expect_identical(e$made_in_bg, 1)
  expect_length(grep("changed made_in_bg in your workspace", notes, fixed = TRUE), 1L)
  fg = gptr_fake_provider(list(list(tool = "r", input = list(code = "made_fg = 2")), "ok"))
  notes2 = bg_capture_notices(function() {
    gptr("make it here", model = fg, mode = "auto", envir = e)
  })
  expect_identical(e$made_fg, 2)
  expect_length(grep("made_fg", notes2, fixed = TRUE), 0L)
  expect_true("builtin:background" %in% gptr_registry()$source)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: the 147 earlier expectations pass; the new test fails with `grep("changed made_in_bg in your workspace", notes, fixed = TRUE)` of length 0 instead of 1 (nothing records `r` results yet; its last expectation already passes, because Task 3's factory registers the `tool_call` hook under the source `builtin:background`).

- [ ] **Step 3: Write the implementation**

Replace the whole definition of `builtin_background()` (its roxygen block and the function, as written in Task 3) with:

```r
#' The `builtin:background` factory: owns the bg.register service, blocks idle-tick `ask` calls,
#' watches r results
#'
#' The hooks are also the built-in's records: P01's service_builtin_active() hides the bootstrap
#' services of a built-in that registered nothing (IC-34). The service stays a bootstrap entry.
#' @noRd
builtin_background = function(gptr) {
  gptr$on("tool_call", bg_on_tool_call, matcher = "ask")
  gptr$on("tool_result", bg_on_tool_result, matcher = "r")
  invisible(NULL)
}
```

Replace the whole definition of `bg_tick()` (from its roxygen title `#' One idle tick: ...` to its closing brace) with:

```r
#' One idle tick: one non-blocking reactor iteration under the interrupt policy
#' @noRd
bg_tick = function() {
  runs = bg_runs()
  if (!length(runs)) return(invisible(FALSE))
  st = bg_state()
  allow = character()
  if (identical(bg_tools_mode(), "idle")) allow = vapply(runs, function(r) r$id, "")
  st$ticking = TRUE
  on.exit({
    st$ticking = FALSE
  }, add = TRUE)
  st$ticks = st$ticks + 1L
  bg_with_policy(function() {
    reactor_pump(until = bg_once(), slice_ms = 0L, allow_runs = allow)
  }, runs)
  bg_flush_changes()
  invisible(TRUE)
}
```

Append to `R/agent-background.R`:

```r
#' `tool_result` hook (matcher "r"): remember names an idle-tick r call changed
#' @noRd
bg_on_tool_result = function(event, ctx) {
  if (!bg_ticking()) return(NULL)
  id = event$session %||% ""
  s = bg_get(id)
  if (is.null(s) || identical(session_data(s)$mode, "plan")) return(NULL)
  nm = unique(as.character(unlist(event$details$objects, use.names = FALSE)))
  if (length(nm)) {
    st = bg_state()
    st$changed[[length(st$changed) + 1L]] = list(id = id, names = nm)
  }
  NULL
}

#' Print one notice per r result that changed bindings during the tick
#' @noRd
bg_flush_changes = function() {
  st = bg_state()
  items = st$changed
  st$changed = list()
  for (it in items) {
    gptr_inform(paste0("Background session ", it$id, " changed ", bg_names_text(it$names),
                       " in your workspace."), "notice")
  }
  invisible(length(items))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 152 ]`

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R
git commit -m "feat(agent): notify when an idle-tick r call changes workspace bindings"
```

---

### Task 7: The `gptr-background` help topic, the examples guard and the copy-safety row

**Files:**
- Modify: `R/agent-background.R` (insert a roxygen topic)
- Generated: `man/gptr-background.Rd`
- Test: `tests/testthat/test-agent-background.R` (append)

**Interfaces:**
- Consumes: `devtools::document()`; `tools::parse_Rd()`; `expect_no_copy()` (P01 `helper-tracemem.R`).
- Produces: the help topic `gptr-background` (alias `background-sessions`) documenting the experimental status, the behaviour, the support matrix and the option `gptr.background_tools` (P25 copies the option text into `?gptr_options`, 04 §3.1).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-agent-background.R`:

```r
test_that("the gptr-background topic documents the status, the matrix and the option", {
  skip_on_cran()
  man = testthat::test_path("..", "..", "man")
  skip_if_not(dir.exists(man), "man/ is not available (installed tests)")
  rd = file.path(man, "gptr-background.Rd")
  expect_true(file.exists(rd))
  txt = paste(readLines(rd, encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "experimental", fixed = TRUE)
  expect_match(txt, "Support matrix", fixed = TRUE)
  expect_match(txt, "gptr.background_tools", fixed = TRUE)
})

test_that("no example uses background = TRUE", {
  skip_on_cran()
  man = testthat::test_path("..", "..", "man")
  skip_if_not(dir.exists(man), "man/ is not available (installed tests)")
  hits = character()
  for (f in list.files(man, pattern = "[.]Rd$", full.names = TRUE)) {
    rd = tools::parse_Rd(f)
    tags = vapply(rd, function(x) attr(x, "Rd_tag") %||% "", "")
    ex = paste(unlist(rd[tags == "\\examples"]), collapse = "")
    if (grepl("background[[:space:]]*=[[:space:]]*TRUE", ex)) hits = c(hits, basename(f))
  }
  expect_identical(hits, character())
})

test_that("a settled background run leaves the caller's object editable in place", {
  skip_on_cran()
  skip_if_not_installed("later")
  wait_loop = paste0("while (identical(s$status, 'running') && ",
                     "as.numeric(Sys.time() - t0, units = 'secs') < 20) later::run_now(0.05)")
  start = "s = gptr('describe big', big, model = gptr_fake_provider(list('ok')), background = TRUE)"
  action = paste(start, "t0 = Sys.time()", wait_loop, "for (i in 1:5) later::run_now(0.06)",
                 sep = "\n")
  expect_no_copy(setup = "big = runif(5e6)", action = action,
                 label = "background run with context, then settled")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: the 152 earlier expectations, the examples guard and the copy-safety row pass; the topic test fails with `file.exists(rd) is not TRUE` and a `cannot open file '.../man/gptr-background.Rd'` error.

- [ ] **Step 3: Write the implementation**

Insert this block into `R/agent-background.R` directly after the file's header comment (after its last line, ``# `waiting`, and the next blocking gptr call continues it, where the gate asks the user.``, and the blank line that follows it) and before `#' Seconds between two background ticks (04 section 7.21)`:

```r
#' Background sessions (experimental)
#'
#' @description
#' \code{gptr(..., background = TRUE)} returns the session at once while its run keeps going.
#' A timer from the \pkg{later} package advances the run every 50 ms while the R console is
#' idle, so you can keep working. Piping into the running session,
#' \code{s |> gptr("...")}, queues a steer that the agent receives after its current tool
#' result; \code{\link{gptr_wait}()} waits for the session, \code{\link{gptr_cancel}()}
#' aborts its run and \code{\link{gptr_jobs}()} lists it. Background sessions are
#' \strong{experimental}: they need the \pkg{later} package, and they are never used in
#' examples or in CRAN tests.
#'
#' @section How a background run behaves:
#' \itemize{
#'   \item Streams progress at every idle tick. While a blocking gptr call runs
#'     (\code{gptr()}, \code{gptr_wait()}, \code{gptr_step()} or a console turn), that call
#'     advances the background runs as well and the background timer does nothing.
#'   \item R tools of a background run execute at an idle tick when
#'     \code{options(gptr.background_tools = "idle")} (the default). The console is busy
#'     while such a tool runs; Ctrl-C then opens the pause menu. With \code{"wait"} they run
#'     only inside a blocking gptr call such as \code{gptr_wait()}.
#'   \item A background run never asks a question at the idle console. When it needs an
#'     approval or an answer at an idle tick, the action is not performed: the agent is told
#'     that the user will be asked, its run stops, and the session moves to status
#'     \code{"waiting"} with a notice. At your next \code{gptr_wait()}, \code{gptr()} call or
#'     console turn the session continues with one more model request, the agent repeats the
#'     call, and you are asked as usual. A message piped into a waiting session is delivered
#'     when it continues.
#'   \item \code{gptr_cancel()} stops a running background session. A waiting session has no
#'     run to cancel: \code{gptr_jobs(kill = TRUE)} stops it (together with every other job).
#'   \item When an R tool changed objects in your workspace at an idle tick, one notice
#'     names them.
#'   \item Under Rscript, knitr and Quarto there is no idle console: background runs
#'     progress only inside blocking gptr calls.
#' }
#'
#' @section Support matrix:
#' \tabular{ll}{
#'   \strong{Front end} \tab \strong{Status} \cr
#'   Terminal R on macOS \tab verified: idle ticks, pause menu, pipe steering \cr
#'   Terminal R on Linux \tab unverified (the same \pkg{later} event loop as macOS) \cr
#'   Rscript, knitr, Quarto \tab no idle ticks by design; progress inside blocking gptr calls \cr
#'   RStudio \tab unverified (\pkg{later} is expected to run callbacks at its idle console) \cr
#'   Positron, Jupyter (IRkernel), Rgui \tab unverified \cr
#'   Windows consoles \tab unverified; a timer polls the reactor, so child pipes are served
#' }
#'
#' @section Options:
#' \describe{
#'   \item{\code{gptr.background_tools}}{\code{"idle"} (default) or \code{"wait"}: whether
#'     R tools of background runs execute at idle ticks or wait for the next blocking gptr
#'     call.}
#' }
#'
#' @seealso \code{\link{gptr}}, \code{\link{gptr_wait}}, \code{\link{gptr_cancel}},
#'   \code{\link{gptr_steer}}, \code{\link{gptr_jobs}}
#' @name gptr-background
#' @aliases background-sessions
NULL
```

Then regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: the output includes `Writing 'gptr-background.Rd'`; `git diff --exit-code NAMESPACE` exits with status 0 (NAMESPACE unchanged).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 158 ]` (with later installed and `capabilities("profmem")` TRUE; otherwise the copy row reports one SKIP).

Run: `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); print(lintr::lint("R/agent-background.R")); print(lintr::lint("tests/testthat/test-agent-background.R"))'`

Expected: `No lints found.` twice (the repository `.lintr` of conventions §4; the namespace is loaded first because the `object_usage_linter` of `linters_with_defaults()` otherwise reports every internal helper as "no visible global function definition", P01 acceptance A3).

Run: `Rscript --vanilla -e 'devtools::test(filter = "arch-layers|lint-rules")'`

Expected: a summary line with `FAIL 0 | WARN 0` (P01's architecture and lint tests; this file calls only L0-L2 functions, the kernel SDK and the declared service `console.interrupt_policy`).

- [ ] **Step 5: Commit**

```bash
git add R/agent-background.R tests/testthat/test-agent-background.R man/gptr-background.Rd
git commit -m "docs(agent): document background sessions and their support matrix"
```

---

## Plan acceptance

Every acceptance check of P21 in `05-plan-decomposition.md` (P21 has no separate "Review amendments" bullet; its IC-57 and IC-36 amendments are part of its scope and are listed after the three checks).

| # | Acceptance check (05, P21) | Proved by |
|---|---|---|
| 1 | `devtools::test(filter = "agent-background")` is green; tests skip without later and on CRAN | Task 7 Step 4 (all 30 tests, 158 expectations); every test calls `skip_on_cran()`; the 14 tests that need later call `skip_if_not_installed("later")` |
| 2a | A background run on the fake provider progresses while the test pumps `later::run_now()` | Task 4, "a background run progresses while the test pumps later::run_now()" |
| 2b | `s \|> gptr("x")` returns invisibly at once and the steer is delivered after the current tool result | Task 4, "a pipe into a running background session steers it after the tool result" (invisible, same object, still running, one queued steer; in request 2 the relay is the message right after the tool result) |
| 2c | `gptr_wait(s)` settles it | the same Task 4 test (`gptr_wait(s, timeout = 20)` then status `idle`) |
| 2d | `gptr_cancel(s)` aborts it | Task 4, "gptr_cancel() aborts a background session and releases its job" |
| 2e | An unreferenced settled background session is collected | Task 4, "an unreferenced settled background session is collected" (weak reference key is `NULL` after `gc()`) |
| 3a | `background = TRUE` without later errors with `gptr_error_missing_package` | Task 3, "without later, background runs fail with gptr_error_missing_package" (direct service call and `gptr(background = TRUE)`, fields `package`, `feature`) |
| 3b | It is never used in examples | Task 7, "no example uses background = TRUE" (scans the `\examples` sections of every `man/*.Rd`) |
| IC-57 | Background pump is a no-op while the reactor is on the stack | Task 1 (`bg_reactor_busy()` inside `reactor_pump()`), Task 4 ("the background tick is a no-op while a reactor pump is on the stack") |
| IC-57 | Asks never prompt from a `later` callback; the run moves to `waiting`; `gptr_jobs()` shows it; shown at the next blocking call | Task 2 ("a session UI wrapper delegates outside idle ticks and never prompts during them": a denial with the pending text, never `abort`), Task 3 ("an ask tool call at an idle tick is blocked and recorded, never shown"), Task 5 ("an ask at an idle tick parks the run as waiting until a blocking pump": no UI call at idle ticks, job status `waiting`, request 2 carries the pending text, one `permission` prompt inside the blocking pump; "gptr_jobs(kill = TRUE) cancels a waiting background session"; "parking prints one waiting notice naming the action"; "a waiting session that cannot continue is aborted and released") |
| IC-57 | A background R tool that changed bindings at an idle tick prints one notice | Task 6 |
| scope | R tools at idle ticks (`"idle"`) or waiting for a blocking call (`"wait"`) | Task 4 (idle: the `r` call ran during `later::run_now()` ticks; wait: `e$y` stayed `NULL` until `gptr_wait()`) |
| scope | The pause menu's `[b]ackground` | Task 3, "bg_register() marks a running foreground run" (whether the foreground call then returns is P06/P08/P14 behaviour; ambiguity A17) |
| IC-36 | Session rows in the job table that P04's `gptr_jobs()` lists | Tasks 3-5 (row, kind `session`, name, status `running`/`waiting`, removal at release, `gptr_jobs(kill = TRUE)`) |
| scope | Cleanup in `.onUnload` | Task 3 (`bg_shutdown()` registered with `on_unload()`; "gptr_jobs(kill = TRUE) and bg_shutdown() stop background sessions") |
| scope | Documentation of the support matrix and the experimental status | Task 7 (topic `gptr-background`) |
| R1/R2 | No user object or frame held | Task 7 copy-safety row (`expect_no_copy()`, 0 copies after a settled background run with a context object); Task 3 "bg_run_opts() keeps the options a resumed run needs, never a frame or a snapshot" (the kept run options never include `call`) |

Commands and expected results, run from `/Users/wanjun/Desktop/gptr` after Task 7:

1. `Rscript --vanilla -e 'devtools::test(filter = "agent-background")'`
   Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 158 ]`.
2. `NOT_CRAN=false Rscript --vanilla -e 'devtools::test(filter = "agent-background")'` (devtools and testthat keep an explicitly set `NOT_CRAN`)
   Expected: `[ FAIL 0 | WARN 0 | SKIP 30 | PASS 0 ]` (every test reports `On CRAN`).
3. `grep -c 'skip_if_not_installed("later")' tests/testthat/test-agent-background.R`
   Expected: `14` (every test that creates a background run or pumps `later`; the other 16 tests need no later).
4. `Rscript --vanilla -e 'devtools::test()'`
   Expected: a summary line with `FAIL 0 | WARN 0` (the whole suite, including P01's `test-lint-rules.R` and `test-arch-layers.R`).
5. M4 exit, run once P18-P21 are complete (05 P20 acceptance 4):
   `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`
   Expected: 0 errors, 0 warnings, and no NOTE apart from the incoming-feasibility NOTE naming the maintainer.

## Manual check (interactive terminal R; not automated)

03 §13 asks for a manual checklist for the pause menu and background pumping. In a terminal `R` session started in the repository (`R --vanilla`, then `devtools::load_all()`):

```r
fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "Sys.sleep(3); counts = matrix(1:20, 4)"), delay = 0.5),
  list(text = "Normalised.", delay = 0.5)))
s = gptr("Load and normalise the counts", model = fake, mode = "auto", background = TRUE)
s$status                          # "running": the prompt came back at once
gptr_jobs()                       # one row: kind "session", status "running"
s |> gptr("Use TPM, not CPM")     # type it during the 3 s tool: returns at once, prints nothing
# press Ctrl-C while the tool sleeps: the pause menu appears on stderr; answer c
s$status                          # "idle" a few seconds later; notices said what changed
exists("counts")                  # TRUE
fake2 = gptr_fake_provider(list(list(tool = "r", input = list(code = "z = 3")),
                                list(tool = "r", input = list(code = "z = 3")), "done"))
w = gptr("set z", model = fake2, mode = "manual", background = TRUE)
w$status                          # "waiting" after a moment: a notice, and no prompt at the console
gptr_wait(w)                      # the approval prompt appears inside the blocking call; answer y
c(w$status, z)                    # "idle" and 3
```

Record the result per front end in the support matrix of Task 7 when a front end moves from "unverified" to "verified".

---

## Self-review


### Spec coverage

| Requirement (05 P21 scope, 04 §7.21, IC-57, IC-36) | Task |
|---|---|
| Registration of a running session with a `later`-driven pump, 50 ms timer, no `later_fd` | Task 3 (`bg_register()`), Task 4 (`bg_ensure_pump()`, `bg_callback()`) |
| Pump calls `reactor_pump(slice_ms = 0)`; no-op while the reactor is on the stack (IC-57) | Task 1 (`bg_once()`, `bg_reactor_busy()`), Task 4 (`bg_tick()`) |
| Idle-tick execution of R tools, `gptr.background_tools = "idle" \| "wait"` | Task 1 (`bg_tools_mode()`), Task 4 (`allow_runs`) |
| Notice when a tool changed user bindings at an idle tick | Task 6 |
| Asks move the session to `waiting` until the next blocking gptr call, where they are shown (IC-57) | Task 2 (wrappers answer a denial with the pending text), Task 3 (`tool_call` hook for `ask`), Task 4 (the sweep stops an asked run), Task 5 (park, resume with the kept run options, failed resume) |
| The pause menu's `[b]ackground` option (P14 calls `bg.register`) | Task 3 (running foreground run marked `opts$background = TRUE`) |
| Session rows in the job table that P04's `gptr_jobs()` lists (IC-36) | Task 3 (`job_add()`), Tasks 4-5 (status, removal) |
| Cleanup in `.onUnload` | Task 3 (`on_load(on_unload(bg_shutdown))`) |
| Support matrix and experimental status documented | Task 7 |
| Acceptance 1, 2a-2e, 3a-3b | see the acceptance table |
| `gptr_error_missing_package` with `package`, `feature` | Task 3 |
| Service `bg.register` owned by a built-in (IC-34) | Task 3 (`builtin:background`, whose `tool_call` hook record keeps the bootstrap service visible under P01's `service_builtin_active()`; test "bg.register is a service provided by P21 and owned by builtin:background") |

### Placeholder scan

Searched the plan for the placeholder phrases of the writing-plans standard (to-be-determined markers, deferred-implementation notes, "fill in" instructions, references to another task's code instead of the code itself, generic error-handling or edge-case instructions): none. Every step that changes code shows the complete code; every modification replaces a whole named function (its roxygen block and definition) or inserts a complete block at a named line. The red-phase expectations of Tasks 3-7 name the failing assertions and messages rather than exact pass counts, because tests that error mid-way make those counts depend on where the error happens.

### Type and name consistency with 04

- `bg_register(s)` returns `invisible(s)` (§7.0 shape `function(session) invisible(session)`; §7.21 name `bg_register(s)`); service name `bg.register`; `provided_by = "P21"`; owner `builtin:background`.
- Option `gptr.background_tools`, default `"idle"`, values `"idle"`/`"wait"` (§3.1). State `the$bg` (§7.0).
- Status `waiting` (§5.1); job kind `session` and columns of `gptr_jobs` (§5.12).
- `gptr_error_missing_package` fields `package`, `feature` (§2.2); notices are `gptr_message_notice` (§2.2); errors never escape the callback and become `registry_diagnostic("builtin:background", <"tick" | "sweep" | "resume">, <class>, <message>)` (§7.2).
- `ui` methods and arguments exactly as §10.2 kind 22; at an idle tick `permission()` answers `list(decision = "deny", remember = NULL, feedback = chr(1))` (a listed decision with feedback), `select()` `NA_integer_`, `input()` `NA_character_`, `questions()` `list(answers = <named list>, cancelled = TRUE)`.
- Hooks: `tool_call` handler returns `NULL` or `list(decision = "block", reason)`; `tool_result` handler returns `NULL` (§10.4).
- `reactor_pump(until, slice_ms, allow_runs, timeout)`, `job_add(kind, id, name, pid, stop, status)`, `run_start(s, input, opts)`, `run_abort(run, reason)`, `session_enqueue(s, text, as, source, blocks)`, `registry_add(spec, source, rank, session)`, `ext_service_set(name, fun, provided_by, builtin)`, `console.interrupt_policy(expr_fun, runs, mode)` are called with the argument names of §7-§8. The kept run options are §7.6 names.
- Queue sources re-used unchanged when dropped items are re-queued (§5.1 `queue`, IC-55); the relay text asserted in Task 4 is the §4.2 text.
- Dependency plans agree: P08's `route_continue()` steers a `running` or `waiting` session with the pipe and its `gptr_wait()` pumps until no session is `running` or `waiting` (its ambiguity 16 follows this plan's A10); P06's `run_start()` refuses only a live run or status `running`, continues from the leaf with `input = NULL`, and records `"abort"` answers as described in A11; P11's `ui_get()` resolves `registry_get("ui", <name>, session = <id>)`; P04's `job_add()` replaces a row with the same id and `gptr_jobs(kill = TRUE)` tolerates stop functions that remove their own rows.

### Contract ambiguities and the reading chosen

- A1. **Parking an ask.** 04 gives P21 the behaviour "an ask moves the run to `waiting`" but no kernel hook, and P06 runs the gate inside the FIFO job of sequential tools, so an idle tick that runs a background tool also runs its gate. Reading: session-scoped rank-0 `ui` records (P02 registry scoping, §7.2, §10.1) wrap every UI and, during an idle tick only, answer a denial whose feedback says that approval is pending (cancelled answers for `select`/`input`/`questions`), a `tool_call` hook blocks the `ask` tool with the same text, and the sweep after the tick aborts the run (reason `"waiting"`) and writes `.d$status = "waiting"` and `.d$reason`. §7.6 and IC-33 ("`session_data()` (read)") say other plans read `.d` only; §7.21, IC-57 and 05 assign exactly this transition to P21 and P06 offers no setter, so P21 writes these two fields (and `aborted` when a waiting session is stopped or cannot continue). It relies on P11's `ui.get` resolving with `registry_get("ui", <name>, session = <session id>)`; Task 5's test fails loudly (a `permission` row in the scripted UI log during idle ticks) if it does not.
- A2. **`run_start(s, NULL, ...)`.** 04 does not say what `input = NULL` means. Reading (P06 implements it): "take the first queued item; with none, continue from the leaf when the path awaits a response, else `gptr_error_invalid_argument`" (the same call starts a `.run = FALSE` session in the §7.21 example and resumes a waiting session; the error case is handled by `bg_resume()`).
- A3. **Marking the run.** §7.6 lists `gptr_run` fields as read-only for other plans, while §7.21 says `bg_register()` "marks the run background". Reading: P21 sets `run$opts$background = TRUE` (the documented run option), which P06's `session_run()` foreground wait honours.
- A4. **Reactor depth.** IC-57 says P04 tracks the pump depth but 04 names no accessor (P04's plan has an internal `reactor_depth()`). Reading: `bg_reactor_busy()` finds `reactor_pump` among `sys.function()` of the call stack (equivalent to depth > 0, no frame is kept, no helper outside 04 is needed).
- A5. **`reactor_pump(slice_ms = 0)`.** With the default `until` and `timeout = Inf` it never returns. Reading: `until = bg_once()` (exactly one non-blocking iteration per tick).
- A6. **Built-in owner.** IC-34 says every service is owned by a built-in, §10.3 lists none for P21. Reading: `builtin:background` (a `tool_call` and a `tool_result` hook), which also makes `-builtin:background` remove the service. The factory registers its `tool_call` hook from Task 3 on, because P01's `service_builtin_active()` hides the bootstrap services of a built-in with no record in a non-empty registry; it registers no `service` record (built-ins own services through the bootstrap table, and a built-in `service` record would shadow test stubs set with `ext_service_set()`, such as P14's pause-menu test).
- A7. **Argument name.** §7.0 shows `function(session)`, §7.21 `bg_register(s)`; both consumers call it positionally. Reading: `s`.
- A8. **`gptr_jobs` owner.** §5.12 lists the class with owner P21, IC-36 moves `gptr_jobs()` to P04. Reading: P04 owns the function and class; P21 adds rows with `job_add()` only.
- A9. **Option documentation.** §3.1 says the owner documents the option in its roxygen `?gptr_options` section (assembled by P25). Reading: the option is documented in the `gptr-background` topic (section "Options"), as P04 does on `?gptr_jobs`, for P25 to collect.
- A10. **`gptr_wait()` on a waiting session.** 04 does not say whether `waiting` counts as settled. Reading: P21 resumes waiting sessions from any blocking reactor pump; P08 treats `waiting` as not settled, so `gptr_wait(s)` pumps (P08 ambiguity 16 agrees). P08's `gptr_step()` starts only queued input and returns at once for a waiting session with an empty queue; `gptr_wait()` or any other blocking call continues it.
- A11. **The `"abort"` permission answer.** 04 lists it but not its kernel effect. P06's `perm_ask()` records it as the tool result "Permission denied: the user aborted the run. The run stops here." and aborts after the call; the assistant tool-call message stays complete (only a streaming partial gets `stop_reason = "aborted"` and leaves the projection). Reading: background asks never answer `"abort"`; they answer a denial with the pending text, and the sweep stops the run itself.
- A12. **Live record and run shapes.** Reading: the live record of `session_live()` and `gptr_run` are environments (§5.1 "environment binding", §5.13; P06's `live_new()`), so P21 assigns `live$background` and `run$opts` in place.
- A13. **Queued input of `.run = FALSE`.** Reading: it lives in `.d$queue` as items `list(text, blocks, source, t)` (§5.1), which is what `bg_has_queued()` and `bg_title()` read.
- A14. **Gateway order.** Reading (P08 implements it): P08 starts the run with its own run options plus `background = TRUE`, then calls `bg.register` (so budgets and `max_turns` of the call are kept, and copied into the live handle for a resume); `bg_register()` also accepts an unstarted session and starts it with `background = TRUE` only (a `.run = FALSE` call's pending options live inside P08's gateway, which P21 must not call).
- A15. **Interrupt mode of idle ticks.** 04 does not say which mode of `console.interrupt_policy` background ticks use. Reading: `"repl"` (an abort does not re-signal the interrupt inside a `later` callback).
- A16. **`gptr_cancel()` on a waiting session.** P08's `gptr_cancel()` aborts only a session's run, and a waiting session has none. Reading: documented in the topic (`gptr_jobs(kill = TRUE)` stops it); P21's sweep releases any waiting session whose status another plan changes, so a later P08 change that sets `aborted` for waiting sessions needs nothing from P21.
- A17. **Returning from `[b]ackground`.** P06's `session_run()` stops its foreground wait when `run$opts$background` is `TRUE`, but P08's `run_foreground()` pumps through `run_wait()`, which waits for settlement only. Reading: P21 marks the run (its contract); whether the interrupted foreground `gptr()` call returns at once is P08/P14 behaviour (P14 is not yet written in full), and the manual check of Task 7 covers it.
- A18. **A `gptr.ui` spec object.** P11's `ui_get()` uses a `gptr_ui` spec given as the `gptr.ui` option directly, without a registry lookup, so session wrappers cannot shadow it. Reading: documented limitation; with such an option a background ask at an idle tick reaches that UI.
- A19. **Asks of sub-agents.** A child session started by a background run's R tool at an idle tick resolves its own UI (its id has no wrappers). Reading: documented limitation; such children run inside the tool's evaluation, while the console is busy, as for any background tool.
- A20. **`"wait"` mode inside unrelated blocking calls.** P04/P06/P08 pumps at depth 1 default `allow_runs` to `NULL`, so a background run's queued R tool also runs inside a blocking call on another session, not only inside `gptr_wait()`. Reading: accepted; 03 §6.2 says such tools are deferred to a blocking call, and the help text says "a blocking gptr call such as `gptr_wait()`".
- A21. **Questions from extensions.** `select()`, `input()` and `questions()` called by an extension at an idle tick receive cancelled answers (the session is parked after the tick); only the `ask` tool is blocked with the pending text, because P21 can name it in a `tool_call` matcher.

### Validation executed while writing and reviewing this plan

- Every `r` code block of the plan was extracted to the scratch directory and parsed with `Rscript --vanilla` (R 4.4.3): all parse. The blocks were applied in task order with a scratch assembler (append, or replace a named definition with its roxygen block, or insert the topic after the header): the assembled stages after Tasks 4, 5 and 6 and the final file parse, and `codetools::findGlobals()` finds no undefined `bg_*` or `builtin_*` function at any stage; the remaining globals are the functions of P01, P02, P04 and P06 listed under "Interfaces used from earlier plans".
- `lintr::lint()` (lintr 3.3.0.1) with the repository `.lintr` linters (`linters_with_defaults()` with `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`, the snake_case `object_name_linter` with the S3 regex; `object_usage_linter` off because the other plans' functions are not in the scratch directory): no lints in the final R file, the test file and the intermediate stages. No `<-` or `%>%` in any code block; both R files are ASCII.
- A stub kernel modelled on P04 (pump depth, the step order tasks, then `later::run_now(0)` at depth 1, then one FIFO tool) and P06 (the gate inside the FIFO job; `"allow"`, `"deny"` with feedback and `"abort"` answers recorded as P06 records them; `run_abort()` at a boundary; `run_start(s, NULL)` taking a queued item or continuing from the leaf, or failing when the transcript ends with a final answer) exercised the final file under `Rscript --vanilla`: 46 of 46 checks passed (registration, job row and name, marking, kept options, timer, progress at idle ticks, release and notices, timer chain stopping, no-op while a pump is on the stack, `"wait"` mode, an idle-tick ask stopped right after the denied call with no further request, the pending text reaching the model and no "aborted" text, the waiting notice and job status, the re-queued steer, no resume at idle ticks, resume inside a blocking pump with exactly one ask, stopping a waiting job, a superseding run's ask parked again without a request loop, the `ask` tool blocked with the pending text, failed resume aborted and released, a failing tick still swept and the timer re-armed after an error and after an interrupt, missing later, shutdown with no revival by a late callback, helpers). The same harness run against the plan's previous version failed 5 checks: the model was told "the user aborted the run", the pending text never reached it, and a superseding run's denied call was retried at every tick.
- The 6 Task 1 tests and the Task 3 `bg_run_opts()` test (30 expectations) passed with testthat 3.3.2 against the stub environment, in `en_US.UTF-8` and in the C locale.
- R 4.4.3 parses a `\u202e` escape inside a string literal (checked); the tests still build bidi and zero-width characters with `intToUtf8()`, and the plan contains no raw bidi or zero-width character.
- later 1.4.8: a cancel function returns `TRUE` for a pending callback and `FALSE` afterwards; an error in a callback propagates out of `later::run_now()` (hence `bg_guard()`); `later::run_now()` called inside a later callback runs the other due callbacks (so the tick's own pump at depth 1 may service other later users, and `bg_callback()` cancels its own handle before ticking).
- The Task 7 topic was generated with roxygen2 in a scratch package: `tools::checkRd()` reports nothing, `tools::Rd2txt()` renders the support matrix, and the Task 7 examples guard finds no `background = TRUE` in any `\examples` section.
- `devtools::test()` keeps an explicitly set `NOT_CRAN=false` (testthat's `local_assume_not_on_cran()` returns early when `NOT_CRAN` is set), so acceptance command 2 skips every test.
- Not executable here (earlier plans' code does not exist yet): the integration tests of Tasks 2-7 against the real P02/P04/P06/P08/P11/P14 code.

## Plan review log

Adversarial review of 2026-10-01 against 00-conventions, 03, 04 (§15 included), 05 P21, the dependency plans P01, P02, P04, P06, P08, P11 and P14, and research reports G3 and 15 with their verification logs.

| # | Severity (claimed, for rejected rows) | Location | Verdict | What changed, or why rejected |
|---|---|---|---|---|
| 1 | major | Task 2 `bg_ui_spec()`; Task 5 "How it works"; topic text | applied | The idle-tick `permission()` answered `"abort"`. P06's `perm_ask()` records that as "Permission denied: the user aborted the run. The run stops here." and keeps the complete tool-call message (the claim that the aborted turn leaves the projection was wrong: only a streaming partial is marked aborted), so the resumed run told the model the user aborted and a real model would not repeat the call: the ask was never shown (IC-57). The wrappers now answer `list(decision = "deny", remember = NULL, feedback = bg_pending_text("approval"))`; the new `bg_pending_text()` tells the model nothing ran and to repeat the call when the session continues; the Task 5 test asserts that request 2 carries it; the topic describes the real behaviour. |
| 2 | major | Task 2 `bg_park()`, `select()`/`input()`/`questions()` | applied | The wrappers called `run_abort()` from inside P06's dispatcher (in the middle of a tool call), settling the run and emitting `agent_end` before the tool result was appended. `bg_park(id, what, summary)` now only records; the sweep after the tick stops the run (Tasks 4 and 5); tests updated ("never stops the run itself"). |
| 3 | major | Task 5 (new `bg_on_tool_call()`, `builtin_background()`) | applied | An `ask` tool call at an idle tick got a cancelled `questions()` answer, which tells the model the user dismissed the questions, so they would not be asked again. `builtin:background` now registers a `tool_call` hook (matcher `ask`) that blocks the call with the pending text during idle ticks and records the ask; new unit test. |
| 4 | major | Task 5 `bg_sweep()` | applied | A run with a recorded ask was aborted only when its id equalled `bg$run`; an ask raised at an idle tick by a run that `gptr_wait()`/`gptr_step()` started on the session was never stopped, so the denied call was retried at every tick (a loop of model requests; reproduced with the stub kernel). The sweep now aborts any live run of a session with a recorded ask, and supersession is keyed on the `waiting` flag. |
| 5 | major | Task 4 `bg_callback()`, `bg_ensure_pump()` | applied | One `tryCatch()` wrapped tick and sweep, so a failing tick skipped the sweep that must stop an asked run before its next request, and an interrupt escaping the callback skipped the re-arm, stopping the timer chain for good. The callback now re-arms through `on.exit()`, guards tick and sweep separately (`bg_guard()`), and `bg_ensure_pump()` no longer recreates `the$bg` after `bg_shutdown()`; `bg_runs()` skips a session with a recorded ask. |
| 6 | minor | Task 4 `bg_sweep(idle)` | applied | Between Tasks 4 and 5 a denied ask at an idle tick would have been retried at every tick. The Task 4 sweep already aborts a run with a recorded ask (released as `aborted`); Task 5 parks it instead. |
| 7 | minor | Task 3 `bg_track()`; Task 5 `bg_resume()` | applied | A resumed run lost the call's run options (`max_turns`, `budget`, `returns`, `timeout`, ...). `bg_run_opts()` keeps a whitelist of §7.6 options in `live$background$opts` (never `call` [R2], `safety`, `doc`, `parent_run`, `interactive` or `rng_state`); new unit test. |
| 8 | minor | Task 5 `bg_resume()` | applied | A `run_start()` error inside the callback (for example nothing to run) left the session `waiting` forever and logged a diagnostic every 50 ms inside every blocking call. It is now set to `aborted` with one diagnostic and released; new test. |
| 9 | minor | Task 5 `bg_park_session()` | applied | A dropped item without text would make `session_enqueue()` (which requires a non-empty string) fail inside the sweep and leave the session half parked; such items are skipped. The notice and reason now say "waiting for an answer" for non-permission asks instead of "waiting for approval: a question from the agent". |
| 10 | minor | Task 7 support matrix | applied | "Terminal R on macOS and Linux: verified" overclaimed: G3 and its verification log exercised only macOS `R --interactive`, and report 15 rates RStudio "LIKELY". Linux and RStudio are now "unverified". |
| 11 | minor | Task 7 Step 4 lint command | applied | `lintr::lint()` on an unloaded development tree makes the `object_usage_linter` of `linters_with_defaults()` report every internal helper (P01 acceptance A3 note); the command now runs `pkgload::load_all(quiet = TRUE)` first. |
| 12 | minor | Task 1 note; validation section | applied | The plan contained raw U+202E (right-to-left override) characters, which reorder displayed text (a Trojan-source hazard in a plan that implementers copy from), and claimed that R 4.4 refuses a `\u202e` escape in a string literal, which is false (checked with R 4.4.3). The characters were removed and the note reworded. |
| 13 | minor | Task 1 `bg_once()` title, test title and "Why these helpers" | applied | "one or two non-blocking iterations" was wrong: P04's loop checks `until()` before each iteration, so the pump runs exactly one. |
| 14 | minor | Self-review ambiguities | applied | Recorded the cross-plan limits found in review (A16 `gptr_cancel()` of a waiting session, A17 the `[b]ackground` return path in P08, A18 a `gptr.ui` spec object, A19 sub-agent asks, A20 `"wait"` mode inside unrelated blocking calls, A21 extension questions) and updated A1, A2, A10, A11 to the code of P06, P08 and P11. |
| 15 | minor | Plan acceptance, Tasks 2-7 Step 4 | applied | Counts updated to the revised tests: 30 tests, 156 expectations, `SKIP 30` on CRAN, 14 tests need later and 16 do not. |
| 16 | minor | Task 1 `bg_reactor_busy()` | rejected | Claim: it should call P04's `reactor_depth()`. 04 names no depth accessor (P04's helper exists only in its plan); the stack test is exactly "depth > 0", keeps no frame and costs one short stack walk per 50 ms. Recorded as A4. |
| 17 | major | Task 5 writes `.d$status` and `.d$reason` | rejected | Claim: IC-33 lists `session_data()` as read-only. §7.21 and IC-57 assign the `waiting` transition to P21 and P06 provides no setter; the writes are confined to `status`/`reason` and recorded as A1. |
| 18 | minor | Task 7 copy-safety row in `test-agent-background.R` | rejected | Claim: copy rows belong in `test-copy-<area>.R`. 05 gives P21 exactly one test file; the row uses P01's `expect_no_copy()` in a fresh process as conventions §7 requires. |
| 19 | minor | Tests that do not need later | rejected | Claim: acceptance 1 ("tests skip without later") requires every test to skip without later. The acceptance means the file is green without later; the 16 tests that do not start a background run need no later and run. |
| 20 | minor | Task 3 "without later" test | rejected | Claim: mocking `bg_has_later()` cannot reach P08, which checks `requireNamespace("later")` itself. With later installed P08 passes its check and calls the service, so the mocked check in `bg_register()` raises the same class; without later P08 raises it; both paths are covered. |

## Cross-plan consolidation log

Consolidation of 2026-10-01 against 04 (IC-34; §10.3; §10.4 `tool_call`), 03 and 05 (P21), and the related plans P01 (`service_lookup()`, `service_builtin_active()`), P02 (`ext_load_builtins()` at rank 6, the factory API's `gptr$on()`, `registry_get()`), P08 (`gptr(background = TRUE)` calls `ext_service_get("bg.register")`) and P14 (the pause menu's `[b]ackground`, and its test that stubs the service with `ext_service_set()`).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | major | Task 3 `builtin_background()` (registered nothing), `ext_service_set("bg.register", ..., builtin = "background")`, Task 3 tests | applied, with a different record | Confirmed: P01's `service_builtin_active()` hides a bootstrap service whose built-in has no record in a non-empty registry, so through Tasks 3-4 `ext_service_has("bg.register")` was FALSE, `ext_service_get()` signalled `gptr_error_not_available` and `gptr(background = TRUE)` failed with that class, and Task 3's `PASS 87` could not be reached. The suggested `service` record was not used: P01's `service_lookup()` consults the registry before the bootstrap table, so a built-in `service` record for `bg.register` would shadow the stub that P14's test "[b]ackground hands a foreground run to bg.register (P21) and resumes" installs with `ext_service_set()`, and that test would fail in acceptance command 4 (`devtools::test()`). No other built-in registers its services as records. Instead, the `tool_call` hook (matcher `ask`) that the final built-in already registers, and its handler `bg_on_tool_call()`, now arrive in Task 3. `builtin_background()` registers the hook from Task 3 on, and the Task 6 version keeps it. Its unit test "an ask tool call at an idle tick is blocked and recorded, never shown" moved from Task 5 to Task 3. The first Task 3 test now also asserts `"builtin:background" %in% gptr_registry()$source` and `expect_null(registry_get("service", "bg.register"))`, so the service must stay a bootstrap entry. Updates: the Task 3 Interfaces, Behaviour and Step 2; Task 5's Files, Interfaces, How it works, Step 2 and Step 3 (no factory replacement, no `bg_on_tool_call()`); Task 6's Produces, Step 2 and Step 3 (it replaces the Task 3 version); the acceptance and spec-coverage rows; and A6. Counts: Task 3 `PASS 94` (was 87); Task 4 127 (was 120); Task 5 147 (was 145); Task 6 152 (was 150); Task 7 and acceptance 158 (was 156). There are still 30 tests: 14 need later and `SKIP 30` on CRAN. Between Tasks 3 and 5, the Task 4 sweep stops a run whose `ask` call was blocked at an idle tick, as it does for any recorded ask. Every `r` block was re-extracted and parses under `Rscript --vanilla`, with no `<-` or `%>%`. |
