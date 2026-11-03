# 1.0.1 fixes, lane D: models and discovery (#106)

Branch `claude/fix-D`, cut from `04dca16a`. Decisions D-325 to D-328. Every medium finding of the
lane is fixed. Lows are fixed where the fix was small; the others are deferred or rejected below.
Each fix had a test written first and seen failing, except the refactors and docs commits.
`codex/default` stays on the shipped list (ff0be9d5).

## Fixed

| Commit | Fix | Findings | Tests |
| --- | --- | --- | --- |
| `8fa21f60` | `discover()` callbacks, which include the claude and codex CLI catalogs, run only on explicit refresh. Before use, only the bounded native listings run. The Claude catalog wait pumps the reactor (D-325). | review: the Claude CLI catalog wait blocks R and the reactor for up to 30 s (medium) | test-cli-discovery.R: "the Claude catalog waits through the reactor and CLI catalogs run only on refresh" |
| `21f8d6fa` | Claude discovery registers the first `claude-` id among a selection's `value` and `resolvedModel`, never an alias (D-326). | review: alias ids are registered, against 03 section 8.4 (medium). Live: CLI aliases appear as separate rows (low, part 2) | test-cli-discovery.R: "Claude discovery uses only initialize and keeps full ids, never selection aliases" |
| `fa783b16` | `pcli_codex_why()` reads a relayed HTTP error body with `retry_body_error()`. The console and sub-agent lines now show "The 'gpt-6.1-sol' model is not supported ...". | live: Codex errors shown as raw cut-off JSON (2 x medium) | test-cli-codex.R: "a provider error body Codex relays shows the service's message" |
| `fd1e2bb1` | A web search whose `item.started` has no query opens its row at `item.completed`. | live: `codex_web_search {"query":""}` rows (medium) | test-cli-codex.R: "a Codex web search row shows the query Codex reports when the search completes" |
| `02e655eb` | `$history` previews and estimates a message without text blocks by its context text (D-328). | review: the `gptr_runtime` note is a blank 0-token row (low) | test-session-history-display.R: "a context-only message previews and estimates its context text" |
| `86e4f213` | Listing cells use `format(scientific = FALSE)`. | live: context column printed as `2e+05` (low) | test-utils-text.R: "listings print numbers in fixed notation" |
| `41e4c1b0` | `print.gptr_listing()` wraps the footer with `strwrap()` to the console width. | live: footer not wrapped (low, part 1) | test-utils-text.R: "listing footers wrap at word boundaries to the console width" |
| `5e7aa925` | The footer has one clause, "listing failed for p (why), ...; prior catalog kept", for listed providers only, and counts the rows of the unfiltered listing. | live: footer piles up failures; its model count differs from the rows (low, parts 2-3) | test-provider-model-discovery.R: "the listing footer names failed listings of listed providers once, with the row count" |
| `4d9898f6` | gptr's own listing conditions carry a short `reason` (no answer within n s, could not connect, invalid response, ...). The footer shows it; other condition text stays hidden. | live: every failure without a status reads "listing unavailable" (low) | test-provider-model-discovery.R: "a failed listing without an HTTP status names gptr's own reason, never other text" |
| `ff4c542c` | A listing's egress question says that no prompt is sent, and that the answer also covers prompts with automatic context (D-327). | live: listing question says "gptr sends your prompts" (low) | test-provider-model-discovery.R: "the egress question of a listing says no prompt is sent and what consent covers" |
| `4007c55c` | The TypeSafe listing API applies to `typesafe` only, not to the `openrouter-jev` and `vercel-jev` gateways. | review: gateway inventories always fail (low) | test-provider-model-discovery.R: "gateways serving the TypeSafe protocol have no TypeSafe model listing" |
| `faef2076` | `catalog_discover()` reads `catalog_get()$models` once. | review: catalog key rebuilt per unnamed record (low) | test-provider-model-discovery.R: "discovery reads the catalog once, not once per unnamed record" |
| `24dda034` | `provider_discoverer()` and the `gptr_native_models` marker are deleted; lmstudio, llamacpp and vllm list through their API. | review: unreachable callback body (low, part 1) | existing vllm credential-retry test |
| `9614c87d` | The unknown-model hint and `catalog_inventory()` share `catalog_listable()`. The regenerated `gptr_models.Rd` also carries D-325. | review: the hint recommends a refresh that does nothing (low) | test-catalog-models.R: "an unknown id points to explicit provider discovery without doing I/O" (+ brx case) |
| `535706c1` | Availability compares Ollama ids through `catalog_ollama_tag()`. | live: `ollama/clef-flash` unlisted next to `clef-flash:latest` (low, part 1) | test-catalog-models.R: "an untagged Ollama catalog name is advertised when its :latest tag is installed" |
| `196567c7` | New test that spies on `catalog_inventory()` from `gateway_guards()`, `run_model_ready()` and `model_prepare()`. A mutation (no `prepare` in `run_model_ready()`) fails it. | review: before-use wiring untested (low) | test-provider-model-discovery.R: "run, gateway and model preparation each inventory with the replay override" |
| `caa8a840` | `pcli_codex_build()` writes the model argument together with the request id. | review: selected model from several sources (low, part 1) | test-cli-codex.R: "build() records a request's model argument with its id, before it can fail" |
| `86c5918c` | `pcli_claude_quiet` names the three `CLAUDE_CODE_*` variables once. `console_status_line()` escapes once. | review: same finding (low, parts 2-3) | existing cli and console suites |
| `3c8cd61b` | `?gptr_egress` and `?gptr_security` describe provider listings. `gptr_models()` stays level 0, with a new reason (D-327, amends D-300). | review: network statements and D-300 rationale are false (low) | none (docs) |
| `1c0c12aa` | The `gptr_runtime` rule moves to 04 section 7.6, the kind joins section 4.1.1, and the `run_model_ready()` comment names the inventory (D-328). | review: contract placement (low, parts a-c) | none (docs) |

## Follow-up after verification

The verifier of the first pass (head `c1975ac4`) reported five problems. Four are fixed; the fifth
is a note for the coordinator.

| Commit | Fix | Problem | Tests |
| --- | --- | --- | --- |
| `9a70c441` | The new `?gptr_egress` sentence is wrapped at 100 columns (`gptr_egress.Rd` regenerated). The first pass wrongly claimed a clean lint. | changed file fails `line_length_linter` (medium) | `isolated-check.R lint` over every changed R and test file now exits 0 |
| `3c358baf` | `pcli_claude_models()` takes the id with `Find()`, so a selection with neither a string `value` nor `resolvedModel` is skipped rather than failing the whole listing. | `startsWith(NULL)` error loses Claude discovery (low) | test-cli-discovery.R: "Claude discovery uses only initialize ..." gains a record with no id |
| `e2a078bd` | `?gptr_provider` says a `discover()` callback runs only on `gptr_models(provider = , refresh = TRUE)`, after consent. | stale "before first use" text (low) | none (docs; Rd regenerated) |
| `a4d0c71a` | The `default` row of `claude-cli` and `codex` takes the availability of the full id it runs (`pcli_default_model()`), recorded under D-326; 04 section 6.2 and `?gptr_models` amended. `codex/default` was also `unlisted` after a refresh before this. | `claude-cli/default` reads `unlisted` after refresh (low) | test-cli-discovery.R: "a CLI route's default row is advertised when the full id it runs is" |

Note for the coordinator (verifier problem 5): D-325 changes documented extension behaviour. A
user's `gptr_provider(discover = )` callback, like the `claude` and `codex` catalogs, no longer runs
before first use; it runs only on `gptr_models(provider = , refresh = TRUE)`. This needs a NEWS
1.0.1 bullet, together with D-326 (Claude discovery keeps full ids; a CLI `default` row is listed as
the id it runs) and D-327 (listings in `?gptr_egress` and `?gptr_security`). This lane does not
edit NEWS.md.

## Validation

- Focused filters, each green after its fix: `^cli-discovery$`, `^cli-codex$`, `^provider-model-discovery$`,
  `^catalog-models$`, `^utils-text$`, `^session-history-display$`, `^gptr-config$`, `^s1-.*`, `^arch-layers$`.
- Broad filter `^(cli-|catalog|provider|agent-run|agent-loop|s1-|session-|console-|gptr-config|gptr-capture|utils-text|listing|arch|doc-jupyter|subagent)`:
  FAIL 2 | WARN 5 | SKIP 5 | PASS 15460. Both failures also fail on the base `04dca16a` in a
  separate worktree: test-console-ui.R:353 (a "checkpoint coverage is incomplete (worker stopped)"
  line) and test-session-budget.R:423 (a `gptr.checkpoint` entry is last). The five `WARN`s are
  `gptr_rewind()` "file coverage: not restored" warnings in test-cli-claude.R and test-cli-codex.R.
  All of these come from the #98 checkpoint scan under host load (lane A), not this lane.
  After the follow-up, the same filter gives FAIL 2 | WARN 5 | SKIP 5 | PASS 15464, with the same
  two failures and warnings.
- Lint: the first pass missed one long line in R/gptr-config.R (fixed in `9a70c441`). Every
  changed R and test file now lints clean. `isolated-check.R document` regenerated
  `gptr_models.Rd`, `gptr_egress.Rd`, `gptr_security.Rd` and `gptr_provider.Rd`, with no stray diff.
- `precompute.R language-models`: the changed paragraph. The knit also refreshed one session
  footer, to 3.5k tokens and a new id. The run reports one problem, "wrote outside the session temp
  directory", which the base knit reports too.

## Deferred

- Live finding 20 (Jupyter shows `gptr_models()` as a plain repr table without its footer): it needs
  repr text, HTML, Markdown and LaTeX methods plus a `knit_print` for every `gptr_listing`. That is
  a notebook-display feature, not a small fix. `print()` and knitr output keep the footer.
- Review finding 6, second part (the 4096 cap and the id checks are in both `provider_models()` and
  `catalog_discover()`): kept. The second check guards `discover()` callback output, which is user code.

## Rejected

- Review finding 8 (redundant clause in `pcli_default_model()`): ff0be9d5 already removed the
  `model_resolve()` clause and kept the D-097 membership rule.
- Live finding 13, part "the rejected model is still listed as advertised": by contract
  (04 section 6.2), advertisement does not establish entitlement. The visible fix is the error message.
- Review finding 11, part "condense the progress log": #106's record stays as written. D-300 keeps
  long records uncondensed, and the record belongs to another lane.
- Review finding 2, NEWS bullet: the coordinator writes NEWS.md.
