# Numeric-only diagnostic for this owned synthetic spec; no object/path/name is published.
worker_size_report = eval(quote(function(path, refhook, file_cap = 16 * 1024^2) {
  started = proc.time()[["elapsed"]]
  bytes = file.size(path)
  stopifnot(length(bytes) == 1L, is.finite(bytes), bytes > 0, bytes <= file_cap)
  before = readBin(path, "raw", n = file_cap + 1L)
  stopifnot(length(before) == bytes)
  spec = readRDS(path, refhook = refhook)
  labels = c("prompt", "model", "mode", "depth", "agent", "name", "object_names",
    "export", "preset", "rng_state", "settings", "env_profile", "registry", "key_provider",
    "parent", "history", "objects")
  stopifnot(is.list(spec), !anyDuplicated(names(spec)), setequal(names(spec), labels))
  state = new.env(parent = emptyenv())
  state$calls = 0L
  measure = function(value) {
    state$calls = state$calls + 1L
    stopifnot(state$calls <= 96L, proc.time()[["elapsed"]] - started <= 10)
    size = length(serialize(value, NULL, ascii = FALSE, refhook = refhook))
    # Serialization is synchronous; this is a post-allocation diagnostic acceptance cap.
    stopifnot(size <= 32 * 1024^2, proc.time()[["elapsed"]] - started <= 10)
    as.numeric(size)
  }
  fields = lapply(spec[labels], measure)
  registry = spec$registry
  stopifnot(is.list(registry), identical(names(registry), c("specs", "plugins", "filters")),
    is.list(registry$specs), length(registry$specs) <= 32L)
  records = lapply(seq_along(registry$specs), function(index) {
    record = registry$specs[[index]]
    stopifnot(is.list(record), identical(names(record), c("spec", "session")),
      is.list(record$spec), length(record$spec) <= 64L)
    closures = unname(which(vapply(record$spec, is.function, logical(1))))
    stopifnot(length(closures) <= 8L)
    sizes = lapply(closures, function(position) {
      fun = record$spec[[position]]
      env = environment(fun)
      bindings = if (is.environment(env)) ls(env, all.names = TRUE) else character()
      stopifnot(length(bindings) <= 4096L)
      list(position = as.integer(position), bytes = measure(fun),
        source_bytes = measure(attributes(fun)), bindings = length(bindings),
        namespace = is.environment(env) && isNamespace(env),
        global = identical(env, globalenv()), base = identical(env, baseenv()),
        empty = identical(env, emptyenv()))
    })
    list(index = as.integer(index), bytes = measure(record$spec),
      fields = length(record$spec), session = isTRUE(record$session),
      provider = inherits(record$spec, "gptr_provider"),
      command = inherits(record$spec, "gptr_command"), closures = sizes)
  })
  after = readBin(path, "raw", n = file_cap + 1L)
  stopifnot(identical(before, after), proc.time()[["elapsed"]] - started <= 10)
  list(complete = TRUE, file_bytes = as.numeric(bytes), fields = fields,
    registry_records = records, registry_count = length(registry$specs),
    registry_plugins_bytes = measure(registry$plugins),
    registry_filters_bytes = measure(registry$filters), measurements = state$calls,
    spec_unchanged = TRUE)
}), envir = new.env(parent = baseenv()))

# Diagnostic failures do not bypass the separately mandatory original cleanup.
worker_size_capture = eval(quote(function(report, publish) {
  tryCatch({
    value = report()
    publish(value)
    value
  }, error = function(e) list(complete = FALSE, error_code = 1L),
    interrupt = function(e) list(complete = FALSE, error_code = 2L))
}), envir = new.env(parent = baseenv()))
