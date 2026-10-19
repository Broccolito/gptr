# Test helpers of the P10 file tools.

# Write `content` (text or raw bytes) to `root/rel`, creating directories; returns the path
put_file = function(root, rel, content = "x\n") {
  p = fs_path(file.path(root, rel))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.raw(content)) content else charToRaw(content), p)
  p
}

# A true symbolic link; on Windows wsec_link() checks its reparse tag and detaches it at teardown
# (it starts native utilities, so it skips on CRAN there)
local_symlink = function(target, link, .env = parent.frame()) {
  if (!is_windows()) return(testthat::expect_true(file.symlink(target, link)))
  testthat::skip_on_cran()
  wsec_link(target, link, .env = .env)
}
