test_that("live direct specs survive collection and a later piped turn", {
  skip_on_cran()
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  log = new.env(parent = emptyenv())
  log$calls = character()
  probe = test_tool("retention_probe", function(ctx) {
    log$calls = c(log$calls, "called")
    "ok"
  })
  fake = gptr_fake_provider(list(fake_tool("retention_probe"), "first",
                                 fake_tool("retention_probe"), "second"))
  session = peter("first", model = fake, tools = list(probe),
                  envir = new.env(parent = emptyenv()))
  withr::defer(registry_session_drop(session$id))
  hook = gptr_on(session, "message_end", function(event, ctx) {
    log$hook_session = session$id
    NULL
  })
  withr::defer(hook())
  invisible(gc())
  expect_identical(registry_get("tool", "retention_probe", session = session$id)$execute,
                   probe$execute)
  expect_identical(registry_get("provider", fake$name, session = session$id)$log, fake$log)
  expect_identical(session |> peter("second"), session)
  expect_identical(session$text, "second")
  expect_identical(log$calls, rep("called", 2L))
  expect_identical(log$hook_session, session$id)
  expect_identical(session$turns, 2L)
})

test_that("discarded closure-bearing direct specs do not root their session", {
  skip_on_cran()
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  make = function() {
    canary = new.env(parent = emptyenv())
    canary$bytes = raw(32768L)
    tool = test_tool("discard_probe", function(ctx) {
      invisible(canary$bytes)
      "ok"
    })
    fake = gptr_fake_provider(function(request) {
      invisible(canary$bytes)
      if (request$n == 1L) fake_tool("discard_probe") else "done"
    }, name = "discard-provider")
    session = peter("one", model = fake, tools = list(tool),
                    envir = new.env(parent = emptyenv()))
    list(id = session$id, key = rlang::new_weakref(key = session),
         canary = rlang::new_weakref(key = canary),
         records = unname(get0(session$id, envir = gateway_state()$specs, inherits = FALSE)))
  }
  discarded = make()
  withr::defer(registry_session_drop(discarded$id))
  expect_false(is.null(rlang::wref_key(discarded$key)))
  expect_length(discarded$records, 2L)
  invisible(peter("other", model = gptr_fake_provider(list("other")),
                  envir = new.env(parent = emptyenv())))
  for (i in seq_len(3L)) {
    invisible(gc())
    ev_drain()
  }
  expect_null(rlang::wref_key(discarded$key))
  expect_null(rlang::wref_key(discarded$canary))
  expect_null(session_by_id(discarded$id))
  expect_true(all(!discarded$records %in% ls(registry_env()$recs)))
  expect_null(get0(discarded$id, envir = gateway_state()$specs, inherits = FALSE))
})

test_that("collected aliased hooks are removed from their event index", {
  skip_on_cran()
  local_gw()
  make = function() {
    session = peter("one", model = gptr_fake_provider(list("done")),
                    envir = new.env(parent = emptyenv()))
    handler = function(event, ctx) {
      invisible(session$id)
      NULL
    }
    spec = gptr_spec("hook", "retention_alias", event = "message_end", handler = handler)
    id = registry_add(spec, source = "session", rank = 0L, session = session$id)
    list(id = session$id, record = id, key = rlang::new_weakref(key = session))
  }
  discarded = make()
  withr::defer(registry_session_drop(discarded$id))
  expect_true(discarded$record %in% get0("message_end", envir = registry_env()$hooks))
  invisible(peter("other", model = gptr_fake_provider(list("other")),
                  envir = new.env(parent = emptyenv())))
  for (i in seq_len(3L)) {
    invisible(gc())
    ev_drain()
  }
  expect_null(rlang::wref_key(discarded$key))
  expect_false(discarded$record %in% ls(registry_env()$recs))
  expect_false(discarded$record %in% get0("message_end", envir = registry_env()$hooks))
  expect_false(discarded$record %in% get0("retention_alias", envir = registry_env()$hooks))
})

test_that("a collected session still dispatches its own shutdown handler before removal", {
  skip_on_cran()
  local_gw()
  log = new.env(parent = emptyenv())
  log$reason = NULL
  handler_env = new.env(parent = baseenv())
  handler_env$log = log
  handler = eval(quote(function(event, ctx) {
    log$reason = event$reason
    NULL
  }), handler_env)
  make = function() {
    session = peter("one", model = gptr_fake_provider(list("done")),
                    envir = new.env(parent = emptyenv()))
    spec = gptr_spec("hook", "retention_shutdown", event = "session_shutdown", handler = handler)
    id = registry_add(spec, source = "session", rank = 0L, session = session$id)
    list(id = session$id, record = id, key = rlang::new_weakref(key = session))
  }
  discarded = make()
  withr::defer(registry_session_drop(discarded$id))
  invisible(peter("other", model = gptr_fake_provider(list("other")),
                  envir = new.env(parent = emptyenv())))
  for (i in seq_len(3L)) {
    invisible(gc())
    ev_drain()
  }
  expect_null(rlang::wref_key(discarded$key))
  expect_identical(log$reason, "gc")
  expect_false(discarded$record %in% ls(registry_env()$recs))
  expect_false(discarded$record %in% get0("session_shutdown", envir = registry_env()$hooks))
})

test_that("forked sessions preserve copied direct specs for their own turns", {
  skip_on_cran()
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  tool = test_tool("fork_probe", function(ctx) "ok")
  fake = gptr_fake_provider(list(fake_tool("fork_probe"), "first",
                                 fake_tool("fork_probe"), "branch"))
  session = peter("first", model = fake, tools = list(tool),
                  envir = new.env(parent = emptyenv()))
  branch = gptr_fork(session)
  withr::defer({
    registry_session_drop(session$id)
    registry_session_drop(branch$id)
  })
  invisible(gc())
  expect_identical(registry_get("tool", "fork_probe", session = branch$id)$execute,
                   tool$execute)
  expect_identical(registry_get("provider", fake$name, session = branch$id)$log, fake$log)
  expect_identical(branch |> peter("branch"), branch)
  expect_identical(branch$text, "branch")
  expect_identical(session$text, "first")
})

test_that("worker snapshots hydrate session records without starting a worker", {
  local_gw()
  execute = eval(quote(function(input, ctx) "worker-ok"), baseenv())
  tool = gptr_tool("worker_retention_probe", "Worker probe",
                   parameters = list(type = "object", properties = json_obj()), execute = execute)
  fake = gptr_fake_provider(list("done"))
  session = peter("one", model = fake, tools = list(tool),
                  envir = new.env(parent = emptyenv()))
  withr::defer(registry_session_drop(session$id))
  snapshot = worker_registry(session$id)
  scoped = Filter(function(record) isTRUE(record$session), snapshot$specs)
  expect_setequal(vapply(scoped, function(record) record$spec$name, ""),
                  c("worker_retention_probe", fake$name))
  selected = Filter(function(record) identical(record$spec$name, "worker_retention_probe"),
                    scoped)
  expect_length(selected, 1L)
  expect_identical(selected[[1L]]$spec$execute, execute)
  restored = unserialize(serialize(snapshot, NULL))
  copied = Filter(function(record) identical(record$spec$name, "worker_retention_probe"),
                  restored$specs)
  expect_identical(copied[[1L]]$spec$execute(list(), NULL), "worker-ok")
})

test_that("explicit global registration keeps its captured state until removal", {
  skip_on_cran()
  local_gw()
  make = function() {
    canary = new.env(parent = emptyenv())
    canary$value = "global-ok"
    tool = test_tool("global_retention_probe", function(ctx) canary$value)
    list(key = rlang::new_weakref(key = canary), off = gptr_register(tool))
  }
  registered = make()
  withr::defer(registered$off())
  invisible(gc())
  expect_false(is.null(rlang::wref_key(registered$key)))
  expect_identical(registry_get("tool", "global_retention_probe")$execute(list(), NULL),
                   "global-ok")
  expect_true(registered$off())
  expect_null(registry_get("tool", "global_retention_probe"))
  for (i in seq_len(3L)) invisible(gc())
  expect_null(rlang::wref_key(registered$key))
})

test_that("collected scoped specs survive deferred shutdown without resurrection", {
  skip_on_cran()
  local_gw()
  reg = registry_env()
  previous = gptr_last()
  withr::defer(last_set(previous))
  log = new.env(parent = emptyenv())
  handler_env = new.env(parent = asNamespace("gptr"))
  handler_env$log = log
  handler = eval(quote(function(event, ctx) {
    spec = registry_get("command", "handoff_probe", session = event$session)
    log$value = if (is.null(spec)) NULL else spec$handler(character(), ctx)
    NULL
  }), handler_env)
  make = function() {
    session = peter("one", model = gptr_fake_provider(list("done")),
                    envir = new.env(parent = emptyenv()))
    command = gptr_command("handoff_probe", function(args, ctx) {
      invisible(session$id)
      "held"
    })
    id = registry_add(command, source = "session", rank = 0L, session = session$id)
    removed = registry_add(gptr_command("removed_probe", command$handler),
                            source = "session", rank = 0L, session = session$id)
    registry_remove(removed)
    shutdown = registry_add(gptr_spec("hook", "handoff_shutdown", event = "session_shutdown",
                                      handler = handler),
                             source = "session", rank = 0L, session = session$id)
    list(id = session$id, key = rlang::new_weakref(key = session), record = id,
         records = c(unname(get0(session$id, envir = gateway_state()$specs)), id),
         removed = removed, shutdown = shutdown)
  }
  discarded = make()
  withr::defer(registry_session_drop(discarded$id))
  last_set(NULL)
  invisible(gc())
  expect_null(rlang::wref_key(discarded$key))
  expect_null(session_by_id(discarded$id))
  expect_false(is.null(get0(discarded$record, envir = reg$recs, inherits = FALSE)))
  expect_length(registry_recs(reg, discarded$record), 1L)
  collected = get0("collected", envir = reg, inherits = FALSE)
  expect_true(is.environment(collected))
  own = c(discarded$records, discarded$removed, discarded$shutdown)
  held_ids = function() {
    if (is.environment(collected)) intersect(ls(collected), own) else character()
  }
  held = held_ids()
  expect_setequal(held, c(discarded$records, discarded$shutdown))
  expect_false(discarded$removed %in% held)
  expect_null(log$value)
  ev_drain()
  expect_identical(log$value, "held")
  expect_false(any(c(discarded$records, discarded$removed, discarded$shutdown) %in% ls(reg$recs)))
  expect_length(held_ids(), 0L)
  for (i in seq_len(3L)) invisible(gc())
  expect_length(held_ids(), 0L)
})

test_that("a self-capturing public shutdown hook releases its session after safe dispatch", {
  skip_on_cran()
  local_gw()
  reg = registry_env()
  previous = gptr_last()
  withr::defer(last_set(previous))
  log = new.env(parent = emptyenv())
  log$order = character()
  make = function() {
    canary = new.env(parent = emptyenv())
    canary$bytes = raw(32768L)
    session = peter("one", model = gptr_fake_provider(list("done")),
                    envir = new.env(parent = emptyenv()))
    invisible(gptr_on(session, "session_shutdown", function(event, ctx) {
      log$order = c(log$order, "shutdown")
      log$reason = event$reason
      log$id = session$id
      log$bytes = length(canary$bytes)
      log$after = rlang::new_weakref(key = canary)
      log$fresh_live = !is.null(rlang::wref_key(log$after))
      NULL
    }))
    hooks = get0("session_shutdown", envir = reg$hooks, inherits = FALSE)
    own_hooks = Filter(function(id) {
      identical(get0(id, envir = reg$recs, inherits = FALSE)$session, session$id)
    }, hooks)
    list(id = session$id, key = rlang::new_weakref(key = session),
         canary = rlang::new_weakref(key = canary),
         records = c(unname(get0(session$id, envir = gateway_state()$specs)), own_hooks))
  }
  discarded = make()
  withr::defer(registry_session_drop(discarded$id))
  expect_length(discarded$records, 2L)
  last_set(NULL)
  invisible(gc())
  expect_null(rlang::wref_key(discarded$key))
  expect_null(rlang::wref_key(discarded$canary))
  expect_identical(log$order, character())
  collected = get0("collected", envir = reg, inherits = FALSE)
  held_ids = function() intersect(ls(collected), discarded$records)
  expect_setequal(held_ids(), discarded$records)
  ev_drain()
  expect_identical(log$order, "shutdown")
  expect_identical(log$reason, "gc")
  expect_identical(log$id, discarded$id)
  expect_identical(log$bytes, 32768L)
  expect_false(is.null(log$after))
  expect_true(log$fresh_live)
  expect_false(any(discarded$records %in% ls(reg$recs)))
  expect_length(held_ids(), 0L)
  for (i in seq_len(3L)) invisible(gc())
  expect_null(if (is.null(log$after)) NULL else rlang::wref_key(log$after))
  expect_length(held_ids(), 0L)
})
