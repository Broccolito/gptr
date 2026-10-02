# G2 (b): fixed per-request prefix cost (system prompt + tool declarations) per preset and provider wire format.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
presets = list(
  "pi-4 (Pi default, with <docs>)" = list(tools = pi_tools, system = pi_prompt),
  "pi-4 (no <docs>)" = list(tools = pi_tools, system = pi_prompt_nodocs),
  "gptr-4 read,r,edit,write" = list(tools = gptr_tools[c("read", "r", "edit", "write")], system = gptr_prompt(c("read", "r", "edit", "write"))),
  "gptr-7 (+grep,find,ls)" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"))),
  "gptr-7 without <r_performance>" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"), r_perf = FALSE)),
  "gptr-10 (+r_inspect,ask,agent)" = list(tools = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls", "r_inspect", "ask", "agent")], system = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls", "r_inspect", "ask", "agent"))),
  "gptr-11 (+artifact, <artifacts>)" = list(tools = gptr_tools, system = gptr_prompt(names(gptr_tools), artifacts = TRUE)),
  "gptr-7 apply_patch (no edit/write)" = list(tools = c(gptr_tools[c("read", "r", "grep", "find", "ls")], list(apply_patch = apply_patch_fn)), system = gptr_prompt(c("read", "r", "grep", "find", "ls", "apply_patch")), patch = TRUE),
  "gptr-lean-4 (short r, no r_perf)" = list(tools = list(read = gptr_tools$read, r = r_lean, edit = gptr_tools$edit, write = gptr_tools$write), system = gptr_prompt(c("read", "r", "edit", "write"), r_perf = FALSE)))

cat("Per-tool declaration cost (Anthropic shape, o200k):\n")
all_tools = c(pi_tools["bash"], gptr_tools, list(r_lean = r_lean, apply_patch_fn = apply_patch_fn))
pt = vapply(all_tools, function(t) tok_o200k(j(list(name = t$name, description = t$description, input_schema = t$parameters))), 1)
print(pt)
cat(sprintf("apply_patch as Responses custom grammar tool: %d\n", tok_o200k(j(apply_patch_custom))))
cat(sprintf("<r_performance> section: %d; <artifacts> section: %d; Pi <docs> section: %d\n\n",
            tok_o200k(rd("r_performance.txt")), tok_o200k(rd("artifacts.txt")), tok_o200k(pi_prompt) - tok_o200k(pi_prompt_nodocs)))

res = list()
for (nm in names(presets)) {
  p = presets[[nm]]
  row = data.frame(preset = nm, n_tools = length(p$tools), system = tok_o200k(p$system))
  for (pv in c("anthropic", "responses", "chat", "gemini")) {
    tl = p$tools; extra = list()
    if (isTRUE(p$patch) && pv == "responses") { tl = tl[names(tl) != "apply_patch"]; extra = list(apply_patch_custom) }
    row[[pv]] = tok_o200k(wire(tl, p$system, pv, extra_tools = extra))
  }
  tl = p$tools
  if (isTRUE(p$patch)) tl = tl[names(tl) != "apply_patch"]
  row$resp_ns = tok_o200k(wire(tl, p$system, "responses", namespace = "gptr", extra_tools = if (isTRUE(p$patch)) list(apply_patch_custom) else list()))
  row$resp_strict = tok_o200k(wire(tl, p$system, "responses", strict = TRUE, extra_tools = if (isTRUE(p$patch)) list(apply_patch_custom) else list()))
  res[[nm]] = row
}
d = do.call(rbind, res)
cat("Prefix tokens (o200k) = system prompt + tools, serialised as each provider's request fields:\n")
print(d, row.names = FALSE)
cat("\nAnthropic adds a fixed tool-use system prompt when tools are present (286 tokens on Opus/Sonnet 5.5, report 07 section 2.1);\n")
cat("the JSON above is the payload proxy, not the provider's internal rendering.\n")
