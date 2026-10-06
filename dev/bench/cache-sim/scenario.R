# The scripted session the cache simulator prices (plan P24): eight turns through gptr's real
# request path with two fake providers, a switch to the second model and back, and a 12-minute
# idle pause before turn 6 (G4 section 5.7). The fake providers log every request they receive.

cache_sim_codes = c(
  "Load qc_tbl and summarise percent.mt" = paste(
    "qc = data.frame(sample = rep(c('a', 'b', 'c'), 40), mt = ((1:120) %% 25) / 100)",
    "summary(qc$mt)", sep = "\n"),
  "Flag samples with mt above 0.15" = "qc$flag = qc$mt > 0.15\ntable(qc$sample, qc$flag)",
  "Count the flags by sample" = "aggregate(flag ~ sample, data = qc, FUN = sum)",
  "Use 0.12 as the cut-off instead" = "qc$flag = qc$mt > 0.12\ntable(qc$flag)",
  "Report the final counts" = "tab = table(qc$sample[qc$flag])\ntab")

cache_sim_prompts = c("Load qc_tbl and summarise percent.mt", "Flag samples with mt above 0.15",
                      "Count the flags by sample", "Summarise the flags in one sentence",
                      "Use 0.12 as the cut-off instead", "Report the final counts",
                      "Anything else to check?", "Thanks; a one-line summary please")

# Runs the scenario in run.R's temporary home (bench_load_gptr(); it records a project trust);
# returns list(requests = the logged requests, tools_json, idle_turn).
cache_sim_scenario = function() {
  log = new.env(parent = emptyenv())
  log$requests = list()
  script = function(request) {
    log$requests[[length(log$requests) + 1L]] = list(model = request$model, turn = log$turn,
                                                     system = request$system,
                                                     messages = request$messages)
    msgs = request$messages
    if (identical(msgs[[length(msgs)]]$role, "tool_result")) {
      return(sprintf("Turn %d is done; the result is above.", log$turn))
    }
    if (request$last_user %in% names(cache_sim_codes)) {
      return(list(tool = "r", input = list(code = cache_sim_codes[[request$last_user]],
                                           note = "scenario step")))
    }
    sprintf("Answer for turn %d: nothing else is needed.", log$turn)
  }
  # the scenario's fixed code runs without asking whatever the permission rules say (IC-53); the
  # trusted project's AGENTS.md puts BP2's anchored block in the first message (architecture 6.11)
  proj = withr::local_tempdir("gptr-cache-sim-")
  withr::local_dir(proj)
  withr::local_options(gptr.unsafe_no_permissions = TRUE, gptr.project_root = proj)
  writeLines(c("# AGENTS.md", "- QC tables: one row per cell; percent.mt is a fraction.",
               "- Style: = for assignment, |> for pipes, snake_case."), "AGENTS.md")
  gptr_trust(proj, trust = TRUE)
  main = gptr_fake_provider(script, name = "simopus")
  cheap = gptr_fake_provider(script, name = "simhaiku")
  e = new.env(parent = globalenv())
  s = NULL
  for (k in seq_along(cache_sim_prompts)) {
    log$turn = k
    p = cache_sim_prompts[[k]]
    s = if (k == 1L) {
      peter(prompt = p, model = main, mode = "auto", envir = e)
    } else if (k == 4L) {
      peter(s, prompt = p, model = cheap)
    } else if (k == 5L) {
      peter(s, prompt = p, model = main)
    } else {
      peter(s, prompt = p)
    }
  }
  list(requests = log$requests, tools_json = as.character(session_data(s)$frozen$tools_json),
       idle_turn = 6L)
}
