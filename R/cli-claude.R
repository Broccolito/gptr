# The cli-claude adapter (P20): the user's own claude CLI in stream-json mode, one long-lived
# child per session (per run while it carries budget flags), gptr's tools through the
# in-process `sdk` MCP server over the control protocol (architecture 8.3; contract 8.5,
# IC-65). L1: besides L0 helpers and the shared helpers of cli-common.R it calls only the
# injected opts$send, opts$gate and opts$mcp_dispatch and P12's anthropic_normaliser() (IC-33).
# Adapted from the verified driver of report 07 section 5.7 (cc_proto.R: argv, control
# protocol, notification acks) and its live capture 3.14 (the fixture claude-call2.ndjson).

# ---- build (Task 5) ----------------------------------------------------------------------------

#' The claude argv of architecture 8.3 in its exact order, then the budget flags (IC-65,
#' IC-66), the documented --bare opt-out when the probe found one, and --resume (never --bare)
#'
#' A budget value that is not a positive finite number adds no flag (pcli_claude_flags());
#' `turns` is rounded down (at least 1), `cost` rounded to 4 decimals (at least 0.01), both
#' written as plain decimal numbers whatever `OutDec` and `digits` say.
#' @noRd
pcli_claude_args = function(model_id, mcp_config, system_file, budget = NULL, optout = NULL,
                           resume = NULL) {
  args = c("-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--include-partial-messages", "--tools", "", "--strict-mcp-config",
           "--setting-sources", "", "--disable-slash-commands", "--mcp-config", mcp_config,
           "--permission-prompt-tool", "stdio", "--permission-mode", "default",
           "--allowedTools", "mcp__gptr__*", "--system-prompt-file", system_file,
           "--model", model_id)
  flags = pcli_claude_flags(budget)
  if (!is.null(flags$turns)) {
    args = c(args, "--max-turns", pcli_claude_number(max(1, floor(flags$turns))))
  }
  if (!is.null(flags$cost)) {
    args = c(args, "--max-budget-usd", pcli_claude_number(max(0.01, round(flags$cost, 4))))
  }
  if (!is.null(optout)) args = c(args, optout)
  if (!is.null(resume)) args = c(args, "--resume", resume)
  args
}

#' The budget flags a child is started with: `turns` and `cost` when each is a positive finite
#' number, else NULL (no flag, no limit, as without a budget; P06's budget_check() stays
#' authoritative between requests)
#' @param budget list(turns, cost) or NULL.
#' @return list(turns = num(1) | NULL, cost = num(1) | NULL)
#' @noRd
pcli_claude_flags = function(budget) {
  fin = function(x) {
    x = pcli_scalar_num(x)
    if (!is.null(x) && is.finite(x)) x else NULL
  }
  list(turns = fin(budget[["turns"]]), cost = fin(budget[["cost"]]))
}

#' A budget number as an argv word: plain decimal, `.` as the decimal mark, up to 15
#' significant digits, independent of options(OutDec, digits, scipen)
#' @noRd
pcli_claude_number = function(x) {
  format(x, scientific = FALSE, trim = TRUE, digits = 15L, decimal.mark = ".", big.mark = "")
}

#' The --mcp-config file content: gptr's in-process sdk server (contract 8.5, verbatim)
#' @noRd
pcli_claude_mcp_json = function() '{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}'

#' Write the MCP config and the system-prompt files of a session once, under tempdir(); a
#' restarted child (--resume) gets the same files (07 2.16: the same system prompt on resume)
#' @return list(mcp, system): the two paths, also kept in `state` (`claude_mcp_file`,
#'   `claude_system_file`).
#' @noRd
pcli_claude_files = function(state, context, session) {
  dir = file.path(tempdir(), "gptr", "cli")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  stem = paste0(session %||% id_new("s", 10L), "-claude")
  if (is.null(state$claude_mcp_file) || !file.exists(state$claude_mcp_file)) {
    state$claude_mcp_file = path_norm(file.path(dir, paste0(stem, "-mcp.json")))
    write_utf8(state$claude_mcp_file, pcli_claude_mcp_json())
  }
  if (is.null(state$claude_system_file) || !file.exists(state$claude_system_file)) {
    state$claude_system_file = path_norm(file.path(dir, paste0(stem, "-system.md")))
    write_utf8(state$claude_system_file, pcli_system_text(context))
  }
  list(mcp = state$claude_mcp_file, system = state$claude_system_file)
}

#' Anthropic content blocks of the new input: text, rendered context blocks, base64 images
#' (07 2.14: the stream-json user message takes Anthropic content blocks)
#'
#' A block whose text is empty or only white space is dropped, as P12's anthropic_user() does:
#' the Messages API refuses white-space-only text blocks. Input without any block becomes the
#' single text block "(no new input)".
#' @noRd
pcli_claude_content = function(input) {
  out = list()
  for (m in input) {
    for (b in m[["content"]] %||% list()) {
      type = b[["type"]] %||% ""
      blk = if (identical(type, "image") && is.character(b[["data"]])) {
        list(type = "image", source = list(type = "base64",
                                           media_type = b[["mime"]] %||% "image/png",
                                           data = b[["data"]]))
      } else {
        txt = pcli_block_text(b)
        if (nzchar(trimws(txt))) list(type = "text", text = txt) else NULL
      }
      if (!is.null(blk)) out[[length(out) + 1L]] = blk
    }
  }
  if (!length(out)) out = list(list(type = "text", text = "(no new input)"))
  out
}

#' The stdin line of one user turn (contract 8.5; 07 3.12)
#' @noRd
pcli_claude_user_line = function(content) {
  list(type = "user", message = list(role = "user", content = content),
       parent_tool_use_id = NULL, session_id = "")
}

#' Does a child carry budget flags (`--max-turns`, `--max-budget-usd`)? Only a positive finite
#' value makes a flag (pcli_claude_flags()), so the argv, the reuse rule of build() and Task 9's
#' retirement of a budgeted child agree
#' @param flags list(turns, cost) or NULL.
#' @noRd
pcli_claude_budgeted = function(flags) {
  fl = pcli_claude_flags(flags)
  !is.null(fl$turns) || !is.null(fl$cost)
}

#' build(): reuse the session's live claude child, or start one (find, probe, notice, files,
#' argv, the `initialize` control request), then send the turn (contract 8.1 process_jsonl,
#' 8.5)
#'
#' A child is reused for the same model while it lives, but a child with budget flags only
#' within the run that started it: the flags are fixed at launch and the CLI counts cost for its
#' whole process, while gptr's budgets restart with every top-level call (IC-66). A replaced
#' child is retired here through pcli_stop_child() (stdin closed, then P05's
#' stream_process_kill()), and the new one resumes the CLI session. A reused child or a resumed
#' session gets the turns it has not seen (another model may have answered them,
#' pcli_unseen()); a fresh child gets the whole earlier conversation.
#'
#' The turn's lines are written by P05's transport with write_all(); a fresh child's first user
#' line carries the earlier conversation and the input's images, so it is not bounded. On
#' Windows that write blocks until the CLI has read it (D-019 item 5).
#' @noRd
pcli_claude_build = function(model, context, opts) {
  state = pcli_state(opts)
  state$pcli_request_id = context[["request_id"]]
  state$interrupt_id = NULL
  state$interrupt_acked = FALSE
  pcli_track(opts[["session"]], state)
  model_id = pcli_model_id(model)
  par = pcli_params(context)
  parts = pcli_split(context[["messages"]] %||% list())
  flags = pcli_claude_flags(par)
  same_run = identical(state$claude_run, opts[["run"]])
  unbudgeted = !pcli_claude_budgeted(flags) && !pcli_claude_budgeted(state$claude_flags)
  reuse = identical(state$cli_api, "cli-claude") && identical(state$claude_model, model_id) &&
    pcli_alive(pcli_child(state)) && (same_run || unbudgeted)
  start = NULL
  send = list()
  resume = NULL
  if (!reuse) {
    if (pcli_alive(pcli_child(state))) pcli_stop_child(state, wait_ack = FALSE)
    path = pcli_find("claude")
    probe = pcli_probe(path)
    pcli_notice("claude")
    files = pcli_claude_files(state, context, opts[["session"]])
    resume = state$claude_session
    args = pcli_claude_args(model_id, files$mcp, files$system, budget = flags,
                           optout = probe$bare_optout, resume = resume)
    start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                 env_profile = "cli-claude", env = character(), wd = path_norm(getwd()))
    state$cli_api = "cli-claude"
    state$claude_model = model_id
    state$claude_run = opts[["run"]]
    state$claude_flags = flags
    # the new process's own cumulative total_cost_usd starts here (Task 6 records increases)
    state$claude_cost_seen = 0
    state$n_req = 0L
    send = list(pcli_control_request(state, list(subtype = "initialize", hooks = NULL)))
  }
  seen = reuse || !is.null(resume)
  history = pcli_history_text(if (seen) pcli_unseen(parts$prior, model$provider) else parts$prior)
  content = pcli_claude_content(parts$input)
  if (nzchar(history)) content = c(list(list(type = "text", text = history)), content)
  list(start = start, send = c(send, list(pcli_claude_user_line(content))), close_stdin = FALSE)
}
