# Nominated on provisioned Windows only. No capability or platform skip is allowed.
test_that("owned held-disabled token proves the strict native absence oracle", {
  expect_identical(.Platform$OS.type, "windows")
  packet = Sys.getenv("GPTR_HELD_TOKEN_PACKET")
  stopifnot(nzchar(packet), dir.exists(packet),
    identical(Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"), "true"))
  packet = normalizePath(packet, winslash = "/", mustWork = TRUE)
  scope = new.env(parent = asNamespace("gptr"))
  for (name in c("helper-proc-backpressure.R", "helper-bp-disk-observer.R")) {
    sys.source(file.path(packet, "baseline", name), envir = scope)
  }
  sys.source(file.path(packet, "amended", "helper-proc-writer-runtime.R"), envir = scope)
  sys.source(file.path(packet, "token-held-protocol.R"), envir = scope)
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
  x = scope$rw_held_token_run(packet)
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
  tokens = x$phases[startsWith(x$phases, "GPTR_HELD ")]
  expect_length(tokens, 7L)
  if (length(tokens) == 7L) {
    diagnostic = scope$token_held_decode(tokens)
    expect_true(diagnostic$disabled_exact)
    expect_true(diagnostic$body_finished)
    expect_true(diagnostic$restored_exact)
    expect_true(diagnostic$handle_closed)
    expect_false(diagnostic$individual_privilege_identified)
    expect_false(diagnostic$restored_privilege_denial_proved)
  }
  # This remains the original positive feature requirement; diagnostics cannot waive it.
  expect_true(x$complete)
  if (isTRUE(x$complete)) {
    expect_true(x$result$restored)
    expect_true(x$result$sentinels_unchanged)
    expect_true(x$result$entries_removed)
  }
})
