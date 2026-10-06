# Test helpers of the P10 file tools.

# Write `content` (text or raw bytes) to `root/rel`, creating directories; returns the path
put_file = function(root, rel, content = "x\n") {
  p = fs_path(file.path(root, rel))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.raw(content)) content else charToRaw(content), p)
  p
}
