# Hashes, canonical JSON, RNG-free identifiers, seed preservation and fingerprints
# (contract section 1.2, 7.1; IC-20, IC-61). Nothing here touches .Random.seed except
# with_seed_preserved(), which saves and restores the user's value.

the$id_count = 0
the$id_salt = NULL

#' SHA-256 of the UTF-8 bytes of each string (vectorised; NA stays NA), or of a raw vector
#' @noRd
hash_sha256 = function(x) {
  if (is.raw(x)) return(cli::hash_raw_sha256(x))
  x = as_utf8(as.character(x))
  out = rep(NA_character_, length(x))
  ok = !is.na(x)
  if (any(ok)) out[ok] = cli::hash_sha256(x[ok])
  out
}

#' XXH128 of an R object (rlang::hash(), 32 hex)
#' @noRd
hash_xxh128 = function(x) {
  rlang::hash(x)
}

#' XXH128 of file contents (rlang::hash_file(), 32 hex)
#' @noRd
hash_file = function(path) {
  rlang::hash_file(path)
}

#' JSON with object keys sorted by radix order at every level: byte-identical in every locale
#' @noRd
canonical_json = function(x) json_encode(json_utf8(x, sort = TRUE))

#' Per-process salt for identifiers (derived from the session, never from the RNG)
#' @noRd
id_salt = function() {
  if (is.null(the$id_salt)) {
    the$id_salt = paste(tempdir(), R.home(), Sys.getpid(), proc.time()[["elapsed"]])
  }
  the$id_salt
}

#' An RNG-free identifier: `prefix` followed by `n` lower-case hex digits (IC-20, IC-61)
#' @noRd
id_new = function(prefix = "", n = 10L) {
  check_string(prefix, "prefix", empty = TRUE)
  n = check_number(n, "n", min = 1, max = 64, int = TRUE)
  the$id_count = the$id_count + 1
  seed = paste(
    format(Sys.time(), "%Y%m%d%H%M%OS6"), Sys.getpid(), the$id_count, id_salt()
  )
  paste0(prefix, substr(cli::hash_sha256(seed), 1L, n))
}

#' An 8-hex entry id not in `taken` (12 hex after 100 collisions)
#' @noRd
id_entry = function(taken = NULL) {
  n = 8L
  tries = 0L
  repeat {
    id = id_new("", n)
    if (!(id %in% taken)) return(id)
    tries = tries + 1L
    if (tries >= 100L) n = 12L
  }
}

#' A block id: 6 hex with at least one letter a-f, grown by 2 up to 16 on each collision
#' @noRd
id_block = function(taken = character()) {
  n = 6L
  repeat {
    id = id_new("", n)
    if (!grepl("[a-f]", id)) next
    if (!(id %in% taken)) return(id)
    n = min(n + 2L, 16L)
  }
}

#' Evaluate `expr` and restore (or remove) .Random.seed afterwards (a leaf function) (IC-61)
#'
#' For third-party code that draws from R's RNG in the user's process (chromote, shiny, httpuv).
#' @noRd
with_seed_preserved = function(expr) {
  env = globalenv()
  old_seed = get0(".Random.seed", envir = env, inherits = FALSE)
  on.exit({
    if (!is.null(old_seed)) {
      env[[".Random.seed"]] = old_seed
    } else if (exists(".Random.seed", envir = env, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = env)
    }
  }, add = TRUE)
  expr
}

#' RNG-free candidate ports in 49152-65535 from identifier hash bits (IC-61)
#' @noRd
port_candidates = function(n = 20L) {
  n = check_number(n, "n", min = 1, max = 16384, int = TRUE)
  ports = integer()
  while (length(ports) < n) {
    hex = cli::hash_sha256(paste(id_new("", 16L), seq_len(n)))
    ports = unique(c(ports, 49152L + strtoi(substr(hex, 1L, 4L), 16L) %% 16384L))
  }
  ports[seq_len(n)]
}

#' Cheap content fingerprint of an object (a leaf function)
#'
#' Hashes the type, length, the object's address, attribute and column addresses and up to 64
#' sampled values, without copying the object, expanding compact row names or materialising
#' ALTREP sequences. Returns one 64-hex string.
#' @noRd
fingerprint = function(x) {
  parts = c(typeof(x), length(x), rlang::obj_address(x))
  if (is.data.frame(x)) {
    parts = c(parts, "nrow", .row_names_info(x, 2L))
    for (name in c("names", "class")) {
      parts = c(parts, name, rlang::obj_address(attr(x, name, exact = TRUE)))
    }
  } else if (!is.environment(x) && !isS4(x)) {
    attrs = attributes(x)
    for (name in names(attrs)) {
      parts = c(parts, name, rlang::obj_address(attrs[[name]]))
    }
  }
  if (is.list(x)) {
    for (i in seq_len(min(length(x), 1000L))) {
      element = .subset2(x, i)
      parts = c(parts, typeof(element), length(element), rlang::obj_address(element))
      if (i <= 20L && is.atomic(element)) parts = c(parts, fingerprint_sample(element))
    }
  } else if (is.atomic(x)) {
    parts = c(parts, fingerprint_sample(x))
  }
  cli::hash_sha256(paste(parts, collapse = "|"))
}

#' Up to 64 evenly spaced values of an atomic vector, as text (a leaf function)
#' @noRd
fingerprint_sample = function(x) {
  n = length(x)
  if (!n) return(character())
  idx = if (n <= 64) seq_len(n) else unique(as.integer(round(seq(1, n, length.out = 64))))
  values = .subset(x, idx)
  if (is.character(values)) values = as_utf8(values)
  paste(as.character(values), collapse = ",")
}
