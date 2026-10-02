from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""a per-process registry, `the$live[[id]] = rlang::new_weakref(key = s, value = live)`, so an unreferenced,
settled session is garbage-collected and its finalizer removes the registry entry and the file lock. The
reactor holds a running session strongly until it settles.""",
"""a per-process registry, `the$live[[id]] = rlang::new_weakref(key = s, value = live)`, so an unreferenced,
settled session is garbage-collected and its finalizer removes the registry entry and the file lock (the most
recent session is also held strongly by `the$last` for `gptr_last()` until another replaces it [IC-71]). The
reactor holds a running session strongly until it settles."""),
("""| `status`, `reason` | chr | `idle`, `running`, `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`; reason text |""",
"""| `status`, `reason` | chr | `idle`, `running`, `waiting`, `blocked`, `budget`, `max_turns`, `error`, `aborted`, `interrupted`, `detached`; reason text |"""),
("""| `queue`, `dropped` | list | `steer` and `follow_up` FIFOs of `list(text, source, t)`; items dropped by abort |""",
"""| `queue`, `dropped` | list | `steer` and `follow_up` FIFOs of `list(text, blocks, source, t)`; items dropped by abort |"""),
("""| `store` | open append connection (`"ab"`), lock path `<file>.lock/pid` |""",
"""| `store` | the file path and lock `<file>.lock/pid` only; entries are appended open-append-close, so no R connection outlives a gptr call [IC-59] |
| `out`, `mcp_token` | the session's `gptr$out()` store; the MCP bearer token bound to this session [IC-58, IC-71] |"""),
("""```r
msg_user(content, source = c("prompt", "pipe", "steer", "follow_up", "repl", "context", "parent"))
msg_assistant(content, api, provider, model, response_id = NULL, usage = NULL,
              stop_reason = c("stop", "length", "tool_use", "aborted", "error", "refusal", "pause"),
              error_message = NULL)
msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL)
```""",
"""The constructors `msg_user()`, `msg_assistant()`, `msg_tool_result()` and `msg_operator()` and their argument
order are fixed in the contract (§4.2); user-message sources are `prompt`, `pipe`, `steer`, `follow_up`, `repl`,
`parent`, `replay`, `extension`, `agent`, `imported`."""),
("""```r
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
# -> list(content = list(<text block>, <image blocks>...), details, is_error,
#         value (R side only), spill = <path or NULL>, truncated = <lgl>)
```""",
"""```r
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
# -> list(content = list(<text block>, <image blocks>...), details, is_error,
#         value (R side only), spill = <path or NULL>, out_id = <chr or NULL>, truncated = <lgl>,
#         terminate = <lgl>)   (contract §5.7)
```"""),
("""| `tool_call` | decision, **error = deny** | `list(decision, reason, input)` |""",
"""| `tool_call` | decision, **error = block** | `list(decision, reason, input)` |"""),
("""| `before_request` | notify, read-only (a handler that changes the frozen prefix triggers `cache_break`) | - |""",
"""| `before_request` | notify, read-only (a handler that changes the frozen prefix triggers `cache_break`) | - |
| `request_params` | patch chain over the adapter's declared non-prefix fields [IC-69] | `list(params)` |"""),
("""<root>/artifacts/<id>/artifact.json       {id, title, kind, versions, current, data: [{name, class, dim, bytes}], session}
<root>/artifacts/<id>/vNNN/               immutable snapshot per launch: app.R, R/gptr_data.R, data/<name>.rds
<root>/artifacts/<id>/run/                run.json {pid, port, url, version, started}, port, app-vNNN.log (gitignored)""",
"""<root>/artifacts/<id>/artifact.json       {id, title, kind, versions, current, data: [{name, file, class, dim, bytes}], session}
<root>/artifacts/<id>/vNNN/               immutable snapshot per launch: app.R, R/gptr_data.R, data/001.rds, ... [IC-63]
<root>/artifacts/<id>/run/                run.json {pid, port, url (with the access token), version, started}, port,
                                          app-vNNN.log (read and redacted by the parent; gitignored)"""),
("""`new.env(parent = envir)` with their own L'Ecuyer RNG stream swapped in around evaluations [15 §4.5, §5.12].""",
"""`new.env(parent = envir)` with their own L'Ecuyer RNG stream swapped in around evaluations by `rng_swap()`, seeded
from hash bits of the child's id, never through `set.seed()` or `parallel` [15 §4.5, §5.12; IC-61]."""),
("""Layers, lowest to highest: package defaults < user `R_user_dir("gptr", "config")/settings.json` < project
`.gptr/settings.json` (only when trusted; may only tighten `mode`, `permissions`, `context`, egress) <
`.gptr/settings.local.json` (remembered permission answers, gitignored) < `options(gptr.*)` <
`gptr_config(.scope = "session")` < call arguments.""",
"""Layers, lowest to highest: package defaults < user `R_user_dir("gptr", "config")/settings.json` < project
`.gptr/settings.json` (an untrusted project contributes only tightening of `mode`, `permissions`, `context` and
`record`; a trusted one every key, with tighten-type keys still only tightening; `egress` is read from the user
file only) < the user-level project file `R_user_dir("gptr", "config")/projects/<hash>.json` (remembered
permission answers, transcript target, record consent; never in the project tree [IC-52]) < `options(gptr.*)` <
`gptr_config(.scope = "session")` < call arguments. Safety options are snapshotted per run [IC-53]."""),
("""`transcript`, `plugins`, `filters`, `skills{paths}`, `mcp{exposure}`, `subagents{max_depth, max_active,
max_workers}`, `output_tokens`, `plot{width, height, res}`, `budget{tokens, cost}`, `cache{ttl}`,""",
"""`transcript`, `plugins`, `filters`, `skills{paths}`, `mcp{exposure}`, `subagents{max_depth, max_active,
max_workers, max_cli, max_tasks}`, `output_tokens`, `plot{width, height, res}`, `budget{tokens, cost}` (default 2e6
tokens and 5 USD per top-level call [IC-66]), `cache{ttl}`, `frontend`, `store`, `evaluator`,"""),
]
apply(P, pairs)
