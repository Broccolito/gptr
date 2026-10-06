# ckpt-objects.R -- copy-safe object pre-images and the exported gptr_preimage() generic
# (P16, layer L4). Adapted from G7's verified p1/ckpt_obj.R (report section 5.2). Copy-safety
# rule R6 (architecture 6.4) holds throughout:
#   * a pre-image is a BINDING in a private environment (`store$slots`), never a list element;
#   * it is released with rm(), which lowers the reference count again (the collector never does);
#   * list and S4 images are defused before they are dropped (G7 variant v5);
#   * user objects pass straight from get() into assign() or a leaf, never into a lasting frame.
# While a pre-image is held, a value object cannot be modified in place without R duplicating it,
# so "address changed" is an exact change detector (G7 section 2.3).

#' Tell the object checkpointer how to capture an object
#'
#' `gptr_preimage()` is the S3 generic the object checkpointer calls for a binding of the
#' workspace before a tool call that runs R code. It decides how the value the binding holds now
#' is kept, so that a rewind can put it back. Methods are leaf functions: they may read `x` but
#' must never store it anywhere.
#'
#' The default method keeps value-semantics objects by reference (`"ref"`: nothing is copied
#' unless the agent edits the object in place) and reports environments (including R6 and
#' RefClass objects) and external pointers as not restorable (`"none"`). The `data.table` method
#' returns a deep copy made with `data.table::copy()` (`"copy"`) when the agent's code is
#' predicted to modify the table by reference (`:=`, `set*()`) and the table fits the budget.
#' Packages add methods for their own classes with a delayed registration,
#' `S3method(gptr::gptr_preimage, myclass)`; an R6 class can, for example, return
#' `x$clone(deep = TRUE)` as `"copy"`. This generic is experimental.
#'
#' @param x The object bound to `name`.
#' @param name The binding name (a string).
#' @param ctx A list: `predicted`, what the agent's code is predicted to do to `name` (`"assign"`,
#'   `"modify"`, `"byref"`, `"remove"` or `"none"`); `bytes`, the size of `x` in bytes (`NA` when
#'   unknown); `budget`, the largest copy allowed, in bytes. When `ctx$dry` is `TRUE` the
#'   checkpointer only asks whether a capture is possible and a method must not copy.
#' @param ... Unused; for methods.
#' @return A list with `mode` (`"ref"`, `"copy"` or `"none"`), `reason` (a string explaining
#'   `"none"`, else `NULL`) and `copy` (the deep copy for `"copy"`, else `NULL`).
#' @export
#' @examples
#' gptr_preimage(1:3, "x", list(predicted = "assign", bytes = 64, budget = 1e9))$mode
#' gptr_preimage(new.env(), "cfg", list(predicted = "modify", bytes = NA, budget = 1e9))$reason
gptr_preimage = function(x, name, ctx, ...) {
  UseMethod("gptr_preimage")
}

#' @rdname gptr_preimage
#' @export
gptr_preimage.default = function(x, name, ctx, ...) {
  if (is.environment(x) || typeof(x) == "externalptr") {
    return(list(mode = "none", reason = "reference object (environment, R6 or external pointer)",
                copy = NULL))
  }
  list(mode = "ref", reason = NULL, copy = NULL)
}

#' @rdname gptr_preimage
#' @export
gptr_preimage.data.table = function(x, name, ctx, ...) {
  if (!identical(ctx$predicted, "byref")) return(list(mode = "ref", reason = NULL, copy = NULL))
  if (!isTRUE(ctx$bytes <= ctx$budget)) {
    return(list(mode = "none", reason = "data.table modified by reference, over the undo budget",
                copy = NULL))
  }
  if (!requireNamespace("data.table", quietly = TRUE)) {
    return(list(mode = "none", reason = "the data.table package is needed to copy it",
                copy = NULL))
  }
  copy = if (!isTRUE(ctx$dry)) data.table::copy(x)
  list(mode = "copy", reason = NULL, copy = copy)
}

#' A new pre-image store: private bindings (`slots`), their index and the spill directory `dir`
#' (`<workspace root>/checkpoints/objects/<session id>`, or NULL when images may not go to disk)
#' @noRd
ckpt_obj_store = function(dir = NULL) {
  s = new.env(parent = emptyenv())
  s$slots = new.env(parent = emptyenv())
  s$index = ckpt_index_empty()
  s$dir = dir
  s
}

#' The empty image index: one row per held image, oldest first
#' @noRd
ckpt_index_empty = function() {
  data.frame(key = character(), frag = character(), name = character(), role = character(),
             where = character(), file = character(), bytes = numeric(), turn = integer(),
             expect = character())
}

#' Add an index row (`role`: "pre" undo image, "redo" redo image)
#' @noRd
ckpt_index_add = function(store, key, frag, name, role, where = "memory", file = "",
                          bytes = NA_real_, turn = NA_integer_, expect = "") {
  store$index = rbind(store$index, data.frame(
    key = key, frag = frag, name = name, role = role, where = where, file = file,
    bytes = as.numeric(bytes), turn = as.integer(turn), expect = as.character(expect)
  ))
  invisible(key)
}

#' Remove index rows by key
#' @noRd
ckpt_index_remove = function(store, keys) {
  store$index = store$index[!store$index$key %in% keys, , drop = FALSE]
  invisible(keys)
}

#' Address of a binding (NA when absent); a leaf that never keeps the value
#' @noRd
ckpt_addr = function(envir, name) {
  if (!exists(name, envir = envir, inherits = FALSE)) return(NA_character_)
  rlang::obj_address(get(name, envir = envir, inherits = FALSE))
}

#' Capture bindings by reference into the store; no copy is made
#' @return df(name, key, address): the pending captures.
#' @noRd
ckpt_capture = function(store, envir, names) {
  keys = character(length(names))
  for (i in seq_along(names)) {
    keys[i] = paste0("p", id_new("", 12L))
    assign(keys[i], get(names[i], envir = envir, inherits = FALSE), envir = store$slots)
  }
  addr = vapply(keys, \(k) ckpt_addr(store$slots, k), "", USE.NAMES = FALSE)
  data.frame(name = names, key = keys, address = addr)
}

#' The file of a disk image
#' @noRd
ckpt_disk_file = function(dir, key) {
  file.path(dir, paste0(key, ".rdsx"))
}

#' Write the value bound to `name` as a disk image (contract 11.14, rule R7)
#' @noRd
ckpt_write_image = function(file, envir, name) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  write_atomic(file, serialize_leaf(get(name, envir = envir, inherits = FALSE), xdr = FALSE))
  invisible(file)
}

#' Eager disk image of a binding (a predicted in-place edit of a large object, G7 section 3.4)
#' @return `list(key, file)`.
#' @noRd
ckpt_capture_disk = function(store, envir, name) {
  k = paste0("d", id_new("", 12L))
  f = ckpt_disk_file(store$dir, k)
  ckpt_write_image(f, envir, name)
  list(key = k, file = f)
}

#' Settle captures: release unchanged bindings with rm(), index the rest
#' @return df(name, key, status ("unchanged", "changed", "removed"), pre_address, post_address
#'   ("" when removed)).
#' @noRd
ckpt_settle = function(store, envir, pending, frag = "", turn = NA_integer_) {
  post = vapply(pending$name, \(nm) ckpt_addr(envir, nm), "", USE.NAMES = FALSE)
  status = rep("changed", length(post))
  status[is.na(post)] = "removed"
  status[!is.na(post) & post == pending$address] = "unchanged"
  rm(list = pending$key[status == "unchanged"], envir = store$slots)
  for (i in which(status != "unchanged")) {
    ckpt_index_add(store, pending$key[i], frag, pending$name[i], "pre", turn = turn,
                   expect = pending$address[i])
  }
  post[is.na(post)] = ""
  data.frame(name = pending$name, key = pending$key, status = status,
             pre_address = pending$address, post_address = post)
}

#' Restore `name` from image `key` (memory or disk); the displaced value becomes a redo image
#' held by reference. `expect` is the address recorded after the call (NA for a removal): a
#' binding changed since is refused unless `force = TRUE` (the 3-way rule).
#' @return `list(ok, reason, redo, address)`.
#' @noRd
ckpt_restore = function(store, envir, name, key, expect = NULL, force = FALSE, frag = "",
                        turn = NA_integer_) {
  i = match(key, store$index$key)
  if (is.na(i)) {
    return(list(ok = FALSE, reason = "no pre-image", redo = NA_character_, address = NA_character_))
  }
  now = ckpt_addr(envir, name)
  if (!force && !is.null(expect) && !identical(now, expect)) {
    return(list(ok = FALSE, reason = "conflict: changed after the checkpoint (kept current)",
                redo = NA_character_, address = now))
  }
  f = store$index$file[i]
  disk = store$index$where[i] == "disk"
  if (disk && !file.exists(f)) {
    return(list(ok = FALSE, reason = "the disk image is missing", redo = NA_character_,
                address = now))
  }
  redo = NA_character_
  if (!is.na(now)) {
    redo = paste0("r", id_new("", 12L))
    assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
  }
  if (disk) {
    assign(name, unserialize(readBin(f, "raw", file.size(f))), envir = envir)
    unlink(f)
  } else {
    assign(name, get(key, envir = store$slots, inherits = FALSE), envir = envir)
    rm(list = key, envir = store$slots)
  }
  ckpt_index_remove(store, key)
  addr = ckpt_addr(envir, name)
  if (!is.na(redo)) {
    ckpt_index_add(store, redo, frag, name, "redo", turn = turn, expect = addr,
                   bytes = ckpt_unshared_bytes(store, redo, envir, name))
  }
  list(ok = TRUE, reason = NULL, redo = redo, address = addr)
}

#' Undo of a creation: unbind `name`, keep its value as a redo image
#' @noRd
ckpt_uncreate = function(store, envir, name, frag = "", turn = NA_integer_) {
  redo = paste0("r", id_new("", 12L))
  assign(redo, get(name, envir = envir, inherits = FALSE), envir = store$slots)
  rm(list = name, envir = envir)
  ckpt_index_add(store, redo, frag, name, "redo", turn = turn,
                 bytes = ckpt_unshared_bytes(store, redo, envir, name))
  redo
}

#' Container kind for defusing and the unshared-bytes walk: "list", "s4" or "leaf"
#' @noRd
ckpt_leaf_children = function(x) {
  if (is.environment(x)) return("leaf")
  if (isS4(x)) return("s4")
  if (is.list(x)) return("list")
  "leaf"
}

#' Take an image out of the store, then overwrite its children (G7 defuse variant v5)
#'
#' A list freed by the collector does not decrement its elements' reference counts, so elements
#' shared with the user's object would stay sticky (G7 c12); overwriting them does. Data frames
#' are unclassed first because their `[[<-` method checks row counts.
#' @noRd
ckpt_defuse = function(store, key) {
  v = get(key, envir = store$slots, inherits = FALSE)
  rm(list = key, envir = store$slots)
  k = ckpt_leaf_children(v)
  if (k == "list") {
    oldClass(v) = NULL
    for (j in seq_along(v)) v[[j]] = FALSE
  } else if (k == "s4") {
    for (sl in methods::slotNames(v)) {
      tryCatch({
        attr(v, sl) = FALSE
      }, error = function(e) NULL)
    }
  }
  invisible(key)
}

#' Spill a memory image to disk and defuse it; NULL when it cannot be written
#' @noRd
ckpt_spill = function(store, key) {
  i = match(key, store$index$key)
  if (is.null(store$dir) || is.na(i) || store$index$where[i] != "memory") return(invisible(NULL))
  f = ckpt_disk_file(store$dir, key)
  if (is.null(tryCatch(ckpt_write_image(f, store$slots, key), error = function(e) NULL))) {
    return(invisible(NULL))
  }
  ckpt_defuse(store, key)
  store$index$where[i] = "disk"
  store$index$file[i] = f
  invisible(f)
}

#' Drop images: defuse memory images, delete disk images, remove their index rows
#' @noRd
ckpt_drop = function(store, keys) {
  for (k in intersect(keys, ls(store$slots, all.names = TRUE))) ckpt_defuse(store, k)
  idx = store$index
  unlink(idx$file[idx$key %in% keys & idx$where == "disk"])
  ckpt_index_remove(store, keys)
}

#' Release every slot no index row owns (captures of a call whose settle never ran)
#' @noRd
ckpt_obj_sweep = function(store) {
  orphan = setdiff(ls(store$slots, all.names = TRUE), store$index$key)
  for (k in orphan) ckpt_defuse(store, k)
  invisible(orphan)
}

#' Collect the addresses of x and its children down to depth d
#'
#' `for (el in x)` visits a list's own components; `length()` dispatches (a POSIXlt or a vctrs
#' record reports its record count), so indexing up to it would run past the components.
#' @noRd
ckpt_addr_collect = function(x, d, seen) {
  assign(rlang::obj_address(x), TRUE, envir = seen)
  if (d <= 0L) return(invisible())
  k = ckpt_leaf_children(x)
  if (k == "list") {
    for (el in x) ckpt_addr_collect(el, d - 1L, seen)
  }
  if (k == "s4") {
    for (sl in methods::slotNames(x)) ckpt_addr_collect(attr(x, sl, exact = TRUE), d - 1L, seen)
  }
  invisible()
}

#' Add the bytes of the parts of x not in `seen` to `acc$bytes` (walked as ckpt_addr_collect())
#' @noRd
ckpt_unshared_walk = function(x, d, seen, acc) {
  if (exists(rlang::obj_address(x), envir = seen, inherits = FALSE)) return(invisible())
  k = ckpt_leaf_children(x)
  if (d <= 0L || k == "leaf") {
    acc$bytes = acc$bytes + as.numeric(utils::object.size(x))
    return(invisible())
  }
  acc$bytes = acc$bytes + 64
  if (k == "list") {
    for (el in x) ckpt_unshared_walk(el, d - 1L, seen, acc)
  }
  if (k == "s4") {
    for (sl in methods::slotNames(x)) {
      ckpt_unshared_walk(attr(x, sl, exact = TRUE), d - 1L, seen, acc)
    }
  }
  invisible()
}

#' Bytes of image `key` not shared with the current value of `name` (G7 estimator, depth 4)
#' @noRd
ckpt_unshared_bytes = function(store, key, envir, name, depth = 4L) {
  seen = new.env(parent = emptyenv())
  acc = new.env(parent = emptyenv())
  acc$bytes = 0
  if (exists(name, envir = envir, inherits = FALSE)) {
    ckpt_addr_collect(get(name, envir = envir, inherits = FALSE), depth, seen)
  }
  ckpt_unshared_walk(get(key, envir = store$slots, inherits = FALSE), depth, seen, acc)
  acc$bytes
}

#' A new per-session checkpoint state; its finalizer releases the images (G7 c06b)
#' @noRd
ckpt_ck_new = function(sid, spill_dir = NULL) {
  ck = new.env(parent = emptyenv())
  ck$sid = sid
  ck$obj = ckpt_obj_store(spill_dir)
  reg.finalizer(ck, ckpt_ck_finalize)
  ck
}

#' Release every in-memory image of a checkpoint state (finalizer and session shutdown)
#' @noRd
ckpt_ck_finalize = function(ck) {
  ckpt_drop(ck$obj, ls(ck$obj$slots, all.names = TRUE))
}
