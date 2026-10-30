# gptr-child.R -- coaching jobs, each in its own R process (plan P29 T7, layer L6, area `gptr`;
# 08 section 3.3). The parent sends a job as data over the trusted path (an .rds file in a private
# folder); the child runs it unattended under peter's checks and a process-wide fence, streams what
# ran to its stdout, and writes its result as plain JSON, which the parent rebuilds from a fixed
# list of kinds and reads in the safe direction.

# ---- plain data across processes (08 section 3.3) ------------------------------------------------

plain_types = c("logical", "integer", "double", "character", "factor", "Date", "POSIXct",
                "data.frame", "list", "summary")
plain_keys = c("type", "len", "data", "na", "names", "dim", "levels", "tz", "nrow")
# nesting depth, elements of one value, values of one result, characters of a summary, bytes of
# a result file
plain_max = list(depth = 20L, len = 1e6, nodes = 1e5, summary = 2000L, bytes = 64 * 2^20)

#' A value as plain JSON-ready data (08 section 3.3): `{type, len, data, na, names, dim, levels,
#' tz, nrow}`. Numbers are base64 of little-endian writeBin(), so they stay exact (NA, NaN, -0);
#' anything else, a value these keys do not rebuild exactly (plain_exact()), or a value nested or
#' sized beyond plain_max, is its printed summary. Depth and values count from the first call, as
#' plain_decode() counts them: a value may use `max` values less one for each later sibling, so a
#' list of many values ends in summaries.
#' @noRd
plain_encode = function(x, depth = 0L, max = plain_max$nodes,
                        seen = new.env(parent = emptyenv())) {
  if (is.null(x)) return(NULL)
  n0 = seen$n %||% 0L
  seen$n = n0 + 1L
  if (depth >= plain_max$depth || n0 + 1L + (if (is.list(x)) length(x) else 0L) > max ||
        length(x) > plain_max$len || isS4(x)) {
    return(plain_summary(x))
  }
  each = function(v) {
    Map(plain_encode, unname(v), max = max - (length(v) - seq_along(v)),
        MoreArgs = list(depth = depth + 1L, seen = seen))
  }
  if (is.data.frame(x)) {
    if (!plain_exact(x, "data.frame")) return(plain_summary(x))
    cols = each(unclass(x))
    if (any(vapply(cols, function(c) identical(c$type, "summary"), NA))) {
      seen$n = n0 + 1L
      return(plain_summary(x))
    }
    return(list(type = "data.frame", len = length(x), nrow = nrow(x), names = I(names(x)),
                data = cols))
  }
  type = if (is.null(oldClass(x))) {
    intersect(typeof(x), c("logical", "integer", "double", "character", "list"))
  } else if (is.factor(x)) {
    "factor"
  } else if (is.double(x) && (inherits(x, "Date") || inherits(x, "POSIXct"))) {
    if (inherits(x, "Date")) "Date" else "POSIXct"
  }
  if (!length(type) || !plain_exact(x, type)) return(plain_summary(x))
  out = list(type = type, len = length(x), data = switch(type,
    character = I(replace(as.character(x), is.na(x), "")),
    list = each(x),
    plain_bin(if (is.double(x)) as.double(x) else as.integer(x))))
  if (type == "character" && anyNA(x)) out$na = I(which(is.na(as.character(x))))
  if (!is.null(names(x))) out$names = I(names(x))
  if (!is.null(dim(x))) out$dim = I(dim(x))
  if (type == "factor") out$levels = I(levels(x))
  if (type == "POSIXct") out$tz = attr(x, "tzone")
  out
}

#' Do the plain keys rebuild a value of `type` exactly? Not with dimnames, an ordered factor's
#' class, a data frame's own row names or more than one time zone, nor with NA names or levels,
#' or text that is neither latin1 nor valid UTF-8 (text marked as bytes included)
#' @noRd
plain_exact = function(x, type) {
  text = function(s) {
    !anyNA(s) && all(Encoding(s) == "latin1" | (Encoding(s) != "bytes" & validUTF8(s)))
  }
  text(names(x) %||% character()) && switch(type,
    data.frame = .row_names_info(x) <= 0L,
    is.null(dimnames(x)) && (is.null(attr(x, "tzone")) || rlang::is_string(attr(x, "tzone"))) &&
      (type != "character" || text(x[!is.na(x)])) &&
      (type != "factor" || (identical(oldClass(x), "factor") && text(levels(x)) &&
                              !anyDuplicated(levels(x)))))
}

#' Little-endian bytes of an integer or double vector, as base64
#' @noRd
plain_bin = function(v) {
  gsub("\n", "", jsonlite::base64_enc(writeBin(v, raw(), endian = "little")), fixed = TRUE)
}

#' The printed summary of a value outside the plain kinds, clipped; at most 200 entries are
#' printed, since printing a long list takes time quadratic in its length
#' @noRd
plain_summary = function(x) {
  old = options(max.print = 200L)
  on.exit(options(old), add = TRUE)
  txt = tryCatch(paste(utils::capture.output(print(x)), collapse = "\n"), error = function(e) "")
  txt = paste0("<", paste(class(x), collapse = "/"), ">", if (nzchar(txt)) "\n", txt)
  list(type = "summary", len = 1L, data = child_clip(txt, plain_max$summary))
}

#' A value from plain JSON (plain_encode()'s output, or its text): only the fixed kinds are
#' rebuilt, with readBin(), structure() and .POSIXct(), and a summary is its text. A value beyond
#' the caps, or with an unknown key or type, is refused (gptr_error_untrusted).
#' @noRd
plain_decode = function(json) {
  node = if (is.character(json)) json_decode(json) else json
  seen = new.env(parent = emptyenv())
  seen$n = 0L
  plain_node(node, 0L, seen)
}

#' Refuse a child's result
#' @noRd
plain_bad = function(why) {
  gptr_abort(paste0("A coaching child's result was refused: ", why, "."), "untrusted",
             what = "coaching result", path = NULL)
}

#' A JSON array (or scalar) of `n` strings
#' @noRd
plain_chr = function(x, n) {
  v = unlist(x) %||% character()
  if (!is.character(v) || anyNA(v) || length(v) != n) plain_bad("a value has malformed text")
  v
}

#' A JSON array (or scalar) of whole numbers
#' @noRd
plain_int = function(x) {
  v = unlist(x) %||% integer()
  if (!is.numeric(v) || anyNA(v) || any(v != trunc(v)) || any(abs(v) > .Machine$integer.max)) {
    plain_bad("a value has a malformed number")
  }
  as.integer(v)
}

#' One node of plain_decode()
#' @noRd
plain_node = function(node, depth, seen) {
  if (is.null(node)) return(NULL)
  seen$n = seen$n + 1L
  if (depth > plain_max$depth || seen$n > plain_max$nodes) {
    plain_bad("it is nested too deeply or holds too many values")
  }
  if (!is.list(node) || is.null(names(node)) || !all(names(node) %in% plain_keys) ||
        !rlang::is_string(node$type) || !node$type %in% plain_types) {
    plain_bad("a value has an unknown key or type")
  }
  type = node$type
  len = plain_int(node$len)
  if (length(len) != 1L || len < 0L || len > plain_max$len) plain_bad("a value's length is invalid")
  if (type %in% c("list", "data.frame") && (!is.list(node$data) || length(node$data) != len)) {
    plain_bad("a list has the wrong length")
  }
  if (type == "data.frame") {
    nr = plain_int(node$nrow)
    cols = lapply(node$data, plain_node, depth + 1L, seen)
    if (length(nr) != 1L || nr < 0L || any(vapply(cols, NROW, 1L) != nr)) {
      plain_bad("a data frame has the wrong shape")
    }
    return(structure(cols, names = plain_chr(node$names, len),
                     row.names = .set_row_names(nr), class = "data.frame"))
  }
  x = switch(type,
    summary = plain_chr(node$data, 1L),
    character = {
      na = plain_int(node$na)
      if (any(na < 1L | na > len)) plain_bad("a value has a malformed NA index")
      replace(plain_chr(node$data, len), na, NA_character_)
    },
    list = lapply(node$data, plain_node, depth + 1L, seen),
    plain_numbers(node, type, len))
  if (!is.null(node$dim)) {
    d = plain_int(node$dim)
    if (any(d < 0L) || prod(d) != length(x)) plain_bad("a value has an invalid dim")
    dim(x) = d
  }
  if (!is.null(node$names)) names(x) = plain_chr(node$names, length(x))
  x
}

#' The numbers of a logical, integer, double, factor, Date or POSIXct node
#' @noRd
plain_numbers = function(node, type, len) {
  size = if (type %in% c("double", "Date", "POSIXct")) 8L else 4L
  raw = tryCatch(jsonlite::base64_dec(plain_chr(node$data, 1L)), error = function(e) NULL)
  if (length(raw) != len * size) plain_bad("a value's numbers do not match its length")
  v = readBin(raw, if (size == 8L) "double" else "integer", n = len, size = size,
              endian = "little")
  switch(type,
    logical = as.logical(v),
    factor = {
      lv = plain_chr(node$levels, length(unlist(node$levels)))
      if (anyDuplicated(lv) || any(!is.na(v) & (v < 1L | v > length(lv)))) {
        plain_bad("a factor has invalid levels")
      }
      structure(v, levels = lv, class = "factor")
    },
    Date = structure(v, class = "Date"),
    POSIXct = .POSIXct(v, tz = if (!is.null(node$tz)) plain_chr(node$tz, 1L)),
    v)
}

# ---- the parent: scheduling and reading (08 sections 3.3 and 3.7) --------------------------------

#' Run coaching jobs, each in its own R process (08 section 3.3)
#'
#' A job is `list(id, role = "run" | "coach" | "judge", spec, prompt, objects, args, model,
#' schema, budget, direction)`: `spec` a harness spec, `prompt` the interpolated prompt, `objects`
#' a named list, `args` resolved peter() arguments, `model` a reference or a provider spec,
#' `schema` a coach's reply schema, `direction` "final" (default) or "start" (the safe reading of
#' the run's report); a coach's `surface`, `base` and `rules_allowed` are read by
#' coach_child_reply(). Children run on the worker pool, at most two at once per plan account;
#' once a plan reports its limit, its later jobs are not started (status `skipped`). Interrupting
#' this call kills every child.
#' @param jobs A list of jobs.
#' @return One plain-data result per job, in order: `list(id, status, reason, text, turns,
#'   usage, value, objects, transcript, risk, refusals, unmet, files, plan, limit, checks,
#'   error)`.
#' @noRd
coach_run_jobs = function(jobs) {
  check_list(jobs, "jobs")
  for (job in jobs) child_job_check(job)
  ctx = new.env(parent = emptyenv())
  ctx$jobs = jobs
  ctx$kinds = vapply(jobs, function(j) coach_model_kind(j$model), "")
  ctx$out = vector("list", length(jobs))
  ctx$limits = list()
  ctx$base = list(options = child_options(), parent = proc_self())
  if (any(vapply(jobs, function(j) identical(j$role, "run"), NA))) {
    ctx$run = list(registry = worker_registry(character()), rules = child_rules(),
                   instructions = child_instructions())
  }
  items = lapply(child_lanes(ctx$kinds), function(ix) {
    force(ix)
    list(pool = "worker", start = function() child_lane(ctx, ix))
  })
  subagent_schedule(items, max_total = subagent_limit("worker"))
  ctx$out
}

#' Check one job before anything starts; an object that cannot cross processes is refused
#' @noRd
child_job_check = function(job) {
  check_list(job, "jobs", named = TRUE)
  check_string(job$id, "id")
  check_choice(job$role, c("run", "coach", "judge"), "role")
  check_choice(job$direction %||% "final", c("final", "start"), "direction")
  check_string(job$prompt, "prompt", empty = TRUE)
  check_list(job$objects, "objects", named = TRUE, null = TRUE)
  check_list(job$args, "args", named = TRUE, null = TRUE)
  bad = names(Filter(worker_unserialisable, c(job$objects, job$args, list(model = job$model))))
  if (length(bad)) {
    gptr_abort(paste0("`", bad[[1L]], "` cannot be sent to a coaching run: it holds an external ",
                      "pointer or a connection."),
               "invalid_argument", arg = bad[[1L]], expected = "objects that can cross processes")
  }
  invisible(job)
}

#' The job indices each pool slot runs in turn: one per job, but at most two slots per plan
#' account (08 section 3.7)
#' @noRd
child_lanes = function(kinds) {
  plan = kinds %in% c("claude", "codex")
  lanes = as.list(which(!plan))
  for (k in unique(kinds[plan])) {
    ix = which(kinds == k)
    lanes = c(lanes, unname(split(ix, rep_len(1:2, length(ix)))))
  }
  lanes[order(vapply(lanes, function(l) l[[1L]], 1L))]
}

#' Start one slot: a handle whose `run` settles when its last job has ended
#' @noRd
child_lane = function(ctx, ix) {
  ln = new.env(parent = emptyenv())
  ln$id = id_new("cl", 8L)
  ln$queue = ix
  ln$settled = FALSE
  child_next(ctx, ln)
  list(run = ln, cancel = function() child_cancel(ctx, ln))
}

#' Start a slot's next job, skipping those of a plan that reported its limit
#' @noRd
child_next = function(ctx, ln) {
  ln$st = NULL
  while (length(ln$queue)) {
    i = ln$queue[[1L]]
    ln$queue = ln$queue[-1L]
    id = ctx$jobs[[i]]$id
    limit = ctx$limits[[ctx$kinds[[i]]]]
    if (!is.null(limit)) {
      ctx$out[[i]] = child_result_new(id, status = "skipped", reason = "plan limit", limit = limit)
      next
    }
    ln$st = tryCatch(child_spawn(ctx, ln, i), error = function(e) {
      ctx$out[[i]] = child_result_new(id, error = conditionMessage(e))
      NULL
    })
    if (!is.null(ln$st)) return(invisible(ln))
  }
  ln$settled = TRUE
  invisible(ln)
}

#' Spawn the child of job `i` through proc_rscript()'s `child` entry, with a job row, the
#' process marker of the orphan sweep and the line reader of its stream. Its temporary folder is
#' the private launch folder, so the run's scratch folder goes when the parent cleans up.
#' @noRd
child_spawn = function(ctx, ln, i) {
  job = ctx$jobs[[i]]
  run = identical(job$role, "run")
  st = new.env(parent = emptyenv())
  st$i = i
  st$risk = 0L
  st$refusals = child_refusals()
  st$unmet = character()
  st$stderr = character()
  st$dir = tempfile("gptr-child-")
  dir.create(st$dir, mode = "0700")
  started = FALSE
  on.exit(if (!started) child_cleanup(st), add = TRUE)
  spec_path = file.path(st$dir, "spec.rds")
  st$result_path = file.path(st$dir, "result.json")
  # a coach or judge gets no registry, rules or instruction files (08 section 3.3)
  save_rds(c(ctx$base, if (run) ctx$run, list(job = job, provider = if (!run) {
    child_provider(job$model)
  })), spec_path, refhook = worker_refhook)
  key = if (is.character(job$model)) worker_key_provider(job$model)
  env = child_env("worker", pass = names(coach_cli_env(ctx$kinds[[i]])),
                  set = c(TMPDIR = path_norm(st$dir)), provider = key)
  st$p = proc_rscript("child", list(path_norm(spec_path), path_norm(st$result_path)),
                      dir = st$dir, env = env, .marker = proc_marker_new(),
                      .on_spawn = function(p) st$p = p)
  st$watch = reactor_proc(st$p, on_line = function(line) child_line(st, line),
                          on_exit = function(status) child_exit(ctx, ln, st, status),
                          on_stderr = function(line) {
                            st$stderr = utils::tail(c(st$stderr, line), 20L)
                          })
  st$job = id_new("c", 8L)
  job_add("worker", st$job, name = paste("coaching", job$role, job$id), pid = st$p$get_pid(),
          stop = function() child_cancel(ctx, ln))
  started = TRUE
  st
}

#' The parent's own line reader of a child's stdout: only the coaching event lines are read
#' (`risk`, `refusal`, `unmet`, `limit`); any other line is ignored and none opens a prompt
#' @noRd
child_line = function(st, line) {
  obj = tryCatch(json_decode(line), error = function(e) NULL)
  if (!is.list(obj) || !rlang::is_string(obj$gptr_coach)) return(invisible(NULL))
  str = function(x) if (rlang::is_string(x)) substr(x, 1L, 2000L) else NA_character_
  type = obj$gptr_coach
  lv = obj$level
  if (type == "risk" && is.numeric(lv) && length(lv) == 1L && isTRUE(lv %in% 0:4)) {
    st$risk = max(st$risk, as.integer(lv))
  } else if (type == "refusal" && nrow(st$refusals) < 1000L) {
    st$refusals = rbind(st$refusals, data.frame(id = str(obj$id), tool = str(obj$tool),
                                                reason = str(obj$reason)))
  } else if (type == "unmet" && length(st$unmet) < 1000L) {
    st$unmet = unique(c(st$unmet, str(obj$id)))
  } else if (type == "limit") {
    st$limit = list(resets_at = str(obj$resets_at))
  }
  invisible(NULL)
}

#' A child exited: its result file read in the safe direction with its stream (a result that
#' cannot be read or merged is an error), then its slot moves on
#' @noRd
child_exit = function(ctx, ln, st, status) {
  st$watch = NULL
  job = ctx$jobs[[st$i]]
  dir = job$direction %||% "final"
  tail = redact(paste(st$stderr, collapse = "\n"))
  none = child_result_new(job$id, error = paste0(
    "the coaching child exited (status ", status, ") without a result",
    if (nzchar(tail)) paste0(": ", tail)))
  res = tryCatch(child_merge(child_read(st$result_path) %||% none, st, dir), error = function(e) {
    child_merge(child_result_new(job$id, error = conditionMessage(e)), st, dir)
  })
  res$id = job$id
  ctx$out[[st$i]] = res
  if (!is.null(res$limit)) ctx$limits[[ctx$kinds[[st$i]]]] = res$limit
  child_cleanup(st)
  child_next(ctx, ln)
}

#' A child's result file, read with json_decode() and rebuilt by plain_decode() within a size
#' cap, each field in the shape the parent reads it in; NULL when there is none
#' @noRd
child_read = function(path) {
  size = file.size(path)
  if (is.na(size)) return(NULL)
  if (size > plain_max$bytes) plain_bad("it is larger than 64 MiB")
  res = plain_decode(rawToChar(readBin(path, "raw", n = size)))
  out = child_result_new("")
  if (!is.list(res) || is.null(names(res)) || !all(names(res) %in% names(out))) {
    plain_bad("it does not have the shape of a result")
  }
  out[names(res)] = res
  str = function(x) rlang::is_string(x)
  opt = function(f) function(x) is.null(x) || f(x)
  cols = c("input", "output", "cost")
  shapes = list(
    status = str, text = str, transcript = str, first_user = str, reason = opt(str),
    error = opt(str), refusals = is.list, unmet = is.character, checks = is.character,
    files = opt(is.data.frame), limit = opt(is.list),
    turns = function(x) rlang::is_scalar_integerish(x, finite = TRUE) && x >= 0,
    risk = function(x) rlang::is_scalar_integerish(x) && x %in% 0:4,
    usage = opt(function(x) {
      is.data.frame(x) && all(cols %in% names(x)) && all(vapply(x[cols], is.numeric, NA))
    }),
    objects = function(x) is.list(x) && all(nzchar(names(x) %||% rep("", length(x)))))
  ok = vapply(names(shapes), function(k) isTRUE(shapes[[k]](out[[k]])), NA)
  if (!all(ok)) plain_bad(paste0("its `", names(ok)[!ok][[1L]], "` has the wrong shape"))
  out
}

#' The safe reading of a run's report (08 section 3.3): for a final the worse of its file and its
#' stream (the higher risk, every refusal and unmet requirement), for a starting run, whose risk
#' is the ceiling of the finals, the lower risk
#' @noRd
child_merge = function(res, st, direction) {
  risk = c(as.integer(res$risk), st$risk)
  res$risk = if (identical(direction, "start")) min(risk) else max(risk)
  r = rbind(child_refusals(res$refusals), st$refusals)
  res$refusals = child_refusals(r[!duplicated(r$id), , drop = FALSE])
  res$unmet = unique(c(as.character(unlist(res$unmet)), st$unmet))
  res$limit = res$limit %||% st$limit
  res
}

#' A child's refusals as data.frame(id, tool, reason); anything else is none
#' @noRd
child_refusals = function(x = NULL) {
  if (!is.data.frame(x) || !all(c("id", "tool", "reason") %in% names(x)) || !nrow(x)) {
    return(data.frame(id = character(), tool = character(), reason = character()))
  }
  data.frame(id = as.character(x$id), tool = as.character(x$tool),
             reason = as.character(x$reason))
}

#' A result with every field, `status` "error" unless given; the objects and then the value come
#' last, so that plain_encode() keeps the other fields whole and the objects a list
#' @noRd
child_result_new = function(id, ...) {
  out = list(id = id, status = "error", reason = NULL, text = "", turns = 0L, usage = NULL,
             transcript = "", first_user = "", risk = 0L, refusals = child_refusals(),
             unmet = character(), files = NULL, plan = NULL, limit = NULL, checks = character(),
             error = NULL, objects = list(), value = NULL)
  dots = list(...)
  out[names(dots)] = dots
  out
}

#' Kill a child's tree, stop watching it, and remove its folder and job row
#' @noRd
child_cleanup = function(st) {
  if (!is.null(st$watch)) reactor_cancel(st$watch)
  st$watch = NULL
  kill_all(st$p, grace = 0)
  unlink(st$dir, recursive = TRUE)
  if (!is.null(st$job)) job_remove(st$job)
  st$job = NULL
  invisible(NULL)
}

#' Stop a slot (an interrupt, or gptr_jobs(kill = TRUE)): its child is killed, and it and the
#' slot's later jobs end `aborted`
#' @noRd
child_cancel = function(ctx, ln) {
  ix = c(if (!is.null(ln$st)) ln$st$i, ln$queue)
  if (!is.null(ln$st)) child_cleanup(ln$st)
  for (i in ix) {
    ctx$out[[i]] = child_result_new(ctx$jobs[[i]]$id, status = "aborted",
                                    error = "the coaching job was stopped")
  }
  ln$queue = integer()
  ln$st = NULL
  ln$settled = TRUE
  invisible(NULL)
}

#' The person's effective permission rules for a run's child; path globs relative to the project
#' are anchored to its root (as rule_call_path() writes an outside path), since the child's own
#' root is its scratch folder
#' @noRd
child_rules = function(root = project_root()) {
  anchor = paste0("/", path_norm(root))
  lapply(perm_rules_effective(), function(rules) {
    vapply(rules, function(r) {
      p = tryCatch(rule_parse(r), error = function(e) NULL)
      if (is.null(p) || p$kind != "glob" || grepl("^(~/|/)", p$value)) return(r)
      sep = if (grepl("/", p$value, fixed = TRUE)) "/" else "/**/"
      paste0(p$tool, "(", anchor, sep, p$value, ")")
    }, "", USE.NAMES = FALSE)
  })
}

#' Copies of the project's instruction files: `list(label, text)` each
#' @noRd
child_instructions = function() {
  files = Filter(function(f) !isTRUE(f$user), context_instruction_files())
  lapply(files, function(f) list(label = f$label, text = read_utf8(f$path)$text))
}

#' The gptr options a child gets as the parent has them: the guards, the size and turn limits,
#' the sub-agent limits and the replay mode
#' @noRd
child_options = function() {
  keys = c("critical_guard", "secret_guard", "protect_size", "max_turns",
           paste0("subagents.", c("max_active", "max_cli", "max_workers", "max_tasks",
                                  "max_depth")))
  opts = stats::setNames(lapply(keys, setting_get), paste0("gptr.", keys))
  c(opts, list(gptr.replay = replay_mode()))
}

#' The provider record a model reference names, sent to a coach's child when the person
#' registered it (a coach gets no registry); gptr's own providers are left to the child
#' @noRd
child_provider = function(model) {
  if (!is.character(model)) return(NULL)
  recs = registry_candidates("provider", sub("[/:].*$", "", model), NULL)
  if (length(recs) && !startsWith(recs[[1L]]$source, "builtin:")) recs[[1L]]$spec
}

# ---- the child (08 section 3.3) ------------------------------------------------------------------

#' The `child` entry of proc_rscript() (08 section 3.3)
#'
#' Runs one job unattended in a fresh scratch folder that is its working folder and project root,
#' with recording off, the model gate of 08 section 1.5, sub-agents inline, the fence and the
#' event stream; a run calls its harness, a coach or judge calls peter with no tool and a reply
#' schema. Writes the plain-data result as JSON. Everything it changes is restored on exit.
#' @param spec_path The job file the parent wrote (save_rds()).
#' @param result_path Where the JSON result goes.
#' @param out The connection of the event stream: by default the process's own stdout (fd 1),
#'   which the sink of an `r` evaluation does not capture.
#' @return The job's status, invisibly.
#' @noRd
child_main = function(spec_path, result_path, out = NULL) {
  p = readRDS(spec_path, refhook = worker_refhook)
  job = p$job
  run = identical(job$role, "run")
  dir = tempfile("gptr-run-")
  dir.create(dir, mode = "0700")
  dir = path_norm(dir)
  wd = setwd(dir)
  on.exit({
    setwd(wd)
    unlink(dir, recursive = TRUE)
  }, add = TRUE)
  old = options(c(list(gptr.interactive = FALSE, gptr.noninteractive_ask = "stop",
                       gptr.record = "off", gptr.quiet = TRUE, gptr.verbose = 0L,
                       gptr.project_root = dir), p$options))
  on.exit(options(old), add = TRUE)
  keep = list(rules = the$rules_session, gate = the$model_gate, role = the$coach_role)
  on.exit({
    the$rules_session = keep$rules
    the$model_gate = keep$gate
    the$coach_role = keep$role
  }, add = TRUE)
  the$rules_session = p$rules
  the$coach_role = if (run) "run" else "coach"
  the$model_gate = coach_model_kind
  cs = new.env(parent = emptyenv())
  cs$out = out %||% tryCatch(processx::conn_create_fd(1L, close = FALSE),
                             error = function(e) stdout())
  if (inherits(cs$out, "processx_connection")) {
    on.exit(processx::processx_conn_close(cs$out), add = TRUE)
  }
  cs$risk = 0L
  cs$calls = 0L
  cs$refusals = child_refusals()
  cs$levels = new.env(parent = emptyenv())
  ids = child_register(p, cs)
  on.exit(for (id in ids) registry_remove(id), add = TRUE)
  # a login token goes to the CLI's own environment only (08 section 3.7)
  token = Sys.getenv("CLAUDE_CODE_OAUTH_TOKEN", unset = NA)
  if (!is.na(token) && nzchar(token)) {
    prof = child_env_profiles_builtin()[["cli-claude"]]
    prof$set = list(CLAUDE_CODE_OAUTH_TOKEN = secret_register(token, "CLAUDE_CODE_OAUTH_TOKEN",
                                                              source = "environment"))
    ids = c(ids, registry_add(do.call(gptr_spec, c(list("child_env", "cli-claude"), prof)),
                              source = "user", rank = 3L))
    Sys.unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
    # auth-dotenv.R's restorer: the one file that may set a variable (test-lint-rules.R)
    on.exit(env_restore_python(c(CLAUDE_CODE_OAUTH_TOKEN = token), "CLAUDE_CODE_OAUTH_TOKEN",
                               is_windows()), add = TRUE)
  }
  for (f in p$instructions) {
    dir.create(dirname(file.path(dir, f$label)), recursive = TRUE, showWarnings = FALSE)
    write_atomic(file.path(dir, f$label), f$text)
  }
  before = tools::md5sum(list.files(dir, recursive = TRUE, all.files = TRUE, full.names = TRUE))
  parent = p$parent
  task = reactor_task(function() {
    if (!is.null(parent) && !isTRUE(pid_alive(parent$pid, parent$create_time))) {
      quit(save = "no", status = 3L, runLast = FALSE)
    }
    2
  })
  on.exit(reactor_cancel(task), add = TRUE)
  env = new.env(parent = globalenv())
  objects = job$objects %||% list()
  names(objects) = child_bind(names(objects))
  list2env(objects, envir = env)
  out = tryCatch(eval(child_call(job, run), env), error = function(e) e)
  # a coach's reply is checked here, so its one retry is a follow-up in the same session
  reply = if (!run && !is.null(job$base)) coach_child_reply(job, out, env)
  if (!is.null(reply)) out = reply$out
  res = child_outcome(job, out, env, objects, cs, dir, before)
  if (!is.null(reply) && identical(res$status, "idle")) res$value = reply$value
  json = tryCatch(json_encode(plain_encode(res)), error = function(e) NULL)
  if (is.null(json) || nchar(json, "bytes") > plain_max$bytes) {
    # too large for the parent to read, or for R to encode: the value and each object travel as
    # their summaries
    shown = function(v) if (!is.null(v)) plain_summary(v)$data
    res$value = shown(res$value)
    res$objects = lapply(res$objects, shown)
    json = json_encode(plain_encode(res))
  }
  write_atomic(result_path, json)
  invisible(res$status)
}

#' The names a job's objects are bound under in its child: their labels, but a label R cannot
#' use as a symbol (`..2`, which do.call() gives a value, `...` or "") or one an earlier object
#' has gets a name of its own; child_call() passes such an object under its label
#' @noRd
child_bind = function(labels) {
  labels = labels %||% character()
  bad = grepl("^([.][.]([.]|[0-9]+))?$", labels) | duplicated(labels)
  labels[bad] = utils::tail(make.unique(c(labels, paste0("X", labels[bad]))), sum(bad))
  labels
}

#' Register the child's process-wide records (user, rank 3, before the person's records, which
#' a tie never lets win): sub-agents inline, the fence, the event hooks, and for a coach the
#' deny-every-call policy and the provider of its model; for a run the person's records
#' @noRd
child_register = function(p, cs) {
  run = identical(p$job$role, "run")
  inline = registry_get("backend", "inline")
  specs = list(
    gptr_backend("worker", start = inline$start, cancel = inline$cancel,
                 capabilities = inline$capabilities),
    gptr_policy("fence", child_fence, "a coaching run keeps to its scratch folder"),
    gptr_hook("tool_call", function(event, ctx) child_seen(cs, event)),
    gptr_hook("tool_execution_end", function(event, ctx) child_ended(cs, event)))
  if (!run) {
    specs = c(specs, list(gptr_policy("coach", function(call, ctx) {
      list(decision = "deny", reason = "a coach session runs no tool")
    })))
  }
  if (!is.null(p$provider)) specs = c(specs, list(worker_spec_revive(p$provider)))
  ids = vapply(specs, registry_add, "", source = "user", rank = 3L)
  if (run && !is.null(p$registry)) ids = c(ids, worker_registry_apply(p$registry, NULL))
  ids
}

#' The call the child evaluates: the harness (peter for a coach, a judge or an empty spec) with
#' the prompt, the object symbols and the resolved arguments; the prompt was interpolated in the
#' parent, and a coach gets no extension, no tool and the reply schema
#' @noRd
child_call = function(job, run) {
  args = job$args %||% list()
  args$model = if (inherits(job$model, "gptr_provider")) worker_spec_revive(job$model) else
    job$model
  if (!is.null(job$budget)) args$budget = job$budget
  opts = args$.opts %||% list()
  opts$interpolate = FALSE
  if (!run) {
    args[c("extensions", "plugins", "skills", "agents")] = NULL
    args$tools = c("minimal", paste0("-", registry_names("tool")))
    opts$returns = job$schema
  }
  args$.opts = opts
  fn = if (!run || is.null(job$spec$id)) peter else harness_from_spec(job$spec)
  labels = names(job$objects) %||% character()
  bind = child_bind(labels)
  objects = stats::setNames(lapply(bind, as.name), ifelse(bind == labels, "", labels))
  as.call(c(list(fn, job$prompt), objects, args))
}

#' The `fence` policy of a coaching child (08 sections 3.3 and 3.7): denies writes and edits
#' outside the child's temporary folder (which holds its scratch folder), R code whose classified
#' file targets lie outside it, that writes or deletes a path it computes or that calls a
#' function it computes, a change of working folder to anywhere but the scratch folder itself
#' (child_dirs()), installs, R child processes whose code gptr cannot read (and peter$script(),
#' whose interpreter may be R), and reads of a CLI's login file or of the macOS keychain. The
#' working folder never moves, so the targets the classifier resolves from it hold. It fences
#' only what the classifier sees.
#' @noRd
child_fence = function(call, ctx) {
  why = child_fence_why(call)
  if (!is.null(why)) list(decision = "deny", reason = paste0("the coaching run's fence: ", why))
}

#' Why the fence denies a call, or NULL
#' @noRd
child_fence_why = function(call) {
  name = call$name %||% ""
  login = "it does not read the login of Claude Code or Codex"
  stay = "it stays in its scratch folder"
  script = "it runs no script with peter$script(), which may start R with code gptr cannot read"
  if (!is.null(call$input$wd) && !child_home(call$input$wd)) return(stay)
  if (name %in% c("read", "grep", "edit") && child_login(call$input$path)) return(login)
  if (name %in% c("write", "edit")) {
    p = call$input$path
    if (rlang::is_string(p) && !child_inside(p)) return("it writes only inside its scratch folder")
    return(NULL)
  }
  if (identical(name, "script")) return(script)
  if (!identical(name, "r")) return(NULL)
  fl = call$risk$flagged
  if (!is.data.frame(fl)) return("it runs only code gptr can read")
  fl = fl[fl$level >= 1L, , drop = FALSE]
  if (child_login(fl$path) || any(grepl("find-generic-password", fl$call, fixed = TRUE))) {
    return(login)
  }
  if ("install" %in% fl$category) return("it installs nothing")
  if ("peter$script" %in% fl$fn) return(script)
  callr = c("r", "r_bg", "r_session", "r_vanilla", "rcmd", "rcmd_bg", "rscript")
  prog = "(^|[\\s/\\\\:\"'])(R|Rscript)(\\.exe)?([\\s\"']|$)"
  rproc = fl$category %in% c("process", "dynamic") &
    (fl$fn %in% callr | grepl(prog, fl$call, perl = TRUE, ignore.case = TRUE))
  if (any(rproc)) return("it starts no other R process, whose code gptr cannot read")
  if ("dynamic" %in% fl$category) return("it runs only code gptr can read")
  if (any(fl$category %in% c("file_write", "file_delete") & fl$path_class %in% "unknown")) {
    return("it writes only to paths gptr can read")
  }
  code = tryCatch(parse(text = paste(unlist(call$input$code), collapse = "\n"),
                        keep.source = FALSE), error = function(e) NULL)
  # a changer the classifier reads leaving the project or to a folder the code computes, as
  # when it is passed to lapply()
  moved = fl$fn %in% names(child_chdir) & !is.na(fl$path_class)
  if (any(moved) || !all(vapply(child_dirs(code), child_home, NA))) return(stay)
  files = as.character(unlist(call$risk$targets$files))
  # rule_call_path() writes an absolute path as "//path" (Unix) or "/C:/path" (Windows), and
  # one inside the run's folder relative to it
  files = sub("^/(/|[A-Za-z]:)", "\\1", files)
  rel = !grepl("^([/\\\\~]|[A-Za-z]:)", files)
  files[rel] = file.path(project_root(), files[rel])
  out = files[!vapply(files, child_inside, NA)]
  if (length(out)) return(paste0("it writes only inside its scratch folder, not to ", out[[1L]]))
  NULL
}

# R's directory changers, each with the argument that names the folder
child_chdir = c(setwd = "dir", with_dir = "new", local_dir = "new", in_dir = "dir")

#' The folders R code moves to, each as written or NA when computed: the folder of setwd() and of
#' withr's and xfun's directory changers called by name, NA for one named to do.call(),
#' match.fun() or get(), every `wd =` argument (peter$sh(), processx), and where each cd, pushd,
#' chdir or Set-Location in the code's strings goes. A changer passed on as a value is the
#' classifier's to read (child_fence_why()).
#' @noRd
child_dirs = function(e) {
  lit = function(x) if (rlang::is_string(x)) x else NA_character_
  if (is.character(e)) {
    return(tryCatch(unlist(lapply(e[!is.na(e)], child_cd)), error = function(err) NA_character_))
  }
  if (!is.call(e) && !is.pairlist(e) && !is.expression(e)) return(character())
  parts = as.list(e)
  out = character()
  if (is.call(e)) {
    fn = e[[1L]]
    if (is.call(fn) && (identical(fn[[1L]], quote(`::`)) || identical(fn[[1L]], quote(`:::`)))) {
      fn = fn[[3L]]
    }
    fn = if (is.symbol(fn)) as.character(fn) else ""
    arg = c(child_chdir, do.call = "what", match.fun = "FUN", get = "x")[fn]
    if (!is.na(arg)) {
      # the folder (or function) argument as R matches it: by its name, else the first unnamed one
      sig = function(...) NULL
      formals(sig) = c(stats::setNames(alist(x = ), arg), alist(... = ))
      v = tryCatch(as.list(match.call(sig, e))[[arg]], error = function(err) NULL)
      if (fn %in% names(child_chdir)) {
        out = lit(v)
        parts = parts[-1L]
      } else if ((is.symbol(v) || rlang::is_string(v)) && as.character(v) %in% names(child_chdir)) {
        out = NA_character_
      }
    }
    if ("wd" %in% names(parts)) out = c(out, lit(parts[["wd"]]))
  }
  c(out, unlist(lapply(parts, child_dirs)))
}

#' Where the cd, pushd, chdir or Set-Location commands of a text go ("~" without a folder). Each
#' piece between shell separators or quotes is read as a command after leading keywords, wrappers
#' and assignments, so a cd inside `sh -c '...'` counts too; cd, pushd and chdir fold case only on
#' Windows, whose shells do, and PowerShell's Set-Location everywhere
#' @noRd
child_cd = function(cmd) {
  out = character()
  lead = "^((then|do|else|!|builtin|command|exec|env|sudo|nohup|time|[A-Za-z_]\\w*=\\S*)\\s+)*"
  for (s in sub(lead, "", trimws(strsplit(cmd, "[;&|\n(){}`'\"]")[[1L]]), perl = TRUE)) {
    w = strsplit(s, "\\s+")[[1L]]
    if (length(w) && ((if (is_windows()) tolower(w[[1L]]) else w[[1L]]) %in%
                        c("cd", "pushd", "chdir") || tolower(w[[1L]]) == "set-location")) {
      to = w[-1L][!grepl("^-.", w[-1L])][1L]
      out = c(out, if (is.na(to)) "~" else to)
    }
  }
  out
}

#' Is a folder the run's own folder (the project root), written as an absolute path?
#' @noRd
child_home = function(path) {
  rlang::is_string(path) && is_abs_path(path) &&
    isTRUE(tryCatch(path_key(path) == path_key(project_root()), error = function(e) FALSE))
}

#' Is a path inside this process's temporary folder?
#' @noRd
child_inside = function(path) {
  isTRUE(tryCatch(path_inside(path_norm(path), path_norm(tempdir())), error = function(e) FALSE))
}

#' Does a path name a CLI login file (.credentials.json in CLAUDE_CONFIG_DIR, auth.json in
#' CODEX_HOME; by default ~/.claude and ~/.codex) or a folder that holds one?
#' @noRd
child_login = function(paths) {
  dirs = Sys.getenv(c("CLAUDE_CONFIG_DIR", "CODEX_HOME"))
  login = file.path(ifelse(nzchar(dirs), dirs, c("~/.claude", "~/.codex")),
                    c(".credentials.json", "auth.json"))
  paths = as.character(unlist(paths))
  any(vapply(paths[!is.na(paths) & nzchar(paths)], function(p) {
    isTRUE(tryCatch(any(path_inside(login, p)), error = function(e) FALSE))
  }, NA))
}

#' Write one event line for the parent (a broken pipe is left to the parent watch)
#' @noRd
child_emit = function(cs, obj) {
  line = as_utf8(json_encode(obj))
  tryCatch(if (inherits(cs$out, "processx_connection")) {
    processx::conn_write(cs$out, charToRaw(paste0(line, "\n")))
  } else {
    writeLines(line, cs$out, useBytes = TRUE)
    flush(cs$out)
  }, error = function(e) NULL)
  invisible(NULL)
}

#' The `tool_call` hook: remember the call's risk level by its id
#' @noRd
child_seen = function(cs, event) {
  lv = suppressWarnings(as.integer(event$risk$level))
  if (length(lv) == 1L && !is.na(lv)) assign(event$tool_call_id, lv, envir = cs$levels)
  NULL
}

#' The `tool_execution_end` hook: a call that ran streams its risk level, a refused one its
#' refusal. A call that met a require rule of its harness is left out of the risk unless it is of
#' level 3 or above, which no require pattern names (coaching_pattern())
#' @noRd
child_ended = function(cs, event) {
  cs$calls = cs$calls + 1L
  id = as.character(event$tool_call_id)
  if (is.null(event$refused)) {
    lv = get0(id, envir = cs$levels, inherits = FALSE)
    if (!is.null(lv) && (lv >= 3L || !child_met(event))) {
      cs$risk = max(cs$risk, lv)
      child_emit(cs, list(gptr_coach = "risk", level = lv))
    }
  } else {
    row = data.frame(id = id, tool = as.character(event$tool_name),
                     reason = as.character(event$refused))
    cs$refusals = rbind(cs$refusals, row)
    child_emit(cs, c(list(gptr_coach = "refusal"), as.list(row)))
  }
  NULL
}

#' Did a call meet a require rule? The finish hook adds the call's id to its run's `require_met`
#' (harness_finish_hooks())
#' @noRd
child_met = function(event) {
  s = session_by_id(event$session)
  run = if (!is.null(s)) session_live(s)$run
  isTRUE(as.character(event$tool_call_id) %in% run$require_met)
}

#' The result of a finished job (08 section 3.3); a coach's reply is discarded when its session
#' froze a tool or used one
#' @noRd
child_outcome = function(job, out, env, objects, cs, dir, before) {
  s = if (inherits(out, "gptr_session")) out else if (inherits(out, "condition")) out$session
  err = if (inherits(out, "condition")) out
  d = if (inherits(s, "gptr_session")) session_data(s)
  first = if (!is.null(d)) Find(function(m) identical(m$role, "user"), s$messages)
  unmet = unique(as.character(unlist(lapply(d$entries, function(e) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.unmet")) e$data$ids
  }))))
  for (id in unmet) child_emit(cs, list(gptr_coach = "unmet", id = id))
  limit = if (inherits(err, "gptr_error_plan_limit")) {
    list(resets_at = c(as.character(err$resets_at), NA_character_)[[1L]])
  }
  if (!is.null(limit)) child_emit(cs, c(list(gptr_coach = "limit"), limit))
  res = child_result_new(job$id, status = d$status %||% "error", reason = d$reason,
    text = if (is.null(d) || is.na(d$last_text)) "" else d$last_text, turns = d$turns %||% 0L,
    usage = if (!is.null(d)) session_usage_rows(s),
    value = if (!is.null(d)) tryCatch(session_value_get(s), error = function(e) NULL),
    objects = child_objects(env, objects),
    transcript = if (is.null(d)) "" else child_clip(child_transcript(s$messages), 50000L),
    first_user = if (is.null(first)) "" else child_clip(child_text(first), 50000L),
    risk = cs$risk, refusals = cs$refusals, unmet = unmet, files = child_files(dir, before),
    plan = pcli_cache$plan, limit = limit,
    checks = if (inherits(err, "gptr_error_cli_check")) conditionMessage(err) else character(),
    error = if (!is.null(err)) conditionMessage(err))
  if (!identical(job$role, "run") && (length(d$frozen$tool_names) || cs$calls > 0L)) {
    res[c("status", "text", "value", "error")] = list("error", "", NULL,
                                                      "the coach session had or used a tool")
  }
  res
}

#' The objects a run created or changed in its environment; a promise or an active binding is
#' never forced
#' @noRd
child_objects = function(env, given) {
  nms = ls(env, sorted = TRUE)
  lazy = rlang::env_binding_are_lazy(env, nms) | rlang::env_binding_are_active(env, nms)
  out = list()
  for (k in seq_along(nms)) {
    nm = nms[[k]]
    if (lazy[[k]]) {
      out[[nm]] = "<an unevaluated promise or active binding>"
    } else if (!nm %in% names(given) || !identical(env[[nm]], given[[nm]])) {
      out[nm] = list(env[[nm]])
    }
  }
  out
}

#' The files a run wrote or changed in its scratch folder (at most 100), with their text
#' clipped; binary files have no text. A read that stops inside a character leaves its last
#' bytes out.
#' @noRd
child_files = function(dir, before) {
  now = list.files(dir, recursive = TRUE, all.files = TRUE, full.names = TRUE)
  sums = tools::md5sum(now)
  now = utils::head(now[is.na(before[now]) | before[now] != sums], 100L)
  text = vapply(now, function(f) {
    b = readBin(f, "raw", n = 200000L)
    if (any(b == 0)) return(NA_character_)
    cut = Find(function(k) validUTF8(rawToChar(utils::head(b, length(b) - k))),
               if (file.size(f) > length(b)) 0:3 else 0L)
    if (is.null(cut)) NA_character_ else
      child_clip(as_utf8(rawToChar(utils::head(b, length(b) - cut))), 50000L)
  }, "", USE.NAMES = FALSE)
  data.frame(path = substring(now, nchar(dir) + 2L), bytes = file.size(now), text = text)
}

#' A conversation as text: each message under its role
#' @noRd
child_transcript = function(msgs) {
  parts = vapply(msgs, function(m) {
    who = if (identical(m$role, "tool_result")) paste0("tool result (", m$tool_name, ")") else
      m$role
    paste0("## ", who, "\n", child_text(m))
  }, "")
  paste(parts, collapse = "\n\n")
}

#' One message as text: its text, images as [image], tool calls with their arguments
#' @noRd
child_text = function(m) {
  body = vapply(m$content %||% list(), function(b) {
    switch(b$type %||% "", text = , context = b$text %||% "", image = "[image]",
           tool_call = paste0("[tool call ", b$name, "] ",
                              json_encode(b$arguments %||% json_obj())), "")
  }, "")
  paste(body[nzchar(body)], collapse = "\n")
}

#' Clip a text to `n` characters, saying how much was left out
#' @noRd
child_clip = function(x, n) {
  x = iconv(x, "UTF-8", "UTF-8", sub = "?")
  k = nchar(x)
  if (k <= n) return(x)
  paste0(substr(x, 1L, n), "\n[... clipped: ", k - n, " more characters]")
}
