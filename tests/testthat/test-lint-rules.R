# Package-specific lint rules over R/ (Task 20; contract section 12.3, IC-60, IC-61, IC-62,
# IC-72; conventions sections 4-5). lintr handles style (.lintr); these rules need the parse
# tree. The left arrow is found through getParseData() tokens, never a text regex (IC-72).
# pd_calls(), arch_source_dir() and arch_arrow come from helper-arch.R.

lint_hit = function(file, line, rule, text) {
  data.frame(file = file, line = as.integer(line), rule = rule, text = text)
}

# Rules on single call sites: (file, fun, pkg, parsed call) -> rule id or NA
lint_call_rule = function(file, fun, pkg, call) {
  args = as.list(call)[-1L]
  first_literal = length(args) == 0L || is.character(args[[1L]])
  is_cli = startsWith(fun, "cli_") && pkg %in% c("cli", "") && fun != "cli_verbatim"
  if ((is_cli || (fun == "glue" && pkg %in% c("glue", ""))) && !first_literal) {
    return("cli_literal")
  }
  if (fun %in% c("enquo", "enquos", "quo")) return("quosure")
  if (fun %in% c("lockBinding", "unlockBinding")) return("binding_lock")
  if (pkg == "processx" && fun == "run") return("processx_run")
  if (fun %in% c("serialize", "saveRDS") && file != "utils-paths.R" && !isFALSE(args$ascii)) {
    return("serialize_ascii")
  }
  if (fun %in% c("askYesNo", "menu", "select.list")) return("prompt_fun")
  if (fun == "Sys.setenv" && file != "auth-dotenv.R") return("setenv")
  if (fun %in% c("set.seed", "sample", "runif", "RNGkind")) return("rng")
  if (fun == "randomPort") return("random_port")
  if (fun == "pskill") return("pskill")
  if (fun == "enc2utf8" && file != "utils-encoding.R") return("enc2utf8")
  if (fun %in% c("proc_spawn", "proc_run")) {
    command = if ("command" %in% names(args)) args$command else if (length(args)) args[[1L]]
    if (is.character(command) && command %in% c("R", "Rscript", "R.exe", "Rscript.exe")) {
      return("r_command")
    }
  }
  if (fun == "readLines" && !identical(args$encoding, "UTF-8")) return("readlines_encoding")
  NA_character_
}

# The symbol an assignment target modifies: x, x[[i]], x$a, names(x) -> "x"
lint_target = function(x) {
  while (is.call(x) && length(x) > 1L) x = x[[2L]]
  if (is.name(x) || is.character(x)) as.character(x) else ""
}

lint_mentions_seed = function(x) {
  if (is.name(x) || is.character(x)) return(identical(as.character(x), ".Random.seed"))
  if (!is.call(x)) return(FALSE)
  for (i in seq_along(x)) {
    empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
    if (!empty && lint_mentions_seed(x[[i]])) return(TRUE)
  }
  FALSE
}

# Names a function body assigns with `=` or the left arrow (not inside nested functions) or
# loops over
lint_local_names = function(x) {
  if (!is.call(x)) return(character())
  head = x[[1L]]
  if (identical(head, as.name("function"))) return(character())
  out = character()
  if (identical(head, as.name("=")) || identical(head, arch_arrow)) {
    out = lint_target(x[[2L]])
  }
  if (identical(head, as.name("for"))) out = as.character(x[[2L]])
  for (i in seq_along(x)[-1L]) {
    empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
    if (!empty) out = c(out, lint_local_names(x[[i]]))
  }
  out
}

# `<<-` that does not update a variable of an enclosing function, and .Random.seed assignments
# outside rng_swap() and with_seed_preserved()
lint_scopes = function(path) {
  file = basename(path)
  hits = list()
  walk = function(x, scopes, top) {
    if (!is.call(x)) return(invisible(NULL))
    head = x[[1L]]
    if (identical(head, as.name("function"))) {
      inner = c(names(x[[2L]]), lint_local_names(x[[3L]]))
      walk(x[[3L]], c(scopes, list(inner)), top)
      return(invisible(NULL))
    }
    is_assign = identical(head, as.name("=")) || identical(head, arch_arrow) ||
      identical(head, as.name("<<-"))
    if (identical(head, as.name("<<-"))) {
      outer = unlist(scopes[-length(scopes)])
      if (length(scopes) < 2L || !(lint_target(x[[2L]]) %in% outer)) {
        hits[[length(hits) + 1L]] <<- lint_hit(file, NA, "super_assign", deparse(x)[[1L]])
      }
    }
    seed_calls = c("assign", "rm", "remove", "delayedAssign", "makeActiveBinding")
    seed = (is_assign && lint_mentions_seed(x[[2L]])) ||
      (is.name(head) && as.character(head) %in% seed_calls && lint_mentions_seed(x))
    if (seed && !(top %in% c("rng_swap", "with_seed_preserved"))) {
      hits[[length(hits) + 1L]] <<- lint_hit(file, NA, "random_seed", deparse(x)[[1L]])
    }
    for (i in seq_along(x)[-1L]) {
      empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
      if (!empty) walk(x[[i]], scopes, top)
    }
    invisible(NULL)
  }
  for (e in parse(path, keep.source = FALSE, encoding = "UTF-8")) {
    top = ""
    if (is.call(e) && (identical(e[[1L]], as.name("=")) || identical(e[[1L]], arch_arrow))) {
      top = lint_target(e[[2L]])
    }
    walk(e, list(), top)
  }
  hits
}

# Every rule over the given files: df(file, line, rule, text)
lint_scan = function(paths) {
  hits = list()
  for (path in paths) {
    file = basename(path)
    bytes = readBin(path, "raw", file.size(path))
    bad = which(bytes > as.raw(0x7f))
    if (length(bad)) {
      line = sum(bytes[seq_len(bad[[1L]])] == as.raw(0x0a)) + 1L
      hits[[length(hits) + 1L]] = lint_hit(file, line, "non_ascii", "non-ASCII byte")
    }
    pd = utils::getParseData(parse(path, keep.source = TRUE, encoding = "UTF-8"))
    token_rules = list(
      ns_get_int = pd$token == "NS_GET_INT",
      globalenv_sym = pd$token == "SYMBOL" & pd$text == ".GlobalEnv",
      magrittr = pd$token == "SPECIAL" & pd$text == paste0("%", ">%"),
      left_assign = (pd$token == "LEFT_ASSIGN" & pd$text == as.character(arch_arrow)) |
        pd$token == "RIGHT_ASSIGN",
      withr = pd$token == "SYMBOL_PACKAGE" & pd$text == "withr"
    )
    for (rule in names(token_rules)) {
      rows = pd[token_rules[[rule]], ]
      for (i in seq_len(nrow(rows))) {
        hits[[length(hits) + 1L]] = lint_hit(file, rows$line1[[i]], rule, rows$text[[i]])
      }
    }
    calls = pd_calls(path)
    for (i in seq_len(nrow(calls))) {
      rule = lint_call_rule(file, calls$fun[[i]], calls$pkg[[i]], str2lang(calls$text[[i]]))
      if (!is.na(rule)) {
        hits[[length(hits) + 1L]] = lint_hit(file, calls$line[[i]], rule, calls$text[[i]])
      }
    }
    hits = c(hits, lint_scopes(path))
  }
  if (!length(hits)) return(lint_hit(character(), integer(), character(), character()))
  do.call(rbind, hits)
}

test_that("R/ follows the package lint rules (contract section 12.3, IC-72)", {
  dir = arch_source_dir()
  skip_if(is.null(dir), "the package sources under R/ were not found")
  hits = lint_scan(list.files(dir, pattern = "[.][Rr]$", full.names = TRUE))
  expect(
    nrow(hits) == 0L,
    paste0("lint rule violations:\n",
           paste0(hits$file, ":", hits$line, " [", hits$rule, "] ", hits$text, collapse = "\n"))
  )
})

test_that("each lint rule catches its violation (negative controls)", {
  dir = withr::local_tempdir()
  bad = c(
    "f01 = function() gptr:::the",
    "f02 = function(x) rlang::enquo(x)",
    "f03 = function(x) cli::cli_text(x)",
    "f04 = function() .GlobalEnv",
    "f05 = function(e) lockBinding(\"x\", e)",
    "f06 = function() processx::run(\"ls\")",
    "f07 = function(x) saveRDS(x, \"f.rds\")",
    paste0("f08 = function() {\n  x <", "- 1\n  x\n}"),
    "f09 = function() {\n  total <<- 1\n}",
    paste0("f10 = function(x) x %", ">% sum()"),
    "f11 = function() utils::askYesNo(\"ok?\")",
    "f12 = function() Sys.setenv(A = \"1\")",
    "f13 = function() stats::runif(1)",
    "f14 = function(env) {\n  env[[\".Random.seed\"]] = 1L\n}",
    "f15 = function() httpuv::randomPort()",
    "f16 = function(p) tools::pskill(p)",
    "f17 = function(x) enc2utf8(x)",
    "f18 = function() withr::local_tempdir()",
    "f19 = function() proc_spawn(\"Rscript\", \"-e\")",
    "f20 = function(p) readLines(p)",
    "f21 = function() \"caf\u00e9\""
  )
  path = file.path(dir, "demo-bad.R")
  writeBin(charToRaw(enc2utf8(paste(bad, collapse = "\n"))), path)
  hits = lint_scan(path)
  expect_setequal(hits$rule, c(
    "ns_get_int", "quosure", "cli_literal", "globalenv_sym", "binding_lock", "processx_run",
    "serialize_ascii", "left_assign", "super_assign", "magrittr", "prompt_fun", "setenv", "rng",
    "random_seed", "random_port", "pskill", "enc2utf8", "withr", "r_command",
    "readlines_encoding", "non_ascii"
  ))
  expect_identical(hits$line[hits$rule == "left_assign"], 9L)
})

test_that("the file and function exemptions of the rules hold", {
  dir = withr::local_tempdir()
  writeLines(c(
    "save_rds = function(object, file) saveRDS(object, file, ascii = FALSE, compress = FALSE)",
    "raw_rds = function(object, file) saveRDS(object, file)"
  ), file.path(dir, "utils-paths.R"))
  writeLines("as_native = function(x) enc2utf8(x)", file.path(dir, "utils-encoding.R"))
  writeLines("env_set = function() Sys.setenv(A = \"1\")", file.path(dir, "auth-dotenv.R"))
  writeLines(c(
    "with_seed_preserved = function(expr) {",
    "  env = globalenv()",
    "  on.exit({",
    "    env[[\".Random.seed\"]] = 1L",
    "  }, add = TRUE)",
    "  expr",
    "}",
    "quiet = function(x) cli::cli_verbatim(x)",
    "lines = function(p) readLines(p, encoding = \"UTF-8\")",
    "leaf = function(x) serialize(x, NULL, ascii = FALSE)"
  ), file.path(dir, "demo-good.R"))
  # A replacement method: a text regex would flag the arrow inside its name (IC-72)
  writeLines(
    paste0("`$<", "-.gptr_demo` = function(x, name, value) stop(\"read-only\")"),
    file.path(dir, "demo-method.R")
  )
  hits = lint_scan(list.files(dir, full.names = TRUE))
  expect_identical(nrow(hits), 0L)
})

test_that("S3 methods of Suggests generics and closure state pass (IC-72, acceptance 7)", {
  fixture = testthat::test_path("fixtures", "lint", "s3-methods.R")
  expect_identical(nrow(lint_scan(fixture)), 0L)
})
