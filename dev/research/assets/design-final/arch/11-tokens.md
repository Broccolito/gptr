
---

## 12. Token-efficiency design (S-12, REQ-42)

The design spends tokens only where R cannot compute the answer itself. Four levers, each measured:
**compression** (R and Shiny instead of HTML/JS and shell transcripts), **reference** (objects by name with
budgeted descriptions), **composition** (many operations in one `r` evaluation instead of many tool round
trips) and **stability** (a frozen, append-only, cache-anchored prefix). Every choice that costs tokens is
listed in 12.4.

### 12.1 Static prefix per preset (measured, o200k proxy; §7)

| Preset | Tool array | T0 | T1 (fixture: `<r_env>` + 2 built-in skills) | Static total | Reference points |
|---|---|---|---|---|---|
| `minimal` (sub-agents) | 675 | 624 | 0 | **1,299** | Pi's 4-tool default 919-1,175 [G2 (b)] |
| `standard` core (no documents, artifacts, System 1; no human) | 675 | 1,159 | 551 | **2,385** | |
| `standard`, non-interactive, all sections | 675 | 1,592 | 551 | **2,818** | G4's 7-tool default 3,598 |
| `standard`, interactive (+ `ask`), all sections | 820 | 1,609 | 551 | **2,980** | Claude Code CLI 3-18K [07] |
| `extended` | about 1,300 | about 1,900 | 551 | about 3,750 | Codex 19-38K per turn [08] |

Each MCP or plugin signature adds about 36 tokens (catalog budget 1,500); each visible skill 33-50 (budget
1,500); project instructions typically 150-600 (budget 6,000, warning above). After the first request the
static prefix is read from cache at 0.025-0.1x the input price.

### 12.2 Budget of every context component

| Component | Typical | Budget and enforcement |
|---|---|---|
| `<project_instructions>` | 150-600 | 6,000 (warn), 64 KiB hard cap [20 §4.5] |
| `<environment>` | 76 (measured) | 100 |
| `<mode>` | 50 (manual) - 125 (plan) (measured) | 150 |
| `<plan>` | plan text | 1,500 |
| `<workspace>` | 122 for six objects (measured) | 600; at most 12 lines, largest first, then "(+ n smaller objects: use ls())" |
| `<workspace_changes>` | about 70 | 300; only when non-empty |
| `<attached>` per object | 60-150 | 150 default, 300 maximum; level-based describers keep 90.8% of 98 facts at 150 [G2 (c)] |
| `<skill_content>` | skill body | 5,000 per skill, 10,000 re-injected after compaction [G4 §3.8] |
| `r` result | 30-300 | about 4,000 estimated tokens, head 40% / tail 60% by lines, spill file, `gptr$out(id)`; half the budget once the context passes half the compaction threshold [G2 (g), G4 §4.4.5] |
| namespace helper print (`sh`, `grep`, `sql`, `py`, `out`) | 100-300 | 1,500, and at most 0.6 x the remaining `r` budget; stderr at most 25% with 200/100-token floors [G5 + fact-check] |
| `read` | file slice | 2,000 lines, 50 KB and 12,000 tokens; line numbers off |
| `edit` result | about 20 | message only; a diff of at most 400 tokens only when something deviated |
| direct MCP result | - | 4,000 |
| plot image | 532 (768x512, res 120) | one per plot; `gptr$plot()` for 1000x700 (about 900) |
| artifact result | about 80 + about 900 screenshot | - |
| team `<agent_reports>` | per child | 2,000 per child (full text in `$text`) |
| hook-injected context | - | 10,000 characters |
| System 1 request | 250-280 overhead | the API's state limit |
| compaction checkpoint | about 634 (G4 fixture) | summary output 2,048; user messages 2,000; objects 800; decisions 300 |
| steering relay | about 15 + the text | - |
| secret marker | 6-10 | - |

### 12.3 Savings mechanisms

| Mechanism | Saving | Evidence |
|---|---|---|
| Four direct tools; search and everything else as `gptr$` members | 675 vs 1,199 tokens of tool schema per uncached request; about 36 vs 328 per member [G1 §2.5; an upper bound, G1 fact-check] | G4 §2.8, measured §7.2 |
| MCP tools as R signatures | 50 GitHub tools: 2,285 vs 11,361 tokens; 125 tools: 2,285 vs 28,534 | G2 (b) |
| Composition in one `r` call | 2.2x fewer requests and 3.6x less cumulative input on golden transcripts; SQL in 3 steps 6,476 -> 175 tokens; 8 polyglot tasks 45,140 (bash tool) -> 7,592 (same commands via `gptr$sh`) -> 1,967 (R-composed), i.e. 22.9x | G2 (d), G5 token table |
| R as polyglot glue with default budgets | results stay R objects; cross-language data never passes through the context; frugal bash can match on pure text filtering, R wins on defaults, objects and round trips | G5 fact-check 11 |
| Objects by name, budgeted descriptions | a 5,000-row frame inline costs about 127k tokens vs 1-25 by name | G2 (a), 17 |
| Shiny instead of HTML/JS | 2.35x fewer tokens over 20 apps; edits instead of rewrites 3.9x cheaper | G2 (a) |
| Frozen, cache-anchored, append-only prefix | 2.7x cheaper than rebuilding the prompt per turn; the gap-based TTL is within 2.1% of the best policy | G4 §2.9 and fact-check |
| No in-place micro-compaction; in-conversation checkpoint | avoids +32%; checkpoint input 9.4x cheaper than a fresh summary request (input side) | G4 §2.9-2.10 |
| Output caps in tokens with head/tail and a handle | Pi's 2,000-line/50 KB cap still admits about 29k tokens of printed R; the notice costs 26 vs 64 tokens | G2 (g), G5 fact-check |
| Plots at 768x512 | 532 vs 900 tokens per image, still legible | G2 (g) |
| Read line numbers off | avoids +19-26% | G2 (g) |
| Edit results without a diff unless something deviated | up to about 400 tokens per edit | 11, 20 |
| `{identifier}` interpolation instead of attaching loop scalars | about 10 vs 60-120 tokens per call | P-C §4.1.4 |
| Compact skill catalog with activation through `read` | 33-50 vs 94 tokens per skill; no skill tool whose enum would break the cached tool array | G2 (b), 16 |
| `minimal` preset for sub-agents | 1,299 vs about 2,980 static tokens per child request | §12.1 |
| System 1 for judgements | about 383 vs 2,174 input tokens per decision; about 100x cheaper in dollars | G2 (d), 04 |
| System 1 over a session | 55-70 characters of state instead of the transcript | G3 (12) |
| Replay and caches | 0 tokens for replayed blocks, cached System 1 elements, knitr-cached chunks, `print`, `$value`, audit entries | G3 (14), 14 |
| Redaction markers | 6-10 tokens instead of 26-104 per key | G6 |
| Rewind with a byte-identical prefix | 0 tokens after a full restore; 87 after a partial one; a model-driven revert costs 4,349 | G7 |

### 12.4 Choices that cost tokens (stated, S-12)

| Choice | Cost | Why it is worth it |
|---|---|---|
| `<r_session>` with the helper and polyglot catalog | 443 per request (cached) | replaces direct grep/find/ls/shell tools (about 1,100) and makes composition the default |
| `ask` tool when a human is present | 145 + 17 per request (cached) | a safe UI pause that model code cannot express |
| `<documents>`, `<system1>`, `<artifacts>` sections | 186, 123, 124 when active (cached) | recorded code quality, cheap decisions, compact apps |
| `<r_env>` capability block | about 399 (cached) | prevents failed `library()` calls and slow base-R choices |
| Project instructions every session | 150-600 typical (cached, anchored) | the S-6 contract |
| Per-object `<attached>` descriptions | 60-150 each | the model needs shape and types to write correct code |
| Plot images returned to the model | 532 per plot | REQ-23; vision models check their own plots |
| Artifact screenshots | about 900 | the model verifies the app before claiming success |
| Egress-safe, verbose permission denials | 30-60 per denial | the model must know what was refused and how to proceed |
| The `extended` preset | about +770 over standard | only for models that underuse code or need a 4,096-token cacheable prefix |
| The Codex route | 19-38K extra input per turn | shown when selected; the ChatGPT-plan alternative (Sign in with ChatGPT) is v1.x |
| Model switches | one cache miss of the static prefix per switch | REQ-14 cross-provider hand-off |
| Compaction checkpoint | about 1,100 post-compaction first message + up to 2,048 output | keeps long sessions inside the window |

### 12.5 The calibrated estimator (D-19) [G2 (f), 21 §2.8]

`est_tokens(x, class)` uses characters per o200k token by content class, fitted on a 730k-character corpus:
prose 4.36, code 3.24, printed R output 2.13, `str()` output 2.01, CSV 1.57, JSON 2.90, errors 2.98,
describer output 2.39; CJK 0.848 tokens per character; other non-ASCII 0.35 tokens per character. Median error
11.4% (bias -3.4%) vs 43% (bias -44%) for chars/4, which underestimates printed R by about 51%. Producers tag
content classes (the evaluator, `read` by file extension, MCP JSON). Images: Anthropic `ceil(w/28) *
ceil(h/28)`; OpenAI and Gemini per their documented formulas (dated in the catalog [G2 fact-check]).

Context projection = the last provider-reported input total + output + `m * est(new entries)`, where the
per-session multiplier `m` starts at a provider prior (OpenAI 1.00, Claude 4.7+ 1.35, Gemini 1.10) and is
updated by an EWMA of the log ratio whenever new content is at least 150 estimated tokens (15-19% error on new
content; 0.3% on the usage-anchored whole). Provider-reported usage is authoritative. No tokenizer ships;
rtiktoken is dev-only. The estimator is an `estimator` spec (replaceable). Producers must mark text UTF-8 at
the source (in a C locale unmarked text is over-counted, which is conservative [G2 fact-check]).

### 12.6 Accounting and budgets

- Usage rows per request with route and TTL-split cache writes (§5.5); `gptr_usage(x, by =)` aggregates
  sessions, teams, children and the System 1 log; `gptr_usage(s, detail = TRUE)` and `/context` give the
  per-request **token ledger** by component, marking cache reads; `gptr_registry()` and `gptr_skills()`
  show each capability's declaration cost; `gptr_prompt()` shows the frozen prefix with per-section counts.
- Budgets: `budget = list(tokens =, cost =, turns =)` per call, session defaults in settings; children receive
  a share; checks run before each request; `budget_near` at 80%; exceeding stops at a turn boundary with
  `status = "budget"`, a `budget_exceeded` event and the classed `gptr_error_budget_<kind>` for programmatic
  callers; the partial transcript is kept [G2].
- Per-kind budgets are enforced at registration by `gptr_check()` (sections, catalogs, context blocks, direct
  tool descriptions at most 400 tokens) and at render time (trimming least-recently-used catalog descriptions
  first; names are always kept).
- The prefix guard (`cache_break` events) and cache-read share per request make cache regressions visible.

### 12.7 Benchmark suite (plans must implement)

| Suite | Where | Runs | Gate |
|---|---|---|---|
| Static prefix budgets per preset and mode | `tests/testthat/test-bench-context.R` (P07) | every `R CMD check`, offline, CRAN-safe | each section within its budget (§7.3); each preset's estimate within 5% of the committed baseline `fixtures/bench/prefix-baseline.json` (initial values: the measured totals of §12.1) |
| 20-turn byte-prefix property | `tests/testthat/test-context-prefix.R` (P07) | every check, offline | consecutive same-target requests are byte prefixes across turns, model switches and returns, tool and skill activation, steering, mode changes; the tools, system and anchored project block survive compaction; negative controls detect breaks [G4 §5.9] |
| Golden transcripts NS-1..NS-11 | `dev/bench/tokens/` (P24) | CI (not on CRAN), fake provider replay in about 0.2 s | ratchet vs baseline: prefix +2%, input and output totals +5%, request count and image tokens +0, describer facts no loss, catalogs +5%; failure raises `gptr_error_token_regression` [G2 h_bench] |
| Polyglot tasks | `dev/bench/polyglot/` (P24) | CI | G5's 8 tasks; totals of variants B and C within 10% of baseline |
| Shiny vs HTML/JS ladder | `dev/bench/shiny-html/` (P24) | on demand | G2's 20 apps (parse, launch, HTTP 200, chromote interactions); ratio and edit-vs-rewrite tracked |
| Cache economics | `dev/bench/cache-sim/` (P24) | on demand, before changing layout or TTL policy | G4's simulator: a change may not raise simulated session cost by more than 2% |
| Live calibration | `dev/bench/tokens/live.R` (P24) | `GPTR_LIVE_TESTS=true` only | Anthropic's free count-tokens endpoint plus tiny paid requests: refit estimator priors, check cache accounting; decides per-model presets and the `apply_patch` question |
| Performance | `dev/bench/perf/` (P24) | on demand | grep/read/SSE/diff timings from 11, 19, 21 |

### 12.8 One north-star task end to end (NS-1, Sonnet 5.5)

| Request | Input | of which cache read | Output |
|---|---|---|---|
| 1 (static about 2,860 + first message about 390) | about 3,250 | 0 (1 h anchors written) | about 150 (one composed `r` call + note) |
| 2 (after the tool result) | about 3,600 | about 3,250 | about 150 (answer) |
| `!dim(markers)`, `/mode auto` | 0 | - | - |

About 6,850 input tokens (about 3,250 cache reads) and 300 output tokens plus thinking: roughly $0.02. The
same work through the Codex route would add 19-38K input tokens per turn, and a script-and-rerun harness would
reload the 5 GB object for every fix.
