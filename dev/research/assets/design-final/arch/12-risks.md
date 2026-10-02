
---

## 13. Risks and mitigations

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| A CRAN reviewer objects to evaluating model code in the caller's environment or to document writes | medium / high | every evaluation and write is user-initiated and consented; examples use the fake provider and `envir = new.env()`; a "Security considerations" help page; precedents (btw, aisdk) cited in cran-comments [13 §1] |
| In-process evaluation cannot be sandboxed; `auto` can damage the session or files | high / high | `manual` default; modes, rules, critical and secret guards, protect-size escalation; checkpoints and rewind; documented "not a security boundary" [18, G6, G7] |
| Copy-safety regressions from future code or R versions (one stray quosure, `match.arg()`, list or closure brings back multi-GB copies) | medium / high | rules R1-R10 (§6.4); fresh-process tracemem suite over every entry point incl. function-frame homes on R-release and R-devel; review checklist in every plan touching user objects [G3 fact-check] |
| Values that capture environments (lm terms, closures) keep a function-frame home alive | medium / low | inherent to R; documented; by-name designation for kept homes |
| Interrupt menu, background pumping and readline behaviour unverified in RStudio, Positron, Jupyter, Rgui and Windows consoles | medium / medium | abort-only fallback; UI abstraction; background is experimental with a support matrix; manual test checklist in P14 and P21 [02 §7, 18 §7, G3] |
| Windows untested (processx shims, CTRL+BREAK, rename under antivirus locks, code pages) | high / high | Windows CI from P04; G5 process engine with `cmd.exe /d /c call` and metacharacter refusal; atomic-write retries; no free text on argv; win-builder before submission [13 §6, 16 §6, G5] |
| Claude-plan route falls foul of Anthropic's terms or name-use rule | medium / medium | experimental, opt-in with a notice; unmodified CLI; no credential handling; neutral provider id; the maintainer asks Anthropic before advertising it [07 §2.18] |
| Provider API drift (thinking controls, betas for inline tools and mid-conversation system messages, new finish reasons) | high / medium | capabilities per model in the catalog with fallbacks and logged cost; wire fixtures; the live suite before each release; unknown enum values map to errors with the raw value [G4 §7, 09] |
| MCP spec churn (two breaking eras in eight months) | high / medium | thin protocol layer; era probe and cache; fixtures per era copied from the spec; the versioning page re-checked at each release [16 §7.1] |
| Token estimates are proxies (Claude and Gemini tokenizers are private) | medium / low | provider usage is authoritative; EWMA multiplier; the live calibration mode refits priors [G2] |
| Four-tool default underperforms on models that prefer dedicated search tools | medium / medium | per-model presets chosen by the benchmark; `tools = "+grep"` per call [20] |
| Plan hand-off surprises a user (a later call sees an earlier plan) | low / low | once only, same environment and process, one hour; printed notice; `<plan>` visible in `/context`; `options(gptr.plan_handoff = FALSE)` |
| `{identifier}` interpolation touches LaTeX or prose | low / low | only bound atomic values in literal prompts; `{{ }}` escapes; option off switch; the interpolated prompt is echoed |
| Inline sub-agents mutate reference objects (environments, data.table `:=`, Seurat internals) through the overlay | medium / medium | classifier flags reference mutation at level 2 (denied in parallel runs); `worker` backend for isolation; documented [15 §7] |
| A long R tool stalls other agents' streams; providers drop idle streams during the pause menu | high / low | streams buffer and resume; `continue` retries dropped requests; heavy compute goes to `worker` [15, 18] |
| Nested calls in loops re-run live on re-source | medium / low | S1 cache covers decisions; `GPTR_REPLAY=replay` proves no calls; cassettes are a specified v1.x plugin |
| Session files and caches grow (images, branches from stale knitr copies) | medium / low | images stored once; spill files; compaction checkpoints; `gptr_cache("prune")`; branch pruning command in v1.x [G3 risks] |
| Pid reuse after a crash makes a stale session lock look alive | low / low | lock timeout and a `force` option on resume [G3 risks] |
| Self-maintained providers lag the breadth of other ecosystems | medium / medium | data-driven compat table; adapters as plugins; the catalog refresh [09 §4] |
| Scope: 114 files, 25 plans, 62 exports for a small team | medium / medium | P-A's milestone order (every milestone ships tested software offline); explicit deferrals (§1.3); previews only as v1.x plugins; the layering test prevents coupling drift |

---

## Appendix A. Checks run for this document

All in `scratchpad/work/design/final/`, `Rscript --vanilla`, R 4.4.3, macOS.

1. **`capture_check.R`** (D-07). A wrapper `h(d)` forwards a 40 MB vector into a gptr-like `g(...)`; after it
   returns, `big[1] = 0` is traced. Output: `rlang_enquos -> COPY`, `base_dotelt_leaf -> in place`,
   `base_substitute -> in place`. Confirms G3 p5b/p5i: quosure capture pins the forwarding frame.
2. **`frame_hold_check.R`** (rule R2). A function stores a reference to its own frame in a package-level
   environment in four ways, then the caller edits its argument. Output: `weakref_key -> COPY`,
   `address_string -> in place`, `env_binding_reset -> in place`, `list_then_drop -> COPY`.
3. **`prompt/measure.R`, `prompt/measure2.R`** (§7, §12). rtiktoken 0.0.7 `o200k_base` counts of every
   section and of the tool arrays as sent: preamble 75, tools 83/100, rules 241, r_session 443, r_performance
   127, documents 186, artifacts 124, system1 123, modes 84, context 106, skills (2 built-ins) 152, mcp header
   87, tools array 675 (+145 with `ask`), `r` tool 198, minimal T0 624, `<environment>` 76, `<workspace>` (six
   objects) 122, manual mode 50, plan mode 125.

## Appendix B. Disposition of the judges' grafts and fatal flaws

| Item (judge) | Disposition |
|---|---|
| `$value` by name (all three) | adopted with G3's three-way policy (§5.1) |
| Cassettes (J-req) / HMAC + trust (J-cran) / defer (J-impl) | v1.x plugin with J-cran's security rules and content-fingerprint keys (§1.3) |
| Gateway namespace `gptr$` (J-req, J-impl) | adopted; `$` has no side effects (§4.2) |
| Teams and fan-outs as sessions (J-req) | adopted (§4.1.6) |
| Polyglot bridge set and interpreter kind (J-req, J-cran G5 engine) | adopted (§4.2, §6.7, §11.1) |
| Trimmed `ask`, describers, token ledger (J-req, J-impl) | adopted (§7.2, §7.5, §5.5) |
| codetools layering test (all three) | adopted (§2.2) |
| Extra kinds, API sugar, JSONL sink (J-req) | adopted (§11.1) |
| Overlay fork, `gptr_steer/cancel/wait` (J-req, J-impl) | adopted (§4.3) |
| Codex app-server in v1.x behind a probe (J-req, J-cran) | adopted (§1.3) |
| Artifacts via `write` + `gptr$app()`, working copy + vNNN (J-req) | adopted (§6.15) |
| Non-interactive ask stops with a classed error (J-req, J-impl) | adopted (§6.8.5) |
| Choices that cost tokens, offline budget test, tokens column (J-req) | adopted (§12) |
| System 1 on a piped session with `uncertain = function` (J-req) | adopted (§4.1.5) |
| G7 pre-images and rewind (J-req, J-cran) | adopted (§6.16) |
| Gap-based TTL, class-aware estimator, 4,000-token `r` cap, read line numbers off, 150-token describers (J-req) | adopted (§6.11, §12) |
| `gptr_trust()` separate from write consent (J-cran) | adopted (§6.10) |
| Egress acknowledgement (J-cran) | adopted (§6.10) |
| cli format-string rule and test (J-cran) | adopted (§6.3 C1) |
| Secret-free child environments incl. `R_ENVIRON_USER` (J-cran) | adopted (§6.5) |
| G5 process engine (J-cran, J-impl) | adopted (§6.7) |
| CI matrix (J-cran) | adopted (§3.5) |
| Evaluator shim when `gptr` is not attached (J-cran) | adopted (§4.2) |
| Weak references for session indexes (J-cran, J-impl) | adopted and extended to rule R2 (§6.4) |
| Risk tables as data (J-cran) | adopted (§3.3) |
| No `r` timeout with a human present (J-cran) | adopted (§6.12) |
| Sign in with ChatGPT opt-in in v1 (J-req) vs gated (J-cran) vs v1.x (J-impl) | v1.x plugin; openssl stays in Suggests (§1.3) |
| INFRA acceptance table (J-impl) | adopted (§6.18) |
| `allow_runs` re-entrancy (J-impl) | adopted (§2.3, §6.1) |
| Pure L2 loop with injected stream (J-impl) | adopted (§2.1) |
| Ported report-02 and Pi oracles; quantitative reactor tests; `gptr_prompt()` (J-impl) | adopted (§3.4, §6.18, §4.3) |
| P-A's milestone M1 and deferral table (J-impl) | adopted (`05-plan-decomposition.md`, §1.3) |
| Background mode: v1 experimental (J-req) vs defer (J-cran, J-impl) | v1 experimental, own plan (§0 item 4) |
| rlang capture (all three) | overturned by G3 and `[final/capture_check.R]`: base-R capture (§0 item 1) |
| P-A flaws: value held, Codex without live R, no console pipe-steering, re-entrancy, trust | fixed (§5.1, §8.3, §6.2, §2.3, §6.10) |
| P-B flaws: groups, 50 KB cap, preview defaults, `processx::run()`/shim refusal | fixed (§4.1.6, §12.2, §1.3, §6.7) |
| P-C flaws: binding guard, 1 GB `mget()` undo, hidden cassette code, `$<-` vs grammar, plan order | fixed (§6.4 R5-R6, §6.16, §1.3, §5.1, plans) |
| All: cli injection, `~/.Renviron` re-injection | fixed (§6.3, §6.5) |
