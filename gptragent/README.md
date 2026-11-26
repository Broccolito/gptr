# gptr Agent

Work inside an R session you already have open, from Biorouter, Claude Code or Codex. The agent
inspects, analyses, plots and fixes the objects in memory through
[gptr](https://github.com/Broccolito/gptr), without reloading data. Every call passes gptr's
permission settings, and gptr records each call that runs, so the work can be replayed as a
script.

Current version: **1.3.0**

gptr Agent is released with gptr: its version is gptr's, and its bundle is attached to gptr's
GitHub releases.

## What you need

- R with the gptr package, 1.0 or later (`install.packages("gptr")`), and gptr's serving
  packages `httpuv`, `later` and `openssl`; plan mode needs gptr 1.2.0 or later, and recording
  1.3.0.
- [uv](https://docs.astral.sh/uv/) on your `PATH`. It runs the bridge, a Python program with no
  dependencies, and fetches a Python 3.11 or later when your computer has none.
- An interactive R: RStudio, Positron, R.app or R in a terminal. gptr answers while R waits at its
  prompt, so Rscript, knitr, Quarto and Jupyter kernels do not work.

## Serve your R session

In the R session you want the agent to work in, run one line. With gptr 1.2.0 or later:

```r
gptr::gptr_mcp_serve(advertise = TRUE, mode = "auto")
```

With gptr 1.0 or 1.1, use the helper in this folder (the `sessions` tool prints its full path on
your computer):

```r
source("<gptr Agent's folder>/r/attach.R"); biorouter_gptr_attach(mode = "auto")
```

Leave out `mode = "auto"` to let the agent only read the session. With it, the agent may change
objects, and gptr still refuses critical code (deleting the project or files outside it,
`rm(list = ls())`, its own configuration, reads of registered secrets). Stop serving with
`gptr::gptr_mcp_serve(stop = TRUE)` (or `biorouter_gptr_detach()`).

To keep a runnable record of the agent's work, bind a document first:
`gptr::gptr_doc("agent.R")`. Each call that runs is written into it, and
`gptr::gptr_export("agent.R", "analysis.R")` turns it into a plain R script. Without a document,
the calls are kept on the session (`gptr::gptr_last()`), and `gptr::gptr_last() |> gptr::peter()`
continues from them.

## Install

### Biorouter

Install **gptr Agent** from the BAAM marketplace, or from a downloaded bundle:

```bash
biorouter extension install gptragent.brxt
```

The bundle is `gptragent.brxt` on [gptr's releases](https://github.com/Broccolito/gptr/releases).
Biorouter updates it at its next launch after a new gptr release.

### Claude Code

```bash
claude plugin marketplace add Broccolito/gptr
claude plugin install gptr@gptr
```

In a session: `/plugin marketplace add Broccolito/gptr`, then `/plugin install gptr@gptr`. Check
with `claude mcp list`, which shows `plugin:gptr:gptr ... Connected`. The tools are
`mcp__plugin_gptr_gptr__sessions`, `__inspect` and `__r`, and the skill is `gptr:gptr-live-r`.

### Codex

```bash
codex plugin marketplace add Broccolito/gptr
codex plugin add gptr@gptr
```

Start a new thread afterwards. Check with `codex mcp get gptr`. The plugin sets a tool timeout of
300 seconds, as Codex's default of 60 would cut long calls. Codex asks before each `r` call,
because the tool can change objects; `codex exec`, which has nobody to ask, refuses it unless
its approval settings allow the server's tools.

## Tools

| Tool | What it does |
| --- | --- |
| `sessions` | Lists the R sessions gptr serves on this computer, attaches to one and returns an overview: R version, folder, packages, the objects in memory and the last traceback. One live session attaches by itself. With none, it returns the line to run in R. |
| `inspect` | Runs R code gptr classifies as read-only (risk level 0), such as `str(x)` or `summary(x)`. Anything else is refused without running. Marked read-only, so an agent's approval can run it without asking. |
| `r` | Runs any R code through gptr's permission gate in the mode the session was served with: changes in place, models, plots (returned as images) and fixes. Marked destructive, so an agent asks before it runs where its settings say so. |

The `gptr-live-r` skill tells the model how to work in a live session: look first, never reload,
change in place, fix from the traceback and verify.

## How it finds your session

`gptr_mcp_serve(advertise = TRUE)` serves the session on `127.0.0.1` with a random port and a
192-bit bearer token, and writes them to a private discovery record:

```
tools::R_user_dir("gptr", "cache")/mcp-serve/serve-<pid>.json
```

The folder is private to you (0700), the file is 0600, and gptr removes the record when the server
stops, when gptr is unloaded and when R exits; the next gptr load removes the record of an R that
was killed. gptr Agent looks for records in, in order:

1. `GPTR_MCP_DISCOVERY_DIR`, if you set it;
2. the folder R would use with the agent's environment (`R_USER_CACHE_DIR`, `XDG_CACHE_HOME` or
   the platform default);
3. the folder R reports for itself, asked once with `Rscript` (which reads `.Renviron` but runs no
   `.Rprofile`) when no session is found;
4. the platform default, because a desktop app started from the Finder or the Start menu does not
   see a shell's variables.

Codex passes a plugin only a few environment variables; the plugin forwards
`GPTR_MCP_DISCOVERY_DIR`, `GPTRAGENT_RSCRIPT`, `R_USER_CACHE_DIR` and `XDG_CACHE_HOME`.

It uses a record only when it is your own regular file with no group or other permissions (on
macOS and Linux) and names a loopback address. It talks to gptr with Python's `http.client`, never
through a proxy and never following a redirect. On Windows it never sends a signal to an R
process (signal 0 there would interrupt R); a refused connection tells it the server is gone.

## Limits

- R must be at its idle prompt. While R runs other code, a call waits; when it waits longer than
  the call's timeout (280 seconds at most, under Biorouter's 300 second limit), the answer says R
  may still be running it.
- Stopping the agent does not stop R code. Press Esc (RStudio, Positron, R.app) or Ctrl-C (R in a
  terminal) in R.
- Loopback only: an R session on another computer (HPC, RStudio Server) is not reached.
- gptr's classifier and an agent's own approvals prevent mistakes by a cooperative agent; neither
  is a security boundary.

## Privacy

A live R session can hold anything, including clinical extracts, so Biorouter's marketplace marks
gptr Agent private: private models (for example Versa, Llama Server or a local Ollama) can use it,
and chats on public models do not see its tools. A chat that uses it becomes private. Claude Code
and Codex send what the tools return to the model you chose.

## Develop

The folder is part of the gptr repository and outside the R package. From `gptragent/`:

```bash
uv sync --locked
uv run python -m unittest discover -s tests -v
uv run python scripts/build_brxt.py          # dist/gptragent.brxt and SHA256SUMS
GPTRAGENT_LIVE=1 uv run python -m unittest tests.test_live -v   # needs R with gptr (macOS, Linux)
```

`scripts/version.py X.Y.Z` moves the version everywhere it is written, and the build refuses a
version other than gptr's `DESCRIPTION`. Publishing gptr's GitHub release `vX.Y.Z` runs the
`gptragent` workflow, which attaches `gptragent.brxt`, `gptragent-X.Y.Z.brxt` and `SHA256SUMS`. A
gptr release is a deploy: Biorouter installs the bundle of gptr's newest release at its next
launch.

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
