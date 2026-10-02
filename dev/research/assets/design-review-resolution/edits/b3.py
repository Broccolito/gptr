from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `skills`, `plugins`, `extensions` | identifiers (`c(a, b)`) or `NULL` | names resolved by §6.1.3; `extensions` also accepts `function(gptr)` factories (loaded with `ext_load(rank = 0L)`) and file paths;""",
"""| `skills`, `plugins`, `extensions` | identifiers (`c(a, b)`) or `NULL` | names resolved by §6.1.3 (normalised, IC-42); `extensions` also accepts `function(gptr)` factories (loaded with `ext_load(rank = 0L, session = <id>)`, visible to this session only, IC-69) and file paths;"""),
("""| `agents` | named list or `NULL` | evaluated in a mask where `agent` is `gptr_agent`; names must be unique syntactic names |""",
"""| `agents` | named list or `NULL` | evaluated in a mask where `agent` is `gptr_agent`; names must be unique syntactic names that are not accessor names (IC-71) |"""),
("""| `envir` | `env` | where `r` evaluates and objects persist (D-04); a magrittr mask is replaced by its parent [12 §2.B4] |""",
"""| `envir` | `env` | where `r` evaluates and objects persist (D-04); a magrittr mask is replaced by its parent [12 §2.B4]; for a continuation an explicit `envir` (tested with `missing(envir)`) beats the session's kept home, which beats the caller frame (IC-40) |"""),
("""(`"summary"`, `"names"`, `"none"`), `record` (lgl(1)), `interpolate` (lgl(1)), `timeout` (num(1), seconds for `r`), `output` (`"factor"`), `system` (chr(1) replacing `preamble`/`tools`/`rules`, or a named list overriding sections, `NULL` elements remove), `preset` (chr(1)), `returns` (a JSON Schema list: structured final answer, INFRA-25), `max_active` (int(1)), `backend` (chr(1)); unknown names signal `gptr_error_invalid_argument` |""",
"""(`"summary"`, `"names"`, `"none"`), `record` (lgl(1)), `interpolate` (lgl(1)), `timeout` (num(1), seconds for `r`), `output` (`"factor"`), `system` (chr(1) replacing `preamble`/`tools`/`rules`, or a named list overriding sections, `NULL` elements remove), `preset` (a registered `preset` name), `returns` (a JSON Schema list: structured final answer, INFRA-25), `max_active` (int(1)), `backend` (a registered `backend` name or `"auto"`), `frontend` (a registered `frontend` name), `images` (list of image paths, `ggplot` or `recordedplot` objects, IC-44), `seed` (int(1): reproducible sub-agent RNG streams, IC-61), and entries named by a plugin namespace (validated by that plugin's `setting` specs, IC-44); other unknown names signal `gptr_error_invalid_argument` |"""),
("""1. **Capture** [R3]: `exprs = as.list(substitute(list(...)))[-1L]`, `nms = ...names()`; dot facts
   (`is_session`, `is_literal`, `is_chr1`, `class`, `length`, `dim`, `bytes`, small-character `text` copy) are
   computed by the leaf `dot_facts(...elt(i))` in a `while` loop; evaluating a call among the dots (the inner
   `gptr()` of a pipe) runs it exactly once;""",
"""1. **Capture** [R3]: `exprs = as.list(substitute(list(...)))[-1L]`, `nms = ...names()`; dot facts
   (`is_session`, `is_literal`, `is_chr1`, `class`, `length`, `dim`, `bytes`, small-character `text` copy) are
   computed by leaves: for a dot whose expression is a plain symbol, `dot_facts()` of a leaf
   `get0(name, envir = parent.frame())` and the dot's promise is never forced; calls and forwarded `...`/`..n`
   dots go through `dot_facts(...elt(i))` in a `while` loop (IC-41); evaluating a call among the dots (the inner
   `gptr()` of a pipe) runs it exactly once;"""),
("""4. **Human check**: no prompt, no human (`gptr_has_human()` FALSE) and `.stdin = FALSE` ->
   `gptr_error_noninteractive`.""",
"""4. **Human check**: no prompt, nobody to prompt (`gptr_can_prompt()` FALSE, IC-43) and `.stdin = FALSE` ->
   `gptr_error_noninteractive`."""),
("""   | 10 | `classifier` | P13 | resolved model is a `classifier` provider | `gptr_decision`/`gptr_choice`/`gptr_score`; a piped session becomes the state through `as_state()`, no turn |
   | 20 | `nested` | P08 | a run is active on the call stack (`run_current()` non-NULL) and no session is continued | a child session of the running one (depth + 1, mode inherited and only tightened, usage rolled up, no document block) |
   | 30 | `console` | P14 | no prompt (human present or `.stdin`) | the `console` frontend on the piped session or a new one; returns it invisibly on `/exit` |
   | 40 | `team` | P19 | `agents` given | a team session |
   | 45 | `fanout` | P19 | `parallel` given and exactly one list-like context object | a fan-out session |
   | 50 | `document` | P15 | top-level call and a document binding | fresh recorded block under replay: a replayed session (zero tokens); otherwise sets `call$doc` and passes |
   | 60 | `continue` | P08 | a session was piped in | running: `gptr_steer(s, prompt)` and `invisible(s)`; otherwise a new turn on `s` |
   | 70 | `new` | P08 | always | a new session |

   Before P13/P14/P15/P19 are loaded their routes are absent; a no-prompt call with a human present and no
   `console` route signals `gptr_error_not_available`.
   Team and fan-out calls own no document block in v1 (their order precedes `document`); in replay mode their
   children pass `replay_guard()`, so `GPTR_REPLAY=replay` still proves that a script makes no model calls.""",
"""   | 10 | `classifier` | P13 | resolved model is a `classifier` provider | `gptr_decision`/`gptr_choice`/`gptr_score`; a piped session becomes the state through `as_state()`, no turn |
   | 15 | `team` | P19 | `agents` given | a team session; inside a run its children are children of the running session (IC-39) |
   | 16 | `fanout` | P19 | `parallel` given and exactly one list-like context object | a fan-out session (same nesting rule) |
   | 20 | `nested` | P08 | a run is active on the call stack (`run_current()` non-NULL) and no session is continued | a child session of the running one (depth + 1, mode inherited and only tightened, usage and budget rolled up to the root, no document block) |
   | 30 | `console` | P14 | no prompt (`gptr_can_prompt()` or `.stdin`) | the `console` frontend on the piped session or a new one; returns it invisibly on `/exit` |
   | 50 | `document` | P15 | a top-level call located in a document that contains a block owned by this call (no write consent needed to replay, IC-45) | a fresh block: the replay of IC-46 (the piped session advanced in place, else a replayed session; zero tokens); a stale block under `replay`: `gptr_error_stale_block`; otherwise sets `call$doc` when write consent exists and passes |
   | 60 | `continue` | P08 | a session was piped in | running: `gptr_steer(s, prompt)` and `invisible(s)`; otherwise a new turn on `s` |
   | 70 | `new` | P08 | always | a new session |

   Before P13/P14/P15/P19 are loaded their routes are absent; a no-prompt call that can prompt and no
   `console` route signals `gptr_error_not_available`. Every call made while `run_current()` is non-NULL inherits
   the running mode (only tightened) and filters whatever route handles it (IC-53). Top-level team and fan-out
   statements own one document block (IC-47); in replay mode their children pass `replay_guard()`, so
   `GPTR_REPLAY=replay` still proves that a script makes no model calls."""),
("""| symbol that is a **known identifier** (catalog alias, registered provider/model/router id, mode, preset, skill, plugin, extension, agent name; `identifier_known()`) | its name; a once-per-session `alias_shadowed` message when a *character* variable of that name holds a different value ("used the alias; write !!sonnet") |""",
"""| symbol that is a **known identifier** (catalog alias, registered provider/model/router id, mode, preset, skill, plugin, extension, agent name; `identifier_known()`; skill, plugin, extension and agent names compare after `name_norm()` = lower case with `_` and `.` mapped to `-`, IC-42) | its canonical name; a once-per-session `alias_shadowed` message when a *character* variable of that name holds a different value ("used the alias; write !!sonnet"); an ambiguous normalised match is `gptr_error_invalid_identifier` listing the candidates |"""),
("""disables it. The call record keeps `template` (written to documents, hashed for blocks) and `prompt` (sent).""",
"""disables it. The call record keeps `template` (written to documents, hashed for blocks), `prompt` (sent) and
`interp` (the sorted `name=value` pairs used, hashed into the block header's `args=` key, IC-45)."""),
("""| `path` | `chr(1)`, no default | project directory; missing: with a human present asks `Create .gptr/ in <project_root()>? [y/N]` through `gptr_confirm()`; without a human `gptr_error_noninteractive` |""",
"""| `path` | `chr(1)`, no default | project directory; missing: when `gptr_can_prompt()` asks `Create .gptr/ in <project_root()>? [y/N]` through `gptr_confirm()`; otherwise `gptr_error_noninteractive` |"""),
("""gptr_config(..., .scope = c("session", "project", "user"))
```

With no `...`: returns the effective settings""",
"""gptr_config(..., .scope = NULL)
```

`.scope`: `NULL` = `"project"` when a workspace exists (`workspace_dir()` non-NULL), else `"session"` (NS-9's
"project defaults", IC-71); or one of `"session"`, `"project"`, `"user"`. With no `...`: returns the effective
settings"""),
("""Conditions: `invalid_argument`. Side effects: writes `trust.json` (atomic). Emits `project_trust` (notify).""",
"""The record includes the trust fingerprint of the trust-gated files (IC-52). Conditions: `invalid_argument`. Side
effects: writes `trust.json` (atomic, under a short file lock). Emits nothing (`project_trust` is the first-decision
event raised when untrusted resources are first used, IC-71). Called from model code during a run it is a
`control`-category action (IC-53)."""),
("""`NAME #fp` (never values), CLI versions (P20 contributes a `status` function per `cli` provider), plan status and
egress acknowledgement. `check = TRUE` makes cheap reachability checks (models endpoint with a 2 s timeout for
HTTP providers; `claude --version`/`codex --version` for CLIs; never a paid request). `check = FALSE` performs no
network or process I/O.""",
"""`NAME #fp` (never values), CLI paths and cached versions (P20 contributes a `status` function per `cli` provider
that reads only cached `Sys.which()` data unless `check = TRUE`, IC-65), plan status and egress acknowledgement.
`check = TRUE` makes cheap reachability checks (models endpoint with a 2 s timeout for HTTP providers;
`claude --version`/`codex --version` for CLIs; never a paid request). `check = FALSE` performs no network or
process I/O."""),
("""`"r(sql:select)"`, `"mcp__github__*"`) adds them; `remove` removes matching rules. `scope`: `"session"` = this R
process; `"project"` = `.gptr/settings.local.json` (personal, gitignored); `"user"` = the user settings file.""",
"""`"r(sql:select)"`, `"mcp__github__*"`) adds them; `remove` removes matching rules. `scope`: `"session"` = this R
process; `"project"` = the user-level project file `R_user_dir("gptr", "config")/projects/<hash>.json` (personal,
never in the project tree, IC-52); `"user"` = the user settings file. Called from model code during a run it is a
`control`-category action (IC-53)."""),
]
apply(P, pairs)
