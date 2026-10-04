# gptr

**An R-native AI agent harness for scientific computing.**

gptr 1.0 is being built to bring AI agents into the R session where your data,
models and analyses already live. Its central idea is simple: let R do the
computation, let models help with reasoning and decisions, and keep the work in
documents that scientists can inspect, edit and rerun.

**Status: 1.0 is in development.** The capabilities below describe the accepted
design, not a completed release. See the [implementation progress](dev/PROGRESS.md)
for completed work and verification evidence.

The former 0.x ChatGPT interface, including `get_response()` and
`dataframe_to_text()`, is superseded in this source branch. This is a breaking
redesign; the source branch and a published CRAN release may expose different
APIs. Installation and usage instructions for the new harness will accompany a
validated implementation.

## The workflow we are building

Load a dataset or a large scientific object into R, ask the agent to investigate
it, inspect the results, and steer the next step. The agent works in the selected
R environment, so useful intermediate objects remain available for your own
code. Prompts, concrete R code and typed model decisions can be combined using
ordinary R functions, pipes, loops and conditionals.

The planned `gptr()` gateway serves both interactive conversation and
programmatic workflows. The same design targets terminal R, RStudio, Positron,
R Markdown, Quarto and Jupyter with IRkernel, with plots and Shiny applications
as analysis outputs.

## Design principles

- **Work with live objects.** Inspect large objects through compact, class-aware
  descriptions and compute on them in R. Copy-safety rules aim to prevent the
  harness from retaining references that cause unnecessary large copies; they
  do not eliminate copies required by an analysis itself.
- **Use the right kind of model.** Combine conversational and reasoning models
  ("System 2") with native typed decision models ("System 1") for logical
  decisions, choices and scores. Typed results fit R control flow; a model's
  reported confidence is not proof of scientific correctness or calibration.
- **Keep provider choice open.** gptr owns its transport and provider adapters.
  The design includes cloud APIs, compatible endpoints and local Ollama models,
  with capability checks for each model and a public extension API for others.
- **Make the workflow inspectable.** Record code, prompts, decisions and relevant
  provenance in `.R`, `.Rmd`, `.qmd` and `.ipynb` documents. Recorded responses
  support replay without a model call; replay must report missing records.
  Scientific reproducibility also requires suitable data, dependencies, seeds
  and validation of results in a fresh session.
- **Measure efficiency.** Keep bulk data out of model context, compose operations
  in R, bound tool output and reuse provider caches where supported. Track
  tokens, cost and time alongside task correctness. Early research fixtures
  motivate these choices; real-world savings remain to be established.
- **Make capabilities extensible.** Built-in providers, tools, skills, document
  formats and front ends use the same versioned plugin API planned for external
  R packages. MCP and subagents extend the workflows available to scientists.

## Local models with Ollama

Ollama is a first-class optional provider in the 1.0 design, covering two
different roles:

| Role | Planned support |
|---|---|
| Conversation and agent execution | Installed conversational models, with tools, images and other features enabled only when supported |
| Native typed decisions | Clef and Clef Flash through Ollama's native decision API, alongside hosted Jev decisions |

Clef and Clef Flash require Ollama 0.35.1 or later. They produce decisions rather
than running a conversational agent loop. Ollama and model weights are external,
optional requirements; the package will not install them or download models
automatically.

The default Ollama policy is local-only, with explicit checks for inference
locality and no automatic cloud fallback. A local model does not make a workflow
local if another step sends data to a cloud model or network tool. The full
[Ollama design amendment](dev/spec/07-local-ollama.md) specifies routing,
capabilities, privacy controls, decision semantics and validation.

## Development and contributions

The target is an ordinary cross-platform R package, with R >= 4.2.0, no compiled
code in v1, and no Node.js or Python runtime requirement for core functionality.
Optional integrations have their own dependencies. CRAN readiness is a release
gate, not a claim about the current development branch.

Start with these documents:

- [Vision and requirements](dev/spec/00-vision-brief.md)
- [Architecture](dev/spec/03-architecture.md) and
  [interface contract](dev/spec/04-interface-contract.md)
- [Implementation plans and milestone gates](dev/plan/00-index.md)
- [Progress and verification](dev/PROGRESS.md)
- [Development rules](CLAUDE.md) and [implementation conventions](dev/plan/00-conventions.md)

Contributions should follow the plan dependencies and include focused
verification. Tests use offline providers by default; live tests are explicit
opt-ins. Keep credentials and private data out of source, examples and reports.
In-process R execution is not a security sandbox: the design includes permission
controls and recovery mechanisms, while scientific decisions remain reviewable
by the user.

Questions and proposals are welcome in
[GitHub issues](https://github.com/Broccolito/gptr/issues).

Maintained by [Wanjun Gu](mailto:wanjun.gu@ucsf.edu). Licensed under the
[MIT license](LICENSE.md).
