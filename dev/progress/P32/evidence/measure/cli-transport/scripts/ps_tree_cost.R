# Cost of ps::ps_find_tree(marker) (gptr's proc_tree(), run at each CLI child's exit and twice in
# every kill_all()); it reads the environment of every process of the user
n = length(ps::ps_pids())
t = replicate(10, system.time(ps::ps_find_tree("GPTR_NO_SUCH_MARKER_abc123"))[["elapsed"]])
cat(sprintf("processes=%d ps_find_tree median=%.4f s min=%.4f max=%.4f\n", n, median(t), min(t), max(t)))
