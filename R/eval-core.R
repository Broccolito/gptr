# eval-core.R -- the hand-rolled evaluator eval_r() and the RNG swap rng_swap() (P09).
#
# Adapted from report 12 section 5.1 (gptr_eval2.R: anonymous-file sink, calling handlers,
# per-expression time limits, trimmed tracebacks, plot hooks, harness options) with the fixes of
# its verification log (items 3, 4, 9, 10, 25), the contract's amendments (04 section 7.9;
# IC-61, IC-67) and the G3 fact-check fix for function-frame homes. Frame layout, verified with
# fresh-process tracemem runs (test-copy-eval.R):
#   eval_r()        binds `envir`; creates no closure, no tryCatch() and no loop; stores `envir`
#                   in the state environment `st` and resets st$envir to NULL on exit (R2).
#   eval_run(), eval_loop(), eval_loop_catch(), eval_one()
#                   hold only `st`; eval_one() creates the calling handlers and the restart.
#                   Every helper forces its arguments on entry (R3).
#   eval_top(), eval_frame()
#                   closure-free leaves that reach `envir` through st$envir; every withVisible()
#                   result is cleared in place with res[1L] = list(NULL) (R8, IC-67).
# The value of an evaluation is never kept. Known limit (R itself, not gptr): an error unwinds
# the frames between the failing call and the restart without releasing what they reference, so
# an object the failing code passed through a function (or a home frame the failing code forced)
# copies once on its next in-place edit, exactly as after try() in user code.

#' L'Ecuyer-CMRG seed vector from a key (IC-61)
#'
#' 24 bytes of sha256(key): three 32-bit words reduced modulo m1 = 4294967087 and three modulo
#' m2 = 4294944443, stored as R integers (two's complement) after the kind code 10407L. Uses no
#' random number generator. The word 2^31 has no R integer other than NA_integer_ (its
#' two's-complement bit pattern), so it is stored as NA without a coercion warning; R reads
#' that NA back as the word 2^31.
#' @noRd
rng_seeds = function(key) {
  h = hash_sha256(as.character(key)[[1L]])
  hex = substring(h, seq(1L, 41L, by = 8L), seq(8L, 48L, by = 8L))
  v = as.numeric(paste0("0x", hex))
  v = v %% c(rep(4294967087, 3L), rep(4294944443, 3L))
  if (all(v[1:3] == 0)) v[1L] = 1
  if (all(v[4:6] == 0)) v[4L] = 1
  v = ifelse(v > 2147483647, v - 4294967296, v)
  v[v == -2147483648] = NA
  c(10407L, as.integer(v))
}

#' Evaluate `expr` with an agent's L'Ecuyer stream in .Random.seed (a leaf)
#'
#' Saves the user's `.Random.seed` of the global environment (or its absence), assigns
#' `state$seed` (derived with rng_seeds(state$id) when unset: `id` is the agent id, or
#' `"<.opts$seed>:<agent label>"` for reproducible streams, IC-61), evaluates, keeps the
#' advanced vector in `state$seed` and restores or removes the user's value. With
#' with_seed_preserved() the only code that assigns .Random.seed. R also keeps its generator
#' kind internally, and set.seed() keeps the kind in force: removing the variable alone would
#' leave L'Ecuyer-CMRG in force, so the user's next `set.seed(42)` would draw other numbers.
#' When the user had no seed, the kind code is therefore read before the swap and put back
#' after it: `stats::rbinom(1L, 0L, 0.5)` makes R load (or initialise) and store its state
#' without drawing a number (size 0 returns 0), and the variable it stores is removed again.
#' When the user had a seed, restoring the vector alone leaves the agent's kind in force
#' internally until R next reads the variable, so a user who then removed `.Random.seed` would
#' get L'Ecuyer-CMRG from `set.seed()`. The same call makes R read the kind from the restored
#' vector. It is silent and never fails, also for a vector R rejects (R checks that vector again
#' at the user's next draw), and the vector is assigned again so it stays identical.
#' @param state An environment: `seed` (the vector, or NULL) and `id`.
#' @param expr The expression to evaluate (lazily, inside the swap).
#' @return The value of `expr`.
#' @noRd
rng_swap = function(state, expr) {
  check_env(state, "state")
  seed = state$seed %||% rng_seeds(state$id %||% "gptr")
  env = globalenv()
  saved = get0(".Random.seed", envir = env, inherits = FALSE)
  kind = NULL
  if (is.null(saved)) {
    invisible(stats::rbinom(1L, 0L, 0.5))
    now = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(now)) rm(list = ".Random.seed", envir = env)
    kind = if (is.integer(now) && length(now)) now[1L] else 10403L
  }
  env[[".Random.seed"]] = seed
  on.exit({
    state$seed = get0(".Random.seed", envir = env, inherits = FALSE)
    if (!is.null(saved)) {
      env[[".Random.seed"]] = saved
      try(suppressWarnings(stats::rbinom(1L, 0L, 0.5)), silent = TRUE)
      env[[".Random.seed"]] = saved
    } else {
      env[[".Random.seed"]] = kind
      invisible(stats::rbinom(1L, 0L, 0.5))
      if (exists(".Random.seed", envir = env, inherits = FALSE)) {
        rm(list = ".Random.seed", envir = env)
      }
    }
  }, add = TRUE)
  expr
}
