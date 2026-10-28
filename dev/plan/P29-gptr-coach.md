# P29 Coached harnesses: `gptr_tailor()` and `gptr_coach()` (2026-10-28)

**Goal:** Build the design in `dev/spec/08-recursive-peter.md` (revision 4, names revised
2026-10-28). It adds two exports:
- `gptr_tailor()` builds a *harness*: a function called exactly like `peter()`, carrying fixed
  `peter()` arguments, the person's own rules, and *coaching* data (note, skills, review, rules).
- `gptr_coach()` improves a harness by running the task in separate R processes. It follows
  Harness²'s propose, probe, compose loop, and code decides whether the result is kept.

Both work on API keys and on Claude Code and Codex subscription plans. Harness calls and coaching
calls are recorded in documents and replay without a model.

**Authority:** `dev/spec/08-recursive-peter.md` is the design. Where this plan and 08 disagree, 08
wins unless a decision below says otherwise. Each task amends 04 (new section 15.11, IC-83 onward)
and 03 for the surfaces it builds.

**Depends on:** P01-P28 (merged). **Milestone:** post-M5 feature, before CRAN submission.

## Global constraints

`dev/plan/00-conventions.md` applies in full: house style (`=`, `|>`), simplicity first
(section 11), no new Imports or Suggests, pure R, offline tests with `gptr_fake_provider()`, never
`.GlobalEnv` by name, and every option, working directory, seed and environment variable
restored. Plan-specific rules:
- Run R as `R_LIBS=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla` (D-002's isolated tool
  library, added to the default ones).
- Do not run `devtools::document()` inside a task. The integrator regenerates `NAMESPACE` and
  `man/` once per wave, so parallel tasks never race on generated files.
- Do not commit inside a task. The integrator commits each task with its own conventional
  message.
- Edit only the files your task owns (table below). If you must touch another task's file, change
  only the function named in your task, and say so in your report.
- Live tests run only with `GPTR_LIVE_TESTS=true` and are skipped otherwise (`skip_if_not_live()`
  or the existing helper).

## File ownership

| Path | Task |
|---|---|
| `R/skill-discover.R`, `R/tool-read.R`, `R/ext-specs.R` (skill spec only), `R/gptr-gateway.R` | T1 |
| `R/perm-classify.R`, `inst/extdata/risk-commands.csv`, `inst/extdata/risk-functions.csv` | T2 |
| `R/agent-dispatch.R`, `R/ext-registry.R`, `R/subagent-worker.R` (registry only) | T3 |
| `R/provider-registry.R` (`provider_stream()` gate only) | T4 |
| `R/cli-claude.R`, `R/cli-codex.R`, `R/cli-common.R`, `R/auth-childenv.R`, `R/agent-run.R` (`run_retryable()` only), `inst/gptr/codex_hook.R` | T5 |
| `R/gptr-tailor.R` (new) | T6, then T10 |
| `R/gptr-child.R` (new), `R/proc-rscript.R`, `R/mcp-server.R` (blocked runs only) | T7 |
| `R/doc-*.R`, `R/env-history.R` | T8 |
| `R/gptr-coach.R` (new) | T9, then T11 |
| docs, `NEWS.md`, `_pkgdown.yml`, `dev/spec/0[34]-*.md`, `dev/DEVIATIONS.md`, `dev/progress/P29.md` | integrator |

Tests mirror the files (`tests/testthat/test-<file>.R`). A task may add to an existing test file
of a file it owns.

## Shared internal interfaces

These names are fixed so that parallel tasks fit together. A task that needs to change one says
so in its report.

1. **Skill specs with text (T1).** `gptr_spec("skill", name, description = d, text = t)` is valid
   with `text` instead of `path`. Skill lookup sees the calling session's records, and a skill
   body is its `text` when present.
2. **Keyed factories (T1).** A function factory with attribute `gptr_key` (a string) is loaded at
   most once per session by `gateway_register()`.
3. **Classifier (T2).**
   - `risk_classify_r()` results carry `calls` (chr, every function the code calls) and `targets`
     (`list(files = chr)`), including those of workspace functions read through `read_user()`.
   - A call to a function inheriting `gptr_harness` is classified as `peter`.
   - Overwriting or modifying a binding that holds a `gptr_harness` is a control action.
   - `R CMD INSTALL` is category `install`.
4. **Policies (T3).** Policy collection includes the rank-0 policies of every ancestor session
   (follow the parent chain). `worker_registry()` receives the same ancestor ids. `nested_rules()`
   evaluates every policy named `rules`, `coaching` or `harness_rules`, keeps the strictest
   answer, and also checks nested `write` and `edit` calls.
5. **Model gate (T4).** `provider_stream()` calls `model_gate_check(model)`. That function does
   nothing unless `the$model_gate` holds a function, which it then calls with the resolved model
   record. The function may abort with class `gptr_error_model_refused`.
6. **Model kinds and plan routes (T5).**
   - `coach_model_kind(model)` returns one of `"api"`, `"fake"`, `"claude"` or `"codex"`, or
     aborts with class `gptr_error_model_refused` naming the reason: `router`, `classifier`,
     `process`, `cli_version` or `cli_preflight`.
   - `the$coach_role` (`NULL`, `"run"` or `"coach"`) switches the CLI adapters to the confined
     argv and the per-session checks of 08 section 3.7.
   - `coach_cli_env(kind)` returns the login variables to pass to a child.
   - A failed check aborts with class `gptr_error_cli_check`.
   - A plan limit aborts with class `gptr_error_plan_limit`, carrying the field `resets_at`
     (text).
7. **Harness object (T6).**
   - `gptr_tailor(x = peter, ..., rules = NULL, coaching = NULL, dir = NULL)` returns a function
     of class `c("gptr_harness", "function")` with attribute `gptr_harness` set to
     `list(args, rules, coaching, record, id, gptr)`.
   - `harness_spec(h)` returns that list, or an empty spec for `peter`.
   - `harness_from_spec(spec)` rebuilds a harness.
   - `coaching_validate(coaching, surface = NULL)` returns the normalised coaching or aborts with
     class `gptr_error_coaching`.
   - `coaching_hash(coaching)` returns 8 hex characters; empty coaching has one constant hash.
   - The rewritten call carries attribute `gptr_harness = list(fn, hash, call)`.
8. **Child runner (T7).**
   - `coach_run_jobs(jobs)` (in `R/gptr-child.R`, area `gptr`, layer L6, so it may call
     the worker helpers and the harness code) runs each job in its own R process through the new
     `child` bootstrap entry. It returns one plain-data result per job, in order.
   - Each job is `list(id, role = "run" | "coach" | "judge", spec, prompt, objects, args, model,
     schema)`. `spec` is a harness spec; `objects` is a named list; `args` are resolved `peter()`
     argument values; `schema` is for coaches and the judge.
   - Each result is `list(id, status, reason, text, turns, usage, transcript, first_user, risk,
     refusals, unmet, files, plan, limit, checks, error, value, objects)`, plain data only (the
     review fixes added `first_user` and moved `value` and `objects` last; D-279).
   - `plain_encode(x)` and `plain_decode(json)` implement 08 section 3.3's JSON shape.
9. **Coaching factory (T6, extended by T10).** `harness_factory(spec)` returns a keyed factory that
   registers the note section, the skills and the finish hook. T10 adds the `never` and
   `harness_rules` policies and the `require` part of the finish hook.
10. **Recording (T8).** Harness-call blocks use the call attribute in item 7. Two services are
    registered by `builtin:documents`:
    - `doc.coach(call)` returns the document decision for a coaching call: replay a fresh block,
      record, or neither;
    - `doc.coach_block(site, harness, record)` writes the coach block.

    T9 calls them.

## Tasks

Each task: write the failing tests first, then the code; run the task's test filter and the
neighbouring files' tests; run lint on the files you changed. Report what you changed, the test
counts (`[ FAIL 0 | WARN 0 | SKIP n | PASS m ]`), and anything left open.

### Wave 1 (parallel)

- **T1 Skills with text, keyed factories** (08 sections 3.1 and 3.2; P29a). Interfaces 1 and 2.
  Tests:
  - a session skill with text is listed and opens through `read`, in that session only;
  - a keyed factory loads once across continuations.
- **T2 Classifier** (08 sections 3.1, 3.2 and 3.3; P29a). Interface 3. Tests:
  - `calls` and `targets` for `write.csv`, `peter$write`, `system("cp ...")`, `peter$sh(...)` and
    a helper defined earlier;
  - a harness call is level 1, category network, like `peter`;
  - rebinding a harness is level 4;
  - `R CMD INSTALL` through `system()` and `peter$sh` is category `install`.
- **T3 Policies reach sub-agents** (08 section 3.2, "Reach into sub-agents"; P29a). Interface 4.
  Tests: a person's `extensions =` policy denies the same call in a nested `peter()`, a team
  member, a fan-out child and an inline sub-agent; nested shell and nested write calls consult
  every rules-like policy, and the strictest answer wins.
- **T4 Model gate** (08 section 3.3; P29a). Interface 5. Tests: no gate means no change; a gate
  that aborts stops `provider_stream()` before any request, for chat calls and System 1
  emulation.
- **T5 Plan routes** (08 sections 1.5 and 3.7; P29e). Interface 6.
  - `coach_model_kind()`, with its preflight: a minimum version, plus `codex features list`, which
    must show every switched-off feature as off and `hooks` as on.
  - Claude Code with `the$coach_role`:
    - the extra flags and environment variables;
    - never resume;
    - the `init`, stream and result checks;
    - `.opts$returns` honoured through the returns instruction;
    - an interrupt when a run is blocked.
  - Codex with `the$coach_role`:
    - the confined argv, always read-only;
    - never `exec resume` (a fresh exec carries the whole history);
    - the hook script `inst/gptr/codex_hook.R` (deny or allow, log denials, a start line);
    - the event checks, accepting `error`-type warning items;
    - `--output-schema` in strict form;
    - `cli_auth_credentials_store` passed through.
  - `coach_cli_env()`.
  - Limits:
    - detect them and abort with `gptr_error_plan_limit`;
    - `run_retryable()` stops retrying weekly and model-family limits;
    - read the overage fields.

  Offline tests use gptr's fake CLI fixtures. Write the live tests too, but leave them to the
  integrator to run.

### Wave 2 (after wave 1 is integrated)

- **T6 `gptr_tailor()` and the harness object** (08 sections 3.1 and 3.2, without `rules`; P29b).
  Interfaces 7 and 9:
  - the call rewrite;
  - merging fixed arguments;
  - `$coaching`, `$record` and `$report`;
  - `print()`;
  - `dir =`;
  - coaching validation and the text checks;
  - the note section, skills and the review finish hook;
  - `gptr_tailor(readRDS(f))`;
  - the control row and `session_control_check()`.

  Until T10 lands, a `rules` surface and `gptr_tailor(rules =)` are refused with a named reason.
- **T7 Child runner and JSON transport** (08 section 3.3; P29c). Interface 8, in `R/gptr-child.R`:
  - the `child` bootstrap entry, reusing the worker's spawn, kill, cleanup, registry snapshot and
    fake revival;
  - the run folder and project root;
  - the process-wide fence;
  - the event stream with its own line reader;
  - `plain_encode()` and `plain_decode()` with exact doubles;
  - the safe-direction reading;
  - the scheduler on the worker pool, with at most 2 plan sessions per account;
  - coach sessions with no registry and no tools;
  - login variables through `coach_cli_env()`, unset from R's environment in run children.
- **T8 Recording** (08 sections 1.10 and 3.6; P29b and P29d):
  - harness-call heads, attribute and freshness;
  - the notebook sidecar codec;
  - the `doc.coach` and `doc.coach_block` services;
  - safe literal writing;
  - the closed walker for replay;
  - `kind = coach` freshness;
  - transcript definitions;
  - `gptr_export()` refusing coach blocks;
  - `replay_guard()` before any process starts.

### Wave 3

- **T9 `gptr_coach()` at `k = 1`** (08 sections 1.3 to 1.7 and 3.4; P29d):
  - the document decision first, then the refusals;
  - the egress question and the session count;
  - the plan notice;
  - the coach jobs and their texts;
  - evidence rendering and clipping;
  - the reply schema, with one retry in the same session;
  - `passes()`, the record and the report cache;
  - the coach block through T8's services;
  - stopping at a plan limit.
- **T10 Rules** (08 sections 1.8 and 3.2; P29g):
  - `rules` validation and matching with the three widenings;
  - the `coaching` and `harness_rules` policies;
  - `require` in the finish hook;
  - `gptr_tailor(rules =)`;
  - only the procedure coach writes rules;
  - the composer cannot add one;
  - the risk ceiling skips calls that met a `require` rule.

### Wave 4

- **T11 `k > 1` and sequential** (08 section 3.4; P29f): composers that see every probe, the blind
  judge, and sequential rounds.
- **Integration** (integrator):
  - `document()`, `_pkgdown.yml`, roxygen examples that run offline in under 5 seconds;
  - `NEWS.md`, contract 04 section 15.11, 03, decisions, `dev/progress/P29.md`;
  - the full suite, lint, and `devtools::check(args = c("--as-cran", "--no-manual"))`;
  - live tests on an API key (Bedrock Claude), a Claude Code plan and a Codex plan;
  - an adversarial review, then the PR.

## Wave 1 results that later tasks build on (2026-10-28)

- `skill.body` service: `function(name, session = NULL)`; a text skill returns `text` and `dir = NULL`.
  A session skill reaches only that session (not its sub-agents).
- New files need a row in `tests/testthat/helper-arch.R` and in 03 section 3.2: `gptr-tailor.R`,
  `gptr-coach.R` and `gptr-child.R` are area `gptr`, layer L6 (P29). Files of one area may call
  each other.
- `coach_cli_env(kind)` returns the set login variables. Pass only token-bearing ones
  (`CLAUDE_CODE_OAUTH_TOKEN`) and unset them in run children; path variables (`CLAUDE_CONFIG_DIR`,
  `CODEX_HOME`) stay set, because the adapters resolve files through them.
- The Claude adapter cannot see `run$blocked`; T7 makes the MCP gate refuse every further call of a
  blocked run at once (`R/mcp-server.R`), so a blocked run ends quickly.

## Decisions taken during planning (recorded as D-262 onward at integration)

Recorded as D-262..D-272 in dev/DEVIATIONS.md. The adversarial review's fixes are D-273..D-279
(dev/progress/P29.md, "Review fixes").

- **D-262 Names.** `gptr_tailor()` and `gptr_coach()`, so that both keep the `gptr_` prefix
  (D-28 unchanged). The object class stays `gptr_harness`, because the object is a harness.
- **D-263 Codex reduced tool set.** We recommend Codex with its shell off and gptr's tools as a
  supported route, and the live test decides. If the ChatGPT-plan backend refuses a request,
  `gptr_coach()` reports the backend's error by name and does not fall back to Codex's own shell.
- **D-264 Codex runs without their own shell.** Accepted. Runs act through gptr's tools: `r` runs
  R code, and `peter$sh` reaches the shell through `r`, both risk-checked. The live calibration
  records how well this works. We do not trade the checks for quality.
- **D-265 Codex logs.** Pass `--ephemeral`, plus `-c history.persistence="none"` if 0.157.1 has the
  key. After a live run, gptr's live test looks for a canary from the prompt among the files
  changed under `CODEX_HOME`, by name and match count only. If Codex still writes the prompt,
  honest limit 7 says so.
- **D-266 Version floor.** CLI versions are checked against a minimum, never an exact list (08
  section 3.7).
