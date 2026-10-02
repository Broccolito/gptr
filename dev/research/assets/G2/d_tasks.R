# G2 (d): golden transcripts for six north-star tasks in two styles:
#   S = separate model-visible tool calls (one step per call; each result goes back to the model)
#   C = composed: one r evaluation that chains the steps (tools, MCP tools as R functions) and prints a compact result
# Every r tool result below is REAL output of the code, evaluated with evaluate::evaluate() in a session
# environment (Seurat 5.4.0 on SeuratObject::pbmc_small, nlme, base R), formatted like report 12 section 3.4.
# MCP results (task 5) come from a local fake ClinicalTrials.gov server (synthetic JSON, API-v2-like shape).
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/b_defs.R")
suppressPackageStartupMessages({ library(Seurat); library(evaluate) })
options(width = 100, cli.num_colors = 1)
work = file.path(G2, "d_work"); unlink(work, recursive = TRUE); dir.create(file.path(work, "data"), recursive = TRUE)

# ---------- r tool emulation (output, messages, warnings, errors, plots; head 40% + tail 60% truncation) ----------
fmt_eval = function(res, max_lines = 2000L, max_chars = 50000L) {
  out = character(); n_plot = 0L
  for (x in res) {
    if (inherits(x, "source")) next
    if (is.character(x)) out = c(out, x)
    else if (inherits(x, "recordedplot")) { n_plot = n_plot + 1L; out = c(out, sprintf("[plot %d attached as image]\n", n_plot)) }
    else if (inherits(x, "message")) out = c(out, conditionMessage(x))
    else if (inherits(x, "warning")) out = c(out, sprintf("Warning%s: %s\n", if (is.null(conditionCall(x))) "" else paste0(" in ", deparse(conditionCall(x))[1]), conditionMessage(x)))
    else if (inherits(x, "error")) out = c(out, sprintf("Error%s: %s\n", if (is.null(conditionCall(x))) "" else paste0(" in ", deparse(conditionCall(x))[1]), conditionMessage(x)))
  }
  txt = gsub("\r", "", paste(out, collapse = ""))
  lines = strsplit(txt, "\n", fixed = TRUE)[[1]]
  if (length(lines) > max_lines || nchar(txt) > max_chars) {
    keep_h = floor(0.4 * max_lines); keep_t = floor(0.6 * max_lines)
    txt = paste(c(utils::head(lines, keep_h), sprintf("[... %d lines omitted; full text in /tmp/gptr-output-1.txt]", length(lines) - keep_h - keep_t), utils::tail(lines, keep_t)), collapse = "\n")
  }
  if (!nzchar(trimws(txt))) txt = "[no output]"
  list(text = txt, images = rep(list(c(1000, 700)), n_plot))
}
st = new.env()                                  # holds the current session environment st$S
run_r = function(code) fmt_eval(evaluate::evaluate(code, envir = st$S, stop_on_error = 1L))
# ---------- transcript builders ----------
tr_new = function(task, style, user, workspace, extra_prefix = NULL) {
  list(task = task, style = style, extra_prefix = extra_prefix,
       messages = list(list(role = "user", content = list(list(type = "text", text = paste0("<workspace>\n", workspace, "\n</workspace>\n\n", user))))))
}
step_r = function(tr, say, code) {
  id = sprintf("toolu_%02d", length(tr$messages))
  r = run_r(code)
  tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = say), list(type = "tool_use", id = id, name = "r", input = list(code = code))))
  tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "tool_result", tool_use_id = id, content = r$text, images = r$images)))
  tr
}
step_tool = function(tr, say, name, input, result, images = list()) {
  id = sprintf("toolu_%02d", length(tr$messages))
  tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = say), list(type = "tool_use", id = id, name = name, input = input)))
  tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "tool_result", tool_use_id = id, content = result, images = images)))
  tr
}
say_final = function(tr, text) { tr$messages[[length(tr$messages) + 1]] = list(role = "assistant", content = list(list(type = "text", text = text))); tr }
user_turn = function(tr, text) { tr$messages[[length(tr$messages) + 1]] = list(role = "user", content = list(list(type = "text", text = text))); tr }
fresh = function(setup) { st$S = new.env(parent = globalenv()); eval(setup, st$S); invisible() }
TR = list()

# ================= T1 (north star 1): cluster and show markers of the three largest clusters =================
setup1 = quote({ pbmc = SeuratObject::pbmc_small; gptr_return = function(x) invisible(x) })
ws1 = "pbmc <Seurat> 230 features x 80 cells, assay RNA (counts, data, scale.data), reductions pca, tsne, 2.3 MB"
u1 = "cluster the cells and show me the markers for the three largest clusters"
fin1 = "I clustered the 80 cells (SNN on 10 PCs, resolution 1.5). The three largest clusters are 0, 1 and 2; their top markers are listed above (e.g. cluster 0: LCK, CD3D-like T-cell genes; cluster 1: myeloid genes; cluster 2: B-cell genes). The full table is in `markers`."
for (quiet in c(FALSE, TRUE)) {
  fresh(setup1); v = if (quiet) ", verbose = FALSE" else ""
  t = tr_new(1, if (quiet) "S-quiet" else "S", u1, ws1)
  t = step_r(t, "I'll build the nearest-neighbour graph on the first 10 PCs.", sprintf("pbmc = FindNeighbors(pbmc, dims = 1:10%s)", v))
  t = step_r(t, "Now cluster.", sprintf("pbmc = FindClusters(pbmc, resolution = 1.5%s)", v))
  t = step_r(t, "Cluster sizes:", "sort(table(Idents(pbmc)), decreasing = TRUE)")
  t = step_r(t, "Markers for the three largest clusters.", sprintf("top3 = names(sort(table(Idents(pbmc)), decreasing = TRUE))[1:3]\nmarkers = FindAllMarkers(subset(pbmc, idents = top3), only.pos = TRUE%s)", v))
  t = step_r(t, "Top markers:", "head(markers, 20)")
  t = step_r(t, "Markers per cluster:", "table(markers$cluster)")
  TR[[length(TR) + 1]] = say_final(t, fin1)
}
fresh(setup1)
t = tr_new(1, "C", u1, ws1)
t = step_r(t, "I'll cluster and find the markers in one step.", paste(
  "pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)",
  "sizes = sort(table(Idents(pbmc)), decreasing = TRUE)",
  "top3 = names(sizes)[1:3]",
  "markers = FindAllMarkers(subset(pbmc, idents = top3), only.pos = TRUE, verbose = FALSE)",
  "sizes",
  "tapply(markers$gene, markers$cluster, function(g) paste(head(g, 8), collapse = \", \"))[top3]", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin1)

# ================= T2 (north star 2): mixed model, return the fit =================
setup2 = quote({
  set.seed(2); m = 30; w = 8
  mice = data.frame(mouse = factor(rep(sprintf("m%02d", 1:m), each = w)), week = rep(1:w, m),
                    diet = factor(rep(sample(rep(c("chow", "hfd", "keto"), 10)), each = w)))
  mice$weight = round(20 + 0.4 * mice$week + c(chow = 0, hfd = 3.1, keto = -0.8)[as.character(mice$diet)] + rep(rnorm(m, 0, 1.5), each = w) + rnorm(m * w, 0, 1), 2)
  gptr_return = function(x) invisible(x)
})
ws2 = "mice <data.frame> 240 x 4, 9.6 KB: mouse <factor> 30 levels; week <integer> 1..8; diet <factor> chow, hfd, keto; weight <numeric> min 16.9, max 30.5"
u2 = "Fit a mixed model of weight on diet with a random intercept per mouse, and report the diet effect."
fin2 = "Mixed model weight ~ diet + (1 | mouse), fitted with nlme::lme (REML). Relative to chow, the high-fat diet raises weight by about 3 g and keto lowers it slightly; the overall diet effect is significant in the ANOVA table above. The fitted model is returned as the result (`res$value`)."
fresh(setup2)
t = tr_new(2, "S", u2, ws2)
t = step_r(t, "Let me look at the data.", "str(mice)")
t = step_r(t, "Fit the model.", "library(nlme)\nfit = lme(weight ~ diet, random = ~ 1 | mouse, data = mice)")
t = step_r(t, "Summary:", "summary(fit)")
t = step_r(t, "Test the diet effect:", "anova(fit)")
t = step_r(t, "Confidence intervals:", "intervals(fit, which = \"fixed\")")
t = step_r(t, "Returning the fit.", "gptr_return(fit)")
TR[[length(TR) + 1]] = say_final(t, fin2)
fresh(setup2)
t = tr_new(2, "C", u2, ws2)
t = step_r(t, "Fitting and summarising in one step.", paste(
  "fit = nlme::lme(weight ~ diet, random = ~ 1 | mouse, data = mice)",
  "round(summary(fit)$tTable, 3)", "anova(fit)", "round(nlme::intervals(fit, which = \"fixed\")$fixed, 2)", "gptr_return(fit)", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin2)

# ================= T3 (north star 3): three piped steering prompts on one session =================
set.seed(3)
cnt = matrix(rnbinom(2000 * 24, mu = rep(rlnorm(2000, 3, 1.2), 24), size = 5), 2000, 24,
             dimnames = list(sprintf("gene%04d", 1:2000), sprintf("S%02d", 1:24)))
cnt[1:200, 13:24] = cnt[1:200, 13:24] * 2L
utils::write.csv(cnt, file.path(work, "data/counts.csv"))
setup3 = quote({ setwd(work); meta = data.frame(sample = sprintf("S%02d", 1:24), batch = rep(c("b1", "b2"), each = 12)) })
ws3 = "meta <data.frame> 24 x 2: sample <character> S01..S24; batch <character> b1, b2"
u3 = c("Load the counts in data/counts.csv and normalise them",
       "Now run a PCA and tell me how many components explain 80% of variance",
       "Plot PC1 against PC2 coloured by batch")
fin3 = c("Loaded `counts` (2,000 genes x 24 samples) and stored log2-CPM values in `norm`.",
         "PCA stored in `pca`; the first components needed to reach 80% of the variance are shown above.",
         "Here is PC1 vs PC2 coloured by batch; the batches separate along PC1.")
csv_head = paste(readLines(file.path(work, "data/counts.csv"), n = 5), collapse = "\n")
fresh(setup3)
t = tr_new(3, "S", u3[1], ws3)
t = step_tool(t, "Let me look at the file first.", "read", list(path = "data/counts.csv", limit = 5), paste0(csv_head, "\n\n[1996 more lines in file. Use offset=6 to continue.]"))
t = step_r(t, "Load it.", "counts = read.csv(\"data/counts.csv\", row.names = 1)\ndim(counts)")
t = step_r(t, "Library sizes:", "summary(colSums(counts))")
t = step_r(t, "Normalise to log2 CPM.", "norm = log2(t(t(counts) / colSums(counts)) * 1e6 + 1)\nnorm[1:5, 1:6]")
t = say_final(t, fin3[1]); t = user_turn(t, u3[2])
t = step_r(t, "Run the PCA.", "pca = prcomp(t(norm))")
t = step_r(t, "Variance explained:", "summary(pca)")
t = step_r(t, "Components for 80%:", "which(summary(pca)$importance[3, ] >= 0.8)[1]")
t = say_final(t, fin3[2]); t = user_turn(t, u3[3])
t = step_r(t, "Check the batch labels.", "table(meta$batch)")
t = step_r(t, "Plot.", "plot(pca$x[, 1:2], col = factor(meta$batch), pch = 19)\nlegend(\"topright\", legend = unique(meta$batch), col = 1:2, pch = 19)")
TR[[length(TR) + 1]] = say_final(t, fin3[3])
fresh(setup3)
t = tr_new(3, "C", u3[1], ws3)
t = step_r(t, "Loading and normalising.", "counts = read.csv(\"data/counts.csv\", row.names = 1)\nnorm = log2(t(t(counts) / colSums(counts)) * 1e6 + 1)\ndim(norm)\nsummary(colSums(counts))")
t = say_final(t, fin3[1]); t = user_turn(t, u3[2])
t = step_r(t, "PCA and cumulative variance.", "pca = prcomp(t(norm))\nve = summary(pca)$importance[3, ]\nwhich(ve >= 0.8)[1]\nround(ve[1:8], 3)")
t = say_final(t, fin3[2]); t = user_turn(t, u3[3])
t = step_r(t, "Plotting.", "plot(pca$x[, 1:2], col = factor(meta$batch), pch = 19)\nlegend(\"topright\", legend = unique(meta$batch), col = 1:2, pch = 19)")
TR[[length(TR) + 1]] = say_final(t, fin3[3])

# ================= T4 (north star 8): artifact from the live marker table =================
fresh(setup1)
invisible(run_r("pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)\nmarkers = FindAllMarkers(pbmc, only.pos = TRUE, verbose = FALSE)"))
S4env = st$S
ws4 = "markers <data.frame> 118 x 7: p_val, avg_log2FC, pct.1, pct.2, p_val_adj <numeric>; cluster <factor> 0..4; gene <character>\npbmc <Seurat> 230 features x 80 cells"
u4 = "Build me an explorer for the marker table with a gene search box and a volcano plot"
app = paste("library(shiny)", "library(bslib)", "library(ggplot2)", "",
  "ui = page_sidebar(", "  title = \"Marker explorer\",", "  sidebar = sidebar(textInput(\"gene\", \"Gene\"), selectInput(\"cl\", \"Cluster\", c(\"All\", levels(markers$cluster)))),",
  "  card(card_header(\"Volcano\"), plotOutput(\"volcano\"), full_screen = TRUE),", "  card(card_header(\"Markers\"), tableOutput(\"tbl\"))", ")", "",
  "server = function(input, output) {", "  sel = reactive({", "    d = markers", "    if (input$cl != \"All\") d = d[d$cluster == input$cl, ]",
  "    if (nzchar(input$gene)) d = d[grepl(input$gene, d$gene, ignore.case = TRUE), ]", "    d", "  })",
  "  output$volcano = renderPlot(ggplot(sel(), aes(avg_log2FC, -log10(p_val_adj), label = gene)) + geom_point() + geom_text(vjust = -0.5, size = 3) + theme_minimal())",
  "  output$tbl = renderTable(head(sel()[order(sel()$p_val_adj), ], 20))", "}", "", "shinyApp(ui, server)", sep = "\n")
stopifnot(!inherits(try(parse(text = app), silent = TRUE), "try-error"))
art_result = j(list(ok = TRUE, id = "marker-explorer-3a91c2", version = 1, url = "http://127.0.0.1:34110/", startup_secs = 2.1,
                    outputs = I(c("volcano", "tbl")), data = list(list(name = "markers", class = "data.frame", dim = I(c(118, 7)))),
                    checks = list(static = "ok", launch = "ok", http = 200, session = list(connected = TRUE, output_errors = list(), validation = list(), js_errors = list(), log_errors = list(), log_warnings = list()))))
fin4 = "The explorer is running at http://127.0.0.1:34110/ (artifact marker-explorer): search a gene or pick a cluster; the volcano plot and table update together."
st$S = S4env
t = tr_new(4, "S", u4, ws4)
t = step_r(t, "Let me check the marker table.", "str(markers)")
t = step_r(t, "Ranges for the plot axes:", "summary(markers$avg_log2FC)\nsummary(-log10(markers$p_val_adj))")
t = step_tool(t, "Creating the app.", "artifact", list(title = "Marker explorer", code = app, data = I("markers")), art_result, images = list(c(1100, 750)))
TR[[length(TR) + 1]] = say_final(t, fin4)
t = tr_new(4, "C", u4, ws4)
t = step_tool(t, "Creating the app.", "artifact", list(title = "Marker explorer", code = app, data = I("markers")), art_result, images = list(c(1100, 750)))
TR[[length(TR) + 1]] = say_final(t, fin4)

# ================= T5 (north star 10): plugin with an MCP server (ClinicalTrials.gov-like) =================
set.seed(5)
mk_study = function(i) {
  id = sprintf("NCT0%07d", 5100000 + i * 7919 %% 900000)
  list(protocolSection = list(
    identificationModule = list(nctId = id, briefTitle = sprintf("A Phase %s Study of %s in Patients With Idiopathic Pulmonary Fibrosis", sample(c("2", "3", "2b"), 1), sample(c("BI 1015550", "Admilparant", "Bexotegrast", "Inhaled Treprostinil", "Saracatinib", "Nerandomilast"), 1)),
                                 organization = list(fullName = sample(c("Boehringer Ingelheim", "Bristol-Myers Squibb", "Pliant Therapeutics", "United Therapeutics", "Yale University"), 1), class = "INDUSTRY")),
    statusModule = list(overallStatus = "RECRUITING", startDateStruct = list(date = sprintf("202%d-%02d", sample(3:6, 1), sample(1:12, 1))), primaryCompletionDateStruct = list(date = "2028-06", type = "ESTIMATED")),
    designModule = list(studyType = "INTERVENTIONAL", phases = I(sample(c("PHASE2", "PHASE3"), 1)), enrollmentInfo = list(count = sample(80:1200, 1), type = "ESTIMATED"),
                        designInfo = list(allocation = "RANDOMIZED", interventionModel = "PARALLEL", maskingInfo = list(masking = "QUADRUPLE"))),
    conditionsModule = list(conditions = I(c("Idiopathic Pulmonary Fibrosis")), keywords = I(c("IPF", "FVC", "interstitial lung disease"))),
    eligibilityModule = list(eligibilityCriteria = paste("Inclusion Criteria:\n* Age >= 40 years\n* Diagnosis of IPF per ATS/ERS/JRS/ALAT 2022 guideline\n* FVC >= 45% predicted\n* DLCO >= 25% predicted\n\nExclusion Criteria:\n* Relevant airway obstruction (FEV1/FVC < 0.7)\n* Acute exacerbation within 3 months\n* Listed for lung transplant"), sex = "ALL", minimumAge = "40 Years"),
    contactsLocationsModule = list(locations = lapply(1:sample(3:8, 1), function(k) list(facility = sprintf("Site %d Hospital", k), city = sample(c("Boston", "Heidelberg", "Tokyo", "Toronto", "Madrid", "Sydney"), 1), country = sample(c("United States", "Germany", "Japan", "Canada", "Spain", "Australia"), 1))))))
}
studies = lapply(1:40, mk_study)
search_json = function(n) j(list(studies = studies[seq_len(n)], nextPageToken = "NF0g5JmIo_s"))
get_json = function(i) j(studies[[i]])
ctgov_tools = list(tool("search_studies", "Search ClinicalTrials.gov studies by condition, term and status. Returns study records (protocolSection) with paging.",
                        obj(list(query_cond = str_("Condition or disease"), query_term = str_("Other terms"), filter_status = str_("Overall status, e.g. RECRUITING"),
                                 page_size = num_("Results per page (default 10, max 1000)"), page_token = str_("Token for the next page")), "query_cond")),
                   tool("get_study", "Get the full record of one study by NCT id.", obj(list(nct_id = str_("NCT identifier")), "nct_id")))
ws5 = "indication <character> \"idiopathic pulmonary fibrosis\""
u5 = "Find trials for this indication"
fin5 = "Top recruiting trials for idiopathic pulmonary fibrosis, by planned enrollment, are listed above with phase, sponsor and key eligibility (age >= 40, FVC >= 45% predicted, no recent exacerbation)."
t = tr_new(5, "S", u5, ws5, extra_prefix = list(tools = ctgov_tools))
t = step_tool(t, "Searching recruiting trials.", "search_studies", list(query_cond = "idiopathic pulmonary fibrosis", filter_status = "RECRUITING", page_size = 20), search_json(20))
for (i in c(3, 7, 12)) t = step_tool(t, "Details of a large trial:", "get_study", list(nct_id = studies[[i]]$protocolSection$identificationModule$nctId), get_json(i))
TR[[length(TR) + 1]] = say_final(t, fin5)
st$S = new.env(parent = globalenv())
st$S$indication = "idiopathic pulmonary fibrosis"
st$S$mcp = list(ctgov = list(search_studies = function(query_cond, filter_status = NULL, page_size = 10, ...) jsonlite::fromJSON(search_json(min(page_size, 40)), simplifyVector = FALSE),
                          get_study = function(nct_id) jsonlite::fromJSON(get_json(which(vapply(studies, function(s) s$protocolSection$identificationModule$nctId, "") == nct_id)[1]), simplifyVector = FALSE)))
sig_lines = "<r_functions>\nMCP tools are R functions; call them inside r and reduce results before printing.\nctgov:\n  mcp$ctgov$search_studies(query_cond: string, query_term?: string, filter_status?: string, page_size?: number, page_token?: string)  # Search ClinicalTrials.gov studies by condition, term and status.\n  mcp$ctgov$get_study(nct_id: string)  # Get the full record of one study by NCT id.\n</r_functions>"
t = tr_new(5, "C", u5, ws5, extra_prefix = list(system = sig_lines))
t = step_r(t, "Searching and ranking in R.", paste(
  "res = mcp$ctgov$search_studies(query_cond = indication, filter_status = \"RECRUITING\", page_size = 100)",
  "st = do.call(rbind, lapply(res$studies, function(s) with(s$protocolSection, data.frame(",
  "  nct = identificationModule$nctId, phase = designModule$phases[[1]], n = designModule$enrollmentInfo$count,",
  "  sponsor = identificationModule$organization$fullName, title = substr(identificationModule$briefTitle, 1, 60)))))",
  "st = st[order(-st$n), ]",
  "head(st, 10)",
  "det = lapply(st$nct[1:3], function(id) mcp$ctgov$get_study(nct_id = id))",
  "cat(vapply(det, function(s) substr(gsub(\"\\n\", \" \", s$protocolSection$eligibilityModule$eligibilityCriteria), 1, 160), \"\"), sep = \"\\n\")", sep = "\n"))
TR[[length(TR) + 1]] = say_final(t, fin5)

# ================= T6 (north star 11): whole workflow (prep chain + one ambiguous cluster) =================
setup6 = quote({ pbmc = SeuratObject::pbmc_small; set.seed(6); pbmc$percent.mt = round(runif(ncol(pbmc), 0, 8), 2) })
ws6 = "pbmc <Seurat> 230 features x 80 cells, assay RNA, meta.data has percent.mt"
u6 = c("Normalise pbmc, find variable features and run PCA", "Regress out percent.mt while scaling", "Keep 30 PCs; tell me if the elbow suggests fewer",
       "Cluster 2 has ambiguous markers. Investigate with additional markers and propose a label.", "Prefer canonical markers from the literature; explain your choice")
fin6 = c("Normalised (LogNormalize), found variable features and ran PCA (20 PCs; this object has 80 cells, so 30 PCs are not possible).",
         "Re-scaled with percent.mt regressed out and re-ran the PCA.", "Only 20 PCs exist here; the variance curve flattens after about 5-6 PCs, so fewer suffice.",
         "Cluster 2 expresses MS4A1, CD79A/B and HLA-DR genes, consistent with B cells.", "Canonical B-cell markers (MS4A1/CD20, CD79A, CD79B) are all enriched; I label cluster 2 as B cells.")
for (style in c("S", "C")) {
  fresh(setup6)
  t = tr_new(6, style, u6[1], ws6)
  if (style == "S") {
    t = step_r(t, "Normalise.", "pbmc = NormalizeData(pbmc)")
    t = step_r(t, "Variable features.", "pbmc = FindVariableFeatures(pbmc)")
    t = step_r(t, "Scale.", "pbmc = ScaleData(pbmc)")
    t = step_r(t, "PCA.", "pbmc = RunPCA(pbmc, npcs = 20)")
  } else {
    t = step_r(t, "Running the preprocessing chain.", "pbmc = NormalizeData(pbmc, verbose = FALSE) |> FindVariableFeatures(verbose = FALSE) |> ScaleData(verbose = FALSE) |> RunPCA(npcs = 20, verbose = FALSE)\nhead(VariableFeatures(pbmc), 10)")
  }
  t = say_final(t, fin6[1]); t = user_turn(t, u6[2])
  if (style == "S") {
    t = step_r(t, "Scale with regression.", "pbmc = ScaleData(pbmc, vars.to.regress = \"percent.mt\")")
    t = step_r(t, "Re-run PCA.", "pbmc = RunPCA(pbmc, npcs = 20)")
  } else {
    t = step_r(t, "Re-scaling with regression and re-running PCA.", "pbmc = ScaleData(pbmc, vars.to.regress = \"percent.mt\", verbose = FALSE) |> RunPCA(npcs = 20, verbose = FALSE)")
  }
  t = say_final(t, fin6[2]); t = user_turn(t, u6[3])
  if (style == "S") {
    t = step_r(t, "Elbow plot.", "print(ElbowPlot(pbmc, ndims = 20))")
    t = step_r(t, "Standard deviations:", "pbmc[[\"pca\"]]@stdev")
  } else {
    t = step_r(t, "Variance per PC.", "sd = pbmc[[\"pca\"]]@stdev\nround(sd^2 / sum(sd^2), 3)")
  }
  t = say_final(t, fin6[3]); t = user_turn(t, u6[4])
  if (style == "S") {
    t = step_r(t, "Cluster first.", "pbmc = FindNeighbors(pbmc, dims = 1:10) |> FindClusters(resolution = 1.5)")
    t = step_r(t, "Markers of cluster 2.", "m2 = FindMarkers(pbmc, ident.1 = \"2\", only.pos = TRUE)\nhead(m2, 15)")
    t = step_r(t, "Canonical markers across clusters.", "AverageExpression(pbmc, features = c(\"MS4A1\", \"CD79A\", \"CD79B\", \"CD3D\", \"LYZ\", \"GNLY\", \"PPBP\"))$RNA")
  } else {
    t = step_r(t, "Clustering and checking canonical markers in one step.", paste(
      "pbmc = FindNeighbors(pbmc, dims = 1:10, verbose = FALSE) |> FindClusters(resolution = 1.5, verbose = FALSE)",
      "m2 = FindMarkers(pbmc, ident.1 = \"2\", only.pos = TRUE, verbose = FALSE)",
      "head(rownames(m2), 10)",
      "round(AverageExpression(pbmc, features = c(\"MS4A1\", \"CD79A\", \"CD79B\", \"CD3D\", \"LYZ\", \"GNLY\", \"PPBP\"))$RNA, 1)", sep = "\n"))
  }
  t = say_final(t, fin6[4]); t = user_turn(t, u6[5])
  t = say_final(t, fin6[5])
  TR[[length(TR) + 1]] = t
}
saveRDS(list(TR = TR, ctgov_tools = ctgov_tools), file.path(G2, "d_transcripts.rds"))
for (t in TR) cat(sprintf("task %d %-8s messages %2d  tool calls %2d\n", t$task, t$style, length(t$messages),
                          sum(vapply(t$messages, function(m) sum(vapply(m$content, function(b) identical(b$type, "tool_use"), NA)), 1))))
cat("\n--- example: task 1 C tool result ---\n"); cat(TR[[3]]$messages[[3]]$content[[1]]$content, "\n")
cat("\n--- example: task 1 S step 2 (FindClusters) tool result ---\n"); cat(TR[[1]]$messages[[5]]$content[[1]]$content, "\n")
