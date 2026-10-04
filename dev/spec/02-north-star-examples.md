# gptr — North-Star Usage Examples

What using the finished package should feel like. These examples are the
target user experience that the architecture must make possible. Function and
argument names here are the working names; the interface contract
(`04-interface-contract.md`) fixes the final ones.

Conventions that hold everywhere:

- `gptr(...)` is the only entry point (decision S-1).
- Prompts are quoted strings (S-2). Models, skills, extensions and plugins may
  be written as bare names.
- The agent works on the objects already in the session.

---

## 1. Interactive session on a large in-memory object

```r
library(gptr)
library(Seurat)

pbmc = readRDS("pbmc_3M_cells.rds")   # 5 GB, takes four minutes. Done once.

gptr()                                  # no prompt: opens the chat in the console
```

```text
gptr 1.0.0 | model anthropic/claude-sonnet-5-5 | mode manual | .gptr/ found
Workspace: pbmc <Seurat, 3,012,448 cells x 33,538 features, 5.1 GB>

> cluster the cells and show me the markers for the three largest clusters

  r  pbmc = FindNeighbors(pbmc, dims = 1:30)          allow? [y]es / [a]lways / [n]o: y
  r  pbmc = FindClusters(pbmc, resolution = 0.8)
  r  markers = FindAllMarkers(subset(pbmc, idents = 0:2), only.pos = TRUE)

  The three largest clusters are 0 (T cells, 812k cells), 1 (monocytes) ...
  I stored the marker table in `markers`.

> !dim(markers)                         # "!" runs R directly, no model involved
[1] 4211    7

> /mode auto                            # slash commands control the harness
> /exit
```

After `/exit` the objects `pbmc` (now clustered) and `markers` are simply there
in the session. Nothing was reloaded at any point, and a mistake by the agent
costs one re-evaluation, not another four-minute load.

---

## 2. The same function as a programmable call

```r
res = gptr("Fit a mixed model of weight on diet with a random intercept per
             mouse, and report the diet effect.", mice)

res            # prints the agent's answer
res$value      # the R object the agent designated as its result (the fitted model)
res$usage      # tokens and cost
```

Attaching objects is positional: anything unnamed that is not a string is
context. The data-first pipe works too:

```r
mice |> gptr("Which columns have missing values, and how should I impute them?")
```

---

## 3. The pipe steers one session object

```r
gptr("Load the counts in data/counts.csv and normalise them") |>
  gptr("Now run a PCA and tell me how many components explain 80% of variance") |>
  gptr("Plot PC1 against PC2 coloured by batch", model = opus)
```

What flows through `|>` is the agent session itself. Each piped prompt steers
that same session: same history, same workspace, same objects. The model can
be switched mid-conversation; the history is handed over to the new provider.

Because the session is one object with reference semantics, it can be kept and
steered later from anywhere in the script:

```r
qc = gptr("Run QC on pbmc and flag low-quality cells", pbmc)

# ... ordinary R code in between ...
table(pbmc$percent.mt > 20)

qc |> gptr("Use 15% mitochondrial reads as the cut-off instead of 20%")
qc$value                                 # the steered result
gptr_fork(qc) |> gptr("Try a 10% cut-off as well")   # explicit branch
```

---

## 4. System One decisions inside control flow

```r
# one decision
if (gptr("Is this abstract about a randomised controlled trial?", abstract,
         model = jev)) {
  included = c(included, id)
}

# vectorised over inputs: twenty decisions take about as long as one
is_rct = gptr("Is this abstract about a randomised controlled trial?",
               abstracts, model = jev)
table(is_rct)
attr(is_rct, "prob")                    # calibrated probabilities

# choose one of N
tissue = gptr("Which tissue does this sample description refer to?",
               samples$description, model = jev,
               choices = c("liver", "lung", "brain", "other"))

# a loop that a fast model steers
while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev)) {
  fit = refine(fit)
}
```

The return value is an ordinary typed R vector (logical, factor, numeric) with
the probabilities attached, so it drops into `if`, `while`, `ifelse`,
`dplyr::filter()` and `data.table` expressions unchanged.

---

## 5. System One routing System Two

```r
for (task in tasks) {
  hard = gptr("Is this task subtle enough to need the strongest model?",
               task, model = jev)
  gptr(task, model = if (hard) opus else haiku, mode = auto)
}
```

The R script is the orchestration graph. No separate workflow language.

---

## 6. Sub-agents in parallel and across providers

```r
reviews = gptr(
  "Review analysis.R for statistical errors.",
  agents = list(
    stats   = agent(model = opus,   skills = statistics),
    code    = agent(model = codex),                    # ChatGPT plan via Codex
    biology = agent(model = gemini, skills = single_cell)
  )
)
reviews$stats; reviews$code; reviews$biology

# fan out over a list, four at a time
summaries = gptr("Summarise this cohort", cohorts, parallel = 4)
```

Inline sub-agents read the parent's in-memory objects without copying them.

---

## 7. The script is the history

A session started with `gptr()` in a project writes a runnable transcript as it
goes. After example 1 the file `analysis.R` contains:

```r
library(gptr)

gptr("cluster the cells and show me the markers for the three largest clusters")
# >>> gptr:7f3a21 model=anthropic/claude-sonnet-5-5
pbmc = FindNeighbors(pbmc, dims = 1:30)
pbmc = FindClusters(pbmc, resolution = 0.8)
markers = FindAllMarkers(subset(pbmc, idents = 0:2), only.pos = TRUE)
#> 4211 marker genes across 3 clusters
## Decision: resolution 0.8 chosen because 0.4 merged the two monocyte groups.
# <<< gptr:7f3a21
```

Sourcing that file again replays the recorded code without calling a model.
Running it with `options(gptr.replay = "live")` asks the model afresh. The
agent can return to an earlier block and rewrite it.

The same works in R Markdown, Quarto and Jupyter, where the block becomes a
chunk or cell and figures render next to the prompt that produced them.

---

## 8. Artifacts are Shiny apps

```r
gptr("Build me an explorer for the marker table with a gene search box and a
      volcano plot", markers)
```

```text
  artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)
```

The console stays free. `.gptr/artifacts/marker-explorer/app.R` holds the app
and a snapshot of the data it needs.

---

## 9. Setup

```r
gptr_init()                                   # creates .gptr/ with vignette.Rmd
gptr_config(model = sonnet, mode = manual)    # project defaults
gptr_env("~/keys/jev-key.env")                # load keys from a .env file
gptr_providers()                              # what is configured and reachable
gptr_models("claude")                         # search the model catalog
```

Subscription plans need no key:

```r
gptr("Refactor utils.R", model = claude_code)  # uses the Claude plan via Claude Code
gptr("Refactor utils.R", model = codex)        # uses the ChatGPT plan via Codex
```

---

## 10. Skills, extensions, plugins, MCP

```r
gptr("Annotate these clusters", pbmc, skills = c(single_cell, plotting))

gptr("Find trials for this indication", indication,
     plugins = clinical_trials)               # a bundle: skills + tools + MCP servers

gptr_mcp()                                    # servers found, including those set up
                                              # for Claude Code and Codex
```

`.gptr/vignette.Rmd` is the project-instructions file. It is ordinary R
Markdown, so it renders to HTML for people and is read as text by the agent.

---

## 11. A whole workflow that reads like R

The file below is both the program and the record of the agent work. It mixes
natural-language prompts, plain R, System 1 decisions in control flow and
`|>` steering chains, and it can be sourced again.

```r
library(gptr)
library(Seurat)

pbmc = readRDS("pbmc.rds")

# System 2: open-ended work on the live object, steered with the pipe
prep = gptr("Normalise pbmc, find variable features and run PCA", pbmc) |>
  gptr("Regress out percent.mt while scaling") |>
  gptr("Keep 30 PCs; tell me if the elbow suggests fewer")

# plain R the analyst wrote by hand
pbmc = FindNeighbors(pbmc, dims = 1:30) |> FindClusters(resolution = 0.8)

# System 1: a typed judgement drives the control flow
for (cl in levels(Idents(pbmc))) {
  markers = FindMarkers(pbmc, ident.1 = cl, only.pos = TRUE)
  top = paste(head(rownames(markers), 10), collapse = ", ")

  cell_type = gptr("Which immune cell type do these marker genes indicate?",
                    top, model = jev,
                    choices = c("T cell", "B cell", "NK cell", "monocyte",
                                "dendritic cell", "platelet", "unclear"))

  if (cell_type == "unclear") {
    gptr("Cluster {cl} has ambiguous markers ({top}). Investigate with
          additional markers and propose a label.", pbmc) |>
      gptr("Prefer canonical markers from the literature; explain your choice")
  }
}

# an artifact built from the live objects
gptr("Build a Shiny app to browse clusters, markers and a UMAP", pbmc)
```

## 12. Modes

| Mode | Behaviour |
|------|-----------|
| `manual` | asks before every action that changes a file or an object |
| `edits` | file edits inside the project are automatic; R evaluation still asks |
| `auto` | fully autonomous, no questions |
| `plan` | read-only: inspects and proposes, changes nothing |

```r
gptr("Clean up the data directory", mode = plan)
gptr("Go ahead with that plan", mode = auto)
```

The agent can also ask the user a question mid-task; in a non-interactive run
with `mode = manual` it stops with a clear error instead of guessing.

## NS-13: local conversation and typed decisions on one Ollama server

Design examples for IC-74; these do not imply an implemented public API.
The server and models are installed explicitly. No cloud key is needed, and
local-only selection must not fall back to a hosted service.

```r
s = gptr("Summarize the variables already in my session", model = "ollama/qwen3:1.7b")
route = gptr("Which kind of work is requested?", request,
             model = "ollama/clef-flash", choices = c("analysis", "plot", "other"))
if (gptr("Does this request require numerical analysis?", request,
         model = "ollama/clef-flash")) {
  s = s |> gptr("Perform the analysis using the existing objects")
}
```

Switching the decision model to `ollama/clef` retains the typed interface when
that model is installed. Image decisions use explicitly supplied raw image
records in `.opts$system1_images`, as specified in `07-local-ollama.md` section 4.
Probabilities and confidence are recorded with their provenance; they are not
presented as validated scientific accuracy. Replay performs no model request.
