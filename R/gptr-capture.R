# gptr-capture.R -- copy-safe base-R capture of gptr() calls (rules R2-R3; G3 section 3 "GATEWAY
# CAPTURE RULES", verified by G3 t2b and t5 and its fact-check; IC-41), {identifier}
# interpolation (contract 6.1.4), prompt selection, argument validation and the gptr_call record
# (7.8, IC-13). Identifier resolution (6.1.3, IC-42) joins in Task 6. Plan P08, layer L6.
#
# Every helper that touches a user value is a leaf: it forces its arguments on entry, creates no
# closure, handler or match.arg() while it holds the value, and returns primitives only.

# ------------------------------------------------------------------ dot facts (leaves)

#' Facts about one dot value [leaf] (contract 7.8; G3 `.leaf_dot`)
#' @noRd
dot_facts = function(x) {
  chr = is.character(x)
  n = length(x)
  list(class = class(x),
       is_session = inherits(x, "gptr_session"),
       is_chr1 = chr && n == 1L && !is.na(x) && (!is.object(x) || inherits(x, c("glue", "AsIs"))),
       length = n,
       dim = dim(x),
       bytes = as.numeric(utils::object.size(x)),
       text = if (chr && n <= 65536L && sum(nchar(x, type = "bytes"), na.rm = TRUE) <= 65536L) {
         as_utf8(paste0(x))
       } else {
         NULL
       })
}

#' The value bound to a call-site symbol, read by name [leaf]; an argument error naming the
#' symbol when it is unbound
#' @noRd
dot_get = function(name, envir) {
  if (!exists(name, envir = envir, inherits = TRUE)) {
    gptr_abort(paste0("object '", name, "' not found"), "invalid_argument", arg = name,
               expected = "an object that exists")
  }
  get0(name, envir = envir, inherits = TRUE)
}

#' Address of the object bound to `name` as seen from `envir`, or NA [leaf]
#' @noRd
binding_address = function(name, envir) {
  if (!exists(name, envir = envir, inherits = TRUE)) return(NA_character_)
  obj_address_leaf(get0(name, envir = envir, inherits = TRUE))
}

#' rlang::obj_address() of a forced value [leaf]
#' @noRd
obj_address_leaf = function(x) rlang::obj_address(x)

#' TRUE for a length-1 constant written at the call site (a literal)
#' @noRd
dot_is_literal = function(e) {
  (is.character(e) || is.numeric(e) || is.logical(e) || is.complex(e)) && length(e) == 1L &&
    is.null(attributes(e))
}

#' Names of gptr()'s formals after the dots (contract 6.1; Task 8's test-gptr-gateway.R checks that
#' they equal `setdiff(names(formals(gptr)), "...")`)
#' @noRd
gateway_formal_names = function() {
  c("model", "mode", "skills", "plugins", "extensions", "tools", "agents", "parallel", "choices",
    "levels", "threshold", "min_confidence", "uncertain", "prompt", "envir", "background", "budget",
    "replay", ".opts", ".run", ".stdin")
}

#' For each dot, the symbol written at the call site when the dot is a plain symbol there, else NA.
#' Forwarded dots (`...`, `..1`) are NA: they are forced through ...elt(), never read by name,
#' because the caller frame is not where their promises evaluate (IC-41). Arguments named after a
#' formal of gptr() are not dots; with more than one forwarded `...` every dot is NA. An empty
#' argument (`gptr("x", )`) is a dot without a symbol. Each argument is read by index, never bound
#' to a local, so an empty argument is never evaluated.
#' @noRd
dot_sites = function(sc, n) {
  sites = rep(NA_character_, n)
  if (!n) return(sites)
  args = as.list(sc)[-1L]
  nm = names(args)
  if (is.null(nm)) nm = rep("", length(args))
  nm[is.na(nm)] = ""
  keep = which(!(nzchar(nm) & nm %in% gateway_formal_names()))
  syms = character(length(keep))
  fwd = logical(length(keep))
  k = 1L
  while (k <= length(keep)) {
    j = keep[k]
    s = if (is.symbol(args[[j]])) as.character(args[[j]]) else ""
    fwd[k] = identical(s, "...") || grepl("^[.][.][0-9]+\\z", s, perl = TRUE)
    syms[k] = if (fwd[k]) "" else s
    k = k + 1L
  }
  if (sum(fwd) > 1L) return(sites)
  width = n - sum(!fwd)
  pos = 1L
  k = 1L
  while (k <= length(syms) && pos <= n) {
    if (fwd[k]) {
      pos = pos + max(width, 0L)
    } else {
      if (nzchar(syms[k])) sites[pos] = syms[k]
      pos = pos + 1L
    }
    k = k + 1L
  }
  sites
}

#' Context labels: the argument name, else the symbol, else the deparsed expression (60 chars);
#' values spliced in by do.call() and empty arguments (`gptr("x", , big)`) are labelled `..i`.
#' Like dot_sites(), each expression is read by index, never bound to a local, so an empty
#' argument is never evaluated
#' @noRd
dot_labels = function(exprs, nms) {
  if (!length(exprs)) return(character())
  out = character(length(exprs))
  i = 1L
  while (i <= length(exprs)) {
    sym = is.symbol(exprs[[i]])
    out[i] = if (nzchar(nms[i])) {
      nms[i]
    } else if (sym && nzchar(as.character(exprs[[i]]))) {
      as.character(exprs[[i]])
    } else if (!sym && (is.language(exprs[[i]]) || dot_is_literal(exprs[[i]]))) {
      d = paste(deparse(exprs[[i]], width.cutoff = 60L, nlines = 1L), collapse = "")
      if (nchar(d) > 60L) paste0(substr(d, 1L, 57L), "...") else d
    } else {
      paste0("..", i)
    }
    i = i + 1L
  }
  as_utf8(out)
}

#' Chooses the continuation target, the prompt and the context dots from facts only (contract
#' 6.1.1 step 2; report 12 section 2.D3)
#' @noRd
select_prompt = function(nms, facts, kinds, have_prompt) {
  n = length(facts)
  named = nzchar(nms)
  is_s = vapply(facts, function(f) isTRUE(f$is_session), NA)
  chr1 = vapply(facts, function(f) isTRUE(f$is_chr1), NA)
  target = if (n >= 1L && !named[1L] && is_s[1L]) 1L else NA_integer_
  cand = setdiff(which(!named), target)
  lits = cand[kinds[cand] == "literal" & chr1[cand]]
  vals = cand[kinds[cand] != "literal" & chr1[cand] & !is_s[cand]]
  prompt = if (have_prompt) {
    NA_integer_
  } else if (length(lits)) {
    lits[1L]
  } else if (length(vals)) {
    vals[1L]
  } else {
    NA_integer_
  }
  context = setdiff(seq_len(n), c(target, prompt))
  list(target = target, prompt = prompt,
       literal = !is.na(prompt) && identical(kinds[prompt], "literal"),
       context = context, two = !have_prompt && length(lits) >= 2L)
}

#' Context items of the call record (contract 7.8): label, kind, name (symbols), slot (values and
#' literals in `values`), address (symbols; IC-40 visibility check) and facts. (Named apart from
#' P07's context_items() in R/prompt-context.R.)
#' @noRd
gateway_context_items = function(idx, kinds, sites, labels, facts, addrs) {
  out = vector("list", length(idx))
  for (k in seq_along(idx)) {
    j = idx[k]
    f = facts[[j]]
    sym = identical(kinds[j], "symbol")
    out[[k]] = list(label = labels[j], kind = kinds[j],
                    name = if (sym) sites[j] else NULL,
                    slot = if (sym) NULL else paste0(".v", j),
                    address = if (sym) addrs[j] else NULL,
                    facts = list(class = f$class, dim = f$dim, length = f$length, bytes = f$bytes,
                                 is_chr1 = f$is_chr1))
  }
  out
}

#' Replaces a magrittr mask (an environment whose only binding is `.`) by its parent
#' (report 12 section 2.B4). Uses the primitive names(): ls(<env>) runs tryCatch() internally, and
#' its garbage handler would keep a user frame referenced (rule R3; verified with tracemem).
#' @noRd
unmask_env = function(env) {
  if (!identical(env, globalenv()) && identical(names(env), ".")) return(parent.env(env))
  env
}

# ------------------------------------------------------------------ fixed vocabularies

#' `name_norm(x)`: lower case with `_` and `.` mapped to `-` (IC-42)
#' @noRd
name_norm = function(x) tolower(gsub("[._]", "-", x))

#' The permission modes, known before their plans register anything
#' @noRd
gateway_modes = function() c("plan", "manual", "edits", "auto")

#' The built-in preset names (P07 registers them as `preset` records)
#' @noRd
gateway_presets = function() c("minimal", "standard", "readonly", "extended")

#' The built-in tool names (P10 and P11 register them as `tool` records)
#' @noRd
gateway_builtin_tools = function() c("read", "edit", "write", "grep", "find", "ls", "r", "ask")

# ------------------------------------------------------------------ interpolation (6.1.4; IC-45)

#' Formats one interpolated value: an atomic vector of 1-50 elements, joined with ", ", cut at
#' 1,000 characters; anything else is not interpolated (NULL) [leaf]
#' @noRd
interp_format = function(x) {
  if (is.null(x) || !is.atomic(x) || length(x) < 1L || length(x) > 50L) return(NULL)
  v = as_utf8(paste(format(x, trim = TRUE, justify = "none"), collapse = ", "))
  if (nchar(v) > 1000L) v = substr(v, 1L, 1000L)
  v
}

#' The interpolated text of `{name}`, or NULL when `name` is unbound or not a short atomic vector
#' @noRd
interp_value = function(name, envir) {
  interp_format(get0(name, envir = envir, inherits = TRUE))
}

#' `{identifier}` interpolation of a literal prompt (contract 6.1.4). `{{` and `}}` are literal
#' braces; values are never re-interpolated. Returns list(prompt, interp) where interp holds the
#' sorted `name=value` pairs used (hashed into the block header's `args=` key by P15). `envir` may
#' be a user frame: the loop is a `while` loop, because a `for` loop that calls a closure with a
#' local bound to a frame keeps that frame referenced (G3 cause 2, re-verified for P08).
#' @noRd
interpolate_prompt = function(template, envir) {
  check_string(template, "template", empty = TRUE)
  check_env(envir, "envir")
  hits = gregexpr("\\{\\{|\\}\\}|\\{[.A-Za-z][.A-Za-z0-9_]*\\}", template, perl = TRUE)[[1L]]
  if (hits[1L] == -1L) return(list(prompt = template, interp = character()))
  starts = as.integer(hits)
  lens = attr(hits, "match.length")
  out = character()
  pairs = character()
  pos = 1L
  k = 1L
  while (k <= length(starts)) {
    s = starts[k]
    e = s + lens[k] - 1L
    out = c(out, substr(template, pos, s - 1L))
    tok = substr(template, s, e)
    if (identical(tok, "{{")) {
      out = c(out, "{")
    } else if (identical(tok, "}}")) {
      out = c(out, "}")
    } else {
      nm = substr(tok, 2L, nchar(tok) - 1L)
      v = interp_value(nm, envir)
      if (is.null(v)) {
        out = c(out, tok)
      } else {
        out = c(out, v)
        pairs = c(pairs, paste0(nm, "=", v))
      }
    }
    pos = e + 1L
    k = k + 1L
  }
  out = c(out, substr(template, pos, nchar(template)))
  list(prompt = as_utf8(paste(out, collapse = "")),
       interp = sort(unique(pairs), method = "radix"))
}

#' TRUE unless `.opts$interpolate = FALSE` or `options(gptr.interpolate = FALSE)`
#' @noRd
gateway_interpolate = function(opts) {
  if (isFALSE(opts$interpolate)) return(FALSE)
  !isFALSE(gptr_opt("interpolate"))
}

# ------------------------------------------------------------------ argument validation (6.1)

#' The `.opts` names of contract 6.1, plus `system1_images` (IC-74, 07-local-ollama.md section 4)
#' @noRd
gateway_opts_names = function() {
  c("thinking", "max_turns", "context", "record", "interpolate", "timeout", "output", "system",
    "preset", "returns", "max_active", "backend", "frontend", "images", "seed", "system1_images")
}

#' One string out of `choices`. check_choice() alone would take the whole vector of choices as
#' its first element (the missing-argument convention of match.arg()), which a value given to
#' gptr() must never be
#' @noRd
gateway_choice = function(x, choices, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    expected = if (length(choices)) {
      paste0("one of ", paste0("\"", choices, "\"", collapse = ", "))
    } else {
      "a registered name (none is registered)"
    }
    arg_abort(x, arg, expected)
  }
  x
}

#' TRUE for a name `.opts` never takes as a plugin namespace, whatever is registered under it
#' (IC-74, 07-local-ollama.md sections 2.1 and 5: per-call options cannot relax `local_only`): the
#' protected settings (settings_protected(): `providers`, which holds the local-only control, and
#' `egress`), and `safety`, the run's frozen safety record (run_new()'s `run$opts$safety`, IC-53),
#' which P05's stream_safety() and P13's s1_request() read as `opts$safety`
#' @noRd
gateway_opts_reserved = function(k) settings_protected(k) || identical(k, "safety")

#' Validates `.opts`: the core switches, and entries named by a plugin namespace, validated by
#' that plugin's `setting` specs `<namespace>.<field>` (IC-44). A reserved name
#' (gateway_opts_reserved()) is never a namespace of call options: only a human's user or session
#' configuration and options may relax what it holds
#' @noRd
gateway_opts = function(opts) {
  if (is.null(opts) || (is.list(opts) && !length(opts))) return(list())
  check_list(opts, ".opts", named = TRUE)
  out = opts
  settings = registry_names("setting")
  for (k in names(opts)) {
    v = opts[[k]]
    if (k %in% gateway_opts_names()) {
      out[k] = list(gateway_opt_check(k, v))
      next
    }
    if (gateway_opts_reserved(k)) {
      hint = if (settings_protected(k)) {
        paste0("Set `", k, "` with gptr_config(", k, " = ..., .scope = \"user\").")
      } else {
        "A run's safety record is taken from your options and user configuration when it starts."
      }
      gptr_abort(c(paste0("`.opts$", k, "` cannot be set per call."), hint),
                 "invalid_argument", arg = ".opts",
                 expected = "options other than providers, egress and safety")
    }
    fields = settings[startsWith(settings, paste0(k, "."))]
    if (!length(fields)) {
      gptr_abort(paste0("`.opts$", k, "` is not a known option or plugin namespace."),
                 "invalid_argument", arg = ".opts",
                 expected = paste(gateway_opts_names(), collapse = ", "))
    }
    check_list(v, paste0(".opts$", k), named = TRUE)
    for (f in names(v)) {
      key = paste0(k, ".", f)
      if (!key %in% fields) {
        gptr_abort(paste0("`.opts$", k, "$", f, "` is not a setting of the `", k, "` plugin."),
                   "invalid_argument", arg = ".opts", expected = paste(fields, collapse = ", "))
      }
      spec = registry_get("setting", key)
      if (!is.null(v[[f]]) && is.function(spec$validate)) v[f] = list(spec$validate(v[[f]]))
    }
    out[k] = list(v)
  }
  out
}

#' Validates one core `.opts` entry
#' @noRd
gateway_opt_check = function(k, v) {
  arg = paste0(".opts$", k)
  switch(k,
    thinking = gateway_choice(v, catalog_thinking_levels, arg),
    max_turns = as.integer(check_number(v, arg, min = 1, int = TRUE)),
    context = gateway_choice(v, c("summary", "names", "none"), arg),
    record = check_flag(v, arg),
    interpolate = check_flag(v, arg),
    timeout = check_number(v, arg, min = 0),
    output = gateway_choice(v, "factor", arg),
    system = {
      if (is.character(v)) check_string(v, arg) else check_list(v, arg, named = TRUE)
      v
    },
    preset = gateway_choice(v, unique(c(gateway_presets(), registry_names("preset"))), arg),
    returns = {
      check_list(v, arg, named = TRUE)
      bad = schema_problems(v)
      if (length(bad)) {
        gptr_abort(c("`.opts$returns` is not a valid JSON Schema:", bad), "invalid_argument",
                   arg = arg, expected = "a JSON Schema list")
      }
      v
    },
    max_active = as.integer(check_number(v, arg, min = 1, int = TRUE)),
    backend = gateway_choice(v, unique(c("auto", registry_names("backend"))), arg),
    frontend = gateway_choice(v, registry_names("frontend"), arg),
    images = gateway_images_check(v),
    seed = as.integer(check_number(v, arg, int = TRUE)),
    system1_images = gateway_s1_images_check(v),
    v)
}

#' `.opts$images`: image file paths (a character vector or a list), ggplot or recordedplot objects
#' (IC-44). The MIME type of a path is Task 9's (gateway_image_blocks()); a directory is no image
#' @noRd
gateway_images_check = function(v) {
  items = if (is.character(v)) {
    as.list(v)
  } else if (inherits(v, c("ggplot", "recordedplot"))) {
    list(v)
  } else {
    v
  }
  if (!is.list(items) || is.object(items)) {
    gptr_abort("`.opts$images` takes image paths, ggplot objects or recorded plots.",
               "invalid_argument", arg = ".opts$images", expected = "a list of images")
  }
  for (x in items) {
    ok = (is.character(x) && length(x) == 1L && !is.na(x) && file.exists(x) && !dir.exists(x)) ||
      inherits(x, c("ggplot", "recordedplot"))
    if (!ok) {
      gptr_abort("Each image must be an existing PNG/JPEG path, a ggplot or a recordedplot.",
                 "invalid_argument", arg = ".opts$images", expected = "image paths or plots")
    }
  }
  items
}

#' The MIME types of System 1 image records (07-local-ollama.md section 4)
#' @noRd
gateway_s1_mimes = function() c("image/png", "image/jpeg", "image/webp")

#' `.opts$system1_images` (IC-74, 07-local-ollama.md section 4): a list of image records
#' `list(data = <raw bytes>, mime = "image/png" | "image/jpeg" | "image/webp")`, applied to every
#' state of the call. P08 checks the shape only: each record is a plain list with exactly the
#' fields `data` (non-empty raw) and `mime`; a path, a file name or text never stands in for the
#' bytes. A single record is taken as a list of one; names of the list are dropped (its order is
#' the order the images are sent and hashed in). The resolved model and the adapter limits are
#' P13's checks
#' @noRd
gateway_s1_images_check = function(v) {
  expected = paste0("a list of image records list(data = <raw bytes>, mime = ",
                    paste0("\"", gateway_s1_mimes(), "\"", collapse = " | "), ")")
  if (is.list(v) && !is.object(v) && is.raw(v[["data"]])) v = list(v)
  if (!is.list(v) || is.object(v)) arg_abort(v, ".opts$system1_images", expected)
  for (im in v) {
    nms = names(im)
    ok = is.list(im) && !is.object(im) && length(im) == 2L && !is.null(nms) &&
      setequal(nms, c("data", "mime")) && is.raw(im[["data"]]) && length(im[["data"]]) > 0L &&
      is.character(im[["mime"]]) && length(im[["mime"]]) == 1L && !is.na(im[["mime"]]) &&
      im[["mime"]] %in% gateway_s1_mimes()
    if (!ok) arg_abort(im, ".opts$system1_images", expected)
  }
  unname(v)
}

#' Labels of a `choices` value: a factor's levels; a character vector named in full gives its
#' names (descriptions as values, which may repeat, be empty or NA), otherwise its values. The
#' same reading as P13's choice question; P13 also refuses logical-looking labels
#' (`gptr_error_s1_labels`) and applies the model's option limits
#' @noRd
gateway_choice_labels = function(choices) {
  if (is.factor(choices)) return(levels(choices))
  if (!is.character(choices)) {
    arg_abort(choices, "choices", "a character vector or a factor")
  }
  nm = names(choices)
  if (!is.null(nm) && !anyNA(nm) && all(nzchar(nm))) return(nm)
  check_strings(choices, "choices")
  unname(choices)
}

#' Validates the value arguments of gptr(); forces each on entry [leaf]
#' @noRd
gateway_args = function(parallel, choices, lvls, threshold, min_confidence, uncertain, background,
                        budget, replay, opts, run, stdin) {
  force(parallel)
  force(choices)
  force(lvls)
  force(threshold)
  force(min_confidence)
  force(uncertain)
  force(background)
  force(budget)
  force(replay)
  force(opts)
  force(run)
  force(stdin)
  par_n = NULL
  if (!is.null(parallel)) {
    par_n = as.integer(check_number(parallel, "parallel", min = 1, int = TRUE))
  }
  if (!is.null(choices)) {
    labs = gateway_choice_labels(choices)
    if (length(labs) < 2L || anyNA(labs) || !all(nzchar(labs)) || anyDuplicated(labs)) {
      gptr_abort("`choices` needs at least two unique, non-empty labels.", "invalid_argument",
                 arg = "choices", expected = "two or more unique labels")
    }
  }
  if (!is.null(lvls)) {
    check_strings(lvls, "levels")
    if (length(lvls) < 2L) {
      gptr_abort("`levels` needs at least two level descriptions.", "invalid_argument",
                 arg = "levels", expected = "two or more levels")
    }
  }
  check_number(threshold, "threshold", min = 0, max = 1)
  if (threshold <= 0 || threshold >= 1) {
    gptr_abort("`threshold` must lie strictly between 0 and 1.", "invalid_argument",
               arg = "threshold", expected = "a number in (0, 1)")
  }
  check_number(min_confidence, "min_confidence", min = 0, max = 1, null = TRUE)
  ok_unc = is.null(uncertain) || is.function(uncertain) || identical(uncertain, "stop") ||
    (is.logical(uncertain) && length(uncertain) == 1L)
  if (!ok_unc) {
    gptr_abort("`uncertain` takes NA, TRUE, FALSE, \"stop\" or function(state, answer).",
               "invalid_argument", arg = "uncertain",
               expected = "NA, TRUE, FALSE, \"stop\" or a function")
  }
  check_flag(background, "background")
  check_flag(run, ".run")
  check_flag(stdin, ".stdin")
  if (!is.null(budget)) {
    check_list(budget, "budget", named = TRUE)
    bad = setdiff(names(budget), c("tokens", "cost", "turns"))
    if (length(bad)) {
      gptr_abort(paste0("Unknown budget field: ", paste(bad, collapse = ", "), "."),
                 "invalid_argument", arg = "budget", expected = "tokens, cost and turns")
    }
    for (k in names(budget)) check_number(budget[[k]], paste0("budget$", k), min = 0, null = TRUE)
  }
  rep_mode = if (is.null(replay)) NULL else gateway_choice(replay, replay_modes(), "replay")
  list(parallel = par_n, choices = choices, levels = lvls, threshold = threshold,
       min_confidence = min_confidence, uncertain = uncertain, background = background,
       budget = budget, replay = rep_mode, opts = gateway_opts(opts), run = run, stdin = stdin)
}

# ------------------------------------------------------------------ the gptr_call record (7.8)

#' Builds the gptr_call record (IC-13): an environment with the bindings of contract 7.8, plus
#' `interp` (the sorted `name=value` pairs of 6.1.4) and `hold` (TRUE while a started run still
#' needs the record after gptr() returned)
#' @noRd
call_new = function(prompt = NULL, template = NULL, interp = character(), session = NULL,
                    context = list(), values = NULL, envir = NULL, ids = list(), args = list(),
                    sys_call = NULL, nframe = NA_integer_) {
  call = new.env(parent = emptyenv())
  call$id = id_new("c", 8L)
  call$prompt = prompt
  call$template = template %||% prompt
  call$interp = interp
  call$session = session
  call$context = context
  call$values = values %||% new.env(parent = emptyenv())
  call$envir = envir
  call$ids = ids
  call$args = args
  call$sys_call = sys_call
  call$nframe = nframe
  call$top_level = NA
  call$doc = NULL
  call$hold = FALSE
  class(call) = "gptr_call"
  call
}

#' Releases a call record [R2]: rm() of its values, `envir` and `sys_call` set to NULL. Called on
#' every exit path of gptr(). A record whose `hold` flag is set (its run was started for later
#' pumping) is left alone; the listeners of call_hold() (Task 9) clear the flag and release it.
#' @noRd
call_release = function(call) {
  if (!inherits(call, "gptr_call")) return(invisible(FALSE))
  if (isTRUE(call$hold)) return(invisible(FALSE))
  v = call$values
  if (is.environment(v)) rm(list = names(v), envir = v)
  call$envir = NULL
  call$sys_call = NULL
  invisible(TRUE)
}

#' The value of context item `i` [leaf]: symbols by name from `envir`, others from `values`.
#' After call_release() neither is readable: `gptr_error_internal` (a value bound to NULL is
#' still a value before then)
#' @noRd
call_value = function(call, i) {
  check_class(call, "gptr_call", "call")
  i = check_number(i, "i", min = 1, max = length(call$context), int = TRUE)
  it = call$context[[i]]
  if (identical(it$kind, "symbol")) {
    env = call$envir
    if (!is.environment(env)) {
      gptr_abort("The gateway call was already released; its context cannot be read.",
                 "internal", detail = "call_value() after call_release()")
    }
    return(get0(it$name, envir = env, inherits = TRUE))
  }
  v = call$values
  if (!is.environment(v) || !exists(it$slot, envir = v, inherits = FALSE)) {
    gptr_abort("The gateway call was already released; its context cannot be read.",
               "internal", detail = "call_value() after call_release()")
  }
  get0(it$slot, envir = v, inherits = FALSE)
}
