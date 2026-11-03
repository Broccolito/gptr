# Harness UX verification — 2026-11-02

This records verification of the combined candidate, rather than a second capability
manual. The implementation is split across PRs #100–104 and #106. Package source and
installed Rd remain the runtime documentation sources.

## Combined offline and installed-package checks

- The initial combined focused suite passed 2,476 assertions, with zero failures or
  warnings and one installed-only skip (71.9 seconds). The filter covered discovery,
  namespace, R tools, MCP waits, credential setup, provider/CLI discovery, agent runs,
  console rendering and architecture.
- A temporary installed package was tested from a directory without a Git checkout:
  66 exports and 72 Rd topics were indexed; setup/model search, qualified public help,
  bounded internal source, and the new login signature worked. `tools::codoc()` found
  no signature mismatches.
- Precompute checks for interactive-console, language-models and mcp found zero
  problems across three vignettes.
- The discovery and model branches separately passed the four static-prefix and
  14 golden-transcript checks. The measured prompt additions are recorded in their
  token-baseline ledgers; regression tolerances were unchanged.
- Subsequent CI found neighboring fixture assumptions and an actual operator-context
  serialization defect. Their follow-up verification is recorded below as completed;
  the initial focused result is not a claim that the entire suite passed.
- Model follow-ups passed 6,233 broader assertions covering persistence, replay, forks,
  request accounting, fake-provider tool loops, CLI routes and native adapters. A final
  1,327-assertion pass covered the remaining replay, Responses and identity fixtures;
  all passed without failures, warnings or skips. The four prefix and 14 golden token
  checks passed with unchanged tolerances.
- The final live-discovered alias regression was reproduced before the fix, then
  passed 568 catalog/inventory assertions and lint. The temporal identity wording
  regression was reproduced before its edit, then passed all 741 agent-run assertions
  and lint. The final combined token check again passed all four prefixes and 14
  golden transcripts without changing baselines or tolerances.
- The final combined candidate regenerated Rd without a source diff, passed
  `docs_problems()` and `tools::codoc()` with zero problems, and precomputed all three
  affected vignettes with zero problems. All 82 changed R files passed lint after
  brace-only formatting corrections. Installed-package acceptance was repeated from
  an empty directory without the repository: all 66 exports and 72 topics remained
  discoverable, and help/source/login-shape checks passed.

## Live computer-use tests

Used a fresh `/Applications/R.app` and the temporary installed candidate, without
altering the user's RStudio session. Project:
`/private/tmp/gptr-live-harness-20261102`. All configuration writes were contained in
that synthetic project or its redirected user configuration directory.

1. Started `peter(model = "codex/gpt-6-sol", mode = "auto")` through the console UI.
   Asked which models were available and which model the conversation used, without
   naming the inspection APIs. Peter inspected the R catalog and provider status.
   It correctly distinguished the selected Sol route from an unreported backend
   identity. Footer: `selected gpt-6-sol`. Its prose did not assert Astra identity.
   It still made unnecessary documentation/web-tool calls; the harness cannot
   guarantee optimal model tool choice.
2. Asked Peter to set up the public Microsoft Learn MCP server for the project.
   Installed help search found `gptr_mcp_add`; Peter read that help and recovered
   from a missing workspace by looking up `gptr_init`. After ordinary configuration
   and project-trust approvals, it connected and listed the server's three tools.
   The extra recovery step motivated a prerequisite clarification in the MCP help.
3. Entered `/mcp serve`. R.app returned to its ordinary top-level prompt. An
   independent client called the R tool and received `42` from `value + 1`, without
   a manual event pump or another keypress. Client exited zero, stderr was empty.
   `identical(gptr_last(), codex_chat)` passed and `gptr_last() |> peter()` resumed
   the same chat. The server was stopped afterward.
4. Explicit Claude CLI inventory refresh found currently advertised models absent
   from the package snapshot. Started interactive Peter with the newly discovered
   `claude-cli/claude-sonnet-5`. It completed two turns; the runtime answer and
   footer agreed with CLI metadata: `reported claude-sonnet-5`.
5. Claude found the skill help, copied the official Posit r-cli skill with all its
   references into the project, confirmed it was visible, and used its pluralization
   pattern to print `1 test passed`.
6. Explicitly configured the official feature-dev plugin and the Posit marketplace
   root at session scope. Feature-dev was listed as lazy. The invalid marketplace
   setting disappeared without a diagnostic before activation; this exposed an
   additional discovery path, addressed in the PR #101 follow-up. Merely appearing
   as lazy is not evidence of activation.
7. A real `ask` text question displayed `/skip` and `/cancel`; `/skip` returned a
   skipped answer and the live model acknowledged it.
8. `gptr_login(..., method = "key", scope = "session")` in R.app refused before
   requesting any value, because hidden input was unavailable. The error directed
   the user to an echo-disabled terminal or RStudio password dialog. No real
   credential was entered into a visible prompt.
9. Native Anthropic and TypeSafe catalog queries succeeded with existing credentials
   loaded only through `gptr_env(..., set_env = FALSE)`. Credentials were neither
   printed nor copied. Newly advertised native model IDs appeared with timestamps;
   retained but unlisted IDs were marked unlisted.
10. A live TypeSafe decision call through `typesafe/jev-latest` returned true with
    probability 0.98 and reported `jev-1.14.0`. A native Anthropic chat request using
    a discovered ID reached the service but was rejected for insufficient account
    credits. Native Anthropic inference is therefore not verified as successful.
11. Retested plugin discovery in a fresh R.app using the updated installed candidate.
    The configured marketplace-only root now produced an actionable footer and one
    registry diagnostic; the valid feature-dev plugin remained available. Starting
    interactive Peter activated feature-dev and exposed its three imported agents.
12. Tested the real terminal host with a public canary, rather than a real credential.
    Hidden entry returned success without echoing the canary, setting an environment
    variable or writing an auth file. Terminal modes were restored. Blank input
    skipped; Ctrl-C cancelled safely. Real OS-keychain writes remain untested.
13. Drove ordinary text questions through the actual terminal UI and a deterministic
    four-request Peter tool loop. A typed `bluebird` answer, `/skip` and `/cancel`
    produced the expected structured answers and cancellation status.
14. A live `claude-cli/default` turn displayed selected and reported identities
    separately (`sonnet` versus `claude-sonnet-5-5`). This exposed a separate routing
    regression: newly discovered CLI short names could take precedence over declared
    native aliases. The final correction preserves declared aliases ahead of bare
    discovered IDs, while keeping explicit provider-qualified selection and registered
    provider fallback.
15. Reinstalled the combined final candidate and refreshed Claude's live inventory.
    `gptr_models("sonnet")` still preferred the native Anthropic alias. A fresh
    interactive `claude-cli/default` session sent the full `claude-sonnet-5-5` argument
    and completed two turns, both reporting that same model. The first answer correctly
    distinguished configuration from metadata that arrives afterward; the next answer
    used the prior completed report without claiming independent identity verification.
    An ordinary `peter("...", model = "claude-cli/default")` call also received the same
    route context and reported the matching model. Saved public messages were checked
    for the full selected argument and matching provider metadata.

Public test artifacts include `codex-messages.json`, `claude-messages.json`,
`idle-client.json`, `native-model-catalogs.json` and
`cli-and-decision-verification.json`, `default-cli-final-messages.json` and
`ordinary-cli-final-messages.json` in the synthetic project. The fresh R.app was
closed without saving its workspace. No account funding or authentication settings
were changed.

## CI and incoming constraints

Each PR has normal platform CI and an exact-source-tarball workflow requested.
The latter builds one archive for five consumers with incoming checks enabled.
Failures are investigated rather than suppressed. As of this ledger's initial
write, the final heads are still being verified.

The released CRAN version was verified as 1.0.0; the candidate version is 1.0.1.
Incoming checks additionally report `Days since last update: 1`. Release timing is
an external constraint: no check was disabled, clock changed, or zero-note gate
weakened. No CRAN submission was made.

The first combined Linux optional run stopped before tests: R dependency setup
installed Quarto 1.11.9, then the dedicated pinned setup could not downgrade it to
1.10.19. The existing R setup action supports `install-quarto: false`; both optional
workflows now leave Quarto to their existing pinned setup. No installer, dependency
pin or test gate was replaced. All 14 offline dependency-helper tests passed, and
combined Windows/Linux verification was requested again using the corrected
workflow as controller. The original Windows run was allowed to finish.

The original Windows optional artifact had no failed or warning assertions in any
of the six files, and child cleanup settled with no remaining owned processes.
Its controller rejected intentional Codex platform skips. The existing skip table
now admits only the exact POSIX-shell case on Windows and the exact PowerShell
case on unsupported hosts/volumes. All 12 mandatory Codex cases remain mandatory;
unknown titles/files and an incorrectly skipped Linux shell case still fail.
The correction passed 3,843 pure-controller assertions and lint, and replaying the
original artifact passed. Package runtime source was unchanged by these CI fixes.
