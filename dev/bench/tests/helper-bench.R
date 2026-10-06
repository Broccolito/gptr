# Helpers of the development tests of dev/bench (plan P24). From the repository root:
#   Rscript --vanilla -e 'testthat::test_dir("dev/bench/tests")'
# testthat sources this file with the working directory at dev/bench/tests.
source(file.path("..", "common.R"), local = TRUE)
