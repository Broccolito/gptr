# Native Python startup, observed from an independent processx/Rscript watchdog.
# No Python initialization or caller environment mutation occurs in the supervising R process.
py_native_child = function(case, root, failure) {
  seen = new.env(parent = emptyenv())
  seen$total = 0L
  seen$classes = list()
  run = function() {
    phase = function(text) {
      cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE, sep = "")
    }
    assert_native = function(value, stage) {
      if (!isTRUE(value)) stop(paste("Native Python fixture failed:", stage), call. = FALSE)
      invisible(TRUE)
    }
    phase("entered")
    file.create(file.path(root, "case-started"))
    handle = ps::ps_handle()
    saveRDS(list(pid = Sys.getpid(), create_time = as.numeric(ps::ps_create_time(handle))),
            file.path(root, "inner-identity.rds"))
    assert_native(requireNamespace("reticulate", quietly = TRUE), "reticulate-required")
    assert_native(requireNamespace("knitr", quietly = TRUE), "knitr-required")
    assert_native(requireNamespace("jsonlite", quietly = TRUE), "json-required")
    assert_native(!reticulate::py_available(initialize = FALSE), "fresh-python")
    assert_native(identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"), "offline")
    assert_native(identical(Sys.getenv("RETICULATE_USE_MANAGED_VENV"), "false"), "managed-disabled")
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
    seed = function(name, value, exact_name = FALSE) {
      raw = Sys.getenv()
      hits = which(toupper(names(raw)) == toupper(name))
      length(hits) == 1L && identical(unname(raw[hits]), value) &&
        (!exact_name || identical(names(raw)[hits], name))
    }
    keys = c("PATH", "VIRTUAL_ENV", "R_SESSION_INITIALIZED", "LD_LIBRARY_PATH",
             "PYTHONPATH", "PYTHONIOENCODING")
    absent = setdiff(keys, "PATH")
    if (case == "absent") {
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
    before = snapshot()
    native_usage = nrow(gptr:::usage_log())
    versions = NULL
    phase("gptr-first-call")
    if (case %in% c("empty", "alias")) {
      condition = tryCatch(gptr::peter$py("41 + 1"), error = identity)
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
      cli = gptr:::proc_run(configured, c("-I", "-c", cli_code, library), timeout = 10,
        env = Sys.getenv(), echo = FALSE)
      assert_native(identical(cli$status, 0L) && !cli$timed_out && cli$elapsed <= 11 &&
        identical(cli$stderr, ""), "independent-cli-status")
      assert_native(is.character(cli$stdout) && length(cli$stdout) == 1L && !is.na(cli$stdout) &&
        nchar(cli$stdout, type = "bytes") <= 4096L, "bounded-cli-identity")
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
      assert_native(identical(cli_identity$version, unname(pins[[1L]])), "independent-version")
      cli_state = identical(snapshot(), before)
      first = gptr::peter$py(paste("copied = sentinel.copy()", "copied.iloc[0, 0] = 99",
        "counter = 41", "counter + 1", sep = "\n"), name = list(sentinel = sentinel))
      after_init = snapshot()
      assert_native(is.null(first$error), "first-python-result")
      first_value = first$value
      second = gptr::peter$py("counter += 1\ncounter")
      opts = knitr::opts_chunk$merge(list(engine = "python", code = "print(counter)",
        label = "native-gptr-python", echo = FALSE, results = "markup"))
      knitted = knitr::knit_engines$get("python")(opts)
      third = gptr::peter$py("counter")
      phase("native-numerical-imports")
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
      config = reticulate::py_config()
      versions = list(python = identity$version, numpy = identity$numpy, pandas = identity$pandas,
                      bits = identity$bits)
      # Embedded base_prefix is diagnostic only; reticulate may set PythonHome to the venv.
      library_size = file.info(library, extra_cols = FALSE)$size
      library_identity = length(library_size) == 1L && is.finite(library_size) &&
        library_size > 0 && library_size == cli_identity$library_bytes &&
        library_size <= 64 * 1024^2 &&
        is.character(config$libpython) && length(config$libpython) == 1L &&
        !is.na(config$libpython) && file.exists(config$libpython) &&
        same_path(config$libpython, library) && inside(library, cli_identity$base_prefix) &&
        identical(cli::hash_file_sha256(library), library_sha)
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
    phase("finished")
    list(schema = "gptr_native_python_startup_v1", case = case, checks = checks,
         observed_check_count = length(checks), versions = versions)
  }
  # The handler surrounds the inner function's on.exit cleanup too. Never muffle warnings
  # or publish diagnostics during an error unwind: the original condition must propagate.
  result = withCallingHandlers(run(), warning = function(warning) {
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
