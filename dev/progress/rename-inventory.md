# D-135 rename inventory: `gptr()` -> `peter()`, `gptr$` -> `peter$`

Read-only survey of HEAD `2425843` (plus copies of the uncommitted P11/P17 work-in-progress files).
Nothing in the repository was edited. Scratch artifacts next to this file:

| File | What it is |
|---|---|
| `dev/progress/rename/rename.py` | the mechanical pass (7 context-free regex rules, byte-preserving, skips lines that already say `peter`) |
| `dryrun.log`, `dryrun-perfile.md` | what `dev/progress/rename/rename.py` changes on HEAD, per file and rule (3,999 replacements in 125 files) |
| `residue.txt` | 310 lines left for manual review after the mechanical pass (includes expected keeps) |
| `long-lines.txt`, `plan-long-lines.txt` | 13 code lines and 23 plan R-block lines that cross the 100-column lint limit after the pass |
| `full/` | HEAD + mechanical pass + `export(peter)` + "the peter object", used to measure token counts |
| `idx-head/`, `idx-new2/` | cross-plan index on HEAD and on the renamed tree (0 new error/warn findings) |

## 1. The one rule

Rename only text and code that **names the callable or its `$` namespace**: `gptr(` -> `peter(`,
`gptr$member` / `gptr[["member"]]` -> `peter$...`, `gptr::gptr` -> `gptr::peter`, the symbol `gptr` where it
means the gateway (`class(gptr)`, `quote(gptr)`, `"gptr"` compared with a call head), and phrases that name
that object ("the gptr object", "gptr member", "gptr namespace"). Everything branded by the package stays:
package name, `library(gptr)`, `gptr::`, `gptr_*` exports, `gptr.*` options, `.gptr/`, `GPTR_*`,
`gptr_error_*`, S3 classes (`gptr_gateway`, `gptr_ns`, ...), file names `R/gptr-*.R` and
`test-gptr-*.R`, block markers `# >>> gptr:<id>`, chunk labels/cell ids `gptr-<id>`, notebook
`metadata.gptr`, JSONL entry field `gptr` (`e$gptr$turn`, `[["gptr"]]`), the `<gptr>` srcfile, the
`gptr` MCP server name, keyring service `"gptr"`, `R_user_dir("gptr", ...)`, User-Agent `gptr/x.y`, event
origin `"gptr"`, `plugin.json` `"gptr": {"api": ...}`.

No back-compat: 1.0 is unreleased, so the document scanner recognises only `peter(...)`; old `gptr(...)`
lines in user documents are not recognised (re-record them). No alias `gptr = peter` is kept.

### Decisions the maintainer should confirm (recommended default first)

- **D1 Extension factories keep `function(gptr)`.** The factory argument is a different object
  (`gptr_extension_api`, contract 10.5: `$register*`, `$on`, `$state`, `$require`, `$has`, `$name`,
  `$dir`). Keeping it avoids about 600 more edits (P02 plan 51 factories / 66 API calls, test-ext-load 42/59,
  21 `builtin_*` factories in R/) and keeps the two objects visibly distinct. Nothing checks the formal's
  name except `test-s1-route.R:914` (`names(formals(factory)) == "gptr"`), which stays.
- **D2 Agent persona "You are gptr," stays** (`R/prompt-text.R:59,66`, architecture 7.3). Package identity;
  changing it saves 1 o200k token per preamble. Maintainer's call.
- **D3 UI text naming the namespace object becomes `peter`** (it names the callable): print headers
  `<gptr gateway> ...` (`R/gptr-gateway.R:328`, snapshot) -> `<peter gateway>`, `<gptr namespace peter$x...>`
  (`R/tool-namespace.R:741`) -> `<peter namespace ...>`, `"<gptr member>"` (482), "is not a gptr member" (638),
  "gptr namespaces are read-only." (682, 689), help/search descriptions "a gptr member"/"gptr members" (1653,
  1663), r_session helpers "R functions on the gptr object" (1642, model-facing) -> "on peter". Alternative:
  keep the labels; then only the `gptr$`/`gptr(` inside them change.
- **D4 Console prompt** `gptr> ` / `gptr[auto]> ` (P14 plan only, not implemented): keep, or `peter> `.
  Recommend deciding now because P14 has not started (28 plan lines).
- **D5 Internal names stay** (`gptr_shim`, `user_log_gptr_head`, env-history kind label `"gptr"`, perm-classify
  kind `"gptr"` in `risk_proc_flags()`): they are not user-visible; only their doc comments change.
- **Name collision note for `?peter`** (no code): `peter` is a plausible user object name. The P09 shim does
  not rewrite when `exists("peter", envir)` (any mode), and a user object `peter` shadows the gateway's
  `peter$...` for model code; one sentence in `?peter` ("an object named `peter` hides the gateway; use
  `gptr::peter()`") is enough.

## 2. Counts (HEAD, by occurrence class)

`call` = `gptr(` (incl. `gptr::gptr(`); `ns` = gateway `gptr$x` / `gptr[[`; `extapi` = factory API
`gptr$register*|on|state|require|has|name|dir` (kept); `qual` = `gptr::gptr`; `factory` = `function(gptr)`
(kept); `strlit` = `"gptr"`/`` `gptr` `` (mostly package name, triaged below); `entry` = `$gptr$`/`[["gptr"]]`
(stored field, kept).

| group | files | call | ns | extapi | qual | factory | strlit | entry |
|---|---|---|---|---|---|---|---|---|
| R/ | 65 | 121 | 129 | 75 | 2 | 34 | 109 | 30 |
| tests/ (code) | 61 | 667 | 116 | 99 | 17 | 86 | 123 | 28 |
| tests fixtures + _snaps | 18 | 17 | 50 | 0 | 0 | 0 | 99 | 0 |
| man/ (generated) | 23 | 26 | 4 | 0 | 0 | 3 | 8 | 0 |
| inst/ | 7 | 2 | 4 | 1 | 0 | 1 | 68 | 0 |
| root (DESCRIPTION, CLAUDE.md, README.md) | 3 | 2 | 1 | 0 | 0 | 0 | 2 | 0 |
| dev/bench | 5 | 11 | 1 | 0 | 0 | 0 | 0 | 0 |
| dev/spec (incl. proposals) | 10 | 423 | 352 | 39 | 8 | 19 | 110 | 0 |
| dev/plan | 27 | 1213 | 1117 | 311 | 25 | 131 | 509 | 59 |
| dev/progress | 16 | 166 | 43 | 5 | 38 | 5 | 81 | 1 |
| dev/DEVIATIONS, HANDOFF, other dev | 4 | 89 | 38 | 0 | 3 | 5 | 15 | 0 |
| dev/research | 106 | 888 | 802 | 160 | 15 | 67 | 333 | 17 |

Mechanical pass (`dev/progress/rename/rename.py`) on the in-scope files: 3,999 replacements in 125 files
(qual 48, call 2,258, ns 1,663, ns2 13, regex 7, quote 6, def 4): R/ 255 in 41 files, tests 855 in 42 files,
inst 6, DESCRIPTION 1, dev/bench fixtures 12, dev/spec 539 in 7 files, dev/plan 2,326 in 25 files,
CLAUDE.md/HANDOFF 0 (their lines already say `peter`). Uncommitted P11/P17 WIP files add 137
(R/perm-classify.R 30, R/tool-r.R 12, R/subagent-defs.R 1, test-perm-classify.R 72, test-tool-r.R 17,
man/gptr_risk.Rd 5). Per-file table: `dryrun-perfile.md`.

Per-file counts for dev/spec and dev/plan (mechanical replacements):
00-vision-brief 13, 01-decision-register 37, 02-north-star-examples 38, 03-architecture 199,
04-interface-contract 159, 05-plan-decomposition 79, 06-review-resolution 14, 07-local-ollama 0;
00-conventions 3, 00-index 5, P01 14, P02 23, P03 0, P04 6, P05 2, P06 25, P07 89, P08 217, P09 50, P10 246,
P11 135, P12 0, P13 104, P14 83, P15 262, P16 52, P17 40, P18 84, P19 89, P20 33, P21 49, P22 332, P23 113,
P24 171, P25 99.

## 3. R/ code (HEAD line numbers)

Mechanical (handled by `dev/progress/rename/rename.py`, listed so a reviewer can check them):

- Definition `R/gptr-gateway.R:66` `gptr = structure(function(` -> `peter = ...` (rule `def`); roxygen
  9-63 incl. explicit `@usage` 29 and examples 61-63; messages 90, 154, 183-185, 235-241, 506, 568, 704;
  route description 1262; print text 328-329.
- `R/eval-guard.R:388` `quote(gptr)`; comments 374, 411-413.
- `R/doc-blocks.R:736` `quote(gptr)`; comments 2, 206, 256-410, 484, 619, 712-724, 1087.
- `R/doc-formats.R:526-527` transcript statement `s_<hex> = gptr(` / `|> gptr(` (IC-49, string-built);
  `:1076` regex `"^(#~ )?s_[0-9a-f]{6} (=|\\|>) gptr\\("` (rule `regex`); `:1172-1181` the `documents`
  prompt section (model-facing, T0).
- `R/prompt-sections.R:1080` regex `"^gptr\\$([^$( ]+)..."` (rule `regex`) and `:1221` prefix `"gptr$"`:
  member signature lines (P07 tool additions); both must change together.
- `R/tool-namespace.R` 56 sites: signature prefixes 238, 259, 276, 735, 738, 1019; errors 298, 536, 638,
  1186, 1255-1257, 1454; print header 741; helpers/out fragments 1642-1648 and 752 (model-facing, T0).
- `R/prompt-text.R:81, 88, 98, 118, 156` (model-facing, T0 rules/r_session/modes).
- `R/s1-client.R:894` system1 section (T0); `R/s1-route.R:402` error; `R/skill-discover.R:374, 383` catalog
  overflow line (T1); `R/utils-text.R:68` truncation notice `gptr$out("id")`; `R/eval-format.R:64, 66` plot
  notices; `R/agent-run.R:817` `image_omitted_text()` **and** `R/prompt-cache.R:67` (the same placeholder
  `[image omitted: gptr$plot("<id>")]` built twice; must stay identical, see section 9);
  `R/agent-run.R:1184` nested-call cap message.
- `R/agent-dispatch.R:547-548` `paste0("gptr$", short)` matched against the classifier's `flagged$fn`;
  coupled with the classifier's `paste0("gptr$", member)` rows (WIP perm-classify 8926, 8930, 9991,
  10106-10126). Both renamed by the pass.
- `R/ext-registry.R:186, 213, 242` (gateway member names, "equals an existing gptr$ member name").
- Messages: `R/session-object.R:370, 914`, `R/doc-replay.R:89, 174, 316`, `R/gptr-config.R:437`.
- `R/gptr-sdk.R:134` roxygen link `[gptr()]` -> `[peter()]`; examples 136-261.
- Comments/roxygen elsewhere: agent-run, catalog-models 689, doc-locate, env-describe 13, eval-core 740,
  eval-plots 63, ext-specs 969-970/1165, gptr-capture, http-reactor, perm-classify (HEAD: 3 comments
  `gptr$py`), proc-supervise 508, s1-types, session-*, subagent-defs, tool-edit/read/search/write.

Manual (the pass does not catch these):

| Site | Change |
|---|---|
| `R/gptr-gateway.R:308, 311` | "`gptr` is read-only." and `object = "gptr"` -> `peter` |
| `R/gptr-gateway.R` roxygen | add the naming rationale (Peter Wason; Peter Naur, as README "Why `peter()`?") in 2-3 lines; the collision sentence (section 1) |
| `R/gptr-gateway.R:328` + D3 labels in `R/tool-namespace.R:482, 638, 682, 689, 741, 1642, 1653, 1663` | per D3 |
| `R/eval-guard.R:386, 389, 423` | `identical(nm, "gptr")`, `eval_guard_ns_call("gptr")`, `exists("gptr", envir = envir)` -> `"peter"` (the first argument of `call("::", as.symbol("gptr"), ...)` at 377 is the package and stays) |
| `R/doc-blocks.R:264` | `doc_scan_calls(lines, fun = "gptr", ...)` -> `"peter"`; no caller passes `fun`, so prefer deleting the parameter (section 9) |
| `R/doc-blocks.R:736` | `eval_guard_ns_call("gptr")` -> `"peter"` |
| `R/env-history.R:34, 37` | `user_log_is_name(head, "gptr")` and the **third** name (`head[[3L]]`) -> `"peter"`; `head[[2L]]` is the package and stays; doc 7, 31, 40-46 |
| `R/ext-check.R:525` | `heads = c("gptr", "gptr_agent", "gptr_parallel")` -> `"peter"` (IC-42 bare-identifier check) |
| `R/ext-check.R:46` | **revert** the pass: `"gptr$"` here prefixes deprecated *extension-API* members (D1) |
| `@examplesIf exists("gptr", mode = "function")` x6: `R/s1-types.R:492`, `R/session-budget.R:389`, `R/session-live.R:131`, `R/session-object.R:880`, `R/session-store.R:701, 833` | **must** change: after the rename the guard is FALSE and R CMD check silently skips the examples of `gptr_prob`, `gptr_usage`, `gptr_wait`/`gptr_step`, `gptr_fork`, `gptr_last`, `gptr_resume`, `gptr_sessions`. The guard existed only until P08 exported the gateway: replace with plain `@examples` |
| `inst/extdata/risk-functions.csv:768` | `"gptr","gptr",1,"network",...` -> `"gptr","peter",...`, moved after line 828 (`gptr_usage`) to keep the C-locale sort |
| NAMESPACE `export(gptr)` (line 100) | regenerated: `export(peter)`; the six `S3method(..., gptr_gateway)` lines stay |
| WIP `R/perm-classify.R` (after P11 commits) | `risk_member_name()` 7838-7840: `quote(gptr)` (pass) and `identical(risk_str_or_sym(lhs[[3L]]), "gptr")` -> `"peter"` (`gptr::peter$x`); `is_fun` 8182 `"gptr"` -> `"peter"`; 9053 `identical(ref$name, "gptr")` -> `"peter"` (`ref$pkg` stays `"gptr"`); 9288 and 9888 `grepl("^gptr(_|$)", x)` -> `x == "peter" \|\| startsWith(x, "gptr_")`; doc 7829 `gptr$name` -> `peter$name`. Package-name literals (7809, 8305, 9287, 9353, 9861-9875) stay |

## 4. Tests and fixtures

Mechanical: 855 replacements in 42 files (largest: test-doc-blocks 165, test-gptr-gateway 130,
test-doc-locate 87, prefix-baseline.json 57, test-doc-replay 55, test-doc-io 53, test-tool-namespace 49,
test-doc-formats 46, test-copy-gateway 31, test-s1-client 25, test-gptr-sdk 22, test-s1-route 22,
test-prompt-sections 17, test-env-history 18, test-copy-s1 11). Includes the escaped regex
`test-agent-run.R:584` `"^\\[image omitted: gptr\\$plot\\("`, `fixed = TRUE` matches
(`test-eval-format.R:82`, `test-skill-discover.R:493, 642`, `test-prompt-sections.R:374, 819, 1151`,
`test-ext-check.R:507`), string-built code (`paste0("gptr(", ...)`, `str2lang("... gptr('p') ...")`,
`sprintf`), `test-agent-dispatch.R:232, 255` `fn = "gptr$inner"`.

Manual:

| Site | Change |
|---|---|
| `test-gptr-gateway.R:73, 208, 223, 229, 234, 238` | bare symbol: `do.call(gptr, ...)`, `class(gptr)`, `.DollarNames(gptr, ...)`, `print(gptr)`, `formals(gptr)` -> `peter` |
| `test-gptr-gateway.R:232` + `_snaps/gptr-gateway.md` | test name "print(gptr) shows ..." -> "print(peter) ..."; edit the snapshot by hand (header, `print(peter)`, the D3 label); a missing snapshot fails on CI |
| `test-gptr-gateway.R:1253` | exports list `"gptr"` -> `"peter"` |
| `test-tool-namespace.R:986, 987` | `.DollarNames(gptr, ...)` -> `peter`; 213, 234, 338 per D3 labels |
| `test-copy-gateway.R:10-16` (`copy_exports`) and `test-copy-s1.R:6-12` (`with_gptr()`) | **must** change: after the rename the child script runs `gptr = get('gptr', asNamespace('gptr'))` and errors. The code is dead since P08 Task 12 exported the gateway ("once exported these lines do nothing"): delete both and their uses |
| `test-doc-blocks.R:497-498` | `eval_guard_ns_call("gptr")` -> `"peter"` (expected `quote(gptr::peter)` is done by the pass), or delete with the helper (section 9) |
| `test-doc-replay.R:925` | `call("gptr", prompt, quote(mtcars))` -> `call("peter", ...)` |
| `test-env-history.R:197-199` | input renamed by the pass; expected label `"gptr"` stays (D5) |
| WIP `test-perm-classify.R`, `test-tool-r.R` | pass (72 + 17); then grep for `"gptr"` used as a function name |
| `fixtures/bench/prefix-baseline.json` | pass renames the stand-in and rendered texts; manual "the gptr object" (2, per D3); then `preset` (and the four changed `sections` entries) re-measured, section 6 |
| `fixtures/docs/crlf-bom.R`, `crlf-bom.expected.R` | renamed by the pass with CRLF and BOM preserved (verified); never edit them with a text editor that normalises line ends |

Kept (not renamed): `local_project(gptr = ...)` (workspace flag), `fixtures/oracles/report02/*.json`
`"gptr"` fields, `fixtures/cli/*` MCP server `"gptr"`, `test-s1-route.R:914` factory formal, every
`function(gptr)` / `gptr$register` in test-ext-load/ext-builtins/ext-check/provider-registry/session-live/
gptr-capture, `<gptr>#n` traceback text, `.gptr\\settings.json`.

## 5. man/, roxygen, inst/, README, DESCRIPTION, root files

- man/ is generated: run `devtools::document()` after the R edits. Result: `man/peter.Rd` replaces
  `man/gptr.Rd` (roxygen removes its own stale file), `\link[=peter]{peter()}` in `man/gptr_step.Rd`,
  the six `\dontshow{if (exists("gptr", mode = "function")) ...}` wrappers disappear (fork, last, prob,
  resume, sessions, usage), usage examples in 23 Rd files follow. WIP `man/gptr_risk.Rd` follows its roxygen.
- `?gptr` no longer resolves to a page. Not needed for the rename; P25 owns help topics ("The `?gptr` page
  links all three" in P25 becomes `?peter`).
- inst/: `inst/gptr/prompts/explain.md:5`, `inst/gptr/skills/high-performance-r/SKILL.md:23, 25`,
  `.../references/single-cell.md:5` (`gptr$describe`), `inst/gptr/examples/jev-router.R:14, 18` comments:
  pass. Kept: `jev-router.R:97-98` factory, `plugin.json`, `COPYRIGHTS`, `vignette.Rmd`. Manual: the
  risk-functions.csv row (section 3).
- DESCRIPTION Description "A single function, gptr(), opens ..." -> `peter()` (pass).
- README.md already describes `peter()` (and "Why `peter()`?"); no README.Rmd exists yet (P25). Nothing to do.
- CLAUDE.md:28 "Older spec/plan text that says `gptr()` ... means `peter()`" -> after the rename say only:
  "dev/research, dev/progress and DEVIATIONS predate D-135: their `gptr()`/`gptr$` mean `peter()`/`peter$`."
  The untracked `AGENTS.md` mirrors CLAUDE.md: same edit if it is committed.
- `dev/HANDOFF.md:73-77` rename item -> done note; `dev/PROGRESS.md` resume-log line.

## 6. Token baselines (dev/bench, IC-68, IC-73)

Model-facing texts change (T0 rules, r_session helpers/out fragments, documents, system1, modes plan text,
truncation and plot notices, image placeholder, golden-transcript model code), so the baselines must be
re-recorded. o200k via rtiktoken 0.11.0.3 (`dev/.library`): `peter` is never more tokens than `gptr`
(`peter(`/`gptr(` 3 each, `peter$grep(`/`gptr$grep(` 5 each, but ` peter` 1 vs ` gptr` 2 after a space,
`res = peter("x")` 6 vs 7). The char estimator (prose 4.36 chars/token) rises by one char per occurrence:
`est_prefix` +3 to +6, inside the 5% estimate gate; no section nears its budget (r_session about 417 of 500).

Measured on `full/` (HEAD + mechanical pass + "the peter object"), `run.R --check` OK:

| static prefix (prefix-baseline.json `preset`) | HEAD | renamed |
|---|---|---|
| minimal | 1,271 | 1,263 |
| standard_core | 2,360 | 2,336 |
| standard_all | 2,844 | 2,814 |
| standard_interactive | 2,987 | 2,957 |

| golden transcript | prefix HEAD -> renamed | input_total | output_total |
|---|---|---|---|
| ns02-mixed-model | 2,296 -> 2,278 | 5,464 -> 5,428 | 140 -> 140 |
| ns02b-data-first-pipe | 1,271 -> 1,263 | 3,280 -> 3,264 | 130 -> 130 |
| ns03-pipe-steering | 2,296 -> 2,278 | 17,072 -> 16,964 | 337 -> 337 |
| ns04-system-one | 2,296 -> 2,278 | 5,258 -> 5,221 | 119 -> 118 |
| ns07-script-history | 2,533 -> 2,512 | 5,894 -> 5,852 | 144 -> 143 |

Section o200k (`sections` in prefix-baseline.json): rules_standard 238 -> 237, rules_readonly 123 -> 122,
rules_minimal 308 -> 301, r_session 455 -> 433. Final numbers depend on D2/D3 wording: measure after all edits.

Pre-existing drift (not caused by the rename): the committed `dev/bench/tokens/baseline.csv` says prefix
2,750 / input 6,088 / catalog 542 for ns02, but HEAD measures 2,296 / 5,464 / 351 (all five rows similar).
The ratchet only fails on growth, so `--check` passes; `--update` will absorb this drift too. Record it.

Files that carry the numbers: `tests/testthat/fixtures/bench/prefix-baseline.json` (`preset`, `sections`;
`estimate` may stay, within 5%), `tests/testthat/test-bench-context.R` (literal `c(minimal = 1271L, ...)`),
`dev/bench/tokens/baseline.csv` (`run.R --update`), architecture 12.1 table (03:2674-2677 and the 2,750 row),
01-decision-register:631. Completed-plan evidence (P07:5959-6098, 6694-6728, 6909; P10:7439-7459) records
what was measured then: leave. Future-task text (P15:8736 "2,750 -> 2,987", P19:4738 `ns06-team-member`
row 1271) will be re-measured by those tasks; a one-line note in each is enough.
P24 says "`dev/bench/tokens/run.R` and the fixtures ... are read, never edited": the rename edits five
fixtures; record that under D-135.

## 7. dev/spec and dev/plan

Update dev/spec/00-06 (not proposals) and every dev/plan file: they are the design record future tasks read.
The pass skips lines already mentioning `peter` (vision-brief 111-118, CLAUDE.md, HANDOFF). Manual residue
(`residue.txt`, 310 lines incl. expected keeps) - the function-identity items:

- 00-vision-brief:118 "Below, `gptr()` reads as `peter()`." -> delete; :111 "(formerly `gptr()`)" keep.
- 01-decision-register:456, 491, 577 ("`gptr` plus `gptr_*`", "an evaluator shim resolves `gptr`",
  "Only `gptr` and `gptr_*`") -> `peter`; :631 numbers (section 6).
- 03-architecture:353 (`gptr` symbol shim), 495 (`gptr` plus 62 `gptr_*`), 506 (`gptr = function(` - pass),
  515-516 (`gptr` is a closure; `gptr$name` reaches the namespace), 666-667, 865 (Gateway `gptr`), 1961
  ("gptr object", D3), 2904, 2674-2677 numbers. Keep 288 (layer name `gptr` L6 = files `R/gptr-*.R`).
- 04-interface-contract:214 (`$<-` on sessions and `gptr`), 839 (`class(gptr)`), 1003 (pass), 1012, 2645
  (shim row), **4161 and 4173 (14.1 export list)** - without these the cross-plan index reports 2 errors.
  Keep 215 `$.gptr_gateway`, 421/608/610/664 (`gptr` entry object), 2326/3445 (origin `gptr`), 3493-3504
  (10.5 factory API, D1).
- 05-plan-decomposition:551, 620, 694 (`gptr` symbol/closure) -> `peter`.
- Plans: P08 (tests with `class(gptr)`, `print(gptr)`, `formals(gptr)`, readonly `object`), P09 (shim
  "`gptr`" names; examplesIf), P10 (`.DollarNames(gptr...)`, labels), P11:2251 doc, P14 console prompt (D4,
  28 lines), P25 (`?gptr` page -> `?peter`, 1134 prose), P07/P16/P24 test code with bare `gptr`, P15:3423 and
  8134, P06:5357, P24:1613 escaped regexes (pass).
- `plan-long-lines.txt`: 23 plan R-block lines become 101-103 columns (P08 1, P10 9, P11 1, P14 1, P15 4,
  P18 1, P19 2, P21 1, P22 3): rewrap or `lint_all.R` reports them.
- Leave untouched: dev/research (888 calls, 802 ns in 106 files), dev/spec/proposals (P-A 53, P-B 42,
  P-C 62/79), dev/progress, dev/DEVIATIONS.md (historical evidence). One exception: the live cross-plan
  tool `dev/research/assets/consolidation-tools/build_index.py:586` `DSL_HOSTS = {"gptr"}` -> `{"peter"}`;
  without it the index reports 12 false `agent()` errors in P19/P20/P21 tests. (Its `DEFAULT_REPO` and
  `extract.py` `plan_dir` hard-code `/Users/wanjun/...`: pass `--repo`, use a patched temp copy of extract.py.)

Verified: cross-plan index on the renamed tree (pass + the two 14.1 lines + DSL_HOSTS) has the same findings
as HEAD (0 errors; the 4 extra warnings are files missing from the scratch copy).

## 8. Tricky cases (summary)

1. `@examplesIf exists("gptr", mode = "function")` x6: silent example skip after the rename.
2. `with_gptr()` / `copy_exports`: child scripts `get('gptr', ...)` error after the rename.
3. Escaped regexes: `doc-formats.R:1076` `gptr\\(`, `prompt-sections.R:1080` `^gptr\\$`,
   `test-agent-run.R:584`, P15/P06/P24 copies; and a WIP combined regex `^gptr(_|$)` that must become two
   tests (`== "peter"`, `startsWith(, "gptr_")`).
4. `gptr$` is three different things: gateway members (rename), extension-API members inside
   `function(gptr)` (keep, D1; `ext-check.R:46` string prefix too), and stored entry fields (`e$gptr$turn`,
   prose `gptr$turn`, `gptr$reason`, `gptr$blocks`; keep). A blind `s/gptr\$/peter$/` breaks P02/P17 code.
   `gptr$name` is extension API in contract 10.5 but the gateway in architecture 516 and P11:2251.
5. Package vs function `"gptr"`: `call("::", as.symbol("gptr"), as.symbol(name))`, `user_log_is_name(head[[2L]], "gptr")`,
   `ref$pkg == "gptr"`, `asNamespace("gptr")` stay; the function-name strings change.
6. Coupled strings that must change together: image placeholder (agent-run.R:817 / prompt-cache.R:67),
   member `fn` (classifier rows / agent-dispatch.R:547), member signature prefix and its parser
   (prompt-sections.R:1221 / 1080; tool-namespace.R), transcript writer and reader (doc-formats.R:527 / 1076),
   prompt texts and prefix-baseline.json `expected.rendered` (byte-for-byte test).
7. Byte-exact fixtures: crlf-bom fixtures (CRLF + BOM), `.gitattributes` `* -text`.
8. Line length: 13 code lines and 23 plan lines reach 101-103 columns.
9. Snapshot `_snaps/gptr-gateway.md` is keyed by the test name; edit both.
10. Lines that intentionally keep the old name ("formerly `gptr()`", D-135 notes, DEVIATIONS) must not be
    rewritten: `dev/progress/rename/rename.py` skips lines that already contain `peter`.
11. `print.gptr_gateway` label and `<gptr namespace ...>` headers (D3).
12. The P11 WIP (perm-classify, tool-r, subagent-defs and their tests) is uncommitted: rename after it lands.

## 9. Simplicity items the rename exposes (optional, same change or next)

- Delete the dead pre-P08 guards instead of renaming them: six `@examplesIf`, `with_gptr()`, `copy_exports`.
- `eval_guard_ns_call()` exists only because `gptr::gptr`/`gptr::gptr_return` were unexported before P08
  (comment at eval-guard.R:371-376, CI-4). Both are exported now (`test-zzz.R` checks every literal
  `gptr::` call names an export), so `quote(gptr::peter)` and `quote(gptr::gptr_return)` can replace the
  helper (3 call sites, 2 test lines).
- `doc_scan_calls(fun = "gptr")`: the parameter is never passed; drop it and the `fun` in its memo key.
- `"[image omitted: gptr$plot(...)]"` is built in two places (agent-run.R `image_omitted_text()`,
  prompt-cache.R:67): one definition, if the layer order allows prompt-cache to call it.
- The literal prefix `"gptr$"` is repeated at about 10 sites (tool-namespace, ext-registry,
  prompt-sections x2, agent-dispatch x2, WIP classifier x6); the rename touches all of them anyway.

## 10. Ordered execution plan

Prefix every R command with `R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library` (roxygen2 7.3.3, rtiktoken).

0. **Freeze.** Let the in-flight P11/P17 tasks commit; pause lanes that touch R/, tests/, dev/plan.
   Confirm D1-D4. Start from a clean `git status`.
1. **Mechanical pass** (one command):
   `git ls-files R tests inst DESCRIPTION dev/bench/tokens/fixtures 'dev/spec/0*.md' dev/plan CLAUDE.md dev/HANDOFF.md | grep -v -E '\.(gz|png|csv)$' | xargs python3 <scratch>/rename.py`
   then `git diff --stat` (expect about 130 files, 4,100+ replacements with the P11 work).
2. **Revert** `R/ext-check.R:46` to `"gptr$"`.
3. **Manual R edits** (section 3 table), the risk-functions.csv row, D3 labels, `?peter` rationale and
   collision sentence; delete the six `@examplesIf` guards (and optionally the section 9 items).
4. **Manual test edits** (section 4 table); delete `with_gptr()`/`copy_exports`; edit the snapshot.
5. **Rewrap** the 13 lines in `long-lines.txt`.
6. **Regenerate docs:** `Rscript --vanilla -e 'devtools::document()'`; check `git status man NAMESPACE`
   (`man/peter.Rd` added, `man/gptr.Rd` deleted, `export(peter)`, S3 methods unchanged).
7. **Token baselines:** `Rscript --vanilla dev/bench/tokens/run.R` (prints the four static o200k totals) ->
   write them to prefix-baseline.json `preset` (and the changed `sections`), test-bench-context.R literal,
   architecture 12.1, decision register 631; then `run.R --update` (all five rows) and `run.R --check` (exit 0).
8. **Specs/plans** (section 7 manual list), 23 plan rewraps, `DSL_HOSTS`, CLAUDE.md:28, vision-brief:118,
   HANDOFF/PROGRESS, a short D-135 completion note (scope, D1-D4 outcomes, baseline drift, P24 fixture edit).
9. **Verify** (all must pass):
   - Zero hits expected except lines containing `peter` (D-135 notes):
     `git grep -n -P '(?<![\w.$/\-\[])gptr(?=\(|\[\[|\\\\[($])|gptr:::?gptr(?!\w)' -- R tests inst DESCRIPTION dev/bench 'dev/spec/0*.md' dev/plan`
   - Only `R/ext-check.R:46` expected:
     `git grep -n -P '(?<![\w.$/\-\[])gptr\$(?!(register\w*|on|state|require|has|name|dir|turn|reason|blocks)\b)' -- R tests inst`
   - None expected: `git grep -n -E 'exists\("gptr"|with_gptr|copy_exports|fun = "gptr"|\^gptr\(_\|\$\)|identical\(nm, "gptr"\)' -- R tests`
   - `grep -c '^"gptr","peter",' inst/extdata/risk-functions.csv` -> 1; `grep -c '^"gptr","gptr",' ...` -> 0
   - `Rscript --vanilla -e 'lintr::lint_package()'` -> no lints
   - `Rscript --vanilla -e 'devtools::test(filter = "gptr-gateway|gptr-capture|gptr-sdk|gptr-config|copy-|eval-guard|eval-format|doc-|env-history|ext-check|ext-registry|agent-dispatch|agent-run|prompt-|tool-|utils-text|skill-discover|s1-|perm-classify|bench-context|zzz|lint-rules|arch-layers")'`
     (copy-* rows need `capabilities("profmem")`; they run locally), then the full `devtools::test()`
   - `Rscript --vanilla dev/bench/tokens/run.R --check` -> `OK: 4 static prefixes and 5 golden transcripts ...`
   - `R CMD build . && R CMD check --as-cran gptr_*.tar.gz` -> 0 errors / 0 warnings; the formerly guarded
     examples now run
   - Cross-plan checks (CLAUDE.md rule): `python3 dev/research/assets/consolidation-tools/build_index.py --repo "$PWD" --quiet`
     (0 errors), then extract.py (temp copy with `plan_dir` fixed), `check_r.R`, `lint_all.R` (0 lints).
10. **Commit** as one coordinated change (code/tests/fixtures/man/baselines, then spec/plan docs), conventional
    message such as `refactor(gateway): rename the entry point gptr() to peter() (D-135)` and
    `docs(spec,plan): use peter() for the entry point (D-135)`; resume lanes on the new names.
