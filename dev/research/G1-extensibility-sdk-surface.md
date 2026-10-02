# G1 - Extensibility and SDK surface: capability map, registration API, versioning, exported names (S-11 / REQ-41)

Research date: 2026-09-29. Track: G1 (gap report). Author: research sub-agent.
Pi reference: clone at commit `1b347794` (`@earendil-works/pi-coding-agent` 0.99.1).
All R ran as `Rscript --vanilla` on R 4.4.3, macOS arm64, under heavy machine load (load
average 25-140 from parallel agents; timings are medians and noisy, ratios are stable).
Nothing ran on Windows or Linux. No model API was called.

Path abbreviations: `$PI` = the Pi clone; `$CA` = `$PI/packages/coding-agent`;
`$G1` = `scratchpad/work/G1` (prototype packages in `$G1/pkg`, scripts in `$G1/proto`,
outputs in `$G1/out`, `R CMD check` logs in `$G1/check`).

Evidence labels: **VERIFIED** (read in source, or executed and output shown in section 5),
**LIKELY** (documented or strongly implied, not executed), **UNCERTAIN** (inference).

House style: every R block uses `=` for assignment and `|>` for pipes (S-9).

---

## 1. Executive summary

1. **One registry, one registration verb, per-kind constructors.** Every capability category is a
   *kind* in a single process-level registry keyed by `(kind, name)`. A capability is a classed spec
   made by an exported constructor (`gptr_tool()`, `gptr_provider()`, `gptr_policy()`, ... 23 in all)
   and registered with one verb: `gptr$register(spec)` inside a plugin factory, or
   `gptr_register(spec)` at top level. Kinds are themselves registered specs (`gptr_kind()`), so a
   plugin can add a new capability category and register into it in the same factory. The prototype
   registers **all built-in features (9 built-in extensions, 22 kinds, 42 records) through exactly this
   API** and passes 59/59 end-to-end checks plus 21/21 third-party-plugin checks (section 5). VERIFIED.
   (Verification note: the 42 records are 21 kind-definition records plus 21 capability records
   spread over 13 kinds: tool 4, setting 6, and one each of adapter, backend, compactor, context,
   doc_format, frontend, hook, policy, provider, section, ui. The `artifact_type` kind is declared
   but nothing registers or exercises a record of it anywhere in the prototype or its tests, and
   `mcp_server` records are data only, with no MCP connection prototyped. Those two contracts are
   design, not verified behaviour.)
2. **Three layers, chosen by what must run.** (a) *Declarative* resources (skills, prompt templates,
   agent definitions, MCP entries, the plugin manifest) are read from files and never execute code;
   (b) *factories* `function(gptr)` register code-backed capabilities transactionally (staged, then
   committed; a failing factory leaves nothing behind); (c) *S3 generics* are used only where
   dispatch is on the class of a user object (`gptr_describe()`), registered through `NAMESPACE`
   so a package can support gptr with gptr only in Suggests (delayed registration VERIFIED).
3. **Lazy activation.** A plugin manifest lists what its factory `provides`; gptr registers
   placeholders and runs the factory on first use (first tool call, first dispatch of a provided
   event). Declaring 100 plugins lazily took 8-16 ms against 28-49 ms eager (in-memory factories) and
   106-189 ms for directory plugins that parse R files (verification re-run at load average 5:
   7 / 26 / 84 ms, same ordering); a plugin whose namespace imports Seurat would add about 2-4 s at
   start-up if activated eagerly (`loadNamespace("Seurat")` measured: 4.17 s under the original
   run's load, 1.9-2.6 s in four verification runs at load average 5-7; Seurat 5.4.0). VERIFIED.
4. **Object system (D-02): S3 classes on environments, no R6 in the contract.** Measured: calling a
   method stored as a closure in a locked environment costs 1.6-1.9 µs vs 3.8-4.5 µs for an R6
   method and 3.4-4.1 µs for an S3 generic; creating a ctx-like object with 10 methods costs
   3.2-5.0 µs vs 47-76 µs for `R6Class$new()`; the serialised object is 2,991 vs 14,390 bytes
   (these absolute timings were taken at load average 12-82; the verification re-run at load
   average 5 gave 0.70 vs 1.64 vs 1.48 µs per call and 1.7 vs 23-28 µs per creation, so quote the
   ratios, about 2x per call and 13-16x per creation, not the microseconds). R6 is
   already in the dependency closure (via httr2, processx, callr), so dependency weight is *not* the
   argument; the arguments are speed of per-session/per-dispatch objects, a contract that does not
   depend on inheritance, and pipe-friendly functional SDK verbs (S-8). This overturns report 02's
   R6 recommendation for Agent/SessionStore. VERIFIED.
5. **Versioning.** An extension API version independent of the package version
   (`gptr_api_version()` = `1.0`), semver on MAJOR.MINOR, requirements declared in the manifest,
   in `DESCRIPTION` (`Config/gptr/api`), on the factory (`attr(f, "gptr_api")`) or checked inside it
   (`gptr$require()`). Unmet requirements raise `gptr_error_api_version`; a call to a method this API
   lacks raises `gptr_error_api_missing`; old API objects captured across `gptr_reload()` raise
   `gptr_error_stale_api`. Feature negotiation: `gptr_api_features()` / `gptr$has("kind.router")`.
   Pi has **no** extension API version at all (peer dependencies declared `"*"`), and its changelog
   has 47 "Breaking Changes" sections in 280 releases between 2025-11-25 and 2026-09-29, about 26 of
   which touch extension, SDK or provider surfaces (regex count). VERIFIED.
6. **Conformance helpers are exported** (`gptr_check()` for specs, factories and installed plugin
   packages; `gptr_fake_provider()` for offline sessions). The toy plugin runs them from its own
   testthat suite; `gptr_check("gptrpanel")` also proves that the manifest's lazy `provides` list
   matches what the factory really registers. VERIFIED.
7. **CRAN.** The host prototype and two toy plugin packages pass `R CMD check --as-cran` with
   `Status: OK` (three local overrides for network and clock; to reproduce from the embedded
   sources, `gptrpanel` must be roxygenised and `cohortdesc/man/cohort.Rd` added, see section 5,
   otherwise each plugin check gives 1 WARNING "Undocumented code objects"). Found by the check: a hidden
   `inst/gptr/.mcp.json` gives a NOTE, so packages must ship `inst/gptr/mcp.json`; closures built
   with `environment<-` trigger "no visible binding" NOTEs, so tool functions must be real closures.
   The CRAN policy asks maintainers to check "reverse strong dependencies, reverse suggests and the
   recursive strong dependencies of these", so plugins that only *Suggest* gptr are still in gptr's
   reverse-dependency blast radius. VERIFIED.
8. **SDK for agentic layers composes with S-8.** `gptr()` returns the session environment;
   `gptr("...", .run = FALSE)` queues a prompt; `gptr_step()` runs one model turn; `gptr_wait()`
   runs to settlement; `gptr_on()` subscribes session-scoped hooks (same contract as plugin hooks);
   `gptr_steer()` queues steering or follow-ups; `s |> gptr("...")` steers a running session and
   continues an idle one; `gptr_fork()` never copies listeners. A reviewer-panel orchestrator built
   only on these exports (`gptrpanel::panel_review()`) interleaves reviewer sessions with
   `gptr_step()`, aggregates usage and runs a judge. VERIFIED.
9. **Token efficiency is built into the registration contract.** Each tool declares an `exposure`:
   on btw's 31 real tool declarations, `direct` (JSON schema every request) costs 10,156 o200k
   tokens (328/tool), `r` (one R signature line in the run-R tool description) costs 1,129 (36/tool,
   9x less), `deferred` costs a flat 55 tokens (search tool plus a one-line count), `hidden` 0.
   The default exposure for *plugin* tools is therefore `r`. A skill catalog entry costs about 63
   tokens, an agent listing about 19; prompt templates cost nothing until used. Composition: an
   illustrative three-lookup task costs 1,532 transcript tokens as three direct tool round trips and
   109 as one `run_r` call through the dispatcher. VERIFIED (rtiktoken o200k_base).
   Caveats: o200k_base is OpenAI's tokenizer, not Claude's, so treat the counts as relative. The
   9x is not like-for-like: an `r` signature line keeps parameter names, types and only the first
   sentence of the description, and drops parameter descriptions, enums and nested schemas, so the
   model may spend extra tokens (`gptr_tools$.search()`, help lookups, failed calls) to recover
   them. The net saving on real tasks is UNCERTAIN until the REQ-42 benchmark suite measures it.
10. **Exported names.** 76 final names (`gptr()` plus 75 `gptr_*`) collide with nothing in an index of
    41,331 exports from 592 installed packages (base, recommended, dplyr, rlang, purrr, Seurat stack),
    the NAMESPACE files of 37 CRAN LLM packages (mcptools 1.0.3, btw 1.5.0, ellmer 0.5.0,
    tidyllm 0.6.0, ...), and the r-universe exports search. 25 unprefixed names proposed by earlier
    tracks collide (for example `mcp_tools` with mcptools, `classify` with admisc and dozens more,
    `is_true` with rlang, `agent` with LLMRagent/llm.api, `mcp` with multcomp, `artifact` with
    icesTAF, `tools` with eppoFindeR). The tools-as-R-functions dispatcher is named `gptr_tools`
    (+2 tokens per call vs `tools$`). VERIFIED.

Proposed positions: **D-02** S3 + environments (item 4); **D-16** Agent Skills directories,
`function(gptr)` factories referenced from a manifest, R packages with `inst/gptr/` (section 4.4);
**D-25** Pi-derived canonical event names and dispatch semantics, Claude/Codex names only through an
import alias map, nine gptr-specific events (section 3.2); **D-28** `gptr()` plus `gptr_*` only, one
exported dispatcher object `gptr_tools`, no unprefixed exports, `agent()` only as a data-mask alias
(section 4.7).

---

## 2. Findings with evidence

### 2.1 What Pi offers and what it lacks

- **Factory model.** A Pi extension is a default-exported factory receiving `ExtensionAPI`; the
  factory registers, action methods throw until the runtime is bound, and a failing factory's
  registrations are discarded (report 05 §2.1; `$CA/src/core/extensions/loader.ts:156-236, 593-612`).
  VERIFIED (report 05, re-read in `$CA/docs/extensions.md` "Respect the runtime lifecycle").
- **Per-category methods on one API object.** `registerTool`, `registerCommand`, `registerShortcut`,
  `registerFlag`, `registerProvider`, `registerMcpServer`, `registerVirtualModel`, renderers,
  `on(event)`, `events` bus (report 05 §3.2, `types.ts:1535-1858`). Pi has no registration point
  for permission policies, context describers, compaction strategies, document writers, artifact
  types, sub-agent backends or front ends: those are either absent or implemented by *using*
  events (`tool_call` for permissions, `session_before_compact` returning a `compaction` for
  compaction). VERIFIED (report 05 §2.4, §3.1).
- **Built-ins as extensions.** Pi's built-in `codemode`, `tool-search`, `mcp` and `llama.cpp` are
  `InlineExtension` entries marked `builtin: true` (`sdk.md` notes that such an entry "is not an
  inline extension": it supplies the code of a `builtin:<name>` extension that loads like a
  configured extension file, after project trust is resolved). The last three in that file
  (`codemode`, `tool-search`, `mcp`) are also `replaceable` (dropped when another
  extension registers a tool, command or flag of the same name) and all are disabled with
  `-builtin:<name>` (`$CA/src/extensions/index.ts:7-14`; `$CA/docs/sdk.md` "InlineExtension").
  But Pi's core tools (read, bash, edit, write) and its providers are not extensions. VERIFIED.
- **Tool exposure.** `direct | model-only | codemode | deferred | hidden`, plus `namespace`,
  `annotations`, `prepareLoadout` (`$CA/docs/extensions.md` "Tool exposure"). VERIFIED.
- **No API version.** Pi packages declare the host packages as `peerDependencies` with a `"*"` range
  (`$CA/docs/packages.md` "Declare dependencies"); a grep for version checks over
  `src/core/extensions/*.ts` and `pi-manifest.ts` finds none. The changelog shows 280 dated
  releases from 2025-11-25 to 2026-09-29, 47 with a "Breaking Changes" section, about 26 of which
  mention extension, SDK or provider surfaces (regex over the section text; approximate). Examples:
  `user_bash` now fails closed; provider stream inputs changed from `Context` to
  `TranscriptContext`; `TurnEndEvent` gained required boundary fields. VERIFIED (python count over
  `$CA/CHANGELOG.md`, shown in section 5.10).

Conclusion: Pi's *mechanism* (factory + events + registration methods) is the right model, but
gptr must add (a) registration kinds for the categories Pi leaves to events or to core code,
(b) an explicit API version, and (c) conformance tests, because a CRAN package with plugins on
CRAN cannot absorb Pi's rate of breaking change silently.

### 2.2 Gaps left by earlier tracks (the reason for this report)

| Gap | Evidence |
|---|---|
| `register_mcp_server`, `register_router` designed but not prototyped | report 05 §4.4 marks them NP |
| No registration contract for policies, context describers, compaction, document writers, artifact types, sub-agent backends, agent definitions, front ends, System 1 adapters | reports 05, 14, 15, 17, 18 each define a local API; none says how a third party plugs in |
| Object system undecided | report 02 §4.1 recommends R6; D-02 prefers S3 + environments; report 05 §4.14 says R6/S7 not needed |
| Names collide or conflict | 06 `tools` object (open question), 16 `mcp_tools()`/`mcp`, 17 `artifact()`, 04 `decide()`/`classify()`; and gptr-internal clashes: `gptr_agent()` means an R6 agent (02) and an agent definition (06, 15); `gptr_usage()` means accounting (15) and "open the ChatGPT usage page" (08); `gptr_classify()` (18, R-code risk) vs System 1 classification (04); `gptr_capabilities()` (19, installed R packages) vs capability registry; `gptr_setting()` getter (05) vs setting declaration; `gptr_hook()` registration verb (20) vs spec constructor |
| Hook names conflict | report 05 uses Pi names (`tool_call`, `tool_result`, `input`), report 20 §4.6 proposes Claude/Codex-derived names (`pre_tool`, `post_tool`, `user_prompt`) |

### 2.3 Object system measurements (D-02)

Measured with microbenchmark (section 5.6; three runs, load average 12-82). A verification re-run
at load average 5 gave 0.70 (env closure) / 2.01 (env + S3 `$`) / 1.64 (R6) / 1.48 (S3 generic) µs
per call and 1.72 / 28.0 / 22.9 µs per creation (env / R6 portable / R6 non-portable): every
absolute number below is inflated by load, the orderings and ratios hold, and the serialised sizes
reproduced exactly.

| Operation | env of closures (locked) | env + S3 `$` method | R6 | S3 generic |
|---|---|---|---|---|
| one method call, median µs | **1.64-1.93** | 4.55-5.37 | 3.81-4.51 | 3.44-4.10 |
| create ctx-like object with 10 methods, median µs | **3.16-4.96** | - | 46.6-75.6 (`$new()`, portable or not) | - |
| serialised size, bytes | **2,991** | - | 14,390 | - |
| method replacement after lock | blocked | blocked | blocked | n/a |
| field change after lock | blocked (except the one binding left unlocked on purpose) | - | **allowed** (R6 `lock_objects` locks membership, not values) | - |

Other facts:
- R6 is already a hard transitive dependency of httr2, processx and callr (package_dependencies on
  the installed library), and `loadNamespace("R6")` takes 2-26 ms in a fresh process. Dependency
  weight is not a reason to avoid it. VERIFIED.
- R6's `inherit` is captured as an unevaluated expression, so portable R6 classes can be inherited
  across packages (R6Class.Rd: "When R6 classes are portable (the default), they can be inherited
  across packages without complication"). VERIFIED (installed R6 2.6.1 Rd). Cross-package
  inheritance is therefore not a hazard, but it is also not needed: in the proposed contract third
  parties *register specs*, they never subclass gptr's classes.
- The `$` S3 method that turns an unknown API method name into a classed error costs ~3 µs per
  access under load (~1.3 µs at load average 5). It is used only on the extension API object (touched at load time), never on ctx
  (touched per event). VERIFIED.
- A locked environment breaks the natural `gptr$state$n = 1` idiom ("cannot change value of locked
  binding for 'state'") because R re-assigns the outer binding. Fix: lock the environment and every
  method binding *except* `state`, with `lockBinding()` per name (`unlockBinding()` would draw an
  `R CMD check` "possibly unsafe calls" NOTE). After the fix `gptr$state$n = 1` works, method
  replacement and new bindings are still refused. VERIFIED (section 5.3 transcript).

### 2.4 Start-up and dispatch cost (0, 10, 100 plugins)

Median of 5 repetitions, fresh registry each (section 5.7; three runs under load 15-50). Each
synthetic plugin registers one tool, one command and one `tool_result` hook.

| Plugins | Records | Built-ins only | Eager factories | Directory plugins (parse R file + manifest + skill) | Lazy manifests | Resolve all tools, cold | One session run (1 tool call) |
|---|---|---|---|---|---|---|---|
| 0 | 42 | 3-8 ms | 2-7 ms | 3-6 ms | 3-9 ms | 1 ms | 3-6 ms |
| 10 | 72 | 3-6 ms | 6-17 ms | 11-25 ms | 3-6 ms | 0-1 ms | 4-7 ms |
| 100 | 342 | 3-7 ms | 28-49 ms | 106-189 ms | 8-16 ms | 2-4 ms | 20-39 ms |

- The first version was 5-8x slower: 40% of eager load time was one `grepl()` validating tool names
  with a TRE pattern containing `{0,63}` (bounded repetition is expensive to compile in TRE).
  `perl = TRUE` removed it (profile in section 5.8). Rule for the implementation: every regex on a
  registration or dispatch path uses `perl = TRUE` (consistent with report 19 §4.4). VERIFIED
  (verification microbenchmark: 100 calls of `grepl("^[A-Za-z][A-Za-z0-9_]{0,63}$", x)` took a
  median 16.0 ms with TRE vs 0.68 ms with `perl = TRUE`). Note that the prototype itself still breaks
  this rule in one place: the hook `matcher` in `dispatch()` (`ext-events.R`) calls `grepl()` without
  `perl = TRUE`.
- Scanning all 618 installed packages for `inst/gptr` with one vectorised `dir.exists()` costs 3-6 ms
  (report 05 measured 2-4 ms). VERIFIED.
- Lazy registration of the real `gptrpanel` package: 15-20 ms (namespace *not* loaded); first use
  including activation 5-8 ms; eager 16-24 ms (verification re-run at load average 5: lazy 9-10 ms,
  first use 4 ms, eager 10-12 ms, so for this dependency-free toy the two are nearly equal). The
  saving grows with the plugin's dependencies (`loadNamespace("Seurat")`: 4.17 s in the original
  run; 1.9-2.6 s in four verification runs at load average 5-7). VERIFIED.
- Verification re-run of `bench_startup.R` at load average 5 (100 plugins): built-ins 3 ms, eager
  26 ms, directory plugins 84 ms, lazy 7 ms, session run with 100 hooks 16 ms; record counts
  42 / 72 / 342 reproduced exactly.
- Dispatch cost scales with the number of hooks for an event: 100 `tool_result` hooks raise one
  session run from 3-6 ms to 20-39 ms. Acceptable against model latency; the implementation should
  index hooks by event (the prototype filters all hook records per `emit()`). VERIFIED.

### 2.5 Token cost of plugin declarations (eager vs deferred)

Corpus: btw 1.5.0's 31 tool declarations in Anthropic wire format (46,236 characters, matching
report 10's 46,235 plus a newline), dumped with ellmer 0.5.0; tokenizer rtiktoken `o200k_base`
(section 5.9).

| Tools | `direct` (JSON schema) | `r` (one signature line each) | `deferred` (count line + search tool) | `hidden` |
|---|---|---|---|---|
| 10 | 3,032 | 394 | 55 | 0 |
| 31 | 10,156 | 1,129 | 55 | 0 |
| 100 (the 31 repeated; extrapolation) | 32,869 | 3,649 | 55 | 0 |

- Per tool: 327.6 tokens direct vs 36.4 as an R signature line (ratio 9.0). chars/4 estimated 11,355
  tokens for the JSON (11.8% over; JSON is dense in punctuation). The two columns do not carry the
  same information: the signature line (`sig()` in `tokens.R`) keeps parameter names, types and the
  first sentence of the description only; parameter descriptions, enums and nested schemas are
  dropped. The 9x is therefore an upper bound on the declaration saving, and whether the model
  then needs extra lookups is UNCERTAIN (not measured). o200k_base is not Claude's tokenizer.
- Skill catalog entry (`<skill>` name + description + location) 63 tokens; agent listing line 19
  tokens; prompt templates 0 until a user invokes them.
- Dispatcher spellings (o200k): `gptr_tools$grep("TODO", "R")` 11 tokens, `tools$grep(...)` 9,
  `gptr::tools$grep(...)` 12, `gptr_tools$github$search_code(q = "x")` 13 vs
  `gptr_tools$mcp__github__search_code(...)` 15; a nested sub-agent written as
  `gptr("Summarise x", x, model = haiku)` 15.
- Composition example (constructed, illustrative): three `trial_lookup` calls with 20-row results as
  direct tool round trips put 1,532 tokens into the transcript; one `run_r` call composing the same
  three calls through `gptr_tools$trial_lookup()` and printing a 2x3 table puts 109. VERIFIED
  (numbers), UNCERTAIN (representativeness).

### 2.6 Plugins shipped by R packages

- `inst/gptr/...` installs to `<lib>/<pkg>/gptr/...`; `system.file("gptr", package = )` finds it;
  custom `DESCRIPTION` fields `Config/gptr/plugin` and `Config/gptr/api` survive installation and
  `R CMD check --as-cran`. VERIFIED (report 05 §5.9; this report's checks).
- **Hidden files are flagged.** `inst/gptr/.mcp.json` produced "checking for hidden files and
  directories ... NOTE ... Found the following hidden files and directories: inst/gptr/.mcp.json".
  Renamed to `inst/gptr/mcp.json` the check is OK. Directory plugins and Claude plugins may keep
  `.mcp.json`; installed packages must use `mcp.json`. VERIFIED.
- **Delayed S3 registration works for Suggests-only packages.** `cohortdesc` declares
  `S3method(gptr::gptr_describe, cohort)` with gptr only in Suggests. Loading `cohortdesc` does not
  load gptr; after `library(gptr)`, `gptr_describe(cohort(25, "pilot"))` dispatches to the plugin's
  method; `R CMD check --as-cran` is OK. VERIFIED. (Delayed registration through `S3method()`
  directives is new in R 3.6.0: VERIFIED in the installed `doc/NEWS.3`, section "CHANGES IN R 3.6.0":
  "S3method() directives in NAMESPACE can now also be used to perform _delayed_ S3 method
  registration"; behaviour VERIFIED by experiment.)
- **Unload invalidation.** `setHook(packageEvent(pkg, "onUnload"), ...)` fires on
  `unloadNamespace()`; the prototype marks that package's records dead and re-declares its
  extension lazily, so the next use re-activates from the new namespace. VERIFIED (plugin test G).
- **`.onLoad` self-registration is the wrong default.** It would turn "the namespace was loaded for
  any reason" (a `pkg::fun` call, a dependency) into "its extension code runs inside every gptr
  session", which defeats the opt-in rule of reports 05 and 16. Discovery + explicit enabling +
  lazy activation gives the same convenience without that side effect. (Reasoned; the opt-in rule is
  VERIFIED policy in 05 §4.10.)

### 2.7 CRAN reverse dependencies

- Policy (revision 6875): "If an update will change the package's API and hence affect packages
  depending on it, it is expected that you will contact the maintainers of affected packages and
  suggest changes, and give them time (at least 2 weeks, ideally more) to prepare updates before
  submitting your updated package." And: "If possible, check reverse strong dependencies, reverse
  suggests and the recursive strong dependencies of these (by
  `tools::package_dependencies(reverse = TRUE, which = "most", recursive = "strong")`)." VERIFIED
  (fetched policy page; two quotes counted as policy text, not reproduced beyond this).
- `tools::check_packages_in_dir(reverse = )` defaults to strong dependencies only; `which = "most"`
  adds Suggests. VERIFIED (installed Rd). Consequence: a plugin with `Suggests: gptr` is in gptr's
  reverse-suggests set and will be checked; its tests must pass against every gptr release that
  satisfies its declared API range, and must skip when gptr is absent.

### 2.8 Pitfalls found while building the prototype (all VERIFIED)

1. `on.exit(the$stack = the$stack[-1], add = TRUE)` is a *parse error* under the house style
   (`=` inside a call is argument matching): "unexpected '='". Write `on.exit({ the$stack = ... })`.
   Add to conventions §4 next to the existing "no assignment inside calls" rule.
2. Resolution caches must key on every input that changes the result: a cache filled by a
   non-activating listing (`gptr_registry()`) served a lazy placeholder to the dispatcher ("attempt to
   apply non-function") until the `activate` flag entered the key.
3. `package_version("2")` is invalid: normalise one-component requirements to `"2.0"`.
4. Tool functions generated with `environment(f) = env` plus variables assigned into `env` give
   `R CMD check` "no visible binding for global variable" NOTEs; building them as ordinary closures
   (variables in the enclosing function's frame, then `formals(f) = ...`) is clean.
5. `gptr$state$n = 1` fails on a fully locked environment (2.3).
6. TRE bounded repetition (`{0,63}`) dominated registration time (2.4).
7. Steering typed *between* `gptr_step()` calls must be drained at the start of the next turn, not
   only after that turn's tools, or the model answers the previous request first (test 13 failed until
   fixed; now matches INFRA-12 ordering).
8. A replaceable built-in must look only at *enabled* overriding records: after the user disabled
   their override (`-user:mydoc`), the built-in stayed suppressed until filters were applied inside
   the replacement check.

---

## 3. Exact specifications

### 3.1 Capability kinds and their registration contracts

Rows 1-12 and 14-23 are the 22 registry kinds (row 23 is the meta-kind); row 13 is the S3 generic
used for class-directed description, listed here because it is part of the same contract.
All constructors return `structure(list(kind = , name = , ...), class = c("gptr_<kind>", "gptr_spec"))`.
Registration: `gptr$register(spec)` in a factory (or the sugar `gptr$register_<ctor suffix>(...)`,
e.g. `gptr$register_context_block()`), `gptr_register(spec)` at top level, or a spec in a call-level
argument (`gptr(..., tools = list(spec))`, rank 0). "Never throws" means the harness wraps the call
and converts failures as stated; the conformance test checks that the capability does not rely on
throwing for control flow.

| # | Kind (constructor) | Contract: inputs -> outputs | Failure rule | Sync / async |
|---|---|---|---|---|
| 1 | `provider` (`gptr_provider(id, api, base_url, auth, models, compat, type = c("chat", "classifier", "cli"), headers, discover)`) | data record bound to an adapter by `api`; `auth` is a zero-argument resolver evaluated per request (INFRA-22) | invalid record -> `gptr_error_invalid_spec` at registration | n/a (data) |
| 2 | `adapter` (`gptr_adapter(api, transport = c("http_sse", "http_ndjson", "process_jsonl", "inprocess"), build, parse, stream, classify)`) | `http_*`/`process_jsonl`: `build(model, context, options)` -> request spec (`url, headers, body` or `command, args, stdin`), `parse(model, options)` -> normaliser `list(push, finish, fail, message)` emitting INFRA-02 events; the reactor owns I/O. `inprocess`: `stream(model, context, options, on_event)` -> final assistant message. Classifier adapters: `classify(model, state, questions, options)` -> answers with probabilities (report 04 §4) | never throws: failures after `start` become an `error` event carrying the partial message (INFRA-02); a thrown error is converted to `stop_reason = "error"` | sync callbacks driven by the reactor (INFRA-16); `inprocess` must poll `options$signal` and return within `options$deadline` |
| 3 | `router` (`gptr_router(name, route, description)`) | `route(request, ctx)` -> a registered model reference; usable as `model = <name>` | error -> fallback to the configured default model + diagnostic + `route` event | sync, budget 50 ms; System 1 through `ctx$decide()` only |
| 4 | `model` (`gptr_model(id, provider, ...)`) | catalog entry (report 09 §4.2 fields) | invalid -> error at registration | data |
| 5 | `tool` (`gptr_tool(name, description, parameters, execute, annotations, exposure = c("direct", "r", "deferred", "hidden"), execution = c("sequential", "concurrent"), namespace, snippet, guidelines, output_schema, replay)`) | `execute(input, ctx)` -> `gptr_tool_result(text, details, is_error)` or character; R data for the dispatcher in `details$value` | may throw; the dispatcher converts every failure (unknown tool, validation, denial, error, warning-as-error, timeout, interrupt) into `is_error = TRUE` (INFRA-10) | sync; `sequential` if it evaluates R or writes files |
| 6 | `mcp_server` (`gptr_mcp_server(name, command, args, url, env, headers, exposure = "r", tool_exposure, timeout)`) | the `mcpServers` entry shape (report 16 §4.2) | data; connection errors are classed conditions at first use | lazy connect |
| 7 | `skill` (`gptr_skill(path, name, description)`) | Agent Skills directory (`SKILL.md` frontmatter) | invalid frontmatter -> skipped with diagnostic (report 16 §4.8) | data |
| 8 | `prompt` (`gptr_prompt_template(name, text, description, argument_hint)`) | Pi template grammar (report 05 §3.7) | data | data |
| 9 | `command` (`gptr_command(name, handler, description, complete)`) | `handler(args, ctx)`; `args` is the raw string | error -> reported; input counted as handled | sync |
| 10 | `hook` (`gptr_hook(event, handler, matcher)`; sugar `gptr$on()`, session-scoped `gptr_on(s, ...)`) | `handler(event, ctx)` -> `NULL` or the event's patch list (3.2) | error -> diagnostic and skipped, **except** `tool_call`, `document_write`, `permission_request`: error = block (fail closed). Prototype status: `tool_call` and `document_write` fail closed (dispatch kind `block`); `permission_request` is catalogued but never emitted, and its `first_decision` dispatch skips a failing handler, so error = deny for it is design, UNCERTAIN until implemented | sync |
| 11 | `policy` (`gptr_policy(name, check, description)`) | `check(call, ctx)` -> `NULL` or `list(decision = "allow" \| "deny" \| "ask" \| "modify", reason, input)`; combined deny > ask > modify > allow; `ask` without UI -> deny with an actionable reason | error -> deny (fail closed) | sync, < 10 ms |
| 12 | `context` (`gptr_context_block(name, provide, placement = c("turn", "system", "once"), budget)`) | `provide(ctx, budget)` -> text within `budget` tokens; truncated by the harness otherwise | error -> block omitted + diagnostic | sync; must not force promises or do I/O on user objects (report 12 §3.9) |
| 13 | `describer` (S3: `gptr_describe(x, budget = 300L, ...)`) | method returns character lines, first line a header, <= budget tokens | error -> default method used | sync; leaf discipline (report 12 C2) |
| 14 | `compactor` (`gptr_compactor(name, should, compact)`) | `should(session, ctx)` -> logical; `compact(session, ctx)` -> `list(summary, first_kept_id \| keep, details, usage)` | error -> built-in strategy + diagnostic | sync (its own model calls go through the reactor) |
| 15 | `doc_format` (`gptr_doc_format(name, ext, locate, render, write)`) | report 14 §4.1 backends: `render(block)` -> lines; `write()` goes through the atomic document I/O | error -> nothing written, transcript fallback | sync; Rscript writes deferred to exit (report 14 §4.3) |
| 16 | `artifact_type` (`gptr_artifact_type(name, build, check, launch, stop)`) | report 17 §4.1-4.3 lifecycle; `launch` returns a handle with `url`, `pid` | build/check failure -> tool result with stage and log tail | launch in a child process |
| 17 | `backend` (`gptr_backend(name, start, poll, cancel, capabilities)`) | `start(spec, ctx)` -> finished session (inline) or handle with `fds`/`poll()`/`cancel()` for the reactor (report 15 §4.2) | errors -> child status `error`; cancel must kill the process tree | never block the reactor > 50 ms |
| 18 | `agent` (`gptr_agent(name, description, system, model, tools, skills, backend, max_turns, returns)`) | definition (report 20 §4.4 frontmatter superset) | invalid file -> skipped with diagnostic | data |
| 19 | `ui` (`gptr_ui(name, select, input, questions, notify, has_ui)`) | report 18 §4.9 | a failing dialog = "not approved" | blocking by nature |
| 20 | `frontend` (`gptr_frontend(name, run)`) | `run(session, ...)`: console REPL, Shiny gadget, knitr engine, RPC | errors surface to the user | owns the loop it runs |
| 21 | `setting` (`gptr_setting(name, default, description, scope = c("both", "user"), validate)`) | values read with `gptr_config()`; project may only tighten security settings | invalid value -> error at `gptr_config()` | data |
| 22 | `section` (`gptr_prompt_section(name, text, position)`) | system-prompt section; `text` string or `function(ctx)` | error -> section omitted | sync; must be stable across turns (cache) |
| 23 | `kind` (`gptr_kind(name, validate, resolve = c("first", "all"))`, `gptr_spec(kind, name, ...)`) | new capability category; `validate(spec)` -> normalised spec | invalid spec -> `gptr_error_invalid_spec` | n/a |

Inter-plugin bus (not a kind): `gptr$events$emit(channel, data)`, `gptr$events$on(channel, fn)`;
channels are namespaced `"<plugin>:<topic>"`; listener errors are diagnostics.

### 3.2 Event catalogue (D-25)

Canonical names follow Pi (snake_case) wherever the semantics match (report 05 §3.1, 41 events).
Dispatch semantics (report 05 §2.4) are kept; handlers return patches instead of mutating (R value
semantics). Claude/Codex names (report 20 §4.6) are **not** accepted by `gptr$on()`; they are mapped
only when importing a Claude plugin's `hooks.json` (report 16 §4.9), and `gptr$on("PreToolUse", ...)`
fails with "did you mean 'tool_call'?" (VERIFIED, test 20).

| Event | Semantics | Payload (besides `type`) | Handler may return | Claude/Codex alias (import only) |
|---|---|---|---|---|
| `project_trust` | first decision | `cwd` | `list(decision = "yes" \| "no", remember)` | - |
| `resources_discover` | collect | `cwd`, `reason` | `list(skill_paths, prompt_paths, agent_paths)` | - |
| `session_start`, `session_shutdown` | notify | `reason` | - | SessionStart, SessionEnd |
| `session_before_fork`, `session_before_compact` | cancel | `preparation` | `list(cancel, compaction)` | PreCompact |
| `session_compact` | notify | `strategy`, `summary_tokens` | - | PostCompact |
| `input` | transform | `text`, `source` | `list(action = "continue" \| "transform" \| "handled", text)` | UserPromptSubmit |
| `before_agent_start` | collect | `prompt`, `system_prompt_sections` | `list(message, sections)` | - |
| `agent_start`, `agent_end`, `agent_settled` | notify | `messages` | - | Stop = `agent_end` |
| `turn_start`, `turn_end` | notify / boundary | `turn`, `message`, `tool_results` | `turn_end`: `list(entries, continue)` | - |
| `context` | transform chain | `messages` | `list(messages)` | - |
| `before_provider_request` | replace chain | `payload`, `provider`, `model` | replacement payload | - |
| `message_start`, `message_update` | notify | delta-only (report 02 §4.4) | - | - |
| `message_end` | replace (same role) | `message` | `list(message)` | - |
| `tool_call` | block, **error = block** | `tool_name`, `tool_call_id`, `input`, `nested`, `parent_tool_call_id` | `list(block, reason)` or `list(input)` | PreToolUse |
| `permission_request` (gptr) | first decision, **error = deny** (design only: not emitted by the prototype, whose `first_decision` dispatch skips failing handlers) | `tool_name`, `input`, `risk`, `reason` | `list(decision = "allow" \| "deny", reason)`; lets a plugin answer an `ask` (e.g. a System 1 reviewer) before the UI | PermissionRequest |
| `tool_result` | patch chain | `tool_name`, `input`, `content`, `details`, `is_error` | `list(content, details, is_error)` | PostToolUse |
| `tool_execution_start`, `tool_execution_end` | notify | ids, `is_error` | - | - |
| `model_select`, `route` (gptr) | notify | `model`, `router` | - | - |
| `document_write` (gptr) | block + patch, **error = block** | `path`, `format`, `kind`, `text` | `list(block, reason)` or `list(text)` | - |
| `decision` (gptr) | notify | System 1 `model`, `question`, `answer`, `prob` | - | - |
| `subagent_start`, `subagent_end` (gptr) | notify | `agent`, `backend`, `usage` | - | SubagentStart, SubagentStop |
| `artifact_start`, `artifact_stop` (gptr) | notify | `id`, `url`, `version` | - | - |
| `budget_exceeded` (gptr) | notify | `usage`, `budget` | - | - |

Not ported (no R-console equivalent): shortcuts, message/entry renderers, `cache_warming_decision`,
`user_bash` (no bash tool, S-4). R code typed with `!` is an `input` of `source = "passthrough"`.

Verification note (Pi `types.ts` `on(event: ...)` overloads, commit `1b347794`): Pi has 41 events;
the table keeps 24 of them, lists 2 as not ported, and is silent on the other 15:
`after_provider_response`, `agent_before_settle`, `before_provider_headers`, `context_with_system`,
`mcp_servers_change`, `provider_stream_event`, `session_before_switch`, `session_before_tree`,
`session_compact_failed`, `session_info_changed`, `session_tree`, `thinking_level_select`,
`tool_execution_update`, `ui_prompt_start`, `ui_prompt_end`. Their status (port, rename or drop) is
an open decision, not "not needed". The nine gptr-specific events count is correct. The prototype
also emits a tenth gptr-only notify event, `compaction`, that this table omits (test 18 checks for
it); an implementation should settle on `session_compact` or add `compaction` to the catalogue.

### 3.3 The extension API object (what a factory receives)

`gptr` is a locked environment of class `gptr_extension_api` (method bindings locked, `state`
binding left assignable). Prototyped members (section 5.3):

```r
gptr$name                        # extension name, e.g. "plugin:gptrpanel/gptrpanel::panel_plugin"
gptr$dir                         # directory of the plugin (for files shipped next to it)
gptr$state                       # environment private to the extension (process lifetime)
gptr$register(spec)              # the one registration verb (staged while loading)
gptr$register_tool(...)          # sugar = gptr$register(gptr_tool(...)); one per core constructor
gptr$on(event, handler, matcher = NULL)
gptr$require(requires)           # raise gptr_error_api_version when unmet (rolls the factory back)
gptr$has(feature)                # capability negotiation, e.g. gptr$has("kind.router")
gptr$events$emit(channel, data); gptr$events$on(channel, handler)
```

Everything that acts on a session lives on `ctx` (passed to every handler), not on the API
object: `ctx$session`, `ctx$envir`, `ctx$mode()`, `ctx$ui()`, `ctx$has_ui()`, `ctx$get(kind, name)`,
`ctx$execute_tool(name, input)` (nested call through the same gate), `ctx$send_message(text, as)`,
`ctx$append_entry(type, data)`, `ctx$abort()`; design additions not prototyped: `ctx$decide()`
(System 1), `ctx$usage()`, `ctx$state()` (per-session, per-extension state), `ctx$signal`.
This removes Pi's "action methods throw until bound" state: factories run once per R process, and
actions always have a session.

### 3.4 Plugin manifest (`inst/gptr/plugin.json` in packages, `plugin.json` in directories)

```json
{
  "name": "gptrpanel",
  "version": "0.1.0",
  "description": "Reviewer panels and clinical-trial lookups",
  "gptr": {"api": ">= 1.0, < 2"},
  "skills": "skills",
  "prompts": "prompts",
  "agents": "agents",
  "mcpServers": "mcp.json",
  "extension": {
    "entry": "gptrpanel::panel_plugin",
    "activation": "lazy",
    "provides": {"tool": ["trial_lookup"], "command": ["panel"], "hook": ["tool_result"]},
    "declarations": {"trial_lookup": {"description": "Look up registered trials...", "signature": "trial_lookup(indication: string, max?: integer)"}}
  },
  "rDepends": ["ggplot2 (>= 3.5)"]
}
```

- `entry` names an **exported** function (`getExportedValue()`; no `:::`); directory plugins use
  `extensions/*.R` files whose last expression is `function(gptr)` (report 05 §4.10).
- `provides` lists kind -> names (hooks by event). `declarations` (design, not prototyped) carries
  what the model needs before activation, so a lazy tool's `r` signature is in the system prompt
  from the first request and activation does not change the cached prefix.
- Compatible superset of report 16's `.gptr-plugin/plugin.json` and Claude's `plugin.json`
  (report 16 §4.9); `.claude-plugin/plugin.json` is still consumed unmodified.

### 3.5 Version requirement grammar

`"1.2"` means `>= 1.2, < 2` (caret). Otherwise a comma-separated list of `op version` with
`op` in `>=, >, <=, <, ==`; one-component versions are normalised (`"2"` -> `"2.0"`). Sources, in
order of evaluation: manifest `gptr.api`, `DESCRIPTION` `Config/gptr/api`, factory
`attr(f, "gptr_api")`, then `gptr$require()` calls inside the factory. All VERIFIED in tests 7 and I.

### 3.6 Precedence ranks and filters

| Rank | Source | Pi equivalent (report 05 §2.2) |
|---|---|---|
| 0 | call arguments (`gptr(..., tools = list(spec))`, session hooks via `gptr_on()`) | CLI `-e` |
| 1 | project settings / `.gptr/` (trusted projects only) | 0-1 |
| 3 | user settings / user directories / `gptr_register()` at top level | 2-3 |
| 5 | plugin packages (in `plugins` order) | 4 |
| 6 | built-ins | 5 |

Same `(kind, name)`: lowest rank wins; ties: first registered wins with a `collision` diagnostic.
Kinds with `resolve = "all"` (hook, policy, context, section) keep every record, ordered by rank then
registration. A replaceable built-in extension disappears entirely when any of its capabilities is
overridden by an *enabled* record (Pi semantics; VERIFIED test 5).
Filters (settings key `filters`, call argument, prototype `gptr_filter()`): `-<extension>`
(`-builtin:permissions`), `-<kind>:<name>` (`-tool:grep`), `-plugin:<pkg>`, and `+...` to undo.
Security rule: filters from a *project* settings file may not disable `policy` or `hook` records of
the user or built-ins (a repository must not switch off the permission gate).

---

## 4. Recommended design for gptr

### 4.1 Capability map

"Tokens" is the cost to the model when the capability is enabled; "B" = implemented as a built-in
extension on the same API; "Test" = what `gptr_check()` (or the named suite) verifies.

| Category | Pi mechanism | gptr registration | Tokens (eager / deferred) | Built-in through the API | Precedence / disable | Conformance test |
|---|---|---|---|---|---|---|
| Native HTTP provider | `registerProvider(name, ProviderConfig)` | `gptr_provider(id, api, ...)` | 0 / 0 (catalog is user-facing) | B `builtin:providers` registers Anthropic, OpenAI, Google, OpenAI-compatible hosts as data | by `id`; `-provider:<id>` | fields, adapter exists, credentials never printed, fixture replay (INFRA-24d) |
| Wire adapter | `api` + `streamSimple` | `gptr_adapter(api, transport, build, parse \| stream)` | 0 | B `anthropic-messages`, `openai-responses`, `openai-completions`, `google-generative-ai`, `fake` | by `api`; a plugin may replace one | golden event sequence; error event not condition; split UTF-8 chunk invariance; abort gives partial (INFRA-02, 23) |
| Subscription CLI provider | none (Pi uses OAuth) | `gptr_provider(type = "cli")` + adapter `transport = "process_jsonl"` | 0 | B `cli-claude`, `cli-codex` (reports 07, 08, 15) | by `id` | fake-CLI fixtures stream into the reactor; abort kills tree (INFRA-19) |
| System 1 / classifier | model type `classifier`, `modelRegistry.classify` | `gptr_provider(type = "classifier")` + adapter `classify()` | 0 to System 2; S1 input tokens only | B `typesafe-system-one`, emulation adapter | by `id` | typed vector return; probabilities; abstention policy (INFRA-18, report 04 §4) |
| Router / virtual model | `registerVirtualModel(route)` | `gptr_router(name, route)` | 0 (+ S1 call if used) | none by default; `jev-router` as optional plugin | by name; `-router:<n>` | route matrix returns registered models; error falls back (test 14) |
| Tools | `registerTool` | `gptr_tool(..., exposure)` | direct 328 / r 36 / deferred 0 (+55 once) per tool | B `builtin:tools` (read, write, edit, grep, find, ls, run_r) | name; user/call override built-in; `-tool:<n>` | `gptr_check(tool)`: name, description, schema, <= 400 tokens if direct, annotations, empty input handled |
| MCP servers | `registerMcpServer` | `gptr_mcp_server(...)`; package `mcp.json` | via exposure (default `r`) | B `builtin:mcp` (replaceable) reads `mcp.json` and imports other harness configs | project > user > plugin > imported (report 16 §4.4) | spec validation; name sanitisation; era probe fixtures |
| Skills | resource directories | `gptr_skill(path)`; `resources_discover` | ~63 tokens per catalog entry / body on activation | B gptr's own `inst/gptr/skills` | first found wins, project over user | frontmatter, name = directory, description <= 1024 chars |
| Prompt templates | resource directories | `gptr_prompt_template()` | 0 until used | B none | first found wins | grammar parses (report 05 §5.1 tests) |
| Slash commands | `registerCommand` | `gptr_command(name, handler)` | 0 | B console commands (report 18 §4.4) | Pi renames duplicates; gptr: rank, collision diagnostic | handler signature |
| Hooks / events | `pi.on(event)` | `gptr_hook()`, `gptr$on()`, `gptr_on(session)` | 0; injected context capped at 10,000 chars (report 20) | B session store, document writer, console renderer are hooks | all run in rank order | fail-closed events block on error (tests 10) |
| Permission policies | example extensions on `tool_call` | `gptr_policy(name, check)` | 0 (+ denial text) | B `builtin:permissions` (modes, rules, risk classifier) | all run; deny wins; project cannot disable | verdict matrix mode x risk (report 18 §4.7) |
| Context / environment describers | none (`context` event) | `gptr_context_block()`; S3 `gptr_describe()` | declared budget per block; e.g. `session_context` 300 | B `session_context`, `r_env`, instructions | all run; budget cap per turn | budget respected; no promise forcing (tracemem suite, report 12) |
| Compaction strategies | `session_before_compact` returning a compaction | `gptr_compactor(name, should, compact)`; setting `compactor` | reports summary cost and saving | B two-stage strategy (reports 02, 20) (replaceable) | selected by setting | usage reported; skills protected; error falls back |
| Document formats / history writers | none | `gptr_doc_format()` + `document_write` event | 0 | B R, Rmd/qmd, ipynb, transcript (report 14) (replaceable) | by format name | round trip byte-identical; idempotent upsert (report 14 §5) |
| Artifact types | none | `gptr_artifact_type(name, build, check, launch, stop)` | system-prompt section only when enabled | B `shiny`, `html` (report 17) | by name | ladder: parse, launch, HTTP 200, session check |
| Sub-agent backends | subagent example extension | `gptr_backend(name, start, poll, cancel, capabilities)` | 0 | B `inline`, `worker` (callr), `cli`; opt-in `fork` | by name, chosen by agent definition | start/cancel; no orphan processes; usage roll-up (test 15) |
| Agent definitions | `.pi/agents/*.md` | `gptr_agent()`; `.gptr/agents/*.md`, `.claude/agents` | ~19 tokens per listing line | B none (files) | later wins by name (report 15 §4.10) | frontmatter, tool-name map |
| Front ends / UI | modes (tui/rpc/json/print) | `gptr_ui()`, `gptr_frontend()` | 0 | B console, none, scripted, rstudio, rpc | setting `ui` | `has_ui = FALSE` fails closed (test 9) |
| Settings / flags | `registerFlag` | `gptr_setting()`; values via `gptr_config()` | 0 | B core settings | project may only tighten | default readable (test 17b) |
| New categories | none | `gptr_kind()` + `gptr_spec()` | declared by the kind | - | as declared | validate function (test 17) |
| Inter-plugin bus | `pi.events` | `gptr$events` | 0 | - | - | listener errors are diagnostics (test 17b) |

### 4.2 Mechanism: why one registry with per-kind constructors

| Option | For | Against | Verdict |
|---|---|---|---|
| One registry, per-kind constructors, one verb (`register(spec)`) | uniform precedence, filters, diagnostics, conformance and listing for all 22 kinds; new kinds need no new API method; specs are testable values | one more concept (spec) than Pi's direct methods | **adopt**; keep Pi-style sugar `register_<x>()` generated from the constructor list |
| Per-category registration functions only (Pi) | familiar | every new category grows the API object; precedence and disable rules re-implemented per category; no meta-extensibility | reject as the only mechanism |
| Declarative manifests only | safe (no code), cheap to scan, enables lazy | cannot express behaviour (tools, policies, adapters) | use for resources and for `provides`/`declarations` |
| `function(gptr)` factories | full power, Pi mental model, transactional | runs code: needs opt-in and trust | use for code-backed capabilities, lazily |
| S3 generics | natural R dispatch on the user's object class; zero registration code; works with Suggests | global per process, cannot be disabled per session, no precedence | use only for class-directed extension points (`gptr_describe()`, and System 1 `as_state()` from report 04) |

Loading algorithm (extends report 05 §4.15):

```r
gptr_load_resources = function(cwd, args) {
  reg = registry_new()
  register_builtins(reg)                                   # the same ext_load() third parties use
  user = read_settings(gptr_user_dir())                    # filters, plugins, config
  for (f in user_extension_files()) ext_load(reg, parse_factory(f), f, "user")
  trusted = resolve_project_trust(cwd, reg)                # project_trust event: user extensions only
  if (trusted) for (f in project_extension_files(cwd)) ext_load(reg, parse_factory(f), f, "project")
  for (p in c(args$plugins, user$plugins)) plugin_load_package(reg, p, lazy = TRUE)   # declarative now, code on first use
  for (p in attached_packages_with_inst_gptr()) register_declarative(reg, p)          # skills and prompts only
  reg
}
```

### 4.3 Object system decision (D-02)

- Mutable objects: environments with an S3 class: registry (`gptr_registry`), extension API
  (`gptr_extension_api`), ctx (`gptr_ctx`, one per session, not per dispatch), session
  (`gptr_session`), dispatcher (`gptr_tools`, a classed list with `$`, `[[`, `names`, `print`
  methods). Immutable values: classed lists (specs, records, messages, results) and base-typed S3
  vectors (System 1 decisions, report 04).
- Methods: closures stored in locked environments for the API object and ctx (fast: 1.9 µs);
  exported functions (S3 generics where polymorphism is needed) for the SDK verbs, because they
  compose with `|>` (S-8) and are documented and versioned like any R function.
- No R6 or S7 in the public contract. Internal R6 is allowed only with a measured reason (none was
  found). Consequence for report 02: `Agent` and `SessionStore` become the session environment plus
  internal functions; `agent$prompt()` becomes `gptr()`/`gptr_step()`.

### 4.4 Plugins shipped by R packages (D-16)

```text
DESCRIPTION
  Imports: gptr                      # an agentic-layer package whose own exported functions call the SDK
  # or
  Suggests: gptr                     # a domain package that only ships describers, skills, templates
  Config/gptr/plugin: true           # listing marker (gptr_plugins(installed = TRUE) also finds inst/gptr)
  Config/gptr/api: >= 1.0, < 2       # API requirement readable without parsing the manifest
NAMESPACE
  export(panel_plugin)               # the factory named in plugin.json "extension.entry"
  S3method(gptr::gptr_describe, cohort)   # delayed registration; works with gptr in Suggests
inst/gptr/plugin.json                # manifest (3.4)
inst/gptr/skills/<name>/SKILL.md     # also inst/skills/ for btw compatibility (report 05)
inst/gptr/prompts/<name>.md
inst/gptr/agents/<name>.md
inst/gptr/mcp.json                   # NOT .mcp.json: hidden files draw an R CMD check NOTE
inst/gptr/extensions/<name>.R        # optional alternative to an exported factory (not analysed by R CMD check)
```

Rules:
1. **Discovery, not self-registration.** gptr finds plugins by name (`plugins =` argument or
   setting), by attached packages (declarative resources only), or by listing
   (`gptr_plugins(installed = TRUE)`, one vectorised `dir.exists()`, 3-6 ms for 618 packages).
   Plugin packages do not call gptr from `.onLoad`.
2. **Opt-in for code.** Extension code and MCP servers of a package run only when the user enabled
   the plugin (call, user settings, or trusted project settings). Skills and prompts of attached
   packages are available without enabling (report 05 §4.10, report 16 §4.9).
3. **Lazy by default.** Declarative resources register immediately; the factory runs on first use of
   anything in `provides`. `activation: "eager"` exists for plugins whose hooks must see every event
   from the start (e.g. an audit logger).
4. **Honest manifests.** `gptr_check("<pkg>")` loads the plugin eagerly in a scratch registry and
   fails when a `provides` entry is not registered by the factory; at run time a missing provided
   capability becomes a diagnostic and its placeholder is removed.
5. **Unload and reload.** gptr registers `setHook(packageEvent(pkg, "onUnload"), ...)` for every
   activated plugin; records of the unloaded namespace are dropped and the extension is re-declared
   lazily. `gptr_reload()` bumps the registry generation so any API object kept by old code raises
   `gptr_error_stale_api`.
6. **Imports vs Suggests.** Imports when the package's exported functions use the SDK
   (`gptrpanel::panel_review()`), Suggests when gptr is optional; never Enhances (not in the
   `which = "most"` reverse-dependency set).

### 4.5 Versioning and compatibility policy

1. **Version.** `gptr_api_version()` returns `package_version("MAJOR.MINOR")`, starting at `1.0`
   with gptr 1.0.0, and changes only when the extension API changes. `gptr_api_features()` lists
   `kind.*`, `event.*` and named features (`lazy_activation`, `ctx.decide`, ...).
2. **MINOR** (additive): new kinds, events, API or ctx members, optional spec fields, new payload
   fields. Handlers must ignore unknown payload fields; validators must accept unknown spec fields.
3. **MAJOR** (breaking): removing or renaming a member, kind, event or field; changing a
   contract's semantics (for example what a handler's return value means). A MAJOR bump requires
   the CRAN notice period (>= 2 weeks, section 2.7) to maintainers of reverse dependencies found
   with `which = "most"`.
4. **Deprecation without lifecycle.** An internal `gptr_deprecated(what, since, instead)` warns once
   per R session with a condition of class `gptr_deprecated` (prototyped in `utils.R`);
   `options(gptr.deprecations = "error")` turns it into an error for plugin CI. A deprecated member
   stays for at least one MINOR release and six months, and is removed only at the next MAJOR.
   Kind validators migrate old spec shapes (a spec records the API version it was written for).
5. **Negotiation.** Plugins test features (`gptr$has("kind.router")`), not package versions; the
   toy plugin registers its router only when the kind exists (VERIFIED test C).
6. **Failure is local.** An unmet requirement, a failing factory, or a missing method disables that
   one plugin with a classed condition recorded in `gptr_registry(diagnostics = TRUE)`; gptr
   start-up never fails because of a plugin.
7. **Conformance helpers** are exported and network-free: `gptr_check(spec | factory | package,
   error = FALSE)` returns a `gptr_check` data frame and, with `error = TRUE`, raises
   `gptr_error_conformance`; `gptr_fake_provider(script)` drives sessions offline (scripts may be
   functions of the request context, so tests can assert on what the model saw). Planned:
   `gptr_check()` methods for adapters with wire fixtures (INFRA-24 d) and for policies over report
   18's decision matrix. Plugin tests use `skip_if_not_installed("gptr")` when gptr is in Suggests.
8. **gptr's own release process** runs reverse-dependency checks with
   `tools::package_dependencies(reverse = TRUE, which = "most", recursive = "strong")` and keeps a
   plugin compatibility test suite (the toy plugins of this report are its seed).

### 4.6 SDK for agentic layers

```r
# create / continue (S-1, S-8)
s = gptr("Plan the analysis", model = opus, .run = FALSE)   # session with the prompt queued
gptr_step(s)                            # exactly one model turn (tool calls included)
s |> gptr("Use TPM, not CPM")           # running: steering message; idle: follow-up turn; same object
gptr_wait(s)                            # run to settlement (also takes a list of sessions)
gptr_steer(s, "stop after QC", follow_up = TRUE)
gptr_cancel(s)                          # abort (named to avoid the internal gptr_abort() error helper)
f = gptr_fork(s)                        # explicit branch: history copied, listeners and queues not

# observe and intervene
off = gptr_on(s, "tool_result", function(event, ctx) NULL)   # session-scoped hook, rank 0
off()

# sub-agents, parallelism, budgets, usage
res = gptr("Review analysis.R", agents = list(stats = gptr_agent("stats", model = opus)))
sums = gptr_map(cohorts, "Summarise this cohort", max_active = 4)          # report 15
both = gptr_parallel(plan = gptr("Plan", model = opus), lit = gptr("Summarise X", model = gemini))
s2 = gptr("Explore", budget = list(tokens = 2e5, turns = 20))              # status "budget" + event
gptr_usage(list(s, s2))                 # sums, including children
# persistence (workspace consented): sessions append to .gptr/sessions/*.jsonl automatically
gptr_sessions(); s3 = gptr_resume("s00017")
```

- Every verb takes the session object; nothing needs internals. The prototype's
  `gptrpanel::panel_review()` shows the pattern: one session per reviewer created with
  `.run = FALSE`, interleaved with `gptr_step()` round-robin, observed with `gptr_on()`, summed with
  `gptr_usage()`, judged with a final `gptr()` (VERIFIED test E).
- Model-written R code may call `gptr()` itself: a nested call made while a tool runs creates a child
  session linked to the running one (depth + 1, usage rolled up), so "sub-agents as R functions"
  (REQ-42) needs no separate API and costs about 15 tokens per call. (Not covered by the 59/21
  checks; VERIFIED in the verification pass: a fake-provider `run_r` call containing a nested
  `gptr()` produced an inner session with `depth` 1, `parent` identical to the outer session, and
  the inner session's 51 tokens added to the outer `usage$children`.)
- The console pause menu (reports 02 §4.7, 18 §2.2) and the pipe are two front doors to the same
  queue: both call `gptr_steer()`; the menu serves a blocked console, the pipe serves stepwise or
  background sessions (resolves cross-track conflict 16).

### 4.7 Exported API surface (D-28): collisions and final names

Collision scan (section 5.11): index of 41,331 exports from 592 installed packages (including base,
recommended, dplyr 284, rlang 441, purrr 184 exports), the NAMESPACE files of 37 CRAN LLM packages
extracted and MD5-verified by track 10 (mcptools 1.0.3 exports 3 names, btw 1.5.0 67, ellmer 0.5.0
130, tidyllm 0.6.0 146), plus an r-universe exports query per name (CRAN, Bioconductor,
r-universe; not exhaustive, report 10 §2.10).

**Colliding proposals (25):**

| Proposed (track) | Collides with | Final |
|---|---|---|
| `decide()`, `classify()`, `rate()` (04) | nimble, decideR...; admisc, terra and 41 others (report 10 §2.10); distr, popEpi... | none: `gptr(..., model = jev, type = )` (S-1, D-06) |
| `state()`, `as_state()` (04) | tcltk2, VanillaICE...; naijR | internal helper; `gptr(..., state = )` argument |
| `prob()`, `confidence()` (04) | copula, distr, crmPack...; psychmeta... | `gptr_prob(x, what = c("prob", "confidence"))` |
| `is_true()` (04) | rlang | not exported |
| `tools` object (06) | eppoFindeR; base package name | `gptr_tools` |
| `tools_list()`, `show_image()` (06) | mcpr; fastai, showimage | `names(gptr_tools)`; images come from plots automatically |
| `mcp_tools()`, `mcp_connect()`, `mcp_call()` (06, 16) | mcptools, LLMRagent, llm.api | `gptr_tools$<server>$<tool>()`; `gptr_mcp()` lists servers and tools |
| `mcp` object (16) | multcomp, adehabitatHR, ... | merged into `gptr_tools` namespaces |
| `mcp_serve()` (16) | vellumplot | `gptr_mcp_serve()` |
| `artifact()` (17) | icesTAF | model tool `artifact`; users: `gptr_artifacts()`, `gptr_artifact_open()` |
| `plot_image()` (17) | matter, rayimage, ... | internal |
| `llm_model()`, `llm_classify()` (03) | metacheck; mall | internal |
| `api_register()`, `auth_login/logout/status()` (03) | metasurvey; ukbflow | `gptr_register(gptr_adapter())`; `gptr_login()`, `gptr_logout()`, `gptr_providers()` |
| `agent()` (north star, 15) | LLMRagent, llm.api, rmorie, villager | alias inside `gptr(agents = list(...))` data mask only; export `gptr_agent()` |

The 51 remaining unprefixed proposals are free today (`judge`, `mcp_servers`, `mcp_add`,
`artifact_open`, `llm_stream`, `sse_parser`, ...) but are renamed or made internal anyway: D-28's
prefix rule is what keeps them free tomorrow.

**gptr-internal clashes resolved:**

| Name | Meanings proposed | Final |
|---|---|---|
| `gptr_agent()` | R6 agent (02); agent definition (06, 15, 20) | agent **definition** constructor |
| `gptr_usage()` | accounting (15, 10a); open the ChatGPT usage web page (08) | accounting; plan usage appears in `gptr_providers()` |
| `gptr_classify()` | R-code risk classifier (18) vs System 1 classification (04) | `gptr_risk()` |
| `gptr_capabilities()` | installed R packages (19) vs capability registry | `gptr_packages()` and `gptr_registry()` |
| `gptr_setting()` / `gptr_settings()` / `gptr_set()` | getter / listing / setter (05) | declaration constructor `gptr_setting()`; values via `gptr_config()` |
| `gptr_hook()` | registration verb (20) | spec constructor; session subscription `gptr_on()` |
| `gptr_tools()` | function returning the tool list (02) | the dispatcher object |
| `gptr_context()` | environment detection (18) | internal |
| `gptr_prompt()` / `gptr_prompts()` | expand / list templates (05) | `gptr("/name args")` expands; `gptr_registry("prompt")` lists |
| `gptr_models_update()`, `gptr_models_reset()`, `gptr_discover()` (09) | catalog maintenance | `gptr_models(refresh = , reset = , discover = )` |
| `gptr_read/write/edit/grep/find/ls()` (11) | data-returning tool functions | reached as `gptr_tools$grep(...)` (returns the data frame, VERIFIED); fewer exports, same behaviour |
| `gptr_panel()`, `gptr_debate()`, `gptr_review()` (15) | cross-LLM helpers | not core: shipped as a plugin or vignette (the toy `gptrpanel` shows it needs only the SDK) |

**Final exported names (76; none collides):**

| Tier | Names |
|---|---|
| Gateway | `gptr` |
| User setup and status | `gptr_init`, `gptr_config`, `gptr_env`, `gptr_login`, `gptr_logout`, `gptr_providers`, `gptr_models`, `gptr_trust`, `gptr_skills`, `gptr_agents`, `gptr_plugins`, `gptr_mcp`, `gptr_mcp_add`, `gptr_mcp_remove`, `gptr_mcp_import`, `gptr_mcp_serve`, `gptr_mcp_stop` |
| Documents, artifacts, safety | `gptr_doc`, `gptr_source`, `gptr_cache`, `gptr_artifacts`, `gptr_artifact_open`, `gptr_artifact_stop`, `gptr_artifact_export`, `gptr_permissions`, `gptr_risk` |
| Values and introspection | `gptr_usage`, `gptr_last`, `gptr_describe` (S3 generic), `gptr_return`, `gptr_prob`, `gptr_packages`, `gptr_tools` (object) |
| SDK verbs | `gptr_step`, `gptr_wait`, `gptr_on`, `gptr_steer`, `gptr_cancel`, `gptr_fork`, `gptr_parallel`, `gptr_map`, `gptr_jobs`, `gptr_sessions`, `gptr_resume` |
| Extension API | `gptr_api_version`, `gptr_api_features`, `gptr_register`, `gptr_registry`, `gptr_reload`, `gptr_check`, `gptr_fake_provider`, `gptr_tool_result`, `gptr_spec` |
| Spec constructors | `gptr_tool`, `gptr_provider`, `gptr_adapter`, `gptr_router`, `gptr_model`, `gptr_mcp_server`, `gptr_skill`, `gptr_prompt_template`, `gptr_command`, `gptr_hook`, `gptr_policy`, `gptr_context_block`, `gptr_compactor`, `gptr_doc_format`, `gptr_artifact_type`, `gptr_backend`, `gptr_agent`, `gptr_ui`, `gptr_frontend`, `gptr_setting`, `gptr_prompt_section`, `gptr_kind` |

Everything else in the prototype's NAMESPACE (`gptr_filter()`) folds into `gptr_config(filters = )`.
The model-facing tool names (`read`, `write`, `edit`, `grep`, `find`, `ls`, `run_r`, `r_inspect`,
`ask`, `agent`, `artifact`, `tool_search`) are not R exports and do not collide.

### 4.8 Token efficiency, built into the extension contract (REQ-42 / S-12)

1. Default exposure for plugin tools is `r` (36 tokens per tool instead of 328); `deferred` for
   rarely used tools (flat 55 tokens); `direct` only for tools a model is trained to call natively.
2. Per-kind budgets enforced by the harness: `r` signatures 3,000 tokens (reports 06, 16), skill
   catalog `max(8000 chars, 1% of window)` (report 16), agent listings, context blocks (declared
   `budget`, summed cap per turn), hook-injected context 10,000 characters (report 20).
3. `gptr_registry()` gains a `tokens` column (estimated declaration cost per capability, chars/4 for
   prose and chars/2 for printed R output, report 21 §2.8) so users see what a plugin costs;
   `gptr_check()` flags a `direct` declaration above 400 tokens (prototyped).
4. Lazy activation must not change the cached prefix: manifests carry `declarations` so the
   signature line exists before activation; system-prompt sections are registered at load time
   and must be stable (`gptr_prompt_section()` contract).
5. Composition over round trips: every tool, MCP tool and sub-agent is callable from one `run_r`
   evaluation (`gptr_tools$...`, nested `gptr()`); results stay R objects (`details$value`), so only
   what the model prints enters the context (illustration: 1,532 vs 109 tokens).
6. Polyglot glue through plugins: a plugin can wrap `system2()`/processx, reticulate, DBI or knitr
   engines as `r`-exposed tools (`gptr_tools$sql$query(con, "...")`), which keeps S-4 (no bash tool)
   and costs one signature line each.

---

## 5. Verified R prototypes

Everything below was executed with `Rscript --vanilla` on R 4.4.3 (macOS arm64) and is embedded
verbatim (sources and captured outputs), because the scratch directory is temporary. House style
(`=`, `|>`) holds in every R file; `lintr::lint_dir()` with `assignment_linter(operator = "=")`
reported no assignment lints on the host package (one `commented_code_linter` hit on a comment).

Reproduce:

```sh
G1=scratchpad/work/G1
sh $G1/rebuild.sh                                         # roxygenise, build, install gptr into $G1/lib
cd $G1/pkg && R_LIBS=$G1/lib Rscript --vanilla -e 'roxygen2::roxygenise("gptrpanel")'   # writes man/panel_*.Rd (not embedded)
# cohortdesc/man/cohort.Rd is hand-written and embedded in section 5.4
R CMD build --no-manual gptrpanel && R CMD build --no-manual cohortdesc
R_LIBS=$G1/lib R CMD INSTALL --library=$G1/lib gptrpanel_0.1.0.tar.gz cohortdesc_0.1.0.tar.gz
cd $G1/proto
R_LIBS=$G1/lib Rscript --vanilla test_registry.R          # 59 checks
R_LIBS=$G1/lib Rscript --vanilla test_plugin.R            # 21 checks
Rscript --vanilla bench_objsys.R
R_LIBS=$G1/lib Rscript --vanilla bench_startup.R
R_LIBS=$G1/lib Rscript --vanilla bench_lazy.R
W=$G1 R_LIBS=$G1/lib:scratchpad/rlib Rscript --vanilla tokens.R
SP=scratchpad W=$G1 Rscript --vanilla collide.R
```

The toy host package is deliberately named `gptr` (version 0.99.9000) and installed only into the
temporary library `$G1/lib`; gptr is not installed in the user library, so nothing is shadowed.

### 5.1 Host prototype package `gptr` (registry, extension API, session SDK)

`$G1/pkg/gptr/DESCRIPTION`

```text
Package: gptr
Title: Prototype of the 'gptr' Extension Registry and SDK Surface
Version: 0.99.9000
Authors@R: person("G1", "Prototype", email = "g1@example.org", role = c("aut", "cre"))
Description: Throw-away research prototype (track G1) of a single versioned
    extension registry through which every capability category of an agent
    harness registers, including its built-in features, plus the stepwise
    session interface that third-party packages build on. Not for release.
License: MIT + file LICENSE
Encoding: UTF-8
Depends: R (>= 4.2)
Imports: jsonlite, stats, utils
Suggests: testthat (>= 3.0.0)
Config/gptr/api: 1.0
RoxygenNote: 7.3.3
```

`$G1/pkg/gptr/NAMESPACE` (generated by roxygen2 7.3.3)

```text
# Generated by roxygen2: do not edit by hand

S3method("$",gptr_extension_api)
S3method("$",gptr_tools)
S3method("[[",gptr_tools)
S3method(gptr_check,"function")
S3method(gptr_check,character)
S3method(gptr_check,gptr_adapter)
S3method(gptr_check,gptr_policy)
S3method(gptr_check,gptr_tool)
S3method(gptr_describe,default)
S3method(names,gptr_tools)
S3method(print,gptr_extension_api)
S3method(print,gptr_registry)
S3method(print,gptr_results)
S3method(print,gptr_session)
S3method(print,gptr_spec)
S3method(print,gptr_tool_fn)
S3method(print,gptr_tools)
export(gptr)
export(gptr_adapter)
export(gptr_agent)
export(gptr_api_features)
export(gptr_api_version)
export(gptr_artifact_type)
export(gptr_backend)
export(gptr_cancel)
export(gptr_check)
export(gptr_command)
export(gptr_compactor)
export(gptr_config)
export(gptr_context_block)
export(gptr_describe)
export(gptr_doc_format)
export(gptr_fake_provider)
export(gptr_filter)
export(gptr_fork)
export(gptr_frontend)
export(gptr_hook)
export(gptr_kind)
export(gptr_mcp_server)
export(gptr_model)
export(gptr_on)
export(gptr_plugins)
export(gptr_policy)
export(gptr_prompt_section)
export(gptr_prompt_template)
export(gptr_provider)
export(gptr_register)
export(gptr_registry)
export(gptr_reload)
export(gptr_return)
export(gptr_router)
export(gptr_setting)
export(gptr_skill)
export(gptr_spec)
export(gptr_steer)
export(gptr_step)
export(gptr_tool)
export(gptr_tool_result)
export(gptr_tools)
export(gptr_ui)
export(gptr_usage)
export(gptr_wait)
```

`$G1/rebuild.sh`

```sh
#!/bin/sh
W=/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G1
cd $W/pkg && Rscript --vanilla -e 'roxygen2::roxygenise("gptr")' > $W/out/roxygen.log 2>&1 && R CMD build --no-manual gptr > $W/out/build.log 2>&1 && R CMD INSTALL --library=$W/lib gptr_0.99.9000.tar.gz > $W/out/install.log 2>&1 && echo "rebuilt ok" || (tail -20 $W/out/*.log)
```

`$G1/pkg/gptr/R/utils.R`

```r
# Small internal helpers. House style: "=" for assignment, "|>" for pipes.

`%||%` = function(a, b) if (is.null(a)) b else a

# Package-level state. Only the capability registry and a counter live here
# (INFRA-15: no package-global run state; the session stack is dynamic extent only).
the = new.env(parent = emptyenv())

#' Signal a classed gptr condition
#' @noRd
gptr_abort = function(message, class, ..., call = NULL) {
  cnd = structure(
    class = c(paste0("gptr_error_", class), "gptr_error", "error", "condition"),
    list(message = message, call = call, ...)
  )
  stop(cnd)
}

#' Ids without touching .Random.seed
#' @noRd
new_id = function(prefix = "") {
  the$counter = (the$counter %||% 0L) + 1L
  paste0(prefix, sprintf("%06x", the$counter))
}

#' Deprecation without lifecycle: warn once per R session per `what`
#' @noRd
gptr_deprecated = function(what, since, instead = NULL) {
  the$deprecated = the$deprecated %||% character()
  if (what %in% the$deprecated) return(invisible(FALSE))
  the$deprecated = c(the$deprecated, what)
  msg = paste0(what, " is deprecated since gptr API ", since,
               if (!is.null(instead)) paste0("; use ", instead, " instead") else "", ".")
  warning(structure(class = c("gptr_deprecated", "warning", "condition"),
                    list(message = msg, call = NULL, what = what, since = since)))
  invisible(TRUE)
}

is_string = function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)

check_fun = function(f, what, args = NULL) {
  if (!is.function(f)) gptr_abort(paste0(what, " must be a function"), "invalid_spec")
  if (!is.null(args)) {
    fa = names(formals(f))
    if (!("..." %in% fa) && length(fa) < length(args))
      gptr_abort(paste0(what, " must accept arguments (", paste(args, collapse = ", "), ")"),
                 "invalid_spec")
  }
  invisible(f)
}
```

`$G1/pkg/gptr/R/ext-version.R`

```r
# Extension API version and capability negotiation.

#' Extension API version
#'
#' The version of the public extension API, independent of the package version.
#' @return A `package_version`.
#' @export
gptr_api_version = function() package_version("1.0")

#' Features offered by this build of the extension API
#'
#' Plugins test for optional features instead of comparing package versions.
#' @return A character vector of feature names.
#' @export
gptr_api_features = function() {
  c(paste0("kind.", names(the$registry$kinds %||% list())),
    paste0("event.", names(EVENTS)),
    "lazy_activation", "staged_load", "session_view", "dispatcher")
}

# "1.2"            -> >= 1.2 and < 2  (caret semantics for a bare version)
# ">= 1.0, < 2"    -> both constraints
api_parse_requires = function(req) {
  req = trimws(strsplit(req, ",", fixed = TRUE)[[1]])
  out = list()
  for (r in req) {
    m = regmatches(r, regexec("^(>=|<=|==|>|<)?\\s*([0-9]+(\\.[0-9]+)*)$", r))[[1]]
    if (!length(m)) gptr_abort(paste0("cannot parse API requirement '", r, "'"), "api_version")
    op = if (nzchar(m[2])) m[2] else "^"
    v = if (grepl(".", m[3], fixed = TRUE)) m[3] else paste0(m[3], ".0")   # "2" -> "2.0"
    out[[length(out) + 1L]] = list(op = op, v = package_version(v))
  }
  out
}

api_satisfies = function(requires, provided = gptr_api_version()) {
  for (c in api_parse_requires(requires)) {
    ok = switch(c$op,
      ">=" = provided >= c$v, ">" = provided > c$v, "<=" = provided <= c$v,
      "<" = provided < c$v, "==" = provided == c$v,
      "^" = provided >= c$v && provided$major == c$v$major)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

#' Check an API requirement; classed error when unmet
#' @noRd
api_check = function(requires, who = "extension") {
  if (is.null(requires) || !length(requires) || !nzchar(requires)) return(invisible(TRUE))
  if (!api_satisfies(requires)) {
    gptr_abort(
      sprintf("%s requires gptr extension API %s, but this gptr provides API %s",
              who, requires, format(gptr_api_version())),
      "api_version", required = requires, provided = format(gptr_api_version()))
  }
  invisible(TRUE)
}
```

`$G1/pkg/gptr/R/ext-specs.R`

```r
# Capability spec constructors. Every constructor returns a classed list
# c("gptr_<kind>", "gptr_spec"). Registration is always the same call:
# gptr$register(spec) inside a plugin factory, or gptr_register(spec) at top level.

new_spec = function(kind, name, ...) {
  if (!is_string(name)) gptr_abort(paste0(kind, " needs a non-empty name"), "invalid_spec")
  structure(list(kind = kind, name = name, ...), class = c(paste0("gptr_", kind), "gptr_spec"))
}

#' Capability specs
#'
#' Constructors for every capability category. Each returns a spec that is
#' registered with `gptr$register()` in a plugin factory or [gptr_register()].
#' @param name Unique name within the capability kind.
#' @param description One-line description (model-facing for tools and agents).
#' @param parameters JSON-Schema object as an R list.
#' @param execute `function(input, ctx)` returning a [gptr_tool_result()] or text.
#' @param annotations MCP-style hints (`read_only`, `destructive`, `open_world`).
#' @param exposure How the model reaches the tool: `"direct"` (declared every
#'   request), `"r"` (callable from R code, one signature line), `"deferred"`
#'   (found by search), `"hidden"`.
#' @param execution `"sequential"` or `"concurrent"`.
#' @param namespace Optional namespace for the dispatcher (`gptr_tools$ns$tool`).
#' @param ... Further fields kept in the spec.
#' @return A classed spec list.
#' @export
gptr_tool = function(name, description, parameters = list(type = "object", properties = list()),
                     execute, annotations = list(), exposure = c("direct", "r", "deferred", "hidden"),
                     execution = c("sequential", "concurrent"), namespace = NULL, ...) {
  if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,63}$", name, perl = TRUE))
    gptr_abort(paste0("invalid tool name '", name, "'"), "invalid_spec")
  if (!identical(parameters$type, "object")) gptr_abort("tool parameters must be a JSON-Schema object", "invalid_spec")
  check_fun(execute, "execute", c("input", "ctx"))
  new_spec("tool", name, description = description, parameters = parameters, execute = execute,
           annotations = annotations, exposure = match.arg(exposure), execution = match.arg(execution),
           namespace = namespace, ...)
}

#' @rdname gptr_tool
#' @param text Text content of a tool result.
#' @param details R-side details, never sent to the model.
#' @param is_error Whether the result is an error.
#' @export
gptr_tool_result = function(text = "", details = NULL, is_error = FALSE) {
  structure(list(content = list(list(type = "text", text = paste(text, collapse = "\n"))),
                 details = details, is_error = isTRUE(is_error)), class = "gptr_tool_result")
}

#' @rdname gptr_tool
#' @param id Provider or model identifier.
#' @param api Wire adapter id the provider binds to.
#' @param base_url Endpoint base URL.
#' @param models List of model entries.
#' @param type `"chat"` or `"classifier"` (System 1).
#' @export
gptr_provider = function(id, api, base_url = NULL, models = list(), type = c("chat", "classifier"), ...) {
  new_spec("provider", id, api = api, base_url = base_url, models = models, type = match.arg(type), ...)
}

#' @rdname gptr_tool
#' @param stream `function(model, context, options, on_event)` returning the final
#'   assistant message; must never throw.
#' @param transport `"inprocess"`, `"http_sse"`, `"http_ndjson"` or `"process_jsonl"`.
#' @export
gptr_adapter = function(api, stream, transport = c("inprocess", "http_sse", "http_ndjson", "process_jsonl"), ...) {
  check_fun(stream, "stream", c("model", "context", "options", "on_event"))
  new_spec("adapter", api, stream = stream, transport = match.arg(transport), ...)
}

#' @rdname gptr_tool
#' @param route `function(request, ctx)` returning a model reference.
#' @export
gptr_router = function(name, route, description = "") {
  check_fun(route, "route", c("request", "ctx"))
  new_spec("router", name, route = route, description = description)
}

#' @rdname gptr_tool
#' @param provider Provider id of a model entry.
#' @export
gptr_model = function(id, provider, ...) new_spec("model", id, provider = provider, ...)

#' @rdname gptr_tool
#' @param command,args,url,env Stdio or HTTP MCP server configuration.
#' @export
gptr_mcp_server = function(name, command = NULL, args = character(), url = NULL, env = NULL,
                           exposure = c("r", "direct", "deferred", "hidden")) {
  if (is.null(command) == is.null(url)) gptr_abort("MCP server needs exactly one of command or url", "invalid_spec")
  new_spec("mcp_server", name, command = command, args = args, url = url, env = env, exposure = match.arg(exposure))
}

#' @rdname gptr_tool
#' @param path Path to a skill directory or file.
#' @export
gptr_skill = function(path, name = basename(path), description = "") {
  new_spec("skill", name, path = path, description = description)
}

#' @rdname gptr_tool
#' @export
gptr_prompt_template = function(name, text, description = "") new_spec("prompt", name, text = text, description = description)

#' @rdname gptr_tool
#' @param handler Command handler `function(args, ctx)` or hook handler `function(event, ctx)`.
#' @export
gptr_command = function(name, handler, description = "") {
  check_fun(handler, "handler", c("args", "ctx"))
  new_spec("command", name, handler = handler, description = description)
}

#' @rdname gptr_tool
#' @param event Event name (see `gptr_api_features()`).
#' @param matcher Optional tool-name regex for tool events.
#' @export
gptr_hook = function(event, handler, matcher = NULL, name = new_id("hook:")) {
  if (!event %in% names(EVENTS)) gptr_abort(hook_event_error(event), "unknown_event")
  check_fun(handler, "handler", c("event", "ctx"))
  new_spec("hook", name, event = event, handler = handler, matcher = matcher)
}

#' @rdname gptr_tool
#' @param check Policy `function(call, ctx)` returning `list(decision = "allow"|"deny"|"ask"|"modify", reason, input)`.
#' @export
gptr_policy = function(name, check, description = "") {
  check_fun(check, "check", c("call", "ctx"))
  new_spec("policy", name, check = check, description = description)
}

#' @rdname gptr_tool
#' @param provide Context block `function(ctx, budget)` returning text.
#' @param placement `"turn"` (user-role block each turn), `"system"` (cached section) or `"once"`.
#' @param budget Token budget for the block.
#' @export
gptr_context_block = function(name, provide, placement = c("turn", "system", "once"), budget = 300L) {
  check_fun(provide, "provide", c("ctx", "budget"))
  new_spec("context", name, provide = provide, placement = match.arg(placement), budget = as.integer(budget))
}

#' @rdname gptr_tool
#' @param should `function(session, ctx)` returning TRUE when compaction is due.
#' @param compact `function(session, ctx)` returning `list(summary, keep)`.
#' @export
gptr_compactor = function(name, should, compact) {
  check_fun(should, "should"); check_fun(compact, "compact")
  new_spec("compactor", name, should = should, compact = compact)
}

#' @rdname gptr_tool
#' @param ext File extensions handled by a document format.
#' @param render `function(block)` returning document lines.
#' @export
gptr_doc_format = function(name, ext, render) {
  check_fun(render, "render")
  new_spec("doc_format", name, ext = ext, render = render)
}

#' @rdname gptr_tool
#' @param build,launch,stop Artifact lifecycle functions.
#' @export
gptr_artifact_type = function(name, build, launch, stop = function(handle) invisible(NULL)) {
  check_fun(build, "build"); check_fun(launch, "launch")
  new_spec("artifact_type", name, build = build, launch = launch, stop = stop)
}

#' @rdname gptr_tool
#' @param start Backend `function(spec, ctx)` returning a finished or pollable handle.
#' @param capabilities Character flags such as `"sees_objects"`, `"parallel"`.
#' @export
gptr_backend = function(name, start, capabilities = character()) {
  check_fun(start, "start", c("spec", "ctx"))
  new_spec("backend", name, start = start, capabilities = capabilities)
}

#' @rdname gptr_tool
#' @param system System prompt of an agent definition.
#' @param model Model reference.
#' @param tools Tool names.
#' @param backend Sub-agent backend name.
#' @export
gptr_agent = function(name, description = "", system = NULL, model = NULL, tools = NULL, backend = "inline") {
  new_spec("agent", name, description = description, system = system, model = model, tools = tools, backend = backend)
}

#' @rdname gptr_tool
#' @param select,input,notify UI functions.
#' @param has_ui Whether dialogs can be answered.
#' @export
gptr_ui = function(name, select, input = function(prompt, ...) NA_character_,
                   notify = function(text, ...) invisible(NULL), has_ui = TRUE) {
  check_fun(select, "select")
  new_spec("ui", name, select = select, input = input, notify = notify, has_ui = has_ui)
}

#' @rdname gptr_tool
#' @param run Front-end `function(session, ...)`.
#' @export
gptr_frontend = function(name, run) {
  check_fun(run, "run")
  new_spec("frontend", name, run = run)
}

#' @rdname gptr_tool
#' @param default,scope Setting default and allowed scope.
#' @export
gptr_setting = function(name, default = NULL, description = "", scope = c("both", "user")) {
  new_spec("setting", name, default = default, description = description, scope = match.arg(scope))
}

#' @rdname gptr_tool
#' @param position Numeric position of a system-prompt section (lower first).
#' @export
gptr_prompt_section = function(name, text, position = 50) {
  new_spec("section", name, text = text, position = position)
}

#' @rdname gptr_tool
#' @param validate `function(spec)` returning the normalised spec (kinds only).
#' @param resolve `"first"` (one winner per name) or `"all"` (every record, ordered).
#' @export
gptr_kind = function(name, validate = identity, resolve = c("first", "all"), description = "") {
  check_fun(validate, "validate")
  new_spec("kind", name, validate = validate, resolve = match.arg(resolve), description = description)
}

#' @rdname gptr_tool
#' @param kind Kind name of a spec for a plugin-defined capability kind.
#' @export
gptr_spec = function(kind, name, ...) new_spec(kind, name, ...)

#' @export
print.gptr_spec = function(x, ...) {
  cat("<gptr ", x$kind, "> ", x$name, "\n", sep = "")
  d = x$description %||% ""
  if (nzchar(d)) cat("  ", d, "\n", sep = "")
  invisible(x)
}
```

`$G1/pkg/gptr/R/ext-events.R`

```r
# Event catalogue: canonical names (Pi-derived) and dispatch semantics.
# Claude/Codex hook names are accepted only through the alias table used when
# importing hooks.json from Claude plugins; gptr_on() suggests the canonical name.

EVENTS = c(
  project_trust = "first_decision", resources_discover = "collect",
  session_start = "notify", session_shutdown = "notify", session_before_fork = "cancel",
  session_before_compact = "cancel", session_compact = "notify",
  input = "transform", before_agent_start = "collect", agent_start = "notify", agent_end = "notify",
  agent_settled = "notify", turn_start = "notify", turn_end = "notify",
  context = "context", before_provider_request = "replace",
  message_start = "notify", message_update = "notify", message_end = "replace_message",
  tool_call = "block", permission_request = "first_decision", tool_result = "patch",
  tool_execution_start = "notify", tool_execution_end = "notify",
  model_select = "notify", route = "notify",
  document_write = "block", decision = "notify",
  subagent_start = "notify", subagent_end = "notify",
  artifact_start = "notify", artifact_stop = "notify",
  budget_exceeded = "notify", compaction = "notify"
)

EVENT_ALIASES = c(
  PreToolUse = "tool_call", PostToolUse = "tool_result", UserPromptSubmit = "input",
  SessionStart = "session_start", SessionEnd = "session_shutdown", Stop = "agent_end",
  SubagentStart = "subagent_start", SubagentStop = "subagent_end",
  PreCompact = "session_before_compact", PostCompact = "session_compact",
  PermissionRequest = "permission_request",
  pre_tool = "tool_call", post_tool = "tool_result", user_prompt = "input",
  stop = "agent_end", session_end = "session_shutdown", pre_compact = "session_before_compact",
  post_compact = "session_compact", subagent_stop = "subagent_end"
)

hook_event_error = function(event) {
  alt = EVENT_ALIASES[event]
  if (!is.na(alt)) sprintf("unknown gptr event '%s'; did you mean '%s'?", event, alt)
  else sprintf("unknown gptr event '%s'", event)
}

# Dispatch one event over an ordered list of hook records. Handlers never
# unwind the loop except where noted: a failing tool_call handler BLOCKS (fail closed).
dispatch = function(hooks, event, data, ctx) {
  kind = EVENTS[[event]]
  ev = c(list(type = event), data)
  if (!is.null(ev$tool_name)) {
    hooks = Filter(function(h) is.null(h$spec$matcher) || grepl(h$spec$matcher, ev$tool_name), hooks)
  }
  safe = function(h, ev) tryCatch(h$spec$handler(ev, ctx), error = function(e) {
    diag_add(the$registry, "handler_error", h$ext, paste0(event, ": ", conditionMessage(e)))
    structure(list(), class = "gptr_handler_error")
  })
  switch(kind,
    notify = { for (h in hooks) safe(h, ev); invisible(NULL) },
    cancel = {
      for (h in hooks) { r = safe(h, ev); if (is.list(r) && isTRUE(r$cancel)) return(r) }
      list(cancel = FALSE)
    },
    block = {
      for (h in hooks) {
        r = tryCatch(h$spec$handler(ev, ctx), error = function(e)
          list(block = TRUE, reason = paste0("hook '", h$ext, "' failed, blocking: ", conditionMessage(e))))
        if (!is.list(r)) next
        if (!is.null(r$input)) ev$input = r$input
        if (!is.null(r$text)) ev$text = r$text
        if (isTRUE(r$block)) return(list(block = TRUE, reason = r$reason %||% "blocked", input = ev$input, by = h$ext))
      }
      list(block = FALSE, input = ev$input, text = ev$text)
    },
    patch = {
      for (h in hooks) {
        r = safe(h, ev)
        if (is.list(r)) for (k in intersect(names(r), c("content", "details", "is_error"))) ev[[k]] = r[[k]]
      }
      ev[c("content", "details", "is_error")]
    },
    transform = {
      for (h in hooks) {
        r = safe(h, ev)
        if (is.list(r) && identical(r$action, "handled")) return(list(action = "handled"))
        if (is.list(r) && identical(r$action, "transform")) ev$text = r$text
      }
      list(action = "continue", text = ev$text)
    },
    context = {
      for (h in hooks) { r = safe(h, ev); if (is.list(r) && !is.null(r$messages)) ev$messages = r$messages }
      ev$messages
    },
    replace = { for (h in hooks) { r = safe(h, ev); if (!is.null(r) && !inherits(r, "gptr_handler_error")) ev$payload = r }; ev$payload },
    replace_message = {
      for (h in hooks) {
        r = safe(h, ev)
        if (is.list(r) && !is.null(r$message) && identical(r$message$role, ev$message$role)) ev$message = r$message
      }
      ev$message
    },
    first_decision = { for (h in hooks) { r = safe(h, ev); if (is.list(r) && length(r$decision)) return(r) }; NULL },
    collect = {
      acc = list()
      for (h in hooks) { r = safe(h, ev); if (is.list(r)) for (k in names(r)) acc[[k]] = c(acc[[k]], list(r[[k]])) }
      acc
    }
  )
}
```

`$G1/pkg/gptr/R/ext-registry.R`

```r
# The one capability registry. Mutable things are environments with an S3 class
# (D-02); records and specs are plain classed lists.

SOURCE_RANK = c(call = 0L, project = 1L, user = 3L, package = 5L, builtin = 6L)

registry_new = function() {
  r = new.env(parent = emptyenv())
  r$gen = 1L          # bumped on reload: invalidates API objects captured by old extensions
  r$ver = 0L          # bumped on every commit: invalidates resolution caches
  r$seq = 0L
  r$kinds = list()
  r$recs = list()
  r$exts = list()
  r$diag = list()
  r$filters = character()
  r$bus = list()
  r$cache = new.env(parent = emptyenv())
  class(r) = "gptr_registry"
  r
}

diag_add = function(reg, type, who, message) {
  if (is.null(reg)) return(invisible(NULL))
  reg$diag[[length(reg$diag) + 1L]] = list(type = type, who = who, message = message)
  invisible(NULL)
}

# ---- kinds ------------------------------------------------------------------------

CORE_CTORS = list(
  tool = "gptr_tool", provider = "gptr_provider", adapter = "gptr_adapter", router = "gptr_router",
  model = "gptr_model", mcp_server = "gptr_mcp_server", skill = "gptr_skill", prompt = "gptr_prompt_template",
  command = "gptr_command", hook = "gptr_hook", policy = "gptr_policy", context = "gptr_context_block",
  compactor = "gptr_compactor", doc_format = "gptr_doc_format", artifact_type = "gptr_artifact_type",
  backend = "gptr_backend", agent = "gptr_agent", ui = "gptr_ui", frontend = "gptr_frontend",
  setting = "gptr_setting", section = "gptr_prompt_section", kind = "gptr_kind"
)
ALL_KINDS = c("hook", "policy", "context", "section")
SUGAR_NAMES = lapply(CORE_CTORS, function(f) sub("^gptr_", "register_", f))   # register_tool, register_context_block, ...    # every record is active, ordered by rank

kind_get = function(reg, kind) {
  k = reg$kinds[[kind]]
  if (is.null(k)) gptr_abort(paste0("unknown capability kind '", kind, "'"), "unknown_kind")
  k
}

# ---- extensions ---------------------------------------------------------------------

ext_info = function(reg, name, source, requires = NULL, pkg = NA_character_, path = NA_character_,
                    replaceable = FALSE) {
  info = new.env(parent = emptyenv())
  info$name = name; info$source = source; info$rank = SOURCE_RANK[[source]]
  info$requires = requires; info$pkg = pkg; info$path = path; info$replaceable = replaceable
  info$status = "new"; info$error = NULL; info$stage = list(); info$n = 0L; info$loader = NULL
  info$provides = NULL
  reg$exts[[name]] = info
  info
}

is_filtered = function(filters, ext = NULL, kind = NULL, name = NULL, pkg = NA_character_) {
  if (!length(filters)) return(FALSE)
  keys = c(ext, if (!is.null(kind)) paste0(kind, ":", name), if (!is.na(pkg)) paste0("plugin:", pkg))
  any(paste0("-", keys) %in% filters)
}

#' Load one extension factory transactionally
#' @noRd
ext_load = function(reg, factory, name, source = "user", requires = NULL, pkg = NA_character_,
                    path = NA_character_, replaceable = FALSE) {
  info = reg$exts[[name]]
  if (!is.null(info) && identical(info$status, "loaded")) return(invisible(TRUE))
  if (is.null(info)) info = ext_info(reg, name, source, requires, pkg, path, replaceable)
  if (is_filtered(reg$filters, ext = name, pkg = pkg)) { info$status = "disabled"; return(invisible(FALSE)) }
  fail = function(e) {
    info$status = "failed"; info$error = conditionMessage(e); info$stage = list()
    diag_add(reg, "load_error", name, conditionMessage(e))
    invisible(FALSE)
  }
  ok = tryCatch({ api_check(requires %||% attr(factory, "gptr_api"), who = name); TRUE },
                gptr_error_api_version = function(e) { fail(e); FALSE })
  if (!ok) return(invisible(FALSE))
  info$status = "loading"; info$stage = list()
  api = api_new(reg, info)
  err = tryCatch({ factory(api); NULL }, error = function(e) e)
  if (!is.null(err)) return(fail(err))          # nothing staged reaches the registry: rollback
  commit(reg, info, info$stage)
  info$stage = list(); info$status = "loaded"; info$api = api
  # placeholders of a lazily declared extension are now superseded
  if (isTRUE(info$was_lazy))
    for (i in seq_along(reg$recs)) if (isTRUE(reg$recs[[i]]$lazy) && identical(reg$recs[[i]]$ext, name)) reg$recs[[i]]$dead = TRUE
  reg$ver = reg$ver + 1L
  invisible(TRUE)
}

commit = function(reg, info, specs) {
  is_kind = vapply(specs, function(s) identical(s$kind, "kind"), NA)
  specs = c(specs[is_kind], specs[!is_kind])        # kinds first, so later specs validate
  for (s in specs) {
    k = kind_get(reg, s$kind)
    s = k$validate(s)
    reg$seq = reg$seq + 1L
    rec = list(id = length(reg$recs) + 1L, kind = s$kind, name = s$name, spec = s, ext = info$name,
               source = info$source, rank = info$rank, seq = reg$seq, pkg = info$pkg, lazy = FALSE, dead = FALSE)
    reg$recs[[rec$id]] = rec
    if (identical(s$kind, "kind")) reg$kinds[[s$name]] = s
    info$n = info$n + 1L
  }
  reg$ver = reg$ver + 1L
  invisible(NULL)
}

#' Declare an extension whose factory runs on first use (lazy activation)
#' @noRd
ext_declare_lazy = function(reg, name, loader, provides, source = "package", requires = NULL,
                            pkg = NA_character_) {
  info = ext_info(reg, name, source, requires, pkg)
  info$status = "lazy"; info$loader = loader; info$provides = provides; info$was_lazy = TRUE
  if (is_filtered(reg$filters, ext = name, pkg = pkg)) { info$status = "disabled"; return(invisible(FALSE)) }
  for (kind in names(provides)) for (nm in provides[[kind]]) {
    reg$seq = reg$seq + 1L
    spec = if (kind == "hook") list(kind = "hook", name = paste0("lazy:", name, ":", nm), event = nm) else list(kind = kind, name = nm)
    reg$recs[[length(reg$recs) + 1L]] = list(id = length(reg$recs) + 1L, kind = kind, name = spec$name, spec = spec,
      ext = name, source = source, rank = SOURCE_RANK[[source]], seq = reg$seq, pkg = pkg, lazy = TRUE, dead = FALSE)
  }
  reg$ver = reg$ver + 1L
  invisible(TRUE)
}

ext_activate = function(reg, name) {
  info = reg$exts[[name]]
  if (is.null(info) || !identical(info$status, "lazy")) return(invisible(FALSE))
  factory = tryCatch(info$loader(), error = function(e) e)
  if (inherits(factory, "error")) {
    info$status = "failed"; info$error = conditionMessage(factory)
    for (i in seq_along(reg$recs)) if (identical(reg$recs[[i]]$ext, name) && isTRUE(reg$recs[[i]]$lazy)) reg$recs[[i]]$dead = TRUE
    reg$ver = reg$ver + 1L
    diag_add(reg, "load_error", name, info$error)
    return(invisible(FALSE))
  }
  info$status = "new"
  ok = ext_load(reg, factory, name, info$source, info$requires, info$pkg)
  if (!ok) { for (i in seq_along(reg$recs)) if (identical(reg$recs[[i]]$ext, name) && isTRUE(reg$recs[[i]]$lazy)) reg$recs[[i]]$dead = TRUE; reg$ver = reg$ver + 1L }
  invisible(ok)
}

# ---- resolution (precedence, filters, replaceable built-ins) ---------------------------

#' Resolve active records of one kind for a view
#' @noRd
resolve = function(reg, kind, view = NULL, activate = TRUE) {
  filters = c(reg$filters, view$filters)
  key = paste(kind, reg$ver, view$id %||% "", view$ver %||% 0L, activate, sep = "|")
  hit = reg$cache[[key]]
  if (!is.null(hit)) return(hit)
  recs = c(Filter(function(r) identical(r$kind, kind) && !r$dead, reg$recs),
           Filter(function(r) identical(r$kind, kind), view$inline %||% list()))
  recs = Filter(function(r) !is_filtered(filters, ext = r$ext, kind = r$kind, name = r$name, pkg = r$pkg), recs)
  # a replaceable built-in extension disappears entirely once any of its capabilities is overridden
  repl = replaced_exts(reg, view, filters)
  recs = Filter(function(r) !(r$ext %in% repl), recs)
  if (length(recs)) recs = recs[order(vapply(recs, `[[`, 0L, "rank"), vapply(recs, `[[`, 0L, "seq"))]
  if (kind %in% ALL_KINDS || identical(reg$kinds[[kind]]$resolve, "all")) {
    out = recs
  } else {
    out = list()
    for (r in recs) if (is.null(out[[r$name]])) out[[r$name]] = r
  }
  if (activate) {
    lazy_exts = unique(vapply(Filter(function(r) isTRUE(r$lazy), out), `[[`, "", "ext"))
    if (length(lazy_exts)) {
      for (e in lazy_exts) ext_activate(reg, e)
      return(resolve(reg, kind, view, activate = FALSE))
    }
  }
  reg$cache[[key]] = out
  out
}

replaced_exts = function(reg, view, filters = character()) {
  out = character()
  for (info in reg$exts) {
    if (!isTRUE(info$replaceable) || !identical(info$status, "loaded")) next
    mine = Filter(function(r) identical(r$ext, info$name) && !r$dead && r$kind != "hook", reg$recs)
    for (m in mine) {
      other = Filter(function(r) identical(r$kind, m$kind) && identical(r$name, m$name) && !identical(r$ext, info$name) && !r$dead &&
                       !is_filtered(filters, ext = r$ext, kind = r$kind, name = r$name, pkg = r$pkg),
                     c(reg$recs, view$inline %||% list()))
      if (length(other)) { out = c(out, info$name); break }
    }
  }
  out
}

cap_get = function(reg, kind, name, view = NULL) {
  r = resolve(reg, kind, view)[[name]]
  if (is.null(r)) NULL else r$spec
}

# ---- the extension API object -----------------------------------------------------------

api_new = function(reg, info) {
  gen = reg$gen
  alive = function() {
    if (!identical(reg$gen, gen))
      gptr_abort(paste0("this gptr API object belongs to extension '", info$name,
                        "' from a registry that was reloaded; use the api passed to the new factory call"), "stale_api")
  }
  api = new.env(parent = emptyenv())
  api$name = info$name
  api$dir = info$path
  api$state = new.env(parent = emptyenv())
  api$register = function(x) {
    alive()
    if (!inherits(x, "gptr_spec")) gptr_abort("register() needs a spec made by a gptr_*() constructor", "invalid_spec")
    staged_kinds = vapply(Filter(function(s) identical(s$kind, "kind"), info$stage), `[[`, "", "name")
    if (!(x$kind %in% staged_kinds)) kind_get(reg, x$kind)
    if (identical(info$status, "loading")) info$stage[[length(info$stage) + 1L]] = x
    else commit(reg, info, list(x))
    invisible(x)
  }
  api$on = function(event, handler, matcher = NULL) api$register(gptr_hook(event, handler, matcher))
  for (k in names(CORE_CTORS)) local({
    ctor = get(CORE_CTORS[[k]], mode = "function")
    api[[SUGAR_NAMES[[k]]]] = function(...) api$register(ctor(...))
  })
  api$require = function(requires) api_check(requires, who = info$name)
  api$has = function(feature) feature %in% gptr_api_features()
  api$events = list(
    emit = function(channel, data = NULL) {
      alive()
      for (h in reg$bus[[channel]]) tryCatch(h(data), error = function(e) diag_add(reg, "bus_error", info$name, conditionMessage(e)))
      invisible(NULL)
    },
    on = function(channel, handler) { alive(); reg$bus[[channel]] = c(reg$bus[[channel]], list(handler)); invisible(NULL) }
  )
  lockEnvironment(api)                                   # no new bindings
  for (nm in setdiff(ls(api, all.names = TRUE), "state")) lockBinding(nm, api)   # methods frozen; api$state$x = v works
  class(api) = "gptr_extension_api"
  api
}

#' @export
`$.gptr_extension_api` = function(x, name) {
  if (!exists(name, envir = x, inherits = FALSE))
    gptr_abort(sprintf("the gptr extension API %s has no method '%s'; test with gptr$has() or require a newer API",
                       format(gptr_api_version()), name), "api_missing")
  get(name, envir = x, inherits = FALSE)
}

#' @export
print.gptr_extension_api = function(x, ...) { cat("<gptr extension API ", format(gptr_api_version()), "> ", x$name, "\n", sep = ""); invisible(x) }

# ---- public registration surface ----------------------------------------------------------

#' Register capabilities, plugin factories or plugin packages
#'
#' @param x A spec from a `gptr_*()` constructor, a list of specs, a plugin factory
#'   `function(gptr)`, or the name of a plugin package or directory.
#' @param name Extension name used in diagnostics and `-name` filters.
#' @param source Precedence source: `"user"`, `"project"` or `"call"`.
#' @param lazy For plugin packages: activate code on first use (default) or now.
#' @return Invisibly `TRUE` when the registration succeeded.
#' @export
gptr_register = function(x, name = NULL, source = c("user", "project", "call"), lazy = TRUE) {
  source = match.arg(source)
  reg = the$registry
  if (inherits(x, "gptr_spec")) x = list(x)
  if (is.list(x) && !is.function(x)) {
    name = name %||% paste0(source, ":inline")
    info = reg$exts[[name]] %||% { i = ext_info(reg, name, source); i$status = "loaded"; i }
    commit(reg, info, x)
    return(invisible(TRUE))
  }
  if (is.function(x)) return(invisible(ext_load(reg, x, name %||% new_id("inline:"), source)))
  if (is_string(x)) {
    if (dir.exists(x)) return(invisible(plugin_load_dir(reg, x, source)))
    return(invisible(plugin_load_package(reg, x, lazy = lazy)))
  }
  gptr_abort("cannot register this object", "invalid_spec")
}

#' Enable or disable capabilities by filter
#'
#' @param ... Filters such as `"-builtin:permissions"`, `"-tool:grep"`, `"-plugin:pkg"`;
#'   a leading `+` removes a filter.
#' @return Invisibly, the active filters.
#' @export
gptr_filter = function(...) {
  f = c(...)
  reg = the$registry
  add = f[startsWith(f, "-")]; rm = sub("^\\+", "-", f[startsWith(f, "+")])
  reg$filters = setdiff(unique(c(reg$filters, add)), rm)
  reg$ver = reg$ver + 1L
  invisible(reg$filters)
}

#' List the capability registry
#'
#' @param kind Optional kind to show.
#' @param diagnostics Return load diagnostics instead of capabilities.
#' @return A data frame.
#' @export
gptr_registry = function(kind = NULL, diagnostics = FALSE) {
  reg = the$registry
  if (diagnostics) {
    d = reg$diag
    return(data.frame(type = vapply(d, `[[`, "", "type"), who = vapply(d, `[[`, "", "who"),
                      message = vapply(d, `[[`, "", "message")))
  }
  kinds = kind %||% names(reg$kinds)
  rows = list()
  for (k in kinds) {
    act = resolve(reg, k, activate = FALSE)
    act_ids = vapply(act, `[[`, 0L, "id")
    for (r in Filter(function(r) identical(r$kind, k) && !r$dead, reg$recs)) {
      rows[[length(rows) + 1L]] = data.frame(kind = k, name = r$name, ext = r$ext, source = r$source,
        status = if (r$id %in% act_ids) (if (r$lazy) "lazy" else "active") else "shadowed",
        exposure = r$spec$exposure %||% "")
    }
  }
  if (!length(rows)) return(data.frame(kind = character(), name = character()))
  do.call(rbind, rows)
}

#' Reload the registry
#'
#' Invalidates every extension API object handed out before (they raise
#' `gptr_error_stale_api`), then rebuilds built-ins and enabled plugins.
#' @return Invisibly the new registry.
#' @export
gptr_reload = function() {
  old = the$registry
  old$gen = old$gen + 1L
  the$registry = registry_new()
  the$registry$filters = old$filters
  register_builtins(the$registry)
  for (p in the$enabled %||% character()) plugin_load_package(the$registry, p)
  invisible(the$registry)
}

#' @export
print.gptr_registry = function(x, ...) {
  n = sum(!vapply(x$recs, `[[`, NA, "dead"))
  cat("<gptr registry> API ", format(gptr_api_version()), ", ", length(x$exts), " extensions, ",
      n, " capabilities, ", length(x$kinds), " kinds\n", sep = "")
  invisible(x)
}
```

`$G1/pkg/gptr/R/ext-plugins.R`

```r
# Plugins: R packages shipping inst/gptr/ and plain directories.
# Declarative resources (skills, prompts, agents, MCP entries) never run code.
# Extension code runs only for plugins the user enabled, and lazily by default.

read_manifest = function(root) {
  f = file.path(root, "plugin.json")
  if (!file.exists(f)) return(list())
  jsonlite::fromJSON(f, simplifyVector = FALSE)
}

md_description = function(path) {
  l = readLines(path, warn = FALSE, encoding = "UTF-8")
  d = grep("^description:", l, value = TRUE)
  if (length(d)) trimws(sub("^description:", "", d[1])) else ""
}

declarative_specs = function(root, man) {
  out = list()
  sk = file.path(root, man$skills %||% "skills")
  for (d in list.dirs(sk, recursive = FALSE)) {
    f = file.path(d, "SKILL.md")
    if (file.exists(f)) out[[length(out) + 1L]] = gptr_skill(d, basename(d), md_description(f))
  }
  pr = file.path(root, man$prompts %||% "prompts")
  for (f in list.files(pr, "\\.md$", full.names = TRUE))
    out[[length(out) + 1L]] = gptr_prompt_template(sub("\\.md$", "", basename(f)),
      paste(readLines(f, warn = FALSE), collapse = "\n"), md_description(f))
  ag = file.path(root, man$agents %||% "agents")
  for (f in list.files(ag, "\\.md$", full.names = TRUE))
    out[[length(out) + 1L]] = gptr_agent(sub("\\.md$", "", basename(f)), md_description(f))
  mcp = file.path(root, man$mcpServers %||% ".mcp.json")
  if (file.exists(mcp)) {
    j = jsonlite::fromJSON(mcp, simplifyVector = FALSE)$mcpServers
    for (nm in names(j)) {
      s = j[[nm]]
      out[[length(out) + 1L]] = gptr_mcp_server(nm, command = s$command, args = unlist(s$args %||% list()),
                                                url = s$url, exposure = s$exposure %||% "r")
    }
  }
  out
}

#' Load a plugin package (inst/gptr) without ':::'
#' @noRd
plugin_load_package = function(reg, pkg, lazy = TRUE) {
  root = system.file("gptr", package = pkg)
  if (!nzchar(root)) gptr_abort(paste0("package '", pkg, "' is not installed or ships no inst/gptr/"), "not_a_plugin")
  man = read_manifest(root)
  requires = man$gptr$api %||% utils::packageDescription(pkg, fields = "Config/gptr/api")
  if (identical(requires, NA)) requires = NULL
  name = paste0("plugin:", pkg)
  if (is_filtered(reg$filters, ext = name, pkg = pkg)) return(invisible(FALSE))
  ok = tryCatch({ api_check(requires, who = name); TRUE }, gptr_error_api_version = function(e) {
    diag_add(reg, "load_error", name, conditionMessage(e)); FALSE })
  if (!ok) return(invisible(FALSE))
  info = reg$exts[[name]] %||% ext_info(reg, name, "package", requires, pkg, root)
  if (!identical(info$status, "loaded")) { commit(reg, info, declarative_specs(root, man)); info$status = "loaded" }
  entry = man$extension
  if (!is.null(entry)) {
    ename = paste0(name, "/", entry$entry)
    fun = sub("^.*::", "", entry$entry)
    loader = function() getExportedValue(asNamespace(pkg), fun)
    provides = lapply(entry$provides %||% list(), unlist)
    if (lazy && length(provides) && !identical(entry$activation, "eager")) {
      if (is.null(reg$exts[[ename]])) ext_declare_lazy(reg, ename, loader, provides, "package", requires, pkg)
    } else {
      ext_load(reg, loader(), ename, "package", requires, pkg)
    }
    plugin_watch_unload(pkg)
  }
  the$enabled = union(the$enabled %||% character(), pkg)
  invisible(TRUE)
}

# When a plugin namespace is unloaded (reinstall, devtools::load_all), its records
# become stale: mark them dead and re-declare the extension lazily from its manifest.
plugin_watch_unload = function(pkg) {
  the$watched = the$watched %||% character()
  if (pkg %in% the$watched) return(invisible())
  the$watched = c(the$watched, pkg)
  setHook(packageEvent(pkg, "onUnload"), function(...) plugin_invalidate(pkg))
  invisible()
}

plugin_invalidate = function(pkg) {
  reg = the$registry
  for (i in seq_along(reg$recs)) if (identical(reg$recs[[i]]$pkg, pkg) && !isTRUE(reg$recs[[i]]$lazy) &&
                                     !identical(reg$recs[[i]]$ext, paste0("plugin:", pkg))) reg$recs[[i]]$dead = TRUE
  for (info in reg$exts) if (identical(info$pkg, pkg) && !is.null(info$loader)) {
    info$status = "lazy"
    ext_declare_lazy_again(reg, info)
  }
  reg$ver = reg$ver + 1L
  diag_add(reg, "unloaded", pkg, "plugin namespace unloaded; extension will re-activate on next use")
  invisible()
}

ext_declare_lazy_again = function(reg, info) {
  loader = info$loader; provides = info$provides
  reg$exts[[info$name]] = NULL
  ext_declare_lazy(reg, info$name, loader, provides, info$source, info$requires, info$pkg)
}

#' Load a directory plugin (plugin.json + skills/ + extensions/*.R)
#' @noRd
plugin_load_dir = function(reg, path, source = "user") {
  man = read_manifest(path)
  name = paste0("dir:", man$name %||% basename(path))
  info = reg$exts[[name]] %||% ext_info(reg, name, source, man$gptr$api, NA_character_, path)
  commit(reg, info, declarative_specs(path, man))
  info$status = "loaded"
  for (f in sort(list.files(file.path(path, "extensions"), "\\.[Rr]$", full.names = TRUE), method = "radix")) {
    env = new.env(parent = globalenv())
    val = NULL
    for (e in parse(f, keep.source = FALSE, encoding = "UTF-8")) val = eval(e, env)
    ext_load(reg, val, paste0(name, "/", basename(f)), source, man$gptr$api, path = path)
  }
  invisible(TRUE)
}

#' List plugin packages
#'
#' @param installed Scan every installed package (vectorised `dir.exists()`),
#'   not only enabled ones.
#' @return A data frame of plugin packages.
#' @export
gptr_plugins = function(installed = FALSE) {
  pk = if (installed) {
    libs = .libPaths(); dirs = list.files(libs, full.names = TRUE)
    basename(dirs[dir.exists(file.path(dirs, "gptr"))])
  } else the$enabled %||% character()
  data.frame(package = pk, enabled = pk %in% (the$enabled %||% character()))
}
```

`$G1/pkg/gptr/R/session.R`

```r
# The session object (S-8): an environment with an S3 class, so every binding
# that holds it sees the same growing session. gptr() returns it; `|>` steers it.

session_new = function(model = NULL, tools = NULL, mode = NULL, envir = parent.frame(),
                       budget = NULL, parent = NULL, max_turns = 20L) {
  s = new.env(parent = emptyenv())
  s$id = new_id("s")
  s$model = model; s$mode = mode %||% config_get("mode"); s$envir = envir
  s$messages = list(); s$pending = list(); s$steer = list(); s$follow = list()
  s$status = "idle"; s$text = ""; s$value = NULL; s$turn = 0L; s$max_turns = max_turns
  s$usage = list(input = 0, output = 0, turns = 0L, children = 0)
  s$budget = budget; s$parent = parent; s$depth = if (is.null(parent)) 0L else parent$depth + 1L
  s$doc = character(); s$trace = character(); s$ui = config_get("ui")
  s$view = list(id = s$id, ver = 0L, filters = character(), inline = list(), active_tools = NULL)
  if (is.character(tools)) s$view$active_tools = tools
  if (is.list(tools)) for (t in tools) view_add(s, t)
  class(s) = "gptr_session"
  s
}

view_add = function(s, spec) {
  rec = list(id = -length(s$view$inline) - 1L, kind = spec$kind, name = spec$name, spec = spec, ext = paste0("session:", s$id),
             source = "call", rank = 0L, seq = length(s$view$inline) + 1L, pkg = NA_character_, lazy = FALSE, dead = FALSE)
  s$view$inline[[length(s$view$inline) + 1L]] = rec
  s$view$ver = s$view$ver + 1L
  rec
}

session_ctx = function(s) {
  if (!is.null(s$ctx)) return(s$ctx)
  ctx = new.env(parent = emptyenv())
  ctx$session = s
  ctx$envir = s$envir
  ctx$ui = function() cap_get(the$registry, "ui", s$ui, s$view) %||% cap_get(the$registry, "ui", "none", s$view)
  ctx$has_ui = function() isTRUE(ctx$ui()$has_ui)
  ctx$mode = function() s$mode
  ctx$get = function(kind, name) cap_get(the$registry, kind, name, s$view)
  ctx$execute_tool = function(name, input) run_tool_call(s, list(id = new_id("n"), name = name, arguments = input), ctx, nested = TRUE)
  ctx$append_entry = function(type, data = NULL) { s$trace = c(s$trace, paste0("entry:", type)); invisible(NULL) }
  ctx$send_message = function(text, as = c("follow_up", "steer")) {
    as = match.arg(as); msg = list(role = "user", content = text, custom = TRUE)
    if (as == "steer") s$steer[[length(s$steer) + 1L]] = msg else s$follow[[length(s$follow) + 1L]] = msg
    invisible(NULL)
  }
  ctx$abort = function() { s$abort = TRUE; invisible(NULL) }
  lockEnvironment(ctx, bindings = TRUE)
  class(ctx) = "gptr_ctx"
  s$ctx = ctx
  ctx
}

emit = function(s, event, data = list(), ctx = session_ctx(s)) {
  s$trace = c(s$trace, event)
  reg = the$registry
  pick = function() Filter(function(r) identical(r$spec$event, event), resolve(reg, "hook", s$view, activate = FALSE))
  hooks = pick()
  lazy = unique(vapply(Filter(function(r) isTRUE(r$lazy), hooks), `[[`, "", "ext"))
  if (length(lazy)) { for (e in lazy) ext_activate(reg, e); hooks = pick() }
  hooks = Filter(function(r) !isTRUE(r$lazy), hooks)
  dispatch(hooks, event, data, ctx)
}

session_tools = function(s) {
  all = resolve(the$registry, "tool", s$view)
  if (!is.null(s$view$active_tools)) all = all[names(all) %in% s$view$active_tools]
  all
}

resolve_model = function(s, ctx) {
  m = s$model %||% config_get("model")
  if (inherits(m, "gptr_model")) return(m)
  if (is_string(m)) {
    r = cap_get(the$registry, "router", m, s$view)
    if (!is.null(r)) {
      picked = r$route(list(messages = s$messages, session = s), ctx)
      emit(s, "route", list(router = m, model = picked$name), ctx)
      return(picked)
    }
    mm = cap_get(the$registry, "model", m, s$view)
    if (!is.null(mm)) return(mm)
  }
  gptr_abort("no model: pass model = or set gptr_config(model = )", "no_model")
}

system_prompt = function(s, tools, ctx) {
  secs = resolve(the$registry, "section", s$view)
  secs = secs[order(vapply(secs, function(r) as.numeric(r$spec$position), 0))]
  txt = vapply(secs, function(r) { t = r$spec$text; if (is.function(t)) t(ctx) else t }, "")
  sig = r_signatures(tools)
  paste(c(txt, if (length(sig)) c("<r_functions>", sig, "</r_functions>")), collapse = "\n")
}

context_blocks = function(s, ctx) {
  out = list()
  for (r in resolve(the$registry, "context", s$view)) {
    if (!identical(r$spec$placement, "turn")) next
    txt = tryCatch(r$spec$provide(ctx, r$spec$budget), error = function(e) "")
    txt = truncate_tokens(paste(txt, collapse = "\n"), r$spec$budget)
    if (nzchar(txt)) out[[length(out) + 1L]] = list(role = "user", content = paste0("<", r$name, ">\n", txt, "\n</", r$name, ">"), context = TRUE)
  }
  out
}

# chars/4 for prose; chars/2 for printed R output (report 21 s2.8)
estimate_tokens = function(x, printed = FALSE) ceiling(sum(nchar(x, type = "chars")) / if (printed) 2 else 4)
truncate_tokens = function(x, budget) {
  if (estimate_tokens(x) <= budget) return(x)
  paste0(substr(x, 1L, budget * 4L - 20L), "\n[truncated to budget]")
}

policy_verdict = function(s, call, ctx) {
  input = call$input
  for (p in resolve(the$registry, "policy", s$view)) {
    v = tryCatch(p$spec$check(utils::modifyList(call, list(input = input)), ctx),
                 error = function(e) list(decision = "deny", reason = paste0("policy '", p$name, "' failed: ", conditionMessage(e))))
    if (is.null(v)) next
    if (identical(v$decision, "deny")) return(list(decision = "deny", reason = v$reason %||% "denied", by = p$name, input = input))
    if (identical(v$decision, "modify")) input = v$input
    if (identical(v$decision, "ask")) call$ask = c(call$ask, v$reason %||% p$name)
  }
  list(decision = if (length(call$ask)) "ask" else "allow", input = input, reason = call$ask)
}

run_tool_call = function(s, tc, ctx, nested = FALSE) {
  err = function(text) gptr_tool_result(text, is_error = TRUE)
  tool = resolve(the$registry, "tool", s$view)[[tc$name]]
  if (is.null(tool) || (!nested && !(tc$name %in% names(session_tools(s))))) return(err(paste0("Tool ", tc$name, " not found")))
  tool = tool$spec
  gate = emit(s, "tool_call", list(tool_name = tc$name, tool_call_id = tc$id, input = tc$arguments, nested = nested), ctx)
  if (isTRUE(gate$block)) return(err(gate$reason))
  v = policy_verdict(s, list(tool = tc$name, annotations = tool$annotations, input = gate$input %||% tc$arguments), ctx)
  if (identical(v$decision, "ask")) {
    ui = ctx$ui()
    ans = if (isTRUE(ui$has_ui)) tryCatch(ui$select(paste0("Allow ", tc$name, "?"), c("Yes", "No")), error = function(e) 2L) else NA
    if (!identical(as.integer(ans), 1L)) v = list(decision = "deny", reason = if (is.na(ans)) "needs approval but no UI is available; not performed" else "denied by user")
  }
  if (identical(v$decision, "deny")) return(err(v$reason))
  emit(s, "tool_execution_start", list(tool_name = tc$name, tool_call_id = tc$id), ctx)
  res = tryCatch(tool$execute(v$input, ctx), error = function(e) err(conditionMessage(e)),
                 interrupt = function(i) err("Operation aborted"))
  if (is.character(res)) res = gptr_tool_result(res)
  patch = emit(s, "tool_result", list(tool_name = tc$name, tool_call_id = tc$id, input = v$input,
                                      content = res$content, details = res$details, is_error = res$is_error), ctx)
  res[names(patch)] = patch
  emit(s, "tool_execution_end", list(tool_name = tc$name, tool_call_id = tc$id, is_error = isTRUE(res$is_error)), ctx)
  res
}

result_text = function(res) paste(vapply(res$content, function(b) b$text %||% "", ""), collapse = "\n")

#' Advance a session by one model turn
#'
#' The stepwise loop for orchestrators and tests: starts the pending prompt if
#' idle, calls the model once, runs its tool calls, delivers steering, and
#' settles when there is nothing left to do.
#' @param s A session returned by [gptr()].
#' @return The session, invisibly.
#' @export
gptr_step = function(s) {
  stopifnot(inherits(s, "gptr_session"))
  if (s$status %in% c("done", "idle", "aborted", "budget") && !length(s$pending) && !length(s$follow)) return(invisible(s))
  ctx = session_ctx(s)
  the$stack = c(list(s), the$stack)
  on.exit({ the$stack = the$stack[-1] }, add = TRUE)
  if (!identical(s$status, "running")) {
    p = if (length(s$pending)) s$pending[[1]] else s$follow[[1]]
    if (length(s$pending)) s$pending = s$pending[-1] else s$follow = s$follow[-1]
    inp = emit(s, "input", list(text = p$content, source = "call"), ctx)
    if (identical(inp$action, "handled")) return(invisible(s))
    bas = emit(s, "before_agent_start", list(prompt = inp$text), ctx)
    s$messages[[length(s$messages) + 1L]] = list(role = "user", content = inp$text)
    for (m in bas$message) s$messages[[length(s$messages) + 1L]] = m
    s$status = "running"; s$turn = 0L
    emit(s, "agent_start", list(), ctx)
  }
  if (isTRUE(s$abort)) { s$status = "aborted"; emit(s, "agent_end", list(), ctx); return(invisible(s)) }
  s$turn = s$turn + 1L
  emit(s, "turn_start", list(turn = s$turn), ctx)
  for (m in s$steer) s$messages[[length(s$messages) + 1L]] = m     # steering queued between steps
  s$steer = list()
  tools = session_tools(s)
  model = resolve_model(s, ctx)
  adapter = cap_get(the$registry, "adapter", model$api %||% model$provider, s$view)
  context = list(system = system_prompt(s, tools, ctx),
                 messages = c(context_blocks(s, ctx), emit(s, "context", list(messages = s$messages), ctx)),
                 tools = declarations(tools))
  msg = tryCatch(adapter$stream(model, context, list(session = s$id), function(ev) NULL),
                 error = function(e) list(role = "assistant", content = "", stop_reason = "error", error_message = conditionMessage(e)))
  msg = emit(s, "message_end", list(message = msg), ctx)
  s$messages[[length(s$messages) + 1L]] = msg
  s$usage$input = s$usage$input + (msg$usage$input %||% 0); s$usage$output = s$usage$output + (msg$usage$output %||% 0)
  s$usage$turns = s$usage$turns + 1L
  calls = msg$tool_calls %||% list()
  for (tc in calls) {
    res = run_tool_call(s, tc, ctx)
    s$messages[[length(s$messages) + 1L]] = list(role = "tool_result", tool_call_id = tc$id, tool_name = tc$name,
                                                 content = result_text(res), is_error = isTRUE(res$is_error))
  }
  emit(s, "turn_end", list(turn = s$turn, n_tools = length(calls)), ctx)
  steered = length(s$steer) > 0L
  for (m in s$steer) s$messages[[length(s$messages) + 1L]] = m
  s$steer = list()
  comp = cap_get(the$registry, "compactor", config_get("compactor"), s$view)
  if (!is.null(comp) && isTRUE(comp$should(s, ctx))) {
    out = comp$compact(s, ctx)
    s$messages = c(list(list(role = "user", content = out$summary, compaction = TRUE)), utils::tail(s$messages, out$keep))
    emit(s, "compaction", list(strategy = comp$name), ctx)
  }
  b = s$budget
  over = !is.null(b) && ((!is.null(b$tokens) && s$usage$input + s$usage$output > b$tokens) || (!is.null(b$turns) && s$usage$turns >= b$turns))
  if (over) { s$status = "budget"; emit(s, "budget_exceeded", list(usage = s$usage), ctx); return(invisible(s)) }
  if (identical(msg$stop_reason, "error")) { s$status = "error"; s$text = msg$error_message; emit(s, "agent_end", list(), ctx); return(invisible(s)) }
  if (!length(calls) && !steered) {
    s$text = msg$content %||% ""
    emit(s, "agent_end", list(), ctx)
    s$status = "done"
    emit(s, "agent_settled", list(), ctx)
  } else if (s$turn >= s$max_turns) {
    s$status = "done"; s$text = "[max_turns reached]"
  }
  invisible(s)
}

#' Run until settled
#'
#' @param x A session, or a list of sessions.
#' @param max_steps Safety cap on steps.
#' @return `x`, invisibly.
#' @export
gptr_wait = function(x, max_steps = 100L) {
  if (is.list(x) && !is.environment(x)) { lapply(x, gptr_wait, max_steps = max_steps); return(invisible(x)) }
  for (i in seq_len(max_steps)) {
    if (!identical(x$status, "running") && !length(x$pending) && !length(x$follow)) break
    gptr_step(x)
  }
  invisible(x)
}

#' Subscribe to session events
#'
#' Adds a session-scoped hook (highest precedence). Handlers use the same
#' contract as plugin hooks, so they may block tool calls or patch results.
#' @param x A session.
#' @param event Event name.
#' @param handler `function(event, ctx)`.
#' @param matcher Optional tool-name regex.
#' @return An unsubscribe function, invisibly.
#' @export
gptr_on = function(x, event, handler, matcher = NULL) {
  rec = view_add(x, gptr_hook(event, handler, matcher))
  invisible(function() {
    x$view$inline = Filter(function(r) !identical(r$id, rec$id), x$view$inline)
    x$view$ver = x$view$ver + 1L
    invisible(NULL)
  })
}

#' Queue a steering or follow-up message
#'
#' @param x A session.
#' @param text Message text.
#' @param follow_up Deliver after the run settles instead of after the current turn.
#' @return The session, invisibly.
#' @export
gptr_steer = function(x, text, follow_up = FALSE) {
  msg = list(role = "user", content = text)
  if (follow_up || !identical(x$status, "running")) x$follow[[length(x$follow) + 1L]] = msg
  else x$steer[[length(x$steer) + 1L]] = msg
  invisible(x)
}

#' Cancel a running session
#' @param x A session.
#' @return The session, invisibly.
#' @export
gptr_cancel = function(x) { x$abort = TRUE; invisible(x) }

#' Fork a session explicitly
#'
#' Copies history and configuration; never shares listeners, queues or
#' connections (INFRA-14).
#' @param x A session.
#' @return A new session.
#' @export
gptr_fork = function(x) {
  f = session_new(x$model, NULL, x$mode, x$envir, x$budget, NULL, x$max_turns)
  f$messages = x$messages; f$text = x$text; f$value = x$value; f$status = if (x$status == "running") "idle" else x$status
  f$view$active_tools = x$view$active_tools
  f$view$inline = Filter(function(r) !identical(r$kind, "hook"), x$view$inline)
  f$forked_from = x$id
  f
}

#' Usage of a session, including sub-agents
#' @param x A session or a list of sessions.
#' @return A list with input and output token counts and turns.
#' @export
gptr_usage = function(x) {
  if (inherits(x, "gptr_session")) return(x$usage)
  u = lapply(x, gptr_usage)
  list(input = sum(vapply(u, `[[`, 0, "input")), output = sum(vapply(u, `[[`, 0, "output")),
       turns = sum(vapply(u, `[[`, 0L, "turns")))
}

#' Designate the R value of the running request
#' @param value Any R object.
#' @return `value`, invisibly.
#' @export
gptr_return = function(value) {
  s = current_session()
  if (is.null(s)) gptr_abort("gptr_return() can only be called while a gptr request is running", "no_session")
  s$value = value
  invisible(value)
}

#' @export
print.gptr_session = function(x, ...) {
  cat(x$text, "\n", sep = "")
  cat(sprintf("<gptr_session %s> %s, %d turns, %g in / %g out tokens%s\n", x$id, x$status, x$usage$turns,
              x$usage$input, x$usage$output, if (!is.null(x$value)) paste0(", value: <", class(x$value)[1], ">") else ""))
  invisible(x)
}
```

`$G1/pkg/gptr/R/gateway.R`

```r
# The single gateway (S-1) plus configuration.

#' The gptr gateway
#'
#' `gptr("prompt")` runs the agent and returns the session object (reference
#' semantics). `s |> gptr("more")` steers or continues the same session.
#' `gptr("prompt", .run = FALSE)` returns a session with the prompt queued, for
#' stepwise drivers ([gptr_step()]).
#' @param ... A prompt string, optionally a session to continue, and context objects.
#' @param model Model spec, model name or router name.
#' @param tools Character vector of active tool names, or a list of tool specs
#'   (call-level precedence).
#' @param plugins Plugin packages or directories to enable.
#' @param agents Named list of [gptr_agent()] definitions to run on the prompt.
#' @param mode Permission mode.
#' @param budget List with optional `tokens` and `turns` limits.
#' @param envir Evaluation environment (default: the caller's frame).
#' @param .run Run to settlement now (`TRUE`) or only queue the prompt.
#' @return A `gptr_session` (or a `gptr_results` list when `agents` is used).
#' @export
gptr = function(..., model = NULL, tools = NULL, plugins = NULL, agents = NULL, mode = NULL,
                budget = NULL, envir = parent.frame(), .run = TRUE) {
  dots = list(...)
  nms = names(dots) %||% rep("", length(dots))
  sess = NULL; prompt = NULL; context = list()
  for (i in seq_along(dots)) {
    d = dots[[i]]
    if (is.null(sess) && inherits(d, "gptr_session")) sess = d
    else if (is.null(prompt) && !nzchar(nms[i]) && is_string(d)) prompt = d
    else context[[length(context) + 1L]] = d
  }
  for (p in plugins) gptr_register(p)
  if (!is.null(agents)) return(run_agents(prompt, agents, model, envir))
  if (is.null(sess) && is.null(prompt))
    gptr_abort("gptr() without a prompt starts the console, which this prototype does not implement", "noninteractive")
  if (is.null(sess)) {
    sess = session_new(model, tools, mode, envir, budget, parent = current_session())
  } else if (!is.null(model)) {
    sess$model = model
  }
  if (length(context)) sess$context = c(sess$context, context)
  if (!is.null(prompt)) {
    if (identical(sess$status, "running")) { gptr_steer(sess, prompt); return(invisible(sess)) }
    sess$pending[[length(sess$pending) + 1L]] = list(role = "user", content = prompt)
  }
  if (.run) {
    gptr_wait(sess)
    if (!is.null(sess$parent)) sess$parent$usage$children = sess$parent$usage$children + sess$usage$input + sess$usage$output
  }
  sess
}

run_agents = function(prompt, agents, model, envir) {
  out = list()
  for (nm in names(agents)) {
    def = agents[[nm]]
    if (is_string(def)) def = cap_get(the$registry, "agent", def)
    be = cap_get(the$registry, "backend", def$backend %||% "inline")
    if (is.null(be)) gptr_abort(paste0("no sub-agent backend '", def$backend, "'"), "no_backend")
    out[[nm]] = be$start(list(agent = def, prompt = prompt, model = def$model %||% model, envir = envir), NULL)
  }
  structure(out, class = "gptr_results")
}

#' @export
print.gptr_results = function(x, ...) {
  for (nm in names(x)) cat(sprintf("%-10s %-6s %s\n", nm, x[[nm]]$status, substr(x[[nm]]$text, 1, 60)))
  invisible(x)
}

#' Get or set configuration
#'
#' @param ... `key = value` pairs to set; no arguments returns the effective configuration.
#' @return The configuration list (invisibly when setting).
#' @export
gptr_config = function(...) {
  args = list(...)
  if (!length(args)) {
    keys = names(resolve(the$registry, "setting"))
    return(stats::setNames(lapply(keys, config_get), keys))
  }
  cfg = the$config %||% list()
  cfg[names(args)] = args
  the$config = cfg
  invisible(cfg)
}

config_get = function(key) {
  v = (the$config %||% list())[[key]]
  if (!is.null(v)) return(v)
  s = cap_get(the$registry, "setting", key)
  if (is.null(s)) NULL else s$default
}

#' A scripted provider for tests and examples
#'
#' @param script List of responses, each `list(text = , tool_calls = list(list(name =, arguments =)))`.
#' @return A model spec for `gptr(model = )`.
#' @export
gptr_fake_provider = function(script) {
  cur = new.env(parent = emptyenv()); cur$i = 0L
  gptr_model("fake", "fake", api = "fake", script = script, cursor = cur)
}
```

`$G1/pkg/gptr/R/tools-dispatch.R`

```r
# Tool exposure to the model, and the tools-as-R-functions dispatcher.

# Provider-neutral declarations of the tools the model sees natively ("direct").
declarations = function(tools) {
  out = list()
  for (r in tools) {
    t = r$spec
    if (!identical(t$exposure, "direct")) next
    out[[length(out) + 1L]] = list(name = t$name, description = t$description, input_schema = t$parameters)
  }
  out
}

first_sentence = function(x) sub("([.!?])\\s.*$", "\\1", x %||% "")

sig_type = function(p) {
  t = p$type %||% "any"
  if (identical(t, "array")) paste0("vector<", p$items$type %||% "any", ">") else t
}

# One compact line per "r"-exposed tool: callable from R code, cheap in tokens.
r_signature = function(t, prefix = "gptr_tools$") {
  props = t$parameters$properties %||% list()
  req = unlist(t$parameters$required %||% list())
  args = vapply(names(props), function(n) if (n %in% req) paste0(n, ": ", sig_type(props[[n]]))
                else paste0(n, "?: ", sig_type(props[[n]])), "")
  ns = if (!is.null(t$namespace)) paste0(t$namespace, "$") else ""
  paste0(prefix, ns, t$name, "(", paste(args, collapse = ", "), ")  # ", first_sentence(t$description))
}

r_signatures = function(tools) {
  out = character()
  deferred = 0L
  for (r in tools) {
    t = r$spec
    if (identical(t$exposure, "r")) out = c(out, r_signature(t))
    if (identical(t$exposure, "deferred")) deferred = deferred + 1L
  }
  if (deferred) out = c(out, sprintf("# %d more tools: gptr_tools$.search(\"query\")", deferred))
  out
}

current_session = function() if (length(the$stack)) the$stack[[1]] else NULL

make_tool_fn = function(t) {
  tool = t
  tool_name = t$name
  props = t$parameters$properties %||% list()
  req = unlist(t$parameters$required %||% list())
  nms = c(intersect(names(props), req), setdiff(names(props), req))
  fmls = c(stats::setNames(rep(list(quote(expr = )), length(intersect(nms, req))), intersect(nms, req)),
           stats::setNames(rep(list(NULL), length(setdiff(nms, req))), setdiff(nms, req)),
           alist(... = ))
  f = function() {
    mc = as.list(match.call())[-1L]
    args = lapply(mc, eval, envir = parent.frame())
    miss = setdiff(req, names(args))
    if (length(miss)) gptr_abort(paste0(tool_name, "(): missing required argument ", paste(miss, collapse = ", ")), "tool_args")
    s = current_session()
    res = if (!is.null(s)) run_tool_call(s, list(id = new_id("n"), name = tool_name, arguments = args), session_ctx(s), nested = TRUE)
          else tool$execute(args, NULL)
    if (is.character(res)) return(res)
    if (isTRUE(res$is_error)) gptr_abort(result_text(res), "tool")
    res$details$value %||% result_text(res)
  }
  formals(f) = fmls                  # keeps the closure over this frame (tool, tool_name, req)
  structure(f, class = c("gptr_tool_fn", "function"), tool = t$name)
}

#' Tools as R functions
#'
#' `gptr_tools$<name>(...)` calls any registered tool (built-in, plugin or MCP)
#' from R code, through the same permission gate as model-issued calls when a
#' session is running. `gptr_tools$.search("query")` searches deferred tools.
#' @format An object of class `gptr_tools`.
#' @export
gptr_tools = structure(list(), class = "gptr_tools")

#' @export
`$.gptr_tools` = function(x, name) {
  s = current_session()
  all = resolve(the$registry, "tool", s$view)
  if (identical(name, ".search")) return(function(query) {
    hit = Filter(function(r) grepl(query, paste(r$name, r$spec$description), ignore.case = TRUE), all)
    vapply(hit, function(r) r_signature(r$spec), "")
  })
  if (identical(name, ".list")) return(function() names(all))
  r = all[[name]]
  if (!is.null(r)) return(make_tool_fn(r$spec))
  ns = Filter(function(r) identical(r$spec$namespace, name), all)
  if (length(ns)) return(structure(lapply(ns, function(r) make_tool_fn(r$spec)), names = vapply(ns, function(r) r$spec$name, "")))
  gptr_abort(paste0("no tool '", name, "'"), "tool_not_found")
}

#' @export
`[[.gptr_tools` = function(x, i) `$.gptr_tools`(x, i)

#' @export
names.gptr_tools = function(x) names(resolve(the$registry, "tool", current_session()$view))

#' @export
print.gptr_tools = function(x, ...) {
  cat("<gptr_tools> ", length(names(x)), " tools: ", paste(names(x), collapse = ", "), "\n", sep = "")
  invisible(x)
}

#' @export
print.gptr_tool_fn = function(x, ...) {
  t = cap_get(the$registry, "tool", attr(x, "tool"))
  cat(r_signature(t), "\n")
  invisible(x)
}
```

`$G1/pkg/gptr/R/builtins.R`

```r
# Built-in features, registered through exactly the same API that third-party
# plugins use (S-11). Each is an ordinary factory; disable with "-builtin:<name>".

builtin_core = function(gptr) {
  for (k in setdiff(names(CORE_CTORS), "kind"))
    gptr$register(gptr_kind(k, resolve = if (k %in% ALL_KINDS) "all" else "first"))
  gptr$register_setting("model", NULL, "Default model")
  gptr$register_setting("mode", "manual", "Permission mode: plan, manual, edits, auto")
  gptr$register_setting("ui", "none", "UI backend name")
  gptr$register_setting("compactor", "truncate", "Compaction strategy")
  gptr$register_setting("compaction_max", 40L, "Messages before compaction")
  gptr$register_setting("doc_format", "R", "History document format")
  gptr$register_prompt_section("preamble", "You are gptr, an agent inside the user's live R session.", 10)
}

builtin_tools = function(gptr) {
  gptr$register_tool("read", "Read a text file.",
    list(type = "object", properties = list(path = list(type = "string")), required = list("path")),
    function(input, ctx) {
      l = readLines(input$path, warn = FALSE)
      gptr_tool_result(l, details = list(value = l))
    }, annotations = list(read_only = TRUE))
  gptr$register_tool("ls", "List files in a directory.",
    list(type = "object", properties = list(path = list(type = "string"))),
    function(input, ctx) {
      f = sort(list.files(input$path %||% ".", all.files = FALSE), method = "radix")
      gptr_tool_result(f, details = list(value = f))
    }, annotations = list(read_only = TRUE))
  gptr$register_tool("run_r", "Evaluate R code in the live session.",
    list(type = "object", properties = list(code = list(type = "string")), required = list("code")),
    function(input, ctx) {
      env = if (is.null(ctx)) parent.frame(3) else ctx$envir
      val = NULL
      out = utils::capture.output({ val = withVisible(eval(parse(text = input$code), env)) })
      if (isTRUE(val$visible)) out = c(out, utils::capture.output(print(val$value)))
      gptr_tool_result(out, details = list(code = input$code))
    }, annotations = list(read_only = FALSE))
  gptr$register_tool("grep", "Search file contents with a regular expression. Returns a data frame.",
    list(type = "object", properties = list(pattern = list(type = "string"), path = list(type = "string")),
         required = list("pattern")),
    function(input, ctx) {
      files = list.files(input$path %||% ".", recursive = TRUE, full.names = TRUE)
      hits = do.call(rbind, lapply(files, function(f) {
        l = readLines(f, warn = FALSE); i = grep(input$pattern, l)
        if (length(i)) data.frame(file = f, line = i, text = l[i]) else NULL
      }))
      gptr_tool_result(if (is.null(hits)) "no matches" else paste(hits$file, hits$line, hits$text, sep = ":"),
                       details = list(value = hits))
    }, annotations = list(read_only = TRUE), exposure = "r")
}

builtin_providers = function(gptr) {
  gptr$register_adapter("fake", function(model, context, options, on_event) {
    cur = model$cursor; cur$i = cur$i + 1L
    r = model$script[[min(cur$i, length(model$script))]]
    if (is.function(r)) r = r(context)
    list(role = "assistant", content = r$text %||% "", tool_calls = lapply(r$tool_calls %||% list(), function(tc)
           list(id = new_id("call"), name = tc$name, arguments = tc$arguments)),
         stop_reason = if (length(r$tool_calls)) "tool_use" else "stop",
         usage = list(input = estimate_tokens(c(context$system, unlist(lapply(context$messages, `[[`, "content")))),
                      output = estimate_tokens(r$text %||% "")))
  }, transport = "inprocess")
  gptr$register_provider("fake", api = "fake")
}

builtin_permissions = function(gptr) {
  gptr$register_policy("modes", function(call, ctx) {
    ro = isTRUE(call$annotations$read_only)
    switch(ctx$mode(),
      auto = NULL,
      plan = if (ro) NULL else list(decision = "deny", reason = "plan mode is read-only"),
      edits = if (ro || call$tool %in% c("write", "edit")) NULL else list(decision = "ask", reason = "edits mode"),
      manual = if (ro) NULL else list(decision = "ask", reason = "manual mode"),
      list(decision = "deny", reason = paste0("unknown mode ", ctx$mode())))
  }, "Permission modes plan/manual/edits/auto")
}

builtin_context = function(gptr) {
  gptr$register_context_block("session_context", function(ctx, budget) {
    nm = sort(ls(ctx$envir), method = "radix")
    vapply(nm, function(n) gptr_describe(get(n, envir = ctx$envir), budget = 20L)[1], "")
  }, "turn", 300L)
}

builtin_compaction = function(gptr) {
  gptr$register_compactor("truncate",
    should = function(s, ctx) length(s$messages) > config_get("compaction_max"),
    compact = function(s, ctx) list(summary = paste0("[", length(s$messages) - 10L, " earlier messages compacted]"), keep = 10L))
}

builtin_document = function(gptr) {
  gptr$register_doc_format("R", "R", function(block) c(paste0("# >>> gptr:", block$id), block$code,
                                                       paste0("#> ", utils::head(block$output, 3)), paste0("# <<< gptr:", block$id)))
  gptr$on("tool_result", function(event, ctx) {
    s = ctx$session
    fmt = ctx$get("doc_format", config_get("doc_format"))
    lines = fmt$render(list(id = s$id, code = event$input$code,
                            output = strsplit(event$content[[1]]$text %||% "", "\n")[[1]]))
    gate = emit(s, "document_write", list(text = lines), ctx)
    if (!isTRUE(gate$block)) s$doc = c(s$doc, gate$text %||% lines)
    NULL
  }, matcher = "^run_r$")
}

builtin_agents = function(gptr) {
  gptr$register_backend("inline", function(spec, ctx) {
    parent = current_session()
    child = session_new(spec$model, spec$agent$tools, "auto", new.env(parent = spec$envir), NULL, parent)
    if (!is.null(spec$agent$system)) view_add(child, gptr_prompt_section("agent", spec$agent$system, 15))
    child$pending = list(list(role = "user", content = spec$prompt))
    if (!is.null(parent)) emit(parent, "subagent_start", list(agent = spec$agent$name))
    gptr_wait(child)
    if (!is.null(parent)) emit(parent, "subagent_end", list(agent = spec$agent$name, usage = child$usage))
    child
  }, capabilities = c("sees_objects"))
}

builtin_ui = function(gptr) {
  gptr$register_ui("none", select = function(title, choices, ...) NA_integer_, has_ui = FALSE)
  gptr$register_frontend("console", function(session, ...) gptr_abort("console front end not in prototype", "noninteractive"))
}

BUILTINS = list(core = builtin_core, tools = builtin_tools, providers = builtin_providers,
                permissions = builtin_permissions, context = builtin_context, compaction = builtin_compaction,
                document = builtin_document, agents = builtin_agents, ui = builtin_ui)

register_builtins = function(reg) {
  reg$kinds$kind = gptr_kind("kind")
  for (nm in names(BUILTINS))
    ext_load(reg, BUILTINS[[nm]], paste0("builtin:", nm), "builtin", replaceable = nm %in% c("compaction", "document"))
  invisible(reg)
}

.onLoad = function(libname, pkgname) {
  the$registry = registry_new()
  register_builtins(the$registry)
  invisible()
}

#' Describe an object compactly for the model
#'
#' S3 generic; packages add methods (for example `gptr_describe.Seurat`) through
#' `S3method(gptr::gptr_describe, <class>)`, which registers lazily when gptr is
#' only in Suggests.
#' @param x Object.
#' @param budget Token budget.
#' @param ... Unused.
#' @return Character lines; the first is a header.
#' @export
gptr_describe = function(x, budget = 300L, ...) UseMethod("gptr_describe")

#' @export
gptr_describe.default = function(x, budget = 300L, ...) {
  d = dim(x)
  paste0("<", class(x)[1], "> ", if (is.null(d)) paste0("length ", length(x)) else paste(d, collapse = " x "))
}
```

`$G1/pkg/gptr/R/check.R`

```r
# Exported conformance helpers: plugin authors call these from their own
# testthat suites (no testthat dependency here).

check_row = function(check, ok, detail = "") data.frame(check = check, ok = isTRUE(ok), detail = detail)

with_scratch_registry = function(code) {
  old = the$registry
  on.exit({ the$registry = old }, add = TRUE)
  the$registry = registry_new()
  register_builtins(the$registry)
  force(code)
}

finish_check = function(rows, error) {
  out = do.call(rbind, rows)
  class(out) = c("gptr_check", "data.frame")
  if (error && !all(out$ok))
    gptr_abort(paste0("conformance failed: ", paste(out$check[!out$ok], collapse = "; ")), "conformance", checks = out)
  out
}

#' Conformance checks for plugin authors
#'
#' Checks a capability spec, a plugin factory, or an installed plugin package
#' against the contract of the extension API, in a scratch registry.
#' @param x A spec, a factory `function(gptr)`, or a package name.
#' @param error Raise `gptr_error_conformance` when any check fails.
#' @param ... Unused.
#' @return A data frame of class `gptr_check` with columns `check`, `ok`, `detail`.
#' @export
gptr_check = function(x, ..., error = FALSE) UseMethod("gptr_check")

#' @export
gptr_check.gptr_tool = function(x, ..., error = FALSE) {
  decl = jsonlite::toJSON(list(name = x$name, description = x$description, input_schema = x$parameters), auto_unbox = TRUE)
  toks = estimate_tokens(decl)
  bad = tryCatch(x$execute(list(), NULL), error = function(e) gptr_tool_result(conditionMessage(e), is_error = TRUE))
  rows = list(
    check_row("name is a provider-safe identifier", grepl("^[A-Za-z][A-Za-z0-9_]{0,63}$", x$name, perl = TRUE)),
    check_row("description present, <= 1024 chars", nzchar(x$description) && nchar(x$description) <= 1024),
    check_row("parameters is a JSON-Schema object", identical(x$parameters$type, "object")),
    check_row("declaration cost <= 400 tokens (direct)", x$exposure != "direct" || toks <= 400, paste0(toks, " tokens")),
    check_row("annotations declared", length(x$annotations) > 0L),
    check_row("empty input yields a result or a classed error", inherits(bad, "gptr_tool_result") || is.character(bad)))
  finish_check(rows, error)
}

#' @export
gptr_check.gptr_policy = function(x, ..., error = FALSE) {
  rows = list()
  for (mode in c("plan", "manual", "edits", "auto")) for (ro in c(TRUE, FALSE)) {
    ctx = list(mode = function() mode)
    v = tryCatch(x$check(list(tool = "t", annotations = list(read_only = ro), input = list()), ctx), error = function(e) e)
    ok = !inherits(v, "error") && (is.null(v) || v$decision %in% c("allow", "deny", "ask", "modify"))
    rows[[length(rows) + 1L]] = check_row(sprintf("verdict valid (mode=%s, read_only=%s)", mode, ro), ok)
  }
  finish_check(rows, error)
}

#' @export
gptr_check.gptr_adapter = function(x, ..., error = FALSE) {
  cur = new.env(); cur$i = 0L
  m = gptr_model("probe", "probe", api = x$name, script = list(list(text = "ok")), cursor = cur)
  out = tryCatch(x$stream(m, list(system = "", messages = list(list(role = "user", content = "hi")), tools = list()),
                          list(), function(ev) stop("listener failure")), error = function(e) e)
  rows = list(
    check_row("stream never throws", !inherits(out, "error"), if (inherits(out, "error")) conditionMessage(out) else ""),
    check_row("returns an assistant message", is.list(out) && identical(out$role, "assistant")),
    check_row("stop_reason in contract", is.list(out) && out$stop_reason %in% c("stop", "length", "tool_use", "error", "aborted")),
    check_row("reports usage", is.list(out) && is.list(out$usage)))
  finish_check(rows, error)
}

#' @export
gptr_check.function = function(x, ..., error = FALSE) {
  with_scratch_registry({
    reg = the$registry
    ok = ext_load(reg, x, "probe", "user")
    info = reg$exts$probe
    recs = Filter(function(r) identical(r$ext, "probe"), reg$recs)
    rows = list(check_row("factory loads in a scratch registry", ok, info$error %||% ""),
                check_row("registers at least one capability", length(recs) > 0L, paste(length(recs), "records")))
    for (r in recs) if (inherits(r$spec, c("gptr_tool", "gptr_policy", "gptr_adapter"))) {
      sub = gptr_check(r$spec)
      sub$check = paste0(r$kind, ":", r$name, ": ", sub$check)
      rows[[length(rows) + 1L]] = sub
    }
    finish_check(rows, error)
  })
}

#' @export
gptr_check.character = function(x, ..., error = FALSE) {
  with_scratch_registry({
    reg = the$registry
    root = system.file("gptr", package = x)
    man = if (nzchar(root)) read_manifest(root) else list()
    req = man$gptr$api
    rows = list(check_row("package ships inst/gptr", nzchar(root)),
                check_row("declares an API requirement", !is.null(req), req %||% ""),
                check_row("API requirement satisfied", is.null(req) || api_satisfies(req)))
    if (nzchar(root)) {
      ok = tryCatch(plugin_load_package(reg, x, lazy = FALSE), error = function(e) FALSE)
      rows[[length(rows) + 1L]] = check_row("plugin loads eagerly without error", isTRUE(ok) && !length(Filter(function(d) d$type == "load_error", reg$diag)))
      prov = man$extension$provides %||% list()
      for (k in names(prov)) for (nm in unlist(prov[[k]])) {
        got = Filter(function(r) identical(r$kind, k) && !r$lazy && !r$dead &&
                       (identical(r$name, nm) || identical(r$spec$event, nm)), reg$recs)
        rows[[length(rows) + 1L]] = check_row(paste0("manifest provides ", k, ":", nm, " and the factory registers it"), length(got) > 0L)
      }
      for (r in Filter(function(r) identical(r$kind, "skill"), reg$recs))
        rows[[length(rows) + 1L]] = check_row(paste0("skill ", r$name, " has a description"), nzchar(r$spec$description))
    }
    finish_check(rows, error)
  })
}
```

### 5.2 End-to-end checks of the registry and SDK (59/59)

Built-ins, precedence, filters, replaceable built-ins, transactional rollback, API version and
missing-method errors, stale API objects, fail-closed permissions, patching hooks, S-8 pipe
semantics and stepwise driving, routers, sub-agent backends, the dispatcher, a plugin-defined
kind, the event bus, budgets, compaction, conformance helpers, event-name aliases.

`$G1/proto/test_registry.R`

```r
# G1 end-to-end checks of the prototype registry + SDK (installed package, no ':::').
# Run: R_LIBS=<G1>/lib Rscript --vanilla test_registry.R
library(gptr)
n_pass = 0L; n_fail = 0L
ok = function(label, cond) {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("PASS ", label, "\n", sep = "") }
  else { n_fail <<- n_fail + 1L; cat("FAIL ", label, "\n", sep = "") }
}
err_class = function(expr) tryCatch({ force(expr); "none" }, error = function(e) class(e)[1])
fake = function(...) gptr_fake_provider(list(...))
call_r = function(code) list(text = "", tool_calls = list(list(name = "run_r", arguments = list(code = code))))

# ---- 1. built-ins are ordinary registrations ------------------------------------------------
reg = gptr_registry()
kinds_present = unique(reg$kind)
ok("built-ins register through the API (9 builtin extensions)", length(unique(reg$ext[startsWith(reg$ext, "builtin:")])) == 9L)
ok("categories present: tool/adapter/provider/hook/policy/context/compactor/doc_format/backend/ui/frontend/setting/section",
   all(c("tool", "adapter", "provider", "hook", "policy", "context", "compactor", "doc_format", "backend",
         "ui", "frontend", "setting", "section") %in% kinds_present))
ok("21 core kinds are themselves registered specs (plus the bootstrap meta-kind)", sum(reg$kind == "kind") == 21L)

# ---- 2. a run with the fake provider through every built-in category --------------------------
env = new.env(); env$mice = data.frame(w = 1:3)
gptr_config(mode = "auto")
seen_ctx = new.env()
s = gptr("fit it", model = fake(call_r("fit = lm(w ~ 1, mice); coef(fit)"),
                                function(context) { seen_ctx$c = context; list(text = "done") }), envir = env)
ok("session settles", identical(s$status, "done") && identical(s$text, "done"))
ok("run_r evaluated in the caller env (object persists)", exists("fit", envir = env, inherits = FALSE))
ok("history writer (doc_format R via hook) recorded the code block", any(grepl("fit = lm", s$doc)) && any(startsWith(s$doc, "# >>> gptr:")))
ctx_txt = paste(vapply(seen_ctx$c$messages, function(m) paste(m$content, collapse = " "), ""), collapse = "\n")
ok("context block session_context reached the model (it lists 'mice' and 'fit')",
   grepl("<session_context>", ctx_txt) && grepl("data.frame", ctx_txt) && grepl("lm", ctx_txt))
ok("event trace in Pi order", identical(s$trace[1:4], c("input", "before_agent_start", "agent_start", "turn_start")))

# ---- 3. precedence: call > user > builtin ---------------------------------------------------------
gptr_register(gptr_tool("read", "User read.", list(type = "object", properties = list()),
                        function(input, ctx) "user-read", annotations = list(read_only = TRUE)))
r = gptr_registry("tool")
ok("user tool overrides builtin of the same name", r$status[r$name == "read" & r$ext == "user:inline"] == "active" &&
   r$status[r$name == "read" & r$ext == "builtin:tools"] == "shadowed")
ok("dispatcher resolves the winner", identical(gptr_tools$read(), "user-read"))
s2 = gptr("x", model = fake(list(text = "", tool_calls = list(list(name = "read", arguments = list()))), list(text = "ok")),
          tools = list(gptr_tool("read", "Call read.", list(type = "object", properties = list()),
                                 function(input, ctx) "call-read", annotations = list(read_only = TRUE))))
ok("call-level spec (rank 0) beats user and builtin", grepl("call-read", s2$messages[[3]]$content))

# ---- 4. filters (-builtin:x, -kind:name, +) ---------------------------------------------------------
gptr_filter("-tool:grep")
ok("-tool:grep hides grep", !("grep" %in% names(gptr_tools)))
gptr_filter("+tool:grep")
ok("+tool:grep restores it", "grep" %in% names(gptr_tools))
gptr_filter("-builtin:permissions"); gptr_config(mode = "plan")
s3 = gptr("x", model = fake(call_r("1 + 1"), list(text = "ok")))
ok("-builtin:permissions removes the mode policy (plan no longer blocks)", !isTRUE(s3$messages[[3]]$is_error))
gptr_filter("+builtin:permissions")
s4 = gptr("x", model = fake(call_r("1 + 1"), list(text = "ok")))
ok("policy back: plan mode denies mutating R code", isTRUE(s4$messages[[3]]$is_error) && grepl("plan mode", s4$messages[[3]]$content))

# ---- 5. replaceable built-in extension --------------------------------------------------------------
gptr_config(mode = "auto")
gptr_register(gptr_doc_format("R", "R", function(block) paste("MYFMT", block$code)), name = "user:mydoc")
s5 = gptr("x", model = fake(call_r("2 + 2"), list(text = "ok")))
ok("overriding doc_format R replaces the whole builtin:document extension (its writer hook too)", length(s5$doc) == 0L)
gptr_filter("-user:mydoc")
s5b = gptr("x", model = fake(call_r("2 + 2"), list(text = "ok")))
ok("disabling the override brings builtin:document back", any(grepl("2 \\+ 2", s5b$doc)))

# ---- 6. transactional load with rollback ---------------------------------------------------------------
bad = function(gptr) {
  gptr$register_tool("half", "Registered before failing.", list(type = "object", properties = list()),
                     function(input, ctx) "x", annotations = list(read_only = TRUE))
  stop("boom in factory")
}
gptr_register(bad, name = "bad-ext")
ok("failing factory: nothing it staged reaches the registry", !("half" %in% names(gptr_tools)))
d = gptr_registry(diagnostics = TRUE)
ok("failure recorded as a diagnostic", any(d$who == "bad-ext" & grepl("boom", d$message)))

# ---- 7. API version checks -----------------------------------------------------------------------------
f2 = structure(function(gptr) gptr$register_command("x2", function(args, ctx) NULL), gptr_api = ">= 2.0")
gptr_register(f2, name = "needs-2")
d = gptr_registry(diagnostics = TRUE)
ok("factory requiring API >= 2.0 is refused with a clear message",
   any(d$who == "needs-2" & grepl("requires gptr extension API >= 2.0", d$message)))
f3 = function(gptr) { gptr$register_command("x3", function(args, ctx) NULL); gptr$require("1.9") }
gptr_register(f3, name = "needs-1.9")
ok("gptr$require() inside the factory rolls back its registrations", !("x3" %in% gptr_registry("command")$name))
gptr_register(function(gptr) gptr$register_widget("w"), name = "future-api")
d = gptr_registry(diagnostics = TRUE)
ok("calling a method this API version lacks gives a clear message (gptr_error_api_missing)",
   any(d$who == "future-api" & grepl("has no method 'register_widget'", d$message)))
cls = tryCatch(gptr_register(structure(function(gptr) NULL, gptr_api = "1.0"), name = "fine"), error = function(e) "err")
ok("bare '1.0' means >= 1.0, < 2 (caret)", isTRUE(cls))
ok("feature negotiation lists kinds and events", all(c("kind.tool", "kind.router", "event.tool_call") %in% gptr_api_features()))

# ---- 8. stale API objects after reload -----------------------------------------------------------------
keep = new.env()
gptr_register(function(gptr) { keep$api = gptr; gptr$register_command("hello", function(args, ctx) "hi") }, name = "keeper")
gptr_reload()
ok("reload drops non-enabled inline extensions", !("hello" %in% gptr_registry("command")$name))
ok("captured API object raises gptr_error_stale_api", err_class(keep$api$register_command("again", function(args, ctx) NULL)) == "gptr_error_stale_api")
gptr_config(mode = "auto")

# ---- 9-10. permissions fail closed ----------------------------------------------------------------------
gptr_config(mode = "manual")
s9 = gptr("x", model = fake(call_r("3"), list(text = "ok")))
ok("manual mode without UI: ask becomes a denial (fail closed)", grepl("no UI", s9$messages[[3]]$content))
gptr_register(gptr_ui("scripted", select = function(title, choices, ...) 1L, has_ui = TRUE))
gptr_config(ui = "scripted")
s9b = gptr("x", model = fake(call_r("3"), list(text = "ok")))
ok("a registered UI backend answers the ask (Yes)", !isTRUE(s9b$messages[[3]]$is_error))
gptr_config(ui = "none", mode = "auto")
gptr_register(gptr_policy("buggy", function(call, ctx) stop("policy bug")), name = "user:buggy")
s10 = gptr("x", model = fake(call_r("4"), list(text = "ok")))
ok("a throwing policy denies (fail closed)", grepl("policy 'buggy' failed", s10$messages[[3]]$content))
gptr_filter("-user:buggy")
gptr_register(function(gptr) gptr$on("tool_call", function(event, ctx) stop("hook bug")), name = "user:badhook")
s10b = gptr("x", model = fake(call_r("5"), list(text = "ok")))
ok("a throwing tool_call hook blocks the tool", grepl("hook 'user:badhook' failed", s10b$messages[[3]]$content))
gptr_filter("-user:badhook")

# ---- 11-12. patching hooks, session subscriptions, fork isolation ----------------------------------------
s11 = gptr("x", model = fake(call_r("'secret-123'"), list(text = "ok")), .run = FALSE)
seen = 0L
unsub = gptr_on(s11, "tool_execution_start", function(event, ctx) seen <<- seen + 1L)
gptr_on(s11, "tool_result", function(event, ctx) list(content = list(list(type = "text", text = gsub("secret-[0-9]+", "[redacted]", event$content[[1]]$text)))))
gptr_wait(s11)
ok("session hook patched the tool result before the model saw it", grepl("\\[redacted\\]", s11$messages[[3]]$content))
ok("session subscription fired", seen == 1L)
f11 = gptr_fork(s11)
invisible(f11 |> gptr("again", model = fake(call_r("'secret-9'"), list(text = "ok"))))
ok("fork does not share listeners (INFRA-14)", seen == 1L && !grepl("redacted", f11$messages[[length(f11$messages) - 1L]]$content))
unsub()

# ---- 13. S-8: the pipe steers ONE session; stepwise driving ------------------------------------------------
m13 = fake(call_r("x13 = 1"), list(text = "first"), list(text = "second"))
s13 = gptr("start", model = m13, .run = FALSE)
ok(".run = FALSE queues without running", identical(s13$status, "idle") && length(s13$pending) == 1L)
gptr_step(s13)
ok("gptr_step ran exactly one model turn (tool turn)", identical(s13$status, "running") && s13$usage$turns == 1L)
same = s13 |> gptr("use TPM")
ok("piping into a RUNNING session queues a steering message and returns the same object", identical(same, s13) && length(s13$steer) == 1L)
gptr_wait(s13)
roles = vapply(s13$messages, `[[`, "", "role")
ok("steering delivered after the tool result (INFRA-12 ordering)", identical(roles[1:4], c("user", "assistant", "tool_result", "user")))
invisible(s13 |> gptr("follow up"))
ok("piping into an idle session appends a follow-up turn to the same session", identical(s13$status, "done") && s13$usage$turns == 3L)

# ---- 14. router (virtual model) ----------------------------------------------------------------------------
cheap = fake(list(text = "cheap answer")); strong = fake(list(text = "strong answer"))
gptr_register(gptr_router("auto_route", function(request, ctx) {
  p = request$messages[[1]]$content
  if (nchar(p) > 20) strong else cheap
}))
routed = character()
s14 = gptr("short q", model = "auto_route", .run = FALSE); gptr_on(s14, "route", function(event, ctx) routed <<- c(routed, event$router)); gptr_wait(s14)
s14b = gptr("a much longer and harder question", model = "auto_route")
ok("router picks a model per request", identical(s14$text, "cheap answer") && identical(s14b$text, "strong answer"))
ok("route event emitted", identical(routed, "auto_route"))

# ---- 15. sub-agent backends --------------------------------------------------------------------------------
res = gptr("review", agents = list(a = gptr_agent("a", model = fake(list(text = "A says ok"))),
                                   b = gptr_agent("b", model = fake(list(text = "B says fix")))))
ok("inline backend runs agents and returns named results", identical(res$a$text, "A says ok") && identical(res$b$text, "B says fix"))
gptr_register(gptr_backend("recorder", function(spec, ctx) {
  s = gptr(spec$prompt, model = spec$model, .run = FALSE); s$text = paste("recorded:", spec$prompt); s$status = "done"; s }))
res2 = gptr("audit", agents = list(r = gptr_agent("r", model = cheap, backend = "recorder")))
ok("third-party backend selected by the agent definition", identical(res2$r$text, "recorded: audit"))

# ---- 16. tools as R functions (dispatcher) ---------------------------------------------------------------------
td = tempfile(); dir.create(td); writeLines(c("alpha", "beta"), file.path(td, "a.txt"))
hits = gptr_tools$grep("beta", td)
ok("gptr_tools$grep returns R data (data frame), not tool text", is.data.frame(hits) && hits$line == 2L)
ok("gptr_tools$.search finds r-exposed tools", any(grepl("grep", gptr_tools$.search("search"))))
gptr_config(mode = "plan")
s16 = gptr("x", model = fake(call_r(sprintf("h = gptr_tools$grep('alpha', '%s'); nrow(h)", td)), list(text = "ok")))
ok("model-written R code calls a tool through the gate (plan: run_r itself denied)", isTRUE(s16$messages[[3]]$is_error))
gptr_config(mode = "auto")
s16b = gptr("x", model = fake(call_r(sprintf("h = gptr_tools$grep('alpha', '%s'); nrow(h)", td)), list(text = "ok")))
ok("nested dispatcher call emits tool events (grep inside run_r)", sum(s16b$trace == "tool_execution_start") == 2L)
sys_seen = new.env()
invisible(gptr("x", model = fake(function(context) { sys_seen$s = context$system; sys_seen$d = context$tools; list(text = "ok") })))
ok("system prompt lists r-exposed tools as one-line signatures", grepl("gptr_tools\\$grep\\(pattern: string", sys_seen$s))
ok("direct tools are declared natively; r-exposed grep is not", "run_r" %in% vapply(sys_seen$d, `[[`, "", "name") &&
   !("grep" %in% vapply(sys_seen$d, `[[`, "", "name")))

# ---- 17. plugin-defined capability kind (meta-extensibility) -------------------------------------------------------
gptr_register(function(gptr) {
  gptr$register(gptr_kind("reviewer", resolve = "all"))
  gptr$register(gptr_spec("reviewer", "stats", model = "opus", focus = "statistics"))
  gptr$register(gptr_spec("reviewer", "style", model = "haiku", focus = "code style"))
}, name = "panel-kinds")
ok("a plugin adds a new capability kind and registers into it in the same factory",
   all(c("stats", "style") %in% gptr_registry("reviewer")$name))

# ---- 17b. inter-plugin event bus and plugin-declared settings --------------------------------------------------------
got = NULL
gptr_register(function(gptr) gptr$events$on("panel:verdict", function(data) got <<- data), name = "listener-ext")
gptr_register(function(gptr) {
  gptr$register_setting("panel.size", 3L, "Reviewers per panel")
  gptr$on("agent_end", function(event, ctx) gptr$events$emit("panel:verdict", ctx$session$text))
}, name = "emitter-ext")
invisible(gptr("judge this", model = fake(list(text = "accept"))))
ok("inter-plugin event bus: one extension's emit reaches another's listener", identical(got, "accept"))
ok("plugin-declared setting has a default readable with gptr_config()", identical(gptr_config()[["panel.size"]], 3L))
gptr_filter("-emitter-ext", "-listener-ext")

# ---- 18. budgets and compaction -------------------------------------------------------------------------------------
loop = fake(call_r("1"))
s18 = gptr("loop", model = loop, budget = list(turns = 3))
ok("budget stops the run with status 'budget' and a budget_exceeded event", identical(s18$status, "budget") && "budget_exceeded" %in% s18$trace)
gptr_config(compaction_max = 5L)
s18b = gptr("loop", model = fake(call_r("1"), call_r("2"), call_r("3"), list(text = "fin")))
ok("compaction strategy ran via the compactor kind", "compaction" %in% s18b$trace)
gptr_config(compaction_max = 40L)

# ---- 19. conformance helpers ------------------------------------------------------------------------------------------
t_ok = gptr_tool("t1", "A tool.", list(type = "object", properties = list()), function(input, ctx) "x", annotations = list(read_only = TRUE))
t_bad = gptr_tool("t2", "", list(type = "object", properties = list()), function(input, ctx) "x")
ok("gptr_check passes a good tool", all(gptr_check(t_ok)$ok))
ok("gptr_check flags a bad tool (no description, no annotations)", sum(!gptr_check(t_bad)$ok) == 2L)
ok("gptr_check(error = TRUE) raises gptr_error_conformance", err_class(gptr_check(t_bad, error = TRUE)) == "gptr_error_conformance")
ok("gptr_check on a policy spec", all(gptr_check(gptr_policy("p", function(call, ctx) NULL))$ok))
ok("gptr_check on a factory (scratch registry, process registry untouched)",
   all(gptr_check(function(gptr) gptr$register(t_ok))$ok) && !("t1" %in% names(gptr_tools)))

# ---- 20. event names: canonical + helpful error for Claude/Codex names -------------------------------------------------
m = tryCatch(gptr_hook("PreToolUse", function(event, ctx) NULL), error = function(e) conditionMessage(e))
ok("Claude hook name is rejected with the canonical suggestion", grepl("did you mean 'tool_call'", m))

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
```

Output (`$G1/out/test_registry.out`):

```text
PASS built-ins register through the API (9 builtin extensions)
PASS categories present: tool/adapter/provider/hook/policy/context/compactor/doc_format/backend/ui/frontend/setting/section
PASS 21 core kinds are themselves registered specs (plus the bootstrap meta-kind)
PASS session settles
PASS run_r evaluated in the caller env (object persists)
PASS history writer (doc_format R via hook) recorded the code block
PASS context block session_context reached the model (it lists 'mice' and 'fit')
PASS event trace in Pi order
PASS user tool overrides builtin of the same name
PASS dispatcher resolves the winner
PASS call-level spec (rank 0) beats user and builtin
PASS -tool:grep hides grep
PASS +tool:grep restores it
PASS -builtin:permissions removes the mode policy (plan no longer blocks)
PASS policy back: plan mode denies mutating R code
PASS overriding doc_format R replaces the whole builtin:document extension (its writer hook too)
PASS disabling the override brings builtin:document back
PASS failing factory: nothing it staged reaches the registry
PASS failure recorded as a diagnostic
PASS factory requiring API >= 2.0 is refused with a clear message
PASS gptr$require() inside the factory rolls back its registrations
PASS calling a method this API version lacks gives a clear message (gptr_error_api_missing)
PASS bare '1.0' means >= 1.0, < 2 (caret)
PASS feature negotiation lists kinds and events
PASS reload drops non-enabled inline extensions
PASS captured API object raises gptr_error_stale_api
PASS manual mode without UI: ask becomes a denial (fail closed)
PASS a registered UI backend answers the ask (Yes)
PASS a throwing policy denies (fail closed)
PASS a throwing tool_call hook blocks the tool
PASS session hook patched the tool result before the model saw it
PASS session subscription fired
PASS fork does not share listeners (INFRA-14)
PASS .run = FALSE queues without running
PASS gptr_step ran exactly one model turn (tool turn)
PASS piping into a RUNNING session queues a steering message and returns the same object
PASS steering delivered after the tool result (INFRA-12 ordering)
PASS piping into an idle session appends a follow-up turn to the same session
PASS router picks a model per request
PASS route event emitted
PASS inline backend runs agents and returns named results
PASS third-party backend selected by the agent definition
PASS gptr_tools$grep returns R data (data frame), not tool text
PASS gptr_tools$.search finds r-exposed tools
PASS model-written R code calls a tool through the gate (plan: run_r itself denied)
PASS nested dispatcher call emits tool events (grep inside run_r)
PASS system prompt lists r-exposed tools as one-line signatures
PASS direct tools are declared natively; r-exposed grep is not
PASS a plugin adds a new capability kind and registers into it in the same factory
PASS inter-plugin event bus: one extension's emit reaches another's listener
PASS plugin-declared setting has a default readable with gptr_config()
PASS budget stops the run with status 'budget' and a budget_exceeded event
PASS compaction strategy ran via the compactor kind
PASS gptr_check passes a good tool
PASS gptr_check flags a bad tool (no description, no annotations)
PASS gptr_check(error = TRUE) raises gptr_error_conformance
PASS gptr_check on a policy spec
PASS gptr_check on a factory (scratch registry, process registry untouched)
PASS Claude hook name is rejected with the canonical suggestion

59 passed, 0 failed
```

### 5.3 Locking the extension API object

`$G1/proto/lock_state.R`

```r
# G1: the extension API object is locked, but `gptr$state$x = v` must still work.
# (1) a fully locked environment, (2) the prototype's partial locking.
e = new.env(); e$state = new.env(); e$register = function(x) x
lockEnvironment(e, bindings = TRUE)
cat("fully locked, e$state$n = 1:", tryCatch({ e$state$n = 1L; "ok" }, error = function(err) conditionMessage(err)), "\n")
st = e$state; st$n = 2L
cat("fully locked, via a local alias:", e$state$n, "\n")
suppressPackageStartupMessages(library(gptr))
keep = new.env()
gptr_register(function(gptr) keep$api = gptr, name = "x")
api = keep$api
api$state$n = 1L
cat("prototype API, api$state$n = 1:", api$state$n, "\n")
cat("replace a method:", tryCatch({ api$register = function(x) NULL; "replaced!" }, error = function(err) conditionMessage(err)), "\n")
cat("add a binding:", tryCatch({ api$newthing = 1; "added!" }, error = function(err) conditionMessage(err)), "\n")
cat("unknown method:", tryCatch(api$register_widget, error = function(err) paste(class(err)[1], "-", conditionMessage(err))), "\n")
```

Output (`$G1/out/lock_state.out`):

```text
fully locked, e$state$n = 1: cannot change value of locked binding for 'state' 
fully locked, via a local alias: 2 
prototype API, api$state$n = 1: 1 
replace a method: cannot change value of locked binding for 'register' 
add a binding: cannot add bindings to a locked environment 
unknown method: gptr_error_api_missing - the gptr extension API 1.0 has no method 'register_widget'; test with gptr$has() or require a newer API 
```

### 5.4 Third-party plugin packages

`gptrpanel` is an agentic-layer package (Imports: gptr): a lazily activated factory (one tool,
one command, one hook, one router when the kind exists), a domain skill, an agent definition, one
MCP server entry, and an orchestrator `panel_review()` built only on gptr exports. `cohortdesc` is a
domain package with gptr in Suggests that ships a delayed S3 describer and a skill.

`$G1/pkg/gptrpanel/DESCRIPTION`

```text
Package: gptrpanel
Title: Reviewer Panels for 'gptr' (Toy Third-Party Plugin)
Version: 0.1.0
Authors@R: person("G1", "Prototype", email = "g1@example.org", role = c("aut", "cre"))
Description: Toy plugin used by research track G1: an orchestrator that runs a
    panel of reviewer agents on one prompt through the public 'gptr' interface,
    plus a domain skill, one tool, one command, one hook and one MCP server entry.
License: MIT + file LICENSE
Encoding: UTF-8
Depends: R (>= 4.2)
Imports: gptr
Suggests: testthat (>= 3.0.0)
Config/gptr/plugin: true
Config/gptr/api: >= 1.0, < 2
Config/testthat/edition: 3
RoxygenNote: 7.3.3
```

`$G1/pkg/gptrpanel/NAMESPACE`

```text
# Generated by roxygen2: do not edit by hand

export(panel_plugin)
export(panel_review)
```

`$G1/pkg/gptrpanel/inst/gptr/plugin.json`

```json
{
  "name": "gptrpanel",
  "version": "0.1.0",
  "description": "Reviewer panels and clinical-trial lookups",
  "gptr": {"api": ">= 1.0, < 2"},
  "skills": "skills",
  "agents": "agents",
  "mcpServers": "mcp.json",
  "extension": {
    "entry": "gptrpanel::panel_plugin",
    "activation": "lazy",
    "provides": {"tool": ["trial_lookup"], "command": ["panel"], "hook": ["tool_result"]}
  }
}
```

`$G1/pkg/gptrpanel/inst/gptr/mcp.json`

```json
{"mcpServers": {"ctgov": {"command": "uvx", "args": ["ctgov-mcp"], "exposure": "r"}}}
```

`$G1/pkg/gptrpanel/inst/gptr/skills/clinical-trials/SKILL.md`

```markdown
---
name: clinical-trials
description: Find and appraise clinical trials for an indication; use trial_lookup() from R and report phase, N and primary endpoint.
---
Call `gptr_tools$trial_lookup(indication = "...")` inside run_r, keep the
result as a data frame and print only the columns you need.
```

`$G1/pkg/gptrpanel/inst/gptr/agents/methodologist.md`

```markdown
---
name: methodologist
description: Reviews study design, randomisation and endpoints.
---
You are a trial methodologist. Be terse.
```

`$G1/pkg/gptrpanel/R/plugin.R`

```r
#' gptr plugin factory for gptrpanel
#'
#' Registered lazily by gptr from `inst/gptr/plugin.json`; runs only when one of
#' the capabilities it provides is first used.
#' @param gptr The gptr extension API object.
#' @return `NULL`, invisibly.
#' @export
panel_plugin = function(gptr) {
  gptr$require(">= 1.0")
  gptr$register_tool("trial_lookup", "Look up registered trials for an indication. Returns a data frame.",
    list(type = "object", properties = list(indication = list(type = "string"), max = list(type = "integer")),
         required = list("indication")),
    function(input, ctx) {
      df = data.frame(id = c("NCT001", "NCT002"), phase = c("3", "2"), n = c(420L, 88L),
                      indication = input$indication)
      df = utils::head(df, input$max %||% 2L)
      gptr::gptr_tool_result(paste(df$id, df$phase, df$n), details = list(value = df))
    }, annotations = list(read_only = TRUE, open_world = TRUE), exposure = "r")
  gptr$register_command("panel", function(args, ctx) paste("panel for:", args), "Run a reviewer panel")
  gptr$on("tool_result", function(event, ctx) {
    gptr$state$n_results = (gptr$state$n_results %||% 0L) + 1L
    NULL
  })
  if (gptr$has("kind.router"))
    gptr$register_router("panel_route", function(request, ctx) ctx$get("model", "panel-default"))
  invisible(NULL)
}

`%||%` = function(a, b) if (is.null(a)) b else a

#' Run a reviewer panel
#'
#' An agentic layer built only on gptr's exported interface: one session per
#' reviewer, stepped round-robin, with a judge that sees every review.
#' @param prompt Task for the reviewers.
#' @param reviewers Named list of model specs, one per reviewer.
#' @param judge Model spec for the synthesis step, or `NULL`.
#' @param max_rounds Maximum steps per reviewer.
#' @return A list with `reviews` (named character), `verdict`, `usage` and `events`.
#' @export
panel_review = function(prompt, reviewers, judge = NULL, max_rounds = 10L) {
  sessions = lapply(reviewers, function(m) gptr::gptr(prompt, model = m, .run = FALSE))
  events = 0L
  for (s in sessions) gptr::gptr_on(s, "tool_execution_end", function(event, ctx) events <<- events + 1L)
  for (round in seq_len(max_rounds)) {
    live = Filter(function(s) !(s$status %in% c("done", "error", "aborted", "budget")), sessions)
    if (!length(live)) break
    for (s in live) gptr::gptr_step(s)
  }
  reviews = vapply(sessions, function(s) s$text, "")
  verdict = NULL
  if (!is.null(judge)) {
    j = gptr::gptr(paste0("Synthesise these reviews:\n", paste(names(reviews), reviews, sep = ": ", collapse = "\n")),
                   model = judge)
    verdict = j$text
  }
  list(reviews = reviews, verdict = verdict, usage = gptr::gptr_usage(sessions), events = events)
}
```

`$G1/pkg/gptrpanel/tests/testthat.R`

```r
library(testthat)
library(gptrpanel)
test_check("gptrpanel")
```

`$G1/pkg/gptrpanel/tests/testthat/test-conformance.R`

```r
test_that("plugin conforms to the gptr extension API", {
  chk = gptr::gptr_check("gptrpanel")
  expect_true(all(chk$ok), info = paste(chk$check[!chk$ok], collapse = "; "))
  expect_true(all(gptr::gptr_check(panel_plugin)$ok))
})

test_that("panel runs offline with the fake provider", {
  m = function(txt) gptr::gptr_fake_provider(list(list(text = txt)))
  out = panel_review("Is the design sound?", list(stats = m("power ok"), clin = m("endpoint ok")),
                     judge = m("accept"))
  expect_equal(unname(out$reviews), c("power ok", "endpoint ok"))
  expect_equal(out$verdict, "accept")
})
```

`$G1/pkg/cohortdesc/DESCRIPTION`

```text
Package: cohortdesc
Title: Cohort Objects with a 'gptr' Describer (Toy Domain Package)
Version: 0.1.0
Authors@R: person("G1", "Prototype", email = "g1@example.org", role = c("aut", "cre"))
Description: Toy domain package used by research track G1. It defines a small
    cohort class and, only when 'gptr' is installed, a compact describer method
    and a skill; 'gptr' is in Suggests.
License: MIT + file LICENSE
Encoding: UTF-8
Depends: R (>= 4.2)
Suggests: gptr
Config/gptr/plugin: true
Config/gptr/api: 1.0
```

`$G1/pkg/cohortdesc/NAMESPACE`

```text
export(cohort)
S3method(print, cohort)
S3method(gptr::gptr_describe, cohort)
```

`$G1/pkg/cohortdesc/R/cohort.R`

```r
cohort = function(n, name = "cohort") structure(list(n = n, name = name, ages = seq_len(n) %% 90), class = "cohort")

print.cohort = function(x, ...) { cat("<cohort ", x$name, ": ", x$n, " people>\n", sep = ""); invisible(x) }

# Registered lazily with S3method(gptr::gptr_describe, cohort): no hard dependency on gptr.
gptr_describe.cohort = function(x, budget = 300L, ...) {
  c(sprintf("<cohort %s> %d people", x$name, x$n), sprintf("age range %d-%d", min(x$ages), max(x$ages)))
}
```

`$G1/pkg/cohortdesc/inst/gptr/skills/cohort-qc/SKILL.md`

```markdown
---
name: cohort-qc
description: Quality-control checks for cohort objects (sizes, age ranges, missingness).
---
Use gptr_describe() on cohort objects before printing them.
```

The hand-written Rd file below was added by the verification pass, which found that without it
`R CMD check --as-cran` of the rebuilt package gives 1 WARNING "Undocumented code objects".

`$G1/pkg/cohortdesc/man/cohort.Rd`

```text
\name{cohort}
\alias{cohort}
\title{Create a toy cohort}
\usage{cohort(n, name = "cohort")}
\arguments{
\item{n}{Number of people.}
\item{name}{Cohort name.}
}
\value{An object of class \code{cohort}.}
\description{Creates a toy cohort object.}
\examples{
x = cohort(10)
x
}
```

### 5.5 Plugin integration checks (21/21)

`$G1/proto/test_plugin.R`

```r
# G1: third-party plugin packages installed into a temporary library, used without ':::'.
# Run: R_LIBS=<G1>/lib Rscript --vanilla test_plugin.R
n_pass = 0L; n_fail = 0L
ok = function(label, cond) {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("PASS ", label, "\n", sep = "") }
  else { n_fail <<- n_fail + 1L; cat("FAIL ", label, "\n", sep = "") }
}

# ---- A. domain package with gptr only in Suggests: delayed S3 registration --------------------------
x = cohortdesc::cohort(25, "pilot")
ok("cohortdesc loads without loading gptr", !("gptr" %in% loadedNamespaces()))
library(gptr)
ok("S3method(gptr::gptr_describe, cohort) registered lazily once gptr loads",
   identical(gptr_describe(x)[1], "<cohort pilot> 25 people"))

# ---- B. discovery and declarative registration ---------------------------------------------------------
pl = gptr_plugins(installed = TRUE)
ok("installed plugin packages discovered by a vectorised dir.exists() scan", all(c("gptrpanel", "cohortdesc") %in% pl$package))
gptr_register("gptrpanel")                                   # lazy by default
r = gptr_registry()
ok("skill, agent and MCP entry registered from files, no code run",
   all(c("clinical-trials", "methodologist", "ctgov") %in% r$name))
ok("extension declared but NOT executed: plugin namespace not loaded", !("gptrpanel" %in% loadedNamespaces()))
ok("provided tool listed as a lazy placeholder", r$status[r$name == "trial_lookup"] == "lazy")

# ---- C. lazy activation on first use -------------------------------------------------------------------
df = gptr_tools$trial_lookup(indication = "asthma", max = 1L)
ok("first use activates the plugin (namespace now loaded)", "gptrpanel" %in% loadedNamespaces())
ok("tool returns R data through the dispatcher", is.data.frame(df) && nrow(df) == 1L && df$indication == "asthma")
ok("placeholder replaced by the real registration", gptr_registry("tool")$status[gptr_registry("tool")$name == "trial_lookup"] == "active")
ok("capability negotiation: plugin saw kind.router and registered its router", "panel_route" %in% gptr_registry("router")$name)

# ---- D. the plugin's hook participates in a session; state kept per extension ---------------------------
gptr_config(mode = "auto")
m = gptr_fake_provider(list(list(text = "", tool_calls = list(list(name = "run_r", arguments = list(code = "1 + 1")))),
                            list(text = "two")))
s = gptr("add", model = m)
ok("session ran with the plugin hook active", identical(s$text, "two"))

# ---- E. an agentic layer built on the public SDK only ------------------------------------------------------
fk = function(...) gptr_fake_provider(list(...))
out = gptrpanel::panel_review("Is the trial design sound?",
  reviewers = list(stats = fk(list(text = "", tool_calls = list(list(name = "run_r", arguments = list(code = "power.t.test(n = 20, delta = 1)$power")))),
                              list(text = "power 0.87: ok")),
                   clin = fk(list(text = "endpoint is clinically relevant"))),
  judge = fk(list(text = "accept with minor revisions")))
ok("panel_review interleaves reviewer sessions with gptr_step()", identical(unname(out$reviews), c("power 0.87: ok", "endpoint is clinically relevant")))
ok("judge synthesis via gptr()", identical(out$verdict, "accept with minor revisions"))
ok("events observed with gptr_on() and usage aggregated with gptr_usage()", out$events == 1L && out$usage$turns == 3L)

# ---- F. conformance helper, as a plugin's own testthat suite would call it ----------------------------------
chk = gptr_check("gptrpanel")
print(chk[, c("check", "ok")], row.names = FALSE)
ok("gptr_check('gptrpanel'): manifest 'provides' matches what the factory registers", all(chk$ok))

# ---- G. unload / reload invalidates stale records ------------------------------------------------------------
unloadNamespace("gptrpanel")
r = gptr_registry("tool")
ok("onUnload hook: records of the unloaded namespace go back to lazy", r$status[r$name == "trial_lookup"] == "lazy")
df2 = gptr_tools$trial_lookup(indication = "copd")
ok("next use re-activates from the reloaded namespace", "gptrpanel" %in% loadedNamespaces() && df2$indication[1] == "copd")

# ---- H. filters disable a whole plugin -------------------------------------------------------------------------
gptr_filter("-plugin:gptrpanel")
ok("-plugin:gptrpanel hides its tool, skill and MCP entry",
   !any(c("trial_lookup", "clinical-trials", "ctgov") %in% gptr_registry()$name[gptr_registry()$status != "shadowed"]))
gptr_filter("+plugin:gptrpanel")

# ---- I. API mismatch in a manifest is refused with a classed, readable diagnostic -------------------------------
d = file.path(tempdir(), "future-plugin"); dir.create(file.path(d, "extensions"), recursive = TRUE, showWarnings = FALSE)
writeLines('{"name": "future", "gptr": {"api": ">= 2.0"}}', file.path(d, "plugin.json"))
writeLines("function(gptr) gptr$register_command('f', function(args, ctx) NULL)", file.path(d, "extensions", "f.R"))
gptr_register(d)
dd = gptr_registry(diagnostics = TRUE)
ok("directory plugin requiring API >= 2.0 refused", any(grepl("requires gptr extension API >= 2.0", dd$message)) &&
   !("f" %in% gptr_registry("command")$name))
cls = NULL
gptr_register(function(gptr) cls <<- tryCatch(gptr$require(">= 2.0"), error = function(e) class(e)), name = "probe-cls")
ok("the condition class is gptr_error_api_version", "gptr_error_api_version" %in% cls)

# ---- J. no ':::' anywhere in the plugin packages -------------------------------------------------------------------
src = c(list.files(system.file(package = "gptrpanel"), recursive = TRUE, full.names = TRUE),
        list.files(system.file(package = "cohortdesc"), recursive = TRUE, full.names = TRUE))
rfiles = unlist(lapply(c("gptrpanel", "cohortdesc"), function(p) {
  ns = asNamespace(p); unlist(lapply(ls(ns, all.names = TRUE), function(f) deparse(get(f, ns)))) }))
ok("no ':::' in the plugin packages' code", !any(grepl(":::", rfiles, fixed = TRUE)))

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
```

Output (`$G1/out/test_plugin.out`):

```text
PASS cohortdesc loads without loading gptr
PASS S3method(gptr::gptr_describe, cohort) registered lazily once gptr loads
PASS installed plugin packages discovered by a vectorised dir.exists() scan
PASS skill, agent and MCP entry registered from files, no code run
PASS extension declared but NOT executed: plugin namespace not loaded
PASS provided tool listed as a lazy placeholder
PASS first use activates the plugin (namespace now loaded)
PASS tool returns R data through the dispatcher
PASS placeholder replaced by the real registration
PASS capability negotiation: plugin saw kind.router and registered its router
PASS session ran with the plugin hook active
PASS panel_review interleaves reviewer sessions with gptr_step()
PASS judge synthesis via gptr()
PASS events observed with gptr_on() and usage aggregated with gptr_usage()
                                                            check   ok
                                          package ships inst/gptr TRUE
                                      declares an API requirement TRUE
                                        API requirement satisfied TRUE
                               plugin loads eagerly without error TRUE
 manifest provides tool:trial_lookup and the factory registers it TRUE
     manifest provides command:panel and the factory registers it TRUE
  manifest provides hook:tool_result and the factory registers it TRUE
                          skill clinical-trials has a description TRUE
PASS gptr_check('gptrpanel'): manifest 'provides' matches what the factory registers
PASS onUnload hook: records of the unloaded namespace go back to lazy
PASS next use re-activates from the reloaded namespace
PASS -plugin:gptrpanel hides its tool, skill and MCP entry
PASS directory plugin requiring API >= 2.0 refused
PASS the condition class is gptr_error_api_version
PASS no ':::' in the plugin packages' code

21 passed, 0 failed
```

### 5.6 Object system: R6 vs S3 + environments

`$G1/proto/bench_objsys.R`

```r
# G1: R6 vs S3 + environments for registry, API and ctx objects (D-02).
# Run: Rscript --vanilla bench_objsys.R
suppressPackageStartupMessages({ library(microbenchmark); library(R6) })
cat("R", as.character(getRversion()), " R6", as.character(packageVersion("R6")), "\n")
med = function(mb) { s = summary(mb, unit = "us"); stats::setNames(round(s$median, 2), s$expr) }

# ---- 1. calling one method ------------------------------------------------------------------------
# (a) environment holding closures (the gptr API / ctx design), locked
make_env_api = function() {
  st = new.env(parent = emptyenv()); st$n = 0L
  api = new.env(parent = emptyenv())
  api$register = function(x) { st$n = st$n + 1L; invisible(x) }
  lockEnvironment(api, bindings = TRUE)
  api
}
# (b) the same with an S3 class and a `$` method that gives a classed error for unknown names
make_env_api_s3 = function() {
  a = make_env_api(); class(a) = "demo_api"; a
}
`$.demo_api` = function(x, name) {
  if (!exists(name, envir = x, inherits = FALSE)) stop("no method ", name)
  get(name, envir = x, inherits = FALSE)
}
# (c) R6
Api6 = R6Class("Api6", public = list(n = 0L, register = function(x) { self$n = self$n + 1L; invisible(x) }))
# (d) S3 generic on an environment
register = function(api, x) UseMethod("register")
register.demo_reg = function(api, x) { api$n = api$n + 1L; invisible(x) }
e1 = make_env_api(); e2 = make_env_api_s3(); r6 = Api6$new()
g = structure(new.env(), class = "demo_reg"); g$n = 0L
plain = function(x) invisible(x)
mb1 = microbenchmark(
  plain_function = plain(1),
  env_closure = e1$register(1),
  env_closure_S3_dollar = e2$register(1),
  R6_method = r6$register(1),
  S3_generic = register(g, 1),
  times = 20000L)
cat("\n1. method call, median microseconds\n"); print(med(mb1))

# ---- 2. creating a ctx-like object with 10 methods ------------------------------------------------
new_ctx_env = function(s) {
  ctx = new.env(parent = emptyenv())
  ctx$session = s
  ctx$m1 = function() s$a; ctx$m2 = function() s$b; ctx$m3 = function(x) x; ctx$m4 = function(x) x
  ctx$m5 = function(x) x; ctx$m6 = function(x) x; ctx$m7 = function(x) x; ctx$m8 = function(x) x
  ctx$m9 = function(x) x; ctx$m10 = function(x) x
  lockEnvironment(ctx, bindings = TRUE)
  class(ctx) = "demo_ctx"
  ctx
}
Ctx6 = R6Class("Ctx6", public = list(session = NULL, initialize = function(s) self$session = s,
  m1 = function() self$session$a, m2 = function() self$session$b, m3 = function(x) x, m4 = function(x) x,
  m5 = function(x) x, m6 = function(x) x, m7 = function(x) x, m8 = function(x) x, m9 = function(x) x, m10 = function(x) x))
Ctx6np = R6Class("Ctx6np", portable = FALSE, cloneable = FALSE, public = list(session = NULL, initialize = function(s) session <<- s,
  m1 = function() session$a, m2 = function() session$b, m3 = function(x) x, m4 = function(x) x,
  m5 = function(x) x, m6 = function(x) x, m7 = function(x) x, m8 = function(x) x, m9 = function(x) x, m10 = function(x) x))
s = new.env(); s$a = 1; s$b = 2
mb2 = microbenchmark(
  list_record = list(session = s, a = 1, b = 2),
  env_10_closures_locked = new_ctx_env(s),
  R6_new_portable = Ctx6$new(s),
  R6_new_nonportable_nonclone = Ctx6np$new(s),
  times = 5000L)
cat("\n2. create a ctx-like object, median microseconds\n"); print(med(mb2))

# ---- 3. locking semantics ------------------------------------------------------------------------------
cat("\n3. locking\n")
cat("env: add binding ->", tryCatch({ e1$x = 1; "allowed" }, error = function(e) conditionMessage(e)), "\n")
cat("env: replace method ->", tryCatch({ e1$register = NULL; "allowed" }, error = function(e) conditionMessage(e)), "\n")
cat("R6 default: add member ->", tryCatch({ r6$x = 1; "allowed" }, error = function(e) conditionMessage(e)), "\n")
cat("R6 default: replace method ->", tryCatch({ r6$register = NULL; "allowed" }, error = function(e) conditionMessage(e)), "\n")
cat("R6 default: change field ->", tryCatch({ r6$n = 5L; "allowed" }, error = function(e) conditionMessage(e)), "\n")

# ---- 4. size of one object -------------------------------------------------------------------------------
cat("\n4. object.size (bytes): env ctx", format(utils::object.size(new_ctx_env(s))), "; R6 ctx",
    format(utils::object.size(Ctx6$new(s))), "(object.size does not follow environments; indicative only)\n")
cat("   serialised bytes: env ctx", length(serialize(new_ctx_env(s), NULL)), "; R6 ctx", length(serialize(Ctx6$new(s), NULL)), "\n")

# ---- 5. dependency cost ------------------------------------------------------------------------------------
deps = tools::package_dependencies(c("httr2", "processx", "callr", "curl", "jsonlite", "cli", "yaml", "rlang"),
                                   db = installed.packages(), recursive = TRUE, which = c("Depends", "Imports", "LinkingTo"))
cat("\n5. R6 already in the hard-dependency closure of:", paste(names(deps)[vapply(deps, function(d) "R6" %in% d, NA)], collapse = ", "), "\n")
lt = vapply(1:5, function(i) as.numeric(system2(file.path(R.home("bin"), "Rscript"),
  c("--vanilla", "-e", shQuote("cat(system.time(loadNamespace('R6'))[['elapsed']])")), stdout = TRUE)), 0)
cat("   loadNamespace('R6') in a fresh process, 5 runs (s):", paste(lt, collapse = " "), "\n")
```

Output, run 2 (load average 82; `$G1/out/bench_objsys.out`):

```text
R 4.4.3  R6 2.6.1 

1. method call, median microseconds
       plain_function           env_closure env_closure_S3_dollar 
                 0.41                  1.93                  5.37 
            R6_method            S3_generic 
                 4.51                  4.10 

2. create a ctx-like object, median microseconds
                list_record      env_10_closures_locked 
                       0.49                        4.96 
            R6_new_portable R6_new_nonportable_nonclone 
                      69.13                       70.07 

3. locking
env: add binding -> cannot add bindings to a locked environment 
env: replace method -> cannot change value of locked binding for 'register' 
R6 default: add member -> cannot add bindings to a locked environment 
R6 default: replace method -> cannot change value of locked binding for 'register' 
R6 default: change field -> allowed 

4. object.size (bytes): env ctx 288 bytes ; R6 ctx 344 bytes (object.size does not follow environments; indicative only)
   serialised bytes: env ctx 2991 ; R6 ctx 14390 

5. R6 already in the hard-dependency closure of: httr2, processx, callr 
   loadNamespace('R6') in a fresh process, 5 runs (s): 0.007 0.005 0.026 0.008 0.008 
```

Output, run 3 (load average 15; `$G1/out/bench_objsys2.out`):

```text
R 4.4.3  R6 2.6.1 

1. method call, median microseconds
       plain_function           env_closure env_closure_S3_dollar 
                 0.37                  1.64                  4.55 
            R6_method            S3_generic 
                 3.81                  3.44 

2. create a ctx-like object, median microseconds
                list_record      env_10_closures_locked 
                       0.25                        3.16 
            R6_new_portable R6_new_nonportable_nonclone 
                      46.58                       47.44 

3. locking
env: add binding -> cannot add bindings to a locked environment 
env: replace method -> cannot change value of locked binding for 'register' 
R6 default: add member -> cannot add bindings to a locked environment 
R6 default: replace method -> cannot change value of locked binding for 'register' 
R6 default: change field -> allowed 

4. object.size (bytes): env ctx 288 bytes ; R6 ctx 344 bytes (object.size does not follow environments; indicative only)
   serialised bytes: env ctx 2991 ; R6 ctx 14390 

5. R6 already in the hard-dependency closure of: httr2, processx, callr 
   loadNamespace('R6') in a fresh process, 5 runs (s): 0.005 0.003 0.002 0.004 0.003 
```

Run 1 (load average 12, before the load-time measurement was fixed) gave method-call medians
0.41 / 1.84 / 5.04 / 4.39 / 3.98 µs and creation medians 0.41 / 4.67 / 75.64 / 61.42 µs, the same
ordering.

### 5.7 Start-up and dispatch cost with 0, 10, 100 plugins

`$G1/proto/bench_startup.R`

```r
# G1: registry start-up and dispatch cost with 0, 10 and 100 plugins.
# Uses gptr internals only to build fresh registries for timing (measurement script).
# Run: R_LIBS=<G1>/lib Rscript --vanilla bench_startup.R
suppressPackageStartupMessages(library(gptr))
ns = asNamespace("gptr")
fresh = function() { reg = ns$registry_new(); ns$register_builtins(reg); assign("registry", reg, envir = ns$the); reg }
reps = 5L
time_med = function(f) { t = vapply(seq_len(reps), function(i) { gc(FALSE); system.time(f())[["elapsed"]] }, 0); stats::median(t) * 1000 }

factory = function(i) {
  force(i)
  function(gptr) {
    gptr$register_tool(paste0("tool_", i), paste("Tool number", i, "from a plugin."),
      list(type = "object", properties = list(x = list(type = "string")), required = list("x")),
      function(input, ctx) input$x, annotations = list(read_only = TRUE), exposure = "r")
    gptr$register_command(paste0("cmd_", i), function(args, ctx) NULL, "A command")
    gptr$on("tool_result", function(event, ctx) NULL)
  }
}

root = file.path(tempdir(), "plugdirs"); dir.create(root, showWarnings = FALSE)
make_dirs = function(n) {
  for (i in seq_len(n)) {
    d = file.path(root, sprintf("p%03d", i))
    if (dir.exists(d)) next
    dir.create(file.path(d, "skills", paste0("skill", i)), recursive = TRUE); dir.create(file.path(d, "extensions"))
    writeLines(sprintf('{"name": "p%03d", "gptr": {"api": ">= 1.0, < 2"}}', i), file.path(d, "plugin.json"))
    writeLines(c("---", paste0("name: skill", i), paste0("description: Skill ", i, " for benchmarking."), "---", "Body"),
               file.path(d, "skills", paste0("skill", i), "SKILL.md"))
    writeLines(c("function(gptr) {",
                 sprintf("  gptr$register_tool('dtool_%d', 'Dir tool %d.', list(type = 'object', properties = list()), function(input, ctx) 'x', annotations = list(read_only = TRUE))", i, i),
                 sprintf("  gptr$register_command('dcmd_%d', function(args, ctx) NULL)", i),
                 "  gptr$on('tool_result', function(event, ctx) NULL)", "}"), file.path(d, "extensions", "ext.R"))
  }
}
make_dirs(100)

rows = list()
for (n in c(0L, 10L, 100L)) {
  t_builtins = time_med(function() fresh())
  t_eager = time_med(function() { reg = fresh(); for (i in seq_len(n)) ns$ext_load(reg, factory(i), paste0("p", i), "user") })
  t_dirs = time_med(function() { reg = fresh(); for (i in seq_len(n)) ns$plugin_load_dir(reg, file.path(root, sprintf("p%03d", i))) })
  t_lazy = time_med(function() {
    reg = fresh()
    for (i in seq_len(n)) ns$ext_declare_lazy(reg, paste0("lz", i), function() factory(i),
      list(tool = paste0("tool_", i), command = paste0("cmd_", i), hook = "tool_result"), "package")
  })
  # first resolution of all tools after an eager load (cache cold), then warm
  reg = fresh(); for (i in seq_len(n)) ns$ext_load(reg, factory(i), paste0("p", i), "user")
  t_resolve_cold = system.time(ns$resolve(reg, "tool"))[["elapsed"]] * 1000
  t_resolve_warm = system.time(for (k in 1:100) ns$resolve(reg, "tool"))[["elapsed"]] * 10
  # a session run with one tool call: every plugin's tool_result hook fires once
  gptr_config(mode = "auto")
  m = function() gptr_fake_provider(list(list(text = "", tool_calls = list(list(name = "ls", arguments = list(path = ".")))), list(text = "ok")))
  t_run = time_med(function() gptr("go", model = m()))
  rows[[length(rows) + 1L]] = data.frame(plugins = n, records = sum(!vapply(reg$recs, `[[`, NA, "dead")),
    builtins_ms = t_builtins, eager_factories_ms = t_eager, dir_plugins_ms = t_dirs, lazy_manifests_ms = t_lazy,
    resolve_cold_ms = t_resolve_cold, resolve_warm_ms = round(t_resolve_warm, 2), session_run_ms = t_run)
}
print(do.call(rbind, rows), row.names = FALSE)
t_scan = time_med(function() gptr_plugins(installed = TRUE))
cat("\ngptr_plugins(installed = TRUE) over", length(list.files(.libPaths())), "installed packages:", t_scan, "ms (median of 5)\n")
cat("load average at end:", system("uptime", intern = TRUE), "\n")
```

Output, run 1 after the regex fix (load average 34; `$G1/out/bench_startup.out`):

```text
 plugins records builtins_ms eager_factories_ms dir_plugins_ms
       0      42           3                  2              3
      10      72           3                  6             11
     100     342           3                 28            106
 lazy_manifests_ms resolve_cold_ms resolve_warm_ms session_run_ms
                 3               1            0.01              3
                 3               0            0.01              4
                 8               2            0.00             20

gptr_plugins(installed = TRUE) over 618 installed packages: 3 ms (median of 5)
load average at end: 22:30  up 7 days, 18:58, 1 user, load averages: 32.25 44.46 29.02 
```

Output, run 2 (load average 32; `$G1/out/bench_startup2.out`):

```text
 plugins records builtins_ms eager_factories_ms dir_plugins_ms
       0      42           4                  5              5
      10      72           5                  8             18
     100     342           4                 37            128
 lazy_manifests_ms resolve_cold_ms resolve_warm_ms session_run_ms
                 4               1            0.00              4
                 4               1            0.01              6
                 9               4            0.00             24

gptr_plugins(installed = TRUE) over 618 installed packages: 3 ms (median of 5)
load average at end: 22:31  up 7 days, 18:58, 1 user, load averages: 31.27 44.06 28.97 
```

Output, run 3 (load average 15; `$G1/out/bench_startup3.out`):

```text
 plugins records builtins_ms eager_factories_ms dir_plugins_ms
       0      42           8                  7              6
      10      72           6                 17             25
     100     342           7                 49            189
 lazy_manifests_ms resolve_cold_ms resolve_warm_ms session_run_ms
                 9               1            0.01              6
                 6               0            0.02              7
                16               3            0.01             39

gptr_plugins(installed = TRUE) over 618 installed packages: 5 ms (median of 5)
load average at end: 22:40  up 7 days, 19:07, 1 user, load averages: 14.48 16.34 20.18 
```

`$G1/proto/bench_lazy.R`

```r
# G1: lazy vs eager registration of the installed toy plugin package, fresh process per run.
# Run: R_LIBS=<G1>/lib Rscript --vanilla bench_lazy.R
rs = file.path(R.home("bin"), "Rscript")
lazy = 'suppressPackageStartupMessages(library(gptr)); a = system.time(gptr_register("gptrpanel", lazy = TRUE))[["elapsed"]]; l1 = "gptrpanel" %in% loadedNamespaces(); b = system.time(gptr_tools$trial_lookup(indication = "x"))[["elapsed"]]; cat(sprintf("lazy register %.3f s (namespace loaded: %s); first use incl. activation %.3f s\n", a, l1, b))'
eager = 'suppressPackageStartupMessages(library(gptr)); a = system.time(gptr_register("gptrpanel", lazy = FALSE))[["elapsed"]]; cat(sprintf("eager register %.3f s (namespace loaded: %s)\n", a, "gptrpanel" %in% loadedNamespaces()))'
for (i in 1:3) cat(system2(rs, c("--vanilla", "-e", shQuote(lazy)), stdout = TRUE), sep = "\n")
for (i in 1:3) cat(system2(rs, c("--vanilla", "-e", shQuote(eager)), stdout = TRUE), sep = "\n")
cat(system2(rs, c("--vanilla", "-e", shQuote('cat("loadNamespace(Seurat):", system.time(suppressMessages(loadNamespace("Seurat")))[["elapsed"]], "s\n")')),
            stdout = TRUE, stderr = FALSE), sep = "\n")
```

Output (`$G1/out/bench_lazy.out`):

```text
lazy register 0.020 s (namespace loaded: FALSE); first use incl. activation 0.008 s
lazy register 0.015 s (namespace loaded: FALSE); first use incl. activation 0.006 s
lazy register 0.019 s (namespace loaded: FALSE); first use incl. activation 0.007 s
eager register 0.024 s (namespace loaded: TRUE)
eager register 0.021 s (namespace loaded: TRUE)
eager register 0.019 s (namespace loaded: TRUE)
loadNamespace(Seurat): 4.172 s
```

### 5.8 Profile of eager loading (the TRE regex finding)

`$G1/proto/prof_eager.R`

```r
suppressPackageStartupMessages(library(gptr))
ns = asNamespace("gptr")
factory = function(i) { force(i); function(gptr) {
  gptr$register_tool(paste0("tool_", i), "T.", list(type = "object", properties = list(x = list(type = "string"))),
    function(input, ctx) input$x, annotations = list(read_only = TRUE), exposure = "r")
  gptr$register_command(paste0("cmd_", i), function(args, ctx) NULL, "A command")
  gptr$on("tool_result", function(event, ctx) NULL) } }
f = tempfile(); Rprof(f, interval = 0.002)
for (k in 1:5) { reg = ns$registry_new(); ns$register_builtins(reg); for (i in 1:100) ns$ext_load(reg, factory(i), paste0("p", i), "user") }
Rprof(NULL); s = summaryRprof(f)$by.total; print(head(s[, c("total.time", "total.pct")], 18))
```

Output of the first version (tool-name validation with `grepl("^[A-Za-z][A-Za-z0-9_]{0,63}$", name)`,
TRE engine; captured from the terminal before the fix, top rows):

```text
                       total.time total.pct
"ns$ext_load"               0.448     87.50
"tryCatch"                  0.358     69.92
"tryCatchList"              0.356     69.53
"doTryCatch"                0.352     68.75
"tryCatchOne"               0.352     68.75
"factory"                   0.330     64.45
"api$register"              0.292     57.03
"gptr$register_tool"        0.246     48.05
"ctor"                      0.242     47.27
"grepl"                     0.206     40.23
"api_new"                   0.108     21.09
```

The same startup benchmark before the fix (load average 50-124) gave, for 100 plugins, eager
209-293 ms and directory plugins 442-738 ms, with built-ins alone at 14-19 ms.

Output after `perl = TRUE` and precomputed sugar names (`$G1/out/prof_eager.out`):

```text
                       total.time total.pct
"ns$ext_load"               0.200     81.97
"doTryCatch"                0.130     53.28
"tryCatch"                  0.130     53.28
"tryCatchList"              0.130     53.28
"tryCatchOne"               0.130     53.28
"factory"                   0.114     46.72
"api$register"              0.080     32.79
"api_new"                   0.054     22.13
"gptr$register_tool"        0.052     21.31
"commit"                    0.046     18.85
"ctor"                      0.044     18.03
"<Anonymous>"               0.042     17.21
"$"                         0.034     13.93
"ext_load"                  0.028     11.48
"ns$register_builtins"      0.028     11.48
"vapply"                    0.024      9.84
"new_spec"                  0.024      9.84
"get"                       0.022      9.02
```

### 5.9 Token cost of declarations (rtiktoken o200k_base)

`$G1/proto/dump_btw_tools.R`

```r
# Dump btw 1.5.0's tool declarations (Anthropic wire format) as a realistic corpus
# for token measurements. Uses ellmer internals only in this measurement script.
.libPaths(c(file.path(Sys.getenv("SP"), "work/track10/rlib"), .libPaths()))
suppressPackageStartupMessages({ library(ellmer); library(btw) })
prov = ellmer:::ProviderAnthropic(name = "Anthropic", base_url = "x", credentials = function() "x",
                                  beta_headers = character(), cache = "none")
options(btw.run_r.enabled = TRUE)
tools = btw_tools()
js = lapply(tools, function(t) ellmer:::as_json(prov, t))
cat("btw", as.character(packageVersion("btw")), "ellmer", as.character(packageVersion("ellmer")), "tools:", length(js), "\n")
writeLines(jsonlite::toJSON(js, auto_unbox = TRUE, pretty = FALSE), file.path(Sys.getenv("W"), "out", "btw_tools.json"))
```

Output: `btw 1.5.0 ellmer 0.5.0 tools: 31` (file `$G1/out/btw_tools.json`, 46,236 bytes).

`$G1/proto/tokens.R`

```r
# G1: token cost of plugin-provided declarations under eager vs deferred exposure.
# Corpus: btw 1.5.0's 31 real tool declarations (Anthropic wire format), plus the toy
# plugin's skill/agent entries. Tokenizer: rtiktoken o200k_base (private library).
# Run: R_LIBS=<G1>/lib:<scratchpad>/rlib Rscript --vanilla tokens.R
suppressPackageStartupMessages(library(gptr))
tok = function(x) sum(rtiktoken::get_token_count(paste(x, collapse = "\n"), "o200k_base"))
W = Sys.getenv("W")
decl = jsonlite::fromJSON(file.path(W, "out", "btw_tools.json"), simplifyVector = FALSE)

# The same tools as gptr specs (execute is a stub; only declarations matter here)
specs = lapply(decl, function(d) gptr_tool(gsub("[^A-Za-z0-9_]", "_", d$name), d$description,
                                            d$input_schema, function(input, ctx) "", exposure = "r"))
one_json = function(d) as.character(jsonlite::toJSON(d, auto_unbox = TRUE))
sig = function(s) {
  props = s$parameters$properties
  req = unlist(s$parameters$required)
  a = vapply(names(props), function(n) paste0(n, if (n %in% req) "" else "?", ": ",
                                              props[[n]]$type %||% "any"), "")
  paste0("gptr_tools$", s$name, "(", paste(a, collapse = ", "), ")  # ",
         sub("([.!?])\\s.*$", "\\1", gsub("\\s+", " ", s$description)))
}
search_tool = one_json(list(name = "tool_search", description = "Search deferred tools by keyword; matches become callable next turn.",
  input_schema = list(type = "object", properties = list(query = list(type = "string")), required = list("query"))))

cost = function(idx) {
  d = decl[idx]; s = specs[idx]
  c(n = length(idx),
    direct_json = tok(vapply(d, one_json, "")),
    r_signatures = tok(vapply(s, sig, "")),
    deferred = tok(c(sprintf("# %d more tools: gptr_tools$.search(\"query\")", length(idx)), search_tool)),
    hidden = 0)
}
set_10 = 1:10; set_31 = seq_along(decl)
res = rbind(cost(set_10), cost(set_31))
# 100 tools: the 31 real declarations repeated (names made unique); marked as extrapolation
rep_idx = rep(set_31, length.out = 100)
d100 = decl[rep_idx]; s100 = specs[rep_idx]
res = rbind(res, c(n = 100, direct_json = tok(vapply(d100, one_json, "")), r_signatures = tok(vapply(s100, sig, "")),
                   deferred = tok(c("# 100 more tools: gptr_tools$.search(\"query\")", search_tool)), hidden = 0))
print(res)
cat("\nper tool (31 real): direct", round(res[2, "direct_json"] / 31, 1), "tokens; r-signature",
    round(res[2, "r_signatures"] / 31, 1), "tokens; ratio", round(res[2, "direct_json"] / res[2, "r_signatures"], 1), "x\n")

# chars/4 estimate vs o200k on the same text (calibration check, report 21)
txt = paste(vapply(decl, one_json, ""), collapse = "\n")
cat("direct JSON: chars/4 =", ceiling(nchar(txt) / 4), " o200k =", tok(txt), "\n")

# Example signature lines as the model sees them
cat("\nexample r-exposure lines:\n"); cat(head(vapply(specs, sig, ""), 3), sep = "\n")

# ---- skills / agents / prompt templates from plugins ------------------------------------------------------------
sk = "<skill><name>clinical-trials</name><description>Find and appraise clinical trials for an indication; use trial_lookup() from R and report phase, N and primary endpoint.</description><location>/lib/gptrpanel/gptr/skills/clinical-trials/SKILL.md</location></skill>"
ag = "methodologist: Reviews study design, randomisation and endpoints. (model inherit, backend inline)"
cat("\ncatalog entry cost: skill", tok(sk), "tokens; agent", tok(ag), "tokens; prompt template 0 (expands user input only)\n")

# ---- dispatcher spellings in model-written code --------------------------------------------------------------------
calls = c("gptr_tools$grep(\"TODO\", \"R\")", "tools$grep(\"TODO\", \"R\")", "gptr::tools$grep(\"TODO\", \"R\")",
          "gptr_tools$github$search_code(q = \"x\")", "mcp$github$search_code(q = \"x\")",
          "gptr_tools$mcp__github__search_code(q = \"x\")",
          "gptr(\"Summarise x\", x, model = haiku)")
print(data.frame(call = calls, o200k = vapply(calls, tok, 0), row.names = NULL))

# ---- composition: one R evaluation vs N model-visible tool round trips ---------------------------------------------
# Three lookups + a merge done as three direct tool calls (each call and result is model-visible), vs one run_r call.
tc = function(name, args) one_json(list(type = "tool_use", id = "toolu_01ABCDEFGHIJKLMNOPQRSTUV", name = name, input = args))
res_txt = paste(sprintf("NCT%03d | phase %d | n=%d | primary endpoint: FEV1 change at week 12", 1:20, rep(2:3, 10), 50 + 1:20 * 7), collapse = "\n")
three = c(tc("trial_lookup", list(indication = "asthma")), res_txt, tc("trial_lookup", list(indication = "copd")), res_txt,
          tc("trial_lookup", list(indication = "bronchiectasis")), res_txt)
one = c(tc("run_r", list(code = "t = lapply(c('asthma','copd','bronchiectasis'), \\(i) gptr_tools$trial_lookup(i)); d = do.call(rbind, t); table(d$phase, d$indication)")),
        "            asthma bronchiectasis copd\n  2            10             10   10\n  3            10             10   10")
cat("\ncomposition: 3 direct tool round trips =", tok(three), "tokens of transcript; 1 run_r composition =", tok(one), "tokens\n")
```

Output (`$G1/out/tokens.out`):

```text
       n direct_json r_signatures deferred hidden
[1,]  10        3032          394       55      0
[2,]  31       10156         1129       55      0
[3,] 100       32869         3649       55      0

per tool (31 real): direct 327.6 tokens; r-signature 36.4 tokens; ratio 9 x
direct JSON: chars/4 = 11355  o200k = 10156 

example r-exposure lines:
gptr_tools$btw_tool_agent_subagent(prompt: string, tools?: array, session_id?: string, _intent: string)  #  Delegate a task to a specialized assistant that can work independently with its own conversation thread.
gptr_tools$btw_tool_cran_search(query: string, format?: string, n_results?: number, _intent: string)  # Search for an R package on CRAN.
gptr_tools$btw_tool_cran_versions(package_name: string, after?: string, before?: string, _intent: string)  # List a CRAN package's release versions and dates.

catalog entry cost: skill 63 tokens; agent 19 tokens; prompt template 0 (expands user input only)
                                          call o200k
1                 gptr_tools$grep("TODO", "R")    11
2                      tools$grep("TODO", "R")     9
3                gptr::tools$grep("TODO", "R")    12
4       gptr_tools$github$search_code(q = "x")    13
5              mcp$github$search_code(q = "x")    12
6 gptr_tools$mcp__github__search_code(q = "x")    15
7        gptr("Summarise x", x, model = haiku)    15

composition: 3 direct tool round trips = 1532 tokens of transcript; 1 run_r composition = 109 tokens
```

### 5.10 Pi changelog: releases and breaking changes

`$G1/proto/pi_changelog.py`

```python
# G1: count releases and "Breaking Changes" sections in Pi's coding-agent changelog.
import re, sys
t = open(sys.argv[1]).read()
rel = re.findall(r'\n## \[([0-9.]+)\] - (\d{4}-\d{2}-\d{2})', t)
print("dated releases:", len(rel), "from", rel[-1], "to", rel[0])
secs = re.split(r'\n## \[', t)[1:]
n = ext = 0
for s in secs:
    m = re.search(r'### Breaking Changes\n(.*?)(\n### |\Z)', s, re.S)
    if m:
        n += 1
        if re.search(r'extension|registerTool|registerProvider|ExtensionAPI|ctx\.|pi\.on|tool_call|user_bash|SDK|custom provider', m.group(1), re.I):
            ext += 1
print("sections with Breaking Changes:", n, "; mentioning extension/SDK/provider surface (regex):", ext)
```

Output (`$G1/out/pi_changelog.out`):

```text
dated releases: 280 from ('0.10.0', '2025-11-25') to ('0.99.1', '2026-09-29')
sections with Breaking Changes: 47 ; mentioning extension/SDK/provider surface (regex): 26
```

### 5.11 Export-collision scan

`$G1/proto/collide.R`

```r
# G1: export-collision scan for every exported name proposed across the research tracks
# and for the final names. Sources: (a) exports of all installed packages (incl. base and
# recommended, dplyr, rlang, purrr), read from Meta/nsInfo.rds; (b) NAMESPACE files of the
# CRAN LLM packages extracted and MD5-verified by track 10 (mcptools 1.0.3, btw 1.5.0,
# ellmer 0.5.0, tidyllm 0.6.0, ...); (c) the r-universe exports search (CRAN, Bioconductor,
# r-universe), queried per name. Run: Rscript --vanilla collide.R
SP = Sys.getenv("SP"); W = Sys.getenv("W")

# ---- (a) installed packages -------------------------------------------------------------------
idx = list()
add = function(pkg, ex, src) if (length(ex)) idx[[length(idx) + 1L]] <<- data.frame(name = ex, pkg = pkg, src = src)
for (lib in .libPaths()) for (p in list.files(lib)) {
  f = file.path(lib, p, "Meta", "nsInfo.rds")
  if (p == "base") { add("base", ls(baseenv(), all.names = TRUE), "installed"); next }
  if (!file.exists(f)) next
  ni = tryCatch(readRDS(f), error = function(e) NULL)
  ex = ni$exports
  if (length(ni$exportPatterns)) ex = unique(c(ex, tryCatch(getNamespaceExports(p), error = function(e) character())))
  add(p, unique(unlist(ex)), "installed")
}
n_inst = length(unique(do.call(rbind, idx)$pkg))

# ---- (b) extracted CRAN LLM tarballs (track 10) ----------------------------------------------------
srcv = file.path(SP, "work", "track10", "srcv")
for (p in list.files(srcv)) {
  nsf = file.path(srcv, p, "NAMESPACE")
  if (!file.exists(nsf)) next
  ns = tryCatch(parseNamespaceFile(p, srcv), error = function(e) NULL)
  if (!is.null(ns)) add(paste0(p, "@src"), ns$exports, "cran-src")
}
idx = do.call(rbind, idx)
cat("export index:", nrow(idx), "names from", n_inst, "installed packages and",
    length(unique(idx$pkg[idx$src == "cran-src"])), "extracted CRAN LLM packages\n")
for (p in c("mcptools", "btw", "ellmer", "tidyllm")) cat(" ", p, sum(idx$pkg == paste0(p, "@src")), "exports\n")
for (p in c("dplyr", "rlang", "purrr", "base", "utils", "stats", "tools", "methods")) cat(" ", p, sum(idx$pkg == p), "exports\n")

# ---- candidates ---------------------------------------------------------------------------------------
proposed = c(
  # report 04 (System 1)
  "decide", "classify", "rate", "judge", "q_bool", "q_choice", "q_score", "s1_ask", "s1_ask_many", "s1_models",
  "state", "as_state", "prob", "confidence", "s1_meta", "as_decision", "is_true", "is_yes",
  # report 06 (sub-agents, MCP, codemode)
  "agent_run", "agent_parallel", "agent_chain", "tool_search", "tool_help", "tools_list", "tools", "mcp_call_many", "show_image",
  "mcp_status", "mcp_reconnect",
  # report 16 (MCP, skills, plugins)
  "mcp_servers", "mcp_add", "mcp_remove", "mcp_import", "mcp_connect", "mcp_disconnect", "mcp_tools", "mcp_call",
  "mcp_search", "mcp_describe", "mcp_resources", "mcp_read", "mcp_prompts", "mcp_prompt", "mcp_login", "mcp_logout",
  "mcp", "mcp_serve", "mcp_serve_stop", "mcp_bridge", "plugins_import_claude",
  # report 17 (artifacts)
  "artifact", "artifacts", "artifact_open", "artifact_stop", "artifact_screenshot", "artifact_export", "artifact_delete",
  "artifact_dir", "plot_image",
  # reports 03 / 09 (providers)
  "llm_model", "llm_models", "llm_stream", "llm_complete", "llm_stream_many", "llm_classify", "provider_register",
  "api_register", "provider_openai_compatible", "auth_resolve", "auth_login", "auth_logout", "auth_status",
  "catalog_refresh", "stream_chat", "sse_parser",
  # north star / 15
  "agent",
  # gptr_-prefixed proposals across 02, 05, 06, 08, 09, 11-20
  "gptr_agent", "gptr_agents", "gptr_tools", "gptr_steer", "gptr_retry_policy", "gptr_compaction_settings",
  "gptr_user_dir", "gptr_skill_install", "gptr_set", "gptr_plugins", "gptr_home", "gptr_diagnostics", "gptr_trust",
  "gptr_setup", "gptr_session", "gptr_rpc", "gptr_tool_result", "gptr_skills", "gptr_skill", "gptr_settings",
  "gptr_setting", "gptr_reload", "gptr_prompts", "gptr_prompt", "gptr_jsonl", "gptr_init", "gptr_handoff",
  "gptr_login", "gptr_logout", "gptr_usage", "gptr_accounts", "gptr_codex_status", "gptr_models", "gptr_models_update",
  "gptr_models_reset", "gptr_model", "gptr_register_provider", "gptr_register_model", "gptr_discover", "gptr_fork",
  "gptr_step", "gptr_return", "gptr_read", "gptr_write", "gptr_edit", "gptr_grep", "gptr_find", "gptr_ls",
  "gptr_describe", "gptr_env_snapshot", "gptr_workspace_summary", "gptr_cache_prune", "gptr_doc", "gptr_source",
  "gptr_blocks", "gptr_cache", "gptr_map", "gptr_parallel", "gptr_panel", "gptr_debate", "gptr_review", "gptr_wait",
  "gptr_cancel", "gptr_jobs", "gptr_last", "gptr_ui", "gptr_permissions", "gptr_classify", "gptr_capabilities",
  "gptr_hook", "gptr_config", "gptr_env", "gptr_providers", "gptr_mcp", "gptr_tool", "gptr_app")
final = c("gptr", "gptr_init", "gptr_config", "gptr_env", "gptr_login", "gptr_logout", "gptr_providers", "gptr_models",
  "gptr_trust", "gptr_skills", "gptr_agents", "gptr_plugins", "gptr_mcp", "gptr_mcp_add", "gptr_mcp_remove",
  "gptr_mcp_import", "gptr_mcp_serve", "gptr_mcp_stop", "gptr_doc", "gptr_source", "gptr_cache", "gptr_artifacts",
  "gptr_artifact_open", "gptr_artifact_stop", "gptr_artifact_export", "gptr_permissions", "gptr_risk", "gptr_usage",
  "gptr_last", "gptr_describe", "gptr_return", "gptr_prob", "gptr_packages", "gptr_tools",
  "gptr_step", "gptr_wait", "gptr_on", "gptr_steer", "gptr_cancel", "gptr_fork", "gptr_parallel", "gptr_map",
  "gptr_jobs", "gptr_sessions", "gptr_resume",
  "gptr_api_version", "gptr_api_features", "gptr_register", "gptr_registry", "gptr_reload", "gptr_check",
  "gptr_fake_provider", "gptr_tool_result", "gptr_spec",
  "gptr_tool", "gptr_provider", "gptr_adapter", "gptr_router", "gptr_model", "gptr_mcp_server", "gptr_skill",
  "gptr_prompt_template", "gptr_command", "gptr_hook", "gptr_policy", "gptr_context_block", "gptr_compactor",
  "gptr_doc_format", "gptr_artifact_type", "gptr_backend", "gptr_agent", "gptr_ui", "gptr_frontend", "gptr_setting",
  "gptr_prompt_section", "gptr_kind")
cands = unique(c(proposed, final))

# ---- (c) r-universe exports search ----------------------------------------------------------------------
cran = readRDS(file.path(SP, "work", "track10", "cran_db2.rds"))$Package
runiv = function(nm) {
  u = sprintf("https://r-universe.dev/api/search?q=exports:%s&limit=100", utils::URLencode(nm, reserved = TRUE))
  j = tryCatch(jsonlite::fromJSON(u, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(NA_character_)
  pk = unique(vapply(j$results, function(r) r$Package %||% "", ""))
  paste(sort(pk), collapse = " ")
}
`%||%` = function(a, b) if (is.null(a)) b else a
rows = lapply(cands, function(nm) {
  hit = unique(idx$pkg[idx$name == nm])
  ru = runiv(nm)
  ru_pk = if (is.na(ru) || !nzchar(ru)) character() else strsplit(ru, " ")[[1]]
  data.frame(name = nm, final = nm %in% final, local = paste(hit, collapse = " "),
             runiverse = paste(ru_pk, collapse = " "), n_cran = sum(ru_pk %in% cran),
             collides = length(hit) > 0 || length(ru_pk) > 0)
})
res = do.call(rbind, rows)
saveRDS(res, file.path(W, "out", "collide.rds"))
cat("\nPROPOSED NAMES THAT COLLIDE (local index or r-universe):\n")
col = res[res$collides & !startsWith(res$name, "gptr"), ]
for (i in seq_len(nrow(col))) cat(sprintf("  %-22s local: %-40s r-universe: %s\n", col$name[i],
  substr(col$local[i], 1, 40), substr(col$runiverse[i], 1, 70)))
cat("\nFREE unprefixed proposals:", paste(res$name[!res$collides & !startsWith(res$name, "gptr")], collapse = ", "), "\n")
cat("\ngptr_* names with any hit:", paste(res$name[res$collides & startsWith(res$name, "gptr")], collapse = ", "), "\n")
cat("final names checked:", sum(res$final), " colliding:", sum(res$final & res$collides), "\n")
cat("r-universe queries that failed:", sum(is.na(res$runiverse) | res$runiverse == "NA"), "\n")
```

Output (`$G1/out/collide.out`):

```text
Warning message:
In fun(libname, pkgname) :
  couldn't connect to display "/var/run/com.apple.launchd.CAfvrq8obw/org.xquartz:0"
export index: 41331 names from 592 installed packages and 37 extracted CRAN LLM packages
  mcptools 3 exports
  btw 67 exports
  ellmer 130 exports
  tidyllm 146 exports
  dplyr 284 exports
  rlang 441 exports
  purrr 184 exports
  base 1402 exports
  utils 233 exports
  stats 460 exports
  tools 123 exports
  methods 367 exports

PROPOSED NAMES THAT COLLIDE (local index or r-universe):
  decide                 local:                                          r-universe: assesslite countfitteR decideR ham justifier nimble
  classify               local: admisc                                   r-universe: Allspice BASiNETEntropy ClusterSignificance FuzzyLogit GMCM MLSeq Morp
  rate                   local:                                          r-universe: distr distrSim koma pop popEpi ratelimitr rmorie rmoriebricklayer scub
  state                  local:                                          r-universe: ReinforcementLearning SiMRiv VanillaICE dsge oligoClasses tcltk2 uniti
  as_state               local:                                          r-universe: naijR
  prob                   local:                                          r-universe: PhIPData RTDE copula crmPack cylcop deal distr exams.forge metadynmine
  confidence             local:                                          r-universe: Moonlight2R confcons gog psychmeta
  is_true                local: rlang                                    r-universe: fritools gtree mark ricu rlang tester
  tools_list             local:                                          r-universe: mcpr
  tools                  local:                                          r-universe: eppoFindeR
  show_image             local:                                          r-universe: fastai r2typ showimage
  mcp_connect            local: llm.api@src                              r-universe: 
  mcp_tools              local: LLMRagent@src llm.api@src mcptools@src   r-universe: LLMRagent mcptools
  mcp_call               local: llm.api@src                              r-universe: 
  mcp                    local: multcomp                                 r-universe: adehabitatHR lessSEM mcp multcomp quadrupen simctest
  mcp_serve              local:                                          r-universe: vellumplot
  artifact               local:                                          r-universe: icesTAF
  plot_image             local:                                          r-universe: matter plotfunctions rayimage spatialGE
  llm_model              local:                                          r-universe: metacheck
  llm_classify           local: mall@src                                 r-universe: mall
  api_register           local:                                          r-universe: metasurvey
  auth_login             local:                                          r-universe: ukbflow
  auth_logout            local:                                          r-universe: ukbflow
  auth_status            local:                                          r-universe: ukbflow
  agent                  local: LLMRagent@src llm.api@src                r-universe: LLMRagent rmorie villager

FREE unprefixed proposals: judge, q_bool, q_choice, q_score, s1_ask, s1_ask_many, s1_models, s1_meta, as_decision, is_yes, agent_run, agent_parallel, agent_chain, tool_search, tool_help, mcp_call_many, mcp_status, mcp_reconnect, mcp_servers, mcp_add, mcp_remove, mcp_import, mcp_disconnect, mcp_search, mcp_describe, mcp_resources, mcp_read, mcp_prompts, mcp_prompt, mcp_login, mcp_logout, mcp_serve_stop, mcp_bridge, plugins_import_claude, artifacts, artifact_open, artifact_stop, artifact_screenshot, artifact_export, artifact_delete, artifact_dir, llm_models, llm_stream, llm_complete, llm_stream_many, provider_register, provider_openai_compatible, auth_resolve, catalog_refresh, stream_chat, sse_parser 

gptr_* names with any hit:  
final names checked: 76  colliding: 0 
r-universe queries that failed: 0 
```

### 5.12 `R CMD check --as-cran` of the three packages

Command (per tarball): `_R_CHECK_SYSTEM_CLOCK_=false _R_CHECK_CRAN_INCOMING_=false _R_CHECK_CRAN_INCOMING_REMOTE_=false R_LIBS=$G1/lib R CMD check --as-cran --no-manual <tarball>`.

Verification pass (packages rebuilt from the sources embedded in this report): `gptr` Status: OK.
`gptrpanel` and `cohortdesc` first gave `Status: 1 WARNING` ("Undocumented code objects") because
their `man/` files were not embedded; after roxygenising `gptrpanel` (output identical to the
original `man/`) and adding `cohort.Rd` (section 5.4) both gave `Status: OK`. A copy of `gptrpanel`
with `inst/gptr/mcp.json` renamed to `.mcp.json` reproduced the hidden-files NOTE verbatim.

Excerpt of `$G1/check/gptr_0.99.9000.check.log` (final run):

```text
* using log directory '/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G1/check/gptr.Rcheck'
* using R version 4.4.3 (2025-02-28)
* using platform: aarch64-apple-darwin20
* using session charset: ASCII
* using options '--no-manual --as-cran'
* checking for hidden files and directories ... OK
* checking dependencies in R code ... OK
* checking R code for possible problems ... OK
Status: OK
```

Excerpt of `$G1/check/gptrpanel_0.1.0.check.log` (final run):

```text
* using log directory '/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G1/check/gptrpanel.Rcheck'
* using R version 4.4.3 (2025-02-28)
* using platform: aarch64-apple-darwin20
* using session charset: ASCII
* using options '--no-manual --as-cran'
* checking for hidden files and directories ... OK
* checking dependencies in R code ... OK
* checking R code for possible problems ... OK
* checking tests ...
  Running 'testthat.R'
 OK
Status: OK
```

Excerpt of `$G1/check/cohortdesc_0.1.0.check.log` (final run):

```text
* using log directory '/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G1/check/cohortdesc.Rcheck'
* using R version 4.4.3 (2025-02-28)
* using platform: aarch64-apple-darwin20
* using session charset: ASCII
* using options '--no-manual --as-cran'
* checking for hidden files and directories ... OK
* checking dependencies in R code ... OK
* checking R code for possible problems ... OK
Status: OK
```

NOTEs of the first run (before the fixes described in section 2.8), captured verbatim:

```text
=== gptr_0.99.9000.check.log
* checking for future file timestamps ... NOTE
unable to verify current time
* checking dependencies in R code ... NOTE
Namespace in Imports field not imported from: 'tools'
  All declared Imports should be used.
* checking R code for possible problems ... NOTE
make_tool_fn : f: no visible binding for global variable 'TOOL_REQ'
make_tool_fn : f: no visible binding for global variable 'TOOL_NAME'
make_tool_fn : f: no visible binding for global variable 'TOOL'
Undefined global functions or variables:
  TOOL TOOL_NAME TOOL_REQ
=== gptrpanel_0.1.0.check.log
* checking for hidden files and directories ... NOTE
Found the following hidden files and directories:
  inst/gptr/.mcp.json
These were most likely included in error. See section 'Package
structure' in the 'Writing R Extensions' manual.
* checking for future file timestamps ... NOTE
unable to verify current time
```

The parse error behind pitfall 1 (section 2.8), from `roxygen2::roxygenise()` on the first draft:

```text
Error in `load_all()`:
! Failed to load 'R/check.R'
Caused by error in `parse()`:
! At 'R/check.R:8:24': unexpected '='
7:   old = the$registry
8:   on.exit(the$registry =
                          ^
```

---

## 6. CRAN and cross-platform (Windows) considerations

- **Checks.** Host prototype and both plugin packages: `R CMD check --as-cran --no-manual`
  `Status: OK` with `_R_CHECK_CRAN_INCOMING_=false`, `_R_CHECK_CRAN_INCOMING_REMOTE_=false`,
  `_R_CHECK_SYSTEM_CLOCK_=false` (no network in this sandbox; the clock check otherwise gave
  "unable to verify current time"). R-devel, Windows and Linux checks were not run.
- **Hidden files.** `inst/gptr/.mcp.json` draws a NOTE (VERIFIED); packages use `mcp.json`. The same
  applies to `.gptr-plugin/` directories: inside an R package use `inst/gptr/plugin.json`.
- **No `:::`**: plugin factories are exported and resolved with `getExportedValue()`; callr children
  use `package = "gptr"` (report 17 §4.2). The prototype packages contain no `:::` (VERIFIED test J).
- **`unlockBinding()`** is avoided (R CMD check lists it among possibly unsafe calls); partial locking
  uses `lockBinding()` per name. (VERIFIED: on R 4.4.3, `tools:::.check_package_code_tampers()` run
  on a scratch package flags `unlockBinding("x", e)` and not `lockBinding("y", e)`, and
  `tools:::.check_packages` prints that list under "Found the following possibly unsafe calls:";
  the lockBinding pattern itself is VERIFIED to pass `--as-cran`.)
- **Global state.** The registry lives in a package-level environment (allowed: configuration and
  registries, INFRA-15); sessions hold run state; no writes to `.GlobalEnv`.
- **Delayed S3 registration** (`S3method(gptr::gptr_describe, cls)`) is the CRAN-clean way for
  domain packages to support gptr from Suggests (VERIFIED on R 4.4.3; requires R >= 3.6.0).
- **Examples.** Every exported constructor needs an example that runs offline; the fake provider makes
  that possible (the prototype has no examples: "checking examples ... NONE").
- **Windows (not tested).** `setHook(packageEvent())`, `system.file()`, `dir.exists()` scanning,
  `lockBinding()` and `getExportedValue()` are platform-independent base R (LIKELY). Risks: network
  library paths on managed Windows machines can make the installed-package scan an order of
  magnitude slower (report 05 §4.10 caveat); plugin names are case-insensitive on NTFS, so
  registry keys for directory plugins should be compared case-insensitively on Windows; manifests
  must use forward slashes; `unloadNamespace()` of a package with a loaded DLL can fail on Windows
  while the DLL is in use (LIKELY), in which case the `onUnload` hook does not fire and the user must
  restart R after reinstalling a compiled plugin.

---

## 7. Risks and open questions

### Risks

1. **Plugins are arbitrary code in the user's session.** Trust gating, opt-in and fail-closed
   policies are the only mitigations; there is no sandbox (reports 05, 06, 18).
2. **Lazy activation can surprise.** A plugin's hook does not exist until something it provides is
   used; plugins that must observe every event need `activation: "eager"`. A manifest that
   under-declares `provides` silently loses hooks until another provided capability triggers
   activation; `gptr_check()` catches this in the plugin's own tests, not at the user's site.
3. **API breadth.** 76 exports and 22 registry kinds are a large surface to keep stable. The versioning
   policy and conformance suite are the defence; the alternative (Pi's unversioned churn) is worse
   for a CRAN package with CRAN plugins.
4. **Process-level registry vs per-session views.** Factories run once per R process, so extension
   `state` is shared across sessions; per-session state must use `ctx` or session entries. A plugin
   author who keeps session data in `gptr$state` will leak it across sessions.
5. **Dispatch cost grows with hooks.** 100 `tool_result` hooks raised a trivial run from 3-6 ms to
   20-39 ms; the implementation must index hooks by event and avoid per-emit resolution.
6. **Reverse-suggests coupling.** CRAN checks reverse suggests; a MAJOR API change can break CRAN
   plugins' checks and triggers the 2-week notice duty.
7. **Timings were taken under load averages up to 140** from parallel agents; absolute numbers are
   inflated, relative comparisons were stable across two runs. A verification re-run at load
   average 5 confirmed the orderings, with absolute times about 1.1-3.3x lower (see sections 2.3,
   2.4).
8. Nothing was run on Windows, Linux, RStudio, Positron or Jupyter.

### Open questions

1. Should project-level plugin enabling be allowed at all (it runs code after one trust decision),
   or only user-level and call-level?
2. Is `activation: "lazy"` the right default for plugins that register hooks only (no tools or
   commands)? Proposal: hook-only plugins activate at the first dispatch of a provided event
   (prototyped), which is session start for `session_start` hooks.
3. Should `gptr_register()` at top level persist into user settings, or stay per R session
   (prototype: per R session; persistence through `gptr_config(plugins = )`)?
4. Should spec constructors accept a compact R schema shorthand (`list(path = "string",
   n = "integer?")`) to cut plugin-author friction and declaration tokens? Not measured.
5. How many kinds should v1 actually ship with registration support? Proposal: all 22 in the
   contract, with `artifact_type`, `frontend` and custom `kind` marked "experimental" in
   `gptr_api_features()` for 1.0.
6. Does `ctx$decide()` (System 1 inside plugins, report 05 open question) belong in API 1.0? It is
   cheap and useful for routers and permission reviewers.
7. Must hook handler exceptions for notify events be surfaced to the user interactively, or only
   in `gptr_registry(diagnostics = TRUE)`?

---

## 8. Sources

Local (read first-hand):
- `dev/spec/00-vision-brief.md` (REQ-29, REQ-41, REQ-42), `dev/spec/01-decision-register.md`
  (S-1, S-8..S-12; D-02, D-16, D-25, D-28), `dev/spec/02-north-star-examples.md` (§6, §9, §10),
  `dev/plan/00-conventions.md`.
- Research reports: 05 §2.1-2.10, §3.1-3.4, §4.3-4.15, §5.4, §5.9; 06 §4.2-4.5; 16 §4.1-4.10;
  10a §3.7 and INFRA-02/10/11/12/16/17/24; 15 §4.2-4.4; 17 §4.1-4.2; 14 §4.1-4.3; 18 §4.1, §4.7,
  §4.9; 12 §2.C6, §3.9-3.10; 02 §4.1-4.5; 03 §4.2-4.3; 09 §4.2-4.3; 04 §4.2-4.3; 20 §4.1, §4.6;
  10 §2.10; 13 (Imports and hidden-directory NOTE); 19 §4.2, §4.4; 21 §2.8; digest `00-digest.md`.
- Pi: `$CA/docs/extensions.md`, `$CA/docs/sdk.md`, `$CA/docs/packages.md`,
  `$CA/src/core/extensions/{index,loader,runner,types}.ts`, `$CA/src/extensions/index.ts`,
  `$CA/CHANGELOG.md`, `$CA/src/core/pi-manifest.ts`.
- Installed R documentation: R6 2.6.1 `R6Class.Rd`; tools `check_packages_in_dir.Rd`.
- Track 10 scratch: `scratchpad/work/track10/srcv/*/NAMESPACE` (37 CRAN LLM packages),
  `cran_db2.rds` (CRAN package db, 2026-09-29); `scratchpad/work/track10/rlib` (btw 1.5.0,
  ellmer 0.5.0 used only to dump btw's tool declarations).

Web (fetched 2026-09-29):
- [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html) (revision 6875):
  API-change notice and reverse-suggests checking.
- [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-devel/R-exts.html) (registering S3
  methods; delayed registration for Suggests; read through a summarising fetch. The R 3.6.0 date is
  now confirmed locally in `R.home("doc")/NEWS.3`.)
- [r-universe exports search](https://r-universe.dev/api/search?q=exports:mcp_tools) (queried per name,
  section 5.11).
- [check_packages_in_dir (R manual)](https://stat.ethz.ch/R-manual/R-devel/library/tools/html/check_packages_in_dir.html),
  [r-devel/recheck](https://github.com/r-devel/recheck), [R Packages (2e), Releasing to CRAN](https://r-pkgs.org/release.html)
  (context for reverse-dependency practice; no load-bearing claim rests on them).

---

## Verification log

Adversarial fact-check, 2026-09-29, R 4.4.3 macOS arm64, `Rscript --vanilla`, load average 5-9.
Method: every file embedded in section 5 was extracted from this report by a script (45 blocks) and
diffed against the original scratch (all identical). The three packages were rebuilt and installed
from the extracted sources into a fresh private library (`scratchpad/work/verify-G1/lib`), and every
prototype was re-run from there. Pi claims were re-read in the clone at `1b347794`. Web: the CRAN
policy page was fetched with curl. No model API was called.

| # | Claim | Verdict | Source / evidence |
|---|---|---|---|
| 1 | Registry and SDK end-to-end checks pass 59/59 | VERIFIED | `test_registry.R` re-run; output byte-identical to 5.2 |
| 2 | Third-party plugin checks pass 21/21 (lazy activation, delayed S3, unload, no `:::`) | VERIFIED | `test_plugin.R` re-run; byte-identical to 5.5 |
| 3 | 9 built-in extensions, 22 kinds, 42 records, 23 spec constructors | VERIFIED, clarified | `gptr_registry()`: 42 records = 21 kind records + 21 capability records over 13 kinds; the 23 constructors are all exported. `artifact_type` is never registered or exercised; `mcp_server` is data only (exec. summary 1) |
| 4 | Locked API object: `gptr$state$n = 1` works, method replacement and new bindings refused, unknown method gives `gptr_error_api_missing` | VERIFIED | `lock_state.R` re-run; byte-identical |
| 5 | Env-of-closures faster than R6 and S3 per call and per creation; serialised 2,991 vs 14,390 bytes | VERIFIED (ratios), CORRECTED (absolutes) | `bench_objsys.R` at load 5: 0.70 / 1.64 / 1.48 µs, creation 1.7 vs 23-28 µs; sizes exact. Report microseconds are load-inflated 2-3x (sections 1.4, 2.3) |
| 6 | R6 is a hard dependency of httr2, processx, callr; portable R6 inherits across packages | VERIFIED | `tools::package_dependencies()` on the installed library (direct Imports of all three); installed R6 2.6.1 `R6Class.Rd` sentence found |
| 7 | Start-up cost for 0/10/100 plugins; lazy cheaper than eager; 42/72/342 records | VERIFIED (ordering, counts); absolutes lower at low load | `bench_startup.R`, `bench_lazy.R` re-run: 100 plugins lazy 7, eager 26, directory 84 ms; toy package lazy 9-10 vs eager 10-12 ms |
| 8 | `loadNamespace("Seurat")` costs 4.2-5.0 s | CORRECTED | The report's own output shows 4.172 s (no 5.0 s run embedded). Four verification runs: 1.886, 2.613, 2.080, 2.082 s (Seurat 5.4.0, load 5-7). Now reads "about 2-4 s" |
| 9 | TRE bounded repetition `{0,63}` dominated registration time; `perl = TRUE` fixes it | VERIFIED | microbenchmark: 16.0 ms (TRE) vs 0.68 ms (PCRE) per 100 calls. Side finding: prototype `dispatch()` matcher `grepl()` lacks `perl = TRUE` |
| 10 | btw 1.5.0: 31 tools, 46,236 bytes; direct 10,156 vs `r` 1,129 vs deferred 55 o200k tokens; skill 63, agent 19; composition 1,532 vs 109 | VERIFIED (numbers); representativeness UNCERTAIN | `dump_btw_tools.R` re-dump byte-identical JSON; `tokens.R` output byte-identical. Caveat added: the signature line drops parameter descriptions, enums and nested schemas, and o200k is not Claude's tokenizer (sections 1.9, 2.5) |
| 11 | Pi: no extension API version; peer dependencies `"*"` | VERIFIED | `docs/packages.md:88`; no "version" string in `src/core/extensions/*.ts` or `src/core/pi-manifest.ts` |
| 12 | Pi changelog: 280 dated releases 2025-11-25 to 2026-09-29, 47 Breaking Changes sections, 26 on the extension/SDK/provider surface; cited examples exist | VERIFIED | `pi_changelog.py` re-run on `$CA/CHANGELOG.md`; `TurnEndEvent`, `TranscriptContext`, `user_bash` fails closed at lines 143, 202, 204 |
| 13 | Pi factory is transactional (commit or discard); action methods throw until bound | VERIFIED | `loader.ts` `initializeExtension()` (`load.commit()` / `load.discard()`), `createExtensionRuntime()` "Extension runtime not initialized" stubs |
| 14 | Pi built-ins `codemode`, `tool-search`, `mcp` (replaceable) and `llama.cpp` with `builtin: true`, disabled by `-builtin:<name>` | VERIFIED, wording fixed | `src/extensions/index.ts:7-14`; `docs/sdk.md:112` says a `builtin: true` entry "is not an inline extension" but a `builtin:<name>` extension (section 2.1 reworded) |
| 15 | Pi tool exposure `direct / model-only / codemode / deferred / hidden` | VERIFIED | `docs/extensions.md` "Tool exposure" |
| 16 | Pi has 41 events; gptr keeps Pi names and adds nine gptr-specific events | VERIFIED; catalogue gap added | Regex over `types.ts` `on(event: ...)` overloads: 41. The gptr table covers 24, names 2 as not ported, omits 15 (listed in 3.2). Prototype also emits an uncatalogued `compaction` event |
| 17 | `permission_request` handler error = deny (fail closed) | UNCERTAIN (design only) | `ext-events.R`: dispatch kind `first_decision` uses `safe()`, which skips failing handlers; the event is never emitted. Marked in 3.1 and 3.2 |
| 18 | 76 final names (gptr + 75 `gptr_*`) collide with nothing; 41,331 exports / 592 packages; 25 unprefixed proposals collide, 51 free | VERIFIED | `collide.R` re-run including every r-universe query; output identical apart from the X11 warning line; counts recomputed from `collide.rds` |
| 19 | CRAN policy rev. 6875: at least 2 weeks' notice for API changes; check reverse strong deps + reverse suggests with `which = "most"` | VERIFIED | curl of `cran.r-project.org/web/packages/policies.html`: "Revision: 6875"; both sentences present verbatim |
| 20 | `check_packages_in_dir(reverse =)` defaults to Depends/Imports/LinkingTo; `"most"` adds Suggests (not Enhances) | VERIFIED | installed `tools` `check_packages_in_dir.Rd` |
| 21 | Three packages pass `R CMD check --as-cran` with Status: OK | VERIFIED, reproducibility gap fixed | `gptr` OK as embedded. The plugins gave 1 WARNING each until `gptrpanel` was roxygenised and `cohort.Rd` (not embedded; now added to 5.4) restored, then both OK. Reproduce block updated |
| 22 | `inst/gptr/.mcp.json` draws a hidden-files NOTE | VERIFIED | `R CMD check --as-cran` of a `.mcp.json` variant: NOTE text identical to 5.12 |
| 23 | `unlockBinding()` is listed among "possibly unsafe calls" | VERIFIED (was LIKELY) | `tools:::.check_package_code_tampers()` flags it on a scratch package; `.check_packages` prints that heading |
| 24 | Delayed `S3method(pkg::gen, cls)` registration since R 3.6.0 | VERIFIED (was LIKELY) | `R.home("doc")/NEWS.3`, "CHANGES IN R 3.6.0" |
| 25 | Pitfalls: `on.exit(the$stack = ...)` is a parse error; `package_version("2")` invalid; `environment<-` closures give "no visible binding" | VERIFIED | `parse()`: "unexpected '='"; "invalid version specification '2'"; `codetools::checkUsage()` flags `TOOL` only in the `environment<-` variant |
| 26 | `Config/gptr/plugin` and `Config/gptr/api` survive installation; `inst/gptr` installs to `<lib>/<pkg>/gptr` | VERIFIED | `packageDescription("gptrpanel")`, `system.file("gptr", package = "gptrpanel")` |
| 27 | A nested `gptr()` in model-written R code creates a linked child session (depth + 1, usage rolled up) | VERIFIED (new test) | Not in the original checks. Fake-provider run: inner `depth` 1, `parent` identical to the outer session, 51 tokens rolled into `usage$children` |

Not re-verified: Windows or Linux behaviour (section 6, still LIKELY); the first-run `R CMD check`
NOTE texts for `gptr` (the logs were overwritten by the final run; the underlying behaviours are
verified in rows 22 and 25); report-to-report citations (05, 10, 16, 20).
