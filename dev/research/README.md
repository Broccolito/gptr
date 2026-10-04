# gptr research reports

Primary-source research behind the gptr 1.0 design (2026-09-29/30). Start with `00-digest.md`: one section per
report with its summary, design implications, risks, open questions and the fact-checker's corrections. Open a
full report only for the exact specifications and verified prototypes you need.

## How to read a report

- Every report ends with a **Verification log** written by an independent adversarial fact-checker, who re-ran
  the prototypes and checked the load-bearing claims. **Corrections in the log override the body.**
- Claims are labelled VERIFIED (evidence seen by the author), LIKELY, or UNCERTAIN.
- Prototype code is embedded verbatim in each report. It often uses `<-`; convert it to the house style (`=` for
  assignment, `|>` for pipes; see `dev/plan/00-conventions.md`) when copying it into the package.
- Absolute paths under `/private/tmp/claude-501/.../scratchpad/...` record where an experiment ran. That scratch
  space was temporary and is gone. The code is embedded in the report, and the artifacts that specs and plans
  reference were copied to `assets/` (see `assets/README.md`).
- Pi citations (`packages/.../file.ts:line`) refer to <https://github.com/earendil-works/pi> at commit
  `1b347794`.

## Index

| Report | Topic |
|---|---|
| 01 | Pi's built-in tools; pure-R read/write/edit/grep/find/ls prototype |
| 02 | Pi's agent loop, events, retry, compaction, session format; R loop, interrupts, steering |
| 03 | Pi's unified provider layer, wire formats, OAuth; R SSE and partial-JSON parsers |
| 04, 04a | System One models and the TypeSafe Jev API (04a: live verification from R) |
| [04b](04b-ollama-local-models.md) | Ollama local chat and Clef decisions: official contracts, capabilities, locality and validation expectations |
| 05 | Pi's extensions, skills, prompt templates, settings, trust, modes |
| 06 | Pi's sub-agents, MCP client, tool search, codemode |
| 07 | Anthropic Messages API; the Claude plan through Claude Code |
| 08 | OpenAI Responses/Chat Completions; the ChatGPT plan (Sign in with ChatGPT, Codex) |
| 09 | Gemini, OpenAI-compatible providers, local models, model catalog |
| 10, 10a | R LLM ecosystem survey; critical review of its infrastructure and INFRA-01..28 |
| 11 | Pure-R file tools: benchmarks and implementations |
| 12 | R evaluation tool, environment introspection, copy-safety, NSE, pipe semantics |
| 13 | CRAN compliance checklist C-01..C-58 |
| 14 | Script-as-harness and script-as-history (.R, .Rmd, .qmd, .ipynb) |
| 15 | Concurrency and sub-agents in R: the curl-multi reactor |
| 16 | MCP protocol (both eras), MCP in R, Agent Skills, plugin formats |
| 17 | Shiny artifacts |
| 18 | Console REPL, interrupts, permission modes, ask-user |
| 19 | High-performance R recommendations; harness internals benchmarks |
| 20 | Feature survey of Claude Code, Codex and other harnesses; apply_patch |
| 21 | Rcpp hot paths (verdict: none needed in v1) |
| G1 | Extensibility / SDK surface (S-11) |
| G2 | Token-efficiency measurements and benchmark design (S-12) |
| G3 | The session object and pipe steering (S-8) |
| G4 | Context assembly, prompt caching, compaction |
| G5 | R as token-efficient polyglot glue |
| G6 | Secrets and redaction end to end |
| G7 | Checkpoints, undo and rewind |
