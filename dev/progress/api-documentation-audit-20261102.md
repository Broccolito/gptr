# API documentation audit — 2026-11-02

Base: `4bf477c05b6b60041a68a909d7dcc2abffb9c905` (`origin/main`). This is a
source/documentation audit and focused offline verification, not a live-provider or CRAN
acceptance report. Normal roxygen next to the implementation and generated installed Rd remain
the documentation source of truth. This ledger records coverage and findings; it is not a second
capability manual or a runtime index.

## Coverage

- All 66 public exports were reviewed against their implementation and installed-help source for
  parameters, defaults, returned values, significant errors/approvals, side effects and examples.
  Every export resolves to an Rd alias. Shared pages are intentional.
- All 72 Rd topics (60 export topics and 12 additional topics) were reviewed. All 90 option
  defaults occur in the options topic. The nine other files under `man/` are figure assets.
- All 128 R files were included in a static internal-doc census: 4,348 `@noRd` blocks. Of these,
  3,051 have 1–3 lines, 1,120 have 4–7, 161 have 8–15 and 16 have at least 16 lines. The 177
  longer blocks across 52 files were screened and substantive contracts traced through their
  implementation/callers. A parameter-name screen found no stale parameter in 53 internal
  blocks with `@param`. Short private-helper titles were retained. This is static documentation
  triage, not semantic proof of all private implementations.
- The static function scan found 4,371 top-level named function definitions: 4,240 associated
  with `@noRd`, 129 with public/S3 roxygen and two with plain source comments (`replacement_sub`
  and `r_session_out_text`). No private helper was promoted into public help.
- Four inaccurate internal comments were corrected: two artifact URL promises overlooked fresh
  access tokens; artifact sweeping runs at each listing rather than only once; and the reactor's
  5 ms cap concerns its next I/O wait rather than callback/iteration duration. Behavior unchanged.
- New credential-input, discovery and plugin setup diagnostics belong to their owning branches. Their
  changed signatures and behavior need their own matching docs and final integration review.
  The small new `?peter` discovery pointer is a separate commit to ship with that implementation.

## Focused verification

- `roxygen2::roxygenise(roclets = "rd")`: only relevant Rd pages changed; NAMESPACE unchanged.
- `docs_problems(rd_read_dir())` from `dev/release/lib.R`: zero problems.
- `tools::codoc(dir = ".")`: zero code/documentation signature mismatches.
- The revised adapter example was extracted with `tools::Rd2ex()` and executed offline after
  `pkgload::load_all()`: completed successfully.
- `git diff --check`: clean. No live credentials or provider calls, package downloads, or full
  suite/check were used for this audit. Final broad validation belongs to the integrated candidate
  and CI.

## Export-by-export review

| Export | Owning source | Rd topic | Outcome |
|---|---|---|---|
| `gptr_adapter` | `R/ext-specs.R` | `gptr_adapter` | Callback result contracts; terminal-event example |
| `gptr_agent` | `R/ext-specs.R` | `gptr_agent` | No confirmed documentation gap |
| `gptr_agents` | `R/subagent-defs.R` | `gptr_skills` | No confirmed documentation gap |
| `gptr_api` | `R/ext-check.R` | `gptr_api` | No confirmed documentation gap |
| `gptr_artifacts` | `R/artifact-registry.R` | `gptr_artifacts` | No confirmed documentation gap |
| `gptr_backend` | `R/ext-specs.R` | `gptr_backend` | Handle and current scheduler callback semantics |
| `gptr_blocks` | `R/doc-replay.R` | `gptr_blocks` | No confirmed documentation gap |
| `gptr_cache` | `R/doc-replay.R` | `gptr_cache` | No confirmed documentation gap |
| `gptr_cancel` | `R/gptr-sdk.R` | `gptr_cancel` | Approval for other-session model calls |
| `gptr_check` | `R/ext-check.R` | `gptr_check` | No confirmed documentation gap |
| `gptr_checkpoints` | `R/ckpt-rewind.R` | `gptr_rewind` | No confirmed documentation gap |
| `gptr_coach` | `R/gptr-coach.R` | `gptr_coach` | No confirmed documentation gap |
| `gptr_command` | `R/ext-specs.R` | `gptr_command` | No confirmed documentation gap |
| `gptr_config` | `R/gptr-config.R` | `gptr_config` | Approved model changes are permitted |
| `gptr_context_block` | `R/ext-specs.R` | `gptr_context_block` | No confirmed documentation gap |
| `gptr_describe` | `R/env-describe.R` | `gptr_describe` | No confirmed documentation gap |
| `gptr_doc` | `R/doc-replay.R` | `gptr_doc` | No confirmed documentation gap |
| `gptr_env` | `R/auth-dotenv.R` | `gptr_env` | Safe report metadata versus secret values |
| `gptr_export` | `R/doc-export.R` | `gptr_export` | No confirmed documentation gap |
| `gptr_fake_provider` | `R/provider-fake.R` | `gptr_fake_provider` | No confirmed documentation gap |
| `gptr_fork` | `R/session-object.R` | `gptr_fork` | No confirmed documentation gap |
| `gptr_hook` | `R/ext-specs.R` | `gptr_hook` | No confirmed documentation gap |
| `gptr_init` | `R/gptr-config.R` | `gptr_init` | No confirmed documentation gap |
| `gptr_jobs` | `R/proc-supervise.R` | `gptr_jobs` | No confirmed documentation gap |
| `gptr_last` | `R/session-live.R` | `gptr_sessions` | Shared session topic approval clarification |
| `gptr_login` | `R/auth-oauth.R` | `gptr_login` | No confirmed documentation gap |
| `gptr_logout` | `R/auth-oauth.R` | `gptr_login` | No confirmed documentation gap |
| `gptr_mcp` | `R/mcp-config.R` | `gptr_mcp` | Selector applies to tools/refresh, not server rows |
| `gptr_mcp_add` | `R/mcp-config.R` | `gptr_mcp_add` | Add is lazy; listing/refresh can also connect |
| `gptr_mcp_remove` | `R/mcp-config.R` | `gptr_mcp_add` | Shared MCP setup topic clarified |
| `gptr_mcp_serve` | `R/mcp-server.R` | `gptr_mcp_serve` | No confirmed documentation gap |
| `gptr_models` | `R/catalog-models.R` | `gptr_models` | No confirmed documentation gap |
| `gptr_on` | `R/gptr-sdk.R` | `gptr_on` | Model-call approval requirement |
| `gptr_parallel` | `R/subagent-team.R` | `gptr_parallel` | No confirmed documentation gap |
| `gptr_permissions` | `R/perm-rules.R` | `gptr_permissions` | No confirmed documentation gap |
| `gptr_plugins` | `R/ext-plugins.R` | `gptr_plugins` | Documented with the plugin setup diagnostics (PR 101) |
| `gptr_policy` | `R/ext-specs.R` | `gptr_policy` | No confirmed documentation gap |
| `gptr_preimage` | `R/ckpt-objects.R` | `gptr_preimage` | No confirmed documentation gap |
| `gptr_prob` | `R/s1-types.R` | `gptr_prob` | Names preserved, including unnamed inputs |
| `gptr_prompt` | `R/prompt-sections.R` | `gptr_prompt` | No confirmed documentation gap |
| `gptr_prompt_section` | `R/ext-specs.R` | `gptr_prompt_section` | No confirmed documentation gap |
| `gptr_provider` | `R/ext-specs.R` | `gptr_provider` | No confirmed documentation gap |
| `gptr_providers` | `R/provider-registry.R` | `gptr_providers` | No confirmed documentation gap |
| `gptr_redact` | `R/auth-redact.R` | `gptr_redact` | No confirmed documentation gap |
| `gptr_register` | `R/ext-registry.R` | `gptr_register` | No confirmed documentation gap |
| `gptr_registry` | `R/ext-registry.R` | `gptr_registry` | No confirmed documentation gap |
| `gptr_reload` | `R/ext-load.R` | `gptr_reload` | No confirmed documentation gap |
| `gptr_resume` | `R/session-store.R` | `gptr_sessions` | Other/stored session model-call approval requirement |
| `gptr_return` | `R/gptr-sdk.R` | `gptr_return` | No confirmed documentation gap |
| `gptr_rewind` | `R/ckpt-rewind.R` | `gptr_rewind` | No confirmed documentation gap |
| `gptr_risk` | `R/perm-classify.R` | `gptr_risk` | No confirmed documentation gap |
| `gptr_router` | `R/ext-specs.R` | `gptr_router` | No confirmed documentation gap |
| `gptr_scrub` | `R/auth-redact.R` | `gptr_scrub` | No confirmed documentation gap |
| `gptr_sessions` | `R/session-store.R` | `gptr_sessions` | Shared session topic approval clarification |
| `gptr_skills` | `R/skill-discover.R` | `gptr_skills` | No confirmed documentation gap |
| `gptr_source` | `R/doc-replay.R` | `gptr_source` | No confirmed documentation gap |
| `gptr_spec` | `R/ext-specs.R` | `gptr_spec` | No confirmed documentation gap |
| `gptr_steer` | `R/gptr-sdk.R` | `gptr_steer` | Other-session model-call approval requirement |
| `gptr_step` | `R/gptr-sdk.R` | `gptr_step` | No confirmed documentation gap |
| `gptr_tailor` | `R/gptr-tailor.R` | `gptr_tailor` | Model-call approval requirement |
| `gptr_tool` | `R/ext-specs.R` | `gptr_tool` | Derived schemas use string properties |
| `gptr_tool_result` | `R/ext-specs.R` | `gptr_tool_result` | Accepted image formats and input containers |
| `gptr_trust` | `R/gptr-config.R` | `gptr_trust` | No confirmed documentation gap |
| `gptr_usage` | `R/session-budget.R` | `gptr_usage` | No confirmed documentation gap |
| `gptr_wait` | `R/gptr-sdk.R` | `gptr_wait` | No confirmed documentation gap |
| `peter` | `R/gptr-gateway.R` | `peter` | No confirmed documentation gap |

## Additional Rd topics

`as.data.frame.gptr_session_summary`, `format.gptr_risk`, `format.gptr_session`, `gptr-background`, `gptr_egress`, `gptr_options`, `gptr_security`, `print.gptr_session`, `print.gptr_session_summary`, `session-accessors`, `str.gptr_session`, `summary.gptr_session`. No additional confirmed documentation mismatch was found
in these topics at the audited base.
