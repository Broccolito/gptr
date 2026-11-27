---
name: gptr-live-r
description: Work inside the user's live R session through gptr Agent. Use when the user refers to objects, data, models or errors in an R session they have open (RStudio, Positron, R.app or R in a terminal), or asks to analyse, plot, debug or fix something there without reloading.
license: Apache-2.0
metadata:
  extension: gptragent
---

# Working in a live R session

The user's data is already loaded in an R session they have open. The gptr Agent tools reach
that session through gptr: `sessions`, `inspect` and `r` (hosts prefix these names, as in
`gptragent__r`). Objects persist between calls and belong to the user.

1. **Find the session.** Call `sessions`. If none is listed, give the user the one line it
   returns and stop until they have run it; do not start R yourself. If several are listed, ask
   which one (by label or folder) unless the user already named it, then attach with
   `attach: <pid>`. Never mix objects from two sessions.
2. **Look first.** The attach overview lists the objects in memory and the last traceback. Use
   `inspect` for `str()`, `head()`, `summary()`, `table()` and `peter$describe(x)`. Never print
   a whole large object, and never print row-level records of people unless the user asks for
   them.
3. **Never reload.** Do not call `read.csv()`, `readRDS()`, `load()` or similar for data that is
   already in memory, and do not run `Rscript` or `R -e` from the shell for this work: a new R
   process has none of the user's objects. If something truly is not in the session, say so and
   ask.
4. **Change in place, minimally.** Use `r`. Keep object, column and argument names. Before a
   change that overwrites data, say what will change; for large or irreplaceable objects keep a
   copy first (`cohort_before_fix = cohort`) unless the user declines.
5. **Fixing an error.** Read the traceback and the last error message from the overview (or
   `traceback()` and `geterrmessage()` through inspect), reproduce it on a small slice, fix the
   cause (a data type, a function body, an argument), then re-run the user's original call and
   show that it now works. Keep a fixed function's arguments as they were. A traceback shows the
   calls, not the name the user was assigning the result to. When the fix needs a choice only the
   user can make (a column or object that does not exist, which variable to use instead, where
   the result should go), ask one precise question instead of guessing, and never overwrite
   another existing object as a stand-in.
6. **Verify.** After each change, check it with `inspect` (the changed values, or `stopifnot()`
   of the property the user asked for) and report the object change lines gptr returns
   (`+ new`, `~ modified`).
7. **Refusals.** gptr refuses what its mode does not allow and names what the user can do. Relay
   that once, in its words; do not reword the code to get around it, and do not retry it.
8. **Long work.** Keep each call under four minutes. When a call times out, R may still be
   running it: do not run it again; check with a quick inspect, and tell the user they can stop
   it with Esc or Ctrl-C in R. Start longer jobs in the background (`callr::r_bg()`, `future`, or
   `peter$bg()`) and poll.
9. **Record.** gptr 1.3.0 and later records each `r` call that runs in the session's history
   (`gptr_last()`) and in the document the user bound with `gptr_doc()`, so do not also write
   that work to a script unless the user asks for one.
10. **Style.** R code follows the `r-scripting` and `ggplot-visualization` skills when they are
    installed. Do not call `peter()` from `r`: it starts a second agent with its own model.
