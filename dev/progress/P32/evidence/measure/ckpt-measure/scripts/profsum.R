# Summarise Rprof files: top self and total functions, and the share under checkpoint_before/after.
# Usage: Rscript --vanilla profsum.R <out.txt> <file.Rprof> ...
a = commandArgs(TRUE)
out = a[1]
sink(out)
for (f in a[-1]) {
  cat("\n#####", basename(f), "\n")
  sp = tryCatch(summaryRprof(f), error = function(e) NULL)
  if (is.null(sp) || !length(sp$sampling.time)) { cat("(no samples)\n"); next }
  cat("sampling.time:", sp$sampling.time, "s\n")
  print(utils::head(sp$by.self, 15))
  bt = sp$by.total
  keep = rownames(bt) %in% c('"checkpoint_before"', '"checkpoint_after"', '"ckpt_objects_before"',
    '"ckpt_objects_after"', '"ckpt_files_before"', '"ckpt_files_after"', '"env_snapshot"',
    '"env_snap_size"', '"env_size_strings"', '"unique.default"', '"ckpt_scan_run"',
    '"ckpt_settle_row"', '"ckpt_capture"', '"ckpt_preimage_modes"', '"fingerprint"',
    '"env_snap_facts"', '"ckpt_write_image"', '"serialize_leaf"', '"write_atomic"',
    '"ckpt_store_put"', '"path_class"', '"path_info"', '"ckpt_is_link"', '"ckpt_regular"',
    '"mcp_serve_gate"', '"mcp_serve_r"', '"mcp_serve_exec"', '"perm_check"', '"risk_binding_info"',
    '"ckpt_unshared_bytes"', '"id_new"', '"ckpt_addr"', '"ckpt_settle"', '"env_shape"',
    '"ckpt_files_sync"', '"ckpt_files_step"', '"hash_file"', '"walk_list_dir"', '"ignore_eval"',
    '"ckpt_on_agent_end"', '"ckpt_objects_budget"', '"ckpt_spill"', '"[.data.frame"', '"match"',
    '"tryCatch"', '"data.frame"', '"rbind"', '"cli::hash_sha256"', '"rlang::obj_address"')
  cat("-- selected by.total --\n")
  print(bt[keep, , drop = FALSE])
  cat("-- top by.total --\n")
  print(utils::head(bt, 30))
}
sink()
