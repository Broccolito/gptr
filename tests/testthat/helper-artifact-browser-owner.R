# Clone actual private callables and replace only constructor, clock and loop leaves.
artifact_owner_fixture = function(remote = FALSE) {
  namespace = environment(artifact_browser)
  separate_owner = exists("browser_owner", envir = get("artifact_state", envir = namespace),
    inherits = FALSE)
  scope = new.env(parent = namespace)
  scope$artifact_state = new.env(parent = emptyenv())
  scope$artifact_state$browser_pending = NULL
  state = new.env(parent = emptyenv())
  state$alive = TRUE
  state$active = TRUE
  state$local = TRUE
  state$events = character()
  state$clock = 0
  state$pump_timeouts = numeric()
  state$owner_calls = 0L
  state$container_calls = 0L
  state$wait_dead = TRUE
  state$draw = FALSE
  state$draw_construct = FALSE
  state$draw_close = FALSE
  state$draw_pump = FALSE
  state$draws = numeric()
  state$during = list()
  state$needs_pump = FALSE
  state$replace_on_close = FALSE
  state$factory_error = NULL
  state$process_error = NULL
  state$wait_error = NULL
  state$query_error = NULL
  state$active_error = NULL
  state$replace_construct = ""
  state$replace_launch = ""
  state$replace_pending_wait = FALSE
  state$constructed = NULL
  state$pump_error = NULL
  state$loop_error = NULL
  state$socket_error = NULL
  state$wait_jump = 0
  state$replace_browser = FALSE
  state$replace_owner = FALSE
  state$port = 4321L
  replacement = list(replacement = TRUE)
  loop = new.env(parent = emptyenv())
  draw = function(stage) {
    if (state$draw || isTRUE(state[[paste0("draw_", stage)]])) {
      state$draws = c(state$draws, runif(1))
    }
  }
  process = list(is_alive = function() {
    if (!is.null(state$query_error)) stop(state$query_error)
    state$alive
  }, wait = function(timeout) {
    stopifnot(length(timeout) == 1L, is.finite(timeout), timeout > 0, timeout <= 10000)
    state$wait_timeout = timeout
    state$events = c(state$events, "wait")
    state$during = c(state$during, list(scope$artifact_state$browser))
    draw("close")
    if (state$replace_pending_wait) scope$artifact_state$browser_pending = replacement
    if (!is.null(state$wait_error)) stop(state$wait_error)
    state$clock = state$clock + state$wait_jump
    if (state$wait_dead) state$alive = FALSE
  })
  owner = list(is_local = function() state$local, get_process = function() process,
    get_host = function() "127.0.0.1", get_port = function() 4321L,
    close = function(wait) {
      stopifnot(identical(wait, FALSE))
      state$events = c(state$events, "process")
      state$during = c(state$during, list(scope$artifact_state$browser))
      draw("close")
      if (!is.null(state$process_error)) stop(state$process_error)
    })
  make_remote = function(host = "127.0.0.1", port = 4321L) {
    list(is_local = function() FALSE, get_process = function() NULL,
      get_host = function() host, get_port = function() state$port)
  }
  make_container = function(browser) {
    list(get_browser = function() browser, is_alive = function() process$is_alive(),
      is_active = function() {
        if (!is.null(state$active_error)) stop(state$active_error)
        state$active
      }, get_child_loop = function() {
        if (!is.null(state$loop_error)) stop(state$loop_error)
        loop
      }, close = function(wait = TRUE) {
        draw("close")
        state$during = c(state$during, list(scope$artifact_state$browser))
        state$socket_wait = wait
        if (isTRUE(wait)) {
          state$events = c(state$events, "legacy-rpc")
          if (!is.null(state$process_error)) stop(state$process_error)
          if (state$wait_dead) state$alive = FALSE
        } else {
          state$events = c(state$events, "websocket")
        }
        if (!is.null(state$socket_error)) stop(state$socket_error)
        if (state$needs_pump) stop("The retained socket callback has not settled")
        state$active = FALSE
        if (state$replace_on_close) scope$artifact_state$browser = replacement
      })
  }
  container = make_container(if (!remote && !separate_owner) owner else make_remote())
  scope$artifact_state$browser = container
  scope$artifact_state$browser_owner = if (remote) NULL else owner
  rewrite = function(expr) {
    if (is.call(expr)) {
      heads = list(quote(chromote::Chrome$new), quote(chromote::ChromeRemote$new),
        quote(chromote::Chromote$new), quote(chromote::get_chrome_args),
        quote(later::run_now), quote(proc.time), quote(Sys.sleep))
      names = c("new_owner", "new_remote", "new_container", "chrome_args", "pump", "clock", "nap")
      for (i in seq_along(heads)) {
        if (identical(expr[[1L]], heads[[i]])) expr[[1L]] = as.name(names[[i]])
      }
      for (i in seq_along(expr)) expr[i] = list(rewrite(expr[[i]]))
    }
    expr
  }
  scope$new_owner = function(args) {
    stopifnot(identical(args, "--use-mock-keychain"))
    state$owner_calls = state$owner_calls + 1L
    state$alive = TRUE
    state$active = TRUE
    draw("construct")
    if (state$replace_launch %in% c("browser", "both", "all")) {
      scope$artifact_state$browser = replacement
    }
    if (state$replace_launch %in% c("owner", "both", "all")) {
      scope$artifact_state$browser_owner = replacement
    }
    if (state$replace_launch %in% c("pending", "all")) {
      scope$artifact_state$browser_pending = replacement
    }
    owner
  }
  scope$new_remote = function(host, port) {
    stopifnot(identical(host, "127.0.0.1"), identical(port, 4321L))
    make_remote(host, port)
  }
  scope$new_container = function(browser = NULL) {
    state$container_calls = state$container_calls + 1L
    draw("construct")
    if (state$replace_construct %in% c("browser", "both", "all")) {
      scope$artifact_state$browser = replacement
    }
    if (state$replace_construct %in% c("owner", "both", "all")) {
      scope$artifact_state$browser_owner = replacement
    }
    if (state$replace_construct %in% c("pending", "all")) {
      scope$artifact_state$browser_pending = replacement
    }
    if (!is.null(state$factory_error)) stop(state$factory_error)
    if (is.null(browser)) {
      state$alive = TRUE
      state$active = TRUE
    }
    state$constructed = make_container(if (is.null(browser)) owner else browser)
    state$constructed
  }
  scope$chrome_args = function() character()
  scope$clock = function() {
    state$clock = state$clock + 0.01
    c(elapsed = state$clock)
  }
  scope$nap = function(seconds) {
    stopifnot(length(seconds) == 1L, seconds > 0, seconds <= 0.01)
    state$clock = state$clock + seconds
  }
  scope$pump = function(loop, ...) {
    args = list(...)
    stopifnot(identical(names(args), "timeoutSecs"),
      args[["timeoutSecs"]] > 0,
      args[["timeoutSecs"]] <= 0.02 || identical(args[["timeoutSecs"]], 0.2),
      identical(loop, get("loop", envir = environment(make_remote))))
    state$pump_timeouts = c(state$pump_timeouts, args[["timeoutSecs"]])
    state$events = c(state$events, "pump")
    state$during = c(state$during, list(scope$artifact_state$browser))
    state$alive_at_pump = state$alive
    draw("pump")
    if (!is.null(state$pump_error)) stop(state$pump_error)
    state$needs_pump = FALSE
    if (state$replace_browser) scope$artifact_state$browser = replacement
    if (state$replace_owner) scope$artifact_state$browser_owner = replacement
    invisible(FALSE)
  }
  open = artifact_browser
  close = artifact_browser_close
  body(open) = rewrite(body(open))
  body(close) = rewrite(body(close))
  environment(open) = environment(close) = scope
  scope$artifact_browser_close = close
  list(scope = scope, state = state, open = open, close = close,
    owner = owner, container = container, replacement = replacement)
}
