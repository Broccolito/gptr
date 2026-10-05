# Golden-transcript token benchmark (architecture 12.7; contract IC-73). A development tool: it
# is excluded from the package build and needs rtiktoken (o200k_base counts), which is not a
# dependency of gptr.
#
# Each fixture in dev/bench/tokens/fixtures/*.json scripts one north-star session: its prompts,
# attached objects, the model's replies (tool calls with recorded results) and model switches.
# The runner drives gptr's real context assembly: it freezes the prompt, renders the first
# message and turn blocks, and calls request_build() before every scripted reply, so the counts
# measure what gptr would send. The volatile <environment> block is pinned by the fixture, and
# texts owned by plans that are not loaded yet come from the stand-ins of
# tests/testthat/fixtures/bench/prefix-baseline.json (only when no real spec is registered).
#
# Usage (from the repository root):
#   Rscript --vanilla dev/bench/tokens/run.R                 # run, write results.csv
#   Rscript --vanilla dev/bench/tokens/run.R --check         # also compare with baseline.csv
#   Rscript --vanilla dev/bench/tokens/run.R --update [ids]  # rewrite baseline rows (all or ids)
#
# Gates (architecture 12.7): prefix +2%, input_total and output_total +5%, requests and
# image_tokens +0, catalog +5%, facts no loss. A regression raises gptr_error_token_regression.
# The o200k static prefixes of the four cases of prefix-baseline.json are measured on every
# run too and held to its `preset` totals with the prefix gate (architecture 12.1, IC-68).

bench_tolerance = c(prefix = 0.02, input_total = 0.05, output_total = 0.05, requests = 0,
                    image_tokens = 0, catalog = 0.05)
bench_columns = c("case", "requests", "prefix", "input_total", "output_total", "image_tokens",
                  "catalog", "facts", "est_prefix", "est_input_total")

# o200k token counter with an in-memory memo (rtiktoken builds its encoder on every call)
bench_counter = function() {
  memo = new.env(parent = emptyenv())
  function(x) {
    if (is.null(x) || !nzchar(x)) return(0)
    key = cli::hash_sha256(x)
    hit = get0(key, envir = memo, inherits = FALSE)
    if (!is.null(hit)) return(hit)
    n = as.numeric(rtiktoken::get_token_count(x, "o200k_base"))
    assign(key, n, envir = memo)
    n
  }
}

# Text payload of a message (what a tokenizer sees, without wire-format keys) and its images
bench_message_payload = function(m) {
  txt = character()
  img = 0
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context")) txt = c(txt, b$text)
    if (identical(type, "thinking")) txt = c(txt, b$thinking)
    if (identical(type, "tool_call")) txt = c(txt, b$name, json_encode(b$arguments))
    if (identical(type, "image")) {
      img = img + as.numeric(est_image_tokens(b$width %||% 768L, b$height %||% 512L, "anthropic"))
    }
  }
  if (!is.null(m$tool_add)) txt = c(txt, json_encode(m$tool_add))
  list(text = paste(txt, collapse = "\n"), images = img)
}

# Register a fake provider for every model reference of a fixture; returns unregister functions
bench_providers = function(refs) {
  provs = unique(sub("/.*$", "", refs))
  lapply(provs, function(p) gptr_register(gptr_fake_provider(list("(bench)"), name = p)))
}

# prompt_standins_register() of tests/testthat/fixtures/bench/standins.R, which the caller
# sources (bench_main() into the global environment, P24's tests into the runner's): looked up
# by name when called, since lintr cannot see a sourced definition
bench_standins = function(...) {
  get("prompt_standins_register", mode = "function")(...)
}

# The fixture's pinned <environment> block. Its provide function closes over this small frame
# (the text only), never over bench_case()'s frame: the session-scoped registry record would
# otherwise keep the session and the fixture's home objects alive after the case returns
bench_environment_block = function(text) {
  force(text)
  gptr_context_block("environment", function(ctx, budget) text, placement = "first",
                     budget = 100L, order = 200L)
}

# A temporary project (working directory, `opts`, option gptr.project_root and the variable
# GPTR_PROJECT_ROOT, which project_root() reads in that order) until the caller `env` returns
bench_in_project = function(opts = list(), env = parent.frame()) {
  proj = withr::local_tempdir("gptr-bench-", .local_envir = env)
  withr::local_dir(proj, .local_envir = env)
  withr::local_options(c(opts, list(gptr.project_root = proj)), .local_envir = env)
  withr::local_envvar(GPTR_PROJECT_ROOT = proj, .local_envir = env)
  proj
}

# Run one fixture; returns a one-row data frame of metrics
bench_case = function(fx, standins, tok) {
  proj = bench_in_project(list(gptr.interactive = isTRUE(fx$human), gptr.quiet = TRUE))
  dir.create(file.path(proj, ".gptr"))
  for (f in names(fx$files)) {
    p = file.path(proj, f)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(fx$files[[f]], p, useBytes = TRUE)
  }
  refs = unlist(fx$models)
  offs = bench_providers(refs)
  on.exit(for (off in offs) off(), add = TRUE)
  home = new.env()
  for (nm in names(fx$objects)) {
    assign(nm, eval(parse(text = fx$objects[[nm]]), envir = new.env(parent = baseenv())),
           envir = home)
  }
  s = session_new(refs[1], fx$mode %||% "manual", home = home, preset = fx$preset)
  sid = session_data(s)$id
  bench_standins(standins, sid, sections = unlist(fx$standins), only_missing = TRUE)
  if (!is.null(fx$environment)) {
    registry_add(bench_environment_block(fx$environment), source = "session", rank = 0L,
                 session = sid)
  }
  prompt_freeze(s, list(interactive = isTRUE(fx$human)))
  target = model_resolve(refs[1])
  frozen = session_data(s)$frozen
  prefix = tok(frozen$tools_json) + tok(frozen$t0) + tok(frozen$t1)
  est_prefix = est_tokens(frozen$tools_json, "json") + est_tokens(frozen$t0, "prose") +
    (if (nzchar(frozen$t1)) est_tokens(frozen$t1, "prose") else 0)
  m = list(requests = 0, input_total = 0, output_total = 0, image_tokens = 0, est_input = 0)
  facts_found = 0
  n_call = 0L
  for (k in seq_along(fx$turns)) {
    turn = fx$turns[[k]]
    if (!is.null(turn$model)) {
      session_set_model(s, turn$model, reason = "user")
      target = model_resolve(turn$model)
    }
    # P08's gptr_call record (contract 7.8): P09's `attached` block reads the objects through
    # call_value(), which refuses anything else
    call = call_new(context = lapply(turn$context, function(o) {
      list(label = o$label, kind = "symbol", name = o$label,
           facts = list(class = unlist(o$class)))
    }), envir = home, args = list(opts = list()))
    input = list(call = call, turn = k, prompt = turn$prompt)
    blocks = if (k == 1L) context_first_message(s, input) else context_turn_blocks(s, input)
    if (k == 1L) {
      att = paste(vapply(Filter(function(b) identical(b$kind, "attached"), blocks),
                         function(b) b$text, ""), collapse = "\n")
      facts_found = sum(vapply(unlist(fx$facts), function(f) grepl(f, att, fixed = TRUE), NA))
    }
    session_append(s, list(type = "message",
                           message = msg_user(c(blocks, list(block_text(turn$prompt))),
                                              source = turn$source %||% "pipe")))
    for (st in turn$steps) {
      req = request_build(s, target)
      pay = lapply(req$context$messages, bench_message_payload)
      m$requests = m$requests + 1
      m$input_total = m$input_total + prefix + sum(vapply(pay, function(p) tok(p$text), 0)) +
        sum(vapply(pay, function(p) p$images, 0))
      m$image_tokens = m$image_tokens + sum(vapply(pay, function(p) p$images, 0))
      m$est_input = m$est_input + req$tokens_est
      content = list()
      if (!is.null(st$text)) content[[length(content) + 1L]] = block_text(st$text)
      ids = character()
      for (cl in st$calls) {
        n_call = n_call + 1L
        id = cl$id %||% sprintf("toolu_%02d", n_call)
        ids = c(ids, id)
        content[[length(content) + 1L]] = block_tool_call(id, cl$name, cl$input)
      }
      reply = msg_assistant(content, api = target$api, provider = target$provider,
                            model = target$id,
                            stop_reason = if (length(st$calls)) "tool_use" else "stop")
      m$output_total = m$output_total + tok(bench_message_payload(reply)$text)
      session_append(s, list(type = "message", message = reply))
      for (i in seq_along(st$calls)) {
        cl = st$calls[[i]]
        res = list(block_text(cl$result))
        for (im in cl$images) {
          res[[length(res) + 1L]] = block_image("iVBORw0KGgo=", mime = "image/png", source = "plot",
                                                width = as.integer(im[[1]]),
                                                height = as.integer(im[[2]]))
        }
        session_append(s, list(type = "message",
                               message = msg_tool_result(ids[i], cl$name, res,
                                                         details = cl$details)))
      }
    }
  }
  data.frame(case = fx$id, requests = m$requests, prefix = prefix, input_total = m$input_total,
             output_total = m$output_total, image_tokens = m$image_tokens,
             catalog = tok(frozen$t1), facts = facts_found, est_prefix = est_prefix,
             est_input_total = m$est_input, stringsAsFactors = FALSE)
}

# The o200k static prefix (tool array, T0 and T1) of the four cases of prefix-baseline.json,
# composed with the stand-ins only (exclusive), as test-bench-context.R composes them, so the
# committed `preset` totals of architecture 12.1 (IC-68) are re-measured on every run
bench_static = function(pb, tok) {
  proj = bench_in_project()
  off = gptr_register(gptr_fake_provider(list("(bench)"), name = "benchstatic"))
  on.exit(off(), add = TRUE)
  out = numeric()
  for (nm in names(pb$cases)) {
    cs = pb$cases[[nm]]
    s = session_new("benchstatic/benchstatic-1", cs$mode, home = new.env(), preset = cs$preset)
    bench_standins(pb$standins, session_data(s)$id, sections = unlist(cs$sections),
                   exclusive = TRUE)
    doc = if (isTRUE(cs$document)) list(path = file.path(proj, "analysis.R"), format = "R")
    fr = prompt_compose(s, list(interactive = isTRUE(cs$human), doc = doc))
    out[[nm]] = tok(fr$tools_json) + tok(fr$t0) + tok(fr$t1)
  }
  out
}

# Compare results with the baseline (the metrics `res` has); signals
# gptr_error_token_regression listing every failure
bench_compare = function(res, base) {
  bad = character()
  first = NULL
  for (i in seq_len(nrow(res))) {
    b = base[base$case == res$case[i], , drop = FALSE]
    if (!nrow(b)) {
      bad = c(bad, paste0(res$case[i], ": no baseline row (run with --update ", res$case[i], ")"))
      next
    }
    for (k in intersect(names(bench_tolerance), names(res))) {
      limit = b[[k]] * (1 + bench_tolerance[[k]])
      if (res[[k]][i] > limit + 1e-9) {
        bad = c(bad, sprintf("%s: %s %s -> %s (tolerance %+.0f%%)", res$case[i], k,
                             format(b[[k]], big.mark = ","), format(res[[k]][i], big.mark = ","),
                             100 * bench_tolerance[[k]]))
        if (is.null(first)) {
          first = list(fixture = res$case[i], metric = k, baseline = b[[k]], value = res[[k]][i])
        }
      }
    }
    if ("facts" %in% names(res) && res$facts[i] < b$facts) {
      bad = c(bad, sprintf("%s: facts %d -> %d (no loss allowed)", res$case[i], b$facts,
                           res$facts[i]))
      if (is.null(first)) {
        first = list(fixture = res$case[i], metric = "facts", baseline = b$facts,
                     value = res$facts[i])
      }
    }
  }
  if (length(bad)) {
    gptr_abort(c("Token-efficiency regression:", paste0("  ", bad)), "token_regression",
               .data = first)
  }
  invisible(TRUE)
}

bench_main = function(args = commandArgs(trailingOnly = TRUE)) {
  root = normalizePath(".", winslash = "/")
  if (!file.exists(file.path(root, "DESCRIPTION"))) stop("Run from the repository root.")
  if (!requireNamespace("rtiktoken", quietly = TRUE)) {
    stop("dev/bench/tokens/run.R needs the development package rtiktoken (o200k_base counts).")
  }
  for (v in c("R_USER_CONFIG_DIR", "R_USER_DATA_DIR", "R_USER_CACHE_DIR")) {
    d = file.path(tempdir(), "bench-home", v)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    do.call(Sys.setenv, stats::setNames(list(d), v))
  }
  Sys.setenv(GPTR_REPLAY = "replay")
  pkgload::load_all(root, export_all = TRUE, helpers = FALSE, quiet = TRUE)
  fixtures = file.path(root, "tests", "testthat", "fixtures", "bench")
  source(file.path(fixtures, "standins.R"))
  pb = jsonlite::fromJSON(file.path(fixtures, "prefix-baseline.json"), simplifyVector = FALSE)
  standins = pb$standins
  dir = file.path(root, "dev", "bench", "tokens")
  files = sort(list.files(file.path(dir, "fixtures"), pattern = "[.]json$", full.names = TRUE))
  tok = bench_counter()
  t0 = proc.time()[["elapsed"]]
  static = bench_static(pb, tok)
  res = do.call(rbind, lapply(files, function(f) {
    bench_case(jsonlite::fromJSON(f, simplifyVector = FALSE), standins, tok)
  }))
  secs = proc.time()[["elapsed"]] - t0
  utils::write.csv(res, file.path(dir, "results.csv"), row.names = FALSE)
  print(data.frame(static_prefix = names(static), o200k = unname(static),
                   baseline = unname(unlist(pb$preset)[names(static)])), row.names = FALSE)
  print(res[, bench_columns], row.names = FALSE)
  message(sprintf("%d golden transcripts in %.1f s; wrote dev/bench/tokens/results.csv",
                  nrow(res), secs))
  base_file = file.path(dir, "baseline.csv")
  if ("--update" %in% args) {
    ids = setdiff(args, c("--update", "--check"))
    base = res[0, bench_columns]
    if (file.exists(base_file)) base = utils::read.csv(base_file, stringsAsFactors = FALSE)
    new = if (length(ids)) res[res$case %in% ids, , drop = FALSE] else res
    base = rbind(base[!base$case %in% new$case, bench_columns, drop = FALSE], new[, bench_columns])
    base = base[order(base$case, method = "radix"), , drop = FALSE]
    utils::write.csv(base, base_file, row.names = FALSE)
    message("baseline written: ", paste(new$case, collapse = ", "))
  }
  if ("--check" %in% args) {
    if (!file.exists(base_file)) stop("dev/bench/tokens/baseline.csv is missing.")
    base = utils::read.csv(base_file, stringsAsFactors = FALSE)
    # the static prefixes against the committed `preset` totals (the prefix gate)
    pre = function(x) data.frame(case = paste0("prefix-baseline:", names(x)), prefix = unname(x))
    bench_compare(pre(static), pre(unlist(pb$preset)))
    bench_compare(res, base)
    message("OK: ", length(static), " static prefixes and ", nrow(res),
            " golden transcripts within the baseline tolerances")
  }
  invisible(res)
}

if (sys.nframe() == 0L) bench_main()
