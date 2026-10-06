# gptr

**An R-native AI agent harness for scientific computing.**

gptr brings AI agents into the R session where your data, models and analyses already live: R does
the computation, models help with reasoning and decisions, and the work is kept in documents that
scientists can inspect, edit and rerun.

**Status.** gptr 1.0 is under development and replaces the 0.x ChatGPT interface (`get_response()`,
`dataframe_to_text()`). Today `peter()` runs agent sessions that compute on your R objects with
cloud and local Ollama models, and returns typed System 1 decisions; see [progress](dev/PROGRESS.md).

## Example

```r
library(gptr)
s = peter("Fit mpg against weight and summarise the fit.", mtcars, model = sonnet)
s$text
s = s |> peter("Now add horsepower and compare the two models.")
s$usage
peter$describe(mtcars)
```

Context objects are read where they live, never copied, and objects the agent creates stay in your
session. R code runs in your R process, which is not a security sandbox; the `mode` argument sets
which actions need your approval. `gptr_fake_provider()` runs the same code offline.

## Why `peter()`?

The package is `gptr`; you talk to its agent through `peter()`. The name honours two Peters:

- **Peter Cathcart Wason** (1924-2003), the cognitive psychologist whose work on human
  reasoning, with Jonathan Evans, framed the dual-process view later known as "System 1" and
  "System 2" thinking. gptr joins both kinds of model in one agent flow: fast, typed System 1
  decisions inside R control flow, and System 2 reasoning models that plan and write code.
- **Peter Naur** (1928-2016), whose name the Backus-Naur form carries: a notation for writing
  down the syntax of programming languages. In that spirit, gptr records agent sessions as
  ordinary documents - R scripts, R Markdown and Quarto files, Jupyter notebooks - that can be
  read, edited and replayed.

## Design principles

- **Work with live objects.** Large objects get compact, class-aware descriptions
  (`gptr_describe()`) and are computed on in R; the harness holds no references that force copies.
- **Use the right kind of model.** Conversational and reasoning models ("System 2") plan and write
  code; native typed decision models ("System 1") return logical, choice and score vectors for R
  control flow.
- **Keep provider choice open.** gptr owns its transport and adapters for cloud APIs, compatible
  endpoints and local Ollama models, checks each model's capabilities, and takes new providers
  through `gptr_provider()`.
- **Make the workflow inspectable.** Code, prompts, decisions and provenance are recorded in `.R`,
  `.Rmd`, `.qmd` and `.ipynb` documents; recorded responses replay without a model call.
- **Measure efficiency.** Bulk data stays out of model context, tool output is bounded and provider
  caches are reused; `gptr_usage()` reports tokens, cost and time.
- **Make capabilities extensible.** Providers, tools, skills, document formats and front ends use one
  versioned plugin API that other R packages can use too, with MCP and subagents.

## Local models with Ollama

Ollama is a first-class optional provider with two roles:

| Role | Support |
|---|---|
| Conversation and agent execution | Installed conversational models, with tools, images and other features enabled only when supported |
| Native typed decisions | Clef and Clef Flash through Ollama's native decision API, alongside hosted Jev decisions |

Clef and Clef Flash require Ollama 0.35.1 or later and return decisions, not a conversational agent
loop. Ollama and model weights are optional external requirements; gptr never installs them or
downloads models.

The default Ollama policy is local-only, with explicit checks for inference locality and no
automatic cloud fallback. A local model does not make a workflow local if another step sends data
to a cloud model or network tool. The [Ollama design amendment](dev/spec/07-local-ollama.md)
specifies routing, capabilities, privacy controls, decision semantics and validation.

## Development

gptr is pure R (R >= 4.2.0, no compiled code in v1). Start with the
[plan index](dev/plan/00-index.md), the [interface contract](dev/spec/04-interface-contract.md) and
the [development rules](CLAUDE.md). Tests are offline; live tests run only with
`GPTR_LIVE_TESTS=true`. Run a filtered subset with user state isolated:

```sh
R_LIBS_USER=<lib> Rscript --vanilla dev/ci/isolated-check.R test <filter>
```

Questions and proposals are welcome in [GitHub issues](https://github.com/Broccolito/gptr/issues).
Maintained by [Wanjun Gu](mailto:wanjun.gu@ucsf.edu). Licensed under the [MIT license](LICENSE.md).
