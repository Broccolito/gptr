from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""| 0 | read-only R, reads inside the project, namespace reads | allow | allow | allow | allow |
| 1 | new objects, reads outside the project | R in a scratch child env (discarded); other tools deny | ask | ask | allow |""",
"""| 0 | **known** read-only R (level 0 means "known read-only", not "nothing flagged"), reads inside the project, namespace reads | allow | allow | allow | allow |
| 1 | new objects, reads outside the project, calls of unlisted functions from packages outside base/stats/utils/methods/graphics/grDevices/tools [IC-54] | only allowlisted read-only calls run, in a scratch child env (discarded); anything else and other tools deny | ask | ask | allow |"""),
("""| 4 | critical: `q()`, deleting home/root/project/top-level/drive roots or their parents, secret + network sink | deny | ask | ask | ask (blocked without a UI) |""",
"""| 4 | critical: `q()`, deleting home/root/project/top-level/drive roots or their parents, secret + network sink; the `control` category (gptr's own configuration exports, `options(gptr.*)`, control-plane files [IC-53, IC-54]) | deny | ask_human | ask_human | ask_human (blocked without a UI) |"""),
("""`r` is classified per flagged call by `gptr_risk()` (tables in `inst/extdata/risk-functions.csv` and
`risk-commands.csv`, extendable by plugins);""",
"""`r` is classified per flagged call by `gptr_risk()` (tables in `inst/extdata/risk-functions.csv` and
`risk-commands.csv`, extendable by additive `risk_rule` records; a shipped risky-package list (targets, usethis,
devtools, renv, pak, remotes, fs, gert, git2r, gh, googledrive, pins, `aws.*`, `paws.*`, DBI write verbs, httr/
httr2/curl request performers) is at least level 2 [18 §2.5 and §7 item 1; IC-54]); gptr's own exports that change
harness state (`gptr_config`, `gptr_permissions`, `gptr_trust`, `gptr_register`, `gptr_on`, `gptr_mcp_add`, ...)
are level 4 `control` and also check `run_current()` [IC-53]; writes to control-plane paths (`.gptr/settings*.json`,
`mcp.json`, `extensions/`, `plugins/`, `SYSTEM.md`, `agents/`, the user config directory, `.Rprofile`,
`Makevars`, git hooks) are level 4 and to instruction files (`AGENTS.md`, `CLAUDE.md`, `vignette.Rmd`, skills,
prompts) level 3 [IC-54];"""),
("""`perm_check(call, run)` (in `agent-dispatch.R`, P06; the built-in policies are P11's `perm-gate.R`) ->
`list(decision = "allow" | "deny" | "ask" | "modify", reason, input, risk)`:
every `policy` record (deny > ask > modify > allow; a throwing policy denies) -> `permission_request` hooks
(first decision; a System 1 reviewer plugin may answer an ask) -> the UI backend.""",
"""`perm_check(call, run)` (in `agent-dispatch.R`, P06; the built-in policies are P11's `perm-gate.R`) ->
`list(decision = "allow" | "deny" | "ask" | "ask_human" | "modify", reason, input, risk)`:
every `policy` record (deny > ask_human > ask > modify > allow; a throwing policy denies; with no active `mode`
policy the decision is ask, fail closed) -> for `ask` only, `permission_request` hooks (first decision; a System 1
reviewer plugin may answer) -> the UI backend. `ask_human` (level 4, the secret guard, the control category and
paths, first use of a CLI route, the egress acknowledgement) goes only to a UI whose `has_ui()` is true in the
run's snapshot; a hook's allow is ignored with a diagnostic [IC-53]. The run snapshots the safety options
(`gptr.ui`, `gptr.interactive`, the guards, `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode`) at its
start, so model code cannot change them mid-run. A `modify` is re-classified and re-checked once."""),
("""status*)`, `r(sql:select)`), `critical_guard`, `secret_guard`, `protect_size`. Allow rules never loosen plan
and never pre-approve level 4; project settings may only tighten; project filters cannot disable user or
built-in policies or hooks [G1 §3.6]. `modify` changes the arguments the tool sees and is recorded.""",
"""status*)`, `r(sql:select)`), `critical_guard`, `secret_guard`, `protect_size`. Allow rules never loosen plan
and never pre-approve level 4; only `r(secret:NAME)` rules pre-approve the secret guard; project settings may
only tighten; no filter from any source disables `builtin:permissions`, `builtin:plan` or the two guards, and
inside a run filters that remove policies or hooks are refused [G1 §3.6; IC-53]. Every call made while a run is
active inherits the running mode (only tightened) whatever its route, and the parent re-classifies every
permission request forwarded by a worker (the worker backend is not an isolation boundary). `modify` changes the
arguments the tool sees and is recorded."""),
("""One line (NS-1): `allow? [y]es / [a]lways / [n]o / [?]`. `a` adds a session rule covering exactly the flagged
calls (`r(fn:FindNeighbors,FindClusters)`); `?` opens the detail view (code, flagged calls with levels, paths,
"cannot be undone" when no checkpoint is possible, and "always in this project", written to
`.gptr/settings.local.json`);""",
"""One line (NS-1): `allow? [y]es / [a]lways / [n]o / [?]`, listing every flagged call and `+N more lines`, with C0/C1
controls, bidi and zero-width characters escaped as `<U+XXXX>` [IC-53]. `a` adds a session rule covering exactly the
flagged calls (`r(fn:FindNeighbors,FindClusters)`); `?` opens the detail view (code, flagged calls with levels,
paths, "cannot be undone" when no checkpoint is possible, and "always in this project", written to the user-level
project file `R_user_dir("gptr", "config")/projects/<hash>.json`, never into the project tree [IC-52]);"""),
("""An `ask` with no human stops the run with `status = "blocked"` and a classed `gptr_error_permission` stating
the action and how to allow it (`mode = auto`, a rule, or `gptr_permissions()`); the session is attached to
the condition. `options(gptr.noninteractive_ask = "deny")` returns a denial to the model instead [P-A §6.7].
Plan mode (`mode = plan`) uses the `readonly` preset: `read`, and `r` evaluated in a scratch
`new.env(parent = envir)` where level-1 code may run and nothing persists; writes are denied.""",
"""An `ask` with no human stops the run with `status = "blocked"` and a classed `gptr_error_permission` stating
the action and how to allow it (`mode = auto`, a rule, or `gptr_permissions()`); the session is attached to
the condition. `options(gptr.noninteractive_ask = "deny")` returns a denial to the model instead [P-A §6.7]. In a
non-interactive `manual` run the `ask` tool stays declared (+145 tokens), and calling it stops the run with status
`blocked` and `gptr_error_noninteractive` carrying the questions (NS-12: "stops with a clear error instead of
guessing") [IC-68]. Plan mode (`mode = plan`) uses the `readonly` preset: `read`, and `r` evaluated in a scratch
`new.env(parent = envir)` where only calls known to be read-only run (an allowlist; anything else is denied as
"not known to be read-only in plan mode" [IC-54]) and nothing persists; writes are denied; plan-mode code is never
recorded in documents [IC-48]."""),
("""**pending plan**. The next non-plan `gptr()` call in the same environment (matched by an address string, never
a reference, R2) within the same R process and one hour receives it once as a `<plan>` block, with the notice
"using the plan from session <id>", and its block header records `plan=<id>`.""",
"""**pending plan**. The next non-plan `gptr()` call in the same environment (matched by an address string, never
a reference, R2) within the same R process and one hour receives it once as a `<plan>` block, with the notice
"using the plan from session <id>" and the plan's step list printed before the first action, and its block header
records `plan=<id>`; only a top-level call (not nested, not in a run, not in a loop body) may consume it, and any
other `gptr()` call in between discards it [IC-56]."""),
("""  settings.json                        project settings (committed; applied only when trusted; may only tighten)
  settings.local.json                  remembered permission answers, transcript target (gitignored)
  .gitignore                           sessions/, cache/s2/, cache/tmp/, checkpoints/, artifacts/*/v*/data/,
                                       artifacts/*/run/, *.lock/, settings.local.json""",
"""  settings.json                        project settings (committed; beyond tightening applied only when trusted)
  settings.local.json                  legacy only: deny/ask additions, only when trusted [IC-52] (gitignored)
  .gitignore                           sessions/, cache/s2/, cache/tmp/, checkpoints/, artifacts/*/v*/data/,
                                       artifacts/*/run/, locks/, *.lock/, settings.local.json, transcripts/"""),
("""  cache/s1/<2hex>/<sha256>.json        System 1 answers keyed by input hash (committed by default; no inputs)""",
"""  cache/s1/<2hex>/<sha256>.json        System 1 answers keyed by salted input hash (committed by default; no inputs,
                                       no question text [IC-70]); cache/s1/salt holds the per-project salt"""),
("""  cache/tmp/                           spill files (pruned after 7 days)""",
"""  cache/tmp/                           spill files and per-session wire logs (pruned after 7 days); deferred-write
                                       sidecars (never pruned automatically [IC-51])"""),
("""  transcripts/gptr-session-<ts>.R      console transcripts when no document is bound
tools::R_user_dir("gptr", "config")    settings.json, auth.json (0600), trust.json, mcp.json, egress acks
tools::R_user_dir("gptr", "cache")     refreshed model catalog (ETag), pruned by gptr_cache("prune")""",
"""  transcripts/gptr-session-<ts>.R      console transcripts when no document is bound (gitignored by default)
tools::R_user_dir("gptr", "config")    settings.json, auth.json (0600), trust.json (with trust fingerprints),
                                       mcp.json, egress acks, projects/<hash>.json (per-project remembered answers,
                                       transcript target, record consent [IC-52])
tools::R_user_dir("gptr", "cache")     refreshed model catalog (ETag), MCP tool and era caches, procs/ (tree
                                       markers for the orphan sweep), pruned by gptr_cache("prune")"""),
("""One kept-open `file(path, "ab")` connection per session; each entry is one line appended inside
`suspendInterrupts()` and flushed; ids from `utils-hash.R` never touch `.Random.seed`; the reader tolerates a
torn last line;""",
"""Open, append, close: each entry (or each batch at a turn boundary) is appended through `file(path, "ab")` opened,
written, flushed and closed inside `suspendInterrupts()`, so no R connection outlives a gptr call (R allows 125
user connections, and `--as-cran` examples fail with "connections left open"; both reproduced) [IC-59]; ids from
`utils-hash.R` never touch `.Random.seed`; a resume on a file whose last byte is not LF first appends `"\\n"` and a
`gptr.recovered` entry, and the reader skips any unparsable line with a diagnostic and re-parents its children;
the pid lock records the process creation time, is checked with `ps` and is touched every 10 minutes;"""),
("""Top-level calls only (not nested in functions, loops, `if` or braces, and not inside an agent block) own the
run of blocks immediately after their statement:""",
"""Top-level calls only (not nested in functions, loops, `if` or braces, and not inside an agent block) own the
run of blocks immediately after their statement (a `gptr()` statement directly inside an agent block is a
*block-nested* call, replayed from the S2 cache [IC-47]):"""),
("""Header keys: `model`, `date`, `prompt` (12-hex hash of the prompt *template*), optional `sha` (body hash for
user-edit detection), `call` (k-th call of a pipeline), `tokens`, `cost`, `session`, `turn`, `value` (the
designated name), `fork=<parent>:<turn>`, `plan=<id>`, `status=undone`. The body holds successful
`record = TRUE` code verbatim, `#>` outputs (12 lines max), `## Decision:` notes, bridge digests (`#> sh git
status --porcelain: exit 0, 6 lines`) and artifact paths. Overlay-fork turns replay inside
`local({ ... }, envir = gptr_resume("<id>")$envir)` so they never clobber the workspace.""",
"""Header keys: `model`, `date`, `prompt` (12-hex hash of the prompt *template*), `args` (8-hex hash of the
interpolated values, so a parameterised report never replays another parameter's block [IC-45]), optional `sha`
(body hash for user-edit detection), `call` (k-th call of a pipeline), `tokens`, `cost`, `session`, `turn`,
`value` (the designated name), `fork=<parent>:<turn>`, `plan=<id>`, `kind`/`children` (team and fan-out blocks
[IC-47]), `status=undone`. The body holds successful `record = TRUE` code (top-level `gptr_return()` calls and
calls of `record = FALSE` members such as `gptr$out()` dropped, top-level `<-` rewritten to `=` where safe
[IC-48]), `#>` outputs (12 lines max), `## Decision:` notes, `## Steer:`/`## Follow-up:` lines for steering during
the turn [IC-49], bridge digests (`#> sh git status --porcelain: exit 0, 6 lines`) and artifact paths. Overlay-fork
turns replay inside `local({ ... }, envir = gptr_resume(block = "<block id>")$envir)`, which finds the fork that
replay created for that block and never falls back to the caller's frame, so they never clobber the workspace
[IC-46]. A top-level team or fan-out statement owns one block with a line per child and, for children with
exports, their code in child overlays plus one assignment per export [IC-47]."""),
("""[14 fact-check]) and never while the notebook is open. A top-level System 1 call gets a one-line block""",
"""[14 fact-check]) and never while the notebook is open (in Jupyter the block is shown as the cell output and kept
pending until `gptr_doc(path, sync = TRUE)` [IC-50]). A top-level System 1 call gets a one-line block"""),
("""retry; IDE buffers go through rstudioapi with ids (Positron: disk write when the buffer is clean); under
Rscript writes are deferred to `reg.finalizer(onexit = TRUE)` with a crash sidecar. Every write passes the
`document_write` event (fail closed, patchable). gptr writes only documents the user designated or confirmed:
`gptr_doc()`, an interactive yes, or `record = "auto"` in trusted settings; non-interactive runs without a
workspace never write documents.""",
"""retry (with rename retries and an in-place fallback on Windows, and case-insensitive path keys on Windows and
macOS [IC-51]); IDE buffers go through rstudioapi with ids (Positron: disk write when the buffer is clean); under
Rscript writes are deferred to `reg.finalizer(onexit = TRUE)` with a sidecar of block upserts flushed after every
settled call and re-applied through the md5 path by the next gptr call that touches the document (SIGTERM skips
finalizers) [IC-51]. Every write passes the `document_write` event (fail closed, patchable). Replaying needs no
consent; **writing** does, checked only when a block is written: `gptr_doc(path)` in this process (any call,
console or script), `options(gptr.record = "auto")` or user-scope `record = "auto"`, or an interactive yes
remembered per document at user level; `record` is a tighten-type setting, so a project can only turn it off
[IC-45]; non-interactive runs without such consent never write documents."""),
("""**Replay modes** (`replay =`, `options(gptr.replay)`, `GPTR_REPLAY`): `auto` (default: a fresh recorded block
is replayed, a missing or stale one runs), `replay` (never call models; a missing block errors
`gptr_error_not_recorded`), `live` (ask afresh and regenerate), `record` (regenerate stale blocks). `gptr()`
never executes a recorded block: in replay it returns a replayed session with zero tokens (answer text from
the S2 cache when present; conversation positioned at the recorded turn of the session file) and the
document's own code runs next.""",
"""**Replay modes** (`replay =`, `options(gptr.replay)`, `GPTR_REPLAY`): `auto` (default: a fresh recorded block
is replayed, a missing or stale one runs), `replay` (never call models; a missing block errors
`gptr_error_not_recorded`), `live` (ask afresh and regenerate), `record` (regenerate stale blocks). `gptr()`
never executes a recorded block: in replay a piped session is advanced **in place** (turn, `seen`, value, text:
`identical()` holds along a replayed pipe chain), otherwise it returns a replayed session with zero tokens whose
history comes from the session file truncated at the recorded turn, or is reconstructed from the document when the
file is absent (a fresh clone; `history_source = "reconstructed"`) [IC-46]; the document's own code runs next."""),
("""downgrade to replay with a warning. Replay is forced when `_R_CHECK_PACKAGE_NAME_` is set and in vignette
builds [13, 14 §4.4.2]. Nested calls have no block: they run live on re-source, or fail with "not recorded"
under `replay`.""",
"""downgrade to replay with a warning. Replay is forced when `_R_CHECK_PACKAGE_NAME_` is set outside testthat (the
examples of R CMD check; tests use offline fake and mock providers and may pass `replay =`) [13, 14 §4.4.2; IC-45].
Calls nested in loops and functions have no block: they run live on re-source, or fail with "not recorded" under
`replay`; block-nested calls and team children replay from the S2 cache [IC-47]."""),
("""**Console transcripts.** An interactive session without a bound document asks once per project where to record
(the IDE's active document, a new `.gptr/transcripts/gptr-session-<ts>.R`, or nowhere), remembered in
`settings.local.json`. Direct R lines (`!expr`) are recorded as `# direct R (no model)` with `#>` output.""",
"""**Console transcripts.** An interactive session without a bound document asks once per project where to record
(the IDE's active document, a new `.gptr/transcripts/gptr-session-<ts>.R`, or nowhere), remembered in the
user-level project file and validated (inside the project, an R/Rmd/qmd/ipynb file, not a control path) [IC-52].
The first prompt is recorded as `s_<hex> = gptr("...")` and later prompts as `s_<hex> |> gptr("...")`, so the
transcript re-sources as one steered session (S-8) [IC-49]. Direct R lines (`!expr`) are recorded as
`# direct R (no model)` with `#>` output."""),
("""**Caches.** S1: per element, key `sha256(canonical_json(endpoint, model, question, type, criteria, input))`,
stores the input hash and the answer, never the input; memory before `gptr_init()`. S2: answer text keyed by
(document, block, prompt hash), redacted at ingress, gitignored by default (privacy over Quarto-style
commit) [C-31].""",
"""**Caches.** S1: per element, key `sha256(canonical_json(salt, endpoint, model, question, type, criteria,
input))` with a committed per-project salt, storing the salted input hash, the question's hash and the answer,
never the input or question text (low-entropy inputs are otherwise reversible by dictionary [IC-70]); memory before
`gptr_init()`. S2: answer text keyed by (document, block, part, prompt hash, args hash), redacted at ingress,
gitignored by default (privacy over Quarto-style commit) [C-31]."""),
]
apply(P, pairs)
