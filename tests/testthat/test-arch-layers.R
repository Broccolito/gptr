# The layering test (Task 19; architecture section 2.2 rule 4; contract IC-33).

local_arch_sources = function() {
  dir = arch_source_dir()
  if (is.null(dir)) testthat::skip("the package sources under R/ were not found")
  dir
}

test_that("the layer table lists the 119 files of architecture section 3.2", {
  table = arch_layer_table()
  expect_identical(nrow(table), 119L)
  expect_false(anyDuplicated(table$file) > 0)
  expect_true(all(table$layer %in% c("L0", "L1", "L2", "L3", "L4", "L5", "L6", "-")))
  expect_identical(sum(table$plan == "P01"), 15L)
  expect_identical(sum(table$service), 9L)
  expect_identical(table$plan[table$file == "s1-ollama.R"], "P13")
  expect_identical(table$layer[table$file == "s1-ollama.R"], "L4")
})

test_that("every file under R/ has a layer and every function one home", {
  dir = local_arch_sources()
  files = list.files(dir, pattern = "[.][Rr]$")
  expect_identical(setdiff(files, arch_layer_table()$file), character())
  map = arch_fun_map(dir)
  expect_identical(unique(map$fun[duplicated(map$fun)]), character())
})

test_that("internal calls respect the layer table and the kernel SDK (IC-33)", {
  skip_if_not_installed("codetools")
  dir = local_arch_sources()
  bad = arch_check(arch_edges(arch_fun_map(dir)))
  expect(
    nrow(bad) == 0L,
    paste0("layering violations:\n",
           paste0(bad$caller, " (", bad$caller_file, ") -> ", bad$callee, " (",
                  bad$callee_file, ")", collapse = "\n"))
  )
})

test_that("built-in factories call only L0 helpers, their own area and declared services", {
  skip_if_not_installed("codetools")
  dir = local_arch_sources()
  edges = arch_edges(arch_fun_map(dir))
  edges = edges[startsWith(edges$caller, "builtin_"), , drop = FALSE]
  table = arch_layer_table()
  to = table$layer[match(edges$callee_file, table$file)]
  ok = to == "L0" | arch_area(edges$caller_file) == arch_area(edges$callee_file) |
    edges$callee %in% arch_kernel_sdk() | edges$callee_file %in% arch_record_files |
    table$service[match(edges$callee_file, table$file)] |
    arch_contract_ok(edges$caller_file, edges$callee)
  expect_identical(edges$callee[!ok], character())
})

test_that("literal service names are declared in the service table (IC-33)", {
  dir = local_arch_sources()
  used = arch_service_calls(dir)
  expect_identical(setdiff(used$service, names(arch_services())), character())
})

test_that("arch_check() flags calls that cross a boundary (negative controls)", {
  # rows 11-13 are the contract edges of arch_contract_edges(); rows 14-15 show that they are
  # admitted only from the named areas
  edges = data.frame(
    caller = rep("f", 15L),
    caller_file = c("utils-text.R", "tool-read.R", "tool-read.R", "tool-read.R",
                    "gptr-gateway.R", "gptr-gateway.R", "agent-loop.R", "agent-loop.R",
                    "ext-specs.R", "console-repl.R", "ckpt-objects.R", "subagent-team.R",
                    "mcp-server.R", "tool-read.R", "doc-replay.R"),
    callee = c("session_new", "ns_resolve", "eval_capture", "policy_mode", "tool_r_execute",
               "eval_r", "provider_stream", "msg_user", "block_image", "gptr_step",
               "code_targets", "session_new", "session_new", "session_new", "code_targets"),
    callee_file = c("session-object.R", "tool-namespace.R", "eval-core.R", "perm-gate.R",
                    "tool-r.R", "eval-core.R", "provider-registry.R", "provider-message.R",
                    "provider-message.R", "gptr-sdk.R", "perm-classify.R", "session-object.R",
                    "session-object.R", "session-object.R", "perm-classify.R")
  )
  bad = arch_check(edges)
  expect_identical(paste(bad$caller_file, bad$callee), c(
    "utils-text.R session_new", "tool-read.R policy_mode", "gptr-gateway.R tool_r_execute",
    "agent-loop.R provider_stream", "tool-read.R session_new", "doc-replay.R code_targets"
  ))
})
