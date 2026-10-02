from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/05-plan-decomposition.md"
pairs = [
# P13
("""- **Scope.** `s1-types.R` (the three classes and methods of architecture §5.6; delayed vctrs methods);""",
"""- **Scope.** `s1-types.R` (the three classes and methods of architecture §5.6; delayed vctrs methods;
  `gptr_prob()`, moved from P08, IC-36);"""),
("""  one-line document summary via an event); `s1-cache.R` (per-element cache, memory before init, input hash
  only); `s1-emulate.R` (opt-in emulation through structured output, uncalibrated flag).""",
"""  one-line document summary through the `doc.s1_block` service); `s1-cache.R` (per-element cache, memory before
  init, salted input hash and question hash only, IC-70); `s1-emulate.R` (opt-in emulation through structured
  output, uncalibrated flag).
- **Review amendments (contract §15).** `gptr_prob()` and its example (IC-36); the `system1` prompt section
  (IC-68); `inst/gptr/examples/jev-router.R` with its test (IC-69); the typesafe record's static `rate` and
  process-wide admission (IC-64); `gptr.s1_max_elements` (IC-66); the `s1_split` message instead of the `s1_batch`
  error (IC-71); S1 cache schema 2 with the committed salt (IC-70); System 1 calls inside recorded blocks use the
  cache and error `not_recorded` on a miss under `replay` (IC-47)."""),
("""- **Owns.** The five R files and tests; `fixtures/jev/`; `test-copy-s1.R`; `test-live-jev.R`.""",
"""- **Owns.** The five R files and tests; `fixtures/jev/`; `test-copy-s1.R`; `test-live-jev.R`;
  `inst/gptr/examples/jev-router.R`."""),
("""     `"TRUE"` is rejected; `min_confidence` with `uncertain = NA`, `"stop"` and a function behave as
     specified; a data frame in `while()` without `I()` errors with the hint naming `I()`.""",
"""     `"TRUE"` is rejected; `min_confidence` with `uncertain = NA`, `"stop"` and a function behave as
     specified; splitting a data frame into several states prints the once-per-session `s1_split` message naming
     `I()` (a function cannot see that it is a condition; IC-71)."""),
("""  4. Emulation never happens without `gptr_config(system1 = "emulate:<model>")`.""",
"""  4. Emulation never happens without `gptr_config(system1 = "emulate:<model>")`.
  4b. Review additions: the `gptr_prob()` example runs; a fake-classifier router loaded from the example switches
     models after the first successful `edit`, with exactly one `model_change`; 100 concurrent System 1 states never
     exceed 40 requests per second; the S1 cache files contain neither the input nor the question text; P13's NS
     fixtures are added to `dev/bench/tokens/` (IC-73)."""),
# P14
("""  `console-jsonl.R` (the `jsonl` frontend: redacted Pi-named events on a connection).""",
"""  `console-jsonl.R` (the `jsonl` frontend: redacted Pi-named events on a connection).
- **Review amendments (contract §15).** The renderer prints the NS-8 artifact line on `artifact_start` and uses
  tool `render` functions and `renderer` records (IC-69, IC-71); approval displays are sanitised and list every
  flagged call (IC-53); the `console` route and the REPL use `gptr_can_prompt()` (IC-43); the pause-menu steer and
  follow-up enter the queue with `source = "pause_menu"` and are recorded as `## Steer:`/`## Follow-up:` lines by
  P15 (IC-49, IC-55); asks of background runs are shown at the next blocking call (IC-57); `!expr` notes within
  300 tokens (IC-73); the `.stdin` connection closes on `/exit` and on exit (IC-59); `frontend` selectable by
  setting (IC-69)."""),
("""  6. The JSONL sink contains no registered secret (fake key).""",
"""  6. The JSONL sink contains no registered secret (fake key).
  7. Review additions: `artifact_start` prints `artifact  <id>  ->  <url>   (running in background)`; an ESC
     sequence in a tool preview is escaped; with `jupyter.in_kernel = TRUE` mocked, `gptr()` with no prompt starts the
     console on a mocked `gptr_readline()`."""),
# P15
("""  `doc-knitr.R` (`knit_print` methods for sessions and System 1 vectors registered lazily, the scoped label
  hook for regeneration).""",
"""  `doc-knitr.R` (`knit_print` methods for sessions and System 1 vectors registered lazily, the scoped label
  hook for regeneration).
- **Review amendments (contract §15).** The route matches a top-level call located in a document that holds a block
  for it, and replay needs no consent; write consent (`gptr_doc()` for every call of the process, the `record`
  option or user setting, an interactive yes) is checked only in `doc_upsert()` (IC-45); the `args=` header key and
  S2 key (IC-45); replay in place for piped sessions, replayed sessions from the JSONL or reconstructed from the
  document, fork blocks bound by block id and wrapped with `gptr_resume(block =)` (IC-46); team and fan-out blocks
  and block-nested calls replayed from S2 (IC-47); dropping top-level `gptr_return()` and `record = FALSE` member
  calls, the best-effort `<-` rewrite, no recording in plan mode (IC-48); console transcripts as pipe chains and
  `## Steer:`/`## Follow-up:` lines (IC-49); Jupyter pending blocks and `gptr_doc(sync = TRUE)` (IC-50); the
  sidecar of block upserts with recovery, rename retries with an in-place fallback, `path_key()` matching (IC-51);
  transcript targets validated and stored in the user-level project file (IC-52); forced replay only outside
  testthat (IC-45); the `documents` prompt section and services owned by `builtin:documents` (IC-68, IC-34)."""),
("""  3. With `_R_CHECK_PACKAGE_NAME_` set, replay is forced; with `GPTR_REPLAY=replay`, a nested call raises
     `gptr_error_not_recorded`.""",
"""  3. With `_R_CHECK_PACKAGE_NAME_` set and `TESTTHAT` unset, replay is forced; with `TESTTHAT=true` it is not;
     with `GPTR_REPLAY=replay`, a call nested in a loop raises `gptr_error_not_recorded`."""),
("""  5. No document is written without `gptr_doc()`, an interactive yes or trusted `record = "auto"`.""",
"""  5. No document is written without `gptr_doc()`, `options(gptr.record = "auto")` or user-scope `record =
     "auto"`, or an interactive yes; a project `record = "auto"` is ignored (tighten-only); a fresh clone without
     any consent replays with zero model calls and executes no block twice (IC-45).
  6. Review additions: a block whose code called `gptr_return(fit)` and `gptr$out("o1")` re-sources cleanly under
     `source()` and Rscript and `$value` resolves `fit` (IC-48); re-sourcing NS-3 twice leaves the main-line
     `qc_flags` and `qc$value` unchanged and the fork's objects only in its overlay (IC-46); a replayed pipe chain
     returns one object; in a fresh clone without `sessions/` a continuation replays from the reconstructed history;
     a parameterised document rendered with two values of `{gene}` does not replay the first block for the second
     (IC-45); a two-turn console session plus one menu steer produces a transcript that re-sources as one session
     (IC-49); a plan-mode run records no code; NS-6 and a block containing a sub-agent call replay under
     `GPTR_REPLAY=replay` with zero requests (IC-47, with P19); an Rscript run killed with SIGTERM after two calls
     leaves a sidecar whose upserts the next run applies without overwriting user edits (IC-51); a notebook is
     never written while `jupyter.in_kernel` is mocked, and `gptr_doc(path, sync = TRUE)` applies its pending
     blocks (IC-50); P15's NS-7 fixture is added to `dev/bench/tokens/` (IC-73)."""),
# P16
("""  objects, files and state, and the exported `gptr_preimage()` S3 generic, contract IC-01).""",
"""  objects, files and state, and the exported `gptr_preimage()` S3 generic, contract IC-01).
- **Review amendments (contract §15).** File restores stay inside the project root and `tempdir()` unless the user
  confirms each outside path (`ask_human`, IC-52); blob garbage collection keeps blobs referenced by any session
  file of the project and skips while another live pid holds a session lock (IC-71); after a Codex
  `workspace-write` exec the files checkpointer walks, so `/undo` covers it (IC-65)."""),
("""  4. Undone blocks in a bound document become inert (`#~ `, `status=undone`) and re-sourcing reproduces the
     rewound workspace.""",
"""  4. Undone blocks in a bound document become inert (`#~ `, `status=undone`) and re-sourcing reproduces the
     rewound workspace.
  5. Review additions: a checkpoint record whose path lies outside the project is not restored without a human;
     pruning in one process does not delete a blob another live session references."""),
# P17
("""  `inst/gptr/skills/high-performance-r/`, `inst/gptr/prompts/review.md`, `explain.md`.""",
"""  `inst/gptr/skills/high-performance-r/`, `inst/gptr/prompts/review.md`, `explain.md`.
- **Review amendments (contract §15).** Name normalisation for skills, plugins, extensions and agents (IC-42);
  untrusted project skills and agents are listed but not catalogued, and omitted non-interactively in `auto`/
  `edits` (IC-52); `[skill:<name>/SKILL.md]` pseudo-paths in the catalog (IC-68); string frontmatter keys keep
  their source text against YAML 1.1 coercion (IC-71); user and foreign-harness directories through
  `user_home()`/`app_config_dir()` (IC-63); plugins and extensions enabled for a call are scoped to that session
  (IC-69); the high-performance-r skill says `str()` copies large objects (IC-67)."""),
("""- **Depends on.** P08.
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "skill|subagent-defs|ext-plugins")'` is green.""",
"""- **Depends on.** P08, P10 (the `plugins` section, `ns_catalog()` and activation through `read`; IC-36).
- **Milestone.** M3.
- **Acceptance.**
  1. `Rscript --vanilla -e 'devtools::test(filter = "skill|subagent-defs|ext-plugins")'` is green."""),
("""  4. A `.claude-plugin` fixture contributes a skill, a command, an agent and an MCP entry; project plugin code
     is ignored until `gptr_trust()`.""",
"""  4. A `.claude-plugin` fixture contributes a skill, a command, an agent and an MCP entry; project plugin code
     is ignored until `gptr_trust()`.
  4b. Review additions: `skills = single_cell` resolves to `single-cell` and `skills = high_performance_r` to the
     built-in; a SKILL.md with `name: on` and `version: 1.0` keeps both as strings; a plugin passed with `plugins =`
     is invisible to the next `gptr()` call; an untrusted project's skill is not in the catalog."""),
]
apply(P, pairs)
