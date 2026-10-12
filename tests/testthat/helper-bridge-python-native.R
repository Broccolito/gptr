# Native Python startup, observed from an independent processx/Rscript watchdog.
# No Python initialization or caller environment mutation occurs in the supervising R process.
py_native_child = function(case, root, failure) {
  seen = new.env(parent = emptyenv())
  seen$total = 0L
  seen$classes = list()
  seen$stage = "entered"
  phase = function(text) {
    cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE, sep = "")
  }
  diagnostic_stages = c("entered", "identity-save", "startup-read", "snapshot-before",
    "usage-before", "direct-reticulate-init", "independent-cli-run", "independent-cli-decode",
    "python-first-eval", "python-second-eval", "python-knitr-eval", "python-third-eval",
    "python-import-eval", "python-config", "library-stat", "checks", "finished",
    "reticulate-required", "knitr-required", "json-required", "fresh-python", "offline",
    "managed-disabled", "explicit-python", "private-prefix", "explicit-version-pins",
    "explicit-native-library", "explicit-native-library-sha", "native-absent-seed",
    "native-unrelated-empty", "native-known-empty", "native-case-empty",
    "native-initialized-empty-seed", "already-initialized", "native-empty-survives-direct-init",
    "independent-cli-status", "bounded-cli-identity", "closed-cli-identity",
    "independent-private-venv", "independent-library-hash", "independent-version",
    "first-python-result", "compiled-import-result", "bounded-import-identity",
    "closed-import-identity", "linux-cli-diagnostics", "owned-r-absent-seed")
  run = function() {
    assert_native = function(value, stage) {
      seen$stage = stage
      if (!isTRUE(value)) stop(paste("Native Python fixture failed:", stage), call. = FALSE)
      invisible(TRUE)
    }
    phase("entered")
    phase(if (any(toupper(names(Sys.getenv())) == "LD_LIBRARY_PATH"))
      "after-loader-ld-present" else "after-loader-ld-absent")
    file.create(file.path(root, "case-started"))
    seen$stage = "identity-save"
    handle = ps::ps_handle()
    saveRDS(list(pid = Sys.getpid(), create_time = as.numeric(ps::ps_create_time(handle))),
            file.path(root, "inner-identity.rds"))
    assert_native(requireNamespace("reticulate", quietly = TRUE), "reticulate-required")
    assert_native(requireNamespace("knitr", quietly = TRUE), "knitr-required")
    assert_native(requireNamespace("jsonlite", quietly = TRUE), "json-required")
    assert_native(!reticulate::py_available(initialize = FALSE), "fresh-python")
    assert_native(identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"), "offline")
    assert_native(identical(Sys.getenv("RETICULATE_USE_MANAGED_VENV"), "false"), "managed-disabled")
    seen$stage = "startup-read"
    configured = Sys.getenv("RETICULATE_PYTHON")
    prefix = Sys.getenv("GPTR_PY_NATIVE_PREFIX")
    pins = Sys.getenv(c("GPTR_PY_NATIVE_VERSION", "GPTR_NP_NATIVE_VERSION",
                       "GPTR_PD_NATIVE_VERSION"))
    assert_native(nzchar(configured) && file.exists(configured), "explicit-python")
    assert_native(nzchar(prefix) && dir.exists(prefix) &&
                    file.exists(file.path(prefix, "pyvenv.cfg")), "private-prefix")
    assert_native(all(nzchar(pins)), "explicit-version-pins")
    library = Sys.getenv("GPTR_PY_NATIVE_LIBPYTHON")
    library_sha = Sys.getenv("GPTR_PY_NATIVE_LIB_SHA256")
    assert_native(nzchar(library) && file.exists(library), "explicit-native-library")
    assert_native(grepl("^[0-9a-f]{64}$", library_sha), "explicit-native-library-sha")
    same_path = function(a, b) {
      a = normalizePath(a, winslash = "/", mustWork = TRUE)
      b = normalizePath(b, winslash = "/", mustWork = TRUE)
      if (.Platform$OS.type == "windows") identical(tolower(a), tolower(b)) else identical(a, b)
    }
    inside = function(path, dir) {
      path = normalizePath(path, winslash = "/", mustWork = TRUE)
      dir = normalizePath(dir, winslash = "/", mustWork = TRUE)
      if (.Platform$OS.type == "windows") {
        path = tolower(path)
        dir = tolower(dir)
      }
      startsWith(path, paste0(dir, "/"))
    }
    cli_environment = function(raw, variant, library_dir) {
      stopifnot(is.character(raw), !anyNA(raw), !is.null(names(raw)),
        all(nzchar(names(raw))), !anyDuplicated(toupper(names(raw))),
        length(variant) == 1L, variant %in% c("inherited", "prepend", "unset", "direct"),
        is.character(library_dir), length(library_dir) == 1L, !is.na(library_dir),
        nzchar(library_dir))
      if (variant %in% c("inherited", "direct")) return(raw)
      hits = which(toupper(names(raw)) == "LD_LIBRARY_PATH")
      old = if (length(hits)) raw[[hits]] else ""
      env = raw[!toupper(names(raw)) %in% "LD_LIBRARY_PATH"]
      if (variant == "prepend") {
        value = if (nzchar(old)) paste(library_dir, old, sep = ":") else library_dir
        env = c(env, LD_LIBRARY_PATH = value)
      }
      env
    }
    cli_version_phase = function(variant, version, expected, env, mapped = NULL) {
      stopifnot(length(variant) == 1L,
        variant %in% c("inherited", "prepend", "unset", "direct", "original"))
      version_text = function(x) {
        valid = is.character(x) && length(x) == 1L && !is.na(x) &&
          grepl("^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$", x)
        if (valid) x else "invalid"
      }
      type_text = function(x) {
        types = c("character", "integer", "double", "logical", "NULL")
        if (length(x) == 1L && !anyNA(x) && typeof(x) %in% types) typeof(x) else "invalid"
      }
      hits = which(toupper(names(env)) == "LD_LIBRARY_PATH")
      present = length(hits) == 1L &&
        library_dir %in% strsplit(env[[hits]], ":", fixed = TRUE)[[1L]]
      phase(paste0("cli-version-", variant, "-expected-", version_text(expected),
        "-observed-", version_text(version)))
      phase(paste0("cli-type-", variant, "-expected-", type_text(expected),
        "-observed-", type_text(version)))
      phase(paste0("cli-admitted-dir-", variant, if (present) "-present" else "-absent"))
      phase(paste0("cli-mapped-", variant,
        if (isTRUE(mapped)) "-yes" else if (identical(mapped, FALSE)) "-no" else "-unknown"))
      invisible(NULL)
    }
    seed = function(name, value, exact_name = FALSE) {
      raw = Sys.getenv()
      hits = which(toupper(names(raw)) == toupper(name))
      length(hits) == 1L && identical(raw[[hits]], value) &&
        (!exact_name || identical(names(raw)[hits], name))
    }
    keys = c("PATH", "VIRTUAL_ENV", "R_SESSION_INITIALIZED", "LD_LIBRARY_PATH",
             "PYTHONPATH", "PYTHONIOENCODING")
    absent = setdiff(keys, "PATH")
    phase(if (any(toupper(names(Sys.getenv())) == "LD_LIBRARY_PATH"))
      "preseed-ld-present" else "preseed-ld-absent")
    phase(if (any(toupper(names(Sys.getenv())) == "VIRTUAL_ENV"))
      "preseed-virtual-present" else "preseed-virtual-absent")
    phase(if (any(toupper(names(Sys.getenv())) == "R_SESSION_INITIALIZED"))
      "preseed-session-present" else "preseed-session-absent")
    phase(if (any(toupper(names(Sys.getenv())) == "PYTHONPATH"))
      "preseed-pythonpath-present" else "preseed-pythonpath-absent")
    phase(if (any(toupper(names(Sys.getenv())) == "PYTHONIOENCODING"))
      "preseed-encoding-present" else "preseed-encoding-absent")
    if (case == "absent") {
      # R.sh may seed LD_LIBRARY_PATH after the complete native launch vector was supplied.
      # This deliberate setup belongs only to this disposable owned R-session fixture.
      seen$stage = "owned-r-absent-seed"
      phase("owned-r-absent-seed")
      Sys.unsetenv(absent)
      assert_native(!any(toupper(names(Sys.getenv())) %in% absent), "native-absent-seed")
    }
    if (case == "unrelated") {
      assert_native(seed("GPTR_PY_NATIVE_EMPTY", ""), "native-unrelated-empty")
    }
    if (case == "empty") assert_native(seed("PYTHONPATH", ""), "native-known-empty")
    if (case == "alias") assert_native(seed("pythonpath", "", TRUE), "native-case-empty")
    if (case == "initialized") {
      assert_native(seed("PYTHONIOENCODING", ""), "native-initialized-empty-seed")
      # This separate admission case deliberately initializes reticulate before GPTR.
      # It cannot certify GPTR-first setup. The empty key must survive this real setup.
      phase("direct-reticulate-init")
      seen$stage = "direct-reticulate-init"
      invisible(reticulate::import_main(convert = FALSE))
      assert_native(reticulate::py_available(initialize = FALSE), "already-initialized")
      assert_native(seed("PYTHONIOENCODING", ""), "native-empty-survives-direct-init")
    }
    withr::local_seed(68017)
    sentinel = data.frame(x = 1:6, label = rep("synthetic", 6L))
    bytes = serialize(sentinel, NULL)
    snapshot = function() {
      list(env = Sys.getenv(), options = options(), cwd = getwd(), libraries = .libPaths(),
        seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
        globals = sort(ls(envir = globalenv(), all.names = TRUE)),
        bytes = serialize(sentinel, NULL))
    }
    seen$stage = "snapshot-before"
    before = snapshot()
    seen$stage = "usage-before"
    native_usage = nrow(gptr:::usage_log())
    versions = NULL
    phase("gptr-first-call")
    if (case %in% c("empty", "alias")) {
      condition = tryCatch(gptr::peter$py("41 + 1"), error = identity)
      seen$stage = "checks"
      checks = list(native_seed_observed = TRUE,
        typed_refusal = inherits(condition, "gptr_error_not_available"),
        still_uninitialized = !reticulate::py_available(initialize = FALSE),
        full_state_after_refusal = identical(snapshot(), before),
        no_native_usage = identical(nrow(gptr:::usage_log()), native_usage))
    } else {
      # The embedded home may make sys.base_prefix equal the venv prefix. The independent
      # executable supplies the real CLI base, and the separately admitted library hash.
      phase("independent-python-cli")
      cli_code = paste(
        "import os, sys, json, hashlib", "library = os.path.realpath(sys.argv[1])",
        "base = os.path.realpath(sys.base_prefix)", "limit = 64 * 1024 * 1024",
        "size = os.path.getsize(library)", "assert 0 < size <= limit",
        "assert os.path.normcase(os.path.commonpath([library, base])) == os.path.normcase(base)",
        "assert os.path.normcase(library) != os.path.normcase(base)",
        "hash = hashlib.sha256()", "read = 0", "with open(library, 'rb') as stream:",
        " while True:", "  chunk = stream.read(1024 * 1024)", "  if not chunk: break",
        "  read += len(chunk)", "  assert read <= limit", "  hash.update(chunk)",
        "assert read == size == os.path.getsize(library)",
        "print(json.dumps(dict(executable=os.path.abspath(sys.executable), prefix=sys.prefix,",
        " base_prefix=sys.base_prefix, version='.'.join(map(str, sys.version_info[:3])),",
        " library=library, sha256=hash.hexdigest(), library_bytes=read)))", sep = "\n")
      # This Linux-only diagnostic precedes the unchanged strict identity/version oracle.
      # Only public numeric versions and fixed booleans leave these owned CLI probes.
      library_dir = dirname(normalizePath(library, winslash = "/", mustWork = TRUE))
      if (identical(Sys.info()[["sysname"]], "Linux")) {
        probe_code = paste("import os, sys, json",
          "library = os.path.realpath(sys.argv[1])",
          "with open('/proc/self/maps', encoding='utf-8') as stream:",
          " maps = stream.read(1024 * 1024 + 1)", "assert len(maps) <= 1024 * 1024",
          "entries = [line.split(None, 5) for line in maps.splitlines()]",
          "mapped = any(len(row) == 6 and os.path.realpath(row[5]) == library for row in entries)",
          "print(json.dumps(dict(version='.'.join(map(str, sys.version_info[:3])),",
          " admitted_library_mapped=mapped)))", sep = "\n")
        probe_args = c("-I", "-c", probe_code, library)
        complete = logical()
        for (variant in c("inherited", "prepend", "unset", "direct")) {
          seen$stage = "linux-cli-diagnostics"
          env = cli_environment(Sys.getenv(), variant, library_dir)
          probe = tryCatch({
            if (variant == "direct") {
              processx::run(configured, probe_args, env = env, timeout = 10,
                error_on_status = FALSE, cleanup_tree = TRUE, supervise = FALSE,
                encoding = "UTF-8", echo = FALSE, spinner = FALSE)
            } else {
              gptr:::proc_run(configured, probe_args, env = env, timeout = 10, echo = FALSE)
            }
          }, error = function(error) error)
          if (inherits(probe, "error")) {
            phase(paste0("cli-probe-", variant, "-condition"))
            complete = c(complete, FALSE)
            next
          }
          timeout = if (variant == "direct") isTRUE(probe$timeout) else isTRUE(probe$timed_out)
          phase(paste0("cli-probe-", variant,
            if (identical(probe$status, 0L)) "-exit-zero" else "-exit-not-zero"))
          phase(paste0("cli-probe-", variant, if (timeout) "-timeout" else "-no-timeout"))
          phase(paste0("cli-probe-", variant,
            if (identical(probe$stderr, "")) "-stderr-empty" else "-stderr-not-empty"))
          bounded = is.character(probe$stdout) && length(probe$stdout) == 1L &&
            !is.na(probe$stdout) && nchar(probe$stdout, type = "bytes") <= 4096L
          identity = if (bounded) tryCatch(jsonlite::fromJSON(probe$stdout),
            error = function(error) NULL) else NULL
          closed = is.list(identity) &&
            identical(names(identity), c("version", "admitted_library_mapped")) &&
            is.character(identity$version) && length(identity$version) == 1L &&
            !is.na(identity$version) &&
            grepl("^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$", identity$version) &&
            is.logical(identity$admitted_library_mapped) &&
            length(identity$admitted_library_mapped) == 1L &&
            !is.na(identity$admitted_library_mapped)
          cli_version_phase(variant, if (closed) identity$version else NULL,
            unname(pins[[1L]]), env, if (closed) identity$admitted_library_mapped else NULL)
          complete = c(complete, identical(probe$status, 0L) && !timeout &&
            identical(probe$stderr, "") && closed)
        }
        assert_native(length(complete) == 4L && all(complete), "linux-cli-diagnostics")
      }
      seen$stage = "independent-cli-run"
      cli = gptr:::proc_run(configured, c("-I", "-c", cli_code, library), timeout = 10,
        env = Sys.getenv(), echo = FALSE)
      phase(if (identical(cli$status, 0L)) "cli-exit-zero" else "cli-exit-not-zero")
      phase(if (isTRUE(cli$timed_out)) "cli-timeout" else "cli-no-timeout")
      phase(if (identical(cli$stderr, "")) "cli-stderr-empty" else "cli-stderr-not-empty")
      assert_native(identical(cli$status, 0L) && !cli$timed_out && cli$elapsed <= 11 &&
        identical(cli$stderr, ""), "independent-cli-status")
      assert_native(is.character(cli$stdout) && length(cli$stdout) == 1L && !is.na(cli$stdout) &&
        nchar(cli$stdout, type = "bytes") <= 4096L, "bounded-cli-identity")
      seen$stage = "independent-cli-decode"
      cli_identity = jsonlite::fromJSON(cli$stdout)
      cli_names = c("executable", "prefix", "base_prefix", "version", "library", "sha256",
                    "library_bytes")
      assert_native(is.list(cli_identity) && identical(names(cli_identity), cli_names),
        "closed-cli-identity")
      assert_native(same_path(cli_identity$executable, configured) &&
        same_path(cli_identity$prefix, prefix) &&
        !same_path(cli_identity$prefix, cli_identity$base_prefix), "independent-private-venv")
      assert_native(same_path(cli_identity$library, library) &&
        identical(cli_identity$sha256, library_sha) && cli_identity$library_bytes > 0 &&
        cli_identity$library_bytes <= 64 * 1024^2, "independent-library-hash")
      cli_version_phase("original", cli_identity$version, unname(pins[[1L]]), Sys.getenv())
      assert_native(identical(cli_identity$version, unname(pins[[1L]])), "independent-version")
      cli_state = identical(snapshot(), before)
      seen$stage = "python-first-eval"
      first = gptr::peter$py(paste("copied = sentinel.copy()", "copied.iloc[0, 0] = 99",
        "counter = 41", "counter + 1", sep = "\n"), name = list(sentinel = sentinel))
      after_init = snapshot()
      assert_native(is.null(first$error), "first-python-result")
      first_value = first$value
      seen$stage = "python-second-eval"
      second = gptr::peter$py("counter += 1\ncounter")
      opts = knitr::opts_chunk$merge(list(engine = "python", code = "print(counter)",
        label = "native-gptr-python", echo = FALSE, results = "markup"))
      seen$stage = "python-knitr-eval"
      knitted = knitr::knit_engines$get("python")(opts)
      seen$stage = "python-third-eval"
      third = gptr::peter$py("counter")
      phase("native-numerical-imports")
      seen$stage = "python-import-eval"
      imports = gptr::peter$py(paste(
        "import json, os, sys, struct, math", "import numpy as np, pandas as pd",
        "import numpy._core._multiarray_umath as np_native",
        "import pandas._libs.algos as pd_native", "import numpy.linalg as linear",
        "json.dumps(dict(executable=os.path.abspath(sys.executable), prefix=sys.prefix,",
        " base_prefix=sys.base_prefix, version='.'.join(map(str, sys.version_info[:3])),",
        " bits=struct.calcsize('P') * 8, numpy=np.__version__, pandas=pd.__version__,",
        " numpy_origin=os.path.realpath(np_native.__file__),",
        " pandas_origin=os.path.realpath(pd_native.__file__), total=int(np.array([1,2,3]).sum()),",
        " rows=int(len(pd.DataFrame({'x':[1,2,3]}))), subsequent=int(math.sqrt(49))))",
        sep = "\n"))
      assert_native(is.null(imports$error), "compiled-import-result")
      value = imports$value
      assert_native(is.character(value) && length(value) == 1L && !is.na(value) &&
        nchar(value, type = "bytes") <= 4096L, "bounded-import-identity")
      identity = jsonlite::fromJSON(value)
      expected = c("executable", "prefix", "base_prefix", "version", "bits", "numpy",
                    "pandas", "numpy_origin", "pandas_origin", "total", "rows", "subsequent")
      assert_native(is.list(identity) && identical(names(identity), expected),
                    "closed-import-identity")
      seen$stage = "python-config"
      config = reticulate::py_config()
      versions = list(python = identity$version, numpy = identity$numpy, pandas = identity$pandas,
                      bits = identity$bits)
      # Embedded base_prefix is diagnostic only; reticulate may set PythonHome to the venv.
      seen$stage = "library-stat"
      library_size = file.info(library, extra_cols = FALSE)$size
      library_identity = length(library_size) == 1L && is.finite(library_size) &&
        library_size > 0 && library_size == cli_identity$library_bytes &&
        library_size <= 64 * 1024^2 &&
        is.character(config$libpython) && length(config$libpython) == 1L &&
        !is.na(config$libpython) && file.exists(config$libpython) &&
        same_path(config$libpython, library) && inside(library, cli_identity$base_prefix) &&
        identical(cli::hash_file_sha256(library), library_sha)
      seen$stage = "checks"
      checks = list(native_seed_observed = TRUE,
        first_value = identical(first_value, 42L),
        full_state_after_initialization = identical(after_init, before),
        independent_cli_state = cli_state,
        private_executable = same_path(identity$executable, configured),
        private_prefix = same_path(identity$prefix, prefix),
        private_venv = !same_path(cli_identity$prefix, cli_identity$base_prefix),
        configured_interpreter = same_path(config$python, configured),
        python_version = identical(identity$version, unname(pins[[1L]])),
        numpy_version = identical(identity$numpy, unname(pins[[2L]])),
        pandas_version = identical(identity$pandas, unname(pins[[3L]])),
        compiled_numpy_private = inside(identity$numpy_origin, prefix),
        compiled_pandas_private = inside(identity$pandas_origin, prefix),
        native_library_identity = isTRUE(library_identity),
        numerical_oracles = identical(identity$total, 6L) && identical(identity$rows, 3L) &&
          identical(identity$subsequent, 7L) && identical(identity$bits, 64L),
        persistent_main = is.null(second$error) && is.null(third$error) &&
          identical(second$value, 42L) && identical(third$value, 42L),
        knitr_shared_main = any(grepl("(^|[[:space:]])42([[:space:]]|$)", knitted)),
        user_bytes_unchanged = identical(serialize(sentinel, NULL), bytes),
        repeated_full_state = identical(snapshot(), before),
        no_native_usage = identical(nrow(gptr:::usage_log()), native_usage))
      if (case == "unrelated") checks$unrelated_empty_preserved = seed("GPTR_PY_NATIVE_EMPTY", "")
      if (case == "absent") {
        checks$absent_setup_keys_preserved = !any(toupper(names(Sys.getenv())) %in% absent)
      }
      if (case == "initialized") checks$initialized_empty_preserved = seed("PYTHONIOENCODING", "")
    }
    seen$stage = "finished"
    phase("finished")
    list(schema = "gptr_native_python_startup_v1", case = case, checks = checks,
         observed_check_count = length(checks), versions = versions)
  }
  # Observe fixed phases only; even failed diagnostic publication preserves the original error.
  # The warning handler surrounds the inner function's on.exit cleanup and never muffles.
  result = withCallingHandlers(run(), error = function(error) {
    tryCatch({
      stage = seen$stage
      valid = is.character(stage) && length(stage) == 1L && !is.na(stage) &&
        stage %in% diagnostic_stages
      phase(if (valid) paste0("failure-", stage) else "failure-unknown")
    }, error = function(error) NULL, interrupt = function(interrupt) NULL)
  }, warning = function(warning) {
    seen$total = seen$total + 1L
    if (length(seen$classes) < 16L) {
      seen$classes[[length(seen$classes) + 1L]] =
        intersect(class(warning), c("simpleWarning", "warning", "condition"))
    }
  })
  result$warning_total = seen$total
  result$warning_classes = seen$classes
  result
}

py_native_run = function(case) {
  allowed = c("first", "unrelated", "absent", "empty", "alias", "initialized")
  stopifnot(case %in% allowed, nzchar(Sys.getenv("RETICULATE_PYTHON")),
    identical(Sys.getenv("RETICULATE_USE_MANAGED_VENV"), "false"))
  settings = Sys.getenv(c("RETICULATE_PYTHON", "GPTR_PY_NATIVE_PREFIX",
    "GPTR_PY_NATIVE_VERSION", "GPTR_NP_NATIVE_VERSION", "GPTR_PD_NATIVE_VERSION",
    "GPTR_PY_NATIVE_LIBPYTHON", "GPTR_PY_NATIVE_LIB_SHA256"))
  stopifnot(all(nzchar(settings)), file.exists(settings[[1L]]), dir.exists(settings[[2L]]),
    file.exists(file.path(settings[[2L]], "pyvenv.cfg")))
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = py_native_child
  original_loader = bp_loader
  scope$bp_loader = function() {
    # bp_run starts this script in its exact private root, before the GPTR loader.
    observation = c("(function() {",
      "  present = any(toupper(names(Sys.getenv())) == 'LD_LIBRARY_PATH')",
      "  cat(if (present) 'before-loader-ld-present' else 'before-loader-ld-absent',",
      "    '\\n', file = 'phases.txt', append = TRUE, sep = '')",
      "})()")
    paste(c(observation, original_loader()), collapse = "\n")
  }
  original_env = child_env
  scope$child_env = function(profile, set, ...) {
    # Preserve the watchdog's private dirs/marker/thread caps but never inherit credentials.
    values = c(set, settings, RETICULATE_USE_MANAGED_VENV = "false")
    values = values[!duplicated(toupper(names(values)), fromLast = TRUE)]
    env = original_env("worker", set = values)
    keys = c("VIRTUAL_ENV", "R_SESSION_INITIALIZED", "LD_LIBRARY_PATH",
             "PYTHONPATH", "PYTHONIOENCODING", "GPTR_PY_NATIVE_EMPTY")
    env = env[!toupper(names(env)) %in% keys]
    if (case == "unrelated") env = c(env, GPTR_PY_NATIVE_EMPTY = "")
    if (case == "empty") env = c(env, PYTHONPATH = "")
    if (case == "alias") env = c(env, pythonpath = "")
    if (case == "initialized") env = c(env, PYTHONIOENCODING = "")
    # This COMPLETE vector is handed to processx; no Sys.setenv bridge or callr is involved.
    stopifnot(!anyNA(env), !anyDuplicated(toupper(names(env))))
    env
  }
  runner(case)
}

py_native_expect = function(case) {
  testthat::skip_if_not_installed("reticulate")
  testthat::skip_if_not_installed("knitr")
  if (!nzchar(Sys.getenv("RETICULATE_PYTHON"))) {
    testthat::skip("native Python startup requires an explicitly provisioned runtime")
  }
  # Warm only the assertion formatter, before exact caller-state observations.
  testthat::expect_failure(testthat::expect_identical(1L, 2L))
  withr::local_seed(68017)
  before = list(env = Sys.getenv(), options = options(), cwd = getwd(), libraries = .libPaths(),
    seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
    globals = sort(ls(envir = globalenv(), all.names = TRUE)))
  x = py_native_run(case)
  after = list(env = Sys.getenv(), options = options(), cwd = getwd(), libraries = .libPaths(),
    seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
    globals = sort(ls(envir = globalenv(), all.names = TRUE)))
  expect_identical(after, before)
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_gte(x$samples, 1L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(x$complete, info = paste(x$guard, paste(x$phases, collapse = "/")))
  if (!x$complete) return(invisible(NULL))
  expect_identical(x$result$schema, "gptr_native_python_startup_v1")
  expect_identical(x$result$case, case)
  expect_identical(x$result$warning_total, 0L)
  expect_identical(x$result$warning_classes, list())
  expected = if (case %in% c("empty", "alias")) {
    c("native_seed_observed", "typed_refusal", "still_uninitialized",
      "full_state_after_refusal", "no_native_usage")
  } else {
    c("native_seed_observed", "first_value", "full_state_after_initialization",
      "independent_cli_state", "private_executable", "private_prefix", "private_venv",
      "configured_interpreter",
      "python_version",
      "numpy_version", "pandas_version", "compiled_numpy_private", "compiled_pandas_private",
      "native_library_identity", "numerical_oracles", "persistent_main", "knitr_shared_main",
      "user_bytes_unchanged", "repeated_full_state", "no_native_usage")
  }
  extra = switch(case, unrelated = "unrelated_empty_preserved",
    absent = "absent_setup_keys_preserved", initialized = "initialized_empty_preserved", NULL)
  expect_true(is.list(x$result$checks))
  expect_identical(names(x$result$checks), c(expected, extra))
  expect_identical(length(x$result$checks), x$result$observed_check_count)
  expect_true(!is.null(names(x$result$checks)) && !anyDuplicated(names(x$result$checks)))
  for (name in names(x$result$checks)) expect_identical(x$result$checks[[name]], TRUE, info = name)
  expect_identical(x$inner_identity$pid, x$outer_identity$pid)
  expect_lt(abs(x$inner_identity$create_time - x$outer_identity$create_time), 0.01)
  invisible(x)
}
