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

#' Add an index row (`role`: "pre" undo image, "redo" redo image, "mark" the address a value
#' without an image left; `expect`: the address the binding must have for the row to apply, ""
#' when absent, an image key while the value it expects lives only in that image)
#' @noRd
ckpt_index_add = function(store, key, frag, name, role, where = "memory", file = "",
                          bytes = NA_real_, turn = NA_integer_, expect = "") {
  store$index = rbind(store$index, data.frame(
    key = key, frag = frag, name = name, role = role, where = where, file = file,
    bytes = as.numeric(bytes), turn = as.integer(turn), expect = as.character(expect)
  ))
  invisible(key)
}

#' The newest index key for (fragment, name, role), or NA
#' @noRd
ckpt_index_find = function(store, frag, name, role) {
  idx = store$index
  i = which(idx$frag == frag & idx$name == name & idx$role == role)
  if (length(i)) idx$key[max(i)] else NA_character_
}

#' Add a "mark" row: the address a created binding, or a removed one an undo brought back, left
#' @noRd
ckpt_mark = function(store, frag, name, turn, expect) {
  ckpt_index_add(store, paste0("u", id_new("", 12L)), frag, name, "mark", where = "none",
                 turn = turn, expect = expect)
}

#' Rows of `name` that expect `from` expect `to` instead: their value was restored at the new
#' address `to`, or lives only in image `to` (a copy or a disk image; `from` may be reused)
#' @noRd
ckpt_repoint = function(store, name, from, to) {
  store$index$expect[store$index$name == name & store$index$expect == from] = to
  invisible(to)
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
  post[is.na(post)] = ""
  rm(list = pending$key[status == "unchanged"], envir = store$slots)
  for (i in which(status != "unchanged")) {
    ckpt_index_add(store, pending$key[i], frag, pending$name[i], "pre", turn = turn,
                   expect = post[i])
  }
  data.frame(name = pending$name, key = pending$key, status = status,
             pre_address = pending$address, post_address = post)
}

#' Restore `name` from image `key` (memory or disk); the displaced value becomes a redo image
#' held by reference. Callers apply the 3-way rule first (ckpt_expect_ok()).
#' @return `list(ok, reason, redo, address)`.
#' @noRd
ckpt_restore = function(store, envir, name, key, frag = "", turn = NA_integer_) {
  i = match(key, store$index$key)
  if (is.na(i)) {
    return(list(ok = FALSE, reason = "no pre-image", redo = NA_character_, address = NA_character_))
  }
  now = ckpt_addr(envir, name)
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
  ckpt_repoint(store, name, key, addr)
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

#' Spill a memory image to disk and defuse it; NULL when it cannot be written. Rows expecting its
#' value expect its key, unless the binding in `envir` (the session home) still holds that value.
#' @noRd
ckpt_spill = function(store, key, envir) {
  i = match(key, store$index$key)
  if (is.null(store$dir) || is.na(i) || store$index$where[i] != "memory") return(invisible(NULL))
  f = ckpt_disk_file(store$dir, key)
  if (is.null(tryCatch(ckpt_write_image(f, store$slots, key), error = function(e) NULL))) {
    return(invisible(NULL))
  }
  nm = store$index$name[i]
  addr = ckpt_addr(store$slots, key)
  if (!identical(ckpt_addr(envir, nm), addr)) ckpt_repoint(store, nm, addr, key)
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
  ck$state_img = new.env(parent = emptyenv())
  reg.finalizer(ck, ckpt_ck_finalize)
  ck
}

#' Release every in-memory image of a checkpoint state (finalizer and session shutdown)
#' @noRd
ckpt_ck_finalize = function(ck) {
  ckpt_drop(ck$obj, ls(ck$obj$slots, all.names = TRUE))
}

#' A new fragment id ("k" + 10 hex, RNG-free)
#' @noRd
ckpt_frag_id = function() {
  paste0("k", id_new("", 10L))
}

#' A number for a fragment: NA becomes -1 (json_encode() would write NA as the string "NA")
#' @noRd
ckpt_json_num = function(x) {
  if (is.na(x)) -1 else as.numeric(x)
}

#' A character vector from a fragment field, as built or as decoded from JSON (lists, NULL)
#' @noRd
ckpt_chr = function(x) {
  as.character(unlist(x, use.names = FALSE))
}

#' An empty item table (the results of undo, redo and previews)
#' @noRd
ckpt_items = function() {
  data.frame(item = character(), ok = logical(), action = character())
}

#' Add one row to an item table
#' @noRd
ckpt_item = function(out, item, ok, action) {
  rbind(out, data.frame(item = item, ok = ok, action = action))
}

# ---- capture policy (G7 section 3.4) ------------------------------------------------------------

#' May object images go to disk? With a consented workspace (`.gptr/`) or when a human is
#' present (then under tempdir()); never in a non-interactive run without `.gptr/` (G7 4.5)
#' @noRd
ckpt_spill_allowed = function() {
  !is.null(workspace_dir()) || gptr_has_human()
}

#' The object budgets (contract 3.1, options gptr.undo_*)
#' @noRd
ckpt_limits = function() {
  list(capture_max = gptr_opt("undo_capture_max"), max_bytes = gptr_opt("undo_max_bytes"),
       spill_max = gptr_opt("undo_spill_max"), turns = gptr_opt("undo_turns"))
}

#' Targets of R code for the checkpointers: P11's code_targets() reduced (contract 7.16, IC-31);
#' code that cannot be analysed has the one `unknown` target
#' @return `list(assign, modify, byref, remove, super, files, unknown, process)`, chr each.
#' @noRd
ckpt_predict = function(code) {
  fields = c("assign", "modify", "byref", "remove", "super", "files", "unknown", "process")
  out = sapply(fields, function(f) character(), simplify = FALSE)
  if (!rlang::is_string(code)) return(out)
  tg = tryCatch(code_targets(code), error = function(e) list(parse_error = TRUE))
  if (!isTRUE(tg$parse_error)) return(tg[fields])
  out$unknown = "the code could not be analysed"
  out
}

#' What the code is predicted to do to each name: byref > modify > remove > assign > none
#' @noRd
ckpt_predicted = function(names, tg) {
  out = rep("none", length(names))
  out[names %in% c(tg$assign, tg$super)] = "assign"
  out[names %in% tg$remove] = "remove"
  out[names %in% tg$modify] = "modify"
  out[names %in% tg$byref] = "byref"
  out
}

#' The capture plan of each binding (G7 section 3.4 step 3): "ref", "copy", "disk", "none" (the
#' gptr_preimage() method refused) or "skip" (over the budget). Unknown sizes count as 0 bytes.
#' @noRd
ckpt_capture_how = function(bytes, predicted, mode, spill_ok, lim) {
  bytes[is.na(bytes)] = 0
  over = bytes > lim$capture_max
  how = ifelse(over, "skip", "ref")
  how[over & predicted %in% c("assign", "remove") & bytes <= lim$max_bytes] = "ref"
  how[over & predicted == "modify" & bytes <= lim$spill_max & spill_ok] = "disk"
  how[mode == "copy"] = "copy"
  how[mode == "none"] = "none"
  how
}

#' gptr_preimage() for every binding of a snapshot; "copy" results go straight into the store
#' (with `dry = TRUE` nothing is copied and `store` may be NULL). A by-reference edit bypasses
#' copy-on-modify and would change a "ref" pre-image too, so it needs a copy or is "none".
#' @noRd
ckpt_preimage_modes = function(store, envir, snap, pred, lim, dry = FALSE) {
  n = nrow(snap)
  mode = rep("ref", n)
  reason = rep("", n)
  key = rep("", n)
  for (i in seq_len(n)) {
    pm = gptr_preimage(get(snap$name[i], envir = envir, inherits = FALSE), snap$name[i],
                       list(predicted = pred[i], bytes = snap$bytes[i], budget = lim$max_bytes,
                            dry = dry))
    if (pred[i] == "byref" && identical(pm$mode, "ref")) {
      pm = list(mode = "none", reason = "edited by reference")
    }
    mode[i] = pm$mode
    if (identical(pm$mode, "none")) reason[i] = pm$reason %||% "not restorable"
    if (!identical(pm$mode, "copy") || dry) next
    if (is.null(pm$copy)) {
      # a restore would bind NULL: fail closed
      mode[i] = "none"
      reason[i] = "the gptr_preimage() method returned no copy"
    } else {
      key[i] = paste0("c", id_new("", 12L))
      assign(key[i], pm$copy, envir = store$slots)
    }
  }
  list(mode = mode, reason = reason, key = key)
}

# ---- the objects checkpointer (G7 sections 3.4, 3.6, 3.9) ----------------------------------------

#' Objects checkpointer, before a call that evaluates R code: capture pre-images per the plan
#' @return A token, or NULL when the call evaluates no R code.
#' @noRd
ckpt_objects_before = function(ck, call, envir, turn = 1L) {
  code = call$input$code
  if (!rlang::is_string(code)) return(NULL)
  store = ck$obj
  ckpt_obj_sweep(store)
  lim = ckpt_limits()
  ck$snap = env_snapshot(envir, ck$snap)
  full = ck$snap
  snap = full[full$kind == "value", , drop = FALSE]
  tg = ckpt_predict(code)
  pred = ckpt_predicted(snap$name, tg)
  pm = ckpt_preimage_modes(store, envir, snap, pred, lim)
  how = ckpt_capture_how(snap$bytes, pred, pm$mode, !is.null(store$dir), lim)
  reason = pm$reason
  reason[how == "skip"] = "over the undo budget"
  key = pm$key
  refs = which(how == "ref")
  key[refs] = ckpt_capture(store, envir, snap$name[refs])$key
  for (j in which(how == "disk")) {
    key[j] = tryCatch(ckpt_capture_disk(store, envir, snap$name[j])$key, error = function(e) "")
    if (!nzchar(key[j])) {
      how[j] = "skip"
      reason[j] = "the disk image could not be written"
    }
  }
  list(frag = ckpt_frag_id(), turn = as.integer(turn), snap = snap,
       others = full$name[full$kind != "value"], tg = tg, how = how, reason = reason, key = key,
       pred = pred)
}

#' A fragment row: names, classes, sizes and addresses, never a value (contract 4.6)
#' @noRd
ckpt_obj_row = function(name, status, how, class, bytes, pre, post, restorable, reason,
                        image = "", where = "", held = NA) {
  list(name = name, status = status, how = how, class = class, bytes = ckpt_json_num(bytes),
       pre_address = pre, post_address = post, restorable = restorable, reason = reason,
       image = image, where = where, held_bytes = ckpt_json_num(held))
}

#' Settle binding i of the token after the call: a fragment row, or NULL when unchanged.
#' ckpt_settle() has already released the unchanged "ref" captures and indexed the others.
#' @noRd
ckpt_settle_row = function(store, envir, token, i, post) {
  s0 = token$snap[i, , drop = FALSE]
  nm = s0$name
  how = token$how[i]
  key = token$key[i]
  j = match(nm, post$name)
  removed = is.na(j)
  now = if (removed) "" else post$address[j]
  same = !removed && identical(now, s0$address)
  changed = !same || !identical(post$fp[j], s0$fp)
  # a held "ref" pre-image (never one of a by-reference edit) makes the address exact; others may
  # change in place unseen (fingerprints sample), so every predicted target counts as changed
  if (how != "ref") changed = changed || token$pred[i] != "none"
  if (!changed) {
    if (identical(how, "copy")) rm(list = key, envir = store$slots)
    return(NULL)
  }
  status = if (removed) "removed" else "changed"
  if (identical(how, "ref") && same) {
    return(ckpt_obj_row(nm, status, how, s0$class, s0$bytes, s0$address, now, FALSE,
                        "modified by reference (the pre-image is the live object)"))
  }
  if (!how %in% c("ref", "copy", "disk")) {
    return(ckpt_obj_row(nm, status, how, s0$class, s0$bytes, s0$address, now, FALSE,
                        token$reason[i]))
  }
  disk = identical(how, "disk")
  held = if (disk) 0 else ckpt_unshared_bytes(store, key, envir, nm)
  if (identical(how, "ref")) {
    store$index$bytes[store$index$key == key] = held
  } else {
    ckpt_repoint(store, nm, s0$address, key)
    ckpt_index_add(store, key, token$frag, nm, "pre", where = if (disk) "disk" else "memory",
                   file = if (disk) ckpt_disk_file(store$dir, key) else "",
                   bytes = if (disk) s0$bytes else held, turn = token$turn, expect = now)
  }
  ckpt_obj_row(nm, status, how, s0$class, s0$bytes, s0$address, now, TRUE, "", image = key,
               where = if (disk) "disk" else "memory", held = held)
}

#' Objects checkpointer, after the call: settle every capture and build the JSON-able fragment
#' @return `list(id, turn, objects = list(<row>))`, or NULL when nothing changed.
#' @noRd
ckpt_objects_after = function(ck, call, envir, token) {
  if (is.null(token)) return(NULL)
  store = ck$obj
  snap = token$snap
  ck$snap = env_snapshot(envir, ck$snap)
  full = ck$snap
  post = full[full$kind == "value", , drop = FALSE]
  refs = which(token$how == "ref")
  ckpt_settle(store, envir, data.frame(name = snap$name[refs], key = token$key[refs],
                                       address = snap$address[refs]),
              frag = token$frag, turn = token$turn)
  rows = list()
  for (i in seq_len(nrow(snap))) {
    row = ckpt_settle_row(store, envir, token, i, post)
    if (!is.null(row)) rows[[length(rows) + 1L]] = row
  }
  for (nm in setdiff(post$name, c(snap$name, token$others))) {
    j = match(nm, post$name)
    ckpt_mark(store, token$frag, nm, token$turn, post$address[j])
    rows[[length(rows) + 1L]] = ckpt_obj_row(nm, "created", "created", post$class[j],
                                             post$bytes[j], "", post$address[j], TRUE, "")
  }
  pred = ckpt_predicted(token$others, token$tg)
  for (k in seq_along(token$others)) {
    gone = !token$others[k] %in% full$name
    if (!gone && pred[k] == "none") next
    rows[[length(rows) + 1L]] = ckpt_obj_row(token$others[k], if (gone) "removed" else "changed",
                                             "none", "unknown", NA, "", "", FALSE,
                                             "a promise or an active binding (not captured)")
  }
  if (!length(rows)) return(NULL)
  list(id = token$frag, turn = token$turn, objects = rows)
}

#' Undo one objects fragment, newest row first (the 3-way rule of G7 section 3.6)
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_objects_undo = function(ck, fragment, envir, force = FALSE, dry = FALSE) {
  store = ck$obj
  frag = fragment$id
  turn = as.integer(fragment$turn)
  out = ckpt_items()
  for (r in rev(fragment$objects)) {
    nm = r$name
    item = paste("object", nm)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not restored (", r$reason, ")"))
      next
    }
    now = ckpt_addr(envir, nm)
    created = identical(r$status, "created")
    key = ckpt_index_find(store, frag, nm, if (created) "mark" else "pre")
    # the index follows the value to the new address a restore from a copy or disk image gave it
    expect = if (is.na(key)) r$post_address else store$index$expect[match(key, store$index$key)]
    if (created) {
      if (is.na(now)) {
        out = ckpt_item(out, item, TRUE, "already absent")
      } else if (!force && !identical(now, expect)) {
        out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
      } else if (dry) {
        out = ckpt_item(out, item, TRUE, "would be removed")
      } else {
        ckpt_index_remove(store, key)
        ckpt_uncreate(store, envir, nm, frag, turn)
        out = ckpt_item(out, item, TRUE, "removed (created by the turn)")
      }
      next
    }
    if (is.na(key)) {
      # an image of an earlier R process: the fragment row may still say "memory" when the image
      # was spilled at a turn end after the row was written; image keys are unique and alphanumeric
      ok = !is.null(store$dir) && grepl("^[[:alnum:]]+$", r$image)
      f = if (ok) ckpt_disk_file(store$dir, r$image) else ""
      if (!file.exists(f)) {
        out = ckpt_item(out, item, FALSE, paste0("not restored (no pre-image: dropped over the ",
                                                 "undo budget or made in another R process)"))
        next
      }
      if (!force) {
        out = ckpt_item(out, item, FALSE, paste0("not restored (the image on disk was made by ",
                                                 "an earlier R process; use force = TRUE)"))
        next
      }
      key = r$image
      if (!dry) ckpt_index_add(store, key, frag, nm, "pre", where = "disk", file = f, turn = turn)
    }
    if (!force && !ckpt_expect_ok(now, expect)) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the checkpoint (kept current)")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be restored")
      next
    }
    res = ckpt_restore(store, envir, nm, key, frag = frag, turn = turn)
    if (res$ok && identical(r$status, "removed")) ckpt_mark(store, frag, nm, turn, res$address)
    out = ckpt_item(out, item, res$ok,
                    if (res$ok) "restored" else paste0("not restored (", res$reason, ")"))
  }
  out
}

#' Redo one objects fragment, oldest row first: the mirror of ckpt_objects_undo(). The undo left
#' a "redo" image (or, for a removal, a "mark") whose `expect` is the address it left behind.
#' @noRd
ckpt_objects_redo = function(ck, fragment, envir, force = FALSE, dry = FALSE) {
  store = ck$obj
  frag = fragment$id
  turn = as.integer(fragment$turn)
  out = ckpt_items()
  for (r in fragment$objects) {
    nm = r$name
    item = paste("object", nm)
    if (!isTRUE(r$restorable)) {
      out = ckpt_item(out, item, FALSE, paste0("not redone (", r$reason, ")"))
      next
    }
    removed = identical(r$status, "removed")
    key = ckpt_index_find(store, frag, nm, if (removed) "mark" else "redo")
    if (is.na(key)) {
      out = ckpt_item(out, item, FALSE, "not redone (it was not undone in this R process)")
      next
    }
    now = ckpt_addr(envir, nm)
    if (!force && !ckpt_expect_ok(now, store$index$expect[match(key, store$index$key)])) {
      out = ckpt_item(out, item, FALSE, "conflict: changed after the undo (kept current)")
      next
    }
    if (dry) {
      out = ckpt_item(out, item, TRUE, "would be redone")
      next
    }
    if (removed) {
      res = list(ok = TRUE, redo = if (!is.na(now)) ckpt_uncreate(store, envir, nm, frag, turn))
      ckpt_index_remove(store, key)
    } else {
      res = ckpt_restore(store, envir, nm, key, frag = frag, turn = turn)
      if (res$ok && identical(r$status, "created")) ckpt_mark(store, frag, nm, turn, res$address)
    }
    # the value the redo displaced is the next undo's pre-image
    store$index$role[store$index$key %in% res$redo] = "pre"
    action = if (removed) "removed again" else "redone"
    out = ckpt_item(out, item, res$ok,
                    if (res$ok) action else paste0("not redone (", res$reason, ")"))
  }
  out
}

#' The 3-way rule (G7 section 3.6): does the binding's address `now` match `expect` ("" = absent)?
#' @noRd
ckpt_expect_ok = function(now, expect) {
  if (nzchar(expect)) identical(now, expect) else is.na(now)
}

#' Model-facing notices for objects changed without an undo copy (G7 section 3.9, about 25
#' tokens each): `note: <name> (<size>) was <overwritten|modified|removed> without an undo copy
#' (<reason>).`
#' @noRd
ckpt_objects_notes = function(fragment) {
  out = character()
  for (r in fragment$objects) {
    if (isTRUE(r$restorable)) next
    verb = if (identical(r$status, "removed")) {
      "removed"
    } else if (identical(r$pre_address, r$post_address)) {
      "modified"
    } else {
      "overwritten"
    }
    size = if (r$bytes < 0) "unknown size" else env_fmt_bytes(r$bytes)
    out = c(out, paste0("note: ", r$name, " (", size, ") was ", verb,
                        " without an undo copy (", r$reason, ")."))
  }
  out
}

#' One line per object of a fragment
#' @noRd
ckpt_objects_describe = function(fragment) {
  vapply(fragment$objects, function(r) {
    paste0("object ", r$name, ": ", r$status, if (!isTRUE(r$restorable)) " (not restorable)")
  }, "")
}

#' Enforce the in-memory budget at the end of a turn (G7 section 3.4 step 6, architecture 6.16):
#' drop images older than gptr.undo_turns turns, then, while over gptr.undo_max_bytes, spill the
#' largest image or, when it cannot be spilled, drop the oldest. `envir` is the session home.
#' @noRd
ckpt_objects_budget = function(ck, turn, envir) {
  store = ck$obj
  lim = ckpt_limits()
  ckpt_obj_sweep(store)
  ckpt_drop(store, store$index$key[which(store$index$turn <= turn - lim$turns)])
  repeat {
    mem = store$index[store$index$where == "memory", , drop = FALSE]
    if (sum(mem$bytes, na.rm = TRUE) <= lim$max_bytes) break
    big = which.max(mem$bytes)
    if (mem$bytes[big] > lim$spill_max || is.null(ckpt_spill(store, mem$key[big], envir))) {
      ckpt_drop(store, mem$key[1L])
    }
  }
  invisible(store$index)
}

#' The `checkpoint.note` service (contract 7.0): "cannot be undone: ..." for the permission
#' detail view of a call that would change objects gptr cannot capture, or NULL. With `run =
#' NULL` (P11's detail view) the innermost executing run is used.
#' @noRd
ckpt_note = function(call, run = NULL) {
  code = call$input$code
  if (!rlang::is_string(code)) return(NULL)
  mode = setting_get("checkpoint", default = "on")
  if (identical(mode, "off")) {
    return("cannot be undone: checkpoints are off (gptr.checkpoint = \"off\")")
  }
  run = run %||% run_current()
  envir = run_eval_env(run)
  if (!is.environment(envir)) return(NULL)
  snap = env_snapshot(envir)
  snap = snap[snap$kind == "value", , drop = FALSE]
  pred = ckpt_predicted(snap$name, ckpt_predict(code))
  snap = snap[pred != "none", , drop = FALSE]
  pred = pred[pred != "none"]
  lim = ckpt_limits()
  # objects are captured only with "on" and in the session home, never a function frame (R2)
  pm = if (identical(mode, "on") && identical(envir, session_home(run$shell))) {
    ckpt_preimage_modes(NULL, envir, snap, pred, lim, dry = TRUE)
  } else {
    list(mode = rep("none", nrow(snap)),
         reason = rep("objects are not checkpointed here", nrow(snap)))
  }
  how = ckpt_capture_how(snap$bytes, pred, pm$mode, ckpt_spill_allowed(), lim)
  bad = how %in% c("none", "skip")
  if (!any(bad)) return(NULL)
  size = vapply(snap$bytes[bad], env_fmt_bytes, "")
  why = ifelse(how[bad] == "skip", paste0(size, ", over the undo budget"), pm$reason[bad])
  paste0("cannot be undone: ", paste0(snap$name[bad], " (", why, ")", collapse = "; "))
}

# ---- the state checkpointer (G7 section 5.5) -----------------------------------------------------
# Fragments carry names; option values, working directories and connection identities stay in this
# R process (ck$state_img, by fragment id). Environment variables and the RNG state are reported,
# never set (contract 12.3: Sys.setenv() only in auth-dotenv.R; .Random.seed only in rng_swap() and
# with_seed_preserved(), IC-61).

#' The open user connections, named by number: each one's conn_id as text (unique within this R
#' process; text, so an image never keeps a connection alive)
#' @noRd
ckpt_cons = function() {
  n = setdiff(as.integer(getAllConnections()), 0:2)
  stats::setNames(vapply(n, function(i) format(attr(getConnection(i), "conn_id")), ""), n)
}

#' The process state an R call can change: P09's session state, the locale, the open connections
#' and a hash of the global RNG state ("" when there is none)
#' @noRd
ckpt_state_snapshot = function() {
  seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  c(eval_session_state(),
    list(locale = Sys.getlocale(), connections = ckpt_cons(),
         seed = if (is.null(seed)) "" else hash_xxh128(seed)))
}

#' State checkpointer, before a call that evaluates R code
#' @return A token, or NULL when the call evaluates no R code.
#' @noRd
ckpt_state_before = function(ck, call, turn = 1L) {
  if (!rlang::is_string(call$input$code)) return(NULL)
  list(frag = ckpt_frag_id(), turn = as.integer(turn), pre = ckpt_state_snapshot())
}

#' State checkpointer, after the call: names in the fragment, values in `ck$state_img`. Options
#' that appear while the call loads namespaces belong to those namespaces and stay with them.
#' @return `list(id, turn, options, envvars, wd, locale, attached, detached, loaded, dev_opened,
#'   dev_closed, con_opened, con_closed, rng)`, or NULL when nothing changed.
#' @noRd
ckpt_state_after = function(ck, call, token) {
  if (is.null(token)) return(NULL)
  pre = token$pre
  post = ckpt_state_snapshot()
  ev = eval_state_diff(pre, post)
  new = if (length(ev$loaded)) setdiff(names(post$options), names(pre$options))
  dev = function(a, b) as.integer(setdiff(a$devices, b$devices))
  con = function(a, b) as.integer(names(a$connections)[!a$connections %in% b$connections])
  d = list(options = setdiff(ev$options, new), envvars = ev$envvars, wd = !is.null(ev$wd),
           locale = !identical(pre$locale, post$locale), attached = ev$attached,
           detached = setdiff(pre$search, post$search), loaded = ev$loaded,
           dev_opened = dev(post, pre), dev_closed = dev(pre, post),
           con_opened = con(post, pre), con_closed = con(pre, post),
           rng = isTRUE(gptr_opt("checkpoint_rng")) && !identical(pre$seed, post$seed))
  if (!any(vapply(d, function(x) length(x) > 0L && !isFALSE(x), NA))) return(NULL)
  items = c(paste("option", d$options, recycle0 = TRUE), "working directory")
  keep = function(s) stats::setNames(c(s$options[d$options], list(s$wd)), items)
  assign(token$frag, list(pre = keep(pre), post = keep(post), con = post$connections),
         envir = ck$state_img)
  c(list(id = token$frag, turn = token$turn), d)
}

#' One undo or redo action as an item row: "would be <verb>" when `dry`; otherwise `fun()` runs
#' and the row says <verb>, or "not <verb> (<error>)" when it fails
#' @noRd
ckpt_state_do = function(out, item, verb, dry, fun) {
  err = if (!dry) {
    tryCatch({
      fun()
      NULL
    }, error = conditionMessage)
  }
  action = if (dry) paste("would be", verb) else if (is.null(err)) verb else
    paste0("not ", verb, " (", err, ")")
  ckpt_item(out, item, is.null(err), action)
}

#' Undo (or redo) the options, the working directory and the search path of a state fragment. An
#' option or the directory is set only while it holds the value the call (or the undo) left: the
#' 3-way rule of G7 section 3.6.
#' @noRd
ckpt_state_apply = function(ck, fragment, undo, force, dry) {
  img = get0(fragment$id, envir = ck$state_img, inherits = FALSE)
  left = if (undo) img$post else img$pre
  goal = if (undo) img$pre else img$post
  done = if (undo) "restored" else "redone"
  out = ckpt_items()
  wd = if (isTRUE(fragment$wd)) "working directory"
  for (item in c(paste("option", ckpt_chr(fragment$options), recycle0 = TRUE), wd)) {
    n = sub("^option ", "", item)
    now = if (identical(item, wd)) getwd() else getOption(n)
    if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, paste0("not ", done, " (the values were not kept: ",
                                               "another R process made this checkpoint)"))
    } else if (!force && !identical(now, left[[item]])) {
      out = ckpt_item(out, item, FALSE, paste0("conflict: changed after the ",
                                               if (undo) "checkpoint" else "undo",
                                               " (kept current)"))
    } else {
      out = ckpt_state_do(out, item, done, dry, function() {
        if (identical(item, wd)) setwd(goal[[item]]) else options(stats::setNames(goal[item], n))
      })
    }
  }
  attached = ckpt_chr(fragment$attached)
  for (p in c(attached, ckpt_chr(fragment$detached))) {
    attach = xor(undo, p %in% attached)
    out = ckpt_state_do(out, p, if (attach) "attached" else "detached", dry, function() {
      if (attach && !p %in% search()) {
        suppressPackageStartupMessages(attachNamespace(sub("^package:", "", p)))
      }
      if (!attach && p %in% search()) detach(p, character.only = TRUE)
    })
  }
  out
}

#' Undo one state fragment: options, the working directory and the search path
#' (ckpt_state_apply()), connections the call opened while they are still open, and devices with
#' gptr.checkpoint_close_devices; the rest is reported
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_state_undo = function(ck, fragment, force = FALSE, dry = FALSE) {
  out = ckpt_state_apply(ck, fragment, TRUE, force, dry)
  img = get0(fragment$id, envir = ck$state_img, inherits = FALSE)
  gone = "not closed (another R process made this checkpoint)"
  for (n in ckpt_chr(fragment$envvars)) {
    out = ckpt_item(out, paste("environment variable", n), FALSE,
                    "not restored (gptr never sets environment variables; use Sys.setenv())")
  }
  if (isTRUE(fragment$locale)) {
    out = ckpt_item(out, "locale", NA, "changed by the turn; left as is (see Sys.setlocale())")
  }
  loaded = ckpt_chr(fragment$loaded)
  if (length(loaded)) {
    out = ckpt_item(out, paste("namespaces", paste(loaded, collapse = ", ")), NA,
                    "stay loaded with the options they created (unloading is unsafe)")
  }
  close_dev = isTRUE(gptr_opt("checkpoint_close_devices"))
  for (dv in as.integer(ckpt_chr(fragment$dev_opened))) {
    item = paste("graphics device", dv)
    if (!close_dev) {
      out = ckpt_item(out, item, NA, "left open (gptr.checkpoint_close_devices = FALSE)")
    } else if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, gone)
    } else {
      out = ckpt_state_do(out, item, "closed", dry, function() {
        if (dv %in% grDevices::dev.list()) grDevices::dev.off(dv)
      })
    }
  }
  now = ckpt_cons()
  for (cn in ckpt_chr(fragment$con_opened)) {
    item = paste("connection", cn)
    if (is.null(img)) {
      out = ckpt_item(out, item, FALSE, gone)
    } else if (!identical(now[cn], img$con[cn])) {
      out = ckpt_item(out, item, TRUE, "already closed")
    } else {
      out = ckpt_state_do(out, item, "closed", dry, function() close(getConnection(as.integer(cn))))
    }
  }
  for (item in c(paste("graphics device", ckpt_chr(fragment$dev_closed), recycle0 = TRUE),
                 paste("connection", ckpt_chr(fragment$con_closed), recycle0 = TRUE))) {
    out = ckpt_item(out, item, FALSE, "not restored (closed by the turn; it cannot be reopened)")
  }
  if (isTRUE(fragment$rng)) {
    out = ckpt_item(out, "RNG state", NA,
                    "advanced by the turn; left as is (gptr never sets .Random.seed)")
  }
  out
}

#' Redo one state fragment: options, the working directory and packages again
#' @noRd
ckpt_state_redo = function(ck, fragment, force = FALSE, dry = FALSE) {
  ckpt_state_apply(ck, fragment, FALSE, force, dry)
}

#' One line per item of a state fragment
#' @noRd
ckpt_state_describe = function(fragment) {
  c(paste("option", ckpt_chr(fragment$options), recycle0 = TRUE),
    paste("environment variable", ckpt_chr(fragment$envvars), recycle0 = TRUE),
    if (isTRUE(fragment$wd)) "working directory",
    ckpt_chr(fragment$attached), ckpt_chr(fragment$detached),
    if (isTRUE(fragment$rng)) "RNG state")
}
