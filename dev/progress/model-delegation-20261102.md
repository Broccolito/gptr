# Model delegation and typed decision composition (2026-11-02)

- Sub-agent model references pass through the existing session-aware canonical resolver before
  backend, pool, guard and worker selection. Provider aliases, CLI aliases, explicit thinking
  suffixes and session-scoped provider specifications retain their selected target. Unspecified
  children inherit the running session's model before consulting the global default.
- The model's delegation guidance names model discovery and the distinct API, Claude Code and
  Codex references. Configured System 1 guidance also reaches minimal children. Decision-only
  models are refused by interactive chat, including its initial default and first model switch;
  ordinary typed one-shot calls remain available.
- System 1 composes as typed leaves through the existing vectorized API, rather than pretending
  to provide conversational tools. Batches retain the existing element and concurrency limits,
  deduplication, retries, native/emulated provenance and cache. Each completed attempt charges
  the owning session and its ancestors; admission checks their budgets, journaled charges survive
  resume, and completed answers remain cached if a batch stops. Context services identify their
  owning session even when constructed from its id or called outside the R tool frame. Optional
  malformed usage metadata remains unknown, and displayed decision values are escaped.
- Offline source validation passed 4,886 assertions with zero failures, warnings or skips in
  264.4 seconds. Coverage includes native and emulated adapters, bounded scheduling, retry costs,
  cache-only calls, exhausted budgets, unknown counters, owner/ancestor/global deduplication,
  session resume, actual thousand-item decision batches, real R worker execution, fake native
  Claude Code/Codex MCP delegation in both directions, aliases and scoped providers. Changed
  production/test files lint clean.
- The console work is reviewed separately in PR #99. Final combined installed-package,
  token-efficiency, native live, release-file, CRAN-mode and hosted checks are recorded in the PR.
