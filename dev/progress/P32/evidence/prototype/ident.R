suppressMessages(library(data.table))
serialize_leaf = function(object, xdr = TRUE) serialize(object, NULL, ascii = FALSE, xdr = xdr)
e0 = new.env(); source("../p32/orig-size.R", local = e0); e0$serialize_leaf = serialize_leaf
e1 = new.env(); source("b-size.R", local = e1); e1$serialize_leaf = serialize_leaf
set.seed(2)
objs = list(iris, mtcars, letters, c(NA, "a", "a", NA), character(), as.character(1:1e5), 1:1e6,
  lapply(1:5000, function(i) list(id = paste0("id", i), v = runif(5), tag = c("a", "b"))),
  lapply(1:300, function(i) paste0("s", i %% 7, "_", 1:(if (i %% 9) 200 else 20000))),
  data.table(a = sample(letters, 1e5, TRUE), b = paste0("x", 1:1e5)), lm(mpg ~ wt, mtcars),
  list2env(list(a = "x", b = letters)), function(x) x, paste0("id_", 1:4e6),
  c(strrep("a", 1e8), paste0("s", 1:1000)))
ok = vapply(objs, function(x) identical(e0$env_snap_size(x), as.numeric(e1$env_snap_size(x))), NA)
print(ok)
x = objs[[8]]; y = x; y[[3]]$id = "new"; y[[4000]] = list(id = "zz", v = 1, tag = "q")
print(identical(e0$env_snap_size(x, NULL, y), e1$env_snap_size(x, NULL, y)))
print(identical(e0$env_snap_size(x, NULL, x), e1$env_snap_size(x, NULL, x)))
gc(reset = TRUE); invisible(e1$env_snap_size(objs[[15]])); print(gc()[2, 6])
