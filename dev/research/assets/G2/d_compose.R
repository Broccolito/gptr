# G2 (d): cumulative tokens, round trips and cost of the golden transcripts, per style and provider,
# with and without prompt caching. Tokens are o200k counts of the Anthropic-shaped message JSON
# (images by the Claude patch formula); the prefix is the gptr-7 preset (report G2 part b).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
X = readRDS(file.path(G2, "d_transcripts.rds")); TR = X$TR
img_tok = function(wh) ceiling(wh[1] / 28) * ceiling(wh[2] / 28)          # Claude standard tier, <= 1568 px long edge
sys7 = gptr_prompt(c("read", "r", "edit", "write", "grep", "find", "ls"))
tools7 = gptr_tools[c("read", "r", "edit", "write", "grep", "find", "ls")]
prefix_tokens = function(t) {
  sys = if (!is.null(t$extra_prefix$system)) paste0(sys7, "\n\n", t$extra_prefix$system) else sys7
  tl = if (!is.null(t$extra_prefix$tools)) c(tools7, t$extra_prefix$tools) else tools7
  tok_o200k(wire(tl, sys, "anthropic"))
}
msg_tokens = function(m) {
  blocks = lapply(m$content, function(b) {
    if (identical(b$type, "tool_result")) list(type = "tool_result", tool_use_id = b$tool_use_id, content = list(list(type = "text", text = b$content)))
    else b
  })
  imgs = sum(vapply(m$content, function(b) if (identical(b$type, "tool_result") && length(b$images)) sum(vapply(b$images, img_tok, 1)) else 0, 1))
  c(text = tok_o200k(j(list(role = m$role, content = blocks))), img = imgs)
}
out_tokens = function(m) tok_o200k(j(lapply(m$content, function(b) if (identical(b$type, "tool_use")) list(name = b$name, input = b$input) else b$text)))

# prices, USD per 1M tokens (verified 2026-09-29/30): Anthropic pricing page; OpenAI pricing page; Gemini pricing page
P = list(
  sonnet55 = list(label = "Claude Sonnet 5.5", i = 2, o = 10, read = 0.20, write = 2.50, min = 512, tokf = 1.35),
  opus55 = list(label = "Claude Opus 5.5", i = 4, o = 20, read = 0.20, write = 5.00, min = 512, tokf = 1.35),
  gpt61sol = list(label = "GPT-6.1 Sol", i = 2, o = 10, read = 0.10, write = 2.50, min = 1024, tokf = 1.00),
  gem38flash = list(label = "Gemini 3.8 Flash", i = 0.75, o = 3.75, read = 0.075, write = 0.75, min = 4096, tokf = 1.00))
cost = function(inp, outp, p, cache) {
  inp = inp * p$tokf; outp = outp * p$tokf
  if (!cache) return((sum(inp) * p$i + sum(outp) * p$o) / 1e6)
  total = 0; prev = 0
  for (k in seq_along(inp)) {
    rd = if (prev >= p$min) prev else 0
    new = inp[k] - rd
    total = total + rd * p$read + new * p$write                           # new tail is written to the cache
    prev = inp[k]
  }
  (total + sum(outp) * p$o) / 1e6
}
rows = list(); per_req = list()
for (t in TR) {
  pre = prefix_tokens(t)
  mt = t(vapply(t$messages, msg_tokens, c(text = 0, img = 0)))
  is_a = vapply(t$messages, function(m) m$role == "assistant", NA)
  hist = cumsum(mt[, "text"] + mt[, "img"])
  k_a = which(is_a)
  inp = pre + c(0, hist)[k_a]                                               # everything before assistant message k
  outp = vapply(t$messages[k_a], out_tokens, 1)
  n_tool = sum(vapply(t$messages, function(m) sum(vapply(m$content, function(b) identical(b$type, "tool_use"), NA)), 1))
  res_tok = sum(mt[!is_a, "text"]) - sum(mt[1, "text"])
  r = data.frame(task = t$task, style = t$style, requests = length(k_a), tool_calls = n_tool, prefix = pre,
                 tool_result_tok = res_tok, image_tok = sum(mt[, "img"]), input_cum = sum(inp), output = sum(outp),
                 last_context = max(inp) + tail(outp, 1))
  for (pn in names(P)) {
    r[[paste0(pn, "_nocache")]] = round(cost(inp, outp, P[[pn]], FALSE), 4)
    r[[paste0(pn, "_cache")]] = round(cost(inp, outp, P[[pn]], TRUE), 4)
  }
  rows[[length(rows) + 1]] = r
  per_req[[length(per_req) + 1]] = data.frame(task = t$task, style = t$style, req = seq_along(inp), input = inp, output = outp)
}
d = do.call(rbind, rows)
cat("Per transcript (o200k tokens; cost in USD for one run of the task):\n")
print(d[, c("task", "style", "requests", "tool_calls", "prefix", "tool_result_tok", "image_tok", "input_cum", "output", "last_context")], row.names = FALSE)
cat("\nCost per run (USD), without / with prompt caching; Claude costs include a 1.35x tokenizer factor over o200k:\n")
print(d[, c("task", "style", grep("_(no)?cache$", names(d), value = TRUE))], row.names = FALSE)
cat("\nS / C ratios per task (S = separate tool calls, C = composed r evaluation):\n")
for (k in unique(d$task)) {
  s = d[d$task == k & d$style == "S", ]; cc = d[d$task == k & d$style == "C", ]
  cat(sprintf("  task %d: requests %d vs %d | cumulative input %.2fx | output %.2fx | Sonnet 5.5 cost %.2fx uncached, %.2fx cached | GPT-6.1 Sol cached %.2fx | Gemini 3.8 Flash cached %.2fx\n",
              k, s$requests, cc$requests, s$input_cum / cc$input_cum, s$output / cc$output, s$sonnet55_nocache / cc$sonnet55_nocache,
              s$sonnet55_cache / cc$sonnet55_cache, s$gpt61sol_cache / cc$gpt61sol_cache, s$gem38flash_cache / cc$gem38flash_cache))
}
q = d[d$task == 1, ]
cat(sprintf("\nTask 1 verbosity vs composition: S %d, S-quiet %d, C %d cumulative input tokens\n", q$input_cum[q$style == "S"], q$input_cum[q$style == "S-quiet"], q$input_cum[q$style == "C"]))
tot = aggregate(cbind(requests, tool_calls, input_cum, output, sonnet55_nocache, sonnet55_cache, gpt61sol_cache, gem38flash_cache) ~ style, d[d$style %in% c("S", "C"), ], sum)
cat("\nAll six tasks together:\n"); print(tot, row.names = FALSE)
cat(sprintf("S/C: requests %.2fx, cumulative input %.2fx, output %.2fx, Sonnet 5.5 uncached %.2fx, cached %.2fx\n",
            tot$requests[tot$style == "S"] / tot$requests[tot$style == "C"], tot$input_cum[tot$style == "S"] / tot$input_cum[tot$style == "C"],
            tot$output[tot$style == "S"] / tot$output[tot$style == "C"], tot$sonnet55_nocache[tot$style == "S"] / tot$sonnet55_nocache[tot$style == "C"],
            tot$sonnet55_cache[tot$style == "S"] / tot$sonnet55_cache[tot$style == "C"]))
cat(sprintf("Caching saves %.0f%% (S) and %.0f%% (C) of the Sonnet 5.5 bill; the prefix is %.0f%% of cumulative input in C and %.0f%% in S\n",
            100 * (1 - tot$sonnet55_cache[tot$style == "S"] / tot$sonnet55_nocache[tot$style == "S"]),
            100 * (1 - tot$sonnet55_cache[tot$style == "C"] / tot$sonnet55_nocache[tot$style == "C"]),
            100 * sum((d$prefix * d$requests)[d$style == "C"]) / sum(d$input_cum[d$style == "C"]),
            100 * sum((d$prefix * d$requests)[d$style == "S"]) / sum(d$input_cum[d$style == "S"])))

# ---- System 1 vs System 2 for the nine cluster-label decisions of north star 11 ----
labels = c("T cell", "B cell", "NK cell", "monocyte", "dendritic cell", "platelet", "unclear")
jev_body = function(top) j(list(model = "jev-latest", state = list(markers = top),
  questions = list(cell_type = list(type = "choice", instructions = "Which immune cell type do the marker genes in `markers` indicate?",
                                    criteria = setNames(as.list(labels), labels)))))
example = j(list(model = "jev-latest", state = list(text = "My golden retriever loves long walks on the beach."),
  questions = list(is_dog = list(type = "noul", instructions = "Does `text` describe a dog?", criteria = list(`true` = "The text describes a dog", `false` = "The text does not describe a dog")),
                   animal = list(type = "choice", instructions = "Which animal does `text` describe?", criteria = list(dog = "A dog", cat = "A cat", bird = "A bird", other = "None of these")),
                   cuteness = list(type = "score", instructions = "How positive is the sentiment of `text`?", criteria = list("Very negative", "Neutral", "Very positive")))))
jev_overhead = 443 / tok_o200k(example)
top = "LCK, CD3D, IL32, CD3E, CD2, CD7, GZMA, CCL5, CTSW, CST7"
jev_in = round(tok_o200k(jev_body(top)) * jev_overhead)
s2_prompt = sprintf("Which immune cell type do these marker genes indicate? %s\nAnswer with exactly one of: %s.", top, paste(labels, collapse = ", "))
s2_one = prefix_tokens(list()) + tok_o200k(j(list(role = "user", content = s2_prompt)))
cat(sprintf("\nNine cluster labels (north star 11): Jev ~%d input tokens per decision (o200k body x %.2f, calibrated on report 04a's 443-token request) = %d tokens, $%.6f at $0.042/MTok, output free\n",
            jev_in, jev_overhead, 9 * jev_in, 9 * jev_in * 0.042 / 1e6))
cat(sprintf("System 2 emulation through gptr: %d input tokens per decision (prefix + prompt) = %d for nine calls; Sonnet 5.5 $%.4f uncached, $%.4f with the prefix cached\n",
            s2_one, 9 * s2_one, 9 * (s2_one * 1.35 * 2 + 5 * 1.35 * 10) / 1e6,
            ((s2_one * 1.35) * 2.5 + 8 * ((s2_one - 60) * 1.35 * 0.2 + 60 * 1.35 * 2.5) + 9 * 5 * 1.35 * 10) / 1e6))
saveRDS(list(d = d, per_req = do.call(rbind, per_req)), file.path(G2, "d_metrics.rds"))
tok_save()
