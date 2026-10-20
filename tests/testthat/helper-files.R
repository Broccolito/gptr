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

# A link at `path` to its missing sibling "absent": a symlink, on Windows a junction (no privilege
# needed; R's stat() still succeeds on it) detached at teardown, as R's recursive unlink() of its
# directory may fail on a dangling junction
local_dangling_link = function(path, .env = parent.frame()) {
  target = file.path(dirname(path), "absent")
  if (!is_windows()) return(testthat::expect_true(file.symlink(target, path)))
  testthat::expect_true(dir.create(target))
  withr::defer(unlink(path), envir = .env)
  testthat::expect_true(base::Sys.junction(target, path))
  testthat::expect_identical(unlink(target, recursive = TRUE), 0L)
}
