# P16 Checkpoints and rewind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every mutating agent action reversible (objects, files and session state) without copying user objects, and add `gptr_rewind()`/`gptr_checkpoints()`, the `/undo`, `/redo`, `/rewind`, `/checkpoints` commands and the `gptr_preimage()` generic (G7).

**Architecture:** Three L4 files. `ckpt-objects.R` holds copy-safe object pre-images (bindings in a private environment released with `rm()`, list and S4 images defused before dropping, eager disk images through `serialize_leaf(xdr = FALSE)`, data.table deep copies, settle and turn-end budgets), the `gptr_preimage()` S3 generic, the `state` checkpointer and the `checkpoint.note` service; `ckpt-files.R` holds the content-addressed blob store (XXH128, gzip level 1), its garbage collector, the pruned walk and tracker, and guarded 3-way restores; `ckpt-rewind.R` registers `builtin:checkpoints` (the `objects`, `files` and `state` checkpointers that P06's dispatcher calls around each sequential mutating tool call, hooks, the rewind `workspace_changes` block, the commands) and implements `gptr_rewind()` as G7's branch-in-place on the one session object (undo newest first to the lowest common ancestor, redo oldest first, then one appended `gptr.rewind` entry parented at the target) and `gptr_checkpoints()`.

**Tech Stack:** base R (methods, tools, utils, grDevices), rlang (`obj_address()`, `env_binding_are_*()` through P09, `hash()`/`hash_file()` through P01, weak references), jsonlite (through P01's `json_encode()`), ps (through P04's `pid_alive()`), testthat 3e, withr, processx (tests), data.table (Suggests; optional method and tests).

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2 rows `ckpt-*`, §5.11, §6.4, §6.16, §6.9.1, §7.3 `<context>` text, §11.1 checkpointers row), dev/spec/04-interface-contract.md (§1.3, §2.2 `busy`/`rewind_range`/`rewind_partial`, §3.1 `gptr.undo_*`/`gptr.checkpoint*`, §4.1.1, §4.6 `gptr.checkpoint`/`gptr.rewind`, §5.1 `last_rewind`/`editor_text`, §5.12 `gptr_checkpoints`, §6.5 `gptr_rewind()`/`gptr_checkpoints()`, §6.6 `gptr_preimage()`, §7.0 `checkpoint.note`, §7.16, §10.2 row 29 `checkpointer`, §10.3 `builtin:checkpoints`, §10.4 `session_before_tree`/`session_tree`/`checkpoint`, §11.1, §11.14, §12, §15 IC-31, IC-33, IC-52, IC-53, IC-65, IC-71), dev/spec/05-plan-decomposition.md (P16).

**Depends on:** P11, P15 (and, through them, P01-P10). **Milestone:** M3.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (`=` for assignment, never the left arrow; native `|>`; ASCII-only R sources; `pkg::fun()` calls; `gptr_abort()`/`gptr_warn()`/`gptr_inform()`; no `:::` in `R/`; no `.GlobalEnv`; testthat 3e; no network in tests; one commit per task). Plan-specific requirements, copied from the spec:

- Owned files (05 P16 "Owns"): `R/ckpt-objects.R`, `R/ckpt-files.R`, `R/ckpt-rewind.R`, `tests/testthat/test-ckpt-objects.R`, `tests/testthat/test-ckpt-files.R`, `tests/testthat/test-ckpt-rewind.R`, `tests/testthat/test-copy-ckpt.R`; `NAMESPACE` and `man/` only through `devtools::document()`.
- Layer L4 (03 §3.2). L4 "may call: the extension API (`gptr$register()`, `ctx`), L0, their own area, the declared services `eval-*`, `env-*`, `tool-walk`, `proc-*`, the §7.0 service table of the contract, and the **kernel SDK** allowlist [IC-33]"; "L6 and L3 never call an L4 capability by function name".
- Exports (04 §6.5, §6.6; 3 of the 63): `gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"), force = FALSE, preview = FALSE)`, `gptr_checkpoints(s, all = FALSE)`, `gptr_preimage(x, name, ctx, ...)` [experimental] with S3 methods `default` and `data.table`.
- `gptr_preimage()` returns `list(mode = "ref" | "copy" | "none", reason = chr(1) | NULL, copy = <deep copy> | NULL)`; `ctx` is `list(predicted = chr in assign, modify, byref, remove, none; bytes num(1); budget num(1))`; "Packages add methods with delayed `S3method(gptr::gptr_preimage, cls)`".
- Internal cross-plan functions (04 §7.16): `builtin_checkpoints(gptr)` "registers `checkpointer` specs `objects`, `files`, `state`; command specs `/undo`, `/redo`, `/rewind`, `/checkpoints`; the service `checkpoint.note`"; `ckpt_predict(code)` -> `list(assign, modify, byref, remove, super, files, unknown, process)` ("P11's `code_targets()` reduced"); `ckpt_store_put(path)` / `ckpt_store_get(hash, dest)` ("content-addressed blobs `<root>/checkpoints/blobs/<2hex>/<xxh128>[.gz]`"; consumer P23; `ckpt_store_put()` is in the IC-33 kernel SDK).
- Service (04 §7.0): `checkpoint.note` = `function(call, run) chr(1) or NULL` ("cannot be undone: ..."), provided by P16, owned by `builtin:checkpoints`, consumed by P06's permission request record and P11's detail view.
- `checkpointer` kind (04 §10.2 row 29) [experimental]: "`scope` (`objects`, `files`, `state`, `artifacts`, `other`); `before` `function(call, ctx)` -> token; `after` `function(call, ctx, token)` -> JSON-able fragment; `undo`/`redo` `function(fragment, ctx, force)` -> chr report lines; `prune` `function(live_keys, ctx)`; `describe` `function(fragment)` -> chr"; "never throws into the loop (a failure marks its fragment not restorable); runs only for sequential, non-read-only tools".
- Options (04 §3.1): `gptr.undo_capture_max` `1e8`, `gptr.undo_max_bytes` `1e9`, `gptr.undo_spill_max` `2e9`, `gptr.undo_turns` `20L`, `gptr.checkpoint` `"on"` (`"on"`, `"files"`, `"off"`), `gptr.checkpoint_disk_bytes` `2e9`, `gptr.checkpoint_days` `30`, `gptr.checkpoint_turns` `100`, `gptr.checkpoint_track_file_max` `1e6`, `gptr.checkpoint_track_total` `1e8`, `gptr.checkpoint_capture_max` `5e7`, `gptr.checkpoint_scan_budget` `0.25`, `gptr.checkpoint_rng` `TRUE`, `gptr.checkpoint_close_devices` `FALSE`; settings key `checkpoint` `"on"` (04 §11.2; P08 registers its `setting` spec). Read through `gptr_opt()` / `setting_get()`.
- Conditions (04 §2.2): `gptr_error_busy` (field `session`; "the session is running"), `gptr_error_rewind_range` (fields `turn`, `turns`; "rewind target out of range"), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_permission` (IC-53 item 3: `gptr_rewind` "on a session other than the running one" from model code), warning `gptr_warning_rewind_partial` (field `report`).
- Entries (04 §4.6): `gptr.checkpoint` "G7 §3.1 shape (object names, addresses, sizes, classes, capture mode; file paths, hashes, modes; state names; artifact `current` before/after); never values" (P06 writes the container `{tool_call_id, fragments: {<checkpointer>: <fragment>}}`); `gptr.rewind` "`{from, to, keep, restore, report: [chr]}`; parented at the target, becomes the leaf".
- Checkpoint store (04 §11.14): `<root>/checkpoints/blobs/<2hex>/<xxh128>[.gz]` "file contents (gzip level 1), shared by the project's sessions"; `<root>/checkpoints/objects/<session id>/<key>.rdsx` "spilled object images (serialize_leaf(ascii = FALSE, xdr = FALSE))"; `<root>/checkpoints/index.json` `{"blobs": {"<hash>": <last referenced epoch>}}` "rebuilt if missing"; "Never inside `.git`, never in `R_user_dir()`". `<root>` is the workspace root (`.gptr/` or `tempdir()/gptr`, 04 §11.1).
- Events (04 §10.4): `session_before_tree` (first decision; payload `from`, `to`, `plan` (df); returns `list(cancel = TRUE, reason)`), `session_tree` (notify; `from`, `to`, `report`), `checkpoint` (notify; `tool_call_id`, `objects`, `files`, `restorable` (counts)); all emitted by P16.
- Context block kind `workspace_changes` "(attrs `since`, `reason`, optional)" (04 §4.1.1): a partial rewind "sends `<workspace_changes since=... reason="rewind">` (about 87 tokens)" (03 §6.16); a full restore sends nothing.
- Session fields (04 §5.1): `last_rewind` "report of the last `gptr_rewind()`", `editor_text` "the undone prompt after a rewind".
- Listing (04 §5.12): class `c("gptr_checkpoints", "gptr_listing", "data.frame")`, columns `turn`, `id`, `time`, `prompt`, `objects`, `files`, `held_mb`, `disk_mb`, `branch`, built by `new_listing()`.
- Copy safety (03 §6.4, 04 §1.3): R1 "never hold a user object ... Designated values follow the value policy"; R6 "No `mget()` or list snapshots of user objects. Checkpoint pre-images are bindings in a private environment released with `rm()`; list and S4 pre-images are defused before dropping; a finalizer does the same for dropped sessions"; R7 "Every `serialize()`/`saveRDS()` of user data passes `ascii = FALSE` explicitly ... through one leaf wrapper"; `gptr_rewind()` is tagged [R1][R6] ("pre-images are released or swapped by reference, never copied"); `gptr_preimage()` methods are leaves [R4].
- Review amendments (05 P16, 04 §15): "File restores stay inside the project root and `tempdir()` unless the user confirms each outside path (`ask_human`, IC-52)"; "blob garbage collection keeps blobs referenced by any session file of the project and skips while another live pid holds a session lock (IC-71)" ("prunes only blobs unreferenced by every session file of the project and older than `gptr.checkpoint_days`"); "after a Codex `workspace-write` exec the files checkpointer walks, so `/undo` covers it (IC-65)".
- Modes (03 §6.16, G7 §4.5): "plan: conversation only"; manual/edits: "the permission detail view says 'cannot be undone' when capture is impossible"; auto: "a 25-token notice" (`note: <name> (<size>) was <overwritten|modified|removed> without an undo copy (<reason>).`).
- Lint rules that bind this plan (04 §12.3): no `Sys.setenv(` outside `auth-dotenv.R`, no `.Random.seed` assignment outside `rng_swap()`/`with_seed_preserved()`, no `serialize(`/`saveRDS(` without `ascii = FALSE` outside `utils-paths.R`, no `withr::` in `R/`, `cli_*()` first arguments literal.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `R/ckpt-objects.R` | create (Task 1), append (Tasks 2, 3) | shared helpers; `gptr_preimage()` and methods; the pre-image store (capture, settle, restore, uncreate, defuse, spill, drop, sweep, unshared bytes); per-session state; capture policy; `ckpt_predict()`; the objects checkpointer; turn-end budget; the `checkpoint.note` service function; the state checkpointer |
| `R/ckpt-files.R` | create (Task 4), append (Task 5) | content-addressed blob store (`ckpt_store_put()`, `ckpt_store_get()`), blob garbage collection (IC-71); pruned walk and tracker, baseline, the files checkpointer, CLI-route turn scans (IC-65), guarded 3-way undo and redo (IC-52) |
| `R/ckpt-rewind.R` | create (Task 6), append (Tasks 7, 8) | `builtin:checkpoints` declaration, the `checkpoint.note` service registration, checkpointer specs, hooks (`tool_result`, `agent_start`, `turn_end`, `agent_end`, `session_shutdown`), the rewind `workspace_changes` block, the `checkpoint` event; session tree, rewind planning, `gptr_rewind()`; `gptr_checkpoints()`; `/undo`, `/redo`, `/rewind`, `/checkpoints` |
| `tests/testthat/test-ckpt-objects.R` | create (Task 1), append (Tasks 2, 3) | store, policy, objects and state checkpointers, `gptr_preimage()`, `checkpoint.note` |
| `tests/testthat/test-ckpt-files.R` | create (Task 4), append (Task 5) | blob store, GC, walk, tracker, restores and guards |
| `tests/testthat/test-ckpt-rewind.R` | create (Task 6), append (Tasks 7, 8) | registration and records through `peter()`, rewind, redo, documents, listing, commands |
| `tests/testthat/test-copy-ckpt.R` | create (Task 1), append (Task 7) | G7's 24-verdict tracemem matrix and the serialize case; end-to-end copy rows for `peter()`, `gptr_rewind()`, `gptr_preimage()`, `gptr_checkpoints()` |
| `NAMESPACE`, `man/gptr_preimage.Rd`, `man/gptr_rewind.Rd`, `man/gptr_checkpoints.Rd` | generated | `devtools::document()` (Tasks 1, 7, 8) |

## Interfaces consumed (exact names; 04 is authoritative)

- P01: `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `gptr_warn(message, class, ..., .data = NULL, .once = NULL)`, `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`, `check_class(x, class, arg, null = FALSE)`, `check_number(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE)`, `check_string(x, arg, null = FALSE, empty = FALSE)`, `check_flag(x, arg, null = FALSE)`, `check_choice(x, choices, arg)`, `gptr_opt(name)`, `setting_get(key, session = NULL, default = NULL)`, `id_new(prefix = "", n = 10L)`, `hash_file(path)`, `hash_xxh128(x)`, `write_atomic(path, content)`, `serialize_leaf(object, xdr = TRUE)`, `path_norm(path)`, `project_root(path = getwd())`, `workspace_dir(path = getwd())`, `workspace_root(create = TRUE)`, `gptr_user_dir(which = c("config", "cache", "data"), create = FALSE)`, `path_class(path, root = project_root())`, `gptr_has_human()`, `gptr_can_prompt()`, `gptr_is_interactive()`, `est_tokens(x, class)`, `json_encode(x, pretty = FALSE)`, `json_obj()`, `new_listing(df, class, footer = NULL)`, `block_text(text, signature = NULL)`, `msg_text(msg)`, `ev_new(type, ...)`, `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_get(name)`, `ext_service_has(name)`, `` `%||%` ``; tests: `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_fake_provider(script, name = "fake", type = "chat", .env = parent.frame())`, `fake_tool(name, ..., .text = NULL, .id = NULL)`, `fake_requests(spec)`, `local_gptr_options(..., .env = parent.frame())`, `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)`, `rscript_path()`, `front_end()` (mocked).
- P02: `gptr_spec(kind, name, ...)`, `gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"), budget = 300L, order = 650L)`, `gptr_command(name, handler, description = NULL, complete = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `registry_all(kind, session = NULL)`, `registry_get(kind, name, session = NULL)`, `ev_dispatch(event, payload, session = NULL, ctx = NULL)`, `ctx_new(session, run = NULL)`; the factory API object members `gptr$state`, `gptr$register(spec)`, `gptr$on(event, handler, matcher = NULL)`; `ctx$session`, `ctx$envir`, `ctx$run`, `ctx$mode()`, `ctx$has_ui()`, `ctx$ui()`; tests: `gptr_register(spec)`, `gptr_registry(kind = NULL, diagnostics = FALSE)`, `gptr_hook(event, handler, matcher = NULL)`.
- P04: `pid_alive(pid, create_time = NULL)`.
- P06 (kernel SDK, IC-33): `session_data(s)`, `session_live(s)` (`$ctx`), `session_home(s)`, `session_append(s, entry)` (an entry in R shape `list(type = "custom", custom_type, data)`; it sets `id`, `parent_id` = the current leaf, `timestamp`, and makes the entry the leaf), `run_current()` (fields `session`, `signal`), `run_eval_env(run)`; `.d` fields `id`, `entries`, `index`, `leaf`, `turns`, `status`, `reason`, `last_text`, `fork_of`, `replayed`, `file`, `model`, `last_rewind`, `editor_text`; user-message entries carry `gptr$turn`; the dispatcher's `checkpoint_before()`/`checkpoint_after()` and the container `{tool_call_id, fragments}`; session locks `<file>.lock/pid` (two lines: pid, process creation time); tests: `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))`.
- P08: `peter()`, `gptr_on(s, event, handler, matcher = NULL)` (tests); the IC-53 one-shot token `run$signal$control`.
- P09: `env_snapshot(envir, previous = NULL)` (df `name`, `kind`, `address`, `class`, `bytes`, `shape`, `fp`; never forces promises).
- P11: `code_targets(code)` -> `list(assign, modify, byref, remove, super, files, unknown, process, calls, parse_error)` (IC-31); service `ui.get` = `function(session = NULL) <spec:ui>` (`has_ui()`, `select(title, choices, default = NULL, details = NULL, multiple = FALSE, allow_other = FALSE)`); test helper `local_scripted_ui(answers = list(), .env = parent.frame())`.
- P15: the `session_tree` hook of `builtin:documents` makes undone blocks inert (04 §7.15); options `gptr.record`, `gptr.replay`.

## Interfaces produced

- `gptr_rewind()`, `gptr_checkpoints()`, `gptr_preimage()` (exports above).
- `builtin_checkpoints(gptr)`; checkpointer specs `objects`, `files`, `state` (scope = name), each also carrying `preview(fragment, ctx, force, direction)` (a dry run, an item table) and `ckpt_state` (the extension state); commands `undo`, `redo`, `rewind`, `checkpoints`; the `context_block` `workspace_changes` (placement `both`, order 101, budget 300) rendering the rewind note.
- `ckpt_predict(code)`, `ckpt_store_put(path)`, `ckpt_store_get(hash, dest)`, service `checkpoint.note`.
- Events `checkpoint`, `session_before_tree`, `session_tree`; entries `gptr.rewind` (data `from`, `to`, `keep`, `restore`, `report`, plus the additive `undone`, `redone`: the checkpoint entry ids undone and redone) and the files-scan `gptr.checkpoint` entries `{tool_call_id: "scan-<fragment id>", fragments: {files}}`.

## Tasks

1. Pre-image store and `gptr_preimage()` (`ckpt-objects.R`) + G7 copy matrix
2. Capture policy, the objects checkpointer and `checkpoint.note` (`ckpt-objects.R`)
3. The state checkpointer (`ckpt-objects.R`)
4. Content-addressed blob store and garbage collection (`ckpt-files.R`)
5. Walk, tracker, the files checkpointer and guarded restores (`ckpt-files.R`)
6. `builtin:checkpoints`: specs, hooks, rewind block, `checkpoint` event (`ckpt-rewind.R`)
7. Session tree and `gptr_rewind()` (`ckpt-rewind.R`) + end-to-end copy rows
8. `gptr_checkpoints()` and the console commands (`ckpt-rewind.R`)

### Task 1: Pre-image store and `gptr_preimage()`

**Files:**
- Create: `R/ckpt-objects.R`
- Test: `tests/testthat/test-ckpt-objects.R` (create), `tests/testthat/test-copy-ckpt.R` (create)
- Generated: `NAMESPACE`, `man/gptr_preimage.Rd` (`devtools::document()`)

**Interfaces:**
- Consumes: P01 `id_new(prefix = "", n = 10L)`, `write_atomic(path, content)`, `serialize_leaf(object, xdr = TRUE)` (R7: `serialize(object, NULL, ascii = FALSE, xdr = xdr)`); `rlang::obj_address()`; `methods::slotNames()`; tests: P01 `expect_no_copy()` (and the `save_rds()` leaf in the child script), `local_gptr_options()`.
- Produces: the export `gptr_preimage(x, name, ctx, ...)` (04 §6.6) with methods `gptr_preimage.default` and `gptr_preimage.data.table`; internal helpers used by Tasks 2-8: `ckpt_frag_id()`, `ckpt_chr(x)`, `ckpt_scalar(x, default = "")`, `ckpt_num(x)`, `ckpt_json_num(x)`, `ckpt_fmt_bytes(b)`, `ckpt_items()`, `ckpt_item(out, item, ok, action)`, `ckpt_lines(items)`, `ckpt_is_reference(x)`, `ckpt_within_budget(bytes, budget)`; the store `ckpt_obj_store(dir = NULL)` (environment: `slots`, `index`, `dir`, `seq`), `ckpt_index_empty()`, `ckpt_index_add(store, key, frag, name, role, where = "memory", file = "", bytes = NA_real_, turn = NA_integer_, expect = "")`, `ckpt_index_find(store, frag, name, role)`, `ckpt_index_remove(store, keys)`, `ckpt_addr(envir, name)`, `ckpt_capture(store, envir, names)` -> df(`name`, `key`, `address`), `ckpt_capture_value(store, value)`, `ckpt_disk_file(dir, key)`, `ckpt_write_image(file, envir, name)`, `ckpt_read_image(file)`, `ckpt_capture_disk(store, envir, name)`, `ckpt_settle(store, envir, pending, frag = "", turn = NA_integer_)` -> df(`name`, `key`, `status`, `pre_address`, `post_address`), `ckpt_restore(store, envir, name, key, expect = NULL, force = FALSE, frag = "", turn = NA_integer_)` -> `list(ok, reason, redo, address)`, `ckpt_uncreate(store, envir, name, frag = "", turn = NA_integer_)`, `ckpt_leaf_children(x)`, `ckpt_defuse(store, key)`, `ckpt_spill(store, key)`, `ckpt_drop(store, keys)`, `ckpt_obj_sweep(store)`, `ckpt_unshared_bytes(store, key, envir, name, depth = 4L)`; the per-session state `ckpt_ck_new(sid, spill_dir = NULL)` (environment: `sid`, `obj`, `snap`, `files`, `state_img`, `notes`, `rewind_note`, `rewind_since`, `gc_done`) with its finalizer `ckpt_ck_finalize(ck)`.

The store is G7's verified `p1/ckpt_obj.R` (report section 5.2; verification log items 1-4) with the deltas listed in the file header. The per-session checkpoint state `ckpt_ck_new()` and its finalizer `ckpt_ck_finalize()` (G7's `c06b_finalizer.R`) are part of this task, because the copy suite's finalizer row needs them. The copy suite reproduces G7's 24 EDIT verdicts of `run_cases.R` (report section 5.2 output: 8 COPY lines, 16 in-place lines) and the five `dbg_ser.R` serialize cases, plus two P16 rows (the R7 image writer and the state finalizer of G7's `c06b_finalizer.R`). Row c17 counts the attribute duplicate by address because tracemem does not report it (G7 logged "tracemem duplication events: 0" for c17 and found the copy by address: `attr<-` on a long vector makes an ALTREP wrapper, which tracemem does not see).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ckpt-objects.R`:

```r
# tests/testthat/test-ckpt-objects.R -- pre-images, the capture policy, the objects and state
# checkpointers and gptr_preimage() (P16). Model code is simulated with agent_eval(), the way the
# evaluator runs top-level expressions in the workspace (values never kept); values are compared,
# and addresses where G7 says an operation must not copy.

agent_eval = function(code, envir) {
  for (ex in parse(text = code, keep.source = FALSE)) eval(ex, envir)
  invisible(NULL)
}

test_that("gptr_preimage() keeps value objects by reference and refuses reference objects", {
  ctx = list(predicted = "assign", bytes = 64, budget = 1e9)
  expect_identical(gptr_preimage(1:3, "x", ctx), list(mode = "ref", reason = NULL, copy = NULL))
  res = gptr_preimage(new.env(), "cfg", ctx)
  expect_identical(res$mode, "none")
  expect_match(res$reason, "reference object")
  expect_identical(gptr_preimage(methods::new("externalptr"), "p", ctx)$mode, "none")
  expect_identical(gptr_preimage(mtcars, "mt", list(predicted = "byref", bytes = 7e3,
                                                     budget = 1e9))$mode, "ref")
})

test_that("the data.table method copies only predicted := and set() targets within budget", {
  skip_if_not_installed("data.table")
  dt = data.table::data.table(a = 1:3)
  ctx = list(predicted = "modify", bytes = 100, budget = 1e9)
  expect_identical(gptr_preimage(dt, "dt", ctx)$mode, "ref")
  res = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 100, budget = 1e9))
  expect_identical(res$mode, "copy")
  data.table::set(dt, 1L, "a", 99L)
  expect_identical(res$copy$a, 1:3)
  over = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 2e9, budget = 1e9))
  expect_identical(over$mode, "none")
  dry = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 100, budget = 1e9, dry = TRUE))
  expect_identical(dry$mode, "copy")
  expect_null(dry$copy)
})

test_that("capture, settle and restore swap values by reference", {
  e = new.env()
  e$x = c(1, 2, 3)
  e$y = "unchanged"
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, c("x", "y"))
  expect_identical(p$address, c(rlang::obj_address(e$x), rlang::obj_address(e$y)))
  agent_eval("x = x * 2", e)
  r = ckpt_settle(st, e, p, frag = "f1", turn = 1L)
  expect_identical(r$status, c("changed", "unchanged"))
  expect_false(exists(p$key[2], envir = st$slots))
  expect_true(exists(p$key[1], envir = st$slots))
  res = ckpt_restore(st, e, "x", r$key[1], expect = r$post_address[1], frag = "f1")
  expect_true(res$ok)
  expect_identical(e$x, c(1, 2, 3))
  expect_identical(rlang::obj_address(e$x), p$address[1])
  expect_identical(get(res$redo, envir = st$slots), c(2, 4, 6))
  expect_identical(st$index$role, "redo")
})

test_that("a restore refuses a binding changed after the checkpoint unless forced", {
  e = new.env()
  e$x = c(1, 2, 3)
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "x")
  agent_eval("x = x * 2", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  e$x = 0
  res = ckpt_restore(st, e, "x", r$key, expect = r$post_address)
  expect_false(res$ok)
  expect_match(res$reason, "conflict")
  expect_identical(e$x, 0)
  res = ckpt_restore(st, e, "x", r$key, expect = r$post_address, force = TRUE)
  expect_true(res$ok)
  expect_identical(e$x, c(1, 2, 3))
  expect_identical(ckpt_restore(st, e, "x", "pnone")$reason, "no pre-image")
})

test_that("removed bindings come back and created ones are unbound into redo images", {
  e = new.env()
  e$a = 1
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "a")
  agent_eval("rm(a); b = 2", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  expect_identical(r$status, "removed")
  res = ckpt_restore(st, e, "a", r$key, expect = NA_character_, frag = "f1")
  expect_true(res$ok)
  expect_identical(e$a, 1)
  expect_true(is.na(res$redo))
  k = ckpt_uncreate(st, e, "b", frag = "f1")
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(get(k, envir = st$slots), 2)
})

test_that("spilled images restore from disk; drop deletes images and defuses lists", {
  dir = withr::local_tempdir()
  e = new.env()
  e$x = seq(1, 10, by = 0.5)
  st = ckpt_obj_store(dir)
  p = ckpt_capture(st, e, "x")
  agent_eval("x[2] = 0", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  f = ckpt_spill(st, r$key)
  expect_true(file.exists(f))
  expect_false(exists(r$key, envir = st$slots))
  expect_identical(st$index$where, "disk")
  res = ckpt_restore(st, e, "x", r$key, expect = r$post_address)
  expect_true(res$ok)
  expect_identical(e$x, seq(1, 10, by = 0.5))
  expect_false(file.exists(f))
  e$L = list(a = 1:3, b = 4:6)
  p = ckpt_capture(st, e, "L")
  agent_eval("L$new = 1", e)
  r = ckpt_settle(st, e, p, frag = "f2")
  expect_lt(ckpt_unshared_bytes(st, r$key, e, "L"), 400)
  ckpt_drop(st, st$index$key)
  expect_identical(nrow(st$index), 0L)
  expect_identical(ls(st$slots), character())
  expect_identical(e$L$a, 1:3)
  expect_identical(e$L$new, 1)
})

test_that("the unshared-bytes walk visits a classed list's components, not its length()", {
  e = new.env()
  e$tm = as.POSIXlt(as.POSIXct("2024-01-01", tz = "UTC") + 0:99)
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "tm")
  agent_eval("tm = as.POSIXlt(as.POSIXct(tm) + 60)", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  expect_gt(ckpt_unshared_bytes(st, r$key, e, "tm"), 800)
})

test_that("defusing a data frame image leaves the user's data frame intact", {
  e = new.env()
  e$df = data.frame(a = 1:3, b = c("x", "y", "z"))
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "df")
  agent_eval("df$c = 1", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  ckpt_drop(st, r$key)
  expect_identical(e$df$a, 1:3)
  expect_identical(e$df$b, c("x", "y", "z"))
  expect_identical(ls(st$slots), character())
})

test_that("an eager disk image restores a large object edited in place", {
  dir = withr::local_tempdir()
  e = new.env()
  e$big = c(1, 2, 3)
  st = ckpt_obj_store(dir)
  d = ckpt_capture_disk(st, e, "big")
  expect_true(file.exists(d$file))
  expect_identical(ls(st$slots), character())
  agent_eval("big[1] = 10", e)
  ckpt_index_add(st, d$key, "f1", "big", "pre", where = "disk", file = d$file)
  res = ckpt_restore(st, e, "big", d$key, expect = ckpt_addr(e, "big"))
  expect_true(res$ok)
  expect_identical(e$big, c(1, 2, 3))
})

test_that("the sweep releases captures that no index row owns", {
  e = new.env()
  e$x = 1:3
  st = ckpt_obj_store()
  ckpt_capture(st, e, "x")
  expect_length(ls(st$slots), 1L)
  ckpt_obj_sweep(st)
  expect_length(ls(st$slots), 0L)
})

test_that("a collected checkpoint state releases its images (finalizer, G7 c06b)", {
  ck = ckpt_ck_new("s0000000008")
  e = new.env()
  e$x = seq(0, 1, length.out = 10)
  ckpt_capture(ck$obj, e, "x")
  slots = ck$obj$slots
  expect_length(ls(slots), 1L)
  rm(ck)
  invisible(gc())
  invisible(gc())
  expect_length(ls(slots), 0L)
})
```

Create `tests/testthat/test-copy-ckpt.R`:

```r
# tests/testthat/test-copy-ckpt.R -- copy safety of checkpoint pre-images (P16; G7 section 5.2,
# acceptance 2). Every row runs in a fresh Rscript --vanilla process through P01's
# expect_no_copy(): `setup` creates the objects (and, when the traced object is one the agent
# creates, the earlier steps too), `action` is the step under test, `edit` the edit whose
# tracemem copies are counted, and the last field the number of copies G7 measured
# (0 = in place, 1 = one copy). Rows reproduce G7's run_cases.R verdicts; the internal ckpt_*
# functions are fetched from the loaded namespace inside the child script.

ckpt_copy_prelude = c(
  "ns = asNamespace('gptr')",
  "for (fn in c('ckpt_obj_store', 'ckpt_capture', 'ckpt_settle', 'ckpt_restore', 'ckpt_drop',",
  "             'ckpt_spill', 'ckpt_ck_new', 'ckpt_write_image', 'save_rds')) {",
  "  assign(fn, get(fn, envir = ns))",
  "}")

ckpt_copy_setup = c(
  "A = rlang::obj_address",
  "agent = compiler::cmpfun(function(code, envir) {",
  "  for (e in parse(text = code, keep.source = FALSE)) eval(e, envir)",
  "  invisible(NULL)",
  "})")

ckpt_copy_x = c(ckpt_copy_setup, "x = runif(1e6)")
ckpt_copy_list = c(ckpt_copy_setup, "L = list(a = runif(1e6), b = runif(1e6))")
ckpt_copy_s4 = c(ckpt_copy_setup,
                 "setClass('Big', representation(counts = 'numeric', meta = 'data.frame'))",
                 "obj = new('Big', counts = runif(1e6), meta = data.frame(id = 1:10))")
ckpt_capture_x = "st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'x')"
ckpt_capture_l = "st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'L')"
ckpt_settle_x = "r = ckpt_settle(st, globalenv(), p, frag = 'f1')"

ckpt_copy_rows = list(
  list("c01 user edit, no gptr involvement", ckpt_copy_x, "", "x[1] = 0", "x", 0L),
  list("c01 user edit after agent edit (no snapshot)", ckpt_copy_x,
       "agent('x[2] = 0', globalenv())", "x[3] = 0", "x", 0L),
  list("c02 agent edit while mget() snapshot held", ckpt_copy_x,
       "snap = mget('x', envir = globalenv())", "agent('x[2] = 0', globalenv())", "x", 1L),
  list("c03 user edit after mget() snapshot dropped + gc", ckpt_copy_x,
       "snap = mget('x', envir = globalenv()); rm(snap); invisible(gc())", "x[1] = 0", "x", 1L),
  list("c03 second user edit", ckpt_copy_x,
       "snap = mget('x', envir = globalenv()); rm(snap); invisible(gc()); x[1] = 0",
       "x[2] = 0", "x", 0L),
  list("c04 agent edit while env pre-image held", ckpt_copy_x, ckpt_capture_x,
       "agent('x[2] = 0', globalenv())", "x", 1L),
  list("c04 user edit after settle (pre-image kept)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x[2] = 0', globalenv())", ckpt_settle_x), "x[3] = 0", "x", 0L),
  list("c05 user edit after capture + release (rm)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('y = sum(x)', globalenv())", ckpt_settle_x), "x[1] = 0", "x", 0L),
  list("c06 user edit after store garbage-collected", ckpt_copy_x,
       c(ckpt_capture_x, "rm(st, p); invisible(gc())"), "x[1] = 0", "x", 1L),
  list("c07 user edit of the NEW x (old kept)",
       c(ckpt_copy_x, ckpt_capture_x, "agent('x = x * 2', globalenv())"), ckpt_settle_x,
       "x[1] = 0", "x", 0L),
  list("c08 user edit after restore + redo dropped", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x = x * 2', globalenv())", ckpt_settle_x,
         "res = ckpt_restore(st, globalenv(), 'x', r$key, expect = r$post_address)",
         "ckpt_drop(st, res$redo)"), "x[1] = 0", "x", 0L),
  list("c08b user edit after restore (redo image kept)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x = x * 2', globalenv())", ckpt_settle_x,
         "res = ckpt_restore(st, globalenv(), 'x', r$key, expect = r$post_address)"),
       "x[1] = 0", "x", 0L),
  list("c10 user edit after pre-image spilled", ckpt_copy_x,
       c("st = ckpt_obj_store(dir = tempfile()); p = ckpt_capture(st, globalenv(), 'x')",
         "agent('x[2] = 0', globalenv())", ckpt_settle_x, "f = ckpt_spill(st, r$key)"),
       "x[3] = 0", "x", 0L),
  list("c10 user edit after restore from disk",
       c(ckpt_copy_x,
         "st = ckpt_obj_store(dir = tempfile()); p = ckpt_capture(st, globalenv(), 'x')",
         "agent('x[2] = 0', globalenv())", ckpt_settle_x, "f = ckpt_spill(st, r$key)",
         "res = ckpt_restore(st, globalenv(), 'x', r$key, expect = A(x), force = TRUE)",
         "ckpt_drop(st, res$redo)"), "", "x[4] = 0", "x", 0L),
  list("c11 user edit after saveRDS(get()) by name", ckpt_copy_x,
       c("save_pre = compiler::cmpfun(function(name, envir, file) {",
         "  saveRDS(get(name, envir = envir), file, compress = FALSE)",
         "})", "save_pre('x', globalenv(), tempfile())"), "x[1] = 0", "x", 0L),
  list("c12 user edit of column shared with pre-image", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')"), "L$a[1] = 0", "L$a", 1L),
  list("c12 user edit of shared column after drop", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "L$a[1] = 0",
         "ckpt_drop(st, r$key)"), "L$b[1] = 0", "L$b", 0L),
  list("c12d user edit of shared column after defuse+drop", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "L$b[1] = 0", "L$b", 0L),
  list("c12d user edit of other shared column", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "L$a[1] = 0", "L$a", 0L),
  list("c12e S4 slot edit after defuse+drop", ckpt_copy_s4,
       c("st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'obj')",
         "agent('obj@meta$cluster = rep(1:2, 5)', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "obj@counts[1] = 0", "obj@counts", 1L),
  list("c12e S4 slot edit, plain R baseline", ckpt_copy_s4, "", "obj@counts[1] = 0",
       "obj@counts", 1L),
  list("c17 agent attribute edit while pre-image held", ckpt_copy_x, ckpt_capture_x,
       c("a0 = A(x)", "agent('attr(x, \"unit\") = 1', globalenv())",
         "if (!identical(a0, A(x))) cat('tracemem[attr duplicate]\\n')"), "x", 1L),
  list("c12b user edit of column after L$new (no gptr)", ckpt_copy_list,
       "agent('L$new = 1', globalenv())", "L$b[1] = 0", "L$b", 0L),
  list("c12b user edit of column after M$a[1] (no gptr)",
       c(ckpt_copy_setup, "M = list(a = runif(1e6), b = runif(1e6))"),
       "agent('M$a[1] = 0', globalenv())", "M$b[1] = 0", "M$b", 0L)
)

ckpt_serialize_rows = list(
  list("serialize(x, con) without ascii at top level", ckpt_copy_x,
       "f = tempfile(); con = file(f, 'wb'); serialize(x, con, xdr = FALSE); close(con)",
       "x[1] = 0", "x", 1L),
  list("serialize(x, con, ascii = FALSE) at top level", ckpt_copy_x,
       c("f = tempfile(); con = file(f, 'wb')",
         "serialize(x, con, ascii = FALSE, xdr = FALSE); close(con)"),
       "x[1] = 0", "x", 0L),
  list("by-name serialize() without ascii", ckpt_copy_x,
       c("ser = compiler::cmpfun(function(nm, env, f) {",
         "  con = file(f, 'wb')",
         "  on.exit(close(con))",
         "  serialize(get(nm, envir = env), con, xdr = FALSE)",
         "  invisible()",
         "})", "ser('x', globalenv(), tempfile())"), "x[1] = 0", "x", 1L),
  list("by-name serialize() with ascii = FALSE", ckpt_copy_x,
       c("ser = compiler::cmpfun(function(nm, env, f) {",
         "  con = file(f, 'wb')",
         "  on.exit(close(con))",
         "  serialize(get(nm, envir = env), con, ascii = FALSE, xdr = FALSE)",
         "  invisible()",
         "})", "ser('x', globalenv(), tempfile())"), "x[1] = 0", "x", 0L),
  list("by-name saveRDS()", ckpt_copy_x, "save_rds(get('x'), tempfile())", "x[1] = 0", "x", 0L),
  list("ckpt_write_image() (serialize_leaf, rule R7)", ckpt_copy_x,
       "ckpt_write_image(tempfile(), globalenv(), 'x')", "x[1] = 0", "x", 0L),
  list("a collected checkpoint state releases its pre-images (finalizer)", ckpt_copy_x,
       c("ck = ckpt_ck_new('s0000000001'); p = ckpt_capture(ck$obj, globalenv(), 'x')",
         "rm(ck, p); invisible(gc()); invisible(gc())"), "x[1] = 0", "x", 0L)
)

ckpt_copy_check = function(rows) {
  for (row in rows) {
    n = expect_no_copy(c(ckpt_copy_prelude, row[[2L]]), row[[3L]], edit = row[[4L]],
                       object = row[[5L]], allow = row[[6L]], label = row[[1L]])
    expect_identical(n, row[[6L]], label = row[[1L]])
  }
}

test_that("G7's 24-verdict tracemem matrix reproduces, c03 and c06 included (acceptance 2)", {
  expect_length(ckpt_copy_rows, 24L)
  ckpt_copy_check(ckpt_copy_rows)
})

test_that("user data is serialised without a sticky reference only with ascii = FALSE (R7)", {
  ckpt_copy_check(ckpt_serialize_rows)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects|copy-ckpt")'`

Expected: every test of `test-ckpt-objects.R` errors with `could not find function "gptr_preimage"`, `"ckpt_obj_store"` or `"ckpt_ck_new"`; every copy row fails with `expect_no_copy(...): the script did not finish` (the child's `get('ckpt_obj_store', envir = ns)` finds nothing) and `n` is `NA`; summary `[ FAIL 73 | WARN 0 | SKIP 0 | PASS 1 ]` (11 erroring tests, 2 failures per copy row for 31 rows; on a build without `capabilities("profmem")` the copy tests skip: `[ FAIL 11 | WARN 0 | SKIP 2 | PASS 1 ]`).

- [ ] **Step 3: Write the implementation**

Create `R/ckpt-objects.R`:

```r
# ckpt-objects.R -- copy-safe object pre-images, the capture policy, the objects and state
# checkpointers, the checkpoint.note service and the exported gptr_preimage() generic
# (P16, layer L4).
#
# Adapted from the verified G7 prototypes (dev/research/G7-checkpoint-undo-rewind.md, section 5.2
# p1/ckpt_obj.R and section 5.5 p4/ckpt_state.R; verification log items 1-4 and 12). The rules of
# G7 section 1 item 2 (architecture section 6.4 rule R6) hold throughout:
#   * a pre-image is a BINDING in a private environment (`store$slots`), never a list element;
#   * it is released with rm(), which lowers the reference count again (the collector never does);
#   * list and S4 images are defused before they are dropped: taken out of the store, then
#     overwritten element by element (G7 variant v5; the in-store variant v1 does not release);
#   * user objects are addressed by name and passed straight from get() into assign() or into a
#     leaf (rlang::obj_address(), serialize_leaf()), never kept in a frame that outlives the call.
# While a pre-image is held, a value-semantics object cannot be modified in place without R
# duplicating it, so "address changed" is an exact change detector (G7 section 2.3).
# Changes from the prototype: keys come from id_new() (RNG-free and unique across R processes,
# so a spilled image is found again after a restart); the index records fragment, role, turn
# and an expected address; data frames are unclassed before defusing (their `[[` replacement
# method checks row counts); spills go through serialize_leaf(xdr = FALSE) and write_atomic()
# (rule R7, contract 11.14); fragments use "" and -1 for missing values because json_encode()
# would write NA numbers as the string "NA"; the unshared-bytes walk iterates a list with
# `for (el in x)` instead of indexing up to the dispatched length(x) (POSIXlt, vctrs records).

# ---- small shared helpers (also used by ckpt-files.R and ckpt-rewind.R) ------------------------

#' A new fragment id ("k" + 10 hex, RNG-free)
#' @noRd
ckpt_frag_id = function() {
  paste0("k", id_new("", 10L))
}

#' A character vector from an R or JSON-decoded value (NULL and list() give character())
#' @noRd
ckpt_chr = function(x) {
  if (is.null(x) || !length(x)) return(character())
  as.character(unlist(x, use.names = FALSE))
}

#' The first element of x as a string, or `default` when absent, NA or empty
#' @noRd
ckpt_scalar = function(x, default = "") {
  x = ckpt_chr(x)
  if (length(x) && !is.na(x[1L]) && nzchar(x[1L])) x[1L] else default
}

#' A number from an R or JSON-decoded value; NULL, NA and negative sentinels give NA
#' @noRd
ckpt_num = function(x) {
  if (is.null(x) || !length(x)) return(NA_real_)
  v = suppressWarnings(as.numeric(unlist(x, use.names = FALSE))[1L])
  if (is.na(v) || v < 0) NA_real_ else v
}

#' A number for a fragment: NA becomes -1 (JSON-safe sentinel)
#' @noRd
ckpt_json_num = function(x) {
  v = suppressWarnings(as.numeric(x)[1L])
  if (!length(v) || is.na(v)) -1 else v
}

#' Human-readable sizes (vectorised; NA and negative sizes read "unknown size")
#' @noRd
ckpt_fmt_bytes = function(b) {
  b = suppressWarnings(as.numeric(b))
  out = ifelse(b >= 1e9, sprintf("%.1f GB", b / 1e9),
               ifelse(b >= 1e6, sprintf("%.1f MB", b / 1e6),
                      ifelse(b >= 1e3, sprintf("%.0f KB", b / 1e3), sprintf("%.0f B", b))))
  out[is.na(b) | b < 0] = "unknown size"
  out
}

#' An empty item table (the results of undo, redo and previews)
#' @noRd
ckpt_items = function() {
  data.frame(item = character(), ok = logical(), action = character(), stringsAsFactors = FALSE)
}

#' Add one row to an item table (`ok`: TRUE restored, FALSE not restored, NA reported only)
#' @noRd
ckpt_item = function(out, item, ok, action) {
  rbind(out, data.frame(item = item, ok = as.logical(ok), action = action,
                        stringsAsFactors = FALSE))
}

#' Report lines of an item table: "<item>: <action>"
#' @noRd
ckpt_lines = function(items) {
  if (!nrow(items)) return(character())
  paste0(items$item, ": ", items$action)
}

# ---- gptr_preimage() (contract 6.6, IC-01) ------------------------------------------------------

#' Tell the object checkpointer how to capture an object
#'
#' `gptr_preimage()` is the S3 generic the object checkpointer calls for every binding of the
#' workspace before a tool call that runs R code. It decides how the value the binding holds now
#' is kept, so that [gptr_rewind()] can put it back. Methods are leaf functions: they may read
#' `x` but must never store it anywhere.
#'
#' The default method keeps value-semantics objects by reference (`"ref"`: nothing is copied
#' unless the agent edits the object in place) and reports environments, R6 and RefClass objects
#' and external pointers as not restorable (`"none"`). The `data.table` method returns a deep copy
#' made with `data.table::copy()` (`"copy"`) when the agent's code is predicted to modify the
#' table by reference (`:=`, `set*()`) and the table fits the budget. Packages add methods for
#' their own classes with a delayed registration, `S3method(gptr::gptr_preimage, myclass)`, so gptr
#' can stay in Suggests; an R6 class can, for example, return `x$clone(deep = TRUE)` as `"copy"`.
#' This generic is experimental (contract IC-01).
#'
#' @param x The object bound to `name`.
#' @param name The binding name (a string).
#' @param ctx A list: `predicted`, what the agent's code is predicted to do to `name` (`"assign"`,
#'   `"modify"`, `"byref"`, `"remove"` or `"none"`); `bytes`, the size of `x` in bytes (`NA` when
#'   unknown); `budget`, the largest copy allowed, in bytes. When `ctx$dry` is `TRUE` the
#'   checkpointer only asks whether a capture is possible and a method must not copy.
#' @param ... Unused; for methods.
#' @return A list with `mode` (`"ref"`, `"copy"` or `"none"`), `reason` (a string explaining
#'   `"none"`, else `NULL`) and `copy` (the deep copy for `"copy"`, else `NULL`).
#' @family checkpoints
#' @export
#' @examples
#' gptr_preimage(1:3, "x", list(predicted = "assign", bytes = 64, budget = 1e9))$mode
#' gptr_preimage(new.env(), "cfg", list(predicted = "modify", bytes = NA, budget = 1e9))$reason
gptr_preimage = function(x, name, ctx, ...) {
  UseMethod("gptr_preimage")
}

#' @rdname gptr_preimage
#' @export
gptr_preimage.default = function(x, name, ctx, ...) {
  if (ckpt_is_reference(x)) {
    return(list(mode = "none", reason = "reference object (environment, R6 or external pointer)",
                copy = NULL))
  }
  list(mode = "ref", reason = NULL, copy = NULL)
}

#' @rdname gptr_preimage
#' @export
gptr_preimage.data.table = function(x, name, ctx, ...) {
  if (!identical(ctx$predicted, "byref")) return(list(mode = "ref", reason = NULL, copy = NULL))
  if (!ckpt_within_budget(ctx$bytes, ctx$budget)) {
    return(list(mode = "none", reason = "data.table modified by reference, over the undo budget",
                copy = NULL))
  }
  if (isTRUE(ctx$dry)) return(list(mode = "copy", reason = NULL, copy = NULL))
  if (!requireNamespace("data.table", quietly = TRUE)) {
    return(list(mode = "none", reason = "the data.table package is needed to copy it",
                copy = NULL))
  }
  list(mode = "copy", reason = NULL, copy = data.table::copy(x))
}

#' Leaf: does x have reference semantics (environment, R6, RefClass, external pointer)?
#' @noRd
ckpt_is_reference = function(x) {
  typeof(x) %in% c("environment", "externalptr", "weakref", "bytecode") ||
    (isS4(x) && is.environment(x)) || inherits(x, "R6")
}

#' Is a size within a byte budget (unknown sizes are not)?
#' @noRd
ckpt_within_budget = function(bytes, budget) {
  b = suppressWarnings(as.numeric(bytes)[1L])
  m = suppressWarnings(as.numeric(budget)[1L])
  length(b) == 1L && !is.na(b) && length(m) == 1L && !is.na(m) && b <= m
}

# ---- the pre-image store (G7 p1/ckpt_obj.R) ---------------------------------------------------

#' A new pre-image store: a private environment of bindings plus an index
#'
#' `dir` is the spill directory (`<workspace root>/checkpoints/objects/<session id>`), or NULL
#' when images may not go to disk.
#' @noRd
ckpt_obj_store = function(dir = NULL) {
  s = new.env(parent = emptyenv())
  s$slots = new.env(parent = emptyenv())
  s$index = ckpt_index_empty()
  s$dir = dir
  s$seq = 0L
  s
}

#' The empty image index: one row per held image (memory or disk)
#' @noRd
ckpt_index_empty = function() {
  data.frame(key = character(), frag = character(), name = character(), role = character(),
             where = character(), file = character(), bytes = numeric(), turn = integer(),
             expect = character(), seq = integer(), stringsAsFactors = FALSE)
}

#' Add one row to the image index (`role`: "pre" undo image, "redo" redo image, "mark" a
#' restored removal, so that a redo can remove the binding again)
#' @noRd
ckpt_index_add = function(store, key, frag, name, role, where = "memory", file = "",
                          bytes = NA_real_, turn = NA_integer_, expect = "") {
  store$seq = store$seq + 1L
  row = data.frame(key = key, frag = frag, name = name, role = role, where = where,
                   file = as.character(file), bytes = as.numeric(bytes),
                   turn = as.integer(turn), expect = as.character(expect), seq = store$seq,
                   stringsAsFactors = FALSE)
  store$index = rbind(store$index, row)
  invisible(key)
}

#' The newest index key for (fragment, name, role), or NA
#' @noRd
ckpt_index_find = function(store, frag, name, role) {
  idx = store$index
  i = which(idx$frag == frag & idx$name == name & idx$role == role)
  if (!length(i)) return(NA_character_)
  idx$key[i[length(i)]]
}

#' Remove index rows by key
#' @noRd
ckpt_index_remove = function(store, keys) {
  store$index = store$index[!store$index$key %in% keys, , drop = FALSE]
  invisible(keys)
}

#' Address of a binding (NA when absent); a leaf that never keeps the value
#' @noRd
ckpt_addr = function(envir, name) {
  if (!exists(name, envir = envir, inherits = FALSE)) return(NA_character_)
  rlang::obj_address(get(name, envir = envir, inherits = FALSE))
}

#' Capture bindings by reference into the store; no copy is made
#' @return df(name, key, address): the pending captures.
#' @noRd
ckpt_capture = function(store, envir, names) {
  n = length(names)
  keys = character(n)
  addr = character(n)
  i = 1L
  while (i <= n) {
    k = paste0("p", id_new("", 12L))
    assign(k, get(names[i], envir = envir, inherits = FALSE), envir = store$slots)
    keys[i] = k
    addr[i] = rlang::obj_address(get(k, envir = store$slots, inherits = FALSE))
    i = i + 1L
  }
  data.frame(name = names, key = keys, address = addr, stringsAsFactors = FALSE)
}

#' Keep a value a gptr_preimage() method already copied; returns its key
#' @noRd
ckpt_capture_value = function(store, value) {
  k = paste0("c", id_new("", 12L))
  assign(k, value, envir = store$slots)
  k
}

#' The file of a disk image
#' @noRd
ckpt_disk_file = function(dir, key) {
  file.path(dir, paste0(key, ".rdsx"))
}

#' Write the value bound to `name` in `envir` as a disk image (contract 11.14:
#' serialize_leaf() with `xdr = FALSE`, rule R7) through an atomic write
#' @noRd
ckpt_write_image = function(file, envir, name) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  write_atomic(file, serialize_leaf(get(name, envir = envir, inherits = FALSE), xdr = FALSE))
  invisible(file)
}

#' Read a disk image back
#' @noRd
ckpt_read_image = function(file) {
  unserialize(readBin(file, "raw", file.size(file)))
}

#' Eager disk image of a binding (a predicted in-place edit of a large object, G7 section 3.4)
#' @return `list(key, file)`.
#' @noRd
ckpt_capture_disk = function(store, envir, name) {
  k = paste0("d", id_new("", 12L))
  f = ckpt_disk_file(store$dir, k)
  ckpt_write_image(f, envir, name)
  list(key = k, file = f)
}

#' Settle by-reference captures: release unchanged bindings with rm(), index the rest
#' @return df(name, key, status ("unchanged", "changed", "removed"), pre_address, post_address).
#' @noRd
ckpt_settle = function(store, envir, pending, frag = "", turn = NA_integer_) {
  n = nrow(pending)
  status = character(n)
  post = rep("", n)
  i = 1L
  while (i <= n) {
    nm = pending$name[i]
    now = ckpt_addr(envir, nm)
    post[i] = if (is.na(now)) "" else now
    status[i] = if (is.na(now)) {
      "removed"
    } else if (identical(now, pending$address[i])) {
      "unchanged"
    } else {
      "changed"
    }
    if (status[i] == "unchanged") {
      rm(list = pending$key[i], envir = store$slots)
    } else {
      ckpt_index_add(store, pending$key[i], frag, nm, "pre", turn = turn,
                     expect = pending$address[i])
    }
    i = i + 1L
  }
  data.frame(name = pending$name, key = pending$key, status = status,
             pre_address = pending$address, post_address = post, stringsAsFactors = FALSE)
}

#' Restore `name` from image `key` (memory or disk); the displaced current value becomes a redo
#' image held by reference (no copy). `expect` is the address recorded after the call (NA for a
#' removal): a binding changed since is refused unless `force = TRUE` (the 3-way rule).
#' @return `list(ok, reason, redo, address)`.
#' @noRd
ckpt_restore = function(store, envir, name, key, expect = NULL, force = FALSE, frag = "",
                        turn = NA_integer_) {
  i = match(key, store$index$key)
  if (is.na(i)) {
    return(list(ok = FALSE, reason = "no pre-image", redo = NA_character_, address = NA_character_))
  }
  now = ckpt_addr(envir, name)
  if (!force && !is.null(expect) && !identical(now, expect)) {
    return(list(ok = FALSE, reason = "conflict: changed after the checkpoint (kept current)",
                redo = NA_character_, address = now))
  }
  disk = !identical(store$index$where[i], "memory")
  if (disk && !file.exists(store$index$file[i])) {
    return(list(ok = FALSE, reason = "the disk image is missing", redo = NA_character_,
                address = now))
  }
  redo = NA_character_
  if (!is.na(now)) {
    redo = paste0("r", id_new("", 12L))
    assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
  }
  if (disk) {
    f = store$index$file[i]
    assign(name, ckpt_read_image(f), envir = envir)
    unlink(f)
  } else {
    assign(name, get(key, envir = store$slots, inherits = FALSE), envir = envir)
    rm(list = key, envir = store$slots)
  }
  ckpt_index_remove(store, key)
  addr = ckpt_addr(envir, name)
  if (!is.na(redo)) {
    ckpt_index_add(store, redo, frag, name, "redo", turn = turn, expect = addr,
                   bytes = ckpt_unshared_bytes(store, redo, envir, name))
  }
  list(ok = TRUE, reason = NULL, redo = redo, address = addr)
}

#' Undo of a creation: unbind `name`, keep its value as a redo image
#' @noRd
ckpt_uncreate = function(store, envir, name, frag = "", turn = NA_integer_) {
  redo = paste0("r", id_new("", 12L))
  assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
  rm(list = name, envir = envir)
  ckpt_index_add(store, redo, frag, name, "redo", turn = turn, expect = "",
                 bytes = ckpt_unshared_bytes(store, redo, envir, name))
  redo
}

#' Kind of container for defusing and for the unshared-bytes walk: "list", "s4" or "leaf"
#' @noRd
ckpt_leaf_children = function(x) {
  if (is.environment(x)) return("leaf")
  if (isS4(x)) return("s4")
  if (is.list(x)) return("list")
  "leaf"
}

#' Take an image out of the store, then release its children (G7 defuse variant v5)
#'
#' When R frees a list by garbage collection it does not decrement its elements' reference
#' counts, so elements still shared with the user's current object would stay sticky (G7 c12).
#' Overwriting each element of the taken-out image (its only reference is the local binding)
#' decrements them. Data frames are unclassed first: the data.frame `[[` replacement method
#' checks row counts. A failure while overwriting only leaves the image to the collector.
#' @noRd
ckpt_defuse = function(store, key) {
  v = get(key, envir = store$slots, inherits = FALSE)
  rm(list = key, envir = store$slots)
  k = ckpt_leaf_children(v)
  if (k == "list") {
    oldClass(v) = NULL
    n = length(v)
    j = 1L
    while (j <= n) {
      v[[j]] = FALSE
      j = j + 1L
    }
  } else if (k == "s4") {
    for (sl in methods::slotNames(class(v))) {
      tryCatch({
        attr(v, sl) = FALSE
      }, error = function(e) NULL)
    }
  }
  invisible(key)
}

#' Spill a held memory image to disk and release it from memory (defused); NULL when the image
#' cannot be written
#' @noRd
ckpt_spill = function(store, key) {
  if (is.null(store$dir)) return(invisible(NULL))
  i = match(key, store$index$key)
  if (is.na(i) || !identical(store$index$where[i], "memory")) return(invisible(NULL))
  if (!exists(key, envir = store$slots, inherits = FALSE)) return(invisible(NULL))
  f = ckpt_disk_file(store$dir, key)
  ok = tryCatch({
    ckpt_write_image(f, store$slots, key)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) {
    unlink(f)
    return(invisible(NULL))
  }
  ckpt_defuse(store, key)
  store$index$where[i] = "disk"
  store$index$file[i] = f
  invisible(f)
}

#' Drop images (budget eviction or session end): defuse memory images, delete disk images
#' @noRd
ckpt_drop = function(store, keys) {
  mem = intersect(keys, ls(store$slots, all.names = TRUE))
  for (k in mem) ckpt_defuse(store, k)
  files = store$index$file[store$index$key %in% keys & store$index$where == "disk"]
  files = files[nzchar(files)]
  if (length(files)) unlink(files)
  ckpt_index_remove(store, keys)
  invisible(keys)
}

#' Release every slot no index row owns (captures of a call whose after() never ran)
#' @noRd
ckpt_obj_sweep = function(store) {
  orphan = setdiff(ls(store$slots, all.names = TRUE), store$index$key)
  for (k in orphan) ckpt_defuse(store, k)
  invisible(orphan)
}

#' Collect the addresses of x and its children down to depth d (closure-free recursion)
#'
#' Lists are walked with `for (el in x)`, which visits the list's own components without
#' dispatch; `length()` dispatches, and a POSIXlt or a vctrs record reports its record count, so
#' indexing up to `length(x)` would run past the components.
#' @noRd
ckpt_addr_collect = function(x, d, seen) {
  assign(rlang::obj_address(x), TRUE, envir = seen)
  if (d <= 0L) return(invisible())
  k = ckpt_leaf_children(x)
  if (k == "list") {
    for (el in x) ckpt_addr_collect(el, d - 1L, seen)
  }
  if (k == "s4") {
    for (sl in methods::slotNames(class(x))) {
      ckpt_addr_collect(attr(x, sl, exact = TRUE), d - 1L, seen)
    }
  }
  invisible()
}

#' Add the bytes of the parts of x that are not in `seen` to `acc$bytes` (lists walked as in
#' ckpt_addr_collect())
#' @noRd
ckpt_unshared_walk = function(x, d, seen, acc) {
  if (exists(rlang::obj_address(x), envir = seen, inherits = FALSE)) return(invisible())
  k = ckpt_leaf_children(x)
  if (d <= 0L || k == "leaf") {
    acc$bytes = acc$bytes + as.numeric(utils::object.size(x))
    return(invisible())
  }
  acc$bytes = acc$bytes + 64
  if (k == "list") {
    for (el in x) ckpt_unshared_walk(el, d - 1L, seen, acc)
  }
  if (k == "s4") {
    for (sl in methods::slotNames(class(x))) {
      ckpt_unshared_walk(attr(x, sl, exact = TRUE), d - 1L, seen, acc)
    }
  }
  invisible()
}

#' Bytes of image `key` not shared with the current value of `name` (G7 estimator, depth 4)
#' @noRd
ckpt_unshared_bytes = function(store, key, envir, name, depth = 4L) {
  seen = new.env(parent = emptyenv())
  acc = new.env(parent = emptyenv())
  acc$bytes = 0
  if (exists(name, envir = envir, inherits = FALSE)) {
    ckpt_addr_collect(get(name, envir = envir, inherits = FALSE), depth, seen)
  }
  ckpt_unshared_walk(get(key, envir = store$slots, inherits = FALSE), depth, seen, acc)
  acc$bytes
}

# ---- per-session checkpoint state ------------------------------------------------------------

#' A new per-session checkpoint state
#'
#' `obj`: the pre-image store (spill directory `<root>/checkpoints/objects/<session id>`);
#' `snap`: the last workspace snapshot (names, addresses, sizes; reused so object sizes are
#' cached by address); `files`: the file tracker (created by the files checkpointer on first
#' use); `state_img`: option values and working directories of state fragments, by fragment id
#' (memory only); `notes`: model-facing notices by tool-call id; `rewind_note`, `rewind_since`:
#' the lines the rewind context block sends after a partial rewind; `gc_done`: one blob
#' collection per session. A finalizer defuses every in-memory image when the state is collected
#' (G7 c06b).
#' @noRd
ckpt_ck_new = function(sid, spill_dir = NULL) {
  ck = new.env(parent = emptyenv())
  ck$sid = sid
  ck$obj = ckpt_obj_store(spill_dir)
  ck$snap = NULL
  ck$files = NULL
  ck$state_img = new.env(parent = emptyenv())
  ck$notes = new.env(parent = emptyenv())
  ck$rewind_note = NULL
  ck$rewind_since = ""
  ck$gc_done = FALSE
  reg.finalizer(ck, ckpt_ck_finalize, onexit = FALSE)
  ck
}

#' Release every in-memory image of a checkpoint state (finalizer and session shutdown)
#' @noRd
ckpt_ck_finalize = function(ck) {
  store = ck$obj
  if (is.environment(store) && is.environment(store$slots)) {
    for (k in ls(store$slots, all.names = TRUE)) ckpt_defuse(store, k)
    store$index = store$index[store$index$where == "disk", , drop = FALSE]
  }
  invisible(NULL)
}
```

Regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: `NAMESPACE` gains `export(gptr_preimage)`, `S3method(gptr_preimage,default)` and `S3method(gptr_preimage,data.table)`; `man/gptr_preimage.Rd` is written.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects|copy-ckpt")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 118 ]` (55 in `test-ckpt-objects.R`, 63 in `test-copy-ckpt.R`: 1 + 2 x 24 matrix rows, 2 x 7 serialize rows). Without `capabilities("profmem")`: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 56 ]`. Without data.table installed: one more SKIP and 6 fewer PASS.

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-objects.R tests/testthat/test-ckpt-objects.R tests/testthat/test-copy-ckpt.R NAMESPACE man/gptr_preimage.Rd
git commit -m "feat(ckpt): add copy-safe object pre-images and gptr_preimage()"
```

### Task 2: Capture policy, the objects checkpointer and `checkpoint.note`

**Files:**
- Modify: `R/ckpt-objects.R` (append)
- Test: `tests/testthat/test-ckpt-objects.R` (append)

**Interfaces:**
- Consumes: Task 1 (the store, the per-session state `ckpt_ck_new()`); P01 `gptr_opt(name)`, `setting_get(key, session = NULL, default = NULL)`, `workspace_root(create = TRUE)`, `workspace_dir(path = getwd())`, `gptr_has_human()`; P06 `run_current()`, `run_eval_env(run)`; P09 `env_snapshot(envir, previous = NULL)` (`name`, `kind`, `address`, `class`, `bytes`, `shape`, `fp`; `bytes` is `NA` for environments, functions, external pointers and compact sequences; promises and active bindings are never forced); P11 `code_targets(code)` (IC-31); the generic `gptr_preimage()` of Task 1.
- Produces (used by Tasks 6-8): `ckpt_store_root()` = `file.path(workspace_root(create = TRUE), "checkpoints")`; `ckpt_spill_allowed()`; `ckpt_limits()`; `ckpt_predict(code)` -> `list(assign, modify, byref, remove, super, files, unknown, process)` (04 §7.16); `ckpt_predicted(names, tg)`; `ckpt_capture_how(bytes, predicted, mode, spill_ok, lim)`; `ckpt_value_snapshot(envir, previous = NULL)`; `ckpt_snapshot(ck, envir)`; `ckpt_preimage_modes(store, envir, snap, pred, lim, dry = FALSE)`; the objects checkpointer `ckpt_objects_before(ck, call, envir, turn = 1L)` -> token, `ckpt_objects_after(ck, call, envir, token)` -> `list(id, turn, objects = list(<row>))` or `NULL`, `ckpt_objects_undo(ck, fragment, envir, force = FALSE, dry = FALSE)` and `ckpt_objects_redo(...)` -> item tables, `ckpt_objects_describe(fragment)`, `ckpt_objects_notes(fragment)`, `ckpt_objects_budget(ck, turn)`; the service function `ckpt_note(call, run = NULL)` (registered as `checkpoint.note` in Task 6).

An objects fragment row is `list(name, status ("changed", "removed", "created"), how ("ref", "copy", "disk", "none", "skip", "created"), class, bytes, pre_address, post_address, restorable, reason, image, where, held_bytes)`: names, classes, sizes and addresses only, never a value (04 §4.6). The capture plan is G7 section 3.4 step 3: every value binding up to `gptr.undo_capture_max` by reference; a predicted `assign`/`remove`/`super` target up to `gptr.undo_max_bytes` by reference; a predicted in-place (`modify`) edit of a larger object up to `gptr.undo_spill_max` as an eager disk image when images may go to disk; a predicted by-reference data.table edit as the `gptr_preimage()` copy; the rest is not undoable and is reported (the `note:` line of G7 section 3.9 in the tool result, the "cannot be undone" note in the permission detail view). After the call the settle step releases unchanged captures with `rm()`; an unchanged address with a changed fingerprint means a by-reference modification (not restorable). The turn-end budget drops images older than `gptr.undo_turns` turns, then spills the largest image while the held bytes exceed `gptr.undo_max_bytes`, or drops it when it cannot be spilled (G7 section 3.4 step 6).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ckpt-objects.R`:

```r
rows_by_name = function(frag) {
  rows = frag$objects
  stats::setNames(rows, vapply(rows, function(r) r$name, ""))
}

test_that("ckpt_predict() reduces code_targets() to the checkpointers' fields (IC-31)", {
  tg = ckpt_predict("x[1] = 0; y = f(y); write.csv(d, 'out.csv'); rm(z)")
  expect_named(tg, c("assign", "modify", "byref", "remove", "super", "files", "unknown",
                     "process"))
  expect_true("x" %in% tg$modify)
  expect_true("y" %in% tg$assign)
  expect_true("z" %in% tg$remove)
  expect_true("out.csv" %in% tg$files)
  expect_identical(ckpt_predict(NA_character_)$assign, character())
  expect_identical(ckpt_predict("not valid (")$unknown, "the code could not be analysed")
  expect_identical(ckpt_predicted(c("x", "y", "z", "w"), tg),
                   c("modify", "assign", "remove", "none"))
})

test_that("the capture plan follows G7's budget rules", {
  lim = list(capture_max = 100, max_bytes = 1000, spill_max = 5000)
  how = ckpt_capture_how(
    bytes = c(10, 500, 500, 500, 2000, 9000, NA, 10, 10),
    predicted = c("none", "assign", "modify", "none", "modify", "modify", "none", "byref",
                  "assign"),
    mode = c("ref", "ref", "ref", "ref", "ref", "ref", "ref", "copy", "none"),
    spill_ok = TRUE, lim = lim)
  expect_identical(how, c("ref", "ref", "disk", "skip", "disk", "skip", "ref", "copy", "none"))
  expect_identical(ckpt_capture_how(500, "modify", "ref", spill_ok = FALSE, lim = lim), "skip")
})

test_that("before/after record changed, removed and created bindings; undo and redo swap them", {
  ck = ckpt_ck_new("s0000000001")
  e = new.env()
  e$x = c(1, 2, 3)
  e$keep = "same"
  e$gone = 1
  call = list(id = "c1", name = "r", input = list(code = "x[2] = 0; rm(gone); new = 1"))
  tok = ckpt_objects_before(ck, call, e, turn = 1L)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_setequal(names(rows), c("x", "gone", "new"))
  expect_identical(rows$x$status, "changed")
  expect_identical(rows$gone$status, "removed")
  expect_identical(rows$new$status, "created")
  expect_true(all(vapply(rows, function(r) isTRUE(r$restorable), TRUE)))
  expect_identical(sort(ck$obj$index$name), c("gone", "x"))
  expect_length(ls(ck$obj$slots), 2L)
  expect_silent(json_encode(frag))
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(all(u$ok))
  expect_identical(e$x, c(1, 2, 3))
  expect_identical(e$gone, 1)
  expect_false(exists("new", envir = e, inherits = FALSE))
  r = ckpt_objects_redo(ck, frag, e)
  expect_true(all(r$ok))
  expect_identical(e$x, c(1, 0, 3))
  expect_false(exists("gone", envir = e, inherits = FALSE))
  expect_identical(e$new, 1)
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(all(u$ok))
  expect_identical(e$x, c(1, 2, 3))
})

test_that("undo keeps a binding changed after the turn (3-way) unless forced", {
  ck = ckpt_ck_new("s0000000002")
  e = new.env()
  e$x = c(1, 2, 3)
  call = list(id = "c1", name = "r", input = list(code = "x = x * 2"))
  tok = ckpt_objects_before(ck, call, e)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  e$x = "user"
  u = ckpt_objects_undo(ck, frag, e)
  expect_false(u$ok)
  expect_match(u$action, "conflict")
  expect_identical(e$x, "user")
  plan = ckpt_objects_undo(ck, frag, e, dry = TRUE)
  expect_false(plan$ok)
  u = ckpt_objects_undo(ck, frag, e, force = TRUE)
  expect_true(u$ok)
  expect_identical(e$x, c(1, 2, 3))
})

test_that("reference objects and objects over the budget are reported with a model notice", {
  local_gptr_options(undo_capture_max = 100, undo_max_bytes = 200, undo_spill_max = 150)
  ck = ckpt_ck_new("s0000000003")
  e = new.env()
  e$cfg = new.env()
  e$cfg$alpha = 1
  e$big = as.numeric(1:1000)
  call = list(id = "c2", name = "r", input = list(code = "cfg$alpha = 2; big[1] = 0"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how[match(c("big", "cfg"), tok$snap$name)], c("skip", "none"))
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_false(rows$cfg$restorable)
  expect_match(rows$cfg$reason, "reference object")
  expect_false(rows$big$restorable)
  expect_match(rows$big$reason, "over the undo budget")
  notes = ckpt_objects_notes(frag)
  expect_length(notes, 2L)
  expect_match(notes, "^note: big \\(8 KB\\) was (modified|overwritten) without an undo copy",
               all = FALSE)
  u = ckpt_objects_undo(ck, frag, e)
  expect_false(any(u$ok))
  expect_true(all(grepl("^not restored", u$action)))
  expect_identical(e$cfg$alpha, 2)
})

test_that("a predicted data.table set() gets a deep copy and is restorable", {
  skip_if_not_installed("data.table")
  ck = ckpt_ck_new("s0000000004")
  e = new.env()
  e$dt = data.table::data.table(a = 1:3)
  call = list(id = "c3", name = "r",
              input = list(code = "data.table::set(dt, j = 'b', value = dt$a * 2L)"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how[tok$snap$name == "dt"], "copy")
  agent_eval(call$input$code, e)
  expect_identical(names(e$dt), c("a", "b"))
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_identical(rows$dt$how, "copy")
  expect_true(rows$dt$restorable)
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(u$ok)
  expect_identical(names(e$dt), "a")
})

test_that("promises are never forced; a predicted rebinding of one is reported", {
  ck = ckpt_ck_new("s0000000005")
  e = new.env()
  delayedAssign("lazy", stop("forced"), assign.env = e)
  e$x = 1
  call = list(id = "c4", name = "r", input = list(code = "lazy = 2; x = 3"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$others, "lazy")
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_false(rows$lazy$restorable)
  expect_match(rows$lazy$reason, "promise")
  expect_true(rows$x$restorable)
})

test_that("the turn-end budget spills the largest image and drops images older than undo_turns", {
  dir = withr::local_tempdir()
  local_gptr_options(undo_max_bytes = 1000, undo_spill_max = 1e6, undo_turns = 2L)
  ck = ckpt_ck_new("s0000000006", dir)
  st = ck$obj
  e = new.env()
  e$a = as.numeric(1:500)
  e$b = as.numeric(1:10)
  p = ckpt_capture(st, e, c("a", "b"))
  agent_eval("a = a + 1; b = b + 1", e)
  ckpt_settle(st, e, p, frag = "f1", turn = 1L)
  st$index$bytes = c(4048, 128)
  ckpt_objects_budget(ck, turn = 1L)
  expect_identical(st$index$where[st$index$name == "a"], "disk")
  expect_identical(st$index$where[st$index$name == "b"], "memory")
  expect_length(list.files(dir), 1L)
  ckpt_objects_budget(ck, turn = 3L)
  expect_identical(nrow(st$index), 0L)
  expect_length(list.files(dir), 0L)
  expect_length(ls(st$slots), 0L)
})

test_that("an image that cannot be spilled is dropped instead", {
  local_gptr_options(undo_max_bytes = 10, undo_spill_max = 5)
  ck = ckpt_ck_new("s0000000007", withr::local_tempdir())
  e = new.env()
  e$a = as.numeric(1:50)
  p = ckpt_capture(ck$obj, e, "a")
  agent_eval("a = 0", e)
  ckpt_settle(ck$obj, e, p, frag = "f1", turn = 1L)
  ck$obj$index$bytes = 400
  ckpt_objects_budget(ck, turn = 1L)
  expect_identical(nrow(ck$obj$index), 0L)
  expect_length(ls(ck$obj$slots), 0L)
})

test_that("an image spilled at a turn end is found again by a new R process (force)", {
  dir = withr::local_tempdir()
  local_gptr_options(undo_max_bytes = 10)
  ck = ckpt_ck_new("s0000000009", dir)
  e = new.env()
  e$x = as.numeric(1:50)
  call = list(id = "c1", name = "r", input = list(code = "x = x * 2"))
  tok = ckpt_objects_before(ck, call, e)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  ckpt_objects_budget(ck, turn = 1L)
  expect_identical(ck$obj$index$where, "disk")
  ck2 = ckpt_ck_new("s0000000009", dir)
  u = ckpt_objects_undo(ck2, frag, e)
  expect_false(u$ok)
  expect_match(u$action, "earlier R process")
  u = ckpt_objects_undo(ck2, frag, e, force = TRUE)
  expect_true(u$ok)
  expect_identical(e$x, as.numeric(1:50))
})

test_that("checkpoint.note names what cannot be undone", {
  local_gptr_options(undo_capture_max = 100, undo_max_bytes = 200, undo_spill_max = 150)
  e = new.env()
  e$cfg = new.env()
  e$big = as.numeric(1:1000)
  e$small = 1
  run = list(envir = e)
  local_mocked_bindings(run_eval_env = function(run) run$envir)
  expect_null(ckpt_note(list(input = list(code = "small = 2")), run))
  expect_null(ckpt_note(list(input = list(path = "a.R")), run))
  note = ckpt_note(list(input = list(code = "cfg$a = 1; big[1] = 0")), run)
  expect_match(note, "^cannot be undone: ")
  expect_match(note, "big (8 KB, over the undo budget)", fixed = TRUE)
  expect_match(note, "cfg (reference object", fixed = TRUE)
  expect_null(ckpt_note(list(input = list(code = "big[1] = 0")), NULL))
  local_gptr_options(checkpoint = "off")
  expect_match(ckpt_note(list(input = list(code = "small = 2")), run), "checkpoints are off")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects")'`

Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 55 ]`; the eleven new tests error with `could not find function "ckpt_predict"`, `"ckpt_capture_how"`, `"ckpt_objects_before"`, `"ckpt_objects_budget"` or `"ckpt_note"`.

- [ ] **Step 3: Write the implementation**

Append to `R/ckpt-objects.R`:

```r
# ---- the store root and the spill policy -----------------------------------------------------

#' The checkpoint store root, `<workspace root>/checkpoints` (contract 11.14): `.gptr/` when
#' the project has one, else `tempdir()/gptr`; never `.git`, never `R_user_dir()`
#' @noRd
ckpt_store_root = function() {
  file.path(workspace_root(create = TRUE), "checkpoints")
}

#' May object images go to disk? With a consented workspace, or when a human is present (then
#' under tempdir()); never in a non-interactive run without `.gptr/` (G7 section 4.5)
#' @noRd
ckpt_spill_allowed = function() {
  !is.null(workspace_dir()) || isTRUE(gptr_has_human())
}

# ---- capture policy (G7 section 3.4) -----------------------------------------------------------

#' The checkpoint budgets (contract 3.1: options gptr.undo_* and gptr.checkpoint_*)
#' @noRd
ckpt_limits = function() {
  list(
    capture_max = as.numeric(gptr_opt("undo_capture_max")),
    max_bytes = as.numeric(gptr_opt("undo_max_bytes")),
    spill_max = as.numeric(gptr_opt("undo_spill_max")),
    turns = as.integer(gptr_opt("undo_turns")),
    disk_bytes = as.numeric(gptr_opt("checkpoint_disk_bytes")),
    days = as.numeric(gptr_opt("checkpoint_days")),
    file_turns = as.integer(gptr_opt("checkpoint_turns")),
    track_file_max = as.numeric(gptr_opt("checkpoint_track_file_max")),
    track_total = as.numeric(gptr_opt("checkpoint_track_total")),
    file_capture_max = as.numeric(gptr_opt("checkpoint_capture_max")),
    scan_budget = as.numeric(gptr_opt("checkpoint_scan_budget")),
    rng = isTRUE(gptr_opt("checkpoint_rng")),
    close_devices = isTRUE(gptr_opt("checkpoint_close_devices"))
  )
}

#' Targets of R code for the checkpointers: P11's code_targets() reduced (contract 7.16, IC-31)
#' @return `list(assign, modify, byref, remove, super, files, unknown, process)`, chr each.
#' @noRd
ckpt_predict = function(code) {
  out = list(assign = character(), modify = character(), byref = character(),
             remove = character(), super = character(), files = character(),
             unknown = character(), process = character())
  if (!is.character(code) || length(code) != 1L || is.na(code)) return(out)
  tg = tryCatch(code_targets(code), error = function(e) NULL)
  if (!is.list(tg) || isTRUE(tg$parse_error)) {
    out$unknown = "the code could not be analysed"
    return(out)
  }
  for (f in names(out)) out[[f]] = unique(ckpt_chr(tg[[f]]))
  out
}

#' What the code is predicted to do to each name: byref > modify > remove > assign > none
#' @noRd
ckpt_predicted = function(names, tg) {
  out = rep("none", length(names))
  out[names %in% c(tg$assign, tg$super)] = "assign"
  out[names %in% tg$remove] = "remove"
  out[names %in% tg$modify] = "modify"
  out[names %in% tg$byref] = "byref"
  out
}

#' The capture plan of each binding (G7 section 3.4 step 3): "ref", "copy", "disk", "none" (the
#' gptr_preimage() method refused) or "skip" (over the budget; reported if it changes).
#' Unknown sizes (functions, compact sequences) count as 0 bytes.
#' @noRd
ckpt_capture_how = function(bytes, predicted, mode, spill_ok, lim) {
  b = suppressWarnings(as.numeric(bytes))
  b[is.na(b)] = 0
  how = rep("skip", length(b))
  how[b <= lim$capture_max] = "ref"
  how[b > lim$capture_max & predicted %in% c("assign", "remove") & b <= lim$max_bytes] = "ref"
  how[b > lim$capture_max & predicted == "modify" & b <= lim$spill_max & isTRUE(spill_ok)] = "disk"
  how[mode == "copy"] = "copy"
  how[mode == "none"] = "none"
  how
}

#' Value bindings of `envir` with address, class, bytes and fingerprint (P09's env_snapshot(),
#' which never forces promises or calls active bindings); `previous` reuses cached sizes
#' @noRd
ckpt_value_snapshot = function(envir, previous = NULL) {
  snap = env_snapshot(envir, previous)
  snap = snap[snap$kind == "value", c("name", "address", "class", "bytes", "fp"), drop = FALSE]
  snap$class = vapply(snap$class, function(x) ckpt_scalar(x, "unknown"), "", USE.NAMES = FALSE)
  rownames(snap) = NULL
  snap
}

#' The full snapshot of a workspace, reusing the session's last one for cached sizes
#' @noRd
ckpt_snapshot = function(ck, envir) {
  snap = env_snapshot(envir, ck$snap)
  ck$snap = snap
  snap
}

#' gptr_preimage() for every binding of a snapshot; "copy" results go straight into the store
#' (with `dry = TRUE` nothing is copied and `store` may be NULL)
#' @noRd
ckpt_preimage_modes = function(store, envir, snap, pred, lim, dry = FALSE) {
  n = nrow(snap)
  mode = rep("ref", n)
  reason = rep("", n)
  key = rep("", n)
  i = 1L
  while (i <= n) {
    pm = gptr_preimage(get(snap$name[i], envir = envir, inherits = FALSE), snap$name[i],
                       list(predicted = pred[i], bytes = snap$bytes[i], budget = lim$max_bytes,
                            dry = dry))
    mode[i] = ckpt_scalar(pm$mode, "ref")
    if (identical(mode[i], "none")) reason[i] = ckpt_scalar(pm$reason, "not restorable")
    if (identical(mode[i], "copy") && !dry) {
      if (is.null(pm$copy)) {
        mode[i] = "none"
        reason[i] = "the gptr_preimage() method returned no copy"
      } else {
        key[i] = ckpt_capture_value(store, pm$copy)
      }
    }
    pm = NULL
    i = i + 1L
  }
  list(mode = mode, reason = reason, key = key)
}

# ---- the objects checkpointer (G7 sections 3.4, 3.6, 3.9) --------------------------------------

#' Objects checkpointer, before a call that evaluates R code: capture pre-images per the plan
#' @return A token, or NULL when the call evaluates no R code.
#' @noRd
ckpt_objects_before = function(ck, call, envir, turn = 1L) {
  code = call$input$code
  if (!is.environment(envir) || !is.character(code) || length(code) != 1L) return(NULL)
  store = ck$obj
  ckpt_obj_sweep(store)
  lim = ckpt_limits()
  full = ckpt_snapshot(ck, envir)
  others = full$name[full$kind != "value"]
  snap = full[full$kind == "value", c("name", "address", "class", "bytes", "fp"), drop = FALSE]
  snap$class = vapply(snap$class, function(x) ckpt_scalar(x, "unknown"), "", USE.NAMES = FALSE)
  rownames(snap) = NULL
  tg = ckpt_predict(code)
  pred = ckpt_predicted(snap$name, tg)
  pm = ckpt_preimage_modes(store, envir, snap, pred, lim)
  how = ckpt_capture_how(snap$bytes, pred, pm$mode, !is.null(store$dir), lim)
  reason = pm$reason
  skip = how == "skip"
  reason[skip] = paste0("over the undo budget (", ckpt_fmt_bytes(snap$bytes[skip]), ")")
  key = pm$key
  refs = which(how == "ref")
  if (length(refs)) key[refs] = ckpt_capture(store, envir, snap$name[refs])$key
  for (j in which(how == "disk")) {
    key[j] = tryCatch(ckpt_capture_disk(store, envir, snap$name[j])$key, error = function(e) "")
    if (!nzchar(key[j])) {
      how[j] = "skip"
      reason[j] = "the disk image could not be written"
    }
  }
  list(frag = ckpt_frag_id(), turn = as.integer(turn), snap = snap, others = others, tg = tg,
       how = how, reason = reason, key = key, pred = pred)
}

#' Release a capture that turned out unchanged
#' @noRd
ckpt_release_capture = function(store, how, key) {
  if (!nzchar(key)) return(invisible(NULL))
  if (how %in% c("ref", "copy") && exists(key, envir = store$slots, inherits = FALSE)) {
    rm(list = key, envir = store$slots)
  }
  if (identical(how, "disk") && !is.null(store$dir)) unlink(ckpt_disk_file(store$dir, key))
  invisible(NULL)
}

#' A fragment row (JSON-safe: "" and -1 for missing values; never a value)
#' @noRd
ckpt_obj_row = function(name, status, how, class, bytes, pre, post, restorable, reason,
                        image = "", where = "", held = -1) {
  list(name = name, status = status, how = how, class = class, bytes = ckpt_json_num(bytes),
       pre_address = pre, post_address = post, restorable = restorable, reason = reason,
       image = image, where = where, held_bytes = ckpt_json_num(held))
}

#' Settle one captured binding after the call; returns a fragment row, or NULL when unchanged
#' @noRd
ckpt_settle_row = function(store, envir, s0, post, token, i, settled) {
  nm = s0$name
  how = token$how[i]
  key = token$key[i]
  j = match(nm, post$name)
  removed = is.na(j)
  now = if (removed) "" else post$address[j]
  same_fp = !removed && identical(post$fp[j], s0$fp)
  if (identical(how, "ref")) {
    st = settled[match(key, settled$key), , drop = FALSE]
    if (identical(st$status, "unchanged")) {
      if (same_fp) return(NULL)
      return(ckpt_obj_row(nm, "changed", how, s0$class, s0$bytes, s0$address, now, FALSE,
                          "modified by reference (the pre-image is the live object)"))
    }
    held = if (removed) ckpt_num(s0$bytes) else ckpt_unshared_bytes(store, key, envir, nm)
    store$index$bytes[store$index$key == key] = if (is.na(held)) 0 else held
    return(ckpt_obj_row(nm, if (removed) "removed" else "changed", how, s0$class, s0$bytes,
                        s0$address, now, TRUE, "", image = key, where = "memory", held = held))
  }
  changed = removed || !identical(now, s0$address) || !same_fp
  if (identical(how, "none")) changed = changed || token$pred[i] != "none"
  if (how %in% c("copy", "disk")) {
    if (!changed) {
      ckpt_release_capture(store, how, key)
      return(NULL)
    }
    disk = identical(how, "disk")
    held = if (disk) 0 else ckpt_unshared_bytes(store, key, envir, nm)
    ckpt_index_add(store, key, token$frag, nm, "pre", where = if (disk) "disk" else "memory",
                   file = if (disk) ckpt_disk_file(store$dir, key) else "",
                   bytes = if (disk) ckpt_num(s0$bytes) else held, turn = token$turn,
                   expect = s0$address)
    return(ckpt_obj_row(nm, if (removed) "removed" else "changed", how, s0$class, s0$bytes,
                        s0$address, now, TRUE, "", image = key,
                        where = if (disk) "disk" else "memory", held = held))
  }
  if (!changed) return(NULL)
  ckpt_obj_row(nm, if (removed) "removed" else "changed", how, s0$class, s0$bytes, s0$address,
               now, FALSE, token$reason[i])
}

#' Objects checkpointer, after the call: settle every capture and build the JSON-able fragment
#' @return `list(id, turn, objects = list(<row>))`, or NULL when nothing changed.
#' @noRd
ckpt_objects_after = function(ck, call, envir, token) {
  if (is.null(token) || !is.environment(envir)) return(NULL)
  store = ck$obj
  snap = token$snap
  full = ckpt_snapshot(ck, envir)
  post = full[full$kind == "value", c("name", "address", "class", "bytes", "fp"), drop = FALSE]
  post$class = vapply(post$class, function(x) ckpt_scalar(x, "unknown"), "", USE.NAMES = FALSE)
  refs = which(token$how == "ref")
  settled = if (length(refs)) {
    ckpt_settle(store, envir,
                data.frame(name = snap$name[refs], key = token$key[refs],
                           address = snap$address[refs], stringsAsFactors = FALSE),
                frag = token$frag, turn = token$turn)
  }
  rows = list()
  i = 1L
  while (i <= nrow(snap)) {
    row = ckpt_settle_row(store, envir, snap[i, , drop = FALSE], post, token, i, settled)
    if (!is.null(row)) rows[[length(rows) + 1L]] = row
    i = i + 1L
  }
  for (nm in setdiff(post$name, c(snap$name, token$others))) {
    j = match(nm, post$name)
    rows[[length(rows) + 1L]] = ckpt_obj_row(nm, "created", "created", post$class[j],
                                             post$bytes[j], "", post$address[j], TRUE, "")
  }
  lazy_pred = ckpt_predicted(token$others, token$tg)
  for (k in seq_along(token$others)) {
    nm = token$others[k]
    gone = !nm %in% full$name
    if (!gone && lazy_pred[k] == "none") next
    rows[[length(rows) + 1L]] = ckpt_obj_row(nm, if (gone) "removed" else "changed", "none",
                                             "unknown", NA, "", "", FALSE,
                                             "a promise or an active binding (not captured)")
  }
  if (!length(rows)) return(NULL)
  list(id = token$frag, turn = token$turn, objects = rows)
}

#' Does a binding's current address match an expected one ("" means: absent)?
#' @noRd
ckpt_expect_ok = function(now, expect) {
  if (!nzchar(expect)) return(is.na(now))
  identical(now, expect)
}

#' Undo one objects fragment, newest row first (the 3-way rule of G7 section 3.6)
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_objects_undo = function(ck, fragment, envir, force = FALSE, dry = FALSE) {
  store = ck$obj
  frag = ckpt_scalar(fragment$id)
  turn = as.integer(ckpt_num(fragment$turn))
  rows = fragment$objects
  out = ckpt_items()
  for (i in rev(seq_along(rows))) {
    r = rows[[i]]
    nm = ckpt_scalar(r$name)
    item = paste("object", nm)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not restored (", ckpt_scalar(r$reason), ")"))
      next
    }
    now = ckpt_addr(envir, nm)
    status = ckpt_scalar(r$status)
    if (identical(status, "created")) {
      if (is.na(now)) {
        out = ckpt_item(out, item, TRUE, "already absent")
      } else if (!force && !identical(now, ckpt_scalar(r$post_address))) {
        out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
      } else if (dry) {
        out = ckpt_item(out, item, TRUE, "would be removed")
      } else {
        ckpt_uncreate(store, envir, nm, frag, turn)
        out = ckpt_item(out, item, TRUE, "removed (created by the turn)")
      }
      next
    }
    expect = if (identical(status, "removed")) NA_character_ else ckpt_scalar(r$post_address)
    key = ckpt_index_find(store, frag, nm, "pre")
    if (is.na(key)) {
      # an image of an earlier R process: an eager disk image (where = "disk") or one spilled at
      # a turn end after the fragment was written (its row still says "memory"); keys are unique
      img = ckpt_scalar(r$image)
      f = if (nzchar(img) && !is.null(store$dir)) ckpt_disk_file(store$dir, img) else ""
      if (!nzchar(f) || !file.exists(f)) {
        out = ckpt_item(out, item, FALSE, paste0("not restored (no pre-image: dropped over the ",
                                                 "undo budget or made in another R process)"))
        next
      }
      if (!force) {
        out = ckpt_item(out, item, FALSE, paste0("not restored (the image on disk was made by ",
                                                 "an earlier R process; use force = TRUE)"))
        next
      }
      if (!dry) ckpt_index_add(store, img, frag, nm, "pre", where = "disk", file = f, turn = turn)
      key = img
    }
    if (!force && !identical(now, expect)) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be restored")
      next
    }
    res = ckpt_restore(store, envir, nm, key, expect = expect, force = force, frag = frag,
                       turn = turn)
    if (isTRUE(res$ok) && identical(status, "removed")) {
      ckpt_index_add(store, paste0("u", id_new("", 12L)), frag, nm, "mark", where = "none",
                     turn = turn, expect = res$address)
    }
    out = ckpt_item(out, item, isTRUE(res$ok),
                    if (isTRUE(res$ok)) "restored" else paste0("not restored (", res$reason, ")"))
  }
  out
}

#' Redo one objects fragment, oldest row first: the mirror of ckpt_objects_undo()
#' @noRd
ckpt_objects_redo = function(ck, fragment, envir, force = FALSE, dry = FALSE) {
  store = ck$obj
  frag = ckpt_scalar(fragment$id)
  turn = as.integer(ckpt_num(fragment$turn))
  out = ckpt_items()
  for (r in fragment$objects) {
    nm = ckpt_scalar(r$name)
    item = paste("object", nm)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not redone (", ckpt_scalar(r$reason), ")"))
      next
    }
    removed = identical(ckpt_scalar(r$status), "removed")
    key = ckpt_index_find(store, frag, nm, if (removed) "mark" else "redo")
    if (is.na(key)) {
      out = ckpt_item(out, item, FALSE, "not redone (it was not undone in this R process)")
      next
    }
    now = ckpt_addr(envir, nm)
    if (!force && !ckpt_expect_ok(now, store$index$expect[match(key, store$index$key)])) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the undo (kept current)")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be redone")
      next
    }
    if (!is.na(now)) {
      pk = ckpt_capture(store, envir, nm)$key
      ckpt_index_add(store, pk, frag, nm, "pre", turn = turn, expect = now,
                     bytes = ckpt_unshared_bytes(store, pk, envir, nm))
    }
    if (removed) {
      rm(list = nm, envir = envir)
      ckpt_index_remove(store, key)
      out = ckpt_item(out, item, TRUE, "removed again")
    } else {
      assign(nm, get(key, envir = store$slots, inherits = FALSE), envir = envir)
      rm(list = key, envir = store$slots)
      ckpt_index_remove(store, key)
      again = if (identical(ckpt_scalar(r$status), "created")) "created again" else "redone"
      out = ckpt_item(out, item, TRUE, again)
    }
  }
  out
}

#' One line per object of a fragment (previews of other checkpointers, /checkpoints)
#' @noRd
ckpt_objects_describe = function(fragment) {
  vapply(fragment$objects, function(r) {
    paste0("object ", ckpt_scalar(r$name), ": ", ckpt_scalar(r$status),
           if (isTRUE(r$restorable)) "" else " (not restorable)")
  }, "")
}

#' Model-facing notices for objects changed without an undo copy (G7 section 3.9, about 25
#' tokens each): `note: <name> (<size>) was <overwritten|modified|removed> without an undo copy
#' (<reason>).`
#' @noRd
ckpt_objects_notes = function(fragment) {
  out = character()
  for (r in fragment$objects) {
    if (isTRUE(r$restorable) || identical(ckpt_scalar(r$status), "created")) next
    verb = if (identical(ckpt_scalar(r$status), "removed")) {
      "removed"
    } else if (identical(ckpt_scalar(r$pre_address), ckpt_scalar(r$post_address))) {
      "modified"
    } else {
      "overwritten"
    }
    out = c(out, paste0("note: ", ckpt_scalar(r$name), " (", ckpt_fmt_bytes(ckpt_num(r$bytes)),
                        ") was ", verb, " without an undo copy (", ckpt_scalar(r$reason), ")."))
  }
  out
}

#' Enforce the in-memory budget at the end of a turn (G7 section 3.4 step 6): drop images older
#' than gptr.undo_turns turns, then spill the largest image while over gptr.undo_max_bytes, or
#' drop it when it cannot be spilled
#' @noRd
ckpt_objects_budget = function(ck, turn) {
  store = ck$obj
  lim = ckpt_limits()
  ckpt_obj_sweep(store)
  idx = store$index
  old = idx$key[!is.na(idx$turn) & idx$turn <= turn - lim$turns & idx$role != "mark"]
  if (length(old)) ckpt_drop(store, old)
  repeat {
    mem = store$index[store$index$where == "memory", , drop = FALSE]
    if (!nrow(mem) || sum(mem$bytes, na.rm = TRUE) <= lim$max_bytes) break
    big = mem[order(-mem$bytes, mem$seq), , drop = FALSE]
    spilled = if (!is.null(store$dir) && isTRUE(big$bytes[1L] <= lim$spill_max)) {
      ckpt_spill(store, big$key[1L])
    }
    if (is.null(spilled)) ckpt_drop(store, big$key[1L])
  }
  invisible(store$index)
}

#' The `checkpoint.note` service (contract 7.0): "cannot be undone: ..." for the permission
#' detail view of a call that would change objects gptr cannot capture, or NULL. `run` may be
#' NULL (P11's detail view), then the innermost executing run is used.
#' @noRd
ckpt_note = function(call, run = NULL) {
  code = call$input$code
  if (!is.character(code) || length(code) != 1L) return(NULL)
  mode = ckpt_scalar(setting_get("checkpoint", default = "on"), "on")
  if (identical(mode, "off")) {
    return("cannot be undone: checkpoints are off (gptr.checkpoint = \"off\")")
  }
  if (identical(mode, "files")) return(NULL)
  run = run %||% run_current()
  envir = if (is.null(run)) NULL else tryCatch(run_eval_env(run), error = function(e) NULL)
  if (!is.environment(envir)) return(NULL)
  snap = ckpt_value_snapshot(envir)
  pred = ckpt_predicted(snap$name, ckpt_predict(code))
  keep = pred != "none"
  if (!any(keep)) return(NULL)
  snap = snap[keep, , drop = FALSE]
  pred = pred[keep]
  lim = ckpt_limits()
  pm = ckpt_preimage_modes(NULL, envir, snap, pred, lim, dry = TRUE)
  how = ckpt_capture_how(snap$bytes, pred, pm$mode, ckpt_spill_allowed(), lim)
  bad = how %in% c("none", "skip")
  if (!any(bad)) return(NULL)
  why = ifelse(how[bad] == "skip",
               paste0(ckpt_fmt_bytes(snap$bytes[bad]), ", over the undo budget"), pm$reason[bad])
  paste0("cannot be undone: ", paste0(snap$name[bad], " (", why, ")", collapse = "; "))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 129 ]` (55 from Task 1, 74 new).

Cross-plan note (do not edit P01's files): IC-31 makes `ckpt_predict()` call P11's `code_targets()` (L4 `perm-classify.R`), which IC-33's kernel SDK (P01's `arch_kernel_sdk()`) does not list. P01's `tests/testthat/helper-arch.R` admits exactly this edge through `arch_contract_edges()` (caller area `ckpt` -> `code_targets`, P01's cross-plan consolidation), so `Rscript --vanilla -e 'devtools::test(filter = "arch-layers")'` reports no P16 edge; no other P16 edge leaves the IC-33 allowlist (self-review, ambiguity 1).

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-objects.R tests/testthat/test-ckpt-objects.R
git commit -m "feat(ckpt): add the object capture policy, objects checkpointer and undo note"
```

### Task 3: The state checkpointer

**Files:**
- Modify: `R/ckpt-objects.R` (append)
- Test: `tests/testthat/test-ckpt-objects.R` (append)

**Interfaces:**
- Consumes: Tasks 1-2 (`ckpt_frag_id()`, `ckpt_chr()`, `ckpt_scalar()`, `ckpt_items()`, `ckpt_item()`, `ckpt_limits()`, `ckpt_ck_new()`); P01 `hash_xxh128(x)`.
- Produces (used by Task 6): `ckpt_state_before(ck, call, turn = 1L)` -> token or `NULL` (calls without R code); `ckpt_state_after(ck, call, token)` -> `list(id, turn, options, envvars, wd, locale, attached, detached, loaded, dev_opened, dev_closed, con_opened, con_closed, rng)` or `NULL`; `ckpt_state_undo(ck, fragment, force = FALSE, dry = FALSE)`, `ckpt_state_redo(ck, fragment, force = FALSE, dry = FALSE)` -> item tables; `ckpt_state_describe(fragment)`.

Adapted from G7's verified `p4/ckpt_state.R` (report section 5.5; verification log item 12). The fragment holds names only; option values and working directories stay in memory (`ck$state_img`, keyed by fragment id), so a record from another R process reports "the values were not kept". Two deliberate departures from the prototype, forced by the lint rules of 04 §12.3: environment variables are reported, never set (no `Sys.setenv()` outside `auth-dotenv.R`, and values may be secrets), and the RNG state is reported, never assigned (only `rng_swap()` and `with_seed_preserved()` assign `.Random.seed`, IC-61). Options, the working directory, attached packages and connections the turn opened are restored with the 3-way rule; loaded namespaces stay loaded; devices the turn opened are closed only with `options(gptr.checkpoint_close_devices = TRUE)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ckpt-objects.R`:

```r
test_that("the state checkpointer restores options and the working directory (3-way)", {
  ck = ckpt_ck_new("s0000000011")
  withr::local_options(ckpttest.opt = "before")
  old_wd = getwd()
  withr::defer(setwd(old_wd))
  dir = withr::local_tempdir()
  call = list(id = "c1", name = "r",
              input = list(code = "options(ckpttest.opt = 'after'); setwd(dir)"))
  tok = ckpt_state_before(ck, call, turn = 1L)
  options(ckpttest.opt = "after")
  setwd(dir)
  frag = ckpt_state_after(ck, call, tok)
  expect_identical(frag$options, "ckpttest.opt")
  expect_true(frag$wd)
  expect_silent(json_encode(frag))
  u = ckpt_state_undo(ck, frag)
  expect_identical(getOption("ckpttest.opt"), "before")
  expect_identical(normalizePath(getwd()), normalizePath(old_wd))
  expect_true(all(u$ok[u$item %in% c("option ckpttest.opt", "working directory")]))
  r = ckpt_state_redo(ck, frag)
  expect_true(all(r$ok))
  expect_identical(getOption("ckpttest.opt"), "after")
  expect_identical(normalizePath(getwd()), normalizePath(dir))
  options(ckpttest.opt = "user")
  u = ckpt_state_undo(ck, frag)
  expect_match(u$action[u$item == "option ckpttest.opt"], "conflict")
  expect_identical(getOption("ckpttest.opt"), "user")
})

test_that("environment variables and the RNG state are reported, never set", {
  ck = ckpt_ck_new("s0000000012")
  withr::local_envvar(CKPT_TEST_VAR = "a")
  withr::local_preserve_seed()
  call = list(id = "c2", name = "r", input = list(code = "Sys.setenv(CKPT_TEST_VAR = 'b')"))
  tok = ckpt_state_before(ck, call)
  withr::local_envvar(CKPT_TEST_VAR = "b")
  invisible(stats::runif(1))
  frag = ckpt_state_after(ck, call, tok)
  expect_identical(frag$envvars, "CKPT_TEST_VAR")
  expect_true(frag$rng)
  u = ckpt_state_undo(ck, frag)
  expect_identical(Sys.getenv("CKPT_TEST_VAR"), "b")
  expect_false(u$ok[u$item == "environment variable CKPT_TEST_VAR"])
  expect_true(is.na(u$ok[u$item == "RNG state"]))
  expect_false("b" %in% unlist(frag))
})

test_that("packages attached by the turn are detached; nothing is recorded when nothing changed", {
  skip_if("package:tools" %in% search())
  ck = ckpt_ck_new("s0000000013")
  withr::defer(if ("package:tools" %in% search()) detach("package:tools", character.only = TRUE))
  call = list(id = "c3", name = "r", input = list(code = "library(tools)"))
  tok = ckpt_state_before(ck, call)
  suppressPackageStartupMessages(attachNamespace("tools"))
  frag = ckpt_state_after(ck, call, tok)
  expect_true("package:tools" %in% frag$attached)
  u = ckpt_state_undo(ck, frag)
  expect_false("package:tools" %in% search())
  expect_true(u$ok[u$item == "package:tools"])
  tok = ckpt_state_before(ck, call)
  expect_null(ckpt_state_after(ck, call, tok))
  expect_null(ckpt_state_before(ck, list(id = "c4", name = "write", input = list(path = "a"))))
})

test_that("connections the turn opened are closed on undo", {
  ck = ckpt_ck_new("s0000000014")
  call = list(id = "c5", name = "r", input = list(code = "con = file(tempfile(), 'w')"))
  tok = ckpt_state_before(ck, call)
  con = file(withr::local_tempfile(), "w")
  frag = ckpt_state_after(ck, call, tok)
  expect_identical(as.integer(frag$con_opened), as.integer(con))
  u = ckpt_state_undo(ck, frag)
  expect_true(u$ok[startsWith(u$item, "connection")])
  expect_false(as.integer(con) %in% as.integer(getAllConnections()))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects")'`

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 129 ]`; the four new tests error with `could not find function "ckpt_state_before"`.

- [ ] **Step 3: Write the implementation**

Append to `R/ckpt-objects.R`:

```r
# ---- the state checkpointer (G7 section 5.5, p4/ckpt_state.R) -----------------------------------
# Option values and working directories are kept in memory only (ck$state_img); fragments carry
# names. Environment variables are reported, never set (the lint rule allows Sys.setenv() only in
# auth-dotenv.R, and values may be secrets), and the RNG state is reported, never assigned
# (IC-61: only rng_swap() and with_seed_preserved() assign .Random.seed).

#' Options the evaluator owns and restores itself (never checkpointed; G7 p4)
#' @noRd
ckpt_harness_options = c("max.print", "width", "warn", "rlang_interactive", "cli.dynamic",
                         "cli.num_colors", "askYesNo", "try.outFile")

#' A hash of the global RNG state ("" when there is none); reads only
#' @noRd
ckpt_seed_hash = function() {
  s = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (is.null(s)) "" else hash_xxh128(s)
}

#' Snapshot of the process state an R tool call can change (kept in memory only)
#' @noRd
ckpt_state_snapshot = function() {
  list(options = options(), wd = getwd(), envvars = Sys.getenv(), locale = Sys.getlocale(),
       search = search(), loaded = loadedNamespaces(),
       devices = as.integer(grDevices::dev.list()),
       connections = setdiff(as.integer(getAllConnections()), 0:2),
       seed = ckpt_seed_hash())
}

#' Names of what changed between two state snapshots
#' @noRd
ckpt_state_diff = function(pre, post, rng = TRUE) {
  on = setdiff(union(names(pre$options), names(post$options)), ckpt_harness_options)
  same_opt = vapply(on, function(n) identical(pre$options[[n]], post$options[[n]]), TRUE)
  en = union(names(pre$envvars), names(post$envvars))
  same_env = vapply(en, function(n) identical(unname(pre$envvars[n]), unname(post$envvars[n])),
                    TRUE)
  list(options = on[!same_opt], envvars = en[!same_env], wd = !identical(pre$wd, post$wd),
       locale = !identical(pre$locale, post$locale),
       attached = setdiff(post$search, pre$search), detached = setdiff(pre$search, post$search),
       loaded = setdiff(post$loaded, pre$loaded),
       dev_opened = setdiff(post$devices, pre$devices),
       dev_closed = setdiff(pre$devices, post$devices),
       con_opened = setdiff(post$connections, pre$connections),
       con_closed = setdiff(pre$connections, post$connections),
       rng = isTRUE(rng) && !identical(pre$seed, post$seed))
}

#' Did anything in a state diff change?
#' @noRd
ckpt_state_changed = function(d) {
  length(ckpt_chr(d$options)) > 0L || length(ckpt_chr(d$envvars)) > 0L || isTRUE(d$wd) ||
    isTRUE(d$locale) || length(ckpt_chr(d$attached)) > 0L ||
    length(ckpt_chr(d$detached)) > 0L || length(ckpt_chr(d$loaded)) > 0L ||
    length(ckpt_chr(d$dev_opened)) > 0L || length(ckpt_chr(d$dev_closed)) > 0L ||
    length(ckpt_chr(d$con_opened)) > 0L || length(ckpt_chr(d$con_closed)) > 0L ||
    isTRUE(d$rng)
}

#' State checkpointer, before a call that evaluates R code
#' @noRd
ckpt_state_before = function(ck, call, turn = 1L) {
  code = call$input$code
  if (!is.character(code) || length(code) != 1L) return(NULL)
  list(frag = ckpt_frag_id(), turn = as.integer(turn), pre = ckpt_state_snapshot())
}

#' State checkpointer, after the call: names in the fragment, values in `ck$state_img`
#' @return `list(id, turn, options, envvars, wd, locale, attached, detached, loaded, dev_opened,
#'   dev_closed, con_opened, con_closed, rng)`, or NULL when nothing changed.
#' @noRd
ckpt_state_after = function(ck, call, token) {
  if (is.null(token)) return(NULL)
  pre = token$pre
  post = ckpt_state_snapshot()
  d = ckpt_state_diff(pre, post, rng = ckpt_limits()$rng)
  if (!ckpt_state_changed(d)) return(NULL)
  opts = d$options
  assign(token$frag, list(
    options_pre = stats::setNames(lapply(opts, function(n) pre$options[[n]]), opts),
    options_post = stats::setNames(lapply(opts, function(n) post$options[[n]]), opts),
    wd_pre = pre$wd, wd_post = post$wd), envir = ck$state_img)
  c(list(id = token$frag, turn = token$turn), d)
}

#' Attach a namespace again (redo of an attach, undo of a detach); FALSE when impossible
#' @noRd
ckpt_reattach = function(p) {
  if (p %in% search()) return(TRUE)
  pkg = sub("^package:", "", p)
  if (!requireNamespace(pkg, quietly = TRUE)) return(FALSE)
  tryCatch({
    suppressPackageStartupMessages(attachNamespace(pkg))
    TRUE
  }, error = function(e) FALSE)
}

#' Detach a package the turn attached; FALSE when detach() fails
#' @noRd
ckpt_detach = function(p) {
  if (!p %in% search()) return(TRUE)
  tryCatch({
    detach(p, character.only = TRUE)
    TRUE
  }, error = function(e) FALSE)
}

#' Undo one state fragment (3-way per item: an item is put back only if its current value is
#' still the value the call left)
#' @noRd
ckpt_state_undo = function(ck, fragment, force = FALSE, dry = FALSE) {
  lim = ckpt_limits()
  out = ckpt_items()
  img = get0(ckpt_scalar(fragment$id), envir = ck$state_img, inherits = FALSE)
  gone = "not restored (the values were not kept: another R process made this checkpoint)"
  for (n in ckpt_chr(fragment$options)) {
    item = paste("option", n)
    if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, gone)
    } else if (!force && !identical(getOption(n), img$options_post[[n]])) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
    } else if (dry) {
      out = ckpt_item(out, item, TRUE, "would be restored")
    } else {
      options(stats::setNames(list(img$options_pre[[n]]), n))
      out = ckpt_item(out, item, TRUE, "restored")
    }
  }
  for (n in ckpt_chr(fragment$envvars)) {
    out = ckpt_item(out, paste("environment variable", n), FALSE,
                    "not restored (gptr never sets environment variables; use Sys.setenv())")
  }
  if (isTRUE(fragment$wd)) {
    item = "working directory"
    if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, gone)
    } else if (!force && !identical(getwd(), img$wd_post)) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
    } else if (dry) {
      out = ckpt_item(out, item, TRUE, "would be restored")
    } else {
      setwd(img$wd_pre)
      out = ckpt_item(out, item, TRUE, "restored")
    }
  }
  if (isTRUE(fragment$locale)) {
    out = ckpt_item(out, "locale", NA, "changed by the turn; left as is (see Sys.setlocale())")
  }
  for (p in grep("^package:", ckpt_chr(fragment$attached), value = TRUE)) {
    ok = dry || ckpt_detach(p)
    out = ckpt_item(out, p, ok, if (ok) "detached" else "not restored (detach() failed)")
  }
  for (p in grep("^package:", ckpt_chr(fragment$detached), value = TRUE)) {
    ok = dry || ckpt_reattach(p)
    out = ckpt_item(out, p, ok, if (ok) "attached again" else "not restored (cannot attach it)")
  }
  loaded = ckpt_chr(fragment$loaded)
  if (length(loaded)) {
    out = ckpt_item(out, paste("namespaces", paste(loaded, collapse = ", ")), NA,
                    "stay loaded (unloading is unsafe)")
  }
  for (dv in ckpt_chr(fragment$dev_opened)) {
    item = paste("graphics device", dv)
    if (lim$close_devices && !dry && as.integer(dv) %in% grDevices::dev.list()) {
      grDevices::dev.off(as.integer(dv))
      out = ckpt_item(out, item, TRUE, "closed")
    } else {
      out = ckpt_item(out, item, NA, "left open (gptr.checkpoint_close_devices)")
    }
  }
  for (dv in ckpt_chr(fragment$dev_closed)) {
    out = ckpt_item(out, paste("graphics device", dv), FALSE,
                    "not restored (a closed device cannot be reopened)")
  }
  for (cn in ckpt_chr(fragment$con_opened)) {
    open_now = as.integer(cn) %in% as.integer(getAllConnections())
    if (open_now && !dry) close(getConnection(as.integer(cn)))
    out = ckpt_item(out, paste("connection", cn), TRUE,
                    if (open_now) "closed" else "already closed")
  }
  for (cn in ckpt_chr(fragment$con_closed)) {
    out = ckpt_item(out, paste("connection", cn), FALSE,
                    "not restored (a closed connection cannot be reopened)")
  }
  if (isTRUE(fragment$rng) && lim$rng) {
    out = ckpt_item(out, "RNG state", NA,
                    "advanced by the turn; left as is (gptr never sets .Random.seed)")
  }
  out
}

#' Redo one state fragment: options and the working directory go back to their post values,
#' attachments are repeated
#' @noRd
ckpt_state_redo = function(ck, fragment, force = FALSE, dry = FALSE) {
  out = ckpt_items()
  img = get0(ckpt_scalar(fragment$id), envir = ck$state_img, inherits = FALSE)
  for (n in ckpt_chr(fragment$options)) {
    item = paste("option", n)
    if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, "not redone (the values were not kept)")
    } else if (!force && !identical(getOption(n), img$options_pre[[n]])) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the undo (kept current)")
    } else if (dry) {
      out = ckpt_item(out, item, TRUE, "would be redone")
    } else {
      options(stats::setNames(list(img$options_post[[n]]), n))
      out = ckpt_item(out, item, TRUE, "redone")
    }
  }
  if (isTRUE(fragment$wd) && !is.null(img)) {
    item = "working directory"
    if (!force && !identical(getwd(), img$wd_pre)) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the undo (kept current)")
    } else if (dry) {
      out = ckpt_item(out, item, TRUE, "would be redone")
    } else {
      setwd(img$wd_post)
      out = ckpt_item(out, item, TRUE, "redone")
    }
  }
  for (p in grep("^package:", ckpt_chr(fragment$attached), value = TRUE)) {
    ok = dry || ckpt_reattach(p)
    out = ckpt_item(out, p, ok, if (ok) "attached again" else "not redone (cannot attach it)")
  }
  for (p in grep("^package:", ckpt_chr(fragment$detached), value = TRUE)) {
    ok = dry || ckpt_detach(p)
    out = ckpt_item(out, p, ok, if (ok) "detached again" else "not redone (detach() failed)")
  }
  out
}

#' One line per item of a state fragment
#' @noRd
ckpt_state_describe = function(fragment) {
  c(paste("option", ckpt_chr(fragment$options), recycle0 = TRUE),
    paste("environment variable", ckpt_chr(fragment$envvars), recycle0 = TRUE),
    if (isTRUE(fragment$wd)) "working directory",
    ckpt_chr(fragment$attached), ckpt_chr(fragment$detached),
    if (isTRUE(fragment$rng)) "RNG state")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-objects")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 154 ]` (one SKIP and five fewer PASS when `package:tools` is already attached in the test process).

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-objects.R tests/testthat/test-ckpt-objects.R
git commit -m "feat(ckpt): add the session-state checkpointer"
```

### Task 4: Content-addressed blob store and garbage collection

**Files:**
- Create: `R/ckpt-files.R`
- Test: `tests/testthat/test-ckpt-files.R` (create)

**Interfaces:**
- Consumes: Task 2 `ckpt_store_root()`, `ckpt_limits()`, Task 1 `ckpt_fmt_bytes()`; P01 `hash_file(path)` (`rlang::hash_file()`, XXH128, 32 hex), `write_atomic(path, content)`, `workspace_root(create = TRUE)`, `json_encode()`, `json_obj()`, `gptr_inform(message, class, ..., .once = NULL)`; P04 `pid_alive(pid, create_time = NULL)`; P06's lock format (`<session file>.lock/pid`, two lines: pid and process creation time); tests: P01 `local_project()`, `rscript_path()`, processx.
- Produces: `ckpt_store_put(path)` -> chr of hashes and `ckpt_store_get(hash, dest)` -> `lgl(1)` (04 §7.16; consumers P16, P23; `ckpt_store_put()` is in the IC-33 kernel SDK); `ckpt_blob_path(hash, gz)`, `ckpt_blob_find(hash)`, `ckpt_blob_read(hash)`; `ckpt_gc(root = workspace_root(create = FALSE), days = ckpt_limits()$days, now = Sys.time())` -> `list(deleted, kept, skipped, bytes)` invisibly (IC-71); helpers `ckpt_lock_holder(session_file)`, `ckpt_foreign_lock(session_files)`, `ckpt_session_hashes(session_files)`.

Adapted from G7's verified `p3/ckpt_files.R` (report section 5.4; verification log items 9-11: XXH128 through rlang, gzip level 1 up to 8 MB, already-compressed formats stored raw, new blobs written to a temporary name and renamed). The collector implements IC-71 verbatim: it "prunes only blobs unreferenced by every session file of the project and older than `gptr.checkpoint_days`, and skips while another live pid holds a session lock in the project". A blob's modification time is its "last referenced" time (refreshed on every deduplicated put); `index.json` records it. References are read from the `custom` lines of every session file (every 32-hex token counts, so an unrelated token only keeps a blob longer). The live-lock test starts a real second R process (`rscript_path()`, `skip_on_cran()`): this is acceptance 5's "pruning in one process does not delete a blob another live session references".

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ckpt-files.R`:

```r
# tests/testthat/test-ckpt-files.R -- the blob store, garbage collection, the tracker and the
# guarded 3-way restores (P16).

blob_count = function() {
  length(list.files(file.path(workspace_root(create = FALSE), "checkpoints", "blobs"),
                    recursive = TRUE))
}

test_that("the blob store deduplicates, compresses small text and restores atomically", {
  proj = local_project()
  f = file.path(proj, "a.R")
  writeLines(c("x = 1", "y = 2"), f)
  h = ckpt_store_put(f)
  expect_match(h, "^[0-9a-f]{32}$")
  blob = ckpt_blob_find(h)
  expect_true(endsWith(blob, ".gz"))
  expect_match(blob, "/.gptr/checkpoints/blobs/", fixed = TRUE)
  n0 = blob_count()
  f2 = file.path(proj, "copy.R")
  file.copy(f, f2)
  expect_identical(ckpt_store_put(f2), h)
  expect_identical(blob_count(), n0)
  writeLines("changed", f)
  expect_true(ckpt_store_get(h, f))
  expect_identical(readLines(f), c("x = 1", "y = 2"))
  expect_false(ckpt_store_get(strrep("0", 32L), f))
  expect_identical(ckpt_store_put(character()), character())
})

test_that("already-compressed files are stored raw and come back byte for byte", {
  proj = local_project()
  f = file.path(proj, "d.rds")
  saveRDS(1:10, f)
  h = ckpt_store_put(f)
  expect_false(endsWith(ckpt_blob_find(h), ".gz"))
  out = file.path(proj, "restored", "d.rds")
  expect_true(ckpt_store_get(h, out))
  expect_identical(readBin(out, "raw", 1e4), readBin(f, "raw", 1e4))
})

test_that("without a workspace the store lives under tempdir(), never in the project", {
  proj = local_project(gptr = FALSE)
  f = file.path(proj, "a.txt")
  writeLines("a", f)
  h = ckpt_store_put(f)
  expect_true(startsWith(path_norm(ckpt_blob_find(h)), path_norm(tempdir())))
  expect_false(dir.exists(file.path(proj, ".gptr")))
})

test_that("blob GC keeps referenced and young blobs and deletes old unreferenced ones", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  make = function(txt) {
    f = tempfile(fileext = ".txt", tmpdir = proj)
    writeLines(txt, f)
    ckpt_store_put(f)
  }
  h_ref = make("referenced")
  h_old = make("old and unreferenced")
  h_new = make("young and unreferenced")
  old = Sys.time() - 40 * 86400
  Sys.setFileTime(ckpt_blob_find(h_ref), old)
  Sys.setFileTime(ckpt_blob_find(h_old), old)
  sdir = file.path(root, "sessions")
  writeLines(c('{"type":"session","version":3,"id":"s0000000001"}',
               paste0('{"type":"custom","id":"a1b2c3d4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"a.R","pre":"', h_ref, '"}]}}}}')),
             file.path(sdir, "20260930T000000_s0000000001.jsonl"))
  stale = file.path(root, "checkpoints", "blobs", "ab", paste0(strrep("ab", 16L), ".tmp-1"))
  dir.create(dirname(stale), showWarnings = FALSE)
  writeLines("interrupted", stale)
  Sys.setFileTime(stale, old)
  res = ckpt_gc(root, days = 30)
  expect_false(file.exists(stale))
  expect_false(res$skipped)
  expect_identical(res$deleted, 1L)
  expect_false(is.null(ckpt_blob_find(h_ref)))
  expect_null(ckpt_blob_find(h_old))
  expect_false(is.null(ckpt_blob_find(h_new)))
  idx = jsonlite::fromJSON(file.path(root, "checkpoints", "index.json"), simplifyVector = FALSE)
  expect_setequal(names(idx$blobs), c(h_ref, h_new))
})

test_that("blob GC skips while another live process holds a session lock (IC-71)", {
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("old and unreferenced", f)
  h_old = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h_old), Sys.time() - 40 * 86400)
  sf = file.path(root, "sessions", "20260930T000000_s0000000002.jsonl")
  writeLines('{"type":"session","version":3,"id":"s0000000002"}', sf)
  dir.create(paste0(sf, ".lock"))
  writeLines(c("999999", "1790000000.5"), file.path(paste0(sf, ".lock"), "pid"))
  local_mocked_bindings(pid_alive = function(pid, create_time = NULL) TRUE)
  res = ckpt_gc(root, days = 30)
  expect_true(res$skipped)
  expect_false(is.null(ckpt_blob_find(h_old)))
  local_mocked_bindings(pid_alive = function(pid, create_time = NULL) FALSE)
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_null(ckpt_blob_find(h_old))
})

test_that("pruning in one process keeps the blobs another live process's session references", {
  skip_on_cran()
  proj = local_project()
  root = workspace_root(create = FALSE)
  f = withr::local_tempfile(fileext = ".txt")
  writeLines("held by the other session", f)
  h = ckpt_store_put(f)
  Sys.setFileTime(ckpt_blob_find(h), Sys.time() - 40 * 86400)
  other = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(other$kill())
  sf = file.path(root, "sessions", "20260930T000000_s0000000003.jsonl")
  writeLines(c('{"type":"session","version":3,"id":"s0000000003"}',
               paste0('{"type":"custom","id":"b1c2d3e4","parentId":null,',
                      '"customType":"gptr.checkpoint","data":{"fragments":{"files":{"files":[',
                      '{"path":"x.R","pre":"', h, '"}]}}}}')), sf)
  dir.create(paste0(sf, ".lock"))
  writeLines(c(as.character(other$get_pid()), ""), file.path(paste0(sf, ".lock"), "pid"))
  expect_true(ckpt_gc(root, days = 30)$skipped)
  other$kill()
  other$wait(5000)
  res = ckpt_gc(root, days = 30)
  expect_false(res$skipped)
  expect_false(is.null(ckpt_blob_find(h)))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-files")'`

Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors with `could not find function "ckpt_store_put"`.

- [ ] **Step 3: Write the implementation**

Create `R/ckpt-files.R`:

```r
# ckpt-files.R -- the content-addressed file store, blob garbage collection, the file tracker
# and walk, the files checkpointer and its guarded 3-way restores (P16, layer L4).
#
# Adapted from the verified G7 prototype (dev/research/G7-checkpoint-undo-rewind.md, section 5.4
# p3/ckpt_files.R; verification log items 9-11). Blobs live in
# <workspace root>/checkpoints/blobs/<2 hex>/<xxh128>[.gz] (gzip level 1 up to 8 MB; formats that
# are already compressed are stored raw), shared and deduplicated by every session of the
# project (contract 11.14). A tracker holds path -> hash for files whose content was captured; a
# walk after each mutating call finds created, modified and deleted files, including files
# written by model R code and by child processes (and, through the CLI-route scan of
# ckpt-rewind.R, a Codex workspace-write exec, IC-65). Changes from the prototype: walks stop at
# 50,000 files; restores go through write_atomic(); gzip blobs are read in chunks; restores never
# go through symbolic links (the file or a directory above it), never into .git or gptr's user
# directories, and ask a human for every path outside the project root and tempdir() and for
# control or critical paths (IC-52, IC-54); the garbage collector keeps every blob a session file
# of the project references and skips while another live process holds a session lock (IC-71).

# ---- the blob store ------------------------------------------------------------------------------

#' File names stored raw (already compressed)
#' @noRd
ckpt_no_compress = paste0("\\.(gz|bz2|xz|zip|zst|rds|rda|RData|qs2?|parquet|feather|arrow|",
                          "png|jpe?g|gif|pdf|xlsx|docx|pptx)$")

#' Path of a blob
#' @noRd
ckpt_blob_path = function(hash, gz) {
  file.path(ckpt_store_root(), "blobs", substr(hash, 1L, 2L),
            paste0(hash, if (gz) ".gz" else ""))
}

#' The stored blob of a hash, or NULL
#' @noRd
ckpt_blob_find = function(hash) {
  for (gz in c(TRUE, FALSE)) {
    p = ckpt_blob_path(hash, gz)
    if (file.exists(p)) return(p)
  }
  NULL
}

#' Store the current content of files (contract 7.16; also used by P23's artifact records)
#'
#' Deduplicated: an existing blob is not rewritten, only its modification time is refreshed (the
#' "last referenced" time the garbage collector reads).
#' @param path Absolute paths of existing regular files.
#' @return Their XXH128 hashes (32 hex), in order.
#' @noRd
ckpt_store_put = function(path) {
  path = as.character(path)
  if (!length(path)) return(character())
  hashes = unname(hash_file(path))
  for (i in seq_along(path)) ckpt_blob_write(path[i], hashes[i])
  hashes
}

#' Write one blob through a temporary name and a rename; an existing blob is only touched
#' @noRd
ckpt_blob_write = function(src, hash) {
  have = ckpt_blob_find(hash)
  if (!is.null(have)) {
    Sys.setFileTime(have, Sys.time())
    return(invisible(have))
  }
  size = file.size(src)
  gz = isTRUE(size <= 8e6) && !grepl(ckpt_no_compress, src, ignore.case = TRUE)
  dest = ckpt_blob_path(hash, gz)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp = paste0(dest, ".tmp-", Sys.getpid())
  if (gz) ckpt_gzip(src, tmp, size) else file.copy(src, tmp, overwrite = TRUE)
  if (!file.rename(tmp, dest)) unlink(tmp)
  invisible(dest)
}

#' gzip level 1 copy of a file
#' @noRd
ckpt_gzip = function(src, dest, size) {
  con = gzfile(dest, "wb", compression = 1L)
  on.exit(close(con), add = TRUE)
  writeBin(readBin(src, "raw", size), con)
  invisible(dest)
}

#' Read a gzip blob in 8 MB chunks
#' @noRd
ckpt_gunzip = function(path) {
  con = gzfile(path, "rb")
  on.exit(close(con), add = TRUE)
  chunks = list()
  repeat {
    b = readBin(con, "raw", 8388608L)
    if (!length(b)) break
    chunks[[length(chunks) + 1L]] = b
  }
  if (!length(chunks)) return(raw())
  do.call(c, chunks)
}

#' The bytes of a blob, or NULL when it is missing
#' @noRd
ckpt_blob_read = function(hash) {
  p = ckpt_blob_find(hash)
  if (is.null(p)) return(NULL)
  if (endsWith(p, ".gz")) ckpt_gunzip(p) else readBin(p, "raw", file.size(p))
}

#' Write the blob of `hash` to `dest` atomically (contract 7.16)
#' @return `TRUE`, or `FALSE` when the blob is missing.
#' @noRd
ckpt_store_get = function(hash, dest) {
  b = ckpt_blob_read(hash)
  if (is.null(b)) return(FALSE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  write_atomic(dest, b)
  TRUE
}

# ---- blob garbage collection (IC-71) ----------------------------------------------------------

#' The holder of a session lock `<file>.lock/pid` (two lines: pid and process creation time, the
#' format of P06's lock_acquire()), or NULL
#' @noRd
ckpt_lock_holder = function(session_file) {
  f = file.path(paste0(session_file, ".lock"), "pid")
  if (!file.exists(f)) return(NULL)
  x = tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  list(pid = suppressWarnings(as.integer(x[1L])),
       created = suppressWarnings(as.numeric(x[2L])),
       heartbeat = as.numeric(file.mtime(f)))
}

#' Does another live process hold a session lock of the project? A lock whose holder cannot be
#' read counts as live (the collector then skips: deleting too little is safe)
#' @noRd
ckpt_foreign_lock = function(session_files) {
  for (f in session_files) {
    h = ckpt_lock_holder(f)
    if (is.null(h)) next
    if (is.na(h$pid)) return(TRUE)
    if (identical(h$pid, Sys.getpid())) next
    if (isTRUE(as.numeric(Sys.time()) - h$heartbeat > 24 * 3600)) next
    created = if (is.na(h$created)) NULL else h$created
    alive = tryCatch(isTRUE(pid_alive(h$pid, created)), error = function(e) TRUE)
    if (alive) return(TRUE)
  }
  FALSE
}

#' Every 32-hex token in the custom entries of the given session files (blob hashes are
#' XXH128; a token that is not a blob hash only keeps a blob longer)
#' @noRd
ckpt_session_hashes = function(session_files) {
  out = character()
  for (f in session_files) {
    x = tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
    x = x[grepl("\"customType\"", x, fixed = TRUE)]
    if (length(x)) {
      m = regmatches(x, gregexpr("(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])", x, perl = TRUE))
      out = c(out, unlist(m))
    }
  }
  unique(out)
}

#' Collect checkpoint garbage of a workspace root (IC-71; G7 section 3.3 retention)
#'
#' Skips entirely while another live process holds a session lock of the project. Otherwise
#' deletes every blob that no session file references and that was last referenced (its
#' modification time) more than `days` days ago, and the spilled-image directories of sessions
#' that have no session file and are older than `days`; rewrites `index.json`
#' (`{"blobs": {"<hash>": <last referenced epoch>}}`) and tells the user once when the store is
#' above gptr.checkpoint_disk_bytes.
#' @return `list(deleted, kept, skipped, bytes)`, invisibly.
#' @noRd
ckpt_gc = function(root = workspace_root(create = FALSE), days = ckpt_limits()$days,
                   now = Sys.time()) {
  store = file.path(root, "checkpoints")
  if (!dir.exists(store)) {
    return(invisible(list(deleted = 0L, kept = 0L, skipped = FALSE, bytes = 0)))
  }
  sessions = list.files(file.path(root, "sessions"), pattern = "[.]jsonl$", full.names = TRUE)
  if (ckpt_foreign_lock(sessions)) {
    return(invisible(list(deleted = 0L, kept = NA_integer_, skipped = TRUE, bytes = NA_real_)))
  }
  live = ckpt_session_hashes(sessions)
  age = function(p) as.numeric(difftime(now, file.mtime(p), units = "days"))
  blobs = list.files(file.path(store, "blobs"), recursive = TRUE, full.names = TRUE)
  tmp = blobs[grepl("[.]tmp-", blobs)]
  # temporary names left by an interrupted write (a live writer renames within seconds)
  if (length(tmp)) unlink(tmp[!is.na(age(tmp)) & age(tmp) > 1])
  blobs = blobs[!grepl("[.]tmp-", blobs)]
  hash = sub("[.]gz$", "", basename(blobs))
  dead = !(hash %in% live) & !is.na(age(blobs)) & age(blobs) > days
  if (any(dead)) unlink(blobs[dead])
  ids = sub("^.*_", "", sub("[.]jsonl$", "", basename(sessions)))
  obj = list.dirs(file.path(store, "objects"), recursive = FALSE, full.names = TRUE)
  stale = obj[!(basename(obj) %in% ids) & !is.na(age(obj)) & age(obj) > days]
  if (length(stale)) unlink(stale, recursive = TRUE)
  keep = blobs[!dead]
  idx = stats::setNames(as.list(as.numeric(file.mtime(keep))), sub("[.]gz$", "", basename(keep)))
  write_atomic(file.path(store, "index.json"),
               json_encode(list(blobs = if (length(idx)) idx else json_obj())))
  bytes = sum(file.size(keep), na.rm = TRUE) +
    sum(file.size(list.files(file.path(store, "objects"), recursive = TRUE, full.names = TRUE)),
        na.rm = TRUE)
  if (bytes > ckpt_limits()$disk_bytes) {
    gptr_inform(paste0("The checkpoint store ", store, " holds ", ckpt_fmt_bytes(bytes),
                       ", above gptr.checkpoint_disk_bytes; gptr deletes only blobs that no ",
                       "session file references once they are gptr.checkpoint_days days old."),
                "notice", .once = paste0("ckpt-disk:", store))
  }
  invisible(list(deleted = sum(dead), kept = length(keep), skipped = FALSE, bytes = bytes))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-files")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 28 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-files.R tests/testthat/test-ckpt-files.R
git commit -m "feat(ckpt): add the content-addressed blob store and its garbage collector"
```

### Task 5: Walk, tracker, the files checkpointer and guarded restores

**Files:**
- Modify: `R/ckpt-files.R` (append)
- Test: `tests/testthat/test-ckpt-files.R` (append)

**Interfaces:**
- Consumes: Task 4 (`ckpt_store_put()`, `ckpt_store_get()`), Tasks 1-2 (`ckpt_frag_id()`, `ckpt_scalar()`, `ckpt_num()`, `ckpt_json_num()`, `ckpt_items()`, `ckpt_item()`, `ckpt_limits()`, `ckpt_predict()`, `ckpt_ck_new()`); P01 `path_norm(path)`, `project_root(path = getwd())`, `path_class(path, root = project_root())`, `gptr_user_dir(which, create = FALSE)`, `gptr_can_prompt()`, `ext_service_get(name)` (service `ui.get`, P11: `function(session = NULL) <spec:ui>` with `has_ui()` and `select(title, choices, default = NULL, ...)`), `gptr_inform()`; tests: P11 `local_scripted_ui(answers = list(), .env = parent.frame())`, P01 `local_project()`, `local_gptr_options()`.
- Produces (used by Tasks 6-7): `ckpt_walk(root, max_files = 50000L)` -> df(`path`, `size`, `mtime`, `link`); the tracker `ckpt_files_tracker(root)`, `ckpt_files_tr(ck)`; `ckpt_files_baseline(tr, lim)`, `ckpt_files_scan(tr, racy = 2)`, `ckpt_files_step(tr, lim)`, `ckpt_files_sync(tr, lim)`; the files checkpointer `ckpt_files_before(ck, call, turn = 1L)` -> token, `ckpt_files_after(ck, call, token)` -> `list(id, turn, root, files = list(<row>))` or `NULL`, `ckpt_files_turn_scan(ck, turn, force = FALSE)`, `ckpt_files_undo(ck, fragment, session = NULL, force = FALSE, dry = FALSE, turn_now = NA_integer_)`, `ckpt_files_redo(ck, fragment, session = NULL, force = FALSE, dry = FALSE)`, `ckpt_files_describe(fragment)`; `ckpt_file_row(path, abs, status, pre, post, mode, size, mtime, restorable, reason)`; the guards `ckpt_restore_guard(full, root = project_root())` -> `list(ok, ask, reason)`, `ckpt_confirm_outside(full, session)`, `ckpt_temp_root()`.

Adapted from G7's verified `p3/ckpt_files.R` (report section 5.4; walk, baseline of source-like files first, racy-clean rule, 3-way undo; verification log items 9-10). A files fragment row is `list(path, abs, status ("created", "modified", "deleted"), pre, post (hashes or ""), mode, post_size, post_mtime, restorable, reason)`; paths inside the walked root are relative (with the fragment's `root`), predicted paths outside it are absolute (`abs = TRUE`). Restores follow IC-52: never through a symbolic link (the file or a directory above it), never into `.git` or gptr's user directories, and "confined to the project root and `tempdir()`; a restore outside needs an `ask_human` per path"; the confinement uses the current `project_root()`, never a root read from a session file (so a planted record cannot widen it), and control or critical paths (`path_class()`, IC-54) also need the human. The walk is G7's own pruned walker, not P10's `walk_files()`: it must list symbolic links without following them, include hidden and git-ignored files (an ignored data file the agent overwrote must be restorable) and prune `.gptr`; 04 §7.10 does not specify those three behaviours for `walk_files()` (recorded in the self-review). A forced turn scan records what a CLI child changed during a turn (IC-65; wired to the `turn_end` hook in Task 6).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ckpt-files.R`:

```r
paths_status = function(frag) {
  stats::setNames(vapply(frag$files, function(r) r$status, ""),
                  vapply(frag$files, function(r) r$path, ""))
}

test_that("the walk prunes .git and .gptr and lists links without following them", {
  skip_on_os("windows")
  proj = local_project(files = list("R/a.R" = "a = 1", ".git/config" = "[core]",
                                    "data/x.csv" = "id"))
  file.symlink(file.path(proj, "data"), file.path(proj, "data_link"))
  w = ckpt_walk(proj)
  expect_setequal(w$path, c("R/a.R", "data/x.csv", "data_link"))
  expect_true(w$link[w$path == "data_link"])
})

test_that("a mutating step records created, modified and deleted files; undo and redo swap them", {
  proj = local_project(files = list("R/a.R" = "f = function(x) x + 1",
                                    "notes.md" = c("# Notes", "keep me")))
  ck = ckpt_ck_new("s0000000021")
  call = list(id = "c1", name = "r",
              input = list(code = "write.csv(data.frame(id = 1:3), 'out.csv')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  expect_true(all(c("R/a.R", "notes.md") %in% names(ck$files$hash)))
  writeLines("f = function(x) x + 10", file.path(proj, "R", "a.R"))
  utils::write.csv(data.frame(id = 1:3), file.path(proj, "out.csv"), row.names = FALSE)
  file.remove(file.path(proj, "notes.md"))
  frag = ckpt_files_after(ck, call, tok)
  st = paths_status(frag)
  expect_identical(st[["out.csv"]], "created")
  expect_identical(st[["R/a.R"]], "modified")
  expect_identical(st[["notes.md"]], "deleted")
  expect_silent(json_encode(frag))
  u = ckpt_files_undo(ck, frag)
  expect_true(all(u$ok))
  expect_false(file.exists(file.path(proj, "out.csv")))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "f = function(x) x + 1")
  expect_identical(readLines(file.path(proj, "notes.md")), c("# Notes", "keep me"))
  r = ckpt_files_redo(ck, frag)
  expect_true(all(r$ok))
  expect_true(file.exists(file.path(proj, "out.csv")))
  expect_identical(readLines(file.path(proj, "R", "a.R")), "f = function(x) x + 10")
  expect_false(file.exists(file.path(proj, "notes.md")))
})

test_that("files changed by a child process are recorded too", {
  skip_on_cran()
  proj = local_project(files = list("R/b.R" = "h = function() 'b'"))
  ck = ckpt_ck_new("s0000000022")
  call = list(id = "c1", name = "r", input = list(code = "system2('Rscript', 'job.R')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  processx::run(rscript_path(), c("--vanilla", "-e", "writeLines('child', 'R/b.R')"),
                wd = proj)
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(paths_status(frag)[["R/b.R"]], "modified")
  u = ckpt_files_undo(ck, frag)
  expect_true(all(u$ok))
  expect_identical(readLines(file.path(proj, "R", "b.R")), "h = function() 'b'")
})

test_that("undo keeps a file edited after the turn (3-way) unless forced", {
  proj = local_project(files = list("b.R" = "h = function() 'b'"))
  ck = ckpt_ck_new("s0000000023")
  call = list(id = "c1", name = "write", input = list(path = "b.R", content = "child"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("h = function() 'agent'", file.path(proj, "b.R"))
  frag = ckpt_files_after(ck, call, tok)
  writeLines("h = function() 'user edit'", file.path(proj, "b.R"))
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "conflict")
  expect_identical(readLines(file.path(proj, "b.R")), "h = function() 'user edit'")
  expect_identical(ckpt_files_undo(ck, frag, dry = TRUE)$ok, FALSE)
  u = ckpt_files_undo(ck, frag, force = TRUE)
  expect_true(u$ok)
  expect_identical(readLines(file.path(proj, "b.R")), "h = function() 'b'")
})

test_that("files over the capture cap and symbolic links are not restorable", {
  skip_on_os("windows")
  local_gptr_options(checkpoint_track_file_max = 10, checkpoint_capture_max = 10)
  proj = local_project(files = list("big.txt" = "0123456789ABCDEF", "notes.md" = "small"))
  file.symlink(file.path(proj, "notes.md"), file.path(proj, "link.md"))
  ck = ckpt_ck_new("s0000000024")
  call = list(id = "c1", name = "r", input = list(code = "cat('x', file = 'big.txt')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("0123456789ABCDEFGH", file.path(proj, "big.txt"))
  writeLines("longer text", file.path(proj, "notes.md"))
  frag = ckpt_files_after(ck, call, tok)
  rows = stats::setNames(frag$files, vapply(frag$files, function(r) r$path, ""))
  expect_false(rows[["big.txt"]]$restorable)
  expect_match(rows[["big.txt"]]$reason, "no pre-image")
  expect_false(rows[["link.md"]]$restorable)
  expect_match(rows[["link.md"]]$reason, "symbolic link")
  u = ckpt_files_undo(ck, frag)
  expect_identical(u$ok[u$item == "file link.md"], FALSE)
  expect_true(nzchar(Sys.readlink(file.path(proj, "link.md"))))
})

test_that("a path outside the project and tempdir() is restored only after a human confirms", {
  proj = local_project()
  outside = withr::local_tempdir()
  local_mocked_bindings(ckpt_temp_root = function() file.path(tempdir(), "not-this-one"))
  out = path_norm(file.path(outside, "result.csv"))
  writeLines("old", out)
  ck = ckpt_ck_new("s0000000025")
  call = list(id = "c9", name = "r",
              input = list(code = paste0("writeLines('new', '", out, "')")))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("new", out)
  frag = ckpt_files_after(ck, call, tok)
  row = frag$files[[1L]]
  expect_true(row$abs)
  expect_identical(row$status, "modified")
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "not confirmed")
  expect_identical(readLines(out), "new")
  expect_true(is.na(ckpt_files_undo(ck, frag, dry = TRUE)$ok))
  local_scripted_ui(answers = list(1L))
  u = ckpt_files_undo(ck, frag)
  expect_true(u$ok)
  expect_identical(readLines(out), "old")
})

test_that("a planted record pointing outside the project is not restored without a human", {
  proj = local_project()
  outside = withr::local_tempdir()
  local_mocked_bindings(ckpt_temp_root = function() file.path(tempdir(), "not-this-one"))
  target = path_norm(file.path(outside, "victim.txt"))
  writeLines("current", target)
  src = file.path(proj, "planted.txt")
  writeLines("planted", src)
  h = ckpt_store_put(src)
  ck = ckpt_ck_new("s0000000026")
  frag = list(id = "kplanted", turn = 1L, root = path_norm(outside),
              files = list(ckpt_file_row("victim.txt", FALSE, "modified", h,
                                         unname(hash_file(target)), 420, 8, 0, TRUE, "")))
  u = ckpt_files_undo(ck, frag)
  expect_false(u$ok)
  expect_match(u$action, "not confirmed")
  expect_identical(readLines(target), "current")
})

test_that("restores never write into .git or gptr's user directories; control paths ask", {
  proj = local_project()
  g = ckpt_restore_guard(file.path(proj, ".git", "config"))
  expect_false(g$ok)
  expect_match(g$reason, ".git")
  u = ckpt_restore_guard(file.path(gptr_user_dir("config"), "settings.json"))
  expect_false(u$ok)
  ok = ckpt_restore_guard(file.path(proj, "R", "a.R"))
  expect_true(ok$ok)
  expect_false(ok$ask)
  ctl = ckpt_restore_guard(file.path(proj, ".gptr", "settings.json"))
  expect_true(ctl$ok)
  expect_true(ctl$ask)
})

test_that("slow walks switch the session to one scan per turn plus predicted paths", {
  local_gptr_options(checkpoint_scan_budget = -1)
  proj = local_project(files = list("R/a.R" = "a = 1"))
  ck = ckpt_ck_new("s0000000027")
  call = list(id = "c1", name = "r", input = list(code = "writeLines('a = 2', 'R/a.R')"))
  tok = ckpt_files_before(ck, call, turn = 1L)
  writeLines("a = 2", file.path(proj, "R", "a.R"))
  frag = ckpt_files_after(ck, call, tok)
  expect_identical(names(paths_status(frag)), "R/a.R")
  expect_true(ck$files$per_turn)
  call2 = list(id = "c2", name = "write", input = list(path = "R/b.R", content = "b = 1"))
  tok2 = ckpt_files_before(ck, call2, turn = 1L)
  writeLines("b = 1", file.path(proj, "R", "b.R"))
  writeLines("unpredicted", file.path(proj, "other.txt"))
  frag2 = ckpt_files_after(ck, call2, tok2)
  expect_length(frag2$files, 1L)
  expect_true(frag2$files[[1L]]$abs)
  expect_identical(basename(frag2$files[[1L]]$path), "b.R")
  turn_frag = ckpt_files_turn_scan(ck, 1L)
  expect_identical(names(paths_status(turn_frag)), "other.txt")
})

test_that("a forced turn scan records what a CLI child changed (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  ck = ckpt_ck_new("s0000000028")
  ckpt_files_sync(ckpt_files_tr(ck), ckpt_limits())
  expect_null(ckpt_files_turn_scan(ck, 1L, force = TRUE))
  writeLines("a = 2", file.path(proj, "R", "a.R"))
  frag = ckpt_files_turn_scan(ck, 1L, force = TRUE)
  expect_identical(paths_status(frag), c(`R/a.R` = "modified"))
  u = ckpt_files_undo(ck, frag)
  expect_true(u$ok)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-files")'`

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 28 ]`; the ten new tests error with `could not find function "ckpt_walk"`, `"ckpt_files_before"`, `"ckpt_file_row"`, `"ckpt_restore_guard"` or `"ckpt_files_sync"` (`local_mocked_bindings()` reports that `ckpt_temp_root` does not exist).

- [ ] **Step 3: Write the implementation**

Append to `R/ckpt-files.R`:

```r
# ---- the tracker and the walk (G7 sections 3.5, 2.7) ---------------------------------------------

#' Directories the walk never enters (G7 p3; `.gptr` holds the store itself)
#' @noRd
ckpt_prune_dirs = c(".git", ".gptr", "node_modules", ".Rproj.user", "packrat", ".venv",
                    "__pycache__", ".ipynb_checkpoints", ".quarto", ".svn", ".hg")

#' The same prune as a regular expression over relative paths (plus renv's library)
#' @noRd
ckpt_prune_re = paste0("(^|/)(\\.git|\\.gptr|node_modules|\\.Rproj\\.user|packrat|\\.venv|",
                       "__pycache__|\\.ipynb_checkpoints|\\.quarto|\\.svn|\\.hg)(/|$)|",
                       "^renv/(library|staging|sandbox)(/|$)")

#' Source-like files go first into the baseline
#' @noRd
ckpt_source_re = "\\.(R|r|Rmd|qmd|Rnw|md|ya?ml|json|txt|csv|tsv|ipynb|py|sql|sh|toml|Rprofile)$"

#' Is a path a symbolic link?
#' @noRd
ckpt_is_link = function(path) {
  l = Sys.readlink(path)
  !is.na(l) & nzchar(l)
}

#' Pruned breadth-first walk of a project (G7 p3 `ckpt_walk()`, verified): one list.files(),
#' file.info() and Sys.readlink() per directory; hidden files included, .gitignore not applied
#' (an ignored data file the agent overwrote must be restorable); symbolic links are listed but
#' never followed; at most `max_files` files
#' @return df(path (relative, "/"), size, mtime (numeric), link), sorted by path.
#' @noRd
ckpt_walk = function(root, max_files = 50000L) {
  queue = ""
  out = list()
  n = 0L
  while (length(queue) && n <= max_files) {
    rel = queue[1L]
    queue = queue[-1L]
    d = if (nzchar(rel)) file.path(root, rel) else root
    ents = list.files(d, all.files = TRUE, no.. = TRUE)
    if (!length(ents)) next
    relp = if (nzchar(rel)) paste(rel, ents, sep = "/") else ents
    full = file.path(root, relp)
    info = file.info(full, extra_cols = FALSE)
    link = ckpt_is_link(full)
    isdir = !is.na(info$isdir) & info$isdir & !link
    queue = c(queue, relp[isdir & !(ents %in% ckpt_prune_dirs) & !grepl(ckpt_prune_re, relp)])
    f = (!isdir & !is.na(info$size)) | link
    if (any(f)) {
      out[[length(out) + 1L]] = data.frame(
        path = relp[f], size = ifelse(is.na(info$size[f]), 0, info$size[f]),
        mtime = ifelse(is.na(info$mtime[f]), 0, as.numeric(info$mtime[f])),
        link = link[f], stringsAsFactors = FALSE)
      n = n + sum(f)
    }
  }
  if (!length(out)) {
    return(data.frame(path = character(), size = numeric(), mtime = numeric(),
                      link = logical(), stringsAsFactors = FALSE))
  }
  w = do.call(rbind, out)
  w = w[order(w$path, method = "radix"), , drop = FALSE]
  rownames(w) = NULL
  w
}

#' A new file tracker for a project root
#'
#' `stat`: the last walk; `hash`/`mode`: path -> content hash and mode bits of captured files;
#' `explicit`/`explicit_mode`: predicted absolute paths outside the walk ("" absent, "?" present
#' but not capturable); `per_turn`: adaptive scanning switched on.
#' @noRd
ckpt_files_tracker = function(root) {
  tr = new.env(parent = emptyenv())
  tr$root = path_norm(root)
  tr$stat = NULL
  tr$hash = character()
  tr$mode = integer()
  tr$explicit = character()
  tr$explicit_mode = integer()
  tr$walk_time = NA_real_
  tr$per_turn = FALSE
  tr$scanned_turn = NA_integer_
  tr
}

#' The session's tracker, created on first use at project_root()
#' @noRd
ckpt_files_tr = function(ck) {
  if (!is.environment(ck$files)) ck$files = ckpt_files_tracker(project_root())
  ck$files
}

#' Path relative to `root`, or NA when outside it
#' @noRd
ckpt_rel = function(root, path) {
  r = sub("/+$", "", path_norm(root))
  p = path_norm(path)
  if (startsWith(p, paste0(r, "/"))) substring(p, nchar(r) + 2L) else NA_character_
}

#' Is `path` equal to or inside `dir` (after normalisation)?
#' @noRd
ckpt_within = function(path, dir) {
  p = path_norm(path)
  d = sub("/+$", "", path_norm(dir))
  identical(p, d) || startsWith(p, paste0(d, "/"))
}

#' Mode bits of files as integers (-1 when unknown)
#' @noRd
ckpt_modes = function(full) {
  m = suppressWarnings(as.integer(file.info(full, extra_cols = FALSE)$mode))
  m[is.na(m)] = -1L
  m
}

#' Capture the current content of tracked (relative) paths
#' @noRd
ckpt_ingest = function(tr, rel) {
  if (!length(rel)) return(character())
  full = file.path(tr$root, rel)
  h = ckpt_store_put(full)
  tr$hash[rel] = h
  tr$mode[rel] = ckpt_modes(full)
  h
}

#' Can the file at an absolute path be captured within the cap?
#' @noRd
ckpt_capturable = function(full, lim) {
  file.exists(full) && !dir.exists(full) && !ckpt_is_link(full) &&
    isTRUE(file.size(full) <= lim$file_capture_max)
}

#' Baseline at the first mutating call: walk, then capture small source-like files first within
#' gptr.checkpoint_track_file_max (each) and gptr.checkpoint_track_total (all)
#' @noRd
ckpt_files_baseline = function(tr, lim) {
  w = ckpt_walk(tr$root)
  tr$stat = w
  tr$walk_time = as.numeric(Sys.time())
  src = grepl(ckpt_source_re, w$path)
  cand = w[!w$link & w$size <= lim$track_file_max, , drop = FALSE]
  if (nrow(cand)) {
    o = order(!src[match(cand$path, w$path)], cand$size, method = "radix")
    cand = cand[o, , drop = FALSE]
    cand = cand[cumsum(cand$size) <= lim$track_total, , drop = FALSE]
    ckpt_ingest(tr, cand$path)
  }
  invisible(nrow(cand))
}

#' Walk and diff against the tracker's stat view (git's racy-clean rule: a tracked file with the
#' same size and mtime whose mtime lies within `racy` seconds of the last walk is hashed)
#' @noRd
ckpt_files_scan = function(tr, racy = 2) {
  w = ckpt_walk(tr$root)
  now = as.numeric(Sys.time())
  old = tr$stat
  if (is.null(old)) old = w[0L, , drop = FALSE]
  created = setdiff(w$path, old$path)
  deleted = setdiff(old$path, w$path)
  both = intersect(w$path, old$path)
  o = old[match(both, old$path), , drop = FALSE]
  n = w[match(both, w$path), , drop = FALSE]
  changed = both[which(o$size != n$size | o$mtime != n$mtime | o$link != n$link)]
  racy_p = both[which(!both %in% changed & !n$link & n$mtime >= tr$walk_time - racy &
                        both %in% names(tr$hash))]
  if (length(racy_p)) {
    hh = unname(hash_file(file.path(tr$root, racy_p)))
    changed = c(changed, racy_p[hh != tr$hash[racy_p]])
  }
  list(walk = w, time = now, created = created, deleted = deleted, modified = changed)
}

#' A files fragment row (JSON-safe)
#' @noRd
ckpt_file_row = function(path, abs, status, pre, post, mode, size, mtime, restorable, reason) {
  list(path = path, abs = abs, status = status, pre = pre, post = post,
       mode = ckpt_json_num(mode), post_size = ckpt_json_num(size),
       post_mtime = ckpt_json_num(mtime), restorable = restorable, reason = reason)
}

#' Fragment rows for changed relative paths; captures post-images and updates the tracker
#' @noRd
ckpt_files_rows = function(tr, walk, created, modified, deleted, lim) {
  paths = c(created, modified, deleted)
  status = rep(c("created", "modified", "deleted"),
               c(length(created), length(modified), length(deleted)))
  rows = vector("list", length(paths))
  for (i in seq_along(paths)) {
    p = paths[i]
    st = status[i]
    j = match(p, walk$path)
    link = !is.na(j) && isTRUE(walk$link[j])
    pre = if (st == "created") "" else ckpt_scalar(tr$hash[p], "")
    pre_mode = if (p %in% names(tr$mode)) tr$mode[[p]] else -1L
    size = if (st == "deleted") -1 else walk$size[j]
    mtime = if (st == "deleted") -1 else walk$mtime[j]
    post = ""
    if (st != "deleted" && !link && walk$size[j] <= lim$file_capture_max) {
      post = ckpt_ingest(tr, p)
    } else {
      tr$hash = tr$hash[names(tr$hash) != p]
    }
    restorable = TRUE
    reason = ""
    if (link) {
      restorable = FALSE
      reason = "symbolic link (never restored through)"
    } else if (st != "created" && !nzchar(pre)) {
      restorable = FALSE
      reason = "no pre-image (not tracked: over the size cap or outside the baseline)"
    }
    rows[[i]] = ckpt_file_row(p, FALSE, st, pre, post, pre_mode, size, mtime, restorable, reason)
  }
  rows
}

#' One mutating step: scan, record rows, update the tracker
#' @noRd
ckpt_files_step = function(tr, lim) {
  s = ckpt_files_scan(tr)
  rows = ckpt_files_rows(tr, s$walk, s$created, s$modified, s$deleted, lim)
  tr$stat = s$walk
  tr$walk_time = s$time
  rows
}

#' Bring the tracker up to date without recording anything: the baseline on first use, else a
#' scan that absorbs edits made outside gptr (they are never undone by a rewind)
#' @noRd
ckpt_files_sync = function(tr, lim) {
  if (is.null(tr$stat)) ckpt_files_baseline(tr, lim) else ckpt_files_step(tr, lim)
  invisible(tr)
}

#' Absolute paths a call is predicted to write: `input$path` of edit/write, literal paths of R
#' code (relative paths resolve against the working directory, where the code runs)
#' @noRd
ckpt_call_paths = function(call) {
  inp = call$input
  p = character()
  if (is.character(inp$path) && length(inp$path) == 1L) p = inp$path
  if (is.character(inp$code) && length(inp$code) == 1L) p = c(p, ckpt_predict(inp$code)$files)
  p = p[!is.na(p) & nzchar(p) & !grepl("^[A-Za-z][A-Za-z0-9+.-]*://", p) & !grepl("[*?]", p)]
  if (!length(p)) return(character())
  absolute = grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", p)
  full = ifelse(absolute, path.expand(p), file.path(getwd(), p))
  unique(path_norm(full))
}

#' State of a predicted path: its hash, "" when absent, "?" when present but not capturable
#' @noRd
ckpt_explicit_state = function(full, lim) {
  if (!file.exists(full) || dir.exists(full)) return("")
  if (!ckpt_capturable(full, lim)) return("?")
  ckpt_store_put(full)
}

#' Pre-capture predicted paths: tracked when the walk covers them, else explicit (absolute)
#' @noRd
ckpt_files_precapture = function(tr, paths, lim) {
  for (p in paths) {
    rel = ckpt_rel(tr$root, p)
    walked = !is.na(rel) && !grepl(ckpt_prune_re, rel) && !isTRUE(tr$per_turn)
    if (walked) {
      if (!rel %in% names(tr$hash) && ckpt_capturable(p, lim)) ckpt_ingest(tr, rel)
    } else {
      tr$explicit[p] = ckpt_explicit_state(p, lim)
      tr$explicit_mode[p] = if (file.exists(p)) ckpt_modes(p) else -1L
    }
  }
  invisible(paths)
}

#' Refresh the tracker's stat rows of relative paths, so that the next walk does not report them
#' @noRd
ckpt_stat_refresh = function(tr, rel) {
  if (is.null(tr$stat) || !length(rel)) return(invisible(NULL))
  full = file.path(tr$root, rel)
  info = file.info(full, extra_cols = FALSE)
  add = data.frame(path = rel, size = ifelse(is.na(info$size), 0, info$size),
                   mtime = ifelse(is.na(info$mtime), 0, as.numeric(info$mtime)),
                   link = ckpt_is_link(full), stringsAsFactors = FALSE)
  add = add[file.exists(full), , drop = FALSE]
  st = rbind(tr$stat[!tr$stat$path %in% rel, , drop = FALSE], add)
  tr$stat = st[order(st$path, method = "radix"), , drop = FALSE]
  invisible(NULL)
}

#' Rows for predicted paths outside the walk (or every predicted path in per-turn mode)
#' @noRd
ckpt_files_check_explicit = function(tr, paths, lim) {
  rows = list()
  for (p in intersect(paths, names(tr$explicit))) {
    before = tr$explicit[[p]]
    exists_now = file.exists(p) && !dir.exists(p)
    if (!exists_now && !nzchar(before)) next
    now = ckpt_explicit_state(p, lim)
    if (identical(now, before) || identical(before, "?")) next
    st = if (!nzchar(before)) "created" else if (!exists_now) "deleted" else "modified"
    link = exists_now && ckpt_is_link(p)
    mode = if (p %in% names(tr$explicit_mode)) tr$explicit_mode[[p]] else -1L
    rows[[length(rows) + 1L]] = ckpt_file_row(
      p, TRUE, st, if (st == "created") "" else before, if (identical(now, "?")) "" else now,
      mode, if (exists_now) file.size(p) else -1,
      if (exists_now) as.numeric(file.mtime(p)) else -1,
      !link, if (link) "symbolic link (never restored through)" else "")
    tr$explicit[p] = now
    rel = ckpt_rel(tr$root, p)
    if (!is.na(rel)) {
      if (nzchar(now) && !identical(now, "?")) tr$hash[rel] = now
      ckpt_stat_refresh(tr, rel)
    }
  }
  rows
}

#' Files checkpointer, before a mutating call: baseline (first call) or absorb outside edits
#' (never undone by a rewind), then pre-capture the predicted paths
#' @noRd
ckpt_files_before = function(ck, call, turn = 1L) {
  tr = ckpt_files_tr(ck)
  lim = ckpt_limits()
  if (is.null(tr$stat)) {
    ckpt_files_baseline(tr, lim)
  } else if (!isTRUE(tr$per_turn) || !identical(tr$scanned_turn, as.integer(turn))) {
    ckpt_files_step(tr, lim)
  }
  tr$scanned_turn = as.integer(turn)
  paths = ckpt_call_paths(call)
  ckpt_files_precapture(tr, paths, lim)
  list(frag = ckpt_frag_id(), turn = as.integer(turn), paths = paths)
}

#' Files checkpointer, after the call: walk (adaptive: switches to one scan per turn when a walk
#' takes longer than gptr.checkpoint_scan_budget) plus the predicted paths outside the walk
#' @return `list(id, turn, root, files = list(<row>))`, or NULL when nothing changed.
#' @noRd
ckpt_files_after = function(ck, call, token) {
  if (is.null(token)) return(NULL)
  tr = ckpt_files_tr(ck)
  lim = ckpt_limits()
  rows = list()
  if (!isTRUE(tr$per_turn)) {
    t0 = proc.time()[["elapsed"]]
    rows = ckpt_files_step(tr, lim)
    if (proc.time()[["elapsed"]] - t0 > lim$scan_budget) {
      tr$per_turn = TRUE
      gptr_inform(paste0("Checkpoint scans of ", tr$root, " take longer than ",
                         "gptr.checkpoint_scan_budget; gptr now scans once per turn plus the ",
                         "paths it can predict."), "notice", .once = paste0("ckpt-scan:", tr$root))
    }
  }
  rows = c(rows, ckpt_files_check_explicit(tr, token$paths, lim))
  if (!length(rows)) return(NULL)
  list(id = token$frag, turn = token$turn, root = tr$root, files = rows)
}

#' One full scan recorded as its own fragment: the end of a turn in per-turn mode, and the turns
#' of a CLI route whose child edits files itself (IC-65); NULL when nothing changed
#' @noRd
ckpt_files_turn_scan = function(ck, turn, force = FALSE) {
  tr = ckpt_files_tr(ck)
  if (is.null(tr$stat) || (!isTRUE(tr$per_turn) && !force)) return(NULL)
  rows = ckpt_files_step(tr, ckpt_limits())
  if (!length(rows)) return(NULL)
  list(id = ckpt_frag_id(), turn = as.integer(turn), root = tr$root, files = rows)
}

# ---- restores (G7 section 3.6; IC-52, IC-54) -----------------------------------------------------

#' tempdir(), where restores need no confirmation (a function, so tests can replace it)
#' @noRd
ckpt_temp_root = function() {
  tempdir()
}

#' Does any directory between the file system root and `full` resolve elsewhere, that is, would
#' a write to `full` go through a symbolic link?
#' @noRd
ckpt_through_link = function(full) {
  d = dirname(full)
  while (!dir.exists(d) && dirname(d) != d) d = dirname(d)
  real = normalizePath(d, winslash = "/", mustWork = FALSE)
  lex = sub("/+$", "", d)
  fold = .Platform$OS.type == "windows" || identical(Sys.info()[["sysname"]], "Darwin")
  if (fold) !identical(tolower(real), tolower(lex)) else !identical(real, lex)
}

#' May a restore write to `full`? Never through links, into .git or gptr's user directories;
#' outside the project root and tempdir(), and for control or critical paths, only after a human
#' confirms (`ask`, IC-52, IC-54). `root` is the current project root, never a root read from a
#' session file.
#' @return `list(ok, ask, reason)`.
#' @noRd
ckpt_restore_guard = function(full, root = project_root()) {
  if (isTRUE(ckpt_is_link(full)) || ckpt_through_link(full)) {
    return(list(ok = FALSE, ask = FALSE, reason = "symbolic link (never restored through)"))
  }
  if (grepl("(^|/)\\.git(/|$)", path_norm(full))) {
    return(list(ok = FALSE, ask = FALSE, reason = "inside .git (never restored)"))
  }
  for (w in c("config", "cache", "data")) {
    if (ckpt_within(full, gptr_user_dir(w))) {
      return(list(ok = FALSE, ask = FALSE,
                  reason = "inside gptr's user directory (never restored)"))
    }
  }
  inside = ckpt_within(full, root) || ckpt_within(full, ckpt_temp_root())
  sensitive = tryCatch(path_class(full, root) %in% c("control", "critical"),
                       error = function(e) TRUE)
  list(ok = TRUE, ask = !inside || isTRUE(sensitive), reason = "")
}

#' Ask a human to confirm one restore outside the project (an ask_human: only a UI backend whose
#' has_ui() is TRUE may answer; without one the file is not restored)
#' @noRd
ckpt_confirm_outside = function(full, session) {
  if (!isTRUE(gptr_can_prompt())) return(FALSE)
  ui = tryCatch(ext_service_get("ui.get")(session), error = function(e) NULL)
  if (is.null(ui) || !is.function(ui$has_ui) || !isTRUE(ui$has_ui())) return(FALSE)
  ans = tryCatch(
    ui$select(paste0("Restore ", full, "? It lies outside the project and tempdir(), or it ",
                     "configures R or gptr."),
              c("Restore this file", "Leave it as it is"), default = 2L),
    error = function(e) NA_integer_)
  identical(as.integer(ans), 1L)
}

#' Current state of a file: exists, hash, size, mtime
#' @noRd
ckpt_file_state = function(full) {
  if (!file.exists(full) || dir.exists(full)) {
    return(list(exists = FALSE, hash = "", size = -1, mtime = -1))
  }
  list(exists = TRUE, hash = unname(hash_file(full)), size = file.size(full),
       mtime = as.numeric(file.mtime(full)))
}

#' Absolute path of a fragment row
#' @noRd
ckpt_row_full = function(row, root) {
  p = ckpt_scalar(row$path)
  if (isTRUE(row$abs)) p else file.path(root, p)
}

#' Set a restored file's mode bits (Unix; on Windows only read-only is honoured)
#' @noRd
ckpt_chmod = function(full, mode) {
  m = ckpt_num(mode)
  if (!is.na(m)) Sys.chmod(full, as.octmode(as.integer(m)), use_umask = FALSE)
  invisible(full)
}

#' Keep the tracker in step with a restore (hash "" means the file is gone)
#' @noRd
ckpt_files_note = function(tr, row, hash) {
  p = ckpt_scalar(row$path)
  if (isTRUE(row$abs)) {
    tr$explicit[p] = hash
    return(invisible(NULL))
  }
  if (nzchar(hash)) tr$hash[p] = hash else tr$hash = tr$hash[names(tr$hash) != p]
  if (!is.null(tr$stat)) tr$stat = tr$stat[tr$stat$path != p, , drop = FALSE]
  if (nzchar(hash)) ckpt_stat_refresh(tr, p)
  invisible(NULL)
}

#' Undo one files fragment, newest row first (3-way rule: a file is restored only while its
#' content is still what the call left; the user's later edits win unless `force = TRUE`)
#' @noRd
ckpt_files_undo = function(ck, fragment, session = NULL, force = FALSE, dry = FALSE,
                           turn_now = NA_integer_) {
  tr = ckpt_files_tr(ck)
  root = ckpt_scalar(fragment$root, tr$root)
  lim = ckpt_limits()
  ft = ckpt_num(fragment$turn)
  too_old = !is.na(turn_now) && !is.na(ft) && ft <= turn_now - lim$file_turns
  out = ckpt_items()
  rows = fragment$files
  for (i in rev(seq_along(rows))) {
    r = rows[[i]]
    full = ckpt_row_full(r, root)
    item = paste("file", ckpt_scalar(r$path))
    status = ckpt_scalar(r$status)
    post = ckpt_scalar(r$post)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not restored (", ckpt_scalar(r$reason), ")"))
      next
    }
    if (too_old) {
      out = ckpt_item(out, item, FALSE, "not restored (older than gptr.checkpoint_turns turns)")
      next
    }
    g = ckpt_restore_guard(full)
    if (!g$ok) {
      out = ckpt_item(out, item, FALSE, paste0("not restored (", g$reason, ")"))
      next
    }
    cur = ckpt_file_state(full)
    expect_ok = if (status == "deleted") {
      !cur$exists
    } else if (nzchar(post)) {
      identical(cur$hash, post)
    } else {
      cur$exists && isTRUE(cur$size == ckpt_num(r$post_size)) &&
        isTRUE(abs(cur$mtime - ckpt_num(r$post_mtime)) < 1e-3)
    }
    if (!expect_ok && !force) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
      next
    }
    if (g$ask && dry) {
      out = ckpt_item(out, item, NA, "needs confirmation (outside the project and tempdir())")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be restored")
      next
    }
    if (g$ask && !ckpt_confirm_outside(full, session)) {
      out = ckpt_item(out, item, FALSE,
                      "not restored (outside the project and tempdir(); not confirmed)")
      next
    }
    if (status == "created") {
      if (cur$exists) unlink(full)
      ckpt_files_note(tr, r, "")
      out = ckpt_item(out, item, TRUE, "removed (created by the turn)")
    } else {
      pre = ckpt_scalar(r$pre)
      ok = ckpt_store_get(pre, full)
      if (ok) {
        ckpt_chmod(full, r$mode)
        ckpt_files_note(tr, r, pre)
      }
      out = ckpt_item(out, item, ok,
                      if (ok) "restored" else "not restored (the stored copy is missing)")
    }
  }
  out
}

#' Redo one files fragment, oldest row first
#' @noRd
ckpt_files_redo = function(ck, fragment, session = NULL, force = FALSE, dry = FALSE) {
  tr = ckpt_files_tr(ck)
  root = ckpt_scalar(fragment$root, tr$root)
  out = ckpt_items()
  for (r in fragment$files) {
    full = ckpt_row_full(r, root)
    item = paste("file", ckpt_scalar(r$path))
    status = ckpt_scalar(r$status)
    pre = ckpt_scalar(r$pre)
    post = ckpt_scalar(r$post)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not redone (", ckpt_scalar(r$reason), ")"))
      next
    }
    g = ckpt_restore_guard(full)
    if (!g$ok) {
      out = ckpt_item(out, item, FALSE, paste0("not redone (", g$reason, ")"))
      next
    }
    cur = ckpt_file_state(full)
    expect_ok = if (status == "created") !cur$exists else nzchar(pre) && identical(cur$hash, pre)
    if (!expect_ok && !force) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the undo (kept current)")
      next
    }
    if (status != "deleted" && !nzchar(post)) {
      out = ckpt_item(out, item, FALSE, "not redone (no stored copy of the new content)")
      next
    }
    if (g$ask && dry) {
      out = ckpt_item(out, item, NA, "needs confirmation (outside the project and tempdir())")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be redone")
      next
    }
    if (g$ask && !ckpt_confirm_outside(full, session)) {
      out = ckpt_item(out, item, FALSE,
                      "not redone (outside the project and tempdir(); not confirmed)")
      next
    }
    if (status == "deleted") {
      if (cur$exists) unlink(full)
      ckpt_files_note(tr, r, "")
      out = ckpt_item(out, item, TRUE, "deleted again")
    } else {
      ok = ckpt_store_get(post, full)
      if (ok) ckpt_files_note(tr, r, post)
      out = ckpt_item(out, item, ok,
                      if (ok) "redone" else "not redone (the stored copy is missing)")
    }
  }
  out
}

#' One line per file of a fragment
#' @noRd
ckpt_files_describe = function(fragment) {
  vapply(fragment$files, function(r) {
    paste0("file ", ckpt_scalar(r$path), ": ", ckpt_scalar(r$status),
           if (isTRUE(r$restorable)) "" else " (not restorable)")
  }, "")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-files")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]` (on Windows the two symbolic-link tests skip).

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-files.R tests/testthat/test-ckpt-files.R
git commit -m "feat(ckpt): add the files checkpointer with guarded 3-way restores"
```

### Task 6: `builtin:checkpoints`: specs, hooks, the rewind block and the `checkpoint` event

**Files:**
- Create: `R/ckpt-rewind.R`
- Test: `tests/testthat/test-ckpt-rewind.R` (create)

**Interfaces:**
- Consumes: Tasks 1-5; P01 `on_load(expr)`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `setting_get()`, `est_tokens(x, class)`, `block_text()`, `ev_new(type, ...)`; P02 `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `gptr_spec("checkpointer", ...)`, `gptr_context_block(name, provide, placement, authority, budget, order)`, `registry_all(kind, session = NULL)`, `registry_get(kind, name, session = NULL)`, `ev_dispatch(event, payload, session = NULL, ctx = NULL)`, the factory API (`gptr$state`, `gptr$register()`, `gptr$on()`), `ctx$session`, `ctx$envir`, `ctx$run`, `ctx$mode()`; P06 `session_data(s)` (`id`, `turns`, `model`, `index`, `entries`), `session_home(s)`, `session_append(s, entry)`, the dispatcher's checkpointer calls and the `gptr.checkpoint` container `{tool_call_id, fragments}` (P06 `checkpoint_after()`), the payloads of `tool_result` (`tool_call_id`, `content`, `details`), `agent_start`, `turn_end`, `agent_end`, `session_shutdown` (`session`); tests: P08 `peter()`, P02 `gptr_register()`, `gptr_hook()`, `gptr_registry()`, P01 `local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_project()`, `local_gptr_options()`, `msg_text()`.
- Produces: `builtin_checkpoints(gptr)` declared as `builtin:checkpoints` (04 §7.16, §10.3) and the service `checkpoint.note` (owned by `builtin:checkpoints`, IC-34); `ckpt_ck_of(st, s, create = TRUE)`, `ckpt_turn(s)`, `ckpt_setting(s = NULL)`, `ckpt_pure_read(call)`, `ckpt_enabled(s, name, ctx, call)`, `ckpt_cli_session(s)`, `ckpt_spec(st, name)` (with `preview()` and `ckpt_state`), `ckpt_cp_apply(st, name, direction, fragment, ctx, force, dry)`, `ckpt_append_scan(s, frag)`, `ckpt_emit_checkpoint(s, ctx, event)`, the hook functions `ckpt_on_tool_result()`, `ckpt_on_agent_start()`, `ckpt_on_turn_end()`, `ckpt_on_agent_end()`, `ckpt_on_shutdown()`, `ckpt_rewind_lines(report)`, `ckpt_rewind_block(st, ctx, budget)`, `ckpt_ext_state(s)`, `ckpt_specs(s)`; the event `checkpoint` (04 §10.4).

The dispatcher of P06 calls every `checkpointer` record's `before(call, ctx)` after the gate and `after(call, ctx, token)` after the tool, for sequential tools that are not read-only, and writes one `gptr.checkpoint` entry `{tool_call_id, fragments: {objects, files, state}}` before the tool's result message, setting `details$checkpoint` to its id. The per-session state of the three built-ins lives in the extension's private `gptr$state` under `rlang::new_weakref(key = <session shell>, value = <state>)` (shells hold no frames or user objects, rule R10); when the shell is collected the state's finalizer defuses its images (G7 c06b), and `session_shutdown` releases them at once. Objects are captured only when the call evaluates in the session's kept home (`ctx$envir` identical to `session_home(s)`): never a function-frame home (R2), never the plan-mode scratch overlay or an inline sub-agent overlay. Plan mode and `options(gptr.checkpoint = "off")` record nothing; `"files"` records files only; only pure reads are skipped: an R call the classifier rated level 0 (`call$risk$level`) whose code has no target in `ckpt_predict()` (no binding assigned, modified, removed or super-assigned, no file, no process, nothing unknown). A level-0 call that only creates a binding (`y = 2`: no existing object is overwritten, so P11 rates it 0) is checkpointed, so a rewind removes what it created (G7 section 3.4 step 5, section 4.1: every tool that is not `read_only`). The `tool_result` hook appends the G7 section 3.9 notices to the result the model sees and emits the `checkpoint` event with the counts of the entry named in `details$checkpoint`. On a subscription-CLI route (a provider record of type `cli`, IC-65) the `agent_start` hook brings the file tracker up to date and the `turn_end` hook walks after every turn, so `/undo` covers what the CLI child edited itself; the scan becomes its own `gptr.checkpoint` entry with `tool_call_id = "scan-<fragment id>"`. The `agent_end` hook runs the per-turn scan of adaptive mode, the turn-end memory budget and one blob collection per session. The `workspace_changes` context block (placement `both`, order 101, budget 300; next to P09's own `workspace_changes` block at order 100, which the `all`-resolving `context_block` kind keeps) renders the rewind note of Task 7 once, as G7 section 3.9's `<workspace_changes since="turn 1" reason="rewind">`; it returns `NULL` otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-ckpt-rewind.R`:

```r
# tests/testthat/test-ckpt-rewind.R -- builtin:checkpoints, gptr_rewind(), gptr_checkpoints() and
# the commands (P16). Model behaviour comes from the fake provider (contract section 12).

entries_of = function(s, custom_type) {
  Filter(function(e) identical(e$custom_type, custom_type), session_data(s)$entries)
}

tool_results_of = function(s) {
  Filter(function(e) identical(e$type, "message") && identical(e$message$role, "tool_result"),
         session_data(s)$entries)
}

test_that("builtin:checkpoints registers three checkpointers, the block and checkpoint.note", {
  reg = gptr_registry(c("checkpointer", "context_block"))
  mine = reg[reg$source == "builtin:checkpoints", , drop = FALSE]
  expect_setequal(mine$name[mine$kind == "checkpointer"], c("objects", "files", "state"))
  expect_true("workspace_changes" %in% mine$name[mine$kind == "context_block"])
  expect_true(ext_service_has("checkpoint.note"))
  expect_true(is.function(ext_service_get("checkpoint.note")))
})

test_that("a mutating r call appends one gptr.checkpoint entry that never holds values", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 'SENTINEL-7f3a'; writeLines('a', 'a.txt')"),
                           "done"))
  e = new.env()
  s = peter("make x", model = "fake/fake-1", mode = "auto", envir = e)
  expect_identical(e$x, "SENTINEL-7f3a")
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  frags = cps[[1L]]$data$fragments
  expect_identical(vapply(frags$objects$objects, function(r) r$name, ""), "x")
  expect_identical(vapply(frags$files$files, function(r) r$path, ""), "a.txt")
  expect_identical(tool_results_of(s)[[1L]]$message$details$checkpoint, cps[[1L]]$id)
  lines = readLines(s$file, encoding = "UTF-8")
  cp_lines = lines[grepl("\"gptr.checkpoint\"", lines, fixed = TRUE)]
  expect_length(cp_lines, 1L)
  expect_false(grepl("SENTINEL-7f3a", cp_lines, fixed = TRUE))
})

test_that("an object changed without an undo copy adds a notice to the tool result (G7 3.9)", {
  local_project()
  local_gptr_options(undo_capture_max = 10, undo_max_bytes = 10, undo_spill_max = 10)
  fake = local_fake_provider(list(fake_tool("r", code = "big[1] = 0"), "ok"))
  e = new.env()
  e$big = as.numeric(1:100)
  peter("edit big", model = "fake/fake-1", mode = "auto", envir = e)
  txt = msg_text(fake_requests(fake)[[2L]]$last_results[[1L]])
  expect_match(txt, "note: big \\([0-9]+ B\\) was (modified|overwritten) without an undo copy")
})

test_that("the checkpoint event reports counts (contract 10.4)", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1; writeLines('a', 'a.txt')"), "done"))
  seen = new.env()
  off = gptr_register(gptr_hook("checkpoint", function(event, ctx) {
    seen$ev = event
    NULL
  }))
  withr::defer(off())
  peter("make x", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_identical(as.integer(seen$ev$objects), 1L)
  expect_identical(as.integer(seen$ev$files), 1L)
  expect_identical(as.integer(seen$ev$restorable), 2L)
  expect_true(nzchar(seen$ev$tool_call_id))
})

test_that("checkpoint = 'off' records nothing, 'files' records files only, plan mode nothing", {
  local_project()
  step = list(fake_tool("r", code = "y = 2; writeLines('b', 'b.txt')"), "ok")
  local_fake_provider(c(step, step, step))
  local_gptr_options(checkpoint = "off")
  s = peter("off", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_length(entries_of(s, "gptr.checkpoint"), 0L)
  local_gptr_options(checkpoint = "files")
  s = peter("files", model = "fake/fake-1", mode = "auto", envir = new.env())
  frags = entries_of(s, "gptr.checkpoint")[[1L]]$data$fragments
  expect_null(frags$objects)
  expect_false(is.null(frags$files))
  local_gptr_options(checkpoint = "on")
  s = peter("plan", model = "fake/fake-1", mode = "plan", envir = new.env())
  expect_length(entries_of(s, "gptr.checkpoint"), 0L)
})

test_that("only pure reads skip the checkpointers; a level-0 creation is checkpointed", {
  local_project()
  read = list(name = "r", input = list(code = "length(letters)"), risk = list(level = 0L))
  expect_true(ckpt_pure_read(read))
  expect_false(ckpt_pure_read(list(name = "r", input = list(code = "y = 2"),
                                   risk = list(level = 0L))))
  expect_false(ckpt_pure_read(list(name = "r", input = list(code = "length(letters)"),
                                   risk = list(level = 2L))))
  expect_false(ckpt_pure_read(list(name = "write", input = list(path = "a.R"),
                                   risk = list(level = 0L))))
  local_fake_provider(list(fake_tool("r", code = "y = 2"), "made y",
                           fake_tool("r", code = "length(letters)"), "counted"))
  e = new.env()
  s = peter("make y", model = "fake/fake-1", mode = "auto", envir = e)
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  expect_identical(vapply(cps[[1L]]$data$fragments$objects$objects, function(r) r$status, ""),
                   "created")
  s |> peter("count letters")
  expect_length(entries_of(s, "gptr.checkpoint"), 1L)
})

test_that("a session's state is found by its shell and released at session_shutdown", {
  local_project()
  local_fake_provider(list("hello"))
  st = new.env(parent = emptyenv())
  st$sessions = new.env(parent = emptyenv())
  s = peter("hi", model = "fake/fake-1", envir = new.env())
  ck = ckpt_ck_of(st, s)
  expect_identical(ckpt_ck_of(st, s, create = FALSE), ck)
  e = new.env()
  e$x = as.numeric(1:10)
  ckpt_capture(ck$obj, e, "x")
  expect_length(ls(ck$obj$slots), 1L)
  ckpt_on_shutdown(st, list(session = session_data(s)$id), NULL)
  expect_length(ls(ck$obj$slots), 0L)
  expect_null(ckpt_ck_of(st, s, create = FALSE))
})

test_that("on a CLI route the files the child changes during a turn are checkpointed (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
  local_fake_provider(function(request) {
    writeLines("a = 2", file.path(proj, "R", "a.R"))
    "Codex edited R/a.R"
  })
  s = peter("edit a", model = "fake/fake-1", mode = "auto", envir = new.env())
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  row = cps[[1L]]$data$fragments$files$files[[1L]]
  expect_identical(row$path, "R/a.R")
  expect_identical(row$status, "modified")
  expect_true(row$restorable)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind")'`

Expected: failures, among them `mine$name[mine$kind == "checkpointer"]` being empty, `ext_service_has("checkpoint.note")` being `FALSE`, `expect_length(cps, 1L)` seeing 0 entries, `could not find function "ckpt_ck_of"` and `"ckpt_pure_read"`, and a `local_mocked_bindings()` error for `ckpt_cli_session`; the summary reads about `[ FAIL 17 | WARN 0 | SKIP 0 | PASS 2 ]` (the exact count depends on how many expectations fail before each test's first error).

- [ ] **Step 3: Write the implementation**

Create `R/ckpt-rewind.R`:

```r
# ckpt-rewind.R -- builtin:checkpoints, gptr_rewind(), gptr_checkpoints() and the /undo, /redo,
# /rewind and /checkpoints commands (P16, layer L4).
#
# The dispatcher (P06) calls every `checkpointer` record's before() and after() around each
# sequential, non-read-only tool call and appends one `gptr.checkpoint` custom entry
# `{tool_call_id, fragments: {<checkpointer>: <fragment>}}` before the tool's result message
# (contract 10.2 row 29, 4.6). builtin:checkpoints registers the checkpointers `objects`, `files`
# and `state`; their per-session state (pre-image store, file tracker, state values, notices)
# lives in this extension's private state (the factory API's `gptr$state`) under a weak
# reference keyed on the session shell, so a dropped session releases its images
# (ckpt_ck_finalize(), G7 c06b). gptr_rewind() is G7's branch-in-place on the one session object
# (G7 sections 3.2, 3.6, 4.2-4.3; contract 6.5): it undoes the records between the leaf and the
# lowest common ancestor (newest first), redoes those between that ancestor and the target
# (oldest first), appends one `gptr.rewind` entry parented at the target (the durable leaf; the
# JSONL stays append-only) and returns the session invisibly. Adapted from G7 p5/ckpt_session.R.

on_load(ext_declare_builtin("checkpoints", builtin_checkpoints))
on_load(ext_service_set("checkpoint.note", ckpt_note, provided_by = "P16",
                        builtin = "checkpoints"))

# ---- per-session state ---------------------------------------------------------------------------

#' The checkpoint state of session `s` in the extension state `st` (created on demand)
#'
#' Held under `rlang::new_weakref(key = <shell>, value = <state>)`: while the shell lives its
#' state lives; when it is collected the state becomes unreachable and its finalizer defuses the
#' images. A shell holds no frames or user objects, so the weak key is copy-safe (rule R10). A
#' different shell with the same id (a detached copy) gets a state of its own that is not
#' registered.
#' @noRd
ckpt_ck_of = function(st, s, create = TRUE) {
  if (!is.environment(st) || !inherits(s, "gptr_session")) return(NULL)
  sid = session_data(s)$id
  w = get0(sid, envir = st$sessions, inherits = FALSE)
  k = if (is.null(w)) NULL else rlang::wref_key(w)
  if (!is.null(k) && identical(k, s)) return(rlang::wref_value(w))
  if (!create) return(NULL)
  spill = if (ckpt_spill_allowed()) file.path(ckpt_store_root(), "objects", sid) else NULL
  ck = ckpt_ck_new(sid, spill)
  if (is.null(k)) assign(sid, rlang::new_weakref(key = s, value = ck), envir = st$sessions)
  ck
}

#' The current prompt turn of a session (at least 1)
#' @noRd
ckpt_turn = function(s) {
  t = suppressWarnings(as.integer(session_data(s)$turns))
  if (!length(t) || is.na(t) || t < 1L) 1L else t
}

#' The `checkpoint` setting: "on", "files" or "off" (contract 3.1, 11.2)
#' @noRd
ckpt_setting = function(s = NULL) {
  sid = if (inherits(s, "gptr_session")) session_data(s)$id else NULL
  ckpt_scalar(setting_get("checkpoint", session = sid, default = "on"), "on")
}

#' Is a call a pure read: R code the classifier rated level 0 (known read-only) that binds,
#' modifies, removes or writes nothing (no target of ckpt_predict())? A level-0 call that creates
#' a binding (`y = 2`) is not pure: a rewind must remove what it created (G7 section 3.4 step 5)
#' @noRd
ckpt_pure_read = function(call) {
  level = if (is.list(call$risk)) suppressWarnings(as.integer(call$risk$level)[1L]) else NA
  code = call$input$code
  if (!identical(level, 0L) || !is.character(code) || length(code) != 1L || is.na(code)) {
    return(FALSE)
  }
  tg = ckpt_predict(code)
  !length(c(tg$assign, tg$modify, tg$byref, tg$remove, tg$super, tg$files, tg$unknown,
            tg$process))
}

#' Does checkpointer `name` run for this call? Not when the setting excludes it, not in plan mode
#' (conversation only, G7 section 4.5), not for a pure read (ckpt_pure_read())
#' @noRd
ckpt_enabled = function(s, name, ctx, call) {
  mode = ckpt_setting(s)
  if (identical(mode, "off")) return(FALSE)
  if (identical(mode, "files") && !identical(name, "files")) return(FALSE)
  m = tryCatch(ctx$mode(), error = function(e) NULL)
  if (identical(m, "plan")) return(FALSE)
  !ckpt_pure_read(call)
}

#' Does the session run on a subscription-CLI route whose child edits files itself (a provider
#' record of type "cli", IC-65)?
#' @noRd
ckpt_cli_session = function(s) {
  id = sub("/.*$", "", ckpt_scalar(session_data(s)$model, ""))
  if (!nzchar(id)) return(FALSE)
  p = tryCatch(registry_get("provider", id), error = function(e) NULL)
  identical(ckpt_scalar(p$type, ""), "cli")
}

# ---- the checkpointer specs (contract 10.2 row 29) ---------------------------------------------

#' A checkpointer's before(): its own capture, or NULL when it does not apply. Objects are
#' captured only when the call evaluates in the session's kept home (never a function frame,
#' rule R2; never a plan-mode or sub-agent overlay)
#' @noRd
ckpt_cp_before = function(st, name, call, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || !ckpt_enabled(s, name, ctx, call)) return(NULL)
  ck = ckpt_ck_of(st, s)
  turn = ckpt_turn(s)
  switch(name,
    objects = {
      envir = ctx$envir
      home = session_home(s)
      if (is.null(home) || !identical(home, envir)) return(NULL)
      ckpt_objects_before(ck, call, envir, turn)
    },
    files = ckpt_files_before(ck, call, turn),
    state = ckpt_state_before(ck, call, turn),
    NULL)
}

#' A checkpointer's after(): the JSON-able fragment, or NULL; objects notices are kept until the
#' tool_result hook appends them to the result
#' @noRd
ckpt_cp_after = function(st, name, call, ctx, token) {
  if (is.null(token)) return(NULL)
  ck = ckpt_ck_of(st, ctx$session, create = FALSE)
  if (is.null(ck)) return(NULL)
  frag = switch(name,
    objects = ckpt_objects_after(ck, call, ctx$envir, token),
    files = ckpt_files_after(ck, call, token),
    state = ckpt_state_after(ck, call, token),
    NULL)
  if (identical(name, "objects") && !is.null(frag)) {
    notes = ckpt_objects_notes(frag)
    if (length(notes)) assign(ckpt_scalar(call$id, "call"), notes, envir = ck$notes)
  }
  frag
}

#' Undo, redo or preview one fragment with a built-in checkpointer (an item table)
#' @noRd
ckpt_cp_apply = function(st, name, direction, fragment, ctx, force, dry) {
  if (isFALSE(fragment$restorable) && is.null(fragment$id)) {
    return(ckpt_item(ckpt_items(), paste("checkpointer", name), FALSE,
                     paste0("not restored (the checkpoint failed: ",
                            ckpt_scalar(fragment$reason, "unknown error"), ")")))
  }
  s = ctx$session
  ck = ckpt_ck_of(st, s)
  undo = identical(direction, "undo")
  switch(name,
    objects = {
      envir = session_home(s)
      if (is.null(envir)) {
        ckpt_item(ckpt_items(), "objects", FALSE,
                  paste0("not restored (the session keeps no workspace: its calls ran in a ",
                         "function frame)"))
      } else if (undo) {
        ckpt_objects_undo(ck, fragment, envir, force, dry)
      } else {
        ckpt_objects_redo(ck, fragment, envir, force, dry)
      }
    },
    files = if (undo) {
      ckpt_files_undo(ck, fragment, s, force, dry, turn_now = ckpt_turn(s))
    } else {
      ckpt_files_redo(ck, fragment, s, force, dry)
    },
    state = if (undo) {
      ckpt_state_undo(ck, fragment, force, dry)
    } else {
      ckpt_state_redo(ck, fragment, force, dry)
    },
    ckpt_items())
}

#' A checkpointer's prune(): blob garbage collection (files), the memory budget (objects)
#' @noRd
ckpt_cp_prune = function(st, name, live_keys, ctx) {
  if (identical(name, "files")) ckpt_gc()
  if (identical(name, "objects")) {
    s = ctx$session
    ck = ckpt_ck_of(st, s, create = FALSE)
    if (!is.null(ck)) ckpt_objects_budget(ck, ckpt_turn(s))
  }
  invisible(NULL)
}

#' A checkpointer's describe(): one line per item
#' @noRd
ckpt_describe = function(name, fragment) {
  if (isFALSE(fragment$restorable) && is.null(fragment$id)) {
    return(paste0(name, ": checkpoint failed"))
  }
  switch(name,
    objects = ckpt_objects_describe(fragment),
    files = ckpt_files_describe(fragment),
    state = ckpt_state_describe(fragment),
    character())
}

#' The checkpointer spec of one built-in checkpointer (closures over the extension state)
#'
#' Besides the contract fields it carries `preview(fragment, ctx, force, direction)` (a dry run:
#' an item table) and `ckpt_state` (the extension state, found by gptr_rewind() through the
#' registry); validators keep unknown fields (contract 10.2).
#' @noRd
ckpt_spec = function(st, name) {
  force(st)
  force(name)
  gptr_spec("checkpointer", name, scope = name,
    before = function(call, ctx) ckpt_cp_before(st, name, call, ctx),
    after = function(call, ctx, token) ckpt_cp_after(st, name, call, ctx, token),
    undo = function(fragment, ctx, force) {
      ckpt_lines(ckpt_cp_apply(st, name, "undo", fragment, ctx, force, FALSE))
    },
    redo = function(fragment, ctx, force) {
      ckpt_lines(ckpt_cp_apply(st, name, "redo", fragment, ctx, force, FALSE))
    },
    prune = function(live_keys, ctx) ckpt_cp_prune(st, name, live_keys, ctx),
    describe = function(fragment) ckpt_describe(name, fragment),
    preview = function(fragment, ctx, force, direction) {
      ckpt_cp_apply(st, name, direction, fragment, ctx, force, TRUE)
    },
    ckpt_state = st)
}

# ---- hooks and the rewind context block --------------------------------------------------------

#' Append a scan fragment as its own `gptr.checkpoint` entry (the container P06 writes)
#' @noRd
ckpt_append_scan = function(s, frag) {
  session_append(s, list(type = "custom", custom_type = "gptr.checkpoint",
                         data = list(tool_call_id = paste0("scan-", frag$id),
                                     fragments = list(files = frag))))
}

#' Emit the `checkpoint` event (contract 10.4: tool_call_id, objects, files, restorable counts)
#' for the gptr.checkpoint entry named in a tool result's details
#' @noRd
ckpt_emit_checkpoint = function(s, ctx, event) {
  id = ckpt_scalar(event$details$checkpoint, "")
  if (!nzchar(id)) return(invisible(NULL))
  d = session_data(s)
  pos = get0(id, envir = d$index, inherits = FALSE)
  if (is.null(pos)) return(invisible(NULL))
  frags = d$entries[[pos]]$data$fragments
  rows = c(frags$objects$objects %||% list(), frags$files$files %||% list())
  ok = sum(vapply(rows, function(r) isTRUE(r$restorable), NA))
  ev_dispatch("checkpoint",
              ev_new("checkpoint", session = d$id, run = ctx$run, turn = d$turns,
                     tool_call_id = ckpt_scalar(event$tool_call_id, ""),
                     objects = length(frags$objects$objects %||% list()),
                     files = length(frags$files$files %||% list()), restorable = ok),
              session = s, ctx = ctx)
  invisible(NULL)
}

#' tool_result hook: emit the checkpoint event, and append the notices of objects changed
#' without an undo copy to the result the model sees (G7 3.9)
#' @noRd
ckpt_on_tool_result = function(st, event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session")) return(NULL)
  tryCatch(ckpt_emit_checkpoint(s, ctx, event), error = function(e) NULL)
  ck = ckpt_ck_of(st, s, create = FALSE)
  id = ckpt_scalar(event$tool_call_id, "")
  if (is.null(ck) || !nzchar(id) || !exists(id, envir = ck$notes, inherits = FALSE)) return(NULL)
  notes = get(id, envir = ck$notes, inherits = FALSE)
  rm(list = id, envir = ck$notes)
  list(content = c(event$content, list(block_text(paste(notes, collapse = "\n")))))
}

#' agent_start hook: on a CLI route, bring the file tracker up to date before the child acts
#' @noRd
ckpt_on_agent_start = function(st, event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || !ckpt_cli_session(s)) return(NULL)
  if (!ckpt_enabled(s, "files", ctx, list())) return(NULL)
  ck = ckpt_ck_of(st, s)
  tryCatch(ckpt_files_sync(ckpt_files_tr(ck), ckpt_limits()), error = function(e) NULL)
  NULL
}

#' turn_end hook: on a CLI route, walk after the turn so /undo covers the files the CLI child
#' changed itself (a Codex workspace-write exec, IC-65)
#' @noRd
ckpt_on_turn_end = function(st, event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || !ckpt_cli_session(s)) return(NULL)
  if (!ckpt_enabled(s, "files", ctx, list())) return(NULL)
  ck = ckpt_ck_of(st, s)
  frag = tryCatch(ckpt_files_turn_scan(ck, ckpt_turn(s), force = TRUE), error = function(e) NULL)
  if (!is.null(frag)) ckpt_append_scan(s, frag)
  NULL
}

#' agent_end hook: the per-turn scan (adaptive mode), the memory budget, one blob collection
#' per session
#' @noRd
ckpt_on_agent_end = function(st, event, ctx) {
  s = ctx$session
  ck = ckpt_ck_of(st, s, create = FALSE)
  if (is.null(ck)) return(NULL)
  turn = ckpt_turn(s)
  frag = tryCatch(ckpt_files_turn_scan(ck, turn), error = function(e) NULL)
  if (!is.null(frag)) ckpt_append_scan(s, frag)
  ckpt_objects_budget(ck, turn)
  if (!isTRUE(ck$gc_done)) {
    ck$gc_done = TRUE
    tryCatch(ckpt_gc(), error = function(e) NULL)
  }
  NULL
}

#' session_shutdown hook: release the session's in-memory images now (reason "unload"); after a
#' collection the weak reference is already empty and the state's finalizer does it
#' @noRd
ckpt_on_shutdown = function(st, event, ctx) {
  sid = ckpt_scalar(event$session, "")
  w = if (nzchar(sid)) get0(sid, envir = st$sessions, inherits = FALSE) else NULL
  if (is.null(w)) return(NULL)
  ck = rlang::wref_value(w)
  if (is.environment(ck)) ckpt_ck_finalize(ck)
  rm(list = sid, envir = st$sessions)
  NULL
}

#' Lines of the rewind block from the report lines of items that were not restored
#' (`~ <object> (<why>)`, `file <path> (<why>)`, other items as reported)
#' @noRd
ckpt_rewind_lines = function(report) {
  out = sub("^object (.*?): ((not |conflict|needs ).*)$", "~ \\1 (\\2)", report, perl = TRUE)
  sub("^file (.*?): ((not |conflict|needs ).*)$", "file \\1 (\\2)", out, perl = TRUE)
}

#' The rewind context block: after a partial rewind, once, a
#' `<workspace_changes since="turn 3" reason="rewind">` block listing what was not restored
#' (G7 section 3.9; contract 4.1.1 attrs `since`, `reason`)
#' @noRd
ckpt_rewind_block = function(st, ctx, budget) {
  ck = ckpt_ck_of(st, ctx$session, create = FALSE)
  if (is.null(ck) || !length(ck$rewind_note)) return(NULL)
  lines = utils::head(ckpt_rewind_lines(ck$rewind_note), 12L)
  # sent once; a gptr_prompt() preview (ctx$input$preview, P07) does not consume it
  if (!isTRUE(ctx$input$preview)) ck$rewind_note = NULL
  while (length(lines) > 1L && est_tokens(paste(lines, collapse = "\n"), "prose") > budget) {
    lines = lines[-length(lines)]
  }
  list(text = paste(lines, collapse = "\n"),
       attrs = list(since = ck$rewind_since, reason = "rewind"))
}

#' builtin:checkpoints (contract 7.16, 10.3): the checkpointers `objects`, `files` and `state`,
#' the hooks above and the rewind `workspace_changes` context block; the service
#' `checkpoint.note` is declared at the top of this file
#' @noRd
builtin_checkpoints = function(gptr) {
  st = gptr$state
  st$sessions = new.env(parent = emptyenv())
  for (nm in c("objects", "files", "state")) gptr$register(ckpt_spec(st, nm))
  gptr$on("tool_result", function(event, ctx) ckpt_on_tool_result(st, event, ctx))
  gptr$on("agent_start", function(event, ctx) ckpt_on_agent_start(st, event, ctx))
  gptr$on("turn_end", function(event, ctx) ckpt_on_turn_end(st, event, ctx))
  gptr$on("agent_end", function(event, ctx) ckpt_on_agent_end(st, event, ctx))
  gptr$on("session_shutdown", function(event, ctx) ckpt_on_shutdown(st, event, ctx))
  gptr$register(gptr_context_block("workspace_changes", function(ctx, budget) {
    ckpt_rewind_block(st, ctx, budget)
  }, placement = "both", budget = 300L, order = 101L))
  invisible(NULL)
}

#' The extension state of builtin:checkpoints, found through the registry (NULL when the
#' built-in is filtered out)
#' @noRd
ckpt_ext_state = function(s) {
  for (sp in ckpt_specs(s)) {
    if (is.environment(sp$ckpt_state)) return(sp$ckpt_state)
  }
  NULL
}

#' Every registered checkpointer spec for a session (built-in and plugin ones), registry order
#' @noRd
ckpt_specs = function(s) {
  specs = tryCatch(registry_all("checkpointer", session = session_data(s)$id),
                   error = function(e) list())
  Filter(function(sp) is.list(sp) && is.character(sp$name) && is.function(sp$undo), specs)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 35 ]`.

Run the earlier suites again (the built-in now runs inside every `peter()` test of the package):

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt|agent-dispatch|tool-r|perm")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with the skips those plans name.

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-rewind.R tests/testthat/test-ckpt-rewind.R
git commit -m "feat(ckpt): register builtin:checkpoints with its checkpointers and hooks"
```

### Task 7: The session tree and `gptr_rewind()`

**Files:**
- Modify: `R/ckpt-rewind.R` (append)
- Test: `tests/testthat/test-ckpt-rewind.R` (append), `tests/testthat/test-copy-ckpt.R` (append)
- Generated: `NAMESPACE`, `man/gptr_rewind.Rd` (`devtools::document()`)

**Interfaces:**
- Consumes: Tasks 1-6 (`ckpt_ck_of()`, `ckpt_ext_state()`, `ckpt_specs()`, the specs' `undo`/`redo`/`preview`, `ckpt_partial_re` users); P01 `check_class()`, `check_number()`, `check_string()`, `check_choice()`, `check_flag()`, `gptr_abort()`, `gptr_warn()`, `gptr_inform()`, `msg_text()`, `ev_new()`; P02 `ev_dispatch()`, `ctx_new(session, run = NULL)`; P06 `session_data()`, `session_live()` (`$ctx`), `session_append()`, `run_current()` (`session`, `signal`); the IC-53 one-shot token `run$signal$control` (P06's `perm_grant_control()` appends the approved export's name; P08 consumes it the same way); tests: P08 `peter()`, `gptr_on()`, P06 `gptr_fork()`, P15's `builtin:documents` (record and replay of `.R` documents, its `session_tree` hook), P01 `front_end()` (mocked), `local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_project()`, `local_gptr_options()`, `expect_no_copy()`.
- Produces: the export `gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"), force = FALSE, preview = FALSE)` (04 §6.5); the events `session_before_tree` (first decision; payload `from`, `to`, `plan`; `list(cancel = TRUE, reason)` cancels) and `session_tree` (notify; payload `from`, `to`, `report`, plus `restore`, `keep`, `undone`, `redone`); the entry `gptr.rewind` `{from, to, keep, restore, report, undone, redone}`; the session fields `.d$last_rewind` (`list(id, from, to, keep, restore, report, partial)`) and `.d$editor_text`; internal `ckpt_tree(d)`, `ckpt_tree_path(tree, id)`, `ckpt_path_starts(tree, path)`, `ckpt_user_turn(e)`, `ckpt_tree_entry(tree, id)`, `ckpt_entry_text(tree, id)`, `ckpt_final_text(tree, path)`, `ckpt_fragment(data, name)`, `ckpt_rewind_target(tree, turn, to)`, `ckpt_applied(tree, ids)`, `ckpt_wanted(tree, target, ids)`, `ckpt_rewind_ops(tree, target, fork_entry = NULL)`, `ckpt_rewind_apply(tree, ops, specs, ctx, force)`, `ckpt_rewind_plan(tree, ops, specs, ctx, force)`, `ckpt_plan_chain(plan)`, `ckpt_partial(report)`, `ckpt_rewind_guard(d)` (`d` is a `.d` environment or a list with `id` and `status`), `ckpt_session_ctx(s)`, `ckpt_append_at(s, parent, entry)`.

Adapted from G7's verified `p5/ckpt_session.R` (report section 5.6, 13/13 PASS; verification log item 13) and sections 3.2, 3.6, 4.2-4.3. A turn is one `peter()` call on the session: P06 stamps every user message with `gptr$turn` (the prompt turn it belongs to), so a turn opens at the first user message of a new turn number; steers and follow-ups belong to the running turn. Keeping turns `1..k` targets the parent of turn `k + 1`'s opening user message (Pi: selecting a user message moves the leaf to its parent); `turn = 0` keeps the `gptr.frozen` entry, so the frozen prefix survives. The records to undo are those applied now (all at creation, then the `undone`/`redone` lists of every earlier `gptr.rewind` in file order) but not wanted at the target (on its path, minus workspace-only rewinds there): undone newest first through every registered checkpointer (`undo(fragment, ctx, force)`, plugins included; a fragment whose checkpointer is gone is reported), then redone oldest first. Records a fork copied from its source session belong to the source and are never undone by the fork (G7 section 4.2; `.d$fork_of$entry`). Then one `gptr.rewind` entry is appended under the target (P06's `session_append()` parents at the leaf, so the leaf moves first), so the JSONL stays byte-append-only and the leaf is durable on reload (Pi: the leaf is the last entry in file order); `restore = "workspace"` parents it at the old leaf instead (the conversation stays, so no prompt is handed back: `s$editor_text` is `NULL`). P16 writes `.d$turns`, `.d$last_text`, `.d$status` (a terminal status of the abandoned turn becomes `idle`), `.d$last_rewind` and `.d$editor_text` itself: P06 offers no verb for a rewind (self-review). A full restore tells the model nothing (the next request's prefix equals the earlier request at the target; P07's prefix guard resets on `session_tree`); a partial one leaves the not-restored items for the Task 6 block, warns `gptr_warning_rewind_partial` (field `report`) and lists them in `s$last_rewind$report`. A replayed session (`.d$replayed`) and `restore = "conversation"` only move the leaf (G7 section 4.4: a `gptr_rewind()` written into a script is a workspace no-op in replay). The IC-53 guard: a running or waiting session is `gptr_error_busy`; model code of a run rewinding another session is `gptr_error_permission` unless the one-shot token `gptr_rewind` is present (it is consumed). P15's `session_tree` hook makes the undone blocks of a bound document inert (`status=undone`, `#~ ` lines, 04 §11.5), which is acceptance 4.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ckpt-rewind.R`:

```r
# Synthetic entry trees (R shape, contract section 4.6) for the pure rewind helpers
tree_of = function(...) {
  d = new.env(parent = emptyenv())
  d$entries = list(...)
  d$leaf = d$entries[[length(d$entries)]]$id
  ckpt_tree(d)
}
e_frozen = function(id) {
  list(type = "custom", id = id, parent_id = NULL, custom_type = "gptr.frozen", data = list())
}
e_user = function(id, parent, text, turn) {
  list(type = "message", id = id, parent_id = parent, gptr = list(turn = turn),
       message = list(role = "user", content = list(list(type = "text", text = text)),
                      source = "prompt"))
}
e_asst = function(id, parent) {
  list(type = "message", id = id, parent_id = parent,
       message = list(role = "assistant", content = list(list(type = "text", text = "ok")),
                      stop_reason = "stop"))
}
e_cp = function(id, parent) {
  list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.checkpoint",
       data = list(tool_call_id = id, fragments = list()))
}
e_rw = function(id, parent, from, undone = character(), redone = character(), restore = "all") {
  list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.rewind",
       data = list(from = from, restore = restore, undone = undone, redone = redone))
}
three_turns = function(...) {
  tree_of(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"), e_asst("a1", "c1"),
          e_user("u2", "a1", "two", 2), e_cp("c2", "u2"), e_asst("a2", "c2"),
          e_user("u3", "a2", "three", 3), e_cp("c3", "u3"), e_asst("a3", "c3"), ...)
}

test_that("rewind targets: kept turns, relative turns, entry ids and range errors", {
  tr = three_turns()
  t1 = ckpt_rewind_target(tr, 1L, NULL)
  expect_identical(t1$target, "a1")
  expect_identical(t1$keep, 1L)
  expect_identical(t1$prompt, "two")
  expect_identical(ckpt_rewind_target(tr, -1L, NULL)$target, "a2")
  expect_identical(ckpt_rewind_target(tr, 0L, NULL)$target, "f0")
  expect_identical(ckpt_rewind_target(tr, 3L, NULL)$target, "a3")
  expect_identical(ckpt_rewind_target(tr, 1L, "c2")$target, "c2")
  expect_error(ckpt_rewind_target(tr, 4L, NULL), class = "gptr_error_rewind_range")
  expect_error(ckpt_rewind_target(tr, -4L, NULL), class = "gptr_error_rewind_range")
  expect_error(ckpt_rewind_target(tr, 1L, "nope"), class = "gptr_error_rewind_range")
  expect_identical(ckpt_rewind_ops(tr, "a1")$undo, c("c3", "c2"))
  expect_identical(ckpt_rewind_ops(tr, "a1")$redo, character())
})

test_that("applied records follow the rewinds in file order; redo targets abandoned records", {
  tr = three_turns(e_rw("r1", "a1", from = "a3", undone = c("c3", "c2")),
                   e_user("u4", "r1", "four", 2), e_cp("c4", "u4"), e_asst("a4", "c4"))
  expect_identical(ckpt_applied(tr, c("c1", "c2", "c3", "c4")),
                   c(c1 = TRUE, c2 = FALSE, c3 = FALSE, c4 = TRUE))
  ops = ckpt_rewind_ops(tr, "a3")
  expect_identical(ops$undo, "c4")
  expect_identical(ops$redo, c("c2", "c3"))
  expect_identical(sum(ckpt_path_starts(tr, ckpt_tree_path(tr, "a4"))), 2L)
  tr2 = tree_of(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"),
                e_asst("a1", "c1"), e_user("u2", "a1", "two", 2), e_cp("c2", "u2"),
                e_asst("a2", "c2"),
                e_rw("w1", "a2", from = "a2", undone = "c2", restore = "workspace"))
  expect_identical(ckpt_wanted(tr2, "w1", c("c1", "c2")), c(c1 = TRUE, c2 = FALSE))
  expect_identical(ckpt_rewind_ops(tr2, "a2")$redo, "c2")
  ops = ckpt_rewind_ops(tr, "f0", fork_entry = "a1")
  expect_identical(ops$undo, "c4")
  expect_identical(ops$foreign, "c1")
})

test_that("the preview credits items that a newer record of the same rewind puts back", {
  plan = data.frame(record = c("c3", "c2"), turn = c(3L, 2L), action = "undo",
                    checkpointer = "objects", item = "object x", restore = c(TRUE, FALSE),
                    reason = c("would be restored",
                               "conflict: changed after the checkpoint (kept current)"),
                    stringsAsFactors = FALSE)
  expect_identical(ckpt_plan_chain(plan)$restore, c(TRUE, TRUE))
})

test_that("report lines become the rewind block lines", {
  expect_identical(
    ckpt_rewind_lines(c("object cfg: not restored (reference object)",
                        "file data/x.csv: conflict: changed after the checkpoint (kept current)",
                        "option digits: not restored (gone)")),
    c("~ cfg (not restored (reference object))",
      "file data/x.csv (conflict: changed after the checkpoint (kept current))",
      "option digits: not restored (gone)"))
})

test_that("gptr_rewind(s, 1) after three mutating turns restores objects and files (acc. 3)", {
  proj = local_project(files = list("R/clean.R" = "clean = function(d) d[complete.cases(d), ]"))
  fake = local_fake_provider(list(
    fake_tool("r", code = "counts = log1p(counts); writeLines('normalised', 'log.txt')"),
    "turn one",
    fake_tool("r", code = "counts[, 1] = 0; pca = prcomp(counts[, 1:3])"), "turn two",
    fake_tool("r", code = paste0("writeLines('clean = function(d) na.omit(d)', 'R/clean.R'); ",
                                 "rm(pca); draw = 1:3")), "turn three",
    "after the rewind"))
  e = new.env()
  e$counts = matrix(as.numeric(1:200), 20)
  s = peter("normalise", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("scale") |> peter("clean up")
  expect_true(exists("draw", envir = e, inherits = FALSE))
  f = s$file
  before = readBin(f, "raw", file.size(f))
  expect_no_warning(gptr_rewind(s, 1))
  expect_equal(e$counts, log1p(matrix(as.numeric(1:200), 20)))
  expect_false(exists("pca", envir = e, inherits = FALSE))
  expect_false(exists("draw", envir = e, inherits = FALSE))
  expect_identical(readLines(file.path(proj, "R", "clean.R")),
                   "clean = function(d) d[complete.cases(d), ]")
  expect_true(file.exists(file.path(proj, "log.txt")))
  after = readBin(f, "raw", file.size(f))
  expect_identical(after[seq_along(before)], before)
  expect_gt(length(after), length(before))
  rw = entries_of(s, "gptr.rewind")
  expect_length(rw, 1L)
  u2 = Filter(function(x) {
    identical(x$type, "message") && identical(x$message$role, "user") &&
      identical(msg_text(x$message), "scale")
  }, session_data(s)$entries)[[1L]]
  expect_identical(rw[[1L]]$parent_id, u2$parent_id)
  expect_identical(session_data(s)$leaf, rw[[1L]]$id)
  expect_identical(s$turns, 1L)
  expect_identical(s$text, "turn one")
  expect_identical(s$editor_text, "scale")
  expect_false(s$last_rewind$partial)
  s |> peter("try again")
  req = fake_requests(fake)
  expect_length(req, 7L)
  m3 = req[[3L]]$messages
  m7 = req[[7L]]$messages
  expect_identical(m7[-length(m7)], m3[-length(m3)])
  expect_identical(msg_text(m7[[length(m7)]]), "try again")
  expect_length(entries_of(s, "gptr.cache_break"), 0L)
})

test_that("a user edit made after the turn survives the 3-way restore; the rewind warns", {
  proj = local_project()
  fake = local_fake_provider(list(
    fake_tool("r", code = "x = 1"), "one",
    fake_tool("r", code = "x = 2; writeLines('agent', 'out.txt')"), "two",
    "three"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  e$x = 99
  writeLines("user", file.path(proj, "out.txt"))
  expect_warning(gptr_rewind(s, 1), class = "gptr_warning_rewind_partial")
  expect_identical(e$x, 99)
  expect_identical(readLines(file.path(proj, "out.txt")), "user")
  expect_true(s$last_rewind$partial)
  expect_true(any(grepl("^object x: conflict", s$last_rewind$report)))
  s |> peter("three")
  req = fake_requests(fake)
  last = req[[length(req)]]$messages
  texts = vapply(last[[length(last)]]$content, function(b) ckpt_scalar(b$text, ""), "")
  block = texts[grepl("reason=\"rewind\"", texts, fixed = TRUE)]
  expect_length(block, 1L)
  expect_match(block, "<workspace_changes since=\"turn 1\" reason=\"rewind\">", fixed = TRUE)
  expect_match(block, "~ x (conflict", fixed = TRUE)
})

test_that("gptr_rewind() refuses a running session and bad arguments", {
  local_project()
  local_fake_provider(list("hello", fake_tool("r", code = "z = 1"), "done"))
  e = new.env()
  s = peter("hi", model = "fake/fake-1", mode = "auto", envir = e)
  seen = new.env()
  gptr_on(s, "tool_execution_start", function(event, ctx) {
    seen$cls = class(tryCatch(gptr_rewind(ctx$session), error = function(err) err))
    NULL
  })
  s |> peter("go")
  expect_true("gptr_error_busy" %in% seen$cls)
  expect_identical(e$z, 1)
  expect_error(gptr_rewind(s, 5), class = "gptr_error_rewind_range")
  expect_error(gptr_rewind(s, to = "ffffffff"), class = "gptr_error_rewind_range")
  expect_error(gptr_rewind(s, restore = "everything"), class = "gptr_error_invalid_argument")
  expect_error(gptr_rewind(list()), class = "gptr_error_invalid_argument")
})

test_that("the IC-53 guard: rewinding another session from model code needs the one-shot token", {
  sig = new.env(parent = emptyenv())
  sig$control = character()
  local_mocked_bindings(run_current = function() list(session = "s9999999999", signal = sig))
  other = list(id = "s0000000001", status = "idle")
  expect_error(ckpt_rewind_guard(other), class = "gptr_error_permission")
  sig$control = c("gptr_doc", "gptr_rewind")
  expect_true(ckpt_rewind_guard(other))
  expect_identical(sig$control, "gptr_doc")
  expect_error(ckpt_rewind_guard(other), class = "gptr_error_permission")
  expect_error(ckpt_rewind_guard(list(id = "s9999999999", status = "idle")),
               class = "gptr_error_busy")
  expect_error(ckpt_rewind_guard(list(id = "s0000000001", status = "running")),
               class = "gptr_error_busy")
})

test_that("model code cannot rewind another session during a run (IC-53)", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "made x",
                           fake_tool("r", code = "gptr_rewind(other)"), "tried"))
  e = new.env()
  other = peter("make x", model = "fake/fake-1", mode = "auto", envir = e)
  e$other = other
  tryCatch(peter("rewind the other one", model = "fake/fake-1", mode = "auto", envir = e),
           gptr_error = function(err) NULL)
  expect_identical(e$x, 1)
  expect_length(entries_of(other, "gptr.rewind"), 0L)
})

test_that("gptr_rewind(to =) redoes an abandoned branch", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2; y = 1"), "two",
                           fake_tool("r", code = "z = 1"), "other"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  old_leaf = session_data(s)$leaf
  gptr_rewind(s, 1)
  expect_identical(e$x, 1)
  expect_false(exists("y", envir = e, inherits = FALSE))
  s |> peter("other")
  expect_identical(e$z, 1)
  gptr_rewind(s, to = old_leaf)
  expect_identical(e$x, 2)
  expect_identical(e$y, 1)
  expect_false(exists("z", envir = e, inherits = FALSE))
  expect_identical(s$turns, 2L)
})

test_that("restore = 'conversation' keeps the workspace; 'workspace' keeps the conversation", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2"), "two"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  gptr_rewind(s, 1, restore = "conversation")
  expect_identical(e$x, 2)
  expect_identical(s$turns, 1L)
  leaf = session_data(s)$leaf
  gptr_rewind(s, 0, restore = "workspace")
  expect_false(exists("x", envir = e, inherits = FALSE))
  expect_identical(entries_of(s, "gptr.rewind")[[2L]]$parent_id, leaf)
  expect_identical(s$turns, 1L)
})

test_that("preview returns the plan and changes nothing; a session_before_tree handler cancels", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2"), "two"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  plan = gptr_rewind(s, 0, preview = TRUE)
  expect_named(plan, c("record", "turn", "action", "checkpointer", "item", "restore", "reason"))
  expect_true("object x" %in% plan$item)
  expect_true(all(plan$restore[plan$item == "object x"]))
  expect_identical(e$x, 2)
  expect_length(entries_of(s, "gptr.rewind"), 0L)
  gptr_on(s, "session_before_tree", function(event, ctx) list(cancel = TRUE, reason = "not now"))
  gptr_rewind(s, 0)
  expect_identical(e$x, 2)
  expect_length(entries_of(s, "gptr.rewind"), 0L)
})

test_that("a fork never undoes the records it copied from its source", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  f = gptr_fork(s)
  expect_warning(gptr_rewind(f, 0), class = "gptr_warning_rewind_partial")
  expect_identical(e$x, 1)
  expect_true(any(grepl("made before the fork", f$last_rewind$report, fixed = TRUE)))
})

test_that("a CLI child's file edit is undone by gptr_rewind() (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
  local_fake_provider(function(request) {
    writeLines("a = 2", file.path(proj, "R", "a.R"))
    "Codex edited R/a.R"
  })
  s = peter("edit a", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 2")
  gptr_rewind(s, 0)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
})

test_that("undone blocks in a bound document become inert; re-sourcing reproduces the rewind", {
  proj = local_project()
  local_gptr_options(record = "auto", replay = "auto")
  local_mocked_bindings(front_end = function() "terminal")
  fake = local_fake_provider(list(
    fake_tool("r", code = "a = 1"), "set a",
    fake_tool("r", code = "b = a + 1"), "set b",
    fake_tool("r", code = "a = 10"), "reset a"))
  script = file.path(proj, "analysis.R")
  writeLines(c('s = peter("set a", model = "fake/fake-1", mode = "auto")',
               's |> peter("set b")',
               's |> peter("reset a")'), script)
  e = new.env()
  source(script, local = e)
  expect_identical(e$a, 10)
  expect_identical(e$b, 2)
  expect_no_warning(gptr_rewind(e$s, 1))
  expect_identical(e$a, 1)
  expect_false(exists("b", envir = e, inherits = FALSE))
  txt = readLines(script, encoding = "UTF-8")
  expect_identical(sum(grepl("status=undone", txt, fixed = TRUE)), 2L)
  expect_true(any(startsWith(txt, "#~ ")))
  n = length(fake_requests(fake))
  e2 = new.env()
  source(script, local = e2)
  expect_identical(e2$a, 1)
  expect_false(exists("b", envir = e2, inherits = FALSE))
  expect_identical(length(fake_requests(fake)), n)
})
```

Append to `tests/testthat/test-copy-ckpt.R`:

```r
# End-to-end rows (04 section 1.3: gptr_rewind() [R1][R6], gptr_preimage() [R4]). The child runs
# the fake provider in its global environment, with replay off and a temporary project root,
# so nothing touches the test process.
ckpt_e2e_setup = function(code) {
  c("d = tempfile('proj'); dir.create(d)",
    "options(gptr.project_root = d, gptr.replay = 'live')",
    "big = runif(5e6)",
    sprintf("fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = '%s')), 'done'))",
            code))
}

test_that("a checkpointed turn leaves an object the agent only read editable in place", {
  expect_no_copy(ckpt_e2e_setup("n = length(big)"),
                 "s = peter('count', model = fake, mode = 'auto', envir = globalenv())",
                 label = "peter() with checkpoints on, the agent reads big")
})

test_that("gptr_rewind() after an in-place edit by the agent leaves the restored object editable", {
  expect_no_copy(ckpt_e2e_setup("big[1] = -1"),
                 c("s = peter('edit', model = fake, mode = 'auto', envir = globalenv())",
                   "suppressWarnings(gptr_rewind(s))", "stopifnot(big[1] != -1)"),
                 edit = "big[2] = 0", label = "gptr_rewind() swaps the pre-image back")
})

test_that("gptr_preimage() is a leaf (R4)", {
  expect_no_copy(c("big = runif(5e6)"),
                 paste0("invisible(gptr_preimage(big, 'big', list(predicted = 'modify', ",
                        "bytes = 4e7, budget = 1e9)))"),
                 label = "gptr_preimage() default method")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind|copy-ckpt")'`

Expected: the two tree tests and the preview-chain test error with `could not find function "ckpt_tree"` or `"ckpt_plan_chain"` (the block-lines test exercises Task 6 code and passes); the IC-53 guard test errors with `could not find function "ckpt_rewind_guard"`; every end-to-end test errors with `could not find function "gptr_rewind"`, the end-to-end IC-53 test (a negative test: the classifier already stops the call) already passes, and the copy row "gptr_rewind() swaps the pre-image back" fails with `the script did not finish`. The Task 6 and Task 1 tests still pass.

- [ ] **Step 3: Write the implementation**

Append to `R/ckpt-rewind.R`:

```r
# ---- the session tree ----------------------------------------------------------------------------

#' User-message sources that open a turn when an entry carries no turn number (steers, follow-ups,
#' extension and agent notes belong to the running turn)
#' @noRd
ckpt_turn_sources = c("prompt", "pipe", "repl", "replay", "parent", "imported")

#' The prompt turn of an entry: -1 not a user message; the recorded turn (P06 stamps user
#' messages with `gptr$turn`); NA unknown but turn-opening; -2 unknown and mid-turn
#' @noRd
ckpt_user_turn = function(e) {
  if (!identical(e$type, "message") || !identical(e$message$role, "user")) return(-1)
  t = suppressWarnings(as.numeric(e$gptr$turn)[1L])
  if (length(t) && !is.na(t)) return(t)
  if (ckpt_scalar(e$message$source, "prompt") %in% ckpt_turn_sources) NA_real_ else -2
}

#' The entry tree of a session (vectors over `.d$entries`, which are in append order)
#' @noRd
ckpt_tree = function(d) {
  ents = d$entries
  field = function(e, a, b) {
    v = e[[a]] %||% e[[b]]
    if (is.null(v) || !length(v)) "" else as.character(v)[1L]
  }
  list(ids = vapply(ents, function(e) field(e, "id", "id"), ""),
       parent = vapply(ents, function(e) field(e, "parent_id", "parentId"), ""),
       ctype = vapply(ents, function(e) field(e, "custom_type", "customType"), ""),
       uturn = vapply(ents, ckpt_user_turn, 0),
       entries = ents, leaf = ckpt_scalar(d$leaf, ""))
}

#' Entry ids from the root to `id`
#' @noRd
ckpt_tree_path = function(tree, id) {
  out = character()
  guard = length(tree$ids) + 1L
  while (length(id) && !is.na(id) && nzchar(id) && guard > 0L) {
    i = match(id, tree$ids)
    if (is.na(i)) break
    out = c(id, out)
    id = tree$parent[i]
    guard = guard - 1L
  }
  out
}

#' Which entries of a path open a turn: a user message whose turn differs from the last turn seen
#' on the path (or, without turn numbers, a turn-opening source)
#' @noRd
ckpt_path_starts = function(tree, path) {
  u = tree$uturn[match(path, tree$ids)]
  start = logical(length(path))
  last = NA_real_
  for (i in seq_along(path)) {
    if (!is.na(u[i]) && u[i] < 0) next
    if (is.na(u[i]) || is.na(last) || u[i] != last) start[i] = TRUE
    if (!is.na(u[i])) last = u[i]
  }
  start
}

#' The entry of an id
#' @noRd
ckpt_tree_entry = function(tree, id) {
  tree$entries[[match(id, tree$ids)]]
}

#' Text of a user message entry (context blocks excluded), "" when it has none
#' @noRd
ckpt_entry_text = function(tree, id) {
  m = ckpt_tree_entry(tree, id)$message
  if (is.null(m)) return("")
  tryCatch(ckpt_scalar(msg_text(m), ""), error = function(e) "")
}

#' The final answer at the end of a path, or NA when the path ends inside a turn or has none
#' @noRd
ckpt_final_text = function(tree, path) {
  for (id in rev(path)) {
    e = ckpt_tree_entry(tree, id)
    if (!identical(e$type, "message") || !identical(e$message$role, "assistant")) next
    m = e$message
    if (ckpt_scalar(m$stop_reason, "stop") %in% c("error", "aborted")) next
    calls = vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA)
    if (any(calls)) return(NA_character_)
    return(tryCatch(msg_text(m), error = function(err) NA_character_))
  }
  NA_character_
}

#' A checkpointer's fragment inside a `gptr.checkpoint` entry's data
#' @noRd
ckpt_fragment = function(data, name) {
  data$fragments[[name]] %||% data[[name]]
}

# ---- rewind planning ---------------------------------------------------------------------------

#' Resolve the rewind target: an entry id (NULL: before the first entry), the kept turn and the
#' undone prompt. Keeping turns 1..k targets the parent of turn k + 1's opening user message
#' (Pi: selecting a user message moves the leaf to its parent).
#' @noRd
ckpt_rewind_target = function(tree, turn, to) {
  path = ckpt_tree_path(tree, tree$leaf)
  starts = path[ckpt_path_starts(tree, path)]
  last = length(starts)
  if (!is.null(to)) {
    if (!to %in% tree$ids) {
      gptr_abort(paste0("There is no entry ", to, " in this session; see ",
                        "gptr_checkpoints(s, all = TRUE)."),
                 "rewind_range", turn = NA_integer_, turns = last)
    }
    return(list(target = to, keep = NULL, prompt = NULL))
  }
  keep = if (turn < 0L) last + turn else turn
  if (keep < 0L || keep > last) {
    gptr_abort(paste0("Cannot rewind to turn ", keep, ": the session has ", last,
                      " turn(s) on its active path."),
               "rewind_range", turn = as.integer(keep), turns = last)
  }
  if (keep == last) {
    return(list(target = if (nzchar(tree$leaf)) tree$leaf else NULL, keep = keep, prompt = NULL))
  }
  first = starts[keep + 1L]
  parent = tree$parent[match(first, tree$ids)]
  list(target = if (nzchar(parent)) parent else NULL, keep = keep,
       prompt = ckpt_entry_text(tree, first))
}

#' Which checkpoint records are applied now: all at creation, then the undone/redone lists of
#' every rewind in file order
#' @noRd
ckpt_applied = function(tree, ids) {
  have = stats::setNames(rep(TRUE, length(ids)), ids)
  for (i in which(tree$ctype == "gptr.rewind")) {
    dat = tree$entries[[i]]$data
    have[intersect(ckpt_chr(dat$undone), ids)] = FALSE
    have[intersect(ckpt_chr(dat$redone), ids)] = TRUE
  }
  have
}

#' Which records should be applied at `target`: the records on its path, minus those undone by
#' workspace-only rewinds on that path
#' @noRd
ckpt_wanted = function(tree, target, ids) {
  want = stats::setNames(rep(FALSE, length(ids)), ids)
  path = if (is.null(target)) character() else ckpt_tree_path(tree, target)
  for (i in match(path, tree$ids)) {
    if (tree$ctype[i] == "gptr.checkpoint") want[tree$ids[i]] = TRUE
    dat = tree$entries[[i]]$data
    if (tree$ctype[i] == "gptr.rewind" && identical(ckpt_scalar(dat$restore), "workspace")) {
      want[intersect(ckpt_chr(dat$undone), ids)] = FALSE
      want[intersect(ckpt_chr(dat$redone), ids)] = TRUE
    }
  }
  want
}

#' Records to undo (newest first) and redo (oldest first) to reach `target`; records a fork
#' copied from its source session belong to the source and are left alone (G7 section 4.2)
#' @noRd
ckpt_rewind_ops = function(tree, target, fork_entry = NULL) {
  ids = tree$ids[tree$ctype == "gptr.checkpoint"]
  none = list(undo = character(), redo = character(), foreign = character())
  if (!length(ids)) return(none)
  have = ckpt_applied(tree, ids)
  want = ckpt_wanted(tree, target, ids)
  foreign = character()
  if (!is.null(fork_entry)) foreign = intersect(ids, ckpt_tree_path(tree, fork_entry))
  undo = rev(ids[have & !want])
  redo = ids[!have & want]
  list(undo = setdiff(undo, foreign), redo = setdiff(redo, foreign),
       foreign = intersect(c(undo, redo), foreign))
}

#' Call a checkpointer's undo() or redo(); a failure becomes a report line
#' @noRd
ckpt_call_cp = function(fun, name, fragment, ctx, force) {
  tryCatch(as.character(fun(fragment, ctx, force)),
           error = function(e) {
             paste0("checkpointer ", name, ": failed (", conditionMessage(e), ")")
           })
}

#' Fragments of a record whose checkpointer is no longer registered
#' @noRd
ckpt_orphan_lines = function(data, specs) {
  have = names(data$fragments %||% list())
  miss = setdiff(have, vapply(specs, function(sp) sp$name, ""))
  if (!length(miss)) return(character())
  paste0("checkpointer ", miss, ": not restored (it is not registered)")
}

#' Apply the undo and redo lists through every checkpointer
#' @return `list(report = chr)`.
#' @noRd
ckpt_rewind_apply = function(tree, ops, specs, ctx, force) {
  report = character()
  for (id in ops$undo) {
    data = ckpt_tree_entry(tree, id)$data
    for (sp in rev(specs)) {
      fr = ckpt_fragment(data, sp$name)
      if (!is.null(fr)) report = c(report, ckpt_call_cp(sp$undo, sp$name, fr, ctx, force))
    }
    report = c(report, ckpt_orphan_lines(data, specs))
  }
  for (id in ops$redo) {
    data = ckpt_tree_entry(tree, id)$data
    for (sp in specs) {
      fr = ckpt_fragment(data, sp$name)
      if (!is.null(fr)) report = c(report, ckpt_call_cp(sp$redo, sp$name, fr, ctx, force))
    }
    report = c(report, ckpt_orphan_lines(data, specs))
  }
  if (length(ops$foreign)) {
    report = c(report, paste0("checkpoint ", ops$foreign, ": not restored (made before the ",
                              "fork; the source session owns it)"))
  }
  list(report = report)
}

#' The empty rewind plan (`preview = TRUE`)
#' @noRd
ckpt_plan_empty = function() {
  data.frame(record = character(), turn = integer(), action = character(),
             checkpointer = character(), item = character(), restore = logical(),
             reason = character(), stringsAsFactors = FALSE)
}

#' One checkpointer's preview of one fragment: its `preview()` (built-ins), else `describe()`
#' lines with an unknown outcome
#' @noRd
ckpt_preview_one = function(sp, fragment, ctx, force, direction) {
  if (is.function(sp$preview)) {
    p = tryCatch(sp$preview(fragment, ctx, force, direction), error = function(e) NULL)
    if (is.data.frame(p)) return(p)
  }
  lines = if (is.function(sp$describe)) {
    tryCatch(as.character(sp$describe(fragment)), error = function(e) character())
  } else {
    character()
  }
  data.frame(item = lines, ok = rep(NA, length(lines)), action = rep("", length(lines)),
             stringsAsFactors = FALSE)
}

#' The rewind plan: one row per item and whether it would be restored
#' @noRd
ckpt_rewind_plan = function(tree, ops, specs, ctx, force) {
  rows = list()
  for (direction in c("undo", "redo")) {
    order_specs = if (direction == "undo") rev(specs) else specs
    for (id in ops[[direction]]) {
      data = ckpt_tree_entry(tree, id)$data
      for (sp in order_specs) {
        fr = ckpt_fragment(data, sp$name)
        if (is.null(fr)) next
        p = ckpt_preview_one(sp, fr, ctx, force, direction)
        if (!nrow(p)) next
        rows[[length(rows) + 1L]] = data.frame(
          record = id, turn = as.integer(ckpt_num(fr$turn)), action = direction,
          checkpointer = sp$name, item = p$item, restore = as.logical(p$ok), reason = p$action,
          stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(rows)) return(ckpt_plan_empty())
  out = do.call(rbind, rows)
  rownames(out) = NULL
  ckpt_plan_chain(out)
}

#' A dry run checks each record against the current workspace, so an older record's item that a
#' newer record of the same rewind puts back first is marked restorable too
#' @noRd
ckpt_plan_chain = function(plan) {
  for (i in which(plan$restore %in% FALSE & grepl("^conflict", plan$reason))) {
    prior = which(seq_len(nrow(plan)) < i & plan$action == plan$action[i] &
                    plan$checkpointer == plan$checkpointer[i] & plan$item == plan$item[i] &
                    plan$restore %in% TRUE)
    if (length(prior)) {
      plan$restore[i] = TRUE
      plan$reason[i] = "would be restored (after the newer record)"
    }
  }
  plan
}

#' Report lines that mean an item was not restored
#' @noRd
ckpt_partial_re = "not restored|not redone|conflict|failed"

#' Was a rewind partial?
#' @noRd
ckpt_partial = function(report) {
  any(grepl(ckpt_partial_re, report))
}

#' Refuse to rewind a running session (`busy`), and a gptr_rewind() of another session made from
#' model code during a run unless the dispatcher approved exactly that call (IC-53 item 3: the
#' one-shot token "gptr_rewind" in `run$signal$control`, consumed here)
#' @noRd
ckpt_rewind_guard = function(d) {
  if (ckpt_scalar(d$status) %in% c("running", "waiting")) {
    gptr_abort(paste0("Session ", d$id, " is running; wait for it or cancel it before ",
                      "rewinding."), "busy", session = d$id)
  }
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  if (identical(ckpt_scalar(run$session), d$id)) {
    gptr_abort(paste0("Session ", d$id, " is running; it cannot rewind itself."), "busy",
               session = d$id)
  }
  sig = run$signal
  tokens = if (is.environment(sig)) ckpt_chr(sig$control) else character()
  i = match("gptr_rewind", tokens)
  if (!is.na(i)) {
    sig$control = tokens[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0("gptr_rewind() of session ", d$id, " was called from model code during ",
                      "a run."), "Only you can rewind another session."),
             "permission", action = "gptr_rewind", tool = "r", risk = 4L,
             how_to_allow = "call gptr_rewind() yourself, outside the run",
             session = ckpt_scalar(run$session))
}

#' The ctx handed to checkpointers outside a run (the session's own, or a new one for a detached
#' copy)
#' @noRd
ckpt_session_ctx = function(s) {
  live = session_live(s)
  if (!is.null(live) && !is.null(live$ctx)) return(live$ctx)
  ctx_new(s)
}

#' Append an entry under `parent` (P06 parents every entry at the leaf, so the leaf moves first;
#' it is put back if the append fails)
#' @noRd
ckpt_append_at = function(s, parent, entry) {
  d = session_data(s)
  old = d$leaf
  d$leaf = parent
  done = FALSE
  on.exit({
    if (!done) d$leaf = old
  }, add = TRUE)
  id = session_append(s, entry)
  done = TRUE
  invisible(id)
}

#' Statuses a conversation rewind clears: the session is idle at the target
#' @noRd
ckpt_terminal_status = c("blocked", "budget", "max_turns", "error", "aborted", "interrupted")

# ---- gptr_rewind() (contract 6.5) ----------------------------------------------------------------

#' Rewind a session: undo turns, restore objects and files, move the conversation
#'
#' `gptr_rewind()` is a branch-in-place on the one session object: it undoes the checkpoint
#' records of the turns being left (newest first), redoes the records of a target on another
#' branch (oldest first), appends one `gptr.rewind` entry parented at the target (the session file
#' stays append-only and the rewind survives a reload), hands back the undone prompt in
#' `s$editor_text` and returns `s` invisibly, so it pipes:
#' `s |> gptr_rewind() |> peter("Try another way")`. Use [gptr_fork()] for a second session object.
#'
#' Restores are 3-way: an object or file that changed after the turn (by you or another session)
#' is kept and reported, unless `force = TRUE`. Reference objects (environments, R6, external
#' pointers), objects over the undo budget (`gptr.undo_max_bytes`), environment variables,
#' loaded namespaces, the random-number state and effects outside R (network, databases,
#' processes) are not restored; they are listed in `s$last_rewind$report`, and items that were
#' not restored raise the warning `gptr_warning_rewind_partial`. Files outside the project and
#' `tempdir()` are restored only after you confirm each path. After a full restore the model is
#' told nothing (the next request's prefix is byte-identical to the earlier request at the
#' target); after a partial one the next prompt carries a short
#' `<workspace_changes reason="rewind">` block listing what was not restored.
#'
#' @param s A `gptr_session`.
#' @param turn Integer. Negative counts back from the last turn (`-1` undoes the last turn); `0`
#'   goes back to before the first turn; `k > 0` keeps turns `1..k` of the active path.
#' @param to An entry id from `gptr_checkpoints(s, all = TRUE)`; overrides `turn`. Any entry
#'   works, including the end of an abandoned branch, which is how redo works.
#' @param restore `"all"` (objects, files, session state and the conversation), `"conversation"`
#'   (only the conversation) or `"workspace"` (only objects, files and session state; the
#'   conversation stays where it is).
#' @param force Also restore items that changed after the checkpoint (3-way conflicts).
#' @param preview Return the plan instead: a data frame with one row per item (`record`, `turn`,
#'   `action`, `checkpointer`, `item`, `restore`, `reason`); nothing changes.
#' @return `s`, invisibly (the plan when `preview = TRUE`). `s$last_rewind` holds the report and
#'   `s$editor_text` the undone prompt.
#' @section Options:
#' Options of checkpoints and rewind (`?gptr_options` collects every option):
#' `gptr.checkpoint` (`"on"`): `"files"` checkpoints files only, `"off"` nothing (also the
#' settings key `checkpoint`).
#' `gptr.undo_capture_max` (`1e8`): bytes; every object up to this size is captured by
#' reference.
#' `gptr.undo_max_bytes` (`1e9`): bytes of pre-images held in memory per session.
#' `gptr.undo_spill_max` (`2e9`): bytes; the largest object image written to disk.
#' `gptr.undo_turns` (`20`): object images older than this many turns are dropped.
#' `gptr.checkpoint_disk_bytes` (`2e9`): bytes of blobs and spilled images before a notice.
#' `gptr.checkpoint_days` (`30`): unreferenced blobs older than this many days are deleted.
#' `gptr.checkpoint_turns` (`100`): file checkpoints older than this many turns are not
#' restored.
#' `gptr.checkpoint_track_file_max` (`1e6`), `gptr.checkpoint_track_total` (`1e8`): bytes per
#' file and in all of the baseline taken at the first mutating call.
#' `gptr.checkpoint_capture_max` (`5e7`): bytes; a larger changed file gets no stored copy.
#' `gptr.checkpoint_scan_budget` (`0.25`): seconds; slower walks switch to one scan per turn.
#' `gptr.checkpoint_rng` (`TRUE`): report changes of the random-number state.
#' `gptr.checkpoint_close_devices` (`FALSE`): close graphics devices an undone turn opened.
#' @family checkpoints
#' @export
#' @examples
#' d = tempfile("project")
#' dir.create(d)
#' op = options(gptr.project_root = d)
#' fake = gptr_fake_provider(list(
#'   list(tool = "r", input = list(code = "x = 1")), "Made x.",
#'   list(tool = "r", input = list(code = "x = x + 1")), "Added one."))
#' e = new.env()
#' s = peter("Make x", model = fake, mode = "auto", envir = e)
#' s |> peter("Add one to x")
#' e$x
#' s |> gptr_rewind()
#' e$x
#' s$editor_text
#' options(op)
gptr_rewind = function(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"),
                       force = FALSE, preview = FALSE) {
  check_class(s, "gptr_session", "s")
  turn = check_number(turn, "turn", int = TRUE)
  check_string(to, "to", null = TRUE)
  restore = check_choice(restore, c("all", "conversation", "workspace"), "restore")
  check_flag(force, "force")
  check_flag(preview, "preview")
  d = session_data(s)
  ckpt_rewind_guard(d)
  tree = ckpt_tree(d)
  tgt = ckpt_rewind_target(tree, turn, to)
  ops = ckpt_rewind_ops(tree, tgt$target, d$fork_of$entry)
  if (identical(restore, "conversation") || isTRUE(d$replayed)) {
    ops = list(undo = character(), redo = character(), foreign = character())
  }
  ctx = ckpt_session_ctx(s)
  specs = ckpt_specs(s)
  plan = ckpt_rewind_plan(tree, ops, specs, ctx, force)
  if (preview) return(plan)
  dec = tryCatch(
    ev_dispatch("session_before_tree",
                ev_new("session_before_tree", session = d$id, from = tree$leaf,
                       to = tgt$target, plan = plan),
                session = s, ctx = ctx),
    error = function(e) NULL)
  if (isTRUE(dec$cancel)) {
    gptr_inform(paste0("Rewind cancelled: ",
                       ckpt_scalar(dec$reason, "a session_before_tree handler cancelled it.")),
                "notice")
    return(invisible(s))
  }
  res = ckpt_rewind_apply(tree, ops, specs, ctx, force)
  from = tree$leaf
  parent = if (identical(restore, "workspace")) from else tgt$target
  entry = list(type = "custom", custom_type = "gptr.rewind",
               data = list(from = from, to = tgt$target, keep = tgt$keep, restore = restore,
                           report = I(res$report), undone = I(ops$undo), redone = I(ops$redo)))
  eid = ckpt_append_at(s, if (nzchar(parent %||% "")) parent else NULL, entry)
  partial = ckpt_partial(res$report)
  if (!identical(restore, "workspace")) {
    path = if (is.null(tgt$target)) character() else ckpt_tree_path(tree, tgt$target)
    d$turns = as.integer(sum(ckpt_path_starts(tree, path)))
    d$last_text = ckpt_final_text(tree, path)
    if (ckpt_scalar(d$status) %in% ckpt_terminal_status) {
      d$status = "idle"
      d$reason = NULL
    }
  }
  d$last_rewind = list(id = eid, from = from, to = tgt$target, keep = tgt$keep,
                       restore = restore, report = res$report, partial = partial)
  # a workspace-only rewind keeps the conversation, so no prompt was undone
  d$editor_text = if (identical(restore, "workspace")) NULL else tgt$prompt
  if (partial) {
    ck = ckpt_ck_of(ckpt_ext_state(s), s, create = TRUE)
    if (!is.null(ck)) {
      ck$rewind_note = res$report[grepl(ckpt_partial_re, res$report)]
      ck$rewind_since = if (is.null(tgt$keep)) {
        paste("entry", ckpt_scalar(tgt$target, "start"))
      } else {
        paste("turn", tgt$keep)
      }
    }
  }
  tryCatch(
    ev_dispatch("session_tree",
                ev_new("session_tree", session = d$id, from = from, to = tgt$target,
                       report = res$report, restore = restore, keep = tgt$keep,
                       undone = ops$undo, redone = ops$redo),
                session = s, ctx = ctx),
    error = function(e) NULL)
  if (partial) {
    gptr_warn(c("gptr_rewind() could not restore everything:",
                res$report[grepl(ckpt_partial_re, res$report)]),
              "rewind_partial", report = res$report)
  }
  invisible(s)
}
```

Regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: `NAMESPACE` gains `export(gptr_rewind)`; `man/gptr_rewind.Rd` is written.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind|copy-ckpt")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 199 ]` (133 in `test-ckpt-rewind.R`, 66 in `test-copy-ckpt.R`; without `capabilities("profmem")` the five copy tests skip: `[ FAIL 0 | WARN 0 | SKIP 5 | PASS 134 ]`).

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-rewind.R tests/testthat/test-ckpt-rewind.R tests/testthat/test-copy-ckpt.R NAMESPACE man/gptr_rewind.Rd
git commit -m "feat(ckpt): add gptr_rewind() as a branch-in-place on the session"
```

### Task 8: `gptr_checkpoints()` and the console commands

**Files:**
- Modify: `R/ckpt-rewind.R` (append; one line added to `builtin_checkpoints()`)
- Test: `tests/testthat/test-ckpt-rewind.R` (append), `tests/testthat/test-copy-ckpt.R` (append)
- Generated: `NAMESPACE`, `man/gptr_checkpoints.Rd` (`devtools::document()`)

**Interfaces:**
- Consumes: Tasks 1-7 (`ckpt_tree()`, `ckpt_tree_path()`, `ckpt_path_starts()`, `ckpt_fragment()`, `ckpt_entry_text()`, `ckpt_ck_of()`, `ckpt_ext_state()`, `ckpt_index_empty()`, `gptr_rewind()`); P01 `new_listing(df, class, footer = NULL)`, `gptr_opt("history")`, `gptr_is_interactive()`; P02 `gptr_command(name, handler, description = NULL, complete = NULL)` (the handler is `function(args, ctx)` and returns `NULL`, a chr printed verbatim or `list(prompt = chr(1))`, 04 §10.2 row 10); `ctx$session`, `ctx$has_ui()`, `ctx$ui()` (`select()`); tests: P11 `local_scripted_ui()`, the `ui.get` service, P02 `gptr_registry()`, `registry_get()`.
- Produces: the export `gptr_checkpoints(s, all = FALSE)` -> a `gptr_checkpoints` listing (04 §5.12: `turn`, `id`, `time`, `prompt`, `objects`, `files`, `held_mb`, `disk_mb`, `branch`); the command specs `undo`, `redo`, `rewind`, `checkpoints` registered by `builtin:checkpoints` (P14's console dispatches them; 03 §6.17); internal `ckpt_turn_rows(tree, path, branch, ck = NULL, exclude = character())`, `ckpt_segment_counts(tree, idx, ck)`, `ckpt_time(x)`, `ckpt_cmd_run(s, turn = -1L, to = NULL, restore = "all")`, `ckpt_history_push(text)`, `ckpt_cmd_undo(args, ctx)`, `ckpt_is_redo(tree, dat)`, `ckpt_redo_target(tree)`, `ckpt_cmd_redo(args, ctx)`, `ckpt_cmd_rewind(args, ctx)`, `ckpt_cmd_checkpoints(args, ctx)`, `ckpt_commands()`.

The commands follow G7 section 4.2: `/undo` is `gptr_rewind(s, -1)` and asks first (through the UI) when the preview shows items that cannot be restored, then pushes the undone prompt into the console history with `utils::timestamp()` so Up recalls it (`readline()` cannot pre-fill; only with `gptr.history` and a human); `/redo` rewinds to the `from` of the latest `gptr.rewind` on the active path when no turn started since, skipping rewinds that were themselves redos (a rewind whose `from` is an earlier rewind and whose `to` is that rewind's `from`) and the rewinds they redid, so a second `/redo` says "Nothing to redo." instead of undoing the first and `/undo`, `/undo`, `/redo`, `/redo` walks back and forth through both turns; `/rewind <k>` keeps turns `1..k`; `/rewind` without a number offers the turns and Claude Code's actions ("Code and conversation", "Conversation only", "Code only", "Never mind") through `ctx$ui()$select()`; `/checkpoints [all]` prints the listing. A command returns its report lines (the console prints them verbatim); a `gptr_error` becomes its message and the partial warning is muffled because the report already lists the items.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-ckpt-rewind.R`:

```r
two_turn_session = function(e, .env = parent.frame()) {
  local_fake_provider(list(fake_tool("r", code = "x = 1; writeLines('a', 'a.txt')"), "one",
                           fake_tool("r", code = "x = 2"), "two", "three"), .env = .env)
  s = peter("first prompt", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("second prompt")
}

test_that("gptr_checkpoints() lists the turns of the active path (contract 5.12)", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  cp = gptr_checkpoints(s)
  expect_s3_class(cp, c("gptr_checkpoints", "gptr_listing", "data.frame"))
  expect_named(cp, c("turn", "id", "time", "prompt", "objects", "files", "held_mb", "disk_mb",
                     "branch"))
  expect_identical(cp$turn, 1:2)
  expect_identical(cp$prompt, c("first prompt", "second prompt"))
  expect_identical(cp$objects, c("1/1", "1/1"))
  expect_identical(cp$files, c("1/1", "0/0"))
  expect_identical(cp$branch, c("active", "active"))
  expect_s3_class(cp$time, "POSIXct")
  expect_true(all(cp$held_mb >= 0))
  expect_identical(cp$id[2L], session_data(s)$leaf)
  expect_output(print(cp), "Rewind with gptr_rewind")
})

test_that("gptr_checkpoints(all = TRUE) adds abandoned branches", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  gptr_rewind(s, 1)
  expect_identical(nrow(gptr_checkpoints(s)), 1L)
  all = gptr_checkpoints(s, all = TRUE)
  expect_identical(all$branch, c("active", "abandoned"))
  expect_identical(all$prompt[2L], "second prompt")
  expect_error(gptr_checkpoints(list()), class = "gptr_error_invalid_argument")
})

test_that("/undo, /redo, /rewind k and /checkpoints drive gptr_rewind()", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  ctx = list(session = s, has_ui = function() FALSE)
  out = ckpt_cmd_undo("", ctx)
  expect_match(out[1L], "^Rewound \\(all\\)")
  expect_true("second prompt" %in% out)
  expect_identical(e$x, 1)
  out = ckpt_cmd_redo("", ctx)
  expect_match(out[1L], "^Rewound")
  expect_identical(e$x, 2)
  expect_identical(ckpt_cmd_redo("", ctx), "Nothing to redo.")
  out = ckpt_cmd_rewind("0", ctx)
  expect_false(exists("x", envir = e, inherits = FALSE))
  expect_identical(ckpt_cmd_rewind("abc", ctx), "Usage: /rewind [turn]")
  expect_match(ckpt_cmd_rewind("9", ctx), "Cannot rewind to turn 9")
  lines = ckpt_cmd_checkpoints("all", ctx)
  expect_true(any(grepl("abandoned", lines, fixed = TRUE)))
  expect_identical(ckpt_cmd_undo("", list(session = NULL)), "There is no session to undo.")
})

test_that("/rewind without a turn offers a menu through the UI", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  ui = local_scripted_ui(answers = list(2L, 3L))
  ctx = list(session = s, has_ui = function() TRUE,
             ui = function() ext_service_get("ui.get")(s))
  out = ckpt_cmd_rewind("", ctx)
  expect_match(out[1L], "^Rewound \\(workspace\\)")
  expect_identical(e$x, 1)
  expect_identical(s$turns, 2L)
  expect_identical(ui$remaining(), 0L)
})

test_that("/redo follows chains of undos and stops after a redo", {
  rw = function(id, parent, from, to) {
    list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.rewind",
         data = list(from = from, to = to, restore = "all"))
  }
  base = list(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"), e_asst("a1", "c1"),
              e_user("u2", "a1", "two", 2), e_cp("c2", "u2"), e_asst("a2", "c2"))
  undo1 = rw("r1", "a1", "a2", "a1")
  expect_identical(ckpt_redo_target(do.call(tree_of, c(base, list(undo1))))$to, "a2")
  redo1 = rw("r2", "a2", "r1", "a2")
  expect_null(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, redo1)))))
  undo2 = rw("r2", "f0", "r1", "f0")
  redo2 = rw("r3", "r1", "r2", "r1")
  expect_identical(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, undo2, redo2))))$to,
                   "a2")
  again = e_user("u3", "r1", "three", 2)
  expect_null(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, again)))))
})

test_that("builtin:checkpoints registers the four commands", {
  reg = gptr_registry("command")
  mine = reg$name[reg$source == "builtin:checkpoints"]
  expect_setequal(mine, c("undo", "redo", "rewind", "checkpoints"))
  undo = registry_get("command", "undo")
  expect_match(undo$description, "Undo the last turn")
})
```

Append to `tests/testthat/test-copy-ckpt.R`:

```r
test_that("gptr_checkpoints() reads only", {
  expect_no_copy(ckpt_e2e_setup("n = length(big)"),
                 c("s = peter('count', model = fake, mode = 'auto', envir = globalenv())",
                   "cp = gptr_checkpoints(s)"),
                 label = "gptr_checkpoints() after a checkpointed turn")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind|copy-ckpt")'`

Expected: the six new tests of `test-ckpt-rewind.R` fail (`could not find function "gptr_checkpoints"`, `"ckpt_cmd_undo"`, `"ckpt_cmd_rewind"`, `"ckpt_redo_target"`; the registry test finds no `builtin:checkpoints` commands) and the new copy row fails with `the script did not finish`; the 133 earlier rewind expectations and 66 copy expectations still pass.

- [ ] **Step 3: Write the implementation**

Append to `R/ckpt-rewind.R`:

```r
# ---- gptr_checkpoints() (contract 6.5, 5.12) ----------------------------------------------------

#' List the checkpoints of a session
#'
#' One row per turn of the active path (`all = TRUE` adds the turns of abandoned branches):
#' `turn`; `id`, the last entry of the turn (pass it as `to` to [gptr_rewind()]); `time`;
#' `prompt` (at most 60 characters); `objects` and `files`, `"changed/restorable"` counts;
#' `held_mb`, memory held by object pre-images; `disk_mb`, object images on disk; and `branch`
#' (`"active"` or `"abandoned"`).
#'
#' @param s A `gptr_session`.
#' @param all Also list the turns of abandoned branches.
#' @return A `gptr_checkpoints` data frame (it prints at most 20 rows).
#' @family checkpoints
#' @export
#' @examples
#' fake = gptr_fake_provider(list("done"))
#' s = peter("step", model = fake, envir = new.env())
#' gptr_checkpoints(s)
gptr_checkpoints = function(s, all = FALSE) {
  check_class(s, "gptr_session", "s")
  check_flag(all, "all")
  d = session_data(s)
  ck = ckpt_ck_of(ckpt_ext_state(s), s, create = FALSE)
  tree = ckpt_tree(d)
  active = ckpt_tree_path(tree, tree$leaf)
  rows = ckpt_turn_rows(tree, active, "active", ck)
  if (all) {
    for (leaf in setdiff(tree$ids, tree$parent)) {
      if (leaf %in% active) next
      r = ckpt_turn_rows(tree, ckpt_tree_path(tree, leaf), "abandoned", ck, exclude = active)
      rows = rbind(rows, r[!r$id %in% rows$id, , drop = FALSE])
    }
  }
  rownames(rows) = NULL
  new_listing(rows, "gptr_checkpoints",
              footer = "Rewind with gptr_rewind(s, <turn>) or gptr_rewind(s, to = \"<id>\").")
}

#' The empty checkpoint listing
#' @noRd
ckpt_turn_rows_empty = function() {
  data.frame(turn = integer(), id = character(), time = as.POSIXct(character(), tz = "UTC"),
             prompt = character(), objects = character(), files = character(),
             held_mb = numeric(), disk_mb = numeric(), branch = character(),
             stringsAsFactors = FALSE)
}

#' An ISO 8601 entry timestamp as POSIXct (UTC)
#' @noRd
ckpt_time = function(x) {
  x = ckpt_scalar(x, "")
  if (!nzchar(x)) return(as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"))
  as.POSIXct(sub("Z$", "", x), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
}

#' Change counts and image sizes of the checkpoint records among entry positions `idx`
#' @noRd
ckpt_segment_counts = function(tree, idx, ck) {
  n = c(objects = 0L, objects_ok = 0L, files = 0L, files_ok = 0L)
  held = 0
  disk = 0
  store_idx = if (is.null(ck)) ckpt_index_empty() else ck$obj$index
  ok = function(rows) sum(vapply(rows, function(r) isTRUE(r$restorable), NA))
  for (i in idx[tree$ctype[idx] == "gptr.checkpoint"]) {
    data = tree$entries[[i]]$data
    fo = ckpt_fragment(data, "objects")
    if (length(fo$objects)) {
      n[["objects"]] = n[["objects"]] + length(fo$objects)
      n[["objects_ok"]] = n[["objects_ok"]] + ok(fo$objects)
      rows = store_idx[store_idx$frag == ckpt_scalar(fo$id), , drop = FALSE]
      held = held + sum(rows$bytes[rows$where == "memory"], na.rm = TRUE)
      disk = disk + sum(rows$bytes[rows$where == "disk"], na.rm = TRUE)
    }
    ff = ckpt_fragment(data, "files")
    if (length(ff$files)) {
      n[["files"]] = n[["files"]] + length(ff$files)
      n[["files_ok"]] = n[["files_ok"]] + ok(ff$files)
    }
  }
  list(objects = paste0(n[["objects"]], "/", n[["objects_ok"]]),
       files = paste0(n[["files"]], "/", n[["files_ok"]]),
       held_mb = held / 1e6, disk_mb = disk / 1e6)
}

#' One listing row per turn of a path
#' @noRd
ckpt_turn_rows = function(tree, path, branch, ck = NULL, exclude = character()) {
  idx = match(path, tree$ids)
  ts = which(ckpt_path_starts(tree, path))
  if (!length(ts)) return(ckpt_turn_rows_empty())
  ends = c(ts[-1L] - 1L, length(path))
  out = list()
  for (j in seq_along(ts)) {
    if (path[ts[j]] %in% exclude) next
    seg = idx[ts[j]:ends[j]]
    cnt = ckpt_segment_counts(tree, seg, ck)
    prompt = ckpt_entry_text(tree, path[ts[j]])
    out[[length(out) + 1L]] = data.frame(
      turn = j, id = path[ends[j]], time = ckpt_time(tree$entries[[seg[1L]]]$timestamp),
      prompt = if (nchar(prompt) > 60L) paste0(substr(prompt, 1L, 57L), "...") else prompt,
      objects = cnt$objects, files = cnt$files, held_mb = cnt$held_mb, disk_mb = cnt$disk_mb,
      branch = branch, stringsAsFactors = FALSE)
  }
  if (!length(out)) return(ckpt_turn_rows_empty())
  do.call(rbind, out)
}

# ---- console commands (G7 section 4.2; contract 10.2 row 10) ------------------------------------

#' Run gptr_rewind() for a command: report lines, or the error's message
#' @noRd
ckpt_cmd_run = function(s, turn = -1L, to = NULL, restore = "all") {
  res = tryCatch(
    withCallingHandlers(gptr_rewind(s, turn = turn, to = to, restore = restore),
                        gptr_warning_rewind_partial = function(w) invokeRestart("muffleWarning")),
    gptr_error = function(e) e)
  if (inherits(res, "condition")) return(conditionMessage(res))
  d = session_data(s)
  lr = d$last_rewind
  title = paste0("Rewound (", lr$restore, ")",
                if (isTRUE(lr$partial)) "; some items were not restored:" else ".")
  c(title, lr$report, if (length(d$editor_text) && nzchar(d$editor_text)) {
    c("Undone prompt:", d$editor_text)
  })
}

#' Put the undone prompt into the console history, so Up recalls it (readline() cannot pre-fill)
#' @noRd
ckpt_history_push = function(text) {
  if (!length(text) || !nzchar(text[1L])) return(invisible(FALSE))
  if (!isTRUE(gptr_opt("history")) || !isTRUE(gptr_is_interactive())) return(invisible(FALSE))
  ok = tryCatch({
    utils::timestamp(stamp = text[1L], prefix = "", suffix = "", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)
  invisible(ok)
}

#' /undo: rewind the last turn; asks first when something cannot be restored
#' @noRd
ckpt_cmd_undo = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to undo.")
  plan = tryCatch(gptr_rewind(s, -1L, preview = TRUE), gptr_error = function(e) e)
  if (inherits(plan, "condition")) return(conditionMessage(plan))
  bad = plan[plan$restore %in% FALSE, , drop = FALSE]
  if (nrow(bad) && isTRUE(ctx$has_ui())) {
    ans = ctx$ui()$select("Some items cannot be restored. Undo anyway?", c("Undo", "Cancel"),
                          default = 2L, details = paste0(bad$item, ": ", bad$reason))
    if (!identical(as.integer(ans), 1L)) return("Undo cancelled.")
  }
  out = ckpt_cmd_run(s, -1L)
  ckpt_history_push(session_data(s)$editor_text)
  out
}

#' Is a `gptr.rewind` entry's data a redo: did it go back to where an earlier rewind (its `from`)
#' came from?
#' @noRd
ckpt_is_redo = function(tree, dat) {
  j = match(ckpt_scalar(dat$from), tree$ids)
  if (is.na(j) || !identical(tree$ctype[j], "gptr.rewind")) return(FALSE)
  identical(ckpt_scalar(dat$to), ckpt_scalar(tree$entries[[j]]$data$from))
}

#' The target of /redo: the `from` of the latest rewind on the active path that is not a redo
#' and was not redone already, when no turn started since. A redo is itself a rewind, so without
#' this a second /redo would undo the first one again.
#' @noRd
ckpt_redo_target = function(tree) {
  path = ckpt_tree_path(tree, tree$leaf)
  starts = ckpt_path_starts(tree, path)
  skip = character()
  for (k in rev(seq_along(path))) {
    if (starts[k]) return(NULL)
    i = match(path[k], tree$ids)
    if (!identical(tree$ctype[i], "gptr.rewind") || path[k] %in% skip) next
    dat = tree$entries[[i]]$data
    if (ckpt_is_redo(tree, dat)) {
      skip = c(skip, ckpt_scalar(dat$from))
      next
    }
    return(list(to = ckpt_scalar(dat$from), restore = ckpt_scalar(dat$restore, "all")))
  }
  NULL
}

#' /redo: go back to where the last rewind came from
#' @noRd
ckpt_cmd_redo = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to redo.")
  tgt = ckpt_redo_target(ckpt_tree(session_data(s)))
  if (is.null(tgt) || !nzchar(tgt$to)) return("Nothing to redo.")
  ckpt_cmd_run(s, to = tgt$to, restore = tgt$restore)
}

#' /rewind [k]: keep turns 1..k, or choose a turn and what to restore from a menu
#' @noRd
ckpt_cmd_rewind = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to rewind.")
  a = trimws(ckpt_scalar(args, ""))
  if (nzchar(a)) {
    k = suppressWarnings(as.integer(a))
    if (is.na(k)) return("Usage: /rewind [turn]")
    return(ckpt_cmd_run(s, turn = k))
  }
  cp = gptr_checkpoints(s)
  if (!nrow(cp)) return("Nothing to rewind.")
  if (!isTRUE(ctx$has_ui())) return("Use /rewind <turn> to keep turns 1..<turn>.")
  ui = ctx$ui()
  choices = c("Before turn 1", paste0("Keep turns 1-", cp$turn, ": ", cp$prompt))
  k = ui$select("Rewind to", choices, default = length(choices))
  if (is.na(k)) return("Rewind cancelled.")
  act = ui$select("Restore", c("Code and conversation", "Conversation only", "Code only",
                               "Never mind"), default = 1L)
  if (is.na(act) || act == 4L) return("Rewind cancelled.")
  ckpt_cmd_run(s, turn = k - 1L, restore = c("all", "conversation", "workspace")[act])
}

#' /checkpoints [all]: the listing
#' @noRd
ckpt_cmd_checkpoints = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session.")
  all = identical(trimws(ckpt_scalar(args, "")), "all")
  utils::capture.output(print(gptr_checkpoints(s, all = all)))
}

#' The command specs of builtin:checkpoints
#' @noRd
ckpt_commands = function() {
  list(
    gptr_command("undo", ckpt_cmd_undo,
                 description = "Undo the last turn: objects, files and the conversation"),
    gptr_command("redo", ckpt_cmd_redo, description = "Redo what the last rewind undid"),
    gptr_command("rewind", ckpt_cmd_rewind,
                 description = "Rewind to a turn: /rewind <k> keeps turns 1..k"),
    gptr_command("checkpoints", ckpt_cmd_checkpoints,
                 description = "List this session's checkpoints (/checkpoints all)"))
}
```

In `R/ckpt-rewind.R`, replace the whole `builtin_checkpoints()` definition of Task 6 (its roxygen block and body):

```r
#' builtin:checkpoints (contract 7.16, 10.3): the checkpointers `objects`, `files` and `state`,
#' the hooks above and the rewind `workspace_changes` context block; the service
#' `checkpoint.note` is declared at the top of this file
#' @noRd
builtin_checkpoints = function(gptr) {
  st = gptr$state
  st$sessions = new.env(parent = emptyenv())
  for (nm in c("objects", "files", "state")) gptr$register(ckpt_spec(st, nm))
  gptr$on("tool_result", function(event, ctx) ckpt_on_tool_result(st, event, ctx))
  gptr$on("agent_start", function(event, ctx) ckpt_on_agent_start(st, event, ctx))
  gptr$on("turn_end", function(event, ctx) ckpt_on_turn_end(st, event, ctx))
  gptr$on("agent_end", function(event, ctx) ckpt_on_agent_end(st, event, ctx))
  gptr$on("session_shutdown", function(event, ctx) ckpt_on_shutdown(st, event, ctx))
  gptr$register(gptr_context_block("workspace_changes", function(ctx, budget) {
    ckpt_rewind_block(st, ctx, budget)
  }, placement = "both", budget = 300L, order = 101L))
  invisible(NULL)
}
```

with (two changes: the roxygen text and the `for (cmd in ckpt_commands())` line):

```r
#' builtin:checkpoints (contract 7.16, 10.3): the checkpointers `objects`, `files` and `state`,
#' the hooks above, the rewind `workspace_changes` context block and the commands `undo`,
#' `redo`, `rewind` and `checkpoints`; the service `checkpoint.note` is declared at the top of
#' this file
#' @noRd
builtin_checkpoints = function(gptr) {
  st = gptr$state
  st$sessions = new.env(parent = emptyenv())
  for (nm in c("objects", "files", "state")) gptr$register(ckpt_spec(st, nm))
  gptr$on("tool_result", function(event, ctx) ckpt_on_tool_result(st, event, ctx))
  gptr$on("agent_start", function(event, ctx) ckpt_on_agent_start(st, event, ctx))
  gptr$on("turn_end", function(event, ctx) ckpt_on_turn_end(st, event, ctx))
  gptr$on("agent_end", function(event, ctx) ckpt_on_agent_end(st, event, ctx))
  gptr$on("session_shutdown", function(event, ctx) ckpt_on_shutdown(st, event, ctx))
  gptr$register(gptr_context_block("workspace_changes", function(ctx, budget) {
    ckpt_rewind_block(st, ctx, budget)
  }, placement = "both", budget = 300L, order = 101L))
  for (cmd in ckpt_commands()) gptr$register(cmd)
  invisible(NULL)
}
```

Regenerate the documentation:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: `NAMESPACE` gains `export(gptr_checkpoints)`; `man/gptr_checkpoints.Rd` is written.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind|copy-ckpt")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 236 ]` (169 in `test-ckpt-rewind.R`, 67 in `test-copy-ckpt.R`; without `capabilities("profmem")`: `[ FAIL 0 | WARN 0 | SKIP 6 | PASS 170 ]`).

- [ ] **Step 5: Commit**

```bash
git add R/ckpt-rewind.R tests/testthat/test-ckpt-rewind.R tests/testthat/test-copy-ckpt.R NAMESPACE man/gptr_checkpoints.Rd
git commit -m "feat(ckpt): add gptr_checkpoints() and the /undo, /redo, /rewind, /checkpoints commands"
```

## Plan acceptance

Every acceptance check of 05 P16 (including its review amendments), the task and test that prove it, and the command:

| # | Acceptance check (05 P16) | Proved by | Command | Expected |
|---|---|---|---|---|
| 1 | "`Rscript --vanilla -e 'devtools::test(filter = "ckpt\|copy-ckpt")'` is green" | all tests of Tasks 1-8 | `Rscript --vanilla -e 'devtools::test(filter = "ckpt|copy-ckpt")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 476 ]` (154 objects, 86 files, 169 rewind, 67 copy); without `capabilities("profmem")` the six copy tests skip: `[ FAIL 0 \| WARN 0 \| SKIP 6 \| PASS 410 ]` |
| 2 | "G7's 24-verdict tracemem matrix reproduces (including c03: a dropped pre-image leaves no sticky reference, and the serialize case)" | Task 1, `test-copy-ckpt.R`: "G7's 24-verdict tracemem matrix reproduces, c03 and c06 included (acceptance 2)" (24 rows: 8 COPY, 16 in place, exactly G7's `run_cases.R` output) and "user data is serialised without a sticky reference only with ascii = FALSE (R7)" (G7's five `dbg_ser.R` cases, the R7 image writer, the state finalizer of `c06b`) | `Rscript --vanilla -e 'devtools::test(filter = "copy-ckpt")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 67 ]` |
| 3a | "`gptr_rewind(s, 1)` after three mutating turns restores objects and files, appends one `gptr.rewind` entry, leaves the JSONL byte-append-only and the next request's prefix byte-identical" | Task 7, `test-ckpt-rewind.R`: "gptr_rewind(s, 1) after three mutating turns restores objects and files (acc. 3)" (objects back, created ones gone, the edited file back, turn 1's file kept, one `gptr.rewind` entry parented at the parent of turn 2's prompt and now the leaf, the old file bytes a prefix of the new, `req[[7]]$messages` minus its last equal to `req[[3]]$messages` minus its last, no `gptr.cache_break`) | `Rscript --vanilla -e 'devtools::test(filter = "ckpt-rewind")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 169 ]` |
| 3b | "a user edit made after the turn survives the 3-way restore; a partial restore warns `gptr_warning_rewind_partial`" | Task 7: "a user edit made after the turn survives the 3-way restore; the rewind warns" (object and file kept, the warning class, the report, the `<workspace_changes since="turn 1" reason="rewind">` block on the next request); Tasks 2 and 5 unit tests "undo keeps a binding changed after the turn (3-way) unless forced", "undo keeps a file edited after the turn (3-way) unless forced" | as 3a and `devtools::test(filter = "ckpt-objects|ckpt-files")` | as 3a; `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 240 ]` |
| 3c | "a running session errors `gptr_error_busy`" | Task 7: "gptr_rewind() refuses a running session and bad arguments" (a `tool_execution_start` hook calls `gptr_rewind()` on the running session) and "the IC-53 guard: rewinding another session from model code needs the one-shot token" (`busy` for a running session and for a run rewinding itself; `permission` without the token) | as 3a | as 3a |
| 4 | "Undone blocks in a bound document become inert (`#~ `, `status=undone`) and re-sourcing reproduces the rewound workspace" | Task 7: "undone blocks in a bound document become inert; re-sourcing reproduces the rewind" (two `status=undone` headers, `#~ ` lines, a second `source()` rebuilds `a = 1` without `b` and makes zero requests) | as 3a | as 3a |
| 5a | "a checkpoint record whose path lies outside the project is not restored without a human" (IC-52) | Task 5, `test-ckpt-files.R`: "a path outside the project and tempdir() is restored only after a human confirms" and "a planted record pointing outside the project is not restored without a human"; "restores never write into .git or gptr's user directories; control paths ask" | `Rscript --vanilla -e 'devtools::test(filter = "ckpt-files")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 86 ]` |
| 5b | "pruning in one process does not delete a blob another live session references" (IC-71) | Task 4: "pruning in one process keeps the blobs another live process's session references" (a real second R process holds the session lock: the collector skips; after it exits the blob survives because the session file references it) and "blob GC skips while another live process holds a session lock (IC-71)", "blob GC keeps referenced and young blobs and deletes old unreferenced ones" | as 5a | as 5a |
| 5c | review amendment: "after a Codex `workspace-write` exec the files checkpointer walks, so `/undo` covers it" (IC-65) | Task 5: "a forced turn scan records what a CLI child changed (IC-65)"; Task 6: "on a CLI route the files the child changes during a turn are checkpointed (IC-65)"; Task 7: "a CLI child's file edit is undone by gptr_rewind() (IC-65)" | as 3a and 5a | as 3a and 5a |

The M3 exit check (`/undo` and rewind on the fake provider, `devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")` clean) is P17's acceptance item 5 and runs once P14-P17 are complete; the P16 part of it is acceptance 1 above.

## Self-review

**Spec coverage (05 P16 scope -> task).**
- `ckpt-objects.R`: "pre-images as private-environment bindings released with `rm()`" -> Task 1 (`ckpt_capture()`, `ckpt_settle()`, `ckpt_drop()`); "defusing of list and S4 pre-images" -> Task 1 (`ckpt_defuse()`, G7 variant v5; copy rows c12, c12d, c12e); "capture policy and budgets of architecture §6.16" -> Task 2 (`ckpt_capture_how()`, `ckpt_objects_budget()`, options `gptr.undo_*`); "eager disk images with `serialize(ascii = FALSE, xdr = FALSE)`" -> Tasks 1-2 (`ckpt_capture_disk()`, `ckpt_spill()` through `serialize_leaf(xdr = FALSE)`); "data.table deep copies" -> Tasks 1-2 (`gptr_preimage.data.table()`, `how = "copy"`); "settle" -> Task 2 (`ckpt_objects_after()`); the exported `gptr_preimage()` S3 generic (IC-01) -> Task 1; the per-session state `ckpt_ck_new()` and its finalizer (G7 c06b; needed by Task 1's copy rows) -> Task 1; the `state` checkpointer -> Task 3; `checkpoint.note` -> Task 2 (function) and Task 6 (service registration).
- `ckpt-files.R`: "content-addressed store with XXH128" -> Task 4; "baseline and pruned walk" -> Task 5; "3-way restore" -> Task 5; "symlink and `.git` guards" -> Task 5 (`ckpt_restore_guard()`); IC-52 confinement -> Task 5; IC-71 collection -> Task 4; IC-65 walk -> Tasks 5-6.
- `ckpt-rewind.R`: "`gptr.checkpoint` and `gptr.rewind` entries" -> Task 6 (fragments into P06's container, scan entries) and Task 7 (`gptr.rewind`); "`gptr_rewind()`" -> Task 7; "`gptr_checkpoints()`" -> Task 8; "`/undo`, `/redo`, `/rewind`, `/checkpoints` commands" -> Task 8; "`builtin:checkpoints` registering the `checkpointer` kind's built-ins for objects, files and state" -> Task 6.
- Owns `test-copy-ckpt.R` -> Tasks 1, 7, 8. Every acceptance check -> the table above.

**Placeholder scan.** Searched the plan for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task": none. Every step that changes code shows the complete code; the only edit to earlier code (Task 8, `builtin_checkpoints()`) shows the full old and new definitions. Red-phase counts for the integration tasks (6, 7, 8) are stated as the failures to expect, because the exact count depends on how many expectations precede the first error in each test.

**Type and name consistency with 04.** Exports and arguments match 04 §6.5/§6.6 exactly: `gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"), force = FALSE, preview = FALSE)`, `gptr_checkpoints(s, all = FALSE)`, `gptr_preimage(x, name, ctx, ...)` returning `list(mode, reason, copy)`. Internal names match 04 §7.16 (`builtin_checkpoints(gptr)`, `ckpt_predict(code)`, `ckpt_store_put(path)`, `ckpt_store_get(hash, dest)`), the service `checkpoint.note` (`function(call, run)`), the checkpointer fields of 04 §10.2 row 29 (`scope`, `before`, `after`, `undo`, `redo`, `prune`, `describe`), the events of 04 §10.4 (`session_before_tree`, `session_tree`, `checkpoint` with `tool_call_id`, `objects`, `files`, `restorable`), the condition classes (`busy`, `rewind_range`, `invalid_argument`, `permission`, warning `rewind_partial` with field `report`), the listing class and columns of 04 §5.12, the store layout of 04 §11.14 and the option names and defaults of 04 §3.1. No P16 function name repeats a name another plan defines (checked against the `ckpt_` prefix: only P16 uses it; P23 calls `ckpt_store_put()`/`ckpt_store_get()`).

**Contract ambiguities and the readings chosen.**
1. IC-31 and 04 §7.11/§7.16 say `ckpt_predict()` wraps P11's `code_targets()`, but IC-33's kernel SDK (P01 `arch_kernel_sdk()`) does not list `code_targets`, and `perm-classify.R` is a plain L4 file. This plan follows IC-31 (the decision that names this exact edge). Resolved in P01's cross-plan consolidation: P01's `arch_contract_edges()` (`tests/testthat/helper-arch.R`) admits `ckpt-*.R` -> `code_targets()` while `arch_kernel_sdk()` stays the IC-33 list, so P01's `test-arch-layers.R` reports no P16 edge.
2. 04 §4.6 describes `gptr.checkpoint` data as "G7 §3.1 shape"; P06's dispatcher writes `{tool_call_id, fragments: {<checkpointer>: <fragment>}}`. P16 follows P06's container (P06 writes the entry); each fragment carries G7's per-scope content; `ckpt_fragment()` also reads the flat shape.
3. `gptr.rewind` data adds `undone` and `redone` (the checkpoint entry ids) to `{from, to, keep, restore, report}`; they let a later rewind know which records are applied after a reload. 04 §11 lets readers ignore unknown keys.
4. 04 §5.1 says `.d` is written only through P06's functions, while 04 §6.5 makes `gptr_rewind()` set `last_rewind` and `editor_text`; P06 has no rewind verb, so P16 writes `.d$leaf` (before `session_append()`, to parent the entry at the target), `.d$turns`, `.d$last_text`, `.d$status`/`.d$reason` (a terminal status becomes `idle`), `.d$last_rewind` and `.d$editor_text`.
5. 03 §6.16 and G7 §3.9 send `<workspace_changes since=... reason="rewind">` after a partial rewind, but `workspace_changes` is P09's block with no `reason` input. P16 registers a second `context_block` record named `workspace_changes` (order 101); the kind resolves `all` (P02's collision diagnostic covers only `first` kinds) and P07 renders the spec name as the tag.
6. P09's `workspace_changes` block (baseline: the `agent_end` snapshot in P09's private `ctx$state()`) will list objects a rewind restored as `~ name` lines on the next request, so "a full restore sends the model nothing" holds for P16's own block only; the byte-identical prefix of acceptance 3 is unaffected (the block is inside the new user message).
7. G7 restores environment variables and `.Random.seed` with the 3-way rule; 04 §12.3 forbids `Sys.setenv(` outside `auth-dotenv.R` and `.Random.seed` assignment outside `rng_swap()`/`with_seed_preserved()`, so the state checkpointer reports both as not restored.
8. 04 §7.10 lists P16 among the consumers of P10's `walk_files()` and `diff_lines()`, and §7.7 of `extract_state()`. `walk_files()`'s contract does not say how it treats symbolic links, hidden files or the `prune` argument, which G7's verified walker needs (links listed but not followed, git-ignored files included, `.gptr` pruned); P16 keeps G7's walker. `diff_lines()` and `extract_state()` would serve G7's preview diffs and `summarize = TRUE`, which 04 §6.5 does not include.
9. IC-65 asks for a files walk after a Codex `workspace-write` exec, but the Codex adapter (P20, later, L1) has no way to call P16. P16 detects a subscription-CLI route from the provider record (`type = "cli"`) and walks at every `turn_end` of such a session (the baseline is brought up to date at `agent_start`); the tests mock `ckpt_cli_session()`.
10. P11's detail view calls `checkpoint.note` as `(call, NULL)`; `ckpt_note()` then uses `run_current()`.
11. G7 §3.6 makes `turn = 0` "a null target (a new root)"; P16 keeps the entries before the first user message (the `gptr.frozen` entry), so resume and the frozen prefix stay valid.
12. IC-52 confines restores to "the project root and `tempdir()`"; P16 measures this against the current `project_root()` (never the root a session file records) and also asks for `control` and `critical` path classes (IC-54), a tightening.
13. Acceptance 4 relies on P15's `builtin:documents` writing blocks at once when `front_end()` is not `"rscript"` (04 §7.15: writes are "deferred under Rscript"); the test mocks `front_end()` to `"terminal"` and sets `gptr.record = "auto"` and `gptr.replay = "auto"`. P15's plan consumes exactly the `session_tree` fields P16 emits: its `doc_on_session_tree()` reads `from`, `to` and `report` and makes the `gptr.doc_block` blocks between them inert (`doc_set_inert()`), appending `gptr.doc_block` entries after P16's `gptr.rewind` entry (so the leaf after a rewind can be one of those entries; acceptance 3 counts only `gptr.rewind` entries).
14. IC-53 item 3: P16 consumes the one-shot token in `run$signal$control` exactly as P06's `session_control_check()` (the one IC-53 check, D-146) does; calling it would leave the IC-33 allowlist.
15. G7's `checkpoint` event payload had `turn` and summary counts; 04 §10.4 fixes `tool_call_id`, `objects`, `files`, `restorable`; P16 emits it from its `tool_result` hook (after P06 wrote the entry) with those fields (and `turn` in the standard event fields).
16. Once loaded, `builtin:checkpoints` takes part in every `peter()` run of the package: a mutating `r` call now gets a `gptr.checkpoint` entry (written by P06 by design). Tests of earlier plans that assert an exact entry sequence for such calls would see it; Task 6 Step 4 re-runs the dispatcher, `r` tool and permission suites to catch that.
17. 04 §4.6 says a `gptr.rewind` entry is "parented at the target, becomes the leaf". For `restore = "workspace"` (only objects, files and state; 04 §6.5) the conversation must stay where it is, so P16 parents that entry at the old leaf; `ckpt_wanted()` then reads such workspace-only rewinds on a path to know which records they undid. `s$editor_text` is `NULL` after a workspace-only rewind (no prompt was undone).
18. 03 §6.16 says the manual/edits permission detail view "offers 'spill first'" when capture is impossible. 04 gives no interface for it (the `checkpoint.note` service returns only `chr(1)` or `NULL`, and P11's detail view has no such action), so P16 provides the "cannot be undone: ..." note only; a spill-first action would need a contract change in 04 §7.0 and P11.
19. 04 §6.6 lists `ctx` fields `predicted`, `bytes`, `budget` for `gptr_preimage()`; P16 adds `dry` (`TRUE` for the `checkpoint.note` dry run, when a method must not copy). It is documented in `@param ctx`; methods that ignore it still work (they copy, and the dry run drops the copy).
20. 04 §10.2 row 29 runs checkpointers for every "sequential, non-read-only" tool. P16 additionally skips pure reads (`ckpt_pure_read()`: an R call at level 0 whose `ckpt_predict()` result is empty), which only saves a walk and a snapshot; a level-0 call that creates a binding (P11 rates `y = 2` level 0 because nothing existing is overwritten) is still checkpointed so a rewind removes it (G7 section 3.4 step 5).
21. G7 section 3.1 says spilled images carry `"where":"disk"` in the record, but a pre-image spilled at a turn end belongs to a fragment that P06 already appended (append-only). `ckpt_objects_undo()` therefore looks for `<root>/checkpoints/objects/<session id>/<image>.rdsx` whatever the row's `where` says (image keys are unique), and restores such an image of an earlier R process only with `force = TRUE` (the address check means nothing across processes).

**Executed validation.**
- Every `r` code block of this plan was extracted and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all 21 parse.
- Grep of the code blocks: no left-arrow assignment and no `%>%`; R sources are ASCII and at most 100 characters per line. P01's lint scanner (`lint_scan()` of `test-lint-rules.R`, copied from P01's plan) over the three assembled R files reports no hit (no `Sys.setenv()` call, no `.Random.seed` assignment, every `serialize()`/`saveRDS()` through `serialize_leaf()`, every `readLines()` with `encoding = "UTF-8"`, no `withr::`, no `:::`).
- Codetools' `findGlobals()` over the assembled files: every function the code calls outside P16 is one listed under "Interfaces consumed"; no top-level name is defined twice (Task 8's replacement of `builtin_checkpoints()` excepted).
- The R code of Tasks 1-5 was sourced with scratch stand-ins of contract shape for P01, P04, P06 and P11 (`code_targets()` approximated by G7's verified `ckpt_targets()` walker) and the real P09 `env_snapshot()` and P01 `fingerprint()` code copied from their plans, and the unit tests ran with testthat 3.3: Task 1 alone 54 expectations, Tasks 1-3 `test-ckpt-objects.R` 153, Tasks 4-5 `test-ckpt-files.R` 86 (with `NOT_CRAN=true`, including the real second R process), all passing; Task 2's red phase gives `[ FAIL 11 | ... | PASS 54 ]` against Task 1's code.
- The 24 G7 matrix rows and the 7 serialize/finalizer rows of `test-copy-ckpt.R` ran in fresh `Rscript --vanilla` processes through `expect_no_copy()`'s script layout against Task 1's code alone: every count equals G7's verdict (8 COPY, 16 in place; row c17 needs the address check, as in G7). Twelve further rows drove the full objects checkpointer (`ckpt_objects_before()`/`after()`, undo, redo, the turn-end budget, spill and restore from disk, a created and a removed object, a list and a data frame, the `checkpoint.note` dry run, a collected state): the user's next in-place edit copied nothing in every row (a data frame column copies once on its first `df$a[1] = 0` in plain R too, so that row counts the second edit).
- The pure tree tests of Task 7 (targets, applied/wanted records, the preview chain, the report lines), the IC-53 guard test and Task 8's `/redo` chain test ran against Tasks 6-8's code: 32 expectations passing; the `/redo` chain test fails against the plan's earlier `ckpt_redo_target()` (a second `/redo` undid the first).
- Not executed here: the `peter()`-driven tests of Tasks 6-8, the documents test and the end-to-end copy rows, which need the assembled package (P01-P15).
- Finalize pass (cross-plan consolidation log rows 3-5): with the same stand-ins, Task 1 alone gives 55 expectations, Task 2's red phase `[ FAIL 11 | ... | PASS 55 ]`, Task 2 green 129, Task 3's red phase `[ FAIL 4 | ... | PASS 129 ]` and Tasks 1-3 `test-ckpt-objects.R` 154, all as stated in the steps; the new POSIXlt test errors with "subscript out of bounds" against the earlier walk.

## Plan review log

Adversarial review of 2026-10-01 against 00-conventions, 04 (incl. §15), 05 P16, G7 and the dependency plans (P01, P02, P04, P06, P07, P09, P11, P15, P20). Every code block was re-extracted and parsed, linted with P01's scanner, and the self-contained parts were run in scratch (see "Executed validation").

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | blocker | Task 1, `test-copy-ckpt.R` prelude and the finalizer row | The child prelude fetched `ckpt_ck_new` (and the last serialize row called it), but `ckpt_ck_new()` was defined in Task 2, so at Task 1 Step 4 every one of the 31 copy rows failed with "the script did not finish" (reproduced in scratch: `object 'ckpt_ck_new' not found`). | applied | `ckpt_ck_new()`, `ckpt_ck_finalize()` and the unit test "a collected checkpoint state releases its images" moved from Task 2 to Task 1; Task 1 and 2 Produces/Consumes, red and green counts updated (Task 1 117, Task 2 128). Re-run: all 31 rows match G7 with Task 1's code alone. |
| 2 | blocker | Task 6 `ckpt_enabled()` | Every R call rated level 0 was skipped. P11 rates a binding that does not exist yet (`x = 1`, `b = a + 1`, `z = 1`) level 0, so turns that only create objects were never checkpointed and a rewind left their objects behind: Task 7's "redoes an abandoned branch" (`z`), "restore = 'workspace'" (`x`), "a fork never undoes ..." (no record, no warning) and acceptance 4's documents test (`b`) could not pass; G7 3.4 step 5 and 4.1 checkpoint every non-read-only tool and undo creations. | applied | New `ckpt_pure_read(call)`: only a level-0 call whose `ckpt_predict()` result is empty (no assign/modify/byref/remove/super/files/unknown/process) is skipped; `ckpt_enabled()` uses it; new Task 6 test "only pure reads skip the checkpointers; a level-0 creation is checkpointed"; intro text and self-review ambiguity 20. |
| 3 | major | Task 8 `ckpt_redo_target()` | A `/redo` is itself a rewind, so the latest `gptr.rewind` on the path after a redo pointed back at the undo: a second `/redo` undid the first one instead of answering "Nothing to redo." (the Task 8 test asserting that fails; reproduced with synthetic trees). | applied | New `ckpt_is_redo(tree, dat)`; `ckpt_redo_target()` skips redos and the rewinds they redid; new test "/redo follows chains of undos and stops after a redo" (fails on the old code, passes on the new); Task 8 text and counts updated. |
| 4 | major | Task 2 `ckpt_predict()` (cross-plan) | IC-31 makes `ckpt_predict()` call P11's `code_targets()` (L4 `perm-classify.R`), but P01's `arch_kernel_sdk()` does not list it, so P01's `test-arch-layers.R` reports the edge once P16 lands; the plan only mentioned it in the self-review. | applied | Kept the IC-31 call (the contract names it); added an explicit cross-plan note after Task 2 Step 4 with the exact edge the arch test reports and that P01's owner must add `"code_targets"` (P16 may not edit P01's helper); self-review ambiguity 1 stands. |
| 5 | minor | Task 2 `ckpt_objects_undo()` | An image of an earlier R process was looked up only when the fragment row said `where = "disk"`; a pre-image spilled at a turn end belongs to a row already written as `"memory"` (append-only), so after a restart it was reported as having no pre-image although the file existed. | applied | The lookup checks `<spill dir>/<image>.rdsx` whatever `where` says (keys are unique); new test "an image spilled at a turn end is found again by a new R process (force)"; self-review ambiguity 21. |
| 6 | minor | Task 7 IC-53 test | The end-to-end IC-53 test passes vacuously: P11 classifies `gptr_rewind(other)` as a control call and blocks it before P16's guard runs, so the guard and its one-shot token were untested. | applied | New unit test "the IC-53 guard: rewinding another session from model code needs the one-shot token" (mocked `run_current()`: permission without the token, the token consumed once, `busy` for the running session and for a run rewinding itself); acceptance row 3c cites it. |
| 7 | minor | Task 7 `gptr_rewind()` | `s$editor_text` was set to the undone prompt after `restore = "workspace"`, although the conversation did not move (and `/rewind` "Code only" printed "Undone prompt:"). | applied | `editor_text` is `NULL` after a workspace-only rewind; Task 7 intro states it. |
| 8 | minor | Task 6 `ckpt_rewind_block()` | The once-only rewind note was consumed by any provider call, including a `gptr_prompt()` preview, so the real next request could lose it. | applied | The note is cleared only when `ctx$input$preview` is not `TRUE` (P07's rendering input). |
| 9 | minor | Task 4 `ckpt_gc()` | Temporary blob names (`<hash>.tmp-<pid>`) left by an interrupted write were excluded from collection forever. | applied | `ckpt_gc()` deletes temporary names older than one day; the GC test plants one and checks it is gone (Task 4 28, Task 5 86). |
| 10 | minor | Task 1 intro, Plan acceptance row 2 | "7 COPY lines, 17 in-place lines": G7's output has 8 COPY and 16 in-place verdicts (the rows themselves were right). | applied | Text corrected in both places. |
| 11 | minor | Self-review | Item 13 said P15 was "not yet planned" (P15's `doc_on_session_tree()` exists and reads `from`, `to`, `report`); the workspace-only parenting (04 §4.6 says "parented at the target"), the missing "spill first" action of 03 §6.16, the additive `ctx$dry` of `gptr_preimage()` and the pure-read rule were not recorded. | applied | Item 13 rewritten; ambiguities 17-21 added; executed validation rewritten with this review's runs; Plan acceptance counts updated (474 -> 475 total after item 9). |
| 12 | minor | Tasks 2-8 expected outputs | Counts derived from the old test sets (and Task 6's red-phase estimate) no longer matched after fixes 1-9. | applied | Recounted: objects 153, files 86, rewind 169 (Task 6 35, Task 7 133), copy 67; acceptance 1 `PASS 475` (`SKIP 6`, `PASS 409` without profmem), 3b `PASS 239`, 5a `PASS 86`. |
| 13 | minor | `test-copy-ckpt.R` coverage | Suspected sticky references from the full objects checkpointer (`ckpt_unshared_bytes()` inside restore, `gptr_preimage()` dispatch, the state finalizer) that G7's matrix does not exercise. | rejected | Twelve extra scratch rows (see Executed validation) showed no copy on the user's next in-place edit; the one copying row (a data frame column) copies identically in plain R without gptr. No change needed. |
| 14 | minor | Task 5 `ckpt_through_link()` | Compares the resolved directory with an unnormalised one, so a raw `tempdir()`-style path under macOS `/var` reads as "through a link". | rejected | Every caller passes paths built from `path_norm()`ed roots (`project_root()`, fragment roots, `ckpt_call_paths()`); the only unnormalised input is a test path that is refused anyway (gptr's user directory). |
| 15 | minor | Task 6 Step 4 | The re-run of other plans' suites states `SKIP n \| PASS m` instead of exact numbers. | rejected | Those counts belong to other plans and change as they land; the pass criterion (`FAIL 0 \| WARN 0`) is exact. |
| 16 | minor | Task 6 context block | A second `context_block` record named `workspace_changes` next to P09's. | rejected | `context_block` resolves `all` (P02 keeps both; collisions are diagnosed only for `first` kinds); P07 keys its dedup hash by kind, so at worst P09's block is re-sent once; recorded as ambiguity 5. |

## Cross-plan consolidation log

Cross-plan check of 2026-10-01 against 04 (incl. §15), 05 and the related plans. Every `r` code block was re-extracted and parsed with `Rscript --vanilla` afterwards (all parse; no left-arrow assignment and no `%>%` in code).

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | minor | Self-review ambiguity 14 | applied | P08 defines the IC-53 token check as `control_check(what)` (P08 Task 1; its review row 5 renamed `gateway_control_check()`), and P06's is `session_control_check(what, s = NULL)`. Ambiguity 14 now names P08's `control_check()`. No code changed (P16 reads `run$signal$control` itself and calls neither check), so no test or count changes. |
| 2 | shared-names | minor | Self-review item 14 | applied (same edit as row 1) | Duplicate of row 1: the text named `gateway_control_check()`, which no plan defines. Fixed by the edit in row 1. |
| 3 | finalize | major | Task 1 `R/ckpt-objects.R`: `ckpt_addr_collect()`, `ckpt_unshared_walk()` | applied | Lint (seq_linter, 2 hits: `seq_len(length(x))`). `seq_along(x)` alone would have kept a latent crash: `length()` dispatches, so for a POSIXlt (`strptime()` results; 100 times report length 100 over 11 components) or a vctrs record the loop indexed `.subset2(x, j)` past the components and the estimator stopped with "subscript out of bounds" inside the objects checkpointer's after hook, `ckpt_restore()` and `ckpt_uncreate()`. Both walks now use `for (el in x)`, which visits the list's own components without dispatch; same values for plain lists and data frames. Checked in scratch that the walk leaves the user's list and data frame elements at the same reference counts as the old walk (with the pre-image held and after it is released), so copy safety (G7) is unchanged. Header delta list and the `ckpt_addr_collect()` roxygen note the change. |
| 4 | finalize | minor | Task 1 `test-ckpt-objects.R`; expected counts of Tasks 1-3 and Plan acceptance | applied | Regression test for row 3: "the unshared-bytes walk visits a classed list's components, not its length()" (a 100-element POSIXlt replaced by agent code; the estimate is over 800 bytes; it errors on the old walk). Counts: Task 1 red `FAIL 73` (11 erroring tests; `FAIL 11` without profmem), green `PASS 118` (55 + 63; `PASS 56` without profmem); Task 2 red `PASS 55`, green `PASS 129` (55 from Task 1); Task 3 red `PASS 129`, green `PASS 154`; acceptance 1 `PASS 476` (154 objects; `PASS 410` without profmem), 3b `PASS 240`. All re-run with the review's stand-ins (Executed validation, last item). |
| 5 | finalize | minor | Task 7 `test-ckpt-rewind.R`, "gptr_rewind(s, 1) after three mutating turns ..." | applied | Lint (brace_linter: multi-line function body without braces): the `Filter()` predicate that finds turn two's prompt now has a braced body. Same expectations, no count change. After rows 3-5, P01's linters (`indentation_linter = NULL`, `object_usage_linter` off for extracted blocks) report no lint over the 21 `r` blocks of this plan; every block parses with `Rscript --vanilla`, has no left-arrow assignment or `%>%`, and is ASCII with lines of at most 100 characters. No name was renamed. |
