# perm-classify.R -- gptr_risk(): the advisory static classifier (P11).
#
# Adapted from report 18 Appendix A.1 (b1_classifier.R, 101/101 verified cases), report G5
# g5_classify.R (command, SQL and Python classifiers, 46/46 cases; fact-check 20: edits parity
# for mkdir/touch/mv/cp), report G6 section 3.8 (secret rules, through P03's secret_scan()) and
# G7 section 3.4 (the shared target walk, code_targets(), IC-31). Amended by contract IC-53
# (control category), IC-54 (level 1 for unlisted non-base functions, risky-package floor,
# control and instructions path classes, plan allowlist) and architecture section 6.8.1 (reads
# outside the project are level 1, network reads level 2). It NEVER evaluates the code it
# classifies and is not a security boundary.

risk_labels = c("read-only", "local", "mutating", "dangerous", "critical")
risk_base_pkgs = c("base", "stats", "utils", "methods", "graphics", "grDevices", "tools")

# A file-local cache: the merged risk tables keyed by registry generation and the content of the
# risk_rule records, and the object sizes keyed by address (numbers only, never the objects;
# copy-safety R1).
risk_state = new.env(parent = emptyenv())

# ---- risk tables --------------------------------------------------------------------------

#' The merged risk table: the shipped CSV plus additive risk_rule records (contract 11.15)
#'
#' `kind = "functions"` is `inst/extdata/risk-functions.csv` plus `risk_rule` records with
#' `target = "function"`; `kind = "commands"` is `risk-commands.csv` plus `target = "command"`
#' records. Cached until the registry generation or the content of the risk_rule records
#' changes (a record registered again under the same name with other rows is seen).
#' @noRd
risk_table = function(kind = c("functions", "commands")) {
  kind = check_choice(kind, c("functions", "commands"), "kind")
  target = if (identical(kind, "functions")) "function" else "command"
  rules = tryCatch(registry_all("risk_rule"), error = function(e) list())
  rules = Filter(function(r) identical(r[["target"]] %||% "function", target), rules)
  gen = tryCatch(registry_generation(), error = function(e) 0L)
  key = paste(gen, hash_xxh128(lapply(rules, function(r) {
    list(r[["name"]], r[["rows"]], isTRUE(r[["lower"]]))
  })))
  hit = risk_state[[kind]]
  if (!is.null(hit) && identical(hit$key, key)) return(hit$tab)
  file = if (identical(kind, "functions")) "risk-functions.csv" else "risk-commands.csv"
  base = risk_read_csv(system.file("extdata", file, package = "gptr"))
  tab = risk_table_merge(base, rules, kind)
  if (identical(kind, "functions")) tab = risk_index_functions(tab)
  assign(kind, list(key = key, tab = tab), envir = risk_state)
  tab
}

#' Read one shipped risk CSV (all columns character, level integer)
#' @noRd
risk_read_csv = function(path) {
  df = utils::read.csv(path, colClasses = "character", na.strings = character(),
                       strip.white = TRUE, encoding = "UTF-8", check.names = FALSE)
  df$level = as.integer(df$level)
  df
}

#' Merge risk_rule records into a table: the highest level wins unless `lower = TRUE`
#'
#' A row that wins over a shipped row replaces only the cells it supplies (a column of its record,
#' not NA in that row), so a rule that raises `saveRDS()` keeps the shipped category and path
#' argument.
#' @noRd
risk_table_merge = function(base, rules, kind) {
  cols = if (identical(kind, "functions")) {
    c("package", "function", "level", "category", "path_arg", "note")
  } else {
    c("command", "subcommand", "level", "category", "note")
  }
  key_cols = cols[1:2]
  for (spec in rules) {
    rows = risk_rule_rows(spec, cols)
    if (is.null(rows) || !nrow(rows)) next
    given = attr(rows, "given")
    unset = attr(rows, "unset")
    lower = isTRUE(spec[["lower"]])
    for (i in seq_len(nrow(rows))) {
      k = which(base[[key_cols[1]]] == rows[[key_cols[1]]][i] &
                  base[[key_cols[2]]] == rows[[key_cols[2]]][i])
      if (length(k)) {
        k = k[1L]
        if (lower || rows$level[i] > base$level[k]) {
          set = given[!unset[i, given]]
          base[k, set] = rows[i, set, drop = FALSE]
        }
      } else {
        base = rbind(base, rows[i, cols, drop = FALSE])
      }
    }
  }
  rownames(base) = NULL
  base
}

#' Rows of one risk_rule spec (its `rows` data frame, contract 10.2 row 33) in table columns
#'
#' Command rows may omit `subcommand`, as a column or as an NA cell (then `*`); missing and NA
#' text cells become "" and factors text. Rows without a level or a key are dropped. The
#' attribute `given` names the columns the record supplies; `unset` is the logical matrix of
#' the cells that were NA before blanking, which a merge leaves alone.
#' @noRd
risk_rule_rows = function(spec, cols) {
  src = spec[["rows"]]
  if (!is.data.frame(src) || !nrow(src)) return(NULL)
  n = nrow(src)
  command = identical(cols[1L], "command")
  if (command && is.null(src[["subcommand"]])) src[["subcommand"]] = rep("*", n)
  if (!all(cols[1:3] %in% names(src))) return(NULL)
  given = intersect(cols, names(src))
  out = lapply(cols, function(cl) {
    v = src[[cl]]
    if (is.null(v)) v = rep("", n)
    if (is.factor(v)) v = as.character(v)
    v
  })
  names(out) = cols
  out = as.data.frame(out, stringsAsFactors = FALSE, optional = TRUE)
  names(out) = cols
  out$level = as.integer(out$level)
  for (cl in setdiff(cols, "level")) out[[cl]] = as.character(out[[cl]])
  if (command) out$subcommand[is.na(out$subcommand)] = "*"
  keep = !is.na(out$level) & !is.na(out[[cols[1L]]]) & !is.na(out[[cols[2L]]])
  out = out[keep, , drop = FALSE]
  unset = is.na(out)
  for (cl in setdiff(cols, c("level", cols[1:2]))) out[[cl]][unset[, cl]] = ""
  attr(out, "given") = given
  attr(out, "unset") = unset
  out
}

#' Attach lookup indexes to the functions table
#'
#' A `*` makes a glob only in rows of packages outside base R: base's `*` (multiplication) and
#' `%*%` rows are exact names, never a package-wide wildcard or a `%...%` glob. The anchored
#' regular expressions of the glob rows are compiled once here.
#' @noRd
risk_index_functions = function(tab) {
  glob = grepl("*", tab[["function"]], fixed = TRUE) & !tab$package %in% risk_base_pkgs
  exact = tab[!glob, , drop = FALSE]
  globs = tab[glob, , drop = FALSE]
  globs$fn_re = vapply(globs[["function"]], risk_glob_re, character(1), USE.NAMES = FALSE)
  globs$pkg_re = vapply(globs$package, risk_glob_re, character(1), USE.NAMES = FALSE)
  structure(tab, exact = split(seq_len(nrow(exact)), exact[["function"]]), exact_rows = exact,
            globs = globs)
}

#' Convert a table glob (only `*` is special) to an anchored regular expression
#' @noRd
risk_glob_re = function(glob) {
  g = gsub("([.+^$(){}|\\[\\]\\\\?])", "\\\\\\1", glob, perl = TRUE)
  paste0("^", gsub("*", ".*", g, fixed = TRUE), "$")
}

#' Look up one function in the risk table
#'
#' `pkg` is the package the call resolved to, or NA when it did not resolve. Exact rows win,
#' then function globs of the package (`geom_*`), then package-wide rows (`targets::*`, the
#' risky-package floor of IC-54). Returns a one-row list or NULL.
#' @noRd
risk_lookup = function(fn, pkg = NA_character_, tab = risk_table("functions")) {
  exact = attr(tab, "exact_rows")
  idx = attr(tab, "exact")[[fn]]
  if (length(idx)) {
    rows = exact[idx, , drop = FALSE]
    if (!is.na(pkg)) {
      hit = rows[rows$package == pkg, , drop = FALSE]
      if (nrow(hit)) return(as.list(hit[1L, ]))
    } else {
      base_hit = rows[rows$package %in% risk_base_pkgs, , drop = FALSE]
      if (nrow(base_hit)) return(as.list(base_hit[1L, ]))
      return(as.list(rows[which.max(rows$level), ]))
    }
  }
  globs = attr(tab, "globs")
  if (nrow(globs)) {
    cols = setdiff(names(globs), c("fn_re", "pkg_re"))
    fn_glob = globs[globs[["function"]] != "*", , drop = FALSE]
    ok = vapply(seq_len(nrow(fn_glob)), function(i) {
      grepl(fn_glob$fn_re[i], fn, perl = TRUE) &&
        (is.na(pkg) || grepl(fn_glob$pkg_re[i], pkg, perl = TRUE))
    }, logical(1))
    if (any(ok)) return(as.list(fn_glob[which(ok)[1L], cols]))
    if (!is.na(pkg)) {
      pk = globs[globs[["function"]] == "*", , drop = FALSE]
      ok = vapply(pk$pkg_re, function(re) grepl(re, pkg, perl = TRUE), logical(1),
                  USE.NAMES = FALSE)
      if (any(ok)) {
        row = as.list(pk[which(ok)[1L], cols])
        row[["function"]] = fn
        return(row)
      }
    }
  }
  NULL
}
