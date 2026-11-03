# gptr 1.0.1 fixes, lane B: credentials (#104)

Branch `claude/fix-B` from `04dca16a`. Findings: 24 (lane B of the 1.0.1 review; review #104
correctness and design, the combined-interactions review and the live credential test). Decisions:
D-315 to D-318. Numbers below are the finding indexes of lane B.

## Fixed

| # | Severity | Fix | Commit | Test |
|---|---|---|---|---|
| 17 | medium | `/skip` and `/cancel` at the hidden prompt skip and cancel; never stored | `742d40af` | test-auth-setup.R "/skip and /cancel at the hidden prompt skip and cancel instead of storing a key" |
| 18 | medium | every `gptr_login()` outcome is a `gptr_message_login` notice naming the store, never the value; the model sees it in the `r` result | `17bed7eb` | "login says what it stored, skipped or cancelled, never the value"; "model-initiated login sends only safe status ..." (now asserts the notice in the tool result) |
| 1, 5, 15 | medium | a session login reaches worker and coaching children under the provider's first key variable, through `provider_credential()` (endpoint binding kept); remembered logins are still read from `auth.json` by the child (D-315) | `97572735` | test-auth-childenv.R "a session login reaches workers as its provider's key, bound to the endpoint" |
| 0, 6 | medium | stdio slot binding drops `getwd()` and secret-like expanded env values; the prompt says "R's working directory when the server starts" (D-316) | `c1a84aad` | "a remembered stdio slot survives setwd() and credential variables, not a new host" |
| 19 | low | the review names the one store used; a remembered login reuses an existing keyring item for the record's own field | `15df52ed` | "a remembered login names the one store it uses and keeps an existing keyring item" |
| 2 | low | a malformed `auth.json` no longer stops stdio servers (fail-soft read, session credentials kept) | `d1be04b4` | "a malformed credential store does not stop stdio servers; session slots still work" |
| 3 | low | the hidden answer's `login-input` vault entry is redaction-only | `02bd86f9` | "session login keeps values out of files, ..." (lookup is NULL, redaction holds) |
| 4 | low | the OAuth paste fallback refuses a UI without hidden input before the browser opens | `7febf3fd` | "an OAuth paste fallback without hidden input refuses before the browser opens" |
| 8, 22 | low | the refusal names `gptr_env(path)` or a remembered login made in RStudio or terminal R on Unix; `?gptr_login` and the language-models guide say where hidden entry works | `8af9a98d` | "login refuses unsupported hidden input and missing humans before reading" |
| 9 | low | `mcp_http_auth()` uses only the setup-time binding; the test builds connections through `mcp_http_setup()` | `f992b3a7` | "HTTP MCP path and authentication configuration edits invalidate login" |
| 7 | low | one record read (and keyring access) per HTTP MCP request | `cc8b4973` | same test, counts `auth_store_get()` calls |
| 10 | low | logout resolves with login's rule first; cached aliases only once the config is gone (an alias no longer removes another server's credential) | `0a8a3661` | "logout resolves a configured name before a cached alias" |
| 11 | low | dead `credential_from_store()` defaults and hash fallback removed; `auth_store_set()` reuses `auth_record_handles()`; the second keyring backend check removed | `0c3e0fdf` | existing auth tests |
| 13 | low | the rstudio UI keeps prompt line feeds (`console_escape()`); a select title goes in the message | `491a69d3` | test-console-ui.R "the rstudio UI keeps the line feeds of gptr's own prompts and escapes the rest" |
| 20 | low | keyring refusal names `install.packages("keyring")` | `b11b8e11` | "keyring storage without the keyring package says how to install it" |
| 21 | low | Ctrl-D reads as blank and skips: `?gptr_login` and the reader's comment say so | `7389bf71` | "an end of input at a terminal's hidden prompt reads as blank and skips" |
| 16 | low | `?gptr_mcp_add` and the MCP guide describe stdio credential slots | `edb2a450` | none (docs) |
| 12 | low | contract 11.8 record shapes and session store; ask schema 840 o200k tokens (+166), re-measured with rtiktoken; D-243 visible-key bullets edited in place | `85ce1339` | none (docs) |
| 14 | low | tests for native keyring backends, the missing-endpoint refusal and a remembered slot's logout; OAuth Skip/Cancel, user-scope keyring reuse and the setwd() binding are covered by the tests above | `e0c6a9f9` | "explicit keyring storage accepts the native backends only", "provider login refuses a provider without a valid endpoint before input" |

Decisions: `e9457c8a` (D-317, D-318); D-315 and D-316 are in their fix commits.

## Deferred

- 23 (low): `gptr_providers()` naming the store of a credential (`auth:<id> (session)` and so on).
  It changes the listing's credential column format, which tests and readers parse, for a UX gain;
  the login notice now names the store at login time.
- 14, remainder (low): no new tests for `ask_execute()` returning `details$skipped` (the ask tool is
  not changed here) or for `model_default()` after a session login (#106 fixed and tests
  `model_key_present()`).
- 12, remainder (low): the `ui` kind's `has_secret_input` stays documented in the contract only; no
  package help page documents the `ui` kind's members.

## Rejected (in part)

- 6, dropping the executable's content hash: kept. An updated launcher is a changed executable, the
  error says so and asks for login again; only `getwd()` and credential values were ambient (D-316).
- 5, "session credentials are invisible to `model_default()` and the keyed pick": already fixed by
  #106 (`model_key_present()` reads `the$secrets$auth`); only the worker gap remained (fixed above).
- 10, unifying login and logout resolution into one shape: logout must work after the
  configuration is gone, so the branch stays; its precedence was the defect (fixed above).

## Checks

- Broad filter `auth|mcp|secret|provider|catalog|tool-ask|ask|subagent-worker|gptr-coach|console-ui|ui`:
  FAIL 4, WARN 1, SKIP 5, PASS 7182; the 4 failures and the warning are the pre-existing ones below.
- Focused filters: `auth-setup` 127 pass; `auth` 1667+ pass; `auth-childenv`, `subagent-worker`,
  `gptr-coach` 721 pass; `mcp-client`, `mcp-namespace`, `mcp-config` pass; `console-ui` passes
  except the line below.
- Pre-existing on `04dca16a` as well (not lane B): test-mcp-server.R:284-289 and
  test-console-ui.R:353 fail here because the automatic file checkpoint scan reports coverage
  incomplete; test-console-ui.R:799 (the PTY login test) timed out once under load and passed on
  rerun.
- Lint clean for every changed R and test file; `document` regenerated `gptr_login.Rd` and
  `gptr_mcp_add.Rd` only; `precompute.R language-models` and `mcp` knitted (the language-models
  "wrote outside the session temp directory" problem also occurs on `04dca16a`).
