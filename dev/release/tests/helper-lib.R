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
