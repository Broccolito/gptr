# Track 05 - Pi extensions, skills, prompt templates, packages, settings, modes

Research date: 2026-09-29. Author: research sub-agent (track 05).
Primary source: Pi monorepo clone, commit `1b347794e2a630e4359f2584f4eea388145d0ddf` (2026-09-29),
`@earendil-works/pi-coding-agent` version `0.99.1`.

Path abbreviations used in citations:

- `$PI` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi`
- `$CA` = `$PI/packages/coding-agent`
- `$W`  = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/05` (prototype scratch directory)

Evidence labels: **VERIFIED** (I read the source / ran the command myself), **LIKELY** (documented or
strongly implied, not executed), **UNCERTAIN** (inference).

All R experiments were run with `Rscript --vanilla` on R 4.4.3, macOS (aarch64), 615 installed packages.
Nothing was run on Windows; every Windows statement is LIKELY or UNCERTAIN unless it quotes R documentation.

---

## 1. Executive summary

1. **Pi's extension is a factory function** `export default function (pi: ExtensionAPI)`. The factory only
   *registers* things (event handlers, tools, commands, shortcuts, flags, providers, MCP servers, renderers);
   "action" methods (`sendMessage`, `appendEntry`, `setActiveTools`, ...) throw until the runner is bound to a
   session. A factory that throws has all of its registrations discarded. VERIFIED (`$CA/src/core/extensions/loader.ts:156-236, 243-529, 593-612`).
2. **41 events** exist (`$CA/src/core/extensions/types.ts:1540-1607`). They fall into seven dispatch
   semantics that gptr must reproduce exactly: *notify*, *cancel (first cancel wins)*, *block (first block
   wins, handler error = block)*, *chain/patch*, *replace (last wins)*, *first decision wins*, *collect*.
   VERIFIED (`$CA/src/core/extensions/runner.ts:1020-1550`).
3. **Permission gates, plan mode, ask-user and todo are not core features in Pi**; they are example
   extensions built from a small set of hooks: `tool_call` (block / patch input), `before_agent_start`
   (inject message / system prompt), `context` (filter messages), `turn_end`/`agent_end`,
   `setActiveTools`, `sendMessage`, `appendEntry`, `registerTool`, `registerCommand`, `registerFlag`,
   and `ctx.ui.select/confirm/input/notify/setStatus`. VERIFIED (`$CA/examples/extensions/permission-gate.ts`, `plan-mode/index.ts`, `question.ts`, `todo.ts`).
   I re-implemented all four in pure R on a prototype runtime; **38/38 behavioural checks pass** (section 5.4-5.5).
4. **Skills** follow the Agent Skills standard: a directory with `SKILL.md` (YAML frontmatter `name`,
   `description`, ...). Only name + description + path go into the system prompt (XML `<available_skills>`);
   the model reads the file with the `read` tool; `/skill:name args` force-loads it. VERIFIED (`$CA/src/core/skills.ts:355-383`, `$CA/src/core/agent-session.ts:2062-2086`).
5. **Pi scans `.pi/skills`, `~/.pi/agent/skills`, `.agents/skills` (cwd up to git root) and
   `~/.agents/skills`. It does NOT scan `.claude/skills` or `.codex/skills`** (`grep` for `.claude`, `.codex`,
   `claude/skills`, `codex/skills` over `$CA/src`, `$CA/docs`, `$CA/README.md` finds only a Bedrock model id;
   the example `claude-rules.ts` reads `.claude/rules`, not skills). VERIFIED by grep. Claude Code uses `~/.claude/skills` + `.claude/skills`;
   Codex uses `.agents/skills`, `~/.agents/skills`, `/etc/codex/skills`. On the development machine
   all three of `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills` exist and overlap heavily.
6. **A real YAML parser is mandatory for skills.** 21 of 65 real `SKILL.md` files on this machine use a
   folded block scalar (`description: >`). With the `yaml` package my loader read 37 unique skills with 0
   warnings; a hand-written "key: value" parser rejected 12 of the 65 files ("description is required"),
   which lost 4 of the 37 unique skill names outright (37 -> 33) and garbled 6 more descriptions (only 27 of
   37 descriptions identical). VERIFIED by experiment (section 5.2; re-run by the verifier with identical output).
   Recommendation: `yaml` in **Imports**.
7. **Prompt templates** are Markdown files whose file name is the command name; frontmatter keys are
   `description` and `argument-hint`; substitutions are `$1..$N`, `$@`, `$ARGUMENTS`, `${N:-default}`,
   `${@:-default}`, `${@:N}`, `${@:N:L}`. VERIFIED (`$CA/src/core/prompt-templates.ts:25-103`).
   My R port passes 67 assertions ported from Pi's own test-suite, in both a C locale and a UTF-8 locale.
8. **Settings** are two JSON files (`~/.pi/agent/settings.json`, `.pi/settings.json`), deep-merged with
   project over user; arrays replace, except `defaultTools` (`+name`/`-name` modifiers append) and the
   resource arrays (`extensions/skills/prompts/themes/packages`, which are read per scope and combined).
   `defaultProjectTrust`, `cacheWarming`, `deviceId` and `httpProxy` are read from the user file only. VERIFIED
   (`$CA/src/core/settings-manager.ts:131-252, 1021-1104`; `httpProxy`: `$CA/src/main.ts:588, 865` read
   `getGlobalSettings().httpProxy`).
9. **Recommended gptr settings format: JSON** (`jsonlite`, already required for LLM APIs). JSON round-trips
   losslessly when read with `simplifyVector = FALSE`; YAML round trip through `yaml` was *not* identical;
   DCF is flat strings only; an R file would be arbitrary code execution from a project directory.
   VERIFIED by experiment (section 5.3).
10. **Pi packages** are npm/git/local bundles with optional `package.json` `"pi"` manifest
    (`extensions`, `skills`, `prompts`, `themes` arrays with glob and `!`/`+`/`-` filters). VERIFIED
    (`$CA/src/core/pi-manifest.ts`, `$CA/src/core/package-manager.ts:745-791, 2214-2263`). The R analogue is
    an ordinary R package shipping `inst/gptr/{skills,extensions,prompts}`.
11. **Scanning installed R packages is cheap.** For 615 installed packages a vectorised
    `dir.exists()` / `Sys.glob()` scan takes 2-4 ms (49-70 ms once, with a cold directory cache);
    `system.file()` per package takes roughly 80-120 ms (87-345 ms on the first call); scanning only attached
    packages takes 0-2 ms. VERIFIED (section 5.9; four runs in total, two by the author and two by the
    verifier; absolute timings vary with file-system cache state, the ordering does not).
    The cost is not the problem; **trust** is. Recommendation: skills from *attached* packages are
    auto-available (same rule as Posit's `btw`), extension code only from packages explicitly named in
    `plugins`.
12. **Project trust** gates `.pi/settings.json`, `.pi/mcp.json`, `.pi/{extensions,skills,prompts,themes}`,
    `.pi/SYSTEM.md`, `.pi/APPEND_SYSTEM.md` and project `.agents/skills`. Context files
    (`AGENTS.md`/`CLAUDE.md`) load regardless of trust. Decision order: CLI override > `project_trust`
    extension event > saved decision for cwd or nearest ancestor (`~/.pi/agent/trust.json`) >
    `defaultProjectTrust` > interactive prompt; without UI the answer is "not trusted". VERIFIED
    (`$CA/src/core/project-trust.ts:47-96`, `$CA/src/core/trust-manager.ts`).
13. **24 built-in slash commands** (`$CA/src/core/slash-commands.ts:19-44`); dispatch order for typed text
    is: built-in command > `!`/`!!` shell > extension command > `input` event > `/skill:name` expansion >
    prompt-template expansion > model. VERIFIED (`interactive-mode.ts:3096-3294`, `agent-session.ts:1883-1925`).
14. **Run modes**: interactive (TUI), print (final text to stdout, exit code 1 on error), json (JSONL event
    stream with a session header), rpc (bidirectional JSONL with an extension-UI sub-protocol), sdk
    (in-process). `ctx.mode` is `"tui" | "rpc" | "json" | "print"`; `ctx.hasUI` is true in TUI and RPC only.
    VERIFIED (`$CA/src/modes/*`, `types.ts:323-331`).
15. **R-specific hazards found by experiment**: (a) `utils::askYesNo()` returns `TRUE` in a
    non-interactive session, so it must never be used for approvals; (b) `readline()` returns `""` and
    `menu()` errors non-interactively; (c) in a C locale (the default under `Rscript` when `LANG` is unset)
    `cat()` writes `<U+00E9>`-style escapes instead of UTF-8 bytes and `readLines()` returns unmarked
    strings, so files and protocol streams must be read and written as UTF-8 bytes
    (`writeLines(useBytes = TRUE)`), and R sources must be ASCII; (d) `jsonlite::fromJSON(simplifyVector = TRUE)` silently turns one-element
    arrays into scalars on write-back; (e) a formal argument named `id` in a helper that forwards `...`
    swallowed a user argument called `id` (partial/exact matching), so every gptr API that forwards `...`
    must use dot-prefixed formals. All VERIFIED (sections 5.1, 5.3, 5.5, 5.7, 5.10).
16. **Static R-code classification is feasible and fast** (AST walk, 500-line script in 0.05-0.13 s across runs) and gives
    the permission gate something much better than Pi's regexes over bash strings, but it is a heuristic:
    `do.call`, `get`, `eval(parse())` and computed calls must be treated as "dangerous/unknown". VERIFIED (section 5.6).
17. **Prior art in R**: Posit's `btw` (1.5.0.9000) already ships Agent-Skills support, uses
    `inst/skills/` inside R packages, auto-exposes skills of *attached* packages, and reads
    `btw.md`/`AGENTS.md`/`CLAUDE.md`. gptr should read `inst/skills` as well as `inst/gptr/skills` so
    that packages written for `btw` work unchanged. VERIFIED from the btw manual and source.

---

## 2. Findings

### 2.1 Extension model and loading

- An extension is a TypeScript/JavaScript module with a default-exported factory
  `(pi: ExtensionAPI) => void | Promise<void>` (`types.ts:1985`). Pi loads it with `jiti` (no build
  step) (`loader.ts:539-570`). Async factories are awaited before startup continues (`docs/extensions.md`). VERIFIED.
- **Registration vs action.** `createExtensionAPI()` (`loader.ts:243-529`) gives each extension its own
  API object. Registration methods write into the extension's own record (`handlers`, `tools`, `commands`,
  `flags`, `shortcuts`, renderers). Action methods delegate to a shared `runtime` whose members are
  throwing stubs (`"Extension runtime not initialized. Action methods cannot be called during extension
  loading."`) until `runner.bindCore()` replaces them (`loader.ts:156-236`, `runner.ts:409-543`). VERIFIED.
- **Transactional load.** Provider / MCP / virtual-model registrations and flag defaults made during the
  factory are queued (`applyRuntimeChange`, `pendingFlagValues`) and only applied by `commit()` after the
  factory returned; on error `discard()` drops them and marks the API as failed (`loader.ts:259-267, 510-528, 593-612`). VERIFIED.
- **Tool schema check**: `registerTool` throws unless `parameters` is a non-array object (`loader.ts:288-300`). VERIFIED.
- **Stale contexts.** After `/reload`, `newSession`, `fork`, `switchSession`, the old runtime is
  invalidated and every API/ctx access throws a long explanatory error (`runner.ts:721-734`, `loader.ts:192-199`). VERIFIED.
- **Do not start timers/processes in the factory**; use `session_start` and clean up in an idempotent
  `session_shutdown` (`docs/extensions.md` "Respect the runtime lifecycle"). VERIFIED (doc).
- **Extension files and directories** (`loader.ts:716-803`, `package-manager.ts:563-645`):
  1. `extensions/*.ts|*.js` direct files;
  2. `extensions/<dir>/index.ts|index.js`;
  3. `extensions/<dir>/package.json` with `"pi": {"extensions": [...]}`.
  No recursion beyond one level. Dot-files and `node_modules` are skipped; `.gitignore`, `.ignore`,
  `.fdignore` are honoured. VERIFIED.
- **Inline extensions (SDK)**: `DefaultResourceLoader({ extensionFactories: [...] })`; named as
  `<inline:N>` or `<inline:name>`; options `hidden`, `replaceable`, `builtin` (`types.ts:1987-2015`). VERIFIED.
- **Built-in extensions** `builtin:mcp`, `builtin:llama.cpp`, `builtin:codemode`, `builtin:tool-search`
  are ordinary extensions (`builtin: true`). Only `codemode`, `tool-search` and `mcp` are also `replaceable`
  (`llama.cpp` is **not**): if another extension registers a tool/command/flag with the same name as a
  replaceable one, the built-in one is omitted with a warning (`$CA/src/extensions/index.ts:7-14`,
  `resource-loader.ts:120-151`, `docs/settings.md` "Resources"). VERIFIED (corrected by verifier: the
  original text listed `llama.cpp` as replaceable).

### 2.2 Load order, precedence and conflicts

Resolved resources are sorted by `resourcePrecedenceRank` (`package-manager.ts:180-198`), lower = earlier:

| Rank | Source |
|---|---|
| 0 | project + explicit settings entry (`source: "local"`, `scope: "project"`) |
| 1 | project + auto-discovered (`.pi/...`, `.agents/skills`) |
| 2 | user + explicit settings entry |
| 3 | user + auto-discovered (`~/.pi/agent/...`, `~/.agents/skills`) |
| 4 | package resource (`origin: "package"`) |
| 5 | built-in extension |

CLI `-e/--skill/--prompt-template` paths are placed **before** all of these
(`resource-loader.ts:569-571, 587-589`: `mergePaths(cliEnabled..., enabled...)`), inline SDK factories **after**
(`resource-loader.ts:766-769`). Paths are de-duplicated by canonical (realpath) path. VERIFIED.

Consequences (all VERIFIED):

- **Event handlers** run in extension load order, then registration order within an extension
  (`runner.ts:268-270` `snapshotEventHandlers`); handlers added/removed during a dispatch do not affect it.
- **Tools**: among extensions the *first* registration of a name wins (`runner.ts:629-639`); a conflict is
  reported as an extension error (`resource-loader.ts:1238-1274`). Extension/SDK tools **override built-in
  tools of the same name** (`agent-session.ts:3478-3482`; `examples/extensions/tool-override.ts`).
- **Commands**: duplicates are all kept and renamed `name:1`, `name:2`, ... (`runner.ts:798-832`).
- **Skills / prompt templates / themes**: first discovered name wins, a `collision` diagnostic is recorded
  (`skills.ts:421-450`, `resource-loader.ts:1148-1199`).
- **Shortcuts**: a key bound to a *reserved* built-in action (interrupt, clear, exit, submit, ...) cannot
  be taken by an extension; other built-in keys can be overridden with a warning; between extensions the
  last one wins (`runner.ts:95-137, 672-715`).

### 2.3 Lifecycle (startup and one run)

Startup (VERIFIED: `resource-loader.ts:497-666`, `project-trust.ts`, `agent-session.ts:3173-3197`):

1. Load user settings. Project settings are **not** applied yet (`setProjectTrusted(false)`), except
   `sessionDir`, which the CLI reads before trust resolution (`docs/configuration.md`, `docs/security.md`).
2. **Pre-trust pass**: load user-level + CLI + inline extensions (not built-ins).
3. **Resolve project trust** (section 2.17). Only the extensions from step 2 can handle `project_trust`.
4. Reload settings with the trust state; `packageManager.resolve()` (installs missing packages if allowed).
5. Load the remaining extensions (already loaded ones are reused, failed ones are not retried), then
   built-in extensions, then inline factories; remove replaced `replaceable` extensions; record conflicts.
6. Load skills, prompt templates, themes; load context files; resolve `SYSTEM.md` / `APPEND_SYSTEM.md`.
7. `createAgentSession()` builds the tool registry and `runner.bindCore()` flushes queued provider /
   virtual-model registrations.
8. The mode calls `session.bindExtensions({uiContext, mode, commandContextActions, onError, ...})`, which
   emits `session_start` (`reason: "startup"`), then reports unhandled MCP registrations, then emits
   `resources_discover` and merges the returned skill/prompt/theme paths.

One user prompt (VERIFIED: `agent-session.ts:1883-2026`, `$PI/packages/agent/src/agent-loop.ts:535-560, 707-776`, `runner.ts`):

```
text typed / prompt()
  1. "/name ..." and an extension command exists -> run handler, STOP (disposition "handled")
  2. input event (continue | transform | handled)
  3. /skill:name expansion, then prompt-template expansion
  4. if a run is active: queue as steer or followUp (must be specified), STOP (disposition "queued")
  5. before_agent_start  (collect injected messages; system prompt edits)
  6. agent_start
     repeat per turn:
       turn_start
       context -> context_with_system            (message transforms)
       before_provider_headers, before_provider_request
       after_provider_response, provider_stream_event*
       message_start, message_update*, message_end   (assistant)
       for each tool call (parallel unless tool or config says sequential):
         tool_execution_start
         [argument preparation + schema validation]
         tool_call              (block / patch input)
         execute()              tool_execution_update*
         tool_result            (patch result)
         tool_execution_end
       turn_end                 (boundary: may append entries, may request one more model request)
  7. agent_end                  (one low-level run ended; retries/compaction/queued work may follow)
  8. agent_before_settle        (last actionable boundary)
  9. agent_settled              (notification only)
```

Note the order inside a tool call: `tool_execution_start` is emitted **before** validation and before the
`tool_call` hook (`agent-loop.ts:541-549`), so a blocked call still produces start/end events.

Shutdown / replacement: `session_shutdown` (`reason: "quit" | "reload" | "new" | "resume" | "fork"`).

### 2.4 Event dispatch semantics

| Semantics | Events | Rule | Evidence (`runner.ts`) |
|---|---|---|---|
| notify | `session_start`, `session_info_changed`, `session_compact`, `session_compact_failed`, `session_shutdown`, `session_tree`, `mcp_servers_change`, `agent_start`, `agent_end`, `agent_settled`, `turn_start`, `message_start`, `message_update`, `tool_execution_*`, `model_select`, `thinking_level_select`, `after_provider_response`, `provider_stream_event`, `ui_prompt_start/end`, `before_provider_headers` (mutates `headers` in place, return ignored) | every handler runs; errors are caught, reported via `emitError`, dispatch continues | 1080-1109, 1383-1409 |
| cancel | `session_before_switch`, `session_before_fork`, `session_before_compact`, `session_before_tree` | last non-empty result is kept; the first result with `cancel: true` returns immediately | 1080-1109 |
| block | `tool_call` | handlers may mutate `event.input` in place (no re-validation); first result with `block: true` returns immediately; **no try/catch**: a throwing handler propagates and the agent loop converts it into an error tool result, i.e. the tool is blocked (fail-safe) | 1233-1251; `agent-session.ts:617-640`; `agent-loop.ts:724-775` |
| patch chain | `tool_result` | each handler sees the result as modified by earlier handlers; fields `content`, `details`, `structuredContent`, `isError`, `usage` are replaced individually; replacing `content` without `structuredContent` drops the latter | 1174-1231 |
| transform chain | `input` | `transform` results chain (`text`, `images`); `handled` short-circuits; final result `continue` if nothing changed | 1511-1550 |
| transform chain | `context`, `context_with_system` | handlers may return `{messages}` or edit the array in place; for `context` Pi hides system messages and restores them afterwards | 1289-1350 |
| replace chain | `before_provider_request` | any non-`undefined` return value replaces the payload for the next handler | 1352-1381 |
| replace chain | `message_end` | returned `message` replaces the finalized message, must keep the same `role` | 1135-1172 |
| collect + override | `before_agent_start` | all returned `message`s are collected; `systemPrompt` sets `forceSystemPrompt` (later handlers see it); handlers may also mutate `event.systemPromptOptions` | 1411-1463 |
| boundary | `turn_end`, `agent_before_settle` | handlers chain `entries` and `continue`; invalid entries void the whole result | 1020-1069 |
| last wins | `cache_warming_decision` | last handler that returns `action` wins | 1111-1133 |
| first decision | `project_trust` | first handler returning `trusted: "yes" \| "no"` wins; `"undecided"` falls through | 294-321 |
| first handler | `user_bash` | first handler returning `{operations}` or `{result}` wins; a handler error **blocks the command** (rethrown) | 1253-1282 |
| collect | `resources_discover` | `skillPaths`, `promptPaths`, `themePaths` are concatenated | 1465-1508 |

### 2.5 Context objects

- `ExtensionContext` (every handler): `ui`, `mode`, `hasUI`, `cwd`, `sessionManager` (read-only),
  `modelRegistry`, `model`, `scopedModels`, `thinkingLevel`, `isIdle()`, `isProjectTrusted()`, `signal`,
  `abort()`, `hasPendingMessages()`, `shutdown()`, `getContextUsage()`, `compact()`, `getSystemPrompt()`
  (`types.ts:325-365`). Values are resolved lazily at access time (`runner.ts:868-946`). VERIFIED.
- `ExtensionToolContext` (tool `execute`): adds `tools` and `executeTool(name, args, options)`; nested calls
  get id `<parent id>/<n>`, pass through `tool_call`/`tool_result` hooks, never reject (failures come back as
  `isError: true`) (`types.ts:383-395`, `agent-session.ts:689-723`). VERIFIED.
- `ExtensionCommandContext` (command handlers only): adds `getSystemPromptOptions()`, `waitForIdle()`,
  `newSession()`, `fork()`, `navigateTree()`, `switchSession()`, `reload()`. These are command-only because
  calling them from lifecycle handlers can deadlock (`types.ts:401-435`, `docs/extensions.md`). VERIFIED.
- `ProjectTrustContext`: only `cwd`, `mode`, `hasUI` and `ui.{select,confirm,input,notify}` (`types.ts:673-678`). VERIFIED.

### 2.6 UI methods and behaviour per mode

`ExtensionUIContext` (`types.ts:149-300`). Dialogs: `select`, `confirm`, `input`, `editor`, `custom`.
Fire-and-forget: `notify`, `setStatus`, `setWidget`, `setTitle`, `setEditorText`, `pasteToEditor`,
`setWorkingMessage/Visible/Indicator`, `setHiddenThinkingLabel`, `setFooter`, `setHeader`. Others:
`onTerminalInput`, `getEditorText`, `addAutocompleteProvider`, `setEditorComponent`, themes,
`getToolsExpanded/setToolsExpanded`.

| Mode | `ctx.mode` | `ctx.hasUI` | Dialogs |
|---|---|---|---|
| interactive | `"tui"` | true | full |
| rpc | `"rpc"` | true | `select/confirm/input/editor` forwarded as `extension_ui_request`; `custom()` returns `undefined`; many setters are no-ops (`rpc-mode.ts:138-317`) |
| json | `"json"` | false | no-op UI: `select -> undefined`, `confirm -> false`, `input -> undefined` (`runner.ts:323-354`) |
| print | `"print"` | false | same no-op UI |

Dialog options: `{ signal?: AbortSignal, timeout?: number }`; on timeout/abort the dialog resolves to the
default (`undefined` / `false`) (`types.ts:114-119`, `rpc-mode.ts:93-135`). Dialogs are wrapped so that
`ui_prompt_start` / `ui_prompt_end` events fire around the outermost open dialog (`runner.ts:569-614`). VERIFIED.

Design lesson: every example checks `ctx.hasUI` (or `ctx.mode === "tui"` for custom components) and
**fails closed** when there is no UI (`permission-gate.ts`: "Dangerous command blocked (no UI for confirmation)").

### 2.7 Tools

- `ToolDefinition` fields: `name`, `label`, `description`, `promptSnippet`, `promptGuidelines`,
  `parameters` (TypeBox/JSON Schema object), `constrainedSampling`, `renderShell`, `prepareArguments`,
  `outputSchema`, `exposure`, `namespace`, `annotations`, `defaultActive`, `prepareLoadout`,
  `executionMode` (`"sequential" | "parallel"`), `execute(toolCallId, params, signal, onUpdate, ctx)`,
  `renderCall`, `renderResult` (`types.ts:560-640`). VERIFIED.
- Result: `{ content: (Text|Image)[], details, structuredContent?, usage?, isError?, terminate? }`
  (`$PI/packages/agent/src/types.ts:423-446`). Throwing from `execute` produces an error result; returning
  `isError: true` reports failure but keeps `details`. `terminate: true` ends the run without a follow-up
  model call only if **every** tool result in the batch sets it (`agent-loop.ts:690`). VERIFIED.
- Exposure: `direct` (default) | `model-only` | `codemode` | `deferred` | `hidden`; "active tools" = tools
  declared to the model; tools cannot be unregistered, only re-registered as `hidden` (`types.ts:494-509`, `docs/extensions.md`). VERIFIED.
- Annotations (MCP semantics): `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`; defaults
  when missing: not read-only, possibly destructive, open world. The documented approval rule is
  `destructiveHint === true || (!readOnlyHint && ((destructiveHint ?? true) || (openWorldHint ?? true)))`
  (`docs/extensions.md` "Tool exposure"). VERIFIED (doc + `types.ts:511-524`).
- System-prompt contribution: a custom tool appears in the "tools" section only if it has a
  `promptSnippet`; `promptGuidelines` are appended to the rules while the tool is active
  (`system-prompt.ts:81-118, 148-152`). VERIFIED.
- State storage guidance (`docs/extensions.md` "State"): branch-following tool state in tool-result
  `details`; durable non-context data via `appendEntry`; context-visible custom content via `sendMessage`.
  `todo.ts` rebuilds its list from `ctx.sessionManager.getBranch()` on `session_start` and `session_tree`. VERIFIED.

### 2.8 Commands, shortcuts, flags

- `registerCommand(name, { description?, getArgumentCompletions?, handler(args: string, ctx) })`
  (`types.ts:1512-1518, 1623`). Commands run immediately, even while the agent is streaming; they cannot be
  queued (`agent-session.ts:2186-2193`). A handler error is reported and the input is still considered
  handled (`agent-session.ts:2031-2055`). VERIFIED.
- `registerShortcut(key, { description?, handler(ctx) })` (`types.ts:1626-1632`). TUI only.
- `registerFlag(name, { type: "boolean" | "string", default?, description? })` + `getFlag(name)`; flags
  become CLI options `--name` shown in `pi --help`; `getFlag` only returns flags registered by the same
  extension (`loader.ts:322-363`). VERIFIED.

### 2.9 Message injection and persistence

- `sendMessage({customType, content, display, details}, {triggerTurn?, deliverAs?: "steer" | "followUp" | "nextTurn"})`
  (`types.ts:1671-1674`). Four cases (`agent-session.ts:2195-2244`): `nextTurn` = held until the next user
  prompt; streaming and `triggerTurn !== false` = queued as steer (default) or follow-up; idle +
  `triggerTurn` = starts a run; idle without trigger = appended to the session only; streaming +
  `triggerTurn: false` = appended after the current turn. VERIFIED.
- `sendUserMessage(content, {deliverAs?, expandPromptTemplates?})` always triggers a turn; while streaming
  `deliverAs` is required (`types.ts:1681-1684`, `examples/extensions/send-user-message.ts`). VERIFIED.
- Steering messages are delivered after the current assistant turn and its tool calls; follow-ups after the
  run has finished its pending work (`docs/sdk.md` "Prompting"). Settings `steeringMode` / `followUpMode`
  choose `"all"` or `"one-at-a-time"` (default). VERIFIED (doc + `settings-manager.ts:828-846`).
- `appendEntry(customType, data)` writes a `custom` session entry that never reaches the model and emits
  `entry_appended` (`agent-session.ts:3321-3327`). VERIFIED.
- `before_agent_start` may return `{ message }` (custom message stored and sent with the prompt) and/or
  `{ systemPrompt }` (whole-prompt replacement for this run). Preferred: mutate
  `event.systemPromptOptions` (sections, guidelines, selected tools) so that Pi can append a transcript
  delta instead of invalidating the prompt cache (`docs/extensions.md`). VERIFIED.

### 2.10 Providers, virtual models, classifier (Jev) access

- `registerProvider(name, ProviderConfig)` supports `baseUrl`, `apiKey` (literal, `$ENV`, `${ENV}`, or
  leading `!command`), `api`, `headers`, `authHeader`, `models[]`, `refreshModels()`, `oauth{...}`,
  `streamSimple()`, `images`, `classifiers` (`types.ts:1871-1927`). Model config types: chat, image,
  classifier (`types.ts:1929-1982`). VERIFIED.
- `registerVirtualModel({provider, id, name, thinkingLevels, contextWindow, maxTokens, route(request, ctx)})`
  routes each request to a physical model; router state is stored on the session branch
  (`types.ts:1842-1854`). VERIFIED.
- The shipped example `examples/extensions/jev-router.ts` calls TypeSafe Jev through
  `ctx.modelRegistry.classify(jev, { state: {prompt}, questions: { complexity: { type: "choice",
  instructions, criteria: {standard, complex} } } })` and reads
  `result.answers.complexity.probabilities.complex`. This is the only System-1 usage inside Pi's extension
  surface and confirms that Pi already treats Jev as a "classifier" model type reachable from extensions. VERIFIED (file read; not executed).

### 2.11 Discovery directories (global vs project)

Agent directory `<agent-dir>` = `$PI_CODING_AGENT_DIR` or `~/.pi/agent` (`$CA/src/config.ts:530-561`).
Project directory = `<cwd>/.pi` (name configurable through `package.json` `piConfig.configDir`). VERIFIED.

| Resource | User (global) | Project (trust-gated) | Other |
|---|---|---|---|
| settings | `<agent-dir>/settings.json` | `.pi/settings.json` | |
| MCP servers | `<agent-dir>/mcp.json` | `.pi/mcp.json` | `pi.registerMcpServer()` |
| extensions | `<agent-dir>/extensions/` | `.pi/extensions/` | settings `extensions`, `-e`, packages |
| skills | `<agent-dir>/skills/`, `~/.agents/skills/` | `.pi/skills/`, `.agents/skills/` in cwd and every ancestor up to the git root (or filesystem root when no repo) | settings `skills`, `--skill`, packages, `resources_discover` |
| prompt templates | `<agent-dir>/prompts/` (direct `.md` children only) | `.pi/prompts/` | settings `prompts`, `--prompt-template`, packages |
| themes | `<agent-dir>/themes/` | `.pi/themes/` | |
| system prompt | `<agent-dir>/SYSTEM.md`, `APPEND_SYSTEM.md` | `.pi/SYSTEM.md`, `.pi/APPEND_SYSTEM.md` (project file wins, files are not combined) | `--system-prompt`, `--append-system-prompt` |
| context files | `<agent-dir>/{AGENTS.override.md, AGENTS.md, AGENTS.MD, CLAUDE.md, CLAUDE.MD}` | same names in cwd and **every ancestor** (not trust-gated) | `--no-context-files` |
| keybindings | `<agent-dir>/keybindings.json` | - | |
| credentials / models | `<agent-dir>/auth.json`, `models.json` | - | |
| trust store | `<agent-dir>/trust.json` | - | |
| installed packages | `<agent-dir>/npm/node_modules/<name>`, `<agent-dir>/git/<host>/<path>` | `.pi/npm/...`, `.pi/git/...` | temporary: `<agent-dir>/tmp/extensions/<prefix>/<hash>/...` (mode 0700) |

Evidence: `docs/configuration.md`; `package-manager.ts:2085-2184, 2413-2577`; `resource-loader.ts:184-270, 1201-1227`. VERIFIED.

### 2.12 Skills

- **Discovery rules** (`skills.ts:160-275`, `package-manager.ts:371-448`): if a directory contains
  `SKILL.md` it is a skill root and recursion stops; otherwise recurse into sub-directories (skipping
  names starting with `.` and `node_modules`, honouring ignore files). Additionally, in "pi" mode direct
  `*.md` children of the scan **root** are accepted as standalone skills; in "agents" mode
  (`.agents/skills`) `*.md` files in *sub-directories* (not the root) are accepted. Symlinks are followed;
  the same real file reached twice is loaded once. VERIFIED.
  Pi's own repository uses the standalone form: `$PI/.pi/skills/release.md`, `add-llm-provider.md`,
  `interactive-testing.md`. VERIFIED.
- **Validation** (`skills.ts:88-127, 277-345`): name = frontmatter `name` or parent directory name;
  `^[a-z0-9-]+$`, max 64 chars, no leading/trailing/consecutive hyphen; description required, max 1024
  chars. All violations are *warnings*; the skill still loads **unless the description is missing/empty or
  the YAML cannot be parsed**. Pi does not warn when the name differs from the directory name
  (`docs/skills.md`), although the spec requires equality. VERIFIED.
- **Frontmatter parsing** (`$CA/src/utils/frontmatter.ts`): strip BOM, normalise CRLF/CR to LF, the text
  must start with `---`, the block ends at the first `"\n---"`; body is trimmed; YAML parsed by the `yaml`
  npm package; empty YAML gives `{}`. VERIFIED.
- **Pi-specific frontmatter key**: `disable-model-invocation: true` hides the skill from the catalog; it
  stays available as `/skill:name` (`skills.ts:341, 355-360`). Other keys (`license`, `compatibility`,
  `metadata`, `allowed-tools`) are parsed by the YAML parser but never read: `SkillFrontmatter`
  (`skills.ts:67-72`) names only `name`, `description`, `disable-model-invocation`, everything else falls
  under an index signature, and no source file references `allowed-tools`. VERIFIED.
- **Catalog in the system prompt**: section `<skills>` containing the text in section 3.6; only emitted
  when the `read` (or `bash`) tool is active (`system-prompt.ts:165-169`). VERIFIED.
- **Explicit invocation**: `/skill:name args` is replaced by
  `<skill name="..." location="...">\nReferences are relative to <baseDir>.\n\n<body>\n</skill>` followed by
  a blank line and the args (`agent-session.ts:2062-2086`). Setting `enableSkillCommands` only controls
  whether skill commands are *listed* in completion; typed commands always work (`docs/skills.md`). VERIFIED.
- **Standards cross-check** (VERIFIED by fetching the pages on 2026-09-29):
  - agentskills.io specification: `name` (required, 1-64, must match directory), `description` (required,
    1-1024), `license`, `compatibility` (max 500), `metadata` (string map), `allowed-tools`
    (space-separated string, experimental); recommended `SKILL.md` < 500 lines / < 5000 tokens.
  - agentskills.io integration guide: scan `<project>/.<client>/skills`, `<project>/.agents/skills`,
    `~/.<client>/skills`, `~/.agents/skills`; "Some implementations also scan `.claude/skills/`"; bounds
    "max depth of 4-6 levels, max 2000 directories"; project overrides user; lenient validation; quote-repair
    fallback for unquoted values containing colons; hide filtered skills; omit the catalog when empty;
    protect skill content from compaction; de-duplicate activations.
  - Claude Code: enterprise (managed dir) > personal `~/.claude/skills/<name>/SKILL.md` > project
    `.claude/skills/<name>/SKILL.md` (note: **personal beats project**, the opposite of Pi and of the
    agentskills.io convention); plugin skills are namespaced `plugin:skill`; extra frontmatter keys
    `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`,
    `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`,
    `paths`, `shell`; description + `when_to_use` truncated at 1,536 characters in the listing;
    substitutions `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N` (0-based!), `${CLAUDE_SKILL_DIR}`,
    `${CLAUDE_SESSION_ID}`, `${CLAUDE_PROJECT_DIR}`; `.claude/commands/*.md` are equivalent to skills.
  - Codex: `$CWD/.agents/skills`, parents up to `$REPO_ROOT/.agents/skills`, `$HOME/.agents/skills`,
    `/etc/codex/skills`, bundled; optional `agents/openai.yaml`
    (`interface.*`, `policy.allow_implicit_invocation`, `dependencies.tools`); explicit invocation `$skill-name`.
    The development machine nevertheless has a populated `~/.codex/skills` (legacy or tool-managed location). VERIFIED (`ls`).
  - btw (R): `.btw/skills`, `.agents/skills`, `~/.btw/skills`, `~/.config/btw/skills`,
    `tools::R_user_dir("btw")/skills`, and `inst/skills/` of **attached** packages
    (`attached_package_skill_dirs()` iterates `.packages()` with `system.file("skills", package = pkg)`);
    a dedicated tool `btw_tool_skill` returns the skill text.

### 2.13 Prompt templates

- A template is a `.md` file; command name = file name without `.md`
  (`prompt-templates.ts:129`). Conventional directories load **direct children only** (non-recursive)
  (`prompt-templates.ts:156-198`); settings/packages may point at nested files. VERIFIED.
- Frontmatter: `description` (fallback: first non-empty body line, truncated to 60 chars + `...`),
  `argument-hint` (`<required>` / `[optional]` by convention). No other key is read
  (`prompt-templates.ts:131-153`). VERIFIED.
- Expansion happens only if the whole input matches `^\/([^\s]+)(?:\s+([\s\S]*))?$` and a template of that
  name exists; otherwise the text passes through unchanged (`prompt-templates.ts:304-320`). VERIFIED.
- Arguments are split on whitespace with `'...'` and `"..."` quoting; **no backslash escapes**; an empty
  quoted string produces no argument (`parseCommandArgs`, `prompt-templates.ts:25-56`). VERIFIED + tested.
- Substitution is a single regex pass over the template; argument values and defaults are **not**
  re-scanned (`prompt-templates.ts:59-103`). VERIFIED + tested.
- Pi's own templates (`$PI/.pi/prompts/*.md`) use exactly `description`, `argument-hint`, `$@`, `$ARGUMENTS`. VERIFIED.

### 2.14 Context files and system prompt assembly

- Per directory the first existing candidate wins, in this order: `AGENTS.override.md`, `AGENTS.md`,
  `AGENTS.MD`, `CLAUDE.md`, `CLAUDE.MD` (`resource-loader.ts:184-203`). So an override file replaces
  `AGENTS.md`/`CLAUDE.md` only in its own directory. VERIFIED.
- Order in the prompt: agent-dir file first, then ancestors from the filesystem root down to cwd
  (`resource-loader.ts:232-270`). In a linked git worktree nested inside the main checkout, the main
  checkout's file is skipped when the worktree has its own (`findShadowedContextFile`, 205-230). VERIFIED.
- The system prompt is built from ordered sections (`system-prompt.ts:121-180`): `preamble` (untagged),
  then XML-tagged `tools`, `rules`, `docs`, `addendum` (APPEND_SYSTEM / `--append-system-prompt`),
  `project_context`, `skills`, `cwd`, then extension-defined custom sections. With a custom prompt
  (`SYSTEM.md` / `--system-prompt`) `tools`, `rules`, `docs` are omitted. Section names must match
  `^[a-z][a-z0-9_-]*$` and must not be `preamble`. Context files are rendered as
  `<project_instructions path="...">\n...\n</project_instructions>`. `cwd` uses forward slashes even on
  Windows (`cwd.replace(/\\/g, "/")`). VERIFIED.
- Default rules always end with "Be concise in your responses" and "Show file paths clearly when working
  with files"; when only shell tools are active the rule "Use bash for file operations like ls, rg, find"
  is added (`system-prompt.ts:81-118`). VERIFIED.

### 2.15 Settings

See section 3.8 for the complete key list. Behaviour (VERIFIED, `settings-manager.ts`):

- Files are plain JSON (BOM stripped). A parse error is recorded as a diagnostic, the scope is treated as
  empty, and **the broken file is never overwritten** (`save()` returns early when a load error exists, 734-748).
- Writes are *field-level merges*: the file is re-read under a lock and only the fields modified during
  this session are replaced (703-732). Lock: `proper-lockfile`, 10 attempts x 20 ms (302-327).
- Project settings are ignored (treated as `{}`) while the project is untrusted, and writing them throws
  (`"Project is not trusted; refusing to write project settings"`, 660-664).
- Migrations of legacy keys: `queueMode -> steeringMode`, `websockets -> transport`,
  `skills: {enableSkillCommands, customDirectories} -> enableSkillCommands + skills[]`,
  `retry.maxDelayMs -> retry.provider.maxRetryDelayMs` (502-561).
- Resource paths in user settings resolve from the agent directory, in project settings from `.pi`
  (`docs/settings.md`, `package-manager.ts:938-967`).
- Precedence overall: CLI flags > project settings (trusted) > user settings > built-in defaults; the SDK
  can add `applyOverrides()` on top of the merged view (633-636).

### 2.16 Packages

- Sources (`package-manager.ts:1480-1505`, `$CA/src/utils/git.ts`, `$CA/src/utils/paths.ts:50-65`):
  `npm:<spec>` (exact version = pinned); `git:<host>/<path>[@ref]`, `https://`, `http://`, `ssh://`,
  `git://` URLs, `git@host:path` (with `git:` prefix) - a ref pins the package; anything else is a local
  path (file = single extension, directory = package). Git paths are validated against `..`, backslashes,
  NUL and absolute paths. VERIFIED.
- Identity for de-duplication: npm name; git `host/path` without ref; local absolute path. A project
  entry replaces the user entry of the same identity; with `autoload: false` it is a filtering delta
  (`docs/packages.md`, `package-manager.ts:1407-1428`). VERIFIED.
- Resource selection inside a package (`package-manager.ts:2214-2263`): (1) settings object-form filter if
  present; (2) else `package.json` `"pi"` manifest; (3) else conventional directories `extensions/`,
  `skills/`, `prompts/`, `themes/`.
- Filter grammar (`package-manager.ts:745-791`): plain entries = include globs; `!pattern` = exclude glob;
  `+path` = force-include exact path; `-path` = force-exclude exact path; order of application:
  includes, excludes, force-includes, force-excludes. Globs are matched against the path relative to the
  base, the base name, and the absolute path; for `SKILL.md` also against the skill directory. `[]` = load
  nothing of that type; property omitted = load everything. VERIFIED.
- Dependencies: runtime deps in `dependencies` are installed by npm; host-provided packages
  (`@earendil-works/pi-ai`, `pi-agent-core`, `pi-coding-agent`, `pi-tui`, `typebox`) must be
  `peerDependencies` with `"*"`; Pi warns otherwise (`resource-loader.ts:53-97`). VERIFIED.
- CLI: `pi install|remove|uninstall|update|list|config`, `-l/--local` for project scope,
  `pi -e npm:...` for a temporary install (`docs/cli.md`). Project installs require trust
  (`assertProjectTrustedForScope`). VERIFIED.
- A newer, experimental "plugin" mechanism (`examples/plugins/pi-example-plugin`, Chord facets
  `src/session.ts` / `src/tui.ts`, `PI_EXPERIMENTAL=1`) exists for the client/server architecture. It is
  out of scope for gptr. VERIFIED (README read).

### 2.17 Project trust

- Trigger (`trust-manager.ts:26-35, 187-208`): any of `.pi/settings.json`, `.pi/mcp.json`,
  `.pi/extensions`, `.pi/skills`, `.pi/prompts`, `.pi/themes`, `.pi/SYSTEM.md`, `.pi/APPEND_SYSTEM.md`
  exists in **cwd**, or a `.agents/skills` directory exists in cwd or any ancestor (excluding
  `~/.agents/skills`). A bare `.pi` directory does not trigger. VERIFIED.
- Resolution order (`project-trust.ts:47-96`): (1) `trustOverride` (`--approve` / `--no-approve`);
  (2) nothing to gate -> trusted; (3) `project_trust` event, first yes/no wins, `remember: true` persists;
  (4) saved decision for cwd or the nearest ancestor; (5) `defaultProjectTrust` `always` / `never`;
  (6) no UI -> **not trusted**; (7) prompt. VERIFIED.
- Prompt text and options: see section 3.10. "Trust parent folder" stores `true` for the parent and
  deletes the entry for cwd. VERIFIED (`trust-manager.ts:64-95`).
- Store: `<agent-dir>/trust.json`, a JSON object `{ "<canonical absolute path>": true | false }`, keys
  sorted, written under a lock file `trust.json.lock` (`trust-manager.ts:97-184, 210-246`). VERIFIED.
- Trust is *not* a sandbox: it only decides which project resources load; context files and tool calls are
  unaffected (`docs/security.md`). VERIFIED (doc).

### 2.18 Slash commands

Built-ins (24) are listed in section 3.11. Two more are contributed by built-in extensions (`/mcp`,
`/llama`), and three undocumented ones are handled by the TUI (`/debug`, `/arminsayshi`,
`/dementedelves`; `interactive-mode.ts:3217-3231`). Built-in commands are matched by exact string or
prefix + space in the TUI's submit handler and are therefore **not available in print/json/rpc modes**;
RPC exposes equivalent typed commands instead (`rpc-types.ts`). `get_commands` / `pi.getCommands()` return
only extension, prompt and skill commands (`agent-session.ts:3276-3299`). VERIFIED.

### 2.19 Run modes

| Mode | Start | Input | Output | Ends | Extension UI |
|---|---|---|---|---|---|
| interactive | `pi` on a TTY | editor | TUI | user quits | full |
| print | `pi -p "..."` or any redirected stdin/stdout | argv messages, `@file`, piped stdin (prepended to first prompt) | text blocks of the **last assistant message** on stdout; errors on stderr; exit 1 when the last message has `stopReason` `error`/`aborted` | after prompts | none |
| json | `pi --mode json "..."` | argv messages | JSONL: session header `{"type":"session","version":3,"id","timestamp","cwd"}` then every session event; failed runs do **not** change the exit code | after prompts | none |
| rpc | `pi --mode rpc` | JSONL commands on stdin | JSONL `response` records + session events + `extension_ui_request` on stdout; diagnostics on stderr | stdin closed | dialogs via sub-protocol |
| sdk | `createAgentSession()` | `session.prompt()`, `steer()`, `followUp()`, `abort()` | `session.subscribe(event => ...)` with cumulative snapshots | `session.dispose()` | host-provided `uiContext` via `bindExtensions` |

Evidence: `$CA/src/modes/print-mode.ts`, `json-event.ts`, `rpc/rpc-mode.ts`, `rpc/rpc-types.ts`,
`docs/cli.md`, `docs/cli-integration.md`, `docs/json.md`, `docs/rpc.md`, `docs/sdk.md`. VERIFIED.

Important details:

- JSON/RPC `message_update` records are **delta-only**: the cumulative `message` and
  `assistantMessageEvent.partial` are removed; `toolcall_start` gains `id` and `toolName`
  (`json-event.ts:23-61`). VERIFIED.
- Framing is strict JSONL split on LF only (U+2028/U+2029 are valid inside strings) (`docs/json.md`). VERIFIED.
- In RPC a successful `prompt` response only means accepted (`data.disposition`: `"started"`, `"queued"`,
  `"handled"`); completion is signalled by `agent_settled` (`docs/rpc.md`). VERIFIED.
- SDK sessions do not load the built-in `codemode`, `tool_search`, MCP extensions unless the host adds
  them, and `session.bindExtensions()` must be called for `session_start` to fire (`docs/sdk.md`). VERIFIED.

### 2.20 What the example extensions teach

| Example | Mechanism | Hooks / API used |
|---|---|---|
| `permission-gate.ts` | regex list over `event.input.command`; `ctx.ui.select(..., ["Yes","No"])`; block when no UI | `tool_call`, `ctx.hasUI`, `ctx.ui.select` |
| `protected-paths.ts` | substring match on `event.input.path` for `write`/`edit` | `tool_call`, `ctx.ui.notify` |
| `confirm-destructive.ts` | confirm before new/resume/fork | `session_before_switch`, `session_before_fork`, `{cancel: true}` |
| `plan-mode/` | removes `edit`/`write` from active tools; bash allowlist + denylist; injects hidden context message; filters it out again when plan mode is off; extracts numbered steps after `Plan:`; asks "Execute / Stay / Refine"; tracks `[DONE:n]` | `registerFlag("plan")`, `registerCommand("plan"/"todos")`, `registerShortcut`, `getActiveTools/setActiveTools`, `tool_call`, `context`, `before_agent_start`, `turn_end`, `agent_end`, `session_start`, `sendMessage({triggerTurn, deliverAs:"followUp"})`, `sendUserMessage`, `appendEntry`, `ctx.ui.select/editor/notify/setStatus/setWidget` |
| `question.ts`, `questionnaire.ts` | model-callable tool that renders a custom TUI component; returns error text when `ctx.mode !== "tui"`; `executionMode: "sequential"` | `registerTool`, `ctx.ui.custom`, result `details` |
| `qna.ts`, `handoff.ts` | command that makes a side model call (`ctx.modelRegistry.complete`) and puts the result into the editor / a new session | `registerCommand`, `ctx.sessionManager.getBranch()`, `ctx.newSession({withSession})`, `ctx.ui.editor`, `setEditorText` |
| `todo.ts` | tool with `list/add/toggle/clear`; full state snapshot in every result's `details`; rebuild on `session_start`/`session_tree` | `registerTool`, `registerCommand`, `ctx.sessionManager.getBranch()` |
| `tool-override.ts` | re-registers `read` with auditing and path blocking | `registerTool` (same name as built-in) |
| `tools.ts` | `/tools` selector persisted with `appendEntry` | `getAllTools`, `setActiveTools`, `appendEntry` |
| `dynamic-tools.ts` | registers tools in `session_start` and from a command at runtime | `registerTool` after bind |
| `commands.ts` | lists commands, argument completion | `getCommands`, `getArgumentCompletions` |
| `input-transform.ts` | `?quick` prefix rewrite; `ping` handled without model | `input` |
| `preset.ts` | named presets (model, thinking level, tools, instructions) from `presets.json` | `registerFlag`, `setModel`, `setThinkingLevel`, `setActiveTools`, `before_agent_start` |
| `custom-compaction.ts` | replaces the summariser with another model | `session_before_compact` returning `{compaction}` |
| `structured-output.ts` | final answer as a tool call with `terminate: true` | `registerTool`, `defineTool` |
| `claude-rules.ts` | lists `.claude/rules/*.md` in the system prompt | `session_start`, `before_agent_start` returning `systemPrompt` |
| `project-trust.ts` | custom trust dialog | `project_trust` |
| `jev-router.ts` | classifier-driven model routing | `registerVirtualModel`, `modelRegistry.classify` |
| `custom-provider-anthropic/` | full provider with OAuth and custom `streamSimple` (617 lines) | `registerProvider` |

All VERIFIED by reading the files under `$CA/examples/extensions/`.

Weaknesses of Pi's examples that gptr should not copy:

- The permission gate and plan mode rely on **regular expressions over shell text**; the plan-mode
  allowlist accepts `curl ...` and any `awk`/`echo` invocation. gptr can do better because its execution
  tool receives R code that can be parsed (section 5.6).
- `question.ts` returns a normal (non-error) result when no UI exists, so the model may read "Error: UI not
  available" as an answer. gptr should return `is_error = TRUE` with an instruction to proceed on a stated
  assumption.
- Plan extraction from free text (`Plan:` header + numbered list) is fragile; a `todo`/`plan` tool with
  structured arguments is more robust.

---

## 3. Exact specifications

Everything in this section is copied from the Pi source at the commit named above unless stated otherwise.

### 3.1 Event catalogue (41 events): payload and allowed handler result

Handler signature for all events except `project_trust`:
`(event, ctx: ExtensionContext) => Promise<R | void> | R | void` (`types.ts:1530`).

| # | Event | Payload fields (besides `type`) | Handler may return |
|---|---|---|---|
| 1 | `project_trust` | `cwd` | `{ trusted: "yes" \| "no" \| "undecided", remember?: boolean }` (required); ctx is `ProjectTrustContext` |
| 2 | `resources_discover` | `cwd`, `reason: "startup" \| "reload"` | `{ skillPaths?: string[], promptPaths?: string[], themePaths?: string[] }` |
| 3 | `session_start` | `reason: "startup" \| "reload" \| "new" \| "resume" \| "fork"`, `previousSessionFile?` | - |
| 4 | `session_info_changed` | `name: string \| undefined` | - |
| 5 | `session_before_switch` | `reason: "new" \| "resume"`, `targetSessionFile?` | `{ cancel?: boolean }` |
| 6 | `session_before_fork` | `entryId`, `position: "before" \| "at"` | `{ cancel?: boolean, skipConversationRestore?: boolean }` |
| 7 | `session_before_compact` | `preparation: CompactionPreparation`, `branchEntries`, `customInstructions?`, `reason: "manual" \| "threshold" \| "overflow"`, `willRetry`, `signal` | `{ cancel?: boolean, compaction?: CompactionResult }` |
| 8 | `session_compact` | `compactionEntry`, `fromExtension`, `reason`, `willRetry` | - |
| 9 | `session_compact_failed` | `reason`, `errorMessage?`, `aborted`, `willRetry`, `fromExtension` | - |
| 10 | `session_shutdown` | `reason: "quit" \| "reload" \| "new" \| "resume" \| "fork"`, `targetSessionFile?` | - |
| 11 | `mcp_servers_change` | `servers: RegisteredMcpServer[]` | - |
| 12 | `session_before_tree` | `preparation: TreePreparation {targetId, oldLeafId, commonAncestorId, entriesToSummarize, userWantsSummary, customInstructions?, replaceInstructions?, label?}`, `signal` | `{ cancel?, summary?: {summary, details?, usage?}, customInstructions?, replaceInstructions?, label? }` |
| 13 | `session_tree` | `newLeafId`, `oldLeafId`, `summaryEntry?`, `fromExtension?` | - |
| 14 | `context` | `messages: AgentMessage[]` (without system messages) | `{ messages?: AgentMessage[] }` (or mutate in place) |
| 15 | `context_with_system` | `messages: AgentMessage[]` (full transcript, system message at index 0) | `{ messages?: AgentMessage[] }` |
| 16 | `cache_warming_decision` | `warmCost`, `missCost`, `continuationProbability`, `action` | `{ action?: "warm" \| "stop" }` |
| 17 | `before_provider_request` | `payload: unknown` | replacement payload (any non-`undefined` value) |
| 18 | `before_provider_headers` | `headers: ProviderHeaders` (mutable; `null` value deletes a header) | ignored |
| 19 | `after_provider_response` | `status: number`, `headers: Record<string,string>` | - |
| 20 | `provider_stream_event` | `provider`, `api`, `model`, `data: unknown` (read-only) | - |
| 21 | `before_agent_start` | `prompt`, `images?`, `systemPrompt` (read-only getter), `systemPromptOptions` (mutable) | `{ message?: {customType, content, display, details?}, systemPrompt?: string }` |
| 22 | `agent_start` | - | - |
| 23 | `agent_end` | `messages: AgentMessage[]` | - |
| 24 | `agent_before_settle` | `entries: SessionBoundaryDraft[]`, `continue: boolean`, `context: BoundaryContextPreview`, `outcome: "completed" \| "aborted" \| "error"` | `{ entries?: SessionBoundaryDraft[], continue?: boolean }` |
| 25 | `agent_settled` | - | - |
| 26 | `ui_prompt_start` | `reason: "ui_prompt"`, `kind: "select" \| "confirm" \| "input" \| "editor" \| "custom"`, `title?` | - |
| 27 | `ui_prompt_end` | same as start | - |
| 28 | `turn_start` | `turnIndex`, `timestamp` | - |
| 29 | `turn_end` | boundary fields (as #24) + `turnIndex`, `message`, `toolResults: ToolResultMessage[]`, `messageEntryId`, `toolResultEntryIds` | `{ entries?, continue? }` |
| 30 | `message_start` | `message` | - |
| 31 | `message_update` | `message`, `assistantMessageEvent` | - |
| 32 | `message_end` | `message` | `{ message?: AgentMessage }` (same role) |
| 33 | `tool_execution_start` | `toolCallId`, `toolName`, `args`, `parentToolCallId?` | - |
| 34 | `tool_execution_update` | `toolCallId`, `toolName`, `args`, `partialResult`, `parentToolCallId?` | - |
| 35 | `tool_execution_end` | `toolCallId`, `toolName`, `result`, `isError`, `parentToolCallId?` | - |
| 36 | `model_select` | `model`, `previousModel`, `source: "set" \| "cycle" \| "restore"` | - |
| 37 | `thinking_level_select` | `level`, `previousLevel` | - |
| 38 | `tool_call` | `toolCallId`, `toolName`, `input` (mutable), `parentToolCallId?` | `{ block?: boolean, reason?: string, terminate?: boolean }` |
| 39 | `tool_result` | `toolCallId`, `toolName`, `input`, `content`, `details`, `structuredContent?`, `isError`, `usage?`, `parentToolCallId?` | `{ content?, details?, structuredContent?, isError?, usage? }` |
| 40 | `user_bash` | `command`, `excludeFromContext` (true for `!!`), `cwd` | `{ operations: BashOperations }` or `{ result: BashResult }` (exactly one) |
| 41 | `input` | `text`, `images?`, `source: "interactive" \| "rpc" \| "extension"`, `streamingBehavior?: "steer" \| "followUp"` | `{ action: "continue" }` or `{ action: "transform", text, images? }` or `{ action: "handled" }` |

`SessionBoundaryDraft` is one of (`types.ts:919-952`):

```typescript
{ type: "custom"; customType: string; data?: unknown }
{ type: "custom_message"; customType: string; content: string | (TextContent | ImageContent)[]; display: boolean; details?: unknown }
{ type: "context_edit"; targetId: string; replacement: ContextEditEntry["replacement"] }
{ type: "compaction"; summary: string; firstKeptEntryId: string | null; details?: unknown; usage?: Usage }
```

Default message used when a call is blocked without a reason: `"Tool execution was blocked"`; unknown tool:
`` `Tool ${toolCall.name} not found` ``; aborted: `"Operation aborted"` (`agent-loop.ts:719, 740, 745`).

### 3.2 `ExtensionAPI` (verbatim signatures, `types.ts:1535-1858`)

```typescript
on(event: "<name>", handler): () => void;                      // returns an unsubscribe function

registerTool<TParams extends TSchema = TSchema, TDetails = unknown, TState = any>(
    tool: ToolDefinition<TParams, TDetails, TState>): void;

registerCommand(name: string, options: Omit<RegisteredCommand, "name" | "sourceInfo">): void;
//   RegisteredCommand = { name; sourceInfo; description?: string;
//     getArgumentCompletions?: (argumentPrefix: string) => AutocompleteItem[] | null | Promise<AutocompleteItem[] | null>;
//     handler: (args: string, ctx: ExtensionCommandContext) => Promise<void> }

registerShortcut(shortcut: KeyId,
    options: { description?: string; handler: (ctx: ExtensionContext) => Promise<void> | void }): void;

registerFlag(name: string, options:
    | { description?: string; type: "boolean"; default?: boolean }
    | { description?: string; type: "string";  default?: string }): void;
getFlag(name: string): boolean | string | undefined;

registerMessageRenderer<T = unknown>(customType: string, renderer: MessageRenderer<T>): void;
registerMarkdownTransformer(transformer: MarkdownTransformer): void;
registerEntryRenderer<T = unknown>(customType: string, renderer: EntryRenderer<T>): void;

sendMessage<T = unknown>(
    message: Pick<CustomMessage<T>, "customType" | "content" | "display" | "details">,
    options?: { triggerTurn?: boolean; deliverAs?: "steer" | "followUp" | "nextTurn" }): void;
sendUserMessage(
    content: string | (TextContent | ImageContent)[],
    options?: { deliverAs?: "steer" | "followUp"; expandPromptTemplates?: boolean }): void;
appendEntry<T = unknown>(customType: string, data?: T): void;

setSessionName(name: string): void;
getSessionName(): string | undefined;
setLabel(entryId: string, label: string | undefined): void;

exec(command: string, args: string[], options?: ExecOptions): Promise<ExecResult>;
//   ExecOptions = { signal?: AbortSignal; timeout?: number /* ms */; cwd?: string }
//   ExecResult  = { stdout: string; stderr: string; code: number; killed: boolean }   (spawned with shell: false)

getActiveTools(): string[];
getAllTools(): ToolInfo[];       // {name, description, parameters, promptGuidelines, exposure, namespace?, annotations?, sourceInfo}
getSettings(): Settings;         // copy of the merged settings
setActiveTools(toolNames: string[]): void;      // unknown and hidden names are ignored
getCommands(): SlashCommandInfo[];              // {name, description?, source: "extension" | "prompt" | "skill", sourceInfo}

setModel(model: Model<any>): Promise<boolean>;  // false when the provider has no credentials
getThinkingLevel(): ThinkingLevel;
setThinkingLevel(level: ThinkingLevel): void;   // clamped to the model's capabilities

registerProvider(provider: Provider): void;
registerProvider(name: string, config: ProviderConfig): void;
unregisterProvider(name: string): void;

registerMcpServer(name: string, config: McpServerConfig): void;
unregisterMcpServer(name: string): void;
getMcpServers(): RegisteredMcpServer[];

registerVirtualModel<TState = unknown>(model: ExtensionVirtualModel<TState>): void;
unregisterVirtualModel(provider: string, id: string): void;

events: EventBus;   // { emit(channel: string, data: unknown): void; on(channel: string, handler: (data: unknown) => void): () => void }
```

`SourceInfo` = `{ path: string; source: string; scope: "user" | "project" | "temporary"; origin: "package" | "top-level"; baseDir?: string }` (`source-info.ts`).

`ThinkingLevel` values accepted by settings and CLI: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`.

### 3.3 Context interfaces (verbatim, `types.ts:323-452`)

```typescript
export type ExtensionMode = "tui" | "rpc" | "json" | "print";

export interface ExtensionContext {
  ui: ExtensionUIContext;
  mode: ExtensionMode;
  hasUI: boolean;                        // true in TUI and RPC modes
  cwd: string;
  sessionManager: ReadonlySessionManager;
  modelRegistry: ModelRegistry;
  model: Model<any> | undefined;
  scopedModels: readonly ScopedModel[];
  thinkingLevel?: ThinkingLevel;
  isIdle(): boolean;
  isProjectTrusted(): boolean;
  signal: AbortSignal | undefined;       // undefined when the agent is not streaming
  abort(): void;
  hasPendingMessages(): boolean;
  shutdown(): void;
  getContextUsage(): ContextUsage | undefined;   // { tokens: number | null; contextWindow: number; percent: number | null }
  compact(options?: CompactOptions): void;       // { customInstructions?; onComplete?; onError? }
  getSystemPrompt(): string;
}

export interface ExtensionToolContext extends ExtensionContext {
  readonly tools: readonly AgentTool[];
  executeTool(name: string, args: unknown, options?: ExecuteToolOptions): Promise<AgentToolCallOutcome>;
}

export interface ExtensionCommandContext extends ExtensionContext {
  getSystemPromptOptions(): BuildSystemPromptOptions;
  waitForIdle(): Promise<void>;
  newSession(options?: { parentSession?: string;
                         setup?: (sessionManager: SessionManager) => Promise<void>;
                         withSession?: (ctx: ReplacedSessionContext) => Promise<void> }): Promise<{ cancelled: boolean }>;
  fork(entryId: string, options?: { position?: "before" | "at";
                         withSession?: (ctx: ReplacedSessionContext) => Promise<void> }): Promise<{ cancelled: boolean }>;
  navigateTree(targetId: string, options?: { summarize?: boolean; customInstructions?: string;
                         replaceInstructions?: boolean; label?: string }): Promise<{ cancelled: boolean }>;
  switchSession(sessionPath: string,
                options?: { withSession?: (ctx: ReplacedSessionContext) => Promise<void> }): Promise<{ cancelled: boolean }>;
  reload(): Promise<void>;
}
```

### 3.4 Tool definition and result (verbatim excerpts)

```typescript
export type ToolExposure = "direct" | "model-only" | "codemode" | "deferred" | "hidden";

export interface ToolAnnotations {
  readOnlyHint?: boolean;      // does not modify its environment
  destructiveHint?: boolean;   // may delete or overwrite data (meaningful when not read-only)
  idempotentHint?: boolean;    // repeating the call has no further effect
  openWorldHint?: boolean;     // reaches external entities such as the web
}

export interface ToolDefinition<TParams extends TSchema = TSchema, TDetails = unknown, TState = any> {
  name: string;
  label: string;
  description: string;
  promptSnippet?: string;
  promptGuidelines?: string[];
  parameters: TParams;
  constrainedSampling?: false | ConstrainedSamplingConfig;
  renderShell?: "default" | "self";
  prepareArguments?: (args: unknown) => Static<TParams>;
  outputSchema?: TSchema;
  exposure?: ToolExposure;
  namespace?: ToolNamespace;            // { name: string; description?: string }
  annotations?: ToolAnnotations;
  defaultActive?: boolean;
  prepareLoadout?: (loadout: ToolLoadout) => ToolLoadoutChanges | undefined;
  executionMode?: ToolExecutionMode;    // "sequential" | "parallel"
  execute(toolCallId: string, params: Static<TParams>, signal: AbortSignal | undefined,
          onUpdate: AgentToolUpdateCallback<TDetails> | undefined,
          ctx: ExtensionToolContext): Promise<AgentToolResult<TDetails>>;
  renderCall?: (...) => Component;
  renderResult?: (...) => Component;
}

export interface AgentToolResult<T = JsonValue | undefined> {
  content: (TextContent | ImageContent)[];
  details: T;
  structuredContent?: JsonValue;
  usage?: Usage;
  isError?: boolean;
  terminate?: boolean;
}
```

Nested-call record limits (`docs/extensions.md`): arguments over 8 KiB per call or 32 KiB per tool result
are omitted; at most 256 nested calls are kept.

### 3.5 UI interface (dialog subset) and the RPC UI sub-protocol

```typescript
select(title: string, options: string[], opts?: ExtensionUIDialogOptions): Promise<string | undefined>;
confirm(title: string, message: string, opts?: ExtensionUIDialogOptions): Promise<boolean>;
input(title: string, placeholder?: string, opts?: ExtensionUIDialogOptions): Promise<string | undefined>;
editor(title: string, prefill?: string): Promise<string | undefined>;
notify(message: string, type?: "info" | "warning" | "error"): void;
setStatus(key: string, text: string | undefined): void;
setWidget(key: string, content: string[] | undefined, options?: { placement?: "aboveEditor" | "belowEditor" }): void;
setTitle(title: string): void;
setEditorText(text: string): void;
getEditorText(): string;
custom<T>(factory, options?): Promise<T>;                 // TUI only
// ExtensionUIDialogOptions = { signal?: AbortSignal; timeout?: number /* ms */ }
```

RPC records (`rpc-types.ts:245-296`):

```json
{"type":"extension_ui_request","id":"uuid-1","method":"select","title":"Allow dangerous command?","options":["Allow","Block"],"timeout":10000}
{"type":"extension_ui_request","id":"uuid-2","method":"confirm","title":"Clear session?","message":"All messages will be lost.","timeout":5000}
{"type":"extension_ui_request","id":"uuid-3","method":"input","title":"Enter a value","placeholder":"type something..."}
{"type":"extension_ui_request","id":"uuid-4","method":"editor","title":"Edit some text","prefill":"Line 1\nLine 2"}
{"type":"extension_ui_request","id":"uuid-5","method":"notify","message":"Command blocked by user","notifyType":"warning"}
{"type":"extension_ui_request","id":"uuid-6","method":"setStatus","statusKey":"my-ext","statusText":"Turn 3 running..."}
{"type":"extension_ui_request","id":"uuid-7","method":"setWidget","widgetKey":"my-ext","widgetLines":["Line 1"],"widgetPlacement":"aboveEditor"}
{"type":"extension_ui_request","id":"uuid-8","method":"setTitle","title":"pi - my project"}
{"type":"extension_ui_request","id":"uuid-9","method":"set_editor_text","text":"prefilled text"}
```

Responses (dialogs only; `id` must match):

```json
{"type":"extension_ui_response","id":"uuid-1","value":"Allow"}
{"type":"extension_ui_response","id":"uuid-2","confirmed":true}
{"type":"extension_ui_response","id":"uuid-3","cancelled":true}
```

### 3.6 Skill format

```text
skill-name/
  SKILL.md          required: YAML frontmatter + Markdown body
  scripts/          optional
  references/       optional
  assets/           optional
```

```markdown
---
name: pdf-tools
description: Extract text and tables from PDF files. Use when reading, converting, or inspecting PDFs.
license: Apache-2.0
compatibility: Requires R >= 4.1 and the pdftools package
metadata:
  author: example-org
  version: "1.0"
allowed-tools: Bash(git:*) Read
disable-model-invocation: false
---

# PDF tools
Read `references/formats.md` before converting a document.
```

Constants (`skills.ts:10-16`): `MAX_NAME_LENGTH = 64`, `MAX_DESCRIPTION_LENGTH = 1024`,
`IGNORE_FILE_NAMES = [".gitignore", ".ignore", ".fdignore"]`. Spec-only constant: `compatibility` max 500 chars.

Validation messages (verbatim): `name exceeds 64 characters (N)`,
`name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)`,
`name must not start or end with a hyphen`, `name must not contain consecutive hyphens`,
`description is required`, `description exceeds 1024 characters (N)`, collision: `name "X" collision`.

Catalog text placed in the `<skills>` section (`skills.ts:362-380`; the second line says "Use bash" when
only `bash` is active; the source string begins with `"\n\n"`, which `system-prompt.ts` removes with
`.trim()` before wrapping it in `<skills>...</skills>`):

```text
The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.

<available_skills>
  <skill>
    <name>pdf-tools</name>
    <description>Extract text and tables from PDF files. Use when reading PDFs.</description>
    <location>/abs/path/pdf-tools/SKILL.md</location>
  </skill>
</available_skills>
```

XML escaping: `&`->`&amp;`, `<`->`&lt;`, `>`->`&gt;`, `"`->`&quot;`, `'`->`&apos;`.

Explicit invocation expansion (`agent-session.ts:2075-2076`):

```text
<skill name="NAME" location="/abs/path/SKILL.md">
References are relative to /abs/path.

BODY (frontmatter stripped, trimmed)
</skill>

ARGS (only when arguments were given)
```

### 3.7 Prompt template format

```markdown
---
description: Review staged git changes
argument-hint: "[focus]"
---
Review the staged changes. Focus on ${1:-correctness, security, and error handling}.
```

Substitution regex (verbatim, `prompt-templates.ts:75`):

```text
/\$\{(\d+|ARGUMENTS|@):-([^}]*)\}|\$\{@:(\d+)(?::(\d+))?\}|\$(ARGUMENTS|@|\d+)/g
```

| Syntax | Result |
|---|---|
| `$1`, `$2`, ... | positional argument (1-based); missing -> empty string; `$0` -> empty string |
| `$@`, `$ARGUMENTS` | all arguments joined with one space (case-sensitive) |
| `${N:-default}` | argument N, or `default` when missing **or empty** |
| `${@:-default}`, `${ARGUMENTS:-default}` | all arguments, or `default` when there are none |
| `${@:N}` | arguments from N onwards (N = 0 is treated as 1) |
| `${@:N:L}` | L arguments starting at N |

Command match regex: `^\/([^\s]+)(?:\s+([\s\S]*))?$`. Description fallback: first non-empty body line, cut
to 60 characters followed by `...`.

### 3.8 `settings.json`: all keys (from `settings-manager.ts:131-187` and `docs/settings.md`)

| Key | Type | Default | Notes |
|---|---|---|---|
| `lastChangelogVersion` | string | - | internal |
| `defaultProvider` | string | automatic | |
| `defaultModel` | string | automatic | |
| `defaultThinkingLevel` | `"off"\|"minimal"\|"low"\|"medium"\|"high"\|"xhigh"\|"max"` | `"medium"` | |
| `modelThinkingLevels` | object | - | keyed by exact `provider/modelId` |
| `thinkingBudgets` | `{minimal?, low?, medium?, high?}` numbers | built-in | token budgets |
| `enabledModels` | string[] | all | same patterns as `--models` |
| `hideThinkingBlock` | boolean | `false` | |
| `showCacheMissNotices` | boolean | `false` | |
| `cacheWarming` | `"off"\|"streaming"\|"idle"` | `"streaming"` | **user file only** |
| `transport` | `"auto"\|"sse"\|"websocket"\|"websocket-cached"` | `"auto"` | |
| `steeringMode` | `"all"\|"one-at-a-time"` | `"one-at-a-time"` | |
| `followUpMode` | `"all"\|"one-at-a-time"` | `"one-at-a-time"` | |
| `externalEditor` | string | `$VISUAL`, `$EDITOR`, platform default | |
| `doubleEscapeAction` | `"tree"\|"fork"\|"none"` | `"tree"` | |
| `treeFilterMode` | `"default"\|"no-tools"\|"user-only"\|"labeled-only"\|"all"` | `"default"` | |
| `defaultProjectTrust` | `"ask"\|"always"\|"never"` | `"ask"` | **user file only** |
| `defaultTools` | string[] | `["read","bash","edit","write"]` | plain names replace; `+name` adds; `-name` removes; `[]` disables built-ins |
| `codemode.mode` | `"on"\|"only"` | `"on"` | |
| `codemode.inlineBudget` | number | `3000` | estimated tokens (chars / 4) |
| `sessionDir` | string | agent session dir | read before trust resolution |
| `compaction.enabled` | boolean | `true` | |
| `compaction.reserveTokens` | number | `16384` | |
| `compaction.keepRecentTokens` | number | `20000` | |
| `compaction.modelOverrides` | object | - | keyed by `provider/modelId` -> `{reserveTokens?, keepRecentTokens?}` |
| `branchSummary.reserveTokens` | number | `16384` | |
| `branchSummary.skipPrompt` | boolean | `false` | |
| `theme` | string | `"system"` | |
| `quietStartup` | boolean | `false` | |
| `tuiMode` | `"regular"\|"fullscreen"` | `"regular"` | |
| `fullscreenExitOutput` | `"transcript"\|"resume-hint"` | `"transcript"` | |
| `fullscreenScrollbar` | `"auto"\|"always"\|"hidden"` | `"auto"` | |
| `fullscreenCopyOnSelect` | boolean | `true` | |
| `fullscreenWheelScrollLines` | `"auto"` or 1-100 | `"auto"` | |
| `editorPaddingX` | number 0-3 | `0` | |
| `outputPad` | `0\|1` | `1` | |
| `autocompleteMaxVisible` | number 3-20 | `5` | |
| `showHardwareCursor` | boolean | `false` | |
| `terminal.showImages` | boolean | `true` | |
| `terminal.imageWidthCells` | number | `60` | |
| `terminal.clearOnShrink` | boolean | `false` | |
| `terminal.showTerminalProgress` | boolean | `false` | |
| `terminal.hyperlinks` | boolean or `"auto"` | `"auto"` | |
| `terminal.images` | `"kitty"\|"iterm2"\|"auto"\|false` | `"auto"` | |
| `terminal.trueColor` | boolean or `"auto"` | `"auto"` | |
| `images.autoResize` | boolean | `true` | max 2000 x 2000 px |
| `images.blockImages` | boolean | `false` | |
| `markdown.codeBlockIndent` | string | two spaces | |
| `markdown.mermaid` | `"off"\|"final"\|"streaming"` | `"streaming"` | |
| `httpProxy` | string | - | **user file only**: documented, and enforced because `main.ts:588, 865` read `getGlobalSettings().httpProxy` (VERIFIED by verifier) |
| `httpIdleTimeoutMs` | number | `300000` | `0` disables |
| `websocketConnectTimeoutMs` | number | `15000` | |
| `retry.enabled` | boolean | `true` | |
| `retry.maxRetries` | number | `3` | |
| `retry.baseDelayMs` | number | `2000` | exponential backoff 2 s, 4 s, 8 s |
| `retry.maxAgentDelayMs` | number | `60000` | |
| `retry.provider.timeoutMs` | number | `httpIdleTimeoutMs` | |
| `retry.provider.maxRetries` | number | `0` | |
| `retry.provider.maxRetryDelayMs` | number | `60000` | |
| `shellPath` | string | platform default | |
| `shellCommandPrefix` | string | - | |
| `npmCommand` | string[] | `["npm"]` | |
| `packages` | `(string \| {source, autoload?, extensions?, skills?, prompts?, themes?})[]` | `[]` | |
| `extensions` | string[] | `[]` | also `+builtin:<name>` / `-builtin:<name>` |
| `skills` | string[] | `[]` | |
| `prompts` | string[] | `[]` | |
| `themes` | string[] | `[]` | |
| `enableSkillCommands` | boolean | `true` | |
| `collapseChangelog` | boolean | `false` | |
| `enableInstallTelemetry` | boolean | `true` | |
| `enableAnalytics` | boolean | `false` | |
| `trackingId`, `deviceId` | string | generated | `deviceId` user file only |
| `warnings.anthropicExtraUsage` | boolean | `true` | |

Merge functions (verbatim logic, `settings-manager.ts:193-252`):

```typescript
function deepMergeObjects(base, overrides) {
  const result = { ...base };
  for (const key of Object.keys(overrides)) {
    const overrideValue = overrides[key];
    if (overrideValue === undefined) continue;
    const baseValue = base[key];
    result[key] = isMergeableObject(baseValue) && isMergeableObject(overrideValue)
      ? deepMergeObjects(baseValue, overrideValue) : overrideValue;      // arrays are NOT mergeable
  }
  return result;
}
export const DEFAULT_TOOL_NAMES = ["read", "bash", "edit", "write"];
function mergeDefaultTools(base, overrides) {
  if (overrides === undefined) return base;
  if (!Array.isArray(base) || !Array.isArray(overrides) || !overrides.every(isToolModifier)) return overrides;
  return [...base, ...overrides];
}
function resolveDefaultTools(entries) {
  const plain = entries.filter((entry) => !isToolModifier(entry));
  const tools = plain.length > 0 || entries.length === 0 ? plain : [...DEFAULT_TOOL_NAMES];
  for (const entry of entries) {
    if (!isToolModifier(entry)) continue;
    const name = entry.slice(1);
    const index = tools.indexOf(name);
    if (entry.startsWith("+") && index === -1 && name) tools.push(name);
    else if (entry.startsWith("-") && index !== -1) tools.splice(index, 1);
  }
  return tools;
}
```

### 3.9 Package manifest, settings object form, sources

`package.json` manifest (`pi-manifest.ts`; only these four string-array fields are read; `pi.image` and
`pi.video` are gallery metadata):

```json
{
  "name": "my-pi-package",
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./src/extension.ts"],
    "skills": ["./resources/skills"],
    "prompts": ["./resources/prompts/*.md"],
    "themes": ["./resources/themes/*.json"]
  }
}
```

Conventional layout without a manifest: `extensions/` (`.ts`/`.js`), `skills/` (skill directories),
`prompts/` (`.md`), `themes/` (`.json`). File patterns per type (`package-manager.ts:212-217`):
extensions `/\.(ts|js)$/`, skills `/\.md$/`, prompts `/\.md$/`, themes `/\.json$/`.

Settings object form:

```json
{
  "packages": [
    "npm:@example/pi-tools@1.0.0",
    "git:github.com/example/pi-tools@v1",
    "./local-package",
    { "source": "npm:@example/pi-tools",
      "autoload": true,
      "extensions": ["extensions/*.ts", "!extensions/legacy.ts"],
      "skills": [],
      "prompts": ["prompts/review.md"] }
  ]
}
```

Source strings: `npm:<name>[@<version-or-range>]`, `git:<host>/<owner>/<repo>[@<ref>]`,
`https://host/owner/repo[@ref]`, `ssh://...`, `git://...`, `git:git@host:owner/repo[@ref]`, local path
(relative paths resolve from the directory of the settings file that contains them). Constants:
`NETWORK_TIMEOUT_MS = 10000`, `UPDATE_CHECK_CONCURRENCY = 4`, `GIT_UPDATE_CONCURRENCY = 4`.

### 3.10 Trust store and prompt

`<agent-dir>/trust.json`:

```json
{
  "/Users/me/work": true,
  "/Users/me/work/untrusted-clone": false
}
```

Prompt (`project-trust.ts:24-26`, `trust-manager.ts:64-95`), options in this order:

```text
Trust project folder?
<cwd>

This allows pi to load .pi settings and resources, install missing project packages, and execute project extensions.

  Trust
  Trust parent folder (<parent>)
  Trust (this session only)
  Do not trust
  Do not trust (this session only)
```

### 3.11 Built-in slash commands (verbatim, `slash-commands.ts:19-44`)

| Command | Description | Argument hint |
|---|---|---|
| `/settings` | Open settings menu | |
| `/model` | Select model (opens selector UI) | `<provider/model>` |
| `/tree` | Navigate session tree (switch branches) | |
| `/thinking` | Set thinking level | `<level>` |
| `/scoped-models` | Enable/disable models for Ctrl+P cycling | |
| `/export` | Export session (HTML default, or specify path: .html/.jsonl) | |
| `/import` | Import and resume a session from a JSONL file | |
| `/share` | Share session as a secret GitHub gist | |
| `/bug` | Report a bug to the Pi developers | `<description>` |
| `/copy` | Copy last agent message to clipboard | |
| `/name` | Set session display name | |
| `/session` | Show session info and stats | |
| `/changelog` | Show changelog entries | |
| `/hotkeys` | Show all keyboard shortcuts | |
| `/fork` | Create a new fork from a previous user message | |
| `/clone` | Duplicate the current session at the current position | |
| `/trust` | Save project trust decision for future sessions | |
| `/login` | Configure provider authentication | `<provider>` |
| `/logout` | Remove provider authentication | |
| `/new` | Start a new session | |
| `/compact` | Manually compact the session context | |
| `/resume` | Resume a different session | |
| `/reload` | Reload keybindings, extensions, skills, prompts, themes, and context files | |
| `/quit` | Quit pi | |

Plus: `/mcp`, `/llama` (built-in extensions); `/skill:<name>`; one command per prompt template; extension
commands. Input prefixes: `!cmd` runs a shell command and adds the output to the context, `!!cmd` runs it
without adding it to the context (`interactive-mode.ts:3243-3259`).

### 3.12 CLI flags relevant to extensibility (`docs/cli.md`)

`-p/--print`, `--mode text|json|rpc`, `-e/--extension <path>` (repeatable), `-ne/--no-extensions`,
`--skill <path>`, `-ns/--no-skills`, `--prompt-template <path>`, `-np/--no-prompt-templates`,
`--theme <path>`, `--no-themes`, `-nc/--no-context-files`, `--system-prompt <text|path>`,
`--append-system-prompt <text|path>` (repeatable), `-t/--tools <list>`, `-xt/--exclude-tools <list>`,
`-nbt/--no-builtin-tools`, `-nt/--no-tools`, `-a/--approve`, `-na/--no-approve`, `--offline`
(`PI_OFFLINE=1`), `--model`, `--provider`, `--thinking`, `--models`, `--session*`, `--no-session`.
Environment: `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`.

### 3.13 JSON event stream (json and rpc modes)

Session events: `agent_start`, `agent_end {messages, willRetry}`, `agent_settled`, `turn_start`,
`turn_end {message, toolResults}`, `message_start {message}`, `message_update {usage, assistantMessageEvent}`,
`message_end {message}`, `tool_execution_start {toolCallId, toolName, args}`,
`tool_execution_update {..., partialResult}`, `tool_execution_end {toolCallId, toolName, result, isError}`,
`queue_update {steering, followUp}`, `entry_appended {entry}`, `session_info_changed {name}`,
`thinking_level_changed {level}`, `compaction_start {reason}`,
`compaction_end {reason, result?, aborted, willRetry, errorMessage?}`,
`auto_retry_start {attempt, maxAttempts, delayMs, errorMessage}`, `auto_retry_end {success, attempt, finalError?}`,
`summarization_retry_scheduled`, `summarization_retry_attempt_start`, `summarization_retry_finished`.
RPC only: `bash_execution_update {id?, delta}`, `extension_error {extensionPath, event, error}`.

`assistantMessageEvent.type` values: `start`, `text_start`, `text_delta`, `text_end`, `thinking_start`,
`thinking_delta`, `thinking_end`, `toolcall_start` (`contentIndex`, `id`, `toolName`), `toolcall_delta`,
`toolcall_end` (`toolCall`), `done` (`reason`, `message`), `error` (`reason`, `error`).

Example run (from `docs/json.md`):

```json
{"type":"session","version":3,"id":"uuid","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/path"}
{"type":"agent_start"}
{"type":"turn_start"}
{"type":"message_start","message":{"role":"user","content":"Review this repository","timestamp":1733234401000}}
{"type":"message_end","message":{"role":"user","content":"Review this repository","timestamp":1733234401000}}
{"type":"message_update","usage":{"input":100,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":101,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello "}}
{"type":"tool_execution_start","toolCallId":"call_abc123","toolName":"bash","args":{"command":"ls -la"}}
{"type":"tool_execution_end","toolCallId":"call_abc123","toolName":"bash","result":{"content":[{"type":"text","text":"complete output"}],"details":{}},"isError":false}
{"type":"turn_end","message":{"role":"assistant"},"toolResults":[]}
{"type":"agent_end","messages":[],"willRetry":false}
{"type":"agent_settled"}
```

RPC command types (`rpc-types.ts:19-72`): `prompt {message, images?, streamingBehavior?}`,
`steer`, `follow_up`, `abort`, `clear_queue`, `new_session {parentSession?}`, `get_state`,
`set_model {provider, modelId}`, `cycle_model`, `get_available_models`, `set_thinking_level {level}`,
`cycle_thinking_level`, `get_available_thinking_levels`, `set_steering_mode {mode}`,
`set_follow_up_mode {mode}`, `compact {customInstructions?}`, `set_auto_compaction {enabled}`,
`set_auto_retry {enabled}`, `abort_retry`, `bash {command, excludeFromContext?}`, `abort_bash`,
`get_session_stats`, `export_html {outputPath?}`, `switch_session {sessionPath}`, `fork {entryId}`,
`clone`, `get_fork_messages`, `get_entries {since?}`, `get_tree`, `get_last_assistant_text`,
`set_session_name {name}`, `get_messages`, `get_commands`. Every command accepts an optional string `id`.

Response envelope: `{"id"?, "type":"response", "command":"<type>", "success":true, "data"?}` or
`{"id"?, "type":"response", "command":"<type>", "success":false, "error":"..."}`; malformed JSON gives
`{"type":"response","command":"parse","success":false,"error":"Failed to parse command: ..."}`.

`get_state` data (`RpcSessionState`): `model?`, `thinkingLevel`, `isStreaming`, `isCompacting`,
`steeringMode`, `followUpMode`, `sessionFile?`, `sessionId`, `sessionName?`, `autoCompactionEnabled`,
`messageCount`, `pendingMessageCount`.

### 3.14 System prompt option structure (`system-prompt.ts:9-32`)

```typescript
export interface BuildSystemPromptOptions {
  customPrompt?: string;            // replaces the default preamble (and drops tools/rules/docs sections)
  forceSystemPrompt?: string;       // exact full replacement set by a before_agent_start handler
  selectedTools?: string[];         // default: [read, bash, edit, write]
  toolSnippets?: Record<string, string>;
  toolGuidelines?: Record<string, string[]>;
  promptGuidelines?: string[];
  appendSystemPrompt?: string;
  sections?: Record<string, string>;   // additional XML-wrapped sections keyed by tag name
  cwd: string;
  contextFiles?: Array<{ path: string; content: string }>;
  skills?: Skill[];
}
```

Default preamble (verbatim): "You are an expert coding assistant operating inside pi, a coding agent
harness. You help users by reading files, executing commands, editing code, and writing new files."

---

## 4. Recommended design for gptr

Status of this section: design proposal derived from the findings. Everything marked "prototyped" was
executed (section 5). Requirement IDs refer to `dev/spec/00-vision-brief.md`.

### 4.1 Principles

1. **Same mental model as Pi, R-native surface.** An extension is `function(gptr) { ... }`; it registers
   handlers/tools/commands on the API object it receives. Names are snake_case, event names are identical
   to Pi's wherever the semantics are identical, so Pi documentation and examples remain useful. (REQ-29)
2. **Synchronous.** R is single-threaded; handlers are ordinary functions and dialogs block. There is no
   `waitForIdle`, no promise, no `AbortSignal`; cancellation is the R interrupt condition.
3. **Value semantics instead of in-place mutation.** Pi handlers mutate `event.input`; R lists are copied,
   so gptr handlers return patches (`list(input = ...)`, `list(messages = ...)`).
4. **Fail closed.** A throwing `tool_call` handler blocks the tool; no UI means "not approved", "not
   trusted"; a corrupt settings file is never overwritten.
5. **The core stays minimal** (REQ-10): permission modes (REQ-37), plan mode, ask-user (REQ-36) and todo
   are *built-in extensions* that use only the public API, can be disabled (`"-builtin:plan"`) and can be
   replaced by a user extension that registers the same tool/command name.
6. **Interoperate, do not invent**: Agent Skills folders, `.agents/skills`, `.claude/skills`,
   `AGENTS.md`/`CLAUDE.md`, `mcp.json` with `mcpServers`, btw's `inst/skills`. (REQ-28, REQ-30)

### 4.2 Directories

User level, resolved by `gptr_home()` in this order (partially prototyped as `gptr_user_dir()` in section
5.8: the `GPTR_HOME` and `R_user_dir` branches were run, the `options()` and `~/.gptr` branches were not):

1. `options(gptr.home = "...")`, then environment variable `GPTR_HOME`;
2. `<profile>/.gptr` **if it already exists** (the user created it; `<profile>` is `USERPROFILE` on Windows,
   `HOME` elsewhere - never `path.expand("~")` on Windows, see section 6);
3. `tools::R_user_dir("gptr", "config")` (the only location gptr creates on its own, and only after an
   explicit user action such as `gptr_setup()`, `/trust` or `gptr_set()`).

```text
<gptr-home>/
  settings.json            user settings
  trust.json               project trust decisions
  mcp.json                 user MCP servers ("mcpServers" object)
  AGENTS.md                user-wide instructions (AGENTS.override.md, CLAUDE.md also read)
  SYSTEM.md                replaces the default system prompt
  APPEND_SYSTEM.md         appended to the system prompt
  extensions/              *.R files, or <dir>/index.R
  skills/                  <name>/SKILL.md (standalone *.md accepted at the root)
  prompts/                 *.md (direct children only)

<project>/.gptr/           REQ-27
  vignette.Rmd             project instructions (read as TEXT, never rendered or evaluated while loading)
  settings.json  mcp.json  SYSTEM.md  APPEND_SYSTEM.md
  extensions/  skills/  prompts/
  sessions/                (session data; other track)
```

Read-only compatibility locations:

| What | Locations | Setting to disable |
|---|---|---|
| skills | `.agents/skills`, `.claude/skills` in cwd and each ancestor up to the project root; `<profile>/.agents/skills`, `<profile>/.claude/skills`, `<profile>/.codex/skills` | `skillCompat: []` (default `["agents","claude","codex"]`) |
| context files | `AGENTS.override.md`, `AGENTS.md`, `CLAUDE.md` (exact case) in cwd and every ancestor; `.gptr/vignette.Rmd` takes the place of `AGENTS.md`/`CLAUDE.md` in its directory | `contextFiles: false` or `gptr(context_files = FALSE)` |
| prompt templates | `.claude/commands/*.md` (P2, optional) | `promptCompat: []` |
| R packages | `<lib>/<pkg>/gptr/{skills,extensions,prompts}` and `<lib>/<pkg>/skills` | `plugins`, `pluginsAutoload` |

Project root = nearest ancestor containing `.git`, `DESCRIPTION`, `*.Rproj` or `.gptr` (prototyped:
`find_project_root()`); ancestor scans stop there, exactly like Pi stops at the git root.

### 4.3 Resource precedence (first wins on a name collision)

| Rank | Source | Pi equivalent |
|---|---|---|
| 0 | call arguments `gptr(skills =, extensions =, plugins =, prompts =)` | CLI `-e`, `--skill` |
| 1 | project `settings.json` entries | rank 0 |
| 2 | project auto-discovery: `.gptr/...`, then `.agents/skills`, then `.claude/skills` (nearest directory first) | rank 1 |
| 3 | user `settings.json` entries | rank 2 |
| 4 | user auto-discovery: `<gptr-home>/...`, then `~/.agents`, `~/.claude`, `~/.codex` | rank 3 |
| 5 | plugin packages: `plugins` order, then attached packages in `search()` order | rank 4 |
| 6 | built-in resources shipped in gptr's own `inst/gptr/` | rank 5 |

Collisions produce a diagnostic `list(type = "collision", name, winner, loser)` available from
`gptr_diagnostics()`; they never stop startup. On the development machine the same skill is installed in
up to three agent folders (31 collisions among 68 files), so collisions must be silent by default and only
shown by `/skills` or `gptr_diagnostics()`.

Extension handlers run in rank order, then file name order (`sort(method = "radix")` for locale
independence), then registration order.

### 4.4 The extension API object

`gptr` is a locked environment of class `"gptr_extension_api"` (the prototype locks the environment but
does not set the class). Methods are prototyped in section 5.4 unless marked NP (= not prototyped, design
only). Also NP: `unregister_provider`, the fields `path` and `dir`, and the `timeout` argument of dialogs.

| Method | Signature | Notes |
|---|---|---|
| `on` | `gptr$on(event, handler)` | `handler = function(event, ctx)`; returns (invisibly) an unsubscribe function; unknown event names are an error |
| `register_tool` | `gptr$register_tool(name, description, parameters, execute, label = name, annotations = list(), prompt_snippet = NULL, prompt_guidelines = character(), sequential = FALSE, active = TRUE)` | `parameters` is a JSON-Schema-shaped list with `type = "object"`; `execute = function(input, ctx, tool_call_id)`; same name as a built-in tool overrides it |
| `register_command` | `gptr$register_command(name, handler, description = "", complete = NULL)` | `handler = function(args, ctx)`; `args` is the raw string after the command name |
| `register_flag` / `get_flag` | `gptr$register_flag(name, type = c("logical","character"), default = NULL, description = "")` | set by `gptr(flags = list(plan = TRUE))`, `options(gptr.flag.plan = TRUE)` or `Rscript ... --plan` |
| `register_provider` / `unregister_provider` | `gptr$register_provider(name, config)` | config keys as Pi `ProviderConfig` in snake_case; queued until bind |
| `register_mcp_server` / `unregister_mcp_server` (NP) | `gptr$register_mcp_server(name, config)` | same shape as an `mcpServers` entry |
| `register_router` (NP) | `gptr$register_router(id, route)` | R analogue of `registerVirtualModel`; `route = function(request, ctx)` returns a model spec (REQ-14) |
| `send_message` | `gptr$send_message(custom_type, content, display = TRUE, details = NULL, trigger_turn = FALSE, deliver_as = c("follow_up","steer","next_turn"))` | |
| `send_user_message` | `gptr$send_user_message(content, deliver_as = c("follow_up","steer"))` | always triggers a turn |
| `append_entry` | `gptr$append_entry(custom_type, data = NULL)` | never sent to the model; `data` must be JSON-serialisable |
| `get_active_tools` / `set_active_tools` / `get_all_tools` | | unknown names are ignored |
| `get_commands` / `get_settings` | | |
| `set_model` / `get_thinking_level` / `set_thinking_level` (NP) | | session-scoped, does not change saved defaults |
| `set_session_name` / `get_session_name` (NP) | | |
| `exec` (NP) | `gptr$exec(command, args = character(), timeout = NULL, cwd = NULL)` | returns `list(stdout, stderr, code, killed)`; `processx::run()` when installed, else `system2()`; never a shell string (REQ-09) |
| `events` | `gptr$events$emit(channel, data)`, `gptr$events$on(channel, handler)` | inter-extension bus |
| `state` | environment | private mutable state of this extension |
| `name`, `path`, `dir` | character | `dir` lets an extension find files shipped next to it |

Action methods (`send_message`, `send_user_message`, `append_entry`, `set_*`) raise
`gptr$<name>() cannot be called while extensions are loading` until the session is bound (prototyped).

Not ported from Pi (no equivalent surface in an R console): `registerShortcut`, message/entry renderers,
markdown transformer, `setWidget`, `setFooter`, `setHeader`, `custom()` components, themes,
`cache_warming_decision`. `set_status(key, text)` is kept as a cheap hook for front ends (RStudio, Shiny).

**Tool result constructor** (exported):

```r
gptr_tool_result(text = NULL, ..., images = list(), details = NULL, is_error = FALSE, terminate = FALSE)
# returns list(content = list(list(type = "text", text = ...), ...), details, is_error, terminate)
```

`execute` may also return a character vector (wrapped automatically) and may `stop()` (becomes an error
result whose text is the condition message).

**Context object `ctx`** (environment, fields computed when the context is created for a dispatch).
Prototyped fields: `ui`, `mode`, `has_ui`, `cwd`, `env`, `is_idle()`, `entries()`, `settings()`, `tools()`,
`execute_tool()`. Everything else in the table is design only.

| Field | Meaning |
|---|---|
| `ctx$ui` | `select(title, options, default = NULL, timeout = NULL)`, `confirm(title, message = "", default = FALSE, timeout = NULL)`, `input(title, placeholder = "", default = NULL)`, `editor(title, prefill = "")`, `notify(message, type = c("info","warning","error"))`, `set_status(key, text = NULL)` |
| `ctx$mode` | `"console"` (interactive chat), `"script"` (programmatic call / `Rscript`), `"knit"` (knitr/Quarto), `"rpc"`, `"shiny"` |
| `ctx$has_ui` | whether dialogs can be answered |
| `ctx$cwd`, `ctx$project_root` | |
| `ctx$env` | the evaluation environment of the session (REQ-22); extensions must treat it as the user's property |
| `ctx$model`, `ctx$thinking_level` | |
| `ctx$is_idle()`, `ctx$abort()`, `ctx$is_project_trusted()` | |
| `ctx$entries()`, `ctx$branch()` | read-only session entries (all / active branch) |
| `ctx$context_usage()` | `list(tokens, context_window, percent)` |
| `ctx$compact(instructions = NULL)`, `ctx$system_prompt()`, `ctx$settings()` | |
| tool context only | `ctx$tool_call_id`, `ctx$tools()`, `ctx$execute_tool(name, args)` (nested call goes through `tool_call`/`tool_result`) |
| command context only | `ctx$new_session()`, `ctx$fork(entry_id)`, `ctx$switch_session(path)`, `ctx$reload()` |

### 4.5 Events for gptr

Priority P0 = required for the built-in extensions and for v1; P1 = provider/session hooks; P2 = later.

| Event | Pri | Payload | Handler returns | Dispatch |
|---|---|---|---|---|
| `project_trust` | P0 | `cwd` | `list(trusted = "yes"\|"no"\|"undecided", remember = FALSE)` | first decision (user-level extensions only) |
| `resources_discover` | P0 | `cwd`, `reason` | `list(skill_paths, prompt_paths)` | collect |
| `session_start` | P0 | `reason = "startup"\|"reload"\|"new"\|"resume"\|"fork"` | - | notify |
| `session_shutdown` | P0 | `reason` | - | notify (also from `on.exit`/finalizer) |
| `input` | P0 | `text`, `images`, `source = "interactive"\|"script"\|"rpc"\|"extension"` | `list(action = "continue"\|"transform"\|"handled", text)` | transform chain |
| `before_agent_start` | P0 | `prompt`, `images`, `system_prompt`, `system_prompt_options` | `list(message = list(custom_type, content, display, details), system_prompt, append_system_prompt, sections)` | collect + override |
| `agent_start`, `agent_end` (`messages`) | P0 | | - | notify |
| `turn_start` (`turn_index`), `turn_end` (`turn_index`, `message`, `tool_results`) | P0 | | `turn_end`: `list(entries, continue)` | notify / boundary |
| `context` | P0 | `messages` (no system message) | `list(messages)` | transform chain |
| `tool_call` | P0 | `tool_name`, `tool_call_id`, `input`, `annotations`, `parent_tool_call_id` | `list(block = TRUE, reason)`, `list(input = patched)` | block; handler error = block |
| `tool_result` | P0 | `tool_name`, `tool_call_id`, `input`, `content`, `details`, `is_error` | `list(content, details, is_error)` | patch chain |
| `tool_execution_start/update/end` | P0 | as Pi | - | notify |
| `message_end` | P0 | `message` | `list(message)` (same role) | replace chain |
| `message_start`, `message_update` | P1 | as Pi | - | notify |
| `before_provider_request` | P1 | `payload` (R list before JSON encoding), `provider`, `model` | replacement payload | replace chain |
| `before_provider_headers` | P1 | `headers` (named character) | `list(headers)` | patch chain (value `NA` deletes) |
| `after_provider_response` | P1 | `status`, `headers` | - | notify |
| `model_select`, `thinking_level_select` | P1 | as Pi | - | notify |
| `session_before_compact` / `session_compact` | P1 | as Pi | `list(cancel, compaction)` | cancel |
| `session_before_switch` / `session_before_fork` | P1 | as Pi | `list(cancel)` | cancel |
| `agent_before_settle`, `agent_settled` | P1 | as Pi | `list(entries, continue)` / - | boundary / notify |
| `document_write` (gptr) | P1 | `path`, `format`, `kind = "code"\|"prompt"\|"decision"\|"comment"`, `text`, `position` | `list(block, reason)`, `list(text)` | block + patch; lets an extension veto or reformat what is written to the history document (REQ-24..26) |
| `decision` (gptr) | P1 | `model`, `question`, `type`, `input_index`, `answer`, `probabilities`, `latency` | - | notify; fired after each System 1 call (REQ-13, REQ-20) |
| `subagent_start`, `subagent_end` (gptr) | P2 | `id`, `name`, `model`, `prompt` / `result`, `usage` | - | notify (REQ-32..34) |

The R execution tool needs no dedicated event: it is the tool named `"R"`, so `tool_call` sees
`event$input$code` before evaluation and `tool_result` sees the outcome. To make that useful the R tool
must put a stable structure in `details` (proposal; coordinate with the tools track):

```r
details = list(code = "<source>", visible = TRUE, value_class = "lm",
               created = c("fit"), modified = character(), removed = character(),   # diff of ls(ctx$env)
               plots = 1L, messages = character(), warnings = character(), error = NULL, elapsed = 0.12)
```

### 4.6 Hooks required by the four built-in extensions

| Extension | Hooks and API it needs | Verified in prototype |
|---|---|---|
| **Permission gate** (REQ-37) | `tool_call` with `tool_name`, `input`, `annotations` and block/patch result; handler error = block; nested calls (`ctx$execute_tool`) routed through the same hook; `ctx$has_ui`, `ctx$ui$select`, `ctx$ui$input`, `ctx$ui$set_status`; `gptr$state`; `register_flag("permission-mode")`; `register_command("permissions")`; `append_entry` (persist the mode); `get_settings()`; `session_start`; static code classifier `gptr_classify_code()` | yes (12 checks) |
| **Plan mode** | `get_active_tools` / `set_active_tools`; `tool_call` (block non-read-only R code); `before_agent_start` (hidden context message); `context` (drop stale plan context); `turn_end` (track `[DONE:n]`); `agent_end` (extract plan, ask what next); `send_message(trigger_turn = TRUE)`; `send_user_message`; `append_entry` + `session_start` + `ctx$entries()` (restore); `register_command("plan")`; `register_flag("plan")`; `ctx$ui$select/input/notify/set_status` | yes (9 checks) |
| **Ask user** (REQ-36) | `register_tool(..., sequential = TRUE, annotations = list(read_only = TRUE))`; `ctx$has_ui`; `ctx$ui$select` / `ctx$ui$input`; result `details`; error result when there is no UI | yes (2 checks) |
| **Todo** | `register_tool`; full state snapshot in tool-result `details`; `session_start` (+ later `session_tree`) and `ctx$entries()` to rebuild; `register_command("todos")`; `ctx$ui$set_status` | yes (4 checks) |

Permission modes (prototyped semantics):

| Mode | Risk level allowed without asking | Otherwise |
|---|---|---|
| `auto` | everything | - |
| `edits` | 0 (read-only) and 1 (non-destructive tools, R code that only assigns objects) | ask |
| `ask` (default for interactive use) | 0 | ask |
| `readonly` | 0 | block without asking |

Risk level of a call as implemented in the prototype: tool annotated `read_only = TRUE` = 0; tool
annotated `destructive = FALSE` = 1; destructive **or unannotated** tool = 2 (MCP default: a tool without
hints may be destructive); for the `R` tool the classifier verdict maps `read-only` = 0, `assigns` = 1,
`side-effect` = 2, `dangerous`/`invalid` = 3. Without UI every "ask" becomes a block whose reason tells the
model (and the user reading the transcript) how to allow it. Dialog options: `Yes`,
`Yes, always this session`, `No`, `No, and tell the model what to do instead`.

Recommendations beyond the prototype:

- **Path awareness** (not prototyped): the prototype rates every `write` call as level 2, so mode `edits`
  still asks for file writes. The real gate should rate `write`/`edit` of a path inside the project root
  as level 1 and any path outside it (or matching a protected pattern such as `.env`, `.git/`, `.Rprofile`,
  `.Renviron`, `.gptr/settings.json`) as level 3, after resolving the path with `normalizePath()`.
- `permissionMode` in a **project** settings file may only make the mode stricter
  (`auto < edits < ask < readonly`), never looser.
- Reads under any discovered skill directory are pre-approved (agentskills.io "Permission allowlisting").
- `allowed-tools` in skill frontmatter may pre-approve tools for the turn in which the skill was explicitly
  invoked by the user (`/skill:name`), never for model-initiated loads (P2).
- Persistent rules (P1): `"permissions": {"allow": [...], "deny": [...]}` with entries
  `{"tool": "write", "path": "output/**"}` or `{"tool": "R", "calls": ["ggsave"]}`; deny beats allow.

### 4.7 Skills (REQ-28)

Exported functions:

```r
gptr_skills(cwd = getwd(), refresh = FALSE)      # data.frame: name, description, path, base_dir, scope, source, model_invocable
gptr_skill(name, args = NULL)                    # the <skill ...> block as one string (what /skill:name injects)
gptr_skill_install(source, scope = c("project", "user"), overwrite = FALSE)   # P2: copy a skill dir / package skill / GitHub repo
gptr_diagnostics()                               # warnings and collisions from the last resource load
```

Rules:

1. Discovery and validation exactly as Pi (section 2.12), with bounds from the integration guide:
   `max_depth = 6`, `max_dirs = 2000`; skip dot-directories, `node_modules`, `renv`, `packrat`.
   Ignore-file support (`.gitignore`) is **not** implemented in v1 (UNCERTAIN whether anyone relies on it).
2. Parse frontmatter with `yaml::yaml.load()`; on a parse error retry once after quoting unquoted values
   that contain `": "` (prototyped; repairs `description: Use this skill when: ...`).
3. Honoured keys: `name`, `description`, `disable-model-invocation`, Claude's `when_to_use` (appended to the
   description in the catalog) and `user-invocable: false` (hide from `/` listing). Parsed and exposed but
   not acted on in v1: `license`, `compatibility`, `metadata`, `allowed-tools`, `argument-hint`.
4. Catalog = Pi's text (section 3.6) with the tool name of gptr's read tool. Emitted only when a read tool
   is active. Paths use forward slashes (`normalizePath(winslash = "/")`).
5. **Catalog budget** (not in Pi): setting `skills.catalogMaxChars` (default 12000). When the catalog
   exceeds it, descriptions are truncated to their first 250 characters in reverse precedence order until it
   fits. Measured need: 37 real skills produce 23,552 characters (about 5,900 tokens).
6. Activation: the model reads `SKILL.md` with the read tool (no extra tool, REQ-10); the user types
   `/skill:name args`; programmatically `gptr("prompt", skills = c(name1, name2))` **pre-loads** the named
   skills as `<skill>` blocks in front of the prompt, and `skills = FALSE` disables skills for the call
   (semantics to be confirmed by the maintainer, see open questions).
7. De-duplicate activations per session (guide, step 5) and protect `<skill ...>` blocks from compaction.

### 4.8 Prompt templates and slash commands (REQ-31)

- Format, substitution and argument parsing are byte-for-byte Pi's (prototyped, 67 tests). No R expression
  interpolation in templates: a template comes from a file that may belong to an untrusted project.
- Exported: `gptr_prompts()` (data.frame `name`, `description`, `argument_hint`, `path`, `scope`),
  `gptr_prompt(name, ...)` (returns the expanded text; `...` are the arguments).
- `gptr("/review concurrency")` expands templates and skill commands unless `expand = FALSE`.
- Console chat input dispatch (same order as Pi):
  1. built-in command; 2. `!code` / `!!code`; 3. extension command; 4. `input` handlers;
  5. `/skill:name`; 6. prompt template; 7. model.
- `!expr` evaluates R code typed by the user in `ctx$env`, shows the output and adds it to the context;
  `!!expr` does the same without adding it to the context (R analogue of Pi's `!cmd` / `!!cmd`).

Built-in commands proposed for the console chat:

| Command | Purpose | Pi equivalent |
|---|---|---|
| `/help` | list commands, skills, templates | `/hotkeys` + menu |
| `/model [provider/model]`, `/thinking [level]` | REQ-14 | same |
| `/tools [+name\|-name ...]` | show / change active tools | `tools.ts` example |
| `/skills`, `/skill:<name> [args]` | list / force-load | same |
| `/permissions [mode]`, `/plan`, `/todos` | built-in extensions | examples |
| `/compact [instructions]`, `/new`, `/resume`, `/fork`, `/name [name]`, `/session` | session control | same |
| `/export [path]` | write the session document (`.R`, `.Rmd`, `.qmd`, `.ipynb`) | `/export` |
| `/copy` | copy the last answer (`utils::writeClipboard` on Windows, `pbcopy`/`xclip` via `system2`, else message) | `/copy` |
| `/settings [key [value]]`, `/login [provider]`, `/logout [provider]` | REQ-15 | same |
| `/trust`, `/reload`, `/mcp` | | same |
| `/quit` (also `/exit`, empty line + Ctrl-D/Esc) | leave the chat | `/quit` |

### 4.9 Settings (format decision: JSON)

| Candidate | Nested data | Comments | Lossless machine round trip | Executes code | Dependency | Verdict |
|---|---|---|---|---|---|---|
| JSON | yes | no | yes (verified with `simplifyVector = FALSE`) | no | jsonlite (already needed) | **chosen** |
| YAML | yes | yes | no (verified: sequences come back as atomic vectors, scalars/arrays ambiguous; verifier also saw `yaml::as.yaml()` write `caf<U+00E9>` in a C locale, while `yaml::yaml.load()` reads UTF-8 correctly there) | no | yaml | use only for reading frontmatter |
| DCF | no (flat, character only; verified) | `#` lines | no | no | base | rejected |
| R script / `.Rprofile`-style | yes | yes | no | **yes** | base | rejected: project-supplied code execution |

Additional reasons for JSON: `mcp.json` must be JSON to stay copy-paste compatible with other agents;
Pi/Claude settings can be reused; one parser for settings, sessions and provider payloads.
Comments: accept `//`-free strict JSON only; document keys in `?gptr_settings`.

Proposed keys (camelCase, identical to Pi where the meaning is identical):

| Key | Type | Default | Scope |
|---|---|---|---|
| `defaultProvider`, `defaultModel` | string | first provider with credentials | both |
| `defaultThinkingLevel` | `off\|minimal\|low\|medium\|high\|xhigh\|max` | `medium` | both |
| `modelThinkingLevels`, `enabledModels` | object / string[] | - | both |
| `system1Model` | string | `typesafe/jev-latest` | both |
| `permissionMode` | `auto\|edits\|ask\|readonly` | `ask` | both (project may only tighten) |
| `permissions.allow`, `permissions.deny` | array of rule objects | `[]` | both (project `allow` ignored unless trusted) |
| `defaultTools` | string[] with `+name`/`-name` | `["read","write","edit","R"]` | both |
| `steeringMode`, `followUpMode` | `all\|one-at-a-time` | `one-at-a-time` | both |
| `compaction.enabled/reserveTokens/keepRecentTokens/modelOverrides` | | `true/16384/20000/-` | both |
| `retry.*` | as Pi | as Pi | both |
| `images.autoResize`, `images.blockImages` | boolean | `true`, `false` | both |
| `httpProxy` | string | - | user only |
| `httpIdleTimeoutMs` | number | `300000` | both |
| `document.format`, `document.path` | `R\|Rmd\|qmd\|ipynb`, string | `R`, `.gptr/history.R` | both |
| `sessionDir` | string | `.gptr/sessions` | both |
| `extensions`, `skills`, `prompts` | string[] (paths, globs, `!`/`+`/`-`, `+builtin:x`, `-builtin:x`) | `[]` | both, combined |
| `plugins` | string[] (R package names) or objects `{ "package": "x", "extensions": [...], "skills": [...], "prompts": [...] }` | `[]` | both, combined |
| `pluginsAutoload` | `none\|attached\|installed` | `attached` | user only |
| `skillCompat` | subset of `["agents","claude","codex"]` | all three | both |
| `skills.catalogMaxChars` | number | `12000` | both |
| `enableSkillCommands` | boolean | `true` | both |
| `contextFiles` | boolean | `true` | both |
| `defaultProjectTrust` | `ask\|always\|never` | `ask` | user only |
| `quietStartup` | boolean | `false` | both |

Precedence (highest first): arguments of `gptr()` > `options(gptr.<key> = )` > environment variables
(`GPTR_HOME`, `GPTR_OFFLINE`, provider keys) > project `.gptr/settings.json` (trusted projects only) > user
`settings.json` > built-in defaults. Merge rules are Pi's (prototyped, section 5.3): objects merge
recursively, arrays replace, `defaultTools` modifiers append, resource arrays are combined per scope,
user-only keys are dropped from the project file.

Exported functions:

```r
gptr_settings(scope = c("effective", "user", "project"), cwd = getwd())   # nested list
gptr_setting(key, default = NULL)                                         # dotted key, e.g. "compaction.reserveTokens"
gptr_set(..., scope = c("user", "project"))                               # gptr_set(defaultModel = "x"); writes only the named fields
gptr_trust(path = ".", decision = c("trust", "distrust", "forget"))
```

### 4.10 Plugins distributed as ordinary R packages (REQ-29)

Package layout (installed paths in parentheses):

```text
inst/gptr/skills/<name>/SKILL.md        (<lib>/<pkg>/gptr/skills/<name>/SKILL.md)
inst/gptr/prompts/<name>.md             (<lib>/<pkg>/gptr/prompts/<name>.md)
inst/gptr/extensions/<name>.R           (<lib>/<pkg>/gptr/extensions/<name>.R)   last expression: function(gptr)
inst/gptr/plugin.json                   optional manifest, same grammar as Pi's "pi" manifest:
                                        {"extensions": ["extensions/*.R", "!extensions/dev.R"], "skills": ["skills"], "prompts": []}
inst/skills/<name>/SKILL.md             btw-compatible location (skills only)
DESCRIPTION:  Suggests: gptr            (a plugin must not need gptr to be installed)
              Config/gptr/plugin: true  optional marker so that gptr_plugins() can label the package
```

Verified: `R CMD INSTALL` copies `inst/gptr/...` to `<lib>/<pkg>/gptr/...`; `system.file("gptr", package = )`
finds it; a custom `Config/gptr/plugin` DESCRIPTION field survives installation; an extension file
evaluates to a function (section 5.9).

Extension files of a plugin are evaluated in a fresh environment whose parent is the package namespace
(`asNamespace(pkg)`), so they can call internal and exported functions of their package without
`library()`. This loads the namespace (runs `.onLoad`), which is why extension loading is opt-in.

Discovery strategies and measured cost (615 installed packages, one library; ranges cover four runs, two by
the author and two re-runs by the verifier on the same machine):

| Strategy | First call | Median of repeats | Use |
|---|---|---|---|
| explicit list `plugins` via `system.file()` (3 packages) | 0-1 ms | 0-2 ms | **default for extensions** |
| attached packages (`.packages()`, 7 packages) | 0-1 ms | 0-1 ms | **default for skills and prompts** (same rule as btw) |
| loaded namespaces (9) | 0-1 ms | 0-1 ms | not recommended (invisible to the user) |
| all installed: vectorised `dir.exists(file.path(libs, pkgs, c("gptr","skills")))` | 3-70 ms | 2-4 ms | `gptr_plugins(installed = TRUE)` listing only |
| all installed: `Sys.glob()` | 2-3 ms | 2-4 ms | same |
| all installed: `system.file()` per package | 87-345 ms | 83-120 ms | do not use |
| all installed: `installed.packages(fields = "Config/gptr/plugin", noCache = TRUE)` | 87-130 ms | 77-119 ms | do not use at startup |

Not measured: libraries on network drives (common on managed Windows machines) and machines with several
thousand packages; both could be slower by an order of magnitude. Cache the result per session.

Feasibility verdict: scanning every installed package is technically cheap, but auto-running extension
code from every installed package would turn "installed once for some other reason" into "executes inside
every gptr session". Therefore:

- `pluginsAutoload = "attached"` (default): skills and prompts of attached packages are available;
  extensions are loaded only for packages listed in `plugins` (settings or argument).
- `pluginsAutoload = "installed"` (user setting only): skills/prompts of all installed packages are
  available; extensions still require `plugins`.
- `gptr_plugins(installed = FALSE)` returns a data.frame (`package`, `version`, `lib`, `skills`, `prompts`,
  `extensions`, `enabled`).
- gptr never installs packages. `gptr_skill_install("pkg::skill")` only copies a skill directory.

Pi's npm/git package manager is **not** ported: R already has `install.packages()`, `pak`, `renv`.
Non-package bundles (a git repository of skills) are handled by `gptr_skill_install()` (P2, download of a
tarball with `utils::download.file()` + `utils::untar()`; requires explicit user call).

### 4.11 Project trust

Gated resources: `.gptr/settings.json`, `.gptr/mcp.json`, `.gptr/extensions`, `.gptr/skills`,
`.gptr/prompts`, `.gptr/SYSTEM.md`, `.gptr/APPEND_SYSTEM.md`, and project-level `.agents/skills`,
`.claude/skills`, `.codex/skills` in cwd or an ancestor. Not gated (as in Pi): context files including
`.gptr/vignette.Rmd`, which are read as text.

Resolution order (prototyped, `resolve_project_trust()`): `gptr(trust = TRUE/FALSE)` or
`options(gptr.trust = )` > nothing to gate > `project_trust` handlers of user-level extensions > saved
decision for cwd or nearest ancestor > `defaultProjectTrust` > no UI: not trusted > console prompt with
Pi's five options. Store: `<gptr-home>/trust.json`, keys are canonical absolute paths with forward
slashes (lower-cased on Windows).

When resources were skipped because the project is untrusted and there is no UI, gptr emits one message:
`gptr: project resources in <path>/.gptr were not loaded (project not trusted). Use gptr_trust() to trust it.`

### 4.12 Run modes

| Pi mode | gptr equivalent | `ctx$mode` | `ctx$has_ui` | Output |
|---|---|---|---|---|
| interactive | `gptr()` in an interactive session (REQ-16) | `console` | `TRUE` | streamed text in the console; returns the session invisibly |
| print | `gptr("prompt")` in a script (REQ-17) | `script` | `interactive()` | returns a `gptr_result`; under `Rscript` the final text is printed by the print method |
| (none) | `gptr()` calls inside knitr/Quarto chunks | `knit` | `FALSE` | chunk output; approvals follow `permissionMode`, never prompt |
| json | `gptr("prompt", on_event = gptr_jsonl(stdout()))` or `options(gptr.on_event = )` | `script` | as above | one JSON object per line, Pi-compatible event names; header record `{"type":"session","version":1,...}` |
| rpc | `gptr_rpc()` run as `Rscript -e "gptr::gptr_rpc()"` (P2) | `rpc` | `TRUE` | Pi's command/response/event envelope and the `extension_ui_request`/`extension_ui_response` sub-protocol |
| sdk | the exported R API (`gptr_session()` object and its methods) | - | - | in-process |

`has_ui` detection (design; the behaviour of `interactive()`, `readline()`, `menu()`, `askYesNo()` that it
guards against is verified in section 5.7. The verifier ran the function as printed: `FALSE` under
`Rscript`, `FALSE` with `TESTTHAT` set, `TRUE` in `R --interactive`, and `FALSE` there once
`options(gptr.ui = FALSE)` or `options(knitr.in.progress = TRUE)` is set):

```r
gptr_has_ui <- function() {
  interactive() &&
    !isTRUE(getOption("knitr.in.progress")) &&
    !nzchar(Sys.getenv("TESTTHAT")) && !nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")) &&
    !isFALSE(getOption("gptr.ui"))
}
```

Limit of a synchronous RPC loop (verified by prototype): while a run is in progress the process does not
read stdin, so `abort`/`steer` commands are only seen between turns (or while a dialog is pending). A
client that needs immediate abort must signal the process (SIGINT). Therefore the `prompt` response should
be written **before** the run starts (as in Pi) and `agent_settled` marks completion.

### 4.13 Non-standard evaluation for names (REQ-19)

`gptr(skills = c(pdf, stats), extensions = audit, plugins = btw, tools = c(read, -write))` accepts bare
names, strings, `c(...)` mixtures, `-name`/`+name` modifiers and character variables from the caller's
scope (a variable that exists and is character wins over the symbol name). Prototyped as `names_arg()`
(section 5.10). Rule for package authors: provide `skills = !!x`-free escape by also accepting any
expression that evaluates to a character vector.

### 4.14 Package choices

| Package | Role | Recommendation |
|---|---|---|
| jsonlite | settings, trust store, JSONL, `plugin.json` | **Imports** |
| yaml | `SKILL.md` / template frontmatter | **Imports** (a hand parser rejected 12 of 65 real `SKILL.md` files, losing 4 of 37 unique skills and garbling 6 more descriptions) |
| cli | coloured console output, progress | Suggests with plain `cat()`/`message()` fallback (or Imports if another track needs it) |
| rstudioapi | native dialogs in RStudio/Positron (`showQuestion`, `showPrompt`) | Suggests; console fallback is complete |
| processx | `gptr$exec()` with timeout and kill | Suggests; `system2()` fallback (timeout argument exists in base R) |
| filelock | cross-process lock for settings/trust files | not used in v1; atomic rename + re-read-before-write instead |
| R6 / S7 | - | not needed: API objects are locked environments with an S3 class |
| rlang | - | not needed for this track (base `substitute()` suffices) |
| withr, testthat | tests | Suggests |

`Depends: R (>= 4.1)` (native pipe and `\(x)` allowed; `tools::R_user_dir()` needs 4.0).

### 4.15 Loading algorithm (pseudo-code)

```text
gptr_load_resources(cwd, args):
  home     <- gptr_home()
  user     <- read_json_file(home/settings.json)               # errors -> diagnostic, treated as {}
  pre      <- load extensions: args$extensions, user$extensions, home/extensions   (transactional factories)
  trusted  <- resolve_project_trust(cwd, override = args$trust, default = user$defaultProjectTrust,
                                    decide = emit(project_trust) over `pre`, ui)
  project  <- if trusted read_json_file(cwd/.gptr/settings.json) else {}
  settings <- merge_settings(user, project, overrides = args + options)
  ext      <- pre + [project settings extensions, .gptr/extensions] (if trusted)
                  + extensions of packages in settings$plugins + built-ins not disabled by "-builtin:x"
             (drop replaceable built-ins whose tool/command/flag names are taken; record conflicts)
  skills   <- load_skills(dirs in precedence order of section 4.3)            # yaml, first name wins
  prompts  <- load_templates(...)
  context  <- load_context_files(cwd, home)                                   # not trust-gated
  system   <- SYSTEM.md / APPEND_SYSTEM.md: project file (if trusted) else user file; never combined
  bind: runtime$bound <- TRUE; flush queued provider registrations
  emit(session_start, reason = "startup"); emit(resources_discover) -> extend skills/prompts

gptr_reload(): emit(session_shutdown, reason = "reload"); mark old API objects stale
               (every method then errors with an explanatory message); run gptr_load_resources();
               emit(session_start, reason = "reload")
```

---

## 5. Verified R prototypes

All code in this section was executed exactly as printed (the code blocks were spliced into this report
from the files that were run; outputs are the captured stdout/stderr with temporary directory names
replaced by `<tmp>`). Command for every script: `Rscript --vanilla <file>` in `$W`, R 4.4.3, macOS arm64.
The default environment of these runs has **no `LANG`**, so R runs in the `C` locale; scripts that are
encoding-sensitive were run a second time with `LANG=en_US.UTF-8`.

All sources are pure ASCII. Note for implementers: write non-ASCII test data with `intToUtf8()` or `\u`
escapes. A first version of the template test file contained literal non-ASCII characters and failed in
the C locale because the R parser read them in the native encoding.

| File | Purpose | Result |
|---|---|---|
| `02-templates.R` | argument parser, substitution, template expansion | 67 assertions pass in C and UTF-8 locales |
| `02b-encoding.R` | which base functions are safe for UTF-8 text in a C locale | see 5.1 |
| `01-skills.R` | frontmatter, discovery, validation, catalog, `/skill:` expansion | expected skills and diagnostics |
| `01b-real-skills.R` | loader against real skill folders of other agents | 37 skills (yaml) vs 33 (hand parser) |
| `03-settings.R` | JSON settings merge, `defaultTools`, field-level write, format comparison | all `stopifnot` pass |
| `04-extensions.R` | extension runtime (API object, dispatch, tool pipeline, mock agent loop) | used by 04b |
| `04b-examples.R` | permission gate, plan mode, ask-user, todo, input transform, redaction + test run | 38 checks ok |
| `07-codecalls.R` | static R code classifier | verdicts as expected |
| `06-ui.R` | console dialogs; non-interactive behaviour of base functions | see 5.7 |
| `08-trust.R` | home directory, trust store, trust resolution, context files | all `stopifnot` pass |
| `05-pkgscan.R` | cost of scanning installed packages; plugin package install test | see 5.9 |
| `09-modes.R` | NSE names, JSONL sink, RPC loop with UI sub-protocol | see 5.10 |
| `10-patterns.R` | `!`/`+`/`-` resource filters | all `stopifnot` pass |

### 5.1 Prompt templates: `02-templates.R`

```r
# Prototype: prompt-template argument parsing + substitution (port of Pi prompt-templates.ts)
# Base R only.

# --- parse_command_args: bash-style quoting, no escape processing (matches Pi) ----
parse_command_args <- function(x) {
  stopifnot(is.character(x), length(x) == 1L)
  chars <- strsplit(enc2utf8(x), "", fixed = TRUE)[[1L]]
  args <- character()
  cur <- ""
  in_quote <- NULL
  for (ch in chars) {
    if (!is.null(in_quote)) {
      if (identical(ch, in_quote)) in_quote <- NULL else cur <- paste0(cur, ch)
    } else if (ch == "\"" || ch == "'") {
      in_quote <- ch
    } else if (grepl("^\\s$", ch, perl = TRUE)) {
      if (nzchar(cur)) { args <- c(args, cur); cur <- "" }
    } else {
      cur <- paste0(cur, ch)
    }
  }
  if (nzchar(cur)) args <- c(args, cur)
  args
}

# --- substitute_args ---------------------------------------------------------------
TEMPLATE_RE <- "\\$\\{(\\d+|ARGUMENTS|@):-([^}]*)\\}|\\$\\{@:(\\d+)(?::(\\d+))?\\}|\\$(ARGUMENTS|@|\\d+)"

substitute_args <- function(content, args = character()) {
  # Locale-independent: matching is done on UTF-8 *bytes* (useBytes = TRUE), the pieces are
  # assembled by hand and the result is re-marked as UTF-8, so the outcome does not depend on
  # the session locale or on the encoding marks of the inputs.
  stopifnot(is.character(content), length(content) == 1L)
  content <- enc2utf8(content)
  args <- enc2utf8(as.character(args))
  mark <- function(x) { Encoding(x) <- "UTF-8"; x }
  all_args <- paste(args, collapse = " ")
  m <- gregexpr(TEMPLATE_RE, content, perl = TRUE, useBytes = TRUE)[[1L]]
  if (m[1L] == -1L) return(mark(content))
  raw <- charToRaw(content)
  ml <- attr(m, "match.length")
  cs <- attr(m, "capture.start"); cl <- attr(m, "capture.length")
  bytes <- function(start, len) if (len <= 0L) "" else rawToChar(raw[seq.int(start, length.out = len)])
  has <- function(i, j) cs[i, j] > 0L            # unset PCRE group => capture.start <= 0
  grp <- function(i, j) bytes(cs[i, j], cl[i, j])
  pick <- function(idx) if (!is.na(idx) && idx >= 1 && idx <= length(args)) args[idx] else ""
  out <- character(); pos <- 1L
  for (i in seq_along(m)) {
    out <- c(out, bytes(pos, m[i] - pos))
    if (has(i, 1L)) {                              # ${N:-default} | ${@:-default} | ${ARGUMENTS:-default}
      target <- grp(i, 1L)
      value <- if (target %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(target))
      rep <- if (nzchar(value)) value else grp(i, 2L)
    } else if (has(i, 3L)) {                       # ${@:N} | ${@:N:L}  (1-indexed, 0 treated as 1)
      start <- max(1, as.numeric(grp(i, 3L)))
      end <- if (has(i, 4L)) start + as.numeric(grp(i, 4L)) - 1 else length(args)
      end <- min(end, length(args))
      rep <- if (start <= end) paste(args[seq.int(start, end)], collapse = " ") else ""
    } else {                                       # $N | $@ | $ARGUMENTS
      simple <- grp(i, 5L)
      rep <- if (simple %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(simple))
    }
    out <- c(out, rep)
    pos <- m[i] + ml[i]
  }
  out <- c(out, bytes(pos, length(raw) - pos + 1L))
  Encoding(out) <- "bytes"
  mark(paste(vapply(out, function(z) { Encoding(z) <- "unknown"; z }, ""), collapse = ""))
}

expand_prompt_template <- function(text, templates) {
  # templates: named list name -> list(content=)
  if (!startsWith(text, "/")) return(text)
  mm <- regmatches(text, regexec("^/([^\\s]+)(?:\\s+([\\s\\S]*))?$", text, perl = TRUE))[[1L]]
  if (!length(mm)) return(text)
  name <- mm[2L]; argstr <- if (length(mm) >= 3L && !is.na(mm[3L])) mm[3L] else ""
  tpl <- templates[[name]]
  if (is.null(tpl)) return(text)
  substitute_args(tpl$content, parse_command_args(argstr))
}

# --- tests (ported from pi/packages/coding-agent/test/prompt-templates.test.ts) ----
n_ok <- 0L; n_fail <- 0L
expect <- function(got, want, label = "") {
  same <- identical(length(got), length(want)) &&
    all(vapply(seq_along(got), function(i) identical(charToRaw(enc2utf8(got[i])), charToRaw(enc2utf8(want[i]))), NA))
  if (same) n_ok <<- n_ok + 1L else {
    n_fail <<- n_fail + 1L
    cat("FAIL", label, "\n  got : ", deparse(got), "\n  want: ", deparse(want), "\n")
  }
}
S <- substitute_args
expect(S("Test: $ARGUMENTS", c("a","b","c")), "Test: a b c")
expect(S("Test: $@", c("a","b","c")), "Test: a b c")
expect(S("$ARGUMENTS", c("$1","$ARGUMENTS")), "$1 $ARGUMENTS", "no recursion")
expect(S("$@", c("$100","$1")), "$100 $1")
expect(S("$1: $ARGUMENTS", c("prefix","a","b")), "prefix: prefix a b")
expect(S("Test: $ARGUMENTS", character()), "Test: ")
expect(S("Test: $1", character()), "Test: ")
expect(S("$1 $2 $3 $4 $5", c("a","b")), "a b   ")
expect(S("$ARGUMENTS", c("\u65e5\u672c\u8a9e", "\U0001F389", "caf\u00e9")), "\u65e5\u672c\u8a9e \U0001F389 caf\u00e9", "unicode")
expect(S("$1 $2", c("line1\nline2", "tab\tthere")), "line1\nline2 tab\tthere")
expect(S("$1$2", c("a","b")), "ab")
expect(S("$0", c("a","b")), "", "$0 empty")
expect(S("$1.5", "a"), "a.5")
expect(S("pre$ARGUMENTS", c("a","b")), "prea b")
expect(S("$ARGUMENTS", c("a","","c")), "a  c")
expect(S("$A $$ $ $ARGS", "a"), "$A $$ $ $ARGS")
expect(S("$arguments $Arguments $ARGUMENTS", c("a","b")), "$arguments $Arguments a b")
expect(S("$10 $12 $15", paste0("val", 0:19)), "val9 val11 val14")
expect(S("Price: \\$100", character()), "Price: \\")
expect(S("Just plain text", c("a","b")), "Just plain text")
expect(S("$1 $2 $@", c("a","b","c")), "a b a b c")
expect(S("List exactly ${1:-7} next steps", character()), "List exactly 7 next steps")
expect(S("List exactly ${1:-7} next steps", "3"), "List exactly 3 next steps")
expect(S("Mode: ${1:-brief}", ""), "Mode: brief", "empty arg uses default")
expect(S("${1:-7} ${2:-brief}", "3"), "3 brief")
expect(S("${1:-7}", "$ARGUMENTS"), "$ARGUMENTS")
expect(S("${1:-$ARGUMENTS}", c("a","b")), "a")
expect(S("${3:-$ARGUMENTS}", c("a","b")), "$ARGUMENTS", "default not recursively substituted")
expect(S("${1:-seven steps}", character()), "seven steps")
expect(S("$1 ${2:-x} $ARGUMENTS", "a"), "a x a")
expect(S("${@:-all default}", character()), "all default")
expect(S("${ARGUMENTS:-d}", c("q","r")), "q r")
expect(S("${@:2}", c("a","b","c","d")), "b c d")
expect(S("${@:1}", c("a","b","c")), "a b c")
expect(S("${@:2:2}", c("a","b","c","d")), "b c")
expect(S("${@:3:1}", c("a","b","c","d")), "c")
expect(S("${@:99}", c("a","b")), "")
expect(S("${@:10:5}", c("a","b")), "")
expect(S("${@:2:0}", c("a","b","c")), "")
expect(S("${@:2:99}", c("a","b","c")), "b c")
expect(S("${@:2} vs $@", c("a","b","c")), "b c vs a b c")
expect(S("${@:1}", c("${@:2}", "test")), "${@:2} test")
expect(S("${@:0}", c("a","b","c")), "a b c", "0 treated as 1")
expect(S("${@:2}", character()), "")
expect(S("${@:2}", "only"), "")
expect(S("prefix${@:2}suffix", c("a","b","c")), "prefixb csuffix")
expect(S("${@:5:100}", paste0("arg", 1:10)), "arg5 arg6 arg7 arg8 arg9 arg10")

P <- parse_command_args
expect(P("a b c"), c("a","b","c"))
expect(P('"first arg" second'), c("first arg","second"))
expect(P("'first arg' second"), c("first arg","second"))
expect(P('"double" \'single\' "double again"'), c("double","single","double again"))
expect(P(""), character())
expect(P("a  b   c"), c("a","b","c"))
expect(P("a\tb\tc"), c("a","b","c"))
expect(P('"" " "'), " ")
expect(P("$100 @user #tag"), c("$100","@user","#tag"))
expect(P('"line1\nline2" second'), c("line1\nline2","second"))
expect(P("a\n\n\tb  c"), c("a","b","c"))
expect(P('"quoted \\"text\\""'), "quoted \\text\\")
expect(P("   a b c   "), c("a","b","c"))
expect(P("\u65e5\u672c\u8a9e \U0001F389 caf\u00e9"), c("\u65e5\u672c\u8a9e", "\U0001F389", "caf\u00e9"), "unicode args")

tpls <- list(review = list(content = "Review the staged changes. Focus on ${1:-correctness, security, and error handling}."))
expect(expand_prompt_template("/review", tpls), "Review the staged changes. Focus on correctness, security, and error handling.")
expect(expand_prompt_template("/review concurrency", tpls), "Review the staged changes. Focus on concurrency.")
expect(expand_prompt_template("/review \"API compatibility\"", tpls), "Review the staged changes. Focus on API compatibility.")
expect(expand_prompt_template("/unknown x", tpls), "/unknown x")
expect(expand_prompt_template("not a command", tpls), "not a command")
expect(expand_prompt_template("/review multi\nline arg", tpls), "Review the staged changes. Focus on multi.")

cat(sprintf("templates: %d passed, %d failed\n", n_ok, n_fail))
```

Observed output (C locale, then `LANG=en_US.UTF-8`):

```text
templates: 67 passed, 0 failed
templates: 67 passed, 0 failed
```

Encoding experiment `02b-encoding.R`:

```r
# Experiment: what base R string functions do to non-ASCII text in a C locale. ASCII-only source.
cat("locale:", Sys.getlocale("LC_CTYPE"), " UTF-8 locale:", l10n_info()[["UTF-8"]], "\n")
E_ACUTE <- intToUtf8(0xE9L); KANJI <- intToUtf8(0x65E5L)          # both marked UTF-8
want <- paste0("caf", E_ACUTE, " ", KANJI)
hex <- function(x) paste(as.character(charToRaw(x)), collapse = " ")
cat("expected bytes           :", hex(enc2utf8(want)), "\n")
x <- paste0("caf", E_ACUTE, " $1")
m <- gregexpr("\\$1", x, perl = TRUE)
y <- x; regmatches(y, m) <- list(KANJI)
cat("regmatches<-             : Encoding =", Encoding(y), "| bytes:", hex(y), "\n")
z <- sub("\\$1", KANJI, x, perl = TRUE)
cat("sub()                    : Encoding =", Encoding(z), "| bytes:", hex(z), "\n")
zb <- sub("\\$1", KANJI, x, perl = TRUE, useBytes = TRUE); Encoding(zb) <- "UTF-8"
cat("sub(useBytes=TRUE)+mark  : Encoding =", Encoding(zb), "| bytes:", hex(zb), "\n")
tf <- tempfile()
cat(want, "\n", file = tf, sep = "")
cat("cat(file=) wrote         :", hex(rawToChar(readBin(tf, "raw", 100))), "\n")
writeLines(enc2utf8(want), tf, useBytes = TRUE)
cat("writeLines(useBytes) wrote:", hex(rawToChar(readBin(tf, "raw", 100))), "\n")
a <- readLines(tf, warn = FALSE); b <- readLines(tf, warn = FALSE, encoding = "UTF-8")
cat("readLines() default      : Encoding =", Encoding(a), " nchar =", nchar(a, "chars", allowNA = TRUE), "\n")
cat("readLines(encoding=UTF-8): Encoding =", Encoding(b), " nchar =", nchar(b, "chars"), "\n")
```

Observed output, C locale:

```text
locale: C  UTF-8 locale: FALSE 
expected bytes           : 63 61 66 c3 a9 20 e6 97 a5 
regmatches<-             : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
sub()                    : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
sub(useBytes=TRUE)+mark  : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
cat(file=) wrote         : 63 61 66 3c 55 2b 30 30 45 39 3e 20 3c 55 2b 36 35 45 35 3e 0a 
writeLines(useBytes) wrote: 63 61 66 c3 a9 20 e6 97 a5 0a 
readLines() default      : Encoding = unknown  nchar = 9 
readLines(encoding=UTF-8): Encoding = UTF-8  nchar = 6 
```

Observed output, `LANG=en_US.UTF-8`:

```text
locale: en_US.UTF-8  UTF-8 locale: TRUE 
expected bytes           : 63 61 66 c3 a9 20 e6 97 a5 
regmatches<-             : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
sub()                    : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
sub(useBytes=TRUE)+mark  : Encoding = UTF-8 | bytes: 63 61 66 c3 a9 20 e6 97 a5 
cat(file=) wrote         : 63 61 66 c3 a9 20 e6 97 a5 0a 
writeLines(useBytes) wrote: 63 61 66 c3 a9 20 e6 97 a5 0a 
readLines() default      : Encoding = unknown  nchar = 6 
readLines(encoding=UTF-8): Encoding = UTF-8  nchar = 6 
```

Conclusions (VERIFIED): with correctly UTF-8-marked strings `sub()`, `regmatches<-` and `paste0()` keep the
bytes intact even in a C locale; **`cat()` does not** (it wrote `<U+00E9>` and `<U+65E5>` escapes), and
`readLines()` without `encoding = "UTF-8"` returns unmarked strings (`nchar` 9 instead of 6 in the C
locale). Rules for gptr: read text with `readBin()` + `rawToChar()` + `Encoding<- "UTF-8"` (or
`readLines(encoding = "UTF-8")`), write with `writeLines(enc2utf8(x), con, useBytes = TRUE)`, never `cat()`
model text into files or protocol streams.

### 5.2 Skills: `01-skills.R` and `01b-real-skills.R`

```r
# Prototype: frontmatter parsing + Agent-Skills discovery + catalog rendering. ASCII-only source.
# Uses 'yaml' when installed, else a minimal flat "key: value" fallback parser.

read_text_utf8 <- function(path) {
  raw <- readBin(path, "raw", n = file.size(path))
  if (length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) raw <- raw[-(1:3)]  # BOM
  raw <- raw[raw != as.raw(0)]
  x <- rawToChar(raw)
  Encoding(x) <- "UTF-8"
  if (!validUTF8(x)) x <- iconv(x, "latin1", "UTF-8")
  x <- gsub("\r\n?", "\n", x, useBytes = TRUE)
  Encoding(x) <- "UTF-8"
  x
}

split_frontmatter <- function(text) {
  # Same rule as Pi utils/frontmatter.ts: must start with '---', ends at first "\n---".
  if (!startsWith(text, "---")) return(list(yaml = NULL, body = text))
  end <- regexpr("\n---", substring(text, 4L), fixed = TRUE, useBytes = TRUE)
  if (end < 0L) return(list(yaml = NULL, body = text))
  b <- charToRaw(text)
  end_abs <- 3L + end                     # byte index of the "\n" that precedes closing ---
  yaml <- rawToChar(b[seq.int(5L, length.out = max(0L, end_abs - 5L))])
  rest <- if (end_abs + 4L <= length(b)) rawToChar(b[seq.int(end_abs + 4L, length(b))]) else ""
  Encoding(yaml) <- "UTF-8"; Encoding(rest) <- "UTF-8"
  list(yaml = yaml, body = trimws(rest))
}

parse_yaml_minimal <- function(y) {
  # Flat scalars, quoted strings, booleans, one-level "key:\n  sub: v" maps, "- item" lists.
  out <- list(); cur <- NULL
  for (ln in strsplit(y, "\n", fixed = TRUE)[[1L]]) {
    if (!nzchar(trimws(ln)) || grepl("^\\s*#", ln)) next
    unq <- function(v) {
      v <- trimws(v)
      if (grepl("^\".*\"$", v) || grepl("^'.*'$", v)) return(substr(v, 2L, nchar(v) - 1L))
      if (v %in% c("true", "True", "TRUE")) return(TRUE)
      if (v %in% c("false", "False", "FALSE")) return(FALSE)
      v
    }
    if (grepl("^\\s+-\\s+", ln) && !is.null(cur)) {
      out[[cur]] <- c(out[[cur]], unq(sub("^\\s+-\\s+", "", ln))); next
    }
    if (grepl("^\\s+[^:]+:", ln) && !is.null(cur)) {
      kv <- regmatches(ln, regexec("^\\s+([^:]+):\\s*(.*)$", ln))[[1L]]
      if (!is.list(out[[cur]])) out[[cur]] <- list()
      out[[cur]][[trimws(kv[2L])]] <- unq(kv[3L]); next
    }
    kv <- regmatches(ln, regexec("^([A-Za-z0-9_-]+):\\s*(.*)$", ln))[[1L]]
    if (length(kv) == 3L) {
      cur <- kv[2L]
      out[cur] <- list(if (nzchar(trimws(kv[3L]))) unq(kv[3L]) else NULL)
      if (is.null(out[[cur]])) out[cur] <- list(NULL)
    } else if (!is.null(cur) && is.character(out[[cur]])) {
      out[[cur]] <- paste(out[[cur]], trimws(ln))      # folded continuation line
    }
  }
  out
}

parse_frontmatter <- function(text, use_yaml = requireNamespace("yaml", quietly = TRUE)) {
  sp <- split_frontmatter(text)
  if (is.null(sp$yaml)) return(list(frontmatter = list(), body = sp$body, repaired = FALSE))
  repaired <- FALSE
  fm <- NULL
  if (use_yaml) {
    fm <- tryCatch(yaml::yaml.load(sp$yaml), error = function(e) e)
    if (inherits(fm, "error")) {
      # agentskills.io "Handling malformed YAML": quote unquoted scalar values containing ': '
      fixed <- vapply(strsplit(sp$yaml, "\n", fixed = TRUE)[[1L]], function(ln) {
        kv <- regmatches(ln, regexec("^([A-Za-z0-9_-]+):\\s+([^\"'|>\\[{].*:.*)$", ln))[[1L]]
        if (length(kv) == 3L) sprintf("%s: \"%s\"", kv[2L], gsub("([\"\\\\])", "\\\\\\1", kv[3L])) else ln
      }, "", USE.NAMES = FALSE)
      fm <- tryCatch(yaml::yaml.load(paste(fixed, collapse = "\n")), error = function(e) e)
      repaired <- !inherits(fm, "error")
    }
    if (inherits(fm, "error")) stop("invalid YAML frontmatter: ", conditionMessage(fm), call. = FALSE)
  } else {
    fm <- parse_yaml_minimal(sp$yaml)
  }
  if (is.null(fm) || !is.list(fm)) fm <- list()
  list(frontmatter = fm, body = sp$body, repaired = repaired)
}

validate_skill_name <- function(name) {
  e <- character()
  if (nchar(name) > 64L) e <- c(e, sprintf("name exceeds 64 characters (%d)", nchar(name)))
  if (!grepl("^[a-z0-9-]+$", name)) e <- c(e, "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)")
  if (startsWith(name, "-") || endsWith(name, "-")) e <- c(e, "name must not start or end with a hyphen")
  if (grepl("--", name, fixed = TRUE)) e <- c(e, "name must not contain consecutive hyphens")
  e
}

load_skill_file <- function(path, source = "path", scope = "user") {
  diag <- character()
  declared <- basename(path) == "SKILL.md"
  text <- tryCatch(read_text_utf8(path), error = function(e) e)
  if (inherits(text, "error")) return(list(skill = NULL, diagnostics = conditionMessage(text)))
  p <- tryCatch(parse_frontmatter(text), error = function(e) e)
  if (inherits(p, "error")) return(list(skill = NULL, diagnostics = if (declared) conditionMessage(p) else character()))
  fm <- p$frontmatter
  desc <- fm[["description"]]
  has_desc <- is.character(desc) && length(desc) == 1L && nzchar(trimws(desc))
  if (!declared && !has_desc) return(list(skill = NULL, diagnostics = character()))
  if (!has_desc) return(list(skill = NULL, diagnostics = "description is required"))
  if (nchar(desc) > 1024L) diag <- c(diag, sprintf("description exceeds 1024 characters (%d)", nchar(desc)))
  base_dir <- dirname(path)
  name <- if (is.character(fm[["name"]]) && nzchar(fm[["name"]])) fm[["name"]] else basename(base_dir)
  diag <- c(diag, validate_skill_name(name))
  if (p$repaired) diag <- c(diag, "frontmatter was not valid YAML; repaired by quoting values")
  list(skill = list(
    name = name, description = desc, file_path = path, base_dir = base_dir,
    source = source, scope = scope,
    disable_model_invocation = isTRUE(fm[["disable-model-invocation"]]),
    allowed_tools = fm[["allowed-tools"]], compatibility = fm[["compatibility"]],
    license = fm[["license"]], metadata = fm[["metadata"]]
  ), diagnostics = diag)
}

SKIP_DIRS <- c("node_modules", "renv", "packrat", "__pycache__")

discover_skill_files <- function(dir, root_md = TRUE, max_depth = 6L, max_dirs = 2000L) {
  # Pi semantics: a dir containing SKILL.md is a skill root (no further recursion);
  # root_md = TRUE additionally accepts direct *.md children of the scan root ("pi" mode).
  if (!dir.exists(dir)) return(character())
  seen <- 0L
  walk <- function(d, depth) {
    seen <<- seen + 1L
    if (seen > max_dirs || depth > max_depth) return(character())
    sk <- file.path(d, "SKILL.md")
    if (file.exists(sk) && !dir.exists(sk)) return(sk)
    ent <- list.files(d, all.files = FALSE, full.names = TRUE, no.. = TRUE)   # skips dotfiles
    isdir <- dir.exists(ent)
    out <- character()
    if (depth == 0L && root_md) out <- ent[!isdir & grepl("\\.md$", ent)]
    for (s in ent[isdir]) if (!basename(s) %in% SKIP_DIRS) out <- c(out, walk(s, depth + 1L))
    out
  }
  walk(normalizePath(dir, winslash = "/", mustWork = TRUE), 0L)
}

load_skills <- function(dirs) {
  # dirs: data.frame(path, scope, source, root_md) in PRECEDENCE ORDER (first wins on collision).
  skills <- list(); diags <- list(); real_seen <- character()
  for (i in seq_len(nrow(dirs))) {
    for (f in discover_skill_files(dirs$path[i], root_md = dirs$root_md[i])) {
      r <- load_skill_file(f, source = dirs$source[i], scope = dirs$scope[i])
      for (d in r$diagnostics) diags[[length(diags) + 1L]] <- list(type = "warning", message = d, path = f)
      if (is.null(r$skill)) next
      real <- normalizePath(f, winslash = "/", mustWork = FALSE)
      if (real %in% real_seen) next                           # same file through symlink: silent
      if (!is.null(skills[[r$skill$name]])) {
        diags[[length(diags) + 1L]] <- list(type = "collision",
          message = sprintf("name \"%s\" collision", r$skill$name), path = f,
          winner = skills[[r$skill$name]]$file_path)
        next
      }
      skills[[r$skill$name]] <- r$skill
      real_seen <- c(real_seen, real)
    }
  }
  list(skills = skills, diagnostics = diags)
}

escape_xml <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE); x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&apos;", x, fixed = TRUE)
}

format_skills_for_prompt <- function(skills, read_tool = "read") {
  vis <- Filter(function(s) !isTRUE(s$disable_model_invocation), skills)
  if (!length(vis)) return("")
  c(
    "The following skills provide specialized instructions for specific tasks.",
    sprintf("Use the %s tool to load a skill's file when the task matches its description.", read_tool),
    "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.",
    "", "<available_skills>",
    unlist(lapply(vis, function(s) c("  <skill>",
      sprintf("    <name>%s</name>", escape_xml(s$name)),
      sprintf("    <description>%s</description>", escape_xml(s$description)),
      sprintf("    <location>%s</location>", escape_xml(s$file_path)),
      "  </skill>")), use.names = FALSE),
    "</available_skills>") |> paste(collapse = "\n")
}

expand_skill_command <- function(text, skills) {
  if (!startsWith(text, "/skill:")) return(text)
  sp <- regexpr(" ", text, fixed = TRUE)
  name <- if (sp < 0L) substring(text, 8L) else substring(text, 8L, sp - 1L)
  args <- if (sp < 0L) "" else trimws(substring(text, sp + 1L))
  s <- skills[[name]]
  if (is.null(s)) return(text)
  body <- trimws(parse_frontmatter(read_text_utf8(s$file_path))$body)
  block <- sprintf("<skill name=\"%s\" location=\"%s\">\nReferences are relative to %s.\n\n%s\n</skill>",
                   s$name, s$file_path, s$base_dir, body)
  if (nzchar(args)) paste0(block, "\n\n", args) else block
}

# ---------------------------------------------------------------- tests
if (sys.nframe() == 0L) {
  td <- file.path(tempdir(), "sk"); unlink(td, recursive = TRUE); dir.create(td)
  mk <- function(rel, txt) { p <- file.path(td, rel); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeLines(txt, p, useBytes = TRUE); p }
  mk("proj/.gptr/skills/pdf-tools/SKILL.md", c("---", "name: pdf-tools", "description: Extract text & tables from <PDF> files. Use when reading PDFs.", "license: MIT", "metadata:", "  author: me", "  version: \"1.0\"", "---", "", "# PDF tools", "Read `references/formats.md`."))
  mk("proj/.gptr/skills/pdf-tools/references/formats.md", "should not be treated as a skill")
  mk("proj/.gptr/skills/standalone.md", c("---", "name: standalone", "description: A standalone markdown skill", "---", "body"))
  mk("proj/.gptr/skills/README.md", "# no frontmatter: ignored")
  mk("proj/.gptr/skills/nodesc/SKILL.md", c("---", "name: nodesc", "---", "x"))
  mk("proj/.gptr/skills/Bad_Name/SKILL.md", c("---", "description: name falls back to dir and fails validation", "---", "x"))
  mk("proj/.gptr/skills/colon/SKILL.md", c("---", "name: colon", "description: Use this skill when: the user asks about PDFs", "---", "x"))
  mk("proj/.gptr/skills/manual/SKILL.md", c("---", "name: manual", "description: only by command", "disable-model-invocation: true", "---", "Manual body"))
  mk("user/skills/pdf-tools/SKILL.md", c("---", "name: pdf-tools", "description: user-level duplicate", "---", "x"))
  mk("proj/.gptr/skills/crlf/SKILL.md", paste0("\xEF\xBB\xBF---\r\nname: crlf\r\ndescription: BOM and CRLF\r\n---\r\nbody\r\n"))

  dirs <- data.frame(path = file.path(td, c("proj/.gptr/skills", "user/skills")),
                     scope = c("project", "user"), source = "auto", root_md = TRUE)
  for (use_yaml in c(TRUE, FALSE)) {
    cat("\n== use_yaml =", use_yaml, "\n")
    body(parse_frontmatter)  # no-op
    formals(parse_frontmatter)$use_yaml <- use_yaml
    r <- load_skills(dirs)
    cat("skills:", paste(names(r$skills), collapse = ", "), "\n")
    for (d in r$diagnostics) cat(sprintf("  [%s] %s (%s)\n", d$type, d$message, sub(td, "", d$path, fixed = TRUE)))
    cat("pdf-tools scope:", r$skills[["pdf-tools"]]$scope, "| metadata$version:", r$skills[["pdf-tools"]]$metadata$version, "\n")
  }
  formals(parse_frontmatter)$use_yaml <- TRUE
  r <- load_skills(dirs)
  cat("\n", gsub(td, "<tmp>", format_skills_for_prompt(r$skills), fixed = TRUE), "\n", sep = "")
  cat("\n", gsub(td, "<tmp>", expand_skill_command("/skill:manual do the thing", r$skills), fixed = TRUE), "\n", sep = "")
}
```

Observed output:

```text

== use_yaml = TRUE 
skills: standalone, Bad_Name, colon, crlf, manual, pdf-tools 
  [warning] name contains invalid characters (must be lowercase a-z, 0-9, hyphens only) (<tmp>/sk/proj/.gptr/skills/Bad_Name/SKILL.md)
  [warning] frontmatter was not valid YAML; repaired by quoting values (<tmp>/sk/proj/.gptr/skills/colon/SKILL.md)
  [warning] description is required (<tmp>/sk/proj/.gptr/skills/nodesc/SKILL.md)
  [collision] name "pdf-tools" collision (<tmp>/sk/user/skills/pdf-tools/SKILL.md)
pdf-tools scope: project | metadata$version: 1.0 

== use_yaml = FALSE 
skills: standalone, Bad_Name, colon, crlf, manual, pdf-tools 
  [warning] name contains invalid characters (must be lowercase a-z, 0-9, hyphens only) (<tmp>/sk/proj/.gptr/skills/Bad_Name/SKILL.md)
  [warning] description is required (<tmp>/sk/proj/.gptr/skills/nodesc/SKILL.md)
  [collision] name "pdf-tools" collision (<tmp>/sk/user/skills/pdf-tools/SKILL.md)
pdf-tools scope: project | metadata$version: 1.0 

The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.

<available_skills>
  <skill>
    <name>standalone</name>
    <description>A standalone markdown skill</description>
    <location><tmp>/sk/proj/.gptr/skills/standalone.md</location>
  </skill>
  <skill>
    <name>Bad_Name</name>
    <description>name falls back to dir and fails validation</description>
    <location><tmp>/sk/proj/.gptr/skills/Bad_Name/SKILL.md</location>
  </skill>
  <skill>
    <name>colon</name>
    <description>Use this skill when: the user asks about PDFs</description>
    <location><tmp>/sk/proj/.gptr/skills/colon/SKILL.md</location>
  </skill>
  <skill>
    <name>crlf</name>
    <description>BOM and CRLF</description>
    <location><tmp>/sk/proj/.gptr/skills/crlf/SKILL.md</location>
  </skill>
  <skill>
    <name>pdf-tools</name>
    <description>Extract text &amp; tables from &lt;PDF&gt; files. Use when reading PDFs.</description>
    <location><tmp>/sk/proj/.gptr/skills/pdf-tools/SKILL.md</location>
  </skill>
</available_skills>

<skill name="manual" location="<tmp>/sk/proj/.gptr/skills/manual/SKILL.md">
References are relative to <tmp>/sk/proj/.gptr/skills/manual.

Manual body
</skill>

do the thing
```

What this shows: `README.md` without frontmatter is ignored; `references/formats.md` inside a skill root
is not scanned; BOM + CRLF are handled; the unquoted-colon description is repaired with `yaml`; a missing
description rejects the skill; an invalid name only warns; the project skill wins over the user skill of
the same name; XML escaping works; `disable-model-invocation` hides `manual` from the catalog while
`/skill:manual` still expands.

Real-world run `01b-real-skills.R` (prints counts and names only):

```r
# Run the skill loader against real skill folders installed by other agents on this machine.
# Prints counts, names and diagnostics only (no skill bodies).
source("01-skills.R")
home <- Sys.getenv("HOME")
pi_repo <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
dirs <- data.frame(
  path = c(file.path(pi_repo, ".pi/skills"), file.path(home, ".agents/skills"),
           file.path(home, ".claude/skills"), file.path(home, ".codex/skills")),
  scope = c("project", "user", "user", "user"),
  source = c("pi", "agents", "claude", "codex"),
  root_md = c(TRUE, FALSE, TRUE, FALSE)
)
for (use_yaml in c(TRUE, FALSE)) {
  formals(parse_frontmatter)$use_yaml <- use_yaml
  t <- system.time(r <- load_skills(dirs))
  cat(sprintf("\nuse_yaml=%s: %d skills, %d diagnostics, %.3fs elapsed\n", use_yaml, length(r$skills), length(r$diagnostics), t[["elapsed"]]))
  tab <- table(vapply(r$skills, function(s) s$source, ""))
  print(tab)
  types <- table(vapply(r$diagnostics, function(d) d$type, ""))
  print(types)
  msgs <- vapply(Filter(function(d) d$type != "collision", r$diagnostics), function(d) d$message, "")
  if (length(msgs)) print(table(substr(msgs, 1, 70)))
  if (use_yaml) res_yaml <- r else res_min <- r
}
same_names <- setequal(names(res_yaml$skills), names(res_min$skills))
cat("\nsame skill set with both parsers:", same_names, "\n")
d1 <- vapply(res_yaml$skills, function(s) s$description, "")
d2 <- vapply(res_min$skills[names(res_yaml$skills)], function(s) if (is.null(s)) NA_character_ else s$description, "")
cat("descriptions identical:", sum(d1 == d2, na.rm = TRUE), "of", length(d1), "\n")
diff <- names(d1)[is.na(d2) | d1 != d2]
if (length(diff)) cat("differ:", paste(head(diff, 10), collapse = ", "), "\n")
cat("catalog size (chars):", nchar(format_skills_for_prompt(res_yaml$skills)), " approx tokens:", round(nchar(format_skills_for_prompt(res_yaml$skills)) / 4), "\n")
cat("max description length:", max(nchar(d1)), "\n")
fm_keys <- sort(table(unlist(lapply(res_yaml$skills, function(s) {
  names(parse_frontmatter(read_text_utf8(s$file_path))$frontmatter)
}))), decreasing = TRUE)
cat("frontmatter keys seen in the wild:\n"); print(fm_keys)
```

Observed output:

```text

use_yaml=TRUE: 37 skills, 31 diagnostics, 0.215s elapsed

agents claude  codex     pi 
    19      4     11      3 

collision 
       31 

use_yaml=FALSE: 33 skills, 35 diagnostics, 0.153s elapsed

agents claude  codex     pi 
    15      4     11      3 

collision   warning 
       23        12 

description is required 
                     12 

same skill set with both parsers: FALSE 
descriptions identical: 27 of 37 
differ: general-video, hyperframes, hyperframes-audio, hyperframes-cli, hyperframes-keyframes, motion-graphics, remotion-to-hyperframes, slideshow, destiny-liuren, destiny-mbti 
catalog size (chars): 23552  approx tokens: 5888 
max description length: 792 
frontmatter keys seen in the wild:

description        name        tags     version 
         37          37           2           2 
```

Additional shell check of the description style in those files (`awk` over the frontmatter of every
`SKILL.md` under `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`): 21 of the 65 visible files have
`description: >` (folded block scalar with the text on the following lines); the rest are inline plain or
quoted scalars. This is why the hand-written parser fails and `yaml` must be an Import. (Verifier
recount: 71 `SKILL.md` files exist in total, 19 + 19 + 33; 6 of them sit under the hidden
`~/.codex/skills/.system` directory, which both Pi and this loader skip. The 68 files the loader saw are
those 65 plus Pi's 3 standalone `.md` skills. The hand parser rejects a folded description whenever a
continuation line contains a colon (it is read as a nested key), which happened in 12 files; the other 9
folded descriptions load with the wrong text `"> ..."`.)

### 5.3 Settings: `03-settings.R`

```r
# Prototype: settings.json load / merge / persist with Pi semantics, using jsonlite.
# Also compares format candidates (JSON / YAML / DCF / R) on round-trip fidelity.
library(jsonlite)

read_json_file <- function(path) {
  if (!file.exists(path)) return(list())
  raw <- readBin(path, "raw", n = file.size(path))
  if (length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) raw <- raw[-(1:3)]
  txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
  if (!nzchar(trimws(txt))) return(list())
  x <- jsonlite::fromJSON(txt, simplifyVector = FALSE)   # arrays stay lists: lossless round trip
  if (!is.list(x) || (length(x) && is.null(names(x)))) stop("settings file must contain a JSON object: ", path, call. = FALSE)
  x
}

write_json_atomic <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, pretty = 2, null = "null", digits = NA)
  tmp <- tempfile(pattern = ".settings-", tmpdir = dirname(path), fileext = ".tmp")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(enc2utf8(as.character(txt)), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) {            # Windows: rename over existing file can fail
    if (!file.copy(tmp, path, overwrite = TRUE)) stop("cannot write ", path, call. = FALSE)
  }
  invisible(path)
}

is_object <- function(x) is.list(x) && !is.null(names(x)) && all(nzchar(names(x)))

deep_merge <- function(base, over) {
  # Pi deepMergeObjects: objects merge recursively, everything else (incl. arrays) is replaced.
  for (k in names(over)) {
    ov <- over[[k]]
    if (is.null(ov)) next
    bv <- base[[k]]
    base[[k]] <- if (is_object(bv) && is_object(ov)) deep_merge(bv, ov) else ov
  }
  base
}

is_tool_modifier <- function(x) is.character(x) && length(x) == 1L && grepl("^[+-]", x)
merge_default_tools <- function(base, over) {
  if (is.null(over)) return(base)
  if (is.null(base) || !all(vapply(over, is_tool_modifier, NA))) return(over)
  c(base, over)
}
resolve_default_tools <- function(entries, defaults = c("read", "write", "edit", "R")) {
  entries <- as.character(unlist(entries))
  plain <- entries[!grepl("^[+-]", entries)]
  tools <- if (length(plain) || !length(entries)) plain else defaults
  for (e in entries[grepl("^[+-]", entries)]) {
    nm <- substring(e, 2L)
    if (startsWith(e, "+") && nzchar(nm) && !nm %in% tools) tools <- c(tools, nm)
    if (startsWith(e, "-")) tools <- setdiff(tools, nm)
  }
  tools
}

GLOBAL_ONLY <- c("defaultProjectTrust", "httpProxy", "plugins.autoload")

merge_settings <- function(global, project, overrides = list(), project_trusted = TRUE) {
  if (!project_trusted) project <- list()
  project[intersect(names(project), GLOBAL_ONLY)] <- NULL   # project file cannot set these
  m <- deep_merge(global, project)
  dt <- merge_default_tools(global[["defaultTools"]], project[["defaultTools"]])
  if (!is.null(dt)) m[["defaultTools"]] <- dt
  deep_merge(m, overrides)
}

setting <- function(s, key, default = NULL) {
  # dotted access: setting(s, "compaction.reserveTokens", 16384)
  for (k in strsplit(key, ".", fixed = TRUE)[[1L]]) {
    if (!is.list(s) || is.null(s[[k]])) return(default)
    s <- s[[k]]
  }
  s
}

update_settings_file <- function(path, fields) {
  # Pi persistScopedSettings: re-read the file, overwrite only the modified top-level fields.
  cur <- tryCatch(read_json_file(path), error = function(e) NULL)
  if (is.null(cur)) stop("refusing to overwrite unparseable settings file: ", path, call. = FALSE)
  for (k in names(fields)) cur[k] <- list(fields[[k]])
  write_json_atomic(cur, path)
}

# ------------------------------------------------------------------ tests
td <- file.path(tempdir(), "settings"); unlink(td, recursive = TRUE); dir.create(td)
g <- file.path(td, "user", "settings.json"); p <- file.path(td, "proj", ".gptr", "settings.json")
dir.create(dirname(g), recursive = TRUE); dir.create(dirname(p), recursive = TRUE)
writeLines('{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-sonnet-4-5",
  "defaultThinkingLevel": "medium",
  "permissionMode": "ask",
  "defaultTools": ["+grep"],
  "compaction": {"enabled": true, "reserveTokens": 16384},
  "skills": ["~/my-skills"],
  "plugins": ["btw"],
  "defaultProjectTrust": "ask",
  "retry": {"maxRetries": 3, "provider": {"maxRetries": 0}}
}', g)
writeLines('{
  "defaultModel": "gpt-5.2",
  "defaultTools": ["-write", "+find"],
  "compaction": {"reserveTokens": 8000},
  "skills": ["./team-skills"],
  "defaultProjectTrust": "always",
  "retry": {"provider": {"maxRetries": 2}}
}', p)
G <- read_json_file(g); P <- read_json_file(p)
s <- merge_settings(G, P, overrides = list(defaultThinkingLevel = "high"))
stopifnot(
  identical(s$defaultProvider, "anthropic"),
  identical(s$defaultModel, "gpt-5.2"),                         # project overrides user
  identical(s$defaultThinkingLevel, "high"),                     # call-level override wins
  identical(setting(s, "compaction.enabled"), TRUE),             # nested objects merge
  identical(setting(s, "compaction.reserveTokens"), 8000L),
  identical(setting(s, "retry.maxRetries"), 3L),
  identical(setting(s, "retry.provider.maxRetries"), 2L),
  identical(unlist(s$skills), "./team-skills"),                  # arrays REPLACE in the merged view...
  identical(s$defaultProjectTrust, "ask"),                       # global-only key ignored from project
  identical(resolve_default_tools(s$defaultTools), c("read", "edit", "R", "grep", "find")),
  identical(setting(s, "nope.deeper", "dflt"), "dflt")
)
# ... but resource lists are read per scope and COMBINED by the resource resolver (Pi behaviour):
res <- c(unlist(P$skills), unlist(G$skills))
stopifnot(identical(res, c("./team-skills", "~/my-skills")))
su <- merge_settings(G, P, project_trusted = FALSE)
stopifnot(identical(su$defaultModel, "claude-sonnet-4-5"), identical(resolve_default_tools(su$defaultTools), c("read", "write", "edit", "R", "grep")))
cat("merge semantics: OK\n")

stopifnot(identical(resolve_default_tools(list()), character()),                 # [] disables all built-ins
          identical(resolve_default_tools(list("read", "grep")), c("read", "grep")),
          identical(resolve_default_tools(list("read", "+find", "-read")), "find"))
cat("defaultTools semantics: OK\n")

# round trip: single-element arrays must stay arrays, scalars stay scalars, unknown keys preserved
update_settings_file(g, list(defaultModel = "claude-opus-4-5", plugins = list("btw", "mypkg")))
G2 <- read_json_file(g)
stopifnot(identical(G2$defaultModel, "claude-opus-4-5"), is.list(G2$skills), length(G2$skills) == 1L,
          identical(G2$compaction$reserveTokens, 16384L), identical(unlist(G2$plugins), c("btw", "mypkg")))
cat(readLines(g), sep = "\n")
cat("round trip keeps 1-element arrays as arrays:", grepl('"skills":\\s*\\[\\s*"~/my-skills"\\s*\\]', paste(readLines(g), collapse = " "), perl = TRUE), "\n")

# pitfall demo: simplifyVector = TRUE loses array-ness of length-1 arrays on write
bad <- jsonlite::fromJSON('{"skills":["a"]}', simplifyVector = TRUE)
cat("simplifyVector=TRUE then auto_unbox ->", as.character(jsonlite::toJSON(bad, auto_unbox = TRUE)), " (array lost)\n")

# corrupted file: never clobbered
writeLines("{ not json", p)
r <- tryCatch(update_settings_file(p, list(a = 1)), error = function(e) conditionMessage(e))
cat("corrupt file ->", r, "\n"); stopifnot(identical(readLines(p), "{ not json"))

# ---- format comparison -------------------------------------------------------------
obj <- list(defaultModel = "x", skills = list("one"), compaction = list(enabled = TRUE, reserveTokens = 16384L),
            packages = list(list(source = "pkg:btw", skills = list())), note = "caf\u00e9")
j <- jsonlite::fromJSON(jsonlite::toJSON(obj, auto_unbox = TRUE), simplifyVector = FALSE)
cat("JSON round trip identical:", identical(j, obj), "\n")
if (requireNamespace("yaml", quietly = TRUE)) {
  y <- yaml::yaml.load(yaml::as.yaml(obj))
  cat("YAML round trip identical:", identical(y, obj), " (skills class:", class(y$skills), ", empty list ->", deparse(y$packages[[1]]$skills), ")\n")
}
dcf <- tempfile(); write.dcf(data.frame(defaultModel = "x", skills = "one, two", `compaction.enabled` = "TRUE", check.names = FALSE), dcf)
d <- read.dcf(dcf); cat("DCF gives a character matrix only:", class(d)[1], typeof(d), "cols:", paste(colnames(d), collapse = ","), "\n")
```

Observed output:

```text
merge semantics: OK
defaultTools semantics: OK
{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-opus-4-5",
  "defaultThinkingLevel": "medium",
  "permissionMode": "ask",
  "defaultTools": [
    "+grep"
  ],
  "compaction": {
    "enabled": true,
    "reserveTokens": 16384
  },
  "skills": [
    "~/my-skills"
  ],
  "plugins": [
    "btw",
    "mypkg"
  ],
  "defaultProjectTrust": "ask",
  "retry": {
    "maxRetries": 3,
    "provider": {
      "maxRetries": 0
    }
  }
}
round trip keeps 1-element arrays as arrays: TRUE 
simplifyVector=TRUE then auto_unbox -> {"skills":"a"}  (array lost)
corrupt file -> refusing to overwrite unparseable settings file: <tmp>/settings/proj/.gptr/settings.json 
JSON round trip identical: TRUE 
YAML round trip identical: FALSE  (skills class: character , empty list -> list() )
DCF gives a character matrix only: matrix character cols: defaultModel,skills,compaction.enabled 
```

### 5.4 Extension runtime: `04-extensions.R`

This file has no output of its own; it is sourced by `04b-examples.R`. It sources `07-codecalls.R`
(section 5.6).

```r
# Prototype: gptr extension runtime (pure base R). ASCII-only source.
#   - extension = function(gptr) { ... } that receives an API object (environment)
#   - events with Pi's dispatch semantics (notify / block / chain / first-wins / collect)
#   - tools, commands, flags registries; custom session entries; message injection queue
#   - a mock agent loop with a scripted "model" so the hooks can be exercised offline
source("07-codecalls.R")

`%||%` <- function(a, b) if (is.null(a)) b else a

EVENT_KINDS <- c(
  project_trust = "first_decision", resources_discover = "collect",
  session_start = "notify", session_shutdown = "notify", session_before_switch = "cancel",
  session_before_fork = "cancel", session_before_compact = "cancel", session_compact = "notify",
  input = "input", before_agent_start = "before_agent_start", agent_start = "notify", agent_end = "notify",
  agent_before_settle = "boundary", agent_settled = "notify", turn_start = "notify", turn_end = "boundary",
  message_start = "notify", message_update = "notify", message_end = "message_end",
  context = "context", before_provider_request = "payload", after_provider_response = "notify",
  tool_call = "tool_call", tool_result = "tool_result",
  tool_execution_start = "notify", tool_execution_update = "notify", tool_execution_end = "notify",
  model_select = "notify", thinking_level_select = "notify",
  code_eval = "tool_call", object_change = "notify", document_write = "tool_call"   # gptr-specific
)

new_runtime <- function(cwd = getwd(), mode = "script", ui = NULL, env = globalenv(), settings = list()) {
  rt <- new.env(parent = emptyenv())
  rt$cwd <- cwd; rt$mode <- mode; rt$ui <- ui; rt$env <- env; rt$settings <- settings
  rt$extensions <- list()          # ordered: load order == dispatch order
  rt$tools <- list(); rt$active_tools <- character()
  rt$commands <- list(); rt$flags <- list(); rt$flag_values <- list(); rt$providers <- list()
  rt$entries <- list()             # session log: messages + custom entries
  rt$queue <- list()               # injected messages (follow-ups)
  rt$errors <- list()
  rt$bus <- list()
  rt$bound <- FALSE
  rt$idle <- TRUE
  rt
}

rt_error <- function(rt, ext, event, err) {
  rt$errors[[length(rt$errors) + 1L]] <- list(extension = ext, event = event, error = conditionMessage(err))
  invisible(NULL)
}

new_context <- function(rt, tool_call_id = NULL) {
  ctx <- new.env(parent = emptyenv())
  ctx$ui <- rt$ui; ctx$mode <- rt$mode; ctx$has_ui <- isTRUE(rt$ui$has_ui); ctx$cwd <- rt$cwd
  ctx$env <- rt$env
  ctx$is_idle <- function() rt$idle
  ctx$entries <- function() rt$entries
  ctx$settings <- function() rt$settings
  ctx$tools <- function() names(rt$tools)
  ctx$execute_tool <- function(name, args) run_tool_call(rt, list(id = paste0(tool_call_id %||% "cmd", "/n"), name = name, arguments = args), nested = TRUE)
  ctx
}

new_extension_api <- function(rt, name, path = NA_character_) {
  ext <- new.env(parent = emptyenv())
  ext$name <- name; ext$path <- path; ext$handlers <- list(); ext$state <- new.env(parent = emptyenv())
  api <- new.env(parent = emptyenv())
  api$name <- name
  api$state <- ext$state
  api$on <- function(event, handler) {
    stopifnot(is.character(event), length(event) == 1L, is.function(handler))
    if (!event %in% names(EVENT_KINDS)) stop("unknown gptr event: ", event, call. = FALSE)
    id <- paste0(event, "#", length(ext$handlers[[event]]) + 1L, "@", format(Sys.time(), "%H%M%OS6"))
    ext$handlers[[event]] <- c(ext$handlers[[event]], stats::setNames(list(handler), id))
    invisible(function() { ext$handlers[[event]][[id]] <- NULL; invisible(NULL) })
  }
  api$register_tool <- function(name, description, parameters = list(type = "object", properties = list()),
                                execute, label = name, annotations = list(), prompt_snippet = NULL,
                                prompt_guidelines = character(), sequential = FALSE, active = TRUE) {
    stopifnot(is.function(execute), identical(parameters$type, "object"))
    if (!is.null(rt$tools[[name]]) && !identical(rt$tools[[name]]$owner, ext$name) && !identical(rt$tools[[name]]$owner, "builtin"))
      rt_error(rt, ext$name, "register_tool", simpleError(sprintf("Tool \"%s\" conflicts with %s", name, rt$tools[[name]]$owner)))
    rt$tools[[name]] <- list(name = name, label = label, description = description, parameters = parameters,
                             execute = execute, annotations = annotations, prompt_snippet = prompt_snippet,
                             prompt_guidelines = prompt_guidelines, sequential = sequential, owner = ext$name)
    if (active) rt$active_tools <- union(rt$active_tools, name)
    invisible(NULL)
  }
  api$register_command <- function(name, handler, description = "", complete = NULL) {
    rt$commands[[name]] <- list(name = name, description = description, handler = handler, complete = complete, owner = ext$name)
    invisible(NULL)
  }
  api$register_flag <- function(name, type = c("logical", "character"), default = NULL, description = "") {
    type <- match.arg(type)
    rt$flags[[name]] <- list(name = name, type = type, default = default, description = description, owner = ext$name)
    if (is.null(rt$flag_values[[name]]) && !is.null(default)) rt$flag_values[[name]] <- default
    invisible(NULL)
  }
  api$get_flag <- function(name) rt$flag_values[[name]]
  api$register_provider <- function(name, config) { rt$providers[[name]] <- c(config, list(owner = ext$name)); invisible(NULL) }
  needs_bound <- function(what) if (!rt$bound) stop("gptr$", what, "() cannot be called while extensions are loading", call. = FALSE)
  api$send_message <- function(custom_type, content, display = TRUE, details = NULL, trigger_turn = FALSE,
                               deliver_as = c("follow_up", "steer", "next_turn")) {
    needs_bound("send_message"); deliver_as <- match.arg(deliver_as)
    rt$queue[[length(rt$queue) + 1L]] <- list(role = "custom", custom_type = custom_type, content = content,
                                              display = display, details = details, trigger_turn = trigger_turn, deliver_as = deliver_as)
    invisible(NULL)
  }
  api$send_user_message <- function(content, deliver_as = c("follow_up", "steer")) {
    needs_bound("send_user_message"); deliver_as <- match.arg(deliver_as)
    rt$queue[[length(rt$queue) + 1L]] <- list(role = "user", content = content, trigger_turn = TRUE, deliver_as = deliver_as)
    invisible(NULL)
  }
  api$append_entry <- function(custom_type, data = NULL) {
    needs_bound("append_entry")
    rt$entries[[length(rt$entries) + 1L]] <- list(type = "custom", custom_type = custom_type, data = data, time = Sys.time())
    invisible(NULL)
  }
  api$get_active_tools <- function() rt$active_tools
  api$set_active_tools <- function(names) { rt$active_tools <- intersect(unique(names), names(rt$tools)); invisible(NULL) }
  api$get_all_tools <- function() lapply(rt$tools, function(t) t[c("name", "description", "parameters", "annotations", "owner")])
  api$get_commands <- function() lapply(rt$commands, function(cm) cm[c("name", "description", "owner")])
  api$get_settings <- function() rt$settings
  api$events <- list(
    emit = function(channel, data = NULL) { for (h in rt$bus[[channel]]) tryCatch(h(data), error = function(e) rt_error(rt, ext$name, paste0("bus:", channel), e)); invisible(NULL) },
    on = function(channel, handler) { rt$bus[[channel]] <- c(rt$bus[[channel]], list(handler)); invisible(NULL) }
  )
  lockEnvironment(api, bindings = TRUE)
  list(api = api, ext = ext)
}

load_extension <- function(rt, factory, name = NULL, path = NA_character_) {
  # factory: function(gptr); or a path to an .R file whose LAST expression evaluates to such a function
  if (is.character(factory)) {
    path <- normalizePath(factory, winslash = "/", mustWork = TRUE)
    name <- name %||% tools::file_path_sans_ext(basename(path))
    exprs <- parse(path, keep.source = FALSE, encoding = "UTF-8")
    envir <- new.env(parent = globalenv())          # extension file scope; never the user's workspace
    val <- NULL
    for (e in exprs) val <- eval(e, envir)
    factory <- if (is.function(val)) val else envir[["gptr_extension"]]
  }
  name <- name %||% paste0("<inline:", length(rt$extensions) + 1L, ">")
  if (!is.function(factory)) { rt_error(rt, name, "load", simpleError("Extension does not evaluate to a function(gptr)")); return(invisible(FALSE)) }
  snap <- list(tools = rt$tools, active = rt$active_tools, commands = rt$commands, flags = rt$flags, fv = rt$flag_values, prov = rt$providers)
  x <- new_extension_api(rt, name, path)
  ok <- tryCatch({ factory(x$api); TRUE }, error = function(e) { rt_error(rt, name, "load", e); FALSE })
  if (!ok) {   # Pi: a failing factory discards everything it registered
    rt$tools <- snap$tools; rt$active_tools <- snap$active; rt$commands <- snap$commands
    rt$flags <- snap$flags; rt$flag_values <- snap$fv; rt$providers <- snap$prov
    return(invisible(FALSE))
  }
  rt$extensions[[name]] <- x$ext
  invisible(TRUE)
}

handlers_for <- function(rt, event) {
  out <- list()
  for (ext in rt$extensions) for (h in ext$handlers[[event]]) out[[length(out) + 1L]] <- list(ext = ext$name, fn = h)
  out     # snapshot: (un)subscribing during a dispatch does not affect it
}

emit <- function(rt, event, data = list(), ctx = new_context(rt)) {
  kind <- EVENT_KINDS[[event]]
  ev <- c(list(type = event), data)
  hs <- handlers_for(rt, event)
  safe <- function(h, ev) tryCatch(h$fn(ev, ctx), error = function(e) { rt_error(rt, h$ext, event, e); structure(list(), class = "gptr_handler_error") })
  switch(kind,
    notify = { for (h in hs) safe(h, ev); invisible(NULL) },
    cancel = {
      res <- NULL
      for (h in hs) { r <- safe(h, ev); if (is.list(r) && length(r) && !inherits(r, "gptr_handler_error")) { res <- r; if (isTRUE(r$cancel)) return(res) } }
      res
    },
    tool_call = {
      # chain input patches; first block wins; a handler ERROR blocks (fail-safe)
      for (h in hs) {
        r <- tryCatch(h$fn(ev, ctx), error = function(e) { rt_error(rt, h$ext, event, e); list(block = TRUE, reason = paste0("Extension '", h$ext, "' failed, blocking execution: ", conditionMessage(e))) })
        if (!is.list(r)) next
        if (!is.null(r$input)) ev$input <- r$input
        if (isTRUE(r$block)) return(list(block = TRUE, reason = r$reason %||% "Tool execution was blocked", input = ev$input, by = h$ext))
      }
      list(block = FALSE, input = ev$input)
    },
    tool_result = {
      for (h in hs) { r <- safe(h, ev); if (is.list(r)) for (k in intersect(names(r), c("content", "details", "is_error"))) ev[[k]] <- r[[k]] }
      ev[c("content", "details", "is_error")]
    },
    input = {
      for (h in hs) {
        r <- safe(h, ev)
        if (is.list(r) && identical(r$action, "handled")) return(list(action = "handled"))
        if (is.list(r) && identical(r$action, "transform")) ev$text <- r$text
      }
      list(action = if (identical(ev$text, data$text)) "continue" else "transform", text = ev$text)
    },
    before_agent_start = {
      msgs <- list()
      for (h in hs) {
        r <- safe(h, ev)
        if (!is.list(r)) next
        if (!is.null(r$message)) msgs[[length(msgs) + 1L]] <- r$message
        if (!is.null(r$system_prompt)) ev$system_prompt <- r$system_prompt
        if (!is.null(r$append_system_prompt)) ev$system_prompt <- paste(ev$system_prompt, r$append_system_prompt, sep = "\n\n")
      }
      list(messages = msgs, system_prompt = ev$system_prompt)
    },
    context = { for (h in hs) { r <- safe(h, ev); if (is.list(r) && !is.null(r$messages)) ev$messages <- r$messages }; ev$messages },
    payload = { for (h in hs) { r <- safe(h, ev); if (!is.null(r) && !inherits(r, "gptr_handler_error")) ev$payload <- r }; ev$payload },
    message_end = { for (h in hs) { r <- safe(h, ev); if (is.list(r) && !is.null(r$message) && identical(r$message$role, ev$message$role)) ev$message <- r$message }; ev$message },
    boundary = {
      cont <- FALSE; entries <- list()
      for (h in hs) { r <- safe(h, c(ev, list(entries = entries, continue = cont))); if (is.list(r)) { if (!is.null(r$entries)) entries <- r$entries; if (!is.null(r$continue)) cont <- isTRUE(r$continue) } }
      list(entries = entries, continue = cont)
    },
    first_decision = { for (h in hs) { r <- safe(h, ev); if (is.list(r) && r$trusted %in% c("yes", "no")) return(r) }; NULL },
    collect = { acc <- list(); for (h in hs) { r <- safe(h, ev); if (is.list(r)) for (k in names(r)) acc[[k]] <- c(acc[[k]], r[[k]]) }; acc }
  )
}

tool_result <- function(text, details = NULL, is_error = FALSE, terminate = FALSE)
  list(content = list(list(type = "text", text = paste(text, collapse = "\n"))), details = details, is_error = is_error, terminate = terminate)

run_tool_call <- function(rt, call, nested = FALSE) {
  tool <- rt$tools[[call$name]]
  if (is.null(tool) || (!nested && !call$name %in% rt$active_tools)) return(tool_result(sprintf("Tool %s not found", call$name), is_error = TRUE))
  ctx <- new_context(rt, call$id)
  gate <- emit(rt, "tool_call", list(tool_name = call$name, tool_call_id = call$id, input = call$arguments, annotations = tool$annotations), ctx)
  if (isTRUE(gate$block)) return(tool_result(gate$reason, is_error = TRUE))
  emit(rt, "tool_execution_start", list(tool_name = call$name, tool_call_id = call$id, args = gate$input), ctx)
  res <- tryCatch(tool$execute(gate$input, ctx, call$id), error = function(e) tool_result(conditionMessage(e), is_error = TRUE),
                  interrupt = function(i) tool_result("Operation aborted", is_error = TRUE))
  if (is.character(res)) res <- tool_result(res)
  patch <- emit(rt, "tool_result", c(list(tool_name = call$name, tool_call_id = call$id, input = gate$input), res[c("content", "details", "is_error")]), ctx)
  res[names(patch)] <- patch
  emit(rt, "tool_execution_end", list(tool_name = call$name, tool_call_id = call$id, result = res, is_error = isTRUE(res$is_error)), ctx)
  res
}

dispatch_command <- function(rt, text) {
  if (!startsWith(text, "/")) return(FALSE)
  sp <- regexpr(" ", text, fixed = TRUE)
  name <- if (sp < 0L) substring(text, 2L) else substring(text, 2L, sp - 1L)
  args <- if (sp < 0L) "" else substring(text, sp + 1L)
  cmd <- rt$commands[[name]]
  if (is.null(cmd)) return(FALSE)
  tryCatch(cmd$handler(args, new_context(rt)), error = function(e) rt_error(rt, paste0("command:", name), "command", e))
  TRUE
}

# Mock agent loop. `model` is function(messages, tools, system_prompt) -> assistant message
# list(role="assistant", text=, tool_calls=list(list(id,name,arguments)))
run_prompt <- function(rt, text, model, system_prompt = "You are gptr.", max_turns = 10L) {
  if (dispatch_command(rt, text)) return(invisible(list(disposition = "handled")))
  inp <- emit(rt, "input", list(text = text, source = "interactive"))
  if (identical(inp$action, "handled")) return(invisible(list(disposition = "handled")))
  text <- inp$text
  bas <- emit(rt, "before_agent_start", list(prompt = text, system_prompt = system_prompt))
  add <- function(m) { rt$entries[[length(rt$entries) + 1L]] <- c(list(type = "message"), m); invisible(NULL) }
  add(list(role = "user", content = text))
  for (m in bas$messages) add(c(list(role = "custom"), m))
  rt$idle <- FALSE; on.exit(rt$idle <- TRUE, add = TRUE)
  emit(rt, "agent_start")
  new_msgs <- list(); turn <- 0L
  repeat {
    turn <- turn + 1L
    emit(rt, "turn_start", list(turn_index = turn))
    msgs <- Filter(function(e) identical(e$type, "message"), rt$entries)
    msgs <- emit(rt, "context", list(messages = msgs))
    tools <- rt$tools[rt$active_tools]
    a <- model(msgs, tools, bas$system_prompt)
    a <- emit(rt, "message_end", list(message = a))
    add(a); new_msgs[[length(new_msgs) + 1L]] <- a
    results <- lapply(a$tool_calls, function(tc) {
      r <- run_tool_call(rt, tc)
      add(list(role = "tool_result", tool_call_id = tc$id, tool_name = tc$name, content = r$content, details = r$details, is_error = isTRUE(r$is_error)))
      r
    })
    b <- emit(rt, "turn_end", list(turn_index = turn, message = a, tool_results = results))
    for (e in b$entries) rt$entries[[length(rt$entries) + 1L]] <- e
    all_terminate <- length(results) > 0L && all(vapply(results, function(r) isTRUE(r$terminate), NA))
    steer <- Filter(function(q) identical(q$deliver_as, "steer"), rt$queue)
    if (length(steer)) { rt$queue <- Filter(function(q) !identical(q$deliver_as, "steer"), rt$queue); for (q in steer) add(q) }
    if ((length(a$tool_calls) == 0L || all_terminate) && !length(steer) && !isTRUE(b$continue)) break
    if (turn >= max_turns) break
  }
  emit(rt, "agent_end", list(messages = new_msgs))
  s <- emit(rt, "agent_before_settle", list(outcome = "completed"))
  follow <- rt$queue; rt$queue <- list()
  for (q in follow) add(q)
  emit(rt, "agent_settled")
  invisible(list(disposition = "started", turns = turn, final = a$text, follow_ups = follow, continue = s$continue))
}
```

Deviations from Pi that are intentional: the prototype emits `tool_call` before `tool_execution_start`
(Pi emits `tool_execution_start` first); tools run sequentially; handlers return input patches instead of
mutating the event.

### 5.5 Built-in extensions as pure extensions + test run: `04b-examples.R`

```r
# Example extensions implemented purely on the prototype extension API + an offline test run.
source("04-extensions.R")

# ---------------------------------------------------------------- scripted UI for tests
new_scripted_ui <- function(answers = list(), has_ui = TRUE) {
  ui <- new.env(parent = emptyenv())
  ui$has_ui <- has_ui; ui$answers <- answers; ui$log <- character(); ui$status <- list()
  pop <- function(kind, title) {
    ui$log <- c(ui$log, sprintf("%s: %s", kind, gsub("\n", " / ", title)))
    if (!length(ui$answers)) stop("scripted UI ran out of answers at: ", title)
    a <- ui$answers[[1L]]; ui$answers <- ui$answers[-1L]; a
  }
  ui$select <- function(title, options, default = NULL) if (!ui$has_ui) default else pop("select", title)
  ui$confirm <- function(title, message = "", default = FALSE) if (!ui$has_ui) default else isTRUE(pop("confirm", title))
  ui$input <- function(title, placeholder = "", default = NULL) if (!ui$has_ui) default else pop("input", title)
  ui$notify <- function(message, type = "info") { ui$log <- c(ui$log, sprintf("notify[%s]: %s", type, message)); invisible(NULL) }
  ui$set_status <- function(key, text = NULL) { ui$status[[key]] <- text; invisible(NULL) }
  ui
}

# ---------------------------------------------------------------- built-in tools (mock)
builtin_tools <- function(gptr) {
  gptr$register_tool("read", "Read a text file", list(type = "object", properties = list(path = list(type = "string")), required = list("path")),
    annotations = list(read_only = TRUE),
    execute = function(input, ctx, id) tool_result(readLines(input$path, warn = FALSE)))
  gptr$register_tool("write", "Create or overwrite a file", list(type = "object", properties = list(path = list(type = "string"), content = list(type = "string")), required = list("path", "content")),
    annotations = list(read_only = FALSE, destructive = TRUE),
    execute = function(input, ctx, id) { writeLines(input$content, input$path); tool_result(sprintf("Wrote %d bytes to %s", nchar(input$content), basename(input$path))) })
  gptr$register_tool("R", "Evaluate R code in the live session", list(type = "object", properties = list(code = list(type = "string")), required = list("code")),
    annotations = list(read_only = FALSE, destructive = TRUE, open_world = TRUE),
    execute = function(input, ctx, id) {
      out <- utils::capture.output(val <- withVisible(eval(parse(text = input$code), envir = ctx$env)))
      if (val$visible) out <- c(out, utils::capture.output(print(val$value)))
      tool_result(out, details = list(code = input$code))
    })
}

# ---------------------------------------------------------------- 1. permission gate (REQ-37)
# modes: "auto" (never ask) | "edits" (file edits + assigning R code allowed, ask for the rest)
#        | "ask" (ask for everything that is not read-only) | "readonly" (block instead of asking)
permission_gate <- function(gptr) {
  st <- gptr$state
  st$mode <- gptr$get_settings()$permissionMode %||% "ask"
  st$always <- character()                       # session-scoped "always allow" keys
  gptr$register_flag("permission-mode", "character", description = "auto | edits | ask | readonly")
  risk_of <- function(event) {
    if (identical(event$tool_name, "R")) {
      v <- classify_code(event$input$code %||% "")
      return(list(level = switch(v$verdict, "read-only" = 0L, assigns = 1L, "side-effect" = 2L, 3L),
                  why = if (length(v$reasons)) paste(sprintf("%s (%s)", names(v$reasons), vapply(v$reasons, paste, "", collapse = ", ")), collapse = "; ") else v$verdict))
    }
    a <- event$annotations
    if (isTRUE(a$read_only)) return(list(level = 0L, why = "read-only tool"))
    list(level = if (isTRUE(a$destructive %||% TRUE)) 2L else 1L, why = "tool may modify its environment")
  }
  gptr$on("session_start", function(event, ctx) { st$mode <- gptr$get_flag("permission-mode") %||% st$mode; ctx$ui$set_status("permissions", st$mode) })
  gptr$on("tool_call", function(event, ctx) {
    if (identical(st$mode, "auto")) return(NULL)
    r <- risk_of(event)
    limit <- switch(st$mode, edits = 1L, ask = 0L, readonly = 0L, 0L)
    if (r$level <= limit) return(NULL)
    key <- paste0(event$tool_name, ":", r$level)
    if (key %in% st$always) return(NULL)
    if (identical(st$mode, "readonly")) return(list(block = TRUE, reason = sprintf("Read-only mode: %s was blocked (%s).", event$tool_name, r$why)))
    if (!ctx$has_ui) return(list(block = TRUE, reason = sprintf("%s requires approval (%s) but no user interface is available. Re-run with permission mode 'auto' to allow it.", event$tool_name, r$why)))
    shown <- if (!is.null(event$input$code)) event$input$code else paste(utils::capture.output(utils::str(event$input, give.attr = FALSE)), collapse = "\n")
    choice <- ctx$ui$select(sprintf("Allow %s? [%s]\n%s", event$tool_name, r$why, shown),
                            list("Yes", "Yes, always this session", "No", "No, and tell the model what to do instead"))
    if (identical(choice, "Yes")) return(NULL)
    if (identical(choice, "Yes, always this session")) { st$always <- c(st$always, key); return(NULL) }
    why <- if (identical(choice, "No, and tell the model what to do instead")) ctx$ui$input("Instruction for the model") else NULL
    list(block = TRUE, reason = paste0("Blocked by user.", if (!is.null(why)) paste0(" User says: ", why)))
  })
  gptr$register_command("permissions", description = "Show or set the permission mode", handler = function(args, ctx) {
    args <- trimws(args)
    if (nzchar(args)) { stopifnot(args %in% c("auto", "edits", "ask", "readonly")); st$mode <- args; st$always <- character(); gptr$append_entry("permission-mode", list(mode = args)) }
    ctx$ui$set_status("permissions", st$mode); ctx$ui$notify(paste("permission mode:", st$mode))
  })
}

# ---------------------------------------------------------------- 2. plan mode
plan_mode <- function(gptr) {
  st <- gptr$state; st$on <- FALSE; st$executing <- FALSE; st$todos <- list(); st$tools_before <- NULL
  gptr$register_flag("plan", "logical", default = FALSE, description = "Start in plan mode")
  persist <- function() gptr$append_entry("plan-mode", list(on = st$on, executing = st$executing, todos = st$todos, tools_before = st$tools_before))
  toggle <- function(ctx) {
    st$on <- !st$on; st$executing <- FALSE; st$todos <- list()
    if (st$on) { st$tools_before <- gptr$get_active_tools(); gptr$set_active_tools(setdiff(st$tools_before, c("write", "edit"))) }
    else { gptr$set_active_tools(st$tools_before %||% gptr$get_active_tools()); st$tools_before <- NULL }
    ctx$ui$set_status("plan-mode", if (st$on) "plan" else NULL)
    ctx$ui$notify(if (st$on) "Plan mode enabled. Write tools disabled; R code must be read-only." else "Plan mode disabled.")
    persist()
  }
  gptr$register_command("plan", description = "Toggle plan mode (read-only exploration)", handler = function(args, ctx) toggle(ctx))
  gptr$on("tool_call", function(event, ctx) {
    if (!st$on || !identical(event$tool_name, "R")) return(NULL)
    v <- classify_code(event$input$code %||% "")
    if (!identical(v$verdict, "read-only"))
      return(list(block = TRUE, reason = sprintf("Plan mode: only read-only R code is allowed (verdict: %s). Use /plan to leave plan mode first.", v$verdict)))
    NULL
  })
  gptr$on("before_agent_start", function(event, ctx) {
    if (st$on) return(list(message = list(custom_type = "plan-mode-context", display = FALSE, content = paste(
      "[PLAN MODE ACTIVE]", "You are in plan mode: a read-only exploration mode.",
      "Do not modify files or objects. Produce a numbered plan under a 'Plan:' header.", sep = "\n"))))
    if (st$executing && length(st$todos)) {
      rem <- Filter(function(t) !t$done, st$todos)
      return(list(message = list(custom_type = "plan-execution-context", display = FALSE, content = paste0(
        "[EXECUTING PLAN]\nRemaining steps:\n", paste(sprintf("%d. %s", vapply(rem, `[[`, 1L, "step"), vapply(rem, `[[`, "", "text")), collapse = "\n"),
        "\nAfter completing a step, include a [DONE:n] tag in your response."))))
    }
    NULL
  })
  gptr$on("context", function(event, ctx) {
    if (st$on) return(NULL)   # drop stale plan-mode context once plan mode is off
    list(messages = Filter(function(m) !identical(m$custom_type, "plan-mode-context"), event$messages))
  })
  extract_plan <- function(text) {
    if (!grepl("Plan:\\s*\n", text)) return(list())
    sec <- sub("^[\\s\\S]*?Plan:\\s*\n", "", text, perl = TRUE)
    m <- regmatches(sec, gregexpr("(?m)^\\s*(\\d+)[.)]\\s+(.+)$", sec, perl = TRUE))[[1L]]
    lapply(seq_along(m), function(i) list(step = i, text = trimws(sub("^\\s*\\d+[.)]\\s+", "", m[i])), done = FALSE))
  }
  gptr$on("turn_end", function(event, ctx) {
    if (!st$executing) return(NULL)
    done <- as.integer(unlist(regmatches(event$message$text %||% "", gregexpr("(?<=\\[DONE:)\\d+(?=\\])", event$message$text %||% "", perl = TRUE))))
    for (i in seq_along(st$todos)) if (st$todos[[i]]$step %in% done) st$todos[[i]]$done <- TRUE
    persist(); NULL
  })
  gptr$on("agent_end", function(event, ctx) {
    if (st$executing) {
      if (length(st$todos) && all(vapply(st$todos, `[[`, NA, "done"))) { st$executing <- FALSE; gptr$send_message("plan-complete", "Plan complete."); st$todos <- list(); persist() }
      return(NULL)
    }
    if (!st$on || !ctx$has_ui) return(NULL)
    last <- event$messages[[length(event$messages)]]
    plan <- extract_plan(last$text %||% "")
    if (!length(plan)) return(NULL)
    st$todos <- plan
    choice <- ctx$ui$select("Plan mode - what next?", list("Execute the plan (track progress)", "Stay in plan mode", "Refine the plan"))
    if (identical(choice, "Execute the plan (track progress)")) {
      st$on <- FALSE; st$executing <- TRUE
      gptr$set_active_tools(st$tools_before %||% gptr$get_active_tools()); st$tools_before <- NULL
      gptr$send_message("plan-mode-execute", paste0("Execute the plan. Start with: ", plan[[1L]]$text), trigger_turn = TRUE)
    } else if (identical(choice, "Refine the plan")) {
      r <- ctx$ui$input("Refine the plan")
      if (!is.null(r)) gptr$send_user_message(r)
    }
    persist(); NULL
  })
  gptr$on("session_start", function(event, ctx) {
    if (isTRUE(gptr$get_flag("plan")) && !st$on) toggle(ctx)
    for (e in ctx$entries()) if (identical(e$custom_type, "plan-mode")) { st$on <- e$data$on; st$executing <- e$data$executing; st$todos <- e$data$todos }
    NULL
  })
}

# ---------------------------------------------------------------- 3. ask-user tool (REQ-36)
ask_user <- function(gptr) {
  gptr$register_tool("ask_user", "Ask the user one question and wait for the answer. Use when you need a decision or missing information.",
    parameters = list(type = "object", required = list("question"), properties = list(
      question = list(type = "string", description = "The question to ask"),
      options = list(type = "array", items = list(type = "string"), description = "Optional choices"),
      allow_other = list(type = "boolean", description = "Allow a free-text answer (default true)"))),
    annotations = list(read_only = TRUE), sequential = TRUE,
    prompt_guidelines = "Use ask_user instead of guessing when requirements are ambiguous.",
    execute = function(input, ctx, id) {
      if (!ctx$has_ui) return(tool_result("No user is available to answer (non-interactive run). Proceed with your best assumption and state it explicitly.",
                                          details = list(question = input$question, answer = NULL), is_error = TRUE))
      opts <- as.list(input$options)
      if (length(opts)) {
        other <- "Type something else"
        if (!identical(input$allow_other, FALSE)) opts <- c(opts, other)
        ans <- ctx$ui$select(input$question, opts)
        if (identical(ans, other)) ans <- ctx$ui$input("Your answer")
      } else ans <- ctx$ui$input(input$question)
      if (is.null(ans)) return(tool_result("User cancelled the question", details = list(question = input$question, answer = NULL)))
      tool_result(paste("User answered:", ans), details = list(question = input$question, answer = ans))
    })
}

# ---------------------------------------------------------------- 4. todo tool (state in tool-result details)
todo <- function(gptr) {
  st <- gptr$state; st$todos <- list(); st$next_id <- 1L
  rebuild <- function(ctx) {
    st$todos <- list(); st$next_id <- 1L
    for (e in ctx$entries()) if (identical(e$role, "tool_result") && identical(e$tool_name, "todo") && !is.null(e$details)) { st$todos <- e$details$todos; st$next_id <- e$details$next_id }
  }
  gptr$on("session_start", function(event, ctx) rebuild(ctx))
  fmt <- function() if (!length(st$todos)) "No todos" else paste(vapply(st$todos, function(t) sprintf("[%s] #%d: %s", if (t$done) "x" else " ", t$id, t$text), ""), collapse = "\n")
  gptr$register_tool("todo", "Manage a todo list. Actions: list, add (text), toggle (id), clear",
    parameters = list(type = "object", required = list("action"), properties = list(
      action = list(type = "string", enum = list("list", "add", "toggle", "clear")),
      text = list(type = "string"), id = list(type = "integer"))),
    annotations = list(read_only = TRUE),
    execute = function(input, ctx, id) {
      msg <- switch(input$action,
        list = fmt(),
        add = { if (is.null(input$text)) stop("text required for add"); st$todos[[length(st$todos) + 1L]] <- list(id = st$next_id, text = input$text, done = FALSE); st$next_id <- st$next_id + 1L; sprintf("Added todo #%d: %s", st$next_id - 1L, input$text) },
        toggle = { k <- which(vapply(st$todos, function(t) identical(t$id, as.integer(input$id)), NA)); if (!length(k)) stop(sprintf("Todo #%s not found", input$id)); st$todos[[k]]$done <- !st$todos[[k]]$done; sprintf("Todo #%d %s", st$todos[[k]]$id, if (st$todos[[k]]$done) "completed" else "uncompleted") },
        clear = { n <- length(st$todos); st$todos <- list(); st$next_id <- 1L; sprintf("Cleared %d todos", n) },
        stop("unknown action: ", input$action))
      ctx$ui$set_status("todo", sprintf("%d/%d", sum(vapply(st$todos, `[[`, NA, "done")), length(st$todos)))
      tool_result(msg, details = list(action = input$action, todos = st$todos, next_id = st$next_id))
    })
  gptr$register_command("todos", description = "Show all todos", handler = function(args, ctx) ctx$ui$notify(fmt()))
}

# ---------------------------------------------------------------- 5. misc
input_transform <- function(gptr) gptr$on("input", function(event, ctx) {
  if (startsWith(event$text, "?quick ")) return(list(action = "transform", text = paste("Respond briefly:", substring(event$text, 8L))))
  if (identical(tolower(event$text), "ping")) { ctx$ui$notify("pong"); return(list(action = "handled")) }
  list(action = "continue")
})
redact_results <- function(gptr) gptr$on("tool_result", function(event, ctx) {
  txt <- event$content[[1L]]$text
  if (grepl("sk-[A-Za-z0-9]{8,}", txt)) list(content = list(list(type = "text", text = gsub("sk-[A-Za-z0-9]{8,}", "[REDACTED]", txt))))
})
broken_factory <- function(gptr) { gptr$register_command("ghost", handler = function(args, ctx) NULL); stop("boom during load") }
broken_handler <- function(gptr) gptr$on("tool_call", function(event, ctx) if (identical(event$tool_name, "write") && grepl("crash", event$input$path)) stop("handler exploded"))

# =================================================================== TEST RUN
scripted_model <- function(script) { i <- 0L; function(messages, tools, system_prompt) { i <<- i + 1L; s <- script[[min(i, length(script))]]; c(list(role = "assistant"), s) } }
tc <- function(.id, .name, ...) list(id = .id, name = .name, arguments = list(...))
check <- function(label, cond) cat(sprintf("%-78s %s\n", label, if (isTRUE(cond)) "ok" else "FAILED"))
last_results <- function(rt) Filter(function(e) identical(e$role, "tool_result"), rt$entries)
txt <- function(e) e$content[[1L]]$text

work <- file.path(tempdir(), "gptr-ext-test"); unlink(work, recursive = TRUE); dir.create(work)
user_env <- new.env()
ui <- new_scripted_ui()
rt <- new_runtime(cwd = work, mode = "console", ui = ui, env = user_env, settings = list(permissionMode = "ask"))
load_extension(rt, builtin_tools, "builtin")
for (nm in c("permission_gate", "plan_mode", "ask_user", "todo", "input_transform", "redact_results", "broken_handler")) load_extension(rt, get(nm), nm)
check("failing factory returns FALSE", identical(load_extension(rt, broken_factory, "broken_factory"), FALSE))
check("failing factory: its registrations are rolled back", is.null(rt$commands$ghost) && is.null(rt$extensions$broken_factory))
check("action methods are rejected while loading", {
  load_extension(rt, function(gptr) gptr$append_entry("x"), "early"); any(vapply(rt$errors, function(e) grepl("cannot be called while extensions are loading", e$error), NA)) })
rt$bound <- TRUE
emit(rt, "session_start", list(reason = "startup"))
check("tools registered", setequal(names(rt$tools), c("read", "write", "R", "ask_user", "todo")))
check("commands registered", setequal(names(rt$commands), c("permissions", "plan", "todos")))

cat("\n-- permission gate, mode 'ask'\n")
f1 <- file.path(work, "a.txt")
ui$answers <- list("Yes", "No", "No, and tell the model what to do instead", "use saveRDS instead")
r <- run_prompt(rt, "write files", scripted_model(list(
  list(text = "writing", tool_calls = list(tc("c1", "write", path = f1, content = "hello"))),
  list(text = "again", tool_calls = list(tc("c2", "write", path = file.path(work, "b.txt"), content = "x"))),
  list(text = "R", tool_calls = list(tc("c3", "R", code = "write.csv(mtcars, 'out.csv')"))),
  list(text = "read-only R runs without asking", tool_calls = list(tc("c4", "R", code = "nrow(mtcars)"))),
  list(text = "done", tool_calls = list()))))
res <- last_results(rt)
check("approved write executed", file.exists(f1) && !res[[1]]$is_error)
check("denied write blocked with error result", !file.exists(file.path(work, "b.txt")) && res[[2]]$is_error && grepl("Blocked by user", txt(res[[2]])))
check("denial reason with user instruction reaches model", grepl("use saveRDS instead", txt(res[[3]])))
check("read-only R code ran without a prompt", identical(txt(res[[4]]), "[1] 32") && length(ui$answers) == 0L)
check("prompt shows the classifier reason", any(grepl("write \\(write.csv\\)", ui$log)))

cat("\n-- 'always this session', then mode 'edits', 'readonly', 'auto'\n")
ui$answers <- list("Yes, always this session")
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("d1", "write", path = f1, content = "1"), tc("d2", "write", path = f1, content = "2"))), list(text = "done", tool_calls = list()))))
check("second call not prompted after 'always'", length(ui$answers) == 0L && identical(readLines(f1), "2"))
run_prompt(rt, "/permissions edits", scripted_model(list()))
ui$answers <- list("No")
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("e1", "R", code = "z <- 41 + 1"), tc("e2", "R", code = "unlink('a.txt')"))), list(text = "done", tool_calls = list()))))
check("mode edits: assignment allowed silently, object lands in user env", identical(user_env$z, 42))
check("mode edits: dangerous call asked and denied", grepl("Blocked by user", txt(tail(last_results(rt), 1)[[1]])))
run_prompt(rt, "/permissions readonly", scripted_model(list()))
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("f1", "write", path = f1, content = "3"))), list(text = "done", tool_calls = list()))))
check("mode readonly: blocked without any prompt", grepl("Read-only mode", txt(tail(last_results(rt), 1)[[1]])) && identical(readLines(f1), "2"))
run_prompt(rt, "/permissions ask", scripted_model(list()))
ui$has_ui <- FALSE
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("g1", "write", path = f1, content = "4"))), list(text = "done", tool_calls = list()))))
check("no UI + mode ask: fail closed", grepl("no user interface is available", txt(tail(last_results(rt), 1)[[1]])) && identical(readLines(f1), "2"))
ui$has_ui <- TRUE
run_prompt(rt, "/permissions auto", scripted_model(list()))
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("h1", "write", path = f1, content = "5"))), list(text = "done", tool_calls = list()))))
check("mode auto: executes without prompt", identical(readLines(f1), "5"))

cat("\n-- fail-safe + result patching + input transform\n")
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("i1", "write", path = file.path(work, "crash.txt"), content = "x"))), list(text = "done", tool_calls = list()))))
check("throwing tool_call handler blocks the tool", !file.exists(file.path(work, "crash.txt")) && grepl("failed, blocking execution: handler exploded", txt(tail(last_results(rt), 1)[[1]])))
writeLines("key=sk-abcdefgh12345678", file.path(work, "secret.txt"))
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("j1", "read", path = file.path(work, "secret.txt")))), list(text = "done", tool_calls = list()))))
check("tool_result handler redacts content", identical(txt(tail(last_results(rt), 1)[[1]]), "key=[REDACTED]"))
seen <- NULL
run_prompt(rt, "?quick what is R", function(messages, tools, sp) { seen <<- messages[[length(messages)]]$content; list(role = "assistant", text = "ok", tool_calls = list()) })
check("input transform rewrites the prompt", identical(seen, "Respond briefly: what is R"))
check("input 'handled' short-circuits (no model call)", identical(run_prompt(rt, "ping", function(...) stop("model must not be called"))$disposition, "handled"))

cat("\n-- ask_user + todo\n")
ui$answers <- list("Type something else", "use data.table")
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("k1", "ask_user", question = "Which backend?", options = list("dplyr", "base")))), list(text = "done", tool_calls = list()))))
check("ask_user returns the free-text answer", identical(txt(tail(last_results(rt), 1)[[1]]), "User answered: use data.table"))
ui$has_ui <- FALSE
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("k2", "ask_user", question = "Which backend?"))), list(text = "done", tool_calls = list()))))
check("ask_user without UI tells the model to assume", grepl("No user is available", txt(tail(last_results(rt), 1)[[1]])))
ui$has_ui <- TRUE
run_prompt(rt, "x", scripted_model(list(list(text = "", tool_calls = list(tc("l1", "todo", action = "add", text = "load data"), tc("l2", "todo", action = "add", text = "fit model"), tc("l3", "todo", action = "toggle", id = 1L), tc("l4", "todo", action = "toggle", id = 9L))), list(text = "done", tool_calls = list()))))
check("todo state", identical(rt$extensions$todo$state$todos[[1]]$done, TRUE) && length(rt$extensions$todo$state$todos) == 2L)
check("tool error (unknown id) became an error result", grepl("Todo #9 not found", txt(tail(last_results(rt), 1)[[1]])))
rt$extensions$todo$state$todos <- list(); emit(rt, "session_start", list(reason = "resume"))
check("todo state reconstructed from session entries", length(rt$extensions$todo$state$todos) == 2L && rt$extensions$todo$state$next_id == 3L)
run_prompt(rt, "/todos", scripted_model(list())); check("/todos command", grepl("\\[x\\] #1: load data", tail(ui$log, 1)))

cat("\n-- plan mode\n")
run_prompt(rt, "/plan", scripted_model(list()))
check("plan mode removes write from active tools", !"write" %in% rt$active_tools && "R" %in% rt$active_tools)
ui$answers <- list("Execute the plan (track progress)")
sp_seen <- list()
r <- run_prompt(rt, "plan the analysis", (function() { i <- 0L; function(messages, tools, sp) { i <<- i + 1L
  sp_seen[[i]] <<- vapply(messages, function(m) m$custom_type %||% m$role, "")
  if (i == 1L) list(role = "assistant", text = "", tool_calls = list(tc("m1", "R", code = "x_plan <- 1"), tc("m2", "R", code = "ls()"), tc("m3", "write", path = f1, content = "no")))
  else list(role = "assistant", text = "Plan:\n1. Load the data\n2. Fit the model\n", tool_calls = list()) } })())
pr <- tail(last_results(rt), 3)
check("plan mode blocks assigning R code", grepl("Plan mode: only read-only R code", txt(pr[[1]])) && !exists("x_plan", envir = user_env))
check("plan mode allows read-only R code", !pr[[2]]$is_error)
check("plan mode: write tool is not callable", grepl("Tool write not found", txt(pr[[3]])))
check("plan-mode context message injected", "plan-mode-context" %in% sp_seen[[1]])
check("plan extracted, user chose execute, follow-up queued", length(r$follow_ups) == 1L && identical(r$follow_ups[[1]]$custom_type, "plan-mode-execute") && isTRUE(r$follow_ups[[1]]$trigger_turn))
check("tools restored for execution", "write" %in% rt$active_tools)
ctx_seen <- NULL
run_prompt(rt, r$follow_ups[[1]]$content, function(messages, tools, sp) { ctx_seen <<- vapply(messages, function(m) m$custom_type %||% m$role, ""); list(role = "assistant", text = "did both [DONE:1] [DONE:2]", tool_calls = list()) })
check("stale plan-mode context filtered by 'context' hook; execution context present", !"plan-mode-context" %in% ctx_seen && "plan-execution-context" %in% ctx_seen)
check("[DONE:n] tracking completes the plan", !rt$extensions$plan_mode$state$executing)

cat("\nextension errors recorded:\n"); for (e in rt$errors) cat(sprintf("  %s / %s: %s\n", e$extension, e$event, e$error))
check("user globalenv untouched by extension files", !exists("gptr_extension", envir = globalenv()))

# file-based extension
ef <- file.path(work, "hello.R")
writeLines(c("# gptr extension file: the last expression must be function(gptr)", "greeting <- 'Hello'",
             "function(gptr) {", "  gptr$register_command('hello', description = 'Show a greeting',",
             "    handler = function(args, ctx) ctx$ui$notify(paste0(greeting, ', ', if (nzchar(args)) args else 'world', '!')))", "}"), ef)
check("file extension loads", isTRUE(load_extension(rt, ef)))
run_prompt(rt, "/hello R", scripted_model(list())); check("file extension command works and sees its file scope", identical(tail(ui$log, 1), "notify[info]: Hello, R!"))
```

Observed output:

```text
failing factory returns FALSE                                                  ok
failing factory: its registrations are rolled back                             ok
action methods are rejected while loading                                      ok
tools registered                                                               ok
commands registered                                                            ok

-- permission gate, mode 'ask'
approved write executed                                                        ok
denied write blocked with error result                                         ok
denial reason with user instruction reaches model                              ok
read-only R code ran without a prompt                                          ok
prompt shows the classifier reason                                             ok

-- 'always this session', then mode 'edits', 'readonly', 'auto'
second call not prompted after 'always'                                        ok
mode edits: assignment allowed silently, object lands in user env              ok
mode edits: dangerous call asked and denied                                    ok
mode readonly: blocked without any prompt                                      ok
no UI + mode ask: fail closed                                                  ok
mode auto: executes without prompt                                             ok

-- fail-safe + result patching + input transform
throwing tool_call handler blocks the tool                                     ok
tool_result handler redacts content                                            ok
input transform rewrites the prompt                                            ok
input 'handled' short-circuits (no model call)                                 ok

-- ask_user + todo
ask_user returns the free-text answer                                          ok
ask_user without UI tells the model to assume                                  ok
todo state                                                                     ok
tool error (unknown id) became an error result                                 ok
todo state reconstructed from session entries                                  ok
/todos command                                                                 ok

-- plan mode
plan mode removes write from active tools                                      ok
plan mode blocks assigning R code                                              ok
plan mode allows read-only R code                                              ok
plan mode: write tool is not callable                                          ok
plan-mode context message injected                                             ok
plan extracted, user chose execute, follow-up queued                           ok
tools restored for execution                                                   ok
stale plan-mode context filtered by 'context' hook; execution context present  ok
[DONE:n] tracking completes the plan                                           ok

extension errors recorded:
  broken_factory / load: boom during load
  early / load: gptr$append_entry() cannot be called while extensions are loading
  broken_handler / tool_call: handler exploded
user globalenv untouched by extension files                                    ok
file extension loads                                                           ok
file extension command works and sees its file scope                           ok
```

A bug found while writing this test is worth recording: the first version of the helper
`tc <- function(id, name, ...)` received `tc("l3", "todo", action = "toggle", id = 1L)`; R matched the
named argument `id = 1L` to the formal `id`, shifted the positional arguments, and the call silently became
a call to a tool named `"l3"`. Any exported gptr function that forwards user-named arguments through `...`
(tool arguments, template arguments, settings) must use dot-prefixed formals (`.id`, `.name`).

### 5.6 Static R code classifier: `07-codecalls.R`

```r
# Prototype: static classification of R code for permission gates (AST based, never evaluates).
# Returns the set of called functions and a risk verdict. This is a HEURISTIC, not a sandbox.

RISK_TABLE <- list(
  delete   = c("unlink", "file.remove", "file_delete", "dir_delete", "rm_rf"),
  write    = c("writeLines", "write", "cat_file", "write.csv", "write.csv2", "write.table", "saveRDS", "save", "save.image",
               "file.create", "file.copy", "file.rename", "file.append", "dir.create", "sink", "dput_file", "download.file",
               "fwrite", "write_csv", "write_tsv", "write_rds", "write_parquet", "ggsave", "pdf", "png", "jpeg", "svg",
               "file_create", "file_copy", "file_move", "dir_create", "zip", "unzip", "untar", "tar", "Sys.chmod", "Sys.setFileTime"),
  process  = c("system", "system2", "shell", "shell.exec", "pipe", "run", "process", "r_bg", "rscript", "callr", "browseURL"),
  install  = c("install.packages", "remove.packages", "update.packages", "install_github", "install_local", "pak", "pkg_install"),
  session  = c("q", "quit", "setwd", "Sys.setenv", "Sys.unsetenv", "options", "attach", "detach", "library", "require",
               "source", "sys.source", "loadNamespace", "requireNamespace", "unloadNamespace", "Sys.setlocale", "set.seed"),
  network  = c("url", "curl", "curl_fetch_memory", "curl_download", "req_perform", "GET", "POST", "PUT", "DELETE", "socketConnection", "download.file"),
  dynamic  = c("eval", "evalq", "eval.parent", "parse", "str2lang", "str2expression", "do.call", "get", "get0", "mget", "match.fun",
               "getExportedValue", "getFromNamespace", "assignInNamespace", "body<-", "environment<-", "Reduce_call", ".Call", ".External", ".C", ".Internal"),
  secrets  = c("Sys.getenv", "readRenviron", "key_get", "askpass")
)

code_calls <- function(code) {
  exprs <- tryCatch(parse(text = code, keep.source = FALSE), error = function(e) e)
  if (inherits(exprs, "error")) return(list(ok = FALSE, error = conditionMessage(exprs), calls = character(), assigns = character()))
  calls <- character(); assigns <- character(); globals_rm <- FALSE
  walk <- function(e) {
    if (is.call(e)) {
      f <- e[[1L]]
      fname <- if (is.symbol(f)) as.character(f)
               else if (is.call(f) && as.character(f[[1L]]) %in% c("::", ":::")) paste0(as.character(f[[2L]]), "::", as.character(f[[3L]]))
               else "<computed>"
      calls <<- c(calls, fname)
      if (fname %in% c("<-", "=", "<<-", "assign", "->") && length(e) >= 2L) {
        tgt <- e[[2L]]
        while (is.call(tgt) && length(tgt) >= 2L) tgt <- tgt[[2L]]   # x$a[[1]] <- v  => x
        if (is.symbol(tgt) || is.character(tgt)) assigns <<- c(assigns, as.character(tgt))
      }
      for (a in as.list(e)) if (!missing(a)) walk(a)
    } else if (is.expression(e) || is.pairlist(e)) {
      for (a in as.list(e)) if (!missing(a)) walk(a)
    }
    invisible()
  }
  walk(exprs)
  list(ok = TRUE, calls = unique(calls), assigns = unique(assigns))
}

classify_code <- function(code, readonly_ok = NULL) {
  cc <- code_calls(code)
  if (!cc$ok) return(list(verdict = "invalid", reasons = cc$error, calls = character()))
  bare <- sub("^.*::", "", cc$calls)
  hits <- lapply(RISK_TABLE, function(v) intersect(bare, v))
  hits <- hits[lengths(hits) > 0L]
  if ("<computed>" %in% cc$calls) hits$dynamic <- unique(c(hits$dynamic, "<computed call>"))
  if ("rm" %in% bare) hits$delete_objects <- "rm"
  verdict <- if (any(names(hits) %in% c("delete", "process", "install", "dynamic"))) "dangerous"
             else if (length(hits)) "side-effect"
             else if (length(cc$assigns)) "assigns"          # creates/modifies objects in the session env
             else "read-only"
  list(verdict = verdict, reasons = hits, calls = cc$calls, assigns = cc$assigns)
}

if (sys.nframe() == 0L) {
  cases <- c(
    "summary(mtcars); str(iris); head(df[df$x > 1, ])",
    "fit <- lm(mpg ~ wt, data = mtcars); coef(fit)",
    "unlink('~/project', recursive = TRUE)",
    "base::unlink(tempdir())",
    "do.call('unlink', list('x'))",
    "f <- get('unl' %+% 'ink'); f('x')",
    "(function(x) x)(1)",
    "system2('rm', c('-rf', '/'))",
    "write.csv(mtcars, 'out.csv')",
    "install.packages('data.table')",
    "x$y[[3]] <- 5; names(z) <- 'a'",
    "rm(list = ls())",
    "Sys.getenv('ANTHROPIC_API_KEY')",
    "library(ggplot2); ggplot(mtcars, aes(wt, mpg)) + geom_point()",
    "this is not R code {"
  )
  for (k in cases) {
    r <- classify_code(k)
    cat(sprintf("%-11s | %-62s | %s\n", r$verdict, substr(k, 1, 62),
                paste(sprintf("%s:%s", names(r$reasons), vapply(r$reasons, paste, "", collapse = ",")), collapse = " ")))
  }
  big <- paste(rep("x <- mean(rnorm(10)); y <- lapply(1:3, function(i) i^2)", 500), collapse = "\n")
  cat("classify 500-line script: ", system.time(classify_code(big))[["elapsed"]], "s\n")
}
```

Observed output:

```text
read-only   | summary(mtcars); str(iris); head(df[df$x > 1, ])               | 
assigns     | fit <- lm(mpg ~ wt, data = mtcars); coef(fit)                  | 
dangerous   | unlink('~/project', recursive = TRUE)                          | delete:unlink
dangerous   | base::unlink(tempdir())                                        | delete:unlink
dangerous   | do.call('unlink', list('x'))                                   | dynamic:do.call
dangerous   | f <- get('unl' %+% 'ink'); f('x')                              | dynamic:get
dangerous   | (function(x) x)(1)                                             | dynamic:<computed call>
dangerous   | system2('rm', c('-rf', '/'))                                   | process:system2
side-effect | write.csv(mtcars, 'out.csv')                                   | write:write.csv
dangerous   | install.packages('data.table')                                 | install:install.packages
assigns     | x$y[[3]] <- 5; names(z) <- 'a'                                 | 
side-effect | rm(list = ls())                                                | delete_objects:rm
side-effect | Sys.getenv('ANTHROPIC_API_KEY')                                | secrets:Sys.getenv
side-effect | library(ggplot2); ggplot(mtcars, aes(wt, mpg)) + geom_point()  | session:library
invalid     | this is not R code {                                           | 
classify 500-line script:  0.129 s
```

### 5.7 Console UI and non-interactive behaviour: `06-ui.R`

Run as `echo "piped-line" | Rscript --vanilla 06-ui.R`.

```r
# Prototype: console UI primitives (confirm/select/input/notify) and their behaviour when
# the session is NOT interactive (Rscript, knitr, R CMD check).
cat("interactive():", interactive(), "\n")
cat("readline() in non-interactive returns:", deparse(readline("prompt> ")), "\n")
r <- tryCatch(utils::menu(c("a", "b"), title = "pick"), error = function(e) paste("ERROR:", conditionMessage(e)))
cat("utils::menu() ->", r, "\n")
r <- tryCatch(utils::askYesNo("ok?"), error = function(e) paste("ERROR:", conditionMessage(e)))
cat("utils::askYesNo() ->", deparse(r), "\n")
r <- tryCatch(readLines(file("stdin"), n = 1L), error = function(e) paste("ERROR:", conditionMessage(e)))
cat("readLines(file('stdin'), 1) with piped stdin ->", deparse(r), "\n")
cat("knitr in progress:", isTRUE(getOption("knitr.in.progress")), "\n")
cat("RSTUDIO env:", Sys.getenv("RSTUDIO"), "| rstudioapi available:",
    requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable(), "\n")
cat("TESTTHAT:", Sys.getenv("TESTTHAT"), " R_CHECK:", nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")), "\n")

# --- the console UI object ------------------------------------------------------------
new_console_ui <- function(input = function(prompt) readline(prompt), is_interactive = interactive(),
                           out = function(...) cat(..., "\n", sep = "", file = stderr())) {
  ui <- new.env(parent = emptyenv())
  ui$has_ui <- is_interactive
  ui$notify <- function(message, type = c("info", "warning", "error")) {
    type <- match.arg(type)
    out(switch(type, info = "[gptr] ", warning = "[gptr] warning: ", error = "[gptr] error: "), message)
    invisible(NULL)
  }
  ui$select <- function(title, options, default = NULL) {
    if (!ui$has_ui) return(default)                      # Pi: no-UI select resolves to undefined
    out(title)
    for (i in seq_along(options)) out(sprintf("  %d: %s", i, options[[i]]))
    repeat {
      ans <- trimws(input(sprintf("Selection [1-%d, empty = cancel]: ", length(options))))
      if (!nzchar(ans)) return(NULL)
      k <- suppressWarnings(as.integer(ans))
      if (!is.na(k) && k >= 1L && k <= length(options)) return(options[[k]])
      hit <- which(tolower(unlist(options)) == tolower(ans))
      if (length(hit) == 1L) return(options[[hit]])
      out("Please enter a number between 1 and ", length(options), ".")
    }
  }
  ui$confirm <- function(title, message = "", default = FALSE) {
    if (!ui$has_ui) return(default)                      # Pi: no-UI confirm resolves to false
    if (nzchar(message)) out(title, "\n", message) else out(title)
    repeat {
      ans <- tolower(trimws(input("[y/N]: ")))
      if (ans %in% c("y", "yes")) return(TRUE)
      if (ans %in% c("", "n", "no")) return(FALSE)
    }
  }
  ui$input <- function(title, placeholder = "", default = NULL) {
    if (!ui$has_ui) return(default)
    ans <- input(paste0(title, if (nzchar(placeholder)) sprintf(" (%s)", placeholder), ": "))
    if (!nzchar(ans)) NULL else ans
  }
  ui$set_status <- function(key, text = NULL) invisible(NULL)
  ui
}

# scripted input lets us test the interactive code path under Rscript
script <- c("9", "2", "maybe", "y", "", "free text")
i <- 0L
fake_input <- function(prompt) { i <<- i + 1L; cat(prompt, script[i], "\n", sep = "", file = stderr()); script[i] }
ui <- new_console_ui(input = fake_input, is_interactive = TRUE)
stopifnot(identical(ui$select("Pick one", list("Allow", "Block")), "Block"))      # "9" rejected, then "2"
stopifnot(isTRUE(ui$confirm("Run it?", "rm -rf")))                                # "maybe" rejected, then "y"
stopifnot(is.null(ui$input("Name")))                                              # empty -> cancel
stopifnot(identical(ui$input("Name"), "free text"))
ui0 <- new_console_ui(is_interactive = FALSE)
stopifnot(is.null(ui0$select("x", list("a"))), identical(ui0$confirm("x"), FALSE), is.null(ui0$input("x")))
cat("console UI: OK (interactive path via scripted input; non-interactive returns safe defaults)\n")
```

Observed output:

```text
interactive(): FALSE 
prompt> 
readline() in non-interactive returns: "" 
utils::menu() -> ERROR: menu() cannot be used non-interactively 
ok? (Yes/no/cancel) 
utils::askYesNo() -> TRUE 
readLines(file('stdin'), 1) with piped stdin -> "piped-line" 
knitr in progress: FALSE 
RSTUDIO env:  | rstudioapi available: FALSE 
TESTTHAT:   R_CHECK: FALSE 
Pick one
  1: Allow
  2: Block
Selection [1-2, empty = cancel]: 9
Please enter a number between 1 and 2.
Selection [1-2, empty = cancel]: 2
Run it?
rm -rf
[y/N]: maybe
[y/N]: y
Name: 
Name: free text
console UI: OK (interactive path via scripted input; non-interactive returns safe defaults)
```

Key facts (VERIFIED): in a non-interactive session `readline()` returns `""` immediately, `utils::menu()`
raises `menu() cannot be used non-interactively`, and **`utils::askYesNo()` returns `TRUE`** (its default).
`readLines(file("stdin"), n = 1)` reads a piped line. A permission dialog must therefore be implemented on
`readline()`/`readLines()` with an explicit `has_ui` guard, never on `askYesNo()`.

### 5.8 Home directory, trust store, context files: `08-trust.R`

```r
# Prototype: user/project directories, project trust store, context-file discovery. Base R + jsonlite.
library(jsonlite)
`%||%` <- function(a, b) if (is.null(a)) b else a

is_windows <- function() identical(.Platform$OS.type, "windows")

user_home <- function() {
  # The OS profile directory, which is where other agents keep ~/.claude, ~/.codex, ~/.agents.
  # On Windows path.expand("~") is normally <profile>/Documents, so it must NOT be used for this.
  h <- if (is_windows()) Sys.getenv("USERPROFILE", unset = NA) else Sys.getenv("HOME", unset = NA)
  if (is.na(h) || !nzchar(h)) h <- path.expand("~")
  normalizePath(h, winslash = "/", mustWork = FALSE)
}

gptr_user_dir <- function(which = c("config", "data", "cache")) {
  which <- match.arg(which)
  d <- Sys.getenv("GPTR_HOME", unset = "")
  if (nzchar(d)) return(normalizePath(file.path(d, which), winslash = "/", mustWork = FALSE))
  normalizePath(tools::R_user_dir("gptr", which), winslash = "/", mustWork = FALSE)
}

canonical <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  p <- sub("/+$", "", p)
  if (!nzchar(p)) p <- "/"
  if (is_windows()) p <- tolower(p)          # NTFS is case-insensitive
  p
}
parent_dir <- function(p) { d <- dirname(p); if (identical(d, p)) NULL else d }
ancestors <- function(p) { out <- p <- canonical(p); while (!is.null(p <- parent_dir(p))) out <- c(out, p); out }

find_project_root <- function(cwd) {
  for (d in ancestors(cwd)) {
    if (file.exists(file.path(d, ".git")) || file.exists(file.path(d, "DESCRIPTION")) || dir.exists(file.path(d, ".gptr")) ||
        length(Sys.glob(file.path(d, "*.Rproj")))) return(d)
  }
  canonical(cwd)
}

# ---- trust store --------------------------------------------------------------------
trust_path <- function() file.path(gptr_user_dir("config"), "trust.json")
trust_read <- function(path = trust_path()) {
  if (!file.exists(path)) return(list())
  x <- jsonlite::fromJSON(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), simplifyVector = FALSE)
  if (length(x) && is.null(names(x))) stop("Invalid trust store ", path, ": expected an object", call. = FALSE)
  Filter(function(v) isTRUE(v) || identical(v, FALSE), x)
}
trust_write <- function(data, path = trust_path()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  data <- data[order(names(data))]
  tmp <- paste0(path, ".", Sys.getpid(), ".tmp")
  writeLines(as.character(jsonlite::toJSON(if (length(data)) data else structure(list(), names = character()), auto_unbox = TRUE, pretty = 2)), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}
trust_get <- function(cwd, path = trust_path()) {
  data <- trust_read(path)
  for (d in ancestors(cwd)) if (!is.null(data[[d]])) return(list(path = d, decision = data[[d]]))   # closest decision applies
  NULL
}
trust_set <- function(cwd, decision, path = trust_path()) {
  data <- trust_read(path)                       # re-read immediately before writing
  key <- canonical(cwd)
  if (is.null(decision)) data[[key]] <- NULL else data[[key]] <- isTRUE(decision)   # NULL deletes the entry
  trust_write(data, path)
}

TRUST_GATED <- c("settings.json", "mcp.json", "extensions", "skills", "prompts", "SYSTEM.md", "APPEND_SYSTEM.md")
needs_trust <- function(cwd) {
  cfg <- file.path(canonical(cwd), ".gptr")
  if (any(file.exists(file.path(cfg, TRUST_GATED)))) return(TRUE)
  home <- canonical(user_home())
  for (d in ancestors(cwd)) {
    if (identical(d, home)) next                 # ~/.agents/skills etc. are user resources
    if (any(dir.exists(file.path(d, c(".agents/skills", ".claude/skills", ".codex/skills"))))) return(TRUE)
  }
  FALSE
}

resolve_project_trust <- function(cwd, override = NULL, default = c("ask", "always", "never"), ui = NULL,
                                  decide = NULL, store = trust_path()) {
  default <- match.arg(default)
  if (!is.null(override)) return(isTRUE(override))                       # 1. explicit argument / option
  if (!needs_trust(cwd)) return(TRUE)                                    # nothing to gate
  if (is.function(decide)) {                                             # 2. project_trust hook (user-level extensions only)
    r <- decide(list(type = "project_trust", cwd = canonical(cwd)))
    if (is.list(r) && r$trusted %in% c("yes", "no")) {
      if (isTRUE(r$remember)) trust_set(cwd, identical(r$trusted, "yes"), store)
      return(identical(r$trusted, "yes"))
    }
  }
  saved <- trust_get(cwd, store)                                          # 3. saved decision (closest ancestor)
  if (!is.null(saved)) return(saved$decision)
  if (default != "ask") return(default == "always")                       # 4. defaultProjectTrust (user settings only)
  if (is.null(ui) || !isTRUE(ui$has_ui)) return(FALSE)                    # 5. no UI: fail closed
  opts <- list("Trust", sprintf("Trust parent folder (%s)", dirname(canonical(cwd))), "Trust (this session only)",
               "Do not trust", "Do not trust (this session only)")
  ans <- ui$select(sprintf("Trust project folder?\n%s\n\nThis allows gptr to load .gptr settings and resources and to execute project extensions.", canonical(cwd)), opts)
  if (is.null(ans)) return(FALSE)
  k <- match(ans, unlist(opts))
  if (k == 1L) trust_set(cwd, TRUE, store)
  if (k == 2L) { trust_set(dirname(canonical(cwd)), TRUE, store); trust_set(cwd, NULL, store) }
  if (k == 4L) trust_set(cwd, FALSE, store)
  k %in% 1:3
}

# ---- context files --------------------------------------------------------------------
CONTEXT_CANDIDATES <- c("AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD")
context_file_in <- function(dir, candidates = CONTEXT_CANDIDATES) {
  present <- list.files(dir, all.files = TRUE, no.. = TRUE)               # exact-case match even on case-insensitive FS
  for (f in candidates) if (f %in% present && !dir.exists(file.path(dir, f))) return(file.path(dir, f))
  NULL
}
load_context_files <- function(cwd, user_dir = gptr_user_dir("config")) {
  out <- character()
  g <- context_file_in(user_dir); if (!is.null(g)) out <- g
  anc <- character()
  for (d in ancestors(cwd)) {
    v <- file.path(d, ".gptr", "vignette.Rmd")                           # REQ-27: gptr's own instructions file wins in its dir
    f <- if (file.exists(v)) v else context_file_in(d)
    if (!is.null(f) && !f %in% c(out, anc)) anc <- c(f, anc)              # outermost first, cwd last
  }
  unique(c(out, anc))
}

# ------------------------------------------------------------------ tests
if (sys.nframe() == 0L) {
  cat("user_home():", user_home(), "\n")
  cat("path.expand('~'):", path.expand("~"), "\n")
  cat("R_user_dir config/data/cache:\n"); for (w in c("config", "data", "cache")) cat("  ", tools::R_user_dir("gptr", w), "\n")
  root <- file.path(tempdir(), "trust-test"); unlink(root, recursive = TRUE)
  Sys.setenv(GPTR_HOME = file.path(root, "home"))
  proj <- file.path(root, "work", "proj"); sub <- file.path(proj, "analysis", "deep")
  dir.create(sub, recursive = TRUE); dir.create(file.path(proj, ".git"))
  stopifnot(identical(find_project_root(sub), canonical(proj)))
  stopifnot(!needs_trust(sub))                                            # bare project: nothing to gate
  dir.create(file.path(proj, ".gptr")); stopifnot(!needs_trust(proj))     # bare .gptr does not require trust
  dir.create(file.path(proj, ".gptr", "extensions")); stopifnot(needs_trust(proj), !needs_trust(sub))
  dir.create(file.path(proj, ".agents", "skills"), recursive = TRUE); stopifnot(needs_trust(sub))   # ancestors' .agents/skills
  no_ui <- list(has_ui = FALSE)
  stopifnot(identical(resolve_project_trust(proj, ui = no_ui), FALSE))                # ask + no UI => not trusted
  stopifnot(identical(resolve_project_trust(proj, override = TRUE), TRUE))
  stopifnot(identical(resolve_project_trust(proj, default = "always"), TRUE))
  ui <- list(has_ui = TRUE, select = function(title, options) options[[2L]])          # "Trust parent folder"
  stopifnot(isTRUE(resolve_project_trust(proj, ui = ui)))
  cat(readLines(trust_path()), sep = "\n")
  stopifnot(isTRUE(trust_get(sub)$decision), identical(trust_get(sub)$path, canonical(file.path(root, "work"))))
  trust_set(proj, FALSE); stopifnot(identical(resolve_project_trust(sub, ui = no_ui), FALSE))   # closest decision wins
  stopifnot(isTRUE(resolve_project_trust(sub, decide = function(e) list(trusted = "yes"))))     # hook beats store
  stopifnot(identical(resolve_project_trust(sub, decide = function(e) list(trusted = "undecided"), ui = no_ui), FALSE))
  cat("trust resolution: OK\n")

  writeLines("root rules", file.path(root, "work", "AGENTS.md"))
  writeLines("claude rules", file.path(proj, "CLAUDE.md"))
  writeLines("agents rules", file.path(proj, "AGENTS.md"))
  writeLines("deep override", file.path(sub, "AGENTS.override.md")); writeLines("deep", file.path(sub, "AGENTS.md"))
  dir.create(gptr_user_dir("config"), recursive = TRUE, showWarnings = FALSE); writeLines("global", file.path(gptr_user_dir("config"), "AGENTS.md"))
  cf <- load_context_files(sub)
  print(sub(canonical(root), "<root>", cf, fixed = TRUE))
  stopifnot(length(cf) == 4L, basename(cf[4]) == "AGENTS.override.md", basename(cf[3]) == "AGENTS.md")
  writeLines("---\ntitle: project instructions\n---\nUse data.table.", file.path(proj, ".gptr", "vignette.Rmd"))
  cf <- load_context_files(sub); print(sub(canonical(root), "<root>", cf, fixed = TRUE))
  stopifnot(any(grepl("vignette.Rmd$", cf)), !any(grepl("proj/AGENTS.md$", cf)))
  cat("context files: OK\n")
  Sys.unsetenv("GPTR_HOME")
}
```

Observed output:

```text
user_home(): <home> 
path.expand('~'): <home> 
R_user_dir config/data/cache:
   <home>/Library/Preferences/org.R-project.R/R/gptr 
   <home>/Library/Application Support/org.R-project.R/R/gptr 
   <home>/Library/Caches/org.R-project.R/R/gptr 
{
  "<tmp>/trust-test/work": true
}
trust resolution: OK
[1] "<root>/home/config/AGENTS.md"                     
[2] "<root>/work/AGENTS.md"                            
[3] "<root>/work/proj/AGENTS.md"                       
[4] "<root>/work/proj/analysis/deep/AGENTS.override.md"
[1] "<root>/home/config/AGENTS.md"                     
[2] "<root>/work/AGENTS.md"                            
[3] "<root>/work/proj/.gptr/vignette.Rmd"              
[4] "<root>/work/proj/analysis/deep/AGENTS.override.md"
context files: OK
```

### 5.9 Scanning installed packages and installing a plugin package: `05-pkgscan.R`

```r
# Benchmark: cost of discovering gptr resources shipped by installed R packages.
# Installed layout: inst/gptr/{skills,extensions,prompts} -> <lib>/<pkg>/gptr/...; btw convention inst/skills -> <lib>/<pkg>/skills
bench <- function(expr, n = 5L) {
  e <- substitute(expr); env <- parent.frame()
  t <- vapply(seq_len(n), function(i) system.time(eval(e, env))[["elapsed"]], 0)
  c(first = t[1], median = stats::median(t), min = min(t))
}
libs <- .libPaths()
cat("libPaths:", length(libs), " packages:", length(list.files(libs)), "\n\n")

# (A) vectorised dir.exists over every installed package directory
scan_A <- function(sub = c("gptr", "skills")) {
  pk <- list.files(libs, full.names = TRUE)
  cand <- as.vector(outer(pk, sub, file.path))
  cand[dir.exists(cand)]
}
# (B) Sys.glob
scan_B <- function() Sys.glob(file.path(libs, "*", c("gptr", "skills")))
# (C) system.file() per installed package (what a naive implementation does)
scan_C <- function() {
  pk <- unique(list.files(libs))
  r <- vapply(pk, function(p) system.file("gptr", package = p), "")
  r[nzchar(r)]
}
# (D) installed.packages() with a custom DESCRIPTION field (opt-in marker)
scan_D <- function() {
  ip <- utils::installed.packages(fields = "Config/gptr/plugin", noCache = TRUE)
  rownames(ip)[!is.na(ip[, "Config/gptr/plugin"])]
}
# (E) only attached packages (btw's strategy) / (F) loaded namespaces
scan_E <- function() { p <- .packages(); r <- vapply(p, function(x) system.file("gptr", package = x), ""); r[nzchar(r)] }
scan_F <- function() { p <- loadedNamespaces(); r <- vapply(p, function(x) system.file("gptr", package = x), ""); r[nzchar(r)] }
# (G) explicit list of N plugin packages
scan_G <- function(pk = c("jsonlite", "yaml", "cli")) { r <- vapply(pk, function(x) system.file("gptr", package = x), ""); r[nzchar(r)] }

res <- rbind(
  A_dir.exists_all    = bench(scan_A()),
  B_Sys.glob_all      = bench(scan_B()),
  C_system.file_all   = bench(scan_C(), n = 3L),
  D_installed.pkgs    = bench(scan_D(), n = 3L),
  E_attached_only     = bench(scan_E()),
  F_loadedNamespaces  = bench(scan_F()),
  G_explicit_3        = bench(scan_G())
)
print(round(res * 1000, 2))   # milliseconds
cat("\nhits A:", length(scan_A()), "\n")
print(basename(dirname(scan_A())))
cat("attached:", length(.packages()), " loaded namespaces:", length(loadedNamespaces()), "\n")

# Simulate a plugin package in a private library and confirm discovery via both routes.
lib <- file.path(tempdir(), "plib"); dir.create(lib, showWarnings = FALSE)
pkg <- file.path(tempdir(), "gptrdemo"); unlink(pkg, recursive = TRUE)
dir.create(file.path(pkg, "inst/gptr/skills/demo-skill"), recursive = TRUE)
dir.create(file.path(pkg, "inst/gptr/extensions"), recursive = TRUE)
dir.create(file.path(pkg, "inst/gptr/prompts"), recursive = TRUE)
dir.create(file.path(pkg, "R"))
writeLines(c("Package: gptrdemo", "Title: Demo gptr Plugin", "Version: 0.0.1", "Description: Demo.", "License: MIT",
             "Config/gptr/plugin: true", "Encoding: UTF-8"), file.path(pkg, "DESCRIPTION"))
writeLines("export(gptr_extension)", file.path(pkg, "NAMESPACE"))
writeLines(c("gptr_extension <- function(gptr) {", "  gptr$register_command('hello', description = 'Say hi', handler = function(args, ctx) ctx$ui$notify(paste('hi', args)))", "  invisible(NULL)", "}"), file.path(pkg, "R/ext.R"))
writeLines(c("---", "name: demo-skill", "description: Demo skill shipped inside an R package.", "---", "Body"), file.path(pkg, "inst/gptr/skills/demo-skill/SKILL.md"))
writeLines(c("function(gptr) {", "  gptr$on('tool_call', function(event, ctx) NULL)", "}"), file.path(pkg, "inst/gptr/extensions/audit.R"))
writeLines(c("---", "description: Demo template", "---", "Hello $1"), file.path(pkg, "inst/gptr/prompts/hello.md"))
out <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", "--no-docs", "--no-multiarch", paste0("--library=", shQuote(lib)), shQuote(pkg)), stdout = TRUE, stderr = TRUE)
cat(tail(out, 2), sep = "\n")
root <- system.file("gptr", package = "gptrdemo", lib.loc = lib)
cat("system.file root:", sub(tempdir(), "<tmp>", root, fixed = TRUE), "\n")
print(list.files(root, recursive = TRUE))
d <- utils::packageDescription("gptrdemo", lib.loc = lib)
cat("DESCRIPTION marker Config/gptr/plugin =", d[["Config/gptr/plugin"]], "\n")
ns <- loadNamespace("gptrdemo", lib.loc = lib)
cat("exported extension factory found:", is.function(getExportedValue(ns, "gptr_extension")), "\n")
f <- eval(parse(file.path(root, "extensions", "audit.R"), keep.source = FALSE)[[1L]], envir = new.env(parent = baseenv()))
cat("file extension evaluates to function:", is.function(f), " formals:", names(formals(f)), "\n")
```

Observed output (milliseconds; second of two runs):

```text
libPaths: 1  packages: 615 

                   first median min
A_dir.exists_all       4      4   4
B_Sys.glob_all         3      4   3
C_system.file_all    287    120 115
D_installed.pkgs     107    119 107
E_attached_only        1      0   0
F_loadedNamespaces     1      1   0
G_explicit_3           1      2   1

hits A: 0 
character(0)
attached: 7  loaded namespaces: 9 
** testing if installed package keeps a record of temporary installation path
* DONE (gptrdemo)
system.file root: <tmp>/plib/gptrdemo/gptr 
[1] "extensions/audit.R"         "prompts/hello.md"          
[3] "skills/demo-skill/SKILL.md"
DESCRIPTION marker Config/gptr/plugin = true 
exported extension factory found: TRUE 
file extension evaluates to function: TRUE  formals: gptr 
```

First run of the same script (different file-system cache state): `A_dir.exists_all 70 / 3 / 2`,
`B_Sys.glob_all 2 / 3 / 2`, `C_system.file_all 345 / 99 / 94`, `D_installed.pkgs 94 / 79 / 77`,
`E`, `F`, `G` all `0`. "hits A: 0" means that no package installed on this machine ships a `gptr/` or
`skills/` directory (btw is not installed).

### 5.10 NSE names, JSONL sink, RPC loop: `09-modes.R`

```r
# Prototype: (a) NSE capture of bare names, (b) JSONL event sink ("json mode"),
# (c) minimal RPC loop over stdin/stdout incl. the extension-UI sub-protocol.
library(jsonlite)

# ---- (a) bare names, like library(pkg) ------------------------------------------------
names_arg <- function(x, env = parent.frame(2L)) {
  # Call as names_arg(<formal>) from inside the user-facing function.
  # accepts: pdf | "pdf" | c(pdf, stats) | c("pdf", stats) | a character variable in the caller's scope
  e <- eval.parent(substitute(substitute(x)))
  one <- function(e) {
    if (is.null(e)) return(character())
    if (is.character(e)) return(e)
    if (is.symbol(e)) {
      nm <- as.character(e)
      if (exists(nm, envir = env, inherits = TRUE)) { v <- get(nm, envir = env); if (is.character(v)) return(v) }
      return(nm)
    }
    if (is.call(e) && identical(e[[1L]], quote(c))) return(unlist(lapply(as.list(e)[-1L], one)))
    if (is.call(e) && identical(e[[1L]], quote(`-`)) && length(e) == 2L) return(paste0("-", one(e[[2L]])))   # -write
    if (is.call(e) && as.character(e[[1L]]) %in% c("::", "$")) return(paste(deparse(e), collapse = ""))       # pkg::thing
    v <- eval(e, env); if (is.character(v)) v else stop("cannot interpret `", deparse(e), "` as names", call. = FALSE)
  }
  unique(one(e))
}
f <- function(skills = NULL, tools = NULL) list(skills = names_arg(skills), tools = names_arg(tools))
mine <- c("from-variable", "second")
stopifnot(identical(f(pdf)$skills, "pdf"), identical(f("pdf-tools")$skills, "pdf-tools"),
          identical(f(c(pdf, "data-analysis", stats))$skills, c("pdf", "data-analysis", "stats")),
          identical(f(mine)$skills, mine), identical(f()$skills, character()),
          identical(f(tools = c(read, -write))$tools, c("read", "-write")),
          identical(f(btw::skills)$skills, "btw::skills"))
cat("NSE names: OK\n")

# ---- (b) JSONL event sink ---------------------------------------------------------------
json_line <- function(x) paste0(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, force = TRUE), "\n")
write_bytes <- function(txt, con) {
  # cat()/textConnection() translate to the native encoding (lossy in a C locale): write UTF-8 bytes instead
  writeLines(enc2utf8(sub("\n$", "", txt)), con, sep = "\n", useBytes = TRUE)
}
new_jsonl_sink <- function(con = stdout()) function(event) { write_bytes(json_line(event), con); invisible(NULL) }
tmpf <- tempfile(fileext = ".jsonl"); sink_con <- file(tmpf, "wb")
emit_json <- new_jsonl_sink(sink_con)
emit_json(list(type = "session", version = 1L, id = "0001", timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"), cwd = "/path"))
emit_json(list(type = "agent_start"))
emit_json(list(type = "message_update", assistantMessageEvent = list(type = "text_delta", contentIndex = 0L, delta = "line1\nline2 \u2028 caf\u00e9")))
emit_json(list(type = "tool_execution_end", toolCallId = "c1", toolName = "R", isError = FALSE, result = list(content = list(list(type = "text", text = "[1] 32")))))
emit_json(list(type = "agent_settled"))
close(sink_con)
captured <- readLines(tmpf, warn = FALSE, encoding = "UTF-8")
stopifnot(length(captured) == 5L)                       # one record per line even with embedded \n and U+2028
back <- lapply(captured, jsonlite::fromJSON, simplifyVector = FALSE)
stopifnot(identical(charToRaw(back[[3]]$assistantMessageEvent$delta), charToRaw("line1\nline2 \u2028 caf\u00e9")))
cat("JSONL sink: OK (", length(captured), "records )\n")

# ---- (c) RPC loop ------------------------------------------------------------------------
rpc_loop <- function(input = file("stdin", "rb"), output = stdout(), handlers) {
  out <- function(x) { write_bytes(json_line(x), output); flush(output) }
  pending <- new.env(parent = emptyenv())
  read_record <- function() {
    ln <- readLines(input, n = 1L, warn = FALSE, encoding = "UTF-8")
    if (!length(ln)) return(NULL)                                     # EOF => orderly shutdown
    ln <- sub("\r$", "", ln)
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) structure(list(error = conditionMessage(e)), class = "parse_error"))
  }
  ui <- list(has_ui = TRUE,
    confirm = function(title, message = "") {
      id <- sprintf("ui-%d", length(ls(pending)) + 1L); assign(id, TRUE, envir = pending)
      out(list(type = "extension_ui_request", id = id, method = "confirm", title = title, message = message))
      repeat {                                                        # block until the matching response arrives
        r <- read_record(); if (is.null(r)) return(FALSE)
        if (identical(r$type, "extension_ui_response") && identical(r$id, id)) return(!isTRUE(r$cancelled) && isTRUE(r$confirmed))
        out(list(id = r$id, type = "response", command = r$type %||% "unknown", success = FALSE, error = "busy: waiting for extension_ui_response"))
      }
    })
  repeat {
    cmd <- read_record()
    if (is.null(cmd)) break
    if (inherits(cmd, "parse_error")) { out(list(type = "response", command = "parse", success = FALSE, error = paste("Failed to parse command:", cmd$error))); next }
    h <- handlers[[cmd$type %||% ""]]
    if (is.null(h)) { out(list(id = cmd$id, type = "response", command = cmd$type, success = FALSE, error = paste("Unknown command:", cmd$type))); next }
    res <- tryCatch(list(ok = TRUE, data = h(cmd, ui, out)), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    out(if (res$ok) c(list(id = cmd$id, type = "response", command = cmd$type, success = TRUE), if (!is.null(res$data)) list(data = res$data))
        else list(id = cmd$id, type = "response", command = cmd$type, success = FALSE, error = res$error))
  }
  invisible(NULL)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
if (identical(commandArgs(trailingOnly = TRUE), "rpc")) {
  rpc_loop(handlers = list(
    get_state = function(cmd, ui, out) list(isStreaming = FALSE, sessionId = "0001", messageCount = 0L),
    prompt = function(cmd, ui, out) {
      out(list(type = "agent_start"))
      ok <- ui$confirm("Allow R code?", "unlink('x')")
      out(list(type = "tool_execution_end", toolCallId = "c1", toolName = "R", isError = !ok))
      out(list(type = "agent_settled"))
      list(disposition = "started")
    }))
}
```

Observed output of `Rscript --vanilla 09-modes.R`:

```text
NSE names: OK
JSONL sink: OK ( 5 records )
```

Observed output of the RPC run, input piped on stdin
(`{"id":"1","type":"get_state"}`, `not json`, `{"id":"2","type":"prompt","message":"hi"}`,
`{"type":"extension_ui_response","id":"ui-1","confirmed":true}`, `{"id":"3","type":"nope"}`):

```text
NSE names: OK
JSONL sink: OK ( 5 records )
{"id":"1","type":"response","command":"get_state","success":true,"data":{"isStreaming":false,"sessionId":"0001","messageCount":0}}
{"type":"response","command":"parse","success":false,"error":"Failed to parse command: lexical error: invalid string in json text.\n                                       not json\n                     (right here) ------^\n"}
{"type":"agent_start"}
{"type":"extension_ui_request","id":"ui-1","method":"confirm","title":"Allow R code?","message":"unlink('x')"}
{"type":"tool_execution_end","toolCallId":"c1","toolName":"R","isError":false}
{"type":"agent_settled"}
{"id":"2","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}
{"id":"3","type":"response","command":"nope","success":false,"error":"Unknown command: nope"}
```

### 5.11 Resource filter patterns: `10-patterns.R`

```r
# Prototype: Pi resource filter patterns (plain include globs, !exclude, +force-include, -force-exclude)
glob_match <- function(x, pattern) {
  # minimatch-like: '*' does not cross '/', '**' does, '?' one char. Case-sensitive.
  rx <- gsub("([.+^$(){}|\\\\\\[\\]])", "\\\\\\1", pattern, perl = TRUE)
  rx <- gsub("**/", "\001", rx, fixed = TRUE); rx <- gsub("**", "\002", rx, fixed = TRUE)
  rx <- gsub("*", "[^/]*", rx, fixed = TRUE); rx <- gsub("?", "[^/]", rx, fixed = TRUE)
  rx <- gsub("\001", "(?:.*/)?", rx, fixed = TRUE); rx <- gsub("\002", ".*", rx, fixed = TRUE)
  grepl(paste0("^", rx, "$"), x, perl = TRUE)
}
rel_to <- function(path, base) {
  path <- gsub("\\\\", "/", path); base <- sub("/+$", "", gsub("\\\\", "/", base))
  ifelse(startsWith(path, paste0(base, "/")), substring(path, nchar(base) + 2L), path)
}
matches_any <- function(path, patterns, base, exact = FALSE) {
  if (!length(patterns)) return(FALSE)
  path <- gsub("\\\\", "/", path)                          # normalise BEFORE basename()/dirname(): portable on all OSes
  cand <- c(rel_to(path, base), if (!exact) basename(path), path)
  if (basename(path) == "SKILL.md") {                      # a skill can be addressed by its directory
    d <- dirname(path); cand <- c(cand, rel_to(d, base), if (!exact) basename(d), d)
  }
  patterns <- sub("^\\./", "", gsub("\\\\", "/", patterns))
  for (p in patterns) if (any(if (exact) cand == p else glob_match(cand, p))) return(TRUE)
  FALSE
}
apply_patterns <- function(paths, patterns, base) {
  inc <- patterns[!grepl("^[!+-]", patterns)]
  exc <- substring(patterns[startsWith(patterns, "!")], 2L)
  finc <- substring(patterns[startsWith(patterns, "+")], 2L)
  fexc <- substring(patterns[startsWith(patterns, "-")], 2L)
  keep <- if (length(inc)) vapply(paths, matches_any, NA, inc, base) else rep(TRUE, length(paths))
  keep <- keep & !vapply(paths, matches_any, NA, exc, base)
  keep <- keep | vapply(paths, matches_any, NA, finc, base, exact = TRUE)
  keep <- keep & !vapply(paths, matches_any, NA, fexc, base, exact = TRUE)
  paths[keep]
}

base <- "/pkg"
files <- c("/pkg/extensions/a.R", "/pkg/extensions/legacy.R", "/pkg/extensions/sub/b.R",
           "/pkg/skills/pdf/SKILL.md", "/pkg/skills/stats/SKILL.md", "/pkg/prompts/review.md")
b <- function(x) sub("^/pkg/", "", x)
stopifnot(
  identical(b(apply_patterns(files, character(), base)), b(files)),
  identical(b(apply_patterns(files, c("extensions/*.R", "!extensions/legacy.R"), base)), "extensions/a.R"),
  identical(b(apply_patterns(files, "extensions/**", base)), c("extensions/a.R", "extensions/legacy.R", "extensions/sub/b.R")),
  identical(b(apply_patterns(files, "!legacy.R", base)), b(files[-2])),                       # basename match
  identical(b(apply_patterns(files, c("!skills/*", "+skills/pdf"), base)), b(files[-5])),     # skill addressed by dir
  identical(b(apply_patterns(files, c("!*.R", "+extensions/a.R"), base)), b(files[c(1, 4, 5, 6)])),
  identical(b(apply_patterns(files, c("+extensions/a.R", "-extensions/a.R"), base)), b(files[-1])),  # force-exclude wins
  identical(b(apply_patterns(files, "prompts/review.md", base)), "prompts/review.md"),
  identical(b(apply_patterns(gsub("/", "\\\\", files[1:2]), "!legacy.R", "\\pkg")), "\\pkg\\extensions\\a.R")  # Windows separators
)
cat("pattern filters: OK\n")
```

Observed output:

```text
pattern filters: OK
```

### 5.12 What was not run

- Nothing was executed on Windows or Linux.
- No LLM or Jev API call was made; the agent loop in `04-extensions.R` is driven by a scripted model.
- Interactive dialogs were exercised through an injected input function, not a real terminal, RStudio,
  Positron or Jupyter front end.
- Pi itself was not executed (no `npm install`); all Pi statements come from reading source and docs.
- `rstudioapi` dialogs, `processx`-based `exec`, `.gitignore` handling, git/GitHub skill installation,
  MCP registration from extensions and provider registration were not prototyped.

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN Repository Policy (revision 6875, fetched 2026-09-29)

Quoted rules and their consequence for this track:

| Policy text | Consequence |
|---|---|
| "Packages should not write in the user's home filespace (including clipboards), nor anywhere else on the file system apart from the R session's temporary directory" | gptr never creates `~/.gptr`. It only *reads* it when present. `.gptr/` in a project (REQ-27) is created only by an explicit call (`gptr_init()`) or after an interactive confirmation. `/copy` writes the clipboard only on explicit user command. |
| "For R version 4.0 or later ... packages may store user-specific data, configuration and cache files in their respective user directories obtained from `tools::R_user_dir()`" | default user directory; `Depends: R (>= 4.1)`. Keep it small and managed: settings, trust store, user skills; sessions belong to `R_user_dir("gptr", "data")` or the project. |
| "Limited exceptions may be allowed in interactive sessions if the package obtains confirmation from the user." | first write to the user directory happens from `gptr_setup()` / `gptr_set()` / `/trust`, all user-initiated. |
| "Packages should not modify the global environment (user's workspace)." | extension files are evaluated in a fresh environment (parent `globalenv()` for user files, the package namespace for plugin files); verified that loading an extension file leaves `globalenv()` untouched. Objects created by the agent's R tool are the user's explicit request; examples and tests must pass `envir = new.env()`. |
| "Packages which use Internet resources should fail gracefully with an informative message" | `gptr_skill_install()` from GitHub must catch download errors; nothing in this track needs the network at load time. |
| "... must never use more than two [cores] simultaneously" | not relevant to this track (everything is sequential). |
| "Packages should not start external software ... during examples or tests" | `exec`, editor dialogs and browser-based flows must not run in examples/tests. |

Other R CMD check points:

- **ASCII-only R sources** (non-ASCII literals broke my first test run in a C locale). Use `\uxxxx`.
- Files under `inst/gptr/extensions/*.R` are *not* analysed by `R CMD check` (no codetools, no usage
  checks). Recommendation: implement the built-in extensions as ordinary internal functions in `R/`
  (`builtin_permissions <- function(gptr) ...`) and register them under the names `builtin:permissions`,
  `builtin:plan`, `builtin:ask-user`, `builtin:todo`; ship only *skills* and *prompts* in `inst/gptr/`.
- Examples and tests must never prompt: guard with `if (interactive())` and give every dialog function a
  non-interactive default. Tests inject a scripted UI (as in `04b-examples.R`).
- Tests must set `GPTR_HOME` (and `R_USER_CONFIG_DIR`) to a temporary directory and clean up.
- `parse()` + `eval()` of extension files is not forbidden by policy, but must not happen at package load
  or in checks except on files created by the test itself.
- The repository's own `dev/` and `.gptr/` directories must be listed in `.Rbuildignore`.
- Keep paths inside `inst/` short (tar header limit 100 bytes produces check NOTEs).
- Dependencies: `jsonlite` and `yaml` are small, dependency-free packages (both need compilation
  themselves, which does not conflict with REQ-01 because gptr contains no compiled code). VERIFIED:
  installed `yaml 2.3.12` has no Imports/Depends; `jsonlite 2.0.0` depends on `methods` only.

### 6.2 Windows specifics

| Topic | Fact | Evidence | Action |
|---|---|---|---|
| Home directory | On Windows R's `~` is `R_USER`, else `HOME`, else the "personal" directory, "typically `C:\Users\username\Documents`"; only then `HOMEDRIVE`/`HOMEPATH` | R for Windows FAQ 2.13 (fetched) VERIFIED | Other agents store `.claude`, `.codex`, `.agents` in `%USERPROFILE%`; use `Sys.getenv("USERPROFILE")` (prototype `user_home()`); never `path.expand("~")` for compatibility folders |
| User config directory | `tools::R_user_dir("gptr", "config")` = `%APPDATA%/R/config/R/gptr`; data = `%APPDATA%/R/data/R/gptr`; cache = `%LOCALAPPDATA%/R/cache/R/gptr`; overridable with `R_USER_CONFIG_DIR`, `XDG_CONFIG_HOME` | source of `tools::R_user_dir` printed locally VERIFIED | document the location in `?gptr_settings`; `gptr_home()` prints it |
| Path separators | R accepts `/` and `\`; model-facing paths and trust keys should use `/` | FAQ 2.15 VERIFIED; Pi renders cwd with `/` | `normalizePath(winslash = "/", mustWork = FALSE)` everywhere; pattern matcher normalises before `basename()` (a bug of exactly this kind was found and fixed in `10-patterns.R`) |
| Case-insensitive file system | `file.exists("CLAUDE.MD")` is true for `CLAUDE.md` on NTFS/APFS, while `"CLAUDE.MD" %in% list.files()` is false | VERIFIED on APFS (macOS) by the verifier; NTFS LIKELY | match context-file candidates against `list.files()` output (prototype `context_file_in()`); lower-case trust keys on Windows |
| Path length | 260-character limit unless long paths are enabled (Windows 10 1607+ and R 4.3+) | FAQ 2.15 VERIFIED | keep `.gptr` layouts shallow; report a clear error when `dir.create()` fails |
| Encoding | UTF-8 is the native encoding only with R >= 4.2 on Windows 10 1903+ | FAQ 2.2 VERIFIED | always read bytes and mark UTF-8; write with `useBytes = TRUE`; never rely on the locale (section 5.1) |
| Line endings / BOM | `SKILL.md`, `settings.json` edited with Windows tools may contain CRLF and a BOM | tested in `01-skills.R`, `03-settings.R` VERIFIED | strip BOM, normalise `\r\n` |
| Atomic replace | `file.rename()` onto an existing or locked file may fail on Windows | LIKELY (documented in `?file.rename`: behaviour is platform-dependent) | prototype falls back to `file.copy(overwrite = TRUE)`; retry a few times for antivirus locks |
| File locks | base R has no advisory file locking; Pi uses `proper-lockfile` | VERIFIED (Pi source); R: no base API | re-read immediately before writing and write only modified fields; optional `filelock` later |
| Symlinks | skill installers for other agents often symlink skill folders; symlink creation on Windows needs privileges, so copies/junctions are common | UNCERTAIN | de-duplicate by `normalizePath()` result and by name |
| Shell | no POSIX shell may be assumed (REQ-03, REQ-09) | requirement | `gptr$exec(command, args)` without shell; Pi's plan-mode bash allowlist is replaced by the R code classifier |
| Console input | `readline()` works in Rterm, RGui, RStudio, Positron consoles when `interactive()`; returns `""` otherwise | non-interactive part VERIFIED; GUI part LIKELY | `has_ui` guard; optional `rstudioapi::showQuestion()` / `showPrompt()` |
| Scripts in skills | skills written for other agents reference `scripts/*.sh` or Python | observed in real skills, LIKELY common | show `compatibility` in `/skills`; the model decides; gptr does not execute skill scripts by itself |

### 6.3 Front ends

| Front end | `interactive()` | Dialog strategy | Confidence |
|---|---|---|---|
| Terminal R | TRUE | `readline()` | VERIFIED for the non-interactive contrast only |
| `Rscript`, `R CMD BATCH`, cron | FALSE | none: safe defaults, fail closed | VERIFIED |
| RStudio / Positron console | TRUE | `readline()`; optionally `rstudioapi` dialogs | LIKELY |
| knitr / rmarkdown / Quarto render | FALSE when rendered in a separate R process (and `getOption("knitr.in.progress")` is TRUE); stays TRUE if `knit()`/`render()` is called from an interactive console, which is why `gptr_has_ui()` also checks the option | none | VERIFIED for `knitr::knit()` under `Rscript` (knitr 1.51: `interactive()` FALSE, option TRUE); console case LIKELY |
| Jupyter (IRkernel) | kernel-dependent | treat as no UI unless `options(gptr.ui = TRUE)` | UNCERTAIN |
| Shiny app (REQ-39) | FALSE | app-provided `ui` object (modal dialogs) passed through `gptr_session(ui = )` | UNCERTAIN, design only |

---

## 7. Risks, pitfalls, open questions

### 7.1 Risks and pitfalls

1. **Extensions are arbitrary code with the user's privileges.** Pi states this explicitly
   (`docs/extensions.md`, `docs/security.md`). In R the same holds, plus the code runs inside the session
   that holds the user's data. Trust gating of project extensions and opt-in loading of plugin-package
   extensions are the only mitigations; there is no sandbox.
2. **The R code classifier is a heuristic, not a security boundary.** It cannot see through S4/R6 method
   dispatch, user-defined wrappers (`my_cleanup()` that calls `unlink()`), operators overloaded by loaded
   packages, or functions whose names are not in the table. It treats unknown functions as harmless
   ("read-only" when nothing assigns). A stricter plan mode could use an allowlist instead (only calls
   from a known read-only set such as `str`, `head`, `summary`, `ls`, `class`, `dim`, `names`, `nrow`),
   at the cost of many false blocks. Needs a decision.
3. **Prompt injection through skills and context files.** Skills from `.agents/skills`/`.claude/skills` of a
   cloned repository are instructions to the model; they are trust-gated in the proposal, but context files
   (`AGENTS.md`, `.gptr/vignette.Rmd`) are not (same as Pi). Combined with `permissionMode = "auto"` this is
   dangerous; the documentation must say so.
4. **`utils::askYesNo()` returns TRUE non-interactively** (verified). Any approval path built on it would
   auto-approve under `Rscript`.
5. **One-element arrays in JSON.** `fromJSON(simplifyVector = TRUE)` + `toJSON(auto_unbox = TRUE)` turns
   `["a"]` into `"a"` (verified) and would corrupt `skills`, `plugins`, `defaultTools`. Always read
   settings with `simplifyVector = FALSE`.
6. **No file locking.** Two R sessions writing `settings.json` or `trust.json` at the same moment can
   lose an update. Field-level merge + atomic rename makes the window small, not zero.
7. **Catalog size.** Real machines accumulate skills (68 skill files loaded here: 65 `SKILL.md` plus 3
   standalone `.md`; 37 unique names, 23.5k characters). Without a budget the system prompt grows by about 6k tokens per session.
8. **Name collisions across ecosystems.** Claude Code gives personal skills precedence over project
   skills; Pi, Codex and the agentskills.io guide give project precedence. gptr follows the latter; a user
   coming from Claude Code may be surprised.
9. **Handlers block the loop.** A slow `message_update` handler slows streaming; a handler that never
   returns hangs the session. Mitigation: document; wrap dispatch in `tryCatch(interrupt = )` so Ctrl-C
   aborts the handler and the run (REQ-38).
10. **Stale API objects after reload.** R closures keep references; an extension that stored `gptr` or
    `ctx` in a global could keep calling into a dead runtime. The runtime must mark replaced API objects
    as stale and make every method raise a clear error (Pi does the same).
11. **Argument matching with `...`** (verified bug class, section 5.5) affects `gptr()` itself:
    `gptr("prompt", model = x, m = 3)` style partial matching of user arguments to formals. Put `...`
    early in signatures and use dot-prefixed internal formals.
12. **Synchronous RPC** cannot process `abort` while a model request is streaming unless the HTTP layer
    polls stdin. Pi clients that expect immediate abort responses would not work unchanged.
13. **Plan extraction from prose** (Pi's approach, reproduced in the prototype) is fragile: it depends on a
    literal `Plan:` header and numbered lines.
14. **Pi moves fast.** Version 0.99.1 contains features that did not exist a few months earlier
    (`agent_before_settle`, tool `exposure`, `context_with_system`, virtual models, experimental Chord
    plugins). Copying the whole surface would chase a moving target; the P0/P1/P2 split above limits the
    commitment.
15. **`yaml` type coercion.** YAML 1.1 parsers turn unquoted `yes`/`no`/`on`/`off` into logicals and
    `1.0` into a number; a skill named `no` or a `version: 1.0` metadata value changes type. The loader must
    check `is.character()` before using `name`/`description` (the prototype does) and should coerce
    `metadata` values with `as.character()`. VERIFIED by the verifier with yaml 2.3.12:
    `yaml.load("a: yes\nb: 1.0\nc: no\nd: on")` gives `TRUE`, `1` (numeric), `FALSE`, `TRUE`.

### 7.2 Open questions for the maintainer / design spec

1. **Meaning of `gptr("prompt", skills = ...)`** (REQ-17): pre-load the named skills into the prompt
   (proposed), or restrict the catalog to them, or add extra skill directories?
2. **Default tool set**: only `read`, `write`, `edit`, `R` (Pi-like minimal set, REQ-10) with the rule "use
   R for listing and searching", or also `grep`/`find`/`ls` active by default (REQ-07, REQ-08)?
3. **Plan-mode strictness** for R code: denylist classifier (proposed) or strict read-only allowlist?
4. **User directory**: is reading an existing `~/.gptr` desired, or should gptr use `R_user_dir` only?
   (btw reads `~/.btw`, `~/.config/btw` and `R_user_dir`.)
5. **Instructions file**: REQ-27 names `.gptr/vignette.Rmd`. Should `AGENTS.md`/`CLAUDE.md` in the same
   directory be loaded in addition to it or be replaced by it (proposed: replaced, other directories still
   contribute)? Should a user-level `vignette.Rmd` exist?
6. **Compatibility folders on by default?** Scanning `~/.claude/skills` and `~/.codex/skills` exposes
   skills written for other tools (shell/Python scripts). Default proposed: on, because the catalog only
   costs tokens and the model can ignore them; the budget limits the cost.
7. **Should `permissionMode` be settable by a trusted project at all?** Proposed: only towards stricter.
8. **Extension file contract**: "last expression is `function(gptr)`" (proposed; terse, R-like) versus
   "file defines `gptr_extension`" (more explicit). The prototype accepts both.
9. **RPC mode in v1?** It is feasible (prototype) but has the abort limitation; json mode (event callback)
   is cheap and sufficient for IDE integrations that run R in-process.
10. **Session tree / fork events**: depend on whether gptr sessions are trees (Pi) or linear documents
    (REQ-24). If linear, `session_before_fork`, `session_tree`, `session_before_tree` are not needed.
11. **Jev from extensions**: Pi exposes `ctx.modelRegistry.classify()`. Should `ctx` offer
    `ctx$decide(question, ...)` so that permission extensions can use System 1 for risk scoring?

---

## 8. Sources

### 8.1 Local source (Pi commit `1b347794e2a630e4359f2584f4eea388145d0ddf`)

Documentation, all under `$CA/docs/`: `extensions.md`, `skills.md`, `prompt-templates.md`, `packages.md`,
`settings.md`, `configuration.md`, `slash-commands.md`, `sdk.md`, `rpc.md`, `rpc-extension-ui.md`,
`rpc-commands.md` (prompt disposition lines 37-90), `json.md`, `cli.md`, `cli-integration.md`,
`security.md`, `keybindings.md` (lines 1-80), `mcp.md` (lines 1-60).

Source files read (full unless a range is given):

- `$CA/src/core/extensions/types.ts` (2240 lines), `runner.ts` (1551), `loader.ts` (856), `wrapper.ts`,
  `virtual-modules.ts`
- `$CA/src/core/skills.ts`, `prompt-templates.ts`, `resource-loader.ts`, `pi-manifest.ts`,
  `slash-commands.ts`, `project-trust.ts`, `trust-manager.ts`, `system-prompt.ts`, `event-bus.ts`,
  `source-info.ts`, `exec.ts` (1-45)
- `$CA/src/core/package-manager.ts` lines 60-1060, 1400-1510, 2085-2665
- `$CA/src/core/settings-manager.ts` lines 1-850 and accessor excerpts
- `$CA/src/core/agent-session.ts` lines 600-730, 1820-2120, 2186-2270, 3160-3340, 3400-3530
- `$CA/src/core/sdk.ts` lines 1-200
- `$CA/src/utils/frontmatter.ts`, `$CA/src/utils/git.ts` (1-200), `$CA/src/utils/paths.ts` (50-75), `$CA/src/config.ts` (grep)
- `$CA/src/modes/print-mode.ts`, `json-event.ts`, `index.ts`, `rpc/rpc-types.ts`, `rpc/rpc-mode.ts` (1-330),
  `interactive/interactive-mode.ts` (3096-3294)
- `$PI/packages/agent/src/agent-loop.ts` (535-560, 690-820), `$PI/packages/agent/src/types.ts` (420-470)
- `$CA/test/prompt-templates.test.ts` (assertions ported to R)
- Examples under `$CA/examples/extensions/`: `permission-gate.ts`, `confirm-destructive.ts`,
  `protected-paths.ts`, `plan-mode/{README.md,index.ts,utils.ts}`, `question.ts`, `questionnaire.ts` (1-110),
  `qna.ts`, `todo.ts`, `handoff.ts`, `tool-override.ts`, `tools.ts`, `dynamic-tools.ts`, `commands.ts`,
  `input-transform.ts`, `preset.ts` (1-140), `custom-compaction.ts`, `structured-output.ts`,
  `send-user-message.ts`, `timed-confirm.ts`, `project-trust.ts`, `claude-rules.ts`, `jev-router.ts`
- `$CA/examples/sdk/01, 03, 04, 06, 07, 08, 10, 12`; `$CA/examples/plugins/pi-example-plugin/` (README,
  `package.json`, `src/contract.ts`, `src/session.ts`)
- `$PI/.pi/prompts/{pr,is,cl}.md`, `$PI/.pi/skills/{release,interactive-testing}.md`,
  `$PI/.pi/extensions/tps.ts`, `$PI/AGENTS.md`

### 8.2 Web (all fetched 2026-09-29)

- Agent Skills specification: https://agentskills.io/specification
- Agent Skills integration guide: https://agentskills.io/integrate-skills
- Claude Code skills documentation: https://code.claude.com/docs/en/skills
- Codex skills documentation: https://learn.chatgpt.com/docs/build-skills (redirect target of
  https://developers.openai.com/codex/skills)
- btw reference manual (version 1.5.0.9000): https://posit-dev.r-universe.dev/btw/doc/manual.html
- btw source, skills: https://raw.githubusercontent.com/posit-dev/btw/main/R/tool-skills.R
- CRAN Repository Policy (revision 6875): https://cran.r-project.org/web/packages/policies.html
- R for Windows FAQ (sections 2.2, 2.13, 2.15): https://cran.r-project.org/bin/windows/base/rw-FAQ.html

Web pages were read through a summarising fetch tool; quotations from them in this report are the tool's
rendering of the page and should be re-checked against the live page before being cited externally.

### 8.3 Local experiments

Scripts and captured outputs: `$W/*.R`, `$W/out/*.txt` (scratch directory, may be deleted after the
session; the complete code and output are reproduced in section 5). Local facts used: installed package
versions (`00-pkgs.R`), `tools::R_user_dir` source (printed with `Rscript -e 'print(tools::R_user_dir)'`),
directory listings of `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills` (names only).

---

## Verification log

Independent fact-check, 2026-09-29, against the Pi clone at commit `1b347794e2a6...` (`@earendil-works/pi-coding-agent`
0.99.1, confirmed), R 4.4.3 on macOS arm64 (`Rscript --vanilla`), and the live web pages named below. Every R block
in section 5 was re-extracted from this report (not from the author's scratch files) into
`scratchpad/work/verify-05/mine/` and re-run; the design snippet `gptr_has_ui()` from 4.12 was run as well.
Pi itself was not executed. Verdicts: **confirmed** = matches the source; **corrected** = the report was edited;
**unverifiable** = no primary evidence could be obtained here.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | 41 extension events | confirmed | `types.ts:1540-1607` (41 distinct `on("...")` overloads) |
| 2 | Action methods throw `Extension runtime not initialized. Action methods cannot be called during extension loading.` until bound | confirmed | `loader.ts:156-236` |
| 3 | Precedence ranks 0-5; CLI paths merged first | confirmed | `package-manager.ts:180-198`; `resource-loader.ts:564-589` |
| 4 | Skill constants (64 / 1024 / ignore files) and validation messages verbatim | confirmed | `skills.ts:10-16, 91-127` |
| 5 | Invalid name only warns; missing description or unparseable YAML rejects; no name/dir equality check | confirmed | `skills.ts:277-345`; `utils/frontmatter.ts` |
| 6 | Skill catalog text and XML escaping | confirmed (precision note added: source string starts with `\n\n`, trimmed by `system-prompt.ts`) | `skills.ts:347-386`; `system-prompt.ts:164-168` |
| 7 | `/skill:name` expansion block | confirmed | `agent-session.ts:2062-2086` |
| 8 | Template substitution regex, argument parser, command regex, 60-char description fallback | confirmed | `prompt-templates.ts:25-103, 129-141, 304-320` |
| 9 | 67 ported template assertions come from Pi's test-suite | confirmed (spot-checked 8) | `$CA/test/prompt-templates.test.ts` |
| 10 | `deepMergeObjects`, `DEFAULT_TOOL_NAMES`, `mergeDefaultTools`, `resolveDefaultTools` verbatim | confirmed | `settings-manager.ts:188-245` |
| 11 | Settings defaults in 3.8 (compaction 16384/20000, retry 3/2000/60000, provider retries 0, idle 300000, websocket 15000, codemode, markdown, terminal, images, theme, ...) | confirmed (about 25 rows spot-checked) | `settings-manager.ts:19-60, 998-1041`; `docs/settings.md` |
| 12 | User-only keys; `httpProxy` enforcement "not located in source" | **corrected**: `httpProxy` is enforced (`main.ts:588, 865` read `getGlobalSettings()`), added to the user-only list in 1.8 and 3.8 | `main.ts`, `settings-manager.ts:149-180, 1021-1104, 1173` |
| 13 | Settings lock 10 x 20 ms; untrusted project write throws; broken global file never overwritten | confirmed | `settings-manager.ts:302-327, 660-664, 734-748` |
| 14 | 24 built-in slash commands (names, descriptions, hints); hidden `/debug`, `/arminsayshi`, `/dementedelves`; `/mcp`, `/llama` from built-ins | confirmed | `slash-commands.ts:19-44`; `interactive-mode.ts:3217-3231`; `extensions/llama/index.ts:183`, `extensions/mcp/index.ts:901` |
| 15 | Trust prompt text, five options, resolution order, gated resources, `~/.agents/skills` exclusion | confirmed | `project-trust.ts:24-96`; `trust-manager.ts:26-95, 180-208` |
| 16 | `tool_call`: no try/catch, throwing handler becomes a blocked error result; `tool_execution_start` before validation; default reason `Tool execution was blocked`; `terminate` only if every result sets it | confirmed | `runner.ts:1233-1251`; `agent-session.ts:617-640`; `agent-loop.ts:541-549, 690-775` |
| 17 | Generic emit: notify semantics, cancel = first `cancel: true` returns | confirmed | `runner.ts:1079-1107` |
| 18 | RPC `extension_ui_request` / `extension_ui_response` shapes | confirmed | `rpc/rpc-types.ts:245-296` |
| 19 | `ExtensionMode`, `hasUI` true in TUI and RPC; no-op UI in json/print | confirmed | `types.ts:323-331`; `runner.ts:323-354` |
| 20 | JSON header `version: 3`; print mode exit 1 on `error`/`aborted`; json mode exit code unchanged; print mode when stdin/stdout redirected | confirmed | `session-manager.ts:41`; `print-mode.ts:120-158`; `docs/json.md:26`; `docs/cli.md:30` |
| 21 | Package constants, filter grammar and order, per-type file patterns | confirmed | `package-manager.ts:50-52, 208-217, 745-791` |
| 22 | Duplicate commands renamed `name:N`; first tool registration wins | confirmed | `runner.ts:628-639, 798-832` |
| 23 | Pi does not scan `.claude/skills` / `.codex/skills`; `.agents/skills` scanned from cwd up to git root | confirmed | grep over `$CA/src`, `$CA/docs`, `README.md`; `package-manager.ts:455-485` |
| 24 | All four built-in extensions are `replaceable` | **corrected**: `llama.cpp` is built-in but not replaceable | `$CA/src/extensions/index.ts:7-14`; `docs/sdk.md:112` |
| 25 | Skill keys `license`/`compatibility`/`metadata`/`allowed-tools` "no reference outside the type" | **corrected** (wording): the type does not name them at all; they fall under an index signature | `skills.ts:67-72` |
| 26 | Default preamble, section-name regex, forward-slash `cwd`, `<project_instructions>` rendering | confirmed | `system-prompt.ts:52, 76, 107-116, 137-178` |
| 27 | Context-file candidate order, ancestors outermost-first, not trust-gated | confirmed | `resource-loader.ts:184-270`; `docs/security.md:57` |
| 28 | CLI flag spellings in 3.12 | confirmed | `docs/cli.md:63-243` |
| 29 | Annotation approval rule; nested-call limits 8 KiB / 32 KiB / 256; `ThinkingLevel` values | confirmed | `docs/extensions.md:148, 166-173`; `packages/agent/src/types.ts:349` |
| 30 | SDK sessions do not load built-ins; RPC `disposition`, wait for `agent_settled` | confirmed | `docs/sdk.md:116`; `docs/rpc.md:64-69` |
| 31 | `02-templates.R`: 67 pass in C and UTF-8 locales | confirmed (re-run) | Rscript, `LANG` unset and `LANG=en_US.UTF-8` |
| 32 | `02b-encoding.R` byte outputs (incl. `cat()` writing `<U+00E9>` in C locale) | confirmed byte-for-byte | Rscript, both locales |
| 33 | `01-skills.R` output | confirmed (re-run) | Rscript |
| 34 | `01b-real-skills.R`: 37 vs 33 skills, 31 collisions, 12 "description is required", 27/37 identical, 23,552 chars | confirmed (re-run, identical); **corrected** the interpretation "hand parser lost 12 of them / 12 of 37" (it rejected 12 of 65 files, lost 4 of 37 unique names, garbled 6 more) in 1.6 and 4.14 | Rscript |
| 35 | 21 of 65 `SKILL.md` use `description: >`; "68 `SKILL.md` files" | confirmed 21/65; **corrected** 68 = 65 `SKILL.md` + 3 standalone Pi `.md` (71 `SKILL.md` exist incl. 6 under hidden `.codex/skills/.system`) | `find` + `awk` over frontmatter lines only |
| 36 | `03-settings.R` stopifnot and outputs | confirmed (re-run) | Rscript |
| 37 | `04b-examples.R` (+ `04`, `07`): 38/38 checks; per-extension split 12/9/2/4 | confirmed (re-run) | Rscript |
| 38 | `07-codecalls.R` verdicts; "500-line script in 0.05 s" vs captured 0.129 s | verdicts confirmed; timing **corrected** to 0.05-0.13 s (verifier: 0.051-0.056 s) | Rscript, three runs |
| 39 | `06-ui.R`: `askYesNo()` TRUE, `menu()` error, `readline()` "" non-interactively | confirmed (re-run with piped stdin); `formals(askYesNo)$default` is `TRUE` | Rscript |
| 40 | `08-trust.R` trust resolution and context-file order | confirmed (re-run) | Rscript |
| 41 | `05-pkgscan.R` timings and plugin-package install layout | layout confirmed; timings reproduce in order of magnitude, ranges **corrected** (1.11 and 4.10 table) to cover four runs | Rscript twice, temporary library under the verifier's scratch dir |
| 42 | `09-modes.R` NSE, JSONL sink, RPC transcript | confirmed byte-for-byte (re-run) | Rscript, piped stdin |
| 43 | `10-patterns.R` | confirmed (re-run) | Rscript |
| 44 | `gptr_has_ui()` design snippet "not run" | now run: behaves as described | Rscript and `R --interactive` |
| 45 | `id` formal captures a named `id` argument through `...` | confirmed (exact matching) | Rscript |
| 46 | YAML 1.1 coercion of `yes`/`no`/`on`/`1.0` (was LIKELY) | upgraded to VERIFIED | Rscript, yaml 2.3.12 |
| 47 | Case-insensitive `file.exists()` (was LIKELY) | upgraded: VERIFIED on APFS, NTFS still LIKELY | Rscript on this Mac |
| 48 | knitr: `interactive()` FALSE, `knitr.in.progress` TRUE (was LIKELY) | upgraded: VERIFIED under `Rscript` + `knitr::knit()` (knitr 1.51); console-knit nuance added as LIKELY | Rscript |
| 49 | `tools::R_user_dir()` Windows paths and env overrides | confirmed | function source printed locally |
| 50 | `system2()` has `timeout`; R >= 4.0 for `R_user_dir` | confirmed | `formals(system2)`; CRAN policy wording |
| 51 | yaml 2.3.12 (no Depends/Imports), jsonlite 2.0.0 (Depends: methods), both compiled | confirmed installed and current on CRAN (published 2025-12-10 / 2025-03-27) | `packageDescription()`; cran.r-project.org/package=yaml, =jsonlite |
| 52 | CRAN Repository Policy quotes, revision 6875 | confirmed | cran.r-project.org/web/packages/policies.html |
| 53 | R for Windows FAQ 2.2, 2.13, 2.15 statements | confirmed | cran.r-project.org/bin/windows/base/rw-FAQ.html |
| 54 | btw 1.5.0.9000: skill directories, `attached_package_skill_dirs()` over `.packages()` with `system.file("skills")`, `btw_tool_skill`, `btw.md > AGENTS.md > CLAUDE.md` | confirmed | btw `R/tool-skills.R`, `DESCRIPTION`, r-universe manual |
| 55 | Claude Code skills: enterprise > personal > project, 1,536-char cap, `$N` 0-based, frontmatter keys, `.claude/commands` equivalence | confirmed | code.claude.com/docs/en/skills |
| 56 | agentskills.io spec limits and integration-guide advice (scan dirs, `.claude/skills` note, depth 4-6 / 2000 dirs, project over user, colon repair, allowlisting, compaction, dedupe) | confirmed | agentskills.io/specification, /integrate-skills |
| 57 | Codex skill locations, `agents/openai.yaml`, `$skill-name` | confirmed | learn.chatgpt.com/docs/build-skills (redirect target) |

Not verifiable here (left with their existing LIKELY/UNCERTAIN labels): all Windows behaviour and NTFS
case-insensitivity; RStudio/Positron/Jupyter dialog behaviour; package-scan cost on network drives or very large
libraries; runtime behaviour of Pi itself (only source and docs were read); the RPC-mode no-op setter list in
`rpc-mode.ts:138-317` (not re-read by the verifier).

