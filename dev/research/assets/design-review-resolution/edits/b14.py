from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `history` | chr(1) | `"store"` or `"reconstructed"` (a replayed session rebuilt from its document, IC-46) |""",
"""| `history_source` | chr(1) | `"store"` or `"reconstructed"` (a replayed session rebuilt from its document, IC-46) |"""),
("""adopting the recorded id, from the JSONL or reconstructed from the document with `history = "reconstructed"`),""",
"""adopting the recorded id, from the JSONL or reconstructed from the document with `history_source =
"reconstructed"`),"""),
("""  `.d$history = "reconstructed"`. A later live continuation""",
"""  `.d$history_source = "reconstructed"`. A later live continuation"""),
("""| IC-27 | P07 owns every built-in section text, including `documents`, `artifacts`, `system1`, each with an inclusion predicate on `ctx$input`;""",
"""| IC-27 | (amended by IC-68: `documents`, `artifacts`, `system1` are registered by P15, P23, P13, and `<rules>`/`<r_session>` are composed from owners' guidelines and fragments.) P07 owns every built-in section text, including `documents`, `artifacts`, `system1`, each with an inclusion predicate on `ctx$input`;"""),
("""(lgl: a human can answer), `depth` (int), `parent_run` (run id), `agent` (label), `background` (lgl),
`rng_stream` (int(7) L'Ecuyer seed for inline children), `preset`, `tools` (chr modifiers), `call` (the
`gptr_call`, released at settlement).""",
"""(lgl: a human can answer), `depth` (int), `parent_run` (run id), `agent` (label), `background` (lgl),
`rng_state` (environment holding the child's `c(10407L, <6 seeds>)` L'Ecuyer vector for `rng_swap()`, IC-61),
`preset`, `tools` (chr modifiers), `call` (the `gptr_call`, released at settlement), `safety` (the option
snapshot of IC-53), `root` (the root session id for budgets, IC-66)."""),
("""| `resolve_identifier(expr, arg, envir)` | §6.1.3; returns chr or a spec | P08, P17 (`agents` mask), P02 (`gptr_agent()`) |""",
"""| `resolve_identifier(expr, arg, envir)` (service `identifier.resolve`) | §6.1.3; returns chr or a spec | P08, P17 (`agents` mask); P02 stores raw expressions and never calls it (IC-34) |"""),
("""| `gptr.cache_break` | P07 | `{provider, model, firstDiff, entry, culprit}` |""",
"""| `gptr.cache_break` | P07 | `{provider, model, firstDiff, entry, culprit}` |
| `gptr.recovered` | P06 | `{from, to}`: the byte range of a torn line found at resume (IC-59) |
| `gptr.router` | P06 | `{router, state, model, reason}`: a router's per-branch state (IC-69) |
| `gptr.image_elision` | P06 | `{images: [ids]}`: older images projected as omitted (IC-67) |
| `gptr.scrub` | P03 | `{date, secrets, count}`: `gptr_scrub()` rewrote this file (IC-70) |"""),
("""| `gptr.replay` | P15 | `{doc, block, mode}` |""",
"""| `gptr.replay` | P15 | `{doc, block, mode, turn, value}` (appended by `session_replay_apply()`/`session_replay_new()`, IC-46) |"""),
]
apply(P, pairs)
