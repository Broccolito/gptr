# G2 (b): how small can the default 7-tool prefix get without dropping a capability?
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
lean = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
lean$r = r_lean
lean$read$description = "Read a text file or an image. Text is capped at 2000 lines / 50 KB; continue with offset/limit (lines)."
lean$grep$description = "Search file contents (PCRE or literal); returns path:line: text; respects .gitignore; at most 100 matches by default."
lean$find$description = "Find files by glob (respects .gitignore); sort by path, mtime or size."
lean$ls$description = "List a directory; directories end with '/'."
lean$write$description = "Create or overwrite a file (parent directories are created)."
lean$edit$description = "Exact-text replacements in one file: each edits[].oldText must match once in the original file; edits must not overlap."
for (k in c("read", "grep", "find", "ls", "edit", "write")) {        # drop per-property prose that repeats the description
  pr = lean[[k]]$parameters$properties
  for (p in names(pr)) if (!is.null(pr[[p]]$description) && nchar(pr[[p]]$description) > 60) pr[[p]]$description = sub("^(.{0,57}[^ ]*).*$", "\\1", pr[[p]]$description)
  lean[[k]]$parameters$properties = pr
}
r_perf_short = "<r_performance>\nObjects in memory are the asset: never reload data; print str()/head(), never whole big objects; compose several steps in one r call and print only the result; data.table/duckdb/arrow for big data; ask before installing packages. Details: skill high-performance-r.\n</r_performance>"
sys_lean = paste0("You are gptr, an agent inside the user's live R session. Objects you create persist for the user.\n\n<tools>\n",
                  paste(sprintf("- %s: %s", names(lean), snippets[names(lean)]), collapse = "\n"),
                  "\n</tools>\n\n<rules>\n- Use r for computation; compose several steps in one call and print compact results.\n- Use edit for precise changes (one call, several edits[]); write only for new files or full rewrites.\n- Be concise; name the objects and files you create.\n</rules>\n\n", r_perf_short, "\n\n<cwd>\n/Users/me/project\n</cwd>")
full = wire(gptr_tools[names(lean)], gptr_prompt(names(lean)), "anthropic")
lw = wire(lean, sys_lean, "anthropic")
cat(sprintf("gptr-7 as specified by reports 01/12/19: %d o200k tokens (system %d)\n", tok_o200k(full), tok_o200k(gptr_prompt(names(lean)))))
cat(sprintf("gptr-7 lean rewrite (same tools and parameters): %d o200k tokens (system %d); saving %.0f%%\n",
            tok_o200k(lw), tok_o200k(sys_lean), 100 * (1 - tok_o200k(lw) / tok_o200k(full))))
for (pv in c("responses", "chat", "gemini")) cat(sprintf("  %-9s full %d | lean %d\n", pv, tok_o200k(wire(gptr_tools[names(lean)], gptr_prompt(names(lean)), pv)), tok_o200k(wire(lean, sys_lean, pv))))
tok_save()
