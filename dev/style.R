# Development helper (not part of the package; `dev/` is excluded by .Rbuildignore).
# styler's default tidyverse_style() rewrites `=` assignments to the left arrow; this variant
# keeps the house style (conventions section 4): `=` for assignment and the native pipe.
#
# Usage from the repository root: source dev/style.R, then pass
# transformers = gptr_style() to styler::style_pkg().
gptr_style = function(...) {
  s = styler::tidyverse_style(...)
  s$token$force_assignment_op = NULL
  s
}
