
<!-- README.md is generated from README.Rmd by dev/release/precompute.R; edit README.Rmd. -->

# gptr <img src="https://raw.githubusercontent.com/Broccolito/gptr/main/man/img/logo.png" align="right" height="140" alt="gptr logo"/>

gptr runs language model agents inside your live R session. The agent
works on the objects that are already in memory: it inspects them, runs
R code on them and leaves its results in your workspace, so a large
object is loaded once and a mistake costs one re-evaluation instead of a
fresh run of the whole script. One function, `peter()`, is an
interactive chat in the console and a programmable call that you put in
scripts, loops and `if` statements.

- **One gateway.** `peter()` with no prompt opens a chat at the console;
  with a prompt it runs the agent and returns the session, which the
  pipe steers: `peter("...") |> peter("...")`.
- **System 1 and System 2.** Generative models (Anthropic, OpenAI,
  Google Gemini, any OpenAI-compatible endpoint, local Ollama models,
  and the Claude and ChatGPT plans through the `claude` and `codex`
  command-line tools) work next to typed decision models such as
  TypeSafe AI's Jev and Clef on a local Ollama server, whose yes/no,
  choice and score answers go straight into `if` and `for`.
- **The script is the history.** The code the agent ran is recorded into
  your `.R`, `.Rmd`, `.qmd` or `.ipynb` document and replays without
  model calls.
- **Everything is R.** Tools are R functions; artifacts are Shiny apps;
  skills, MCP servers, sub-agents, hooks and plugins use one documented
  extension API.
- **Safe defaults.** In the default `manual` mode only actions known to
  be read-only run without asking; every change to a file or an object
  asks first. The permission gate is not a sandbox: see
  `?gptr_security`.

## Installation

``` r
install.packages("gptr")
# the development version
pak::pak("Broccolito/gptr")
```

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
#> idle . fake/fake-1 . 2 turns . 5.0k tokens . $0.0000 . s11bce5cb35
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
#> judge-s1-1.0 . calibration unknown . 2026-10-06
gptr_prob(is_rct)
#>    a    b 
#> 0.93 0.08
```

## With a real model

``` r
gptr_env("~/keys/.env")          # ANTHROPIC_API_KEY, OPENAI_API_KEY, TYPESAFE_API_KEY, ...
gptr_providers()                 # what is configured
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

- `vignette("getting-started", package = "gptr")`
- `vignette("system-one", package = "gptr")`
- `vignette("script-as-history", package = "gptr")`
- `vignette("extending-gptr", package = "gptr")`
- `vignette("token-efficiency", package = "gptr")`
- `?gptr_security` for what gptr does on your behalf and where its
  protections end, and `?gptr_egress` for what is sent to model
  providers.

## Why `peter()`?

The package is `gptr`; you talk to its agent through `peter()`. The name
honors two Peters:

- **Peter Cathcart Wason** (1924-2003), the cognitive psychologist whose
  work on human reasoning, with Jonathan Evans, framed the dual-process
  view later known as "System 1" and "System 2" thinking. gptr joins
  both kinds of model in one agent flow: fast, typed System 1 decisions
  inside R control flow, and System 2 reasoning models that plan and
  write code.
- **Peter Naur** (1928-2016), whose name the Backus-Naur form carries: a
  notation for writing down the syntax of programming languages. In that
  spirit, gptr records agent sessions as ordinary documents - R scripts,
  R Markdown and Quarto files, Jupyter notebooks - that can be read,
  edited and replayed.

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
