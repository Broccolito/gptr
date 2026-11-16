# Step 1 on a byte-compiled install of the local source (R CMD INSTALL into the work folder); otherwise as step1-minimal.R
# instead of installing from GitHub; the rest kept (4M synthetic IDs, served `r` call from a
# before_request hook, outer vs internal elapsed). Prints one CSV row per run.
W = "/private/tmp/claude-501/-Users-wgu--claude-spares-spare-n02ZLD/6fb98ae7-bd14-4c28-8b44-cc52b94423a1/scratchpad/work/gate-measure"
main = function() {
  work = tempfile("gptr-minimal-", tmpdir = file.path(W, "tmp"))
  dir.create(work, recursive = TRUE)
  original_directory = getwd()
  on.exit({
    setwd(original_directory)
    unlink(work, recursive = TRUE)
  }, add = TRUE)
  setwd(work)
  Sys.setenv(R_USER_CONFIG_DIR = work, R_USER_DATA_DIR = work, R_USER_CACHE_DIR = work, GPTR_PROJECT_ROOT = work)
  library(gptr, lib.loc = file.path(W, "lib"))
  options(gptr.quiet = TRUE, gptr.interactive = FALSE, gptr.project_root = work)
  data.table::setDTthreads(1)
  home = new.env()
  home$x = sprintf("gene_%08d", seq_len(4000000))
  s = peter("Strip digits from existing IDs and count the remaining characters", model = gptr_fake_provider("Done"),
    envir = home, mode = "auto", tools = "minimal", .run = FALSE)
  started = 0
  out = new.env()
  gptr_on(s, "tool_execution_start", function(event, ctx) {
    started <<- proc.time()[["elapsed"]]
  })
  gptr_on(s, "tool_execution_end", function(event, ctx) {
    outer = proc.time()[["elapsed"]] - started
    out$row = data.frame(outer_s = outer, internal_s = event$elapsed,
      gap_s = outer - event$elapsed, ratio = outer / event$elapsed, error = event$is_error)
  })
  gptr_on(s, "before_request", function(event, ctx) {
    gptr:::mcp_dispatch_local(list(jsonrpc = "2.0", id = 1L, method = "tools/call",
      params = list(name = "r", arguments = list(
        code = 'if (!exists("x")) x = NULL; sum(nchar(gsub("[0-9]", "", x)))'))), ctx$session)
    NULL
  })
  invisible(gptr_wait(s))
  out$row
}
r = main()
r$run = Sys.getenv("RUN_ID")
write.table(r, stdout(), sep = ",", row.names = FALSE, col.names = Sys.getenv("RUN_ID") == "1")
