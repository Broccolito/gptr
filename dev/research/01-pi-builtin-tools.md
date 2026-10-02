# Track 01 — Pi built-in tools exposed to the LLM, and their mapping to a pure-R tool layer for gptr

Research date: 2026-09-29. Author: research sub-agent (track 01).

Primary source: local read-only clone of Pi at
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi`,
commit `1b347794e2a630e4359f2584f4eea388145d0ddf` (2026-09-29), package versions `0.99.1`
(`@earendil-works/pi-coding-agent`, `pi-agent-core`, `pi-ai`).
All `pi/...` paths below are relative to that clone root. Abbreviations:
`CA` = `pi/packages/coding-agent`, `AG` = `pi/packages/agent`, `AI` = `pi/packages/ai`.

Evidence levels: **VERIFIED** = I read the cited source lines / ran the cited command myself;
**LIKELY** = inferred from verified evidence; **UNCERTAIN** = could not verify (mostly Windows runtime behaviour: this machine is macOS arm64).

Requirement IDs (`REQ-nn`) refer to `/Users/wanjun/Desktop/gptr/dev/spec/00-vision-brief.md`.

---

## 1. Executive summary

1. **Pi ships exactly eight built-in tools**: `read`, `bash`, `powershell`, `edit`, `write`, `grep`, `find`, `ls` (`CA/src/core/tools/index.ts:95-105`). **Only four are active by default: `read`, `bash`, `edit`, `write`** (`CA/src/core/settings-manager.ts:213`, `CA/src/core/tools/index.ts:164-171`). `grep`/`find`/`ls` form an opt-in "read-only" set; `powershell` is opt-in and Windows-only. Two more tools (`codemode`, `tool_search`) come from built-in extensions and are registered inactive. VERIFIED.
2. **Every tool returns `{content: (text|image)[], details, isError?}`. Only `content` and `isError` reach the model**; `details` (diffs, truncation metadata, temp-file paths) is UI/log only (`AG/src/types.ts` `AgentToolResult`; `AI/src/api/anthropic-messages.ts:1220-1227`). The `edit` tool therefore tells the model only `Successfully replaced N block(s) in <path>.` — the diff is never sent to the model. VERIFIED.
3. **Errors are plain text.** A tool throws; the agent loop converts the exception message into a tool result with `isError: true` (`AG/src/agent-loop.ts:820-851, 905-910`). Unknown tool → `Tool <name> not found`; schema failure → `Validation failed for tool "<name>": ...` plus the received JSON (`AI/src/utils/validation.ts:341-349`). VERIFIED.
4. **Two global limits govern all output: 2000 lines and 50 KB (51200 bytes), whichever is hit first** (`CA/src/core/tools/truncate.ts:11-12`). File-like output is **head**-truncated (`read`, `grep`, `find`, `ls`); command output is **tail**-truncated (`bash`, `powershell`) and the full output is spilled to `os.tmpdir()/pi-bash-<16 hex>.log`. Every truncation appends an actionable bracketed notice (`[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]`). VERIFIED.
5. **`read` does not add line numbers** and does not normalise anything: the text is the raw UTF-8 decode of the file, split on `\n` (`CA/src/core/tools/read.ts:132-184`). Images are detected by magic bytes (not extension), resized to ≤2000×2000 px and <4.5 MB base64, and returned as an image block after a text note. There is **no binary-file detection** for non-images. VERIFIED.
6. **`edit` is a multi-edit exact-replace tool** (`{path, edits:[{oldText,newText}]}`): all edits are matched against the *original* file, each `oldText` must be unique, edits must not overlap, nothing is written unless every edit succeeds. BOM is stripped and restored, CRLF is normalised to LF for matching and restored afterwards. If exact matching fails for any edit, the whole operation falls back to a **fuzzy-normalised space** (NFKC, trailing whitespace stripped per line, smart quotes/dashes/special spaces → ASCII) while preserving the bytes of untouched lines (`CA/src/core/tools/edit-diff.ts:34-55, 300-362`). VERIFIED.
7. **`grep` and `find` are not implemented in JavaScript: they shell out to ripgrep (`rg`) and `fd`**, which Pi downloads from GitHub releases into `~/.pi/agent/bin` when they are not on `PATH` (`CA/src/utils/tools-manager.ts:29-69, 349-400`). `ls` is pure Node (`readdir` + `stat`). VERIFIED. This is the part gptr cannot copy (REQ-01/REQ-07/REQ-08) and must re-implement in R.
8. ripgrep flags used by Pi: `--json --line-number --color=never --hidden [--ignore-case] [--fixed-strings] [--glob G] -- <pattern> <path>`; fd flags: `--glob --color=never --hidden [--no-require-git] --max-results N [--full-path] -- <pattern> <path>` (`grep.ts:162-166`, `find.ts:182-214`). Neither result list is sorted; only `ls` sorts (case-insensitive `localeCompare`). VERIFIED.
9. Experimentally verified ripgrep behaviours that matter for a faithful port (ripgrep 15.2.0, §2.13): `.gitignore` is **not** honoured outside a git repository; `--hidden` searches inside `.git/`; a positive `--glob` **overrides** ignore rules; a `--glob` containing `/` is anchored at **rg's process working directory**, not at the search path (Pi spawns rg without a `cwd`, so this is the Pi process cwd); one match event per *line* (not per occurrence); files with a NUL byte in the first read buffer are skipped (a NUL far into a file, e.g. at offset 300,013, still lets rg report the matches before it and then stop); exit code 1 = no match, 2 = error. VERIFIED (re-run by the verifier).
10. **The default system prompt is short** (359 words / ≈2,460 characters with the default four tools, measured on the §3.10 text with the `<PKG_DIR>` placeholder; the real prompt is longer by 3 × the install-path length, e.g. ≈2,610 characters for a `/usr/local/lib/node_modules/...` install): a one-sentence preamble, then XML-tagged sections `<tools>` (one line per active tool that has a `promptSnippet`), `<rules>` (de-duplicated guideline bullets contributed by the active tools), `<docs>`, optional `<addendum>`, `<project_context>`, `<skills>`, and `<cwd>` (`CA/src/core/system-prompt.ts:121-180`). Reproduced verbatim in §3.10. VERIFIED.
11. **Tool selection**: `--tools a,b` (replace), `--exclude-tools`, `--no-builtin-tools`, `--no-tools`; setting `defaultTools` accepts plain names (replace) or `+name`/`-name` modifiers (`CA/docs/cli.md:111-128`, `settings-manager.ts:223-246`). VERIFIED.
12. **Windows**: `bash` uses Git Bash (or any `bash.exe`), legacy WSL `bash.exe` receives the command on stdin; `powershell` prefers `pwsh.exe`, args `-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command`, and prefixes every command with a UTF-8 console-encoding statement; process trees are killed with `taskkill /F /T /PID`; Git-Bash/WSL/Cygwin paths (`/c/Users/..`, `/mnt/c/..`) are rewritten to `C:\...` (`CA/src/utils/shell.ts`, `CA/src/utils/paths.ts:68-74`). VERIFIED (source), UNCERTAIN (runtime).
13. **Recommended gptr tool list**: `read`, `run_r`, `edit`, `write` (the Pi-equivalent core), `grep`, `find`, `ls` (pure R), and an opt-in `shell`. The JSON schemas of `read`/`edit`/`write`/`ls` can be kept **byte-identical** to Pi's (and `grep` structurally identical, with two description strings reworded), so models trained on Pi-style harnesses behave the same. `find` gains one optional `sort` enum (REQ-08); `run_r` replaces `bash` with `{code, timeout?}`.
14. **A complete pure-R prototype of all eight gptr tools was written and run**: 1,535 lines, base R + `jsonlite` only (optional: `stringi` for NFKC, `magick` for image resize/BMP, `processx` for the shell tool, `ragg` for plots). **175 assertions pass** in a C locale, in a UTF-8 locale, and with all optional packages blocked (167 assertions). The test-suite mirrors Pi's own `tools.test.ts`. VERIFIED (§5).
15. **The R grep/find/gitignore implementation was validated against ripgrep as an oracle**: identical file set to `rg --files --hidden` (853 files) and identical matching `file:line` pairs for six patterns on Pi's `packages/coding-agent` directory (not the whole monorepo). VERIFIED (re-run). Speed: whole Pi monorepo (2,125 files, 25.9 MiB = 27.2 MB) grep in 0.4–0.5 s vs 0.04 s for `rg` in the author's single run; a verifier re-run on a heavily loaded machine (load average 67 on 8 cores) measured 1.1–3.5 s vs 0.12–0.38 s, i.e. R is roughly 4–30× slower than rg. Absolute timings UNCERTAIN; "adequate for an agent loop" is LIKELY for trees of this size.
16. **R-specific traps discovered by experiment** (all affect CRAN robustness): (a) the original claim "`\u00e9` string literals are not reliably marked UTF-8" was **CORRECTED by the verifier**: it is false for `\u` escapes. An escaped literal in ASCII source is marked `UTF-8` (and `nchar()` = 4 for "café") in every combination re-tested with R 4.4.3: plain script, and installed package; C or UTF-8 locale at install time; C or UTF-8 locale at load time. What is *not* reliably marked is a literal written with **raw non-ASCII bytes** in the source (the original probes `probe1.R`/`probe2.R` and the test package actually contained raw UTF-8 bytes, not escapes): its mark depends on the locale at install and load time. Keep R sources ASCII and build non-ASCII constants with `\u` escapes (CRAN's recommended form) or `intToUtf8()`; (b) in a non-UTF-8 locale, UTF-8-*marked* non-ASCII paths make `file.exists()`/`basename()` fail with "unable to translate … to native encoding"; (c) `jsonlite::base64_enc()` (2.0.0) wraps its output with a `\n` every **72** characters (corrected by the verifier from 76); (d) `setTimeLimit()` cannot interrupt a single `Sys.sleep()`, a LAPACK call, or `system2()` — in-session timeouts are *soft*; (e) `system2(timeout = 0.5)` is ignored (fractional seconds < 1); (f) `ragg::agg_png()` writes a blank file even if nothing is drawn. VERIFIED (§2.14).
17. Deliberate gptr deviations from Pi, each justified in §4: deterministic sorting of `grep`/`find` results; `.git/` always skipped; `.gitignore` honoured everywhere (not only inside git repos); binary files are reported instead of being decoded as garbage; CP1252/latin1/UTF-16 files round-trip through `edit` instead of being corrupted; `run_r` output is truncated head+tail (R prints headers at the top and errors at the bottom); overlapping grep context blocks are merged.

---

## 2. Findings

### 2.1 Tool inventory, activation and selection

| Tool | Default | Implementation | Strict JSON-schema sampling | Source |
|---|---|---|---|---|
| `read` | **on** | Node `fs` + Photon (WASM) for images | `prefer` | `CA/src/core/tools/read.ts` |
| `bash` | **on** | `child_process.spawn(shell, ["-c", cmd])` | `prefer` | `CA/src/core/tools/bash.ts` |
| `edit` | **on** | Node `fs` + `diff` npm package (8.0.4) | `prefer` | `CA/src/core/tools/edit.ts`, `edit-diff.ts` |
| `write` | **on** | Node `fs` | `prefer` | `CA/src/core/tools/write.ts` |
| `grep` | opt-in | **spawns ripgrep** | none | `CA/src/core/tools/grep.ts` |
| `find` | opt-in | **spawns fd** | none | `CA/src/core/tools/find.ts` |
| `ls` | opt-in | Node `readdir`/`stat` | none | `CA/src/core/tools/ls.ts` |
| `powershell` | opt-in, Windows only | spawn `pwsh.exe`/`powershell.exe` | `prefer` | `CA/src/core/tools/powershell.ts` |
| `codemode` | opt-in (built-in extension) | QuickJS sandbox calling other tools | – | `CA/src/extensions/codemode/tool.ts` |
| `tool_search` | opt-in (built-in extension) | BM25 over undeclared tools | – | `CA/src/extensions/tool-search/tool.ts` |

Evidence (VERIFIED):

* `export type ToolName = "read" | "bash" | "powershell" | "edit" | "write" | "grep" | "find" | "ls"` — `CA/src/core/tools/index.ts:95`.
* `createCodingToolDefinitions()` returns read, bash, edit, write (`index.ts:164-171`); `createReadOnlyToolDefinitions()` returns read, grep, find, ls (`index.ts:173-180`).
* `export const DEFAULT_TOOL_NAMES: readonly string[] = ["read", "bash", "edit", "write"];` — `CA/src/core/settings-manager.ts:213`.
* Strictness: `CA/test/builtin-tool-strict-mode.test.ts:13-28` asserts `constrainedSampling` equals `{type:"json_schema", strict:"prefer"}` for `read, bash, powershell, edit, write` and is `undefined` for `grep, find, ls`.
* All eight built-ins are always *registered*; only the selection is *active* (declared to the model) — `CA/test/default-tools-setting.test.ts:58-71`.

Selection mechanics (VERIFIED, `CA/docs/cli.md:111-128`, `CA/docs/settings.md:36-56`, `CA/src/cli/args.ts:143-157`, `CA/src/core/sdk.ts:264-270`, `settings-manager.ts:215-246`):

| Mechanism | Semantics |
|---|---|
| `-t`, `--tools <list>` | comma-separated allowlist; **replaces** the whole selection (built-in, extension and custom tools); naming an inactive tool activates it; does not accept `+`/`-` |
| `-xt`, `--exclude-tools <list>` | denylist applied after everything else |
| `-nbt`, `--no-builtin-tools` | disables the default built-ins, keeps extension/custom tools |
| `-nt`, `--no-tools` | starts with nothing enabled |
| setting `defaultTools: string[]` | plain names replace `DEFAULT_TOOL_NAMES`; a list consisting only of `+name`/`-name` entries modifies the inherited selection, processed in order; `[]` disables all built-ins |
| SDK `CreateAgentSessionOptions` | `tools?: string[]`, `excludeTools?: string[]`, `noTools?: "all" \| "builtin"`, `customTools?: ToolDefinition[]` |

Precedence: `options.tools ?? (options.noTools ? [] : (settings.defaultTools ?? DEFAULT_TOOL_NAMES))`, then `excludeTools` filtered out (`sdk.ts:264-270`).

Tool exposure classes for extension tools (`CA/src/core/extensions/types.ts:494-509`): `direct` (declared + callable), `model-only`, `codemode` (callable from scripts, not declared), `deferred` (found only by `tool_search`), `hidden`.

### 2.2 Common machinery

**Tool definition object** (`CA/src/core/extensions/types.ts:558-631`), fields that matter for a port:

```ts
interface ToolDefinition {
  name: string;               // used in LLM tool calls
  label: string;              // UI
  description: string;        // sent to the model
  promptSnippet?: string;     // one line for the <tools> section of the system prompt
  promptGuidelines?: string[];// bullets for the <rules> section while the tool is active
  parameters: TSchema;        // TypeBox => plain JSON Schema
  constrainedSampling?: false | { type: "json_schema", strict: "prefer" | "require" } | { type: "grammar", ... };
  prepareArguments?: (args: unknown) => Params;   // compatibility shim BEFORE validation
  outputSchema?: TSchema;     // schema of structuredContent (programmatic callers only)
  exposure?, namespace?, annotations?, defaultActive?, prepareLoadout?;
  executionMode?: "sequential" | "parallel";
  execute(toolCallId, params, signal, onUpdate, ctx): Promise<AgentToolResult>;
  renderCall?, renderResult?;  // TUI only
}
```

**Result object** (`AG/src/types.ts:424-446`):

```ts
interface AgentToolResult<T> {
  content: (TextContent | ImageContent)[];  // model-facing
  details: T;                                // UI / logs only
  structuredContent?: JsonValue;             // programmatic callers (codemode); NOT sent to the model
  usage?: Usage;
  isError?: boolean;                         // report failure without throwing
  terminate?: boolean;                       // stop the agent after this tool batch (only if ALL results set it)
}
// TextContent  = { type: "text",  text: string }
// ImageContent = { type: "image", data: string /* base64 */, mimeType: string }
```

**What the model receives** (Anthropic wire format; `AI/src/api/anthropic-messages.ts:128-160, 1220-1227`, VERIFIED):

```json
{ "type": "tool_result", "tool_use_id": "<toolCallId>", "content": "<all text blocks joined by \n>", "is_error": false }
```

If any image block is present, `content` becomes an array of `{"type":"text","text":...}` and
`{"type":"image","source":{"type":"base64","media_type":"image/png","data":"..."}}` blocks.

**Agent-loop pipeline per tool call** (`AG/src/agent-loop.ts:707-776, 820-851`, VERIFIED):

1. find the tool by name — else error result `Tool ${toolCall.name} not found`;
2. `tool.prepareArguments(args)` if defined;
3. `validateToolArguments(tool, call)`: drops `null` for optional properties (`normalizeOptionalNulls`), converts primitives with TypeBox `Value.Convert` (LIKELY `"5"`→5, `"true"`→true; for plain-JSON-schema tools the explicit `coercePrimitiveByType` does string→number/boolean, number/boolean→string, VERIFIED `validation.ts:59-131`), validates against the schema; on failure throws
   `Validation failed for tool "<name>":\n  - <path>: <message>\n\nReceived arguments:\n<JSON pretty-printed with 2 spaces>` (`AI/src/utils/validation.ts:317-350`);
4. `beforeToolCall` hook (can block: error text = `reason` or `Tool execution was blocked`);
5. `execute()`; a thrown error becomes `{content:[{type:"text",text: error.message}], details:{}}` with `isError: true`;
6. `afterToolCall` hook may replace content/details/isError;
7. abort at any stage → `Operation aborted`.

If the assistant message was cut off by the output-token limit, *no* tool call of that message is executed; each gets the error
`Tool call "<name>" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments.` (`agent-loop.ts:478-503`).

**Execution mode**: default `"parallel"` — calls are prepared sequentially, executed concurrently, results emitted in assistant source order (`AG/src/agent.ts:253`, `AG/src/types.ts:305-317`). Because of that, `edit` and `write` serialise per file through `withFileMutationQueue(realpath(file))` (`CA/src/core/tools/file-mutation-queue.ts:32-61`).

**Strict schemas are a provider-side conversion**, not a change of the execution schema: `makeStrictJsonSchema()` clones the schema, makes every property required, turns optional ones into `anyOf:[T,{type:"null"}]`, sets `additionalProperties:false` (`AI/src/api/constrained-sampling.ts:53-127`). That is why step 3 above strips `null`s.

**Truncation** (`CA/src/core/tools/truncate.ts`, VERIFIED):

* line counting: `""` = 0 lines; a single trailing `\n` does not add a line (`splitLinesForCounting`, lines 47-56);
* `truncateHead(content, {maxLines=2000, maxBytes=51200})`: keeps whole lines from the start while `lines ≤ maxLines` and `bytes (incl. 1 per newline) ≤ maxBytes`; never a partial line; if the *first* line alone exceeds `maxBytes` → `content: ""`, `firstLineExceedsLimit: true` (lines 78-160);
* `truncateTail(...)`: same from the end; if the *last* line alone exceeds `maxBytes`, keeps the last `maxBytes` bytes of it cut on a UTF-8 character boundary and sets `lastLinePartial: true` (lines 168-262);
* `truncateLine(line, 500)`: `line.slice(0,500) + "... [truncated]"` (lines 268-276; JS `length` = UTF-16 code units);
* `truncateMiddle(content, maxBytes)`: head half + `…N chars truncated…` + tail half — used by the MCP extension's tools (`CA/src/extensions/mcp/tools.ts:125`, `MCP_OUTPUT_MAX_BYTES = 20 * 1024`), not by the eight tools and not by codemode (codemode has its own head/tail token truncation in `extensions/codemode/execute.ts:174-187`) (lines 292-314; corrected by the verifier);
* `formatSize(bytes)`: `<1024` → `"512B"`; `<1 MiB` → `"50.0KB"` (one decimal); else `"3.0MB"` (lines 61-69).

`TruncationResult` (goes into `details.truncation`): `content, truncated, truncatedBy: "lines"|"bytes"|null, totalLines, totalBytes, outputLines, outputBytes, lastLinePartial, firstLineExceedsLimit, maxLines, maxBytes`.

**Path resolution** (`CA/src/core/tools/path-utils.ts`, `CA/src/utils/paths.ts:68-107`, tests `CA/test/path-utils.test.ts`, VERIFIED). For every path argument:

1. replace Unicode spaces `[\u00A0\u2000-\u200A\u202F\u205F\u3000]` by a normal space;
2. strip one leading `@` (models copy the `@file` mention syntax);
3. on Windows only: rewrite `/c/x`, `/mnt/c/x`, `/cygdrive/c/x` to `C:\x` (not if the path starts with `//` or contains `\`);
4. `~` → home; `~/x` (and `~\x` on Windows) → `home/x`; **`~draft.md` stays literal** (no `~user` expansion);
5. `file://` URLs → `fileURLToPath`;
6. absolute → `path.resolve(p)`; relative → `path.resolve(cwd, p)` (lexical `.`/`..` normalisation, no symlink resolution). `cwd` is `ctx.cwd || cwd` — the session's cwd at call time.
7. **`read` only**: if the resolved path does not exist, try in order (a) space before `AM.`/`PM.` (case-insensitive) → U+202F narrow no-break space (macOS screenshot names), (b) NFD form, (c) `'` → U+2019, (d) NFD + U+2019; first existing variant wins, else the original path is used (and the read fails).

There is **no sandboxing**: absolute paths and `..` may leave the cwd (`CA/docs/how-pi-works.md:47-49`: "Enabled tools use the operating-system permissions of the Pi process").

### 2.3 `read`

Source `CA/src/core/tools/read.ts` (VERIFIED):

* arguments `path` (required), `offset` (1-indexed line), `limit` (max lines) — lines 14-18;
* access check `fs.access(path, R_OK)`; a missing file rejects with Node's message (test accepts `/ENOENT|not found/i`, `tools.test.ts:94-98`);
* **image branch** (lines 112-131): MIME is sniffed from the first 4100 bytes (`CA/src/utils/mime.ts:3-23`): JPEG `FF D8 FF` (but not `FF D8 FF F7`, JPEG-LS), PNG signature + valid `IHDR` and **not animated** (an `acTL` chunk before `IDAT` rejects it), `GIF87a`/`GIF89a`, `RIFF....WEBP`, `BM` with a plausible DIB header. A `.png` file containing text is read as text; a `.txt` file containing a PNG is read as an image (`tools.test.ts:200-249`).
  * BMP (or any non png/jpeg/gif/webp type) is converted to PNG (`CA/src/utils/image-process.ts:49-65`), hint `[Image converted from image/bmp to image/png.]`.
  * auto-resize (default on; `CA/src/utils/image-resize-core.ts:22-29, 59-164`): limits 2000×2000 px and 4.5 MB of base64; if within limits the original bytes are sent unchanged; otherwise scale to fit, encode PNG and JPEG (qualities 80, 85, 70, 55, 40), first candidate under the limit wins, else shrink both dimensions ×0.75 and retry down to 1×1; EXIF orientation is applied. Hint after a resize: `[Image: original WxH, displayed at wxh. Multiply coordinates by S.SS to map to original image.]` (`image-resize.ts:116-123`).
  * result: `[{type:"text", text:"Read image file [image/png]\n<hints>"}, {type:"image", data:<base64>, mimeType}]`; failure texts `[Image omitted: could not be converted to a supported inline image format.]` / `[Image omitted: could not be resized below the inline image size limit.]`; for non-vision models the note `[Current model does not support images. The image will be omitted from this request.]` is appended (lines 59-64).
* **text branch** (lines 132-184): `buffer.toString("utf-8")` (invalid bytes become U+FFFD; BOM and `\r` are kept), `split("\n")` (so a file ending in `\n` has a final empty "line" and `totalFileLines` counts it), `startLine = offset ? max(0, offset-1) : 0`; `startLine >= lines` → error `Offset ${offset} is beyond end of file (${n} lines total)`; user `limit` is applied first, then `truncateHead`.
* **no line numbers, no `cat -n` formatting** — the output is the file text verbatim.
* `details` is `undefined` unless truncated (`{truncation}`).

### 2.4 `write`

Source `CA/src/core/tools/write.ts` (VERIFIED): `mkdir(dirname, {recursive:true})`, `writeFile(path, content, "utf-8")` (overwrite, no backup, no atomic rename, no newline handling), serialised by the file mutation queue, abort checked between steps. Result text `Successfully wrote to ${path}` where `path` is the string the model passed (not the resolved absolute path); `details: undefined`.

### 2.5 `edit` — the exact algorithm

Sources `CA/src/core/tools/edit.ts`, `CA/src/core/tools/edit-diff.ts`; tests `CA/test/tools.test.ts:273-483, 1100-1419`, `CA/test/edit-tool-legacy-input.test.ts` (all VERIFIED by reading; re-verified by porting and running the same cases in R, §5).

**Step 0 — argument shim `prepareEditArguments`** (`edit.ts:103-134`), runs before validation:
* `edits` given as a JSON *string* (comment in source: "Some models (Opus 4.6, GLM-5.1) send edits as a JSON string instead of an array") → `JSON.parse`; an array is used as is, a single `{oldText,newText}` object is wrapped; unparsable strings are left alone (validation then fails);
* `edits` given as a single object instead of an array → wrapped in an array;
* legacy top-level `oldText`/`newText` (both strings) → appended to `edits` and removed from the top level.

**Step 1 — validation**: `edits` must be a non-empty array, else `Edit tool input is invalid. edits must contain at least one replacement.`

**Step 2 — file access** `fs.access(R_OK | W_OK)`; failure → `Could not edit file: ${path}. Error code: ${code}.` (`ENOENT`, `EACCES`, …); errors without a code → `Could not edit file: ${path}. Error: <message>.`

**Step 3 — read and normalise**: decode UTF-8; split a leading BOM (`\uFEFF`) off; `detectLineEnding` = CRLF iff the first `\r\n` occurs before the first bare `\n` (i.e. the first line ending is CRLF), else LF; `normalizeToLF`: `\r\n`→`\n`, then remaining `\r`→`\n`.

**Step 4 — `applyEditsToNormalizedContent(normalizedContent, edits, path)`** (`edit-diff.ts:300-362`):

1. each edit's `oldText`/`newText` is LF-normalised; an empty `oldText` → `oldText must not be empty in ${path}.` (multi-edit: `edits[${i}].oldText must not be empty in ${path}.`);
2. `fuzzyFindText(content, oldText)` for every edit: `content.indexOf(oldText)`; if not found, `indexOf` in `normalizeForFuzzyMatch(content)` of `normalizeForFuzzyMatch(oldText)`;
3. **if any edit needed the fuzzy path, the base for *all* edits becomes the fuzzy-normalised content**; otherwise the base is the LF-normalised content;
4. each edit is located again in the base (exact first, fuzzy second) → `matchIndex`, `matchLength`; not found → error (texts in §3.4);
5. **uniqueness**: `countOccurrences` always counts in fuzzy-normalised space (`normalize(base).split(normalize(oldText)).length - 1`, non-overlapping); `> 1` → duplicate error. Consequence: `"hello world   \nhello world\n"` with `oldText = "hello world"` is rejected with `Found 2 occurrences` although only one occurrence matches exactly (`tools.test.ts:1247-1258`);
6. matches are sorted by `matchIndex`; if `prev.matchIndex + prev.matchLength > cur.matchIndex` → `edits[i] and edits[j] overlap in ${path}. Merge them into one edit or target disjoint regions.` (indices are the *original* positions in `edits`);
7. replacements are applied back-to-front on the base. In fuzzy mode `applyReplacementsPreservingUnchangedLines` is used instead: each replacement is widened to the lines it touches, overlapping line ranges are grouped, only those lines are rewritten from the normalised base, **every other line is copied byte-for-byte from the original** (so untouched lines keep their trailing whitespace / smart quotes); requires equal line counts of original and base, else `Cannot preserve unchanged lines because the base content has a different line count.`;
8. if the result equals the original → `No changes made to ${path}. ...` error.

`normalizeForFuzzyMatch(text)` (`edit-diff.ts:34-55`), in this order:

| Step | Transformation |
|---|---|
| 1 | `text.normalize("NFKC")` (full-width forms → ASCII, `e`+U+0301 → `é`, ligatures, …) |
| 2 | per line: `trimEnd()` (JS whitespace set) |
| 3 | `[\u2018\u2019\u201A\u201B]` → `'` |
| 4 | `[\u201C\u201D\u201E\u201F]` → `"` |
| 5 | `[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]` → `-` |
| 6 | `[\u00A0\u2002-\u200A\u202F\u205F\u3000]` → space |

Note: `newText` is never *fuzzy*-normalised; like `oldText` it is LF-normalised (`normalizeToLF`, `edit-diff.ts:305-308`) and then converted to the file's line ending on write.

**Step 5 — write back**: `bom + restoreLineEndings(newContent, originalEnding)`; with CRLF *every* `\n` becomes `\r\n`, so a file with mixed endings whose first line ending is CRLF is normalised to CRLF; a CR-only file is rewritten with LF (LIKELY, from the code; not covered by Pi's tests).

**Step 6 — result**: text `Successfully replaced ${edits.length} block(s) in ${path}.`; `details = {diff, patch, firstChangedLine}`:

* `diff` — display format from `generateDiffString(old, new, contextLines = 4)` (`edit-diff.ts:376-499`), built on `Diff.diffLines`: every line is `<sign><line number padded to the width of the largest line number> <text>`; sign `+` uses the new file's line number, `-` and ` ` (context) use the old file's; at most 4 context lines before and after each change; skipped runs are one line ` <padding> ...`; context between two changes is shown in full if it has ≤ 8 lines. Example (VERIFIED with the R port):

  ```
   96 line 000096 some text here
  ...
  -   100 line 000100 some text here
  +   100 LINE 000100 some text here
      101 line 000101 some text here
  ```
* `patch` — `Diff.createTwoFilesPatch(path, path, old, new, undefined, undefined, {context: 4, headerOptions: Diff.FILE_HEADERS_ONLY})` (`edit-diff.ts:365-370`): `--- path`, `+++ path`, `@@ -a,b +c,d @@` hunks, `\ No newline at end of file` markers; no `Index:` / `====` lines (jsdiff `src/patch/create.ts`, fetched 2026-09-29).
* `firstChangedLine` — line number in the new file of the first change.

Both are computed on the LF-normalised, BOM-less contents. A preview variant `computeEditsDiff()` runs the same algorithm without writing (used by the TUI before execution).

**Atomicity**: all matching and the no-change check happen before the single `writeFile`; if any edit fails the file is untouched (`tools.test.ts:417-433`).

### 2.6 `bash` and `powershell`

Source `CA/src/core/tools/bash.ts` (shared implementation `createShellToolDefinition`), `powershell.ts`, `CA/src/utils/shell.ts`, `CA/src/utils/child-process.ts`, `output-accumulator.ts` (VERIFIED):

* arguments `command` (required), `timeout` seconds (optional, **no default timeout**; must be finite and > 0 else `Invalid timeout: must be a finite number of seconds`; max 2,147,483.647 s else `Invalid timeout: maximum is 2147483.647 seconds`);
* optional `commandPrefix` setting is prepended as `${prefix}\n${command}`;
* spawn: `spawn(shell, [...args, command], {cwd, detached: platform !== "win32", env, stdio: ["ignore","pipe","pipe"], windowsHide: true})`; stdin is closed; stdout and stderr are merged in arrival order;
* shell resolution (`shell.ts:67-120`): `shellPath` setting → (Windows) `%ProgramFiles%\Git\bin\bash.exe`, `%ProgramFiles(x86)%\Git\bin\bash.exe`, then `bash.exe` via `where` → (Unix) `/bin/bash`, `bash` via `which`, fallback `sh`; args `["-c"]`; a legacy WSL launcher `C:\Windows\System32\bash.exe` gets `["-s"]` and the command on **stdin**;
* environment: `process.env` with Pi's managed bin dir prepended to `PATH`, plus `PI_SESSION_ID`, `PI_SESSION_FILE`, `PI_PROVIDER`, `PI_MODEL`, `PI_REASONING_LEVEL` (`bash.ts:189-215`; guideline "You can inspect PI_* environment variables…" is only added when this is enabled);
* working directory must exist: `Working directory does not exist: ${cwd}\nCannot execute bash commands.`;
* timeout/abort kill the whole process tree: Unix `process.kill(-pid, "SIGKILL")`, Windows `%SystemRoot%\System32\taskkill.exe /F /T /PID <pid>` (`shell.ts:187-218`);
* after the child exits, reading continues until the pipes are idle for 100 ms (detached grandchildren keeping the pipe open must not hang the tool, `child-process.ts:16, 49-137`);
* exit code: `null` + signal → `128 + signal number` (SIGKILL → 137, SIGTERM → 143);
* **output handling** (`OutputAccumulator`): streaming UTF-8 decode (multi-byte characters split across chunks are handled), rolling in-memory tail of ≤ 100–200 KB, a temp file `os.tmpdir()/pi-bash-<16 hex>.log` (`pi-powershell-…` for PowerShell) is opened as soon as total bytes > 50 KB or lines > 2000 and receives the *raw* bytes of the complete output; temp files are never deleted by Pi;
* the model-facing text is **not** ANSI-stripped or sanitised (only the TUI renderer and the user `!cmd` path `executeBashWithOperations` strip ANSI codes and control characters, `CA/src/core/bash-executor.ts:82`);
* UI streaming updates are throttled to one per 100 ms (`BASH_UPDATE_THROTTLE_MS`, `CA/src/core/tools/renderers/bash.ts:19`);
* result text: output or `(no output)`; truncation notices see §3.5; **non-zero exit is returned (not thrown) as `isError: true`** with `\n\nCommand exited with code N` appended; timeout/abort throw with the partial output followed by `Command timed out after N seconds` / `Command aborted`;
* `structuredContent` for programmatic callers: `{output (≤ 1 MiB, head 512 KiB + "\n\n[... N bytes omitted ...]\n\n" + tail 512 KiB), truncated, full_output_path?, exit_code, wall_time_seconds}`.

PowerShell differences (`powershell.ts`): name `powershell`, shell name in the description `PowerShell`, executable `pwsh.exe` else `powershell.exe` (found with `where`), args `-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command`, every command prefixed with
`try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}\n`; on non-Windows it throws `The powershell tool is only available on Windows.`

### 2.7 `grep`

Source `CA/src/core/tools/grep.ts` (VERIFIED):

* requires ripgrep: `ensureTool("rg")` = managed copy in `~/.pi/agent/bin`, else `rg` on `PATH`, else download of the latest GitHub release (`BurntSushi/ripgrep`; disabled by `PI_OFFLINE=1`; on Android/Termux a hint to `pkg install ripgrep`). Failure → `ripgrep (rg) is not available and could not be downloaded`;
* argument vector: `["--json", "--line-number", "--color=never", "--hidden"]`, `+ "--ignore-case"` if `ignoreCase`, `+ "--fixed-strings"` if `literal`, `+ "--glob", glob` if `glob`, then `"--", pattern, searchPath` (lines 162-166). The `--` makes flag-like patterns (`--pre=…`) plain text (security test `tools.test.ts:903-918`);
* `path` may be a file or a directory; missing → `Path not found: ${absolutePath}`;
* `limit`: `max(1, limit ?? 100)` **matching lines** (rg emits one `match` event per line); when reached, rg is killed and the notice is added;
* `context` (default 0): Pi reads the file itself (LF-normalised, cached per file) and prints lines `n-context … n+context` per match; **overlapping blocks of neighbouring matches are printed repeatedly**, there is no `--` separator;
* line format: match `relative/path:LINE: text`, context `relative/path-LINE- text`; path is relative to the search directory with `/` separators, or the basename when a single file was searched;
* lines longer than 500 characters are cut and suffixed `... [truncated]`;
* whole output head-truncated at 50 KB (no line limit);
* no matches → text `No matches found`; rg exit codes other than 0/1 → error with rg's stderr (e.g. `regex parse error: …`);
* **order** = rg's output order: multi-threaded directory traversal, not sorted, not deterministic across files (rg GUIDE: `--sort path` is needed to force sorting); lines within a file are ascending;
* default ignore behaviour = ripgrep's with `--hidden`: see §2.13.

### 2.8 `find`

Source `CA/src/core/tools/find.ts`; regression tests `CA/test/suite/regressions/3302-…`, `3303-…`, `6104-…` (VERIFIED for the code; fd semantics from fd's README, man page, `src/main.rs` and CHANGELOG fetched 2026-09-29 because `fd` is not installed here):

* requires `fd` (`ensureTool("fd")`, also tries `fdfind`; pinned `10.3.0` on darwin/x64, otherwise latest release); failure → `fd is not available and could not be downloaded`;
* argument vector: `["--glob", "--color=never", "--hidden"]`; `+ "--no-require-git"` when no ancestor of the search path contains `.git` (so `.gitignore` files are honoured outside repositories, and nested repositories keep fd's default boundaries — issue #5960); `+ "--max-results", limit`; if the pattern contains `/`: `+ "--full-path"` and the pattern is prefixed with `**/` unless it starts with `/` or `**/` or is `**` (fd then matches against the absolute path — issue #3302); on Windows every `/` of such a pattern is replaced by `[/\\]`; finally `"--", pattern, searchPath`;
* fd semantics relevant to results: glob built with `GlobBuilder::new(pattern).literal_separator(true)` (`*` never matches `/`, `**` does); **smart case** — case-insensitive unless the pattern contains an uppercase character; matches **files and directories**; directories are printed with a trailing separator (fd ≥ 8.4.0); since fd 10.0.0 `.git/` is *not* skipped automatically with `--hidden`; "The order in which different search results are processed and their output is printed is not guaranteed";
* output: paths relative to the search directory, `/` separators, trailing `/` for directories (`relativizeFindResultPath`, lines 14-24); head-truncated at 50 KB; `limit` default 1000; `resultLimitReached = results >= limit`;
* no results → text `No files found matching pattern`; fd failure without output → error with fd's stderr;
* an SDK embedding may replace fd by a custom `glob(pattern, cwd, {ignore: ["**/node_modules/**", "**/.git/**"], limit})` (lines 116-169) — the only place where Pi has a hard-coded ignore list.

### 2.9 `ls`

Source `CA/src/core/tools/ls.ts` (VERIFIED): `readdir(path)` (includes dotfiles, excludes `.`/`..`); sort `a.toLowerCase().localeCompare(b.toLowerCase())` (ICU collation of the process locale); first `limit` (default 500) entries; each entry is `stat`-ed (follows symlinks) and gets a `/` suffix if it is a directory; entries that cannot be `stat`-ed (broken symlinks) are silently skipped; not recursive; no sizes/dates. Texts: `(empty directory)`; errors `Path not found: ${abs}`, `Not a directory: ${abs}`, `Cannot read directory: ${message}`.

### 2.10 `codemode` and `tool_search` (built-in extensions, inactive by default)

* `codemode` — parameter `{code: string}` ("Raw JavaScript source. Top-level await and return work. May start with a `// @options: {"max_output_tokens": 1000}` line."); runs the script in a QuickJS sandbox (256 MB, no fs/network/timers) where every other tool is `await tools.<name>({...})`; helpers `text()`, `image()`, `store()/load()`, `ALL_TOOLS`, `searchTools()`, `describeTool()`, and `models.classify(model, context)` for classifier models such as TypeSafe's Jev with question types `choice` / `score` / `bool` (`CA/src/extensions/codemode/tool.ts:85-196`, `CA/docs/cli.md:164-178`). Output budget 10,000 tokens by default. **Relevance for gptr**: `run_r` *is* gptr's codemode — R code that can call the other tools as functions and System-1 models inline (REQ-20, REQ-35).
* `tool_search` — parameters `{query: string, limit?: number = 8}`; BM25 over tools that are registered but not declared (MCP tools with `deferred`/`codemode` exposure) and activates the matches for the next model call (`CA/src/extensions/tool-search/tool.ts:158-163, 225-250`). Relevant to the MCP track (REQ-30), not to the core tool layer.

### 2.11 System prompt assembly

Source `CA/src/core/system-prompt.ts`, `CA/src/core/agent-session.ts:1601-1648, 3430-3470`, `AI/src/utils/text.ts:15-21`; tests `CA/test/system-prompt.test.ts`, `CA/test/tool-system-prompt-contributions.test.ts` (VERIFIED):

* every tool contributes a `promptSnippet` (normalised to one line) and `promptGuidelines` (trimmed, de-duplicated);
* `buildSystemPromptSections()` creates an ordered map of sections; `preamble` is untagged, every other section is wrapped as `<name>\n…\n</name>`; the prompt text is the sections joined by a blank line;
* order: `preamble`, `tools`, `rules`, `docs`, `addendum` (from `.pi/APPEND_SYSTEM.md`, `~/.pi/agent/APPEND_SYSTEM.md` or `--append-system-prompt`; `CA/src/core/resource-loader.ts:1216-1221`), `project_context` (per directory the first existing of `AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`, `CLAUDE.MD`; `resource-loader.ts:184`; project-level `.pi/SYSTEM.md` / `.pi/APPEND_SYSTEM.md` are used only when the project is trusted, `resource-loader.ts:1200-1222`), `skills`, `cwd`, then custom sections from extensions (names must match `^[a-z][a-z0-9_-]*$`);
* `<tools>` lists only *active* tools that have a snippet: `- name: snippet`; `(none)` if empty; always followed by the sentence `In addition to the tools above, you may have access to other custom tools depending on the project.`;
* `<rules>` = (1) a shell hint only if bash/powershell is active and none of grep/find/ls is: `Use bash for file operations like ls, rg, find` / `Use PowerShell for file operations like listing, searching, and finding files` / `Use bash or PowerShell for file operations like listing, searching, and finding files`; (2) the guidelines of each active tool in selection order; (3) extra guidelines; (4) always `Be concise in your responses` and `Show file paths clearly when working with files`;
* with a **custom prompt** (`.pi/SYSTEM.md`, `~/.pi/agent/SYSTEM.md` or `--system-prompt`; `resource-loader.ts:1202-1207`) the `tools`, `rules` and `docs` sections are dropped entirely; addendum, project context, skills and cwd are still appended;
* `<skills>` is only added if `read` or `bash` is active (the model needs a way to load `SKILL.md`), with the sentence `Use the read tool to load a skill's file…` or `Use bash to load a skill's file…`;
* `<cwd>` holds the working directory with `\` replaced by `/`;
* there is no date/time, OS, or git-status information in the default prompt;
* sections are individually diffable: when tools change mid-session only the changed sections are re-sent as an update message (`diffSystemPromptSections`, lines 204-216).

### 2.12 The second implementation in `packages/agent`

`AG/src/harness/tools/` contains a newer, environment-abstracted copy of **only four tools** (`bash`, `read`, `edit`, `write`; `index.ts:1-23`) with identical schemas and descriptions for `read`/`edit`/`write`; `bash` differs slightly (harness: `command` "Bash command to execute", description "Returns combined stdout and stderr"; coding-agent: "Shell command to execute", "Returns stdout and stderr"). Differences (VERIFIED): `edit-diff.ts` is identical to the coding-agent version minus the preview helpers (diffed); harness `bash` **throws** on non-zero exit (`AG/src/harness/tools/bash.ts:137-141`) whereas the coding-agent version returns an `isError` result with `structuredContent`; harness `read` without an `imageProcessor` sends images unresized and omits BMP (`read.ts:82-99`). This confirms that read/bash/edit/write is the irreducible core in Pi's own view.

### 2.13 Experiments with ripgrep (oracle for the R port)

Executed on this machine with ripgrep 15.2.0 (`/opt/homebrew/bin/rg`) using exactly Pi's flags on a synthetic tree (files `kept.txt`, `ignored.txt` listed in `.gitignore`, `.hiddendir/h.txt`, `sub/s.txt`, `node_modules/pkg/index.js`, `bin.dat` containing a NUL byte, `crlf.txt`, `.git/config`). VERIFIED observations:

| Command (abridged) | Observation |
|---|---|
| `rg --json --line-number --color=never --hidden -- needle DIR` with `DIR/.git` present | `ignored.txt` skipped; `.git/config` **is searched**; `.hiddendir` and `node_modules` searched; `bin.dat` skipped; output order `node_modules/…, .git/config, .hiddendir/…, crlf.txt, kept.txt, sub/s.txt` (unsorted) |
| same, after moving `.git` away (not a repository) | `ignored.txt` **is returned** → `.gitignore` is not honoured outside git repositories (Pi's `grep` does not pass `--no-require-git`; its `find` does) |
| `… --glob '*.txt' -- needle DIR` (repository) | `ignored.txt` is returned → a positive glob overrides ignore rules (rg docs: "This always overrides any other ignore logic") |
| `… --glob 'sub/**' …` | only `sub/s.txt` **when rg's working directory is `DIR`**. Verifier re-run: a glob containing `/` is anchored at rg's *process* cwd, not at the search path — with cwd = parent of `DIR` (relative or absolute `DIR`) or cwd = `/`, `--glob 'sub/**'` matches nothing, while `--glob 'rgt/sub/**'` or `'**/sub/**'` matches. Pi spawns rg without a `cwd` option (`grep.ts:168`), so a model passing `path: "src", glob: "sub/**"` gets no matches unless the Pi process runs inside `src` |
| file with `needle needle needle` on one line | one `match` event with three `submatches` → Pi's limit counts lines |
| CRLF file | `lines.text` = `"café needle utf8\r\n"`; Pi strips `\r` and the final `\n` |
| explicit path to an ignored file / a binary file | both are searched when named explicitly |
| (verifier) NUL byte late in a file (offset 300,013), directory search | the match before the NUL **is** reported, then `WARNING: stopped searching binary file after match`; "binary files are skipped" holds only when the NUL is in rg's first read buffer |
| no match / invalid regex `a(` | exit code 1 / exit code 2 with stderr `rg: regex parse error: … error: unclosed group` |

### 2.14 R platform findings that shape the design

All VERIFIED by running scripts with `/usr/local/bin/Rscript --vanilla` (R 4.4.3, aarch64-apple-darwin20). Note that this harness environment has `LANG` unset, i.e. **`Rscript --vanilla` runs in the `C` locale** (`l10n_info()$"UTF-8"` is `FALSE`), which turned out to be an excellent stress test.

| # | Experiment | Observed | Consequence for gptr |
|---|---|---|---|
| E1 | `Encoding("caf\u00e9")` (ASCII `\u` escape) in an `Rscript --vanilla` script, C locale | **CORRECTED**: `"UTF-8"`, `nchar()` = 4 (verifier re-run). The original observation (`"unknown"`, `nchar()` = 5) came from a probe that contained the raw UTF-8 bytes of "café", not the escape | `\u` escapes are safe; raw non-ASCII bytes in source are not (keep sources ASCII) |
| E2 | literal inside an *installed package* | **CORRECTED**: with a `\u` escape the value is `UTF-8`, `nchar` 4 for every install-locale x load-locale combination (C / UTF-8). With **raw UTF-8 bytes** in the source (+ `Encoding: UTF-8` in DESCRIPTION): installed under `LC_ALL=C` -> `unknown`, `nchar` 9 in C locale, 6 in UTF-8 locale (with a translation warning); installed under UTF-8 and loaded under C: `UTF-8` (verifier re-run) | build non-ASCII constants with `\u` escapes or `intToUtf8()` (both always marked `UTF-8`) |
| E3 | `gsub("[ \\t\\x{00A0}\\x{3000}]+$", …, perl=TRUE)` on unmarked strings, C locale | error `invalid regular expression …`, preceded by the PCRE warning "character code point value in \x{} or \o{} is too large" | mark inputs (`Encoding(x) <- "UTF-8"`); with marked inputs results are identical in both locales |
| E4 | `file.create()/file.exists()/basename()` with a UTF-8-*marked* non-ASCII path, C locale | error/warning "unable to translate '…<U+00E9>…' to native encoding" | strip the mark (`Encoding(p) <- "unknown"`) before OS calls on non-UTF-8 Unix locales (`os_path()` in the prototype) |
| E5 | `list.files()` on a directory with non-ASCII names | names come back unmarked (`unknown`) but are valid UTF-8 bytes | mark results as UTF-8 before regex/output |
| E6 | `enc2utf8()` on an unmarked string holding UTF-8 bytes, C locale | re-encodes from the native encoding → mangles | `as_utf8()`: if unmarked and `validUTF8()` → just mark |
| E7 | `jsonlite::base64_enc(as.raw(0:80))` (jsonlite 2.0.0) | contains `"\n"` after **72** characters (lines of 72; corrected by the verifier from 76) | strip `[\r\n]`, or use `base64enc::base64encode()` / `openssl::base64_encode()` (no newlines by default; verified) |
| E8 | `strsplit("a\nb\n", "\n", fixed=TRUE)` | drops the trailing empty piece | JS `split` semantics need `strsplit(paste0(x, "\n"), …)` |
| E9 | `rawToChar()` with a NUL byte | error "embedded nul in string" | binary sniffing must happen on raw vectors |
| E10 | `setTimeLimit(elapsed=0.5, transient=TRUE)` then a busy R loop / a loop of `Sys.sleep(0.1)` | interrupted after 0.53 s / 0.74 s (verifier re-run under heavy load: 0.51 s / 1.04 s) | works for ordinary R code |
| E11 | same, then one `Sys.sleep(3)`; `svd()` of a 2000×2000 matrix; `system2("sleep","3")` | **not interrupted** (3.0 s; 22.7 s; 3.0 s), and no error afterwards | in-session timeouts are *soft*; document it in the tool description |
| E12 | `system2(…, timeout = 0.5)` / `timeout = 1` | 0.5 is ignored (ran 5 s); 1 works (warning "timed out after 1s", status 124) | `ceiling(timeout)` in the fallback |
| E13 | `ragg::agg_png(file); dev.off()` without plotting vs `grDevices::png()` | ragg writes `p-001.png` anyway; `png()` writes nothing | count pages with `before.plot.new` / `before.grid.newpage` hooks |
| E14 | `grepl("a(", x, perl=TRUE)` | error `invalid regular expression 'a('` + *warning* `PCRE pattern compilation error 'missing closing parenthesis' at ''` | capture the warning to give the model the reason |
| E15 | `grepl(pattern, x, fixed=TRUE, ignore.case=TRUE)` | `ignore.case` ignored **with a warning** ("argument 'ignore.case = TRUE' will be ignored"; corrected by the verifier: not silent) | literal + ignoreCase must use `\Q…\E` with `perl=TRUE` |
| E16 | `cat()` of a UTF-8 string into a `sink()` file, C locale | written as `<U+4F60>` escapes | output capture is only faithful in UTF-8 locales (all modern defaults incl. Windows R ≥ 4.2) |
| E17 | `file.rename(a, b)` with existing `b` (macOS) | `TRUE`, replaced | atomic write via temp file + rename works on POSIX; UNCERTAIN on Windows |
| E18 | `normalizePath("/tmp/../tmp/./a/b/../c", mustWork=FALSE)` | returned unchanged | lexical normalisation must be implemented by hand |
| E19 | `path.expand("~draft.md")` | `"~draft.md"` | matches Pi's rule |

---

## 3. Exact specifications (Pi, verbatim)

### 3.1 Constants

| Constant | Value | Source |
|---|---|---|
| `DEFAULT_MAX_LINES` | `2000` | `CA/src/core/tools/truncate.ts:11` |
| `DEFAULT_MAX_BYTES` | `50 * 1024` = 51200 | `truncate.ts:12` |
| `GREP_MAX_LINE_LENGTH` | `500` characters | `truncate.ts:13` |
| grep `DEFAULT_LIMIT` | `100` matches (min 1) | `grep.ts:41, 136` |
| find `DEFAULT_LIMIT` | `1000` results | `find.ts:41` |
| ls `DEFAULT_LIMIT` | `500` entries | `ls.ts:23` |
| bash `MAX_TIMEOUT_MS` | `2_147_483_647` ms | `bash.ts:22` |
| bash `STRUCTURED_OUTPUT_MAX_BYTES` | `1024 * 1024` | `bash.ts:24` |
| `BASH_UPDATE_THROTTLE_MS` | `100` | `renderers/bash.ts:19` |
| `EXIT_STDIO_GRACE_MS` | `100` | `CA/src/utils/child-process.ts:16` |
| `IMAGE_TYPE_SNIFF_BYTES` | `4100` | `CA/src/utils/mime.ts:3` |
| image `maxWidth` / `maxHeight` | `2000` / `2000` | `CA/src/utils/image-resize-core.ts:24-29` |
| image `maxBytes` (base64 payload) | `4.5 * 1024 * 1024` | `image-resize-core.ts:22` |
| image `jpegQuality` / quality ladder | `80` / `[80, 85, 70, 55, 40]` | `image-resize-core.ts:28, 122` |
| image shrink factor | `0.75` per step | `image-resize-core.ts:146-147` |
| diff context lines | `4` | `edit-diff.ts:365, 379` |
| rolling output buffer | `max(2 * maxBytes, 1)` = 102400 bytes, trimmed when > 204800 | `output-accumulator.ts:67, 198` |
| tool downloads | network timeout 10 s, download timeout 120 s | `tools-manager.ts:11-12` |
| `DEFAULT_TOOL_NAMES` | `["read","bash","edit","write"]` | `settings-manager.ts:213` |
| `POWERSHELL_ARGS` | `["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-Command"]` | `shell.ts:122` |
| codemode output budget / memory | 10000 tokens / 256 MB | `codemode/tool.ts:140, 145` |
| tool_search default limit | `8` | `tool-search/tool.ts:21` |

### 3.2 `read`

Description (verbatim, template expanded):

> Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.

`promptSnippet`: `Read file contents` — `promptGuidelines`: `Use read to examine files instead of cat or sed.`

Schema (generated from the TypeBox definition in `read.ts:14-18` with typebox 1.3.7; Pi pins 1.3.27 — shape VERIFIED, key order LIKELY identical):

```json
{
  "type": "object",
  "required": ["path"],
  "properties": {
    "path":   { "type": "string", "description": "Path to the file to read (relative or absolute)" },
    "offset": { "type": "number", "description": "Line number to start reading from (1-indexed)" },
    "limit":  { "type": "number", "description": "Maximum number of lines to read" }
  }
}
```

Result texts (each is the whole text block; `${…}` are values):

| Situation | Text |
|---|---|
| fits | file content verbatim |
| cut by line limit | `${content}\n\n[Showing lines ${start}-${end} of ${totalFileLines}. Use offset=${end+1} to continue.]` |
| cut by byte limit | `${content}\n\n[Showing lines ${start}-${end} of ${totalFileLines} (50.0KB limit). Use offset=${end+1} to continue.]` |
| user `limit` stopped before EOF | `${content}\n\n[${remaining} more lines in file. Use offset=${next} to continue.]` |
| first selected line > 50 KB | `[Line ${n} is ${size}, exceeds 50.0KB limit. Use bash: sed -n '${n}p' ${path} \| head -c 51200]` (no `\` in the original; escaped here for the table) |
| image | block 1 text `Read image file [${mimeType}]` + optional hint lines; block 2 image |
| image failed | `Read image file [${mimeType}]\n[Image omitted: could not be converted to a supported inline image format.]` or `…\n[Image omitted: could not be resized below the inline image size limit.]` |
| non-vision model | extra line `[Current model does not support images. The image will be omitted from this request.]` |

Errors: `Offset ${offset} is beyond end of file (${n} lines total)`; Node fs errors (`ENOENT: no such file or directory, access '…'`, `EACCES…`, `EISDIR…`); `Operation aborted`.

`details`: `undefined`, or `{ truncation: TruncationResult }`.

### 3.3 `write`

Description:

> Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.

`promptSnippet`: `Create or overwrite files` — `promptGuidelines`: `Use write only for new files or complete rewrites.`

```json
{
  "type": "object",
  "required": ["path", "content"],
  "properties": {
    "path":    { "type": "string", "description": "Path to the file to write (relative or absolute)" },
    "content": { "type": "string", "description": "Content to write to the file" }
  }
}
```

Result: `Successfully wrote to ${path}`; `details: undefined`. Errors: Node fs messages; `Operation aborted`.

### 3.4 `edit`

Description:

> Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.

`promptSnippet`: `Make precise file edits with exact text replacement, including multiple disjoint edits in one call`

`promptGuidelines` (four bullets):

1. `Use edit for precise changes (edits[].oldText must match exactly)`
2. `When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls`
3. `Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.`
4. `Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions.`

```json
{
  "type": "object",
  "required": ["path", "edits"],
  "properties": {
    "path": { "type": "string", "description": "Path to the file to edit (relative or absolute)" },
    "edits": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["oldText", "newText"],
        "properties": {
          "oldText": { "type": "string", "description": "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call." },
          "newText": { "type": "string", "description": "Replacement text for this targeted edit." }
        }
      },
      "description": "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."
    }
  }
}
```

Result: `Successfully replaced ${edits.length} block(s) in ${path}.`; `details: { diff: string, patch: string, firstChangedLine?: number }`.

Error messages (verbatim; "single" = exactly one edit in the call; indices are 0-based):

| Condition | single edit | multiple edits |
|---|---|---|
| empty/invalid `edits` | `Edit tool input is invalid. edits must contain at least one replacement.` | same |
| file not accessible | `Could not edit file: ${path}. Error code: ${code}.` (or `… Error: ${message}.`) | same |
| empty `oldText` | `oldText must not be empty in ${path}.` | `edits[${i}].oldText must not be empty in ${path}.` |
| not found | `Could not find the exact text in ${path}. The old text must match exactly including all whitespace and newlines.` | `Could not find edits[${i}] in ${path}. The oldText must match exactly including all whitespace and newlines.` |
| not unique | `Found ${n} occurrences of the text in ${path}. The text must be unique. Please provide more context to make it unique.` | `Found ${n} occurrences of edits[${i}] in ${path}. Each oldText must be unique. Please provide more context to make it unique.` |
| overlap | – | `edits[${i}] and edits[${j}] overlap in ${path}. Merge them into one edit or target disjoint regions.` |
| nothing changed | `No changes made to ${path}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.` | `No changes made to ${path}. The replacements produced identical content.` |
| fuzzy overlay impossible | `Cannot preserve unchanged lines because the base content has a different line count.` | same |
| abort | `Operation aborted` | same |

### 3.5 `bash` / `powershell`

Description (`${shellName}` = `bash` or `PowerShell`):

> Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.

`promptSnippet`: bash `Execute bash commands (ls, grep, find, etc.)`; powershell `Execute PowerShell commands` — `promptGuidelines` (both): `You can inspect PI_* environment variables for current model and session details.`

```json
{
  "type": "object",
  "required": ["command"],
  "properties": {
    "command": { "type": "string", "description": "Shell command to execute" },
    "timeout": { "type": "number", "description": "Timeout in seconds (optional, no default timeout)" }
  }
}
```

Output schema (`structuredContent`, never sent to the model):

```json
{
  "type": "object",
  "required": ["output", "truncated", "exit_code", "wall_time_seconds"],
  "properties": {
    "output": { "type": "string", "description": "Combined stdout and stderr, up to 1 MiB. Longer output keeps its first and last 512 KiB around an omission marker." },
    "truncated": { "type": "boolean", "description": "Whether `output` omits part of the command output" },
    "full_output_path": { "type": "string", "description": "Temp file with the full output, when truncated" },
    "exit_code": { "type": "number" },
    "wall_time_seconds": { "type": "number" }
  }
}
```

Result texts:

| Situation | Text |
|---|---|
| success, output | `${output}` |
| success, empty | `(no output)` |
| truncated by lines | `${tail}\n\n[Showing lines ${start}-${end} of ${total}. Full output: ${tempFile}]` |
| truncated by bytes | `${tail}\n\n[Showing lines ${start}-${end} of ${total} (50.0KB limit). Full output: ${tempFile}]` |
| last line alone > 50 KB | `${partial}\n\n[Showing last ${size} of line ${n} (line is ${lineSize}). Full output: ${tempFile}]` |
| exit code ≠ 0 (`isError: true`) | `${output}\n\nCommand exited with code ${code}` (observed in Pi's test: `"out\n\n\nCommand exited with code 3"` because the output itself ends in `\n`; with empty output the text is `(no output)\n\nCommand exited with code N`) |
| timeout (thrown) | `${output}\n\nCommand timed out after ${timeout} seconds` (with no output: the status line alone, no leading blank lines — `appendStatus`, `bash.ts:361`) |
| abort (thrown) | `${output}\n\nCommand aborted` (same rule for empty output) |
| no exit code (custom backends) | `${output}\n\nCommand terminated without an exit code` |

Other errors: `Working directory does not exist: ${cwd}\nCannot execute bash commands.`; `Custom shell path not found: ${path}`; on Windows without bash:
`No bash shell found. Options:\n  1. Install Git for Windows: https://git-scm.com/download/win\n  2. Add your bash to PATH (Cygwin, MSYS2, etc.)\n  3. Set shellPath in settings.json\n\nSearched Git Bash in:\n  …`; `No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH.`; spawn errors (`spawn … ENOENT`).

`details`: `undefined`, or `{ truncation: TruncationResult, fullOutputPath: string }`.

### 3.6 `grep`

Description:

> Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.

`promptSnippet`: `Search file contents for patterns (respects .gitignore)` — no guidelines.

```json
{
  "type": "object",
  "required": ["pattern"],
  "properties": {
    "pattern":    { "type": "string",  "description": "Search pattern (regex or literal string)" },
    "path":       { "type": "string",  "description": "Directory or file to search (default: current directory)" },
    "glob":       { "type": "string",  "description": "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'" },
    "ignoreCase": { "type": "boolean", "description": "Case-insensitive search (default: false)" },
    "literal":    { "type": "boolean", "description": "Treat pattern as literal string instead of regex (default: false)" },
    "context":    { "type": "number",  "description": "Number of lines to show before and after each match (default: 0)" },
    "limit":      { "type": "number",  "description": "Maximum number of matches to return (default: 100)" }
  }
}
```

Output example (Pi test `tools.test.ts:882-901`, `limit: 1, context: 1`):

```
context.txt-1- before
context.txt:2: match one
context.txt-3- after

[1 matches limit reached. Use limit=2 for more, or refine pattern]
```

Notices (joined with `". "` inside one pair of brackets, preceded by a blank line): `${limit} matches limit reached. Use limit=${limit*2} for more, or refine pattern` · `50.0KB limit reached` · `Some lines truncated to 500 chars. Use read tool to see full lines`. Unreadable file during context formatting: `${path}:${line}: (unable to read file)`.

`details`: `undefined` or `{ truncation?, matchLimitReached?: number, linesTruncated?: boolean }`.

### 3.7 `find`

Description:

> Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).

`promptSnippet`: `Find files by glob pattern (respects .gitignore)` — no guidelines.

```json
{
  "type": "object",
  "required": ["pattern"],
  "properties": {
    "pattern": { "type": "string", "description": "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'" },
    "path":    { "type": "string", "description": "Directory to search in (default: current directory)" },
    "limit":   { "type": "number", "description": "Maximum number of results (default: 1000)" }
  }
}
```

Output: one relative path per line. Notices: `${limit} results limit reached. Use limit=${limit*2} for more, or refine pattern` · `50.0KB limit reached`. Empty: `No files found matching pattern`. `details`: `undefined` or `{ truncation?, resultLimitReached?: number }`.

### 3.8 `ls`

Description:

> List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).

`promptSnippet`: `List directory contents` — no guidelines.

```json
{
  "type": "object",
  "properties": {
    "path":  { "type": "string", "description": "Directory to list (default: current directory)" },
    "limit": { "type": "number", "description": "Maximum number of entries to return (default: 500)" }
  }
}
```

(no `required` key at all). Notices: `${limit} entries limit reached. Use limit=${limit*2} for more` · `50.0KB limit reached`. Empty: `(empty directory)`. `details`: `undefined` or `{ truncation?, entryLimitReached?: number }`.

### 3.9 Tool declaration on the wire

Anthropic Messages API (one element of `tools`): `{"name": "...", "description": "...", "input_schema": <schema>}`; with strict sampling the schema is first passed through `makeStrictJsonSchema` (§2.2). OpenAI-style: `{"type":"function","function":{"name","description","parameters":<schema>}}`. (Provider details belong to the provider tracks; listed here only to show that the three fields `name`, `description`, `parameters` are all a tool contributes besides the system-prompt snippet/guidelines.)

### 3.10 Default system prompt (verbatim)

Reconstructed by executing a line-by-line copy of `buildRules()` / `buildSystemPromptSections()` / `getSystemMessageText()` with the real snippets and guidelines (script `sysprompt.mjs`, run with node v26.8.2). `<PKG_DIR>` stands for the absolute installation directory of the `pi-coding-agent` package (`getReadmePath()` etc., `CA/src/config.ts:441-453`). Default tool selection `[read, bash, edit, write]`, no context files, no skills:

```text
You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.

<tools>
- read: Read file contents
- bash: Execute bash commands (ls, grep, find, etc.)
- edit: Make precise file edits with exact text replacement, including multiple disjoint edits in one call
- write: Create or overwrite files

In addition to the tools above, you may have access to other custom tools depending on the project.
</tools>

<rules>
- Use bash for file operations like ls, rg, find
- Use read to examine files instead of cat or sed.
- You can inspect PI_* environment variables for current model and session details.
- Use edit for precise changes (edits[].oldText must match exactly)
- When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls
- Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.
- Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions.
- Use write only for new files or complete rewrites.
- Be concise in your responses
- Show file paths clearly when working with files
</rules>

<docs>
Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):
- Main documentation: <PKG_DIR>/README.md
- Additional docs: <PKG_DIR>/docs
- Examples: <PKG_DIR>/examples (extensions, custom tools, SDK)
- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory
- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), pi packages (docs/packages.md), environment variables (docs/environment-variables.md), MCP servers (docs/mcp.md)
- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing
- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)
</docs>

<cwd>
/Users/me/project
</cwd>
```

With the read-only set `[read, grep, find, ls]` the `<tools>` section lists those four snippets and `<rules>` shrinks to:

```text
<rules>
- Use read to examine files instead of cat or sed.
- Be concise in your responses
- Show file paths clearly when working with files
</rules>
```

Optional sections, in order, when present:

```text
<addendum>
${appendSystemPrompt}
</addendum>

<project_context>
Project-specific instructions and guidelines:

<project_instructions path="${path}">
${content}
</project_instructions>
</project_context>

<skills>
The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.

<available_skills>
  <skill>
    <name>${name}</name>
    <description>${description}</description>
    <location>${filePath}</location>
  </skill>
</available_skills>
</skills>
```

(`CA/src/core/skills.ts:355-392`; values are XML-escaped; skills with `disableModelInvocation` are omitted.)

---

## 4. Recommended design for gptr

### 4.1 Tool list

| gptr tool | Pi ancestor | Default | Mutating | Notes |
|---|---|---|---|---|
| `read` | `read` | on | no | schema and texts identical to Pi; adds binary-file notice, CP1252/latin1/UTF-16 decoding |
| `run_r` | `bash` | on | yes | evaluates R code in the caller's environment (REQ-09, REQ-22, REQ-23) |
| `edit` | `edit` | on | yes | schema, algorithm and messages identical to Pi; round-trips non-UTF-8 encodings |
| `write` | `write` | on | yes | identical |
| `grep` | `grep` | on (see below) | no | pure R, PCRE; schema identical except wording "Perl-compatible regex" |
| `find` | `find` | on (see below) | no | pure R glob; optional `sort` enum (REQ-08) |
| `ls` | `ls` | on (see below) | no | pure R; deterministic sort |
| `shell` | `bash`/`powershell` | **off** | yes | `processx` (Suggests) or `system2()`; description names the detected shell |

**Default selection — decision needed (open question Q1).** Pi's default is the four-tool core because `bash` gives the model `rg`/`fd`/`ls`. gptr has no shell by default, and writing `list.files()`/`readLines()`/`grepl()` loops through `run_r` for every code search is slower, ignores `.gitignore`, and risks huge outputs. Recommendation: **default = `read, run_r, edit, write, grep, find, ls`** (the seven schemas + descriptions cost ≈ 1,200 tokens, measured as characters/4 in the prototype: read 152, run_r 187, edit 276, write 88, grep 244, find 172, ls 99), plus named presets so REQ-10's "minimal surface" stays one argument away:

```r
gptr_tool_presets <- list(
  default  = c("read", "run_r", "edit", "write", "grep", "find", "ls"),
  minimal  = c("read", "run_r", "edit", "write"),          # Pi-equivalent core
  readonly = c("read", "grep", "find", "ls")               # Pi's read-only set; safe for review/planning sub-agents
)
```

Every tool must also be callable as an ordinary R function from `run_r` code (e.g. `gptr::tool_grep("pattern", "R/")`), which makes the `minimal` preset fully capable — this is the R analogue of Pi's `codemode`.

Selection syntax (identical to Pi's `defaultTools`, VERIFIED port `resolve_tool_selection()`): `tools = NULL` → preset default (**caution, verifier:** in the §5 prototype `GPTR_DEFAULT_TOOLS` is the four-tool `minimal` set `c("read","run_r","edit","write")` and `test-03.R` asserts that, so `resolve_tool_selection(NULL)` and `build_system_prompt()` default to four tools; the seven-tool recommendation above is *not* what the prototype implements — change the constant and that assertion when adopting it); `tools = c("read","grep")` → replace; `tools = c("+shell", "-write")` → modify; `exclude = ` applied last. With REQ-19 (NSE) the user-facing form can be `gptr("…", tools = c(read, grep, +shell))`.

### 4.2 Data structures

```r
# A tool (S3 class "gptr_tool"); `parameters` is a JSON Schema as nested R lists
gptr_tool(
  name,                     # chr(1), must match ^[a-zA-Z0-9_-]{1,64}$ (Anthropic's documented limit is now {1,128}, checked 2026-09-29; 64 is kept as a conservative limit, LIKELY safe for other providers but not verified here)
  description,              # chr(1), sent to the model
  parameters,               # list(type = "object", required = I(chr), properties = list(...))
  execute,                  # function(args, ctx) -> gptr_tool_result   (may signal conditions)
  snippet      = NULL,      # one line for the <tools> prompt section
  guidelines   = character(),# bullets for the <rules> prompt section
  prepare      = NULL,      # function(args) -> args  (compatibility shim before validation)
  mutates      = FALSE,     # permission gating (REQ-37): TRUE for run_r, edit, write, shell
  default_active = TRUE
)

# Context handed to execute()
ctx <- list(
  cwd    = getwd(),         # evaluated at call time: the model may setwd() via run_r
  envir  = <environment>,   # caller's environment (REQ-22)
  images = TRUE,            # does the current model accept images?
  check_abort = function() NULL   # called inside long loops; signals an "interrupt"/abort condition
)

# A result (S3 class "gptr_tool_result")
list(
  content = list(list(type = "text", text = "..."),
                 list(type = "image", data = "<base64, no newlines>", mimeType = "image/png")),
  details = list(...),      # never sent to the model: truncation, diff, patch, fullOutputPath, created objects
  isError = FALSE
)
```

JSON schema helper constructors (`s_string()`, `s_number()`, `s_boolean()`, `s_enum()`, `s_array()`, `s_object(..., .required=)`) are in the prototype; **`required` and `enum` must be wrapped in `I()`** so that `jsonlite::toJSON(auto_unbox = TRUE)` keeps one-element vectors as JSON arrays. The prototype's `read`, `edit` and `ls` schemas serialise **byte-identically** to Pi's (asserted in `test-03.R`).

Tool-call arguments must be parsed with `jsonlite::fromJSON(txt, simplifyVector = FALSE)` (lists of lists, never data frames).

### 4.3 Dispatcher

`execute_tool_call(tools, name, args, ctx)` never throws (port of Pi's pipeline, §2.2): unknown tool → `Tool <name> not found`; `prepare()`; `validate_args()` (drops `NULL`/JSON `null`, coerces `"2"`→2, `"true"`→TRUE, number→string, checks required/type/enum, recurses into arrays of objects; message format identical to Pi's); permission hook (`before_tool_call`, may block with a reason); `execute()`; `tryCatch(error=, interrupt=)` → error result (`Operation aborted` for interrupts). gptr executes tool calls **sequentially** in the R session, so Pi's file mutation queue is unnecessary in-process; parallel sub-agents running in *separate R processes* (REQ-33) should serialise writes with the optional `filelock` package or accept last-writer-wins (open question Q6).

### 4.4 R-side parameter schemas (final proposal)

Schemas for `read`, `write`, `edit`, `ls` — exactly §3.2, §3.3, §3.4, §3.8. The remaining ones:

```json
{ "name": "run_r",
  "description": "Evaluate R code in the user's live R session (the same environment the user works in). Objects persist between calls and are visible to the user: inspect existing objects instead of re-loading data. Returns printed output, messages, warnings and errors; plots are returned as images. Output is truncated to the first and last 1000 lines or 25KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
  "parameters": {
    "type": "object",
    "required": ["code"],
    "properties": {
      "code":    { "type": "string", "description": "R code to evaluate. May contain several expressions; visible values are printed as at the console" },
      "timeout": { "type": "number", "description": "Timeout in seconds (optional, no default timeout)" }
    } } }
```

```json
{ "name": "grep",
  "description": "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",
  "parameters": {
    "type": "object",
    "required": ["pattern"],
    "properties": {
      "pattern":    { "type": "string",  "description": "Search pattern (Perl-compatible regex, or literal string)" },
      "path":       { "type": "string",  "description": "Directory or file to search (default: current directory)" },
      "glob":       { "type": "string",  "description": "Filter files by glob pattern, e.g. '*.R' or '**/*.qmd'" },
      "ignoreCase": { "type": "boolean", "description": "Case-insensitive search (default: false)" },
      "literal":    { "type": "boolean", "description": "Treat pattern as literal string instead of regex (default: false)" },
      "context":    { "type": "number",  "description": "Number of lines to show before and after each match (default: 0)" },
      "limit":      { "type": "number",  "description": "Maximum number of matches to return (default: 100)" }
    } } }
```

```json
{ "name": "find",
  "description": "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).",
  "parameters": {
    "type": "object",
    "required": ["pattern"],
    "properties": {
      "pattern": { "type": "string", "description": "Glob pattern to match files, e.g. '*.R', '**/*.csv', or 'R/**/*.R'" },
      "path":    { "type": "string", "description": "Directory to search in (default: current directory)" },
      "limit":   { "type": "number", "description": "Maximum number of results (default: 1000)" },
      "sort":    { "type": "string", "enum": ["path", "mtime", "size"], "description": "Result order: path (default, alphabetical), mtime (newest first) or size (largest first)" }
    } } }
```

```json
{ "name": "shell",
  "description": "Execute a ${shell name: bash | bash (Git Bash) | PowerShell | cmd.exe | sh} command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
  "parameters": {
    "type": "object",
    "required": ["command"],
    "properties": {
      "command": { "type": "string", "description": "Shell command to execute" },
      "timeout": { "type": "number", "description": "Timeout in seconds (optional, no default timeout)" }
    } } }
```

Prompt snippets / guidelines for the new tools:

| Tool | snippet | guidelines |
|---|---|---|
| `read` | `Read file contents` | `Use read to examine files instead of readLines() or cat() in run_r.` |
| `run_r` | `Evaluate R code in the live session (objects persist; plots are returned as images)` | `Use run_r for computation and data inspection in the live session; do not shell out for things R can do` · `Objects created with run_r stay in the user's session: do not re-load data that is already in memory, and print compact summaries (str(), head(), dim()) rather than whole objects` |
| `shell` | `Execute ${shell name} commands (git, quarto, system utilities)` | `Use shell only for external programs; prefer run_r for anything R can do` |
| conditional rule | – | if `run_r` is active and none of grep/find/ls: `Use run_r for file operations like list.files(), file.info(), grepl()` |

### 4.5 Function signatures (as prototyped and tested)

```r
tool_read (path, offset = NULL, limit = NULL, cwd = getwd(), model_supports_images = TRUE, auto_resize_images = TRUE)
tool_write(path, content, cwd = getwd())
tool_edit (path, edits, cwd = getwd(), dry_run = FALSE)        # dry_run = preview diff for permission prompts
tool_ls   (path = NULL, limit = NULL, cwd = getwd())
tool_find (pattern, path = NULL, limit = NULL, sort = c("path","mtime","size"), type = c("any","file","dir"),
           cwd = getwd(), hidden = TRUE, check_abort = NULL)
tool_grep (pattern, path = NULL, glob = NULL, ignoreCase = FALSE, literal = FALSE, context = NULL, limit = NULL,
           cwd = getwd(), hidden = TRUE, check_abort = NULL)
tool_run_r(code, timeout = NULL, envir = globalenv(), capture_plots = TRUE, max_plots = 4L,
           plot_width = 1200, plot_height = 900, plot_res = 144)
tool_shell(command, timeout = NULL, cwd = getwd(), shell = resolve_shell(), use_processx = requireNamespace("processx", quietly = TRUE))

# shared internals
truncate_head(content, max_lines = 2000L, max_bytes = 51200L)     # -> TruncationResult-like list
truncate_tail(content, max_lines = 2000L, max_bytes = 51200L)
truncate_middle_lines(content, max_lines = 2000L, max_bytes = 51200L)
truncate_line(line, max_chars = 500L)
format_size(bytes)
resolve_to_cwd(path, cwd); resolve_read_path(path, cwd); path_norm_lexical(p); normalize_tool_path(p)
decode_text(bytes) -> list(text, encoding); encode_text(text, encoding); is_binary_bytes(bytes, sniff = 8000L)
detect_image_mime(bytes); image_dims(bytes, mime); process_image(bytes, mime, auto_resize = TRUE)
normalize_for_fuzzy(text); fuzzy_find_text(content, old_text); apply_edits_to_normalized_content(content, edits, path)
diff_ops(a, b, max_d = 4000L); generate_diff_string(old, new, context = 4L); generate_unified_patch(path, old, new, context = 4L)
glob_to_regex(glob, braces = TRUE); compile_ignore_rules(lines, base = ""); apply_ignore_rules(rules, rel, is_dir)
walk_files(root, hidden = TRUE, use_ignore_files = TRUE, default_ignore = DEFAULT_IGNORE, ...)
builtin_tools(shell = NULL); resolve_tool_selection(entries, defaults, exclude); validate_args(schema, args)
execute_tool_call(tools, name, args, ctx); build_system_prompt(tools, selected, cwd, custom_prompt, append, context_files, skills_text, ...)
```

### 4.6 Algorithms

**Text I/O (all tools).** Read with `readBin(con, "raw", n)`; decide on raw bytes: image magic → NUL byte in the first 8000 bytes (binary; UTF-16 BOM exempt) → decode. Decoding order: UTF-16 BOM → `iconv`; valid UTF-8 → mark; else CP1252, else latin1. Write with `writeBin(bytes, file(path, "wb"))` — **never text-mode connections** (CRLF translation on Windows) and encode *before* opening the file so a failed conversion cannot truncate it.

**`read`**: port of §2.3 with JS `split` semantics; identical notices; `firstLineExceedsLimit` message points to `run_r` instead of `sed`. Non-image binary files return `[Binary file: <path> (<size>). Not shown as text. Use the run_r tool to load it, e.g. readRDS().]` with hints for `.rds/.RData/.parquet/.feather/.xlsx/.qs2/.pdf`.

**`edit`**: port of §2.5 operating on **bytes** (`regexpr(..., fixed = TRUE, useBytes = TRUE)`, raw-vector splicing) so it is locale-independent; fuzzy normalisation uses `stringi::stri_trans_nfkc()` when available (without stringi the NFKC step is skipped, everything else works); the diff is a pure-R Myers O(ND) implementation with common prefix/suffix trimming and chunked backtracking (`max_d = 4000`, beyond that the changed middle is reported as replaced). The file's original encoding is kept: a CP1252 R script stays CP1252; text that cannot be represented is refused with `Text contains characters that cannot be represented in the file's encoding (CP1252).` and the file is left untouched.

**Walker (`grep`, `find`)**: breadth-first, **one `list.files()` + one `dir.exists()` call per directory level** (both vectorised), ignored directories are pruned before descending; symlinked directories are not followed. Ignore sources, lowest to highest precedence: `DEFAULT_IGNORE` (`.git/`, `.Rproj.user/`, `renv/library/`, `renv/staging/`, `renv/sandbox/`, `packrat/lib*/`, `node_modules/`, `__pycache__/`, `.venv/`), ignore files of ancestor directories up to the git root, then `.gitignore`, `.ignore`, `.gptrignore` of each visited directory (deeper files override shallower ones; within a file the last matching rule wins; `!` negation; `/`-anchoring; trailing-`/` directory rules; `**`). Not implemented (documented gap): `.git/info/exclude`, `core.excludesFile`.

**`find`**: fd semantics — pattern without `/` matches the basename; with `/` it matches the path relative to the search root as `**/<pattern>`; absolute patterns match the absolute path; smart case; files and directories (`/` suffix); then deterministic sort (`order(tolower(x), x, method = "radix")`), optional `mtime`/`size` sort, `limit`.

**`grep`**: candidate files from the walker (or the single file), optional gitignore-style `glob` filter (`!pattern` excludes), sorted by path; files > 10 MB are skipped and counted in a notice; processed in batches of 256: read → sniff → decode → CRLF→LF → **whole-file pre-filter** `grepl(paste0("(?m)", rx), texts, perl = TRUE)` (one vectorised call per batch) → only files that can match are split into lines and matched per line. The pre-filter is disabled for patterns containing `\A`, `\z`, `\Z`, `\G` or starting with `(*`. `literal` → `fixed = TRUE`; `literal` + `ignoreCase` → `\Q…\E` with `perl = TRUE`. Invalid regex → `regex parse error: 'missing closing parenthesis' at '' (pattern: a()`. With `context > 0` overlapping blocks are merged and non-adjacent blocks separated by `--` (grep convention) — a deliberate token-saving deviation from Pi.

**`ls`**: `list.files(all.files = TRUE, no.. = TRUE, include.dirs = TRUE)`, radix sort on `tolower()`, `dir.exists()` for the `/` suffix.

**`run_r`** (prototype level; the dedicated R-evaluation track should refine it):
1. `parse(text = code, encoding = "UTF-8")`; a syntax error returns `Error: parse failed\nline L:C: unexpected symbol\n…` without evaluating anything;
2. open a PNG device (`ragg::agg_png` if available, else `grDevices::png`) on `plot-%03d.png` in a temp dir, install `before.plot.new`/`before.grid.newpage` hooks to count pages; `sink()` stdout to a temp file; `options(warn = 1, max.print = 5000, width = 120)`; optional `setTimeLimit(elapsed = timeout, transient = TRUE)`;
3. evaluate expression by expression with `withVisible(eval(ex, envir))`, auto-printing visible values (`methods::show` for S4); messages and warnings are written immediately and in order through calling handlers (`Warning in f(x) : msg` / `Warning: msg`), evaluation stops at the first error (`Error in f(5) : too big: 5` / `Error: boom`);
4. always restore sinks, options, time limit, hooks and the previously active graphics device;
5. output: ANSI codes stripped, **head + tail** truncation (first 1000 + last 1000 lines / 25 KB each) with `[... N lines omitted ...]` and `[Showing first 1000 and last 1000 of N lines. Full output: <tempfile>]`; status line `Code timed out after N seconds` / `Code aborted`; `(no output)`; plots appended as image blocks (last 4); `details$created` lists new object names in `envir` (useful for the script-as-history document, REQ-24/26).

**`shell`**: `processx::run(shell, c(args, command), wd = cwd, timeout, stdout = <tempfile>, stderr = "2>&1", cleanup_tree = TRUE, windows_hide_window = TRUE, error_on_status = FALSE)`; fallback `system2(shell, c(args, shQuote(command)), stdout = TRUE, stderr = TRUE, timeout = ceiling(timeout))`. Texts identical to Pi's bash (§3.5). Shell resolution: option `gptr.shell` → Windows: Git Bash → `pwsh.exe` → `powershell.exe` → `cmd.exe /d /s /c`; Unix: `/bin/bash` → `bash` on PATH → `sh`. PowerShell gets Pi's args and UTF-8 prefix.

### 4.7 Package choices

| Package | Role | Recommendation | Reason |
|---|---|---|---|
| `jsonlite` | JSON schemas, argument parsing, base64 | **Imports** | needed by every provider anyway; remember to strip newlines from `base64_enc()` |
| `stringi` | NFKC/NFD normalisation in `edit` fuzzy fallback and `read` path variants | Suggests (opportunistic) | compiled, large; everything else works without it (VERIFIED) |
| `processx` | `shell` tool: process-tree kill, sub-second timeouts, Windows quoting | Suggests (needed only when `shell` is enabled; `system2` fallback exists) | compiled dependency; also relevant for MCP stdio / sub-agents tracks, which may promote it to Imports |
| `magick` | image resize / BMP→PNG in `read` | Suggests | system library; without it images within limits are sent unchanged, others omitted with Pi's message |
| `ragg` | plot capture device on headless machines | Suggests | `grDevices::png()` needs X11/cairo capabilities on some Linux builds |
| `evaluate` | alternative engine for `run_r` | Suggests / decision for the run_r track | pure R (`NeedsCompilation: no`, no Imports; 1.0.5 installed), battle-tested by knitr; the base-R prototype shows it is not strictly required |
| `diffobj` | – | not needed | pure-R Myers diff in the prototype is sufficient |
| `fs` | – | not needed | base R + the helpers above cover it |
| `filelock` | cross-process write serialisation for parallel sub-agents | Suggests (optional) | only if sub-agents share a working tree |

`Depends: R (>= 4.2.0)` is recommended: native pipe (REQ-18) needs 4.1, and Windows gets UTF-8 as the native encoding only with R ≥ 4.2 (UCRT).

### 4.8 Deviations from Pi (summary, all intentional)

| Topic | Pi | gptr proposal | Why |
|---|---|---|---|
| grep/find engine | ripgrep / fd binaries | pure R | REQ-01, REQ-07, REQ-08 |
| result order of grep/find | unspecified | sorted by path (find: optional mtime/size) | determinism, REQ-08, reproducible history documents |
| `.git/` | searched by `grep`, listed by `find` (fd ≥ 10) | always skipped | never useful, token waste |
| `.gitignore` outside git repos | `find` yes, `grep` no | always honoured | consistency |
| positive glob overrides ignore rules | yes (ripgrep) | no | simpler, safer |
| anchoring of a `glob` containing `/` | rg's process cwd (Pi spawns rg without `cwd`; verified) | the search root (`path`) | what a model expects; independent of the R session's `getwd()` |
| regex dialect | Rust regex | PCRE (`perl = TRUE`) | base R; superset for almost all patterns models write |
| grep context blocks | repeated when overlapping | merged, `--` between blocks | fewer tokens |
| files > 10 MB in grep | searched | skipped with notice | R projects contain large data files |
| binary non-image files in `read` | decoded as UTF-8 garbage | notice with an R loading hint | useful in data projects |
| non-UTF-8 text files | replaced by U+FFFD; `edit` corrupts them | decoded (CP1252/latin1/UTF-16) and re-encoded on write | legacy R scripts on Windows |
| command tool | `bash` with tail truncation | `run_r` with head+tail truncation | R prints headers first, errors last |
| timeouts | hard (process kill) | soft for `run_r` (R interrupt points), hard for `shell` | in-process evaluation (REQ-22) |
| home directory `~` | OS home | `path.expand("~")` (R's notion; on Windows usually `Documents`) | `read("~/x")` and `run_r` code `read.csv("~/x")` must agree |
| parallel tool calls + mutation queue | yes | sequential in-session | R is single-threaded |

---

## 5. Verified R prototypes

Everything in this section was executed on this machine (R 4.4.3, macOS arm64) from
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-01/proto/`.
The source files are embedded verbatim below (they are ASCII-only; the scratch directory is temporary).

**Verifier changes to the embedded sources (2026-09-29):** (1) `04-run.R` `.spill_file()` originally built its random file name with `sample()`, which **advanced the user's RNG stream** on every `tool_run_r()` / `tool_shell()` call (verified: `set.seed(1); tool_run_r("x <- 1"); runif(1)` gave 0.718 instead of 0.266) — a reproducibility bug for a tool that runs inside the user's live session; it now uses `tempfile()`, which does not touch `.Random.seed` (verified). (2) Two comment lines in `00-utils.R` and one in `01-read-write.R` were corrected (the `\u`-escape claim, see E1/E2; base64 wraps at 72). After these edits the extracted files were re-run: 80/45/50 assertions pass in the C locale and 44 in `test-03.R` with optional packages blocked, unchanged from the author's counts. Implementation rule: no gptr tool may call R's RNG (`sample()`, `runif()`, …) outside the user's own code.

### 5.1 Test results

Command: `Rscript --vanilla run-tests.R test-01.R test-02.R test-03.R` with `PI_DIR` pointing at the Pi clone.

| Configuration | test-01 (read/write/edit/ls/paths) | test-02 (glob/gitignore/find/grep + rg oracle) | test-03 (run_r/shell/registry/prompt) |
|---|---|---|---|
| default environment (`LC_CTYPE=C`), all optional packages | 80 passed, 0 failed | 45 passed, 0 failed | 50 passed, 0 failed |
| `LC_ALL=en_US.UTF-8`, all optional packages | 80 passed, 0 failed | 45 passed, 0 failed | 50 passed, 0 failed |
| `GPTR_BLOCK=stringi,magick,processx,ragg` (base R + jsonlite only), C locale | 78 passed, 0 failed | 45 passed, 0 failed | 44 passed, 0 failed |

(The lower counts in the last row are the assertions that are skipped without the optional package: two NFKC cases, the `processx` variants of the shell tests.)

Observed oracle output (UTF-8 run):

```text
  ok: ORACLE: same file set as `rg --files --hidden` in a git repo 
  ok: ORACLE: parent .gitignore applies when searching a sub-directory 
  ok: file set identical to rg --files (853 files) 
   walk_files: 938 entries in 0.032s
  ok: pattern DEFAULT_MAX_BYTES: 74 matching lines identical to rg (R: 0.27s) 
  ok: pattern truncat(e|ion)Result: 26 matching lines identical to rg (R: 0.21s) 
  ok: pattern export function \w+\(: 541 matching lines identical to rg (R: 0.22s) 
  ok: pattern todo: 169 matching lines identical to rg (R: 0.20s) 
  ok: pattern a.b: 27 matching lines identical to rg (R: 0.17s) 
  ok: pattern ^import .* from "\./: 62 matching lines identical to rg (R: 0.09s) 
```

Observed `run_r` transcript excerpts (from the test run):

```text
== run_r
a
note
Warning: careful
[1] 1 2 3

Error: boom 
Error: parse failed
line 2:1: unexpected symbol
1: x <- c(1, 2
2: y
   ^ 
   NOTE single Sys.sleep(2) with timeout=0.5 -> isError=FALSE text=done elapsed=2.0s (soft timeout: not interruptible)
== shell
   resolved shell: /bin/bash -c 
   processx timeout result: begin\n\nCommand timed out after 0.5 seconds (0.5s)
   system2 timeout result: begin\n\nCommand timed out after 0.5 seconds (1.0s)
```

### 5.2 Benchmarks (single run, machine under load from parallel jobs; treat as order of magnitude)

Verifier re-run (own script, same Pi clone, `LC_ALL=en_US.UTF-8`, load average ≈ 67 on 8 cores, two runs): `walk_files` 2,125 files / 247 dirs / 27.2 MB (= 25.9 MiB) in 0.68–1.12 s; `tool_grep` 1.1–3.5 s vs `rg` full scan 0.12–0.38 s; `tool_find("**/*.test.ts")` 0.29–0.33 s, 679 results. File/dir/result counts reproduce exactly; the absolute times below could not be reproduced under this load and are UNCERTAIN.

```text
walk_files(pi monorepo): 2125 files, 247 dirs, 25.9 MB, 0.158s
list.files(recursive=TRUE, incl .git): 2154 files, 0.018s
tool_grep(DEFAULT_MAX_BYTES, limit=100): 0.540s; first line: packages/agent/docs/mobile-handoff/01-harness/03-execenv/ba
   rg (full scan, no limit): 0.041s
tool_grep(function \w+\(, limit=100): 0.142s; first line: .github/workflows/approve-contributor.yml:63:             func
   rg (full scan, no limit): 0.059s
tool_grep(zzz_not_present_zzz, limit=100): 0.426s; first line: No matches found
   rg (full scan, no limit): 0.056s
tool_find(**/*.test.ts): 0.084s, 679 results
big file: 5.1MB
tool_edit(2 edits, 200k lines): 1.436s; diff lines: 23
tool_read(offset=150000, limit=50): 0.106s
tool_grep(single 5MB file): 0.092s
```

Stage profile of `grep` over the Pi monorepo (2,125 files, 25.9 MB), which motivated the batch pre-filter: `readBin` 0.14 s; NUL sniff of 8000 bytes 0.06 s (full scan 0.17 s); `decode_text` 0.16 s; whole-file vectorised `grepl` 0.023 s; splitting *all* files into lines 0.43 s (avoided by the pre-filter); per-line `grepl` on pre-filtered files 0.025 s.

Stage profile of `edit` on a 5.1 MB / 200,000-line file with two edits: fuzzy normalisation of the whole file 0.61 s (needed for Pi-compatible uniqueness counting), diff tokens + Myers 0.54 s, display diff 0.32 s, unified patch 0.03 s.

### 5.3 Source: `00-utils.R` (constants, encoding, truncation, paths, results)

````r
# gptr tool layer prototype -- utilities (pure base R; ASCII-only source)
# Track 01 prototype. Port of pi: truncate.ts, path-utils.ts, utils/paths.ts

GPTR_MAX_LINES <- 2000L            # pi DEFAULT_MAX_LINES
GPTR_MAX_BYTES <- 50L * 1024L      # pi DEFAULT_MAX_BYTES (50KB)
GPTR_GREP_MAX_LINE_LENGTH <- 500L  # pi GREP_MAX_LINE_LENGTH

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- UTF-8 helpers ---------------------------------------------------------
# Build non-ASCII constants with intToUtf8() (or "\u" escapes, which are also marked UTF-8;
# verifier-corrected comment: raw non-ASCII bytes in source are what is NOT reliably marked).
u_chr <- function(...) intToUtf8(c(...))
# Unmarked strings that are valid UTF-8 are taken to BE UTF-8 (enc2utf8() would
# re-encode them from the native encoding and mangle them in C / CP125x locales).
as_utf8 <- function(x) {
  x <- as.character(x)
  unk <- Encoding(x) == "unknown"
  if (any(unk)) {
    valid <- validUTF8(x)
    conv <- unk & !valid
    if (any(conv)) x[conv] <- enc2utf8(x[conv])
  }
  lat <- Encoding(x) == "latin1"
  if (any(lat)) x[lat] <- enc2utf8(x[lat])
  Encoding(x) <- "UTF-8"
  x
}
mark_utf8 <- function(x) { Encoding(x) <- "UTF-8"; x }
byte_len <- function(x) nchar(x, type = "bytes", allowNA = FALSE)

# Path handed to OS-level functions. On non-UTF-8 Unix locales a UTF-8 *marked*
# non-ASCII path fails with "unable to translate ... to native encoding";
# unmarked bytes are passed through untouched.
os_path <- function(p) {
  if (.Platform$OS.type != "windows" && !isTRUE(l10n_info()[["UTF-8"]])) Encoding(p) <- "unknown"
  p
}

# Decode raw bytes to one UTF-8 string, remembering how to encode it back.
# UTF-8 BOM is kept inside the text (like pi); UTF-16 BOMs are decoded; invalid
# UTF-8 is assumed to be CP1252 (latin1 as a last resort, which maps every byte).
decode_text <- function(bytes) {
  n <- length(bytes)
  if (n == 0L) return(list(text = mark_utf8(""), encoding = "UTF-8"))
  if (has_utf16_bom(bytes)) {
    from <- if (bytes[1] == 0xff) "UTF-16LE" else "UTF-16BE"
    out <- iconv(list(bytes[-(1:2)]), from = from, to = "UTF-8")
    if (!is.na(out)) return(list(text = mark_utf8(out), encoding = from))
  }
  txt <- tryCatch(rawToChar(bytes), error = function(e) rawToChar(bytes[bytes != as.raw(0L)]))   # R strings cannot hold NUL
  if (validUTF8(txt)) return(list(text = mark_utf8(txt), encoding = "UTF-8"))
  for (enc in c("CP1252", "latin1")) {
    out <- suppressWarnings(iconv(txt, from = enc, to = "UTF-8"))
    if (!is.na(out)) return(list(text = mark_utf8(out), encoding = enc))
  }
  list(text = mark_utf8(iconv(txt, from = "latin1", to = "UTF-8", sub = "?")), encoding = "latin1")
}
bytes_to_text <- function(bytes) decode_text(bytes)$text

encode_text <- function(text, encoding = "UTF-8") {
  text <- as_utf8(text)
  if (identical(encoding, "UTF-8")) return(charToRaw(text))
  out <- iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1L]]
  if (is.null(out)) stop(sprintf("Text contains characters that cannot be represented in the file's encoding (%s).", encoding), call. = FALSE)
  if (encoding == "UTF-16LE") out <- c(as.raw(c(0xff, 0xfe)), out)
  if (encoding == "UTF-16BE") out <- c(as.raw(c(0xfe, 0xff)), out)
  out
}

has_utf16_bom <- function(bytes) {
  length(bytes) >= 2L && ((bytes[1] == 0xff && bytes[2] == 0xfe) || (bytes[1] == 0xfe && bytes[2] == 0xff))
}
# NUL byte in the first 8000 bytes (git's heuristic; ripgrep: any NUL byte). UTF-16 with BOM is text.
is_binary_bytes <- function(bytes, sniff = 8000L) {
  if (has_utf16_bom(bytes)) return(FALSE)
  n <- min(length(bytes), sniff)
  n > 0L && any(bytes[seq_len(n)] == as.raw(0L))
}

read_file_bytes <- function(path) {
  p <- os_path(path)
  size <- file.size(p)
  if (is.na(size)) stop(sprintf("ENOENT: no such file or directory, open '%s'", path), call. = FALSE)
  if (dir.exists(p)) stop(sprintf("EISDIR: illegal operation on a directory, read '%s'", path), call. = FALSE)
  con <- file(p, "rb"); on.exit(close(con))
  readBin(con, what = "raw", n = size + 16L)
}

write_file_text <- function(path, text, encoding = "UTF-8") {
  p <- os_path(path)
  bytes <- encode_text(text, encoding)          # encode first: a failure must not truncate the file
  con <- file(p, "wb"); on.exit(close(con))
  writeBin(bytes, con)
  invisible(TRUE)
}

# ---- line splitting --------------------------------------------------------
# JavaScript "x".split("\n") semantics (keeps a trailing empty piece).
split_lines_js <- function(x) {
  out <- strsplit(paste0(x, "\n"), "\n", fixed = TRUE)[[1L]]
  if (length(out) == 0L) out <- ""
  mark_utf8(out)
}
# pi splitLinesForCounting(): "" -> 0 lines; one trailing "\n" is not an extra line.
split_lines_count <- function(x) {
  if (!nzchar(x)) return(character())
  out <- strsplit(x, "\n", fixed = TRUE)[[1L]]
  # strsplit drops exactly one trailing empty piece, same as pi's pop()
  mark_utf8(out)
}

format_size <- function(bytes) {
  if (bytes < 1024) sprintf("%dB", as.integer(bytes))
  else if (bytes < 1024 * 1024) sprintf("%.1fKB", bytes / 1024)
  else sprintf("%.1fMB", bytes / (1024 * 1024))
}

# ---- truncation ------------------------------------------------------------
truncation_result <- function(content, truncated, truncated_by, total_lines, total_bytes,
                              output_lines, output_bytes, last_line_partial = FALSE,
                              first_line_exceeds_limit = FALSE, max_lines, max_bytes) {
  list(content = content, truncated = truncated, truncatedBy = truncated_by,
       totalLines = total_lines, totalBytes = total_bytes, outputLines = output_lines,
       outputBytes = output_bytes, lastLinePartial = last_line_partial,
       firstLineExceedsLimit = first_line_exceeds_limit, maxLines = max_lines, maxBytes = max_bytes)
}

# Keep the first lines (file reads, search results). Never returns partial lines.
truncate_head <- function(content, max_lines = GPTR_MAX_LINES, max_bytes = GPTR_MAX_BYTES) {
  total_bytes <- byte_len(content)
  lines <- split_lines_count(content)
  total_lines <- length(lines)
  if (total_lines <= max_lines && total_bytes <= max_bytes) {
    return(truncation_result(content, FALSE, NULL, total_lines, total_bytes, total_lines, total_bytes,
                             max_lines = max_lines, max_bytes = max_bytes))
  }
  lb <- byte_len(lines)
  if (lb[1L] > max_bytes) {
    return(truncation_result("", TRUE, "bytes", total_lines, total_bytes, 0L, 0L,
                             first_line_exceeds_limit = TRUE, max_lines = max_lines, max_bytes = max_bytes))
  }
  k <- min(total_lines, max_lines)
  cum <- cumsum(as.numeric(lb[seq_len(k)]) + c(0, rep(1, k - 1L)))   # +1 per newline
  fit <- sum(cum <= max_bytes)
  by <- if (fit < k) "bytes" else "lines"
  out <- paste(lines[seq_len(fit)], collapse = "\n")
  truncation_result(out, TRUE, by, total_lines, total_bytes, fit, byte_len(out),
                    max_lines = max_lines, max_bytes = max_bytes)
}

# Cut a UTF-8 string to its last `max_bytes` bytes on a character boundary.
utf8_tail_bytes <- function(x, max_bytes) {
  b <- charToRaw(x)
  if (length(b) <= max_bytes) return(x)
  start <- length(b) - max_bytes + 1L
  while (start <= length(b) && bitwAnd(as.integer(b[start]), 0xC0L) == 0x80L) start <- start + 1L
  if (start > length(b)) return(mark_utf8(""))
  mark_utf8(rawToChar(b[start:length(b)]))
}

# Keep the last lines (command / R output: errors are at the end).
truncate_tail <- function(content, max_lines = GPTR_MAX_LINES, max_bytes = GPTR_MAX_BYTES) {
  total_bytes <- byte_len(content)
  lines <- split_lines_count(content)
  total_lines <- length(lines)
  if (total_lines <= max_lines && total_bytes <= max_bytes) {
    return(truncation_result(content, FALSE, NULL, total_lines, total_bytes, total_lines, total_bytes,
                             max_lines = max_lines, max_bytes = max_bytes))
  }
  k <- min(total_lines, max_lines)
  tail_lines <- rev(lines)[seq_len(k)]                 # last line first
  lb <- byte_len(tail_lines)
  cum <- cumsum(as.numeric(lb) + c(0, rep(1, k - 1L)))
  fit <- sum(cum <= max_bytes)
  partial <- FALSE
  if (fit == 0L) {                                     # last line alone exceeds the byte limit
    out_lines <- utf8_tail_bytes(tail_lines[1L], max_bytes)
    partial <- TRUE; by <- "bytes"
  } else {
    out_lines <- rev(tail_lines[seq_len(fit)])
    by <- if (fit < k) "bytes" else "lines"
  }
  out <- paste(out_lines, collapse = "\n")
  truncation_result(out, TRUE, by, total_lines, total_bytes, length(out_lines), byte_len(out),
                    last_line_partial = partial, max_lines = max_lines, max_bytes = max_bytes)
}

truncate_line <- function(line, max_chars = GPTR_GREP_MAX_LINE_LENGTH) {
  n <- nchar(line, type = "chars", allowNA = TRUE)
  if (is.na(n) || n <= max_chars) return(list(text = line, wasTruncated = FALSE))
  list(text = paste0(substr(line, 1L, max_chars), "... [truncated]"), wasTruncated = TRUE)
}

# ---- paths -----------------------------------------------------------------
.unicode_spaces <- function() c(0xA0L, 0x2000L:0x200AL, 0x202FL, 0x205FL, 0x3000L)

normalize_unicode_spaces <- function(x) {
  x <- as_utf8(x)
  cp <- utf8ToInt(x)
  if (length(cp) == 0L || anyNA(cp)) return(x)
  hit <- cp %in% .unicode_spaces()
  if (any(hit)) { cp[hit] <- 32L; x <- intToUtf8(cp) }
  x
}

is_windows <- function() .Platform$OS.type == "windows"

is_absolute_path <- function(p) {
  grepl("^/", p) || grepl("^[A-Za-z]:[/\\\\]", p) || grepl("^[/\\\\]{2}", p)
}

# "/c/Users/x", "/mnt/c/x", "/cygdrive/c/x" -> "C:/x" (Windows only)
normalize_windows_shell_path <- function(p) {
  if (!startsWith(p, "/") || startsWith(p, "//") || grepl("\\", p, fixed = TRUE)) return(p)
  m <- regmatches(p, regexec("^/(?:mnt/|cygdrive/)?([A-Za-z])(?:/(.*))?$", p, perl = TRUE))[[1L]]
  if (length(m) == 0L) return(p)
  paste0(toupper(m[2L]), ":/", m[3L])
}

# Lexical normalisation (no filesystem access), like node's path.resolve().
path_norm_lexical <- function(p) {
  p <- gsub("\\", "/", p, fixed = TRUE)
  prefix <- ""
  if (grepl("^[A-Za-z]:/", p)) { prefix <- substr(p, 1L, 3L); p <- substring(p, 4L) }
  else if (startsWith(p, "//")) { prefix <- "//"; p <- substring(p, 3L) }
  else if (startsWith(p, "/")) { prefix <- "/"; p <- substring(p, 2L) }
  segs <- strsplit(p, "/", fixed = TRUE)[[1L]]
  out <- character()
  for (s in segs) {
    if (s == "" || s == ".") next
    if (s == "..") { if (length(out)) out <- out[-length(out)]; next }
    out <- c(out, s)
  }
  res <- paste0(prefix, paste(out, collapse = "/"))
  if (!nzchar(res)) res <- "."
  mark_utf8(res)
}

normalize_tool_path <- function(p, strip_at = TRUE, home = path.expand("~")) {
  p <- normalize_unicode_spaces(p)
  if (strip_at && startsWith(p, "@")) p <- substring(p, 2L)
  if (is_windows()) p <- normalize_windows_shell_path(p)
  if (identical(p, "~")) return(as_utf8(home))
  if (startsWith(p, "~/") || (is_windows() && startsWith(p, "~\\"))) return(as_utf8(file.path(home, substring(p, 3L))))
  if (grepl("^file://", p)) {
    p <- utils::URLdecode(sub("^file://(localhost)?", "", p))
    if (is_windows()) p <- sub("^/([A-Za-z]:)", "\\1", p)
  }
  as_utf8(p)
}

resolve_to_cwd <- function(path, cwd = getwd()) {
  p <- normalize_tool_path(path)
  if (is_absolute_path(p)) path_norm_lexical(p) else path_norm_lexical(paste0(as_utf8(cwd), "/", p))
}

# read-only fallback variants for macOS screenshot names (pi resolveReadPath)
resolve_read_path <- function(path, cwd = getwd()) {
  resolved <- resolve_to_cwd(path, cwd)
  exists_ <- function(p) file.exists(os_path(p))
  if (exists_(resolved)) return(resolved)
  nnbsp <- u_chr(0x202F); rsquo <- u_chr(0x2019)
  am_pm <- gsub(" (AM|PM)\\.", paste0(nnbsp, "\\1."), resolved, ignore.case = TRUE, perl = TRUE)
  nfd <- if (requireNamespace("stringi", quietly = TRUE)) stringi::stri_trans_nfd(resolved) else resolved
  curly <- gsub("'", rsquo, resolved, fixed = TRUE)
  nfd_curly <- gsub("'", rsquo, nfd, fixed = TRUE)
  for (v in unique(c(am_pm, nfd, curly, nfd_curly))) {
    v <- mark_utf8(v)
    if (!identical(v, resolved) && exists_(v)) return(v)
  }
  resolved
}

# ---- results ---------------------------------------------------------------
text_block <- function(text) list(type = "text", text = text)
image_block <- function(data, mime_type) list(type = "image", data = data, mimeType = mime_type)
tool_result <- function(content, details = NULL, is_error = FALSE) {
  if (is.character(content)) content <- list(text_block(paste(content, collapse = "\n")))
  structure(list(content = content, details = details, isError = is_error), class = "gptr_tool_result")
}
tool_result_text <- function(res) {
  paste(vapply(Filter(function(b) identical(b$type, "text"), res$content), function(b) b$text, ""), collapse = "\n")
}
````

### 5.4 Source: `01-read-write.R` (image sniffing, read, write, ls)

````r
# gptr tool layer prototype -- read / write / ls (port of pi read.ts, write.ts, ls.ts, utils/mime.ts)

IMAGE_MAX_DIM <- 2000L                       # pi image-resize-core.ts maxWidth/maxHeight
IMAGE_MAX_B64_BYTES <- 4.5 * 1024 * 1024     # pi: 4.5MB of base64 payload
IMAGE_SNIFF_BYTES <- 4100L                   # pi IMAGE_TYPE_SNIFF_BYTES

# ---- image sniffing (magic bytes, never the file extension) -----------------
.u32be <- function(b, off) sum(as.numeric(b[off + 0:3]) * c(16777216, 65536, 256, 1))   # off is 1-based
.u32le <- function(b, off) sum(as.numeric(b[off + 0:3]) * c(1, 256, 65536, 16777216))
.u16le <- function(b, off) sum(as.numeric(b[off + 0:1]) * c(1, 256))
.u16be <- function(b, off) sum(as.numeric(b[off + 0:1]) * c(256, 1))
.starts_raw <- function(b, sig, off = 1L) length(b) >= off + length(sig) - 1L && all(b[off + seq_along(sig) - 1L] == sig)
.starts_ascii <- function(b, txt, off = 1L) .starts_raw(b, charToRaw(txt), off)

detect_image_mime <- function(b) {
  png_sig <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  if (.starts_raw(b, as.raw(c(0xff, 0xd8, 0xff)))) {
    return(if (length(b) >= 4L && b[4L] == as.raw(0xf7)) NULL else "image/jpeg")   # 0xF7 = JPEG-LS
  }
  if (.starts_raw(b, png_sig)) {
    ok <- length(b) >= 16L && .u32be(b, 9L) == 13 && .starts_ascii(b, "IHDR", 13L)
    if (!ok) return(NULL)
    off <- 9L                                        # animated PNG (acTL before IDAT) is rejected
    while (off + 7L <= length(b)) {
      len <- .u32be(b, off)
      if (.starts_ascii(b, "acTL", off + 4L)) return(NULL)
      if (.starts_ascii(b, "IDAT", off + 4L)) break
      nxt <- off + 8 + len + 4
      if (nxt <= off || nxt > length(b) + 1) break
      off <- nxt
    }
    return("image/png")
  }
  if (.starts_ascii(b, "GIF87a") || .starts_ascii(b, "GIF89a")) return("image/gif")
  if (.starts_ascii(b, "RIFF") && .starts_ascii(b, "WEBP", 9L)) return("image/webp")
  if (.starts_ascii(b, "BM") && length(b) >= 26L) {
    fsize <- .u32le(b, 3L); pix <- .u32le(b, 11L); dib <- .u32le(b, 15L)
    if (fsize != 0 && fsize < 26) return(NULL)
    if (pix < 14 + dib) return(NULL)
    if (fsize != 0 && pix >= fsize) return(NULL)
    if (dib == 12) { planes <- .u16le(b, 23L); bpp <- .u16le(b, 25L) }
    else if (dib >= 40 && dib <= 124) { if (length(b) < 30L) return(NULL); planes <- .u16le(b, 27L); bpp <- .u16le(b, 29L) }
    else return(NULL)
    if (planes == 1 && bpp %in% c(1, 4, 8, 16, 24, 32)) return("image/bmp")
  }
  NULL
}

# width/height without decoding (pure R). Returns c(w, h) or NULL.
image_dims <- function(b, mime) {
  tryCatch(switch(mime,
    "image/png" = c(.u32be(b, 17L), .u32be(b, 21L)),
    "image/gif" = c(.u16le(b, 7L), .u16le(b, 9L)),
    "image/bmp" = c(.u32le(b, 19L), abs(.u32le(b, 23L))),
    "image/jpeg" = {
      i <- 3L; n <- length(b); out <- NULL
      while (i + 9L <= n) {
        if (b[i] != as.raw(0xff)) { i <- i + 1L; next }
        m <- as.integer(b[i + 1L])
        if (m == 0xff) { i <- i + 1L; next }
        if (m %in% c(0xd8, 0x01) || (m >= 0xd0 && m <= 0xd7)) { i <- i + 2L; next }
        len <- .u16be(b, i + 2L)
        if (m >= 0xc0 && m <= 0xcf && !(m %in% c(0xc4, 0xc8, 0xcc))) { out <- c(.u16be(b, i + 7L), .u16be(b, i + 5L)); break }
        i <- i + 2L + as.integer(len)
      }
      out
    },
    NULL), error = function(e) NULL)
}

b64 <- function(bytes) gsub("[\r\n]", "", jsonlite::base64_enc(bytes))   # jsonlite wraps at 72 chars

process_image <- function(bytes, mime, auto_resize = TRUE) {
  hints <- character()
  have_magick <- requireNamespace("magick", quietly = TRUE)
  if (identical(mime, "image/bmp")) {
    if (!have_magick) return(list(ok = FALSE, message = "[Image omitted: could not be converted to a supported inline image format.]"))
    img <- magick::image_read(bytes)
    bytes <- magick::image_write(img, format = "png"); mime <- "image/png"
    hints <- c(hints, "[Image converted from image/bmp to image/png.]")
  }
  if (!auto_resize) return(list(ok = TRUE, data = b64(bytes), mimeType = mime, hints = hints))
  dims <- image_dims(bytes, mime)
  b64_size <- ceiling(length(bytes) / 3) * 4
  within <- b64_size < IMAGE_MAX_B64_BYTES && (is.null(dims) || all(dims <= IMAGE_MAX_DIM))
  if (within) return(list(ok = TRUE, data = b64(bytes), mimeType = mime, hints = hints))
  if (!have_magick) return(list(ok = FALSE, message = "[Image omitted: could not be resized below the inline image size limit.]"))
  img <- magick::image_read(bytes)
  info <- magick::image_info(img)[1L, ]
  w <- info$width; h <- info$height
  tw <- w; th <- h
  if (tw > IMAGE_MAX_DIM) { th <- round(th * IMAGE_MAX_DIM / tw); tw <- IMAGE_MAX_DIM }
  if (th > IMAGE_MAX_DIM) { tw <- round(tw * IMAGE_MAX_DIM / th); th <- IMAGE_MAX_DIM }
  repeat {
    r <- magick::image_resize(img, sprintf("%dx%d!", as.integer(tw), as.integer(th)), filter = "Lanczos")
    cands <- list(list(magick::image_write(r, format = "png"), "image/png"))
    for (q in unique(c(80, 85, 70, 55, 40))) cands <- c(cands, list(list(magick::image_write(r, format = "jpeg", quality = q), "image/jpeg")))
    for (cand in cands) {
      if (ceiling(length(cand[[1L]]) / 3) * 4 < IMAGE_MAX_B64_BYTES) {
        hints <- c(hints, sprintf("[Image: original %dx%d, displayed at %dx%d. Multiply coordinates by %.2f to map to original image.]",
                                  as.integer(w), as.integer(h), as.integer(tw), as.integer(th), w / tw))
        return(list(ok = TRUE, data = b64(cand[[1L]]), mimeType = cand[[2L]], hints = hints))
      }
    }
    if (tw == 1 && th == 1) break
    tw <- max(1, floor(tw * 0.75)); th <- max(1, floor(th * 0.75))
  }
  list(ok = FALSE, message = "[Image omitted: could not be resized below the inline image size limit.]")
}

# ---- read --------------------------------------------------------------------
tool_read <- function(path, offset = NULL, limit = NULL, cwd = getwd(), model_supports_images = TRUE,
                      auto_resize_images = TRUE) {
  abs_path <- resolve_read_path(path, cwd)
  bytes <- read_file_bytes(abs_path)
  mime <- detect_image_mime(bytes[seq_len(min(length(bytes), IMAGE_SNIFF_BYTES))])
  non_vision <- if (!model_supports_images) "[Current model does not support images. The image will be omitted from this request.]"
  if (!is.null(mime)) {
    p <- process_image(bytes, mime, auto_resize_images)
    if (!p$ok) return(tool_result(paste(c(sprintf("Read image file [%s]", mime), p$message, non_vision), collapse = "\n")))
    note <- paste(c(sprintf("Read image file [%s]", p$mimeType), p$hints, non_vision), collapse = "\n")
    return(tool_result(list(text_block(note), image_block(p$data, p$mimeType))))
  }
  if (is_binary_bytes(bytes)) {   # gptr addition: pi decodes binary as UTF-8 garbage
    ext <- tolower(tools::file_ext(abs_path))
    hint <- switch(ext, rds = "readRDS()", rdata = , rda = "load()", parquet = "arrow::read_parquet()", feather = "arrow::read_feather()",
                   xlsx = , xls = "readxl::read_excel()", qs2 = "qs2::qs_read()", pdf = "pdftools::pdf_text()", NULL)
    msg <- sprintf("[Binary file: %s (%s). Not shown as text.%s]", path, format_size(length(bytes)),
                   if (is.null(hint)) "" else sprintf(" Use the run_r tool to load it, e.g. %s.", hint))
    return(tool_result(msg, details = list(binary = TRUE, bytes = length(bytes))))
  }
  text <- bytes_to_text(bytes)
  all_lines <- split_lines_js(text)
  total <- length(all_lines)
  start <- if (!is.null(offset) && !is.na(offset) && offset != 0) max(0, as.integer(offset) - 1L) else 0L   # 0-based
  start_display <- start + 1L
  if (start >= total) stop(sprintf("Offset %s is beyond end of file (%d lines total)", format(offset), total), call. = FALSE)
  user_limited <- NULL
  if (!is.null(limit)) {
    end <- min(start + as.integer(limit), total)
    selected <- paste(all_lines[seq.int(start + 1L, length.out = max(0L, end - start))], collapse = "\n")
    user_limited <- end - start
  } else {
    selected <- paste(all_lines[seq.int(start + 1L, total)], collapse = "\n")
  }
  tr <- truncate_head(selected)
  details <- NULL
  if (tr$firstLineExceedsLimit) {
    out <- sprintf("[Line %d is %s, exceeds %s limit. Use run_r: substr(readLines(\"%s\", n = %d, warn = FALSE)[%d], 1, %d)]",
                   start_display, format_size(byte_len(all_lines[start + 1L])), format_size(GPTR_MAX_BYTES),
                   path, start_display, start_display, GPTR_MAX_BYTES)
    details <- list(truncation = tr)
  } else if (tr$truncated) {
    end_display <- start_display + tr$outputLines - 1L
    out <- if (identical(tr$truncatedBy, "lines")) {
      sprintf("%s\n\n[Showing lines %d-%d of %d. Use offset=%d to continue.]", tr$content, start_display, end_display, total, end_display + 1L)
    } else {
      sprintf("%s\n\n[Showing lines %d-%d of %d (%s limit). Use offset=%d to continue.]", tr$content, start_display, end_display, total,
              format_size(GPTR_MAX_BYTES), end_display + 1L)
    }
    details <- list(truncation = tr)
  } else if (!is.null(user_limited) && start + user_limited < total) {
    out <- sprintf("%s\n\n[%d more lines in file. Use offset=%d to continue.]", tr$content, total - (start + user_limited), start + user_limited + 1L)
  } else {
    out <- tr$content
  }
  tool_result(mark_utf8(out), details = details)
}

# ---- write -------------------------------------------------------------------
tool_write <- function(path, content, cwd = getwd()) {
  abs_path <- resolve_to_cwd(path, cwd)
  dir <- dirname(os_path(abs_path))
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(dir)) stop(sprintf("Could not create directory: %s", dir), call. = FALSE)
  write_file_text(abs_path, content)
  tool_result(sprintf("Successfully wrote to %s", path), details = list(bytes = byte_len(as_utf8(content))))
}

# ---- ls ----------------------------------------------------------------------
LS_DEFAULT_LIMIT <- 500L
tool_ls <- function(path = NULL, limit = NULL, cwd = getwd()) {
  dir_path <- resolve_to_cwd(if (is.null(path) || !nzchar(path)) "." else path, cwd)
  p <- os_path(dir_path)
  limit <- as.integer(limit %||% LS_DEFAULT_LIMIT)
  if (!file.exists(p)) stop(sprintf("Path not found: %s", dir_path), call. = FALSE)
  if (!dir.exists(p)) stop(sprintf("Not a directory: %s", dir_path), call. = FALSE)
  entries <- list.files(p, all.files = TRUE, no.. = TRUE, include.dirs = TRUE)
  if (length(entries) == 0L) return(tool_result("(empty directory)"))
  entries <- entries[order(tolower(entries), entries, method = "radix")]   # deterministic on every platform
  limit_reached <- length(entries) > limit
  shown <- utils::head(entries, limit)
  is_dir <- dir.exists(file.path(p, shown))
  out_lines <- mark_utf8(paste0(shown, ifelse(is_dir, "/", "")))
  tr <- truncate_head(paste(out_lines, collapse = "\n"), max_lines = .Machine$integer.max)
  out <- tr$content; notices <- character(); details <- list()
  if (limit_reached) { notices <- c(notices, sprintf("%d entries limit reached. Use limit=%d for more", limit, limit * 2L)); details$entryLimitReached <- limit }
  if (tr$truncated) { notices <- c(notices, sprintf("%s limit reached", format_size(GPTR_MAX_BYTES))); details$truncation <- tr }
  if (length(notices)) out <- sprintf("%s\n\n[%s]", out, paste(notices, collapse = ". "))
  tool_result(mark_utf8(out), details = if (length(details)) details)
}
````

### 5.5 Source: `02-edit.R` (edit algorithm, Myers diff, display diff, unified patch)

````r
# gptr tool layer prototype -- edit (port of pi edit.ts + edit-diff.ts), pure base R
# (stringi is used opportunistically for NFKC; without it the fuzzy fallback skips NFKC)

detect_line_ending <- function(content) {
  crlf <- regexpr("\r\n", content, fixed = TRUE, useBytes = TRUE)
  lf <- regexpr("\n", content, fixed = TRUE, useBytes = TRUE)
  if (lf == -1L || crlf == -1L) return("\n")
  if (crlf < lf) "\r\n" else "\n"
}
normalize_to_lf <- function(text) {
  text <- gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
  text <- gsub("\r", "\n", text, fixed = TRUE, useBytes = TRUE)
  mark_utf8(text)
}
restore_line_endings <- function(text, ending) {
  if (identical(ending, "\r\n")) mark_utf8(gsub("\n", "\r\n", text, fixed = TRUE, useBytes = TRUE)) else text
}
split_bom <- function(text) {
  b <- charToRaw(text)
  if (length(b) >= 3L && all(b[1:3] == as.raw(c(0xef, 0xbb, 0xbf)))) {
    list(bom = mark_utf8(rawToChar(b[1:3])), text = mark_utf8(rawToChar(b[-(1:3)])))
  } else list(bom = "", text = text)
}

# JS String.prototype.trimEnd() whitespace set
.js_ws <- function() c(9L, 11L, 12L, 13L, 32L, 0xA0L, 0x1680L, 0x2000L:0x200AL, 0x2028L, 0x2029L, 0x202FL, 0x205FL, 0x3000L, 0xFEFFL)

normalize_for_fuzzy <- function(text) {
  text <- as_utf8(text)
  if (requireNamespace("stringi", quietly = TRUE)) text <- mark_utf8(stringi::stri_trans_nfkc(text))
  lines <- split_lines_js(text)
  ws_class <- paste0("[", intToUtf8(.js_ws()), "]+$")
  lines <- mark_utf8(gsub(ws_class, "", lines, perl = TRUE))
  text <- mark_utf8(paste(lines, collapse = "\n"))
  cp <- utf8ToInt(text)
  if (length(cp) && !anyNA(cp)) {
    cp[cp %in% c(0x2018L, 0x2019L, 0x201AL, 0x201BL)] <- 39L                      # smart single quotes -> '
    cp[cp %in% c(0x201CL, 0x201DL, 0x201EL, 0x201FL)] <- 34L                      # smart double quotes -> "
    cp[cp %in% c(0x2010L:0x2015L, 0x2212L)] <- 45L                               # dashes -> -
    cp[cp %in% c(0xA0L, 0x2002L:0x200AL, 0x202FL, 0x205FL, 0x3000L)] <- 32L      # special spaces -> space
    text <- intToUtf8(cp)
  }
  mark_utf8(text)
}

.find_bytes <- function(content, needle) as.integer(regexpr(needle, content, fixed = TRUE, useBytes = TRUE))   # 1-based, -1 if absent
.count_bytes <- function(content, needle) {
  m <- gregexpr(needle, content, fixed = TRUE, useBytes = TRUE)[[1L]]
  if (m[1L] == -1L) 0L else length(m)
}

fuzzy_find_text <- function(content, old_text) {
  i <- .find_bytes(content, old_text)
  if (i != -1L) return(list(found = TRUE, index = i, matchLength = byte_len(old_text), usedFuzzyMatch = FALSE))
  fc <- normalize_for_fuzzy(content); fo <- normalize_for_fuzzy(old_text)
  if (!nzchar(fo)) return(list(found = FALSE, index = -1L, matchLength = 0L, usedFuzzyMatch = FALSE))
  i <- .find_bytes(fc, fo)
  if (i == -1L) return(list(found = FALSE, index = -1L, matchLength = 0L, usedFuzzyMatch = FALSE))
  list(found = TRUE, index = i, matchLength = byte_len(fo), usedFuzzyMatch = TRUE)
}

# replacements: list of list(matchIndex (1-based byte), matchLength, newText); must be sorted + disjoint
.apply_replacements <- function(content, reps, offset = 0L) {
  b <- charToRaw(content)
  pieces <- vector("list", 2L * length(reps) + 1L)
  pos <- 1L; k <- 0L
  for (r in reps) {
    s <- r$matchIndex - offset
    k <- k + 1L; pieces[[k]] <- if (s > pos) b[pos:(s - 1L)] else raw()
    k <- k + 1L; pieces[[k]] <- charToRaw(r$newText)
    pos <- s + r$matchLength
  }
  k <- k + 1L; pieces[[k]] <- if (pos <= length(b)) b[pos:length(b)] else raw()
  mark_utf8(rawToChar(do.call(c, pieces)))
}

# lines *with* their "\n" terminator; no phantom empty last line
.split_with_endings <- function(content) {
  if (!nzchar(content)) return(character())
  l <- split_lines_js(content)
  n <- length(l)
  if (l[n] == "") { l <- l[-n]; mark_utf8(paste0(l, "\n")) }
  else mark_utf8(c(if (n > 1L) paste0(l[-n], "\n"), l[n]))
}

.apply_preserving_unchanged_lines <- function(original, base, reps) {
  orig_lines <- .split_with_endings(original)
  base_lines <- .split_with_endings(base)
  if (length(orig_lines) != length(base_lines))
    stop("Cannot preserve unchanged lines because the base content has a different line count.", call. = FALSE)
  len <- byte_len(base_lines)
  ends <- cumsum(len)                 # exclusive end (0-based) == inclusive end (1-based)
  starts <- ends - len + 1L           # 1-based inclusive start
  groups <- list()
  for (r in reps) {
    s <- r$matchIndex; e <- r$matchIndex + r$matchLength - 1L      # inclusive byte range
    sl <- which(s >= starts & s <= ends)[1L]
    el <- which(ends >= e)[1L]
    if (is.na(sl) || is.na(el)) stop("Replacement range is outside the base content.", call. = FALSE)
    g <- length(groups)
    if (g > 0L && sl <= groups[[g]]$end) {
      groups[[g]]$end <- max(groups[[g]]$end, el); groups[[g]]$reps <- c(groups[[g]]$reps, list(r))
    } else groups[[g + 1L]] <- list(start = sl, end = el, reps = list(r))
  }
  out <- character(); idx <- 1L
  for (g in groups) {
    if (g$start > idx) out <- c(out, orig_lines[idx:(g$start - 1L)])
    chunk <- mark_utf8(paste(base_lines[g$start:g$end], collapse = ""))
    out <- c(out, .apply_replacements(chunk, g$reps, offset = starts[g$start] - 1L))
    idx <- g$end + 1L
  }
  if (idx <= length(orig_lines)) out <- c(out, orig_lines[idx:length(orig_lines)])
  mark_utf8(paste(out, collapse = ""))
}

apply_edits_to_normalized_content <- function(normalized_content, edits, path) {
  n <- length(edits)
  edits <- lapply(edits, function(e) list(oldText = normalize_to_lf(as_utf8(e$oldText)), newText = normalize_to_lf(as_utf8(e$newText))))
  for (i in seq_len(n)) if (!nzchar(edits[[i]]$oldText)) {
    stop(if (n == 1L) sprintf("oldText must not be empty in %s.", path)
         else sprintf("edits[%d].oldText must not be empty in %s.", i - 1L, path), call. = FALSE)
  }
  initial <- lapply(edits, function(e) fuzzy_find_text(normalized_content, e$oldText))
  used_fuzzy <- any(vapply(initial, function(m) isTRUE(m$usedFuzzyMatch), logical(1)))
  base <- if (used_fuzzy) normalize_for_fuzzy(normalized_content) else normalized_content
  base_fuzzy <- NULL
  matched <- vector("list", n)
  for (i in seq_len(n)) {
    e <- edits[[i]]
    m <- fuzzy_find_text(base, e$oldText)
    if (!m$found) {
      stop(if (n == 1L) sprintf("Could not find the exact text in %s. The old text must match exactly including all whitespace and newlines.", path)
           else sprintf("Could not find edits[%d] in %s. The oldText must match exactly including all whitespace and newlines.", i - 1L, path), call. = FALSE)
    }
    if (is.null(base_fuzzy)) base_fuzzy <- normalize_for_fuzzy(base)       # pi counts occurrences in fuzzy space, always
    occ <- .count_bytes(base_fuzzy, normalize_for_fuzzy(e$oldText))
    if (occ > 1L) {
      stop(if (n == 1L) sprintf("Found %d occurrences of the text in %s. The text must be unique. Please provide more context to make it unique.", occ, path)
           else sprintf("Found %d occurrences of edits[%d] in %s. Each oldText must be unique. Please provide more context to make it unique.", occ, i - 1L, path), call. = FALSE)
    }
    matched[[i]] <- list(editIndex = i - 1L, matchIndex = m$index, matchLength = m$matchLength, newText = e$newText)
  }
  matched <- matched[order(vapply(matched, function(m) m$matchIndex, integer(1)))]
  if (n > 1L) for (i in 2:n) {
    p <- matched[[i - 1L]]; cur <- matched[[i]]
    if (p$matchIndex + p$matchLength > cur$matchIndex)
      stop(sprintf("edits[%d] and edits[%d] overlap in %s. Merge them into one edit or target disjoint regions.", p$editIndex, cur$editIndex, path), call. = FALSE)
  }
  new_content <- if (used_fuzzy) .apply_preserving_unchanged_lines(normalized_content, base, matched) else .apply_replacements(base, matched)
  if (identical(charToRaw(normalized_content), charToRaw(new_content))) {
    stop(if (n == 1L) sprintf("No changes made to %s. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.", path)
         else sprintf("No changes made to %s. The replacements produced identical content.", path), call. = FALSE)
  }
  list(baseContent = normalized_content, newContent = new_content, usedFuzzyMatch = used_fuzzy)
}

# ---- line diff (Myers O(ND), pure R) ---------------------------------------
# returns data.frame(op = "=", "-", "+"; a = index in old or NA; b = index in new or NA)
diff_ops <- function(a, b, max_d = 4000L) {
  n <- length(a); m <- length(b)
  pre <- 0L
  while (pre < n && pre < m && a[pre + 1L] == b[pre + 1L]) pre <- pre + 1L
  suf <- 0L
  while (suf < n - pre && suf < m - pre && a[n - suf] == b[m - suf]) suf <- suf + 1L
  a2 <- if (n - pre - suf > 0L) a[(pre + 1L):(n - suf)] else a[0]
  b2 <- if (m - pre - suf > 0L) b[(pre + 1L):(m - suf)] else b[0]
  N <- length(a2); M <- length(b2)
  ops <- character(); ia <- integer(); ib <- integer()
  if (N == 0L || M == 0L) {
    ops <- c(rep("-", N), rep("+", M)); ia <- c(seq_len(N), rep(NA_integer_, M)); ib <- c(rep(NA_integer_, N), seq_len(M))
  } else {
    lim <- min(N + M, max_d); off <- lim + 2L
    v <- integer(2L * lim + 4L); trace <- vector("list", lim + 1L); found <- -1L
    for (d in 0:lim) {
      trace[[d + 1L]] <- v
      for (k in seq.int(-d, d, by = 2L)) {
        if (k == -d || (k != d && v[off + k - 1L] < v[off + k + 1L])) x <- v[off + k + 1L] else x <- v[off + k - 1L] + 1L
        y <- x - k
        while (x < N && y < M && a2[x + 1L] == b2[y + 1L]) { x <- x + 1L; y <- y + 1L }
        v[off + k] <- x
        if (x >= N && y >= M) { found <- d; break }
      }
      if (found >= 0L) break
    }
    if (found < 0L) {            # too different: treat the whole middle as replaced
      ops <- c(rep("-", N), rep("+", M)); ia <- c(seq_len(N), rep(NA_integer_, M)); ib <- c(rep(NA_integer_, N), seq_len(M))
    } else {
      # backtrack; whole snakes are emitted as one chunk (never grow vectors element by element)
      x <- N; y <- M; k_ <- 0L
      ro <- vector("list", 2L * found + 2L); ra <- ro; rb <- ro
      for (d in found:0) {
        vv <- trace[[d + 1L]]; k <- x - y
        if (k == -d || (k != d && vv[off + k - 1L] < vv[off + k + 1L])) pk <- k + 1L else pk <- k - 1L
        px <- vv[off + pk]; py <- px - pk
        if (d == 0L) { px <- 0L; py <- 0L }
        s <- min(x - px, y - py)
        if (s > 0L) {
          k_ <- k_ + 1L; ro[[k_]] <- rep("=", s); ra[[k_]] <- seq.int(x, by = -1L, length.out = s); rb[[k_]] <- seq.int(y, by = -1L, length.out = s)
          x <- x - s; y <- y - s
        }
        if (d > 0L) {
          k_ <- k_ + 1L
          if (x == px) { ro[[k_]] <- "+"; ra[[k_]] <- NA_integer_; rb[[k_]] <- y; y <- y - 1L }
          else { ro[[k_]] <- "-"; ra[[k_]] <- x; rb[[k_]] <- NA_integer_; x <- x - 1L }
        }
      }
      ro <- unlist(ro[seq_len(k_)]); ra <- unlist(ra[seq_len(k_)]); rb <- unlist(rb[seq_len(k_)])
      ops <- rev(ro); ia <- rev(ra); ib <- rev(rb)
    }
  }
  ops <- c(rep("=", pre), ops, rep("=", suf))
  ia <- c(seq_len(pre), ia + pre, if (suf) (n - suf + 1L):n)
  ib <- c(seq_len(pre), ib + pre, if (suf) (m - suf + 1L):m)
  # inside every change block: removals first, then additions (jsdiff order)
  if (length(ops) > 1L) {
    blk <- cumsum(c(TRUE, (ops[-1L] == "=") != (ops[-length(ops)] == "=")))
    ord <- order(blk, match(ops, c("=", "-", "+")), seq_along(ops))
    ops <- ops[ord]; ia <- ia[ord]; ib <- ib[ord]
  }
  data.frame(op = ops, a = ia, b = ib, stringsAsFactors = FALSE)
}

.diff_tokens <- function(old, new) {
  ol <- .split_with_endings(old); nl <- .split_with_endings(new)
  ids <- match(c(ol, nl), unique(c(ol, nl)))
  list(old = ol, new = nl, ops = diff_ops(ids[seq_along(ol)], ids[length(ol) + seq_along(nl)]))
}

# Display diff: "+NN text" / "-NN text" / " NN text" with `context` lines, " NN ..." for skipped runs.
generate_diff_string <- function(old, new, context = 4L, tokens = .diff_tokens(old, new)) {
  ops <- tokens$ops
  strip <- function(x) sub("\n$", "", x)
  width <- nchar(as.character(max(length(split_lines_js(old)), length(split_lines_js(new)))))
  num <- function(i) formatC(i, width = width)
  blank <- strrep(" ", width)
  out <- character(); first_changed <- NULL
  if (!nrow(ops)) return(list(diff = "", firstChangedLine = NULL))
  r <- rle(ops$op); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  old_no <- 1L; new_no <- 1L
  for (i in seq_along(r$values)) {
    idx <- starts[i]:ends[i]; type <- r$values[i]
    if (type == "+") {
      if (is.null(first_changed)) first_changed <- new_no
      out <- c(out, paste0("+", num(new_no + seq_along(idx) - 1L), " ", strip(tokens$new[ops$b[idx]]))); new_no <- new_no + length(idx)
    } else if (type == "-") {
      if (is.null(first_changed)) first_changed <- new_no
      out <- c(out, paste0("-", num(old_no + seq_along(idx) - 1L), " ", strip(tokens$old[ops$a[idx]]))); old_no <- old_no + length(idx)
    } else {
      raw <- strip(tokens$old[ops$a[idx]]); L <- length(raw)
      lead <- i > 1L; trail <- i < length(r$values)
      show <- function(lines, from) paste0(" ", num(from + seq_along(lines) - 1L), " ", lines)
      if (lead && trail) {
        if (L <= context * 2L) out <- c(out, show(raw, old_no))
        else out <- c(out, show(raw[seq_len(context)], old_no), paste0(" ", blank, " ..."), show(raw[(L - context + 1L):L], old_no + L - context))
      } else if (lead) {
        out <- c(out, show(utils::head(raw, context), old_no)); if (L > context) out <- c(out, paste0(" ", blank, " ..."))
      } else if (trail) {
        skip <- max(0L, L - context); if (skip > 0L) out <- c(out, paste0(" ", blank, " ..."))
        out <- c(out, show(raw[(skip + 1L):L], old_no + skip))
      }
      old_no <- old_no + L; new_no <- new_no + L
    }
  }
  list(diff = mark_utf8(paste(out, collapse = "\n")), firstChangedLine = first_changed)
}

# Standard unified patch ("--- path" / "+++ path" / "@@ -a,b +c,d @@"), applicable with patch(1).
generate_unified_patch <- function(path, old, new, context = 4L, tokens = .diff_tokens(old, new)) {
  ops <- tokens$ops; n <- nrow(ops)
  header <- c(paste0("--- ", path), paste0("+++ ", path))
  chg <- which(ops$op != "=")
  if (!length(chg)) return(paste0(paste(header, collapse = "\n"), "\n"))
  keep <- rep(FALSE, n)
  for (i in chg) keep[max(1L, i - context):min(n, i + context)] <- TRUE
  runs <- rle(keep); ends <- cumsum(runs$lengths); starts <- ends - runs$lengths + 1L
  old_pos <- cumsum(ops$op != "+"); new_pos <- cumsum(ops$op != "-")     # lines consumed up to and including row i
  out <- header
  for (h in which(runs$values)) {
    idx <- starts[h]:ends[h]
    o_cnt <- sum(ops$op[idx] != "+"); n_cnt <- sum(ops$op[idx] != "-")
    o_start <- (if (starts[h] > 1L) old_pos[starts[h] - 1L] else 0L) + (o_cnt > 0L)
    n_start <- (if (starts[h] > 1L) new_pos[starts[h] - 1L] else 0L) + (n_cnt > 0L)
    out <- c(out, sprintf("@@ -%d,%d +%d,%d @@", o_start, o_cnt, n_start, n_cnt))
    for (i in idx) {
      line <- if (ops$op[i] == "+") tokens$new[ops$b[i]] else tokens$old[ops$a[i]]
      sign <- switch(ops$op[i], "=" = " ", "-" = "-", "+" = "+")
      has_nl <- endsWith(line, "\n")
      out <- c(out, paste0(sign, sub("\n$", "", line)))
      if (!has_nl) out <- c(out, "\\ No newline at end of file")
    }
  }
  mark_utf8(paste0(paste(out, collapse = "\n"), "\n"))
}

# ---- argument shim (pi prepareEditArguments) ---------------------------------
is_single_edit <- function(x) is.list(x) && !is.null(names(x)) && is.character(x$oldText) && is.character(x$newText)
prepare_edit_arguments <- function(args) {
  if (!is.list(args)) return(args)
  if (is.character(args$edits) && length(args$edits) == 1L) {
    parsed <- tryCatch(jsonlite::fromJSON(args$edits, simplifyVector = FALSE), error = function(e) NULL)
    if (is_single_edit(parsed)) args$edits <- list(parsed)
    else if (is.list(parsed) && is.null(names(parsed))) args$edits <- parsed
  } else if (is_single_edit(args$edits)) args$edits <- list(args$edits)
  if (is.character(args$oldText) && is.character(args$newText)) {
    edits <- if (is.list(args$edits)) args$edits else list()
    args$edits <- c(edits, list(list(oldText = args$oldText, newText = args$newText)))
    args$oldText <- NULL; args$newText <- NULL
  }
  args
}

# ---- edit ----------------------------------------------------------------------
tool_edit <- function(path, edits, cwd = getwd(), dry_run = FALSE) {
  if (!is.list(edits) || length(edits) == 0L)
    stop("Edit tool input is invalid. edits must contain at least one replacement.", call. = FALSE)
  abs_path <- resolve_to_cwd(path, cwd); p <- os_path(abs_path)
  code <- if (!file.exists(p)) "ENOENT" else if (dir.exists(p)) "EISDIR"
          else if (file.access(p, 4L) != 0L || file.access(p, 2L) != 0L) "EACCES" else NULL
  if (!is.null(code)) stop(sprintf("Could not edit file: %s. Error code: %s.", path, code), call. = FALSE)
  bytes <- read_file_bytes(abs_path)
  if (is_binary_bytes(bytes, sniff = length(bytes)))
    stop(sprintf("Could not edit file: %s. File is binary.", path), call. = FALSE)
  dec <- decode_text(bytes)                     # pi assumes UTF-8; gptr round-trips CP1252/latin1/UTF-16 too
  sb <- split_bom(dec$text)
  ending <- detect_line_ending(sb$text)
  normalized <- normalize_to_lf(sb$text)
  res <- apply_edits_to_normalized_content(normalized, edits, path)       # throws before anything is written
  final <- paste0(sb$bom, restore_line_endings(res$newContent, ending))
  if (!dry_run) write_file_text(abs_path, final, dec$encoding)
  tokens <- .diff_tokens(res$baseContent, res$newContent)
  d <- generate_diff_string(res$baseContent, res$newContent, tokens = tokens)
  tool_result(sprintf("Successfully replaced %d block(s) in %s.", length(edits), path),
              details = list(diff = d$diff, patch = generate_unified_patch(path, res$baseContent, res$newContent, tokens = tokens),
                             firstChangedLine = d$firstChangedLine, usedFuzzyMatch = res$usedFuzzyMatch))
}
````

### 5.6 Source: `03-search.R` (glob, gitignore, walker, find, grep)

````r
# gptr tool layer prototype -- file walker, gitignore, glob, grep, find (pure base R)
# pi shells out to ripgrep (grep) and fd (find); gptr re-implements both in R (REQ-07, REQ-08).

GREP_DEFAULT_LIMIT <- 100L      # pi grep DEFAULT_LIMIT
FIND_DEFAULT_LIMIT <- 1000L     # pi find DEFAULT_LIMIT
GREP_MAX_FILE_BYTES <- 10 * 1024 * 1024   # gptr addition: do not slurp huge data files
# Always-ignored directories (gptr addition; pi's SDK glob fallback ignores node_modules and .git only)
DEFAULT_IGNORE <- c(".git/", ".Rproj.user/", "renv/library/", "renv/staging/", "renv/sandbox/", "packrat/lib*/",
                    "node_modules/", "__pycache__/", ".venv/")

# ---- glob -> PCRE ------------------------------------------------------------
# `*` and `?` never cross "/" ; `**/`, `/**/`, `/**` cross directories; [abc] [!abc] classes;
# {a,b} alternation (when braces = TRUE); backslash escapes the next character.
glob_to_regex <- function(glob, braces = TRUE) {
  ch <- strsplit(as_utf8(glob), "", fixed = TRUE)[[1L]]
  n <- length(ch); i <- 1L; out <- character(); depth <- 0L
  esc <- function(c) if (grepl("^[][\\\\.^$|?*+(){}/-]$", c)) paste0("\\", c) else c
  while (i <= n) {
    c <- ch[i]
    if (c == "\\" && i < n) { out <- c(out, esc(ch[i + 1L])); i <- i + 2L; next }
    if (c == "*") {
      j <- i; while (j < n && ch[j + 1L] == "*") j <- j + 1L
      stars <- j - i + 1L
      at_start <- i == 1L || ch[i - 1L] == "/"
      at_end <- j == n || ch[j + 1L] == "/"
      if (stars >= 2L && at_start && at_end) {
        if (j < n) { out <- c(out, "(?:.*/)?"); i <- j + 2L }      # "**/"  (also the middle of "/**/")
        else { out <- c(out, ".*"); i <- j + 1L }                   # trailing "/**" or lone "**"
      } else { out <- c(out, "[^/]*"); i <- j + 1L }
      next
    }
    if (c == "?") { out <- c(out, "[^/]"); i <- i + 1L; next }
    if (c == "[") {
      j <- i + 1L
      if (j <= n && ch[j] %in% c("!", "^")) j <- j + 1L
      if (j <= n && ch[j] == "]") j <- j + 1L
      while (j <= n && ch[j] != "]") j <- j + 1L
      if (j > n) { out <- c(out, "\\["); i <- i + 1L; next }        # unterminated: literal "["
      body <- ch[(i + 1L):(j - 1L)]
      neg <- length(body) && body[1L] %in% c("!", "^")
      if (neg) body <- body[-1L]
      body <- gsub("\\", "\\\\", paste(body, collapse = ""), fixed = TRUE)
      body <- gsub("]", "\\]", body, fixed = TRUE)                   # a leading "]" is a literal member
      out <- c(out, paste0("[", if (neg) "^", body, "]")); i <- j + 1L; next
    }
    if (braces && c == "{") { depth <- depth + 1L; out <- c(out, "(?:"); i <- i + 1L; next }
    if (braces && c == "}" && depth > 0L) { depth <- depth - 1L; out <- c(out, ")"); i <- i + 1L; next }
    if (braces && c == "," && depth > 0L) { out <- c(out, "|"); i <- i + 1L; next }
    out <- c(out, esc(c)); i <- i + 1L
  }
  if (depth > 0L) stop(sprintf("error parsing glob '%s': unclosed alternation group", glob), call. = FALSE)
  mark_utf8(paste(out, collapse = ""))
}

# ---- gitignore ------------------------------------------------------------------
# One rule = list(regex, negated, dir_only, base) ; `base` is the directory (relative to the walk
# anchor, "" = anchor itself) of the ignore file the rule came from.
compile_ignore_rules <- function(lines, base = "") {
  rules <- list()
  for (ln in lines) {
    ln <- sub("\r$", "", ln)
    if (!nzchar(ln) || startsWith(ln, "#")) next
    ln <- sub("(?<!\\\\)[ \t]+$", "", ln, perl = TRUE)               # trailing blanks unless escaped
    if (!nzchar(ln)) next
    neg <- startsWith(ln, "!"); if (neg) ln <- substring(ln, 2L)
    if (startsWith(ln, "\\#") || startsWith(ln, "\\!")) ln <- substring(ln, 2L)
    dir_only <- endsWith(ln, "/"); if (dir_only) ln <- sub("/+$", "", ln)
    if (!nzchar(ln)) next
    anchored <- grepl("/", ln, fixed = TRUE)
    ln <- sub("^/", "", ln)
    body <- tryCatch(glob_to_regex(ln, braces = FALSE), error = function(e) NULL)
    if (is.null(body)) next
    rules[[length(rules) + 1L]] <- list(regex = paste0(if (anchored) "^" else "^(?:.*/)?", body, "$"),
                                        negated = neg, dir_only = dir_only, base = base)
  }
  rules
}

.rel_to_base <- function(rel, base) if (!nzchar(base)) rel else substring(rel, nchar(base) + 2L)

# rel: paths relative to the anchor (posix). Returns logical vector "ignored".
apply_ignore_rules <- function(rules, rel, is_dir) {
  ignored <- logical(length(rel))
  for (r in rules) {
    cand <- if (nzchar(r$base)) startsWith(rel, paste0(r$base, "/")) else rep(TRUE, length(rel))
    if (r$dir_only) cand <- cand & is_dir
    if (!any(cand)) next
    hit <- grepl(r$regex, .rel_to_base(rel[cand], r$base), perl = TRUE)
    if (any(hit)) ignored[which(cand)[hit]] <- !r$negated
  }
  ignored
}

.read_ignore_file <- function(path) {
  b <- tryCatch(read_file_bytes(path), error = function(e) raw())
  if (!length(b) || is_binary_bytes(b)) return(character())
  split_lines_js(decode_text(b)$text)
}

# ---- walker -----------------------------------------------------------------------
# Breadth-first, one list.files()/dir.exists() call per LEVEL (vectorised), pruning ignored
# directories before descending. Returns data.frame(rel, is_dir) with `rel` relative to `root`.
walk_files <- function(root, hidden = TRUE, use_ignore_files = TRUE, default_ignore = DEFAULT_IGNORE,
                       ignore_file_names = c(".gitignore", ".ignore", ".gptrignore"),
                       max_entries = 200000L, check_abort = NULL) {
  root <- path_norm_lexical(root)
  rules <- compile_ignore_rules(default_ignore, "")
  # ancestors: inside a git work tree the ignore files of parent directories apply too
  anchor <- root; prefix <- ""
  if (use_ignore_files) {
    cur <- root; chain <- character()
    repeat {
      if (file.exists(os_path(file.path(cur, ".git")))) { anchor <- cur; break }
      parent <- dirname(cur); if (identical(parent, cur)) { chain <- character(); break }
      chain <- c(basename(cur), chain); cur <- parent
    }
    if (!identical(anchor, root)) {
      prefix <- paste(chain, collapse = "/")
      dirs <- c("", Reduce(function(a, b) paste(a, b, sep = "/"), chain, accumulate = TRUE))
      dirs <- dirs[-length(dirs)]                     # ignore files AT root are picked up by the walk
      for (d in dirs) for (nm in ignore_file_names) {
        f <- if (nzchar(d)) file.path(anchor, d, nm) else file.path(anchor, nm)
        if (file.exists(os_path(f))) rules <- c(rules, compile_ignore_rules(.read_ignore_file(f), d))
      }
    }
  }
  to_anchor <- function(rel) if (nzchar(prefix)) paste(prefix, rel, sep = "/") else rel
  frontier <- ""; out_rel <- list(); out_dir <- list(); total <- 0L; truncated <- FALSE
  while (length(frontier)) {
    if (is.function(check_abort)) check_abort()
    abs_dirs <- ifelse(nzchar(frontier), paste(root, frontier, sep = "/"), root)
    full <- unlist(lapply(abs_dirs, function(d) {
      x <- list.files(os_path(d), all.files = TRUE, no.. = TRUE, include.dirs = TRUE)
      if (length(x)) paste(d, x, sep = "/") else character()
    }), use.names = FALSE)
    if (!length(full)) break
    full <- mark_utf8(full)
    rel <- substring(full, nchar(root) + 2L)
    if (root == "/") rel <- substring(full, 2L)
    base <- basename(rel)
    is_dir <- dir.exists(os_path(full))
    link <- suppressWarnings(Sys.readlink(os_path(full))); is_link <- !is.na(link) & nzchar(link)
    if (use_ignore_files) {
      ign <- which(base %in% ignore_file_names & !is_dir)
      for (i in ign[order(match(base[ign], ignore_file_names))]) {
        d <- dirname(rel[i]); d <- if (identical(d, ".")) "" else d
        rules <- c(rules, compile_ignore_rules(.read_ignore_file(full[i]), if (nzchar(d)) to_anchor(d) else prefix))
      }
    }
    keep <- !apply_ignore_rules(rules, to_anchor(rel), is_dir)
    if (!hidden) keep <- keep & !startsWith(base, ".")
    rel <- rel[keep]; is_dir <- is_dir[keep]; is_link <- is_link[keep]
    out_rel[[length(out_rel) + 1L]] <- rel; out_dir[[length(out_dir) + 1L]] <- is_dir
    total <- total + length(rel)
    if (total >= max_entries) { truncated <- TRUE; break }
    frontier <- rel[is_dir & !is_link]            # never follow symlinked directories (loops)
  }
  res <- data.frame(rel = mark_utf8(as.character(unlist(out_rel))), is_dir = as.logical(unlist(out_dir)), stringsAsFactors = FALSE)
  attr(res, "truncated") <- truncated
  res
}

sort_paths <- function(x) x[order(tolower(x), x, method = "radix")]

# ---- find ----------------------------------------------------------------------------
tool_find <- function(pattern, path = NULL, limit = NULL, sort = c("path", "mtime", "size"), type = c("any", "file", "dir"),
                      cwd = getwd(), hidden = TRUE, check_abort = NULL) {
  sort <- match.arg(sort); type <- match.arg(type)
  search <- resolve_to_cwd(if (is.null(path) || !nzchar(path)) "." else path, cwd)
  if (!file.exists(os_path(search))) stop(sprintf("Path not found: %s", search), call. = FALSE)
  limit <- as.integer(limit %||% FIND_DEFAULT_LIMIT)
  pattern <- as_utf8(pattern)
  full_path <- grepl("/", pattern, fixed = TRUE)          # fd: basename match unless the glob has a "/"
  body <- glob_to_regex(pattern)
  absolute <- full_path && is_absolute_path(pattern)
  rx <- if (!full_path || absolute || startsWith(pattern, "**/")) paste0("^", body, "$") else paste0("^(?:.*/)?", body, "$")
  ignore_case <- !grepl("[[:upper:]]", pattern)                     # fd smart case
  w <- walk_files(search, hidden = hidden, check_abort = check_abort)
  walk_truncated <- isTRUE(attr(w, "truncated"))
  if (type == "file") w <- w[!w$is_dir, , drop = FALSE]
  if (type == "dir") w <- w[w$is_dir, , drop = FALSE]
  target <- if (absolute) paste(search, w$rel, sep = "/") else if (full_path) w$rel else basename(w$rel)
  hit <- if (nrow(w)) grepl(rx, target, perl = TRUE, ignore.case = ignore_case) else logical()
  w <- w[hit, , drop = FALSE]
  if (!nrow(w)) return(tool_result("No files found matching pattern"))
  ord <- switch(sort,
    path = order(tolower(w$rel), w$rel, method = "radix"),
    mtime = order(-as.numeric(file.mtime(os_path(file.path(search, w$rel)))), tolower(w$rel), method = "radix"),
    size = order(-file.size(os_path(file.path(search, w$rel))), tolower(w$rel), method = "radix"))
  w <- w[ord, , drop = FALSE]
  limit_reached <- nrow(w) > limit
  w <- utils::head(w, limit)
  lines <- paste0(w$rel, ifelse(w$is_dir, "/", ""))
  tr <- truncate_head(paste(lines, collapse = "\n"), max_lines = .Machine$integer.max)
  out <- tr$content; notices <- character(); details <- list()
  if (limit_reached) { notices <- c(notices, sprintf("%d results limit reached. Use limit=%d for more, or refine pattern", limit, limit * 2L)); details$resultLimitReached <- limit }
  if (tr$truncated) { notices <- c(notices, sprintf("%s limit reached", format_size(GPTR_MAX_BYTES))); details$truncation <- tr }
  if (walk_truncated) notices <- c(notices, "directory walk stopped early; narrow the path")
  if (length(notices)) out <- sprintf("%s\n\n[%s]", out, paste(notices, collapse = ". "))
  tool_result(mark_utf8(out), details = if (length(details)) details)
}

# ---- grep ----------------------------------------------------------------------------
.regex_error <- function(pattern, expr) {
  warn <- NULL
  res <- tryCatch(withCallingHandlers(expr, warning = function(w) { warn <<- conditionMessage(w); invokeRestart("muffleWarning") }),
                  error = function(e) e)
  if (inherits(res, "error")) {
    why <- if (!is.null(warn)) gsub("\\s+", " ", sub("^PCRE pattern compilation error\\s*", "", warn)) else conditionMessage(res)
    stop(sprintf("regex parse error: %s (pattern: %s)", trimws(why), pattern), call. = FALSE)
  }
  res
}
.quote_literal <- function(p) paste0("\\Q", gsub("\\E", "\\E\\\\E\\Q", p, fixed = TRUE), "\\E")

tool_grep <- function(pattern, path = NULL, glob = NULL, ignoreCase = FALSE, literal = FALSE, context = NULL, limit = NULL,
                      cwd = getwd(), hidden = TRUE, check_abort = NULL) {
  search <- resolve_to_cwd(if (is.null(path) || !nzchar(path)) "." else path, cwd)
  if (!file.exists(os_path(search))) stop(sprintf("Path not found: %s", search), call. = FALSE)
  is_dir <- dir.exists(os_path(search))
  ctx <- if (!is.null(context) && !is.na(context) && context > 0) as.integer(context) else 0L
  limit <- max(1L, as.integer(limit %||% GREP_DEFAULT_LIMIT))
  pattern <- as_utf8(pattern)
  if (!nzchar(pattern)) stop("pattern must not be empty", call. = FALSE)
  fixed <- isTRUE(literal) && !isTRUE(ignoreCase)
  rx <- if (isTRUE(literal) && isTRUE(ignoreCase)) .quote_literal(pattern) else pattern
  if (!isTRUE(literal)) .regex_error(pattern, grepl(rx, "", perl = TRUE))       # validate once, friendly message
  matcher <- function(lines) {
    if (fixed) grepl(rx, lines, fixed = TRUE) else grepl(rx, lines, perl = TRUE, ignore.case = isTRUE(ignoreCase))
  }
  if (is_dir) {
    w <- walk_files(search, hidden = hidden, check_abort = check_abort)
    files <- w$rel[!w$is_dir]
    if (!is.null(glob) && nzchar(glob)) {
      gr <- compile_ignore_rules(strsplit(glob, "\n", fixed = TRUE)[[1L]], "")
      inc <- Filter(function(r) !r$negated, gr); exc <- Filter(function(r) r$negated, gr)
      keep <- rep(length(inc) == 0L, length(files))
      for (r in inc) keep <- keep | grepl(r$regex, files, perl = TRUE)
      for (r in exc) keep <- keep & !grepl(r$regex, files, perl = TRUE)
      files <- files[keep]
    }
    files <- sort_paths(files)
    abs_files <- if (length(files)) paste(search, files, sep = "/") else character()
    shown <- files
  } else {
    abs_files <- search; shown <- mark_utf8(basename(search))
  }
  out <- character(); n_match <- 0L; limit_reached <- FALSE; lines_truncated <- FALSE; skipped_large <- 0L
  fmt <- function(lines) {
    vapply(lines, function(l) { t <- truncate_line(l); if (t$wasTruncated) lines_truncated <<- TRUE; t$text }, "", USE.NAMES = FALSE)
  }
  # Whole-file prefilter: one vectorised regex call per batch; only files that can match are
  # split into lines. "(?m)" keeps ^ and $ line-oriented. It may over-select, never under-select,
  # except for the text anchors \A \z \Z \G and leading (*VERB)s, where it is switched off.
  prefilter <- if (fixed) function(txts) grepl(rx, txts, fixed = TRUE)
               else if (grepl("\\\\[AzZG]|^\\(\\*", rx)) function(txts) rep(TRUE, length(txts))
               else function(txts) grepl(paste0("(?m)", rx), txts, perl = TRUE, ignore.case = isTRUE(ignoreCase))
  sizes <- file.size(os_path(abs_files))
  big <- !is.na(sizes) & sizes > GREP_MAX_FILE_BYTES
  skipped_large <- sum(big)
  todo <- which(!is.na(sizes) & sizes > 0 & !big)
  batches <- split(todo, ceiling(seq_along(todo) / 256L))
  for (batch in batches) {
    if (is.function(check_abort)) check_abort()
    texts <- vapply(batch, function(i) {
      bytes <- tryCatch(read_file_bytes(abs_files[i]), error = function(e) NULL)
      if (is.null(bytes) || is_binary_bytes(bytes)) return(NA_character_)
      decode_text(bytes)$text
    }, "")
    cand <- which(!is.na(texts))
    texts[cand] <- normalize_to_lf_bytes(texts[cand])        # CRLF -> LF before matching, so "$" works
    texts <- mark_utf8(texts)
    cand <- cand[prefilter(texts[cand])]
    for (j in cand) {
      i <- batch[j]
      lines <- split_lines_count(texts[j])
      if (!length(lines)) next
      hit <- which(matcher(lines))
      if (!length(hit)) next
      room <- limit - n_match
      if (length(hit) >= room) { hit <- hit[seq_len(room)]; limit_reached <- TRUE }
      n_match <- n_match + length(hit)
      if (ctx == 0L) {
        out <- c(out, sprintf("%s:%d: %s", shown[i], hit, fmt(lines[hit])))
      } else {
        want <- sort(unique(unlist(lapply(hit, function(h) max(1L, h - ctx):min(length(lines), h + ctx)))))
        is_m <- want %in% hit
        blk <- ifelse(is_m, sprintf("%s:%d: %s", shown[i], want, fmt(lines[want])), sprintf("%s-%d- %s", shown[i], want, fmt(lines[want])))
        gap <- c(FALSE, diff(want) > 1L)                      # "--" between non-adjacent blocks (grep convention)
        blk <- as.vector(rbind(ifelse(gap, "--", NA_character_), blk)); blk <- blk[!is.na(blk)]
        if (length(out)) out <- c(out, "--")
        out <- c(out, blk)
      }
      if (limit_reached) break
    }
    if (limit_reached) break
  }
  if (n_match == 0L) return(tool_result("No matches found"))
  tr <- truncate_head(paste(out, collapse = "\n"), max_lines = .Machine$integer.max)
  text <- tr$content; notices <- character(); details <- list()
  if (limit_reached) { notices <- c(notices, sprintf("%d matches limit reached. Use limit=%d for more, or refine pattern", limit, limit * 2L)); details$matchLimitReached <- limit }
  if (tr$truncated) { notices <- c(notices, sprintf("%s limit reached", format_size(GPTR_MAX_BYTES))); details$truncation <- tr }
  if (lines_truncated) { notices <- c(notices, sprintf("Some lines truncated to %d chars. Use read tool to see full lines", GPTR_GREP_MAX_LINE_LENGTH)); details$linesTruncated <- TRUE }
  if (skipped_large > 0L) notices <- c(notices, sprintf("%d file(s) larger than %s skipped", skipped_large, format_size(GREP_MAX_FILE_BYTES)))
  if (length(notices)) text <- sprintf("%s\n\n[%s]", text, paste(notices, collapse = ". "))
  tool_result(mark_utf8(text), details = if (length(details)) details)
}

normalize_to_lf_bytes <- function(text) {
  text <- gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
  mark_utf8(gsub("\r", "\n", text, fixed = TRUE, useBytes = TRUE))
}
````

### 5.7 Source: `04-run.R` (run_r, shell)

````r
# gptr tool layer prototype -- run_r (replaces pi's bash) and shell (optional), base R + optional processx

# Keep the head AND the tail (R output: headers/column names are at the top, errors at the bottom).
truncate_middle_lines <- function(content, max_lines = GPTR_MAX_LINES, max_bytes = GPTR_MAX_BYTES) {
  total_bytes <- byte_len(content)
  lines <- split_lines_count(content); total_lines <- length(lines)
  if (total_lines <= max_lines && total_bytes <= max_bytes)
    return(list(content = content, truncated = FALSE, totalLines = total_lines, totalBytes = total_bytes, omittedLines = 0L))
  h <- truncate_head(content, max_lines = max_lines %/% 2L, max_bytes = max_bytes %/% 2L)
  t <- truncate_tail(content, max_lines = max_lines %/% 2L, max_bytes = max_bytes %/% 2L)
  omitted <- total_lines - h$outputLines - t$outputLines
  if (omitted <= 0L) return(list(content = content, truncated = FALSE, totalLines = total_lines, totalBytes = total_bytes, omittedLines = 0L))
  list(content = mark_utf8(paste0(h$content, if (nzchar(h$content)) "\n", sprintf("[... %d lines omitted ...]", omitted), "\n", t$content)),
       truncated = TRUE, totalLines = total_lines, totalBytes = total_bytes, omittedLines = omitted,
       headLines = h$outputLines, tailLines = t$outputLines, lastLinePartial = t$lastLinePartial)
}

.spill_file <- function(prefix) tempfile(paste0(prefix, "-"), fileext = ".log")   # tempfile() does not consume R's RNG (sample() would change the user's .Random.seed)

.format_condition <- function(cond, kind) {
  call <- conditionCall(cond)
  msg <- conditionMessage(cond)
  if (identical(call, quote(eval(ex, envir)))) call <- NULL        # raised at top level of the submitted code
  if (is.null(call)) sprintf("%s: %s", kind, msg)
  else sprintf("%s in %s : %s", kind, paste(deparse(call, nlines = 1L, width.cutoff = 80L), collapse = " "), msg)
}

tool_run_r <- function(code, timeout = NULL, envir = globalenv(), capture_plots = TRUE, max_plots = 4L,
                       plot_width = 1200, plot_height = 900, plot_res = 144) {
  if (!is.null(timeout) && (!is.finite(timeout) || timeout <= 0)) stop("Invalid timeout: must be a finite number of seconds", call. = FALSE)
  code <- as_utf8(code)
  exprs <- tryCatch(parse(text = code, keep.source = FALSE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(exprs, "error")) {
    return(tool_result(paste0("Error: parse failed\n", sub("^<text>:", "line ", conditionMessage(exprs))), is_error = TRUE,
                       details = list(phase = "parse")))
  }
  out_file <- .spill_file("gptr-r"); con <- file(out_file, open = "wb")
  emit <- function(...) { cat(..., file = con, sep = ""); invisible() }
  before <- ls(envir, all.names = TRUE)
  # --- graphics capture
  plot_dir <- NULL; dev_id <- NULL; prev_dev <- grDevices::dev.cur(); pages <- 0L
  hook <- function(...) pages <<- pages + 1L          # ragg writes a blank file even when nothing is drawn
  old_hooks <- list(getHook("before.plot.new"), getHook("before.grid.newpage"))
  if (capture_plots) {
    plot_dir <- tempfile("gptr-plots-"); dir.create(plot_dir)
    pat <- file.path(plot_dir, "plot-%03d.png")
    opened <- tryCatch({
      if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png(pat, width = plot_width, height = plot_height, res = plot_res)
      else grDevices::png(pat, width = plot_width, height = plot_height, res = plot_res)
      TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
    if (opened) {
      dev_id <- grDevices::dev.cur()
      setHook("before.plot.new", hook, "append"); setHook("before.grid.newpage", hook, "append")
    } else plot_dir <- NULL
  }
  sink_depth <- sink.number()
  sink(con, type = "output")
  old_opts <- options(warn = 1, max.print = 5000L, width = 120L, cli.num_colors = 1L, crayon.enabled = FALSE)
  status <- "ok"; err_text <- NULL
  cleanup <- function() {
    options(old_opts)
    while (sink.number() > sink_depth) sink(type = "output")
    setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
    if (!is.null(dev_id)) {
      setHook("before.plot.new", old_hooks[[1L]], "replace"); setHook("before.grid.newpage", old_hooks[[2L]], "replace")
      if (dev_id %in% grDevices::dev.list()) grDevices::dev.off(dev_id)
    }
    if (prev_dev > 1L && prev_dev %in% grDevices::dev.list()) grDevices::dev.set(prev_dev)
    try(close(con), silent = TRUE)
  }
  started <- proc.time()[["elapsed"]]
  tryCatch({
    withCallingHandlers({
      if (!is.null(timeout)) setTimeLimit(elapsed = timeout, transient = TRUE)
      for (ex in exprs) {
        res <- withVisible(eval(ex, envir))
        if (res$visible) { if (isS4(res$value)) methods::show(res$value) else print(res$value) }
      }
    },
    message = function(m) { emit(conditionMessage(m)); invokeRestart("muffleMessage") },
    warning = function(w) { emit(.format_condition(w, "Warning"), "\n"); invokeRestart("muffleWarning") })
  },
  interrupt = function(i) { status <<- "aborted" },
  error = function(e) {
    msg <- conditionMessage(e)
    if (!is.null(timeout) && grepl("reached (elapsed|CPU) time limit", msg)) status <<- "timeout"
    else { status <<- "error"; err_text <<- .format_condition(e, "Error") }
  })
  cleanup()
  wall <- round(proc.time()[["elapsed"]] - started, 1)
  bytes <- read_file_bytes(out_file)
  text <- if (length(bytes)) decode_text(bytes)$text else mark_utf8("")
  text <- gsub("\033\\[[0-9;]*[A-Za-z]", "", text, perl = TRUE)            # strip ANSI colour codes
  text <- sub("\n+$", "", normalize_to_lf_bytes(text))
  tr <- truncate_middle_lines(text)
  out <- tr$content; details <- list(wallTimeSeconds = wall, status = status)
  if (tr$truncated) {
    out <- sprintf("%s\n\n[Showing first %d and last %d of %d lines. Full output: %s]", out, tr$headLines, tr$tailLines, tr$totalLines, out_file)
    details$truncation <- tr[setdiff(names(tr), "content")]; details$fullOutputPath <- out_file
  } else unlink(out_file)
  after <- ls(envir, all.names = TRUE)
  created <- setdiff(after, before)
  if (length(created)) details$created <- created
  tail_status <- switch(status, ok = NULL, error = err_text,
                        timeout = sprintf("Code timed out after %s seconds", format(timeout)), aborted = "Code aborted")
  if (!is.null(tail_status)) out <- paste0(out, if (nzchar(out)) "\n\n", tail_status)
  if (!nzchar(out)) out <- "(no output)"
  content <- list(text_block(mark_utf8(out)))
  if (!is.null(plot_dir)) {
    pngs <- if (pages > 0L) sort(list.files(plot_dir, pattern = "\\.png$", full.names = TRUE)) else character()
    pngs <- pngs[file.size(pngs) > 0]
    if (length(pngs)) {
      if (length(pngs) > max_plots) {
        content[[1L]]$text <- sprintf("%s\n\n[%d plots produced; showing the last %d]", content[[1L]]$text, length(pngs), max_plots)
        pngs <- utils::tail(pngs, max_plots)
      }
      for (p in pngs) {
        pr <- process_image(read_file_bytes(p), "image/png")
        if (isTRUE(pr$ok)) content[[length(content) + 1L]] <- image_block(pr$data, pr$mimeType)
      }
      details$plots <- length(pngs)
    }
    unlink(plot_dir, recursive = TRUE)
  }
  tool_result(content, details = details, is_error = status != "ok")
}

# ---- shell (optional tool) -------------------------------------------------------
resolve_shell <- function(shell_path = getOption("gptr.shell")) {
  if (!is.null(shell_path)) {
    if (!file.exists(shell_path)) stop(sprintf("Custom shell path not found: %s", shell_path), call. = FALSE)
    ps <- grepl("(pwsh|powershell)(\\.exe)?$", shell_path, ignore.case = TRUE)
    return(list(shell = shell_path, args = if (ps) .powershell_args() else "-c", name = if (ps) "PowerShell" else basename(shell_path), kind = if (ps) "powershell" else "posix"))
  }
  if (is_windows()) {
    cand <- c(file.path(Sys.getenv("ProgramFiles"), "Git", "bin", "bash.exe"), file.path(Sys.getenv("ProgramFiles(x86)"), "Git", "bin", "bash.exe"))
    cand <- cand[file.exists(cand)]
    if (length(cand)) return(list(shell = cand[1L], args = "-c", name = "bash (Git Bash)", kind = "posix"))
    ps <- Sys.which(c("pwsh.exe", "powershell.exe")); ps <- ps[nzchar(ps)]
    if (length(ps)) return(list(shell = unname(ps[1L]), args = .powershell_args(), name = "PowerShell", kind = "powershell"))
    return(list(shell = Sys.getenv("COMSPEC", "cmd.exe"), args = c("/d", "/s", "/c"), name = "cmd.exe", kind = "cmd"))
  }
  if (file.exists("/bin/bash")) return(list(shell = "/bin/bash", args = "-c", name = "bash", kind = "posix"))
  b <- Sys.which("bash"); if (nzchar(b)) return(list(shell = unname(b), args = "-c", name = "bash", kind = "posix"))
  list(shell = "sh", args = "-c", name = "sh", kind = "posix")
}
.powershell_args <- function() c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command")   # pi POWERSHELL_ARGS
.ps_utf8_prefix <- "try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}\n"             # pi UTF8_OUTPUT_PREFIX

tool_shell <- function(command, timeout = NULL, cwd = getwd(), shell = resolve_shell(), use_processx = requireNamespace("processx", quietly = TRUE)) {
  if (!is.null(timeout) && (!is.finite(timeout) || timeout <= 0)) stop("Invalid timeout: must be a finite number of seconds", call. = FALSE)
  if (!dir.exists(os_path(cwd))) stop(sprintf("Working directory does not exist: %s\nCannot execute %s commands.", cwd, shell$name), call. = FALSE)
  cmd <- as_utf8(command)
  if (identical(shell$kind, "powershell")) cmd <- paste0(.ps_utf8_prefix, cmd)
  out_file <- .spill_file("gptr-shell")
  started <- proc.time()[["elapsed"]]
  timed_out <- FALSE; aborted <- FALSE
  if (use_processx) {
    res <- tryCatch(
      processx::run(shell$shell, c(shell$args, cmd), wd = cwd, timeout = timeout %||% Inf, error_on_status = FALSE,
                    stdout = out_file, stderr = "2>&1", cleanup_tree = TRUE, windows_hide_window = TRUE),
      interrupt = function(i) { aborted <<- TRUE; list(status = NA_integer_, timeout = FALSE) })
    status <- res$status; timed_out <- isTRUE(res$timeout)
  } else {
    old <- setwd(cwd); on.exit(setwd(old), add = TRUE)
    lines <- suppressWarnings(tryCatch(
      system2(shell$shell, c(shell$args, shQuote(cmd)), stdout = TRUE, stderr = TRUE,
              timeout = if (is.null(timeout)) 0 else ceiling(timeout)),      # system2() ignores fractional seconds < 1
      interrupt = function(i) { aborted <<- TRUE; character() }))
    status <- attr(lines, "status") %||% 0L
    if (identical(as.integer(status), 124L) && !is.null(timeout)) timed_out <- TRUE
    writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), if (length(lines)) "\n")), out_file)
  }
  wall <- round(proc.time()[["elapsed"]] - started, 1)
  bytes <- if (file.exists(out_file)) read_file_bytes(out_file) else raw()
  text <- if (length(bytes)) normalize_to_lf_bytes(decode_text(bytes)$text) else mark_utf8("")
  tr <- truncate_tail(text)
  out <- sub("\n$", "", tr$content); details <- list(exitCode = status, wallTimeSeconds = wall)
  if (tr$truncated) {
    s <- tr$totalLines - tr$outputLines + 1L
    out <- if (tr$lastLinePartial) sprintf("%s\n\n[Showing last %s of line %d. Full output: %s]", out, format_size(tr$outputBytes), tr$totalLines, out_file)
           else if (identical(tr$truncatedBy, "lines")) sprintf("%s\n\n[Showing lines %d-%d of %d. Full output: %s]", out, s, tr$totalLines, tr$totalLines, out_file)
           else sprintf("%s\n\n[Showing lines %d-%d of %d (%s limit). Full output: %s]", out, s, tr$totalLines, tr$totalLines, format_size(GPTR_MAX_BYTES), out_file)
    details$truncation <- tr[setdiff(names(tr), "content")]; details$fullOutputPath <- out_file
  } else unlink(out_file)
  append_status <- function(text, status) paste0(if (nzchar(text)) paste0(text, "\n\n"), status)
  if (aborted) return(tool_result(append_status(out, "Command aborted"), details, is_error = TRUE))
  if (timed_out) return(tool_result(append_status(out, sprintf("Command timed out after %s seconds", format(timeout))), details, is_error = TRUE))
  if (is.na(status)) return(tool_result(append_status(out, "Command terminated without an exit code"), details, is_error = TRUE))
  if (status != 0L) return(tool_result(append_status(out, sprintf("Command exited with code %d", as.integer(status))), details, is_error = TRUE))
  tool_result(if (nzchar(out)) mark_utf8(out) else "(no output)", details)
}
````

### 5.8 Source: `05-registry.R` (tool definitions, schemas, validation, dispatch, system prompt)

````r
# gptr tool layer prototype -- tool definitions, JSON schemas, validation, dispatch, system prompt

# ---- JSON schema helpers (plain lists -> jsonlite::toJSON(auto_unbox = TRUE)) ----------
s_string <- function(description) list(type = "string", description = description)
s_number <- function(description) list(type = "number", description = description)
s_boolean <- function(description) list(type = "boolean", description = description)
s_enum <- function(values, description) list(type = "string", enum = I(values), description = description)
s_array <- function(items, description) list(type = "array", items = items, description = description)
s_object <- function(..., .required = character()) {
  out <- list(type = "object")
  if (length(.required)) out$required <- I(.required)       # I(): stays a JSON array when length 1
  out$properties <- list(...)
  out
}

gptr_tool <- function(name, description, parameters, execute, snippet = NULL, guidelines = character(),
                      prepare = NULL, mutates = FALSE, default_active = TRUE) {
  structure(list(name = name, label = name, description = description, parameters = parameters, execute = execute,
                 promptSnippet = snippet, promptGuidelines = guidelines, prepareArguments = prepare,
                 mutates = mutates, defaultActive = default_active), class = "gptr_tool")
}

builtin_tools <- function(shell = NULL) {
  kb <- GPTR_MAX_BYTES / 1024
  tools <- list(
    read = gptr_tool("read",
      sprintf("Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to %d lines or %dKB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.", GPTR_MAX_LINES, kb),
      s_object(path = s_string("Path to the file to read (relative or absolute)"),
               offset = s_number("Line number to start reading from (1-indexed)"),
               limit = s_number("Maximum number of lines to read"), .required = "path"),
      function(args, ctx) tool_read(args$path, args$offset, args$limit, cwd = ctx$cwd, model_supports_images = ctx$images %||% TRUE),
      snippet = "Read file contents",
      guidelines = "Use read to examine files instead of readLines() or cat() in run_r."),
    run_r = gptr_tool("run_r",
      sprintf("Evaluate R code in the user's live R session (the same environment the user works in). Objects persist between calls and are visible to the user: inspect existing objects instead of re-loading data. Returns printed output, messages, warnings and errors; plots are returned as images. Output is truncated to the first and last %d lines or %dKB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.", GPTR_MAX_LINES %/% 2L, kb %/% 2L),
      s_object(code = s_string("R code to evaluate. May contain several expressions; visible values are printed as at the console"),
               timeout = s_number("Timeout in seconds (optional, no default timeout)"), .required = "code"),
      function(args, ctx) tool_run_r(args$code, args$timeout, envir = ctx$envir),
      snippet = "Evaluate R code in the live session (objects persist; plots are returned as images)",
      guidelines = c("Use run_r for computation and data inspection in the live session; do not shell out for things R can do",
                     "Objects created with run_r stay in the user's session: do not re-load data that is already in memory, and print compact summaries (str(), head(), dim()) rather than whole objects"),
      mutates = TRUE),
    edit = gptr_tool("edit",
      "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.",
      s_object(path = s_string("Path to the file to edit (relative or absolute)"),
               edits = s_array(s_object(oldText = s_string("Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call."),
                                        newText = s_string("Replacement text for this targeted edit."), .required = c("oldText", "newText")),
                               "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."),
               .required = c("path", "edits")),
      function(args, ctx) tool_edit(args$path, args$edits, cwd = ctx$cwd),
      snippet = "Make precise file edits with exact text replacement, including multiple disjoint edits in one call",
      guidelines = c("Use edit for precise changes (edits[].oldText must match exactly)",
                     "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls",
                     "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.",
                     "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."),
      prepare = prepare_edit_arguments, mutates = TRUE),
    write = gptr_tool("write",
      "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
      s_object(path = s_string("Path to the file to write (relative or absolute)"),
               content = s_string("Content to write to the file"), .required = c("path", "content")),
      function(args, ctx) tool_write(args$path, args$content, cwd = ctx$cwd),
      snippet = "Create or overwrite files", guidelines = "Use write only for new files or complete rewrites.", mutates = TRUE),
    grep = gptr_tool("grep",
      sprintf("Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to %d matches or %dKB (whichever is hit first). Long lines are truncated to %d chars.", GREP_DEFAULT_LIMIT, kb, GPTR_GREP_MAX_LINE_LENGTH),
      s_object(pattern = s_string("Search pattern (Perl-compatible regex, or literal string)"),
               path = s_string("Directory or file to search (default: current directory)"),
               glob = s_string("Filter files by glob pattern, e.g. '*.R' or '**/*.qmd'"),
               ignoreCase = s_boolean("Case-insensitive search (default: false)"),
               literal = s_boolean("Treat pattern as literal string instead of regex (default: false)"),
               context = s_number("Number of lines to show before and after each match (default: 0)"),
               limit = s_number(sprintf("Maximum number of matches to return (default: %d)", GREP_DEFAULT_LIMIT)), .required = "pattern"),
      function(args, ctx) tool_grep(args$pattern, args$path, args$glob, args$ignoreCase, args$literal, args$context, args$limit, cwd = ctx$cwd),
      snippet = "Search file contents for patterns (respects .gitignore)"),
    find = gptr_tool("find",
      sprintf("Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to %d results or %dKB (whichever is hit first).", FIND_DEFAULT_LIMIT, kb),
      s_object(pattern = s_string("Glob pattern to match files, e.g. '*.R', '**/*.csv', or 'R/**/*.R'"),
               path = s_string("Directory to search in (default: current directory)"),
               limit = s_number(sprintf("Maximum number of results (default: %d)", FIND_DEFAULT_LIMIT)),
               sort = s_enum(c("path", "mtime", "size"), "Result order: path (default, alphabetical), mtime (newest first) or size (largest first)"),
               .required = "pattern"),
      function(args, ctx) tool_find(args$pattern, args$path, args$limit, sort = args$sort %||% "path", cwd = ctx$cwd),
      snippet = "Find files by glob pattern (respects .gitignore)"),
    ls = gptr_tool("ls",
      sprintf("List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to %d entries or %dKB (whichever is hit first).", LS_DEFAULT_LIMIT, kb),
      s_object(path = s_string("Directory to list (default: current directory)"),
               limit = s_number(sprintf("Maximum number of entries to return (default: %d)", LS_DEFAULT_LIMIT))),
      function(args, ctx) tool_ls(args$path, args$limit, cwd = ctx$cwd),
      snippet = "List directory contents")
  )
  sh <- shell %||% tryCatch(resolve_shell(), error = function(e) NULL)
  if (!is.null(sh)) tools$shell <- gptr_tool("shell",
    sprintf("Execute a %s command in the current working directory. Returns stdout and stderr. Output is truncated to last %d lines or %dKB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.", sh$name, GPTR_MAX_LINES, kb),
    s_object(command = s_string("Shell command to execute"), timeout = s_number("Timeout in seconds (optional, no default timeout)"), .required = "command"),
    function(args, ctx) tool_shell(args$command, args$timeout, cwd = ctx$cwd, shell = sh),
    snippet = sprintf("Execute %s commands (git, quarto, system utilities)", sh$name),
    guidelines = "Use shell only for external programs; prefer run_r for anything R can do", mutates = TRUE, default_active = FALSE)
  tools
}

GPTR_DEFAULT_TOOLS <- c("read", "run_r", "edit", "write")          # pi: read, bash, edit, write

# pi resolveDefaultTools(): plain names replace the defaults, then +name adds / -name removes, in order.
resolve_tool_selection <- function(entries = NULL, defaults = GPTR_DEFAULT_TOOLS, exclude = character()) {
  if (is.null(entries)) return(setdiff(defaults, exclude))
  mod <- startsWith(entries, "+") | startsWith(entries, "-")
  plain <- entries[!mod]
  tools <- if (length(plain) > 0L || length(entries) == 0L) plain else defaults
  for (e in entries[mod]) {
    nm <- substring(e, 2L)
    if (startsWith(e, "+") && nzchar(nm) && !(nm %in% tools)) tools <- c(tools, nm)
    if (startsWith(e, "-")) tools <- setdiff(tools, nm)
  }
  setdiff(tools, exclude)
}

tool_schema_json <- function(tool, pretty = FALSE) jsonlite::toJSON(tool$parameters, auto_unbox = TRUE, pretty = pretty)
# provider payloads: Anthropic {name, description, input_schema}; OpenAI {type:"function", function:{name, description, parameters}}
tool_declaration <- function(tool, provider = c("anthropic", "openai")) {
  provider <- match.arg(provider)
  if (provider == "anthropic") list(name = tool$name, description = tool$description, input_schema = tool$parameters)
  else list(type = "function", `function` = list(name = tool$name, description = tool$description, parameters = tool$parameters))
}

# ---- argument validation / coercion (subset of pi validateToolArguments) ------------------
.type_ok <- function(v, type) switch(type,
  string = is.character(v) && length(v) == 1L && !is.na(v),
  number = is.numeric(v) && length(v) == 1L && is.finite(v),
  integer = is.numeric(v) && length(v) == 1L && is.finite(v) && v == round(v),
  boolean = is.logical(v) && length(v) == 1L && !is.na(v),
  array = is.list(v) && is.null(names(v)) || (is.atomic(v) && length(v) != 1L),
  object = is.list(v) && (!is.null(names(v)) || length(v) == 0L), TRUE)
.coerce <- function(v, type) {
  if (type %in% c("number", "integer") && is.character(v) && length(v) == 1L && nzchar(trimws(v))) {
    n <- suppressWarnings(as.numeric(v)); if (!is.na(n)) return(n)
  }
  if (type == "boolean" && is.character(v) && length(v) == 1L && v %in% c("true", "false")) return(v == "true")
  if (type == "string" && (is.numeric(v) || is.logical(v)) && length(v) == 1L) return(if (is.logical(v)) tolower(as.character(v)) else format(v))
  v
}
validate_args <- function(schema, args, path = "") {
  errors <- character()
  if (!is.list(args)) return(list(args = args, errors = sprintf("  - %s: must be object", if (nzchar(path)) path else "root")))
  req <- as.character(schema$required %||% character())
  for (nm in names(schema$properties)) {
    ps <- schema$properties[[nm]]; here <- if (nzchar(path)) paste0(path, ".", nm) else nm
    v <- args[[nm]]
    if (is.null(v)) {                                          # JSON null / missing
      if (nm %in% req) errors <- c(errors, sprintf("  - %s: must have required property %s", here, nm))
      args[[nm]] <- NULL; next
    }
    v <- .coerce(v, ps$type)
    if (!.type_ok(v, ps$type)) { errors <- c(errors, sprintf("  - %s: must be %s", here, ps$type)); next }
    if (!is.null(ps$enum) && !(v %in% ps$enum)) errors <- c(errors, sprintf("  - %s: must be one of %s", here, paste(ps$enum, collapse = ", ")))
    if (identical(ps$type, "array") && identical(ps$items$type, "object")) {
      for (i in seq_along(v)) {
        sub <- validate_args(ps$items, v[[i]], sprintf("%s.%d", here, i - 1L)); v[[i]] <- sub$args; errors <- c(errors, sub$errors)
      }
    }
    args[[nm]] <- v
  }
  list(args = args, errors = errors)
}

# ---- dispatch: never throws; every failure becomes an error result for the model ----------
execute_tool_call <- function(tools, name, args, ctx = list(cwd = getwd(), envir = globalenv())) {
  tool <- tools[[name]]
  if (is.null(tool)) return(tool_result(sprintf("Tool %s not found", name), details = list(), is_error = TRUE))
  tryCatch({
    if (is.function(tool$prepareArguments)) args <- tool$prepareArguments(args)
    v <- validate_args(tool$parameters, args)
    if (length(v$errors)) {
      stop(sprintf("Validation failed for tool \"%s\":\n%s\n\nReceived arguments:\n%s", name, paste(v$errors, collapse = "\n"),
                   jsonlite::toJSON(args, auto_unbox = TRUE, pretty = 2, null = "null")), call. = FALSE)
    }
    tool$execute(v$args, ctx)
  },
  interrupt = function(i) tool_result("Operation aborted", details = list(), is_error = TRUE),
  error = function(e) tool_result(conditionMessage(e), details = list(), is_error = TRUE))
}

# ---- system prompt (pi buildSystemPromptSections) -------------------------------------------
build_system_prompt <- function(tools, selected = GPTR_DEFAULT_TOOLS, cwd = getwd(), custom_prompt = NULL, append = NULL,
                                context_files = list(), skills_text = NULL, extra_guidelines = character(), sections = list()) {
  sec <- list()
  if (!is.null(custom_prompt)) {
    sec$preamble <- custom_prompt
  } else {
    sec$preamble <- "You are an expert R programming and data analysis assistant operating inside gptr, an agent harness that runs inside the user's live R session. You help users by inspecting and computing on the objects in their session, reading files, editing code, and writing new files."
    visible <- Filter(function(n) !is.null(tools[[n]]$promptSnippet), selected)
    lst <- if (length(visible)) paste(sprintf("- %s: %s", visible, vapply(visible, function(n) tools[[n]]$promptSnippet, "")), collapse = "\n") else "(none)"
    sec$tools <- paste0(lst, "\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.")
    rules <- character()
    add <- function(r) { r <- trimws(r); if (nzchar(r) && !(r %in% rules)) rules <<- c(rules, r) }
    if ("run_r" %in% selected && !any(c("grep", "find", "ls") %in% selected)) add("Use run_r for file operations like list.files(), file.info(), grepl()")
    for (n in selected) for (r in tools[[n]]$promptGuidelines) add(r)
    for (r in extra_guidelines) add(r)
    add("Be concise in your responses"); add("Show file paths clearly when working with files")
    sec$rules <- paste0("- ", rules, collapse = "\n")
  }
  if (!is.null(append) && nzchar(append)) sec$addendum <- append
  if (length(context_files)) sec$project_context <- paste(c("Project-specific instructions and guidelines:",
      vapply(context_files, function(f) sprintf("<project_instructions path=\"%s\">\n%s\n</project_instructions>", f$path, f$content), "")), collapse = "\n\n")
  if (!is.null(skills_text) && nzchar(skills_text) && any(c("read", "run_r") %in% selected)) sec$skills <- trimws(skills_text)
  sec$cwd <- gsub("\\", "/", cwd, fixed = TRUE)
  for (n in names(sections)) {
    if (!grepl("^[a-z][a-z0-9_-]*$", n) || n == "preamble") stop(sprintf("Invalid system prompt section name: %s", n), call. = FALSE)
    if (nzchar(sections[[n]])) sec[[n]] <- sections[[n]]
  }
  parts <- c(sec$preamble, vapply(setdiff(names(sec), "preamble"), function(n) sprintf("<%s>\n%s\n</%s>", n, sec[[n]], n), ""))
  paste(parts[nzchar(parts)], collapse = "\n\n")
}
````

### 5.9 Tests (convertible to testthat one-to-one)

`run-tests.R`:

````r
args <- commandArgs(trailingOnly = TRUE)
blocked <- strsplit(Sys.getenv("GPTR_BLOCK", ""), ",", fixed = TRUE)[[1]]
if (length(blocked)) {
  cat("simulating missing packages:", paste(blocked, collapse = ", "), "\n")
  requireNamespace <- function(package, ...) if (package %in% blocked) FALSE else base::requireNamespace(package, ...)
}
for (f in args) { cat("\n#### ", f, "\n"); source(f, echo = FALSE) }
````

`test-01.R`:

````r
# Tests mirroring pi's packages/coding-agent/test/tools.test.ts for read / write / edit / ls / truncate
for (f in c("00-utils.R", "01-read-write.R", "02-edit.R")) source(f)
cat("locale UTF-8:", l10n_info()[["UTF-8"]], "| stringi:", requireNamespace("stringi", quietly = TRUE), "\n")
.pass <- 0L; .fail <- 0L
ok <- function(cond, label) {
  if (isTRUE(cond)) .pass <<- .pass + 1L else { .fail <<- .fail + 1L; cat("  FAIL:", label, "\n") }
}
err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
U <- function(...) intToUtf8(c(...))
td <- tempfile("gptr-tools-"); dir.create(td)
wr <- function(name, text) { p <- file.path(td, name); writeBin(charToRaw(text), p); p }
rd <- function(p) { b <- readBin(p, "raw", file.size(p) + 10); x <- rawToChar(b); Encoding(x) <- "UTF-8"; x }
txt <- tool_result_text

cat("== truncate / format_size\n")
ok(format_size(512) == "512B" && format_size(51200) == "50.0KB" && format_size(3 * 1024 * 1024) == "3.0MB", "format_size")
t1 <- truncate_head(paste(sprintf("Line %d", 1:2500), collapse = "\n"))
ok(t1$truncated && t1$truncatedBy == "lines" && t1$totalLines == 2500 && t1$outputLines == 2000, "head by lines")
t2 <- truncate_head(paste(sprintf("Line %d: %s", 1:500, strrep("x", 200)), collapse = "\n"))
ok(t2$truncated && t2$truncatedBy == "bytes" && t2$outputBytes <= 51200 && t2$outputLines < 500, "head by bytes")
t3 <- truncate_head(strrep("y", 60000)); ok(t3$firstLineExceedsLimit && t3$content == "", "head first line exceeds")
t4 <- truncate_tail(paste0(paste(sprintf("line-%04d", 1:4000), collapse = "\n"), "\n"))
ok(t4$totalLines == 4000 && t4$outputLines == 2000 && startsWith(t4$content, "line-2001") && endsWith(t4$content, "line-4000"), "tail by lines, trailing newline not counted")
t5 <- truncate_tail(paste0("a\n", strrep(U(0x20AC), 30000)))   # 90000 bytes of euro signs on the last line
ok(t5$lastLinePartial && t5$outputBytes <= 51200 && validUTF8(t5$content) && t5$outputBytes %% 3 == 0, "tail partial last line cut on UTF-8 boundary")
ok(identical(split_lines_js("a\nb\n"), c("a", "b", "")) && identical(split_lines_js(""), ""), "JS split semantics")

cat("== read\n")
f <- wr("test.txt", "Hello, world!\nLine 2\nLine 3")
r <- tool_read(f); ok(txt(r) == "Hello, world!\nLine 2\nLine 3" && is.null(r$details), "read small file verbatim, no line numbers")
ok(grepl("ENOENT", err(tool_read(file.path(td, "nonexistent.txt")))), "read missing -> ENOENT")
f <- wr("large.txt", paste(sprintf("Line %d", 1:2500), collapse = "\n"))
r <- tool_read(f); o <- txt(r)
ok(grepl("[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]", o, fixed = TRUE) && !grepl("Line 2001", o, fixed = TRUE), "read line truncation notice")
ok(r$details$truncation$truncatedBy == "lines" && r$details$truncation$outputLines == 2000, "read truncation details")
f <- wr("large-bytes.txt", paste(sprintf("Line %d: %s", 1:500, strrep("x", 200)), collapse = "\n"))
ok(grepl("\\[Showing lines 1-\\d+ of 500 \\(50\\.0KB limit\\)\\. Use offset=\\d+ to continue\\.\\]", txt(tool_read(f))), "read byte truncation notice")
f <- wr("hundred.txt", paste(sprintf("Line %d", 1:100), collapse = "\n"))
o <- txt(tool_read(f, offset = 51)); ok(startsWith(o, "Line 51") && endsWith(o, "Line 100") && !grepl("Use offset=", o), "read offset")
o <- txt(tool_read(f, limit = 10)); ok(grepl("Line 10\n\n[90 more lines in file. Use offset=11 to continue.]", o, fixed = TRUE), "read limit")
o <- txt(tool_read(f, offset = 41, limit = 20)); ok(startsWith(o, "Line 41") && grepl("Line 60\n\n[40 more lines in file. Use offset=61 to continue.]", o, fixed = TRUE), "read offset+limit")
f <- wr("short.txt", "Line 1\nLine 2\nLine 3")
ok(identical(err(tool_read(f, offset = 100)), "Offset 100 is beyond end of file (3 lines total)"), "read offset beyond EOF")
png1 <- jsonlite::base64_dec("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==")
p <- file.path(td, "image.txt"); writeBin(png1, p)
r <- tool_read(p)
ok(r$content[[1]]$text == "Read image file [image/png]" && r$content[[2]]$type == "image" && r$content[[2]]$mimeType == "image/png" &&
     identical(jsonlite::base64_dec(r$content[[2]]$data), png1), "read image by magic bytes (not extension), base64 roundtrip")
ok(identical(image_dims(png1, "image/png"), c(1, 1)), "png dims")
r <- tool_read(p, model_supports_images = FALSE); ok(grepl("Current model does not support images", r$content[[1]]$text), "non-vision note")
f <- wr("not-an-image.png", "definitely not a png"); r <- tool_read(f)
ok(txt(r) == "definitely not a png" && length(r$content) == 1L, "fake .png is read as text")
bmp <- raw(58); bmp[1:2] <- charToRaw("BM"); bmp[3] <- as.raw(58); bmp[11] <- as.raw(54); bmp[15] <- as.raw(40); bmp[19] <- as.raw(1); bmp[23] <- as.raw(1)
bmp[27] <- as.raw(1); bmp[29] <- as.raw(24); bmp[35] <- as.raw(4); bmp[57] <- as.raw(0xff)
ok(identical(detect_image_mime(bmp), "image/bmp"), "bmp sniff")
p <- file.path(td, "image.bmp"); writeBin(bmp, p); r <- tool_read(p)
if (requireNamespace("magick", quietly = TRUE)) {
  ok(grepl("Read image file [image/png]", r$content[[1]]$text, fixed = TRUE) && grepl("[Image converted from image/bmp to image/png.]", r$content[[1]]$text, fixed = TRUE) &&
       jsonlite::base64_dec(r$content[[2]]$data)[1] == as.raw(0x89), "bmp converted to png (magick)")
} else ok(grepl("Image omitted", r$content[[1]]$text), "bmp omitted without magick")
p <- file.path(td, "obj.rds"); saveRDS(mtcars, p, compress = FALSE); r <- tool_read(p)
ok(grepl("^\\[Binary file: .*readRDS\\(\\)", txt(r)), "binary file notice with R hint")
p <- file.path(td, "latin1.txt"); writeBin(as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x0a)), p)
ok(identical(charToRaw(txt(tool_read(p))), charToRaw(paste0("caf", U(0xE9), "\n"))), "latin1/CP1252 file decoded to UTF-8")
p <- file.path(td, "utf16.txt"); writeBin(c(as.raw(c(0xff, 0xfe)), iconv(paste0("h", U(0xE9), "llo\n"), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]), p)
ok(identical(charToRaw(txt(tool_read(p))), charToRaw(paste0("h", U(0xE9), "llo\n"))), "UTF-16LE BOM file decoded")
invisible(tool_edit(p, list(list(oldText = "llo", newText = "LLO"))))
ok(identical(readBin(p, "raw", 100), c(as.raw(c(0xff, 0xfe)), iconv(paste0("h", U(0xE9), "LLO\n"), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]])), "UTF-16LE file edited and re-encoded with BOM")

cat("== write\n")
p <- file.path(td, "nested", "dir", "test.txt")
r <- tool_write(p, paste0("Nested ", U(0x4F60, 0x597D), "\r\nx"))
ok(txt(r) == paste0("Successfully wrote to ", p) && identical(rd(p), paste0("Nested ", U(0x4F60, 0x597D), "\r\nx")), "write creates parents, bytes verbatim")
r <- tool_write("rel/a.txt", "x", cwd = td); ok(file.exists(file.path(td, "rel", "a.txt")) && txt(r) == "Successfully wrote to rel/a.txt", "write relative to cwd")

cat("== edit\n")
f <- wr("edit-test.txt", "Hello, world!")
r <- tool_edit(f, list(list(oldText = "world", newText = "testing")))
ok(txt(r) == sprintf("Successfully replaced 1 block(s) in %s.", f) && rd(f) == "Hello, testing!", "edit basic")
ok(grepl("-1 Hello, world!\n+1 Hello, testing!", r$details$diff, fixed = TRUE) && r$details$firstChangedLine == 1, "edit display diff")
ok(grepl("^--- .*\n\\+\\+\\+ .*\n@@ -1,1 \\+1,1 @@\n-Hello, world!\n\\\\ No newline at end of file\n\\+Hello, testing!\n\\\\ No newline", r$details$patch), "edit unified patch")
f <- wr("edit-test.txt", "Hello, world!")
ok(grepl("^Could not find the exact text in ", err(tool_edit(f, list(list(oldText = "nonexistent", newText = "t"))))), "edit not found")
m <- file.path(td, "missing.txt")
ok(identical(err(tool_edit(m, list(list(oldText = "a", newText = "b")))), sprintf("Could not edit file: %s. Error code: ENOENT.", m)), "edit ENOENT")
f <- wr("dups.txt", "foo foo foo")
ok(grepl("^Found 3 occurrences of the text in ", err(tool_edit(f, list(list(oldText = "foo", newText = "bar"))))), "edit duplicate")
f <- wr("multi.txt", "alpha\nbeta\ngamma\ndelta\n")
r <- tool_edit(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"), list(oldText = "gamma\n", newText = "GAMMA\n")))
ok(grepl("Successfully replaced 2 block(s)", txt(r), fixed = TRUE) && rd(f) == "ALPHA\nbeta\nGAMMA\ndelta\n", "edit multi")
f <- wr("gap.txt", paste0(paste(sprintf("line %03d", 1:600), collapse = "\n"), "\n"))
r <- tool_edit(f, list(list(oldText = "line 100\n", newText = "LINE 100\n"), list(oldText = "line 300\n", newText = "LINE 300\n"), list(oldText = "line 500\n", newText = "LINE 500\n")))
d <- r$details$diff
ok(grepl("LINE 100", d) && grepl("LINE 300", d) && grepl("LINE 500", d) && grepl("...", d, fixed = TRUE) && !grepl("line 250", d) && length(strsplit(d, "\n")[[1]]) < 50, "edit diff collapses gaps")
f <- wr("orig.txt", "foo\nbar\nbaz\n")
tool_edit(f, list(list(oldText = "foo\n", newText = "foo bar\n"), list(oldText = "bar\n", newText = "BAR\n")))
ok(rd(f) == "foo bar\nBAR\nbaz\n", "edits matched against original, not incrementally")
ok(grepl("edits must contain at least one replacement", err(tool_edit(f, list()))), "edit empty edits")
f <- wr("overlap.txt", "one\ntwo\nthree\n")
ok(grepl("^edits\\[0\\] and edits\\[1\\] overlap in ", err(tool_edit(f, list(list(oldText = "one\ntwo\n", newText = "A"), list(oldText = "two\nthree\n", newText = "B"))))), "edit overlap")
f <- wr("nopartial.txt", "alpha\nbeta\ngamma\n")
e <- err(tool_edit(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"), list(oldText = "missing\n", newText = "M\n"))))
ok(grepl("^Could not find edits\\[1\\] in ", e) && rd(f) == "alpha\nbeta\ngamma\n", "edit atomic: no partial apply")
f <- wr("ro.txt", "hello\n"); Sys.chmod(f, "0444")
if (.Platform$OS.type != "windows") ok(identical(err(tool_edit(f, list(list(oldText = "hello", newText = "w")))), sprintf("Could not edit file: %s. Error code: EACCES.", f)), "edit EACCES")
f <- wr("same.txt", "abc\n"); ok(grepl("^No changes made to ", err(tool_edit(f, list(list(oldText = "abc", newText = "abc"))))), "edit no change")
ok(grepl("oldText must not be empty", err(tool_edit(f, list(list(oldText = "", newText = "x"))))), "edit empty oldText")

cat("== edit fuzzy\n")
f <- wr("tws.txt", "line one   \nline two  \nline three\n")
tool_edit(f, list(list(oldText = "line one\nline two\n", newText = "replaced\n"))); ok(rd(f) == "replaced\nline three\n", "fuzzy trailing whitespace")
f <- wr("sq.txt", paste0("console.log(", U(0x2018), "hello", U(0x2019), ");\n"))
tool_edit(f, list(list(oldText = "console.log('hello');", newText = "console.log('world');"))); ok(rd(f) == "console.log('world');\n", "fuzzy smart single quotes")
f <- wr("dq.txt", paste0("const msg = ", U(0x201C), "Hello World", U(0x201D), ";\n"))
tool_edit(f, list(list(oldText = "const msg = \"Hello World\";", newText = "const msg = \"Goodbye\";"))); ok(grepl("Goodbye", rd(f)), "fuzzy smart double quotes")
f <- wr("dash.txt", paste0("range: 1", U(0x2013), "5\nbreak", U(0x2014), "here\n"))
tool_edit(f, list(list(oldText = "range: 1-5\nbreak-here", newText = "range: 10-50\nbreak--here"))); ok(rd(f) == "range: 10-50\nbreak--here\n", "fuzzy dashes")
f <- wr("nbsp.txt", paste0("hello", U(0xA0), "world\n"))
tool_edit(f, list(list(oldText = "hello world", newText = "hello universe"))); ok(rd(f) == "hello universe\n", "fuzzy nbsp")
if (requireNamespace("stringi", quietly = TRUE)) {
  f <- wr("zh.txt", paste0(U(0x4F60, 0x597D, 0xFF0C, 0x4E16, 0x754C), "\n", U(0x4F60, 0x597D, 0xFF08, 0x4E16, 0x754C, 0xFF09), "\n"))
  tool_edit(f, list(list(oldText = paste0(U(0x4F60, 0x597D), ",", U(0x4E16, 0x754C), "\n", U(0x4F60, 0x597D), "(", U(0x4E16, 0x754C), ")\n"),
                         newText = paste0(U(0x4F60, 0x597D, 0xFF0C), "pi\n", U(0x4F60, 0x597D), "(pi)\n"))))
  ok(identical(rd(f), paste0(U(0x4F60, 0x597D, 0xFF0C), "pi\n", U(0x4F60, 0x597D), "(pi)\n")), "fuzzy NFKC fullwidth punctuation")
  f <- wr("compat.txt", paste0(U(0xFF21, 0xFF22, 0xFF23, 0xFF11, 0xFF12, 0xFF13), "\ncafe", U(0x301), "\n"))
  tool_edit(f, list(list(oldText = paste0("ABC123\ncaf", U(0xE9), "\n"), newText = "XYZ789\ncoffee\n"))); ok(rd(f) == "XYZ789\ncoffee\n", "fuzzy NFKC compatibility forms")
}
f <- wr("exact.txt", "const x = 'exact';\nconst y = 'other';\n")
r <- tool_edit(f, list(list(oldText = "const x = 'exact';", newText = "const x = 'changed';")))
ok(rd(f) == "const x = 'changed';\nconst y = 'other';\n" && !r$details$usedFuzzyMatch, "exact preferred over fuzzy")
f <- wr("fdups.txt", "hello world   \nhello world\n")
ok(grepl("^Found 2 occurrences", err(tool_edit(f, list(list(oldText = "hello world", newText = "replaced"))))), "duplicates detected after fuzzy normalisation")
f <- wr("fmulti.txt", paste0("console.log(", U(0x2018), "hello", U(0x2019), ");\nhello", U(0xA0), "world\n"))
tool_edit(f, list(list(oldText = "console.log('hello');\n", newText = "console.log('world');\n"), list(oldText = "hello world\n", newText = "hello universe\n")))
ok(rd(f) == "console.log('world');\nhello universe\n", "fuzzy multi-edit")
orig <- "replace me   \nafter   \n"; f <- wr("fdupline.txt", orig)
r <- tool_edit(f, list(list(oldText = "replace me\n", newText = "after\n")))
ok(rd(f) == "after\nafter   \n", "fuzzy: untouched neighbouring line keeps its bytes")
orig <- paste(c("keep before  ", "first target  ", "first after", "keep middle   ", "second target  ", "second after", "keep after  ", ""), collapse = "\n")
f <- wr("fpres.txt", orig)
r <- tool_edit(f, list(list(oldText = "first target\nfirst after", newText = "FIRST\nFIRST2"), list(oldText = "second target\nsecond after", newText = "SECOND\nSECOND2")))
expct <- paste(c("keep before  ", "FIRST", "FIRST2", "keep middle   ", "SECOND", "SECOND2", "keep after  ", ""), collapse = "\n")
ok(rd(f) == expct, "fuzzy multi-edit preserves untouched lines")
pf <- file.path(td, "p.patch"); tf <- wr("fpres-orig.txt", orig); writeBin(charToRaw(r$details$patch), pf)
if (nzchar(Sys.which("patch"))) {
  st <- system2("patch", c("-s", shQuote(tf), shQuote(pf)), stdout = TRUE, stderr = TRUE)
  ok(rd(tf) == expct, "generated unified patch applies cleanly with patch(1)")
}

cat("== edit CRLF / BOM / encodings\n")
f <- wr("crlf.txt", "first\r\nsecond\r\nthird\r\n")
tool_edit(f, list(list(oldText = "second\n", newText = "REPLACED\n"))); ok(rd(f) == "first\r\nREPLACED\r\nthird\r\n", "CRLF preserved, LF oldText matches")
f <- wr("lf.txt", "first\nsecond\nthird\n")
tool_edit(f, list(list(oldText = "second\n", newText = "REPLACED\n"))); ok(rd(f) == "first\nREPLACED\nthird\n", "LF preserved")
f <- wr("mixed.txt", "hello\r\nworld\r\n---\r\nhello\nworld\n")
ok(grepl("^Found 2 occurrences", err(tool_edit(f, list(list(oldText = "hello\nworld\n", newText = "replaced\n"))))), "duplicates across CRLF/LF variants")
bom <- rawToChar(as.raw(c(0xef, 0xbb, 0xbf)))
f <- wr("bom.txt", paste0(bom, "first\r\nsecond\r\nthird\r\nfourth\r\n"))
tool_edit(f, list(list(oldText = "second\n", newText = "SECOND\n"), list(oldText = "fourth\n", newText = "FOURTH\n")))
ok(identical(readBin(f, "raw", 200), charToRaw(paste0(bom, "first\r\nSECOND\r\nthird\r\nFOURTH\r\n"))), "BOM + CRLF preserved in multi-edit")
p <- file.path(td, "cp1252.R"); writeBin(as.raw(c(charToRaw("x <- \"caf"), 0xe9, charToRaw("\"\ny <- 1\n"))), p)
tool_edit(p, list(list(oldText = "y <- 1", newText = "y <- 2")))
ok(identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x <- \"caf"), 0xe9, charToRaw("\"\ny <- 2\n")))), "CP1252 file round-trips in its own encoding")
ok(grepl("cannot be represented", err(tool_edit(p, list(list(oldText = "y <- 2", newText = paste0("y <- '", U(0x4F60), "'")))))) &&
     identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x <- \"caf"), 0xe9, charToRaw("\"\ny <- 2\n")))), "unrepresentable text is refused, file untouched")

cat("== edit argument shim\n")
a <- prepare_edit_arguments(list(path = "f", oldText = "before", newText = "after"))
ok(identical(a, list(path = "f", edits = list(list(oldText = "before", newText = "after")))), "legacy top-level oldText/newText folded")
a <- prepare_edit_arguments(list(path = "f", edits = "[{\"oldText\":\"a\",\"newText\":\"b\"}]"))
ok(identical(a$edits, list(list(oldText = "a", newText = "b"))), "stringified edits parsed")
a <- prepare_edit_arguments(list(path = "f", edits = list(oldText = "a", newText = "b")))
ok(identical(a$edits, list(list(oldText = "a", newText = "b"))), "single edit object wrapped")
a <- prepare_edit_arguments(list(path = "f", edits = "not json")); ok(identical(a$edits, "not json"), "invalid JSON left alone")

cat("== ls\n")
d <- file.path(td, "lsdir"); dir.create(d); invisible(file.create(file.path(d, c(".hidden-file", "Zeta.txt", "alpha.txt", "_under.R", "beta.R")))); dir.create(file.path(d, ".hidden-dir")); dir.create(file.path(d, "Sub"))
o <- txt(tool_ls(d))
ok(identical(strsplit(o, "\n")[[1]], c(".hidden-dir/", ".hidden-file", "_under.R", "alpha.txt", "beta.R", "Sub/", "Zeta.txt")), "ls sorted case-insensitively, dotfiles included, dirs suffixed")
o <- txt(tool_ls(d, limit = 2)); ok(grepl("\n\n[2 entries limit reached. Use limit=4 for more]", o, fixed = TRUE), "ls limit notice")
e <- file.path(td, "empty"); dir.create(e); ok(txt(tool_ls(e)) == "(empty directory)", "ls empty")
ok(grepl("^Path not found: ", err(tool_ls(file.path(td, "nope")))) && grepl("^Not a directory: ", err(tool_ls(f))), "ls errors")

cat("== paths\n")
ok(identical(resolve_to_cwd("relative/file.txt", "/some/cwd"), "/some/cwd/relative/file.txt"), "relative to cwd")
ok(identical(resolve_to_cwd("/abs/./x/../y.txt", "/some/cwd"), "/abs/y.txt"), "absolute, lexically normalised")
ok(identical(resolve_to_cwd("~draft.md", "/c"), "/c/~draft.md") && identical(resolve_to_cwd("@~draft.md", "/c"), "/c/~draft.md"), "tilde-prefixed names literal; @ stripped")
ok(identical(resolve_to_cwd("~/x.txt", "/c"), paste0(path_norm_lexical(path.expand("~")), "/x.txt")), "~/ expands to R home")
ok(identical(normalize_tool_path(paste0("file", U(0xA0), "name.txt")), "file name.txt"), "unicode spaces normalised")
ok(identical(normalize_windows_shell_path("/c/Users/x"), "C:/Users/x") && identical(normalize_windows_shell_path("/mnt/d/a b"), "D:/a b") && identical(normalize_windows_shell_path("/usr/bin"), "/usr/bin"), "git-bash / WSL drive paths")
ok(identical(path_norm_lexical("C:\\Users\\me\\..\\you\\f.R"), "C:/Users/you/f.R"), "windows path normalisation")
sn <- paste0("Screenshot 2024-01-01 at 10.00.00", U(0x202F), "AM.png"); writeBin(as.raw(1), os_path(file.path(td, sn)))
ok(identical(resolve_read_path("Screenshot 2024-01-01 at 10.00.00 AM.png", td), paste0(path_norm_lexical(td), "/", sn)), "macOS screenshot NNBSP variant")
cq <- paste0("Capture d", U(0x2019), "cran.txt"); writeBin(as.raw(1), os_path(file.path(td, cq)))
ok(identical(resolve_read_path("Capture d'cran.txt", td), paste0(path_norm_lexical(td), "/", cq)), "curly quote variant")
un <- paste0("caf", U(0xE9), " ", U(0x4F60), ".txt"); invisible(tool_write(un, "unicode name", cwd = td))
ok(txt(tool_read(un, cwd = td)) == "unicode name", "non-ASCII file name write + read")

unlink(td, recursive = TRUE)
cat(sprintf("\nRESULT: %d passed, %d failed\n", .pass, .fail))
````

`test-02.R`:

````r
# Tests for walker / gitignore / glob / find / grep, incl. ripgrep as an oracle when `rg` is installed
for (f in c("00-utils.R", "01-read-write.R", "02-edit.R", "03-search.R")) source(f)
cat("locale UTF-8:", l10n_info()[["UTF-8"]], "\n")
.pass <- 0L; .fail <- 0L
ok <- function(cond, label) if (isTRUE(cond)) { .pass <<- .pass + 1L; if (grepl("ORACLE|identical to rg", label)) cat("  ok:", label, "\n") } else { .fail <<- .fail + 1L; cat("  FAIL:", label, "\n") }
err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
txt <- tool_result_text
lines_of <- function(r) { l <- strsplit(txt(r), "\n", fixed = TRUE)[[1]]; l[nzchar(l) & !startsWith(l, "[")] }
U <- function(...) intToUtf8(c(...))
td <- tempfile("gptr-search-"); dir.create(td); td <- normalizePath(td)
mk <- function(rel, text = "") { p <- file.path(td, rel); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeBin(charToRaw(text), p); p }

cat("== glob_to_regex\n")
g <- function(glob, x, ...) grepl(paste0("^", glob_to_regex(glob, ...), "$"), x, perl = TRUE)
ok(identical(g("*.ts", c("a.ts", "a.tsx", "d/a.ts")), c(TRUE, FALSE, FALSE)), "* does not cross /")
ok(identical(g("**/*.ts", c("a.ts", "d/a.ts", "d/e/a.ts", "a.js")), c(TRUE, TRUE, TRUE, FALSE)), "**/ prefix")
ok(identical(g("src/**/*.spec.ts", c("src/a.spec.ts", "src/x/y/a.spec.ts", "lib/a.spec.ts")), c(TRUE, TRUE, FALSE)), "infix /**/")
ok(identical(g("some/parent/child/**", c("some/parent/child/f.ext", "some/parent/child/d/g", "some/parent/x")), c(TRUE, TRUE, FALSE)), "suffix /**")
ok(identical(g("file?.[ch]", c("file1.c", "file1.h", "file12.c", "file1.o")), c(TRUE, TRUE, FALSE, FALSE)), "? and [class]")
ok(identical(g("*.{R,Rmd,qmd}", c("a.R", "a.Rmd", "a.qmd", "a.py")), c(TRUE, TRUE, TRUE, FALSE)), "{a,b} alternation")
ok(identical(g("[!a-c]x", c("dx", "ax")), c(TRUE, FALSE)), "negated class")
ok(identical(g("a.b+c(d)", c("a.b+c(d)", "aXb+c(d)")), c(TRUE, FALSE)), "regex metacharacters are literal")
ok(grepl("error parsing glob", err(glob_to_regex("{a,b"))), "unclosed brace is an error")

cat("== find (pi regression cases #3302 #3303)\n")
mk("some/parent/child/file.ext"); mk("some/parent/child/test.spec.ts"); mk("src/foo/bar/example.spec.ts")
f <- function(p, ...) { r <- tool_find(p, td, ...); if (identical(txt(r), "No files found matching pattern")) character() else lines_of(r) }
ok(identical(f("*.spec.ts"), c("some/parent/child/test.spec.ts", "src/foo/bar/example.spec.ts")), "basename pattern")
ok(all(c("some/parent/child/file.ext", "some/parent/child/test.spec.ts") %in% f("some/parent/child/**")), "dir-prefixed ** tail")
ok(all(c("some/parent/child/file.ext", "some/parent/child/test.spec.ts") %in% f("**/parent/child/*")), "leading ** with segments")
ok(identical(f("src/**/*.spec.ts"), "src/foo/bar/example.spec.ts"), "src/**/*.spec.ts")
ok(identical(f("FOO"), character()) && identical(f("foo"), "src/foo/") && identical(f("foo", type = "file"), character()), "smart case; directories get a trailing slash")
ok(txt(tool_find("--help", td)) == "No files found matching pattern", "flag-like pattern is just text")
unlink(file.path(td, c("some", "src")), recursive = TRUE)
mk("a/.gitignore", "ignored.txt\n"); mk("a/deep/.gitignore", "secret.txt\n")
for (p in c("a/ignored.txt", "a/kept.txt", "a/deep/ignored.txt", "a/deep/secret.txt", "a/deep/kept.txt", "b/ignored.txt", "b/kept.txt", "root.txt")) mk(p)
ok(identical(f("**/*.txt"), c("a/deep/kept.txt", "a/kept.txt", "b/ignored.txt", "b/kept.txt", "root.txt")), "nested .gitignore scoped to its own subtree")
mk(".secret/hidden.txt"); ok(".secret/hidden.txt" %in% f("**/*.txt"), "hidden files included")
mk(".git/config", "x"); mk(".git/objects/aa.txt", "x"); mk("node_modules/p/i.txt", "x")
ok(!any(grepl("^\\.git/|^node_modules/", f("**/*"))), ".git and node_modules always skipped")
Sys.setFileTime(file.path(td, "b/kept.txt"), Sys.time() + 100); writeBin(raw(5000), file.path(td, "root.txt"))
ok(f("*.txt", sort = "mtime")[1] == "b/kept.txt" && f("*.txt", sort = "size")[1] == "root.txt", "sort by mtime / size")
r <- tool_find("*.txt", td, limit = 2)
ok(grepl("\n\n[2 results limit reached. Use limit=4 for more, or refine pattern]", txt(r), fixed = TRUE) && r$details$resultLimitReached == 2, "find limit notice")
ok(grepl("^Path not found: ", err(tool_find("*", file.path(td, "nope")))), "find path not found")

cat("== gitignore semantics\n")
unlink(list.files(td, all.files = TRUE, no.. = TRUE, full.names = TRUE), recursive = TRUE)
mk(".gitignore", paste(c("# comment", "", "*.log", "!keep.log", "/rootonly.txt", "build/", "docs/**/*.tmp", "sub/inner.txt", "trail.txt   ", "\\#hash.txt", "data/*", "!data/keep/"), collapse = "\n"))
for (p in c("a.log", "keep.log", "x/y/b.log", "rootonly.txt", "x/rootonly.txt", "build/o.txt", "x/build/o.txt", "build.txt", "docs/a.tmp", "docs/p/q/b.tmp", "docs/b.md",
            "sub/inner.txt", "x/sub/inner.txt", "trail.txt", "#hash.txt", "data/raw.csv", "data/keep/k.csv", "src/main.R")) mk(p, "x")
got <- sort(walk_files(td)$rel[!walk_files(td)$is_dir])
expect <- sort(c(".gitignore", "keep.log", "x/rootonly.txt", "build.txt", "docs/b.md", "x/sub/inner.txt", "data/keep/k.csv", "src/main.R"))
ok(identical(got, expect), "comments, negation, anchoring, dir-only, **, escapes, trailing blanks, re-included directory")
if (!identical(got, expect)) { cat("   got:   ", got, "\n   expect:", expect, "\n") }
if (nzchar(Sys.which("rg")) && nzchar(Sys.which("git"))) {
  system2("git", c("-C", shQuote(td), "init", "-q"), stdout = FALSE, stderr = FALSE)
  rgf <- system2("rg", c("--files", "--hidden", shQuote(td)), stdout = TRUE)
  rgf <- sort(substring(rgf[!grepl("/\\.git/", rgf)], nchar(td) + 2L))
  ok(identical(rgf, expect), "ORACLE: same file set as `rg --files --hidden` in a git repo")
  if (!identical(rgf, expect)) cat("   rg:", rgf, "\n")
  sub_got <- sort(walk_files(file.path(td, "x"))$rel); sub_got <- sub_got[!dir.exists(file.path(td, "x", sub_got))]
  rgs <- system2("rg", c("--files", "--hidden", shQuote(file.path(td, "x"))), stdout = TRUE); rgs <- sort(substring(rgs, nchar(file.path(td, "x")) + 2L))
  ok(identical(sub_got, rgs), "ORACLE: parent .gitignore applies when searching a sub-directory")
  if (!identical(sub_got, rgs)) { cat("   got:", sub_got, "\n   rg: ", rgs, "\n") }
}

cat("== grep\n")
unlink(list.files(td, all.files = TRUE, no.. = TRUE, full.names = TRUE), recursive = TRUE)
p <- mk("example.txt", "first line\nmatch line\nlast line")
ok(identical(txt(tool_grep("match", p)), "example.txt:2: match line"), "single file: basename shown")
p <- mk("context.txt", paste(c("before", "match one", "after", "middle", "match two", "after two"), collapse = "\n"))
o <- txt(tool_grep("match", p, limit = 1, context = 1))
ok(identical(o, "context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after\n\n[1 matches limit reached. Use limit=2 for more, or refine pattern]"), "limit + context")
o <- txt(tool_grep("match", p, context = 1))
ok(identical(o, "context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after\ncontext.txt-4- middle\ncontext.txt:5: match two\ncontext.txt-6- after two"), "adjacent context blocks merged, no duplicates")
mk("sub/s.R", "x <- needle(1)\r\ny <- 2\r\n"); mk("sub/t.R", "NEEDLE <- 3\n"); mk(".hid/h.txt", "needle hidden\n"); mk("bin.dat", "a"); writeBin(as.raw(c(0x62, 0x00, charToRaw("needle"))), file.path(td, "bin.dat"))
mk(".gitignore", "ignored.txt\n"); mk("ignored.txt", "needle ignored\n"); mk(".git/config", "needle git\n")
mk("u.txt", paste0("caf", U(0xE9), " needle ", U(0x4F60, 0x597D), "\n")); writeBin(as.raw(c(charToRaw("needle caf"), 0xe9, 0x0a)), file.path(td, "l1.txt"))
o <- lines_of(tool_grep("needle", td))
ok(
   identical(charToRaw(paste(o, collapse = "\n")), charToRaw(paste(c(".hid/h.txt:1: needle hidden", paste0("l1.txt:1: needle caf", U(0xE9)), "sub/s.R:1: x <- needle(1)", paste0("u.txt:1: caf", U(0xE9), " needle ", U(0x4F60, 0x597D))), collapse = "\n"))),
   "dir search: sorted, hidden included, ignored/.git/binary skipped, CRLF stripped, latin1 decoded")
ok(identical(lines_of(tool_grep("needle", td, ignoreCase = TRUE, glob = "*.R")), c("sub/s.R:1: x <- needle(1)", "sub/t.R:1: NEEDLE <- 3")), "ignoreCase + glob")
ok(identical(lines_of(tool_grep("needle", td, glob = "sub/**")), "sub/s.R:1: x <- needle(1)"), "glob with path")
ok(identical(lines_of(tool_grep("needle(1)", td, literal = TRUE)), "sub/s.R:1: x <- needle(1)"), "literal")
ok(identical(lines_of(tool_grep("NEEDLE(1)", td, literal = TRUE, ignoreCase = TRUE)), "sub/s.R:1: x <- needle(1)"), "literal + ignoreCase")
ok(identical(lines_of(tool_grep("x <- \\w+\\(\\d\\)$", td)), "sub/s.R:1: x <- needle(1)"), "PCRE regex")
ok(txt(tool_grep("zzzzqq", td)) == "No matches found", "no matches")
ok(txt(tool_grep("--pre=/bin/sh", td)) == "No matches found", "flag-like pattern is just text")
e <- err(tool_grep("a(", td)); ok(grepl("^regex parse error: .*missing closing parenthesis", e), "invalid regex -> readable error"); cat("   ", e, "\n")
p <- mk("long.txt", paste0("needle ", strrep("x", 600), "\n")); r <- tool_grep("needle", p)
ok(grepl("x\\.\\.\\. \\[truncated\\]\n\n\\[Some lines truncated to 500 chars\\. Use read tool to see full lines\\]$", txt(r)) && isTRUE(r$details$linesTruncated), "long lines truncated to 500 chars")
ok(grepl("^Path not found: ", err(tool_grep("x", file.path(td, "nope")))), "grep path not found")

rg_pairs <- function(pattern, dir, extra = character()) {
  js <- system2("rg", c("--json", "--line-number", "--color=never", "--hidden", extra, "--", shQuote(pattern), shQuote(dir)), stdout = TRUE)
  ev <- lapply(js, function(l) tryCatch(jsonlite::fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))
  ev <- Filter(function(e) identical(e$type, "match") && !is.null(e$data$path$text), ev)
  p <- vapply(ev, function(e) e$data$path$text, ""); n <- vapply(ev, function(e) as.integer(e$data$line_number), 1L)
  keep <- !grepl("/\\.git/", p)
  sort(paste0(substring(p[keep], nchar(dir) + 2L), ":", n[keep]))
}
pi_dir <- Sys.getenv("PI_DIR")
if (nzchar(Sys.which("rg")) && nzchar(pi_dir) && dir.exists(pi_dir)) {
  cat("== ORACLE: compare against ripgrep on the pi monorepo\n")
  src <- normalizePath(file.path(pi_dir, "packages", "coding-agent"))
  t0 <- Sys.time(); w <- walk_files(src); t_walk <- as.numeric(Sys.time() - t0, units = "secs")
  rgf <- system2("rg", c("--files", "--hidden", shQuote(src)), stdout = TRUE); rgf <- sort(substring(rgf, nchar(src) + 2L))
  mine <- sort(w$rel[!w$is_dir])
  ok(identical(mine, rgf), sprintf("file set identical to rg --files (%d files)", length(rgf)))
  if (!identical(mine, rgf)) { cat("   only mine:", head(setdiff(mine, rgf), 10), "\n   only rg:", head(setdiff(rgf, mine), 10), "\n") }
  cat(sprintf("   walk_files: %d entries in %.3fs\n", nrow(w), t_walk))
  for (pt in list(list("DEFAULT_MAX_BYTES", character(), list()), list("truncat(e|ion)Result", character(), list()),
                  list("export function \\w+\\(", character(), list()), list("todo", "--ignore-case", list(ignoreCase = TRUE)),
                  list("a.b", "--fixed-strings", list(literal = TRUE)), list("^import .* from \"\\./", c("--glob", shQuote("*.test.ts")), list(glob = "*.test.ts")))) {
    t0 <- Sys.time()
    r <- do.call(tool_grep, c(list(pt[[1]], src, limit = 1000000L), pt[[3]]))
    el <- as.numeric(Sys.time() - t0, units = "secs")
    l <- strsplit(txt(tool_result(r$content)), "\n", fixed = TRUE)[[1]]
    full <- r$details$truncation
    # the model-facing text is capped at 50KB, so compare (file:line) pairs from an uncapped run
    GPTR_MAX_BYTES <<- 1e9L
    r2 <- do.call(tool_grep, c(list(pt[[1]], src, limit = 1000000L), pt[[3]])); GPTR_MAX_BYTES <<- 50L * 1024L
    l <- strsplit(txt(r2), "\n", fixed = TRUE)[[1]]; l <- l[nzchar(l) & !startsWith(l, "[")]
    mine <- sort(sub("^(.*?:\\d+): .*$", "\\1", l, perl = TRUE))
    theirs <- rg_pairs(pt[[1]], src, pt[[2]])
    ok(identical(mine, theirs), sprintf("pattern %s: %d matching lines identical to rg (R: %.2fs)", pt[[1]], length(theirs), el))
    if (!identical(mine, theirs)) cat("   only mine:", head(setdiff(mine, theirs), 5), "\n   only rg:", head(setdiff(theirs, mine), 5), "\n")
  }
}
unlink(td, recursive = TRUE)
cat(sprintf("\nRESULT: %d passed, %d failed\n", .pass, .fail))
````

`test-03.R`:

````r
# Tests for run_r, shell, registry / validation / dispatch / system prompt
for (f in c("00-utils.R", "01-read-write.R", "02-edit.R", "03-search.R", "04-run.R", "05-registry.R")) source(f)
cat("locale UTF-8:", l10n_info()[["UTF-8"]], "| processx:", requireNamespace("processx", quietly = TRUE), "| ragg:", requireNamespace("ragg", quietly = TRUE),
    "| png capability:", capabilities("png"), "\n")
.pass <- 0L; .fail <- 0L
ok <- function(cond, label) if (isTRUE(cond)) .pass <<- .pass + 1L else { .fail <<- .fail + 1L; cat("  FAIL:", label, "\n") }
txt <- tool_result_text
td <- tempfile("gptr-run-"); dir.create(td); td <- normalizePath(td)

cat("== run_r\n")
env <- new.env(parent = globalenv())
r <- tool_run_r("x <- 1:10\nmean(x)\ny <- x * 2", envir = env)
ok(txt(r) == "[1] 5.5" && !r$isError && identical(sort(r$details$created), c("x", "y")) && identical(env$y, (1:10) * 2), "autoprint visible values only; objects persist in envir")
r <- tool_run_r("invisible(7); z <- 3", envir = env); ok(txt(r) == "(no output)", "invisible -> (no output)")
r <- tool_run_r("cat('a\\n'); message('note'); warning('careful'); print(x[1:3]); stop('boom')\ncat('never')", envir = env)
cat(txt(r), "\n")
ok(r$isError && identical(txt(r), "a\nnote\nWarning: careful\n[1] 1 2 3\n\nError: boom"), "stdout, message, warning, error interleaved in order; stops at first error")
r <- tool_run_r("f <- function(v) { if (v > 1) stop('too big: ', v); v }\nf(5)", envir = env)
ok(r$isError && grepl("Error in f\\(5\\) : too big: 5$", txt(r)), "error shows the failing call")
r <- tool_run_r("x <- c(1, 2\ny <- 3", envir = env); cat(txt(r), "\n")
ok(r$isError && grepl("^Error: parse failed\nline 2:1: unexpected symbol", txt(r)) && identical(r$details$phase, "parse"), "parse error reported with line:col, nothing evaluated")
r <- tool_run_r("cat('start\\n'); for (i in 1:100) Sys.sleep(0.05); cat('done')", timeout = 0.5, envir = env)
ok(r$isError && txt(r) == "start\n\nCode timed out after 0.5 seconds" && r$details$wallTimeSeconds < 3, "timeout via setTimeLimit (R-level code)")
t0 <- system.time(r <- tool_run_r("Sys.sleep(2); cat('done')", timeout = 0.5, envir = env))[["elapsed"]]
cat(sprintf("   NOTE single Sys.sleep(2) with timeout=0.5 -> isError=%s text=%s elapsed=%.1fs (soft timeout: not interruptible)\n", r$isError, txt(r), t0))
r <- tool_run_r("for (i in 1:5000) cat('row', i, '\\n')", envir = env); o <- txt(r)
ok(grepl("^row 1 \n", o) && grepl("\\[\\.\\.\\. 3000 lines omitted \\.\\.\\.\\]", o) && grepl("row 5000 \n\n\\[Showing first 1000 and last 1000 of 5000 lines\\. Full output: ", o) &&
     file.exists(r$details$fullOutputPath) && length(readLines(r$details$fullOutputPath)) == 5000, "head+tail truncation, full output spilled to temp file")
r <- tool_run_r(paste0("s <- '", intToUtf8(c(0x4F60, 0x597D)), " caf", intToUtf8(0xE9), "'; cat(s, nchar(s), '\\n')"), envir = env)
if (isTRUE(l10n_info()[["UTF-8"]])) ok(identical(charToRaw(txt(r)), charToRaw(paste0(intToUtf8(c(0x4F60, 0x597D)), " caf", intToUtf8(0xE9), " 7 "))), "UTF-8 code and output (UTF-8 locale)") else
  ok(identical(txt(r), "<U+4F60><U+597D> caf<U+00E9> 7 ") && nchar(env$s) == 7, "non-UTF-8 locale: value is correct, printed output is escaped by R itself")
if (capabilities("png") || requireNamespace("ragg", quietly = TRUE)) {
  r <- tool_run_r("plot(1:10, main = 'p1'); hist(rnorm(100))", envir = env)
  ok(length(r$content) == 3L && r$content[[2]]$type == "image" && r$content[[2]]$mimeType == "image/png" &&
       identical(jsonlite::base64_dec(r$content[[2]]$data)[1:4], as.raw(c(0x89, 0x50, 0x4e, 0x47))) && r$details$plots == 2, "two base plots captured as PNG image blocks")
  r <- tool_run_r("1 + 1", envir = env); ok(length(r$content) == 1L, "no plot -> no image block")
  ok(length(grDevices::dev.list()) == 0L, "graphics device closed after the call")
}
ok(sink.number() == 0L, "sink stack restored")
ok(identical(getOption("warn"), 0) || identical(getOption("warn"), 0L), "options restored")
big <- new.env(); big$m <- matrix(0, 3000, 3000)
t <- system.time(r <- tool_run_r("dim(m); object.size(m)", envir = big))[["elapsed"]]
ok(grepl("\\[1\\] 3000 3000\n72000216 bytes", txt(r)) && t < 1, "works on large in-memory objects without copying")

cat("== shell\n")
sh <- resolve_shell(); cat("   resolved shell:", sh$shell, paste(sh$args, collapse = " "), "\n")
for (px in unique(c(requireNamespace("processx", quietly = TRUE), FALSE))) {
  tag <- if (px) "processx" else "system2"
  r <- tool_shell("echo 'test output'", cwd = td, use_processx = px); ok(txt(r) == "test output" && !r$isError, paste(tag, "simple command"))
  r <- tool_shell("echo out; echo err 1>&2; exit 3", cwd = td, use_processx = px)
  ok(r$isError && txt(r) == "out\nerr\n\nCommand exited with code 3" && r$details$exitCode == 3, paste(tag, "non-zero exit, stderr merged"))
  r <- tool_shell("true", cwd = td, use_processx = px); ok(txt(r) == "(no output)", paste(tag, "no output"))
  r <- tool_shell("pwd", cwd = td, use_processx = px); ok(txt(r) == td, paste(tag, "cwd"))
  r <- tool_shell("echo begin; sleep 5; echo done", timeout = 0.5, cwd = td, use_processx = px)
  ok(r$isError && grepl("Command timed out after 0.5 seconds$", txt(r)) && r$details$wallTimeSeconds < 4, paste(tag, "timeout"))
  cat(sprintf("   %s timeout result: %s (%.1fs)\n", tag, gsub("\n", "\\\\n", txt(r)), r$details$wallTimeSeconds))
  r <- tool_shell("seq 1 3000", cwd = td, use_processx = px); o <- txt(r)
  ok(grepl("^1001\n", o) && grepl("3000\n\n\\[Showing lines 1001-3000 of 3000\\. Full output: ", o) && file.exists(r$details$fullOutputPath), paste(tag, "tail truncation + spill file"))
}
e <- tryCatch(tool_shell("echo x", cwd = "/this/does/not/exist"), error = function(e) conditionMessage(e))
ok(grepl("^Working directory does not exist: /this/does/not/exist\nCannot execute bash commands\\.$", e), "bad cwd")

cat("== registry / schemas\n")
tools <- builtin_tools()
ok(identical(names(tools), c("read", "run_r", "edit", "write", "grep", "find", "ls", "shell")), "tool list")
pi_read <- '{"type":"object","required":["path"],"properties":{"path":{"type":"string","description":"Path to the file to read (relative or absolute)"},"offset":{"type":"number","description":"Line number to start reading from (1-indexed)"},"limit":{"type":"number","description":"Maximum number of lines to read"}}}'
ok(identical(as.character(tool_schema_json(tools$read)), pi_read), "read schema is byte-identical to pi's JSON schema")
pi_edit <- '{"type":"object","required":["path","edits"],"properties":{"path":{"type":"string","description":"Path to the file to edit (relative or absolute)"},"edits":{"type":"array","items":{"type":"object","required":["oldText","newText"],"properties":{"oldText":{"type":"string","description":"Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call."},"newText":{"type":"string","description":"Replacement text for this targeted edit."}}},"description":"One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."}}}'
ok(identical(as.character(tool_schema_json(tools$edit)), pi_edit), "edit schema is byte-identical to pi's JSON schema")
ok(identical(as.character(tool_schema_json(tools$ls)), '{"type":"object","properties":{"path":{"type":"string","description":"Directory to list (default: current directory)"},"limit":{"type":"number","description":"Maximum number of entries to return (default: 500)"}}}'), "ls schema (no required)")
cat("   run_r schema:", as.character(tool_schema_json(tools$run_r)), "\n")
ok(identical(resolve_tool_selection(NULL), c("read", "run_r", "edit", "write")), "default tools")
ok(identical(resolve_tool_selection(c("read", "grep", "find", "ls")), c("read", "grep", "find", "ls")), "plain names replace")
ok(identical(resolve_tool_selection(c("+shell", "-write")), c("read", "run_r", "edit", "shell")), "+name / -name modify the defaults")
ok(identical(resolve_tool_selection(character()), character()), "empty list disables everything")
ok(identical(resolve_tool_selection(c("read", "grep"), exclude = "read"), "grep"), "exclude applies last")

cat("== dispatch / validation\n")
ctx <- list(cwd = td, envir = env)
r <- execute_tool_call(tools, "nope", list(), ctx); ok(r$isError && txt(r) == "Tool nope not found", "unknown tool")
r <- execute_tool_call(tools, "read", list(offset = 3), ctx); cat(txt(r), "\n")
ok(r$isError && grepl("^Validation failed for tool \"read\":\n  - path: must have required property path\n\nReceived arguments:\n", txt(r)), "missing required argument")
r <- execute_tool_call(tools, "write", list(path = "v.txt", content = "l1\nl2\nl3\n"), ctx); ok(!r$isError, "write through dispatcher")
r <- execute_tool_call(tools, "read", list(path = "v.txt", offset = "2", limit = "1"), ctx)
ok(!r$isError && txt(r) == "l2\n\n[2 more lines in file. Use offset=3 to continue.]", "numeric strings are coerced (models do send them)")
r <- execute_tool_call(tools, "read", list(path = "v.txt", offset = NULL, limit = NULL), ctx); ok(!r$isError && txt(r) == "l1\nl2\nl3\n", "JSON null for optional params is dropped")
r <- execute_tool_call(tools, "read", list(path = "missing.txt"), ctx); ok(r$isError && grepl("^ENOENT: no such file or directory", txt(r)), "thrown error -> isError result")
r <- execute_tool_call(tools, "edit", list(path = "v.txt", oldText = "l2", newText = "L2"), ctx)
ok(!r$isError && txt(r) == "Successfully replaced 1 block(s) in v.txt.", "legacy edit arguments accepted through prepareArguments")
r <- execute_tool_call(tools, "edit", list(path = "v.txt", edits = list(list(oldText = "l1"))), ctx)
ok(r$isError && grepl("  - edits.0.newText: must have required property newText", txt(r), fixed = TRUE), "nested validation path")
owd <- setwd(td); r <- execute_tool_call(tools, "run_r", list(code = "nchar(readLines('v.txt'))"), ctx); setwd(owd); ok(txt(r) == "[1] 2 2 2", "run_r through dispatcher")
r <- execute_tool_call(tools, "find", list(pattern = "*.txt", sort = "bogus"), ctx); ok(r$isError && grepl("sort: must be one of path, mtime, size", txt(r)), "enum validation")
args <- jsonlite::fromJSON('{"path":"v.txt","edits":[{"oldText":"l3","newText":"L3"}]}', simplifyVector = FALSE)
r <- execute_tool_call(tools, "edit", args, ctx); ok(!r$isError, "arguments parsed with jsonlite::fromJSON(simplifyVector = FALSE)")

cat("== system prompt\n")
p <- build_system_prompt(tools, cwd = "C:\\Users\\me\\proj"); cat(p, "\n")
ok(grepl("<tools>\n- read: Read file contents\n- run_r: ", p, fixed = TRUE) && grepl("<cwd>\nC:/Users/me/proj\n</cwd>$", p) &&
     grepl("- Use run_r for file operations like list.files()", p, fixed = TRUE), "default prompt sections")
p2 <- build_system_prompt(tools, selected = character(), cwd = "/tmp"); ok(grepl("<tools>\n(none)\n", p2, fixed = TRUE) && grepl("Show file paths clearly", p2), "no tools -> (none)")
p3 <- build_system_prompt(tools, cwd = "/tmp", custom_prompt = "You are Exact.", append = "Additional instructions.", context_files = list(list(path = "/tmp/AGENTS.md", content = "Project instructions.")))
ok(startsWith(p3, "You are Exact.\n\n<addendum>\nAdditional instructions.\n</addendum>\n\n<project_context>\nProject-specific instructions and guidelines:\n\n<project_instructions path=\"/tmp/AGENTS.md\">") && endsWith(p3, "<cwd>\n/tmp\n</cwd>"), "custom prompt drops tools/rules, keeps addendum/context/cwd")
unlink(td, recursive = TRUE)
cat(sprintf("\nRESULT: %d passed, %d failed\n", .pass, .fail))
````

### 5.10 gptr system prompt produced by the prototype for the recommended seven-tool selection

(Produced with `build_system_prompt(builtin_tools(), selected = c("read","run_r","edit","write","grep","find","ls"), cwd = "/Users/me/project")`; the verifier re-generated it and it is byte-identical to the block below. Note the prototype's own *default* selection is the four-tool set, see §4.1.)

```text
You are an expert R programming and data analysis assistant operating inside gptr, an agent harness that runs inside the user's live R session. You help users by inspecting and computing on the objects in their session, reading files, editing code, and writing new files.

<tools>
- read: Read file contents
- run_r: Evaluate R code in the live session (objects persist; plots are returned as images)
- edit: Make precise file edits with exact text replacement, including multiple disjoint edits in one call
- write: Create or overwrite files
- grep: Search file contents for patterns (respects .gitignore)
- find: Find files by glob pattern (respects .gitignore)
- ls: List directory contents

In addition to the tools above, you may have access to other custom tools depending on the project.
</tools>

<rules>
- Use read to examine files instead of readLines() or cat() in run_r.
- Use run_r for computation and data inspection in the live session; do not shell out for things R can do
- Objects created with run_r stay in the user's session: do not re-load data that is already in memory, and print compact summaries (str(), head(), dim()) rather than whole objects
- Use edit for precise changes (edits[].oldText must match exactly)
- When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls
- Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit.
- Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions.
- Use write only for new files or complete rewrites.
- Be concise in your responses
- Show file paths clearly when working with files
</rules>

<cwd>
/Users/me/project
</cwd>
```

### 5.11 What was *not* run

* Nothing was executed on Windows or Linux; all Windows statements are from Pi's source/docs or R documentation knowledge (marked UNCERTAIN where behaviour matters).
* `fd` is not installed here; fd semantics come from its documentation and source (URLs in §8), and from Pi's regression tests, whose cases the R `find` port reproduces.
* No LLM API calls were made; how real models cope with the `run_r` description is untested.
* Image resizing was exercised once outside the test-suite (script `imgtest.R`): a 3000×2500 PNG (145.9 KB) read through `tool_read()` came back as `image/png` 2000×1667 with the note `[Image: original 3000x2500, displayed at 2000x1667. Multiply coordinates by 1.50 to map to original image.]`; JPEG sniffing and dimension parsing returned `image/jpeg`, 800×600. The JPEG quality ladder and the ×0.75 shrink loop (payloads ≥ 4.5 MB) were not triggered by any input.

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN policy

* **File system**: tools write where the *model/user* asks at run time — that is user-initiated and acceptable — but examples, tests and vignettes must only write below `tempdir()`. Spill files and plot files of the prototype are created in `tempdir()` and are removed when not referenced (R deletes the session temp dir at exit; Pi never deletes its temp files).
* `.gptr/` workspace creation (REQ-27) must be an explicit user action or an interactive confirmation, never a side effect of `library(gptr)`.
* **No downloads of executables.** Pi's approach (download `rg`/`fd` into the user's home directory) is incompatible with CRAN policy and REQ-01; the pure-R implementation removes the need. If an optional fast path is ever added it may only *use* an `rg` already on `PATH`.
* **Global environment**: `run_r` evaluating in `globalenv()` is the purpose of the tool (REQ-22) but package code, examples and tests must pass an explicit environment (`new.env()`), as the prototype tests do.
* **Options / devices / sinks / working directory** must be restored with `on.exit()`; the prototype asserts `sink.number() == 0`, restored options and no leftover graphics device after each call.
* **ASCII source**: the prototypes are ASCII-only. (The original text said not to rely on `\u` escapes being UTF-8-marked; **corrected by the verifier:** `\u` escapes in ASCII source *are* reliably marked UTF-8 (E1/E2 re-run); it is raw non-ASCII bytes in source that are unreliable. Either `\u` escapes (CRAN's recommended form) or `intToUtf8()` is fine; never put raw non-ASCII bytes in R code.)
* **Tests**: no network, no dependency on `rg`/`git`/`patch` (the oracle tests must be `skip_if_not(nzchar(Sys.which("rg")))` and `skip_on_cran()`), timing assertions only with generous bounds, `Sys.chmod`-based permission tests skipped on Windows.
* **Dependencies**: only `jsonlite` is required by the tool layer; every optional package is guarded by `requireNamespace(quietly = TRUE)` and the package must pass `R CMD check` with `_R_CHECK_FORCE_SUGGESTS_=false`.
* `processx::run(cleanup_tree = TRUE)` and `system2(timeout=)` left no child processes behind in a verifier test on macOS (`bash -c "sleep 41 & sleep 42"` killed after 1 s, background `sleep` gone in both cases); R's `?system` states that timeout termination "is not guaranteed", so this is LIKELY, not guaranteed, and unverified on Windows. CRAN checks flag leftover files in the temp directory (and leftover processes are a known check problem).

### 6.2 Windows specifics

| Topic | Guidance | Status |
|---|---|---|
| Separators | accept `\` and `/`; emit `/` everywhere (R accepts `/` on Windows); `path_norm_lexical()` handles `C:\a\..\b` | VERIFIED (string logic on macOS) |
| Drive / UNC detection | `^[A-Za-z]:[/\\]` and `^[/\\]{2}` are absolute | VERIFIED (string logic) |
| Git-Bash / WSL / Cygwin paths from the model | rewrite `/c/x`, `/mnt/c/x`, `/cygdrive/c/x` → `C:/x` only when running on Windows (Pi does the same) | VERIFIED (string logic) |
| `~` | `path.expand("~")` is R's home (`R_USER`, typically `C:/Users/<u>/Documents`), not `%USERPROFILE%`; keep R's notion so that tools and `run_r` code agree | LIKELY |
| Line endings | always binary connections (`"rb"`, `"wb"`); `edit` preserves CRLF exactly like Pi | VERIFIED (macOS) |
| Encoding | R ≥ 4.2 on Windows 10 1903+ uses UTF-8 natively; on older R the code page limits file names and console output | LIKELY |
| Write-permission check | R's `?file.access` advises against pre-checking with `file.access()` (race between check and open; "better to wrap file open attempts in `try`") — it does not specifically say it is unreliable on Windows (corrected by the verifier); prefer attempting to open with `file(path, "r+b")` inside `tryCatch` and map failure to `EACCES` | UNCERTAIN |
| Read-only / locked files | a file open in Excel/RStudio may refuse writes (sharing violation) → return the OS message as an error result | UNCERTAIN |
| Symlinks | `Sys.readlink()` returns `""` on Windows; junctions are followed by `dir.exists()`; keep the `max_entries` guard of the walker against loops | UNCERTAIN |
| Case-insensitive file system | never use path string equality for identity; `normalizePath()` when comparing | LIKELY |
| Shell | no POSIX shell may be assumed (REQ-03): `shell` is opt-in and its description names the actual shell; PowerShell invocation copied from Pi incl. the UTF-8 console prefix; `processx` does the argument quoting; `system2()` fallback needs `shQuote(type = "cmd")` and cannot kill process trees | UNCERTAIN (not run) |
| Process tree kill | Pi uses `taskkill /F /T /PID`; `processx` tree cleanup (`cleanup_tree = TRUE`, `$kill_tree()`) marks the child with an environment variable inherited by all descendants and finds/kills them through the `ps` package (a processx Import) — **not** a Windows job object (corrected by the verifier from processx 3.8.6 docs; processx's `$kill()` docs note that children that created their own job object escape a plain kill) | VERIFIED (docs), UNCERTAIN (Windows runtime) |
| Long paths (> 260 chars), reserved names (`CON`, `NUL`, …), trailing dots/spaces | surface the OS error text to the model; do not pre-validate | UNCERTAIN |
| `file.rename()` over an existing file | works on POSIX (E17); behaviour on Windows not verified — if atomic writes are wanted, fall back to `file.copy(overwrite = TRUE)` + `unlink()` | UNCERTAIN |
| PNG device | `grDevices::png()` works out of the box on Windows and macOS; on headless Linux check `capabilities("png")` or use `ragg` | LIKELY |

### 6.3 Front-ends (REQ-03)

* RStudio / Positron: plots drawn inside `run_r` go to the capture device, not to the IDE's plot pane; the harness may replay them for the user (`recordPlot()`/`replayPlot()`), which the run_r track has to decide (open question Q4).
* knitr / Quarto / IRkernel: they install their own output hooks and graphics devices; `run_r` must restore the previous device (`dev.set(prev)`), which the prototype does, and must not leave sinks (knitr uses `sink()` too).
* `Rscript` and non-interactive rendering: the locale may be `C` (as in this research environment) — the tool layer has been tested there.

---

## 7. Risks, pitfalls, open questions

### 7.1 Risks and pitfalls

1. **Soft timeouts in `run_r`** (E11): long C-level computations, `Sys.sleep()`, `system2()` cannot be interrupted by `setTimeLimit()`. Users can still press Esc/Ctrl-C at the same interrupt points R always offers. Mitigation: say "best effort" in the description; offer sub-process execution (callr/processx) only for code that does not need the live session.
2. **Regex dialect mismatch**: models trained on ripgrep may use Rust-regex-isms. Known differences: Rust `\d`/`\w`/`\b` are Unicode-aware (PCRE: ASCII unless `(*UCP)`); Rust rejects look-around and back-references while PCRE accepts them (harmless); an unescaped `{` that is not a quantifier is an error in Rust but a literal in PCRE (harmless). The schema description says "Perl-compatible regex".
3. **Character counting differs**: Pi's 500-character line cut uses UTF-16 code units, R uses code points — only astral characters differ. Byte limits are identical.
4. **Sorting differs from Pi's `ls`** for names with punctuation/accents: Pi uses ICU `localeCompare`, gptr a C-locale radix sort on `tolower()` (e.g. `_under.R` sorts before letters). Deterministic across platforms, which matters more.
5. **Fuzzy edit fallback rewrites touched lines in normalised form**: if `oldText` only matches after normalisation, the *replaced region's lines* lose trailing whitespace and typographic quotes even outside `oldText`'s exact span (Pi behaviour, kept). Untouched lines are preserved byte-for-byte.
6. **Uniqueness is checked in fuzzy space even for exact matches** (Pi behaviour, kept): two lines that differ only by trailing whitespace count as duplicates.
7. **Mixed line endings are normalised by `edit`** to the style of the first line ending; CR-only files become LF (Pi behaviour, kept).
8. **Encoding guesses**: invalid UTF-8 is assumed to be CP1252; a Shift-JIS or GBK file would be mis-decoded (shown as mojibake) and then re-encoded consistently by `edit`, so a round trip is still lossless for untouched bytes, but matching non-ASCII text will fail. A `.gptr` preference for a default legacy encoding could be added.
9. **Large files**: `read` loads the whole file to serve `offset`/`limit` (as Pi does); a multi-GB CSV would exhaust memory. Mitigation: for files above a threshold (e.g. 50 MB) read with `readLines(n = offset + limit)` on a connection, or refuse with a hint to use `data.table::fread(nrows=)` via `run_r` (REQ-10).
10. **Performance of pure-R search on very large trees** (≥ 100k files): expect seconds to tens of seconds. The walker has a `max_entries` guard (200,000) and both tools accept a `check_abort` callback. An optional accelerator (use `rg --json` when an `rg` binary already exists on PATH) would give identical output formatting but must stay optional.
11. **Output capture gaps**: text written by C code directly to the process' stdout/stderr (not through `Rprintf`), by child processes started with `system()` without `intern`, or by other sinks is not captured by `sink()`.
12. **`options(max.print = 5000)` / `width = 120` during `run_r`** change what users see if output is mirrored to the console; restored afterwards.
13. **Temp-file accumulation**: spill files of truncated outputs live in `tempdir()` until the session ends; long sessions with many truncated outputs could use noticeable disk space. Consider a cap (keep the last N).
14. **Security**: like Pi, the tools have no sandbox; `run_r` can do anything the R session can. Permission modes (REQ-37) must gate `mutates = TRUE` tools; `edit(dry_run = TRUE)` provides the diff to show in an approval prompt. Flag-injection into external binaries — the reason Pi passes `--` before patterns — does not exist in the pure-R search tools.
15. **`jsonlite::base64_enc()` newlines** (E7) would produce invalid image payloads for most providers if not stripped.
16. **`.gitignore` coverage gaps**: `.git/info/exclude`, global excludes file and `core.excludesFile` are ignored by the prototype; character-class edge cases (`[[:alpha:]]`) are untested.
17. **Typebox version**: JSON schemas were rendered with typebox 1.3.7 (found locally) while Pi pins 1.3.27; key order (`type`, `required`, `properties`) is LIKELY but not proven identical. It has no functional relevance. (Verifier: rendering Pi's `read`/`edit`/`ls` TypeBox definitions with the local typebox 1.3.7 gives exactly the key order `type, required, properties` and is byte-identical to the prototype's JSON; 1.3.27 itself was not available to test.)
18. **Hidden side effects on the live session** (found by the verifier): any tool helper that uses R's RNG (the prototype's original `.spill_file()` used `sample()`) silently changes the user's `.Random.seed`, so `set.seed()`-based analyses stop being reproducible once the agent has run a tool. Use `tempfile()` for names and add a regression test (`set.seed(1); <tool call>; runif(1)` must equal `set.seed(1); runif(1)`), alongside the existing sink/option/device checks.

### 7.2 Open questions for the design phase

* **Q1** Default tool set: seven tools (recommended) or Pi's four-tool minimum with grep/find/ls reachable only as R functions through `run_r`?
* **Q2** Tool name for R evaluation: `run_r` (proposed), `r`, or `eval`? Models see the name in every call; it must match `^[a-zA-Z0-9_-]{1,64}$`.
* **Q3** Should `edit`/`write` results include the diff for the *model* (Pi: no, only for the UI)? Recommendation: no (tokens), but show it to the user and store it in the history document.
* **Q4** Plot handling in interactive IDE sessions: capture only, or capture and replay into the user's device?
* **Q5** `run_r` engine: keep the ~120-line base-R evaluator or depend on `evaluate` (pure R, no dependencies) for robustness with knitr/htmlwidgets/S4 printing?
* **Q6** Parallel sub-agents sharing a working tree (REQ-33): file locking (`filelock`) or isolated working copies?
* **Q7** Windows default for the opt-in `shell` tool: Git Bash first (Pi's choice, models are most fluent in bash) or PowerShell first (always installed)?
* **Q8** Should `read` offer optional line numbers (`cat -n` style) for models that prefer line-addressed edits? Pi deliberately does not, and `edit` does not need them.
* **Q9** Should `ls` gain `sort` (name/mtime/size) like `find` to satisfy REQ-08 literally? The prototype keeps Pi's schema; adding the same enum is trivial.
* **Q10** Default legacy encoding and BOM policy for *new* files written on Windows (prototype: UTF-8 without BOM, always).

---

## 8. Sources

### Local source (Pi commit `1b347794e2a630e4359f2584f4eea388145d0ddf`, all read in full unless a line range is given)

* `pi/packages/coding-agent/src/core/tools/index.ts`, `read.ts`, `write.ts`, `edit.ts`, `edit-diff.ts`, `bash.ts`, `powershell.ts`, `grep.ts`, `find.ts`, `ls.ts`, `truncate.ts`, `output-accumulator.ts`, `path-utils.ts`, `file-mutation-queue.ts`, `tool-definition-wrapper.ts`, `render-utils.ts`, `renderers/bash.ts` (constants)
* `pi/packages/coding-agent/src/core/system-prompt.ts`, `bash-executor.ts`, `skills.ts:355-392`, `settings-manager.ts:205-252`, `sdk.ts:50-90, 250-300`, `agent-session.ts:1600-1660, 3400-3500`, `extensions/types.ts:325-355, 488-660`, `config.ts:439-453, 588-592`
* `pi/packages/coding-agent/src/cli/args.ts:125-170`
* `pi/packages/coding-agent/src/utils/paths.ts`, `shell.ts`, `child-process.ts`, `mime.ts`, `image-process.ts`, `image-resize.ts`, `image-resize-core.ts`, `image-convert.ts`, `text.ts`, `tools-manager.ts`, `ansi.ts`
* `pi/packages/coding-agent/src/extensions/codemode/tool.ts:80-196`, `tool-search/tool.ts:140-250`
* `pi/packages/coding-agent/docs/how-pi-works.md`, `usage.md`, `windows.md`, `cli.md:100-190`, `settings.md:33-56`
* `pi/packages/coding-agent/test/tools.test.ts`, `path-utils.test.ts`, `system-prompt.test.ts`, `tool-system-prompt-contributions.test.ts`, `builtin-tool-strict-mode.test.ts`, `powershell-tool.test.ts`, `default-tools-setting.test.ts`, `edit-tool-legacy-input.test.ts`, `suite/regressions/3302-find-path-glob.test.ts`, `3303-find-nested-gitignore.test.ts`, `6104-find-root-relativization.test.ts`
* `pi/packages/agent/src/agent-loop.ts:470-940`, `agent.ts:253`, `types.ts` (`AgentTool`, `AgentToolResult`, `toolExecution`), `harness/tools/*.ts`, `harness/system-prompt.ts`
* `pi/packages/ai/src/utils/validation.ts`, `utils/text.ts`, `api/constrained-sampling.ts`, `api/anthropic-messages.ts:126-160, 1220-1227`, `types.ts:702-736`

### Web (fetched 2026-09-29)

* fd README — https://raw.githubusercontent.com/sharkdp/fd/master/README.md (smart case, hidden/ignore defaults, `--full-path`)
* fd man page — https://raw.githubusercontent.com/sharkdp/fd/master/doc/fd.1 (`--hidden`, `--no-require-git`, `--glob`, `--max-results`, unordered output)
* fd source — https://raw.githubusercontent.com/sharkdp/fd/master/src/main.rs (`GlobBuilder::new(pattern).literal_separator(true)`, smart-case logic)
* fd changelog — https://raw.githubusercontent.com/sharkdp/fd/master/CHANGELOG.md (v8.4.0 trailing separator for directories; v8.7.0 `--no-require-git`; v9.0.0/v10.0.0 `.git` handling with `--hidden`)
* ripgrep guide — https://raw.githubusercontent.com/BurntSushi/ripgrep/master/GUIDE.md (automatic filtering, binary detection by NUL byte, `--sort`)
* ripgrep flag definitions — https://raw.githubusercontent.com/BurntSushi/ripgrep/master/crates/core/flags/defs.rs (`--glob` "always overrides any other ignore logic"; `--hidden` includes `.git`)
* jsdiff patch creation — https://raw.githubusercontent.com/kpdecker/jsdiff/master/src/patch/create.ts (`FILE_HEADERS_ONLY`, hunk header format, default context 4, no-newline marker)

### Experiments (all executed locally)

* `node schemas.mjs` — JSON schemas and descriptions rendered from the TypeBox definitions (typebox 1.3.7)
* `node sysprompt.mjs` — default system prompt reconstruction
* `rg …` runs of §2.13 (ripgrep 15.2.0)
* R probes `probe1.R` … `probe4.R`, `debug3.R`, `debug4.R`, package `enctest` installed into a private library (§2.14) — note (verifier): these probes contained raw UTF-8 bytes, not `\u` escapes, see E1/E2
* R prototype + tests + benchmarks (§5)

---

## Verification log

Adversarial fact-check performed 2026-09-29 by a verifier sub-agent, independently of the author's scratch outputs. Environment: same Pi clone (commit `1b347794…`, re-checked with `git log -1`), R 4.4.3 aarch64-apple-darwin20 via `Rscript --vanilla` (C locale unless noted), ripgrep 15.2.0, node v26.8.2 with a locally available typebox 1.3.7 (no npm/npx, no package installs into the user library). All verifier scripts are in `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-01/` (`extract.R`, `e-exp.R`, `esc.R`, `enctest*/`, `cmp-schemas.R`, `schemas-v.mjs`, `tok.R`, `sig.R`, `sp.R`, `rng.R`, `bench-v.R`, `rgt/`, `nul/`).

| # | Claim (section) | Verdict | Source / method |
|---|---|---|---|
| 1 | Pi commit `1b347794…`, packages `@earendil-works/pi-coding-agent` / `pi-agent-core` / `pi-ai` 0.99.1, `diff` 8.0.4, `typebox` 1.3.27 (header, §2.1) | confirmed | `git log -1`, `packages/*/package.json` |
| 2 | Exactly eight built-ins; default `read, bash, edit, write` (§1.1, §2.1) | confirmed | `CA/src/core/tools/index.ts:95-105, 164-180`, `settings-manager.ts:213` |
| 3 | `codemode` / `tool_search` registered but inactive (§1.1, §2.10) | confirmed | `extensions/codemode/index.ts:41`, `extensions/tool-search/index.ts:14` (`defaultActive: false`) |
| 4 | Only `content` + `isError` reach the model; text blocks joined with `\n`; image blocks become base64 `source` (§1.2, §2.2) | confirmed | `AI/src/api/anthropic-messages.ts:127-165, 1216-1223`; `AG/src/types.ts:423-446` |
| 5 | Error pipeline texts: `Tool X not found`, validation message format, `Tool execution was blocked`, `Operation aborted`, output-token-limit message (§1.3, §2.2) | confirmed | `AG/src/agent-loop.ts:473-495, 707-776, 820-912`; `AI/src/utils/validation.ts:317-350` |
| 6 | Limits 2000 lines / 51200 bytes / 500 chars; `formatSize`; spill file `os.tmpdir()/pi-bash-<16 hex>.log` (§1.4, §3.1) | confirmed | `truncate.ts:11-13, 47-69`; `output-accumulator.ts:26-28, 63-67`; `bash.ts:427` |
| 7 | `read`: raw UTF-8 decode, `split("\n")`, no line numbers, offset error text, notices; image sniff/resize constants (4100 bytes, 2000×2000, 4.5 MiB base64, qualities 80/85/70/55/40, ×0.75) (§1.5, §2.3, §3.2) | confirmed | `read.ts:14-190`; `utils/mime.ts`; `utils/image-resize-core.ts:22-29, 59-164`; `image-resize.ts:122`; `image-process.ts:69-91` |
| 8 | `edit` algorithm (fuzzy normalisation steps, fuzzy base for all edits, uniqueness in fuzzy space, overlap/no-change/line-count errors, BOM/CRLF handling) and all error texts (§1.6, §2.5, §3.4) | confirmed | `edit-diff.ts:11-362`; `edit.ts:21-215`; `tools.test.ts:1247-1258` |
| 9 | "`newText` is never normalised" (§2.5) | corrected | it is LF-normalised (`edit-diff.ts:305-308`), only never fuzzy-normalised |
| 10 | `prepareEditArguments` shim incl. "Opus 4.6, GLM-5.1" comment (§2.5) | confirmed | `edit.ts:103-134` |
| 11 | rg / fd argument vectors, `--no-require-git` rule, fd pinned 10.3.0 on darwin/x64, `PI_OFFLINE`, managed bin dir `~/.pi/agent/bin`, Termux hint (§1.7-1.8, §2.7-2.8) | confirmed | `grep.ts:162-166`; `find.ts:182-214`; `utils/tools-manager.ts:10-102, 265-267, 349-400`; `config.ts:556-592` |
| 12 | grep/find/ls output formats, notices, limits (100/1000/500), `ls` sort and stat rules (§2.7-2.9, §3.6-3.8) | confirmed | `grep.ts:120-330`; `find.ts:10-45, 140-295`; `ls.ts:11-150` |
| 13 | bash/powershell: timeout validation, non-zero exit returned as `isError`, 128+signal, shell resolution, legacy WSL `-s` + stdin, `taskkill`, PowerShell args + UTF-8 prefix, `PI_*` guideline on by default (§1.12, §2.6, §3.5) | confirmed; two empty-output details added | `bash.ts:22-60, 102-165, 188-260, 340-430`; `utils/shell.ts:20-135, 187-218`; `powershell.ts:16-46` |
| 14 | System prompt structure, rules order, sections, verbatim default prompt (§1.10, §2.11, §3.10) | confirmed; size clarified | `system-prompt.ts:1-216`; `AI/src/utils/text.ts:15-21`; recount: 359 words / 2,461 chars **with the `<PKG_DIR>` placeholder** |
| 15 | Context files `AGENTS.override.md`, `AGENTS.md`, `CLAUDE.md` (§2.11) | corrected (incomplete) | `resource-loader.ts:184` also accepts `AGENTS.MD`, `CLAUDE.MD`; project `SYSTEM.md`/`APPEND_SYSTEM.md` only when trusted (`:1200-1222`) |
| 16 | Harness copy in `packages/agent` has "identical schemas and descriptions" (§2.12) | corrected | `AG/src/harness/tools/bash.ts:12, 57` differ from `CA` bash (`bash.ts:41, 258`); read/edit/write identical; harness bash throws on non-zero exit (`:137-141`) confirmed |
| 17 | `truncateMiddle` "used by codemode" (§2.2) | corrected | only caller is `extensions/mcp/tools.ts:125`; codemode uses its own `truncateOutput` (`extensions/codemode/execute.ts:174-187`) |
| 18 | `makeStrictJsonSchema` behaviour; SDK tool precedence; strict-mode test (§2.1, §2.2) | confirmed | `AI/src/api/constrained-sampling.ts:48-117`; `CA/src/core/sdk.ts:264-270`; `CA/test/builtin-tool-strict-mode.test.ts:13-28` |
| 19 | `read`/`edit`/`ls` schemas byte-identical to Pi's (§1.13, §4.2) | confirmed | rendered Pi's TypeBox definitions with typebox 1.3.7 (`schemas-v.mjs`) and compared with the prototype's `jsonlite::toJSON` output: identical. Key order under 1.3.27 remains LIKELY |
| 20 | ripgrep oracle observations (§1.9, §2.13) | confirmed except one; one corrected, one nuanced | re-ran on a fresh tree (`rgt/`): `.gitignore` ignored outside repo, `.git/config` searched, positive glob overrides ignore, 3 submatches in one event, exit 1/2 confirmed; **`--glob 'sub/**'` is anchored at rg's process cwd** (matched nothing from the parent dir); NUL after offset 300,013 still yields earlier matches (`nul/`) |
| 21 | `--glob` "always overrides any other ignore logic"; `--hidden` includes `.git` (§2.13, §8) | confirmed | `rg --help` (15.2.0) |
| 22 | fd facts: trailing `/` for dirs since 8.4.0, `--no-require-git` since 8.7.0, `.git` with `--hidden` (9.0.0 ignore, 10.0.0 revert) (§2.8) | confirmed | fd `CHANGELOG.md` (GitHub raw, fetched 2026-09-29); fd runtime behaviour not testable (fd not installed) |
| 23 | jsdiff `FILE_HEADERS_ONLY` (no `Index:`/`===`), default context 4, no-newline marker (§2.5) | confirmed | jsdiff `src/patch/create.ts` (master; Pi pins 8.0.4 — LIKELY same) |
| 24 | E1 / E2: `\u` escapes not reliably marked UTF-8 (§1.16a, §2.14, §6.1, `00-utils.R` comment) | **corrected** | `esc.R` and `enctest/` (escape, installed under C and UTF-8, loaded under C and UTF-8): always `UTF-8`, `nchar` 4. Original probes (`track-01/proto/probe1.R`, `probe2.R`, `pkgtest/enctest/R/a.R`) contain raw bytes `c3 a9`, which reproduce the original numbers (`enctest2/`) |
| 25 | E3 error text (§2.14) | corrected (wording) | error is `invalid regular expression`, the code-point message is a PCRE *warning* |
| 26 | E4, E5, E6, E8, E9, E11 (incl. 2000×2000 `svd`: 18.6 s, not interrupted, no error afterwards), E12, E13, E14, E16, E17, E18, E19 (§2.14) | confirmed | `e-exp.R` and separate `svd` run, C locale |
| 27 | E7 / §1.16c: `base64_enc()` wraps every 76 chars | **corrected** | jsonlite 2.0.0 wraps every **72** chars; `base64enc::base64encode()` and `openssl::base64_encode()` produce no newlines (verified) |
| 28 | E10 timings (§2.14) | confirmed (interrupts); timings vary | 0.51 s / 1.04 s under heavy load |
| 29 | E15: `ignore.case` "silently" ignored with `fixed = TRUE` (§2.14) | **corrected** | R emits warning "argument 'ignore.case = TRUE' will be ignored" |
| 30 | Prototype: 1,535 lines, embedded sources identical to the files, base R + jsonlite (§1.14, §5) | confirmed | `extract.R` re-extracted all 10 files from the report; `diff -q` against `track-01/proto/` clean before edits; line counts 284+201+335+312+192+211 |
| 31 | 175 assertions pass in C and UTF-8 locales; 167 with optional packages blocked (§1.14, §5.1) | confirmed | re-ran from the extracted copies: 80/45/50 (C), 80/45/50 (`en_US.UTF-8`), 78/45/44 (blocked); re-run after the verifier's `.spill_file` fix: unchanged |
| 32 | Oracle "853 files, six patterns identical on Pi's own source tree" (§1.15, §5.1) | confirmed; scope corrected | test compares `packages/coding-agent` only, `file:line` pairs; reproduced 853 files and 74/26/541/169/27/62 lines |
| 33 | Benchmarks (0.4–0.5 s grep vs 0.04 s rg; §1.15, §5.2) | unverifiable | re-run under load avg ≈ 67 / 8 cores gave 1.1–3.5 s vs 0.12–0.38 s; counts (2,125 files, 247 dirs, 25.9 MiB, 679 finds) reproduced |
| 34 | §5.10 prompt "produced by the prototype" as its seven-tool default | confirmed text; framing corrected | `sp.R` reproduces it byte-for-byte only with explicit `selected =` seven tools; prototype `GPTR_DEFAULT_TOOLS` is the four-tool set (`05-registry.R:100`, asserted in `test-03.R:72`) |
| 35 | Schema token estimate ≈1,200 (read 152 … ls 99) (§4.1) | confirmed | `tok.R`: (description + JSON schema) chars / 4 = 151.75 … 99.25, total ≈1,218 (a heuristic, not a tokenizer count) |
| 36 | Function signatures in §4.5 | confirmed | `sig.R` (`formals()` of the prototype functions) |
| 37 | Prototype has no hidden side effects on the user's session (§6.1 implied) | **defect found and fixed** | `rng.R`: `.spill_file()` used `sample()` and changed `.Random.seed`; replaced by `tempfile()`; re-verified identical RNG stream |
| 38 | `I()` needed for one-element `required`/`enum`; `fromJSON(simplifyVector = FALSE)` (§4.2) | confirmed | jsonlite 2.0.0 run |
| 39 | `processx::run(stdout = <file>, stderr = "2>&1", cleanup_tree, windows_hide_window, error_on_status)` usable (§4.6) | confirmed | processx 3.8.6 `formals(run)`, `?process` ("2>&1"), runtime test (stdout+stderr interleaved into the file) |
| 40 | `cleanup_tree = TRUE` "uses a job object" on Windows (§6.2) | **corrected** | processx 3.8.6 `?process` `$kill_tree()`: environment-variable marking + `ps` package |
| 41 | `system2(timeout = 0.5)` ignored; `system2`/processx leave no children (§1.16e, §6.1) | confirmed / softened | `?system`: "Fractions of seconds are ignored", termination "is not guaranteed"; macOS test left no background `sleep` |
| 42 | `file.access(path, 2)` "documented as unreliable on Windows" (§6.2) | **corrected** | R docs (`?file.access`, r-source `file.access.Rd`) only warn against check-then-open races generally |
| 43 | Tool name must match `^[a-zA-Z0-9_-]{1,64}$` (§4.2) | updated | Anthropic "Define tools" page (platform.claude.com, 2026-09-29): `^[a-zA-Z0-9_-]{1,128}$`; 64 kept as conservative; other providers UNCERTAIN |
| 44 | `evaluate` pure R, no Imports, 1.0.5 (§4.7) | confirmed | `packageDescription("evaluate")`: 1.0.5, `NeedsCompilation: no`, no Imports |

Not verifiable here (left marked UNCERTAIN/LIKELY in the text): all Windows runtime behaviour (§1.12, §6.2); fd runtime semantics (fd not installed); typebox 1.3.27 key order; the Photon JPEG ladder / ×0.75 loop at runtime; absolute benchmark timings; how real models react to the `run_r` description; tool-name limits of non-Anthropic providers.
