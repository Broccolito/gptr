# Shared helpers of the P02 extension tests (test-ext-*.R).

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
