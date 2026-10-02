from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `parameters` | JSON Schema list or `NULL` | object schema (`type = "object"`); `NULL` = derived from `fun`'s formals (all `string`, required when no default) |""",
"""| `parameters` | JSON Schema list, `function(ctx)` or `NULL` | object schema (`type = "object"`); a function is evaluated once at freeze with `ctx$input` (the `r` tool's four variants, IC-68); `NULL` = derived from `fun`'s formals (all `string`, required when no default) |"""),
("""| `exposure` | `"direct"`, `"r"`, `"deferred"`, `"hidden"` | `direct`: declared in the tool array; `r`: a `gptr$` member (one signature line in a catalog); `deferred`: found only through `gptr$search()`; `hidden`: callable by gptr code only |
| `namespace` | chr(1) or `NULL` | `r` members: `gptr$<namespace>$<name>`; plugins SHOULD set it to their package name |""",
"""| `exposure` | `"direct"`, `"r"`, `"deferred"`, `"hidden"` | a default visibility, not an identity (IC-37): `direct`: declared in the tool array (plugin tools always; built-ins when their preset lists them); `r`: a `gptr$` member with one signature line in a catalog; `deferred`: found only through `gptr$search()` (still callable); `hidden`: callable by gptr code only. Any un-namespaced spec with a `fun` that is not `hidden` is a `gptr$` member, and any spec with an `execute` may be put in the array by a preset |
| `namespace` | chr(1) or `NULL` | `r` members: `gptr$<namespace>$<name>`; plugin specs with `exposure = "r"` MUST set it (their package name); reserved member names and `mcp` are refused (IC-37) |"""),
("""| `record` | lgl(1) | calls of this member made in `r` code are kept in recorded code (bridges record digests) |""",
"""| `record` | lgl(1) | calls of this member made in `r` code are kept in recorded code (bridges record digests); top-level calls of `record = FALSE` members are dropped from recorded code (IC-48) |
| `render` | `function(call, result, width)` or `NULL` | console rendering of a call and its result (IC-69) |"""),
("""The `standard` preset with a human present; `minimal` is the first four elements; `readonly` is `read` and `r`
(plus `ask` with a human);""",
"""The `standard` preset with a human present and a bound document; `minimal` is the first four elements; `readonly`
is `read` and `r` (plus `ask` with a human). The `r` schema below is the full variant; it is frozen in one of four
variants (IC-68): `record` and `note` only when a document is bound at freeze, `timeout` (described `"Seconds; best
effort. Default 3600."`) only when no human can answer; measured 189 (document, no human), 170 (document, human),
138 (no document, no human: sub-agents), 119 (no document, human) o200k tokens;"""),
("""| `preamble` | T0 | 100 | 120 | always (minimal preset: the short variant) | P07 |
| `tools` | T0 | 200 | 250 | always (lines of the active direct tools; the `ask` line only when `ask` is active) | P07 |
| `rules` | T0 | 300 | 450 | always (minimal preset: two extra lines; direct tools' `guidelines` appended) | P07 |
| `r_session` | T0 | 400 | 500 | `r` active and preset is not `minimal` | P07 |
| `r_performance` | T0 | 450 | 150 / 420 | `r` active and preset is not `minimal` (extended: the full text below) | P07 |
| `documents` | T0 | 500 | 250 | a history document is bound (`ctx$input$document` non-NULL, from the `doc.site` service of P15) | P07 |
| `artifacts` | T0 | 600 | 150 | shiny installed and the `app` member registered (`builtin:artifacts`, P23, enabled) | P07 |
| `system1` | T0 | 650 | 150 | a System 1 provider is usable (`model_default("system1")` non-NULL: key found or emulation configured) | P07 |""",
"""| `preamble` | T0 | 100 | 120 | always (minimal preset: the short variant) | P07 |
| `tools` | T0 | 200 | 250 | always (lines of the active direct tools; the `ask` line only when `ask` is active) | P07 |
| `rules` | T0 | 300 | 450 | always: the `guidelines` of the active direct tools in array order, then P07's three closing lines (minimal preset: two extra lines); `readonly` drops the edit/write lines (IC-68) | P07 (closing lines); P10 (tool guidelines) |
| `r_session` | T0 | 400 | 500 | `r` active and the preset record includes it (not `minimal`): P07's core with `{{fragments}}` from `builtin:tools`, `builtin:bridges`, `builtin:lang`, `builtin:subagents` (IC-68) | P07 (core); P10, P22, P19 (fragments) |
| `r_performance` | T0 | 450 | 150 / 420 | `r` active and preset is not `minimal` (extended: the full text below) | P07 |
| `documents` | T0 | 500 | 250 | a history document is bound (`ctx$input$document` non-NULL, from the `doc.site` service) | P15 (IC-68) |
| `artifacts` | T0 | 600 | 150 | shiny installed and `builtin:artifacts` enabled | P23 (IC-68) |
| `system1` | T0 | 650 | 150 | a System 1 provider is usable (`model_default("system1")` non-NULL: key found or emulation configured) | P13 (IC-68) |"""),
("""The standard texts are verbatim in §7.3 of `03` (P07's `prompt-text.R` MUST reproduce them byte for byte; P07
acceptance 2).""",
"""The standard texts are verbatim in §7.3 of `03` as amended by IC-67/IC-68 (no `str()` anywhere; `<r_session>` with
the `record = false` line and without the MCP sentence; `<context>` with the `trusted="false"` sentence; the skills
catalog with `[skill:<name>/SKILL.md]` pseudo-paths). Each owner's text MUST reproduce its part byte for byte (P07
acceptance 2 for P07's parts); P24 compares the composed prompt with every built-in loaded."""),
("""- Check size first (dim(), object.size()); print head()/str(x, max.level = 1), never whole big objects. Avoid copies: data.table := / set*, rm() temporaries.""",
"""- Check size first (dim(), object.size()); print head() or gptr$describe(x), never whole big objects; str() makes the next in-place edit of a large object copy it. Avoid copies: data.table := / set*, rm() temporaries."""),
("""Mode blocks and the first-message formats are verbatim in §7.4 of `03`; the non-interactive suffix appended inside
the mode block is exactly `No one can answer questions or approvals in this run, so actions that need approval
stop the run. State your assumptions instead of asking.` (with `gptr.noninteractive_ask = "deny"` the second
clause reads `so actions that need approval are refused.`).""",
"""Mode blocks and the first-message formats are verbatim in §7.4 of `03`; the non-interactive suffix appended inside
the mode block is exactly `No one can answer questions or approvals in this run, so actions that need approval
stop the run. State your assumptions instead of asking.` (with `gptr.noninteractive_ask = "deny"` the second
clause reads `so actions that need approval are refused.`); in `manual` mode, where `ask` stays declared (IC-68),
it is `No one can answer questions or approvals in this run: actions that need approval, and questions asked with
the ask tool, stop the run. Ask only when no reasonable assumption lets you continue.`"""),
("""| `find` | P10 | `gptr$find(pattern, path = ".", sort = c("path", "mtime", "size"), type = "file", limit = 1000L)` | `gptr_files` | 0 / 1 |""",
"""| `find` | P10 | `gptr$find(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"), type = "file", limit = 1000L)` (`relevance`: exact basename > prefix > substring > subsequence, ties by path; REQ-08) | `gptr_files` | 0 / 1 |"""),
("""| `grep` | P10 | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"))` | `gptr_matches` (`output = "files"`: `gptr_files`; `"count"`: df `file`, `n`) | 0 (1 outside the project) |""",
"""| `grep` | P10 | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE, context = 0L, limit = 100L, output = c("content", "files", "count"), sort = c("path", "count", "mtime"))` (`sort` applies to `files` and `count`) | `gptr_matches` (`output = "files"`: `gptr_files`; `"count"`: df `file`, `n`) | 0 (1 outside the project) |"""),
("""| `help` | P10 | `gptr$help(name, package = NULL, budget = 800L)` | chr: a tool schema for `"<server>/<tool>"`, `"<ns>/<name>"` or a member name; else R help via `tools::Rd2txt()`; budgeted | 0 |
| `search` | P10 | `gptr$search(words, limit = 8L)` | df `name`, `kind` (`member`, `plugin`, `mcp`, `skill`, `deferred`), `signature`, `score` | 0 |
| `describe` | P10 | `gptr$describe(x, budget = 150L)` | `gptr_describe(x, budget)` | 0 |
| `plot` | P10 | `gptr$plot(width = 1000L, height = 700L)` | attaches the current device's plot at that size to the running `r` result (about 900 tokens); `invisible(NULL)` | 0 |
| `out` | P10 | `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)` | chr (the stored full text, or `lines` of it) | 0 |""",
"""| `help` | P10 | `gptr$help(name, package = NULL, budget = 800L)` | chr: a tool schema for `"<server>/<tool>"`, `"<ns>/<name>"` or a member name; else R help via `tools::Rd2txt()`; budgeted; `record = FALSE` | 0 |
| `search` | P10 | `gptr$search(words, limit = 8L)` | df `name`, `kind` (`member`, `plugin`, `mcp`, `skill`, `deferred`, or a `search_source` kind), `signature`, `score`; `record = FALSE` | 0 |
| `describe` | P10 | `gptr$describe(x, budget = 150L)` | `gptr_describe(x, budget)`; `record = FALSE` | 0 |
| `plot` | P10 | `gptr$plot(which = NULL, width = 1000L, height = 700L)` | attaches the current device's plot (or stored plot `which`, IC-67) at that size to the running `r` result (about 900 tokens); `invisible(NULL)`; `record = FALSE` | 0 |
| `out` | P10 (only owner, IC-36) | `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)` | chr (the stored full text from the session store, the process store or the spill file, or `lines` of it); `record = FALSE` | 0 |"""),
("""| `knit` | P22 | `gptr$knit(engine, code)` | chr: output of a knitr engine | 3 |
| `app` | P23 | `gptr$app(id, data = character(), title = NULL, kind = c("shiny", "html"), check = TRUE, launch = interactive())` | `gptr_artifact`; the `r` result gets its URL, checks and screenshot image | 3 |""",
"""| `knit` | P22 | `gptr$knit(engine, code)` | chr: output of a knitr engine; `bash`, `sh`, `zsh`, `powershell`, `cmd` run through `gptr$sh()` with the `helper` environment and a timeout (IC-67) | 3 (shell engines: the command classifier) |
| `app` | P23 | `gptr$app(id, data = character(), title = NULL, kind = "shiny", check = TRUE, launch = interactive())` (`kind`: a registered `artifact_type`, IC-69; ids that are Windows reserved names are refused, IC-63) | `gptr_artifact`; the `r` result gets its URL, checks and screenshot image | 3 |"""),
]
apply(P, pairs)
