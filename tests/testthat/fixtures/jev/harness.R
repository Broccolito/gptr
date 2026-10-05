# Shared helpers of the P13 test files (plan P13), sourced at the top of each of them. P13 owns
# no helper-*.R file; these build on P01's test helpers (local_project(), local_gptr_options()),
# P02's registry, P08's call_new() and P13's own functions.

# A temporary project and an empty System 1 memory cache for the calling test. `gptr = TRUE`
# creates .gptr/, so answers go to the file cache under .gptr/cache/s1/.
s1_fresh = function(gptr = FALSE, .env = parent.frame()) {
  dir = local_project(gptr = gptr, .env = .env)
  old = s1_cache_swap()
  withr::defer(s1_cache_swap(old), envir = .env)
  invisible(dir)
}

# One recorded wire fixture of tests/testthat/fixtures/jev/ as a list
jev_fixture = function(name) {
  path = testthat::test_path("fixtures", "jev", paste0(name, ".json"))
  json_decode(read_utf8(path)$text)
}

# Forget the once-keys of gptr_inform() (kind "message") or gptr_warn() (kind "warning") for the
# calling test, so that a once-per-process notice shows again; the keys are restored afterwards
local_once_reset = function(keys, kind = "message", .env = parent.frame()) {
  slots = paste0(kind, ":", keys)
  had = vapply(slots, function(s) isTRUE(the$once[[s]]), NA)
  for (s in slots[had]) rm(list = s, envir = the$once)
  withr::defer(for (s in slots[had]) assign(s, TRUE, envir = the$once), envir = .env)
  invisible(NULL)
}

# A gptr_call record (P08's call_new()) for the classifier route: every named argument in `...`
# becomes a context object read by name from a fresh environment, as gptr() records symbols
s1_test_call = function(prompt, ..., model, args = list(), session = NULL) {
  objs = list(...)
  env = new.env(parent = globalenv())
  items = list()
  for (nm in names(objs)) {
    assign(nm, objs[[nm]], envir = env)
    items[[length(items) + 1L]] = list(label = nm, kind = "symbol", name = nm, slot = NULL,
                                       facts = list(class = class(objs[[nm]])))
  }
  full = list(threshold = 0.5, choices = NULL, levels = NULL, min_confidence = NULL,
              uncertain = NULL, replay = NULL, opts = list())
  for (k in names(args)) full[k] = list(args[[k]])
  call_new(prompt = prompt, session = session, context = items, envir = env,
           ids = list(model = model), args = full)
}

# Provide a service for the calling test through the registry's `service` kind (IC-34), as P15
# provides doc.s1_block
s1_local_service = function(name, fun, .env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), source = "user", rank = 3L)
  withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

# Register the typesafe-system-one adapter for the calling test when builtin:system1 has not
# (Tasks 4-8 run before Task 9 registers the built-in)
local_s1_adapter = function(.env = parent.frame()) {
  if (!is.null(registry_get("adapter", "typesafe-system-one"))) return(invisible(NULL))
  off = gptr_register(gptr_adapter("typesafe-system-one", transport = "http_json",
                                   classify = list(build = s1_typesafe_build,
                                                   parse = s1_typesafe_parse)))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

# Make every System 1 HTTP transfer fail the test: tests that must not reach the network
local_no_network = function(.env = parent.frame()) {
  local_mocked_bindings(s1_http = function(spec, provider, on_done, on_fail) {
    stop("a System 1 test tried to send an HTTP request to ", spec$url)
  }, .env = .env)
}
