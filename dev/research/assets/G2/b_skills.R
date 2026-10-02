# G2 (b): skills catalogs at 10/40/160 skills in several formats (o200k).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
# ---------------- skills ----------------
# list.files(recursive = TRUE) over the plugin cache walks node_modules trees and took > 30 min here; find(1) takes < 1 s
sk_files = suppressWarnings(system2("find", c(path.expand("~/.claude/plugins/cache"), path.expand("~/.claude/skills"), "-name", "SKILL.md", "-not", "-path", shQuote("*/node_modules/*")), stdout = TRUE, stderr = FALSE))
fm = function(f) {
  x = readLines(f, warn = FALSE, encoding = "UTF-8")
  if (!length(x) || x[1] != "---") return(NULL)
  end = which(x == "---")[2]
  if (is.na(end)) return(NULL)
  y = tryCatch(yaml::yaml.load(paste(x[2:(end - 1)], collapse = "\n")), error = function(e) NULL)
  if (is.null(y$name) || is.null(y$description)) return(NULL)
  data.frame(name = as.character(y$name)[1], description = gsub("\\s+", " ", paste(y$description, collapse = " ")),
             body = paste(x[(end + 1):length(x)], collapse = "\n"))
}
sk = do.call(rbind, lapply(sk_files, fm))
sk = sk[!duplicated(sk$name), ]
cat(sprintf("\nSkills corpus: %d SKILL.md files with valid frontmatter (%d unique names) under ~/.claude\n", length(sk_files), nrow(sk)))
set.seed(3); ib = sample(nrow(sk), 25)
sk$body_tokens = NA; sk$body_tokens[ib] = vapply(sk$body[ib], tok_o200k, 1)
cat(sprintf("Description length: median %.0f chars (p90 %.0f); SKILL.md body (random 25, o200k): median %.0f tokens (p90 %.0f, max %.0f)\n",
            median(nchar(sk$description)), quantile(nchar(sk$description), 0.9), median(sk$body_tokens, na.rm = TRUE),
            quantile(sk$body_tokens, 0.9, na.rm = TRUE), max(sk$body_tokens, na.rm = TRUE)))
esc = function(x) gsub("<", "&lt;", gsub("&", "&amp;", x))
pi_catalog = function(s) paste0("<skills>\nThe following skills provide specialized instructions for specific tasks.\nUse the read tool to load a skill's file when the task matches its description.\nWhen a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n\n<available_skills>\n",
  paste(sprintf("  <skill>\n    <name>%s</name>\n    <description>%s</description>\n    <location>/Users/me/.gptr/skills/%s/SKILL.md</location>\n  </skill>", esc(s$name), esc(s$description), s$name), collapse = "\n"),
  "\n</available_skills>\n</skills>")
compact_catalog = function(s, max_desc = Inf, max_chars = Inf) {
  d = ifelse(nchar(s$description) > max_desc, paste0(substr(s$description, 1, max_desc - 3), "..."), s$description)
  head = "<skills>\nRead ~/.gptr/skills/<name>/SKILL.md when a task matches:\n"
  lines = sprintf("- %s: %s", s$name, d)
  keep = cumsum(nchar(lines) + 1) + nchar(head) <= max_chars
  out = paste0(head, paste(lines[keep], collapse = "\n"))
  if (!all(keep)) out = paste0(out, sprintf("\n(%d more: gptr_skills(\"query\"))", sum(!keep)))
  paste0(out, "\n</skills>")
}
set.seed(7)
so = sample(nrow(sk))
srows = list()
for (n in c(10L, 40L, 160L)) {
  s = sk[so[seq_len(min(n, nrow(sk)))], ]
  srows[[length(srows) + 1]] = data.frame(n_skills = nrow(s), pi_xml = tok_o200k(pi_catalog(s)), compact = tok_o200k(compact_catalog(s)),
    compact_desc250 = tok_o200k(compact_catalog(s, max_desc = 250)),
    pi05_budget_12000chars = tok_o200k(compact_catalog(s, max_desc = 250, max_chars = 12000)),
    budget_3000tok_approx = tok_o200k(compact_catalog(s, max_desc = 160, max_chars = 9000)),
    names_only = tok_o200k(paste(s$name, collapse = ", ")))
}
cat("\nSkills catalog cost in the system prompt (o200k):\n")
print(do.call(rbind, srows), row.names = FALSE)
tok_save()
