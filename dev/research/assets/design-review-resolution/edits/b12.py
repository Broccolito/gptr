from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `ctx$redact(x, profile = "persist")` | redacted `x` | P03 |
| `ctx$secret(name)` | a handle or `NULL` | P03 |""",
"""| `ctx$redact(x, profile = "persist")` | redacted `x` | P01 `redact_hook()` (P03 installs `redact()`, IC-34) |
| `ctx$secret(name)` | a handle or `NULL` | `secret.lookup` (P03) |"""),
("""  settings.local.json              P08/P11        ignored     personal: remembered permissions, transcript target (§11.3)""",
"""  settings.local.json              user           ignored     legacy: only deny/ask additions, only when trusted (§11.3, IC-52)"""),
("""  cache/s1/<2hex>/<sha256>.json    P13            committed   System 1 answers (input hashes only; §11.9)""",
"""  cache/s1/<2hex>/<sha256>.json    P13            committed   System 1 answers (salted input hashes only; §11.9)
  cache/s1/salt                    P13            committed   per-project salt of the S1 hashes (IC-70)"""),
("""  cache/tmp/                       P01            ignored     spill files, wire log, deferred-write sidecars (pruned after 7 days)""",
"""  cache/tmp/                       P01            ignored     spill files, per-session wire logs (pruned after 7 days); deferred-write sidecars (never pruned automatically, IC-51)"""),
("""  transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R  P15  committed  console transcripts (§11.5)
  locks/<sha1 of document path>/pid  P15          ignored     document locks (30 s stale timeout)""",
"""  transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R  P15  ignored  console transcripts (§11.5; ignored by default, IC-70)
  locks/<sha1 of path_key(document path)>/pid  P15  ignored  document locks (pid + creation time; stale when the pid is dead or after 30 s, IC-71)"""),
("""locks/
*.lock/
settings.local.json
```""",
"""locks/
*.lock/
settings.local.json
transcripts/
```"""),
("""User level: `tools::R_user_dir("gptr", "config")` holds `settings.json`, `auth.json` (0600), `trust.json`,
`mcp.json`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `skills/`, `agents/`, `prompts/`, `extensions/`;
`tools::R_user_dir("gptr", "cache")` holds `models.json` + `models.etag`, `mcp-tools/`, `mcp-era/`, `mcp-logs/`
(5 MB rotation).""",
"""User level: `tools::R_user_dir("gptr", "config")` holds `settings.json`, `auth.json` (0600), `trust.json`,
`mcp.json`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `skills/`, `agents/`, `prompts/`, `extensions/` and
`projects/<16 hex>.json` (per-project remembered permission answers, transcript target and record consent, keyed
by `sha256(path_key(root))`, IC-52); `tools::R_user_dir("gptr", "cache")` holds `models.json` + `models.etag`,
`mcp-tools/`, `mcp-era/`, `procs/` (process tree markers for the orphan sweep, IC-60) and, only with
`gptr.mcp_debug`, `mcp-logs/` (5 MB rotation; otherwise MCP logs live in `tempdir()/gptr/mcp-logs/`, IC-70)."""),
("""Layers, lowest to highest: package defaults < user `settings.json` < project `.gptr/settings.json` <
`.gptr/settings.local.json` < `options(gptr.*)` < `gptr_config(.scope = "session")` < call arguments. An
**untrusted** project contributes only changes that tighten `tighten`-type settings (a stricter `mode`, added
`permissions.deny`/`permissions.ask` rules, a stricter `context`); a **trusted** project contributes every key, but
`tighten`-type settings still only tighten and project `permissions.allow` rules never loosen `plan` or pre-approve
level 4. `egress` is read only from the user file.""",
"""Layers, lowest to highest: package defaults < user `settings.json` < project `.gptr/settings.json` < the
user-level project file `projects/<hash>.json` (IC-52) < `options(gptr.*)` < `gptr_config(.scope = "session")` <
call arguments. An **untrusted** project contributes only changes that tighten `tighten`-type settings (a stricter
`mode`, added `permissions.deny`/`permissions.ask` rules, a stricter `context`, `record = "off"`); a **trusted**
project contributes every key, but `tighten`-type settings still only tighten and project `permissions.allow`
rules never loosen `plan` or pre-approve level 4. A legacy `.gptr/settings.local.json` contributes only
deny/ask additions and only in a trusted project. `egress` is read only from the user file. Safety options are
snapshotted per run (IC-53)."""),
("""| `transcript` | chr | `"ask"` (`"file"`, `"active-document"`, `"off"`) | | P15 |""",
"""| `transcript` | chr | `"ask"` (`"file"`, `"active-document"`, `"off"`); the chosen target is stored in the user-level project file and validated (inside the project, `.R`/`.Rmd`/`.qmd`/`.ipynb`, not a control or protected path; IC-52) | | P15 |"""),
("""| `subagents` | `{max_depth, max_active, max_workers, max_cli}` | `{max_depth: 1, max_active: 8, max_workers: null, max_cli: 4}` | | P19 |""",
"""| `subagents` | `{max_depth, max_active, max_workers, max_cli, max_tasks}` (options `gptr.subagents.<key>` are the same knobs, IC-71) | `{max_depth: 1, max_active: 8, max_workers: null, max_cli: 4, max_tasks: 8}` | | P19 |"""),
("""| `budget` | `{tokens, cost, turns}` | all `null` | | P06 |""",
"""| `budget` | `{tokens, cost, turns}` | `{tokens: 2000000, cost: 5, turns: null}` per top-level call (IC-66); `null` set explicitly disables a limit | | P06 |"""),
("""| `ui` | chr\\|null | `null` | | P11 |""",
"""| `ui` | chr\\|null | `null` | | P11 |
| `frontend` | chr\\|null | `null` (`console`) | | P14 |
| `store`, `evaluator` | chr | `"jsonl"`, `"r"` (registered `store` and `evaluator` records, IC-69) | | P06, P09 |"""),
("""### 11.3 `settings.local.json`

```json
{"version": 1,
 "permissions": {"allow": ["r(fn:FindNeighbors,FindClusters)"], "ask": [], "deny": []},
 "transcript": {"target": ".gptr/transcripts/gptr-session-20260929-183000.R"},
 "record": {"analysis.R": "auto"}}
```""",
"""### 11.3 The user-level project file (IC-52)

`R_user_dir("gptr", "config")/projects/<first 16 hex of sha256(path_key(project root))>.json`, written under a
short file lock; never in the project tree, so it cannot arrive by clone:

```json
{"version": 1, "root": "/Users/me/project",
 "permissions": {"allow": ["r(fn:FindNeighbors,FindClusters)"], "ask": [], "deny": []},
 "transcript": {"target": ".gptr/transcripts/gptr-session-20260929-183000.R"},
 "record": {"analysis.R": "auto"}}
```

A legacy `.gptr/settings.local.json` of the same shape contributes only its `permissions.deny`/`ask` entries, and
only in a trusted project; its allow, transcript and record keys are ignored with a notice."""),
("""`<workspace root>/sessions/<YYYYmmddTHHMMSS>_<session id>.jsonl`: the header line (§4.7), then entries (§4.6),
one JSON object per line, written by one kept-open `file(path, "ab")` connection, each line inside
`suspendInterrupts()` and flushed, `persist`-redacted at ingress, never rewritten. The first entry of every session
is `gptr.frozen`. A fork's file is created at its first own message and starts with the copied path (ids kept,
`parentId` re-chained). Readers tolerate a torn last line. Lock: directory `<file>.lock/` with a file `pid`; a lock
whose pid is not alive (`ps`) or older than 24 h without heartbeat is stale.""",
"""`<workspace root>/sessions/<YYYYmmddTHHMMSS>_<session id>.jsonl`: the header line (§4.7), then entries (§4.6),
one JSON object per line, appended open-append-close (`file(path, "ab")` opened, written, flushed and closed per
entry or per batch inside `suspendInterrupts()`; no connection outlives a gptr call; IC-59), `persist`-redacted
at ingress, never rewritten (except by an explicit `gptr_scrub(dry_run = FALSE)`, IC-70). The first entry of every
session is `gptr.frozen`. A fork's file is created at its first own message and starts with the copied path (ids
kept, `parentId` re-chained). A resume on a file whose last byte is not LF first appends `"\\n"` and a
`gptr.recovered` entry; readers skip any unparsable line with a diagnostic. Lock: directory `<file>.lock/` with a
file `pid` holding the pid and the process creation time, touched every 10 minutes while the session is live; a
lock is stale when `pid_alive()` (ps) is `FALSE` or its heartbeat is older than 24 h."""),
("""| `status` | undone blocks | `undone` |""",
"""| `status` | undone blocks | `undone` |
| `args` | when the prompt was interpolated | 8 hex of sha256 of the sorted interpolated `name=value` pairs; part of freshness (IC-45) |
| `kind` | team and fan-out blocks | `team` or `fanout` (IC-47) |
| `children` | team and fan-out blocks | `"<name>:<session id>,..."` (quoted) |"""),
("""**Body**, in emission order: the code of each successful `r` call with `record = TRUE`, verbatim; after each such
call that printed something,""",
"""**Body**, in emission order: the code of each successful `r` call with `record = TRUE`, verbatim except that
top-level `gptr_return()` calls and calls of `record = FALSE` members are dropped and top-level `<-` is rewritten to
`=` where safe (IC-48); `## Steer: <text>` and `## Follow-up: <text>` lines for steering delivered during the turn
(excluded from `prompt` and `sha`, IC-49); after each such call that printed something,"""),
("""Code passes `code_for_history()` (literal secrets -> `Sys.getenv("NAME")`). Failed executions are not recorded.
Overlay-fork turns are wrapped `local({ ... }, envir = gptr_resume("<id>")$envir)`.""",
"""Code passes `code_for_history()` (literal secrets -> `Sys.getenv("NAME")`). Failed executions and plan-mode code
are not recorded (a plan-mode turn gives one `## Plan: <plans path>` line). Overlay-fork turns are wrapped
`local({ ... }, envir = gptr_resume(block = "<block id>")$envir)` (IC-46). Team and fan-out blocks hold one
`## Agent <name> (<model>): <first line>` line per child and, for children with exports, the child's code wrapped
`local({ ... }, envir = gptr_resume(block = "<id>", child = "<name>")$envir)` plus one
`<export> = gptr_resume(block = "<id>", child = "<name>")$envir$<export>` line per export (IC-47)."""),
("""| transcript | `.gptr/transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R`: a header comment (`# gptr session <id> -- started <time>`, `# machine log: <jsonl path>`, `# source() this file to replay ...`), `library(gptr)`, then each prompt as `gptr("...")` with its block; direct R lines under `# direct R (no model)` with `#>` output; slash commands as comments (`# /model opus`) |""",
"""| transcript | `.gptr/transcripts/gptr-session-<YYYYmmdd-HHMMSS>.R`: a header comment (`# gptr session <id> -- started <time>`, `# machine log: <jsonl path>`, `# source() this file to replay ...`), `library(gptr)`, then the first prompt as `s_<6 hex> = gptr("...")` and later prompts as `s_<6 hex> \\|> gptr("...")`, each with its block (IC-49); direct R lines under `# direct R (no model)` with `#>` output; slash commands as comments (`# /model opus`) |"""),
("""| `.ipynb` | a code cell `{"cell_type": "code", "execution_count": null, "id": "gptr-<id>", "metadata": {"gptr": {"id", "model", "prompt", "date", "session", "turn", "value"}}, "outputs": [], "source": [...]}` after the calling cell; keys sorted; indentation copied from the file (Jupyter: 1 space); floats in Python repr; only `source` and `metadata.gptr` change on rewrite; never written while the notebook is open |""",
"""| `.ipynb` | a code cell `{"cell_type": "code", "execution_count": null, "id": "gptr-<id>", "metadata": {"gptr": {"id", "model", "prompt", "date", "session", "turn", "value"}}, "outputs": [], "source": [...]}` after the calling cell; keys sorted; indentation copied from the file (Jupyter: 1 space); floats in Python repr; only `source` and `metadata.gptr` change on rewrite; never written while the notebook is open: in Jupyter the block is shown as the cell output and kept pending until `gptr_doc(path, sync = TRUE)` (IC-50) |"""),
("""<root>/artifacts/<id>/vNNN/R/gptr_data.R    loader: data = lapply(<names>, function(n) readRDS(file.path("data", paste0(n, ".rds"))))
<root>/artifacts/<id>/vNNN/data/<name>.rds  snapshots via save_rds(compress = FALSE) (ignored)
<root>/artifacts/<id>/run/run.json          {pid, port, url, version, started} (ignored)
<root>/artifacts/<id>/run/port              the child's port, published by atomic rename (ignored)
<root>/artifacts/<id>/run/app-vNNN.log      child stdout/stderr, stream-redacted (ignored)""",
"""<root>/artifacts/<id>/vNNN/R/gptr_data.R    loader: reads data/<file> for each name listed in artifact.json (IC-63)
<root>/artifacts/<id>/vNNN/data/001.rds     snapshots via save_rds(compress = FALSE), numbered (ignored)
<root>/artifacts/<id>/run/run.json          {pid, port, url, version, started} (ignored; the URL carries the token)
<root>/artifacts/<id>/run/port              the child's port, published by atomic rename (ignored)
<root>/artifacts/<id>/run/app-vNNN.log      child stdout/stderr read by the parent and appended with persist redaction (ignored; IC-70)"""),
("""`artifact.json`: `{"id", "title", "kind": "shiny" | "html", "versions": [{"n", "created", "app_sha",
"data": [{"name", "class", "dim", "bytes"}], "session", "checks": {"parse", "launch", "http", "session"}}],
"current": int, "port": int | null, "created", "updated"}`. Ids match `^[a-z0-9][a-z0-9-]{0,62}$`.""",
"""`artifact.json`: `{"id", "title", "kind": "shiny" | "html", "versions": [{"n", "created", "app_sha",
"data": [{"name", "file", "class", "dim", "bytes"}], "session", "checks": {"parse", "launch", "http", "session"}}],
"current": int, "port": int | null, "created", "updated"}`. Ids match `^[a-z0-9][a-z0-9-]{0,62}$` and are not a
Windows reserved device name (`con`, `aux`, `nul`, `prn`, `com1`-`com9`, `lpt1`-`lpt9`; IC-63)."""),
("""Placeholders `${VAR}`, `${VAR:-default}`, `${env:VAR}`,
`${workspaceFolder}`, `${userHome}` are expanded at connect time,""",
"""Placeholders `${VAR}`, `${VAR:-default}`, `${env:VAR}`,
`${workspaceFolder}`, `${userHome}` (= `user_home()`, IC-63) are expanded at connect time,"""),
("""Every value read is registered in the vault at once; access tokens stay in memory. `trust.json`:
`{"version": 1, "projects": {"<normalised project path>": {"trusted": true, "date": "2026-09-29",
"base_url_confirmed": {"<provider>": "<url>"}}}}`.""",
"""Every value read is registered in the vault at once; access tokens stay in memory. `trust.json`:
`{"version": 1, "projects": {"<path_key of the project root>": {"trusted": true, "date": "2026-09-29",
"fingerprint": "<sha256 of the trust-gated files>", "base_url_confirmed": {"<provider>": "<url>"}}}}` (IC-52;
written under a short file lock)."""),
("""| System 1 (P13) | memory (`the$s1_cache`) before a workspace; then `<root>/cache/s1/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 1L, endpoint, model, question, type, criteria, input)))` per element (`input` = the state; alias models keyed by the alias string) | `{"key", "model" (physical), "alias", "question", "input_sha256", "answer", "prob", "probabilities", "confidence", "date", "usage": {"input_tokens", "output_tokens"}}`; never the input; mtime touched on hit |
| System 2 answers (P15) | `<root>/cache/s2/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 1L, doc = <path relative to root>, block = <id>, prompt = <prompt hash>)))` | `{"block", "doc", "prompt", "model", "answer" (redacted final text), "usage", "cost", "session", "turn", "date"}` |""",
"""| System 1 (P13) | memory (`the$s1_cache`) before a workspace; then `<root>/cache/s1/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 2L, salt, endpoint, model, question, type, criteria, input)))` per element (`salt` from `cache/s1/salt`; `input` = the state; alias models keyed by the alias string) | `{"key", "model" (physical), "alias", "question_sha256", "input_hash" (salted), "answer", "prob", "probabilities", "confidence", "date", "usage": {"input_tokens", "output_tokens"}}`; never the input or the question text (IC-70); mtime touched on hit |
| System 2 answers (P15) | `<root>/cache/s2/<2hex>/<sha256>.json` | `hash_sha256(canonical_json(list(schema = 2L, doc = <path relative to root>, block = <id>, part = <"" \\| child name \\| "n<ordinal>">, prompt = <prompt hash>, args = <args hash or "">)))` (IC-45, IC-47) | `{"block", "doc", "part", "prompt", "model", "answer" (redacted final text), "usage", "cost", "session", "turn", "date"}` |"""),
("""| Deferred document writes (P15) | `<root>/cache/tmp/pending-<sha1(doc path)>.R` | document path | the pending new document text |""",
"""| Deferred document writes (P15) | `<root>/cache/tmp/pending-<sha1(path_key(doc path))>.rds` | document path | `list(doc, base_md5, upserts = list(list(block_id, lines, site)), session, pid, time)` (IC-51); never pruned automatically |"""),
("""Spec file (written with `save_rds()`): `list(prompt, model, mode, depth, agent = <spec:agent>, objects = named
list (values shipped by name), export = chr, preset, rng_stream, settings = list, env_profile = "worker")`.""",
"""Spec file (written with `save_rds()`): `list(prompt, model, mode, depth, agent = <spec:agent>, objects = named
list (values shipped by name), export = chr, preset, rng_state, settings = list, env_profile = "worker", registry =
list(specs, plugins, filters))` (IC-69; the worker re-registers `registry` before running)."""),
("""`inst/extdata/risk-functions.csv`: columns `package`, `function`, `level` (0-4), `category` (`read`, `object_write`,
`file_write`, `file_delete`, `network`, `process`, `install`, `dynamic`, `session`, `secret`, `interactive`,
`critical`), `path_arg` (the argument holding a path, or empty), `note`. `inst/extdata/risk-commands.csv`:
`command`, `subcommand` (or `*`), `level`, `category`, `note` (G5 levels). Plugins extend both through `setting`
specs `risk.functions` / `risk.commands` (data frames of the same columns).""",
"""`inst/extdata/risk-functions.csv`: columns `package`, `function`, `level` (0-4), `category` (`read`, `object_write`,
`file_write`, `file_delete`, `network`, `process`, `install`, `dynamic`, `session`, `secret`, `interactive`,
`critical`, `control` (IC-53)), `path_arg` (the argument holding a path, or empty), `note`; plus a `packages` table
of risky packages whose unlisted functions are at least level 2 (IC-54). An unlisted function of a package outside
base, stats, utils, methods, graphics, grDevices and tools is level 1. `inst/extdata/risk-commands.csv`:
`command`, `subcommand` (or `*`), `level`, `category`, `note` (G5 levels). Plugins and users extend both through
additive `risk_rule` records (§10.2 row 33; the highest level wins on duplicates, lowering needs `lower = TRUE`)."""),
]
apply(P, pairs)
