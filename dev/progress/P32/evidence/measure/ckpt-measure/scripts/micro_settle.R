# Decompose the per-binding loop of ckpt_objects_after() (ckpt_settle_row) at n bindings
n = as.integer(commandArgs(TRUE)[1])
clock = function() as.numeric(proc.time()[["elapsed"]])
nm = sprintf("o%05d", seq_len(n))
snap = data.frame(name = nm, kind = "value", address = sprintf("0x%010x", seq_len(n)), class = "numeric",
                  bytes = 176, shape = "length 10", fp = sprintf("%064d", seq_len(n)))
post = snap
t0 = clock(); for (i in seq_len(n)) s0 = snap[i, , drop = FALSE]; t_row = clock() - t0
t0 = clock(); for (i in seq_len(n)) j = match(nm[i], post$name); t_match = clock() - t0
t0 = clock(); for (i in seq_len(n)) { a = post$address[i]; b = post$fp[i] }; t_dollar = clock() - t0
f = compiler::cmpfun(function() for (i in seq_len(n)) j = match(nm[i], post$name))
t0 = clock(); f(); t_match_cmp = clock() - t0
cat(sprintf("n=%d row_subset=%.3f match=%.3f match_compiled=%.3f dollar_index=%.3f\n", n, t_row, t_match, t_match_cmp, t_dollar))
