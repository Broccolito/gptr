
<!-- README.md is generated from README.Rmd by dev/release/precompute.R; edit README.Rmd. -->

# gptr <picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Broccolito/gptr/main/man/figures/logo-dark.png"/><img src="https://raw.githubusercontent.com/Broccolito/gptr/main/man/figures/logo.png" align="right" width="120" height="139" alt="gptr logo"/></picture>

gptr runs language model agents inside your live R session. The agent
works on the objects that are already in memory: it inspects them, runs
R code on them and leaves its results in your workspace, so a large
object is loaded once and a mistake costs one re-evaluation instead of a
fresh run of the whole script. One function, `peter()`, is an
interactive chat in the console and a programmable call that you put in
scripts, loops and `if` statements.

Peter's name honors Peter Naur and Peter Cathcart Wason: readable
programs and careful reasoning. See [Why Peter?](#why-peter) and
`vignette("why-peter", package = "gptr")`.

- **One gateway.** `peter()` with no prompt opens a chat at the console;
  with a prompt it runs the agent and returns the session, which the
  pipe steers: `peter("...") |> peter("...")`.
- **System 1 and System 2.** Generative models (Anthropic, OpenAI,
  Google Gemini, any OpenAI-compatible endpoint, local Ollama models,
  and the Claude and ChatGPT plans through the `claude` and `codex`
  command-line tools) work next to typed decision models such as
  TypeSafe AI's Jev and Clef on a local Ollama server, whose yes/no,
  choice and score answers go straight into `if` and `for`.
- **The script is the history.** gptr can record executed agent code
  into your `.R`, `.Rmd`, `.qmd` or `.ipynb` document. Fresh recorded
  blocks replay without model calls.
- **Everything is R.** Tools are R functions; artifacts are Shiny apps;
  skills, MCP servers, sub-agents, hooks and plugins use one documented
  extension API.
- **Safe defaults.** In the default `manual` mode only actions known to
  be read-only run without asking; changes ask unless an applicable
  allow rule permits them. The permission gate is not a sandbox: see
  `?gptr_security`.

## Installation

These guides describe the 1.0 development version. Install it from
GitHub with R 4.2 or later:

``` r
install.packages("pak")  # if pak is not installed
pak::pak("Broccolito/gptr")
```

`install.packages("gptr")` installs the CRAN version, which may still
expose the older 0.7 API. Check `packageVersion("gptr")` before
following these examples. No model server or CLI is required for the
offline examples below.

For an interactive first session, install and sign in to Codex CLI or
Claude Code outside gptr, then call `peter()`. When no default model is
configured, Peter offers the two CLI routes or manual API/Ollama setup.
Selecting an available CLI saves its default model in your user
settings. CLI-reported sign-in does not verify online access or
subscription billing; an API-key login can also appear signed in. See
`vignette("interactive-console", package = "gptr")`.

## A first session

The example below uses `gptr_fake_provider()`, a scripted model that
ships with the package, so it runs without a key. With a real model only
the `model` argument changes.

``` r
library(gptr)

fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "fit = lm(mpg ~ wt, data = mtcars)\ncoef(fit)")),
  "Each additional 1000 lb of weight lowers fuel economy by about 5.3 miles per gallon.",
  "Four-cylinder cars are the most economical."
))
work = new.env()
s = peter("How does fuel economy depend on weight?", model = fake, envir = work, mode = auto)
s$text
#> [1] "Each additional 1000 lb of weight lowers fuel economy by about 5.3 miles per gallon."
ls(work)
#> [1] "fit"

s |> peter("Which cylinder group is the most economical?")
#> Four-cylinder cars are the most economical.
#> idle . fake/fake-1 . 2 turns . 5.0k tokens . $0.0000 . s2accda92df
s$turns
#> [1] 2
```

A System 1 question returns a typed R vector with the probabilities
attached:

``` r
judge = gptr_fake_provider(function(state, question) {
  if (grepl("randomized", paste(unlist(state), collapse = " "))) 0.93 else 0.08
}, name = "judge", type = "classifier")
abstracts = c(a = "We randomized 200 adults to drug or placebo.",
              b = "We followed a cohort of nurses for 20 years.")
is_rct = peter("Is this abstract about a randomized controlled trial?", abstracts, model = judge)
is_rct
#>              a              b
#>  TRUE (p=0.93) FALSE (p=0.08)
#> judge-s1-1.0 . calibration unknown . 2026-10-10
gptr_prob(is_rct)
#>    a    b
#> 0.93 0.08
```

## With a real model

Choose a provider explicitly before your first real call. API
credentials and CLI sign-in are separate routes; see
`vignette("language-models")`.

``` r
gptr_env("~/keys/.env")          # ANTHROPIC_API_KEY, OPENAI_API_KEY, TYPESAFE_API_KEY, ...
gptr_providers()                 # what is configured
gptr_config(model = "openai/gpt-6-sol", .scope = "session")
peter()                          # chat in the console

res = peter("Fit a mixed model of weight on diet with a random intercept per mouse.", mice)
res$value                        # the object the agent designated as its result

if (peter("Is this abstract about a randomized controlled trial?", abstract, model = jev)) {
  included = c(included, id)
}
```

## Local models with Ollama

Ollama is a first-class optional provider with two roles:

| Role | Support |
|----|----|
| Conversation and agent execution | Installed conversational models, with tools, images and other features enabled only when supported |
| Native typed decisions | Clef and Clef Flash through Ollama's native decision API, alongside hosted Jev decisions |

Select them with `model = "ollama/<name>"`, for example
`"ollama/qwen3:1.7b"` or `"ollama/clef-flash"`. Clef and Clef Flash
require Ollama 0.35.1 or later and return decisions, not a
conversational agent loop. Ollama and model weights are optional
external requirements; gptr never installs them or downloads models.

The default Ollama policy is local-only, with explicit checks for
inference locality and no automatic cloud fallback. A local model does
not make a workflow local if another step sends data to a cloud model or
network tool.

## Learn more

Start with `vignette("getting-started", package = "gptr")`. Most guides
include a runnable offline example. Recipes that need a real provider,
MCP server or external program are shown without running them.

| Task | Guide |
|----|----|
| Understand the name and ideas behind Peter | `vignette("why-peter")` |
| Choose a language model; call Peter from functions and scripts | `vignette("language-models")` |
| Make logical, choice and score decisions | `vignette("system-one")` |
| Chat, use slash commands, or run inline R with `!` | `vignette("interactive-console")` |
| Set defaults, permissions, paths and runtime options | `vignette("configuration")` |
| Record, replay and summarize a workflow | `vignette("script-as-history")` |
| Run teams, fan-outs, background sessions and the session SDK | `vignette("teams-and-background")` |
| Use R, files, shell, Python, SQL and Shiny apps | `vignette("tools-and-artifacts")` |
| Reuse skills, templates, agent files and plugins | `vignette("skills-and-plugins")` |
| Connect MCP servers or expose an R session | `vignette("mcp")` |
| Write tools, providers, policies and hooks | `vignette("extending-gptr")` |
| Understand execution, environments and result objects | `vignette("execution-model")` |
| Inspect usage, budgets, caching and compaction | `vignette("token-efficiency")` |

The function reference documents all 63 exports. In R, use
`help(package = "gptr")`, `?peter`, `?gptr_options`, `?gptr_security`
and `?gptr_egress`.

## Why `peter()`?

The package is `gptr`; you talk to its agent through `peter()`. The name
honors two Peters:

- **Peter Naur**, the Danish computer scientist who edited the ALGOL 60
  report and helped develop the syntax notation now called Backus-Naur
  Form. His work connects to gptr's readable R code and history
  documents.
- **Peter Cathcart Wason**, the cognitive psychologist who, with
  Jonathan Evans, studied dual processes in reasoning and the difference
  between a response and its conscious justification. His work connects
  to inspecting results, evidence and explanations.

gptr calls typed decision models "System 1" and conversational agents
"System 2". These are software roles; they do not imply human cognition
or that Wason introduced those labels. The
`vignette("why-peter", package = "gptr")` guide gives the history and
primary sources.

## Upgrading from gptr 0.7.0

gptr 1.0.0 is a complete rewrite. `get_response()` and
`dataframe_to_text()` were removed: use `peter("your prompt")$text`
instead of `get_response()`, and pass a data frame to `peter()` as
context instead of converting it to text. See `NEWS.md`.

## Acknowledgments

The tool descriptions, edit semantics and prompt-template grammar are
derived from 'pi' by Mario Zechner (MIT license). The model catalog is
derived from models.dev (MIT license) and the secret patterns from
gitleaks (MIT license); see `inst/COPYRIGHTS`. Ideas were borrowed from
'ellmer', 'tidyllm', 'btw' and 'mcptools', none of which gptr depends
on. Anthropic, OpenAI, Google, TypeSafe AI, Ollama and the vendors of
the command-line tools are third-party services; gptr is not affiliated
with or endorsed by them.

## License

MIT (c) Wanjun Gu.
