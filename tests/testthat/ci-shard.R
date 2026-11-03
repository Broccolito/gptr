# CI sets GPTR_CI_TEST_SHARD to "i/n": the n shards split the test files so that each takes about
# the same time on this OS (on Windows the ordinary files; only shard 1 runs the native fixtures).
# Unset, every check is shard 1/1: the whole suite.
ci_shard = function(selector = Sys.getenv("GPTR_CI_TEST_SHARD", "1/1")) {
  stopifnot(grepl("^[1-9][0-9]*/[1-9][0-9]*$", selector))
  shard = as.integer(strsplit(selector, "/", fixed = TRUE)[[1L]])
  stopifnot(shard[[1L]] <= shard[[2L]])
  shard
}

# Seconds each test file took in CI's shards on each OS: medians of up to four runs on 2026-11-03,
# read from the progress reporter's times. A file not listed counts 1 s; update the table when a
# lane's shards drift apart.
ci_shard_seconds = utils::read.csv(row.names = 1L, text = "file,linux,macos,windows
aaa-state,40,38,57
agent-background,32,21,27
agent-dispatch,44,39,49
agent-loop,15,11,13
agent-run,31,40,52
arch-layers,33,49,49
artifact-app,46,71,77
artifact-browser-cleanup,2,2,4
artifact-browser-launch,4,5,5
artifact-browser-owner,4,4,8
artifact-registry,24,26,30
auth-childenv,2,2,3
auth-oauth,6,6,8
auth-redact,21,24,49
auth-secrets,3,3,4
auth-setup,2,2,3
bench-context,1,2,2
bp-disk-observer,1,1,4
bridge-lang,10,8,11
bridge-lang-init-env,2,2,2
bridge-sh,63,88,119
catalog-models,9,8,14
ckpt-files,8,6,9
ckpt-objects,8,3,5
ckpt-partial,1,1,2
ckpt-rewind,37,25,50
ckpt-scan,2,2,5
ckpt-scan-integration,28,23,108
cli-claude,40,48,74
cli-claude-result,8,4,7
cli-codex,51,63,92
cli-common,10,9,10
compaction-acceptance,15,21,38
compaction-wait,9,5,12
console-abort-stream,3,3,4
console-commands,12,10,17
console-completion,15,8,2
console-fences,7,6,9
console-input,2,1,3
console-interrupt,35,30,13
console-jsonl,3,3,5
console-jupyter-progress,2,1,2
console-message-stream,2,3,4
console-notice,1,3,1
console-render,86,68,89
console-repl,53,36,26
console-setup,2,1,2
console-subagents,40,35,10
console-typing,301,216,77
console-ui,16,15,17
console-wait,2,2,2
context-prefix,12,9,14
copy-artifact,8,3,3
copy-bridge,25,10,12
copy-ckpt,85,33,30
copy-eval,94,28,32
copy-gateway,145,52,77
copy-s1,16,5,6
copy-subagent,102,14,19
copy-tools,49,14,13
doc-blocks,10,12,20
doc-coach,4,3,6
doc-export,6,6,11
doc-formats,4,2,5
doc-io,100,25,121
doc-jupyter,1,2,1
doc-knitr,20,9,13
doc-locate,3,3,5
doc-replay,82,107,182
env-describe,2,2,3
env-history,4,2,3
env-snapshot,3,4,5
eval-core,16,13,19
eval-format,1,1,4
eval-guard,2,2,2
eval-plots,1,1,4
ext-api,1,1,2
ext-check,4,4,9
ext-events,1,1,2
ext-load,2,2,2
ext-plugins,8,6,15
ext-registry,1,1,2
ext-specs,2,1,2
gptr-capture,8,7,12
gptr-child,63,34,56
gptr-coach,81,66,91
gptr-config,6,5,18
gptr-gateway,58,60,92
gptr-sdk,7,8,17
gptr-tailor,20,24,32
http-reactor,25,27,49
http-request,64,64,71
http-retry,37,43,72
http-sse,4,4,5
injection-e2e,66,42,65
json-partial,1,2,4
lint-rules,11,10,14
mcp-client,38,37,53
mcp-config,6,4,10
mcp-namespace,9,10,23
mcp-recording,4,5,8
mcp-server,25,33,49
mcp-stop-rng,1,1,2
mcp-waits,7,9,10
northstar,19,24,34
perm-classify,29,23,51
perm-gate,52,38,86
perm-plan,6,6,9
perm-rules,2,3,8
proc-backpressure-sampling,9,12,14
proc-marker-family,2,4,1
proc-rscript-native,17,8,1
proc-spawn,18,20,26
proc-supervise,6,6,8
proc-windows-backpressure,32,30,1
proc-writer-prototype,14,12,1
proc-writer-runtime,3,3,1
prompt-cache,2,2,4
prompt-compact,11,7,18
prompt-context,2,2,4
prompt-sections,11,8,16
provider-anthropic,11,13,25
provider-bedrock,13,12,15
provider-events,2,2,2
provider-fake,25,25,58
provider-google,1,1,4
provider-model-discovery,2,1,2
provider-openai-completions,3,2,5
provider-openai-responses,2,2,5
provider-registry,8,7,22
provider-usage,2,2,3
risk-forms,14,13,40
s1-client,10,7,13
s1-composition,90,67,123
s1-emulate,3,2,7
s1-ollama,5,5,10
s1-route,18,12,26
s1-types,1,1,2
s11-conformance,4,5,11
secrets-e2e,58,14,40
session-budget,4,4,7
session-history-display,1,2,1
session-live,21,12,31
session-object,18,18,37
session-registry-retention,11,12,14
session-store,72,82,100
session-usage-durable,9,8,13
skill-discover,6,5,11
skill-templates,2,2,4
storage-boundaries,2,2,13
stream-order,4,2,9
subagent-backends,69,27,42
subagent-defs,1,2,4
subagent-team,76,76,120
subagent-worker,63,20,1
tool-diff,5,4,10
tool-discovery,4,3,4
tool-edit,2,1,4
tool-namespace,10,9,18
tool-r,4,4,9
tool-read,1,1,2
tool-search,4,4,5
tool-walk,1,1,3
utils-encoding,3,2,5
utils-hash,18,6,8
utils-paths,2,3,8
utils-text,2,1,3
windows-security,1,1,13
zzz,1,1,2
")

# Seconds shard 1 spends besides its files: on macOS the vignettes and examples the other shards
# skip, on Windows the native fixtures
ci_shard_head = c(linux = 0, macos = 115, windows = 170)

ci_shard_os = function() {
  switch(Sys.info()[["sysname"]], Darwin = "macos", Windows = "windows", "linux")
}

# Shard i's files: the slowest file first, each goes to the shard with the least time so far
# (shard 1 starts with its head start), so files of equal time take turns in name order
ci_shard_files = function(files, shard = ci_shard(), os = ci_shard_os()) {
  stopifnot(shard[[2L]] <= length(files))
  files = sort(files)
  seconds = ci_shard_seconds[[os]][match(ci_shard_names(files), rownames(ci_shard_seconds))]
  seconds[is.na(seconds)] = 1
  load = numeric(shard[[2L]])
  load[[1L]] = ci_shard_head[[os]]
  owner = integer(length(files))
  for (i in order(-seconds)) {
    owner[[i]] = which.min(load)
    load[[owner[[i]]]] = load[[owner[[i]]]] + seconds[[i]]
  }
  files[owner == shard[[1L]]]
}

ci_shard_names = function(files) sub("[.][rR]$", "", sub("^test[-_]", "", files))

# The testthat filter that selects exactly these test files
ci_shard_filter = function(files) {
  names = ci_shard_names(files)
  stopifnot(all(grepl("^[A-Za-z0-9_-]+$", names)), !anyDuplicated(names))
  paste0("^(", paste(names, collapse = "|"), ")$")
}
