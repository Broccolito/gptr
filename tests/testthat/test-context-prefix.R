# P07 Task 14: the 20-turn byte-prefix property (architecture 12.7; G4 section 5.9, adapted to
# the gptr kernel). Consecutive requests to the same model are byte prefixes across turns, model
# switches and returns, tool and skill activation, steering and mode changes; compaction keeps
# the tools, the system blocks and the anchored project block; negative controls are detected.

scn_new = function(targets, mode = "manual") {
  sc = new.env(parent = emptyenv())
  sc$targets = targets
  sc$key = names(targets)[1]
  sc$s = session_new(targets[[1]]$ref, mode, home = new.env())
  prompt_freeze(sc$s, list(interactive = FALSE))
  sc$requests = list()
  sc$turn = 0L
  sc$n_call = 0L
  sc$sig = 0L
  sc
}

scn_target = function(sc) sc$targets[[sc$key]]

scn_ncompact = function(sc) {
  sum(vapply(prompt_path(sc$s), function(e) identical(e$type, "compaction"), NA))
}

# The canonical request body: the elements joined in the Anthropic key order; open (no closing
# "]}") it is a byte prefix of the next request's body (G4 5.4)
prompt_request_body = function(elements, open = FALSE) {
  m = elements[-(1:3)]
  body = paste0("{\"tools\":", elements[["tools"]], ",\"system\":[", elements[["t0"]], ",",
                elements[["t1"]], "],\"messages\":[", paste(m, collapse = ","))
  if (open) body else paste0(body, "]}")
}

scn_record = function(sc, kind, extra = NULL, guard = TRUE) {
  tg = scn_target(sc)
  req = request_build(sc$s, tg, extra = extra)
  if (guard) prefix_guard(sc$s, tg, req$view)
  el = prompt_request_elements(req$context)
  rec = list(kind = kind, key = sc$key, req = req, el = el, body = prompt_request_body(el),
             open = prompt_request_body(el, open = TRUE), ncompact = scn_ncompact(sc))
  sc$requests[[length(sc$requests) + 1L]] = rec
  invisible(req)
}

scn_append = function(sc, msg) session_append(sc$s, list(type = "message", message = msg))

scn_user = function(sc, prompt, extra = list()) {
  sc$turn = sc$turn + 1L
  blocks = if (sc$turn == 1L) {
    context_first_message(sc$s, list(turn = 1L, prompt = prompt))
  } else {
    context_turn_blocks(sc$s, list(turn = sc$turn, prompt = prompt))
  }
  scn_append(sc, msg_user(c(blocks, extra, list(block_text(prompt)))))
  invisible(sc)
}

scn_step = function(sc, text = NULL, calls = list()) {
  scn_record(sc, "turn")
  tg = scn_target(sc)
  sc$sig = sc$sig + 1L
  sig = strrep(sprintf("%04d", sc$sig), 20)
  origin = list(api = tg$api, provider = tg$provider, model = tg$id)
  content = list(block_thinking(paste("plan", sc$sig), signature = sig, origin = origin))
  if (!is.null(text)) content[[length(content) + 1L]] = block_text(text)
  ids = character()
  for (cl in calls) {
    sc$n_call = sc$n_call + 1L
    id = sprintf("call_%03d", sc$n_call)
    ids = c(ids, id)
    content[[length(content) + 1L]] = block_tool_call(id, cl$name, cl$args)
  }
  stop = if (length(calls)) "tool_use" else "stop"
  scn_append(sc, msg_assistant(content, api = tg$api, provider = tg$provider, model = tg$id,
                               stop_reason = stop))
  for (k in seq_along(calls)) {
    out = list(block_text(calls[[k]]$out))
    scn_append(sc, msg_tool_result(ids[k], calls[[k]]$name, out, details = calls[[k]]$details))
  }
  invisible(sc)
}

scn_switch = function(sc, key) {
  sc$key = key
  session_set_model(sc$s, sc$targets[[key]]$ref, reason = "user")
  invisible(sc)
}

rcall = function(code, out, note = NULL) {
  list(name = "r", args = list(code = code), out = out,
       details = list(code = code, note = note, status = "ok"))
}

tcall = function(name, args, out) list(name = name, args = args, out = out)

scn_run = function(targets, mutate = NULL) {
  sc = scn_new(targets)
  scn_user(sc, "cluster the cells and show me the markers for the three largest clusters")
  scn_step(sc, "I will build the neighbour graph first.",
           list(rcall("pbmc = FindNeighbors(pbmc, dims = 1:30)", "Computing SNN")))
  note = "resolution 0.8 chosen because 0.4 merged two groups"
  scn_step(sc, NULL, list(rcall("pbmc = FindClusters(pbmc, resolution = 0.8)",
                                "Number of communities: 27", note = note)))
  scn_step(sc, NULL, list(rcall("markers = FindAllMarkers(subset(pbmc, idents = 0:2))",
                                "4,211 x 7")))
  scn_step(sc, "The three largest clusters are 0, 1 and 2; markers are in `markers`.")
  scn_user(sc, "which cluster has the highest CD14 expression?")
  scn_step(sc, NULL, list(rcall("tapply(FetchData(pbmc, 'CD14')[[1]], Idents(pbmc), mean)",
                                "1 3.10")))
  scn_step(sc, "Cluster 1 (mean 3.10).")
  session_set_mode(sc$s, "auto")
  scn_user(sc, "annotate the three largest clusters")
  scn_step(sc, NULL, list(rcall("top = split(markers$gene, markers$cluster)", "top <list>")))
  relay = "The user sent this message while you were working: also label cluster 3"
  steer = msg_operator("steer_relay", relay, origin_text = "also label cluster 3")
  session_append(sc$s, prompt_operator_entry(steer))
  scn_step(sc, NULL, list(rcall("annot = c(`0` = 'T', `1` = 'Mono', `2` = 'B')", "annot",
                                note = "labels from canonical markers")))
  scn_step(sc, "Annotated clusters 0-3.")
  if (is.function(mutate)) mutate(sc)
  skill = block_context("skill_content", "Group large tables with data.table.",
                        attrs = list(name = "high-performance-r"))
  scn_user(sc, "speed up the marker search", extra = list(skill))
  scn_step(sc, NULL, list(tcall("read", list(path = "R/markers.R"),
                                "markers = lapply(clusters, f)")))
  edits = list(list(oldText = "lapply(", newText = "future_lapply("))
  scn_step(sc, NULL, list(tcall("edit", list(path = "R/markers.R", edits = edits),
                                "Successfully replaced 1 block(s) in R/markers.R.")))
  scn_step(sc, "Switched to future.apply.")
  scn_switch(sc, names(targets)[2])
  scn_user(sc, "summarise progress so far in three bullets")
  scn_step(sc, "- clustered\n- annotated\n- sped up")
  scn_switch(sc, names(targets)[3])
  scn_user(sc, "write a reusable QC function in R/qc.R")
  scn_step(sc, NULL, list(tcall("write", list(path = "R/qc.R", content = "qc = 1"),
                                "Successfully wrote to R/qc.R")))
  scn_step(sc, "Added qc().")
  schema = list(type = "object", required = I("condition"),
                properties = list(condition = list(type = "string")))
  trials = gptr_tool("trials", "Search ClinicalTrials.gov by condition.", parameters = schema,
                     execute = function(input, ctx) "12 trials")
  session_add_tools(sc$s, trials)
  scn_user(sc, "find recruiting trials for sepsis")
  scn_step(sc, NULL, list(tcall("trials", list(condition = "sepsis"), "12 trials")))
  scn_step(sc, "12 recruiting trials.")
  scn_switch(sc, names(targets)[1])
  scn_user(sc, "plot the UMAP coloured by annotation")
  scn_step(sc, NULL, list(rcall("p_umap = DimPlot(pbmc, group.by = 'annot')", "[plot 1]")))
  scn_step(sc, "The UMAP separates the types.")
  for (p in c("make the points smaller", "explain the cluster 2 markers",
              "export the marker tables")) {
    scn_user(sc, p)
    scn_step(sc, NULL, list(rcall("head(markers)", "gene p_val")))
    scn_step(sc, "Done.")
  }
  scn_user(sc, "run differential expression for all clusters")
  scn_step(sc, NULL, list(rcall("de_all = FindAllMarkers(pbmc)", "38,112 x 7")))
  session_set_mode(sc$s, "edits")
  mode_block = Filter(function(b) identical(b$kind, "mode"), context_turn_blocks(sc$s, list()))
  prompt_pending_add(sc$s, msg_operator("mode", mode_block[[1]]$text))
  scn_step(sc, NULL, list(rcall("nrow(de_all)", "[1] 38112")))
  scn_step(sc, "21,877 significant genes.")
  # the body of the checkpoint request for the prefix comparison; compact_run() sends (and
  # guards) the request itself, with its own message time stamp
  scn_record(sc, "summary", extra = msg_user(compact_request_text(NULL)), guard = FALSE)
  compact_run(sc$s, "manual")
  for (p in c("continue with the pathway analysis", "compare with resolution 0.4")) {
    scn_user(sc, p)
    scn_step(sc, NULL, list(rcall("gs = split(de_all$gene, de_all$cluster)", "gs <list>")))
    scn_step(sc, "Prepared.")
  }
  scn_switch(sc, names(targets)[4])
  scn_user(sc, "draft the methods paragraph")
  scn_step(sc, "Cells were clustered with Louvain.")
  scn_switch(sc, names(targets)[1])
  for (p in c("tighten it to 80 words", "list the objects you created",
              "name the three largest clusters", "save the session objects")) {
    scn_user(sc, p)
    scn_step(sc, "OK.")
  }
  scn_user(sc, "check the cluster sizes once more")
  scn_step(sc, NULL, list(rcall("table(Idents(pbmc))", "0 812044")))
  scn_step(sc, "Largest four: 0, 1, 2, 3.")
  sc
}

# Consecutive requests to the same target: from, to, whether a compaction lies between them and
# whether the earlier open body is a byte prefix of the later body.
scn_pairs = function(sc) {
  reqs = sc$requests
  keys = vapply(reqs, function(r) r$key, "")
  out = list()
  for (i in seq_along(reqs)) {
    j = which(keys == reqs[[i]]$key & seq_along(reqs) > i)[1]
    if (is.na(j)) next
    out[[length(out) + 1L]] = data.frame(from = i, to = j, key = reqs[[i]]$key,
                                         compaction = reqs[[j]]$ncompact > reqs[[i]]$ncompact,
                                         prefix = startsWith(reqs[[j]]$body, reqs[[i]]$open))
  }
  do.call(rbind, out)
}

scn_targets = function(.env = parent.frame()) {
  checkpoint = "## Goal\n- characterise pbmc\n## Next steps\n- pathway analysis"
  for (p in c("fa", "fb", "fc", "fd")) {
    local_fake_provider(function(request) checkpoint, name = p, .env = .env)
  }
  lapply(c(fa = "fa/fa-1", fb = "fb/fb-1", fc = "fc/fc-1", fd = "fd/fd-1"), model_resolve)
}

scn_breaks = function(sc) {
  sum(vapply(prompt_path(sc$s), function(e) identical(e$custom_type, "gptr.cache_break"), NA))
}

test_that("20 turns: every same-model request pair without compaction is a byte prefix", {
  p07_project(list("AGENTS.md" = "- Style: = for assignment, |> for pipes."))
  sc = scn_run(scn_targets())
  pairs = scn_pairs(sc)
  expect_identical(sc$turn, 20L)
  expect_length(sc$requests, 40L)
  expect_identical(nrow(pairs), 36L)
  expect_identical(sum(!pairs$compaction), 35L)
  expect_true(all(pairs$prefix[!pairs$compaction]))
  expect_true(any(pairs$to - pairs$from > 1L & !pairs$compaction))
  expect_identical(scn_breaks(sc), 0L)
})

test_that("compaction keeps the tools, the system blocks and the anchored project block", {
  p07_project(list("AGENTS.md" = "- Style: = for assignment, |> for pipes."))
  sc = scn_run(scn_targets())
  pairs = scn_pairs(sc)
  cp = pairs[pairs$compaction, ]
  expect_identical(nrow(cp), 1L)
  a = sc$requests[[cp$from[1]]]
  b = sc$requests[[cp$to[1]]]
  expect_identical(unname(a$el[1:3]), unname(b$el[1:3]))
  pa = a$req$context$messages[[1]]$content[[1]]
  pb = b$req$context$messages[[1]]$content[[1]]
  expect_identical(pa$text, pb$text)
  expect_true(isTRUE(pb$anchor))
  sm = which(vapply(sc$requests, function(r) r$kind, "") == "summary")
  expect_true(startsWith(sc$requests[[sm]]$body, sc$requests[[sm - 1L]]$open))
})

test_that("negative controls: a re-rendered system prompt and an edited entry break the prefix", {
  p07_project(list("AGENTS.md" = "- Style: = for assignment, |> for pipes."))
  targets = scn_targets()
  rerender = scn_run(targets, mutate = function(sc) {
    d = session_data(sc$s)
    d$frozen$t0 = paste0(d$frozen$t0, "\n<state>turn ", sc$turn, "</state>")
  })
  pairs = scn_pairs(rerender)
  expect_gte(sum(!pairs$prefix & !pairs$compaction), 1L)
  expect_gte(scn_breaks(rerender), 1L)
  edited = scn_run(targets, mutate = function(sc) {
    d = session_data(sc$s)
    i = which(vapply(d$entries, function(e) identical(e$message$role, "tool_result"), NA))[1]
    d$entries[[i]]$message$content[[1]]$text = "[output elided]"
  })
  expect_gte(scn_breaks(edited), 1L)
})
