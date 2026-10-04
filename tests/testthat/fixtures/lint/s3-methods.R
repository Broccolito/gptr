# Lint fixture (IC-72): the S3 methods later plans define for Suggests generics and closure
# state updated with `<<-`. lintr::lint_package() and test-lint-rules.R must
# accept this file unchanged.

.DollarNames.gptr_session = function(x, pattern = "") {
  grep(pattern, c("text", "value", "usage"), value = TRUE)
}

knit_print.gptr_session = function(x, ...) {
  "a gptr session"
}

vec_proxy.gptr_s1 = function(x, ...) {
  unclass(x)
}

make_counter = function() {
  count = 0L
  function() {
    count <<- count + 1L
    count
  }
}
