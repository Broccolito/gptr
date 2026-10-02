# G2 (b): MCP tool exposure (direct vs R-signature "code exposure" vs names/deferred) at 0/10/50 tools,
# and skills catalogs at 10/40/160 skills.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
rd_json = function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)
gh = lapply(sort(list.files(file.path(G2, "mcp_corpus/github"), full.names = TRUE)), rd_json)
cc = rd_json(file.path(G2, "mcp_corpus/claude_code_tools.json"))
cat(sprintf("Corpora: GitHub MCP server %d tools (commit 85598ba, toolsnaps), Claude Code `claude mcp serve` %d tools\n",
            length(gh), length(cc)))
per_tool = function(tl) vapply(tl, function(t) tok_o200k(j(list(name = t$name, description = t$description, input_schema = t$inputSchema))), 1)
cat(sprintf("Direct declaration per tool (o200k): GitHub median %.0f (p10 %.0f, p90 %.0f); Claude Code median %.0f (p90 %.0f)\n\n",
            median(per_tool(gh)), quantile(per_tool(gh), 0.1), quantile(per_tool(gh), 0.9), median(per_tool(cc)), quantile(per_tool(cc), 0.9)))

sig = function(t, server = "github", max_desc = 120L, desc = TRUE) {
  props = t$inputSchema$properties
  if (is.null(props)) props = list()
  req = unlist(t$inputSchema$required)
  a = vapply(names(props), function(p) {
    ty = props[[p]]$type
    if (is.null(ty)) ty = "any"
    if (is.list(ty)) ty = paste(unlist(ty), collapse = "|")
    if (identical(ty, "array") && !is.null(props[[p]]$items$type)) ty = paste0(props[[p]]$items$type, "[]")
    paste0(p, if (p %in% req) "" else "?", ": ", ty)
  }, "")
  line = sprintf("mcp$%s$%s(%s)", server, t$name, paste(a, collapse = ", "))
  if (desc) {
    d = gsub("\\s+", " ", t$description %||% "")
    d = sub("^(.*?[.!?])\\s.*$", "\\1", d)
    if (nchar(d) > max_desc) d = paste0(substr(d, 1, max_desc - 3), "...")
    line = paste0(line, "  # ", d)
  }
  line
}
catalog = function(tl, server, budget = 3000L, desc = TRUE) {
  head = sprintf("<r_functions>\nMCP tools are R functions; call them inside r and reduce results before printing. mcp_search(\"query\") finds more; mcp_describe(\"%s\", \"tool\") shows a full schema.\n%s:", server, server)
  # budget filled with the harness-side estimator (signature lines are code-like: chars/3.2), as gptr would;
  # the finished catalog is then measured with o200k by the caller
  est = function(x) ceiling(nchar(x) / 3.2)
  lines = character(); used = est(head)
  for (k in seq_along(tl)) {
    l = sig(tl[[k]], server, desc = desc)
    tk = est(l) + 1L
    if (used + tk > budget) { lines = c(lines, sprintf("  (%d more %s tools: use mcp_search())", length(tl) - k + 1L, server)); break }
    lines = c(lines, paste0("  ", l)); used = used + tk
  }
  paste(c(head, lines, "</r_functions>"), collapse = "\n")
}
tool_search_def = tool("tool_search", "Search the deferred tools by keyword; matching tool definitions become callable on the next turn.",
                       obj(list(query = str_("Keywords"), limit = num_("Maximum matches (default 5)")), "query"))
set.seed(42)
ord = sample(length(gh))
rows = list()
for (n in c(0L, 10L, 50L, 125L)) {
  tl = gh[ord[seq_len(n)]]
  direct_a = if (n) tok_o200k(j(lapply(tl, function(t) list(name = t$name, description = t$description, input_schema = t$inputSchema)))) else 0L
  direct_ns = if (n) tok_o200k(j(list(type = "namespace", name = "github", description = "GitHub MCP server",
                                      tools = lapply(tl, function(t) list(type = "function", name = t$name, description = t$description, parameters = t$inputSchema))))) else 0L
  rows[[length(rows) + 1]] = data.frame(corpus = "github", n_tools = n,
    direct_anthropic = direct_a, direct_responses_ns = direct_ns,
    r_catalog_3000 = if (n) tok_o200k(catalog(tl, "github")) else 0L,
    r_catalog_unbounded = if (n) tok_o200k(catalog(tl, "github", budget = 1e6)) else 0L,
    r_sig_no_desc = if (n) tok_o200k(catalog(tl, "github", budget = 1e6, desc = FALSE)) else 0L,
    names_only = if (n) tok_o200k(paste(vapply(tl, `[[`, "", "name"), collapse = ", ")) else 0L,
    deferred_search_tool = if (n) tok_o200k(j(list(name = tool_search_def$name, description = tool_search_def$description, input_schema = tool_search_def$parameters))) else 0L)
}
rows[[length(rows) + 1]] = data.frame(corpus = "claude-code", n_tools = length(cc),
  direct_anthropic = tok_o200k(j(lapply(cc, function(t) list(name = t$name, description = t$description, input_schema = t$inputSchema)))),
  direct_responses_ns = NA, r_catalog_3000 = tok_o200k(catalog(cc, "cc")), r_catalog_unbounded = tok_o200k(catalog(cc, "cc", budget = 1e6)),
  r_sig_no_desc = tok_o200k(catalog(cc, "cc", budget = 1e6, desc = FALSE)),
  names_only = tok_o200k(paste(vapply(cc, `[[`, "", "name"), collapse = ", ")), deferred_search_tool = 58L)
d = do.call(rbind, rows)
cat("MCP exposure cost in the request prefix (o200k):\n")
print(d, row.names = FALSE)
cat("\nExample catalog lines:\n"); cat(head(strsplit(catalog(gh[ord[1:10]], "github"), "\n")[[1]], 6), sep = "\n")
cat(sprintf("\nlast lines of the 50-tool catalog under the 3000-token budget:\n%s\n",
            paste(tail(strsplit(catalog(gh[ord[1:50]], "github"), "\n")[[1]], 3), collapse = "\n")))

tok_save()
