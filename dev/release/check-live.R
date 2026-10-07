# Checks a live calibration record against IC-73 (plan P25, Task 14); the maintainer writes it with
# P24's dev/bench/tokens/live.R and real keys. Usage, from the repository root:
#   Rscript --vanilla dev/release/check-live.R [dev/bench/tokens/live-YYYY-MM-DD.csv]
# Without an argument it checks today's file.
source(file.path("dev", "release", "lib.R"))
args = commandArgs(trailingOnly = TRUE)
path = if (length(args)) args[1L] else live_file_name()
if (!file.exists(path)) {
  stop("no calibration file ", path, "; run dev/bench/tokens/live.R first", call. = FALSE)
}
live = utils::read.csv(path)
writeLines(sprintf("check-live: %s, %d rows, models %s", path, nrow(live),
                   paste(unique(live$model), collapse = ", ")))
rel_finish("check-live", live_problems(live))
