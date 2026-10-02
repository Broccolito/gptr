
---

## 5. Core data structures

Mutable things are environments with an S3 class (session, registry, API object, ctx, reactor, run, job);
immutable values are classed lists or base-typed S3 vectors (D-02). No R6 or S7 in code or contract: G1
measured about 2x cheaper method calls and 13-16x cheaper creation than R6 (ratios; absolute times vary with
load) [G1 §2.3 and fact-check], G3 measured 5.5 KB vs 21 KB serialised sessions [G3 (1)]. JSON field names on
disk are Pi-compatible camelCase; R fields are snake_case (mapping in `provider-message.R`) [03 §4.2].

### 5.1 The session (`gptr_session`)

**Layout** [G3 (1)-(2), (9)-(10)]. The object the user holds is a classed *shell* environment whose only
binding is a hidden, unclassed data environment `.d` holding serialisable fields only. Live resources live in
a per-process registry, `the$live[[id]] = rlang::new_weakref(key = s, value = live)`, so an unreferenced,
settled session is garbage-collected and its finalizer removes the registry entry and the file lock. The
reactor holds a running session strongly until it settles.

| `.d` field | Type | Meaning |
|---|---|---|
| `id` | chr | `"s"` + 10 hex, RNG-free |
| `kind` | chr | `chat`, `team`, `fanout`, `child`, `replayed` |
| `parent_id`, `fork_of`, `depth` | chr, list(id, entry, turn), int | lineage |
| `status`, `reason` | chr | `idle`, `running`, `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`; reason text |
| `model`, `thinking`, `mode`, `preset` | chr | canonical `provider/id`; clamped thinking level; mode; preset |
| `rules` | list | session permission rules |
| `frozen` | list | `t0`, `t1` (system text), `tools_json` (once-serialised array), `tool_names`, `sections` (names and hashes) |
| `entries`, `index`, `leaf` | list, env-free index, chr | append-only transcript (5.2); this object's leaf id |
| `turns`, `seen` | int, chr | turn counter; replayed block ids already applied |
| `last_text` | chr | last final assistant text |
| `values` | list | value records by turn: `list(turn, mode = "name" \| "copy" \| "box", name, address, value)` |
| `queue`, `dropped` | list | `steer` and `follow_up` FIFOs of `list(text, source, t)`; items dropped by abort |
| `usage` | data frame | one row per request (5.5), children rolled up by id |
| `budget`, `max_turns` | list, int | limits |
| `children` | named list | child sessions (team members, fan-out elements, nested calls) |
| `doc` | list | document binding: path, format, site (statement, ordinal), block ids |
| `file` | chr | JSONL path (`.gptr/sessions/` or `tempdir()/gptr/sessions/`) |
| `home_label` | chr | description of the workspace (`globalenv`, `overlay of <id>`, `<environment>`), never the environment |
| `plan` | chr | pending plan text (plan mode) |
| `replayed`, `block` | lgl, chr | set for replayed sessions |
| `snapshot` | data frame | last workspace snapshot (names, addresses, fingerprints; no values) |
| `ext` | list | per-plugin session state (JSON-able, persisted as custom entries) |

| `live` field (weak registry value) | Meaning |
|---|---|
| `home` | the kept workspace: `globalenv()`, an explicit `envir =`, or a fork overlay; **never a function frame** |
| `run` | the run environment while running; its `frame` binding (a function-frame home) is reset to `NULL` at settlement, before the run is dropped (§6.4 R2) |
| `listeners` | session-scoped hooks (never copied by fork) |
| `store` | open append connection (`"ab"`), lock path `<file>.lock/pid` |
| `background`, `ctx` | background handle (experimental); the `ctx` object handed to handlers |

**Accessors** (`$.gptr_session`, `[[`, `.DollarNames`): `text`, `value`, `values`, `usage`, `cost`,
`history` (data frame: turn, role, preview, tools, tokens), `messages`, `model`, `mode`, `status`, `id`,
`turns`, `kind`, `envir` (the kept home or `NULL`), `ext`, and child names for teams (`reviews$stats`).
`print()` shows the last answer and a dim footer `status . model . turns . tokens . cost . id`;
`format()`/`as.character()` return the text; `summary()` and `str()` never touch user objects; `knit_print`
is registered lazily. `$<-` and `[[<-` are refused with `gptr_error_readonly`: state changes go through verbs
(G3 t1).

**Value policy** (`gptr_return(x)`, D-05) [G3 (7), J-req graft, judge copy checks]:

| Case | Held as | `$value` |
|---|---|---|
| symbol bound in a kept home, object below `gptr.value_copy_max` (1 MiB) | deep copy (faithful history) | the copy |
| symbol bound in a kept home, larger | **name + address** (no reference) | `get0(name, home, inherits = FALSE)`, a live view; a message if the name was re-bound |
| anonymous expression, or symbol in a function-frame home that will vanish | boxed value | the box |

Held copies and boxes are capped by `gptr.values_max_bytes` (64 MiB; oldest released first, the latest always
kept). A value that captures an environment (an `lm`'s `terms`, a closure, a ggplot) evaluated in a
function-frame home keeps that frame alive, as any such object does in R; this is documented (G3 fact-check).
In a replayed session the value name comes from the block header's `value=` key; generated documents never
contain a `res$value = fit` line.

**Pipe rule** (S-8) [G3 (3)-(4)]: `s |> gptr("p")` on an idle, errored, aborted, interrupted or re-attached
session starts a new prompt turn on the same object and file and returns `s`; on a running session it
enqueues a steer (`as = "follow_up"` optional through `gptr_steer()`) and returns `invisible(s)` at once. It
never starts a nested run and never forks.

**Persistence and attach** [G3 (10)]: sessions hold data only (a 3-turn session serialises to about 15 KB), so
`saveRDS()`, knitr caches and callr produce detached copies. Continuing a copy: a live original in the same
process -> `gptr_error_split_brain`; another live process holding the pid lock -> split brain; otherwise the
copy continues from its own leaf and the file gains a sibling branch. `gptr_resume(x = NULL | id | path)`
returns the live object or rebuilds from JSONL (status `idle` if the tail is a final answer, else
`interrupted`).

### 5.2 Transcript entries, messages and content blocks (INFRA-07)

Pi v3 shape: a header line `{"type":"session","version":3,"id","timestamp","cwd","parentSession",
"gptr":{"version","api","forkOf"}}`, then entries `{type, id, parentId, timestamp, ...}`. Entry types:
`message` (roles user, assistant, toolResult), `model_change`, `thinking_level_change`, `compaction`,
`custom` (`gptr.*`: `doc_block`, `decision`, `value`, `checkpoint`, `rewind`, `replay`, `subagent`,
`artifact`, `section_patch`, `mode_change`, `cache_break`, `plan`). gptr additions sit in fields Pi ignores
[G3 (16), verified against Pi's loader]; Pi-readability is best effort, not a contract [J-cran D-09].

```r
msg_user(content, source = c("prompt", "pipe", "steer", "follow_up", "repl", "context", "parent"))
msg_assistant(content, api, provider, model, response_id = NULL, usage = NULL,
              stop_reason = c("stop", "length", "tool_use", "aborted", "error", "refusal", "pause"),
              error_message = NULL)
msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL)
```

| Block | Fields |
|---|---|
| `text` | `text`, `signature` (opaque, optional) |
| `thinking` | `thinking`, `signature`, `redacted`, `data`, `origin` (api, provider, model) |
| `image` | `mime`, `data` (base64 without newlines), `source` (plot, file, screenshot), `width`, `height` |
| `tool_call` | `id` (provider id verbatim, e.g. `call_id\|item_id`), `name`, `arguments`, `raw_arguments`, `thought_signature` |
| `opaque` | `provider`, `api`, `json` (verbatim string: encrypted reasoning, `phase`, server-tool blocks), replayed byte for byte to the same model only |
| `context` | `kind` (project_instructions, environment, mode, plan, workspace, workspace_changes, attached, skill_content, agent_reports, checkpoint), `attrs`, `text`, `anchor` |

`details` of a tool result never reaches the model; it carries the R-side record (code, record flag, note,
objects added/modified/removed, plots, warnings, status, spill path, nested calls, checkpoint id).
Projection before every request never edits stored entries: aborted and errored assistant entries are
dropped, orphaned calls get "interrupted after 2.3 s; side effects may have occurred" or "No result
provided", steering relays sit after complete tool-result messages, and the hand-off transform applies
(same model keeps signatures and opaque items; otherwise thinking becomes text or is dropped, opaque data is
dropped, ids are normalised) [10a INFRA-04/08, 02 §2.7].

### 5.3 Tool spec and tool result

A tool spec is `gptr_tool(...)` (§4.3). The dispatcher adds `schema_json` (once-serialised, sorted keys),
`r_signature` (one line: `grep(pattern: string, path?: string, ...)  # first sentence`) and `token_cost`.
Contract: `execute(input, ctx)` returns a `gptr_tool_result()`, a character vector or a list with `text`,
`images`, `value`, `is_error`; the R-callable `fun` returns an R value whose `print()` is budgeted.

```r
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
# -> list(content = list(<text block>, <image blocks>...), details, is_error,
#         value (R side only), spill = <path or NULL>, truncated = <lgl>)
```

### 5.4 Events (D-25)

Every event is `list(type, session, run, agent, turn, ts, ...)`; streaming updates are delta-only, never the
partial message (quadratic copies) [02 §4.4]. Every event passes the redactor's `stream` profile before any
subscriber sees it. Provider layer (INFRA-02): `start`, `text_start|delta|end`, `thinking_start|delta|end`,
`toolcall_start|delta|end` (throttled partial-argument preview), `done(reason)`, `error(reason, partial)`.

| Event | Semantics | Handler may return |
|---|---|---|
| `session_start` / `session_end` | collect (before the prompt freezes) / notify | `list(sections, blocks)` / - |
| `input` | transform chain | `list(action = "continue" \| "transform" \| "handled", text)` |
| `agent_start`, `agent_end`, `turn_start`, `turn_end` | notify | - |
| `before_request` | notify, read-only (a handler that changes the frozen prefix triggers `cache_break`) | - |
| `message_start`, `message_update`, `message_end` | notify (update is delta-only) | - |
| `tool_call` | decision, **error = deny** | `list(decision, reason, input)` |
| `permission_request` | first decision, **error = deny** | `list(decision = "allow" \| "deny", reason)` |
| `tool_execution_start`, `tool_execution_update`, `tool_execution_end` | notify | - |
| `tool_result` | patch chain | `list(content, details, is_error)` |
| `queue_update`, `retry_start`, `retry_end` | notify | - |
| `pre_compact` / `post_compact` | first decision / notify | `list(cancel, result)` / - |
| `session_before_tree` / `session_tree` | first decision / notify (rewind, G7) | `list(cancel)` / - |
| `document_write` | block + patch, **error = block** | `list(block, reason)` or `list(lines)` |
| `decision` | notify (System 1 summary) | - |
| `route`, `model_select` | notify | - |
| `subagent_start`, `subagent_end` | notify | - |
| `artifact_start`, `artifact_stop` | notify | - |
| `usage`, `budget_near`, `budget_exceeded` | notify | - |
| `cache_break` | notify (prefix guard culprit) | - |
| `bridge_call` | notify ({bridge, id, redacted cmd, level, status, seconds, bytes out/err, spill, digest}) [G5] | - |
| `checkpoint` | notify (G7) | - |

Canonical names are Pi-derived where semantics match; Claude and Codex hook names (`PreToolUse`, ...) are
accepted only by the hook importer's alias map (v1.x), and `gptr_on(s, "PreToolUse", ...)` fails with "did you
mean 'tool_call'?" [G1 §3.2]. Records are indexed by event; rank order: session 0, project 1, user 3, plugin 5,
built-in 6. Handlers return patches, never mutate (R lists have value semantics) [05 §4]. Hook-injected
context is capped at 10,000 characters [20 §3.7]. Rewriting earlier entries is not offered (append-only);
plugins add context through `context_block` specs.

### 5.5 Usage, cost and the token ledger (INFRA-20)

One row per request in `.d$usage`:

```text
request_id session agent parent_id provider model route input output cache_read cache_write_5m
cache_write_1h reasoning images cost tier stop_reason started seconds estimated multiplier
```

`route` is `api`, `plan-cli`, `system-one` or `emulated`. `estimated` is TRUE when the provider reported
nothing (aborted before usage); the calibrated estimator fills the row. Cost uses dated price tiers (1 h cache
writes at 2x input, 5 min at 1.25x, reads at the model's own rate, 0.025-0.1x) [07 §1, G2 fact-check]; CLI plan
runs record `total_cost_usd` as an estimate. System 1 calls outside a session append to a process accounting
log (append-only, not run state). The **token ledger** (`gptr_usage(s, detail = TRUE)`, `/context`) splits each
request into components: T0 sections, T1 sections, tools array, project block, environment, workspace, attached,
transcript, tool results, images, marking cache reads [P-C §14.6, G2 est_* fields].

### 5.6 System 1 typed vectors [04 §4.5]

| Class | Base type | Attributes |
|---|---|---|
| `c("gptr_decision", "gptr_s1", "logical")` | logical | `names`, `prob` (P(yes)), `threshold`, `meta` |
| `c("gptr_choice", "gptr_s1", "character")` | character | `names`, `s1_levels` (options in request order; never `levels`), `probabilities` (matrix, rows = states), `confidence`, `meta` |
| `c("gptr_score", "gptr_s1", "numeric")` | double (expected 0-based level) | `names`, `s1_levels`, `probabilities`, `confidence`, `meta` |

`meta = list(model = "jev-1.13.0", alias = "jev-latest", engine = "typesafe" | "emulated:structured",
calibrated, question, date, cached, errors, usage, request_ids)`. Methods: `[`, `[[`, `[<-` (degrades to the
bare vector for foreign values), `c`, `rep`, `format` (`TRUE (p=0.93)`), `print`, `as.data.frame`,
`as.logical`/`as.character`/`as.double`, and `Ops`/`Math`/`Summary` group methods returning bare vectors (so
`cell_type == "unclear"` is a plain logical); vctrs proxy/restore registered lazily.

### 5.7 Artifacts [17 §4, P-B graft]

```text
<root>/artifacts/<id>/app.R               working copy (the model writes and edits it)
<root>/artifacts/<id>/artifact.json       {id, title, kind, versions, current, data: [{name, class, dim, bytes}], session}
<root>/artifacts/<id>/vNNN/               immutable snapshot per launch: app.R, R/gptr_data.R, data/<name>.rds
<root>/artifacts/<id>/run/                run.json {pid, port, url, version, started}, port, app-vNNN.log (gitignored)
```

`<root>` is `.gptr` in a consented workspace (so NS-8's `.gptr/artifacts/marker-explorer/app.R` is literal),
else `tempdir()/gptr`. Handle `gptr_artifact`: `list(id, title, version, url, path, status, checks, screenshot,
session)`. Data snapshots use a leaf `saveRDS(compress = FALSE)` wrapper, capped by `gptr.artifact_max_bytes`
(500 MB) (§6.4 R7).

### 5.8 Sub-agent handles

A child is a `gptr_session` with `kind = "child"` plus `backend` (`inline`, `worker`, `cli`), `agent`
(definition name), `exports` (names written back on success) and, out of process, a private `proc` record
(process handle, spec path, result path, events seen). Inline children evaluate in an overlay
`new.env(parent = envir)` with their own L'Ecuyer RNG stream swapped in around evaluations [15 §4.5, §5.12].
Worker and CLI children are proxies whose entries are rebuilt from JSONL events.

### 5.9 Settings

Layers, lowest to highest: package defaults < user `R_user_dir("gptr", "config")/settings.json` < project
`.gptr/settings.json` (only when trusted; may only tighten `mode`, `permissions`, `context`, egress) <
`.gptr/settings.local.json` (remembered permission answers, gitignored) < `options(gptr.*)` <
`gptr_config(.scope = "session")` < call arguments. Keys: `model`, `small_model`, `system1`, `mode`,
`preset`, `tools{enable, disable}`, `permissions{allow, ask, deny}`, `context`, `record`, `replay`,
`transcript`, `plugins`, `filters`, `skills{paths}`, `mcp{exposure}`, `subagents{max_depth, max_active,
max_workers}`, `output_tokens`, `plot{width, height, res}`, `budget{tokens, cost}`, `cache{ttl}`,
`providers{<id>: {...}}`, `egress{<provider>: "ack"}` (user scope only). Plugin settings register as
`setting` specs and are read through `gptr_config()`.

### 5.10 Specs and registry records

A spec is `list(kind, name, ...)` of class `c("gptr_<kind>", "gptr_spec")`, validated by its kind
(§11.1). A registry record adds `rank`, `source` (`builtin:<name>`, `plugin:<pkg>`, `user`, `session`),
`state` (`lazy`, `active`, `overridden`, `disabled`), `generation` and `tokens` (declaration cost).

### 5.11 Checkpoint records (G7)

`custom` entries of type `gptr.checkpoint` appended after each mutating tool result: object names, addresses,
sizes, classes and capture mode (`ref`, `image`, `none: reason`), file paths with content hashes (XXH128) and
modes, artifact `current` before/after; never values or environment-variable values. `gptr.rewind` entries are
parented at the rewind target and make it the durable leaf.
