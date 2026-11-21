---
name: gptr-live-r
description: Work inside the user's live R session through the gptr Agent extension. Use when the user refers to objects, data, models or errors in an R session they have open (RStudio, Positron, R.app or R in a terminal), or asks to analyse, plot, debug or fix something there without reloading.
license: Apache-2.0
metadata:
  version: 0.1.0
  extension: gptragent
---

# Working in a live R session

The user's data is already loaded in an R session they have open. The gptr Agent tools reach
that session through gptr: `gptragent__sessions`, `gptragent__inspect` and `gptragent__r`.
Objects persist between calls and belong to the user.

1. **Find the session.** Call `gptragent__sessions`. If none is listed, give the user the one
   line it returns and stop until they have run it; do not start R yourself. If several are
   listed, ask which one (by label or folder) unless the user already named it, then attach with
   `attach: <pid>`. Never mix objects from two sessions.
2. **Look first.** The attach overview lists the objects in memory and the last traceback. Use
   `gptragent__inspect` for `str()`, `head()`, `summary()`, `table()` and `peter$describe(x)`.
   Never print a whole large object, and never print row-level records of people unless the user
   asks for them.
3. **Never reload.** Do not call `read.csv()`, `readRDS()`, `load()` or similar for data that is
   already in memory, and do not run `Rscript` or `R -e` from the shell for this work: a new R
   process has none of the user's objects. If something truly is not in the session, say so and
   ask.
4. **Change in place, minimally.** Use `gptragent__r`. Keep object, column and argument names.
   Before a change that overwrites data, say what will change; for large or irreplaceable objects
   keep a copy first (`cohort_before_fix = cohort`) unless the user declines.
5. **Fixing an error.** Read the traceback from the overview (or `traceback()` and
   `geterrmessage()` through inspect), reproduce it on a small slice, fix the cause (a data type,
   a function body, an argument), then re-run the user's original call and show that it now
   works. Keep a fixed function's arguments as they were.
6. **Verify.** After each change, check it with `gptragent__inspect` (the changed values, or
   `stopifnot()` of the property the user asked for) and report the object change lines gptr
   returns (`+ new`, `~ modified`).
7. **Refusals.** gptr refuses what its mode does not allow and names what the user can do. Relay
   that once, in its words; do not reword the code to get around it, and do not retry it.
8. **Long work.** Keep each call under four minutes. When a call times out, R may still be
   running it: do not run it again; check with a quick inspect, and tell the user they can stop
   it with Esc or Ctrl-C in R. Start longer jobs in the background (`callr::r_bg()`, `future`, or
   `peter$bg()`) and poll.
9. **Record.** When the user wants the steps kept, write the code you ran to a script with the
   file tools, in the R session's working folder.
10. **Style.** R code follows the `r-scripting` and `ggplot-visualization` skills when they are
    installed. Do not call `peter()` from `gptragent__r`: it starts a second agent with its own
    model.
