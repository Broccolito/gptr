# G2 - Token-efficiency measurement, calibrated estimator, budgets and benchmark suite (S-12 / REQ-42)

Research track G2, 2026-09-29. **Scope:** measure what S-12 claims about R's token efficiency, and design:
- a calibrated pure-R token estimator for gptr;
- output budgets and budget conditions;
- a reproducible token-efficiency benchmark suite that runs offline in CI.

**Conventions.** All code below uses `=` for assignment and `|>` for pipes (S-9). Scratch files live in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/`, written `G2/` below.

**Measurement.** The oracle tokenizers are rtiktoken 0.0.7 (`o200k_base` and `cl100k_base`) from the private
library. I made no paid or keyed model calls. The Claude and Gemini tokenizers are not public; §2.8 bounds them.

## 1. Executive summary

- **Shiny vs HTML/JS (part a).** I wrote 20 apps against one functional spec: 5 complexity levels, two
  independent implementations per side per level. The HTML versions load Plotly, DataTables and Bootstrap
  from CDNs, which makes the HTML cost a lower bound for dependency-free HTML.
  - **Verification.** All 20 pass a four-step ladder: parse, launch, HTTP 200, and a headless Chrome check that
    performs real interactions, including a real mouse brush and a CSV download. The ladder catches bugs:
    10 of 10 injected bugs failed it.
  - **Code tokens.** HTML/JS costs **2.35x** the o200k tokens of Shiny overall (cl100k: 2.31x).
    - By level, the ratio is 1.62x to 2.86x.
    - Across the individual implementation pairs it ranges from 1.02x to 4.32x.
    - Report 17 measured 3.1x to 3.7x, with n = 3.
  - **Growth.** HTML grows faster with complexity: about +80 tokens per level, against +57 for Shiny.
  - **Data dominates, not code.** Inlining a 5,000-row data frame costs 127,113 tokens as row JSON, 72,125 as
    column JSON and 77,122 as CSV: about 25.4, 14.4 and 15.4 tokens per row, linear in rows (100, 1,000,
    5,000 and 50,000 rows all give 25.4 per row as row JSON). Referencing it by name costs 1 token (25 with a
    schema line). *(Corrected in verification: the earlier "33 tokens per row" came from a 50,000-row copy
    whose non-default row names added a `"_row"` field to every JSON record.)*
  - **Revisions.** A full rewrite costs 3.9x (Shiny) and 6.1x (HTML) the output tokens of exact-match edits.
- **Fixed per-request prefix (part b).** The prefix is the system prompt plus the tool declarations, measured
  as the actual provider wire JSON (o200k).
  - Pi's 4-tool default: 919 tokens (1,175 with its `<docs>` section).
  - gptr with 7 tools (read, r, edit, write, grep, find, ls), as reports 01, 12 and 19 specified them: 2,096.
    With 10 tools: 2,816. With 11 tools plus the artifact section: 3,570.
  - A **lean rewrite** of the 7-tool preset, with the same tools and parameters: 1,153 (-45%).
  - Wire formats differ by less than 3% across providers. The exceptions are OpenAI strict mode (+3% to +8%
    over plain Responses, depending on the preset; +6.4% for gptr-7) and namespace wrapping (+24 tokens,
    about +1%).
  - Anthropic adds a 286-token tool prompt on Opus and Sonnet 5.5 (verified).
  - **MCP exposure** (direct declarations vs an R-signature catalog under a 3,000-token budget):

    | Server and number of tools | Direct declarations | R-signature catalog |
    |---|---|---|
    | GitHub, 50 tools | 11,361 | 2,285 (2,547 unbounded) |
    | GitHub, 125 tools | 28,534 | 2,285 |
    | Claude Code, 29 tools | 31,706 | 1,672 |

  - **Skills catalogs.** Pi's XML format costs 94 tokens per skill (157 real skills: 14,536 tokens). A compact
    one-line format with descriptions capped at 250 characters costs 33 tokens per skill.
- **Environment descriptions (part c).** I described 20 object types at budgets of 50, 150, 300 and 600 tokens.
  - Report 12's describer converts budgets at 3.5 characters per token, but its output runs at 2.4. At the
    50-token budget, 12 of 20 descriptions overran it, by up to 1.42x.
  - It also misses or misstates five facts:
    - Date and POSIXct values appear as day numbers.
    - dgCMatrix loses its dimensions.
    - A formula loses its text.
    - Nested lists lose their inner names.
    - `object.size()` reports 3.7 GB for the compact ALTREP `1:1e9`.
  - A level-based describer calibrated with the estimator keeps 73.5%, 90.8% and 99.0% of 98 checked facts at
    50, 150 and 300 tokens, and stays within budget except once (1.08x).
  - Plain `str()` gives 64% of the facts for 2,992 tokens.
- **Composition vs round trips (part d).** Golden transcripts for north-star tasks §1, §2, §3, §8, §10 and §11.
  Every r tool result in them is real output from Seurat 5.4.0, nlme or base R.
  - One r evaluation that chains tools, MCP functions and helpers, compared with separate tool calls, needs
    **2.2x fewer requests** and **3.6x less cumulative input**.
  - Cost, separate over composed:

    | Model | Cached | Uncached |
    |---|---|---|
    | Claude Sonnet 5.5 | 2.0x | 3.3x |
    | GPT-6.1 Sol | 1.9x | - |
    | Gemini 3.8 Flash | 2.1x | - |

  - The MCP task gains most: 9.2x the input and 17x the tool-result tokens.
  - Output tokens differ only 1.13x. On task 1, `verbose = FALSE` saves 3.6% of S's cumulative input (720 of
    19,887 tokens), which is 4.7% of the S-to-C gap. Round trips drive the gap.
  - In the composed style, 78% of all input is the re-sent prefix, so a lean prefix and caching dominate the
    remaining cost.
  - For nine cluster labels, System 1 (Jev) costs about 3,447 input tokens ($0.00015). A System 2 emulation
    through gptr costs 19,566 input tokens ($0.014 cached on Sonnet 5.5), about 100x more.
- **Polyglot helpers vs a bash tool (part e).** The tasks cover shell commands, a shell script, git, Python
  (reticulate), SQL (RSQLite and duckdb) and a knitr engine.
  - Per command, R helpers cost about the same as bash: 198 vs 165 call tokens and 151 vs 156 result tokens.
  - Documenting the helpers in the system prompt costs 105 tokens, the same as a bash tool declaration (110).
  - **The gain is composition.** A git → SQL → Python pipeline takes one r call instead of four bash calls.
    The results stay R objects, and the helpers work on Windows without bash.
- **Calibrated estimator (part f).** The corpus has 481 chunks and 730k characters, including 167k characters of
  printed R output (17x report 21's corpus).
  - Characters per o200k token by class: CSV 1.57, printed data frames 1.94, `str()` 1.97, tibble 2.00,
    `summary(lm)` 2.28, JSON 2.94, errors 3.05, R code 3.21, Markdown 4.28, CJK 1.70.
  - The class-aware `estimate_tokens(x, class)` has a held-out median absolute error of **11.4%** (p90 32%,
    total bias -3.4%). For comparison:

    | Estimator | Median absolute error | p90 | Total bias |
    |---|---|---|---|
    | `estimate_tokens(x, class)` | 11.4% | 32% | -3.4% |
    | chars/4 | 43% | 63% | -44% |
    | chars/2 | 27% | 100% | +12% |
    | report 21's rule | 19% | 63% | +5% |

  - It is pure R: 34-56 ms for the 0.96 MB held-out corpus (two runs). rtiktoken 0.0.7 needs 0.13-0.21 s
    per call in the recorded runs, up to about 0.34 s under load.
  - Recalibrating per session from provider usage lowers the median error on new content from 21-30% to 15-19%.
  - Once the estimate is anchored on reported usage, the whole-context error is **0.3% (median)**.
- **Output budgets (part g).**
  - **r results.** Pi's 2,000-line / 50 KB cap still admits **29,072 tokens** for one printed data frame, and
    its tail-only cut drops the column header. Recommendation: a token-denominated head+tail cap of about 4,000
    tokens, with a spill file.
  - **read.** Line numbers off. If they are ever on, use `N|` (+6.5% to +12%) rather than `cat -n` (+19% to +26%).
  - **edit.** Return a `-U0` diff capped at about 400 tokens: median 111 tokens, against 14 for the message alone.
  - **Plots.** Default to **768x512 at res 120**: 532 Claude and 461 GPT-5.x tokens, against 900 and 845 at
    1000x700. It stays legible even for a 12-panel facet plot.
- **Design.**
  - Every request writes an INFRA-20 usage record, extended with the harness's per-section estimates.
  - `gptr_budget(max_tokens, max_turns, max_cost, max_context)` stops the run with classed conditions
    (`gptr_error_budget_tokens` and the like).
  - An offline benchmark replays golden transcripts through the fake provider in pure R (0.13-0.24 s). It compares
    the result with a JSON baseline, ratchet-style with fixed tolerances, and fails with
    `gptr_error_token_regression`.
  - An optional live mode behind `GPTR_LIVE_TESTS` reads provider usage and the count-tokens endpoints.
    Anthropic's is free; whether OpenAI's and Gemini's are free is UNCERTAIN.
  - All of these were prototyped and run.

## 2. Findings with evidence

### 2.1 Shiny vs HTML/JS: 20 verified apps (part a)

**Method.**
- **Spec and data.** The functional spec is `G2/a_apps/SPEC.md` (verbatim in §5.1). It fixes element ids, so
  one checker tests every app. Data: `sales` (5,000 x 5), `cars_df` (mtcars plus `name`), and `inv_a`/`inv_b`.
- **Two implementations per side:**
  - `shiny_a`: terse bslib with base graphics or ggplot2.
  - `shiny_b`: conventional fluidPage with DT, plotly and wellPanel.
  - `html_a`: vanilla ES2020 with Plotly and Bootstrap.
  - `html_b`: jQuery with DataTables and Plotly.
- **Data in HTML apps.** They load `data/<name>.json`, which the harness exports, so data never counts as code.
  This favours HTML.
- **Offline test.** CDN URLs are rewritten to the copies shipped inside installed R packages, with no
  downloads (report 17 §2.9's technique).

**Functional ladder** (VERIFIED, `G2/out/a_check_original.txt`). Each app goes through four steps:
1. Parse, or a static `shinyApp()` check.
2. Launch in a callr child (Shiny) or a static-server child (HTML).
3. HTTP 200.
4. Headless Chrome (chromote 0.5.1): the spec's assertions plus one real interaction per level.
   - Selectize/select changes and a tab click.
   - A real CDP mouse drag for the brush. The data bounds are read back from the Shiny input or plotly's
     `layout.selections`, and the expected rows are recomputed from them.
   - The CSV download is fetched, or its Blob is intercepted.
   - Cell edits: DT, numericInput and contenteditable.
   - JS exceptions, `.shiny-output-error` elements and server-log `Error` lines are collected.

**Results.** **20/20 PASS.**
- **Mutants** (`G2/a_mutants.R`). One subtle bug per level was injected into `shiny_a` and `html_a`. Examples:
  - wrong sort order, or an off-by-one count;
  - median instead of mean, or swapped brush axes;
  - the wrong edited column, or a total that misses one module.

  The checker failed **10/10** of them (`G2/out/a_check_mutants.txt`).
- **Revised apps.** The apps from the revision experiment pass the original checks plus a per-revision feature
  check (`G2/out/a_check_revised.txt`, 20/20).
- **Screenshots** are in `G2/a_shots/`. I inspected L4 `shiny_a` after the brush and L5 `shiny_a` after the edit.

**Token counts** (VERIFIED, `G2/out/a_tokens.txt`, o200k):

| Level | Shiny a / b | HTML a / b | HTML/Shiny (means) | Pair range | As write-call argument |
|---|---|---|---|---|---|
| L1 static table | 159 / 197 | 356 / 447 | 2.26 | 1.81-2.81 | 2.11 |
| L2 filter + plot | 162 / 233 | 410 / 564 | 2.47 | 1.76-3.48 | 2.27 |
| L3 dashboard, value boxes, 3 tabs | 348 / 526 | 1,079 / 1,417 | 2.86 | 2.05-4.07 | 2.67 |
| L4 linked brushing + download | 194 / 345 | 584 / 839 | 2.64 | 1.69-4.32 | 2.54 |
| L5 editable table in 2 modules | 320 / 530 | 542 / 838 | 1.62 | 1.02-2.62 | 1.57 |
| **All 20** | 3,014 | 7,076 | **2.35** (cl100k 2.31) | 1.02-4.32 | 2.22 |

- **Growth curve.** The mean per level is 178 → 198 → 437 → 270 → 425 for Shiny and 402 → 487 → 1,248 → 712
  → 690 for HTML. The least-squares slope is 57 tokens per level for Shiny and 80 for HTML.
  - The levels are not monotone in size: L3 has the most UI elements.
  - The HTML/Shiny ratio is lowest for L5, where the verbose `shiny_b` builds a numericInput table by hand.
  - It is highest for L3 and L4, where Shiny's value boxes, tabs, `brushedPoints()` and `downloadHandler()`
    replace DOM wiring.
- **Tokenizers agree.** The per-file cl100k/o200k ratio has a median of 0.992 (range 0.963-1.003).
- **JSON escaping** inside a write call adds 24.7% to Shiny and 17.1% to HTML, because R code has more quotes
  per token.
- **Data transfer** is the dominant term:

  | Object | Rows JSON | Columns JSON | CSV | By name | Name + schema line |
  |---|---|---|---|---|---|
  | `sales` (5,000 x 5) | 127,113 | 72,125 | 77,122 | 1 | 25 |
  | `sales[1:100, ]` | 2,546 | 1,458 | 1,555 | 1 | 24 |
  | `cars_df` (32 x 12) | 2,056 | 1,157 | 1,181 | 2 | 48 |
  | 50,000 rows | 1,271,112 (25.4 tokens/row)† | - | - | 1 | - |

  † Corrected in verification. The prototype's `sales[rep(...), ]` copy has row names such as `"1.1"`, so
  `jsonlite::toJSON()` adds a `"_row"` field to every record. That gave 1,651,123 tokens (33.0 per row), the
  figure in `G2/out/a_tokens.txt` (§5.2). With default row names the count is 1,271,112. The per-row cost of
  row JSON is 25.4 at every size measured.

  Report 17's HTML fallback injects `window.GPTR_DATA` on the harness side. Even `kind = "html"` artifacts
  therefore never put data through the model; only the schema line is paid.
- **Revisions** (VERIFIED, `G2/out/a_revisions.txt`). Each level got one functional change, applied to all four
  of its apps: a new column, a bar colour, a fourth value box, a `cyl` column in the table and CSV, and a
  low-stock line. The changes were written as Pi-semantics exact-match edits (each `oldText` unique in the
  original).

  | | Shiny | HTML | HTML/Shiny |
  |---|---|---|---|
  | Edit calls (tokens) | 1,045 | 1,431 | 1.37x |
  | Full rewrites (tokens) | 4,041 | 8,697 | 2.15x |
  | Rewrite / edit | **3.9x** | **6.1x** | |

  The rewrite/edit ratio reaches 15.9x for the largest HTML file (L4 `html_b`).
- **Caveats.**
  - I wrote all 20 apps, so there is author bias. Model-generated samples would require paid calls.
  - HTML with libraries is a lower bound for HTML.
  - The counts exclude fix-up iterations. Report 17 expects 1-3 of them, each with about 1,000 screenshot
    tokens, for both sides.

### 2.2 System prompt + tool schemas per preset and wire format (part b)

**Method.** Tool definitions are taken verbatim from the reports:

| Tool | Source |
|---|---|
| Pi tools | Report 01 §3.2-§3.5 |
| gptr read, edit, write, grep, find, ls | Track-01 prototype `builtin_tools()`, sourced unchanged |
| `r` | Report 12 §3.1 |
| `ask` | Report 18 §3.6 |
| `artifact` | Report 17 §3.2 |
| `apply_patch` | Report 20 §3.4 (Lark grammar) |
| `r_inspect`, `agent` | Written from report 20 §4.1's parameter table |

System prompts: Pi's verbatim default (01 §3.10), and the gptr structure of 01 §5.10 with `<r_performance>`
(19 §3.1) and `<artifacts>` (17 §4.4).

The prompt and tools are serialised as each provider's request fields:

| Wire format | Request fields |
|---|---|
| Anthropic | `system` + `tools[{name, description, input_schema}]` |
| OpenAI Responses | `instructions` + `tools[{type: "function", ...}]`; optionally wrapped in a `{type: "namespace"}` entry (08 §3.1) or sent in strict mode |
| Chat Completions | a `messages[0]` system message + `tools[{type: "function", function: {...}}]` |
| Gemini | `systemInstruction` + `tools[{functionDeclarations: [...]}]` |

**Results** (VERIFIED, `G2/out/b_presets.txt`, o200k of the JSON payload):

| Preset | Tools | System | Anthropic | Responses | Resp. + namespace | Resp. strict | Chat | Gemini |
|---|---|---|---|---|---|---|---|---|
| Pi default (with `<docs>`) | 4 | 547 | 1,175 | 1,187 | 1,211 | 1,240 | 1,204 | 1,192 |
| Pi default without `<docs>` | 4 | 299 | 919 | 931 | 955 | 984 | 948 | 936 |
| gptr-4 read, r, edit, write | 4 | 767 | 1,544 | 1,556 | 1,580 | 1,609 | 1,573 | 1,561 |
| gptr-7 (+grep, find, ls) | 7 | 804 | **2,096** | 2,117 | 2,141 | 2,253 | 2,140 | 2,116 |
| gptr-7 without `<r_performance>` | 7 | 398 | 1,675 | 1,696 | 1,720 | 1,832 | 1,719 | 1,695 |
| gptr-10 (+r_inspect, ask, agent) | 10 | 840 | 2,816 | 2,846 | 2,870 | 3,070 | 2,876 | 2,839 |
| gptr-11 (+artifact, `<artifacts>`) | 11 | 1,221 | 3,570 | 3,603 | 3,627 | 3,877 | 3,635 | 3,594 |
| gptr-7, apply_patch instead of edit/write | 6 | 671 | 1,705 | 1,900* | 1,924* | 2,014* | 1,744 | 1,724 |
| gptr-lean-4 (short r, no r_perf) | 4 | 361 | 957 | 969 | 993 | 1,017 | 986 | 974 |
| **gptr-7 lean rewrite** (`G2/out/b_lean.txt`) | 7 | 258 | **1,153** | 1,174 | - | - | 1,197 | 1,173 |

\* On Responses, apply_patch is the freeform grammar tool (252 tokens); elsewhere it is a one-argument function (71).

- **Per-tool declaration cost** (Anthropic shape):

  | Tool | Tokens | Tool | Tokens |
  |---|---|---|---|
  | bash (Pi) | 110 | ls | 96 |
  | read | 153 | r_inspect | 143 |
  | r (report 12 text) | 254 | ask | 335 |
  | r (lean) | 88 | agent | 199 |
  | edit | 239 | artifact | 350 |
  | write | 85 | apply_patch (function) | 71 |
  | grep | 233 | apply_patch (Responses grammar) | 252 |
  | find | 178 | | |

  Prompt sections: `<r_performance>` 406, `<artifacts>` 360, Pi's `<docs>` 248.
- **Anthropic overheads** (VERIFIED, Anthropic pricing page, 2026-09-29):
  - When tools are present, Anthropic adds 286 tool-use system tokens on Opus and Sonnet 5.5.
  - Anthropic's server-defined bash tool adds 325 tokens on Opus 5, 4.8 and 4.7 (244 on Opus/Sonnet 4.6 and
    earlier; the pricing page lists no figure for the 5.5 models). A custom Pi-style bash costs 110.
  - The 286 figure is for `tool_choice` auto/none; the page gives no any/tool figure for the 5.5 models.
- **The lean rewrite** keeps every tool and parameter. What changes:
  - Descriptions are shortened.
  - Per-property prose that repeats the description is dropped.
  - The rules are reduced to 3 bullets.
  - `<r_performance>` is shortened to about 70 tokens; the details move to a skill, as 19 §3.1 already suggests.

  Its behaviour **has not been evaluated**: that would need model calls. This is listed as a risk in §7.
- **MCP exposure** (VERIFIED, `G2/out/b_catalogs.txt`). Two corpora:
  - GitHub's official MCP server: 125 tool snapshots from `pkg/github/__toolsnaps__` at commit `85598ba`,
    fetched from the public repository as JSON data.
  - Claude Code's own `claude mcp serve` `tools/list`: 29 tools, re-captured with report 16's client. This is
    a local handshake, with no model call.

  A direct declaration costs a median of 169 tokens per GitHub tool (p10 75, p90 424) and 600 per Claude Code
  tool (p90 2,061).

  | Corpus, tools | Direct (Anthropic) | Direct (Responses namespace) | R catalog, 3,000 budget | R catalog unbounded | Signatures, no description | Names only | Deferred (search tool) |
  |---|---|---|---|---|---|---|---|
  | GitHub, 10 | 1,591 | 1,638 | 503 | 503 | 346 | 43 | 67 |
  | GitHub, 50 | 11,361 | 11,528 | 2,285 (44 lines + "6 more") | 2,547 | 1,731 | 214 | 67 |
  | GitHub, 125 | 28,534 | 28,926 | 2,285 | 6,221 | 4,190 | 566 | 67 |
  | Claude Code, 29 | 31,706 | - | 1,672 | 1,672 | 890 | 81 | 58 |

  The catalog budget was filled with a chars/3.2 estimate, but signature lines run at about 4.1 characters per
  token, so the "3,000" budget produced 2,285 tokens. gptr must fill the budget with the calibrated estimator,
  using the `code` class.
- **Skills** (VERIFIED, `G2/out/b_skills.txt`). The corpus is 180 real `SKILL.md` files under `~/.claude`, 157
  with unique names; I read only frontmatter and bodies.
  - Descriptions: median 79 characters (p90 558).
  - Bodies: median **804 tokens** (p90 3,803, max 6,173).

  | Skills | Pi XML | Compact `- name: desc` | Compact, desc ≤ 250 chars | 05's 12,000-char budget | ≈9,000 chars, desc ≤ 160 | Names only |
  |---|---|---|---|---|---|---|
  | 10 | 948 | 473 | 305 | 305 | 252 | 51 |
  | 40 | 3,727 | 1,981 | 1,346 | 1,346 | 1,102 | 213 |
  | 157 | 14,536 | 7,878 | 5,214 | 2,549 | 1,946 | 830 |

### 2.3 Environment descriptions per object type (part c)

**Method** (`G2/c_describe.R`, `G2/c2_describe.R`).
- **Objects.** 20 types:
  - vectors: numeric (1,002,000 values with NA), character, factor, Date, POSIXct;
  - tables and matrices: data.frame, tibble, data.table (keyed), matrix, dgCMatrix (20,000 x 3,000);
  - containers and code: list, nested list, environment, function, formula;
  - models and objects: lm, glm, a Seurat-like S4 object, an R6 object;
  - ALTREP `1:1e9`.
- **Facts.** For each object I listed the 2-9 facts a model needs to use it, 98 facts in all: class, dims,
  column names and types, ranges, NA share, levels, key, dimnames, formula text, and so on. Each fact is
  checked by a regex against the description.
- **Describers compared:**
  - report 12's `gptr_describe()` (`W12/gptr_introspect.R`, sourced unchanged) at budgets 50, 150, 300 and 600;
  - report 10's unbounded describer;
  - plain `str()`;
  - the new level-based `describe2()`.

**Results** (VERIFIED, `G2/out/c_describe_final.txt`):

| Describer | Tokens (20 objects) | Facts found | Facts per 100 tokens | Over budget |
|---|---|---|---|---|
| report 12 @50 | 1,021 | 73.5% | 7.05 | 12 of 20 (max 1.42x) |
| report 12 @150 / @300 / @600 | 1,696 | 88.8% | 5.13 | 4 / 0 / 0 |
| report 10 (unbounded) | 942 | 60.2% | 6.26 | - |
| `str()` | 2,992 | 64.3% | 2.11 | - |
| **G2 describe2 @50** | 675 | 73.5% | 10.67 | 1 (1.08x) |
| **G2 describe2 @150** | 1,152 | 90.8% | 7.73 | 0 |
| **G2 describe2 @300 / @600** | 1,693 | **99.0%** | 5.73 | 0 |

- **Budget adherence.** Report 12 converts budgets at 3.5 characters per token, but describer output measures
  **2.39-2.43 characters per token**. The budget is therefore overrun at 50 tokens, and at 300 and 600 it never
  binds: the output is identical to the 150 version.
- **Gaps in report 12's describer at 300 tokens:**
  - Dates appear as `min 18628, median 19128, max 19628`, and date columns in data frames the same way, because
    the class is dropped before formatting.
  - The dgCMatrix header lacks `20,000 x 3,000`. S4 matrices show only slot lengths, and the workspace summary
    says `length 60,000,000`.
  - A formula shows only `typeof language`.
  - Nested lists show only their top level.
  - The Seurat-like header has no cell or feature counts.
  - `object.size(1:1e9)` returns 4,000,000,048 bytes, so the workspace summary reports **3.7 GB** for a compact
    ALTREP sequence. The description itself took 0.006-0.009 s and did not materialise the vector.
- **describe2** builds 2-3 detail levels per object and returns the richest level whose estimate fits the
  budget. For a data frame, level 0 is the header plus `col:type` pairs, and level 1 adds per-column stats.
  - It estimates size with a `describe` content class of 2.39 characters per token, measured on report 12's
    output.
  - It reuses report 12's copy-safe leaves.
  - It fixes the gaps above with primitives only: dgCMatrix through `attr(x, "Dim")` and `length(attr(x, "x"))`,
    Dates by re-attaching the class to the sampled values.
  - **Limits of the prototype** (verification re-run, `c2_describe.txt`):
    - At the recommended per-object budget of 150, the Seurat-like object still lacks its meta.data
      dimensions, meta.data columns and assay facts. They appear only at 300.
    - The deepest level of the nested list is missing even at 300 and 600.
    - The Seurat header fix in §4.5 is therefore a design requirement, not something the prototype already
      does.
- **Workspace summary.** One line per object, largest first: 21 objects cost 336 tokens (`c_describe.txt`).

### 2.4 Composition vs round trips (part d)

**Method** (`G2/d_tasks.R`, `G2/d_compose.R`). Six north-star tasks, each scripted in two styles:
- **S**: one model-visible call per step; each result goes back to the model.
- **C**: one r evaluation that chains the steps and prints a compact result.
- **S-quiet** (task 1 only): S with `verbose = FALSE`, to separate verbosity from round trips.

Every r result is the real output of the code, evaluated with `evaluate::evaluate()` in a session environment
and formatted as report 12 §3.4 specifies.

| Task | Tool results come from |
|---|---|
| 1, 6 | Seurat 5.4.0 on `SeuratObject::pbmc_small` |
| 2 | nlme |
| 3 | Base R on a simulated count matrix |
| 4 | Report 17 §3.2's artifact tool result shape, plus a 1100x750 screenshot |
| 5 | A local fake ClinicalTrials.gov server returning synthetic JSON in the API-v2 shape (MCP results) |

**Token accounting.**
- Request k's input is the prefix (gptr-7) plus all previous messages, serialised as Anthropic-shaped JSON and
  counted with o200k. Images use the Claude patch formula.
- Output is the assistant text plus the tool-call JSON. Thinking tokens are excluded.

**Prices** (USD per MTok, VERIFIED 2026-09-29):

| Model | Input | Output | Cache read | Cache write |
|---|---|---|---|---|
| Claude Sonnet 5.5 | 2 | 10 | 0.20 | 2.50 (5-minute) |
| Claude Opus 5.5 | 4 | 20 | 0.20 | 5 (5-minute) |
| GPT-6.1 Sol | 2 | 10 | 0.10 | 2.50 |
| Gemini 3.8 Flash | 0.75 | 3.75 | 0.075 | - (implicit caching, minimum 4,096 tokens) |

Claude costs include a 1.35 tokenizer factor (§2.8).

Price caveats (verification, 2026-09-29):
- The Gemini 3.8 Flash prices are promotional "through December 31, 2026". From January 1, 2027 the page lists
  $1.50 input, $7.50 output and $0.15 cache, double the figures above. The price catalog must carry dated tiers.
- Opus 5.5's cache read ($0.20) is 0.05x its input price. Sonnet 5.5 uses the standard 0.1x.
- GPT-6.1 Sol's cache read ($0.10) is 0.05x input. OpenAI states that GPT-5.6 and later have a 1,024-token
  minimum, 1.25x writes and a 30-minute TTL.

**Cache model.** Request k reads the whole prompt of request k-1 from the cache, provided that prompt meets the
provider minimum (Anthropic 512, OpenAI 1,024, Gemini 4,096 tokens). The new tail is written at the cache-write
price; Gemini has no write surcharge.

**Results** (VERIFIED, `G2/out/d_compose.txt`):

| Task | Style | Requests | Tool calls | Tool-result tokens | Image tokens | Cumulative input | Output | Sonnet 5.5 $ uncached / cached |
|---|---|---|---|---|---|---|---|---|
| 1 cluster + markers (§1) | S | 7 | 6 | 1,322 | 0 | 19,887 | 287 | 0.0576 / 0.0212 |
| | S-quiet | 7 | 6 | 1,125 | 0 | 19,167 | 299 | 0.0558 / 0.0206 |
| | C | 2 | 1 | 205 | 0 | 4,714 | 228 | 0.0158 / 0.0122 |
| 2 mixed model (§2) | S | 7 | 6 | 806 | 0 | 19,709 | 221 | 0.0562 / 0.0186 |
| | C | 2 | 1 | 252 | 0 | 4,772 | 159 | 0.0150 / 0.0114 |
| 3 three piped prompts (§3) | S | 12 | 9 | 1,468 | 1,800 | 41,650 | 380 | 0.1176 / 0.0351 |
| | C | 6 | 3 | 303 | 1,800 | 16,868 | 273 | 0.0492 / 0.0226 |
| 4 artifact (§8) | S | 4 | 3 | 641 | 1,080 | 11,938 | 411 | 0.0378 / 0.0223 |
| | C | 2 | 1 | 157 | 1,080 | 5,968 | 350 | 0.0208 / 0.0180 |
| 5 MCP plugin (§10) | S | 5 | 4 | 9,938 | 0 | 49,149 | 161 | 0.1349 / 0.0542 |
| | C | 2 | 1 | 574 | 0 | 5,334 | 277 | 0.0181 / 0.0148 |
| 6 workflow (§11) | S | 16 | 11 | 4,352 | 900 | 83,748 | 507 | 0.2330 / 0.0549 |
| | C | 9 | 4 | 696 | 0 | 24,540 | 451 | 0.0723 / 0.0233 |
| **All six** | **S** | 51 | 39 | | | 226,081 | 1,967 | 0.637 / 0.206 |
| | **C** | 23 | 11 | | | 62,196 | 1,738 | 0.191 / 0.102 |

- **Ratios, S over C:**

  | Measure | S/C |
  |---|---|
  | Requests | 2.22x |
  | Cumulative input | 3.63x (per task: 2.0x artifact to 9.2x MCP) |
  | Output | 1.13x |
  | Sonnet 5.5 cost, uncached | 3.33x |
  | Sonnet 5.5 cost, cached | 2.02x |
  | GPT-6.1 Sol cost, cached | 1.87x |
  | Gemini 3.8 Flash cost, cached | 2.15x |

- **Caching and the prefix.** Caching saves 68% of the S bill but only 46% of the C bill. In C the re-sent
  prefix is **78%** of cumulative input (48% in S), so once work is composed, the prefix is the main lever.
- **Verbosity is not the driver.** On task 1, S-quiet saves only 3.6% over S, while composition saves 76%.
  The S transcripts are conservative: Seurat's txtProgressBar output (`ScaleData` with regression,
  `NormalizeData`) went to the terminal and was not captured, and a real r tool would have returned it.
- **Task 5 (MCP).**
  - Direct MCP calls return 9,938 tokens of JSON. Calling the same tools as R functions, and reducing the
    results before printing, returns 574.
  - The prefix grows by 113 tokens for the two direct schemas, against 77 for two signature lines.
- **System 1 vs System 2** (§11's nine cluster labels):
  - A Jev choice request is about 383 input tokens: the body's o200k size times 3.16, calibrated on report
    04a's live 443-token request. Nine requests: 3,447 tokens and **$0.000145** at $0.042/MTok (output is free).
  - Emulating with System 2 through gptr costs 2,174 input tokens per decision, prefix included, or 19,566 for
    nine. On Sonnet 5.5 that is $0.0534 uncached, or $0.0141 with a warm cache.
  - That is 100-370x the Jev cost, before counting latency.

### 2.5 Polyglot helpers vs a bash tool (part e)

**Method** (`G2/e_polyglot.R`). Every command was executed in a scratch project that has a temporary git
repository. The prototype helpers:
- `sh(cmd, args)`: `processx::run`; no shell is assumed.
- `py(code, ...)`: reticulate; R objects are passed by name. It uses the system python3 and no managed
  environment.
- `sql(query, con)`: DBI; the default connection is an in-memory duckdb.
- `eng(engine, code)`: runs a knitr engine.

**Results** (VERIFIED, `G2/out/e_polyglot.txt`, o200k):

| Task | bash call | bash result | r call | r result |
|---|---|---|---|---|
| Line counts of data files | 10 | 22 | 23 | 17 |
| Shell script with arguments | 10 | 18 | 19 | 18 |
| git: last 5 commits | 11 | 51 | 22 | 51 |
| Python on an in-memory object (bash must re-read the CSV) | 60 | 8 | 42 | 13 |
| SQL on SQLite (`sqlite3` CLI vs RSQLite) | 39 | 42 | 47 | 35 |
| SQL on a CSV (duckdb) | n/a (no CLI) | - | 34 | 34 |
| knitr engine chunk (bash) | 35 | 15 | 45 | 17 |
| **Sum (runnable by both)** | **165** | **156** | **198** | **151** |

- **Fixed prefix.** A bash tool declaration costs 110 tokens (Anthropic's server-defined bash tool costs 325).
  An `<r_helpers>` section documenting all four helpers costs 105.
- **Pipeline** (git → SQL → Python → summary):

  | Approach | Round trips | Call tokens | Result tokens | What the results are |
  |---|---|---|---|---|
  | r | 1 | 117 | 34 | R objects the session keeps |
  | bash | 4 | 120 | 52 | Text; a temporary CSV was needed to pass data between languages |

  Each round trip saved also saves one re-sent prefix plus history (§2.4).
- **Correctness anecdote.** My first bash pipeline returned the second-ranked region, because of an off-by-one
  in `sort | sed -n 2p` over CSV text. I fixed it for fairness. The R version works on typed data frames.

### 2.6 Calibrated estimator (part f)

**Corpus** (`G2/f_corpus.R`, VERIFIED): 481 chunks, 730,317 characters and 320,925 o200k tokens across 12
classes, with at most 50 chunks per class and at most 4 KB per chunk. Sources:
- `print_df`, `print_tibble` and `print_misc`: 60+ `datasets` frames, plus two synthetic frames (trials, genes).
- `str`: `str()` of every object in `datasets`.
- `summary_lm`: 24 fits.
- errors: 55 real R errors and warnings in report 12's format, plus 5 real tracebacks through nested functions.
- JSON: dataset JSON and 60 GitHub MCP tool snapshots.
- CSV.
- R code: the track-01 and track-12 prototypes, 150 deparsed `stats` functions and the part-(a) apps.
- Markdown: Pi's docs.
- CJK: R's zh_CN, ja and ko message catalogues, plus CJK inside printed output.

**Characters per token (whole corpus):**

| Class | o200k | cl100k | chars/4 error | chars/2 error |
|---|---|---|---|---|
| CSV | 1.57 | 1.56 | -60.8% | -21.6% |
| CJK catalogues | 1.70 | **1.30** | -57.6% | -15.1% |
| print(data.frame) | 1.94 | 1.93 | -51.5% | -3.0% |
| str() | 1.97 | 1.96 | -50.8% | -1.5% |
| misc printed output | 1.98 | 1.98 | -50.5% | -1.1% |
| tibble print | 2.00 | 2.00 | -49.9% | +0.2% |
| summary(lm) | 2.28 | 2.26 | -42.9% | +14.1% |
| printed output with CJK | 2.42 | 2.42 | -39.4% | +21.2% |
| JSON | 2.94 | 2.94 | -26.5% | +47.0% |
| errors / warnings / tracebacks | 3.05 | 3.06 | -23.8% | +52.4% |
| R code | 3.21 | 3.22 | -19.8% | +60.5% |
| Markdown | 4.28 | 4.29 | +7.0% | +114.0% |

Per chunk, printed data frames vary widely: p10 1.40, median 1.78, p90 2.67 characters per token.
Numeric-heavy prints are denser.

**Estimator** (§3.2). `estimate_tokens(x, class)` computes:

  ASCII characters / cpt[class] + 0.848 × CJK characters + 0.35 × other non-ASCII characters

- **Fitting.** Two stages, on a random half of the chunks: first a ratio of sums per class on pure-ASCII chunks,
  then the CJK weight from the residuals.
- **Shipped constants** (characters per token):

  | prose | code | r_output | str | csv | json | error | describe |
  |---|---|---|---|---|---|---|---|
  | 4.36 | 3.24 | 2.13 | 2.01 | 1.57 | 2.90 | 2.98 | 2.39 (measured in part c) |

  - `r_output` is the conservative value for table-like prints.
  - The weight for non-CJK non-ASCII characters is floored at 0.35 tokens per character. Report 21 measured
    Cyrillic at 0.30 and German at 0.27.

**Held-out chunks** (n = 240), error against o200k (`G2/out/f_calibrate.txt`, `G2/out/f_features.txt`):

| Estimator | Median abs. error | p90 abs. error | Under by >20% | Total bias | vs cl100k: median / bias |
|---|---|---|---|---|---|
| chars/4 (Pi) | 43.2% | 62.9% | 74% | -44.0% | 44.1% / -49.5% |
| chars/2 | 27.3% | 100.1% | 17% | +12.0% | 32.4% / +0.9% |
| report 21's rule (chars/4 prose and code, chars/2 tool results, 1 per CJK character) | 19.3% | 63.4% | 18% | +5.0% | 18.1% / -5.4% |
| **G2, class known (shipped)** | **11.4%** | **32.3%** | 13% | -3.4% | 14.3% / -12.9% |
| G2, class auto-detected (82% agreement) | 13.0% | 34.6% | 15% | +1.8% | 13.1% / -8.2% |
| universal character-feature model (letters, digits, punctuation, spaces, newlines) | 11.0% | 28.7% | - | -1.7% | - |
| class-specific feature model | 6.9% | 19.5% | - | +1.4% | - |

- **Feature models.** The class-specific feature model halves the error, but its coefficients are collinear
  and partly negative, and it takes about 3.5 times as long (feature extraction 126-200 ms against 34-56 ms for
  the 0.96 MB corpus). I kept it as a documented
  candidate, not the default.
- **Speed** (timings depend on machine load). `estimate_tokens()` processes all 481 chunks (0.96 MB) in 56 ms
  (`f_calibrate.txt`) and 34 ms in the verification re-run. rtiktoken takes **0.13-0.21 s per call** in those
  two runs, even on one 4 KB chunk; about 0.3 s was seen under load. The per-call cost does not depend on text
  length. A vectorised call on 50 short strings takes as long as 50 separate calls (6.2 s against 6.3 s,
  verification), which is consistent with the encoder being rebuilt on every call.
- **Recalibration** (VERIFIED, `G2/out/f_recal.txt`). I replayed the 13 golden transcripts: 81 request deltas,
  20 of them at least 150 tokens.
  - The "provider" was simulated three ways: o200k, cl100k, and a Claude-like tokenizer (1.35 × o200k with ±8%
    noise per message).
  - Before each request, the harness predicts its input as the previous request's reported input and output
    plus m × the estimate of the new messages.
  - After the response it updates m with an EWMA on the log ratio (α = 0.5; the ratio is clamped to [0.5, 3]).
    It updates only when the new content is at least 150 estimated tokens.

  Median absolute error on the new content:

  | Estimate | Claude-like | o200k | cl100k |
  |---|---|---|---|
  | chars/4 | 62.7% | 47.9% | 47.9% |
  | Raw class estimate | 30.0% | 21.5% | 21.1% |
  | With the provider prior (1.30) | 25.7% | - | - |
  | With recalibration | **19.0%** | 15.0% | 16.1% |

  Anchored on reported usage, the error on the whole-context prediction is 0.29-0.37% (median), with a maximum
  of 14-20% caused by one 9,900-token JSON result. For chars/4 the figures are 0.70% (median) and 23.9% (max).

### 2.7 Output budgets (part g)

**Truncation** (VERIFIED, `G2/out/g_budgets.txt`, o200k):

| r result | Full | Pi tail (2,000 lines / 50 KB) | Report 12 head+tail (2,000 lines / 50,000 chars) | Token cap 8,000 | 4,000 | 2,000 |
|---|---|---|---|---|---|---|
| `print(df)` of 20,000 rows | 598,113 | **29,072** | 27,930 | 9,286 | 4,633 | 2,306 |
| `str()` of a 400-model list | 5,627 | 5,650 | 5,627 | 5,627 | 4,230 | 2,130 |
| 300 warnings + final error | 4,817 | 4,841 | 4,817 | 4,817 | 3,139 | 1,571 |
| `summary()` of 60 lm fits | 16,279 | 16,304 | 16,279 | 6,931 | 3,498 | 1,760 |

- The final error survives every rule.
- The column header of the data frame does **not** survive Pi's tail-only cut; both head+tail rules keep it.
- The token caps overshoot by up to 16% on dense numeric prints, because the `r_output` class is conservative
  on average but not on every chunk. The cap must therefore sit below any hard limit.

**Line numbers in read results** (VERIFIED):

| Content | Plain tokens | `cat -n` (6-wide + TAB) | `N\|` | btw hashline `N:hhh\|` |
|---|---|---|---|---|
| 44 R/HTML files, 3,287 lines | 57,175 | +18.7% | +11.5% | +27.1% |
| 12 Markdown files | 32,186 | +25.8% | +12.3% | +31.3% |
| CSV, 300 lines | 4,627 | +25.9% | +6.5% | +24.2% |

The R/HTML figure agrees with report 11's byte measurement: +18.6% in bytes, about +18% in tokens.

**Edit results** for the 20 revisions of §2.1:

| Result returned to the model | Median tokens | Max tokens |
|---|---|---|
| Message only (Pi) | 14 | - |
| Message + `diff -U0` | 111 | 330 |
| Message + `diff -U3` | 191 | 538 |

For comparison, the edit calls themselves have a median of 124 tokens.

**Plot image size** (the same ggplot: 5,000 points and a legend, ragg PNG):

| Size @ res | Claude 5.x (high-res tier) | Claude (standard tier) | GPT-5.x (patches × 1.2) | Gemini 2.5 (tiles) | Gemini 3 (default) |
|---|---|---|---|---|---|
| 768x512 @96 | 532 | 532 | 461 | 258 | 1,120 |
| **768x512 @120** | **532** | 532 | 461 | 258 | 1,120 |
| 1000x700 @120 | 900 | 900 | 845 | 516 | 1,120 |
| 1400x1000 @144 | 1,800 | 1,551 | 1,690 | 1,032 | 1,120 |

- **Legibility.** By inspection, 768x512 at res 120 is fully legible for the scatter plot and also for a
  12-panel `facet_wrap`. At res 120 the text is larger than at res 96.
- Tokens depend on pixels, not bytes (report 17 §2.8).
- For Gemini 3, `media_resolution` sets the cost: low 280, medium 560, high and default 1,120 (report 17 §3.3).

### 2.8 Tokenizer uncertainty for Claude and Gemini (bounds)

- **Claude, newer models** (VERIFIED, Anthropic docs). The pricing and token-counting pages (fetched 2026-09-29)
  say: "Claude 4.7 and later models ... use a newer tokenizer ... This tokenizer produces approximately 30% more
  tokens for the same text". All 5.x models use it.
- **Claude vs OpenAI** (LIKELY; one community study). A June 2026 measurement on one 94-word passage (dev.to,
  "Tokens per Word") found:

  | Tokenizer | Tokens per English word | Relative to o200k |
  |---|---|---|
  | o200k | 1.17 | 1.00x |
  | Claude Sonnet 4.6 | 1.24 | 1.06x |
  | Claude Opus 4.8 | 1.88 | 1.61x |

  Simon Willison measured a 1.46x Opus 4.7 / 4.6 ratio on a system prompt.

  **Bound used here:** one Claude 5.x token ≈ 1.3-1.6 o200k tokens for English prose. The cost figures use 1.35.
  Neither source measured Claude on code, so the bound for code is UNCERTAIN. The same study's non-English
  Latin-script rows run higher on Opus 4.8: German 2.04x o200k (324 vs 159) and Spanish 1.79x.
- **Gemini** (UNCERTAIN). I found no public statement. The free `countTokens` endpoint is the calibration source.
- **Ratios are robust, absolutes are not.** cl100k and o200k agree within 0-4% on every non-CJK class here
  (§2.6), and the Shiny/HTML and S/C ratios compare like content. Absolute budgets do depend on the tokenizer,
  which is why gptr anchors on provider usage and recalibrates (§4.3).
- **Provider count endpoints need a key**, and are therefore used only in live mode:
  - Anthropic `POST /v1/messages/count_tokens`: free, rate-limited, returns an estimate (VERIFIED).
  - OpenAI `POST /v1/responses/input_tokens` (endpoint VERIFIED in OpenAI's token-counting guide). The guide
    does not say whether calls are free, so that is UNCERTAIN.
  - Gemini `models/{model}:countTokens` (endpoint VERIFIED). Its tokens guide states no price, so "free" is
    UNCERTAIN.

### 2.9 CLI plan routes (reports 07 and 08; not re-measured)

- **Claude Code.** These flags reduce its own prompt from about 18.4K tokens (default tools and prompt) to
  12-27 tokens (07 §1 item 15 and §3.13, VERIFIED there):
  `--tools "" --strict-mcp-config --setting-sources "" --disable-slash-commands --system-prompt-file`
- **Codex.** A trivial `exec` turn consumed 38,544 input tokens (30,208 cached), and an app-server turn 19,324
  (08 §1 item 6).

For token-efficient plan use, gptr should use the isolated Claude route. Codex belongs as a delegate for large
tasks, not as the model behind gptr's loop.

## 3. Exact specifications

### 3.1 Content classes and shipped constants

| Class | Producer tags it when | cpt (characters per o200k token) |
|---|---|---|
| `prose` | user text, assistant text, Markdown files, skill bodies | 4.36 |
| `code` | tool-call arguments with code, `.R/.py/.js/.html` files, signature catalogs | 3.24 |
| `r_output` | printed output events of the r evaluator (values, `print`, `cat`) | 2.13 |
| `str` | output of `str()` / `glimpse()` | 2.01 |
| `csv` | `.csv/.tsv` files and CSV text | 1.57 |
| `json` | JSON tool results (MCP, artifact), `.json` files, tool declarations | 2.90 |
| `error` | error/warning/traceback events | 2.98 |
| `describe` | `gptr_describe()` and workspace-summary output | 2.39 |

Additional weights (tokens per character): CJK (Han, Hiragana, Katakana, Hangul) 0.848; other non-ASCII 0.35.

Provider family priors for the multiplier `m`:

| Provider family | Prior m | Status |
|---|---|---|
| OpenAI (o200k) | 1.00 | |
| Anthropic, Claude 4.7 and later | 1.35 | ≈ 1.06 × 1.30 |
| Anthropic, up to 4.6 | 1.06 | |
| Gemini | 1.10 | UNCERTAIN |
| OpenAI-compatible, unknown | 1.10 | |
| Jev | 1.00 | its usage is exact and cheap; the prior only guards budgets |

Images: Claude `ceil(w/28) * ceil(h/28)`, capped at 1,568 (standard) or 4,784 (high-res tier). GPT-5.x
`ceil(w/32) * ceil(h/32) * 1.2`. Gemini 2.5: 258 per 768-pixel tile. Gemini 3: `media_resolution` (report 17 §3.3).

The OpenAI patch formula (VERIFIED, OpenAI images-vision guide, 2026-09-29) has these limits:
- It applies to gpt-5.2 and later and to gpt-6-astra. gpt-5-nano uses a 1.5x multiplier.
- gpt-5 and gpt-5.1 use tile pricing instead: 70 base tokens plus 140 per 512-pixel tile.
- At `detail = "high"`, images are shrunk to at most 2,500 patches.

GPT-6.1 Sol has no row in the multiplier table (UNCERTAIN; assume 1.2). The Gemini 3 `media_resolution`
figures (VERIFIED) are: low 280, medium 560, high 1,120, and 1,120 when unspecified.

### 3.2 `gptr_tokens()`: estimator reference implementation (prototype `G2/f_estimator.R`, run in §5)

```r
.gptr_cpt = c(prose = 4.36, code = 3.24, r_output = 2.13, str = 2.01, csv = 1.57, json = 2.90,
              error = 2.98, describe = 2.39)
.cjk_rx = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]"
gptr_tokens = function(x, class = "auto", m = 1) {
  x = enc2utf8(as.character(x))
  if (identical(class, "auto")) class = vapply(x, .detect_class, "", USE.NAMES = FALSE)
  class = rep_len(class, length(x))
  n = nchar(x, "chars")
  ascii = nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), "chars")
  non = n - ascii
  cjk = if (any(non > 0)) n - nchar(gsub(.cjk_rx, "", x, perl = TRUE), "chars") else numeric(length(x))
  ceiling(m * (ascii / .gptr_cpt[class] + cjk * 0.848 + (non - cjk) * 0.35))
}
```

`.detect_class()` is the fallback rule set in `G2/f_estimator.R`: a JSON sniff, an Error/Traceback prefix, the
constant-comma CSV test, `str()` line prefixes, code tokens, and letter share. It agrees with the true class
82% of the time.

### 3.3 Session recalibration rule (prototype `G2/f_recal.R`)

For request k, with provider usage `u_{k-1}` from the previous response:

- `ctx_k = u_{k-1}$input_total + u_{k-1}$output + m * sum(gptr_tokens(new_parts, class))`, where
  `input_total = input + cache_read + cache_write`.
- `obs = u_k$input_total - u_{k-1}$input_total`, and
  `est = gptr_tokens(previous assistant visible content) + gptr_tokens(new_parts)`.
- If `est >= 150`, the tool list, system prompt and model are unchanged, and no compaction happened in between:
  `m = exp(0.5 * log(m) + 0.5 * log(min(max(obs / est, 0.5), 3)))`.
- m is kept per (session, provider, model) and seeded from the §3.1 prior. It is not persisted across
  sessions unless `gptr.calibration_cache = TRUE`, which would write to `tools::R_user_dir("gptr", "cache")`.

### 3.4 Output budget defaults (all in estimated tokens, configurable by option)

| Budget | Default | Token cost it controls | Evidence |
|---|---|---|---|
| r result (`gptr.r_max_tokens`) | 4,000, head 40% / tail 60% by lines, spill file | ≤ ~4.6k per call instead of ≤ 29k | §2.7 |
| read result | 2,000 lines or 50 KB (Pi) **and** 12,000 est. tokens | 50 KB of CSV is ~32k tokens | §2.6 cpt 1.57 |
| grep/find/ls | Pi's limits (100 / 1000 / 500) + 4,000 est. tokens | | 01 §3.1 |
| MCP result called directly | 4,000; inside r: the r cap | | §2.4 task 5 |
| edit result | message + `-U0` diff, capped at 400 | 111 median | §2.7 |
| read line numbers | off; option `gptr.read_line_numbers = "bar"` gives `N\|` | +6.5-12% vs +19-26% | §2.7 |
| plot image | 768 x 512 px, res 120, PNG | 532 Claude / 461 GPT-5.x | §2.7 |
| artifact screenshot | 960 x 640 (805 Claude tokens) instead of 1100 x 750 (1,080) | -25% | 17 §3.3 formula; legibility UNCERTAIN |
| describe (attached object) | 150 per object, 300 maximum | 90.8% / 99% of facts | §2.3 |
| workspace summary | 600 (one line per object) | 336 for 21 objects | §2.3 |
| MCP signature catalog | 1,500 total, per-server share, "N more: mcp_search()" | ≈1,150 real tokens, ~22 GitHub tools | §2.2 |
| skills catalog | 1,500; compact lines, descriptions ≤ 160 chars | ~55 skills | §2.2 |
| system-prompt sections | each registered section declares a token budget; the sum is gated in the bench | | §4.6 |

### 3.5 Usage record (one row per provider request; extends INFRA-20)

`time, session, agent, parent_agent, provider, model, route` (`api`, `plan-cli`, `system-one`, `emulated`),
followed by:
- **provider usage:** `input, output, cache_read, cache_write_5m, cache_write_1h, reasoning, images`;
- **cost:** `price_tier, cost`;
- **harness estimates before sending:** `est_system, est_tools, est_workspace, est_history, est_new, est_images`,
  and `est_input` (their sum);
- **request facts:** `m` (the multiplier used), `n_tool_calls, stop_reason, budget_state`.

The rows are stored append-only in the session and as `usage` entries in the session JSONL.

### 3.6 Budget conditions

Each condition is signalled by `gptr_abort(message, class = c("budget_<kind>", "budget"), ...)`. Per the
conventions §5 scheme this yields the class
`c("gptr_error_budget_<kind>", "gptr_error_budget", "gptr_error", "error", "condition")`.

| Kind | Checked | Fields |
|---|---|---|
| `tokens` | before each request: used + projected input > `max_tokens` | `used, next_request, limit` |
| `turns` | before each request: requests ≥ `max_turns` | `used, limit` |
| `cost` | before each request: cost ≥ `max_cost` | `used, limit` |
| `context` | projected input > `max_context`, and compaction is disabled or could not reduce enough | `next_request, limit` |
| `output` | a single response hit `max_output` (provider stop reason `max_tokens`) | `used, limit` |

A warning `gptr_warning_budget_near` fires once at `warn_at` (default 0.8).

### 3.7 Golden transcript fixture format (`tests/testthat/fixtures/bench/<case>.json`)

```json
{"id": "ns01-cluster-markers-C", "north_star": 1, "style": "C", "preset": "default",
 "workspace": "pbmc <Seurat> 230 features x 80 cells, ...",
 "messages": [
  {"role": "user", "content": [{"type": "text", "class": "prose", "text": "cluster the cells ..."}]},
  {"role": "assistant", "content": [{"type": "text", "text": "..."},
     {"type": "tool_use", "id": "toolu_01", "name": "r", "input": {"code": "..."}}]},
  {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_01", "class": "r_output",
     "content": "...", "images": [[768, 512]]}]}],
 "recorded_usage": null}
```

`recorded_usage` is filled only by live mode (a list of provider usage objects), which lets CI compare the
estimator with real counts offline.

### 3.8 Benchmark metrics and thresholds

| Metric (per case) | Tolerance vs baseline | Absolute gate |
|---|---|---|
| `prefix` (est. tokens of system + tools for the preset) | +2% | default preset ≤ 1,600 est. (≈ 1,250 o200k) |
| `requests` | 0 | - |
| `input_total` (cumulative, fake-provider usage) | +5% | - |
| `output_total` | +5% | - |
| `image_tokens` | 0 | - |
| `tool_result_max` | +5% | ≤ r cap + 15% |
| `cost_cached` (snapshot prices) | +5% | - |
| describer facts (fixture objects) | no loss | - |
| catalog tokens (MCP fixture of 50 tools, skills fixture of 40) | +5% | ≤ 1,500 each |

Improvements of more than 5% emit a note asking to refresh the baseline (a ratchet). Any regression raises
`gptr_error_token_regression`, whose `details` field lists every failing metric.

## 4. Recommended design for gptr

### 4.1 Where it lives

A new area prefix, `usage`, is proposed as an amendment to conventions §3 [design]. Files and their contents:

| File | Contents |
|---|---|
| `R/usage-estimate.R` | `gptr_tokens()`, `.detect_class()`, the constant table, image token formulas |
| `R/usage-record.R` | usage records, cost from the catalog snapshot, `gptr_usage()` with `print`/`summary`/`format` methods |
| `R/usage-budget.R` | `gptr_budget()`, `.budget_check()`, the conditions |
| `R/usage-calibrate.R` | per-session multiplier, context projection |
| `R/usage-bench.R` | `gptr_bench_tokens()`, `gptr_bench_compare()` (exported so that plugin packages can gate their own prompts, tools and describers) |
| `tests/testthat/test-usage-*.R` | unit tests, plus the offline benchmark with fixtures in `tests/testthat/fixtures/bench/` |
| `dev/bench/` (in `.Rbuildignore`) | the G2 corpus builders, `calibrate.R` (re-fits constants with rtiktoken from a private library), `apps/` (the 20 part-(a) apps and their checker) |

Dependencies: no new Imports. The estimator is base R. rtiktoken is **not** in Suggests, because it is only
used in `dev/bench`.

### 4.2 Public API (signatures)

```r
gptr_tokens(x, class = "auto", model = NULL)            # estimate; model applies the session/provider multiplier
gptr_usage(s, by = c("request", "turn", "agent", "model", "section"))   # data.frame; s is a gptr session
gptr_budget(max_tokens = Inf, max_turns = Inf, max_cost = Inf, max_context = Inf,
            max_output = NULL, warn_at = 0.8)
gptr_describe(x, budget = 150L, ...)                    # S3 generic (report 12), level-based, budget in est. tokens
gptr_bench_tokens(cases, preset = "default", tools = NULL, system = NULL)  # cases: fixture paths or lists
gptr_bench_compare(result, baseline, tol = gptr_bench_tolerance())
```

**Integration with the gateway** (S-1, S-8):
- `gptr("prompt", budget = gptr_budget(max_cost = 0.50))` attaches the budget to the session.
- `s |> gptr("steer", budget = ...)` replaces it for later turns.
- `s$usage` returns `gptr_usage(s)`.
- `print(s)` ends with a one-line footer: `<turn 3: 4,210 in (3,100 cached) / 380 out, $0.004; session $0.019>`.

**When a budget stops a run:**
- The loop records `stop_reason = "budget"`, keeps the partial transcript, and re-signals the condition. Scripts
  can therefore write `tryCatch(gptr(...), gptr_error_budget = function(e) ...)`.
- The interactive console prints the message and returns to the prompt with the session intact.

**Sub-agent budgets are hierarchical.** A child's budget is `min(child, parent remaining)`, and child usage is
charged to the parent's tally.

### 4.3 Context management (D-19)

The context size before each request is
`ctx = last reported input_total + last output + m * gptr_tokens(new parts)`.
This is Pi's usage-anchored method (02 §2.10) with a calibrated estimator in place of chars/4 and a multiplier.
Before the first response in a session, the prefix is estimated as well.
- **Compaction trigger:** `ctx > window - reserve`, with
  `reserve = max(16384, max_output + 2 * gptr.r_max_tokens)`. Pi uses 16,384 (02 §2.10).
- **Compaction itself** remains a plugin strategy (S-11). Each strategy receives the per-section estimates.

### 4.4 Tool-result handling

- **Producers tag content.** Each tool result part carries a content `class`, so estimates use the right cpt.
- **The r evaluator** (report 12) tags each event:
  - `output` events: `r_output`, or `str` when the expression was a `str()` call;
  - `error` and `warning` events: `error`.
- **The read tool** tags content by file extension.
- **Truncation** applies at the source, in estimated tokens, before the result enters the transcript. Head 40%
  and tail 60% are chosen by lines. The full text is written to a spill file under the session directory.
  - The marker line states the omitted lines and tokens, the file path, and an R accessor,
    `gptr_spill(n, lines = )`.
  - The model can page through a spill file with read's offset/limit, or reduce it in R.
- **Images** are rendered at 768x512, res 120. The model may request more resolution inside r with
  `gptr_plot(p, width = 1000, height = 700)`, at 900 tokens.
- **Line numbers** in read are off by default (Pi parity; saves 19-26%). A per-model-family option enables the
  compact `N|` form, for families shown to edit better with numbers (UNCERTAIN; needs live evals).
- **edit** returns the message plus a `-U0` diff capped at 400 tokens (median 111). This satisfies REQ-06
  ("with diff output"), and it usually saves a re-read of the file, which costs 160-1,400 tokens for the
  part-(a) files.

### 4.5 Workspace and object descriptions

- **Adopt report 12's leaf discipline** with level-based methods, as in `describe2()`. A method returns
  `levels` (a list of character vectors, from least to most detailed). The harness then picks the richest level
  that fits `budget` according to `gptr_tokens(..., "describe")`, so each plugin method does not have to
  enforce budgets itself.
- **Fix the report-12 gaps (§2.3):**
  - Dates: re-attach the class before formatting.
  - Matrices: add `dgCMatrix`/`Matrix` methods (dims and nnz via `attr()`).
  - Formulas: add a `formula` method.
  - Nested lists: walk names 3 levels deep.
  - Seurat-like S4: put dims in the S4 header, taken from the slots' own dims.
  - ALTREP: an `object.size()` caveat. Use `lobstr::obj_size()` when it is installed (Suggests); otherwise mark
    the size of a compact-looking integer sequence as "≤" (UNCERTAIN heuristic).
- **Describers are a plugin type** (S-11): `gptr_describe.<class>` methods registered by packages. The bench
  includes a fixture that checks every registered method against its budget.

### 4.6 The request prefix

**Stable and append-only.**
- Tools are sorted deterministically.
- The system prompt contains no per-turn text: the workspace summary, cwd and date go in the first user message
  (20 §4.2 item 8).
- Deferred tools are added only by appending.
- Result: the Anthropic, OpenAI and Gemini caches stay warm. Cache hits cost 0.025-0.1x of input: 0.1x on most
  models, 0.05x on Opus 5.5 and GPT-6.1 Sol, and 0.025x on Fable/Mythos 5.1.

**Default preset.** Keep the 7 tools, but ship the **lean** texts (1,153 tokens against 2,096).
- The `<r_performance>` detail moves into a built-in skill (19 §3.1 already points to one). The prompt keeps
  about 70 tokens, including the composition rule: "compose several steps in one r call and print only what
  you need".
- Tools beyond the first seven are added only when they are useful:

  | Tool | Tokens | Added when |
  |---|---|---|
  | `ask` | 335 | the session is interactive |
  | `agent` | 199 | agents are defined or `agents =` is used |
  | `artifact` | 350, plus a 360-token section | first requested, via a deferred tool |
  | `r_inspect` | 143 | in `manual` and `plan` modes, where `r` needs approval |

**Section budgets.** Each system-prompt section is registered through the extension API with a declared
token budget, and the benchmark gates the total. `gptr_prompt_report(s)` prints each section's estimated
tokens, answering "where do my prefix tokens go".

**OpenAI.** Keep strict mode off unless the model needs it (+3-8%; +136 tokens for gptr-7). Wrap tools in a namespace only on the
ChatGPT plan route (+1%, 08).

### 4.7 MCP tools and skills

- **MCP.** Default exposure is `"r"`: R functions plus a signature catalog (16 §4.7).
  - The catalog budget is 1,500 estimated tokens in total. Report 16 used 3,000. Signature lines run at about
    4.1 characters per token, against 3.24 for the `code` class, so 1,500 estimated tokens are about 1,150 real
    tokens, or roughly 22 GitHub tools at 51 tokens per line (§2.2).
  - Each server gets an equal share; overflow lines become `N more: mcp_search("...")`.
  - `"direct"` exposure is kept per tool (as in Pi), costing a median of 169 tokens per GitHub tool.
  - `"deferred"` uses provider tool search: 67 tokens plus the schemas of the tools it finds.
- **Skills.** Use the compact catalog format with descriptions capped at 160 characters and a 1,500-token
  budget, plus `gptr_skills("query")` search. Pi's XML format costs 94 tokens per skill, against 33 in compact
  form with 250-character descriptions. Bodies (median 804 tokens) are read on activation.

### 4.8 Composition as the default working style

- **Tools, MCP tools and sub-agents are callable as R functions from `r`** (06 §4.5, 16 §4.7). The polyglot
  helpers live in the same dispatcher:
  - `sh`, `py`, `sql` and `engine`, exported for users as `gptr_sh()`, `gptr_py()`, `gptr_sql()`,
    `gptr_engine()`;
  - model-side names are short (the dispatcher name is decided in the tools-as-functions track).
  - Avoid a bare exported `sql()`: dbplyr exports `sql()`.
- **The system prompt states the rule once:** compose, reduce, print compactly.
- **The composition ratio is a tracked metric.** It is the model-visible tool calls per task in the golden
  transcripts, together with the S/C ratio from live evaluations when they exist.
- **System 1.** Routing and judgement calls in control flow use System 1 (REQ-20). The bench reports tokens
  per decision for Jev against System 2 emulation.

### 4.9 Extension points for token efficiency (S-11)

Registered through the one extension API:
- `estimator`: an exact tokenizer for a provider, for example a plugin that wraps a tokenizer package. It
  overrides `gptr_tokens()` for that provider's models.
- `describer`: S3 methods, level contract §4.5.
- `truncation`: per-class head/tail policy.
- `compaction`: a strategy.
- `prompt_section`: a system-prompt section, with a declared token budget.
- `catalog`: MCP and skills formatters.
- `bench_case`: golden transcripts that a plugin ships, so its prompts and tools are gated by the same benchmark.

Events carry usage and estimates. `before_request` receives the per-section estimates and may trim deferred
tools. `usage` fires after each response, and `budget_near` and `budget_exceeded` fire from the budget checks.
Provider plugins declare `tokenizer_factor` and cache capabilities in the catalog entry: minimum prefix, read
and write multipliers, and TTLs.

### 4.10 Benchmark suite

**Offline (CI, every commit)** — `tests/testthat/test-usage-bench.R`:
- **Input:** the 13 golden transcripts of §2.4, as JSON fixtures.
- **Replay:** the fake provider replays them. Fake usage is `gptr_tokens()`, which is deterministic and needs
  no tokenizer, and the prefix is assembled from the *current* registry and prompt.
- **Other checks:** a 50-tool MCP fixture, a 40-skill fixture, and the 20 describer fixture objects (§2.3).
- **Gate:** results are compared with `fixtures/bench/baseline.json` using the §3.8 thresholds.
- **Cost:** the prototype runs in 0.13-0.24 s. A regression raises `gptr_error_token_regression`; verified by
  lengthening the `r` description by 12 sentences (+9.3% prefix, §5).
- **Refresh:** `dev/bench/update-baseline.R` rewrites the baseline after a deliberate change, with the reason
  recorded in NEWS.
- **CRAN:** `skip_on_cran()`, because it is a maintenance gate, not a correctness test.

**Development** — `dev/bench/`:
- `calibrate.R` re-fits the constants on the G2 corpora with rtiktoken from a private library and prints the
  held-out error table.
- `apps/check.R` re-runs the Shiny/HTML ladder, with chromote.
- `transcripts.R` regenerates the golden transcripts from real code (Seurat, nlme), so that outputs stay current.

**Live** (`GPTR_LIVE_TESTS=true`, keys required, never on CRAN):
- **Prefix checks** (free on Anthropic; OpenAI and Gemini pricing of count calls UNCERTAIN): for each
  configured provider, count the default prefix and one mid-size transcript
  with the count endpoints (Anthropic `count_tokens`, OpenAI `responses/input_tokens`, Gemini
  `countTokens`). Store them as `recorded_usage` in the fixtures.
- **Paid checks:** run two tiny paid requests to verify usage parsing and cache accounting. Examples: task 2 C
  with `max_output` of 64, a repeated request to observe `cache_read`, and a Jev decision.
- **Failure conditions:** the test fails if estimator bias exceeds ±30% on the prefix or ±40% on tool results
  for any provider, or if cached reads are not observed on the second request.

### 4.11 Design choice → token cost → recommendation

| Design choice | Token cost (measured) | Recommendation |
|---|---|---|
| Artifacts as Shiny vs HTML/JS | HTML/JS 2.35x (1.02-4.32x) the code tokens; +80 vs +57 per complexity level | Shiny (S-5); HTML fallback only via 17's wrapper |
| Data into artifacts: inline vs by name | about 25 tokens per row inline as row JSON, 14-15 as column JSON or CSV (5,000 rows = 127k / 72k / 77k) vs 1-25 | by name only; HTML fallback gets harness-injected data |
| Artifact revisions: rewrite vs edits | rewrite 3.9x (Shiny) / 6.1x (HTML) the edit output | edits by default |
| Default tool texts: report 01/12/19 vs lean | 2,096 vs 1,153 per request (78% of input in composed style) | lean, with a live A/B before 1.0 |
| Each optional tool | ask 335, agent 199, artifact 350 (+360), r_inspect 143, grep 233, find 178, ls 96 | conditional activation (§4.6) |
| `<r_performance>` section | 406 | about 70 in the prompt; the rest in a skill |
| apply_patch for GPT-5.x on Responses | 252 vs edit+write 324 | use it on Responses (20) |
| OpenAI strict mode / namespace | +48-274 (+136 for gptr-7) / +24 | off / plan route only |
| MCP: direct vs R catalog | 50 tools: 11,361 vs 2,285; 125: 28,534 vs 2,285; results 9,938 vs 574 | `"r"` exposure, catalog budget 1,500 |
| Skills catalog format | Pi XML 94 per skill vs compact 33-50 | compact, 1,500 budget, search beyond |
| Describer budget per object | 50: 73.5% of facts; 150: 90.8%; 300: 99% | 150 per attached object, 600 for the workspace |
| Composition vs separate tool calls | S/C: input 3.6x, cost 2.0x cached / 3.3x uncached | compose; prompt rule; tools as R functions |
| Polyglot: helpers vs bash tool | per call ≈ equal; schema 105 vs 110; pipeline 1 vs 4 round trips | helpers inside r; no bash tool (S-4) |
| System 1 vs System 2 for decisions | 383 vs 2,174 input tokens per decision; ~100x cost | Jev in control flow (REQ-20) |
| Tool-result cap | Pi limits admit 29k; 4,000 est. cap gives ≤ 4.6k | 4,000 est., head+tail, spill |
| Read line numbers | +19-26% (`cat -n`), +6.5-12% (`N\|`) | off; `N\|` if enabled |
| Edit result with diff | +97 median (U0) vs +177 (U3) | U0 capped at 400 |
| Plot size | 768x512: 532 / 461; 1000x700: 900 / 845 | 768x512 @120 |
| Token estimator | chars/4 -44% bias; G2 -3.4%, 11.4% median | `gptr_tokens()` + recalibration |
| Claude plan via CLI | 12-27 tokens isolated vs ~18.4K default (07) | always isolate |
| Codex as a model | 19-38K per turn (08) | delegate only |

### 4.12 Positions on the blocked decisions

- **D-03 tool set.** read, r, edit, write, grep, find and ls with lean texts is 1,153 tokens on the Anthropic
  wire (Pi's 4-tool default is 919). Tools beyond these are conditional (§4.6). The apply_patch variant is used
  on Responses for GPT-5.x.
- **MCP exposure.** `"r"` by default, with a 1,500-token catalog; `"direct"` and `"deferred"` per tool.
- **read line numbers.** Off.
- **edit diff.** Yes, `-U0`, capped at 400.
- **Plot size.** 768x512 at res 120. This supersedes both report 12's 768x512 at res 96 and report 17's
  1000x700 default. Report 17's size stays an option.
- **D-19.** Usage-anchored projection, the calibrated estimator, a per-session multiplier, reserve
  `max(16384, max_output + 2 * r cap)`, tool results capped at the source, spill files, append-only prefix.

## 5. Verified R prototypes

**How it was run.** Every script below was run with `Rscript --vanilla` from `G2/` on R 4.4.3 (macOS arm64).
The private library was first on `.libPaths()`. Token counts are memoised in `G2/tokcache.rds`, because
rtiktoken 0.0.7 takes about 0.3-0.4 s per call.

**Order of execution** (each output file was produced by the final run):

| Part | Script(s), in order |
|---|---|
| (a) | `a_check.R` (originals, mutants, revised), `a_mutants.R`, `a_revisions.R`, `a_tokens.R` |
| (b) | `b_presets.R`, `b_catalogs.R`, `b_skills.R`, `b_lean.R` |
| (c) | `c2_describe.R` (it sources `c_describe.R`) |
| (f) | `f_corpus.R`, `f_count.R`, `f_calibrate.R`, `f_features.R` |
| (d) | `d_tasks.R`, `d_compose.R` |
| (f), again | `f_recal.R` |
| (e) | `e_polyglot.R` |
| (g) | `g_budgets.R` |
| design | `h_bench.R` |

**Scope notes.**
- Two scripts source code from other tracks unchanged: report 12's `gptr_introspect.R` and the track-01 tool
  prototype. Those files keep their original `<-` style. Everything written here uses `=` and `|>`.
- `d_tasks.txt` is shown without Seurat's terminal progress bars, which were not part of any tool result.

### 5.1 Part (a): functional spec, data, the 20 apps

**`G2/a_apps/SPEC.md`**

````text
# G2 part (a): one functional spec per complexity level

Data (identical for both sides): `sales` (5000 rows: region, month [Jan..Dec], units, price, revenue),
`cars_df` (mtcars + column `name`), `inv_a`, `inv_b` (8 rows each: product, price, stock).
Shiny apps reference the objects by name (they exist in the app's environment, as in the report-17
artifact design). HTML apps load `data/<name>.json` (row-wise JSON exported by the harness) and use
CDN URLs for libraries (localised to package-shipped copies for the offline test).
Money = comma thousands, 2 decimals (12,345.67). Element ids are fixed so one checker tests all apps.

L1 static table: title "Sales by region"; table with columns Region, Orders, Units, Revenue, one
row per region, sorted by revenue descending (Units comma-formatted, Revenue money).

L2 filter + plot: title "Revenue by month"; select #region (All, East, North, South, West; default
All); text #n = "<count> orders"; bar chart #chart of total revenue per month (Jan..Dec) for the
selection.

L3 dashboard: title "Sales dashboard"; sidebar select #region (All + 4 regions); value boxes
"Total revenue" #vb_revenue (money), "Total units" #vb_units (comma int), "Average price" #vb_price
(mean price, 2 decimals); tabs "Trend" (#trend line chart of revenue by month of the selection),
"Regions" (#regions bar chart of revenue by region, all data), "Data" (#data table: first 10 rows
of the selection).

L4 linked brushing + download: title "Car explorer"; scatter #plot of wt (x) vs mpg (y); a
rectangular brush/box-select selects cars; #n = "<k> selected"; table #selected with columns
name, wt, mpg, hp listing all selected cars; button/link #download saves the selected rows as CSV
"selected.csv" (header name,wt,mpg,hp).

L5 editable table with modules: title "Inventory"; the same module/component instantiated twice
(ids a, b; titles "Warehouse A", "Warehouse B"); each shows an editable table #<id>-table
(product, price, stock; price and stock editable) and text #<id>-value = "Stock value: <money>"
(sum of price * stock); global text #total = "Total stock value: <money>" updates on every edit.
````

**`G2/a_apps/data.R`**

````r
set.seed(1)
sales = data.frame(region = sample(c("North", "South", "East", "West"), 5000, TRUE),
                   month = factor(sample(month.abb, 5000, TRUE), levels = month.abb),
                   units = rpois(5000, 40), price = round(runif(5000, 5, 50), 2))
sales$revenue = sales$units * sales$price
cars_df = cbind(name = rownames(mtcars), mtcars)
rownames(cars_df) = NULL
inv_a = data.frame(product = c("apple", "banana", "cherry", "date", "elderberry", "fig", "grape", "honeydew"),
                   price = c(1.2, 0.5, 3.75, 2.4, 5.1, 2.25, 1.8, 3.3),
                   stock = c(120, 300, 45, 80, 20, 60, 150, 35))
inv_b = data.frame(product = c("kiwi", "lemon", "mango", "nectarine", "orange", "papaya", "quince", "raspberry"),
                   price = c(0.9, 0.6, 1.95, 1.4, 0.75, 2.8, 2.1, 4.5),
                   stock = c(200, 250, 90, 110, 400, 30, 25, 70))
````

**`G2/a_apps/L1/shiny_a.R`**

````r
library(shiny)
library(bslib)

ui = page_fixed(
  h2("Sales by region"),
  tableOutput("tbl")
)

server = function(input, output) {
  output$tbl = renderTable({
    agg = aggregate(cbind(units, revenue) ~ region, sales, sum)
    agg$orders = as.vector(table(sales$region)[agg$region])
    agg = agg[order(-agg$revenue), ]
    data.frame(Region = agg$region, Orders = agg$orders,
               Units = format(agg$units, big.mark = ","),
               Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","))
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L1/shiny_b.R`**

````r
library(shiny)
library(DT)

region_summary = function(df) {
  out = do.call(rbind, lapply(split(df, df$region), function(d) {
    data.frame(Region = d$region[1], Orders = nrow(d), Units = sum(d$units), Revenue = sum(d$revenue))
  }))
  out[order(out$Revenue, decreasing = TRUE), ]
}

ui = fluidPage(
  titlePanel("Sales by region"),
  DTOutput("summary_table")
)

server = function(input, output, session) {
  output$summary_table = renderDT({
    datatable(region_summary(sales), rownames = FALSE,
              options = list(dom = "t", paging = FALSE, ordering = FALSE)) |>
      formatCurrency("Revenue", currency = "", digits = 2) |>
      formatCurrency("Units", currency = "", digits = 0)
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L1/html_a.html`**

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Sales by region</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
</head>
<body class="container py-4">
<h2>Sales by region</h2>
<table class="table table-striped" id="tbl">
  <thead><tr><th>Region</th><th>Orders</th><th>Units</th><th>Revenue</th></tr></thead>
  <tbody></tbody>
</table>
<script>
const fmt2 = x => x.toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2});
fetch("data/sales.json").then(r => r.json()).then(rows => {
  const agg = {};
  for (const r of rows) {
    const a = agg[r.region] ??= {orders: 0, units: 0, revenue: 0};
    a.orders += 1; a.units += r.units; a.revenue += r.revenue;
  }
  const tbody = document.querySelector("#tbl tbody");
  Object.entries(agg).sort((a, b) => b[1].revenue - a[1].revenue).forEach(([region, a]) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${region}</td><td>${a.orders}</td><td>${a.units.toLocaleString("en-US")}</td><td>${fmt2(a.revenue)}</td>`;
    tbody.appendChild(tr);
  });
});
</script>
</body>
</html>
````

**`G2/a_apps/L1/html_b.html`**

````html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Sales by region</title>
  <link rel="stylesheet" href="https://cdn.datatables.net/2.1.8/css/dataTables.dataTables.min.css">
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/2.1.8/js/dataTables.min.js"></script>
  <style>
    body { font-family: sans-serif; margin: 2em; }
  </style>
</head>
<body>
  <h1>Sales by region</h1>
  <table id="summary" class="display" style="width:100%">
    <thead>
      <tr><th>Region</th><th>Orders</th><th>Units</th><th>Revenue</th></tr>
    </thead>
  </table>
  <script>
    function summarise(rows) {
      var groups = {};
      rows.forEach(function (row) {
        if (!groups[row.region]) {
          groups[row.region] = { region: row.region, orders: 0, units: 0, revenue: 0 };
        }
        groups[row.region].orders += 1;
        groups[row.region].units += row.units;
        groups[row.region].revenue += row.revenue;
      });
      return Object.values(groups).sort(function (a, b) { return b.revenue - a.revenue; });
    }

    $(function () {
      $.getJSON("data/sales.json", function (rows) {
        var data = summarise(rows).map(function (g) {
          return [g.region, g.orders, g.units.toLocaleString("en-US"),
                  g.revenue.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })];
        });
        $("#summary").DataTable({ data: data, paging: false, searching: false, info: false, ordering: false });
      });
    });
  </script>
</body>
</html>
````

**`G2/a_apps/L2/shiny_a.R`**

````r
library(shiny)
library(bslib)

ui = page_sidebar(
  title = "Revenue by month",
  sidebar = sidebar(selectInput("region", "Region", c("All", sort(unique(sales$region))))),
  textOutput("n"),
  plotOutput("chart")
)

server = function(input, output) {
  sel = reactive(if (input$region == "All") sales else sales[sales$region == input$region, ])
  output$n = renderText(paste(nrow(sel()), "orders"))
  output$chart = renderPlot({
    rev = tapply(sel()$revenue, sel()$month, sum)
    barplot(rev, col = "steelblue", ylab = "Revenue")
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L2/shiny_b.R`**

````r
library(shiny)
library(plotly)

ui = fluidPage(
  titlePanel("Revenue by month"),
  sidebarLayout(
    sidebarPanel(
      selectInput("region", "Region",
                  choices = c("All", "East", "North", "South", "West"), selected = "All")
    ),
    mainPanel(
      textOutput("n"),
      plotlyOutput("chart")
    )
  )
)

server = function(input, output, session) {
  filtered = reactive({
    if (input$region == "All") {
      sales
    } else {
      subset(sales, region == input$region)
    }
  })

  output$n = renderText({
    paste(nrow(filtered()), "orders")
  })

  output$chart = renderPlotly({
    monthly = aggregate(revenue ~ month, data = filtered(), FUN = sum)
    plot_ly(monthly, x = ~month, y = ~revenue, type = "bar") |>
      layout(xaxis = list(title = "Month"), yaxis = list(title = "Revenue"))
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L2/html_a.html`**

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Revenue by month</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
</head>
<body class="container py-4">
<h2>Revenue by month</h2>
<label for="region" class="form-label">Region</label>
<select id="region" class="form-select w-auto mb-2"><option>All</option></select>
<p id="n"></p>
<div id="chart" style="height:400px"></div>
<script>
const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
let sales = [];
function draw() {
  const r = document.getElementById("region").value;
  const rows = r === "All" ? sales : sales.filter(d => d.region === r);
  document.getElementById("n").textContent = `${rows.length} orders`;
  const rev = Object.fromEntries(MONTHS.map(m => [m, 0]));
  rows.forEach(d => rev[d.month] += d.revenue);
  Plotly.react("chart", [{type: "bar", x: MONTHS, y: MONTHS.map(m => rev[m])}],
               {yaxis: {title: "Revenue"}, margin: {t: 20}});
}
fetch("data/sales.json").then(r => r.json()).then(d => {
  sales = d;
  const sel = document.getElementById("region");
  [...new Set(d.map(x => x.region))].sort().forEach(r => sel.add(new Option(r)));
  sel.addEventListener("change", draw);
  draw();
});
</script>
</body>
</html>
````

**`G2/a_apps/L2/html_b.html`**

````html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Revenue by month</title>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .controls { margin-bottom: 10px; }
    #chart { width: 100%; height: 450px; }
  </style>
</head>
<body>
  <h1>Revenue by month</h1>
  <div class="controls">
    <label for="region">Region</label>
    <select id="region">
      <option value="All">All</option>
      <option value="East">East</option>
      <option value="North">North</option>
      <option value="South">South</option>
      <option value="West">West</option>
    </select>
  </div>
  <p id="n"></p>
  <div id="chart"></div>
  <script>
    var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var allRows = [];

    function monthlyRevenue(rows) {
      var totals = {};
      MONTHS.forEach(function (m) { totals[m] = 0; });
      rows.forEach(function (row) { totals[row.month] += row.revenue; });
      return MONTHS.map(function (m) { return totals[m]; });
    }

    function update() {
      var region = $("#region").val();
      var rows = region === "All" ? allRows : allRows.filter(function (row) { return row.region === region; });
      $("#n").text(rows.length + " orders");
      var trace = { x: MONTHS, y: monthlyRevenue(rows), type: "bar", marker: { color: "#4682b4" } };
      var layout = { xaxis: { title: "Month" }, yaxis: { title: "Revenue" }, margin: { t: 30 } };
      Plotly.newPlot("chart", [trace], layout, { responsive: true });
    }

    $(document).ready(function () {
      $.getJSON("data/sales.json", function (rows) {
        allRows = rows;
        $("#region").on("change", update);
        update();
      });
    });
  </script>
</body>
</html>
````

**`G2/a_apps/L3/shiny_a.R`**

````r
library(shiny)
library(bslib)
library(ggplot2)

ui = page_sidebar(
  title = "Sales dashboard",
  sidebar = sidebar(selectInput("region", "Region", c("All", sort(unique(sales$region))))),
  layout_columns(
    value_box("Total revenue", textOutput("vb_revenue")),
    value_box("Total units", textOutput("vb_units")),
    value_box("Average price", textOutput("vb_price"))
  ),
  navset_card_tab(
    nav_panel("Trend", plotOutput("trend")),
    nav_panel("Regions", plotOutput("regions")),
    nav_panel("Data", tableOutput("data"))
  )
)

server = function(input, output) {
  sel = reactive(if (input$region == "All") sales else sales[sales$region == input$region, ])
  money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")
  output$vb_revenue = renderText(money(sum(sel()$revenue)))
  output$vb_units = renderText(format(sum(sel()$units), big.mark = ","))
  output$vb_price = renderText(sprintf("%.2f", mean(sel()$price)))
  output$trend = renderPlot({
    m = aggregate(revenue ~ month, sel(), sum)
    ggplot(m, aes(month, revenue, group = 1)) + geom_line() + geom_point()
  })
  output$regions = renderPlot(ggplot(sales, aes(region, revenue)) + geom_col(fill = "steelblue"))
  output$data = renderTable(head(sel(), 10))
}

shinyApp(ui, server)
````

**`G2/a_apps/L3/shiny_b.R`**

````r
library(shiny)
library(plotly)
library(DT)

value_card = function(title, output_id) {
  div(class = "col-sm-4",
      wellPanel(
        h5(title),
        h3(textOutput(output_id))
      ))
}

ui = fluidPage(
  titlePanel("Sales dashboard"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("region", "Region", choices = c("All", "East", "North", "South", "West"))
    ),
    mainPanel(
      width = 9,
      fluidRow(
        value_card("Total revenue", "vb_revenue"),
        value_card("Total units", "vb_units"),
        value_card("Average price", "vb_price")
      ),
      tabsetPanel(
        id = "tabs",
        tabPanel("Trend", plotlyOutput("trend")),
        tabPanel("Regions", plotlyOutput("regions")),
        tabPanel("Data", DTOutput("data"))
      )
    )
  )
)

server = function(input, output, session) {
  filtered = reactive({
    if (input$region == "All") sales else subset(sales, region == input$region)
  })

  output$vb_revenue = renderText({
    formatC(sum(filtered()$revenue), format = "f", digits = 2, big.mark = ",")
  })
  output$vb_units = renderText({
    format(sum(filtered()$units), big.mark = ",")
  })
  output$vb_price = renderText({
    sprintf("%.2f", mean(filtered()$price))
  })

  output$trend = renderPlotly({
    monthly = aggregate(revenue ~ month, data = filtered(), FUN = sum)
    plot_ly(monthly, x = ~month, y = ~revenue, type = "scatter", mode = "lines+markers") |>
      layout(xaxis = list(title = "Month"), yaxis = list(title = "Revenue"))
  })

  output$regions = renderPlotly({
    by_region = aggregate(revenue ~ region, data = sales, FUN = sum)
    plot_ly(by_region, x = ~region, y = ~revenue, type = "bar") |>
      layout(xaxis = list(title = "Region"), yaxis = list(title = "Revenue"))
  })

  output$data = renderDT({
    datatable(head(filtered(), 10), rownames = FALSE, options = list(dom = "t"))
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L3/html_a.html`**

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Sales dashboard</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
</head>
<body class="container-fluid py-3">
<h2>Sales dashboard</h2>
<div class="row">
  <div class="col-md-3">
    <label for="region" class="form-label">Region</label>
    <select id="region" class="form-select"><option>All</option></select>
  </div>
  <div class="col-md-9">
    <div class="row g-3 mb-3">
      <div class="col"><div class="card card-body"><div>Total revenue</div><h3 id="vb_revenue"></h3></div></div>
      <div class="col"><div class="card card-body"><div>Total units</div><h3 id="vb_units"></h3></div></div>
      <div class="col"><div class="card card-body"><div>Average price</div><h3 id="vb_price"></h3></div></div>
    </div>
    <ul class="nav nav-tabs">
      <li class="nav-item"><button class="nav-link active" data-bs-toggle="tab" data-bs-target="#tab-trend">Trend</button></li>
      <li class="nav-item"><button class="nav-link" data-bs-toggle="tab" data-bs-target="#tab-regions">Regions</button></li>
      <li class="nav-item"><button class="nav-link" data-bs-toggle="tab" data-bs-target="#tab-data">Data</button></li>
    </ul>
    <div class="tab-content pt-2">
      <div class="tab-pane show active" id="tab-trend"><div id="trend" style="height:400px"></div></div>
      <div class="tab-pane" id="tab-regions"><div id="regions" style="height:400px"></div></div>
      <div class="tab-pane" id="tab-data">
        <table class="table table-sm" id="data"><thead></thead><tbody></tbody></table>
      </div>
    </div>
  </div>
</div>
<script>
const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
const COLS = ["region","month","units","price","revenue"];
const fmt = (x, d) => x.toLocaleString("en-US", {minimumFractionDigits: d, maximumFractionDigits: d});
const sum = (rows, k) => rows.reduce((s, r) => s + r[k], 0);
let sales = [];
function update() {
  const r = document.getElementById("region").value;
  const rows = r === "All" ? sales : sales.filter(d => d.region === r);
  document.getElementById("vb_revenue").textContent = fmt(sum(rows, "revenue"), 2);
  document.getElementById("vb_units").textContent = fmt(sum(rows, "units"), 0);
  document.getElementById("vb_price").textContent = (sum(rows, "price") / rows.length).toFixed(2);
  const byMonth = MONTHS.map(m => sum(rows.filter(d => d.month === m), "revenue"));
  Plotly.react("trend", [{x: MONTHS, y: byMonth, mode: "lines+markers"}], {margin: {t: 20}});
  document.querySelector("#data thead").innerHTML = "<tr>" + COLS.map(c => `<th>${c}</th>`).join("") + "</tr>";
  document.querySelector("#data tbody").innerHTML = rows.slice(0, 10)
    .map(d => "<tr>" + COLS.map(c => `<td>${d[c]}</td>`).join("") + "</tr>").join("");
}
fetch("data/sales.json").then(r => r.json()).then(d => {
  sales = d;
  const regions = [...new Set(d.map(x => x.region))].sort();
  const sel = document.getElementById("region");
  regions.forEach(r => sel.add(new Option(r)));
  sel.addEventListener("change", update);
  Plotly.newPlot("regions", [{type: "bar", x: regions,
    y: regions.map(g => sum(d.filter(x => x.region === g), "revenue"))}], {margin: {t: 20}});
  update();
});
document.querySelector('[data-bs-target="#tab-regions"]')
  .addEventListener("shown.bs.tab", () => Plotly.Plots.resize("regions"));
</script>
</body>
</html>
````

**`G2/a_apps/L3/html_b.html`**

````html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Sales dashboard</title>
  <link rel="stylesheet" href="https://cdn.datatables.net/2.1.8/css/dataTables.dataTables.min.css">
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/2.1.8/js/dataTables.min.js"></script>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; display: flex; }
    #sidebar { width: 220px; padding: 20px; background: #f4f4f4; min-height: 100vh; }
    #main { flex: 1; padding: 20px; }
    .boxes { display: flex; gap: 16px; margin-bottom: 20px; }
    .box { flex: 1; padding: 16px; border-radius: 8px; background: #2c7be5; color: white; }
    .box .label { font-size: 14px; opacity: 0.8; }
    .box .value { font-size: 26px; font-weight: bold; }
    .tabs button { padding: 8px 16px; border: none; background: #ddd; cursor: pointer; }
    .tabs button.active { background: #2c7be5; color: white; }
    .tab { display: none; padding-top: 12px; }
    .tab.active { display: block; }
  </style>
</head>
<body>
  <div id="sidebar">
    <h2>Sales dashboard</h2>
    <label for="region">Region</label><br>
    <select id="region">
      <option value="All">All</option>
      <option value="East">East</option>
      <option value="North">North</option>
      <option value="South">South</option>
      <option value="West">West</option>
    </select>
  </div>
  <div id="main">
    <div class="boxes">
      <div class="box"><div class="label">Total revenue</div><div class="value" id="vb_revenue"></div></div>
      <div class="box"><div class="label">Total units</div><div class="value" id="vb_units"></div></div>
      <div class="box"><div class="label">Average price</div><div class="value" id="vb_price"></div></div>
    </div>
    <div class="tabs">
      <button class="active" data-tab="trend-tab">Trend</button>
      <button data-tab="regions-tab">Regions</button>
      <button data-tab="data-tab">Data</button>
    </div>
    <div class="tab active" id="trend-tab"><div id="trend"></div></div>
    <div class="tab" id="regions-tab"><div id="regions"></div></div>
    <div class="tab" id="data-tab"><table id="data" class="display" style="width:100%"></table></div>
  </div>
  <script>
    var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var allRows = [];
    var dataTable = null;

    function money(x) {
      return x.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    function sumBy(rows, key) {
      var total = 0;
      rows.forEach(function (row) { total += row[key]; });
      return total;
    }

    function update() {
      var region = $("#region").val();
      var rows = region === "All" ? allRows : allRows.filter(function (row) { return row.region === region; });
      $("#vb_revenue").text(money(sumBy(rows, "revenue")));
      $("#vb_units").text(sumBy(rows, "units").toLocaleString("en-US"));
      $("#vb_price").text((sumBy(rows, "price") / rows.length).toFixed(2));

      var monthly = MONTHS.map(function (m) {
        return sumBy(rows.filter(function (row) { return row.month === m; }), "revenue");
      });
      Plotly.newPlot("trend", [{ x: MONTHS, y: monthly, type: "scatter", mode: "lines+markers" }],
        { xaxis: { title: "Month" }, yaxis: { title: "Revenue" } });

      var tableRows = rows.slice(0, 10).map(function (row) {
        return [row.region, row.month, row.units, row.price, row.revenue];
      });
      if (dataTable) {
        dataTable.clear().rows.add(tableRows).draw();
      } else {
        dataTable = $("#data").DataTable({
          data: tableRows,
          columns: [{ title: "region" }, { title: "month" }, { title: "units" }, { title: "price" }, { title: "revenue" }],
          paging: false, searching: false, info: false
        });
      }
    }

    function drawRegions() {
      var regions = ["East", "North", "South", "West"];
      var totals = regions.map(function (g) {
        return sumBy(allRows.filter(function (row) { return row.region === g; }), "revenue");
      });
      Plotly.newPlot("regions", [{ x: regions, y: totals, type: "bar" }],
        { xaxis: { title: "Region" }, yaxis: { title: "Revenue" } });
    }

    $(document).ready(function () {
      $(".tabs button").on("click", function () {
        $(".tabs button").removeClass("active");
        $(".tab").removeClass("active");
        $(this).addClass("active");
        $("#" + $(this).data("tab")).addClass("active");
        window.dispatchEvent(new Event("resize"));
      });
      $.getJSON("data/sales.json", function (rows) {
        allRows = rows;
        $("#region").on("change", update);
        drawRegions();
        update();
      });
    });
  </script>
</body>
</html>
````

**`G2/a_apps/L4/shiny_a.R`**

````r
library(shiny)
library(bslib)

ui = page_fillable(
  h2("Car explorer"),
  layout_columns(
    plotOutput("plot", brush = "brush"),
    card(textOutput("n"), tableOutput("selected"), downloadButton("download", "Download CSV"))
  )
)

server = function(input, output) {
  picked = reactive(brushedPoints(cars_df, input$brush, xvar = "wt", yvar = "mpg")[c("name", "wt", "mpg", "hp")])
  output$plot = renderPlot(plot(mpg ~ wt, cars_df, pch = 19))
  output$n = renderText(paste(nrow(picked()), "selected"))
  output$selected = renderTable(picked())
  output$download = downloadHandler("selected.csv", function(file) write.csv(picked(), file, row.names = FALSE))
}

shinyApp(ui, server)
````

**`G2/a_apps/L4/shiny_b.R`**

````r
library(shiny)
library(plotly)
library(DT)

ui = fluidPage(
  titlePanel("Car explorer"),
  fluidRow(
    column(7, plotlyOutput("plot")),
    column(5,
           textOutput("n"),
           DTOutput("selected"),
           downloadButton("download", "Download CSV"))
  )
)

server = function(input, output, session) {
  output$plot = renderPlotly({
    plot_ly(cars_df, x = ~wt, y = ~mpg, key = ~name, type = "scatter", mode = "markers",
            source = "cars") |>
      layout(dragmode = "select") |>
      event_register("plotly_selected")
  })

  selected_rows = reactive({
    ev = event_data("plotly_selected", source = "cars")
    if (is.null(ev) || length(ev$key) == 0) {
      cars_df[0, c("name", "wt", "mpg", "hp")]
    } else {
      cars_df[cars_df$name %in% ev$key, c("name", "wt", "mpg", "hp")]
    }
  })

  output$n = renderText({
    paste(nrow(selected_rows()), "selected")
  })

  output$selected = renderDT({
    datatable(selected_rows(), rownames = FALSE, options = list(dom = "t", paging = FALSE))
  })

  output$download = downloadHandler(
    filename = function() "selected.csv",
    content = function(file) {
      write.csv(selected_rows(), file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
````

**`G2/a_apps/L4/html_a.html`**

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Car explorer</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
</head>
<body class="container py-3">
<h2>Car explorer</h2>
<div class="row">
  <div class="col-md-7"><div id="plot" style="height:450px"></div></div>
  <div class="col-md-5">
    <p id="n">0 selected</p>
    <table class="table table-sm" id="selected">
      <thead><tr><th>name</th><th>wt</th><th>mpg</th><th>hp</th></tr></thead><tbody></tbody>
    </table>
    <button id="download" class="btn btn-primary">Download CSV</button>
  </div>
</div>
<script>
const COLS = ["name", "wt", "mpg", "hp"];
let cars = [], picked = [];
function show() {
  document.getElementById("n").textContent = `${picked.length} selected`;
  document.querySelector("#selected tbody").innerHTML = picked
    .map(c => "<tr>" + COLS.map(k => `<td>${c[k]}</td>`).join("") + "</tr>").join("");
}
fetch("data/cars_df.json").then(r => r.json()).then(d => {
  cars = d;
  const plot = document.getElementById("plot");
  Plotly.newPlot(plot, [{x: d.map(c => c.wt), y: d.map(c => c.mpg), text: d.map(c => c.name),
    mode: "markers", type: "scatter"}], {dragmode: "select", xaxis: {title: "wt"}, yaxis: {title: "mpg"}});
  plot.on("plotly_selected", ev => { picked = ev ? ev.points.map(p => cars[p.pointIndex]) : []; show(); });
  plot.on("plotly_deselect", () => { picked = []; show(); });
});
document.getElementById("download").addEventListener("click", () => {
  const csv = [COLS.join(","), ...picked.map(c => COLS.map(k => JSON.stringify(c[k])).join(","))].join("\n");
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([csv], {type: "text/csv"}));
  a.download = "selected.csv";
  a.click();
});
</script>
</body>
</html>
````

**`G2/a_apps/L4/html_b.html`**

````html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Car explorer</title>
  <link rel="stylesheet" href="https://cdn.datatables.net/2.1.8/css/dataTables.dataTables.min.css">
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/2.1.8/js/dataTables.min.js"></script>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .layout { display: flex; gap: 24px; }
    #plot { flex: 3; height: 480px; }
    .side { flex: 2; }
    button { margin-top: 12px; padding: 8px 14px; }
  </style>
</head>
<body>
  <h1>Car explorer</h1>
  <div class="layout">
    <div id="plot"></div>
    <div class="side">
      <p id="n">0 selected</p>
      <table id="selected" class="display" style="width:100%"></table>
      <button id="download">Download CSV</button>
    </div>
  </div>
  <script>
    var COLUMNS = ["name", "wt", "mpg", "hp"];
    var cars = [];
    var selected = [];
    var table;

    function refresh() {
      $("#n").text(selected.length + " selected");
      table.clear();
      table.rows.add(selected.map(function (car) {
        return COLUMNS.map(function (col) { return car[col]; });
      }));
      table.draw();
    }

    function toCsv(rows) {
      var lines = [COLUMNS.join(",")];
      rows.forEach(function (car) {
        lines.push(COLUMNS.map(function (col) {
          var value = car[col];
          return typeof value === "string" ? '"' + value.replace(/"/g, '""') + '"' : value;
        }).join(","));
      });
      return lines.join("\n");
    }

    $(document).ready(function () {
      table = $("#selected").DataTable({
        data: [],
        columns: COLUMNS.map(function (col) { return { title: col }; }),
        paging: false, searching: false, info: false
      });

      $.getJSON("data/cars_df.json", function (rows) {
        cars = rows;
        var trace = {
          x: cars.map(function (c) { return c.wt; }),
          y: cars.map(function (c) { return c.mpg; }),
          text: cars.map(function (c) { return c.name; }),
          mode: "markers",
          type: "scatter"
        };
        var layout = { dragmode: "select", xaxis: { title: "Weight (wt)" }, yaxis: { title: "MPG" } };
        Plotly.newPlot("plot", [trace], layout);
        var plot = document.getElementById("plot");
        plot.on("plotly_selected", function (event) {
          selected = event ? event.points.map(function (p) { return cars[p.pointIndex]; }) : [];
          refresh();
        });
        plot.on("plotly_deselect", function () {
          selected = [];
          refresh();
        });
      });

      $("#download").on("click", function () {
        var blob = new Blob([toCsv(selected)], { type: "text/csv;charset=utf-8" });
        var link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "selected.csv";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
      });
    });
  </script>
</body>
</html>
````

**`G2/a_apps/L5/shiny_a.R`**

````r
library(shiny)
library(bslib)
library(DT)

money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")

warehouse_ui = function(id, title) {
  ns = NS(id)
  card(card_header(title), DTOutput(ns("table")), textOutput(ns("value")))
}

warehouse_server = function(id, data) {
  moduleServer(id, function(input, output, session) {
    inv = reactiveVal(data)
    output$table = renderDT(datatable(data, rownames = FALSE, selection = "none",
                                      editable = list(target = "cell", disable = list(columns = 0))))
    observeEvent(input$table_cell_edit, {
      e = input$table_cell_edit
      d = inv()
      d[e$row, e$col + 1] = as.numeric(e$value)
      inv(d)
    })
    output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))
    reactive(sum(inv()$price * inv()$stock))
  })
}

ui = page_fixed(
  h2("Inventory"),
  layout_columns(warehouse_ui("a", "Warehouse A"), warehouse_ui("b", "Warehouse B")),
  textOutput("total")
)

server = function(input, output) {
  a = warehouse_server("a", inv_a)
  b = warehouse_server("b", inv_b)
  output$total = renderText(paste("Total stock value:", money(a() + b())))
}

shinyApp(ui, server)
````

**`G2/a_apps/L5/shiny_b.R`**

````r
library(shiny)

format_money = function(x) {
  formatC(x, format = "f", digits = 2, big.mark = ",")
}

warehouseUI = function(id, title) {
  ns = NS(id)
  tagList(
    h3(title),
    uiOutput(ns("table")),
    p(textOutput(ns("value"), inline = TRUE))
  )
}

warehouseServer = function(id, inventory) {
  moduleServer(id, function(input, output, session) {
    ns = session$ns

    output$table = renderUI({
      rows = lapply(seq_len(nrow(inventory)), function(i) {
        tags$tr(
          tags$td(inventory$product[i]),
          tags$td(numericInput(ns(paste0("price_", i)), NULL, inventory$price[i], min = 0, width = "100px")),
          tags$td(numericInput(ns(paste0("stock_", i)), NULL, inventory$stock[i], min = 0, width = "100px"))
        )
      })
      tags$table(
        class = "table",
        tags$thead(tags$tr(tags$th("product"), tags$th("price"), tags$th("stock"))),
        tags$tbody(rows)
      )
    })

    current = reactive({
      n = nrow(inventory)
      data.frame(
        product = inventory$product,
        price = vapply(seq_len(n), function(i) input[[paste0("price_", i)]] %||% inventory$price[i], numeric(1)),
        stock = vapply(seq_len(n), function(i) input[[paste0("stock_", i)]] %||% inventory$stock[i], numeric(1))
      )
    })

    stock_value = reactive({
      sum(current()$price * current()$stock, na.rm = TRUE)
    })

    output$value = renderText({
      paste("Stock value:", format_money(stock_value()))
    })

    stock_value
  })
}

ui = fluidPage(
  titlePanel("Inventory"),
  fluidRow(
    column(6, warehouseUI("a", "Warehouse A")),
    column(6, warehouseUI("b", "Warehouse B"))
  ),
  h4(textOutput("total"))
)

server = function(input, output, session) {
  value_a = warehouseServer("a", inv_a)
  value_b = warehouseServer("b", inv_b)

  output$total = renderText({
    paste("Total stock value:", format_money(value_a() + value_b()))
  })
}

shinyApp(ui, server)
````

**`G2/a_apps/L5/html_a.html`**

````html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Inventory</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
</head>
<body class="container py-3">
<h2>Inventory</h2>
<div class="row">
  <div class="col" id="a"></div>
  <div class="col" id="b"></div>
</div>
<p id="total"></p>
<script>
const money = x => x.toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2});
const warehouses = [];
function renderAll() {
  warehouses.forEach(w => document.getElementById(`${w.id}-value`).textContent = `Stock value: ${money(w.value())}`);
  document.getElementById("total").textContent =
    `Total stock value: ${money(warehouses.reduce((s, w) => s + w.value(), 0))}`;
}
function warehouse(id, title, rows) {
  const el = document.getElementById(id);
  el.innerHTML = `<div class="card"><div class="card-header">${title}</div>
    <table class="table table-sm mb-0" id="${id}-table">
    <thead><tr><th>product</th><th>price</th><th>stock</th></tr></thead><tbody>` +
    rows.map((r, i) => `<tr><td>${r.product}</td><td contenteditable data-i="${i}" data-k="price">${r.price}</td>` +
      `<td contenteditable data-i="${i}" data-k="stock">${r.stock}</td></tr>`).join("") +
    `</tbody></table><div class="card-body" id="${id}-value"></div></div>`;
  el.addEventListener("input", e => {
    const c = e.target;
    rows[c.dataset.i][c.dataset.k] = Number(c.textContent) || 0;
    renderAll();
  });
  warehouses.push({id, value: () => rows.reduce((s, r) => s + r.price * r.stock, 0)});
}
Promise.all(["inv_a", "inv_b"].map(n => fetch(`data/${n}.json`).then(r => r.json()))).then(([a, b]) => {
  warehouse("a", "Warehouse A", a);
  warehouse("b", "Warehouse B", b);
  renderAll();
});
</script>
</body>
</html>
````

**`G2/a_apps/L5/html_b.html`**

````html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Inventory</title>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .warehouses { display: flex; gap: 32px; }
    .warehouse { flex: 1; border: 1px solid #ccc; border-radius: 6px; padding: 12px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border-bottom: 1px solid #eee; padding: 4px 8px; text-align: left; }
    input[type=number] { width: 90px; }
    #total { font-size: 18px; font-weight: bold; margin-top: 16px; }
  </style>
</head>
<body>
  <h1>Inventory</h1>
  <div class="warehouses">
    <div class="warehouse" id="a"></div>
    <div class="warehouse" id="b"></div>
  </div>
  <p id="total"></p>
  <script>
    function formatMoney(x) {
      return x.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    class Warehouse {
      constructor(id, title, rows, onChange) {
        this.id = id;
        this.title = title;
        this.rows = rows;
        this.onChange = onChange;
        this.render();
      }

      value() {
        return this.rows.reduce(function (sum, row) { return sum + row.price * row.stock; }, 0);
      }

      render() {
        var self = this;
        var $root = $("#" + this.id).empty();
        $root.append($("<h3>").text(this.title));
        var $table = $("<table>").attr("id", this.id + "-table");
        $table.append("<thead><tr><th>product</th><th>price</th><th>stock</th></tr></thead>");
        var $body = $("<tbody>");
        this.rows.forEach(function (row, i) {
          var $tr = $("<tr>");
          $tr.append($("<td>").text(row.product));
          ["price", "stock"].forEach(function (key) {
            var $input = $("<input type='number' min='0'>").val(row[key]).attr("data-row", i).attr("data-key", key);
            $input.on("input change", function () {
              self.rows[i][key] = parseFloat($(this).val()) || 0;
              self.update();
            });
            $tr.append($("<td>").append($input));
          });
          $body.append($tr);
        });
        $table.append($body);
        $root.append($table);
        $root.append($("<p>").attr("id", this.id + "-value"));
        this.update();
      }

      update() {
        $("#" + this.id + "-value").text("Stock value: " + formatMoney(this.value()));
        if (this.onChange) this.onChange();
      }
    }

    var warehouses = [];

    function updateTotal() {
      var total = warehouses.reduce(function (sum, w) { return sum + w.value(); }, 0);
      $("#total").text("Total stock value: " + formatMoney(total));
    }

    $(document).ready(function () {
      $.when($.getJSON("data/inv_a.json"), $.getJSON("data/inv_b.json")).done(function (a, b) {
        warehouses.push(new Warehouse("a", "Warehouse A", a[0], updateTotal));
        warehouses.push(new Warehouse("b", "Warehouse B", b[0], updateTotal));
        updateTotal();
      });
    });
  </script>
</body>
</html>
````

### 5.2 Part (a): checker, mutants, revisions, token counts, and their outputs

**`G2/a_check.R`**

````r
# G2 (a): functional verification of the 20 apps (5 levels x {shiny_a, shiny_b, html_a, html_b}).
# Ladder per app: parse -> launch (Shiny in a callr child; HTML via a static server child) ->
# HTTP 200 -> headless Chrome (chromote) with spec assertions and one interaction per level.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
A = file.path(G2, "a_apps")
source(file.path(A, "data.R"))
APPS = Sys.getenv("G2_APPS", A)
IMPLS = strsplit(Sys.getenv("G2_IMPLS", "shiny_a,shiny_b,html_a,html_b"), ",")[[1]]
money = function(x) formatC(x, format = "f", digits = 2, big.mark = ",")
shots = file.path(G2, "a_shots"); dir.create(shots, showWarnings = FALSE)
args = commandArgs(TRUE)
only = if (length(args)) args else NULL

# ---------- expected values (computed in R, independent of the apps) ----------
agg = aggregate(cbind(units, revenue) ~ region, sales, sum)
agg$orders = as.vector(table(sales$region)[agg$region])
agg = agg[order(-agg$revenue), ]
exp_l1 = paste(sprintf("%s|%d|%s|%s", agg$region, agg$orders, format(agg$units, big.mark = ",", trim = TRUE),
                       money(agg$revenue)), collapse = "||")
n_north = sum(sales$region == "North")
rev_north = sum(sales$revenue[sales$region == "North"])
west = sales[sales$region == "West", ]
exp_l3_all = c(money(sum(sales$revenue)), format(sum(sales$units), big.mark = ","), sprintf("%.2f", mean(sales$price)))
exp_l3_west = money(sum(west$revenue))
val = function(d) sum(d$price * d$stock)
inv_a2 = inv_a; inv_a2$stock[1] = 100
exp_l5_init = c(money(val(inv_a)), money(val(inv_b)), money(val(inv_a) + val(inv_b)))
exp_l5_edit = c(money(val(inv_a2)), money(val(inv_a2) + val(inv_b)))
cars_js = j(cars_df[c("name", "wt", "mpg")])

# ---------- static site for the HTML apps (CDN URLs -> package-shipped copies; no network) ----------
L = .libPaths()
pkgfile = function(pkg, ...) system.file(..., package = pkg)
site = file.path(G2, "a_site"); unlink(site, recursive = TRUE)
dir.create(file.path(site, "vendor"), recursive = TRUE); dir.create(file.path(site, "data"))
vendor = c(
  "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" = pkgfile("bslib", "css-precompiled/5/bootstrap.min.css"),
  "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" = pkgfile("bslib", "lib/bs5/dist/js/bootstrap.bundle.min.js"),
  "https://cdn.plot.ly/plotly-2.35.2.min.js" = pkgfile("plotly", "htmlwidgets/lib/plotlyjs/plotly-latest.min.js"),
  "https://cdn.datatables.net/2.1.8/css/dataTables.dataTables.min.css" = pkgfile("DT", "htmlwidgets/lib/datatables/css/jquery.dataTables.extra.css"),
  "https://cdn.datatables.net/2.1.8/js/dataTables.min.js" = pkgfile("DT", "htmlwidgets/lib/datatables/js/jquery.dataTables.min.js"),
  "https://code.jquery.com/jquery-3.7.1.min.js" = pkgfile("shiny", "www/shared/jquery.min.js"))
local_name = paste0("vendor/v", seq_along(vendor), sub(".*([.](js|css))$", "\\1", names(vendor)))
invisible(file.copy(vendor, file.path(site, local_name)))
for (nm in c("sales", "cars_df", "inv_a", "inv_b")) {
  jsonlite::write_json(get(nm), file.path(site, "data", paste0(nm, ".json")), dataframe = "rows", digits = NA)
}
localise = function(x) {
  for (i in seq_along(vendor)) x = gsub(names(vendor)[i], local_name[i], x, fixed = TRUE)
  x
}
static_port = 18231L
static = callr::r_bg(function(dir, port, lib) {
  .libPaths(lib)
  httpuv::runStaticServer(dir, port = port, browse = FALSE)
}, list(dir = site, port = static_port, lib = L), supervise = TRUE)

# ---------- helpers ----------
http_ok = function(url, timeout = 30) {
  t0 = Sys.time()
  while (as.numeric(Sys.time() - t0, units = "secs") < timeout) {
    st = tryCatch(curl::curl_fetch_memory(url)$status_code, error = function(e) NA)
    if (identical(st, 200L)) return(TRUE)
    Sys.sleep(0.2)
  }
  FALSE
}
launch_shiny = function(file, port) {
  dir = tempfile("app"); dir.create(dir)
  file.copy(file, file.path(dir, "app.R"))
  log = tempfile(fileext = ".log")
  p = callr::r_bg(function(dir, port, data, lib) {
    .libPaths(lib)
    source(data)
    shiny::runApp(dir, port = port, launch.browser = FALSE)
  }, list(dir = dir, port = port, data = file.path(A, "data.R"), lib = L),
  stdout = log, stderr = "2>&1", supervise = TRUE)
  list(proc = p, log = log)
}
static_check = function(file) {
  ex = tryCatch(parse(file, keep.source = FALSE), error = function(e) e)
  if (inherits(ex, "error")) return(paste("parse error:", conditionMessage(ex)))
  last = ex[[length(ex)]]
  if (!is.call(last) || !identical(deparse(last[[1]]), "shinyApp")) return("last expression is not shinyApp()")
  "ok"
}

seed = if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv()) else NULL
chrome = chromote::Chromote$new()
if (!is.null(seed)) assign(".Random.seed", seed, globalenv())

session_run = function(url, steps, png) {
  b = chrome$new_session(width = 1200, height = 900)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  errs = character()
  b$Runtime$enable()
  b$Runtime$exceptionThrown(callback_ = function(m) errs <<- c(errs, m$exceptionDetails$exception$description %||% m$exceptionDetails$text))
  ld = b$Page$loadEventFired(wait_ = FALSE)
  b$Page$navigate(url, wait_ = FALSE)
  b$wait_for(ld)
  ev = function(js) {
    r = b$Runtime$evaluate(js, returnByValue = TRUE, awaitPromise = TRUE)
    if (!is.null(r$exceptionDetails)) return(paste("JSERR:", r$exceptionDetails$exception$description %||% r$exceptionDetails$text))
    r$result$value
  }
  wait = function(pred, timeout = 15) {
    t0 = Sys.time()
    repeat {
      v = ev(sprintf("(()=>{try{return !!(%s)}catch(e){return false}})()", pred))
      if (isTRUE(v)) return(TRUE)
      if (as.numeric(Sys.time() - t0, units = "secs") > timeout) return(FALSE)
      Sys.sleep(0.15)
    }
  }
  res = list()
  for (s in steps) {
    if (!is.null(s$drag)) drag(b, ev, s$drag)
    if (!is.null(s$act)) ev(s$act)
    ok = wait(s$pred, s$timeout %||% 15)
    detail = if (!ok && !is.null(s$show)) ev(s$show) else ""
    res[[length(res) + 1]] = data.frame(step = s$name, ok = ok, detail = substr(paste(detail, collapse = " "), 1, 200))
  }
  out_err = ev("Array.from(document.querySelectorAll('.shiny-output-error:not(.shiny-output-error-validation)')).length")
  shot = b$Page$captureScreenshot(format = "png")$data
  writeBin(jsonlite::base64_dec(shot), png)
  list(steps = do.call(rbind, res), js_errors = unique(errs), output_errors = out_err %||% 0)
}
drag = function(b, ev, sel) {
  r = ev(sprintf("(()=>{const e=document.querySelector('%s'); const r=e.getBoundingClientRect(); return [r.left,r.top,r.width,r.height]})()", sel))
  r = unlist(r)
  x0 = r[1] + 0.30 * r[3]; y0 = r[2] + 0.25 * r[4]; x1 = r[1] + 0.62 * r[3]; y1 = r[2] + 0.75 * r[4]
  b$Input$dispatchMouseEvent(type = "mouseMoved", x = x0, y = y0)
  b$Input$dispatchMouseEvent(type = "mousePressed", x = x0, y = y0, button = "left", buttons = 1, clickCount = 1)
  for (k in 1:8) {
    b$Input$dispatchMouseEvent(type = "mouseMoved", x = x0 + (x1 - x0) * k / 8, y = y0 + (y1 - y0) * k / 8,
                               button = "left", buttons = 1)
    Sys.sleep(0.03)
  }
  b$Input$dispatchMouseEvent(type = "mouseReleased", x = x1, y = y1, button = "left", buttons = 1, clickCount = 1)
  Sys.sleep(0.5)
}

# ---------- per-level steps (same assertions for all four implementations) ----------
txt = function(sel) sprintf("(document.querySelector('%s')||{textContent:''}).textContent.trim()", sel)
set_select = function(v) sprintf("(()=>{const s=document.getElementById('region'); if (s.selectize) s.selectize.setValue('%s'); else {s.value='%s'; s.dispatchEvent(new Event('change',{bubbles:true}));} return 1})()", v, v)
chart_js = function(id) sprintf("(document.querySelectorAll('#%s .main-svg').length>0 || !!document.querySelector('#%s img[src^=\"data:image\"]'))", id, id)
rows_js = "[...document.querySelectorAll('table tbody tr')].filter(tr=>tr.cells.length>=4).map(tr=>[...tr.cells].slice(0,4).map(c=>c.textContent.trim()).join('|')).join('||')"

steps_for = function(level, impl) {
  is_shiny = startsWith(impl, "shiny")
  switch(level,
    L1 = list(list(name = "table rows sorted, formatted", pred = sprintf("%s === '%s'", rows_js, exp_l1), show = rows_js)),
    L2 = list(
      list(name = "initial count 5000", pred = sprintf("%s === '5000 orders' && %s", txt("#n"), chart_js("chart")), show = txt("#n")),
      list(name = "select North -> count + bars", act = set_select("North"),
           pred = sprintf("%s === '%d orders' && %s && (!document.getElementById('chart').data || Math.abs(document.getElementById('chart').data[0].y.reduce((a,b)=>a+b,0) - %.4f) < 0.01)",
                          txt("#n"), n_north, chart_js("chart"), rev_north), show = txt("#n"))),
    L3 = list(
      list(name = "value boxes (All) + trend chart + 3 tabs",
           pred = sprintf("%s==='%s' && %s==='%s' && %s==='%s' && %s && ['Trend','Regions','Data'].every(t=>[...document.querySelectorAll('a,button')].some(e=>e.textContent.trim()===t))",
                          txt("#vb_revenue"), exp_l3_all[1], txt("#vb_units"), exp_l3_all[2], txt("#vb_price"), exp_l3_all[3], chart_js("trend")),
           show = sprintf("[%s,%s,%s].join(' ; ')", txt("#vb_revenue"), txt("#vb_units"), txt("#vb_price"))),
      list(name = "select West -> revenue box", act = set_select("West"), pred = sprintf("%s==='%s'", txt("#vb_revenue"), exp_l3_west), show = txt("#vb_revenue")),
      list(name = "Data tab -> 10 West rows",
           act = "[...document.querySelectorAll('a,button')].find(e=>e.textContent.trim()==='Data').click()",
           pred = "(()=>{const r=[...document.querySelectorAll('#data tbody tr')].filter(tr=>tr.cells.length>1); return r.length===10 && r.every(tr=>tr.cells[0].textContent.trim()==='West')})()",
           show = "document.querySelectorAll('#data tbody tr').length")),
    L4 = {
      gd = if (is_shiny && impl == "shiny_a") "#plot img" else "#plot .nsewdrag"
      bounds = if (impl == "shiny_a") {
        "(()=>{const v=Shiny.shinyapp.$inputValues; const k=Object.keys(v).find(k=>k.startsWith('brush')); const b=v[k]; return b?[b.xmin,b.xmax,b.ymin,b.ymax]:null})()"
      } else {
        "(()=>{const g=document.querySelector('#plot.js-plotly-plot')||document.querySelector('#plot .js-plotly-plot'); const s=(g.layout.selections||[])[0]; return s?[Math.min(s.x0,s.x1),Math.max(s.x0,s.x1),Math.min(s.y0,s.y1),Math.max(s.y0,s.y1)]:null})()"
      }
      expect = sprintf("(()=>{const b=%s; if(!b) return -1; const c=%s; return c.filter(r=>r.wt>=b[0]&&r.wt<=b[1]&&r.mpg>=b[2]&&r.mpg<=b[3]).map(r=>r.name).sort().join('|')})()", bounds, cars_js)
      shown = "[...document.querySelectorAll('#selected tbody tr')].filter(tr=>tr.cells.length>=4).map(tr=>tr.cells[0].textContent.trim()).sort().join('|')"
      dl = if (is_shiny) {
        "fetch(document.getElementById('download').href).then(r=>r.text())"
      } else {
        "(async()=>{window.__b=[]; const o=URL.createObjectURL; URL.createObjectURL=b=>{window.__b.push(b); return o.call(URL,b)}; document.getElementById('download').click(); await new Promise(r=>setTimeout(r,300)); return await window.__b[0].text()})()"
      }
      csv_ok = sprintf("(async()=>{const t=(await %s).trim().split(/\\r?\\n/); const e=%s; const names=t.slice(1).map(l=>l.split(',')[0].replace(/\"/g,'')).sort().join('|'); return t[0].replace(/\"/g,'').startsWith('name,wt,mpg,hp') && names===e})()", dl, expect)
      list(
        list(name = "initial 0 selected + scatter", pred = sprintf("%s==='0 selected' && document.querySelector('%s')", txt("#n"), gd), show = txt("#n")),
        list(name = "mouse brush -> count and table match bounds", drag = gd,
             pred = sprintf("(()=>{const e=%s; if (e===-1||e==='') return false; return %s===e.split('|').length+' selected' && %s===e})()", expect, txt("#n"), shown),
             show = sprintf("[%s, %s, JSON.stringify(%s)].join(' ; ')", txt("#n"), expect, bounds)),
        list(name = "download CSV = selection", pred = csv_ok, show = dl))
    },
    L5 = {
      edit = switch(impl,
        shiny_a = "(()=>{const td=document.querySelectorAll('#a-table tbody tr')[0].cells[2]; $(td).trigger('dblclick'); const i=td.querySelector('input'); i.value='100'; $(i).trigger('blur'); return 1})()",
        shiny_b = "(()=>{$('#a-stock_1').val(100).trigger('change'); return 1})()",
        html_a = "(()=>{const c=document.querySelector('#a-table td[data-i=\"0\"][data-k=\"stock\"]'); c.textContent='100'; c.dispatchEvent(new Event('input',{bubbles:true})); return 1})()",
        html_b = "(()=>{const i=document.querySelector('#a-table input[data-row=\"0\"][data-key=\"stock\"]'); i.value='100'; i.dispatchEvent(new Event('input',{bubbles:true})); return 1})()")
      list(
        list(name = "initial module values + total",
             pred = sprintf("%s==='Stock value: %s' && %s==='Stock value: %s' && %s==='Total stock value: %s' && document.querySelectorAll('#a-table tbody tr').length===8",
                            txt("#a-value"), exp_l5_init[1], txt("#b-value"), exp_l5_init[2], txt("#total"), exp_l5_init[3]),
             show = sprintf("[%s,%s,%s].join(' ; ')", txt("#a-value"), txt("#b-value"), txt("#total"))),
        list(name = "edit A row 1 stock=100 -> A value + total", act = edit,
             pred = sprintf("%s==='Stock value: %s' && %s==='Total stock value: %s'", txt("#a-value"), exp_l5_edit[1], txt("#total"), exp_l5_edit[2]),
             show = sprintf("[%s,%s].join(' ; ')", txt("#a-value"), txt("#total"))))
    })
}

# ---------- revision-specific steps (G2_REVISED=1; run on a_revised/) ----------
REVISED = identical(Sys.getenv("G2_REVISED"), "1")
top_avg = sprintf("%.2f", mean(sales$price[sales$region == agg$region[1]]))
low_a = paste("Low stock:", paste(inv_a$product[inv_a$stock < 50], collapse = ", "))
rev_steps = function(level, impl) switch(level,
  L1 = list(list(name = "rev: Avg price column", pred = sprintf("[...document.querySelectorAll('table thead th')].some(t=>t.textContent.trim()==='Avg price') && [...document.querySelectorAll('table tbody tr')][0].cells[4].textContent.trim()==='%s'", top_avg),
                 show = "[...document.querySelectorAll('table tbody tr')][0].textContent")),
  L2 = list(list(name = "rev: orange bars (plotly) / plot present (image)",
                 pred = "(()=>{const g=document.getElementById('chart'); return g.data ? JSON.stringify(g.data[0].marker||{}).includes('darkorange') || [...document.querySelectorAll('#chart .point path')].some(p=>getComputedStyle(p).fill.includes('255, 140, 0')) : !!document.querySelector('#chart img')})()",
                 show = "JSON.stringify((document.getElementById('chart').data||[{}])[0].marker)")),
  L3 = list(list(name = "rev: Orders value box", pred = sprintf("%s==='%s'", txt("#vb_orders"), format(sum(sales$region == "West"), big.mark = ",")), show = txt("#vb_orders"))),
  L4 = list(list(name = "rev: cyl column in table and CSV",
                 pred = sprintf("(async()=>{const r=[...document.querySelectorAll('#selected tbody tr')].filter(tr=>tr.cells.length>=5); const t=(await %s).trim().split(/\\r?\\n/); return r.length>0 && t[0].replace(/\"/g,'')==='name,wt,mpg,hp,cyl'})()",
                                if (startsWith(impl, "shiny")) "fetch(document.getElementById('download').href).then(r=>r.text())" else "(async()=>{window.__b=[]; const o=URL.createObjectURL; URL.createObjectURL=b=>{window.__b.push(b); return o.call(URL,b)}; document.getElementById('download').click(); await new Promise(r=>setTimeout(r,300)); return await window.__b[0].text()})()"),
                 show = "[...document.querySelectorAll('#selected tbody tr')].length")),
  L5 = list(list(name = "rev: low-stock line", pred = sprintf("%s==='%s'", txt("#a-low"), low_a), show = txt("#a-low"))))

# ---------- run ----------
stopifnot(http_ok(sprintf("http://127.0.0.1:%d/data/inv_a.json", static_port)))
port = 18300L
out = list()
for (level in paste0("L", 1:5)) for (impl in IMPLS) {
  if (!is.null(only) && !(level %in% only)) next
  is_shiny = startsWith(impl, "shiny")
  f = file.path(APPS, level, paste0(impl, if (is_shiny) ".R" else ".html"))
  t0 = Sys.time()
  if (is_shiny) {
    parse_ok = static_check(f)
    port = port + 1L
    app = launch_shiny(f, port)
    url = sprintf("http://127.0.0.1:%d/", port)
  } else {
    html = readLines(f, warn = FALSE)
    parse_ok = if (any(grepl("</html>", html, fixed = TRUE))) "ok" else "no </html>"
    page = sprintf("%s_%s.html", level, impl)
    writeLines(localise(html), file.path(site, page))
    url = sprintf("http://127.0.0.1:%d/%s", static_port, page)
  }
  h200 = http_ok(url)
  r = if (h200) session_run(url, c(steps_for(level, impl), if (REVISED) rev_steps(level, impl)), file.path(shots, sprintf("%s_%s.png", level, impl))) else NULL
  log_err = character()
  if (is_shiny) {
    app$proc$kill()
    lg = readLines(app$log, warn = FALSE)
    log_err = grep("^(Warning: )?Error", lg, value = TRUE)
  }
  all_ok = identical(parse_ok, "ok") && h200 && !is.null(r) && all(r$steps$ok) &&
    length(r$js_errors) == 0 && r$output_errors == 0 && length(log_err) == 0
  cat(sprintf("%s %-8s parse=%s http200=%s steps=%s js_err=%d out_err=%d log_err=%d => %s (%.1fs)\n",
              level, impl, parse_ok, h200, if (is.null(r)) "-" else paste0(sum(r$steps$ok), "/", nrow(r$steps)),
              if (is.null(r)) 0L else length(r$js_errors), if (is.null(r)) 0L else as.integer(r$output_errors),
              length(log_err), if (all_ok) "PASS" else "FAIL", as.numeric(Sys.time() - t0, units = "secs")))
  if (!is.null(r) && !all(r$steps$ok)) print(r$steps[!r$steps$ok, ])
  if (!is.null(r) && length(r$js_errors)) cat("   js errors:", r$js_errors, "\n")
  if (length(log_err)) cat("   log:", head(log_err, 3), sep = "\n   ")
  out[[length(out) + 1]] = data.frame(level, impl, pass = all_ok)
}
static$kill()
chrome$close()
res = do.call(rbind, out)
cat(sprintf("\nPASS %d of %d apps\n", sum(res$pass), nrow(res)))
````

**`G2/out/a_check_original.txt`**

````text
L1 shiny_a  parse=ok http200=TRUE steps=1/1 js_err=0 out_err=0 log_err=0 => PASS (1.2s)
L1 shiny_b  parse=ok http200=TRUE steps=1/1 js_err=0 out_err=0 log_err=0 => PASS (0.9s)
L1 html_a   parse=ok http200=TRUE steps=1/1 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L1 html_b   parse=ok http200=TRUE steps=1/1 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L2 shiny_a  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.3s)
L2 shiny_b  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.8s)
L2 html_a   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.6s)
L2 html_b   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.6s)
L3 shiny_a  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.9s)
L3 shiny_b  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (2.0s)
L3 html_a   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L3 html_b   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L4 shiny_a  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (2.2s)
L4 shiny_b  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (2.5s)
L4 html_a   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.1s)
L4 html_b   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.1s)
L5 shiny_a  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.4s)
L5 shiny_b  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.2s)
L5 html_a   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L5 html_b   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
[1] TRUE

PASS 20 of 20 apps
````

**`G2/a_mutants.R`**

````r
# G2 (a) negative controls: one subtle bug per level in shiny_a and html_a; the checker must FAIL them.
G2 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2"
src = file.path(G2, "a_apps"); dst = file.path(G2, "a_mutants")
unlink(dst, recursive = TRUE)
mut = list(
  L1 = list(shiny_a = c("agg[order(-agg$revenue), ]", "agg[order(agg$revenue), ]"),
            html_a = c("b[1].revenue - a[1].revenue", "a[1].revenue - b[1].revenue")),
  L2 = list(shiny_a = c("sales$region == input$region", "sales$region != input$region"),
            html_a = c("`${rows.length} orders`", "`${rows.length + 1} orders`")),
  L3 = list(shiny_a = c("mean(sel()$price)", "median(sel()$price)"),
            html_a = c("rows.slice(0, 10)", "rows.slice(0, 9)")),
  L4 = list(shiny_a = c("xvar = \"wt\", yvar = \"mpg\"", "xvar = \"mpg\", yvar = \"wt\""),
            html_a = c("const COLS = [\"name\", \"wt\", \"mpg\", \"hp\"];", "const COLS = [\"name\", \"wt\", \"mpg\"];")),
  L5 = list(shiny_a = c("d[e$row, e$col + 1]", "d[e$row, e$col]"),
            html_a = c("warehouses.reduce((s, w) => s + w.value(), 0)", "warehouses[0].value()")))
for (lv in names(mut)) {
  dir.create(file.path(dst, lv), recursive = TRUE)
  for (impl in names(mut[[lv]])) {
    ext = if (startsWith(impl, "shiny")) ".R" else ".html"
    x = readLines(file.path(src, lv, paste0(impl, ext)), warn = FALSE)
    pat = mut[[lv]][[impl]]
    hit = grepl(pat[1], x, fixed = TRUE)
    stopifnot(sum(hit) == 1)
    x[hit] = sub(pat[1], pat[2], x[hit], fixed = TRUE)
    writeLines(x, file.path(dst, lv, paste0(impl, ext)))
  }
}
cat("mutants written:", length(list.files(dst, recursive = TRUE)), "\n")
````

**`G2/out/a_check_mutants.txt`**

````text
L1 shiny_a  parse=ok http200=TRUE steps=0/1 js_err=0 out_err=0 log_err=0 => FAIL (16.1s)
                          step    ok
1 table rows sorted, formatted FALSE
                                                                                                                        detail
1 East|1196|47,772|1,294,167.04||North|1253|50,228|1,366,753.60||West|1254|49,978|1,374,920.38||South|1297|52,098|1,436,746.14
L1 html_a   parse=ok http200=TRUE steps=0/1 js_err=0 out_err=0 log_err=0 => FAIL (15.3s)
                          step    ok
1 table rows sorted, formatted FALSE
                                                                                                                        detail
1 East|1196|47,772|1,294,167.04||North|1253|50,228|1,366,753.60||West|1254|49,978|1,374,920.38||South|1297|52,098|1,436,746.14
L2 shiny_a  parse=ok http200=TRUE steps=1/2 js_err=0 out_err=0 log_err=0 => FAIL (16.3s)
                          step    ok      detail
2 select North -> count + bars FALSE 3747 orders
L2 html_a   parse=ok http200=TRUE steps=0/2 js_err=0 out_err=0 log_err=0 => FAIL (30.8s)
                          step    ok      detail
1           initial count 5000 FALSE 5001 orders
2 select North -> count + bars FALSE 1254 orders
L3 shiny_a  parse=ok http200=TRUE steps=2/3 js_err=0 out_err=0 log_err=0 => FAIL (17.0s)
                                      step    ok                         detail
1 value boxes (All) + trend chart + 3 tabs FALSE 5,472,587.16 ; 200,076 ; 27.16
L3 html_a   parse=ok http200=TRUE steps=2/3 js_err=0 out_err=0 log_err=0 => FAIL (15.7s)
                      step    ok detail
3 Data tab -> 10 West rows FALSE      9
L4 shiny_a  parse=ok http200=TRUE steps=2/3 js_err=0 out_err=0 log_err=0 => FAIL (17.1s)
                                         step    ok
2 mouse brush -> count and table match bounds FALSE
                                                                                                                                                                                                    detail
2 0 selected ; AMC Javelin|Dodge Challenger|Duster 360|Ferrari Dino|Ford Pantera L|Hornet 4 Drive|Hornet Sportabout|Maserati Bora|Mazda RX4|Mazda RX4 Wag|Merc 230|Merc 240D|Merc 280|Merc 280C|Merc 450SL
L4 html_a   parse=ok http200=TRUE steps=2/3 js_err=0 out_err=0 log_err=0 => FAIL (16.2s)
                                         step    ok
2 mouse brush -> count and table match bounds FALSE
                                                                                                                                                                                                    detail
2 14 selected ; Ferrari Dino|Ford Pantera L|Hornet 4 Drive|Hornet Sportabout|Mazda RX4|Mazda RX4 Wag|Merc 230|Merc 240D|Merc 280|Merc 280C|Merc 450SL|Pontiac Firebird|Valiant|Volvo 142E ; [2.58130794546
L5 shiny_a  parse=ok http200=TRUE steps=1/2 js_err=0 out_err=0 log_err=0 => FAIL (16.3s)
                                       step    ok
2 edit A row 1 stock=100 -> A value + total FALSE
                                                 detail
2 Stock value: 13,133.25 ; Total stock value: 14,544.25
L5 html_a   parse=ok http200=TRUE steps=0/2 js_err=0 out_err=0 log_err=0 => FAIL (30.4s)
                                       step    ok
1             initial module values + total FALSE
2 edit A row 1 stock=100 -> A value + total FALSE
                                                                       detail
1 Stock value: 1,277.25 ; Stock value: 1,411.00 ; Total stock value: 1,277.25
2                         Stock value: 1,253.25 ; Total stock value: 1,253.25
[1] TRUE

PASS 0 of 10 apps
````

**`G2/a_revisions.R`**

````r
# G2 (a) revisions: one functional change request per level applied to all four apps as exact-match
# edits (Pi edit semantics: each oldText unique in the original file). Writes a_revised/ and prints the
# output-token cost of the edit call vs a full rewrite (write call) for each app.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
src = file.path(G2, "a_apps"); dst = file.path(G2, "a_revised")
unlink(dst, recursive = TRUE)
e = function(old, new) list(oldText = old, newText = new)
R = list()
R$L1 = list(
  shiny_a = list(e('Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","))',
                   'Revenue = formatC(agg$revenue, format = "f", digits = 2, big.mark = ","),\n               "Avg price" = sprintf("%.2f", tapply(sales$price, sales$region, mean)[agg$region]),\n               check.names = FALSE)')),
  shiny_b = list(e('Revenue = sum(d$revenue))', 'Revenue = sum(d$revenue),\n               "Avg price" = mean(d$price), check.names = FALSE)'),
                 e('formatCurrency("Units", currency = "", digits = 0)', 'formatCurrency("Units", currency = "", digits = 0) |>\n      formatRound("Avg price", digits = 2)')),
  html_a = list(e('<th>Revenue</th></tr></thead>', '<th>Revenue</th><th>Avg price</th></tr></thead>'),
                e('{orders: 0, units: 0, revenue: 0}', '{orders: 0, units: 0, revenue: 0, price: 0}'),
                e('a.revenue += r.revenue;', 'a.revenue += r.revenue; a.price += r.price;'),
                e('<td>${fmt2(a.revenue)}</td>', '<td>${fmt2(a.revenue)}</td><td>${(a.price / a.orders).toFixed(2)}</td>')),
  html_b = list(e('<th>Revenue</th></tr>', '<th>Revenue</th><th>Avg price</th></tr>'),
                e('orders: 0, units: 0, revenue: 0 };', 'orders: 0, units: 0, revenue: 0, price: 0 };'),
                e('groups[row.region].revenue += row.revenue;', 'groups[row.region].revenue += row.revenue;\n        groups[row.region].price += row.price;'),
                e('g.revenue.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })];',
                  'g.revenue.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }),\n                  (g.price / g.orders).toFixed(2)];')))
R$L2 = list(
  shiny_a = list(e('col = "steelblue"', 'col = "darkorange"')),
  shiny_b = list(e('type = "bar")', 'type = "bar", marker = list(color = "darkorange"))')),
  html_a = list(e('y: MONTHS.map(m => rev[m])}]', 'y: MONTHS.map(m => rev[m]), marker: {color: "darkorange"}}]')),
  html_b = list(e('marker: { color: "#4682b4" }', 'marker: { color: "darkorange" }')))
R$L3 = list(
  shiny_a = list(e('value_box("Average price", textOutput("vb_price"))', 'value_box("Average price", textOutput("vb_price")),\n    value_box("Orders", textOutput("vb_orders"))'),
                 e('output$vb_price = renderText(sprintf("%.2f", mean(sel()$price)))', 'output$vb_price = renderText(sprintf("%.2f", mean(sel()$price)))\n  output$vb_orders = renderText(format(nrow(sel()), big.mark = ","))')),
  shiny_b = list(e('div(class = "col-sm-4",', 'div(class = "col-sm-3",'),
                 e('value_card("Average price", "vb_price")', 'value_card("Average price", "vb_price"),\n        value_card("Orders", "vb_orders")'),
                 e('sprintf("%.2f", mean(filtered()$price))\n  })', 'sprintf("%.2f", mean(filtered()$price))\n  })\n  output$vb_orders = renderText({\n    format(nrow(filtered()), big.mark = ",")\n  })')),
  html_a = list(e('<h3 id="vb_price"></h3></div></div>', '<h3 id="vb_price"></h3></div></div>\n      <div class="col"><div class="card card-body"><div>Orders</div><h3 id="vb_orders"></h3></div></div>'),
                e('.toFixed(2);\n', '.toFixed(2);\n  document.getElementById("vb_orders").textContent = fmt(rows.length, 0);\n')),
  html_b = list(e('<div class="value" id="vb_price"></div></div>', '<div class="value" id="vb_price"></div></div>\n      <div class="box"><div class="label">Orders</div><div class="value" id="vb_orders"></div></div>'),
                e('$("#vb_price").text((sumBy(rows, "price") / rows.length).toFixed(2));', '$("#vb_price").text((sumBy(rows, "price") / rows.length).toFixed(2));\n      $("#vb_orders").text(rows.length.toLocaleString("en-US"));')))
R$L4 = list(
  shiny_a = list(e('[c("name", "wt", "mpg", "hp")]', '[c("name", "wt", "mpg", "hp", "cyl")]')),
  shiny_b = list(e('cars_df[0, c("name", "wt", "mpg", "hp")]', 'cars_df[0, c("name", "wt", "mpg", "hp", "cyl")]'),
                 e('ev$key, c("name", "wt", "mpg", "hp")]', 'ev$key, c("name", "wt", "mpg", "hp", "cyl")]')),
  html_a = list(e('const COLS = ["name", "wt", "mpg", "hp"];', 'const COLS = ["name", "wt", "mpg", "hp", "cyl"];'),
                e('<th>hp</th></tr>', '<th>hp</th><th>cyl</th></tr>')),
  html_b = list(e('var COLUMNS = ["name", "wt", "mpg", "hp"];', 'var COLUMNS = ["name", "wt", "mpg", "hp", "cyl"];')))
R$L5 = list(
  shiny_a = list(e('textOutput(ns("value")))', 'textOutput(ns("value")), textOutput(ns("low")))'),
                 e('output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))',
                   'output$value = renderText(paste("Stock value:", money(sum(inv()$price * inv()$stock))))\n    output$low = renderText(paste("Low stock:", paste(inv()$product[inv()$stock < 50], collapse = ", ")))')),
  shiny_b = list(e('p(textOutput(ns("value"), inline = TRUE))', 'p(textOutput(ns("value"), inline = TRUE)),\n    p(textOutput(ns("low"), inline = TRUE))'),
                 e('paste("Stock value:", format_money(stock_value()))\n    })', 'paste("Stock value:", format_money(stock_value()))\n    })\n\n    output$low = renderText({\n      low = current()$product[current()$stock < 50]\n      paste("Low stock:", paste(low, collapse = ", "))\n    })')),
  html_a = list(e('warehouses.forEach(w => document.getElementById(`${w.id}-value`).textContent = `Stock value: ${money(w.value())}`);',
                  'warehouses.forEach(w => {\n    document.getElementById(`${w.id}-value`).textContent = `Stock value: ${money(w.value())}`;\n    document.getElementById(`${w.id}-low`).textContent = `Low stock: ${w.low().join(", ")}`;\n  });'),
                e('<div class="card-body" id="${id}-value"></div></div>`;', '<div class="card-body"><div id="${id}-value"></div><div id="${id}-low"></div></div></div>`;'),
                e('value: () => rows.reduce((s, r) => s + r.price * r.stock, 0)});', 'value: () => rows.reduce((s, r) => s + r.price * r.stock, 0),\n    low: () => rows.filter(r => r.stock < 50).map(r => r.product)});')),
  html_b = list(e('$root.append($("<p>").attr("id", this.id + "-value"));', '$root.append($("<p>").attr("id", this.id + "-value"));\n        $root.append($("<p>").attr("id", this.id + "-low"));'),
                e('$("#" + this.id + "-value").text("Stock value: " + formatMoney(this.value()));',
                  '$("#" + this.id + "-value").text("Stock value: " + formatMoney(this.value()));\n        var low = this.rows.filter(function (row) { return row.stock < 50; }).map(function (row) { return row.product; });\n        $("#" + this.id + "-low").text("Low stock: " + low.join(", "));')))

count_fixed = function(x, pat) {
  m = gregexpr(pat, x, fixed = TRUE)[[1]]
  if (m[1] == -1) 0L else length(m)
}
rows = list()
for (lv in names(R)) for (impl in names(R[[lv]])) {
  ext = if (startsWith(impl, "shiny")) ".R" else ".html"
  path = file.path(lv, paste0(impl, ext))
  x = paste(readLines(file.path(src, path), warn = FALSE), collapse = "\n")
  y = x
  for (ed in R[[lv]][[impl]]) {
    stopifnot(count_fixed(x, ed$oldText) == 1)          # unique in the ORIGINAL file (Pi semantics)
    y = sub(ed$oldText, ed$newText, y, fixed = TRUE)
  }
  dir.create(file.path(dst, lv), recursive = TRUE, showWarnings = FALSE)
  writeLines(y, file.path(dst, path))
  if (ext == ".R") parse(text = y)
  edit_call = j(list(path = path, edits = R[[lv]][[impl]]))
  write_call = j(list(path = path, content = y))
  rows[[length(rows) + 1]] = data.frame(level = lv, impl, n_edits = length(R[[lv]][[impl]]),
    edit_tok = tok_o200k(edit_call), rewrite_tok = tok_o200k(write_call))
}
d = do.call(rbind, rows)
saveRDS(d, file.path(G2, "a_rev_calls.rds"))
d$rewrite_over_edit = round(d$rewrite_tok / d$edit_tok, 1)
print(d, row.names = FALSE)
d$side = ifelse(startsWith(d$impl, "shiny"), "shiny", "html")
s = aggregate(cbind(edit_tok, rewrite_tok) ~ level + side, d, mean)
s = reshape(s, idvar = "level", timevar = "side", direction = "wide")
s$edit_html_over_shiny = round(s$edit_tok.html / s$edit_tok.shiny, 2)
s$rewrite_html_over_shiny = round(s$rewrite_tok.html / s$rewrite_tok.shiny, 2)
cat("\nMean per side (o200k output tokens of the tool-call arguments):\n")
print(s, row.names = FALSE)
cat(sprintf("\nAll levels: edit total shiny %d vs html %d (x%.2f); rewrite total shiny %d vs html %d (x%.2f)\n",
            sum(d$edit_tok[d$side == "shiny"]), sum(d$edit_tok[d$side == "html"]),
            sum(d$edit_tok[d$side == "html"]) / sum(d$edit_tok[d$side == "shiny"]),
            sum(d$rewrite_tok[d$side == "shiny"]), sum(d$rewrite_tok[d$side == "html"]),
            sum(d$rewrite_tok[d$side == "html"]) / sum(d$rewrite_tok[d$side == "shiny"])))
cat(sprintf("Rewrite / edit: shiny %.1fx, html %.1fx (sum over levels)\n",
            sum(d$rewrite_tok[d$side == "shiny"]) / sum(d$edit_tok[d$side == "shiny"]),
            sum(d$rewrite_tok[d$side == "html"]) / sum(d$edit_tok[d$side == "html"])))
````

**`G2/out/a_revisions.txt`**

````text
 level    impl n_edits edit_tok rewrite_tok rewrite_over_edit
    L1 shiny_a       1      116         242               2.1
    L1 shiny_b       2      108         276               2.6
    L1  html_a       4      179         452               2.5
    L1  html_b       4      209         563               2.7
    L2 shiny_a       1       35         204               5.8
    L2 shiny_b       1       43         312               7.3
    L2  html_a       1       54         488               9.0
    L2  html_b       1       45         664              14.8
    L3 shiny_a       2      132         460               3.5
    L3 shiny_b       3      152         700               4.6
    L3  html_a       2      140        1296               9.3
    L3  html_b       2      168        1702              10.1
    L4 shiny_a       1       59         246               4.2
    L4 shiny_b       2      115         440               3.8
    L4  html_a       2       99         700               7.1
    L4  html_b       1       64        1019              15.9
    L5 shiny_a       2      136         433               3.2
    L5 shiny_b       2      149         728               4.9
    L5  html_a       3      265         713               2.7
    L5  html_b       2      208        1100               5.3

Mean per side (o200k output tokens of the tool-call arguments):
 level edit_tok.html rewrite_tok.html edit_tok.shiny rewrite_tok.shiny
    L1         194.0            507.5          112.0             259.0
    L2          49.5            576.0           39.0             258.0
    L3         154.0           1499.0          142.0             580.0
    L4          81.5            859.5           87.0             343.0
    L5         236.5            906.5          142.5             580.5
 edit_html_over_shiny rewrite_html_over_shiny
                 1.73                    1.96
                 1.27                    2.23
                 1.08                    2.58
                 0.94                    2.51
                 1.66                    1.56

All levels: edit total shiny 1045 vs html 1431 (x1.37); rewrite total shiny 4041 vs html 8697 (x2.15)
Rewrite / edit: shiny 3.9x, html 6.1x (sum over levels)
````

**`G2/out/a_check_revised.txt`**

````text
L1 shiny_a  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.1s)
L1 shiny_b  parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (1.0s)
L1 html_a   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L1 html_b   parse=ok http200=TRUE steps=2/2 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L2 shiny_a  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.3s)
L2 shiny_b  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.8s)
L2 html_a   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.6s)
L2 html_b   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.6s)
L3 shiny_a  parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (1.8s)
L3 shiny_b  parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (2.0s)
L3 html_a   parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L3 html_b   parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L4 shiny_a  parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (2.0s)
L4 shiny_b  parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (2.5s)
L4 html_a   parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (1.1s)
L4 html_b   parse=ok http200=TRUE steps=4/4 js_err=0 out_err=0 log_err=0 => PASS (1.1s)
L5 shiny_a  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.4s)
L5 shiny_b  parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (1.2s)
L5 html_a   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.3s)
L5 html_b   parse=ok http200=TRUE steps=3/3 js_err=0 out_err=0 log_err=0 => PASS (0.2s)
[1] TRUE

PASS 20 of 20 apps
````

**`G2/a_tokens.R`**

````r
# G2 (a): token cost of the 20 verified apps, growth over complexity, and data transfer cost.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
A = file.path(G2, "a_apps")
source(file.path(A, "data.R"))
rows = list()
for (lv in paste0("L", 1:5)) for (impl in c("shiny_a", "shiny_b", "html_a", "html_b")) {
  f = file.path(A, lv, paste0(impl, if (startsWith(impl, "shiny")) ".R" else ".html"))
  x = paste(readLines(f, warn = FALSE), collapse = "\n")
  rows[[length(rows) + 1]] = data.frame(level = lv, impl, lines = length(strsplit(x, "\n")[[1]]),
    chars = nchar(x), o200k = tok_o200k(x), cl100k = tok_cl100k(x),
    as_write_arg = tok_o200k(j(list(path = basename(f), content = x))))
}
d = do.call(rbind, rows)
d$side = ifelse(startsWith(d$impl, "shiny"), "shiny", "html")
print(d[, c("level", "impl", "lines", "chars", "o200k", "cl100k", "as_write_arg")], row.names = FALSE)

cat("\nPer level: mean of the two implementations per side (o200k), ratio html/shiny, and the range over\n")
cat("the four cross pairs (html_x / shiny_y):\n")
for (lv in unique(d$level)) {
  s = d$o200k[d$level == lv & d$side == "shiny"]; h = d$o200k[d$level == lv & d$side == "html"]
  sw = d$as_write_arg[d$level == lv & d$side == "shiny"]; hw = d$as_write_arg[d$level == lv & d$side == "html"]
  pairs = as.vector(outer(h, s, "/"))
  cat(sprintf("  %s shiny %6.1f  html %6.1f  ratio %.2f  pair range %.2f-%.2f | as write-call argument: ratio %.2f\n",
              lv, mean(s), mean(h), mean(h) / mean(s), min(pairs), max(pairs), mean(hw) / mean(sw)))
}
tot = aggregate(cbind(o200k, cl100k, as_write_arg) ~ side, d, sum)
print(tot, row.names = FALSE)
cat(sprintf("Overall html/shiny: o200k %.2f, cl100k %.2f, as write-call argument %.2f\n",
            tot$o200k[tot$side == "html"] / tot$o200k[tot$side == "shiny"],
            tot$cl100k[tot$side == "html"] / tot$cl100k[tot$side == "shiny"],
            tot$as_write_arg[tot$side == "html"] / tot$as_write_arg[tot$side == "shiny"]))
cat(sprintf("Tokenizer agreement: cl100k/o200k per file median %.3f (range %.3f-%.3f)\n",
            median(d$cl100k / d$o200k), min(d$cl100k / d$o200k), max(d$cl100k / d$o200k)))
cat(sprintf("JSON escaping in a write call: +%.1f%% shiny, +%.1f%% html (median over files)\n",
            100 * median(d$as_write_arg[d$side == "shiny"] / d$o200k[d$side == "shiny"] - 1),
            100 * median(d$as_write_arg[d$side == "html"] / d$o200k[d$side == "html"] - 1)))

cat("\nGrowth curve (mean o200k per side by level index 1..5; least-squares slope per level):\n")
g = aggregate(o200k ~ level + side, d, mean)
g$k = as.integer(sub("L", "", g$level))
for (sd in c("shiny", "html")) {
  gg = g[g$side == sd, ]
  fit = lm(o200k ~ k, gg)
  cat(sprintf("  %-5s %s | slope %.0f tokens/level, intercept %.0f\n", sd,
              paste(sprintf("%.0f", gg$o200k[order(gg$k)]), collapse = " -> "), coef(fit)[2], coef(fit)[1]))
}

cat("\nData transfer: what the model must emit/receive for the data (o200k)\n")
desc = function(df) paste0(deparse(substitute(df)), " <data.frame ", nrow(df), " x ", ncol(df), ">: ",
  paste(sprintf("%s %s", names(df), vapply(df, function(v) class(v)[1], "")), collapse = ", "))
show = function(label, df, name) {
  jr = j(df); jc = as.character(jsonlite::toJSON(df, dataframe = "columns", digits = NA))
  csv = paste(capture.output(write.csv(df, stdout(), row.names = FALSE)), collapse = "\n")
  ds = sprintf("%s <data.frame %d x %d>: %s", name, nrow(df), ncol(df),
               paste(sprintf("%s %s", names(df), vapply(df, function(v) class(v)[1], "")), collapse = ", "))
  cat(sprintf("  %-22s rows-JSON %7d | columns-JSON %7d | CSV %7d | name %d | name + schema line %d\n",
              label, tok_o200k(jr), tok_o200k(jc), tok_o200k(csv), tok_o200k(name), tok_o200k(ds)))
}
show("sales (5000 x 5)", sales, "sales")
show("sales[1:1000, ]", sales[1:1000, ], "sales")
show("sales[1:100, ]", sales[1:100, ], "sales")
show("cars_df (32 x 12)", cars_df, "cars_df")
show("inv_a + inv_b (16 x 3)", rbind(inv_a, inv_b), "inv_a")
big = sales[rep(seq_len(nrow(sales)), 10), ]
cat(sprintf("  %-22s rows-JSON %7d (linear in rows: %.1f tokens/row)\n", "sales x10 (50000 x 5)",
            tok_o200k(j(big)), tok_o200k(j(big)) / nrow(big)))
````

**`G2/out/a_tokens.txt`**

````text
 level    impl lines chars o200k cl100k as_write_arg
    L1 shiny_a    20   554   159    157          202
    L1 shiny_b    25   725   197    196          242
    L1  html_a    31  1150   356    349          415
    L1  html_b    45  1580   447    437          523
    L2 shiny_a    20   561   162    161          202
    L2 shiny_b    38   855   233    232          300
    L2  html_a    36  1381   410    395          476
    L2  html_b    57  1900   564    561          665
    L3 shiny_a    34  1268   348    349          421
    L3 shiny_b    69  1917   526    525          656
    L3  html_a    69  3623  1079   1051         1234
    L3  html_b   119  4872  1417   1402         1646
    L4 shiny_a    20   682   194    194          240
    L4 shiny_b    49  1235   345    343          430
    L4  html_a    46  1888   584    567          687
    L4  html_b    95  3115   839    823         1013
    L5 shiny_a    40  1205   320    320          388
    L5 shiny_b    74  1935   530    530          662
    L5  html_a    45  1803   542    525          635
    L5  html_b    90  3055   838    827         1012

Per level: mean of the two implementations per side (o200k), ratio html/shiny, and the range over
the four cross pairs (html_x / shiny_y):
  L1 shiny  178.0  html  401.5  ratio 2.26  pair range 1.81-2.81 | as write-call argument: ratio 2.11
  L2 shiny  197.5  html  487.0  ratio 2.47  pair range 1.76-3.48 | as write-call argument: ratio 2.27
  L3 shiny  437.0  html 1248.0  ratio 2.86  pair range 2.05-4.07 | as write-call argument: ratio 2.67
  L4 shiny  269.5  html  711.5  ratio 2.64  pair range 1.69-4.32 | as write-call argument: ratio 2.54
  L5 shiny  425.0  html  690.0  ratio 1.62  pair range 1.02-2.62 | as write-call argument: ratio 1.57
  side o200k cl100k as_write_arg
  html  7076   6937         8306
 shiny  3014   3007         3743
Overall html/shiny: o200k 2.35, cl100k 2.31, as write-call argument 2.22
Tokenizer agreement: cl100k/o200k per file median 0.992 (range 0.963-1.003)
JSON escaping in a write call: +24.7% shiny, +17.1% html (median over files)

Growth curve (mean o200k per side by level index 1..5; least-squares slope per level):
  shiny 178 -> 198 -> 437 -> 270 -> 425 | slope 57 tokens/level, intercept 132
  html  402 -> 487 -> 1248 -> 712 -> 690 | slope 80 tokens/level, intercept 467

Data transfer: what the model must emit/receive for the data (o200k)
  sales (5000 x 5)       rows-JSON  127113 | columns-JSON   72125 | CSV   77122 | name 1 | name + schema line 25
  sales[1:1000, ]        rows-JSON   25420 | columns-JSON   14432 | CSV   15429 | name 1 | name + schema line 25
  sales[1:100, ]         rows-JSON    2546 | columns-JSON    1458 | CSV    1555 | name 1 | name + schema line 24
  cars_df (32 x 12)      rows-JSON    2056 | columns-JSON    1157 | CSV    1181 | name 2 | name + schema line 48
  inv_a + inv_b (16 x 3) rows-JSON     239 | columns-JSON     149 | CSV     162 | name 2 | name + schema line 19
  sales x10 (50000 x 5)  rows-JSON 1651123 (linear in rows: 33.0 tokens/row)
````

### 5.3 Shared helper and part (b): presets, wire formats, MCP and skills catalogs

**`G2/tok.R`**

````r
# G2 shared helpers: token counting with rtiktoken (oracle) and the proposed estimator.
# House style: "=" for assignment, "|>" for pipes.
G2 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2"
RLIB = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))
suppressPackageStartupMessages(library(rtiktoken))

# rtiktoken 0.0.7 rebuilds its BPE encoder on every call (about 0.3-0.4 s per call on this machine,
# independent of text length), so counts are memoised in an on-disk cache keyed by a hash of the text.
.tokcache_file = file.path(G2, "tokcache.rds")
.tokcache = if (file.exists(.tokcache_file)) readRDS(.tokcache_file) else new.env(hash = TRUE)
reg.finalizer(environment(), function(e) saveRDS(.tokcache, .tokcache_file), onexit = TRUE)
tok_count = function(x, enc) {
  x = enc2utf8(paste(x, collapse = "\n"))
  if (!nzchar(x)) return(0L)
  key = paste0(enc, ":", rlang::hash(x))
  v = .tokcache[[key]]
  if (is.null(v)) {
    v = get_token_count(x, enc)
    assign(key, v, envir = .tokcache)
  }
  v
}
tok_o200k = function(x) tok_count(x, "o200k_base")
tok_cl100k = function(x) tok_count(x, "cl100k_base")
tok_save = function() saveRDS(.tokcache, .tokcache_file)
chars = function(x) nchar(paste(x, collapse = "\n"), "chars")
j = function(x, pretty = FALSE) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = pretty))
}
fmt_row = function(...) cat(sprintf(...), "\n", sep = "")
````

**`G2/b_defs.R`**

````r
# G2 (b) tool definitions and prompt builders shared by b_presets.R and d_compose.R.
# Tool definitions are provider-neutral lists: list(name, description, parameters [JSON Schema]).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
P01 = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto"
local({
  owd = setwd(P01); on.exit(setwd(owd))
  for (f in c("00-utils.R", "01-read-write.R", "02-edit.R", "03-search.R", "04-run.R", "05-registry.R")) {
    sys.source(f, envir = globalenv())
  }
})
T01 = builtin_tools(shell = list(name = "bash"))
tool = function(name, description, parameters) list(name = name, description = description, parameters = parameters)
from01 = function(n) tool(T01[[n]]$name, T01[[n]]$description, T01[[n]]$parameters)
obj = function(props, required = character()) {
  o = list(type = "object", properties = props)
  if (length(required)) o$required = I(required)
  o
}
str_ = function(d) list(type = "string", description = d)
num_ = function(d) list(type = "number", description = d)
bool_ = function(d) list(type = "boolean", description = d)

# ---- Pi (verbatim descriptions and schemas, report 01 sections 3.2-3.8) ----
pi_tools = list(
  read = tool("read", "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
              obj(list(path = str_("Path to the file to read (relative or absolute)"), offset = num_("Line number to start reading from (1-indexed)"),
                       limit = num_("Maximum number of lines to read")), "path")),
  bash = tool("bash", "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
              obj(list(command = str_("Shell command to execute"), timeout = num_("Timeout in seconds (optional, no default timeout)")), "command")),
  edit = from01("edit"),     # identical to Pi's edit (report 01 section 3.4)
  write = from01("write"))   # identical to Pi's write (report 01 section 3.3)

# ---- gptr tools ----
r_tool = tool("r", "Run R code in the user's live R session. Objects you create persist in the user's workspace (by default the environment gptr() was called from) and are visible to later calls and to the user. Returns printed output, messages, warnings, errors (with a traceback) and plots (as images). Execution stops at the first error. Output is truncated to the first 40% and last 60% of 2000 lines / 50000 characters; the full text is saved to a temp file whose path is given. Rules: work in small steps; never re-load data that is already in memory; return values implicitly (write `x`, not `print(x)`) and prefer head()/str()-sized summaries; never call q(), quit(), readline(), menu(), browser() or install packages unless the user asked; to hand an R object back as the result of the request call gptr_return(obj).",
              obj(list(code = str_("R code to evaluate. May contain several expressions."),
                       timeout = num_("Seconds (best effort: long-running C code cannot be interrupted). Default 300.")), "code"))
r_lean = tool("r", "Evaluate R code in the user's live R session; objects persist and are shared with the user. Returns output, messages, warnings, errors and plots (images); long output is cut (head+tail) with the full text in a spill file.",
              obj(list(code = str_("R code; several expressions allowed.")), "code"))
r_inspect = tool("r_inspect", "Describe objects in the live session and look up R documentation without running code (read-only, allowed in plan mode, never needs approval).",
                 obj(list(action = list(type = "string", enum = I(c("objects", "describe", "help", "search", "package", "vignette", "session")), description = "What to inspect"),
                          name = str_("Object name, help topic, package or search pattern"), package = str_("Package for help/vignette lookups"),
                          max_chars = num_("Upper bound on returned characters (default 4000)")), "action"))
ask = tool("ask", "Ask the user one to four questions and wait for the answers. Use it when a decision materially changes the result (which object, which method, which output format) and you cannot infer the answer from the session or files. Prefer options the user can pick; the user can always type their own answer instead. Do not use it for permission to run code: the harness asks for permission itself.",
           list(type = "object", additionalProperties = FALSE, required = I("questions"),
                properties = list(questions = list(type = "array", minItems = 1, maxItems = 4, items = list(
                  type = "object", additionalProperties = FALSE, required = I(c("id", "question")),
                  properties = list(id = str_("Short stable key for the answer, e.g. 'format'"),
                                    header = list(type = "string", maxLength = 16, description = "Very short label, e.g. 'Format'"),
                                    question = str_("The full question shown to the user"),
                                    type = list(type = "string", enum = I(c("single", "multi", "text")), description = "single = pick one option, multi = pick any number, text = free text"),
                                    options = list(type = "array", maxItems = 9, items = list(type = "object", additionalProperties = FALSE, required = I("label"),
                                                   properties = list(label = list(type = "string"), description = list(type = "string")))),
                                    allow_other = bool_("Let the user type an answer that is not an option (default true)"),
                                    default = str_("Label (or text) used if the user just presses Enter")))))))
agent = tool("agent", "Delegate a self-contained task to a sub-agent with its own context, model and tools. The sub-agent reads the parent's session objects; its final answer (and an R value when `returns` is given) comes back as the result. Use for parallel or specialised work; do not delegate trivial steps.",
             obj(list(description = str_("3-7 word summary shown to the user"), prompt = str_("The full task for the sub-agent"),
                      agent_type = str_("Name of a defined agent (optional)"), model = str_("Model id or alias (optional)"),
                      background = bool_("Run in the background and notify on completion (default false)"),
                      returns = list(type = "object", description = "JSON Schema of an R value to return (optional)")), c("description", "prompt")))
artifact = tool("artifact", "Create or revise an interactive Shiny app (an artifact) that the user sees in their viewer or browser. The app runs in a separate R process. Objects named in `data` are copied (snapshotted) from the user's live R session and exist in app.R under the same names. Write ONE app.R that ends with shinyApp(ui, server). The result reports the URL, validation errors, and a screenshot of the running app.",
                list(type = "object", required = I(character()), properties = list(
                  title = str_("Short human-readable title (new artifacts)."),
                  code = str_("Complete app.R source. Required for a new artifact; for a revision either `code` or `edits`."),
                  edits = list(type = "array", description = "Revisions only: exact-match replacements applied to the current app.R.",
                               items = list(type = "object", properties = list(old_text = list(type = "string"), new_text = list(type = "string")), required = I(c("old_text", "new_text")))),
                  data = list(type = "array", items = list(type = "string"), description = "Names of objects in the user's R session to ship into the app (small data frames or summaries, not huge objects)."),
                  id = str_("Existing artifact id to revise. Omit to create a new artifact."),
                  kind = list(type = "string", enum = I(c("shiny", "html")), default = "shiny", description = "Use 'html' only when a raw HTML/JS page is truly required; the data is then available as window.GPTR_DATA.<name> (column-oriented JSON)."),
                  screenshot = list(type = "boolean", default = TRUE))))
lark = "start: begin_patch hunk+ end_patch\nbegin_patch: \"*** Begin Patch\" LF\nend_patch: \"*** End Patch\" LF?\n\nhunk: add_hunk | delete_hunk | update_hunk\nadd_hunk: \"*** Add File: \" filename LF add_line+\ndelete_hunk: \"*** Delete File: \" filename LF\nupdate_hunk: \"*** Update File: \" filename LF change_move? change?\n\nfilename: /(.+)/\nadd_line: \"+\" /(.*)/ LF -> line\n\nchange_move: \"*** Move to: \" filename LF\nchange: (change_context | change_line)+ eof_line?\nchange_context: (\"@@\" | \"@@ \" /(.+)/) LF\nchange_line: (\"+\" | \"-\" | \" \") /(.*)/ LF\neof_line: \"*** End of File\" LF\n\n%import common.LF\n"
apply_patch_custom = list(type = "custom", name = "apply_patch",
  description = "The `apply_patch` tool can be used to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON.",
  format = list(type = "grammar", syntax = "lark", definition = lark))
apply_patch_fn = tool("apply_patch", "Edit files with a patch in the *** Begin Patch / *** End Patch envelope (Add File, Update File with @@ context and +/- lines, Delete File, Move to).",
                      obj(list(patch = str_("The full patch text")), "patch"))

gptr_tools = list(read = from01("read"), r = r_tool, edit = from01("edit"), write = from01("write"),
                  grep = from01("grep"), find = from01("find"), ls = from01("ls"),
                  r_inspect = r_inspect, ask = ask, agent = agent, artifact = artifact)
snippets = c(read = "Read file contents", r = "Evaluate R code in the live session (objects persist; plots are returned as images)",
             edit = "Make precise file edits with exact text replacement, including multiple disjoint edits in one call",
             write = "Create or overwrite files", grep = "Search file contents for patterns (respects .gitignore)",
             find = "Find files by glob pattern (respects .gitignore)", ls = "List directory contents",
             r_inspect = "Describe objects and look up R help without running code", ask = "Ask the user a question",
             agent = "Delegate a task to a sub-agent", artifact = "Create or revise a Shiny app artifact",
             apply_patch = "Edit files with a patch envelope", bash = "Execute bash commands (ls, grep, find, etc.)")

# ---- system prompts ----
rd = function(f) paste(readLines(file.path(G2, "prompts", f), warn = FALSE), collapse = "\n")
pi_prompt = rd("pi_default.txt")
pi_prompt_nodocs = sub("<docs>.*</docs>\n\n", "", pi_prompt)
gptr_prompt = function(tools, r_perf = TRUE, artifacts = FALSE, extra = NULL, cwd = "/Users/me/project") {
  rules = c("Use read to examine files instead of readLines() or cat() in r.",
            if ("r" %in% tools) c("Use r for computation and data inspection in the live session; do not shell out for things R can do",
                                  "Objects created with r stay in the user's session: do not re-load data that is already in memory, and print compact summaries (str(), head(), dim()) rather than whole objects"),
            if ("edit" %in% tools) T01$edit$promptGuidelines,
            if ("write" %in% tools) "Use write only for new files or complete rewrites.",
            "Be concise in your responses", "Show file paths clearly when working with files")
  txt = paste0("You are an expert R programming and data analysis assistant operating inside gptr, an agent harness that runs inside the user's live R session. You help users by inspecting and computing on the objects in their session, reading files, editing code, and writing new files.\n\n",
               "<tools>\n", paste(sprintf("- %s: %s", tools, snippets[tools]), collapse = "\n"),
               "\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.\n</tools>\n\n",
               "<rules>\n", paste("-", rules, collapse = "\n"), "\n</rules>")
  if (r_perf) txt = paste0(txt, "\n\n", rd("r_performance.txt"))
  if (artifacts) txt = paste0(txt, "\n\n<artifacts>\n", rd("artifacts.txt"), "\n</artifacts>")
  if (!is.null(extra)) txt = paste0(txt, "\n\n", extra)
  paste0(txt, "\n\n<cwd>\n", cwd, "\n</cwd>")
}

# ---- provider wire formats (the request fields a preset contributes) ----
strictify = function(s) {                         # OpenAI strict mode: every property required, optional ones nullable
  if (!is.list(s)) return(s)
  if (identical(s$type, "object") && !is.null(s$properties)) {
    req = unlist(s$required)
    for (p in names(s$properties)) {
      s$properties[[p]] = strictify(s$properties[[p]])
      if (!(p %in% req) && !is.null(s$properties[[p]]$type)) s$properties[[p]]$type = I(c(s$properties[[p]]$type, "null"))
    }
    s$required = I(names(s$properties)); s$additionalProperties = FALSE
  }
  if (identical(s$type, "array") && !is.null(s$items)) s$items = strictify(s$items)
  s
}
wire = function(tools, system, provider, namespace = NULL, strict = FALSE, extra_tools = list()) {
  if (provider == "anthropic") {
    body = list(system = system, tools = c(lapply(tools, function(t) list(name = t$name, description = t$description, input_schema = t$parameters)), extra_tools))
  } else if (provider == "responses") {
    fns = lapply(tools, function(t) {
      f = list(type = "function", name = t$name, description = t$description, parameters = if (strict) strictify(t$parameters) else t$parameters)
      if (strict) f$strict = TRUE
      f
    })
    fns = c(fns, extra_tools)
    if (!is.null(namespace)) fns = list(list(type = "namespace", name = namespace, description = "Tools acting on the user's live R session.", tools = fns))
    body = list(instructions = system, tools = fns)
  } else if (provider == "chat") {
    body = list(messages = list(list(role = "system", content = system)),
                tools = lapply(tools, function(t) list(type = "function", `function` = list(name = t$name, description = t$description, parameters = t$parameters))))
  } else if (provider == "gemini") {
    body = list(systemInstruction = list(parts = list(list(text = system))),
                tools = list(list(functionDeclarations = lapply(tools, function(t) list(name = t$name, description = t$description, parametersJsonSchema = t$parameters)))))
  }
  j(body)
}
````

**`G2/b_presets.R`**

````r
# G2 (b): fixed per-request prefix cost (system prompt + tool declarations) per preset and provider wire format.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
presets = list(
  "pi-4 (Pi default, with <docs>)" = list(tools = pi_tools, system = pi_prompt),
  "pi-4 (no <docs>)" = list(tools = pi_tools, system = pi_prompt_nodocs),
  "gptr-4 read,r,edit,write" = list(tools = gptr_tools[c("read", "r", "edit", "write")], system = gptr_prompt(c("read", "r", "edit", "write"))),
  "gptr-7 (+grep,find,ls)" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"))),
  "gptr-7 without <r_performance>" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"), r_perf = FALSE)),
  "gptr-10 (+r_inspect,ask,agent)" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls", "r_inspect", "ask", "agent")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls", "r_inspect", "ask", "agent"))),
  "gptr-11 (+artifact, <artifacts>)" = list(tools = gptr_tools, system = gptr_prompt(names(gptr_tools), artifacts = TRUE)),
  "gptr-7 apply_patch (no edit/write)" = list(tools = c(gptr_tools[c("read", "r", "grep", "find", "ls")], list(apply_patch = apply_patch_fn)), system = gptr_prompt(c("read", "r", "grep", "find", "ls", "apply_patch")), patch = TRUE),
  "gptr-lean-4 (short r, no r_perf)" = list(tools = list(read = gptr_tools$read, r = r_lean, edit = gptr_tools$edit, write = gptr_tools$write), system = gptr_prompt(c("read", "r", "edit", "write"), r_perf = FALSE)))

cat("Per-tool declaration cost (Anthropic shape, o200k):\n")
all_tools = c(pi_tools["bash"], gptr_tools, list(r_lean = r_lean, apply_patch_fn = apply_patch_fn))
pt = vapply(all_tools, function(t) tok_o200k(j(list(name = t$name, description = t$description, input_schema = t$parameters))), 1)
print(pt)
cat(sprintf("apply_patch as Responses custom grammar tool: %d\n", tok_o200k(j(apply_patch_custom))))
cat(sprintf("<r_performance> section: %d; <artifacts> section: %d; Pi <docs> section: %d\n\n",
            tok_o200k(rd("r_performance.txt")), tok_o200k(rd("artifacts.txt")), tok_o200k(pi_prompt) - tok_o200k(pi_prompt_nodocs)))

res = list()
for (nm in names(presets)) {
  p = presets[[nm]]
  row = data.frame(preset = nm, n_tools = length(p$tools), system = tok_o200k(p$system))
  for (pv in c("anthropic", "responses", "chat", "gemini")) {
    tl = p$tools; extra = list()
    if (isTRUE(p$patch) && pv == "responses") { tl = tl[names(tl) != "apply_patch"]; extra = list(apply_patch_custom) }
    row[[pv]] = tok_o200k(wire(tl, p$system, pv, extra_tools = extra))
  }
  tl = p$tools
  if (isTRUE(p$patch)) tl = tl[names(tl) != "apply_patch"]
  row$resp_ns = tok_o200k(wire(tl, p$system, "responses", namespace = "gptr", extra_tools = if (isTRUE(p$patch)) list(apply_patch_custom) else list()))
  row$resp_strict = tok_o200k(wire(tl, p$system, "responses", strict = TRUE, extra_tools = if (isTRUE(p$patch)) list(apply_patch_custom) else list()))
  res[[nm]] = row
}
d = do.call(rbind, res)
cat("Prefix tokens (o200k) = system prompt + tools, serialised as each provider's request fields:\n")
print(d, row.names = FALSE)
cat("\nAnthropic adds a fixed tool-use system prompt when tools are present (286 tokens on Opus/Sonnet 5.5, report 07 section 2.1);\n")
cat("the JSON above is the payload proxy, not the provider's internal rendering.\n")
````

**`G2/out/b_presets.txt`**

````text
Per-tool declaration cost (Anthropic shape, o200k):
          bash           read              r           edit          write 
           110            153            254            239             85 
          grep           find             ls      r_inspect            ask 
           233            178             96            143            335 
         agent       artifact         r_lean apply_patch_fn 
           199            350             88             71 
apply_patch as Responses custom grammar tool: 252
<r_performance> section: 406; <artifacts> section: 360; Pi <docs> section: 248

Prefix tokens (o200k) = system prompt + tools, serialised as each provider's request fields:
                             preset n_tools system anthropic responses chat
     pi-4 (Pi default, with <docs>)       4    547      1175      1187 1204
                   pi-4 (no <docs>)       4    299       919       931  948
           gptr-4 read,r,edit,write       4    767      1544      1556 1573
             gptr-7 (+grep,find,ls)       7    804      2096      2117 2140
     gptr-7 without <r_performance>       7    398      1675      1696 1719
     gptr-10 (+r_inspect,ask,agent)      10    840      2816      2846 2876
   gptr-11 (+artifact, <artifacts>)      11   1221      3570      3603 3635
 gptr-7 apply_patch (no edit/write)       6    671      1705      1900 1744
   gptr-lean-4 (short r, no r_perf)       4    361       957       969  986
 gemini resp_ns resp_strict
   1192    1211        1240
    936     955         984
   1561    1580        1609
   2116    2141        2253
   1695    1720        1832
   2839    2870        3070
   3594    3627        3877
   1724    1924        2014
    974     993        1017

Anthropic adds a fixed tool-use system prompt when tools are present (286 tokens on Opus/Sonnet 5.5, report 07 section 2.1);
the JSON above is the payload proxy, not the provider's internal rendering.
````

**`G2/b_lean.R`**

````r
# G2 (b): how small can the default 7-tool prefix get without dropping a capability?
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
lean = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
lean$r = r_lean
lean$read$description = "Read a text file or an image. Text is capped at 2000 lines / 50 KB; continue with offset/limit (lines)."
lean$grep$description = "Search file contents (PCRE or literal); returns path:line: text; respects .gitignore; at most 100 matches by default."
lean$find$description = "Find files by glob (respects .gitignore); sort by path, mtime or size."
lean$ls$description = "List a directory; directories end with '/'."
lean$write$description = "Create or overwrite a file (parent directories are created)."
lean$edit$description = "Exact-text replacements in one file: each edits[].oldText must match once in the original file; edits must not overlap."
for (k in c("read", "grep", "find", "ls", "edit", "write")) {        # drop per-property prose that repeats the description
  pr = lean[[k]]$parameters$properties
  for (p in names(pr)) if (!is.null(pr[[p]]$description) && nchar(pr[[p]]$description) > 60) pr[[p]]$description = sub("^(.{0,57}[^ ]*).*$", "\\1", pr[[p]]$description)
  lean[[k]]$parameters$properties = pr
}
r_perf_short = "<r_performance>\nObjects in memory are the asset: never reload data; print str()/head(), never whole big objects; compose several steps in one r call and print only the result; data.table/duckdb/arrow for big data; ask before installing packages. Details: skill high-performance-r.\n</r_performance>"
sys_lean = paste0("You are gptr, an agent inside the user's live R session. Objects you create persist for the user.\n\n<tools>\n",
                  paste(sprintf("- %s: %s", names(lean), snippets[names(lean)]), collapse = "\n"),
                  "\n</tools>\n\n<rules>\n- Use r for computation; compose several steps in one call and print compact results.\n- Use edit for precise changes (one call, several edits[]); write only for new files or full rewrites.\n- Be concise; name the objects and files you create.\n</rules>\n\n", r_perf_short, "\n\n<cwd>\n/Users/me/project\n</cwd>")
full = wire(gptr_tools[names(lean)], gptr_prompt(names(lean)), "anthropic")
lw = wire(lean, sys_lean, "anthropic")
cat(sprintf("gptr-7 as specified by reports 01/12/19: %d o200k tokens (system %d)\n", tok_o200k(full), tok_o200k(gptr_prompt(names(lean)))))
cat(sprintf("gptr-7 lean rewrite (same tools and parameters): %d o200k tokens (system %d); saving %.0f%%\n",
            tok_o200k(lw), tok_o200k(sys_lean), 100 * (1 - tok_o200k(lw) / tok_o200k(full))))
for (pv in c("responses", "chat", "gemini")) cat(sprintf("  %-9s full %d | lean %d\n", pv, tok_o200k(wire(gptr_tools[names(lean)], gptr_prompt(names(lean)), pv)), tok_o200k(wire(lean, sys_lean, pv))))
tok_save()
````

**`G2/out/b_lean.txt`**

````text
gptr-7 as specified by reports 01/12/19: 2096 o200k tokens (system 804)
gptr-7 lean rewrite (same tools and parameters): 1153 o200k tokens (system 258); saving 45%
  responses full 2117 | lean 1174
  chat      full 2140 | lean 1197
  gemini    full 2116 | lean 1173
````

**`G2/b_catalogs.R`**

````r
# G2 (b): MCP tool exposure (direct vs R-signature "code exposure" vs names/deferred) at 0/10/50 tools,
# and skills catalogs at 10/40/160 skills.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
rd_json = function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)
gh = lapply(sort(list.files(file.path(G2, "mcp_corpus/github"), full.names = TRUE)), rd_json)
cc = rd_json(file.path(G2, "mcp_corpus/claude_code_tools.json"))
cat(sprintf("Corpora: GitHub MCP server %d tools (commit 85598ba, toolsnaps), Claude Code `claude mcp serve` %d tools\n",
            length(gh), length(cc)))
per_tool = function(tl) vapply(tl, function(t) tok_o200k(j(list(name = t$name, description = t$description, input_schema = t$inputSchema))), 1)
cat(sprintf("Direct declaration per tool (o200k): GitHub median %.0f (p10 %.0f, p90 %.0f); Claude Code median %.0f (p90 %.0f)\n\n",
            median(per_tool(gh)), quantile(per_tool(gh), 0.1), quantile(per_tool(gh), 0.9), median(per_tool(cc)), quantile(per_tool(cc), 0.9)))

sig = function(t, server = "github", max_desc = 120L, desc = TRUE) {
  props = t$inputSchema$properties
  if (is.null(props)) props = list()
  req = unlist(t$inputSchema$required)
  a = vapply(names(props), function(p) {
    ty = props[[p]]$type
    if (is.null(ty)) ty = "any"
    if (is.list(ty)) ty = paste(unlist(ty), collapse = "|")
    if (identical(ty, "array") && !is.null(props[[p]]$items$type)) ty = paste0(props[[p]]$items$type, "[]")
    paste0(p, if (p %in% req) "" else "?", ": ", ty)
  }, "")
  line = sprintf("mcp$%s$%s(%s)", server, t$name, paste(a, collapse = ", "))
  if (desc) {
    d = gsub("\\s+", " ", t$description %||% "")
    d = sub("^(.*?[.!?])\\s.*$", "\\1", d)
    if (nchar(d) > max_desc) d = paste0(substr(d, 1, max_desc - 3), "...")
    line = paste0(line, "  # ", d)
  }
  line
}
catalog = function(tl, server, budget = 3000L, desc = TRUE) {
  head = sprintf("<r_functions>\nMCP tools are R functions; call them inside r and reduce results before printing. mcp_search(\"query\") finds more; mcp_describe(\"%s\", \"tool\") shows a full schema.\n%s:", server, server)
  # budget filled with the harness-side estimator (signature lines are code-like: chars/3.2), as gptr would;
  # the finished catalog is then measured with o200k by the caller
  est = function(x) ceiling(nchar(x) / 3.2)
  lines = character(); used = est(head)
  for (k in seq_along(tl)) {
    l = sig(tl[[k]], server, desc = desc)
    tk = est(l) + 1L
    if (used + tk > budget) { lines = c(lines, sprintf("  (%d more %s tools: use mcp_search())", length(tl) - k + 1L, server)); break }
    lines = c(lines, paste0("  ", l)); used = used + tk
  }
  paste(c(head, lines, "</r_functions>"), collapse = "\n")
}
tool_search_def = tool("tool_search", "Search the deferred tools by keyword; matching tool definitions become callable on the next turn.",
                       obj(list(query = str_("Keywords"), limit = num_("Maximum matches (default 5)")), "query"))
set.seed(42)
ord = sample(length(gh))
rows = list()
for (n in c(0L, 10L, 50L, 125L)) {
  tl = gh[ord[seq_len(n)]]
  direct_a = if (n) tok_o200k(j(lapply(tl, function(t) list(name = t$name, description = t$description, input_schema = t$inputSchema)))) else 0L
  direct_ns = if (n) tok_o200k(j(list(type = "namespace", name = "github", description = "GitHub MCP server",
                                      tools = lapply(tl, function(t) list(type = "function", name = t$name, description = t$description, parameters = t$inputSchema))))) else 0L
  rows[[length(rows) + 1]] = data.frame(corpus = "github", n_tools = n,
    direct_anthropic = direct_a, direct_responses_ns = direct_ns,
    r_catalog_3000 = if (n) tok_o200k(catalog(tl, "github")) else 0L,
    r_catalog_unbounded = if (n) tok_o200k(catalog(tl, "github", budget = 1e6)) else 0L,
    r_sig_no_desc = if (n) tok_o200k(catalog(tl, "github", budget = 1e6, desc = FALSE)) else 0L,
    names_only = if (n) tok_o200k(paste(vapply(tl, `[[`, "", "name"), collapse = ", ")) else 0L,
    deferred_search_tool = if (n) tok_o200k(j(list(name = tool_search_def$name, description = tool_search_def$description, input_schema = tool_search_def$parameters))) else 0L)
}
rows[[length(rows) + 1]] = data.frame(corpus = "claude-code", n_tools = length(cc),
  direct_anthropic = tok_o200k(j(lapply(cc, function(t) list(name = t$name, description = t$description, input_schema = t$inputSchema)))),
  direct_responses_ns = NA, r_catalog_3000 = tok_o200k(catalog(cc, "cc")), r_catalog_unbounded = tok_o200k(catalog(cc, "cc", budget = 1e6)),
  r_sig_no_desc = tok_o200k(catalog(cc, "cc", budget = 1e6, desc = FALSE)),
  names_only = tok_o200k(paste(vapply(cc, `[[`, "", "name"), collapse = ", ")), deferred_search_tool = 58L)
d = do.call(rbind, rows)
cat("MCP exposure cost in the request prefix (o200k):\n")
print(d, row.names = FALSE)
cat("\nExample catalog lines:\n"); cat(head(strsplit(catalog(gh[ord[1:10]], "github"), "\n")[[1]], 6), sep = "\n")
cat(sprintf("\nlast lines of the 50-tool catalog under the 3000-token budget:\n%s\n",
            paste(tail(strsplit(catalog(gh[ord[1:50]], "github"), "\n")[[1]], 3), collapse = "\n")))

tok_save()
````

**`G2/out/b_catalogs.txt`**

````text
Corpora: GitHub MCP server 125 tools (commit 85598ba, toolsnaps), Claude Code `claude mcp serve` 29 tools
Direct declaration per tool (o200k): GitHub median 169 (p10 75, p90 424); Claude Code median 600 (p90 2061)

MCP exposure cost in the request prefix (o200k):
      corpus n_tools direct_anthropic direct_responses_ns r_catalog_3000
      github       0                0                   0              0
      github      10             1591                1638            503
      github      50            11361               11528           2285
      github     125            28534               28926           2285
 claude-code      29            31706                  NA           1672
 r_catalog_unbounded r_sig_no_desc names_only deferred_search_tool
                   0             0          0                    0
                 503           346         43                   67
                2547          1731        214                   67
                6221          4190        566                   67
                1672           890         81                   58

Example catalog lines:
<r_functions>
MCP tools are R functions; call them inside r and reduce results before printing. mcp_search("query") finds more; mcp_describe("github", "tool") shows a full schema.
github:
  mcp$github$get_tag(owner: string, repo: string, tag: string)  # Get details about a specific git tag in a GitHub repository
  mcp$github$search_pull_requests(fields?: string[], order?: string, owner?: string, page?: number, perPage?: number, query: string, repo?: string, sort?: string)  # Search for pull requests in GitHub repositories using issues search syntax already scoped to is:pr
  mcp$github$list_issue_fields(owner: string, repo?: string)  # List issue fields for a repository or organization. Returns field definitions including name, type (text, number, dat...

last lines of the 50-tool catalog under the 3000-token budget:
  mcp$github$get_team_members(org: string, team_slug: string)  # Get member usernames of a specific team in an organization.
  (6 more github tools: use mcp_search())
</r_functions>
````

**`G2/b_skills.R`**

````r
# G2 (b): skills catalogs at 10/40/160 skills in several formats (o200k).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
# ---------------- skills ----------------
# list.files(recursive = TRUE) over the plugin cache walks node_modules trees and took > 30 min here; find(1) takes < 1 s
sk_files = suppressWarnings(system2("find", c(path.expand("~/.claude/plugins/cache"), path.expand("~/.claude/skills"), "-name", "SKILL.md", "-not", "-path", shQuote("*/node_modules/*")), stdout = TRUE, stderr = FALSE))
fm = function(f) {
  x = readLines(f, warn = FALSE, encoding = "UTF-8")
  if (!length(x) || x[1] != "---") return(NULL)
  end = which(x == "---")[2]
  if (is.na(end)) return(NULL)
  y = tryCatch(yaml::yaml.load(paste(x[2:(end - 1)], collapse = "\n")), error = function(e) NULL)
  if (is.null(y$name) || is.null(y$description)) return(NULL)
  data.frame(name = as.character(y$name)[1], description = gsub("\\s+", " ", paste(y$description, collapse = " ")),
             body = paste(x[(end + 1):length(x)], collapse = "\n"))
}
sk = do.call(rbind, lapply(sk_files, fm))
sk = sk[!duplicated(sk$name), ]
cat(sprintf("\nSkills corpus: %d SKILL.md files with valid frontmatter (%d unique names) under ~/.claude\n", length(sk_files), nrow(sk)))
set.seed(3); ib = sample(nrow(sk), 25)
sk$body_tokens = NA; sk$body_tokens[ib] = vapply(sk$body[ib], tok_o200k, 1)
cat(sprintf("Description length: median %.0f chars (p90 %.0f); SKILL.md body (random 25, o200k): median %.0f tokens (p90 %.0f, max %.0f)\n",
            median(nchar(sk$description)), quantile(nchar(sk$description), 0.9), median(sk$body_tokens, na.rm = TRUE),
            quantile(sk$body_tokens, 0.9, na.rm = TRUE), max(sk$body_tokens, na.rm = TRUE)))
esc = function(x) gsub("<", "&lt;", gsub("&", "&amp;", x))
pi_catalog = function(s) paste0("<skills>\nThe following skills provide specialized instructions for specific tasks.\nUse the read tool to load a skill's file when the task matches its description.\nWhen a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n\n<available_skills>\n",
  paste(sprintf("  <skill>\n    <name>%s</name>\n    <description>%s</description>\n    <location>/Users/me/.gptr/skills/%s/SKILL.md</location>\n  </skill>", esc(s$name), esc(s$description), s$name), collapse = "\n"),
  "\n</available_skills>\n</skills>")
compact_catalog = function(s, max_desc = Inf, max_chars = Inf) {
  d = ifelse(nchar(s$description) > max_desc, paste0(substr(s$description, 1, max_desc - 3), "..."), s$description)
  head = "<skills>\nRead ~/.gptr/skills/<name>/SKILL.md when a task matches:\n"
  lines = sprintf("- %s: %s", s$name, d)
  keep = cumsum(nchar(lines) + 1) + nchar(head) <= max_chars
  out = paste0(head, paste(lines[keep], collapse = "\n"))
  if (!all(keep)) out = paste0(out, sprintf("\n(%d more: gptr_skills(\"query\"))", sum(!keep)))
  paste0(out, "\n</skills>")
}
set.seed(7)
so = sample(nrow(sk))
srows = list()
for (n in c(10L, 40L, 160L)) {
  s = sk[so[seq_len(min(n, nrow(sk)))], ]
  srows[[length(srows) + 1]] = data.frame(n_skills = nrow(s), pi_xml = tok_o200k(pi_catalog(s)), compact = tok_o200k(compact_catalog(s)),
    compact_desc250 = tok_o200k(compact_catalog(s, max_desc = 250)),
    pi05_budget_12000chars = tok_o200k(compact_catalog(s, max_desc = 250, max_chars = 12000)),
    budget_3000tok_approx = tok_o200k(compact_catalog(s, max_desc = 160, max_chars = 9000)),
    names_only = tok_o200k(paste(s$name, collapse = ", ")))
}
cat("\nSkills catalog cost in the system prompt (o200k):\n")
print(do.call(rbind, srows), row.names = FALSE)
tok_save()
````

**`G2/out/b_skills.txt`**

````text

Skills corpus: 180 SKILL.md files with valid frontmatter (157 unique names) under ~/.claude
Description length: median 79 chars (p90 558); SKILL.md body (random 25, o200k): median 804 tokens (p90 3803, max 6173)

Skills catalog cost in the system prompt (o200k):
 n_skills pi_xml compact compact_desc250 pi05_budget_12000chars
       10    948     473             305                    305
       40   3727    1981            1346                   1346
      157  14536    7878            5214                   2549
 budget_3000tok_approx names_only
                   252         51
                  1102        213
                  1946        830
````

### 5.4 Part (c): object describers

**`G2/c_describe.R`**

````r
# G2 (c): environment descriptions per object type and budget. Which facts survive per token?
# Describers: report 12's budgeted gptr_describe() (W12/gptr_introspect.R, sourced unchanged),
# report 10's unbounded describer (proto_describe.R), and what the model would get from r("str(x)").
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
suppressPackageStartupMessages({ library(Matrix); library(R6); library(data.table); library(tibble) })
sys.source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/12/gptr_introspect.R", envir = globalenv())
d10 = function(x, name, sample_n = 1000L, max_cols = 30L) {      # report 10 section 5.3, converted to "="
  cls = paste(class(x), collapse = "/")
  sz = if (is.atomic(x) || is.data.frame(x) || isS4(x) || length(x) < 1e5) format(utils::object.size(x), units = "auto") else "?"
  hdr = sprintf("%s <%s> %s", name, cls, sz)
  one_col = function(v) {
    n = length(v)
    s = if (n > sample_n) v[unique(round(seq(1, n, length.out = sample_n)))] else v
    info = if (is.numeric(s)) sprintf("range~[%s, %s]", format(min(s, na.rm = TRUE), digits = 4), format(max(s, na.rm = TRUE), digits = 4))
           else if (is.factor(s)) sprintf("%d levels", nlevels(s))
           else if (is.character(s)) sprintf("e.g. %s", paste(encodeString(utils::head(unique(s), 3), quote = '"'), collapse = ", "))
           else if (inherits(s, "Date")) sprintf("range~[%s, %s]", min(s, na.rm = TRUE), max(s, na.rm = TRUE))
           else ""
    sprintf("%s%s", paste(class(v), collapse = "/"), if (nzchar(info)) paste0(", ", info) else "")
  }
  body = if (is.data.frame(x)) {
    cols = utils::head(names(x), max_cols)
    c(sprintf("  %d rows x %d cols%s", nrow(x), ncol(x), if (ncol(x) > max_cols) sprintf(" (first %d shown)", max_cols) else ""),
      sprintf("  $ %s: %s", cols, vapply(x[cols], one_col, "")))
  } else if (isS4(x)) {
    sprintf("  S4 slots: %s", paste(utils::head(methods::slotNames(x), 20), collapse = ", "))
  } else if (is.function(x)) {
    sprintf("  function(%s)", paste(names(formals(x)), collapse = ", "))
  } else if (is.list(x)) {
    c(sprintf("  list of %d", length(x)),
      sprintf("  $ %s: %s", utils::head(names(x) %||% seq_along(x), 10), vapply(utils::head(x, 10), function(el) paste(class(el), collapse = "/"), "")))
  } else if (is.atomic(x)) {
    sprintf("  length %d: %s", length(x), one_col(x))
  } else ""
  paste(c(hdr, body), collapse = "\n")
}

set.seed(3)
n = 1e5
e = new.env()
e$num_vec = c(rnorm(1e6, 50, 10), rep(NA, 2000))
e$chr_vec = sample(c("control", "treated", "placebo", "unknown"), n, TRUE)
e$fct = factor(sample(c("T cell", "B cell", "NK cell", "monocyte", "platelet"), n, TRUE, prob = c(.4, .2, .15, .2, .05)))
e$dates = as.Date("2021-01-01") + sample(0:1000, n, TRUE)
e$times = as.POSIXct("2024-03-01 08:00:00", tz = "UTC") + sample(0:86400, n, TRUE)
e$df = data.frame(id = seq_len(n), group = sample(c("a", "b", "c"), n, TRUE), dose = round(runif(n, 0, 10), 1),
                  response = c(rnorm(n - 500), rep(NA, 500)), visit = as.Date("2023-01-01") + sample(0:365, n, TRUE),
                  site = factor(sample(paste0("site", 1:12), n, TRUE)), treated = sample(c(TRUE, FALSE), n, TRUE))
e$tbl = tibble::as_tibble(e$df)
e$dt = data.table::as.data.table(e$df); data.table::setkey(e$dt, site, id)
e$mat = matrix(rnorm(1000 * 50), 1000, 50, dimnames = list(paste0("gene", 1:1000), paste0("s", 1:50)))
e$sparse = Matrix::rsparsematrix(20000, 3000, density = 0.01, dimnames = list(paste0("G", 1:20000), paste0("cell", 1:3000)))
e$lst = list(counts = 1:10, label = "run 7", table = mtcars, params = list(alpha = 0.05, method = "BH"))
e$nested = list(project = list(name = "pbmc", samples = list(s1 = list(n = 812, qc = list(mt = 0.12, genes = 1850)),
                                                              s2 = list(n = 640, qc = list(mt = 0.09, genes = 1703)))),
                settings = list(resolution = 0.8, dims = 30))
e$env = local({ v = new.env(); v$counter = 3L; v$cache = list(); v$log = function(msg) msg; v$reset = function() NULL; v })
e$fn = eval(parse(text = "function(df, col, threshold = 0.5, na.rm = TRUE) {\n  x = df[[col]]\n  keep = !is.na(x) & x > threshold\n  df[keep, , drop = FALSE]\n}", keep.source = TRUE))
e$fit_lm = lm(mpg ~ wt + hp, data = mtcars)
e$fit_glm = glm(am ~ wt, family = binomial, data = mtcars)
setClass("SeuratLike", slots = c(assays = "list", meta.data = "data.frame", active.ident = "factor",
                                 reductions = "list", project.name = "character", version = "character"))
cells = paste0("cell", 1:3000)
e$seu = new("SeuratLike", assays = list(RNA = e$sparse), project.name = "pbmc3k", version = "5.1.0",
            meta.data = data.frame(orig.ident = "pbmc3k", nCount_RNA = rpois(3000, 2000), nFeature_RNA = rpois(3000, 800),
                                   percent.mt = runif(3000, 0, 20), row.names = cells),
            active.ident = factor(sample(0:8, 3000, TRUE)), reductions = list(pca = matrix(0, 3000, 30)))
Counter = R6::R6Class("Counter", public = list(count = 0, step = 1, add = function(n = 1) { self$count = self$count + n * self$step; invisible(self) }, reset = function() self$count = 0))
e$r6 = Counter$new()
e$fml = y ~ x + log(dose) + (1 | subject)
e$altrep = 1:1e9

# facts that a model needs to use each object correctly (regex over the description)
F = list(
  num_vec = c(class = "numeric", length = "1,002,000|1002000", min = "min|range", median = "median", max = "max|range", na = "NA"),
  chr_vec = c(class = "character", length = "100,000|1e\\+05|100000", unique = "4 unique|unique", example = "control|treated"),
  fct = c(class = "factor", length = "100,000|1e\\+05|100000", nlevels = "5 levels", top = "T cell"),
  dates = c(class = "Date", length = "100,000|1e\\+05|100000", range_min = "2021-01-0[1-9]", range_max = "2023-09-2[0-9]"),
  times = c(class = "POSIXct", length = "100,000|1e\\+05|100000", range_min = "2024-03-01 08:0", range_max = "2024-03-02 0[78]:"),
  df = c(class = "data.frame", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var", colnames = "response.*visit.*site|response", types = "Date|factor", stats = "min|range|mean", na = "NA", key_col = "treated"),
  tbl = c(class = "tbl_df|tibble", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var|× 7", colnames = "response", types = "Date|fct|factor", stats = "min|range", na = "NA", key_col = "treated"),
  dt = c(class = "data.table", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var", colnames = "response", types = "Date|factor", stats = "min|range", key = "key.*site", key_col = "treated"),
  mat = c(class = "matrix", dim = "1,000 x 50|1000 x 50|\\[1:1000, 1:50\\]", type = "double|num", rownames = "gene1", colnames = "s1", values = "[0-9]\\.[0-9]{2}"),
  sparse = c(class = "dgCMatrix", dim = "20,000 x 3,000|20000 x 3000", nnz = "600,000|6e\\+05|600000|density|non-zero|nnz", rownames = "G1", colnames = "cell1"),
  lst = c(class = "list", length = "length 4|list of 4|List of 4", names = "counts.*label.*table.*params|counts", elem_class = "data.frame"),
  nested = c(class = "list", top_names = "(?s)project.*settings", depth2 = "samples|name", leaf = "resolution|0\\.8", deep = "qc|mt"),
  env = c(class = "environment", n = "4 bindings|4 obj", fields = "counter", methods = "reset"),
  fn = c(class = "function", args = "df, col, threshold", defaults = "threshold = 0\\.5|0\\.5", body = "is.na"),
  fit_lm = c(class = "lm", formula = "mpg ~ wt \\+ hp", n = "32", coefs = "wt", fit_stat = "R\\^2|R-squared|r.squared"),
  fit_glm = c(class = "glm", formula = "am ~ wt", family = "binomial", coefs = "wt", fit_stat = "AIC|deviance"),
  seu = c(class = "SeuratLike", slots = "meta.data", meta_dim = "3,000|3000", meta_cols = "percent.mt", assay = "RNA", idents = "active.ident"),
  r6 = c(class = "Counter", fields = "count", methods = "add"),
  fml = c(class = "formula", text = "log\\(dose\\)|y ~ x"),
  altrep = c(class = "integer", length = "1,000,000,000|1e\\+09|1000000000", range = "1e\\+09|1,000,000,000|max"))

describe_12 = function(nm, budget) paste(gptr_describe_binding(nm, e, budget = budget), collapse = "\n")
describe_str = function(nm) paste(utils::capture.output(utils::str(get(nm, e), give.attr = FALSE, list.len = 10, vec.len = 3)), collapse = "\n")
res = list(); t_alt = NA
for (nm in names(F)) {
  outs = list(`12@50` = describe_12(nm, 50L), `12@150` = describe_12(nm, 150L), `12@300` = describe_12(nm, 300L),
              `12@600` = describe_12(nm, 600L), `10` = d10(get(nm, e), nm),
              `str()` = if (nm == "altrep") "(str skipped)" else describe_str(nm))
  for (k in names(outs)) {
    txt = outs[[k]]
    hit = vapply(F[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
    res[[length(res) + 1]] = data.frame(object = nm, describer = k, tokens = tok_o200k(txt), chars = nchar(txt),
                                        facts = sum(hit), of = length(hit), missing = paste(names(hit)[!hit], collapse = ","))
  }
}
t_alt = system.time(gptr_describe_binding("altrep", e, 300L))[["elapsed"]]
d = do.call(rbind, res)
w = reshape(d[, c("object", "describer", "tokens", "facts")], idvar = "object", timevar = "describer", direction = "wide")
names(w) = sub("^tokens[.]", "tok ", sub("^facts[.]", "facts ", names(w)))
w$of = vapply(F[w$object], length, 1L)
cat("Tokens (o200k) and facts found, per object and describer (12@B = report 12 gptr_describe at budget B):\n")
print(w[, c("object", "of", "tok 12@50", "facts 12@50", "tok 12@150", "facts 12@150", "tok 12@300", "facts 12@300",
            "tok 12@600", "facts 12@600", "tok 10", "facts 10", "tok str()", "facts str()")], row.names = FALSE)
cat("\nTotals over", length(F), "objects:\n")
tt = aggregate(cbind(tokens, facts, of) ~ describer, d, sum)
tt$facts_pct = round(100 * tt$facts / tt$of, 1); tt$facts_per_100tok = round(100 * tt$facts / tt$tokens, 2)
print(tt[order(match(tt$describer, c("12@50", "12@150", "12@300", "12@600", "10", "str()"))), ], row.names = FALSE)
cat("\nBudget adherence of report 12 (budget in tokens, fitted with 3.5 chars/token): actual o200k / budget\n")
for (b in c(50, 150, 300, 600)) {
  x = d[d$describer == sprintf("12@%d", b), ]
  cat(sprintf("  budget %3d: median %.2f, max %.2f (objects over budget: %d of %d); chars per token median %.2f\n",
              b, median(x$tokens / b), max(x$tokens / b), sum(x$tokens > b), nrow(x), median(x$chars / x$tokens)))
}
cat("\nMissing facts at budget 300 (report 12):\n")
m = d[d$describer == "12@300" & nzchar(d$missing), c("object", "missing")]
print(m, row.names = FALSE)
cat(sprintf("\nALTREP 1:1e9 described in %.3f s without materialising (object.size %s)\n", t_alt, format(object.size(e$altrep), units = "B")))
cat("\nExamples at budget 150:\n")
for (nm in c("df", "sparse", "seu", "fml", "dates")) cat(describe_12(nm, 150L), "\n---\n")
ws = paste(gptr_workspace_summary(e, budget = 600L), collapse = "\n")
cat(sprintf("\nWorkspace summary (21 objects, budget 600): %d o200k tokens, %d lines\n%s\n", tok_o200k(ws), length(strsplit(ws, "\n")[[1]]), ws))
tok_save()
````

**`G2/c2_describe.R`**

````r
# G2 (c) prototype: a budgeted describer that degrades by detail LEVEL instead of cutting lines, measures
# its own output with the calibrated estimator (class "str", 2.01 chars/token) instead of 3.5 chars/token,
# and fixes the gaps found in report 12's prototype (Date/POSIXct shown as numbers, dgCMatrix without
# dims, formula without text, nested lists without inner names). It reuses report 12's copy-safe leaves.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/c_describe.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
# describer output is its own content class: 2.39 chars/token (median over report 12's outputs, c_describe.txt)
est_lines = function(l) sum(estimate_tokens(l, "describe", cpt = c(fx$cpt_ship, describe = 2.39))) + length(l)

# ---------- formatting helpers (facts only; never see the object) ----------
fmt_vals = function(s, sampled) {
  v = s$values
  cls = s$class
  na = sum(is.na(v))
  na_txt = if (na) sprintf("%s%.1f%% NA", if (sampled) "~" else "", 100 * na / max(1L, length(v))) else if (sampled) "no NA in sample" else "no NA"
  if (!is.null(s$levels)) {
    v = structure(v, levels = s$levels, class = "factor")
    tb = sort(table(v), decreasing = TRUE); k = seq_len(min(3L, length(tb)))
    return(sprintf("%d levels, top: %s; %s", length(s$levels), paste(sprintf("%s (%d)", names(tb)[k], tb[k]), collapse = ", "), na_txt))
  }
  if (any(c("Date", "POSIXct", "difftime") %in% cls)) {
    v = structure(v, class = cls, tzone = s$tzone, units = s$units)
    r = range(v, na.rm = TRUE)
    return(sprintf("%s to %s; %s", format(r[1]), format(r[2]), na_txt))
  }
  if (is.numeric(v) && any(!is.na(v))) {
    q = stats::quantile(v, c(0, .5, 1), na.rm = TRUE, names = FALSE)
    return(sprintf("%s..%s (median %s); %s", format(q[1], digits = 4), format(q[3], digits = 4), format(q[2], digits = 4), na_txt))
  }
  if (is.character(v)) {
    u = unique(v[!is.na(v)])
    return(sprintf("%s%d unique, e.g. %s; %s", if (sampled) ">=" else "", length(u), paste(encodeString(utils::head(u, 3), quote = "\""), collapse = ", "), na_txt))
  }
  if (is.logical(v)) return(sprintf("%s%d TRUE; %s", if (sampled) "~" else "", sum(v, na.rm = TRUE), na_txt))
  paste(format(utils::head(v, 3)), collapse = ", ")
}
abbr = c(integer = "int", numeric = "dbl", character = "chr", logical = "lgl", factor = "fct", Date = "date", POSIXct = "dttm", list = "list")
leaf_sample2 = function(x, idx) list(values = .subset(x, idx), levels = attr(x, "levels"), class = class(x), n = length(x),
                                      tzone = attr(x, "tzone"), units = attr(x, "units"))
pick = function(levels, budget) {            # richest level whose estimated size fits the budget
  ok = vapply(levels, function(l) est_lines(l) <= budget, NA)
  if (any(ok)) levels[[max(which(ok))]] else {
    l = levels[[1]]; while (length(l) > 1 && est_lines(l) > budget) l = l[-length(l)]; l
  }
}
describe2 = function(x, budget = 300L) UseMethod("describe2")
describe2.default = function(x, budget = 300L) {
  f = .gptr_leaf_core(x)
  if (f$s4) return(describe2_s4(x, f, budget))
  if (inherits(x, "formula")) return(pick(list(sprintf("<formula> %s", paste(deparse(x), collapse = " "))), budget))
  if (is.atomic(x) && !length(f$dim)) {
    idx = gptr_sample_idx(f$length); s = leaf_sample2(x, idx); sampled = length(idx) < f$length
    h = .gptr_fmt_header(f)
    return(pick(list(h, c(h, paste0("  ", fmt_vals(s, sampled), if (sampled) sprintf(" [sample of %s]", gptr_fmt_n(length(idx))) else ""))), budget))
  }
  pick(list(.gptr_fmt_header(f)), budget)
}
describe2.data.frame = function(x, budget = 300L) {
  f = .gptr_leaf_core(x); idx = gptr_sample_idx(f$nrow); d = .gptr_leaf_df(x, idx)
  cols = d$names[seq_along(d$cols)]
  types = vapply(d$cols, function(cj) { a = abbr[cj$class[1]]; if (is.na(a)) cj$class[1] else a }, "")
  h = .gptr_fmt_header(f)
  if (length(d$key)) h = paste0(h, "; key: ", paste(d$key, collapse = ", "))
  l0 = c(h, paste0("  ", paste(sprintf("%s:%s", cols, types), collapse = " ")))
  stats = vapply(seq_along(d$cols), function(j) { cj = d$cols[[j]]; fmt_vals(list(values = cj$values, levels = cj$levels, class = cj$class), length(idx) < f$nrow) }, "")
  l1 = c(h, sprintf("  $ %s <%s> %s", cols, types, stats))
  pick(list(l0, l1), budget)
}
describe2.matrix = function(x, budget = 300L) {
  f = .gptr_leaf_core(x); m = .gptr_leaf_matrix(x)
  h = .gptr_fmt_header(f)
  l1 = c(h, sprintf("  %s; rownames %s; colnames %s", f$type, if (is.null(m$rn)) "none" else paste(m$rn, collapse = ", "), if (is.null(m$cn)) "none" else paste(m$cn, collapse = ", ")))
  pick(list(h, l1, c(l1, paste0("  ", utils::capture.output(print(unname(m$corner), digits = 3))))), budget)
}
describe2.dgCMatrix = function(x, budget = 300L) {        # attr() on slots: primitives only
  d = attr(x, "Dim"); nnz = length(attr(x, "x")); dn = attr(x, "Dimnames")
  h = sprintf("<dgCMatrix> %s x %s sparse, %s non-zero (%.2f%%), %s", gptr_fmt_n(d[1]), gptr_fmt_n(d[2]), gptr_fmt_n(nnz), 100 * nnz / prod(as.numeric(d)), gptr_fmt_bytes(as.numeric(utils::object.size(x))))
  pick(list(h, c(h, sprintf("  rownames %s ...; colnames %s ...", paste(utils::head(dn[[1]], 3), collapse = ", "), paste(utils::head(dn[[2]], 3), collapse = ", ")))), budget)
}
describe2.list = function(x, budget = 300L) {
  f = .gptr_leaf_core(x)
  walk = function(y, depth, prefix) {                    # names and shapes, depth-first, at most 40 lines
    if (!is.list(y) || is.data.frame(y) || depth > 3) return(character())
    nm = names(y); if (is.null(nm)) nm = sprintf("[[%d]]", seq_along(y))
    out = character()
    for (i in seq_len(min(length(y), 8L))) {
      el = .subset2(y, i)
      shape = if (is.data.frame(el)) sprintf("%d x %d", .row_names_info(el, 2L), length(el)) else paste("length", length(el))
      val = if (is.atomic(el) && length(el) == 1L) paste0(" = ", format(el)) else ""
      out = c(out, sprintf("%s%s: <%s> %s%s", prefix, nm[i], class(el)[1], shape, val), walk(el, depth + 1L, paste0(prefix, "  ")))
      if (length(out) > 40) break
    }
    out
  }
  h = .gptr_fmt_header(f)
  top = paste0("  names: ", paste(utils::head(names(x), 20), collapse = ", "))
  pick(list(h, c(h, top), c(h, walk(x, 1L, "  "))), budget)
}
describe2.environment = function(x, budget = 300L) pick(list(gptr_describe.environment(x, 1e6)), budget)
describe2.R6 = function(x, budget = 300L) pick(list(gptr_describe.environment(x, 1e6)), budget)
describe2.function = function(x, budget = 300L) {
  src = attr(x, "srcref"); body = if (!is.null(src)) as.character(src) else deparse(x)
  fm = formals(x)
  dflt = vapply(seq_along(fm), function(i) paste(deparse(fm[[i]]), collapse = ""), "")
  sig = sprintf("<function> function(%s)", paste(ifelse(nzchar(dflt), paste(names(fm), "=", dflt), names(fm)), collapse = ", "))
  pick(list(sig, c(sig, paste0("  ", utils::head(body, 8)))), budget)
}
describe2.lm = function(x, budget = 300L) pick(list(gptr_describe.lm(x, 1e6)[1], gptr_describe.lm(x, 1e6)), budget)
describe2_s4 = function(x, f, budget) {
  slots = methods::slotNames(f$class); sl = .gptr_leaf_s4(x, slots)
  shape = function(s) if (length(s$dim)) paste(gptr_fmt_n(s$dim), collapse = " x ") else if (!is.na(s$nrow)) sprintf("%s rows", gptr_fmt_n(s$nrow)) else paste("length", gptr_fmt_n(s$length))
  h = sprintf("<S4 %s> %s; slots: %s", f$class[1], gptr_fmt_bytes(f$size), paste(slots, collapse = ", "))
  l1 = c(h, sprintf("  @%s: <%s> %s%s", slots, vapply(sl, function(s) s$class[1], ""), vapply(sl, shape, ""),
                    vapply(sl, function(s) if (length(s$names)) paste0("; names: ", paste(s$names, collapse = ", ")) else "", "")))
  pick(list(h, l1), budget)
}

F$nested["top_names"] = "(?s)project.*settings"
# describe2 prints ranges as "a..b" and abbreviates types (int, dbl, fct, date): accept both spellings
for (k in c("num_vec", "df", "tbl", "dt")) { F[[k]][names(F[[k]]) %in% c("min", "max", "stats")] = "min|range|mean|[0-9]\\.\\.[-0-9]" }
for (k in c("df", "tbl", "dt")) F[[k]]["types"] = "Date|factor|date|fct"
res = list()
for (nm in names(F)) for (b in c(50L, 150L, 300L, 600L)) {
  txt = paste(describe2(get(nm, e), budget = b), collapse = "\n")
  txt = paste0(nm, ": ", txt)
  hit = vapply(F[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
  res[[length(res) + 1]] = data.frame(object = nm, budget = b, tokens = tok_o200k(txt), facts = sum(hit), of = length(hit), missing = paste(names(hit)[!hit], collapse = ","))
}
d2 = do.call(rbind, res)
cat("\n\n=== G2 level-based describer (describe2) ===\n")
tt = aggregate(cbind(tokens, facts, of) ~ budget, d2, sum)
tt$facts_pct = round(100 * tt$facts / tt$of, 1); tt$facts_per_100tok = round(100 * tt$facts / tt$tokens, 2)
tt$over_budget = vapply(tt$budget, function(b) sum(d2$tokens[d2$budget == b] > b), 1L)
tt$max_ratio = vapply(tt$budget, function(b) round(max(d2$tokens[d2$budget == b] / b), 2), 1)
print(tt, row.names = FALSE)
cat("\nMissing facts per budget (describe2):\n")
for (b in c(50L, 150L, 300L)) { m = d2[d2$budget == b & nzchar(d2$missing), ]; cat(sprintf("  budget %d: %s\n", b, paste(sprintf("%s[%s]", m$object, m$missing), collapse = "; "))) }
cat("\nExamples (budget 50 and 150):\n")
for (nm in c("df", "dates", "sparse", "seu", "fml", "nested")) for (b in c(50L, 150L)) cat(sprintf("[%s @%d] %s\n", nm, b, paste(describe2(get(nm, e), b), collapse = "\n    ")))
tok_save()
````

**`G2/out/c_describe_final.txt`**

````text
Tokens (o200k) and facts found, per object and describer (12@B = report 12 gptr_describe at budget B):
  object of tok 12@50 facts 12@50 tok 12@150 facts 12@150 tok 12@300
 num_vec  6        60           6         60            6         60
 chr_vec  4        38           4         38            4         38
     fct  4        45           4         45            4         45
   dates  4        35           2         35            2         35
   times  4        53           2         53            2         53
      df  8        54           5        193            8        193
     tbl  8        58           5        197            8        197
      dt  8        62           5        201            8        201
     mat  6        58           5        165            6        165
  sparse  5        64           2         91            2         91
     lst  4        56           4         80            4         80
  nested  5        44           2         44            2         44
     env  4        37           4         37            4         37
      fn  4        54           3         77            4         77
  fit_lm  5        71           5         71            5         71
 fit_glm  5        58           5         58            5         58
     seu  6        45           2        122            6        122
      r6  3        48           3         48            3         48
     fml  2        19           1         19            1         19
  altrep  3        62           3         62            3         62
 facts 12@300 tok 12@600 facts 12@600 tok 10 facts 10 tok str() facts str()
            6         60            6     32        4        25           1
            4         38            4     32        3        17           2
            4         45            4     23        3        32           1
            2         35            2     37        4        34           2
            2         53            2     30        2        54           2
            8        193            8    125        7       187           6
            8        197            8    129        7       223           6
            8        201            8    113        7       189           6
            6        165            6     35        2        29           3
            2         91            2     30        1       213           4
            4         80            4     41        4       395           4
            2         44            2     28        2       188           4
            4         37            4      8        1        14           1
            4         77            4     22        2        19           3
            5         71            5     83        1       294           4
            5         58            5     87        2       455           3
            6        122            6     32        3       548           6
            3         48            3     11        1        53           3
            1         19            1     12        1        20           2
            3         62            3     32        2         3           0

Totals over 20 objects:
 describer tokens facts of facts_pct facts_per_100tok
     12@50   1021    72 98      73.5             7.05
    12@150   1696    87 98      88.8             5.13
    12@300   1696    87 98      88.8             5.13
    12@600   1696    87 98      88.8             5.13
        10    942    59 98      60.2             6.26
     str()   2992    63 98      64.3             2.11

Budget adherence of report 12 (budget in tokens, fitted with 3.5 chars/token): actual o200k / budget
  budget  50: median 1.08, max 1.42 (objects over budget: 12 of 20); chars per token median 2.43
  budget 150: median 0.41, max 1.34 (objects over budget: 4 of 20); chars per token median 2.39
  budget 300: median 0.20, max 0.67 (objects over budget: 0 of 20); chars per token median 2.39
  budget 600: median 0.10, max 0.34 (objects over budget: 0 of 20); chars per token median 2.39

Missing facts at budget 300 (report 12):
 object               missing
  dates   range_min,range_max
  times   range_min,range_max
 sparse dim,rownames,colnames
 nested      depth2,leaf,deep
    fml                  text

ALTREP 1:1e9 described in 0.009 s without materialising (object.size 4000000048 bytes)

Examples at budget 150:
df: <data.frame> 100,000 x 7, 4.2 MB
  $ id <integer> min 1, median 50000, max 1e+05; no NA
  $ group <character> 3 unique, e.g. "a", "c", "b"; no NA
  $ dose <numeric> min 0, median 5, max 10; no NA
  $ response <numeric> min -4.505, median 0.002491, max 4.374; 0.5% NA
  $ visit <Date> min 19358, median 19540, max 19723; no NA
  $ site <factor> 12 levels, top: site11 (8501), site9 (8423), site12 (8421); no NA
  $ treated <logical> 50269 TRUE; no NA 
---
sparse: <S4 dgCMatrix from Matrix> 8.3 MB
  @i: <integer> length 600,000
  @p: <integer> length 3,001
  @Dim: <integer> length 2
  @Dimnames: <list> length 2
  @x: <numeric> length 600,000
  @factors: <list> length 0 
---
seu: <S4 SeuratLike from .GlobalEnv> 9.3 MB
  @assays: <list> length 1; names: RNA
  @meta.data: <data.frame> 3,000 rows; names: orig.ident, nCount_RNA, nFeature_RNA, percent.mt
  @active.ident: <factor> length 3,000
  @reductions: <list> length 1; names: pca
  @project.name: <character> length 1
  @version: <character> length 1 
---
fml: <formula> length 3, 1.9 KB
  typeof language 
---
dates: <Date> length 100,000, 781.5 KB
  min 18628, median 19128, max 19628; no NA 
---

Workspace summary (21 objects, budget 600): 336 o200k tokens, 20 lines
altrep <integer> length 1,000,000,000, 3.7 GB
seu <SeuratLike> length 1, 9.3 MB
sparse <dgCMatrix> length 60,000,000, 8.3 MB
num_vec <numeric> length 1,002,000, 7.6 MB
dt <data.table/data.frame> 100,000 x 7, 4.2 MB
tbl <tbl_df/tbl/data.frame> 100,000 x 7, 4.2 MB
df <data.frame> 100,000 x 7, 4.2 MB
times <POSIXct/POSIXt> length 100,000, 781.8 KB
chr_vec <character> length 100,000, 781.5 KB
dates <Date> length 100,000, 781.5 KB
mat <matrix/array> 1,000 x 50, 456.7 KB
fct <factor> length 100,000, 391.4 KB
fit_glm <glm/lm> length 30, 215.5 KB
fit_lm <lm> length 12, 27.7 KB
lst <list> length 4, 8.2 KB
nested <list> length 2, 3.3 KB
fml <formula> length 3, 1.9 KB
env <environment> length 4
fn <function> length 1
r6 <Counter/R6> length 6
Warning messages:
1: In min(s, na.rm = TRUE) :
  no non-missing arguments to min; returning Inf
2: In max(s, na.rm = TRUE) :
  no non-missing arguments to max; returning -Inf
3: In min(s, na.rm = TRUE) :
  no non-missing arguments to min; returning Inf
4: In max(s, na.rm = TRUE) :
  no non-missing arguments to max; returning -Inf
5: In min(s, na.rm = TRUE) :
  no non-missing arguments to min; returning Inf
6: In max(s, na.rm = TRUE) :
  no non-missing arguments to max; returning -Inf
7: In min.default(c(NA_real_, NA_real_, NA_real_, NA_real_, NA_real_,  :
  no non-missing arguments to min; returning Inf
8: In max.default(c(NA_real_, NA_real_, NA_real_, NA_real_, NA_real_,  :
  no non-missing arguments to max; returning -Inf


=== G2 level-based describer (describe2) ===
 budget tokens facts of facts_pct facts_per_100tok over_budget max_ratio
     50    675    72 98      73.5            10.67           1      1.08
    150   1152    89 98      90.8             7.73           0      1.00
    300   1693    97 98      99.0             5.73           0      0.65
    600   1693    97 98      99.0             5.73           0      0.32

Missing facts per budget (describe2):
  budget 50: df[stats,na]; tbl[colnames,types,stats,na,key_col]; dt[colnames,types,stats,key_col]; mat[values]; sparse[rownames,colnames]; lst[elem_class]; nested[leaf,deep]; env[methods]; fn[body]; fit_lm[fit_stat]; fit_glm[family,fit_stat]; seu[meta_dim,meta_cols,assay]; r6[methods]
  budget 150: df[stats,na]; tbl[stats,na]; dt[stats]; nested[deep]; seu[meta_dim,meta_cols,assay]
  budget 300: nested[deep]

Examples (budget 50 and 150):
[df @50] <data.frame> 100,000 x 7, 4.2 MB
      id:int group:chr dose:dbl response:dbl visit:date site:fct treated:lgl
[df @150] <data.frame> 100,000 x 7, 4.2 MB
      id:int group:chr dose:dbl response:dbl visit:date site:fct treated:lgl
[dates @50] <Date> length 100,000, 781.5 KB
      2021-01-01 to 2023-09-28; no NA
[dates @150] <Date> length 100,000, 781.5 KB
      2021-01-01 to 2023-09-28; no NA
[sparse @50] <dgCMatrix> 20,000 x 3,000 sparse, 600,000 non-zero (1.00%), 8.3 MB
[sparse @150] <dgCMatrix> 20,000 x 3,000 sparse, 600,000 non-zero (1.00%), 8.3 MB
      rownames G1, G2, G3 ...; colnames cell1, cell2, cell3 ...
[seu @50] <S4 SeuratLike> 9.3 MB; slots: assays, meta.data, active.ident, reductions, project.name, version
[seu @150] <S4 SeuratLike> 9.3 MB; slots: assays, meta.data, active.ident, reductions, project.name, version
[fml @50] <formula> y ~ x + log(dose) + (1 | subject)
[fml @150] <formula> y ~ x + log(dose) + (1 | subject)
[nested @50] <list> length 2, 3.3 KB
      names: project, settings
[nested @150] <list> length 2, 3.3 KB
      project: <list> length 2
        name: <character> length 1 = pbmc
        samples: <list> length 2
          s1: <list> length 2
          s2: <list> length 2
      settings: <list> length 2
        resolution: <numeric> length 1 = 0.8
        dims: <numeric> length 1 = 30
````

### 5.5 Part (f): corpora, calibration, feature models, recalibration

**`G2/f_corpus.R`**

````r
# G2 (f): build per-class corpora of the text an R agent puts into its context. Output: f_corpus.rds,
# a named list class -> character vector of chunks (each chunk <= ~4000 chars, split at line ends).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
suppressPackageStartupMessages({ library(tibble) })
options(width = 100, cli.num_colors = 1, crayon.enabled = FALSE, pillar.bold = FALSE, digits = 7)
co = function(expr) paste(utils::capture.output(expr), collapse = "\n")
rd = function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chunk = function(x, size = 4000L) {                     # split long texts at line ends into ~size chunks
  out = character()
  for (t in x) {
    if (nchar(t) <= size) { out = c(out, t); next }
    lines = strsplit(t, "\n", fixed = TRUE)[[1]]
    cur = character(); n = 0L
    for (l in lines) {
      if (n + nchar(l) + 1L > size && length(cur)) { out = c(out, paste(cur, collapse = "\n")); cur = character(); n = 0L }
      cur = c(cur, l); n = n + nchar(l) + 1L
    }
    if (length(cur)) out = c(out, paste(cur, collapse = "\n"))
  }
  out[nzchar(trimws(out))]
}
ds_names = ls("package:datasets")
ds = lapply(setNames(ds_names, ds_names), function(n) get(n, "package:datasets"))
dfs = Filter(function(x) is.data.frame(x) && nrow(x) >= 5, ds)
set.seed(11)
extra = list(
  trials = data.frame(id = sprintf("P%04d", 1:300), arm = sample(c("placebo", "low dose", "high dose"), 300, TRUE),
                      start = as.Date("2022-01-01") + sample(0:700, 300, TRUE), age = round(rnorm(300, 55, 12)),
                      bmi = round(rnorm(300, 27, 4), 1), responder = sample(c(TRUE, FALSE, NA), 300, TRUE)),
  genes = data.frame(gene = paste0("ENSG", sprintf("%011d", sample(1e9, 400))), log2FC = round(rnorm(400, 0, 2), 3),
                     pval = signif(10^-runif(400, 0, 12), 3), padj = signif(10^-runif(400, 0, 10), 3), symbol = replicate(400, paste(sample(LETTERS, 4), collapse = ""))))
dfs = c(dfs, extra)
C = list()
C$print_df = chunk(vapply(dfs, function(d) co(print(utils::head(d, 60))), ""))
C$print_tibble = chunk(vapply(dfs, function(d) co(print(tibble::as_tibble(d), n = 25, width = 100)), ""))
C$str = chunk(c(vapply(ds, function(x) co(utils::str(x)), ""), vapply(extra, function(x) co(utils::str(x)), ""),
                co(utils::str(lm(mpg ~ ., mtcars))), co(utils::str(list(a = 1:3, b = list(c = "x", d = mtcars[1:3, ]))))))
num_dfs = Filter(function(d) sum(vapply(d, is.numeric, NA)) >= 3 && nrow(d) >= 10, dfs)
C$summary_lm = chunk(vapply(num_dfs, function(d) {
  nm = names(d)[vapply(d, is.numeric, NA)]
  f = stats::as.formula(paste0("`", nm[1], "` ~ ", paste0("`", utils::head(nm[-1], 5), "`", collapse = " + ")))
  co(print(summary(stats::lm(f, data = d))))
}, ""))
C$print_misc = chunk(c(co(print(summary(iris))), co(print(table(esoph$agegp, esoph$alcgp))), co(print(t.test(extra ~ group, sleep))),
                       co(print(round(cor(mtcars), 3))), co(print(quantile(rnorm(1e4), seq(0, 1, 0.05)))), co(print(anova(lm(mpg ~ wt * hp, mtcars)))),
                       co(print(aggregate(len ~ supp + dose, ToothGrowth, mean))), co(print(head(letters, 26))), co(print(seq(0.5, 60, by = 0.5))),
                       co(print(list(a = 1:5, b = "text", c = list(d = pi)))), co(print(summary(glm(am ~ wt, binomial, mtcars)))),
                       co(print(xtabs(~ cyl + gear, mtcars))), co(print(chisq.test(table(mtcars$cyl, mtcars$am)))), co(print(sessionInfo()))))
# errors, warnings and tracebacks as the r tool reports them (report 12 section 3.4 format)
errs = list(quote(log(-1:3, base = "e")), quote(sqrt("a")), quote(mean()), quote(lm(y ~ x, data = mtcars)), quote(solve(matrix(0, 2, 2))),
  quote(matrix(1:6, 4, 4)), quote(merge(mtcars, iris, by = "id")), quote(rbind(mtcars, iris)), quote(as.Date("2024-13-45")),
  quote(factor(1:3, levels = c(1, 1))), quote(seq(1, 10, by = -1)), quote(rep(1:3, times = -1)), quote(sample(5, 10)),
  quote(stats::quantile(c(1, NA))), quote(cor(mtcars$mpg, iris$Species)), quote(t.test(1)), quote(chol(matrix(-1))),
  quote(integrate(function(x) 1 / x, 0, 1)), quote(uniroot(function(x) x^2 + 1, c(0, 1))), quote(optim(1, function(p) NA)),
  quote(library(notapackage123)), quote(get("no_such_object_xyz")), quote(match.arg("z", c("a", "b"))), quote(stopifnot(all.equal(pi, 3.14))),
  quote(vapply(1:3, function(i) letters[i], numeric(1))), quote(do.call("nofun", list())), quote(strsplit(1:3, "")), quote(nchar(quote(x))),
  quote(mtcars[, "nonexistent"]), quote(mtcars[["nope"]][[1]]), quote(list(a = 1)$a$b), quote(new.env()$x()), quote(if (NA) 1),
  quote(if (c(TRUE, FALSE)) 1), quote(1:3 + 1:2), quote(as.integer("12abc")), quote(sum("a")), quote(read.csv("no/such/file.csv")),
  quote(readRDS("missing.rds")), quote(glm(am ~ wt, family = "binomal", data = mtcars)), quote(aov(len ~ nothere, ToothGrowth)),
  quote(predict(lm(mpg ~ wt, mtcars), newdata = data.frame(x = 1))), quote(nls(y ~ a * x, data = data.frame(x = 1:5, y = 1:5))),
  quote(apply(1:3, 1, sum)), quote(Reduce(`+`, list(1, "a"))), quote(regmatches("a", 1)), quote(setNames(1:3, c("a", "b"))),
  quote(data.frame(a = 1:3, b = 1:2)), quote(array(1:24, c(2, 3, 4))[3, 1, 1]), quote(environment(1)), quote(parse(text = "x <- (1 + ")),
  quote(eval(quote(zz_undefined + 1))), quote(UseMethod("print")), quote(as.numeric(list(1, 2:3))), quote(strtoi("zz", 36L) + "a"))
fmt_cond = function(e) {
  cl = conditionCall(e)
  sprintf("%s%s: %s", if (inherits(e, "error")) "Error" else "Warning", if (is.null(cl)) "" else paste0(" in ", paste(deparse(cl, width.cutoff = 60), collapse = " ")), conditionMessage(e))
}
err_txt = vapply(errs, function(ex) {
  msgs = character()
  r = withCallingHandlers(tryCatch({ eval(ex, new.env()); "" }, error = function(e) fmt_cond(e)),
                          warning = function(w) { msgs <<- c(msgs, fmt_cond(w)); invokeRestart("muffleWarning") })
  paste(c(sprintf("> %s", paste(deparse(ex), collapse = " ")), msgs, r, sprintf("[status: %s; 0 of 1 top-level expressions completed; 0.01s]", if (nzchar(r)) "error" else "ok")), collapse = "\n")
}, "")
tb = function(depth) {                                       # a real traceback through nested user functions
  calls = NULL
  fs = list()
  for (k in depth:1) local({ kk = k; nxt = if (kk == depth) NULL else fs[[kk + 1L]]
    fs[[kk]] <<- function(x) if (is.null(nxt)) stop("subscript out of bounds: column '", x, "' not found in `counts`") else nxt(paste0(x, kk)) })
  withCallingHandlers(tryCatch(fs[[1]]("gene"), error = function(e) NULL), error = function(e) calls <<- sys.calls())
  calls = calls[seq_len(max(0, length(calls) - 2))]
  paste(c(sprintf("Error in fs[[%d]](x): subscript out of bounds: column 'gene...' not found in `counts`", depth),
          "Traceback (outermost first):", sprintf(" %d: %s", seq_along(calls), vapply(calls, function(cl) substr(paste(deparse(cl), collapse = " "), 1, 120), ""))), collapse = "\n")
}
C$errors = chunk(c(err_txt, vapply(c(3, 5, 8, 12, 20), tb, "")), size = 3000L)
C$json = chunk(c(vapply(utils::head(dfs, 25), function(d) j(utils::head(d, 40)), ""),
                 vapply(utils::head(dfs, 10), function(d) j(utils::head(d, 40), pretty = TRUE), ""),
                 vapply(utils::head(list.files(file.path(G2, "mcp_corpus/github"), full.names = TRUE), 60), rd, "")))
C$csv = chunk(vapply(dfs, function(d) co(utils::write.csv(utils::head(d, 80), stdout(), row.names = FALSE)), ""))
r_files = c(list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto", "\\.R$", full.names = TRUE),
            list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/12", "^gptr_.*\\.R$", full.names = TRUE))
stats_fns = Filter(is.function, mget(utils::head(sort(ls(asNamespace("stats"))), 400), envir = asNamespace("stats")))
C$r_code = chunk(c(vapply(r_files, rd, ""), vapply(utils::head(stats_fns, 150), function(f) paste(deparse(f), collapse = "\n"), ""),
                   vapply(list.files(file.path(G2, "a_apps"), "\\.R$", recursive = TRUE, full.names = TRUE), rd, "")))
md_files = list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi/packages/coding-agent/docs", "\\.md$", full.names = TRUE)
C$markdown = chunk(vapply(md_files, rd, ""))
mo_strings = function(lang) {                              # report 21's .mo reader (converted to "=")
  f = list.files(file.path(R.home("library"), "translations", lang, "LC_MESSAGES"), pattern = "\\.mo$", full.names = TRUE)
  out = character()
  for (p in f) {
    r = readBin(p, "raw", file.size(p))
    u32 = function(o) sum(as.integer(r[o + 1:4]) * 256^(0:3))
    N = u32(8); tt = u32(16)
    for (i in seq_len(N) - 1) {
      len = u32(tt + 8 * i); off = u32(tt + 8 * i + 4)
      if (len > 0) { b = r[off + seq_len(len)]; b[b == as.raw(0)] = as.raw(10); out = c(out, rawToChar(b)) }
    }
  }
  Encoding(out) = "UTF-8"
  out[validUTF8(out) & !grepl("^Project-Id", out)]
}
C$cjk = chunk(c(paste(mo_strings("zh_CN"), collapse = "\n"), paste(mo_strings("ja"), collapse = "\n"), paste(mo_strings("ko"), collapse = "\n")))
cjk_df = data.frame(sample = sprintf("S%02d", 1:40), tissue = sample(c("肝脏", "肺", "脑", "血液"), 40, TRUE),
                    note = sample(c("正常", "异常值", "需要复查", "サンプル不足"), 40, TRUE), value = round(rnorm(40), 3))
C$cjk_mixed_output = chunk(c(co(print(cjk_df)), co(utils::str(cjk_df)), co(print(tibble::as_tibble(cjk_df), n = 40))))
for (k in names(C)) C[[k]] = enc2utf8(C[[k]])
saveRDS(C, file.path(G2, "f_corpus.rds"))
cat(sprintf("%-18s %5s %9s\n", "class", "chunks", "chars"))
for (k in names(C)) cat(sprintf("%-18s %5d %9d\n", k, length(C[[k]]), sum(nchar(C[[k]]))))
````

**`G2/out/f_corpus.txt`**

````text
Warning message:
In summary.lm(stats::lm(f, data = d)) :
  essentially perfect fit: summary may be unreliable
Warning message:
In chisq.test(table(mtcars$cyl, mtcars$am)) :
  Chi-squared approximation may be incorrect
class              chunks     chars
print_df              47     77139
print_tibble          46     43725
str                  109     28432
summary_lm            24     16762
print_misc            14      5434
errors                60      9798
json                 102    167816
csv                   46     53812
r_code               254    446321
markdown             101    320804
cjk                   90    352250
cjk_mixed_output       4      8273
````

**`G2/f_count.R`**

````r
# G2 (f) step 1: count o200k and cl100k tokens per chunk (up to 50 chunks per class; memoised).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
C = readRDS(file.path(G2, "f_corpus.rds"))
set.seed(5)
rows = list()
for (k in names(C)) {
  x = C[[k]]
  if (length(x) > 50) x = x[sort(sample(length(x), 50))]
  for (i in seq_along(x)) {
    rows[[length(rows) + 1]] = data.frame(class = k, i = i, text = x[i], chars = nchar(x[i], "chars"),
                                          o200k = tok_o200k(x[i]), cl100k = tok_cl100k(x[i]))
  }
  tok_save()
  cat(k, "done\n")
}
d = do.call(rbind, rows)
saveRDS(d, file.path(G2, "f_counts.rds"))
cat("chunks:", nrow(d), " chars:", sum(d$chars), "\n")
````

**`G2/out/f_count.txt`**

````text
print_df done
print_tibble done
str done
summary_lm done
print_misc done
errors done
json done
csv done
r_code done
markdown done
cjk done
cjk_mixed_output done
chunks: 481  chars: 730317 
````

**`G2/f_estimator.R`**

````r
# G2 (f): the proposed pure-R estimator. Sourced by f_calibrate.R, c2_describe.R and d_compose.R.
# estimate_tokens(x, class): ASCII characters / chars-per-token of the content class, plus a per-character
# weight for CJK and for other non-ASCII characters. Constants fitted on the training half of the G2
# corpora against o200k_base (f_calibrate.R prints the fit and the held-out error).
.cjk_rx = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]"
GPTR_CPT = c(prose = 4.35, code = 3.55, r_output = 2.05, str = 2.60, csv = 1.75, json = 2.35, error = 3.45)
GPTR_W_CJK = 0.70
GPTR_W_NONASCII = 0.75
estimate_tokens = function(x, class = "auto", cpt = GPTR_CPT, w_cjk = GPTR_W_CJK, w_other = GPTR_W_NONASCII) {
  x = enc2utf8(as.character(x))
  if (identical(class, "auto")) class = vapply(x, detect_class, "", USE.NAMES = FALSE)
  class = rep_len(class, length(x))
  n = nchar(x, "chars")
  ascii = nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), "chars")
  non = n - ascii
  cjk = if (any(non > 0)) n - nchar(gsub(.cjk_rx, "", x, perl = TRUE), "chars") else numeric(length(x))
  ceiling(ascii / cpt[class] + cjk * w_cjk + (non - cjk) * w_other)
}
# Fallback when the producer does not know the class (tool results normally carry it: r -> r_output,
# read of *.csv -> csv, *.json -> json, *.R -> code, *.md -> prose, error events -> error).
detect_class = function(x) {
  s = substr(x, 1, 4000)
  lines = strsplit(s, "\n", fixed = TRUE)[[1]]
  lines = lines[nzchar(trimws(lines))]
  if (!length(lines)) return("prose")
  if (grepl("^\\s*[\\[{]", s) && grepl("\"[^\"]+\"\\s*:", s)) return("json")
  if (grepl("^(Error|Warning)( in |:)|^Traceback|\n(Error|Warning)( in |:)", s)) return("error")
  commas = lengths(regmatches(lines, gregexpr(",", lines, fixed = TRUE)))
  if (length(lines) >= 3 && median(commas) >= 2 && mean(commas == median(commas)) > 0.8) return("csv")
  if (mean(grepl("^\\s*(\\$ |'data.frame'|List of|Classes|tibble \\[| - attr|Formal class| \\.\\.)", lines)) > 0.3) return("str")
  if (grepl("(function\\s*\\(|<-|\\|>|library\\()", s) && !grepl("^\\s*\\[1\\]", s)) return("code")
  alpha = nchar(gsub("[^A-Za-z]", "", s)) / max(1, nchar(s))
  if (alpha > 0.62) return("prose")
  "r_output"
}
````

**`G2/f_calibrate.R`**

````r
# G2 (f): fit and evaluate the class-aware estimator on held-out chunks (tokenizer: o200k_base; cl100k shown too).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
d = readRDS(file.path(G2, "f_counts.rds"))
map = c(print_df = "r_output", print_tibble = "r_output", summary_lm = "r_output", print_misc = "r_output",
        str = "str", errors = "error", json = "json", csv = "csv", r_code = "code", markdown = "prose",
        cjk = "prose", cjk_mixed_output = "r_output")
d$est_class = map[d$class]
d$ascii = nchar(gsub("[^\\x01-\\x7F]", "", d$text, perl = TRUE), "chars")
d$cjk = d$chars - nchar(gsub(.cjk_rx, "", d$text, perl = TRUE), "chars")
d$other = d$chars - d$ascii - d$cjk
set.seed(9)
d$train = as.logical(ave(seq_len(nrow(d)), d$class, FUN = function(i) sample(rep_len(c(1, 0), length(i)))))

cat("Corpora (all chunks): chars per o200k token and chars/4 bias, per corpus class\n")
s = aggregate(cbind(chars, o200k, cl100k, cjk, other) ~ class, d, sum)
s$n = as.vector(table(d$class)[s$class])
s$cpt_o200k = round(s$chars / s$o200k, 2); s$cpt_cl100k = round(s$chars / s$cl100k, 2)
s$chars4_err = sprintf("%+.1f%%", 100 * (s$chars / 4 - s$o200k) / s$o200k)
s$chars2_err = sprintf("%+.1f%%", 100 * (s$chars / 2 - s$o200k) / s$o200k)
print(s[order(s$cpt_o200k), c("class", "n", "chars", "o200k", "cl100k", "cpt_o200k", "cpt_cl100k", "chars4_err", "chars2_err")], row.names = FALSE)
cat(sprintf("Total: %d chunks, %d chars, %d o200k tokens (report 21 section 2.8 had 9,959 chars of printed R output; here %d)\n\n",
            nrow(d), sum(d$chars), sum(d$o200k), sum(d$chars[d$est_class %in% c("r_output", "str")])))

# ---- fit on the training half, in two stages (ratio of sums, so class totals are unbiased) ----
tr = d[d$train, ]
pure = tr$cjk + tr$other < 0.01 * tr$chars
cpt = with(tr[pure, ], round(tapply(ascii, est_class, sum) / tapply(o200k, est_class, sum), 2))
res = function(k) with(tr[k, ], o200k - ascii / cpt[est_class])
k_cjk = tr$cjk > 0.2 * tr$chars
w_cjk = round(sum(res(k_cjk)) / sum(tr$cjk[k_cjk]), 3)
k_oth = tr$other > 0 & tr$cjk == 0
w_other = round(sum(res(k_oth)) / sum(tr$other[k_oth]), 3)
# conservative variant that gptr ships: r_output from table-like prints only (print_df, tibble, misc),
# which are denser than summary() output, and a non-ASCII weight floored at 0.35 (report 21: Cyrillic
# 0.30, German 0.27 tokens/char under o200k; the corpus here has almost no non-CJK non-ASCII text)
w_other_ship = max(w_other, 0.35)
kt = tr$class %in% c("print_df", "print_tibble", "print_misc")
cpt_ship = cpt
cpt_ship["r_output"] = round(sum(tr$ascii[kt]) / sum(tr$o200k[kt] - w_other_ship * tr$other[kt] - w_cjk * tr$cjk[kt]), 2)
cat("Fitted chars-per-token by estimator class (training half):\n"); print(cpt)
cat("Shipped (conservative) constants:\n"); print(cpt_ship)
cat(sprintf("Fitted weights: CJK %.3f tokens/char, other non-ASCII %.3f tokens/char\n\n", w_cjk, w_other))

# ---- evaluate on the held-out half ----
te = d[!d$train, ]
rule21 = function(x, cls) {                       # report 21's rule: chars/4 prose+code, chars/2 tool results, CJK 1/char
  n = nchar(x, "chars"); cj = n - nchar(gsub(.cjk_rx, "", x, perl = TRUE), "chars")
  ceiling((n - cj) / ifelse(cls %in% c("prose", "code"), 4, 2) + cj)
}
ests = list(`chars/4` = ceiling(te$chars / 4), `chars/2` = ceiling(te$chars / 2), `report 21 rule` = rule21(te$text, te$est_class),
            `G2 class known` = estimate_tokens(te$text, te$est_class, cpt = cpt, w_cjk = w_cjk, w_other = w_other),
            `G2 auto-detect` = estimate_tokens(te$text, "auto", cpt = cpt, w_cjk = w_cjk, w_other = w_other),
            `G2 shipped, class known` = estimate_tokens(te$text, te$est_class, cpt = cpt_ship, w_cjk = w_cjk, w_other = w_other_ship),
            `G2 shipped, auto` = estimate_tokens(te$text, "auto", cpt = cpt_ship, w_cjk = w_cjk, w_other = w_other_ship))
err_tab = function(truth, lab) {
  do.call(rbind, lapply(names(ests), function(k) {
    e = (ests[[k]] - truth) / truth
    data.frame(estimator = k, median_abs = sprintf("%.1f%%", 100 * median(abs(e))), p90_abs = sprintf("%.1f%%", 100 * quantile(abs(e), 0.9)),
               under_20pct = sprintf("%.0f%%", 100 * mean(e < -0.2)), total_bias = sprintf("%+.1f%%", 100 * (sum(ests[[k]]) - sum(truth)) / sum(truth)))
  }))
}
cat("Held-out chunks (n =", nrow(te), "), error vs o200k_base:\n"); print(err_tab(te$o200k), row.names = FALSE)
cat("\nSame estimators vs cl100k_base (constants were fitted on o200k):\n"); print(err_tab(te$cl100k), row.names = FALSE)
cat("\nPer class, held-out total bias vs o200k (class known | auto | chars/4 | report 21 rule):\n")
for (k in unique(te$class)) {
  i = te$class == k
  b = function(v) sprintf("%+6.1f%%", 100 * (sum(v[i]) - sum(te$o200k[i])) / sum(te$o200k[i]))
  cat(sprintf("  %-17s %s | %s | %s | %s | shipped %s\n", k, b(ests$`G2 class known`), b(ests$`G2 auto-detect`), b(ests$`chars/4`), b(ests$`report 21 rule`), b(ests$`G2 shipped, class known`)))
}
det = vapply(te$text, detect_class, "", USE.NAMES = FALSE)
cat(sprintf("\nAuto-detect agreement with the true estimator class: %.0f%%\n", 100 * mean(det == te$est_class)))
print(table(true = te$est_class, detected = det))
tm = system.time(for (r in 1:20) estimate_tokens(d$text, d$est_class, cpt = cpt))[["elapsed"]] / 20
cat(sprintf("\nSpeed: estimate_tokens() on all %d chunks (%.2f MB) takes %.1f ms; rtiktoken o200k on one 4 KB chunk takes %.0f ms\n",
            nrow(d), sum(nchar(d$text, "bytes")) / 1e6, 1000 * tm, 1000 * system.time(rtiktoken::get_token_count(d$text[1], "o200k_base"))[["elapsed"]]))
saveRDS(list(cpt = cpt, w_cjk = w_cjk, w_other = w_other, cpt_ship = cpt_ship, w_other_ship = w_other_ship), file.path(G2, "f_fit.rds"))
````

**`G2/out/f_calibrate.txt`**

````text
Corpora (all chunks): chars per o200k token and chars/4 bias, per corpus class
            class  n  chars  o200k cl100k cpt_o200k cpt_cl100k chars4_err
              csv 46  53812  34314  34452      1.57       1.56     -60.8%
              cjk 50 196156 115560 150995      1.70       1.30     -57.6%
         print_df 47  77139  39742  39903      1.94       1.93     -51.5%
              str 50  15382   7810   7832      1.97       1.96     -50.8%
       print_misc 14   5434   2747   2744      1.98       1.98     -50.5%
     print_tibble 46  43725  21825  21879      2.00       2.00     -49.9%
       summary_lm 24  16762   7344   7416      2.28       2.26     -42.9%
 cjk_mixed_output  4   8273   3414   3414      2.42       2.42     -39.4%
             json 50  80529  27382  27406      2.94       2.94     -26.5%
           errors 50   8271   2714   2705      3.05       3.06     -23.8%
           r_code 50  71076  22146  22107      3.21       3.22     -19.8%
         markdown 50 153758  35927  35807      4.28       4.29      +7.0%
 chars2_err
     -21.6%
     -15.1%
      -3.0%
      -1.5%
      -1.1%
      +0.2%
     +14.1%
     +21.2%
     +47.0%
     +52.4%
     +60.5%
    +114.0%
Total: 481 chunks, 730317 chars, 320925 o200k tokens (report 21 section 2.8 had 9,959 chars of printed R output; here 166715)

Fitted chars-per-token by estimator class (training half):
    code      csv    error     json    prose r_output      str 
    3.24     1.57     2.98     2.90     4.36     2.17     2.01 
Shipped (conservative) constants:
    code      csv    error     json    prose r_output      str 
    3.24     1.57     2.98     2.90     4.36     2.13     2.01 
Fitted weights: CJK 0.848 tokens/char, other non-ASCII 0.103 tokens/char

Held-out chunks (n = 240 ), error vs o200k_base:
               estimator median_abs p90_abs under_20pct total_bias
                 chars/4      43.2%   62.9%         74%     -44.0%
                 chars/2      27.3%  100.1%         17%     +12.0%
          report 21 rule      19.3%   63.4%         18%      +5.0%
          G2 class known      11.1%   32.6%         15%      -3.8%
          G2 auto-detect      13.1%   34.6%         18%      +1.1%
 G2 shipped, class known      11.4%   32.3%         13%      -3.4%
        G2 shipped, auto      13.0%   34.6%         15%      +1.8%

Same estimators vs cl100k_base (constants were fitted on o200k):
               estimator median_abs p90_abs under_20pct total_bias
                 chars/4      44.1%   66.1%         74%     -49.5%
                 chars/2      32.4%  100.9%         23%      +0.9%
          report 21 rule      18.1%   63.4%         18%      -5.4%
          G2 class known      14.3%   32.6%         23%     -13.3%
          G2 auto-detect      13.2%   33.1%         19%      -8.8%
 G2 shipped, class known      14.3%   32.3%         22%     -12.9%
        G2 shipped, auto      13.1%   33.2%         17%      -8.2%

Per class, held-out total bias vs o200k (class known | auto | chars/4 | report 21 rule):
  print_df           -16.1% |  -16.1% |  -54.5% |   -9.0% | shipped  -14.5%
  print_tibble       -17.1% |  -17.1% |  -55.0% |  -10.1% | shipped  -15.6%
  str                 -2.9% |   -3.3% |  -51.1% |   -2.5% | shipped   -2.9%
  summary_lm          +5.5% |   +5.5% |  -42.7% |  +14.4% | shipped   +7.5%
  print_misc         -15.1% |  -15.1% |  -53.9% |   -8.0% | shipped  -13.6%
  errors              +5.5% |   +5.0% |  -21.3% |  +56.2% | shipped   +5.5%
  json                +3.7% |   +5.2% |  -24.8% |  +50.3% | shipped   +3.7%
  csv                 +0.1% |   -1.1% |  -60.7% |  -21.4% | shipped   +0.1%
  r_code              -1.8% |   -1.8% |  -20.5% |  -20.5% | shipped   -1.8%
  markdown            -2.7% |   -2.7% |   +6.0% |   +6.0% | shipped   -2.7%
  cjk                 -0.8% |  +13.3% |  -57.4% |  +15.5% | shipped   -0.7%
  cjk_mixed_output    +4.4% |   +4.4% |  -43.4% |  +13.2% | shipped   +6.4%

Auto-detect agreement with the true estimator class: 82%
          detected
true       code csv error json prose r_output str
  code       25   0     0    0     0        0   0
  csv         0  19     0    0     0        4   0
  error       0   0    22    0     2        1   0
  json        0   0     0   23     0        2   0
  prose       6   0     0    0    25       19   0
  r_output    0   0     0    0     0       67   0
  str         0   0     0    0     0        8  17

Speed: estimate_tokens() on all 481 chunks (0.96 MB) takes 55.9 ms; rtiktoken o200k on one 4 KB chunk takes 210 ms
````

**`G2/f_features.R`**

````r
# G2 (f): does a character-feature model beat class ratios? Same train/test split as f_calibrate.R.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
d = readRDS(file.path(G2, "f_counts.rds"))
map = c(print_df = "r_output", print_tibble = "r_output", summary_lm = "r_output", print_misc = "r_output", str = "str",
        errors = "error", json = "json", csv = "csv", r_code = "code", markdown = "prose", cjk = "prose", cjk_mixed_output = "r_output")
d$est_class = map[d$class]
set.seed(9)
d$train = as.logical(ave(seq_len(nrow(d)), d$class, FUN = function(i) sample(rep_len(c(1, 0), length(i)))))
cnt = function(x, rx) nchar(x, "chars") - nchar(gsub(rx, "", x, perl = TRUE), "chars")
feat = function(x) cbind(letters = cnt(x, "[A-Za-z]"), digits = cnt(x, "[0-9]"), punct = cnt(x, "[!-/:-@\\[-`{-~]"),
                         wsrun = cnt(x, "(?<![ \\t]) "), newline = cnt(x, "\n"), cjk = cnt(x, .cjk_rx),
                         other = cnt(x, "[^\\x00-\\x7F]") - cnt(x, .cjk_rx))
F = feat(d$text)
tr = d$train; te = !d$train
fit = lm.fit(F[tr, ], d$o200k[tr])
cat("Universal feature model (tokens per character class):\n"); print(round(fit$coefficients, 3))
pred_u = ceiling(drop(F[te, ] %*% fit$coefficients))
# class-specific feature model: one coefficient vector per estimator class (letters, digits, punct, wsrun)
pred_c = numeric(sum(te))
coefs = list()
for (k in unique(d$est_class)) {
  i = tr & d$est_class == k
  cols = c("letters", "digits", "punct", "wsrun", "newline")
  f = lm.fit(F[i, cols, drop = FALSE], d$o200k[i] - 0.848 * F[i, "cjk"] - 0.35 * F[i, "other"])
  coefs[[k]] = f$coefficients
  j = d$est_class[te] == k
  pred_c[j] = ceiling(drop(F[te, cols, drop = FALSE][j, , drop = FALSE] %*% f$coefficients) + 0.848 * F[te, "cjk"][j] + 0.35 * F[te, "other"][j])
}
fx = readRDS(file.path(G2, "f_fit.rds"))
pred_r = estimate_tokens(d$text[te], d$est_class[te], cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
truth = d$o200k[te]
show = function(lab, p) {
  e = (p - truth) / truth
  cat(sprintf("  %-34s median |err| %5.1f%%  p90 %5.1f%%  bias %+5.1f%%  | r_output-class median |err| %5.1f%%\n", lab,
              100 * median(abs(e)), 100 * quantile(abs(e), .9), 100 * (sum(p) - sum(truth)) / sum(truth),
              100 * median(abs(e[d$est_class[te] == "r_output"]))))
}
cat("\nHeld-out error vs o200k:\n")
show("class ratio (shipped constants)", pred_r)
show("universal feature model", pred_u)
show("class-specific feature model", pred_c)
cat("\nClass-specific coefficients (tokens per letter, digit, punct, space-run start, newline):\n")
print(round(do.call(rbind, coefs), 3))
tm = system.time(for (r in 1:10) feat(d$text))[["elapsed"]] / 10
cat(sprintf("\nFeature extraction for %d chunks: %.0f ms (class ratio: see f_calibrate.txt)\n", nrow(d), 1000 * tm))
````

**`G2/out/f_features.txt`**

````text
Universal feature model (tokens per character class):
letters  digits   punct   wsrun newline     cjk   other 
  0.125   0.792   0.725   0.329   1.712   0.666   0.707 

Held-out error vs o200k:
  class ratio (shipped constants)    median |err|  11.4%  p90  32.3%  bias  -3.4%  | r_output-class median |err|  19.6%
  universal feature model            median |err|  11.0%  p90  28.7%  bias  -1.7%  | r_output-class median |err|  15.1%
  class-specific feature model       median |err|   6.9%  p90  19.5%  bias  +1.4%  | r_output-class median |err|   9.9%

Class-specific coefficients (tokens per letter, digit, punct, space-run start, newline):
         letters digits punct  wsrun newline
r_output   0.090  0.447 0.581  2.461  -0.191
str       -0.113  0.274 0.987  1.371  -0.020
error      0.130  1.019 0.818  0.650  -1.436
json       0.440  0.145 0.794 -2.120   4.233
csv        0.043  0.597 1.104 -2.102  -0.571
code       0.021  0.928 0.423  1.199   2.356
prose      0.290  0.076 0.585 -0.397   0.561

Feature extraction for 481 chunks: 200 ms (class ratio: see f_calibrate.txt)
````

### 5.6 Part (d): golden transcripts and composition metrics

**`G2/d_tasks.R`**

````r
# G2 (d): golden transcripts for six north-star tasks in two styles:
#   S = separate model-visible tool calls (one step per call; each result goes back to the model)
#   C = composed: one r evaluation that chains the steps (tools, MCP tools as R functions) and prints a compact result
# Every r tool result below is REAL output of the code, evaluated with evaluate::evaluate() in a session
# environment (Seurat 5.4.0 on SeuratObject::pbmc_small, nlme, base R), formatted like report 12 section 3.4.
# MCP results (task 5) come from a local fake ClinicalTrials.gov server (synthetic JSON, API-v2-like shape).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
suppressPackageStartupMessages({ library(Seurat); library(evaluate) })
options(width = 100, cli.num_colors = 1)
work = file.path(G2, "d_work"); unlink(work, recursive = TRUE); dir.create(file.path(work, "data"), recursive = TRUE)

# ---------- r tool emulation (output, messages, warnings, errors, plots; head 40% + tail 60% truncation) ----------
fmt_eval = function(res, max_lines = 2000L, max_chars = 50000L) {
  out = character(); n_plot = 0L
  for (x in res) {
    if (inherits(x, "source")) next
    if (is.character(x)) out = c(out, x)
    else if (inherits(x, "recordedplot")) { n_plot = n_plot + 1L; out = c(out, sprintf("[plot %d attached as image]\n", n_plot)) }
    else if (inherits(x, "message")) out = c(out, conditionMessage(x))
    else if (inherits(x, "warning")) out = c(out, sprintf("Warning%s: %s\n", if (is.null(conditionCall(x))) "" else paste0(" in ", deparse(conditionCall(x))[1]), conditionMessage(x)))
    else if (inherits(x, "error")) out = c(out, sprintf("Error%s: %s\n", if (is.null(conditionCall(x))) "" else paste0(" in ", deparse(conditionCall(x))[1]), conditionMessage(x)))
  }
  txt = gsub("\r", "", paste(out, collapse = ""))
  lines = strsplit(txt, "\n", fixed = TRUE)[[1]]
  if (length(lines) > max_lines || nchar(txt) > max_chars) {
    keep_h = floor(0.4 * max_lines); keep_t = floor(0.6 * max_lines)
    txt = paste(c(utils::head(lines, keep_h), sprintf("[... %d lines omitted; full text in /tmp/gptr-output-1.txt]", length(lines) - keep_h - keep_t), utils::tail(lines, keep_t)), collapse = "\n")
  }
  if (!nzchar(trimws(txt))) txt = "[no output]"
  list(text = txt, images = rep(list(c(1000, 700)), n_plot))
}
st = new.env()                                  # holds the current session environment st$S
run_r = function(code) fmt_eval(evaluate::evaluate(code, envir = st$S, stop_on_error = 1L))
# ---------- transcript builders ----------
tr_new = function(task, style, user, workspace, extra_prefix = NULL) {
  list(task = task, style = style, extra_prefix = extra_prefix,
       messages = list(list(role = "user", content = list(list(type = "text", text = paste0("<workspace>\n", workspace, "\n</workspace>\n\n", user))))))
}
step_r = function(tr, say, code) {
  id = sprintf("toolu_%02d", length(tr$messages))
  r = run_r(code)
  tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = say), list(type = "tool_use", id = id, name = "r", input = list(code = code))))
  tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "tool_result", tool_use_id = id, content = r$text, images = r$images)))
  tr
}
step_tool = function(tr, say, name, input, result, images = list()) {
  id = sprintf("toolu_%02d", length(tr$messages))
  tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = say), list(type = "tool_use", id = id, name = name, input = input)))
  tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "tool_result", tool_use_id = id, content = result, images = images)))
  tr
}
say_final = function(tr, text) { tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = text))); tr }
user_turn = function(tr, text) { tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "text", text = text))); tr }
fresh = function(setup) { st$S = new.env(parent = globalenv()); eval(setup, st$S); invisible() }
TR = list()

# ================= T1 (north star 1): cluster and show markers of the three largest clusters =================
setup1 = quote({ pbmc = SeuratObject::pbmc_small; gptr_return = function(x) invisible(x) })
ws1 = "pbmc <Seurat> 230 features x 80 cells, assay RNA (counts, data, scale.data), reductions pca, tsne, 2.3 MB"
u1 = "cluster the cells and show me the markers for the three largest clusters"
fin1 = "I clustered the 80 cells (SNN on 10 PCs, resolution 1.5). The three largest clusters are 0, 1 and 2; their top markers are listed above (e.g. cluster 0: LCK, CD3D-like T-cell genes; cluster 1: myeloid genes; cluster 2: B-cell genes). The full table is in `markers`."
for (quiet in c(FALSE, TRUE)) {
  fresh(setup1); v = if (quiet) ", verbose = FALSE" else ""
  t = tr_new(1, if (quiet) "S-quiet" else "S", u1, ws1)
  t = step_r(t, "I'll build the nearest-neighbour graph on the first 10 PCs.", sprintf("pbmc = FindNeighbors(pbmc, dims = 1:10%s)", v))
  t = step_r(t, "Now cluster.", sprintf("pbmc = FindClusters(pbmc, resolution = 1.5%s)", v))
  t = step_r(t, "Cluster sizes:", "sort(table(Idents(pbmc)), decreasing = TRUE)")
  t = step_r(t, "Markers for the three largest clusters.", sprintf("top3 = names(sort(table(Idents(pbmc)), decreasing = TRUE))[1:3]\nmarkers = FindAllMarkers(subset(pbmc, idents = top3), only.pos = TRUE%s)", v))
  t = step_r(t, "Top markers:", "head(markers, 20)")
  t = step_r(t, "Markers per cluster:", "table(markers$cluster)")
  TR[[length(TR) + 1]] = say_final(t, fin1)
}
fresh(setup1)
t = tr_new(1, "C", u1, ws1)
t = step_r(t, "I'll cluster and find the markers in one step.", paste(
  "pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)",
  "sizes = sort(table(Idents(pbmc)), decreasing = TRUE)",
  "top3 = names(sizes)[1:3]",
  "markers = FindAllMarkers(subset(pbmc, idents = top3), only.pos = TRUE, verbose = FALSE)",
  "sizes",
  "tapply(markers$gene, markers$cluster, function(g) paste(head(g, 8), collapse = \", \"))[top3]", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin1)

# ================= T2 (north star 2): mixed model, return the fit =================
setup2 = quote({
  set.seed(2); m = 30; w = 8
  mice = data.frame(mouse = factor(rep(sprintf("m%02d", 1:m), each = w)), week = rep(1:w, m),
                    diet = factor(rep(sample(rep(c("chow", "hfd", "keto"), 10)), each = w)))
  mice$weight = round(20 + 0.4 * mice$week + c(chow = 0, hfd = 3.1, keto = -0.8)[as.character(mice$diet)] + rep(rnorm(m, 0, 1.5), each = w) + rnorm(m * w, 0, 1), 2)
  gptr_return = function(x) invisible(x)
})
ws2 = "mice <data.frame> 240 x 4, 9.6 KB: mouse <factor> 30 levels; week <integer> 1..8; diet <factor> chow, hfd, keto; weight <numeric> min 16.9, max 30.5"
u2 = "Fit a mixed model of weight on diet with a random intercept per mouse, and report the diet effect."
fin2 = "Mixed model weight ~ diet + (1 | mouse), fitted with nlme::lme (REML). Relative to chow, the high-fat diet raises weight by about 3 g and keto lowers it slightly; the overall diet effect is significant in the ANOVA table above. The fitted model is returned as the result (`res$value`)."
fresh(setup2)
t = tr_new(2, "S", u2, ws2)
t = step_r(t, "Let me look at the data.", "str(mice)")
t = step_r(t, "Fit the model.", "library(nlme)\nfit = lme(weight ~ diet, random = ~ 1 | mouse, data = mice)")
t = step_r(t, "Summary:", "summary(fit)")
t = step_r(t, "Test the diet effect:", "anova(fit)")
t = step_r(t, "Confidence intervals:", "intervals(fit, which = \"fixed\")")
t = step_r(t, "Returning the fit.", "gptr_return(fit)")
TR[[length(TR) + 1]] = say_final(t, fin2)
fresh(setup2)
t = tr_new(2, "C", u2, ws2)
t = step_r(t, "Fitting and summarising in one step.", paste(
  "fit = nlme::lme(weight ~ diet, random = ~ 1 | mouse, data = mice)",
  "round(summary(fit)$tTable, 3)", "anova(fit)", "round(nlme::intervals(fit, which = \"fixed\")$fixed, 2)", "gptr_return(fit)", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin2)

# ================= T3 (north star 3): three piped steering prompts on one session =================
set.seed(3)
cnt = matrix(rnbinom(2000 * 24, mu = rep(rlnorm(2000, 3, 1.2), 24), size = 5), 2000, 24,
             dimnames = list(sprintf("gene%04d", 1:2000), sprintf("S%02d", 1:24)))
cnt[1:200, 13:24] = cnt[1:200, 13:24] * 2L
utils::write.csv(cnt, file.path(work, "data/counts.csv"))
setup3 = quote({ setwd(work); meta = data.frame(sample = sprintf("S%02d", 1:24), batch = rep(c("b1", "b2"), each = 12)) })
ws3 = "meta <data.frame> 24 x 2: sample <character> S01..S24; batch <character> b1, b2"
u3 = c("Load the counts in data/counts.csv and normalise them",
       "Now run a PCA and tell me how many components explain 80% of variance",
       "Plot PC1 against PC2 coloured by batch")
fin3 = c("Loaded `counts` (2,000 genes x 24 samples) and stored log2-CPM values in `norm`.",
         "PCA stored in `pca`; the first components needed to reach 80% of the variance are shown above.",
         "Here is PC1 vs PC2 coloured by batch; the batches separate along PC1.")
csv_head = paste(readLines(file.path(work, "data/counts.csv"), n = 5), collapse = "\n")
fresh(setup3)
t = tr_new(3, "S", u3[1], ws3)
t = step_tool(t, "Let me look at the file first.", "read", list(path = "data/counts.csv", limit = 5), paste0(csv_head, "\n\n[1996 more lines in file. Use offset=6 to continue.]"))
t = step_r(t, "Load it.", "counts = read.csv(\"data/counts.csv\", row.names = 1)\ndim(counts)")
t = step_r(t, "Library sizes:", "summary(colSums(counts))")
t = step_r(t, "Normalise to log2 CPM.", "norm = log2(t(t(counts) / colSums(counts)) * 1e6 + 1)\nnorm[1:5, 1:6]")
t = say_final(t, fin3[1]); t = user_turn(t, u3[2])
t = step_r(t, "Run the PCA.", "pca = prcomp(t(norm))")
t = step_r(t, "Variance explained:", "summary(pca)")
t = step_r(t, "Components for 80%:", "which(summary(pca)$importance[3, ] >= 0.8)[1]")
t = say_final(t, fin3[2]); t = user_turn(t, u3[3])
t = step_r(t, "Check the batch labels.", "table(meta$batch)")
t = step_r(t, "Plot.", "plot(pca$x[, 1:2], col = factor(meta$batch), pch = 19)\nlegend(\"topright\", legend = unique(meta$batch), col = 1:2, pch = 19)")
TR[[length(TR) + 1]] = say_final(t, fin3[3])
fresh(setup3)
t = tr_new(3, "C", u3[1], ws3)
t = step_r(t, "Loading and normalising.", "counts = read.csv(\"data/counts.csv\", row.names = 1)\nnorm = log2(t(t(counts) / colSums(counts)) * 1e6 + 1)\ndim(norm)\nsummary(colSums(counts))")
t = say_final(t, fin3[1]); t = user_turn(t, u3[2])
t = step_r(t, "PCA and cumulative variance.", "pca = prcomp(t(norm))\nve = summary(pca)$importance[3, ]\nwhich(ve >= 0.8)[1]\nround(ve[1:8], 3)")
t = say_final(t, fin3[2]); t = user_turn(t, u3[3])
t = step_r(t, "Plotting.", "plot(pca$x[, 1:2], col = factor(meta$batch), pch = 19)\nlegend(\"topright\", legend = unique(meta$batch), col = 1:2, pch = 19)")
TR[[length(TR) + 1]] = say_final(t, fin3[3])

# ================= T4 (north star 8): artifact from the live marker table =================
fresh(setup1)
invisible(run_r("pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)\nmarkers = FindAllMarkers(pbmc, only.pos = TRUE, verbose = FALSE)"))
S4env = st$S
ws4 = "markers <data.frame> 118 x 7: p_val, avg_log2FC, pct.1, pct.2, p_val_adj <numeric>; cluster <factor> 0..4; gene <character>\npbmc <Seurat> 230 features x 80 cells"
u4 = "Build me an explorer for the marker table with a gene search box and a volcano plot"
app = paste("library(shiny)", "library(bslib)", "library(ggplot2)", "",
  "ui = page_sidebar(", "  title = \"Marker explorer\",", "  sidebar = sidebar(textInput(\"gene\", \"Gene\"), selectInput(\"cl\", \"Cluster\", c(\"All\", levels(markers$cluster)))),",
  "  card(card_header(\"Volcano\"), plotOutput(\"volcano\"), full_screen = TRUE),", "  card(card_header(\"Markers\"), tableOutput(\"tbl\"))", ")", "",
  "server = function(input, output) {", "  sel = reactive({", "    d = markers", "    if (input$cl != \"All\") d = d[d$cluster == input$cl, ]",
  "    if (nzchar(input$gene)) d = d[grepl(input$gene, d$gene, ignore.case = TRUE), ]", "    d", "  })",
  "  output$volcano = renderPlot(ggplot(sel(), aes(avg_log2FC, -log10(p_val_adj), label = gene)) + geom_point() + geom_text(vjust = -0.5, size = 3) + theme_minimal())",
  "  output$tbl = renderTable(head(sel()[order(sel()$p_val_adj), ], 20))", "}", "", "shinyApp(ui, server)", sep = "\n")
stopifnot(!inherits(try(parse(text = app), silent = TRUE), "try-error"))
art_result = j(list(ok = TRUE, id = "marker-explorer-3a91c2", version = 1, url = "http://127.0.0.1:34110/", startup_secs = 2.1,
                    outputs = I(c("volcano", "tbl")), data = list(list(name = "markers", class = "data.frame", dim = I(c(118, 7)))),
                    checks = list(static = "ok", launch = "ok", http = 200, session = list(connected = TRUE, output_errors = list(), validation = list(), js_errors = list(), log_errors = list(), log_warnings = list()))))
fin4 = "The explorer is running at http://127.0.0.1:34110/ (artifact marker-explorer): search a gene or pick a cluster; the volcano plot and table update together."
st$S = S4env
t = tr_new(4, "S", u4, ws4)
t = step_r(t, "Let me check the marker table.", "str(markers)")
t = step_r(t, "Ranges for the plot axes:", "summary(markers$avg_log2FC)\nsummary(-log10(markers$p_val_adj))")
t = step_tool(t, "Creating the app.", "artifact", list(title = "Marker explorer", code = app, data = I("markers")), art_result, images = list(c(1100, 750)))
TR[[length(TR) + 1]] = say_final(t, fin4)
t = tr_new(4, "C", u4, ws4)
t = step_tool(t, "Creating the app.", "artifact", list(title = "Marker explorer", code = app, data = I("markers")), art_result, images = list(c(1100, 750)))
TR[[length(TR) + 1]] = say_final(t, fin4)

# ================= T5 (north star 10): plugin with an MCP server (ClinicalTrials.gov-like) =================
set.seed(5)
mk_study = function(i) {
  id = sprintf("NCT0%07d", 5100000 + i * 7919 %% 900000)
  list(protocolSection = list(
    identificationModule = list(nctId = id, briefTitle = sprintf("A Phase %s Study of %s in Patients With Idiopathic Pulmonary Fibrosis", sample(c("2", "3", "2b"), 1), sample(c("BI 1015550", "Admilparant", "Bexotegrast", "Inhaled Treprostinil", "Saracatinib", "Nerandomilast"), 1)),
                                 organization = list(fullName = sample(c("Boehringer Ingelheim", "Bristol-Myers Squibb", "Pliant Therapeutics", "United Therapeutics", "Yale University"), 1), class = "INDUSTRY")),
    statusModule = list(overallStatus = "RECRUITING", startDateStruct = list(date = sprintf("202%d-%02d", sample(3:6, 1), sample(1:12, 1))), primaryCompletionDateStruct = list(date = "2028-06", type = "ESTIMATED")),
    designModule = list(studyType = "INTERVENTIONAL", phases = I(sample(c("PHASE2", "PHASE3"), 1)), enrollmentInfo = list(count = sample(80:1200, 1), type = "ESTIMATED"),
                        designInfo = list(allocation = "RANDOMIZED", interventionModel = "PARALLEL", maskingInfo = list(masking = "QUADRUPLE"))),
    conditionsModule = list(conditions = I(c("Idiopathic Pulmonary Fibrosis")), keywords = I(c("IPF", "FVC", "interstitial lung disease"))),
    eligibilityModule = list(eligibilityCriteria = paste("Inclusion Criteria:\n* Age >= 40 years\n* Diagnosis of IPF per ATS/ERS/JRS/ALAT 2022 guideline\n* FVC >= 45% predicted\n* DLCO >= 25% predicted\n\nExclusion Criteria:\n* Relevant airway obstruction (FEV1/FVC < 0.7)\n* Acute exacerbation within 3 months\n* Listed for lung transplant"), sex = "ALL", minimumAge = "40 Years"),
    contactsLocationsModule = list(locations = lapply(1:sample(3:8, 1), function(k) list(facility = sprintf("Site %d Hospital", k), city = sample(c("Boston", "Heidelberg", "Tokyo", "Toronto", "Madrid", "Sydney"), 1), country = sample(c("United States", "Germany", "Japan", "Canada", "Spain", "Australia"), 1))))))
}
studies = lapply(1:40, mk_study)
search_json = function(n) j(list(studies = studies[seq_len(n)], nextPageToken = "NF0g5JmIo_s"))
get_json = function(i) j(studies[[i]])
ctgov_tools = list(tool("search_studies", "Search ClinicalTrials.gov studies by condition, term and status. Returns study records (protocolSection) with paging.",
                        obj(list(query_cond = str_("Condition or disease"), query_term = str_("Other terms"), filter_status = str_("Overall status, e.g. RECRUITING"),
                                 page_size = num_("Results per page (default 10, max 1000)"), page_token = str_("Token for the next page")), "query_cond")),
                   tool("get_study", "Get the full record of one study by NCT id.", obj(list(nct_id = str_("NCT identifier")), "nct_id")))
ws5 = "indication <character> \"idiopathic pulmonary fibrosis\""
u5 = "Find trials for this indication"
fin5 = "Top recruiting trials for idiopathic pulmonary fibrosis, by planned enrollment, are listed above with phase, sponsor and key eligibility (age >= 40, FVC >= 45% predicted, no recent exacerbation)."
t = tr_new(5, "S", u5, ws5, extra_prefix = list(tools = ctgov_tools))
t = step_tool(t, "Searching recruiting trials.", "search_studies", list(query_cond = "idiopathic pulmonary fibrosis", filter_status = "RECRUITING", page_size = 20), search_json(20))
for (i in c(3, 7, 12)) t = step_tool(t, "Details of a large trial:", "get_study", list(nct_id = studies[[i]]$protocolSection$identificationModule$nctId), get_json(i))
TR[[length(TR) + 1]] = say_final(t, fin5)
st$S = new.env(parent = globalenv())
st$S$indication = "idiopathic pulmonary fibrosis"
st$S$mcp = list(ctgov = list(search_studies = function(query_cond, filter_status = NULL, page_size = 10, ...) jsonlite::fromJSON(search_json(min(page_size, 40)), simplifyVector = FALSE),
                          get_study = function(nct_id) jsonlite::fromJSON(get_json(which(vapply(studies, function(s) s$protocolSection$identificationModule$nctId, "") == nct_id)[1]), simplifyVector = FALSE)))
sig_lines = "<r_functions>\nMCP tools are R functions; call them inside r and reduce results before printing.\nctgov:\n  mcp$ctgov$search_studies(query_cond: string, query_term?: string, filter_status?: string, page_size?: number, page_token?: string)  # Search ClinicalTrials.gov studies by condition, term and status.\n  mcp$ctgov$get_study(nct_id: string)  # Get the full record of one study by NCT id.\n</r_functions>"
t = tr_new(5, "C", u5, ws5, extra_prefix = list(system = sig_lines))
t = step_r(t, "Searching and ranking in R.", paste(
  "res = mcp$ctgov$search_studies(query_cond = indication, filter_status = \"RECRUITING\", page_size = 100)",
  "st = do.call(rbind, lapply(res$studies, function(s) with(s$protocolSection, data.frame(",
  "  nct = identificationModule$nctId, phase = designModule$phases[[1]], n = designModule$enrollmentInfo$count,",
  "  sponsor = identificationModule$organization$fullName, title = substr(identificationModule$briefTitle, 1, 60)))))",
  "st = st[order(-st$n), ]",
  "head(st, 10)",
  "det = lapply(st$nct[1:3], function(id) mcp$ctgov$get_study(nct_id = id))",
  "cat(vapply(det, function(s) substr(gsub(\"\\n\", \" \", s$protocolSection$eligibilityModule$eligibilityCriteria), 1, 160), \"\"), sep = \"\\n\")", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin5)

# ================= T6 (north star 11): whole workflow (prep chain + one ambiguous cluster) =================
setup6 = quote({ pbmc = SeuratObject::pbmc_small; set.seed(6); pbmc$percent.mt = round(runif(ncol(pbmc), 0, 8), 2) })
ws6 = "pbmc <Seurat> 230 features x 80 cells, assay RNA, meta.data has percent.mt"
u6 = c("Normalise pbmc, find variable features and run PCA", "Regress out percent.mt while scaling", "Keep 30 PCs; tell me if the elbow suggests fewer",
       "Cluster 2 has ambiguous markers. Investigate with additional markers and propose a label.", "Prefer canonical markers from the literature; explain your choice")
fin6 = c("Normalised (LogNormalize), found variable features and ran PCA (20 PCs; this object has 80 cells, so 30 PCs are not possible).",
         "Re-scaled with percent.mt regressed out and re-ran the PCA.", "Only 20 PCs exist here; the variance curve flattens after about 5-6 PCs, so fewer suffice.",
         "Cluster 2 expresses MS4A1, CD79A/B and HLA-DR genes, consistent with B cells.", "Canonical B-cell markers (MS4A1/CD20, CD79A, CD79B) are all enriched; I label cluster 2 as B cells.")
for (style in c("S", "C")) {
  fresh(setup6)
  t = tr_new(6, style, u6[1], ws6)
  if (style == "S") {
    t = step_r(t, "Normalise.", "pbmc = NormalizeData(pbmc)")
    t = step_r(t, "Variable features.", "pbmc = FindVariableFeatures(pbmc)")
    t = step_r(t, "Scale.", "pbmc = ScaleData(pbmc)")
    t = step_r(t, "PCA.", "pbmc = RunPCA(pbmc, npcs = 20)")
  } else {
    t = step_r(t, "Running the preprocessing chain.", "pbmc = NormalizeData(pbmc, verbose = FALSE) |> FindVariableFeatures(verbose = FALSE) |> ScaleData(verbose = FALSE) |> RunPCA(npcs = 20, verbose = FALSE)\nhead(VariableFeatures(pbmc), 10)")
  }
  t = say_final(t, fin6[1]); t = user_turn(t, u6[2])
  if (style == "S") {
    t = step_r(t, "Scale with regression.", "pbmc = ScaleData(pbmc, vars.to.regress = \"percent.mt\")")
    t = step_r(t, "Re-run PCA.", "pbmc = RunPCA(pbmc, npcs = 20)")
  } else {
    t = step_r(t, "Re-scaling with regression and re-running PCA.", "pbmc = ScaleData(pbmc, vars.to.regress = \"percent.mt\", verbose = FALSE) |> RunPCA(npcs = 20, verbose = FALSE)")
  }
  t = say_final(t, fin6[2]); t = user_turn(t, u6[3])
  if (style == "S") {
    t = step_r(t, "Elbow plot.", "print(ElbowPlot(pbmc, ndims = 20))")
    t = step_r(t, "Standard deviations:", "pbmc[[\"pca\"]]@stdev")
  } else {
    t = step_r(t, "Variance per PC.", "sd = pbmc[[\"pca\"]]@stdev\nround(sd^2 / sum(sd^2), 3)")
  }
  t = say_final(t, fin6[3]); t = user_turn(t, u6[4])
  if (style == "S") {
    t = step_r(t, "Cluster first.", "pbmc = FindNeighbors(pbmc, dims = 1:10) |> FindClusters(resolution = 1.5)")
    t = step_r(t, "Markers of cluster 2.", "m2 = FindMarkers(pbmc, ident.1 = \"2\", only.pos = TRUE)\nhead(m2, 15)")
    t = step_r(t, "Canonical markers across clusters.", "AverageExpression(pbmc, features = c(\"MS4A1\", \"CD79A\", \"CD79B\", \"CD3D\", \"LYZ\", \"GNLY\", \"PPBP\"))$RNA")
  } else {
    t = step_r(t, "Clustering and checking canonical markers in one step.", paste(
      "pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)",
      "m2 = FindMarkers(pbmc, ident.1 = \"2\", only.pos = TRUE, verbose = FALSE)",
      "head(rownames(m2), 10)",
      "round(AverageExpression(pbmc, features = c(\"MS4A1\", \"CD79A\", \"CD79B\", \"CD3D\", \"LYZ\", \"GNLY\", \"PPBP\"))$RNA, 1)", sep = "\n"))
  }
  t = say_final(t, fin6[4]); t = user_turn(t, u6[5])
  t = say_final(t, fin6[5])
  TR[[length(TR) + 1]] = t
}
saveRDS(list(TR = TR, ctgov_tools = ctgov_tools), file.path(G2, "d_transcripts.rds"))
for (t in TR) cat(sprintf("task %d %-8s messages %2d  tool calls %2d\n", t$task, t$style, length(t$messages),
                          sum(vapply(t$messages, function(m) sum(vapply(m$content, function(b) identical(b$type, "tool_use"), NA)), 1))))
cat("\n--- example: task 1 C tool result ---\n"); cat(TR[[3]]$messages[[3]]$content[[1]]$content, "\n")
cat("\n--- example: task 1 S step 2 (FindClusters) tool result ---\n"); cat(TR[[1]]$messages[[5]]$content[[1]]$content, "\n")
````

**`G2/out/d_tasks.txt`**

````text
[Seurat progress bars printed to the terminal omitted; the lines below are the script's own output]
task 1 S        messages 14  tool calls  6
task 1 S-quiet  messages 14  tool calls  6
task 1 C        messages  4  tool calls  1
task 2 S        messages 14  tool calls  6
task 2 C        messages  4  tool calls  1
task 3 S        messages 24  tool calls  9
task 3 C        messages 12  tool calls  3
task 4 S        messages  8  tool calls  3
task 4 C        messages  4  tool calls  1
task 5 S        messages 10  tool calls  4
task 5 C        messages  4  tool calls  1
task 6 S        messages 32  tool calls 11
task 6 C        messages 18  tool calls  4

--- example: task 1 C tool result ---

 0  1  2  3  4  5 
22 18 14  9  9  8 
                                                                             0 
                         "S100A8, S100A9, TYMP, FCN1, LYZ, LST1, AIF1, TYROBP" 
                                                                             1 
                              "GNLY, GZMA, CTSW, LAMP1, CST7, LCK, GZMB, GZMM" 
                                                                             2 
"HLA-DQA1, HLA-DPB1, HLA-DRA, HLA-DQB1, HLA-DRB1, HLA-DMB, HLA-DQA2, HLA-DRB5" 
 

--- example: task 1 S step 2 (FindClusters) tool result ---
Modularity Optimizer version 1.3.0 by Ludo Waltman and Nees Jan van Eck

Number of nodes: 80
Number of edges: 2352

Running Louvain algorithm...
Maximum modularity in 10 random starts: 0.1607
Number of communities: 7
Elapsed time: 0 seconds
1 singletons identified. 6 final clusters.
 
````

**`G2/d_compose.R`**

````r
# G2 (d): cumulative tokens, round trips and cost of the golden transcripts, per style and provider,
# with and without prompt caching. Tokens are o200k counts of the Anthropic-shaped message JSON
# (images by the Claude patch formula); the prefix is the gptr-7 preset (report G2 part b).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
X = readRDS(file.path(G2, "d_transcripts.rds")); TR = X$TR
img_tok = function(wh) ceiling(wh[1] / 28) * ceiling(wh[2] / 28)          # Claude standard tier, <= 1568 px long edge
sys7 = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"))
tools7 = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
prefix_tokens = function(t) {
  sys = if (!is.null(t$extra_prefix$system)) paste0(sys7, "\n\n", t$extra_prefix$system) else sys7
  tl = if (!is.null(t$extra_prefix$tools)) c(tools7, t$extra_prefix$tools) else tools7
  tok_o200k(wire(tl, sys, "anthropic"))
}
msg_tokens = function(m) {
  blocks = lapply(m$content, function(b) {
    if (identical(b$type, "tool_result")) list(type = "tool_result", tool_use_id = b$tool_use_id, content = list(list(type = "text", text = b$content)))
    else b
  })
  imgs = sum(vapply(m$content, function(b) if (identical(b$type, "tool_result") && length(b$images)) sum(vapply(b$images, img_tok, 1)) else 0, 1))
  c(text = tok_o200k(j(list(role = m$role, content = blocks))), img = imgs)
}
out_tokens = function(m) tok_o200k(j(lapply(m$content, function(b) if (identical(b$type, "tool_use")) list(name = b$name, input = b$input) else b$text)))

# prices, USD per 1M tokens (verified 2026-09-29/30): Anthropic pricing page; OpenAI pricing page; Gemini pricing page
P = list(
  sonnet55 = list(label = "Claude Sonnet 5.5", i = 2, o = 10, read = 0.20, write = 2.50, min = 512, tokf = 1.35),
  opus55 = list(label = "Claude Opus 5.5", i = 4, o = 20, read = 0.20, write = 5.00, min = 512, tokf = 1.35),
  gpt61sol = list(label = "GPT-6.1 Sol", i = 2, o = 10, read = 0.10, write = 2.50, min = 1024, tokf = 1.00),
  gem38flash = list(label = "Gemini 3.8 Flash", i = 0.75, o = 3.75, read = 0.075, write = 0.75, min = 4096, tokf = 1.00))
cost = function(inp, outp, p, cache) {
  inp = inp * p$tokf; outp = outp * p$tokf
  if (!cache) return((sum(inp) * p$i + sum(outp) * p$o) / 1e6)
  total = 0; prev = 0
  for (k in seq_along(inp)) {
    rd = if (prev >= p$min) prev else 0
    new = inp[k] - rd
    total = total + rd * p$read + new * p$write                           # new tail is written to the cache
    prev = inp[k]
  }
  (total + sum(outp) * p$o) / 1e6
}
rows = list(); per_req = list()
for (t in TR) {
  pre = prefix_tokens(t)
  mt = t(vapply(t$messages, msg_tokens, c(text = 0, img = 0)))
  is_a = vapply(t$messages, function(m) m$role == "assistant", NA)
  hist = cumsum(mt[, "text"] + mt[, "img"])
  k_a = which(is_a)
  inp = pre + c(0, hist)[k_a]                                               # everything before assistant message k
  outp = vapply(t$messages[k_a], out_tokens, 1)
  n_tool = sum(vapply(t$messages, function(m) sum(vapply(m$content, function(b) identical(b$type, "tool_use"), NA)), 1))
  res_tok = sum(mt[!is_a, "text"]) - sum(mt[1, "text"])
  r = data.frame(task = t$task, style = t$style, requests = length(k_a), tool_calls = n_tool, prefix = pre,
                 tool_result_tok = res_tok, image_tok = sum(mt[, "img"]), input_cum = sum(inp), output = sum(outp),
                 last_context = max(inp) + tail(outp, 1))
  for (pn in names(P)) {
    r[[paste0(pn, "_nocache")]] = round(cost(inp, outp, P[[pn]], FALSE), 4)
    r[[paste0(pn, "_cache")]] = round(cost(inp, outp, P[[pn]], TRUE), 4)
  }
  rows[[length(rows) + 1]] = r
  per_req[[length(per_req) + 1]] = data.frame(task = t$task, style = t$style, req = seq_along(inp), input = inp, output = outp)
}
d = do.call(rbind, rows)
cat("Per transcript (o200k tokens; cost in USD for one run of the task):\n")
print(d[, c("task", "style", "requests", "tool_calls", "prefix", "tool_result_tok", "image_tok", "input_cum", "output", "last_context")], row.names = FALSE)
cat("\nCost per run (USD), without / with prompt caching; Claude costs include a 1.35x tokenizer factor over o200k:\n")
print(d[, c("task", "style", grep("_(no)?cache$", names(d), value = TRUE))], row.names = FALSE)
cat("\nS / C ratios per task (S = separate tool calls, C = composed r evaluation):\n")
for (k in unique(d$task)) {
  s = d[d$task == k & d$style == "S", ]; cc = d[d$task == k & d$style == "C", ]
  cat(sprintf("  task %d: requests %d vs %d | cumulative input %.2fx | output %.2fx | Sonnet 5.5 cost %.2fx uncached, %.2fx cached | GPT-6.1 Sol cached %.2fx | Gemini 3.8 Flash cached %.2fx\n",
              k, s$requests, cc$requests, s$input_cum / cc$input_cum, s$output / cc$output, s$sonnet55_nocache / cc$sonnet55_nocache,
              s$sonnet55_cache / cc$sonnet55_cache, s$gpt61sol_cache / cc$gpt61sol_cache, s$gem38flash_cache / cc$gem38flash_cache))
}
q = d[d$task == 1, ]
cat(sprintf("\nTask 1 verbosity vs composition: S %d, S-quiet %d, C %d cumulative input tokens\n", q$input_cum[q$style == "S"], q$input_cum[q$style == "S-quiet"], q$input_cum[q$style == "C"]))
tot = aggregate(cbind(requests, tool_calls, input_cum, output, sonnet55_nocache, sonnet55_cache, gpt61sol_cache, gem38flash_cache) ~ style, d[d$style %in% c("S", "C"), ], sum)
cat("\nAll six tasks together:\n"); print(tot, row.names = FALSE)
cat(sprintf("S/C: requests %.2fx, cumulative input %.2fx, output %.2fx, Sonnet 5.5 uncached %.2fx, cached %.2fx\n",
            tot$requests[tot$style == "S"] / tot$requests[tot$style == "C"], tot$input_cum[tot$style == "S"] / tot$input_cum[tot$style == "C"],
            tot$output[tot$style == "S"] / tot$output[tot$style == "C"], tot$sonnet55_nocache[tot$style == "S"] / tot$sonnet55_nocache[tot$style == "C"],
            tot$sonnet55_cache[tot$style == "S"] / tot$sonnet55_cache[tot$style == "C"]))
cat(sprintf("Caching saves %.0f%% (S) and %.0f%% (C) of the Sonnet 5.5 bill; the prefix is %.0f%% of cumulative input in C and %.0f%% in S\n",
            100 * (1 - tot$sonnet55_cache[tot$style == "S"] / tot$sonnet55_nocache[tot$style == "S"]),
            100 * (1 - tot$sonnet55_cache[tot$style == "C"] / tot$sonnet55_nocache[tot$style == "C"]),
            100 * sum((d$prefix * d$requests)[d$style == "C"]) / sum(d$input_cum[d$style == "C"]),
            100 * sum((d$prefix * d$requests)[d$style == "S"]) / sum(d$input_cum[d$style == "S"])))

# ---- System 1 vs System 2 for the nine cluster-label decisions of north star 11 ----
labels = c("T cell", "B cell", "NK cell", "monocyte", "dendritic cell", "platelet", "unclear")
jev_body = function(top) j(list(model = "jev-latest", state = list(markers = top),
  questions = list(cell_type = list(type = "choice", instructions = "Which immune cell type do the marker genes in `markers` indicate?",
                                    criteria = setNames(as.list(labels), labels)))))
example = j(list(model = "jev-latest", state = list(text = "My golden retriever loves long walks on the beach."),
  questions = list(is_dog = list(type = "noul", instructions = "Does `text` describe a dog?", criteria = list(`true` = "The text describes a dog", `false` = "The text does not describe a dog")),
                   animal = list(type = "choice", instructions = "Which animal does `text` describe?", criteria = list(dog = "A dog", cat = "A cat", bird = "A bird", other = "None of these")),
                   cuteness = list(type = "score", instructions = "How positive is the sentiment of `text`?", criteria = list("Very negative", "Neutral", "Very positive")))))
jev_overhead = 443 / tok_o200k(example)
top = "LCK, CD3D, IL32, CD3E, CD2, CD7, GZMA, CCL5, CTSW, CST7"
jev_in = round(tok_o200k(jev_body(top)) * jev_overhead)
s2_prompt = sprintf("Which immune cell type do these marker genes indicate? %s\nAnswer with exactly one of: %s.", top, paste(labels, collapse = ", "))
s2_one = prefix_tokens(list()) + tok_o200k(j(list(role = "user", content = s2_prompt)))
cat(sprintf("\nNine cluster labels (north star 11): Jev ~%d input tokens per decision (o200k body x %.2f, calibrated on report 04a's 443-token request) = %d tokens, $%.6f at $0.042/MTok, output free\n",
            jev_in, jev_overhead, 9 * jev_in, 9 * jev_in * 0.042 / 1e6))
cat(sprintf("System 2 emulation through gptr: %d input tokens per decision (prefix + prompt) = %d for nine calls; Sonnet 5.5 $%.4f uncached, $%.4f with the prefix cached\n",
            s2_one, 9 * s2_one, 9 * (s2_one * 1.35 * 2 + 5 * 1.35 * 10) / 1e6,
            ((s2_one * 1.35) * 2.5 + 8 * ((s2_one - 60) * 1.35 * 0.2 + 60 * 1.35 * 2.5) + 9 * 5 * 1.35 * 10) / 1e6))
saveRDS(list(d = d, per_req = do.call(rbind, per_req)), file.path(G2, "d_metrics.rds"))
tok_save()
````

**`G2/out/d_compose.txt`**

````text
Per transcript (o200k tokens; cost in USD for one run of the task):
 task   style requests tool_calls prefix tool_result_tok image_tok input_cum
    1       S        7          6   2096            1322         0     19887
    1 S-quiet        7          6   2096            1125         0     19167
    1       C        2          1   2096             205         0      4714
    2       S        7          6   2096             806         0     19709
    2       C        2          1   2096             252         0      4772
    3       S       12          9   2096            1468      1800     41650
    3       C        6          3   2096             303      1800     16868
    4       S        4          3   2096             641      1080     11938
    4       C        2          1   2096             157      1080      5968
    5       S        5          4   2286            9938         0     49149
    5       C        2          1   2209             574         0      5334
    6       S       16         11   2096            4352       900     83748
    6       C        9          4   2096             696         0     24540
 output last_context
    287         3930
    299         3745
    228         2629
    221         3380
    159         2639
    380         6066
    273         4644
    411         4406
    350         3811
    161        12527
    277         3127
    507         8245
    451         3458

Cost per run (USD), without / with prompt caching; Claude costs include a 1.35x tokenizer factor over o200k:
 task   style sonnet55_nocache sonnet55_cache opus55_nocache opus55_cache
    1       S           0.0576         0.0212         0.1151       0.0380
    1 S-quiet           0.0558         0.0206         0.1116       0.0370
    1       C           0.0158         0.0122         0.0316       0.0239
    2       S           0.0562         0.0186         0.1124       0.0327
    2       C           0.0150         0.0114         0.0301       0.0222
    3       S           0.1176         0.0351         0.2352       0.0607
    3       C           0.0492         0.0226         0.0985       0.0419
    4       S           0.0378         0.0223         0.0756       0.0426
    4       C           0.0208         0.0180         0.0417       0.0355
    5       S           0.1349         0.0542         0.2698       0.0985
    5       C           0.0181         0.0148         0.0363       0.0289
    6       S           0.2330         0.0549         0.4659       0.0895
    6       C           0.0723         0.0233         0.1447       0.0410
 gpt61sol_nocache gpt61sol_cache gem38flash_nocache gem38flash_cache
           0.0426         0.0141             0.0160           0.0160
           0.0413         0.0137             0.0155           0.0155
           0.0117         0.0089             0.0044           0.0044
           0.0416         0.0121             0.0156           0.0156
           0.0111         0.0082             0.0042           0.0042
           0.0871         0.0225             0.0327           0.0299
           0.0365         0.0155             0.0137           0.0137
           0.0280         0.0158             0.0105           0.0105
           0.0154         0.0131             0.0058           0.0058
           0.0999         0.0365             0.0375           0.0143
           0.0134         0.0107             0.0050           0.0050
           0.1726         0.0331             0.0647           0.0280
           0.0536         0.0152             0.0201           0.0201

S / C ratios per task (S = separate tool calls, C = composed r evaluation):
  task 1: requests 7 vs 2 | cumulative input 4.22x | output 1.26x | Sonnet 5.5 cost 3.65x uncached, 1.74x cached | GPT-6.1 Sol cached 1.58x | Gemini 3.8 Flash cached 3.64x
  task 2: requests 7 vs 2 | cumulative input 4.13x | output 1.39x | Sonnet 5.5 cost 3.75x uncached, 1.63x cached | GPT-6.1 Sol cached 1.48x | Gemini 3.8 Flash cached 3.71x
  task 3: requests 12 vs 6 | cumulative input 2.47x | output 1.39x | Sonnet 5.5 cost 2.39x uncached, 1.55x cached | GPT-6.1 Sol cached 1.45x | Gemini 3.8 Flash cached 2.18x
  task 4: requests 4 vs 2 | cumulative input 2.00x | output 1.17x | Sonnet 5.5 cost 1.82x uncached, 1.24x cached | GPT-6.1 Sol cached 1.21x | Gemini 3.8 Flash cached 1.81x
  task 5: requests 5 vs 2 | cumulative input 9.21x | output 0.58x | Sonnet 5.5 cost 7.45x uncached, 3.66x cached | GPT-6.1 Sol cached 3.41x | Gemini 3.8 Flash cached 2.86x
  task 6: requests 16 vs 9 | cumulative input 3.41x | output 1.12x | Sonnet 5.5 cost 3.22x uncached, 2.36x cached | GPT-6.1 Sol cached 2.18x | Gemini 3.8 Flash cached 1.39x

Task 1 verbosity vs composition: S 19887, S-quiet 19167, C 4714 cumulative input tokens

All six tasks together:
 style requests tool_calls input_cum output sonnet55_nocache sonnet55_cache
     C       23         11     62196   1738           0.1912         0.1023
     S       51         39    226081   1967           0.6371         0.2063
 gpt61sol_cache gem38flash_cache
         0.0716           0.0532
         0.1341           0.1143
S/C: requests 2.22x, cumulative input 3.63x, output 1.13x, Sonnet 5.5 uncached 3.33x, cached 2.02x
Caching saves 68% (S) and 46% (C) of the Sonnet 5.5 bill; the prefix is 78% of cumulative input in C and 48% in S

Nine cluster labels (north star 11): Jev ~383 input tokens per decision (o200k body x 3.16, calibrated on report 04a's 443-token request) = 3447 tokens, $0.000145 at $0.042/MTok, output free
System 2 emulation through gptr: 2174 input tokens per decision (prefix + prompt) = 19566 for nine calls; Sonnet 5.5 $0.0534 uncached, $0.0141 with the prefix cached
````

**`G2/f_recal.R`**

````r
# G2 (f): per-session recalibration from provider-reported usage, replayed over the golden transcripts.
# Before request k gptr predicts its input size as
#   input_(k-1) + output_(k-1)            (both exact, from the previous response's usage)
#   + m * estimate_tokens(new messages)   (tool results and user text added since then)
# and after the response it updates m from the observed delta. "Provider" token counts are simulated:
# o200k (OpenAI-like), cl100k (a second real tokenizer) and 1.35 x o200k with +-8% per-message noise
# (a Claude-5.x-like tokenizer; Anthropic: "approximately 30% more tokens" than its previous tokenizer).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
TR = readRDS(file.path(G2, "d_transcripts.rds"))$TR
new_msgs = function(t) {                      # the non-assistant messages, each with text and a class
  out = list()
  for (i in seq_along(t$messages)) {
    m = t$messages[[i]]
    if (m$role == "assistant") { out[[length(out) + 1]] = list(boundary = TRUE); next }
    for (b in m$content) {
      if (identical(b$type, "text")) out[[length(out) + 1]] = list(text = b$text, class = "prose")
      else out[[length(out) + 1]] = list(text = b$content, class = if (grepl("^\\s*[{\\[]", b$content)) "json" else "r_output")
    }
  }
  out
}
update_m = function(m, obs, est, alpha = 0.5) {
  if (est < 150) return(m)                                   # too little new text to learn from
  r = min(max(obs / est, 0.5), 3)
  exp((1 - alpha) * log(m) + alpha * log(r))                 # EWMA on the log ratio
}
set.seed(12)
res = list()
for (prov in c("o200k", "cl100k", "claude-like")) for (t in TR) {
  items = new_msgs(t)
  truth_of = function(x) switch(prov, o200k = tok_o200k(x), cl100k = tok_cl100k(x),
                                `claude-like` = round(1.35 * tok_o200k(x) * runif(1, 0.92, 1.08)))
  m = switch(prov, `claude-like` = 1.30, 1.00)                 # provider-family prior (see report section 4)
  m_fixed = m
  seg_true = 0; seg_est = 0; seg_c4 = 0; k = 0
  for (it in items) {
    if (isTRUE(it$boundary)) {
      if (seg_true > 0) {
        k = k + 1
        res[[length(res) + 1]] = data.frame(provider = prov, task = t$task, style = t$style, k = k, true = seg_true,
          chars4 = seg_c4, class_raw = seg_est, class_prior = seg_est * m_fixed, recal = seg_est * m)
        m = update_m(m, seg_true, seg_est)
      }
      seg_true = 0; seg_est = 0; seg_c4 = 0
      next
    }
    seg_true = seg_true + truth_of(it$text)
    seg_est = seg_est + estimate_tokens(it$text, it$class, cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
    seg_c4 = seg_c4 + ceiling(nchar(it$text) / 4)
  }
}
d = do.call(rbind, res)
cat(sprintf("%d request deltas (new tool results and user text between two requests), %d transcripts x 3 providers\n\n", nrow(d) / 3, length(TR)))
for (prov in unique(d$provider)) {
  x = d[d$provider == prov, ]
  e = function(v) (v - x$true) / x$true
  big = x$true >= 150
  cat(sprintf("%-11s delta error (median |err|, p90 |err|, total bias) on deltas >= 150 tokens (n=%d):\n", prov, sum(big)))
  for (k in c("chars4", "class_raw", "class_prior", "recal")) {
    ee = e(x[[k]])[big]
    cat(sprintf("   %-11s %5.1f%%  %5.1f%%  %+5.1f%%\n", k, 100 * median(abs(ee)), 100 * quantile(abs(ee), 0.9), 100 * (sum(x[[k]][big]) - sum(x$true[big])) / sum(x$true[big])))
  }
}
tok_save()
# error on the whole predicted context (usage-anchored), using the transcripts' o200k context sizes
pr = readRDS(file.path(G2, "d_metrics.rds"))$per_req
pr = pr[pr$req > 1, ]
x = d[d$provider == "claude-like", ]
ctx = merge(x, transform(pr, k = req - 1L), by = c("task", "style", "k"))
rel = function(v) abs(v - ctx$true) / (ctx$input * 1.35)
cat(sprintf("\nClaude-like provider, error of the predicted full context (usage-anchored; n = %d requests):\n", nrow(ctx)))
for (k in c("chars4", "class_raw", "class_prior", "recal")) cat(sprintf("   %-11s median %.2f%%, max %.2f%%\n", k, 100 * median(rel(ctx[[k]])), 100 * max(rel(ctx[[k]]))))
````

**`G2/out/f_recal.txt`**

````text
81 request deltas (new tool results and user text between two requests), 13 transcripts x 3 providers

o200k       delta error (median |err|, p90 |err|, total bias) on deltas >= 150 tokens (n=20):
   chars4       47.9%   56.8%  -25.6%
   class_raw    21.5%   41.4%  +14.2%
   class_prior  21.5%   41.4%  +14.2%
   recal        15.0%   50.7%  +13.1%
cl100k      delta error (median |err|, p90 |err|, total bias) on deltas >= 150 tokens (n=20):
   chars4       47.9%   56.8%  -25.2%
   class_raw    21.1%   41.1%  +14.7%
   class_prior  21.1%   41.1%  +14.7%
   recal        16.1%   48.2%  +13.6%
claude-like delta error (median |err|, p90 |err|, total bias) on deltas >= 150 tokens (n=20):
   chars4       62.7%   69.3%  -44.6%
   class_raw    30.0%   42.4%  -15.0%
   class_prior  25.7%   35.9%  +10.5%
   recal        19.0%   45.6%   +9.9%

Claude-like provider, error of the predicted full context (usage-anchored; n = 68 requests):
   chars4      median 0.70%, max 23.91%
   class_raw   median 0.29%, max 13.97%
   class_prior median 0.37%, max 19.95%
   recal       median 0.31%, max 19.95%
````

### 5.7 Part (e): polyglot helpers vs a bash tool

**`G2/e_polyglot.R`**

````r
# G2 (e): polyglot work through compact R helpers inside the r tool vs a bash tool.
# Every command below is executed; token counts are o200k of the tool-call arguments and of the result text.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
Sys.setenv(RETICULATE_PYTHON = Sys.which("python3"), RETICULATE_USE_MANAGED_VENV = "no")
proj = file.path(G2, "e_proj"); unlink(proj, recursive = TRUE); dir.create(file.path(proj, "data"), recursive = TRUE); dir.create(file.path(proj, "scripts"))
owd = setwd(proj)
source(file.path(G2, "a_apps/data.R"))
utils::write.csv(sales, "data/sales.csv", row.names = FALSE)
utils::write.csv(cars_df, "data/cars.csv", row.names = FALSE)
writeLines(c("#!/bin/sh", "set -e", "in=$1; out=$2", "mkdir -p \"$out\"", "for f in \"$in\"/*.csv; do", "  n=$(wc -l < \"$f\")", "  echo \"$(basename \"$f\"): $n lines\"", "  cp \"$f\" \"$out\"/", "done", "echo done"), "scripts/prep.sh")
Sys.chmod("scripts/prep.sh", "755")
git = function(...) system2("git", c("-c", "user.name=G2", "-c", "user.email=g2@example.invalid", ...), stdout = FALSE, stderr = FALSE)
git("init", "-q"); for (i in 1:6) { writeLines(sprintf("step %d", i), sprintf("notes%d.txt", i)); git("add", "."); git("commit", "-q", "-m", shQuote(sprintf("Add analysis step %d", i))) }
con = DBI::dbConnect(RSQLite::SQLite(), "data/sales.sqlite"); DBI::dbWriteTable(con, "sales", sales, overwrite = TRUE); DBI::dbDisconnect(con)

# ---- the proposed helpers (prototype; exported by gptr and documented in one system-prompt section) ----
sh = function(cmd, args = character(), wd = ".", timeout = 60) {
  r = processx::run(cmd, args, wd = wd, error_on_status = FALSE, timeout = timeout)
  structure(list(status = r$status, stdout = r$stdout, stderr = r$stderr), class = "gptr_sh")
}
print.gptr_sh = function(x, ...) {
  cat(x$stdout)
  if (nzchar(x$stderr)) cat("[stderr] ", x$stderr, sep = "")
  if (!identical(x$status, 0L)) cat(sprintf("[exit status %d]\n", x$status))
  invisible(x)
}
py = function(code, ...) {                      # R objects passed by name; returns the value of `result` if set
  m = reticulate::import_main(convert = TRUE)
  args = list(...)
  for (nm in names(args)) m[[nm]] = args[[nm]]
  reticulate::py_run_string(code, convert = TRUE)
  if (reticulate::py_has_attr(m, "result")) m$result else invisible(NULL)
}
.sql_con = new.env()
sql = function(query, con = NULL) {
  if (is.null(con)) {
    if (is.null(.sql_con$duck)) .sql_con$duck = DBI::dbConnect(duckdb::duckdb())
    con = .sql_con$duck
  }
  DBI::dbGetQuery(con, query)
}
eng = function(engine, code) {                  # a knitr language engine, output only
  o = knitr::opts_chunk$merge(list(engine = engine, code = code, echo = FALSE, eval = TRUE, results = "markup", comment = NA))
  out = knitr::knit_engines$get(engine)(o)
  cat(gsub("```[a-z]*\n?", "", out), "\n")
  invisible(out)
}
helpers_doc = "<r_helpers>\nPolyglot work goes through R (no bash tool): sh(cmd, args) runs a program without assuming a shell and returns status/stdout/stderr; py(code, ...) runs Python via reticulate with R objects passed by name (set `result` to return a value); sql(query, con) runs SQL through DBI (default: in-memory duckdb, which reads CSV/Parquet paths directly); eng(engine, code) runs a knitr language engine.\n</r_helpers>"

cap = function(code) {
  res = NULL
  out = utils::capture.output({ res = withVisible(eval(parse(text = code), envir = globalenv())) })
  if (res$visible) out = c(out, utils::capture.output(print(res$value)))
  paste(out, collapse = "\n")
}
bash = function(cmd) paste(suppressWarnings(system2("bash", c("-c", shQuote(cmd)), stdout = TRUE, stderr = TRUE)), collapse = "\n")
tasks = list(
  list(name = "shell command: line counts of data files", bash = "wc -l data/*.csv",
       r = "sapply(Sys.glob(\"data/*.csv\"), \\(f) length(readLines(f)))"),
  list(name = "shell script with arguments", bash = "scripts/prep.sh data out",
       r = "sh(\"scripts/prep.sh\", c(\"data\", \"out\"))"),
  list(name = "git: last 5 commits", bash = "git log -5 --oneline",
       r = "sh(\"git\", c(\"log\", \"-5\", \"--oneline\"))"),
  list(name = "Python on an in-memory R object", bash = "python3 -c \"import csv, statistics; r = [float(x['revenue']) for x in csv.DictReader(open('data/sales.csv'))]; print(round(statistics.pstdev(r), 2), round(statistics.median(r), 2))\"",
       r = "py(\"import statistics\\nresult = [round(statistics.pstdev(x), 2), round(statistics.median(x), 2)]\", x = sales$revenue)"),
  list(name = "SQL on SQLite", bash = "sqlite3 -header -column data/sales.sqlite \"SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC\"",
       r = "sql(\"SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC\", DBI::dbConnect(RSQLite::SQLite(), \"data/sales.sqlite\"))"),
  list(name = "SQL on a CSV file (duckdb)", bash = NA_character_,
       r = "sql(\"SELECT month, AVG(price) AS avg_price FROM 'data/sales.csv' GROUP BY month ORDER BY avg_price DESC LIMIT 3\")"),
  list(name = "knitr engine chunk (bash)", bash = "for f in data/*.csv; do echo \"$f $(head -1 $f | tr ',' '\\n' | wc -l)\"; done",
       r = "eng(\"bash\", \"for f in data/*.csv; do echo \\\"$f $(head -1 $f | tr ',' '\\\\n' | wc -l)\\\"; done\")"))
rows = list()
for (tk in tasks) {
  r_out = cap(tk$r)
  b_out = if (is.na(tk$bash)) NA_character_ else bash(tk$bash)
  rows[[length(rows) + 1]] = data.frame(task = tk$name,
    bash_call = if (is.na(tk$bash)) NA else tok_o200k(j(list(command = tk$bash))), bash_result = if (is.na(tk$bash)) NA else tok_o200k(b_out),
    r_call = tok_o200k(j(list(code = tk$r))), r_result = tok_o200k(r_out))
  cat(sprintf("\n## %s\n$ %s\n%s\n> %s\n%s\n", tk$name, tk$bash, if (is.na(b_out)) "(no duckdb CLI installed; n/a)" else b_out, tk$r, r_out))
}
d = do.call(rbind, rows)
cat("\nTokens (o200k): tool-call arguments and result text per task\n"); print(d, row.names = FALSE)
cat(sprintf("\nSums over the tasks both can run: bash %d call + %d result; r %d call + %d result\n",
            sum(d$bash_call, na.rm = TRUE), sum(d$bash_result, na.rm = TRUE), sum(d$r_call[!is.na(d$bash_call)]), sum(d$r_result[!is.na(d$bash_call)])))
bash_def = tok_o200k(j(list(name = "bash", description = pi_tools$bash$description, input_schema = pi_tools$bash$parameters)))
cat(sprintf("Fixed prefix cost: bash tool declaration %d tokens (Pi's schema; Anthropic's own bash tool adds 325) vs <r_helpers> section %d tokens\n",
            bash_def, tok_o200k(helpers_doc)))

# ---- a composed polyglot pipeline: git -> SQL -> Python -> summary, one r call vs four bash calls ----
pipe_r = paste("log = sh(\"git\", c(\"log\", \"--format=%s\"))$stdout |> strsplit(\"\\n\") |> unlist()",
               "rev = sql(\"SELECT region, SUM(revenue) AS rev FROM 'data/sales.csv' GROUP BY region\")",
               "sdev = py(\"import statistics\\nresult = statistics.pstdev(x)\", x = rev$rev)",
               "list(commits = length(log), top_region = rev$region[which.max(rev$rev)], sd_between_regions = round(sdev, 1))", sep = "\n")
pipe_r_out = cap(pipe_r)
pipe_bash = c("git log --format=%s | wc -l",
              "sqlite3 -header -csv data/sales.sqlite \"SELECT region, SUM(revenue) AS rev FROM sales GROUP BY region\" > out/rev.csv && cat out/rev.csv",
              "python3 -c \"import csv, statistics; r=[float(x['rev']) for x in csv.DictReader(open('out/rev.csv'))]; print(statistics.pstdev(r))\"",
              "sort -t, -k2 -nr out/rev.csv | head -1")
pb = vapply(pipe_bash, bash, "")
cat("\n## composed pipeline in one r call\n", pipe_r, "\n", pipe_r_out, "\n", sep = "")
cat("\n## the same with four bash calls\n"); for (i in seq_along(pipe_bash)) cat("$ ", pipe_bash[i], "\n", pb[i], "\n", sep = "")
cat(sprintf("\nPipeline: r = 1 call, %d call + %d result tokens; bash = 4 calls, %d call + %d result tokens (and the results are text, not R objects)\n",
            tok_o200k(j(list(code = pipe_r))), tok_o200k(pipe_r_out), sum(vapply(pipe_bash, function(x) tok_o200k(j(list(command = x))), 1)), sum(vapply(pb, tok_o200k, 1))))
setwd(owd)
tok_save()
````

**`G2/out/e_polyglot.txt`**

````text

## shell command: line counts of data files
$ wc -l data/*.csv
      33 data/cars.csv
    5001 data/sales.csv
    5034 total
> sapply(Sys.glob("data/*.csv"), \(f) length(readLines(f)))
 data/cars.csv data/sales.csv 
            33           5001 

## shell script with arguments
$ scripts/prep.sh data out
cars.csv:       33 lines
sales.csv:     5001 lines
done
> sh("scripts/prep.sh", c("data", "out"))
cars.csv:       33 lines
sales.csv:     5001 lines
done

## git: last 5 commits
$ git log -5 --oneline
60a7394 Add analysis step 6
a900d09 Add analysis step 5
dc4e545 Add analysis step 4
71d2763 Add analysis step 3
3b76b43 Add analysis step 2
> sh("git", c("log", "-5", "--oneline"))
60a7394 Add analysis step 6
a900d09 Add analysis step 5
dc4e545 Add analysis step 4
71d2763 Add analysis step 3
3b76b43 Add analysis step 2

## Python on an in-memory R object
$ python3 -c "import csv, statistics; r = [float(x['revenue']) for x in csv.DictReader(open('data/sales.csv'))]; print(round(statistics.pstdev(r), 2), round(statistics.median(r), 2))"
551.46 1053.79
> py("import statistics\nresult = [round(statistics.pstdev(x), 2), round(statistics.median(x), 2)]", x = sales$revenue)
[1]  551.46 1053.79

## SQL on SQLite
$ sqlite3 -header -column data/sales.sqlite "SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC"
region  revenue   
------  ----------
South   1436746.14
West    1374920.38
North   1366753.6 
East    1294167.04
> sql("SELECT region, ROUND(SUM(revenue), 2) AS revenue FROM sales GROUP BY region ORDER BY revenue DESC", DBI::dbConnect(RSQLite::SQLite(), "data/sales.sqlite"))
  region revenue
1  South 1436746
2   West 1374920
3  North 1366754
4   East 1294167

## SQL on a CSV file (duckdb)
$ NA
(no duckdb CLI installed; n/a)
> sql("SELECT month, AVG(price) AS avg_price FROM 'data/sales.csv' GROUP BY month ORDER BY avg_price DESC LIMIT 3")
  month avg_price
1   Sep  28.16950
2   Mar  27.92250
3   May  27.89166
running: bash  -c "for f in data/*.csv; do echo \"\$f \$(head -1 \$f | tr ',' '\\n' | wc -l)\"; done"

## knitr engine chunk (bash)
$ for f in data/*.csv; do echo "$f $(head -1 $f | tr ',' '\n' | wc -l)"; done
data/cars.csv       12
data/sales.csv        5
> eng("bash", "for f in data/*.csv; do echo \"$f $(head -1 $f | tr ',' '\\n' | wc -l)\"; done")
data/cars.csv       12
data/sales.csv        5
 
Warning message:
call dbDisconnect() when finished working with a connection 

Tokens (o200k): tool-call arguments and result text per task
                                     task bash_call bash_result r_call r_result
 shell command: line counts of data files        10          22     23       17
              shell script with arguments        10          18     19       18
                      git: last 5 commits        11          50     22       50
          Python on an in-memory R object        60           8     42       13
                            SQL on SQLite        39          42     47       35
               SQL on a CSV file (duckdb)        NA          NA     34       34
                knitr engine chunk (bash)        35          15     45       17

Sums over the tasks both can run: bash 165 call + 155 result; r 198 call + 150 result
Fixed prefix cost: bash tool declaration 110 tokens (Pi's schema; Anthropic's own bash tool adds 325) vs <r_helpers> section 105 tokens

## composed pipeline in one r call
log = sh("git", c("log", "--format=%s"))$stdout |> strsplit("\n") |> unlist()
rev = sql("SELECT region, SUM(revenue) AS rev FROM 'data/sales.csv' GROUP BY region")
sdev = py("import statistics\nresult = statistics.pstdev(x)", x = rev$rev)
list(commits = length(log), top_region = rev$region[which.max(rev$rev)], sd_between_regions = round(sdev, 1))
$commits
[1] 6

$top_region
[1] "South"

$sd_between_regions
[1] 50563.6


## the same with four bash calls
$ git log --format=%s | wc -l
       6
$ sqlite3 -header -csv data/sales.sqlite "SELECT region, SUM(revenue) AS rev FROM sales GROUP BY region" > out/rev.csv && cat out/rev.csv
region,rev
East,1294167.04
North,1366753.6
South,1436746.14
West,1374920.38
$ python3 -c "import csv, statistics; r=[float(x['rev']) for x in csv.DictReader(open('out/rev.csv'))]; print(statistics.pstdev(r))"
50563.56576218982
$ sort -t, -k2 -nr out/rev.csv | head -1
South,1436746.14

Pipeline: r = 1 call, 117 call + 34 result tokens; bash = 4 calls, 120 call + 52 result tokens (and the results are text, not R objects)
````

### 5.8 Part (g): truncation, line numbers, edit diffs, plot sizes

**`G2/g_budgets.R`**

````r
# G2 (g): output budgets: tool-result truncation, read line numbers, edit diffs, plot sizes.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
est = function(x, cls) estimate_tokens(x, cls, cpt = fx$cpt_ship, w_cjk = fx$w_cjk, w_other = fx$w_other_ship)
options(width = 100)
co = function(expr) paste(utils::capture.output(expr), collapse = "\n")

# ---------------- 1. truncation of large r results ----------------
set.seed(1)
big_df = data.frame(id = 1:20000, g = sample(letters, 20000, TRUE), x = rnorm(20000), y = runif(20000), d = as.Date("2020-01-01") + 1:20000)
warn_run = function() { for (i in 1:300) warning(sprintf("NAs introduced by coercion in column %d", i)) }
op = options(max.print = 99999); big_print = co(print(big_df)); options(op)
outs = list(
  `print(df) 20k rows (max.print 99999)` = big_print,
  `str(list of 400 models)` = co(str(lapply(1:400, function(i) list(coef = rnorm(3), call = "lm(y ~ x)", r2 = runif(1))))),
  `300 warnings + final error` = paste(c(vapply(1:300, function(i) sprintf("Warning in f(x): NAs introduced by coercion in column %d", i), ""), "Error in solve.default(m): Lapack routine dgesv: system is exactly singular"), collapse = "\n"),
  `summary() of 60 lm fits` = paste(vapply(1:60, function(i) co(print(summary(lm(mpg ~ wt + hp, mtcars[sample(32, 25), ])))), ""), collapse = "\n"))
trunc_pi = function(x, lines = 2000L, bytes = 51200L) {          # Pi: keep the tail
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  keep = utils::tail(l, lines)
  while (sum(nchar(keep, "bytes") + 1L) > bytes) keep = keep[-1]
  paste(c(keep, sprintf("\n[Showing lines %d-%d of %d. Full output: /tmp/pi-bash-1.log]", length(l) - length(keep) + 1L, length(l), length(l))), collapse = "\n")
}
trunc_ht = function(x, lines = 2000L, chars = 50000L) {          # report 12: head 40% + tail 60% of lines/characters
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  if (length(l) <= lines && nchar(x) <= chars) return(x)
  h = character(); t = character(); nh = 0; nt = 0
  for (s in l) { if (nh + nchar(s) + 1 > 0.4 * chars || length(h) >= 0.4 * lines) break; h = c(h, s); nh = nh + nchar(s) + 1 }
  for (s in rev(l)) { if (nt + nchar(s) + 1 > 0.6 * chars || length(t) >= 0.6 * lines) break; t = c(s, t); nt = nt + nchar(s) + 1 }
  paste(c(h, sprintf("[... %d lines omitted; full text in /tmp/gptr-output-1.txt]", length(l) - length(h) - length(t)), t), collapse = "\n")
}
trunc_tok = function(x, budget = 4000L, cls = "r_output") {      # proposed: head 40% + tail 60% of an estimated-token budget
  l = strsplit(x, "\n", fixed = TRUE)[[1]]
  lt = est(l, cls) + 1
  if (sum(lt) <= budget) return(x)
  h = which(cumsum(lt) <= 0.4 * budget); t = which(rev(cumsum(rev(lt))) <= 0.6 * budget)
  paste(c(l[h], sprintf("[... %d of %d lines omitted (~%d tokens); full text: gptr_spill(1) or /tmp/gptr-output-1.txt]", length(l) - length(h) - length(t), length(l), sum(lt) - sum(lt[c(h, t)])), l[t]), collapse = "\n")
}
cat("Large r results, o200k tokens after each truncation rule:\n")
tr_rows = list()
for (nm in names(outs)) {
  x = outs[[nm]]
  cls = if (grepl("warning", nm)) "error" else "r_output"
  tr_rows[[nm]] = data.frame(output = nm, chars = nchar(x), full = tok_o200k(x), pi_tail_2000l_50KB = tok_o200k(trunc_pi(x)),
                             head_tail_2000l_50000c = tok_o200k(trunc_ht(x)), tok_budget_8000 = tok_o200k(trunc_tok(x, 8000L, cls)),
                             tok_budget_4000 = tok_o200k(trunc_tok(x, 4000L, cls)), tok_budget_2000 = tok_o200k(trunc_tok(x, 2000L, cls)))
}
print(do.call(rbind, tr_rows), row.names = FALSE)
x = outs[["300 warnings + final error"]]
cat(sprintf("\nThe final error survives: Pi tail %s, head+tail %s, token budget 2000 %s\n",
            grepl("singular", trunc_pi(x)), grepl("singular", trunc_ht(x)), grepl("singular", trunc_tok(x, 2000L, "error"))))
x = outs[["print(df) 20k rows (max.print 99999)"]]
cat(sprintf("The column header survives: Pi tail %s, head+tail %s, token budget 4000 %s\n",
            grepl("^ +id g", trunc_pi(x)), grepl("id g", substr(trunc_ht(x), 1, 200)), grepl("id g", substr(trunc_tok(x, 4000L), 1, 200))))

# ---------------- 2. read tool with and without line numbers ----------------
rfiles = c(list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto", "\\.R$", full.names = TRUE),
           list.files(file.path(G2, "a_apps"), "\\.(R|html)$", recursive = TRUE, full.names = TRUE))
mdfiles = list.files("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi/packages/coding-agent/docs", "\\.md$", full.names = TRUE)[1:12]
csvfile = file.path(G2, "e_proj/data/sales.csv")
num_cat = function(l) sprintf("%6d\t%s", seq_along(l), l)                 # cat -n / Claude Code Read style
num_bar = function(l) sprintf("%d|%s", seq_along(l), l)                  # compact
num_hash = function(l) sprintf("%d:%s|%s", seq_along(l), substr(vapply(l, function(s) rlang::hash(s), ""), 1, 3), l)   # btw hashline
ln_rows = list()
for (grp in c("R/HTML source", "Markdown", "CSV (first 300 lines)")) {
  fs = switch(grp, `R/HTML source` = rfiles, Markdown = mdfiles, `CSV (first 300 lines)` = csvfile)
  L = lapply(fs, function(f) { l = readLines(f, warn = FALSE); if (grepl("CSV", grp)) utils::head(l, 300) else l })
  txt = function(fun) paste(vapply(L, function(l) paste(fun(l), collapse = "\n"), ""), collapse = "\n")
  base = tok_o200k(txt(identity))
  ln_rows[[grp]] = data.frame(content = grp, files = length(fs), lines = sum(lengths(L)), plain = base,
                              cat_n = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_cat)) / base - 1)),
                              bar = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_bar)) / base - 1)),
                              hashline = sprintf("%+.1f%%", 100 * (tok_o200k(txt(num_hash)) / base - 1)))
}
cat("\nRead results with line numbers (token overhead vs plain text):\n"); print(do.call(rbind, ln_rows), row.names = FALSE)

# ---------------- 3. edit results with and without a diff ----------------
src = file.path(G2, "a_apps"); rev = file.path(G2, "a_revised")
ed_rows = list()
for (f in list.files(rev, "\\.(R|html)$", recursive = TRUE)) {
  a = file.path(src, f); b = file.path(rev, f)
  d3 = suppressWarnings(system2("diff", c("-U3", shQuote(a), shQuote(b)), stdout = TRUE))
  d0 = suppressWarnings(system2("diff", c("-U0", shQuote(a), shQuote(b)), stdout = TRUE))
  d3 = paste(d3[-(1:2)], collapse = "\n"); d0 = paste(d0[-(1:2)], collapse = "\n")
  msg = sprintf("Successfully replaced %d block(s) in %s.", 1L, f)
  ed_rows[[f]] = data.frame(file = f, message_only = tok_o200k(msg), with_diff_U0 = tok_o200k(paste(msg, d0, sep = "\n")), with_diff_U3 = tok_o200k(paste(msg, d3, sep = "\n")))
}
ed = do.call(rbind, ed_rows)
cat("\nEdit tool result for the 20 revisions of part (a) (o200k):\n")
cat(sprintf("  message only: median %.0f | + diff -U0: median %.0f (max %d) | + diff -U3: median %.0f (max %d)\n",
            median(ed$message_only), median(ed$with_diff_U0), max(ed$with_diff_U0), median(ed$with_diff_U3), max(ed$with_diff_U3)))
er = readRDS(file.path(G2, "a_rev_calls.rds"))
cat(sprintf("  for comparison, the edit CALLS themselves (model output): median %.0f tokens\n", median(er$edit_tok)))

# ---------------- 4. plot sizes ----------------
suppressPackageStartupMessages(library(ggplot2))
set.seed(4)
dd = data.frame(x = rnorm(5000), y = rnorm(5000), grp = sample(c("control", "treated", "placebo"), 5000, TRUE))
p = ggplot(dd, aes(x, y, colour = grp)) + geom_point(alpha = 0.5, size = 0.8) + labs(title = "PC1 vs PC2 by treatment group (n = 5,000)", x = "PC1 (23.4%)", y = "PC2 (11.9%)", colour = "Group") + theme_minimal()
claude = function(w, h, max_px = 1568, max_tok = 1568) {          # standard tier; Claude 4.7+/5.x: max_px 2576, max_tok 4784
  s = min(1, max_px / max(w, h))
  repeat { tk = ceiling(w * s / 28) * ceiling(h * s / 28); if (tk <= max_tok) return(tk); s = s * 0.99 }
}
gpt5 = function(w, h) ceiling(ceiling(w / 32) * ceiling(h / 32) * 1.2)
gem25 = function(w, h) if (w <= 384 && h <= 384) 258 else ceiling(w / 768) * ceiling(h / 768) * 258
pl = list()
for (sz in list(c(768, 512, 96), c(768, 512, 120), c(1000, 700, 120), c(1400, 1000, 144))) {
  f = file.path(G2, "out", sprintf("plot_%dx%d_%d.png", sz[1], sz[2], sz[3]))
  ragg::agg_png(f, width = sz[1], height = sz[2], res = sz[3]); print(p); invisible(grDevices::dev.off())
  pl[[f]] = data.frame(size = sprintf("%dx%d @%d", sz[1], sz[2], sz[3]), bytes = file.size(f), claude5x = claude(sz[1], sz[2], 2576, 4784), claude_std = claude(sz[1], sz[2]),
                       gpt5x = gpt5(sz[1], sz[2]), gemini25 = gem25(sz[1], sz[2]), gemini3_default = 1120)
}
cat("\nPlot image cost (tokens) by size; files written to out/ for visual inspection:\n"); print(do.call(rbind, pl), row.names = FALSE)
tok_save()
````

**`G2/out/g_budgets.txt`**

````text
Large r results, o200k tokens after each truncation rule:
                               output   chars   full pi_tail_2000l_50KB head_tail_2000l_50000c
 print(df) 20k rows (max.print 99999) 1040061 598113              29072                  27930
              str(list of 400 models)   10538   5627               5650                   5627
           300 warnings + final error   17367   4817               4841                   4817
              summary() of 60 lm fits   37657  16279              16304                  16279
 tok_budget_8000 tok_budget_4000 tok_budget_2000
            9286            4633            2306
            5627            4230            2130
            4817            3139            1571
            6931            3498            1760

The final error survives: Pi tail TRUE, head+tail TRUE, token budget 2000 TRUE
The column header survives: Pi tail FALSE, head+tail TRUE, token budget 4000 TRUE

Read results with line numbers (token overhead vs plain text):
               content files lines plain  cat_n    bar hashline
         R/HTML source    44  3287 57175 +18.7% +11.5%   +27.1%
              Markdown    12  2177 32186 +25.8% +12.3%   +31.3%
 CSV (first 300 lines)     1   300  4627 +25.9%  +6.5%   +24.2%

Edit tool result for the 20 revisions of part (a) (o200k):
  message only: median 14 | + diff -U0: median 111 (max 330) | + diff -U3: median 191 (max 538)
  for comparison, the edit CALLS themselves (model output): median 124 tokens

Plot image cost (tokens) by size; files written to out/ for visual inspection:
           size  bytes claude5x claude_std gpt5x gemini25 gemini3_default
    768x512 @96 192294      532        532   461      258            1120
   768x512 @120 204317      532        532   461      258            1120
  1000x700 @120 294648      900        900   845      516            1120
 1400x1000 @144 458424     1800       1551  1690     1032            1120
````

### 5.9 Design prototype: usage records, budgets with classed conditions, offline benchmark

**`G2/h_bench.R`**

````r
# G2 prototype: token accounting, budgets that stop with classed conditions, and the offline
# token-efficiency benchmark (golden transcripts replayed through a fake provider; pure R, no tokenizer).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
GPTR_CPT = fx$cpt_ship; GPTR_W_NONASCII = fx$w_other_ship; GPTR_W_CJK = fx$w_cjk

# ---- conditions (dev/plan/00-conventions.md section 5) ----
gptr_abort = function(message, class, ..., call = NULL) {
  stop(structure(class = c(paste0("gptr_error_", class), "gptr_error", "error", "condition"),
                 list(message = message, call = call, ...)))
}
gptr_warn = function(message, class, ...) {
  warning(structure(class = c(paste0("gptr_warning_", class), "gptr_warning", "warning", "condition"),
                    list(message = message, call = NULL, ...)))
}

# ---- usage records: one row per provider request (INFRA-20 fields) ----
usage_record = function(session, agent, provider, model, route, input, output, cache_read = 0, cache_write_5m = 0,
                        cache_write_1h = 0, reasoning = 0, price = NULL, est = NULL) {
  cost = if (is.null(price)) NA_real_ else (input * price$i + output * price$o + cache_read * price$read +
                                           cache_write_5m * 1.25 * price$i + cache_write_1h * 2 * price$i) / 1e6
  data.frame(time = Sys.time(), session, agent, provider, model, route, input, output, cache_read, cache_write_5m,
             cache_write_1h, reasoning, cost, est_prefix = est$prefix %||% NA, est_history = est$history %||% NA,
             est_new = est$new %||% NA)
}

# ---- budgets ----
gptr_budget = function(max_tokens = Inf, max_turns = Inf, max_cost = Inf, max_context = Inf, warn_at = 0.8) {
  structure(list(max_tokens = max_tokens, max_turns = max_turns, max_cost = max_cost, max_context = max_context, warn_at = warn_at), class = "gptr_budget")
}
# called BEFORE each request with the projected size of that request and the usage so far
budget_check = function(b, usage, projected_input) {
  used_tok = sum(usage$input + usage$cache_read + usage$cache_write_5m + usage$cache_write_1h + usage$output)
  used_cost = sum(usage$cost, na.rm = TRUE)
  turns = nrow(usage)
  if (turns >= b$max_turns) gptr_abort(sprintf("Turn budget reached: %d of %d requests.", turns, b$max_turns), "budget_turns", used = turns, limit = b$max_turns)
  if (used_tok + projected_input > b$max_tokens) gptr_abort(sprintf("Token budget: %s used + %s for the next request would exceed %s.", format(used_tok, big.mark = ","), format(projected_input, big.mark = ","), format(b$max_tokens, big.mark = ",")), "budget_tokens", used = used_tok, next_request = projected_input, limit = b$max_tokens)
  if (used_cost >= b$max_cost) gptr_abort(sprintf("Cost budget reached: $%.4f of $%.4f.", used_cost, b$max_cost), "budget_cost", used = used_cost, limit = b$max_cost)
  if (projected_input > b$max_context) gptr_abort(sprintf("Context budget: next request ~%s tokens > %s; compact or fork.", format(projected_input, big.mark = ","), format(b$max_context, big.mark = ",")), "budget_context", next_request = projected_input, limit = b$max_context)
  if (used_tok + projected_input > b$warn_at * b$max_tokens) gptr_warn(sprintf("%.0f%% of the token budget used.", 100 * (used_tok + projected_input) / b$max_tokens), "budget_near")
  invisible(TRUE)
}

# ---- per-section estimates of a request (what gptr can compute before sending) ----
msg_text = function(m) vapply(m$content, function(b) switch(b$type, text = b$text, tool_use = j(b$input), tool_result = b$content, ""), "")
msg_class = function(m) vapply(m$content, function(b) switch(b$type, text = "prose", tool_use = "code",
                        tool_result = if (grepl("^\\s*[{\\[]", b$content)) "json" else "r_output", "prose"), "")
img_tokens = function(m) sum(vapply(m$content, function(b) if (identical(b$type, "tool_result") && length(b$images)) sum(vapply(b$images, function(wh) ceiling(wh[1] / 28) * ceiling(wh[2] / 28), 1)) else 0, 1))
est_msg = function(m) sum(estimate_tokens(msg_text(m), msg_class(m))) + img_tokens(m) + 8L * length(m$content)   # + per-block JSON wrapper
prefix_est = function(tools, system) sum(estimate_tokens(c(system, j(lapply(tools, function(t) list(name = t$name, description = t$description, input_schema = t$parameters)))), c("prose", "json")))

# ---- fake provider: replays a golden transcript; its "usage" is the estimator's count (deterministic) ----
replay = function(tr, tools, system, budget = gptr_budget(), price = list(i = 2, o = 10, read = 0.2)) {
  pre = prefix_est(tools, system)
  usage = usage_record("s", "main", "fake", "fake-1", "api", 0, 0)[0, ]
  hist = 0; prev_input = 0
  for (i in seq_along(tr$messages)) {
    m = tr$messages[[i]]
    if (m$role != "assistant") { hist = hist + est_msg(m); next }
    projected = pre + hist
    budget_check(budget, usage, projected)
    out = est_msg(m)
    rd = if (prev_input >= 512) prev_input else 0
    usage = rbind(usage, usage_record("s", "main", "fake", "fake-1", "api", input = projected - rd, output = out, cache_read = rd,
                                      price = price, est = list(prefix = pre, history = hist, new = 0)))
    prev_input = projected
    hist = hist + out
  }
  usage
}

# ---- the benchmark: metrics per golden transcript, compared with a stored baseline ----
bench_tokens = function(transcripts, tools, system) {
  do.call(rbind, lapply(transcripts, function(tr) {
    u = replay(tr, tools, system)
    data.frame(case = sprintf("task%d_%s", tr$task, tr$style), requests = nrow(u), prefix = prefix_est(tools, system),
               input_total = sum(u$input + u$cache_read), output_total = sum(u$output), cost_cached = round(sum(u$cost), 5))
  }))
}
bench_compare = function(res, baseline, tol = c(prefix = 0.02, input_total = 0.05, output_total = 0.05, requests = 0, cost_cached = 0.05)) {
  b = baseline[match(res$case, baseline$case), ]
  bad = list()
  for (k in names(tol)) {
    over = res[[k]] > b[[k]] * (1 + tol[[k]])
    if (any(over, na.rm = TRUE)) bad[[k]] = sprintf("%s: %s %s -> %s (+%.1f%%, tolerance %.0f%%)", res$case[over], k, b[[k]][over], res[[k]][over], 100 * (res[[k]][over] / b[[k]][over] - 1), 100 * tol[[k]])
  }
  if (length(bad)) gptr_abort(paste(c("Token-efficiency regression:", unlist(bad)), collapse = "\n  "), "token_regression", details = bad)
  invisible(TRUE)
}

TR = readRDS(file.path(G2, "d_transcripts.rds"))$TR
tools7 = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
sys7 = gptr_prompt(names(tools7))
t0 = Sys.time()
base = bench_tokens(TR, tools7, sys7)
cat(sprintf("Baseline over %d golden transcripts computed in %.2f s (pure R, no tokenizer):\n", length(TR), as.numeric(Sys.time() - t0, units = "secs")))
print(base, row.names = FALSE)
jsonlite::write_json(base, file.path(G2, "out/bench_baseline.json"), dataframe = "rows", digits = NA, pretty = TRUE)
base = jsonlite::read_json(file.path(G2, "out/bench_baseline.json"), simplifyVector = TRUE)
cat("\n1) unchanged harness:", tryCatch(bench_compare(bench_tokens(TR, tools7, sys7), base), error = function(e) conditionMessage(e)), "\n")
fat = tools7; fat$r$description = paste(fat$r$description, strrep("Always explain your reasoning in detail before running code. ", 12))
r2 = tryCatch(bench_compare(bench_tokens(TR, fat, sys7), base), gptr_error_token_regression = function(e) e)
cat("\n2) r tool description grew by 12 sentences -> condition class:", paste(class(r2), collapse = ", "), "\n", substr(conditionMessage(r2), 1, 600), "\n")
cat("\n3) budgets during a replay of task 6 (style S):\n")
for (b in list(gptr_budget(max_tokens = 40000), gptr_budget(max_turns = 5), gptr_budget(max_context = 3500), gptr_budget(max_cost = 0.03))) {
  r = withCallingHandlers(tryCatch({ replay(TR[[12]], tools7, sys7, budget = b); "completed" }, gptr_error = function(e) paste0("[", class(e)[1], "] ", conditionMessage(e))),
                          gptr_warning_budget_near = function(w) invokeRestart("muffleWarning"))
  cat("  ", r, "\n")
}
u = replay(TR[[12]], tools7, sys7)
cat(sprintf("\nUsage records (task 6 S, fake provider): %d rows; columns: %s\n", nrow(u), paste(names(u), collapse = ", ")))
print(utils::head(u[, c("input", "output", "cache_read", "cost", "est_prefix")], 4), row.names = FALSE)
````

**`G2/out/h_bench.txt`**

````text
Baseline over 13 golden transcripts computed in 0.13 s (pure R, no tokenizer):
          case requests prefix input_total output_total cost_cached
       task1_S        7   2706       23536          319     0.01553
 task1_S-quiet        7   2706       22092          334     0.01470
       task1_C        2   2706        5922          217     0.00904
       task2_S        7   2706       22890          269     0.01387
       task2_C        2   2706        5871          159     0.00833
       task3_S       12   2706       44941          425     0.02418
       task3_C        6   2706       19634          271     0.01559
       task4_S        4   2706       13744          424     0.01548
       task4_C        2   2706        7070          348     0.01262
       task5_S        5   2706       58774          194     0.04044
       task5_C        2   2706        6530          289     0.01102
       task6_S       16   2706       83044          564     0.03611
       task6_C        9   2706       28302          471     0.01683

1) unchanged harness: TRUE 

2) r tool description grew by 12 sentences -> condition class: gptr_error_token_regression, gptr_error, error, condition 
 Token-efficiency regression:
  task1_S: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task1_S-quiet: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task1_C: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task2_S: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task2_C: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task3_S: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task3_C: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task4_S: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task4_C: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task5_S: prefix 2706 -> 2959 (+9.3%, tolerance 2%)
  task5_C: prefix 2706 -> 2959 (+9. 

3) budgets during a replay of task 6 (style S):
   [gptr_error_budget_tokens] Token budget: 34,739 used + 6,356 for the next request would exceed 40,000. 
   [gptr_error_budget_turns] Turn budget reached: 5 of 5 requests. 
   [gptr_error_budget_context] Context budget: next request ~4,073 tokens > 3,500; compact or fork. 
   [gptr_error_budget_cost] Cost budget reached: $0.0316 of $0.0300. 

Usage records (task 6 S, fake provider): 16 rows; columns: time, session, agent, provider, model, route, input, output, cache_read, cache_write_5m, cache_write_1h, reasoning, cost, est_prefix, est_history, est_new
 input output cache_read      cost est_prefix
  2749     31          0 0.0058080       2706
    43     35       2749 0.0009858       2706
    47     29       2792 0.0009424       2706
    53     30       2839 0.0009738       2706
````


## 6. CRAN and cross-platform (Windows) considerations

- **Estimator.**
  - It is base R: `nchar()` and `gsub(perl = TRUE)` with Unicode classes. It needs a UTF-8-capable R. R ≥ 4.2
    on Windows uses UCRT UTF-8 (conventions §4, R floor 4.2).
  - `enc2utf8()` is applied before counting.
  - **Locale caveat** (found in verification). In a non-UTF-8 locale, such as the C/POSIX locale that some
    Linux containers, CI runners and `Rscript` with `LANG` unset use, `enc2utf8()` does not re-mark strings of
    "unknown" encoding.
    - `nchar()` then counts bytes, and the CJK regex does not match.
    - Example: `"abc 你好世界"` read by `readLines()` without `encoding = "UTF-8"` estimates at 12 tokens
      instead of 5.
    - The error is an overestimate, so it is conservative.
    - Producers should mark text as UTF-8 at the source: `readLines(encoding = "UTF-8")`, jsonlite, httr2 and
      processx output decoded as UTF-8. Strings that are already UTF-8-marked are counted correctly in any
      locale.
  - The package ships no tokenizer vocabulary, avoiding CRAN's 5 MB data guideline (report 21: rtiktoken is
    13.2 MB installed).
  - The constants are code, not data.
- **Benchmark tests.**
  - They are offline and fast (0.13-0.24 s), with no network, keys, processes or temporary files beyond
    `withr::local_tempdir()`.
  - Fixtures are JSON, written with `writeLines(enc2utf8(x), con, useBytes = TRUE)` in binary mode (conventions
    §6), so Windows adds no CR.
  - Keep them under `skip_on_cran()`. They are deterministic, but a legitimate prompt change must not become a
    CRAN failure.
- **Live mode.** It is gated by `GPTR_LIVE_TESTS` (conventions §7). The count-token endpoints need keys, so
  there are no CRAN examples. `@examplesIf` uses the fake provider for `gptr_usage()` and `gptr_budget()`.
- **Spill files and calibration cache.**
  - Spill files go in the session directory: `.gptr/sessions/<id>/spill/` when the user created `.gptr/`,
    otherwise `tempdir()`. They are removed with the session.
  - The optional calibration cache lives in `tools::R_user_dir("gptr", "cache")`, stays small and is actively
    managed (report 17's CRAN proviso).
- **Polyglot helpers on Windows.**
  - `sh()` uses `processx::run(cmd, args)` without a shell, so no POSIX shell is assumed (REQ-03). Shell syntax
    such as globs and pipes must go through R or an explicit `sh("cmd.exe", c("/c", ...))` or
    `sh("powershell", ...)`.
  - The knitr bash engine needs bash (Git for Windows).
  - `py()` needs a Python that reticulate can find. Set `RETICULATE_USE_MANAGED_VENV = "no"`, or document it, so
    gptr never triggers a download (reticulate 1.46 can provision Python with uv; I prevented this here with
    `RETICULATE_PYTHON`).
  - SQL through DBI works everywhere. The `sqlite3` CLI and a duckdb CLI are usually absent on Windows.
- **Plots.** Use `ragg::agg_png` when installed; otherwise `grDevices::png(type = "cairo")` on Linux without X11
  (report 12 §3.5). Windows `png()` works. Pixel sizes are platform-independent; the text rendering at res 120
  was checked on macOS only.
- **Artifacts checker (dev only).** chromote needs Chrome or Edge. On Windows set `CHROMOTE_CHROME`
  (report 17). The part-(a) ladder was run only on macOS.

## 7. Risks and open questions

**Risks**
1. **Author bias in part (a).**
   - I wrote all 20 apps, and both sides deliberately use idiomatic, compact code.
   - Model-written Shiny may be longer: modules, CSS and comments.
   - Model-written HTML may be much longer if it is dependency-free.
   - I used no paid model calls to sample real generations. The ratio (2.35x) is therefore a design estimate.
     Report 17's 3.1-3.7x and my 1.02-4.32x pair range bracket it.
2. **Constructed transcripts.**
   - The golden transcripts' tool results are real, but the agent behaviour in both styles was scripted by me.
   - Real models may compose less, or print more. The S/C ratios measure the harness-controlled potential,
     not observed model behaviour.
   - The S transcripts omit Seurat progress bars, so S is understated.
3. **Tokenizer uncertainty.**
   - Claude (1.3-1.6x o200k) and Gemini (unknown) affect absolute budgets.
   - The shipped constants are o200k-fitted. On cl100k the total bias is already -13%.
   - Recalibration shrinks the error on new content, but per-message variance remains: p90 of 32-45%.
   - Caps must therefore stay conservative: the token caps overshot by up to 16%.
4. **The lean prompt is unevaluated.** Shorter tool descriptions could change model behaviour: edit uniqueness
   rules, the r tool's safety rules. The lean texts keep the edit uniqueness rule and move the r rules into the
   prompt, but the effect is untested.
5. **Cache pricing model.** It assumes:
   - no TTL expiry between the steering prompts;
   - that every new tail is written to the cache;
   - no 128-token rounding for OpenAI.

   Gemini implicit caching needs a 4,096-token prefix. The lean prefix (1,153) is not cached on Gemini until
   the context grows, and on OpenAI it is just over the 1,024 minimum.
6. **Describer facts are regex-checked.** A fact counted as present may be phrased unhelpfully, and the fact
   list is mine. The ALTREP size fix uses a heuristic, or lobstr when installed.
7. **rtiktoken is slow** (0.3-0.4 s per call, because the encoder is rebuilt each time). This matters only for
   `dev/bench` runtime; memoise, as `G2/tok.R` does.
8. **Corpus coverage.**
   - Russian and other non-CJK non-ASCII scripts are thin, so the 0.35 floor comes from report 21.
   - Real agent sessions may carry more ANSI-stripped cli output, which was not sampled.
9. **External data.** The GitHub MCP tool snapshots were fetched from the public repository at commit
   `85598ba`. The corpus changes over time; pin the commit in `dev/bench`.

**Open questions**
1. Default r-result cap: 4,000 (recommended) or 8,000 estimated tokens? The choice trades the model re-reading
   spill files against context use. It should be decided by live A/B on the north-star tasks.
2. Should the Claude multiplier prior be 1.35 or 1.5? The June 2026 study suggests 1.6x o200k for English on
   Opus 4.8. Live mode should measure this per model with `count_tokens` before 1.0.
3. Should the class-specific feature estimator (6.9% median error) replace the class ratios (11.4%) once it has
   been re-fitted on a larger corpus with non-negative constraints?
4. Gemini 3 `media_resolution` for plots: should low (280) or medium (560) be the default for plot images?
   Legibility is untested.
5. Artifact screenshot size: are 960x640 screenshots (805 Claude tokens) legible enough for the model to catch
   render errors? Report 17 used 1100x750.
6. Read line numbers: should they be enabled per model family, given evidence that some families edit better
   with them? This needs evals, which were not possible here.
7. Should `gptr_usage()` persist across R sessions (a project-level spend report), and where? `.gptr/`, with consent.
8. Should composition ever be enforced, for example by warning when a turn issues more than N consecutive
   single-line `r` calls? Or should it stay a prompt rule only?

## 8. Sources

Local research reports (each closing verification log overrides its body), in `/Users/wanjun/Desktop/gptr/dev/research/`:
- 01 §3.1-§3.10, §5.10 (Pi tools and prompts, gptr 7-tool prompt).
- 02 §2.10 (Pi compaction; reserve 16,384, keepRecent 20,000).
- 04 §2.5 and 04a (Jev price $0.042/MTok, live request of 443 input tokens).
- 05 §4.7 (skills budget, 37 skills = 23,552 characters).
- 06 §3.6, §4.5 (codemode, 3,000-token declarations).
- 07 §1 item 15, §2.1, §2.7, §3.5, §3.13 (Claude prices, caching, CLI isolation).
- 08 §1 item 6, §3.1, §3.7 (Codex overhead, namespace tools, OpenAI prices).
- 09 (Gemini usage fields).
- 10 §5.3 (bounded describer, btw 46k-character schema).
- 10a INFRA-20.
- 11 (line numbers +18.6%).
- 12 §3.1, §3.4, §3.5, §3.9, §4.2 (r tool, truncation, describe contract).
- 16 §2.16, §4.7, §5.14 (MCP context cost).
- 17 §2.8, §2.9, §3.2, §3.3, §4.4 (plots, Shiny vs HTML, artifact tool, image formulas).
- 19 §3.1 (`<r_performance>`).
- 20 §3.4, §4.1, §4.2 (apply_patch grammar, tool table, prompt outline).
- 21 §2.8 (chars/4 bias, report-21 rule).
- Spec: 00-vision-brief (REQ-42), 01-decision-register (S-1..S-12, D-03, D-19), 02-north-star-examples,
  plan/00-conventions.

Prototype sources reused unchanged:
- `scratchpad/work/12/gptr_introspect.R` (report 12).
- `scratchpad/work/track-01/proto/*.R` (report 01).
- `scratchpad/work/16/proto/mcp_client_stdio.R` (report 16).
- `scratchpad/work/17/run2/art_session_check.R` technique (report 17).

Web (fetched 2026-09-29/30):
- Anthropic pricing (models, cache multipliers, tool-use system prompt tokens, tokenizer note):
  https://platform.claude.com/docs/en/about-claude/pricing
- Anthropic token counting (free, estimate, 4.7+ tokenizer ~30% more tokens):
  https://platform.claude.com/docs/en/build-with-claude/token-counting
- OpenAI pricing: https://developers.openai.com/api/docs/pricing
- OpenAI prompt caching (1,024-token minimum, 0.1x / 0.05x read, 1.25x write):
  https://developers.openai.com/api/docs/guides/prompt-caching
- OpenAI input token counting: https://developers.openai.com/api/docs/guides/token-counting and
  https://developers.openai.com/api/reference/python/resources/responses/subresources/input_tokens/methods/count
  (LIKELY, search summary)
- Gemini pricing: https://ai.google.dev/gemini-api/docs/pricing
- Gemini caching (implicit caching, 4,096-token minimum on 3.x): https://ai.google.dev/gemini-api/docs/caching
- Claude vs GPT tokens per word (June 2026, one passage):
  https://dev.to/savi444/tokens-per-word-gpt-5-vs-claude-vs-gpt-4-measured-across-7-languages-4419
- Opus 4.7 vs 4.6 token counts: https://simonwillison.net/2026/Apr/20/claude-token-counts/
- tiktoken encodings (o200k for GPT-5 family): https://github.com/openai/tiktoken/blob/main/tiktoken/model.py
  (search result summary; GPT-5.5/6 mapping UNCERTAIN)
- GitHub MCP server tool snapshots: https://github.com/github/github-mcp-server/tree/main/pkg/github/__toolsnaps__
  (commit `85598ba6e1256f7ebf4867b95d63b833c4549264`, 2026-09-16)

Local executions:
- `claude mcp serve`: `tools/list` handshake only; CLI 2.1.261.
- python3 3.14.7, `/usr/bin/sqlite3`, git, Seurat 5.4.0, SeuratObject `pbmc_small`, nlme, RSQLite 2.4.6,
  duckdb 1.5.0, reticulate 1.46.0, chromote 0.5.1, shiny 1.13.0, bslib 0.10.0, DT 0.34.0, plotly 4.12.0.

## Verification log

Adversarial fact-check, 2026-09-29. Method:
- Every re-run R prototype was run with `Rscript --vanilla` on R 4.4.3, with the private library first. Each
  ran in an isolated copy of `G2/` (`scratchpad/work/verify-G2/G2c/`) with an **empty token cache**, so every
  o200k/cl100k count was recomputed by rtiktoken.
- Outputs were diffed against the original `G2/out/`. Pi facts were checked in the Pi clone at commit
  `1b34779`.
- Web facts come from the vendors' current documentation, fetched 2026-09-29.
- Edits made in the body are marked "verification".

| # | Claim | Verdict | Source / evidence |
|---|---|---|---|
| 1 | HTML/JS costs 2.35x the o200k tokens of Shiny over 20 apps; cl100k 2.31x; per level 1.62-2.86x; pair range 1.02-4.32x; slopes +80 / +57 per level; JSON escaping +24.7% / +17.1% | CONFIRMED | `a_tokens.R` re-run with a fresh token cache: output byte-identical to `a_tokens.txt` |
| 2 | Inlined data costs "33 tokens per row, linear in rows" (50,000 rows = 1,651,123) | **CORRECTED** to 25.4 tokens per row as row JSON (1,271,112 for 50,000 rows) | The 50,000-row copy `sales[rep(...), ]` had row names like `"1.1"`, so `toJSON()` added `"_row"` to every record (checked by printing the JSON). With default row names: 1,271,112 = 25.42 per row, the same as 100, 1,000 and 5,000 rows. Fixed in §1, the §2.1 table and §4.11. |
| 3 | 20/20 apps pass the four-step ladder; 10/10 mutants fail it; 20/20 revised apps pass | CONFIRMED | `a_check.R` re-run on the originals (PASS 20 of 20), mutants (PASS 0 of 10) and revisions (PASS 20 of 20), with headless Chrome through chromote 0.5.1. `a_mutants.R` and `a_revisions.R` regenerate byte-identical files, and `a_revisions.txt` is identical (rewrite/edit 3.9x and 6.1x). |
| 4 | Prefix sizes: Pi 919 (1,175 with `<docs>`), gptr-7 2,096, gptr-10 2,816, gptr-11 3,570, lean rewrite 1,153; per-tool costs | CONFIRMED | `b_presets.R` and `b_lean.R` outputs identical. Pi's read and bash descriptions match `read.ts:76` and `bash.ts:258`, and its prompt text matches `system-prompt.ts:95-160` (tool guidelines `read.ts:22`, `bash.ts:47`). |
| 5 | OpenAI strict mode +5% to +7%; strict / namespace deltas +112-274 / +19-25 | **CORRECTED** | Recomputed from `b_presets.txt`: strict adds +48 to +274 tokens (+3.4% to +8.0% over plain Responses; +136 and +6.4% for gptr-7), and namespace wrapping adds +24 in every preset. Fixed in §1, §4.6 and §4.11. |
| 6 | Anthropic adds 286 tool-use system tokens on Opus and Sonnet 5.5; the server bash tool adds 325 (Opus 5 and 4.8) | CONFIRMED, made more precise | Anthropic pricing page. 286 is the auto/none figure (no any/tool figure is listed for 5.5). The bash tool costs 325 on Opus 5, 4.8 and 4.7 and 244 on 4.6 and earlier; no 5.5 figure is listed. |
| 7 | Prices (USD/MTok): Sonnet 5.5 2/10/0.20/2.50; Opus 5.5 4/20/0.20/5; GPT-6.1 Sol 2/10/0.10/2.50; Gemini 3.8 Flash 0.75/3.75/0.075 | CONFIRMED, caveat added | Anthropic and OpenAI pricing pages and the Gemini pricing page (`.md.txt`). Gemini 3.8 Flash prices are promotional through 2026-12-31 and double on 2027-01-01. Opus 5.5 and GPT-6.1 Sol cache reads are 0.05x. Caveat added under the §2.4 price table; the §4.6 "0.05-0.1x" was corrected to 0.025-0.1x. |
| 8 | Cache minimums: Anthropic 512, OpenAI 1,024, Gemini 4,096 | CONFIRMED | Anthropic prompt caching: 512 for Opus 5.5, Sonnet 5.5 and the other 5.x models. OpenAI prompt caching: 1,024 visible tokens for GPT-5.6 and later, which report exact (unrounded) cached tokens. Gemini caching: 4,096 for 3.5-3.8 Flash and 3.1 Pro. |
| 9 | "Claude 4.7 and later ... newer tokenizer ... approximately 30% more tokens"; dev.to 1.17 / 1.24 / 1.88 tokens per word; Willison 1.46x | CONFIRMED; the bound for code downgraded to UNCERTAIN | Anthropic pricing and token-counting pages, dev.to article, simonwillison.net. Neither source measured Claude on code. The dev.to non-English rows reach 2.04x o200k (German, Opus 4.8). Noted in §2.8. |
| 10 | Count endpoints: Anthropic free (an estimate); OpenAI `POST /v1/responses/input_tokens` LIKELY | Anthropic CONFIRMED; OpenAI endpoint upgraded to VERIFIED; "free" for OpenAI and Gemini downgraded to UNCERTAIN | Anthropic token-counting page ("free to use", "estimate"). OpenAI token-counting guide (endpoint shown, no price stated). Gemini tokens guide (`countTokens`, no price stated). Fixed in §1, §2.8 and §4.10. |
| 11 | Estimator: 481 held-out chunks, cpt table, median absolute error 11.4% / p90 32.3% / bias -3.4%, feature models 11.0% / 6.9%, recalibration 30% to 19% (Claude-like), whole-context error 0.29-0.37% | CONFIRMED | `f_corpus.R` rebuilt an `identical()` corpus. `f_count.R` produced `identical()` counts from a fresh cache. `f_calibrate.R` and `f_features.R` outputs are identical except timings; `f_recal.R` output is identical. |
| 12 | The §3.2 `gptr_tokens()` reference code matches the prototype with the shipped constants | CONFIRMED, with a new caveat | The §3.2 block was extracted verbatim and run on all 897 corpus chunks: `all.equal()` with `estimate_tokens(cpt = cpt_ship, w_cjk = 0.848, w_other = 0.35)` is TRUE. In a C locale, unmarked UTF-8 strings are counted by bytes (12 instead of 5 tokens for `"abc 你好世界"`). Added to §6. |
| 13 | Speed: estimator 66 ms per MB; rtiktoken 277-335 ms per call; bench 0.13 s | **CORRECTED** (load-dependent) | The original `f_calibrate.txt` itself says 55.9 ms and 210 ms; the re-run gives 34 ms and 128 ms. rtiktoken timing script: about 0.13 s per call, and 6.2 s for 50 strings vectorised vs 6.3 s looped. The bench took 0.24 s in the re-run. Ranges fixed in §1, §2.6, §4.10 and §6. |
| 14 | Composition: S/C 2.22x requests, 3.63x input, cost 3.33x / 2.02x (Sonnet 5.5), 1.87x (GPT-6.1 Sol), 2.15x (Gemini); prefix 78% of C input; Jev vs System 2 about 100-370x | CONFIRMED | `d_tasks.R` regenerated `d_transcripts.rds` `identical()` from Seurat 5.4.0 / nlme / base R. `d_compose.R` output identical. The exec-summary verbosity sentence was reworded (3.6% of S input is 4.7% of the S-C gap). |
| 15 | Pi admits 29,072 tokens for one printed data frame (tail cut 2,000 lines / 50 KB); a 4,000 cap gives ≤ 4,633; line-number and edit-diff costs; plot image costs | CONFIRMED | `g_budgets.R` output identical. Pi `truncate.ts:11-12` (2000 lines, 50 x 1024 bytes); bash uses `truncateTail` (`output-accumulator.ts:99`). Claude image formula `⌈w/28⌉ x ⌈h/28⌉`, caps 1,568 / 4,784: Claude vision docs. |
| 16 | Image formulas: GPT-5.x `ceil(w/32) * ceil(h/32) * 1.2`; Gemini 3 media_resolution 280 / 560 / 1,120 | CONFIRMED with scope limits | OpenAI images-vision guide: the patch x1.2 rule covers gpt-5.2+, gpt-5.4/5.5/5.6 and gpt-6-astra. gpt-5 and gpt-5.1 are tile-based (70 + 140 per tile). gpt-6.1-sol is not listed (UNCERTAIN). Gemini media-resolution guide. Note added in §3.1. |
| 17 | MCP catalogs (GitHub 50: 11,361 vs 2,285; Claude Code 29: 31,706) and skills catalogs (Pi XML 94 per skill, compact 33) | CONFIRMED | `b_catalogs.R` and `b_skills.R` outputs identical. GitHub commit `85598ba` exists, dated 2026-09-16 (public API, unauthenticated), and the corpus holds 125 snapshots. The XML per-skill cost is 92.6 at 157 skills and 94.8 at 10. |
| 18 | Describers: report 12 at 3.5 chars/token overruns 12/20 at budget 50; describe2 keeps 73.5 / 90.8 / 99.0% of facts; `object.size(1:1e9)` = 4,000,000,048 | CONFIRMED, limits added | `c2_describe.R` output matches except `str()` at 2,990 vs 2,992 tokens (environment-address variance). `gptr_introspect.R:30-32` uses 3.5. At budget 150 describe2 still misses the Seurat-like meta.data dims, columns and assay, and nested[deep] even at 600. Noted in §2.3. |
| 19 | Offline bench detects a +9.3% prefix regression with class `gptr_error_token_regression` | CONFIRMED | `h_bench.R` output identical except the timing line. |
| 20 | Polyglot: helper doc 105 tokens vs bash declaration 110; per-command table; the pipeline takes 1 vs 4 round trips | Prefix figures CONFIRMED; the per-command table was NOT re-run | 105 and 110 were recounted with rtiktoken. `e_polyglot.R` was not re-run because it creates a git repository and commits to it, which this verification's no-git rule excludes. Its figures stand on the original `e_polyglot.txt`. |
| 21 | Cited facts: Jev $0.042/MTok with free output, and the 443-token live request (04/04a); Claude CLI 18.4K down to 12-27 tokens (07); Codex 38,544 / 19,324 (08); report 17's 3.1-3.7x; report 11's +18.6%; report 21's Cyrillic 0.30 / German 0.27 and rtiktoken 13.2 MB | CONFIRMED against the cited reports | grep of reports 04, 04a, 07, 08, 11, 17 and 21. rtiktoken 0.0.7 measures 13.23 MB installed. dbplyr 2.5.1 exports `sql()`. reticulate 1.46.0 documents `RETICULATE_USE_MANAGED_VENV="no"`. |

**Still unverifiable here:**
- The behaviour of the lean prompt: it needs model calls.
- Gemini's tokenizer ratio.
- The Claude-to-o200k ratio on code.
- Whether the OpenAI and Gemini count endpoints are free.
- The multiplier for gpt-6.1-sol images.
- Model-written (rather than author-written) Shiny and HTML sizes.
