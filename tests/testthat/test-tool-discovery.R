test_that("gptr APIs are searched from documentation and actual function signatures", {
  hits = peter$search("add mcp server project scope", limit = 30L)
  add = hits[hits$name == "gptr::gptr_mcp_add", , drop = FALSE]
  expect_identical(nrow(add), 1L)
  expect_identical(add$kind, "api")
  expect_match(add$signature, "gptr::gptr_mcp_add(name, command = NULL", fixed = TRUE)
  expect_match(add$signature, "scope = c(\"user\", \"project\")", fixed = TRUE)
  expect_true("gptr::gptr_mcp_remove" %in% peter$search("gptr_mcp_remove")$name)
  expect_true("gptr::gptr_options" %in% peter$search("options control gptr", limit = 50L)$name)
  topics = peter$search("gptr_options", limit = 50L)
  expect_identical(topics$signature[topics$name == "gptr::gptr_options"], "gptr::gptr_options")
  methods = peter$search("gptr_describe.function", limit = 100L)
  expect_identical(methods$signature[methods$name == "gptr::gptr_describe.function"],
                   "gptr::gptr_describe.function")
  expect_false(any(grepl("ns_gptr|member_help", peter$search("member_help", 100L)$name)))
})

test_that("the api index lists names in the same order under any collation", {
  byte_order = ns_gptr_docs()$id
  suppressWarnings(withr::local_collate("en_US.UTF-8"))
  skip_if(identical(sort(c("b", "B")), c("B", "b")), "no locale collation here")
  expect_identical(ns_gptr_docs()$id, byte_order)
})

test_that("gptr help provides a compact index and resolves qualified topics and aliases", {
  index = as.character(peter$help("gptr"))
  expect_match(paste(index, collapse = "\n"), "gptr_mcp_add", fixed = TRUE)
  expect_match(paste(index, collapse = "\n"), "peter$search", fixed = TRUE)
  expect_identical(as.character(peter$help("gptr::gptr_mcp_add")),
                   as.character(peter$help("gptr_mcp_add", package = "gptr")))
  alias = as.character(peter$help("gptr::gptr_mcp_remove"))
  expect_match(alias[1L], "gptr::gptr_mcp_remove", fixed = TRUE)
  expect_match(paste(alias, collapse = "\n"), "scope", fixed = TRUE)
})

test_that("source help returns bounded definitions without exposing namespace objects", {
  public = peter$help("gptr::gptr_api", source = TRUE)
  expect_s3_class(public, "gptr_text")
  expect_true(is.character(public))
  expect_match(paste(public, collapse = "\n"), "function ()", fixed = TRUE)
  internal = peter$help("gptr:::member_help", source = TRUE, budget = 60L)
  expect_match(internal[1L], "source: gptr:::member_help", fixed = TRUE)
  expect_match(paste(internal, collapse = "\n"), "source = FALSE", fixed = TRUE)
  expect_match(tail(as.character(internal), 1L), "more lines")
  expect_lte(est_tokens(as.character(internal), "prose"), 80L)
  expect_match(paste(peter$help("member_help", source = TRUE), collapse = "\n"),
               "gptr:::member_help", fixed = TRUE)
  expect_match(paste(peter$help("gptr:::the", source = TRUE), collapse = "\n"),
               "No function", fixed = TRUE)
  expect_match(paste(peter$help("gptr:::no_such_function", source = TRUE), collapse = "\n"),
               "No function", fixed = TRUE)
  for (empty in c("gptr::", "gptr:::")) {
    expect_match(paste(peter$help(empty, source = TRUE), collapse = "\n"), "No function",
                 fixed = TRUE)
  }
  expect_error(peter$help("gptr_api", source = 1), class = "gptr_error_invalid_argument")
})

test_that("minimal tool declarations teach discovery without loading the API documentation", {
  prompt = gptr_prompt(preset = "minimal")
  expect_match(prompt$tools_json, "peter$search", fixed = TRUE)
  expect_match(prompt$tools_json, "peter$help", fixed = TRUE)
  expect_match(prompt$tools_json, "set up MCP servers, skills or settings in gptr itself",
               fixed = TRUE)
  expect_false(grepl("gptr_mcp_add", paste(prompt$system, collapse = "\n"), fixed = TRUE))
})

test_that("model code can inspect internal source text without accessing namespace objects", {
  local_gw()
  local_fake_provider(list(fake_tool("r", code = paste(
    "found = peter$search('add mcp server project scope')",
    "definition = peter$help('gptr:::perm_check', source = TRUE)", sep = "\n")), "done"))
  home = new.env(parent = baseenv())
  session = peter("Inspect harness APIs", model = "fake", mode = "auto", envir = home)
  expect_identical(session$status, "idle")
  expect_true("gptr::gptr_mcp_add" %in% home$found$name)
  expect_true(is.character(home$definition))
  expect_match(home$definition[1L], "source: gptr:::perm_check", fixed = TRUE)
  expect_match(paste(peter$help("gptr::gptr_mcp_add", source = TRUE), collapse = "\n"),
               "function (name, command = NULL", fixed = TRUE)
})

test_that("installed discovery needs no source checkout", {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  skip_if(dir.exists(file.path(path, "man")), "installed-package acceptance")
  expect_true("gptr::gptr_mcp_add" %in% peter$search("add mcp server", limit = 30L)$name)
  expect_match(paste(peter$help("gptr::gptr_mcp_add"), collapse = "\n"),
               "Streamable HTTP", fixed = TRUE)
  expect_match(paste(peter$help("gptr:::member_help", source = TRUE), collapse = "\n"),
               "source = FALSE", fixed = TRUE)
})
