# jev-router.R: a complexity router for gptr (contract IC-69; architecture 11.1 "Model routers").
# A session that uses it plans on a strong model when System 1 rates the request as complex (on
# a standard model otherwise) and implements on a cheap model after the first successful edit or
# write, so it switches models once and pays one prompt-cache miss. A port of Pi's
# packages/coding-agent/examples/extensions/jev-router.ts (MIT, Pi 1b347794; report 04 section
# 2.11), which routes between three OpenAI Codex models.
#
# Use it in one of three ways, where `path` stands for the file's location, the value of
# `system.file("gptr", "examples", "jev-router.R", package = "gptr")` in your session:
#
# 1. As an extension. Copy the file into .gptr/extensions/ of a trusted project, or into the
#    extensions/ folder of `tools::R_user_dir("gptr", "config")`. Its last expression is the
#    factory, which registers the router "jev-auto", so that a later call selects it by name,
#    as in `peter("Refactor the cache layer.", model = "jev-auto")` for example. The file also
#    loads with `extensions = path`, which registers "jev-auto" for that one session only.
# 2. Registered by hand for this R session. Source the file into a new environment `env` with
#    `sys.source(path, envir = env)`, register the router with
#    `gptr_register(env$jev_router_spec())` and then call peter() with `model = "jev-auto"`.
# 3. With other models, passing the router itself as the model, for example as in
#    `model = env$jev_router_spec(strong = "opus", standard = "sonnet", implement = "haiku")`.
#
# System 1 rates the first prompt through ctx$decide(), which uses the configured System 1 model
# (a TYPESAFE_API_KEY, a prepared local decision model such as ollama/clef-flash, or
# gptr_config(system1 = ...)). Without one, or when the rating fails, the router plans on
# `standard`. The router allows 120 s per call (gptr_router()'s default is 2 s), the time one
# System 1 request may take while a local decision model loads; a call slower than that falls
# back to the default chat model (an error when none is set), and the next request rates again. A
# session that already runs on `strong` or `standard` keeps it, so a continued session does not
# pay a second cache miss. Compaction summaries use `implement`, and the router's phase survives
# them; a compaction after the first successful edit or write starts the implementation phase.

jev_router_spec = function(strong = "opus", standard = "sonnet", implement = "haiku",
                           name = "jev-auto") {
  force(strong)
  force(standard)
  force(implement)
  edit_tools = c("edit", "write")

  # Did a tool call since the last user message edit a file successfully?
  edited_this_turn = function(messages) {
    start = 1L
    for (i in seq_along(messages)) {
      if (identical(messages[[i]]$role, "user")) start = i + 1L
    }
    for (m in messages[seq_along(messages) >= start]) {
      done = identical(m$role, "tool_result") && isTRUE(m$tool_name %in% edit_tools)
      if (done && !isTRUE(m$is_error)) return(TRUE)
    }
    FALSE
  }

  # The planning model: strong for complex work, standard otherwise or without System 1
  choose_planner = function(request, ctx) {
    previous = request$previous
    if (is.character(previous) && length(previous) == 1L && previous %in% c(strong, standard)) {
      return(previous)
    }
    prompt = request$prompt
    if (!is.character(prompt) || length(prompt) != 1L || is.na(prompt)) return(standard)
    choices = c(standard = "Ordinary features, fixes, reviews, or questions",
                complex = "Subtle design, cross-cutting changes, or hard debugging")
    rating = tryCatch({
      ctx$decide("How demanding is the software engineering work requested?",
                 substr(prompt, 1L, 16000L), choices = choices)
    }, error = function(e) NULL)
    if (is.null(rating)) return(standard)
    p = gptr::gptr_prob(rating, "probabilities")
    if (isTRUE(p[1L, "complex"] >= 0.5)) strong else standard
  }

  route = function(request, ctx) {
    state = request$state
    planning_done = identical(state$phase, "planning") && edited_this_turn(request$messages)
    # A compaction (or any request outside a turn) runs on the cheap model. gptr records a
    # router's state only when the model changes, so this switch to `implement` carries the
    # phase: the same one, or the implementation once an edit has succeeded (the next turn, on
    # `implement` already, records nothing)
    if (!identical(request$reason, "turn")) {
      if (planning_done) state = list(phase = "implementation", model = implement)
      return(list(model = implement, state = state))
    }
    if (is.null(state)) {
      model = choose_planner(request, ctx)
      return(list(model = model, state = list(phase = "planning", model = model)))
    }
    if (planning_done) {
      return(list(model = implement, state = list(phase = "implementation", model = implement)))
    }
    list(model = state$model, state = state)
  }

  # 120 s per call instead of the default 2 s: enough for one System 1 rating on a cold model
  description = "Plans on a strong model chosen by System 1; implements on a cheap one"
  gptr::gptr_router(name, route = route, description = description, timeout = 120)
}

function(gptr) {
  gptr$register(jev_router_spec())
}
