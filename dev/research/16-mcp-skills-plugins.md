# 16 - MCP client in R, Agent Skills, plugin formats

**Track 16.** This is a research report for the gptr rebuild. It covers REQ-28, REQ-29, REQ-30 and REQ-31, and touches REQ-01..03, REQ-09, REQ-12 and REQ-36..38.

**Setup.**
- Date of research: 2026-09-29.
- Machine: macOS (Darwin 25.6), R 4.4.3.
- Packages: processx 3.8.6, httr2 1.2.2, httpuv 1.6.17, later 1.4.8, jsonlite 2.0.0, yaml 2.3.12, and RcppTOML 0.2.3 (used only for cross-checking).
- CLIs: Claude Code 2.1.261, codex-cli 0.157.0.
- Every R run used `Rscript --vanilla`.
- In this agent environment `LANG` is empty, so R ran in the **C locale** unless a command says `LC_ALL=en_US.UTF-8`. This turned out to matter (2.17).

**Where the evidence lives.** Prototypes and captured outputs are in the scratch folder `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/16/proto/`. Because that folder is temporary, section 5 embeds every prototype source file and every output file verbatim. The MCP spec pages used here were saved to `work/16/spec/` by the previous researcher on this track. I re-downloaded the two TypeScript schema files from GitHub today, and they are byte-identical to the saved copies (`cmp` printed IDENTICAL for both).

**Evidence labels.**
- **VERIFIED**: I saw the evidence myself, as a file with line numbers, a URL fetched today, or an executed command with its output.
- **LIKELY**: strong indirect evidence, such as a fetched documentation page read through a summarising fetch tool, or a source reading I did not execute.
- **UNCERTAIN**: memory, a search snippet, or an extrapolation.

**How this report relates to others.**
- Report `06-pi-subagents-mcp-codemode.md` prototyped a gptr MCP client against protocol **2025-11-25**.
- Report `07-anthropic-api-claude-plan.md` verified an in-process "sdk" MCP server for the Claude Code plan provider, live.
- This report adds what those two do not cover:
  - the **2026-07-28** revision, which became current in July 2026, is stateless, and changes the wire format;
  - dual-era clients and servers that work with both revisions;
  - gptr as an HTTP MCP server for the live R session (the event-loop question left open in `00-digest.md` line 205);
  - config import from 9 harnesses, and a pure-R TOML reader;
  - Agent Skills, and the plugin formats;
  - measured context cost;
  - several locale traps.
- Where this report agrees or disagrees with 06 or 07, it says so.

---

## 1. Executive summary

1. **The current MCP revision is `2026-07-28`, and it changes the wire format** (VERIFIED: https://modelcontextprotocol.io/specification/versioning says "The current protocol version is 2026-07-28").
   - **Removed:** the `initialize` / `notifications/initialized` handshake, protocol sessions and `Mcp-Session-Id`, the HTTP GET stream, SSE resumability, `ping`, and `logging/setLevel`.
   - **Added:** every request carries `_meta["io.modelcontextprotocol/protocolVersion"]` and `_meta["io.modelcontextprotocol/clientCapabilities"]`, and every result carries `resultType`. Servers must implement `server/discover`.
   - **Server-to-client requests** (elicitation, sampling, roots) no longer exist. Instead the server returns a result with `resultType: "input_required"` and the client retries the request. The spec calls this pattern MRTR (Multi Round-Trip Requests).
   - The previous revision is `2025-11-25`. The new spec calls it and everything before it the **legacy** era.
2. **Almost everything still speaks the legacy era**, so **gptr's client must support both eras.**
   - Pi's MCP client (commit 1b347794), mcptools 1.0.3 and mcplite 0.1.0 all stop at 2025-11-25 (VERIFIED from source).
   - Claude Code 2.1.261's own server (`claude mcp serve`) answered a modern `server/discover` probe with `-32601 Method not found`, then completed a 2025-11-25 handshake (VERIFIED, executed).
   - On stdio, the client probes with `server/discover` and falls back to `initialize` on any non-modern error or on a timeout. On HTTP, it inspects the 4xx response body before falling back.
   - The prototype does exactly this, and it passed against a modern R server, a legacy R server and Claude Code's TypeScript server (5.4 and 5.8).
3. **A pure-R MCP client built on processx + jsonlite + httr2 is small and robust. Recommendation: build it; do not depend on mcptools.**
   - The stdio client prototype is 342 lines. It detects the era, pages through `tools/list`, resets its timeout on progress notifications, and sends `notifications/cancelled` both on timeout and on a real SIGINT (Esc/Ctrl-C). It drops late responses, reassembles multi-megabyte single-line messages in about 1 s, and shuts down gracefully (close stdin, wait, then `kill_tree`). All of this was executed.
   - mcptools' stdio client returns only the first line that appears within 4 s, with no id matching (`client.R:1318-1349`). It is legacy-only, and it pulls in ellmer and nanonext.
4. **Locale is the biggest portability trap for MCP in R** (all VERIFIED by execution). `Rscript` runs in the C locale when launched from GUI apps, cron, containers, or this agent environment. In the C locale:
   - (a) `cat()` of UTF-8 text prints `<U+00E9>`, which corrupts JSON. It is also **quadratic**: 25k, 50k and 100k non-ASCII characters took 0.27 s, 1.18 s and 4.79 s, and 600k took **296 s** (an earlier run that was not captured). The verification re-run measured 0.17 s, 0.71 s, 2.81 s and **85 s** for 600k. Absolute times vary about 3x with machine load, but the time still grows about 4x each time n doubles. The same 600k string takes 0.00 s in a UTF-8 locale.
   - (b) `file("stdin", encoding = "UTF-8")` rejects UTF-8 input with "invalid input found on input connection".
   - (c) jsonlite serialises strings of unknown (native) encoding as `<c3><a9>`.
   - Separately, and in any locale, `file("stdout")` silently creates a regular file named `stdout`.
   - **Fix, verified in both the C and UTF-8 locales:**
     - Read stdin with `file("stdin")` plus `readLines(encoding = "UTF-8")`, which only marks the encoding.
     - Give processx `encoding = "UTF-8"`.
     - Send raw bytes.
     - Write **ASCII-only JSON**: every non-ASCII character becomes a JSON backslash-u escape, with surrogate pairs above the Basic Multilingual Plane. The vectorised `json_ascii()` costs 0.02-0.07 s for 5 MB of ASCII and about 1-2 s for 6 MB containing 1 million non-ASCII characters.
5. **gptr can be an MCP server for the live R session, verified end to end.**
   - An in-process httpuv Streamable HTTP server supported both eras, a bearer token, an Origin check, and binding to 127.0.0.1. It served 11 requests from a child `Rscript` acting as the external agent.
   - The object the agent created (`made_by_agent`) existed in the parent session afterwards.
   - Event-loop facts (VERIFIED):
     - `later` callbacks, and therefore httpuv handlers, run only at the top-level prompt or inside `later::run_now()`. So gptr must pump `later::run_now(0.1)` while it waits on a `claude -p` or `codex exec` child process.
     - **`httpuv::service(0)` serves forever in a non-interactive session.** It hung my first test; the source is quoted in 2.11.
6. **Which transport to use for which agent:**
   - For **Claude Code**, report 07's in-process "sdk" MCP over stream-json stays first choice.
   - For **Codex** and every other external agent (Claude Desktop, Cursor, VS Code), use the in-process HTTP server.
   - Codex 0.157.0 accepts `-c mcp_servers.gptr.url="http://127.0.0.1:PORT/mcp" -c mcp_servers.gptr.bearer_token_env_var="GPTR_MCP_TOKEN" -c mcp_servers.gptr.tool_timeout_sec=3600` (VERIFIED with `codex mcp get --json`).
   - A 37-line **stdio-to-HTTP bridge** lets stdio-only clients reach the same in-session server. It was verified in both eras.
   - Codex 0.157.0 no longer lists a `mcp-server` subcommand (VERIFIED `codex --help`). This answers open question 567 of the digest.
7. **Authorization applies to HTTP servers only.** It combines:
   - OAuth 2.1 with PKCE (S256);
   - RFC 9728 protected-resource metadata, plus RFC 8414 / OpenID Connect discovery;
   - RFC 8707 `resource`, and RFC 9207 `iss` validation (new MUST in 2026-07-28).
   - Clients are registered, in order of preference, by pre-registration, **Client ID Metadata Documents (CIMD)**, or Dynamic Client Registration (DCR, deprecated in 2026-07-28).
   - Read-only probes (VERIFIED, executed): Sentry, Linear and Notion answer 401 with `resource_metadata` and advertise S256, DCR and CIMD. GitHub's MCP server advertises neither DCR nor CIMD, so it needs a pre-registered app or a PAT header.
8. **httr2 1.2.2 has most, but not all, of the OAuth pieces** (VERIFIED by printing its source).
   - Exported and working offline: `oauth_flow_auth_code_pkce()`, `oauth_flow_auth_code_url()`, `oauth_flow_auth_code_listen()` (returns the full redirect query, so `iss` is visible), and `oauth_flow_auth_code_parse()`.
   - `oauth_flow_auth_code()` never checks `iss`, and its code-for-token exchange is internal. gptr should compose the flow from the exported pieces plus one token POST.
   - mcptools' DCR request omits `application_type`, which 2026-07-28 now requires.
   - **Version note (verification pass):** 1.2.2 is only the locally installed version. CRAN's current httr2 is **1.3.0** (published 2026-07-13), and mcptools 1.0.3 itself requires httr2 >= 1.2.3. I read the 1.3.0 source. The conclusions above still hold: there is still no `iss` check, and `oauth_flow_auth_code_read()` is still internal. What is new since 1.2.2:
     - `oauth_server_metadata(issuer, type = c("openid", "oauth"), url)`. It fetches **one** well-known URL and checks `issuer`, so it does not do MCP's three-URL fallback.
     - `oauth_client(metadata = )`.
     - `oauth_cache_path()` now defaults to `tools::R_user_dir("httr2", "cache")`.
     - `resp_stream_lines()` now runs in linear time.

     gptr should declare `httr2 (>= 1.2.3)` or later and test against 1.3.0.
9. **Harness-agnostic MCP config (REQ-30).**
   - Most harnesses use the same `{"mcpServers": {name: {command, args, env} | {url, headers}}}` shape: Claude Desktop, Claude Code (`.mcp.json`, `~/.claude.json`), Cursor, Pi, Gemini CLI, mcptools.
   - VS Code uses `{"servers":..., "inputs":...}`, and Codex uses TOML `[mcp_servers.<name>]`.
   - The importer prototype reads 16 file locations for 9 harnesses and normalises every entry to one record. It dedupes servers configured in several harnesses, keeps `${VAR}` placeholders until connect time, and flags VS Code `${input:...}` entries. On the fixtures it found 14 unique servers (VERIFIED).
10. **Pure-R TOML is enough for Codex. Ship it rather than depend on a TOML package.**
    - A 242-line base-R TOML 1.0 reader agrees with RcppTOML 0.2.3 on 36 of 39 values of a realistic Codex config.
    - In all 3 disagreements RcppTOML is the one that is wrong or lossy: `0xDEAD_BEEF` becomes `-559038737`, `9_007_199_254_740_991` becomes `-1`, and an empty array becomes NULL.
    - RcppTOML's default `escape = TRUE` also doubles backslashes.
    - The CRAN alternatives are compiled (RcppTOML: C++17; tomledit: Rust/Cargo) or embed V8 (`toml`).
11. **Agent Skills** (agentskills.io spec plus its client-implementation guide, fetched today).
    - A skill is a directory containing `SKILL.md`.
    - Required frontmatter: `name` (1-64 characters of `[a-z0-9-]`, no leading, trailing or doubled hyphen, must match the directory name) and `description` (1-1024 characters).
    - Optional frontmatter: `license`, `compatibility` (at most 500 characters), `metadata` (string map), and `allowed-tools` (experimental).
    - Loading happens in three stages:
      - a catalog of about 50-100 tokens per skill, as an `<available_skills>` XML block;
      - the body (the guide recommends under 5000 tokens);
      - bundled resources, only when the body refers to them.
    - The guide recommends activation through a file read or a tool, lenient YAML parsing, protecting skill content from context compaction, and project-over-user precedence.
12. **Real skills are messy, and the catalog needs a budget** (VERIFIED, executed).
    - A bounded scan found 161 skills in about 0.3 s (0.19-0.37 s across three runs), plus 57 shadowed duplicates.
    - 101 of the skills use a top-level `version:` field that is not in the spec. 10 bodies exceed 500 lines.
    - The full catalog is **64.5k characters, about 16k tokens**. Claude Code caps its listing at about 1% of the context window and 1536 characters per entry. Codex caps it at 2% of the context window, and uses 8,000 characters only when the context window is unknown; that is a fallback, not a floor (corrected in verification).
    - A naive `list.files(recursive = TRUE)` over `~/.claude/plugins/cache` (1.5 GB, 69,652 files, 15 top-level `node_modules` trees and 797 counting nested ones; re-counted in verification) ran for over 2 minutes. Discovery must be a bounded breadth-first walk that skips `node_modules` and `.git`.
13. **Claude Code plugins, and what gptr can reuse from them.**
    - Layout:
      - `.claude-plugin/plugin.json`: optional; only `name` is required.
      - `skills/`, `commands/`, `agents/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `output-styles/`, `bin/`, `settings.json`.
      - `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` are substituted in paths.
    - Distribution is through `.claude-plugin/marketplace.json`. Installed plugins are recorded in `~/.claude/plugins/installed_plugins.json` (version 2).
    - gptr can use skills, commands, agents and MCP servers **unmodified**, given a tool-name map and a model-alias map.
    - Hooks can only be reused partly (they are opt-in, bash-centric, and not portable to Windows). LSP servers, monitors, themes, workflows and output styles should be ignored.
14. **Proposed gptr plugin format.**
    - A plugin is either a directory or an R package with `inst/gptr/`. It holds `skills/`, `extensions/*.R`, `agents/*.md`, `prompts/*.md` and `.mcp.json`.
    - The optional manifest `.gptr-plugin/plugin.json` takes a superset of Claude's `plugin.json` fields: gptr adds `extensions` and `rDepends`.
    - A Claude plugin directory is accepted as-is.
    - This matches report 05's `inst/gptr/{skills,extensions,prompts}` proposal.
15. **Context cost (Track E): expose MCP tools as R functions by default.**
    - Claude Code's real 27-tool `tools/list` is **143,525 characters, about 36k tokens**. A one-line R signature per tool is 5,899 characters (about 1.5k tokens), and the names alone are 300 characters.
    - Because gptr's main tool already evaluates R (REQ-09), exposing MCP tools as **R functions** is "code mode" at no extra cost, with no separate sandbox VM (Pi runs its code mode in a QuickJS VM).
    - Default `exposure = "r"`; alternatives `"direct"`, `"deferred"` (provider-native tool search) and `"hidden"`. This matches report 06 and Pi's `codemode` default.
16. **Dependencies.**
    - **Imports:** jsonlite, processx, httr2 (the providers need it anyway), yaml (for SKILL.md frontmatter).
    - **Suggests:** httpuv and later (for `mcp_serve()` and the OAuth loopback redirect; httr2 already suggests httpuv), openssl (httr2 imports it anyway).
    - No TOML package.
17. **Windows (not executed; LIKELY or UNCERTAIN).**
    - Run `.cmd` shims such as `npx.cmd` via `cmd.exe /d /c call <shim> args`. The processx docs ("Batch files") show `cmd.exe /c call`; the `/d`, which skips AutoRun, is our own addition.
    - Use `file.path(R.home("bin"), "Rscript.exe")` (callr does this) and `windows_hide_window = TRUE`.
    - `kill_tree()` covers wrapper processes.
    - Expect `\r\n` line endings on R's stdout, and strip the trailing `\r`.
    - `Sys.which()` returns short 8.3 paths.
    - Corrected in verification: the current Claude Code MCP docs (fetched 2026-09-29) do **not** tell users to wrap `npx` in `cmd /c` on Windows. The Claude Code 2.1.119 changelog (April 2026) says it "removed false-positive 'Windows requires 'cmd /c' wrapper' MCP config warning". gptr's own need for `cmd.exe /c call` comes from processx and CreateProcess, not from Claude's docs.

---

## 2. Findings

### 2.1 Protocol revisions and version negotiation

| Revision | Status on 2026-09-29 | Era | Key traits |
|---|---|---|---|
| 2024-11-05 | Final | legacy | HTTP+SSE transport (GET SSE + `endpoint` event + separate POST) |
| 2025-03-26 | Final | legacy | Streamable HTTP introduced; JSON-RPC batching; OAuth 2.1 |
| 2025-06-18 | Final | legacy | batching removed; `structuredContent` / `outputSchema`; elicitation; resource links; `MCP-Protocol-Version` header; RFC 8707 resource indicators; RFC 9728 PRM |
| 2025-11-25 | Final (previous) | legacy | icons; URL-mode elicitation; sampling with tools; CIMD; experimental tasks; OIDC discovery; SSE polling via `retry` + `Last-Event-ID` |
| **2026-07-28** | **Current** | **modern** | stateless: no `initialize`, no sessions, `_meta` on every request, `server/discover`, MRTR, `subscriptions/listen`, `resultType`, `ttlMs`/`cacheScope`, `Mcp-Method`/`Mcp-Name` headers; deprecations: roots, sampling, logging, DCR, HTTP+SSE |

Evidence:
- The versioning page (VERIFIED, fetched 2026-09-29) and the 2026-07-28 changelog (`spec/2026-07-28/changelog.md`; major changes quoted in 3.1).
- The 2025-06-18 changelog (VERIFIED, fetched) records "Remove support for JSON-RPC batching" and the `MCP-Protocol-Version` header.

**Legacy negotiation (up to and including 2025-11-25).**
- The client sends `initialize` with its latest version.
- The server answers with the same version if it supports it, and otherwise with its own latest version.
- The client disconnects if it cannot speak the version the server chose.
- On HTTP, every later request carries `MCP-Protocol-Version: <negotiated>` (`spec/2025-11-25/basic_lifecycle.md:167-183`; VERIFIED).

**Modern negotiation (2026-07-28).** In the spec's words: "There is no negotiation handshake. Every request carries its protocol version, and the server accepts or rejects each request independently."
- An unsupported version gets error `-32022` with `data.supported` and `data.requested`. The client should retry with a version from the supported list.
- `server/discover` is mandatory for servers and optional for clients (`spec/2026-07-28/basic_versioning.md:14-80`; VERIFIED).

**Dual-era rules** (VERIFIED: normative in `basic_versioning.md:128-185`, `basic_transports_stdio.md:128-154` and `basic_transports_streamable-http.md:645-663`).
- *stdio:* send `server/discover` first, carrying modern `_meta`.
  - A `DiscoverResult` means a modern server.
  - A recognised modern error such as `-32022` also means a modern server: pick a version from `data.supported` and do **not** fall back.
  - Any other error, or no answer within a reasonable timeout, means a legacy server: use `initialize`.
  - The spec says: "The fallback MUST NOT be keyed to one specific error code".
- *HTTP:* send a modern request first.
  - On a `400`, look at the body. A recognised modern JSON-RPC error (`-32022`, `-32021`, `-32020`) means a modern server.
  - Otherwise fall back to `initialize`. If the server returns `400`, `404` or `405` with no modern error body, try the old HTTP+SSE transport next.
- Cache the era per server process (stdio) or per origin (HTTP). A client MAY persist the era across restarts.

**Adoption** (VERIFIED):

| Implementation | Latest version it supports | Evidence |
|---|---|---|
| Pi MCP client | 2025-11-25 (also 2025-06-18, 2025-03-26, 2024-11-05) | `pi/packages/mcp/src/protocol/types.ts:4,9` |
| mcptools 1.0.3 | 2025-11-25 (from 2024-11-05) | `src/mcptools/R/protocol-version.R:1-6` |
| mcplite 0.1.0 | 2025-11-25 (also 2025-06-18, 2024-11-05) | `src/mcplite/R/protocol.R:1-5` |
| Claude Code 2.1.261 `claude mcp serve` | 2025-11-25 | answered `server/discover` with -32601; `initialize` returned `serverInfo {name: "claude/tengu", version: "2.1.261"}` and 27 tools (`test_interop.out`) |

### 2.2 JSON-RPC shapes and error codes

**Messages.**
- MCP messages are JSON-RPC 2.0 in UTF-8.
- Request ids are strings or integers, never `null`, and unique among the sender's in-flight requests.
- Notifications carry no `id` and get no response.
- JSON-RPC batching was removed in 2025-06-18.
- In 2026-07-28 every result carries `resultType`. When a legacy server omits it, the client must treat the result as `"complete"` (`basic_index.md:57-87`).

**Error codes** (2026-07-28 `basic_index.md:111-157`; VERIFIED):

| Code | Meaning |
|---|---|
| -32700 / -32600 / -32601 / -32602 / -32603 | Parse error / Invalid request / Method not found / Invalid params / Internal error |
| -32000..-32019 | legacy, implementation-defined; new code SHOULD NOT use them |
| -32020 | HeaderMismatch |
| -32021 | MissingRequiredClientCapability (`data.requiredCapabilities`) |
| -32022 | UnsupportedProtocolVersion (`data.supported`, `data.requested`) |
| -32002 | resource not found in 2025-11-25 and earlier; now -32602; clients SHOULD still accept it |
| -32042 | URL elicitation required (2025-11-25 only) |

**Two kinds of tool error.**
- A **protocol error** (unknown tool, malformed request) is returned as a JSON-RPC error.
- A **tool execution error** (API failure, invalid input) is returned as `result.isError = true` with an explanatory `content`. The spec says: "Clients SHOULD provide tool execution errors to language models to enable self-correction" (`server_tools.md:730-779`).
- The prototype server shows both: an unknown tool gets `-32602`, and an empty `x` gets a result with `isError: true` (`test_stdio.out`).

### 2.3 Lifecycle and capabilities

**Legacy lifecycle** (2025-11-25, `basic_lifecycle.md`; VERIFIED).
- Handshake:
  - The client sends `initialize` with `{protocolVersion, capabilities, clientInfo}`.
  - The server returns `{protocolVersion, capabilities, serverInfo, instructions?}`.
  - The client sends `notifications/initialized`. Only `ping` (and server logging) may be sent before this handshake completes.
- Shutdown:
  - stdio: close stdin, wait, then SIGTERM, then SIGKILL.
  - HTTP: close the connections; `DELETE` with `Mcp-Session-Id` ends the session.
- Client capabilities: `roots{listChanged}`, `sampling{context?, tools?}`, `elicitation{form?, url?}`, `tasks`, `experimental`.
- Server capabilities: `prompts{listChanged}`, `resources{subscribe, listChanged}`, `tools{listChanged}`, `logging`, `completions`, `tasks`, `experimental`.
- `instructions` "MAY be added to the system prompt" (`schema-2025-11-25.ts:279-298`).

**Modern lifecycle** (2026-07-28).
- Per-request metadata. Each client request carries in `params._meta`:
  - `io.modelcontextprotocol/protocolVersion` (required);
  - `io.modelcontextprotocol/clientCapabilities` (required; `{}` is allowed);
  - `io.modelcontextprotocol/clientInfo` (SHOULD);
  - `io.modelcontextprotocol/logLevel` (optional, deprecated).
- A request missing a required field gets `-32602`, which is HTTP 400 on the HTTP transport.
- A server that needs a capability the client did not declare must answer `-32021` (`basic_index.md:367-395`).
- Every result SHOULD carry `_meta["io.modelcontextprotocol/serverInfo"]`.
- `server/discover` returns `{supportedVersions, capabilities, instructions?, ttlMs, cacheScope}`.
- Capabilities gain an `extensions` map (for example `io.modelcontextprotocol/tasks`, `io.modelcontextprotocol/ui`).
- Roots, sampling and logging are deprecated. The earliest removal is the first revision released on or after 2027-07-28 (`deprecated.md`).
- **Statelessness.** A stdio process is not a session. Any state that spans calls must be an explicit handle passed as an ordinary tool argument (`basic_index.md:184-221`; `server_tools.md`, section "Stateful Tools").

### 2.4 Tools

- **`tools/list`.**
  - Paginated: the request takes `params.cursor`; the result has `tools[]` and `nextCursor?`. Cursors are opaque.
  - In 2026-07-28 the result is also *cacheable*:
    - it carries `ttlMs` (at least 0) and `cacheScope` (`public` or `private`);
    - the cache key is the method plus its parameters;
    - retries under MRTR must not be cached (`server_utilities_caching.md`).
  - Servers SHOULD return tools in a deterministic order.
  - The tool set MUST NOT vary per connection, but MAY vary with the authorization presented (`server_tools.md:59-74`).
- **Tool definition.**
  - `name` SHOULD be 1-128 characters from `[A-Za-z0-9_.-]`, case-sensitive and unique per server. Clients that aggregate several servers SHOULD disambiguate, for example with a server prefix.
  - Optional display fields: `title?`, `description?`, `icons?`.
  - `inputSchema` is a JSON Schema with `type: "object"`; the default dialect is 2020-12. Since 2026-07-28 any 2020-12 keyword is allowed, and clients must not automatically fetch `$ref` URIs over the network.
  - `outputSchema?` has an object root in 2025-11-25 and can be any schema in 2026-07-28.
  - `annotations?` carries the hints `title`, `readOnlyHint` (default false), `destructiveHint` (default true), `idempotentHint` (default false) and `openWorldHint` (default true). Treat these hints as **untrusted** unless the server is trusted (`schema-2025-11-25.ts:1180-1227`).
  - `execution.taskSupport` exists in 2025-11-25 only. Plus `_meta`.
- **`tools/call`.** `params {name, arguments?}` returns `{content: ContentBlock[], structuredContent?, isError?}`.
  - `ContentBlock` is one of:
    - `text{text}`
    - `image{data (base64), mimeType}`
    - `audio{data, mimeType}`
    - `resource_link{uri, name, title?, description?, mimeType?, size?}`
    - `resource{resource: {uri, mimeType?, text | blob}}`
  - Every block may carry `annotations{audience[], priority (0..1), lastModified}` and `_meta`.
  - `structuredContent` must be an object in 2025-11-25 and may be any JSON value in 2026-07-28. A server that returns it SHOULD also return the same JSON serialised in a text block. Clients SHOULD validate it against `outputSchema` when one is given.
- **Multi round-trip requests (MRTR, 2026-07-28).**
  - `tools/call`, `resources/read` and `prompts/get` may return `{resultType: "input_required", inputRequests?, requestState?}`. Each entry of `inputRequests` maps a key to an `ElicitRequest`, `CreateMessageRequest` or `ListRootsRequest`.
  - The client then retries the original request with a **new id**, adding `inputResponses` (key to result) and echoing `requestState` byte-for-byte (`basic_patterns_mrtr.md:126-265`).
- **`x-mcp-header` (HTTP only).** A property in the input schema may carry `x-mcp-header: "Region"`.
  - HTTP clients MUST send that argument's value as the header `Mcp-Param-Region`.
  - HTTP clients MUST drop any tool whose annotation is invalid.
  - stdio clients may ignore the annotation (`basic_transports_streamable-http.md:357-567`).

### 2.5 Resources, prompts, completion

**Resources.**
- `resources/list` (paginated) returns `Resource{uri, name, title?, description?, mimeType?, size?, annotations?, icons?}`.
- `resources/templates/list` returns `ResourceTemplate{uriTemplate, ...}`.
- `resources/read {uri}` returns `contents[]`, each either `{uri, mimeType?, text}` or `{uri, mimeType?, blob}`.
- Change notifications:
  - legacy: `resources/subscribe` followed by `notifications/resources/updated`;
  - modern: `subscriptions/listen` with `{notifications: {resourceSubscriptions: [uri]}}`.

**Prompts.**
- `prompts/list` returns `Prompt{name, title?, description?, arguments?: [{name, description?, required?}]}`.
- `prompts/get {name, arguments: {string: string}}` returns `{description?, messages: [{role, content: ContentBlock}]}`.

**Completion.** `completion/complete` completes prompt arguments and resource-template arguments.

**Mapping into gptr.**
- MCP prompts become slash commands such as `/mcp:<server>:<prompt> args`.
- Resources become an R function plus an `@server:uri` mention.
- Claude Code does the same (LIKELY; MCP docs summary).

### 2.6 Client features: roots, sampling, elicitation

- **Roots.** `roots/list` returns `{roots: [{uri: "file://...", name?}]}`. Deprecated in 2026-07-28: pass directories as tool parameters instead.
- **Sampling.** `sampling/createMessage {messages, systemPrompt?, maxTokens, modelPreferences?, tools?, toolChoice?, includeContext?}` returns `{role, content, model, stopReason}`. Deprecated in 2026-07-28, with the advice "Integrate directly with LLM provider APIs". gptr could route sampling requests to its own providers, with user approval; this is low priority.
- **Elicitation (not deprecated).**
  - Two modes:
    - Form mode sends `{mode: "form", message, requestedSchema: {type: "object", properties: {primitive schemas}}}`, and the answer is `{action: accept | decline | cancel, content?}`.
    - URL mode sends `{mode: "url", message, url}`. 2025-11-25 also had `elicitationId` and `notifications/elicitation/complete`; both were removed in 2026-07-28.
  - How the request arrives:
    - In the legacy era these are **server-to-client JSON-RPC requests** that can arrive while a `tools/call` is in flight: on stdio, interleaved on stdout; on HTTP, inside the POST's SSE stream.
    - In the modern era they arrive inside an `InputRequiredResult`.
  - In gptr, form mode maps to REQ-36 (ask the user) in interactive sessions. Non-interactive runs decline.
  - The prototype dispatcher answers `ping` and refuses every other server request with `-32601`.

### 2.7 Progress, cancellation, logging, ping, change notifications

- **Progress.**
  - The client asks for progress by putting a `progressToken` in `_meta`.
  - The server then sends `notifications/progress {progressToken, progress (increasing), total?, message?}`.
  - A client MAY reset its request timeout on each progress notification, but SHOULD keep a hard maximum.
  - The prototype resets its timeout on progress and caps the total at `10 * timeout`.
- **Cancellation.**
  - stdio: the client MUST send `notifications/cancelled {requestId, reason?}`.
  - Modern HTTP: closing the SSE response stream *is* the cancellation.
  - Legacy HTTP: the client SHOULD send an explicit `notifications/cancelled`, and a disconnect "SHOULD NOT be interpreted as the client cancelling its request" (2025-11-25 `basic_transports.md:126-129`).
  - Senders SHOULD ignore responses that arrive after they cancelled.
  - Prototype (VERIFIED, `test_interrupt.out`): a real SIGINT arrived after 1.1 s, the client sent `notifications/cancelled`, and the late response was dropped.
  - A single-threaded R server only sees the cancellation after its blocking work finishes: the server log shows "client cancelled request 2" about 3.2 s into a 3 s job.
- **Logging.**
  - Legacy: the client sends `logging/setLevel {level}`, and the server sends `notifications/message {level, logger?, data}`. Levels: debug, info, notice, warning, error, critical, alert, emergency.
  - Modern: the client sets `_meta` `io.modelcontextprotocol/logLevel` per request. Servers MUST NOT emit log notifications for requests that did not set it.
  - Deprecated in 2026-07-28: servers should log to stderr instead.
- **Ping.** Legacy `ping` returns `{}` and works in both directions. Removed in 2026-07-28.
- **List-changed notifications.**
  - Legacy: `notifications/{tools,prompts,resources}/list_changed` can arrive at any time.
  - Modern: they arrive only on an opted-in `subscriptions/listen` stream. The first message on that stream is `notifications/subscriptions/acknowledged`. Every notification carries `_meta["io.modelcontextprotocol/subscriptionId"]`, whose value is the id of the listen request.
  - The prototype marks its tool cache stale on `notifications/tools/list_changed`.

### 2.8 Transports

**stdio** (both eras; VERIFIED: `spec/2026-07-28/basic_transports_stdio.md:12-33, 92-126`; `spec/2025-11-25/basic_transports.md:22-52`).
- One JSON-RPC message per line, with no embedded newlines.
- The server writes nothing but MCP messages to stdout. It may write UTF-8 logs to stderr, and clients SHOULD NOT treat stderr output as an error.
- In 2026-07-28 the server also MUST NOT send JSON-RPC requests on stdout.
- Shutdown:
  - The client closes the server's stdin, waits, and then forces termination.
  - "Servers SHOULD exit promptly when their standard input is closed".
  - If the server dies, the client SHOULD restart it.

Implementation facts (VERIFIED by execution unless noted):

1. **Reading in chunks.** processx `$read_output()` returns **at most 8192 characters per call**: 611 reads for 5 MB.
   - A naive reader that re-pastes and re-scans a growing buffer after every read is quadratic. It took 2.33-3.16 s for a 3.6 MB line across three runs, one of them the verification re-run (`test_naive_buffer.out`).
   - The chunk-vector pump took 0.54-0.98 s for the same line across three runs, UTF-8 intact (`test_large.out`).
   - Measured with processx 3.8.6. CRAN's current processx is 3.9.0 (2026-04-22). It adds `$read_output_bytes()` and `encoding = "binary"`, which return raw vectors, so gptr could frame on bytes instead of characters. The 8192-character chunk size has not been re-measured on 3.9.0. An earlier run took 1.1-1.4 s for a 7.2 MB line. Both timings include the server's time to generate the line.
   - The chunk-vector pump drains up to 512 chunks per poll and keeps partial lines as a vector of pending chunks.
   - Two 60 s timeouts I hit on the way were **not** caused by the reader. The fake server `cat()`-ed UTF-8 text in a C locale, which is quadratically slow (2.17).
2. **Writing.** `$write_input()` is non-blocking and returns the unwritten remainder, so the caller must loop until it is empty (processx docs). Send raw bytes, `charToRaw(json)`, so that processx does not re-encode the text into a C-locale native encoding.
3. **Server stderr.** Point the server's stderr at a **file** (`stderr = path`). A chatty server can then never block on a full pipe, and the file doubles as a diagnostic log. Pi keeps a 64 KiB stderr tail for the same reason (`pi/packages/mcp/src/transports/stdio.ts:7`).
4. **Framing limits.** Pi caps one message at 16 MiB (`transport.ts:3`) and strips a trailing `\r` before `JSON.parse` (`stdio.ts:199`). gptr should do both.
5. **Stopping wrapper processes.** Pi kills the whole process group on POSIX. On Windows it runs `taskkill /pid N /T /F`, because `npx` and `uvx` wrappers otherwise leave the real server running (`stdio.ts:17-41`, `docs/mcp.md:87`). The R equivalent is processx `cleanup_tree = TRUE` plus `$kill_tree()`, which uses ps (LIKELY on Windows; not run there).
6. **Windows batch files.** processx documents that `.bat` and `.cmd` files should be run as `process$new("cmd.exe", c("/c", "call", bat_file, ...))` (VERIFIED from `process.Rd`, section "Batch files"). R's `Sys.which()` searches for `.exe`, `.com`, `.cmd` and `.bat`, and returns short paths on Windows (VERIFIED from `Sys.which.Rd`).

**Streamable HTTP, legacy era** (2025-03-26 to 2025-11-25; VERIFIED, `spec/2025-11-25/basic_transports.md:54-279`). The server has one endpoint that accepts POST and GET.
- The client POSTs every message with `Accept: application/json, text/event-stream`.
- The server answers a request either with JSON or with an SSE stream. The stream may carry server requests and notifications before the final response.
- With 2025-11-25 polling, the server may close the stream early after sending an event id plus a `retry` hint. The client then resumes with a GET carrying `Last-Event-ID`.
- Client notifications and responses get `202`.
- Sessions:
  - The server may assign `Mcp-Session-Id` on the initialize response, and the client echoes it on every later request.
  - A `404` means the session has expired and the client must re-initialize.
  - `DELETE` ends the session.
- `MCP-Protocol-Version` goes on every request after initialize.
- A GET opens an optional stream from server to client (or the server answers `405`).
- The server MUST validate `Origin` (answering 403) and SHOULD bind to localhost.

**Streamable HTTP, modern era** (2026-07-28; VERIFIED, `basic_transports_streamable-http.md`).
- POST only: GET and DELETE should get `405`.
- No sessions and no resumability: a broken stream loses the request, which the client re-issues with a new id.
- Headers:
  - Every POST carries `MCP-Protocol-Version`, which must equal the version in the body's `_meta`, and `Mcp-Method`.
  - `tools/call`, `prompts/get` and `resources/read` also carry `Mcp-Name`.
  - A header value that is not plain ASCII is sent as `=?base64?<b64>?=`.
- Error statuses: a header/body mismatch gets `400` with -32020; an unknown method gets `404` with -32601; an unsupported version gets `400` with -32022.
- Streams: notifications about one request travel on that request's SSE stream, and change notifications travel on `subscriptions/listen`.
- The server should send `X-Accel-Buffering: no` and SSE comment keep-alives.

**HTTP+SSE (2024-11-05).**
- Deprecated since 2025-03-26, and formally Deprecated under SEP-2596.
- Pi rejects `type: "sse"`, noting that servers documenting an SSE endpoint usually also serve Streamable HTTP at `/mcp` (VERIFIED, `docs/mcp.md:45`).
- Recommendation: gptr v1 does not implement it and says so in the error message.

**SSE parsing.**
- The prototype used `httr2::resp_stream_sse()`, and it worked for streams that are not resumed (`test_http.out`: one progress notification, then the response).
- Report 06 showed that `resp_stream_sse()` drops empty-data events (losing the priming event's id) and ignores `retry`. That makes it unusable for **legacy** resumption. The verification pass confirmed this is unchanged in httr2 1.3.0: `parse_event()` returns NULL when `data == ""` and never reads a `retry` field (`R/resp-stream-sse.R`).
- I agree with 06: write a small SSE parser on top of `httr2::resp_stream_lines()` for the legacy era.

### 2.9 Authorization (HTTP only; stdio servers take credentials from the environment)

**Normative flow** (VERIFIED: 2026-07-28 `basic_authorization_index.md`, `basic_authorization_authorization-server-discovery.md`, `basic_authorization_client-registration.md`). 2025-11-25 is the same, except that there DCR is not deprecated and `iss` validation and `application_type` are not required.

1. The client sends the request without a token and gets `401` with `WWW-Authenticate: Bearer resource_metadata="...", scope="..."`.
2. It fetches the protected resource metadata (RFC 9728) from the header's `resource_metadata` URL. If the header has none, it tries `/.well-known/oauth-protected-resource/<path>`, then `/.well-known/oauth-protected-resource`. The metadata MUST list `authorization_servers`.
3. It fetches the authorization server (AS) metadata. For an issuer with a path, it tries these URLs in order:
   - `/.well-known/oauth-authorization-server/<path>`
   - `/.well-known/openid-configuration/<path>`
   - `<path>/.well-known/openid-configuration`

   For an issuer without a path, it tries `/.well-known/oauth-authorization-server` and then `/.well-known/openid-configuration`. The `issuer` in the document MUST equal the issuer used to build the URL.
4. It obtains a client identity, trying these in order:
   1. Pre-registered credentials for that issuer.
   2. **CIMD**, when the AS metadata has `client_id_metadata_document_supported`. The `client_id` is an HTTPS URL pointing to a JSON document with `client_id`, `client_name` and `redirect_uris`.
   3. **DCR** at `registration_endpoint`. It is deprecated, and the request MUST include `application_type` (`"native"` for CLI and desktop clients).
   4. Asking the user.

   Credentials are stored per issuer and never reused with another AS.
5. It runs the authorization-code flow with **PKCE S256**.
   - It sends `resource=<canonical MCP server URI>` in both the authorization request and the token request (RFC 8707).
   - It picks the scope from the challenge's `scope`, falling back to the metadata's `scopes_supported`.
   - It records `state` and the expected `iss`.
6. Before redeeming the code, it validates `iss` (RFC 9207):
   - If `iss` is present, compare it with the expected value.
   - If `iss` is absent but the AS advertises `authorization_response_iss_parameter_supported`, reject the response.
7. It sends `Authorization: Bearer <token>` on every request, never in the URL.
   - On `401` or token expiry, it refreshes the token.
   - On `403` with `insufficient_scope`, it re-authorises with the union of the old and new scopes.
8. PKCE is mandatory. The exact rule, re-read in verification, is in `basic_authorization_security-considerations.md:51-58`: clients "MUST verify PKCE support before proceeding", and when `code_challenge_methods_supported` is absent from the AS metadata they "MUST refuse to proceed". Using S256 comes from OAuth 2.1 section 7.5.2, which the spec cites. Refusing an AS that lists PKCE methods but not S256 is gptr policy, not a literal quote from the MCP spec. Report 06 notes that Pi deviates here; gptr should follow the spec.

**Read-only probes of real servers** (no credentials sent, no client registered; VERIFIED, `test_oauth_discovery.out`):

| Server | 401 challenge | PRM | AS | S256 | DCR | CIMD | `iss` supported |
|---|---|---|---|---|---|---|---|
| mcp.sentry.dev/mcp | resource_metadata | yes | mcp.sentry.dev | yes | yes | yes | yes |
| mcp.linear.app/mcp | resource_metadata, `scope="read write"` | yes | mcp.linear.app | yes | yes | yes | yes |
| mcp.notion.com/mcp | resource_metadata, `error="invalid_token"` | yes | mcp.notion.com | plain,S256 | yes | yes | no |
| api.githubcopilot.com/mcp/ | resource_metadata | yes | github.com/login/oauth | yes | **no** | **no** | yes |

What this means for gptr:
- (a) DCR alone covers Sentry, Linear and Notion today.
- (b) CIMD needs the maintainer to host a static JSON document at an HTTPS URL, for example on GitHub Pages. It is UNCERTAIN whether these servers accept a loopback redirect with any port. RFC 8252 says they should.
- (c) GitHub needs a PAT (`Authorization: Bearer ${GITHUB_TOKEN}`) or a pre-registered OAuth app.

**httr2 1.2.2** (VERIFIED by printing its source and running it offline, `test_oauth_pieces.out`). Available and usable:
- `oauth_flow_auth_code_pkce()` returns `{verifier, method: "S256", challenge}`.
- `oauth_flow_auth_code_url(client, auth_url, redirect_uri, scope, state, auth_params)` builds the authorization URL, including `resource` and the PKCE fields.
- `oauth_flow_auth_code_listen(redirect_uri)` starts `httpuv::startServer("127.0.0.1", port)` and returns the **whole** redirect query, including `iss`.
- `oauth_flow_auth_code_parse(query, state)` checks `state` and returns the `code`.

Gaps:
- `oauth_flow_auth_code()` neither checks `iss` nor exposes the code-for-token exchange; it calls the internal `oauth_client_get_token()`. gptr should POST the token request itself (`grant_type=authorization_code`, `code`, `redirect_uri`, `code_verifier`, `client_id`, `resource`), wrap the result with `oauth_token()`, and refresh with `oauth_flow_refresh()`.
- `oauth_token_cached(cache_disk = TRUE)` writes under `oauth_cache_path()`. That is `HTTR2_OAUTH_CACHE` if set; otherwise `rappdirs::user_cache_dir("httr2")` in 1.2.2 and `tools::R_user_dir("httr2", "cache")` in 1.3.0.
- `oauth_flow_auth_code_read()`, the "paste the code or URL" reader, is **not exported** in 1.2.2 or in 1.3.0 (checked against both NAMESPACE files). It also keeps only `code` and `state`, so it drops `iss`. gptr must implement its own paste-URL reader.
- httr2 1.3.0 is the current CRAN version; see the version note in section 1, item 8.

**mcptools' OAuth.** It runs DCR + PKCE through httr2's `oauth_token_cached()` (`client-auth.R:17-34, 44-76`). Its DCR metadata has no `application_type` (`client-auth.R:454-472`; `grep application_type` finds nothing), and it performs no `iss` check.

**Browser handling.** Following report 06: **never open a browser from a background connection**. Raise a classed condition that carries the challenge, and let the user run `mcp_login(server)`. For remote sessions (RStudio Server, Posit Workbench, SSH), offer "paste the redirect URL". Pi does this (`docs/mcp.md:101`). httr2 has an equivalent, `oauth_flow_auth_code_read`, but it is internal (`httr2:::`) and discards `iss`, so gptr needs its own.

### 2.10 Existing R implementations: build versus reuse

Sources: CRAN metadata comes from `packages.rds` (25,258 packages when researched; `tools::CRAN_package_db()` returned 25,273 during verification) and the saved CRAN pages. The verification pass re-checked every version, date and Imports list in this table against `tools::CRAN_package_db()` and `available.packages()`, and all matched. It also re-downloaded the mcptools 1.0.3 tarball from CRAN, and it is identical to the copy in `work/16/src/`. Source code was read from the tarballs in `work/16/src/`.

| Package | Version / date | Role | Transport and eras | Imports | Notes |
|---|---|---|---|---|---|
| **mcptools** (Posit) | 1.0.3 / 2026-09-18 | client (produces ellmer tools) and server | stdio and Streamable HTTP client with OAuth; legacy only | cli, **ellmer**, httpuv, httr2, jsonlite, **nanonext**, openssl, processx, promises, rlang, yaml | See the notes below the table. |
| mcplite | 0.1.0 / 2026-08-03 | server | stdio; 2024-11-05, 2025-06-18, 2025-11-25 | jsonlite, nanonext, otel | Uses `nanonext::read_stdin()` / `write_stdout()`. |
| btw (Posit) | 1.5.0 / 2026-09-09 | R context tools; MCP server via mcptools; skills | via mcptools | 22 packages (20 without base `methods`/`utils`), including ellmer, mcptools, dplyr | Spec-aware skill validation (`tool-skills.R:534-700`). Scans bundled skills, `inst/skills` of attached packages, `~/.btw/skills`, `~/.config/btw/skills`, `R_user_dir("btw")/skills`, `.btw/skills` and `.agents/skills`. |
| corteza | 0.7.1 / 2026-08-05 | agent runtime and MCP server | stdio or socket (`serve()`); `2024-11-05` default | callr, codetools, curl, digest, jsonlite, llm.api, printify, processx, saber | Live-session tools; sub-agent spending gates over MCP. |
| aisdk | 1.4.12 / 2026-06-02 | multi-provider SDK | only `openai_hosted_mcp_tool()` | many | No JSON-RPC client in its R code (grep). |
| mcpr (devOpifex) | GitHub / r-universe | client and server | - | - | Not on CRAN (VERIFIED). |
| MCPR (phisanti) | GitHub | live-session server over nanonext | - | - | Not on CRAN (LIKELY, from the README). |

Notes on mcptools (VERIFIED from its source):
- **Client:** the stdio client writes a request, sleeps `Sys.sleep(0.2)` up to 20 times, and returns only the first line it sees. It does no id matching, drops notifications, and gives up if the answer takes more than 4 s (`client.R:1318-1349`).
- **Client:** the HTTP client handles redirects and session expiry carefully, but "Stream resumability ... is intentionally unsupported" (`client-http.R:399`).
- **Client:** the environment allowlist for spawned servers is worth copying (`client.R:855-917`). The config file is `~/.config/mcptools/config.json` (`client.R:167-169`).
- **Server:** the server is a proxy that forwards `tools/call` to an interactive session over nanonext IPC. The session side runs handlers through a promise, so they execute only when the console is idle (`session.R:3-40, 350-355`).

**Decision: build gptr's own client and server.** This agrees with report 06. Reasons:
1. The only CRAN client (mcptools) is legacy-only, and its stdio reader is fragile.
2. mcptools pulls in ellmer (which gptr replaces), nanonext and promises.
3. The stateless 2026-07-28 revision requires era detection, which no R package implements.
4. The code is small: about 350 lines for the stdio client, 250 for the HTTP client and server together, 150 for config import, 250 for TOML, plus OAuth.
5. gptr must own the event loop, because it has to serve the live session while it waits on plan-provider subprocesses.

gptr should still read mcptools' config file as one more import source.

### 2.11 gptr as an MCP server for the live R session

**Why this is needed.**
- The `claude-code` and `codex` plan providers (REQ-12) must run tools such as `r_eval` **inside the user's session**, where the 5 GB object already lives (REQ-21, REQ-22). There the external agent is a child process of R.
- For external agents the user already runs (Claude Desktop, Cursor, VS Code), the agent is an unrelated process.

**Event-loop facts** (VERIFIED):
- The later 1.4.8 docs (`later.Rd`) say: "scheduled operations only run when there is no other R code present on the execution stack; i.e., when R is sitting at the top-level prompt. You can force past-due operations to run at a time of your choosing by calling `run_now()`." httpuv request handlers are later callbacks.
- The source of `httpuv::service` (1.6.17), printed:
  ```r
  function (timeoutMs = ifelse(interactive(), 100, 1000)) {
      if (is.na(timeoutMs)) { run_now(0, all = FALSE) }
      else if (timeoutMs == 0 || timeoutMs == Inf) {
          .globals$paused <- FALSE
          check_time <- if (interactive()) 0.1 else Inf
          while (!.globals$paused) { run_now(check_time, all = FALSE) }
      } else { run_now(timeoutMs/1000, all = FALSE) }
      TRUE
  }
  ```
  So **`httpuv::service(0)` never returns in Rscript.** My first test hung right after the child exited. macOS `sample` showed the main thread in `CallbackRegistry::wait` under `_later_execCallbacks`.
- **Pumping while waiting works.** Use `later::run_now(0.1)` or `httpuv::service(100)` in the loop.
  - The parent served 11 HTTP MCP requests from a child `Rscript` within 0.5-1.4 s, over 104-109 loop iterations.
  - The child's `r_eval` created `made_by_agent`, which existed in the parent afterwards (`test_http.out`).
  - Through the stdio bridge, `via_bridge_auto` and `via_bridge_legacy` also appeared in the parent (`test_bridge.out`).
- At an idle interactive console (RStudio, terminal R), handlers run automatically; mcptools' `mcp_session()` relies on this. I did not test it interactively (LIKELY, from the later docs). IRkernel/Jupyter is UNCERTAIN.

**Transport options:**

| Option | Used for | Pros | Cons |
|---|---|---|---|
| A. Claude Code "sdk" MCP over the stream-json control protocol (report 07) | the `claude -p` plan provider | no port and no token; verified live | Claude only; the protocol is documented only through the SDKs |
| **B. In-process Streamable HTTP server (httpuv)** | Codex (`-c mcp_servers.gptr.url=...`), fallback for Claude Code, HTTP-capable clients such as Claude Desktop, Cursor and VS Code | one implementation, both eras, verified here | needs httpuv and later (Suggests); serves only while R is idle or pumping; clients' HTTP idle timeouts |
| C. stdio bridge, `Rscript -e "gptr::mcp_bridge(url)"`, relaying to B | stdio-only clients | 37 lines; verified in both eras | one extra process; the token travels via an environment variable |
| D. mcptools-style nanonext IPC proxy | - | discovers multiple sessions | extra dependency; C already covers the use case |

**Security for option B.**
- Bind to `127.0.0.1` on a random port, and use a random 192-bit bearer token (`openssl::rand_bytes(24)`).
- Validate `Origin` (403) and `Authorization` (401).
- Route every call through gptr's permission layer (REQ-37). `r_eval` runs arbitrary code in the user's session, so it must be announced as such (`destructiveHint: true`).
- Pass the token through the child's environment, never on its command line. Report 07 warns about BatBadBut on Windows command lines.
- Verified: 401, 403, 405 and the header-mismatch 400 were all returned correctly.

**Timeouts.**
- Claude Code aborts idle HTTP MCP calls after 5 minutes, unless the server sends progress, the config sets a per-server `timeout`, or `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` is set (LIKELY, docs summary; report 07 found the same).
- Codex's `tool_timeout_sec` defaults to 60 s (LIKELY, docs summary). gptr can pass `-c mcp_servers.gptr.tool_timeout_sec=3600` (VERIFIED: Codex accepts it).
- httpuv cannot stream one response incrementally, so gptr should raise the client's timeouts rather than rely on progress notifications.

### 2.12 Harness MCP config formats and locations

Sources:
- Claude Code MCP docs (LIKELY, summary).
- modelcontextprotocol.io "Connect to local MCP servers" (Claude Desktop paths VERIFIED).
- Codex docs (fields LIKELY via a summary; the `-c` override and `codex mcp add --help` are VERIFIED).
- Cursor docs, the VS Code MCP reference and the Gemini CLI docs (LIKELY, summaries).
- Pi `docs/mcp.md` (VERIFIED, local file) and mcptools source (VERIFIED).

**Locations and top-level shape:**

| Harness | Files (user; project) | Top-level shape |
|---|---|---|
| Claude Code | user and local scopes: `~/.claude.json` (top-level `mcpServers` is user scope; `projects["<abs path>"].mcpServers` is local scope); project scope: `<project>/.mcp.json` | `mcpServers` |
| Claude Desktop | macOS `~/Library/Application Support/Claude/claude_desktop_config.json`; Windows `%APPDATA%\Claude\claude_desktop_config.json` (VERIFIED); Linux `~/.config/Claude/` is unofficial (UNCERTAIN) | `mcpServers` |
| Codex | `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`); `.codex/config.toml` | TOML `[mcp_servers.<name>]` |
| Cursor | `~/.cursor/mcp.json`; `.cursor/mcp.json` | `mcpServers` |
| VS Code | user-profile `mcp.json` (Windows `%APPDATA%\Code\User\mcp.json` LIKELY; macOS `~/Library/Application Support/Code/User/mcp.json` UNCERTAIN; separate folders per profile); workspace `.vscode/mcp.json`; also the "portable" `.mcp.json` at the workspace root and `~/.copilot/mcp-config.json` | `servers`, `inputs[]`, `sandbox` |
| Pi | `~/.pi/agent/mcp.json`; `.pi/mcp.json` (read only after project trust) | `mcpServers` |
| Gemini CLI | `~/.gemini/settings.json`; `.gemini/settings.json` | `mcpServers` |
| mcptools | `~/.config/mcptools/config.json` (or option `.mcptools_config`) | `mcpServers` |
| opencode (reference) | `opencode.json` | `mcp` |

**Server fields and variable syntax:**

| Harness | stdio fields | remote fields | variables |
|---|---|---|---|
| Claude Code | `type:"stdio"`, `command`, `args`, `env` | `type: "http"`, `"sse"` or `"ws"`; `url`, `headers`, `headersHelper`, `oauth{clientId, callbackPort, authServerMetadataUrl, scopes}`, `timeout` (ms), `alwaysLoad` | `${VAR}` and `${VAR:-default}` in command, args, env, url and headers; `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}` |
| Claude Desktop | `command`, `args`, `env` | (remote servers are app connectors) | none |
| Codex | `command`, `args`, `env`, `env_vars`, `cwd` | `url`, `bearer_token_env_var`, `http_headers`, `env_http_headers`, `http_headers_helper`, `auth` | through `env_vars` and the `*_env_var` fields |
| Cursor | `type`, `command`, `args`, `env`, `envFile` | `url`, `headers`, `auth{CLIENT_ID, CLIENT_SECRET, scopes}` | `${env:NAME}`, `${userHome}`, `${workspaceFolder}`, `${workspaceFolderBasename}`, `${pathSeparator}` |
| VS Code | `type`, `command`, `args`, `env`, `envFile`, `cwd`, `dev` | `type: "http"` or `"sse"`; `url`, `headers`, `oauth` | `${input:id}` (prompts the user; `password: true` hides input), `${env:VAR}`, `${workspaceFolder}`, `${userHome}` |
| Pi | `command`, `args`, `env`, `cwd` | `url`, `headers`, `oauth{clientId, clientSecret, callbackPort, callbackUrl, scope}` | `${NAME}`; `!command` for a whole value |
| Gemini CLI | `command`, `args`, `env`, `cwd` | **`url` means SSE**, **`httpUrl` means Streamable HTTP**; `headers` | `$VAR`, `${VAR}`, `%VAR%` on Windows |
| mcptools | `command`, `args`, `env` | `url`, `headers`, `timeout`, `allow_http`, `ignore_tools`, `oauth{...}` | `${ENVVAR}` in headers |
| opencode | `type:"local"`, `command` **as an array**, `environment` | `type:"remote"`, `url`, `headers` | `{env:NAME}` |

**Per-harness notes:**
- **Claude Code.**
  - When the same name appears in several scopes, precedence is local > project > user > plugin > claude.ai connectors.
  - Project `.mcp.json` servers need the user's approval ("Pending approval"; VERIFIED in `claude mcp --help`).
  - Corrected in verification: the current MCP docs contain no `cmd /c npx` advice for Windows. The raw page `code.claude.com/docs/en/mcp.md` has no "cmd /c". Claude Code 2.1.119 removed a "Windows requires 'cmd /c' wrapper" config warning as a false positive, so Claude Code apparently resolves `.cmd` shims itself (UNCERTAIN how). The importer should keep `command: "npx"` as written and let gptr's own `.cmd` handling apply.
- **Claude Desktop** writes its MCP logs to `~/Library/Logs/Claude/mcp*.log`.
- **Codex.**
  - Per-server fields: `enabled`, `required`, `enabled_tools`, `disabled_tools`, `startup_timeout_sec` (default 10), `tool_timeout_sec` (default 60) and `default_tools_approval_mode`.
  - CLI: `codex mcp add|get|list|login|logout|remove`. `add` supports `--url`, `--bearer-token-env-var` and `--oauth-client-registration AUTO|CIMD|DCR` (VERIFIED in `--help`).
- **Pi.**
  - Extra fields: `timeout` (seconds, default 60), `enabled`, `exposure`, `toolExposure`.
  - `type` must be `stdio`, `http` or `streamable-http`; `sse` is rejected.
  - Server names may use only `[A-Za-z0-9_-]`, and tools are named `mcp__<server>__<tool>` (VERIFIED, `docs/mcp.md:25-47, 122-148`).
- **Gemini CLI** also has `timeout` (ms, default 600000), `trust`, `includeTools` and `excludeTools`.
- **opencode** entries are described in Pi's conversion notes (`docs/mcp.md:59`).

**Pitfalls when importing:**
- `url` means SSE in Gemini but Streamable HTTP everywhere else.
- In opencode, `command` is an array.
- VS Code's `${input:...}` values need an interactive prompt.
- The project key inside `~/.claude.json` is an absolute path. On Windows its form (slash direction, letter case) is UNCERTAIN, so try both normalisations and compare case-insensitively.
- `~/.claude.json` also holds unrelated state and may hold secrets in `env` or `headers`. Read it; never rewrite it.

### 2.13 TOML in pure R (needed to read Codex config)

**CRAN options** (VERIFIED from packages.rds and the CRAN pages):

| Package | Version | How it is implemented |
|---|---|---|
| RcppTOML | 0.2.3 | compiled C++17 (toml++) |
| tomledit | 0.1.1 | Rust; needs Cargo to build |
| toml | 1.1.0 | imports V8 |
| configr | - | imports RcppTOML |

None of them fits REQ-01 or a lean dependency set.

**The prototype `toml_read()`** is base R only (242 lines) and implements TOML 1.0:
- basic, literal and multi-line strings, including escapes, 8-digit unicode escapes and the line-ending backslash;
- integers with `_` separators, and hex, octal and binary integers parsed through doubles (no int32 overflow);
- floats, including `inf`, `nan` and exponents;
- booleans;
- dates, kept as text;
- arrays, including nested and multi-line arrays, trailing commas and comments;
- inline tables;
- dotted and quoted keys;
- `[table]` and `[[array.of.tables]]` headers, including sub-tables of the last array element.

**Result** (VERIFIED, `test_toml.out`). I compared it with RcppTOML on a realistic 59-line Codex config. Each parser produced 39 values; 36 agree. In the 3 disagreements the pure-R reader is correct:

| Value | Pure R | RcppTOML | Cause |
|---|---|---|---|
| `0xDEAD_BEEF` | 3735928559 | -559038737 | int32 wraparound |
| `9_007_199_254_740_991` | 9007199254740991 | **-1** | 64-bit integer lost |
| empty nested array | `list()` | `NULL` | representation |

RcppTOML's default `escape = TRUE` also turns the literal `'C:\Users'` into `C:\\Users`; pass `escape = FALSE` to get correct strings.

### 2.14 Agent Skills

**The standard** (VERIFIED: agentskills.io/specification and agentskills.io/client-implementation/adding-skills-support, fetched today).

*Layout.* A skill is `skill-name/SKILL.md` (required), optionally with `scripts/`, `references/`, `assets/` and any other files.

*Frontmatter.*

| Field | Required | Constraint |
|---|---|---|
| `name` | yes | 1-64 characters, lowercase `a-z0-9-`, no leading, trailing or consecutive hyphen, must match the parent directory name |
| `description` | yes | 1-1024 characters; says what the skill does and when to use it |
| `license` | no | |
| `compatibility` | no | 1-500 characters |
| `metadata` | no | string-to-string map |
| `allowed-tools` | no | space-separated list; experimental |

*Progressive disclosure.*
- About 100 tokens of metadata per skill; the guide says 50-100 tokens per catalog entry.
- The body should stay under 5000 tokens, and `SKILL.md` under 500 lines.
- Bundled resources load only on demand, and references should be one level deep.
- The reference validator is `skills-ref validate ./my-skill`.

*Client guide.*
- **Discovery.**
  - Scan project and user scopes. In each, look in the client's own directory and in `.agents/skills/`. Scanning `.claude/skills/` is common too.
  - Skip `.git` and `node_modules`. Bound the depth (4-6 levels) and the directory count (about 2000).
  - Name collisions: project overrides user. Within one scope, pick first or last consistently and warn.
  - Gate project-level skills on trust.
- **Parsing.**
  - Be lenient. Quote unquoted values that contain colons. Warn, but still load, on a name mismatch or an over-long name. Skip a skill only if its description is missing or its YAML cannot be parsed.
  - Store `name`, `description` and `location`.
- **Catalog.**
  - Format: `<available_skills><skill><name/><description/><location/></skill></available_skills>`, placed either in the system prompt or in the description of the activation tool, with a short behavioural instruction.
  - Omit the catalog entirely when there are no skills, and hide skills marked `disable-model-invocation`.
- **Activation.**
  - Activate through a file read or a dedicated tool whose `name` parameter is an enum of skill names.
  - Return only the body (frontmatter stripped), wrapped in `<skill_content name="...">`, together with the skill's directory and a `<skill_resources>` list of files that are not read yet.
  - Also support `/skill-name` or `$skill-name` typed by the user.
- **After activation.** Allowlist the skill directories for reads, protect skill content from compaction, and deduplicate repeated activations. Running a skill in a sub-agent is optional.

**How other harnesses do it:**

| Harness | Where skills are found | Extras |
|---|---|---|
| Claude Code (LIKELY, docs summary) | enterprise managed dir; `~/.claude/skills/<n>/SKILL.md`; `.claude/skills/` (also nested `<subdir>/.claude/skills` and `--add-dir`); plugin `skills/`; skills synced from claude.ai | Details below the table. |
| Codex (LIKELY, docs summary) | `$CWD/.agents/skills`, its parents up to `$REPO_ROOT/.agents/skills`, `$HOME/.agents/skills`, `/etc/codex/skills`, and bundled skills. This machine also has a legacy `~/.codex/skills`, including `.system/`. | optional `agents/openai.yaml` with `interface{display_name, short_description, icon_small, icon_large, brand_color, default_prompt}`, `policy{allow_implicit_invocation}` and `dependencies{tools}`; invoke with `$skill-name`; the listing takes "at most 2% of the model's context window, or 8,000 characters when the context window is unknown" (re-fetched in verification: 8,000 is a fallback, not a floor); descriptions are shortened first; on a name collision both skills appear and are not merged (no project-over-user override is documented); disable with `[[skills.config]] path=..., enabled=false` |
| Pi (VERIFIED, source) | `~/.pi/agent/skills`, `.pi/skills`, `~/.agents/skills`, `.agents/skills` (ancestors up to the repository root), settings paths, packages | catalog code in `skills.ts:355-383`; `/skill:name args`; `disable-model-invocation`; first found wins, with a "collision" warning (`docs/skills.md:85`). **Corrected in verification: the project wins.** The runtime path (`resource-loader.ts:833-838`) calls `loadSkills(includeDefaults = false)` with paths that `package-manager.ts` sorts with `resourcePrecedenceRank()` (lines 181-197): project settings, then project auto-discovered (`.pi/skills`, `.agents/skills`), then user settings, then user auto-discovered, then packages. Only the unused `includeDefaults = TRUE` branch of `loadSkills()` scans the user directory first. Pi gives no warning on a name/directory mismatch (`docs/skills.md:83`). |

Claude Code details:
- **Precedence** is **enterprise > personal > project**. `.claude/commands/*.md` files count as skills.
- **Extra frontmatter fields:** `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context: fork`, `agent`, `background`, `hooks`, `paths`, `shell` (bash or powershell), `metadata`, `license`, `compatibility`.
- **Substitutions:** `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `$name`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`.
- **Dynamic context:** an inline ``!`cmd` `` or a fenced block opened with three backticks followed by `!` runs a shell command before the skill is sent; if the command fails, the invocation is aborted.
- **Listing budget:** `description` plus `when_to_use` is capped at **1,536 characters** per skill, and the whole listing at about **1% of the context window** (settings `skillListingBudgetFraction`, env `SLASH_COMMAND_TOOL_CHAR_BUDGET`). The per-entry cap can be changed with the `skillListingMaxDescChars` setting. When the listing overflows, descriptions of the least-invoked skills are dropped first. Verified against the docs text in the verification pass.
- **Compaction:** after compaction, the most recent invocation of each skill is re-attached: the first 5,000 tokens of each, 25,000 tokens in total.

**The real skills on this machine** (VERIFIED, `test_skills.out`).
- Scanned 48 roots:
  - `.gptr`, `.agents` and `.claude` in the project and its ancestors;
  - `~/.config/gptr`, `~/.agents`, `~/.claude`, `~/.codex` and `~/.pi/agent`;
  - the `skills/` folders of the 14 Claude Code plugins installed here.
- Loaded **161 skills in 0.19-0.37 s** (three runs; the verification re-run took 0.34 s and gave identical counts): 122 from plugins, 39 from user directories. 57 more were shadowed duplicates.
- No skill needed the lenient YAML fallback.
- Frontmatter fields actually used: `description` 161, `name` 161, **`version` 101 (not in the spec)**, `metadata` 95, `user-invocable` 3, `tags` 2, `license` 1.
- Body length: median 44 lines, maximum 1206; 10 bodies exceed 500 lines.
- The **catalog for all 161 skills is 64,537 characters, about 16k tokens**.
- The first implementation used `list.files(recursive = TRUE)` over the plugin caches (1.5 GB and 69,652 files, both confirmed with `find`/`du` in verification; 15 top-level `node_modules` trees, 797 including nested ones) and did not finish within 2 minutes.
- Report 05 counted 37 unique skills; the difference is the plugin skills.

### 2.15 Plugin formats

**Claude Code plugins** (the plugins-reference and marketplace-reference pages, fetched today; LIKELY, because they were read through a summary that quoted the tables). The verification pass re-checked parts of this against the raw docs text (`code.claude.com/docs/llms-full.txt`), and these are now VERIFIED:
- the manifest Fields table: `name` is the only required key;
- the semantics of `skills`, `commands`, `hooks` and `mcpServers` as described below;
- unknown top-level keys are stripped with a validator warning;
- `${CLAUDE_PLUGIN_DATA}` is `~/.claude/plugins/data/<id>/`;
- the hooks reference lists exactly 33 events.

*Manifest.* `.claude-plugin/plugin.json` is optional, and `name` is its only required key. Other fields:
- Metadata: `displayName`, `version`, `description`, `author{name, email, url}`, `homepage`, `repository`, `license`, `keywords`, `metadata`, `defaultEnabled`, `dependencies`, `settings`.
- `userConfig{key: {type, title, description, required, default, options, multiple, sensitive, min, max}}`.
- `channels`.
- Components:
  - `skills` adds to `skills/`;
  - `commands` replaces `commands/`;
  - `agents` replaces `agents/`;
  - `hooks` merges with `hooks/hooks.json`;
  - `mcpServers` merges with `.mcp.json` (and accepts `.mcpb` / `.dxt` bundles);
  - also `lspServers`, `outputStyles`, `workflows`, and `experimental{themes, monitors, evals}`.
- Paths must start with `./` and stay inside the plugin. Unknown top-level keys are stripped.

*Standard layout.* `skills/<n>/SKILL.md`, `commands/*.md`, `agents/*.md`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `output-styles/`, `workflows/*.js`, `themes/`, `monitors/monitors.json`, `bin/` (added to the Bash tool's PATH) and `settings.json`.

*Variables.*
- `${CLAUDE_PLUGIN_ROOT}`
- `${CLAUDE_PLUGIN_DATA}`, which is `~/.claude/plugins/data/<id>/`
- `${CLAUDE_PROJECT_DIR}`
- `${user_config.KEY}`
- Hooks also receive `CLAUDE_PLUGIN_OPTION_<KEY>`.

*Naming.* Components are namespaced `plugin:component`. MCP tools become `mcp__plugin_<plugin>_<server>__<tool>`; this session's own tool list includes `mcp__plugin_playwright_playwright__browser_click` (VERIFIED by observation).

*Agents* (sub-agents doc; LIKELY, summary).
- An agent is an `.md` file whose body is the system prompt.
- Frontmatter: `name` and `description` (required); `tools`, `disallowedTools`, `model` (`sonnet`, `opus`, `haiku`, `fable`, a full model id, or `inherit`), `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`.
- When names collide, managed agents win, then `--agents`, then `.claude/agents/`, then `~/.claude/agents/`, then plugin agents.

*Hooks* (LIKELY, summary).
- Shape: `{"hooks": {"<Event>": [{"matcher": "...", "hooks": [{"type": "command"|"http"|"prompt"|"agent"|"mcp_tool", ...}]}]}}`.
- About 33 events, including SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Stop, SubagentStop, PreCompact and SessionEnd.
- The hook receives JSON on stdin with `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input` and more.
- Exit code 2 blocks. The JSON output can carry `hookSpecificOutput.permissionDecision` among other fields.

*Marketplaces.*
- File: `.claude-plugin/marketplace.json` with `{name, owner{name}, plugins: [{name, source, ...}]}`.
- A plugin source is one of: a relative `./path`; `github{repo, ref, sha}`; `url{url, ref, sha}`; `git-subdir{url, path}`; `npm{package, version, registry}`; `archive{url, sha256}`; `command{command, timeout, mode}`.
- Many marketplace names are reserved.

*Installed-plugin registry* (VERIFIED on this machine).
- `~/.claude/plugins/installed_plugins.json` is `{version: 2, plugins: {"<name>@<marketplace>": [{scope, installPath, version, installedAt, lastUpdated, gitCommitSha}]}}`.
- Plugins are cached under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.
- Whether each plugin is enabled lives in settings (`enabledPlugins`), which I did not read.

**Pi packages** (VERIFIED, `docs/packages.md`).
- A package is an npm package, a git repository or a local directory, containing `extensions/`, `skills/`, `prompts/` and `themes/`, or declaring them in the `"pi"` key of `package.json` (with globs).
- Packages install per user or per project. Project packages load only after the project is trusted.

**Codex plugins.** codex-cli 0.157.0 has a `codex plugin` subcommand (VERIFIED `--help`). I did not research its format (UNCERTAIN).

### 2.16 Context cost

**Measured** (VERIFIED, `test_rfuns.out`). The same 27 MCP tools from Claude Code, in three representations:

| Representation | characters | about tokens |
|---|---|---|
| full `tools/list` JSON (descriptions and JSON Schemas) | 143,525 | 35,881 |
| R signature catalog: `name(arg: type, opt?: type)  # first sentence` | 5,899 | 1,475 |
| names only | 300 | 75 |

**How other harnesses and APIs keep this down:**
- **Claude Code** (LIKELY, docs summary): tool search is on by default and defers loading of MCP tools (`ENABLE_TOOL_SEARCH`). Output above `MAX_MCP_OUTPUT_TOKENS` (default 25,000) is written to disk instead.
- **Pi** (VERIFIED, `docs/mcp.md:122-158`, `docs/cli.md:140-182`):
  - The `exposure` setting controls how the model reaches MCP tools:
    - `codemode` (the default): tools are callable from QuickJS scripts, and TypeScript declarations are listed under a 3000-token budget, with BM25 `searchTools()` for the rest;
    - `codemode-deferred`;
    - `deferred`, through `tool_search`;
    - `direct`;
    - `hidden`.
  - `toolExposure` overrides the setting per tool.
  - Text results over 20 KB have their middle cut out, and the full text is saved to a temp file.
- **Anthropic Messages API** (VERIFIED, claude-api skill reference files):
  - The server tools `tool_search_tool_regex_20251119` and `tool_search_tool_bm25_20251119` search the other tools, which are marked `defer_loading: true`.
  - The search tool itself must not be deferred, and at least one tool must not be deferred; otherwise the request is a 400.
  - Tool schemas found by the search are appended, so the prompt cache survives.
  - The MCP connector uses `mcp_servers:[{type:"url", url, name, authorization_token?}]` plus `tools:[{type:"mcp_toolset", mcp_server_name}]`, with beta `mcp-client-2025-11-20`. Sending `mcp_servers` without the matching toolset is a validation error. "Anthropic makes the MCP connection server-side", so the server must be reachable from Anthropic's infrastructure, and a gptr server on 127.0.0.1 cannot be used. The "public servers only" wording is an inference (LIKELY); the reference files do not say it literally.
- **OpenAI Responses API** (LIKELY, from search results for developers.openai.com/api/docs/guides/tools-tool-search): a `tool_search` tool, with `defer_loading: true` on functions, namespaces or MCP servers; the advice is to keep each namespace under about 10 functions.

**Conclusion for gptr.** gptr's model already writes R, so "code mode" costs nothing extra.
- MCP tools become R closures, `mcp$<server>$<tool>(...)`, with formals derived from `inputSchema`. The prototype verifies this.
- Their results are R objects, which the model can filter before printing.
- Only compact signatures enter the prompt.

Design in 4.7.

### 2.17 Encoding and locale (all VERIFIED by execution)

Run conditions:
- `LANG` is empty in this agent environment, so `Sys.getlocale("LC_CTYPE")` is `C` and `l10n_info()$UTF-8` is FALSE.
- Servers launched by GUI apps, cron or containers are often in the same state.

Findings:

1. **`cat()` in a C locale.**
   - It prints UTF-8 text as `<U+00E9>`, which corrupts any JSON written to stdout.
   - It is also **quadratic in the number of non-ASCII characters**:

     | non-ASCII characters | time (original run) | time (verification re-run) |
     |---|---|---|
     | 25k | 0.27 s | 0.17 s |
     | 50k | 1.18 s | 0.71 s |
     | 100k | 4.79 s | 2.81 s |
     | 600k | **296 s** (not captured in a `.out` file) | **85 s** |

   - The same 600k string takes 0.00 s in a UTF-8 locale (`cat_c_locale.out`).
   - Absolute times depend on machine load; what is stable is the roughly 4x growth each time n doubles. Plan with "minutes for about 0.5M non-ASCII characters", not with a precise figure.
   - Verification also found the same `<U+00E9>` corruption with `cat(jsonlite::toJSON(x))` in the C locale. `toJSON()` itself returns correct UTF-8 bytes for UTF-8-marked input (`enc_probe.out`, re-run); the damage happens in `cat()`.
2. **Reading stdin.** In a C locale, `file("stdin", open = "r", encoding = "UTF-8")` fails on UTF-8 input with "invalid input found on input connection" and truncates the line. `file("stdin", open = "r")` plus `readLines(encoding = "UTF-8")` keeps the bytes intact (`68 c3 a9 20 f0 9f 98 80`) and marks them UTF-8.
3. **`file("stdout")`** creates a regular file named `stdout` in the working directory. Use `stdout()` instead.
4. **Raw output.** `writeLines(txt, stdout(), useBytes = TRUE)` writes UTF-8 bytes unchanged even in a C locale. It works, and the large-message test uses it. ASCII-escaped JSON is still the recommended default, because it is locale- and code-page-independent.
5. **String literals in source code** (`enc_probe.out`).
   - A backslash-u escape in an ASCII source file gives a correctly UTF-8-marked string in a C locale, and jsonlite writes it correctly.
   - A **raw UTF-8 byte sequence written directly in the source** is marked "unknown" (native) in a C locale. jsonlite then writes it as `"a<c3><a9>"`.
   - This is why CRAN requires ASCII R sources, which R CMD check enforces. It also means every string that enters gptr from outside (files, processes, sockets) must be marked UTF-8 before it is serialised.
   - The tool that wrote my prototype files turned backslash-u escapes into raw UTF-8. I caught this and converted all sources back to ASCII escapes; every test was re-run afterwards.
6. **Printed output in a C locale.** `capture.output(print(x))` of non-ASCII text prints `"h<U+00E9>llo"`, and that is what the model would see from `r_eval`. In a UTF-8 session it prints `"héllo 世界"` (`test_http.out` vs `test_http_utf8.out`). gptr cannot change the user's locale, but it must never make things worse in transport.

---

## 3. Exact specifications

All MCP shapes in this section come from the TypeScript schemas `schema-2025-11-25.ts` and `schema-2026-07-28.ts`. I re-downloaded both from `https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/<rev>/schema.ts` and they are byte-identical to the saved copies. The spec pages are under `https://modelcontextprotocol.io/specification/<rev>/...`.

### 3.1 Constants

```text
LATEST_PROTOCOL_VERSION (2026-07-28 schema) = "2026-07-28"     schema-2026-07-28.ts:30
LATEST_PROTOCOL_VERSION (2025-11-25 schema) = "2025-11-25"     schema-2025-11-25.ts:12
JSONRPC_VERSION = "2.0"
PARSE_ERROR -32700, INVALID_REQUEST -32600, METHOD_NOT_FOUND -32601, INVALID_PARAMS -32602, INTERNAL_ERROR -32603
HEADER_MISMATCH -32020, MISSING_REQUIRED_CLIENT_CAPABILITY -32021, UNSUPPORTED_PROTOCOL_VERSION -32022   (2026-07-28)
URL_ELICITATION_REQUIRED -32042   (2025-11-25 only)
Reserved _meta keys (2026-07-28): progressToken, io.modelcontextprotocol/protocolVersion, io.modelcontextprotocol/clientInfo,
  io.modelcontextprotocol/clientCapabilities, io.modelcontextprotocol/logLevel, io.modelcontextprotocol/subscriptionId,
  io.modelcontextprotocol/serverInfo (results), traceparent, tracestate, baggage
_meta key prefixes whose second label is "modelcontextprotocol" or "mcp" are reserved (io.modelcontextprotocol/, dev.mcp/, ...)
LoggingLevel: debug | info | notice | warning | error | critical | alert | emergency
ResultType: "complete" | "input_required" | <extension-defined>; an absent resultType means "complete"
Icon MIME types clients must support: image/png, image/jpeg (image/jpg); should support: image/svg+xml, image/webp
```

The 2026-07-28 major changes, condensed from `spec/2026-07-28/changelog.md`:
1. Protocol-level sessions and `Mcp-Session-Id` are removed (SEP-2567).
2. The `initialize` handshake is removed, and each request carries its version and capabilities in `_meta` (SEP-2575).
3. `server/discover` is added and servers must implement it.
4. The HTTP GET stream and `resources/subscribe` are replaced by `subscriptions/listen`.
5. `ping`, `logging/setLevel` and `notifications/roots/list_changed` are removed.
6. Tasks move to the extension `io.modelcontextprotocol/tasks` (SEP-2663).
7. MRTR is introduced (SEP-2322).
8. `resultType` is required in every result.
9. SSE resumability (`Last-Event-ID`) is removed.

Minor changes include: an `extensions` capability, OpenTelemetry `_meta` keys, deterministic `tools/list` order, `Mcp-Method` / `Mcp-Name` / `x-mcp-header`, `ttlMs` and `cacheScope`, resource-not-found moving from -32002 to -32602, `iss` validation, `application_type` in DCR, credentials bound to the issuer, full JSON Schema 2020-12 support, removal of URL-elicitation completion, and the new error code ranges.

Deprecated: Roots, Sampling, Logging, Dynamic Client Registration (in favour of CIMD), the HTTP+SSE transport, and `includeContext: "thisServer"` / `"allServers"`.

### 3.2 Methods by era

| Method | Direction | 2025-11-25 | 2026-07-28 | Notes |
|---|---|---|---|---|
| `initialize` | C->S | yes | **removed** | legacy handshake |
| `notifications/initialized` | C->S | yes | **removed** | |
| `server/discover` | C->S | - | **mandatory for servers** | stdio era probe |
| `ping` | both | yes | **removed** | |
| `tools/list` / `tools/call` | C->S | yes | yes (+ cache hints, MRTR) | |
| `resources/list`, `resources/templates/list`, `resources/read` | C->S | yes | yes (+ cache hints, MRTR on read) | |
| `resources/subscribe` / `resources/unsubscribe` | C->S | yes | **removed** (`subscriptions/listen`) | |
| `prompts/list` / `prompts/get` | C->S | yes | yes (MRTR on get) | |
| `completion/complete` | C->S | yes | yes | |
| `logging/setLevel` | C->S | yes | **removed** (`_meta` logLevel) | |
| `subscriptions/listen` | C->S | - | yes | long-lived response stream |
| `roots/list` | S->C request | yes | only inside `InputRequiredResult` | deprecated |
| `sampling/createMessage` | S->C request | yes | only inside `InputRequiredResult` | deprecated |
| `elicitation/create` | S->C request | yes | only inside `InputRequiredResult` | |
| `tasks/get`, `tasks/result`, `tasks/list`, `tasks/cancel` | both | experimental | moved to an extension | |
| `notifications/cancelled` | C->S (S->C only to end a listen) | yes | yes (stdio only; HTTP closes the stream instead) | |
| `notifications/progress` | S->C | yes | yes | |
| `notifications/message` | S->C | yes | only if the request set `_meta` logLevel | deprecated |
| `notifications/{tools,prompts,resources}/list_changed` | S->C | yes | only on `subscriptions/listen` | |
| `notifications/resources/updated` | S->C | yes | only on `subscriptions/listen` | |
| `notifications/subscriptions/acknowledged` | S->C | - | first message on a listen stream | |
| `notifications/roots/list_changed` | C->S | yes | **removed** | |
| `notifications/elicitation/complete` | S->C | yes | **removed** | |

### 3.3 Message examples

Legacy `initialize` and its response (2025-11-25, `basic_lifecycle.md:55-147`, abridged):

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25",
 "capabilities":{"roots":{"listChanged":true},"sampling":{},"elicitation":{"form":{},"url":{}}},
 "clientInfo":{"name":"ExampleClient","title":"Example Client Display Name","version":"1.0.0"}}}

{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25",
 "capabilities":{"logging":{},"prompts":{"listChanged":true},"resources":{"subscribe":true,"listChanged":true},"tools":{"listChanged":true}},
 "serverInfo":{"name":"ExampleServer","title":"Example Server Display Name","version":"1.0.0"},
 "instructions":"Optional instructions for the client"}}

{"jsonrpc":"2.0","method":"notifications/initialized"}
```

Modern `server/discover` and its response (2026-07-28, `server_discover.md`):

```json
{"jsonrpc":"2.0","id":"discover-1","method":"server/discover","params":{"_meta":{
  "io.modelcontextprotocol/protocolVersion":"2026-07-28",
  "io.modelcontextprotocol/clientInfo":{"name":"ExampleClient","version":"1.0.0"},
  "io.modelcontextprotocol/clientCapabilities":{}}}}

{"jsonrpc":"2.0","id":"discover-1","result":{"resultType":"complete","supportedVersions":["2026-07-28"],
  "capabilities":{"tools":{},"resources":{}},
  "_meta":{"io.modelcontextprotocol/serverInfo":{"name":"ExampleServer","version":"1.0.0"}},
  "instructions":"This server provides weather and resource utilities.","ttlMs":3600000,"cacheScope":"public"}}
```

`UnsupportedProtocolVersionError` (HTTP 400; `basic_versioning.md:56-69`):

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32022,"message":"Unsupported protocol version",
  "data":{"supported":["2026-07-28","2025-11-25"],"requested":"1900-01-01"}}}
```

`tools/list` result, modern (the legacy result lacks `resultType`, `ttlMs` and `cacheScope`):

```json
{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","tools":[{"name":"get_weather","title":"Weather Information Provider",
  "description":"Get current weather information for a location",
  "inputSchema":{"type":"object","properties":{"location":{"type":"string","description":"City name or zip code"}},"required":["location"]},
  "annotations":{"readOnlyHint":true}}],
  "nextCursor":"next-page-cursor","ttlMs":300000,"cacheScope":"public"}}
```

`tools/call` with structured output, and an execution error:

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_weather_data","arguments":{"location":"New York"},
  "_meta":{"progressToken":"abc123","io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}

{"jsonrpc":"2.0","id":5,"result":{"resultType":"complete",
  "content":[{"type":"text","text":"{\"temperature\": 22.5, \"conditions\": \"Partly cloudy\", \"humidity\": 65}"}],
  "structuredContent":{"temperature":22.5,"conditions":"Partly cloudy","humidity":65}}}

{"jsonrpc":"2.0","id":4,"result":{"resultType":"complete","content":[{"type":"text",
  "text":"Invalid departure date: must be in the future. Current date is 08/08/2025."}],"isError":true}}
```

Content blocks (schema `ContentBlock`):

```json
{"type":"text","text":"...","annotations":{"audience":["user","assistant"],"priority":0.9,"lastModified":"2025-01-12T15:00:58Z"}}
{"type":"image","data":"<base64>","mimeType":"image/png"}
{"type":"audio","data":"<base64>","mimeType":"audio/wav"}
{"type":"resource_link","uri":"file:///project/src/main.rs","name":"main.rs","description":"...","mimeType":"text/x-rust"}
{"type":"resource","resource":{"uri":"file:///project/src/main.rs","mimeType":"text/x-rust","text":"fn main() {...}"}}
{"type":"resource","resource":{"uri":"...","mimeType":"application/pdf","blob":"<base64>"}}
```

Progress and cancellation:

```json
{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"abc123","progress":50,"total":100,"message":"Reticulating splines..."}}
{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"123","reason":"User requested cancellation"}}
```

MRTR: the interim result, then the retry. The retry needs a **new id**, the same arguments, `inputResponses`, and `requestState` echoed back exactly (`basic_patterns_mrtr.md`, `server_tools.md:174-234`):

```json
{"jsonrpc":"2.0","id":2,"result":{"resultType":"input_required","inputRequests":{"github_login":{"method":"elicitation/create",
  "params":{"mode":"form","message":"Please provide your GitHub username",
  "requestedSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}}},
  "requestState":"eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..."}}

{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_weather","arguments":{"location":"New York"},
  "inputResponses":{"github_login":{"action":"accept","content":{"name":"octocat"}}},
  "requestState":"eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..."}}
```

MRTR is allowed only on `prompts/get`, `resources/read` and `tools/call`. `inputRequests` values must be `elicitation/create`, `sampling/createMessage` or `roots/list`. A server must not ask for input types the client did not declare in its capabilities.

`subscriptions/listen` (modern):

```json
{"jsonrpc":"2.0","id":1,"method":"subscriptions/listen","params":{"_meta":{...},
  "notifications":{"toolsListChanged":true,"resourceSubscriptions":["file:///project/config.json"]}}}
{"jsonrpc":"2.0","method":"notifications/subscriptions/acknowledged","params":{"_meta":{"io.modelcontextprotocol/subscriptionId":1},
  "notifications":{"toolsListChanged":true,"resourceSubscriptions":["file:///project/config.json"]}}}
{"jsonrpc":"2.0","method":"notifications/resources/updated","params":{"_meta":{"io.modelcontextprotocol/subscriptionId":1},"uri":"file:///project/config.json"}}
```

Legacy elicitation result: `{"action":"accept"|"decline"|"cancel","content":{"field": <string|number|boolean|string[]>}}`. Its form schema allows only primitive properties: string (with optional format), number or integer, boolean, and enums (titled or untitled, single or multi-select).

Sampling request params (legacy): `{messages:[{role, content}], modelPreferences?:{hints:[{name}], costPriority, speedPriority, intelligencePriority}, systemPrompt?, includeContext?:"none"|"thisServer"|"allServers", temperature?, maxTokens, stopSequences?, metadata?, tools?, toolChoice?:{mode:"auto"|"required"|"none"}}`. The result is `{role, content, model, stopReason?: "endTurn"|"stopSequence"|"maxTokens"|"toolUse"}`.

### 3.4 HTTP transport details

| Item | Legacy (2025-03-26..2025-11-25) | Modern (2026-07-28) |
|---|---|---|
| Endpoint | one URL; POST, plus optional GET SSE; DELETE ends the session | one URL; POST only; GET/DELETE return 405 |
| Request headers | `Accept: application/json, text/event-stream`; `Content-Type: application/json`; `MCP-Protocol-Version: <negotiated>` after initialize; `Mcp-Session-Id` if the server assigned one; `Last-Event-ID` on a resume GET | `Accept` and `Content-Type` as before; **required** `MCP-Protocol-Version` (must equal the version in `_meta`), `Mcp-Method`, `Mcp-Name` (tools/call, prompts/get, resources/read), and `Mcp-Param-{Name}` for `x-mcp-header` properties |
| Header value encoding | - | a value that is not printable ASCII, has leading or trailing whitespace, or looks like the sentinel is sent as `=?base64?<Base64(UTF-8)>?=`; the markers are case-sensitive |
| Posting a notification or response | 202, no body | 202 (no client notifications are defined for HTTP) |
| Posting a request | 200 with `application/json`, or `text/event-stream` (requests and notifications, then the response) | 200 JSON or SSE (request-scoped notifications, then the response) |
| Server errors | 400 invalid version; 404 unknown or expired session; 403 bad Origin | 400 plus -32020 / -32021 / -32022 / -32602; 404 plus -32601; 403 bad Origin |
| Session | `Mcp-Session-Id` (visible ASCII 0x21-0x7E; should be cryptographically random) | none (the header is ignored) |
| Resumability | SSE `id` plus GET with `Last-Event-ID`; the server sends `retry` before closing | none |
| Cancellation | explicit `notifications/cancelled`; a disconnect is **not** a cancellation | closing the SSE stream **is** the cancellation |
| Proxy hints | - | response header `X-Accel-Buffering: no`; SSE comment keep-alive lines `:` |

**Legacy HTTP+SSE fallback (client side).** POST to the URL. If that returns 400, 404 or 405 with no modern JSON-RPC error body, send a GET to the same URL and wait for an SSE `endpoint` event whose data is the POST URL.

### 3.5 Authorization: exact endpoints and parameters

```text
401 challenge:  WWW-Authenticate: Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource", scope="files:read"
403 step-up:    WWW-Authenticate: Bearer error="insufficient_scope", scope="files:write", resource_metadata="...", error_description="..."
PRM fallbacks:  https://host/.well-known/oauth-protected-resource/<endpoint path>   then   https://host/.well-known/oauth-protected-resource
AS metadata:    issuer with path  /tenant1 -> /.well-known/oauth-authorization-server/tenant1, /.well-known/openid-configuration/tenant1,
                                             /tenant1/.well-known/openid-configuration
                issuer w/o path          -> /.well-known/oauth-authorization-server, /.well-known/openid-configuration
AS metadata fields used: issuer, authorization_endpoint, token_endpoint, registration_endpoint, code_challenge_methods_supported (must contain S256),
                client_id_metadata_document_supported, authorization_response_iss_parameter_supported, scopes_supported,
                token_endpoint_auth_methods_supported
Authorization request: response_type=code, client_id, redirect_uri, scope, state, code_challenge, code_challenge_method=S256,
                resource=<canonical MCP URI, e.g. https://mcp.example.com/mcp>
Token request:  grant_type=authorization_code, code, redirect_uri, code_verifier, client_id[, client_secret], resource=<same>
Refresh:        grant_type=refresh_token, refresh_token, resource; offline_access may be added only if the AS lists it in scopes_supported
Resource use:   Authorization: Bearer <token>   on every HTTP request; never in the query string
```

CIMD document, served at the HTTPS URL that is also the `client_id` (`basic_authorization_client-registration.md`):

```json
{"client_id":"https://app.example.com/oauth/client-metadata.json","client_name":"Example MCP Client",
 "client_uri":"https://app.example.com","logo_uri":"https://app.example.com/logo.png",
 "redirect_uris":["http://127.0.0.1:3000/callback","http://localhost:3000/callback"],
 "grant_types":["authorization_code"],"response_types":["code"],"token_endpoint_auth_method":"none"}
```

The DCR body gptr should send. This is my composition following RFC 7591 and the MCP rules; `application_type` is required in 2026-07-28:

```json
{"client_name":"gptr (R)","redirect_uris":["http://127.0.0.1:<port>/callback"],"grant_types":["authorization_code","refresh_token"],
 "response_types":["code"],"token_endpoint_auth_method":"none","application_type":"native","client_uri":"https://cran.r-project.org/package=gptr",
 "software_id":"gptr","software_version":"<version>","scope":"<scope from challenge or PRM>"}
```

### 3.6 Config file examples (one per harness)

Claude Desktop (`claude_desktop_config.json`), Cursor (`mcp.json`), Pi (`mcp.json`) and mcptools (`config.json`) all use:

```json
{"mcpServers":{"filesystem":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/Users/username/Desktop"]},
               "docs":{"url":"https://example.com/mcp","headers":{"Authorization":"Bearer ${DOCS_TOKEN}"}}}}
```

Claude Code: `.mcp.json` (project) and `~/.claude.json` (user plus local):

```json
{"mcpServers":{"api-server":{"type":"http","url":"${API_BASE_URL:-https://api.example.com}/mcp",
   "headers":{"Authorization":"Bearer ${API_KEY}"}},
  "local-db":{"type":"stdio","command":"uvx","args":["mcp-server-sqlite","--db-path","${CLAUDE_PROJECT_DIR:-.}/data.db"]}}}

{"mcpServers":{"github":{"type":"http","url":"https://api.githubcopilot.com/mcp/"}},
 "projects":{"/abs/path/to/project":{"mcpServers":{"local-db":{"type":"stdio","command":"uvx","args":["mcp-server-sqlite"]}}}}}
```

Codex `config.toml`:

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
env = { MY_ENV_VAR = "MY_ENV_VALUE" }
startup_timeout_sec = 20
tool_timeout_sec = 60

[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
bearer_token_env_var = "FIGMA_OAUTH_TOKEN"
http_headers = { "X-Figma-Region" = "us-east-1" }
enabled_tools = ["get_file"]
```

VS Code `.vscode/mcp.json`:

```json
{"inputs":[{"type":"promptString","id":"perplexity-key","description":"Perplexity API Key","password":true}],
 "servers":{"perplexity":{"type":"stdio","command":"npx","args":["-y","server-perplexity-ask"],"env":{"PERPLEXITY_API_KEY":"${input:perplexity-key}"}},
            "remote":{"type":"http","url":"https://example.com/mcp","headers":{"Authorization":"Bearer ${env:TOKEN}"}}}}
```

Gemini CLI `settings.json` (note that `url` means SSE and `httpUrl` means Streamable HTTP):

```json
{"mcpServers":{"pythonTools":{"command":"python","args":["-m","my_mcp_server"],"cwd":"./srv","env":{"API_KEY":"${EXTERNAL_API_KEY}"},"timeout":15000},
               "streamy":{"httpUrl":"https://s.example.com/mcp","headers":{"Authorization":"Bearer $TOKEN"},"excludeTools":["delete_all"]}}}
```

Codex `-c` override that points Codex at gptr's live-session server. Executed: `codex mcp get gptr_probe_zz -c 'mcp_servers.gptr_probe_zz.url="http://127.0.0.1:9/mcp"' -c 'mcp_servers.gptr_probe_zz.bearer_token_env_var="GPTR_MCP_TOKEN"' -c 'mcp_servers.gptr_probe_zz.tool_timeout_sec=3600' --json`. Output (VERIFIED):

```json
{"name":"gptr_probe_zz","enabled":true,"disabled_reason":null,
 "transport":{"type":"streamable_http","url":"http://127.0.0.1:9/mcp","bearer_token_env_var":"GPTR_MCP_TOKEN",
              "http_headers":null,"env_http_headers":null,"http_headers_helper":null},
 "enabled_tools":null,"disabled_tools":null,"startup_timeout_sec":null,"tool_timeout_sec":3600.0}
```

Claude Code equivalent (report 07 verified the "sdk" variant live). An HTTP entry passed with `--mcp-config '<json>' --strict-mcp-config` is `{"mcpServers":{"gptr":{"type":"http","url":"http://127.0.0.1:<port>/mcp","headers":{"Authorization":"Bearer <token>"},"timeout":3600000}}}` (LIKELY; the flags themselves are VERIFIED in `claude --help`).

### 3.7 Agent Skills: file and prompt formats

`SKILL.md`:

```markdown
---
name: r-plot
description: Make publication-quality ggplot2 figures from objects in the live R session. Use when the user asks for a plot.
license: MIT
compatibility: Requires R >= 4.1 and ggplot2
metadata:
  author: gptr
  version: "1.0"
allowed-tools: r read
---
# R plots
Read references/theme.md, then ... Task: $ARGUMENTS
```

The catalog placed in the system prompt, with the same structure as Pi's `formatSkillsForPrompt` (`skills.ts:355-382`) and the agentskills.io guide:

```xml
The following skills provide specialized instructions for specific tasks.
When a task matches a skill's description, load it with the skill tool (or read the SKILL.md at <location>).
Resolve relative paths in a skill against its directory.

<available_skills>
  <skill>
    <name>r-plot</name>
    <description>Make publication-quality ggplot2 figures ...</description>
    <location>/abs/path/.gptr/skills/r-plot/SKILL.md</location>
  </skill>
</available_skills>
```

What activation returns (agentskills.io "Structured wrapping"):

```xml
<skill_content name="r-plot">
# R plots
...body with $ARGUMENTS and ${CLAUDE_SKILL_DIR} substituted...

Skill directory: /abs/path/.gptr/skills/r-plot
Relative paths in this skill are relative to the skill directory.
<skill_resources>
  <file>references/theme.md</file>
</skill_resources>
</skill_content>
```

Limits:

| Limit | Value |
|---|---|
| `name` | 1-64 characters, `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, no `--` |
| `description` | 1-1024 characters |
| `compatibility` | at most 500 characters |
| body (recommended) | under 5000 tokens and under 500 lines |
| Claude Code listing entry | 1,536 characters |
| Claude Code listing total | about 1% of the context window |
| Claude Code after compaction | 5,000 tokens per skill, 25,000 tokens in total |
| Codex listing | 2% of the context window (8,000 characters only when the context window is unknown) |
| agentskills.io scan bounds | depth 4-6, about 2000 directories |

### 3.8 Claude Code plugin files

`.claude-plugin/plugin.json`. This is an abridged copy of the full example in the plugins reference (LIKELY verbatim, via the fetch tool):

```json
{"name":"deploy-tools","displayName":"Deploy Tools","version":"1.2.0",
 "description":"Deployment commands, a review agent, and a status monitor",
 "author":{"name":"Example Team","email":"dev@example.com","url":"https://example.com"},
 "homepage":"https://example.com/docs/deploy-tools","repository":"https://github.com/example/deploy-tools",
 "license":"MIT","keywords":["deployment","ci"],"defaultEnabled":true,"dependencies":["secrets-vault"],
 "skills":["./extra-skills/"],
 "commands":{"status":{"source":"./commands/status.md","description":"Show the current deployment status"}},
 "agents":["./agents/reviewer.md"],"hooks":"./config/extra-hooks.json",
 "mcpServers":{"deploy-api":{"command":"node","args":["${CLAUDE_PLUGIN_ROOT}/server.js"]}},
 "userConfig":{"api_token":{"type":"string","title":"API token","description":"Token for the deployment API","sensitive":true}}}
```

`.claude-plugin/marketplace.json` (minimal):

```json
{"name":"my-marketplace","owner":{"name":"Team"},"plugins":[
  {"name":"formatter","source":"./plugins/formatter"},
  {"name":"remote","source":{"source":"github","repo":"your-org/formatter","ref":"v2.0.0"}}]}
```

`~/.claude/plugins/installed_plugins.json` (VERIFIED structure on this machine):

```json
{"version":2,"plugins":{"skill-creator@claude-plugins-official":[{"scope":"user",
  "installPath":"/Users/<u>/.claude/plugins/cache/claude-plugins-official/skill-creator/3b600518a637",
  "version":"3b600518a637","installedAt":"2026-04-06T19:58:02.477Z","lastUpdated":"2026-09-11T06:30:08.840Z",
  "gitCommitSha":"4587d153de1d3f75469e9b73df995a5383658d2c"}]}}
```

Agent file (`agents/*.md`):

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
---
You are a code reviewer. ...
```

`hooks/hooks.json`:

```json
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/block-rm.sh","args":[]}]}]}}
```

### 3.9 Numeric limits and defaults worth copying

| Item | Value | Source |
|---|---|---|
| processx `read_output()` chunk | 8192 characters | executed |
| Pi stdio maximum message size | 16 MiB | `pi/packages/mcp/src/transports/transport.ts:3` |
| Pi stderr tail kept | 64 KiB | `stdio.ts:7` |
| Pi stdin-close grace before SIGTERM / SIGKILL delay | 500 ms / 2000 ms | `stdio.ts:8-10, 165-177` |
| Pi per-request timeout | 60 s, reset by progress | `docs/mcp.md:28` |
| Pi first-prompt wait for server connections | 10 s | `docs/mcp.md:64` |
| Pi retries | HTTP 408/429/5xx retried twice on connect; resource reads once; tool calls never | `docs/mcp.md:64, 172` |
| Pi text-result truncation | 20 KB (middle cut, full text in a temp file) | `docs/mcp.md:156` |
| Pi codemode declaration budget | 3000 tokens | `docs/cli.md:174` |
| Claude Code `MAX_MCP_OUTPUT_TOKENS` | 25,000 (warning at 10,000) | docs (LIKELY) |
| Claude Code tool idle timeout | 5 min HTTP/SSE/WS, 30 min stdio (`CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`) | docs (LIKELY) |
| Codex `startup_timeout_sec` / `tool_timeout_sec` | 10 / 60 | docs (LIKELY) |
| Gemini CLI `timeout` | 600,000 ms | docs (LIKELY) |
| mcptools session response timeout | 2 min (`mcptools.session_response_timeout_seconds`) | mcptools NEWS 1.0.0 |
| MCP tool name | 1-128 characters `[A-Za-z0-9_.-]` (SHOULD) | `server_tools.md` |
| Provider tool names (Anthropic/OpenAI) | keep to `^[a-zA-Z0-9_-]{1,64}$` | UNCERTAIN; the conservative intersection |

---

## 4. Recommended design for gptr

### 4.1 Files and dependencies

**Source files.** Everything is internal unless the file is marked "exported".

| File | Contents |
|---|---|
| `R/json.R` | `json_ascii()`, `to_json()` (ASCII-only output; `auto_unbox`, `null = "null"`, `digits = NA`), `from_json()` (`parse_json(simplifyVector = FALSE)`), `empty_obj()` |
| `R/mcp-protocol.R` | version constants, `_meta` builders, result normalisation, error classes |
| `R/mcp-stdio.R` | processx transport: spawn, pump, send, close; Windows `.cmd` handling |
| `R/mcp-http.R` | httr2 transport: JSON and SSE responses (own SSE parser on `resp_stream_lines()`), legacy sessions, modern headers |
| `R/mcp-oauth.R` | PRM/AS discovery, pre-registration, CIMD, DCR, PKCE flow with `iss` validation, token store keyed by issuer |
| `R/mcp-client.R` | exported: connection manager, `mcp_*()` API, era detection and cache, MRTR loop, tool cache |
| `R/mcp-config.R` | exported: gptr `mcp.json`, importers for other harnesses, placeholder interpolation, trust gating |
| `R/mcp-rfuns.R` | the `mcp` environment of R closures, signatures, search |
| `R/mcp-server.R` | exported: `mcp_serve()` (httpuv), request handlers for both eras, `mcp_bridge()` |
| `R/toml.R` | `toml_read()`, internal |
| `R/skills.R` | exported: discovery, parsing, catalog, activation tool |
| `R/plugins.R` | exported: gptr and Claude plugin loading, and the mapping tables |

**DESCRIPTION.**
- `Imports: jsonlite, processx, httr2, yaml`, plus whatever other tracks need (cli, rlang, and so on). Added in verification: pin `httr2 (>= 1.2.3)`, since current CRAN is 1.3.0 and mcptools already requires 1.2.3. The OAuth findings in 2.9 were re-read against the 1.3.0 source.
- `Suggests: httpuv, later, openssl`. openssl is already an import of httr2, so it adds nothing.
- `Depends: R (>= 4.2)`. Before 4.2, Windows R used a non-UTF-8 native encoding.
- Do **not** depend on mcptools, ellmer, nanonext, promises, RcppTOML, toml, tomledit or V8.

### 4.2 Data structures

The server specification is a plain named list. The importer returns it and the config stores it. It extends `mcp_server_spec()` from the prototype:

```r
list(name = "github", transport = "stdio" | "http",          # "sse" is recognised but refused in v1
     command = "npx", args = c("-y", "..."), env = list(K = "${K}"), cwd = NULL,
     url = NULL, headers = list(Authorization = "Bearer ${GITHUB_TOKEN}"),
     bearer_token_env_var = NULL, oauth = list(clientId = NULL, clientSecret = NULL, callbackPort = NULL, scope = NULL),
     enabled = TRUE, timeout = 60, protocol = "auto" | "modern" | "legacy",
     exposure = "r" | "direct" | "deferred" | "hidden", tool_exposure = list("delete_*" = "hidden"),
     tools_allow = NULL, tools_deny = NULL,
     source = list(harness = "claude-code", scope = "project", path = ".../.mcp.json"),
     also_in = c("claude-desktop:user"), needs_input = FALSE, trusted = TRUE)
```

The connection is an environment with S3 class `gptr_mcp_conn`. Fields:
- `name`, `spec`, `transport` ("stdio" or "http"), `era` ("modern" or "legacy"), `version`.
- `server_info`, `server_capabilities`, `instructions`.
- stdio: `proc`, `pending` (a character vector of chunks), `stderr_file`.
- HTTP: `session_id` (legacy only), `oauth` (a token record).
- `next_id`, and the environments `responses`, `cancelled` and `progress_cb`.
- `tools_cache` (with `fetched_at` and `ttl_ms`), `tools_stale`.

Connections live in an internal environment inside the package namespace, keyed by server name. They are created lazily on first use, reused for the life of the R session (this agrees with report 06), and closed by a finalizer registered with `reg.finalizer(onexit = TRUE)`.

A tool result has S3 class `gptr_mcp_result`:
- `content`: the raw list of blocks.
- `structured`: parsed `structuredContent`, or NULL.
- `is_error`: logical.
- `text`: the model-facing text, built by the `format()` method as in the prototype.
- `images`: blocks ready for vision models.
- `server`, `tool`, `elapsed`.

`as.list()` and `print()` methods are provided. In code mode, the R value the model sees is `structured`, or `text` when there is no structured content. An error result raises `gptr_mcp_tool_error` inside R code, so the model sees a normal R error.

### 4.3 Public API (proposed signatures)

```r
# configuration (REQ-30)
mcp_servers(project = ".", import = TRUE, include_disabled = FALSE)      # data frame view of gptr + imported servers
mcp_add(name, command = NULL, args = character(), env = NULL, url = NULL, headers = NULL,
        scope = c("user", "project"), exposure = "r", timeout = 60, ...)
mcp_remove(name, scope = c("user", "project"))
mcp_import(from = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi", "gemini", "mcptools"),
           names = NULL, scope = "user")        # explicit copy into gptr's own mcp.json (never edits other files)

# connection & use
mcp_connect(server, timeout = 30)                # usually implicit
mcp_disconnect(server = NULL)                    # NULL = all
mcp_tools(server = NULL, refresh = FALSE)        # tibble-free data frame: server, tool, title, description, exposure, annotations
mcp_call(server, tool, ..., .args = NULL, .timeout = NULL, .progress = interactive())
mcp_search(query, n = 5, server = NULL)          # BM25 over name + description (report 06 has a verified BM25 port)
mcp_describe(server, tool)                       # prints signature + JSON schema
mcp_resources(server); mcp_read(server, uri); mcp_prompts(server); mcp_prompt(server, name, ...)
mcp_login(server); mcp_logout(server)            # OAuth; never triggered implicitly from a background call

# code mode (Track E): an environment with one sub-environment per server
mcp                                              # exported object; mcp$github$search_code(query = "x"); lazily populated

# gptr as a server (REQ-12 plan providers, external agents)
mcp_serve(tools = c("r_eval", "r_objects", "r_plot"), envir = globalenv(),
          port = NULL, token = NULL, host = "127.0.0.1", log = FALSE)     # returns list(url, token, stop)
mcp_serve_stop()
mcp_bridge(url, token_env = "GPTR_MCP_TOKEN")    # for Rscript -e "gptr::mcp_bridge('http://127.0.0.1:PORT/mcp')"
```

When the `mcp_*` functions run interactively, gptr's permission layer (REQ-37) applies to them just as it does to model-initiated calls. The model-facing tools are:
- no extra tool when exposure is `"r"`: calls go through gptr's existing R tool;
- the declared `mcp__<server>__<tool>` tools when exposure is `"direct"`;
- a `tool_search` tool when exposure is `"deferred"`;
- the internal resource tools `mcp_read_resource` and `mcp_list_resources`, added only when a server has resources.

### 4.4 gptr's own config file

- **Locations:** `tools::R_user_dir("gptr", "config")/mcp.json` (user) and `.gptr/mcp.json` (project; read only after the project is trusted).
- **Format:** the `mcpServers` shape, so entries copy straight from Claude Desktop, Claude Code, Cursor and Pi, with a few extra fields:

```json
{
  "mcpServers": {
    "github":   {"url": "https://api.githubcopilot.com/mcp/", "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"},
                 "exposure": "r", "toolExposure": {"delete_*": "hidden", "search_code": "direct"}},
    "sentry":   {"url": "https://mcp.sentry.dev/mcp"},
    "sqlite":   {"command": "uvx", "args": ["mcp-server-sqlite", "--db-path", "${workspaceFolder}/data.db"], "timeout": 120},
    "imported": {"enabled": false}
  },
  "import": {"harnesses": ["claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi", "gemini"], "projectScopes": false},
  "defaults": {"exposure": "r", "timeout": 60, "protocol": "auto"}
}
```

Rules:
- `type` is optional. `command` means stdio and `url` means HTTP. `"sse"` gets an actionable error.
- `timeout` is in seconds, as in Pi.
- `${VAR}`, `${VAR:-default}`, `${env:VAR}`, `{env:VAR}`, `${workspaceFolder}` and `${userHome}` are expanded at connect time, never when the file is loaded. Secrets are never written back.
- **Precedence:**
  1. gptr project config;
  2. gptr user config;
  3. imported servers, in the order claude-code (local, then project, then user), claude-desktop, codex (project, then user), cursor, vscode, pi, gemini, mcptools.
- An imported server whose command, args and url are identical to one already seen is merged into it (listed in `also_in`).
- An imported server whose name collides with an existing one is renamed `<harness>_<name>`.
- **Importing** is on by default for **user-level** files only. Project-level files from other harnesses (`.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`, `.codex/config.toml`) start stdio commands, so they are imported only for trusted projects. This follows Claude Code's approval step and Pi's project trust. An open question (7.3) is whether import should be on by default at all.

### 4.5 Algorithms

**Connect.**
1. Resolve the spec and expand its placeholders.
2. stdio:
   - `mcp_resolve_command()`: `Sys.which()`; on Windows, run `.cmd`/`.bat` through `cmd.exe /d /c call`.
   - Environment: an allowlist plus the spec's `env` (copy mcptools' list at `client.R:855-917`). Never pass the whole environment; this avoids leaking keys.
   - `stderr` goes to a per-server log file under `tools::R_user_dir("gptr", "cache")/mcp-logs/`, rotated at 5 MB as Pi does. Keep a 64 KiB tail in memory for error messages.
3. Era detection:
   - If an era is cached for this spec, use it. The cache key is a hash of `command+args` or of the URL origin, and it lives in the cache directory with a 7-day expiry.
   - Otherwise probe:
     - **stdio:** send `server/discover` with a probe timeout of 5 s by default. A result means modern. `-32022` means modern: choose from `data.supported`. Anything else, or a timeout, means legacy: send `initialize` with 2025-11-25, check the chosen version, then send `notifications/initialized`.
     - **HTTP:** POST `server/discover` with the modern headers. A 200 result means modern. A 4xx whose body is a recognised modern error means modern (retry with a supported version). A 401 goes to the OAuth handling below. Any other 4xx means legacy: POST `initialize`, keep `Mcp-Session-Id` and the negotiated version, then POST `notifications/initialized`.
   - If a cached assumption fails later, re-probe once.
4. Record `serverInfo`, `capabilities` and `instructions`. The instructions are appended to the MCP section of the system prompt, truncated to about 2k characters per server.

**Request (stdio).**
- Assign ids from a per-connection counter.
- Modern era: add `_meta` (version, capabilities, client info).
- Add `_meta.progressToken` when a progress callback is registered.
- Send ASCII JSON as raw bytes, looping until `write_input()` has written everything.
- Pump loop:
  - `poll_io(50)`, then drain up to 512 chunks, split into lines, strip `\r`, parse each line and dispatch it.
  - Responses are parked by id; responses to cancelled ids are dropped.
  - Notifications go to handlers: progress resets the deadline; `list_changed` marks the cache stale; log messages go to the log file.
  - Legacy server requests: `ping` gets `{}`; `elicitation/create` goes to ask-user (REQ-36) or is declined when non-interactive; `roots/list` gets the project directory as a `file://` root (only if roots were declared); `sampling/createMessage` is refused with -32601 unless the user enabled sampling.
- Deadlines: a soft deadline equal to the timeout, reset by progress, and a hard deadline of 10x the timeout. When either passes, or the user interrupts, send `notifications/cancelled` and raise a classed condition.
- If the process exits, fail all pending requests; the next call restarts the server.

**Request (HTTP).**
- Build the headers:
  - modern: `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` from `x-mcp-header` in the cached tool schema (drop tools whose annotation is invalid);
  - legacy: `MCP-Protocol-Version` plus `Mcp-Session-Id`;
  - both: `Authorization` when OAuth or static headers apply.
- Send with `req_perform_connection()` and handle the response:
  - JSON body: parse it.
  - SSE: parse with the own parser. Deliver notifications to their handlers. Legacy server requests are answered with a POST. Stop when the response with our id arrives.
  - `401`: run the OAuth handling (when no token yet, and interactive: raise `gptr_mcp_auth_required`, which `mcp_login()` resolves). `403 insufficient_scope`: step up.
  - `404` with a session id: re-initialize once.
- Cancel by closing the connection (modern). In the legacy era, also POST `notifications/cancelled`.
- Legacy resumption: GET with `Last-Event-ID`, honouring `retry`. Worth implementing only if a real server needs it; mcptools skips it.

**MRTR loop** (modern `tools/call`, `resources/read`, `prompts/get`):
1. Call the request.
2. While the result has `resultType == "input_required"`, and for at most 5 rounds:
   - For each entry of `inputRequests`, fulfil it with the same handlers used for legacy server requests.
   - Retry with a new id, the original params, `inputResponses`, and `requestState` echoed exactly.
3. Never cache MRTR results.

**Tool list cache.**
- Memory plus disk: `R_user_dir("gptr", "cache")/mcp-tools/<hash>.json`, holding the tools, `fetched_at`, `ttl_ms` and `cache_scope`.
- A modern `ttlMs` sets freshness. A legacy server is refreshed on connect and on `list_changed`.
- The disk cache lets gptr build signatures and run `mcp_search()` before connecting (report 06 recommends the same).
- Cache only when `cacheScope` is not "private" or the credentials are the user's own.

**Result conversion.**
- Text blocks are concatenated. Results over 20 KB are middle-truncated, with the full text saved to `tempfile()`; the note says where, as Pi does.
- Images go to vision-capable models as images; otherwise they become a placeholder plus a file path.
- Resource links become `[resource_link uri]` plus a hint to use `mcp_read()`. Embedded resources are text or a saved blob.
- `structuredContent` is parsed; in R code mode it is simplified with `jsonlite::fromJSON(simplifyVector = TRUE)` on demand.

**Names for direct exposure.**
- `mcp__<server>__<tool>`, with every character outside `[A-Za-z0-9_-]` replaced by `_`.
- If the name exceeds 64 characters, truncate to 55 and add `_` plus the first 8 hex digits of its SHA-1.
- Keep a map back to `(server, tool)`.

**Shutdown.**
- On `mcp_disconnect()` or session end: close stdin, wait `grace` (2 s), `kill_tree()`.
- HTTP legacy: send `DELETE` with the session id.

### 4.6 gptr as an MCP server (live session)

- **`mcp_serve()`** starts the httpuv server from the prototype (`mcp_session_server()`).
  - It serves both eras, binds to 127.0.0.1 on a random port, and requires a random bearer token (`openssl::rand_bytes(24)`).
  - It checks Origin; GET and DELETE get 405 in the modern era.
  - For a legacy client it keeps sessions only to satisfy the protocol; no state is attached to a session.
  - Tools: `r_eval` (code, evaluated in `envir`, with output captured through report 01's evaluate/capture machinery rather than the prototype's bare `capture.output`), `r_objects` (REQ-21 summaries), and `r_plot` (returns an image block).
  - Every call passes through gptr's permission gate (REQ-37). The call must appear in the session history document (REQ-24/25) as the R code that was executed. This is what makes "agents running tools inside the live session" reproducible.
- **Plan providers (REQ-12).**
  - **Claude Code:** use report 07's "sdk" MCP over stream-json control messages as the default. Use the HTTP server as a fallback, passed with `--mcp-config <tmpfile> --strict-mcp-config` and a large `timeout`.
  - **Codex:** start `mcp_serve()`. Spawn `codex exec` with `-c mcp_servers.gptr.url=...`, `-c mcp_servers.gptr.bearer_token_env_var="GPTR_MCP_TOKEN"` and `-c mcp_servers.gptr.tool_timeout_sec=3600`. Put the token in the child's `env`.
  - **Waiting:** while the child runs, loop `later::run_now(0.1)` together with reading the child's JSONL output (processx `poll()` with a 100 ms timeout). **Never call `httpuv::service(0)`.**
  - **Interrupts:** Esc/Ctrl-C (REQ-38) inside that loop must stop the child (processx `interrupt()`, then `kill_tree()`) and stop the server.
- **External agents** the user runs themselves (Claude Desktop, Cursor, VS Code, Codex app):
  - `gptr::mcp_serve()` prints ready-to-paste config snippets for each client: an HTTP entry with the token header, or a stdio entry that runs `Rscript -e "gptr::mcp_bridge(url)"` with `GPTR_MCP_TOKEN` in `env`.
  - Requests are served while the console is idle, because later runs at the top level. While R is busy, clients wait; set generous timeouts.
  - Warn the user that anything the agent executes runs in their session.

### 4.7 Context cost policy (Track E)

- **Default exposure `"r"`.**
  - Every MCP tool is an R function, reached as `mcp$<server>$<tool>(...)` inside the R tool.
  - The R tool's description gets a compact catalog: one signature line per tool, `name(arg: type, opt?: type)  # first sentence`, grouped by server, within a budget of 3000 tokens by default. The budget is configurable, and Pi uses the same number.
  - Servers that do not fit get a line like `github: 37 more tools, use mcp_search("...")`.
  - `mcp_search()` and `mcp_describe()` are ordinary R functions the model can call.
  - The server's `instructions` go into the same section.
- **Per-tool overrides** (`toolExposure` globs, as in Pi):
  - `"direct"` for a few tools the model should call natively (for example read-only search). These are declared as provider tools with the MCP `inputSchema` passed through and strict mode off.
  - `"deferred"` uses provider-native tool search: Anthropic `tool_search_tool_bm25_20251119` with `defer_loading: true`, or OpenAI `tool_search` with `defer_loading`. Where the provider has neither, it falls back to gptr's own `tool_search` tool, which declares matches on the next turn; report 06 prototyped this.
  - `"hidden"`.
- **Results in `"r"` mode:**
  - The function returns an R value, so the model can reduce it, for example `res <- mcp$github$list_issues(repo = "x"); nrow(res)`, before anything is printed.
  - Only what the R tool prints reaches the model, and it passes through the usual output truncation (REQ-23 and the R-tool track).
- **Annotations are untrusted.**
  - `readOnlyHint: true` may auto-allow a call in intermediate permission modes only when the server is marked trusted in gptr's config. Otherwise every MCP call counts as potentially side-effecting.

### 4.8 Skills (REQ-28)

- **Discovery roots, in order; first found wins:**
  1. `.gptr/skills`, then `.agents/skills`, then `.claude/skills`, for the project and each ancestor up to the git root (only for trusted projects);
  2. `R_user_dir("gptr", "config")/skills`, `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills` (legacy Codex; skip `.system`), `~/.pi/agent/skills`;
  3. `inst/gptr/skills` and btw-style `inst/skills` of **attached** packages (report 05);
  4. plugin `skills/` folders.

  This makes project override user, as the agentskills.io guide ("the universal convention"), Pi's runtime loader (corrected in verification, see 2.14) and report 05 do. Codex's docs say colliding skills both appear and are not merged. Claude Code does the opposite (personal over project); document it.
- **Scanning** is a bounded breadth-first walk: depth 4, at most 2000 directories, skipping `.git`, `node_modules`, `.venv`, `renv` and `__pycache__`. Do not descend into a directory that already contains `SKILL.md`. Re-scan on `/reload`. The prototype needs about 0.3 s for 48 roots.
- **Parsing** uses `yaml::yaml.load` with the lenient fallback (unquoted values containing colons). Missing description: skip. Invalid name, name/directory mismatch, or a long description: load with a warning. Record diagnostics for a `/skills doctor` command.
- **Catalog** in the `<available_skills>` format.
  - Budget: `max(8000 characters, 1% of the model's context window)`. This is a gptr design choice. Corrected in verification: it does **not** match a "Codex floor". Codex uses 2% of the window and falls back to 8,000 characters only when the window is unknown; Claude Code uses 1%.
  - Each entry is capped at 1024 characters of description (Claude Code allows 1536).
  - When the budget overflows, drop descriptions first, starting with the least recently used skills, then the skills themselves; always keep names.
  - Hide skills with `disable-model-invocation: true`.
- **Activation.**
  - A `skill` tool with a `name` enum of visible skills and an `arguments` string. It returns the `<skill_content>` wrapper with the body, the directory and a resource list.
  - `/skill:name args` and `/name args` (when there is no conflict) from the console.
  - `gptr(skills = c(r_plot))` preloads bodies into the system prompt (REQ-19 bare names; report 05's proposal).
  - Supported substitutions: `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `${CLAUDE_SKILL_DIR}` and `${GPTR_SKILL_DIR}`.
  - `` !`cmd` `` injection is **off by default**: it is bash-centric, breaks on Windows, and runs code at load time. When the user enables it, gptr runs it through `processx::run()` under the permission gate.
  - `allowed-tools` is mapped to gptr tool names and used only as a per-turn auto-allow in intermediate permission modes.
- **Context management.** Keep activated skills out of compaction pruning, and re-attach them after compaction (Claude Code keeps 5k tokens per skill and 25k in total). Deduplicate identical activations.

### 4.9 Plugins (REQ-29): gptr format and Claude compatibility

**gptr plugin.** Either a directory or an installed R package with `inst/gptr/`:

```text
myplugin/
  .gptr-plugin/plugin.json      # optional; superset of Claude's plugin.json
  skills/<name>/SKILL.md
  extensions/*.R                # R extension files: function(gptr) {...} (report 05 API)
  agents/*.md                   # sub-agent definitions (REQ-32)
  prompts/*.md                  # prompt templates / slash commands (REQ-31)
  .mcp.json                     # MCP servers; ${GPTR_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_ROOT} both substituted
```

`plugin.json` accepts every Claude field listed in 2.15, plus:
- `"extensions": ["./extensions/"]`
- `"rDepends": ["ggplot2 (>= 3.5)"]`: checked with `requireNamespace()`; gptr never installs anything silently.
- `"gptr": ">= 1.0.0"`

**Loading.**
- `gptr(plugins = c(myplugin, "path/to/dir"))`, or `plugins` in the settings file.
- A bare name resolves to an installed package with `inst/gptr/`, or a directory under `R_user_dir("gptr", "data")/plugins/`.
- Extension code is loaded only for plugins named explicitly (report 05). Skills and prompts from attached packages are always visible.
- `plugins_import_claude()` reads `~/.claude/plugins/installed_plugins.json` and offers the installed Claude plugins in their `installPath`s. It reads only what the user asks for.

**How gptr consumes a Claude plugin unmodified:**

| Claude component | gptr handling | Status |
|---|---|---|
| `skills/` | load as skills, namespaced `plugin:skill` | works as is |
| `commands/*.md`, `commands` object map | prompt templates / slash commands `/plugin:cmd`; frontmatter `description`, `argument-hint`, `model`, `allowed-tools`; `$ARGUMENTS`, `$1` | works as is |
| `agents/*.md` | sub-agent definitions; map `tools` names (table below) and `model` aliases (`sonnet`, `opus`, `haiku`, `fable` to the user's configured Anthropic models, otherwise the default model); ignore `isolation`, `color`, `memory` | works with the maps |
| `.mcp.json` / `mcpServers` | MCP servers (they may need node/python/uv); substitute `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` (= `R_user_dir("gptr","data")/plugins/<id>`), `${CLAUDE_PROJECT_DIR}` | works as is |
| `userConfig` | prompt once through `readline`/ask-user; store non-sensitive values in settings and sensitive ones via keyring if installed, else an environment-variable prompt | partial |
| `hooks/hooks.json` | opt-in only; map PreToolUse to `tool_call`, PostToolUse to `tool_result`, UserPromptSubmit to `input`, SessionStart to `session_start`, Stop to `agent_end`; run `command` hooks with processx, giving Claude-shaped JSON on stdin with tool names mapped back to Claude's; honour exit code 2 and `permissionDecision` | partial; bash/jq scripts are not portable to Windows |
| `bin/` | prepend to PATH only for shell commands gptr runs through processx | optional |
| `.lsp.json`, `output-styles/`, `themes/`, `monitors/`, `workflows/*.js`, `channels`, `settings.json` | ignored, with a diagnostic | not applicable |

**Tool-name map** (Claude to gptr), used for `allowed-tools`, agent `tools` and hook matchers:

| Claude | gptr |
|---|---|
| Read | `read` |
| Write | `write` |
| Edit | `edit` |
| Bash / PowerShell | `r` (shell through `system2`/processx) |
| Grep | `grep` |
| Glob | `find` |
| WebFetch / WebSearch | provider server tools if configured, otherwise unmapped |
| Task / Agent | `subagent` |
| `mcp__<server>__<tool>` | the same name, or `mcp$server$tool` |

### 4.10 Imports vs Suggests

| Package | Role | Recommendation |
|---|---|---|
| jsonlite | all JSON | **Imports** |
| processx | stdio servers, `kill_tree`, plan-provider children | **Imports** (other tracks need it anyway) |
| httr2 | HTTP transport, OAuth pieces | **Imports** (providers track) |
| yaml | SKILL.md and agent frontmatter | **Imports** (compiled but ubiquitous); report 05 agrees that frontmatter needs yaml |
| httpuv | `mcp_serve()`; OAuth loopback via httr2 | **Suggests**, checked with `rlang::check_installed()` |
| later | pump loop while waiting | **Suggests** (httpuv imports it) |
| openssl | random tokens, SHA-1 for names | effectively free through httr2; call it as `openssl::` |
| RcppTOML / toml / tomledit | TOML | **no**: use the internal `toml_read()` |
| mcptools / ellmer / nanonext / promises | - | **no** |

---

## 5. Verified R prototypes

Every file below was **executed**; outputs are the literal `.out` files captured by `run_all.sh` (C locale, i.e. `LANG` unset) unless the name says `_utf8`. Working directory: `work/16/proto/`. All R sources are ASCII (non-ASCII test data is written with backslash-u escapes or `intToUtf8()`), R 4.4.3, macOS. Windows was not available; see section 6.2.

### 5.1 Test driver

`run_all.sh` runs every test with `Rscript --vanilla` and captures `*.out`. All 13 tests exited 0 in the final run.

`run_all.sh`

```sh
#!/bin/sh
# Runs every prototype test; outputs go to *.out. Uses Rscript --vanilla.
cd "$(dirname "$0")"
for t in test_stdio test_interrupt test_large test_naive_buffer test_http test_bridge test_toml test_config test_skills test_rfuns test_oauth_pieces test_interop test_oauth_discovery; do
  echo "=== $t"; Rscript --vanilla $t.R > $t.out 2>&1; echo "exit=$?"
done
```

### 5.2 Minimal MCP stdio SERVER in pure R (dual-era, one tool)

Reads stdin line by line (blocking `readLines(n = 1)` on `file("stdin")`), answers legacy `initialize`/`ping` and modern `_meta`-carrying requests incl. `server/discover`, exposes `describe_numbers` (structuredContent + outputSchema + annotations + progress notifications), logs only to stderr, exits on EOF. `--legacy-only` simulates a pre-2026 server; `--raw-utf8` writes raw UTF-8 with `writeLines(useBytes = TRUE)` instead of ASCII-escaped JSON.

`mcp_server_stdio.R`

```r
#!/usr/bin/env Rscript
# Minimal, dual-era MCP stdio SERVER written in pure R (base R + jsonlite).
#
# * Legacy era  (2024-11-05 .. 2025-11-25): initialize / notifications/initialized
#   handshake, ping, tools/list (paginated), tools/call.
# * Modern era  (2026-07-28): stateless; every request carries
#   _meta["io.modelcontextprotocol/protocolVersion"] and
#   _meta["io.modelcontextprotocol/clientCapabilities"]; server/discover;
#   every result carries resultType; list results carry ttlMs/cacheScope.
#
# Exposes ONE tool: "describe_numbers".
#
# Usage:  Rscript --vanilla mcp_server_stdio.R [--legacy-only] [--page-size=N]
#   --legacy-only  behave like a pre-2026 server (server/discover -> -32601)
#
# Rules followed (spec 2025-11-25 & 2026-07-28, stdio transport):
#   - one JSON-RPC message per line on stdout, no embedded newlines
#   - nothing but MCP messages on stdout; all logging goes to stderr
#   - exit promptly when stdin reaches EOF

suppressWarnings(suppressMessages(requireNamespace("jsonlite", quietly = TRUE)))

args <- commandArgs(trailingOnly = TRUE)
LEGACY_ONLY <- "--legacy-only" %in% args
PAGE_SIZE <- {
  a <- grep("^--page-size=", args, value = TRUE)
  if (length(a)) as.integer(sub("^--page-size=", "", a[1])) else 50L
}

SERVER_INFO <- list(name = "gptr-proto-server", version = "0.0.1")
LEGACY_VERSIONS <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
MODERN_VERSIONS <- if (LEGACY_ONLY) character() else c("2026-07-28")
K_VER <- "io.modelcontextprotocol/protocolVersion"
K_CAPS <- "io.modelcontextprotocol/clientCapabilities"
K_SINFO <- "io.modelcontextprotocol/serverInfo"

empty_obj <- function() structure(list(), names = character())

log_err <- function(...) {
  cat(format(Sys.time(), "%H:%M:%OS3"), " [server] ", ..., "\n", sep = "", file = stderr())
  flush(stderr())
}

# stdout is written with cat(); on Windows R's stdout is in text mode, so
# "\n" may be written as "\r\n". JSON parsers treat "\r" as whitespace, and
# the gptr client strips a trailing "\r" before parsing.
# Non-ASCII code points are written as JSON \uXXXX escapes (surrogate pairs
# above the BMP) so the byte stream is pure ASCII: immune to the C locale
# (cat() would print <U+00E9>) and to Windows code pages.
json_ascii <- function(s) {
  s <- enc2utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)          # fast path (no regex on MBs)
  cp <- utf8ToInt(s)
  hi <- which(cp > 127L)
  out <- intToUtf8(cp, multiple = TRUE)
  v <- cp[hi]; esc <- character(length(v)); bmp <- v < 65536L
  esc[bmp] <- sprintf("\\u%04x", v[bmp])
  a <- v[!bmp] - 65536L
  esc[!bmp] <- sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] <- esc
  paste(out, collapse = "")
}
RAW_UTF8 <- "--raw-utf8" %in% args   # test mode: emit raw UTF-8 bytes instead
# NB: file("stdout") would create a regular FILE named "stdout"; use stdout().
send <- function(msg) {
  txt <- jsonlite::toJSON(msg, auto_unbox = TRUE, null = "null", digits = NA)
  if (RAW_UTF8) {
    writeLines(enc2utf8(as.character(txt)), stdout(), useBytes = TRUE); flush(stdout())
  } else {
    cat(json_ascii(txt), "\n", sep = "", file = stdout()); flush(stdout())
  }
}

reply <- function(id, result) send(list(jsonrpc = "2.0", id = id, result = result))
reply_error <- function(id, code, message, data = NULL) {
  err <- list(code = code, message = message)
  if (!is.null(data)) err$data <- data
  send(list(jsonrpc = "2.0", id = id, error = err))
}

# ---- the single tool ---------------------------------------------------------
TOOLS <- list(
  list(
    name = "describe_numbers",
    title = "Describe numbers",
    description = paste(
      "Compute summary statistics (n, mean, sd, min, max) of a numeric vector.",
      "Optionally sleeps delay_ms milliseconds, emitting progress notifications."
    ),
    inputSchema = list(
      type = "object",
      properties = list(
        x = list(type = "array", items = list(type = "number"), description = "Numbers to describe"),
        digits = list(type = "integer", description = "Rounding digits (default 3)"),
        delay_ms = list(type = "integer", description = "Artificial delay for testing")
      ),
      required = I("x"),
      additionalProperties = FALSE
    ),
    outputSchema = list(
      type = "object",
      properties = list(
        n = list(type = "integer"), mean = list(type = "number"), sd = list(type = "number"),
        min = list(type = "number"), max = list(type = "number")
      ),
      required = I(c("n", "mean", "sd", "min", "max"))
    ),
    annotations = list(readOnlyHint = TRUE, openWorldHint = FALSE)
  )
)

progress <- function(token, progress, total, message) {
  if (is.null(token)) return(invisible())
  send(list(jsonrpc = "2.0", method = "notifications/progress",
            params = list(progressToken = token, progress = progress, total = total, message = message)))
}

call_describe_numbers <- function(arguments, progress_token) {
  x <- suppressWarnings(as.numeric(unlist(arguments$x)))
  digits <- if (is.null(arguments$digits)) 3L else as.integer(arguments$digits)
  delay <- if (is.null(arguments$delay_ms)) 0L else as.integer(arguments$delay_ms)
  if (delay > 0) {
    steps <- 4L
    for (i in seq_len(steps)) {
      Sys.sleep(delay / 1000 / steps)
      progress(progress_token, i, steps, sprintf("step %d/%d", i, steps))
    }
  }
  if (length(x) == 0 || anyNA(x)) {
    # Tool *execution* error: reported in-band with isError = TRUE so the
    # model can self-correct (spec: input validation errors are tool errors).
    return(list(content = list(list(type = "text", text = "Error: `x` must be a non-empty array of numbers.")),
                isError = TRUE))
  }
  s <- list(n = length(x), mean = round(mean(x), digits),
            sd = if (length(x) > 1) round(stats::sd(x), digits) else NA_real_,
            min = min(x), max = max(x))
  if (is.na(s$sd)) s$sd <- NULL
  list(
    content = list(list(type = "text", text = jsonlite::toJSON(s, auto_unbox = TRUE, digits = NA))),
    structuredContent = s,
    isError = FALSE
  )
}

# ---- request handling ----------------------------------------------------------
state <- new.env()
state$legacy_version <- NULL      # set by initialize (legacy era, per process)
state$initialized <- FALSE

list_tools_page <- function(cursor) {
  start <- if (is.null(cursor)) 1L else as.integer(cursor)
  if (is.na(start) || start < 1L) stop("invalid cursor")
  idx <- seq.int(start, length.out = max(0L, min(PAGE_SIZE, length(TOOLS) - start + 1L)))
  res <- list(tools = unname(TOOLS[idx]))
  nxt <- start + PAGE_SIZE
  if (nxt <= length(TOOLS)) res$nextCursor <- as.character(nxt)
  res
}

server_capabilities <- function() list(tools = list(listChanged = FALSE))

finish_modern <- function(result, cacheable = FALSE) {
  result$resultType <- "complete"
  result[["_meta"]] <- setNames(list(SERVER_INFO), K_SINFO)
  if (cacheable) { result$ttlMs <- 60000L; result$cacheScope <- "public" }
  result
}

handle <- function(msg) {
  id <- msg$id
  method <- msg$method
  params <- msg$params %||% list()
  is_request <- !is.null(id)

  if (is.null(method)) return(invisible())          # a response to us; ignore
  if (!is_request) {                                 # notifications
    if (method == "notifications/initialized") state$initialized <- TRUE
    if (method == "notifications/cancelled") log_err("client cancelled request ", format(params$requestId))
    return(invisible())
  }

  meta <- params[["_meta"]]
  modern_ver <- meta[[K_VER]]

  # ---- legacy handshake ----
  if (method == "initialize") {
    requested <- params$protocolVersion
    ver <- if (!is.null(requested) && requested %in% LEGACY_VERSIONS) requested else LEGACY_VERSIONS[1]
    state$legacy_version <- ver
    log_err("initialize: client asked ", requested, ", using ", ver)
    return(reply(id, list(protocolVersion = ver, capabilities = server_capabilities(),
                          serverInfo = SERVER_INFO,
                          instructions = "Prototype R server. Call describe_numbers with x = [numbers].")))
  }
  if (method == "ping") return(reply(id, empty_obj()))

  # ---- era selection per request ----
  modern <- FALSE
  if (!is.null(modern_ver)) {
    if (!(modern_ver %in% MODERN_VERSIONS)) {
      if (LEGACY_ONLY) return(reply_error(id, -32601L, paste("Method not found:", method)))
      return(reply_error(id, -32022L, "Unsupported protocol version",
                         list(supported = I(c(MODERN_VERSIONS, LEGACY_VERSIONS)), requested = modern_ver)))
    }
    if (is.null(meta[[K_CAPS]])) return(reply_error(id, -32602L, "Missing _meta clientCapabilities"))
    modern <- TRUE
  } else if (is.null(state$legacy_version)) {
    return(reply_error(id, -32602L, "Missing required _meta protocol fields (or send initialize first)"))
  }

  if (method == "server/discover") {
    return(reply(id, finish_modern(list(supportedVersions = I(MODERN_VERSIONS),
                                        capabilities = server_capabilities(),
                                        instructions = "Prototype R server."), cacheable = TRUE)))
  }
  if (method == "tools/list") {
    res <- tryCatch(list_tools_page(params$cursor), error = function(e) NULL)
    if (is.null(res)) return(reply_error(id, -32602L, "Invalid cursor"))
    return(reply(id, if (modern) finish_modern(res, cacheable = TRUE) else res))
  }
  if (method == "tools/call") {
    if (!identical(params$name, "describe_numbers"))
      return(reply_error(id, -32602L, paste("Unknown tool:", params$name)))
    res <- call_describe_numbers(params$arguments %||% list(), meta$progressToken)
    return(reply(id, if (modern) finish_modern(res) else res))
  }
  reply_error(id, -32601L, paste("Method not found:", method))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- main loop: blocking line reads from stdin until EOF ------------------------
# No re-encoding on the connection (a C locale would reject UTF-8 input);
# readLines(encoding = "UTF-8") only *marks* the bytes as UTF-8.
con <- file("stdin", open = "r")
log_err("started (legacy_only=", LEGACY_ONLY, ", R ", as.character(getRversion()), ")")
repeat {
  line <- readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(line) == 0L) break                     # EOF: client closed stdin
  line <- sub("\r$", "", line)
  if (!nzchar(trimws(line))) next
  msg <- tryCatch(jsonlite::parse_json(line, simplifyVector = FALSE), error = function(e) e)
  if (inherits(msg, "error")) { reply_error(NULL, -32700L, "Parse error"); next }
  if (!is.list(msg) || !identical(msg$jsonrpc, "2.0")) { reply_error(msg$id, -32600L, "Invalid Request"); next }
  tryCatch(handle(msg), error = function(e) {
    log_err("internal error: ", conditionMessage(e))
    if (!is.null(msg$id)) reply_error(msg$id, -32603L, "Internal error")
  })
}
close(con)
log_err("stdin closed; exiting")
quit(save = "no", status = 0L)
```

### 5.3 Minimal MCP stdio CLIENT in pure R (processx)

Era probe via `server/discover` with fallback to `initialize`; chunked non-blocking reads (processx returns <= 8192 chars per read); ASCII JSON written as raw bytes with a write loop; id-matched responses; progress-reset timeouts with hard cap; `notifications/cancelled` on timeout and on user interrupt; late responses dropped; server stderr to a log file; graceful close (stdin EOF -> wait -> kill_tree). Windows `.cmd` shims are routed through `cmd.exe /d /c call` (not executed here).

`mcp_client_stdio.R`

```r
# Minimal, dual-era MCP stdio CLIENT in pure R (processx + jsonlite).
#
#   conn <- mcp_stdio_connect(command, args)   # spawn + era detection + handshake
#   tools <- mcp_list_tools(conn)                # paginated tools/list
#   res <- mcp_call_tool(conn, "name", list(...))
#   mcp_close(conn)                              # close stdin -> wait -> kill tree
#
# Era detection (spec 2026-07-28, stdio "Backward Compatibility"):
#   probe with server/discover carrying modern _meta;
#     DiscoverResult                -> modern (stateless, _meta on every request)
#     error -32022 (Unsupported...) -> modern, pick from error.data.supported
#     any other error / timeout     -> legacy: initialize + notifications/initialized
#
# Transport details handled here:
#   * non-blocking reads with poll_io(); own line buffer (partial lines, CRLF)
#   * messages written as ASCII-only JSON (non-ASCII -> \uXXXX), as raw bytes,
#     looping until processx has written everything (write_input is non-blocking)
#   * server stderr goes to a log FILE, so a chatty server can never block on a
#     full stderr pipe
#   * responses matched by id; notifications (progress, logging, list_changed)
#     dispatched to callbacks; legacy server->client requests (ping, roots/list,
#     sampling, elicitation) answered or refused with -32601
#   * per-request timeout, reset by progress notifications, with a hard cap;
#     on timeout/interrupt a notifications/cancelled is sent

`%||%` <- function(a, b) if (is.null(a)) b else a
empty_obj <- function() structure(list(), names = character())

MCP_MODERN_VERSIONS <- c("2026-07-28")
MCP_LEGACY_VERSIONS <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
K_VER <- "io.modelcontextprotocol/protocolVersion"
K_CAPS <- "io.modelcontextprotocol/clientCapabilities"
K_CINFO <- "io.modelcontextprotocol/clientInfo"

json_ascii <- function(s) {
  s <- enc2utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)          # fast path (no regex on MBs)
  cp <- utf8ToInt(s)
  hi <- which(cp > 127L)
  out <- intToUtf8(cp, multiple = TRUE)
  v <- cp[hi]; esc <- character(length(v)); bmp <- v < 65536L
  esc[bmp] <- sprintf("\\u%04x", v[bmp])
  a <- v[!bmp] - 65536L
  esc[!bmp] <- sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] <- esc
  paste(out, collapse = "")
}

to_json <- function(x) json_ascii(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))

# Resolve the executable portably. On Windows, npm/npx/uvx shims are .cmd files:
# run them through cmd.exe /c call (processx docs, "Batch files").
mcp_resolve_command <- function(command, args = character()) {
  if (identical(basename(command), command)) {
    found <- Sys.which(command)
    if (nzchar(found)) command <- unname(found)
  }
  if (.Platform$OS.type == "windows" && grepl("\\.(cmd|bat)$", command, ignore.case = TRUE)) {
    return(list(command = Sys.getenv("COMSPEC", "cmd.exe"), args = c("/d", "/c", "call", command, args)))
  }
  list(command = command, args = args)
}

mcp_stdio_connect <- function(command, args = character(), env = NULL, cwd = NULL,
                              name = basename(command),
                              protocol = c("auto", "modern", "legacy"),
                              client_info = list(name = "gptr", version = "0.0.0.9000"),
                              capabilities = empty_obj(),
                              probe_timeout = 5, timeout = 60,
                              stderr_file = tempfile(paste0("mcp-", name, "-"), fileext = ".log"),
                              on_notification = NULL, verbose = FALSE) {
  protocol <- match.arg(protocol)
  cmd <- mcp_resolve_command(command, args)
  proc <- processx::process$new(
    command = cmd$command, args = cmd$args, env = env, wd = cwd,
    stdin = "|", stdout = "|", stderr = stderr_file,
    encoding = "UTF-8", cleanup = TRUE, cleanup_tree = TRUE,
    windows_hide_window = TRUE
  )
  conn <- new.env(parent = emptyenv())
  conn$name <- name
  conn$proc <- proc
  conn$pending <- character()
  conn$next_id <- 0L
  conn$responses <- new.env(parent = emptyenv())
  conn$cancelled <- new.env(parent = emptyenv())
  conn$progress_cb <- new.env(parent = emptyenv())
  conn$on_notification <- on_notification
  conn$timeout <- timeout
  conn$client_info <- client_info
  conn$capabilities <- capabilities
  conn$stderr_file <- stderr_file
  conn$verbose <- verbose
  conn$era <- NA_character_
  conn$version <- NA_character_
  conn$server_info <- NULL
  conn$server_capabilities <- NULL
  conn$instructions <- NULL
  conn$tools_cache <- NULL
  conn$tools_stale <- TRUE

  if (protocol %in% c("auto", "modern")) {
    probe <- mcp_request(conn, "server/discover", list(), timeout = probe_timeout,
                         modern_version = MCP_MODERN_VERSIONS[1], raw = TRUE)
    if (!is.null(probe$result$supportedVersions)) {
      common <- intersect(MCP_MODERN_VERSIONS, unlist(probe$result$supportedVersions))
      if (length(common)) {
        conn$era <- "modern"; conn$version <- common[1]
        conn$server_capabilities <- probe$result$capabilities
        conn$server_info <- probe$result[["_meta"]][["io.modelcontextprotocol/serverInfo"]]
        conn$instructions <- probe$result$instructions
      }
    } else if (identical(probe$error$code, -32022L) || identical(probe$error$code, -32022)) {
      common <- intersect(MCP_MODERN_VERSIONS, unlist(probe$error$data$supported))
      if (length(common)) { conn$era <- "modern"; conn$version <- common[1] }
      else if (protocol == "modern") stop("server supports no modern version we speak")
    }
    conn$probe <- probe
  }
  if (is.na(conn$era)) {
    if (protocol == "modern") { mcp_close(conn); stop("MCP server '", name, "' did not answer as a modern server") }
    init <- mcp_request(conn, "initialize", list(
      protocolVersion = MCP_LEGACY_VERSIONS[1],
      capabilities = capabilities, clientInfo = client_info), timeout = timeout)
    if (!(init$protocolVersion %in% MCP_LEGACY_VERSIONS)) {
      mcp_close(conn); stop("server chose unsupported protocol version ", init$protocolVersion)
    }
    conn$era <- "legacy"; conn$version <- init$protocolVersion
    conn$server_info <- init$serverInfo
    conn$server_capabilities <- init$capabilities
    conn$instructions <- init$instructions
    mcp_notify(conn, "notifications/initialized")
  }
  conn
}

# ---- low-level I/O ------------------------------------------------------------------
mcp_send <- function(conn, msg) {
  if (conn$verbose) message("-> ", to_json(msg))
  bytes <- c(charToRaw(to_json(msg)), as.raw(10L))
  repeat {
    bytes <- conn$proc$write_input(bytes)       # returns the unwritten remainder
    if (length(bytes) == 0L) break
    if (!conn$proc$is_alive()) stop("MCP server '", conn$name, "' exited while writing")
    Sys.sleep(0.005)
  }
  invisible(TRUE)
}

mcp_notify <- function(conn, method, params = NULL) {
  msg <- list(jsonrpc = "2.0", method = method)
  if (!is.null(params)) msg$params <- params
  mcp_send(conn, msg)
}

# Read whatever is available (waiting up to timeout_ms) and dispatch complete lines.
# processx returns at most 8192 chars per read_output() call, so drain in a loop
# and keep partial lines as a vector of pending chunks (linear, not quadratic).
mcp_pump <- function(conn, timeout_ms = 50L, max_chunks = 512L) {
  st <- conn$proc$poll_io(as.integer(timeout_ms))
  chunks <- character()
  while (identical(st[["output"]], "ready") && length(chunks) < max_chunks) {
    ch <- conn$proc$read_output()
    if (!nzchar(ch)) break
    chunks <- c(chunks, ch)
    st <- conn$proc$poll_io(0L)
  }
  for (ch in chunks) {
    if (!grepl("\n", ch, fixed = TRUE)) { conn$pending <- c(conn$pending, ch); next }
    parts <- strsplit(ch, "\n", fixed = TRUE)[[1]]
    if (!length(parts)) parts <- ""
    lines <- c(paste(c(conn$pending, parts[1]), collapse = ""), parts[-1])
    if (endsWith(ch, "\n")) conn$pending <- character()
    else { conn$pending <- lines[length(lines)]; lines <- lines[-length(lines)] }
    for (line in lines) {
      line <- sub("\r$", "", line)
      if (!nzchar(trimws(line))) next
      msg <- tryCatch(jsonlite::parse_json(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(msg)) { warning("MCP '", conn$name, "': non-JSON line on stdout ignored: ", substr(line, 1, 200)); next }
      if (isTRUE(conn$verbose)) message("<- ", substr(line, 1, 500))
      mcp_dispatch(conn, msg)
    }
  }
  invisible(st)
}

mcp_dispatch <- function(conn, msg) {
  has_id <- !is.null(msg$id)
  if (has_id && (!is.null(msg$result) || !is.null(msg$error))) {           # response
    k <- as.character(msg$id)
    if (exists(k, envir = conn$cancelled, inherits = FALSE)) { rm(list = k, envir = conn$cancelled); return(invisible()) }
    assign(as.character(msg$id), msg, envir = conn$responses)
    return(invisible())
  }
  if (!is.null(msg$method) && !has_id) {                                   # notification
    m <- msg$method
    if (m == "notifications/progress") {
      tok <- as.character(msg$params$progressToken)
      cb <- conn$progress_cb[[tok]]
      if (is.function(cb)) cb(msg$params)
    } else if (m %in% c("notifications/tools/list_changed")) {
      conn$tools_stale <- TRUE
    } else if (m == "notifications/message") {
      p <- msg$params
      cat(sprintf("[mcp:%s] %s %s\n", conn$name, p$level %||% "info",
                  if (is.character(p$data)) p$data else to_json(p$data)), file = conn$stderr_file, append = TRUE)
    }
    if (is.function(conn$on_notification)) conn$on_notification(msg)
    return(invisible())
  }
  if (!is.null(msg$method) && has_id) {                                    # server->client request (legacy era)
    if (msg$method == "ping") {
      mcp_send(conn, list(jsonrpc = "2.0", id = msg$id, result = empty_obj()))
    } else {
      mcp_send(conn, list(jsonrpc = "2.0", id = msg$id,
                          error = list(code = -32601L, message = paste("Method not found:", msg$method))))
    }
  }
  invisible()
}

# ---- requests -------------------------------------------------------------------------
mcp_request <- function(conn, method, params = NULL, timeout = conn$timeout,
                        max_timeout = 10 * timeout, on_progress = NULL,
                        modern_version = NULL, raw = FALSE) {
  conn$next_id <- conn$next_id + 1L
  id <- conn$next_id
  key <- as.character(id)
  ver <- modern_version %||% (if (identical(conn$era, "modern")) conn$version else NULL)
  if (!is.null(ver)) {                                    # modern: per-request _meta
    params <- params %||% list()
    meta <- params[["_meta"]] %||% list()
    meta[[K_VER]] <- ver
    meta[[K_CAPS]] <- conn$capabilities
    meta[[K_CINFO]] <- conn$client_info
    params[["_meta"]] <- meta
  }
  if (is.function(on_progress)) {
    tok <- paste0("p", id)
    params <- params %||% list()
    meta <- params[["_meta"]] %||% list()
    meta$progressToken <- tok
    params[["_meta"]] <- meta
    conn$progress_cb[[tok]] <- function(p) { deadline <<- Sys.time() + timeout; on_progress(p) }
    on.exit(rm(list = tok, envir = conn$progress_cb), add = TRUE)
  }
  msg <- list(jsonrpc = "2.0", id = id, method = method)
  if (!is.null(params)) msg$params <- params
  deadline <- Sys.time() + timeout
  hard_deadline <- Sys.time() + max_timeout
  cancel <- function(reason) {
    assign(key, TRUE, envir = conn$cancelled)   # a late response for this id is dropped
    if (conn$proc$is_alive())
      try(mcp_notify(conn, "notifications/cancelled", list(requestId = id, reason = reason)), silent = TRUE)
  }
  resp <- tryCatch({
    mcp_send(conn, msg)
    repeat {
      if (exists(key, envir = conn$responses, inherits = FALSE)) {
        r <- get(key, envir = conn$responses); rm(list = key, envir = conn$responses)
        break
      }
      now <- Sys.time()
      if (now > deadline || now > hard_deadline) {
        cancel("timeout")
        r <- list(error = list(code = NA_integer_, message = sprintf("timeout after %ss", timeout)), timed_out = TRUE)
        break
      }
      st <- mcp_pump(conn, 50L)
      if (!conn$proc$is_alive() && identical(st[["output"]], "closed")) {
        mcp_pump(conn, 0L)
        if (exists(key, envir = conn$responses, inherits = FALSE)) next
        r <- list(error = list(code = NA_integer_, message = "server process exited"), exited = TRUE)
        break
      }
    }
    r
  }, interrupt = function(e) { cancel("user interrupt"); stop("MCP request interrupted by user") })
  if (raw) return(resp)
  if (!is.null(resp$error)) {
    stop(structure(class = c("mcp_error", "error", "condition"),
                   list(message = sprintf("MCP %s '%s' error %s: %s", conn$name, method,
                                          format(resp$error$code), resp$error$message),
                        call = NULL, code = resp$error$code, data = resp$error$data)))
  }
  res <- resp$result
  rt <- res$resultType %||% "complete"          # absent => complete (legacy servers)
  if (!identical(rt, "complete")) res$.input_required <- TRUE
  res
}

mcp_list_tools <- function(conn, max_pages = 100L, refresh = FALSE) {
  if (!refresh && !conn$tools_stale && !is.null(conn$tools_cache)) return(conn$tools_cache)
  tools <- list(); cursor <- NULL
  for (i in seq_len(max_pages)) {
    res <- mcp_request(conn, "tools/list", if (is.null(cursor)) NULL else list(cursor = cursor))
    tools <- c(tools, res$tools)
    cursor <- res$nextCursor
    if (is.null(cursor)) break
  }
  conn$tools_cache <- tools
  conn$tools_stale <- FALSE
  tools
}

mcp_call_tool <- function(conn, name, arguments = empty_obj(), timeout = conn$timeout, on_progress = NULL) {
  if (length(arguments) == 0L) arguments <- empty_obj()
  res <- mcp_request(conn, "tools/call", list(name = name, arguments = arguments),
                     timeout = timeout, on_progress = on_progress)
  structure(list(
    content = res$content %||% list(),
    structured = res$structuredContent,
    is_error = isTRUE(res$isError),
    input_required = isTRUE(res$.input_required),
    raw = res
  ), class = "mcp_tool_result")
}

# Text the model sees: text blocks verbatim; other blocks as short placeholders.
format.mcp_tool_result <- function(x, ...) {
  parts <- vapply(x$content, function(b) switch(b$type,
    text = b$text,
    image = sprintf("[image %s, %d base64 chars]", b$mimeType, nchar(b$data)),
    audio = sprintf("[audio %s]", b$mimeType),
    resource_link = sprintf("[resource_link %s]", b$uri),
    resource = if (!is.null(b$resource$text)) b$resource$text else sprintf("[resource %s]", b$resource$uri),
    sprintf("[%s block]", b$type)), "")
  paste0(if (x$is_error) "ERROR: " else "", paste(parts, collapse = "\n"))
}
print.mcp_tool_result <- function(x, ...) { cat(format(x), "\n"); invisible(x) }

# Shutdown (spec): close stdin -> wait -> terminate (kill_tree covers npx/uvx wrappers).
mcp_close <- function(conn, grace = 2) {
  p <- conn$proc
  if (p$is_alive()) {
    try(close(p$get_input_connection()), silent = TRUE)
    p$wait(timeout = as.integer(grace * 1000))
  }
  exited_gracefully <- !p$is_alive()
  if (!exited_gracefully) try(p$kill_tree(), silent = TRUE)
  invisible(list(exited_gracefully = exited_gracefully, exit_status = p$get_exit_status()))
}
```

### 5.4 stdio tests: both eras, errors, progress, timeout/cancel, interrupt

`test_stdio.R` runs four scenarios: dual-era server with auto detection (-> modern), legacy-only server (-> probe error -32601 -> legacy fallback), forced legacy, and a server writing raw UTF-8. In the C locale, R prints UTF-8 in messages as `<c3><a9>` bytes (display only; the explicit byte check `exact UTF-8 name: TRUE` shows the data is intact); the `_utf8` run shows the same test in a UTF-8 locale.

`test_stdio.R`

```r
# End-to-end test: pure-R MCP client (processx) <-> pure-R MCP server (Rscript).
source("mcp_client_stdio.R")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
server <- normalizePath("mcp_server_stdio.R")
cat("Rscript:", rscript, "\n")

run_case <- function(label, extra_args = character(), protocol = "auto") {
  cat("\n==========", label, "==========\n")
  t0 <- Sys.time()
  conn <- mcp_stdio_connect(rscript, c("--vanilla", server, extra_args), name = "rproto",
                            protocol = protocol, probe_timeout = 5, timeout = 20)
  cat(sprintf("era=%s version=%s server=%s/%s (connect %.2fs)\n", conn$era, conn$version,
              conn$server_info$name, conn$server_info$version, as.numeric(Sys.time() - t0, units = "secs")))
  if (!is.null(conn$probe$error)) cat("probe error:", conn$probe$error$code, conn$probe$error$message, "\n")
  tools <- mcp_list_tools(conn)
  cat("tools:", vapply(tools, `[[`, "", "name"), " (", length(tools), ")\n")
  r <- mcp_call_tool(conn, "describe_numbers", list(x = list(1, 2, 3.5, 10), digits = 2L),
                     on_progress = function(p) cat("  progress:", p$progress, "/", p$total, p$message, "\n"))
  print(r)
  cat("structured mean:", r$structured$mean, " is_error:", r$is_error, "\n")
  r2 <- mcp_call_tool(conn, "describe_numbers", list(x = list()))
  cat("empty x -> is_error:", r2$is_error, "|", format(r2), "\n")
  e <- tryCatch(mcp_call_tool(conn, "no_such_tool \u00e9\u4e16"), mcp_error = function(e) e)
  cat("unknown tool -> class:", class(e)[1], "code:", e$code, "msg:", conditionMessage(e), "\n")
  cat("unknown-tool message carries the exact UTF-8 name:", grepl(intToUtf8(c(0xe9, 0x4e16)), conditionMessage(e), fixed = TRUE), "\n")
  rp <- mcp_call_tool(conn, "describe_numbers", list(x = list(5, 6), delay_ms = 400L),
                      on_progress = function(p) cat("  progress:", p$progress, "/", p$total, p$message, "\n"))
  cat("with progress ->", format(rp), "\n")
  # timeout -> notifications/cancelled is sent, late response is ignored
  rt <- tryCatch(mcp_call_tool(conn, "describe_numbers", list(x = list(1), delay_ms = 1500L), timeout = 0.5),
                 mcp_error = function(e) conditionMessage(e))
  cat("timeout case ->", rt, "\n")
  Sys.sleep(1.6); mcp_pump(conn, 100L)
  cat("stale responses parked:", length(ls(conn$responses)), "\n")
  r3 <- mcp_call_tool(conn, "describe_numbers", list(x = list(1, 1, 1)))
  cat("after timeout, next call ok ->", format(r3), "\n")
  cl <- mcp_close(conn)
  cat("closed: graceful =", cl$exited_gracefully, " exit status =", cl$exit_status, "\n")
  cat("server stderr log:\n"); cat(paste0("  | ", readLines(conn$stderr_file)), sep = "\n")
}

run_case("dual-era server, auto (expect modern)")
run_case("legacy-only server, auto (expect probe fails -> legacy fallback)", "--legacy-only")
run_case("dual-era server, forced legacy", protocol = "legacy")
run_case("raw UTF-8 output server (not ASCII-escaped)", "--raw-utf8")
```

`test_stdio.out`

```text
Rscript: /Library/Frameworks/R.framework/Resources/bin/Rscript 

========== dual-era server, auto (expect modern) ==========
era=modern version=2026-07-28 server=gptr-proto-server/0.0.1 (connect 0.32s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool <U+00E9><U+4E16> 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:43:04.671 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:43:06.738 [server] client cancelled request 7
  | 19:43:07.347 [server] stdin closed; exiting

========== legacy-only server, auto (expect probe fails -> legacy fallback) ==========
era=legacy version=2025-11-25 server=gptr-proto-server/0.0.1 (connect 0.20s)
probe error: -32601 Method not found: server/discover 
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool <U+00E9><U+4E16> 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:43:07.499 [server] started (legacy_only=TRUE, R 4.4.3)
  | 19:43:07.550 [server] initialize: client asked 2025-11-25, using 2025-11-25
  | 19:43:09.509 [server] client cancelled request 8
  | 19:43:10.114 [server] stdin closed; exiting

========== dual-era server, forced legacy ==========
era=legacy version=2025-11-25 server=gptr-proto-server/0.0.1 (connect 0.20s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool <U+00E9><U+4E16> 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:43:10.273 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:43:10.316 [server] initialize: client asked 2025-11-25, using 2025-11-25
  | 19:43:12.280 [server] client cancelled request 7
  | 19:43:12.881 [server] stdin closed; exiting

========== raw UTF-8 output server (not ASCII-escaped) ==========
era=modern version=2026-07-28 server=gptr-proto-server/0.0.1 (connect 0.19s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool <U+00E9><U+4E16> 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:43:13.034 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:43:15.054 [server] client cancelled request 7
  | 19:43:15.650 [server] stdin closed; exiting
```

`test_stdio_utf8.out`

```text
Rscript: /Library/Frameworks/R.framework/Resources/bin/Rscript 

========== dual-era server, auto (expect modern) ==========
era=modern version=2026-07-28 server=gptr-proto-server/0.0.1 (connect 0.63s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool é世 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:18:46.329 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:18:48.558 [server] client cancelled request 7
  | 19:18:49.158 [server] stdin closed; exiting

========== legacy-only server, auto (expect probe fails -> legacy fallback) ==========
era=legacy version=2025-11-25 server=gptr-proto-server/0.0.1 (connect 0.46s)
probe error: -32601 Method not found: server/discover 
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool é世 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:18:49.489 [server] started (legacy_only=TRUE, R 4.4.3)
  | 19:18:49.625 [server] initialize: client asked 2025-11-25, using 2025-11-25
  | 19:18:51.647 [server] client cancelled request 8
  | 19:18:52.258 [server] stdin closed; exiting

========== dual-era server, forced legacy ==========
era=legacy version=2025-11-25 server=gptr-proto-server/0.0.1 (connect 0.35s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool é世 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:18:52.534 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:18:52.612 [server] initialize: client asked 2025-11-25, using 2025-11-25
  | 19:18:54.600 [server] client cancelled request 7
  | 19:18:55.219 [server] stdin closed; exiting

========== raw UTF-8 output server (not ASCII-escaped) ==========
era=modern version=2026-07-28 server=gptr-proto-server/0.0.1 (connect 0.36s)
tools: describe_numbers  ( 1 )
{"n":4,"mean":4.12,"sd":4.05,"min":1,"max":10} 
structured mean: 4.12  is_error: FALSE 
empty x -> is_error: TRUE | ERROR: Error: `x` must be a non-empty array of numbers. 
unknown tool -> class: mcp_error code: -32602 msg: MCP rproto 'tools/call' error -32602: Unknown tool: no_such_tool é世 
unknown-tool message carries the exact UTF-8 name: TRUE 
  progress: 1 / 4 step 1/4 
  progress: 2 / 4 step 2/4 
  progress: 3 / 4 step 3/4 
  progress: 4 / 4 step 4/4 
with progress -> {"n":2,"mean":5.5,"sd":0.707,"min":5,"max":6} 
timeout case -> MCP rproto 'tools/call' error NA: timeout after 0.5s 
stale responses parked: 0 
after timeout, next call ok -> {"n":3,"mean":1,"sd":0,"min":1,"max":1} 
closed: graceful = TRUE  exit status = 0 
server stderr log:
  | 19:18:55.501 [server] started (legacy_only=FALSE, R 4.4.3)
  | 19:18:57.589 [server] client cancelled request 7
  | 19:18:58.201 [server] stdin closed; exiting
```

### 5.5 Real user interrupt (SIGINT) during an in-flight call

A helper process sends SIGINT to the R client after 1 s while a 3 s tool call is in flight: the client catches the interrupt, sends `notifications/cancelled`, drops the late response and the connection stays usable.

`test_interrupt.R`

```r
# Simulate the user pressing Esc/Ctrl-C while an MCP tool call is in flight.
source("mcp_client_stdio.R")
conn <- mcp_stdio_connect(file.path(R.home("bin"), "Rscript"), c("--vanilla", "mcp_server_stdio.R"), name = "rproto")
killer <- processx::process$new("sh", c("-c", sprintf("sleep 1; kill -INT %d", Sys.getpid())))
t0 <- Sys.time()
res <- tryCatch(mcp_call_tool(conn, "describe_numbers", list(x = list(1, 2), delay_ms = 3000L)),
                error = function(e) paste("caught error:", conditionMessage(e)),
                interrupt = function(e) "caught raw interrupt")
cat(sprintf("after %.1fs -> %s\n", as.numeric(Sys.time() - t0, units = "secs"), format(res)))
Sys.sleep(3); mcp_pump(conn, 100L)
cat("late response dropped (parked responses):", length(ls(conn$responses)), "\n")
cat("next call still works ->", format(mcp_call_tool(conn, "describe_numbers", list(x = list(3, 4)))), "\n")
mcp_close(conn)
cat(readLines(conn$stderr_file), sep = "\n")
```

`test_interrupt.out`

```text
after 1.1s -> caught error: MCP request interrupted by user
late response dropped (parked responses): 0 
next call still works -> {"n":2,"mean":3.5,"sd":0.707,"min":3,"max":4} 
19:43:16.111 [server] started (legacy_only=FALSE, R 4.4.3)
19:43:19.235 [server] client cancelled request 2
19:43:20.283 [server] stdin closed; exiting
```

### 5.6 Large single-line messages and json_ascii() cost

A fake server answers with one ~3.6 MB JSON line containing 600k non-ASCII characters (written raw with `useBytes = TRUE`); the client reassembles 440+ chunks in about 1 s with UTF-8 intact. The same test also times `json_ascii()`.

`fake_big_server.R`

```r
# Fake server for the large-message test: one ~7 MB JSON-RPC line containing
# raw UTF-8 (written with useBytes = TRUE; cat() of this UTF-8 string in a C
# locale took 296 s and produced <U+00E9> text - see report 2.17).
con <- file("stdin", "r"); l <- readLines(con, 1)
x <- paste(rep(paste0("abc", intToUtf8(0xE9), " "), 6e5), collapse = "")
j <- jsonlite::toJSON(list(jsonrpc = "2.0", id = 1L, result = list(content = list(list(type = "text", text = x)))), auto_unbox = TRUE)
writeLines(enc2utf8(as.character(j)), stdout(), useBytes = TRUE); flush(stdout()); readLines(con, 1)
```

`test_large.R`

```r
source("mcp_client_stdio.R")
# fake server: waits for one line, answers id 1 with a ~5 MB payload (incl. non-ASCII), in one JSON line
srv <- 'con <- file("stdin","r"); l <- readLines(con, 1); x <- paste(rep("abc\\u00e9 ", 6e5), collapse=""); cat(jsonlite::toJSON(list(jsonrpc="2.0", id=1L, result=list(content=list(list(type="text", text=x)))), auto_unbox=TRUE), "\\n", sep=""); flush(stdout()); readLines(con, 1)'
conn <- new.env(); conn$name <- "big"; conn$pending <- character(); conn$next_id <- 0L; conn$responses <- new.env(); conn$cancelled <- new.env()
conn$progress_cb <- new.env(); conn$timeout <- 60; conn$verbose <- FALSE; conn$era <- "legacy"; conn$stderr_file <- tempfile()
conn$proc <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", "fake_big_server.R"), stdin = "|", stdout = "|",
                                   stderr = conn$stderr_file, encoding = "UTF-8")
t0 <- Sys.time()
res <- mcp_request(conn, "tools/call", list(name = "x"))
cat(sprintf("received %.1f MB text in %.2fs; nchar=%d; first chars: %s; UTF-8 intact: %s\n", nchar(res$content[[1]]$text, "bytes") / 1e6,
            as.numeric(Sys.time() - t0, units = "secs"), nchar(res$content[[1]]$text), substr(res$content[[1]]$text, 1, 3), startsWith(res$content[[1]]$text, paste0("abc", intToUtf8(0xE9)))))
conn$proc$kill()
# json_ascii cost on a 5 MB mostly-ASCII string with scattered non-ASCII
s <- paste(rep("abc\u00e9 ", 1e6), collapse = "")
t1 <- system.time(j <- json_ascii(jsonlite::toJSON(list(t = s), auto_unbox = TRUE)))
cat(sprintf("json_ascii on %.1f MB (1e6 non-ASCII chars): %.2fs elapsed\n", nchar(s, "bytes") / 1e6, t1[["elapsed"]]))
s2 <- strrep("abcd ", 1e6)
t2 <- system.time(j2 <- json_ascii(jsonlite::toJSON(list(t = s2), auto_unbox = TRUE)))
cat(sprintf("json_ascii on %.1f MB pure ASCII: %.3fs elapsed\n", nchar(s2) / 1e6, t2[["elapsed"]]))
```

`test_large.out`

```text
received 3.6 MB text in 0.55s; nchar=3000000; first chars: abc; UTF-8 intact: TRUE
[1] TRUE
json_ascii on 6.0 MB (1e6 non-ASCII chars): 0.93s elapsed
json_ascii on 5.0 MB pure ASCII: 0.050s elapsed
```

`test_naive_buffer.R`

```r
# Compare the first (naive) line buffer - paste0(buf, chunk) + grepl/strsplit on the
# whole buffer after every read - with the chunk-vector pump, on the same ~3.6 MB line.
naive_read_line <- function(p) {
  buf <- ""
  repeat {
    st <- p$poll_io(50L)
    if (identical(st[["output"]], "ready")) buf <- paste0(buf, p$read_output())
    if (grepl("\n", buf, fixed = TRUE)) return(strsplit(buf, "\n", fixed = TRUE)[[1]][1])
  }
}
p <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", "fake_big_server.R"),
                           stdin = "|", stdout = "|", stderr = "|", encoding = "UTF-8")
p$write_input("{}\n")
t <- system.time(line <- naive_read_line(p))[["elapsed"]]
cat(sprintf("naive growing buffer: %.2fs for %.1f MB line\n", t, nchar(line, "bytes") / 1e6))
p$kill()
```

`test_naive_buffer.out`

```text
naive growing buffer: 2.87s for 3.6 MB line
[1] TRUE
```

`json_ascii_fast.R`

```r
# Final json_ascii(): ASCII-only JSON text; vectorised; fast path for pure ASCII.
json_ascii <- function(s) {
  s <- enc2utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)          # fast path (no regex on MBs)
  cp <- utf8ToInt(s)
  hi <- which(cp > 127L)
  out <- intToUtf8(cp, multiple = TRUE)
  v <- cp[hi]; esc <- character(length(v)); bmp <- v < 65536L
  esc[bmp] <- sprintf("\\u%04x", v[bmp])
  a <- v[!bmp] - 65536L
  esc[!bmp] <- sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] <- esc
  paste(out, collapse = "")
}
e_acute <- intToUtf8(0xE9); cjk <- intToUtf8(0x4E16); emoji <- intToUtf8(0x1F600)   # avoid \u literals (C-locale parser quirk)
s <- paste(rep(paste0("abc", e_acute, " "), 1e6), collapse = ""); j <- jsonlite::toJSON(list(t = s), auto_unbox = TRUE)
cat("non-ASCII-heavy 6 MB:"); print(system.time(a <- json_ascii(j))[["elapsed"]])
j2 <- jsonlite::toJSON(list(t = strrep("abcd ", 1e6)), auto_unbox = TRUE)
cat("pure ASCII 5 MB:"); print(system.time(b <- json_ascii(j2))[["elapsed"]])
cat("roundtrip 6 MB ok:", identical(jsonlite::parse_json(a)$t, s), "\n")
x <- paste0("emoji ", emoji, " and ", cjk, e_acute)
jx <- json_ascii(jsonlite::toJSON(x, auto_unbox = TRUE))
cat(jx, " ascii-only:", !any(charToRaw(jx) > as.raw(127L)), " roundtrip:", identical(jsonlite::parse_json(jx), x), "\n")
```

`json_ascii_fast.out`

```text
non-ASCII-heavy 6 MB:[1] 1.071
pure ASCII 5 MB:[1] 0.018
roundtrip 6 MB ok: TRUE 
"emoji \ud83d\ude00 and \u4e16\u00e9"  ascii-only: TRUE  roundtrip: TRUE 
```

### 5.7 Locale probes (why the transport writes ASCII JSON)

`cat_c_locale.R` shows `cat()` of UTF-8 text in the C locale is quadratic (the 600k-character case was measured separately at 296.41 s in an earlier run of the same shape and is recorded in the output file); `enc_escape.R` / `enc_literal.R` show that backslash-u escapes are safe in a C locale while raw UTF-8 bytes in source become native-encoded and are mangled by jsonlite.

`cat_c_locale.R`

```r
# cat() of a UTF-8-marked string to stdout in the current locale; timing to stderr.
n <- as.integer(commandArgs(TRUE)[1])
x <- paste(rep(paste0("abc", intToUtf8(0xE9), " "), n), collapse = "")
t <- system.time(cat(x, "\n", sep = ""))[["elapsed"]]
cat(sprintf("%-12s n=%7d non-ASCII chars, cat() to stdout: %7.2fs, Encoding=%s\n", Sys.getlocale("LC_CTYPE"), n, t, Encoding(x)), file = stderr())
```

`cat_c_locale.out`

```text
C            n=  25000 non-ASCII chars, cat() to stdout:    0.27s, Encoding=UTF-8
C            n=  50000 non-ASCII chars, cat() to stdout:    1.18s, Encoding=UTF-8
C            n= 100000 non-ASCII chars, cat() to stdout:    4.79s, Encoding=UTF-8
en_US.UTF-8  n= 600000 non-ASCII chars, cat() to stdout:    0.00s, Encoding=UTF-8
(earlier run, same script shape: C locale n=600000 -> cat 296.41 s)
```

`enc_escape.R`

```r
x <- "a\u00e9\u4e16\U0001F600"
cat("escape literal -> bytes:", paste(as.character(charToRaw(x)), collapse=" "), " Encoding:", Encoding(x), "\n")
j <- jsonlite::toJSON(x, auto_unbox = TRUE); cat("toJSON bytes:", paste(as.character(charToRaw(j)), collapse=" "), "\n")
```

`enc_literal.R`

```r
y <- "aé"   # raw UTF-8 bytes in the source (non-ASCII source file)
cat("raw-UTF-8 literal -> bytes:", paste(as.character(charToRaw(y)), collapse=" "), " Encoding:", Encoding(y), "\n")
j <- jsonlite::toJSON(y, auto_unbox = TRUE); cat("toJSON bytes:", paste(as.character(charToRaw(j)), collapse=" "), "\n")
```

`enc_probe.out`

```text
--- LC_ALL=C: enc_escape.R (ASCII source with backslash-u escapes)
escape literal -> bytes: 61 c3 a9 e4 b8 96 f0 9f 98 80  Encoding: UTF-8 
toJSON bytes: 22 61 c3 a9 e4 b8 96 f0 9f 98 80 22 
--- LC_ALL=C: enc_literal.R (raw UTF-8 bytes in source)
raw-UTF-8 literal -> bytes: 61 c3 a9  Encoding: unknown 
toJSON bytes: 22 61 3c 63 33 3e 3c 61 39 3e 22 
--- LC_ALL=en_US.UTF-8: enc_literal.R
raw-UTF-8 literal -> bytes: 61 c3 a9  Encoding: UTF-8 
toJSON bytes: 22 61 c3 a9 22 
```

### 5.8 Interop with a real third-party server (Claude Code `claude mcp serve`)

Only the handshake and `tools/list` are exercised (no model calls). The TypeScript-SDK server answers the modern probe with -32601, so the client falls back to 2025-11-25; 27 tools, 143,525 characters of tool metadata.

`test_interop.R`

```r
# Interop: pure-R client against a real third-party (TypeScript SDK) server:
# Claude Code's own MCP server mode (`claude mcp serve`). Only initialize +
# tools/list are exercised (no model calls).
source("mcp_client_stdio.R")
claude <- Sys.which("claude")
cat("claude:", claude, "\n")
t0 <- Sys.time()
conn <- mcp_stdio_connect("claude", c("mcp", "serve"), name = "claude-code",
                          probe_timeout = 5, timeout = 30)
cat(sprintf("era=%s version=%s server=%s/%s (connect %.2fs)\n", conn$era, conn$version,
            conn$server_info$name, conn$server_info$version, as.numeric(Sys.time() - t0, units = "secs")))
if (!is.null(conn$probe$error)) cat("probe answered with error:", format(conn$probe$error$code), conn$probe$error$message, "\n")
if (isTRUE(conn$probe$timed_out)) cat("probe timed out (legacy server ignored unknown pre-init request)\n")
cat("server capabilities:", jsonlite::toJSON(conn$server_capabilities, auto_unbox = TRUE), "\n")
tools <- mcp_list_tools(conn)
cat("n tools:", length(tools), "\n")
cat("tool names:", paste(vapply(tools, `[[`, "", "name"), collapse = ", "), "\n")
sz <- nchar(jsonlite::toJSON(tools, auto_unbox = TRUE))
cat("serialized tools/list size:", sz, "chars (~", round(sz / 4), "tokens)\n")
cl <- mcp_close(conn)
cat("closed: graceful =", cl$exited_gracefully, " exit status =", format(cl$exit_status), "\n")
```

`test_interop.out`

```text
claude: /Users/wanjun/.local/bin/claude 
era=legacy version=2025-11-25 server=claude/tengu/2.1.261 (connect 0.42s)
probe answered with error: -32601 Method not found 
server capabilities: {"tools":{}} 
n tools: 27 
tool names: Agent, TaskOutput, Bash, Read, Edit, Write, NotebookEdit, WebFetch, ReportFindings, WebSearch, TaskStop, Skill, DesignSync, Artifact, EnterWorktree, ExitWorktree, SendMessage, ListAgents, Workflow, CronCreate, CronDelete, CronList, ScheduleWakeup, RemoteTrigger, Monitor, PushNotification, ToolSearch 
serialized tools/list size: 143525 chars (~ 35881 tokens)
closed: graceful = TRUE  exit status = 0 
```

### 5.9 Streamable HTTP: in-process live-session server (httpuv) and client (httr2)

`mcp_session_server()` serves the live R session (tool `r_eval` evaluates in the global environment) over Streamable HTTP for both eras (modern header validation incl. `Mcp-Method`/`Mcp-Name`; legacy `Mcp-Session-Id` sessions incl. DELETE and 404 afterwards), with bearer token, Origin check and 127.0.0.1 binding; optional SSE framing. `mcp_http_connect()` / `mcp_http_request()` implement the dual-era client. `test_http.R` is the live session: it creates `big <- mtcars`, starts two servers (JSON and SSE), spawns `http_child.R` as the external agent and pumps the event loop while waiting (`httpuv::service(100)`; never `service(0)`). The agent creates `made_by_agent`, which the parent then prints.

`mcp_http.R`

```r
# Streamable HTTP MCP: an in-process SERVER (httpuv) that exposes the live R
# session, and a CLIENT (httr2) - both dual-era (legacy 2025-11-25 sessions /
# modern 2026-07-28 stateless).  Prototype for gptr; not production code.

`%||%` <- function(a, b) if (is.null(a)) b else a
empty_obj <- function() structure(list(), names = character())
json_ascii <- function(s) {
  s <- enc2utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)          # fast path (no regex on MBs)
  cp <- utf8ToInt(s)
  hi <- which(cp > 127L)
  out <- intToUtf8(cp, multiple = TRUE)
  v <- cp[hi]; esc <- character(length(v)); bmp <- v < 65536L
  esc[bmp] <- sprintf("\\u%04x", v[bmp])
  a <- v[!bmp] - 65536L
  esc[!bmp] <- sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] <- esc
  paste(out, collapse = "")
}
to_json <- function(x) json_ascii(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
K_VER <- "io.modelcontextprotocol/protocolVersion"
K_CAPS <- "io.modelcontextprotocol/clientCapabilities"
K_CINFO <- "io.modelcontextprotocol/clientInfo"
K_SINFO <- "io.modelcontextprotocol/serverInfo"
MODERN <- "2026-07-28"
LEGACY <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")

# Header value encoding for Mcp-Name / Mcp-Param-* (2026-07-28 "Value Encoding")
mcp_header_value <- function(x) {
  x <- enc2utf8(as.character(x))
  safe <- !grepl("[^\\x20-\\x7e\\t]", x, useBytes = TRUE) && !grepl("^\\s|\\s$", x) &&
    !(startsWith(x, "=?base64?") && endsWith(x, "?="))
  if (safe) x else paste0("=?base64?", jsonlite::base64_enc(charToRaw(x)), "?=")
}

random_token <- function(bytes = 24L) {
  if (requireNamespace("openssl", quietly = TRUE)) return(paste(as.character(openssl::rand_bytes(bytes)), collapse = ""))
  paste(sample(c(0:9, letters[1:6]), 2L * bytes, TRUE), collapse = "")
}

# =============================================================================
# SERVER: serve the live R session over Streamable HTTP (httpuv, 127.0.0.1)
# =============================================================================
# Tools are R functions evaluated IN THIS PROCESS, when httpuv callbacks run -
# i.e. at the idle console (later event loop) or whenever the host code calls
# httpuv::service() / later::run_now() while it waits for something.
mcp_session_server <- function(port = httpuv::randomPort(host = "127.0.0.1"),
                               token = random_token(), envir = globalenv(),
                               sse = FALSE, log = function(...) NULL) {
  sessions <- new.env(parent = emptyenv())
  origins <- c(sprintf("http://127.0.0.1:%d", port), sprintf("http://localhost:%d", port))
  info <- list(name = "gptr-live-session", version = "0.0.1")
  tools <- list(list(
    name = "r_eval",
    description = "Evaluate R code in the user's live R session (global environment). Objects persist.",
    inputSchema = list(type = "object",
                       properties = list(code = list(type = "string", description = "R code")),
                       required = I("code"), additionalProperties = FALSE),
    annotations = list(destructiveHint = TRUE, openWorldHint = FALSE)))

  run_r_eval <- function(code) {
    out <- character(); val <- NULL; err <- NULL
    out <- utils::capture.output(val <- tryCatch(
      withVisible(eval(parse(text = code, keep.source = FALSE), envir = envir)),
      error = function(e) { err <<- conditionMessage(e); NULL }))
    if (!is.null(val) && isTRUE(val$visible)) out <- c(out, utils::capture.output(print(val$value)))
    if (!is.null(err)) return(list(content = list(list(type = "text", text = paste(c(out, paste("Error:", err)), collapse = "\n"))), isError = TRUE))
    list(content = list(list(type = "text", text = paste(out, collapse = "\n"))), isError = FALSE)
  }

  resp <- function(status, body = NULL, headers = list(), content_type = "application/json") {
    h <- c(list(`Content-Type` = content_type), headers)
    list(status = status, headers = h, body = if (is.null(body)) "" else body)
  }
  rpc_error <- function(status, id, code, message, data = NULL) {
    e <- list(code = code, message = message); if (!is.null(data)) e$data <- data
    resp(status, to_json(list(jsonrpc = "2.0", id = id, error = e)))
  }
  rpc_result <- function(id, result, headers = list(), notifications = list()) {
    msg <- to_json(list(jsonrpc = "2.0", id = id, result = result))
    if (!sse) return(resp(200L, msg, headers))
    # SSE framing: request-scoped notifications first, final response last.
    ev <- c(vapply(notifications, function(n) paste0("event: message\ndata: ", to_json(n), "\n\n"), ""),
            paste0("event: message\ndata: ", msg, "\n\n"))
    resp(200L, paste(ev, collapse = ""), c(headers, list(`Cache-Control` = "no-cache", `X-Accel-Buffering` = "no")),
         content_type = "text/event-stream")
  }

  handle <- function(req) {
    h <- function(name) req[[paste0("HTTP_", toupper(gsub("-", "_", name)))]]
    origin <- h("Origin")
    if (!is.null(origin) && !(origin %in% origins)) return(resp(403L, '{"error":"forbidden origin"}'))
    if (!identical(h("Authorization"), paste("Bearer", token)))
      return(resp(401L, "", list(`WWW-Authenticate` = 'Bearer error="invalid_token"')))
    if (req$REQUEST_METHOD != "POST") {
      if (req$REQUEST_METHOD == "DELETE" && !is.null(h("Mcp-Session-Id"))) {
        rm(list = intersect(h("Mcp-Session-Id"), ls(sessions)), envir = sessions); return(resp(200L))
      }
      return(resp(405L, "", list(Allow = "POST")))
    }
    body <- rawToChar(req$rook.input$read())
    msg <- tryCatch(jsonlite::parse_json(body, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) return(rpc_error(400L, NULL, -32700L, "Parse error"))
    id <- msg$id; method <- msg$method; params <- msg$params %||% list()
    log(req$REQUEST_METHOD, " ", method, " hdr-version=", h("MCP-Protocol-Version") %||% "-")
    meta_ver <- params[["_meta"]][[K_VER]]

    # ---------- modern (stateless) ----------
    if (!is.null(meta_ver)) {
      hv <- h("MCP-Protocol-Version")
      if (!identical(hv, meta_ver)) return(rpc_error(400L, id, -32020L, "Header mismatch: MCP-Protocol-Version"))
      if (!identical(h("Mcp-Method"), method)) return(rpc_error(400L, id, -32020L, "Header mismatch: Mcp-Method"))
      if (meta_ver != MODERN)
        return(rpc_error(400L, id, -32022L, "Unsupported protocol version",
                         list(supported = I(c(MODERN, LEGACY)), requested = meta_ver)))
      if (is.null(id)) return(resp(202L))
      fin <- function(r, cache = FALSE) {
        r$resultType <- "complete"; r[["_meta"]] <- setNames(list(info), K_SINFO)
        if (cache) { r$ttlMs <- 0L; r$cacheScope <- "private" }; r
      }
      if (method == "server/discover")
        return(rpc_result(id, fin(list(supportedVersions = I(MODERN), capabilities = list(tools = empty_obj())), TRUE)))
      if (method == "tools/list") return(rpc_result(id, fin(list(tools = tools), TRUE)))
      if (method == "tools/call") {
        if (!identical(h("Mcp-Name"), mcp_header_value(params$name)))
          return(rpc_error(400L, id, -32020L, "Header mismatch: Mcp-Name"))
        if (!identical(params$name, "r_eval")) return(rpc_error(200L, id, -32602L, "Unknown tool"))
        return(rpc_result(id, fin(run_r_eval(params$arguments$code))))
      }
      return(rpc_error(404L, id, -32601L, "Method not found"))
    }

    # ---------- legacy (session-based) ----------
    if (identical(method, "initialize")) {
      v <- params$protocolVersion; v <- if (!is.null(v) && v %in% LEGACY) v else LEGACY[1]
      sid <- random_token(16L)
      assign(sid, list(version = v), envir = sessions)
      return(rpc_result(id, list(protocolVersion = v, capabilities = list(tools = empty_obj()), serverInfo = info),
                        headers = list(`Mcp-Session-Id` = sid)))
    }
    sid <- h("Mcp-Session-Id")
    if (is.null(sid)) return(rpc_error(400L, id, -32600L, "Missing Mcp-Session-Id (send initialize, or use 2026-07-28 _meta)"))
    if (!exists(sid, envir = sessions, inherits = FALSE)) return(resp(404L, ""))
    if (is.null(id)) return(resp(202L))                        # notifications / responses
    if (method == "ping") return(rpc_result(id, empty_obj()))
    if (method == "tools/list") return(rpc_result(id, list(tools = tools)))
    if (method == "tools/call") {
      if (!identical(params$name, "r_eval")) return(rpc_error(200L, id, -32602L, "Unknown tool"))
      note <- list(jsonrpc = "2.0", method = "notifications/progress",
                   params = list(progressToken = params[["_meta"]]$progressToken %||% "none", progress = 1, total = 1))
      return(rpc_result(id, run_r_eval(params$arguments$code), notifications = list(note)))
    }
    rpc_error(200L, id, -32601L, "Method not found")
  }

  srv <- httpuv::startServer("127.0.0.1", port, list(call = function(req) {
    tryCatch(handle(req), error = function(e) resp(500L, to_json(list(error = conditionMessage(e)))))
  }))
  list(url = sprintf("http://127.0.0.1:%d/mcp", port), token = token, port = port,
       stop = function() httpuv::stopServer(srv))
}

# =============================================================================
# CLIENT: Streamable HTTP with httr2 (JSON or SSE responses, both eras)
# =============================================================================
mcp_http_connect <- function(url, headers = list(), protocol = c("auto", "modern", "legacy"),
                             client_info = list(name = "gptr", version = "0.0.0.9000"),
                             capabilities = empty_obj(), timeout = 60) {
  protocol <- match.arg(protocol)
  conn <- new.env(parent = emptyenv())
  conn$url <- url; conn$headers <- headers; conn$timeout <- timeout
  conn$client_info <- client_info; conn$capabilities <- capabilities
  conn$next_id <- 0L; conn$era <- NA_character_; conn$version <- NA_character_
  conn$session_id <- NULL; conn$notifications <- list()
  if (protocol %in% c("auto", "modern")) {
    r <- mcp_http_request(conn, "server/discover", list(), modern_version = MODERN, raw = TRUE)
    if (!is.null(r$result$supportedVersions)) { conn$era <- "modern"; conn$version <- MODERN }
    else if (!is.null(r$error$code) && r$error$code %in% c(-32022, -32020, -32021)) {
      sup <- intersect(MODERN, unlist(r$error$data$supported))
      if (length(sup)) { conn$era <- "modern"; conn$version <- sup[1] }
    }
    conn$probe <- r
  }
  if (is.na(conn$era)) {
    r <- mcp_http_request(conn, "initialize", list(protocolVersion = LEGACY[1], capabilities = capabilities,
                                                   clientInfo = client_info), raw = TRUE)
    if (!is.null(r$error)) stop("initialize failed: ", r$error$message)
    conn$era <- "legacy"; conn$version <- r$result$protocolVersion
    mcp_http_request(conn, "notifications/initialized", NULL, notification = TRUE)
  }
  conn
}

mcp_http_request <- function(conn, method, params = NULL, modern_version = NULL,
                             notification = FALSE, raw = FALSE) {
  ver <- modern_version %||% (if (identical(conn$era, "modern")) conn$version else NULL)
  if (!is.null(ver)) {
    params <- params %||% list()
    params[["_meta"]] <- c(params[["_meta"]] %||% list(),
                           setNames(list(ver, conn$capabilities, conn$client_info), c(K_VER, K_CAPS, K_CINFO)))
  }
  msg <- list(jsonrpc = "2.0", method = method)
  if (!notification) { conn$next_id <- conn$next_id + 1L; msg$id <- conn$next_id }
  if (!is.null(params)) msg$params <- params
  hdr <- c(list(Accept = "application/json, text/event-stream", `Content-Type` = "application/json"), conn$headers)
  if (!is.null(ver)) {
    hdr[["MCP-Protocol-Version"]] <- ver
    hdr[["Mcp-Method"]] <- method
    if (method %in% c("tools/call", "prompts/get")) hdr[["Mcp-Name"]] <- mcp_header_value(params$name)
    if (method == "resources/read") hdr[["Mcp-Name"]] <- mcp_header_value(params$uri)
  } else if (!is.na(conn$version)) {
    hdr[["MCP-Protocol-Version"]] <- conn$version
  }
  if (!is.null(conn$session_id)) hdr[["Mcp-Session-Id"]] <- conn$session_id
  req <- httr2::request(conn$url) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!hdr) |>
    httr2::req_body_raw(charToRaw(to_json(msg)), type = "application/json") |>
    httr2::req_timeout(conn$timeout) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform_connection(req)
  on.exit(close(resp), add = TRUE)
  status <- httr2::resp_status(resp)
  sid <- httr2::resp_header(resp, "Mcp-Session-Id")
  if (!is.null(sid) && identical(method, "initialize")) conn$session_id <- sid
  if (notification) return(invisible(status))
  ctype <- httr2::resp_content_type(resp) %||% ""
  out <- NULL
  if (grepl("text/event-stream", ctype, fixed = TRUE)) {
    repeat {                               # read events until OUR response arrives
      ev <- httr2::resp_stream_sse(resp)
      if (is.null(ev)) { if (httr2::resp_stream_is_complete(resp)) break else next }
      if (!nzchar(ev$data)) next
      m <- jsonlite::parse_json(ev$data, simplifyVector = FALSE)
      if (!is.null(m$id) && (!is.null(m$result) || !is.null(m$error))) { out <- m; break }
      conn$notifications <- c(conn$notifications, list(m))   # progress, logging, ...
    }
  } else {
    body <- tryCatch(httr2::resp_body_raw(resp), error = function(e) raw())
    txt <- if (length(body)) rawToChar(body) else ""
    out <- if (nzchar(txt)) tryCatch(jsonlite::parse_json(txt, simplifyVector = FALSE), error = function(e) NULL)
  }
  if (is.null(out)) out <- list(error = list(code = NA, message = sprintf("HTTP %d with no JSON-RPC body", status)))
  out$http_status <- status
  if (raw) return(out)
  if (!is.null(out$error)) stop(sprintf("MCP HTTP %s error %s: %s", method, format(out$error$code), out$error$message))
  out$result
}

mcp_http_close <- function(conn) {
  if (identical(conn$era, "legacy") && !is.null(conn$session_id)) {
    req <- httr2::request(conn$url) |> httr2::req_method("DELETE") |>
      httr2::req_headers(!!!c(conn$headers, list(`Mcp-Session-Id` = conn$session_id))) |>
      httr2::req_error(is_error = function(resp) FALSE)
    invisible(httr2::resp_status(httr2::req_perform(req)))
  }
}
```

`http_child.R`

```r
# Child process = stands in for an external agent (Claude Code / Codex) that
# talks MCP Streamable HTTP to the user's live R session.
source("mcp_http.R")
a <- commandArgs(TRUE); url_json <- a[1]; url_sse <- a[2]; token <- a[3]
auth <- list(Authorization = paste("Bearer", token))
show <- function(label, x) cat(sprintf("%-38s %s\n", label, x))

c1 <- mcp_http_connect(url_json, headers = auth)
show("json server, auto-detect ->", paste(c1$era, c1$version))
tl <- mcp_http_request(c1, "tools/list")
show("tools/list ->", paste(vapply(tl$tools, `[[`, "", "name"), "| resultType:", tl$resultType, "ttlMs:", tl$ttlMs))
r <- mcp_http_request(c1, "tools/call", list(name = "r_eval", arguments = list(code = "nrow(big)")))
show("r_eval nrow(big) ->", r$content[[1]]$text)
r <- mcp_http_request(c1, "tools/call", list(name = "r_eval",
       arguments = list(code = "made_by_agent <- round(tapply(big$mpg, big$cyl, mean), 2); made_by_agent")))
show("r_eval create object ->", gsub("\n", " | ", r$content[[1]]$text))
r <- mcp_http_request(c1, "tools/call", list(name = "r_eval", arguments = list(code = "stop('boom \u00e9')")))
show("r_eval error -> isError:", paste(r$isError, "|", r$content[[1]]$text))
bad <- mcp_http_request(c1, "tools/call", list(name = "nope"), raw = TRUE)
show("unknown tool ->", paste(bad$http_status, bad$error$code, bad$error$message))

c2 <- mcp_http_connect(url_json, headers = auth, protocol = "legacy")
show("json server, forced legacy ->", paste(c2$era, c2$version, "session:", substr(c2$session_id, 1, 8), "..."))
r <- mcp_http_request(c2, "tools/call", list(name = "r_eval", arguments = list(code = "exists('made_by_agent')")))
show("legacy r_eval ->", r$content[[1]]$text)
show("legacy DELETE session ->", mcp_http_close(c2))
gone <- mcp_http_request(c2, "tools/list", raw = TRUE)
show("request after DELETE ->", paste("HTTP", gone$http_status))

c3 <- mcp_http_connect(url_sse, headers = auth, protocol = "legacy")
r <- mcp_http_request(c3, "tools/call", list(name = "r_eval", arguments = list(code = "sum(1:10)"),
                                               `_meta` = list(progressToken = "tok1")))
show("SSE response r_eval ->", paste(r$content[[1]]$text, "| notifications seen:", length(c3$notifications),
                                     c3$notifications[[1]]$method))
c4 <- mcp_http_connect(url_sse, headers = auth)
r <- mcp_http_request(c4, "tools/call", list(name = "r_eval", arguments = list(code = "paste('h\u00e9llo', '\u4e16\u754c')")))
show("SSE modern, UTF-8 round trip ->", paste(r$content[[1]]$text, "| ok:", grepl("h\u00e9llo", r$content[[1]]$text)))

noauth <- tryCatch(mcp_http_connect(url_json), error = function(e) conditionMessage(e))
show("no bearer token ->", noauth)
req <- httr2::request(url_json) |> httr2::req_method("POST") |>
  httr2::req_headers(Origin = "http://evil.example", !!!auth) |> httr2::req_body_raw("{}", "application/json") |>
  httr2::req_error(is_error = function(r) FALSE)
show("foreign Origin ->", paste("HTTP", httr2::resp_status(httr2::req_perform(req))))
req <- httr2::request(url_json) |> httr2::req_headers(!!!auth) |> httr2::req_error(is_error = function(r) FALSE)
show("GET endpoint ->", paste("HTTP", httr2::resp_status(httr2::req_perform(req))))
# modern request with mismatching header
req <- httr2::request(url_json) |> httr2::req_method("POST") |>
  httr2::req_headers(!!!auth, `MCP-Protocol-Version` = "2026-07-28", `Mcp-Method` = "tools/list") |>
  httr2::req_body_raw(to_json(list(jsonrpc = "2.0", id = 9, method = "tools/call",
     params = list(name = "r_eval", arguments = list(code = "1"), `_meta` = setNames(list("2026-07-28", empty_obj()), c(K_VER, K_CAPS))))), "application/json") |>
  httr2::req_error(is_error = function(r) FALSE)
rr <- httr2::req_perform(req)
show("Mcp-Method header mismatch ->", paste("HTTP", httr2::resp_status(rr), httr2::resp_body_string(rr)))
```

`test_http.R`

```r
# The "live R session": holds a big object, serves MCP over HTTP in-process,
# and keeps servicing tool calls while it waits for a subprocess (as gptr would
# while a `claude -p` / `codex exec` plan-provider subprocess runs).
source("mcp_http.R")
big <- mtcars
srv_json <- mcp_session_server(log = function(...) cat("  [live-session]", ..., "\n"))
srv_sse <- mcp_session_server(token = srv_json$token, sse = TRUE)
cat("serving", srv_json$url, "and", srv_sse$url, "\n")
rscript <- file.path(R.home("bin"), "Rscript")
out <- "http_child.out"; unlink(out)
child <- processx::process$new(rscript, c("--vanilla", "http_child.R", srv_json$url, srv_sse$url, srv_json$token),
                               stdout = out, stderr = "2>&1")
t0 <- Sys.time(); ticks <- 0L
while (child$is_alive() && Sys.time() - t0 < 60) { httpuv::service(100); ticks <- ticks + 1L }   # live session stays responsive
if (child$is_alive()) { cat("TIMEOUT: killing child\n"); child$kill() }
later::run_now(0)   # NB: httpuv::service(0) would serve FOREVER in a non-interactive session
cat(sprintf("child exited with %d after %.1fs; %d service ticks\n", child$get_exit_status(),
            as.numeric(Sys.time() - t0, units = "secs"), ticks))
cat(readLines(out), sep = "\n")
cat("\nBack in the live session: exists('made_by_agent') =", exists("made_by_agent"), "\n")
print(made_by_agent)
srv_json$stop(); srv_sse$stop()
```

`test_http.out`

```text
serving http://127.0.0.1:25362/mcp and http://127.0.0.1:21221/mcp 
  [live-session] POST   server/discover  hdr-version= 2026-07-28 
  [live-session] POST   tools/list  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   initialize  hdr-version= - 
  [live-session] POST   notifications/initialized  hdr-version= 2025-11-25 
  [live-session] POST   tools/call  hdr-version= 2025-11-25 
  [live-session] POST   tools/list  hdr-version= 2025-11-25 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
child exited with 0 after 0.5s; 104 service ticks
json server, auto-detect ->            modern 2026-07-28
tools/list ->                          r_eval | resultType: complete ttlMs: 0
r_eval nrow(big) ->                    [1] 32
r_eval create object ->                    4     6     8  | 26.66 19.74 15.10 
r_eval error -> isError:               TRUE | Error: boom <U+00E9>
unknown tool ->                        200 -32602 Unknown tool
json server, forced legacy ->          legacy 2025-11-25 session: 09760cf8 ...
legacy r_eval ->                       [1] TRUE
legacy DELETE session ->               200
request after DELETE ->                HTTP 404
SSE response r_eval ->                 [1] 55 | notifications seen: 1 notifications/progress
SSE modern, UTF-8 round trip ->        [1] "h<U+00E9>llo <U+4E16><U+754C>" | ok: FALSE
no bearer token ->                     initialize failed: HTTP 401 with no JSON-RPC body
foreign Origin ->                      HTTP 403
GET endpoint ->                        HTTP 405
Mcp-Method header mismatch ->          HTTP 400 {"jsonrpc":"2.0","id":9,"error":{"code":-32020,"message":"Header mismatch: Mcp-Method"}}

Back in the live session: exists('made_by_agent') = TRUE 
    4     6     8 
26.66 19.74 15.10 
```

`test_http_utf8.out`

```text
serving http://127.0.0.1:34417/mcp and http://127.0.0.1:34643/mcp 
  [live-session] POST   server/discover  hdr-version= 2026-07-28 
  [live-session] POST   tools/list  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
  [live-session] POST   initialize  hdr-version= - 
  [live-session] POST   notifications/initialized  hdr-version= 2025-11-25 
  [live-session] POST   tools/call  hdr-version= 2025-11-25 
  [live-session] POST   tools/list  hdr-version= 2025-11-25 
  [live-session] POST   tools/call  hdr-version= 2026-07-28 
child exited with 0 after 1.3s; 109 service ticks
json server, auto-detect ->            modern 2026-07-28
tools/list ->                          r_eval | resultType: complete ttlMs: 0
r_eval nrow(big) ->                    [1] 32
r_eval create object ->                    4     6     8  | 26.66 19.74 15.10 
r_eval error -> isError:               TRUE | Error: boom é
unknown tool ->                        200 -32602 Unknown tool
json server, forced legacy ->          legacy 2025-11-25 session: 1b3f9498 ...
legacy r_eval ->                       [1] TRUE
legacy DELETE session ->               200
request after DELETE ->                HTTP 404
SSE response r_eval ->                 [1] 55 | notifications seen: 1 notifications/progress
SSE modern, UTF-8 round trip ->        [1] "héllo 世界" | ok: TRUE
no bearer token ->                     initialize failed: HTTP 401 with no JSON-RPC body
foreign Origin ->                      HTTP 403
GET endpoint ->                        HTTP 405
Mcp-Method header mismatch ->          HTTP 400 {"jsonrpc":"2.0","id":9,"error":{"code":-32020,"message":"Header mismatch: Mcp-Method"}}

Back in the live session: exists('made_by_agent') = TRUE 
    4     6     8 
26.66 19.74 15.10 
```

### 5.10 stdio-to-HTTP bridge into the live session

For stdio-only clients (e.g. a Claude Desktop entry `{"command":"Rscript","args":["mcp_bridge.R", url]}`): the bridge relays each JSON-RPC line to the in-session HTTP server, adding the correct headers per era. The agent below talks stdio to the bridge in both eras; the objects it creates appear in the parent session, which pumps with `later::run_now(0.1)`.

`mcp_bridge.R`

```r
# stdio <-> Streamable HTTP bridge: lets stdio-only MCP clients (e.g. Claude
# Desktop config {"command":"Rscript","args":["mcp_bridge.R", url]}) reach the
# live R session's in-process HTTP MCP server. Token comes from the environment.
source("mcp_http.R")
a <- commandArgs(TRUE); url <- a[1]; token <- Sys.getenv("GPTR_MCP_TOKEN")
sid <- NULL; ver <- NULL
con <- file("stdin", open = "r")
out <- function(txt) { cat(json_ascii(txt), "\n", sep = ""); flush(stdout()) }
repeat {
  line <- readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (!length(line)) break
  msg <- tryCatch(jsonlite::parse_json(line, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(msg)) next
  mv <- msg$params[["_meta"]][[K_VER]]
  hdr <- list(Accept = "application/json, text/event-stream", Authorization = paste("Bearer", token))
  if (!is.null(mv)) {
    hdr[["MCP-Protocol-Version"]] <- mv; hdr[["Mcp-Method"]] <- msg$method
    if (!is.null(msg$params$name)) hdr[["Mcp-Name"]] <- mcp_header_value(msg$params$name)
    if (!is.null(msg$params$uri)) hdr[["Mcp-Name"]] <- mcp_header_value(msg$params$uri)
  } else {
    if (!is.null(ver)) hdr[["MCP-Protocol-Version"]] <- ver
    if (!is.null(sid)) hdr[["Mcp-Session-Id"]] <- sid
  }
  resp <- httr2::request(url) |> httr2::req_method("POST") |> httr2::req_headers(!!!hdr) |>
    httr2::req_body_raw(line, "application/json") |> httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_perform()
  if (identical(msg$method, "initialize")) {
    sid <- httr2::resp_header(resp, "Mcp-Session-Id")
    ver <- tryCatch(jsonlite::parse_json(httr2::resp_body_string(resp))$result$protocolVersion, error = function(e) NULL)
  }
  if (is.null(msg$id)) next                                   # notification: 202, nothing to relay
  body <- httr2::resp_body_string(resp)
  if (grepl("event-stream", httr2::resp_content_type(resp) %||% "")) {
    for (d in regmatches(body, gregexpr("(?m)^data: .*$", body, perl = TRUE))[[1]]) out(sub("^data: ", "", d))
  } else if (nzchar(body)) out(body)
  else out(to_json(list(jsonrpc = "2.0", id = msg$id, error = list(code = -32603L, message = sprintf("HTTP %d", httr2::resp_status(resp))))))
}
```

`bridge_agent.R`

```r
# the external "agent": speaks stdio MCP to the bridge process
source("mcp_client_stdio.R")
a <- commandArgs(TRUE)
for (proto in c("auto", "legacy")) {
  conn <- mcp_stdio_connect(file.path(R.home("bin"), "Rscript"), c("--vanilla", "mcp_bridge.R", a[1]),
                            name = "bridge", protocol = proto,
                            env = c(Sys.getenv()[c("PATH", "HOME")], GPTR_MCP_TOKEN = a[2]))
  r <- mcp_call_tool(conn, "r_eval", list(code = sprintf("via_bridge_%s <- nrow(big) * 2; via_bridge_%s", proto, proto)))
  cat(sprintf("[agent] protocol=%s era=%s version=%s tools=%s -> %s\n", proto, conn$era, conn$version,
              paste(vapply(mcp_list_tools(conn), `[[`, "", "name"), collapse = ","), format(r)))
  mcp_close(conn)
}
```

`test_bridge.R`

```r
source("mcp_http.R")
big <- mtcars
srv <- mcp_session_server()
child <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", "bridge_agent.R", srv$url, srv$token),
                               stdout = "bridge_agent.out", stderr = "2>&1")
t0 <- Sys.time()
while (child$is_alive() && Sys.time() - t0 < 60) later::run_now(0.1)   # pump; never httpuv::service(0)
cat(readLines("bridge_agent.out"), sep = "\n")
cat("[live session] via_bridge_auto =", via_bridge_auto, " via_bridge_legacy =", via_bridge_legacy, "\n")
srv$stop()
```

`test_bridge.out`

```text
[agent] protocol=auto era=modern version=2026-07-28 tools=r_eval -> [1] 64
[agent] protocol=legacy era=legacy version=2025-11-25 tools=r_eval -> [1] 64
[live session] via_bridge_auto = 64  via_bridge_legacy = 64 
```

### 5.11 Harness-agnostic MCP config discovery (REQ-30)

`mcp_config.R` reads the 16 locations of 9 harnesses and normalises them; `test_config.R` runs it against synthetic fixture homes/projects (not the user's real files) and shows the interpolation rules.

**Defect found in verification:** `fixtures/home/.claude.json` hard-codes the absolute path `.../work/16/proto/fixtures/project` as its `projects` key. When the prototype directory is copied elsewhere, the `local-db` (claude-code:local) entry silently disappears and only 13 servers are found. After the key was rewritten to the new location, the output was byte-identical to `test_config.out`. The gptr test suite should write this fixture at test time with `normalizePath()` of the project fixture.

`mcp_config.R`

```r
# Harness-agnostic MCP config discovery + normalisation (prototype for REQ-30).
# Reads the MCP server definitions that other agent harnesses already have and
# normalises them to one R structure. Values are NOT interpolated here (secrets
# stay as ${VAR} placeholders until connect time).
source("toml_read.R")
`%||%` <- function(a, b) if (is.null(a)) b else a

mcp_config_sources <- function(project = getwd(), home = Sys.getenv("HOME", path.expand("~")),
                               sysname = Sys.info()[["sysname"]],
                               appdata = Sys.getenv("APPDATA"),
                               codex_home = Sys.getenv("CODEX_HOME", file.path(home, ".codex")),
                               gptr_user_dir = file.path(home, ".config", "gptr")) {
  app_support <- switch(sysname,
    Darwin = file.path(home, "Library", "Application Support"),
    Windows = if (nzchar(appdata)) appdata else file.path(home, "AppData", "Roaming"),
    file.path(home, ".config"))
  s <- function(harness, scope, path, format) data.frame(harness = harness, scope = scope, path = path, format = format)
  rbind(
    s("gptr",           "project", file.path(project, ".gptr", "mcp.json"),                 "mcpServers"),
    s("gptr",           "user",    file.path(gptr_user_dir, "mcp.json"),                     "mcpServers"),
    s("claude-code",    "project", file.path(project, ".mcp.json"),                          "mcpServers"),
    s("claude-code",    "local+user", file.path(home, ".claude.json"),                       "claude.json"),
    s("claude-desktop", "user",    file.path(app_support, "Claude", "claude_desktop_config.json"), "mcpServers"),
    s("codex",          "project", file.path(project, ".codex", "config.toml"),              "codex-toml"),
    s("codex",          "user",    file.path(codex_home, "config.toml"),                     "codex-toml"),
    s("cursor",         "project", file.path(project, ".cursor", "mcp.json"),                "mcpServers"),
    s("cursor",         "user",    file.path(home, ".cursor", "mcp.json"),                   "mcpServers"),
    s("vscode",         "project", file.path(project, ".vscode", "mcp.json"),                "vscode"),
    s("vscode",         "user",    file.path(app_support, "Code", "User", "mcp.json"),       "vscode"),
    s("pi",             "project", file.path(project, ".pi", "mcp.json"),                    "mcpServers"),
    s("pi",             "user",    file.path(home, ".pi", "agent", "mcp.json"),              "mcpServers"),
    s("gemini",         "project", file.path(project, ".gemini", "settings.json"),           "gemini"),
    s("gemini",         "user",    file.path(home, ".gemini", "settings.json"),              "gemini"),
    s("mcptools",       "user",    file.path(home, ".config", "mcptools", "config.json"),    "mcpServers")
  )
}

# One normalised record per server.
mcp_server_spec <- function(name, harness, scope, path, e, transport = NULL) {
  transport <- transport %||% {
    t <- e$type %||% ""
    if (t %in% c("sse")) "sse"
    else if (t %in% c("http", "streamable-http", "streamableHttp")) "http"
    else if (t %in% c("ws")) "ws"
    else if (!is.null(e$command)) "stdio" else if (!is.null(e$url)) "http" else NA_character_
  }
  list(name = name, transport = transport,
       command = e$command, args = unlist(e$args %||% list()), env = e$env, cwd = e$cwd,
       url = e$url, headers = e$headers, bearer_token_env_var = e$bearer_token_env_var,
       enabled = !isFALSE(e$enabled) && !isTRUE(e$disabled),
       tools_allow = unlist(e$enabled_tools %||% e$includeTools),
       tools_deny = unlist(e$disabled_tools %||% e$excludeTools),
       timeout = e$timeout, oauth = e$oauth,
       source = list(harness = harness, scope = scope, path = path))
}

read_json_file <- function(p) jsonlite::fromJSON(p, simplifyVector = FALSE)

mcp_read_source <- function(harness, scope, path, format, project) {
  if (!file.exists(path)) return(list())
  out <- list()
  add <- function(entries, sc = scope, tr = NULL) {
    for (nm in names(entries)) out[[length(out) + 1L]] <<- mcp_server_spec(nm, harness, sc, path, entries[[nm]], tr)
  }
  x <- tryCatch(switch(format, `codex-toml` = toml_read(path), read_json_file(path)),
                error = function(e) { warning("cannot parse ", path, ": ", conditionMessage(e)); NULL })
  if (is.null(x)) return(list())
  switch(format,
    mcpServers = add(x$mcpServers),
    claude.json = {
      add(x$mcpServers, "user")
      pj <- x$projects[[normalizePath(project, winslash = "/", mustWork = FALSE)]]
      if (!is.null(pj)) add(pj$mcpServers, "local")
    },
    vscode = {
      for (nm in names(x$servers)) {
        e <- x$servers[[nm]]
        sp <- mcp_server_spec(nm, harness, scope, path, e)
        sp$needs_input <- grepl("\\$\\{input:", jsonlite::toJSON(e, auto_unbox = TRUE))
        out[[length(out) + 1L]] <- sp
      }
    },
    gemini = {
      for (nm in names(x$mcpServers)) {
        e <- x$mcpServers[[nm]]
        tr <- if (!is.null(e$httpUrl)) "http" else if (!is.null(e$url)) "sse" else "stdio"
        if (!is.null(e$httpUrl)) e$url <- e$httpUrl
        out[[length(out) + 1L]] <- mcp_server_spec(nm, harness, scope, path, e, tr)
      }
    },
    `codex-toml` = {
      for (nm in names(x$mcp_servers)) {
        e <- x$mcp_servers[[nm]]
        e$headers <- c(e$http_headers, lapply(e$env_http_headers, function(v) paste0("${", v, "}")))
        out[[length(out) + 1L]] <- mcp_server_spec(nm, harness, scope, path, e)
      }
    })
  out
}

# Discover, then resolve name collisions: earlier rows of mcp_config_sources()
# win (gptr > claude-code > claude-desktop > codex > cursor > vscode > pi > ...;
# project > user within a harness). Same command/url seen in several harnesses
# is reported once with all its sources.
mcp_discover_servers <- function(project = getwd(), ...) {
  src <- mcp_config_sources(project = project, ...)
  all <- list()
  for (k in seq_len(nrow(src))) {
    all <- c(all, mcp_read_source(src$harness[k], src$scope[k], src$path[k], src$format[k], project))
  }
  fp <- vapply(all, function(s) paste(s$transport, s$command %||% "", paste(s$args, collapse = " "), s$url %||% ""), "")
  keep <- list(); seen_fp <- character(); seen_name <- character()
  for (j in seq_along(all)) {
    s <- all[[j]]
    if (fp[j] %in% seen_fp) {                           # same server, another harness
      w <- match(fp[j], seen_fp)
      keep[[w]]$also_in <- c(keep[[w]]$also_in, paste0(s$source$harness, ":", s$source$scope))
      next
    }
    if (s$name %in% seen_name) s$name <- paste0(s$source$harness, "_", s$name)   # disambiguate
    keep[[length(keep) + 1L]] <- s; seen_fp <- c(seen_fp, fp[j]); seen_name <- c(seen_name, s$name)
  }
  keep
}

# Placeholder expansion at connect time. Supports ${VAR}, ${VAR:-default}
# (Claude Code), ${env:VAR} (VS Code / Cursor), {env:VAR} (opencode),
# ${userHome}, ${workspaceFolder}. Unknown ${input:...} is left for the UI.
mcp_interpolate <- function(x, project = getwd(), getenv = Sys.getenv) {
  if (is.list(x)) return(lapply(x, mcp_interpolate, project = project, getenv = getenv))
  if (!is.character(x)) return(x)
  vapply(x, function(s) {
    s <- gsub("${userHome}", path.expand("~"), s, fixed = TRUE)
    s <- gsub("${workspaceFolder}", project, s, fixed = TRUE)
    repeat {
      m <- regmatches(s, regexpr("\\$\\{(env:)?[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\\}|\\{env:[A-Za-z_][A-Za-z0-9_]*\\}", s))
      if (!length(m)) break
      inner <- sub("^\\$?\\{(env:)?", "", sub("\\}$", "", m))
      var <- sub(":-.*$", "", inner)
      def <- if (grepl(":-", inner, fixed = TRUE)) sub("^[^:]*:-", "", inner) else NA_character_
      val <- getenv(var, unset = NA_character_)
      if (is.na(val)) val <- if (is.na(def)) "" else def
      s <- sub(m, val, s, fixed = TRUE)
    }
    s
  }, "", USE.NAMES = FALSE)
}
```

`test_config.R`

```r
source("mcp_config.R")
home <- normalizePath("fixtures/home"); proj <- normalizePath("fixtures/project")
servers <- mcp_discover_servers(project = proj, home = home, sysname = "Darwin", codex_home = file.path(home, ".codex"),
                                gptr_user_dir = file.path(home, ".config", "gptr"))
tab <- do.call(rbind, lapply(servers, function(s) data.frame(
  name = s$name, transport = s$transport, from = paste0(s$source$harness, ":", s$source$scope),
  target = if (!is.null(s$command)) paste(s$command, paste(s$args, collapse = " ")) else s$url,
  enabled = s$enabled, also_in = paste(s$also_in, collapse = ","), needs_input = isTRUE(s$needs_input))))
print(tab, right = FALSE, row.names = FALSE)
cat("\nInterpolation examples:\n")
fake_env <- function(x, unset = NA_character_) c(GITHUB_TOKEN = "gh_xxx", LINEAR_KEY = "lin_yyy")[x] |> (\(v) if (is.na(v)) unset else unname(v))()
print(mcp_interpolate(c("Bearer ${GITHUB_TOKEN}", "Bearer ${env:LINEAR_KEY}", "${CLAUDE_PROJECT_DIR:-.}/data.db",
                        "{env:GITHUB_TOKEN}", "${workspaceFolder}/x", "literal {braces} and $HOME stay"), project = "/proj", getenv = fake_env))
```

`test_config.out`

```text
 name        transport from               
 sentry      http      gptr:project       
 filesystem  stdio     claude-code:project
 github      http      claude-code:user   
 local-db    stdio     claude-code:local  
 r-mcptools  stdio     claude-desktop:user
 context7    stdio     codex:user         
 figma       http      codex:user         
 r-session   stdio     codex:user         
 linear      http      cursor:user        
 perplexity  stdio     vscode:project     
 memory      stdio     vscode:project     
 docs        http      pi:user            
 pythonTools stdio     gemini:user        
 streamy     http      gemini:user        
 target                                                               enabled
 https://mcp.sentry.dev/mcp                                            TRUE  
 npx -y @modelcontextprotocol/server-filesystem .                      TRUE  
 https://api.githubcopilot.com/mcp/                                    TRUE  
 uvx mcp-server-sqlite --db-path ${CLAUDE_PROJECT_DIR:-.}/data.db      TRUE  
 Rscript -e mcptools::mcp_server()                                     TRUE  
 npx -y @upstash/context7-mcp@latest                                   TRUE  
 https://mcp.figma.com/mcp                                            FALSE  
 C:\\Program Files\\R\\R-4.4.3\\bin\\Rscript.exe -e gptr::mcp_serve()  TRUE  
 https://mcp.linear.app/mcp                                            TRUE  
 npx -y server-perplexity-ask                                          TRUE  
 npx -y @modelcontextprotocol/server-memory                            TRUE  
 https://example.com/mcp                                               TRUE  
 python -m my_mcp_server                                               TRUE  
 https://s.example.com/mcp                                             TRUE  
 also_in             needs_input
 claude-code:project FALSE      
 claude-desktop:user FALSE      
                     FALSE      
                     FALSE      
                     FALSE      
                     FALSE      
                     FALSE      
                     FALSE      
                     FALSE      
                      TRUE      
                     FALSE      
                     FALSE      
                     FALSE      
                     FALSE      

Interpolation examples:
[1] "Bearer gh_xxx"                   "Bearer lin_yyy"                 
[3] "./data.db"                       "gh_xxx"                         
[5] "/proj/x"                         "literal {braces} and $HOME stay"
```

`fixtures/home/.claude.json`

```json
{"numStartups": 3,
 "mcpServers": {"github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/", "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"}}},
 "projects": {"/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/16/proto/fixtures/project": {"mcpServers": {"local-db": {"type": "stdio", "command": "uvx", "args": ["mcp-server-sqlite", "--db-path", "${CLAUDE_PROJECT_DIR:-.}/data.db"]}}}}}
```

`fixtures/project/.mcp.json`

```json
{"mcpServers": {"filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]},
                "sentry": {"type": "http", "url": "https://mcp.sentry.dev/mcp"}}}
```

`fixtures/project/.vscode/mcp.json`

```json
{"inputs": [{"type": "promptString", "id": "perplexity-key", "description": "Perplexity API Key", "password": true}],
 "servers": {"perplexity": {"type": "stdio", "command": "npx", "args": ["-y", "server-perplexity-ask"], "env": {"PERPLEXITY_API_KEY": "${input:perplexity-key}"}},
             "memory": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-memory"]}}}
```

`fixtures/home/.gemini/settings.json`

```json
{"theme": "x", "mcpServers": {"pythonTools": {"command": "python", "args": ["-m", "my_mcp_server"], "timeout": 15000},
                              "streamy": {"httpUrl": "https://s.example.com/mcp", "excludeTools": ["delete_all"]}}}
```

`fixtures/project/.gptr/mcp.json`

```json
{"mcpServers": {"sentry": {"type": "http", "url": "https://mcp.sentry.dev/mcp", "exposure": "deferred"}}}
```

### 5.12 Pure-R TOML reader (for Codex config) vs RcppTOML

`toml_read()` in base R, run on a realistic Codex config and compared leaf by leaf with `RcppTOML::parseTOML(escape = FALSE)`; the 3 differences are RcppTOML integer overflows and NULL-vs-list() for an empty array.

`toml_read.R`

```r
# A small pure-R TOML (v1.0) reader, sufficient for agent config files such as
# Codex's ~/.codex/config.toml. Base R only. Returns nested named lists;
# arrays of scalars are simplified to atomic vectors, arrays of tables to lists.
# Offset date-times / local dates are returned as character strings.
# Limitations (by design): no validation of every TOML redefinition rule.

toml_read <- function(file = NULL, text = NULL) {
  if (is.null(text)) text <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- enc2utf8(paste(text, collapse = "\n"))
  text <- sub("^\ufeff", "", text)                         # BOM
  ch <- strsplit(gsub("\r\n", "\n", text, fixed = TRUE), "")[[1]]
  n <- length(ch); i <- 1L
  root <- list(); cur_path <- character(); cur_is_aot <- FALSE

  err <- function(msg) {
    line <- sum(ch[seq_len(min(i, n))] == "\n") + 1L
    stop(sprintf("TOML parse error (line %d): %s", line, msg), call. = FALSE)
  }
  peek <- function(k = 0L) if (i + k <= n) ch[i + k] else ""
  skip_ws <- function() while (i <= n && ch[i] %in% c(" ", "\t")) i <<- i + 1L
  skip_comment <- function() if (peek() == "#") while (i <= n && ch[i] != "\n") i <<- i + 1L
  skip_ws_nl_comments <- function() repeat {
    skip_ws(); skip_comment()
    if (i <= n && ch[i] == "\n") { i <<- i + 1L; next }
    break
  }
  expect_eol <- function() {
    skip_ws(); skip_comment()
    if (i <= n && ch[i] != "\n") err(paste0("unexpected '", ch[i], "' after value"))
  }

  # --- strings ---
  hex_char <- function(len) {
    h <- paste(ch[i:(i + len - 1L)], collapse = ""); i <<- i + len
    intToUtf8(strtoi(h, 16L))
  }
  read_escape <- function() {
    e <- peek(); i <<- i + 1L
    switch(e, b = "\b", t = "\t", n = "\n", f = "\f", r = "\r", `"` = "\"", `\\` = "\\",
           u = hex_char(4L), U = hex_char(8L), err(paste0("bad escape \\", e)))
  }
  read_basic <- function() {                       # after opening "
    out <- character()
    repeat {
      if (i > n) err("unterminated string")
      c <- ch[i]
      if (c == "\"") { i <<- i + 1L; break }
      if (c == "\n") err("newline in basic string")
      if (c == "\\") { i <<- i + 1L; out <- c(out, read_escape()) } else { out <- c(out, c); i <<- i + 1L }
    }
    paste(out, collapse = "")
  }
  read_ml_basic <- function() {                    # after opening """
    if (peek() == "\n") i <<- i + 1L
    out <- character()
    repeat {
      if (i > n) err("unterminated multi-line string")
      if (ch[i] == "\"" && peek(1L) == "\"" && peek(2L) == "\"") {
        i <<- i + 3L
        while (peek() == "\"") { out <- c(out, "\""); i <<- i + 1L }   # up to 2 extra quotes
        break
      }
      if (ch[i] == "\\") {
        # line-ending backslash: trim whitespace/newlines that follow
        j <- i + 1L; while (j <= n && ch[j] %in% c(" ", "\t")) j <- j + 1L
        if (j <= n && ch[j] == "\n") {
          i <<- j; while (i <= n && ch[i] %in% c(" ", "\t", "\n")) i <<- i + 1L; next
        }
        i <<- i + 1L; out <- c(out, read_escape()); next
      }
      out <- c(out, ch[i]); i <<- i + 1L
    }
    paste(out, collapse = "")
  }
  read_literal <- function() {                     # after opening '
    s <- i; while (i <= n && ch[i] != "'") { if (ch[i] == "\n") err("newline in literal string"); i <<- i + 1L }
    if (i > n) err("unterminated literal string")
    v <- paste(ch[seq.int(s, length.out = i - s)], collapse = ""); i <<- i + 1L; v
  }
  read_ml_literal <- function() {                  # after opening '''
    if (peek() == "\n") i <<- i + 1L
    s <- i
    while (i <= n && !(ch[i] == "'" && peek(1L) == "'" && peek(2L) == "'")) i <<- i + 1L
    if (i > n) err("unterminated multi-line literal string")
    e <- i; i <<- i + 3L
    extra <- 0L; while (peek() == "'" && extra < 2L) { extra <- extra + 1L; i <<- i + 1L }
    paste(c(ch[seq.int(s, length.out = e - s)], rep("'", extra)), collapse = "")
  }

  # --- keys ---
  read_key <- function() {
    parts <- character()
    repeat {
      skip_ws()
      c <- peek()
      if (c == "\"") { i <<- i + 1L; parts <- c(parts, read_basic()) }
      else if (c == "'") { i <<- i + 1L; parts <- c(parts, read_literal()) }
      else {
        s <- i
        while (i <= n && grepl("^[A-Za-z0-9_-]$", ch[i])) i <<- i + 1L
        if (i == s) err("expected a key")
        parts <- c(parts, paste(ch[s:(i - 1L)], collapse = ""))
      }
      skip_ws()
      if (peek() == ".") { i <<- i + 1L; next }
      break
    }
    parts
  }

  # --- values ---
  read_value <- function() {
    skip_ws(); c <- peek()
    if (c == "\"") {
      if (peek(1L) == "\"" && peek(2L) == "\"") { i <<- i + 3L; return(read_ml_basic()) }
      i <<- i + 1L; return(read_basic())
    }
    if (c == "'") {
      if (peek(1L) == "'" && peek(2L) == "'") { i <<- i + 3L; return(read_ml_literal()) }
      i <<- i + 1L; return(read_literal())
    }
    if (c == "[") { i <<- i + 1L; return(read_array()) }
    if (c == "{") { i <<- i + 1L; return(read_inline_table()) }
    s <- i
    while (i <= n && !(ch[i] %in% c(",", "]", "}", "\n", "#")) &&
           !(ch[i] %in% c(" ", "\t") && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", paste(ch[s:(i - 1L)], collapse = ""))))
      i <<- i + 1L
    tok <- trimws(paste(ch[seq.int(s, length.out = i - s)], collapse = ""))
    if (tok == "true") return(TRUE)
    if (tok == "false") return(FALSE)
    if (grepl("^[+-]?(inf|nan)$", tok)) return(if (grepl("nan", tok)) NaN else if (startsWith(tok, "-")) -Inf else Inf)
    radix <- function(s, base) {            # doubles: no 32-bit strtoi overflow
      d <- match(strsplit(tolower(gsub("_", "", s)), "")[[1]], c(0:9, letters[1:6])) - 1
      sum(d * base^rev(seq_along(d) - 1))
    }
    if (grepl("^0x[0-9A-Fa-f_]+$", tok)) return(radix(substring(tok, 3), 16))
    if (grepl("^0o[0-7_]+$", tok)) return(radix(substring(tok, 3), 8))
    if (grepl("^0b[01_]+$", tok)) return(radix(substring(tok, 3), 2))
    if (grepl("^[+-]?[0-9][0-9_]*$", tok)) {
      v <- as.numeric(gsub("_", "", tok))
      return(if (abs(v) <= .Machine$integer.max) as.integer(v) else v)
    }
    if (grepl("^[+-]?[0-9_]+(\\.[0-9_]+)?([eE][+-]?[0-9_]+)?$", tok)) return(as.numeric(gsub("_", "", tok)))
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{2}:[0-9]{2}", tok)) return(tok)   # dates kept as text
    err(paste0("invalid value '", tok, "'"))
  }
  simplify <- function(x) {
    if (length(x) && all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, TRUE))) {
      cls <- unique(vapply(x, function(e) class(e)[1], ""))
      if (length(cls) == 1L || all(cls %in% c("integer", "numeric"))) return(unlist(x))
    }
    x
  }
  read_array <- function() {
    out <- list()
    repeat {
      skip_ws_nl_comments()
      if (peek() == "]") { i <<- i + 1L; break }
      out[[length(out) + 1L]] <- read_value()
      skip_ws_nl_comments()
      if (peek() == ",") { i <<- i + 1L; next }
      if (peek() == "]") { i <<- i + 1L; break }
      err("expected , or ] in array")
    }
    simplify(out)
  }
  read_inline_table <- function() {
    tbl <- structure(list(), names = character())
    skip_ws()
    if (peek() == "}") { i <<- i + 1L; return(tbl) }
    repeat {
      key <- read_key(); skip_ws()
      if (peek() != "=") err("expected = in inline table"); i <<- i + 1L
      tbl <- set_in(tbl, key, read_value())
      skip_ws()
      if (peek() == ",") { i <<- i + 1L; next }
      if (peek() == "}") { i <<- i + 1L; break }
      err("expected , or } in inline table")
    }
    tbl
  }

  # --- nested assignment helpers ---
  set_in <- function(tbl, path, value) {
    if (length(path) == 1L) { tbl[[path]] <- value; return(tbl) }
    sub <- tbl[[path[1]]]
    if (is.null(sub)) sub <- structure(list(), names = character())
    tbl[[path[1]]] <- set_in(sub, path[-1], value)
    tbl
  }
  get_in <- function(tbl, path) { for (p in path) { if (is.null(tbl)) return(NULL); tbl <- tbl[[p]] }; tbl }
  # Resolve the current table path, descending into the LAST element of arrays of tables.
  assign_current <- function(key, value) {
    root <<- assign_rec(root, cur_path, key, value)
  }
  assign_rec <- function(tbl, path, key, value) {
    if (!length(path)) return(set_in(tbl, key, value))
    p <- path[1]; sub <- tbl[[p]]
    if (is.null(sub)) sub <- structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {            # array of tables
      k <- length(sub); sub[[k]] <- assign_rec(sub[[k]], path[-1], key, value)
    } else sub <- assign_rec(sub, path[-1], key, value)
    tbl[[p]] <- sub; tbl
  }
  ensure_table <- function(tbl, path, aot_append = FALSE) {
    p <- path[1]; sub <- tbl[[p]]
    if (length(path) == 1L) {
      if (aot_append) {
        if (is.null(sub)) sub <- list()
        sub[[length(sub) + 1L]] <- structure(list(), names = character())
      } else if (is.null(sub)) sub <- structure(list(), names = character())
      tbl[[p]] <- sub; return(tbl)
    }
    if (is.null(sub)) sub <- structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {
      k <- length(sub); sub[[k]] <- ensure_table(sub[[k]], path[-1], aot_append)
    } else sub <- ensure_table(sub, path[-1], aot_append)
    tbl[[p]] <- sub; tbl
  }

  # --- main loop ---
  repeat {
    skip_ws_nl_comments()
    if (i > n) break
    if (peek() == "[") {
      aot <- peek(1L) == "["
      i <- i + if (aot) 2L else 1L
      path <- read_key(); skip_ws()
      if (aot) { if (peek() != "]" || peek(1L) != "]") err("expected ]]"); i <- i + 2L }
      else { if (peek() != "]") err("expected ]"); i <- i + 1L }
      root <- ensure_table(root, path, aot_append = aot)
      cur_path <- path
      expect_eol(); next
    }
    key <- read_key(); skip_ws()
    if (peek() != "=") err("expected = after key"); i <- i + 1L
    val <- read_value()
    assign_current(key, val)
    expect_eol()
  }
  root
}
```

`fixtures/codex_config.toml`

```toml
# Synthetic Codex config (NOT the user's real file), modelled on the Codex docs
model = "gpt-5.5"
approval_policy = "on-request"
model_reasoning_effort = 'high'

[features]
web_search = true

[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]   # trailing comment
startup_timeout_sec = 20
tool_timeout_sec = 60.5

[mcp_servers.context7.env]
MY_ENV_VAR = "MY_ENV_VALUE"
"QUOTED.KEY" = "v"

[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
bearer_token_env_var = "FIGMA_OAUTH_TOKEN"
http_headers = { "X-Figma-Region" = "us-east-1", retries = 3 }
enabled_tools = [
  "get_file",
  "get_node",   # comment inside array
]
enabled = false

[mcp_servers."r-session"]
command = 'C:\Program Files\R\R-4.4.3\bin\Rscript.exe'
args = ["-e", "gptr::mcp_serve()"]
env_vars = ["HOME", "R_LIBS_USER"]
cwd = "C:\\Users\\me\\proj"

[profiles.fast]
model = "gpt-5.5-mini"
mcp_servers.inline.command = "uvx"

[[skills.config]]
path = "/home/me/.agents/skills/pdf/SKILL.md"
enabled = false

[[skills.config]]
path = "/home/me/.agents/skills/r/SKILL.md"
enabled = true

[misc]
hex = 0xDEAD_BEEF
big = 9_007_199_254_740_991
flt = -1.5e-3
when = 1979-05-27T07:32:00Z
ml = """
Roses are red\
   violets are blue
tab:\t "q" \u00e9"""
lit = '''no \escapes '' here'''
nested = [[1, 2], ["a", "b"], []]
aot_inline = [{ name = "a" }, { name = "b", x = 1 }]
empty_tbl = {}
```

`test_toml.R`

```r
source("toml_read.R")
f <- "fixtures/codex_config.toml"
mine <- toml_read(f)
ref <- RcppTOML::parseTOML(f, escape = FALSE)  # default escape=TRUE re-escapes strings
cat("mcp_servers:", names(mine$mcp_servers), "\n")
str(mine$mcp_servers, max.level = 3, give.attr = FALSE)
cat("\nskills.config:\n"); str(mine$skills$config)
cat("\nprofiles.fast:\n"); str(mine$profiles$fast)
cat("\nmisc:\n"); str(mine$misc)
# Compare with RcppTOML leaf by leaf (as character; RcppTOML returns POSIXct for datetimes)
flat <- function(x, p = "") {
  if (is.list(x) && length(x) == 0) return(setNames("<empty>", p))
  if (is.list(x)) { nm <- names(x); if (is.null(nm)) nm <- paste0("[", seq_along(x), "]")
    return(unlist(Map(function(v, k) flat(v, paste0(p, "/", k)), x, nm), use.names = TRUE)) }
  if (inherits(x, "POSIXt")) x <- format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  setNames(paste(format(x, digits = 15), collapse = ","), p)
}
a <- flat(mine); b <- flat(ref)
common <- intersect(names(a), names(b))
cat("\nleaves: mine", length(a), " RcppTOML", length(b), " common", length(common), "\n")
diffs <- common[a[common] != b[common]]
cat("value differences:", length(diffs), "\n"); if (length(diffs)) print(cbind(mine = a[diffs], ref = b[diffs]))
cat("only in mine:", setdiff(names(a), names(b)), "\n")
cat("only in RcppTOML:", setdiff(names(b), names(a)), "\n")
cat("\nerror handling: "); print(tryCatch(toml_read(text = "a = [1, 2\nb = 3"), error = conditionMessage))
```

`test_toml.out`

```text
mcp_servers: context7 figma r-session 
List of 3
 $ context7 :List of 5
  ..$ command            : chr "npx"
  ..$ args               : chr [1:2] "-y" "@upstash/context7-mcp@latest"
  ..$ startup_timeout_sec: int 20
  ..$ tool_timeout_sec   : num 60.5
  ..$ env                :List of 2
  .. ..$ MY_ENV_VAR: chr "MY_ENV_VALUE"
  .. ..$ QUOTED.KEY: chr "v"
 $ figma    :List of 5
  ..$ url                 : chr "https://mcp.figma.com/mcp"
  ..$ bearer_token_env_var: chr "FIGMA_OAUTH_TOKEN"
  ..$ http_headers        :List of 2
  .. ..$ X-Figma-Region: chr "us-east-1"
  .. ..$ retries       : int 3
  ..$ enabled_tools       : chr [1:2] "get_file" "get_node"
  ..$ enabled             : logi FALSE
 $ r-session:List of 4
  ..$ command : chr "C:\\Program Files\\R\\R-4.4.3\\bin\\Rscript.exe"
  ..$ args    : chr [1:2] "-e" "gptr::mcp_serve()"
  ..$ env_vars: chr [1:2] "HOME" "R_LIBS_USER"
  ..$ cwd     : chr "C:\\Users\\me\\proj"

skills.config:
List of 2
 $ :List of 2
  ..$ path   : chr "/home/me/.agents/skills/pdf/SKILL.md"
  ..$ enabled: logi FALSE
 $ :List of 2
  ..$ path   : chr "/home/me/.agents/skills/r/SKILL.md"
  ..$ enabled: logi TRUE

profiles.fast:
List of 2
 $ model      : chr "gpt-5.5-mini"
 $ mcp_servers:List of 1
  ..$ inline:List of 1
  .. ..$ command: chr "uvx"

misc:
List of 9
 $ hex       : num 3.74e+09
 $ big       : num 9.01e+15
 $ flt       : num -0.0015
 $ when      : chr "1979-05-27T07:32:00Z"
 $ ml        : chr "Roses are redviolets are blue\ntab:\t \"q\" <U+00E9>"
 $ lit       : chr "no \\escapes '' here"
 $ nested    :List of 3
  ..$ : int [1:2] 1 2
  ..$ : chr [1:2] "a" "b"
  ..$ : list()
 $ aot_inline:List of 2
  ..$ :List of 1
  .. ..$ name: chr "a"
  ..$ :List of 2
  .. ..$ name: chr "b"
  .. ..$ x   : int 1
 $ empty_tbl : Named list()

leaves: mine 39  RcppTOML 39  common 39 
value differences: 3 
                             mine               ref         
misc.hex./misc/hex           "3735928559"       "-559038737"
misc.big./misc/big           "9007199254740991" "-1"        
misc.nested./misc/nested/[3] "<empty>"          "NULL"      
only in mine:  
only in RcppTOML:  

error handling: [1] "TOML parse error (line 2): expected , or ] in array"
```

### 5.13 Agent Skills: discovery, lenient parsing, catalog, activation

`skills.R` + `skills_scan_bfs.R` (bounded BFS that replaces the recursive `list.files()` version, which did not finish over the 1.5 GB plugin cache). `test_skills.R` first runs synthetic fixtures (a colon-in-value description needing the lenient fallback, a skill without description, a skill with references and `$ARGUMENTS`), then the real skills installed on this machine.

`skills.R`

```r
# Agent Skills (agentskills.io) discovery, lenient parsing, catalog and
# activation for gptr - prototype. Dependencies: base R + yaml.
`%||%` <- function(a, b) if (is.null(a)) b else a

skill_dirs_default <- function(project = getwd(), home = path.expand("~")) {
  up <- function(d) {                 # project and its ancestors up to the git root
    out <- character(); d <- normalizePath(d, mustWork = FALSE)
    repeat { out <- c(out, d); if (dir.exists(file.path(d, ".git")) || dirname(d) == d) break; d <- dirname(d) }
    out
  }
  anc <- up(project)
  data.frame(stringsAsFactors = FALSE,
    scope = c(rep("project", 3 * length(anc)), rep("user", 5)),
    path = c(file.path(anc, ".gptr", "skills"), file.path(anc, ".agents", "skills"), file.path(anc, ".claude", "skills"),
             file.path(home, ".config", "gptr", "skills"), file.path(home, ".agents", "skills"),
             file.path(home, ".claude", "skills"), file.path(home, ".codex", "skills"),
             file.path(home, ".pi", "agent", "skills")))
}

# Split "---\nyaml\n---\nbody"; parse YAML leniently (agentskills.io guidance:
# unquoted values containing ": " are common in skills written for other clients).
skill_parse <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- sub("\r$", "", lines)
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) return(list(error = "no frontmatter"))
  end <- which(grepl("^---\\s*$", lines))[2]
  if (is.na(end)) return(list(error = "unterminated frontmatter"))
  fm_lines <- lines[seq_len(end - 1L)[-1]]
  body <- paste(lines[-seq_len(end)], collapse = "\n")
  fm <- tryCatch(yaml::yaml.load(paste(fm_lines, collapse = "\n")), error = function(e) e)
  lenient <- FALSE
  if (inherits(fm, "error")) {
    fixed <- vapply(fm_lines, function(l) {
      m <- regmatches(l, regexec("^([A-Za-z0-9_-]+):[ \t]+(.*)$", l))[[1]]
      if (length(m) == 3L && !grepl("^['\"|>\\[{]", m[3]) && grepl(":[ \t]| #", m[3])) {
        v <- gsub("\\\\", "\\\\\\\\", m[3]); v <- gsub("\"", "\\\\\"", v)
        return(sprintf("%s: \"%s\"", m[2], v))
      }
      l
    }, "", USE.NAMES = FALSE)
    fm <- tryCatch(yaml::yaml.load(paste(fixed, collapse = "\n")), error = function(e) e)
    lenient <- TRUE
    if (inherits(fm, "error")) return(list(error = paste("YAML:", conditionMessage(fm))))
  }
  if (!is.list(fm)) return(list(error = "frontmatter is not a mapping"))
  dir <- dirname(path)
  name <- fm$name %||% basename(dir)
  warn <- character()
  if (!grepl("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name) || grepl("--", name, fixed = TRUE) || nchar(name) > 64)
    warn <- c(warn, "name violates spec")
  if (!identical(name, basename(dir))) warn <- c(warn, "name != directory")
  desc <- fm$description
  if (is.null(desc) || !nzchar(trimws(paste(desc, collapse = " ")))) return(list(error = "missing description"))
  desc <- paste(desc, collapse = " ")
  if (nchar(desc) > 1024) warn <- c(warn, "description > 1024 chars")
  list(name = name, description = desc, location = normalizePath(path), dir = normalizePath(dir),
       frontmatter = fm, body = body, lenient = lenient, warnings = warn,
       model_invocable = !isTRUE(fm[["disable-model-invocation"]]),
       user_invocable = !isFALSE(fm[["user-invocable"]]))
}

skills_scan <- function(dirs, max_depth = 4L) {
  found <- list(); diags <- list()
  for (k in seq_len(nrow(dirs))) {
    d <- dirs$path[k]; if (!dir.exists(d)) next
    files <- list.files(d, pattern = "^SKILL\\.md$", recursive = TRUE, full.names = TRUE)
    rel_depth <- lengths(regmatches(files, gregexpr("/", files))) - lengths(regmatches(d, gregexpr("/", d)))
    files <- files[rel_depth <= max_depth & !grepl("/(\\.git|node_modules)/", files)]
    for (f in files) {
      s <- skill_parse(f)
      if (!is.null(s$error)) { diags[[length(diags) + 1L]] <- list(path = f, error = s$error); next }
      s$scope <- dirs$scope[k]
      if (s$name %in% names(found)) {                     # first found wins (project dirs listed first)
        diags[[length(diags) + 1L]] <- list(path = f, error = paste("shadowed by", found[[s$name]]$location)); next
      }
      found[[s$name]] <- s
    }
  }
  structure(found, diagnostics = diags)
}

xml_escape <- function(x) { x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
                            gsub(">", "&gt;", x, fixed = TRUE) }

# Tier 1: the catalog placed in the system prompt (Pi / agentskills.io format).
skills_catalog <- function(skills, max_desc = 1024L) {
  vis <- Filter(function(s) s$model_invocable, skills)
  if (!length(vis)) return("")
  items <- vapply(vis, function(s) sprintf(
    "  <skill>\n    <name>%s</name>\n    <description>%s</description>\n    <location>%s</location>\n  </skill>",
    xml_escape(s$name), xml_escape(substr(s$description, 1, max_desc)), xml_escape(s$location)), "")
  paste0("The following skills provide specialized instructions for specific tasks.\n",
         "When a task matches a skill's description, load it with the skill tool (or read the SKILL.md at <location>).\n",
         "Resolve relative paths in a skill against its directory.\n\n<available_skills>\n",
         paste(items, collapse = "\n"), "\n</available_skills>")
}

# Tier 2: activation result (body only, wrapped, resources listed not read).
skill_activate <- function(skill, arguments = "") {
  body <- skill$body
  body <- gsub("${CLAUDE_SKILL_DIR}", skill$dir, body, fixed = TRUE)
  body <- gsub("${GPTR_SKILL_DIR}", skill$dir, body, fixed = TRUE)
  if (grepl("$ARGUMENTS", body, fixed = TRUE)) body <- gsub("$ARGUMENTS", arguments, body, fixed = TRUE)
  else if (nzchar(arguments)) body <- paste0(body, "\n\nARGUMENTS: ", arguments)
  res <- setdiff(list.files(skill$dir, recursive = TRUE), "SKILL.md")
  res <- head(res, 50L)
  sprintf("<skill_content name=\"%s\">\n%s\n\nSkill directory: %s\nRelative paths in this skill are relative to the skill directory.\n<skill_resources>\n%s\n</skill_resources>\n</skill_content>",
          skill$name, trimws(body), skill$dir, paste0("  <file>", res, "</file>", collapse = "\n"))
}

source("skills_scan_bfs.R")   # overrides skills_scan() with the bounded BFS version
```

`skills_scan_bfs.R`

```r
# Bounded breadth-first skill discovery (replaces list.files(recursive = TRUE),
# which walked 70k files / 1.5 GB of plugin caches incl. node_modules).
skills_find_files <- function(root, max_depth = 4L, max_dirs = 2000L,
                              skip = c(".git", "node_modules", ".venv", "__pycache__", "renv", ".Rproj.user")) {
  if (!dir.exists(root)) return(character())
  queue <- list(list(d = root, depth = 0L)); out <- character(); visited <- 0L
  while (length(queue) && visited < max_dirs) {
    cur <- queue[[1]]; queue <- queue[-1]; visited <- visited + 1L
    sk <- file.path(cur$d, "SKILL.md")
    if (file.exists(sk) && cur$depth > 0L) { out <- c(out, sk); next }   # a skill dir: don't descend
    if (cur$depth >= max_depth) next
    subs <- list.dirs(cur$d, full.names = TRUE, recursive = FALSE)
    subs <- subs[!basename(subs) %in% skip]
    queue <- c(queue, lapply(subs, function(s) list(d = s, depth = cur$depth + 1L)))
  }
  out
}
skills_scan <- function(dirs, max_depth = 4L) {
  found <- list(); diags <- list()
  for (k in seq_len(nrow(dirs))) {
    for (f in skills_find_files(dirs$path[k], max_depth)) {
      s <- skill_parse(f)
      if (!is.null(s$error)) { diags[[length(diags) + 1L]] <- list(path = f, error = s$error); next }
      s$scope <- dirs$scope[k]
      if (s$name %in% names(found)) { diags[[length(diags) + 1L]] <- list(path = f, error = paste("shadowed by", found[[s$name]]$location)); next }
      found[[s$name]] <- s
    }
  }
  structure(found, diagnostics = diags)
}
# Claude Code installed plugins: ~/.claude/plugins/installed_plugins.json (v2)
claude_installed_plugins <- function(home = path.expand("~")) {
  f <- file.path(home, ".claude", "plugins", "installed_plugins.json")
  if (!file.exists(f)) return(data.frame())
  x <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  do.call(rbind, lapply(names(x$plugins), function(id) do.call(rbind, lapply(x$plugins[[id]], function(e)
    data.frame(id = id, scope = e$scope %||% NA, installPath = e$installPath %||% NA, version = e$version %||% NA)))))
}
```

`fixtures/skills/broken-colon/SKILL.md`

```markdown
---
name: broken-colon
description: Use this skill when: the user asks about PDFs # not a comment
---
Body of broken-colon.
```

`fixtures/skills/r-plot/SKILL.md`

```markdown
---
name: r-plot
description: Make publication-quality ggplot2 figures from objects in the live R session. Use when the user asks for a plot.
allowed-tools: r_eval read
metadata:
  author: gptr
---
# R plots
Read references/theme.md, then call ${CLAUDE_SKILL_DIR}/references/theme.md helpers. Task: $ARGUMENTS
```

`test_skills.R`

```r
source("skills.R")
# 1) synthetic fixtures
fx <- skills_scan(data.frame(scope = "project", path = normalizePath("fixtures/skills")))
cat("fixture skills:", names(fx), "\n")
cat("broken-colon lenient:", fx[["broken-colon"]]$lenient, "| description:", fx[["broken-colon"]]$description, "\n")
for (d in attr(fx, "diagnostics")) cat("diag:", basename(dirname(d$path)), "-", d$error, "\n")
cat("\n", skills_catalog(fx["r-plot"]), "\n\n")
cat(skill_activate(fx[["r-plot"]], arguments = "scatter of mpg vs wt"), "\n")

# 2) the real skills installed on this machine (Claude Code / Codex / .agents / plugin caches)
home <- path.expand("~")
pl <- claude_installed_plugins(home)
cat("Claude Code installed plugins:", nrow(pl), "\n")
plugin_skill_dirs <- unique(file.path(pl$installPath, "skills"))
dirs <- rbind(skill_dirs_default(project = getwd(), home = home),
              data.frame(scope = "plugin", path = plugin_skill_dirs))
t0 <- Sys.time()
sk <- skills_scan(dirs)
el <- as.numeric(Sys.time() - t0, units = "secs")
diags <- attr(sk, "diagnostics")
cat(sprintf("\nreal corpus: %d dirs scanned, %d skills loaded, %d diagnostics, %.2fs\n", nrow(dirs), length(sk), length(diags), el))
cat("loaded per scope:"); print(table(vapply(sk, `[[`, "", "scope")))
cat("lenient YAML fallback needed:", sum(vapply(sk, `[[`, TRUE, "lenient")), "\n")
w <- unlist(lapply(sk, `[[`, "warnings")); cat("warnings:"); print(table(w))
cat("diagnostic kinds:"); print(table(sub(" by .*", "", vapply(diags, `[[`, "", "error"))))
fields <- unlist(lapply(sk, function(s) names(s$frontmatter)))
cat("frontmatter fields in the wild:\n"); print(sort(table(fields), decreasing = TRUE))
bl <- vapply(sk, function(s) length(strsplit(s$body, "\n")[[1]]), 1L)
cat("SKILL.md body lines: median", median(bl), " max", max(bl), " >500 lines:", sum(bl > 500), "\n")
cat("model-invocable:", sum(vapply(sk, `[[`, TRUE, "model_invocable")), "\n")
cat_txt <- skills_catalog(sk)
cat(sprintf("catalog for all %d skills: %d chars (~%d tokens)\n", length(sk), nchar(cat_txt), round(nchar(cat_txt) / 4)))
```

`test_skills.out`

```text
fixture skills: broken-colon r-plot 
broken-colon lenient: TRUE | description: Use this skill when: the user asks about PDFs # not a comment 
diag: no-desc - missing description 

 The following skills provide specialized instructions for specific tasks.
When a task matches a skill's description, load it with the skill tool (or read the SKILL.md at <location>).
Resolve relative paths in a skill against its directory.

<available_skills>
  <skill>
    <name>r-plot</name>
    <description>Make publication-quality ggplot2 figures from objects in the live R session. Use when the user asks for a plot.</description>
    <location>/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/16/proto/fixtures/skills/r-plot/SKILL.md</location>
  </skill>
</available_skills> 

<skill_content name="r-plot">
# R plots
Read references/theme.md, then call /private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/16/proto/fixtures/skills/r-plot/references/theme.md helpers. Task: scatter of mpg vs wt

Skill directory: /private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/16/proto/fixtures/skills/r-plot
Relative paths in this skill are relative to the skill directory.
<skill_resources>
  <file>references/theme.md</file>
</skill_resources>
</skill_content> 
Claude Code installed plugins: 14 

real corpus: 48 dirs scanned, 161 skills loaded, 57 diagnostics, 0.19s
loaded per scope:
plugin   user 
   122     39 
lenient YAML fallback needed: 0 
warnings:< table of extent 0 >
diagnostic kinds:
shadowed 
      57 
frontmatter fields in the wild:
fields
   description           name        version       metadata user-invocable 
           161            161            101             95              3 
          tags        license 
             2              1 
SKILL.md body lines: median 44  max 1206  >500 lines: 10 
model-invocable: 161 
catalog for all 161 skills: 64537 chars (~16134 tokens)
```

### 5.14 Context cost: MCP tools as R functions, signatures, search

`mcp_tools_as_functions()` builds one R closure per MCP tool (formals from `inputSchema`), verified against the R server; the signature catalog and names are compared with the full `tools/list` of `claude mcp serve`. `mcp_tool_search()` is a deliberately naive idf ranking (ties on generic queries show why gptr should port report 06's verified BM25).

`mcp_rfuns.R`

```r
# Context-cost strategy prototype: expose MCP tools as ordinary R functions that
# the model calls from the R-eval tool ("code mode"), instead of declaring every
# MCP tool (with its JSON Schema) to the model.
`%||%` <- function(a, b) if (is.null(a)) b else a

# One R closure per MCP tool. Formals come from inputSchema$properties;
# required properties have no default, optional ones default to NULL.
mcp_tools_as_functions <- function(tools, caller) {
  env <- new.env(parent = emptyenv())
  for (t in tools) local({
    tool <- t
    props <- names(tool$inputSchema$properties %||% list())
    req <- unlist(tool$inputSchema$required %||% list())
    ok <- make.names(props) == props            # exotic property names go through `...`
    fmls <- rep(list(quote(expr = )), sum(ok)); names(fmls) <- props[ok]
    opt <- !(props[ok] %in% req); fmls[opt] <- rep(list(NULL), sum(opt))
    fmls <- c(fmls, alist(... = ))
    f <- function() {
      mc <- as.list(match.call(expand.dots = TRUE))[-1]       # only supplied args
      args <- lapply(mc, eval, envir = parent.frame())
      args <- Filter(Negate(is.null), args)
      caller(tool$name, args)
    }
    formals(f) <- fmls
    attr(f, "mcp_tool") <- tool$name
    assign(tool$name, f, envir = env)
  })
  env
}

# Compact signature line per tool for the prompt (name(args) + first sentence).
mcp_tool_signature <- function(tool, max_desc = 120L) {
  props <- tool$inputSchema$properties %||% list()
  req <- unlist(tool$inputSchema$required %||% list())
  arg <- vapply(names(props), function(p) {
    ty <- props[[p]]$type %||% "any"; if (is.list(ty)) ty <- paste(unlist(ty), collapse = "|")
    paste0(p, if (p %in% req) "" else "?", ": ", ty)
  }, "")
  d <- gsub("\\s+", " ", tool$description %||% "")
  d <- sub("^(.*?[.!?])\\s.*$", "\\1", d)          # first sentence
  if (nchar(d) > max_desc) d <- paste0(substr(d, 1, max_desc - 3), "...")
  sprintf("%s(%s)  # %s", tool$name, paste(arg, collapse = ", "), d)
}

# Tiny lexical search (BM25-lite) over name + description for tool discovery.
mcp_tool_search <- function(tools, query, limit = 5L) {
  tok <- function(x) unique(tolower(unlist(strsplit(x, "[^A-Za-z0-9]+"))))
  docs <- lapply(tools, function(t) tok(paste(gsub("_", " ", t$name), t$name, t$description %||% "")))
  q <- tok(query); N <- length(docs)
  df <- vapply(q, function(w) sum(vapply(docs, function(d) w %in% d, TRUE)), 1)
  idf <- log(1 + (N - df + 0.5) / (df + 0.5))
  score <- vapply(docs, function(d) sum(idf[q %in% d]), 1)
  o <- order(-score)[seq_len(min(limit, N))]
  data.frame(tool = vapply(tools[o], `[[`, "", "name"), score = round(score[o], 3))
}
```

`test_rfuns.R`

```r
source("mcp_client_stdio.R"); source("mcp_rfuns.R")
# (a) real R server: call the tool as an R function
rscript <- file.path(R.home("bin"), "Rscript")
conn <- mcp_stdio_connect(rscript, c("--vanilla", "mcp_server_stdio.R"), name = "rproto")
fns <- mcp_tools_as_functions(mcp_list_tools(conn), function(name, args) mcp_call_tool(conn, name, args))
print(args(fns$describe_numbers))
r <- fns$describe_numbers(x = c(2, 4, 9), digits = 1)   # R vector -> JSON array (auto_unbox keeps length>1 arrays)
cat("R-function call result:", format(r), " structured n =", r$structured$n, "\n")
r1 <- fns$describe_numbers(x = I(5))                     # length-1 array needs I() (jsonlite auto_unbox pitfall)
cat("length-1 vector via I():", format(r1), "\n")
mcp_close(conn)

# (b) context cost on a real server tool list (Claude Code's `claude mcp serve`: 27 tools)
conn <- mcp_stdio_connect("claude", c("mcp", "serve"), name = "claude-code")
tools <- mcp_list_tools(conn); mcp_close(conn)
full <- jsonlite::toJSON(tools, auto_unbox = TRUE)
sigs <- vapply(tools, mcp_tool_signature, "")
names_only <- paste(vapply(tools, `[[`, "", "name"), collapse = ", ")
cat(sprintf("\nfull tools/list JSON: %d chars (~%d tok)\n", nchar(full), round(nchar(full) / 4)))
cat(sprintf("R signature catalog:  %d chars (~%d tok)\n", sum(nchar(sigs)) + length(sigs), round((sum(nchar(sigs)) + length(sigs)) / 4)))
cat(sprintf("names only:           %d chars (~%d tok)\n", nchar(names_only), round(nchar(names_only) / 4)))
cat("\nexample signatures:\n"); cat(head(sigs, 6), sep = "\n")
cat("\nsearch 'edit a file':\n"); print(mcp_tool_search(tools, "edit a file"))
cat("search 'schedule recurring job':\n"); print(mcp_tool_search(tools, "schedule recurring job"))
```

`test_rfuns.out`

```text
function (x, digits = NULL, delay_ms = NULL, ...) 
NULL
R-function call result: {"n":3,"mean":5,"sd":3.6,"min":2,"max":9}  structured n = 3 
length-1 vector via I(): {"n":1,"mean":5,"min":5,"max":5} 

full tools/list JSON: 143525 chars (~35881 tok)
R signature catalog:  5899 chars (~1475 tok)
names only:           300 chars (~75 tok)

example signatures:
Agent(description: string, prompt: string, subagent_type?: string, model?: string, run_in_background?: boolean, name?: string, team_name?: string, mode?: string, isolation?: string)  # Launch a new agent to handle complex, multi-step tasks. Each agent type has specific capabilities and tools available...
TaskOutput(task_id: string, block: boolean, timeout: number)  # DEPRECATED: Background tasks return their output file path in the tool result, and you receive a <task-notification> ...
Bash(command: string, timeout?: number, description?: string, run_in_background?: boolean, dangerouslyDisableSandbox?: boolean)  # Executes a given bash command and returns its output. The working directory persists between commands, but shell stat...
Read(file_path: string, offset?: integer, limit?: integer, pages?: string)  # Reads a file from the local filesystem. You can access any file directly by using this tool. Assume this tool is able...
Edit(file_path: string, old_string: string, new_string: string, replace_all?: boolean)  # Performs exact string replacements in files. Usage: - You must use your `Read` tool at least once in the conversation...
Write(file_path: string, content: string)  # Writes a file to the local filesystem. Usage: - This tool will overwrite the existing file if there is one at the pro...

search 'edit a file':
   tool score
1 Agent 1.977
2  Bash 1.977
3  Read 1.977
4  Edit 1.977
5 Write 1.977
search 'schedule recurring job':
            tool score
1     CronCreate 6.834
2        Monitor 3.908
3     CronDelete 2.079
4 ScheduleWakeup 1.828
5  RemoteTrigger 1.828
```

### 5.15 OAuth building blocks (offline) and read-only discovery against public servers

`test_oauth_pieces.R` runs httr2's exported PKCE/URL/parse helpers and the `iss` rule gptr must add; `test_oauth_discovery.R` performs an unauthenticated modern probe (-> 401), protected-resource-metadata and AS-metadata discovery against four public MCP servers (no credentials, no registration).

`test_oauth_pieces.R`

```r
library(httr2)
print(args(oauth_flow_auth_code_url)); print(args(oauth_flow_auth_code_listen)); print(args(oauth_flow_auth_code_parse))
pk <- oauth_flow_auth_code_pkce(); str(pk)
client <- oauth_client(id = "https://gptr.example.org/oauth/client.json", token_url = "https://mcp.linear.app/token")
state <- "st-123"
url <- oauth_flow_auth_code_url(client, auth_url = "https://mcp.linear.app/authorize",
  redirect_uri = "http://127.0.0.1:1410/callback", scope = "read write", state = state,
  auth_params = list(code_challenge = pk$challenge, code_challenge_method = pk$method,
                     resource = "https://mcp.linear.app/mcp"))
cat(url, "\n")
# iss check the MCP 2026-07-28 spec requires before redeeming the code (httr2 does not do this):
q <- list(code = "abc", state = state, iss = "https://evil.example")
check_iss <- function(q, expected_iss, iss_supported) {
  if (!is.null(q$iss)) return(identical(q$iss, expected_iss))
  !isTRUE(iss_supported)
}
cat("iss mismatch accepted? ", check_iss(q, "https://mcp.linear.app", TRUE), "\n")
cat("iss absent + advertised -> accepted? ", check_iss(list(code = "abc", state = state), "https://mcp.linear.app", TRUE), "\n")
cat("parse (state ok):", oauth_flow_auth_code_parse(list(code = "abc", state = state), state), "\n")
```

`test_oauth_pieces.out`

```text
function (client, auth_url, redirect_uri = NULL, scope = NULL, 
    state = NULL, auth_params = list()) 
NULL
function (redirect_uri = "http://localhost:1410") 
NULL
function (query, state) 
NULL
List of 3
 $ verifier : chr "Ty1fjZCBwmD2OJTJXwL-2whT48tkjfOzChD0SfE_1Q0"
 $ method   : chr "S256"
 $ challenge: chr "XRaRn0znq_BlfbjAu3vE6xlW2d6osHTK9a67hi7FXVg"
https://mcp.linear.app/authorize?response_type=code&client_id=https%3A%2F%2Fgptr.example.org%2Foauth%2Fclient.json&redirect_uri=http%3A%2F%2F127.0.0.1%3A1410%2Fcallback&scope=read%20write&state=st-123&code_challenge=XRaRn0znq_BlfbjAu3vE6xlW2d6osHTK9a67hi7FXVg&code_challenge_method=S256&resource=https%3A%2F%2Fmcp.linear.app%2Fmcp 
iss mismatch accepted?  FALSE 
iss absent + advertised -> accepted?  FALSE 
parse (state ok): abc 
```

`test_oauth_discovery.R`

```r
# Read-only OAuth discovery against public remote MCP servers (no credentials,
# no client registration): unauthenticated modern probe -> 401 challenge ->
# protected resource metadata (RFC 9728) -> AS metadata (RFC 8414 / OIDC).
source("mcp_http.R")
parse_www_auth <- function(h) {
  if (is.null(h)) return(list())
  m <- gregexpr('([A-Za-z_]+)="([^"]*)"', h)[[1]]
  kv <- regmatches(h, list(m))[[1]]
  setNames(as.list(sub('^[^=]+="(.*)"$', "\\1", kv)), sub("=.*$", "", kv))
}
get_json <- function(url) {
  r <- tryCatch(httr2::request(url) |> httr2::req_headers(Accept = "application/json", `MCP-Protocol-Version` = "2025-11-25") |>
                  httr2::req_timeout(15) |> httr2::req_error(is_error = function(r) FALSE) |> httr2::req_perform(),
                error = function(e) NULL)
  if (is.null(r) || httr2::resp_status(r) != 200) return(NULL)
  tryCatch(httr2::resp_body_json(r), error = function(e) NULL)
}
as_meta_urls <- function(issuer) {
  u <- httr2::url_parse(issuer); path <- sub("/$", "", u$path %||% "")
  base <- sprintf("%s://%s%s", u$scheme, u$hostname, if (!is.null(u$port)) paste0(":", u$port) else "")
  if (nzchar(path)) c(paste0(base, "/.well-known/oauth-authorization-server", path),
                      paste0(base, "/.well-known/openid-configuration", path),
                      paste0(base, path, "/.well-known/openid-configuration"))
  else c(paste0(base, "/.well-known/oauth-authorization-server"), paste0(base, "/.well-known/openid-configuration"))
}
probe <- function(url) {
  cat("\n==", url, "\n")
  body <- to_json(list(jsonrpc = "2.0", id = 1, method = "server/discover",
                       params = list(`_meta` = setNames(list("2026-07-28", empty_obj(), list(name = "gptr-probe", version = "0")),
                                                         c(K_VER, K_CAPS, K_CINFO)))))
  r <- tryCatch(httr2::request(url) |> httr2::req_method("POST") |>
    httr2::req_headers(Accept = "application/json, text/event-stream", `MCP-Protocol-Version` = "2026-07-28", `Mcp-Method` = "server/discover") |>
    httr2::req_body_raw(body, "application/json") |> httr2::req_timeout(15) |>
    httr2::req_error(is_error = function(r) FALSE) |> httr2::req_perform(), error = function(e) { cat("request failed:", conditionMessage(e), "\n"); NULL })
  if (is.null(r)) return(invisible())
  st <- httr2::resp_status(r); wa <- httr2::resp_header(r, "WWW-Authenticate")
  cat("POST server/discover (no token) -> HTTP", st, "\n")
  if (!is.null(wa)) cat("WWW-Authenticate:", substr(wa, 1, 200), "\n")
  ch <- parse_www_auth(wa)
  prm_urls <- c(ch$resource_metadata, {
    u <- httr2::url_parse(url); base <- sprintf("%s://%s", u$scheme, u$hostname)
    c(paste0(base, "/.well-known/oauth-protected-resource", sub("/$", "", u$path %||% "")), paste0(base, "/.well-known/oauth-protected-resource"))
  })
  prm <- NULL; for (p in unique(prm_urls)) { prm <- get_json(p); if (!is.null(prm)) { cat("PRM from", p, "\n"); break } }
  if (is.null(prm)) { cat("no protected resource metadata found\n"); return(invisible()) }
  cat("  resource:", prm$resource %||% "-", "| authorization_servers:", paste(unlist(prm$authorization_servers), collapse = ", "),
      "| scopes_supported:", paste(unlist(prm$scopes_supported), collapse = " "), "\n")
  iss <- unlist(prm$authorization_servers)[1]
  asm <- NULL; for (m in as_meta_urls(iss)) { asm <- get_json(m); if (!is.null(asm)) { cat("AS metadata from", m, "\n"); break } }
  if (is.null(asm)) { cat("no AS metadata\n"); return(invisible()) }
  cat("  issuer matches:", identical(asm$issuer, iss), "\n")
  cat("  code_challenge_methods_supported:", paste(unlist(asm$code_challenge_methods_supported), collapse = ","), "\n")
  cat("  registration_endpoint (DCR):", !is.null(asm$registration_endpoint), "\n")
  cat("  client_id_metadata_document_supported (CIMD):", isTRUE(asm$client_id_metadata_document_supported), "\n")
  cat("  authorization_response_iss_parameter_supported:", isTRUE(asm$authorization_response_iss_parameter_supported), "\n")
  cat("  token_endpoint_auth_methods_supported:", paste(unlist(asm$token_endpoint_auth_methods_supported), collapse = ","), "\n")
}
for (u in c("https://mcp.sentry.dev/mcp", "https://mcp.linear.app/mcp", "https://mcp.notion.com/mcp", "https://api.githubcopilot.com/mcp/")) probe(u)
```

`test_oauth_discovery.out`

```text

== https://mcp.sentry.dev/mcp 
POST server/discover (no token) -> HTTP 401 
WWW-Authenticate: Bearer realm="OAuth", resource_metadata="https://mcp.sentry.dev/.well-known/oauth-protected-resource/mcp" 
PRM from https://mcp.sentry.dev/.well-known/oauth-protected-resource/mcp 
  resource: https://mcp.sentry.dev/mcp | authorization_servers: https://mcp.sentry.dev | scopes_supported: org:read project:write team:write event:write alerts:write 
AS metadata from https://mcp.sentry.dev/.well-known/oauth-authorization-server 
  issuer matches: TRUE 
  code_challenge_methods_supported: S256 
  registration_endpoint (DCR): TRUE 
  client_id_metadata_document_supported (CIMD): TRUE 
  authorization_response_iss_parameter_supported: TRUE 
  token_endpoint_auth_methods_supported: client_secret_basic,client_secret_post,none 

== https://mcp.linear.app/mcp 
POST server/discover (no token) -> HTTP 401 
WWW-Authenticate: Bearer realm="OAuth", resource_metadata="https://mcp.linear.app/.well-known/oauth-protected-resource/mcp", scope="read write" 
PRM from https://mcp.linear.app/.well-known/oauth-protected-resource/mcp 
  resource: https://mcp.linear.app/mcp | authorization_servers: https://mcp.linear.app | scopes_supported: read write 
AS metadata from https://mcp.linear.app/.well-known/oauth-authorization-server 
  issuer matches: TRUE 
  code_challenge_methods_supported: S256 
  registration_endpoint (DCR): TRUE 
  client_id_metadata_document_supported (CIMD): TRUE 
  authorization_response_iss_parameter_supported: TRUE 
  token_endpoint_auth_methods_supported: client_secret_basic,client_secret_post,none 

== https://mcp.notion.com/mcp 
POST server/discover (no token) -> HTTP 401 
WWW-Authenticate: Bearer realm="OAuth", resource_metadata="https://mcp.notion.com/.well-known/oauth-protected-resource/mcp", error="invalid_token", error_description="Missing or invalid access token" 
PRM from https://mcp.notion.com/.well-known/oauth-protected-resource/mcp 
  resource: https://mcp.notion.com/mcp | authorization_servers: https://mcp.notion.com | scopes_supported: default 
AS metadata from https://mcp.notion.com/.well-known/oauth-authorization-server 
  issuer matches: TRUE 
  code_challenge_methods_supported: plain,S256 
  registration_endpoint (DCR): TRUE 
  client_id_metadata_document_supported (CIMD): TRUE 
  authorization_response_iss_parameter_supported: FALSE 
  token_endpoint_auth_methods_supported: client_secret_basic,client_secret_post,none 

== https://api.githubcopilot.com/mcp/ 
POST server/discover (no token) -> HTTP 401 
WWW-Authenticate: Bearer error="invalid_request", error_description="No access token was provided in this request", resource_metadata="https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp/" 
PRM from https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp/ 
  resource: https://api.githubcopilot.com/mcp/ | authorization_servers: https://github.com/login/oauth | scopes_supported: repo read:org read:user user:email read:packages write:packages read:project project gist notifications 
AS metadata from https://github.com/.well-known/oauth-authorization-server/login/oauth 
  issuer matches: TRUE 
  code_challenge_methods_supported: S256 
  registration_endpoint (DCR): FALSE 
  client_id_metadata_document_supported (CIMD): FALSE 
  authorization_response_iss_parameter_supported: TRUE 
  token_endpoint_auth_methods_supported:  
```

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN

- **ASCII sources.** R code must be ASCII; R CMD check warns otherwise. Write non-ASCII as backslash-u escapes, or build it with `intToUtf8()`. Section 2.17 shows that raw UTF-8 bytes in source misbehave in a C locale anyway.
- **Writing files.**
  - Write only under `tools::R_user_dir("gptr", which = "config" | "cache" | "data")`, `tempdir()`, or project paths the user asked for (`.gptr/`, REQ-27).
  - Never write into other harnesses' config files. The importer only reads them.
  - OAuth tokens go under `R_user_dir("gptr", "data")/oauth/<issuer-hash>/`, with permissions 0600/0700 on Unix.
  - httr2's `oauth_token_cached(cache_disk = TRUE)` writes to `oauth_cache_path()`. Only allow it after the user opts in, for example through `mcp_login()`.
- **Examples and tests.**
  - Examples must not start servers, open ports or reach the network: wrap them in `if (interactive())` or `\dontrun{}`.
  - Tests: unit-test the JSON framing, `json_ascii`, the TOML reader, the config importer (fixtures under `tests/testthat/fixtures/`) and skill parsing.
  - Integration tests (spawning `Rscript` stdio servers, loopback httpuv) run locally and on CI but are `skip_on_cran()`, because of child processes and timing.
  - Never contact real MCP servers in tests.
- **Child processes.** Spawn them only on explicit request. Clean them up with `cleanup_tree = TRUE`, a finalizer, and `on.exit()` in tests. Do not leave processes behind after R CMD check.
- **Cores and threads.** processx and httpuv use no extra CPU cores beyond I/O threads, so nothing to declare.
- **Interactivity.** `mcp_login()` and elicitation prompts must check `interactive()`. Non-interactive runs, including knitr (REQ-25), decline elicitation and never open a browser.

### 6.2 Windows specifics

None of this was executed on Windows. Each item is labelled.

1. **Rscript path.** `file.path(R.home("bin"), "Rscript.exe")`; callr does the same (VERIFIED from callr source). On Windows `R.home("bin")` points at the architecture subfolder (UNCERTAIN on exact form); callr's approach works regardless.
2. **Batch shims** (`npx.cmd`, `uvx.cmd`, `pnpm.cmd`). `Sys.which("npx")` finds `.cmd`/`.bat` files (VERIFIED from `?Sys.which`). CreateProcess cannot run them directly, so run `cmd.exe /d /c call <shim> args...`. The processx docs (VERIFIED) show `process$new("cmd.exe", c("/c", "call", bat_file, ...))`; `/d`, which skips AutoRun, is our addition. Arguments pass through cmd.exe parsing: `%`, `^`, `&`, `|` and `"` in arguments are dangerous (BatBadBut). MCP arguments come from config, not from the model, but gptr should still refuse arguments containing `%` or `"` for `.cmd` targets, or escape them. Corrected in verification: Claude Code's current docs do **not** recommend `cmd /c npx`; version 2.1.119 removed its "Windows requires 'cmd /c' wrapper" warning as a false positive.
3. **Hidden windows.** `windows_hide_window = TRUE`, so launching servers from RGui or RStudio does not flash console windows (processx option; LIKELY effect).
4. **Line endings.** R's stdout is in text mode on Windows, so a stdio server written in R emits `\r\n` (UNCERTAIN; standard MSVCRT behaviour). The client strips a trailing `\r`; the prototype does. JSON parsers tolerate `\r` as whitespace anyway.
5. **Encoding.** R 4.2+ on Windows uses UTF-8 as the native encoding, which avoids most C-locale problems. Still send raw bytes, use `encoding = "UTF-8"` in processx, and write ASCII JSON; these are verified to work in the C locale, the worst case.
6. **Process trees.** `kill_tree()` works through the ps package on Windows (processx docs; LIKELY). Pi uses `taskkill /T /F` for the same purpose. Closing stdin to request a graceful exit works on Windows too.
7. **Signals.** There is no SIGTERM. processx `kill()` calls TerminateProcess, and `interrupt()` sends CTRL_BREAK. Rely on stdin EOF for graceful shutdown.
8. **Paths in configs.** Claude Desktop's Windows example uses `C:\\Users\\...` in JSON args (VERIFIED from the MCP docs). The `~/.claude.json` project keys on Windows are UNCERTAIN; compare normalised and case-folded forms. `%APPDATA%` locates Claude Desktop and VS Code user config. Some Node servers need `APPDATA` passed in `env`: the MCP docs' ENOENT troubleshooting note (VERIFIED) says to add the expanded value of `%APPDATA%` to `env`, so the env allowlist must include `APPDATA`, as mcptools' list does.
9. **Loopback OAuth.** The Windows firewall may prompt when httpuv binds, even on 127.0.0.1 (UNCERTAIN). The redirect listener must bind `127.0.0.1`, not `0.0.0.0`; httr2's listener already does.
10. **httpuv on Windows.** CRAN binaries exist (httpuv is compiled); later's event loop runs at the RGui and Rterm top level (LIKELY, from the later docs).

### 6.3 Other front-ends

- **RStudio / Positron.** The console idles through later, so `mcp_serve()` answers requests between user commands. `rstudioapi` is not needed.
- **knitr / Quarto rendering (REQ-25).** There is no idle loop. `mcp_serve()` is only useful during an explicit wait loop, such as a plan-provider call. MCP client calls work normally. Elicitation is declined.
- **IRkernel / Jupyter.** Whether later callbacks run between cells is UNCERTAIN. `mcp_serve()` should warn that it is unsupported there until tested.
- **Remote sessions (RStudio Server, Workbench, SSH).** OAuth loopback redirects do not reach the R process. Fall back to "paste the redirected URL", which is Pi's approach. Write gptr's own reader: httr2's `oauth_flow_auth_code_read` is internal in 1.2.2 and in 1.3.0, and it drops `iss`.

---

## 7. Risks, pitfalls, open questions

### 7.1 Risks

1. **The spec moves fast.** Protocol 2026-07-28 arrived 8 months after 2025-11-25 and changed the wire format. A self-written client means ongoing maintenance.
   - Mitigations: dual-era support; a small protocol layer with fixtures copied from the spec's examples directory; re-checking the versioning page at each gptr release.
2. **Era detection edge cases.**
   - Legacy servers that ignore unknown pre-initialize requests cost the probe timeout (5 s) on first connect. Caching the era per server config removes the cost later.
   - Some legacy servers may *process* an era-ambiguous request under legacy semantics. That is why the probe must be `server/discover` and not `tools/list`.
3. **Security.**
   - Project-level MCP configs from other harnesses run arbitrary commands, which needs trust gating.
   - Tool descriptions, results and server instructions are untrusted text reaching the model (prompt injection), and annotations are hints only.
   - `mcp_serve()` exposes arbitrary R evaluation. It needs a random token, localhost binding, Origin checks and the permission layer.
   - Never forward the user's provider API keys to MCP servers. Use the env allowlist; Claude Code blanks credential-like variables in remote URLs and headers.
4. **Locale and encoding.** Any code path that `cat()`s or `print()`s non-ASCII text in a C locale corrupts it and can be quadratically slow (85-296 s for 600k characters across two runs). The code must write ASCII JSON and mark external strings as UTF-8. **Test this in CI under `LC_ALL=C`.**
5. **Blocking.** The R session is single-threaded:
   - a slow MCP call blocks the console until it finishes, is interrupted, or times out;
   - an in-session server cannot answer while R is busy, and external clients may time out.
   Document this, and use generous client-side timeouts for gptr-served tools.
6. **Chatty or malformed servers.**
   - A server that writes non-JSON to stdout (common with print-debugging Python servers) produces warnings; ignore those lines.
   - A server that floods stderr is fine because stderr goes to a file.
   - A single message larger than 16 MiB is rejected.
7. **OAuth fragmentation.** Some servers support DCR only, some also CIMD, and some (GitHub) neither. CIMD requires the maintainer to host a JSON document permanently. DCR is deprecated and may disappear.
8. **Claude-plugin compatibility drift.** Claude Code's plugin schema changes often; the docs cite versions up to v2.1.283. gptr should support a stable subset (skills, commands, agents, .mcp.json) and ignore the rest with diagnostics.
9. **Skill catalog bloat.** 161 skills are about 16k tokens. Without a budget, every prompt pays for skills never used.

### 7.2 Pitfalls found during this research (all executed)

- `httpuv::service(0)` loops forever in non-interactive R.
- processx `read_output()` returns at most 8192 characters per call, so a naive buffer concatenation is quadratic.
- `file("stdout")` creates a regular file named `stdout`.
- `file("stdin", encoding = "UTF-8")` in a C locale fails on UTF-8 input.
- `cat()` of UTF-8 in a C locale produces `<U+00E9>` text and is quadratic.
- jsonlite writes native-encoded non-ASCII strings as `<c3><a9>` in a C locale.
- `jsonlite::toJSON(auto_unbox = TRUE)` turns a length-1 vector into a scalar, so `x = 5` becomes `5`, not `[5]`. Wrap length-1 array arguments in `I()` or `list()`. The generated R wrappers must consult the schema (`type: array`) and wrap automatically.
- An empty named list serialises as `{}` and an empty unnamed list as `[]`. Use `structure(list(), names = character())` for empty `arguments`.
- `httr2::resp_body_raw()` on an empty-body streaming response (`req_perform_connection`) returned something `rawToChar()` rejected ("argument 'x' must be a raw vector"). Guard it.
- `list.files(recursive = TRUE)` over Claude's plugin cache is unbounded.
- RcppTOML's default `escape = TRUE` doubles backslashes, and it overflows large integers.
- The tool I used to write prototype files decoded backslash-u escape sequences into raw UTF-8 characters, silently. Always check generated R sources with `grep -P '[^\x00-\x7F]'` before trusting them.

### 7.3 Open questions (for the maintainer or for later tracks)

1. Should gptr read **user-level** MCP configs of other harnesses automatically, with project-level ones only after trust? Or only when the user calls `mcp_import()` or sets `import = TRUE`? This track recommends automatic for user-level, gated for project-level.
2. Default exposure: `"r"` for all MCP tools, or switch to `"direct"` when a server has very few tools (say 3 or fewer) and the model is weak at writing code?
3. Should gptr host a CIMD client-metadata document, for example at `https://<maintainer>.github.io/gptr/oauth/client.json`? This is a permanent operational commitment. The alternative is DCR only, plus a pre-registration escape hatch.
4. Will later callbacks run between cells in IRkernel and Positron notebooks? This decides whether `mcp_serve()` works in notebooks.
5. Should `mcp_serve()` expose file tools (read, write, edit) to Codex and Claude, or only the R-specific tools, since the external agent has its own file tools?
6. Is legacy SSE resumption (`Last-Event-ID`) worth implementing? None of the servers probed today could be tested for it without credentials.
7. Codex plugin format (`codex plugin`) and Codex's skills `agents/openai.yaml`: consume, or ignore?
8. Sampling (deprecated): should a gptr client offer to answer `sampling/createMessage` with its own providers (with approval), for legacy servers that need it?
9. How does the Claude Code "sdk" in-process MCP transport (report 07) behave on Windows, and does it need the HTTP fallback there?

---

## 8. Sources

### MCP specification (fetched or saved on 2026-09-29)

| Topic | URL |
|---|---|
| Versioning (current = 2026-07-28) | https://modelcontextprotocol.io/specification/versioning |
| 2026-07-28 index | https://modelcontextprotocol.io/specification/2026-07-28/ |
| 2026-07-28 changelog | https://modelcontextprotocol.io/specification/2026-07-28/changelog |
| basic (messages, `_meta`, error codes) | https://modelcontextprotocol.io/specification/2026-07-28/basic |
| versioning and backward compatibility | https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning |
| stdio transport | https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio |
| Streamable HTTP transport | https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http |
| MRTR | https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr |
| subscriptions | https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions |
| cancellation | https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/cancellation |
| progress | https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/progress |
| authorization | https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization |
| authorization-server discovery | https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/authorization-server-discovery |
| client registration | https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration |
| tools | https://modelcontextprotocol.io/specification/2026-07-28/server/tools |
| server/discover | https://modelcontextprotocol.io/specification/2026-07-28/server/discover |
| caching | https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching |
| deprecated features | https://modelcontextprotocol.io/specification/2026-07-28/deprecated |
| 2025-11-25 (lifecycle, transports, tools, elicitation, sampling, roots, changelog) | https://modelcontextprotocol.io/specification/2025-11-25/ |
| 2025-06-18 changelog | https://modelcontextprotocol.io/specification/2025-06-18/changelog |
| Schemas (byte-identical to the saved copies) | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2026-07-28/schema.ts and `.../2025-11-25/schema.ts` |
| Claude Desktop config paths | https://modelcontextprotocol.io/docs/develop/connect-local-servers |

### Agent Skills

- https://agentskills.io/specification
- https://agentskills.io/client-implementation/adding-skills-support.md
- https://agentskills.io/llms.txt

### Harness documentation

| Harness | URL |
|---|---|
| Claude Code skills | https://code.claude.com/docs/en/skills |
| Claude Code MCP | https://code.claude.com/docs/en/mcp |
| Claude Code plugin manifest reference | https://code.claude.com/docs/en/plugins-reference (= /plugins/manifest-reference) |
| Claude Code marketplace reference | https://code.claude.com/docs/en/plugins/marketplace-reference |
| Claude Code sub-agents | https://code.claude.com/docs/en/sub-agents |
| Claude Code hooks | https://code.claude.com/docs/en/hooks |
| Codex MCP | https://learn.chatgpt.com/docs/extend/mcp?surface=cli (redirected from https://developers.openai.com/codex/mcp) |
| Codex skills | https://learn.chatgpt.com/docs/build-skills (redirected from https://developers.openai.com/codex/skills) |
| Cursor MCP | https://cursor.com/docs/context/mcp |
| VS Code MCP configuration | https://code.visualstudio.com/docs/copilot/reference/mcp-configuration; also search results pointing to https://code.visualstudio.com/docs/agents/reference/mcp-configuration and https://github.com/microsoft/vscode/issues/251790 |
| Gemini CLI MCP | https://geminicli.com/docs/tools/mcp-server/ |
| OpenAI tool search (LIKELY; search result) | https://developers.openai.com/api/docs/guides/tools-tool-search |
| mcpr (not on CRAN) | https://github.com/devOpifex/mcpr, https://devopifex.r-universe.dev/mcpr |
| MCPR (not on CRAN) | https://github.com/phisanti/MCPR |

### Local source read (with line numbers cited in the text)

- **Pi clone** at `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi` (commit 1b347794):
  - `packages/mcp/src/protocol/types.ts`, `packages/mcp/src/transports/stdio.ts`, `packages/mcp/src/transports/transport.ts`;
  - `packages/coding-agent/docs/mcp.md`, `skills.md`, `packages.md`, `cli.md`;
  - `packages/coding-agent/src/core/skills.ts`.
- **CRAN tarballs** in `work/16/src/`:
  - mcptools 1.0.3 (`R/client.R`, `R/client-http.R`, `R/client-auth.R`, `R/server.R`, `R/session.R`, `R/protocol-version.R`, `NEWS.md`);
  - mcplite 0.1.0 (`R/protocol.R`, `R/transport_stdio.R`);
  - btw 1.5.0 (`R/tool-skills.R`, `R/mcp.R`);
  - corteza 0.7.1 (`R/serve.R`, `R/mcp-handler.R`);
  - aisdk 1.4.12 (`NAMESPACE`).
- **CRAN package database** `work/16/web/packages.rds` and the saved CRAN pages `work/16/web/cran_*.html`.
- **Installed R packages:**
  - printed functions and help pages: `httpuv::service`, `httr2::oauth_flow_auth_code`, `oauth_flow_auth_code_parse`, `oauth_flow_auth_code_listen`, `oauth_redirect_uri`, `oauth_cache_path`, `callr:::setup_rscript_binary_and_args`;
  - processx `process.Rd`, later `later.Rd`, base `Sys.which.Rd`.

### CLIs (executed, read-only)

- `claude --version`, `claude --help`, `claude mcp --help`, `claude mcp serve` (handshake and `tools/list` only).
- `codex --version`, `codex --help`, `codex mcp --help`, `codex mcp add --help`, `codex mcp get <probe> -c ... --json`.

### Remote MCP servers probed read-only

No credentials were sent and no clients were registered.

- https://mcp.sentry.dev/mcp
- https://mcp.linear.app/mcp
- https://mcp.notion.com/mcp
- https://api.githubcopilot.com/mcp/

### Other gptr reports cross-referenced

- `dev/research/00-digest.md`
- `05-pi-extensibility.md` (via the digest)
- `06-pi-subagents-mcp-codemode.md`
- `07-anthropic-api-claude-plan.md`

---

## Verification log

An independent adversarial fact-check was run on 2026-09-29 (R 4.4.3, macOS, `Rscript --vanilla`, C locale unless noted).

**How it was done:**
- **Prototypes.** Every prototype embedded in section 5 was first compared byte for byte with the files in `work/16/proto/`: all 56 embedded files are identical. They were then copied to `work/verify-16/proto/` and re-run with `run_all.sh`. All 13 tests exited 0.
- **Outputs.** The outputs match the originals except in these places:
  - timings;
  - random tokens, ports and session ids;
  - absolute fixture paths;
  - the `test_config` fixture-path defect noted in 5.11.
- **Sources.** Pi was read at commit 1b347794. CRAN tarballs for httr2 1.3.0, mcptools 1.0.3 and processx 3.9.0 were freshly downloaded from CRAN. The spec pages and docs were fetched live.

**Verdicts:**
- **confirmed**: the claim matched the source.
- **corrected**: the report was edited in place; the correction is marked "corrected in verification".
- **unverifiable**: the claim could not be checked here.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | Current MCP revision is 2026-07-28; per-request `_meta` versioning; `server/discover` mandatory for servers | confirmed | live https://modelcontextprotocol.io/specification/versioning and .../2026-07-28/basic/versioning |
| 2 | `LATEST_PROTOCOL_VERSION` at `schema-2026-07-28.ts:30` / `schema-2025-11-25.ts:12`; -32020/-32021/-32022; -32042 legacy only; `ResultType`; `ttlMs`/`cacheScope`; MRTR fields; `_meta` keys | confirmed | the schema files; their SHA-256 equals a fresh fetch from GitHub `main` |
| 3 | stdio dual-era probe rules, including "The fallback MUST NOT be keyed to one specific error code" | confirmed | `spec/2026-07-28/basic_transports_stdio.md:128-154`; live versioning page |
| 4 | Modern HTTP headers (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, `Mcp-Param-{Name}`), `=?base64?...?=`, 404/-32601, 400/-32020, GET/DELETE 405, `X-Accel-Buffering: no`, 4xx fallback rules | confirmed | live streamable-http page |
| 5 | Legacy HTTP: client "must" send `notifications/cancelled` | corrected (SHOULD) | `spec/2025-11-25/basic_transports.md:126-129` |
| 6 | PRM and AS discovery URL order, `issuer` equality, CIMD fields, registration priority, DCR `application_type` MUST, credentials bound to the issuer | confirmed | live authorization-server-discovery and client-registration pages |
| 7 | "Clients MUST refuse to proceed when the AS does not support S256" | corrected (spec wording: refuse when `code_challenge_methods_supported` is absent) | `basic_authorization_security-considerations.md:51-58` |
| 8 | RFC 9207 `iss` validation table | confirmed | `basic_authorization_index.md:194-211` |
| 9 | Pi supports up to 2025-11-25 (`types.ts:4,9`); 16 MiB cap (`transport.ts:3`); 64 KiB stderr tail, 500 ms / 2000 ms (`stdio.ts:7-10`); `\r` strip (`stdio.ts:199`); taskkill and process groups (`stdio.ts:17-41`) | confirmed | Pi clone |
| 10 | Pi `docs/mcp.md` lines 25-47, 28, 45, 59, 64, 87, 101, 122-158, 156, 172; `cli.md:168,174` (QuickJS, 3000-token budget, BM25) | confirmed | Pi clone |
| 11 | Pi skill precedence: "user scanned first, so user wins" | **corrected** (project wins at runtime) | `resource-loader.ts:833-838`, `package-manager.ts:181-197, 2477-2560`, `docs/skills.md:83-85` |
| 12 | Pi `formatSkillsForPrompt` at `skills.ts:355-382`; no warning on a name/directory mismatch; Pi packages format | confirmed (the function ends at line 383) | Pi clone |
| 13 | mcptools stdio client (`client.R:1318-1349`), "intentionally unsupported" resumability (`client-http.R:399`), config path, env allowlist including `APPDATA`, no `application_type`, protocol versions 2024-11-05..2025-11-25, 2-minute session timeout | confirmed | fresh CRAN tarball mcptools 1.0.3 (identical to `work/16/src`) |
| 14 | CRAN versions and dates: mcptools 1.0.3, mcplite 0.1.0, btw 1.5.0, corteza 0.7.1, aisdk 1.4.12, RcppTOML 0.2.3 (C++17), tomledit 0.1.1 (Cargo), toml 1.1.0 (V8); mcpr and MCPR not on CRAN | confirmed | `tools::CRAN_package_db()`, `available.packages()` |
| 15 | btw imports "20 packages" | corrected (22, or 20 without base) | `available.packages()` |
| 16 | httr2 OAuth pieces: signatures, `listen()` binds 127.0.0.1 and returns the whole query, no `iss` check, internal `oauth_client_get_token` | confirmed (1.2.2 printed; 1.3.0 source read) | installed httr2 1.2.2; CRAN tarball httr2 1.3.0 |
| 17 | httr2 has `oauth_flow_auth_code_read` (usable) | **corrected** (internal, not exported; drops `iss`) | httr2 1.2.2 and 1.3.0 NAMESPACE |
| 18 | httr2 1.2.2 as the relevant version | **corrected** (CRAN is 1.3.0 since 2026-07-13; mcptools needs >= 1.2.3; the 1.3.0 changes are listed in 1.8) | CRAN db; httr2 1.3.0 NEWS.md |
| 19 | `resp_stream_sse()` drops empty-data events and ignores `retry` | confirmed, still true in 1.3.0 | httr2 1.3.0 `R/resp-stream-sse.R` |
| 20 | `httpuv::service` source; `service(0)` loops forever in Rscript | confirmed | printed httpuv 1.6.17 |
| 21 | later docs: callbacks run only at top level or in `run_now()` | confirmed | `later.Rd` via `tools::Rd_db` |
| 22 | processx `read_output()` returns at most 8192 characters (611 reads for 5 MB) | confirmed (processx 3.8.6); 3.9.0 is current (note added) | `chunk.R` in `verify-16`; processx 3.9.0 NEWS |
| 23 | processx "Batch files": `cmd.exe /c call` | confirmed; `/d` is labelled as our addition | processx 3.9.0 `man/process.Rd` |
| 24 | C-locale `cat()` prints `<U+00E9>` and is quadratic: 0.27/1.18/4.79 s, 600k = 296 s | confirmed (shape); timings **corrected** (re-run 0.17/0.71/2.81 s, 600k = 85 s) | `cat_c_locale.R` re-run |
| 25 | `file("stdin", encoding = "UTF-8")` fails on UTF-8 input in C; `readLines(encoding = "UTF-8")` keeps `68 c3 a9 20 f0 9f 98 80` | confirmed | `stdin_enc.R`, `stdin_plain.R` in `verify-16` |
| 26 | jsonlite writes unknown-encoding strings as `<c3><a9>`; escaped literals are fine; `file("stdout")` creates a file; `auto_unbox` / empty-list rules; `writeLines(useBytes = TRUE)` keeps the bytes | confirmed | `enc_escape.R`, `enc_literal.R`, `loc1.R`, `loc2.R` |
| 27 | RcppTOML `escape = TRUE` doubles backslashes; `0xDEAD_BEEF` becomes -559038737; 2^53-1 becomes -1; empty array becomes NULL; `toml_read()` is 242 lines; 36 of 39 values agree | confirmed | `t.toml` probe; `test_toml` re-run identical |
| 28 | Line counts: stdio client 342, bridge 37 | confirmed | `wc -l` |
| 29 | `claude mcp serve` answers `server/discover` with -32601, then 2025-11-25; 27 tools; 143,525 characters | confirmed | `test_interop` re-run |
| 30 | HTTP live-session server: 11 requests, `made_by_agent` present, 401/403/405/-32020; bridge in both eras | confirmed | `test_http` and `test_bridge` re-run |
| 31 | OAuth probes of Sentry, Linear, Notion and GitHub (PRM, AS, S256, DCR, CIMD, `iss`) | confirmed (output identical) | `test_oauth_discovery` re-run (read-only, no credentials) |
| 32 | Codex 0.157.0: `-c` override JSON; `mcp add` flags including `--oauth-client-registration AUTO/CIMD/DCR`; no `mcp-server` subcommand; `plugin` subcommand exists | confirmed | `codex --help`, `codex mcp add --help`, `codex mcp get ... --json` |
| 33 | Codex config fields; `startup_timeout_sec` 10, `tool_timeout_sec` 60 | confirmed (docs via fetch tool, so LIKELY-grade) | learn.chatgpt.com/docs/extend/mcp |
| 34 | Codex skills listing "2% or 8000 characters"; Codex is project-over-user | **corrected** (8,000 is the fallback when the window is unknown; collisions are not merged) | learn.chatgpt.com/docs/build-skills |
| 35 | Agent Skills spec fields and limits; client guide (scan bounds 4-6 / 2000, project over user, lenient parsing, catalog, `skill_content`, compaction) | confirmed | live agentskills.io specification and client-implementation pages |
| 36 | Claude Code skills: 1,536 characters, 1% budget, settings and env names, 5,000 / 25,000 tokens after compaction, enterprise > personal > project | confirmed | code.claude.com/docs/en/skills (full text) |
| 37 | Claude Code MCP: output limit 25k with warning at 10k; idle timeout 5 min HTTP, 30 min stdio; scope precedence; `${VAR:-default}`; `~/.claude.json` | confirmed | code.claude.com/docs/en/mcp |
| 38 | "Claude's docs say to use `cmd /c npx` on Windows" | **corrected** (not in current docs; the 2.1.119 changelog removed the warning) | raw `mcp.md`; `llms-full.txt` changelog |
| 39 | Claude Desktop config paths, log location, `APPDATA` ENOENT note, Windows `C:\\Users` example | confirmed | live connect-local-servers page |
| 40 | Gemini: `url` is SSE, `httpUrl` is Streamable HTTP; `timeout` 600,000 ms; `trust`/`includeTools`/`excludeTools`; env syntax | confirmed | geminicli.com MCP page |
| 41 | Claude plugin manifest (only `name` required; component-key semantics; unknown keys stripped); `${CLAUDE_PLUGIN_DATA}` path; 33 hook events | confirmed | `llms-full.txt` plugins reference and hooks pages |
| 42 | Anthropic tool search type names and `defer_loading` 400 rule; MCP connector beta and shape | confirmed | claude-api skill reference (`SKILL.md`, `shared/tool-use-concepts.md`) |
| 43 | MCP connector "only works for public remote servers" | corrected (reworded as an inference, LIKELY) | same |
| 44 | Plugin cache 1.5 GB, 69,652 files, "16 `node_modules`" | confirmed / corrected (15 top-level, 797 nested) | `find` and `du` |
| 45 | Real skill corpus: 161 skills, 57 shadowed, field counts, 64,537-character catalog | confirmed | `test_skills` re-run (0.34 s) |
| 46 | Config importer finds 14 unique servers on the fixtures | confirmed after fixing the relocation defect (13 without the fix) | `test_config` re-run |
| 47 | `claude --mcp-config` / `--strict-mcp-config` flags; `.mcp.json` "Pending approval" | confirmed | `claude --help`, `claude mcp --help` |

**Unverifiable in this pass**, so the labels in the text stand:
- all Windows behaviour in 6.2, since no Windows machine was available;
- whether later callbacks run in IRkernel or Positron notebooks;
- whether Sentry, Linear and Notion accept an arbitrary loopback port;
- VS Code and Cursor config fields and paths;
- the OpenAI `tool_search` details;
- Claude Code agent frontmatter and marketplace source types (not re-fetched);
- the original 296 s run, which was not captured in a `.out` file (a re-run gave 85 s);
- the exact provider tool-name regex.


