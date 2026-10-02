from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""passed through the condition redactor (`redact(profile = "persist")` once P03 has installed it with `condition_redactor_set()`; identity before) |""",
"""passed through the redaction hook `redact_hook()` (`redact(profile = "persist")` once P03 has installed it with `redactor_set()`; identity before; IC-34) |"""),
("""**`utils-conditions.R`**: §1.1 checkers, §2.1 constructors, `msg_verbatim()`, `condition_redactor_set()`,
`gptr_deprecated()`.""",
"""**`utils-conditions.R`**: §1.1 checkers, §2.1 constructors, `msg_verbatim()`, `gptr_deprecated()` (the redaction
hook itself lives in `aaa-state.R`, IC-32, IC-34)."""),
("""(used by P02 for its 30 kinds and through the `kind` kind by plugins and
P22),""",
"""(used by P02 for its 37 kinds and through the `kind` kind by plugins and
P22, IC-69),"""),
("""                     fun = function(a, b) a + b, exposure = "r"))
```""",
"""                     fun = function(a, b) a + b, exposure = "r", namespace = "demo"))
```"""),
("""Registered as tool specs with `exposure = "r"` by the plans named.""",
"""Registered as tool specs with a `fun` by the plans named (`read`, `write`, `edit`, `grep`, `find`, `ls` also carry
an `execute`, so presets can declare them as direct tools; IC-37)."""),
("""### 10.2 The 31 kinds""", """### 10.2 The 38 kinds"""),
]
apply(P, pairs)
