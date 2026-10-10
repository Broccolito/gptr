# gptr 1.0 — Interface contract (definitive)

Status: final, design phase, 2026-09-30. Author: interface-contract author (design phase).
Inputs, in order of authority: `00-vision-brief.md` (REQ-nn), `01-decision-register.md` (S-n, D-nn, C-nn),
`03-architecture.md` (names, layers, mechanisms; cited as `03` §x, while a bare §x refers to this document), `05-plan-decomposition.md` (plans P01-P25),
`dev/plan/00-conventions.md` (Global Constraints), the research reports (their verification logs override their
bodies) and the proposals. This document fixes, for every function that crosses a plan boundary and every
exported function, the owning plan and file, the full signature, argument types and validation, the return
value, the conditions, the side effects and the events; and it fixes every record, S3 class, file format,
option, environment variable and test helper that more than one plan touches. Implementation agents code against
this document without talking to each other. Where this document and `03-architecture.md` differ, this document
wins and the difference is listed in §13 (and `03`/`05` were edited to agree). The review amendments of §15
(IC-32..IC-73, 2026-09-30; issue-by-issue record in `06-review-resolution.md`) win over every earlier section of
this document; the sections they touch were edited in place. All code uses `=` for assignment and `|>` for pipes
(S-9); untrusted text is never a cli/glue format string (rule C1).
The 2026-10-03 local-provider amendment **IC-74** below incorporates
`07-local-ollama.md` and overrides earlier conflicting Jev-only assumptions.

---

## 0. How to use this document

### 0.1 Reading order and scope

An implementer of plan Pnn reads `dev/plan/00-conventions.md`, `03-architecture.md`, then this document's §1-§5
(conventions, conditions, options, records, classes), then the sections for the functions their plan **owns**
(§6 exported, §7 internal by plan) and the functions their plan **calls** (find the owner in §7, which is organised by plan, in the service table §7.0, or in the export index §14.1).
§8 (adapters, reactor), §9 (tools and prompt texts), §10 (extension API), §11 (file formats) and §12 (test
infrastructure) are normative references used by several plans.

"Crosses a plan boundary" means: defined in a file owned by one plan and called, registered, subclassed or read by
code or tests owned by another plan. Functions used only inside their own plan are implementation details and are
not listed; a plan may add private helpers freely (with `@noRd`) but may not change anything specified here.

### 0.2 Normative words and stability tags

MUST, MUST NOT, SHOULD, MAY have their RFC 2119 meanings. Every public item carries a stability tag:

| Tag | Meaning |
|---|---|
| **[stable]** | part of extension API 1.0 (§10.9); changes only additively in MINOR API releases |
| **[experimental]** | may change in a MINOR API release; documented as experimental (background sessions, the Claude-plan route, `artifact_type`, `frontend`, `interpreter`, `checkpointer`, `route`, plugin-defined kinds) |
| **[internal]** | not exported; stable only between plans of this release (changing it needs a contract edit) |

### 0.3 Contract decisions added by this document

These decisions were not fixed (or were fixed inconsistently) by `03`/`05`; they are binding. §13 lists the edits
made to `03` and `05` so that the three documents agree.

| Id | Decision | Reason / evidence |
|---|---|---|
| IC-01 | **63 exports**: the 62 of `03` §4.4 plus the S3 generic `gptr_preimage()` (P16). | `03` §6.16 and §11.1 promise "plugins add `gptr_preimage()` S3 methods"; delayed registration `S3method(gptr::gptr_preimage, cls)` from a package that only Suggests gptr needs an exported, documented generic, exactly like `gptr_describe()` [G7 §4.6, G1 §3.1 row 13]. |
| IC-02 | (amended by IC-34/IC-69: 38 kinds in all, P02 defines 37 and P22 adds `interpreter`; §10.2.) A 31st registry kind, **`route`** [experimental], carries the gateway routes (classifier, nested, console, team, fan-out, document, continue, new). P02 defines 30 kinds (the 29 of `03` §11.1 other than `interpreter`, plus `route`); P22 defines `interpreter` through the `kind` meta-kind. | `03` §2.2 rule 1 and 05 "Registration without shared lists" require routes to be registry records contributed by their owning plans; no kind existed for them. |
| IC-03 | Event names follow D-25's rule (Pi-derived where the semantics match): **`session_shutdown`** replaces `session_end`, **`session_before_compact`** / **`session_compact`** replace `pre_compact` / `post_compact`. | D-25, G1 §3.2 (Pi's names); `03` §5.4 used Claude-style names that D-25 reserves for the v1.x importer. |
| IC-04 | The permission **combination** `perm_check()` (policies, `permission_request` hooks, UI, non-interactive stop) lives in `agent-dispatch.R` (P06); `perm-gate.R` (P11) owns the built-in **policies** (mode table, rules, critical guard, secret guard, protect size) and `builtin:permissions`; the UI's `permission()` method (console prompt) is in `console-ui.R` (P11). | `03` §3.2 gave "policy combination" to P11 while P06's dispatcher must already gate fail-closed at M1; the split keeps the kernel complete and the policies pluggable (S-11). |
| IC-05 | `gptr_usage()` is defined in `session-budget.R` (P06), not `provider-usage.R` (P05). | layering: an L1 file may not reach sessions (L3) (`03` §2.2). P05 keeps usage rows, prices and the process System 1 log. |
| IC-06 | `gptr_permissions()` is defined in `perm-rules.R` (P11); `gptr-config.R` (P08) provides only the settings I/O it uses. | `03` §3.2 and `05` gave it to both P08 and P11. |
| IC-07 | `knit_print` methods (sessions, System 1 vectors) exist only in `doc-knitr.R` (P15). | `03` §3.2 gave them to both P06 and P15. |
| IC-08 | The fake adapter is declared as built-in `builtin:fake` by P05 (`provider-registry.R`), using `builtin_fake()` from P01's `provider-fake.R`. | P01 precedes the extension API (P02); `on_load()` expressions naming `ext_declare_builtin()` cannot live in P01's files. |
| IC-09 | A **service table** (`ext_service_set()`/`ext_service_get()`/`ext_service_has()`, P01 `utils-options.R`) late-binds `ctx` members and every cross-plan call whose provider plan comes later in the build order (for example P06's run calls P07's context assembly, and every layer reads settings through `setting_get()`, which uses P08's `settings.get` service); an unbound service raises `gptr_error_not_available`, or the caller uses its documented fallback. | P02 scope ("members whose services arrive later return a classed 'not available' error"); the 05 dependency graph and the `03` §2.2 layering test forbid direct backward calls. |
| IC-10 | Records (content blocks, messages, transcript entries, events, usage rows) are **unclassed named lists**; `type`/`role` is the discriminator; R fields are snake_case, JSON fields Pi camelCase through one mapping table (§4.8). | speed and byte-exact JSON round trips [03 §4.2, 19 §2.2]. |
| IC-11 | `ctx` also offers `get(kind, name)`, `secret(name)`, `aborted()` and `update(text)`; inter-plugin channels are events whose name contains `:` (`"myplugin:done"`), subscribed with `gptr$on()` and raised with `ctx$emit()`. | G1 §3.3, G6 §4.8; one dispatch mechanism instead of a second bus. |
| IC-12 | (amended by IC-36: `gptr_jobs()` itself moved to `proc-supervise.R`, P04.) A **job table** in `proc-supervise.R` (P04) records every supervised child and background session, so `gptr_jobs()` lists bridge jobs (P22) and artifacts (P23) without a back-dependency. | 05 dependency graph (P21 precedes P22). |
| IC-13 | The gateway passes one **`gptr_call`** record (an environment) to routes; its frame binding is reset at settlement (`03` §6.4 R2). | routes are contributed by five plans and need one shape. |
| IC-14 | `options(gptr.noninteractive_ask)` takes `"stop"` (default: status `blocked` + `gptr_error_permission`) or `"deny"` (the model gets a denial). | `03` §6.8.5 vs report 18's older default. |
| IC-15 | Plan mode's scratch environment is created by the run (P06) when the effective mode is `plan`; P11 owns the `plan` policy, `<proposed_plan>` capture, the pending-plan store and the execute menu. | the `r` tool (P10) must know where to evaluate before P11 exists. |
| IC-16 | `inprocess` adapters return a **generator** pumped by `reactor_task()`, so fake agents interleave deterministically on the reactor (INFRA-16 tests). | `03` §6.1, INFRA-16. |
| IC-17 | The `minimal` preset texts and the `extended` preset's direct `grep`/`find`/`ls` schemas are fixed verbatim in §9 (minimal texts measured in `final/prompt/`; the three schemas are Pi's, MIT [01 §3.6-3.8]). | `03` §7 gave only the standard texts. |
| IC-18 | `.gptr/extensions/` (trust-gated `function(gptr)` files) and `.gptr/locks/` are part of the workspace tree. | D-16 extensions; 14 §4.3 document locks. |
| IC-19 | Model references for the plan routes: provider ids `claude-cli` (alias `claude_code`) and `codex` (alias `codex`); System 1 emulation references are `"emulate:<provider>/<id>"`. | D-15, `03` §8.2-8.4. |
| IC-20 | Session ids `s` + 10 lower hex; entry ids 8 lower hex; block ids 6-16 lower hex with at least one letter; request ids `q` + 12 hex; run ids `u` + 8 hex; transfer/task/timer ids `t<integer>`. | `03` §5.1, 02 §3.1, 14 §3.1. |
| IC-21 | `gptr_fake_provider()` gains `type = c("chat", "classifier")` so System 1 examples and tests run offline (§12.1). | every export's example must run offline (conventions §4); NS-4 examples need a classifier. |
| IC-22 | `gptr_context_block()` gains `order = 650L`: `all`-resolving kinds must not order user blocks (rank 3) before the built-in first-message blocks (rank 6). | §7.4 of `03` fixes the first-message order. |
| IC-23 | Specs carry `api_version` (the extension API version), not `api`, which is the wire-api field of providers and adapters. | a name clash in `03` §5.10 / G1. |
| IC-24 | `builtin:gateway` (P08) registers the routes `nested`, `continue`, `new` and the core `setting` specs. | routes and settings need an owner; P08 owns the gateway. |
| IC-25 | A T1 `plugins` section (order 860, budget 1,500) lists plugin `r` members; P10 builds it (`ns_catalog()`). | §4.2 of `03` ("one signature line each enters the frozen ... plugin catalog") had no section. |
| IC-26 | The API object and `ctx` use no binding locks (P01's lint forbids `lockBinding()`); their `$<-`/`[[<-` methods refuse assignment. | rule R5 and the P01 lint rule vs G1 §3.3's locked bindings. |
| IC-27 | (amended by IC-68: `documents`, `artifacts`, `system1` are registered by P15, P23, P13, and `<rules>`/`<r_session>` are composed from owners' guidelines and fragments.) P07 owns every built-in section text, including `documents`, `artifacts`, `system1`, each with an inclusion predicate on `ctx$input`; `skills`, `mcp`, `plugins`, `r_env` are registered by P17, P18, P10, P09. | P07 acceptance 2 needs byte-identical texts of §7.3 of `03` in one file. |
| IC-28 | Four dependency edges are added to `05`: P04 -> P05 (`provider_stream()` runs on the reactor), P09 -> P13 (`describe_binding()` for System 1 states), P14 -> P19 (worker children write the `jsonl` frontend), P12 -> P20 (`cli-claude` reuses the Anthropic normaliser). | every other backward use goes through a service (§7.0); the graph stays acyclic. |
| IC-29 | `egress_check()` lives in `gptr-config.R` (P08), next to the acknowledgement it records; P05 only reads acknowledgements through `setting_get()`. | the check needs the settings writer (P08); `03` §3.2 listed it for both files. |
| IC-30 | Replay mode is resolved by `replay_mode()` in P08, and `replay_guard()` refuses non-`offline` providers in replay mode; `gptr_fake_provider()` specs are `offline = TRUE`, so `GPTR_REPLAY=replay` in `tests/testthat/setup.R` blocks real models but not the fake. | `03` §3.4 sets `GPTR_REPLAY=replay` for every test while every test drives the fake provider. |
| IC-32..IC-73 | Review amendments (load order, layering allowlist, services, replay, safety kernel, store, processes, RNG, encoding, CLI routes, budgets, prompt composition, extension-API additions, release). | §15; `06-review-resolution.md`. |
| IC-31 | The classifier's parse walk `code_targets()` is P11's; P16's `ckpt_predict()` wraps it. Prompt templates become `command` specs registered by P17, so the console (P14) only dispatches commands. | the shared walk of G7 §3.4 needs one owner earlier than both users. |

### 0.4 Type notation

| Notation | Meaning |
|---|---|
| `chr(1)`, `int(1)`, `num(1)`, `lgl(1)` | length-1 character / integer / double (or integer) / logical, not `NA` unless stated |
| `chr`, `int`, `num`, `lgl` | vector of any length (length 0 allowed unless stated) |
| `list`, `named list`, `df` | list, list with unique non-empty names, `data.frame` |
| `env`, `fn` | environment, function |
| `T \| NULL` | `T` or `NULL` |
| `<spec:kind>` | a spec list of class `c("gptr_<kind>", "gptr_spec")` (§5.4) |
| `<session>` | a `gptr_session` (§5.1) |
| `<msg>`, `<block>`, `<entry>`, `<event>` | records of §4 |
| `<handle>` | a `gptr_secret` handle (§5.9) |

---

## 1. Conventions shared by every interface

### 1.1 Argument validation

Every exported function validates its arguments on entry with the internal checkers of `utils-conditions.R`
(P01) and signals `gptr_error_invalid_argument` with fields `arg` (the argument name) and `expected` (a short
phrase), never including the argument's value (it may be large or secret; only `class(x)[1]` and `length(x)` may
appear). Checkers never use `match.arg()` (copy-safety rule R3); `check_choice()` does exact matching and accepts
the first element of the default vector when the argument is missing.

```r
check_string(x, arg, null = FALSE, empty = FALSE)          # chr(1), not NA
check_strings(x, arg, null = FALSE)                        # chr, no NA
check_flag(x, arg, null = FALSE)                           # lgl(1), not NA
check_number(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE)
check_choice(x, choices, arg)                              # -> the chosen chr(1)
check_function(x, arg, null = FALSE, args = NULL)          # args: required formal names
check_env(x, arg, null = FALSE)
check_list(x, arg, named = FALSE, null = FALSE)
check_class(x, class, arg, null = FALSE)
```

All return the (possibly normalised) value invisibly; they are [internal] but every plan uses them.

### 1.2 Identifiers, time, paths

- Ids (IC-20) come from `id_new(prefix, n)` (P01): `substr(cli::hash_sha256(paste(<time with microseconds>,
  Sys.getpid(), <process counter>, <salt>)), 1, n)`; they never touch `.Random.seed`.
- Times: events carry `ts` = `num(1)` seconds since the epoch (`as.numeric(Sys.time())`); JSONL entries carry
  `timestamp` = ISO 8601 UTC with milliseconds (`"2026-09-29T23:42:57.689Z"`); messages on disk carry `timestamp`
  = epoch milliseconds (JSON number) as in Pi v3 [02 §3.4]. Durations are seconds (`num`).
- Paths returned by functions are absolute and normalised with `/`; paths shown to the model or the user are
  relative to the project root when inside it. The project root is `project_root()` (§7.1): the nearest ancestor
  of `getwd()` containing `.gptr/`, `DESCRIPTION`, `.git/`, `*.Rproj` or `_quarto.yml`, else `getwd()`.
- Monotonic clock for timers: `reactor_now()` = `as.numeric(proc.time()[["elapsed"]])`.

### 1.3 Copy-safety obligations (headline benefit 1)

Every function in this contract that receives a user object or a user frame is tagged with the `03` §6.4 rules it must
satisfy. The tags used below:

| Tag | Obligation |
|---|---|
| **[R1]** | holds no user object after return (values by name/address only; §5.1 value policy) |
| **[R2]** | holds a caller frame only in an environment binding reset to `NULL` at settlement; never in a list, closure, attribute or weak reference |
| **[R3]** | base-R capture; dots reach only leaf functions through `...elt(i)` in a `while` loop; no `match.arg()`, closures, `tryCatch()` or `withCallingHandlers()` in a frame holding `...` or the home; never assigns a formal |
| **[R4]** | introspects user objects only through leaf functions returning primitives; never `str()` on user objects |
| **[R5]** | never calls `lockBinding()`/`unlockBinding()` |
| **[R6]** | no `mget()` or list snapshots of user objects; checkpoint pre-images are bindings in a private environment released with `rm()` (lists and S4 defused first) |
| **[R7]** | serialises user data only through `save_rds()`/`serialize_leaf()` (`ascii = FALSE`) |
| **[R8]** | prints symbols with `print(<sym>)` evaluated in the target environment; never passes assignments through `withVisible()`; never keeps the value of an evaluation |
| **[leaf]** | the function itself is a leaf: forces its arguments on entry, returns primitives only |

Every plan that touches user objects owns a `test-copy-<area>.R` row for each tagged exported entry point (§12.3).

### 1.4 Events emitted

"Emits" lists the §10.4 events a function dispatches (through `ev_dispatch()`, P02). Events are dispatched to
session-scoped listeners first (rank 0), then registry hooks by rank. Every event payload passes
`redact_tree(profile = "stream")` before dispatch (`03` §6.5).

### 1.5 Printing

Nothing below layer L5 prints (`03` §2.2 rule 2). Functions documented here as "prints" do so only through the console
layer or `print()` methods of their own classes. Progress and notices go through `gptr_inform()` and are silenced
by `options(gptr.quiet = TRUE)`. Untrusted text reaches the console only through `msg_verbatim()` or a
`cli::cli_text("{x}")` interpolation (rule C1).

---

## 2. Conditions

### 2.1 Constructors (P01, `utils-conditions.R`) [stable for plugins through `ctx$abort()`]

```r
gptr_abort(message, class, ..., .data = NULL, call = NULL)
gptr_warn(message, class, ..., .data = NULL, .once = NULL)
gptr_inform(message, class, ..., .data = NULL, .once = NULL)
```

| Argument | Type | Meaning |
|---|---|---|
| `message` | `chr` | pasted with `paste(message, collapse = "\n")`; never interpolated; passed through the redaction hook `redact_hook()` (`redact(profile = "persist")` once P03 has installed it with `redactor_set()`; identity before; IC-34) |
| `class` | `chr` (>= 1) | suffixes, most specific first: `gptr_abort("...", c("rate_limit", "provider"))` gives `c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error", "error", "condition")` |
| `...`, `.data` | named | extra condition fields (for example `session`, `status`, `request_id`, `action`, `how_to_allow`); `.data` is a named list merged after `...` |
| `call` | `call \| NULL` | shown call; `NULL` by default (no user call in messages) |
| `.once` | `chr(1) \| NULL` | a key; the warning/message is signalled at most once per R process for that key |

Returns: `gptr_abort()` never returns; `gptr_warn()`/`gptr_inform()` return `invisible(NULL)`. `gptr_inform()`
is a no-op when `getOption("gptr.quiet")` is `TRUE`. Warnings get class
`c("gptr_warning_<cls>", "gptr_warning", "warning", "condition")`, messages
`c("gptr_message_<cls>", "gptr_message", "message", "condition")`.

Also in P01: `redactor_set(fun)` [internal] (`aaa-state.R`; P03 installs `redact`; it replaces the earlier
`condition_redactor_set()`, IC-34),
`msg_verbatim(x, stream = c("stdout", "stderr"))` [internal] (prints untrusted text with `cli::cli_verbatim()`,
or `cat()` to `stderr()`), `gptr_deprecated(what, since, instead = NULL)` [internal] (warning class
`deprecated`, once per session per `what`; an error when `options(gptr.deprecations = "error")`).

### 2.2 Hierarchy

All error classes below are `gptr_error_<name>` and inherit `gptr_error`, `error`, `condition`; a "parent" column
names the intermediate class when there is one. Fields are in addition to `message` and `call`.

| Error `<name>` | Parent | Fields | Signalled by (plan) | When |
|---|---|---|---|---|
| `invalid_argument` | - | `arg`, `expected` | every export (all) | argument validation (§1.1) |
| `invalid_spec` | - | `kind`, `name`, `field`, `problem` | `gptr_spec()`, constructors, `gptr_register()` (P02) | a spec fails its kind validator |
| `unknown_kind` | `invalid_spec` | `kind` | P02 | spec of an unregistered kind |
| `api_version` | - | `plugin`, `required`, `available` | `gptr$require()` (P02) | unmet API requirement (rolls the factory back) |
| `stale_api` | - | `plugin`, `generation` | extension API methods (P02) | API object used after `gptr_reload()` or unload |
| `conformance` | - | `results` (`gptr_check` df) | `gptr_check(error = TRUE)` (P02) | a conformance check failed |
| `not_available` | - | `member`, `provided_by` | `ctx$<member>()`, `ext_service_get()` (P01) | the service's plan is not loaded or disabled |
| `readonly` | - | `object`, `field` | `$<-`/`[[<-` on sessions and `peter` (P06, P08) | state changes must use verbs |
| `unknown_member` | - | `name`, `available` | `$.gptr_gateway`, `$.gptr_ns` (P10, P18) | `peter$nope` |
| `noninteractive` | - | `what`, `questions` | `peter()` (P08), `gptr_init()` (P08), `gptr_login()` (P18), the `ask` tool in a non-interactive `manual` run (P11; status `blocked`) | needs a human and none is present (`gptr_can_prompt()` FALSE) |
| `permission` | - | `action`, `tool`, `risk`, `how_to_allow`, `session` | `perm_check()` (P06) via the run | an `ask` without a human (NS-12); status `blocked` |
| `provider` | - | `provider`, `model`, `status`, `request_id`, `error_type`, `session` | `peter()` routes (P08) after the run ends in `error` | provider failure after retries |
| `auth` | `provider` | as `provider` | P04/P12 | 401/403 |
| `rate_limit` | `provider` | + `retry_after` | P04 | 429 exhausted |
| `spend_cap` | `provider` | as `provider` | P04 | Anthropic `enforced_spend_limit_reached` (never retried) |
| `retry_after` | `provider` | + `retry_after` | P04 | server asked to wait longer than `gptr.max_retry_delay` |
| `overloaded` | `provider` | as `provider` | P04 | 5xx/529 after retries |
| `context_overflow` | `provider` | + `tokens` | P06 | a second overflow after one compact-and-retry |
| `network` | `provider` | + `curl_code` | P04 | connection failures after retries |
| `redirect` | `provider` | + `location_origin` | P04 | a 3xx response (redirects are never followed, IC-64) |
| `billing` | `provider` | + `source` | P20 | the claude CLI reports an `apiKeySource` other than `"none"` on the plan route (IC-65) |
| `timeout` | - | `seconds`, `what` | P04, P09, P22 | generic timeout (tool, bridge, process) |
| `timeout_first_byte` | `timeout` | `seconds`, `provider` | P04 | no first byte within `gptr.first_byte_timeout` |
| `timeout_idle` | `timeout` | `seconds`, `provider` | P04 | no byte within `gptr.idle_timeout` mid-stream |
| `timeout_connect` | `timeout` | `seconds`, `provider` | P04 | TCP/TLS connect timeout |
| `budget` | - | `kind`, `budget`, `used`, `session` | P06 | a budget was exceeded; status `budget` |
| `budget_tokens`, `budget_cost`, `budget_turns` | `budget` | as `budget` | P06 | per kind |
| `max_turns` | - | `max_turns`, `session` | P06 | status `max_turns` |
| `tool` | - | `tool`, `status` | `dispatch_nested()` (P06) | a `peter$` member called from R code ended with an error result; raised inside the model's code so it sees an ordinary R error |
| `split_brain` | - | `id`, `holder_pid` | P06 | continuing a detached copy while a live original exists |
| `busy` | - | `session` | `gptr_rewind()` (P16), `gptr_resume()` (P06), `gptr_fork()` of a busy store (P06) | the session is running |
| `rewind_range` | - | `turn`, `turns` | P16 | rewind target out of range |
| `missing_package` | - | `package`, `feature` | any Suggests use (all) | a Suggests package is needed and absent |
| `no_key` | - | `provider`, `variables` | P05 | no credential found for a provider |
| `egress` | - | `provider`, `how_to_ack` | P08 (`egress_check()`) | first non-interactive use without an acknowledgement |
| `untrusted` | - | `what`, `path`, `origin` | P03, P08, P17, P18 | handle for a wrong origin; project resource used without trust |
| `unknown_model` | - | `ref`, `suggestions` | P05 | a model reference cannot be resolved |
| `invalid_identifier` | `invalid_argument` | `arg`, `class` | P08 | an identifier argument bound to a non-character, non-spec value |
| `not_recorded` | - | `document`, `prompt` | P15 | `replay` mode and no recorded block |
| `stale_block` | `not_recorded` | `document`, `block` | P15 | `replay` mode and the block's prompt or interpolated values changed |
| `replay_unbound` | `not_recorded` | `block`, `child` | P06 (`gptr_resume(block =)`) | no session is bound to that block in this process (IC-46) |
| `secret_found` | - | `findings` (df, no values) | P03 (`gptr_scrub(error = TRUE)`) | persisted files contain a registered secret (IC-70) |
| `redaction_limit` | - | `limit` (characters, no input) | P03 (`redact_stream()`) | an unresolved sensitive candidate exceeds the hold-back cap; the stream fails closed |
| `doc_write` | - | `path`, `reason` | P15 | a document write failed or was blocked and the caller asked for strictness |
| `s1` | - | `status`, `error_type`, `request_id`, `model` | P13 | System 1 failure, parent of the next rows |
| `s1_auth`, `s1_validation`, `s1_rate_limit`, `s1_overloaded`, `s1_connection`, `s1_response` | `s1` | as `s1` | P13 | classified as in 04 §4.12 (scalar calls; vectorised calls give `NA` + one warning) |
| `s1_uncertain` | `s1` | `prob`, `min_confidence` | P13 | `uncertain = "stop"` inside the uncertain band |
| `s1_labels` | `s1` | `labels` | P13 | a choice label `if()` would read as logical |
| `mcp` | - | `server` | P18 | parent of MCP errors |
| `mcp_auth_required` | `mcp` | `server`, `login` | P18 | OAuth needed; names `gptr_login("mcp:<name>")` |
| `mcp_protocol` | `mcp` | `server`, `code` | P18 | JSON-RPC or era failure |
| `mcp_tool` | `mcp` | `server`, `tool` | P18 | a tool call returned `isError` (raised inside R code, so the model sees an R error) |
| `cli_missing` | - | `cli` | P20 | the `claude`/`codex` binary was not found |
| `cli_version` | - | `cli`, `found`, `required` | P20 | below the minimum version |
| `process` | - | `command`, `status`, `stderr` (tail, redacted) | P04, P22 | a child exited non-zero with `check = TRUE` |
| `spawn` | - | `command` | P04 | a child could not be started |
| `artifact` | - | `id`, `stage`, `log` (tail) | P23 | a validation-ladder stage failed |
| `artifact_too_large` | `artifact` | `bytes`, `max` | P23 | snapshot above `gptr.artifact_max_bytes` |
| `workspace` | - | `path` | P08 | `.gptr/` cannot be created or is not a directory |
| `token_regression` | - | `fixture`, `metric`, `baseline`, `value` | `dev/bench` (P24) | a benchmark ratchet failed |
| `internal` | - | `detail` | any | a broken invariant (a bug) |

Warnings (`gptr_warning_<name>`): `rewind_partial` (P16; field `report`), `deprecated` (P02), `two_prompts` (P08;
two unnamed string literals), `replay_downgraded` (P15; live/stale regeneration downgraded under `source()`),
`doc_conflict` (P15; md5 conflict after three attempts), `s1_errors` (P13; failed elements in a vectorised call;
field `errors`), `billing_env` (P03/P20; names of removed billing variables),
`readline_limit` (P14), `plugin` (P02/P17; a plugin was disabled; field `diagnostic`), `cache_break` (P07; only
when `options(gptr.check_prefix = "warn")`), `secret_late` (P03; a newly registered secret already occurs in live
session entries; field `counts`).

Messages (`gptr_message_<name>`): `alias_shadowed` (P08), `plan_handoff` (P11), `egress_ack` (P08, IC-71), `s1_split` (P13; once per
session when a data frame is split into several states, naming `I(x)`), `notice`
(one-time notices: experimental routes, Codex overhead, uncalibrated emulation), `value_rebound` (P06),
`progress` (P14, verbosity 1), `interpolated` (P08, echo of the interpolated prompt at verbosity >= 2).

Transport, adapter and System 1 failures are condition **objects** created (not signalled) by P04, P12 and P13
with the classes above; they travel in `error` events and in the run. The gateway (P08) signals the stored object
when a programmatic run ends in status `error` (so `tryCatch(peter(...), gptr_error_rate_limit = ...)` works),
with the session attached as `cnd$session`.

R's own `interrupt` condition is re-signalled unchanged by programmatic calls (`03` §6.2); it is never wrapped.

---

## 3. Options and environment variables

### 3.1 Options

Every option is read through `gptr_opt(name)` (P01, §7.1), which returns
`getOption(paste0("gptr.", name), <default below>)`. Defaults marked "settings" fall back to the settings layers
(§11.2) when the option is unset; `gptr_opt()` returns `NULL` for them. The owner plan documents the option in
its roxygen `?gptr_options` section (P25 assembles the page).

| Option | Type | Default | Owner | Meaning |
|---|---|---|---|---|
| `gptr.quiet` | `lgl(1)` | `FALSE` | P01 | silence `gptr_inform()` and progress |
| `gptr.interactive` | `lgl(1) \| NULL` | `NULL` | P01 | force the human-present decisions (`gptr_has_human()` and `gptr_can_prompt()`, IC-43) |
| `gptr.project_root` | `chr(1) \| NULL` | `NULL` | P01 | overrides `project_root()` (also `GPTR_PROJECT_ROOT`; tests set it, IC-63) |
| `gptr.unsafe_no_permissions` | `lgl(1)` | `FALSE` | P06 | set outside a run only: no permission gate (sandboxed CI); snapshotted at run start (IC-53) |
| `gptr.verbose` | `int(1) \| NULL` | `NULL` | P01/P14 | 0 silent, 1 progress on stderr, 2 streamed console, 3 debug; `NULL` = by context (0 knitr/testthat, 1 Rscript, 2 console) |
| `gptr.ui` | `chr(1) \| <spec:ui> \| NULL` | `NULL` | P11 | UI backend name or spec; `NULL` = console when a human is present, else `none` |
| `gptr.model`, `gptr.mode`, `gptr.preset`, `gptr.system1`, `gptr.small_model` | `chr(1) \| NULL` | settings | P08 | option layer of the settings keys of the same names |
| `gptr.replay` | `chr(1) \| NULL` | settings (`"auto"`) | P08 (resolution), P15 | `"auto"`, `"replay"`, `"live"`, `"record"`; overridden by the call's `replay =` |
| `gptr.record` | `chr(1) \| NULL` | settings (`"ask"`) | P15 | `"auto"`, `"ask"`, `"off"`: may gptr write into documents (write consent, IC-45) |
| `gptr.interpolate` | `lgl(1)` | `TRUE` | P08 | `{identifier}` prompt interpolation (§6.1.4) |
| `gptr.value_copy_max` | `num(1)` | `1048576` | P06 | bytes; designated values below this are deep-copied |
| `gptr.values_max_bytes` | `num(1)` | `67108864` | P06 | bytes of held value copies and boxes per session |
| `gptr.max_turns` | `int(1)` | `50L` | P06 | turns per programmatic run |
| `gptr.max_turns_console` | `int(1)` | `200L` | P14 | turns per console prompt |
| `gptr.max_active` | `int(1)` | `8L` | P04 | concurrent HTTP transfers (global); nothing else |
| `gptr.subagents.max_active` | `int(1)` | `8L` | P19 | concurrent inline children; default of `gptr_parallel(max_active =)` (IC-71) |
| `gptr.subagents.max_cli` | `int(1)` | `4L` | P19 | concurrent CLI sub-agents |
| `gptr.subagents.max_workers` | `int(1) \| NULL` | `NULL` | P19 | `NULL` = `min(4, cores - 1)`; every child pool is capped at 2 whenever `check_running()` (IC-60) |
| `gptr.subagents.max_tasks` | `int(1)` | `8L` | P19 | children per team/fan-out call made from model code (depth >= 1, IC-39) |
| `gptr.subagents.max_depth` | `int(1)` | `1L` | P08 | nesting depth of child sessions (at most 2) |
| `gptr.max_nested_calls` | `int(1)` | `20L` | P06 | `peter()` calls per `r` evaluation (IC-66) |
| `gptr.connect_timeout` | `num(1)` | `20` | P04 | seconds |
| `gptr.first_byte_timeout` | `num(1)` | `120` | P04 | seconds |
| `gptr.idle_timeout` | `num(1)` | `90` | P04 | seconds |
| `gptr.max_retry_delay` | `num(1)` | `60` | P04 | seconds; a longer `retry-after` fails fast |
| `gptr.max_attempts` | `int(1)` | `4L` | P04 | transport attempts per request |
| `gptr.wire_log` | `lgl(1) \| chr(1)` | `FALSE` | P04 | `TRUE` = `<workspace root>/cache/tmp/wire-<session id>.jsonl` (one file per session, IC-65); a path must be inside the workspace root or `tempdir()`; each line is written open-append-close |
| `gptr.supervise` | `lgl(1) \| NULL` | `NULL` | P04 | callr/processx `supervise`, resolved by `supervise_default()`: `NULL` = `!check_running()` (IC-60) |
| `gptr.stdin_timeout` | `num(1)` | `60` | P04 | seconds to drain a pending stdin write to a child (IC-60) |
| `gptr.cli_path` | named list \| `NULL` | `NULL` | P20 | explicit `claude`/`codex` paths (tests point them at the fake CLI, IC-65) |
| `gptr.cli_turn_timeout` | `num(1)` | `3600` | P20 | wall-clock seconds per CLI turn (IC-65) |
| `gptr.r_timeout` | `num(1)` | `3600` | P09 | seconds for `r` when no human is present |
| `gptr.r_output_tokens` | `int(1)` | `4000L` | P09 | `r` result budget (estimated tokens, images included) |
| `gptr.r_max_images` | `int(1)` | `3L` | P09 | plot images attached per `r` result (IC-67) |
| `gptr.helper_output_tokens` | `int(1)` | `1500L` | P10/P22 | print budget of `peter$` members |
| `gptr.read_max_tokens` | `int(1)` | `12000L` | P10 | `read` cap (also 2,000 lines and 50 KB) |
| `gptr.plot_width`, `gptr.plot_height`, `gptr.plot_res` | `int(1)` | `768L`, `512L`, `120L` | P09 | PNG sent to the model |
| `gptr.protect_size` | `num(1)` | `1e8` | P11 | bytes; overwriting a larger object is level 3 |
| `gptr.noninteractive_ask` | `chr(1)` | `"stop"` | P06 | `"stop"` or `"deny"` (IC-14) |
| `gptr.critical_guard` | `lgl(1)` | `TRUE` | P11 | level 4 asks even in `auto` |
| `gptr.secret_guard` | `lgl(1)` | `TRUE` | P03/P11 | guarded secret reads ask even in `auto` |
| `gptr.plan_handoff` | `lgl(1)` | `TRUE` | P11 | pending-plan hand-off (`03` §6.8.5) |
| `gptr.background_tools` | `chr(1)` | `"idle"` | P21 | `"idle"` or `"wait"` |
| `gptr.compact_at` | `num(1) \| NULL` | `200000` | P07 | compaction soft cap; `NULL` disables the cap |
| `gptr.compact_cold_min` | `num(1)` | `100000` | P07 | tokens for the cold rule |
| `gptr.cache_ttl` | `chr(1)` | `"gap"` | P07 | tail TTL policy: `"gap"`, `"5m"`, `"1h"` |
| `gptr.cache_gap` | `num(1)` | `240` | P07 | seconds of inter-request gap that switch the tail to 1 h |
| `gptr.check_prefix` | `chr(1)` | `"event"` | P07 | on a prefix break: `"event"`, `"warn"`, `"error"` |
| `gptr.artifact_max_bytes` | `num(1)` | `5e8` | P23 | snapshot cap |
| `gptr.undo_capture_max` | `num(1)` | `1e8` | P16 | G7 §3.7 |
| `gptr.undo_max_bytes` | `num(1)` | `1e9` | P16 | G7 §3.7 |
| `gptr.undo_spill_max` | `num(1)` | `2e9` | P16 | G7 §3.7 |
| `gptr.undo_turns` | `int(1)` | `20L` | P16 | G7 §3.7 |
| `gptr.checkpoint` | `chr(1)` | `"on"` | P16 | `"on"`, `"files"`, `"off"` |
| `gptr.checkpoint_disk_bytes`, `gptr.checkpoint_days`, `gptr.checkpoint_turns`, `gptr.checkpoint_track_file_max`, `gptr.checkpoint_track_total`, `gptr.checkpoint_capture_max`, `gptr.checkpoint_scan_budget`, `gptr.checkpoint_rng`, `gptr.checkpoint_close_devices` | as G7 §3.7 | `2e9`, `30`, `100`, `1e6`, `1e8`, `5e7`, `0.25`, `TRUE`, `FALSE` | P16 | G7 §3.7 |
| `gptr.redact_min_chars` | `int(1)` | `8L` | P03 | shortest value-redacted secret |
| `gptr.redact_patterns` | `lgl(1)` | `TRUE` | P03 | pattern layer (values are always redacted) |
| `gptr.stream_hold_max` | `int(1)` | `4096L` | P03 | streaming hold-back cap (characters) |
| `gptr.env_export` | `lgl(1)` | `TRUE` | P03 | default of `gptr_env(set_env =)` |
| `gptr.prompt_secrets` | `chr(1)` | `"redact"` | P03 | secret-looking text in prompts: `"redact"` or `"ask"` |
| `gptr.deprecations` | `chr(1)` | `"warn"` | P02 | `"warn"` or `"error"` |
| `gptr.history` | `lgl(1)` | `TRUE` | P14 | REPL inputs to the console history via `utils::timestamp()` |
| `gptr.s1_max_active` | `int(1)` | `8L` | P13 | concurrent System 1 requests |
| `gptr.s1_rounds` | `int(1)` | `3L` | P13 | bounded retry rounds |
| `gptr.s1_state_max` | `int(1)` | `2000L` | P13 | characters of `as_state(<session>)` |
| `gptr.s1_max_elements` | `int(1)` | `10000L` | P13 | elements per System 1 call (IC-66) |
| `gptr.doc_output_lines` | `int(1)` | `12L` | P15 | `#>` lines per recorded execution |
| `gptr.doc_source_frames` | `lgl(1)` | `TRUE` | P15 | off switch for reading `source()` frames (CRAN grey zone) |
| `gptr.skills_budget` | `int(1)` | `1500L` | P17 | skill catalog tokens |
| `gptr.mcp_budget` | `int(1)` | `1500L` | P18 | MCP signature catalog tokens |
| `gptr.mcp_timeout` | `num(1)` | `60` | P18 | seconds per MCP request (soft; progress re-arms) |
| `gptr.mcp_probe_timeout` | `num(1)` | `5` | P18 | seconds for the era probe |
| `gptr.mcp_debug` | `lgl(1)` | `FALSE` | P18 | keep redacted MCP server logs in the user cache instead of `tempdir()` (IC-70) |
| `gptr.child_text_max` | `int(1)` | `51200L` | P19 | bytes of child text returned per task |
| `gptr.out_keep` | `int(1)` | `20L` | P01 | results kept per session in the `peter$out()` store (IC-71) |
| `gptr.spill_days` | `num(1)` | `7` | P15 | age after which `cache/tmp` files are pruned |

### 3.2 Environment variables read by gptr

| Variable | Read by | Meaning |
|---|---|---|
| `GPTR_REPLAY` | P08 `replay_mode()` | replay mode below the option (`replay`, `auto`, `live`, `record`) |
| `GPTR_LIVE_TESTS` | tests | `"true"` enables `test-live-*.R` |
| `GPTR_SUBAGENT_DEPTH`, `GPTR_WORKER` | P19 | set in worker children; `GPTR_WORKER = "1"` marks a worker process |
| `GPTR_MCP_TOKEN` | P18/P20 | set only in a child's environment: the bearer token of `gptr_mcp_serve()` |
| Provider keys | P05 (vault discovery, P03) | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `DEEPSEEK_API_KEY`, `MISTRAL_API_KEY`, `TOGETHER_API_KEY`, `XAI_API_KEY`, `CEREBRAS_API_KEY`, `FIREWORKS_API_KEY`, `VLLM_API_KEY`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT` (not secret), `AWS_BEARER_TOKEN_BEDROCK`, `TYPESAFE_API_KEY` (aliases `jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` through `gptr_env()`) |
| `_R_CHECK_PACKAGE_NAME_`, `_R_CHECK_LIMIT_CORES_` | P01 `check_running()` | forced replay outside testthat (examples; IC-45), child pools capped at 2, no supervision |
| `GPTR_PROJECT_ROOT` | P01 `project_root()` | overrides the project root (tests; IC-63) |
| `TESTTHAT` | P08 `replay_mode()` | `"true"` under testthat: no forced replay |
| `jupyter.in_kernel` (option) | P01 `gptr_can_prompt()` | IRkernel answers `readline()` (IC-43) |
| `QUARTO_DOCUMENT_PATH`, `QUARTO_DOCUMENT_FILE`, `JPY_SESSION_NAME`, `RSTUDIO`, `POSITRON`, `TERM_PROGRAM` | P01 `front_end()`, P15 | front-end and document detection (14 §3.9) |
| `NO_COLOR` | cli | colours off |

Set by gptr in child processes only (never in the user's session): `NO_COLOR=1`, `TERM=dumb`, `PAGER=cat`,
`GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1` (`helper` profile);
`R_ENVIRON_USER` and `R_PROFILE_USER` pointing at empty files, and `R_ENVIRON` dropped unless passed explicitly,
in **every** profile (an Rscript child otherwise re-reads keys from `~/.Renviron`; IC-60); `GPTR_MCP_TOKEN`,
`GPTR_SUBAGENT_DEPTH`, `GPTR_WORKER` as above. Removed from CLI children (G6 §3.7 verbatim, IC-65): for claude,
secret-like names, registered values, `^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)` except the kept
`CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`, and with a `billing_env` warning
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`,
`ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`,
`CLAUDE_CODE_USE_FOUNDRY`; for codex, secret-like names, registered values, `^(CODEX_MANAGED_|CODEX_SANDBOX)`, and
with the warning `OPENAI_API_KEY`, `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, `OPENAI_BASE_URL` (`CODEX_HOME` kept).
`child_env()` returns the complete vector without removed names (processx form); callr receives
`child_env_callr()` (removed names as `NA`).

Tests set (`tests/testthat/setup.R`, P01): `R_USER_CONFIG_DIR`, `R_USER_DATA_DIR`, `R_USER_CACHE_DIR`, `HOME`,
`USERPROFILE`, `APPDATA`, `LOCALAPPDATA` and `XDG_CONFIG_HOME` to temporary directories, `GPTR_PROJECT_ROOT` to a
temporary project, every provider key to `""` unless `GPTR_LIVE_TESTS=true`, `GPTR_REPLAY=replay`,
`OMP_THREAD_LIMIT=2`, and `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`.


---

## 4. Records (R shape and JSON shape)

All records are unclassed named lists (IC-10). Constructors and validators are in `provider-message.R` and
`provider-events.R` (P01); every plan builds records only through them. JSON uses the Pi v3 field names at top
level and puts gptr-only fields in a `gptr` object, which Pi ignores [G3 (16)]. Optional fields are omitted from
JSON when `NULL` (never written as `null`), except where a column says otherwise.

### 4.1 Content blocks

| R `type` | R fields (type) | JSON | Notes |
|---|---|---|---|
| `text` | `text` chr(1); `signature` chr(1)\|NULL | `{"type":"text","text":…,"textSignature":…}` | |
| `thinking` | `thinking` chr(1); `signature` chr(1)\|NULL; `redacted` lgl(1); `data` chr(1)\|NULL (redacted payload, verbatim); `origin` list(api, provider, model) | `{"type":"thinking","thinking":…,"thinkingSignature":…,"redacted":true,"gptr":{"data":…,"origin":{…}}}` | replayed byte for byte only to the same `origin$model`; `redacted` omitted when `FALSE` |
| `image` | `mime` chr(1); `data` chr(1) base64 without newlines; `source` one of `plot`, `file`, `screenshot`, `user`, `mcp`; `width`, `height` int(1)\|NULL | `{"type":"image","data":…,"mimeType":…,"gptr":{"source":…,"width":…,"height":…}}` | |
| `tool_call` | `id` chr(1) (provider id verbatim, e.g. `call_1\|fc_2`); `name` chr(1); `arguments` named list (a JSON object; empty = `structure(list(), names = character())`); `raw_arguments` chr(1)\|NULL; `thought_signature` chr(1)\|NULL | `{"type":"toolCall","id":…,"name":…,"arguments":{…},"thoughtSignature":…,"gptr":{"raw":…}}` | `arguments` always serialises as an object, never an array |
| `opaque` | `provider`, `api`, `model` chr(1); `json` chr(1) (a verbatim JSON text: encrypted reasoning items, `phase`, server-tool blocks) | `{"type":"opaque","provider":…,"api":…,"model":…,"json":"…"}` | resent verbatim to the same model only; dropped by the hand-off transform otherwise |
| `context` | `kind` chr(1) (§4.1.1); `attrs` named list of chr(1); `text` chr(1) (the **rendered** block including its tags); `anchor` lgl(1) | `{"type":"text","text":…,"gptr":{"context":…,"attrs":{…},"anchor":true}}` | adapters send it as a text block; `anchor = TRUE` marks the cache anchor (BP2) |

Constructors (P01) [internal]: `block_text(text, signature = NULL)`, `block_thinking(thinking, signature = NULL,
redacted = FALSE, data = NULL, origin = NULL)`, `block_image(data, mime = "image/png", source = "plot", width =
NULL, height = NULL)`, `block_tool_call(id, name, arguments, raw_arguments = NULL, thought_signature = NULL)`,
`block_opaque(provider, api, model, json)`, `block_context(kind, text, attrs = list(), anchor = FALSE)`
(`block_context()` renders `text` as `<kind a="v">\ntext\n</kind>` with attributes in the given order, values
escaped with `&quot;`; the rendered string is what is stored). All mark strings UTF-8.

#### 4.1.1 Context block kinds

`project_instructions` (attrs `path`), `environment`, `mode` (attrs `name`), `plan` (attrs `from`), `workspace`
(attrs `env`, `objects`), `workspace_changes` (attrs `since`, `reason`, optional), `attached` (attrs `name`),
`skill_content` (attrs `name`), `agent_reports`, `checkpoint` (attrs `n`, `turns`, `tokens_before`),
`project_instructions_update` (attrs `path`), `agent_notification`. Plugins add kinds through `context_block`
specs (§10.2); the kind name is the spec name.

### 4.2 Messages

| R `role` | R fields | JSON (inside a `message` entry) |
|---|---|---|
| `user` | `content` list of `text`/`image`/`context` blocks; `source` chr(1) in `prompt`, `pipe`, `steer`, `follow_up`, `repl`, `parent`, `replay`, `extension`, `agent`, `imported`; `timestamp` num(1) ms | `{"role":"user","content":[…],"timestamp":…,"gptr":{"source":…}}` |
| `assistant` | `content` list of `text`/`thinking`/`tool_call`/`opaque` blocks; `api`, `provider`, `model` chr(1); `response_id`, `response_model` chr(1)\|NULL; `usage` (§4.3); `stop_reason` chr(1) in `stop`, `length`, `tool_use`, `aborted`, `error`, `refusal`, `pause`; `error_message` chr(1)\|NULL; `raw_stop_reason` chr(1)\|NULL; `thinking_level` chr(1)\|NULL; `route` chr(1) in `api`, `plan-cli`, `system-one`, `emulated`; `request_id` chr(1)\|NULL; `timestamp` | Pi: `{"role":"assistant","content":[…],"api","provider","model","responseId","responseModel","usage":{…},"stopReason","errorMessage","rawStopReason","thinkingLevel","timestamp","gptr":{"route","requestId"}}`; `stopReason` `tool_use` is written `toolUse`, other values verbatim |
| `tool_result` | `tool_call_id`, `tool_name` chr(1); `content` list of `text`/`image` blocks; `is_error` lgl(1); `details` named list\|NULL (never sent to a model); `usage` (§4.3)\|NULL (sub-agent tools); `timestamp` | `{"role":"toolResult","toolCallId","toolName","content":[…],"details":{…},"isError":false,"usage":…,"timestamp"}` |
| `operator` | `kind` chr(1) in `steer_relay`, `mode`, `model`, `section_patch`, `tool_change`, `plan`, `workspace`, `reminder` (project-file updates travel as user-role `project_instructions_update` context blocks, IC-52); `content` list of `text` blocks; `tool_add` list of tool declarations `list(name, description, input_schema)`\|NULL (JSON-able; never specs); `origin_text` chr(1)\|NULL (the user's words for `steer_relay`); `timestamp` | stored as a Pi `custom_message` entry (§4.6) with `customType = "gptr.operator"` |

Operator messages carry harness facts and steering relays; adapters render them as a mid-conversation system
message (Anthropic models with that capability), a developer message (OpenAI Responses) or user text (others)
[G4 §3.5]. A steering relay's text is exactly `The user sent this message while you were working: <text>`, and
only queue items from user sources (`pipe`, `pause_menu`, `repl`, `api_user`) become relays; `extension` items are
user-role text `Extension <name> sent this note (not from the user): <text>` and `agent` items user-role
`<agent_report from="<name>">` blocks (IC-55). Operator messages carry harness facts only; a project-file update is
user-role data (a `project_instructions_update` context block, IC-52).

Constructors (P01) [internal]:

```r
msg_user(content, source = "prompt", timestamp = NULL)
msg_assistant(content, api, provider, model, usage = NULL, stop_reason = "stop", response_id = NULL,
              response_model = NULL, error_message = NULL, raw_stop_reason = NULL, thinking_level = NULL,
              route = "api", request_id = NULL, timestamp = NULL)
msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL, usage = NULL,
                timestamp = NULL)
msg_operator(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL)
msg_to_json(msg)                        # -> named list in JSON shape (§4.8 mapping), not yet serialised
msg_from_json(x)                        # inverse; unknown fields kept under `extra`
msg_text(msg)                           # -> chr(1): concatenated text blocks (context blocks excluded)
```

`content` given as a character vector is wrapped as one `text` block. `timestamp = NULL` means now.

### 4.3 Usage

Per assistant message (`msg$usage`):

| R field | Type | JSON (Pi) |
|---|---|---|
| `input` | num(1) | `input` |
| `output` | num(1) | `output` |
| `cache_read` | num(1) | `cacheRead` |
| `cache_write_5m` | num(1) | part of `cacheWrite` |
| `cache_write_1h` | num(1) | `cacheWrite1h` (and part of `cacheWrite`) |
| `reasoning` | num(1) | `reasoning` (subset of `output`) |
| `images` | num(1) | `gptr.images` (estimated image tokens in the input) |
| `total` | num(1) | `totalTokens` = input + output + cache_read + cache_write_5m + cache_write_1h |
| `cost` | list(input, output, cache_read, cache_write, total) num(1) each, USD | `cost` |
| `estimated` | lgl(1) | `gptr.estimated`: TRUE when the provider reported nothing and the estimator filled the row |

`usage_new(...)` (P05) builds it with zeros for missing fields.

Per request (one row of `.d$usage`, a `data.frame`; §5.5 of `03`):

| Column | Type | Meaning |
|---|---|---|
| `request_id` | chr | `q` + 12 hex |
| `session`, `agent`, `parent_id` | chr | session id; agent label (`"main"`, a team member name, `"s1"`); parent session id or `NA` |
| `provider`, `model` | chr | canonical provider id and model id |
| `route` | chr | `api`, `plan-cli`, `system-one`, `emulated` |
| `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`, `reasoning`, `images` | num | tokens |
| `cost` | num | USD, from dated price tiers (P05) |
| `tier` | chr | price tier label (`"<=200k"`, `">200k"`, `"default"`) |
| `stop_reason` | chr | as in §4.2 |
| `started` | POSIXct | request start |
| `seconds` | num | wall time |
| `estimated` | lgl | provider reported nothing |
| `multiplier` | num | EWMA estimator multiplier in force (§12.5 of `03`) |

The token ledger (`gptr_usage(s, detail = TRUE)`) adds, per request, one row per component with columns
`request_id`, `component` (`t0`, `t1`, `tools`, `project`, `environment`, `workspace`, `attached`, `transcript`,
`tool_results`, `images`, `other`), `tokens` (estimated), `cached` (lgl).

### 4.4 Tool calls and tool results inside the loop

The dispatcher (P06) works on **call records**:

```text
list(id = chr(1),            # the tool_call block id
     name = chr(1),          # tool name as the model wrote it
     input = named list,     # parsed arguments (after validation and coercion: the validated input)
     raw = chr(1) | NULL,    # raw argument JSON
     tool = <spec:tool> | NULL,   # NULL when unknown
     nested = lgl(1),        # a peter$ call made inside an r evaluation
     parent_id = chr(1) | NULL,   # the outer r call's id for nested calls
     outer_level = int(1) | NULL, # risk level approved for the outer call
     risk = <risk> | NULL)   # gptr_risk() result for r/sh/py/sql, or a tool's risk() result
```

and produce `gptr_tool_result` objects (§5.7) that `tool_result_message(result, call)` (P06) turns into a
`tool_result` message: `content` = the result's `content` after redaction (`context` profile) and truncation,
`details` = the result's `details` plus `value_ref` (never the value itself), `is_error`.

`details` of the `r` tool (the stable structure other plans read; P10 writes it) [stable]:

| Field | Type | Meaning |
|---|---|---|
| `code` | chr(1) | the code as sent by the model |
| `record` | lgl(1) | record into the document (default `TRUE`) |
| `note` | chr(1)\|NULL | one-line decision, written as `## Decision:` |
| `status` | chr(1) | `ok`, `error`, `timeout`, `interrupt`, `blocked`, `parse_error`, `denied` |
| `n_done`, `n_total` | int(1) | top-level expressions completed / parsed |
| `objects` | list(added, modified, removed) of chr | state diff |
| `plots` | int(1) | images attached |
| `warnings` | chr | warning messages (redacted) |
| `error` | chr(1)\|NULL | error message (redacted) |
| `changes` | list(wd, options, envvars, attached, loaded, devices) | session-state changes (names only) |
| `elapsed` | num(1) | seconds |
| `out_id` | chr(1)\|NULL | `peter$out()` id when truncated |
| `spill` | chr(1)\|NULL | spill file path when truncated |
| `outputs` | chr | printed-output lines of each successful recorded expression group, for `#>` comments (at most `gptr.doc_output_lines` per group, 76 characters each) |
| `nested` | list | at most 20 `list(tool, summary, is_error, level)` |
| `bridge` | chr | `#>` digests of bridge calls (`#> sh git status --porcelain: exit 0, 6 lines`) |
| `artifacts` | chr | paths of artifacts written (`.gptr/artifacts/<id>/app.R`) |
| `checkpoint` | chr(1)\|NULL | id of the `gptr.checkpoint` entry |
| `value` | chr(1)\|NULL | name designated through `gptr_return()` during this call (the value itself is held by the session per §5.1) |

`details` of `read`: `path`, `offset`, `limit`, `lines_total`, `truncated`, `image` (lgl), `encoding`, `eol`.
Of `edit`: `path`, `n_edits`, `fuzzy` (lgl), `diff` (chr, the full unified diff), `document` (lgl: the path is a
bound history document). Of `write`: `path`, `bytes`, `created` (lgl). Of `ask`: `answers` (named list),
`cancelled` (lgl). Of MCP tools: `server`, `tool`, `structured` (list\|NULL), `elapsed`.

### 4.5 Events

Every event is a named list `list(type = chr(1), session = chr(1) | NULL, run = chr(1) | NULL, agent = chr(1),
turn = int(1) | NULL, ts = num(1), ...)`; streaming updates are delta-only (never the partial message)
[02 §4.4]. `ev_new(type, ...)` (P01) builds one and fills `ts`.

**Provider stream events (INFRA-02)**, emitted by adapters through `opts$emit(ev)` (§8.1); `index` is the
1-based content index:

| `type` | Fields | Rule |
|---|---|---|
| `start` | `api`, `provider`, `model`, `request_id`, `response_id` (chr\|NULL) | exactly once, first |
| `text_start` / `text_delta` / `text_end` | `index`; `delta` (chr(1)) for delta; `block` for end | |
| `thinking_start` / `thinking_delta` / `thinking_end` | same | |
| `toolcall_start` / `toolcall_delta` / `toolcall_end` | `index`, `id`, `name` (start); `delta` (raw JSON text), `preview` (named list\|NULL; throttled to at most 10 Hz by `json-partial.R`) (delta); `block` (end) | |
| `done` | `reason` (the stop reason), `message` (final assistant message), `usage` | exactly one terminal event per stream |
| `error` | `reason` (`error` or `aborted`), `message` (partial assistant message with `stop_reason` `error`/`aborted` and `error_message`), `error` = list(class, status, request_id, retry_after) | terminal; after `start` failures are always this event, never an R condition |

**Agent, session and gptr events** are listed with their payloads, dispatch semantics and allowed handler returns
in §10.4.

JSON form of events (the `jsonl` frontend, the worker protocol, the wire log): the same field names, `ts` written
as ISO 8601 UTC, messages and blocks in their §4.1-4.2 JSON shapes, `type` unchanged (Pi's names for `pi`-origin
events; gptr events keep their names).

### 4.6 Session JSONL entries

A session file is one header line followed by entries, one JSON object per line, UTF-8, LF (§11.4). Every entry
has `type`, `id` (8 hex), `parentId` (id or `null` for the first entry), `timestamp` (ISO 8601 UTC).

| `type` | Fields | In model context |
|---|---|---|
| `message` | `message` (§4.2 JSON; roles `user`, `assistant`, `toolResult`) | yes (after projection) |
| `custom_message` | `customType` = `"gptr.operator"`, `content` (text blocks), `display` lgl, `details` = `{kind, toolAdd, originText}` | yes (as operator message) |
| `model_change` | `provider`, `modelId`, `gptr` = `{ref, thinking, reason}` | no |
| `thinking_level_change` | `thinkingLevel` | no |
| `compaction` | `summary` (chr), `firstKeptEntryId` (id\|null), `tokensBefore` (num), `details`, `usage`, `gptr` = `{blocks: [context blocks of the new first message], state: {...}, n: int}` | yes: its `gptr.blocks` replace everything before `firstKeptEntryId` |
| `custom` | `customType` (below), `data` | no (harness state) |

`custom` entry types (`customType` = `gptr.<name>`; `data` fields):

| Name | Written by | `data` |
|---|---|---|
| `gptr.frozen` | P07 | `{preset, t0, t1, toolsJson, toolNames, sections: [{name, tier, hash, tokens}], model}`; first entry of every session, so resume reproduces the byte-exact prefix |
| `gptr.mode_change` | P06 | `{from, to, source}` |
| `gptr.value` | P06 | `{turn, mode: "name"\|"copy"\|"box", name, address, class, bytes}` (never the value) |
| `gptr.doc_block` | P15 | `{doc, format, block, action: "insert"\|"replace"\|"stale-regenerate"\|"undone", prompt, sha, lines: [from, to], backend: "file"\|"deferred"\|"rstudio"\|"positron"\|"vscode"\|"transcript"}` |
| `gptr.replay` | P15 | `{doc, block, mode, turn, value}` (appended by `session_replay_apply()`/`session_replay_new()`, IC-46) |
| `gptr.decision` | P13 | `{question, type, model, alias, n, summary, answers: [...] (at most 50), probs: [...], cached: int}` |
| `gptr.checkpoint` | P16 | G7 §3.1 shape (object names, addresses, sizes, classes, capture mode; file paths, hashes, modes; state names; artifact `current` before/after); never values |
| `gptr.rewind` | P16 | `{from, to, keep, restore, report: [chr]}`; parented at the target, becomes the leaf |
| `gptr.subagent` | P19 | `{child, backend, model, agent, status, file, usage: {...}}` |
| `gptr.artifact` | P23 | `{id, version, url, status, checks}` |
| `gptr.plan` | P11 | `{path, text_hash, status: "pending"\|"used"\|"superseded"}` |
| `gptr.cache_break` | P07 | `{provider, model, firstDiff, entry, culprit}` |
| `gptr.recovered` | P06 | `{from, to}`: the byte range of a torn line found at resume (IC-59) |
| `gptr.router` | P06 | `{router, state, model, reason}`: a router's per-branch state (IC-69) |
| `gptr.image_elision` | P06 | `{images: [ids]}`: older images projected as omitted (IC-67) |
| `gptr.scrub` | P03 | `{date, secrets, count}`: `gptr_scrub()` rewrote this file (IC-70) |
| `gptr.ext` | P02 | `{plugin, state}`: a plugin's JSON-able per-session state (`ctx$state()` persistence) |
| `gptr.budget` | P06 | `{kind, budget, used}` when a budget stops a run |

### 4.7 Session header line

```json
{"type":"session","version":3,"id":"s4c2e9a01b7","timestamp":"2026-09-29T18:31:02.000Z","cwd":"/Users/me/project",
 "parentSession":"/Users/me/project/.gptr/sessions/20260929T183000_s1a2b3c4d5e.jsonl",
 "gptr":{"version":"1.0.0","api":"1.0","kind":"chat","parent":"s1a2b3c4d5e","depth":1,"home":"globalenv",
         "forkOf":{"id":"s1a2b3c4d5e","entry":"9f3a1c2b","turn":2}}}
```

`parentSession` is present only for forks (Pi semantics); `gptr.parent` is the parent session id for child
sessions (team members, fan-out elements, nested calls); `gptr.forkOf` only for forks.

### 4.8 R-to-JSON field mapping (one table, `provider-message.R`, P01)

| R | JSON | R | JSON |
|---|---|---|---|
| `tool_call` (type) | `toolCall` | `tool_result` (role) | `toolResult` |
| `signature` (text) | `textSignature` | `signature` (thinking) | `thinkingSignature` |
| `thought_signature` | `thoughtSignature` | `mime` | `mimeType` |
| `tool_call_id` | `toolCallId` | `tool_name` | `toolName` |
| `is_error` | `isError` | `stop_reason` | `stopReason` (`tool_use` <-> `toolUse`) |
| `error_message` | `errorMessage` | `raw_stop_reason` | `rawStopReason` |
| `response_id` | `responseId` | `response_model` | `responseModel` |
| `thinking_level` | `thinkingLevel` | `cache_read` | `cacheRead` |
| `cache_write_5m + cache_write_1h` | `cacheWrite` | `cache_write_1h` | `cacheWrite1h` |
| `total` | `totalTokens` | `parent_id` | `parentId` |
| `model_id` | `modelId` | `custom_type` | `customType` |
| `first_kept_entry_id` | `firstKeptEntryId` | `tokens_before` | `tokensBefore` |
| `parent_session` | `parentSession` | `fork_of` | `forkOf` (inside `gptr`) |

Anything else keeps its name. `json_encode()` (P01) serialises with `jsonlite::toJSON(x, auto_unbox = TRUE,
null = "null", digits = NA)`; vectors that must stay arrays at length 1 are wrapped in `I()`; strings are marked
UTF-8 first (§6.6 of `03`).

### 4.9 Model records (catalog)

`model_resolve()` (P05) returns a model record, a named list:

| Field | Type | Meaning |
|---|---|---|
| `ref` | chr(1) | canonical `provider/id` (thinking suffix removed) |
| `provider`, `id`, `name`, `family` | chr(1) | e.g. `"anthropic"`, `"claude-sonnet-5-5"`, `"Claude Sonnet 5.5"`, `"claude-sonnet"` |
| `api` | chr(1) | the adapter api (from the provider record unless overridden per model) |
| `type` | chr(1) | `chat`, `classifier`, `cli` |
| `release_date` | chr(1) `YYYY-MM-DD`\|NA | |
| `context`, `max_output` | num(1)\|NA | tokens |
| `reasoning` | lgl(1) | supports thinking |
| `thinking_levels` | chr | levels the model accepts (subset of `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`) |
| `thinking` | chr(1)\|NULL | the clamped level requested with `:level` or `.opts$thinking` |
| `input` | chr | `text`, `image`, `pdf` |
| `tool_call`, `structured_output` | lgl(1) | |
| `prices` | df(`from` Date, `tier` chr, `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h` USD per million) | dated price tiers |
| `cache_min` | num(1)\|NA | minimum cacheable prefix |
| `capabilities` | named list of lgl | `mid_system`, `tool_addition`, `images_in_results`, `operator_role`, `adaptive_thinking`, `effort` |
| `aliases` | chr | aliases that resolve to it |
| `status` | chr(1) | `active`, `deprecated`, `preview` |
| `local` | lgl(1) | a local server (unknown ids allowed) |


---

## 5. S3 classes

Methods are registered with `S3method()` in `NAMESPACE` (roxygen `@export` on the method, which registers
without exporting a name); methods for generics of Suggests packages (`knitr::knit_print`, vctrs generics) are
registered lazily with `s3_register()` (P01). "Refuses" means the method signals `gptr_error_readonly`.

### 5.1 `gptr_session` (P06, `session-object.R`) [stable]

**Object.** A classed environment (the *shell*), `class(s) == "gptr_session"`, whose only binding is `.d`, an
unclassed environment of serialisable fields. Live resources are held in a process registry
`the$live[[id]] = rlang::new_weakref(key = s, value = live)` (§5.1 of `03`); the reactor holds a running
session strongly until it settles. Reference semantics: every variable bound to `s` sees every change; the pipe
returns the identical object (`identical(s |> peter("x"), s)`).

**`.d` fields** (internal; accessed only through `session_data(s)` and the verbs):

| Field | Type | Meaning |
|---|---|---|
| `id` | chr(1) | `s` + 10 hex |
| `kind` | chr(1) | `chat`, `team`, `fanout`, `child`, `replayed` |
| `parent_id` | chr(1)\|NULL | parent session id (children) |
| `fork_of` | list(id, entry, turn)\|NULL | fork lineage |
| `depth` | int(1) | 0 top level, +1 per nesting |
| `created` | num(1) | epoch seconds |
| `status` | chr(1) | `idle`, `running`, `waiting` (a background or served run with an ask pending, IC-57), `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`, `detached` |
| `reason` | chr(1)\|NULL | reason text for the status |
| `model` | chr(1) | canonical `provider/id` of the next request |
| `thinking` | chr(1)\|NULL | clamped thinking level |
| `mode`, `preset` | chr(1) | permission mode; preset |
| `rules` | list(allow, ask, deny) of chr | session permission rules |
| `frozen` | list | `t0`, `t1` (chr(1)), `tools_json` (chr(1), once-serialised Anthropic-shape array), `tool_names` (chr), `sections` (df name, tier, hash, tokens) |
| `entries` | list of entries (§4.6, R shape) | append-only transcript (a tree) |
| `index` | env | entry id -> position (not persisted) |
| `leaf` | chr(1)\|NULL | this object's leaf entry id |
| `turns` | int(1) | completed turns |
| `seen` | chr | replayed block ids already applied |
| `last_text` | chr(1) | last final assistant text (`NA` before any) |
| `values` | list | value records `list(turn, mode = "name"\|"copy"\|"box", name, address, class, bytes, value)` (`value` only for `copy`/`box`) |
| `queue` | list(steer = list, follow_up = list) | FIFO items `list(text, blocks, source, t)`; `source` in `pipe`, `pause_menu`, `repl`, `api_user`, `extension`, `agent` (IC-55) |
| `history_source` | chr(1) | `"store"` or `"reconstructed"` (a replayed session rebuilt from its document, IC-46) |
| `dropped` | list | items dropped by an abort |
| `usage` | df | §4.3 rows, children rolled up |
| `budget` | list(tokens, cost, turns) | limits (NULL = none) |
| `max_turns` | int(1) | |
| `children` | named list of `<session>` | team members, fan-out elements, nested children |
| `doc` | list(path, format, site, blocks)\|NULL | document binding |
| `file` | chr(1)\|NULL | JSONL path |
| `home_label` | chr(1) | `"globalenv"`, `"overlay of s…"`, `"<environment>"`, `"frame of f()"` |
| `plan` | chr(1)\|NULL | pending plan text (plan mode) |
| `replayed` | lgl(1) | a replayed session |
| `block` | chr(1)\|NULL | replayed block id |
| `snapshot` | df\|NULL | last workspace snapshot (names, addresses, fingerprints; no values) |
| `ext` | named list | per-plugin JSON-able state |
| `backend`, `agent`, `exports` | chr | children only (§5.8 of `03`) |
| `last_rewind` | list\|NULL | report of the last `gptr_rewind()` |
| `editor_text` | chr(1)\|NULL | the undone prompt after a rewind |

**Live record** (`session_live(s)`, P06): `home` (environment binding: `globalenv()`, an explicit `envir`, or a
fork overlay; never a function frame), `run` (`gptr_run` or `NULL`), `listeners` (list of hook records, rank
0), `store` (`gptr_store`: the file path and lock only; no open connection, IC-59), `ctx` (`gptr_ctx`), `memo`
(environment: serialised entry JSON by `<entry id>|<api>|<same model>`), `adapter` (environment: per-provider live
state, e.g. the claude child), `background` (list or `NULL`), `lock` (chr path), `out` (the session's `peter$out()`
store, IC-71), `mcp_token` (the MCP bearer token bound to this session, IC-58).

**Accessors** (`$.gptr_session`, `[[.gptr_session`; unknown names signal `gptr_error_unknown_member` listing
the valid names):

| Name | Returns |
|---|---|
| `text` | chr(1): last final assistant text; `NA_character_` before the first turn; team sessions: the joined `### <name> (<model>)` reports; fan-out: the named chr of child texts |
| `value` | the latest designated value by turn (§5.1 of `03` value policy); `NULL` when none; name-held values are resolved with `get0(name, home, inherits = FALSE)` (a message `value_rebound` if the address changed); team/fan-out: named list of child values |
| `values` | df `turn`, `mode`, `name`, `class`, `bytes` |
| `usage` | a `gptr_usage` df (§5.12) of this session and its children |
| `cost` | num(1) USD |
| `history` | df `turn`, `role`, `preview` (60 chars), `tools` (chr, comma-joined), `tokens` |
| `messages` | list of messages on the active branch (R shape, unprojected) |
| `model`, `mode`, `status`, `reason`, `id`, `kind`, `file` | chr(1) |
| `turns` | int(1) |
| `envir` | the kept home environment, or `NULL` |
| `children` | named list of child sessions |
| `ext` | named list of plugin state |
| `plan` | chr(1) or `NULL` |
| `last_rewind`, `editor_text` | as in `.d` |
| `<child name>` | the child session (teams: agent names; fan-out: element names); agent names equal to an accessor name are rejected at call time (IC-71) |

`[[` also accepts an integer index into `children`.

**Methods.**

| Method | Behaviour |
|---|---|
| `print(x, ...)` | the last answer through `msg_verbatim()` (rendered markdown when the console renderer is available), then a dim footer `status . model . turns . tokens . cost . id`; returns `invisible(x)`; never touches user objects |
| `format(x, ...)`, `as.character(x, ...)` | `$text` |
| `summary(object, ...)` | class `gptr_session_summary` (df of `history`) with a `print` method |
| `str(object, ...)` | one line: `<gptr_session s… \| chat \| idle \| 3 turns \| anthropic/claude-sonnet-5-5>` |
| `$<-`, `[[<-` | refuse (`gptr_error_readonly`) |
| `.DollarNames(x, pattern)` | accessor and child names |
| `names(x)` | accessor and child names |
| `knit_print` | P15 (IC-07) |

`print`, `format`, `str` and `summary` are copy-safe [R1][R4]: they read only `.d`.

### 5.2 System 1 vectors (P13, `s1-types.R`) [stable]

| Class vector | Base type | Attributes |
|---|---|---|
| `c("gptr_decision", "gptr_s1", "logical")` | logical | `names`, `prob` (num, P(yes) per element), `threshold` (num(1)), `meta` |
| `c("gptr_choice", "gptr_s1", "character")` | character | `names`, `s1_levels` (chr, options in request order; never `levels`), `probabilities` (num matrix, rows = elements, columns = `s1_levels`), `confidence` (num), `meta` |
| `c("gptr_score", "gptr_s1", "numeric")` | double (expected 0-based level) | `names`, `s1_levels` (level descriptions), `probabilities` (matrix), `confidence`, `meta` |

`meta` = `list(model = "jev-1.13.0" (physical id), alias = "jev-latest", engine = provider ID |
"emulated:structured", calibrated = lgl(1) (NA when unknown; IC-74), question = chr(1), date = "YYYY-MM-DD", cached = lgl (per element),
errors = df(index, class, message) | NULL, usage = list(input, output, cost), request_ids = chr)`.

Constructors [internal]: `new_gptr_decision(x, prob, threshold = 0.5, meta = list())`,
`new_gptr_choice(x, levels, probabilities, confidence, meta = list())`,
`new_gptr_score(x, levels, probabilities, confidence, meta = list())` (names taken from `x`).

Methods (all on `gptr_s1` unless noted; results that are "bare" carry no gptr class or attributes):

| Method | Behaviour |
|---|---|
| `[` | subsets the value and every per-element attribute (rows of `probabilities`), keeps class |
| `[[` | one element as a length-1 object of the same class (so `if (x[[1]])` works) |
| `[<-`, `[[<-` | a value of the same class, or a bare value of the same base type, keeps the class and aligns per-element attributes (assignment past the end extends them with `NA`); anything else returns the bare vector |
| `c` | same class and compatible `s1_levels`: combined object; otherwise the bare combination |
| `rep` | repeats value and per-element attributes |
| `format` | `TRUE (p=0.93)`, `liver (p=0.81)`, `1.98 (conf 0.97)` |
| `print` | values with `format()`, a dim footer `jev-1.13.0 . calibrated . 2026-09-29`; `invisible(x)` |
| `as.data.frame` | one row per element: `value` plus `prob`/`confidence` and one column per level (`p_<level>`) |
| `as.logical`, `as.character`, `as.double`, `as.vector` | the bare vector |
| `Ops` (group) | computed on the bare values; the result is bare (`cell_type == "unclear"` is a plain logical) |
| `Math`, `Summary` (groups) | bare results |
| `unique`, `rev`, `sort` | bare results for `unique`; `rev` keeps class and reverses attributes; `sort` bare |
| vctrs (`vec_proxy`, `vec_restore`, `vec_proxy_equal`, `vec_ptype2`, `vec_cast`, `vec_ptype_abbr`) | registered lazily with `s3_register()` when vctrs is loaded [04 §4.5] |
| `knit_print` | P15 |

`if (x)`, `while (x)`, `isTRUE(x)`, `ifelse(x, ...)`, `table(x)`, `sum(x)` and `mean(x)` behave as for the
bare vector (tests in P13).

### 5.3 The gateway closure and namespace nodes (P08 `gptr-gateway.R`, P10 `tool-namespace.R`)

`peter` is a function with `class(peter) == c("gptr_gateway", "function")`. Methods:

| Method | Owner | Behaviour |
|---|---|---|
| `$.gptr_gateway(x, name)`, `[[.gptr_gateway(x, i)` | P08 (calls the `ns.resolve` service of P10; `gptr_error_not_available` before P10, IC-36) | a member closure (any un-namespaced tool spec with a `fun` that is not `hidden`, IC-37), or a `gptr_ns` node (`mcp`, plugin namespaces); no I/O, no connections (side-effect free); unknown -> `gptr_error_unknown_member` with the member list |
| `$<-.gptr_gateway`, `[[<-.gptr_gateway` | P08 | refuse |
| `.DollarNames.gptr_gateway(x, pattern)` | P08 (the `ns.names` service of P10; `character(0)` before P10) | member and namespace names |
| `print.gptr_gateway(x, ...)` | P08 | two lines: the gateway usage and "members: peter$<tab>" |

`gptr_ns` (P10) is an environment with class `gptr_ns` and bindings `path` (chr, e.g. `c("mcp", "github")`),
`kind` (`"mcp"`, `"mcp_server"`, `"plugin"`). Methods `$`, `[[` (resolve the next path element lazily: an MCP
server node, a tool closure), `.DollarNames`, `names`, `print` (the member signatures within
`gptr.helper_output_tokens`). Closures returned for tools have class `c("gptr_member", "function")` with a
`print` method showing the one-line signature and the first sentence of the description.

### 5.4 Specs (P02, `ext-specs.R`) [stable]

A spec is `structure(list(kind = chr(1), name = chr(1), ..., api_version = "1.0"), class = c("gptr_<kind>",
"gptr_spec"))`, validated by its kind's validator (§10.2). `api_version` records the extension API version the spec was
written for. Methods: `print` and `format` (one line `<gptr_<kind> name>` plus the non-function fields;
functions are shown as `<fn>`, never their bodies). Specs are values: modifying one after registration has no
effect on the registry.

### 5.5 Registry records and listings (P02)

A record (internal): `list(id = chr(1), kind, name, spec, rank = int(1), source = chr(1) ("builtin:<name>",
"plugin:<pkg>", "user", "project", "session"), state = chr(1) ("lazy", "active", "overridden", "disabled"),
generation = int(1), tokens = num(1), session = chr(1) | NULL, order = int(1))`.

`gptr_registry(...)` returns class `c("gptr_registry", "data.frame")` with columns `kind`, `name`, `source`,
`rank`, `state`, `tokens`, `experimental` (lgl); with `diagnostics = TRUE` a `c("gptr_diagnostics",
"data.frame")` with `time`, `source`, `event`, `class`, `message` (redacted).

### 5.6 Extension API object and `ctx` (P02, `ext-api.R`)

`gptr_extension_api` (the argument of every factory) and `gptr_ctx` (the argument of every handler) are
environments with those classes; their members are specified in §10.5 and §10.6. No binding is locked (the lint
rule of P01 forbids `lockBinding()` in `R/`); instead `$<-` and `[[<-` methods refuse assignment
(`gptr_error_readonly`) except re-assigning `state` to the identical environment, which is what
`gptr$state$x = v` does. `print()` lists the members.

### 5.7 `gptr_tool_result` (P02) [stable]

```text
structure(list(content = list(<text block>, <image block>, ...),   # what the model sees
               details = named list | NULL,                         # never sent to a model
               is_error = lgl(1),
               value = <any> | NULL,        # R-side value for peter$ member calls; memory only, never persisted
               spill = chr(1) | NULL,       # spill file of the full text
               out_id = chr(1) | NULL,      # peter$out() id
               truncated = lgl(1),
               terminate = lgl(1)),         # TRUE: end the run after this tool batch (Pi semantics)
          class = "gptr_tool_result")
```

Methods: `print` (the text content through `msg_verbatim()`, `[image]` markers), `format` (text).
`as_tool_result(x)` [internal, P02] normalises what `execute()` may return: a `gptr_tool_result`; a character
vector (one text block, `is_error = FALSE`); a list with `text`, `images`, `value`, `is_error`, `details`; `NULL`
(empty text `"(no output)"`).

### 5.8 `gptr_eval_result` (P09, `eval-core.R`) [internal]

`structure(list(status, events, n_done, n_total, changes, elapsed, images, assigned, outputs, spill, out_id,
interrupted_after), class = "gptr_eval_result")`:

| Field | Type | Meaning |
|---|---|---|
| `status` | chr(1) | `ok`, `error`, `timeout`, `interrupt`, `blocked`, `parse_error` |
| `events` | list | ordered `list(type = "source"\|"output"\|"message"\|"warning"\|"error"\|"interrupt"\|"plot", ...)` [12 §3.3]; `plot` events carry the PNG path, never the recorded plot |
| `n_done`, `n_total` | int(1) | |
| `changes` | list(wd = chr(2)\|NULL, options = chr, envvars = chr, attached = chr, loaded = chr, devices = list(from, to)) | names only |
| `elapsed` | num(1) | |
| `images` | list of image blocks | 768x512 PNGs |
| `assigned` | chr | static assignment targets of the evaluated code (for the state diff) |
| `outputs` | list of chr | printed output per top-level expression (cleaned) |
| `spill`, `out_id` | chr(1)\|NULL | set by `format_eval_result()` when truncated |
| `interrupted_after` | num(1)\|NULL | seconds |

The value of an evaluation is never kept (R8).

### 5.9 Secrets (P03)

`gptr_secret` (handle): `structure(list(id = "TYPESAFE_API_KEY#851d37", name = "TYPESAFE_API_KEY", fp =
"851d37", origin = chr(1) | NULL), class = "gptr_secret")`. `print`/`format` give `<secret TYPESAFE_API_KEY
#851d37>`; `as.character` gives the marker `[secret:TYPESAFE_API_KEY]`; `str`, `serialize()` and `saveRDS()`
contain no value.

`gptr_env_report`: `c("gptr_env_report", "data.frame")` with `name` (as spelled in the file), `variable`
(canonical), `secret` (lgl), `fingerprint`, `action` (`"set"`, `"registered"`, `"skipped"`, `"duplicate"`);
`print` never shows values; attribute `bad_lines` (int).

### 5.10 Namespace member results

| Class | Owner | Shape | `print` |
|---|---|---|---|
| `gptr_lines` | P10 | chr (file lines) + attributes `path`, `offset`, `limit`, `total`, `truncated`, `encoding` | Pi's read format, within `gptr.helper_output_tokens` |
| `gptr_patch` | P10 | list(path, message, diff (chr), n_edits, fuzzy (lgl)) | the message; the diff only when `fuzzy` |
| `gptr_matches` | P10 | `c("gptr_matches", "data.frame")`: `file`, `line` (int), `text`; attr `truncated`, `limit` | `file:line: text` lines within 1,500 tokens, then a notice |
| `gptr_files` | P10 | `c("gptr_files", "data.frame")`: `path`, `size` (num), `mtime` (POSIXct), `type` (`file`, `dir`, `link`) | paths within 1,500 tokens |
| `gptr_cmd` | P22 | list(cmd (chr), status (int), ok (lgl), stdout (chr(1)), stderr (chr(1)), elapsed, timed_out (lgl), id (out id)) | head 40% / tail 60% within `max_tokens`, stderr at most 25% with 200/100-token floors [G5 fact-check]; `format`/`as.character` give stdout |
| `gptr_job` | P22 | environment: `id`, `cmd`, `name`, `pid`; methods as closures `read(stream = "stdout", n = NULL)`, `wait(timeout = Inf, until = NULL)`, `write(text)`, `kill()`, `status()` | one line `<job id name pid status>` |
| `gptr_py` | P22 | list(name, output (chr), repr (chr)); `$value` converts to R through reticulate | output within budget |
| `gptr_artifact` | P23 | list(id, title, kind, version (int), url (with the `gptr_token` query, IC-71), path, status (`running`, `stopped`, `failed`), checks (list(parse, launch, http, session) of lgl\|NA plus `messages`), screenshot (chr(1)\|NULL), session (chr(1)\|NULL)) | `artifact  <id>  ->  <url>   (<status text>)`, where `running` reads `running in background` (NS-8; P14's renderer prints the same line on `artifact_start`) |

### 5.11 Other user-facing classes

| Class | Owner | Shape |
|---|---|---|
| `gptr_config` | P08 | named list of effective settings with attribute `sources` (named chr: key -> layer); `print` shows value and source per key |
| `gptr_risk` | P11 | list(level int(1) 0-4, label chr(1), categories chr, flagged df(call, fn, level, category, path, path_class), paths chr, secret lgl(1), secret_guard lgl(1), assigned chr, dynamic lgl(1)); `print` shows the flagged calls |
| `gptr_prompt_view` | P07 | list(system = list(t0, t1), tools_json, first_message (chr), sections df(name, tier, tokens), total_tokens); `print` shows each part with its token estimate |
| `gptr_check` | P02 | `c("gptr_check", "data.frame")`: `target`, `check`, `ok` (lgl), `message` |
| `gptr_api` | P02 | list(version = package_version, features = chr) |
| `gptr_mcp_handle` | P18 | environment: `url`, `port`, `token_env` (chr(1): the variable name, never the token), `config` (named list of client snippets), `stop()` |

### 5.12 Listing data frames

All are `c("gptr_<name>", "gptr_listing", "data.frame")`, built by `new_listing(df, class, footer = NULL)` (P01,
`utils-text.R`), whose `print.gptr_listing` method prints at most 20 rows, then a count line and the footer.

| Class | Owner | Columns |
|---|---|---|
| `gptr_usage` | P06 | the §4.3 per-request columns (`detail = FALSE` aggregates by `by`: `group`, `requests`, `input`, `output`, `cache_read`, `cache_write`, `cost`); attribute `totals` (named num) |
| `gptr_ledger` | P06 | the §4.3 ledger columns |
| `gptr_sessions` | P06 | `id`, `file`, `created`, `updated`, `turns`, `model`, `status`, `title` (first prompt, 60 chars), `live` (lgl) |
| `gptr_models` | P05 | `ref`, `provider`, `name`, `context`, `max_output`, `input_price`, `output_price`, `reasoning`, `aliases`, `status` |
| `gptr_providers` | P05 | `id`, `type`, `api`, `credential` (`"NAME #fp"` or `NA`), `source`, `status`, `default_model`, `egress` (`ack`/`needed`), `version` (CLIs); optional `login` when `check_login = TRUE` |
| `gptr_mcp_servers` | P18 | `name`, `source` (`gptr:user`, `gptr:project`, `claude-code:user`, ...), `transport`, `era`, `status`, `tools`, `exposure`, `tokens`, `trusted` |
| `gptr_skills` | P17 | `name`, `description`, `source`, `path`, `tokens`, `visible` |
| `gptr_agents` | P17 | `name`, `description`, `model`, `backend`, `source`, `path` |
| `gptr_plugins` | P17 | `name`, `version`, `api`, `kind` (`package`, `directory`, `claude-plugin`), `enabled`, `state`, `provides`, `tokens`, `path` |
| `gptr_blocks` | P15 | `id`, `lines` (chr `"12-18"`), `prompt`, `status` (`fresh`, `stale`, `user-edited`, `undone`), `model`, `date`, `tokens`, `cost`, `session` |
| `gptr_checkpoints` | P16 | `turn`, `id`, `time`, `prompt`, `objects`, `files`, `held_mb`, `disk_mb`, `branch` |
| `gptr_artifacts` | P23 | `id`, `title`, `version`, `status`, `url`, `pid`, `bytes`, `path` |
| `gptr_jobs` | P21 | `id`, `kind` (`session`, `bg`, `artifact`, `mcp_serve`, `worker`, `cli`), `name`, `pid`, `status`, `started` |
| `gptr_cache_info` | P15 | `kind`, `entries`, `bytes`, `oldest`, `path` |
| `gptr_permissions` | P11 | `rule`, `list` (`allow`, `ask`, `deny`), `scope`, `source` |

### 5.13 Internal environments

| Class | Owner | Purpose (fields in §7) |
|---|---|---|
| `gptr_reactor` | P04 | the process reactor |
| `gptr_run` | P06 | one run of a session (fields §7.6) |
| `gptr_loop` | P06 | the L2 state machine of a run |
| `gptr_call` | P08 | one gateway call (IC-13, §7.8) |
| `gptr_store` | P06 | the open JSONL writer of a session |
| `gptr_mcp_conn` | P18 | an MCP connection |
| `gptr_registry_env` | P02 | the registry |


---

## 6. Exported API (63 names)

Every export has roxygen docs with `@param`, `@return` and an `@examples` block that runs offline on CRAN: examples
use `gptr_fake_provider()`, `envir = new.env()`, `tempfile()` directories and never keys, network, processes or
servers (13 C-24, C-47). Related exports share Rd pages with `@rdname` (P25 groups them as in §4.4 of `03`).
Each entry below gives: owner plan and file, stability, signature, arguments, return value, conditions, side
effects, events, copy-safety tags and an example.

### 6.1 `peter()` — the gateway (P08, `gptr-gateway.R`, `gptr-capture.R`) [stable]

```r
peter = function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                choices = NULL, levels = NULL, threshold = 0.5,
                min_confidence = NULL, uncertain = NULL,
                prompt = NULL, envir = parent.frame(), background = FALSE,
                budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                .stdin = FALSE)
```

`peter` carries class `c("gptr_gateway", "function")` (§5.3). All formals follow `...`, so they match only by
exact name.

| Argument | Type / default | Meaning and validation |
|---|---|---|
| `...` | any | at most one leading unnamed `<session>` (continuation target), the prompt (below), context objects (unnamed: labelled by their deparsed expression, e.g. `mice`; named: by name). A named `<session>` is context, not a target. |
| `model` | identifier, `<spec:provider>`, `<spec:router>` or `NULL` | resolved by §6.1.3; `NULL` = settings default (§8.4 of `03`) |
| `mode` | identifier or `NULL` | one of `plan`, `manual`, `edits`, `auto`; a continuation may only keep or change it explicitly; children only tighten |
| `skills`, `plugins`, `extensions` | identifiers (`c(a, b)`) or `NULL` | names resolved by §6.1.3 (normalised, IC-42); `extensions` also accepts `function(gptr)` factories (loaded with `ext_load(rank = 0L, session = <id>)`, visible to this session only, IC-69) and file paths; plugins and named extensions are enabled for the session through P17's `plugin.enable` service (`gptr_error_not_available` before P17); skills are preloaded as `<skill_content>` through `skill.body` |
| `tools` | chr, identifiers, `<spec:tool>` list, or `NULL` | tool names; `"+grep"`/`"-write"` modifiers; a preset name (`"minimal"`, `"standard"`, `"readonly"`, `"extended"`); tool specs are registered at rank 0 for this session |
| `agents` | named list or `NULL` | evaluated in a mask where `agent` is `gptr_agent`; names must be unique syntactic names that are not accessor names (IC-71) |
| `parallel` | `int(1)` >= 1 or `NULL` | fan out one list-like context object over at most `parallel` concurrent children |
| `choices` | chr (>= 2, unique, no logical-looking labels) or factor or `NULL` | System 1 choice question |
| `levels` | chr (>= 2) or `NULL` | System 1 score question (level descriptions, 0-based) |
| `threshold` | `num(1)` in (0, 1) | System 1: P(yes) at or above it is `TRUE` |
| `min_confidence` | `num(1)` in [0, 1] or `NULL` | System 1 uncertain band: `abs(2 * p - 1) < min_confidence` (decisions); `confidence < min_confidence` (choices, scores) |
| `uncertain` | `NA`, `TRUE`, `FALSE`, `"stop"`, `function(state, answer)` or `NULL` | what an uncertain element becomes; `NULL` with `min_confidence` given means `NA` |
| `prompt` | `chr(1)` or `NULL` | explicit prompt; wins over positional selection |
| `envir` | `env` | where `r` evaluates and objects persist (D-04); a magrittr mask is replaced by its parent [12 §2.B4]; for a continuation an explicit `envir` (tested with `missing(envir)`) beats the session's kept home, which beats the caller frame (IC-40) |
| `background` | `lgl(1)` | [experimental] return the running session at once (needs later; P21) |
| `budget` | `list(tokens =, cost =, turns =)` or `NULL` | per-call limits; each element `num(1)` or `NULL` |
| `replay` | `chr(1)` or `NULL` | `"auto"`, `"replay"`, `"live"`, `"record"` (document replay mode, P15) |
| `.opts` | named list | rare switches: `thinking` (chr(1)), `max_turns` (int(1)), `context` (`"summary"`, `"names"`, `"none"`), `record` (lgl(1)), `interpolate` (lgl(1)), `timeout` (num(1), seconds for `r`), `output` (`"factor"`), `system` (chr(1) replacing `preamble`/`tools`/`rules`, or a named list overriding sections, `NULL` elements remove), `preset` (a registered `preset` name), `returns` (a JSON Schema list: structured final answer, INFRA-25), `max_active` (int(1)), `backend` (a registered `backend` name or `"auto"`), `frontend` (a registered `frontend` name), `images` (list of image paths, `ggplot` or `recordedplot` objects, IC-44), `seed` (int(1): reproducible sub-agent RNG streams, IC-61), and entries named by a plugin namespace (validated by that plugin's `setting` specs, IC-44); other unknown names signal `gptr_error_invalid_argument` |
| `.run` | `lgl(1)` | `FALSE`: build the session with the prompt queued and return it (SDK) |
| `.stdin` | `lgl(1)` | drive the console from piped standard input [18 §4.2] |

#### 6.1.1 Dispatch

1. **Capture** [R3]: `exprs = as.list(substitute(list(...)))[-1L]`, `nms = ...names()`; dot facts
   (`is_session`, `is_literal`, `is_chr1`, `class`, `length`, `dim`, `bytes`, small-character `text` copy) are
   computed by leaves: for a dot whose expression is a plain symbol, `dot_facts()` of a leaf
   `get0(name, envir = parent.frame())` and the dot's promise is never forced; calls and forwarded `...`/`..n`
   dots go through `dot_facts(...elt(i))` in a `while` loop (IC-41); evaluating a call among the dots (the inner
   `peter()` of a pipe) runs it exactly once; values of calls are held only in the call record's `values`
   environment (§7.8) until settlement; symbols are never evaluated except by leaves.
2. **Prompt**: `prompt =` if given; else the first unnamed string literal; else the first unnamed length-1
   character value that is not a session [12 §2.D3]; two unnamed literals signal the warning `two_prompts`.
   Literal prompts get `{identifier}` interpolation (§6.1.4).
3. **Resolve** `model`, `mode`, `skills`, `plugins`, `extensions`, `tools`, `agents` (§6.1.3).
4. **Human check**: no prompt, nobody to prompt (`gptr_can_prompt()` FALSE, IC-43) and `.stdin = FALSE` ->
   `gptr_error_noninteractive`.
5. **Route**: the `route` records (§10.2, kind `route`) are tried in ascending `order`; the first whose
   `match(call)` is `TRUE` runs `run(call)`; a `run` may return `route_pass()` to continue with the next match:

   | Order | Route | Owner | Match | Result |
   |---|---|---|---|---|
   | 10 | `classifier` | P13 | resolved model is a `classifier` provider | `gptr_decision`/`gptr_choice`/`gptr_score`; a piped session becomes the state through `as_state()`, no turn |
   | 15 | `team` | P19 | `agents` given | a team session; inside a run its children are children of the running session (IC-39) |
   | 16 | `fanout` | P19 | `parallel` given and exactly one list-like context object | a fan-out session (same nesting rule) |
   | 20 | `nested` | P08 | a run is active on the call stack (`run_current()` non-NULL) and no session is continued | a child session of the running one (depth + 1, mode inherited and only tightened, usage and budget rolled up to the root, no document block) |
   | 30 | `console` | P14 | no prompt (`gptr_can_prompt()` or `.stdin`) | the `console` frontend on the piped session or a new one; returns it invisibly on `/exit`, or `NULL` when first-use setup returns before a session starts |
   | 50 | `document` | P15 | a top-level call located in a document that contains a block owned by this call (no write consent needed to replay, IC-45) | a fresh block: the replay of IC-46 (the piped session advanced in place, else a replayed session; zero tokens); a stale block under `replay`: `gptr_error_stale_block`; otherwise sets `call$doc` when write consent exists and passes |
   | 60 | `continue` | P08 | a session was piped in | running: `gptr_steer(s, prompt)` and `invisible(s)`; otherwise a new turn on `s` |
   | 70 | `new` | P08 | always | a new session |

   Before P13/P14/P15/P19 are loaded their routes are absent; a no-prompt call that can prompt and no
   `console` route signals `gptr_error_not_available`. Every call made while `run_current()` is non-NULL inherits
   the running mode (only tightened) and filters whatever route handles it (IC-53). Top-level team and fan-out
   statements own one document block (IC-47); in replay mode their children pass `replay_guard()`, so
   `GPTR_REPLAY=replay` still proves that a script makes no model calls.

   The console's first-use setup runs before its banner or chat input only for a new interactive
   console without an explicit or effective configured model. It offers the expected Codex and
   Claude CLI adapters plus manual API/Ollama instructions. A usable CLI with reported sign-in, or
   unknown login explicitly selected by the user, saves `codex/default` or `claude-cli/default`
   through `gptr_config(model = ..., .scope = "user")` and continues. Cancellation, manual setup,
   unavailable/signed-out CLI or a same-name non-CLI provider returns `NULL` without saving.
   Existing sessions, explicit/configured models, `.stdin = TRUE` and noninteractive workflows
   skip setup; prompt-bearing calls retain normal model resolution. Setup preserves unrelated
   settings, does not grant an egress acknowledgment and never performs inference. Login status
   is a local CLI report, not proof of subscription billing or online credential validity.
6. **Run**: `.run = FALSE` -> the session with the rendered input queued; `background = TRUE` -> registered with
   the background pump (P21) and returned running; otherwise run to settlement on the reactor under the
   interrupt policy (`console-interrupt.R` when loaded, else abort-only), then return.

#### 6.1.2 Returns and visibility

- System 2 shapes return the `<session>` (the continued one for pipes). It is returned **invisibly** when its
  answer was streamed to the console (verbosity 2), visibly otherwise (Rscript, knitr, tests). `.run = FALSE`
  and `background = TRUE` return it invisibly.
- System 1 returns a typed vector (§5.2), visibly.
- Terminal statuses of a programmatic run: `idle` returns normally; `error` signals `gptr_error_provider`;
  `blocked` signals `gptr_error_permission`; `budget` signals `gptr_error_budget_<kind>`; `max_turns` signals
  `gptr_error_max_turns`. Each condition carries the session as `cnd$session`, and the session is also
  `gptr_last()`. An interrupt (Ctrl-C abort) persists the partial turn and re-signals R's `interrupt` condition so
  loops stop [15 §4.7].

#### 6.1.3 Identifier resolution (D-07, `resolve_identifier()`, P08)

| Expression | Result |
|---|---|
| `NULL` | the settings default |
| string literal | itself |
| symbol that is a **known identifier** (catalog alias, registered provider/model/router id, mode, preset, skill, plugin, extension, agent name; `identifier_known()`; skill, plugin, extension and agent names compare after `name_norm()` = lower case with `_` and `.` mapped to `-`, IC-42) | its canonical name; a once-per-session `alias_shadowed` message when a *character* variable of that name holds a different value ("used the alias; write !!sonnet"); an ambiguous normalised match is `gptr_error_invalid_identifier` listing the candidates |
| `!!x`, `I(x)` | the value of `x` (must be character or a spec) |
| other symbol bound where the call's promise is evaluated | the formal's promise is forced in a leaf: character -> its value; `<spec:provider>`, `<spec:router>`, `<spec:tool>`, `<spec:agent>` -> registered at rank 0; any other class -> `gptr_error_invalid_identifier` ("`mice` is a data.frame, not a model name") |
| unknown unbound symbol | the literal name, validated later (`gptr_error_unknown_model` with `adist()` suggestions) |
| `c(a, "b")`, `+name`, `-name` | element-wise |
| other calls (`if (hard) opus else haiku`) | evaluated in an alias mask (known identifiers bound to their names; parent = the caller); the mask's parent is reset to `emptyenv()` afterwards |

A symbol that looks like a decimal model version (`gpt5.1`) is echoed once; documents always record quoted
canonical ids.

#### 6.1.4 Prompt interpolation (`interpolate_prompt()`, P08)

Only literal prompts; only `{identifier}` where `identifier` matches `^[.A-Za-z][.A-Za-z0-9_]*$` and is bound in
`envir` (found with `get0(inherits = TRUE)` in a leaf) to an atomic vector of 1-50 elements; elements are
`format()`ted, joined with `", "` and cut at 1,000 characters; `{{`/`}}` are literal braces; everything else is
untouched; a value is never re-interpolated; `.opts$interpolate = FALSE` or `options(gptr.interpolate = FALSE)`
disables it. The call record keeps `template` (written to documents, hashed for blocks), `prompt` (sent) and
`interp` (the sorted `name=value` pairs used, hashed into the block header's `args=` key, IC-45).

#### 6.1.5 Conditions, side effects, events

Conditions: `invalid_argument`, `invalid_identifier`, `noninteractive`, `not_available`, `unknown_model`,
`no_key`, `egress`, `permission`, `provider` (and subclasses), `budget_*`, `max_turns`, `not_recorded`,
`stale_block`, `missing_package` (background without later), the System 1 errors of §2.2; warning `two_prompts`.
Side effects: creates or continues sessions; appends to their JSONL store (workspace or `tempdir()`); may
evaluate model-written R code in `envir` (gated); may write the bound document (P15); may start processes (CLI
providers, MCP servers, workers) that end with the run or the session. Emits: `route`, `model_select`,
`session_start` (new sessions), `input`, then the run's events (§10.4).
Copy-safety: [R1][R2][R3] (the gateway is the principal entry point of the tracemem suite, `test-copy-gateway.R`).

```r
fake = gptr_fake_provider(list("The data has 32 rows."))
s = peter("How many rows does the data have?", mtcars, model = fake, envir = new.env())
s$text
s |> peter("And how many columns?")          # same object, second turn (the fake repeats its last reply)
identical(gptr_last(), s)
```

### 6.2 Setup and status

#### `gptr_init()` — P08, `gptr-config.R` [stable]

```r
gptr_init(path, instructions = TRUE, gitignore = TRUE)
```

| Argument | Type | Meaning |
|---|---|---|
| `path` | `chr(1)`, no default | project directory; missing: when `gptr_can_prompt()` asks `Create .gptr/ in <project_root()>? [y/N]` through `gptr_confirm()`; otherwise `gptr_error_noninteractive` |
| `instructions` | `lgl(1)` | write `vignette.Rmd` from `inst/templates/vignette.Rmd` if absent |
| `gitignore` | `lgl(1)` | write `.gptr/.gitignore` from `inst/templates/gitignore` if absent |

Returns `invisible(<absolute path of .gptr>)`. Creates `.gptr/`, `settings.json` (from
`inst/templates/settings.json`), `skills/`, `agents/`, `prompts/` (never overwrites existing files; idempotent).
In a package source (a `DESCRIPTION` with `Package:`) whose `.Rbuildignore` lacks `^\.gptr$` it **offers** the line
(interactive `gptr_confirm()`; otherwise one `notice` message naming the line); it never writes it silently
[13 §2.3]. With a human present it then asks a separate question `Trust this project (its settings, extensions and
MCP servers)? [y/N]` and records the answer with `gptr_trust()`; without a human nothing is trusted. Conditions:
`noninteractive`, `workspace`, `invalid_argument`. Emits nothing.

```r
d = tempfile("proj"); dir.create(d)
gptr_init(d)
list.files(file.path(d, ".gptr"), all.files = TRUE)
```

#### `gptr_config()` — P08, `gptr-config.R` [stable]

```r
gptr_config(..., .scope = NULL)
```

`.scope`: `NULL` = `"project"` when a workspace exists (`workspace_dir()` non-NULL), else `"session"` (NS-9's
"project defaults", IC-71); or one of `"session"`, `"project"`, `"user"`. With no `...`: returns the effective
settings as a `gptr_config` (§5.11), each key annotated with the layer it came
from (§11.2). With named arguments: sets keys in the scope and returns the previous values invisibly (a named
list). Keys are the registered `setting` specs (core keys of §11.2 plus plugin settings); an unknown key is
`gptr_error_invalid_argument`. `model`, `small_model`, `system1`, `mode`, `preset` take bare identifiers
(§6.1.3); a `NULL` value removes the key from the scope. Scopes: `"session"` = this R process; `"project"` =
`.gptr/settings.json` (needs a workspace, `gptr_error_workspace` otherwise; values that would loosen a `tighten`
setting are stored but never applied, and other keys apply only in a trusted project, §11.2); `"user"` =
`R_user_dir("gptr", "config")/settings.json`. `egress` is accepted only at user scope. Files are written
atomically with top-level keys merged. Conditions: `invalid_argument`, `workspace`,
`invalid_identifier`. Emits nothing.

```r
old = gptr_config(mode = plan)
gptr_config()$mode
gptr_config(mode = old$mode)
```

#### `gptr_env()` — P03, `auth-dotenv.R` [stable]

```r
gptr_env(path = ".env", aliases = NULL, set_env = getOption("gptr.env_export", TRUE),
         override = FALSE, quiet = FALSE)
```

| Argument | Type | Meaning |
|---|---|---|
| `path` | `chr(1)` | an existing file (else `gptr_error_invalid_argument`) |
| `aliases` | named list or `NULL` | extra `canonical = c(aliases)`; added to the built-in table (`TYPESAFE_API_KEY = c("jev-key", "JEV_KEY", "JEV_API_KEY", "TYPESAFE_KEY")`) and `env_alias` specs |
| `set_env` | `lgl(1)` | export canonical names with `Sys.setenv()` |
| `override` | `lgl(1)` | overwrite variables already set |
| `quiet` | `lgl(1)` | no report message |

Parses with gptr's own parser (G6 §3.1: BOM, CRLF, `export`, quotes, multi-line, ` #` comments, hyphenated names),
maps aliases (a canonical spelling wins over an alias), registers **every** value in the vault (including losing
duplicates), exports canonical names only. Returns `invisible(<gptr_env_report>)` (names and fingerprints only).
Unless `quiet`, one message lists `variable #fingerprint` per entry. Never prints, logs or returns a value.
Conditions: `invalid_argument` (missing file; malformed lines are reported by line number in the report, not
errors). Side effects: vault; environment variables. Emits `secret_registered` (count only) to audit hooks.

```r
f = tempfile(fileext = ".env")
writeLines("jev-key=example-not-a-real-key-123", f)
rep = gptr_env(f, set_env = FALSE)
rep$variable
```

#### `gptr_trust()` — P08, `gptr-config.R` [stable]

```r
gptr_trust(path = ".", trust = NULL)
```

`trust = NULL` returns the recorded decision for `project_root(path)` visibly: `TRUE`, `FALSE` or `NA`
(undecided). `TRUE`/`FALSE` records it in `R_user_dir("gptr", "config")/trust.json` keyed by the normalised
project path and returns the previous decision invisibly. Trust gates (§6.10 of `03`): project settings beyond
tightening, `.gptr/extensions/` and project plugin code, project MCP servers, `SYSTEM.md`/`APPEND_SYSTEM.md`,
project `.env` auto-discovery, provider base-URL overrides, tool and model fields of project agent files.
The record includes the trust fingerprint of the trust-gated files (IC-52). Conditions: `invalid_argument`. Side
effects: writes `trust.json` (atomic, under a short file lock). Emits nothing (`project_trust` is the first-decision
event raised when untrusted resources are first used, IC-71). Called from model code during a run it is a
`control`-category action (IC-53).

```r
d = tempfile("proj"); dir.create(d)
gptr_trust(d)
```

#### `gptr_login()`, `gptr_logout()` — P18, `auth-oauth.R` [stable]

```r
gptr_login(provider, method = c("auto", "oauth", "key"))
gptr_logout(provider)
```

`provider`: a provider id (`"anthropic"`, `"openrouter"`, ...) or `"mcp:<server>"`. `method = "auto"`: OAuth
(PKCE S256, loopback callback when httpuv/later are installed, paste fallback otherwise) for providers and MCP
servers that support it, else masked key entry (`rstudioapi::askForPassword()` when available, else a no-echo
console read). Credentials go to the credential store (`auth.json`, 0600, or a keyring reference); access tokens
stay in memory. Needs a human (`gptr_error_noninteractive`). `gptr_login()` returns `invisible(TRUE)`;
`gptr_logout()` removes stored and in-memory credentials and returns `invisible(<lgl: something removed>)`.
Conditions: `noninteractive`, `invalid_argument`, `missing_package`, `provider` (token endpoint failure).
Emits `secret_registered`.

```r
# interactive only (roxygen wraps it in \dontrun{})
gptr_login("openrouter")
```

#### `gptr_providers()` — P05, `provider-registry.R` [stable]

```r
gptr_providers(check = FALSE, check_login = FALSE)
```

Returns a `gptr_providers` data frame (§5.12): every registered provider record, its credential source as
`NAME #fp` (never values), CLI paths and cached versions (P20 contributes a `status` function per CLI provider
that uses cached results or filesystem discovery unless `check = TRUE`, IC-65), plan status and egress acknowledgement.
`check = TRUE` makes cheap reachability checks (models endpoint with a 2 s timeout for HTTP providers;
version and capability probes for CLIs; never a paid request). With both `check = FALSE` and
`check_login = FALSE`, listing performs no network or process I/O.
`check_login = TRUE` independently checks CLI-reported login using supported `codex login status` and
`claude auth status` commands (3 s timeout per subprocess, closed stdin, no model request). It adds a
`login` column: `signed in`, `not signed in`, or `unknown`; non-CLI providers report `not applicable`.
Unsupported commands, missing tools and failed checks report `unknown`. Raw account/key output is never
returned or displayed. A signed-in report does not guarantee online credential validity or quota.
The first-use console accepts the CLI shortcuts only when their registered APIs are `cli-codex` and
`cli-claude`, respectively; same-name non-CLI overrides cannot be saved as CLI defaults.
Conditions: `invalid_argument`. Emits nothing.

```r
gptr_providers()
```

#### `gptr_models()` — P05, `catalog-models.R` [stable]

```r
gptr_models(query = NULL, provider = NULL, refresh = FALSE)
```

`query`: a regular expression or alias (`"sonnet"`) matched against ref, name and aliases; `provider`: a provider
id filter. Returns a `gptr_models` data frame from the merged catalog (snapshot < cache < overrides < user config <
live discovery of local servers). `refresh = TRUE` fetches the models.dev data with ETag into
`R_user_dir("gptr", "cache")` (interactive or explicit only; the one network call of this function). Offline
resolution takes under 0.1 s (P05 acceptance). Conditions: `invalid_argument`, `network` (refresh only).

```r
gptr_models("sonnet")
```

#### `gptr_permissions()` — P11, `perm-rules.R` (IC-06) [stable]

```r
gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL,
                 scope = c("session", "project", "user"))
```

With no rule arguments: returns a `gptr_permissions` data frame of all rules in effect (session, project
`settings.json`, the user-level project file, user). With `allow`/`ask`/`deny` (chr of rules in the §6.8.2 grammar
of `03`, e.g. `"write(results/**)"`, `"r(fn:write.csv,saveRDS)"`, `"r(level<=1)"`, `"r(sh:git status*)"`,
`"r(sql:select)"`, `"mcp__github__*"`) adds them; `remove` removes matching rules. `scope`: `"session"` = this R
process; `"project"` = the user-level project file `R_user_dir("gptr", "config")/projects/<hash>.json` (personal,
never in the project tree, IC-52); `"user"` = the user settings file. Called from model code during a run it is a
`control`-category action (IC-53).
Every rule is parsed first; an invalid rule signals `gptr_error_invalid_argument` and nothing is written.
Allow rules never loosen `plan` and never pre-approve level 4 (enforced at evaluation, not here). Returns the
updated data frame invisibly. Conditions: `invalid_argument`, `workspace`.

```r
gptr_permissions(allow = "r(level<=1)")
gptr_permissions()
gptr_permissions(remove = "r(level<=1)")
```

### 6.3 Discovery and MCP

#### `gptr_skills()`, `gptr_agents()` — P17, `skill-discover.R`, `subagent-defs.R` [stable]

```r
gptr_skills(scope = c("all", "project", "user", "packages"))
gptr_agents(scope = c("all", "project", "user", "packages"))
```

Return `gptr_skills` / `gptr_agents` data frames (§5.12) with a `tokens` column (catalog cost). Project resources
are listed even in untrusted projects (read-only discovery; the `source` column shows `project (untrusted)`).
No side effects. Conditions: `invalid_argument`.

```r
gptr_skills("packages")
```

```r
gptr_agents()
```

#### `gptr_plugins()` — P17, `ext-plugins.R` [stable]

```r
gptr_plugins(installed = FALSE)
```

`installed = FALSE`: plugins known to this session (enabled through arguments or settings, attached packages with
`inst/gptr/`, plugin directories, `.claude-plugin` bundles), with state (`lazy`, `active`, `disabled`, `failed`).
`installed = TRUE`: also scans installed packages for `Config/gptr/plugin` or `inst/gptr/plugin.json` (one
vectorised `dir.exists()`; loads nothing). Returns `gptr_plugins` (§5.12).

```r
gptr_plugins(installed = TRUE)
```

#### `gptr_mcp()` — P18, `mcp-config.R` [stable]

```r
gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)
```

Without `tools`: a `gptr_mcp_servers` data frame of gptr's servers (user and trusted project `mcp.json`) and the
servers configured for Claude Code, Claude Desktop, Codex (TOML subset), Cursor, VS Code and Pi (read-only; their
files are found under `user_home()` and `app_config_dir()`, never `path.expand("~")`, IC-63), with era (from the
era cache), status and tool counts; no connection is made. `tools = TRUE`: a data frame of tools
(`server`, `tool`, `signature`, `exposure`, `tokens`) for `server` (or all enabled servers), from the tool cache
when fresh, otherwise by connecting (which starts stdio servers). `refresh = TRUE` reconnects and refreshes the
caches. Conditions: `invalid_argument`, `mcp_*`, `untrusted` (project servers of an untrusted project are listed but
never started).

```r
gptr_mcp()                            # lists servers without connecting
```

#### `gptr_mcp_add()`, `gptr_mcp_remove()` — P18, `mcp-config.R` [stable]

```r
gptr_mcp_add(name, command = NULL, args = character(), url = NULL, env = NULL, headers = NULL,
             exposure = "r", timeout = 60, scope = c("user", "project"))
gptr_mcp_remove(name, scope = c("user", "project"))
```

`name` matches `^[A-Za-z0-9_-]{1,64}$`; exactly one of `command` (stdio) and `url` (Streamable HTTP) is given;
`env`/`headers` are named character vectors whose values that look secret (a registered value or a `03` §6.5 pattern)
must be written as `${VAR}` placeholders (otherwise `gptr_error_invalid_argument` naming the key); `exposure` in
`r`, `direct`, `deferred`, `hidden`; `timeout` seconds. Writes gptr's `mcp.json` at the scope (project needs a
workspace) atomically; never edits other harnesses' files. `gptr_mcp_add()` returns the spec invisibly;
`gptr_mcp_remove()` returns `invisible(<lgl: removed>)`. Emits `mcp_servers_change` (notify).

```r
# writes the user mcp.json (roxygen wraps it in \dontrun{})
gptr_mcp_add("fs", command = "npx", args = c("-y", "@modelcontextprotocol/server-filesystem", "."))
```

#### `gptr_mcp_serve()` — P18, `mcp-server.R` [stable]

```r
gptr_mcp_serve(tools = c("r", "read", "edit", "write"), envir = parent.frame(), port = NULL,
               stop = FALSE)
```

Serves the live session over loopback Streamable HTTP (both MCP eras): binds `127.0.0.1` on `port` (`NULL` = a
free port from `port_candidates()`, never `httpuv::randomPort()`, IC-61), requires a 192-bit bearer token
(`openssl::rand_bytes(24)`, hex), validates `Origin`, and runs every call through the permission gate as a nested
call of a dedicated session (`kind = "chat"`, label `mcp`) whose home is `envir`. The listening socket is shared:
CLI children get their own tokens bound to their sessions through `mcp.serve_ensure(session)` (IC-58). Needs httpuv, later and openssl (`gptr_error_missing_package`). Returns a
`gptr_mcp_handle` (§5.11): `$url`, `$port`, `$token_env` (the name `GPTR_MCP_TOKEN`; the token itself is only
placed in child environments and in `$config` snippets marked as secret), `$config` (client snippets for Codex,
Claude Code, Claude Desktop, Cursor with a tool timeout of at least 3,600 s), `$stop()`. One server per process:
calling again returns the running handle; `stop = TRUE` stops it and returns `invisible(NULL)`. Requests are served
while the outermost reactor pump runs (`later::run_now(0)` at depth 1, IC-57) or at an idle console, where a
request that needs approval is denied with how to allow it (never a prompt from a callback). Copy-safety: [R2] (`envir` is held
only while the server runs, in an environment binding reset by `$stop()`). Emits `mcp_serve_start`,
`mcp_serve_stop` (notify).

```r
# starts a server (roxygen wraps it in \dontrun{})
if (interactive()) {
  h = gptr_mcp_serve(envir = globalenv())
  h$config$codex                      # a client snippet (the token comes from the child's environment)
  gptr_mcp_serve(stop = TRUE)
}
```

### 6.4 Documents and artifacts

#### `gptr_doc()` — P15, `doc-replay.R` [stable]

```r
gptr_doc(path = NULL, format = NULL, sync = FALSE)
```

`path = NULL`: returns the current binding `list(path, format)` or `NULL`, visibly. A path binds every `peter()`
call of this R process (console and script) to that document, which is explicit consent to write it (IC-45);
`FALSE` unbinds. `sync = TRUE` applies the pending blocks recorded for that document (a Jupyter notebook that was
open while recording, or unapplied deferred-write sidecars) through the format's writer (IC-50, IC-51). `format`: `"r"`, `"rmd"`,
`"qmd"`, `"ipynb"`, `"transcript"`; `NULL` = from the extension. Returns the previous binding invisibly.
Conditions: `invalid_argument`.

The binding lives in `the$doc_binding` for this R process; nothing is written until a block is recorded.

```r
f = tempfile(fileext = ".R"); writeLines("library(gptr)", f)
gptr_doc(f)
gptr_doc()
gptr_doc(FALSE)
```

#### `gptr_source()` — P15, `doc-replay.R` [stable]

```r
gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)
```

Sources `file` top-level expression by expression in `envir` so that stale or live blocks regenerate without
executing the old block (which base `source()` cannot do [14 §4.4.2]); fresh blocks replay (their code runs as
ordinary R). Returns `invisible(<gptr_blocks>)` with an extra `action` column (`replayed`, `regenerated`, `ran`,
`skipped`). Conditions: `invalid_argument`, `not_recorded`, `stale_block` (replay mode), plus whatever the sourced
code signals. Side effects: those of the sourced code; document writes for regenerated blocks. Copy-safety:
[R1][R2].

```r
f = tempfile(fileext = ".R")
writeLines(c("x = 1", "y = x + 1"), f)
gptr_source(f, replay = "replay", envir = new.env())
```

#### `gptr_blocks()` — P15, `doc-replay.R` [stable]

```r
gptr_blocks(file)
```

Returns a `gptr_blocks` data frame (§5.12) of the agent blocks in `file` (`.R`, `.Rmd`, `.qmd`, `.ipynb`), with
status `fresh`, `stale`, `user-edited` or `undone`. Reads only.

```r
f = tempfile(fileext = ".R")
writeLines(c('peter("add one")', '# >>> gptr:7f3a21 model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2',
             'x = 1 + 1', '# <<< gptr:7f3a21'), f)
gptr_blocks(f)
```

#### `gptr_cache()` — P15, `doc-replay.R` [stable]

```r
gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp"))
```

`info` returns a `gptr_cache_info` data frame (including unapplied document sidecars, which are never pruned
automatically, IC-51); `prune` removes S2 entries of deleted blocks, S1 entries unused for
90 days (mtime touched on hit), `cache/tmp` files older than `gptr.spill_days`, the refreshed catalog cache beyond
the newest, checkpoint blobs per G7 retention; `clear` removes the kind entirely. `prune`/`clear` return the number
of files removed invisibly. Works on the workspace root (or `tempdir()/gptr`) and `R_user_dir("gptr", "cache")`.

```r
gptr_cache()
gptr_cache("prune", "tmp")
```

#### `gptr_artifacts()` — P23, `artifact-registry.R` [stable]

```r
gptr_artifacts(id = NULL, open = FALSE, stop = FALSE, version = NULL)
```

Without `id`: a `gptr_artifacts` data frame (after a lazy orphan sweep). With `id`: the `gptr_artifact` handle;
`open = TRUE` opens it in the viewer or browser (interactive only; relaunches a stopped artifact); `version =
<int>` relaunches that immutable version; `stop = TRUE` stops its process (interrupt, 3 s grace, `kill_all()`).
Conditions: `invalid_argument` (unknown id), `artifact`, `missing_package` (shiny). Emits `artifact_start`,
`artifact_stop`.

```r
gptr_artifacts()                      # an empty listing when no artifact exists
```


### 6.5 Session SDK

Every verb takes the session object first so it composes with `|>`; none needs internals (G1 §4.6).

#### `gptr_step()` — P08, `gptr-sdk.R` [stable]

```r
gptr_step(s, turns = 1L)
```

`s`: `<session>`; `turns`: `int(1)` >= 1 or `Inf`. If `s` is idle with queued input (`.run = FALSE`, a queued
follow-up or steer), starts a run; then pumps the reactor until `turns` `turn_end` events of `s` have occurred or
the run settles. A running (background) session is advanced the same way. Returns `invisible(s)`. Conditions:
`invalid_argument`; the §6.1.2 terminal-status conditions when the run settles in that status. Emits the run's
events.

```r
s = peter("Plan the analysis", model = gptr_fake_provider(list("Plan: ...")), .run = FALSE,
         envir = new.env())
gptr_step(s)
s$turns
```

#### `gptr_wait()` — P08, `gptr-sdk.R` [stable]

```r
gptr_wait(x, timeout = Inf)
```

`x`: `<session>` or a list of sessions (a team or fan-out session counts as one). Starts idle sessions that have
queued input, then pumps the reactor until every one has settled or `timeout` seconds passed. Returns
`invisible(x)`. On timeout the sessions keep running (background) or are left `running` with their run
suspended (foreground) and a `timeout` condition is **not** raised; the function returns and the statuses say
`running`. Conditions: `invalid_argument`; terminal-status conditions only for a single session.

```r
fake = gptr_fake_provider(list("a"))
runs = list(a = peter("one", model = fake, .run = FALSE, envir = new.env()),
            b = peter("two", model = fake, .run = FALSE, envir = new.env()))
gptr_wait(runs, timeout = 10)
vapply(runs, function(x) x$status, "")
```

#### `gptr_steer()` — P08, `gptr-sdk.R` [stable]

```r
gptr_steer(s, text, as = c("steer", "follow_up"))
```

The one enqueue function behind the pipe into a running session, the pause menu and `ctx$send()` (C-16).
`text`: `chr(1)` (redacted with the `context` profile at ingress). Appends `list(text, blocks = list(), source,
t)` to the session's `steer` or `follow_up` FIFO and returns `invisible(s)` at once. Steers are delivered only
after a complete tool-result message as an operator relay; follow-ups when the agent would otherwise stop; on an
idle session the item is taken at the next run start. Emits `queue_update`.

```r
s = peter("Summarise mtcars", model = gptr_fake_provider(list("ok")), .run = FALSE, envir = new.env())
gptr_steer(s, "Use only the mpg column", as = "follow_up")
```

#### `gptr_cancel()` — P08, `gptr-sdk.R` [stable]

```r
gptr_cancel(x)
```

Aborts the run of a session (or of each session in a list): `curl::multi_cancel()` of its transfers, interrupt then
`kill_all()` of its child processes after a grace period, the partial turn recorded with
`stop_reason = "aborted"`, queued items moved to `dropped`, status `aborted`. Idle sessions: no-op. Returns
`invisible(x)`. Emits `agent_end` (status `aborted`).

```r
s = peter("long task", model = gptr_fake_provider(list(list(hang = TRUE))), .run = FALSE,
         envir = new.env())
gptr_cancel(s)                        # idle: a no-op
```

#### `gptr_fork()` — P06, `session-object.R` [stable]

```r
gptr_fork(s, at = NULL, envir = c("overlay", "shared"))
```

| Argument | Type | Meaning |
|---|---|---|
| `s` | `<session>` | the source |
| `at` | `NULL`, `int(1)` >= 0, or `chr(1)` entry id | cut: `NULL` = the last closed boundary (a running source is cut there); `k` = end of turn `k`; `0` = empty conversation; an entry id = that entry |
| `envir` | `"overlay"` or `"shared"` | `overlay`: the fork evaluates in `new.env(parent = <source home>)` (zero-copy reads, isolated writes); `shared`: the same home |

Returns a new idle `<session>` with a new id whose transcript is the source path up to the cut (entry ids kept and
re-chained); its JSONL file is written lazily at its first own message with `parentSession` and `gptr.forkOf`;
the source's rank-0 specs (providers, tools, agents given as call arguments) are registered again for the fork,
but nothing live is shared (listeners, queues, connections, processes, locks, usage) (INFRA-14). Emits
`session_start` (reason `fork`) to process-wide hooks. Copy-safety: [R1][R2]: the overlay's parent is the
source's kept home (`globalenv()`, an explicit `envir`, or the source's own overlay), never a function frame. A
source without a kept home (its calls ran in function frames) yields a fork without a kept home as well: each of
the fork's turns evaluates in the caller of that `peter()` call, and a `notice` message says so.

```r
fake = gptr_fake_provider(list("A", "B"))
s = peter("first", model = fake, envir = new.env())
f = gptr_fork(s)
f |> peter("branch")
c(s$turns, f$turns)
```

#### `gptr_on()` — P08, `gptr-sdk.R` [stable]

```r
gptr_on(s, event, handler, matcher = NULL)
```

Registers a session-scoped hook (rank 0, source `session`). `event`: a catalogued event name (§10.4) or a channel
containing `:`; a Claude/Codex name (`PreToolUse`, ...) signals `gptr_error_invalid_argument` with "did you mean
'tool_call'?". `handler`: `function(event, ctx)` returning what §10.4 allows for that event. `matcher`: `NULL`, a
tool-name glob (`"r"`, `"mcp__github__*"`) for tool events, or `function(event) lgl(1)`. Listeners are never
copied by `gptr_fork()`. Returns a zero-argument function that removes the hook (invisibly). Conditions:
`invalid_argument`.

```r
s = peter("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
log = new.env()
log$roles = character()
off = gptr_on(s, "message_end", function(event, ctx) {
  log$roles = c(log$roles, event$message$role)
  NULL
})
gptr_step(s)
off()
log$roles
```

#### `gptr_parallel()` — P19, `subagent-team.R` [stable]

```r
gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))
```

`gptr_parallel()`: each `...` argument (named) is a `peter()` call, forced under a dynamic flag so that it returns
an unstarted session, or a session created with `.run = FALSE`; `.list` is a named list of such sessions. All run
concurrently on one reactor (at most `max_active`, default `gptr.subagents.max_active`, IC-71). Returns a **team session**
(`kind = "team"`, children named by the argument names; `$text` joins the reports under `### <name> (<model>)`,
`$value` is the named list of child values). `on_error = "stop"` signals the first child's condition after all
children settled; `"return"` leaves failed children with status `error`.

`gptr_map()` is **internal** (IC-36; S-1 keeps one gateway): the function behind `parallel =`, one inline (or
`backend`) child per element of `.x` (a list, atomic vector or data frame rows), each receiving the prompt and its
element as context (read in place by name, `.x[[i]]`); it returns a **fan-out session** (`kind = "fanout"`;
`$text` a named chr, `[[i]]`/`$name` child sessions). Users write `peter("Summarise this", cohorts, parallel = 4)`.
Copy-safety: [R1][R3] (elements are read in place; `test-copy-subagent.R`).

```r
fake = gptr_fake_provider(list("ok"))
team = gptr_parallel(plan = peter("Plan it", model = fake, envir = new.env()),
                     lit = peter("Summarise it", model = fake, envir = new.env()))
names(team$children)
```

#### `gptr_sessions()`, `gptr_resume()`, `gptr_last()` — P06, `session-store.R`, `session-live.R` [stable]

```r
gptr_sessions(project = TRUE)
gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)
gptr_last()
```

`gptr_sessions()`: a `gptr_sessions` data frame of stored sessions of the workspace store (`.gptr/sessions/`, or
`tempdir()/gptr/sessions/` without a workspace); `project = FALSE` adds live sessions of this process that are not
in that store. Reads only the header and last lines of each file.

`gptr_resume()`: `x` = `NULL` (the most recently updated stored session), a session id, a file path, or a detached
`<session>` (from `saveRDS()`/knitr cache/callr). Returns the live object if one exists in this process;
otherwise rebuilds the session from its JSONL (leaf = last entry; status `idle` when the tail is a final answer,
else `interrupted`) with home `envir`; a rebuilt **fork** always gets a fresh `new.env(parent = envir)` overlay
(IC-46). A file from another machine or tracked by git is rebuilt with a freshly frozen prompt and its user turns
marked `imported` (IC-52). A detached copy follows the split-brain rules of §5.1 of `03` (`gptr_error_split_brain`).
`block = "<id>"` (and `child = "<name>"` for team blocks) returns the session that replay bound to that document
block in this process, or signals `gptr_error_replay_unbound`; it never falls back to `envir` (IC-46). Conditions:
`invalid_argument`, `split_brain`, `busy`, `replay_unbound`.

`gptr_last()`: the most recently active session of this process, held **strongly** (IC-71), including one whose
call was interrupted before assignment, or `NULL`.

```r
s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
identical(gptr_last(), s)
gptr_sessions()
identical(gptr_resume(s$id), s)      # the live object is returned
```

#### `gptr_jobs()` — P04, `proc-supervise.R` (IC-36) [stable]

```r
gptr_jobs(kill = FALSE)
```

Returns a `gptr_jobs` data frame of the job table (IC-12): background sessions (rows added by P21, status
`waiting` when an ask is pending, IC-57), `peter$bg()` jobs, artifacts, the MCP server, workers and CLI children. `kill = TRUE` stops them all (sessions are cancelled, processes killed with
`kill_all()`) and returns the table of what was stopped invisibly.

```r
gptr_jobs()
```

#### `gptr_usage()` — P06, `session-budget.R` (IC-05) [stable]

```r
gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)
```

`x`: `<session>`, a list of sessions, or `NULL` (every live session of this process plus the process System 1
log). `detail = FALSE`: a `gptr_usage` data frame aggregated by `by`, children rolled up, with attribute `totals`;
`detail = TRUE`: the `gptr_ledger` per request and component (§4.3). Reads only.

```r
s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
gptr_usage(s)
```

#### `gptr_rewind()`, `gptr_checkpoints()` — P16, `ckpt-rewind.R` [stable]

```r
gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"),
            force = FALSE, preview = FALSE)
gptr_checkpoints(s, all = FALSE)
```

`gptr_rewind()` is G7's branch-in-place on the same object: `turn` negative = relative (`-1` undoes the last turn),
`0` = before the first turn, `k` = keep turns `1..k`; `to` = an entry id from `gptr_checkpoints()` (overrides
`turn`; any node, including abandoned branches, which is how redo works); `restore = "all"` restores objects, files,
state and the conversation leaf, `"conversation"` only the leaf, `"workspace"` only objects/files/state;
`force = TRUE` also restores items changed since (3-way conflicts); `preview = TRUE` returns the plan (a data frame of
items and whether each would be restored) and changes nothing. Appends one `gptr.rewind` entry (the JSONL stays
byte-append-only). Returns `invisible(s)` (so it pipes), with `s$last_rewind` and `s$editor_text` set. Warns
`gptr_warning_rewind_partial` when some items were not restored. Conditions: `busy` (running), `rewind_range`,
`invalid_argument`. Emits `session_before_tree` (first decision; a handler may cancel) and `session_tree`
(notify). Copy-safety: [R1][R6] (pre-images are released or swapped by reference, never copied).

`gptr_checkpoints()`: a `gptr_checkpoints` data frame of the active path (`all = TRUE`: all branches).

```r
fake = gptr_fake_provider(list("done"))
s = peter("step", model = fake, envir = new.env())
gptr_checkpoints(s)
```

### 6.6 Agent-side and introspection

#### `gptr_return()` — P08, `gptr-sdk.R` [stable]

```r
gptr_return(x)
```

Called by model-written (or user) R code during a run to designate the run's result. Captures `substitute(x)`
and forces `x` in a leaf; the session stores it under the §5.1 value policy of `03` (symbol bound in a kept home and
below `gptr.value_copy_max`: deep copy; larger: name + address; anonymous or bound in a function-frame home: boxed),
capped by `gptr.values_max_bytes`, and appends a `gptr.value` entry. Returns `invisible(NULL)`. Outside a run it
returns `invisible(x)` and does nothing else (a once-per-session `notice`, silent while a document is replayed), so
recorded code that still contains the call re-sources cleanly (IC-48). Copy-safety: [R1][leaf] (`test-copy-tools.R`
rows for the three cases).

#### `gptr_describe()` — P09, `env-describe.R` [stable]

```r
gptr_describe(x, budget = 150L, ...)
```

S3 generic for compact, budgeted object descriptions (the `<attached>` and `<workspace>` blocks, `peter$describe()`,
the `@object` console mention). `budget`: `int(1)` >= 20, estimated tokens (`est_tokens(, "describe")`).
Returns a character vector of lines, the first a header `<class> shape, size`, at most `budget` estimated
tokens (the harness truncates longer method output). Methods MUST follow [R4][leaf]: no promise forcing, no I/O
(no `dbListTables()`, no `collect()`), no `str()` on the object. Built-in methods: `default`, `data.frame`,
`matrix`, `list`, `formula`, `lm`, `environment`, `function`, `dgCMatrix`, `ArrowTabular`, `Dataset`,
`DBIConnection`, `Seurat`, `SingleCellExperiment`, `ggplot`; `factor`, `Date`, `POSIXct` and `S4` (`isS4()`)
dispatch through `default`, `data.table` through `data.frame` and `glm` through `lm` (D-142). Level-based: a method
may accept `level = 1:4` in `...` and return successively richer descriptions; the harness picks the richest that
fits. Methods for classes of packages outside Suggests (`dgCMatrix`, `ArrowTabular`, `Dataset`, `Seurat`,
`SingleCellExperiment`, `ggplot`) use only base generics, `methods::slot()`/`slotNames()`, `attr()` and `dim()`
guarded by `isNamespaceLoaded()`, never `pkg::fun()` (IC-71). Packages add methods with delayed
`S3method(gptr::gptr_describe, cls)`. Copy-safety: [R4].

```r
gptr_describe(mtcars, budget = 60)
```

#### `gptr_prob()` — P13, `s1-types.R` (IC-36) [stable]

```r
gptr_prob(x, what = c("prob", "confidence", "probabilities"))
```

`x`: a System 1 vector (§5.2). Returns the named attribute: `prob` (num, decisions; for choices and scores the
probability of the chosen option / the confidence), `confidence` (num), `probabilities` (matrix; for decisions a
two-column matrix `FALSE`, `TRUE`). Conditions: `invalid_argument` for other classes.

```r
judge = gptr_fake_provider(list(0.9, 0.2), name = "judge", type = "classifier")
d = peter("Is this about dogs?", c(a = "A puppy.", b = "A car."), model = judge)   # not `jev`: a known alias wins
gptr_prob(d)
```

#### `gptr_risk()` — P11, `perm-classify.R` [stable]

```r
gptr_risk(code, envir = NULL, root = NULL)
```

The advisory static classifier (not a security boundary). `code`: chr (R code) or a call/expression; `envir`:
optional environment the code would run in (enables overwrite-size detection by leaf `object.size()` of bound
names; read-only lookups, never forcing promises); `root`: project root (default `project_root()`). Never
evaluates `code`. Returns a `gptr_risk` (§5.11). Commands passed to `peter$sh()` are classified with the command
table, `peter$sql()`/`peter$py()` with keyword classifiers (P11 registers them for P22). Copy-safety: [R4].

```r
gptr_risk("unlink('data', recursive = TRUE)")$level
```

#### `gptr_prompt()` — P07, `prompt-sections.R` [stable]

```r
gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)
```

`x`: `<session>` (its frozen system blocks, tool array and first message) or `NULL` (what a new session would
freeze now with the current settings, `preset` or the default preset). Returns a `gptr_prompt_view` (§5.11);
`tokens = TRUE` adds per-section estimates. No model call. Conditions: `invalid_argument`.

```r
gptr_prompt(preset = "minimal")
```

#### `gptr_redact()` — P03, `auth-redact.R` [stable]

```r
gptr_redact(x, profile = c("persist", "stream", "context", "code", "user_data"))
```

`x`: chr, or a list (recursively; opaque replay fields of §3.9 of G6 are never touched). Returns `x` with
registered secret values (and their derived forms) and, except for `user_data`, the pattern layer replaced by
`[secret:<NAME>]` markers; the `code` profile rewrites a literal secret in R code to `Sys.getenv("NAME")`.
Idempotent. Never errors on invalid UTF-8 (bytewise fallback).

```r
gptr_redact("Authorization: Bearer abcdef0123456789abcdef")
```

#### `gptr_scrub()` — P03, `auth-redact.R` (IC-70) [stable]

```r
gptr_scrub(paths = NULL, dry_run = TRUE, error = FALSE)
```

Audits (and, on request, cleans) persisted text for registered secrets that entered history before they were
registered. `paths`: `NULL` = the workspace's sessions, caches, spill files, plans, transcripts and the documents
bound in this project; or a chr of files and directories. Returns a data frame `file`, `secret` (the variable
name), `count` (never values), visibly with `dry_run = TRUE`. `error = TRUE` signals `gptr_error_secret_found` when
any row exists (pre-commit and CI use). `dry_run = FALSE` rewrites the listed files replacing values and derived
forms with `[secret:NAME]` markers (the only sanctioned rewrite of append-only files; each rewritten session file
gets a `gptr.scrub` entry) and returns the data frame invisibly. Called from model code during a run with
`dry_run = FALSE` it is a `control`-category action (IC-53). Conditions: `invalid_argument`, `secret_found`.

```r
d = tempfile("proj"); dir.create(d)
writeLines("nothing secret here", file.path(d, "notes.txt"))
gptr_scrub(d)
```

#### `gptr_preimage()` — P16, `ckpt-objects.R` (IC-01) [experimental]

```r
gptr_preimage(x, name, ctx, ...)
```

S3 generic deciding how the object checkpointer captures a binding before a mutating tool call. `x` is the
object (the method is a leaf [R4]); `name` its binding name; `ctx` a list(`predicted` = chr in `assign`,
`modify`, `byref`, `remove`, `none`; `bytes` num(1); `budget` num(1)). Returns
`list(mode = "ref" | "copy" | "none", reason = chr(1) | NULL, copy = <deep copy> | NULL)`: `ref` (the caller binds
the original object into its private pre-image environment; default for value-semantics objects), `copy` (the
method returns a deep copy in `copy`; the `data.table` method does this for `:=`/`set*()` targets within budget),
`none` (not restorable; `reason` explains, e.g. environments, R6, external pointers). Packages add methods with
delayed `S3method(gptr::gptr_preimage, cls)`.

### 6.7 Extension API

#### `gptr_api()` — P02, `ext-check.R` [stable]

```r
gptr_api()
```

Returns a `gptr_api` list: `version = package_version("1.0")` (the extension API version, independent of the
package version) and `features` (chr: `kind.<name>` for every registered kind, `event.<name>` for every catalogued
event, and named features `lazy_activation`, `declarations`, `ctx.decide`, `ctx.secret`, `route`, `services`).

```r
gptr_api()$version
"kind.router" %in% gptr_api()$features
```

#### `gptr_register()` — P02, `ext-registry.R` [stable]

```r
gptr_register(spec)
```

Registers a spec at top level (rank 3, source `user`, process lifetime) after validation by its kind. Returns an
unregister function invisibly. Inside a factory the verb is `gptr$register(spec)` (§10.5); per session it is
`peter(..., tools = list(spec))` (rank 0). Conditions: `invalid_spec`, `unknown_kind`. Emits nothing (records are
visible to the next session freeze; already frozen sessions are unchanged).

```r
off = gptr_register(gptr_command("hello", function(args, ctx) "hi"))
off()
```

#### `gptr_registry()` — P02, `ext-registry.R` [stable]

```r
gptr_registry(kind = NULL, diagnostics = FALSE)
```

`kind`: `NULL` or chr of kinds. Returns `gptr_registry` (or `gptr_diagnostics` with `diagnostics = TRUE`), §5.5.

```r
gptr_registry("tool")
gptr_registry(diagnostics = TRUE)
```

#### `gptr_reload()` — P02, `ext-load.R` [stable]

```r
gptr_reload()
```

Re-discovers declarative resources (skills, prompts, agents, MCP configs, plugin manifests), re-declares lazily
activated plugins, bumps the registry generation so that captured API objects raise `gptr_error_stale_api`, and
returns the new generation invisibly. Frozen sessions are not re-frozen.

```r
gptr_reload()
```

#### `gptr_check()` — P02, `ext-check.R` [stable]

```r
gptr_check(x, error = FALSE, tokens = FALSE)
```

`tokens = TRUE` also reports a plugin's declaration cost and the printed-result cost of each member on its examples
(IC-69); for an installed package it flags bare gptr identifiers in package code (IC-42). Runs the conformance
suite for `x`: a spec (fields, kind validator, schema validity, direct tool descriptions at
most 400 tokens, section/block/catalog budgets, empty-input handling for tools), a factory `function(gptr)`
(loaded eagerly in a scratch registry: every manifest `provides` entry registered, no action at load), an
installed package name (`chr(1)`: manifest, API requirement, factory), an adapter spec (fixture replay through
`check_adapter()`, which P12 registers as the `check.adapter` service; a list `tool_choice` sent while the model
capability `forced_tool_choice` is `FALSE` fails: golden events, error as event, chunk
invariance, byte-identical opaque round trip), a policy (report 18 §4.7 matrix), a backend (cancel leaves no
process). Returns a `gptr_check` data frame; with `error = TRUE` a failing row signals `gptr_error_conformance`.
No network.

```r
gptr_check(gptr_tool("add", "Add two numbers",
                     parameters = list(type = "object", required = I(c("a", "b")),
                                       properties = list(a = list(type = "number"),
                                                         b = list(type = "number"))),
                     fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
```

#### `gptr_fake_provider()` — P01, `provider-fake.R` [stable]

```r
gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))
```

Returns a `<spec:provider>` (`id = name`, `api = "fake"` or `"fake-classifier"`, `type`, one model `name/<name>-1`
or `name/<name>-s1`, `offline = TRUE`; IC-21, IC-35) whose engine plays `script`; usable as `model = <spec>` (registered at rank 0 for that session) or through
`gptr_register()`. The script grammar is §12.1. No network, no keys; examples and tests everywhere use it.

#### `gptr_tool_result()` — P02, `ext-specs.R` [stable]

```r
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
```

`text`: chr (joined with `"\n"` into one text block); `images`: list of image blocks, PNG file paths or raw PNG
vectors (converted with `block_image()`); `details`: named list; `is_error`: `lgl(1)`; `value`: any R value
returned to R callers of the member (never sent to a model, never persisted). Returns a `gptr_tool_result`
(§5.7).

```r
gptr_tool_result("3 rows", details = list(n = 3L), value = 3L)
```

#### `gptr_spec()` — P02, `ext-specs.R` [stable]

```r
gptr_spec(kind, name, ...)
```

Builds and validates a spec of any registered kind (the 11 exported constructors are sugar for the common kinds;
the other kinds, including plugin-defined ones, use this). `...` are the kind's fields (§10.2). Returns
`<spec:kind>`. Conditions: `invalid_spec`, `unknown_kind`.

```r
gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
```

### 6.8 Spec constructors (P02, `ext-specs.R`) [stable]

Each returns `<spec:kind>` after validation (field contracts in §10.2). Arguments not listed in §10.2 for the kind
signal `gptr_error_invalid_spec`.

```r
gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL,
          exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL,
          execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL,
          guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE,
          available = NULL, annotations = list())
gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
              type = c("chat", "classifier", "cli"), headers = list(), discover = NULL,
              status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)
gptr_adapter(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"),
             build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())
gptr_router(name, route, description = NULL, timeout = 2)
gptr_hook(event, handler, matcher = NULL)
gptr_policy(name, check, description = NULL)
gptr_agent(name = NULL, description = NULL, model = NULL, tools = NULL, skills = NULL,
           system = NULL, backend = c("auto", "inline", "worker", "cli"), preset = "minimal",
           max_turns = NULL, mode = NULL, objects = NULL, export = NULL, returns = NULL, file = NULL)
gptr_command(name, handler, description = NULL, complete = NULL)
gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)
gptr_context_block(name, provide, placement = c("turn", "first", "both"),
                   authority = c("data", "operator"), budget = 300L, order = 650L)
gptr_backend(name, start, poll = NULL, cancel, capabilities = list())
```

Notes that cross plans: `gptr_adapter()` validates per transport (`http_*` and `process_jsonl` need `build` and
`parse`, `inprocess` needs `stream`, classifier adapters need `classify`; IC-35). `gptr_agent()` with only `name`
(or `file`) loads the definition through the `agent_def.get` service of P17 (`gptr_error_not_available` before
P17); inside `peter(agents = list(...))` `agent()` is this function; `model` and `skills` accept bare identifiers,
and `gptr_agent()` stores the raw captured expressions (symbol names or literals), which the gateway resolves
(§6.1.3), so P02 never calls P08 (it is itself a capture site obeying [R3]; IC-34). A `gptr_context_block()` with
`authority = "operator"` is accepted only from records of rank >= 3 (IC-52). `gptr_prompt_section(parent =)` makes
the spec a fragment of the named section (IC-68). `gptr_tool()` requires
at least one of `execute` (direct/deferred/hidden tools; `function(input, ctx)`) and `fun` (`exposure = "r"` members;
an R function whose formals match the schema properties); a direct tool with `fun` only gets a generated
`execute` that calls `fun` with the validated input and returns `as_tool_result(<printed value within
output_tokens>)`, and an `r` member with `execute` only gets a generated `fun`.

Examples (one per constructor):

```r
gptr_tool("nrow_of", "Number of rows of a data frame in the session",
          parameters = list(type = "object", required = I("name"),
                            properties = list(name = list(type = "string"))),
          fun = function(name) nrow(get(name, envir = globalenv())), exposure = "r",
          namespace = "demo")
gptr_provider("corp", api = "openai-completions", base_url = "https://llm.corp.example/v1",
              auth = "CORP_LLM_KEY", models = list(list(id = "corp-large", context = 128000)))
gptr_adapter("echo", transport = "inprocess",
             stream = function(model, context, opts) {
               state = new.env()
               state$done = FALSE
               function() {
                 if (state$done) return(NULL)
                 state$done = TRUE
                 list(events = list())        # a real adapter emits start ... done here
               }
             })
gptr_router("cheapest", route = function(request, ctx) "anthropic/claude-haiku-4-5")
gptr_hook("tool_result", function(event, ctx) NULL, matcher = "r")
gptr_policy("no_installs", check = function(call, ctx) {
  if (identical(call$name, "r") && grepl("install.packages", call$input$code, fixed = TRUE)) {
    list(decision = "deny", reason = "installs are not allowed here")
  } else {
    NULL
  }
})
gptr_agent("stats", description = "Statistical reviewer", model = "anthropic/claude-opus-5-5",
           skills = "statistics")
gptr_command("rows", function(args, ctx) paste("rows:", nrow(mtcars)), description = "Show rows")
gptr_prompt_section("house_rules", "Use SI units in every table.", tier = "T1", order = 780L)
gptr_context_block("lab_notebook", function(ctx, budget) "Experiment 12: cohort B only.",
                   placement = "first", order = 650L)
gptr_backend("echo", start = function(spec, ctx) NULL, cancel = function(handle) NULL)
```


---

## 7. Internal interfaces that cross plan boundaries

All functions in this section are [internal] (`@noRd`, not exported). Each is listed once, under its owning plan
and file, with its consumers. A consumer may rely on exactly what is written here and nothing else. "Leaf"
functions follow [leaf] (§1.3).

### 7.0 Package state (`the`) and the service table

`the = new.env(parent = emptyenv())` is created in `aaa-state.R` (P01; collates first, IC-32). Each field has one
owner; other plans read it only through the owner's functions (INFRA-15: no run state here).

| Field | Owner | Content |
|---|---|---|
| `on_load`, `on_unload`, `once`, `out`, `services`, `redactor` | P01 | load-time expressions; unload callbacks; once-keys of `gptr_warn(.once =)`; the process-level `peter$out()` store for user calls outside a run (sessions keep their own, IC-71); the bootstrap service table (IC-09, IC-34); the installed redaction hook |
| `registry`, `kinds`, `hooks`, `builtins`, `diagnostics` | P02 | registry env; kind table; event index; built-in declarations; diagnostics log |
| `vault`, `secrets`, `redactor` | P03 | secret values; secret metadata; compiled redaction patterns |
| `reactor`, `jobs` | P04 | the process reactor; the job table (IC-12) |
| `catalog`, `s1_log` | P05 | merged model catalog; process System 1 accounting log |
| `live`, `last`, `replay_blocks` | P06 | weak index of live sessions `id -> weakref(key = shell, value = live)`; the last session, held strongly (IC-71); block id -> the session replay bound to it (gptr-created sessions only, IC-46) |
| `settings_session`, `interp` | P08 | R-process settings layer; interpolation notices |
| `rules_session`, `plan_pending` | P11 | R-process permission rules; pending plans keyed by environment address string |
| `s1_cache` | P13 | in-memory System 1 cache (before a workspace exists) |
| `doc_binding`, `doc_pending` | P15 | console document binding; deferred Rscript writes |
| `mcp_conns`, `mcp_server`, `mcp_tokens` | P18 | MCP connections; the running `gptr_mcp_serve()` server; bearer token -> session id (IC-58) |
| `bg` | P21 | background pump state |

Services (IC-09) are named functions registered with `ext_service_set(name, fun, provided_by, builtin)` (P01, §7.1)
by their provider plan in an `on_load()` expression, and fetched with `ext_service_get(name)` (signals
`gptr_error_not_available` naming the providing plan when absent or when the owning built-in is filtered out; once
P02 is loaded a `service` registry record of lower rank replaces the bootstrap entry, IC-34). The complete list:

| Service | Provider | Consumers | Signature |
|---|---|---|---|
| `settings.get` | P08 | `setting_get()` (P01), hence every plan | `function(key, session = NULL) value` (all layers of §11.2) |
| `prompt.freeze` | P07 | the first run of a session (P06) | `function(s, opts) frozen list` |
| `context.first`, `context.turn` | P07 | run input assembly (P06, via `gateway_run()` of P08) | `function(s, input) list of context blocks` |
| `request.build` | P07 | every model request of a run (P06) | `function(s, target, extra = NULL) list(context, view, tokens_est, components)` |
| `prefix.guard` | P07 | every model request (P06) | `function(s, target, view) invisible(NULL)` |
| `compact.should`, `compact.run` | P07 | turn boundaries and overflow recovery (P06) | `function(s, tokens, idle_s) lgl(1)`; `function(s, reason, focus = NULL) invisible(s)` |
| `ns.resolve` | P10 | `$.gptr_gateway` (P08) | `function(path) <gptr_member or gptr_ns>` |
| `console.interrupt_policy` | P14 | `session_run()` (P06), SDK verbs (P08) | `function(expr_fun, runs, mode = c("call", "repl")) value` |
| `ui.get` | P11 | `ctx$ui()`, `ctx$has_ui()`, `perm_check()` (P06) | `function(session = NULL) <spec:ui>` |
| `risk.classify` | P11 | `r` tool (P10), bridges (P22), `ctx$risk()` | `function(code, envir = NULL, root = NULL, kind = c("r", "command", "sql", "python")) <gptr_risk>` |
| `plan.pending` | P11 | `plan` context block (P07) | `function(envir_address, consume = TRUE) chr(1) or NULL` |
| `s1.decide` | P13 | `ctx$decide()` | `function(question, x, ...) <gptr_s1>` |
| `doc.site` | P15 | `r` tool record flag (P10), `documents` section (P07) | `function(session) list(path, format) or NULL` |
| `doc.edit` | P15 | `edit` tool (P10) | `function(path, edits, session) <gptr_tool_result> or NULL` (NULL: not a bound document) |
| `doc.s1_block` | P15 | top-level System 1 calls (P13) | `function(call, summary) invisible(NULL)` (writes the one-line block) |
| `doc.replay` | P15 | `team` and `fanout` routes (P19) | `function(call) <session> or NULL`: the replayed team or fan-out session for a fresh block, else `NULL` (IC-47) |
| `checkpoint.note` | P16 | permission detail view (P11) | `function(call, run) chr(1) or NULL` ("cannot be undone: ...") |
| `agent_def.get` | P17 | `gptr_agent()` (P02) | `function(name, file = NULL) <spec:agent>` |
| `skill.catalog`, `skill.body` | P17 | `skills =` preloads (P08/P07), `peter$search()` (P10) | `function(session, budget) chr(1)`; `function(name) list(text, dir)` |
| `plugin.enable` | P17 | `peter(plugins =, extensions =)` (P08) | `function(name, rank, session = NULL) invisible(lgl(1))` |
| `mcp.catalog` | P18 | `peter$search()` (P10) | `function(session, budget) chr(1) or NULL` |
| `mcp.dispatch_local` | P18 | `cli-claude` (P20) | `function(message, session) list` (JSON-RPC response) |
| `mcp.serve_ensure` | P18 | `cli-codex` (P20), `cli` backend (P19) | `function(session) <gptr_mcp_handle>` |
| `bg.register` | P21 | `peter(background = TRUE)` (P08), the pause menu (P14) | `function(session) invisible(session)` |
| `check.adapter` | P12 | `gptr_check()` (P02) | `function(adapter, fixtures = NULL) <gptr_check>` |
| `trust.get` | P08 | P03 (`.env` discovery), P07 (SYSTEM.md, instruction authority), P17, P18 (IC-33) | `function(path = getwd()) lgl(1)`; fallback `FALSE` |
| `identifier.resolve` | P08 | `gptr_agent()` capture (P02), agent files (P17) | `function(expr, arg, envir) chr or spec`; fallback: literal names |
| `secret.lookup` | P03 | `ctx$secret()` (P02) | `function(name, ctx = NULL) <handle> or NULL`; fallback `NULL` |
| `ctx.kernel` | P06 | `ctx_new()` (P02) | `function() named list` of the §10.6 member implementations marked P06 |
| `ctx.input` | P07 | `ctx$input` (P02) | `function(ctx) list or NULL` |
| `ns.names` | P10 | `.DollarNames.gptr_gateway` (P08) | `function(pattern) chr`; fallback `character(0)` |
| `eval.r` | P09 | `ctx$eval()` (P02), P18 server `r`, P14 `!expr` | `eval_r()` through the `evaluator` kind (IC-69) |
| `describe` | P09 | `ctx$describe()` (P02) | `function(x, budget) chr` |
| `router.call` | P08 | every request of a routed session (P06) | `function(s, reason) list(model, thinking, state)` (IC-69) |
| `session.add_tools` | P07 | `ctx$add_tools()`, `gateway_run()` continuations | `function(s, specs) invisible(s)` (IC-69) |
| `search.sources` | P10 | `peter$search()` | `function(session) df(id, text, kind)` from `search_source` records (IC-69) |

Until a provider plan is loaded, P06 uses documented fallbacks for the P07 services (freeze: empty T0/T1 and the
direct tools' JSON; first message: the prompt alone; request: the projected messages; no prefix guard; no
compaction), so P06's tests run before P07 exists. Every other consumer treats a missing service as
`gptr_error_not_available`, except `setting_get()` (option layer, then default).

### 7.1 P01 Foundation

**`utils-options.R`**

| Function | Returns | Consumers |
|---|---|---|
| `gptr_opt(name)` | the option value or the §3.1 default (`NULL` for settings-backed options) | all |
| `gptr_has_human()` | `lgl(1)`: `getOption("gptr.interactive")` if set, else `interactive()` and not knitting and not under testthat and not `check_running()`; decides streaming and verbosity only | P06, P08, P14, P15 |
| `gptr_can_prompt()` | `lgl(1)`: `getOption("gptr.interactive")` if set, else `interactive() \|\| isTRUE(getOption("jupyter.in_kernel"))`, excluding knitr, testthat and `check_running()`; decides every question (IC-43) | P06 (`perm_check()`), P08, P11, P14, P15 |
| `gptr_is_interactive()`, `gptr_readline(prompt = "")` | wrappers of `interactive()` and `readline()` (mockable with `testthat::local_mocked_bindings()`) | P11, P14 |
| `gptr_confirm(question, default = FALSE)` | `lgl(1)`: `y`/`yes` (case-insensitive) is `TRUE`; empty input gives `default`; when `gptr_can_prompt()` is `FALSE` returns `default` without asking; never `askYesNo()` | P08, P15 |
| `front_end()` | `chr(1)`: `rstudio`, `positron`, `vscode`, `jupyter`, `knitr`, `quarto`, `rscript`, `terminal`, `rgui`, `unknown` | P07, P14, P15 |
| `verbosity()` | `int(1)` 0-3 (§3.1 `gptr.verbose`) | P14, P06 |
| `check_running()` | `lgl(1)`: `_R_CHECK_PACKAGE_NAME_` is set | P04, P15, P19 |
| `on_load(expr)` (`aaa-state.R`, IC-32) | stores `substitute(expr)` and `parent.frame()`; `.onLoad` evaluates them in registration order after the namespace is loaded | all built-in declarations |
| `on_unload(fun)` (`aaa-state.R`) | registers a zero-argument cleanup run by `.onUnload` (reverse order, each in `try()`) | P04, P18, P21, P23 |
| `supervise_default()` | `lgl(1)`: `isTRUE(getOption("gptr.supervise"))` when set, else `!check_running()` (IC-60) | P04, P19, P23 |
| `s3_register(generic, class, method = NULL)` | delayed S3 registration for Suggests generics (`"knitr::knit_print"`, `"vctrs::vec_proxy"`), vctrs-style | P13, P15 |
| `ext_service_set(name, fun, provided_by, builtin = NULL)` (`aaa-state.R`) | registers a service (IC-09) in `the$services`, owned by `builtin`; a second registration replaces the first (recorded as a diagnostic once P02 is loaded) | all service providers |
| `redactor_set(fun)`, `redact_hook(x, profile = "persist")` (`aaa-state.R`) | the redaction hook: identity until P03 installs `redact()` (IC-34) | P01, P02, P03 |
| `` `%||%` `` (`aaa-state.R`) | internal null default (base has it only from R 4.4) | all |
| `ext_service_get(name)`, `ext_service_has(name)` | the function (or `gptr_error_not_available` naming the providing plan) / `lgl(1)` | all |
| `setting_get(key, session = NULL, default = NULL)` | the effective setting: the `settings.get` service (P08: all layers of §11.2) when registered, else the option layer (`gptr_opt(key)`) and then `default`; every plan reads settings through it | all |

**`utils-conditions.R`**: §1.1 checkers, §2.1 constructors, `msg_verbatim()`, `gptr_deprecated()` (the redaction
hook itself lives in `aaa-state.R`, IC-32, IC-34).

**`utils-hash.R`**

| Function | Contract | Consumers |
|---|---|---|
| `with_seed_preserved(expr)` [leaf] | evaluates `expr` and restores (or removes) `.Random.seed` in the global environment afterwards; one of the two functions allowed to assign it (IC-61) | P18, P23 |
| `port_candidates(n = 20L)` | int: RNG-free ports in 49152-65535 from `id_new()` hash bits (IC-61) | P18, P23 |
| `hash_sha256(x)` | chr -> chr of 64-hex digests (vectorised, UTF-8 bytes); raw -> chr(1) | P03, P13, P15, P16 |
| `hash_xxh128(x)`, `hash_file(path)` | `rlang::hash()` / `rlang::hash_file()` wrappers (32 hex) | P16 |
| `canonical_json(x)` | chr(1): JSON with object keys sorted by `order(method = "radix")` recursively, `digits = NA`, `auto_unbox = TRUE`; byte-identical across locales | P13, P15, P07 |
| `id_new(prefix = "", n = 10L)` | chr(1) `prefix` + `n` lower hex; RNG-free | all |
| `id_entry(taken = NULL)` | 8-hex entry id not in `taken` (grows to 12 after 100 collisions) | P06 |
| `id_block(taken = character())` | 6-hex id with at least one letter a-f, grown to 8, 10, ... 16 on collision | P15 |
| `fingerprint(x)` [leaf] | chr(1): type, length, attribute and column addresses, 64 sampled values (never expanding compact row names or ALTREP sequences) | P09, P16 |

**`utils-encoding.R`**: `as_utf8(x)` (the ingress normaliser of IC-62: unknown-encoded valid UTF-8 is marked UTF-8,
other unknown strings go through `enc2utf8()`; the only place `enc2utf8()` may be called), `utf8_mark(x)` (marks valid UTF-8 as UTF-8, leaves ASCII), `os_bytes(x)` (native bytes
for argv/env/wd), `raw_to_utf8(x, fallback = "CP1252")` (-> chr(1)), `read_utf8(path)` -> `list(text = chr(1),
eol = "\n" | "\r\n", bom = lgl(1), encoding = chr(1), final_newline = lgl(1))`, `write_utf8(path, text, eol =
"\n", bom = FALSE, final_newline = TRUE)` (binary connection, atomic via `write_atomic()`). Consumers: P03, P04, P10, P15, P18.

**`utils-paths.R`**

| Function | Contract | Consumers |
|---|---|---|
| `project_root(path = getwd())` | chr(1) (§1.2); `options(gptr.project_root)` or `GPTR_PROJECT_ROOT` override it (IC-63) | all |
| `user_home()`, `app_config_dir(app)` | the user's home (`USERPROFILE` on Windows, else `HOME`, else `path.expand("~")`) and an application's config directory (`%APPDATA%`, `~/Library/Application Support`, `$XDG_CONFIG_HOME` or `~/.config`) (IC-63) | P17, P18 |
| `path_key(path)` | normalised path, lower-cased on Windows and macOS (IC-51) | P08, P11, P15 |
| `rscript_path()` | `file.path(R.home("bin"), "Rscript")` (`Rscript.exe` on Windows), never a PATH lookup (IC-60) | P04, P19, P20, tests |
| `gptr_user_dir(which = c("config", "cache", "data"), create = FALSE)` | `tools::R_user_dir("gptr", which)`; created only when `create = TRUE` | P03, P05, P08, P18 |
| `workspace_dir(path = getwd())` | chr(1) path of an existing `.gptr/` of `project_root(path)`, or `NULL` | all |
| `workspace_root(create = TRUE)` | `workspace_dir()` if non-NULL, else `file.path(tempdir(), "gptr")` (created lazily) | P06, P11, P15, P16, P23 |
| `ws_path(..., create_parent = TRUE)` | `file.path(workspace_root(), ...)` with parents created | P06, P11, P15, P16, P23 |
| `write_atomic(path, content)` | writes chr (UTF-8, LF) or raw to a temp file in the same directory, then `file.rename()` (3 retries with 100 ms sleeps, then an in-place `writeBin()` after an md5 re-check, IC-51); returns `invisible(path)` | all writers |
| `save_rds(object, file, compress = FALSE, refhook = NULL)` [R7][leaf] | `saveRDS(object, file, ascii = FALSE, compress = compress, refhook = refhook)`; the only `saveRDS` of user data | P16, P19, P23 |
| `serialize_leaf(object, xdr = TRUE)` [R7][leaf] | `serialize(object, NULL, ascii = FALSE, xdr = xdr)` | P16 |
| `path_norm(path)`, `path_rel(path, root = project_root())` | normalised absolute / root-relative paths (symlink-safe: the deepest existing ancestor is resolved) | P10, P11, P15, P16 |
| `path_class(path, root = project_root())` | chr: `workspace`, `temp`, `outside`, `protected`, `control` (level 4, IC-54), `instructions` (level 3, IC-54), `critical`, `url`, `wildcard`, `unknown` [18 §3.8] | P10, P11, P16 |

**`utils-text.R`**

| Function | Contract | Consumers |
|---|---|---|
| `truncate_output(text, budget_tokens, class = "r_output", head = 0.4)` | `list(text = chr(1), truncated = lgl(1), omitted = int(1), total_lines = int(1), out_id = chr(1) \| NULL, spill = chr(1) \| NULL)`; keeps the first 40% and last 60% of lines within the budget, inserts `[... n lines omitted; all: peter$out(<id>)]`, stores the full text with `out_put()` and a spill file | P09, P10, P18, P22 |
| `out_put(text, stream = "stdout", meta = list(), session = NULL)` | chr(1) id `o` + 6 hex (RNG-free); kept in the session's store (the process store when `session` is `NULL`), the last `gptr.out_keep` entries (IC-71) | P09, P22 |
| `out_get(id, stream = c("stdout", "stderr"), lines = NULL, session = NULL)` | chr (lines) from the session store, then the process store, then the spill file; `gptr_error_invalid_argument` when none has it | P10 (`peter$out`) |
| `spill_write(text, prefix)` | path `<prefix>.txt` under `ws_path("cache", "tmp")`; redacted with `persist` | P09, P22 |
| `clean_terminal(x)` | removes ANSI/OSC sequences, collapses `\r` progress, caps lines at 400 characters | P09, P22, P04 |
| `new_listing(df, class, footer = NULL)` | the listing classes of §5.12 and their shared `print` method | P02, P05, P06, P11, P15-P18, P21, P23 |

**`utils-tokens.R`**: `est_tokens(x, class = c("prose", "code", "r_output", "str", "csv", "json", "error",
"describe"))` -> `num(1)` using the G2 constants of §12.5 of `03` (CJK 0.848 tokens/char, other non-ASCII 0.35);
`est_image_tokens(width, height, api = "anthropic")` -> `num(1)` (Anthropic `ceil(w/28) * ceil(h/28)`; OpenAI and
Gemini formulas from the catalog); `est_multiplier(state, estimated, reported, prior)` -> updated
`list(m = num(1), n = int(1))` (EWMA of the log ratio, updated only when `estimated >= 150`). Consumers: P06, P07,
P09, P10, P17, P18, P24.

**`json-encode.R`**: `json_encode(x, pretty = FALSE)` -> `chr(1)` (UTF-8 marked); `json_decode(text)` -> list
(`simplifyVector = FALSE`, input marked UTF-8 first); `json_verbatim(text)` -> `structure(text, class = "json")`
(embedded verbatim by `json_encode()`); `json_obj()` -> `structure(list(), names = character())`. Consumers: all.

**`json-partial.R`**: `partial_json()` -> environment with `push(delta)`, `value()` (best-effort named list or
`NULL`), `text()`, `complete()` (`lgl(1)`). Consumers: P12 (tool-call previews), P14.

**`json-schema.R`**: `schema_validate(schema, input)` -> `list(ok = lgl(1), input = named list, errors = chr)`:
missing required properties are errors naming the property; types are checked; the only coercions are
integer-valued numbers to integer when the schema says `integer`, and a scalar to a length-1 array when the schema
says `array` of scalars; unknown properties are kept unless `additionalProperties = FALSE`. `schema_signature(name,
schema, description = NULL, prefix = "")` -> `chr(1)` `name(a: string, b?: number)  # <first sentence>`.
`schema_problems(schema)` -> chr (empty when valid). Consumers: P02, P06, P10, P18.

**`provider-message.R`**, **`provider-events.R`**: §4 constructors; `ev_new(type, ...)`; `acc_new()` -> accumulator
environment with `push(ev)` and `message()` (the assistant message built from INFRA-02 events with closure
buffers, linear time). Consumers: P05, P06, P12, P13, P20.

**`provider-fake.R`**: `gptr_fake_provider()` (§6.7), `fake_stream(model, context, opts)` (the `inprocess`
generator of §8.1, playing the script of §12.1), `fake_classify(model, requests, opts)` (the classifier fake of
§12.1), `builtin_fake(gptr)` (registers adapters `fake` and `fake-classifier`; declared by P05, IC-08).

**`zzz.R`**: `.onLoad(libname, pkgname)` runs `the$on_load` expressions, then `ext_load_builtins()` if P02 is
present; `.onUnload(libpath)` runs `the$on_unload`. No disk, no network, no processes at load.

Example calls:

```r
gptr_inform("using the plan from session s12", "plan_handoff")   # silent under gptr.quiet
id = id_new("s", 10L)
key = hash_sha256(canonical_json(list(b = 1, a = "x")))
tr = truncate_output(utils::capture.output(print(1:1e5)), budget_tokens = 400L)
out_get(tr$out_id, lines = 1:3)
est_tokens(utils::capture.output(summary(lm(mpg ~ wt, data = mtcars))), "r_output")
line = json_encode(msg_to_json(msg_user("hello")))
acc = acc_new()
acc$push(ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1"))
save_rds(mtcars, ws_path("cache", "tmp", "mt.rds"))
```

### 7.2 P02 Extension API and registry

**`ext-registry.R`**

| Function | Contract |
|---|---|
| `registry_add(spec, source, rank, session = NULL, state = "active")` | validates `spec` (its kind's validator), stores a record (§5.5) and returns its id; `session` (a session id) scopes rank-0 records; bumps nothing |
| `registry_remove(id)` | `invisible(lgl(1))` |
| `registry_get(kind, name, session = NULL)` | the winning **spec** for `(kind, name)` (lowest rank among enabled records; ties: first registered, with a `collision` diagnostic), after filters, including the session's rank-0 records; `NULL` if none. A lower-rank record shadows only the record with the same `(kind, name)` (IC-69). Lazy records trigger `ext_activate()` of their source first |
| `registry_all(kind, session = NULL)` | list of specs of an `all`-resolving kind (hook, policy, context_block, prompt_section, route, checkpointer, secret_source, redaction_rule, env_alias, risk_rule) ordered by the kind's `order` field when it has one, else by rank then registration; for `first`-resolving kinds, the winning spec of each name |
| `registry_names(kind, session = NULL)` | chr of names with an enabled record |
| `registry_generation()` | `int(1)` |
| `registry_filters_set(filters, scope = c("session", "user", "project"))` | applies `-builtin:<name>`, `-plugin:<pkg>`, `-<kind>:<name>`, `+...`; project filters that would disable user or built-in `policy`/`hook` records are ignored with a diagnostic; no filter from any source disables `builtin:permissions`, `builtin:plan`, `critical_guard` or `secret_guard`, and inside a run filters that remove `policy`/`hook` records are refused (IC-53) |
| `registry_diagnostic(source, event, class, message)` | appends to `the$diagnostics` (redacted) |
| `gptr_register()`, `gptr_registry()` | §6.7 |

**`ext-specs.R`**: `kind_define(name, validate, resolve = c("first", "all"), fields = chr, order_field = NULL,
experimental = FALSE, source = "builtin")` (used by P02 for its 37 kinds and through the `kind` kind by plugins and
P22, IC-69), `kind_get(name)`, `kind_names()`, `spec_new(kind, name, ...)` (build + validate; the engine behind
`gptr_spec()` and the constructors), `as_tool_result(x)`, and the exports of §6.7-6.8.

**`ext-events.R`**

| Function | Contract |
|---|---|
| `ev_dispatch(event, payload, session = NULL, ctx = NULL)` | runs session listeners of `session` then registry hooks for `event` in rank order with the event's semantics (§10.4); payload redacted with `stream` first; returns: `NULL` (notify), the merged list (collect), the final text (transform), the decision list (decision, first decision), the patched payload (patch, block + patch). A handler error is a diagnostic, except for the fail-closed events (`tool_call` -> block, `permission_request` -> deny, `document_write` -> block) |
| `ev_catalogue()` | df `event`, `semantics`, `fail_closed`, `payload`, `returns`, `origin` (`pi`, `gptr`) |
| `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)` | id; validates the event name (unknown and Claude/Codex names are `gptr_error_invalid_argument` with a hint); channel names contain `:` |
| `hook_remove(id)` | `invisible(lgl(1))` |

**`ext-api.R`**

| Function | Contract |
|---|---|
| `ext_api_new(source, dir = NULL, manifest = NULL)` | the `gptr_extension_api` handed to a factory (§10.5) |
| `ctx_new(session, run = NULL)` | the `gptr_ctx` of a session (one per session; §10.6); `run` sets the run whose tool is executing |

**`ext-load.R`**: `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)` ->
`lgl(1)`: with `session` (a session id) every staged record is scoped to that session and removed at its
`session_shutdown` or finalizer (IC-69); stages every registration of the factory and commits only when it returns; a thrown error, an unmet API
requirement or a missing method rolls back all staged records and records a diagnostic (`warning plugin` once);
`lazy = TRUE` registers `manifest$extension$provides` placeholders (state `lazy`) and the manifest
`declarations`, and runs the factory on the first `registry_get()` of a provided name or the first dispatch of a
provided event. `ext_activate(source)` -> `lgl(1)`. `gptr_reload()`.

**`ext-builtins.R`**: `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (records a
built-in in `the$builtins`; called from `on_load()` expressions in the declaring files; `replaceable` now only
decides whether a `-builtin:<name>` filter may disable it, since overrides are per record, IC-69), `ext_load_builtins()`
(loads declared built-ins with `ext_load(source = "builtin:<name>", rank = 6L)` in dependency order given by
`after`, skipping filtered ones; called by `.onLoad`).

**`ext-check.R`**: `gptr_check()`, `gptr_api()`, `check_spec(spec)`, `check_factory(factory)`,
`check_package(pkg)` (each -> `gptr_check` rows).

Example calls:

```r
id = registry_add(gptr_command("rows", function(args, ctx) "32"), source = "user", rank = 3L)
tool = registry_get("tool", "r")
policies = registry_all("policy")
res = ev_dispatch("tool_call", list(tool_name = "r", tool_call_id = "c1", input = list(code = "1 + 1")),
                  session = s)
ext_service_set("risk.classify", gptr_risk, provided_by = "P11")
ui = ext_service_get("ui.get")(s)
ok = ext_load(function(gptr) gptr$register(gptr_command("hi", function(args, ctx) "hi")),
              source = "plugin:demo", rank = 5L)
```

### 7.3 P03 Secrets and redaction

| Function | File | Contract | Consumers |
|---|---|---|---|
| `secret_register(value, name, source = "user", active = TRUE, origin = NULL)` | `auth-secrets.R` | the only entry point for secret values; returns a `gptr_secret` handle; recompiles the redaction literals | P05, P18, P20, P22 |
| `secret_value(handle, origin)` | `auth-secrets.R` | `chr(1)`; `gptr_error_untrusted` when `origin` (scheme + host + port) differs from the handle's bound origin; callers: **only** `http-request.R` (P04) and `auth-childenv.R` | P04 |
| `secret_lookup(name)` | `auth-secrets.R` | handle or `NULL` | P05, P11 |
| `secret_discover_env(env = Sys.getenv())` | `auth-secrets.R` | registers secret-looking variables (G6 §3.3); `invisible(int(1))` count; called at session start | P06 |
| `secret_registered_names()` | `auth-secrets.R` | chr of registered variable names (for the classifier's secret guard) | P11 |
| `redact(x, profile = "persist")` | `auth-redact.R` | chr -> chr (§6.6 `gptr_redact()` semantics) | all sinks |
| `redact_tree(x, profile = "persist", structural = FALSE)` | `auth-redact.R` | recursive over lists; never touches opaque replay fields (G6 §3.9) | P02, P06, P15 |
| `redact_stream(profile = "stream")` | `auth-redact.R` | environment with `push(chunk)` -> chr(1) (safe to emit now) and `flush()` -> chr(1); bounded hold-back; fails closed with `redaction_limit` on an unresolved sensitive candidate above the cap (D-010 clarification below) | P04 (child pipes), P06 (event text), P14 |
| `code_for_history(code)` | `auth-redact.R` | literal secret -> `Sys.getenv("NAME")` | P15 |
| `dotenv_parse(path)` | `auth-dotenv.R` | df(`name`, `value`, `line`) with attribute `bad_lines` | P03 internal, P08 (trusted project `.env`) |
| `alias_resolve(names, aliases = NULL)` | `auth-dotenv.R` | chr of canonical names | P03 |
| `auth_store_get(key)`, `auth_store_set(key, record)`, `auth_store_remove(key)` | `auth-store.R` | credential store (`auth.json`, 0600, lock, keyring references; §11.8) | P05, P18 |
| `child_env(profile, pass = character(), set = character(), provider = NULL)` | `auth-childenv.R` | the **complete** named chr for processx `env` (removed names absent; processx rejects `NA`); `profile` in `mcp`, `worker`, `cli-claude`, `cli-codex`, `helper`, `artifact` or a registered `child_env` spec name; **every** profile sets `R_ENVIRON_USER`/`R_PROFILE_USER` to empty files and drops `R_ENVIRON` unless passed (IC-60); the CLI profiles follow G6 §3.7 verbatim (IC-65) | P04, P18, P19, P20, P22, P23 |
| `child_env_callr(env)` | `auth-childenv.R` | the callr form of a `child_env()` result: every variable of `Sys.getenv()` absent from `env` added as `NA` | P19, P23 |
| `secret_scan(code, tainted = character())` | `auth-secrets.R` | `list(findings = df(rule, name, level, guard), level = int(1), guard = lgl(1), assigned = chr)` (G6 §3.8) | P11 |
| `builtin_secrets(gptr)` | `auth-secrets.R` | registers `secret_source`, `redaction_rule`, `env_alias`, `child_env` specs | P02 load |
| `gptr_scrub()` | `auth-redact.R` | §6.6 (IC-70); `secret_register()` also scans live sessions' in-memory entries for a new value and warns `secret_late` with counts | users, P24 |

Example calls:

```r
h = secret_register(Sys.getenv("ANTHROPIC_API_KEY"), "ANTHROPIC_API_KEY", source = "env",
                    origin = "https://api.anthropic.com")
redact("the key is [value here]", "persist")
rs = redact_stream("stream")
emit_now = rs$push("Authorization: Bearer ab")
emit_rest = rs$flush()
env = child_env("worker", provider = "anthropic")
```

**D-010 implementation clarification (2026-10-03).** An unresolved sensitive
candidate must never be made emit-safe merely because it exceeds
`gptr.stream_hold_max`. In that case the redactor raises
`gptr_error_redaction_limit` with the numeric `limit` and a generic message that
contains no input. It discards held text and remains failed: later `push()` or
`flush()` calls cannot release that candidate. Stream/whole-output parity
applies within the supported bound; overflow terminates the stream instead of
returning a partial unredacted candidate. This supersedes the raw-prefix
overflow fallback in the historical P03 Task 3 example and G6 prototype.

### 7.4 P04 Reactor and process engine

The reactor API is specified in §8.2. Process engine (`proc-spawn.R`, `proc-supervise.R`):

| Function | Contract | Consumers |
|---|---|---|
| `proc_spawn(command, args = character(), env = NULL, wd = NULL, stdin = NULL, stdout = "\|", stderr = "\|", cleanup_tree = TRUE, supervise = supervise_default())` | a `processx::process` created with `encoding = "UTF-8"` (IC-60) and a tree marker under `R_user_dir("gptr", "cache")/procs/` for the orphan sweep; `command` resolved with `Sys.which()` (R itself only through `rscript_path()`); `.cmd`/`.bat` run as `cmd.exe /d /c call <shim> args` refusing `% ^ & \| < > " !` CR LF in any argument (`gptr_error_invalid_argument`); argv, wd and env through `os_bytes()`; `stdin = NULL` is the null device, `"\|"` a pipe | P18, P19, P20, P22 |
| `proc_run(command, args = character(), input = NULL, timeout = 120, env = NULL, wd = NULL, echo = FALSE)` | runs to completion with stdout/stderr redirected to temp files (never `processx::run()`), a `p$wait(200)` loop, `on.exit(kill_all(p))`; returns `list(status = int(1), stdout = chr(1), stderr = chr(1), timed_out = lgl(1), elapsed = num(1))` decoded as UTF-8 with the code-page fallback | P20, P22 |
| `shell_resolve(cmd)` | `list(command, args)` for a string command: Unix `/bin/sh -c`; Windows Git Bash, else PowerShell `-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand <base64 UTF-16LE>` with a `$LASTEXITCODE` postfix, else `cmd /d /s /c "chcp 65001 >nul & ..."` [G5] | P22 |
| `write_all(p, data)` | queues chr (as `charToRaw(as_utf8(x))`) or raw for the child's stdin; the reactor drains the buffer non-blockingly with `write_input()` (which writes at most about 8 KB per call), reading stdout/stderr between attempts, within `gptr.stdin_timeout` (`gptr_error_timeout` otherwise); outside the reactor it loops the same way (IC-60) | P18, P19, P20 |
| `line_reader(p, stream = "stdout", max_line = 16 * 1024^2)` | environment with `read()` -> chr of complete lines (at most 512 chunks per call), `partial()` | P04, P18, P19, P20 |
| `kill_all(p, grace = 2)` | interrupt, wait `grace`, `kill_tree()`, Windows `taskkill /F /T /PID`, then `$kill()`; `invisible(lgl(1))` | P18, P19, P20, P22, P23 |
| `job_add(kind, id, name, pid = NA, stop, status = function() "running")` | adds a row to the job table (IC-12); `stop` is a zero-argument function that also sets `stop_requested`, so a later non-zero exit maps to `stopped`/`aborted`, never `error` (IC-60) | P18, P19, P20, P21, P22, P23 |
| `job_remove(id)`, `job_list(kind = NULL)` | job table maintenance; `job_list()` returns a df (`id`, `kind`, `name`, `pid`, `status`, `started`) | P04 (`gptr_jobs()`), P21 |
| `pid_alive(pid, create_time = NULL)` | `lgl(1)`: `ps::ps_is_running(ps::ps_handle(pid))` and, when given, an equal process creation time (pid reuse); never `tools::pskill()` (IC-59) | P06, P15, P23 |
| `gptr_jobs()` | §6.5 (IC-36) | users |

Example calls:

```r
p = proc_spawn("git", c("status", "--porcelain"), env = child_env("helper"))
res = proc_run("claude", "--version", timeout = 5)
job_add("bg", "j1", "tail log", pid = p$get_pid(), stop = function() kill_all(p))
id = reactor_http(spec, on_bytes = function(raw) NULL, on_done = function(status, headers) NULL,
                  on_fail = function(cnd) NULL, provider = "anthropic")
reactor_pump(until = function() done, slice_ms = 100L)
```

### 7.5 P05 Model layer core

| Function | File | Contract | Consumers |
|---|---|---|---|
| `project_messages(entries, leaf, target)` | `provider-transform.R` | the model-context message list for `target` (a model record) along the path root -> `leaf`: compaction entries replace the prefix; aborted/errored assistant entries dropped; orphaned tool calls get a synthetic result (`"interrupted after <s> s; side effects may have occurred"` or `"No result provided"`); steering relays placed after complete tool-result messages; then `handoff_transform()`. Never edits entries | P06, P07 |
| `handoff_transform(messages, target)` | `provider-transform.R` | same model: keeps signatures and opaque blocks; otherwise thinking becomes text (or is dropped when `target` lacks reasoning replay), opaque blocks dropped, tool ids normalised to the target api's rules (Mistral 9 chars, etc.) | P06, P20 |
| `provider_get(id)` | `provider-registry.R` | `<spec:provider>` or `NULL` | P05, P08, P13, P20 |
| `adapter_get(api)` | `provider-registry.R` | `<spec:adapter>` or `gptr_error_not_available` | P06, P13, P20 |
| `provider_credential(provider)` | `provider-registry.R` | a handle bound to the provider's configured origin, resolved in the order explicit > vault > credential store > keyring > environment table (§8 of `03`); `NULL` for providers without auth; `gptr_error_no_key` otherwise | P05, P13 |
| `provider_stream(model, context, opts, emit, done, run = NULL)` | `provider-registry.R` | starts one model request on the reactor through the model's adapter (§8.1); returns the transfer/task id; calls `emit(ev)` for every INFRA-02 event and `done(msg)` exactly once with the final assistant message; never throws after it returns (INFRA-02) | P06, P07 (compaction), P13 (emulation) |
| `builtin_providers(gptr)` | `provider-registry.R` | registers the provider records of §8.1-8.2 of `03` as data; P05 also declares `builtin:fake` (IC-08) | P02 load |
| `usage_new(...)`, `usage_cost(usage, model, when = Sys.Date())`, `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)` | `provider-usage.R` | §4.3 records; cost from the dated price tier in force on `when`; TTL-split cache writes (1 h at 2x input, 5 min at 1.25x) | P06, P12, P13, P20 |
| `usage_log_append(row)`, `usage_log()` | `provider-usage.R` | the process System 1 accounting log (append-only) | P13, P06 |
| `catalog_get()` | `catalog-models.R` | the merged catalog (§11.10) | P05, P07 |
| `model_resolve(ref, strict = TRUE)` | `catalog-models.R` | a model record (§4.9) for `provider/id[:thinking]`, an alias (dynamic by family and release date), or a provider-less id; `strict = TRUE` signals `gptr_error_unknown_model` with `adist()` suggestions; local providers accept unknown ids | P06, P08, P13, P17, P19 |
| `model_prepare(ref, safety = NULL)` | `catalog-models.R` | explicit selected-model preparation: discovers missing/stale Ollama evidence, then resolves and preflights; no discovery during replay (IC-74; `07-local-ollama.md` section 2.1) | P08, P13 |
| `provider_preflight(model, provider, safety = NULL)` | `catalog-models.R` | pure no-I/O check before payload/state/image serialization and credential lookup; private discovery evidence binds endpoint/path/model/server/lifecycle; missing protected safety means local-only TRUE (IC-74; `07-local-ollama.md` section 2.1) | P05, P08, P13 |
| `catalog_aliases()` | `catalog-models.R` | chr of alias names (for `identifier_known()`) | P08 |
| `model_default(role = c("chat", "small", "system1"))` | `catalog-models.R` | `chr(1)` ref from settings, else the first available route (§8.4 of `03`), else `NULL` | P08, P07, P13 |

Example calls:

```r
m = model_resolve("sonnet")
msgs = project_messages(session_data(s)$entries, session_data(s)$leaf, m)
id = provider_stream(m, request_build(s, m)$context, list(), emit = function(ev) NULL,
                     done = function(msg) NULL)
egress_check("anthropic")
row = usage_row(msg, session = s$id, agent = "main", parent_id = NA_character_, started = Sys.time(),
                seconds = 1.2, multiplier = 1)
```

### 7.6 P06 Session kernel and agent loop

**`session-object.R`, `session-live.R`**

| Function | Contract | Consumers |
|---|---|---|
| `session_new(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL, opts = list())` | a new idle `<session>`: id, `.d` defaults, weak live registration, `secret_discover_env()`, egress not yet checked; `home` is kept only when it is not a function frame (`globalenv()`, an explicit `envir`, an overlay) [R2]; the prompt is frozen lazily at the first run (the `prompt.freeze` service, P07) so that `session_start` handlers can contribute | P08, P13 (as_state), P19 |
| `session_data(s)` | the `.d` environment | P06-P23 (read); writes only through the functions below |
| `session_live(s)` | the live record or `NULL` (detached copy) | P06, P14, P19, P20, P21 |
| `session_home(s)` | the kept home or `NULL` | P09, P16, P19 |
| `session_append(s, entry)` | appends an entry (R shape) to `.d$entries` and the store (`persist` redaction at ingress, inside `suspendInterrupts()`), moves the leaf, returns the entry id invisibly | all plans that write entries |
| `session_set_model(s, ref, reason = "user")` | resolves `ref`, appends `model_change`, emits `model_select` | P08, P14 |
| `session_set_mode(s, mode, source = "user")` | appends `gptr.mode_change`; the next user message (idle) or an operator message after the current tool results (running) carries the new `<mode>` block | P08, P11, P14 |
| `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())` | the queue behind `gptr_steer()`; `source` in `pipe`, `pause_menu`, `repl`, `api_user`, `extension`, `agent`; only user sources become operator relays; a call from model code of the same session tree is refused (IC-55) | P08, P14, P19 |
| `session_value_set(s, label, value, name = NULL, forced_home = NULL)` | the §5.1 value policy of `03`; appends `gptr.value` | P08 (`gptr_return()`), P15 (replay `value=`), P19 (child values) |
| `session_value_get(s, turn = NULL)` | the value (or `NULL`), resolving names in the kept home | P06 accessors, P19 |
| `live_all()` | list of live sessions of this process | P06, P21 |
| `last_set(s)` | updates `the$last` (a strong reference, IC-71) | P06, P08 |

**`session-store.R`** (IC-59): `store_open(s)` (resolves `<workspace_root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl`
lazily at the first entry, writes the header §4.7, creates the lock `<file>.lock/pid` with pid and process
creation time; on an existing file whose last byte is not LF it first appends `"\n"` and a `gptr.recovered`
entry), `store_append(store, entries)` (one line per entry: `json_encode()` of the §4.6 JSON shape; the file is
opened with `file(path, "ab")`, written, flushed and closed through `on.exit()` inside `suspendInterrupts()`; no
connection outlives the call), `store_read(path)` -> `list(header, entries)` (skips any unparsable line with a
diagnostic; children of missing ids are re-parented to the nearest valid ancestor in projection),
`store_fork(s, cut, new)`, `store_rebuild(path, home)` -> `<session>` (a fork gets a fresh
overlay `new.env(parent = home)`), `store_heartbeat(store)` (touches the lock every 10 minutes from a reactor
timer). There is no `store_close()`: the lock is released when the session is collected or the package unloads
(D-154). Consumers: P06, P15 (replay), P16.

**Replay functions** (`session-object.R`, IC-46): `session_replay_apply(s, block, header, text = NULL)` (advances
the piped session in place: `gptr.replay` entry, `seen`, `turns`, the `value=` name, `last_text`; returns `s`),
`session_replay_new(block, header, envir, doc)` (the live session with the header's id, else a `replayed` session
adopting the recorded id, from the JSONL or reconstructed from the document with `history_source =
"reconstructed"`),
`session_replay_bind(block, s, child = NULL)` and `replay_lookup(block, child = NULL)` (the `the$replay_blocks`
table behind `gptr_resume(block =)`). Consumers: P15, P19.

**`session-budget.R`**: `budget_check(s, estimate = 0)` -> `NULL` or `list(kind, budget, used)`;
`ledger_add(s, request_id, components)`; `gptr_usage()` (§6.5).

**`agent-run.R`**

| Function | Contract | Consumers |
|---|---|---|
| `session_run(s, input, opts = list())` | appends the input (a user message or queued items) and runs `s` to settlement on the reactor under the interrupt policy (`console.interrupt_policy` service if present, else abort-only); returns `s` invisibly; raises nothing itself (the gateway maps terminal statuses to conditions, §6.1.2) | P08, P14, P15, P19 |
| `run_start(s, input, opts = list())` | the non-blocking form: returns a `gptr_run` registered with the reactor (strong reference until settled); snapshots the safety options of IC-53 into the run | P08 (`.run`, background), P19, P21 |
| `run_wait(runs, timeout = Inf, background = FALSE)` | pumps the reactor until every run settled (with `background = TRUE`, or was sent to the background) or `timeout`; `invisible(lgl(1))` all done | P08, P19 |
| `run_abort(run, reason = "user")` | cancels transfers and children, records the partial with `stop_reason = "aborted"`, moves the queue to `dropped` | P08, P14, P21 |
| `run_current()` | the innermost run whose tool is executing on this call stack (for nested calls), or `NULL` | P08 (`nested` route), P10, P19 |
| `run_eval_env(run)` | the environment where `r` evaluates for this run: the scratch overlay in plan mode (IC-15), a child overlay for inline sub-agents, else the home (a function-frame home is held in the run's `home` binding only, reset at settlement) [R2] | P09, P10, P16, P22, P23 |
| `run_emit(run, type, ...)` | builds and dispatches an agent event for the run (stream-profile redaction first) | P06-P23 |

Run options (`opts`): `max_turns` (int), `budget` (list), `doc` (document site from P15 or `NULL`), `returns`
(JSON Schema or `NULL`), `context` (`"summary"`, `"names"`, `"none"`), `timeout` (num: `r` timeout), `interactive`
(lgl: a human can answer), `depth` (int), `parent_run` (run id), `agent` (label), `background` (lgl),
`rng_state` (environment holding the child's `c(10407L, <6 seeds>)` L'Ecuyer vector for `rng_swap()`, IC-61),
`preset`, `tools` (chr modifiers), `call` (the `gptr_call`, released at settlement), `safety` (the option
snapshot of IC-53), `root` (the root session id for budgets, IC-66).

`gptr_run` fields (read-only for other plans): `id`, `session` (id), `status` (`queued`, `requesting`,
`streaming`, `tools`, `boundary`, then a terminal status), `turn`, `mode`, `model` (record), `depth`,
`parent_run`, `opts`, `signal` (environment: `aborted`, `reason`), `started`, `children` (chr session ids).

**`agent-dispatch.R`**

| Function | Contract | Consumers |
|---|---|---|
| `dispatch_tools(run, calls)` | executes a turn's tool calls in source order; for each: lookup (unknown -> error result `Tool <name> not found`), `tool_validate()`, `tool_call` hooks, `perm_check()`, checkpointers' `before`, execute (sequential tools through `reactor_enqueue_tool()`; concurrent ones as reactor work), checkpointers' `after`, `tool_result` hooks; never throws; a `length`/`refusal` stop fails every call unrun; returns `list(results = list(<gptr_tool_result>), terminate = lgl(1))` | P06 |
| `dispatch_nested(name, input, ctx)` | the nested entry for `peter$...` calls made while an `r` evaluation runs: if the outer code's static analysis listed this function at a level no higher than the level approved for the outer call, runs without a second prompt; otherwise `perm_check()`; records into the outer result's `details$nested` (at most 20); returns the tool result's `value` (or signals the tool's error as an R error of class `gptr_error_tool` inside the model's code) | P10, P18, P22, P23 |
| `tool_validate(tool, input)` | `schema_validate()` of the tool's `parameters`; `{"INVALID_JSON": raw}` when the final strict parse failed | P06, P18 |
| `perm_check(call, run)` (IC-04, IC-53) | `list(decision = "allow" \| "deny" \| "ask" \| "ask_human" \| "modify", reason = chr(1), input = named list, risk = <gptr_risk> \| NULL, rule = chr(1) \| NULL)`: every `policy` spec's `check(call, ctx)` (deny > ask_human > ask > modify > allow; a throwing policy denies; **no active `mode` policy = ask**, fail closed, unless the run's snapshot has `gptr.unsafe_no_permissions`); a `modify` is re-classified and re-checked once (a second modify denies); an `ask` goes to `permission_request` hooks (first decision; error = deny), then to `ui$permission()` when `gptr_can_prompt()` holds in the run's snapshot; an `ask_human` skips the hooks; without anyone to prompt: `gptr.noninteractive_ask = "stop"` stops the run with status `blocked` (the gateway raises `gptr_error_permission` with `action` and `how_to_allow`), `"deny"` returns a denial the model sees | P06, P20 (through the injected `opts$gate`, IC-33), P18 (server calls) |
| `tool_result_message(result, call)` | the `tool_result` message of §4.4 | P06, P20 (through the injected `opts$tool_result`, IC-33) |

Example calls:

```r
s = session_new("fake/fake-1", "manual", home = globalenv())
session_run(s, msg_user("hello"), list(max_turns = 5L))
run = run_start(s, msg_user("and more"), list())
run_wait(list(run), timeout = 30)
d = perm_check(list(id = "c1", name = "r", input = list(code = "unlink('x')"), nested = FALSE), run)
session_enqueue(s, "use TPM", as = "steer", source = "pipe")
```

### 7.7 P07 Prompt, context, caching and compaction

| Function | File | Contract | Consumers |
|---|---|---|---|
| `prompt_freeze(s, opts = list())` | `prompt-sections.R` | computes and stores `.d$frozen` once per session: the preset's direct tools (`preset_tools()`), the tool array serialised once (Anthropic shape; adapters convert), `session_start` collect results, the `prompt_section` specs rendered in `order` into T0 and T1 (T0 ends after `context`), budgets enforced (a section over its budget is truncated at a line boundary with a diagnostic); appends `gptr.frozen`; returns the frozen list invisibly | P06 (through the §7.0 services) |
| `preset_tools(preset, human, model = NULL, modifiers = character(), mode = NULL)` | `prompt-sections.R` | chr of direct tool names from the registered `preset` record (IC-69): `minimal` = `read`, `r`, `edit`, `write`; `standard` = minimal + `ask` when `human`, or when `mode` is `manual` without a human (NS-12, IC-68); `readonly` = `read`, `r` (+ `ask`); `extended` = standard + `grep`, `find`, `ls`; then `+name`/`-name` modifiers and per-model `tools.presets` settings (shipped defaults for Gemini 3 and Haiku 4.5, IC-73); any spec with an `execute` may be named (IC-37) | P07, P11 (P06 and P19 only through `prompt.freeze`, IC-34) |
| `session_add_tools(s, specs)` (service `session.add_tools`) | `prompt-sections.R` | registers `specs` at rank 0 for `s`; an operator `tool_change` message with their declarations when the adapter declares `tool_addition`, else they become `r` members announced in an operator note; the frozen array never changes (IC-69) | P06 (`ctx$add_tools()`), P08 (continuations with `tools =`, `plugins =`, `extensions =`) |
| `prompt_texts()` | `prompt-text.R` | named list of the verbatim section and mode-block texts of §9.3 | P07, P11 (plan mode block), P24 |
| `context_first_message(s, input)` | `prompt-context.R` | the blocks of the first user message in the §7.4 order of `03`: every `context_block` spec with `placement = "first"` or `"both"` in `order` (so `<attached>` is in the first message, IC-38), each `provide(ctx, budget)` called with `ctx$input` = `list(call, turn = 1L, prompt, placement = "first")`, truncated to its budget; `NULL` results omitted; the project block gets `anchor = TRUE` | P06 (through the §7.0 services) |
| `context_turn_blocks(s, input)` | `prompt-context.R` | the leading blocks of a later user message (`placement = "turn"` or `"both"` specs: `workspace_changes`, `attached`, mode changes, skill activations); only non-empty blocks; a block whose text hash equals the last one emitted under the same name in this session is skipped (IC-38) | P06 (through the §7.0 services) |
| `request_build(s, target, extra = NULL)` | `prompt-cache.R` | `list(context, view, tokens_est, components)`: `context` is the adapter context of §8.1 for `target` (a model record): `system`, `tools_json`, `tools`, `messages` (`project_messages()` + the `extra` tail, e.g. the compaction request), `cache_plan` (the `cache_policy` spec's plan for the api), `params`, ids; `view` is the element summary for the prefix guard; `tokens_est` and `components` feed the budget check and the ledger | P06 (through the §7.0 services) |
| `prefix_guard(s, target, view)` | `prompt-cache.R` | compares with the previous request to the same (provider, model); on a break emits `cache_break`, appends `gptr.cache_break` and acts per `gptr.check_prefix`; resets on `session_tree` | P06 (through the §7.0 services) |
| `compact_threshold(window, max_output, r_cap = 4000)` | `prompt-compact.R` | `min(window - min(max(30000, 0.10 * window), 0.25 * window), window - max(16384, max_output + 2 * r_cap), gptr.compact_at)` | P07 (behind `compact.should`) |
| `compact_should(s, tokens, idle_s)` | `prompt-compact.R` | `lgl(1)`: threshold or cold rule (the `compact.should` service) | P06 (through the service) |
| `extract_state(entries)` | `prompt-compact.R` | harness state for the checkpoint (user messages incl. steering, objects with creating code, decisions, files, skills, plan) | P07, P16 |
| `builtin_prompt(gptr)`, `builtin_context(gptr)`, `builtin_compaction(gptr)` | | register P07's sections (`preamble`, `tools`, the closing lines of `rules`, the core of `r_session`, `r_performance`, `modes`, `context`, `addendum`; IC-68), the four `preset` records, the gap `cache_policy`, the default `estimator`, the context blocks `project_instructions` (rendered `trusted="false"` in an untrusted project, IC-52), `environment`, `mode`, `plan`, and the checkpoint `compactor` (with the post-compaction floor check, IC-71) | P02 load |

Example calls:

```r
frozen = prompt_freeze(s)
blocks = context_first_message(s, list(call = call, turn = 1L, prompt = "hi"))
req = request_build(s, model_resolve("sonnet"))
compact_threshold(200000, max_output = 64000)
```

### 7.8 P08 Gateway and SDK

**The `gptr_call` record** (IC-13), created by `call_new()` in `gptr-capture.R`: an environment of class
`gptr_call` with bindings

| Binding | Type | Meaning |
|---|---|---|
| `id` | chr(1) | `c` + 8 hex |
| `prompt`, `template` | chr(1)\|NULL | interpolated prompt; the literal template (`NULL` for non-literal prompts: then `template = prompt`) |
| `session` | `<session>`\|NULL | the continuation target |
| `context` | list | one `list(label, kind = "symbol" \| "value" \| "literal", name = chr(1) \| NULL, slot = chr(1) \| NULL, facts = list(class, dim, length, bytes, is_chr1))` per context dot; symbols are read by name from `envir` in leaves; `value` items live in `values` |
| `values` | env | call values bound as `.v1`, `.v2`, ...; removed with `rm()` by `call_release()` |
| `envir` | env binding | the caller frame or explicit `envir`; set to `NULL` by `call_release()` [R2] |
| `ids` | named list | resolved `model` (chr or registered spec name), `mode`, `skills`, `plugins`, `extensions`, `tools`, `agents` (list of `<spec:agent>`) |
| `args` | named list | `parallel`, `choices`, `levels`, `threshold`, `min_confidence`, `uncertain`, `background`, `budget`, `replay`, `opts` (validated `.opts`), `run` (`.run`), `stdin` (`.stdin`) |
| `sys_call` | call | `sys.call()` of the `peter()` frame (with its srcref) for document location |
| `nframe` | int(1) | `sys.nframe()` of the `peter()` frame |
| `top_level` | lgl(1)\|NA | set by P15's locator (`NA` until then) |
| `doc` | list\|NULL | document site set by the `document` route |

Functions (P08):

| Function | Contract | Consumers |
|---|---|---|
| `call_new(...)` | builds the record (capture rules [R3]) | P08 |
| `call_release(call)` | `rm()` of `values`, `envir = NULL`; called on every exit path of `peter()` (`on.exit` in a frame that holds no dots) | P08, route owners that keep a call beyond the gateway frame (none may) |
| `call_value(call, i)` [leaf] | the value of context item `i` (by name from `envir` for symbols, from `values` otherwise) | P09 (`attached` block), P13 (states), P19 (fan-out elements) |
| `route_pass()` | the sentinel a route's `run()` returns to continue routing | P13, P14, P15, P19 |
| `gateway_defer(expr_fun)` | evaluates `expr_fun()` with deferral on: every `peter()` call made meanwhile behaves as `.run = FALSE` and returns its unstarted session | P19 (`gptr_parallel()` forces its `...` promises inside it) |
| `gateway_run(call, s = NULL)` | the default System 2 runner used by the `continue`/`new` routes and by other routes: creates the session when `s` is `NULL` (`session_new()` with the resolved model, mode and home; a router model is stored as `router:<name>`, IC-69), chooses the evaluation environment by the IC-40 precedence and checks that context symbols are visible there, applies model/mode changes and `session_add_tools()` for `tools =`/`plugins =`/`extensions =` on a continuation, tightens the mode to the running one when `run_current()` is non-NULL (IC-53), runs `egress_check()`, calls `replay_guard()`, builds the input (first message or turn blocks, the prompt, `skills =` preloads, the pending plan once), then `session_run()`/`run_start()`/queue per `.run` and `background`; writes nothing to documents itself | P13 (escalation), P14, P15, P19 |
| `dot_facts(x)` [leaf] | `list(class, is_session, is_chr1, length, dim, bytes, text)` (`text` = a `paste0()` copy of character values up to 64 KiB, else `NULL`) | P08 |
| `resolve_identifier(expr, arg, envir)` (service `identifier.resolve`) | §6.1.3; returns chr or a spec | P08, P17 (`agents` mask); P02 stores raw expressions and never calls it (IC-34) |
| `identifier_known(name, arg)` | `lgl(1)`: catalog aliases, registered provider/model/router ids, modes, presets, skill/plugin/extension/agent names (by `arg`) | P08 |
| `interpolate_prompt(template, envir)` [leaf per value] | §6.1.4 | P08, P14 (console echo) |
| `settings_get(key, session = NULL)` | the effective value through the layers of §11.2 | all |
| `settings_effective()` | the `gptr_config` of §5.11 | P08, P14 |
| `settings_write(scope, patch)` | merges a named list at top level into the scope's file (atomic) or the process layer | P08, P11, P14, P15 |
| `trust_get(path = getwd())` | `lgl(1)`: `TRUE` only when recorded and the trust fingerprint still matches (IC-52); L0 and L3 callers use the `trust.get` service (IC-33) | P08; P03, P07, P15, P17, P18 through `trust.get` |
| `home_address(envir)` | chr(1) `rlang::obj_address(envir)` for the pending-plan key (an address string, never a reference) [R2] | P11 |
| `replay_mode(arg = NULL)` | `chr(1)`: `arg` > `gptr.replay` > `GPTR_REPLAY` > settings > `"auto"`; `"replay"` is forced when `check_running()` and `Sys.getenv("TESTTHAT") != "true"` (examples), unless `arg` is given (IC-45) | P08, P13, P15, P19 |
| `replay_guard(model, what = "model call")` | in replay mode, signals `gptr_error_not_recorded` before any request to a provider whose record is not `offline = TRUE` (`offline` = no remote model is called: the fake provider and the mock-server and fake-CLI test providers, so tests and examples still run); `invisible(TRUE)` otherwise | P08 (`gateway_run()`), P13 (cache misses), P19 (team and fan-out children) |
| `egress_check(provider_id)` | `invisible(TRUE)` if acknowledged (user settings `egress`), local or offline, or `.opts$context = "none"`; when `gptr_can_prompt()`: shows what automatic context is sent and records the acknowledgement at user scope (an `ask_human`, IC-53); otherwise `gptr_error_egress` | P08 (`gateway_run()`), P13, P19 |


Example calls:

```r
resolve_identifier(quote(opus), "model", globalenv())            # "opus" (a known alias)
interpolate_prompt("Cluster {cl} has markers {top}", envir)       # values of cl and top
replay_mode(NULL)
replay_guard(model_resolve("sonnet"))
v = call_value(call, 1L)
```

### 7.9 P09 Evaluator and workspace

| Function | File | Contract | Consumers |
|---|---|---|---|
| `eval_r(code, envir, timeout = NULL, plots = c("auto", "capture", "none"), tee = gptr_has_human(), budget_tokens = gptr_opt("r_output_tokens"), guard = TRUE, rng = NULL, record = TRUE, max_images = gptr_opt("r_max_images"))` | `eval-core.R` | the built-in `evaluator` record `r` (IC-69); parses with `srcfilecopy("<gptr>", code)`; `eval_guard()`; evaluates top-level expressions one by one in `envir` with sink capture (cleaned up in `suspendInterrupts()`), calling handlers created in a frame that does not hold `envir` [R2][R3], per-expression `setTimeLimit(elapsed = timeout, transient = TRUE)` (`timeout = NULL`: none with a human present, else `gptr.r_timeout`), symbols printed with `print(<sym>)` in `envir` and every `withVisible()` result cleared in place (`res[1L] = list(NULL)`) before the frame returns [R8, IC-67], plots captured (on `pdf(NULL)` with the display list enabled when no device is open and no human sees one; the prior device restored) and replayed to PNG, at most `max_images` attached (the rest kept in the session's out store), interruptions recorded with `on.exit()`, the agent's L'Ecuyer state swapped in and out by `rng_swap()` (IC-61); stops at the first error; returns a `gptr_eval_result` (§5.8); never keeps the value | P10 (`r`), P14 (`!expr`), P18 (server `r`) |
| `rng_swap(state, expr)` [leaf] | `eval-core.R` | saves `.Random.seed` of the global environment (or its absence), assigns the agent's `c(10407L, <6 seeds>)`, evaluates, stores the advanced vector back in `state`, restores or removes the user's; with `with_seed_preserved()` the only code that assigns `.Random.seed` (IC-61) | P09, P19 |
| `format_eval_result(res, budget_tokens)` | `eval-format.R` | `list(text = chr(1), images = list, truncated = lgl(1), out_id, spill)`: output, messages, warnings, error + trimmed traceback, `[plot N attached]`, state-change lines (`~ pbmc <Seurat> modified`, `+ markers <data.frame 4,211 x 7>`), a status line, head 40% / tail 60% truncation with the `peter$out(<id>)` notice; halves the budget when the session's context exceeds half the compaction threshold | P10 |
| `eval_guard(exprs)` | `eval-guard.R` | `list(blocked = chr, reason = chr(1) \| NULL)` for `q`, `quit`, `readline`, `menu`, `browser`, ... [12 §3.6]; the symbols `q` and `quit` are flagged in any position (a value, a `FUN` argument, `match.fun`, `get`, `do.call`, `base::`; IC-67); a literal `[secret:` marker is blocked with the `Sys.getenv()` hint | P09, P18 |
| `gptr_shim(exprs, envir)` | `eval-guard.R` | rewrites calls headed by `peter`, `gptr_return` to `gptr::` when the symbol `peter` is not visible from `envir`, without binding anything; the recorded code keeps the original text | P09 |
| `plot_png(recorded, width = gptr.plot_width, height = gptr.plot_height, res = gptr.plot_res)` | `eval-plots.R` | an image block (ragg when installed, else `grDevices::png()`) | P09, P10 (`peter$plot()`) |
| `env_snapshot(envir, previous = NULL)` [R4] | `env-snapshot.R` | df `name`, `kind` (`value`, `promise`, `active`), `address`, `class`, `bytes` (address-keyed `object.size()` cache; `NA` for environments, functions, external pointers), `shape`, `fp` (`fingerprint()`); never forces promises or calls active bindings; `.Random.seed` and `.Last.value` excluded | P09, P16 |
| `env_diff(old, new, assigned = character())` | `env-snapshot.R` | `list(added, modified, removed)` (chr each): address, kind or fingerprint changed, or a static assignment target | P09, P16 |
| `workspace_lines(snapshot, budget = 600L)` | `env-snapshot.R` | chr: at most 12 lines `name  class  shape  size`, largest first, then `(+ n smaller objects: use ls())` | P09 (block), P14 (banner) |
| `changes_lines(diff, snapshot, user_ran, budget = 300L)` | `env-snapshot.R` | chr lines `+ name class shape size`, `~ name`, `- name`, `user ran: <expr>` | P09, P16 |
| `describe_binding(name, envir, budget = 150L)` [R4] | `env-describe.R` | `gptr_describe()` of a binding looked up in a leaf, never forcing promises (`<promise>`/`<active>`), errors caught (default method) | P09, P14 (`@object`), P13 (state labels) |
| `user_expr_log(since = NULL, n = 20L)` | `env-history.R` | chr of top-level expressions the user evaluated since `since` (task callback registered while a session with a kept home is live), deparsed and cut to 120 characters | P09 |
| `r_env_probe()` | `env-probe.R` | chr(1) body of `<r_env>` (installed fast packages by category, installed-but-not-loadable, missing recommended), computed without loading namespaces, cached per process | P09 |
| `builtin_workspace(gptr)` | `env-snapshot.R` | registers context blocks `workspace` (`first`, order 500), `workspace_changes` (`turn`, order 100), `attached` (`both`, order 600), `skill_content` preloads (`both`, order 700) (IC-38), the prompt section `r_env` (T1, order 900), the `evaluator` record `r` and the `describe` and `eval.r` services | P02 load |

Example calls:

```r
e = new.env()
res = eval_r("fit = lm(mpg ~ wt, data = mtcars); coef(fit)", envir = e)
out = format_eval_result(res, 4000L)
snap = env_snapshot(e)
env_diff(env_snapshot(new.env()), snap)
workspace_lines(snap)
describe_binding("fit", e, budget = 80L)
```

### 7.10 P10 Tools and the `peter$` namespace

| Function | File | Contract | Consumers |
|---|---|---|---|
| `ns_resolve(path)` (service `ns.resolve`), `ns_names(pattern)` (service `ns.names`) | `tool-namespace.R` | resolves `peter$<a>` / `peter$<a>$<b>...` to a member closure or a `gptr_ns` node from un-namespaced tool specs with a `fun` that are not `hidden` (IC-37) and namespace providers (MCP: P18 calls `ns_register_provider("mcp", ...)`); lists names for completion; no I/O | P08 (the gateway methods) |
| `ns_register_provider(name, fun)` | `tool-namespace.R` | registers a namespace node provider (`fun(path)` -> member or node): `mcp` (P18), plugin namespaces (generic, from specs' `namespace`) | P18 |
| `member_closure(spec)` | `tool-namespace.R` | a `gptr_member` function: formals from the schema (required properties first, optional ones default `NULL`), body that validates, calls `dispatch_nested()` when a run is executing on the stack and the spec's `fun`/`execute` directly otherwise (user calls are the user's actions) | P10, P18 |
| `ns_catalog(session, kinds = c("plugin"), budget = 1500L)` | `tool-namespace.R` | chr(1) body of the `plugins` section: one `peter$<ns>$<name>(<sig>)  # <first sentence>` line per plugin member, least-recently-used descriptions trimmed first | P10 (its `plugins` section) |
| `bm25_index(docs)`, `bm25_search(index, words, limit = 8L)` | `tool-namespace.R` | the search behind `peter$search()`; `docs` = df(`id`, `text`) | P10, P18 |
| `read_file(path, offset = NULL, limit = NULL, budget_tokens = gptr.read_max_tokens)` | `tool-read.R` | `list(text = chr(1), image = <block> \| NULL, details = list)` (Pi read semantics [01 §3.2], line numbers off, images by magic bytes, encodings, 16 MiB raw index / streaming index / cached sparse index above 20 MB) | P10 |
| `write_file(path, content)` | `tool-write.R` | atomic; keeps the existing EOL, BOM and encoding of an existing file; creates parent directories; `list(bytes, created, details)` | P10, P23 |
| `edit_file(path, edits, replace_all = FALSE)` | `tool-edit.R` | Pi's multi-edit semantics (each `oldText` matched against the original, unique, non-overlapping), fuzzy fallback (whitespace, quotes, NFKC with stringi), a pasted `*** Begin Patch` envelope applied through `patch_apply()`; `list(message, diff = chr, fuzzy = lgl(1), details)`; the result text carries the diff (at most 400 tokens) only when something deviated from the literal request | P10, P15 (document edits routed back after block bookkeeping) |
| `patch_apply(envelope, root = project_root())` | `tool-edit.R` | applies a Codex-style patch (`*** Add File`, `*** Update File`, `*** Delete File`, `@@` hunks); `list(files, message, details)` | P10 |
| `diff_lines(old, new, context = 3L, max_tokens = 400L)` | `tool-diff.R` | chr unified diff (prefix/suffix trim, patience anchors, Myers capped at D = 256) | P10, P15, P16 |
| `walk_files(root = ".", type = c("file", "dir", "any"), gitignore = TRUE, hidden = FALSE, max = Inf, prune = NULL)` | `tool-walk.R` | df `path` (relative to `root`), `size`, `mtime`, `type`; pruned walker (skips `.git`, `node_modules`, `renv`, `.venv`, `__pycache__`), gitignore engine | P10, P16 |
| `glob_to_regex(glob)` | `tool-walk.R` | PCRE with Pi's `**/` prefix rule [11 verifier] | P10, P11 (rule globs), P18 (tool exposure globs) |
| `search_grep(pattern, path, glob, ignore_case, fixed, context, limit, output)`, `search_find(pattern, path, sort, type, limit)`, `search_ls(path, sort, long)` | `tool-search.R` | the functions behind `peter$grep()`, `peter$find()`, `peter$ls()` (§9.4); results are `gptr_matches`/`gptr_files` | P10 |
| `builtin_tools(gptr)`, `builtin_r(gptr)` | `tool-namespace.R`, `tool-r.R` | register one spec per capability with both `execute` and `fun` for `read`, `edit`, `write`, `grep`, `find`, `ls` (IC-37), the `r` tool (its `parameters` a function of `ctx` giving the four schema variants, IC-68), the other members of §9.4 owned by P10 (including `out`, IC-36), their `guidelines` for `<rules>`, the `r_session` fragments for helpers and `out`, the `plugins` section, the `search_source` record for members, and the services `ns.resolve`, `ns.names`, `search.sources` | P02 load |

Example calls:

```r
grep_fn = ns_resolve("grep")
grep_fn("TODO", path = "R")
m = search_grep("TODO", path = "R", glob = "*.R", ignore_case = FALSE, fixed = TRUE, context = 0L,
                limit = 20L, output = "content")
ed = edit_file("R/a.R", list(list(oldText = "x = 1", newText = "x = 2")))
diff_lines(c("a", "b"), c("a", "c"))
```

### 7.11 P11 Permissions, UI and plan mode

| Function | File | Contract | Consumers |
|---|---|---|---|
| `gptr_risk()` (service `risk.classify`) | `perm-classify.R` | §6.6; `kind = "command"` uses `inst/extdata/risk-commands.csv` (G5 levels), `"sql"` and `"python"` keyword classifiers; tables are data (`risk_table(kind)`) extendable by plugins through `setting` specs | P10 (through the service), P22, P23 |
| `code_targets(code)` | `perm-classify.R` | the one parse walk shared by the classifier and the checkpointer [G7 §3.4]: `list(assign, modify, byref, remove, super, files, unknown, process, calls = df(fn, package, line))` (chr each, never evaluating) | P11, P16 |
| `rule_parse(rule)` | `perm-rules.R` | `list(tool, kind = "any" \| "glob" \| "level" \| "fn" \| "category" \| "sh" \| "sql" \| "secret", value)` or `gptr_error_invalid_argument` | P11, P14 (`/permissions`) |
| `rule_match(rules, call)` | `perm-rules.R` | `list(deny = chr, ask = chr, allow = chr)`: matched rules; allow `r(fn:..)`/`r(category:..)` match only if **every** flagged call (level >= 1) is covered; deny/ask match if **any** is | P11 |
| `rule_suggest(call)` | `perm-rules.R` | chr(1) rule covering exactly the flagged calls (`r(fn:FindNeighbors,FindClusters)`), or `NULL` (never for level 4) | P11, P14 |
| `builtin_permissions(gptr)` | `perm-gate.R` | registers the policies `mode` (the mode x level table of §6.8.1 of `03`), `rules`, `critical_guard`, `secret_guard`, `protect_size` (IC-04) | P02 load |
| `builtin_plan(gptr)` | `perm-plan.R` | registers the `plan` policy (writes denied, level-1 R allowed only because the run evaluates in the scratch overlay), the plan-mode `agent_end` hook (captures the last `<proposed_plan>...</proposed_plan>`, saves `<root>/plans/<YYYY-MM-DD>-<slug>.md`, sets `.d$plan`, stores the pending plan under `home_address(home)` with the time, appends `gptr.plan`, offers the execute menu interactively), the plan-mode allowlist check (only calls known to be read-only run, IC-54), and the `plan.pending` service (returns the plan once, only to the next top-level `peter()` call of the same process and environment within one hour; any other call in between discards it; IC-56) | P02 load |
| `builtin_ui(gptr)` | `console-ui.R` | registers `ui` specs `console`, `none`, `scripted`, `rstudio` and the `ui.get` service (resolution from the run's snapshot of `gptr.ui`, else `console` when `gptr_can_prompt()`, else `none`, IC-43, IC-53); every display escapes control, bidi and zero-width characters and the one-line prompt lists every flagged call and `+N more lines` (IC-53) | P02 load |
| `builtin_ask(gptr)` | `tool-ask.R` | registers the `ask` direct tool (schema §9.2) with `available = function(ctx) ctx$has_ui()`; result text as 18 §3.6 (`The user answered:` lines; cancellation and non-interactive texts) | P02 load |

Console `select()` deliberately preserves title line feeds for setup and `ask` questions.
Choice labels and details escape line feeds, and all other control/bidi/zero-width escaping is
retained. Permission approval displays keep the separate IC-53 escaping rules.

**Permission request record** (argument of `ui$permission()` and payload of `permission_request`):
`list(tool = chr(1), input = named list, summary = chr (the lines to show: code preview, paths), risk =
<gptr_risk> | NULL, reason = chr(1), suggested_rule = chr(1) | NULL, undo_note = chr(1) | NULL (from the
`checkpoint.note` service), session = chr(1), turn = int(1), nested = lgl(1), tier = "ask" | "ask_human")`
(IC-53).

Example calls:

```r
rk = gptr_risk("saveRDS(x, 'out.rds')", envir = e)
rule_parse("r(fn:write.csv,saveRDS)")
rule_suggest(list(name = "r", risk = rk))
ext_service_get("plan.pending")(home_address(globalenv()))
```

### 7.12 P12 Native provider adapters

Each file registers one adapter through its `builtin_<name>()` factory (`builtin_anthropic`, `builtin_openai`,
`builtin_openai_compat`, `builtin_google`), following §8.1. Cross-plan functions:

| Function | File | Contract | Consumers |
|---|---|---|---|
| `anthropic_normaliser(model, opts)` | `provider-anthropic.R` | the Anthropic SSE normaliser (`push(ev)`, `finish()`, `fail(cnd)`, `message()`), accepting either SSE events or already-parsed stream-event objects (`push_parsed(obj)`) | P20 (`cli-claude` reuses it for `stream_event` lines) |
| `check_adapter(adapter, fixtures = NULL)` (service `check.adapter`) | `provider-anthropic.R` | replays `fixtures/sse/<api>/*.sse` (or `fixtures`) through the adapter with random chunkings and compares with `<case>.events.json` / `<case>.message.json`; returns `gptr_check` rows | P02 (`gptr_check()`), P24 |
| `compat_flags(provider, model)` | `provider-openai-completions.R` | the compat record of 09 §3 (field names, `max_tokens` vs `max_completion_tokens`, `reasoning_content` replay, tool-id length, image modes) | P12 |

Example calls:

```r
n = anthropic_normaliser(model_resolve("sonnet"), list(emit = function(ev) NULL))
n$push(list(event = "message_start", data = "{\"type\":\"message_start\",\"message\":{}}"))
msg = n$finish()
check_adapter(adapter_get("anthropic-messages"))
```

### 7.13 P13 System 1

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_system1(gptr)` | `s1-client.R` | registers the provider `typesafe` (base URL `https://api.typesafe.ai/v1/`, key `TYPESAFE_API_KEY`, model alias `jev` -> `jev-latest`, `type = "classifier"`, `rate = list(requests_per_s = 40, tokens_per_s = 1e5)`, IC-64), gateway records of 04 §4, the adapter `typesafe-system-one` (`transport = "http_json"`, `classify`), the adapter `s1-emulate`, the route `classifier` (order 10), the `system1` prompt section (IC-68) and the service `s1.decide`; P13 also owns the example router `inst/gptr/examples/jev-router.R` (IC-69) | P02 load |
| `s1_call(call)` | `s1-route.R` | the `classifier` route's `run()`: states by the batch rule, question type (`choices` -> choice, `levels` -> score, else `noul`), cache lookup, requests for misses, thresholds, abstention, result vector; appends `gptr.decision` to a piped session; emits `decision`; a top-level call writes its one-line block through the `doc.s1_block` service when P15 is loaded | P08 (route) |
| `as_state(x, label)` | `s1-route.R` | internal S3 generic: `default` (atomic -> its value as text for small character/numeric values, else the `describe_binding()` text), `gptr_session` (the last answer, at most `gptr.s1_state_max` characters, plus value facts), `data.frame` (a row record) | P13 |
| `s1_states(values, label, labels = NULL)` | `s1-route.R` | the batch rule of §4.1.5 of `03` -> list of named states | P13 |
| `s1_request(model, states, questions, opts)` | `s1-client.R` | deduplicates states, sends at most `gptr.s1_max_active` concurrent reactor requests, `gptr.s1_rounds` bounded rounds resubmitting only failures (408, 429, 5xx, network; `retry-after` capped at 60 s), parses answers by name (probabilities re-keyed by option name); returns `list(answers = list per state, usage, model_version, request_ids, errors = df)` | P13 |
| `s1_cache_get(key)`, `s1_cache_put(key, record)` | `s1-cache.R` | memory (`the$s1_cache`) before a workspace exists, then `<root>/cache/s1/<2hex>/<sha256>.json` (§11.9) | P13 |
| `s1_emulate(model, states, questions)` | `s1-emulate.R` | answers through a System 2 model's structured output (one request per state), `meta$calibrated = FALSE`; used only with `gptr_config(system1 = "emulate:<ref>")` | P13 |

Example calls:

```r
states = s1_states(c(a = "A puppy.", b = "A car."), label = "text")
q = list(is_dog = list(type = "noul", instructions = "Does `text` describe a dog?",
                       criteria = list(true = "It does", false = "It does not")))
res = s1_request(model_resolve("jev"), states, q, list())
```

### 7.14 P14 Console and front ends

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_console(gptr)` | `console-repl.R` | registers the `frontend` `console`, the route `console` (order 30), the renderer hooks (process-wide notify hooks on `message_update`, `message_end`, `tool_execution_start`, `tool_execution_end`, `agent_end` that render only for the foreground session when `verbosity() >= 2`, a hook on `artifact_start` printing `artifact  <id>  ->  <url>   (running in background)` (NS-8), tool `render` functions and `renderer` records, IC-69, IC-71), the service `console.interrupt_policy`, and the command specs of §6.17 of `03` | P02 load |
| `console_run(s, envir, stdin = FALSE)` | `console-repl.R` | the REPL of 18 §4.3 on `s`; first-use setup per §6.1.1 before its banner/input; returns the session invisibly on `/exit`, or `NULL` when setup returns before starting it | P08 (route) |
| `with_interrupt_policy(expr_fun, runs, mode = c("call", "repl"))` (service) | `console-interrupt.R` | `tryCatch(withCallingHandlers(expr_fun(), interrupt = <pause menu>), interrupt = <abort>)`; the menu (`[s]teer`, `[f]ollow-up`, `[c]ontinue`, `[a]bort`, `[b]ackground` for foreground calls when P21 is loaded) writes to stderr and resumes through the `resume` restart; a second Ctrl-C aborts; `mode = "call"` re-signals the interrupt after an abort; abort-only where the restart is unverified (Rgui, IDE consoles) | P06, P08 |
| `render_markdown_stream(width = cli::console_width())` | `console-render.R` | environment with `write(delta)`, `finish()`, `reset_line()`; chunk-invariant; untrusted text never used as a format string | P14 |
| `builtin_jsonl(gptr)`, `jsonl_sink(session, con)` | `console-jsonl.R` | the `frontend` `jsonl`: subscribes to the session's events and writes one redacted JSON object per line in the §4.5 JSON form (event names verbatim) | P19 (worker children), P24 |

Example calls:

```r
console_run(NULL, envir = globalenv(), stdin = TRUE)
policy = ext_service_get("console.interrupt_policy")
policy(function() session_run(s, msg_user("go"), list()), list(), mode = "call")
```

### 7.15 P15 Documents and replay

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_documents(gptr)` | `doc-formats.R` | registers `doc_format` specs `r`, `rmd`, `qmd`, `ipynb`, `transcript`; the route `document` (order 50); the `documents` prompt section (IC-68); an `agent_end` hook that renders and writes the block when `run$opts$doc` is set; a `session_tree` hook that makes undone blocks inert; the services `doc.site`, `doc.edit`, `doc.s1_block` and `doc.replay` (owned by `builtin:documents`, so filtering it removes them, IC-34, IC-47) | P02 load |
| `doc_locate(call)` | `doc-locate.R` | a site `list(kind = "srcref" \| "source_frame" \| "knitr" \| "quarto" \| "jupyter" \| "rscript" \| "ide" \| "console", path, format, stmt = int(2) \| NULL, expr = call \| NULL, occurrence = int(1), ordinal = int(1), backend = chr(1), top_level = lgl(1), in_block = chr(1) \| NULL (the agent block whose body holds the statement, IC-47), ide_id = chr(1) \| NULL, defer = lgl(1))` using the precedence of §6.9.3 of `03`; `source()` frames are read inside `tryCatch` only when `gptr.doc_source_frames` is `TRUE`; paths compared with `path_key()` | P15 |
| `doc_decide(site, prompt_hash, args_hash, mode)` | `doc-replay.R` | `"replay"`, `"run"`, `"regenerate"`, `"skip"` (undone), or signals `not_recorded`/`stale_block` per the table of 14 §4.4.2 plus the undone row of G7 §3.8; a block is fresh only when both hashes match (IC-45); block-nested calls replay from S2 (IC-47) | P15 |
| `doc_block_lines(session, turn, site, call_ordinal)` | `doc-blocks.R` | chr lines of a block in the §11.5 grammar for the site's format (code of successful `record = TRUE` `r` calls from `details$code` minus top-level `gptr_return()` calls and calls of `record = FALSE` members, with top-level `<-` rewritten to `=` where safe; `#>` outputs from `details$outputs`; `## Decision:`, `## Steer:` and `## Follow-up:` lines; bridge digests; artifact paths; redacted with `code_for_history()` and `persist`; IC-48, IC-49); team and fan-out blocks per IC-47; plan-mode turns give one `## Plan:` line | P15 |
| `doc_upsert(site, block_lines, block_id = NULL)` | `doc-blocks.R` | checks write consent (IC-45; otherwise nothing is written), then idempotent insert/replace of the owned block through the site's backend, passing the `document_write` event (fail closed, patchable) first; md5 conflict check with re-locate and retry (3 times, then warning `doc_conflict`); deferred under Rscript through the sidecar of IC-51; never writes an open notebook (IC-50); returns `list(action, block_id, lines, backend)` and appends `gptr.doc_block`; caches child texts in S2 (IC-47) | P15, P16 |
| `prompt_hash(template)`, `args_hash(interp)` | `doc-blocks.R` | 12 hex of sha256 of the normalised template (trimws, CRLF -> LF, whitespace around newlines removed); 8 hex of sha256 of the sorted interpolated `name=value` pairs, `NULL` without interpolation (IC-45) | P15 |
| `s2_get(key)`, `s2_put(key, record)` | `doc-replay.R` | the S2 answer cache (§11.9) | P15 |

Example calls:

```r
site = doc_locate(call)
doc_decide(site, prompt_hash(call$template), replay_mode())
doc_upsert(site, doc_block_lines(s, 1L, site, 1L))
```

### 7.16 P16 Checkpoints and rewind

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_checkpoints(gptr)` | `ckpt-rewind.R` | registers `checkpointer` specs `objects`, `files`, `state`; command specs `/undo`, `/redo`, `/rewind`, `/checkpoints`; the service `checkpoint.note` | P02 load |
| `ckpt_predict(code)` | `ckpt-objects.R` | `list(assign, modify, byref, remove, super, files, unknown, process)` (chr each): P11's `code_targets()` reduced to what the object and file checkpointers need | P16 |
| `ckpt_store_put(path)` / `ckpt_store_get(hash, dest)` | `ckpt-files.R` | content-addressed blobs `<root>/checkpoints/blobs/<2hex>/<xxh128>[.gz]` | P16, P23 (artifact records) |

The `checkpointer` contract used by the dispatcher (P06) is §10.2.

Example calls:

```r
ckpt_predict("pbmc = FindClusters(pbmc, resolution = 0.8); unlink('tmp.csv')")
```

### 7.17 P17 Skills, templates, agent files and plugins

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_skills(gptr)`, `builtin_prompts(gptr)`, `builtin_agents(gptr)` | `skill-discover.R`, `skill-templates.R`, `subagent-defs.R` | register discovered `skill`, `prompt_template`, `agent` specs (declarative, rank by location), one `command` spec per template, the `skills` section (T1, order 820) and the services `skill.catalog`, `skill.body`, `agent_def.get`, `plugin.enable` | P02 load |
| `skill_discover(scope = "all")` | `skill-discover.R` | df of skills from the roots of 16 §4.8 (`.gptr/skills`, `.agents/skills`, `.claude/skills` of trusted projects; user directories under `user_home()`; attached packages' `inst/gptr/skills` and `inst/skills`; plugin `skills/`), bounded walk; untrusted project skills are listed but never catalogued (IC-52); names compared with `name_norm()` (IC-42) | P17 |
| `skill_parse(path)` | `skill-discover.R` | `<spec:skill>` from `SKILL.md` frontmatter (lenient yaml: `name`, `description` <= 1,024 characters, `disable-model-invocation`, `allowed-tools`; string keys keep their source text against YAML 1.1 coercion, IC-71) or `NULL` + diagnostic; the catalog shows `[skill:<name>/SKILL.md]` pseudo-paths that `read` resolves (IC-68) | P17 |
| `template_expand(text, args)` | `skill-templates.R` | Pi's template grammar (`$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `${@:N}`) [05 §3.7] | P17 (the `command` specs `builtin:prompts` registers for templates, so the console only dispatches commands) |
| `agent_file_parse(path)` | `subagent-defs.R` | `<spec:agent>` from a Claude-compatible `.md` agent file (frontmatter `name`, `description`, `model`, `tools`, `skills`, `backend`; body = system text); tool names mapped by `tool_name_map()` | P17, P19 |
| `tool_name_map(names)` | `subagent-defs.R` | chr: `Read` -> `read`, `Write` -> `write`, `Edit`/`MultiEdit` -> `edit`, `Bash`/`PowerShell` -> `r`, `Grep` -> `grep`, `Glob` -> `find`, `LS` -> `ls`, `Task`/`Agent` -> dropped (sub-agents are `peter()` calls), `mcp__<s>__<t>` kept | P17 |
| `plugin_resolve(name)` | `ext-plugins.R` | `list(kind = "package" \| "directory" \| "claude-plugin", name, path, manifest)` or `gptr_error_invalid_argument` | P17 |
| `plugin_enable(name, rank, session = NULL)` | `ext-plugins.R` | declarative resources registered now; code through `ext_load(lazy = TRUE)`; project plugin code only when `trust_get()`; returns `invisible(lgl(1))` | P17; P08 through the `plugin.enable` service |

Example calls:

```r
skill_discover("project")
template_expand("Review $1 for $ARGUMENTS", "analysis.R statistics")
agent_file_parse(".claude/agents/reviewer.md")
tool_name_map(c("Read", "Bash", "Glob"))
plugin_resolve("gptrpanel")
```

### 7.18 P18 MCP and OAuth

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_mcp(gptr)` | `mcp-namespace.R` | registers the `mcp` namespace provider, the `mcp` section (T1, order 840), per-tool `direct` tool specs at session freeze, `mcp_server` specs from configs, the services `mcp.catalog`, `mcp.dispatch_local`, `mcp.serve_ensure` | P02 load |
| `mcp_config_all(project = project_root())` | `mcp-config.R` | list of server specs (§11.7 shape) with `source`, `trusted`, `also_in` | P18 |
| `mcp_connect(spec)` | `mcp-client.R` | a `gptr_mcp_conn` (era probe with `gptr.mcp_probe_timeout`, cached per spec hash for 7 days; stdio through `proc_spawn()` with `child_env("mcp")` + the spec's expanded `env`, stderr read by gptr and appended redacted to `tempdir()/gptr/mcp-logs/` unless `gptr.mcp_debug`, IC-70; HTTP on the reactor with `followlocation = 0L`) | P18 |
| `mcp_tools(conn, refresh = FALSE)` | `mcp-client.R` | list of `list(name, title, description, input_schema, annotations)` (paginated; disk cache `R_user_dir("gptr", "cache")/mcp-tools/<hash>.json`) | P18 |
| `mcp_call(conn, tool, args, timeout = NULL, on_progress = NULL)` | `mcp-client.R` | `list(content, structured, is_error, text, images, elapsed)`; progress re-arms the idle timer; timeouts and interrupts send `notifications/cancelled`; MRTR at most 5 rounds (elicitation through `ui$questions()`, roots = the project directory, sampling refused) | P18 |
| `mcp_close(conn)` | `mcp-client.R` | stdin closed, 2 s grace, `kill_all()` | P18 |
| `mcp_dispatch_local(message, session)` (service) | `mcp-server.R` | answers one JSON-RPC message (both eras) with the session's `r`, `read`, `edit`, `write` through `dispatch_nested()`-equivalent gating, evaluating in the session's run evaluation environment with its mode and rules; the single gate for the claude route (IC-65); returns the response list | P20 (through `opts$mcp_dispatch`, IC-33) |
| `mcp_serve_token(session)` | `mcp-server.R` | issues a bearer token bound to `session` on the shared server and revokes it when the session's child exits (behind `mcp.serve_ensure`, IC-58) | P18 |
| `oauth_flow(issuer_or_provider, scopes, client)` | `auth-oauth.R` | PKCE S256, loopback (port from `port_candidates()`) or paste callback, locked refresh; refuses authorization-server metadata without `code_challenge_methods_supported` or without S256; validates `iss` (RFC 9207) when advertised with gptr's own callback reader; state and redirect checks (IC-71); tokens registered as secrets | P18 |

Example calls:

```r
conn = mcp_connect(spec)
tools = mcp_tools(conn)
res = mcp_call(conn, "echo", list(text = "x"), timeout = 10)
mcp_close(conn)
```

### 7.19 P19 Sub-agents

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_subagents(gptr)` | `subagent-backends.R` | registers `backend` specs `inline`, `worker`, `cli` (the `cli` backend's tests are P20's, IC-36), the routes `team` (order 15) and `fanout` (order 16) (IC-39), and the `r_session` fragment for sub-agents (IC-68) | P02 load |
| `subagent_backend(agent, model)` | `subagent-backends.R` | `chr(1)`: the `auto` rule (inline, except `cli` for CLI-only models; the agent's `backend` when given) | P19 |
| `subagent_start(spec, parent_run)` | `subagent-backends.R` | starts a child through the backend: `spec` = `list(agent = <spec:agent>, prompt, context (list of call items), model, mode, depth, export, objects, preset, rng_state, registry)`; returns a handle `list(session = <session>, fds = function() int, poll = function() NULL, cancel = function() NULL)`; enforces the limits of §6.13 of `03` (`max_tasks` only at depth >= 1, IC-39; pools capped at 2 under check, IC-60); budget charged to the root (IC-66) | P19 |
| `worker_main(spec_path, result_path)` | `subagent-worker.R` | runs inside a callr child (started with `supervise_default()`, `encoding = "UTF-8"` and `child_env_callr(child_env("worker"))`): reads the spec (`readRDS`), re-registers `spec$registry` (IC-69), runs `peter()` with the `jsonl` frontend on stdout and answers on stdin (§11.11), exits on stdin EOF, EPIPE or a dead parent pid (checked every 5 s, IC-60), saves exports with `save_rds()` | P19 (callr) |

Example calls:

```r
h = subagent_start(list(agent = gptr_agent(model = "fake/fake-1"), prompt = "Summarise", context = list(),
                        model = "fake/fake-1", mode = "manual", depth = 1L, export = character()),
                   parent_run = run)
subagent_backend(gptr_agent(model = "codex"), model_resolve("codex"))     # "cli"
```

### 7.20 P20 Subscription CLI providers

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_cli(gptr)` | `cli-common.R` | registers providers `claude-cli` (alias `claude_code`, `type = "cli"`) and `codex` (alias `codex`), adapters `cli-claude` and `cli-codex` (`transport = "process_jsonl"`), a `status` function per provider for `gptr_providers()` | P02 load |
| `pcli_find(cli = c("claude", "codex"))` | `cli-common.R` | path from `gptr.cli_path`, then PATH, then the per-OS known locations of IC-65; native binaries only for claude (the npm `claude.cmd` shim is refused with an install hint); `gptr_error_cli_missing` otherwise | P20 |
| `pcli_version(path)`, `pcli_probe(path)` | `cli-common.R` | `package_version` from `--version` and a capability probe of `--help` (cached per path and mtime; run only on first use or `check = TRUE`); below the minimum (`claude` >= 2.0.0), or a `-p` that defaults to `--bare` without a documented opt-out, signals `gptr_error_cli_version` | P20 (`status()` reads the cache only unless `gptr_providers(check = TRUE)`, IC-65) |
| `pcli_login_status(cli)` | `cli-common.R` | help-gated CLI login-status commands, closed stdin and 3 s timeout per subprocess; returns only `signed in`, `not signed in`, or `unknown`, never raw auth output; no model request | P05 when `check_login = TRUE` |

Example calls:

```r
path = pcli_find("claude")
pcli_version(path)
```

### 7.21 P21 Background sessions [experimental]

| Function | File | Contract | Consumers |
|---|---|---|---|
| `bg_register(s)` (service `bg.register`) | `agent-background.R` | requires later (`gptr_error_missing_package`); marks the run background, adds a `session` job, ensures the `later` pump (50 ms timer calling `reactor_pump(slice_ms = 0)`, a no-op while the reactor is on the stack, IC-57); R tools of background runs run at idle ticks (`gptr.background_tools = "idle"`) or wait for `gptr_wait()`; an ask moves the run to `waiting` and is shown at the next blocking gptr call; a tool that changed bindings at an idle tick prints one notice | P08, P14 (`[b]ackground`) |

Example calls:

```r
s = peter("long job", model = fake, .run = FALSE, envir = new.env())
ext_service_get("bg.register")(s)
```

### 7.22 P22 Polyglot bridges

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_bridges(gptr)` | `bridge-sh.R` | defines the `interpreter` kind (`kind` spec, IC-02), registers built-in interpreters (`.sh`, `.py`, `.R`, `.js`, `.pl`, `.rb`, `.jl`), the members `sh`, `script`, `bg`, `jobs` (§9.4; `out` is P10's, IC-36) and the `r_session` shell fragment (IC-68); emits `bridge_call` | P02 load |
| `builtin_lang(gptr)` | `bridge-lang.R` | registers the members `py`, `sql`, `knit` (shell engines routed through `peter$sh()`, IC-67) and the `r_session` languages fragment | P02 load |

Example calls (inside an `r` evaluation or at the console):

```r
st = peter$sh(c("git", "status", "--porcelain"))
st$ok
job = peter$bg(c("Rscript", "-e", "Sys.sleep(5)"), name = "sleeper")
job$wait(timeout = 10)
by_cyl = peter$sql("select cyl, avg(mpg) as mpg from mtcars group by cyl", name = mtcars)
```

### 7.23 P23 Artifacts

| Function | File | Contract | Consumers |
|---|---|---|---|
| `builtin_artifacts(gptr)` | `artifact-app.R` | registers `artifact_type` specs `shiny` and `html`, the member `app` (§9.4), the `artifacts` prompt section (IC-68) and the `artifacts` checkpointer | P02 load |
| `artifact_serve(dir, port_file, parent_pid, token)` | `artifact-app.R` | runs inside the callr child: picks a free 127.0.0.1 port from `port_candidates()`, publishes it by atomic rename of `port_file`, starts a parent-PID watchdog, runs the app behind the `gptr_token` check (IC-71); stdout/stderr are read by the parent and appended redacted to `app-vNNN.log` (IC-70) | P23 (callr) |


Example calls (inside an `r` evaluation):

```r
a = peter$app("marker-explorer", data = "markers", title = "Marker explorer")
a$url
gptr_artifacts("marker-explorer", stop = TRUE)
```

---

## 8. Provider adapters and the transport

### 8.1 Adapter contract (kind `adapter`, `gptr_adapter()`) [stable]

Providers are data (§10.2 kind `provider`); each binds by `api` to one adapter. `provider_stream()` (P05) is the
only caller of adapters for System 2 requests; `s1_request()` (P13) is the only caller of `classify`.

**Request context** passed to `build()`/`stream()` (built by `request_build()`, P07):

| Field | Type | Meaning |
|---|---|---|
| `system` | `list(t0 = chr(1), t1 = chr(1))` | the frozen system blocks |
| `tools_json` | `json` (json_verbatim) \| NULL | the frozen tool array in the Anthropic shape (§9.2); adapters convert it once per session and keep the conversion in `opts$memo` |
| `tools` | list of `<spec:tool>` | the same direct tools as specs (array order) |
| `messages` | list of `<msg>` | projected and handed off for this target (§7.5) |
| `cache_plan` | list(`anchors` = chr element ids (`"t0"`, `"project"`), `tail_ttl` = `"5m"` \| `"1h"`, `key` = chr(1) prompt-cache key) | from the `cache_policy` spec for the api |
| `params` | list(`max_tokens` int(1), `thinking` chr(1)\|NULL, `effort` chr(1)\|NULL, `tool_choice` `"auto"` \| `"none"` \| list, `returns` JSON Schema\|NULL, `temperature` num(1)\|NULL) | |
| `session_id`, `request_id` | chr(1) | |

**Options** passed to every adapter function (`opts`):

| Field | Meaning |
|---|---|
| `emit(ev)` | emit an INFRA-02 event (§4.5) |
| `retry(info)` | a normaliser calls this for a retryable failure seen *in the stream* (for example an overload `error` SSE event); `info = list(class, status, retry_after)`. The transport retries only if no delta was committed; otherwise it calls `fail()` |
| `signal` | environment with `aborted` (lgl) and `reason`; `inprocess` generators and `process_jsonl` adapters must check it |
| `credential` | a `gptr_secret` handle bound to the provider's origin, or `NULL`; adapters put it in `headers` as a handle, never as a value |
| `base_url` | chr(1): the provider's configured base URL |
| `state` | environment: per-session, per-provider live state (e.g. the claude child process); lives in the session's live record |
| `memo` | environment: per-session serialisation cache keyed `<entry id>\|<api>\|<same model>` |
| `send(obj)` | `process_jsonl` only: writes one JSON line to the child's stdin (`write_all()`) |
| `gate(call)`, `mcp_dispatch(message)`, `tool_result(result, call)` | injected by `provider_stream()` from the run: the run's `perm_check()`, the `mcp.dispatch_local` service bound to the session, and `tool_result_message()`; L1 adapters use only these, never L2+ functions (IC-33) |
| `run`, `session` | ids, for events and nested calls |
| `first_byte_timeout`, `idle_timeout`, `connect_timeout` | seconds |

**`build(model, context, opts)`** returns a request spec:

- `transport` `http_sse`, `http_ndjson`, `http_json`: `list(url = chr(1), method = "POST", headers = named list of chr(1) or handles, body = chr(1) (UTF-8 JSON text assembled by concatenation of memoised pieces) or raw, stream = "sse" | "ndjson" | "json")`. Only `http-request.R` materialises handles (`secret_value(handle, origin)`), and only when the URL's origin equals the handle's.
- `transport` `process_jsonl`: `list(start = list(command, args, env_profile, env = named chr, wd) | NULL (the process in `opts$state` is reused), send = list of objects to write as JSON lines for this turn, close_stdin = lgl(1))`.

**`parse(model, opts)`** returns a normaliser, a list of functions:

| Function | Contract |
|---|---|
| `push(ev)` | consume one decoded unit; `ev` is `list(event, data, id)` (SSE event; `data` UTF-8 text), `list(data)` (NDJSON line), `list(data, status, headers)` (whole JSON body, once) or `list(data, obj)` (process line, already parsed); emits events; returns `TRUE` when the stream is complete (terminal event emitted), `FALSE` otherwise. `process_jsonl` normalisers answer control requests from the child by calling `opts$send()` |
| `finish()` | end of input: emits the terminal event if not yet emitted (`done`, or `error` for a truncated stream) and returns the final assistant message |
| `fail(cnd)` | a transport failure (`cnd` is a classed, unsignalled `gptr_error_*`): emits `error` with the partial message and returns it |
| `message()` | the current partial assistant message (materialised lazily; never per delta) |

Normalisers never signal R conditions after `start`; every failure becomes exactly one terminal `error` event
carrying the partial message (INFRA-02). Opaque provider data (signatures, encrypted reasoning, `phase`, thought
signatures) is stored byte for byte (INFRA-07). Deltas accumulate in preallocated lists joined once.

**`stream(model, context, opts)`** (`transport = "inprocess"`, IC-16) returns a generator `function()` that
returns `NULL` when finished or `list(events = list(<ev>, ...), wait = num(1))`; the transport emits the events in
order and calls the generator again after `wait` seconds (default 0) through `reactor_task()`; each call returns
within 50 ms; the terminal event's `message` is the final message.

**`classify`** (classifier providers): `list(build = function(model, state, questions, opts) <http request spec>,
parse = function(model, status, headers, body, questions) list(answers = named list (canonical System One records; IC-74), usage =
list(input, output), model_version = chr(1)))`; for `inprocess` classifiers `list(run = function(model, state,
questions, opts) <parse result>)`. `parse` returns a classed, unsignalled `gptr_error_s1_*` object on failure.

**`capabilities`** (named list; missing entries mean `FALSE`/`NULL`): `images_in_results`, `tool_addition`,
`structured_output`, `reasoning_replay`, `parallel_tools`, `forced_tool_choice` (lgl; `FALSE` for Anthropic 5.x
models, IC-71); `request_params` (chr: non-prefix request fields a `request_params` handler may patch, IC-69); `operator_role` (`"system"`, `"developer"`,
`"user"`); `cache` (`"anthropic"`, `"openai"`, `"gemini"`, `"openrouter"`, `"none"`); `max_tool_name` (int);
`tool_shape` (`"anthropic"`, `"responses"`, `"chat"`, `"gemini"`).

Built-in adapters: `anthropic-messages`, `openai-responses`, `openai-completions`, `google-generative-ai` (P12),
`typesafe-system-one`, `ollama-system-one`, `s1-emulate` (P13; IC-74), `cli-claude`, `cli-codex` (P20), `fake`, `fake-classifier` (P01,
declared by P05).

### 8.2 Reactor API (P04, `http-reactor.R`) [internal]

```r
reactor_get()
reactor_now()
reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL,
             retry = NULL)
reactor_proc(proc, on_line, on_exit, run = NULL, stream = "stdout", on_stderr = NULL)
reactor_timer(at, fn, run = NULL)
reactor_task(fn, run = NULL)
reactor_enqueue_tool(run, fn)
reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)
reactor_cancel(ids)
reactor_run_add(run)
reactor_run_remove(run)
```

| Function | Contract |
|---|---|
| `reactor_get()` | the process reactor (`gptr_reactor`), created on first use: a curl multi pool (`multiplex = TRUE`, `host_con = 100`), the fd table, timers, tasks, the tool FIFO, admission state and strong references to active runs |
| `reactor_now()` | `num(1)` monotonic seconds (`proc.time()[["elapsed"]]`) |
| `reactor_http(...)` | queues one HTTP transfer (admitted while global `gptr.max_active` and per-provider limiter slots allow); `spec` from `build()`; every handle sets `pipewait = 0L`, `followlocation = 0L` (a 3xx is `gptr_error_redirect`, never retried, IC-64), `connecttimeout`, `low_speed_limit = 1`, `low_speed_time = idle + 30` as a backstop and no total timeout; the reactor enforces first-byte and idle timers (`gptr_error_timeout_first_byte`/`_idle`). Callbacks: `on_headers(status, headers)` once; `on_bytes(raw)` per chunk of a 2xx response; `on_done(status, headers)` at the end; `on_fail(cnd)` with a classed, unsignalled condition (non-2xx bodies are read fully, redacted and classified by `retry_classify()`). `retry` = `list(max_attempts = gptr.max_attempts, committed = function() lgl(1))`: when a failure is retryable and `committed()` is `FALSE`, the reactor waits (`retry_start`/`retry_end` events; interruptible timer, never a sleep inside a callback) and re-sends the same spec. Returns the transfer id |
| `reactor_proc(...)` | watches a processx child's pipes in `processx::poll()`; `on_line(line)` per complete line (UTF-8 decoded, `\r` stripped, at most 512 chunks per iteration, lines up to 16 MiB); `on_stderr(line)`; `on_exit(status)` once. Returns an id |
| `reactor_timer(at, fn)` | calls `fn()` once at `reactor_now() >= at`; returns an id |
| `reactor_task(fn)` | calls `fn()` once per iteration until it returns `FALSE` (used by `inprocess` adapters and the background pump) |
| `reactor_enqueue_tool(run, fn)` | appends `fn` (a zero-argument function executing one R-evaluating tool) to the FIFO; at most one runs per iteration, only for runs in `allow_runs` of the innermost pump |
| `reactor_pump(...)` | the only blocking wait in gptr; it tracks its depth (IC-57). One iteration: admit queued transfers; `processx::poll(c(processx::curl_fds(curl::multi_fdset(pool)), <pipes>), ms = min(next timer, slice_ms))`; `curl::multi_run(timeout = 0)`; read ready pipes and drain pending stdin buffers (IC-60); fire due timers; run tasks; `later::run_now(0)` only at depth 1, or at depth > 1 when `allow_runs` holds a CLI child served by the MCP server (whose handler then refuses requests of runs outside `allow_runs` with the retryable JSON-RPC error `-32002`); run at most one FIFO tool whose run is in `allow_runs`. `allow_runs` defaults to `NULL` (all runs) only when `run_current()` is `NULL`, else to `character()`; a nested pump (a sub-agent, System 1 or MCP call made inside an `r` evaluation) passes the ids it waits for. Loops until `until()` is `TRUE` (returns `TRUE`) or `timeout` seconds (returns `FALSE`). R interrupts propagate out of the pump to the caller's interrupt policy |
| `reactor_cancel(ids)` | `curl::multi_cancel()` for transfers, removal of timers/tasks/FIFO items; for process watchers: interrupt, grace, `kill_all()`; `invisible(<n cancelled>)` |
| `reactor_run_add(run)`, `reactor_run_remove(run)` | strong references to active runs (INFRA-15: the only run state the reactor holds) |

**Admission and rate limits** (`http-retry.R`): `ratelimit_update(provider, headers)` reads
`anthropic-ratelimit-*`, `x-ratelimit-*` and `retry-after*` into a per-provider token bucket that also holds the
provider record's static `rate` (IC-64; System 1 admission is process-wide); HTTP-date `retry-after` values go
through the locale-independent `parse_http_date()` (`month.abb`, UTC; unparsable -> backoff);
`ratelimit_admit(provider)` -> `lgl(1)`. **Retry classification**: `retry_classify(status, headers, body = NULL,
curl_error = NULL)` -> `list(retry = lgl(1), delay = num(1) | NULL, class = chr, retry_after = num(1) | NULL,
message = chr(1))`: retry 408, 409, 429, 5xx, 529 and network errors; `retry-after-ms`, then `retry-after`, capped
by `gptr.max_retry_delay` (above it: no retry, class `retry_after`); otherwise `0.5 * 2^i` seconds with
time-derived jitter, capped at 8; Anthropic's spend-cap 429 (`enforced_spend_limit_reached`) is never retried
(class `spend_cap`); 401/403 are `auth`.

**Wire log** (INFRA-28, `gptr.wire_log`; one file per session, each line open-append-close, IC-59, IC-65): one
redacted JSON line per request start and per terminal event
(`{"ts", "request_id", "provider", "model", "url" (origin + path), "status", "bytes", "seconds", "event"}`), never
headers or bodies.

### 8.3 Stream splitters (P04, `http-sse.R`)

| Function | Contract |
|---|---|
| `sse_splitter()` | environment with `push(raw)` -> list of events `list(event = chr(1) \| NULL, data = chr(1), id = chr(1) \| NULL, retry = num(1) \| NULL)` (fields per the SSE spec: LF, CRLF and lone CR line ends, a CR at the end of a chunk held until the next chunk, a leading BOM stripped, comment lines dropped, `data:` lines joined with `"\n"`, the **last** `event:` field wins; boundaries found with `grepRaw()` on raw bytes; the incomplete tail carried; each complete event decoded with `rawToChar()` and marked UTF-8; IC-64) and `flush()` -> the final unterminated event, if any |
| `ndjson_splitter()` | environment with `push(raw)` -> chr of complete lines and `flush()` |

Measured cost target: 20,000 deltas in under 1 s CPU; identical output under random re-chunking including splits
inside multi-byte characters and inside CRLF pairs, CR-only streams and duplicate `event:` fields (INFRA-23).

### 8.4 `provider_stream()` glue (P05)

```r
provider_stream(model, context, opts, emit, done, run = NULL)
```

1. `adapter = adapter_get(model$api)`; `provider = provider_get(model$provider)`;
   `opts$credential = provider_credential(provider)`; `opts$base_url` from the provider record (built-in or
   user-level config, or trusted project override confirmed once).
2. `http_*`: `spec = adapter$build(model, context, opts)`; a normaliser `n = adapter$parse(model, opts)`; bytes go
   through `sse_splitter()`/`ndjson_splitter()` into `n$push()`; `on_done` -> `n$finish()`; `on_fail` ->
   `n$fail(cnd)`; `retry$committed` is `TRUE` once `emit` saw a `*_delta` event.
3. `process_jsonl`: `build()`; start or reuse the child (`proc_spawn()` with `child_env(<profile>)`, recorded in
   `opts$state` and the job table); write `send` objects with `write_all()`; child lines -> `n$push()`.
4. `inprocess`: `gen = adapter$stream(model, context, opts)` pumped with `reactor_task()`.
5. Every event goes to `emit`; the terminal event's `message` goes to `done(msg)` exactly once. Returns the
   transfer/task id.

### 8.5 Provider records and plan routes

Provider records (kind `provider`, fields in §10.2) for the native and System 1 providers are the data of §8.1-8.2
of `03`. The two plan routes are `type = "cli"` providers whose adapters use `process_jsonl`:

- **`cli-claude`** (provider `claude-cli`, alias `claude_code`; experimental). `start$args` are exactly
  `-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --tools ""
  --strict-mcp-config --setting-sources "" --disable-slash-commands --mcp-config <file> --permission-prompt-tool
  stdio --permission-mode default --allowedTools mcp__gptr__* --system-prompt-file <file> --model <full id>`, plus
  `--max-turns <n> --max-budget-usd <x>` when a budget is in force (IC-65, IC-66) (never `--bare`; a CLI whose
  `-p` defaults to bare is handled by the probe of IC-65; the binary is native, never the `claude.cmd` shim); `<file>` for `--mcp-config` contains
  `{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}`; the system-prompt file holds the session's frozen T0 +
  T1; the child environment is `child_env("cli-claude")` (billing variables removed with a `billing_env` warning).
  Per turn `send` = one `{"type":"user","message":{"role":"user","content":<blocks>},"parent_tool_use_id":null,
  "session_id":""}` line. The normaliser handles `stream_event` lines with `anthropic_normaliser()` (P12),
  `control_request` lines by subtype: `mcp_message` -> `opts$mcp_dispatch(message)` (P18's
  `mcp_dispatch_local()`, the single gate for gptr's tools) answered as
  `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"mcp_response":…}}}`;
  `can_use_tool` (not sent for the pre-allowed `mcp__gptr__*` tools) -> `opts$gate(call)` answered
  `{"behavior":"allow","updatedInput":…}` or `{"behavior":"deny","message":…}`; unknown subtypes -> an error
  response. After `system/init`, an `apiKeySource` other than `"none"` aborts the turn with `gptr_error_billing`. `result` lines end the turn (usage
  from `usage` and `total_cost_usd` as an estimate, route `plan-cli`); `rate_limit_event` updates the provider's
  plan status. Interrupt: `{"type":"control_request","request_id":…,"request":{"subtype":"interrupt"}}`, then
  `kill_all()` after the grace period [07 §3.9-3.10].
- **`cli-codex`** (provider `codex`, alias `codex`). One `codex exec --json --ignore-user-config
  --skip-git-repo-check -m <full id> -C <wd> -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c
  mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN -c mcp_servers.gptr.default_tools_approval_mode="approve" -c
  mcp_servers.gptr.required=true -c mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <read-only | workspace-write>
  -` per turn (resume: `codex exec resume <thread> --json ... -c sandbox_mode=<mode> -`, IC-65), the prompt on
  stdin (`write_all()`), `GPTR_MCP_TOKEN` (a token bound to this session, IC-58) only in the child's environment
  (`child_env("cli-codex", set =)`); the MCP server comes from the `mcp.serve_ensure` service (P18); without httpuv/later/openssl the route runs on files
  only with a `notice`. Events `thread.started`, `turn.started`, `item.started|updated|completed`
  (`agent_message` -> text, `reasoning` -> thinking, `mcp_tool_call`/`command_execution` -> informational
  `tool_execution_*` events), `turn.completed{usage}`, `turn.failed{error}`, `error` [08 §2.E]; gptr counts turns
  and cancels at the cap, with `gptr.cli_turn_timeout` per exec. Sandbox mapping (IC-65): `plan`, `manual` and
  `edits` -> `read-only` (file changes go through gptr's gated `write`/`edit` over MCP); `auto` ->
  `workspace-write`, with control files hashed before and a files-checkpointer walk after each exec; native
  Windows falls back to `read-only` with a warning when the sandbox probe fails.


---

## 9. Tools and the system prompt

### 9.1 The tool record (kind `tool`, `gptr_tool()`) [stable]

| Field | Type / default | Contract |
|---|---|---|
| `name` | chr(1), `^[a-zA-Z0-9_-]{1,64}$` | direct tools: the wire name; `r` members: the member name under `namespace` |
| `description` | chr(1) | model-facing; direct tools at most 400 estimated tokens (`gptr_check()`); `r` members contribute only the first sentence to catalogs |
| `parameters` | JSON Schema list, `function(ctx)` or `NULL` | object schema (`type = "object"`); a function is evaluated once at freeze with `ctx$input` (the `r` tool's four variants, IC-68); `NULL` = derived from `fun`'s formals (all `string`, required when no default) |
| `execute` | `function(input, ctx)` or `NULL` | returns a `gptr_tool_result`, chr, a list(`text`, `images`, `value`, `is_error`, `details`) or `NULL` (normalised by `as_tool_result()`); may signal: the dispatcher turns any condition into an error result (INFRA-10) |
| `fun` | R function or `NULL` | the R-callable form for `exposure = "r"`; returns an R value whose `print()` is budgeted by `output_tokens` |
| `exposure` | `"direct"`, `"r"`, `"deferred"`, `"hidden"` | a default visibility, not an identity (IC-37): `direct`: declared in the tool array (plugin tools always; built-ins when their preset lists them); `r`: a `peter$` member with one signature line in a catalog; `deferred`: found only through `peter$search()` (still callable); `hidden`: callable by gptr code only. Any un-namespaced spec with a `fun` that is not `hidden` is a `peter$` member, and any spec with an `execute` may be put in the array by a preset |
| `namespace` | chr(1) or `NULL` | `r` members: `peter$<namespace>$<name>`; plugin specs with `exposure = "r"` MUST set it (their package name); reserved member names and `mcp` are refused (IC-37) |
| `execution` | `"sequential"` or `"concurrent"` | sequential tools go through the reactor FIFO (R-evaluating or file-writing tools MUST be sequential); one sequential call makes the whole turn's batch sequential (Pi) |
| `risk` | `function(input, ctx)` or `NULL` | returns a `gptr_risk` or `list(level = int(1), categories = chr, paths = chr)`; `NULL`: level 0 for `annotations$read_only`, else 2 |
| `snippet` | chr(1) or `NULL` | the one-line `- name: snippet` entry in the `<tools>` section (direct tools) |
| `guidelines` | chr or `NULL` | bullet lines appended to `<rules>` (direct tools; frozen at session start) |
| `signature` | chr(1) or `NULL` | the catalog line for `r` members; `NULL` = `schema_signature()` |
| `output_tokens` | int(1) or `NULL` | print/result budget; `NULL` = `gptr.helper_output_tokens` (members) or `gptr.r_output_tokens` (direct) |
| `record` | lgl(1) | calls of this member made in `r` code are kept in recorded code (bridges record digests); top-level calls of `record = FALSE` members are dropped from recorded code (IC-48) |
| `render` | `function(call, result, width)` or `NULL` | console rendering of a call and its result (IC-69) |
| `available` | `function(ctx) lgl(1)` or `NULL` | evaluated at session freeze; `FALSE` excludes a direct tool from the array (e.g. `ask` without a human) |
| `annotations` | named list | `read_only`, `destructive`, `idempotent`, `open_world`, `requires_user` (MCP names `readOnlyHint` etc. accepted and mapped) |

Added by the dispatcher at registration (not by authors): `schema_json` (once-serialised, sorted keys),
`r_signature`, `token_cost`.

**Wire shapes.** The frozen array is stored in the Anthropic shape (`{"name", "description", "input_schema"}`).
Adapters convert once per session: OpenAI Responses `{"type":"function","name","description","parameters",
"strict":false}`; chat completions `{"type":"function","function":{"name","description","parameters"}}`; Gemini
`{"functionDeclarations":[{"name","description","parameters"}]}` (JSON Schema keywords Gemini rejects are removed
by the adapter).

**Array order.** `read`, `r`, `edit`, `write`, `ask` (when available), then `grep`, `find`, `ls` (extended preset),
then plugin direct tools sorted by name, then direct MCP tools (`mcp__<server>__<tool>`) sorted by name.

### 9.2 Model-facing tool schemas (verbatim; Anthropic wire shape)

The `standard` preset with a human present and a bound document; `minimal` is the first four elements; `readonly`
is `read` and `r` (plus `ask` with a human). The `r` schema below is the full variant; it is frozen in one of four
variants (IC-68): `record` and `note` only when a document is bound at freeze, `timeout` (described `"Seconds; best
effort. Default 3600."`) only when no human can answer; measured 188 (document, no human), 169 (document, human),
137 (no document, no human: sub-agents), 118 (no document, human) o200k tokens; `read`, `edit` and `write` are Pi's strings (MIT, Pi `1b347794`, byte-identical
[01 §4.8]). Measured o200k tokens: four tools 674, with `ask` 819, `r` alone 197 (§7.2 of `03`).

```json
[{"name":"read","description":"Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.","input_schema":{"type":"object","required":["path"],"properties":{"path":{"type":"string","description":"Path to the file to read (relative or absolute)"},"offset":{"type":"number","description":"Line number to start reading from (1-indexed)"},"limit":{"type":"number","description":"Maximum number of lines to read"}}}},{"name":"r","description":"Run R code in the user's live R session. Objects persist between calls and belong to the user. Returns printed output, messages, warnings, errors with a traceback, and plots as images. Execution stops at the first error. Output beyond about 4000 tokens keeps the first 40% and last 60% and names a peter$out(id) handle for the rest.","input_schema":{"type":"object","required":["code"],"properties":{"code":{"type":"string","description":"R code to evaluate. May contain several expressions."},"record":{"type":"boolean","description":"Record this code in the user's document (default true). Use false for throwaway inspection."},"note":{"type":"string","description":"One-line decision or rationale, recorded as a '## Decision:' comment."},"timeout":{"type":"number","description":"Seconds; best effort. Default: none when the user is present, else 3600."}}}},{"name":"edit","description":"Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.","input_schema":{"type":"object","required":["path","edits"],"properties":{"path":{"type":"string","description":"Path to the file to edit (relative or absolute)"},"edits":{"type":"array","items":{"type":"object","required":["oldText","newText"],"properties":{"oldText":{"type":"string","description":"Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call."},"newText":{"type":"string","description":"Replacement text for this targeted edit."}}},"description":"One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."}}}},{"name":"write","description":"Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.","input_schema":{"type":"object","required":["path","content"],"properties":{"path":{"type":"string","description":"Path to the file to write (relative or absolute)"},"content":{"type":"string","description":"Content to write to the file"}}}},{"name":"ask","description":"Ask the user one to four questions and wait for the answers, when a decision changes the result and cannot be inferred. The user may always type their own answer. Not for permission to run code: the harness asks for that itself.","input_schema":{"type":"object","required":["questions"],"properties":{"questions":{"type":"array","maxItems":4,"items":{"type":"object","required":["id","question"],"properties":{"id":{"type":"string"},"question":{"type":"string"},"type":{"enum":["single","multi","text"]},"options":{"type":"array","maxItems":9,"items":{"type":"string"}},"default":{"type":"string"}}}}}}}]
```

The `extended` preset appends Pi's `grep`, `find` and `ls` (MIT, verbatim [01 §3.6-3.8]; IC-17):

```json
[{"name":"grep","description":"Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.","input_schema":{"type":"object","required":["pattern"],"properties":{"pattern":{"type":"string","description":"Search pattern (regex or literal string)"},"path":{"type":"string","description":"Directory or file to search (default: current directory)"},"glob":{"type":"string","description":"Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"},"ignoreCase":{"type":"boolean","description":"Case-insensitive search (default: false)"},"literal":{"type":"boolean","description":"Treat pattern as literal string instead of regex (default: false)"},"context":{"type":"number","description":"Number of lines to show before and after each match (default: 0)"},"limit":{"type":"number","description":"Maximum number of matches to return (default: 100)"}}}},{"name":"find","description":"Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).","input_schema":{"type":"object","required":["pattern"],"properties":{"pattern":{"type":"string","description":"Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"},"path":{"type":"string","description":"Directory to search in (default: current directory)"},"limit":{"type":"number","description":"Maximum number of results (default: 1000)"}}}},{"name":"ls","description":"List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).","input_schema":{"type":"object","properties":{"path":{"type":"string","description":"Directory to list (default: current directory)"},"limit":{"type":"number","description":"Maximum number of entries to return (default: 500)"}}}}]
```

Direct `grep` arguments map to `peter$grep()` as `ignoreCase` -> `ignore_case`, `literal` -> `fixed`, `context`,
`limit`, `glob`, `path`; its text result is Pi's format (`file:line: text`, context lines `file-line- text`, the
notices of 01 §3.6). Direct `find` and `ls` use Pi's output formats and notices.

**Result texts.** `read`, `edit`, `write` return Pi's messages [01 §3.2-3.4] (edit adds a diff of at most 400
tokens only when the fuzzy fallback, EOL or encoding normalisation changed what the model literally asked for);
`r` returns `format_eval_result()` text plus image blocks; `ask` returns 18 §3.6's texts; unknown tool:
`Tool <name> not found`; validation failure: `Invalid arguments for <tool>: <errors>`; denial: `Permission denied:
<reason>. <how to proceed>`; hook block: `Tool execution was blocked: <reason>`; interrupted tool: `Interrupted after
<s> s; side effects may have occurred.`; a `length`/`refusal` stop: `Tool call not executed: the response stopped
(<reason>) before the call was complete.`

### 9.3 The system prompt

Sections are `prompt_section` specs (§10.2) rendered at freeze in ascending `order`: the `preamble` untagged, every
other section wrapped as `<name>\n...\n</name>`, sections joined by one blank line. T0 = sections with `tier =
"T0"`, T1 = `tier = "T1"`; the frozen blocks never change during a session (mid-session changes are appended
operator section patches: `Updated system prompt section "<name>":\n\n<section>` or `Removed system prompt section
"<name>".`). `{s1}` is replaced by the configured System 1 alias (`jev`).

| Section | Tier | Order | Budget | Included when | Registered by |
|---|---|---|---|---|---|
| `preamble` | T0 | 100 | 120 | always (minimal preset: the short variant) | P07 |
| `tools` | T0 | 200 | 250 | always (lines of the active direct tools; the `ask` line only when `ask` is active) | P07 |
| `rules` | T0 | 300 | 450 | always: the `guidelines` of the active direct tools in array order, then P07's three closing lines (minimal preset: two extra lines); `readonly` drops the edit/write lines (IC-68) | P07 (closing lines); P10 (tool guidelines) |
| `r_session` | T0 | 400 | 500 | `r` active and the preset record includes it (not `minimal`): P07's core with `{{fragments}}` from `builtin:tools`, `builtin:bridges`, `builtin:lang`, `builtin:subagents` (IC-68) | P07 (core); P10, P22, P19 (fragments) |
| `r_performance` | T0 | 450 | 150 / 450 | `r` active and preset is not `minimal` (extended: the full text below) | P07 |
| `documents` | T0 | 500 | 250 | a history document is bound (`ctx$input$document` non-NULL, from the `doc.site` service) | P15 (IC-68) |
| `artifacts` | T0 | 600 | 150 | shiny installed and `builtin:artifacts` enabled | P23 (IC-68) |
| `system1` | T0 | 650 | 150 | a System 1 provider is usable (`model_default("system1")` non-NULL: key found or emulation configured) | P13 (IC-68) |
| `modes` | T0 | 700 | 120 | always | P07 |
| `context` | T0 | 750 | 160 | always | P07 |
| `addendum` | T1 | 800 | 1,000 | `.gptr/APPEND_SYSTEM.md` (trusted) or the user's `APPEND_SYSTEM.md` | P07 |
| `skills` | T1 | 820 | 1,500 | visible skills and `read` active | P17 |
| `mcp` | T1 | 840 | 1,500 | enabled MCP servers with `r` exposure | P18 |
| `plugins` | T1 | 860 | 1,500 | plugin `r` members exist (`ns_catalog()`, P10) | P10 |
| `r_env` | T1 | 900 | 450 | the capability probe ran | P09 |

The standard texts are verbatim in §7.3 of `03` as amended by IC-67/IC-68 (no `str()` anywhere; `<r_session>` with
the `record = false` line and without the MCP sentence; `<context>` with the `trusted="false"` sentence; the skills
catalog with `[skill:<name>/SKILL.md]` pseudo-paths). Each owner's text MUST reproduce its part byte for byte (P07
acceptance 2 for P07's parts); P24 compares the composed prompt with every built-in loaded. `.gptr/SYSTEM.md` (trusted), the user's `SYSTEM.md` or `.opts$system` (a string) replace
`preamble`, `tools` and `rules` (Pi's rule); a named `.opts$system` list overrides named sections (`NULL` removes).
Texts not given in `03`, fixed here verbatim (measured in `final/prompt/`, IC-17):

`preamble`, minimal variant:

```text
You are Peter, an agent working inside the user's live R session. Use the r tool to inspect and compute on the objects in memory; what you create stays in the session for the user.
```

`tools`, minimal variant (no `ask`):

```text
<tools>
- read: Read file contents
- r: Run R code in the user's live session (objects persist; plots come back as images)
- edit: Make precise file edits with exact text replacement, including multiple disjoint edits in one call
- write: Create or overwrite files

In addition to the tools above, you may have access to other custom tools depending on the project.
</tools>
```

The extended preset adds, after the `write` (or `ask`) line: `- grep: Search file contents for patterns (respects
.gitignore)`, `- find: Find files by glob pattern (respects .gitignore)`, `- ls: List directory contents` (Pi's
snippets). The readonly preset lists `read`, `r` (and `ask`).

`rules`, minimal preset: the standard `<rules>` list of §7.3 of `03` followed, as its last two items before
`</rules>`, by:

```text
- Inside r, peter$grep(), peter$find(), peter$ls(), peter$sh(), peter$py() and peter$sql() search files and run programs, Python and SQL; assign their results and print only what you need
- To hand a result back, assign it and call gptr_return(obj)
```

`r_performance`, extended preset [19 §3.1, shipped verbatim]:

```text
<r_performance>
You work in the user's live R session; objects in memory are the asset. Reuse them; never reload data or re-run slow steps unless asked.
- Use only packages installed per <r_env>. Ask before installing or updating any package; else take the base-R route.
- Check size first (dim(), object.size()); print head() or peter$describe(x), never whole big objects; str() makes the next in-place edit of a large object copy it. Avoid copies: data.table := / set*, rm() temporaries.
- CSV: data.table::fread/fwrite, arrow::read_csv_arrow or vroom, not read.csv. Parquet: arrow or nanoparquet. Larger than RAM: duckdb SQL on files or arrow::open_dataset; filter/aggregate before collect(). Objects: qs2::qs_save, else saveRDS(compress = FALSE).
- Grouping >1e6 rows: data.table or collapse, not aggregate(). Inside data.table j and collapse::fsummarise call mean(x)/fmean(x) unqualified; pkg::fun there disables the fast path (up to 100x slower).
- Regex: grepl(perl = TRUE) or fixed = TRUE, never the default engine on large vectors.
- Sort: order(method = "radix") (byte order for strings); kit::topn for top-k; stringi::stri_sort(numeric = TRUE) for natural order.
- Keep sparse data sparse (Matrix); matrixStats for row/col stats; never as.matrix() a big sparse, DelayedArray or BPCells matrix.
- Parallel: at most the workers in <r_env>; mirai or future multisession (portable), not mclapply on Windows; pass data explicitly.
- Plots >1e5 points: scattermore, ggrastr::rasterise() or geom_hex().
- Measure before optimising (system.time, bench::mark, profvis). More: read the high-performance-r skill.
</r_performance>
```

`plugins` section (T1; body built by `ns_catalog()`):

```text
<plugins>
Plugin functions are R functions called inside r. They return R values; assign and summarise them before printing. peter$search("words") finds more and peter$help("<ns>/<name>") shows a full schema.
peter$<ns>$<name>(<arg>: <type>, <arg>?: <type>)  # <first sentence of the description>
</plugins>
```

Mode blocks and the first-message formats are verbatim in §7.4 of `03`; the non-interactive suffix appended inside
the mode block is exactly `No one can answer questions or approvals in this run, so actions that need approval
stop the run. State your assumptions instead of asking.` (with `gptr.noninteractive_ask = "deny"` the second
clause reads `so actions that need approval are refused.`); in `manual` mode, where `ask` stays declared (IC-68),
it is `No one can answer questions or approvals in this run: actions that need approval, and questions asked with
the ask tool, stop the run. Ask only when no reasonable assumption lets you continue.`

### 9.4 The `peter$` namespace members [stable]

Registered as tool specs with a `fun` by the plans named (`read`, `write`, `edit`, `grep`, `find`, `ls` also carry
an `execute`, so presets can declare them as direct tools; IC-37). Every member validates its arguments with the
§1.1 checkers; called from model code while a run executes, it passes `dispatch_nested()` (P06) with the risk shown;
called by the user it runs directly. Prints are budgeted by `gptr.helper_output_tokens` (1,500), and at most 0.6x
the remaining `r` budget when called inside `r`.

| Member | Owner | Signature | Returns | Risk (level) |
|---|---|---|---|---|
| `read` | P10 | `peter$read(path, offset = NULL, limit = NULL)` | `gptr_lines` | 0 in project, 1 outside, 2 protected |
| `write` | P10 | `peter$write(path, content)` | path, invisibly | 2 in project, 3 outside/protected |
| `edit` | P10 | `peter$edit(path, edits, replace_all = FALSE)` (`edits` = list of `list(oldText =, newText =)` or a chr(1) patch envelope) | `gptr_patch` | as `write` |
| `grep` | P10 | `peter$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"), sort = c("path", "count", "mtime"))` (`sort` applies to `files` and `count`) | `gptr_matches` (`output = "files"`: `gptr_files`; `"count"`: df `file`, `n`) | 0 (1 outside the project) |
| `find` | P10 | `peter$find(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"), type = "file", limit = 1000L)` (`relevance`: exact basename > prefix > substring > subsequence, ties by path; REQ-08) | `gptr_files` | 0 / 1 |
| `ls` | P10 | `peter$ls(path = ".", sort = c("name", "mtime", "size"), long = FALSE)` | `gptr_files` | 0 / 1 |
| `help` | P10 | `peter$help(name, package = NULL, budget = 800L)` | chr: a tool schema for `"<server>/<tool>"`, `"<ns>/<name>"` or a member name; else R help via `tools::Rd2txt()`; budgeted; `record = FALSE` | 0 |
| `search` | P10 | `peter$search(words, limit = 8L)` | df `name`, `kind` (`member`, `plugin`, `mcp`, `skill`, `deferred`, or a `search_source` kind), `signature`, `score`; `record = FALSE` | 0 |
| `describe` | P10 | `peter$describe(x, budget = 150L)` | `gptr_describe(x, budget)`; `record = FALSE` | 0 |
| `plot` | P10 | `peter$plot(which = NULL, width = 1000L, height = 700L)` | attaches the current device's plot (or stored plot `which`, IC-67) at that size to the running `r` result (about 900 tokens); `invisible(NULL)`; `record = FALSE` | 0 |
| `out` | P10 (only owner, IC-36) | `peter$out(id, stream = c("stdout", "stderr"), lines = NULL)` | chr (the stored full text from the session store, the process store or the spill file, or `lines` of it); `record = FALSE` | 0 |
| `sh` | P22 | `peter$sh(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE, max_tokens = NULL)` (`cmd` chr: length > 1 = argv without a shell; length 1 = a command line through `shell_resolve()` when it has shell syntax) | `gptr_cmd` | command classifier (G5 levels); computed commands 3 |
| `script` | P22 | `peter$script(path, args = character(), interpreter = NULL, ...)` | `gptr_cmd` | 3 |
| `bg` | P22 | `peter$bg(cmd, name = NULL, stdin = FALSE, merge = TRUE)` | `gptr_job` (added to the job table) | 3 |
| `jobs` | P22 | `peter$jobs(kill = FALSE)` | df of `bg` jobs | 0 (kill: 3) |
| `py` | P22 | `peter$py(code, name = NULL, max_rows = 10L)` | `gptr_py`; reticulate (Suggests) | Python classifier |
| `sql` | P22 | `peter$sql(query, name = NULL, con = NULL, n = 10L)` | data frame (all rows; prints dims + `n` rows); `name` = a data frame registered in an in-memory duckdb under its expression label (`name = mtcars` -> table `mtcars`) or a named list of data frames (one copy on the next edit of each, R9); without `name`, `con` or the DBI connection found by name in the evaluation environment | SQL classifier (select 0, drop 3) |
| `knit` | P22 | `peter$knit(engine, code)` | chr: output of a knitr engine; `bash`, `sh`, `zsh`, `powershell`, `cmd` run through `peter$sh()` with the `helper` environment and a timeout (IC-67) | 3 (shell engines: the command classifier) |
| `app` | P23 | `peter$app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` (`kind`: a registered `artifact_type`, IC-69; ids that are Windows reserved names are refused, IC-63) | `gptr_artifact`; the `r` result gets its URL, checks and screenshot image | 3 |
| `mcp` | P18 | `peter$mcp$<server>$<tool>(...)` | R values (`structuredContent` simplified, else text); `isError` -> `gptr_error_mcp_tool` in R | server annotations: `readOnlyHint` 0 (trusted servers), `destructiveHint = FALSE` 2, none 3 |

`peter$<ns>$<name>(...)` reaches plugin members (§9.1 `namespace`).


---

## 10. The extension API (S-11, REQ-41) [stable unless marked]

### 10.1 Registration paths, ranks, sources and filters

| Path | Rank | Source string | Lifetime |
|---|---|---|---|
| call arguments: `peter(..., tools = list(spec))`, `model = <spec>`, `agents =`, session hooks `gptr_on(s, ...)` | 0 | `session` | the session |
| trusted project: `.gptr/` resources, `.gptr/extensions/*.R`, project settings `plugins` | 1 | `project` | the process (re-read by `gptr_reload()`) |
| user: `gptr_register()`, user directories, user settings `plugins` | 3 | `user` | the process |
| plugins (packages, directories, `.claude-plugin` bundles) | 5 | `plugin:<name>` | the process; removed when the package unloads |
| built-ins (`builtin_<name>()` factories) | 6 | `builtin:<name>` | the process |

Same `(kind, name)`: the lowest rank wins; ties: the first registered, with a `collision` diagnostic.
`all`-resolving kinds keep every record, ordered by the kind's order field when it has one, else by rank then
registration. A lower-rank record shadows **only** the record with the same `(kind, name)`; a whole built-in is
disabled only by an explicit `-builtin:<name>` filter (Pi merges per tool, `agent-session.ts:3478-3481`; IC-69).
Rank-0 records passed as call arguments (`tools =`, `extensions =`, `plugins =`, `model = <spec>`) are scoped to
their session and removed with it.

Filters (settings key `filters`, call `plugins = "-builtin:mcp"`, `gptr_config(filters =)`): `-builtin:<name>`,
`-plugin:<name>`, `-<kind>:<name>`, and `+...` to undo. Security rule: filters from a *project* settings file never
disable `policy` or `hook` records of the user or of built-ins; filters from **no** source (project, user,
call, `gptr_config()`) disable `builtin:permissions`, `builtin:plan`, the `critical_guard` and `secret_guard`
policies or `builtin:secrets`, and inside a run filters that would remove `policy` or `hook` records are refused
(IC-53).

### 10.2 The 38 kinds

`resolve`: `first` (one winning record per name) or `all`. "Order" is the field that orders `all` kinds. Rows
32-38 were added by IC-69 and IC-34 (38 kinds in all; P02 defines 37, P22 adds `interpreter`). Every spec
also has `kind`, `name` and `api_version` (the extension API version it was written for; the provider and adapter field `api` is the wire api). Validators accept unknown fields
(forward compatibility) and reject wrong types of known fields with `gptr_error_invalid_spec`.

| # | Kind | Resolve / order | Fields (type) | Contract and failure rule | Defined by |
|---|---|---|---|---|---|
| 1 | `provider` | first | `id` (= name, `^[a-z0-9][a-z0-9-]*$`), `api` chr(1), `base_url` chr(1)\|NULL, `auth` (chr of environment-variable names, or `function()` returning a handle or `NULL`, or `NULL` for none), `models` list of model records\|NULL, `compat` named list, `type` (`chat`, `classifier`, `cli`), `headers` named list of non-secret strings, `discover` `function()` -> df\|NULL, `status` `function()` -> named list\|NULL (reads cached data only unless `check = TRUE`), `aliases` chr, `local` lgl(1) (loopback server: unknown model ids allowed, no egress acknowledgement), `offline` lgl(1) (no remote model is called: exempt from `replay_guard()`; the fake provider and the mock-server and fake-CLI test providers, IC-45), `rate` `list(requests_per_s, tokens_per_s)`\|NULL (static limits feeding the token bucket, IC-64) | data; `auth` is evaluated per request (INFRA-22); `discover` runs only on request | P02 |
| 2 | `adapter` | first (name = `api`) | `api`, `transport`, `build`, `parse`, `stream`, `classify`, `capabilities` (§8.1) | never throws after `start` (§8.1); a thrown error becomes `stop_reason = "error"` | P02 |
| 3 | `model` | first (name = `provider/id`) | the §4.9 record fields | data | P02 |
| 4 | `router` | first | `route` `function(request, ctx)` -> chr(1) model ref or `list(model, thinking = NULL, state = NULL)`; `description`; `timeout` num(1) (default 2 s) | usable as `model = <name>`; called by P06 before every request and at compaction (IC-69); `request` = `list(prompt, messages (projected, read-only), state, previous, reason = "turn" \| "compaction" \| "direct", session)`; a timeout, an error or a non-registered result falls back to the default model with a diagnostic and a `route` event; System 1 through `ctx$decide()`; each switch appends `model_change` and a `gptr.router` state entry | P02 |
| 5 | `tool` | first (name, or `<namespace>/<name>`) | §9.1 | §9.1; failures become error results | P02 |
| 6 | `interpreter` | first | `ext` chr, `programs` chr (candidates, first found wins), `args` `function(path, args)` -> chr, `windows_only` lgl(1) | used by `peter$script()` | P22 (through `kind`) |
| 7 | `mcp_server` | first | §11.7 fields | data; connection errors are classed conditions at first use | P02 |
| 8 | `skill` | first | `description` chr(1) (<= 1,024 chars), `path` (SKILL.md), `dir`, `source`, `disable_model_invocation` lgl(1), `allowed_tools` chr, `tokens` num(1) | untrusted text; invalid frontmatter -> skipped with a diagnostic | P02 |
| 9 | `prompt_template` | first | `text` chr(1), `description`, `argument_hint`, `source` | Pi template grammar; `/name args` | P02 |
| 10 | `command` | first (name without `/`) | `handler` `function(args, ctx)`, `description`, `complete` `function(prefix, ctx)` -> chr\|NULL | `args` is the raw string after the command; the handler returns `NULL`, a chr (printed verbatim) or `list(prompt = chr(1))` (sent as a prompt); an error is reported and the input counts as handled | P02 |
| 11 | `hook` | all (rank) | `event` chr(1), `handler` `function(event, ctx)`, `matcher` (NULL, a tool-name glob, or `function(event)` -> lgl) | §10.4 returns; errors per §10.7 | P02 |
| 12 | `policy` | all / `order` (int, default 500) | `check` `function(call, ctx)` -> `NULL` or `list(decision = "allow" \| "deny" \| "ask" \| "modify", reason = chr(1), input = named list)`; `description`; `order` | combined deny > ask > modify > allow; a throwing policy denies; must return within 10 ms | P02 |
| 13 | `context_block` | all / `order` (int, default 650) | `provide` `function(ctx, budget)` -> `NULL`, chr(1) or `list(text, attrs)`; `placement` (`first`, `turn`, `both`; IC-38); `authority` (`data`, `operator`: rank >= 3 only, IC-52); `budget` int(1); `order` | `ctx$input` gives `list(call, turn, prompt, placement, last_hash, opts)`; a turn block equal to its last emitted text is skipped; must not force promises or do I/O on user objects [R4]; output truncated to `budget`; an error omits the block with a diagnostic | P02 |
| 14 | `prompt_section` | all / `order` | `text` chr(1) or `function(ctx)` -> chr(1)\|NULL (`NULL` omits); `tier` (`T0`, `T1`); `order` int(1); `budget` int(1); `parent` chr(1)\|NULL (a fragment rendered inside the named section at its `{{fragments}}` marker, IC-68) | rendered once at freeze; `ctx$input` gives `list(preset (the preset record), tool_names, human, document, s1_alias, model, root, trusted)`; must be stable for the session; an error omits it with a diagnostic | P02 |
| 15 | `compactor` | first (selected by setting `compactor`, default `checkpoint`) | `should` `function(session, ctx)` -> lgl(1); `compact` `function(session, ctx)` -> `list(blocks, summary, state, first_kept_entry_id, usage, details)` | an error falls back to the built-in `checkpoint` compactor with a diagnostic | P02 |
| 16 | `cache_policy` | first (name = api, or `default`) | `plan` `function(parts, caps, session)` -> `list(anchors, tail_ttl, key)` | built-in: gap-based tail TTL | P02 |
| 17 | `estimator` | first (name `default`) | `estimate` `function(x, class)` -> num(1); `calibrate` `function(state, estimated, reported)` -> state | built-in: G2 class-aware estimator | P02 |
| 18 | `doc_format` | first | `ext` chr; `locate` `function(text, site)` -> `list(stmt, blocks)`; `render` `function(block, site)` -> chr; `upsert` `function(text, site, lines, block_id)` -> chr (new document text); `inert` `function(lines)` -> chr | an error writes nothing and falls back to the transcript with a diagnostic | P02 |
| 19 | `artifact_type` [experimental] | first | `build` `function(id, dir, data, ctx)`; `check` `function(dir, ctx)` -> `list(ok, messages)`; `launch` `function(version_dir, ctx)` -> `list(url, pid, stop)`; `stop` `function(handle)` | failures become tool results with the stage and a log tail | P02 |
| 20 | `backend` | first | `start` `function(spec, ctx)` -> handle `list(session, fds = function() int, poll = function() NULL, cancel = function() NULL)`; `poll`, `cancel`; `capabilities` (`parallel` = `io`/`cpu`, `live_objects` lgl, `ask` = `queue`/`forward`/`none`) | never blocks the reactor > 50 ms; cancel kills the process tree; errors give the child status `error` | P02 |
| 21 | `agent` | first | the `gptr_agent()` fields (§6.8) | data; invalid files skipped with a diagnostic | P02 |
| 22 | `ui` | first (selected by `gptr.ui`/settings) | `has_ui` `function()` -> lgl(1); `select(title, choices, default = NULL, details = NULL, multiple = FALSE, allow_other = FALSE)` -> int (NA = cancelled; `attr(, "other")` = free text); `input(prompt, default = "", secret = FALSE)` -> chr(1)\|NA; `questions(qs)` -> `list(answers = named list, cancelled = lgl(1))`; `notify(text, level = "info")`; `permission(request)` -> `list(decision = "allow" \| "deny" \| "abort", remember = NULL \| "session" \| "project", feedback = chr(1) \| NULL)` | a failing dialog is not an approval; `permission` defaults to one built from `select` | P02 |
| 23 | `frontend` [experimental] | first | `run` `function(session, ...)` -> session | owns the loop it runs | P02 |
| 24 | `setting` | first (name = dotted key, e.g. `subagents.max_depth`) | `default`, `description`, `scope` (`both`, `user`), `validate` `function(value)` -> value (or `gptr_error_invalid_argument`), `tighten` (NULL or chr: the ordered values from strictest to loosest) | values through `gptr_config()`; a project layer may only move a `tighten` setting towards the strict end | P02 |
| 25 | `secret_source` | all | `resolve` `function(name, ctx)` -> chr(1)\|NULL (registered with `secret_register()` at once); `list` `function(ctx)` -> chr; `store`, `forget` (optional) | never logs values | P02 |
| 26 | `redaction_rule` | all | `pattern` chr(1) (PCRE), `anchor` chr, `marker` chr(1) (the id inside `[secret:<id>]`), `profiles` chr | combined into one alternation; must not match its own marker | P02 |
| 27 | `env_alias` | all (name = canonical) | `aliases` chr | used by `gptr_env()` and ambient discovery | P02 |
| 28 | `child_env` | first (name = profile) | `base` (`inherit`, `allowlist`), `keep` chr, `drop` chr (regex), `set` named chr (values may be handles), `billing` named list | used by `child_env()`; every profile gets the empty `R_ENVIRON_USER`/`R_PROFILE_USER` files (IC-60) | P02 |
| 29 | `checkpointer` [experimental] | all (rank) | `scope` (`objects`, `files`, `state`, `artifacts`, `other`); `before` `function(call, ctx)` -> token; `after` `function(call, ctx, token)` -> JSON-able fragment; `undo`/`redo` `function(fragment, ctx, force)` -> chr report lines; `prune` `function(live_keys, ctx)`; `describe` `function(fragment)` -> chr | never throws into the loop (a failure marks its fragment not restorable); runs only for sequential, non-read-only tools | P02 |
| 30 | `kind` | first | `validate` `function(spec)` -> spec; `resolve`; `fields` chr; `order_field` chr(1)\|NULL; `experimental` lgl(1) | defines a new category; then `gptr_spec(<kind>, ...)` | P02 |
| 31 | `route` [experimental] (IC-02) | all / `order` (num) | `order`; `match` `function(call)` -> lgl(1); `run` `function(call)` -> value or `route_pass()`; `description` | §6.1.1 step 5; an error in `match` skips the route with a diagnostic; an error in `run` propagates to the caller | P02 |
| 32 | `preset` | first | `tools` chr or `function(human, model, mode)` -> chr; `sections` named lgl or `function(name)` -> lgl; `preamble` (`"standard"`, `"short"`) | `builtin:prompt` registers `minimal`, `standard`, `readonly`, `extended`; section predicates read the preset record, never its name (IC-69) | P02 |
| 33 | `risk_rule` | all | the columns of `risk-functions.csv` (§11.15) as a data frame, or `kind = "command"` rows | rows are concatenated with the shipped tables; on a duplicate the highest level wins; user and plugin rows may lower a level only explicitly (`lower = TRUE`) | P02 |
| 34 | `service` [experimental] (IC-34) | first (name = service name) | `fun` | replaces the bootstrap service of the same name at a lower rank; owned by its source, so filtering the source removes it | P02 |
| 35 | `renderer` [experimental] | first (name = custom entry type) | `render` `function(entry, width, ctx)` -> chr; `doc` `function(entry, format)` -> chr lines | used by the console and the document writers for custom entries appended with `ctx$append_entry()` | P02 |
| 36 | `search_source` [experimental] | all | `docs` `function(ctx)` -> df(`id`, `text`, `kind`) | indexed by `peter$search()` (BM25) | P02 |
| 37 | `store` [experimental] | first (selected by setting `store`, default `jsonl`) | `open`, `append`, `read`, `fork` functions with the `session-store.R` contracts of §7.6 | the built-in is the append-only JSONL store; a failing store stops the run with `gptr_error_internal` | P02 |
| 38 | `evaluator` [experimental] | first (selected by setting `evaluator`, default `r`) | `eval` with the `eval_r()` contract of §7.9 (returns a `gptr_eval_result`) | used by the `r` tool, `ctx$eval()` and the MCP server's `r`; copy-safety obligations [R1]-[R8] apply | P02 |

### 10.3 Built-in extensions (all through `ext_declare_builtin()`, rank 6)

| Built-in | File (plan) | Registers | Replaceable |
|---|---|---|---|
| `builtin:fake` | `provider-fake.R` (P01; declared by P05) | adapters `fake`, `fake-classifier` | yes |
| `builtin:secrets` | `auth-secrets.R` (P03) | secret sources, redaction rules, env aliases, child-env profiles | no (value redaction cannot be disabled) |
| `builtin:providers` | `provider-registry.R` (P05) | provider records of §8.1-8.2 of `03` | yes |
| `builtin:prompt` | `prompt-sections.R` (P07) | the §9.3 sections it owns, the four `preset` records, the gap `cache_policy`, the default `estimator`, the `session.add_tools` service | yes |
| `builtin:context` | `prompt-context.R` (P07) | context blocks `project_instructions` (100), `environment` (200), `mode` (300), `plan` (400) | yes |
| `builtin:compaction` | `prompt-compact.R` (P07) | compactor `checkpoint` | yes |
| `builtin:gateway` | `gptr-gateway.R` (P08) | routes `nested` (20), `continue` (60), `new` (70); core `setting` specs | no |
| `builtin:workspace` | `env-snapshot.R` (P09) | context blocks `workspace` (500), `workspace_changes` (100, turn), `attached` (600, turn); section `r_env` | yes |
| `builtin:tools`, `builtin:r` | `tool-namespace.R`, `tool-r.R` (P10) | one spec each for `read`, `edit`, `write`, `grep`, `find`, `ls` (direct and member forms, IC-37), `r`; the other members of §9.4 owned by P10 (incl. `out`); tool guidelines; `r_session` fragments; section `plugins`; `search_source` for members | yes |
| `builtin:permissions`, `builtin:plan`, `builtin:ui`, `builtin:ask` | `perm-gate.R`, `perm-plan.R`, `console-ui.R`, `tool-ask.R` (P11) | policies; plan policy and hooks; UI backends; `ask` tool | permissions/plan: no (filters from projects ignored); ui, ask: yes |
| `builtin:anthropic`, `builtin:openai`, `builtin:openai-compat`, `builtin:google` | P12 files | adapters | yes |
| `builtin:system1` | `s1-client.R` (P13) | provider `typesafe`, adapters, route `classifier`, section `system1` | yes |
| `builtin:console`, `builtin:jsonl` | `console-repl.R`, `console-jsonl.R` (P14) | frontends, route `console`, renderer hooks, commands | yes |
| `builtin:documents` | `doc-formats.R` (P15) | doc formats, route `document`, hooks, section `documents`, services `doc.*` | yes |
| `builtin:checkpoints` | `ckpt-rewind.R` (P16) | checkpointers, commands | yes |
| `builtin:skills`, `builtin:prompts`, `builtin:agents` | P17 files | skills, templates, agents, section `skills` | yes |
| `builtin:mcp` | `mcp-namespace.R` (P18) | MCP namespace, section `mcp`, servers | yes |
| `builtin:subagents` | `subagent-backends.R` (P19) | backends, routes `team`, `fanout`, the sub-agent `r_session` fragment | yes |
| `builtin:cli` | `cli-common.R` (P20) | providers `claude-cli`, `codex`; adapters | yes |
| `builtin:bridges`, `builtin:lang` | `bridge-sh.R`, `bridge-lang.R` (P22) | kind `interpreter`, interpreters, members, `r_session` fragments | yes |
| `builtin:artifacts` | `artifact-app.R` (P23) | artifact types, member `app`, section `artifacts`, checkpointer | yes |

Every factory calls only the API object, `ctx`, L0 helpers, its own area, the declared services and the kernel
SDK of IC-33 (§2.2 rule 3 of `03`); `test-arch-layers.R` enforces it.

### 10.4 Event catalogue (D-25, IC-03)

Payload fields are in addition to `type`, `session`, `run`, `agent`, `turn`, `ts` (§4.5). "Origin" `pi` means the
name and semantics follow Pi `1b347794`; `gptr` means gptr-specific. Handlers must ignore unknown payload fields.

| Event | Origin | Semantics | Payload | Handler may return | Emitted by |
|---|---|---|---|---|---|
| `project_trust` | pi | first decision | `cwd`, `changed` (files whose trust fingerprint changed, IC-52) | `list(decision = "yes" \| "no", remember = lgl(1))` | P08 (first use of untrusted project resources; `gptr_trust()` itself emits nothing) |
| `resources_discover` | pi | collect | `cwd`, `reason` | `list(skill_paths, prompt_paths, agent_paths)` (chr each) | P17 |
| `session_start` | pi | collect (before the prompt freezes) | `reason` (`new`, `fork`, `resume`, `replay`, `child`) | `list(sections = named list (chr or NULL to remove), blocks = list of context blocks for the first message)` | P06 |
| `session_before_fork` | pi | first decision | `source`, `at` | `list(cancel = TRUE, reason)` | P06 |
| `session_shutdown` | pi | notify | `reason` (`exit`, `gc`, `unload`) | - | P06, P14 |
| `input` | pi | transform chain | `text`, `source` (`prompt`, `pipe`, `repl`, `passthrough`, `steer`; `steer` = pause-menu input) | `list(action = "continue" \| "transform" \| "handled", text)` | P08, P14 |
| `agent_start`, `agent_end` | pi | notify | `agent_end`: `status`, `reason`, `usage` (the run's rows), `doc` (site or NULL), `turns` | - | P06 |
| `turn_start`, `turn_end` | pi | notify | `turn_end`: `message` (assistant), `results` (tool results) | - | P06 |
| `before_request` | gptr | notify, read-only | `provider`, `model`, `request_id`, `view`, `tokens_est` | - (a handler that changes the frozen prefix triggers `cache_break`) | P06 |
| `request_params` | gptr | patch chain | `provider`, `model`, `params` (only the adapter's `capabilities$request_params` fields, e.g. `service_tier`, `metadata`, `user`) | `list(params)`; patches to other fields are ignored with a diagnostic (IC-69) | P06 |
| `message_start`, `message_update`, `message_end` | pi | notify | `role`; update: `index`, `kind` (`text`, `thinking`, `toolcall`), `delta`; end: `message` | - | P06 |
| `tool_call` | pi | decision, **error = block** | `tool_name`, `tool_call_id`, `input`, `nested`, `parent_tool_call_id`, `risk` | `NULL`, `list(decision = "block", reason)`, or `list(decision = "modify", input)` | P06 |
| `permission_request` | gptr | first decision, **error = deny** | the §7.11 permission request record | `list(decision = "allow" \| "deny", reason)` | P06 |
| `tool_execution_start`, `tool_execution_update`, `tool_execution_end` | pi | notify | `tool_call_id`, `tool_name`, `input` (start), `text` (update), `is_error`, `elapsed`, `details` summary (end) | - | P06 |
| `tool_result` | pi | patch chain | `tool_name`, `tool_call_id`, `input`, `content`, `details`, `is_error` | `list(content, details, is_error)` (any subset) | P06 |
| `queue_update` | pi | notify | `steer` int, `follow_up` int | - | P06 |
| `retry_start`, `retry_end` | gptr | notify | `attempt`, `delay`, `class`; end: `ok` | - | P06 (from P04) |
| `session_before_compact` | pi | first decision | `reason` (`threshold`, `cold`, `overflow`, `manual`), `tokens` | `list(cancel = TRUE)` or `list(result = <compactor result>)` | P07 |
| `session_compact` | pi | notify | `strategy`, `tokens_before`, `summary_tokens` | - | P07 |
| `session_before_tree` | pi | first decision | `from`, `to`, `plan` (df) | `list(cancel = TRUE, reason)` | P16 |
| `session_tree` | pi | notify | `from`, `to`, `report` | - | P16 |
| `document_write` | gptr | block + patch, **error = block** | `path`, `format`, `kind` (`block`, `transcript`, `inert`), `block_id`, `lines` | `list(block = TRUE, reason)` or `list(lines)` | P15 |
| `decision` | gptr | notify | `model`, `question`, `type`, `n`, `summary`, `cached` | - | P13 |
| `route`, `model_select` | gptr, pi | notify | `route`, `router`, `model`, `reason`; `from`, `to`, `reason` | - | P08, P06 (router switches, IC-69) |
| `subagent_start`, `subagent_end` | gptr | notify | `child`, `agent`, `backend`, `model`; end: `status`, `usage` | - | P19 |
| `artifact_start`, `artifact_stop` | gptr | notify | `id`, `url`, `version`; stop: `reason` | - | P23 |
| `usage`, `budget_near`, `budget_exceeded` | gptr | notify | `row`; `kind`, `budget`, `used` | - | P06 |
| `cache_break` | gptr | notify | `provider`, `model`, `first_diff`, `entry`, `culprit` | - | P07 |
| `bridge_call` | gptr | notify | `bridge`, `id`, `cmd` (redacted), `level`, `status`, `seconds`, `bytes_out`, `bytes_err`, `spill`, `digest` | - | P22 |
| `checkpoint` | gptr | notify | `tool_call_id`, `objects`, `files`, `restorable` (counts) | - | P16 |
| `secret_registered` | gptr | notify | `name`, `source`, `count` (never values) | - | P03 |
| `mcp_servers_change` | pi | notify | `added`, `removed` | - | P18 |
| `mcp_serve_start`, `mcp_serve_stop` | gptr | notify | `url` | - | P18 |
| `<plugin>:<topic>` channels | gptr | notify | plugin-defined `data` | - | `ctx$emit()` |

Not ported from Pi (no equivalent in an append-only, R-console harness, or superseded; plugin authors use
`compactor`, `context_block` and `request_params` instead, IC-69): `context`,
`context_with_system`, `before_provider_request` (replaced by the read-only `before_request`),
`before_provider_headers`, `after_provider_response`, `provider_stream_event`, `before_agent_start` (use
`session_start`), `agent_before_settle`, `agent_settled`, `session_before_switch`, `session_compact_failed`
(a diagnostic instead), `session_info_changed`, `thinking_level_select`, `ui_prompt_start`, `ui_prompt_end`,
`user_bash` (no bash tool), shortcut and renderer hooks. Claude/Codex hook names are accepted only by the v1.x
hook importer's alias map.

### 10.5 The factory API object (`gptr_extension_api`, argument of `function(gptr)`)

| Member | Contract |
|---|---|
| `gptr$name`, `gptr$dir` | the extension's source string and directory (`NULL` for packages without files) |
| `gptr$state` | an environment private to the extension, process lifetime (assignable binding) |
| `gptr$register(spec)` | the one registration verb; staged until the factory returns (transactional); returns an unregister function invisibly |
| `gptr$register_<kind>(...)` | sugar: `gptr$register(gptr_spec("<kind>", ...))` generated for every registered kind (`register_tool`, `register_policy`, `register_context_block`, `register_route`, ...) |
| `gptr$on(event, handler, matcher = NULL)` | `gptr$register(gptr_hook(event, handler, matcher))`; channel names contain `:` |
| `gptr$require(requires)` | `">= 1.2, < 2"` or `"1.2"` (caret); unmet -> `gptr_error_api_version`, the factory is rolled back and the plugin disabled with a diagnostic |
| `gptr$has(feature)` | `lgl(1)`: feature names of `gptr_api()$features` |

After `gptr_reload()` or the plugin's unload, every method signals `gptr_error_stale_api`.

### 10.6 `ctx` (`gptr_ctx`, argument of every handler, tool `execute` and policy `check`)

| Member | Returns | Service (IC-09) |
|---|---|---|
| `ctx$session` | the `<session>` (or `NULL` for process-level dispatch) | - |
| `ctx$envir` (active binding) | the current run's evaluation environment, else the kept home, else `NULL` | P06 |
| `ctx$run` (active binding) | the current run id or `NULL` | P06 |
| `ctx$input` (active binding) | the rendering input for `context_block`/`prompt_section` calls, else `NULL` | P07 |
| `ctx$mode()`, `ctx$model()` | chr(1) | P06 |
| `ctx$has_ui()`, `ctx$ui()` | lgl(1); the `<spec:ui>` | `ui.get` (P11; before it: `FALSE`, the `none` UI) |
| `ctx$risk(code, kind = "r")` | `gptr_risk` | `risk.classify` (P11) |
| `ctx$redact(x, profile = "persist")` | redacted `x` | P01 `redact_hook()` (P03 installs `redact()`, IC-34) |
| `ctx$secret(name)` | a handle or `NULL` | `secret.lookup` (P03) |
| `ctx$execute_tool(name, input)` | the tool's result value (a nested call through the same gate, `dispatch_nested()`) | P06 |
| `ctx$send(text, as = c("steer", "follow_up"))` | `invisible(NULL)`; enqueues with `source = "extension"` (user-role data, never an operator relay; refused from model code, IC-55) | P06 |
| `ctx$set_model(ref, thinking = NULL, reason = "plugin")` | `invisible(NULL)`; a `model_change` at the next request boundary (one cache miss) | P06 (IC-69) |
| `ctx$add_tools(specs)` | `invisible(NULL)`; `session_add_tools()` | P07 (IC-69) |
| `ctx$tokens(x, class = "prose")` | num(1): the `estimator` kind's estimate | P01 (IC-69) |
| `ctx$eval(code, envir = NULL)` | a `gptr_eval_result` through the `evaluator` kind (plugin code; not gated) | `eval.r` (P09, IC-69) |
| `ctx$describe(x, budget = 150L)` | chr: `gptr_describe()` within the budget | `describe` (P09) |
| `ctx$append_entry(type, data)` | the entry id; `type` becomes `customType` `"<plugin>.<type>"` of a `custom` entry | P06 |
| `ctx$abort(reason)` | aborts the current run | P06 |
| `ctx$aborted()` | lgl(1): the run's abort flag (long tools poll it) | P06 |
| `ctx$update(text)` | emits `tool_execution_update` for the executing tool | P06 |
| `ctx$decide(question, x, ...)` | a System 1 vector, as `peter(question, x, model = <configured System 1>, ...)` | `s1.decide` (P13) |
| `ctx$usage()` | the session's `gptr_usage` | P06 |
| `ctx$state()` | an environment of per-session, per-plugin state (persisted as `gptr.ext` custom entries when JSON-able) | P06 |
| `ctx$emit(channel, data)` | dispatches a `<plugin>:<topic>` channel event | P02 |
| `ctx$get(kind, name)` | `registry_get(kind, name, session)` | P02 |

`ctx` is created once per session (`ctx_new()`), never per dispatch; members are closures that fetch their service
at call time (`ctx.kernel`, `ctx.input`, ...; IC-34); `$<-` refuses assignment.

### 10.7 Dispatch semantics (`ev_dispatch()`, P02)

Handlers run in order: session listeners (rank 0, registration order), then registry hooks by rank and
registration. A `matcher` that does not match skips the handler. Payloads are values: a handler cannot mutate
them; it returns a patch.

| Semantics | Algorithm | Result of `ev_dispatch()` | Handler error |
|---|---|---|---|
| notify | call every handler; ignore returns | `NULL` | diagnostic, continue |
| collect | call every handler; merge returned lists: list-valued fields are concatenated, named-list fields merged with earlier (lower rank) handlers winning on conflicts | the merged list | diagnostic, continue |
| transform chain | `text` flows through handlers; `"transform"` replaces it; `"handled"` stops the chain | `list(action, text)` | diagnostic, continue |
| decision (`tool_call`) | stop at the first `block`; `modify` replaces `input` for later handlers and the tool | `list(decision = "allow" \| "block" \| "modify", reason, input)` | **block** (fail closed) |
| first decision | the first non-`NULL` return wins | that return or `NULL` | diagnostic, continue (`permission_request`: **deny**) |
| patch chain | each handler sees the payload patched by the previous ones | the patched payload | diagnostic, continue |
| block + patch (`document_write`) | stop at the first `block = TRUE`; `lines` patches | `list(block = lgl(1), reason, lines)` | **block** |

Hook-injected context (returned `blocks`, `text` of transforms) is capped at 10,000 characters per dispatch
[20 §3.7]; indexing by event keeps dispatch cost independent of unrelated hooks [G1 risk].

### 10.8 Loading plugins: manifests, lazy activation, declarations

- Discovery never runs plugin code: packages are found by `Config/gptr/plugin` in `DESCRIPTION` or
  `inst/gptr/plugin.json`; directories by `plugin.json`; Claude bundles by `.claude-plugin/plugin.json` (§11.12).
- Code runs only for plugins enabled by a call argument (`plugins =`), user settings, or trusted project settings.
  Declarative resources of attached packages (skills, templates) are available as untrusted text immediately.
- A lazy plugin registers placeholders for `extension.provides` and puts `extension.declarations` (signature lines
  and descriptions of its `r` members and direct tools) into the frozen prompt before activation, so activation
  never changes the cached prefix. The factory runs on the first `registry_get()` of a provided capability or the
  first dispatch of a provided event.
- Loading is transactional (§7.2 `ext_load()`); failures are diagnostics; start-up never fails because of a plugin.
- `setHook(packageEvent(pkg, "onUnload"))` removes an unloaded package's records; captured API objects then raise
  `gptr_error_stale_api`.

### 10.9 API 1.0 surface and versioning

API 1.0 consists of: the 63 exports (§6); the kinds and fields of §10.2; the events, payload fields and handler
returns of §10.4; the API object (§10.5) and `ctx` (§10.6) members; the dispatch semantics (§10.7); the manifest
format (§11.12); the record shapes a plugin sees (§4). `gptr_api()$version` is `1.0` and changes only when this
surface changes: MINOR releases are additive (new kinds, events, members, optional fields; handlers ignore unknown
payload fields, validators accept unknown spec fields); MAJOR releases break and require the CRAN notice period to
reverse dependencies found with `tools::package_dependencies(reverse = TRUE, which = "most")`. Deprecation: a
deprecated member warns once per session (`gptr_warning_deprecated`; `options(gptr.deprecations = "error")` for
plugin CI) and lives at least one MINOR release and six months. Items marked [experimental] may change in a MINOR
release.


---

## 11. File formats

All JSON files are UTF-8 without BOM, LF, written atomically (`write_atomic()`), parsed with `json_decode()`.
Unknown keys are preserved on rewrite and ignored on read.

### 11.1 The workspace tree (IC-18)

```text
<project>/.gptr/                                   created by gptr_init() or an interactive yes (P08)
  vignette.Rmd                     P08 template   committed   project instructions (read as text, never executed; P07)
  settings.json                    P08            committed   project settings (§11.2; trust rules)
  settings.local.json              user           ignored     legacy: only deny/ask additions, only when trusted (§11.3, IC-52)
  .gitignore                       P08 template   committed   (below)
  SYSTEM.md, APPEND_SYSTEM.md      user           committed   optional prompt replacement/addendum (trust-gated; P07)
  mcp.json                         P18            committed   project MCP servers (trust-gated; §11.7)
  skills/<name>/SKILL.md           user/P17       committed   Agent Skills (read as untrusted text)
  agents/<name>.md                 user/P17       committed   agent definitions (tool and model fields trust-gated)
  prompts/<name>.md                user/P17       committed   prompt templates
  extensions/<name>.R              user/P17       committed   `function(gptr)` factories (trust-gated; last expression is the factory)
  plugins/<name>/                  user/P17       committed   directory plugins (trust-gated)
  sessions/<YYYYmmddTHHMMSS>_<id>.jsonl  P06     ignored     session trees (§11.4); lock <file>.lock/pid
  cache/s1/<2hex>/<sha256>.json    P13            committed   System 1 answers (salted input hashes only; §11.9)
  cache/s1/salt                    P13            committed   per-project salt of the S1 hashes (IC-70)
  cache/s2/<2hex>/<sha256>.json    P15            ignored     System 2 answer text for replay (§11.9)
  cache/tmp/                       P01            ignored     spill files, per-session wire logs (pruned after 7 days); deferred-write sidecars (never pruned automatically, IC-51)
  checkpoints/                     P16            ignored     blobs, object images, index (§11.14)
  artifacts/<id>/                  P23            partly      app.R and artifact.json committed; vNNN/data/ and run/ ignored (§11.6)
  plans/<YYYY-MM-DD>-<slug>.md     P11            committed   proposed plans
  transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R  P15  ignored  console transcripts (§11.5; ignored by default, IC-70)
  locks/<sha1 of path_key(document path)>/pid  P15  ignored  document locks (pid + creation time; stale when the pid is dead or after 30 s, IC-71)
```

`inst/templates/gitignore` (P08), written as `.gptr/.gitignore`:

```text
sessions/
cache/s2/
cache/tmp/
checkpoints/
artifacts/*/v*/data/
artifacts/*/run/
locks/
*.lock/
settings.local.json
transcripts/
```

User level: `tools::R_user_dir("gptr", "config")` holds `settings.json`, `auth.json` (0600), `trust.json`,
`mcp.json`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `skills/`, `agents/`, `prompts/`, `extensions/` and
`projects/<16 hex>.json` (per-project remembered permission answers, transcript target and record consent, keyed
by `sha256(path_key(root))`, IC-52); `tools::R_user_dir("gptr", "cache")` holds `models.json` + `models.etag`,
`mcp-tools/`, `mcp-era/`, `procs/` (process tree markers for the orphan sweep, IC-60) and, only with
`gptr.mcp_debug`, `mcp-logs/` (5 MB rotation; otherwise MCP logs live in `tempdir()/gptr/mcp-logs/`, IC-70). Without a workspace everything session-related lives under `file.path(tempdir(), "gptr")` with
the same sub-layout (`sessions/`, `cache/`, `checkpoints/`, `artifacts/`, `plans/`); the System 1 cache stays in
memory.

### 11.2 `settings.json` (user and project) and layers

Layers, lowest to highest: package defaults < user `settings.json` < project `.gptr/settings.json` < the
user-level project file `projects/<hash>.json` (IC-52) < `options(gptr.*)` < `gptr_config(.scope = "session")` <
call arguments. An **untrusted** project contributes only changes that tighten `tighten`-type settings (a stricter
`mode`, added `permissions.deny`/`permissions.ask` rules, a stricter `context`, `record = "off"`); a **trusted**
project contributes every key, but `tighten`-type settings still only tighten and project `permissions.allow`
rules never loosen `plan` or pre-approve level 4. A legacy `.gptr/settings.local.json` contributes only
deny/ask additions and only in a trusted project. `egress` is read only from the user file. Safety options are
snapshotted per run (IC-53).

| Key | Type | Default | Tighten order (strict -> loose) | Owner |
|---|---|---|---|---|
| `version` | int | `1` | | P08 |
| `model` | chr\|null | `null` (first available route, §8.4 of `03`) | | P08 |
| `small_model` | chr\|null | `null` (the catalog's small sibling of `model`) | | P08 |
| `system1` | chr\|null | `null` (= `typesafe/jev-latest` when a key is found); `"emulate:<ref>"` opts into emulation | | P13 |
| `mode` | chr | `"manual"` | `plan`, `manual`, `edits`, `auto` | P08/P11 |
| `preset` | chr | `"standard"` | | P07 |
| `tools` | `{enable: [chr], disable: [chr], presets: {<model glob>: <preset>}}` | `{}` | | P07 |
| `permissions` | `{allow: [rule], ask: [rule], deny: [rule]}` | `{}` | deny/ask additions tighten | P11 |
| `context` | chr | `"summary"` | `none`, `names`, `summary` | P07 |
| `record` | chr | `"ask"` | `off`, `ask`, `auto` | P15 |
| `replay` | chr | `"auto"` | | P15 |
| `transcript` | chr | `"ask"` (`"file"`, `"active-document"`, `"off"`); the chosen target is stored in the user-level project file and validated (inside the project, `.R`/`.Rmd`/`.qmd`/`.ipynb`, not a control or protected path; IC-52) | | P15 |
| `plugins` | [chr] | `[]` | | P17 |
| `filters` | [chr] | `[]` | | P02 |
| `skills` | `{paths: [chr], budget: int}` | `{budget: 1500}` | | P17 |
| `mcp` | `{exposure: chr, budget: int, import: [chr]}` | `{exposure: "r", budget: 1500, import: ["claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi"]}` | | P18 |
| `subagents` | `{max_depth, max_active, max_workers, max_cli, max_tasks}` (options `gptr.subagents.<key>` are the same knobs, IC-71) | `{max_depth: 1, max_active: 8, max_workers: null, max_cli: 4, max_tasks: 8}` | | P19 |
| `output_tokens` | int\|null | `null` | | P06 |
| `plot` | `{width, height, res}` | `{width: 768, height: 512, res: 120}` | | P09 |
| `budget` | `{tokens, cost, turns}` | `{tokens: 2000000, cost: 5, turns: null}` per top-level call (IC-66); `null` set explicitly disables a limit | | P06 |
| `cache` | `{ttl: chr}` | `{ttl: "gap"}` | | P07 |
| `compactor` | chr | `"checkpoint"` | | P07 |
| `compact_at` | num\|null | `200000` | | P07 |
| `checkpoint` | chr | `"on"` | | P16 |
| `doc` | `{outputs: lgl, output_lines: int}` | `{outputs: true, output_lines: 12}` | | P15 |
| `cache_commit` | `{s1: lgl, s2: lgl}` | `{s1: true, s2: false}` (C-31) | | P13/P15 |
| `ui` | chr\|null | `null` | | P11 |
| `frontend` | chr\|null | `null` (`console`) | | P14 |
| `store`, `evaluator` | chr | `"jsonl"`, `"r"` (registered `store` and `evaluator` records, IC-69) | | P06, P09 |
| `providers` | `{<id>: {base_url, models, headers, enabled}}` | `{}` (a project `base_url` needs trust and a one-time confirmation) | | P05 |
| `egress` | `{<provider>: "ack"}` | `{}` (user file only) | | P05 |

Plugin settings are `setting` specs (§10.2) stored under their dotted names.

### 11.3 The user-level project file (IC-52)

`R_user_dir("gptr", "config")/projects/<first 16 hex of sha256(path_key(project root))>.json`, written under a
short file lock; never in the project tree, so it cannot arrive by clone:

```json
{"version": 1, "root": "/Users/me/project",
 "permissions": {"allow": ["r(fn:FindNeighbors,FindClusters)"], "ask": [], "deny": []},
 "transcript": {"target": ".gptr/transcripts/gptr-session-20260929-183000.R"},
 "record": {"analysis.R": "auto"}}
```

A legacy `.gptr/settings.local.json` of the same shape contributes only its `permissions.deny`/`ask` entries, and
only in a trusted project; its allow, transcript and record keys are ignored with a notice.

### 11.4 Session files

`<workspace root>/sessions/<YYYYmmddTHHMMSS>_<session id>.jsonl`: the header line (§4.7), then entries (§4.6),
one JSON object per line, appended open-append-close (`file(path, "ab")` opened, written, flushed and closed per
entry or per batch inside `suspendInterrupts()`; no connection outlives a gptr call; IC-59), `persist`-redacted
at ingress, never rewritten (except by an explicit `gptr_scrub(dry_run = FALSE)`, IC-70). The first entry of every
session is `gptr.frozen`. A fork's file is created at its first own message and starts with the copied path (ids
kept, `parentId` re-chained). A resume on a file whose last byte is not LF first appends `"\n"` and a
`gptr.recovered` entry; readers skip any unparsable line with a diagnostic. Lock: directory `<file>.lock/` with a
file `pid` holding the pid and the process creation time, touched every 10 minutes while the session is live; a
lock is stale when `pid_alive()` (ps) is `FALSE` or its heartbeat is older than 24 h.

### 11.5 History-document blocks (D-08; report 14 §3 grammar)

**Markers (R code, and the body of Rmd/qmd chunks):**

```text
BLOCK_OPEN  = ^([ \t]*)# >>> gptr:([0-9a-z]{6,16})(?:[ \t]+(.*))?$
BLOCK_CLOSE = ^([ \t]*)# <<< gptr:([0-9a-z]{6,16})[ \t]*$
HEADER_KV   = ([A-Za-z_][A-Za-z0-9_.]*)=("([^"\\]|\\.)*"|[^ \t]+)
```

Values containing spaces are double-quoted with R escapes. Header keys, in this order when present:

| Key | Required | Meaning |
|---|---|---|
| `model` | yes | canonical `provider/id` that produced the code (System 1: the physical model) |
| `date` | yes | `YYYY-MM-DD` of the last (re)generation |
| `prompt` | yes | `prompt_hash()` of the prompt template (12 hex) |
| `sha` | recommended | first 8 hex of sha256 of the body lines as last written (user-edit detection) |
| `call` | when > 1 | ordinal of the `peter()` call within the statement (pipelines) |
| `tokens` | optional | `<input>/<output>` of the turn |
| `cost` | optional | USD, plain number |
| `session` | recommended | session id |
| `turn` | recommended | turn number in the session |
| `value` | optional | the name designated with `gptr_return()` (replay binds `$value` to it) |
| `fork` | forks | `<parent session id>:<turn>` |
| `plan` | when used | id of the session whose pending plan was consumed |
| `status` | undone blocks | `undone` |
| `args` | when the prompt was interpolated | 8 hex of sha256 of the sorted interpolated `name=value` pairs; part of freshness (IC-45) |
| `kind` | team and fan-out blocks | `team` or `fanout` (IC-47) |
| `children` | team and fan-out blocks | `"<name>:<session id>,..."` (quoted) |

**Body**, in emission order: the code of each successful `r` call with `record = TRUE`, verbatim except that
top-level `gptr_return()` calls and calls of `record = FALSE` members are dropped and top-level `<-` is rewritten to
`=` where safe (IC-48); `## Steer: <text>` and `## Follow-up: <text>` lines for steering delivered during the turn
(excluded from `prompt` and `sha`, IC-49); after each such call that printed something, its output as `#> ` lines (at most `gptr.doc_output_lines` lines of 76 characters,
then `#> ... (N more lines)`), not in Rmd/qmd; `## Decision: <note>` lines; bridge digests
(`#> sh git status --porcelain: exit 0, 6 lines`); artifact references (`#> [app] .gptr/artifacts/<id>/app.R`,
`#> [plot] <path>`); a block whose code needed a secret gets `# gptr: block needs secrets that are not recorded`.
Code passes `code_for_history()` (literal secrets -> `Sys.getenv("NAME")`). Failed executions and plan-mode code
are not recorded (a plan-mode turn gives one `## Plan: <plans path>` line). Overlay-fork turns are wrapped
`local({ ... }, envir = gptr_resume(block = "<block id>")$envir)` (IC-46). Team and fan-out blocks hold one
`## Agent <name> (<model>): <first line>` line per child and, for children with exports, the child's code wrapped
`local({ ... }, envir = gptr_resume(block = "<id>", child = "<name>")$envir)` plus one
`<export> = gptr_resume(block = "<id>", child = "<name>")$envir$<export>` line per export (IC-47). Indentation copies the owning
statement's first line. Ownership: the run of blocks starting at the first non-blank line after the statement
(blank lines between blocks allowed); the k-th call owns the block whose `prompt=` matches, else the one with
`call=k` (then stale). Only top-level calls own blocks (not inside `function`, `\(x)`, `for`, `while`, `repeat`,
`if`, `{}`, or an agent block).

**Formats:**

| Format | Block form |
|---|---|
| `.R` | the markers above directly below the statement |
| `.Rmd` | a separate chunk `` ```{r gptr-<id>} `` directly after the owning chunk (fence and prefix copied), body with the markers, no `#>` lines |
| `.qmd` | a chunk `` ```{r} `` whose first line is `#| label: gptr-<id>`, same body |
| `.ipynb` | a code cell `{"cell_type": "code", "execution_count": null, "id": "gptr-<id>", "metadata": {"gptr": {"id", "model", "prompt", "date", "session", "turn", "value"}}, "outputs": [], "source": [...]}` after the calling cell; keys sorted; indentation copied from the file (Jupyter: 1 space); numbers kept as read (gptr writes no float of its own, so Jupyter's Python repr is preserved; D-158); only `source` and `metadata.gptr` change on rewrite; never written while the notebook is open: in Jupyter the block is shown as the cell output and kept pending until `gptr_doc(path, sync = TRUE)` (IC-50) |
| transcript | `.gptr/transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R`: a header comment (`# gptr session <id> -- started <time>`, `# machine log: <jsonl path>`, `# source() this file to replay ...`), `library(gptr)`, then the first prompt as `s_<6 hex> = peter("...")` and later prompts as `s_<6 hex> \|> peter("...")`, each with its block (IC-49); direct R lines under `# direct R (no model)` with `#>` output; slash commands as comments (`# /model opus`) |

**Undone blocks** (G7 §3.8): header `status=undone`, every body line prefixed `#~ `; Rmd/qmd chunks get
`eval=FALSE` (`#| eval: false`); ipynb `metadata.gptr.status = "undone"` plus `#~ ` source lines. A top-level System 1
statement gets a one-line block: `#> gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0, 2026-09-29)` (choices:
`#> gptr_choice: liver 8, lung 5, other 2 (...)`; scores: `#> gptr_score: mean 1.4 (...)`).

### 11.6 Artifacts (§5.7 of `03`)

```text
<root>/artifacts/<id>/app.R                 working copy (model-written; committed)
<root>/artifacts/<id>/artifact.json         metadata (committed)
<root>/artifacts/<id>/vNNN/app.R            immutable snapshot copy (NNN = 001, 002, ...)
<root>/artifacts/<id>/vNNN/R/gptr_data.R    loader: reads data/<file> for each name listed in artifact.json (IC-63)
<root>/artifacts/<id>/vNNN/data/001.rds     snapshots via save_rds(compress = FALSE), numbered (ignored)
<root>/artifacts/<id>/run/run.json          {pid, port, url, version, started} (ignored; the URL carries the token)
<root>/artifacts/<id>/run/port              the child's port, published by atomic rename (ignored)
<root>/artifacts/<id>/run/app-vNNN.log      child stdout/stderr read by the parent and appended with persist redaction (ignored; IC-70)
```

`artifact.json`: `{"id", "title", "kind": "shiny" | "html", "versions": [{"n", "created", "app_sha",
"data": [{"name", "file", "class", "dim", "bytes"}], "session", "checks": {"parse", "launch", "http", "session"}}],
"current": int, "port": int | null, "created", "updated"}`. Ids match `^[a-z0-9][a-z0-9-]{0,62}$` and are not a
Windows reserved device name (`con`, `aux`, `nul`, `prn`, `com1`-`com9`, `lpt1`-`lpt9`; IC-63).

### 11.7 `mcp.json` (user and trusted project)

```json
{"mcpServers": {
   "github": {"url": "https://api.githubcopilot.com/mcp/", "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"},
              "exposure": "r", "toolExposure": {"delete_*": "hidden", "search_code": "direct"}, "timeout": 60},
   "sqlite": {"command": "uvx", "args": ["mcp-server-sqlite", "--db-path", "${workspaceFolder}/data.db"],
              "env": {"LOG_LEVEL": "info"}, "timeout": 120, "protocol": "auto"},
   "old": {"enabled": false}},
 "defaults": {"exposure": "r", "timeout": 60, "protocol": "auto"}}
```

Entry fields: `command` (stdio) or `url` (HTTP) (`type` optional; `"sse"` is refused with an actionable error),
`args`, `env`, `headers`, `cwd`, `timeout` (seconds), `protocol` (`auto`, `modern`, `legacy`), `exposure`,
`toolExposure` (glob -> exposure), `enabled`, `trusted` (user file only: trusts the server's annotations),
`oauth` (`{clientId, scope, callbackPort}`). Placeholders `${VAR}`, `${VAR:-default}`, `${env:VAR}`,
`${workspaceFolder}`, `${userHome}` (= `user_home()`, IC-63) are expanded at connect time, never when loading; expanded secret-like values
are registered. The internal spec (kind `mcp_server`) adds `name`, `transport`, `source` (`gptr:user`,
`gptr:project`, `<harness>:<scope>`), `also_in`.

### 11.8 Credential store, trust and egress

`R_user_dir("gptr", "config")/auth.json` (file 0600, directory 0700 on Unix; the Windows ACL caveat is
documented), written under a lock with umask 077 [G6 §3.10]:

```json
{"anthropic":  {"type": "api_key", "keyring": {"service": "gptr", "username": "anthropic"}},
 "openrouter": {"type": "api_key", "key": "<value>"},
 "mcp:github": {"type": "oauth", "issuer": "https://auth.example.com", "client_id": "...", "expires": 1759100000000,
                "keyring": {"service": "gptr", "username": "mcp:github:refresh"}}}
```

Every value read is registered in the vault at once; access tokens stay in memory. `trust.json`:
`{"version": 1, "projects": {"<path_key of the project root>": {"trusted": true, "date": "2026-09-29",
"fingerprint": "<sha256 of the trust-gated files>", "base_url_confirmed": {"<provider>": "<url>"}}}}` (IC-52;
written under a short file lock). Egress acknowledgements live in the user `settings.json`
under `egress` (§11.2).

### 11.9 Caches and their keys

| Cache | Location | Key | Value |
|---|---|---|---|
| System 1 (P13) | memory (`the$s1_cache`) before a workspace; then `<root>/cache/s1/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 2L, salt, endpoint, model, question, type, criteria, input)))` per element (`salt` from `cache/s1/salt`; `input` = the state; alias models keyed by the alias string) | `{"key", "model" (physical), "alias", "question_sha256", "input_hash" (salted), "answer", "prob", "probabilities", "confidence", "date", "usage": {"input_tokens", "output_tokens"}}`; never the input or the question text (IC-70); mtime touched on hit |
| System 2 answers (P15) | `<root>/cache/s2/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 2L, doc = <path relative to root>, block = <id>, part = <"" \| child name \| "n<ordinal>">, prompt = <prompt hash>, args = <args hash or "">)))` (IC-45, IC-47) | `{"block", "doc", "part", "prompt", "model", "answer" (redacted final text), "usage", "cost", "session", "turn", "date"}` |
| Spill files (P01) | `<root>/cache/tmp/gptr-output-<id>.txt` | the out id | redacted full text |
| Deferred document writes (P15) | `<root>/cache/tmp/pending-<sha1(path_key(doc path))>.rds` | document path | `list(doc, base_md5, upserts = list(list(block_id, lines, site)), session, pid, time)` (IC-51); never pruned automatically |
| Model catalog (P05) | `R_user_dir("gptr", "cache")/models.json`, `models.etag` | ETag | the refreshed catalog (§11.10 shape) |
| MCP tool lists (P18) | `R_user_dir("gptr", "cache")/mcp-tools/<hash>.json` | `hash_sha256(canonical_json(command + args, or URL origin + path))` | `{"tools", "fetched_at", "ttl_ms", "cache_scope"}` (not stored when `cacheScope` is `private` and credentials are not the user's own) |
| MCP era (P18) | `R_user_dir("gptr", "cache")/mcp-era/<hash>.json` | as above | `{"era": "modern" \| "legacy", "version", "date"}`, 7-day expiry |
| Serialised entries (P06/P07) | memory (`live$memo`) | `<entry id>\|<api>\|<same model>\|<caps hash>` | the entry's JSON text for that api |
| Object sizes (P09) | memory | `<address>\|<length>\|<class>` | `object.size()` |

### 11.10 `inst/extdata/models.json.gz` (P05)

```json
{"schema_version": 1, "generated": "2026-09-29", "source": "models.dev (MIT) + gptr overrides",
 "providers": {"anthropic": {"api": "anthropic-messages", "base_url": "https://api.anthropic.com",
                             "env": ["ANTHROPIC_API_KEY"], "compat": {}, "local": false}},
 "models": [{"provider": "anthropic", "id": "claude-sonnet-5-5", "name": "Claude Sonnet 5.5",
             "family": "claude-sonnet", "release_date": "2026-08-01", "context": 1000000, "max_output": 64000,
             "reasoning": true, "thinking_levels": ["off", "low", "medium", "high", "xhigh", "max"],
             "input": ["text", "image", "pdf"], "tool_call": true, "structured_output": true,
             "prices": [{"from": "2026-08-01", "tier": "default", "input": 2, "output": 10, "cache_read": 0.2,
                         "cache_write_5m": 2.5, "cache_write_1h": 4}],
             "cache_min": 1024, "capabilities": {"mid_system": true, "tool_addition": true},
             "status": "active"}],
 "aliases": {"sonnet": {"provider": "anthropic", "family": "claude-sonnet"},
             "opus": {"provider": "anthropic", "family": "claude-opus"},
             "haiku": {"provider": "anthropic", "family": "claude-haiku"},
             "gemini": {"provider": "google", "family": "gemini-pro"},
             "flash": {"provider": "google", "family": "gemini-flash"},
             "gpt": {"provider": "openai", "family": "gpt"},
             "jev": {"ref": "typesafe/jev-latest"},
             "claude_code": {"ref": "claude-cli/default"},
             "codex": {"ref": "codex/default"}}}
```

(Values shown are illustrative except the structure.) A family alias resolves to the newest `active` model of the
family by `release_date`; `claude-cli/default` and `codex/default` resolve through the CLI provider's `status()` to
a full id before any invocation (CLI invocations always receive full ids). Merge order: snapshot < cache <
overrides < user config `providers.*.models` < live discovery of local servers.

### 11.11 Worker protocol (P19; 15 §3.6)

Spec file (written with `save_rds()`): `list(prompt, model, mode, depth, agent = <spec:agent>, objects = named
list (values shipped by name), export = chr, preset, rng_state, settings = list, env_profile = "worker", registry =
list(specs, plugins, filters))` (IC-69; the worker re-registers `registry` before running). The
child runs `worker_main(spec_path, result_path)`; stdout carries one JSON object per line (the `jsonl` frontend:
events with Pi names plus `{"type":"ask","id","questions"}`, `{"type":"permission_request","id","request"}`,
`{"type":"result","status","text","usage","turns"}`); stdin carries `{"type":"answer","id","answers"}`,
`{"type":"permission","id","decision","feedback"}`, `{"type":"cancel"}`. Exported objects come back through
`result_path` (`save_rds()`), never the JSON stream. Non-JSON stdout lines are ignored.

### 11.12 Plugins: manifest and package fields [stable]

`inst/gptr/plugin.json` (packages) or `plugin.json` (directories):

```json
{"name": "gptrpanel", "version": "0.1.0", "description": "Reviewer panels and trial lookups",
 "gptr": {"api": ">= 1.0, < 2"},
 "skills": "skills", "prompts": "prompts", "agents": "agents", "mcpServers": "mcp.json",
 "extension": {"entry": "gptrpanel::gptr_plugin", "activation": "lazy",
               "provides": {"tool": ["trials/search"], "command": ["panel"], "hook": ["tool_result"]},
               "declarations": {"trials/search": {"signature": "search(condition: string)",
                                                  "description": "Search ClinicalTrials.gov for recruiting trials"}}},
 "rDepends": ["ggplot2 (>= 3.5)"]}
```

`entry` names an exported function (`getExportedValue()`); directory plugins use `extensions/*.R` files whose last
expression is `function(gptr)`. `DESCRIPTION`: `Config/gptr/plugin: true`, `Config/gptr/api: >= 1.0, < 2`; gptr in
`Imports` (SDK users) or `Suggests` (describers, skills only); `NAMESPACE` exports the factory and registers
`S3method(gptr::gptr_describe, <cls>)`/`S3method(gptr::gptr_preimage, <cls>)` as delayed methods. Hidden files are
not used (`mcp.json`, not `.mcp.json`). `.claude-plugin/plugin.json` bundles are consumed unmodified for `skills/`,
`commands/` (as prompt templates `/<plugin>:<cmd>`), `agents/` (tool-name map) and `.mcp.json` (placeholders
`${CLAUDE_PLUGIN_ROOT}`, `${GPTR_PLUGIN_ROOT}`); hooks are v1.x.

### 11.13 Frontmatter of skills, agents and templates

| File | Required | Optional |
|---|---|---|
| `SKILL.md` | `name` (= directory name, `^[a-z0-9][a-z0-9-]*$`), `description` (<= 1,024 characters; catalog shows at most 160) | `disable-model-invocation`, `allowed-tools`, `license`, `metadata` |
| agent `.md` (`.gptr/agents`, `.claude/agents`, `.codex/agents`, `.pi/agents`, `inst/gptr/agents`) | `name`, `description` | `model` (alias or ref), `tools` (comma list or array; mapped by `tool_name_map()`), `skills`, `backend`, `preset`, `max_turns`, `mode`, `returns`; body = the agent's system text |
| prompt template `.md` | - (name = file name) | `description`, `argument-hint`, `model`, `allowed-tools` (Claude commands) |

YAML is parsed with `yaml::yaml.load()` and a lenient fallback for unquoted values containing colons; failures are
diagnostics, never errors.

### 11.14 Checkpoint store (P16; G7 §3.3)

```text
<root>/checkpoints/blobs/<2hex>/<xxh128>[.gz]        file contents (gzip level 1), shared by the project's sessions
<root>/checkpoints/objects/<session id>/<key>.rdsx   spilled object images (serialize_leaf(ascii = FALSE, xdr = FALSE))
<root>/checkpoints/index.json                        {"blobs": {"<hash>": <last referenced epoch>}}; rebuilt if missing
```

Records live in the session log (`gptr.checkpoint`, `gptr.rewind`, §4.6). Never inside `.git`, never in
`R_user_dir()`.

### 11.15 Risk tables (P11)

`inst/extdata/risk-functions.csv`: columns `package`, `function`, `level` (0-4), `category` (`read`, `object_write`,
`file_write`, `file_delete`, `network`, `process`, `install`, `dynamic`, `session`, `secret`, `interactive`,
`critical`, `control` (IC-53)), `path_arg` (the argument holding a path, or empty), `note`; plus a `packages` table
of risky packages whose unlisted functions are at least level 2 (IC-54). An unlisted function of a package outside
base, stats, utils, methods, graphics, grDevices and tools is level 1. `inst/extdata/risk-commands.csv`:
`command`, `subcommand` (or `*`), `level`, `category`, `note` (G5 levels). Plugins and users extend both through
additive `risk_rule` records (§10.2 row 33; the highest level wins on duplicates, lowering needs `lower = TRUE`).

### 11.16 Templates (P08)

`inst/templates/vignette.Rmd`: an R Markdown document with a YAML header (`title: "Project instructions"`,
`output: html_document`), a first line `@AGENTS.md` comment hint (as an HTML comment), and sections "Data",
"Conventions", "Do not" with placeholder bullets; it contains no executable chunks. `inst/templates/settings.json`:
`{"version": 1, "mode": "manual", "record": "ask"}`.


---

## 12. The fake provider and shared test infrastructure

Every plan tests model behaviour with the fake provider and the helpers below; none writes its own fake, mock
server or tracemem harness (D-24, INFRA-24).

### 12.1 `gptr_fake_provider()` (P01) — script grammar (IC-21)

```r
gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))
```

The returned spec is `structure(list(kind = "provider", name = name, id = name, api = "fake" (or
"fake-classifier"), type = type, base_url = NULL, auth = NULL, local = TRUE, models = list(<one model record,
ref "<name>/<name>-1" (chat) or "<name>/<name>-s1" (classifier), context 200000, max_output 8192, reasoning TRUE,
input c("text", "image"), tool_call TRUE, zero prices>), compat = list(), headers = list(), aliases = character(),
offline = TRUE, script = script, log = <environment>, api_version = "1.0"), class = c("gptr_provider", "gptr_spec"))`. It is local (no
egress acknowledgement, no key) and deterministic (no RNG, no clock-dependent output except `delay`/`gap`).

**Chat scripts.** `script` is a list of replies (request `i` gets element `min(i, length(script))`: the last reply
repeats) or a `function(request)` returning one reply. `request` is `list(n = int(1), model = chr(1), system =
list(t0, t1), tools = chr (direct tool names), messages = list(<msg>) (projected), last_user = chr(1) (text of the
last user message), last_results = list(<tool_result msg>) (of the last turn), params = list)`. Every request is
appended to `spec$log$requests` (the log is an environment shared by copies of the spec). A reply is:

| Form | Effect |
|---|---|
| `chr(1)` | one text block, `stop_reason = "stop"` |
| `list(text = chr(1))` | the same |
| `list(thinking = chr(1), signature = chr(1))` | a thinking block (before any text) |
| `list(tool = chr(1), input = named list, id = chr(1))` | one tool call (`id` default `fake_<n>_1`), `stop_reason = "tool_use"` |
| `list(tools = list(list(name, input), ...))` | parallel tool calls in order |
| `list(stop = "length" \| "refusal" \| "pause" \| "stop")` | overrides the stop reason (a tool call with `length` is truncated: its arguments are incomplete JSON) |
| `list(error = chr(1), status = int(1), after = int(1))` | an `error` terminal event after `after` text deltas (`after = 0`: before any delta, which the agent retries as transient when `status` is 408/409/429/5xx/529) |
| `list(overflow = TRUE)` | an error whose message is `prompt is too long: <n> tokens > <window> maximum` (classified as context overflow) |
| `list(hang = TRUE)` | starts and never finishes until aborted (timeout and abort tests) |
| `list(json = <any>)` | the structured final answer for `.opts$returns` (serialised as the text) |
| modifiers `delay` (seconds before `start`), `gap` (seconds between deltas), `chunk` (characters per text delta; default 16), `usage` (a §4.3 usage list; default: `est_tokens()` of the request and the reply) | combine with any form above |

**Classifier scripts** (`type = "classifier"`): a list of answers per question (recycled like chat replies) or
`function(state, question)` where `question = list(id, type = "noul" | "choice" | "score", instructions,
criteria)`. An answer is `num(1)` (P(yes)) for `noul`, a named numeric vector of probabilities over the choices for
`choice`, a numeric vector of level probabilities for `score`, or `list(error = chr(1), status = int(1))`. The
fake reports `model_version = "<name>-s1-1.0"`, engine `"fake"`, `calibrated = TRUE`.

```r
fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "n = nrow(d)", note = "count rows")),
  "There are 32 rows."))
e = new.env(); e$d = mtcars
s = peter("Count the rows of d", model = fake, envir = e, mode = auto,   # no human: auto avoids a blocked ask
         .opts = list(context = "names"))
e$n
fake$log$requests[[2]]$last_results
```

### 12.2 Test helper files (all under `tests/testthat/`)

| File (owner) | Functions |
|---|---|
| `setup.R` (P01) | §3.2 environment: redirected `R_USER_*_DIR`, `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME`, `GPTR_PROJECT_ROOT` (a temporary project, IC-63), blank keys, `GPTR_REPLAY=replay`, `OMP_THREAD_LIMIT=2`, `options(gptr.interactive = FALSE, gptr.quiet = TRUE)` |
| `helper-fake.R` (P01) | `fake_text(text, ...)`; `fake_tool(name, ..., .text = NULL, .id = NULL)` (a reply calling tool `name` with input `list(...)`); `fake_tools(...)` (each argument `list(name, input)`); `fake_error(message = "overloaded", status = 529L, after = 0L)`; `local_fake_provider(script, name = "fake", type = "chat", .env = parent.frame())` (registers with `gptr_register()` and unregisters on exit; returns the spec); `fake_requests(spec)` (the request log); `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())` (a temporary project directory made the working directory with `withr::local_dir()`, a `.gptr/` skeleton created directly (no dependency on `gptr_init()`), `files` = named list of relative path -> content, `trust = TRUE` records trust in the redirected user config; returns the path); `local_gptr_options(..., .env = parent.frame())` (`withr::local_options()` with `gptr.` prefixed names) |
| `helper-tracemem.R` (P01) | `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)`: writes a script that loads gptr (`library(gptr)` when installed, else `pkgload::load_all()` of the source tree; that call exists only in the generated script text, never as package or test code, IC-71), evaluates `setup` (chr: code creating `object`, e.g. `big = runif(5e6)`), `tracemem(object)` with output to a file, `action` (chr: the gptr code under test; with `in_run_edit = TRUE` the fake provider's `r` call runs `edit` inside the run, IC-41), then `edit`; runs it with `c(rscript_path(), "--vanilla", <script>)` through processx (IC-60); counts `tracemem[` lines after `action`; passes when the count is at most `allow`; skips on CRAN and when `!capabilities("profmem")`; returns the count invisibly |
| `helper-mock-server.R` + `fixtures/mock_server.R` (P01) | `local_mock_server(scenario, ..., .env = parent.frame())` -> `list(url, port, log = function() df(time, method, path, headers (redacted), body, disconnected), stop = function(), provider = <spec:provider with offline = TRUE>)`; a base-R `serverSocket()`/`socketSelect()` server run with `rscript_path()` through processx; it listens on every interface (base R has no host argument), so it answers only paths carrying a per-run token and lives for one test; skips on CRAN (IC-71). The returned provider record is `offline = TRUE` so `GPTR_REPLAY=replay` does not block it (IC-45). Scenarios: `stream` (Anthropic-shaped SSE: `n = 12` text events every `interval = 0.25` s), `slow`, `ttft` (`delay` before the first byte), `hold_headers`, `stall` (events then silence), `bytes_per_10s` (`duration`), `overload` (an overloaded SSE `error` event before the first delta, then success after `attempts`), `status` (`status`, `body`, optional `retry_after`, `succeed_after`), `spend_cap`, `truncated` (connection closed mid-stream), `parallel_tools`, `openai_responses`, `chat_completions`, `gemini` (per-adapter stream shapes, P12), `systemone` (JSON answers from `answers = function(body)`), `json` (a fixed body), `redirect` (a 307 to a second origin that logs any key bytes, IC-64) |
| `helper-arch.R` (P01) | `arch_layer_table()` -> df(`file`, `layer`) from §3.2 of `03`; `arch_fun_map()` -> df(`fun`, `file`) built by parsing the files under `R/` (found through `testthat::test_path("..", "..", "R")` or the check directory's `00_pkg_src`; the test skips with a message when absent); `arch_allowed()` -> the `03` §2.2 matrix; `arch_kernel_sdk()` -> the IC-33 allowlist; `arch_services()` -> the §7.0 service table (literal `ext_service_get("<name>")` calls are mapped to the providing plan; an undeclared name fails) |
| `helper-scripted-ui.R` (P11) | `local_scripted_ui(answers = list(), .env = parent.frame())` -> an environment with `log` (df `method`, `prompt`, `answer`) and `remaining()`; registers a `scripted` UI, sets `options(gptr.ui = "scripted", gptr.interactive = TRUE)`. Queue items: for `permission()`: `"y"`, `"a"` (always, session), `"p"` (always, project), `"n"`, `list(decision = "deny", feedback = chr(1))`, `"abort"`; for `select()`: int; for `input()`: chr(1); for `questions()`: a named list |
| `helper-mcp-server.R` + `fixtures/mcp/server.R` (P18) | `local_mcp_fixture(era = c("modern", "legacy"), transport = c("stdio", "http"), tools = c("echo", "add", "slow", "fail", "elicit"), n_extra = 0L, .env = parent.frame())` -> `list(spec, log = function() df, stop = function())`; a pure-R server speaking the chosen era; `n_extra` adds generated tools (catalog budget tests) |

### 12.3 Test files every plan inherits

- **Copy suites** (`test-copy-<area>.R`): one `expect_no_copy()` row per tagged entry point (§1.3); areas and owners in
  §3.4 of `03`. Each row states `setup`, `action`, `edit`.
- **Lint rules** (`test-lint-rules.R`, P01): scans `R/` for `:::`, non-ASCII bytes, `rlang::enquo`/`enquos`/`quo`,
  `cli_*()`/`glue` calls with a non-literal first argument, `.GlobalEnv`, `lockBinding`/`unlockBinding`,
  `processx::run(`, `serialize(`/`saveRDS(` without `ascii = FALSE` outside `utils-paths.R`, `<-` assignments
  (found as `LEFT_ASSIGN` tokens through `getParseData()`, not by a text regex, IC-72), `<<-` outside closures
  updating enclosing-function state, `%>%`, calls to `askYesNo(`, `menu(` or `select.list(` (gptr's own prompts use
  the UI kind), `Sys.setenv(` outside `auth-dotenv.R`, `set.seed(`, `sample(`, `runif(`, `RNGkind(` anywhere (ids
  and jitter are RNG-free), `.Random.seed` assignment outside `rng_swap()` and `with_seed_preserved()`,
  `httpuv::randomPort(`, `tools::pskill(`, `enc2utf8(` outside `utils-encoding.R`, `withr::` in `R/`, and a bare
  `"R"` or `"Rscript"` command passed to `proc_spawn()`/`proc_run()` (IC-60, IC-61, IC-62, IC-72).
- **Architecture** (`test-arch-layers.R`, P01): §2.2 of `03` rule 4.
- **Golden events**: fixtures store events without the volatile fields `ts`, `session`, `run`, `request_id`;
  comparisons use `expect_equal()` on the JSON-decoded lists.

### 12.4 Fixture directories

| Directory | Owner | Content |
|---|---|---|
| `fixtures/tokens/` | P01 | 12 content-class samples of G2's corpus, `counts.json` (o200k counts) |
| `fixtures/oracles/report02/` | P06 | report 02's 24 loop, 42 store and 26 recovery checks as JSON |
| `fixtures/bench/prefix-baseline.json` | P07 | `{"preset": {"minimal": 1262, "standard_core": 2335, "standard_all": 2813, "standard_interactive": 2956}, "sections": {...}, "estimator": "..."}` (IC-68) |
| `fixtures/sse/<api>/<case>.sse`, `.events.json`, `.message.json` | P12 | raw stream bytes; golden events; final message (thinking, redacted thinking, encrypted reasoning, parallel tools, overload, truncation) |
| `fixtures/jev/<case>.json` | P13 | `{"request": {...}, "status": 200, "response": {...}}` in the 04a shapes |
| `fixtures/docs/<case>.{R,Rmd,qmd,ipynb}` + `<case>.expected.*` | P15 | documents before and after block writes (CRLF, BOM, missing final newline, Python-written floats) |
| `fixtures/oracles/pi-templates/` | P17 | Pi's 67 template tests |
| `fixtures/mcp/` | P18 | the fixture server and era message examples |
| `fixtures/cli/claude-<case>.ndjson`, `codex-<case>.jsonl` | P20 | redacted CLI transcripts; `inst/gptr/fixtures/fake_cli.R` replays them as a fake `claude`/`codex`, run as `c(rscript_path(), fake_cli)` through `gptr.cli_path` with `offline = TRUE` provider records (IC-60, IC-45) |
| `dev/bench/tokens/` NS-2 and NS-3 golden transcripts and runner | P07 (IC-73) | other NS fixtures added by P10, P13, P15, P18, P19, P22, P23, P24 |


---

## 13. Reconciliation with `03-architecture.md` and `05-plan-decomposition.md`

The following edits were made to `03` and `05` on 2026-09-30 so that the three documents agree. Each is the
consequence of an IC decision (§0.3).

| Where | Before | After | Decision |
|---|---|---|---|
| `03` header, `05` header | "`04-interface-contract.md` (written next)" | the contract named as authoritative for interfaces; its §13 lists these edits | - |
| `03` §3.2 `ext-specs.R` | "the kind table and validators (30 kinds, §11.1)" | "30 kinds here: §11.1 minus `interpreter`, plus `route`; P22 adds `interpreter`, 31 in all" | IC-02 |
| `03` §3.2 `provider-registry.R` | builtin `providers` | + `provider_stream()`; declares `builtin:fake` | IC-08 |
| `03` §3.2 `provider-usage.R`, `session-budget.R` | `gptr_usage()` in `provider-usage.R` | in `session-budget.R` | IC-05 |
| `03` §3.2 `session-object.R` | "... print/format/summary/`knit_print` ..." | `knit_print` is P15's | IC-07 |
| `03` §3.2 `agent-dispatch.R`, `perm-gate.R`, §6.8.2 | combination in `perm-gate.R` | `perm_check()` combination in `agent-dispatch.R`; built-in policies in `perm-gate.R` | IC-04 |
| `03` §3.2 `gptr-gateway.R` | no built-in | `builtin:gateway` (routes `nested`, `continue`, `new`; core settings) | IC-24 |
| `03` §3.2 `gptr-config.R`, `perm-rules.R` | "`gptr_permissions()` storage" in `gptr-config.R` | settings I/O plus `replay_mode()`/`replay_guard()` in `gptr-config.R`; `gptr_permissions()` in `perm-rules.R` | IC-06 |
| `03` §3.2 `doc-replay.R` | "replay modes" | "replay decisions (the mode is resolved by `replay_mode()`, P08)" | §7.8 |
| `03` §3.2 `ckpt-objects.R` | - | the exported `gptr_preimage()` generic | IC-01 |
| `03` §4 intro, §4.3, §4.4, §13 | 62 exports; Agent-side (6) | 63 exports; Agent-side (7) with `gptr_preimage` | IC-01 |
| `03` §4.3 signatures | `gptr_fake_provider(script, name = "fake")`; `gptr_context_block(..., budget = 300L)`; `gptr_env(..., set_env = TRUE, ...)` | `type = c("chat", "classifier")`; `order = 650L`; `set_env = getOption("gptr.env_export", TRUE)` | IC-21, IC-22 |
| `03` §5.4, §10.1 | `session_end`, `pre_compact`, `post_compact` | `session_shutdown`, `session_before_compact`, `session_compact`; `session_before_fork` added | IC-03 |
| `03` §5.10 | the API-version field unnamed | `api_version` | IC-23 |
| `03` §6.9.1 | tree without `extensions/`, `plugins/`, `locks/` | added | IC-18 |
| `03` §7.3 section catalogue | no `plugins` section | `plugins` row (T1) | IC-25 |
| `03` §11 intro, §11.1 | "30 kinds"; no route row | "31 kinds"; a "Gateway routes" row | IC-02 |
| `05` P01 | fake provider signature; helper names; lint list | `type =`, `offline = TRUE`; the §12.2 helper names and mock scenarios; "the further rules of contract §12.3" | IC-21 |
| `05` P02 | "the 30 kinds" | the 30 kinds of `ext-specs.R`; `ctx` members bound through P01's service table | IC-02, IC-09 |
| `05` P05 | `gptr_usage()` in `provider-usage.R` | removed; `provider_stream()` and the `builtin:fake` declaration added | IC-05, IC-08 |
| `05` P06 | "`knit_print` stub registration"; gate via policies | removed; `gptr_usage()` in `session-budget.R`; `perm_check()` in `agent-dispatch.R`; `run_eval_env()` plan-mode overlay | IC-04, IC-05, IC-07, IC-15 |
| `05` P08 | "rule storage behind `gptr_permissions()`" | settings I/O; `replay_mode()`, `replay_guard()`; `builtin:gateway` | IC-06, IC-24 |
| `05` P11 | `perm-gate.R` "policy combination ... non-interactive stop" | "the built-in policies" | IC-04 |
| `05` P15 | "replay modes, forced replay under check" | "replay decisions per mode (the mode comes from P08's `replay_mode()`)" | §7.8 |
| `05` P16 | "the `gptr_preimage()` generic" | "the exported `gptr_preimage()` S3 generic" | IC-01 |
| `05` P25 | "all 62 exports" | "all 63 exports" | IC-01 |
| `05` dependency graph and table, P05/P13/P19/P20 "Depends on" | `P02, P03 -> P05`; `P08, P12 -> P13`; `P11, P17 -> P19`; `P18, P19 -> P20` | `P02, P03, P04 -> P05`; `P08, P09, P12 -> P13`; `P11, P14, P17 -> P19`; `P12, P18, P19 -> P20` | IC-28 |
| `03` §3.2 `utils-options.R`; `05` P01, P02 | service table unowned (P02 scope) | service table and `setting_get()` in `utils-options.R` (P01) | IC-09 |
| `03` §3.2 `provider-registry.R`; `05` P05 | "egress check" in `provider-registry.R` | removed (P08's `egress_check()`) | IC-29 |

The review round of 2026-09-30 (§15, IC-32..IC-73) edited `03`, `05`, `01-decision-register.md` (D-28 now says
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
| `05` P01-P25 | scopes and acceptance per the decisions above; P17 depends on P10; P19's CLI leg moved to P20; P25 adds `VignetteBuilder` | IC-36, IC-72, IC-73 |

---

## 14. Plans (as in `05` after the §13 edits; ownership per §3.2 of `03` as amended in §13)

| Plan | Title | Milestone | Depends on | Owns (R files) |
|---|---|---|---|---|
| P01 | Foundation | M0 | - | `aaa-state.R`, `utils-*.R` (7), `json-*.R` (3), `provider-message.R`, `provider-events.R`, `provider-fake.R`, `zzz.R` |
| P02 | Extension API and registry | M0 | P01 | `ext-registry.R`, `ext-specs.R`, `ext-api.R`, `ext-events.R`, `ext-load.R`, `ext-check.R`, `ext-builtins.R` |
| P03 | Secrets and redaction | M0 | P01, P02 | `auth-secrets.R`, `auth-redact.R`, `auth-dotenv.R`, `auth-store.R`, `auth-childenv.R` |
| P04 | Reactor and process engine | M0 | P01, P03 | `proc-spawn.R`, `proc-supervise.R`, `http-reactor.R`, `http-request.R`, `http-sse.R`, `http-retry.R` |
| P05 | Model layer core | M1 | P02, P03, P04 | `provider-transform.R`, `provider-registry.R`, `provider-usage.R`, `catalog-models.R` |
| P06 | Session kernel and agent loop | M1 | P04, P05 | `session-object.R`, `session-live.R`, `session-store.R`, `session-budget.R`, `agent-loop.R`, `agent-run.R`, `agent-dispatch.R` |
| P07 | Prompt, context, caching and compaction | M1 | P06 | `prompt-sections.R`, `prompt-text.R`, `prompt-context.R`, `prompt-cache.R`, `prompt-compact.R` |
| P08 | Gateway and SDK | M1 | P03, P07 | `gptr-gateway.R`, `gptr-capture.R`, `gptr-sdk.R`, `gptr-config.R` |
| P09 | Evaluator and workspace | M2 | P08 | `eval-core.R`, `eval-plots.R`, `eval-guard.R`, `eval-format.R`, `env-snapshot.R`, `env-describe.R`, `env-history.R`, `env-probe.R` |
| P10 | Tools and the `peter$` namespace | M2 | P09 | `tool-namespace.R`, `tool-r.R`, `tool-read.R`, `tool-write.R`, `tool-edit.R`, `tool-diff.R`, `tool-walk.R`, `tool-search.R` |
| P11 | Permissions, UI and plan mode | M2 | P10 | `perm-classify.R`, `perm-rules.R`, `perm-gate.R`, `perm-plan.R`, `console-ui.R`, `tool-ask.R` |
| P12 | Native provider adapters | M2 | P05, P07 | `provider-anthropic.R`, `provider-openai-responses.R`, `provider-openai-completions.R`, `provider-google.R` |
| P13 | System 1 | M2 | P08, P09, P12 | `s1-types.R`, `s1-client.R`, `s1-route.R`, `s1-cache.R`, `s1-emulate.R` |
| P14 | Console and front ends | M3 | P08, P11 | `console-repl.R`, `console-render.R`, `console-interrupt.R`, `console-commands.R`, `console-jsonl.R` |
| P15 | Documents and replay | M3 | P08, P10 | `doc-locate.R`, `doc-blocks.R`, `doc-io.R`, `doc-formats.R`, `doc-replay.R`, `doc-knitr.R` |
| P16 | Checkpoints and rewind | M3 | P11, P15 | `ckpt-objects.R`, `ckpt-files.R`, `ckpt-rewind.R` |
| P17 | Skills, templates, agent files and plugins | M3 | P08, P10 | `skill-discover.R`, `skill-templates.R`, `subagent-defs.R`, `ext-plugins.R` |
| P18 | MCP and OAuth | M4 | P10, P11 | `mcp-client.R`, `mcp-config.R`, `mcp-namespace.R`, `mcp-server.R`, `auth-oauth.R` |
| P19 | Sub-agents | M4 | P11, P14, P15, P17 | `subagent-backends.R`, `subagent-team.R`, `subagent-worker.R` |
| P20 | Subscription CLI providers | M4 | P12, P18, P19 | `cli-common.R`, `cli-claude.R`, `cli-codex.R` |
| P21 | Background sessions (experimental) | M4 | P06, P14 | `agent-background.R` |
| P22 | Polyglot bridges | M5 | P10, P11 | `bridge-sh.R`, `bridge-lang.R` |
| P23 | Artifacts | M5 | P10, P11, P14, P16 | `artifact-app.R`, `artifact-registry.R` |
| P24 | Token benchmark and end-to-end acceptance | M5 | P01-P23 | none (`dev/bench/`, e2e tests) |
| P25 | Release | M5 | P24 | none (docs, vignettes, release files) |

### 14.1 Where each export lives

| Plan | Exports |
|---|---|
| P01 | `gptr_fake_provider` |
| P02 | `gptr_api`, `gptr_register`, `gptr_registry`, `gptr_reload`, `gptr_check`, `gptr_tool_result`, `gptr_spec`, `gptr_tool`, `gptr_provider`, `gptr_adapter`, `gptr_router`, `gptr_hook`, `gptr_policy`, `gptr_agent`, `gptr_command`, `gptr_prompt_section`, `gptr_context_block`, `gptr_backend` |
| P03 | `gptr_env`, `gptr_redact`, `gptr_scrub` |
| P04 | `gptr_jobs` |
| P05 | `gptr_providers`, `gptr_models` |
| P06 | `gptr_fork`, `gptr_sessions`, `gptr_resume`, `gptr_last`, `gptr_usage` |
| P07 | `gptr_prompt` |
| P08 | `peter`, `gptr_init`, `gptr_config`, `gptr_trust`, `gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_on`, `gptr_return` |
| P09 | `gptr_describe` |
| P11 | `gptr_permissions`, `gptr_risk` |
| P13 | `gptr_prob` |
| P15 | `gptr_doc`, `gptr_source`, `gptr_blocks`, `gptr_cache` |
| P16 | `gptr_rewind`, `gptr_checkpoints`, `gptr_preimage` |
| P17 | `gptr_skills`, `gptr_agents`, `gptr_plugins` |
| P18 | `gptr_login`, `gptr_logout`, `gptr_mcp`, `gptr_mcp_add`, `gptr_mcp_remove`, `gptr_mcp_serve` |
| P19 | `gptr_parallel` |
| P23 | `gptr_artifacts` |

Total (IC-36): 1 + 18 + 3 + 1 + 2 + 5 + 1 + 10 + 1 + 2 + 1 + 4 + 3 + 3 + 6 + 1 + 1 = 63 (P08's 10 names are
`peter` plus 9 `gptr_*`; `gptr_map()` is internal, `gptr_scrub()` is new).

---

## 15. Review amendments (IC-32..IC-73, 2026-09-30)

An adversarial review of `03`, `04`, `05`, the register and the conventions raised 144 issues
(`dev/spec/06-review-resolution.md` lists each with its verdict). The decisions below are binding and **win over
every earlier section of this document** where they differ; the sections they touch were edited in place as well
(and `03`, `05`, the register and the conventions were edited to agree). Each decision names the review issues it
resolves by lens and number (`req-n`, `cran-n`, `cons-n`, `fid-n`, `plug-n`, `safe-n`, numbered in the order of
06's table). All code uses `=` and `|>` (S-9).

### 15.1 Package build and layering

**IC-32 Load order.** `R/aaa-state.R` (P01) holds `the`, `on_load()`, `on_unload()`, `ext_service_set()`,
`ext_service_get()`, `ext_service_has()`, the internal `%||%` (R >= 4.2 has no base `%||%`; fid-19) and
`redactor_set()` (IC-34). It is the one exception to the `<area>-<topic>.R` rule and collates first, so every
file may call `on_load(...)` at top level: R evaluates package code at install time in collation order, and
`utils-options.R` collates after every other area but `zzz.R` (a toy package failed to install with "could not
find function on_load"; cons-1). `on_load()` stores its expression unevaluated, so the stored
`ext_declare_builtin()` and `ext_service_set()` calls need not exist yet. P01 acceptance adds "`R CMD INSTALL`
succeeds with a later-collating file calling `on_load()` at top level". DESCRIPTION has no `Collate` field.

**IC-33 Layering test and the kernel SDK.** The area matrix of `03` §2.2 is replaced, for calls *into* kernel
functions, by a function-level allowlist (req-13, cons-2, req-32):

- *Kernel SDK* (callable from any layer L3-L6 and from L4 built-ins): `session_data()` (read), `session_live()`,
  `session_home()`, `session_append()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`,
  `session_value_set()`, `session_value_get()`, `session_replay_apply()`, `session_replay_new()`,
  `session_replay_bind()`, `replay_lookup()`, `session_run()`, `run_start()`, `run_wait()`, `run_abort()`,
  `run_current()`, `run_eval_env()`, `run_emit()`, `dispatch_nested()`, `perm_check()`,
  `tool_result_message()`, `store_read()`, `store_rebuild()`, `call_value()`, `route_pass()`, `gateway_run()`,
  `gateway_defer()`, `replay_mode()`, `replay_guard()`, `egress_check()`, `home_address()`, `setting_get()`,
  `settings_effective()`, `settings_write()`, `resolve_identifier()`, `interpolate_prompt()`,
  `describe_binding()`, `eval_r()`, `format_eval_result()`, `rule_parse()`, `last_set()`, `ckpt_store_put()`.
- L1 adapters never call L2+: `provider_stream()` injects `opts$gate(call)` (the run's `perm_check()`),
  `opts$mcp_dispatch(message)` (the `mcp.dispatch_local` service bound to the session) and
  `opts$tool_result(result, call)`; `cli-claude.R` uses only these.
- L0 and L3 files reach trust through the `trust.get` service (fallback `FALSE`, i.e. untrusted) instead of
  calling `trust_get()` (P08, L6).
- `helper-arch.R` builds its function-to-file map by **parsing the files under `R/`** (located with
  `testthat::test_path("..", "..", "R")`, else `file.path(Sys.getenv("R_PACKAGE_DIR"), "..", "00_pkg_src", "gptr", "R")`
  under check); the test is skipped with a message when the sources cannot be found, never passes vacuously.
  Literal `ext_service_get("<name>")` calls are mapped to the providing plan so service coupling is visible;
  a call to an undeclared service name fails the test.
- `arch_allowed()` = the `03` §2.2 layer matrix plus `arch_kernel_sdk()` (the list above); `arch_services()` =
  the §7.0 service names.

**IC-34 Services: completeness, ownership, the `service` kind.** (cons-3, cons-4, plug-3)

- `redactor_set(fun)` (P01, `aaa-state.R`) generalises `condition_redactor_set()`: identity until P03 installs
  `redact()`; `gptr_abort()`, `spill_write()`, `ev_dispatch()`, `registry_diagnostic()` and `ctx$redact()` call
  `redact_hook(x, profile)`, so P01/P02 never call P03.
- New services (§7.0): `trust.get` (P08; fallback `FALSE`), `identifier.resolve` (P08; fallback: symbols and
  strings are taken literally), `secret.lookup` (P03; fallback `NULL`), `ctx.kernel` (P06: a named list of the
  implementations behind the `ctx` members of §10.6 that are marked P06), `ctx.input` (P07), `ns.names` (P10;
  fallback `character(0)`), `eval.r` (P09: `eval_r()` through the `evaluator` kind), `describe` (P09),
  `router.call` (P08, IC-69), `session.add_tools` (P07, IC-69), `search.sources` (P10). `ctx_new()` (P02) is a
  thin shell whose members call `ext_service_get()` lazily at call time.
- `gptr_agent()` stores the raw captured expressions (symbol names or literals) and resolution happens at the
  gateway (no P02 -> P08 call). P06 obtains the preset's tool list only through `prompt.freeze` (and its
  documented fallback: the four core tools); it never calls `preset_tools()`.
- Every service is **owned by a built-in**: `ext_service_set(name, fun, provided_by, builtin)`; when that built-in
  is filtered out, `ext_service_get()` signals `gptr_error_not_available` (so `-builtin:documents` removes
  `doc.site`, `doc.edit` and `doc.s1_block` too). A new registry kind **`service`** [experimental] (resolve
  `first`, name = service name, field `fun`) lets a plugin provide or replace a service at a lower rank; once P02
  is loaded `ext_service_get()` consults the registry first, then the bootstrap table.

**IC-35 Constructor signatures.** (req-20, cons-5) §6.7 and §6.8 now read:
`gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`;
`gptr_context_block(name, provide, placement = c("turn", "first", "both"), authority = c("data", "operator"),
budget = 300L, order = 650L)`;
`gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL,
capabilities = list())` with the validator rule: `http_*` and `process_jsonl` need `build` and `parse`,
`inprocess` needs `stream`, classifier adapters need `classify`;
`gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat",
"classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE,
offline = FALSE, rate = NULL)`;
`gptr_router(name, route, description = NULL, timeout = 2)`;
`gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`.
P02 acceptance adds: every §6.8 example runs.

**IC-36 Ownership moves.** (cons-6, cons-7, cons-8, req-29, cons-15, req-31, cons-16, cons-23)

| Item | Before | After |
|---|---|---|
| `gptr_prob()` | P08 `gptr-sdk.R` (its example needed P13 at M1) | P13 `s1-types.R` |
| `$`, `[[`, `.DollarNames`, `print`, `$<-` of `gptr_gateway` | split P08/P10 | all P08; `$`/`[[` call the `ns.resolve` service, `.DollarNames` the `ns.names` service (fallbacks: `gptr_error_not_available` / `character(0)`); P10 only registers the services |
| member `out` | P10 and P22 | P10 only (`builtin:tools`); P22 keeps `sh`, `script`, `bg`, `jobs` |
| `gptr_map()` | export (P19) | internal: the function behind `parallel =` (S-1: one gateway); `gptr_parallel()` stays |
| `gptr_jobs()` | P21 `agent-background.R` | P04 `proc-supervise.R` (it reads the job table); P21 adds session rows |
| `inst/gptr/fixtures/fake_cli.R` and the CLI leg of the INFRA-16 test | used by P19 before P20 exists | P20 (acceptance 2 gains the interleave leg); P19 tests inline and worker only |
| dependency edges | P17 depends on P08 | P17 depends on P08 and P10 (the `plugins` section, `ns_catalog()`, `read` activation) |

New export (IC-70): `gptr_scrub()` (P03). The export count stays **63** (-1 `gptr_map`, +1 `gptr_scrub`).

### 15.2 Gateway, capture and routing

**IC-37 Tool identity and exposure.** (cons-9, plug-11) One tool spec per capability; `exposure` is a default
visibility, not an identity:

- A spec may carry both `execute` (the direct-tool form) and `fun` (the member form); the built-ins `read`,
  `edit`, `write`, `grep`, `find`, `ls` carry both.
- The tool array is built by the preset (IC-69 `preset` kind) from any spec with an `execute`; plugin specs with
  `exposure = "direct"` are always added.
- `$.gptr_gateway` resolves any spec **without** a namespace that has a `fun`, whatever its exposure, except
  `hidden`; `deferred` and `hidden` only exclude a spec from catalogs.
- Reserved member and namespace names: every built-in member name, `mcp`, and the names of the §9.4 table. A
  plugin spec with `exposure = "r"` MUST set `namespace`; a namespace equal to a reserved or existing member name
  is `gptr_error_invalid_spec` at registration.

**IC-38 Context placement.** (req-9, cons-10, plug-14) `context_block` `placement` accepts `"both"`:
`context_first_message()` renders `first` and `both` specs, `context_turn_blocks()` renders `turn` and `both`
specs, each in `order`. `builtin:workspace` registers `attached` (order 600) and `skill_content` preloads with
`placement = "both"`, so `peter("x", mtcars)` sends `<attached name="mtcars">` after `<workspace>` in its first
request (P07/P09 acceptance). Turn blocks are **deduplicated**: a block whose text hash equals the last emitted
text of the same name in this session is skipped, and `ctx$input$last_hash` lets `provide()` return `NULL`
itself. The spec default placement stays `turn`; the extending-gptr vignette recommends `first` for constant
text.

**IC-39 Route order and nesting.** (cons-11, req-19) Route orders are: `classifier` 10, `team` 15, `fanout` 16,
`nested` 20, `console` 30, `document` 50, `continue` 60, `new` 70. `team` and `fanout` calls made while a run is
active create children of the running session (depth + 1, mode only tightened, usage rolled up, budget charged
to the root, IC-66). `gptr.subagents.max_tasks` (8) applies only to team and fan-out calls made at depth >= 1
(model code), with the classed error `gptr_error_invalid_argument` naming the limit; user-level fan-outs queue
every element and run `parallel`/`max_active` at a time (P19 acceptance: 20 elements, `parallel = 4`).

**IC-40 Where a continuation evaluates.** (req-10) Precedence for the run's evaluation environment: an explicit
`envir =` (detected with `missing(envir)` in the gateway frame) > the session's kept home (globalenv, an explicit
earlier `envir`, or a fork overlay) > the caller frame (`parent.frame()`). Context symbols of the call are read
from the call's frame; when a symbol label is not visible from the run's evaluation environment with the same
object address, the gateway fails fast with `gptr_error_invalid_argument` naming the object and suggesting
`envir =` or a named value. P08 test: `f = function(s, d) s |> peter("filter d", d)`.

**IC-41 Capture without forcing symbol dots.** (req-4) For a dot whose expression in `sys.call()` is a plain
symbol (top level, data-first pipe, continuation with context), the gateway computes the facts with a leaf
`get0(name, envir = parent.frame(), inherits = TRUE)` and never forces the dot's promise; only calls and
forwarded `...`/`..n` dots are forced through `...elt(i)`. Documented: an object passed through a call or a
wrapper's formal is referenced by that frame for the run, so an in-place edit of it *during* the run copies once.
`expect_no_copy()` gains `in_run_edit = TRUE`: the fake provider issues an `r` call running `edit` inside the run;
rows for `peter("x", big)`, `big |> peter("x")` and `s |> peter("x", big)` expect 0 copies.

**IC-42 Identifier normalisation.** (req-12) `identifier_known()`/`resolve_identifier()` compare skill, plugin,
extension and agent names after `name_norm(x) = tolower(gsub("[._]", "-", x))`, so `skills = single_cell`
resolves to `single-cell` and `skills = high_performance_r` to the built-in; an ambiguous match is
`gptr_error_invalid_identifier` listing the candidates. Package-facing documentation and `03` §11.3 use strings
(`model = "jev"`) and `gptr::gptr_agent()`; bare identifiers are for scripts and the console, and
`gptr_check(<package>)` flags bare gptr identifiers in package code (plug-13).

**IC-43 Human predicates.** (req-11, cran-6) `gptr_can_prompt()` (P01): the `gptr.interactive` option if set,
else `interactive() || isTRUE(getOption("jupyter.in_kernel"))`, excluding knitr, testthat and
`check_running()`. It decides every question: `perm_check()` asks, the `ask` tool, `gptr_confirm()`,
`gptr_init()`, the egress acknowledgement, the `console` route and the mode-block variant. `gptr_has_human()`
keeps deciding streaming and verbosity. `builtin_ui`'s resolution uses `gptr_can_prompt()`.

**IC-44 Namespaced call options.** (plug-8) `.opts` accepts entries named by a registered plugin namespace
(the prefix of its `setting` specs): `peter("Review analysis.R", .opts = list(panel = list(size = 3)))` is
validated by the `panel.*` setting specs and reaches routes and handlers as `call$args$opts$panel` and
`ctx$input$opts$panel`; unknown names still signal `gptr_error_invalid_argument`. Named arguments to `peter()`
are always context objects (documented). `.opts$images` (req-36): a list of PNG/JPEG paths, `ggplot` objects or
`recordedplot` objects sent as image blocks in the user message (vision-capable models only; rendered with
`plot_png()`, 532 tokens each at 768x512).

### 15.3 Documents and replay

**IC-45 The document route.** (req-7, safe-15, cran-3)

- `document` (order 50) matches a **top-level** call located in a document (any `doc_locate()` site with a
  path) that **contains a block owned by this call**. Replay needs no write consent. Without a block it sets
  `call$doc` when write consent exists and passes.
- **Write consent** is checked only in `doc_upsert()`: `gptr_doc(path)` in this process (binds that document for
  every `peter()` call of the process, console or script), `options(gptr.record = "auto")`, user-scope setting
  `record = "auto"`, or an interactive yes (remembered per document in the user-level project file, IC-52).
  `record` is a tighten-type setting, so a project can only turn it off; the earlier "trusted `record = auto`"
  wording is deleted.
- **Freshness** also covers interpolated values: header key `args=<8 hex>` = the first 8 hex of sha256 of the
  sorted `name=value` pairs interpolated into the prompt (absent without interpolation). A block is fresh only
  when `prompt=` and `args=` both match; the S2 cache key includes the args hash. A stale block under `replay`
  errors `gptr_error_stale_block`.
- **Forced replay only in examples**: `replay_mode()` forces `"replay"` when `check_running()` and
  `Sys.getenv("TESTTHAT") != "true"`; an explicit `replay =` argument wins under tests. "In a vignette build" is
  deleted (vignettes are precomputed and run no gptr code). The mock-server and fake-CLI test helpers register
  their providers with `offline = TRUE` (no remote model is called), so `GPTR_REPLAY=replay` in `setup.R` does
  not block them.

**IC-46 Replaying fresh blocks.** (req-5, cons-22, req-2)

- **Piped session**: when `call$session` is non-NULL, `session_replay_apply(s, block, header)` (P06) advances
  that **same object**: appends `gptr.replay`, adds the block id to `.d$seen` (a block already in `seen` adds no
  turn), increments `turns`, sets the value by name from `value=` under the value policy, sets `last_text` from
  the S2 cache when present, and returns `s`. So `identical(chain_result, first_result)` holds for a replayed
  pipe chain.
- **No piped session**: `session_replay_new(block, header, envir)` returns a live session holding the header's
  `session=` id if one exists in this process; otherwise a `replayed` session that adopts the recorded id when
  no live session holds it. Its transcript comes from the session JSONL truncated at the recorded turn when the
  file exists, else it is **reconstructed** from the document (the template as the user message, the recorded
  code as the assistant's `r` call, the `#>` lines as its result, the S2 answer text if cached) with
  `.d$history_source = "reconstructed"`. A later live continuation of a reconstructed session prints a one-time notice
  that the history is reconstructed.
- **Fork blocks** (`fork=` header): the replay result is bound to the block id with `session_replay_bind(block,
  s)` in a process table `the$replay_blocks` (gptr-created sessions only, never user frames; replaced on
  re-source). Recorded fork turns are wrapped `local({ ... }, envir = gptr_resume(block = "<block id>")$envir)`;
  `gptr_resume(block =)` returns the bound session or signals `gptr_error_replay_unbound` ("source the
  statement that owns block <id> first"); it never falls back to `parent.frame()`. A fork rebuilt from JSONL
  always gets a fresh `new.env(parent = <parent's kept home>)`. P15 acceptance: re-source NS-3 twice; the
  main-line `qc_flags` and `qc$value` are unchanged and the fork's objects live only in its overlay.
- `gptr_resume()` gains `block = NULL, child = NULL` (§6.5).

**IC-47 Recording teams, fan-outs and block-nested calls.** (req-6)

- A top-level team or fan-out statement owns **one block**: header `kind=team|fanout`,
  `children="<name>:<session id>,..."`, `session=<team id>`, `turn`; body per child in name order:
  `## Agent <name> (<model>): <first line of its report>`; for a child with exports, its recorded code wrapped
  `local({ ... }, envir = gptr_resume(block = "<id>", child = "<name>")$envir)` followed by one
  `<export> = gptr_resume(block = "<id>", child = "<name>")$envir$<export>` line per exported name. Child texts
  are cached in S2 under `(doc, block, "<name>")`. Replay returns a team or fan-out session of replayed children
  with zero requests; the "team and fan-out calls own no document block" note is deleted. Because the `team` and
  `fanout` routes (15, 16) run before `document` (50), they first call the `doc.replay` service (P15; absent
  before P15, then they run live) and return its replayed session when the statement's block is fresh, and they
  pass their session to P15's writer through `run$opts$doc` like any other top-level call.
- **Block-nested calls**: a `peter()` statement located directly inside an agent block's body (`site$in_block`)
  is replayed from S2 under `(doc, block, "n<ordinal>")` in `auto` and `replay` (zero requests; a miss under
  `replay` errors `not_recorded`) and runs live only in `live`. When a block is written, the final texts of the
  child sessions its `r` calls created are cached in creation order. Calls deeper inside block code (loops,
  functions) run live, like calls in user loops. System 1 calls inside blocks use the S1 cache; a miss under
  `replay` errors `not_recorded`.
- Acceptance under `GPTR_REPLAY=replay` with zero requests: a block containing a nested sub-agent call (P15);
  NS-6's team block (P19, which depends on P15).

**IC-48 What recorded code contains.** (req-1, req-26, req-28)

- `gptr_return(x)` outside a run returns `invisible(x)` with a once-per-session `notice`, suppressed while a
  document is being replayed; `gptr_error_not_in_run` is removed.
- `doc_block_lines()` drops, at top-level-expression granularity (`getParseData()` of each recorded code chunk),
  calls to `gptr_return()`/`gptr::gptr_return()` and to members whose spec has `record = FALSE`; a chunk that
  becomes empty is omitted; the value stays in `value=`. `record = FALSE` is set for `out`, `plot`, `help`,
  `search`, `describe`; the `<r_session>` text tells the model to use them only with `record = false`.
- Plan-mode runs never record code (`record` forced `FALSE`); their block holds one `## Plan: <plans path>`
  comment.
- S-9 best effort: `doc_block_lines()` rewrites `<-` to `=` for `LEFT_ASSIGN` tokens whose assignment is a
  top-level expression of the chunk or a direct child of a `{` expression list, never inside call arguments;
  `->`, `<<-` and `%>%` are left alone.
- P15 acceptance: a block whose code called `gptr_return(fit)` and `peter$out("o1")` re-sources cleanly under
  `source()` and Rscript, and `$value` resolves `fit`.

**IC-49 Console transcripts and steering in documents.** (req-8) The first REPL prompt of a session is recorded
as `s_<6 hex of the session id> = peter("...")`, later REPL turns as `s_<hex> |> peter("...")`. Steers and
follow-ups delivered during a block's turn (pause menu, `gptr_steer()`, pipe into a running session) are recorded
inside that block as `## Steer: <text>` / `## Follow-up: <text>` lines, excluded from the prompt hash and `sha`.
P15 acceptance: a two-turn console session plus one menu steer produces a transcript that re-sources as one
session.

**IC-50 Jupyter documents.** (req-11) With `front_end() == "jupyter"` gptr never writes the open notebook: the
block is shown as the cell's output (a fenced R code block) and recorded as a pending `gptr.doc_block` entry
(`backend = "pending"`) plus a pending sidecar; `gptr_doc(path, format = NULL, sync = FALSE)` gains `sync`:
`TRUE` applies the pending blocks of that notebook through gptr's ipynb serializer when the notebook is closed or
headless. P15 fixture test with `jupyter.in_kernel` mocked.

**IC-51 Durable, safe document writes.** (safe-16, cran-17)

- The deferred-write sidecar holds `list(doc, base_md5, upserts = list(list(block_id, lines, site)), session,
  pid, time)`, is flushed after each settled top-level call (so SIGTERM loses at most one call) and is applied at
  exit by the finalizer; the next `peter()`, `gptr_blocks()` or `gptr_doc()` touching that document in any process
  re-applies unapplied upserts of a dead pid through the normal md5 and re-locate path and reports conflicts
  instead of overwriting. Sidecars are never pruned automatically; `gptr_cache("info")` lists them. Under a
  document lock held by another live pid (array jobs) nothing is recorded and a notice is printed.
- `write_atomic()` retries `file.rename()` 3 times with 100 ms sleeps, then writes in place with `writeBin()`
  after an md5 re-check. `path_key(p)` (P01) lower-cases normalised paths on Windows and macOS; document bindings,
  trust keys, locks and site matching use it.

### 15.4 Safety

**IC-52 Settings the project cannot plant.** (safe-2, safe-3, safe-23, safe-24)

- "Always in this project" rules, the transcript target and per-document record consent live in
  `R_user_dir("gptr", "config")/projects/<first 16 hex of sha256(path_key(root))>.json`, never in the project
  tree. `gptr_permissions(scope = "project")` writes there. An existing `.gptr/settings.local.json` contributes
  only `permissions.deny`/`ask` additions and only in a trusted project; allow, record and transcript keys in it
  are ignored with a notice. Transcript and document targets must lie inside the project root, have extension
  `.R`, `.Rmd`, `.qmd` or `.ipynb`, and not be a `control` or protected path.
- Instruction authority follows trust. In an untrusted project, project instructions render as
  `<project_instructions trusted="false">` and the frozen `<context>` section says such blocks are information,
  not commands; the first interactive session in an untrusted project that has `AGENTS.md`, `CLAUDE.md` or
  `.gptr` skills/agents asks the trust question once. Non-interactive + untrusted + mode `auto` or `edits`:
  project instructions, project skills and project agents are omitted with a notice. Only skills from user
  directories, installed packages and trusted projects enter the T1 catalog. Project-file updates are no longer
  operator messages but user-role `project_instructions_update` context blocks; `context_block` `authority = "operator"` is allowed only for records of rank >= 3.
- `trust.json` records a `fingerprint` (sha256 over the sorted paths and contents of the trust-gated files:
  `.gptr/settings.json`, `mcp.json`, `extensions/`, `plugins/`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `agents/`, an
  auto-discovered `.env`). On a mismatch the changed resources are treated as untrusted: interactively the
  changed files are listed and the question asked again; non-interactively they are ignored with a notice.
  gptr's own writes re-fingerprint.
- `gptr_resume(path)` of a file whose header `cwd` differs from the project root, or that git tracks, rebuilds
  with a freshly frozen prompt from the current settings and marks the prior user turns `source = "imported"`.
  File restores (rewind) are confined to the project root and `tempdir()`; a restore outside needs an
  `ask_human` per path.

**IC-53 The permission kernel cannot be reconfigured by model code.** (safe-1, req-16, safe-6, safe-18)

1. `perm_check()` fails closed: with no active `mode` policy the decision is `ask` (and `blocked` without a
   human). `builtin:permissions`, `builtin:plan` and the `critical_guard` and `secret_guard` policies cannot be
   disabled by filters from any source; filters that would remove `policy` or `hook` records are refused inside a
   run. The only escape is `options(gptr.unsafe_no_permissions = TRUE)` set outside a run (documented for
   sandboxed CI).
2. `run_start()` snapshots `gptr.ui`, `gptr.interactive`, `gptr.critical_guard`, `gptr.secret_guard`,
   `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode` and `gptr.unsafe_no_permissions`; the run's gate
   reads only the snapshot.
3. `risk-functions.csv` gains category `control`, level 4, `ask_human`: `gptr_config`, `gptr_permissions`,
   `gptr_trust`, `gptr_init`, `gptr_env`, `gptr_register`, `gptr_reload`, `gptr_on`, `gptr_mcp_add`,
   `gptr_mcp_remove`, `gptr_mcp_serve`, `gptr_login`, `gptr_logout`, `gptr_doc`, `gptr_cache` (prune, clear),
   `gptr_scrub` (`dry_run = FALSE`), and `gptr_resume`, `gptr_fork`, `gptr_steer`, `gptr_cancel`, `gptr_rewind`
   on a session other than the running one; `options()` with `gptr.*` names, `Sys.setenv()`/`Sys.unsetenv()` of
   `GPTR_*` or provider key names, `setHook()`, `assignInNamespace()`. These exports also check `run_current()`:
   called from model code during a run they signal `gptr_error_permission` unless the dispatcher approved
   exactly that call through an `ask_human` (a one-shot token on the run).
4. Every gateway call made while `run_current()` is non-NULL (any route) inherits the running mode (only
   tightened) and filters; model code continuing an idle user session runs it in the stricter of the two modes.
5. The parent re-classifies the raw input carried in every forwarded worker `permission_request`; the worker
   backend is documented as not an isolation boundary.
6. Two ask tiers: `ask` (levels 1-3 without a guard) may be answered by `permission_request` hooks;
   `ask_human` (level 4, the secret guard, the `control` category and path class, first use of a CLI route, the
   egress acknowledgement) only by a UI backend whose `has_ui()` is `TRUE` in the run's snapshot. A hook
   returning allow for an `ask_human` is ignored with a diagnostic.
7. A `modify` decision is re-classified and re-checked once; a second `modify` denies. Only `r(secret:NAME)`
   rules pre-approve the secret guard.
8. Approval displays (console, rstudio dialogs, worker-forwarded requests) escape C0/C1 controls except TAB and
   bidi and zero-width characters as `<U+XXXX>`; the one-line prompt lists every flagged call and `+N more
   lines`.

P24's `test-injection-e2e.R` adds an injected model trying each path above; every attempt ends in a human ask
(interactive) or `blocked`.

**IC-54 Classifier defaults and protected paths.** (safe-4, safe-5)

- Level 0 means "known read-only". A call to a function outside base, stats, utils, methods, graphics, grDevices
  and tools that is not in the table is level 1 (asks in `manual` and `edits`). A shipped risky-package list
  (targets, usethis, devtools, renv, pak, remotes, fs, gert, git2r, gh, googledrive, pins, `aws.*`, `paws.*`, DBI
  write verbs `dbExecute`, `dbWriteTable`, `dbRemoveTable`, `dbSendStatement`, and request performers of httr,
  httr2 and curl) is at least level 2 (delete verbs 3). User and plugin `risk_rule` rows (IC-69) may lower
  levels explicitly.
- Plan mode evaluates an `r` call only when every call in it resolves to an allowlisted read-only function
  (level-0 `read` rows, base/stats/utils getters and summaries, describers, gptr read members); otherwise the
  call is denied with "not known to be read-only in plan mode".
- `path_class()` gains `control` (level 4, `ask_human`, never pre-approved by rules): `.gptr/settings*.json`,
  `.gptr/mcp.json`, `.gptr/extensions/`, `.gptr/plugins/`, `.gptr/SYSTEM.md`, `.gptr/APPEND_SYSTEM.md`,
  `.gptr/agents/`, all of `R_user_dir("gptr", "config")`, `.git/hooks/`, `.git/config`, `.Rprofile` anywhere,
  `Rprofile.site`, `Renviron.site`, the `R_PROFILE_USER`/`R_ENVIRON_USER` targets and `~/.R/Makevars`; and
  `instructions` (level 3): `AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`, `.gptr/skills/`, `.gptr/prompts/`.
  Both apply to the direct `write`/`edit` tools, `peter$write`/`peter$edit` and static path arguments in R code.
  Control files modified during the process are not loaded again without confirmation (IC-52 fingerprint).
- P11 acceptance adds 18 §2.5's blind-spot cases with the new levels and the control-category calls in `manual`
  and `plan`.

**IC-55 Steering relays by source.** (safe-7) Queue items carry `source` in `pipe`, `pause_menu`, `repl`,
`api_user` (`gptr_steer()` called outside any run), `extension` (`ctx$send()` from a plugin or hook) and `agent`
(a sibling or child). Only the user sources get the operator relay `The user sent this message while you were
working: <text>`. `extension` items are user-role data `Extension <name> sent this note (not from the user):
<text>`; `agent` items are delivered as `<agent_report from="<name>">...</agent_report>` user-role data, never
as steers. `ctx$send()` and `gptr_steer()` called from model-evaluated code of the same session tree are refused
with `gptr_error_permission`. Test: a child agent's text never appears in an operator message.

**IC-56 Pending-plan hand-off.** (safe-19) The plan is handed only to the **next** `peter()` call of the same R
process and environment within one hour, and only when that call is top-level (not nested, not in a run, not in
a loop body); any other `peter()` call in between discards it with a notice. The executing run prints the plan's
step list before its first action.

### 15.5 Reactor, processes and the store

**IC-57 Re-entrancy.** (req-17, safe-8)

- The reactor tracks its pump depth. A nested pump (depth > 1) runs FIFO tools only of the runs it was given in
  `allow_runs`; its default is `if (is.null(run_current())) NULL else character()`, so System 1 and MCP HTTP calls
  made from inside an `r` evaluation never run a sibling's R tool.
- `later::run_now(0)` is called only at depth 1, or at depth > 1 when `allow_runs` contains a CLI child served by
  the MCP server; in that case the MCP handler answers a request whose token is bound to a run outside
  `allow_runs` with a retryable JSON-RPC error (`-32002`, "gptr is busy; retry") instead of evaluating.
- The background pump is a no-op while the reactor is on the stack (depth > 0).
- Asks raised outside a blocking gptr call (background runs, `gptr_mcp_serve()` at an idle console) never
  prompt from a `later` callback: a background run moves to status `waiting` (a notice; `gptr_jobs()` shows it)
  and the ask is shown at the next `gptr_wait()`, `peter()` or console turn; a served request that needs approval
  is denied with how to allow it and a console notice. Non-interactively both are `blocked`/denied.
- A background R tool that changed bindings in the user's environment at an idle tick prints one notice.
- P04/P19 acceptance: an inline agent calls System 1 while a sibling has a queued tool; the sibling's tool starts
  only after the first evaluation returns.

**IC-58 One MCP server, one token per client.** (req-18) `gptr_mcp_serve()` keeps one listening socket per
process but issues a separate 192-bit bearer token per client: `mcp.serve_ensure(session)` returns a handle whose
token is bound to that session (the CLI child's session). The server maps token -> session and evaluates each
request in that session's run evaluation environment (so a fork's CLI child evaluates in the fork overlay) with
its mode, rules, budget and usage roll-up; tokens are revoked when the child exits. The explicit user handle
keeps its dedicated session. P18/P20 tests cover a fork and a plan-mode parent.

**IC-59 Session store.** (cran-1, fid-3, safe-10, req-3, cran-2)

- **Open, append, close**: `store_append()` does `con = file(path, "ab"); on.exit(close(con), add = TRUE)`,
  writes and flushes inside `suspendInterrupts()`, per entry or per batch at a turn boundary. No R connection
  outlives a gptr call; the live record keeps the path and the lock only. The same rule holds for the wire log,
  the JSONL frontend (it writes to a connection its caller owns) and the `.stdin` REPL connection (closed on
  `/exit` and by `on.exit()`). R allows 125 user connections, and `--as-cran` examples fail with "connections left
  open" (both reproduced).
- **Torn-line recovery**: opening an existing file for a resume reads its last byte; when it is not LF, gptr
  appends `"\n"` and a `gptr.recovered` custom entry naming the torn byte range before any new entry.
  `store_read()` skips any unparsable line with a diagnostic and re-parents the children of missing ids to the
  nearest valid ancestor in projection.
- **Locks**: `<file>.lock/pid` holds the pid and the process creation time; a lock is stale when
  `pid_alive(pid, create_time)` is `FALSE` or its heartbeat is older than 24 h; the reactor touches the file every
  10 minutes while the session is live. `pid_alive()` (P04, `proc-supervise.R`) is
  `ps::ps_is_running(ps::ps_handle(pid))` plus a creation-time comparison against pid reuse. **ps joins Imports**
  (it is already in the dependency closure through processx; the closure does not grow). `tools::pskill()` is
  never used as a liveness probe (on Windows it always calls `TerminateProcess`; lint rule).
- Tests: `nrow(showConnections())` unchanged after `peter()` returns, errors or is interrupted; 300 sessions kept in
  a list; CI runs `devtools::test()` with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true`; INFRA-13 extended: SIGKILL
  mid-append, resume, three appends, all present and the tree connected.

**IC-60 Child processes.** (cran-10, fid-4, fid-5, fid-6, fid-18, cran-11, safe-9, cran-19, fid-20)

- `rscript_path()` (P01) = `file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else
  "Rscript")`; every test helper, fixture server and fake CLI uses it (fake CLIs run as `c(rscript_path(),
  fake_cli)` through `options(gptr.cli_path)`); lint rejects a bare `"R"` or `"Rscript"` command in `proc_spawn()`
  and `proc_run()` (R CMD check puts failing dummy R and Rscript scripts first on PATH).
- `child_env()` returns a **complete** named character vector without the removed names (processx rejects `NA`
  in `env`); `child_env_callr(env)` converts it for callr (removed names as `NA`). Every profile (mcp, helper,
  cli-claude, cli-codex, worker, artifact) points `R_ENVIRON_USER` and `R_PROFILE_USER` at gptr's empty files and
  drops `R_ENVIRON` unless passed explicitly (an Rscript child otherwise re-reads keys from `~/.Renviron`).
- `proc_spawn()` and every `callr::r_bg()` pass `encoding = "UTF-8"` (processx drops non-ASCII bytes of piped
  output in a C locale); `write_all()` writes raw bytes (`charToRaw(as_utf8(x))`) and is **non-blocking**: the
  reactor keeps a per-child buffer, retries `write_input()` each iteration and drains stdout/stderr between
  attempts, with a deadline (`gptr.stdin_timeout`, 60 s) and `gptr_error_timeout`.
- `supervise_default()` = `getOption("gptr.supervise")` if set (`isTRUE()`), else `!check_running()`; used by
  `proc_spawn()`, workers and artifacts (passing `NULL` to processx errors). Every long-lived child exits when the
  parent dies: `worker_main()` on stdin EOF or EPIPE and a 5 s parent-pid check; artifacts through their watchdog;
  CLI children through supervision. `proc_spawn()` records a tree marker under `R_user_dir("gptr", "cache")/procs/`;
  the orphan sweep at the next load is mandatory (SIGTERM skips finalizers; verified). P04 acceptance kills the
  parent with SIGTERM and asserts no survivors after the next sweep.
- Under `check_running()` every child-process pool (CLI, MCP stdio, bridges, fixtures, workers) is capped at 2;
  every process-spawning test calls `skip_on_cran()`.
- A requested stop is recorded in the job table (`stop_requested`); any exit after it maps to status `stopped`
  (artifacts, bridges) or `aborted` (children), never `error` (callr 3.8.0 exits 1 with `callr_timeout_error`).

**IC-61 Randomness.** (req-3, cran-8, fid-9) gptr never calls `set.seed()`, `RNGkind()`, `sample()` or
`runif()`, and `parallel` is not imported. Per-agent L'Ecuyer streams are swapped in by one leaf,
`rng_swap(state, expr)` (P09, `eval-core.R`): it saves `get0(".Random.seed", globalenv(), inherits = FALSE)`,
assigns the agent's `c(10407L, <6 seeds>)`, evaluates, keeps the advanced vector in the agent's state, then
restores the saved value or removes the variable. The six seeds come from 24 bytes of `sha256(<agent id>)` reduced
modulo m1 = 4294967087 (three) and m2 = 4294944443 (three), stored as R integers (two's complement), or from an
explicit `.opts$seed` hashed with the agent label. `with_seed_preserved(expr)` (P01, `utils-hash.R`) saves and
restores `.Random.seed` around third-party calls that use R's RNG in the parent (`chromote::Chromote$new()`,
loading shiny, httpuv helpers). Ports come from `port_candidates()` (P01: RNG-free hash bits in 49152-65535),
retried through `httpuv::startServer()` up to 20 times; `httpuv::randomPort()` is never called (it calls
`sample()`, verified). These two functions are the only code that assigns `.Random.seed` (R CMD check exempts
it; the lint rule allows it only there). Tests assert an identical `.Random.seed` after inline sub-agents,
`gptr_mcp_serve()`, the OAuth loopback and `peter$app(check = TRUE)`.

**IC-62 Encoding at ingress.** (cran-7) `as_utf8(x)` (P01): strings marked "unknown" that are valid UTF-8 are
marked UTF-8; other unknown strings go through `enc2utf8()`. It is applied at every ingress (prompts and
templates, context labels, file reads, child output, `.env` values, frontmatter, readline input). Every
`readLines()` passes `encoding = "UTF-8"`; bare `enc2utf8()` outside `utils-encoding.R` is a lint error
(`enc2utf8()` rewrites unmarked UTF-8 to `<c3><a9>` in a C locale, verified). End-to-end test: a script file with
a UTF-8 prompt literal under `LC_ALL=C Rscript --vanilla`; the bytes in the fake request log, the JSONL and the
document are exact.

**IC-63 Paths, homes and names.** (cran-5, cran-16, cran-20)

- `user_home()` (P01) = `USERPROFILE` on Windows, else `HOME`, else `path.expand("~")`, normalised with `/`;
  `app_config_dir(app)` resolves `%APPDATA%`, `~/Library/Application Support` or `$XDG_CONFIG_HOME` (else
  `~/.config`). Every foreign-harness path (Claude Code, Claude Desktop, Codex, Cursor, VS Code, Pi configs; `.claude`,
  `.agents`, `.pi` skill and agent directories) and `${userHome}` use them.
- `project_root()` honours `options(gptr.project_root)` and `GPTR_PROJECT_ROOT`. `setup.R` sets it to a temporary
  project and redirects `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA` and `XDG_CONFIG_HOME` to temporary
  directories. A Windows CI test plants `.claude.json` under a fake `USERPROFILE` and expects `gptr_mcp()` to list
  it.
- Artifact ids that are Windows reserved device names (`con`, `aux`, `nul`, `prn`, `com1`-`com9`,
  `lpt1`-`lpt9`) are rejected. Data snapshots are `data/001.rds`, `data/002.rds`, ... with the mapping in
  `artifact.json` (`data: [{name, file, class, dim, bytes}]`); the loader reads the file listed for each name.

**IC-64 HTTP details.** (safe-13, fid-11, fid-13, fid-12)

- Every provider, System 1, MCP, OAuth-token and catalog transfer sets `followlocation = 0L`; a 3xx is
  `gptr_error_provider` (class `redirect`) naming only the Location origin, never retried (libcurl forwards
  custom headers such as `x-api-key` across origins; reproduced). INFRA-22 and `test-secrets-e2e.R` add a
  redirecting mock that must receive no key bytes.
- `sse_splitter()` accepts LF, CRLF and lone CR line ends (a CR at a chunk end is held until the next chunk),
  strips a leading BOM, drops comment lines, joins `data:` lines with `"\n"`, lets the **last** `event:` field win
  and parses `id` and `retry`; `test-http-sse.R` and the INFRA-23 row add CRLF, CR-only, split-CRLF and
  duplicate-`event:` cases.
- `retry-after` HTTP-dates go through a locale-independent `parse_http_date()` (`month.abb`, UTC); an unparsable
  value falls back to exponential backoff (tests under `LC_ALL=de_DE.UTF-8` and `retry-after: soon`) [02
  fact-check].
- Provider records gain `rate = list(requests_per_s, tokens_per_s)` (the `typesafe` record: 40 and 1e5,
  overridable by settings and catalog); static rates feed the same token bucket as header-derived limits, and
  System 1 admission is process-wide.

### 15.6 Subscription CLI routes

**IC-65 CLI discovery and invocation.** (cran-9, cons-21, req-33, fid-7, fid-8, safe-12)

- `pcli_find()`: `options(gptr.cli_path = list(claude =, codex =))`, then PATH, then per-OS known locations
  (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `%USERPROFILE%\.local\bin`,
  WinGet links, and for codex the npm prefix resolved to the vendored `codex.exe`); RStudio and Positron on macOS
  do not source shell profiles. The npm `claude.cmd` shim is **refused** with an install hint (07); native
  binaries run without a shell, so the empty-string arguments `--tools ""` and `--setting-sources ""` are safe.
  The providers' `status()` functions use cached results or filesystem discovery unless
  `gptr_providers(check = TRUE)` requests version and capability probes. With both `check = FALSE` and
  `check_login = FALSE`, listing never spawns a process. `check_login = TRUE` is an explicit exception:
  help-gated CLI login-status commands run with closed stdin and a 3 s timeout per subprocess, never
  a model request. Only sanitized login states are returned; unknown/error states never imply signed out.
  A signed-in state includes supported API-key authentication and does not establish subscription
  billing or online credential validity.
- **claude** argv adds `--permission-mode default` and `--allowedTools "mcp__gptr__*"`, so the CLI sends no
  `can_use_tool` for gptr's own tools and gating happens once, in the `mcp_message` dispatch (the handler still
  denies anything else). With a budget in force it adds `--max-turns <remaining turns>` and
  `--max-budget-usd <remaining cost>` [07 table]. The child environment follows G6 §3.7 verbatim: remove
  secret-like names, registered values, `^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)` and
  `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`; keep `CLAUDE_CODE_OAUTH_TOKEN`,
  `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`; `CLAUDE_CODE_USE_BEDROCK`/`VERTEX`/`FOUNDRY` are removed with the
  `billing_env` warning. A capability probe (`--help`, version) detects a CLI whose `-p` defaults to `--bare`
  (which never reads the subscription login [07]) and passes the documented opt-out or stops with
  `gptr_error_cli_version`. After `system/init`, an `apiKeySource` other than `"none"` aborts the turn with
  `gptr_error_billing`. The wire log is per session (`cache/tmp/wire-<session id>.jsonl`).
- **codex** argv per turn: `codex exec --json --ignore-user-config --skip-git-repo-check -m <full id> -C <wd>
  -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN
  -c mcp_servers.gptr.default_tools_approval_mode="approve" -c mcp_servers.gptr.required=true
  -c mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <mode> -`; resume: `codex exec resume <thread> --json ...
  -c sandbox_mode=<mode> -` (resume rejects `-s` and `-C`) [08 §2.E, line 594-600, fact-check 16]. gptr's gate
  stays the approval authority. The child environment removes `^(CODEX_MANAGED_|CODEX_SANDBOX)`, `CODEX_API_KEY`,
  `CODEX_ACCESS_TOKEN`, `OPENAI_API_KEY`, `OPENAI_BASE_URL` and keeps `CODEX_HOME`. The evidence note is corrected:
  the in-session HTTP MCP route was verified through app-server listing and calls without a model; the verified
  model-driven MCP call used `default_tools_approval_mode = "approve"` and `required = true` [08 §2.G].
- **Sandbox mapping**: `plan`, `manual` and `edits` -> `read-only` (file changes go through gptr's gated
  `write`/`edit` over MCP, so edits-mode approval and checkpoints apply); `auto` -> `workspace-write`. Before a
  `workspace-write` exec gptr hashes the `control` files (IC-54) and refuses to load changed ones until the user
  confirms; the files checkpointer walks after each exec so `/undo` covers Codex's edits. On native Windows the
  sandbox is probed and the route falls back to `read-only` with a warning when it is not ready [08 line 2796].
  The one-time notice says Codex runs its own shell inside its sandbox.
- Codex has no turn cap flag: gptr counts `turn.completed`/`item.completed` events and cancels at the cap; each
  exec has a wall-clock limit (`gptr.cli_turn_timeout`, 3600 s).
- Live tests (`GPTR_LIVE_TESTS=true`) run Codex in a non-git temporary directory and require it to call the gptr
  MCP `r` tool.

### 15.7 Budgets, evaluation and tokens

**IC-66 Budgets.** (safe-11) Settings default `budget = {cost: 5, tokens: 2000000, turns: null}` per top-level
call (per prompt at the console); `budget_near` at 80%; reaching it asks to extend by the same amount
(`ask_human`) interactively and stops with status `budget` otherwise; `null` set explicitly disables a limit.
Budgets are hierarchical: every request's check walks to the root session and charges the root, and children
start with `min(<their share>, <root remaining>)`. Caps: `gptr.max_nested_calls` (20 `peter()` calls per `r`
evaluation; a team or fan-out counts as one) and `gptr.s1_max_elements` (10,000 elements per System 1 call; error
with a hint to chunk). Sourcing a document in `auto` prints one notice with the number and cost of live nested
calls and suggests `GPTR_REPLAY=replay`.

**IC-67 Evaluator details.** (fid-2, cran-15, plug-6, fid-15, fid-1, fid-16)

- R8 amended: the evaluator clears the `withVisible()` result in place (`res[1L] = list(NULL)`) before its frame
  returns and never stores it elsewhere (a result that aliases a user object, such as `L$a`, `(x)` or `get("x")`,
  otherwise makes the next edit copy; reproduced and fixed in place). `test-copy-eval.R` adds `L$a`, `(x)`,
  `get("x")`, `x@slot` and `x[["a"]]` rows.
- Plot capture: when `grDevices::dev.cur() == 1` and no human can see a device, the evaluator opens
  `grDevices::pdf(NULL)` with `dev.control(displaylist = "enable")`, closes it on exit and `dev.set()`s back to the
  prior device (no `Rplots.pdf` in `getwd()`; no screen device under `_R_CHECK_SCREEN_DEVICE_=stop`).
- Images: at most `gptr.r_max_images` (3) plots are attached per `r` result; later plots are kept in the session's
  out store and listed as `[plots 4-50 not attached: peter$plot(k)]` (`peter$plot(which = NULL, width, height)`).
  Image tokens count against `gptr.r_output_tokens`. When a request would exceed the provider's image count or
  byte limit (catalog `max_images`, 32 MB), older images are projected as `[image omitted: peter$plot(<id>)]`,
  recorded by an appended `gptr.image_elision` entry (one stated cache break). P09 acceptance: a 50-plot loop
  attaches 3 images.
- `eval_guard()` flags the `q` and `quit` symbols in any position (as a value, a `FUN` argument, inside
  `match.fun`, `get`, `do.call`, `base::`) as level 4 [12 fact-check].
- No shipped prompt text or skill recommends `str()` (it leaves a sticky reference: every `str()` of a large
  object makes the next edit copy; re-verified); the texts recommend `peter$describe(x)`, `dim()`, `head()`. A P07
  test fails when any shipped section or skill mentions `str(`; the high-performance-r skill states the cost.
- `peter$knit()` routes the shell engines (`bash`, `sh`, `zsh`, `powershell`, `cmd`) through `peter$sh()` with the
  `helper` environment and a timeout, and classifies the others like `peter$script()` [G5 fact-check 7].

**IC-68 Prompt composition by owners.** (plug-2, plug-10, plug-15, req-25; measured with rtiktoken o200k in
`dev/research/assets/design-review-resolution/prompt/measure3.R`)

- `<rules>` = the `guidelines` of the active direct tools in array order (read: its line; r: the three R lines;
  edit: four lines; write: one line; plugin direct tools: theirs), then P07's three closing lines. With the
  standard tools this equals `03` §7.3; the `readonly` preset drops the edit and write lines (237 -> 122 tokens).
- `prompt_section` specs may set `parent = "<section>"`: a fragment rendered inside that section at the
  `{{fragments}}` marker, in `order`. `<r_session>` is P07's core text with fragments from `builtin:tools`
  (helpers, `out`), `builtin:bridges` (shell), `builtin:lang` (Python, SQL, knitr) and `builtin:subagents`
  (sub-agents); `-builtin:bridges` removes its line. `documents` is registered by P15, `artifacts` by P23 and
  `system1` by P13 (IC-27 amended). P07's acceptance compares P07-owned texts byte for byte; P24 compares the
  composed prompt with every built-in loaded.
- The `r` tool schema is frozen in one of four variants: `record` and `note` only when a document is bound at
  freeze, `timeout` (described "Seconds; best effort. Default 3600.") only when no human can answer. Measured:
  197 (old) -> 188 / 169 / 137 / 118 tokens.
- The skills catalog shows pseudo-paths `[skill:<name>/SKILL.md]` that `read` resolves (`skill:<name>/<path>`),
  never library paths (which cost more and leak the Windows user name): 152 -> 143 tokens for the two built-ins.
- `<context>` adds one sentence for `trusted="false"` blocks (106 -> 141). `<r_session>` drops the MCP sentence
  (the `<mcp>` section says it) and adds the `record = false` rule (443 -> 455; 433 after D-135).
- Non-interactive runs in `manual` mode keep `ask` declared (+145 tokens of schema); calling it stops the run
  with status `blocked` and `gptr_error_noninteractive` carrying the questions (NS-12). The manual suffix reads
  `No one can answer questions or approvals in this run: actions that need approval, and questions asked with the
  ask tool, stop the run. Ask only when no reasonable assumption lets you continue.`; other modes keep the
  earlier suffix.
- New static totals (o200k; `03` §12.1): minimal 614 + 648 = **1,262**; standard core non-interactive 614 + 1,179
  + 542 = **2,335**; standard non-interactive with every section and a document 665 + 1,606 + 542 = **2,813**;
  standard interactive with every section and a document 791 + 1,623 + 542 = **2,956**; without a document 2,722.
  These are `prefix-baseline.json`'s initial values.

**IC-69 Extension API additions.** (plug-1, plug-9, plug-7, req-35, plug-12, plug-4, plug-16, req-14, req-15)

- **Routers** (kind `router`): `route(request, ctx)` with `request = list(prompt, messages (projected, read-only),
  state (the router's state from its last `gptr.router` entry on this branch), previous (the previous request's
  model), reason = "turn" | "compaction" | "direct", session)` returns a model ref or `list(model, thinking =
  NULL, state = NULL)`. Dispatch: P08 stores `router:<name>` as the session's model when `model` resolves to a
  router; P06 calls the router (service `router.call`) before each request and at compaction, with a timeout of
  `timeout` seconds (default 2; `ctx$decide()` allowed), falling back to the default model with a diagnostic. Each
  switch appends `model_change` (reason `router`) and a `gptr.router` state entry and emits `route`; each switch
  costs one System 1 call and one cache miss (`03` §12.4). P13 ships `inst/gptr/examples/jev-router.R`, a tested
  complexity router loadable with `extensions =`; P13 acceptance: a fake-classifier router switches models after
  the first successful `edit`, with exactly one `model_change`.
- **`ctx` run control**: `ctx$set_model(ref, thinking = NULL, reason = "plugin")` (a `model_change` at the next
  request boundary; one cache miss), `ctx$add_tools(specs)` (P07 `session_add_tools()`: rank-0 registration; an
  operator `tool_change` message carrying the declarations when the adapter declares `tool_addition`, else the
  specs become `r` members announced in an operator note), `ctx$tokens(x, class = "prose")` (the `estimator`
  kind), `ctx$eval(code, envir = NULL)` (the `evaluator` kind; plugin code, not gated), `ctx$describe(x, budget
  = 150L)`. `gateway_run()` calls `session_add_tools()` for `tools =`, `plugins =` and `extensions =` on a
  continuation.
- Tool specs gain `render = function(call, result, width)` (console rendering) and `parameters` may be a
  `function(ctx)` evaluated once at freeze (the `r` schema variants). New kinds (P02 validates them): `preset`
  (stable: `tools` chr or `function(human, model)`, `sections` named lgl or `function(name)`, `preamble`
  `"standard" | "short"`; `builtin:prompt` registers `minimal`, `standard`, `readonly`, `extended`; section
  predicates test the preset record, not its name), `risk_rule` (stable, resolve `all`: rows of
  `risk-functions.csv` columns, concatenated; the highest level wins on duplicates), `renderer` [experimental]
  (`type` = a custom entry type, `render(entry, width, ctx)` -> chr, `doc(entry, format)` -> chr lines),
  `search_source` [experimental] (`docs(ctx)` -> df `id`, `text`, `kind`, indexed by `peter$search()`), `store`
  [experimental] (`open`, `append`, `read`, `fork`; the JSONL store is its built-in, selected by setting `store`),
  `evaluator` [experimental] (the `eval_r()` contract; the built-in is `r`, selected by setting `evaluator`), and
  `service` (IC-34). 31 + 7 = **38 kinds**.
- New event `request_params` (patch chain): payload `params` limited to the fields the adapter declares non-prefix
  (`capabilities$request_params`, e.g. `service_tier`, `metadata`, `user`); a patch to any other field is ignored
  with a diagnostic.
- Arguments that name extensible records are validated against the registry, not fixed vectors: `backend`
  (`registry_names("backend")` plus `"auto"`), `peter$app(kind =)` (`artifact_type`), `.opts$frontend` and setting
  `frontend` (`frontend`), `.opts$preset` (`preset`). `mode` stays the fixed four values (the permission model is
  defined on them; plugins add policies instead).
- **Overrides are per record**: a lower-rank record shadows only the record with the same `(kind, name)`; a
  whole built-in is disabled only by an explicit `-builtin:<name>` filter (Pi merges per tool:
  `agent-session.ts:3478-3481`). P02 test: a user `read` override leaves `edit` and `peter$grep` working.
- **Session scope**: `ext_load(factory, source, rank, dir = NULL, manifest = NULL, lazy = FALSE, session = NULL)`;
  the API object, lazy activation and `hook_add()` carry `session`, every staged `registry_add()` receives it,
  and the session's records are removed at `session_shutdown` and by its finalizer. P02/P17 test: a factory passed
  through `extensions =` is invisible to the next `peter()` call.
- **Workers inherit the registry**: the worker spec gains `registry = list(specs = <rank-0 session specs and
  rank-3 user specs>, plugins = <enabled plugins with ranks>, filters = chr)`; `worker_main()` re-registers them
  first. Functions from package namespaces serialise by reference; closures from the global environment are shipped
  with their environments (documented); a registry serialises by reference and reads back in the worker as the
  empty environment, so a closure that reaches it (an extension's API object) ships none of its records (IC-70,
  D-177); a spec that cannot be serialised makes an explicit `backend = "worker"`
  fail with `gptr_error_invalid_argument` naming it, and `auto` stays inline. P19 acceptance: a plugin `r` member
  and a `gptr_fake_provider()` spec work inside a worker.
- **Token extension points**: `gptr_check(x, error = FALSE, tokens = FALSE)`; `tokens = TRUE` reports a plugin's
  declaration cost and the printed-result cost of each member on its examples. Truncation policies and catalog
  formatters are recorded as v1.x kinds (§1.3 of `03`). The append-only transcript is why Pi's `context` message
  transform is not ported; `compactor`, `context_block` and `request_params` are the supported alternatives.

### 15.8 Secrets, caches and small items

**IC-70 Late secrets and child output.** (safe-14, safe-21)

- `gptr_scrub(paths = NULL, dry_run = TRUE, error = FALSE)` (P03, `auth-redact.R`, exported): scans the
  workspace's persisted text (sessions, caches, spill files, plans, transcripts, the documents bound in this
  project; `paths` overrides) for registered secret values and derived forms; returns a data frame (`file`,
  `secret`, `count`, no values); `error = TRUE` signals `gptr_error_secret_found` when anything is found (for
  pre-commit and CI); `dry_run = FALSE` rewrites the files with markers, the only sanctioned rewrite of
  append-only files, and appends a `gptr.scrub` entry to each rewritten session. `secret_register()` scans live
  sessions' in-memory entries and warns with counts and the `gptr_scrub()` call [G6 §4.7].
- Child output is persisted only through gptr: MCP stderr and artifact logs are read incrementally and appended
  through `redact_stream("persist")`; raw redirect files are deleted at process exit; MCP logs live in
  `tempdir()/gptr/mcp-logs/` unless `options(gptr.mcp_debug = TRUE)`. `test-secrets-e2e.R` greps these sinks, the
  deferred-write sidecars and the worker spec and result files.
- System 1 cache values store `question_sha256`, never the question, and `input_hash` = sha256 of a per-project
  salt (`.gptr/cache/s1/salt`, committed, RNG-free id bits) concatenated with the canonical input; the cache key
  includes the salt. `transcripts/` is gitignored by default. The Security considerations page mentions PHI.

**IC-71 Smaller contract fixes.**

| Item | Decision | Issues |
|---|---|---|
| out store | per session (`live$out`, cap `gptr.out_keep`); `out_put(..., session = NULL)`, `out_get(id, ..., session = NULL)` look in the session, then the process store, then the spill file; ids `o` + 6 hex (RNG-free) | req-27 |
| artifact line | `print.gptr_artifact` shows `(running in background)` for status `running`; P14's renderer prints `artifact  <id>  ->  <url>   (running in background)` on `artifact_start` (NS-8) | req-22 |
| `gptr_config()` | `.scope = NULL`: `"project"` when a workspace exists, else `"session"` (NS-9) | req-23 |
| System 1 in `while()` | the `I()` hint claim is dropped (a function cannot see that it is a condition, verified); `s1_batch` is removed; a once-per-session message `s1_split` names `I(x)` when a data frame is split into several states | req-24 |
| agent names | names equal to a session accessor (`text`, `value`, `values`, `usage`, `cost`, `history`, `messages`, `model`, `mode`, `status`, `reason`, `id`, `kind`, `file`, `turns`, `envir`, `children`, `ext`, `plan`, `last_rewind`, `editor_text`) are rejected; children stay reachable through `[[` and `$children` | cons-23 |
| REQ-08 sorting | `peter$find(sort = c("path", "mtime", "size", "relevance"))` (fuzzy score); `peter$grep(output = "files", sort = c("path", "count", "mtime"))` | req-30 |
| forced tool choice | model capability `forced_tool_choice` (`FALSE` for Anthropic 5.x); `returns =` uses `output_config.format` on Anthropic, elsewhere `auto` + instruction + validation; `gptr_check()` rejects adapters sending a list `tool_choice` when the capability is `FALSE` [07 §2.5-2.6] | fid-14 |
| OAuth | refuse AS metadata without `code_challenge_methods_supported` or without S256; validate `iss` (RFC 9207) when advertised; own callback reader keeping `iss`; state and redirect checks; negative mock cases in P18 [16 §4 item 8, fact-check] | fid-17 |
| frontmatter | scalars of the string keys (`name`, `description`, `version`, `model`, `tools`, `argument-hint`) keep their source text (YAML 1.1 turns `yes`/`on`/`1.0` into logicals and numbers; verified) | fid-19 |
| describers | methods for classes of packages outside Suggests (Matrix, SeuratObject, SingleCellExperiment, arrow, ggplot2) use only base generics, `methods::slot()`/`slotNames()`, `attr()`, `dim()`, guarded by `isNamespaceLoaded()`; never `pkg::fun()` | cran-21 |
| compaction floor | at freeze the post-compaction floor (static prefix + project instructions + re-injection budgets + 634) is compared with the threshold; if it is not below it, skill and project re-injection budgets are cut to 25% of the threshold, and if still not below, the model is refused for the preset with `gptr_error_invalid_argument` suggesting `preset = "minimal"` or `context = "names"`; after a threshold compaction, further threshold compactions wait until the context grew by 20% of the window | safe-20 |
| concurrent writers | read-modify-write of `auth.json`, settings, trust, MCP and user-level project files (and the OAuth refresh) under one short `mkdir` lock (`<file>.lock/`, pid + creation time, 50 x 100 ms retries); a lock is stale when `pid_alive()` is `FALSE` or it is older than 30 s, never when it has vanished (the taker retries); checkpoint blob GC prunes only blobs unreferenced by every session file of the project and older than `gptr.checkpoint_days`, and skips while another live pid holds a session lock in the project | safe-17 |
| artifact access | each launch gets a 128-bit token (`openssl::rand_bytes(16)`, else `/dev/urandom` on Unix; on Windows without openssl no token and a notice); the wrapper app rejects sessions whose URL lacks `gptr_token=<hex>`; the handle's URL carries it; static checks flag reads of `secret_file` paths at level 3 | safe-22 |
| knobs | one knob per limit: options `gptr.subagents.max_depth`, `.max_active`, `.max_workers`, `.max_cli`, `.max_tasks` mirror the settings keys; `gptr.max_active` is HTTP transfers only; `gptr_parallel(max_active = NULL)` defaults to `gptr.subagents.max_active` | cons-20 |
| enums | message `source` in `prompt`, `pipe`, `steer`, `follow_up`, `repl`, `parent`, `replay`, `extension`, `agent`, `imported`; `child_env` resolves `first`; `project_trust` is a first decision everywhere and `gptr_trust()` emits nothing; the `egress_ack` message is P08's | cons-20 |
| names | `setting_get()` is the only reader; `settings_get()` is the `settings.get` implementation; `ns.resolve`; `check_adapter()`; `fake_classify(model, state, questions, opts)` | cons-17 |
| Suggests generics | `vctrs` methods registered lazily as before; `pkgload::load_all()` appears only inside the generated child-script text of `helper-tracemem.R`, never as package or test code | cons-23 |
| `gptr_last()` | `the$last` holds the most recent session **strongly** (a shell holds no frames or user objects, so this is copy-safe under R1/R2); the live index stays weak; a replaced session is released normally (a weak reference was collected at the first `gc()`, verified) | cons-12 |
| `03` drift | the signature blocks of `03` (reactor, evaluator, messages, tool result, session fields) point to this contract; `03`'s manifest example provides `"trials/search"`; `tool_call` fails closed with **block**; the deprecation class is `gptr_warning_deprecated`; the settings key is `tools.presets`; the experimental kinds include `route` | cons-18 |
| fixture servers | the base-R SSE mock stays on `serverSocket()` (it needs raw streaming; `serverSocket()` has no host argument and listens on every interface, reproduced), runs only under `skip_on_cran()` for one test, and answers only requests whose path carries a per-run token; the MCP fixture's HTTP transport and `gptr_mcp_serve()` bind `127.0.0.1` through httpuv | cran-18 |
| stale figures | the PIPEWAIT evidence is the fact-check's (default pool 4.94-5.11 s, streams fully serialised; fixes 1.25-1.36 s); "`later_fd` cannot watch processx pipes on Windows" is LIKELY (inferred, untested) [15 fact-check] | fid-21 |

**IC-72 DESCRIPTION, lint and conventions.** (cran-4, cons-14, cran-22, cons-13, cran-12, cran-13, cran-14, fid-10,
req-21, cons-19, cran-16)

- P01 writes, once: `Authors@R` with the maintainer (as in the current DESCRIPTION) in roles `aut`, `cre`, `cph`,
  plus `person("Mario", "Zechner", role = c("ctb", "cph"), comment = "Author of 'pi' (MIT), from which tool texts
  and templates are derived")`; `Copyright: file inst/COPYRIGHTS` (Pi, models.dev, the gitleaks-derived patterns);
  `URL`, `BugReports`, `Language: en-US`; `ps` in Imports. No `VignetteBuilder` before vignettes exist (a
  `VignetteBuilder` without vignettes gives a NOTE, verified): P25 adds `VignetteBuilder: knitr` together with the
  vignettes, a named exception to "Version is the only DESCRIPTION field P25 may change". P01 acceptance asserts
  these fields.
- Expected check result at every milestone: 0 errors, 0 warnings, and no NOTE apart from the incoming-feasibility
  NOTE naming the maintainer (gptr 0.7.0 is on CRAN, so 1.0.0 is an update and gets no "New submission" NOTE).
  P25 runs `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` on submission day and records the
  result in `cran-comments.md`.
- `.lintr`: `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100)`,
  `object_name_linter(styles = "snake_case", regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$"))`
  (lintr 3.3.0.1 flagged `<<-` and those S3 methods, verified). `test-lint-rules.R` finds `<-` through
  `getParseData()` `LEFT_ASSIGN` tokens, not a text regex (which would flag `` `$<-.gptr_session` ``), and adds the
  rules: bare `enc2utf8(` outside `utils-encoding.R`; `tools::pskill(`; `RNGkind(`; `.Random.seed` assignment
  outside `rng_swap()` and `with_seed_preserved()`; `httpuv::randomPort(`; `withr::` in `R/`; a bare `"R"` or
  `"Rscript"` command in `proc_spawn()`/`proc_run()`.
- `.Rbuildignore` adds `^CLAUDE\.md$`, `^AGENTS\.md$` and `^\.claude$`.
- Conventions: non-ASCII characters in R sources are written as `\u` escapes (for example `"\u00e9"`), which are
  marked UTF-8 in every locale, so `intToUtf8()` is not needed; `@examplesIf` predicates use the fake provider or
  `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` (there is no `gptr_has_key()`); package code restores state with
  `on.exit(..., add = TRUE)` right after the change and uses withr only in tests; `:::` is never used in `R/` and
  tests need none; the complete condition-class list is §2.2 of this contract; the layout lists `R/aaa-state.R`,
  `inst/templates/` and `inst/extdata/`; `LICENSE.md` is P01's; "files the package writes" adds documents the
  user named or confirmed and tool writes approved by the permission mode, and nothing by default in
  non-interactive runs.
- The register's D-28 says 63 exports.

**IC-73 Benchmarks and token accounting.** (plug-5, plug-7, plug-17, plug-18, req-34)

- P01's CI gains a `bench` job that installs rtiktoken (a development tool) and runs `Rscript --vanilla
  dev/bench/tokens/run.R --check` once the runner exists.
- The golden-transcript runner (`dev/bench/tokens/run.R`) and the NS-2/NS-3 fixtures move to P07 (M1); P10, P13,
  P15, P18, P19, P22 and P23 each add their NS fixture and baseline rows in their acceptance; P24 covers every
  gate of `03` §12.7 (prefix +2%, input and output +5%, request count and image tokens +0, describer facts no
  loss, catalogs +5%) and adds `tests/testthat/test-s11-conformance.R`: a fixture plugin registers one record of
  every kind and the test asserts that each is used at run time.
- P25's release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against one Anthropic and one OpenAI model
  and records request counts (within +2 of the golden transcript) and input tokens (within 20%) in
  `dev/bench/tokens/live-<date>.csv`; the golden transcripts script the agent, so they measure harness potential,
  and the live run measures behaviour.
- `tools.presets` ships defaults `{"google/gemini-3*": "extended", "anthropic/claude-haiku-4-5*": "extended"}`,
  applied only when the catalog's `cache_min` exceeds the projected standard prefix (o200k estimate times the
  provider prior) and the session is expected to pass break-even (interactive sessions and fan-out children).
- `03` §12.1 and §12.8 report o200k and projected Claude tokens (x1.35 prior, range 1.3-1.6); budgets are in
  o200k-estimated units scaled by the session multiplier. `03` §12.4 gains rows for every new cost of this
  section: `!expr` notes (budget 300, the `workspace_changes` rules), tool additions after a plan -> auto switch
  (the edit and write schemas as a `tool_addition`, about 480 tokens), router switches, `ask` in non-interactive
  manual runs (+145), the `trusted="false"` sentence (+35), the Claude-CLI route's own framing beyond gptr's
  frozen prompt (UNCERTAIN until the live suite measures it), and the gptr MCP schemas Codex receives (four tools,
  about 700 tokens per turn inside its 19-38K).

**IC-74 Local Ollama chat and native decisions (2026-10-03).**

`07-local-ollama.md` is normative and incorporated in full. It takes precedence
over conflicting earlier sections, including this section's older amendments,
and over literal plan examples. It adds REQ-13a without changing the core Imports.
P05/P08 dispatch from model-level `type`/`api`; Ollama's chat and classifier
models share a provider but use different adapters. P13 owns `s1-ollama.R`,
the `ollama-system-one` classifier adapter and corresponding conformance tests.
The canonical answer contract, image option and cache identity, unknown
calibration state, local-only protection, model discovery, usage accounting,
and plan ownership/acceptance are specified there. Hosted Jev remains supported;
Ollama requires no Jev key and is not a structured-chat emulation fallback.
