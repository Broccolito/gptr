# P10 Tools and the `peter$` namespace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the model-visible tools `r`, `read`, `edit` and `write` (plus Pi's `grep`, `find` and `ls` for the `extended` preset) and the `peter$` namespace that makes every other capability an ordinary R function the model composes inside one `r` call (S-12).

**Architecture:** Every capability is one tool spec (IC-37) registered by two built-ins: `builtin:tools` (`R/tool-namespace.R`: `read`, `edit`, `write`, `grep`, `find`, `ls`, `help`, `search`, `describe`, `plot`, `out`, their `<rules>` guidelines, the `<r_session>` fragments, the T1 `plugins` section, the `members` search source and the services `ns.resolve`, `ns.names`, `search.sources` behind P08's gateway methods) and `builtin:r` (`R/tool-r.R`: the `r` tool, whose `parameters` is a function giving the four frozen schema variants of IC-68 and whose execute evaluates through P09's evaluator). Member closures are generated from the specs; a member called while an `r` evaluation runs (found through an r-call marker bound in the `r` tool's own frame, never package state) passes P06's `dispatch_nested()`, and a member called by the user runs directly. The file engines (`tool-walk.R`, `tool-diff.R`, `tool-read.R`, `tool-write.R`, `tool-edit.R`, `tool-search.R`) are pure base R ports of Pi's semantics and report 11's verified prototypes.

**Tech Stack:** base R (>= 4.2.0: `grepRaw()`, `iconv(toRaw = TRUE)`, `utils::help()`, `tools::Rd2txt()`, `grDevices::recordPlot()`); jsonlite (`base64_enc()` fallback); P01's helpers (`json_encode()`, `est_tokens()`, `out_get()`, `write_atomic()`, `path_class()`); Suggests behind `requireNamespace()`: stringi (NFKC/NFD), magick (image conversion), openssl (base64); testthat 3e and withr in tests; rtiktoken only in the development runner `dev/bench/tokens/run.R` (P07's, not a dependency).

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2, §4.2, §6.4, §6.12, §7.1-7.3, §12.7), dev/spec/04-interface-contract.md (§2.2, §3.1, §4.4, §5.3, §5.7, §5.10, §7.10, §9.1-9.4, §10.8, §12.2-12.4, §15: IC-36, IC-37, IC-48, IC-54, IC-67, IC-68, IC-69, IC-71, IC-73), dev/spec/05-plan-decomposition.md (P10).

**Depends on:** P09 (and through it P01-P08). **Milestone:** M2.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (`=` for assignment, never the left arrow; native `|>`; ASCII-only `R/` sources with `\u` escapes; `pkg::fun()` calls; `gptr_abort()`/`gptr_warn()`/`gptr_inform()`; no `:::`; no `.GlobalEnv`; state restored with `on.exit(..., add = TRUE)`; testthat 3e; no network in tests). Plan-specific requirements, copied from the specification:

- Owned options (04 §3.1): `gptr.helper_output_tokens` `int(1)` default `1500L` ("print budget of `peter$` members", shared with P22); `gptr.read_max_tokens` `int(1)` default `12000L` ("`read` cap (also 2,000 lines and 50 KB)"). Both defaults already live in P01's `gptr_opt()` table; P10 adds no option.
- Consumed options: `gptr.r_output_tokens` (`4000L`, P09), `gptr.r_max_images` (`3L`, P09: "plot images attached per `r` result (IC-67)"; P10 applies the same cap to the images `peter$plot()` and `peter$read()` attach to one `r` result and names the rest in a notice), `gptr.plot_res` (`120L`, P09), `gptr.doc_output_lines` (`12L`, P15), `gptr.unsafe_no_permissions` (`FALSE`, P06; tests only, IC-53).
- Member prints are budgeted by `gptr.helper_output_tokens` (1,500), "and at most 0.6x the remaining `r` budget when called inside `r`" (04 §9.4).
- `read` (03 §7.2, 04 §7.10): "caps at 2,000 lines, 50 KB and 12,000 tokens, with line numbers off"; images by magic bytes (jpg, png, gif, webp, bmp); "16 MiB raw index / streaming index / cached sparse index above 20 MB"; `skill:<name>/<path>` pseudo-paths resolve through P17's `skill.body` service (IC-68).
- `edit` (03 §7.1, 04 §9.2): Pi's multi-edit semantics; "a diff (at most 400 tokens) is appended only when the fuzzy fallback, EOL or encoding normalisation changed what the model literally asked for"; a pasted `*** Begin Patch` envelope is applied through `patch_apply()`; a bound history document is edited through P15's `doc.edit` service.
- `diff_lines(old, new, context = 3L, max_tokens = 400L)`: "prefix/suffix trim, patience anchors, Myers capped at D = 256".
- `walk_files()` prunes `.git`, `node_modules`, `renv`, `.venv`, `__pycache__`; `glob_to_regex()` implements "Pi's `**/` prefix rule".
- Pi's direct-tool defaults (04 §9.2): `grep` 100 matches or 50 KB, long lines truncated to 500 characters; `find` 1000 results or 50 KB; `ls` 500 entries or 50 KB. `gptr_matches` and `gptr_files` print "within 1,500 tokens, then a notice".
- Classes (04 §5.3, §5.10): `gptr_member` (`c("gptr_member", "function")`), `gptr_ns` (environment with bindings `path`, `kind` in `"mcp"`, `"mcp_server"`, `"plugin"`), `gptr_lines` (attributes `path`, `offset`, `limit`, `total`, `truncated`, `encoding`), `gptr_patch` (`list(path, message, diff, n_edits, fuzzy)`), `gptr_matches` (`file`, `line`, `text`; attributes `truncated`, `limit`), `gptr_files` (`path`, `size`, `mtime`, `type` in `file`, `dir`, `link`).
- Conditions (04 §2.2): `gptr_error_unknown_member` (fields `name`, `available`), `gptr_error_readonly` (`object`, `field`), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_not_available` (`member`, `provided_by`), `gptr_error_tool` (`tool`, `status`), `gptr_error_internal` (`detail`).
- Services (04 §7.0, IC-34, IC-36): `ns.resolve`, `ns.names`, `search.sources`, each `provided_by = "P10"`, `builtin = "tools"`. Built-ins: `builtin:tools` (`R/tool-namespace.R`) and `builtin:r` (`R/tool-r.R`), declared with `on_load(ext_declare_builtin(...))`.
- IC-37: "One tool spec per capability"; `read`, `edit`, `write`, `grep`, `find`, `ls` carry both `execute` and `fun`; `$.gptr_gateway` "resolves any spec **without** a namespace that has a `fun`, whatever its exposure, except `hidden`"; reserved member and namespace names: every built-in member name, `mcp` and the names of the 04 §9.4 table (`read`, `write`, `edit`, `grep`, `find`, `ls`, `help`, `search`, `describe`, `plot`, `out`, `sh`, `script`, `bg`, `jobs`, `py`, `sql`, `knit`, `app`, `mcp`).
- IC-48: "`record = FALSE` is set for `out`, `plot`, `help`, `search`, `describe`".
- IC-68: `<rules>` lines come from the tools' `guidelines` (read: 1 line, r: 3, edit: 4, write: 1); the `<r_session>` fragments of `builtin:tools` are `helpers` (order 10) and `out` (order 20) with `parent = "r_session"`; the `r` schema has `record` and `note` "only when a document is bound at freeze" and `timeout` (described `"Seconds; best effort. Default 3600."`) "only when no human can answer".
- IC-25 / 04 §9.3: the `plugins` section is T1, order 860, budget 1,500, header text verbatim, one `peter$<ns>$<name>(<arg>: <type>, <arg>?: <type>)  # <first sentence>` line per plugin `r` member.
- IC-54: `write`/`edit` risk applies the `control` (level 4) and `instructions` (level 3) path classes of P01's `path_class()`; reads are level 0 in the project, 1 outside, 2 protected (04 §9.4).
- IC-71: `peter$find(sort = c("path", "mtime", "size", "relevance"))` ("exact basename > prefix > substring > subsequence, ties by path"); `peter$grep(output = "files", sort = c("path", "count", "mtime"))`; out ids are `o` + 6 hex and `out_get()` looks in the session, then the process store, then the spill file.
- IC-67: `peter$plot(which = NULL, width = 1000L, height = 700L)` attaches the current plot or stored plot `which`.
- IC-73: P10 adds its north-star fixture and baseline row to `dev/bench/tokens/` with P07's runner (`--update <id>`).
- Copy-safety (03 §6.4, rules R1-R10): a member called by the user passes its arguments to the member function as promises through a call of symbols, never through a list (R1); a member called from model code hands P06's gate the input list that 04 §7.6 fixes (`dispatch_nested(name, input, ctx)`), so P10's own members take only scalar arguments on that path except `describe`, whose gate input is short labels of its argument expressions and whose value is computed locally (a plugin member that receives a user object from model code makes that object copy once on its next in-place edit: the documented cost of the contract's list input, like R9's bridges); the `r` tool resets its binding of the evaluation environment before returning and keeps no value (R2, R8).
- Lazy plugins (04 §10.8): "A lazy plugin registers placeholders for `extension.provides` and puts `extension.declarations` (signature lines and descriptions of its `r` members and direct tools) into the frozen prompt before activation, so activation never changes the cached prefix. The factory runs on the first `registry_get()` of a provided capability". So the `plugins` catalog, completion, `peter$search()` and namespace prints read tool specs through `registry_all("tool")` (which returns tool placeholders unactivated) and render placeholders from their declarations; only resolving or calling a member (`registry_get()`) activates a plugin.
- Exception to 00-conventions §7 (named here as that file requires): printed output of member results is tested with exact `utils::capture.output()` expectations instead of `expect_snapshot()`, because the texts are Pi's byte-exact formats and token budgets that a snapshot would only record, not check.
- Texts from Pi (MIT, Pi `1b347794`) are byte-identical to 04 §9.2 and carry the attribution comment; `read` never deserialises a data file (CVE-2024-27322).

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `R/tool-namespace.R` | create (Tasks 1, 8, 9, 10) | r-call marker and member print budgets; member closures, resolution (`ns.resolve`, `ns.names`), `gptr_ns` nodes and namespace providers; the `plugins` catalog, BM25, `peter$search()`, `peter$help()`; the members, direct-tool executes, risk functions, specs and `builtin:tools` |
| `R/tool-walk.R` | create (Task 2) | path resolution (Pi's `resolveToCwd`), `glob_to_regex()`, the `.gitignore` engine, `walk_files()` |
| `R/tool-diff.R` | create (Task 3) | `diff_lines()` and `diff_unified()` (trim, patience anchors, Myers capped at D = 256) |
| `R/tool-read.R` | create (Task 4) | `read_file()`, `read_lines_value()` (`gptr_lines`), encodings, images, windows and indexes |
| `R/tool-write.R` | create (Task 5) | `write_file()`: atomic, EOL-, BOM-, encoding- and mode-preserving |
| `R/tool-edit.R` | create (Task 6) | `edit_file()`, the fuzzy fallback, `patch_apply()`, `gptr_patch` |
| `R/tool-search.R` | create (Task 7) | `search_grep()`, `search_find()`, `search_ls()`, Pi's direct texts, `gptr_matches`/`gptr_files` prints |
| `R/tool-r.R` | create (Task 11) | the `r` tool: schema variants, evaluation, the `details` record, `builtin:r` |
| `tests/testthat/test-tool-namespace.R` | create (Tasks 1, 8, 9, 10) | budgets, closures, resolution, search, members, specs, acceptance 3 |
| `tests/testthat/test-tool-walk.R` | create (Task 2) | paths, globs, gitignore, walker, git oracle |
| `tests/testthat/test-tool-diff.R` | create (Task 3) | hunks, edit-script property test, cap, budgets, `git apply` |
| `tests/testthat/test-tool-read.R` | create (Task 4) | Pi's read oracle, images, encodings, caps, indexes, skill paths |
| `tests/testthat/test-tool-write.R` | create (Task 5) | Pi's write oracle and conventions |
| `tests/testthat/test-tool-edit.R` | create (Task 6) | Pi's edit oracle, fuzzy, byte-exactness, envelopes, acceptance 6 |
| `tests/testthat/test-tool-search.R` | create (Task 7) | grep/find/ls oracles, ripgrep oracle, sorting |
| `tests/testthat/test-tool-r.R` | create (Task 11) | schema variants, details record, end-to-end acceptance 4-7 |
| `tests/testthat/test-copy-tools.R` | create (Task 12) | copy-safety rows of acceptance 5 |
| `dev/bench/tokens/fixtures/ns02b-data-first-pipe.json` | create (Task 13) | P10's golden transcript (IC-73) |
| `dev/bench/tokens/baseline.csv` | modify (Task 13, through P07's runner) | the `ns02b-data-first-pipe` baseline row |
| `NAMESPACE` | regenerate (Tasks 1, 4, 6, 7, 8) | S3 method registrations through `Rscript --vanilla -e 'devtools::document()'` |

P10 exports no function (its user-facing surface is the `peter$` members, reached through P08's exported `peter`), so no `man/` page is generated; its S3 methods (`print.gptr_text`, `print.gptr_member`, `print.gptr_lines`, `print.gptr_patch`, `print.gptr_matches`, `print.gptr_files`, `$.gptr_ns`, `[[.gptr_ns`, `$<-.gptr_ns`, `[[<-.gptr_ns`, `names.gptr_ns`, `print.gptr_ns`, `.DollarNames.gptr_ns`) are registered in `NAMESPACE` through `@export`/`@exportS3Method` with `@noRd`.

Tasks ("Create `f`" means write a new file with exactly the block shown; "Append to `f`" means add the block at the end of the existing file, separated from the previous content by one blank line, so `R/tool-namespace.R` and `tests/testthat/test-tool-namespace.R` are the concatenation of their four blocks in task order; every block is complete code):

1. Member print budgets and the r-call marker (`R/tool-namespace.R`, part 1)
2. Paths, globs, `.gitignore` and the walker (`R/tool-walk.R`)
3. Unified diffs (`R/tool-diff.R`)
4. The `read` engine and `gptr_lines` (`R/tool-read.R`)
5. The `write` engine (`R/tool-write.R`)
6. The `edit` engine, the fuzzy fallback and patch envelopes (`R/tool-edit.R`)
7. `grep`, `find` and `ls` (`R/tool-search.R`)
8. Member closures, resolution and namespace nodes (`R/tool-namespace.R`, part 2)
9. The plugin catalog, BM25, `peter$search()` and `peter$help()` (`R/tool-namespace.R`, part 3)
10. Members, direct-tool executes, risk and `builtin:tools` (`R/tool-namespace.R`, part 4)
11. The `r` tool and `builtin:r` (`R/tool-r.R`)
12. Copy-safety rows (`tests/testthat/test-copy-tools.R`)
13. P10's golden transcript and baseline row (`dev/bench/tokens/`)

### Task 1: Member print budgets and the r-call marker

**Files:** Create: `R/tool-namespace.R` (part 1 of 4); Test: `tests/testthat/test-tool-namespace.R` (part 1 of 4); Modify: `NAMESPACE` (generated).

Every `peter$` member prints within `gptr.helper_output_tokens` (1,500), and while an `r` evaluation runs within 0.6 x the **remaining** `r` budget (04 §9.4; G5: "helper defaults take min(option, 0.6 x remaining)"): the marker counts the estimated tokens that member prints have written during this evaluation, and `member_budget()` is `min(gptr.helper_output_tokens, floor(0.6 * (gptr.r_output_tokens - printed)))`, so ten member prints in one loop shrink instead of each taking 1,500 tokens (output the evaluator prints for ordinary values is not counted; P09 cuts the whole result to `gptr.r_output_tokens` anyway). Whether a member runs inside model code is decided by the **r-call marker**: the `r` tool (Task 11) binds a local variable `gptr_r_call` of class `gptr_r_call` in its own execute frame for exactly the dynamic extent of one evaluation; `ns_r_call()` finds the innermost one by walking `sys.frame(k)` outwards (never `sys.frames()`, which would collect every frame in a list, rule R3), so no package-level run state exists (INFRA-15, architecture §2.2 rule 5) and nested sub-agent evaluations see their own marker. The marker holds the tool's `ctx` and collectors for images (`peter$plot()`, image reads; at most `gptr.r_max_images` per evaluation, the rest counted in `dropped` and named in a notice by Task 11, so a loop over 50 image reads cannot attach 50 images, IC-67), bridge digests and artifact paths; it never holds a user object or frame. The print helpers write plain UTF-8 lines with `writeLines()`: member output is data, never a format string (rule C1), and `cli` output would go to stderr in non-interactive sessions, where P09's sink capture does not see it. `budget_head()` and `budget_head_tail()` (head 40%, tail 60%) keep whole lines only, found by binary search over P01's `est_tokens()`.

**Interfaces:**
- Consumes (P01, 04 §7.1): `gptr_opt(name)`, `est_tokens(x, class)`, `as_utf8(x)`, `` `%||%` ``; test helper `local_gptr_options(..., .env)` (04 §12.2).
- Produces (internal, used by Tasks 4, 6, 7 and 8-11): `r_call_new(ctx)` -> environment of class `gptr_r_call` (`ctx`, `images`, `dropped`, `printed`, `bridge`, `artifacts`); `ns_r_call()` -> the innermost marker or `NULL`; `r_call_attach_image(block)` -> `invisible(TRUE/FALSE)` (`FALSE` outside an `r` call and beyond `gptr.r_max_images`); `member_budget()` -> num(1); `lines_fit(lines, budget, class = "r_output")` -> int(1); `budget_head(lines, budget, class)` -> `list(lines, omitted)`; `budget_head_tail(lines, budget, class)` -> `list(head, tail, omitted)`; `ns_print_lines(lines)`; `new_gptr_text(x)` -> `c("gptr_text", "character")` with `print.gptr_text()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-namespace.R`:

```r
# Tests for R/tool-namespace.R (P10): member printing budgets and the r-call marker; member
# closures, resolution and plugin namespaces (IC-37); BM25 search, help, describe, plot, out and the
# file members; builtin:tools (one spec per capability, guidelines, fragments, the plugins section,
# services).

png1 = jsonlite::base64_dec(paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
  "BAEAX+XDSwAAAABJRU5ErkJggg=="
))

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# Evaluate `expr_fun()` as if it ran inside the `r` tool: the r-call marker is bound in this frame
with_r_call = function(expr_fun, ctx = NULL) {
  gptr_r_call = r_call_new(ctx)
  expr_fun()
}

test_that("ns_r_call() finds the innermost r-call marker on the stack and nothing outside", {
  expect_null(ns_r_call())
  outer_ctx = list(tag = "outer")
  inner_ctx = list(tag = "inner")
  seen = with_r_call(function() {
    a = ns_r_call()$ctx$tag
    b = with_r_call(function() ns_r_call()$ctx$tag, inner_ctx)
    c(a, b)
  }, outer_ctx)
  expect_identical(seen, c("outer", "inner"))
  expect_null(ns_r_call())
})

test_that("a variable called gptr_r_call without the marker class is ignored", {
  gptr_r_call = new.env()
  expect_null((function() ns_r_call())())
})

test_that("r_call_attach_image() collects images only inside an r call", {
  expect_false(r_call_attach_image(list(type = "image")))
  n = with_r_call(function() {
    r_call_attach_image(list(type = "image", data = "AA"))
    r_call_attach_image(list(type = "image", data = "BB"))
    length(ns_r_call()$images)
  })
  expect_identical(n, 2L)
})

test_that("r_call_attach_image() attaches at most gptr.r_max_images and counts the rest", {
  local_gptr_options(r_max_images = 3L)
  got = with_r_call(function() {
    ok = vapply(1:5, function(i) r_call_attach_image(list(type = "image", data = "AA")), NA)
    list(ok = ok, n = length(ns_r_call()$images), dropped = ns_r_call()$dropped)
  })
  expect_identical(got$ok, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(got$n, 3L)
  expect_identical(got$dropped, 2L)
})

test_that("member_budget() is gptr.helper_output_tokens, capped at 0.6 x the r budget inside r", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 4000L)
  expect_identical(member_budget(), 1500)
  expect_identical(with_r_call(function() member_budget()), 1500)
  local_gptr_options(r_output_tokens = 1000L)
  expect_identical(with_r_call(function() member_budget()), 600)
})

test_that("member prints inside one r call shrink the budget (0.6 x the remaining r budget)", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 1000L)
  words = rep("several words of printed member output on one line", 20)
  got = with_r_call(function() {
    first = member_budget()
    utils::capture.output(ns_print_lines(words))
    c(first, ns_r_call()$printed, member_budget())
  })
  expect_identical(got[1], 600)
  expect_identical(got[2], est_tokens(words, "r_output"))
  expect_identical(got[3], floor(0.6 * (1000 - got[2])))
  utils::capture.output(ns_print_lines(words))
  expect_identical(member_budget(), 1500)
})

test_that("budget_head() and budget_head_tail() keep whole lines within the budget", {
  lines = sprintf("row %04d of a long printed result with some words", 1:500)
  h = budget_head(lines, 200)
  expect_lte(est_tokens(h$lines, "r_output"), 200)
  expect_identical(h$omitted, 500L - length(h$lines))
  expect_identical(h$lines, lines[seq_along(h$lines)])
  ht = budget_head_tail(lines, 200)
  expect_lte(est_tokens(c(ht$head, ht$tail), "r_output"), 200)
  expect_identical(ht$tail, utils::tail(lines, length(ht$tail)))
  expect_identical(length(ht$head) + length(ht$tail) + ht$omitted, 500L)
  expect_identical(budget_head(c("a", "b"), 200), list(lines = c("a", "b"), omitted = 0L))
  expect_identical(lines_fit(character(), 10), 0L)
})

test_that("print.gptr_text() prints head and tail within the budget with a notice", {
  local_gptr_options(helper_output_tokens = 100L)
  x = new_gptr_text(sprintf("line %03d of the help text", 1:200))
  out = utils::capture.output(print(x))
  utils::capture.output(expect_invisible(print(x)))
  expect_true(any(grepl("^\\[\\.\\.\\. [0-9]+ lines not printed; index the value", out)))
  expect_lte(est_tokens(out, "r_output"), 130)
  expect_identical(utils::capture.output(print(new_gptr_text(c("a", "b")))), c("a", "b"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "ns_r_call"` (or `"r_call_attach_image"`, `"member_budget"`, `"budget_head"`, `"new_gptr_text"`).

- [ ] **Step 3: Write the implementation**

Create `R/tool-namespace.R`:

```r
# tool-namespace.R -- the `peter$` namespace (P10): member printing within token budgets, the r-call
# marker that tells a member it runs inside model code, member closures generated from tool specs,
# member resolution (the `ns.resolve`, `ns.names` and `search.sources` services behind P08's gateway
# methods, IC-36), `gptr_ns` nodes for plugin and MCP namespaces, the plugin catalog, BM25 search,
# `peter$help()`, `peter$search()`, `peter$describe()`, `peter$plot()`, `peter$out()`, the specs of
# `read`, `edit`, `write`, `grep`, `find`, `ls` (one per capability, direct and member forms,
# IC-37), their `<rules>` guidelines, the `<r_session>` fragments and `builtin:tools` (IC-68).
# Sources: dev/research/G5-polyglot-glue-helpers.md (gateway-as-namespace pattern verified by the
# `gwtoy` R CMD check; 1,500-token prints and 0.6 x the r budget inside r),
# dev/research/G1-extensibility-sdk-surface.md sections 2.5 and 2.8 (one signature line per member;
# closures built by replacing formals(), never by replacing the environment),
# dev/research/06-pi-subagents-mcp-codemode.md section 5.7 (BM25 port, parity with Pi),
# dev/research/20-harness-feature-survey.md section 5.2 (help text through tools::Rd2txt, no `:::`).

#' Class of the marker that the `r` tool binds (as `gptr_r_call`) in its own frame while it
#' evaluates
#' @noRd
r_call_class = "gptr_r_call"

#' A new r-call marker: the session ctx plus collectors for images, bridge digests and artifact
#' paths
#'
#' The `r` tool binds it as the local variable `gptr_r_call` of its execute frame, so it exists
#' exactly for the dynamic extent of one evaluation and no package-level run state is kept
#' (INFRA-15). It holds no user object and no user frame.
#' @noRd
r_call_new = function(ctx) {
  rc = new.env(parent = emptyenv())
  rc$ctx = ctx
  rc$images = list()
  rc$dropped = 0L
  rc$printed = 0
  rc$bridge = character()
  rc$artifacts = character()
  class(rc) = r_call_class
  rc
}

#' The innermost r-call marker on the call stack, or NULL outside an `r` evaluation
#'
#' Walks the frames from the innermost outwards with sys.frame(k) (never sys.frames(), rule R3) and
#' looks only for the binding `gptr_r_call` of class `gptr_r_call`; no promise is forced.
#' @noRd
ns_r_call = function() {
  k = sys.nframe() - 1L
  while (k > 0L) {
    fr = sys.frame(k)
    if (exists("gptr_r_call", envir = fr, inherits = FALSE)) {
      rc = get("gptr_r_call", envir = fr, inherits = FALSE)
      if (inherits(rc, r_call_class)) return(rc)
    }
    k = k - 1L
  }
  NULL
}

#' Attach an image block to the result of the innermost running `r` call; FALSE when there is none
#' or when gptr.r_max_images images are attached already (the refused ones are counted in
#' `dropped`, which the r tool names in a notice; IC-67)
#' @noRd
r_call_attach_image = function(block) {
  rc = ns_r_call()
  if (is.null(rc)) return(invisible(FALSE))
  if (length(rc$images) >= as.integer(gptr_opt("r_max_images"))) {
    rc$dropped = rc$dropped + 1L
    return(invisible(FALSE))
  }
  rc$images = c(rc$images, list(block))
  invisible(TRUE)
}

#' Print budget of a member result: gptr.helper_output_tokens, and inside r at most 0.6 x the r
#' budget that the member prints of this evaluation have left (04 section 9.4; G5)
#' @noRd
member_budget = function() {
  b = as.numeric(gptr_opt("helper_output_tokens"))
  rc = ns_r_call()
  if (!is.null(rc)) {
    left = max(0, as.numeric(gptr_opt("r_output_tokens")) - rc$printed)
    b = min(b, floor(0.6 * left))
  }
  b
}

#' The largest number of leading lines within a token budget (binary search over est_tokens())
#' @noRd
lines_fit = function(lines, budget, class = "r_output") {
  lo = 0L
  hi = length(lines)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (est_tokens(lines[seq_len(mid)], class) <= budget) lo = mid else hi = mid - 1L
  }
  lo
}

#' Leading lines within a budget and the number of lines left out
#' @noRd
budget_head = function(lines, budget, class = "r_output") {
  if (!length(lines) || est_tokens(lines, class) <= budget) {
    return(list(lines = lines, omitted = 0L))
  }
  k = lines_fit(lines, budget, class)
  list(lines = lines[seq_len(k)], omitted = length(lines) - k)
}

#' Head (40% of the budget) and tail (60%) of lines and the number left out
#' @noRd
budget_head_tail = function(lines, budget, class = "r_output") {
  n = length(lines)
  if (!n || est_tokens(lines, class) <= budget) {
    return(list(head = lines, tail = character(), omitted = 0L))
  }
  h = lines_fit(lines, 0.4 * budget, class)
  t = min(lines_fit(rev(lines), 0.6 * budget, class), n - h)
  list(head = lines[seq_len(h)], tail = if (t > 0L) lines[(n - t + 1L):n] else character(),
       omitted = n - h - t)
}

#' Write lines of a member result to standard output as UTF-8 bytes (the evaluator's sink captures
#' them); inside an `r` call their estimated tokens are added to the marker's `printed` count
#'
#' Plain writeLines(): the text is data, never a format string (rule C1), and cli output would go to
#' stderr in non-interactive sessions, where the evaluator's sink does not see it.
#' @noRd
ns_print_lines = function(lines) {
  lines = as_utf8(as.character(lines))
  rc = ns_r_call()
  if (!is.null(rc)) rc$printed = rc$printed + est_tokens(lines, "r_output")
  writeLines(lines, useBytes = TRUE)
  invisible(NULL)
}

#' A character result (`peter$help()`, `peter$out()`) that prints within the member budget
#' @noRd
new_gptr_text = function(x) structure(as_utf8(as.character(x)), class = c("gptr_text", "character"))

#' Print a gptr text result: head and tail within the member budget
#'
#' @param x A `gptr_text` character vector.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_text = function(x, ...) {
  s = budget_head_tail(as.character(x), member_budget())
  mid = if (s$omitted > 0L) {
    paste0("[... ", s$omitted, " lines not printed; index the value, e.g. x[a:b]]")
  }
  ns_print_lines(c(s$head, mid, s$tail))
  invisible(x)
}
```

Regenerate `NAMESPACE` (adds `S3method(print,gptr_text)`):

```bash
Rscript --vanilla -e 'devtools::document()'
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 28 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/tool-namespace.R tests/testthat/test-tool-namespace.R NAMESPACE
git commit -m "feat(tools): add the r-call marker and member print budgets"
```

### Task 2: Paths, globs, `.gitignore` and the walker

**Files:** Create: `R/tool-walk.R`; Test: `tests/testthat/test-tool-walk.R`.

`tool-walk.R` is the "L4 svc" file other built-ins may call (architecture §2.2: P11 rule globs, P16 file tracking, P18 exposure globs). It is a port of report 11 §5.5 (`proto/01-paths.R`, `proto/40-walk.R`; the walker's file set equalled `git ls-files --others --exclude-standard` on 14 rule kinds, §2.6) with the verification-log fixes applied: Pi's `**/` prefix rule for patterns containing `/` (row 5; proposal P-C C-29), `path.expand()` only for `~`, `~/` and `~\` (row 18), and no probe file written to detect a case-insensitive file system (`fs_case_insensitive()` flips the case of an existing path component and asks whether the flipped spelling exists). `resolve_tool_path()` follows Pi's `resolveToCwd` (report 11 §2.8: Unicode spaces become `" "`, one leading `@` is dropped, `file://` URLs are decoded, Git-Bash and WSL drive paths are rewritten on Windows). `fs_path()` hands UTF-8 bytes without a mark to base file functions in non-UTF-8 Unix locales (report 01 E4). The walker prunes `.git/`, `node_modules/`, `.Rproj.user/`, the `renv` library/staging/sandbox, `packrat` libraries, `.venv/`, `__pycache__/`, `.ipynb_checkpoints/` and `.quarto/`, reads `.git/info/exclude`, then `.gitignore`, `.ignore` and `.gptrignore` of the ancestors up to the git root and of every directory walked (deeper files later, so they win), lists symlinked directories without following them, and stops at 500,000 entries.

**Interfaces:**
- Consumes (P01, 04 §7.1): `as_utf8()`, `read_utf8(path)`, `check_string()`, `check_strings()`, `check_choice()`, `check_number()`, `check_flag()`, `gptr_abort()`.
- Produces (04 §7.10): `walk_files(root = ".", type = c("file", "dir", "any"), gitignore = TRUE, hidden = FALSE, max = Inf, prune = NULL)` -> df `path` (relative to `root`), `size`, `mtime`, `type`; `glob_to_regex(glob)` -> chr(1) PCRE; internal helpers used by Tasks 4-10: `fs_path(p)`, `tool_path_is_abs(p)`, `tool_path_norm(p)`, `resolve_tool_path(path, cwd = getwd())` -> absolute normalised chr(1), `fs_case_insensitive(dir)` -> lgl(1).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-walk.R` (oracle cases of report 11 §5.6 "glob / gitignore / walk" and report 01 §5.9 `test-02.R`, adapted to Pi's `**/` rule; the git oracle compares the file set with `git ls-files --others --exclude-standard`):

```r
# Tests for R/tool-walk.R: path resolution, globs (Pi semantics), the .gitignore engine and the
# walker. Oracle cases from dev/research/11-r-file-tools.md section 5.6 (tests/test-tools.R, "glob /
# gitignore / walk") and dev/research/01-pi-builtin-tools.md section 5.9 (test-02.R), adapted to
# Pi's `**/` rule; the git oracle compares the file set with `git ls-files --others
# --exclude-standard`.

put = function(root, rel, text = "x\n") {
  p = file.path(root, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(text), p)
  invisible(p)
}

test_that("resolve_tool_path() follows Pi's resolveToCwd rules", {
  expect_identical(resolve_tool_path("sub/../f.R", "/w"), "/w/f.R")
  expect_identical(resolve_tool_path("@src/x.R", "/w"), "/w/src/x.R")
  expect_identical(resolve_tool_path("a\u00a0b.txt", "/w"), "/w/a b.txt")
  expect_identical(resolve_tool_path("file:///tmp/a%20b.txt", "/w"), "/tmp/a b.txt")
  expect_identical(resolve_tool_path("~/x", "/w"), tool_path_norm(path.expand("~/x")))
  expect_identical(resolve_tool_path("~draft.md", "/c"), "/c/~draft.md")
  expect_identical(tool_path_norm("/a/./b/../c//d/"), "/a/c/d")
  expect_identical(tool_path_norm("C:\\x\\..\\y\\.\\z"), "C:/y/z")
  expect_identical(tool_path_norm("C:/.."), "C:/")
  expect_identical(tool_path_norm("\\\\server\\share\\..\\x"), "//server/share/x")
  expect_identical(tool_path_norm("../../a"), "../../a")
  expect_true(tool_path_is_abs("C:\\x") && tool_path_is_abs("/x") && !tool_path_is_abs("x/y"))
})

test_that("glob_to_regex() implements fd/Pi semantics including the `**/` prefix rule", {
  g = function(glob, x) grepl(glob_to_regex(glob), x, perl = TRUE)
  expect_identical(g("*.R", c("a.R", "d/a.R", "a.r", "a.Rmd")), c(TRUE, TRUE, FALSE, FALSE))
  expect_identical(g("src/*.R", c("src/a.R", "src/x/a.R", "a/src/a.R")), c(TRUE, FALSE, TRUE))
  expect_identical(g("/src/*.R", c("src/a.R", "a/src/a.R")), c(TRUE, FALSE))
  expect_identical(g("**/*.R", c("a.R", "d/e/a.R")), c(TRUE, TRUE))
  expect_identical(g("src/**/*.spec.ts", c("src/a.spec.ts", "src/x/y/a.spec.ts", "lib/a.spec.ts")),
                   c(TRUE, TRUE, FALSE))
  expect_identical(g("some/parent/child/**", c("some/parent/child/f.ext", "some/parent/x")),
                   c(TRUE, FALSE))
  expect_identical(g("*.{R,Rmd,qmd}", c("a.R", "b.Rmd", "c.qmd", "d.md")),
                   c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(g("[ab].R", c("a.R", "b.R", "c.R")), c(TRUE, TRUE, FALSE))
  expect_identical(g("[!ab].R", c("a.R", "c.R")), c(FALSE, TRUE))
  expect_identical(g("file?.[ch]", c("file1.c", "file1.h", "file12.c")), c(TRUE, TRUE, FALSE))
  expect_identical(g("a+b(1).R", c("a+b(1).R", "aab(1).R")), c(TRUE, FALSE))
  expect_identical(g("{a,b", "{a,b"), TRUE)
  expect_error(glob_to_regex(""), class = "gptr_error_invalid_argument")
})

test_that("the .gitignore engine: negation, anchoring, dir-only rules, `**`, escapes, blanks", {
  td = withr::local_tempdir()
  rules = c("# comment", "", "*.log", "!keep.log", "/rootonly.txt", "build/", "docs/**/*.tmp",
            "sub/inner.txt", "trail.txt   ", "\\#hash.txt", "data/*", "!data/keep/")
  put(td, ".gitignore", paste(rules, collapse = "\n"))
  files = c("a.log", "keep.log", "x/y/b.log", "rootonly.txt", "x/rootonly.txt", "build/o.txt",
            "x/build/o.txt", "build.txt", "docs/a.tmp", "docs/p/q/b.tmp", "docs/b.md",
            "sub/inner.txt", "x/sub/inner.txt", "trail.txt", "#hash.txt", "data/raw.csv",
            "data/keep/k.csv", "src/main.R")
  for (p in files) put(td, p)
  w = walk_files(td, type = "file", hidden = TRUE)
  expect_identical(sort(w$path, method = "radix"),
                   sort(c(".gitignore", "keep.log", "x/rootonly.txt", "build.txt", "docs/b.md",
                          "x/sub/inner.txt", "data/keep/k.csv", "src/main.R"), method = "radix"))
})

test_that("nested .gitignore files apply to their own subtree only", {
  td = withr::local_tempdir()
  put(td, "a/.gitignore", "ignored.txt\n")
  put(td, "a/deep/.gitignore", "secret.txt\n")
  for (p in c("a/ignored.txt", "a/kept.txt", "a/deep/ignored.txt", "a/deep/secret.txt",
              "a/deep/kept.txt", "b/ignored.txt", "b/kept.txt", "root.txt")) {
    put(td, p)
  }
  w = walk_files(td, type = "file", hidden = FALSE)
  expect_identical(w$path, c("a/deep/kept.txt", "a/kept.txt", "b/ignored.txt", "b/kept.txt",
                             "root.txt"))
})

test_that("the walker prunes .git, node_modules, renv/library; dotfiles only with hidden = TRUE", {
  td = withr::local_tempdir()
  for (p in c(".git/config", "node_modules/p/i.js", "renv/library/x/DESCRIPTION", "renv/activate.R",
              ".hid/h.txt", "R/a.R")) put(td, p)
  w = walk_files(td, type = "file", hidden = TRUE)
  expect_identical(w$path, c(".hid/h.txt", "R/a.R", "renv/activate.R"))
  expect_identical(walk_files(td, type = "file")$path, c("R/a.R", "renv/activate.R"))
  expect_identical(walk_files(td, type = "dir", hidden = TRUE)$path, c(".hid", "R", "renv"))
})

test_that("walk_files() returns path, size, mtime, type and honours max", {
  td = withr::local_tempdir()
  put(td, "a.txt", "12345")
  put(td, "d/b.txt", "1")
  w = walk_files(td, type = "any")
  expect_named(w, c("path", "size", "mtime", "type"))
  expect_identical(w$type, c("file", "dir", "file"))
  expect_identical(w$size[w$path == "a.txt"], 5)
  expect_true(is.na(w$size[w$path == "d"]))
  expect_s3_class(w$mtime, "POSIXct")
  expect_identical(nrow(walk_files(td, type = "any", max = 1)), 1L)
  expect_error(walk_files(file.path(td, "nope")), class = "gptr_error_invalid_argument")
})

test_that("max counts only rows of the requested type (directories do not use it up)", {
  td = withr::local_tempdir()
  for (i in 1:12) put(td, sprintf("d%02d/f.txt", i))
  w = walk_files(td, type = "file", max = 5)
  expect_identical(w$path, sprintf("d%02d/f.txt", 1:5))
  expect_true(attr(w, "truncated"))
  expect_identical(nrow(walk_files(td, type = "dir", max = 3)), 3L)
  expect_false(attr(walk_files(td, type = "file"), "truncated"))
})

test_that("ancestor .gitignore files apply when walking a subdirectory of a repository", {
  td = withr::local_tempdir()
  dir.create(file.path(td, ".git"))
  put(td, ".gitignore", "*.tmp\n")
  put(td, "src/a.R")
  put(td, "src/b.tmp")
  expect_identical(walk_files(file.path(td, "src"))$path, "a.R")
})

test_that("the file set equals git ls-files on a repository with tricky rules", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  td = withr::local_tempdir()
  files = c("a.R", "b.log", "keep.log", "build/out.o", "build/keep.txt", "doc/frotz/x.txt",
            "a/doc/frotz/y.txt", "src/deep/tmp.R", "src/deep/.hidden", "src/gen/g.R",
            "src/gen/keep.R", "logs/2026/a.txt", "logs/2026/b.txt", "sp ace.txt",
            "nested/inner/drop.csv", "nested/inner/ok.R", "nested/drop.csv", "abc/x/y",
            "#hash.txt", "!bang.txt")
  for (f in files) put(td, f)
  rules = c("# comment", "*.log", "!keep.log", "build/", "!build/keep.txt", "/doc/frotz/",
            "logs/**/b.txt", "sp\\ ace.txt", "abc/**", "\\#hash.txt", "\\!bang.txt", "",
            "src/deep/tmp.R   ")
  put(td, ".gitignore", paste(rules, collapse = "\n"))
  put(td, "src/.gitignore", "gen/*\n!gen/keep.R\n")
  put(td, "nested/inner/.gitignore", "*.csv\n")
  system2("git", c("-C", shQuote(td), "init", "-q"), stdout = FALSE, stderr = FALSE)
  git = sort(system2("git", c("-C", shQuote(td), "ls-files", "--others", "--exclude-standard"),
                     stdout = TRUE), method = "radix")
  ours = sort(walk_files(td, hidden = TRUE)$path, method = "radix")
  expect_identical(ours, git)
})

test_that("a symlinked directory is listed but not followed", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  dir.create(file.path(td, "a"))
  file.symlink(td, file.path(td, "a", "back"))
  w = walk_files(td, type = "any")
  expect_true("a/back" %in% w$path)
  expect_identical(w$type[w$path == "a/back"], "link")
  expect_false(any(startsWith(w$path, "a/back/")))
})

test_that("fs_case_insensitive() writes nothing", {
  td = withr::local_tempdir()
  before = list.files(td, all.files = TRUE, no.. = TRUE)
  expect_type(fs_case_insensitive(normalizePath(td)), "logical")
  expect_identical(list.files(td, all.files = TRUE, no.. = TRUE), before)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-walk")'
```

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "resolve_tool_path"` (or `"glob_to_regex"`, `"walk_files"`, `"fs_case_insensitive"`).

- [ ] **Step 3: Write the implementation**

Create `R/tool-walk.R`:

```r
# tool-walk.R -- tool path resolution, glob to PCRE, the .gitignore engine and the pruned walker
# (P10; an L4 service that P11, P16 and P18 also use, contract section 7.10). Ported from
# dev/research/11-r-file-tools.md section 5.5 (proto/01-paths.R, proto/40-walk.R; walker file set
# equal to `git ls-files` on 14 rule kinds, section 2.6) with its verification log applied: Pi's
# `**/` prefix rule for patterns containing "/" (row 5; proposal P-C C-29), path.expand() only for
# "~", "~/" and "~\" (row 18), no probe file written to detect a case-insensitive file system.

walk_default_prune = c(".git/", "node_modules/", ".Rproj.user/", "renv/library/", "renv/staging/",
                       "renv/sandbox/", "packrat/lib*/", "packrat/src/", ".venv/", "__pycache__/",
                       ".ipynb_checkpoints/", ".quarto/")
walk_ignore_files = c(".gitignore", ".ignore", ".gptrignore")
walk_max_entries = 500000L

#' Path handed to base file-system functions: UTF-8 bytes without a mark in non-UTF-8 Unix locales
#' (a marked non-ASCII path fails there with "unable to translate"; report 01 E4)
#' @noRd
fs_path = function(p) {
  if (.Platform$OS.type != "windows" && !isTRUE(l10n_info()[["UTF-8"]])) Encoding(p) = "unknown"
  p
}

#' Is a path absolute ("/x", "C:/x", "C:\\x", UNC)?
#' @noRd
tool_path_is_abs = function(p) grepl("^([/\\\\]|[A-Za-z]:[/\\\\])", p)

#' Root prefix of a "/"-separated path (drive, UNC share or "/"), "" for a relative path
#' @noRd
tool_path_prefix = function(p) {
  if (grepl("^[A-Za-z]:/", p)) return(substr(p, 1L, 3L))
  if (grepl("^//[^/]+/[^/]+", p)) return(regmatches(p, regexpr("^//[^/]+/[^/]+/?", p)))
  if (startsWith(p, "/")) return("/")
  ""
}

#' Lexical path normalisation (no file-system access; ".." never climbs above a root)
#' @noRd
tool_path_norm = function(p) {
  p = gsub("\\", "/", as_utf8(p), fixed = TRUE)
  pre = tool_path_prefix(p)
  if (nzchar(pre)) {
    p = substring(p, nchar(pre) + 1L)
    if (!endsWith(pre, "/")) pre = paste0(pre, "/")
  }
  out = character()
  for (s in strsplit(p, "/", fixed = TRUE)[[1L]]) {
    if (s == "" || s == ".") next
    if (s == "..") {
      if (length(out) && out[length(out)] != "..") {
        out = out[-length(out)]
      } else if (!nzchar(pre)) {
        out = c(out, "..")
      }
      next
    }
    out = c(out, s)
  }
  res = paste0(pre, paste(out, collapse = "/"))
  if (!nzchar(res)) res = "."
  if (nchar(res) > 1L && endsWith(res, "/") && !grepl("^[A-Za-z]:/$", res)) {
    res = sub("/+$", "", res)
  }
  as_utf8(res)
}

#' Resolve a model- or user-supplied path to an absolute, normalised path (Pi resolveToCwd; report
#' 11 section 2.8): Unicode spaces become " ", one leading "@" is dropped, file:// URLs are decoded,
#' Git-Bash and WSL drive paths are rewritten on Windows, "~" is expanded (only "~", "~/", "~\\").
#' @noRd
resolve_tool_path = function(path, cwd = getwd()) {
  p = as_utf8(path)
  cp = utf8ToInt(p)
  spaces = c(0xA0L, 0x2000:0x200A, 0x202FL, 0x205FL, 0x3000L)
  if (length(cp) && !anyNA(cp) && any(cp %in% spaces)) {
    cp[cp %in% spaces] = 32L
    p = intToUtf8(cp)
  }
  if (startsWith(p, "@")) p = substring(p, 2L)
  if (grepl("^file://", p)) {
    p = utils::URLdecode(sub("^file://(localhost)?", "", p))
    if (.Platform$OS.type == "windows") p = sub("^/([A-Za-z]:)", "\\1", p)
  }
  if (.Platform$OS.type == "windows" && grepl("^/(mnt/|cygdrive/)?[A-Za-z](/|$)", p) &&
        !startsWith(p, "//")) {
    p = sub("^/(mnt/|cygdrive/)?([A-Za-z])(/|$)", "\\2:/", p)
  }
  if (p == "~" || startsWith(p, "~/") || startsWith(p, "~\\")) p = as_utf8(path.expand(p))
  if (.Platform$OS.type == "windows" && grepl("^[A-Za-z]:[^/\\\\]", p)) {
    p = normalizePath(p, winslash = "/", mustWork = FALSE)
  }
  if (!tool_path_is_abs(p)) p = paste0(gsub("\\", "/", as_utf8(cwd), fixed = TRUE), "/", p)
  tool_path_norm(p)
}

#' Translate one glob into a PCRE body (no anchors)
#'
#' `*` and `?` never cross "/"; `**` as a whole segment crosses directories; `[abc]`, `[!a-z]`,
#' `[^a]` and POSIX classes; `{a,b}` alternation only when balanced; a backslash escapes the next
#' character; every other regex metacharacter is escaped (report 11 section 3.4).
#' @noRd
glob_translate = function(glob, braces = TRUE) {
  ch = strsplit(as_utf8(glob), "", fixed = TRUE)[[1L]]
  n = length(ch)
  i = 1L
  out = character()
  depth = 0L
  meta = c(".", "+", "(", ")", "|", "^", "$", "{", "}", "[", "]", "\\", "*", "?")
  esc = function(x) if (x %in% meta) paste0("\\", x) else x
  closes = function(from) {
    d = 0L
    for (j in from:n) {
      if (ch[j] == "{") d = d + 1L
      if (ch[j] == "}") {
        d = d - 1L
        if (d == 0L) return(TRUE)
      }
    }
    FALSE
  }
  while (i <= n) {
    chr = ch[i]
    if (chr == "\\" && i < n) {
      out = c(out, esc(ch[i + 1L]))
      i = i + 2L
      next
    }
    if (chr == "*") {
      j = i
      while (j < n && ch[j + 1L] == "*") j = j + 1L
      seg_start = i == 1L || ch[i - 1L] == "/"
      seg_end = j == n || ch[j + 1L] == "/"
      if (j > i && seg_start && seg_end) {
        if (j == n) {
          out = c(out, if (i == 1L) ".*" else "(?:.*)?")
          i = j + 1L
        } else {
          out = c(out, "(?:[^/]*/)*")
          i = j + 2L
        }
      } else {
        out = c(out, "[^/]*")
        i = j + 1L
      }
      next
    }
    if (chr == "?") {
      out = c(out, "[^/]")
      i = i + 1L
      next
    }
    if (chr == "[") {
      j = i + 1L
      if (j <= n && ch[j] %in% c("!", "^")) j = j + 1L
      if (j <= n && ch[j] == "]") j = j + 1L
      while (j <= n && ch[j] != "]") {
        if (ch[j] == "[" && j < n && ch[j + 1L] == ":") {
          k = j + 2L
          while (k < n && !(ch[k] == ":" && ch[k + 1L] == "]")) k = k + 1L
          j = k + 1L
        }
        j = j + 1L
      }
      if (j > n) {
        out = c(out, "\\[")
        i = i + 1L
        next
      }
      body = ch[(i + 1L):(j - 1L)]
      neg = length(body) > 0L && body[1L] %in% c("!", "^")
      if (neg) body = body[-1L]
      body = vapply(seq_along(body), function(k) {
        if (body[k] == "\\" || (body[k] == "]" && k > 1L)) paste0("\\", body[k]) else body[k]
      }, "")
      out = c(out, paste0("[", if (neg) "^/", paste(body, collapse = ""), "]"))
      i = j + 1L
      next
    }
    if (braces && chr == "{" && closes(i)) {
      depth = depth + 1L
      out = c(out, "(?:")
      i = i + 1L
      next
    }
    if (braces && chr == "}" && depth > 0L) {
      depth = depth - 1L
      out = c(out, ")")
      i = i + 1L
      next
    }
    if (braces && chr == "," && depth > 0L) {
      out = c(out, "|")
      i = i + 1L
      next
    }
    out = c(out, esc(chr))
    i = i + 1L
  }
  as_utf8(paste(out, collapse = ""))
}

#' Glob to an anchored PCRE for "/"-separated paths relative to the search root (contract section
#' 7.10)
#'
#' fd/Pi semantics: a pattern without "/" matches the basename at any depth; a pattern with "/" gets
#' Pi's `**/` prefix (so `src/*.R` also matches `a/src/x.R`) unless it starts with `**/` or is `**`
#' (Pi find.ts:201-214; report 11 verification log row 5); a leading "/" anchors at the root.
#' @param glob A glob pattern, chr(1).
#' @return chr(1), a PCRE to use with `perl = TRUE`.
#' @noRd
glob_to_regex = function(glob) {
  check_string(glob, "glob")
  g = as_utf8(glob)
  if (startsWith(g, "/")) return(paste0("^", glob_translate(substring(g, 2L)), "$"))
  if (!grepl("/", g, fixed = TRUE)) return(paste0("^(?:.*/)?", glob_translate(g), "$"))
  if (!startsWith(g, "**/") && g != "**") g = paste0("**/", g)
  paste0("^", glob_translate(g), "$")
}

#' Compile ignore-file lines into rules (git PATTERN FORMAT; report 11 section 3.4)
#' @noRd
ignore_compile = function(lines, base = "", ignore_case = FALSE) {
  rules = list()
  for (ln in lines) {
    ln = sub("\r$", "", ln)
    if (!nzchar(ln) || startsWith(ln, "#")) next
    ln = sub("(?<!\\\\)[ ]+$", "", ln, perl = TRUE)
    if (!nzchar(ln) || (endsWith(ln, "\\") && !endsWith(ln, "\\ "))) next
    neg = startsWith(ln, "!")
    if (neg) ln = substring(ln, 2L)
    if (startsWith(ln, "\\#") || startsWith(ln, "\\!")) ln = substring(ln, 2L)
    dir_only = endsWith(ln, "/")
    if (dir_only) ln = sub("/+$", "", ln)
    if (!nzchar(ln)) next
    anchored = grepl("/", ln, fixed = TRUE)
    ln = sub("^/", "", ln)
    if (ignore_case) ln = tolower(ln)
    kind = "regex"
    if (!anchored && !grepl("[][*?\\\\]", ln)) {
      kind = "literal"
      value = ln
    } else if (!anchored && grepl("^\\*[^][*?\\\\]+$", ln)) {
      kind = "suffix"
      value = substring(ln, 2L)
    } else {
      value = paste0("^", glob_translate(ln, braces = FALSE), "$")
    }
    rules[[length(rules) + 1L]] = list(kind = kind, value = value, negated = neg,
                                       dir_only = dir_only, anchored = anchored, base = base)
  }
  rules
}

#' Evaluate compiled rules: TRUE ignored, FALSE re-included, NA no rule matched (the last match
#' wins)
#' @noRd
ignore_eval = function(rules, rel, is_dir, ignore_case = FALSE) {
  res = rep(NA, length(rel))
  if (!length(rules) || !length(rel)) return(res)
  relc = if (ignore_case) tolower(rel) else rel
  bn = basename(relc)
  for (r in rules) {
    base = if (ignore_case) tolower(r$base) else r$base
    cand = if (nzchar(base)) startsWith(relc, paste0(base, "/")) else rep(TRUE, length(rel))
    if (r$dir_only) cand = cand & is_dir
    if (!any(cand)) next
    idx = which(cand)
    tgt = if (r$anchored) {
      if (nzchar(base)) substring(relc[idx], nchar(base) + 2L) else relc[idx]
    } else {
      bn[idx]
    }
    hit = switch(r$kind,
                 literal = tgt == r$value,
                 suffix = endsWith(tgt, r$value),
                 regex = grepl(r$value, tgt, perl = TRUE))
    res[idx[hit]] = !r$negated
  }
  res
}

#' Lines of an ignore file (none when it cannot be read)
#' @noRd
ignore_read_lines = function(f) {
  txt = tryCatch(read_utf8(fs_path(f))$text, error = function(e) "")
  if (!nzchar(txt)) return(character())
  strsplit(txt, "\n", fixed = TRUE)[[1L]]
}

#' Nearest ancestor (or self) holding a .git entry, or NULL
#' @noRd
git_root_of = function(dir) {
  cur = dir
  repeat {
    if (file.exists(fs_path(file.path(cur, ".git")))) return(cur)
    parent = dirname(cur)
    if (identical(parent, cur)) return(NULL)
    cur = parent
  }
}

#' Is the file system holding `dir` case-insensitive? Flips the case of a path component and asks
#' whether it still exists; writes nothing
#' @noRd
fs_case_insensitive = function(dir) {
  if (.Platform$OS.type == "windows") return(TRUE)
  cur = dir
  repeat {
    b = basename(cur)
    flip = chartr(paste(c(letters, LETTERS), collapse = ""),
                  paste(c(LETTERS, letters), collapse = ""), b)
    if (!identical(flip, b)) return(file.exists(fs_path(file.path(dirname(cur), flip))))
    parent = dirname(cur)
    if (identical(parent, cur)) return(identical(Sys.info()[["sysname"]], "Darwin"))
    cur = parent
  }
}

#' Breadth-first walk that prunes ignored directories before descending (report 11 walk_tree)
#'
#' One list.files() per directory and one vectorised dir.exists()/Sys.readlink() per level;
#' symlinked directories are listed but never followed (a canonical-path guard on Windows, where
#' Sys.readlink() returns ""). Rules: the prune list, `.git/info/exclude`, ignore files of ancestors
#' up to the git root, then the ignore files found while walking (deeper files later, so they win).
#' The walk stops after the level at which more than `max_rows` entries of kind `count` (`"file"`,
#' `"dir"` or `"any"`) were kept, or at `max_entries` entries of any kind (the safety cap).
#' @noRd
walk_tree = function(root, hidden = TRUE, gitignore = TRUE, prune = walk_default_prune,
                     max_entries = walk_max_entries, max_rows = Inf, count = "any") {
  root = as_utf8(normalizePath(fs_path(root), winslash = "/", mustWork = TRUE))
  detect_cycles = .Platform$OS.type == "windows"
  visited = if (detect_cycles) root else character()
  ignore_case = fs_case_insensitive(root)
  rules = ignore_compile(prune, "", ignore_case)
  prefix = ""
  if (gitignore) {
    groot = git_root_of(root)
    if (!is.null(groot)) {
      prefix = if (identical(groot, root)) "" else substring(root, nchar(groot) + 2L)
      ex = file.path(groot, ".git", "info", "exclude")
      if (file.exists(fs_path(ex))) {
        rules = c(rules, ignore_compile(ignore_read_lines(ex), "", ignore_case))
      }
      if (nzchar(prefix)) {
        segs = strsplit(prefix, "/", fixed = TRUE)[[1L]]
        bases = c("", vapply(seq_len(length(segs) - 1L), function(k) {
          paste(segs[seq_len(k)], collapse = "/")
        }, ""))
        for (bs in bases) {
          for (nm in walk_ignore_files) {
            f = if (nzchar(bs)) file.path(groot, bs, nm) else file.path(groot, nm)
            if (file.exists(fs_path(f))) {
              rules = c(rules, ignore_compile(ignore_read_lines(f), bs, ignore_case))
            }
          }
        }
      }
    }
  }
  anchor_rel = function(rel) if (nzchar(prefix)) paste(prefix, rel, sep = "/") else rel
  frontier = ""
  acc_rel = list()
  acc_dir = list()
  acc_lnk = list()
  total = 0L
  rows = 0
  truncated = FALSE
  depth = 0L
  while (length(frontier)) {
    depth = depth + 1L
    dirs_abs = ifelse(nzchar(frontier), paste(root, frontier, sep = "/"), root)
    listing = lapply(dirs_abs, function(d) list.files(fs_path(d), all.files = TRUE, no.. = TRUE))
    counts = lengths(listing)
    if (!sum(counts)) break
    nm = as_utf8(unlist(listing, use.names = FALSE))
    parent = rep(frontier, counts)
    rel = ifelse(nzchar(parent), paste(parent, nm, sep = "/"), nm)
    full = paste(root, rel, sep = "/")
    if (gitignore) {
      for (f in which(nm %in% walk_ignore_files)) {
        bs = if (nzchar(parent[f])) anchor_rel(parent[f]) else prefix
        rules = c(rules, ignore_compile(ignore_read_lines(full[f]), bs, ignore_case))
      }
    }
    lnk = Sys.readlink(fs_path(full))
    is_link = !is.na(lnk) & nzchar(lnk)
    is_dir = dir.exists(fs_path(full))
    ign = ignore_eval(rules, anchor_rel(rel), is_dir, ignore_case)
    keep = is.na(ign) | !ign
    if (!hidden) keep = keep & !startsWith(nm, ".")
    rel = rel[keep]
    is_dir = is_dir[keep]
    is_link = is_link[keep]
    acc_rel[[depth]] = rel
    acc_dir[[depth]] = is_dir
    acc_lnk[[depth]] = is_link
    total = total + length(rel)
    rows = rows + switch(count, file = sum(!is_dir), dir = sum(is_dir), length(rel))
    if (total >= max_entries || rows > max_rows) {
      truncated = TRUE
      break
    }
    frontier = rel[is_dir & !is_link]
    if (detect_cycles && length(frontier)) {
      real = as_utf8(normalizePath(fs_path(paste(root, frontier, sep = "/")), winslash = "/",
                                   mustWork = FALSE))
      fresh = !duplicated(real) & !(real %in% visited)
      frontier = frontier[fresh]
      visited = c(visited, real[fresh])
    }
  }
  out = data.frame(rel = as_utf8(as.character(unlist(acc_rel))),
                   is_dir = as.logical(unlist(acc_dir)), is_link = as.logical(unlist(acc_lnk)),
                   stringsAsFactors = FALSE)
  attr(out, "truncated") = truncated
  attr(out, "root") = root
  out
}

#' Walk a directory tree (contract section 7.10)
#'
#' @param root Directory to walk.
#' @param type `"file"`, `"dir"` or `"any"`.
#' @param gitignore Honour `.gitignore`, `.ignore`, `.gptrignore` and `.git/info/exclude`.
#' @param hidden Include dot-files and dot-directories.
#' @param max Maximum number of rows of the requested `type` (directories do not use up a
#'   `type = "file"` limit; `Inf`: the walker cap of 500,000 entries).
#' @param prune Prune rules replacing the default list (`NULL`: `.git`, `node_modules`,
#'   `renv/library`, `.venv`, `__pycache__`, ...).
#' @return A data frame `path` (relative to `root`, "/"-separated), `size` (`NA` for directories),
#'   `mtime`, `type` (`file`, `dir`, `link`), sorted case-insensitively by path (radix); attributes
#'   `root` (the canonical root) and `truncated` (`TRUE` when rows were left out).
#' @noRd
walk_files = function(root = ".", type = c("file", "dir", "any"), gitignore = TRUE, hidden = FALSE,
                      max = Inf, prune = NULL) {
  check_string(root, "root")
  type = check_choice(type, c("file", "dir", "any"), "type")
  check_flag(gitignore, "gitignore")
  check_flag(hidden, "hidden")
  check_number(max, "max", min = 0)
  check_strings(prune, "prune", null = TRUE)
  abs = resolve_tool_path(root)
  if (!dir.exists(fs_path(abs))) {
    gptr_abort(paste0("Path not found: ", abs), "invalid_argument", arg = "root",
               expected = "an existing directory")
  }
  w = walk_tree(abs, hidden = hidden, gitignore = gitignore, prune = prune %||% walk_default_prune,
                max_rows = max, count = type)
  truncated = isTRUE(attr(w, "truncated"))
  if (type == "file") w = w[!w$is_dir, , drop = FALSE]
  if (type == "dir") w = w[w$is_dir, , drop = FALSE]
  real_root = attr(w, "root")
  fi = file.info(fs_path(file.path(real_root, w$rel)), extra_cols = FALSE)
  size = as.numeric(fi$size)
  size[w$is_dir] = NA_real_
  kind = rep("file", nrow(w))
  kind[w$is_dir] = "dir"
  kind[w$is_link] = "link"
  out = data.frame(path = w$rel, size = size, mtime = fi$mtime, type = kind,
                   stringsAsFactors = FALSE)
  out = out[order(tolower(out$path), out$path, method = "radix"), , drop = FALSE]
  if (is.finite(max) && nrow(out) > max) {
    out = out[seq_len(max), , drop = FALSE]
    truncated = TRUE
  }
  rownames(out) = NULL
  attr(out, "root") = real_root
  attr(out, "truncated") = truncated
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-walk")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 48 ]` with git on `PATH` (the git-oracle test skips without git and on CRAN; the symlink test skips on Windows).

- [ ] **Step 5: Commit**

```bash
git add R/tool-walk.R tests/testthat/test-tool-walk.R
git commit -m "feat(tools): add path resolution, globs, the gitignore engine and the walker"
```

### Task 3: Unified diffs

**Files:** Create: `R/tool-diff.R`; Test: `tests/testthat/test-tool-diff.R`.

`diff_lines()` is the diff engine of `edit` (Task 6), P15's document writer and P16's checkpoints (04 §7.10). It is a pure base R port of report 11 §5.5 (`proto/30-diff.R`): common prefix/suffix trim, patience anchors (lines unique in both ranges, longest increasing subsequence through `findInterval()`), Myers O(ND) on the remaining gaps with the cost capped at D = 256 (report 21 §2.3: a gap beyond the cap is reported as a replacement, still a valid edit script; no diffobj, no compiled code), and unified rendering with GNU conventions (`@@ -a,b +c,d @@`, a hunk count of 1 written without `,1`, `\ No newline at end of file`). The verification log's property test (report 11 row 32: 150 random pairs and `git apply` checks) is reproduced in the test: the edit script, applied to the old lines, yields the new lines on generated inputs. `max_tokens` cuts the rendered diff at a line boundary with a notice.

**Interfaces:**
- Consumes (P01): `check_strings()`, `check_number()`, `est_tokens(x, "code")`, `as_utf8()`, `utf8_mark()`.
- Produces (04 §7.10): `diff_lines(old, new, context = 3L, max_tokens = 400L)` -> chr (hunks without file headers; `character()` when equal); internal for Task 6 and P15/P16: `diff_ops(a, b, max_d = 256)` -> `data.frame(op = "=" | "-" | "+", a, b)` in file order, `diff_split(x)` -> `list(lines, final_nl)`, `diff_unified(path, old, new, context = 3L)` -> chr with `--- a/<path>` / `+++ b/<path>` headers.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-diff.R`:

```r
# Tests for R/tool-diff.R: hunks, the validity of edit scripts on generated inputs (the property
# test of dev/research/11-r-file-tools.md verification log row 32), the D = 256 cap, budgets and git
# apply.

apply_ops = function(a, b, ops) {
  keep = ops$op != "-"
  out = character(sum(keep))
  out[ops$op[keep] == "="] = a[ops$a[keep & ops$op == "="]]
  out[ops$op[keep] == "+"] = b[ops$b[keep & ops$op == "+"]]
  out
}

test_that("diff_lines() renders unified hunks without file headers (GNU conventions)", {
  expect_identical(diff_lines(c("a", "b", "c"), c("a", "x", "c")),
                   c("@@ -1,3 +1,3 @@", " a", "-b", "+x", " c"))
  expect_identical(diff_lines(c("a", "b"), c("a", "b")), character())
  expect_identical(diff_lines(character(), c("x", "y")), c("@@ -0,0 +1,2 @@", "+x", "+y"))
  expect_identical(diff_lines(c("x", "y"), character()), c("@@ -1,2 +0,0 @@", "-x", "-y"))
  expect_identical(diff_lines("a", "b"), c("@@ -1 +1 @@", "-a", "+b"))
  a = sprintf("l%02d", 1:40)
  b = a
  b[5] = "five"
  b = b[-30]
  expect_identical(diff_lines(a, b), c(
    "@@ -2,7 +2,7 @@", " l02", " l03", " l04", "-l05", "+five", " l06", " l07", " l08",
    "@@ -27,7 +27,6 @@", " l27", " l28", " l29", "-l30", " l31", " l32", " l33"
  ))
  expect_identical(diff_lines(a[1:10], c(a[1:5], "new", a[6:10]), context = 0L),
                   c("@@ -5,0 +6 @@", "+new"))
})

test_that("edit scripts are valid on generated inputs", {
  alphabet = c("a", "b", "c", "d", "e")
  for (i in 1:200) {
    n = (i * 7L) %% 30L
    a = alphabet[(seq_len(n) * (i %% 5L + 1L)) %% 5L + 1L]
    b = a
    if (length(b)) b[((i * 3L) %% length(b)) + 1L] = "z"
    if (i %% 3L == 0L) b = c("q", b)
    if (i %% 4L == 0L && length(b) > 2L) b = b[-2L]
    ops = diff_ops(a, b)
    expect_identical(apply_ops(a, b, ops), b)
    expect_identical(a[ops$a[ops$op != "+"]], a)
  }
})

test_that("a total rewrite stays fast and valid under the D = 256 cap", {
  a = sprintf("old line %d", 1:2000)
  b = sprintf("new line %d", 1:2000)
  t0 = proc.time()[["elapsed"]]
  ops = diff_ops(a, b)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_identical(apply_ops(a, b, ops), b)
  expect_identical(sum(ops$op == "-"), 2000L)
})

test_that("diff_lines() cuts to max_tokens with a notice", {
  a = sprintf("line %03d with some words in it", 1:300)
  b = sprintf("LINE %03d with some words in it", 1:300)
  d = diff_lines(a, b, max_tokens = 100)
  expect_match(d[length(d)], "^\\[diff truncated: [0-9]+ more lines\\]$")
  expect_lte(est_tokens(d, "code"), 100)
  expect_gt(length(diff_lines(a, b, max_tokens = Inf)), 600)
  expect_error(diff_lines(a, b, max_tokens = 0), class = "gptr_error_invalid_argument")
})

test_that("diff_unified() adds headers and marks a missing final newline", {
  expect_identical(diff_unified("f.txt", "a\nb", "a\nc\n"), c(
    "--- a/f.txt", "+++ b/f.txt", "@@ -1,2 +1,2 @@", " a", "-b", "\\ No newline at end of file",
    "+c"
  ))
  expect_identical(diff_unified("f.txt", "same\n", "same\n"), character())
  expect_identical(diff_unified("f.txt", "x\n", "x"), c(
    "--- a/f.txt", "+++ b/f.txt", "@@ -1 +1 @@", "-x", "+x", "\\ No newline at end of file"
  ))
})

test_that("unified diffs apply cleanly with git apply", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  td = withr::local_tempdir()
  old = paste0(paste(sprintf("line %d", 1:30), collapse = "\n"), "\n")
  new_lines = sprintf("line %d", 1:30)
  new_lines[c(3, 17)] = c("THREE", "SEVENTEEN")
  new = paste(c("first", new_lines[-25]), collapse = "\n")
  writeBin(charToRaw(old), file.path(td, "f.txt"))
  writeLines(diff_unified("f.txt", old, new), file.path(td, "p.diff"))
  status = system2("git", c("-C", shQuote(td), "apply", "p.diff"), stdout = FALSE, stderr = FALSE)
  expect_identical(status, 0L)
  expect_identical(rawToChar(readBin(file.path(td, "f.txt"), "raw", 1e5)), new)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-diff")'
```

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "diff_lines"` (or `"diff_ops"`, `"diff_unified"`).

- [ ] **Step 3: Write the implementation**

Create `R/tool-diff.R`:

```r
# tool-diff.R -- line diff in pure base R (P10): common prefix/suffix trim, patience anchors (lines
# unique in both ranges, longest increasing subsequence), Myers O(ND) on the remaining gaps with the
# cost capped at D = 256 (a gap beyond the cap is reported as replaced, still a valid edit script),
# and unified-diff rendering with GNU conventions. Ported from dev/research/11-r-file-tools.md
# section 5.5 (proto/30-diff.R; 150 random property tests and git-apply checks in its verification
# log, row 32) with the cap of dev/research/21-rcpp-hot-paths.md section 2.3 (no diffobj, no
# compiled code; contract section 7.10).

diff_max_d = 256L

#' Indices of a longest strictly increasing subsequence of `x` (patience sort with findInterval())
#' @noRd
diff_lis = function(x) {
  n = length(x)
  if (n <= 1L || !is.unsorted(x, strictly = TRUE)) return(seq_len(n))
  tails_val = numeric(0)
  tails_idx = integer(0)
  prev = integer(n)
  for (i in seq_len(n)) {
    k = findInterval(x[i], tails_val, left.open = TRUE)
    prev[i] = if (k > 0L) tails_idx[k] else 0L
    tails_val[k + 1L] = x[i]
    tails_idx[k + 1L] = i
  }
  out = integer(length(tails_idx))
  j = tails_idx[length(tails_idx)]
  for (p in rev(seq_along(out))) {
    out[p] = j
    j = prev[j]
  }
  out
}

#' Length of the common run a[x + 1 ..], b[y + 1 ..]: eight scalar steps, then doubling vector
#' blocks
#' @noRd
diff_snake = function(a, b, x, y) {
  len_max = min(length(a) - x, length(b) - y)
  k = 0L
  while (k < len_max && k < 8L) {
    if (a[x + k + 1L] != b[y + k + 1L]) return(k)
    k = k + 1L
  }
  blk = 64L
  while (k < len_max) {
    len = min(blk, len_max - k)
    i = seq_len(len)
    neq = which(a[x + k + i] != b[y + k + i])
    if (length(neq)) return(k + neq[1L] - 1L)
    k = k + len
    blk = blk * 2L
  }
  len_max
}

#' Myers greedy forward pass over integer-coded lines; matched pairs `list(a, b)`, or NULL when the
#' edit distance exceeds `max_d`
#' @noRd
diff_myers = function(a, b, max_d = diff_max_d) {
  n = length(a)
  m = length(b)
  off = n + m + 2L
  v = integer(2L * off + 1L)
  trace = list()
  dmax = min(n + m, max_d)
  for (d in 0:dmax) {
    trace[[d + 1L]] = v
    for (k in seq.int(-d, d, by = 2L)) {
      down = k == -d || (k != d && v[off + k - 1L] < v[off + k + 1L])
      x = if (down) v[off + k + 1L] else v[off + k - 1L] + 1L
      y = x - k
      if (x < n && y < m && a[x + 1L] == b[y + 1L]) {
        s = diff_snake(a, b, x, y)
        x = x + s
        y = y + s
      }
      v[off + k] = x
      if (x >= n && y >= m) return(diff_myers_back(trace, d, n, m, off))
    }
  }
  NULL
}

#' Backtrack a finished Myers pass into matched index pairs (snakes recorded as ranges: linear time)
#' @noRd
diff_myers_back = function(trace, d, n, m, off) {
  ra = integer(0)
  rb = integer(0)
  rl = integer(0)
  x = n
  y = m
  for (dd in seq.int(d, 1L, by = -1L)[seq_len(d)]) {
    vv = trace[[dd + 1L]]
    kk = x - y
    down = kk == -dd || (kk != dd && vv[off + kk - 1L] < vv[off + kk + 1L])
    pk = if (down) kk + 1L else kk - 1L
    px = vv[off + pk]
    py = px - pk
    len = min(x - px, y - py)
    if (len > 0L) {
      ra = c(ra, x - len + 1L)
      rb = c(rb, y - len + 1L)
      rl = c(rl, len)
    }
    x = px
    y = py
  }
  if (x > 0L && y > 0L) {
    len = min(x, y)
    ra = c(ra, x - len + 1L)
    rb = c(rb, y - len + 1L)
    rl = c(rl, len)
  }
  if (!length(rl)) return(list(a = integer(0), b = integer(0)))
  o = order(ra)
  idx = sequence(rl[o]) - 1L
  list(a = rep(ra[o], rl[o]) + idx, b = rep(rb[o], rl[o]) + idx)
}

#' Match vector: element i is the index of `b` matched to `a[i]` (0 = deleted); matches increase
#' @noRd
diff_match = function(a, b, max_d = diff_max_d) {
  u = unique(c(a, b))
  ta = match(a, u)
  tb = match(b, u)
  m = integer(length(a))
  stack = list(c(1L, length(a), 1L, length(b)))
  while (length(stack)) {
    r = stack[[length(stack)]]
    stack[[length(stack)]] = NULL
    a0 = r[1L]
    a1 = r[2L]
    b0 = r[3L]
    b1 = r[4L]
    if (a0 > a1 || b0 > b1) next
    k = min(a1 - a0, b1 - b0) + 1L
    neq = which(ta[a0:(a0 + k - 1L)] != tb[b0:(b0 + k - 1L)])
    p = if (length(neq)) neq[1L] - 1L else k
    if (p > 0L) {
      m[a0:(a0 + p - 1L)] = b0:(b0 + p - 1L)
      a0 = a0 + p
      b0 = b0 + p
    }
    if (a0 > a1 || b0 > b1) next
    k = min(a1 - a0, b1 - b0) + 1L
    neq = which(ta[a1:(a1 - k + 1L)] != tb[b1:(b1 - k + 1L)])
    s = if (length(neq)) neq[1L] - 1L else k
    if (s > 0L) {
      m[(a1 - s + 1L):a1] = (b1 - s + 1L):b1
      a1 = a1 - s
      b1 = b1 - s
    }
    if (a0 > a1 || b0 > b1) next
    ra = ta[a0:a1]
    rb = tb[b0:b1]
    ua = !duplicated(ra) & !duplicated(ra, fromLast = TRUE)
    ub = !duplicated(rb) & !duplicated(rb, fromLast = TRUE)
    pa = which(ua)
    pb = match(ra[pa], rb)
    ok = !is.na(pb)
    pa = pa[ok]
    pb = pb[ok]
    ok = ub[pb]
    pa = pa[ok]
    pb = pb[ok]
    if (length(pa)) {
      keep = diff_lis(pb)
      pa = pa[keep] + a0 - 1L
      pb = pb[keep] + b0 - 1L
      m[pa] = pb
      lo_a = c(a0, pa + 1L)
      hi_a = c(pa - 1L, a1)
      lo_b = c(b0, pb + 1L)
      hi_b = c(pb - 1L, b1)
      for (i in seq_along(lo_a)) {
        if (lo_a[i] <= hi_a[i] && lo_b[i] <= hi_b[i]) {
          stack[[length(stack) + 1L]] = c(lo_a[i], hi_a[i], lo_b[i], hi_b[i])
        }
      }
      next
    }
    my = diff_myers(ra, rb, max_d)
    if (!is.null(my) && length(my$a)) m[my$a + a0 - 1L] = my$b + b0 - 1L
  }
  m
}

#' Edit script `data.frame(op = "=" | "-" | "+", a = line of a or NA, b = line of b or NA)` in file
#' order
#' @noRd
diff_ops = function(a, b, max_d = diff_max_d) {
  m = diff_match(a, b, max_d)
  matched_a = m > 0L
  mb = logical(length(b))
  mb[m[matched_a]] = TRUE
  ca = cumsum(matched_a)
  cb = cumsum(mb)
  del = which(!matched_a)
  ins = which(!mb)
  eq = which(matched_a)
  op = c(rep("-", length(del)), rep("+", length(ins)), rep("=", length(eq)))
  ia = c(del, rep(NA_integer_, length(ins)), eq)
  ib = c(rep(NA_integer_, length(del)), ins, m[eq])
  grp = c(ca[del] + 1L, cb[ins] + 1L, ca[eq])
  typ = c(rep(1L, length(del)), rep(2L, length(ins)), rep(3L, length(eq)))
  o = order(grp, typ, c(del, ins, eq), method = "radix")
  data.frame(op = op[o], a = ia[o], b = ib[o], stringsAsFactors = FALSE)
}

#' Unified hunks (`@@ -a,b +c,d @@` and " ", "-", "+" lines) of an edit script
#' @noRd
diff_hunks = function(a, b, ops, context = 3L, a_final_nl = TRUE, b_final_nl = TRUE) {
  ch = which(ops$op != "=")
  if (!length(ch)) return(character())
  brk = c(TRUE, diff(ch) > 2L * context + 1L)
  starts = ch[brk]
  ends = ch[c(brk[-1L], TRUE)]
  rng = function(s, n) if (n == 1L) sprintf("%d", s) else sprintf("%d,%d", s, n)
  before = function(idx, lo) {
    p = idx[seq_len(lo - 1L)]
    p = p[!is.na(p)]
    if (length(p)) max(p) else 0L
  }
  out = character()
  for (h in seq_along(starts)) {
    lo = max(1L, starts[h] - context)
    hi = min(nrow(ops), ends[h] + context)
    o = ops[lo:hi, , drop = FALSE]
    a_lines = o$a[!is.na(o$a)]
    b_lines = o$b[!is.na(o$b)]
    a_start = if (length(a_lines)) min(a_lines) else before(ops$a, lo)
    b_start = if (length(b_lines)) min(b_lines) else before(ops$b, lo)
    header = sprintf("@@ -%s +%s @@", rng(a_start, length(a_lines)), rng(b_start, length(b_lines)))
    out = c(out, header)
    body = ifelse(o$op == "=", paste0(" ", a[pmax(1L, o$a)]),
                  ifelse(o$op == "-", paste0("-", a[pmax(1L, o$a)]), paste0("+", b[pmax(1L, o$b)])))
    nonl = (!a_final_nl & !is.na(o$a) & o$a == length(a) & o$op != "+") |
      (!b_final_nl & !is.na(o$b) & o$b == length(b) & o$op != "-")
    body = as.vector(rbind(body, ifelse(nonl, "\\ No newline at end of file", NA_character_)))
    out = c(out, body[!is.na(body)])
  }
  utf8_mark(out)
}

#' Cut diff lines to a token budget, ending with a notice
#' @noRd
diff_budget = function(lines, max_tokens) {
  if (!length(lines) || est_tokens(lines, "code") <= max_tokens) return(lines)
  lo = 0L
  hi = length(lines)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (est_tokens(lines[seq_len(mid)], "code") + 12 <= max_tokens) lo = mid else hi = mid - 1L
  }
  c(lines[seq_len(lo)], paste0("[diff truncated: ", length(lines) - lo, " more lines]"))
}

#' Unified diff of two line vectors (contract section 7.10)
#'
#' @param old,new Character vectors of lines (no line terminators).
#' @param context Lines of context around each change.
#' @param max_tokens Estimated-token cap of the result (`Inf`: no cap).
#' @return Character vector of hunk lines without file headers, or `character()` when equal.
#' @noRd
diff_lines = function(old, new, context = 3L, max_tokens = 400L) {
  check_strings(old, "old")
  check_strings(new, "new")
  context = check_number(context, "context", min = 0, int = TRUE)
  check_number(max_tokens, "max_tokens", min = 1)
  old = as_utf8(old)
  new = as_utf8(new)
  out = diff_hunks(old, new, diff_ops(old, new), context = context)
  if (is.finite(max_tokens)) out = diff_budget(out, max_tokens)
  out
}

#' Lines of a text and whether it ends with a newline ("a\nb\n" -> c("a", "b"), TRUE)
#' @noRd
diff_split = function(x) {
  x = as_utf8(x)
  if (!nzchar(x)) return(list(lines = character(), final_nl = TRUE))
  l = utf8_mark(strsplit(paste0(x, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
  nl = l[length(l)] == ""
  if (nl) l = l[-length(l)]
  list(lines = l, final_nl = nl)
}

#' Full unified diff of two texts: `--- a/<path>`, `+++ b/<path>`, hunks and "\ No newline" markers
#'
#' A change of only the final newline is detected: each side's last line is keyed with a sentinel
#' when it lacks the newline.
#' @noRd
diff_unified = function(path, old, new, context = 3L) {
  a = diff_split(old)
  b = diff_split(new)
  ka = a$lines
  kb = b$lines
  if (!a$final_nl && length(ka)) ka[length(ka)] = paste0(ka[length(ka)], "\001<no-eol>")
  if (!b$final_nl && length(kb)) kb[length(kb)] = paste0(kb[length(kb)], "\001<no-eol>")
  hunks = diff_hunks(a$lines, b$lines, diff_ops(ka, kb), context = context,
                     a_final_nl = a$final_nl, b_final_nl = b$final_nl)
  if (!length(hunks)) return(character())
  c(paste0("--- a/", path), paste0("+++ b/", path), hunks)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-diff")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 419 ]` with git on `PATH` (the `git apply` test skips on CRAN and without git, leaving `PASS 417`).

- [ ] **Step 5: Commit**

```bash
git add R/tool-diff.R tests/testthat/test-tool-diff.R
git commit -m "feat(tools): add the unified diff engine"
```

### Task 4: The `read` engine and `gptr_lines`

**Files:** Create: `R/tool-read.R`; Test: `tests/testthat/test-tool-read.R`; Modify: `NAMESPACE` (generated).

`read_file()` is the engine of the direct `read` tool and `read_lines_value()` the value of `peter$read()` (both wired in Task 10). Ported from report 11 §5.5 (`proto/00-core.R`, `proto/10-read.R`) and report 21 §2.2 (a `grepRaw()` newline index over raw bytes, decoding only the requested window; a streaming chunked index above 16 MiB; a sparse index of every 10,000th line cached per process for files above 20 MB, keyed by path, size and mtime, at most 8 entries of numbers), with Pi's texts from report 01 §2.3 and §3.2 (`[Showing lines a-b of n. Use offset=k to continue.]`, `[n more lines in file. Use offset=k to continue.]`, `Offset n is beyond end of file (m lines total)`, `ENOENT`/`EISDIR`/`EACCES` messages, `Read image file [mime]`). Deviations from Pi are report 11 §3.3's documented ones: no line numbers (03 §7.2: "cat -n costs +19-26%"), the CR of CRLF is not shown, empty and binary files get notices (binary with a loading hint, never deserialised: CVE-2024-27322), a first line above 50 KB is shown in part with a notice, and decoding notices name the source encoding. Verification-log fixes applied (report 11): base64 without jsonlite's 72-character line breaks (row 15), `iconv(sub =)` only on an unmarked byte string (row 9), never `iconv(sub = "Unicode")` (row 8). Images are recognised by magic bytes only (JPEG, PNG without `acTL`, GIF, WebP, BMP; JPEG-LS rejected), sent unchanged when native and within 2,000 px and 4.5 MB of base64 (Pi `image-resize-core.ts`), else converted with magick (Suggests) or omitted with a note. `skill:<name>/<path>` resolves inside the directory P17's `skill.body` service returns (IC-68); without P17 it signals `gptr_error_not_available`. macOS screenshot names are found through Pi's fallbacks (U+202F before AM/PM, NFD, U+2019).

**Interfaces:**
- Consumes (P01, 04 §7.1): `as_utf8()`, `utf8_mark()`, `est_tokens()`, `path_key()`, `block_image(data, mime, source, width, height)`, `gptr_opt("read_max_tokens")`, `ext_service_has()`, `ext_service_get("skill.body")` (P17, 04 §7.0: `function(name) list(text, dir)`), the checkers, `gptr_abort()`; Task 1: `lines_fit()`, `budget_head()`, `member_budget()`, `ns_print_lines()`; Task 2: `fs_path()`, `tool_path_norm()`, `tool_path_is_abs()`, `resolve_tool_path()`.
- Produces (04 §7.10, §5.10): `read_file(path, offset = NULL, limit = NULL, budget_tokens = gptr_opt("read_max_tokens"))` -> `list(text = chr(1), image = <image block> | NULL, details = list(path, offset, limit, lines_total, truncated, image, encoding, eol))`; `read_lines_value(path, offset = NULL, limit = NULL)` -> `gptr_lines` (attributes `path`, `offset`, `limit`, `total`, `truncated`, `encoding`, `notices`, `image_block`) with `print.gptr_lines()`; internal helpers for Tasks 5-7 and 10: `read_raw(path, n = NULL, offset = 0)`, `sniff_bom(b)`, `is_binary_raw(b)`, `decode_raw(b)` -> `list(text, encoding, bom, lossy)`, `encode_text(text, encoding = "UTF-8", bom = FALSE)` -> raw, `split_lines_js(x)`, `split_lines_count(x)`, `detect_eol(x)`, `normalize_lf(x)`, `truncate_lines_head(lines)`, `format_size(bytes)`, `image_dims(b, mime)`, `base64_raw(b)`, `read_token_class(path)`, constants `tool_max_lines` (2000L), `tool_max_bytes` (51200L), `bom_bytes`, `replacement_sub`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-read.R` (Pi's read oracle cases of report 01 §5.9 `test-01.R` "read", with report 11 §3.3's documented deviations):

```r
# Tests for R/tool-read.R: Pi's read oracle cases of dev/research/01-pi-builtin-tools.md section 5.9
# (test-01.R "read") with the documented deviations of dev/research/11-r-file-tools.md section 3.3
# (CR of CRLF stripped, empty/binary/decoding notices, a long first line shown in part), images by
# magic bytes, encodings, the token cap, the big-file index and skill pseudo-paths.

put = function(dir, name, text) {
  p = fs_path(file.path(dir, name))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.raw(text)) text else charToRaw(text), p)
  p
}

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

png1 = jsonlite::base64_dec(paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
  "BAEAX+XDSwAAAABJRU5ErkJggg=="
))

test_that("read returns a small file verbatim, without line numbers", {
  td = withr::local_tempdir()
  f = put(td, "test.txt", "Hello, world!\nLine 2\nLine 3")
  r = read_file(f)
  expect_identical(r$text, "Hello, world!\nLine 2\nLine 3")
  expect_null(r$image)
  expect_identical(r$details$lines_total, 3L)
  expect_false(r$details$truncated)
  expect_identical(r$details$eol, "\n")
  expect_error(read_file(file.path(td, "nonexistent.txt")), "ENOENT",
               class = "gptr_error_invalid_argument")
  expect_error(read_file(td), "EISDIR", class = "gptr_error_invalid_argument")
})

test_that("read truncates at 2000 lines and 50 KB with Pi's notices", {
  td = withr::local_tempdir()
  r = read_file(put(td, "large.txt", paste(sprintf("Line %d", 1:2500), collapse = "\n")))
  expect_match(r$text, "[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]", fixed = TRUE)
  expect_false(grepl("Line 2001", r$text, fixed = TRUE))
  expect_true(r$details$truncated)
  wide = paste(sprintf("Line %d: %s", 1:500, strrep("x", 200)), collapse = "\n")
  r = read_file(put(td, "large-bytes.txt", wide), budget_tokens = 1e6)
  expect_match(r$text, paste0("\\[Showing lines 1-\\d+ of 500 \\(50\\.0KB limit\\)\\. ",
                              "Use offset=\\d+ to continue\\.\\]"))
})

test_that("offset and limit follow Pi (1-indexed; remaining-lines notice)", {
  td = withr::local_tempdir()
  f = put(td, "hundred.txt", paste(sprintf("Line %d", 1:100), collapse = "\n"))
  o = read_file(f, offset = 51)$text
  expect_true(startsWith(o, "Line 51") && endsWith(o, "Line 100"))
  expect_false(grepl("Use offset=", o, fixed = TRUE))
  expect_match(read_file(f, limit = 10)$text,
               "Line 10\n\n[90 more lines in file. Use offset=11 to continue.]", fixed = TRUE)
  o = read_file(f, offset = 41, limit = 20)$text
  expect_true(startsWith(o, "Line 41"))
  expect_match(o, "Line 60\n\n[40 more lines in file. Use offset=61 to continue.]", fixed = TRUE)
  expect_identical(read_file(f, offset = 0, limit = 1)$text,
                   "Line 1\n\n[99 more lines in file. Use offset=2 to continue.]")
  f = put(td, "short.txt", "Line 1\nLine 2\nLine 3")
  expect_error(read_file(f, offset = 100), "Offset 100 is beyond end of file (3 lines total)",
               fixed = TRUE)
})

test_that("images are recognised by magic bytes, not by extension", {
  td = withr::local_tempdir()
  r = read_file(put(td, "image.txt", png1))
  expect_identical(r$text, "Read image file [image/png]")
  expect_identical(r$image$type, "image")
  expect_identical(r$image$mime, "image/png")
  expect_identical(jsonlite::base64_dec(r$image$data), png1)
  expect_false(grepl("\n", r$image$data, fixed = TRUE))
  expect_identical(image_dims(png1, "image/png"), c(1, 1))
  expect_true(r$details$image)
  r = read_file(put(td, "not-an-image.png", "definitely not a png"))
  expect_identical(r$text, "definitely not a png")
  expect_null(r$image)
})

test_that("a BMP is converted with magick or omitted with a note", {
  td = withr::local_tempdir()
  bmp = raw(58)
  bmp[1:2] = charToRaw("BM")
  bmp[c(3, 11, 15, 19, 23, 27, 29, 35, 57)] = as.raw(c(58, 54, 40, 1, 1, 1, 24, 4, 0xff))
  expect_identical(detect_image_mime(bmp), "image/bmp")
  r = read_file(put(td, "image.bmp", bmp))
  if (requireNamespace("magick", quietly = TRUE)) {
    expect_match(r$text, "Read image file [image/png]", fixed = TRUE)
    expect_match(r$text, "[Image converted from image/bmp to image/png.]", fixed = TRUE)
    expect_identical(jsonlite::base64_dec(r$image$data)[1], as.raw(0x89))
  } else {
    expect_match(r$text, "Image omitted", fixed = TRUE)
  }
})

test_that("binary files get a notice with a loading hint and are never deserialised", {
  td = withr::local_tempdir()
  p = file.path(td, "obj.rds")
  saveRDS(mtcars, p, compress = FALSE)
  expect_match(read_file(p)$text, paste0("^\\[Binary file: .*obj\\.rds \\([0-9.]+KB\\)\\. ",
                                         "Not shown as text\\. .*readRDS\\(\\)\\.\\]$"))
  expect_identical(read_file(put(td, "empty.txt", raw()))$text,
                   paste0("[File is empty: ", file.path(td, "empty.txt"), "]"))
})

test_that("CP1252, UTF-16 and BOM files are decoded; the CR of CRLF is not shown", {
  td = withr::local_tempdir()
  o = read_file(put(td, "latin1.txt", as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x0a))))$text
  expect_true(startsWith(o, "caf\u00e9\n"))
  expect_match(o, "[Decoded from CP1252]", fixed = TRUE)
  u16 = c(as.raw(c(0xff, 0xfe)), iconv("h\u00e9llo\n", "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]])
  r = read_file(put(td, "utf16.txt", u16))
  expect_identical(charToRaw(sub("\n\n\\[Decoded from UTF-16LE\\]$", "", r$text)),
                   charToRaw("h\u00e9llo\n"))
  expect_identical(r$details$encoding, "UTF-16LE")
  r = read_file(put(td, "bom.txt", c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("a\r\nb\r\n"))))
  expect_identical(r$text, "a\nb\n")
  expect_identical(r$details$eol, "\r\n")
  o = read_file(put(td, "stray.txt", c(charToRaw("caf\u00e9 ok "), as.raw(0xff),
                                       charToRaw(" end\n"))))$text
  expect_match(o, "[File is not valid UTF-8; invalid bytes shown as U+FFFD]", fixed = TRUE)
  expect_true(validUTF8(o))
})

test_that("the token cap and a giant first line are reported, never a partial line", {
  td = withr::local_tempdir()
  f = put(td, "prose.txt", paste(rep("a sentence of ordinary prose words", 400), collapse = "\n"))
  r = read_file(f, budget_tokens = 100)
  expect_match(r$text, paste0("\\[Showing lines 1-[0-9]+ of 400 \\(100 token limit\\)\\. ",
                              "Use offset=[0-9]+ to continue\\.\\]"))
  expect_lte(est_tokens(sub("\n\n\\[Showing.*$", "", r$text), "prose"), 100)
  f = put(td, "wide.txt", paste0(strrep("y", 60000), "\nsecond\n"))
  o = read_file(f, budget_tokens = 1e6)$text
  expect_match(o, "[Line 1 is 58.6KB, exceeds the 50.0KB limit; showing its first 50.0KB.",
               fixed = TRUE)
  expect_identical(nchar(strsplit(o, "\n")[[1]][1]), 51200L)
  mb = put(td, "euro.txt", strrep("\u20ac", 20000))
  first = strsplit(read_file(mb, budget_tokens = 1e6)$text, "\n")[[1]][1]
  expect_true(validUTF8(first))
  expect_identical(nchar(first, "bytes") %% 3L, 0L)
})

test_that("the streaming index gives the same windows as the in-memory reader", {
  td = withr::local_tempdir()
  f = put(td, "idx.txt", paste0(paste(sprintf("row %d caf\u00e9", 1:1000), collapse = "\n"), "\n"))
  small = read_text_window(f, 1L, NULL)
  expect_identical(small$total, 1001L)
  for (off in c(1L, 7L, 8L, 500L, 995L, 1001L)) {
    big = read_text_window(f, off, 10L, big = 10, every = 7L)
    expect_identical(big$lines, utils::head(small$lines[off:1001], 10))
    expect_identical(big$total, 1001L)
  }
  idx = read_line_index(f, size = 3e7, every = 7L)
  expect_identical(read_line_index(f, size = 3e7, every = 7L), idx)
  expect_identical(idx$total, 1001L)
})

test_that("skill:<name>/<path> resolves inside the skill directory only (IC-68)", {
  td = withr::local_tempdir()
  put(td, "sk/references/a.md", "reference text")
  put(td, "sk/SKILL.md", "---\nname: demo\n---\nbody")
  local_service("skill.body", function(name) {
    if (identical(name, "demo")) list(text = "", dir = file.path(td, "sk"))
  })
  expect_identical(read_file("skill:demo/references/a.md")$text, "reference text")
  expect_match(read_file("skill:demo/SKILL.md")$text, "^---\nname: demo")
  expect_error(read_file("skill:demo/../../etc/passwd"), "must stay inside the skill directory")
  expect_error(read_file("skill:nope/SKILL.md"), "Unknown skill: nope")
})

test_that("macOS screenshot names are found through Pi's fallbacks", {
  td = withr::local_tempdir()
  real = put(td, "Screenshot 2024-01-01 at 10.00.00\u202fAM.png", "x")
  expect_identical(read_resolve(file.path(td, "Screenshot 2024-01-01 at 10.00.00 AM.png")),
                   tool_path_norm(real))
  real = put(td, "Capture d\u2019cran.txt", "x")
  expect_identical(read_resolve(file.path(td, "Capture d'cran.txt")), tool_path_norm(real))
})

test_that("peter$read() gives gptr_lines with the contract attributes and prints within budget", {
  td = withr::local_tempdir()
  f = put(td, "hundred.txt", paste(sprintf("Line %d", 1:100), collapse = "\n"))
  v = read_lines_value(f, offset = 11, limit = 5)
  expect_s3_class(v, "gptr_lines")
  expect_identical(as.character(v), sprintf("Line %d", 11:15))
  expect_identical(attr(v, "path"), resolve_tool_path(f))
  expect_identical(attr(v, "offset"), 11L)
  expect_identical(attr(v, "limit"), 5L)
  expect_identical(attr(v, "total"), 100L)
  expect_false(attr(v, "truncated"))
  expect_identical(attr(v, "encoding"), "UTF-8")
  out = utils::capture.output(print(v))
  expect_identical(out, c(sprintf("Line %d", 11:15), "",
                          "[85 more lines in file. Use offset=16 to continue.]"))
  local_gptr_options(helper_output_tokens = 30L)
  out = utils::capture.output(print(read_lines_value(f)))
  expect_match(out[length(out)], "^\\[\\.\\.\\. [0-9]+ more lines not printed")
  img = read_lines_value(put(td, "i.png", png1))
  expect_identical(as.character(img), "Read image file [image/png]")
  expect_identical(attr(img, "image_block")$mime, "image/png")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-read")'
```

Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "read_file"` (or `"detect_image_mime"`, `"read_text_window"`, `"read_resolve"`, `"read_lines_value"`).

- [ ] **Step 3: Write the implementation**

Create `R/tool-read.R`:

```r
# tool-read.R -- the `read` tool and `peter$read()` (P10): Pi's read semantics without line numbers,
# images by magic bytes, BOM/UTF-16/UTF-32/CP1252 decoding, line windows over a raw newline index
# (files up to 16 MiB), a streaming chunked index above that and a cached sparse index above 20 MB,
# the 2,000-line / 50 KB / gptr.read_max_tokens caps, and `skill:<name>/<path>` pseudo-paths
# (IC-68). Ported from dev/research/11-r-file-tools.md section 5.5 (proto/00-core.R,
# proto/10-read.R) and dev/research/21-rcpp-hot-paths.md section 2.2 (grepRaw newline index, sparse
# index); Pi's texts from dev/research/01-pi-builtin-tools.md sections 2.3 and 3.2. Verification-log
# fixes applied (report 11): base64 without jsonlite's 72-character line breaks (row 15), iconv(sub
# =) only with an unmarked byte string (row 9), never iconv(sub = "Unicode") (row 8), no
# deserialising previews of data files (a binary notice with a loading hint instead;
# CVE-2024-27322).

tool_max_lines = 2000L
tool_max_bytes = 51200L
read_big_file = 16 * 1024^2
read_index_min = 20 * 1024^2
read_index_every = 10000L
read_chunk = 4L * 1024L^2
read_sniff_bytes = 65536L
image_sniff_bytes = 4100L
image_max_edge = 2000L
image_max_b64 = 4.5 * 1024^2
binary_sniff = 8000L
replacement_sub = rawToChar(as.raw(c(0xEF, 0xBF, 0xBD)))
bom_len = c("UTF-8" = 3L, "UTF-16LE" = 2L, "UTF-16BE" = 2L, "UTF-32LE" = 4L, "UTF-32BE" = 4L)
bom_bytes = list("UTF-8" = as.raw(c(0xEF, 0xBB, 0xBF)), "UTF-16LE" = as.raw(c(0xFF, 0xFE)),
                 "UTF-16BE" = as.raw(c(0xFE, 0xFF)), "UTF-32LE" = as.raw(c(0xFF, 0xFE, 0, 0)),
                 "UTF-32BE" = as.raw(c(0, 0, 0xFE, 0xFF)))
binary_hints = c(rds = "readRDS()", rda = "load()", rdata = "load()", qs = "qs::qread()",
                 qs2 = "qs2::qs_read()", parquet = "arrow::read_parquet()",
                 feather = "arrow::read_feather()", xlsx = "readxl::read_excel()",
                 xls = "readxl::read_excel()", sav = "haven::read_sav()", dta = "haven::read_dta()",
                 fst = "fst::read_fst()", pdf = "pdftools::pdf_text()",
                 zip = "utils::unzip(list = TRUE)", gz = "readLines(gzfile())")

# Sparse line indexes of files above 20 MB keyed by path, size and mtime: numbers only, at most 8.
read_index_cache = new.env(parent = emptyenv())

#' Pi formatSize(): 512B, 50.0KB, 3.0MB
#' @noRd
format_size = function(bytes) {
  if (bytes < 1024) return(sprintf("%dB", as.integer(bytes)))
  if (bytes < 1024^2) return(sprintf("%.1fKB", bytes / 1024))
  sprintf("%.1fMB", bytes / 1024^2)
}

#' Raw bytes of a file: all, or `n` bytes from byte `offset`
#' @noRd
read_raw = function(path, n = NULL, offset = 0) {
  p = fs_path(path)
  size = file.size(p)
  if (is.na(size)) {
    gptr_abort(paste0("ENOENT: no such file or directory, access '", path, "'"), "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  con = file(p, "rb")
  on.exit(close(con), add = TRUE)
  if (offset > 0) seek(con, offset, rw = "read")
  readBin(con, "raw", n = if (is.null(n)) size - offset else n)
}

#' Byte-order mark of a raw vector ("" when there is none)
#' @noRd
sniff_bom = function(b) {
  n = length(b)
  starts = function(x) n >= length(x) && identical(b[seq_along(x)], x)
  if (starts(bom_bytes[["UTF-8"]])) return("UTF-8")
  if (starts(bom_bytes[["UTF-32LE"]])) return("UTF-32LE")
  if (starts(bom_bytes[["UTF-32BE"]])) return("UTF-32BE")
  if (starts(bom_bytes[["UTF-16LE"]])) return("UTF-16LE")
  if (starts(bom_bytes[["UTF-16BE"]])) return("UTF-16BE")
  ""
}

#' Binary heuristic (git): a NUL byte in the first 8000 bytes; UTF-16/32 text with a BOM is exempt
#' @noRd
is_binary_raw = function(b, sniff = binary_sniff) {
  bom = sniff_bom(b)
  if (nzchar(bom) && bom != "UTF-8") return(FALSE)
  n = min(length(b), sniff)
  n > 0L && any(b[seq_len(n)] == as.raw(0L))
}

#' Decode bytes to one UTF-8 string without BOM
#'
#' Order: BOM; valid UTF-8; CP1252 (then latin1) when invalid bytes dominate; else UTF-8 with U+FFFD
#' (`lossy`). Returns `list(text, encoding, bom, lossy)`.
#' @noRd
decode_raw = function(b, fallback = c("CP1252", "latin1")) {
  if (!length(b)) return(list(text = as_utf8(""), encoding = "UTF-8", bom = FALSE, lossy = FALSE))
  bom = sniff_bom(b)
  if (nzchar(bom)) {
    body = b[-seq_len(bom_len[[bom]])]
    if (bom != "UTF-8") {
      txt = iconv(list(body), from = bom, to = "UTF-8", sub = replacement_sub)
      return(list(text = as_utf8(txt), encoding = bom, bom = TRUE, lossy = FALSE))
    }
    b = body
  }
  if (any(b == as.raw(0L))) {
    gptr_abort("The file contains NUL bytes: it is binary.", "invalid_argument", arg = "path",
               expected = "a text file")
  }
  txt = rawToChar(b)
  if (validUTF8(txt)) {
    return(list(text = as_utf8(txt), encoding = "UTF-8", bom = nzchar(bom), lossy = FALSE))
  }
  n_hi = sum(b >= as.raw(0x80))
  n_bad = (nchar(iconv(txt, "UTF-8", "UTF-8", sub = "byte"), "bytes") - length(b)) / 3
  if (!nzchar(bom) && n_bad * 2 > (n_hi - n_bad)) {
    for (enc in fallback) {
      out = suppressWarnings(iconv(txt, from = enc, to = "UTF-8"))
      if (!is.na(out)) return(list(text = as_utf8(out), encoding = enc, bom = FALSE, lossy = FALSE))
    }
  }
  list(text = as_utf8(iconv(txt, "UTF-8", "UTF-8", sub = replacement_sub)), encoding = "UTF-8",
       bom = nzchar(bom), lossy = TRUE)
}

#' Encode UTF-8 text for writing; fails before any file is touched when a character is not
#' representable in the target encoding (report 11 section 2.3)
#' @noRd
encode_text = function(text, encoding = "UTF-8", bom = FALSE) {
  text = as_utf8(text)
  out = if (identical(encoding, "UTF-8")) {
    charToRaw(text)
  } else {
    r = iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1L]]
    if (is.null(r)) {
      gptr_abort(
        paste0("Text contains characters that cannot be represented in the file's encoding (",
               encoding, ")."),
        "invalid_argument", arg = "content", expected = "text representable in the file's encoding"
      )
    }
    r
  }
  if (isTRUE(bom) && encoding %in% names(bom_bytes)) out = c(bom_bytes[[encoding]], out)
  out
}

#' JavaScript "x".split("\n") semantics: "a\n" -> c("a", ""), "" -> "" (re-marked UTF-8, report 11
#' P1)
#' @noRd
split_lines_js = function(x) {
  out = strsplit(paste0(x, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  if (!length(out)) out = ""
  utf8_mark(out)
}

#' Pi splitLinesForCounting(): "" -> no lines; one trailing "\n" is not an extra line
#' @noRd
split_lines_count = function(x) {
  if (!nzchar(x)) return(character())
  utf8_mark(strsplit(x, "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
}

#' Pi detectLineEnding(): CRLF when the first line ending is CRLF, else LF
#' @noRd
detect_eol = function(x) {
  lf = regexpr("\n", x, fixed = TRUE, useBytes = TRUE)
  crlf = regexpr("\r\n", x, fixed = TRUE, useBytes = TRUE)
  if (lf < 0 || crlf < 0) return("\n")
  if (crlf < lf) "\r\n" else "\n"
}

#' CRLF and lone CR to LF
#' @noRd
normalize_lf = function(x) {
  x = gsub("\r\n", "\n", x, fixed = TRUE, useBytes = TRUE)
  utf8_mark(gsub("\r", "\n", x, fixed = TRUE, useBytes = TRUE))
}

#' Keep the first lines within a line and byte limit, never a partial line (Pi truncateHead)
#' @noRd
truncate_lines_head = function(lines, max_lines = tool_max_lines, max_bytes = tool_max_bytes) {
  n = length(lines)
  lb = as.numeric(nchar(lines, type = "bytes"))
  if (n <= max_lines && sum(lb) + max(0, n - 1) <= max_bytes) {
    return(list(lines = lines, truncated = FALSE, by = NA_character_, first_line_exceeds = FALSE))
  }
  if (n && lb[1L] > max_bytes) {
    return(list(lines = character(), truncated = TRUE, by = "bytes", first_line_exceeds = TRUE))
  }
  k = min(n, max_lines)
  cum = cumsum(lb[seq_len(k)] + c(0, rep(1, k - 1L)))
  fit = sum(cum <= max_bytes)
  list(lines = lines[seq_len(fit)], truncated = TRUE, by = if (fit < k) "bytes" else "lines",
       first_line_exceeds = FALSE)
}

#' Image type from magic bytes (never the extension; Pi mime.ts); NA when not an accepted image
#' (JPEG-LS and animated PNG are rejected)
#' @noRd
detect_image_mime = function(b) {
  u32be = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(3:0))
  ascii_at = function(o, s) {
    r = charToRaw(s)
    length(b) >= o + length(r) - 1L && identical(b[o:(o + length(r) - 1L)], r)
  }
  if (length(b) >= 3L && identical(b[1:3], as.raw(c(0xFF, 0xD8, 0xFF)))) {
    return(if (length(b) >= 4L && b[4] == as.raw(0xF7)) NA_character_ else "image/jpeg")
  }
  png_sig = as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
  if (length(b) >= 16L && identical(b[1:8], png_sig)) {
    if (u32be(9L) != 13 || !ascii_at(13L, "IHDR")) return(NA_character_)
    off = 9L
    while (off + 7L <= length(b)) {
      if (ascii_at(off + 4L, "acTL")) return(NA_character_)
      if (ascii_at(off + 4L, "IDAT")) break
      off = off + 12L + u32be(off)
    }
    return("image/png")
  }
  if (ascii_at(1L, "GIF87a") || ascii_at(1L, "GIF89a")) return("image/gif")
  if (ascii_at(1L, "RIFF") && ascii_at(9L, "WEBP")) return("image/webp")
  if (ascii_at(1L, "BM") && length(b) >= 26L) return("image/bmp")
  NA_character_
}

#' Width and height from the image header without decoding; NULL when unknown
#' @noRd
image_dims = function(b, mime) {
  u32be = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(3:0))
  u32le = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(0:3))
  u16le = function(o) as.integer(b[o]) + 256L * as.integer(b[o + 1L])
  u16be = function(o) 256L * as.integer(b[o]) + as.integer(b[o + 1L])
  jpeg_dims = function() {
    o = 3L
    n = length(b)
    while (o + 8L <= n) {
      if (b[o] != as.raw(0xFF)) {
        o = o + 1L
        next
      }
      m = as.integer(b[o + 1L])
      if (m %in% c(0xC0:0xC3, 0xC5:0xC7, 0xC9:0xCB, 0xCD:0xCF)) {
        return(c(u16be(o + 7L), u16be(o + 5L)))
      }
      if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
        o = o + 2L
        next
      }
      o = o + 2L + u16be(o + 2L)
    }
    NULL
  }
  webp_dims = function() {
    if (identical(b[13:16], charToRaw("VP8X"))) {
      return(c(1 + u16le(25L) + 65536 * as.integer(b[27]),
               1 + u16le(28L) + 65536 * as.integer(b[30])))
    }
    if (identical(b[13:16], charToRaw("VP8L"))) {
      v = u32le(22L)
      return(c(1 + v %% 16384, 1 + (v %/% 16384) %% 16384))
    }
    c(u16le(27L) %% 16384, u16le(29L) %% 16384)
  }
  bmp_height = function() abs(u32le(23L) - if (u32le(23L) > 2^31) 2^32 else 0)
  dims = function() {
    switch(mime,
           "image/png" = c(u32be(17L), u32be(21L)),
           "image/gif" = c(u16le(7L), u16le(9L)),
           "image/bmp" = c(u32le(19L), bmp_height()),
           "image/webp" = webp_dims(),
           "image/jpeg" = jpeg_dims(),
           NULL)
  }
  tryCatch(dims(), error = function(e) NULL)
}

#' base64 without line breaks (openssl when installed; jsonlite wraps every 72 characters)
#' @noRd
base64_raw = function(b) {
  if (requireNamespace("openssl", quietly = TRUE)) return(as.character(openssl::base64_encode(b)))
  gsub("[\r\n]", "", jsonlite::base64_enc(b))
}

#' Image bytes to an inline payload: unchanged when a provider-native format within 2000 px and 4.5
#' MB of base64 (Pi image-resize-core.ts), else converted and resized with magick (Suggests) or
#' omitted with a note. Returns `list(ok, data, mime, note, dims)`.
#' @noRd
process_image = function(b, mime) {
  dims = image_dims(b, mime)
  b64_size = ceiling(length(b) / 3) * 4
  native = mime %in% c("image/png", "image/jpeg", "image/gif", "image/webp")
  if (native && !is.null(dims) && all(dims <= image_max_edge) && b64_size < image_max_b64) {
    return(list(ok = TRUE, data = base64_raw(b), mime = mime, note = NULL, dims = dims))
  }
  if (!requireNamespace("magick", quietly = TRUE)) {
    shape = if (is.null(dims)) "" else sprintf(", %dx%d px", as.integer(dims[1]),
                                               as.integer(dims[2]))
    note = paste0("[Image omitted: ", mime, " is ", format_size(length(b)), shape,
                  "; install the 'magick' package to let gptr resize or convert it.]")
    return(list(ok = FALSE, note = note))
  }
  img = magick::image_read(b)[1]
  info = magick::image_info(img)
  if (info$width > image_max_edge || info$height > image_max_edge) {
    img = magick::image_resize(img, sprintf("%dx%d>", image_max_edge, image_max_edge))
  }
  best = NULL
  for (q in c(NA, 85, 70, 55, 40)) {
    cand = if (is.na(q)) {
      magick::image_write(img, format = "png")
    } else {
      magick::image_write(magick::image_flatten(img), format = "jpeg", quality = q)
    }
    if (is.null(best) || length(cand) < length(best$raw)) {
      best = list(raw = cand, mime = if (is.na(q)) "image/png" else "image/jpeg")
    }
    if (ceiling(length(best$raw) / 3) * 4 < image_max_b64) break
  }
  if (ceiling(length(best$raw) / 3) * 4 >= image_max_b64) {
    note = "[Image omitted: could not be resized below the inline image size limit.]"
    return(list(ok = FALSE, note = note))
  }
  ni = magick::image_info(img)
  notes = character()
  if (!identical(best$mime, mime)) {
    notes = paste0("[Image converted from ", mime, " to ", best$mime, ".]")
  }
  if (ni$width != info$width) {
    fmt = paste("[Image: original %dx%d, displayed at %dx%d.",
                "Multiply coordinates by %.2f to map to original image.]")
    notes = c(notes, sprintf(fmt, as.integer(info$width), as.integer(info$height),
                             as.integer(ni$width), as.integer(ni$height), info$width / ni$width))
  }
  list(ok = TRUE, data = base64_raw(best$raw), mime = best$mime,
       note = if (length(notes)) paste(notes, collapse = "\n") else NULL,
       dims = c(ni$width, ni$height))
}

#' `skill:<name>/<path>` to a file inside the skill's directory (the `skill.body` service of P17)
#' @noRd
skill_file_path = function(name, rel) {
  if (!ext_service_has("skill.body")) {
    gptr_abort(paste0("Skills are not available in this session (skill:", name, ")."),
               "not_available", member = "skill.body", provided_by = "P17")
  }
  sk = tryCatch(ext_service_get("skill.body")(name), error = function(e) NULL)
  if (!is.list(sk) || !is.character(sk$dir) || length(sk$dir) != 1L) {
    gptr_abort(paste0("Unknown skill: ", name), "invalid_argument", arg = "path",
               expected = "skill:<name>/<path> of a visible skill")
  }
  inner = tool_path_norm(rel)
  if (tool_path_is_abs(rel) || inner == ".." || startsWith(inner, "../")) {
    gptr_abort(paste0("A skill path must stay inside the skill directory: ", rel),
               "invalid_argument", arg = "path",
               expected = "a path relative to the skill directory")
  }
  tool_path_norm(file.path(sk$dir, inner))
}

#' Resolve a path for reading: skill pseudo-paths, then Pi's fallbacks for macOS screenshot names
#' (U+202F before AM/PM, NFD, U+2019) when the path does not exist
#' @noRd
read_resolve = function(path) {
  m = regmatches(path, regexec("^skill:([^/]+)/(.+)$", path))[[1L]]
  if (length(m)) return(skill_file_path(m[2L], m[3L]))
  res = resolve_tool_path(path)
  if (file.exists(fs_path(res))) return(res)
  nfd = if (requireNamespace("stringi", quietly = TRUE)) stringi::stri_trans_nfd(res) else res
  cand = c(gsub(" (AM|PM)\\.", "\u202f\\1.", res, ignore.case = TRUE, perl = TRUE),
           nfd, gsub("'", "\u2019", res, fixed = TRUE), gsub("'", "\u2019", nfd, fixed = TRUE))
  for (v in unique(as_utf8(cand))) {
    if (!identical(v, res) && file.exists(fs_path(v))) return(v)
  }
  res
}

#' Decode a window of text and split it (JS semantics, the CR of CRLF removed)
#' @noRd
read_decode_lines = function(txt, encoding, lossy) {
  txt = if (identical(encoding, "UTF-8")) {
    if (lossy || !validUTF8(txt)) iconv(txt, "UTF-8", "UTF-8", sub = replacement_sub) else txt
  } else {
    iconv(txt, encoding, "UTF-8")
  }
  lines = split_lines_js(txt)
  crlf = any(endsWith(lines[seq_len(min(length(lines), 1000L))], "\r"))
  list(lines = utf8_mark(sub("\r$", "", lines, perl = TRUE, useBytes = TRUE)),
       eol = if (crlf) "\r\n" else "\n")
}

#' Line window of a file up to 16 MiB: raw newline index, decode and split only the window
#' @noRd
read_window_small = function(abs, offset, n) {
  b = read_raw(abs)
  if (is_binary_raw(b)) return(list(binary = TRUE))
  bom = sniff_bom(b)
  if (nzchar(bom) && bom != "UTF-8") {
    d = decode_raw(b)
    lines = split_lines_js(d$text)
    total = length(lines)
    last = if (is.null(n)) total else min(total, offset + n - 1L)
    sel = if (offset > total) character() else lines[offset:last]
    crlf = any(endsWith(sel, "\r"))
    sel = utf8_mark(sub("\r$", "", sel, perl = TRUE, useBytes = TRUE))
    return(list(binary = FALSE, lines = sel, total = total, encoding = d$encoding, lossy = FALSE,
                eol = if (crlf) "\r\n" else "\n"))
  }
  if (bom == "UTF-8") b = b[-(1:3)]
  all_txt = tryCatch(rawToChar(b), error = function(e) NULL)
  if (is.null(all_txt)) return(list(binary = TRUE))
  d = if (validUTF8(all_txt)) list(encoding = "UTF-8", lossy = FALSE) else decode_raw(b)
  nl = grepRaw(as.raw(10L), b, fixed = TRUE, all = TRUE)
  total = length(nl) + 1L
  if (offset > total) {
    return(list(binary = FALSE, lines = character(), total = total, encoding = d$encoding,
                lossy = d$lossy, eol = "\n"))
  }
  last = if (is.null(n)) total else min(total, offset + n - 1L)
  s0 = if (offset == 1L) 1L else nl[offset - 1L] + 1L
  e0 = if (last <= length(nl)) nl[last] - 1L else length(b)
  wtxt = if (e0 >= s0) rawToChar(b[s0:e0]) else ""
  lines = read_decode_lines(wtxt, d$encoding, d$lossy)
  list(binary = FALSE, lines = lines$lines, total = total, encoding = d$encoding, lossy = d$lossy,
       eol = lines$eol)
}

#' Sparse line index: 0-based byte offsets of lines 1, every + 1, 2 * every + 1, ... and the total
#' line count (JS semantics), built in one streaming pass with grepRaw(all = TRUE) (report 21
#' section 2.2)
#' @noRd
read_line_index_build = function(abs, every = read_index_every, chunk = read_chunk) {
  con = file(fs_path(abs), "rb")
  on.exit(close(con), add = TRUE)
  offs = list(0)
  k = 1L
  line = 1
  base = 0
  repeat {
    r = readBin(con, "raw", chunk)
    if (!length(r)) break
    p = grepRaw(as.raw(10L), r, fixed = TRUE, all = TRUE)
    if (length(p)) {
      want = which(((line + seq_along(p) - 1) %% every) == 0)
      if (length(want)) {
        k = k + 1L
        offs[[k]] = base + p[want]
      }
      line = line + length(p)
    }
    base = base + length(r)
  }
  list(every = every, offsets = as.numeric(unlist(offs)), total = as.integer(line))
}

#' The sparse index of a file, cached per process for files above 20 MB (key: path, size, mtime)
#' @noRd
read_line_index = function(abs, size, every = read_index_every) {
  mtime = as.numeric(file.mtime(fs_path(abs)))
  key = paste(path_key(abs), size, mtime, every, sep = "|")
  hit = get0(key, envir = read_index_cache, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  idx = read_line_index_build(abs, every = every)
  if (size > read_index_min) {
    keys = ls(read_index_cache, all.names = TRUE)
    if (length(keys) >= 8L) rm(list = keys[seq_len(length(keys) - 7L)], envir = read_index_cache)
    assign(key, idx, envir = read_index_cache)
  }
  idx
}

#' Line window of a file above 16 MiB through the sparse index (bounded memory)
#' @noRd
read_window_big = function(abs, offset, n, size, every = read_index_every) {
  head = read_raw(abs, n = min(size, read_sniff_bytes))
  if (is_binary_raw(head)) return(list(binary = TRUE))
  bom = sniff_bom(head)
  if (nzchar(bom) && bom != "UTF-8") {
    gptr_abort(paste("UTF-16 and UTF-32 files larger than 16 MB are not supported by read;",
                     "load it in the r tool."),
               "invalid_argument", arg = "path", expected = "a UTF-8 or 8-bit text file")
  }
  d = decode_raw(head[seq_len(max(0L, length(head) - 4L))])
  idx = read_line_index(abs, size, every = every)
  if (offset > idx$total) {
    return(list(binary = FALSE, lines = character(), total = idx$total, encoding = d$encoding,
                lossy = d$lossy, eol = "\n"))
  }
  want = if (is.null(n)) idx$total - offset + 1L else min(n, idx$total - offset + 1L)
  k = (offset - 1L) %/% idx$every
  start_byte = idx$offsets[k + 1L]
  skip = offset - (k * idx$every + 1L)
  con = file(fs_path(abs), "rb")
  on.exit(close(con), add = TRUE)
  if (start_byte > 0) seek(con, start_byte, rw = "read")
  pieces = list()
  got = 0L
  repeat {
    r = readBin(con, "raw", 262144L)
    if (!length(r)) break
    pieces[[length(pieces) + 1L]] = r
    got = got + length(grepRaw(as.raw(10L), r, fixed = TRUE, all = TRUE))
    if (got >= skip + want) break
  }
  bytes = if (length(pieces)) do.call(c, pieces) else raw()
  nlp = grepRaw(as.raw(10L), bytes, fixed = TRUE, all = TRUE)
  s = if (skip == 0L) 1L else nlp[skip] + 1L
  e = if (length(nlp) >= skip + want) nlp[skip + want] - 1L else length(bytes)
  if (start_byte == 0 && skip == 0L && bom == "UTF-8") s = 4L
  wtxt = if (e >= s) rawToChar(bytes[s:e]) else ""
  lines = read_decode_lines(wtxt, d$encoding, d$lossy)
  list(binary = FALSE, lines = lines$lines, total = idx$total, encoding = d$encoding,
       lossy = d$lossy, eol = lines$eol)
}

#' Lines `offset .. offset + n - 1` of a text file with the total line count
#' @noRd
read_text_window = function(abs, offset = 1L, n = NULL, big = read_big_file,
                            every = read_index_every) {
  size = file.size(fs_path(abs))
  if (size <= big) return(read_window_small(abs, offset, n))
  read_window_big(abs, offset, n, size, every = every)
}

#' Estimator class of a file by its extension
#' @noRd
read_token_class = function(path) {
  ext = tolower(tools::file_ext(path))
  code = c("r", "rmd", "qmd", "py", "js", "ts", "c", "cpp", "h", "java", "sql", "sh", "jl", "rs",
           "go")
  if (ext %in% code) return("code")
  if (ext %in% c("csv", "tsv")) return("csv")
  if (ext %in% c("json", "jsonl", "ipynb")) return("json")
  "prose"
}

#' The leading part of one long line, cut on a UTF-8 character boundary
#' @noRd
read_line_prefix = function(line, max_bytes) {
  b = charToRaw(line)
  b = b[seq_len(min(max_bytes, length(b)))]
  while (length(b) && bitwAnd(as.integer(b[length(b)]), 0xC0L) == 0x80L) b = b[-length(b)]
  if (length(b) && as.integer(b[length(b)]) >= 0xC0L) b = b[-length(b)]
  as_utf8(rawToChar(b))
}

#' Shared core of read_file() and peter$read(): kind (text, empty, image, binary), the window and
#' notices
#' @noRd
read_core = function(path, offset = NULL, limit = NULL, budget_tokens = Inf) {
  check_string(path, "path")
  check_number(offset, "offset", min = 0, null = TRUE)
  check_number(limit, "limit", min = 1, null = TRUE)
  abs = read_resolve(path)
  p = fs_path(abs)
  if (!file.exists(p)) {
    gptr_abort(paste0("ENOENT: no such file or directory, access '", abs, "'"), "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  if (dir.exists(p)) {
    gptr_abort(paste0("EISDIR: illegal operation on a directory, read '", abs, "'"),
               "invalid_argument", arg = "path", expected = "a file, not a directory")
  }
  if (file.access(p, 4L) != 0L) {
    gptr_abort(paste0("EACCES: permission denied, access '", abs, "'"), "invalid_argument",
               arg = "path", expected = "a readable file")
  }
  size = file.size(p)
  start = if (is.null(offset) || offset < 1) 1L else as.integer(offset)
  out = list(kind = "text", path = path, abs = abs, size = size, start = start, total = NA_integer_,
             lines = character(), truncated = FALSE, by = NA_character_,
             first_line_bytes = NA_real_, user_limited = !is.null(limit), encoding = "UTF-8",
             eol = "\n", lossy = FALSE, image = NULL, note = NULL, budget_tokens = budget_tokens)
  if (size == 0) {
    out$kind = "empty"
    out$total = 0L
    return(out)
  }
  head = read_raw(abs, n = min(size, read_sniff_bytes))
  mime = detect_image_mime(head[seq_len(min(length(head), image_sniff_bytes))])
  if (!is.na(mime)) {
    im = process_image(read_raw(abs), mime)
    out$kind = "image"
    shown_mime = if (isTRUE(im$ok)) im$mime else mime
    out$note = paste(c(paste0("Read image file [", shown_mime, "]"), im$note), collapse = "\n")
    if (isTRUE(im$ok)) {
      out$image = block_image(im$data, mime = im$mime, source = "file",
                              width = as.integer(im$dims[1]), height = as.integer(im$dims[2]))
    }
    return(out)
  }
  if (is_binary_raw(head)) {
    out$kind = "binary"
    return(out)
  }
  w = read_text_window(abs, start, if (is.null(limit)) tool_max_lines + 1L else as.integer(limit))
  if (isTRUE(w$binary)) {
    out$kind = "binary"
    return(out)
  }
  out$total = w$total
  out$encoding = w$encoding
  out$eol = w$eol
  out$lossy = isTRUE(w$lossy)
  if (start > w$total) {
    gptr_abort(paste0("Offset ", format(offset), " is beyond end of file (", w$total,
                      " lines total)"),
               "invalid_argument", arg = "offset", expected = "a line within the file")
  }
  tr = truncate_lines_head(w$lines)
  lines = tr$lines
  cls = read_token_class(abs)
  if (!tr$first_line_exceeds && length(lines) && is.finite(budget_tokens) &&
        est_tokens(lines, cls) > budget_tokens) {
    k = lines_fit(lines, budget_tokens, cls)
    if (k == 0L) {
      tr$first_line_exceeds = TRUE
    } else {
      lines = lines[seq_len(k)]
      tr$truncated = TRUE
      tr$by = "tokens"
    }
  }
  if (tr$first_line_exceeds) {
    first = w$lines[1L]
    keep = tool_max_bytes
    if (is.finite(budget_tokens)) {
      per_token = nchar(first, type = "bytes") / max(1, est_tokens(first, cls))
      keep = min(keep, floor(per_token * budget_tokens))
    }
    lines = read_line_prefix(first, keep)
    out$first_line_bytes = nchar(first, type = "bytes")
    tr$truncated = TRUE
    tr$by = "first_line"
  }
  out$lines = lines
  out$truncated = isTRUE(tr$truncated)
  out$by = tr$by
  out
}

#' Notice lines of a read: Pi's texts plus the first-line, token-cap and encoding notices of report
#' 11
#' @noRd
read_notices = function(rc) {
  n = length(rc$lines)
  end = rc$start + n - 1L
  notes = if (identical(rc$by, "first_line")) {
    paste0("[Line ", rc$start, " is ", format_size(rc$first_line_bytes), ", exceeds the ",
           format_size(tool_max_bytes), " limit; showing its first ",
           format_size(nchar(rc$lines[1L], type = "bytes")),
           ". Use the r tool (for example substr()) to see the rest.]")
  } else if (isTRUE(rc$truncated)) {
    why = switch(rc$by, bytes = paste0(" (", format_size(tool_max_bytes), " limit)"),
                 tokens = paste0(" (", as.integer(rc$budget_tokens), " token limit)"), "")
    paste0("[Showing lines ", rc$start, "-", end, " of ", rc$total, why, ". Use offset=", end + 1L,
           " to continue.]")
  } else if (isTRUE(rc$user_limited) && end < rc$total) {
    paste0("[", rc$total - end, " more lines in file. Use offset=", end + 1L, " to continue.]")
  }
  c(notes, if (!identical(rc$encoding, "UTF-8")) paste0("[Decoded from ", rc$encoding, "]"),
    if (isTRUE(rc$lossy)) "[File is not valid UTF-8; invalid bytes shown as U+FFFD]")
}

#' Binary-file notice with a loading hint (report 11 section 3.3)
#' @noRd
read_binary_text = function(path, abs, size) {
  ext = tolower(tools::file_ext(abs))
  hint = if (ext %in% names(binary_hints)) binary_hints[[ext]] else "readBin()"
  paste0("[Binary file: ", path, " (", format_size(size), "). Not shown as text. ",
         "Load it with the r tool, e.g. ", hint, ".]")
}

#' Text of a read window: the lines and, after a blank line, the notices
#' @noRd
read_text_body = function(rc) {
  body = paste(rc$lines, collapse = "\n")
  notes = read_notices(rc)
  if (length(notes)) paste0(body, "\n\n", paste(notes, collapse = "\n")) else body
}

#' Read a file for the model: the `read` tool (contract section 7.10)
#'
#' @param path File path (relative to the working directory, absolute, or `skill:<name>/<path>`).
#' @param offset,limit 1-based first line and number of lines (`NULL`: from line 1, up to the caps).
#' @param budget_tokens Estimated-token cap of the text (`gptr.read_max_tokens`, 12,000).
#' @return `list(text = chr(1), image = <image block> | NULL, details = list(path, offset, limit,
#'   lines_total, truncated, image, encoding, eol))`
#' @noRd
read_file = function(path, offset = NULL, limit = NULL,
                     budget_tokens = gptr_opt("read_max_tokens")) {
  check_number(budget_tokens, "budget_tokens", min = 1)
  rc = read_core(path, offset, limit, budget_tokens = budget_tokens)
  details = list(path = rc$abs, offset = rc$start, limit = length(rc$lines), lines_total = rc$total,
                 truncated = isTRUE(rc$truncated), image = identical(rc$kind, "image"),
                 encoding = rc$encoding, eol = rc$eol)
  text = switch(rc$kind,
                empty = paste0("[File is empty: ", path, "]"),
                image = rc$note,
                binary = read_binary_text(path, rc$abs, rc$size),
                read_text_body(rc))
  list(text = as_utf8(text), image = rc$image, details = details)
}

#' The value of `peter$read()`: the window's lines as a `gptr_lines` vector (contract section 5.10)
#'
#' An image file gives its note line, and the image block travels in the attribute `image_block`
#' until the member attaches it to the running `r` result.
#' @noRd
read_lines_value = function(path, offset = NULL, limit = NULL) {
  rc = read_core(path, offset, limit, budget_tokens = Inf)
  lines = switch(rc$kind,
                 empty = character(),
                 image = rc$note,
                 binary = read_binary_text(path, rc$abs, rc$size),
                 rc$lines)
  structure(as_utf8(lines), class = c("gptr_lines", "character"), path = rc$abs, offset = rc$start,
            limit = length(rc$lines), total = rc$total, truncated = isTRUE(rc$truncated),
            encoding = rc$encoding,
            notices = if (identical(rc$kind, "text")) read_notices(rc) else character(),
            image_block = rc$image)
}

#' Print the lines of `peter$read()` in Pi's read format within the member budget
#'
#' @param x A `gptr_lines` vector.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_lines = function(x, ...) {
  shown = budget_head(as.character(x), member_budget(), read_token_class(attr(x, "path") %||% ""))
  out = shown$lines
  if (shown$omitted > 0L) {
    out = c(out, paste0("[... ", shown$omitted,
                        " more lines not printed; index the value or use offset/limit]"))
  }
  notes = attr(x, "notices") %||% character()
  if (length(notes)) out = c(out, "", notes)
  ns_print_lines(out)
  invisible(x)
}
```

Regenerate `NAMESPACE` (adds `S3method(print,gptr_lines)`):

```bash
Rscript --vanilla -e 'devtools::document()'
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-read")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 80 ]` with magick installed (without magick the BMP test takes its note branch: `PASS 78`).

- [ ] **Step 5: Commit**

```bash
git add R/tool-read.R tests/testthat/test-tool-read.R NAMESPACE
git commit -m "feat(tools): add the read engine with encodings, images and line indexes"
```

### Task 5: The `write` engine

**Files:** Create: `R/tool-write.R`; Test: `tests/testthat/test-tool-write.R`.

`write_file()` backs the direct `write` tool and `peter$write()` (Task 10) and P23's artifact writes (04 §7.10). Ported from report 11 §5.5 (`proto/20-write.R`) and §2.3: the text is encoded before any file is touched (a character the existing encoding cannot represent fails cleanly), the bytes go through P01's `write_atomic()` (temporary file in the target's directory, rename with retries), parent directories are created, and a symbolic link is resolved first because `file.rename()` would replace the link itself (verified on macOS). An existing text file keeps its dominant line ending, byte-order mark, encoding and permission bits; a new file is written verbatim as in Pi (report 01 §2.4). Pi's message `Successfully wrote to <path>` is produced by the direct tool's execute in Task 10.

**Interfaces:**
- Consumes (P01): `write_atomic(path, content)`, `as_utf8()`, `utf8_mark()`, `check_string()`, `gptr_abort()`; Task 2: `fs_path()`, `tool_path_is_abs()`, `tool_path_norm()`, `resolve_tool_path()`; Task 4: `read_raw()`, `is_binary_raw()`, `decode_raw()`, `encode_text()`.
- Produces (04 §7.10): `write_file(path, content)` -> `list(bytes = num(1), created = lgl(1), details = list(path, bytes, created, encoding, eol))` (`details$path` is the absolute path written: the link target for a symlink); internal for Task 6: `resolve_link_target(p, max_hops = 40L)`, `write_bytes_keep_mode(target, bytes)` -> `invisible(existed)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-write.R` (Pi's write oracle cases of report 01 §5.9 and the conventions of report 11 §2.3):

```r
# Tests for R/tool-write.R: Pi's write oracle cases (dev/research/01-pi-builtin-tools.md section
# 5.9) and the conventions of dev/research/11-r-file-tools.md section 2.3 (EOL, BOM, encoding,
# links, mode bits).

raw_of = function(p) readBin(fs_path(p), "raw", file.size(fs_path(p)) + 10)

test_that("write creates parent directories and writes a new file verbatim", {
  td = withr::local_tempdir()
  p = file.path(td, "nested", "dir", "test.txt")
  w = write_file(p, "Nested \u4f60\u597d\r\nx")
  expect_identical(raw_of(p), charToRaw("Nested \u4f60\u597d\r\nx"))
  expect_true(w$created)
  expect_identical(w$bytes, length(raw_of(p)))
  expect_identical(w$details$path, resolve_tool_path(p))
  expect_identical(w$details$eol, "asis")
  w2 = write_file(p, "again\n")
  expect_false(w2$created)
  expect_identical(raw_of(p), charToRaw("again\r\n"))
  expect_identical(w2$details$eol, "\r\n")
})

test_that("relative paths resolve against the working directory", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  write_file("rel/a.txt", "x")
  expect_identical(raw_of(file.path(td, "rel", "a.txt")), charToRaw("x"))
})

test_that("an existing CRLF file keeps CRLF, its BOM and its encoding", {
  td = withr::local_tempdir()
  p = file.path(td, "crlf.txt")
  writeBin(charToRaw("a\r\nb\r\n"), p)
  write_file(p, "one\ntwo\n")
  expect_identical(raw_of(p), charToRaw("one\r\ntwo\r\n"))
  p = file.path(td, "bom.txt")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("old\n")), p)
  write_file(p, "new\n")
  expect_identical(raw_of(p), c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("new\n")))
  p = file.path(td, "cp1252.R")
  writeBin(as.raw(c(charToRaw("x = \"caf"), 0xe9, charToRaw("\"\n"))), p)
  write_file(p, "y = \"th\u00e9\"\n")
  expect_identical(raw_of(p), as.raw(c(charToRaw("y = \"th"), 0xe9, charToRaw("\"\n"))))
  before = raw_of(p)
  expect_error(write_file(p, "z = \"\u4f60\"\n"),
               "cannot be represented in the file's encoding (CP1252)",
               fixed = TRUE, class = "gptr_error_invalid_argument")
  expect_identical(raw_of(p), before)
})

test_that("write refuses directories and writes through symbolic links keeping the mode", {
  td = withr::local_tempdir()
  expect_error(write_file(td, "x"), "EISDIR", class = "gptr_error_invalid_argument")
  skip_on_os("windows")
  real = file.path(td, "real.txt")
  writeBin(charToRaw("old"), real)
  Sys.chmod(real, "0755", use_umask = FALSE)
  link = file.path(td, "link.txt")
  file.symlink(real, link)
  w = write_file(link, "new")
  expect_identical(raw_of(real), charToRaw("new"))
  expect_true(nzchar(Sys.readlink(link)))
  expect_identical(format(file.info(real)$mode), "755")
  expect_identical(w$details$path, resolve_tool_path(real))
})

test_that("no temporary file is left behind", {
  td = withr::local_tempdir()
  write_file(file.path(td, "a.txt"), "x")
  expect_identical(list.files(td, all.files = TRUE, no.. = TRUE), "a.txt")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-write")'
```

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`; the tests error with `could not find function "write_file"`.

- [ ] **Step 3: Write the implementation**

Create `R/tool-write.R`:

```r
# tool-write.R -- the `write` tool and `peter$write()` (P10): an atomic replace through P01's
# write_atomic() that keeps an existing file's line endings, byte-order mark, encoding and
# permission bits and writes through symbolic links. Ported from dev/research/11-r-file-tools.md
# section 5.5 (proto/20-write.R) and section 2.3: the text is encoded before any file is touched,
# the temporary file lives in the target's directory, and a symlink is resolved first because
# rename() would replace the link itself (verified on macOS). New files are written verbatim, as in
# Pi (dev/research/01-pi-builtin-tools.md section 2.4).

#' Follow a symlink chain to the file it names (a no-op on Windows, where Sys.readlink() returns "")
#' @noRd
resolve_link_target = function(p, max_hops = 40L) {
  for (i in seq_len(max_hops)) {
    l = Sys.readlink(fs_path(p))
    if (is.na(l) || !nzchar(l)) return(p)
    l = as_utf8(l)
    p = if (tool_path_is_abs(l)) tool_path_norm(l) else tool_path_norm(file.path(dirname(p), l))
  }
  gptr_abort(paste0("ELOOP: too many symbolic links encountered, open '", p, "'"),
             "invalid_argument", arg = "path", expected = "a path without a symbolic-link loop")
}

#' Encoding, BOM and dominant line ending of an existing text file; NULL for a new file and
#' `list(binary = TRUE)` for a binary one
#' @noRd
write_conventions = function(path) {
  p = fs_path(path)
  if (!file.exists(p) || dir.exists(p)) return(NULL)
  b = read_raw(path, n = min(file.size(p), 1024^2))
  if (is_binary_raw(b)) return(list(binary = TRUE))
  d = tryCatch(decode_raw(b), error = function(e) NULL)
  if (is.null(d)) return(list(binary = TRUE))
  count = function(pattern) {
    m = gregexpr(pattern, d$text, fixed = TRUE, useBytes = TRUE)[[1L]]
    if (m[1L] == -1L) 0L else length(m)
  }
  n_crlf = count("\r\n")
  n_lf = count("\n") - n_crlf
  list(binary = FALSE, encoding = if (d$lossy) "UTF-8" else d$encoding, bom = d$bom,
       eol = if (n_crlf > 0L && n_crlf >= n_lf) "\r\n" else "\n")
}

#' Write bytes atomically, creating parent directories and keeping the target's mode bits; returns
#' TRUE invisibly when the file existed before
#' @noRd
write_bytes_keep_mode = function(target, bytes) {
  p = fs_path(target)
  existed = file.exists(p)
  mode = if (existed) file.info(p, extra_cols = FALSE)$mode else NULL
  dir = dirname(target)
  if (!dir.exists(fs_path(dir))) {
    dir.create(fs_path(dir), recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(fs_path(dir))) {
      gptr_abort(paste0("ENOENT: could not create directory '", dir, "'"), "invalid_argument",
                 arg = "path", expected = "a path whose parent directory can be created")
    }
  }
  write_atomic(p, bytes)
  if (!is.null(mode) && .Platform$OS.type != "windows") Sys.chmod(p, mode, use_umask = FALSE)
  invisible(existed)
}

#' Write a file for the model or the user: the `write` tool (contract section 7.10)
#'
#' @param path File path (relative to the working directory or absolute).
#' @param content The complete new content, chr(1).
#' @return `list(bytes = num(1), created = lgl(1), details = list(path, bytes, created,
#'   encoding, eol))`; `details$path` is the absolute path of the file written (the link target
#'   for a symlink).
#' @noRd
write_file = function(path, content) {
  check_string(path, "path")
  check_string(content, "content", empty = TRUE)
  abs = resolve_tool_path(path)
  if (dir.exists(fs_path(abs))) {
    gptr_abort(paste0("EISDIR: illegal operation on a directory, open '", abs, "'"),
               "invalid_argument", arg = "path", expected = "a file path, not a directory")
  }
  target = resolve_link_target(abs)
  conv = write_conventions(target)
  text = as_utf8(content)
  enc = "UTF-8"
  bom = FALSE
  eol = "asis"
  if (!is.null(conv) && !isTRUE(conv$binary)) {
    enc = conv$encoding
    bom = conv$bom
    eol = conv$eol
    text = gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
    if (identical(eol, "\r\n")) text = gsub("\n", "\r\n", text, fixed = TRUE, useBytes = TRUE)
    text = utf8_mark(text)
  }
  bytes = encode_text(text, enc, bom)
  existed = write_bytes_keep_mode(target, bytes)
  list(bytes = length(bytes), created = !existed,
       details = list(path = target, bytes = length(bytes), created = !existed, encoding = enc,
                      eol = eol))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-write")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]` (the symlink and mode test skips on Windows).

- [ ] **Step 5: Commit**

```bash
git add R/tool-write.R tests/testthat/test-tool-write.R
git commit -m "feat(tools): add the atomic, convention-preserving write engine"
```

### Task 6: The `edit` engine, the fuzzy fallback and patch envelopes

**Files:** Create: `R/tool-edit.R`; Test: `tests/testthat/test-tool-edit.R`; Modify: `NAMESPACE` (generated).

`edit_file()` backs the direct `edit` tool and `peter$edit()` (Task 10) and P15's routed document edits (04 §7.10). Ported from report 11 §5.5 (`proto/31-edit.R`; §2.4) and report 01 §2.5 and §3.4 (Pi's algorithm and texts): every `oldText` is matched against the **original** file, must be unique and must not overlap another edit; nothing is written unless every edit succeeds; the fuzzy fallback (NFKC through stringi when installed, trailing whitespace, smart quotes, Unicode dashes, special spaces; every class pattern starts with `(*UTF)` so it compiles on all-ASCII input, report 11 P5) rewrites only the touched lines; bytes outside the edited spans are kept exactly (mixed line endings, BOM, CP1252, UTF-16, stray invalid bytes). One deliberate return to Pi over report 11: occurrences are counted in fuzzy-normalised space (Pi `edit-diff.ts:247-251`), so Pi's oracle case `"hello world   \nhello world\n"` reports 2 occurrences. `edit_normalize_args()` is Pi's `prepareEditArguments()` (edits as a JSON string, a single object or a data frame). A pasted Codex `*** Begin Patch` envelope (in `edits` itself, or as the only edit's `newText`/`oldText` with the other text empty, which is how a model pastes one through the direct schema) is applied by `patch_apply()` (`*** Add File`, `*** Update File` with `*** Move to`, `*** Delete File`, `@@` hunks; every operation computed before anything is written). `edit_result_text()` is the model text of acceptance 6: Pi's message alone, or, when the fuzzy fallback, an EOL change, a re-encoding or kept invalid bytes made the result deviate from the literal request, the message, one bracketed reason line and the diff (at most 400 tokens, 03 §7.1). `edit_nested_input()` prepares the gate input of a nested `peter$edit()` call with an envelope: `edits = list()` plus `patch = <envelope>`, so the input validates against the edit schema (Task 10 tests it through the schema).

**Interfaces:**
- Consumes (P01): `as_utf8()`, `utf8_mark()`, `project_root()`, checkers, `gptr_abort()`, `` `%||%` ``; Task 1: `ns_print_lines()`; Task 2: `fs_path()`, `resolve_tool_path(path, cwd)`; Task 3: `diff_lines()`, `diff_split()`, `diff_unified()`; Task 4: `split_lines_js()`, `split_lines_count()`, `detect_eol()`, `normalize_lf()`, `read_raw()`, `is_binary_raw()`, `sniff_bom()`, `decode_raw()`, `encode_text()`, `bom_bytes`, `replacement_sub`; Task 5: `resolve_link_target()`, `write_bytes_keep_mode()`.
- Produces (04 §7.10, §5.10): `edit_file(path, edits, replace_all = FALSE)` -> `list(message, diff = chr (at most 400 tokens), fuzzy = lgl(1), details = list(path, n_edits, fuzzy, diff (the full unified diff), document, deviated, reasons, encoding))`; `patch_apply(envelope, root = project_root())` -> `list(files, message, details)`; `new_gptr_patch(path, message, diff, n_edits, fuzzy)` -> `gptr_patch` with `print.gptr_patch()`; internal for Task 10: `edit_result_text(ed)`, `edit_normalize_args(edits)`, `edit_envelope_of(edits)`, `edit_nested_input(input)`, `patch_paths(envelope)` -> chr (paths an envelope touches, for the risk function).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-edit.R` (Pi's oracle cases of report 01 §5.9 `test-01.R` "== edit", "== edit fuzzy", "== edit CRLF / BOM / encodings", "== edit argument shim", and report 11 §5.6's byte-exactness cases):

```r
# Tests for R/tool-edit.R. Pi oracle cases from dev/research/01-pi-builtin-tools.md section 5.9
# (test-01.R, "== edit", "== edit fuzzy", "== edit CRLF / BOM / encodings", "== edit argument shim")
# and report 11's byte-exactness cases (dev/research/11-r-file-tools.md section 5.6, "edit").

wr = function(dir, name, text) {
  p = file.path(dir, name)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.character(text)) charToRaw(text) else text, p)
  p
}
rd = function(p) {
  x = rawToChar(readBin(p, "raw", file.size(p)))
  Encoding(x) = "UTF-8"
  x
}
err = function(expr) {
  tryCatch({
    force(expr)
    NA_character_
  }, error = function(e) conditionMessage(e))
}
e1 = function(old, new) list(list(oldText = old, newText = new))

test_that("a basic edit writes the file and returns Pi's message and a diff", {
  td = withr::local_tempdir()
  f = wr(td, "edit-test.txt", "Hello, world!")
  ed = edit_file(f, e1("world", "testing"))
  expect_identical(ed$message, sprintf("Successfully replaced 1 block(s) in %s.", f))
  expect_identical(rd(f), "Hello, testing!")
  expect_identical(ed$diff, c("@@ -1 +1 @@", "-Hello, world!", "+Hello, testing!"))
  expect_identical(ed$details$diff[1:2], c(paste0("--- a/", f), paste0("+++ b/", f)))
  expect_true("\\ No newline at end of file" %in% ed$details$diff)
  expect_false(ed$fuzzy)
  expect_named(ed$details, c("path", "n_edits", "fuzzy", "diff", "document", "deviated", "reasons",
                             "encoding"))
})

test_that("edit errors use Pi's texts and never write partially", {
  td = withr::local_tempdir()
  f = wr(td, "edit-test.txt", "Hello, world!")
  expect_match(err(edit_file(f, e1("nonexistent", "t"))), "^Could not find the exact text in ")
  m = file.path(td, "missing.txt")
  expect_identical(err(edit_file(m, e1("a", "b"))),
                   sprintf("Could not edit file: %s. Error code: ENOENT.", m))
  f = wr(td, "dups.txt", "foo foo foo")
  expect_match(err(edit_file(f, e1("foo", "bar"))), "^Found 3 occurrences of the text in ")
  f = wr(td, "overlap.txt", "one\ntwo\nthree\n")
  expect_match(err(edit_file(f, list(list(oldText = "one\ntwo\n", newText = "A"),
                                     list(oldText = "two\nthree\n", newText = "B")))),
               "^edits\\[0\\] and edits\\[1\\] overlap in ")
  f = wr(td, "nopartial.txt", "alpha\nbeta\ngamma\n")
  expect_match(err(edit_file(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"),
                                     list(oldText = "missing\n", newText = "M\n")))),
               "^Could not find edits\\[1\\] in ")
  expect_identical(rd(f), "alpha\nbeta\ngamma\n")
  f = wr(td, "same.txt", "abc\n")
  expect_match(err(edit_file(f, e1("abc", "abc"))), "^No changes made to ")
  expect_match(err(edit_file(f, e1("", "x"))), "oldText must not be empty", fixed = TRUE)
  expect_match(err(edit_file(f, list())), "edits must contain at least one replacement",
               fixed = TRUE)
  if (.Platform$OS.type != "windows") {
    f = wr(td, "ro.txt", "hello\n")
    Sys.chmod(f, "0444")
    expect_identical(err(edit_file(f, e1("hello", "w"))),
                     sprintf("Could not edit file: %s. Error code: EACCES.", f))
  }
})

test_that("multiple edits are matched against the original, not incrementally", {
  td = withr::local_tempdir()
  f = wr(td, "multi.txt", "alpha\nbeta\ngamma\ndelta\n")
  ed = edit_file(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"),
                         list(oldText = "gamma\n", newText = "GAMMA\n")))
  expect_match(ed$message, "Successfully replaced 2 block(s)", fixed = TRUE)
  expect_identical(rd(f), "ALPHA\nbeta\nGAMMA\ndelta\n")
  f = wr(td, "orig.txt", "foo\nbar\nbaz\n")
  edit_file(f, list(list(oldText = "foo\n", newText = "foo bar\n"),
                    list(oldText = "bar\n", newText = "BAR\n")))
  expect_identical(rd(f), "foo bar\nBAR\nbaz\n")
})

test_that("the fuzzy fallback normalises whitespace, quotes, dashes and special spaces", {
  td = withr::local_tempdir()
  f = wr(td, "tws.txt", "line one   \nline two  \nline three\n")
  edit_file(f, e1("line one\nline two\n", "replaced\n"))
  expect_identical(rd(f), "replaced\nline three\n")
  f = wr(td, "sq.txt", "console.log(\u2018hello\u2019);\n")
  edit_file(f, e1("console.log('hello');", "console.log('world');"))
  expect_identical(rd(f), "console.log('world');\n")
  f = wr(td, "dq.txt", "const msg = \u201cHello World\u201d;\n")
  edit_file(f, e1("const msg = \"Hello World\";", "const msg = \"Goodbye\";"))
  expect_match(rd(f), "Goodbye", fixed = TRUE)
  f = wr(td, "dash.txt", "range: 1\u20135\nbreak\u2014here\n")
  edit_file(f, e1("range: 1-5\nbreak-here", "range: 10-50\nbreak--here"))
  expect_identical(rd(f), "range: 10-50\nbreak--here\n")
  f = wr(td, "nbsp.txt", "hello\u00a0world\n")
  edit_file(f, e1("hello world", "hello universe"))
  expect_identical(rd(f), "hello universe\n")
  orig = paste(c("keep before  ", "first target  ", "first after", "keep middle   ",
                 "second target  ", "second after", "keep after  ", ""), collapse = "\n")
  f = wr(td, "fpres.txt", orig)
  edit_file(f, list(list(oldText = "first target\nfirst after", newText = "FIRST\nFIRST2"),
                    list(oldText = "second target\nsecond after", newText = "SECOND\nSECOND2")))
  expect_identical(rd(f), paste(c("keep before  ", "FIRST", "FIRST2", "keep middle   ", "SECOND",
                                  "SECOND2", "keep after  ", ""), collapse = "\n"))
  f = wr(td, "fdupline.txt", "replace me   \nafter   \n")
  edit_file(f, e1("replace me\n", "after\n"))
  expect_identical(rd(f), "after\nafter   \n")
})

test_that("NFKC compatibility forms match through stringi", {
  skip_if_not_installed("stringi")
  td = withr::local_tempdir()
  f = wr(td, "compat.txt", "\uff21\uff22\uff23\uff11\uff12\uff13\ncafe\u0301\n")
  edit_file(f, e1("ABC123\ncaf\u00e9\n", "XYZ789\ncoffee\n"))
  expect_identical(rd(f), "XYZ789\ncoffee\n")
})

test_that("exact matches win and occurrences are counted in fuzzy space (Pi)", {
  td = withr::local_tempdir()
  f = wr(td, "exact.txt", "const x = 'exact';\nconst y = 'other';\n")
  ed = edit_file(f, e1("const x = 'exact';", "const x = 'changed';"))
  expect_identical(rd(f), "const x = 'changed';\nconst y = 'other';\n")
  expect_false(ed$fuzzy)
  f = wr(td, "fdups.txt", "hello world   \nhello world\n")
  expect_match(err(edit_file(f, e1("hello world", "replaced"))), "^Found 2 occurrences")
})

test_that("CRLF, BOM, mixed endings, CP1252, UTF-16 and stray bytes round-trip byte for byte", {
  td = withr::local_tempdir()
  f = wr(td, "crlf.txt", "first\r\nsecond\r\nthird\r\n")
  edit_file(f, e1("second\n", "REPLACED\n"))
  expect_identical(rd(f), "first\r\nREPLACED\r\nthird\r\n")
  f = wr(td, "mixed.txt", "one\r\ntwo\nthree\r\nfour\n")
  edit_file(f, e1("three\nfour", "3\n4"))
  expect_identical(rd(f), "one\r\ntwo\n3\r\n4\n")
  f = wr(td, "dupmix.txt", "hello\r\nworld\r\n---\r\nhello\nworld\n")
  expect_match(err(edit_file(f, e1("hello\nworld\n", "replaced\n"))), "^Found 2 occurrences")
  bom = as.raw(c(0xEF, 0xBB, 0xBF))
  f = wr(td, "bom.txt", c(bom, charToRaw("first\r\nsecond\r\nthird\r\nfourth\r\n")))
  edit_file(f, list(list(oldText = "second\n", newText = "SECOND\n"),
                    list(oldText = "fourth\n", newText = "FOURTH\n")))
  expect_identical(readBin(f, "raw", 200), c(bom,
                                             charToRaw("first\r\nSECOND\r\nthird\r\nFOURTH\r\n")))
  p = wr(td, "cp1252.R", as.raw(c(charToRaw("x = \"caf"), 0xE9, charToRaw("\"\ny = 1\n"))))
  edit_file(p, e1("y = 1", "y = 2"))
  expect_identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x = \"caf"), 0xE9,
                                                    charToRaw("\"\ny = 2\n"))))
  expect_match(err(edit_file(p, e1("y = 2", "y = '\u4f60'"))), "cannot be represented")
  expect_identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x = \"caf"), 0xE9,
                                                    charToRaw("\"\ny = 2\n"))))
  p = wr(td, "utf16.txt", c(as.raw(c(0xFF, 0xFE)), iconv("h\u00e9llo\n", "UTF-8", "UTF-16LE",
                                                         toRaw = TRUE)[[1L]]))
  edit_file(p, e1("llo", "LLO"))
  expect_identical(readBin(p, "raw", 100), c(as.raw(c(0xFF, 0xFE)),
                                             iconv("h\u00e9LLO\n", "UTF-8", "UTF-16LE",
                                                   toRaw = TRUE)[[1L]]))
  p = wr(td, "lossy.R", c(charToRaw("# caf\u00e9\n"), as.raw(0xFF), charToRaw("\nx = 1\n")))
  edit_file(p, e1("x = 1", "x = 2"))
  expect_identical(readBin(p, "raw", 100), c(charToRaw("# caf\u00e9\n"), as.raw(0xFF),
                                             charToRaw("\nx = 2\n")))
})

test_that("replace_all replaces every occurrence", {
  td = withr::local_tempdir()
  f = wr(td, "e1.R", "f = function(x) x\ng = function(y) y\n")
  ed = edit_file(f, e1("function", "\\(z)"), replace_all = TRUE)
  expect_match(ed$message, "replaced 2 block(s)", fixed = TRUE)
  expect_identical(rd(f), "f = \\(z)(x) x\ng = \\(z)(y) y\n")
  f = wr(td, "e2.R", "a a a\n")
  edit_file(f, list(list(oldText = "a", newText = "b", replaceAll = TRUE)))
  expect_identical(rd(f), "b b b\n")
})

test_that("Pi's argument shim accepts JSON strings, a single object and a data frame", {
  expect_identical(edit_normalize_args("[{\"oldText\":\"a\",\"newText\":\"b\"}]"),
                   list(list(oldText = "a", newText = "b")))
  expect_identical(edit_normalize_args(list(oldText = "a", newText = "b")),
                   list(list(oldText = "a", newText = "b")))
  expect_identical(edit_normalize_args(data.frame(oldText = "a", newText = "b"))[[1L]]$newText, "b")
  expect_error(edit_normalize_args("not json"), "edits must contain at least one replacement")
})

test_that("the result text carries a diff only when something deviated (acceptance 6)", {
  td = withr::local_tempdir()
  f = wr(td, "exact.R", "x = 1\ny = 2\n")
  ed = edit_file(f, e1("y = 2", "y = 3"))
  expect_identical(edit_result_text(ed), ed$message)
  g = wr(td, "fuzzy.R", paste0(paste(sprintf("v%03d = %d   ", 1:300, 1:300), collapse = "\n"),
                               "\n"))
  ed = edit_file(g, e1("v150 = 150\nv151 = 151", "v150 = 0\nv151 = 0"))
  expect_true(ed$fuzzy)
  txt = edit_result_text(ed)
  expect_true(startsWith(txt, ed$message))
  expect_match(txt, "[matched after whitespace, quote or dash normalisation]", fixed = TRUE)
  expect_match(txt, "@@", fixed = TRUE)
  expect_lte(est_tokens(paste(ed$diff, collapse = "\n"), "code"), 400)
  c1 = wr(td, "crlf.R", "a = 1\r\nb = 2\r\n")
  ed = edit_file(c1, e1("a = 1\nb = 2", "a = 3\nb = 4"))
  expect_match(edit_result_text(ed), "line endings written as CRLF", fixed = TRUE)
  expect_identical(rd(c1), "a = 3\r\nb = 4\r\n")
})

test_that("patch envelopes add, update, move and delete files atomically", {
  td = withr::local_tempdir()
  wr(td, "a.R", "x = 1\ny = 2\nz = 3\n")
  wr(td, "old.R", "gone\n")
  wr(td, "m.R", "keep = 1\n")
  env = paste(c("*** Begin Patch", "*** Add File: new/b.R", "+b = 1", "+c = 2",
                "*** Update File: a.R", "@@", " x = 1", "-y = 2", "+y = 20", " z = 3",
                "*** Update File: m.R", "*** Move to: moved.R", "@@", "-keep = 1", "+keep = 2",
                "*** Delete File: old.R", "*** End Patch"), collapse = "\n")
  expect_true(patch_is_envelope(env))
  expect_identical(sort(patch_paths(env)), sort(c("new/b.R", "a.R", "m.R", "old.R", "moved.R")))
  pa = patch_apply(env, root = td)
  expect_match(pa$message, "^Applied patch: 4 file\\(s\\) changed\\.")
  expect_identical(rd(file.path(td, "new/b.R")), "b = 1\nc = 2\n")
  expect_identical(rd(file.path(td, "a.R")), "x = 1\ny = 20\nz = 3\n")
  expect_identical(rd(file.path(td, "moved.R")), "keep = 2\n")
  expect_false(file.exists(file.path(td, "m.R")))
  expect_false(file.exists(file.path(td, "old.R")))
  bad = paste(c("*** Begin Patch", "*** Add File: c.R", "+c = 1", "*** Update File: a.R", "@@",
                "-nope", "+x",
                "*** End Patch"), collapse = "\n")
  expect_error(patch_apply(bad, root = td), "Could not find the exact text")
  expect_false(file.exists(file.path(td, "c.R")))
  expect_error(patch_apply("*** Begin Patch\n*** Add File: x.R\n", root = td),
               "missing '*** End Patch'",
               fixed = TRUE)
})

test_that("edit_file() applies a pasted envelope relative to the working directory", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  wr(td, "a.R", "x = 1\n")
  ed = edit_file("a.R", "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 2\n*** End Patch")
  expect_identical(rd(file.path(td, "a.R")), "x = 2\n")
  expect_match(ed$message, "M a.R", fixed = TRUE)
})

test_that("an envelope pasted into the only edit's newText or oldText is applied as a patch", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  wr(td, "a.R", "x = 1\n")
  env = "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 3\n*** End Patch"
  expect_identical(edit_envelope_of(e1("", env)), env)
  expect_identical(edit_envelope_of(list(list(oldText = env))), env)
  expect_identical(edit_envelope_of(env), env)
  expect_null(edit_envelope_of(e1("x = 1", env)))
  expect_null(edit_envelope_of(e1("x = 1", "x = 2")))
  ed = edit_file("a.R", e1("", env))
  expect_identical(rd(file.path(td, "a.R")), "x = 3\n")
  expect_match(ed$message, "Applied patch: 1 file(s) changed.", fixed = TRUE)
})

test_that("edit_nested_input() sends an envelope to the gate as `patch` with an empty edits", {
  env = "*** Begin Patch\n*** Add File: b.R\n+y = 1\n*** End Patch"
  inp = edit_nested_input(list(path = "b.R", edits = env))
  expect_identical(inp, list(path = "b.R", edits = list(), patch = env))
  plain = list(path = "a.R", edits = e1("a", "b"))
  expect_identical(edit_nested_input(plain), plain)
})

test_that("gptr_patch prints the message, and the diff only when fuzzy", {
  p = new_gptr_patch("a.R", "Successfully replaced 1 block(s) in a.R.",
                     c("@@ -1 +1 @@", "-a", "+b"), 1L, FALSE)
  expect_identical(utils::capture.output(print(p)), "Successfully replaced 1 block(s) in a.R.")
  p$fuzzy = TRUE
  expect_identical(utils::capture.output(print(p)), c("Successfully replaced 1 block(s) in a.R.",
                                                      "@@ -1 +1 @@", "-a", "+b"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-edit")'
```

Expected: `[ FAIL 23 | WARN 0 | SKIP 0 | PASS 1 ]`; the tests error with `could not find function "edit_file"` (or `"apply_edits"`, `"edit_normalize_args"`, `"patch_apply"`, `"edit_nested_input"`, `"new_gptr_patch"`), and the error-text expectations fail because the helper `err()` returns `could not find function` instead of Pi's message.

- [ ] **Step 3: Write the implementation**

Create `R/tool-edit.R`:

```r
# tool-edit.R -- the `edit` tool and `peter$edit()` (P10): Pi's multi-edit semantics (every oldText
# matched against the original, unique, non-overlapping; nothing written unless every edit
# succeeds), the fuzzy fallback (NFKC with stringi, trailing whitespace, smart quotes, dashes,
# special spaces) that rewrites only the touched lines, bytes outside the edited spans kept exactly
# (mixed line endings, BOM, CP1252, UTF-16, stray invalid bytes), `replace_all`, and pasted `***
# Begin Patch` envelopes (Codex format). Ported from dev/research/11-r-file-tools.md section 5.5
# (proto/31-edit.R; section 2.4) and dev/research/01-pi-builtin-tools.md sections 2.5 and 3.4 (Pi's
# algorithm and texts). One deliberate return to Pi over report 11: occurrences are counted in
# fuzzy-normalised space (edit-diff.ts:247-251), so Pi's oracle case "hello world   \nhello world\n"
# reports 2 occurrences.

#' Pi normalizeForFuzzyMatch() applied line by line (the line structure is unchanged). Every class
#' pattern starts with (*UTF) so it compiles on all-ASCII input (report 11 P5)
#' @noRd
fuzzy_normalize_lines = function(x) {
  x = utf8_mark(x)
  if (requireNamespace("stringi", quietly = TRUE)) x = stringi::stri_trans_nfkc(x)
  x = sub("(*UTF)[\\h\\v\\x{FEFF}]+$", "", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{2018}\\x{2019}\\x{201A}\\x{201B}]", "'", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{201C}\\x{201D}\\x{201E}\\x{201F}]", "\"", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{2010}-\\x{2015}\\x{2212}]", "-", x, perl = TRUE)
  x = gsub("(*UTF)[\\x{00A0}\\x{2002}-\\x{200A}\\x{202F}\\x{205F}\\x{3000}]", " ", x, perl = TRUE)
  utf8_mark(x)
}

#' Fuzzy normalisation of a whole text
#' @noRd
fuzzy_normalize = function(text) {
  utf8_mark(paste(fuzzy_normalize_lines(split_lines_js(text)), collapse = "\n"))
}

#' All non-overlapping occurrences (0-based byte offsets) of a fixed string; locale independent
#' @noRd
fixed_positions = function(haystack, needle) {
  r = gregexpr(needle, haystack, fixed = TRUE, useBytes = TRUE)[[1L]]
  if (r[1L] == -1L) integer(0) else as.integer(r) - 1L
}

#' Splice replacements (0-based start, byte length, new text) into a string, working on raw bytes
#' @noRd
splice_bytes = function(x, start, len, new) {
  if (!length(start)) return(x)
  o = order(start)
  start = start[o]
  len = len[o]
  new = new[o]
  b = charToRaw(x)
  pieces = vector("list", 2L * length(start) + 1L)
  pos = 0
  for (i in seq_along(start)) {
    pieces[[2L * i - 1L]] = if (start[i] > pos) b[(pos + 1):start[i]] else raw(0)
    pieces[[2L * i]] = charToRaw(new[i])
    pos = start[i] + len[i]
  }
  pieces[[length(pieces)]] = if (pos < length(b)) b[(pos + 1):length(b)] else raw(0)
  rawToChar(unlist(pieces))
}

#' Signal an edit error with Pi's single-edit or multi-edit wording (`i` is 1-based, shown 0-based)
#' @noRd
edit_error = function(single, multi, path, i, n) {
  msg = if (n == 1L) sprintf(single, path) else sprintf(multi, i - 1L, path)
  gptr_abort(msg, "invalid_argument", arg = "edits", expected = "edits that match the file")
}

#' Apply edits to decoded text (a string without BOM; unmarked bytes when it is lossy UTF-8)
#'
#' @return `list(text, base_old, base_new, fuzzy, counts, eol_changed)`: `base_old`/`base_new` are
#'   the LF views before and after (for the diff).
#' @noRd
apply_edits = function(text, edits, path = "file", replace_all = FALSE) {
  n = length(edits)
  if (!n) {
    gptr_abort("Edit tool input is invalid. edits must contain at least one replacement.",
               "invalid_argument", arg = "edits", expected = "at least one replacement")
  }
  pieces = strsplit(paste0(text, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  k = length(pieces)
  has_cr = grepl("\r$", pieces, perl = TRUE, useBytes = TRUE) & seq_len(k) < k
  lossy = !validUTF8(text)
  remark = function(x) if (lossy) x else utf8_mark(x)
  body = pieces
  body[has_cr] = sub("\r$", "", pieces[has_cr], perl = TRUE, useBytes = TRUE)
  body = remark(body)
  base = remark(paste(body, collapse = "\n"))
  eol = detect_eol(text)
  field = function(e, a, b) as_utf8(e[[a]] %||% e[[b]] %||% "")
  olds = normalize_lf(vapply(edits, field, "", "oldText", "old_text"))
  news = normalize_lf(vapply(edits, field, "", "newText", "new_text"))
  each_all = function(e) isTRUE(e$replaceAll %||% e$replace_all)
  all_ = isTRUE(replace_all) | vapply(edits, each_all, NA)
  for (i in seq_len(n)) {
    if (!nzchar(olds[i])) {
      edit_error("oldText must not be empty in %s.",
                 "edits[%d].oldText must not be empty in %s.", path, i, n)
    }
  }
  pos = lapply(olds, function(o) fixed_positions(base, o))
  space = base
  olds_space = olds
  fz_lines = NULL
  used_fuzzy = FALSE
  if (any(lengths(pos) == 0L) && !lossy) {
    fz_lines = fuzzy_normalize_lines(body)
    space = utf8_mark(paste(fz_lines, collapse = "\n"))
    in_space = function(o) if (length(fixed_positions(space, o))) o else fuzzy_normalize(o)
    olds_space = vapply(olds, in_space, "")
    pos = lapply(olds_space, function(o) fixed_positions(space, o))
    used_fuzzy = TRUE
  }
  fz_base = if (used_fuzzy) space else NULL
  starts = integer(0)
  lens = integer(0)
  repl = character(0)
  owner = integer(0)
  counts = integer(n)
  for (i in seq_len(n)) {
    p = pos[[i]]
    if (!length(p)) {
      edit_error(paste("Could not find the exact text in %s. The old text must match exactly",
                       "including all whitespace and newlines."),
                 paste("Could not find edits[%d] in %s. The oldText must match exactly",
                       "including all whitespace and newlines."), path, i, n)
    }
    if (!all_[i]) {
      occ = length(p)
      if (!lossy) {
        if (is.null(fz_base)) {
          fz_base = utf8_mark(paste(fuzzy_normalize_lines(body), collapse = "\n"))
        }
        occ = max(occ, length(fixed_positions(fz_base, fuzzy_normalize(olds[i]))))
      }
      if (occ > 1L) {
        msg = if (n == 1L) {
          paste0("Found ", occ, " occurrences of the text in ", path,
                 ". The text must be unique. Please provide more context to make it unique.")
        } else {
          paste0("Found ", occ, " occurrences of edits[", i - 1L, "] in ", path,
                 ". Each oldText must be unique. Please provide more context to make it unique.")
        }
        gptr_abort(msg, "invalid_argument", arg = "edits", expected = "a unique oldText")
      }
      p = p[1L]
    }
    counts[i] = length(p)
    starts = c(starts, p)
    lens = c(lens, rep(nchar(olds_space[i], type = "bytes"), length(p)))
    repl = c(repl, rep(news[i], length(p)))
    owner = c(owner, rep(i, length(p)))
  }
  o = order(starts)
  starts = starts[o]
  lens = lens[o]
  repl = repl[o]
  owner = owner[o]
  ov = which(starts[-1L] < (starts + lens)[-length(starts)])
  if (length(ov)) {
    gptr_abort(paste0("edits[", owner[ov[1L]] - 1L, "] and edits[", owner[ov[1L] + 1L] - 1L,
                      "] overlap in ", path,
                      ". Merge them into one edit or target disjoint regions."),
               "invalid_argument", arg = "edits", expected = "non-overlapping edits")
  }
  new_text = if (!used_fuzzy) {
    edit_splice_exact(text, body, has_cr, k, eol, starts, lens, repl)
  } else {
    edit_splice_fuzzy(body, fz_lines, has_cr, k, eol, starts, lens, repl)
  }
  new_text = remark(new_text)
  if (identical(new_text, text)) {
    msg = if (n == 1L) {
      paste0("No changes made to ", path, ". The replacement produced identical content. ",
             "This might indicate an issue with special characters or the text not existing ",
             "as expected.")
    } else {
      paste0("No changes made to ", path, ". The replacements produced identical content.")
    }
    gptr_abort(msg, "invalid_argument", arg = "edits", expected = "edits that change the file")
  }
  eol_changed = identical(eol, "\r\n") && any(grepl("\n", news, fixed = TRUE))
  list(text = new_text, base_old = base, base_new = normalize_lf(new_text), fuzzy = used_fuzzy,
       counts = counts, eol_changed = eol_changed)
}

#' Exact path: map offsets of the LF view to the original by adding one byte per CRLF before them,
#' then splice on the raw bytes; newText takes the file's line ending (Pi detectLineEnding())
#' @noRd
edit_splice_exact = function(text, body, has_cr, k, eol, starts, lens, repl) {
  nl_base = cumsum(nchar(body, type = "bytes") + 1L)[seq_len(k - 1L)] - 1L
  crs = cumsum(has_cr[seq_len(k - 1L)])
  shift = function(off) {
    j = findInterval(off, nl_base, left.open = TRUE)
    ifelse(j > 0L, crs[pmax(1L, j)], 0L)
  }
  o_start = starts + shift(starts)
  o_end = (starts + lens) + shift(starts + lens)
  repl_eol = if (eol == "\r\n") gsub("\n", "\r\n", repl, fixed = TRUE, useBytes = TRUE) else repl
  splice_bytes(text, o_start, o_end - o_start, repl_eol)
}

#' Fuzzy path (Pi applyReplacementsPreservingUnchangedLines()): lines carry their terminators,
#' touched line groups are rewritten from the fuzzy view, every other line keeps its original bytes
#' @noRd
edit_splice_fuzzy = function(body, fz_lines, has_cr, k, eol, starts, lens, repl) {
  term = ifelse(seq_len(k) < k, "\n", "")
  fz_with = paste0(fz_lines, term)
  orig_with = paste0(body, ifelse(has_cr, "\r\n", term))
  line_start = c(0, cumsum(nchar(fz_with, type = "bytes")))[seq_len(k)]
  s_line = findInterval(starts, line_start)
  e_line = findInterval(starts + lens - 1L, line_start)
  grp = cumsum(c(TRUE, s_line[-1L] > cummax(e_line)[-length(e_line)]))
  g_s = tapply(s_line, grp, min)
  g_e = tapply(e_line, grp, max)
  out = character(0)
  cur = 1L
  for (g in seq_along(g_s)) {
    if (g_s[g] > cur) out = c(out, orig_with[cur:(g_s[g] - 1L)])
    seg = paste(fz_with[g_s[g]:g_e[g]], collapse = "")
    sel = grp == g
    seg = splice_bytes(seg, starts[sel] - line_start[g_s[g]], lens[sel], repl[sel])
    if (eol == "\r\n") seg = gsub("\n", "\r\n", seg, fixed = TRUE, useBytes = TRUE)
    out = c(out, seg)
    cur = g_e[g] + 1L
  }
  if (cur <= k) out = c(out, orig_with[cur:k])
  paste(out, collapse = "")
}

#' Pi prepareEditArguments(): edits as a JSON string, a single object, a data frame or a list
#' @noRd
edit_normalize_args = function(edits) {
  if (is.character(edits) && length(edits) == 1L && !patch_is_envelope(edits)) {
    parsed = tryCatch(jsonlite::fromJSON(edits, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(parsed)) edits = parsed
  }
  if (is.data.frame(edits)) {
    edits = lapply(seq_len(nrow(edits)), function(i) as.list(edits[i, , drop = FALSE]))
  }
  single = is.list(edits) && !is.null(names(edits))
  if (single && !is.null(edits$oldText %||% edits$old_text)) edits = list(edits)
  if (!is.list(edits) || !length(edits) || !all(vapply(edits, is.list, NA))) {
    gptr_abort("Edit tool input is invalid. edits must contain at least one replacement.",
               "invalid_argument", arg = "edits", expected = "a list of list(oldText =, newText =)")
  }
  edits
}

#' Compute an edit without writing: the target, the new bytes, the apply_edits() result and the
#' decoding
#' @noRd
edit_compute = function(abs, path, edits, replace_all = FALSE) {
  p = fs_path(abs)
  code = if (!file.exists(p)) "ENOENT" else if (dir.exists(p)) "EISDIR" else NULL
  if (!is.null(code)) {
    gptr_abort(paste0("Could not edit file: ", path, ". Error code: ", code, "."),
               "invalid_argument", arg = "path", expected = "an existing file")
  }
  target = resolve_link_target(abs)
  if (file.access(fs_path(target), 2L) != 0L || file.access(fs_path(target), 4L) != 0L) {
    gptr_abort(paste0("Could not edit file: ", path, ". Error code: EACCES."), "invalid_argument",
               arg = "path", expected = "a readable and writable file")
  }
  b = read_raw(target)
  if (is_binary_raw(b) || (any(b == as.raw(0L)) && !nzchar(sniff_bom(b)))) {
    gptr_abort(paste0("Could not edit file: ", path, ". It is a binary file."), "invalid_argument",
               arg = "path", expected = "a text file")
  }
  d = decode_raw(b)
  text = if (d$lossy) {
    t = rawToChar(if (d$bom) b[-(1:3)] else b)
    Encoding(t) = "unknown"
    t
  } else {
    d$text
  }
  res = apply_edits(text, edits, path, replace_all = replace_all)
  bytes = if (d$lossy) {
    c(if (d$bom) bom_bytes[["UTF-8"]], charToRaw(res$text))
  } else {
    encode_text(res$text, d$encoding, d$bom)
  }
  list(target = target, bytes = bytes, res = res, dec = d)
}

#' Edit a file: the `edit` tool (contract section 7.10)
#'
#' @param path File path as given (used in messages).
#' @param edits A list of `list(oldText =, newText =)` (also `old_text`/`new_text`, per-edit
#'   `replaceAll`), a JSON string, a single object, or a chr(1) `*** Begin Patch` envelope.
#' @param replace_all Replace every occurrence of each oldText.
#' @return `list(message, diff = chr (at most 400 tokens), fuzzy = lgl(1), details = list(path,
#'   n_edits, fuzzy, diff (the full unified diff), document, deviated, reasons, encoding))`
#' @noRd
edit_file = function(path, edits, replace_all = FALSE) {
  check_string(path, "path")
  check_flag(replace_all, "replace_all")
  envelope = edit_envelope_of(edits)
  if (!is.null(envelope)) return(edit_from_patch(envelope))
  edits = edit_normalize_args(edits)
  abs = resolve_tool_path(path)
  cp = edit_compute(abs, path, edits, replace_all)
  write_bytes_keep_mode(cp$target, cp$bytes)
  res = cp$res
  view = function(x) {
    if (cp$dec$lossy) utf8_mark(iconv(x, "UTF-8", "UTF-8", sub = replacement_sub)) else x
  }
  enc = cp$dec$encoding
  reasons = c(if (res$fuzzy) "matched after whitespace, quote or dash normalisation",
              if (res$eol_changed) "line endings written as CRLF",
              if (!identical(enc, "UTF-8")) paste0("file re-encoded as ", enc),
              if (isTRUE(cp$dec$lossy)) "invalid UTF-8 bytes kept")
  list(message = paste0("Successfully replaced ", sum(res$counts), " block(s) in ", path, "."),
       diff = diff_lines(diff_split(view(res$base_old))$lines, diff_split(view(res$base_new))$lines,
                         context = 3L, max_tokens = 400L),
       fuzzy = res$fuzzy,
       details = list(path = cp$target, n_edits = length(edits), fuzzy = res$fuzzy,
                      diff = diff_unified(path, view(res$base_old), view(res$base_new)),
                      document = FALSE, deviated = length(reasons) > 0L, reasons = reasons,
                      encoding = enc))
}

#' Model-facing text of an edit: Pi's message, plus the reasons and the diff only when something
#' deviated from the literal request (contract sections 7.10 and 9.2)
#' @noRd
edit_result_text = function(ed) {
  if (!isTRUE(ed$details$deviated) || !length(ed$diff)) return(ed$message)
  reasons = paste0("[", paste(ed$details$reasons, collapse = "; "), "]")
  paste(c(ed$message, reasons, ed$diff), collapse = "\n")
}

#' Is `x` a pasted `*** Begin Patch` envelope (a string, or a one-element unnamed list of one)?
#' @noRd
patch_is_envelope = function(x) {
  if (is.list(x) && length(x) == 1L && is.null(names(x))) x = x[[1L]]
  is.character(x) && length(x) == 1L && !is.na(x) &&
    grepl("^\\s*\\*\\*\\* Begin Patch", x, perl = TRUE)
}

#' The patch envelope carried by an edit's arguments, or NULL: `edits` itself (a string, or a list
#' of one string), or the only edit's `newText` (or `oldText`) when the other text is empty, which
#' is how a model pastes an envelope through the direct tool's schema
#' @noRd
edit_envelope_of = function(edits) {
  if (patch_is_envelope(edits)) return(if (is.list(edits)) edits[[1L]] else edits)
  if (!is.list(edits) || length(edits) != 1L || !is.list(edits[[1L]])) return(NULL)
  e = edits[[1L]]
  pairs = list(c("newText", "oldText"), c("oldText", "newText"), c("new_text", "old_text"),
               c("old_text", "new_text"))
  for (p in pairs) {
    other = e[[p[2L]]]
    if (patch_is_envelope(e[[p[1L]]]) && (is.null(other) || identical(other, ""))) {
      return(e[[p[1L]]])
    }
  }
  NULL
}

#' The input of a nested `peter$edit()` call for the gate: a patch envelope travels as `patch`, with
#' an empty `edits` array, so the input validates against the edit schema
#' @noRd
edit_nested_input = function(input) {
  envelope = edit_envelope_of(input$edits)
  if (is.null(envelope)) return(input)
  input$edits = list()
  input$patch = envelope
  input
}

#' Parse a Codex-style patch envelope into file operations
#' @noRd
patch_parse = function(envelope) {
  lines = split_lines_count(normalize_lf(as_utf8(envelope)))
  marks = trimws(lines)
  bad = function(what) {
    gptr_abort(paste0("Invalid patch: ", what), "invalid_argument", arg = "edits",
               expected = "a *** Begin Patch envelope")
  }
  i = which(marks == "*** Begin Patch")[1L]
  if (is.na(i)) bad("missing '*** Begin Patch'.")
  j = which(marks == "*** End Patch")
  j = j[j > i][1L]
  if (is.na(j)) bad("missing '*** End Patch'.")
  body = if (j > i + 1L) lines[(i + 1L):(j - 1L)] else character()
  ops = list()
  cur = NULL
  for (ln in body) {
    header = regmatches(ln, regexec("^\\*\\*\\* (Add|Delete|Update) File: (.+)$", ln))[[1L]]
    if (length(header)) {
      if (!is.null(cur)) ops[[length(ops) + 1L]] = cur
      cur = list(op = tolower(header[2L]), path = trimws(header[3L]), content = character(),
                 move_to = NULL, hunks = list())
    } else if (startsWith(ln, "*** Move to: ") && identical(cur$op, "update")) {
      cur$move_to = trimws(substring(ln, 14L))
    } else if (startsWith(ln, "*** End of File")) {
      next
    } else if (identical(cur$op, "add")) {
      if (!startsWith(ln, "+")) {
        bad(paste0("a line of the added file ", cur$path, " does not start with '+'."))
      }
      cur$content = c(cur$content, substring(ln, 2L))
    } else if (identical(cur$op, "update")) {
      if (startsWith(ln, "@@")) {
        cur$hunks[[length(cur$hunks) + 1L]] = list(old = character(), new = character())
        next
      }
      if (!length(cur$hunks)) cur$hunks[[1L]] = list(old = character(), new = character())
      h = length(cur$hunks)
      tag = substr(ln, 1L, 1L)
      txt = substring(ln, 2L)
      if (tag != "+") cur$hunks[[h]]$old = c(cur$hunks[[h]]$old, txt)
      if (tag != "-") cur$hunks[[h]]$new = c(cur$hunks[[h]]$new, txt)
    } else if (nzchar(trimws(ln))) {
      bad(paste0("unexpected line '", substr(ln, 1L, 60L), "'."))
    }
  }
  if (!is.null(cur)) ops[[length(ops) + 1L]] = cur
  ops
}

#' File paths an envelope touches (for the risk of the edit tool)
#' @noRd
patch_paths = function(envelope) {
  ops = tryCatch(patch_parse(envelope), error = function(e) list())
  unique(c(vapply(ops, function(o) o$path, ""), unlist(lapply(ops, function(o) o$move_to))))
}

#' Apply a Codex-style patch envelope: `*** Add File`, `*** Update File` (with `*** Move to`), `***
#' Delete File`, `@@` hunks (contract section 7.10)
#'
#' Every operation is computed first; nothing is written unless all succeed.
#' @param envelope chr(1) text from `*** Begin Patch` to `*** End Patch`.
#' @param root Directory that relative paths are resolved against.
#' @return `list(files = chr (absolute paths written), message = chr(1), details = list(ops, files,
#'   diff))`
#' @noRd
patch_apply = function(envelope, root = project_root()) {
  check_string(envelope, "envelope")
  check_string(root, "root")
  ops = patch_parse(envelope)
  if (!length(ops)) {
    gptr_abort("Invalid patch: no file operations.", "invalid_argument", arg = "edits",
               expected = "a *** Begin Patch envelope")
  }
  resolve = function(p) resolve_tool_path(p, cwd = root)
  plan = lapply(ops, function(op) {
    abs = resolve(op$path)
    if (identical(op$op, "add")) {
      if (file.exists(fs_path(abs))) {
        gptr_abort(paste0("Invalid patch: the file to add already exists: ", op$path),
                   "invalid_argument", arg = "edits", expected = "a new file path")
      }
      bytes = encode_text(paste0(paste(op$content, collapse = "\n"), "\n"))
      return(list(op = op, abs = abs, bytes = bytes))
    }
    if (identical(op$op, "delete")) {
      if (!file.exists(fs_path(abs))) {
        gptr_abort(paste0("Could not delete file: ", op$path, ". Error code: ENOENT."),
                   "invalid_argument", arg = "edits", expected = "an existing file")
      }
      return(list(op = op, abs = abs))
    }
    edits = lapply(op$hunks, function(h) {
      if (!length(h$old)) {
        gptr_abort(paste0("Invalid patch: a hunk of ", op$path,
                          " has no context or removed lines."),
                   "invalid_argument", arg = "edits", expected = "hunks with context")
      }
      list(oldText = paste(h$old, collapse = "\n"), newText = paste(h$new, collapse = "\n"))
    })
    list(op = op, abs = abs, cp = edit_compute(abs, op$path, edits),
         move = if (is.null(op$move_to)) NULL else resolve(op$move_to))
  })
  diffs = character()
  tags = character()
  for (pl in plan) {
    if (identical(pl$op$op, "add")) {
      write_bytes_keep_mode(pl$abs, pl$bytes)
      tags = c(tags, paste0("A ", pl$op$path))
    } else if (identical(pl$op$op, "delete")) {
      file.remove(fs_path(pl$abs))
      tags = c(tags, paste0("D ", pl$op$path))
    } else {
      dest = pl$move %||% pl$cp$target
      write_bytes_keep_mode(dest, pl$cp$bytes)
      if (!is.null(pl$move) && !identical(pl$move, pl$cp$target)) file.remove(fs_path(pl$cp$target))
      diffs = c(diffs, diff_unified(pl$op$path, pl$cp$res$base_old, pl$cp$res$base_new))
      tags = c(tags, paste0("M ", pl$op$path, if (!is.null(pl$move)) paste0(" -> ", pl$op$move_to)))
    }
  }
  files = vapply(plan, function(pl) pl$move %||% pl$abs, "")
  head = paste0("Applied patch: ", length(plan), " file(s) changed.")
  list(files = files, message = paste(c(head, tags), collapse = "\n"),
       details = list(ops = tags, files = files, diff = diffs))
}

#' An edit given as a patch envelope, in edit_file()'s return shape (paths relative to getwd())
#' @noRd
edit_from_patch = function(envelope) {
  if (is.list(envelope)) envelope = envelope[[1L]]
  pa = patch_apply(envelope, root = getwd())
  list(message = pa$message, diff = character(), fuzzy = FALSE,
       details = list(path = pa$files[1L], n_edits = length(pa$files), fuzzy = FALSE,
                      diff = pa$details$diff, document = FALSE, deviated = FALSE,
                      reasons = character(), encoding = "UTF-8", files = pa$files))
}

#' The value of `peter$edit()` (contract section 5.10)
#' @noRd
new_gptr_patch = function(path, message, diff, n_edits, fuzzy) {
  structure(list(path = path, message = message, diff = as.character(diff),
                 n_edits = as.integer(n_edits), fuzzy = isTRUE(fuzzy)),
            class = "gptr_patch")
}

#' Print a gptr patch: the message, and the diff only when the fuzzy fallback was used
#'
#' @param x A `gptr_patch`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_patch = function(x, ...) {
  lines = x$message
  if (isTRUE(x$fuzzy) && length(x$diff)) lines = c(lines, x$diff)
  ns_print_lines(lines)
  invisible(x)
}
```

Regenerate `NAMESPACE` (adds `S3method(print,gptr_patch)`):

```bash
Rscript --vanilla -e 'devtools::document()'
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-edit")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 79 ]` with stringi installed (the NFKC test skips without it).

- [ ] **Step 5: Commit**

```bash
git add R/tool-edit.R tests/testthat/test-tool-edit.R NAMESPACE
git commit -m "feat(tools): add the edit engine with the fuzzy fallback and patch envelopes"
```

### Task 7: `grep`, `find` and `ls`

**Files:** Create: `R/tool-search.R`; Test: `tests/testthat/test-tool-search.R`; Modify: `NAMESPACE` (generated).

The functions behind `peter$grep()`, `peter$find()`, `peter$ls()` and the direct `grep`, `find`, `ls` tools of the `extended` preset (REQ-07, REQ-08; 04 §7.10, §9.2, §9.4). Ported from report 11 §5.5 (`proto/50-search.R`; identical (file, line) sets to ripgrep on 5 patterns, §2.5) and report 21 §2.1 (files read in batches with `readChar(useBytes = TRUE)`, never `readLines()` per file; a whole-file prefilter, fixed bytes or a `(?m)` PCRE, before splitting a file into lines; a NUL that truncates `readChar()` marks a binary file, ripgrep's rule), per-line PCRE with `(*UTF)(*UCP)`, early stop at the limit and radix sorting; Pi's texts from report 01 §3.6-3.8 (`file:line: text`, context lines `file-line- text` with `--` between blocks, `No matches found`, `[100 matches limit reached. Use limit=200 for more, or refine pattern]`, `No files found matching pattern`, `(empty directory)`, the 50 KB notice, long lines cut to 500 characters around the match). Report 11 §7.1 risk 3 is handled: PCRE match-limit warnings are captured and reported as "results may be incomplete". Files larger than 20 MB are skipped with a notice. Sorting (IC-71): `grep(output = "files" | "count", sort = "path" | "count" | "mtime")`; `find(sort = "path" | "mtime" | "size" | "relevance")`, where relevance ranks exact basename (or stem) > prefix > substring > subsequence, ties by path; `ls(sort = "name" | "mtime" | "size")`. UTF-8 BOM, UTF-16 and CP1252 files are decoded before matching; CRLF is matched as LF so `$` anchors work.

**Interfaces:**
- Consumes (P01): `as_utf8()`, `utf8_mark()`, checkers, `gptr_abort()`, `` `%||%` ``; Task 1: `ns_print_lines()`, `budget_head()`, `member_budget()`; Task 2: `fs_path()`, `resolve_tool_path()`, `walk_files()`, `glob_to_regex()`; Task 4: `read_raw()`, `sniff_bom()`, `decode_raw()`, `split_lines_count()`, `truncate_lines_head()`, `format_size()`, `tool_max_bytes`.
- Produces (04 §7.10, §5.10): `search_grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"), sort = c("path", "count", "mtime"))` -> `gptr_matches` (`file`, `line` int, `text`; attributes `truncated`, `limit`, plus `context` rows when asked) or, for `output = "files"`, `gptr_files`, for `"count"`, a df `file`, `n`; `search_find(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"), type = "file", limit = 1000L)` -> `gptr_files`; `search_ls(path = ".", sort = c("name", "mtime", "size"), long = FALSE)` -> `gptr_files`; `print.gptr_matches()`, `print.gptr_files()` (within the member budget, then a notice); internal for Task 10: `grep_tool_text(m)`, `find_tool_text(f)`, `ls_tool_text(f, limit)` (Pi's direct texts), `grep_default_limit` (100L), `find_default_limit` (1000L), `ls_default_limit` (500L).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-search.R` (oracle cases of report 11 §5.6 "find / ls / sort" and "grep", Pi's `tools.test.ts` cases of report 01 §5.9 for the grep limit and context texts and for `ls`, and a ripgrep oracle):

```r
# Tests for R/tool-search.R: grep, find, ls. Oracle cases from dev/research/11-r-file-tools.md
# section 5.6 (tests/test-tools.R, "find / ls / sort" and "grep") and
# dev/research/01-pi-builtin-tools.md section 5.9 (Pi's tools.test.ts cases for grep limit/context
# and ls).

put = function(root, rel, bytes) {
  p = file.path(root, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.character(bytes)) charToRaw(bytes) else bytes, p)
  invisible(p)
}

grep_fixture = function() {
  td = withr::local_tempdir(.local_envir = parent.frame())
  put(td, "a.R", "alpha = 1\nbeta = 2\n# TODO fix\ngamma = alpha + beta\n")
  put(td, "b.txt", paste0("Alpha\r\nx.y\r\n\u00e9t\u00e9\r\n"))
  put(td, "bin.dat", as.raw(c(97, 108, 112, 104, 97, 0, 1)))
  put(td, "sub/c.R", paste0(sprintf("line %d", 1:12), "\n", collapse = ""))
  put(td, ".gitignore", "ignored.R\n")
  put(td, "ignored.R", "alpha\n")
  put(td, "long.js", paste0(strrep("x", 3000), "needle", strrep("y", 3000), "\n"))
  td
}

lines_of = function(text) {
  l = strsplit(text, "\n", fixed = TRUE)[[1L]]
  l[nzchar(l) & !startsWith(l, "[")]
}

test_that("grep sorts by path and skips binary and .gitignore'd files", {
  td = grep_fixture()
  m = search_grep("alpha", td)
  expect_s3_class(m, "gptr_matches")
  expect_identical(grep_tool_text(m), "a.R:1: alpha = 1\na.R:4: gamma = alpha + beta")
  expect_identical(names(as.data.frame(m)), c("file", "line", "text"))
  expect_identical(m$line, c(1L, 4L))
})

test_that("grep options: ignore case, literal, CRLF anchors, UTF-8 and PCRE classes", {
  td = grep_fixture()
  txt = function(...) grep_tool_text(search_grep(...))
  expect_identical(txt("alpha", td, ignore_case = TRUE),
                   "a.R:1: alpha = 1\na.R:4: gamma = alpha + beta\nb.txt:1: Alpha")
  expect_identical(txt("x.y", td, fixed = TRUE), "b.txt:2: x.y")
  expect_identical(txt("X.Y", td, fixed = TRUE, ignore_case = TRUE), "b.txt:2: x.y")
  expect_identical(txt("y$", td, glob = "*.txt"), "b.txt:2: x.y")
  expect_identical(txt("\u00e9t", td), "b.txt:3: \u00e9t\u00e9")
  expect_identical(txt("\\x{E9}t", td), "b.txt:3: \u00e9t\u00e9")
  expect_identical(txt("^\\w+$", td, glob = "*.txt"), "b.txt:1: Alpha\nb.txt:3: \u00e9t\u00e9")
  expect_identical(txt("beta", file.path(td, "a.R")),
                   "a.R:2: beta = 2\na.R:4: gamma = alpha + beta")
  expect_identical(txt("zzz", td), "No matches found")
})

test_that("grep decodes UTF-8 BOM, UTF-16 and CP1252 files before matching", {
  td = withr::local_tempdir()
  put(td, "bom.R", c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x\u00e9yz = 1\n")))
  put(td, "u16.txt", c(as.raw(c(0xFF, 0xFE)), iconv("u16 needle\r\n", "UTF-8", "UTF-16LE",
                                                    toRaw = TRUE)[[1L]]))
  put(td, "legacy.R", as.raw(c(charToRaw("# caf"), 0xE9, charToRaw(" legacyword\n"))))
  expect_identical(grep_tool_text(search_grep("^x\u00e9yz", td)), "bom.R:1: x\u00e9yz = 1")
  expect_identical(grep_tool_text(search_grep("needle$", td)), "u16.txt:1: u16 needle")
  expect_identical(grep_tool_text(search_grep("\u00e9 legacy", td)),
                   "legacy.R:1: # caf\u00e9 legacyword")
})

test_that("grep context merges overlapping windows and separates blocks with --", {
  td = grep_fixture()
  expect_identical(grep_tool_text(search_grep("line (3|5|12)$", td, context = 1L)),
                   paste(c("sub/c.R-2- line 2", "sub/c.R:3: line 3", "sub/c.R-4- line 4",
                           "sub/c.R:5: line 5", "sub/c.R-6- line 6", "--", "sub/c.R-11- line 11",
                           "sub/c.R:12: line 12"), collapse = "\n"))
})

test_that("grep reproduces Pi's limit and context texts (tools.test.ts)", {
  td = withr::local_tempdir()
  p = put(td, "context.txt", paste(c("before", "match one", "after", "middle", "match two",
                                     "after two"), collapse = "\n"))
  expect_identical(grep_tool_text(search_grep("match", p, limit = 1L, context = 1L)),
                   paste0("context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after",
                          "\n\n[1 matches limit reached. Use limit=2 for more, or refine pattern]"))
  expect_identical(grep_tool_text(search_grep("match", p, context = 1L)),
                   paste0("context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after",
                          "\ncontext.txt-4- middle\ncontext.txt:5: match two",
                          "\ncontext.txt-6- after two"))
})

test_that("grep notices: limit, long lines centred on the match, regex errors, missing paths", {
  td = grep_fixture()
  expect_match(grep_tool_text(search_grep("line", td, limit = 3L)),
               "[3 matches limit reached. Use limit=6 for more, or refine pattern]", fixed = TRUE)
  long = grep_tool_text(search_grep("needle", td))
  expect_match(long, "needle", fixed = TRUE)
  expect_match(long, "Some lines truncated to 500 chars. Use read tool to see full lines",
               fixed = TRUE)
  expect_error(search_grep("a(", td), "regex parse error", class = "gptr_error_invalid_argument")
  expect_error(search_grep("x", file.path(td, "nope")), "^Path not found: ")
  expect_identical(grep_tool_text(search_grep("--pre=/bin/sh", td)), "No matches found")
})

test_that("grep output files and count, sorted by path or by match count", {
  td = grep_fixture()
  f = search_grep("alpha|line", td, output = "files")
  expect_s3_class(f, "gptr_files")
  expect_identical(f$path, c("a.R", "sub/c.R"))
  n = search_grep("alpha|line", td, output = "count")
  expect_identical(n$file, c("a.R", "sub/c.R"))
  expect_identical(n$n, c(2L, 12L))
  expect_identical(search_grep("alpha|line", td, output = "files", sort = "count")$path,
                   c("sub/c.R", "a.R"))
})

test_that("grep agrees with ripgrep on (file, line) pairs", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("rg")), "ripgrep is not installed")
  td = grep_fixture()
  dir.create(file.path(td, ".git"))
  pairs = function(p) {
    out = system2("rg", c("--line-number", "--no-heading", "--color=never", "--hidden", "--",
                          shQuote(p), "."),
                  stdout = TRUE, stderr = FALSE)
    out = out[!grepl("^\\./\\.git/", out)]
    sort(sub("^\\./", "", sub("^([^:]+:[0-9]+):.*$", "\\1", out)), method = "radix")
  }
  withr::local_dir(td)
  for (p in c("alpha", "line [0-9]+", "TODO")) {
    m = search_grep(p, ".", limit = 10000L)
    expect_identical(sort(paste0(m$file, ":", m$line), method = "radix"), pairs(p), label = p)
  }
})

find_fixture = function() {
  td = withr::local_tempdir(.local_envir = parent.frame())
  for (f in c("f1.R", "f10.R", "f2.R", "B.R", "a.R", "sub/x.R", "sub/y.Rmd", ".hid.R", "test.R",
              "tests/testthat/test-find.R",
              "README.md")) put(td, f, "x\n")
  put(td, "big.R", strrep("x", 5000))
  Sys.setFileTime(file.path(td, "f2.R"), Sys.time() + 100)
  td
}

test_that("find matches basenames at any depth, sorts by path and marks directories", {
  td = find_fixture()
  expect_identical(search_find("*.R", td)$path,
                   c(".hid.R", "a.R", "B.R", "big.R", "f1.R", "f10.R", "f2.R", "sub/x.R", "test.R",
                     "tests/testthat/test-find.R"))
  expect_identical(search_find("sub/*", td)$path, c("sub/x.R", "sub/y.Rmd"))
  expect_identical(search_find("sub", td, type = "dir")$path, "sub")
  expect_identical(find_tool_text(search_find("sub", td, type = "any")), "sub/")
  expect_identical(search_find("FOO", td)$path, character())
  expect_identical(find_tool_text(search_find("*.zzz", td)), "No files found matching pattern")
})

test_that("find sorts by mtime (newest first), size (largest first) and relevance (IC-71)", {
  td = find_fixture()
  expect_identical(search_find("*.R", td, sort = "mtime")$path[1L], "f2.R")
  expect_identical(search_find("*", td, sort = "size")$path[1L], "big.R")
  expect_identical(search_find("tst", td, sort = "relevance")$path[1L], "test.R")
  expect_identical(search_find("test", td, sort = "relevance")$path[1:2],
                   c("test.R", "tests/testthat/test-find.R"))
})

test_that("find applies Pi's limit notice", {
  td = find_fixture()
  f = search_find("*.R", td, limit = 3L)
  expect_true(attr(f, "truncated"))
  expect_match(find_tool_text(f),
               "[3 results limit reached. Use limit=6 for more, or refine pattern]", fixed = TRUE)
  expect_error(search_find("*", file.path(td, "nope")), "^Path not found: ")
})

test_that("ls lists entries case-insensitively with dotfiles and '/' after directories (Pi)", {
  td = withr::local_tempdir()
  for (f in c(".hidden-file", "Zeta.txt", "alpha.txt", "_under.R", "beta.R")) put(td, f, "")
  dir.create(file.path(td, ".hidden-dir"))
  dir.create(file.path(td, "Sub"))
  l = search_ls(td)
  expect_s3_class(l, "gptr_files")
  expect_identical(strsplit(ls_tool_text(l), "\n")[[1L]],
                   c(".hidden-dir/", ".hidden-file", "_under.R", "alpha.txt", "beta.R", "Sub/",
                     "Zeta.txt"))
  expect_match(ls_tool_text(l, limit = 2L), "\n\n[2 entries limit reached. Use limit=4 for more]",
               fixed = TRUE)
  e = file.path(td, "empty")
  dir.create(e)
  expect_identical(ls_tool_text(search_ls(e)), "(empty directory)")
  expect_error(search_ls(file.path(td, "nope")), "^Path not found: ")
  expect_error(search_ls(file.path(td, "beta.R")), "^Not a directory: ")
})

test_that("prints of matches and files stay within the member budget with a notice", {
  td = withr::local_tempdir()
  put(td, "many.txt", paste0("hit ", strrep("w", 80), " ", 1:2000, "\n", collapse = ""))
  m = search_grep("hit", td, limit = 2000L)
  out = utils::capture.output(print(m))
  expect_lte(est_tokens(paste(out, collapse = "\n"), "r_output"), 1500 + 40)
  expect_match(out[length(out)], "more lines not printed", fixed = TRUE)
  f = search_find("*", td)
  expect_identical(utils::capture.output(print(f)), "many.txt")
  l = search_ls(td, long = TRUE)
  expect_match(utils::capture.output(print(l)),
               "^ +[0-9.]+KB  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  many\\.txt$")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-search")'
```

Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "search_grep"` (or `"grep_tool_text"`, `"search_find"`, `"search_ls"`, `"ls_tool_text"`).

- [ ] **Step 3: Write the implementation**

Create `R/tool-search.R`:

```r
# tool-search.R -- `peter$grep()`, `peter$find()`, `peter$ls()` and the direct `grep`, `find`, `ls`
# tools of the extended preset (P10): batched readChar() reads, a whole-file prefilter (fixed bytes
# or `(?m)` PCRE), per-line PCRE with `(*UTF)(*UCP)`, early stop at the limit, radix sorting
# (REQ-08: path, mtime, size, count, relevance), Pi's output texts and notices, and prints within
# the member budget. Ported from dev/research/11-r-file-tools.md section 5.5 (proto/50-search.R;
# identical (file, line) sets to ripgrep on 5 patterns, section 2.5) with
# dev/research/21-rcpp-hot-paths.md section 2.1 (prefilter before splitting, never readLines() per
# file) and dev/research/01-pi-builtin-tools.md sections 3.6-3.8 (Pi's texts). Report 11 section 7.1
# risk 3: PCRE match-limit warnings are captured and reported.

grep_default_limit = 100L
find_default_limit = 1000L
ls_default_limit = 500L
grep_max_line = 500L
grep_max_file = 20 * 1024^2

#' Batch reader: UTF-8 texts with LF line endings, NA for binary files (a NUL truncates readChar(),
#' so `nchar < size` detects binary files anywhere in the file, ripgrep's rule)
#' @noRd
search_read_texts = function(files, sizes) {
  txt = vapply(seq_along(files), function(k) {
    if (sizes[k] <= 0) return("")
    x = tryCatch(suppressWarnings(readChar(fs_path(files[k]), sizes[k], useBytes = TRUE)),
                 error = function(e) character())
    if (!length(x) || nchar(x, "bytes") < sizes[k]) NA_character_ else x
  }, "")
  for (k in which(is.na(txt))) {
    head = tryCatch(read_raw(files[k], n = min(4, sizes[k])), error = function(e) raw(0))
    bom = sniff_bom(head)
    if (nzchar(bom) && bom != "UTF-8") {
      txt[k] = tryCatch(decode_raw(read_raw(files[k]))$text, error = function(e) NA_character_)
    }
  }
  ok = !is.na(txt)
  bom8 = which(ok & grepl("^\xef\xbb\xbf", txt, perl = TRUE, useBytes = TRUE))
  if (length(bom8)) txt[bom8] = sub("^\xef\xbb\xbf", "", txt[bom8], perl = TRUE, useBytes = TRUE)
  for (k in which(ok & !validUTF8(txt))) txt[k] = decode_raw(charToRaw(txt[k]))$text
  cr = which(ok & grepl("\r", txt, fixed = TRUE, useBytes = TRUE))
  if (length(cr)) txt[cr] = gsub("\r\n", "\n", txt[cr], fixed = TRUE, useBytes = TRUE)
  utf8_mark(txt)
}

#' Matcher, prefilter and locator of a pattern; `state$incomplete` records PCRE match-limit warnings
#' @noRd
grep_prepare = function(pattern, fixed = FALSE, ignore_case = FALSE) {
  state = new.env(parent = emptyenv())
  state$incomplete = FALSE
  quiet = function(expr_fun) {
    withCallingHandlers(expr_fun(), warning = function(w) {
      state$incomplete = TRUE
      invokeRestart("muffleWarning")
    })
  }
  if (isTRUE(fixed) && !isTRUE(ignore_case)) {
    matcher = function(x) grepl(pattern, x, fixed = TRUE, useBytes = TRUE)
    return(list(matcher = matcher, prefilter = matcher, state = state,
                locator = function(x) as.integer(regexpr(pattern, x, fixed = TRUE))))
  }
  rx = pattern
  if (isTRUE(fixed)) rx = paste0("\\Q", gsub("\\E", "\\E\\\\E\\Q", pattern, fixed = TRUE), "\\E")
  utf = if (grepl("^\\(\\*UTF", rx)) "" else "(*UTF)(*UCP)"
  seen = new.env(parent = emptyenv())
  on_warning = function(w) {
    seen$warning = conditionMessage(w)
    invokeRestart("muffleWarning")
  }
  compile = function() {
    withCallingHandlers(grepl(paste0(utf, rx), "", perl = TRUE), warning = on_warning)
  }
  res = tryCatch(compile(), error = function(e) e)
  if (inherits(res, "error")) {
    why = seen$warning %||% conditionMessage(res)
    why = trimws(sub("^PCRE pattern compilation error\\s*", "", why))
    gptr_abort(paste0("regex parse error: ", gsub("\\s+", " ", why), " (pattern: ", pattern, ")"),
               "invalid_argument", arg = "pattern",
               expected = "a valid Perl-compatible regular expression")
  }
  ic = isTRUE(ignore_case)
  full = paste0(utf, rx)
  matcher = function(x) quiet(function() grepl(full, x, perl = TRUE, ignore.case = ic))
  unsafe = grepl("\\\\[AzZG]|^\\(\\*|\\(\\?[a-zA-Z]*s", rx)
  prefilter = if (unsafe) {
    function(x) rep(TRUE, length(x))
  } else {
    pre = paste0(utf, "(?m)", rx)
    function(x) quiet(function() grepl(pre, x, perl = TRUE, ignore.case = ic))
  }
  list(matcher = matcher, prefilter = prefilter, state = state,
       locator = function(x) as.integer(regexpr(full, x, perl = TRUE, ignore.case = ic)))
}

#' Engine: data.frame(file, abs, line, text) of up to `limit` matching lines, files in the given
#' order, in batches of at most 256 files or 4 MB (early stop at the limit)
#' @noRd
grep_engine = function(files, labels, eng, limit, sizes, batch_files = 256L,
                       batch_bytes = 4 * 1024^2) {
  sizes[is.na(sizes)] = 0
  batch = cummax(pmax(cumsum(sizes) %/% batch_bytes, (seq_along(files) - 1L) %/% batch_files))
  res = list()
  n = 0L
  n_bin = 0L
  for (bi in unique(batch)) {
    idx = which(batch == bi)
    texts = search_read_texts(files[idx], sizes[idx])
    bin = is.na(texts)
    n_bin = n_bin + sum(bin & sizes[idx] > 0)
    idx = idx[!bin]
    texts = texts[!bin]
    if (!length(idx)) next
    cand = eng$prefilter(texts)
    idx = idx[cand]
    texts = texts[cand]
    if (!length(idx)) next
    pieces = strsplit(texts, "\n", fixed = TRUE, useBytes = TRUE)
    lines = utf8_mark(unlist(pieces, use.names = FALSE))
    fid = rep(idx, lengths(pieces))
    lno = sequence(lengths(pieces))
    hit = which(eng$matcher(lines))
    if (!length(hit)) next
    take = hit[seq_len(min(length(hit), limit - n))]
    res[[length(res) + 1L]] = data.frame(file = labels[fid[take]], abs = files[fid[take]],
                                         line = lno[take], text = lines[take],
                                         stringsAsFactors = FALSE)
    n = n + length(take)
    if (n >= limit) break
  }
  out = if (length(res)) {
    do.call(rbind, res)
  } else {
    data.frame(file = character(), abs = character(), line = integer(), text = character(),
               stringsAsFactors = FALSE)
  }
  attr(out, "limit_reached") = n >= limit
  attr(out, "binary_skipped") = n_bin
  out
}

#' Candidate files of a search root: the walker, a glob filter (comma list, `!` excludes), the 20 MB
#' cap and the file order (path, or mtime newest first)
#' @noRd
grep_candidates = function(root, glob = NULL, sort = "path") {
  if (!dir.exists(fs_path(root))) {
    return(list(files = root, labels = basename(root), sizes = file.size(fs_path(root)),
                skipped_big = 0L, mtime = file.mtime(fs_path(root))))
  }
  w = walk_files(root, type = "file", hidden = TRUE)
  if (!is.null(glob) && nzchar(glob)) {
    gl = trimws(strsplit(glob, ",(?![^{]*})", perl = TRUE)[[1L]])
    gl = gl[nzchar(gl)]
    inc = gl[!startsWith(gl, "!")]
    exc = substring(gl[startsWith(gl, "!")], 2L)
    keep = if (length(inc)) {
      Reduce(`|`, lapply(inc, function(g) grepl(glob_to_regex(g), w$path, perl = TRUE)))
    } else {
      rep(TRUE, nrow(w))
    }
    for (g in exc) keep = keep & !grepl(glob_to_regex(g), w$path, perl = TRUE)
    w = w[keep, , drop = FALSE]
  }
  big = !is.na(w$size) & w$size > grep_max_file
  w = w[!big, , drop = FALSE]
  if (identical(sort, "mtime")) {
    w = w[order(-as.numeric(w$mtime), tolower(w$path), w$path, method = "radix"), , drop = FALSE]
  }
  list(files = file.path(attr(w, "root"), w$path), labels = w$path, sizes = w$size,
       skipped_big = sum(big), mtime = w$mtime)
}

#' Search file contents: the function behind `peter$grep()` and the direct `grep` tool (contract
#' 7.10)
#'
#' @param pattern PCRE pattern, or a literal string with `fixed = TRUE`.
#' @param path Directory or file to search.
#' @param glob Glob filter of file paths (comma-separated; `!glob` excludes).
#' @param ignore_case,fixed Case-insensitive; literal pattern.
#' @param context Lines shown before and after each match (merged blocks, `--` separators).
#' @param limit Maximum matching lines (`content`) or files (`files`, `count`).
#' @param output `"content"`, `"files"` or `"count"`.
#' @param sort File order for `files` and `count`: `"path"`, `"count"` (most matches first) or
#'   `"mtime"`.
#' @return `gptr_matches` (`file`, `line`, `text`), `gptr_files` (`output = "files"`) or a data
#'   frame `file`, `n` (`output = "count"`); attributes `truncated`, `limit`, `root`, `skipped_big`,
#'   `binary_skipped`, `incomplete`.
#' @noRd
search_grep = function(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE,
                       context = 0L, limit = 100L, output = c("content", "files", "count"),
                       sort = c("path", "count", "mtime")) {
  check_string(pattern, "pattern")
  check_string(path, "path")
  check_string(glob, "glob", null = TRUE, empty = TRUE)
  check_flag(ignore_case, "ignore_case")
  check_flag(fixed, "fixed")
  context = check_number(context, "context", min = 0, int = TRUE)
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  output = check_choice(output, c("content", "files", "count"), "output")
  sort = check_choice(sort, c("path", "count", "mtime"), "sort")
  root = resolve_tool_path(path)
  if (!file.exists(fs_path(root))) {
    gptr_abort(paste0("Path not found: ", root), "invalid_argument", arg = "path",
               expected = "an existing file or directory")
  }
  eng = grep_prepare(as_utf8(pattern), fixed = fixed, ignore_case = ignore_case)
  content = identical(output, "content")
  cand = grep_candidates(root, glob, sort = if (content) "path" else sort)
  m = grep_engine(cand$files, cand$labels, eng, if (content) limit else .Machine$integer.max,
                  sizes = cand$sizes)
  common = list(root = root, skipped_big = cand$skipped_big,
                binary_skipped = attr(m, "binary_skipped"),
                incomplete = isTRUE(eng$state$incomplete), limit = limit)
  if (content) {
    ctx_rows = if (context > 0L && nrow(m)) grep_context_rows(m, context) else NULL
    out = data.frame(file = m$file, line = as.integer(m$line), text = m$text,
                     stringsAsFactors = FALSE)
    head = list(out, class = c("gptr_matches", "data.frame"),
                truncated = isTRUE(attr(m, "limit_reached")), context = ctx_rows,
                locator = eng$locator)
    return(do.call(structure, c(head, common)))
  }
  counts = table(factor(m$file, levels = unique(m$file)))
  df = data.frame(file = names(counts), n = as.integer(counts), stringsAsFactors = FALSE)
  if (identical(sort, "count")) {
    df = df[order(-df$n, tolower(df$file), df$file, method = "radix"), , drop = FALSE]
  }
  truncated = nrow(df) > limit
  df = utils::head(df, limit)
  rownames(df) = NULL
  if (identical(output, "count")) {
    return(do.call(structure, c(list(df, truncated = truncated), common)))
  }
  hit = match(df$file, cand$labels)
  files = data.frame(path = df$file, size = as.numeric(cand$sizes[hit]), mtime = cand$mtime[hit],
                     type = rep("file", nrow(df)), stringsAsFactors = FALSE)
  head = list(files, class = c("gptr_files", "data.frame"), truncated = truncated)
  do.call(structure, c(head, common))
}

#' Context lines around matches (the matching lines themselves excluded)
#' @noRd
grep_context_rows = function(m, context) {
  rows = list()
  for (f in unique(m$file)) {
    mm = m[m$file == f, , drop = FALSE]
    txt = search_read_texts(mm$abs[1L], file.size(fs_path(mm$abs[1L])))
    lines = if (is.na(txt)) character() else split_lines_count(txt)
    around = function(h) max(1L, h - context):min(length(lines), h + context)
    want = sort(unique(unlist(lapply(mm$line, around))))
    want = setdiff(want, mm$line)
    if (length(want)) {
      rows[[length(rows) + 1L]] = data.frame(file = f, line = as.integer(want), text = lines[want],
                                             stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

#' Cap long lines at 500 characters, keeping a window around the first match visible (report 11)
#' @noRd
grep_cap_lines = function(x, locator = NULL, max_chars = grep_max_line) {
  n = nchar(x, type = "chars", allowNA = TRUE)
  long = !is.na(n) & n > max_chars
  if (!any(long)) return(structure(x, truncated = long))
  start = rep(1L, length(x))
  if (is.function(locator)) {
    ctr = pmax(0L, locator(x[long]) - 1L)
    start[long] = pmax(1L, pmin(ctr - max_chars %/% 5L, n[long] - max_chars + 1L))
  }
  x[long] = paste0(ifelse(start[long] > 1L, "...", ""),
                   substr(x[long], start[long], start[long] + max_chars - 1L), "... [truncated]")
  structure(utf8_mark(x), truncated = long)
}

#' Pi-format lines of matches: `file:N: text`, context `file-N- text`, merged blocks separated by
#' `--`
#' @noRd
grep_format_lines = function(m) {
  if (!nrow(m)) return(list(lines = character(), truncated = FALSE))
  ctx = attr(m, "context")
  all = data.frame(file = m$file, line = m$line, text = m$text, match = TRUE,
                   stringsAsFactors = FALSE)
  if (!is.null(ctx) && nrow(ctx)) {
    all = rbind(all, data.frame(file = ctx$file, line = ctx$line, text = ctx$text, match = FALSE,
                                stringsAsFactors = FALSE))
  }
  first = match(all$file, unique(m$file))
  all = all[order(first, all$line, method = "radix"), , drop = FALSE]
  t = grep_cap_lines(all$text, attr(m, "locator"))
  body = ifelse(all$match, sprintf("%s:%d: %s", all$file, all$line, t),
                sprintf("%s-%d- %s", all$file, all$line, t))
  if (!is.null(ctx) && nrow(ctx)) {
    gap = c(FALSE, (all$file[-1L] != all$file[-nrow(all)]) | (diff(all$line) > 1L))
    body = as.vector(rbind(ifelse(gap, "--", NA_character_), body))
    body = body[!is.na(body)]
  }
  list(lines = utf8_mark(body), truncated = any(attr(t, "truncated")))
}

#' Head lines within the 50 KB byte limit (Pi truncateHead without a line limit)
#' @noRd
head_bytes = function(lines, max_bytes = tool_max_bytes) {
  tr = truncate_lines_head(lines, max_lines = .Machine$integer.max, max_bytes = max_bytes)
  list(lines = tr$lines, truncated = tr$truncated)
}

#' "text\n\n[note. note]" (Pi's notice form)
#' @noRd
with_notices = function(text, notes) {
  if (!length(notes)) return(text)
  paste0(text, "\n\n[", paste(notes, collapse = ". "), "]")
}

#' Direct `grep` tool text (Pi's format and notices, report 11's extra notices)
#' @noRd
grep_tool_text = function(m) {
  if (!nrow(m)) return("No matches found")
  fm = grep_format_lines(m)
  tr = head_bytes(fm$lines)
  limit = attr(m, "limit")
  notes = c(
    if (isTRUE(attr(m, "truncated"))) {
      paste0(limit, " matches limit reached. Use limit=", limit * 2L,
             " for more, or refine pattern")
    },
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached"),
    if (fm$truncated) {
      paste0("Some lines truncated to ", grep_max_line, " chars. Use read tool to see full lines")
    },
    if (isTRUE(attr(m, "skipped_big") > 0L)) {
      paste0(attr(m, "skipped_big"), " file(s) larger than 20MB skipped")
    },
    if (isTRUE(attr(m, "incomplete"))) {
      "The pattern was too expensive on some lines; results may be incomplete"
    }
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' Relevance classes of a name query (IC-71): 1 exact basename, 2 prefix, 3 substring, 4
#' subsequence, NA no match; glob characters are ignored
#' @noRd
find_relevance = function(query, paths) {
  q = tolower(gsub("[*?]", "", query))
  base = tolower(basename(paths))
  stem = tools::file_path_sans_ext(base)
  cls = rep(NA_integer_, length(paths))
  if (!nzchar(q)) return(rep(4L, length(paths)))
  cls[base == q | stem == q] = 1L
  cls[is.na(cls) & startsWith(base, q)] = 2L
  cls[is.na(cls) & grepl(q, base, fixed = TRUE)] = 3L
  chars = strsplit(q, "", fixed = TRUE)[[1L]]
  rx = paste(gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", chars, perl = TRUE), collapse = ".*")
  cls[is.na(cls) & grepl(rx, base, perl = TRUE)] = 4L
  cls
}

#' Find files by glob: the function behind `peter$find()` and the direct `find` tool (contract 7.10)
#'
#' @param pattern Glob (fd semantics, smart case) or, with `sort = "relevance"`, a name query.
#' @param path Directory to search.
#' @param sort `"path"`, `"mtime"` (newest first), `"size"` (largest first) or `"relevance"` (exact
#'   basename > prefix > substring > subsequence, ties by path).
#' @param type `"file"`, `"dir"` or `"any"`.
#' @param limit Maximum rows.
#' @return `gptr_files`: `path` (relative to the search root), `size`, `mtime`, `type`; attributes
#'   `root`, `truncated`, `limit`.
#' @noRd
search_find = function(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"),
                       type = "file", limit = 1000L) {
  check_string(pattern, "pattern")
  check_string(path, "path")
  sort = check_choice(sort, c("path", "mtime", "size", "relevance"), "sort")
  type = check_choice(type, c("file", "dir", "any"), "type")
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  root = resolve_tool_path(path)
  if (!dir.exists(fs_path(root))) {
    gptr_abort(paste0("Path not found: ", root), "invalid_argument", arg = "path",
               expected = "an existing directory")
  }
  w = walk_files(root, type = type, hidden = TRUE)
  pattern = as_utf8(pattern)
  if (identical(sort, "relevance")) {
    cls = find_relevance(pattern, w$path)
    keep = !is.na(cls)
    w = w[keep, , drop = FALSE]
    cls = cls[keep]
    w = w[order(cls, tolower(w$path), w$path, method = "radix"), , drop = FALSE]
  } else {
    if (!(pattern %in% c("**", "*", "**/*"))) {
      ic = !grepl("[[:upper:]]", pattern)
      w = w[grepl(glob_to_regex(pattern), w$path, perl = TRUE, ignore.case = ic), , drop = FALSE]
    }
    ord = switch(sort,
                 path = order(tolower(w$path), w$path, method = "radix"),
                 mtime = order(-as.numeric(w$mtime), tolower(w$path), w$path, method = "radix"),
                 size = order(-w$size, tolower(w$path), w$path, method = "radix", na.last = TRUE))
    w = w[ord, , drop = FALSE]
  }
  truncated = nrow(w) > limit
  w = utils::head(w, limit)
  rownames(w) = NULL
  structure(w, class = c("gptr_files", "data.frame"), root = root, truncated = truncated,
            limit = limit)
}

#' Direct `find` tool text (Pi's format: relative paths, "/" after directories, notices)
#' @noRd
find_tool_text = function(f) {
  if (!nrow(f)) return("No files found matching pattern")
  tr = head_bytes(paste0(f$path, ifelse(f$type == "dir", "/", "")))
  limit = attr(f, "limit")
  notes = c(
    if (isTRUE(attr(f, "truncated"))) {
      paste0(limit, " results limit reached. Use limit=", limit * 2L,
             " for more, or refine pattern")
    },
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached")
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' List a directory: the function behind `peter$ls()` and the direct `ls` tool (contract 7.10)
#'
#' @param path Directory to list.
#' @param sort `"name"` (case-insensitive, radix), `"mtime"` (newest first) or `"size"` (largest
#'   first).
#' @param long Print size and modification time.
#' @return `gptr_files` of the entries (dot-files included; entries that cannot be stat-ed dropped,
#'   as Pi).
#' @noRd
search_ls = function(path = ".", sort = c("name", "mtime", "size"), long = FALSE) {
  check_string(path, "path")
  sort = check_choice(sort, c("name", "mtime", "size"), "sort")
  check_flag(long, "long")
  dir = resolve_tool_path(path)
  p = fs_path(dir)
  if (!file.exists(p)) {
    gptr_abort(paste0("Path not found: ", dir), "invalid_argument", arg = "path",
               expected = "an existing directory")
  }
  if (!dir.exists(p)) {
    gptr_abort(paste0("Not a directory: ", dir), "invalid_argument", arg = "path",
               expected = "a directory")
  }
  nm = as_utf8(list.files(p, all.files = TRUE, no.. = TRUE))
  full = file.path(dir, nm)
  fi = file.info(fs_path(full), extra_cols = FALSE)
  lnk = Sys.readlink(fs_path(full))
  is_dir = fi$isdir %in% TRUE
  kind = ifelse(!is.na(lnk) & nzchar(lnk), "link", ifelse(is_dir, "dir", "file"))
  df = data.frame(path = nm, size = ifelse(is_dir, NA_real_, as.numeric(fi$size)), mtime = fi$mtime,
                  type = kind, stringsAsFactors = FALSE)
  keep = !is.na(fi$isdir)
  df = df[keep, , drop = FALSE]
  slash = is_dir[keep]
  ord = switch(sort,
               name = order(tolower(df$path), df$path, method = "radix"),
               mtime = order(-as.numeric(df$mtime), tolower(df$path), method = "radix"),
               size = order(-df$size, tolower(df$path), method = "radix", na.last = TRUE))
  df = df[ord, , drop = FALSE]
  slash = slash[ord]
  rownames(df) = NULL
  structure(df, class = c("gptr_files", "data.frame"), root = dir, long = long, truncated = FALSE,
            limit = NA_integer_, slash = slash)
}

#' Direct `ls` tool text (Pi's format and notices) of a search_ls() listing
#' @noRd
ls_tool_text = function(f, limit = ls_default_limit) {
  if (!nrow(f)) return("(empty directory)")
  slash = attr(f, "slash") %||% (f$type == "dir")
  reached = nrow(f) > limit
  keep = seq_len(min(nrow(f), limit))
  tr = head_bytes(paste0(f$path[keep], ifelse(slash[keep], "/", "")))
  notes = c(
    if (reached) paste0(limit, " entries limit reached. Use limit=", limit * 2L, " for more"),
    if (tr$truncated) paste0(format_size(tool_max_bytes), " limit reached")
  )
  with_notices(paste(tr$lines, collapse = "\n"), notes)
}

#' Print grep matches in Pi's format within the member budget
#'
#' @param x A `gptr_matches` data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_matches = function(x, ...) {
  if (!nrow(x)) {
    ns_print_lines("No matches found")
    return(invisible(x))
  }
  fm = grep_format_lines(x)
  shown = budget_head(fm$lines, member_budget())
  limit = attr(x, "limit")
  notes = c(
    if (shown$omitted > 0L) paste0(shown$omitted, " more lines not printed; subset the value"),
    if (isTRUE(attr(x, "truncated"))) {
      paste0(limit, " matches limit reached; use limit = ", limit * 2L, " for more")
    },
    if (isTRUE(attr(x, "incomplete"))) {
      "the pattern was too expensive on some lines; results may be incomplete"
    }
  )
  ns_print_lines(c(shown$lines, if (length(notes)) paste0("[", paste(notes, collapse = ". "), "]")))
  invisible(x)
}

#' Print a file listing (paths, "/" after directories; size and time with `long`) within the member
#' budget
#'
#' @param x A `gptr_files` data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_files = function(x, ...) {
  if (!nrow(x)) {
    ns_print_lines("(no files)")
    return(invisible(x))
  }
  slash = attr(x, "slash") %||% (x$type == "dir")
  lines = paste0(x$path, ifelse(slash, "/", ""))
  if (isTRUE(attr(x, "long"))) {
    size = vapply(x$size, function(s) if (is.na(s)) "-" else format_size(s), "")
    lines = sprintf("%8s  %s  %s", size, format(x$mtime, "%Y-%m-%d %H:%M"), lines)
  }
  shown = budget_head(lines, member_budget())
  limit = attr(x, "limit")
  notes = c(
    if (shown$omitted > 0L) paste0(shown$omitted, " more entries not printed; subset the value"),
    if (isTRUE(attr(x, "truncated"))) {
      paste0("limit of ", limit, " reached; use limit = ", limit * 2L, " for more")
    }
  )
  ns_print_lines(c(shown$lines, if (length(notes)) paste0("[", paste(notes, collapse = ". "), "]")))
  invisible(x)
}
```

Regenerate `NAMESPACE` (adds `S3method(print,gptr_matches)` and `S3method(print,gptr_files)`):

```bash
Rscript --vanilla -e 'devtools::document()'
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-search")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 56 ]` with ripgrep (`rg`) on `PATH`; the ripgrep oracle skips on CRAN and without `rg` (then `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 53 ]`).

- [ ] **Step 5: Commit**

```bash
git add R/tool-search.R tests/testthat/test-tool-search.R NAMESPACE
git commit -m "feat(tools): add grep, find and ls with radix sorting and Pi's texts"
```

### Task 8: Member closures, resolution and namespace nodes

**Files:** Modify: `R/tool-namespace.R` (append part 2 of 4); Test: `tests/testthat/test-tool-namespace.R` (append part 2 of 4); Modify: `NAMESPACE` (generated).

The `peter$` namespace of 04 §5.3 and §7.10. P08 owns every `gptr_gateway` method (IC-36); its `$`/`[[` call the `ns.resolve` service and `.DollarNames` calls `ns.names` (registered in Task 10). `member_closure(spec)` builds a `gptr_member` function whose formals are the spec's `fun` formals (the member's own defaults) or, for an execute-only spec, the schema's properties (required first, optional ones defaulting to `NULL`, 04 §7.10). Its body is one call of an inlined closure on the inlined `base::environment()`, so the member's frame holds only its arguments and an argument named `frame`, `value`, `flags` or `environment` cannot shadow the machinery (G1 §2.8: closures are built by replacing `formals()` and `body()`, never the environment). Called while an `r` evaluation runs (the r-call marker of Task 1 is on the stack), the call passes P06's `dispatch_nested(name, input, ctx)` with only the supplied arguments, which runs the gate, records the call in the outer result's `details$nested` and returns the R value; called by the user, it runs the spec's `fun` directly (04 §9.4: "called by the user it runs directly"). On the user path arguments reach `fun` as promises through a call of symbols, never through a list (copy-safety rule R1); on the nested path the gate's contract is an input list (04 §7.6), so `describe`, the one P10 member that takes a user object, sends the gate only short labels of its argument expressions and computes the description locally, and `edit` sends a patch envelope as `patch` (`edit_nested_input()`, Task 6). Resolution and completion never activate a lazy plugin: names come from `registry_names()` and specs for catalogs and prints from `registry_all("tool")`, which returns tool placeholders unactivated (04 §10.8; `ns_spec_line()` renders a placeholder from its manifest declaration); only resolving a member by name (`registry_get()`) activates its plugin, which is the "first use" of 04 §10.8. A `deferred` spec without a namespace is callable even when it carries only an `execute` (04 §9.1: "found only through `peter$search()` (still callable)"): its closure takes its formals from the schema. `write` and `plot` return invisibly. The `describe` and `edit` members are defined here because `ns_member_flags()` recognises them; the other members follow in Task 10.

Resolution (IC-37): a name resolves to a member when an un-namespaced tool spec with a `fun` (or a `deferred` one with an `execute`) exists and is not `hidden` (the running session's rank-0 specs included); `"<ns>/<name>"` registry keys form plugin namespaces, reached as `peter$<ns>$<name>` through lazy `gptr_ns` nodes; a namespace equal to a reserved or existing member name, or to a provider name, is refused with one registry diagnostic (P02 already refuses it at registration; this is the second line of defence for specs registered in the other order). `ns_register_provider(name, fun)` registers a node provider (`mcp` is P18's); providers are configuration, not run state. Unknown names signal `gptr_error_unknown_member` with the sorted member list (acceptance 3). Resolution does no I/O and opens no connection (Task 10 proves it with traced file functions).

**Interfaces:**
- Consumes (P01, P02, P06, P09, P15; 04 §7.1, §7.2, §7.6, §7.9, §7.0): `registry_get(kind, name, session = NULL)` (activates a lazy winner), `registry_all(kind, session = NULL)` (returns `tool` placeholders unactivated: `lazy = TRUE`, `declaration = list(signature, description)`), `registry_names(kind, session = NULL)`, `registry_diagnostic(source, event, class, message)`, `registry_add(spec, source, rank, session = NULL, state = "active")` (default `state = "active"`, which `local_spec()` relies on; tests pass `state = "lazy"` for plugin placeholders) and `ext_placeholder(kind, name, source, declaration = NULL)` (tests), `as_tool_result(x)`, `gptr_tool_result(text, images, details, is_error, value)`, `gptr_tool(...)` (tests), `registry_add()`/`registry_remove()` (tests), `schema_signature(name, schema, description, prefix)`, `first_sentence(text)`, `json_obj()`, `check_class()`, `check_string()`, `check_strings()`, `check_choice()`, `check_function()`, `check_number()`, `dispatch_nested(name, input, ctx)` (P06, kernel SDK), `gptr_describe(x, budget)` (P09), `ext_service_has("doc.edit")`/`ext_service_get("doc.edit")` (P15: `function(path, edits, session) <gptr_tool_result> or NULL`); Task 1: `ns_r_call()`, `budget_head()`, `member_budget()`, `ns_print_lines()`, `new_gptr_text()`; Task 2: `resolve_tool_path()`; Task 6: `edit_file()`, `edit_envelope_of()`, `edit_normalize_args()`, `edit_nested_input()`, `new_gptr_patch()`.
- Produces (04 §5.3, §7.10): `member_closure(spec)` -> `c("gptr_member", "function")` with attributes `tool`, `spec`, `signature` and `print.gptr_member()`; `ns_resolve(path)` (service `ns.resolve`) -> a member closure or a `gptr_ns` node; `ns_names(pattern)` (service `ns.names`) -> sorted chr; `ns_register_provider(name, fun)` (P18); `ns_node(path, kind = "plugin", members = NULL, signatures = NULL)` -> `gptr_ns` with methods `$`, `[[`, `$<-`/`[[<-` (refuse: `gptr_error_readonly`), `names`, `.DollarNames`, `print`; internal for Tasks 9-11: `ns_tool_name(spec)`, `member_signature(spec)`, `ns_spec_line(spec, key)` (a spec's catalog line, or a lazy placeholder's from its declaration; `NULL` when there is none), `ns_member_ok(spec)`, `ns_signature_line(name, fun, description, dots = TRUE)`, `ns_formals_schema(fun)`, `ns_result_text(res)`, `ns_current_session()`, `ns_session_id()`, `ns_member_spec(name, sid)`, `ns_plugin_namespaces(sid, members)`, `ns_builtin_members`, `ns_reserved`, `ns_providers`, `member_describe(x, budget = 150L)`, `member_edit(path, edits, replace_all = FALSE)`, `edit_route_document(path, edits, session = NULL)`, `ns_routed_patch(path, res)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-tool-namespace.R`:

```r
# Register a spec for the calling test only (rank 3, source "user", or a plugin source)
local_spec = function(spec, source = "user", rank = 3L, .env = parent.frame()) {
  id = tryCatch(registry_add(spec, source = source, rank = rank),
                gptr_error_invalid_spec = function(e) NULL)
  if (!is.null(id)) withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

double_spec = function() {
  gptr_tool("double_it", "Double a number. Returns twice x.",
            fun = function(x, times = 2) x * times,
            exposure = "r")
}

test_that("member_closure() keeps the function's formals and calls it directly outside r", {
  m = member_closure(double_spec())
  expect_s3_class(m, "gptr_member")
  expect_identical(names(formals(m)), c("x", "times"))
  expect_identical(m(4), 8)
  expect_identical(m(4, times = 3), 12)
  expect_error(m(), "peter$double_it(): argument `x` is missing.", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  expect_identical(attr(m, "tool"), "double_it")
  expect_identical(utils::capture.output(print(m)),
                   "peter$double_it(x, times = 2)  # Double a number.")
})

test_that("inside r a member call passes dispatch_nested() with the supplied arguments only", {
  seen = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$name = name
    seen$input = input
    seen$ctx = ctx
    "gated value"
  })
  m = member_closure(double_spec())
  ctx = list(session = NULL, tag = "ctx-1")
  out = with_r_call(function() withVisible(m(5)), ctx)
  expect_identical(out, list(value = "gated value", visible = TRUE))
  expect_identical(seen$name, "double_it")
  expect_identical(seen$input, list(x = 5))
  expect_identical(seen$ctx$tag, "ctx-1")
  w = member_closure(gptr_tool("write", "Write a file.",
                               fun = function(path, content) invisible(path),
                               exposure = "r"))
  expect_false(with_r_call(function() withVisible(w("a", "b")), ctx)$visible)
  expect_identical(seen$input, list(path = "a", content = "b"))
})

test_that("arguments named like the member machinery reach the function unchanged", {
  spec = gptr_tool("clash", "Clash.", exposure = "r",
                   fun = function(frame, value, flags, environment, rc = 1) {
                     list(frame, value, flags, environment, rc)
                   })
  m = member_closure(spec)
  expect_identical(m("f", "v", "g", "e"), list("f", "v", "g", "e", 1))
  seen = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$input = input
    "gated"
  })
  expect_identical(with_r_call(function() m("f", "v", "g", "e", rc = 2), list()), "gated")
  expect_identical(seen$input, list(frame = "f", value = "v", flags = "g", environment = "e",
                                    rc = 2))
})

test_that("an execute-only spec gets formals from its schema", {
  params = list(type = "object", required = I("text"),
                properties = list(text = list(type = "string"), n = list(type = "number")))
  spec = gptr_tool("echo_it", "Echo.", parameters = params, exposure = "r",
                   execute = function(input, ctx) gptr_tool_result(input$text, value = input$text))
  spec$fun = NULL
  m = member_closure(spec)
  expect_identical(names(formals(m)), c("text", "n"))
  expect_null(formals(m)$n)
  expect_identical(m("hi"), "hi")
})

test_that("ns_resolve() finds user members and errors on unknown names listing the members", {
  local_spec(double_spec())
  expect_identical(ns_resolve("double_it")(21), 42)
  expect_true("double_it" %in% ns_names(""))
  expect_identical(ns_names("^double"), "double_it")
  cnd = tryCatch(ns_resolve("nope"), error = identity)
  expect_s3_class(cnd, "gptr_error_unknown_member")
  expect_identical(cnd$name, "nope")
  expect_true("double_it" %in% cnd$available)
  expect_match(conditionMessage(cnd), "peter$nope is not a peter member. Members: ", fixed = TRUE)
  local_spec(gptr_tool("secret_helper", "Hidden.", fun = function() 1, exposure = "hidden"))
  expect_error(ns_resolve("secret_helper"), class = "gptr_error_unknown_member")
})

test_that("plugin members live under their namespace; gptr_ns nodes are lazy and read-only", {
  local_spec(gptr_tool("summarise", "Summarise a vector. Returns a list.",
                       fun = function(x) list(n = length(x)),
                       exposure = "r", namespace = "demo"), source = "plugin:demo", rank = 5L)
  node = ns_resolve("demo")
  expect_s3_class(node, "gptr_ns")
  expect_identical(get("path", envir = node), "demo")
  expect_identical(names(node), "summarise")
  expect_identical(utils::.DollarNames(node, "^sum"), "summarise")
  expect_identical(node$summarise(1:3), list(n = 3L))
  expect_identical(node[["summarise"]](1:4), list(n = 4L))
  expect_true("demo" %in% ns_names(""))
  expect_error({
    node$x = 1
  }, class = "gptr_error_readonly")
  out = utils::capture.output(print(node))
  expect_identical(out, c("<peter namespace peter$demo: 1 members>",
                          "peter$demo$summarise(x: string)  # Summarise a vector."))
  expect_error(ns_resolve(c("demo", "nope")), class = "gptr_error_unknown_member")
})

test_that("a plugin r member without a namespace or with a reserved one is refused (IC-37)", {
  local_spec(gptr_tool("nsless", "No namespace.", fun = function(x) x, exposure = "r"),
             source = "plugin:demo", rank = 5L)
  expect_error(ns_resolve("nsless"), class = "gptr_error_unknown_member")
  expect_false("nsless" %in% ns_names(""))
  local_spec(gptr_tool("grep2", "Shadow.", fun = function(x) x, exposure = "r", namespace = "grep"),
             source = "plugin:demo", rank = 5L)
  expect_false("grep" %in% ns_plugin_namespaces())
  local_spec(gptr_tool("mine", "A user member.", fun = function() "ok", exposure = "r"))
  expect_identical(ns_resolve("mine")(), "ok")
})

test_that("namespace providers resolve their own paths (the hook P18 uses for peter$mcp)", {
  withr::defer(rm("mcpx", envir = ns_providers))
  ns_register_provider("mcpx", function(path) {
    if (length(path) == 1L) return(ns_node(path, "mcp", members = function() c("github", "files")))
    paste("resolved", paste(path, collapse = "/"))
  })
  node = ns_resolve("mcpx")
  expect_identical(names(node), c("files", "github"))
  expect_identical(node$github, "resolved mcpx/github")
  expect_true("mcpx" %in% ns_names(""))
  expect_error(ns_register_provider("grep", function(path) NULL),
               class = "gptr_error_invalid_argument")
})

test_that("peter$describe() returns gptr_describe() of the object", {
  d = member_describe(mtcars, budget = 60L)
  expect_s3_class(d, "gptr_text")
  expect_identical(as.character(d), gptr_describe(mtcars, budget = 60L))
  expect_error(member_describe(mtcars, budget = 5), class = "gptr_error_invalid_argument")
})

test_that("a bound history document is edited through the doc.edit service", {
  td = withr::local_tempdir()
  f = file.path(td, "analysis.R")
  writeBin(charToRaw("x = 1\n"), f)
  calls = new.env()
  local_service("doc.edit", function(path, edits, session) {
    calls$path = path
    gptr_tool_result("Successfully replaced 1 block(s) in analysis.R.",
                     details = list(path = path, n_edits = 1L, fuzzy = FALSE, diff = character(),
                                    document = TRUE))
  })
  p = member_edit(f, list(list(oldText = "x = 1", newText = "x = 2")))
  expect_identical(calls$path, resolve_tool_path(f))
  expect_identical(p$message, "Successfully replaced 1 block(s) in analysis.R.")
  expect_identical(rawToChar(readBin(f, "raw", 100)), "x = 1\n")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 28 ]`; Task 1's tests pass and the new ones error with `could not find function "member_closure"` (or `"ns_resolve"`, `"ns_register_provider"`, `"member_describe"`, `"member_edit"`).

- [ ] **Step 3: Write the implementation**

Append to `R/tool-namespace.R`:

```r
# ---- member closures (contract sections 5.3 and 7.10) --------------------------------------------

ns_builtin_members = c("read", "write", "edit", "grep", "find", "ls", "help", "search", "describe",
                       "plot", "out")
ns_reserved = c(ns_builtin_members, "sh", "script", "bg", "jobs", "py", "sql", "knit", "app", "mcp")

# Namespace providers registered by later plans (`mcp`, P18), and names already refused (one
# diagnostic each). Configuration only: no run state, no user object.
ns_providers = new.env(parent = emptyenv())
ns_refused = new.env(parent = emptyenv())

#' Registry name of a tool spec: "grep", or "<namespace>/<name>" for namespaced members
#' @noRd
ns_tool_name = function(spec) {
  if (is.null(spec$namespace)) spec$name else paste0(spec$namespace, "/", spec$name)
}

#' "(pattern, path = \".\", ...)" from a function's formals; `dots = FALSE` leaves out a `...`
#' formal (the built-in grep and ls accept Pi's argument names through it)
#' @noRd
ns_formals_text = function(fun, dots = TRUE) {
  if (!is.function(fun)) return("()")
  f = formals(fun)
  if (!dots) f = f[names(f) != "..."]
  parts = vapply(seq_along(f), function(i) {
    if (identical(f[[i]], quote(expr = ))) return(names(f)[i])
    paste0(names(f)[i], " = ", paste(deparse(f[[i]], width.cutoff = 500L), collapse = " "))
  }, "")
  paste0("(", paste(parts, collapse = ", "), ")")
}

#' A JSON Schema derived from a function's formals (contract section 9.1: all strings, required when
#' there is no default)
#' @noRd
ns_formals_schema = function(fun) {
  if (!is.function(fun)) return(list(type = "object", properties = json_obj()))
  f = formals(fun)
  f = f[names(f) != "..."]
  empty = vapply(seq_along(f), function(i) identical(f[[i]], quote(expr = )), NA)
  props = stats::setNames(rep(list(list(type = "string")), length(f)), names(f))
  list(type = "object", required = I(names(f)[empty]),
       properties = if (length(props)) props else json_obj())
}

#' Formals from a JSON Schema: required properties first (no default), optional ones default NULL
#' @noRd
ns_schema_formals = function(schema) {
  props = names(schema$properties %||% list())
  req = as.character(unlist(schema$required %||% list()))
  nms = c(intersect(req, props), setdiff(props, req))
  f = rep(list(quote(expr = )), length(nms))
  names(f) = nms
  for (nm in setdiff(nms, req)) f[nm] = list(NULL)
  as.pairlist(f)
}

#' One-line signature of a member: the spec's own `signature`; for namespaced (plugin) members the
#' typed catalog line `peter$<ns>$<name>(<arg>: <type>, <arg>?: <type>)  # <first sentence>`
#' (contract section 9.3); otherwise the R formals `peter$<name>(<formals>)  # <first sentence>`
#' @noRd
member_signature = function(spec) {
  if (is.character(spec$signature) && length(spec$signature) == 1L) return(spec$signature)
  if (!is.null(spec$namespace)) {
    schema = if (is.list(spec$parameters)) spec$parameters else ns_formals_schema(spec$fun)
    return(schema_signature(paste0(spec$namespace, "$", spec$name), schema,
                            description = spec$description, prefix = "peter$"))
  }
  fun = spec$fun
  if (!is.function(fun) && is.list(spec$parameters)) {
    fun = function() NULL
    formals(fun) = ns_schema_formals(spec$parameters)
  }
  ns_signature_line(spec$name, fun, spec$description)
}

#' Catalog line of a registered spec, or of a lazy plugin's placeholder from its manifest
#' declaration without activating the plugin (contract section 10.8): `peter$<ns>$<signature>  #
#' <first sentence>`; NULL for a placeholder that declares no signature
#' @noRd
ns_spec_line = function(spec, key) {
  if (!isTRUE(spec$lazy)) return(member_signature(spec))
  decl = spec$declaration
  sig = if (is.list(decl)) decl$signature else NULL
  if (!is.character(sig) || length(sig) != 1L || !nzchar(sig)) return(NULL)
  sentence = first_sentence(as.character(decl$description %||% ""))
  ns = if (grepl("/", key, fixed = TRUE)) paste0(sub("/.*$", "", key), "$") else ""
  paste0("peter$", ns, sig, if (nzchar(sentence)) paste0("  # ", sentence))
}

#' Is an un-namespaced spec a `peter$` member? A `fun`, or an `execute` when the spec is `deferred`
#' (contract 9.1: "found only through peter$search() (still callable)"), and not `hidden` (IC-37)
#' @noRd
ns_member_ok = function(spec) {
  !is.null(spec) && !isTRUE(spec$lazy) && is.null(spec$namespace) &&
    !identical(spec$exposure, "hidden") &&
    (is.function(spec$fun) || (identical(spec$exposure, "deferred") && is.function(spec$execute)))
}

#' `peter$<name>(<formals>)  # <first sentence>`
#' @noRd
ns_signature_line = function(name, fun, description, dots = TRUE) {
  sentence = first_sentence(description %||% "")
  comment = if (nzchar(sentence)) paste0("  # ", sentence)
  paste0("peter$", name, ns_formals_text(fun, dots), comment)
}

#' Names of formals without a default (`...` excluded)
#' @noRd
ns_required_formals = function(fmls) {
  if (!length(fmls)) return(character())
  empty = vapply(seq_along(fmls), function(i) identical(fmls[[i]], quote(expr = )), NA)
  setdiff(names(fmls)[empty], "...")
}

#' Signal a missing required argument of a member call
#' @noRd
ns_check_required = function(frame, required, tool_name) {
  for (nm in required) {
    if (eval(call("missing", as.name(nm)), frame)) {
      shown = sub("/", "$", tool_name, fixed = TRUE)
      gptr_abort(paste0("peter$", shown, "(): argument `", nm, "` is missing."),
                 "invalid_argument", arg = nm, expected = "a value")
    }
  }
  invisible(NULL)
}

#' The input list of a nested member call for the gate: the supplied arguments only (the member's
#' own defaults apply when its function runs), or, for `gate_only` members, short labels of the
#' argument expressions, so no user object ever enters a list (a list that becomes garbage leaves
#' the object's reference count raised; architecture section 6.4 rule R1)
#' @noRd
ns_collect_input = function(frame, arg_names, gate_only = FALSE) {
  input = list()
  for (nm in setdiff(arg_names, "...")) {
    if (eval(call("missing", as.name(nm)), frame)) next
    if (gate_only) {
      expr = eval(call("substitute", as.name(nm)), frame)
      input[[nm]] = if (is.atomic(expr) && length(expr) == 1L) {
        expr
      } else {
        substr(paste(deparse(expr, width.cutoff = 60L), collapse = " "), 1L, 80L)
      }
      next
    }
    val = get(nm, envir = frame, inherits = FALSE)
    if (!is.null(val)) input[[nm]] = val
  }
  if ("..." %in% arg_names && !gate_only) input = c(input, eval(quote(list(...)), frame))
  if (!length(input)) json_obj() else input
}

#' Call symbols `fun(a = a, b = b, ...)` for a member's formals
#' @noRd
ns_arg_symbols = function(arg_names) {
  out = lapply(arg_names, as.name)
  names(out) = ifelse(arg_names == "...", "", arg_names)
  out
}

#' Text of a tool result (its text blocks joined)
#' @noRd
ns_result_text = function(res) {
  blocks = Filter(function(b) identical(b$type, "text"), res$content %||% list())
  txt = vapply(blocks, function(b) b$text, "")
  paste(txt, collapse = "\n")
}

#' A member function for an execute-only spec (P02 normally generates `fun`; this is the fallback)
#' @noRd
ns_generated_fun = function(fmls, exec, tool_name) {
  arg_names = names(fmls) %||% character()
  f = function() {
    input = ns_collect_input(environment(), arg_names, FALSE)
    res = as_tool_result(exec(input, NULL))
    if (isTRUE(res$is_error)) {
      gptr_abort(ns_result_text(res), "tool", tool = tool_name, status = "error")
    }
    res$value %||% ns_result_text(res)
  }
  formals(f) = fmls
  f
}

#' `peter$describe(x, budget = 150L)`: gptr_describe() of the object (P09), as printable text
#'
#' Copy-safety [R4]: `x` reaches only the describer's leaf functions; nothing keeps it.
#' @noRd
member_describe = function(x, budget = 150L) {
  budget = check_number(budget, "budget", min = 20, int = TRUE)
  new_gptr_text(gptr_describe(x, budget = budget))
}

#' Edit through the document backend when `path` is a bound history document (the `doc.edit` service
#' of P15; NULL when P15 is absent or the path is not a bound document)
#' @noRd
edit_route_document = function(path, edits, session = NULL) {
  if (!is.null(edit_envelope_of(edits)) || !ext_service_has("doc.edit")) return(NULL)
  ext_service_get("doc.edit")(resolve_tool_path(path), edit_normalize_args(edits), session)
}

#' The value of an edit routed to the document backend, as a `gptr_patch`
#' @noRd
ns_routed_patch = function(path, res) {
  if (inherits(res$value, "gptr_patch")) return(res$value)
  d = res$details %||% list()
  new_gptr_patch(path, ns_result_text(res), d$diff %||% character(), d$n_edits %||% 1L, d$fuzzy)
}

#' `peter$edit(path, edits, replace_all = FALSE)`: a `gptr_patch`
#' @noRd
member_edit = function(path, edits, replace_all = FALSE) {
  routed = edit_route_document(path, edits)
  if (!is.null(routed)) return(ns_routed_patch(path, routed))
  ed = edit_file(path, edits, replace_all = replace_all)
  new_gptr_patch(path, ed$message, ed$diff, ed$details$n_edits, ed$fuzzy)
}

#' Behaviour of built-in members: `write` and `plot` return invisibly; P10's own `describe` passes
#' only labels of its arguments to the gate and computes its description locally (rule R1); P10's
#' own `edit` sends a patch envelope to the gate as `patch` (the edit schema's `edits` is an array
#' of objects)
#' @noRd
ns_member_flags = function(spec) {
  name = ns_tool_name(spec)
  own = function(fun) identical(spec$fun, fun)
  prepare = if (own(member_edit)) edit_nested_input else identity
  list(gate_only = own(member_describe), visible = !(name %in% c("write", "plot")),
       prepare = prepare)
}

#' A `gptr_member` closure for a tool spec (contract section 7.10)
#'
#' Formals come from the spec's `fun` (the R-callable form, whose defaults are the member's) or, for
#' an execute-only spec, from its schema (required properties first, optional ones default NULL).
#' Called while an `r` evaluation runs (model code), the call passes the gate through
#' dispatch_nested() (P06), which records it in the outer result's `details$nested`; called by the
#' user it runs the spec's `fun` directly. Arguments reach `fun` as promises through a call of
#' symbols, never through a list. The member's own frame holds only its arguments: its body is a
#' call of an inlined closure on the inlined base::environment(), so an argument named `frame`,
#' `value`, `flags` or `environment` cannot shadow the machinery.
#' @param spec A `gptr_tool` spec with a `fun` or an `execute`.
#' @return A function of class `c("gptr_member", "function")` with attributes `tool`, `spec`,
#'   `signature`.
#' @noRd
member_closure = function(spec) {
  check_class(spec, "gptr_tool", "spec")
  tool_name = ns_tool_name(spec)
  member_fun = spec$fun
  fmls = if (is.function(member_fun)) formals(member_fun) else ns_schema_formals(spec$parameters)
  if (!is.function(member_fun)) member_fun = ns_generated_fun(fmls, spec$execute, tool_name)
  arg_names = names(fmls) %||% character()
  required = ns_required_formals(fmls)
  flags = ns_member_flags(spec)
  call_fun = as.call(c(list(as.name("member_fun")), ns_arg_symbols(arg_names)))
  run = function(frame) {
    ns_check_required(frame, required, tool_name)
    rc = ns_r_call()
    if (!is.null(rc)) {
      input = flags$prepare(ns_collect_input(frame, arg_names, flags$gate_only))
      value = dispatch_nested(tool_name, input, rc$ctx)
      if (!flags$gate_only) return(if (flags$visible) value else invisible(value))
    }
    eval(call_fun, frame)
  }
  f = function() NULL
  formals(f) = fmls
  body(f) = as.call(list(run, as.call(list(base::environment))))
  structure(f, class = c("gptr_member", "function"), tool = tool_name, spec = spec,
            signature = member_signature(spec))
}

#' Print a member: its one-line signature with the first sentence of its description
#'
#' @param x A `gptr_member` function.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_member = function(x, ...) {
  ns_print_lines(attr(x, "signature") %||% "<peter member>")
  invisible(x)
}

# ---- resolution (the ns.resolve and ns.names services) -------------------------------------------

#' The session of the innermost running `r` evaluation, or NULL at the console
#' @noRd
ns_current_session = function() {
  rc = ns_r_call()
  if (is.null(rc) || is.null(rc$ctx)) NULL else rc$ctx$session
}

#' Id of that session (session-scoped rank-0 tools are visible to it), or NULL
#' @noRd
ns_session_id = function() {
  s = ns_current_session()
  if (is.null(s)) NULL else s$id
}

#' Record a refused namespace once, as a registry diagnostic
#' @noRd
ns_refuse = function(name, why) {
  if (exists(name, envir = ns_refused, inherits = FALSE)) return(invisible(NULL))
  assign(name, TRUE, envir = ns_refused)
  registry_diagnostic("builtin:tools", "member_refused", "invalid_spec",
                      paste0("peter$", name, " refused: ", why))
  invisible(NULL)
}

#' The member spec of an un-namespaced name, or NULL (IC-37: a spec with a `fun`, no namespace, not
#' `hidden`; P02 refuses a plugin `r` member without a namespace at registration). Resolving a name
#' is a first use: registry_get() activates a lazy plugin that provides it (contract 10.8)
#' @noRd
ns_member_spec = function(name, sid = NULL) {
  if (grepl("/", name, fixed = TRUE)) return(NULL)
  spec = registry_get("tool", name, session = sid)
  if (!ns_member_ok(spec)) return(NULL)
  spec
}

#' Un-namespaced member names, from registry_all("tool"), which leaves lazy placeholders
#' unactivated (completion and catalogs never load a plugin)
#' @noRd
ns_member_names = function(sid = NULL) {
  specs = registry_all("tool", session = sid)
  keys = names(specs)
  if (!length(keys)) return(character())
  ok = vapply(seq_along(specs), function(i) {
    !grepl("/", keys[i], fixed = TRUE) && ns_member_ok(specs[[i]])
  }, NA)
  keys[ok]
}

#' Plugin namespaces (prefixes of "<namespace>/<name>" tool names) that are neither reserved nor
#' member or provider names (IC-37); refused ones get a diagnostic
#' @noRd
ns_plugin_namespaces = function(sid = NULL, members = ns_member_names(sid)) {
  nms = registry_names("tool", session = sid)
  ns = unique(sub("/.*$", "", nms[grepl("/", nms, fixed = TRUE)]))
  taken = unique(c(ns_reserved, members, ls(ns_providers)))
  for (b in ns[ns %in% taken]) {
    ns_refuse(paste0(b, "$"), "the namespace is a reserved or existing member name")
  }
  sort(ns[!(ns %in% taken)], method = "radix")
}

#' Names completing `peter$` (the `ns.names` service behind P08's `.DollarNames.gptr_gateway`)
#'
#' @param pattern A regular expression from the completion engine ("" for all).
#' @return Sorted chr of member, provider and plugin-namespace names.
#' @noRd
ns_names = function(pattern) {
  sid = ns_session_id()
  members = ns_member_names(sid)
  all = unique(c(members, ls(ns_providers), ns_plugin_namespaces(sid, members)))
  all = sort(all, method = "radix")
  if (is.null(pattern) || !nzchar(pattern)) return(all)
  all[tryCatch(grepl(pattern, all), error = function(e) startsWith(all, pattern))]
}

#' A `gptr_ns` node (contract section 5.3): an environment with bindings `path` and `kind`, and for
#' provider nodes optional `members()` (chr of names) and `signatures()` (chr of lines) functions
#' @noRd
ns_node = function(path, kind = "plugin", members = NULL, signatures = NULL) {
  check_strings(path, "path")
  check_choice(kind, c("plugin", "mcp", "mcp_server"), "kind")
  node = new.env(parent = emptyenv())
  assign("path", as.character(path), envir = node)
  assign("kind", kind, envir = node)
  if (is.function(members)) assign("members", members, envir = node)
  if (is.function(signatures)) assign("signatures", signatures, envir = node)
  class(node) = "gptr_ns"
  node
}

#' Register a namespace provider (contract section 7.10): `fun(path)` returns a member closure or a
#' `gptr_ns` node for `peter$<name>$...` (P18 registers "mcp")
#' @noRd
ns_register_provider = function(name, fun) {
  check_string(name, "name")
  check_function(fun, "fun")
  if (name %in% setdiff(ns_builtin_members, "mcp")) {
    gptr_abort(paste0("`", name, "` is a built-in member name."), "invalid_argument", arg = "name",
               expected = "a name that is not a built-in member")
  }
  assign(name, fun, envir = ns_providers)
  invisible(name)
}

#' Unknown member: gptr_error_unknown_member listing the members
#' @noRd
ns_unknown = function(path) {
  avail = ns_names("")
  gptr_abort(paste0("peter$", paste(path, collapse = "$"), " is not a peter member. Members: ",
                    paste(avail, collapse = ", "), "."),
             "unknown_member", name = paste(path, collapse = "$"), available = avail)
}

#' Resolve `peter$<a>` or `peter$<a>$<b>...` (the `ns.resolve` service behind P08's
#' `$.gptr_gateway`)
#'
#' No I/O and no connections: only registry lookups and closure construction.
#' @param path chr: the member path, e.g. "grep" or c("demo", "summarise").
#' @return A `gptr_member` closure or a `gptr_ns` node.
#' @noRd
ns_resolve = function(path) {
  check_strings(path, "path")
  if (!length(path) || !nzchar(path[[1L]])) ns_unknown(path)
  sid = ns_session_id()
  head = path[[1L]]
  if (length(path) == 1L) {
    spec = ns_member_spec(head, sid)
    if (!is.null(spec)) return(member_closure(spec))
  }
  prov = get0(head, envir = ns_providers, inherits = FALSE)
  if (is.function(prov)) return(prov(path))
  if (length(path) <= 2L && head %in% ns_plugin_namespaces(sid)) {
    if (length(path) == 1L) return(ns_node(head, "plugin"))
    spec = registry_get("tool", paste0(head, "/", path[[2L]]), session = sid)
    if (!is.null(spec) && (is.function(spec$fun) || is.function(spec$execute)) &&
          !identical(spec$exposure, "hidden")) {
      return(member_closure(spec))
    }
  }
  ns_unknown(path)
}

#' @export
#' @noRd
`$.gptr_ns` = function(x, name) ns_resolve(c(get("path", envir = x, inherits = FALSE), name))

#' @export
#' @noRd
`[[.gptr_ns` = function(x, i, ...) ns_resolve(c(get("path", envir = x, inherits = FALSE), i))

#' @export
#' @noRd
`$<-.gptr_ns` = function(x, name, value) {
  gptr_abort("peter namespaces are read-only.", "readonly", object = "gptr_ns",
             field = as.character(name))
}

#' @export
#' @noRd
`[[<-.gptr_ns` = function(x, i, ..., value) {
  gptr_abort("peter namespaces are read-only.", "readonly", object = "gptr_ns",
             field = as.character(i))
}

#' Member names of a namespace node
#'
#' @param x A `gptr_ns` node.
#' @return Sorted chr.
#' @export
#' @noRd
names.gptr_ns = function(x) {
  members = get0("members", envir = x, inherits = FALSE)
  if (is.function(members)) return(sort(as.character(members()), method = "radix"))
  if (!identical(get("kind", envir = x, inherits = FALSE), "plugin")) return(character())
  pre = paste0(get("path", envir = x, inherits = FALSE)[1L], "/")
  nms = registry_names("tool", session = ns_session_id())
  sort(substring(nms[startsWith(nms, pre)], nchar(pre) + 1L), method = "radix")
}

#' @exportS3Method utils::.DollarNames
#' @noRd
.DollarNames.gptr_ns = function(x, pattern = "") {
  nms = names(x)
  if (is.null(pattern) || !nzchar(pattern)) return(nms)
  nms[tryCatch(grepl(pattern, nms), error = function(e) startsWith(nms, pattern))]
}

#' Print a namespace node: its member signatures within the member budget
#'
#' @param x A `gptr_ns` node.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_ns = function(x, ...) {
  path = get("path", envir = x, inherits = FALSE)
  nms = names(x)
  sigs = get0("signatures", envir = x, inherits = FALSE)
  lines = if (is.function(sigs)) {
    as.character(sigs())
  } else if (identical(get("kind", envir = x, inherits = FALSE), "plugin")) {
    specs = registry_all("tool", session = ns_session_id())
    vapply(nms, function(n) {
      key = paste0(path[1L], "/", n)
      line = if (is.null(specs[[key]])) NULL else ns_spec_line(specs[[key]], key)
      line %||% paste0("peter$", path[1L], "$", n)
    }, "", USE.NAMES = FALSE)
  } else {
    paste0("peter$", paste(path, collapse = "$"), "$", nms)
  }
  shown = budget_head(lines, member_budget())
  title = paste0("<peter namespace peter$", paste(path, collapse = "$"), ": ", length(nms),
                 " members>")
  more = if (shown$omitted > 0L) paste0("(+ ", shown$omitted, " more: names(x))")
  ns_print_lines(c(title, shown$lines, more))
  invisible(x)
}
```

Regenerate `NAMESPACE` (adds `S3method(print,gptr_member)`, `S3method("$",gptr_ns)`, `S3method("[[",gptr_ns)`, `S3method("$<-",gptr_ns)`, `S3method("[[<-",gptr_ns)`, `S3method(names,gptr_ns)`, `S3method(print,gptr_ns)` and `S3method(utils::.DollarNames,gptr_ns)`):

```bash
Rscript --vanilla -e 'devtools::document()'
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 79 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/tool-namespace.R tests/testthat/test-tool-namespace.R NAMESPACE
git commit -m "feat(tools): add member closures, namespace resolution and gptr_ns nodes"
```

### Task 9: The plugin catalog, BM25, `peter$search()` and `peter$help()`

**Files:** Modify: `R/tool-namespace.R` (append part 3 of 4); Test: `tests/testthat/test-tool-namespace.R` (append part 3 of 4).

`ns_catalog()` builds the body of the T1 `plugins` section (IC-25, 04 §9.3; header text verbatim): one `peter$<ns>$<name>(<arg>: <type>, <arg>?: <type>)  # <first sentence>` line per plugin `r` member, sorted by name; over the budget, descriptions are trimmed from the end of the catalog (no usage history exists at freeze, so the last entries count as least recently used), names are always kept. A lazy plugin contributes the signature lines its manifest declares (`extension.declarations`), read from the unactivated placeholders that `registry_all("tool")` returns, so freezing a prompt never runs a plugin's factory (04 §10.8: "activation never changes the cached prefix"; P17's acceptance 3a checks that the package is still not loaded after the first `peter()` call); `peter$search()` searches placeholders through their declarations the same way, and only calling the member activates the plugin. `bm25_index()`/`bm25_search()` are the port of Pi's `tool_search` ranker (report 06 §5.7: camelCase splitting, stop words, naive singular stemming, k1 = 1.2, b = 0.75, idf = ln(1 + (N - f + 0.5) / (f + 0.5)), ties in document order); the test reproduces Pi's tokens, ranking and scores on its fixture. `peter$search(words, limit = 8L)` ranks the documents of every `search_source` record (IC-69: the `members` source of Task 10, kinds `member`, `plugin`, `deferred`, plus any plugin's) together with skills (P17's `skill.catalog` service) and MCP tools (P18's `mcp.catalog` service) parsed from their catalog texts, returning df `name`, `kind`, `signature`, `score` (04 §9.4). `search_sources(session)` is the `search.sources` service (IC-34); a failing source is skipped with a registry diagnostic. `peter$help(name, package = NULL, budget = 800L)` shows a member's or plugin function's signature, description and arguments (an MCP tool's through the `mcp` provider's member `spec` attribute), else the R help page through `utils::help()`, `tools::Rd_db()` and `tools::Rd2txt()` (report 20 §5.2: no `:::`), cut to the budget with a notice.

**Interfaces:**
- Consumes (P01, P02, P06, P17, P18): `registry_all(kind, session = NULL)` (tool placeholders unactivated), `registry_add(spec, source, rank, session = NULL, state = "active")` (tests pass `state = "lazy"` for plugin placeholders), `ext_placeholder(kind, name, source, declaration = NULL)` and `gptr_registry("tool")` (tests), `registry_get()`, `registry_names()`, `registry_diagnostic()`, `est_tokens()`, `schema_signature()`, `first_sentence()`, `check_*()`, `gptr_abort()`, `session_live(s)` (kernel SDK; its `ctx`), `ext_service_has()`/`ext_service_get()` for `skill.catalog` and `mcp.catalog` (`function(session, budget) chr(1)`); Task 1: `budget_head()`, `new_gptr_text()`; Task 4: `split_lines_count()`; Task 8: `member_signature()`, `ns_spec_line()`, `ns_formals_schema()`, `ns_plugin_namespaces()`, `ns_member_spec()`, `ns_current_session()`, `ns_session_id()`, `ns_providers`.
- Produces (04 §7.10, §9.4): `ns_catalog(session, kinds = c("plugin"), budget = 1500L)` -> chr(1) (`""` without plugin members; lazy plugins contribute their declared signatures without being activated, 04 §10.8); `ns_plugins_section(ctx)` -> the section text or `NULL` (the `plugins` section's `text` function, registered in Task 10); `bm25_index(docs)` (docs = df `id`, `text`), `bm25_search(index, words, limit = 8L)` -> df `id`, `score` (P18 reuses both); `search_sources(session = NULL)` (service `search.sources`) -> df `id`, `text`, `kind`; `ns_search_docs(ctx)` (the `members` search source); `member_search(words, limit = 8L)`; `member_help(name, package = NULL, budget = 800L)` -> `gptr_text`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-tool-namespace.R` (the BM25 expectations are Pi's ranking and scores on report 06 §5.7's fixture):

```r
test_that("ns_catalog() lists plugin r members and trims descriptions, never names, over budget", {
  expect_identical(ns_catalog(NULL), "")
  expect_null(ns_plugins_section(NULL))
  for (i in 1:40) {
    local_spec(gptr_tool(sprintf("tool%02d", i), paste("Does thing number", i,
                                                       "with several words of text."),
                         fun = function(x, y = 1) x, exposure = "r", namespace = "demo"),
               source = "plugin:demo", rank = 5L)
  }
  local_spec(gptr_tool("hidden_one", "Hidden.", fun = function() 1, exposure = "hidden",
                       namespace = "demo"),
             source = "plugin:demo", rank = 5L)
  full = strsplit(ns_catalog(NULL), "\n")[[1L]]
  expect_identical(length(full), 40L)
  expect_identical(full[1L], paste("peter$demo$tool01(x: string, y?: string)",
                                   " # Does thing number 1 with several words of text."))
  small = strsplit(ns_catalog(NULL, budget = 800L), "\n")[[1L]]
  expect_identical(length(small), 40L)
  expect_identical(sub("\\(.*$", "", small), sub("\\(.*$", "", full))
  expect_lte(est_tokens(small, "code"), 800)
  expect_true(grepl("  # ", small[1L], fixed = TRUE))
  expect_false(grepl("  # ", small[40L], fixed = TRUE))
  tiny = strsplit(ns_catalog(NULL, budget = 10L), "\n")[[1L]]
  expect_identical(length(tiny), 40L)
  expect_false(any(grepl("  # ", tiny, fixed = TRUE)))
  sec = ns_plugins_section(NULL)
  expect_true(startsWith(sec, "Plugin functions are R functions called inside r."))
  expect_identical(ns_catalog(NULL, kinds = "mcp"), "")
})

test_that("a lazy plugin is catalogued, completed and searched through its declarations", {
  decl = list(signature = "search(condition: string)",
              description = "Search recruiting clinical trials. Returns a data frame.")
  id = registry_add(ext_placeholder("tool", "lazyns/search", "plugin:lazyns", declaration = decl),
                    source = "plugin:lazyns", rank = 5L, state = "lazy")
  withr::defer(registry_remove(id))
  state = function() {
    reg = gptr_registry("tool")
    reg$state[reg$name == "lazyns/search"]
  }
  line = "peter$lazyns$search(condition: string)  # Search recruiting clinical trials."
  expect_identical(ns_catalog(NULL), line)
  expect_true("lazyns" %in% ns_names(""))
  node = ns_resolve("lazyns")
  expect_identical(names(node), "search")
  expect_identical(utils::capture.output(print(node))[2L], line)
  if (is.null(registry_get("search_source", "members"))) {
    local_spec(gptr_spec("search_source", "members", docs = ns_search_docs))
  }
  res = member_search("recruiting trials")
  expect_identical(res$name[1L], "lazyns/search")
  expect_identical(res$kind[1L], "plugin")
  expect_identical(res$signature[1L], line)
  expect_identical(state(), "lazy")
})

test_that("the BM25 port reproduces Pi's tokens, ranking and scores (report 06 section 5.7)", {
  words = "getHTTPResponse parses XMLHttpRequest_bodies, the Queries & classes/boxes"
  expect_identical(bm25_tokenize(words),
                   c("get", "http", "response", "parse", "xml", "http", "request", "body", "query",
                     "class", "box"))
  doc = function(name, description, properties, ns = NULL, ns_desc = NULL) {
    params = list(type = "object", properties = properties)
    parts = c(name, gsub("_", " ", name, fixed = TRUE), description, bm25_schema_text(params),
              ns, ns_desc)
    paste(parts[nzchar(trimws(parts))], collapse = " ")
  }
  str_prop = function(description = NULL) list(type = "string", description = description)
  gh = c("mcp__github", "GitHub repositories, issues and pull requests")
  wh = c("mcp__warehouse", "SQL warehouse")
  texts = c(
    doc("mcp__github__search_issues", "Search issues and pull requests across repositories.",
        list(query = str_prop("Search query using GitHub syntax"),
             perPage = list(type = "integer")), gh[1], gh[2]),
    doc("mcp__github__create_issue", "Open a new issue in a repository.",
        list(title = str_prop(), body = str_prop(),
             labels = list(type = "array", items = str_prop("Label names"))), gh[1], gh[2]),
    doc("mcp__github__getPullRequestFiles", "List the files changed by a pull request.",
        list(pullNumber = list(type = "integer")), gh[1], gh[2]),
    doc("mcp__warehouse__run_query", "Run a read-only SQL query and return rows.",
        list(sql = str_prop("The SQL statement"), limit = list(type = "integer")), wh[1], wh[2]),
    doc("mcp__warehouse__list_tables", "List the tables of a schema with their columns.",
        list(schema = list(anyOf = list(str_prop("Schema name"), list(type = "null")))),
        wh[1], wh[2]),
    doc("fetch_url", "Fetch a web page and convert it to markdown.", list(url = str_prop()))
  )
  ids = c("github__search_issues", "github__create_issue", "github__getPullRequestFiles",
          "warehouse__run_query", "warehouse__list_tables", "fetch_url")
  docs = data.frame(id = ids, text = texts, stringsAsFactors = FALSE)
  idx = bm25_index(docs)
  top = function(q) {
    r = bm25_search(idx, q)
    utils::head(data.frame(id = r$id, score = round(r$score, 4)), 2L)
  }
  expect_identical(top("search github issues"),
                   data.frame(id = c("github__search_issues", "github__create_issue"),
                              score = c(4.5635, 2.2182)))
  expect_identical(top("sql tables"),
                   data.frame(id = c("warehouse__list_tables", "warehouse__run_query"),
                              score = c(3.565, 1.738)))
  expect_identical(top("pull request files"),
                   data.frame(id = c("github__getPullRequestFiles", "github__search_issues"),
                              score = c(4.6575, 1.7275)))
  expect_identical(nrow(bm25_search(idx, "the of and")), 0L)
  expect_identical(top("markdown"), data.frame(id = "fetch_url", score = 1.997))
  expect_identical(top("issue labels"),
                   data.frame(id = c("github__create_issue", "github__search_issues"),
                              score = c(3.211, 1.1028)))
  expect_identical(top("queries"),
                   data.frame(id = c("warehouse__run_query", "github__search_issues"),
                              score = c(1.6129, 1.2831)))
  expect_error(bm25_index(list()), class = "gptr_error_invalid_argument")
})

test_that("peter$search() ranks members, plugin tools and search_source documents", {
  local_spec(double_spec())
  local_spec(gptr_tool("trial_lookup", "Look up clinical trials by indication.",
                       fun = function(indication) 1,
                       exposure = "r", namespace = "trials"), source = "plugin:trials", rank = 5L)
  local_spec(gptr_tool("rare_thing", "Convert units of measurement.",
                       execute = function(input, ctx) "x",
                       exposure = "deferred"))
  if (is.null(registry_get("search_source", "members"))) {
    local_spec(gptr_spec("search_source", "members", docs = ns_search_docs))
  }
  local_spec(gptr_spec("search_source", "glossary", docs = function(ctx) {
    data.frame(id = "glossary/cohort", text = "cohort definition of a clinical trial population",
               kind = "glossary")
  }))
  res = member_search("clinical trials")
  expect_named(res, c("name", "kind", "signature", "score"))
  expect_identical(res$name[1], "trials/trial_lookup")
  expect_identical(res$kind[1], "plugin")
  expect_identical(res$signature[1], paste("peter$trials$trial_lookup(indication: string)",
                                           " # Look up clinical trials by indication."))
  expect_true("glossary/cohort" %in% res$name)
  expect_identical(res$kind[res$name == "glossary/cohort"], "glossary")
  conv = member_search("convert units")
  expect_identical(conv$kind[1], "deferred")
  expect_identical(conv$signature[1], "peter$rare_thing()  # Convert units of measurement.")
  expect_identical(ns_resolve("rare_thing")(), "x")
  expect_identical(member_search("double number")$kind[1], "member")
  expect_identical(nrow(member_search("zzzz qqqq")), 0L)
})

test_that("peter$help() shows a member's schema, else the R help page, within the budget", {
  params = list(type = "object", required = I("indication"),
                properties = list(indication = list(type = "string", description = "Disease"),
                                  phase = list(enum = c("1", "2", "3"))))
  description = "Look up clinical trials by indication. Returns a data frame."
  local_spec(gptr_tool("trial_lookup", description, parameters = params,
                       fun = function(indication, phase = NULL) 1, exposure = "r",
                       namespace = "trials"),
             source = "plugin:trials", rank = 5L)
  h = member_help("trials/trial_lookup")
  expect_s3_class(h, "gptr_text")
  expect_identical(as.character(h), c(
    paste("peter$trials$trial_lookup(indication: string, phase?: any)",
          " # Look up clinical trials by indication."),
    "",
    "Look up clinical trials by indication. Returns a data frame.",
    "",
    "Arguments:",
    "  indication (string, required): Disease",
    "  phase (enum) [1, 2, 3]"
  ))
  r = member_help("median", budget = 100L)
  expect_identical(as.character(r)[1], "[help: stats::median]")
  expect_lte(est_tokens(as.character(r), "prose"), 100 + 20)
  expect_match(as.character(r)[length(r)], "more lines of help not shown")
  expect_match(as.character(member_help("no_such_topic_xyz")),
               "No help found for 'no_such_topic_xyz'", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 79 ]`; the five new tests error with `could not find function "ns_catalog"` (or `"bm25_tokenize"`, `"member_search"`, `"member_help"`).

- [ ] **Step 3: Write the implementation**

Append to `R/tool-namespace.R`:

```r
# ---- the plugin catalog (the `plugins` prompt section, IC-25) ------------------------------------

ns_plugins_header = paste(
  "Plugin functions are R functions called inside r. They return R values; assign and summarise",
  "them before printing. peter$search(\"words\") finds more and peter$help(\"<ns>/<name>\") shows",
  "a full schema."
)

#' Body of the `plugins` section: one signature line per plugin `r` member (contract section 7.10)
#'
#' Over the budget, descriptions are trimmed from the end of the name-sorted catalog (no usage
#' history exists at freeze, so the least recently used are the last); names are always kept. A
#' lazy plugin contributes the signatures its manifest declares, and the catalog never activates
#' it (contract 10.8: activation never changes the cached prefix).
#' @param session A `gptr_session` (its rank-0 tools count) or NULL.
#' @param kinds Kinds of members to list; only `"plugin"` is catalogued here (MCP has its own
#'   section).
#' @param budget Estimated-token budget of the lines.
#' @return chr(1), "" when there is no plugin member.
#' @noRd
ns_catalog = function(session, kinds = c("plugin"), budget = 1500L) {
  check_strings(kinds, "kinds")
  check_number(budget, "budget", min = 1)
  if (!("plugin" %in% kinds)) return("")
  sid = if (is.null(session)) NULL else session$id
  ok = ns_plugin_namespaces(sid)
  specs = registry_all("tool", session = sid)
  keys = names(specs)
  keys = keys[grepl("/", keys, fixed = TRUE) & sub("/.*$", "", keys) %in% ok]
  lines = character()
  for (k in sort(keys, method = "radix")) {
    spec = specs[[k]]
    if (!isTRUE(spec$lazy) && !identical(spec$exposure, "r")) next
    line = ns_spec_line(spec, k)
    if (!is.null(line)) lines = c(lines, line)
  }
  if (!length(lines)) return("")
  i = length(lines)
  while (i >= 1L && est_tokens(lines, "code") > budget) {
    lines[i] = sub("  # .*$", "", lines[i])
    i = i - 1L
  }
  paste(lines, collapse = "\n")
}

#' Text of the `plugins` section (T1, order 860) or NULL when no plugin member exists
#' @noRd
ns_plugins_section = function(ctx) {
  s = if (is.null(ctx)) NULL else ctx$session
  body = ns_catalog(s, budget = 1500L - ceiling(est_tokens(ns_plugins_header, "prose")))
  if (!nzchar(body)) return(NULL)
  paste(c(ns_plugins_header, body), collapse = "\n")
}

# ---- BM25 search (contract section 7.10; Pi's tool_search ranker, report 06 section 5.7) ---------

bm25_stop_words = c("a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is",
                    "it", "of", "on", "or", "that", "the", "this", "to", "with")

#' Pi's naive singular stemming
#' @noRd
bm25_stem = function(term) {
  n = nchar(term)
  plural = n > 3 & endsWith(term, "s") & !endsWith(term, "ss")
  ifelse(n > 4 & endsWith(term, "ies"), paste0(substr(term, 1, n - 3), "y"),
         ifelse(n > 4 & grepl("(ches|shes|sses|xes|zes)$", term), substr(term, 1, n - 2),
                ifelse(plural, substr(term, 1, n - 1), term)))
}

#' Pi's tokeniser: split camelCase, lower-case, split on non-alphanumerics, drop stop words, stem
#' @noRd
bm25_tokenize = function(text) {
  text = gsub("([a-z0-9])([A-Z])", "\\1 \\2", text, perl = TRUE)
  text = gsub("([A-Z]+)([A-Z][a-z])", "\\1 \\2", text, perl = TRUE)
  terms = strsplit(tolower(text), "[^a-z0-9]+", perl = TRUE)[[1L]]
  terms = terms[nzchar(terms) & !terms %in% bm25_stop_words]
  if (!length(terms)) character() else bm25_stem(terms)
}

#' Text of a JSON Schema for search: descriptions and property names, recursively (Pi schemaText())
#' @noRd
bm25_schema_text = function(schema) {
  if (!is.list(schema) || is.null(names(schema))) return(character())
  parts = character()
  if (is.character(schema$description)) parts = c(parts, schema$description)
  if (is.list(schema$properties)) {
    for (n in names(schema$properties)) {
      parts = c(parts, n, bm25_schema_text(schema$properties[[n]]))
    }
  }
  parts = c(parts, bm25_schema_text(schema$items))
  for (key in c("anyOf", "oneOf", "allOf")) {
    if (is.list(schema[[key]])) for (v in schema[[key]]) parts = c(parts, bm25_schema_text(v))
  }
  parts
}

#' BM25 index of documents `data.frame(id, text)` (contract section 7.10)
#' @noRd
bm25_index = function(docs) {
  if (!is.data.frame(docs) || !all(c("id", "text") %in% names(docs))) {
    gptr_abort("`docs` must be a data frame with columns id and text.", "invalid_argument",
               arg = "docs", expected = "a data frame with columns id and text")
  }
  tf = lapply(as.character(docs$text), function(t) table(bm25_tokenize(t)))
  len = vapply(tf, function(x) as.numeric(sum(x)), numeric(1))
  avg = if (length(len) && sum(len) > 0) sum(len) / length(len) else 1
  list(ids = as.character(docs$id), tf = tf, len = len, avgdl = avg,
       df = table(unlist(lapply(tf, names), use.names = FALSE)), n = nrow(docs))
}

bm25_k1 = 1.2
bm25_b = 0.75

#' Rank indexed documents for a query: k1 = 1.2, b = 0.75, idf = ln(1 + (N - f + 0.5) / (f + 0.5)),
#' ties keep document order; data.frame(id, score) of at most `limit` rows with a positive score
#' @noRd
bm25_search = function(index, words, limit = 8L) {
  check_string(words, "words", empty = TRUE)
  limit = check_number(limit, "limit", min = 0, int = TRUE)
  q = unique(bm25_tokenize(words))
  empty = data.frame(id = character(), score = numeric(), stringsAsFactors = FALSE)
  if (!length(q) || !index$n || limit <= 0) return(empty)
  score = numeric(index$n)
  norm = bm25_k1 * (1 - bm25_b + bm25_b * index$len / index$avgdl)
  for (t in q) {
    f = if (t %in% names(index$df)) as.numeric(index$df[[t]]) else 0
    idf = log(1 + (index$n - f + 0.5) / (f + 0.5))
    cnt = vapply(index$tf, function(x) if (t %in% names(x)) as.numeric(x[[t]]) else 0, numeric(1))
    hit = cnt > 0
    score[hit] = score[hit] + idf * (cnt[hit] * (bm25_k1 + 1)) / (cnt[hit] + norm[hit])
  }
  keep = which(score > 0)
  if (!length(keep)) return(empty)
  keep = utils::head(keep[order(-score[keep], keep)], limit)
  data.frame(id = index$ids[keep], score = score[keep], stringsAsFactors = FALSE)
}

#' Pi's search document text of a tool: name, name with "_" as " ", description, schema text,
#' namespace
#' @noRd
ns_search_text = function(spec) {
  params = if (is.list(spec$parameters)) spec$parameters else list()
  parts = c(spec$name, gsub("_", " ", spec$name, fixed = TRUE), spec$description %||% "",
            bm25_schema_text(params), spec$namespace)
  paste(parts[nzchar(trimws(parts))], collapse = " ")
}

#' Search text of a lazy plugin's placeholder: its name, the name with "_" as " ", the declared
#' description and signature, and the namespace (the plugin is not activated, contract 10.8)
#' @noRd
ns_search_text_lazy = function(key, declaration) {
  name = sub("^.*/", "", key)
  parts = c(name, gsub("_", " ", name, fixed = TRUE),
            as.character(declaration$description %||% ""),
            as.character(declaration$signature %||% ""),
            if (grepl("/", key, fixed = TRUE)) sub("/.*$", "", key))
  paste(parts[nzchar(trimws(parts))], collapse = " ")
}

#' Documents of every non-hidden tool with a member form or a deferred exposure: the `members`
#' search_source of builtin:tools (kinds `member`, `plugin`, `deferred`). Specs come from
#' registry_all("tool"), so a lazy plugin is searched through its declarations, not activated.
#' @noRd
ns_search_docs = function(ctx) {
  s = if (is.null(ctx)) NULL else ctx$session
  sid = if (is.null(s)) NULL else s$id
  specs = registry_all("tool", session = sid)
  rows = lapply(names(specs), function(n) {
    spec = specs[[n]]
    if (isTRUE(spec$lazy)) {
      if (!grepl("/", n, fixed = TRUE) || is.null(ns_spec_line(spec, n))) return(NULL)
      return(data.frame(id = n, text = ns_search_text_lazy(n, spec$declaration), kind = "plugin",
                        stringsAsFactors = FALSE))
    }
    if (is.null(spec) || identical(spec$exposure, "hidden")) return(NULL)
    kind = if (identical(spec$exposure, "deferred")) {
      "deferred"
    } else if (!is.null(spec$namespace)) {
      "plugin"
    } else if (is.function(spec$fun)) {
      "member"
    } else {
      return(NULL)
    }
    data.frame(id = n, text = ns_search_text(spec), kind = kind, stringsAsFactors = FALSE)
  })
  rows = Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame(id = character(), text = character(), kind = character()))
  do.call(rbind, rows)
}

#' Documents of every `search_source` record (the `search.sources` service, IC-69)
#'
#' @param session A `gptr_session` or NULL; each source's `docs(ctx)` gets the session's ctx.
#' @return data.frame(id, text, kind); a failing source is skipped with a registry diagnostic.
#' @noRd
search_sources = function(session = NULL) {
  sid = if (is.null(session)) NULL else session$id
  live = if (is.null(session)) NULL else session_live(session)
  ctx = if (is.null(live)) NULL else live$ctx
  out = lapply(registry_all("search_source", session = sid), function(r) {
    d = tryCatch(r$docs(ctx), error = function(e) {
      registry_diagnostic("builtin:tools", "search_source", "internal",
                          paste0("search source ", r$name, " failed: ", conditionMessage(e)))
      NULL
    })
    if (is.data.frame(d) && all(c("id", "text", "kind") %in% names(d)) && nrow(d)) {
      data.frame(id = as.character(d$id), text = as.character(d$text), kind = as.character(d$kind),
                 stringsAsFactors = FALSE)
    }
  })
  out = Filter(Negate(is.null), out)
  if (!length(out)) return(data.frame(id = character(), text = character(), kind = character()))
  do.call(rbind, out)
}

#' Search documents of skills (P17 `skill.catalog`) and MCP tools (P18 `mcp.catalog`) parsed from
#' their catalog texts (formats of architecture section 7.3); data.frame(id, text, kind, signature)
#' @noRd
ns_catalog_docs = function(session) {
  rows = list()
  catalog = function(service) {
    txt = tryCatch(ext_service_get(service)(session, 1e6), error = function(e) "")
    split_lines_count(txt %||% "")
  }
  if (ext_service_has("skill.catalog")) {
    lines = catalog("skill.catalog")
    lines = lines[startsWith(lines, "- ")]
    if (length(lines)) {
      rows[[length(rows) + 1L]] = data.frame(id = sub("^- ([^:]+):.*$", "\\1", lines),
                                             text = lines, kind = "skill", signature = lines,
                                             stringsAsFactors = FALSE)
    }
  }
  if (ext_service_has("mcp.catalog")) {
    lines = catalog("mcp.catalog")
    server = ""
    for (ln in lines) {
      hdr = regmatches(ln, regexec("^(\\S+): [0-9]+ tools", ln))[[1L]]
      if (length(hdr)) {
        server = hdr[2L]
        next
      }
      tool = regmatches(ln, regexec("^\\s+([A-Za-z0-9_.-]+)\\(", ln))[[1L]]
      if (length(tool) && nzchar(server)) {
        sig = paste0("peter$mcp$", server, "$", trimws(ln))
        rows[[length(rows) + 1L]] = data.frame(id = paste0(server, "/", tool[2L]),
                                               text = paste(server, ln), kind = "mcp",
                                               signature = sig, stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(id = character(), text = character(), kind = character(),
                      signature = character()))
  }
  do.call(rbind, rows)
}

# ---- member functions (contract section 9.4) -----------------------------------------------------

#' `peter$search(words, limit = 8L)`: BM25 over members, plugin and deferred tools, `search_source`
#' records, skills and MCP tools
#' @noRd
member_search = function(words, limit = 8L) {
  check_string(words, "words")
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  s = ns_current_session()
  docs = search_sources(s)
  docs$signature = rep(NA_character_, nrow(docs))
  docs = rbind(docs, ns_catalog_docs(s))
  hits = bm25_search(bm25_index(docs), words, limit)
  m = match(hits$id, docs$id)
  sig = docs$signature[m]
  sid = if (is.null(s)) NULL else s$id
  specs = registry_all("tool", session = sid)
  for (i in which(is.na(sig))) {
    spec = specs[[hits$id[i]]]
    line = if (is.null(spec)) NULL else ns_spec_line(spec, hits$id[i])
    sig[i] = line %||% hits$id[i]
  }
  data.frame(name = hits$id, kind = docs$kind[m], signature = sig, score = round(hits$score, 3),
             stringsAsFactors = FALSE)
}

#' Help lines of a tool spec: signature, description and the arguments of its schema
#' @noRd
ns_tool_help = function(spec) {
  params = if (is.list(spec$parameters)) spec$parameters else ns_formals_schema(spec$fun)
  props = params$properties %||% list()
  req = as.character(unlist(params$required %||% list()))
  same = !is.function(spec$fun) || setequal(names(props), setdiff(names(formals(spec$fun)), "..."))
  args = if (same && length(props)) {
    vapply(names(props), function(p) {
      pr = props[[p]]
      type = pr$type %||% if (!is.null(pr$enum)) "enum" else "any"
      paste0("  ", p, " (", paste(unlist(type), collapse = "|"),
             if (p %in% req) ", required" else "", ")",
             if (is.character(pr$description)) paste0(": ", pr$description) else "",
             if (!is.null(pr$enum)) paste0(" [", paste(unlist(pr$enum), collapse = ", "), "]"))
    }, "", USE.NAMES = FALSE)
  }
  c(member_signature(spec), "", spec$description %||% "",
    if (length(args)) c("", "Arguments:", args))
}

#' R help page as plain text: utils::help(), tools::Rd_db(), tools::Rd2txt() (no `:::`; report 20
#' section 5.2)
#' @noRd
ns_r_help = function(topic, package = NULL) {
  hf = if (is.null(package)) {
    utils::help((topic), help_type = "text")
  } else {
    utils::help((topic), package = (package), help_type = "text")
  }
  paths = as.character(hf)
  if (!length(paths)) {
    where = if (is.null(package)) "" else paste0(" in package '", package, "'")
    return(paste0("No help found for '", topic, "'", where, "."))
  }
  path = paths[[1L]]
  pkg = basename(dirname(dirname(path)))
  rd = tools::Rd_db(pkg)[[paste0(basename(path), ".Rd")]]
  if (is.null(rd)) {
    return(paste0("Help page '", basename(path), "' not found in package '", pkg, "'."))
  }
  tf = tempfile(fileext = ".txt")
  on.exit(unlink(tf), add = TRUE)
  tools::Rd2txt(rd, out = tf, options = list(underline_titles = FALSE, width = 80L))
  txt = readLines(tf, encoding = "UTF-8", warn = FALSE)
  more = if (length(paths) > 1L) paste0(" (", length(paths), " matches; first shown)") else ""
  c(paste0("[help: ", pkg, "::", topic, "]", more), as_utf8(txt))
}

#' `peter$help(name, package = NULL, budget = 800L)`: the schema of a member (`"grep"`), a plugin
#' function (`"<ns>/<name>"`) or an MCP tool (`"<server>/<tool>"`), else the R help page; budgeted
#' @noRd
member_help = function(name, package = NULL, budget = 800L) {
  check_string(name, "name")
  check_string(package, "package", null = TRUE)
  check_number(budget, "budget", min = 20)
  sid = ns_session_id()
  lines = NULL
  if (is.null(package)) {
    spec = if (grepl("/", name, fixed = TRUE)) {
      registry_get("tool", name, session = sid)
    } else {
      ns_member_spec(name, sid)
    }
    if (!is.null(spec)) lines = ns_tool_help(spec)
    mcp = get0("mcp", envir = ns_providers, inherits = FALSE)
    if (is.null(lines) && grepl("/", name, fixed = TRUE) && is.function(mcp)) {
      m = tryCatch(mcp(c("mcp", strsplit(name, "/", fixed = TRUE)[[1L]])), error = function(e) NULL)
      if (is.function(m) && is.list(attr(m, "spec"))) lines = ns_tool_help(attr(m, "spec"))
    }
  }
  if (is.null(lines)) lines = ns_r_help(name, package)
  shown = budget_head(lines, budget, "prose")
  more = if (shown$omitted > 0L) paste0("[... ", shown$omitted, " more lines of help not shown]")
  new_gptr_text(c(shown$lines, more))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 126 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/tool-namespace.R tests/testthat/test-tool-namespace.R
git commit -m "feat(tools): add the plugin catalog, BM25 search and peter\$help()"
```

### Task 10: Members, direct-tool executes, risk and `builtin:tools`

**Files:** Modify: `R/tool-namespace.R` (append part 4 of 4); Test: `tests/testthat/test-tool-namespace.R` (append part 4 of 4).

This task completes `builtin:tools` (04 §7.10 `builtin_tools(gptr)`). **Members** (04 §9.4): `peter$read()` returns `gptr_lines` and attaches an image block to the running `r` result; `peter$write()` returns the absolute path invisibly; `peter$grep()` and `peter$ls()` also accept the direct tools' argument names (`ignoreCase`, `literal`, `limit`) through `...`: the same spec carries both forms (IC-37) and P02's validator requires `fun`'s formals to cover the schema's properties unless `fun` has `...` (04 §6.8), while the member keeps the R names of 04 §9.4 (`ignore_case`, `fixed`); `peter$out(id, stream, lines)` returns the stored text through P01's `out_get()` (session store, process store, spill file; IC-71), accepting the `lines` list a validated nested input carries; `peter$plot(which = NULL, width = 1000L, height = 700L)` attaches the current device's plot through P09's `plot_png()` or stored plot `which` of the last `r` result (the PNGs listed in its `details$plot_files`/`details$plot_index`, IC-67). **Direct-tool executes** return Pi's texts (04 §9.2 "Result texts"; `Successfully wrote to <path>`, `Successfully replaced N block(s) in <path>.`, the read text, `grep`/`find`/`ls` texts of Task 7); called as a nested member call of the same session's running `r` evaluation, the same execute returns the member's R value with a one-line summary instead (that is how `dispatch_nested()` obtains the value). `describe` as a nested call records only the gate (the member computes the value itself, rule R1). **Risk** (04 §9.4, IC-54): reads are level 0 in the project root and for skill pseudo-paths, 1 outside, 2 for protected, critical and control paths; writes are 2 in the project or `tempdir()`, 3 outside, protected or `instructions`, 4 for `control` and critical paths; an envelope's paths count too; `grep`/`find`/`ls` are 0 in the project and at most 1. **Specs**: one spec per capability (IC-37) with Pi's descriptions and schemas byte for byte (04 §9.2), the `<tools>` snippets of 03 §7.3 / 04 §9.3, the `<rules>` `guidelines` of 03 §7.3 (IC-68), `execution = "sequential"` for file tools, `annotations = list(read_only = TRUE)` for read-only ones, and `record = FALSE` for `help`, `search`, `describe`, `plot`, `out` (IC-48). `builtin_tools()` also registers the `<r_session>` fragments `helpers` (order 10) and `out` (order 20), the `plugins` section (T1, order 860, budget 1,500, text `ns_plugins_section`) and the `members` `search_source`; the file ends with the `on_load()` declarations of the built-in and of the services `ns.resolve`, `ns.names` and `search.sources` (owned by `builtin:tools`, IC-34).

The tests check the specs against 04 §9.2 and against P07's stand-ins in `tests/testthat/fixtures/bench/prefix-baseline.json` (P07 copied 04's texts there, so P10's texts must reproduce them byte for byte), acceptance 3 (`peter$nope` lists the members; completion lists `read`, `grep`, `find`, `ls`, `help`, `search`, `describe`, `plot`, `out`; member access performs no I/O, measured by tracing base file functions, and opens no connection), acceptance 6 at the tool level (a fuzzy edit returns the message, the reason line and a diff of at most 400 tokens; an exact edit the message only) and nested calls validated against each tool's schema exactly as P06 does (`schema_validate()`).

**Interfaces:**
- Consumes (P01, P02, P06, P09; 04 §7.1, §7.2, §7.9): `gptr_tool()`, `gptr_prompt_section(name, text, tier, order, budget, parent)`, `gptr_spec("search_source", name, docs =)`, `gptr_tool_result()`, `out_get(id, stream, lines, session)`, `out_put()` (tests), `plot_png(recorded, width, height, res)`, `block_image()`, `session_data(s)`, `session_live(s)`, `describe_binding(name, envir, budget)`, `path_class(path, root)`, `path_key()`, `project_root()`, `gptr_inform()`, `gptr_opt("plot_res")`, `ext_declare_builtin(name, factory)`, `ext_service_set(name, fun, provided_by, builtin)`, `on_load(expr)`, `schema_validate(schema, input)` (tests), `gptr_registry("tool")` (tests), the exported `peter` gateway (P08, tests), `local_project()` (tests); Tasks 1-9.
- Produces (04 §7.10, §9.4): `builtin_tools(gptr)`; specs `read`, `edit`, `write` (`exposure = "direct"`), `grep`, `find`, `ls` (`exposure = "r"`, promoted to direct tools by the `extended` preset), each with `execute` and `fun`; members `help`, `search`, `describe`, `plot`, `out` (`exposure = "r"`, `record = FALSE`); prompt sections `helpers`, `out` (`parent = "r_session"`) and `plugins`; the `members` search source; services `ns.resolve`, `ns.names`, `search.sources`; internal for Task 11: `member_plot()`, `ns_last_plots(session)`, `tool_path_risk(path, write = FALSE)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-tool-namespace.R`:

```r
test_that("peter$out() returns stored text from the process store and pages it with lines", {
  id = out_put(sprintf("line %d", 1:50))
  expect_identical(as.character(member_out(id, lines = 2:3)), c("line 2", "line 3"))
  expect_s3_class(member_out(id), "gptr_text")
  expect_identical(length(member_out(id)), 50L)
  expect_error(member_out("o000000"), class = "gptr_error_invalid_argument")
  expect_error(member_out(id, lines = 0), class = "gptr_error_invalid_argument")
})

test_that("peter$plot() attaches the current plot or a stored one to the running r result", {
  expect_null(member_plot())
  withr::local_pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  graphics::plot(1:3)
  n = with_r_call(function() {
    member_plot(width = 800L, height = 600L)
    length(ns_r_call()$images)
  })
  expect_identical(n, 1L)
  td = withr::local_tempdir()
  png_file = file.path(td, "plot4.png")
  writeBin(png1, png_file)
  session = list(id = "s0000000001")
  details = list(plot_index = 1:4, plot_files = c("a.png", "b.png", "c.png", png_file))
  result = list(role = "tool_result", tool_name = "r", details = details)
  local_mocked_bindings(session_data = function(s) {
    list(entries = list(list(type = "message", message = result)))
  })
  img = with_r_call(function() {
    member_plot(which = 4L)
    ns_r_call()$images[[1]]
  }, list(session = session))
  expect_identical(img$mime, "image/png")
  expect_identical(img$width, 1L)
  expect_error(with_r_call(function() member_plot(which = 9L), list(session = session)),
               "No stored plot 9")
})

test_that("file members return R values; an image read inside r is attached", {
  td = withr::local_tempdir()
  writeBin(charToRaw("a\nb\n"), file.path(td, "x.txt"))
  v = member_read(file.path(td, "x.txt"))
  expect_s3_class(v, "gptr_lines")
  expect_null(attr(v, "image_block"))
  writeBin(png1, file.path(td, "i.png"))
  n = with_r_call(function() {
    member_read(file.path(td, "i.png"))
    length(ns_r_call()$images)
  })
  expect_identical(n, 1L)
  out = withVisible(member_write(file.path(td, "y.txt"), "z\n"))
  expect_false(out$visible)
  expect_identical(out$value, resolve_tool_path(file.path(td, "y.txt")))
  p = member_edit(file.path(td, "y.txt"), list(list(oldText = "z", newText = "w")))
  expect_s3_class(p, "gptr_patch")
  expect_identical(p$n_edits, 1L)
  expect_s3_class(member_grep("w", td), "gptr_matches")
  expect_identical(member_find("*.txt", td)$path, c("x.txt", "y.txt"))
  expect_identical(member_ls(td)$path, c("i.png", "x.txt", "y.txt"))
})

test_that("peter$grep() and peter$ls() accept the direct tools' argument names (P02 formals)", {
  td = withr::local_tempdir()
  writeBin(charToRaw("Alpha\nbeta\n"), file.path(td, "a.txt"))
  writeBin(charToRaw("x"), file.path(td, "b.txt"))
  expect_identical(member_grep("alpha", td, ignoreCase = TRUE)$line, 1L)
  expect_identical(nrow(member_grep("a.p", td, literal = TRUE)), 0L)
  expect_error(member_grep("a", td, colour = TRUE), "unused argument(s): colour",
               fixed = TRUE, class = "gptr_error_invalid_argument")
  one = member_ls(td, limit = 1L)
  expect_identical(one$path, "a.txt")
  expect_true(attr(one, "truncated"))
  expect_identical(member_ls(td, limit = 5L)$path, c("a.txt", "b.txt"))
  expect_error(member_ls(td, 1L), class = "gptr_error_invalid_argument")
  expect_false(grepl("...", attr(ns_resolve("grep"), "signature"), fixed = TRUE))
})

test_that("peter$out(lines =) accepts the list that a validated nested input carries", {
  id = out_put(c("l1", "l2", "l3"))
  expect_identical(as.character(member_out(id, lines = list(1, 3))), c("l1", "l3"))
  expect_identical(as.character(member_out(id, lines = 2L)), "l2")
  expect_error(member_out(id, lines = 0), class = "gptr_error_invalid_argument")
})

# A stand-in for P06's dispatch_nested(): validates the input against the tool's schema as P06
# does (schema_validate(), P01), runs the tool's execute and returns its value
local_nested_dispatch = function(seen = new.env(), .env = parent.frame()) {
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$name = name
    seen$input = input
    tool = registry_get("tool", name)
    v = schema_validate(tool$parameters, input)
    if (!v$ok) gptr_abort(paste(v$errors, collapse = "; "), "tool", tool = name, status = "invalid")
    res = tool$execute(v$input, ctx)
    if (isTRUE(res$is_error)) gptr_abort(ns_result_text(res), "tool", tool = name, status = "error")
    res$value
  }, .env = .env)
  seen
}

caps = c("read", "edit", "write", "grep", "find", "ls")
members = c(caps, "help", "search", "describe", "plot", "out")

test_that("builtin:tools registers one spec per capability, direct and member form (IC-37)", {
  reg = gptr_registry("tool")
  for (cap in caps) {
    rows = reg[reg$name == cap & reg$source == "builtin:tools", , drop = FALSE]
    expect_identical(nrow(rows), 1L, label = cap)
    spec = registry_get("tool", cap)
    expect_true(is.function(spec$execute) && is.function(spec$fun), label = cap)
    expect_identical(attr(ns_resolve(cap), "spec"), spec, label = cap)
  }
  expect_identical(vapply(caps, function(n) registry_get("tool", n)$exposure, ""),
                   c(read = "direct", edit = "direct", write = "direct", grep = "r", find = "r",
                     ls = "r"))
  expect_true(all(members %in% ns_names("")))
  expect_identical(vapply(members, function(n) isTRUE(registry_get("tool", n)$record), NA),
                   stats::setNames(!(members %in% c("help", "search", "describe", "plot", "out")),
                                   members))
  expect_identical(registry_get("tool", "read")$guidelines,
                   "Use read to examine files instead of readLines() or cat() in r.")
  expect_identical(registry_get("tool", "write")$guidelines,
                   "Use write only for new files or complete rewrites.")
  expect_identical(length(registry_get("tool", "edit")$guidelines), 4L)
  expect_identical(registry_get("tool", "edit")$guidelines[1],
                   "Use edit for precise changes (edits[].oldText must match exactly)")
  snippets = c(
    read = "Read file contents",
    edit = paste("Make precise file edits with exact text replacement, including multiple",
                 "disjoint edits in one call"),
    write = "Create or overwrite files",
    grep = "Search file contents for patterns (respects .gitignore)",
    find = "Find files by glob pattern (respects .gitignore)",
    ls = "List directory contents"
  )
  expect_identical(vapply(caps, function(n) registry_get("tool", n)$snippet, ""), snippets)
})

test_that("the direct schemas serialise byte for byte as contract section 9.2 (Pi's strings)", {
  wire = function(n) {
    spec = registry_get("tool", n)
    json_encode(list(name = spec$name, description = spec$description,
                     input_schema = spec$parameters))
  }
  write_json = paste0(
    "{\"name\":\"write\",\"description\":\"Write content to a file. Creates the file if it ",
    "doesn't exist, overwrites if it does. Automatically creates parent directories.\",",
    "\"input_schema\":{\"type\":\"object\",\"required\":[\"path\",\"content\"],",
    "\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path to the file to write ",
    "(relative or absolute)\"},\"content\":{\"type\":\"string\",\"description\":\"Content to ",
    "write to the file\"}}}}"
  )
  expect_identical(wire("write"), write_json)
  ls_json = paste0(
    "{\"name\":\"ls\",\"description\":\"List directory contents. Returns entries sorted ",
    "alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to ",
    "500 entries or 50KB (whichever is hit first).\",\"input_schema\":{\"type\":\"object\",",
    "\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Directory to list ",
    "(default: current directory)\"},\"limit\":{\"type\":\"number\",\"description\":\"Maximum ",
    "number of entries to return (default: 500)\"}}}}"
  )
  expect_identical(wire("ls"), ls_json)
  expect_match(wire("read"), "\"required\":[\"path\"],\"properties\":{\"path\":", fixed = TRUE)
  expect_match(wire("edit"),
               "\"items\":{\"type\":\"object\",\"required\":[\"oldText\",\"newText\"]",
               fixed = TRUE)
})

test_that("the specs reproduce P07's stand-ins byte for byte (prefix-baseline.json)", {
  sb = jsonlite::fromJSON(test_path("fixtures", "bench", "prefix-baseline.json"),
                          simplifyVector = FALSE)$standins
  for (t in sb$tools) {
    if (!(t$name %in% caps)) next
    spec = registry_get("tool", t$name)
    expect_identical(spec$description, t$description, label = t$name)
    expect_identical(json_encode(spec$parameters), json_encode(t$input_schema), label = t$name)
    expect_identical(spec$snippet, t$snippet, label = t$name)
    expect_identical(as.character(spec$guidelines), as.character(unlist(t$guidelines)),
                     label = t$name)
  }
  secs = registry_all("prompt_section")
  for (f in sb$fragments[1:2]) {
    mine = Filter(function(s) identical(s$name, f$name) && identical(s$parent, f$parent), secs)
    expect_identical(length(mine), 1L, label = f$name)
    expect_identical(mine[[1L]]$text, f$text, label = f$name)
    expect_identical(as.integer(mine[[1L]]$order), as.integer(f$order), label = f$name)
  }
})

test_that("builtin:tools registers fragments, the plugins section, a search source, services", {
  secs = registry_all("prompt_section")
  frag = Filter(function(s) identical(s$parent, "r_session") && s$name %in% c("helpers", "out"),
                secs)
  expect_identical(unname(vapply(frag, function(s) as.integer(s$order), 0L)), c(10L, 20L))
  helpers = paste(
    "- Helpers are R functions on the peter object and return R values: peter$grep(pattern,",
    "path), peter$find(pattern, path, sort), peter$ls(path), peter$describe(x).",
    "peter$search(\"words\") and peter$help(name) find more."
  )
  out = paste(
    "- Long output is cut to its head and tail; the notice names peter$out(id) for the rest.",
    "Use peter$out(), peter$help(), peter$search() and peter$plot() only with record = false."
  )
  expect_identical(unname(vapply(frag, function(s) s$text, "")), c(helpers, out))
  plugins = Filter(function(s) identical(s$name, "plugins"), secs)[[1L]]
  expect_identical(plugins$tier, "T1")
  expect_identical(plugins$order, 860L)
  expect_identical(plugins$budget, 1500L)
  expect_true(is.function(plugins$text))
  expect_true(is.function(registry_get("search_source", "members")$docs))
  expect_identical(ext_service_get("ns.resolve"), ns_resolve)
  expect_identical(ext_service_get("ns.names"), ns_names)
  expect_identical(ext_service_get("search.sources"), search_sources)
})

# Number of calls of base file-system functions made while expr_fun() runs (traced, then untraced)
count_io = function(expr_fun) {
  counter = new.env()
  counter$n = 0L
  bump = function() {
    counter$n = counter$n + 1L
  }
  fns = c("file", "readLines", "readBin", "readChar", "list.files", "file.exists", "dir.exists",
          "file.info")
  for (f in fns) suppressMessages(trace(f, tracer = bquote(.(bump)()), print = FALSE,
                                        where = baseenv()))
  on.exit(for (f in fns) suppressMessages(untrace(f, where = baseenv())), add = TRUE)
  expr_fun()
  counter$n
}

test_that("peter$nope lists the members; completion lists the built-in members (acceptance 3)", {
  cnd = tryCatch(peter$nope, error = identity)
  expect_s3_class(cnd, "gptr_error_unknown_member")
  expect_identical(cnd$name, "nope")
  expect_true(all(members %in% cnd$available))
  expect_true(all(members %in% utils::.DollarNames(peter, "")))
  expect_identical(utils::.DollarNames(peter, "^gr"), "grep")
  expect_s3_class(peter$grep, "gptr_member")
  expect_identical(attr(peter[["read"]], "spec"), registry_get("tool", "read"))
})

test_that("accessing a member performs no I/O and opens no connection", {
  cons = nrow(showConnections())
  n = count_io(function() {
    for (m in members) ns_resolve(m)
    ns_names("")
    peter$grep
    peter[["read"]]
  })
  expect_identical(n, 0L)
  expect_identical(nrow(showConnections()), cons)
  expect_gt(count_io(function() file.exists(tempdir())), 0L)
})

test_that("direct tools return Pi's texts", {
  td = withr::local_tempdir()
  f = file.path(td, "a.R")
  r = tool_write_execute(list(path = f, content = "x = 1\ny = 2\n"), NULL)
  expect_identical(ns_result_text(r), paste0("Successfully wrote to ", f))
  expect_identical(r$details$created, TRUE)
  r = tool_read_execute(list(path = f), NULL)
  expect_identical(ns_result_text(r), "x = 1\ny = 2\n")
  expect_identical(r$details$lines_total, 3L)
  r = tool_edit_execute(list(path = f, edits = list(list(oldText = "y = 2", newText = "y = 3"))),
                        NULL)
  expect_identical(ns_result_text(r), paste0("Successfully replaced 1 block(s) in ", f, "."))
  expect_s3_class(r$value, "gptr_patch")
  r = tool_edit_execute(list(path = f, oldText = "x = 1", newText = "x = 0"), NULL)
  expect_identical(rawToChar(readBin(f, "raw", 100)), "x = 0\ny = 3\n")
  env = paste0("*** Begin Patch\n*** Update File: ", f, "\n@@\n-y = 3\n+y = 4\n*** End Patch")
  r = tool_edit_execute(list(path = "ignored", edits = env), NULL)
  expect_match(ns_result_text(r), "^Applied patch: 1 file\\(s\\) changed\\.")
  dir.create(file.path(td, "sub"))
  writeBin(charToRaw("NEEDLE here\n"), file.path(td, "sub", "b.txt"))
  expect_identical(ns_result_text(tool_grep_execute(list(pattern = "needle", path = td,
                                                         ignoreCase = TRUE), NULL)),
                   "sub/b.txt:1: NEEDLE here")
  expect_identical(ns_result_text(tool_grep_execute(list(pattern = "e.h", path = td,
                                                         literal = TRUE), NULL)),
                   "No matches found")
  expect_identical(ns_result_text(tool_find_execute(list(pattern = "*", path = td), NULL)),
                   "a.R\nsub/\nsub/b.txt")
  expect_identical(ns_result_text(tool_ls_execute(list(path = td, limit = 1), NULL)),
                   "a.R\n\n[1 entries limit reached. Use limit=2 for more]")
})

test_that("a fuzzy edit returns the message and a diff of at most 400 tokens (acceptance 6)", {
  td = withr::local_tempdir()
  f = file.path(td, "fuzzy.R")
  body = paste0(paste(sprintf("v%03d = %d   ", 1:300, 1:300), collapse = "\n"), "\n")
  writeBin(charToRaw(body), f)
  fuzzy = list(list(oldText = "v150 = 150\nv151 = 151", newText = "v150 = 0\nv151 = 0"))
  txt = ns_result_text(tool_edit_execute(list(path = f, edits = fuzzy), NULL))
  lines = strsplit(txt, "\n")[[1L]]
  expect_identical(lines[1], paste0("Successfully replaced 1 block(s) in ", f, "."))
  expect_identical(lines[2], "[matched after whitespace, quote or dash normalisation]")
  expect_true(any(startsWith(lines, "@@")))
  expect_lte(est_tokens(lines[-(1:2)], "code"), 400)
  g = file.path(td, "exact.R")
  writeBin(charToRaw("a = 1\n"), g)
  exact = list(list(oldText = "a = 1", newText = "a = 2"))
  expect_identical(ns_result_text(tool_edit_execute(list(path = g, edits = exact), NULL)),
                   paste0("Successfully replaced 1 block(s) in ", g, "."))
})

test_that("inside r members return R values through the gate; describe passes labels (R1)", {
  td = withr::local_tempdir()
  writeBin(charToRaw("needle one\nhay\n"), file.path(td, "x.txt"))
  seen = local_nested_dispatch()
  ctx = list(session = NULL, tag = "ctx")
  m = with_r_call(function() ns_resolve("grep")("needle", path = td), ctx)
  expect_s3_class(m, "gptr_matches")
  expect_identical(seen$name, "grep")
  expect_identical(seen$input, list(pattern = "needle", path = td))
  v = with_r_call(function() withVisible(ns_resolve("write")(file.path(td, "y.txt"), "w\n")), ctx)
  expect_false(v$visible)
  expect_identical(v$value, resolve_tool_path(file.path(td, "y.txt")))
  d = with_r_call(function() ns_resolve("describe")(mtcars, budget = 60L), ctx)
  expect_identical(seen$name, "describe")
  expect_identical(seen$input, list(x = "mtcars", budget = 60L))
  expect_identical(as.character(d), gptr_describe(mtcars, budget = 60L))
  h = with_r_call(function() ns_resolve("help")("grep"), ctx)
  expect_s3_class(h, "gptr_text")
  expect_identical(seen$input, list(name = "grep"))
  expect_error(with_r_call(function() ns_resolve("read")(file.path(td, "nope.txt")), ctx),
               class = "gptr_error")
})

test_that("inside r an envelope, member argument names and out lines pass the schema check", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  writeBin(charToRaw("x = 1\nNeedle\n"), file.path(td, "a.R"))
  seen = local_nested_dispatch()
  ctx = list(session = NULL)
  env = "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 2\n*** End Patch"
  p = with_r_call(function() ns_resolve("edit")("a.R", env), ctx)
  expect_s3_class(p, "gptr_patch")
  expect_identical(seen$input, list(path = "a.R", edits = list(), patch = env))
  expect_identical(rawToChar(readBin(file.path(td, "a.R"), "raw", 100)), "x = 2\nNeedle\n")
  m = with_r_call(function() ns_resolve("grep")("needle", ignore_case = TRUE, output = "files"),
                  ctx)
  expect_s3_class(m, "gptr_files")
  expect_identical(m$path, "a.R")
  id = out_put(c("l1", "l2", "l3"))
  o = with_r_call(function() ns_resolve("out")(id, lines = c(1, 3)), ctx)
  expect_identical(as.character(o), c("l1", "l3"))
})

test_that("risk levels follow contract 9.4 and the control and instructions classes (IC-54)", {
  root = local_project(files = list("R/a.R" = "x = 1", "AGENTS.md" = "rules"))
  lvl = function(fun, path) fun(list(path = path), NULL)$level
  expect_identical(lvl(tool_risk_read, "R/a.R"), 0L)
  expect_identical(lvl(tool_risk_read, "skill:demo/SKILL.md"), 0L)
  expect_identical(lvl(tool_risk_read, file.path(R.home(), "elsewhere.txt")), 1L)
  expect_identical(lvl(tool_risk_read, ".env"), 2L)
  expect_identical(lvl(tool_risk_write, "R/a.R"), 2L)
  expect_identical(lvl(tool_risk_write, tempfile()), 2L)
  expect_identical(lvl(tool_risk_write, "AGENTS.md"), 3L)
  expect_identical(lvl(tool_risk_write, file.path(R.home(), "elsewhere.txt")), 3L)
  expect_identical(lvl(tool_risk_write, ".gptr/settings.json"), 4L)
  expect_identical(tool_risk_write(list(path = ".gptr/settings.json"), NULL)$categories, "control")
  expect_identical(tool_risk_write(list(path = "AGENTS.md"), NULL)$categories, "instructions")
  env = "*** Begin Patch\n*** Add File: .gptr/mcp.json\n+{}\n*** End Patch"
  r = tool_risk_write(list(path = "R/a.R", edits = env), NULL)
  expect_identical(r$level, 4L)
  expect_identical(sort(r$paths), sort(c("R/a.R", ".gptr/mcp.json")))
  expect_identical(lvl(tool_risk_search, "."), 0L)
  expect_identical(lvl(tool_risk_search, ".env"), 1L)
  expect_identical(tool_risk_none(list(), NULL)$level, 0L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 50 | WARN 0 | SKIP 0 | PASS 129 ]`; the earlier tests pass, and the new ones error with `could not find function "member_out"` (or `"member_plot"`, `"member_read"`, `"member_grep"`, `"tool_write_execute"`, `"tool_risk_read"`) or fail because `registry_get("tool", "read")` is `NULL` and `peter$nope` signals `gptr_error_not_available` (the `ns.resolve` service is not registered yet).

- [ ] **Step 3: Write the implementation**

Append to `R/tool-namespace.R`:

```r
#' The plots of the session's last completed `r` result: `list(index, path)` from its
#' `details$plot_index` and `details$plot_files` (every rendered plot, attached or stored)
#' @noRd
ns_last_plots = function(session) {
  none = list(index = integer(), path = character())
  if (is.null(session)) return(none)
  for (e in rev(session_data(session)$entries %||% list())) {
    m = e$message
    if (identical(e$type, "message") && identical(m$role, "tool_result") &&
          identical(m$tool_name, "r")) {
      return(list(index = as.integer(unlist(m$details$plot_index)),
                  path = as.character(unlist(m$details$plot_files))))
    }
  }
  none
}

#' `peter$plot(which = NULL, width = 1000L, height = 700L)`: attach the current device's plot at
#' that size, or plot `which` of the last `r` result (IC-67: the plots it listed as "not
#' attached"), to the running `r` result; invisible NULL
#' @noRd
member_plot = function(which = NULL, width = 1000L, height = 700L) {
  which = check_number(which, "which", min = 1, int = TRUE, null = TRUE)
  width = check_number(width, "width", min = 64, max = 4000, int = TRUE)
  height = check_number(height, "height", min = 64, max = 4000, int = TRUE)
  rc = ns_r_call()
  if (is.null(rc)) {
    gptr_inform("peter$plot() attaches a plot to a running r call; there is none here.", "notice")
    return(invisible(NULL))
  }
  block = if (is.null(which)) {
    if (grDevices::dev.cur() == 1L) {
      gptr_abort("There is no plot to attach: draw one first.", "invalid_argument", arg = "which",
                 expected = "a plot on the current device")
    }
    plot_png(grDevices::recordPlot(), width = width, height = height,
             res = as.integer(gptr_opt("plot_res")))
  } else {
    plots = ns_last_plots(if (is.null(rc$ctx)) NULL else rc$ctx$session)
    k = match(which, plots$index)
    if (is.na(k) || !file.exists(plots$path[k])) {
      gptr_abort(paste0("No stored plot ", which, ": the last r result made ",
                        length(plots$index), " plot(s)."),
                 "invalid_argument", arg = "which", expected = "the number of a stored plot")
    }
    b = read_raw(plots$path[k])
    dims = image_dims(b, "image/png")
    block_image(base64_raw(b), mime = "image/png", source = "plot", width = as.integer(dims[1]),
                height = as.integer(dims[2]))
  }
  if (is.null(block)) {
    gptr_abort("The plot could not be rendered to PNG.", "invalid_argument", arg = "which",
               expected = "a plot that the PNG device can draw")
  }
  r_call_attach_image(block)
  invisible(NULL)
}

#' `peter$out(id, stream = c("stdout", "stderr"), lines = NULL)`: the stored full text of a
#' truncated result (the session's out store, the process store, then the spill file; P01
#' out_get())
#' @noRd
member_out = function(id, stream = c("stdout", "stderr"), lines = NULL) {
  check_string(id, "id")
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  if (is.list(lines)) lines = unlist(lines)
  if (!is.null(lines) && (!is.numeric(lines) || anyNA(lines) || any(lines < 1))) {
    gptr_abort("`lines` must be positive line numbers.", "invalid_argument", arg = "lines",
               expected = "positive line numbers")
  }
  s = ns_current_session()
  live = if (is.null(s)) NULL else session_live(s)
  new_gptr_text(out_get(id, stream = stream, lines = lines, session = live))
}

#' `peter$read(path, offset = NULL, limit = NULL)`: a `gptr_lines` value; an image is attached to
#' the running `r` result
#' @noRd
member_read = function(path, offset = NULL, limit = NULL) {
  v = read_lines_value(path, offset, limit)
  img = attr(v, "image_block")
  if (!is.null(img)) r_call_attach_image(img)
  attr(v, "image_block") = NULL
  v
}

#' `peter$write(path, content)`: the absolute path written, invisibly
#' @noRd
member_write = function(path, content) invisible(write_file(path, content)$details$path)

#' Extra arguments a built-in member accepts through `...`: the direct form's (Pi's) names
#' @noRd
ns_member_dots = function(dots, allowed, member) {
  nms = names(dots) %||% rep("", length(dots))
  bad = nms[!(nms %in% allowed)]
  if (length(bad)) {
    shown = if (any(nzchar(bad))) paste(bad[nzchar(bad)], collapse = ", ") else "unnamed"
    gptr_abort(paste0("peter$", member, "(): unused argument(s): ", shown, "."),
               "invalid_argument", arg = "...",
               expected = paste0("the arguments of peter$", member, "()"))
  }
  dots
}

#' `peter$grep()` (contract section 9.4); `ignoreCase` and `literal` (the direct tool's names) are
#' accepted as aliases of `ignore_case` and `fixed`
#' @noRd
member_grep = function(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE,
                       context = 0L, limit = 100L, output = c("content", "files", "count"),
                       sort = c("path", "count", "mtime"), ...) {
  dots = ns_member_dots(list(...), c("ignoreCase", "literal"), "grep")
  if (!is.null(dots$ignoreCase)) ignore_case = dots$ignoreCase
  if (!is.null(dots$literal)) fixed = dots$literal
  search_grep(pattern, path = path, glob = glob, ignore_case = ignore_case, fixed = fixed,
              context = context, limit = limit, output = output, sort = sort)
}

#' `peter$find()` (contract section 9.4)
#' @noRd
member_find = function(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"),
                       type = "file", limit = 1000L) {
  search_find(pattern, path = path, sort = sort, type = type, limit = limit)
}

#' `peter$ls()` (contract section 9.4); `limit` (the direct tool's argument) keeps the first entries
#' @noRd
member_ls = function(path = ".", sort = c("name", "mtime", "size"), long = FALSE, ...) {
  dots = ns_member_dots(list(...), "limit", "ls")
  f = search_ls(path, sort = sort, long = long)
  if (is.null(dots$limit)) return(f)
  limit = check_number(dots$limit, "limit", min = 1, int = TRUE)
  if (nrow(f) <= limit) return(f)
  keep = seq_len(limit)
  out = f[keep, , drop = FALSE]
  rownames(out) = NULL
  structure(out, class = class(f), root = attr(f, "root"), long = long, truncated = TRUE,
            limit = limit, slash = attr(f, "slash")[keep])
}

# ---- tool executes: the direct-tool form and nested member calls ---------------------------------

#' Is this execute a nested member call of the running `r` evaluation of the same session (not a
#' direct tool call, and not a direct tool of a sub-agent started from that evaluation)?
#' @noRd
member_nested = function(ctx) {
  rc = ns_r_call()
  !is.null(rc) && !is.null(ctx) && identical(rc$ctx, ctx)
}

#' One-line summary of a member value (the text of a nested result; dispatch_nested() records it)
#' @noRd
ns_value_summary = function(name, value) {
  shape = if (is.null(value)) {
    "no value"
  } else if (is.data.frame(value)) {
    paste0(nrow(value), " rows")
  } else {
    paste0("<", class(value)[1L], "> length ", length(value))
  }
  paste0(name, ": ", shape)
}

#' The tool result of a nested member call: a summary text and the R value
#' @noRd
ns_value_result = function(name, value) {
  gptr_tool_result(ns_value_summary(name, value), value = value)
}

#' Text of a member value for a direct tool result (help, search, out as direct tools)
#' @noRd
ns_value_text = function(value) {
  if (is.null(value)) return("(no output)")
  if (is.data.frame(value)) {
    return(paste(utils::capture.output(print(value, row.names = FALSE)), collapse = "\n"))
  }
  paste(as.character(value), collapse = "\n")
}

#' @noRd
tool_read_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("read", do.call(member_read, as.list(input))))
  rf = read_file(input$path, offset = input$offset, limit = input$limit)
  images = if (is.null(rf$image)) NULL else list(rf$image)
  gptr_tool_result(rf$text, images = images, details = rf$details)
}

#' @noRd
tool_write_execute = function(input, ctx) {
  wf = write_file(input$path, input$content)
  gptr_tool_result(paste0("Successfully wrote to ", input$path), details = wf$details,
                   value = wf$details$path)
}

#' @noRd
tool_edit_execute = function(input, ctx) {
  edits = input$patch %||% input$edits
  if (is.null(edits) && !is.null(input$oldText)) {
    edits = list(list(oldText = input$oldText, newText = input$newText))
  }
  routed = edit_route_document(input$path, edits, if (is.null(ctx)) NULL else ctx$session)
  if (!is.null(routed)) {
    routed$value = ns_routed_patch(input$path, routed)
    return(routed)
  }
  ed = edit_file(input$path, edits, replace_all = isTRUE(input$replace_all %||% input$replaceAll))
  value = new_gptr_patch(input$path, ed$message, ed$diff, ed$details$n_edits, ed$fuzzy)
  gptr_tool_result(edit_result_text(ed), details = ed$details, value = value)
}

#' @noRd
tool_grep_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("grep", do.call(member_grep, as.list(input))))
  m = search_grep(input$pattern, path = input$path %||% ".", glob = input$glob,
                  ignore_case = isTRUE(input$ignoreCase), fixed = isTRUE(input$literal),
                  context = as.integer(input$context %||% 0L),
                  limit = max(1L, as.integer(input$limit %||% grep_default_limit)))
  gptr_tool_result(grep_tool_text(m), value = m,
                   details = list(matches = nrow(m), truncated = isTRUE(attr(m, "truncated"))))
}

#' @noRd
tool_find_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("find", do.call(member_find, as.list(input))))
  f = search_find(input$pattern, path = input$path %||% ".", type = "any",
                  limit = max(1L, as.integer(input$limit %||% find_default_limit)))
  gptr_tool_result(find_tool_text(f), value = f,
                   details = list(results = nrow(f), truncated = isTRUE(attr(f, "truncated"))))
}

#' @noRd
tool_ls_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("ls", do.call(member_ls, as.list(input))))
  f = search_ls(input$path %||% ".")
  limit = max(1L, as.integer(input$limit %||% ls_default_limit))
  gptr_tool_result(ls_tool_text(f, limit = limit), value = f, details = list(entries = nrow(f)))
}

#' Execute of a member-only capability (help, search, out): call the member function with the input
#' @noRd
member_execute = function(fun, name) {
  force(fun)
  force(name)
  function(input, ctx) {
    value = do.call(fun, as.list(input))
    text = if (member_nested(ctx)) ns_value_summary(name, value) else ns_value_text(value)
    gptr_tool_result(text, value = value)
  }
}

#' `describe`: nested calls only record the gate (the member computes the value locally, rule R1);
#' as a direct tool it describes the binding named `x` in the session's environment
#' @noRd
tool_describe_execute = function(input, ctx) {
  if (member_nested(ctx)) {
    return(gptr_tool_result(paste0("describe: ", as.character(input$x)[1L]), value = NULL))
  }
  envir = if (is.null(ctx)) NULL else ctx$envir
  if (!is.environment(envir)) {
    gptr_abort("describe needs the session's environment.", "invalid_argument", arg = "x",
               expected = "the name of an object in the session")
  }
  budget = as.integer(input$budget %||% 150L)
  lines = describe_binding(as.character(input$x), envir, budget = budget)
  gptr_tool_result(paste(lines, collapse = "\n"))
}

#' @noRd
tool_plot_execute = function(input, ctx) {
  member_plot(input$which, input$width %||% 1000L, input$height %||% 700L)
  gptr_tool_result("plot attached to the r result", value = NULL)
}

# ---- risk (contract section 9.4; control and instructions path classes, IC-54) -------------------

#' Level and category of one path. Reads: 0 in the project (the project root included) and for skill
#' pseudo-paths, 1 outside, 2 for protected, critical and control paths. Writes: 2 in the project or
#' tempdir(), 3 outside, protected or instructions, 4 control or critical.
#' @noRd
tool_path_risk = function(path, write = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    return(list(level = 3L, category = "unknown"))
  }
  if (startsWith(path, "skill:")) {
    return(list(level = if (write) 3L else 0L, category = "instructions"))
  }
  abs = tryCatch(resolve_tool_path(path), error = function(e) NA_character_)
  cls = if (is.na(abs)) "unknown" else as.character(path_class(abs))[1L]
  if (!write && identical(cls, "critical") && identical(path_key(abs), path_key(project_root()))) {
    cls = "workspace"
  }
  if (!write) {
    level = switch(cls, workspace = , instructions = 0L,
                   protected = , critical = , control = 2L, 1L)
    return(list(level = level, category = "read"))
  }
  level = switch(cls, workspace = , temp = 2L, control = , critical = 4L, 3L)
  category = switch(cls, control = "control", instructions = "instructions", critical = "critical",
                    protected = "protected", "write")
  list(level = level, category = category)
}

#' Risk of a set of paths: `list(level, categories, paths)`
#' @noRd
tool_paths_risk = function(paths, write = FALSE) {
  paths = as.character(unlist(paths))
  if (!length(paths)) {
    return(list(level = if (write) 2L else 0L, categories = if (write) "write" else "read",
                paths = character()))
  }
  rs = lapply(paths, tool_path_risk, write = write)
  list(level = max(vapply(rs, function(r) as.integer(r$level), 0L)),
       categories = unique(vapply(rs, function(r) r$category, "")), paths = paths)
}

#' @noRd
tool_risk_read = function(input, ctx) tool_paths_risk(input$path, write = FALSE)

#' @noRd
tool_risk_write = function(input, ctx) {
  paths = input$path
  env = edit_envelope_of(input$patch %||% input$edits)
  if (!is.null(env)) paths = unique(c(paths, patch_paths(env)))
  tool_paths_risk(paths, write = TRUE)
}

#' @noRd
tool_risk_search = function(input, ctx) {
  r = tool_paths_risk(input$path %||% ".", write = FALSE)
  r$level = min(r$level, 1L)
  r
}

#' @noRd
tool_risk_none = function(input, ctx) list(level = 0L, categories = "read", paths = character())

# ---- the specs of builtin:tools (contract sections 9.2 and 9.4; Pi's strings, MIT, 01 section 3)

tool_read_description = paste(
  "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp).",
  "Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB",
  "(whichever is hit first). Use offset/limit for large files. When you need the full file,",
  "continue with offset until complete."
)
tool_edit_description = paste(
  "Edit a single file using exact text replacement. Every edits[].oldText must match a unique,",
  "non-overlapping region of the original file. If two changes affect the same block or nearby",
  "lines, merge them into one edit instead of emitting overlapping edits. Do not include large",
  "unchanged regions just to connect distant changes."
)
tool_write_description = paste(
  "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
  "Automatically creates parent directories."
)
tool_grep_description = paste(
  "Search file contents for a pattern. Returns matching lines with file paths and line numbers.",
  "Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first).",
  "Long lines are truncated to 500 chars."
)
tool_find_description = paste(
  "Search for files by glob pattern. Returns matching file paths relative to the search",
  "directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit",
  "first)."
)
tool_ls_description = paste(
  "List directory contents. Returns entries sorted alphabetically, with '/' suffix for",
  "directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit",
  "first)."
)

#' A JSON Schema property
#' @noRd
tool_prop = function(type, description) list(type = type, description = description)

#' A JSON Schema object of properties
#' @noRd
tool_obj = function(required, ...) {
  s = list(type = "object")
  if (length(required)) s$required = I(required)
  s$properties = list(...)
  s
}

tool_read_schema = tool_obj(
  "path",
  path = tool_prop("string", "Path to the file to read (relative or absolute)"),
  offset = tool_prop("number", "Line number to start reading from (1-indexed)"),
  limit = tool_prop("number", "Maximum number of lines to read")
)
tool_edit_item = tool_obj(
  c("oldText", "newText"),
  oldText = tool_prop("string", paste(
    "Exact text for one targeted replacement. It must be unique in the original file and must",
    "not overlap with any other edits[].oldText in the same call."
  )),
  newText = tool_prop("string", "Replacement text for this targeted edit.")
)
tool_edit_schema = tool_obj(
  c("path", "edits"),
  path = tool_prop("string", "Path to the file to edit (relative or absolute)"),
  edits = list(type = "array", items = tool_edit_item, description = paste(
    "One or more targeted replacements. Each edit is matched against the original file, not",
    "incrementally. Do not include overlapping or nested edits. If two changes touch the same",
    "block or nearby lines, merge them into one edit instead."
  ))
)
tool_write_schema = tool_obj(
  c("path", "content"),
  path = tool_prop("string", "Path to the file to write (relative or absolute)"),
  content = tool_prop("string", "Content to write to the file")
)
tool_grep_schema = tool_obj(
  "pattern",
  pattern = tool_prop("string", "Search pattern (regex or literal string)"),
  path = tool_prop("string", "Directory or file to search (default: current directory)"),
  glob = tool_prop("string", "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"),
  ignoreCase = tool_prop("boolean", "Case-insensitive search (default: false)"),
  literal = tool_prop("boolean",
                      "Treat pattern as literal string instead of regex (default: false)"),
  context = tool_prop("number",
                      "Number of lines to show before and after each match (default: 0)"),
  limit = tool_prop("number", "Maximum number of matches to return (default: 100)")
)
tool_find_schema = tool_obj(
  "pattern",
  pattern = tool_prop("string", paste(
    "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"
  )),
  path = tool_prop("string", "Directory to search in (default: current directory)"),
  limit = tool_prop("number", "Maximum number of results (default: 1000)")
)
tool_ls_schema = tool_obj(
  character(),
  path = tool_prop("string", "Directory to list (default: current directory)"),
  limit = tool_prop("number", "Maximum number of entries to return (default: 500)")
)

tool_read_guidelines = "Use read to examine files instead of readLines() or cat() in r."
tool_edit_guidelines = c(
  "Use edit for precise changes (edits[].oldText must match exactly)",
  paste("When changing multiple separate locations in one file, use one edit call with multiple",
        "entries in edits[] instead of multiple edit calls"),
  paste("Each edits[].oldText is matched against the original file, not after earlier edits are",
        "applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit."),
  paste("Keep edits[].oldText as small as possible while still being unique in the file. Do not",
        "pad with large unchanged regions.")
)
tool_write_guidelines = "Use write only for new files or complete rewrites."

# The <r_session> fragments of builtin:tools (architecture section 7.3; IC-68)
r_session_helpers_text = paste(
  "- Helpers are R functions on the peter object and return R values: peter$grep(pattern, path),",
  "peter$find(pattern, path, sort), peter$ls(path), peter$describe(x). peter$search(\"words\") and",
  "peter$help(name) find more."
)
r_session_out_text = paste(
  "- Long output is cut to its head and tail; the notice names peter$out(id) for the rest. Use",
  "peter$out(), peter$help(), peter$search() and peter$plot() only with record = false."
)

# Member-only capabilities: descriptions and schemas
tool_help_description = paste(
  "Show the full schema of a peter member, a plugin function (\"<ns>/<name>\") or an MCP tool",
  "(\"<server>/<tool>\"), or else the R help page of a topic."
)
tool_help_schema = tool_obj(
  "name",
  name = tool_prop("string", "Member, \"<ns>/<name>\", \"<server>/<tool>\" or R topic"),
  package = tool_prop("string", "Package of the R help topic"),
  budget = tool_prop("number", "Token budget (default 800)")
)
tool_search_description = paste(
  "Search peter members, plugin functions, MCP tools and skills by keywords (BM25). Returns name,",
  "kind, signature and score."
)
tool_search_schema = tool_obj(
  "words",
  words = tool_prop("string", "Keywords"),
  limit = tool_prop("number", "Maximum results (default 8)")
)
tool_describe_description = paste(
  "Describe an R object compactly within a token budget (class, shape, columns, values)."
)
tool_describe_schema = tool_obj(
  "x",
  x = list(description = "The object to describe"),
  budget = tool_prop("number", "Token budget (default 150)")
)
tool_plot_description = paste(
  "Attach the current plot, or stored plot `which` of the last r result, at a larger size to the",
  "running r result."
)
tool_plot_schema = tool_obj(
  character(),
  which = tool_prop("number", "Number of a stored plot"),
  width = tool_prop("number", "Width in pixels (default 1000)"),
  height = tool_prop("number", "Height in pixels (default 700)")
)
tool_out_description = paste(
  "Return the full text of a truncated result by the id in its notice, or some of its lines."
)
tool_out_schema = tool_obj(
  "id",
  id = tool_prop("string", "The id named in the truncation notice"),
  stream = list(type = "string", enum = I(c("stdout", "stderr")),
                description = "Which stream (default stdout)"),
  lines = list(type = "array", items = list(type = "number"),
               description = "Line numbers to return")
)

#' The tool specs of builtin:tools: one spec per capability, with a direct and a member form for
#' read, edit, write, grep, find and ls (IC-37), and the members help, search, describe, plot and
#' out (`record = FALSE`, IC-48)
#' @noRd
tool_builtin_specs = function() {
  ro = list(read_only = TRUE)
  edit_snippet = paste("Make precise file edits with exact text replacement, including multiple",
                       "disjoint edits in one call")
  list(
    gptr_tool("read", tool_read_description, parameters = tool_read_schema,
              execute = tool_read_execute, fun = member_read, exposure = "direct",
              execution = "sequential", risk = tool_risk_read, snippet = "Read file contents",
              guidelines = tool_read_guidelines, annotations = ro),
    gptr_tool("edit", tool_edit_description, parameters = tool_edit_schema,
              execute = tool_edit_execute, fun = member_edit, exposure = "direct",
              execution = "sequential", risk = tool_risk_write, snippet = edit_snippet,
              guidelines = tool_edit_guidelines),
    gptr_tool("write", tool_write_description, parameters = tool_write_schema,
              execute = tool_write_execute, fun = member_write, exposure = "direct",
              execution = "sequential", risk = tool_risk_write,
              snippet = "Create or overwrite files", guidelines = tool_write_guidelines),
    gptr_tool("grep", tool_grep_description, parameters = tool_grep_schema,
              execute = tool_grep_execute, fun = member_grep, exposure = "r",
              execution = "sequential", risk = tool_risk_search,
              signature = ns_signature_line("grep", member_grep, tool_grep_description, FALSE),
              snippet = "Search file contents for patterns (respects .gitignore)",
              annotations = ro),
    gptr_tool("find", tool_find_description, parameters = tool_find_schema,
              execute = tool_find_execute, fun = member_find, exposure = "r",
              execution = "sequential", risk = tool_risk_search,
              snippet = "Find files by glob pattern (respects .gitignore)", annotations = ro),
    gptr_tool("ls", tool_ls_description, parameters = tool_ls_schema, execute = tool_ls_execute,
              fun = member_ls, exposure = "r", execution = "sequential", risk = tool_risk_search,
              signature = ns_signature_line("ls", member_ls, tool_ls_description, FALSE),
              snippet = "List directory contents", annotations = ro),
    gptr_tool("help", tool_help_description, parameters = tool_help_schema,
              execute = member_execute(member_help, "help"), fun = member_help, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("search", tool_search_description, parameters = tool_search_schema,
              execute = member_execute(member_search, "search"), fun = member_search,
              exposure = "r", risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("describe", tool_describe_description, parameters = tool_describe_schema,
              execute = tool_describe_execute, fun = member_describe, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("plot", tool_plot_description, parameters = tool_plot_schema,
              execute = tool_plot_execute, fun = member_plot, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("out", tool_out_description, parameters = tool_out_schema,
              execute = member_execute(member_out, "out"), fun = member_out, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro)
  )
}

#' builtin:tools: the file tools and members, their guidelines (for `<rules>`), the `<r_session>`
#' fragments (helpers, out), the `plugins` section and the `members` search source (contract 7.10)
#' @noRd
builtin_tools = function(gptr) {
  for (spec in tool_builtin_specs()) gptr$register(spec)
  gptr$register(gptr_prompt_section("helpers", r_session_helpers_text, tier = "T0", order = 10L,
                                    budget = 300L, parent = "r_session"))
  gptr$register(gptr_prompt_section("out", r_session_out_text, tier = "T0", order = 20L,
                                    budget = 300L, parent = "r_session"))
  gptr$register(gptr_prompt_section("plugins", ns_plugins_section, tier = "T1", order = 860L,
                                    budget = 1500L))
  gptr$register(gptr_spec("search_source", "members", docs = ns_search_docs))
  invisible(NULL)
}

on_load(ext_declare_builtin("tools", builtin_tools))
on_load(ext_service_set("ns.resolve", ns_resolve, provided_by = "P10", builtin = "tools"))
on_load(ext_service_set("ns.names", ns_names, provided_by = "P10", builtin = "tools"))
on_load(ext_service_set("search.sources", search_sources, provided_by = "P10", builtin = "tools"))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 287 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/tool-namespace.R tests/testthat/test-tool-namespace.R
git commit -m "feat(tools): add the peter\$ members, direct tools, risk and builtin:tools"
```

### Task 11: The `r` tool and `builtin:r`

**Files:** Create: `R/tool-r.R`; Test: `tests/testthat/test-tool-r.R`.

The `r` tool of 03 §7.2 and 04 §9.2. Its `parameters` is a function evaluated once at freeze with `ctx$input` (IC-68, IC-69): `record` and `note` only when a document is bound (`ctx$input$document` non-NULL, from P15's `doc.site` service), `timeout` (described `"Seconds; best effort. Default 3600."`) only when no human can answer, giving the four measured variants (189 / 170 / 138 / 119 o200k tokens). The execute evaluates `code` through the session's `evaluator` record (setting `evaluator`, default `r`, IC-69; P09's `eval_r()` when no record exists) in the run's evaluation environment (`run_eval_env(run)`: the plan-mode scratch overlay, IC-15; `ctx$envir` outside a run), formats the model text with P09's `format_eval_result()` within `gptr.r_output_tokens`, adds the images `peter$plot()` and `peter$read()` attached through the r-call marker (at most `gptr.r_max_images` per call, IC-67; the refused ones are named in a final `[k image(s) from peter$plot() or peter$read() not attached: at most n per r call]` line, so a loop over 50 image reads cannot put 50 images into the context), and fills the stable `details` record of 04 §4.4 (`code`, `record`, `note`, `status`, `n_done`, `n_total`, `objects`, `plots`, `warnings` and `error` redacted with the `persist` profile, `changes`, `elapsed`, `out_id`, `spill`, `outputs` (at most `gptr.doc_output_lines` lines of 76 characters per expression, only when recorded), `nested` (filled by P06's `dispatch_nested()`), `bridge`, `artifacts`, `checkpoint`, `value`), plus `plot_files` and `plot_index` for `peter$plot(which)`. Plan mode never records (IC-48). While the evaluation runs, the execute frame binds the r-call marker `gptr_r_call` (Task 1) and two session hooks collect `bridge_call` digests (P22) and `artifact_start` app paths (P23); both hooks are removed on exit. Copy-safety (R2, R3, R8): the frame binds the evaluation environment only while the call runs and resets it before formatting and on exit, creates no closure over it and keeps no value. The risk of an `r` call comes from P11's `risk.classify` service, level 2 before P11 exists.

The end-to-end tests run `peter()` on P01's fake provider through P08, P06, P07 and P09. P11 does not exist yet, so they switch the permission gate off with the documented escape hatch `gptr.unsafe_no_permissions` set outside the run (IC-53). They prove acceptance 4 (model code `peter$grep("x")` evaluated where `peter` is not visible runs through P09's `gptr::` shim, binds nothing in the environment, and the recorded `details$code` keeps `peter$grep("needle")`), acceptance 5 (`gptr_return()`: a 12 MB value held by name, a 200 KB value as a copy, an anonymous value boxed; outside a run it returns its argument invisibly), acceptance 6 (a fuzzy edit returns the message and a diff of at most 400 tokens; an exact edit the message only) and acceptance 7 (the `r` schema frozen without a bound document has no `record`/`note`, and with no human it carries the short `timeout` text).

**Interfaces:**
- Consumes (P01, P02, P06, P07, P09, P11, P15, P22, P23; 04 §7.1-7.9, §7.0): `gptr_tool()`, `ext_declare_builtin()`, `on_load()`, `registry_get("evaluator", name, session)`, `setting_get("evaluator", session, default = "r")`, `hook_add(event, handler, matcher, rank, source, session)`, `hook_remove(id)`, `run_current()`, `run_eval_env(run)`, `session_data(s)`, `eval_r(code, envir, timeout, plots, tee, budget_tokens, guard, rng, record, max_images)`, `format_eval_result(res, budget_tokens)`, `redact_hook(x, profile)`, `gptr_can_prompt()`, `workspace_root(create = FALSE)`, `path_rel()`, `project_root()`, `gptr_opt()`, `as_utf8()`, `check_string()`, `gptr_abort()`, services `doc.site` (P15: `function(session) list(path, format) or NULL`) and `risk.classify` (P11: `function(code, envir = NULL, root = NULL, kind = "r")`); tests: `peter()`, `gptr_return()` (P08), `local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_project()`, `local_gptr_options()` (P01 helpers), `json_encode()`, `schema_validate()`; Task 1: `r_call_new()`; Task 10: `ns_resolve()` (tests).
- Produces (04 §7.10, §9.2, §4.4): `builtin_r(gptr)` registering the direct tool `r` (`execution = "sequential"`, `guidelines` = the three `<rules>` R lines, `snippet` of 04 §9.3); `r_schema(document = FALSE, human = TRUE)`; `r_tool_parameters(ctx)`; `r_tool_execute(input, ctx)` -> `gptr_tool_result` with `out_id`, `spill`, `truncated` set; `r_tool_risk(input, ctx)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-tool-r.R`:

```r
# Tests for R/tool-r.R: the four schema variants (IC-68), evaluation and the details record
# (contract 4.4), record and note, plan mode, images from peter$plot(), bridge and artifact
# collection, risk, and (below) end-to-end runs through peter() on the fake provider: the gptr shim,
# the value policy, nested gating and the fuzzy-edit diff (05 P10 acceptance 4-7).

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# A stand-in for P06's dispatch_nested(): runs the tool's execute with the input and returns its
# value
local_nested_dispatch = function(seen = new.env(), .env = parent.frame()) {
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$name = c(seen$name, name)
    res = registry_get("tool", name)$execute(input, ctx)
    res$value
  }, .env = .env)
  seen
}

test_that("the r schema is frozen in one of four variants (IC-68)", {
  props = function(document, human) names(r_schema(document, human)$properties)
  expect_identical(props(TRUE, FALSE), c("code", "record", "note", "timeout"))
  expect_identical(props(TRUE, TRUE), c("code", "record", "note"))
  expect_identical(props(FALSE, FALSE), c("code", "timeout"))
  expect_identical(props(FALSE, TRUE), "code")
  expect_identical(
    json_encode(r_schema(FALSE, TRUE)),
    paste0("{\"type\":\"object\",\"required\":[\"code\"],\"properties\":{\"code\":",
           "{\"type\":\"string\",\"description\":\"R code to evaluate. May contain several ",
           "expressions.\"}}}")
  )
  expect_identical(r_schema(TRUE, FALSE)$properties$timeout$description,
                   "Seconds; best effort. Default 3600.")
  variant = function(input) names(r_tool_parameters(list(input = input))$properties)
  expect_identical(variant(list(human = TRUE, document = NULL)), "code")
  expect_identical(variant(list(human = FALSE, document = list(path = "a.R"))),
                   c("code", "record", "note", "timeout"))
  spec = registry_get("tool", "r")
  expect_true(is.function(spec$parameters))
  expect_identical(spec$exposure, "direct")
  expect_identical(spec$snippet, paste("Run R code in the user's live session (objects persist;",
                                       "plots come back as images)"))
  expect_identical(length(spec$guidelines), 3L)
  expect_error(ns_resolve("r"), class = "gptr_error_unknown_member")
})

test_that("the r spec reproduces P07's stand-in in each of its four variants (IC-68)", {
  sb = jsonlite::fromJSON(test_path("fixtures", "bench", "prefix-baseline.json"),
                          simplifyVector = FALSE)$standins
  t = Filter(function(x) identical(x$name, "r"), sb$tools)[[1L]]
  spec = registry_get("tool", "r")
  expect_identical(spec$description, t$description)
  expect_identical(spec$snippet, t$snippet)
  expect_identical(as.character(spec$guidelines), as.character(unlist(t$guidelines)))
  for (doc in c(TRUE, FALSE)) {
    for (human in c(TRUE, FALSE)) {
      want = t$input_schema
      want$properties = want$properties[c("code", if (doc) c("record", "note"),
                                          if (!human) "timeout")]
      if (!human) want$properties$timeout$description = sb$r_timeout_short
      expect_identical(json_encode(r_schema(doc, human)), json_encode(want))
    }
  }
})

test_that("the r tool evaluates in ctx$envir outside a run and fills the details record", {
  e = new.env()
  e$keep = 1
  res = r_tool_execute(list(code = "x = 41\nx + 1", note = "one decision"),
                       list(envir = e, session = NULL))
  expect_s3_class(res, "gptr_tool_result")
  expect_false(res$is_error)
  expect_identical(e$x, 41)
  d = res$details
  expect_identical(d$code, "x = 41\nx + 1")
  expect_true(d$record)
  expect_identical(d$note, "one decision")
  expect_identical(d$status, "ok")
  expect_identical(d$n_done, 2L)
  expect_identical(d$n_total, 2L)
  expect_true("x" %in% d$objects$added)
  expect_false("keep" %in% c(d$objects$added, d$objects$modified))
  expect_identical(d$nested, list())
  expect_null(d$value)
  expect_match(ns_result_text(res), "42", fixed = TRUE)
  fields = c("code", "record", "note", "status", "n_done", "n_total", "objects", "plots",
             "warnings", "error", "changes", "elapsed", "out_id", "spill", "outputs", "nested",
             "bridge", "artifacts", "checkpoint", "value")
  expect_true(all(fields %in% names(d)))
})

test_that("an error stops the evaluation and is reported; plan mode never records", {
  e = new.env()
  res = r_tool_execute(list(code = "a = 1\nstop('boom')\nb = 2"), list(envir = e, session = NULL))
  expect_true(res$is_error)
  expect_identical(res$details$status, "error")
  expect_match(res$details$error, "boom", fixed = TRUE)
  expect_false(exists("b", envir = e, inherits = FALSE))
  plan_ctx = list(envir = e, session = NULL, mode = function() "plan")
  expect_false(r_tool_execute(list(code = "1", record = TRUE), plan_ctx)$details$record)
  plain_ctx = list(envir = e, session = NULL)
  expect_false(r_tool_execute(list(code = "1", record = FALSE), plain_ctx)$details$record)
  expect_error(r_tool_execute(list(code = "1"), list(envir = NULL, session = NULL)),
               class = "gptr_error_internal")
})

test_that("images attached by peter$plot() during the evaluation are added to the result", {
  local_nested_dispatch()
  e = new.env()
  withr::local_pdf(NULL)
  grDevices::dev.control(displaylist = "enable")
  code = "graphics::plot(1:3)\nns_resolve(\"plot\")(width = 800L, height = 600L)"
  res = r_tool_execute(list(code = code), list(envir = e, session = NULL))
  imgs = Filter(function(b) identical(b$type, "image"), res$content)
  widths = vapply(imgs, function(b) as.integer(b$width %||% NA_integer_), 0L)
  expect_true(800L %in% widths)
  expect_identical(res$details$plots, length(imgs))
})

test_that("images beyond gptr.r_max_images are not attached and the result names them (IC-67)", {
  local_nested_dispatch()
  local_gptr_options(r_max_images = 2L)
  td = withr::local_tempdir()
  png1 = jsonlite::base64_dec(paste0(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
    "BAEAX+XDSwAAAABJRU5ErkJggg=="
  ))
  writeBin(png1, file.path(td, "i.png"))
  e = new.env()
  e$f = file.path(td, "i.png")
  res = r_tool_execute(list(code = "for (i in 1:5) ns_resolve(\"read\")(f)"),
                       list(envir = e, session = NULL))
  imgs = Filter(function(b) identical(b$type, "image"), res$content)
  expect_identical(length(imgs), 2L)
  expect_identical(res$details$plots, 2L)
  expect_match(ns_result_text(res), paste0("[3 image(s) from peter$plot() or peter$read() not ",
                                           "attached: at most 2 per r call]"), fixed = TRUE)
})

test_that("#> outputs keep at most gptr.doc_output_lines lines of 76 characters per expression", {
  local_gptr_options(doc_output_lines = 2L)
  res = list(outputs = list(c("[1] 2", "", "[1] 3", "[1] 4"), strrep("x", 100)), n_done = 2L)
  expect_identical(r_doc_outputs(res), c("[1] 2", "[1] 3", paste0(strrep("x", 73), "...")))
  expect_identical(r_doc_outputs(list(outputs = list("a"), n_done = 0L)), character())
})

test_that("bridge digests and artifact paths are collected through session hooks and unhooked", {
  added = new.env()
  removed = new.env()
  removed$ids = character()
  fake_add = function(event, handler, matcher = NULL, rank = 3L, source = "user",
                      session = NULL) {
    assign(event, handler, envir = added)
    event
  }
  fake_remove = function(id) {
    removed$ids = c(removed$ids, id)
    invisible(TRUE)
  }
  local_mocked_bindings(hook_add = fake_add, hook_remove = fake_remove)
  rc = r_call_new(NULL)
  ids = r_collect_hooks(rc, "s0123456789")
  expect_identical(ids, c("bridge_call", "artifact_start"))
  added$bridge_call(list(digest = "#> sh git status --porcelain: exit 0, 6 lines"), NULL)
  added$artifact_start(list(id = "marker-explorer", url = "http://127.0.0.1:1"), NULL)
  expect_identical(rc$bridge, "#> sh git status --porcelain: exit 0, 6 lines")
  expect_match(rc$artifacts, "artifacts/marker-explorer/app.R$")
  r_collect_unhook(ids)
  expect_identical(removed$ids, ids)
  expect_identical(r_collect_hooks(rc, NULL), character())
})

test_that("the risk of r comes from the risk.classify service, level 2 before it exists", {
  if (!ext_service_has("risk.classify")) {
    expect_identical(r_tool_risk(list(code = "1 + 1"), NULL)$level, 2L)
  }
  local_service("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    list(level = 0L, categories = "read", paths = character(), kind = kind)
  })
  r = r_tool_risk(list(code = "1 + 1"), list(envir = new.env()))
  expect_identical(r$level, 0L)
  expect_identical(r$kind, "r")
})

# ---- end to end through peter() on the fake provider (P08, P06, P09; P11 does not exist yet, so
# the permission gate is switched off with the documented escape hatch
# gptr.unsafe_no_permissions, IC-53) ----

# The r tool results of a session, in order
r_results = function(s) {
  Filter(function(m) identical(m$role, "tool_result") && identical(m$tool_name, "r"), s$messages)
}

test_that("model code peter$grep() runs through the shim; the recorded code keeps it", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_project(files = list("notes.txt" = "a needle here", "other.txt" = "hay"))
  e = new.env(parent = baseenv())
  fake = local_fake_provider(list(fake_tool("r", code = "m = peter$grep(\"needle\")"), "Found it."))
  s = peter("Find the needle", model = fake, envir = e, mode = "auto")
  expect_s3_class(e$m, "gptr_matches")
  expect_identical(e$m$file, "notes.txt")
  res = r_results(s)[[1L]]
  expect_identical(res$details$code, "m = peter$grep(\"needle\")")
  expect_identical(res$details$status, "ok")
  expect_identical(res$details$nested[[1L]]$tool, "grep")
  expect_false(exists("peter", envir = e, inherits = FALSE))
})

test_that("gptr_return(): 12 MB by name, 200 KB as a copy, an anonymous value boxed", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  e = new.env()
  e$big = stats::runif(1.5e6)
  e$small = stats::runif(25000)
  fake = local_fake_provider(list(
    fake_tool("r", code = "gptr_return(big)"), "Returned big.",
    fake_tool("r", code = "gptr_return(small)"), "Returned small.",
    fake_tool("r", code = "gptr_return(summary(small))"), "Returned a summary."
  ))
  s = peter("Return big", model = fake, envir = e, mode = "auto")
  s |> peter("Return small")
  s |> peter("Return a summary")
  expect_identical(s$values$mode, c("name", "copy", "box"))
  expect_identical(s$values$name[1:2], c("big", "small"))
  expect_identical(vapply(r_results(s)[1:2], function(m) m$details$value, ""), c("big", "small"))
  expect_s3_class(s$value, "summaryDefault")
  expect_identical(withVisible(gptr_return(5)), list(value = 5, visible = FALSE))
})

test_that("a fuzzy edit returns the message and a diff; an exact edit the message only", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  root = local_project(files = list(
    "fuzzy.R" = sprintf("v%03d = %d   ", 1:300, 1:300),
    "exact.R" = "a = 1"
  ))
  fuzzy_edit = list(oldText = "v150 = 150\nv151 = 151", newText = "v150 = 0\nv151 = 0")
  fake = local_fake_provider(list(
    fake_tool("edit", path = "fuzzy.R", edits = list(fuzzy_edit)),
    fake_tool("edit", path = "exact.R", edits = list(list(oldText = "a = 1", newText = "a = 2"))),
    "Edited."
  ))
  s = peter("Edit both files", model = fake, envir = new.env(), mode = "auto")
  reqs = fake_requests(fake)
  fuzzy = reqs[[2L]]$last_results[[1L]]$content[[1L]]$text
  lines = strsplit(fuzzy, "\n")[[1L]]
  expect_identical(lines[1L], "Successfully replaced 1 block(s) in fuzzy.R.")
  expect_identical(lines[2L], "[matched after whitespace, quote or dash normalisation]")
  expect_true(any(startsWith(lines, "@@")))
  expect_lte(est_tokens(lines[-(1:2)], "code"), 400)
  exact = reqs[[3L]]$last_results[[1L]]$content[[1L]]$text
  expect_identical(exact, "Successfully replaced 1 block(s) in exact.R.")
  expect_identical(readLines(file.path(root, "exact.R"), encoding = "UTF-8"), "a = 2")
})

test_that("the r schema frozen without a bound document has no record or note (IC-68)", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  fake = local_fake_provider(list("Hello."))
  s = peter("Say hello", model = fake, envir = new.env(), mode = "auto")
  tools_json = session_data(s)$frozen$tools_json
  expect_match(tools_json, "\"name\":\"r\"", fixed = TRUE)
  expect_false(grepl("\"record\"", tools_json, fixed = TRUE))
  expect_false(grepl("\"note\"", tools_json, fixed = TRUE))
  expect_match(tools_json, "Seconds; best effort. Default 3600.", fixed = TRUE)
  expect_true(all(c("read", "r", "edit", "write") %in% fake_requests(fake)[[1L]]$tools))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-r$")'
```

Expected: `[ FAIL 23 | WARN 0 | SKIP 0 | PASS 9 ]`; the unit tests error with `could not find function "r_schema"` (or `"r_tool_execute"`, `"r_doc_outputs"`, `"r_collect_hooks"`, `"r_tool_risk"`) or fail because `registry_get("tool", "r")` is `NULL`; in the end-to-end tests the `r` calls come back as `Tool r not found`, so `e$m`, `s$values` and `details` are missing. (The filter `tool-r$` matches `test-tool-r.R` only; `tool-r` alone would also match `test-tool-read.R`.)

- [ ] **Step 3: Write the implementation**

Create `R/tool-r.R`:

```r
# tool-r.R -- the `r` tool (P10): the frozen schema variants of IC-68 (`record` and `note` only with
# a bound document, `timeout` only when no human can answer), evaluation through the `evaluator`
# kind (P09's eval_r() by default, IC-69) in the run's evaluation environment (the plan-mode scratch
# overlay, IC-15), the model text of format_eval_result() (P09) plus images attached by
# peter$plot(), and the `details` record of contract section 4.4. While the evaluation runs, the
# execute frame binds the r-call marker (`gptr_r_call`, tool-namespace.R) through which member
# calls reach dispatch_nested() (the nested-call gating hook) and peter$plot() attaches images.
# Sources: architecture sections 6.12 and 7.2; contract sections 4.4, 7.9, 9.2;
# dev/research/14-script-as-harness-history.md section 4.1 (`record`, `note`); the measured variants
# of dev/research/assets/design-review-resolution/prompt/tools.R.

r_tool_description = paste(
  "Run R code in the user's live R session. Objects persist between calls and belong to the user.",
  "Returns printed output, messages, warnings, errors with a traceback, and plots as images.",
  "Execution stops at the first error. Output beyond about 4000 tokens keeps the first 40% and",
  "last 60% and names a peter$out(id) handle for the rest."
)
r_tool_snippet =
  "Run R code in the user's live session (objects persist; plots come back as images)"
r_tool_guidelines = c(
  paste("Use r to inspect and compute on objects in the live session; never reload or recompute",
        "data that is already in memory"),
  paste("In r, assign results to names and print compact summaries (dim(), head(),",
        "peter$describe(x)) rather than whole objects"),
  "Use = for assignment and |> for pipes in all R code you write"
)

#' The `r` input schema variant (IC-68): `record` and `note` only with a document bound at freeze,
#' `timeout` only when no human can answer
#' @noRd
r_schema = function(document = FALSE, human = TRUE) {
  props = list(code = list(
    type = "string", description = "R code to evaluate. May contain several expressions."
  ))
  if (isTRUE(document)) {
    props$record = list(type = "boolean", description = paste(
      "Record this code in the user's document (default true).",
      "Use false for throwaway inspection."
    ))
    props$note = list(type = "string", description = paste(
      "One-line decision or rationale, recorded as a '## Decision:' comment."
    ))
  }
  if (!isTRUE(human)) {
    props$timeout = list(type = "number", description = "Seconds; best effort. Default 3600.")
  }
  list(type = "object", required = I("code"), properties = props)
}

#' The r tool's `parameters`: a function evaluated once at freeze with `ctx$input` (P07; contract
#' 10.2 row 14: `document` is non-NULL when a history document is bound, `human` whether someone can
#' answer)
#' @noRd
r_tool_parameters = function(ctx) {
  input = if (is.null(ctx)) NULL else ctx$input
  document = !is.null(input$document)
  if (is.null(input) && !is.null(ctx) && !is.null(ctx$session) && ext_service_has("doc.site")) {
    site = tryCatch(ext_service_get("doc.site")(ctx$session), error = function(e) NULL)
    document = !is.null(site)
  }
  human = if (is.null(input$human)) gptr_can_prompt() else isTRUE(input$human)
  r_schema(document = document, human = human)
}

#' The evaluator of a session: the `evaluator` record named by setting `evaluator` (default "r"),
#' else P09's eval_r() (IC-69)
#' @noRd
r_evaluator = function(session = NULL) {
  sid = if (is.null(session)) NULL else session$id
  name = setting_get("evaluator", session = session, default = "r") %||% "r"
  ev = registry_get("evaluator", name, session = sid)
  if (is.null(ev) || !is.function(ev$eval)) eval_r else ev$eval
}

#' Session hooks collecting bridge digests (`bridge_call`, P22) and artifact paths
#' (`artifact_start`, P23) into the r-call marker while the evaluation runs; returns the hook ids
#' @noRd
r_collect_hooks = function(rc, sid) {
  if (is.null(sid)) return(character())
  on_bridge = function(event, ctx) {
    if (is.character(event$digest)) rc$bridge = c(rc$bridge, event$digest)
    NULL
  }
  on_artifact = function(event, ctx) {
    if (is.character(event$id) && length(event$id) == 1L) {
      app = file.path(workspace_root(create = FALSE), "artifacts", event$id, "app.R")
      rc$artifacts = c(rc$artifacts, path_rel(app))
    }
    NULL
  }
  c(hook_add("bridge_call", on_bridge, rank = 6L, source = "builtin:r", session = sid),
    hook_add("artifact_start", on_artifact, rank = 6L, source = "builtin:r", session = sid))
}

#' Remove the collecting hooks
#' @noRd
r_collect_unhook = function(ids) {
  for (id in ids) hook_remove(id)
  invisible(NULL)
}

#' Printed-output lines of the completed expressions for `#>` comments: at most
#' gptr.doc_output_lines per expression, 76 characters each (contract section 4.4)
#' @noRd
r_doc_outputs = function(res) {
  outs = res$outputs %||% list()
  n = min(length(outs), as.integer(res$n_done %||% 0L))
  if (!n) return(character())
  cap = as.integer(gptr_opt("doc_output_lines"))
  lines = unlist(lapply(outs[seq_len(n)], function(o) {
    o = as.character(o)
    o = utils::head(o[nzchar(o)], cap)
    ifelse(nchar(o) > 76L, paste0(substr(o, 1L, 73L), "..."), o)
  }), use.names = FALSE)
  as_utf8(as.character(lines))
}

#' Name designated through gptr_return() during this call (the newest value record), or NULL
#' @noRd
r_new_value_name = function(session, n_before) {
  if (is.null(session)) return(NULL)
  vals = session_data(session)$values %||% list()
  if (length(vals) <= n_before) return(NULL)
  vals[[length(vals)]]$name
}

#' Messages of the events of one type
#' @noRd
r_event_text = function(events, type) {
  ev = Filter(function(e) identical(e$type, type), events)
  as.character(unlist(lapply(ev, function(e) e$message %||% e$text), use.names = FALSE))
}

#' The r tool result of an evaluation: format_eval_result() text and images, peter$plot() images,
#' and the `details` record of contract section 4.4 (plus `plot_files`, the PNGs behind
#' peter$plot(which))
#' @noRd
r_tool_result = function(code, record, note, res, fmt, rc, session, n_values) {
  events = res$events %||% list()
  plots = Filter(function(e) identical(e$type, "plot"), events)
  err = r_event_text(events, "error")
  images = c(fmt$images %||% list(), rc$images)
  rendered = Filter(function(e) is.character(e$path) && length(e$path) == 1L, plots)
  plot_files = vapply(rendered, function(e) e$path, "")
  plot_index = vapply(rendered, function(e) as.integer(e$index %||% NA_integer_), 0L)
  obj = res$changes$objects %||% list()
  objects = list(added = as.character(obj$added), modified = as.character(obj$modified),
                 removed = as.character(obj$removed))
  changes = res$changes
  changes$objects = NULL
  details = list(
    code = code, record = record, note = note, status = res$status,
    n_done = as.integer(res$n_done %||% 0L), n_total = as.integer(res$n_total %||% 0L),
    objects = objects, plots = length(images),
    warnings = redact_hook(r_event_text(events, "warning"), "persist"),
    error = if (length(err)) redact_hook(err[[1L]], "persist") else NULL,
    changes = changes, elapsed = res$elapsed, out_id = fmt$out_id, spill = fmt$spill,
    outputs = if (record) r_doc_outputs(res) else character(), nested = list(), bridge = rc$bridge,
    artifacts = rc$artifacts, checkpoint = NULL, value = r_new_value_name(session, n_values),
    plot_files = plot_files, plot_index = plot_index
  )
  text = fmt$text
  dropped = as.integer(rc$dropped %||% 0L)
  if (dropped > 0L) {
    text = paste0(text, "\n[", dropped, " image(s) from peter$plot() or peter$read() not ",
                  "attached: at most ", as.integer(gptr_opt("r_max_images")), " per r call]")
  }
  out = gptr_tool_result(text, images = if (length(images)) images else NULL, details = details,
                         is_error = !identical(res$status, "ok"))
  out$out_id = fmt$out_id
  out$spill = fmt$spill
  out$truncated = isTRUE(fmt$truncated)
  out
}

#' The r tool's execute: evaluate `code` in the run's evaluation environment
#'
#' Copy-safety [R2][R3]: this frame binds the evaluation environment (possibly a function-frame
#' home) only while the call runs and resets the binding on exit; it creates no closure and uses no
#' tryCatch(); the value of the evaluation is never kept (R8, P09). The r-call marker `gptr_r_call`
#' holds the ctx and collectors only.
#' @noRd
r_tool_execute = function(input, ctx) {
  code = as_utf8(input$code)
  check_string(code, "code", empty = TRUE)
  record = if (is.null(input$record)) TRUE else isTRUE(input$record)
  note = input$note
  check_string(note, "note", null = TRUE, empty = TRUE)
  run = run_current()
  opts = if (is.null(run)) list() else run$opts %||% list()
  mode = if (is.null(run)) NULL else run$mode
  if (is.null(mode) && !is.null(ctx) && is.function(ctx$mode)) mode = ctx$mode()
  if (identical(mode, "plan")) record = FALSE
  timeout = input$timeout %||% opts$timeout
  envir = if (is.null(run)) ctx$envir else run_eval_env(run)
  on.exit({
    envir = NULL
  }, add = TRUE)
  if (!is.environment(envir)) {
    gptr_abort("The r tool has no evaluation environment.", "internal",
               detail = "no run and no ctx$envir")
  }
  session = if (is.null(ctx)) NULL else ctx$session
  gptr_r_call = r_call_new(ctx)
  hooks = r_collect_hooks(gptr_r_call, if (is.null(session)) NULL else session$id)
  on.exit(r_collect_unhook(hooks), add = TRUE)
  n_values = if (is.null(session)) 0L else length(session_data(session)$values %||% list())
  budget = as.integer(gptr_opt("r_output_tokens"))
  evaluate = r_evaluator(session)
  res = evaluate(code, envir, timeout = timeout, budget_tokens = budget, rng = opts$rng_state,
                 record = record)
  envir = NULL
  fmt = format_eval_result(res, budget)
  r_tool_result(code, record, note, res, fmt, gptr_r_call, session, n_values)
}

#' Risk of an r call: P11's classifier through the `risk.classify` service; level 2 before P11
#' exists
#' @noRd
r_tool_risk = function(input, ctx) {
  code = input$code
  if (!is.character(code) || length(code) != 1L || !ext_service_has("risk.classify")) {
    return(list(level = 2L, categories = "r", paths = character()))
  }
  envir = if (is.null(ctx)) NULL else ctx$envir
  ext_service_get("risk.classify")(code, envir = envir, root = project_root(), kind = "r")
}

#' builtin:r: the `r` tool (contract sections 7.10 and 9.2)
#' @noRd
builtin_r = function(gptr) {
  gptr$register(gptr_tool("r", r_tool_description, parameters = r_tool_parameters,
                          execute = r_tool_execute, exposure = "direct", execution = "sequential",
                          risk = r_tool_risk, snippet = r_tool_snippet,
                          guidelines = r_tool_guidelines, record = TRUE))
  invisible(NULL)
}

on_load(ext_declare_builtin("r", builtin_r))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-r$")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 79 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/tool-r.R tests/testthat/test-tool-r.R
git commit -m "feat(tools): add the r tool with its frozen schema variants and builtin:r"
```

### Task 12: Copy-safety rows

**Files:** Test: `tests/testthat/test-copy-tools.R` (create).

The copy suite of 03 §3.4 (`test-copy-tools.R`: "namespace members and designated values") and 05 P10 acceptance 5: each row runs in a fresh `Rscript --vanilla` through P01's `expect_no_copy()` (04 §12.2), which loads gptr, runs `setup`, starts `tracemem(big)`, runs the gptr `action`, then the user's next in-place edit `big[1] = 0`, and passes when that edit makes no copy (nothing kept a reference). The rows cover the three designated-value modes of `gptr_return()` (by name above `gptr.value_copy_max`, a copy below it, an anonymous value boxed), `gptr_return()` outside a run (IC-48), tool code `n = 1L; length(d)` evaluated in a function-frame home (`f = function(d) peter(..., d)`; the `peter()` form moved here from P09, cons-16), and `peter$describe(big)` at the console and from model code. The permission gate is off through `gptr.unsafe_no_permissions` set before the run (IC-53), because P11 does not exist yet. The last row is a negative control: `keep = list(big)` holds a reference, so exactly one copy is counted, which shows that the zero counts are not vacuous.

These rows guard behaviour implemented in Tasks 8-11 (closures that pass promises, the `r` tool's reset of its environment binding, P06's value policy, P09's evaluator), so they pass as soon as they are written; the negative control is the row that demonstrates the harness detects a copy. This task adds no production code. If a row fails, the fix belongs in the code path the row names, following the rules of 03 §6.4 (R1 never put a user object in a list that becomes garbage, R2 never keep a user frame, R3 never collect frames, R8 clear evaluation results in place).

**Interfaces:**
- Consumes (P01 helper, 04 §12.2): `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` -> the copy count, invisibly; inside the child: `peter()`, `gptr_return()`, `gptr_fake_provider()` (P01, P08), the `r` tool (Task 11), `peter$describe` (Tasks 8 and 10).
- Produces: the P10 rows of the copy suite (no runtime interface).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-copy-tools.R`:

```r
# Copy-safety rows of P10 (architecture section 6.4; contract sections 1.3 and 12.3): designated
# values under the value policy, tool code evaluated in a function-frame home (moved from P09) and
# the describe member at the console and inside model code. Each row runs in a fresh `Rscript
# --vanilla` through P01's expect_no_copy() and passes when the user's next in-place edit of `big`
# makes no copy. The last row is a negative control: a held reference makes exactly one copy, so
# the zero counts above are not vacuous.

gate_off = "options(gptr.unsafe_no_permissions = TRUE, gptr.quiet = TRUE, gptr.interactive = FALSE)"

go = "s = peter('go', model = fake, envir = globalenv(), mode = 'auto')"

run_r = function(code, call = go) {
  fake = "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = '%s')), 'done'))"
  paste(gate_off, sprintf(fake, code), call, sep = "; ")
}

test_that("a designated value held by name (12 MB) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("gptr_return(big)"),
                 label = "value by name")
})

test_that("a designated value held as a copy (200 KB) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(25000)", action = run_r("gptr_return(big)"),
                 label = "value as copy")
})

test_that("an anonymous designated value (boxed) leaves the object editable in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("gptr_return(big * 2)"),
                 label = "boxed value")
})

test_that("gptr_return(big) outside a run leaves the object editable in place (IC-48)", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = "gptr_return(big)",
                 label = "outside a run")
})

test_that("tool code `n = 1L; length(d)` in a function-frame home leaves the object in place", {
  home = "f = function(d) peter('count', d, model = fake, mode = 'auto'); s = f(big)"
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("n = 1L; length(d)", call = home),
                 label = "function-frame home")
})

test_that("peter$describe(big) at the console and from model code leaves the object in place", {
  expect_no_copy(setup = "big = runif(1.5e6)", action = "x = peter$describe(big)",
                 label = "describe (user)")
  expect_no_copy(setup = "big = runif(1.5e6)", action = run_r("x = peter$describe(big)"),
                 label = "describe (model code)")
})

test_that("the harness counts a held reference (negative control)", {
  copies = expect_no_copy(setup = "big = runif(1.5e6)", action = "keep = list(big)",
                          allow = 1L, label = "negative control")
  expect_identical(copies, 1L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-tools")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 9 ]`. The rows are regression guards over Tasks 8-11 and pass immediately; the negative control proves they can fail (its `expect_no_copy(..., allow = 1L)` counts exactly 1 copy). To see a row fail, temporarily replace `allow = 1L` by `allow = 0L` in the negative control: the run reports the failure "negative control: 1 copies of big (allowed 0)" (the message quotes `big` in backticks); restore `allow = 1L` before Step 4. The suite skips on CRAN and when R lacks `capabilities("profmem")` (then `SKIP 7`).

- [ ] **Step 3: Write the implementation**

No production code: this task adds regression rows only (see above for where a failing row's fix belongs).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "copy-tools")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 9 ]` (each row starts one `Rscript`, so the file takes about 20 seconds).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-copy-tools.R
git commit -m "test(tools): add the copy-safety rows for members and designated values"
```

### Task 13: P10's golden transcript and baseline row

**Files:** Create: `dev/bench/tokens/fixtures/ns02b-data-first-pipe.json`; Modify: `dev/bench/tokens/baseline.csv` (one row added by P07's runner with `--update`).

IC-73: P10 adds its north-star fixture and baseline row to P07's golden-transcript runner (`dev/bench/tokens/run.R`, a development tool that needs rtiktoken and is excluded from the build). P10's fixture is NS-2's data-first pipe (02 §2: `mice |> peter("Which columns have missing values, and how should I impute them?")`) run as a script with a small model, which exercises what P10 adds to the token budget: the `minimal` preset (the four direct tools only, `grep`/`find`/`ls` and every helper reachable as R signatures through the `<rules>` lines, 03 §7.1) and one composed `r` call that uses a `peter$` member (`peter$describe()`) instead of extra tool calls (S-12). Its result text is the exact output P09's evaluator and P10's `describe` member produce for this code in an English UTF-8 locale (re-checked with `LC_ALL=en_US.UTF-8`; `tapply()` orders the `diet` groups by the locale's collation, so the C locale prints `HF control` instead, with the same tokens; the runner replays the recorded text and does not evaluate the code). The prefix it measures is the IC-68 total of the minimal preset, 615 + 656 = **1,271** o200k tokens.

With P10 loaded, P07's existing rows measure a smaller prefix (2,620 instead of 2,750): the stand-in loader registers no `r_session` fragment stand-ins once a real fragment exists (`prompt_standins_register(only_missing = TRUE)`), so the `shell`, `languages` and `subagents` lines of P22 and P19 are absent until those plans land with byte-identical texts. The runner gates only increases, so the existing baseline rows stay as they are and `--check` passes; P10 updates only its own row.

**Interfaces:**
- Consumes (P07, IC-73): `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]`, the fixture format of `dev/bench/tokens/fixtures/ns02-mixed-model.json`, `bench_compare()` (signals `gptr_error_token_regression`), `tests/testthat/fixtures/bench/standins.R`; the development package rtiktoken (as P07's runner requires).
- Produces: the fixture `ns02b-data-first-pipe` and its row in `dev/bench/tokens/baseline.csv` (P24 gates every row).

- [ ] **Step 1: Write the failing test**

Create `dev/bench/tokens/fixtures/ns02b-data-first-pipe.json`:

```json
{
  "id": "ns02b-data-first-pipe",
  "north_star": 2,
  "description": "mice |> peter(\"Which columns have missing values, and how should I impute them?\") in an Rscript run with a small model: minimal preset, auto mode, no human, no bound document; one composed r call that calls the peter$describe() member, then the answer.",
  "mode": "auto",
  "human": false,
  "preset": "minimal",
  "models": [
    "benchsmall/benchsmall-1"
  ],
  "standins": [],
  "environment": "Date: 2026-09-29\nWorking directory: /Users/me/project (project root)\nFront end: Rscript (no human present)\nR 4.4.3 on aarch64-apple-darwin20; RAM 24 GB (17 GB free)",
  "files": {
    "AGENTS.md": "# AGENTS.md\n- Style: = for assignment, |> for pipes, snake_case.\n- Mixed models: lme4; report estimates with 95% confidence intervals."
  },
  "objects": {
    "mice": "data.frame(mouse = rep(sprintf('m%02d', 1:12), each = 4), diet = rep(c('control', 'HF'), 24), weight = replace(round(20 + (1:48) %% 7 + rep(c(0, 3), 24), 1), c(5, 17, 30), NA))"
  },
  "facts": [
    "mice",
    "weight",
    "diet",
    "mouse"
  ],
  "turns": [
    {
      "prompt": "Which columns have missing values, and how should I impute them?",
      "source": "prompt",
      "context": [
        {
          "label": "mice",
          "class": "data.frame"
        }
      ],
      "steps": [
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_01",
              "name": "r",
              "input": {
                "code": "miss = colSums(is.na(mice))\nmiss[miss > 0]\npeter$describe(mice$weight, budget = 60)\ntapply(is.na(mice$weight), mice$diet, sum)"
              },
              "result": "weight \n     3 \n<numeric> length 48, 432 B\n  min 20, median 25, max 29; 6.2% NA\ncontrol      HF \n      2       1 \n+ miss <numeric length 3>",
              "details": {
                "code": "miss = colSums(is.na(mice))\nmiss[miss > 0]\npeter$describe(mice$weight, budget = 60)\ntapply(is.na(mice$weight), mice$diet, sum)",
                "status": "ok"
              }
            }
          ]
        },
        {
          "text": "Only `weight` has missing values: 3 of 48 rows (2 control, 1 HF). Weight is measured four times per mouse, so impute within mouse (the mean of that mouse's observed weights), or skip imputation and fit the mixed model on the 45 observed rows, which handles unbalanced repeats. The counts per column are in `miss`.",
          "calls": []
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: P07's static-prefix table and the results table are printed (Step 4 shows both), then the run stops with the `gptr_error_token_regression` message:

```text
Error: Token-efficiency regression:
  ns02b-data-first-pipe: no baseline row (run with --update ns02b-data-first-pipe)
Execution halted
```

- [ ] **Step 3: Write the implementation**

Record the baseline row with P07's runner:

```bash
Rscript --vanilla dev/bench/tokens/run.R --update ns02b-data-first-pipe
```

Expected: the static-prefix and results tables, then `baseline written: ns02b-data-first-pipe`. `dev/bench/tokens/baseline.csv` now reads (the `est_*` columns are informational and may differ by a few tokens):

```text
"case","requests","prefix","input_total","output_total","image_tokens","catalog","facts","est_prefix","est_input_total"
"ns02-mixed-model",2,2750,6088,140,0,542,1,2930,6410
"ns02b-data-first-pipe",2,1271,3280,130,0,0,4,1638,4014
"ns03-pipe-steering",6,2750,19700,337,532,542,0,2930,20500
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected (the elapsed time varies; the `est_*` columns are not gated):

```text
        static_prefix o200k baseline
              minimal  1271     1271
        standard_core  2360     2360
         standard_all  2844     2844
 standard_interactive  2987     2987
                  case requests prefix input_total output_total image_tokens
      ns02-mixed-model        2   2620        6112          140            0
 ns02b-data-first-pipe        2   1271        3280          130            0
    ns03-pipe-steering        6   2620       19016          337          532
 catalog facts est_prefix est_input_total
     552     4       2789            6428
       0     4       1638            4014
     552     0       2789           19828
3 golden transcripts in 5.0 s; wrote dev/bench/tokens/results.csv
OK: 4 static prefixes and 3 golden transcripts within the baseline tolerances
```

The static prefixes are composed by P07 with its stand-ins only (`exclusive = TRUE`), so P10 leaves them at the IC-68 totals; the minimal static prefix and P10's `ns02b-data-first-pipe` prefix are the same 1,271 tokens.

- [ ] **Step 5: Commit**

```bash
git add dev/bench/tokens/fixtures/ns02b-data-first-pipe.json dev/bench/tokens/baseline.csv
git commit -m "chore(bench): add the NS-2 data-first pipe golden transcript and baseline row"
```

## Plan acceptance

Every acceptance check of 05 P10 (including its review amendments), the task and test that prove it, and the command with its expected result. Expected counts assume git and ripgrep on `PATH`, stringi and magick installed and an R built with memory profiling (the documented skips apply otherwise).

| # | Acceptance check (05 P10) | Proved by |
|---|---|---|
| 1 | `devtools::test(filter = "tool-|copy-tools")` is green | Tasks 1-12 (all nine test files) |
| 2 | Pi's read/edit/write oracle cases (01) and report 11's grep/find/ls oracles pass; `find` sorts by path, mtime and size; grep respects `.gitignore` | Task 4 `test-tool-read.R` (Pi's read cases), Task 5 `test-tool-write.R`, Task 6 `test-tool-edit.R` (Pi's edit, fuzzy, CRLF/BOM and argument-shim cases), Task 7 `test-tool-search.R` ("grep sorts by path and skips binary and .gitignore'd files", "grep reproduces Pi's limit and context texts", "find sorts by mtime (newest first), size (largest first) and relevance (IC-71)", "grep agrees with ripgrep on (file, line) pairs"), Task 2 `test-tool-walk.R` ("the file set equals git ls-files ...") |
| 3 | `peter$nope` errors listing the members; `.DollarNames` completion lists `read`, `grep`, `find`, `ls`, `help`, `search`, `describe`, `plot`, `out`; accessing a member performs no I/O | Task 10 "peter$nope lists the members; completion lists the built-in members (acceptance 3)" and "accessing a member performs no I/O and opens no connection"; Task 8 "ns_resolve() finds user members and errors on unknown names listing the members" |
| 4 | model code `peter$grep("x")` evaluated where `peter` is not visible runs through the shim, and the recorded code keeps `peter$grep("x")` | Task 11 "model code peter$grep() runs through the shim; the recorded code keeps it" |
| 5 | value policy: 12 MB by name, 200 KB as a copy, anonymous boxed; `gptr_return(x)` outside a run returns `x` invisibly and changes nothing (IC-48); the copy rows of all three stay in place, as does tool code `n = 1L` and `length(d)` in `f = function(d) peter(..., d)` | Task 11 "gptr_return(): 12 MB by name, 200 KB as a copy, an anonymous value boxed"; Task 12 all rows (including "gptr_return(big) outside a run ..." and "tool code `n = 1L; length(d)` in a function-frame home ...") |
| 6 | an edit whose `oldText` matched only through the fuzzy fallback returns the message plus a diff of at most 400 tokens; an exact edit returns the message only | Task 6 "the result text carries a diff only when something deviated (acceptance 6)"; Task 10 "a fuzzy edit returns the message and a diff of at most 400 tokens (acceptance 6)"; Task 11 "a fuzzy edit returns the message and a diff; an exact edit the message only" (end to end through `peter()`) |
| 7a | a plugin member with `namespace = "grep"` or without a namespace is refused | Task 8 "a plugin r member without a namespace or with a reserved one is refused (IC-37)" (P02 refuses at registration; resolution refuses too) |
| 7b | `peter$read` and the direct `read` tool come from one spec | Task 10 "builtin:tools registers one spec per capability, direct and member form (IC-37)" (`attr(ns_resolve(cap), "spec")` is identical to `registry_get("tool", cap)` for `read`, `edit`, `write`, `grep`, `find`, `ls`) |
| 7c | `peter$find("tst", sort = "relevance")` ranks `test.R` first | Task 7 "find sorts by mtime (newest first), size (largest first) and relevance (IC-71)" |
| 7d | the `r` schema frozen without a document has no `record`/`note` | Task 11 "the r schema is frozen in one of four variants (IC-68)", "the r spec reproduces P07's stand-in in each of its four variants (IC-68)" and "the r schema frozen without a bound document has no record or note (IC-68)" |
| 7e | P10's NS fixture and baseline rows are added to `dev/bench/tokens/` (IC-73) | Task 13 |

Commands:

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-|copy-tools")'
```

Expected (acceptance 1): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1077 ]` (`test-copy-tools.R` 9, `test-tool-diff.R` 419, `test-tool-edit.R` 79, `test-tool-namespace.R` 287, `test-tool-r.R` 79, `test-tool-read.R` 80, `test-tool-search.R` 56, `test-tool-walk.R` 48, `test-tool-write.R` 20). Without git, ripgrep, magick or memory profiling the documented skips appear (`SKIP` > 0) and nothing fails.

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-read|tool-write|tool-edit|tool-search|tool-walk")'
```

Expected (acceptance 2): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 283 ]`.

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-namespace")'
```

Expected (acceptances 3, 6, 7a, 7b): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 287 ]`.

```bash
Rscript --vanilla -e 'devtools::test(filter = "tool-r$|copy-tools")'
```

Expected (acceptances 4, 5, 6, 7d): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`.

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected (acceptance 7e): the tables of Task 13 Step 4 and `OK: 4 static prefixes and 3 golden transcripts within the baseline tolerances`.

The milestone check (`devtools::check()`) runs at the end of M2 (05: the last plan of the milestone); P10 needs only that its files pass P01's `test-lint-rules.R` and `test-arch-layers.R`, which run in the full suite:

```bash
Rscript --vanilla -e 'devtools::test(filter = "lint-rules|arch-layers")'
```

Expected: `FAIL 0` (P10 adds no expectation to these two files of P01). P10's sources contain no `<-`, `%>%`, `:::`, `.GlobalEnv`, `withr::`, non-ASCII byte or non-literal `cli_*()` format in `R/tool-*.R`; every internal call from a `tool-*.R` file is allowed by the layer table and the kernel SDK.

## Self-review

**Spec coverage (05 P10 scope, review amendments and acceptance -> task).**

| Requirement | Task |
|---|---|
| `tool-namespace.R`: gateway services resolving members from tool specs (`ns.resolve`, `ns.names`, IC-36), generated closures from JSON Schema, side-effect-free `$`, `.DollarNames` completion | 8 (closures, resolution, nodes), 10 (service registration, no-I/O test) |
| `peter$help()`, `peter$search()` (BM25 over members, plugin and MCP tools, skills; `search.sources`, IC-69) | 9 |
| `peter$describe()`, `peter$plot(which =)` (IC-67), `peter$out()` (only owner, IC-36), `builtin:tools` | 8 (`describe`), 10 |
| `tool-r.R`: schema of §7.2, `record`/`note`/`timeout`, results through the evaluator, nested-call gating hook (the r-call marker), `builtin:r`; `parameters` as a function giving the four variants (IC-68) | 1 (marker), 11 |
| `tool-read.R`: encodings, windows, images by magic bytes, large-file index, 12,000-token cap, line numbers off; `skill:<name>/<path>` (IC-68) | 4 |
| `tool-write.R`: atomic, EOL- and encoding-preserving | 5 |
| `tool-edit.R`: multi-edit, fuzzy fallback, `*** Begin Patch` envelopes, diff only on deviation, routing to the document backend | 6, 8 (`doc.edit` routing), 10 (direct tool) |
| `tool-diff.R` | 3 |
| `tool-walk.R`: pruned walker, gitignore engine, glob to PCRE, Pi's `**/` rule | 2 |
| `tool-search.R`: raw prefilters, radix sorting, early stop, 1,500-token prints; `find(sort = "relevance")`, `grep(sort =)` (IC-71) | 7 |
| One spec per capability for `read`, `edit`, `write`, `grep`, `find`, `ls`; reserved member names; required plugin namespaces (IC-37) | 8, 10 |
| `record = FALSE` for `out`, `plot`, `help`, `search`, `describe` (IC-48) | 10 |
| `guidelines` for `<rules>`; `r_session` fragments for helpers and `out` (IC-68) | 10 (tools), 11 (`r`) |
| `edit`/`write` apply the `control` and `instructions` path classes (IC-54) | 10 (risk functions and test) |
| Copy-safety suite `test-copy-tools.R`, including the function-frame row moved from P09 | 12 |
| P10's NS fixture and baseline rows (IC-73) | 13 |
| Lazy plugins in the `plugins` section, completion and search through manifest `declarations`, never activated (04 §10.8; consumed by P17 under IC-36) | 8 (`ns_spec_line()`, `ns_member_names()`, `print.gptr_ns`), 9 (`ns_catalog()`, `ns_search_docs()`, `member_search()`; test "a lazy plugin is catalogued, completed and searched through its declarations") |
| At most `gptr.r_max_images` images from `peter$plot()`/`peter$read()` per `r` result, the rest named (IC-67) | 1 (`r_call_attach_image()`), 11 (notice; test "images beyond gptr.r_max_images ...") |
| Member prints within 0.6 x the remaining `r` budget (04 §9.4) | 1 (`member_budget()`, the marker's `printed` count) |
| Acceptance 1-7 | see the Plan acceptance table |

**Placeholder scan.** The plan was searched for "TBD", "TODO", "implement later", "fill in", "similar to Task", "appropriate error handling" and "handle edge cases": the only hits are the word `TODO` inside the grep fixture data of `test-tool-search.R` (a pattern the tests search for). Every step that changes a file shows the complete code; Task 12 Step 3 states explicitly that the task adds no production code.

**Type and name consistency with 04.** Signatures match 04 §7.10 and §9.4 exactly: `ns_resolve(path)`, `ns_names(pattern)`, `ns_register_provider(name, fun)`, `member_closure(spec)`, `ns_catalog(session, kinds = c("plugin"), budget = 1500L)`, `bm25_index(docs)`, `bm25_search(index, words, limit = 8L)`, `read_file(path, offset = NULL, limit = NULL, budget_tokens = gptr_opt("read_max_tokens"))`, `write_file(path, content)`, `edit_file(path, edits, replace_all = FALSE)`, `patch_apply(envelope, root = project_root())`, `diff_lines(old, new, context = 3L, max_tokens = 400L)`, `walk_files(root = ".", type = c("file", "dir", "any"), gitignore = TRUE, hidden = FALSE, max = Inf, prune = NULL)`, `glob_to_regex(glob)`, `search_grep()`, `search_find()`, `search_ls()`, `builtin_tools(gptr)`, `builtin_r(gptr)`; members `peter$read(path, offset = NULL, limit = NULL)`, `peter$write(path, content)`, `peter$edit(path, edits, replace_all = FALSE)`, `peter$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"), sort = c("path", "count", "mtime"))`, `peter$find(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"), type = "file", limit = 1000L)`, `peter$ls(path = ".", sort = c("name", "mtime", "size"), long = FALSE)`, `peter$help(name, package = NULL, budget = 800L)`, `peter$search(words, limit = 8L)`, `peter$describe(x, budget = 150L)`, `peter$plot(which = NULL, width = 1000L, height = 700L)`, `peter$out(id, stream = c("stdout", "stderr"), lines = NULL)`. Classes `gptr_member`, `gptr_ns`, `gptr_lines`, `gptr_patch`, `gptr_matches`, `gptr_files`; condition classes `unknown_member`, `readonly`, `invalid_argument`, `not_available`, `tool`, `internal`; services `ns.resolve`, `ns.names`, `search.sources`; options `gptr.helper_output_tokens`, `gptr.read_max_tokens`. Every consumed function exists with the 04 signature in the dependency plans as extracted on 2026-10-01 (`dispatch_nested(name, input, ctx)`, `out_get(id, stream, lines, session)`, `plot_png(recorded, width, height, res)`, `eval_r(...)`, `format_eval_result(res, budget_tokens)`, `describe_binding(name, envir, budget)`, `gptr_describe(x, budget)`, `run_current()`, `run_eval_env(run)`, `session_data()`, `session_live()`, `setting_get(key, session, default)`, `registry_get/names/all/diagnostic()`, `hook_add()`, `hook_remove()`, `schema_signature()`, `first_sentence()`, `est_tokens()`, `block_image()`, `path_class()`, `write_atomic()`, `gptr_tool()`, `gptr_prompt_section()`, `gptr_spec()`, `ext_declare_builtin()`, `ext_service_set/get/has()`, `on_load()`); a script listed every function the P10 sources call and found each defined in P01-P09 or in P10.

Contract readings recorded here (none changes an API of 04):

1. `ns_catalog()`: 04 says "least-recently-used descriptions trimmed first"; at freeze no usage history exists, so descriptions are trimmed from the end of the name-sorted catalog and names are never trimmed.
2. `peter$grep()` and `peter$ls()` carry a trailing `...` that accepts the direct tools' argument names (`ignoreCase`, `literal`, `limit`): the specs carry both forms (IC-37) and P02's validator requires `fun`'s formals to cover the schema's properties unless `fun` has `...` (04 §6.8). The printed signatures omit the `...`; unknown names still fail with `gptr_error_invalid_argument`.
3. `gptr_lines` carries two attributes beyond 04 §5.10: `notices` (the read notices, printed after the lines) and, transiently, `image_block` (removed by the member after attaching the image to the running `r` result).
4. The `r` tool's `details` adds `plot_files` and `plot_index` to the 04 §4.4 record so that `peter$plot(which)` finds the PNGs of plots that were listed as not attached (IC-67 says only "kept in the session's out store"; P09 renders them to files and lists them in its plot events).
5. `peter$plot(which = k)` reads the plots of the session's last completed `r` result (the current call's plots are not yet in the transcript); `which = NULL` records the current device's plot.
6. Risk levels for path classes 04 §9.4 does not name: reads of `critical` and `control` paths are level 2 (as `protected`), except that the project root itself reads at level 0; writes to `tempdir()` are level 2 (as in the project) and writes to `critical` paths level 4 (as `control`); `temp`, `outside`, `url`, `wildcard` and `unknown` paths read at 1, and `instructions`, `protected`, `outside`, `url`, `wildcard` and `unknown` paths write at 3.
7. The members `help`, `search`, `describe`, `plot` and `out` also carry an `execute`, so a preset may declare them (IC-37: "any spec with an `execute` may be put in the array by a preset"); their default exposure is `r`.
8. A pasted patch envelope is applied to the files it names and is not routed through `doc.edit` (P15 routes `oldText`/`newText` edits of a bound document; an envelope may touch several files).
9. `search_grep()` has the `sort` argument of IC-71 in addition to 04 §7.10's argument list.
10. Dependency-plan observations (04 wins; no effect on P10's code): P02's `gptr_tool()` has no `render` argument although IC-69 adds `render = function(call, result, width)` to tool specs (P10 sets none); P07's stand-in loader registers no `r_session` fragment stand-ins once any real fragment exists, so with P10 loaded the NS-2/NS-3 prefixes measure 2,620 instead of 2,750 until P19 and P22 add their fragments (Task 13).
11. Cross-plan defect for P06 (found in review, reproduced on the scratch package): 04 §6.8 gives an `r` member that has only a `fun` no generated `execute`, and 04 §7.6 has `dispatch_nested(name, input, ctx)` return "the tool result's `value`", but P06's `dispatch_nested()` aborts with `Tool <name> not found` when the spec has no `execute`. So a plugin member written as `gptr_tool(..., fun = f, exposure = "r", namespace = "pkg")` fails when model code calls it (`peter$pkg$f()` inside `r`), which P17's acceptance 3a (`peter$trials$search("asthma")`) and P19's "a plugin r member ... inside a worker" test exercise. P10 follows 04 (`member_closure()` calls `dispatch_nested()` for every nested call); it cannot run such a member around the gate without bypassing the permission check. The fix belongs in P06: when `tool$execute` is `NULL`, run `tool$fun` through P02's `spec_tool_execute(fun, output_tokens)` (the generated execute of 04 §6.8) with the validated input. P10's own built-ins all carry an `execute`, so P10's tests are unaffected.
12. `ns_catalog()`, completion (`ns_member_names()`), namespace prints and `peter$search()` read specs with `registry_all("tool")`, which returns lazy tool placeholders unactivated (P02), and render a placeholder from its manifest declaration (`peter$<ns>$<signature>  # <first sentence>`); only resolving or calling a member by name goes through `registry_get()`, which activates the plugin (04 §10.8: "The factory runs on the first `registry_get()` of a provided capability").
13. A `deferred` un-namespaced spec that has only an `execute` resolves to a member whose formals come from its schema (04 §9.1: "`deferred`: found only through `peter$search()` (still callable)"); IC-37 names only specs with a `fun`, so this extends resolution to the one exposure whose specs `peter$search()` advertises as callable.
14. `gptr.r_max_images` (IC-67: plots attached per `r` result) also caps the images that `peter$plot()` and `peter$read()` attach through the r-call marker, separately from the evaluator's own captured plots (which P09 caps); the refused ones are counted and named in the result text.

**Validation executed while writing this plan** (scratch directory `work/plans/P10/v3/`):

- Every ```` ```r ```` block of this plan was extracted and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'` (all parse); the `R/` and `tests/testthat/` files reassembled from the blocks are byte-identical to the verified scratch sources.
- No left-arrow assignment (checked through `getParseData()` `LEFT_ASSIGN` tokens), no `%>%`, no non-ASCII byte in any code block; `lintr::lint()` with the repository's `.lintr` linters (assignment `=`/`<<-`, line length 100, snake_case with the S3 regex) reports nothing for the eight `R/` files and nine test files.
- The P01-P09 sources were extracted from their plans (first as of 2026-10-01 10:55, then again at 11:50 after concurrent revisions of P01-P08; both runs gave the results below) and loaded with P10's sources: (a) by `sys.source()` into one environment, task by task, to record each task's red and green counts (Steps 2 and 4); (b) as a scratch source package `gptr` through `testthat::test_local(load_package = "source")` with P01's `setup.R` and helpers: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1053 ]` for `filter = "tool-|copy-tools"`, including the shim test of acceptance 4 and the nine copy rows run in child `Rscript` processes. (The review of 2026-10-01 re-ran (b) after its fixes: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1077 ]`, and re-derived every red and green count of Steps 2 and 4 by assembling the package as it stands at each step; see the Plan review log.)
- P01's `lint_scan()` (the scanner of `test-lint-rules.R`, extracted from P01's Task 20) over the eight `R/tool-*.R` files: 0 hits.
- P01's architecture helper (`arch_edges()`, `arch_check()`) over the combined sources: 569 call edges from `tool-*.R` files, 0 violations; every literal service name used by P10 (`ns.resolve`, `ns.names`, `search.sources`, `doc.edit`, `doc.site`, `skill.body`, `skill.catalog`, `mcp.catalog`, `risk.classify`) is in the 04 §7.0 service table.
- P07's runner `dev/bench/tokens/run.R` (as in P07's plan at 2026-10-01 11:47, with its static-prefix gate) against the scratch package: `--check` fails with "no baseline row" before Task 13's update, `--update ns02b-data-first-pipe` writes the row shown in Task 13, and `--check` then passes with the table shown.

## Plan review log

Adversarial review of 2026-10-01 against 05 (P10), 04 (with §15), 03, 00-conventions and the dependency plans P01-P09 (and the consumers P17, P18, P19). Every R block was extracted and parsed, the eight `R/` files and nine test files were assembled from the plan into a scratch source package together with P01-P09's code extracted from their plans, and the P10 suite was run there (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1077 ]`); the red and green counts of every Step 2 and Step 4 were re-derived by assembling the package as it stands at that step. The repository's three linters report 0 lints; no `<-`, `%>%`, `:::` or non-ASCII byte occurs in code.

| # | Severity | Location | Verdict | What changed, or why rejected |
|---|---|---|---|---|
| 1 | blocker | Task 9 `ns_catalog()`, `ns_search_docs()`, `member_search()`; Task 8 `ns_member_names()`, `print.gptr_ns` | applied | They called `registry_get()` for every tool name, which activates every lazy plugin when the prompt freezes (the `plugins` section) and on every `peter$search()`, against 04 §10.8 ("puts `extension.declarations` ... into the frozen prompt before activation, so activation never changes the cached prefix"); P17's acceptance 3a asserts the toy package is still not loaded after the first `peter()` call. They now read `registry_all("tool")`, which returns tool placeholders unactivated, and render a placeholder from its declaration through the new `ns_spec_line()`; only resolving a member by name activates its plugin. New test "a lazy plugin is catalogued, completed and searched through its declarations"; Global Constraints, Task 8/9 prose, interfaces, header (§10.8) and Self-review readings 12 updated. |
| 2 | major | Task 1 `member_budget()` | applied | Inside `r` it capped member prints at 0.6 x the whole `r` budget, so ten prints in one loop could each take 1,500 tokens; 04 §9.4 says "at most 0.6x the remaining `r` budget". The r-call marker now counts the estimated tokens member prints wrote (`printed`, updated by `ns_print_lines()`), and the cap is `floor(0.6 * (gptr.r_output_tokens - printed))`; new test "member prints inside one r call shrink the budget". |
| 3 | major | Task 1 `r_call_attach_image()`; Task 11 `r_tool_result()` | applied | Images attached by `peter$plot()` and `peter$read()` were unbounded (a loop over 50 image reads attached 50 images), although IC-67 caps attached images per `r` result at `gptr.r_max_images` (3). The marker now refuses images beyond the cap and counts them in `dropped`, and the `r` result text ends with `[k image(s) from peter$plot() or peter$read() not attached: at most n per r call]`; tests in Tasks 1 and 11 ("images beyond gptr.r_max_images ..."); the option is listed under consumed options; Self-review reading 14. |
| 4 | major | Task 2 `walk_tree()`/`walk_files()` | applied | `max` was applied to the walker's breadth-first entry count of every kind, so `walk_files(type = "file", max = 5)` on a tree of directories returned no file at all, and `truncated` was set even when nothing was left out. The walker now counts only rows of the requested type (`max_rows`, `count`) and keeps the 500,000-entry safety cap for all entries; `truncated` is `TRUE` exactly when rows were left out. New test "max counts only rows of the requested type". |
| 5 | major | Task 8 `member_closure()` with a `fun`-only plugin member; P06 `dispatch_nested()` | applied | Reproduced on the scratch package: `peter$wdemo$hello()` called from model code fails with `Tool wdemo/hello not found`, because P06's `dispatch_nested()` requires `tool$execute`, while 04 §6.8 gives `fun`-only `r` members no generated `execute` and 04 §7.6 promises the tool result's value. P10 already follows 04 (every nested call goes through `dispatch_nested()`); calling `fun` around the gate would bypass the permission check, so no P10 code changes. Recorded as Self-review item 11 with the P06 fix (run `fun` through P02's `spec_tool_execute()` when `execute` is `NULL`); it affects P17 acceptance 3a and P19's worker test, not P10's tests. |
| 6 | minor | Tasks 1, 2, 8, 9, 10, 11 Steps 2 and 4; Plan acceptance; Self-review validation | applied | The red/green counts no longer matched the tests (the resumed fixes added tests). All re-derived on the scratch package: Task 1 `FAIL 8` / `PASS 28`; Task 2 `FAIL 11` / `PASS 48`; Task 8 `FAIL 11 \| PASS 28` / `PASS 79`; Task 9 `FAIL 5 \| PASS 79` / `PASS 126`; Task 10 `FAIL 50 \| PASS 129` / `PASS 287`; Task 11 `FAIL 23 \| PASS 9` / `PASS 79`; acceptance 1 `PASS 1077`, acceptance 2 `PASS 283`, `tool-namespace` `PASS 287`, `tool-r$\|copy-tools` `PASS 88`. Tasks 3-7 and 12 were unchanged and re-confirmed. |
| 7 | minor | Global Constraints (copy-safety line); Task 8 prose | applied | The plan claimed member arguments never travel in a list (R1), but a member called from model code hands `dispatch_nested(name, input, ctx)` the input list that 04 §7.6 fixes. The text now says so, keeps the promise path for user calls, explains that `describe` (the one P10 member that takes a user object) sends labels and computes locally, and documents the one-copy cost for a plugin member that receives a user object from model code. |
| 8 | minor | Global Constraints | applied | The consumed option `gptr.r_max_images` (`3L`, P09) was missing; added with its contract text. |
| 9 | minor | Global Constraints; all test files | applied | 00-conventions §7 requires `expect_snapshot()` for printed output and wins unless a plan names the exception; the plan tests prints with exact `capture.output()` expectations. The exception is now named in Global Constraints with its reason (byte-exact Pi formats and budgets). |
| 10 | minor | Task 8 `ns_names()`, Task 9 `ns_catalog()`, `bm25_search()` | applied | Signatures differed from 04 §7.10 (`ns_names(pattern = "")`, `ns_catalog(session = NULL, ...)`, `bm25_search(index, words, limit = 8L, k1 = 1.2, b = 0.75)`). Now exactly `ns_names(pattern)`, `ns_catalog(session, kinds = c("plugin"), budget = 1500L)`, `bm25_search(index, words, limit = 8L)` (k1 and b are constants `bm25_k1`, `bm25_b`); every caller passes the arguments. |
| 11 | minor | Task 8 `ns_member_spec()`, `member_signature()`; Task 9 test | applied | `peter$search()` listed a `deferred` spec that has only an `execute` (kind `deferred`, signature `peter$rare_thing()`), but `ns_resolve()` refused it, although 04 §9.1 says deferred tools are "still callable". `ns_member_ok()` now admits deferred `execute`-only specs (closure formals from the schema, as `member_closure()` already supports) and `member_signature()` uses those formals; the search test calls the member. Self-review reading 13. |
| 12 | minor | Task 11 test "images attached by peter$plot() ..." | applied | Vacuous: the evaluator's own captured plot satisfied `length(imgs) >= 1` even if `peter$plot()` attached nothing. It now asserts an 800-pixel-wide image, which only `peter$plot(width = 800L)` produces (P09's captures are 768 wide). |
| 13 | minor | Task 13 prose | applied | The fixture's result text was called "the exact output" of the code; re-running it shows `tapply()` orders the `diet` groups by collation (`HF control` in the C locale). Re-checked with `LC_ALL=en_US.UTF-8` (identical to the fixture) and the claim now names the locale; tokens are the same and the runner replays the recorded text. |
| 14 | minor | Task 10 `member_plot()` | applied | When `plot_png()` returns `NULL` (the device could not render) a `NULL` block was attached to the result's content. It now signals `gptr_error_invalid_argument` instead. |
| 15 | minor | Task 10 risk (`tempdir()` writes at level 2) | rejected | 04 §9.4 lists "2 in project, 3 outside/protected", but P01's `path_class()` has a separate `temp` class and 03 P9 lists `tempdir()` among the places gptr may write; level 2 for scratch files is the reading the plan already records (Self-review reading 6), not a defect. |
| 16 | minor | Task 12 Step 2 (the rows pass at once) | rejected | Not a TDD violation: the rows guard behaviour implemented in Tasks 8-11, and the negative control (`keep = list(big)`, exactly one copy) shows the harness detects a held reference; the step says how to see a row fail. |
| 17 | minor | Task 10 `tool_write_execute()` message uses the path as given | rejected | Matches Pi (report 01 §2.4: `Successfully wrote to ${path}` "where `path` is the string the model passed"); `details$path` carries the absolute path. |
| 18 | minor | Task 8/10 nested-call tests mock `dispatch_nested()` | rejected | The unit tests isolate P10 from P06 on purpose, and Task 11's end-to-end test runs the real P06 `dispatch_nested()` (`details$nested[[1]]$tool == "grep"`), so the real gate path is covered. |

## Cross-plan consolidation log

Cross-plan consistency pass of 2026-10-01 against 04 (with §15), 03, 05 and the related plans. Every ```` ```r ```` block was re-extracted and parsed with `Rscript --vanilla`; no `<-` or `%>%` occurs in code. No code block, test or expected count changed.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | minor | Task 8 Consumes (`registry_add` signature); Task 9 Consumes | applied | Both lines gave P02's signature as `registry_add(spec, source, rank, session = NULL, state = "lazy")`; 04 §7.2 and P02 define the default `state = "active"`. Both now read `state = "active"` and note that tests pass `state = "lazy"` for plugin placeholders (Task 8's `local_spec()` relies on the `active` default; Task 9's lazy-plugin test passes `state = "lazy"` explicitly). Text only: the code already matched 04, and the existing tests exercise both states (every `local_spec()` member resolves as active; the lazy-plugin test asserts the placeholder stays `lazy` through cataloguing, completion and search), so no test was added and no count changed. |
