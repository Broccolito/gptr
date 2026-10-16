# Nominated on provisioned Windows only. No capability or platform skip is allowed.
test_that("owned-token A-B-A retains the strict native absence oracle", {
  expect_identical(.Platform$OS.type, "windows")
  packet = Sys.getenv("GPTR_TOKEN_EXPERIMENT_PACKET")
  stopifnot(nzchar(packet), dir.exists(packet),
    identical(Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"), "true"))
  packet = normalizePath(packet, winslash = "/", mustWork = TRUE)
  scope = new.env(parent = asNamespace("gptr"))
  for (name in c("helper-proc-backpressure.R", "helper-bp-disk-observer.R")) {
    sys.source(file.path(packet, "baseline", name), envir = scope)
  }
  sys.source(file.path(packet, "amended", "helper-proc-writer-runtime.R"), envir = scope)
  sys.source(file.path(packet, "token-protocol.R"), envir = scope)
  observer = get("bp_disk_observer", scope, inherits = FALSE)
  scanner = file.path(packet, "baseline", "fixtures", "bp-disk-observer.py")
  scope$bp_disk_observer = function(root, declarations = list()) {
    observer(root, declarations = declarations, source = scanner)
  }
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  snapshot = function() list(env = Sys.getenv(), options = options(), cwd = getwd(),
    libs = .libPaths(), kind = RNGkind(), seed = seed(),
    globals = sort(ls(envir = globalenv(), all.names = TRUE)))
  canary = list(bytes = charToRaw("PUBLIC-TOKEN-INPUT"), data = data.frame(x = 1:4))
  original = serialize(canary, NULL, version = 2)
  before = snapshot()
  x = scope$rw_token_run(packet)
  after = snapshot()
  expect_true(identical(before, after))
  expect_identical(serialize(canary, NULL, version = 2), original)
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_gte(x$samples, 1L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
  expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
  expect_true(is.list(x$disk_observer))
  expect_lte(x$disk_observer$peak_combined_rss, 1024^3)
  expect_true("GPTR-TOKEN-COMPILED-10" %in% x$phases)
  expect_true("absence-compiler-settled-1" %in% x$phases)
  compiler = grep("^token-compiler-identity-[0-9]+-[0-9]+\\.[0-9]{6}$",
    x$phases, value = TRUE)
  expect_length(compiler, 1L)
  for (family in c("compiler", "main", "recovery")) {
    times = grep(paste0("^absence-", family, "-elapsed-ms-[0-9]+$"), x$phases,
      value = TRUE)
    expect_length(times, 1L)
    if (length(times) == 1L) {
      elapsed = as.double(sub(".*-", "", times))
      expect_lte(elapsed, if (family == "compiler") 30000 else 5000)
    }
  }
  expect_true("absence-main-settled-1" %in% x$phases)
  expect_true("absence-recovery-settled-1" %in% x$phases)
  expect_false(any(x$phases %in% c("token-protocol-failed", "token-unexpected-stderr")))
  tokens = x$phases[startsWith(x$phases, "GPTR_TOKEN ")]
  expect_length(tokens, 26L)
  if (length(tokens) == 26L) {
    diagnostic = scope$token_trial_decode(tokens)
    expect_identical(dim(diagnostic$records), c(3L, 8L))
    expect_false(diagnostic$individual_privilege_identified)
    expect_false(diagnostic$feature_accepted)
    # The fixed phase reports only group contribution, not a package fix.
    expect_true(paste0("token-group-contribution-",
      as.integer(diagnostic$group_contribution)) %in% x$phases)
  }
  # This remains the original positive feature requirement; diagnostics cannot waive it.
  expect_true(x$complete)
  if (isTRUE(x$complete)) {
    expect_true(x$result$restored)
    expect_true(x$result$sentinels_unchanged)
    expect_true(x$result$entries_removed)
  }
})
