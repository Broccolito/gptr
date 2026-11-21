# gptr Agent

Work inside an R session you already have open. Biorouter inspects, analyses, plots and fixes
objects in memory through [gptr](https://github.com/Broccolito/gptr), without reloading data.
Every call passes gptr's permission settings.

Current version: **0.1.0**

## What you need

- R with the gptr package, 1.1 or later (`install.packages("gptr")`), and gptr's serving
  packages `httpuv`, `later` and `openssl`.
- [uv](https://docs.astral.sh/uv/), which Biorouter uses to install every `.brxt` extension.
- An interactive R: RStudio, Positron, R.app or R in a terminal. gptr answers while R waits at its
  prompt, so Rscript, knitr, Quarto and Jupyter kernels do not work.

## Set up

1. In Biorouter, install **gptr Agent** from the BAAM marketplace, or from a downloaded bundle:
   `biorouter extension install gptragent.brxt`.
2. In the R session you want Biorouter to work in, run one line.

   With gptr 1.2.0 or later:

   ```r
   gptr::gptr_mcp_serve(advertise = TRUE, mode = "auto")
   ```

   With gptr 1.0 or 1.1, use the helper that ships with the extension (the `sessions` tool prints
   its full path on your computer):

   ```r
   source("<gptr Agent's folder>/r/attach.R"); biorouter_gptr_attach(mode = "auto")
   ```

   Leave out `mode = "auto"` to let Biorouter only read the session. With it, Biorouter may change
   objects, and gptr still refuses critical code (deleting the project or files outside it,
   `rm(list = ls())`, its own configuration, reads of registered secrets).
3. Ask Biorouter about your objects, for example "Describe `cohort` in my R session".

Stop serving with `gptr::gptr_mcp_serve(stop = TRUE)` (or `biorouter_gptr_detach()`).

## Tools

| Tool | What it does |
| --- | --- |
| `sessions` | Lists the R sessions gptr serves on this computer, attaches to one and returns an overview: R version, folder, packages, the objects in memory and the last traceback. One live session attaches by itself. With none, it returns the line to run in R. |
| `inspect` | Runs R code gptr classifies as read-only (risk level 0), such as `str(x)` or `summary(x)`. Anything else is refused without running. Marked read-only, so Biorouter's Smart approval runs it without asking. |
| `r` | Runs any R code through gptr's permission gate in the mode the session was served with: changes in place, models, plots (returned as images) and fixes. Marked destructive, so Smart approval shows the code before it runs. |

The extension also brings the `gptr-live-r` skill, which tells the model how to work in a live
session: look first, never reload, change in place, fix from the traceback and verify.

## How it finds your session

`gptr_mcp_serve(advertise = TRUE)` serves the session on `127.0.0.1` with a random port and a
192-bit bearer token, and writes them to a private discovery record:

```
tools::R_user_dir("gptr", "cache")/mcp-serve/serve-<pid>.json
```

The folder is private to you (0700), the file is 0600, and gptr removes the record when the server
stops, when gptr is unloaded and when R exits; the next gptr load removes the record of an R that
was killed. gptr Agent looks for records in, in order:

1. `GPTR_MCP_DISCOVERY_DIR`, if you set it for the extension;
2. the folder R would use with Biorouter's environment (`R_USER_CACHE_DIR`, `XDG_CACHE_HOME` or
   the platform default);
3. the folder R reports for itself, asked once with `Rscript` (which reads `.Renviron` but runs no
   `.Rprofile`) when no session is found;
4. the platform default, because a desktop app started from the Finder or the Start menu does not
   see a shell's variables.

It uses a record only when it is your own regular file with no group or other permissions (on
macOS and Linux) and names a loopback address. It talks to gptr with Python's `http.client`, never
through a proxy and never following a redirect. On Windows it never sends a signal to an R
process (signal 0 there would interrupt R); a refused connection tells it the server is gone.

## Limits

- R must be at its idle prompt. While R runs other code, a call waits; when it waits longer than
  the call's timeout (280 seconds at most, under Biorouter's 300 second limit), the answer says R
  may still be running it.
- Stop in Biorouter does not stop R code. Press Esc (RStudio, Positron, R.app) or Ctrl-C (R in a
  terminal) in R.
- Loopback only: an R session on another computer (HPC, RStudio Server) is not reached.
- gptr's classifier and Biorouter's privacy tiers prevent mistakes by a cooperative agent; neither
  is a security boundary.

## Privacy

A live R session can hold anything, including clinical extracts, so the BAAM listing marks gptr
Agent private: private models (for example Versa, Llama Server or a local Ollama) can use it, and
chats on public models do not see its tools. A chat that uses it becomes private.

## Develop

```bash
uv sync --locked
uv run python -m unittest discover -s tests -v
uv run python scripts/build_brxt.py          # dist/gptragent.brxt and SHA256SUMS
GPTRAGENT_LIVE=1 uv run python -m unittest tests.test_live -v   # needs R with gptr (macOS, Linux)
```

`scripts/version.py X.Y.Z` moves the version everywhere it is written. A pushed tag `vX.Y.Z`
must equal the manifest version; the release workflow then publishes `gptragent.brxt`,
`gptragent-X.Y.Z.brxt` and `SHA256SUMS`. A GitHub release is a deploy: the desktop app installs
the newest release of this repository at its next launch.

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
