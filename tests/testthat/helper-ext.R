# Shared helpers of the extension registry and service tests.

local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

local_builtins = function(env = parent.frame()) {
  old = the$builtins
  withr::defer(assign("builtins", old, envir = the), envir = env)
  the$builtins = list()
  invisible(NULL)
}

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

# Provide a service for the calling test through the registry's `service` kind (IC-34)
local_service = function(name, fun, .env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), source = "user", rank = 3L)
  withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

# Bind a service in P01's bootstrap table for the calling test (the entry is restored afterwards)
local_bootstrap_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# Empty P01's bootstrap service table for the calling test (later plans fill it from on_load())
local_no_bootstrap_services = function(.env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = .env)
  assign("services", list(), envir = the)
  invisible(NULL)
}

# Record the bridge_call events (P22) raised while the calling test runs
local_bridge_events = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$events = list()
  off = gptr_register(gptr_hook("bridge_call", function(event, ctx) {
    log$events[[length(log$events) + 1L]] = event
    NULL
  }))
  withr::defer(off(), envir = .env)
  log
}
