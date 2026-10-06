# Helpers of the release self-tests (plan P25). From the repository root:
#   Rscript --vanilla -e 'testthat::test_dir("dev/release/tests")'
# testthat sources this file with the working directory at dev/release/tests.
source(file.path("..", "lib.R"), local = TRUE)

# A toy Rd page in the shape roxygen2 7.3.3 writes.
rd_page = function(name, aliases = name, value = "A value.", examples = "f(1)", extra = character(),
                   keywords = character()) {
  c(sprintf("\\name{%s}", name), sprintf("\\alias{%s}", aliases),
    sprintf("\\title{Title of %s}", name), "\\description{Description.}",
    if (!is.null(value)) sprintf("\\value{%s}", value), extra,
    if (!is.null(examples)) c("\\examples{", examples, "}"),
    sprintf("\\keyword{%s}", keywords))
}

# roxygen2's rendering of `@examplesIf <pred>` followed by `code`.
rd_examples_if = function(pred, code) {
  c(sprintf("\\dontshow{if (%s) withAutoprint(\\{ # examplesIf}", pred), code,
    "\\dontshow{\\}) # examplesIf}")
}

# Writes the toy pages (name = lines) into a new man directory and returns its path.
toy_man = function(pages) {
  dir = tempfile("man")
  dir.create(dir)
  for (nm in names(pages)) writeLines(pages[[nm]], file.path(dir, paste0(nm, ".Rd")))
  dir
}

# The repository root for the test-gptr-*.R files, which skip outside the gptr repository.
gptr_root = function() {
  root = normalizePath(file.path("..", "..", ".."), winslash = "/", mustWork = FALSE)
  desc = file.path(root, "DESCRIPTION")
  is_gptr = file.exists(desc) && identical(unname(read.dcf(desc)[1L, "Package"]), "gptr")
  testthat::skip_if_not(is_gptr, "not inside the gptr repository")
  root
}

# Passes when `problems` is empty; otherwise fails and lists every problem.
expect_no_problems = function(problems) {
  if (length(problems)) {
    testthat::fail(paste(c("open problems:", paste0("  ", problems)), collapse = "\n"))
  } else {
    testthat::succeed()
  }
  invisible(problems)
}
