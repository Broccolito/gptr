# Stand-ins for texts owned by plans that come after P07 (P09, P10, P11, P13, P15, P17, P19,
# P22, P23): the direct tools (Anthropic schemas of contract 9.2, snippets and guidelines of
# architecture 7.3), the r_session fragments and the documents, artifacts, system1, skills and
# r_env sections, all copied from the specification into prefix-baseline.json (`standins`).
# Sourced by helper-p07.R and dev/bench/tokens/run.R, so that P07's composition of architecture
# 7.3 can be checked before the owners exist.

# The `r` tool's four schema variants (IC-68), built from its full schema: `record` and `note`
# only with a bound document, `timeout` (with the short description) only without a human.
standin_r_parameters = function(full, short) {
  force(full)
  force(short)
  function(ctx) {
    inp = ctx$input
    keep = c("code", if (!is.null(inp$document)) c("record", "note"),
             if (!isTRUE(inp$human)) "timeout")
    p = full
    p$properties = full$properties[keep]
    if ("timeout" %in% keep) p$properties$timeout$description = short
    p
  }
}

# Register the stand-ins of `fx` (the `standins` element of prefix-baseline.json)
#
# @param fx The stand-in data.
# @param session_id Register at rank 0 for this session; `NULL`: rank 3, source "user".
# @param sections Names of stand-in sections to register (fragments and tools always are).
# @param only_missing Register only names that have no registered spec (dev/bench).
# @param exclusive Hide every other section and fragment for this session (tests), so the
#   composition holds exactly P07's texts and the stand-ins.
# @return Registry ids, invisibly.
prompt_standins_register = function(fx, session_id = NULL, sections = character(),
                                    only_missing = FALSE, exclusive = FALSE) {
  rank = if (is.null(session_id)) 3L else 0L
  src = if (is.null(session_id)) "user" else "session"
  add = function(spec) registry_add(spec, source = src, rank = rank, session = session_id)
  ids = character()
  for (t in fx$tools) {
    if (only_missing && !is.null(registry_get("tool", t$name, session = session_id))) next
    params = if (identical(t$name, "r")) {
      standin_r_parameters(t$input_schema, fx$r_timeout_short)
    } else {
      t$input_schema
    }
    ids = c(ids, add(gptr_tool(t$name, t$description, parameters = params,
                               execute = function(input, ctx) "(stand-in)", snippet = t$snippet,
                               guidelines = as.character(unlist(t$guidelines)))))
  }
  mine = c("preamble", "tools", "rules", "r_session", "r_performance", "modes", "context",
           "addendum")
  frag_names = vapply(fx$fragments, function(f) f$name, "")
  existing = prompt_specs("prompt_section", session_id)
  have_frag = any(vapply(existing, function(x) identical(x$parent, "r_session"), NA))
  if (exclusive) {
    keep = c(mine, frag_names, sections)
    for (x in existing) {
      if (x$name %in% keep) next
      ids = c(ids, add(gptr_prompt_section(x$name, function(ctx) NULL, tier = x$tier %||% "T0",
                                           order = as.integer(x$order %||% 500L),
                                           budget = 1L, parent = x$parent)))
    }
  }
  if (!(only_missing && have_frag)) {
    for (f in fx$fragments) {
      ids = c(ids, add(gptr_prompt_section(f$name, f$text, tier = "T0",
                                           order = as.integer(f$order), budget = 300L,
                                           parent = f$parent)))
    }
  }
  for (sc in fx$sections) {
    if (!sc$name %in% sections) next
    if (only_missing && !is.null(registry_get("prompt_section", sc$name, session = session_id))) {
      next
    }
    ids = c(ids, add(gptr_prompt_section(sc$name, sc$text, tier = sc$tier,
                                         order = as.integer(sc$order),
                                         budget = as.integer(sc$budget))))
  }
  invisible(ids)
}

# The prefix-baseline.json fixture as a list
prefix_fixture = function() {
  jsonlite::fromJSON(testthat::test_path("fixtures", "bench", "prefix-baseline.json"),
                     simplifyVector = FALSE)
}
