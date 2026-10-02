from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/03-architecture.md"
pairs = [
("""| `minimal` (sub-agents) | 675 | 624 | 0 | **1,299** | Pi's 4-tool default 919-1,175 [G2 (b)] |
| `standard` core (no documents, artifacts, System 1; no human) | 675 | 1,159 | 551 | **2,385** | |
| `standard`, non-interactive, all sections | 675 | 1,592 | 551 | **2,818** | G4's 7-tool default 3,598 |
| `standard`, interactive (+ `ask`), all sections | 820 | 1,609 | 551 | **2,980** | Claude Code CLI 3-18K [07] |
| `extended` | about 1,300 | about 1,900 | 551 | about 3,750 | Codex 19-38K per turn [08] |""",
"""| `minimal` (sub-agents) | 615 | 656 | 0 | **1,271** (about 1,720 Claude) | Pi's 4-tool default 919-1,175 [G2 (b)] |
| `standard` core (no documents, artifacts, System 1; no human) | 615 | 1,203 | 542 | **2,360** (about 3,190) | |
| `standard`, non-interactive, all sections, a bound document | 666 | 1,636 | 542 | **2,844** (about 3,840) | G4's 7-tool default 3,598 |
| `standard`, interactive (+ `ask`), all sections, a bound document | 792 | 1,653 | 542 | **2,987** (about 4,030) | Claude Code CLI 3-18K [07] |
| `standard`, interactive (+ `ask`), no document | 741 | 1,467 | 542 | 2,750 (about 3,710) | |
| `extended` | about 1,300 | about 1,950 | 542 | about 3,790 (about 5,120) | Codex 19-38K per turn [08] |

Measured after the review with rtiktoken o200k [IC-68]; the parenthesised values project Claude tokens with the
1.35 prior of §12.5 (range 1.3-1.6) [IC-73]. Budgets are in o200k-estimated units scaled by the session's
multiplier."""),
("""Each MCP or plugin signature adds about 36 tokens (catalog budget 1,500); each visible skill 33-50 (budget
1,500);""",
"""Each MCP or plugin signature adds about 36 tokens (catalog budget 1,500); each visible skill about 30-45 with
pseudo-paths (budget 1,500);"""),
("""| plot image | 532 (768x512, res 120) | one per plot; `gptr$plot()` for 1000x700 (about 900) |""",
"""| plot image | 532 (768x512, res 120) | at most 3 per `r` result (`gptr.r_max_images`), counted against the `r` budget; the rest stored for `gptr$plot(k)`; older images projected as omitted above the provider's image limits [IC-67]; `gptr$plot()` for 1000x700 (about 900) |"""),
("""| steering relay | about 15 + the text | - |""",
"""| steering relay | about 15 + the text | - |
| `!expr` note | the `#>` output | 300, with the `workspace_changes` rules [IC-73] |"""),
("""| Compact skill catalog with activation through `read` | 33-50 vs 94 tokens per skill; no skill tool whose enum would break the cached tool array | G2 (b), 16 |""",
"""| Compact skill catalog with activation through `read` | about 30-45 vs 94 tokens per skill with pseudo-paths (a real library path costs about 15 more per entry); no skill tool whose enum would break the cached tool array | G2 (b), 16; [IC-68] |
| `r` schema variants | 9-79 tokens per request (`record`/`note` only with a bound document, `timeout` only without a human) | [IC-68] |
| Rules from the active tools' guidelines | -115 tokens in the `readonly` (plan) preset; disabling a built-in removes its `<r_session>` line | [IC-68] |
| Deduplicated turn blocks | an unchanged plugin block is not re-sent every prompt | [IC-38] |"""),
("""| `minimal` preset for sub-agents | 1,299 vs about 2,980 static tokens per child request | §12.1 |""",
"""| `minimal` preset for sub-agents | 1,271 vs about 2,987 static tokens per child request | §12.1 |"""),
("""| `<r_session>` with the helper and polyglot catalog | 443 per request (cached) | replaces direct grep/find/ls/shell tools (about 1,100) and makes composition the default |
| `ask` tool when a human is present | 145 + 17 per request (cached) | a safe UI pause that model code cannot express |""",
"""| `<r_session>` with the helper and polyglot catalog | 455 per request (cached; +12 for the `record = false` rule that keeps replay clean) | replaces direct grep/find/ls/shell tools (about 1,100) and makes composition the default |
| `ask` tool when a human is present | 145 + 17 per request (cached) | a safe UI pause that model code cannot express |
| `ask` in non-interactive `manual` runs | 145 + 11 per request (cached) | NS-12: stop with the question instead of guessing [IC-68] |
| `trusted="false"` sentence in `<context>` | 35 per request (cached) | untrusted project text must not command the agent [IC-52] |"""),
("""| Model switches | one cache miss of the static prefix per switch | REQ-14 cross-provider hand-off |
| Compaction checkpoint | about 1,100 post-compaction first message + up to 2,048 output | keeps long sessions inside the window |""",
"""| Model switches | one cache miss of the static prefix per switch | REQ-14 cross-provider hand-off |
| Router switches | one System 1 call (about 280 tokens) and one cache miss per switch [IC-69] | cheap models for easy steps |
| Tool additions mid-session (plan -> auto, `ctx$add_tools()`, `tools =` on a continuation) | the added schemas once as a `tool_addition` (edit and write: about 480) | the frozen array never changes [IC-69] |
| The Claude-CLI route | the CLI's own framing beyond gptr's frozen prompt (UNCERTAIN until the live suite measures it) | the Claude plan |
| gptr's MCP schemas inside Codex | about 700 per turn (four tools) inside Codex's 19-38K | live R for the ChatGPT plan |
| Images attached by `.opts$images` | 532 per image at 768x512 | the user asked for it [IC-44] |
| Compaction checkpoint | about 1,100 post-compaction first message + up to 2,048 output | keeps long sessions inside the window |"""),
("""- Budgets: `budget = list(tokens =, cost =, turns =)` per call, session defaults in settings; children receive
  a share; checks run before each request; `budget_near` at 80%; exceeding stops at a turn boundary with
  `status = "budget"`, a `budget_exceeded` event and the classed `gptr_error_budget_<kind>` for programmatic
  callers; the partial transcript is kept [G2].""",
"""- Budgets: `budget = list(tokens =, cost =, turns =)` per call, session defaults in settings (default ceiling 2e6
  tokens and 5 USD per top-level call; `null` disables) [IC-66]; budgets are hierarchical: every request charges the
  root session and children start with the smaller of their share and the root's remainder; at most 20 `gptr()`
  calls per `r` evaluation and 10,000 elements per System 1 call; the CLI routes get `--max-turns`/
  `--max-budget-usd` or a turn counter; checks run before each request; `budget_near` at 80%; reaching a limit asks
  to extend interactively and otherwise stops at a turn boundary with `status = "budget"`, a `budget_exceeded` event
  and the classed `gptr_error_budget_<kind>` for programmatic callers; the partial transcript is kept [G2]."""),
("""| Static prefix budgets per preset and mode | `tests/testthat/test-bench-context.R` (P07) | every `R CMD check`, offline, CRAN-safe | each section within its budget (§7.3); each preset's estimate within 5% of the committed baseline `fixtures/bench/prefix-baseline.json` (initial values: the measured totals of §12.1) |""",
"""| Static prefix budgets per preset and mode | `tests/testthat/test-bench-context.R` (P07) | every `R CMD check`, offline, CRAN-safe | each section within its budget (§7.3); each preset's estimate within 5% of the committed baseline `fixtures/bench/prefix-baseline.json` (initial values: the measured totals of §12.1: 1,271 / 2,360 / 2,844 / 2,987); no shipped text mentions `str(` [IC-67] |"""),
("""| Golden transcripts NS-1..NS-11 | `dev/bench/tokens/` (P24) | CI (not on CRAN), fake provider replay in about 0.2 s | ratchet vs baseline: prefix +2%, input and output totals +5%, request count and image tokens +0, describer facts no loss, catalogs +5%; failure raises `gptr_error_token_regression` [G2 h_bench] |""",
"""| Golden transcripts NS-1..NS-11 | `dev/bench/tokens/` (runner and NS-2/NS-3 from P07 at M1; fixtures added by P10, P13, P15, P18, P19, P22, P23, P24) | the CI `bench` job (not on CRAN; installs rtiktoken), fake provider replay in about 0.2 s | ratchet vs baseline: prefix +2%, input and output totals +5%, request count and image tokens +0, describer facts no loss, catalogs +5%; failure raises `gptr_error_token_regression` [G2 h_bench; IC-73] |"""),
("""| Live calibration | `dev/bench/tokens/live.R` (P24) | `GPTR_LIVE_TESTS=true` only | Anthropic's free count-tokens endpoint plus tiny paid requests: refit estimator priors, check cache accounting; decides per-model presets and the `apply_patch` question |""",
"""| Live calibration | `dev/bench/tokens/live.R` (P24) | `GPTR_LIVE_TESTS=true` only; part of P25's release checklist | Anthropic's free count-tokens endpoint plus tiny paid requests: refit estimator priors, check cache accounting; NS-1..NS-11 against one Anthropic and one OpenAI model with request counts within +2 and input tokens within 20% of the golden transcripts (the golden transcripts script the agent, so they measure harness potential; this measures behaviour) [IC-73]; decides per-model presets and the `apply_patch` question |"""),
("""| 1 (static about 2,860 + first message about 390) | about 3,250 | 0 (1 h anchors written) | about 150 (one composed `r` call + note) |
| 2 (after the tool result) | about 3,600 | about 3,250 | about 150 (answer) |
| `!dim(markers)`, `/mode auto` | 0 | - | - |

About 6,850 input tokens (about 3,250 cache reads) and 300 output tokens plus thinking: roughly $0.02.""",
"""| 1 (static about 2,990 + first message about 390) | about 3,380 | 0 (1 h anchors written) | about 150 (one composed `r` call + note) |
| 2 (after the tool result) | about 3,730 | about 3,380 | about 150 (answer) |
| `!dim(markers)`, `/mode auto` | 0 | - | - |

About 7,100 o200k input tokens (about 3,380 cache reads) and 300 output tokens plus thinking. Projected to
Claude's tokenizer (x1.35, range 1.3-1.6 [§12.5]) that is about 9,600 input tokens (about 4,560 cache reads):
roughly $0.03 at Sonnet 5.5 prices [IC-73]."""),
("""| Plan hand-off surprises a user (a later call sees an earlier plan) | low / low | once only, same environment and process, one hour; printed notice; `<plan>` visible in `/context`; `options(gptr.plan_handoff = FALSE)` |""",
"""| Plan hand-off surprises a user (a later call sees an earlier plan) | low / low | once only, only to the next top-level call of the same environment and process within one hour (any other call discards it); printed notice and step list; `<plan>` visible in `/context`; `options(gptr.plan_handoff = FALSE)` [IC-56] |
| Model code or injected project text reconfigures the permission gate (hooks, rules, trust, options, `.gptr` control files) | medium / high | fail-closed gate with non-removable kernel policies; option snapshot per run; `control` category and paths at level 4 with `ask_human`; the user-level project file for remembered answers; trust-dependent instruction authority and trust fingerprints; relays by source; adversarial e2e tests [IC-52..IC-55] |
| Secrets persisted before registration, or leaked by redirects or child logs | medium / high | `followlocation = 0`; child output persisted only through the redactor; `gptr_scrub()` and the late-registration warning [IC-64, IC-70] |"""),
("""| Pid reuse after a crash makes a stale session lock look alive | low / low | lock timeout and a `force` option on resume [G3 risks] |""",
"""| Pid reuse after a crash makes a stale session lock look alive | low / low | `pid_alive()` compares the process creation time (ps), a 10-minute heartbeat, a lock timeout and a `force` option on resume [G3 risks; IC-59] |"""),
("""| Scope: 117 R files, 25 plans, 63 exports for a small team | medium / medium |""",
"""| Scope: 118 R files, 25 plans, 63 exports for a small team | medium / medium |"""),
]
apply(P, pairs)
