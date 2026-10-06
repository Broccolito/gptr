#!/usr/bin/env python3
"""build_index.py -- machine-readable CROSS-PLAN INDEX for the gptr 1.0 implementation plans.

Parses every plan file dev/plan/P*.md (writing-plans format), attributes every fenced code block to
the file it belongs to, analyses every R block with R's own parser (Rscript --vanilla, getParseData;
the R half is embedded below as R_ANALYZER and written next to the outputs on every run), and writes

    <out>/index.json   complete index (plans, tasks, files, blocks, definitions, calls, names, findings)
    <out>/index.md     per-plan counts and every automatic finding with plan, task and line references

Usage:
    python3 build_index.py [--plan-dir DIR] [--spec-dir DIR] [--repo DIR] [--out DIR] [--quiet]

Defaults: the repository that holds this script as --repo and a new temporary directory as --out.
Nothing outside --out is written. Spec and plan files are only read.
"""

import argparse
import collections
import datetime
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.normpath(os.path.join(HERE, "../../../.."))

# --------------------------------------------------------------------------------------------
# R half (written to <out>/build_index_rparse.R and run with Rscript --vanilla)
# --------------------------------------------------------------------------------------------

R_ANALYZER = r'''
# build_index_rparse.R -- R side of build_index.py (rewritten by build_index.py on every run;
# edit the copy embedded in build_index.py, not this file).
#
# Usage: Rscript --vanilla build_index_rparse.R <blocks.json> <out.json>
# Input: {"blocks": [{"id": ..., "code": ...}], "lookup": ["name", ...]}
# Output: {"blocks": [...per block analysis...], "external": {...}}

strval = function(s) {
  out = tryCatch(eval(str2lang(s)), error = function(e) NULL)
  ok = is.character(out) && length(out) == 1L && !is.na(out) && validUTF8(out)
  if (ok) out else gsub("^[\"'`]|[\"'`]$", "", s)
}

roxygen_above = function(src, line1) {
  out = character()
  j = line1 - 1L
  while (j >= 1L && grepl("^\\s*#'", src[j])) {
    out = c(src[j], out)
    j = j - 1L
  }
  I(out)
}

str_mapping = function(rhs) {
  if (!is.call(rhs)) return(NULL)
  head = rhs[[1]]
  if (!(identical(head, as.name("c")) || identical(head, as.name("list")))) return(NULL)
  n = length(rhs) - 1L
  if (n < 1L) return(NULL)
  nms = names(rhs)
  if (is.null(nms)) return(NULL)
  vals = character(n)
  for (j in seq_len(n)) {
    v = tryCatch(rhs[[j + 1L]], error = function(e) NULL)
    if (!is.character(v) || length(v) != 1L || !nzchar(nms[j + 1L])) return(NULL)
    vals[j] = v
  }
  as.list(stats::setNames(vals, nms[-1L]))
}

analyze = function(code) {
  exprs = tryCatch(
    withCallingHandlers(parse(text = code, keep.source = TRUE, encoding = "UTF-8"),
                        warning = function(w) invokeRestart("muffleWarning")),
    error = function(e) e
  )
  if (inherits(exprs, "error")) return(list(ok = FALSE, error = conditionMessage(exprs)))
  src = strsplit(code, "\n", fixed = TRUE)[[1]]
  n_top = length(exprs)
  empty = list(ok = TRUE, toplevel = list(), calls = list(), symbols = list(), strings = list(),
               locals = list(), style = list(left_assign = I(integer()), magrittr = I(integer()),
                                             triple_colon = I(integer()), right_assign = I(integer())))
  if (n_top == 0L) return(empty)
  pd = utils::getParseData(exprs, includeText = TRUE)
  if (is.null(pd) || nrow(pd) == 0L) return(empty)
  pd = pd[order(pd$line1, pd$col1, -pd$line2, -pd$col2), , drop = FALSE]
  id = pd$id
  par = pd$parent
  tok = pd$token
  txt = pd$text
  ln = pd$line1
  nr = nrow(pd)
  kids = split(seq_len(nr), factor(par, levels = unique(par)))
  children = function(pid) {
    k = kids[[as.character(pid)]]
    if (is.null(k)) integer() else k
  }
  row_of = function(i) match(i, id)

  par_map = stats::setNames(par, id)
  anc = id
  repeat {
    p = par_map[as.character(anc)]
    move = !is.na(p) & p > 0
    if (!any(move)) break
    anc[move] = p[move]
  }
  top_rows = which(par == 0 & tok != "COMMENT")
  top_ids = id[top_rows]
  srcrefs = attr(exprs, "srcref")
  if (length(top_ids) != n_top) {
    starts = vapply(seq_len(n_top), function(i) srcrefs[[i]][[1]], 0L)
    top_ids = id[top_rows][match(starts, ln[top_rows])]
  }
  scope = match(anc, top_ids)

  toplevel = lapply(seq_len(n_top), function(i) {
    e = exprs[[i]]
    sr = srcrefs[[i]]
    info = list(i = i, line1 = sr[[1]], line2 = sr[[3]], kind = "call", name = NULL)
    if (is.call(e)) info$head = paste(deparse(e[[1]]), collapse = "")
    is_assign = is.call(e) && length(e) == 3L &&
      (identical(e[[1]], as.name("=")) || identical(e[[1]], as.name("<-")) ||
         identical(e[[1]], as.name("<<-")))
    if (is_assign && (is.name(e[[2]]) || is.character(e[[2]]))) {
      info$name = as.character(e[[2]])
      info$assign_op = as.character(e[[1]])
      rhs = e[[3]]
      if (is.call(rhs) && identical(rhs[[1]], as.name("function"))) {
        info$kind = "fn"
        f = rhs[[2]]
        info$formals = if (is.null(f)) list() else lapply(seq_along(f), function(j) {
          list(name = names(f)[j],
               default = if (identical(f[[j]], quote(expr = ))) NULL else
                 paste(deparse(f[[j]], width.cutoff = 500L), collapse = " "))
        })
      } else {
        info$kind = "obj"
        info$rhs_head = if (is.call(rhs)) paste(deparse(rhs[[1]]), collapse = "") else class(rhs)[1]
        info$mapping = tryCatch(str_mapping(rhs), error = function(e) NULL)
        lit = tryCatch(paste(deparse(rhs, width.cutoff = 500L), collapse = " "), error = function(e) "")
        if (nchar(lit) <= 200L && !grepl("function", lit, fixed = TRUE)) info$literal = lit
      }
    }
    info$roxygen = roxygen_above(src, sr[[1]])
    info
  })

  simple_text = function(r) {
    s = tryCatch(utils::getParseText(pd, id[r]), error = function(e) "<expr>")
    s = paste(s, collapse = " ")
    if (nchar(s) > 60) s = paste0(substr(s, 1, 57), "...")
    s
  }

  callee_of = function(r) {
    ks = children(id[r])
    if (length(ks) < 2L || tok[ks[1]] != "expr") return(NA_integer_)
    if (!any(tok[ks] == "'('")) return(NA_integer_)
    fk = children(id[ks[1]])
    w = fk[tok[fk] == "SYMBOL_FUNCTION_CALL"]
    if (length(w)) w[1] else NA_integer_
  }

  call_args = function(call_id, frow, depth = 0L) {
    ks = children(call_id)
    ks = ks[ks != frow]
    out = list()
    cur = list(name = NULL, v = NULL)
    seen_open = FALSE
    had_comma = FALSE
    for (k in ks) {
      t = tok[k]
      if (t == "'('" && !seen_open) {
        seen_open = TRUE
        next
      }
      if (!seen_open) next
      if (t == "')'") break
      if (t == "','") {
        out[[length(out) + 1L]] = describe_arg(cur, depth)
        cur = list(name = NULL, v = NULL)
        had_comma = TRUE
        next
      }
      if (t == "SYMBOL_SUB") {
        cur$name = gsub("^`|`$", "", txt[k])
        next
      }
      if (t == "STR_CONST") {
        cur$name = strval(txt[k])
        next
      }
      if (t == "EQ_SUB") next
      cur$v = k
    }
    if (!is.null(cur$name) || !is.null(cur$v) || had_comma) {
      out[[length(out) + 1L]] = describe_arg(cur, depth)
    }
    out
  }

  describe_arg = function(cur, depth) {
    a = list(name = cur$name)
    if (is.null(cur$v)) {
      a$kind = "empty"
      return(a)
    }
    v = cur$v
    vk = children(id[v])
    if (length(vk) == 1L) {
      t1 = tok[vk]
      if (t1 == "STR_CONST") {
        a$kind = "str"
        a$str = strval(txt[vk])
      } else if (t1 == "SYMBOL") {
        a$kind = "sym"
        a$sym = txt[vk]
      } else if (t1 == "NUM_CONST") {
        a$kind = "num"
        a$text = txt[vk]
      } else if (t1 == "NULL_CONST") {
        a$kind = "null"
      } else {
        a$kind = "other"
      }
      return(a)
    }
    fr = callee_of(v)
    if (!is.na(fr)) {
      a$kind = "call"
      a$callfn = txt[fr]
      if (depth < 1L && txt[fr] %in% c("c", "list", "I", "structure", "alist")) {
        a$inner = call_args(id[v], row_of(par_map[[as.character(id[fr])]]), depth + 1L)
      }
      return(a)
    }
    if (any(tok[vk] == "FUNCTION") || any(tok[vk] == "'\\\\'")) {
      a$kind = "fun"
      return(a)
    }
    a$kind = "other"
    a
  }

  # ancestor call chain of every row (nearest first, at most 8 callee names; "~" for formulas)
  prow = match(par, id)
  callee_name = rep(NA_character_, nr)
  for (r in which(tok %in% c("expr", "equal_assign", "expr_or_assign_or_help"))) {
    fr = callee_of(r)
    if (!is.na(fr)) callee_name[r] = gsub("^`|`$", "", txt[fr])
  }
  tl_rows = match(unique(par[tok == "'~'"]), id)
  tl_rows = tl_rows[!is.na(tl_rows)]
  callee_name[tl_rows] = ifelse(is.na(callee_name[tl_rows]), "~", callee_name[tl_rows])
  depth = rep(0L, nr)
  cur = prow
  while (any(!is.na(cur))) {
    depth[!is.na(cur)] = depth[!is.na(cur)] + 1L
    cur = prow[cur]
  }
  chain = vector("list", nr)
  for (r in order(depth)) {
    p = prow[r]
    base = if (is.na(p)) character() else chain[[p]]
    own = callee_name[r]
    chain[[r]] = if (is.na(own)) base else utils::head(c(own, base), 8L)
  }

  fc_rows = which(tok == "SYMBOL_FUNCTION_CALL")
  calls = lapply(fc_rows, function(r) {
    frow = row_of(par[r])
    call_id = par[frow]
    crow = prow[frow]
    anc = if (is.na(crow) || is.na(prow[crow])) character() else chain[[prow[crow]]]
    fk = children(par[r])
    ftoks = tok[fk]
    pkg = NULL
    ns_op = NULL
    member = FALSE
    obj = NULL
    if (any(ftoks == "SYMBOL_PACKAGE")) {
      pkg = txt[fk[ftoks == "SYMBOL_PACKAGE"][1]]
      ns_op = txt[fk[ftoks %in% c("NS_GET", "NS_GET_INT")][1]]
    }
    if (any(ftoks %in% c("'$'", "'@'"))) {
      member = TRUE
      obj = simple_text(fk[1])
    }
    args = if (is.na(call_id) || call_id <= 0) list() else call_args(call_id, frow)
    list(fn = gsub("^`|`$", "", txt[r]), line = ln[r], scope = scope[r], pkg = pkg, ns = ns_op,
         member = member, obj = obj, args = args, anc = I(anc))
  })

  loc_rows = integer()
  loc_names = character()
  w = which(tok == "SYMBOL_FORMALS")
  loc_rows = c(loc_rows, w)
  loc_names = c(loc_names, txt[w])
  lhs_rows = integer()
  member_defs = list()
  for (r in which(tok %in% c("EQ_ASSIGN", "LEFT_ASSIGN", "RIGHT_ASSIGN"))) {
    sib = children(par[r])
    pos = match(r, sib)
    target = if (tok[r] == "RIGHT_ASSIGN") sib[pos + 1L] else sib[pos - 1L]
    if (is.na(target)) next
    tk = children(id[target])
    if (length(tk) == 1L && tok[tk] %in% c("SYMBOL", "STR_CONST")) {
      lhs_rows = c(lhs_rows, tk)
      loc_rows = c(loc_rows, r)
      loc_names = c(loc_names, gsub("^[\"'`]|[\"'`]$", "", txt[tk]))
    } else if (length(tk) == 3L && tok[tk[2]] %in% c("'$'", "'@'") &&
               tok[tk[3]] %in% c("SYMBOL", "STR_CONST")) {
      member_defs[[length(member_defs) + 1L]] = list(
        name = gsub("^[\"'`]|[\"'`]$", "", txt[tk[3]]), line = ln[tk[3]], scope = scope[tk[3]])
    }
  }
  for (r in which(tok == "forcond")) {
    fk = children(id[r])
    s = fk[tok[fk] == "SYMBOL"]
    if (length(s)) {
      loc_rows = c(loc_rows, s[1])
      loc_names = c(loc_names, txt[s[1]])
    }
  }
  loc_scope = scope[loc_rows]
  locals = lapply(seq_len(n_top), function(i) I(unique(loc_names[!is.na(loc_scope) & loc_scope == i])))

  sym_rows = which(tok == "SYMBOL")
  sym_rows = setdiff(sym_rows, lhs_rows)
  keep = vapply(sym_rows, function(r) length(children(par[r])) == 1L, TRUE)
  sym_rows = sym_rows[keep]
  symbols = list()
  if (length(sym_rows)) {
    sym_df = data.frame(text = txt[sym_rows], scope = scope[sym_rows], line = ln[sym_rows],
                        stringsAsFactors = FALSE)
    sym_df = sym_df[!duplicated(sym_df[, c("text", "scope")]), , drop = FALSE]
    symbols = lapply(seq_len(nrow(sym_df)), function(k) {
      list(text = sym_df$text[k], scope = sym_df$scope[k], line = sym_df$line[k])
    })
  }

  str_rows = which(tok == "STR_CONST")
  str_vals = vapply(txt[str_rows], strval, "", USE.NAMES = FALSE)
  interesting = grepl(
    "^(gptr[._][A-Za-z0-9_.]+|[A-Z][A-Z0-9]*(_[A-Z0-9]+)+|gptr_(error|warning|message)_[a-z0-9_]+)$",
    str_vals)
  strings = lapply(which(interesting), function(k) {
    list(value = str_vals[k], line = ln[str_rows[k]], scope = scope[str_rows[k]])
  })

  style = list(
    left_assign = I(ln[tok == "LEFT_ASSIGN" & txt == "<-"]),
    right_assign = I(ln[tok == "RIGHT_ASSIGN"]),
    magrittr = I(ln[tok == "SPECIAL" & txt == "%>%"]),
    triple_colon = I(ln[tok == "NS_GET_INT"])
  )
  list(ok = TRUE, toplevel = toplevel, calls = calls, symbols = symbols, strings = strings,
       locals = locals, style = style, member_defs = member_defs)
}

base_pkgs = c("base", "stats", "utils", "methods", "tools", "grDevices", "graphics")

fun_formals = function(f) {
  if (!is.function(f)) return(NULL)
  fm = if (is.primitive(f)) {
    a = args(f)
    if (is.null(a)) return(NULL)
    formals(a)
  } else {
    formals(f)
  }
  if (is.null(fm)) return(I(character()))
  I(names(fm))
}

external_info = function(results, lookup, dep_pkgs) {
  bare = character()
  nsd = character()
  for (r in results) {
    if (!isTRUE(r$ok)) next
    for (cl in r$calls) {
      if (isTRUE(cl$member)) next
      if (is.null(cl$pkg)) {
        bare = c(bare, cl$fn)
      } else {
        nsd = c(nsd, paste0(cl$pkg, cl$ns, cl$fn))
      }
    }
  }
  bare = unique(c(bare, unlist(lookup)))
  nsd = unique(nsd)
  exports = lapply(stats::setNames(base_pkgs, base_pkgs), function(p) getNamespaceExports(p))
  tt = if (requireNamespace("testthat", quietly = TRUE)) getNamespaceExports("testthat") else character()
  bare_info = list()
  for (nm in bare) {
    found = NULL
    for (p in base_pkgs) {
      if (nm %in% exports[[p]]) {
        found = p
        break
      }
    }
    in_tt = nm %in% tt
    if (is.null(found) && !in_tt) next
    f = if (!is.null(found)) get(nm, envir = asNamespace(found)) else get(nm, envir = asNamespace("testthat"))
    bare_info[[nm]] = list(pkg = found, testthat = in_tt, formals = fun_formals(f))
  }
  ns_info = list()
  for (q in nsd) {
    m = regmatches(q, regexec("^([A-Za-z0-9.]+)(:::?)(.+)$", q))[[1]]
    if (length(m) != 4L) next
    pkg = m[2]
    fn = m[4]
    inst = suppressWarnings(suppressMessages(requireNamespace(pkg, quietly = TRUE)))
    if (!inst) {
      ns_info[[q]] = list(installed = FALSE)
      next
    }
    ns = asNamespace(pkg)
    exported = fn %in% getNamespaceExports(pkg)
    exists_in = exported || exists(fn, envir = ns, inherits = FALSE)
    f = if (exported) {
      tryCatch(getExportedValue(pkg, fn), error = function(e) NULL)
    } else if (exists_in) {
      get(fn, envir = ns)
    } else {
      NULL
    }
    ns_info[[q]] = list(installed = TRUE, exported = exported, exists = exists_in,
                        is_function = is.function(f),
                        formals = if (is.function(f)) fun_formals(f) else NULL)
  }
  generics = c(names(.knownS3Generics), .S3PrimitiveGenerics,
               tryCatch(tools:::.get_internal_S3_generics(), error = function(e) character()))
  for (p in base_pkgs) {
    ns = asNamespace(p)
    for (nm in exports[[p]]) {
      f = get0(nm, envir = ns, inherits = FALSE)
      if (is.function(f) && !is.primitive(f)) {
        b = tryCatch(deparse(body(f), nlines = 30L), error = function(e) "")
        if (any(grepl("UseMethod(", b, fixed = TRUE))) generics = c(generics, nm)
      }
    }
  }
  dep_exports = list()
  for (p in unlist(dep_pkgs)) {
    if (suppressWarnings(suppressMessages(requireNamespace(p, quietly = TRUE)))) {
      dep_exports[[p]] = getNamespaceExports(p)
    }
  }
  lookup_pkgs = list()
  for (nm in unique(unlist(lookup))) {
    hits = names(dep_exports)[vapply(dep_exports, function(e) nm %in% e, TRUE)]
    if (length(hits)) lookup_pkgs[[nm]] = I(hits)
  }
  list(bare = bare_info, ns = ns_info, generics = I(sort(unique(generics))),
       lookup_pkgs = lookup_pkgs, dep_installed = I(names(dep_exports)),
       testthat_exports = I(sort(tt)),
       withr_exports = I(if (requireNamespace("withr", quietly = TRUE)) sort(getNamespaceExports("withr")) else character()),
       r_version = R.version.string)
}

main = function() {
  args = commandArgs(trailingOnly = TRUE)
  input = jsonlite::fromJSON(args[[1]], simplifyVector = FALSE)
  blocks = input$blocks
  out = vector("list", length(blocks))
  for (k in seq_along(blocks)) {
    b = blocks[[k]]
    r = tryCatch(analyze(b$code), error = function(e) {
      list(ok = FALSE, error = paste("analyzer failure:", conditionMessage(e)))
    })
    r$id = b$id
    out[[k]] = r
  }
  ext = external_info(out, input$lookup, input$dep_pkgs)
  res = list(blocks = out, external = ext)
  json = jsonlite::toJSON(res, auto_unbox = TRUE, null = "null", digits = NA)
  con = file(args[[2]], open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(as.character(json)), con, useBytes = TRUE)
}

main()
'''

# --------------------------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------------------------

FENCE_OPEN_RE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([^\s`]*)(.*)$")
FENCE_CLOSE_RE = re.compile(r"^\s*(`{3,}|~{3,})\s*$")
TASK_RE = re.compile(r"^#{2,4}\s+Task\s+(\d+)\s*[:.]\s*(.*?)\s*$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
STEP_RE = re.compile(r"^\s*-\s*\[[ xX]\]\s*\*\*Step\s+(\d+)\s*[:.]?\s*(.*?)\*\*")
BACKTICK_RE = re.compile(r"`([^`]+)`")
FILE_ACTIONS = ["Create", "Modify", "Test", "Delete", "Generated", "Generate", "Append", "Remove",
                "Rename", "Move", "Update", "Run", "Read", "Replace", "Overwrite"]
FILE_ACTION_RE = re.compile(r"(?<![\w`])(" + "|".join(FILE_ACTIONS) + r")\s*(?:\([^)]*\))?\s*:")
ROOT_FILES = {"DESCRIPTION", "NAMESPACE", "LICENSE", "LICENSE.md", "NEWS.md", "README.md", "README.Rmd",
              ".lintr", ".Rbuildignore", ".gitignore", ".Rprofile", "_pkgdown.yml", "cran-comments.md",
              "CRAN-SUBMISSION", "CLAUDE.md", "AGENTS.md", "gptr.Rproj", "codemeta.json"}
PATH_EXT_RE = re.compile(
    r"\.(R|r|Rmd|qmd|md|json|jsonl|csv|tsv|yaml|yml|txt|Rd|html|js|css|py|sh|sse|ipynb|orig|lintr|"
    r"Rbuildignore|gitignore|Rprofile|rds|png|svg|toml|xml|Rproj|ndjson|bat|ps1|cmd|log)$")
CALL_CATS = {"R", "test", "helper", "setup", "fixture", "test-entry", "unknown", "dev", "scratch", "inst",
             "vignette", "other"}
TESTISH = {"test", "helper", "setup", "fixture", "test-entry"}
HELPER_NAME_RE = re.compile(r"^(fake_|local_|expect_|with_fake|mock_|skip_if_no_|helper_)|^(expect_no_copy|local_mock_server)$")
EXTRA_GENERICS = {"knit_print", ".DollarNames", "vec_ptype2", "vec_cast", "vec_ptype_abbr", "vec_ptype_full",
                  "vec_proxy", "vec_restore", "obj_sum", "type_sum", "pillar_shaft", "tbl_sum", "as_tibble",
                  "obj_print_data", "obj_print_footer", "format_glimpse", "print", "format", "summary",
                  "toString", "as.list", "as.character", "as.data.frame", "length", "str", "head", "tail",
                  "all.equal", "c", "rep", "unique", "sort", "rev", "xtfrm", "as.vector", "as.logical",
                  "as.numeric", "as.double", "as.integer", "names", "levels", "dim", "t", "seq", "mean",
                  "median", "quantile", "plot", "update", "merge", "split", "within", "with", "subset",
                  "transform", "aggregate", "as.environment", "close", "open", "cnd_header", "cnd_body",
                  "cnd_footer", "conditionMessage", "conditionCall", "as.POSIXct", "as.Date",
                  "is.na", "anyNA", "Ops", "Math", "Summary", "[", "[[", "$", "[<-", "[[<-", "$<-",
                  "==", "!=", "<", ">", "<=", ">=", "&", "|", "!", "+", "-", "*", "/", "length<-",
                  "names<-", "levels<-", "dimnames<-", "dim<-", "row.names", "row.names<-", "dimnames"}
OPTION_RE = re.compile(r"^gptr\.[a-z][a-z0-9_.]*$")
OPTION_FILE_RE = re.compile(r"\.(R|r|Rmd|md|json|csv|yml|yaml|txt|Rproj|rds)$")
ENVVAR_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
ENVVAR_MENTION_RE = re.compile(r"^(GPTR|TYPESAFE|JEV)_[A-Z0-9_]+$")
COND_RE = re.compile(r"^gptr_(error|warning|message)_[a-z0-9_]+$")

# semantic arguments: callee -> list of (formal, category, prefix, role)
SEMANTIC_ARGS = {
    "getOption": [("x", "option", "", "read")],
    "gptr_opt": [("name", "option", "gptr.", "read")],
    "setting_get": [("key", "setting", "", "read")],
    "Sys.getenv": [("x", "envvar", "", "read")],
    "Sys.unsetenv": [("x", "envvar", "", "unset")],
    "gptr_abort": [("class", "condition", "gptr_error_", "raise")],
    "gptr_warn": [("class", "condition", "gptr_warning_", "raise")],
    "gptr_inform": [("class", "condition", "gptr_message_", "raise")],
    "ev_dispatch": [("event", "event", "", "dispatch")],
    "gptr_on": [("event", "event", "", "handle")],
    "ev_semantics": [("event", "event", "", "read")],
    "ev_check_name": [("event", "event", "", "read")],
    "ev_row": [("event", "event", "", "define")],
    "ev_new": [("type", "stream_event", "", "emit")],
    "run_emit": [("type", "stream_event", "", "emit")],
    "session_emit": [("type", "stream_event", "", "emit")],
    "subagent_emit": [("type", "stream_event", "", "emit")],
    "adp_emit": [("type", "stream_event", "", "emit")],
    "artifact_emit": [("type", "stream_event", "", "emit")],
    "ext_service_get": [("name", "service", "", "use")],
    "ext_service_has": [("name", "service", "", "use")],
    "ext_service_try": [("name", "service", "", "use")],
    "ext_service_set": [("name", "service", "", "provide")],
    "gptr_spec": [("kind", "registry_kind", "", "spec")],
    "spec_new": [("kind", "registry_kind", "", "spec")],
}
BASE_FORMALS_FALLBACK = {"getOption": ["x", "default"], "Sys.getenv": ["x", "unset", "names"],
                         "Sys.unsetenv": ["x"]}
OPTION_SETTERS = {"options", "local_options", "with_options", "local_gptr_options"}
ENV_SETTERS = {"Sys.setenv", "local_envvar", "with_envvar"}
MOCKERS = {"local_mocked_bindings", "with_mocked_bindings"}
LATE_REF_FUNS = {"ns_fun": "late", "exists": "late", "get0": "late", "do.call": "call", "match.fun": "call",
                 "getExportedValue": "late"}
INACTIVE_ROLES = {"old", "reference"}
FOREIGN_NAMES = {"repr", "len", "setsid", "ceil", "json.loads", "json.dumps", "isinstance", "JSON.parse",
                 "JSON.stringify", "subprocess.run", "os.environ"}
SPEC_CONSTRUCTORS = {"gptr_tool": "tool", "gptr_provider": "provider", "gptr_adapter": "adapter",
                     "gptr_router": "router", "gptr_hook": "hook", "gptr_policy": "policy", "gptr_agent": "agent",
                     "gptr_command": "command", "gptr_prompt_section": "prompt_section",
                     "gptr_context_block": "context_block", "gptr_backend": "backend"}
NAMESPACE_DIRECTIVES = {"S3method", "export", "importFrom", "S4method", "useDynLib", "exportPattern", "exportClasses",
                        "exportMethods", "import"}
REGISTRY_KIND_FUNS = {"gptr_registry", "gptr_spec", "spec_new", "kind_get", "kind_validator"}
DEP_PKGS = ["jsonlite", "curl", "processx", "callr", "rlang", "cli", "yaml", "ps", "testthat", "withr",
            "knitr", "rmarkdown", "later", "httpuv", "openssl", "shiny", "bslib", "chromote", "ragg",
            "rstudioapi", "reticulate", "DBI", "duckdb", "RSQLite", "data.table", "vctrs", "stringi", "magick",
            "keyring", "codetools", "R6", "pkgload", "devtools", "roxygen2", "lintr", "styler"]
QUOTERS = {"quote", "bquote", "expression", "substitute", "alist", "expr", "exprs", "quo", "quos", "~",
           "enquote", "deparse_call"}
DSL_HOSTS = {"peter"}
DELIBERATE_MISSING_RE = re.compile(r"(not_exist|nonexist|no_such|does_not|undefined|bogus|nope|missing_fn|"
                                   r"not_a_|unknown_fn|fake_missing)")
TYPE_NOTATION = {"chr", "lgl", "int", "num", "dbl", "df", "fn", "env", "raw", "cpl", "tbl", "vec", "list",
                 "lst", "dfr", "named", "chr_or_null"}
SOURCE_FUNS = {"source", "sys.source", "test_path", "file.path", "system.file", "testthat::test_path"}


CATEGORY_HELP = {
    "dup_function_cross_plan": "a top-level R/ function defined by more than one plan (signatures shown)",
    "dup_function_in_plan_files": "one plan defines the same R/ function in two files",
    "redefined_in_plan": "one plan defines an R/ function twice in the same file without a replace instruction",
    "dup_test_helper": "a helper-*.R/setup.R function defined twice (all helpers are sourced together)",
    "helper_shadows_package_fn": "a test helper has the name of a package function",
    "test_shadows_package_fn": "a test-file function has the name of a package function",
    "test_redefines_sourced_fixture_fn": "a test file defines a function that a fixture it sources also defines",
    "file_created_multi": "a file is created ('Create:' in Files or a 'Create `f`:' block) by more than one plan",
    "file_created_twice_in_plan": "one plan has two 'Create `f`:' blocks for the same file",
    "file_modified_never_created": "a block appends to/replaces in a file no plan creates and the repo lacks",
    "ordering_file": "a plan modifies a file created only by a plan outside its dependency closure",
    "ordering_call": "a call to a function defined only in plans outside the caller's 05 dependency closure",
    "ordering_value_ref": "a function used as a value (not called) defined only outside the closure",
    "ordering_mock": "local_mocked_bindings() of a function defined only outside the closure",
    "mock_undefined": "local_mocked_bindings() of a function no plan defines in R/",
    "bad_arg_name": "a named argument that is not a formal of the plan-defined callee (callee has no ...)",
    "too_many_args": "more positional arguments than the plan-defined callee accepts",
    "partial_arg_match": "a named argument that only partially matches a formal",
    "bad_arg_name_external": "a named argument that is not a formal of the installed external function",
    "unknown_external_function": "pkg::fun where the installed pkg has no such function",
    "unexported_external_function": "pkg::fun where fun is not exported",
    "call_not_visible": "a test calls a function defined only in another test/fixture file it does not source",
    "R_calls_test_only_function": "package code calls a function that only test code defines",
    "R_calls_testthat": "package code calls a testthat function",
    "withr_without_prefix": "tests call withr functions without withr:: (withr is not attached)",
    "test_helper_undefined": "a test helper (fake_*, local_*, expect_*, ...) called in tests but defined nowhere",
    "undefined_function": "package code calls a function no plan defines and base R lacks",
    "undefined_function_in_tests": "test code calls a function no plan defines and base R/testthat lack",
    "undefined_function_other": "a dev/scratch/fixture script calls a function defined nowhere (may come from a library())",
    "undefined_function_deliberate": "a call to a function whose name says it is undefined on purpose",
    "needs_pkg_prefix": "package code calls a stats/utils/tools/methods/grDevices/graphics function without pkg::",
    "near_name": "an option/condition/event/... name used in one plan with a near-identical name (edit distance <= 2) "
                 "in other plans",
    "name_not_in_contract": "a name used by package code that 04/03 never mention",
    "service_not_declared": "ext_service_*() with a service name absent from P01's service_plans",
    "service_provider_mismatch": "ext_service_set() from a plan other than the one service_plans names",
    "service_never_provided": "a service_plans entry that no plan's package code sets with ext_service_set()",
    "iface_consumes_undefined": "an Interfaces 'Consumes' function that no plan defines",
    "iface_produces_undefined": "an Interfaces 'Produces' function that no plan defines",
    "iface_produces_elsewhere": "an Interfaces 'Produces' function the plan does not define but another plan does",
    "prose_mentions_undefined": "a backticked fn() in a plan's prose (outside code) that no plan defines (stale name?)",
    "contract_fn_undefined": "a backticked fn() in 04 that no plan defines",
    "iface_signature_mismatch": "an Interfaces signature that disagrees with the definition (warn = named argument, "
                                "order or default; info = positional naming only)",
    "contract_signature_mismatch": "a backticked signature in 04 that disagrees with the final definition",
    "export_missing": "a 04 section 14.1 export that no plan exports",
    "export_wrong_plan": "an export carried by a plan other than the one 04 section 14.1 names",
    "export_not_in_contract": "an @export that is not one of the 63 exports of 04 section 14.1",
    "file_owner_mismatch": "a plan writes an R/ file that 04 section 14 assigns to another plan",
    "file_owner_unlisted": "a plan creates an R/ file that 04 section 14 does not list",
    "depends_header_mismatch": "the plan header's 'Depends on' differs from 05's dependency table",
    "plan_not_in_decomposition": "a plan file missing from 05's dependency table",
    "roxygen_missing": "an R/ function without a roxygen block",
    "roxygen_no_export_or_noRd": "an R/ roxygen block without @export/@noRd/@rdname (would write an Rd page)",
    "roxygen_export_and_noRd": "@export together with @noRd",
    "forbidden_r6": "R6 used",
    "withr_in_package_code": "withr:: in R/",
    "readlines_without_encoding": "readLines() without encoding = 'UTF-8' in R/ (IC-62)",
    "fromjson_simplify": "jsonlite::fromJSON() without simplifyVector = FALSE in R/",
    "forbidden_call_in_R": "library()/require()/set.seed()/sample()/runif()/RNGkind()/randomPort() in R/",
    "bare_enc2utf8": "enc2utf8() in R/ (conventions prefer as_utf8())",
    "style_left_arrow": "`<-` assignment in a code block",
    "style_magrittr_pipe": "`%>%` in a code block",
    "style_triple_colon": "`:::` in R/",
    "style_non_ascii": "non-ASCII character in an R/ block",
    "r_parse_error": "an R block that R cannot parse",
    "block_unattributed": "an R block whose target file could not be determined",
}

METHOD_NOTES = [
    "Plans are parsed with a CommonMark-style fence scanner (nested 4-backtick blocks are content). Each fenced "
    "block is attributed to a file from the paragraph before it ('Create `f`:', 'Append to `f`:', 'In `f`, "
    "replace', ...), else the replaced function's earlier file, else a leading '# R/x.R' comment, else the "
    "task's single R/ or test file. A block followed by a 'with'/'by' paragraph and another block is the old "
    "text of a replacement (role old) and contributes no definitions; 'for reference' blocks likewise.",
    "R blocks are parsed by R itself (parse(keep.source = TRUE) + utils::getParseData() under Rscript --vanilla); "
    "blocks R cannot parse fall back to regular expressions (marked parse_ok = false).",
    "A definition is a top-level `name = function(...)` (or `<-`). S3 methods are names generic.class whose "
    "generic is a base/recommended generic, a known Suggests generic or a plan function calling UseMethod().",
    "Calls are SYMBOL_FUNCTION_CALL tokens; calls inside quote()/bquote()/formulas are data and are skipped; a "
    "name bound locally in the same top-level expression (formal, assignment, for variable) is not a call to a "
    "plan function. Visibility: R/ functions everywhere; helper-*.R/setup.R in tests; a test file's own functions "
    "in that file; a fixture's functions where the file source()s it.",
    "Dependency closure: the transitive closure of 05-plan-decomposition's 'Depends on' column. An ordering "
    "finding is an error when the callee exists only in later plans, a warning for an earlier plan of the same "
    "or a later milestone, info for an earlier milestone or when the call is guarded by exists()/ns_fun().",
    "Argument names are checked with R's matching rules (exact, then partial before `...`, then positional) "
    "against every definition of the callee visible from the caller within its closure; a call is accepted when "
    "it matches any of them.",
    "Option/condition/event/env-var/setting/service/kind names come from literal arguments of getOption(), "
    "gptr_opt(), options()/local_options()/local_gptr_options(), setting_get(), Sys.getenv()/Sys.setenv()/"
    "local_envvar(), gptr_abort()/gptr_warn()/gptr_inform() and ctx$abort(), tryCatch() handler names, "
    "ev_dispatch()/gptr_on()/$on(), ev_new()/*_emit(), ext_service_*(), gptr_spec()/registry_*(kind), plus "
    "string literals shaped like gptr.x, gptr_error_x and GPTR_X.",
]

# --------------------------------------------------------------------------------------------
# small utilities
# --------------------------------------------------------------------------------------------

def as_list(x):
    if x is None:
        return []
    if isinstance(x, list):
        return x
    return [x]


def levenshtein(a, b, cap=3):
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        best = cur[0]
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
            best = min(best, cur[j])
        if best > cap:
            return cap + 1
        prev = cur
    return prev[-1]


def is_path(tok):
    tok = tok.strip()
    if not tok or " " in tok or "(" in tok or tok.startswith("-") or "::" in tok or tok.startswith("http"):
        return False
    if tok.startswith("gptr.") and "/" not in tok:
        return False
    if tok in ROOT_FILES:
        return True
    if "/" in tok and re.match(r"^[\w.$~{}<>*/@-]+$", tok):
        return True
    return bool(PATH_EXT_RE.search(tok)) and re.match(r"^[\w.$~{}<>*/@-]+$", tok) is not None


def norm_path(p):
    p = p.strip()
    if p.startswith("./"):
        p = p[2:]
    return p


def category_of(path):
    if path is None:
        return "unknown"
    p = path
    if p.startswith("$") or p.startswith("/tmp") or "TMPDIR" in p or p.startswith("/private/tmp"):
        return "scratch"
    if re.match(r"^R/[^/]+\.[Rr]$", p):
        return "R"
    if re.match(r"^tests/testthat/test-[^/]+\.[Rr]$", p):
        return "test"
    if re.match(r"^tests/testthat/helper[^/]*\.[Rr]$", p):
        return "helper"
    if re.match(r"^tests/testthat/setup[^/]*\.[Rr]$", p):
        return "setup"
    if p == "tests/testthat.R":
        return "test-entry"
    if p.startswith("tests/"):
        return "fixture" if re.search(r"\.[Rr]$", p) else "test-data"
    if p.startswith("dev/"):
        return "dev"
    if p.startswith("inst/"):
        return "inst"
    if p.startswith("vignettes/"):
        return "vignette"
    return "other"


def strip_parens(text):
    out, depth = [], 0
    for ch in text:
        if ch == "(":
            depth += 1
            continue
        if ch == ")":
            depth = max(0, depth - 1)
            continue
        if depth == 0:
            out.append(ch)
    return "".join(out)


def plan_ids_in(text):
    ids = set()
    for a, b in re.findall(r"P(\d\d)\s*(?:-|\.\.|–)\s*P(\d\d)", text):
        for k in range(int(a), int(b) + 1):
            ids.add("P%02d" % k)
    text2 = re.sub(r"P\d\d\s*(?:-|\.\.|–)\s*P\d\d", " ", text)
    for a in re.findall(r"\bP(\d\d)\b", text2):
        ids.add("P%02d" % int(a))
    return ids


def split_top_commas(s):
    parts, depth, cur, quote = [], 0, [], None
    for ch in s:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur.append(ch)
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur).strip())
    return parts


def parse_sig_text(args_text):
    """'message, class, ..., .data = NULL' -> list of (name, default|None); None if not declaration-like."""
    out = []
    for part in split_top_commas(args_text):
        if part in ("...", "…"):
            out.append(("...", None))
            continue
        m = re.match(r"^([A-Za-z.][\w.]*)\s*(?:=\s*(.*))?$", part, re.S)
        if not m:
            return None
        out.append((m.group(1), m.group(2).strip() if m.group(2) is not None else None))
    return out


def extract_fn_mentions(text):
    """Backticked `fn(args)` mentions -> list of (name, args_text) with balanced parentheses."""
    res = []
    for m in BACKTICK_RE.finditer(text):
        tok = m.group(1).strip()
        mm = re.match(r"^([A-Za-z.][\w.]*)\s*\((.*)$", tok, re.S)
        if not mm:
            continue
        name, rest = mm.group(1), mm.group(2)
        depth, end = 1, None
        for k, ch in enumerate(rest):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    end = k
                    break
        args = rest[:end] if end is not None else rest
        prefix = text[max(0, m.start() - 3):m.start()]
        res.append((name, args.strip(), m.start()))
    return res


def norm_default(s, consts=None):
    """Canonical text of a default value: quotes, spaces, integer suffixes, numbers in e-notation, option
    shorthands (`gptr.x` == gptr_opt("x") == getOption("gptr.x", ...)) and named constants."""
    if s is None:
        return None
    s = s.strip().replace("\\|", "|").replace("'", '"')
    s = re.sub(r"\s+", "", s)
    if consts:
        m = re.match(r"^([A-Za-z.][\w.]*)$", s)
        if m and m.group(1) in consts:
            s = re.sub(r"\s+", "", consts[m.group(1)])
        m = re.match(r'^([A-Za-z.][\w.]*)\[\["(\w+)"\]\]$', s)
        if m and m.group(1) in consts:
            mm = re.search(r"\b%s=([^,()]+)" % re.escape(m.group(2)), re.sub(r"\s+", "", consts[m.group(1)]))
            if mm:
                s = mm.group(1)
    s = re.sub(r'^gptr_opt\("([\w.]+)"\)$', r"gptr.\1", s)
    s = re.sub(r'^getOption\("(gptr\.[\w.]+)"(,.*)?\)$', r"\1", s)
    s = re.sub(r"(\d+)L\b", r"\1", s)
    try:
        f = float(s)
        s = repr(f)
    except ValueError:
        pass
    return s


def defaults_equal(text_default, def_default, consts=None):
    a, b = norm_default(text_default, consts), norm_default(def_default, consts)
    if a == b:
        return True
    # match.arg(): the effective default of c("a", "b") is "a"
    m = re.match(r'^c\(("[^"]*")', b or "")
    if m and a == m.group(1):
        return True
    return False


# --------------------------------------------------------------------------------------------
# spec parsing (05 dependency table, 04 contract lists)
# --------------------------------------------------------------------------------------------

def parse_decomposition(path):
    deps, titles, milestones = {}, {}, {}
    if not os.path.exists(path):
        return deps, titles, milestones
    lines = open(path, encoding="utf-8").read().split("\n")
    in_tab = False
    for l in lines:
        if l.startswith("| Plan | Title | Milestone | Depends on"):
            in_tab = True
            continue
        if in_tab:
            if not l.startswith("|"):
                if deps:
                    break
                continue
            cells = [c.strip() for c in l.strip().strip("|").split("|")]
            if len(cells) < 4 or not re.match(r"^P\d\d$", cells[0]):
                continue
            pid = cells[0]
            titles[pid] = cells[1]
            milestones[pid] = cells[2]
            d = cells[3]
            deps[pid] = sorted(plan_ids_in(d)) if d not in ("-", "none", "") else []
    return deps, titles, milestones


def closure_of(pid, deps):
    seen, stack = set(), list(deps.get(pid, []))
    while stack:
        q = stack.pop()
        if q in seen:
            continue
        seen.add(q)
        stack.extend(deps.get(q, []))
    return seen


def section_text(lines, start_pat, level):
    """Text of the section whose heading matches start_pat, until the next heading of level <= level."""
    out, on = [], False
    for l in lines:
        m = HEADING_RE.match(l)
        if m and on and len(m.group(1)) <= level:
            break
        if m and re.search(start_pat, m.group(2)) and len(m.group(1)) == level:
            on = True
            out.append(l)
            continue
        if on:
            out.append(l)
    return out


def table_first_col_tokens(lines, col=0):
    toks = []
    for l in lines:
        if not l.startswith("|") or l.startswith("|---") or l.startswith("| ---"):
            continue
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) <= col:
            continue
        toks.extend(BACKTICK_RE.findall(cells[col]))
    return toks


def parse_contract(spec_dir):
    c = {"exports": {}, "owners": {}, "conditions": set(), "options": set(), "envvars": set(),
         "events": set(), "kinds": set(), "backticked": set(), "fn_mentions": [], "available": False}
    p04 = os.path.join(spec_dir, "04-interface-contract.md")
    p03 = os.path.join(spec_dir, "03-architecture.md")
    if not os.path.exists(p04):
        return c
    c["available"] = True
    text04 = open(p04, encoding="utf-8").read()
    lines04 = text04.split("\n")
    text03 = open(p03, encoding="utf-8").read() if os.path.exists(p03) else ""
    alltext = text04 + "\n" + text03
    # inline code is matched line by line outside fenced blocks (a fence would pair backticks across
    # lines); quoted strings inside fenced blocks count as mentions too
    bt = set()
    for doc in (text04, text03):
        fence = None
        for l in doc.split("\n"):
            mf = re.match(r"^\s*(`{3,}|~{3,})", l)
            if mf:
                fence = None if fence else mf.group(1)[0]
                continue
            if fence:
                bt.update(re.findall(r'"([^"\s]{1,80})"', l))
                continue
            bt.update(t.strip() for t in BACKTICK_RE.findall(l))
    c["backticked"] = bt
    # 14: owners; 14.1 exports
    sec14 = section_text(lines04, r"^14\. Plans", 2)
    for l in sec14:
        if not l.startswith("| P"):
            continue
        cells = [x.strip() for x in l.strip().strip("|").split("|")]
        pid = cells[0]
        if len(cells) >= 5 and re.match(r"^P\d\d$", pid) and "Owns" not in cells[-1]:
            c["owners"][pid] = [t for t in BACKTICK_RE.findall(cells[-1]) if t.endswith(".R")]
        if len(cells) == 2 and re.match(r"^P\d\d$", pid):
            c["exports"][pid] = BACKTICK_RE.findall(cells[1])
    # 2.2 conditions
    sec22 = section_text(lines04, r"^2\.2 ", 3)
    for t in table_first_col_tokens(sec22, 0):
        if re.match(r"^[a-z0-9_]+$", t):
            c["conditions"].add("gptr_error_" + t)
    for l in sec22:
        if l.startswith("Warnings (") or l.startswith("Messages ("):
            pass
    wtxt = " ".join(sec22)
    mw = re.search(r"Warnings \(`gptr_warning_<name>`\):(.*?)Messages \(", wtxt, re.S)
    if mw:
        for t in BACKTICK_RE.findall(mw.group(1)):
            if re.match(r"^[a-z0-9_]+$", t):
                c["conditions"].add("gptr_warning_" + t)
    mm = re.search(r"Messages \(`gptr_message_<name>`\):(.*?)(Transport, adapter|$)", wtxt, re.S)
    if mm:
        for t in BACKTICK_RE.findall(mm.group(1)):
            if re.match(r"^[a-z0-9_]+$", t):
                c["conditions"].add("gptr_message_" + t)
    for t in re.findall(r"gptr_(?:error|warning|message)_[a-z0-9_]+", alltext):
        c["conditions"].add(t)
    # options and env vars anywhere
    for t in bt:
        if re.match(r"^gptr\.[a-z][a-z0-9_.]*$", t):
            c["options"].add(t.rstrip("."))
    for t in c["backticked"]:
        if ENVVAR_RE.match(t) and "_" in t:
            c["envvars"].add(t)
    # events (10.4 table first column) and kinds (10.2 second column); plus any backticked mention
    sec104 = section_text(lines04, r"^10\.4 ", 3)
    c["events"] = set(t for t in table_first_col_tokens(sec104, 0) if re.match(r"^[a-z_0-9]+$", t))
    sec102 = section_text(lines04, r"^10\.2 ", 3)
    c["kinds"] = set(t for t in table_first_col_tokens(sec102, 1) if re.match(r"^[a-z_0-9]+$", t))
    # function mentions with a declaration-like argument list, by section
    cur_sec = ""
    for ln_no, l in enumerate(lines04, 1):
        m = HEADING_RE.match(l)
        if m:
            cur_sec = m.group(2)
            continue
        for name, args, _ in extract_fn_mentions(l):
            c["fn_mentions"].append({"name": name, "args": args, "line": ln_no, "section": cur_sec[:60]})
    return c


# --------------------------------------------------------------------------------------------
# plan markdown parsing
# --------------------------------------------------------------------------------------------

def collect_labelled_block(lines, i):
    """Lines of a **Files:** / **Interfaces:** block starting at line i; returns (lines, next_index)."""
    n = len(lines)
    out = [lines[i]]
    j = i + 1
    header_only = re.match(r"^\*\*[^*]+:\*\*\s*$", lines[i].strip()) is not None
    while j < n:
        s = lines[j]
        if s.strip() == "":
            k = j + 1
            while k < n and lines[k].strip() == "":
                k += 1
            if header_only and len(out) == 1 and k < n and re.match(r"^\s*-\s+(?!\[)", lines[k]):
                j = k
                continue
            break
        if s.startswith("**") or re.match(r"^\s*-\s*\[[ xX]\]", s) or HEADING_RE.match(s) or \
                FENCE_OPEN_RE.match(s) and s.strip().startswith(("```", "~~~")):
            break
        out.append(s)
        j += 1
    return out, j


def parse_files_block(raw_lines):
    text = "\n".join(raw_lines)
    text = re.sub(r"^\*\*Files:\*\*", "", text.strip())
    entries = []
    matches = list(FILE_ACTION_RE.finditer(text))
    if not matches:
        for t in BACKTICK_RE.findall(text):
            if is_path(t):
                entries.append({"action": "unspecified", "path": norm_path(t), "note": "", "create": False})
        return entries
    for k, m in enumerate(matches):
        seg_end = matches[k + 1].start() if k + 1 < len(matches) else len(text)
        seg = text[m.end():seg_end]
        action = m.group(1)
        toks = list(BACKTICK_RE.finditer(seg))
        depth_at = []
        dpt = 0
        for ch in seg:
            depth_at.append(dpt)
            if ch == "(":
                dpt += 1
            elif ch == ")":
                dpt = max(0, dpt - 1)
        for q, tm in enumerate(toks):
            t = tm.group(1)
            if not is_path(t) or t.endswith("/") or depth_at[tm.start()] > 0:
                continue
            nxt = toks[q + 1].start() if q + 1 < len(toks) else len(seg)
            follow = seg[tm.end():nxt]
            note = ""
            nm = re.match(r"\s*(\([^)]*\))", follow)
            if nm:
                note = nm.group(1)
            create = action == "Create" or (action == "Test" and re.search(r"\(\s*create", note or "", re.I) is not None)
            entries.append({"action": action, "path": norm_path(t), "note": note, "create": bool(create)})
    return entries


def parse_interfaces_block(raw_lines):
    res = {"raw": "\n".join(raw_lines), "consumes": [], "produces": [], "other": []}
    body = list(raw_lines)
    first = re.sub(r"^\*\*Interfaces:\*\*\s*", "", body[0].strip())
    body = ([first] if first else []) + body[1:]
    bullet_mode = any(re.match(r"^\s*-\s+(Consumes|Produces)", l) for l in body)
    if bullet_mode:
        items, cur = [], None
        for l in body:
            if re.match(r"^-\s+", l):
                if cur is not None:
                    items.append(cur)
                cur = [l]
            elif cur is not None:
                cur.append(l)
            elif l.strip():
                items.append([l])
        if cur is not None:
            items.append(cur)
        for it in items:
            t = "\n".join(it)
            s = re.sub(r"^-\s+", "", it[0].strip())
            if s.startswith("Consumes"):
                res["consumes"].append(t)
            elif s.startswith("Produces"):
                res["produces"].append(t)
            else:
                res["other"].append(t)
    else:
        text = "\n".join(body)
        ms = list(re.finditer(r"(?<![\w`])(Consumes|Produces)\b(\s*\([^)]*\))?\s*:", text))
        if not ms:
            res["other"].append(text)
        for k, m in enumerate(ms):
            end = ms[k + 1].start() if k + 1 < len(ms) else len(text)
            seg = text[m.start():end].rstrip()
            (res["consumes"] if m.group(1) == "Consumes" else res["produces"]).append(seg)
    return res


def paragraph_before(lines, s):
    """Paragraph text before line index s (a fence). Returns (text, kind, first_line_idx)."""
    j = s - 1
    while j >= 0 and not lines[j].strip():
        j -= 1
    if j < 0:
        return None, "none", None
    if FENCE_CLOSE_RE.match(lines[j]):
        return None, "after_block", j
    if STEP_RE.match(lines[j]):
        return lines[j].strip(), "step", j
    if HEADING_RE.match(lines[j]):
        return lines[j].strip(), "heading", j
    k = j
    while k > 0 and lines[k - 1].strip() and not FENCE_CLOSE_RE.match(lines[k - 1]) and \
            not HEADING_RE.match(lines[k - 1]) and not STEP_RE.match(lines[k - 1]):
        k -= 1
    return " ".join(x.strip() for x in lines[k:j + 1]), "para", k


def parse_plan(pid, path):
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    n = len(lines)
    plan = {"id": pid, "file": path, "title": "", "header_depends_text": "", "milestone_header": "",
            "tasks": [], "blocks": [], "n_lines": n}
    m = re.match(r"^#\s+(.*)$", lines[0]) if lines else None
    if m:
        plan["title"] = m.group(1).strip()
    for l in lines[:60]:
        if l.startswith("**Depends on:**"):
            plan["header_depends_text"] = l[len("**Depends on:**"):].strip()
            mm = re.search(r"\*\*Milestone:\*\*\s*(\S+)", l)
            if mm:
                plan["milestone_header"] = mm.group(1).rstrip(".")
            break
    hd = plan["header_depends_text"]
    hd_main = re.split(r"\*\*Milestone", hd)[0]
    hd_core = strip_parens(hd_main)
    hd_core = re.split(r";|\.\s|\btransitively\b|\bthrough\b", hd_core)[0]
    plan["header_depends"] = sorted(plan_ids_in(hd_core))
    plan["header_mentions"] = sorted(plan_ids_in(hd_main))

    cur = {"num": 0, "title": "(preamble)", "line": 1, "files": [], "files_raw": "",
           "interfaces": None, "steps": [], "commit_files": [], "section": None}
    plan["tasks"].append(cur)
    in_tasks = False
    step = None
    section = None
    fence = None
    i = 0
    while i < n:
        l = lines[i]
        if fence is not None:
            mc = FENCE_CLOSE_RE.match(l)
            if mc and mc.group(1)[0] == fence["char"] and len(mc.group(1)) >= fence["len"]:
                blk = fence["blk"]
                blk["end_line"] = i + 1
                code_lines = lines[fence["start"] + 1:i]
                ind = fence["indent"]
                if ind:
                    code_lines = [x[ind:] if x[:ind].strip() == "" else x for x in code_lines]
                blk["code"] = "\n".join(code_lines)
                plan["blocks"].append(blk)
                fence = None
            i += 1
            continue
        mo = FENCE_OPEN_RE.match(l)
        if mo and l.strip().startswith(("```", "~~~")) and "`" not in (mo.group(3) + mo.group(4)):
            fence = {"char": mo.group(2)[0], "len": len(mo.group(2)), "start": i, "indent": len(mo.group(1)),
                     "blk": {"plan": pid, "task": cur["num"], "step": step, "section": section,
                             "line": i + 1, "lang": (mo.group(3) or "").lower(), "indent": len(mo.group(1))}}
            i += 1
            continue
        mt = TASK_RE.match(l)
        if mt:
            in_tasks = True
            cur = {"num": int(mt.group(1)), "title": mt.group(2).strip(), "line": i + 1, "files": [],
                   "files_raw": "", "interfaces": None, "steps": [], "commit_files": [], "section": None}
            plan["tasks"].append(cur)
            step = None
            section = None
            i += 1
            continue
        mh = HEADING_RE.match(l)
        if mh:
            level = len(mh.group(1))
            if in_tasks and level <= 3:
                # a non-task heading after the tasks began closes the current task
                section = mh.group(2).strip()
                cur = {"num": None, "title": section, "line": i + 1, "files": [], "files_raw": "",
                       "interfaces": None, "steps": [], "commit_files": [], "section": section}
                plan["tasks"].append(cur)
                step = None
            i += 1
            continue
        ms = STEP_RE.match(l)
        if ms:
            step = int(ms.group(1))
            cur["steps"].append({"num": step, "title": ms.group(2).strip(), "line": i + 1})
            i += 1
            continue
        if l.startswith("**Files:**") and cur["num"] is not None:
            raw, j = collect_labelled_block(lines, i)
            cur["files_raw"] = "\n".join(raw)
            cur["files_line"] = i + 1
            cur["files"] = parse_files_block(raw)
            i = j
            continue
        if l.startswith("**Interfaces:**") and cur["num"] is not None:
            raw, j = collect_labelled_block(lines, i)
            cur["interfaces"] = parse_interfaces_block(raw)
            cur["interfaces"]["line"] = i + 1
            i = j
            continue
        i += 1
    # backticked `fn(...)` mentions in prose (outside fences), with the task they fall in
    plan["prose_mentions"] = []
    task_starts = sorted((t["line"], t["num"]) for t in plan["tasks"])
    fence_c = None
    for ln_no, l in enumerate(lines, 1):
        mf = re.match(r"^\s*(`{3,}|~{3,})", l)
        if mf:
            if fence_c is None:
                fence_c = (mf.group(1)[0], len(mf.group(1)))
            elif mf.group(1)[0] == fence_c[0] and len(mf.group(1)) >= fence_c[1] and l.strip() == mf.group(1):
                fence_c = None
            continue
        if fence_c is not None:
            continue
        tnum = None
        for st, num in task_starts:
            if st <= ln_no:
                tnum = num
        for name, args, _ in extract_fn_mentions(l):
            plan["prose_mentions"].append({"line": ln_no, "task": tnum, "name": name, "args": args[:120]})
    # drop pseudo-tasks without content
    plan["tasks"] = [t for t in plan["tasks"] if t["num"] is not None or
                     any(b["task"] is None and b["section"] == t["section"] for b in plan["blocks"])]
    attribute_blocks(plan, lines)
    return plan


DEF_LINE_RE = re.compile(r"^(`[^`]+`|[A-Za-z.][\w.]*)\s*(?:=|<-)\s*(?:function\b|\\\()", re.M)


def attribute_blocks(plan, lines):
    blocks = plan["blocks"]
    tasks_by_num = {t["num"]: t for t in plan["tasks"] if t["num"] is not None}
    name_file = {}
    last_file_in_task = {}
    for k, b in enumerate(blocks):
        b["id"] = "%s:%d" % (plan["id"], b["line"])
        intro, kind, _ = paragraph_before(lines, b["line"] - 1)
        b["intro"] = intro if intro is None else intro[:600]
        b["intro_kind"] = kind
        # text between this block and the next one
        nb = blocks[k + 1] if k + 1 < len(blocks) else None
        gap_end = (nb["line"] - 1) if nb else min(len(lines), b["end_line"] + 6)
        gap = " ".join(x.strip() for x in lines[b["end_line"]:gap_end] if x.strip())
        b["_gap_after"] = gap
        b["role"] = "code"
        b["replaced"] = []
    for k, b in enumerate(blocks):
        nb = blocks[k + 1] if k + 1 < len(blocks) else None
        gap = b["_gap_after"]
        if nb is not None and re.match(r"^(with|by)\b", gap, re.I) and len(gap) < 400 and \
                b["lang"] == nb["lang"]:
            b["role"] = "old"
            nb["role"] = "new"
        intro = (b.get("intro") or "").lower()
        if b["role"] == "code" and re.search(r"\bfor reference\b|no new package code|\bfor illustration\b|"
                                             r"\bexample session\b|manual checklist", intro):
            b["role"] = "reference"
    for k, b in enumerate(blocks):
        intro = b["intro"] or ""
        path, action, method = None, None, None
        if b["role"] == "new" and k > 0:
            prev = blocks[k - 1]
            path, action, method = prev.get("file"), "replace", "inherited-from-old-block"
        if path is None and b["intro_kind"] == "para":
            paths = [norm_path(t) for t in BACKTICK_RE.findall(intro) if is_path(t)]
            low = intro.lower()
            if re.match(r"^(then,?\s+)?create\b", low):
                action = "create"
            elif "append" in low[:80] or low.startswith("add to"):
                action = "append"
            elif "replace the contents of" in low:
                action = "overwrite"
            elif re.search(r"\breplace\b", low):
                action = "replace"
            elif low.startswith("insert"):
                action = "insert"
            elif low.startswith("modify"):
                action = "modify"
            elif low.startswith("save"):
                action = "save"
            else:
                action = "other"
            if paths:
                path, method = paths[0], "intro"
            if action == "replace" or b["role"] == "old":
                b["replaced"] = sorted(set(re.findall(r"`([A-Za-z.][\w.]*)\(\)`", intro)))
            if path is None and b["replaced"]:
                for nm in b["replaced"]:
                    if nm in name_file:
                        path, method = name_file[nm], "replaced-function-lookup"
                        break
        if path is None:
            first = next((x for x in b.get("code", "").split("\n") if x.strip()), "")
            mm = re.match(r"^\s*#+\s*(?:file:\s*)?`?((?:R|tests|inst|dev|vignettes)/[\w./-]+)`?", first)
            if mm:
                path, method = mm.group(1), "leading-comment"
        if path is None and b["task"] is not None and b["task"] in tasks_by_num and b["lang"] == "r":
            t = tasks_by_num[b["task"]]
            code = b.get("code", "")
            istest = "test_that(" in code
            cands = [f["path"] for f in t["files"] if f["action"] in ("Create", "Modify", "Test", "Append")]
            want = [p for p in cands if category_of(p) in (("test",) if istest else ("R",))]
            want = sorted(set(want))
            if len(want) == 1:
                path, method = want[0], "task-files"
            elif b["role"] in ("new", "old") and last_file_in_task.get(b["task"]):
                path, method = last_file_in_task[b["task"]], "task-last-file"
        b["file"] = path
        b["action"] = action or ("create" if path and method == "task-files" else action)
        b["attribution"] = method or "unknown"
        b["category"] = category_of(path)
        if path and b["lang"] == "r":
            last_file_in_task[b["task"]] = path
            for mdef in DEF_LINE_RE.finditer(b.get("code", "")):
                name_file.setdefault(mdef.group(1).strip("`"), path)
    for b in blocks:
        b.pop("_gap_after", None)


def commit_files_from_blocks(plan):
    for b in plan["blocks"]:
        if b["lang"] not in ("bash", "sh", ""):
            continue
        for l in b.get("code", "").split("\n"):
            m = re.match(r"^\s*git add\s+(.*)$", l)
            if m and b["task"] is not None:
                t = next((t for t in plan["tasks"] if t["num"] == b["task"]), None)
                if t is not None:
                    t["commit_files"].extend([x for x in m.group(1).split() if not x.startswith("-")])


# --------------------------------------------------------------------------------------------
# R analysis
# --------------------------------------------------------------------------------------------

def run_r(blocks, lookup, out_dir, quiet, reuse=False):
    rfile = os.path.join(out_dir, "build_index_rparse.R")
    with open(rfile, "w", encoding="utf-8") as fh:
        fh.write(R_ANALYZER.lstrip("\n"))
    inp = os.path.join(out_dir, ".build_index_blocks.json")
    outp = os.path.join(out_dir, ".build_index_rparse.json")
    cache = os.path.join(out_dir, ".build_index_rcache.json")
    payload = json.dumps({"blocks": [{"id": b["id"], "code": b["code"]} for b in blocks],
                          "lookup": sorted(lookup), "dep_pkgs": DEP_PKGS})
    key = hashlib.sha256((payload + R_ANALYZER).encode("utf-8")).hexdigest()
    if reuse and os.path.exists(cache):
        try:
            with open(cache, encoding="utf-8", errors="replace") as fh:
                cached = json.load(fh)
            if cached.get("key") == key:
                if not quiet:
                    print("reusing cached R analysis", file=sys.stderr)
                return cached["result"]
        except (OSError, ValueError):
            pass
    with open(inp, "w", encoding="utf-8") as fh:
        fh.write(payload)
    cmd = ["Rscript", "--vanilla", rfile, inp, outp]
    if not quiet:
        print("running:", " ".join(cmd), file=sys.stderr)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit("R analyzer failed")
    with open(outp, encoding="utf-8", errors="replace") as fh:
        res = json.load(fh)
    for p in (inp, outp):
        try:
            os.remove(p)
        except OSError:
            pass
    if reuse:
        with open(cache, "w", encoding="utf-8") as fh:
            json.dump({"key": key, "result": res}, fh)
    return res


def parse_roxygen(lines):
    tags = collections.defaultdict(list)
    title = None
    for l in as_list(lines):
        body = re.sub(r"^\s*#'\s?", "", l)
        m = re.match(r"\s*@(\w+)\s*(.*)$", body)
        if m:
            tags[m.group(1)].append(m.group(2).strip())
        elif title is None and body.strip():
            title = body.strip()
    return dict(tags), title


FALLBACK_CALL_RE = re.compile(r"(?<![\w.$@:])([A-Za-z.][\w.]*)\s*\(")
R_KEYWORDS = {"if", "for", "while", "function", "repeat", "else", "in", "next", "break", "return",
              "switch", "TRUE", "FALSE", "NULL"}


def fallback_analysis(code):
    """Regex analysis for blocks R cannot parse (fragments): definitions and bare calls only."""
    res = {"ok": False, "toplevel": [], "calls": [], "symbols": [], "strings": [], "locals": [],
           "style": {"left_assign": [], "magrittr": [], "triple_colon": [], "right_assign": []}}
    lines = code.split("\n")
    for k, l in enumerate(lines, 1):
        m = re.match(r"^(`[^`]+`|[A-Za-z.][\w.]*)\s*(=|<-)\s*function\s*\((.*)", l)
        if m:
            text = m.group(3)
            j = k
            depth = 1
            acc = ""
            buf = text
            while True:
                for ch in buf:
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    acc += ch
                if depth == 0 or j >= len(lines):
                    break
                buf = lines[j]
                acc += " "
                j += 1
            fm = parse_sig_text(acc) or []
            res["toplevel"].append({"i": len(res["toplevel"]) + 1, "line1": k, "line2": k, "kind": "fn",
                                    "name": m.group(1).strip("`"), "assign_op": m.group(2),
                                    "formals": [{"name": a, "default": d} for a, d in fm],
                                    "roxygen": [], "fallback": True})
        for mc in FALLBACK_CALL_RE.finditer(l):
            if mc.group(1) in R_KEYWORDS:
                continue
            res["calls"].append({"fn": mc.group(1), "line": k, "scope": None, "pkg": None, "ns": None,
                                 "member": False, "obj": None, "args": [], "fallback": True})
        if re.search(r"(?<![<])<-(?!>)", re.sub(r'"[^"]*"', "", l)) and not l.strip().startswith("#"):
            res["style"]["left_assign"].append(k)
        if "%>%" in l:
            res["style"]["magrittr"].append(k)
    return res


# --------------------------------------------------------------------------------------------
# main build
# --------------------------------------------------------------------------------------------

class Builder:
    def __init__(self, args):
        self.args = args
        self.repo = args.repo
        self.plan_dir = args.plan_dir or os.path.join(self.repo, "dev", "plan")
        self.spec_dir = args.spec_dir or os.path.join(self.repo, "dev", "spec")
        self.out_dir = args.out or HERE
        self.findings = []
        self.quiet = args.quiet
        self.scope = plan_ids_in(args.scope)

    def log(self, *a):
        if not self.quiet:
            print(*a, file=sys.stderr)

    # ---------------------------------------------------------------- findings
    def add(self, category, severity, plan, task, line, file, message, **extra):
        f = {"category": category, "severity": severity, "plan": plan, "task": task, "line": line,
             "file": file, "message": message}
        f.update(extra)
        involved = set([plan] if plan else []) | set(extra.get("plans") or [])
        f["out_of_scope"] = bool(involved) and not (involved & self.scope)
        self.findings.append(f)

    # ---------------------------------------------------------------- loading
    def load(self):
        self.deps, self.titles05, self.milestones = parse_decomposition(
            os.path.join(self.spec_dir, "05-plan-decomposition.md"))
        self.contract = parse_contract(self.spec_dir)
        self.plans = {}
        for path in sorted(glob.glob(os.path.join(self.plan_dir, "P*.md"))):
            m = re.match(r"^P(\d\d)", os.path.basename(path))
            if not m:
                continue
            pid = "P" + m.group(1)
            self.log("parsing", os.path.basename(path))
            self.plans[pid] = parse_plan(pid, path)
            commit_files_from_blocks(self.plans[pid])
        self.closure = {pid: closure_of(pid, self.deps) for pid in self.plans}
        self.repo_files = set()
        for root, dirs, files in os.walk(self.repo):
            rel = os.path.relpath(root, self.repo)
            if rel.startswith(("dev", ".git")) and rel != ".":
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in (".git", "dev")]
            for f in files:
                p = os.path.normpath(os.path.join(rel, f))
                self.repo_files.add(p[2:] if p.startswith("./") else p)
        self.blocks = [b for p in self.plans.values() for b in p["blocks"]]
        self.block_by_id = {b["id"]: b for b in self.blocks}

    def ms_index(self, pid):
        m = self.milestones.get(pid) or self.plans.get(pid, {}).get("milestone_header", "")
        mm = re.match(r"M(\d+)", m or "")
        return int(mm.group(1)) if mm else 99

    # ---------------------------------------------------------------- R analysis
    def analyse(self):
        rblocks = [b for b in self.blocks if b["lang"] == "r"]
        lookup = set()
        for p in self.plans.values():
            for t in p["tasks"]:
                itf = t.get("interfaces")
                if not itf:
                    continue
                for seg in itf["consumes"] + itf["produces"]:
                    for name, _, _ in extract_fn_mentions(seg):
                        lookup.add(name)
        for p in self.plans.values():
            for m in p["prose_mentions"]:
                lookup.add(m["name"])
        for m in self.contract["fn_mentions"]:
            lookup.add(m["name"])
        lookup = set(x for x in lookup if re.match(r"^[A-Za-z.][\w.]*$", x))
        res = run_r(rblocks, lookup, self.out_dir, self.quiet, self.args.reuse_r)
        self.ext = res["external"]
        self.ext["generics"] = set(as_list(self.ext.get("generics")))
        self.ext["testthat_exports"] = set(as_list(self.ext.get("testthat_exports")))
        self.ext["withr_exports"] = set(as_list(self.ext.get("withr_exports")))
        self.ext["bare"] = self.ext.get("bare") or {}
        self.ext["ns"] = self.ext.get("ns") or {}
        by_id = {r["id"]: r for r in res["blocks"]}
        for b in rblocks:
            r = by_id.get(b["id"]) or {"ok": False, "error": "missing"}
            if not r.get("ok"):
                fb = fallback_analysis(b["code"])
                fb["error"] = r.get("error")
                r = fb
            b["_r"] = r
            b["parse_ok"] = bool(r.get("ok"))
            b["parse_error"] = r.get("error")

    # ---------------------------------------------------------------- definitions
    def build_definitions(self):
        self.defs = []
        self.objects = []
        plan_generics = set()
        for b in self.blocks:
            r = b.get("_r")
            if not r:
                continue
            off = b["line"]
            calls_by_scope = collections.defaultdict(list)
            for c in as_list(r.get("calls")):
                calls_by_scope[c.get("scope")].append(c)
            for tl in as_list(r.get("toplevel")):
                if tl.get("kind") not in ("fn", "obj") or not tl.get("name"):
                    continue
                tags, title = parse_roxygen(tl.get("roxygen"))
                sc_calls = calls_by_scope.get(tl["i"], [])
                rec = {"name": tl["name"], "plan": b["plan"], "task": b["task"], "step": b["step"],
                       "file": b["file"], "category": b["category"], "line": off + tl["line1"],
                       "line_end": off + tl["line2"], "block": b["id"], "role": b["role"],
                       "assign_op": tl.get("assign_op"), "roxygen_title": title,
                       "tags": {k: v for k, v in tags.items()}, "parse_fallback": bool(tl.get("fallback"))}
                if tl["kind"] == "fn":
                    fml = as_list(tl.get("formals"))
                    rec["formals"] = [f["name"] for f in fml]
                    rec["defaults"] = {f["name"]: f.get("default") for f in fml}
                    rec["signature"] = "%s(%s)" % (tl["name"], ", ".join(
                        f["name"] if f.get("default") is None else "%s = %s" % (f["name"], f["default"])
                        for f in fml))
                    rec["has_dots"] = "..." in rec["formals"]
                    um = [a.get("str") for c in sc_calls if c["fn"] == "UseMethod" and not c.get("pkg")
                          for a in as_list(c.get("args"))[:1] if a.get("kind") == "str"]
                    rec["generic_of"] = um[0] if um else None
                    if um and b["role"] not in INACTIVE_ROLES:
                        plan_generics.add(um[0])
                    fns = set(c["fn"] for c in sc_calls)
                    rec["creates_env"] = bool(fns & {"new.env", "list2env", "new_environment", "env"})
                    classes = []
                    for c in sc_calls:
                        if c["fn"] == "structure":
                            for a in as_list(c.get("args")):
                                if a.get("name") == "class":
                                    if a.get("kind") == "str":
                                        classes.append(a["str"])
                                    for ia in as_list(a.get("inner")):
                                        if ia.get("kind") == "str":
                                            classes.append(ia["str"])
                    rec["classes_set"] = sorted(set(classes))
                    rec["uses_r6"] = "R6Class" in fns
                    rec["env_constructor"] = bool(rec["creates_env"] and (classes or "class" in fns or
                                                  re.search(r"(_new$|^new_|_state$)", tl["name"])))
                    rec["kind"] = "function"
                    self.defs.append(rec)
                else:
                    rec["kind"] = "object"
                    rec["rhs_head"] = tl.get("rhs_head")
                    rec["mapping"] = tl.get("mapping")
                    rec["literal"] = tl.get("literal")
                    self.objects.append(rec)
        self.generics = self.ext["generics"] | EXTRA_GENERICS | plan_generics
        for d in self.defs:
            d["s3"] = None
            t = d["tags"]
            if "method" in t and t["method"]:
                parts = t["method"][0].split()
                if len(parts) == 2:
                    d["s3"] = {"generic": parts[0], "class": parts[1], "how": "@method"}
            if d["s3"] is None and "." in d["name"]:
                nm = d["name"]
                best = None
                for k in range(len(nm)):
                    if nm[k] == "." and k > 0 and nm[:k] in self.generics and nm[k + 1:]:
                        best = (nm[:k], nm[k + 1:])
                if best:
                    d["s3"] = {"generic": best[0], "class": best[1], "how": "name"}
            if d["s3"] is None and "exportS3Method" in t:
                d["s3"] = {"generic": (t["exportS3Method"][0] or "?"), "class": "?", "how": "@exportS3Method"}
            d["export"] = "export" in t and d["s3"] is None
            d["s3_export"] = ("export" in t or "exportS3Method" in t) and d["s3"] is not None
            d["noRd"] = "noRd" in t
            d["rdname"] = t["rdname"][0] if t.get("rdname") else None
        self.fn_defs = collections.defaultdict(list)
        for d in self.defs:
            if d["role"] not in INACTIVE_ROLES:
                self.fn_defs[d["name"]].append(d)
        self.obj_defs = collections.defaultdict(list)
        for d in self.objects:
            if d["role"] not in INACTIVE_ROLES:
                self.obj_defs[d["name"]].append(d)
        self.constants = {d["name"]: d["literal"] for d in self.objects
                          if d["category"] == "R" and d.get("literal") and d["role"] not in INACTIVE_ROLES}
        # per-file source strings (for fixture visibility)
        self.source_strings = collections.defaultdict(set)
        for b in self.blocks:
            r = b.get("_r")
            if not r or not b["file"]:
                continue
            for c in as_list(r.get("calls")):
                if c["fn"] in ("source", "sys.source", "test_path", "file.path", "system.file", "readLines",
                               "normalizePath", "callr_script", "rscript_path"):
                    for a in as_list(c.get("args")):
                        if a.get("kind") == "str":
                            self.source_strings[b["file"]].add(os.path.basename(a["str"]))
            for s in re.findall(r"[\"']([\w.-]+\.R)[\"']", b.get("code", "")):
                self.source_strings[b["file"]].add(s)

    # ---------------------------------------------------------------- resolution helpers
    def visible(self, d, b):
        dc, bc = d["category"], b["category"]
        if dc == "R":
            return True
        if dc in ("helper", "setup"):
            return bc in TESTISH or bc == "unknown"
        if dc == "test":
            return d["file"] == b["file"]
        if dc == "fixture":
            return d["file"] == b["file"] or os.path.basename(d["file"] or "") in self.source_strings.get(b["file"], set())
        if dc == "unknown":
            return d["block"] == b["id"]
        return d["file"] == b["file"]

    def ok_plans(self, pid):
        return self.closure.get(pid, set()) | {pid}

    def effective_defs(self, name, b):
        cands = [d for d in self.fn_defs.get(name, []) if self.visible(d, b)]
        okp = self.ok_plans(b["plan"])
        eff = [d for d in cands if d["plan"] in okp]
        return cands, (eff or cands)

    @staticmethod
    def match_call(fnames, args):
        dots = "..." in fnames
        before = fnames[:fnames.index("...")] if dots else list(fnames)
        assigned, problems = {}, []
        unmatched = []
        for k, a in enumerate(args):
            nm = a.get("name")
            if nm:
                if nm in fnames and nm != "...":
                    assigned[nm] = k
                else:
                    unmatched.append(k)
        for k in unmatched:
            nm = args[k]["name"]
            cands = [f for f in before if f.startswith(nm) and f not in assigned]
            if len(cands) == 1:
                assigned[cands[0]] = k
                problems.append(("partial", nm, cands[0]))
            elif dots:
                continue
            else:
                problems.append(("unknown", nm, None))
        free = [f for f in before if f not in assigned]
        for k, a in enumerate(args):
            if a.get("name"):
                continue
            if free:
                assigned[free.pop(0)] = k
            elif dots:
                continue
            else:
                problems.append(("too_many", str(k + 1), None))
        return assigned, problems

    # ---------------------------------------------------------------- calls
    def build_calls(self):
        self.calls = []          # resolved calls to plan-defined functions (index.json)
        self.unresolved = []     # calls to names defined nowhere
        self.name_occ = collections.defaultdict(lambda: collections.defaultdict(list))
        self.mocks = []
        self.late_refs = []
        self.value_refs = []
        self.ext_calls_bad = []
        self.dsl_calls = []
        self.quoted_calls = 0
        r_fn_names = set(n for n, ds in self.fn_defs.items() if any(d["category"] == "R" for d in ds))
        # names assigned anywhere in a file (any scope, any block): local objects, not package functions
        self.file_assigned = collections.defaultdict(set)
        for b in self.blocks:
            r = b.get("_r")
            if not r or b["role"] in INACTIVE_ROLES:
                continue
            key = b["file"] or b["id"]
            for tl in as_list(r.get("toplevel")):
                if tl.get("kind") == "obj" and tl.get("name"):
                    self.file_assigned[key].add(tl["name"])
            if b["category"] != "R":
                for loc in as_list(r.get("locals")):
                    self.file_assigned[key].update(as_list(loc))
        for b in self.blocks:
            r = b.get("_r")
            if not r or b["role"] in INACTIVE_ROLES:
                continue
            off = b["line"]
            toplevel = as_list(r.get("toplevel"))
            locals_ = [set(as_list(x)) for x in as_list(r.get("locals"))]
            code_lines = b["code"].split("\n")

            def scope_info(sc):
                if sc is None or not isinstance(sc, int) or sc < 1 or sc > len(toplevel):
                    return "<block>", set(), None
                tl = toplevel[sc - 1]
                loc = locals_[sc - 1] if sc - 1 < len(locals_) else set()
                nm = tl.get("name")
                if nm:
                    loc = loc - {nm}
                label = nm or tl.get("head") or "<toplevel>"
                return label, loc, tl

            test_desc = {}
            for c in as_list(r.get("calls")):
                if c["fn"] == "test_that" and c.get("args"):
                    a0 = as_list(c["args"])[0]
                    if a0.get("kind") == "str":
                        test_desc.setdefault(c.get("scope"), a0["str"])
            for c in as_list(r.get("calls")):
                fn = c["fn"]
                line = off + (c.get("line") or 0)
                label, loc, tl = scope_info(c.get("scope"))
                if label == "test_that" and c.get("scope") in test_desc:
                    label = "test_that: " + test_desc[c["scope"]][:80]
                args = as_list(c.get("args"))
                anc = as_list(c.get("anc"))
                if set(anc) & QUOTERS:
                    # quoted code (quote(), bquote(), formulas ...) is data, not a call
                    self.quoted_calls += 1
                    continue
                self.semantic_names(b, c, line, args)
                if c.get("member") or fn == ".":
                    continue
                pkg = c.get("pkg")
                if pkg and pkg != "gptr":
                    self.check_external_ns(b, c, line, args)
                    continue
                if fn in loc:
                    continue
                if fn in MOCKERS:
                    self.handle_mock(b, c, line, args, label)
                if fn in LATE_REF_FUNS and args and args[0].get("kind") == "str":
                    tgt = args[0]["str"]
                    if tgt in self.fn_defs:
                        self.late_refs.append({"plan": b["plan"], "task": b["task"], "file": b["file"],
                                               "line": line, "via": fn, "target": tgt,
                                               "target_plans": sorted(set(d["plan"] for d in self.fn_defs[tgt]))})
                cands, eff = self.effective_defs(fn, b)
                if not cands:
                    allc = self.fn_defs.get(fn, [])
                    if allc and fn not in self.ext["bare"]:
                        self.add_not_visible(b, fn, line, allc, label)
                        continue
                    if fn in self.obj_defs or fn in self.file_assigned.get(b["file"] or b["id"], set()):
                        continue
                    if set(anc) & DSL_HOSTS and fn not in self.ext["bare"]:
                        self.dsl_calls.append({"plan": b["plan"], "task": b["task"], "file": b["file"],
                                               "line": line, "fn": fn, "host": sorted(set(anc) & DSL_HOSTS)})
                        continue
                    self.resolve_external_bare(b, c, fn, line, args, label)
                    continue
                guarded = self.is_guarded(code_lines, tl, fn)
                rec = {"caller_plan": b["plan"], "caller_task": b["task"], "caller_file": b["file"],
                       "caller_category": b["category"], "line": line, "caller": label, "callee": fn,
                       "callee_plans": sorted(set(d["plan"] for d in cands)),
                       "args_named": [a.get("name") for a in args if a.get("name")],
                       "n_positional": sum(1 for a in args if not a.get("name")),
                       "args": [[a.get("name") or "", a.get("kind"),
                                 (a.get("str") if a.get("kind") == "str" else
                                  a.get("sym") if a.get("kind") == "sym" else
                                  a.get("callfn") if a.get("kind") == "call" else None)] for a in args],
                       "kind": "call", "guarded": guarded}
                self.calls.append(rec)
                self.check_ordering(b, rec, cands, guarded)
                if b["category"] == "R" and all(d["category"] != "R" for d in cands):
                    self.add("R_calls_test_only_function", "error", b["plan"], b["task"], line, b["file"],
                             "package code calls %s(), which is defined only in test code (%s)" % (
                                 fn, ", ".join(sorted(set("%s %s" % (d["plan"], d["file"]) for d in cands)))))
                if not c.get("fallback"):
                    self.check_args(b, fn, line, args, eff, label)
            # value references (functions passed as values)
            for s in as_list(r.get("symbols")):
                nm = s["text"]
                if nm not in r_fn_names:
                    continue
                label, loc, tl = scope_info(s.get("scope"))
                if nm in loc or (tl and tl.get("name") == nm):
                    continue
                if nm in self.file_assigned.get(b["file"] or b["id"], set()):
                    continue
                cands = [d for d in self.fn_defs[nm] if self.visible(d, b)]
                if not cands:
                    continue
                rec = {"caller_plan": b["plan"], "caller_task": b["task"], "caller_file": b["file"],
                       "caller_category": b["category"], "line": off + s["line"], "caller": label,
                       "callee": nm, "callee_plans": sorted(set(d["plan"] for d in cands)), "kind": "ref"}
                self.value_refs.append(rec)
                okp = self.ok_plans(b["plan"])
                if not (set(rec["callee_plans"]) & okp) and b["category"] in ({"R"} | TESTISH):
                    self.add("ordering_value_ref", "warn", b["plan"], b["task"], rec["line"], b["file"],
                             "%s (in %s) refers to function %s as a value; it is defined only in %s, "
                             "outside %s's dependency closure" % (label, b["file"], nm,
                                                                ", ".join(rec["callee_plans"]), b["plan"]))
            # string mentions (options, env vars, conditions)
            for s in as_list(r.get("strings")):
                v = s["value"]
                ln = off + s["line"]
                if OPTION_RE.match(v) and not OPTION_FILE_RE.search(v):
                    self.occ("option", v, b, ln, "mention", "literal")
                elif COND_RE.match(v):
                    self.occ("condition", v, b, ln, "mention", "literal")
                elif ENVVAR_MENTION_RE.match(v):
                    self.occ("envvar", v, b, ln, "mention", "literal")
            # style
            st = r.get("style") or {}
            if b["category"] in ("R", "test", "helper", "setup", "fixture", "test-entry", "unknown", "dev",
                                 "scratch", "inst", "vignette", "other"):
                for ln in as_list(st.get("left_assign")):
                    self.add("style_left_arrow", "warn", b["plan"], b["task"], off + ln, b["file"],
                             "left-arrow assignment `<-` in a code block (house style is `=`)")
                for ln in as_list(st.get("magrittr")):
                    self.add("style_magrittr_pipe", "warn", b["plan"], b["task"], off + ln, b["file"],
                             "magrittr pipe `%>%` in a code block (house style is `|>`)")
                if b["category"] == "R":
                    for ln in as_list(st.get("triple_colon")):
                        self.add("style_triple_colon", "warn", b["plan"], b["task"], off + ln, b["file"],
                                 "`:::` in package code")
            if b["category"] == "R":
                for k, l in enumerate(code_lines, 1):
                    if any(ord(ch) > 127 for ch in l):
                        self.add("style_non_ascii", "warn", b["plan"], b["task"], off + k, b["file"],
                                 "non-ASCII character in an R/ source line: %s" % l.strip()[:80])

    def is_guarded(self, code_lines, tl, fn):
        if not tl:
            return False
        seg = "\n".join(code_lines[tl["line1"] - 1:tl["line2"]])
        pat = r"(exists|get0|ns_fun|is\.function|existsFunction)\(\s*[\"']%s[\"']" % re.escape(fn)
        return re.search(pat, seg) is not None

    def occ(self, cat, name, b, line, role, via):
        self.name_occ[cat][name].append({"plan": b["plan"], "task": b["task"], "file": b["file"],
                                         "category": b["category"], "line": line, "role": role, "via": via})

    def semantic_names(self, b, c, line, args):
        fn = c["fn"]
        member = c.get("member")
        if member:
            if fn == "on" and args:
                a = args[0]
                if a.get("kind") == "str" and (a.get("name") in (None, "event")):
                    self.occ("event", a["str"], b, line, "handle", "$on")
            if fn in ("abort", "warn", "inform") and len(args) >= 2:
                pref = {"abort": "gptr_error_", "warn": "gptr_warning_", "inform": "gptr_message_"}[fn]
                a = next((x for x in args if x.get("name") == "class"), None)
                if a is None:
                    pos = [x for x in args if not x.get("name")]
                    a = pos[1] if len(pos) >= 2 else None
                if a is not None and a.get("kind") == "str":
                    self.occ("condition", pref + a["str"], b, line, "raise", "$" + fn)
            return
        if c.get("pkg") and c["pkg"] not in ("gptr", "withr", "base"):
            return
        # option and env-var setters (argument names)
        if fn in OPTION_SETTERS:
            prefix = "gptr." if fn == "local_gptr_options" else ""
            for a in args:
                names = [a.get("name")] + [ia.get("name") for ia in as_list(a.get("inner"))]
                for nm in names:
                    if not nm or nm.startswith("."):
                        continue
                    full = nm if nm.startswith("gptr.") or not prefix else prefix + nm
                    if OPTION_RE.match(full):
                        self.occ("option", full, b, line, "set", fn)
        if fn in ENV_SETTERS:
            for a in args:
                names = [a.get("name")] + [ia.get("name") for ia in as_list(a.get("inner"))]
                for nm in names:
                    if nm and ENVVAR_RE.match(nm) and not nm.startswith("."):
                        self.occ("envvar", nm, b, line, "set", fn)
        if fn in ("tryCatch", "withCallingHandlers", "try_fetch"):
            for a in args:
                nm = a.get("name")
                if nm and COND_RE.match(nm):
                    self.occ("condition", nm, b, line, "handle", fn)
        if fn in SPEC_CONSTRUCTORS and not c.get("pkg"):
            self.occ("registry_kind", SPEC_CONSTRUCTORS[fn], b, line, "construct", fn)
        rules = SEMANTIC_ARGS.get(fn)
        fnames = None
        if rules:
            ds = self.fn_defs.get(fn)
            if ds:
                fnames = ds[0]["formals"]
            else:
                bi = self.ext["bare"].get(fn)
                fnames = as_list(bi.get("formals")) if bi else BASE_FORMALS_FALLBACK.get(fn)
        else:
            ds = self.fn_defs.get(fn)
            if ds and (fn.startswith("registry_") or fn in REGISTRY_KIND_FUNS) and \
                    any("kind" in d["formals"] for d in ds):
                fnames = next(d["formals"] for d in ds if "kind" in d["formals"])
                rules = [("kind", "registry_kind", "", "use")]
        if not rules or not fnames:
            return
        assigned, _ = self.match_call(list(fnames), args)
        for formal, cat, prefix, role in rules:
            k = assigned.get(formal)
            if k is None:
                continue
            a = args[k]
            vals = []
            if a.get("kind") == "str":
                vals = [a["str"]]
            elif a.get("kind") == "call" and a.get("callfn") == "c":
                vals = [ia["str"] for ia in as_list(a.get("inner")) if ia.get("kind") == "str"]
            for v in vals:
                name = v if (not prefix or v.startswith(prefix)) else prefix + v
                if cat == "option" and not name.startswith("gptr."):
                    continue
                self.occ(cat, name, b, line, role, fn)

    def handle_mock(self, b, c, line, args, label):
        pkg = next((a.get("str") for a in args if a.get("name") == ".package"), None)
        if pkg and pkg != "gptr":
            return
        for a in args:
            nm = a.get("name")
            if not nm or nm.startswith(".") or nm == "code":
                continue
            cands = [d for d in self.fn_defs.get(nm, []) if d["category"] == "R"]
            rec = {"plan": b["plan"], "task": b["task"], "file": b["file"], "line": line, "mocked": nm,
                   "defined_in": sorted(set(d["plan"] for d in cands))}
            self.mocks.append(rec)
            if not cands and nm not in self.obj_defs:
                self.add("mock_undefined", "error", b["plan"], b["task"], line, b["file"],
                         "%s mocks %s(), which no plan defines in R/ (testthat errors: binding not found)"
                         % (c["fn"], nm))
            elif cands and not (set(rec["defined_in"]) & self.ok_plans(b["plan"])):
                self.add("ordering_mock", "error", b["plan"], b["task"], line, b["file"],
                         "%s mocks %s(), defined only in %s, outside %s's dependency closure"
                         % (c["fn"], nm, ", ".join(rec["defined_in"]), b["plan"]))

    def add_not_visible(self, b, fn, line, allc, label):
        where = sorted(set("%s %s (%s)" % (d["plan"], d["file"], d["category"]) for d in allc))
        if b["category"] == "R":
            self.add("R_calls_test_only_function", "error", b["plan"], b["task"], line, b["file"],
                     "package code calls %s(), defined only in non-package code: %s" % (fn, "; ".join(where)))
        elif b["category"] in TESTISH:
            self.add("call_not_visible", "error", b["plan"], b["task"], line, b["file"],
                     "%s calls %s(), defined only in another test or fixture file that this file does not "
                     "source: %s" % (label, fn, "; ".join(where)))
        else:
            self.add("call_not_visible", "info", b["plan"], b["task"], line, b["file"],
                     "%s calls %s(), defined only in %s" % (label, fn, "; ".join(where)))

    def resolve_external_bare(self, b, c, fn, line, args, label):
        bi = self.ext["bare"].get(fn)
        cat = b["category"]
        if bi:
            pkg = bi.get("pkg")
            if cat == "R" and pkg and pkg != "base":
                self.add("needs_pkg_prefix", "warn", b["plan"], b["task"], line, b["file"],
                         "package code calls %s() from %s without `%s::` (R CMD check NOTE: no visible global "
                         "function definition)" % (fn, pkg, pkg))
            elif cat == "R" and not pkg and bi.get("testthat"):
                self.add("R_calls_testthat", "error", b["plan"], b["task"], line, b["file"],
                         "package code calls testthat's %s() bare" % fn)
            if cat in TESTISH and not pkg and not bi.get("testthat"):
                pass
            if pkg or cat in TESTISH or cat == "unknown":
                if not c.get("fallback"):
                    fm = bi.get("formals")
                    if fm is not None:
                        _, probs = self.match_call(as_list(fm), args)
                        for kind, nm, tgt in probs:
                            if kind == "unknown":
                                self.add("bad_arg_name_external", "error", b["plan"], b["task"], line, b["file"],
                                         "%s(%s = ...): `%s` is not an argument of %s::%s(%s)" % (
                                             fn, nm, nm, pkg or "testthat", fn, ", ".join(as_list(fm))))
                return
        if fn in self.ext["withr_exports"] and cat in TESTISH:
            self.add("withr_without_prefix", "error", b["plan"], b["task"], line, b["file"],
                     "%s calls withr's %s() without `withr::` (withr is not attached in tests)" % (label, fn))
            return
        rec = {"plan": b["plan"], "task": b["task"], "file": b["file"], "category": cat, "line": line,
               "fn": fn, "caller": label}
        self.unresolved.append(rec)

    def check_external_ns(self, b, c, line, args):
        q = "%s%s%s" % (c["pkg"], c.get("ns") or "::", c["fn"])
        info = self.ext["ns"].get(q)
        if not info or not info.get("installed"):
            return
        if not info.get("exists"):
            self.add("unknown_external_function", "error", b["plan"], b["task"], line, b["file"],
                     "%s does not exist in the installed %s" % (q, c["pkg"]))
            return
        if c.get("ns") == "::" and not info.get("exported"):
            self.add("unexported_external_function", "error", b["plan"], b["task"], line, b["file"],
                     "%s is not exported by %s (use of `::` fails)" % (q, c["pkg"]))
        fm = info.get("formals")
        if fm is None or c.get("fallback"):
            return
        _, probs = self.match_call(as_list(fm), args)
        for kind, nm, tgt in probs:
            if kind == "unknown":
                self.add("bad_arg_name_external", "error", b["plan"], b["task"], line, b["file"],
                         "%s(%s = ...): `%s` is not an argument of %s(%s)" % (q, nm, nm, q, ", ".join(as_list(fm))))
            elif kind == "partial":
                self.add("partial_arg_match", "info", b["plan"], b["task"], line, b["file"],
                         "%s(%s = ...) partially matches `%s`" % (q, nm, tgt))

    def check_ordering(self, b, rec, cands, guarded):
        okp = self.ok_plans(b["plan"])
        dplans = set(rec["callee_plans"])
        if dplans & okp:
            return
        if b["category"] not in ({"R", "unknown"} | TESTISH):
            return
        pnum = int(b["plan"][1:])
        later = all(int(p[1:]) > pnum for p in dplans)
        same_ms = any(self.ms_index(p) >= self.ms_index(b["plan"]) for p in dplans)
        acknowledged = bool(dplans & set(self.plans[b["plan"]]["header_mentions"]))
        if guarded:
            sev = "info"
        elif later:
            sev = "error"
        elif same_ms:
            sev = "warn"
        else:
            sev = "info"
        note = []
        if later:
            note.append("defined only in a later plan")
        elif same_ms:
            note.append("earlier plan of the same milestone, not a declared dependency")
        else:
            note.append("earlier milestone, not a declared dependency")
        if acknowledged:
            note.append("the plan header mentions %s" % ", ".join(sorted(dplans & set(self.plans[b["plan"]]["header_mentions"]))))
        if guarded:
            note.append("guarded by an existence check")
        self.add("ordering_call", sev, b["plan"], b["task"], rec["line"], b["file"],
                 "%s calls %s(), defined only in %s, outside %s's dependency closure (%s)" % (
                     rec["caller"], rec["callee"], ", ".join(sorted(dplans)), b["plan"], "; ".join(note)),
                 callee=rec["callee"], callee_plans=sorted(dplans))

    def check_args(self, b, fn, line, args, eff, label):
        if not args:
            return
        results = []
        for d in eff:
            _, probs = self.match_call(d["formals"], args)
            results.append((d, probs))
        if any(not p for _, p in results):
            return
        if any(all(k == "partial" for k, _, _ in p) for _, p in results):
            d, probs = next((d, p) for d, p in results if all(k == "partial" for k, _, _ in p))
            for kind, nm, tgt in probs:
                self.add("partial_arg_match", "warn", b["plan"], b["task"], line, b["file"],
                         "%s calls %s(%s = ...), which only partially matches `%s` of %s [%s %s]" % (
                             label, fn, nm, tgt, d["signature"], d["plan"], d["file"]))
            return
        d, probs = sorted(results, key=lambda x: (x[0]["plan"], x[0]["line"]))[-1]
        sigs = sorted(set("%s [%s T%s %s]" % (dd["signature"], dd["plan"], dd["task"], dd["file"]) for dd, _ in results))
        for kind, nm, tgt in probs:
            if kind == "unknown":
                self.add("bad_arg_name", "error", b["plan"], b["task"], line, b["file"],
                         "%s calls %s(%s = ...): `%s` is not a formal of %s" % (label, fn, nm, nm, " | ".join(sigs)),
                         callee=fn, arg=nm)
            elif kind == "too_many":
                self.add("too_many_args", "error", b["plan"], b["task"], line, b["file"],
                         "%s calls %s() with %d positional arguments; %s" % (
                             label, fn, sum(1 for a in args if not a.get("name")), " | ".join(sigs)),
                         callee=fn)
            elif kind == "partial":
                self.add("partial_arg_match", "warn", b["plan"], b["task"], line, b["file"],
                         "%s calls %s(%s = ...), which only partially matches `%s` of %s" % (
                             label, fn, nm, tgt, " | ".join(sigs)))

    # ---------------------------------------------------------------- finding passes
    def find_duplicates(self):
        by_name = collections.defaultdict(list)
        for d in self.defs:
            if d["role"] in INACTIVE_ROLES:
                continue
            by_name[d["name"]].append(d)
        self.dup_functions = []
        for name, ds in sorted(by_name.items()):
            rds = [d for d in ds if d["category"] == "R"]
            plans = sorted(set(d["plan"] for d in rds))
            if len(plans) > 1:
                sigs = ["%s %s T%s L%d %s: %s%s" % (d["plan"], d["file"], d["task"], d["line"],
                        "replace" if d["role"] in ("new",) or name in self.block_by_id[d["block"]].get("replaced", []) else "def",
                        d["signature"], " (S3 %s.%s)" % (d["s3"]["generic"], d["s3"]["class"]) if d["s3"] else "")
                        for d in sorted(rds, key=lambda x: (x["plan"], x["line"]))]
                distinct_sigs = set(d["signature"] for d in rds)
                files = set(d["file"] for d in rds)
                explicit = all(name in self.block_by_id[d["block"]].get("replaced", []) or d["role"] == "new"
                               for d in rds if d["plan"] != plans[0])
                sev = "error" if (len(distinct_sigs) > 1 or len(files) > 1) and not explicit else "warn"
                if explicit:
                    sev = "info"
                self.dup_functions.append({"name": name, "plans": plans, "definitions": sigs,
                                           "explicit_replacement": explicit})
                first = sorted(rds, key=lambda x: (x["plan"], x["line"]))[-1]
                self.add("dup_function_cross_plan", sev, first["plan"], first["task"], first["line"], first["file"],
                         "%s() defined in %d plans%s: %s" % (
                             name, len(plans), " (later plan says replace)" if explicit else "", " || ".join(sigs)),
                         name=name, plans=plans)
            elif len(rds) > 1:
                files = sorted(set(d["file"] for d in rds))
                p = rds[0]["plan"]
                if len(files) > 1:
                    self.add("dup_function_in_plan_files", "error", p, rds[-1]["task"], rds[-1]["line"], rds[-1]["file"],
                             "%s() defined in %d different files of %s: %s" % (
                                 name, len(files), p, "; ".join("%s T%s L%d" % (d["file"], d["task"], d["line"]) for d in rds)))
                else:
                    unmarked = [d for d in rds[1:] if not (d["role"] == "new" or name in
                                self.block_by_id[d["block"]].get("replaced", []) or
                                self.block_by_id[d["block"]].get("action") in ("replace", "overwrite"))]
                    if unmarked:
                        self.add("redefined_in_plan", "warn", p, unmarked[0]["task"], unmarked[0]["line"], files[0],
                                 "%s() defined %d times in %s of %s without a replace instruction: %s" % (
                                     name, len(rds), files[0], p,
                                     "; ".join("T%s L%d %s" % (d["task"], d["line"], d["signature"]) for d in rds)))
            # helper duplicates (all helper-*.R / setup.R are sourced together)
            hds = [d for d in ds if d["category"] in ("helper", "setup")]
            hfiles = sorted(set((d["plan"], d["file"]) for d in hds))
            if len(set(f for _, f in hfiles)) > 1 or len(set(p for p, _ in hfiles)) > 1:
                sigs = ["%s %s T%s L%d: %s" % (d["plan"], d["file"], d["task"], d["line"], d["signature"]) for d in hds]
                if len(set(d["signature"] for d in hds)) > 1 or len(set(d["file"] for d in hds)) > 1:
                    last = hds[-1]
                    self.add("dup_test_helper", "error", last["plan"], last["task"], last["line"], last["file"],
                             "test helper %s() defined more than once across helper files/plans: %s" % (name, " || ".join(sigs)))
            if rds and hds:
                for h in hds:
                    self.add("helper_shadows_package_fn", "warn", h["plan"], h["task"], h["line"], h["file"],
                             "test helper %s() has the same name as package function(s) in %s" % (
                                 name, ", ".join(sorted(set("%s %s" % (d["plan"], d["file"]) for d in rds)))))
            if rds:
                for t in [d for d in ds if d["category"] == "test"]:
                    self.add("test_shadows_package_fn", "info", t["plan"], t["task"], t["line"], t["file"],
                             "test-file function %s() shadows package function(s) in %s (signature %s vs %s)" % (
                                 name, ", ".join(sorted(set("%s %s" % (d["plan"], d["file"]) for d in rds))),
                                 t["signature"], rds[-1]["signature"]))

    def find_fixture_conflicts(self):
        """A test file that source()s a fixture and also defines a top-level function of the same name."""
        fx = collections.defaultdict(list)
        for d in self.defs:
            if d["category"] == "fixture" and d["role"] not in INACTIVE_ROLES:
                fx[d["name"]].append(d)
        seen = set()
        for d in self.defs:
            if d["category"] not in ("test", "helper") or d["role"] in INACTIVE_ROLES or d["name"] not in fx:
                continue
            srcs = self.source_strings.get(d["file"], set())
            for f in fx[d["name"]]:
                if os.path.basename(f["file"]) in srcs and (d["file"], d["name"]) not in seen:
                    seen.add((d["file"], d["name"]))
                    self.add("test_redefines_sourced_fixture_fn", "warn", d["plan"], d["task"], d["line"], d["file"],
                             "%s defines %s() (%s), and the file also sources %s (%s %s T%s) which defines %s() (%s); "
                             "the later definition wins" % (d["file"], d["name"], d["signature"],
                                                            os.path.basename(f["file"]), f["plan"], f["file"],
                                                            f["task"], d["name"], f["signature"]),
                             plans=sorted({d["plan"], f["plan"]}))

    def find_file_issues(self):
        self.file_actions = collections.defaultdict(list)
        for p in self.plans.values():
            for t in p["tasks"]:
                for f in t["files"]:
                    self.file_actions[f["path"]].append({"plan": p["id"], "task": t["num"], "action": f["action"],
                                                         "create": f["create"], "source": "Files",
                                                         "line": t.get("files_line"), "note": f["note"]})
            for b in p["blocks"]:
                if b["file"] and b["role"] not in INACTIVE_ROLES and b["action"] in (
                        "create", "append", "replace", "overwrite", "insert", "modify", "save") and \
                        b["attribution"] in ("intro", "leading-comment", "task-files", "inherited-from-old-block",
                                             "replaced-function-lookup", "task-last-file"):
                    self.file_actions[b["file"]].append({"plan": p["id"], "task": b["task"],
                                                         "action": b["action"] or "", "role": b["role"],
                                                         "create": b["action"] == "create" and b["attribution"] == "intro",
                                                         "source": "block", "line": b["line"], "lang": b["lang"]})
        self.file_index = {}
        for path, acts in sorted(self.file_actions.items()):
            creators = sorted(set(a["plan"] for a in acts if a["create"]))
            plans = sorted(set(a["plan"] for a in acts))
            self.file_index[path] = {"category": category_of(path), "creators": creators, "plans": plans,
                                     "actions": acts, "pre_existing": path in self.repo_files}
            if path.startswith("$") or category_of(path) == "scratch":
                continue
            if len(creators) > 1:
                det = "; ".join("%s T%s %s(%s) L%s" % (a["plan"], a["task"], a["action"], a["source"], a["line"])
                                for a in acts if a["create"])
                self.add("file_created_multi", "error", creators[-1], None, None, path,
                         "%s is created by %d plans: %s" % (path, len(creators), det), plans=creators)
            for pid in plans:
                ctasks = sorted(set(a["task"] for a in acts if a["create"] and a["plan"] == pid and a["source"] == "block"))
                if len(ctasks) > 1:
                    self.add("file_created_twice_in_plan", "warn", pid, ctasks[-1], None, path,
                             "%s is created ('Create `...`:' block) in tasks %s of %s" % (path, ctasks, pid))
            if path in ("NAMESPACE",) or path.startswith("man/") or path in self.repo_files:
                continue
            for a in acts:
                if a["create"] or a["action"] in ("Delete", "Generated", "Generate", "save", "Read", "Run"):
                    continue
                if a["source"] == "Files" and a["action"] in ("Test",) and not creators:
                    pass
                okp = self.ok_plans(a["plan"])
                if not creators:
                    if a["source"] == "block" and a["action"] in ("append", "replace", "insert", "modify", "overwrite"):
                        self.add("file_modified_never_created", "warn", a["plan"], a["task"], a["line"], path,
                                 "%s is %s-ed by %s but no plan creates it (and it is not in the repository)" % (
                                     path, a["action"], a["plan"]))
                    continue
                if not (set(creators) & okp):
                    later = all(int(c[1:]) > int(a["plan"][1:]) for c in creators)
                    self.add("ordering_file", "error" if later else "warn", a["plan"], a["task"], a["line"], path,
                             "%s %s %s (via %s), but it is created only by %s, outside %s's dependency closure" % (
                                 a["plan"], a["action"] or "touches", path, a["source"], ", ".join(creators), a["plan"]))

    def find_helper_and_undefined(self):
        seen = set()
        self.undefined_names = collections.defaultdict(list)
        for u in self.unresolved:
            self.undefined_names[u["fn"]].append(u)
        for fn, uses in sorted(self.undefined_names.items()):
            for u in uses:
                key = (u["plan"], u["task"], u["line"], fn)
                if key in seen:
                    continue
                seen.add(key)
                cat = u["category"]
                if DELIBERATE_MISSING_RE.search(fn):
                    self.add("undefined_function_deliberate", "info", u["plan"], u["task"], u["line"], u["file"],
                             "%s calls %s(), which is undefined on purpose (name says so)" % (u["caller"], fn))
                elif cat in TESTISH and HELPER_NAME_RE.search(fn):
                    self.add("test_helper_undefined", "error", u["plan"], u["task"], u["line"], u["file"],
                             "%s uses test helper %s(), defined nowhere (no plan, not testthat)" % (u["caller"], fn))
                elif cat == "R":
                    self.add("undefined_function", "error", u["plan"], u["task"], u["line"], u["file"],
                             "package code (%s) calls %s(), defined in no plan and not in base R" % (u["caller"], fn))
                elif cat in TESTISH:
                    self.add("undefined_function_in_tests", "error" if cat in ("test", "helper", "setup") else "warn",
                             u["plan"], u["task"], u["line"], u["file"],
                             "%s calls %s(), defined in no plan, not base R, not testthat" % (u["caller"], fn))
                else:
                    self.add("undefined_function_other", "info", u["plan"], u["task"], u["line"], u["file"],
                             "%s (%s block) calls %s(), defined in no plan and not base R" % (u["caller"], cat, fn))

    @staticmethod
    def in_package_code(occ):
        return any(o.get("category") == "R" for o in occ)

    def contract_known(self, cat):
        ctr = self.contract
        sets = {"option": ctr["options"], "condition": ctr["conditions"], "event": ctr["events"],
                "registry_kind": ctr["kinds"], "envvar": ctr["envvars"]}
        return sets.get(cat, set()) | ctr["backticked"]

    def find_near_names(self):
        """Names used in exactly one plan with a near-identical name (edit distance <= 2) in other plans."""
        self.near = []
        for cat, names in sorted(self.name_occ.items()):
            plans_of = {n: sorted(set(o["plan"] for o in occ)) for n, occ in names.items()}
            allnames = sorted(names)
            for n in allnames:
                if len(plans_of[n]) != 1:
                    continue
                for m in allnames:
                    if m == n or not (set(plans_of[m]) - set(plans_of[n])):
                        continue
                    dist = levenshtein(n, m, 2)
                    if dist > 2:
                        continue
                    core_n = re.sub(r"^(gptr_(error|warning|message)_|gptr\.)", "", n)
                    core_m = re.sub(r"^(gptr_(error|warning|message)_|gptr\.)", "", m)
                    if min(len(core_n), len(core_m)) < (5 if dist == 2 else 3):
                        continue
                    o = names[n][0]
                    in_pkg = self.in_package_code(names[n])
                    known = self.contract_known(cat)
                    if n in known and m in known:
                        in_pkg = False  # both names are contract names: deliberate, not a typo
                    self.near.append({"category": cat, "name": n, "plan": plans_of[n][0], "near": m,
                                      "near_plans": plans_of[m], "distance": dist, "in_package_code": in_pkg})
                    self.add("near_name", "warn" if in_pkg else "info", o["plan"], o["task"], o["line"], o["file"],
                             "%s '%s' is used only in %s (%d site%s%s); near-identical '%s' (distance %d) is used in %s" % (
                                 cat, n, o["plan"], len(names[n]), "" if len(names[n]) == 1 else "s",
                                 "" if self.in_package_code(names[n]) else ", tests only", m, dist,
                                 ", ".join(plans_of[m])),
                             name=n, near=m, kind=cat)

    def find_contract_names(self):
        """Option, condition, event and kind names used in package code that 04/03 never name."""
        if not self.contract["available"]:
            return
        ctr = self.contract
        bt = ctr["backticked"]
        checks = {"option": ctr["options"], "condition": ctr["conditions"], "event": ctr["events"],
                  "registry_kind": ctr["kinds"], "envvar": ctr["envvars"], "stream_event": set(),
                  "setting": set(), "service": set()}
        for cat, known in checks.items():
            for name, occ in sorted(self.name_occ.get(cat, {}).items()):
                if ":" in name or " " in name:
                    continue
                if cat == "condition":
                    ok = name in known or name.split("_", 2)[-1] in bt
                elif cat == "envvar":
                    ok = name in known or name in bt or not ENVVAR_MENTION_RE.match(name)
                else:
                    ok = name in known or name in bt
                if ok:
                    continue
                pkg_occ = [o for o in occ if o.get("category") == "R"]
                if not pkg_occ:
                    continue
                o = pkg_occ[0]
                plans = sorted(set(x["plan"] for x in occ))
                self.add("name_not_in_contract", "warn", o["plan"], o["task"], o["line"], o["file"],
                         "%s '%s' (package code; used in %s, %d sites) is not named in 04-interface-contract or "
                         "03-architecture" % (cat, name, ", ".join(plans), len(occ)), kind=cat, name=name)

    def find_services(self):
        sp = None
        for d in self.objects:
            if d["name"] == "service_plans" and d.get("mapping"):
                sp = d
        self.service_plans = sp["mapping"] if sp else {}
        occ = self.name_occ.get("service", {})
        for name, os_ in sorted(occ.items()):
            if self.service_plans and name not in self.service_plans:
                pk = [x for x in os_ if x.get("category") == "R"]
                o = (pk or os_)[0]
                self.add("service_not_declared", "error" if pk else "info", o["plan"], o["task"], o["line"], o["file"],
                         "service '%s' (%s in %s%s) is not in P01's service_plans" % (
                             name, "/".join(sorted(set(x["via"] for x in os_))),
                             ", ".join(sorted(set(x["plan"] for x in os_))), "" if pk else "; tests only"))
            providers = sorted(set(x["plan"] for x in os_ if x["role"] == "provide" and x.get("category") == "R"))
            want = self.service_plans.get(name)
            if want and providers and want not in providers:
                o = next(x for x in os_ if x["role"] == "provide" and x.get("category") == "R")
                self.add("service_provider_mismatch", "error", o["plan"], o["task"], o["line"], o["file"],
                         "service '%s' is set by %s but service_plans names %s" % (name, ", ".join(providers), want))
        for name, want in sorted(self.service_plans.items()):
            os_ = occ.get(name, [])
            if not any(x["role"] == "provide" and x.get("category") == "R" for x in os_):
                self.add("service_never_provided", "warn", want, None, sp["line"] if sp else None,
                         "R/aaa-state.R", "service '%s' (service_plans: %s) is never provided through "
                                          "ext_service_set(\"%s\", ...) in any plan's package code (it may be "
                                          "provided by a `service` registry record)" % (name, want, name))
            users = sorted(set(x["plan"] for x in os_ if x["role"] == "use" and x.get("category") == "R"))
            providers = sorted(set(x["plan"] for x in os_ if x["role"] == "provide" and x.get("category") == "R"))
            for u in users:
                if providers and not (set(providers) & self.ok_plans(u)):
                    pass  # services are late-bound by design (IC-33); recorded in the index only

    def collect_member_names(self):
        """Names that are members or fields, not top-level functions: x$name(...), x$name = ...,
        list(name = function ...), and formal names (callbacks such as `execute`, `render`)."""
        self.member_names = set()
        for b in self.blocks:
            r = b.get("_r")
            if not r:
                continue
            for c in as_list(r.get("calls")):
                if c.get("member"):
                    self.member_names.add(c["fn"])
                for a in as_list(c.get("args")):
                    if a.get("name") and a.get("kind") in ("fun", "sym"):
                        self.member_names.add(a["name"])
                    for ia in as_list(a.get("inner")):
                        if ia.get("name") and ia.get("kind") in ("fun", "sym"):
                            self.member_names.add(ia["name"])
            for m in as_list(r.get("member_defs")):
                self.member_names.add(m["name"])
        for d in self.defs:
            self.member_names.update(d.get("formals") or [])

    def find_interfaces(self):
        self.collect_member_names()
        lookup_pkgs = self.ext.get("lookup_pkgs") or {}
        self.iface_entries = []
        for p in self.plans.values():
            for t in p["tasks"]:
                itf = t.get("interfaces")
                if not itf:
                    continue
                for kind in ("consumes", "produces"):
                    for seg in itf[kind]:
                        fns = []
                        for name, args, _ in extract_fn_mentions(seg):
                            fns.append({"name": name, "args": args})
                        self.iface_entries.append({"plan": p["id"], "task": t["num"], "line": itf.get("line"),
                                                   "kind": kind, "text": seg, "functions": fns})
        for e in self.iface_entries:
            seen = set()
            for f in e["functions"]:
                name = f["name"]
                if not re.match(r"^[A-Za-z][\w.]*$", name) or name in TYPE_NOTATION:
                    continue
                defs = self.fn_defs.get(name, [])
                external = name in self.ext["bare"] or name in lookup_pkgs
                f["resolved"] = sorted(set(d["plan"] for d in defs)) or (
                    ["external:" + ",".join(as_list(lookup_pkgs.get(name)) or [(self.ext["bare"].get(name) or {}).get("pkg") or "testthat"])]
                    if external else (["member"] if name in self.member_names else []))
                if e["kind"] == "consumes":
                    if not defs:
                        if name in self.obj_defs or external or name in self.member_names or name in seen:
                            continue
                        seen.add(name)
                        self.add("iface_consumes_undefined", "error", e["plan"], e["task"], e["line"], None,
                                 "Interfaces (Consumes) of %s T%s names %s(%s), which no plan defines (not a base, "
                                 "dependency-package, member or callback name either)" % (
                                     e["plan"], e["task"], name, f["args"][:80]), name=name)
                        continue
                else:
                    own = [d for d in defs if d["plan"] == e["plan"]]
                    if not own:
                        if name in self.obj_defs or external or name in self.member_names or name in seen:
                            continue
                        seen.add(name)
                        if name in NAMESPACE_DIRECTIVES or name in self.service_plans or name in FOREIGN_NAMES:
                            continue
                        if defs:
                            self.add("iface_produces_elsewhere", "info", e["plan"], e["task"], e["line"], None,
                                     "Interfaces (Produces) of %s T%s names %s(), which %s does not define "
                                     "(defined in %s)" % (e["plan"], e["task"], name, e["plan"],
                                                          ", ".join(sorted(set(d["plan"] for d in defs)))), name=name)
                        else:
                            camel = re.search(r"[a-z][A-Z]", name) is not None
                            self.add("iface_produces_undefined", "info" if camel else "error", e["plan"], e["task"],
                                     e["line"], None,
                                     "Interfaces (Produces) of %s T%s mentions %s(%s), which no plan defines%s" % (
                                         e["plan"], e["task"], name, f["args"][:80],
                                         " (camelCase: probably an upstream Pi/TypeScript name)" if camel else ""),
                                     name=name)
                        continue
                    defs = own
                sig = parse_sig_text(f["args"]) if f["args"] else None
                if not sig:
                    continue
                okp = self.ok_plans(e["plan"])
                rdefs = [d for d in defs if d["category"] in ("R", "helper", "setup")]
                rdefs = [d for d in rdefs if d["plan"] in okp] or rdefs
                if rdefs:
                    self.compare_sig(name, sig, rdefs, "iface_signature_mismatch", e["plan"], e["task"], e["line"],
                                     "Interfaces (%s) of %s T%s" % (e["kind"].capitalize(), e["plan"], e["task"]))

    def sig_problems(self, sig, d):
        consts = self.constants
        fnames = d["formals"]
        has_dots = "..." in fnames
        elided = any(a == "..." for a, _ in sig) and not has_dots
        items = [(a, v) for a, v in sig if not (a == "..." and not has_dots)]
        strong, weak = [], []
        for a, v in items:
            if v is not None and a not in fnames and not has_dots:
                strong.append("`%s =` is not a formal" % a)
        complete = (not elided) and len(items) == len(fnames) and len(fnames) > 0
        if complete:
            names = [a for a, _ in items]
            if names != fnames:
                msg = ("argument order differs" if sorted(names) == sorted(fnames) else
                       "argument names differ: (%s) vs (%s)" % (", ".join(names), ", ".join(fnames)))
                if len(items) <= 1 and all(v is None for _, v in items):
                    weak.append(msg + " (single positional argument: may be a usage example)")
                else:
                    strong.append(msg)
            else:
                for a, v in items:
                    if v is None or v == "" or "<" in v or "..." in v:
                        continue
                    dd = d["defaults"].get(a)
                    if dd is None:
                        strong.append("gives `%s = %s` but the definition has no default" % (a, v))
                    elif not defaults_equal(v, dd, consts):
                        strong.append("default `%s = %s` vs definition `%s = %s`" % (a, v, a, dd))
        else:
            for k, (a, v) in enumerate(items):
                if v is not None or a == "...":
                    continue
                if a not in fnames and k < len(fnames) and fnames[k] != "...":
                    weak.append("position %d is `%s`, the formal there is `%s`" % (k + 1, a, fnames[k]))
                elif a not in fnames and not has_dots and k >= len(fnames):
                    strong.append("more arguments than formals (`%s`)" % a)
        return strong, weak

    def compare_sig(self, name, sig, defs, category, plan, task, line, where):
        best = None
        for d in defs:
            strong, weak = self.sig_problems(sig, d)
            if not strong and not weak:
                return
            score = (len(strong), len(weak))
            if best is None or score < best[0]:
                best = (score, d, strong, weak)
        _, d, strong, weak = best
        text = "%s: %s(%s) vs %s [%s T%s L%d]: %s" % (
            where, name, ", ".join(a if v is None else "%s = %s" % (a, v) for a, v in sig),
            d["signature"], d["plan"], d["task"], d["line"], "; ".join(strong + weak))
        self.add(category, "warn" if strong else "info", plan, task, line, d["file"], text, name=name)

    def resolvable_name(self, name):
        lookup_pkgs = self.ext.get("lookup_pkgs") or {}
        if name in FOREIGN_NAMES or name in ("TRUE", "FALSE", "NULL", "NA"):
            return True
        if re.match(r"^[A-Z][A-Za-z0-9]*$", name):
            return True  # Failure(...), Traceback(...), Bash(...): prose, not R functions
        missing = set(DEP_PKGS) - set(as_list(self.ext.get("dep_installed")))
        if any(name.lower().startswith(pk.lower() + "_") for pk in missing):
            return True  # e.g. duckdb_register(): an uninstalled Suggests package's function
        return (name in self.fn_defs or name in self.obj_defs or name in self.ext["bare"] or name in lookup_pkgs
                or name in self.member_names or name in TYPE_NOTATION or name in NAMESPACE_DIRECTIVES
                or name in self.service_plans or not re.match(r"^[A-Za-z][\w.]*$", name))

    def find_mentions(self):
        """Backticked fn() names in plan prose and in 04 that no plan defines (stale names after renames)."""
        self.unresolved_mentions = []
        for pid, p in sorted(self.plans.items()):
            groups = collections.OrderedDict()
            for m in p["prose_mentions"]:
                if self.resolvable_name(m["name"]) or COND_RE.match(m["name"]):
                    continue
                groups.setdefault(m["name"], []).append(m)
            for name, ms in groups.items():
                camel = re.search(r"[a-z][A-Z]", name) is not None
                snake = "_" in name and not camel
                self.unresolved_mentions.append({"plan": pid, "name": name, "lines": [m["line"] for m in ms]})
                in_task = any(m["task"] not in (None,) for m in ms)
                self.add("prose_mentions_undefined", "warn" if (snake and in_task) else "info", pid, ms[0]["task"],
                         ms[0]["line"],
                         None, "%s prose names %s(%s) %d time%s (lines %s), but no plan defines it%s" % (
                             pid, name, ms[0]["args"][:60], len(ms), "" if len(ms) == 1 else "s",
                             ", ".join(str(m["line"]) for m in ms[:8]) + (" ..." if len(ms) > 8 else ""),
                             " (camelCase: probably an upstream Pi/TypeScript or external name)" if camel else ""),
                         name=name)
        if not self.contract["available"]:
            return
        groups = collections.OrderedDict()
        for m in self.contract["fn_mentions"]:
            if self.resolvable_name(m["name"]):
                continue
            groups.setdefault(m["name"], []).append(m)
        for name, ms in groups.items():
            camel = re.search(r"[a-z][A-Z]", name) is not None
            if camel or "_" not in name:
                sev = "info"
            else:
                sev = "warn"
            self.add("contract_fn_undefined", sev, None, None, None, None,
                     "04 names %s(%s) (lines %s; section %s) but no plan defines it" % (
                         name, ms[0]["args"][:60], ", ".join(str(m["line"]) for m in ms[:6]) + (" ..." if len(ms) > 6 else ""),
                         ms[0]["section"]), name=name)

    def find_contract_signatures(self):
        if not self.contract["available"]:
            return
        seen = set()
        for m in self.contract["fn_mentions"]:
            name = m["name"]
            rdefs = [d for d in self.fn_defs.get(name, []) if d["category"] == "R"]
            if not rdefs or not m["args"]:
                continue
            sig = parse_sig_text(m["args"])
            if not sig or all(a == "..." for a, _ in sig):
                continue
            key = (name, re.sub(r"\s+", "", m["args"]))
            if key in seen:
                continue
            seen.add(key)
            final = sorted(rdefs, key=lambda d: (d["plan"], d["line"]))
            last_plan = final[-1]["plan"]
            cand = [d for d in final if d["plan"] == last_plan]
            self.compare_sig(name, sig, cand, "contract_signature_mismatch", cand[-1]["plan"], cand[-1]["task"],
                             cand[-1]["line"], "04 L%d (%s)" % (m["line"], m["section"]))

    def find_exports_and_owners(self):
        ctr = self.contract
        self.exports_by_plan = collections.defaultdict(list)
        for d in self.defs:
            if d["category"] == "R" and d["export"] and d["role"] not in INACTIVE_ROLES:
                self.exports_by_plan[d["plan"]].append(d["name"])
        for d in self.objects:
            if d["category"] == "R" and "export" in d["tags"] and d["role"] not in INACTIVE_ROLES:
                self.exports_by_plan[d["plan"]].append(d["name"])
        if not ctr["available"]:
            return
        want_plan = {}
        for pid, names in ctr["exports"].items():
            for n in names:
                want_plan[n] = pid
        got_plan = collections.defaultdict(set)
        for pid, names in self.exports_by_plan.items():
            for n in names:
                got_plan[n].add(pid)
        for n, pid in sorted(want_plan.items()):
            if pid not in self.plans:
                continue
            if n not in got_plan:
                defs = self.fn_defs.get(n, [])
                where = ", ".join(sorted(set("%s(%s)" % (d["plan"], "noRd" if d["noRd"] else "no @export") for d in defs)))
                self.add("export_missing", "error", pid, None, None, None,
                         "contract 04 section 14.1 lists export %s for %s, but no plan exports it%s" % (
                             n, pid, (" (defined: %s)" % where) if where else " (not defined)"))
            elif pid not in got_plan[n]:
                self.add("export_wrong_plan", "warn", sorted(got_plan[n])[0], None, None, None,
                         "export %s is exported by %s; contract 04 section 14.1 assigns it to %s" % (
                             n, ", ".join(sorted(got_plan[n])), pid))
        for n, pids in sorted(got_plan.items()):
            if n not in want_plan:
                d = next(d for d in self.defs if d["name"] == n and d["export"]) if any(
                    d["name"] == n and d["export"] for d in self.defs) else None
                self.add("export_not_in_contract", "error", sorted(pids)[0], d["task"] if d else None,
                         d["line"] if d else None, d["file"] if d else None,
                         "%s carries @export but is not one of the 63 exports of contract 04 section 14.1" % n)
        # file ownership
        owner_pat = []
        for pid, pats in ctr["owners"].items():
            for ptn in pats:
                rx = "^" + re.escape(ptn).replace(r"\*", "[^/]*") + "$"
                owner_pat.append((re.compile(rx), pid))
        for path, info in sorted(self.file_index.items()):
            if info["category"] != "R":
                continue
            base = os.path.basename(path)
            owners = sorted(set(pid for rx, pid in owner_pat if rx.match(base)))
            for a in info["actions"]:
                if a["action"] in ("Read", "Run"):
                    continue
                if owners and a["plan"] not in owners:
                    self.add("file_owner_mismatch", "warn", a["plan"], a["task"], a["line"], path,
                             "%s %s %s, which contract 04 section 14 assigns to %s" % (
                                 a["plan"], a["action"] or "touches", path, ", ".join(owners)))
                elif not owners and a["create"]:
                    self.add("file_owner_unlisted", "warn", a["plan"], a["task"], a["line"], path,
                             "%s creates %s, which no plan owns in contract 04 section 14" % (a["plan"], path))

    def find_header_deps(self):
        for pid, p in sorted(self.plans.items()):
            want = set(self.deps.get(pid, []))
            got = set(p["header_depends"])
            if pid not in self.deps:
                self.add("plan_not_in_decomposition", "warn", pid, None, None, None,
                         "%s is not in the 05-plan-decomposition dependency table" % pid)
                continue
            if want != got:
                self.add("depends_header_mismatch", "warn", pid, None, 13, None,
                         "plan header 'Depends on' lists %s; 05-plan-decomposition lists %s" % (
                             ", ".join(sorted(got)) or "none", ", ".join(sorted(want)) or "none"))

    def find_roxygen(self):
        for d in self.defs:
            if d["category"] != "R" or d["role"] in INACTIVE_ROLES or d.get("parse_fallback"):
                continue
            t = d["tags"]
            if d["roxygen_title"] is None and not t:
                self.add("roxygen_missing", "info", d["plan"], d["task"], d["line"], d["file"],
                         "%s() in R/ has no roxygen block (convention: one-line title + @noRd)" % d["name"])
                continue
            if not (d["export"] or d["s3_export"] or d["noRd"] or d["rdname"] or "describeIn" in t
                    or "method" in t or "exportS3Method" in t or "keywords" in t and "internal" in " ".join(t["keywords"])):
                self.add("roxygen_no_export_or_noRd", "warn", d["plan"], d["task"], d["line"], d["file"],
                         "%s() has a roxygen block without @export, @noRd or @rdname (roxygen would write an Rd "
                         "page for an internal function)" % d["name"])
            if d["export"] and d["noRd"]:
                self.add("roxygen_export_and_noRd", "warn", d["plan"], d["task"], d["line"], d["file"],
                         "%s() is both @export and @noRd" % d["name"])
            if d["uses_r6"]:
                self.add("forbidden_r6", "error", d["plan"], d["task"], d["line"], d["file"],
                         "%s() uses R6 (never a dependency)" % d["name"])

    def find_misc_r(self):
        """Cheap convention checks on package code calls."""
        for b in self.blocks:
            r = b.get("_r")
            if not r or b["role"] in INACTIVE_ROLES or b["category"] != "R":
                continue
            off = b["line"]
            for c in as_list(r.get("calls")):
                fn = c["fn"]
                args = as_list(c.get("args"))
                line = off + (c.get("line") or 0)
                pkg = c.get("pkg")
                if c.get("member") or c.get("fallback"):
                    continue
                if pkg == "withr":
                    self.add("withr_in_package_code", "error", b["plan"], b["task"], line, b["file"],
                             "withr::%s() in R/ (withr is a Suggests used only in tests)" % fn)
                if fn == "readLines" and not pkg and not any(a.get("name") == "encoding" for a in args):
                    self.add("readlines_without_encoding", "warn", b["plan"], b["task"], line, b["file"],
                             "readLines() without encoding = \"UTF-8\" in R/ (IC-62)")
                if pkg == "jsonlite" and fn == "fromJSON" and not any(
                        a.get("name") == "simplifyVector" for a in args):
                    self.add("fromjson_simplify", "warn", b["plan"], b["task"], line, b["file"],
                             "jsonlite::fromJSON() without simplifyVector = FALSE in R/ (conventions section 6)")
                if not pkg and fn in ("library", "require", "set.seed", "RNGkind", "sample", "runif"):
                    self.add("forbidden_call_in_R", "warn", b["plan"], b["task"], line, b["file"],
                             "%s() in package code (conventions section 4)" % fn)
                if fn == "randomPort":
                    self.add("forbidden_call_in_R", "warn", b["plan"], b["task"], line, b["file"],
                             "httpuv::randomPort() (IC-61)")
                if fn == "enc2utf8" and not pkg:
                    self.add("bare_enc2utf8", "info", b["plan"], b["task"], line, b["file"],
                             "bare enc2utf8() in R/ (conventions: use as_utf8())")

    def find_parse_errors(self):
        for b in self.blocks:
            if b["lang"] != "r" or b.get("parse_ok", True):
                continue
            sev = "info" if b["role"] in INACTIVE_ROLES or b["category"] in ("unknown", "scratch") else "error"
            if b["category"] in ("inst", "vignette", "other", "dev"):
                sev = "warn"
            err = (b.get("parse_error") or "").replace("\n", " | ")
            self.add("r_parse_error", sev, b["plan"], b["task"], b["line"], b["file"],
                     "R block (%s, role %s) does not parse: %s" % (b["category"], b["role"], err[:200]))

    def find_attribution(self):
        for b in self.blocks:
            if b["lang"] == "r" and b["file"] is None and b["role"] not in INACTIVE_ROLES:
                code = b.get("code", "")
                has_defs = bool(DEF_LINE_RE.search(code))
                sev = "warn" if has_defs else "info"
                self.add("block_unattributed", sev, b["plan"], b["task"], b["line"], None,
                         "R block could not be attributed to a file (intro: %s)%s" % (
                             (b.get("intro") or b.get("intro_kind") or "")[:100],
                             "; it defines functions" if has_defs else ""))

    # ---------------------------------------------------------------- output
    def stats(self):
        st = {}
        for pid, p in sorted(self.plans.items()):
            bl = p["blocks"]
            rbl = [b for b in bl if b["lang"] == "r"]
            defs = [d for d in self.defs if d["plan"] == pid and d["role"] not in INACTIVE_ROLES]
            calls_out = collections.Counter()
            for c in self.calls:
                if c["caller_plan"] == pid:
                    for q in c["callee_plans"]:
                        if q != pid:
                            calls_out[q] += 1
            fcount = collections.Counter(f["severity"] for f in self.findings if f["plan"] == pid)
            st[pid] = {
                "title": p["title"], "lines": p["n_lines"], "tasks": len([t for t in p["tasks"] if t["num"]]),
                "blocks": len(bl), "r_blocks": len(rbl),
                "r_blocks_parse_failed": sum(1 for b in rbl if not b.get("parse_ok", True)),
                "r_blocks_unattributed": sum(1 for b in rbl if b["file"] is None),
                "files_created": len(set(path for path, info in self.file_index.items() if pid in info["creators"])),
                "functions_R": len([d for d in defs if d["category"] == "R"]),
                "functions_test": len([d for d in defs if d["category"] != "R"]),
                "exports": len(self.exports_by_plan.get(pid, [])),
                "s3_methods": len([d for d in defs if d["s3"] and d["category"] == "R"]),
                "calls_to_plan_functions": sum(1 for c in self.calls if c["caller_plan"] == pid),
                "cross_plan_calls": sum(calls_out.values()),
                "calls_into_plans": dict(sorted(calls_out.items())),
                "options": len(set(n for n, occ in self.name_occ.get("option", {}).items() if any(o["plan"] == pid for o in occ))),
                "conditions": len(set(n for n, occ in self.name_occ.get("condition", {}).items() if any(o["plan"] == pid for o in occ))),
                "events": len(set(n for n, occ in self.name_occ.get("event", {}).items() if any(o["plan"] == pid for o in occ))),
                "findings": dict(fcount),
            }
        return st

    def write(self):
        sev_rank = {"error": 0, "warn": 1, "info": 2}
        self.findings.sort(key=lambda f: (f["out_of_scope"], sev_rank.get(f["severity"], 3), f["category"],
                                          f["plan"] or "", f["task"] if isinstance(f["task"], int) else 999,
                                          f["line"] or 0))
        for k, f in enumerate(self.findings, 1):
            f["id"] = "F%04d" % k
            f["text"] = self.finding_line(f)
        st = self.stats()
        call_graph = collections.defaultdict(lambda: collections.Counter())
        for c in self.calls:
            for q in c["callee_plans"]:
                call_graph[c["caller_plan"]][q] += 1
        names_out = {cat: {n: occ for n, occ in sorted(v.items())} for cat, v in sorted(self.name_occ.items())}
        helpers_def = collections.defaultdict(list)
        for d in self.defs:
            if d["category"] in ("helper", "setup", "fixture") or (d["category"] == "test"):
                helpers_def[d["name"]].append({k: d[k] for k in ("plan", "task", "file", "category", "line", "signature")})
        helpers_used = collections.defaultdict(list)
        for c in self.calls:
            if c["caller_category"] in TESTISH and HELPER_NAME_RE.search(c["callee"]):
                helpers_used[c["callee"]].append({k: c[k] for k in ("caller_plan", "caller_task", "caller_file", "line")})
        test_files = collections.defaultdict(lambda: {"plans": set(), "tasks": []})
        for b in self.blocks:
            if b["category"] in TESTISH and b["file"]:
                tf = test_files[b["file"]]
                tf["plans"].add(b["plan"])
                tf["tasks"].append("%s T%s" % (b["plan"], b["task"]))
        test_files_out = {k: {"category": category_of(k), "plans": sorted(v["plans"]),
                              "tasks": sorted(set(v["tasks"]))} for k, v in sorted(test_files.items())}
        plans_out = {}
        for pid, p in sorted(self.plans.items()):
            plans_out[pid] = {
                "title": p["title"], "file": p["file"], "lines": p["n_lines"],
                "milestone": self.milestones.get(pid) or p["milestone_header"],
                "depends_05": self.deps.get(pid), "closure": sorted(self.closure.get(pid, [])),
                "depends_header_text": p["header_depends_text"], "depends_header": p["header_depends"],
                "in_scope": pid in self.scope,
                "tasks": [{
                    "num": t["num"], "title": t["title"], "line": t["line"], "files": t["files"],
                    "files_raw": t["files_raw"], "interfaces": t["interfaces"], "steps": t["steps"],
                    "commit_files": sorted(set(t["commit_files"])),
                    "blocks": [b["id"] for b in p["blocks"] if b["task"] == t["num"] and
                               (t["num"] is not None or b["section"] == t["section"])],
                } for t in p["tasks"]],
                "counts": st[pid],
            }
        blocks_out = []
        for b in self.blocks:
            blocks_out.append({k: b.get(k) for k in ("id", "plan", "task", "step", "section", "line", "end_line", "lang",
                                                    "file", "category", "action", "role", "attribution",
                                                    "intro", "replaced", "parse_ok", "parse_error")})
            blocks_out[-1]["n_lines"] = len(b.get("code", "").split("\n"))
        defs_out = [{k: v for k, v in d.items()} for d in self.defs]
        index = {
            "generated": datetime.datetime.now().isoformat(timespec="seconds"),
            "generator": os.path.abspath(__file__),
            "inputs": {"plan_dir": self.plan_dir, "spec_dir": self.spec_dir, "repo": self.repo,
                       "plans": [p["file"] for p in self.plans.values()], "r": self.ext.get("r_version")},
            "dependency_table_05": {pid: {"depends": self.deps[pid], "title": self.titles05.get(pid),
                                          "milestone": self.milestones.get(pid),
                                          "closure": sorted(closure_of(pid, self.deps))} for pid in sorted(self.deps)},
            "plans": plans_out,
            "blocks": blocks_out,
            "definitions": defs_out,
            "objects": self.objects,
            "s3_methods": [{k: d[k] for k in ("name", "plan", "task", "file", "line", "s3", "export", "s3_export")}
                           for d in self.defs if d["s3"] and d["category"] == "R" and d["role"] not in INACTIVE_ROLES],
            "env_constructors": [{k: d[k] for k in ("name", "plan", "task", "file", "line", "classes_set", "signature")}
                                 for d in self.defs if d.get("env_constructor") and d["role"] not in INACTIVE_ROLES],
            "exports_by_plan": {k: sorted(set(v)) for k, v in sorted(self.exports_by_plan.items())},
            "calls": self.calls,
            "value_refs": self.value_refs,
            "late_refs": self.late_refs,
            "mocks": self.mocks,
            "unresolved_calls": self.unresolved,
            "call_graph": {k: dict(sorted(v.items())) for k, v in sorted(call_graph.items())},
            "names": names_out,
            "service_plans": self.service_plans,
            "test_helpers": {"defined": dict(sorted(helpers_def.items())), "used": dict(sorted(helpers_used.items()))},
            "test_files": test_files_out,
            "files": self.file_index,
            "interfaces": self.iface_entries,
            "duplicate_functions": self.dup_functions,
            "near_names": self.near,
            "contract": {"exports": self.contract["exports"], "owners": self.contract["owners"],
                         "events_10_4": sorted(self.contract["events"]), "kinds_10_2": sorted(self.contract["kinds"]),
                         "conditions": sorted(self.contract["conditions"]), "options": sorted(self.contract["options"])},
            "stats": st,
            "findings": self.findings,
        }
        self.index = index
        jp = os.path.join(self.out_dir, "index.json")
        with open(jp, "w", encoding="utf-8") as fh:
            json.dump(index, fh, indent=1, ensure_ascii=False, default=lambda o: sorted(o) if isinstance(o, set) else str(o))
        mp = os.path.join(self.out_dir, "index.md")
        with open(mp, "w", encoding="utf-8") as fh:
            fh.write(self.render_md(st, call_graph))
        self.index = index
        return jp, mp

    @staticmethod
    def finding_line(f):
        loc = f["plan"] or "-"
        if f["task"] is not None:
            loc += " T%s" % f["task"]
        if f["line"]:
            loc += " L%s" % f["line"]
        fl = (" %s" % f["file"]) if f.get("file") else ""
        return "[%s] %s %s%s: %s" % (f["severity"], f["category"], loc, fl, f["message"])

    def render_md(self, st, call_graph):
        out = []
        w = out.append
        inscope = [f for f in self.findings if not f["out_of_scope"]]
        outscope = [f for f in self.findings if f["out_of_scope"]]
        w("# gptr plan cross-index\n")
        w("Generated %s by `%s` from `%s/P*.md` (%d plan files: %s), `05-plan-decomposition.md` "
          "(dependencies, milestones) and `04-interface-contract.md` / `03-architecture.md` (exports, file owners, "
          "names). Machine-readable companion: `index.json` (same directory). Findings are reported for the plans "
          "in scope (%s); findings that involve only other plans are listed at the end.\n" % (
              self.index["generated"], os.path.basename(__file__), self.plan_dir, len(self.plans),
              ", ".join(sorted(self.plans)), ", ".join(sorted(self.scope & set(self.plans)))))
        tot = collections.Counter(f["severity"] for f in inscope)
        w("Totals: %d tasks, %d code blocks (%d R), %d top-level function definitions (%d in R/), %d resolved call "
          "sites of plan-defined functions, %d value references, %d late-bound references; in-scope findings: %d "
          "(%d error, %d warn, %d info); out-of-scope findings: %d.\n" % (
              sum(s["tasks"] for s in st.values()), len(self.blocks),
              sum(1 for b in self.blocks if b["lang"] == "r"), len(self.defs),
              sum(1 for d in self.defs if d["category"] == "R"), len(self.calls), len(self.value_refs),
              len(self.late_refs), len(inscope), tot["error"], tot["warn"], tot["info"], len(outscope)))
        w("Severity: `error` = will break a build or test as written; `warn` = inconsistency to resolve or confirm; "
          "`info` = context for the checkers (heuristic, low confidence or intended).\n")
        w("## Counts per plan\n")
        w("| Plan | Depends (05) | Tasks | Blocks (R) | R unparsed | R unattributed | Files created | R/ fns | test fns | "
          "Exports | S3 | Calls to plan fns | Cross-plan calls | Options | Conditions | Events | Findings E/W/I |")
        w("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for pid, s in sorted(st.items()):
            f = s["findings"]
            w("| %s%s | %s | %d | %d (%d) | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d/%d/%d |" % (
                pid, "" if pid in self.scope else " (out of scope)", ", ".join(self.deps.get(pid, [])) or "-",
                s["tasks"], s["blocks"], s["r_blocks"],
                s["r_blocks_parse_failed"], s["r_blocks_unattributed"], s["files_created"], s["functions_R"],
                s["functions_test"], s["exports"], s["s3_methods"], s["calls_to_plan_functions"], s["cross_plan_calls"],
                s["options"], s["conditions"], s["events"], f.get("error", 0), f.get("warn", 0), f.get("info", 0)))
        w("")
        w("## Call graph (caller plan -> callee plan: resolved call sites)\n")
        w("Edges count call sites (package and test code) whose callee is defined in the callee plan; a callee "
          "defined in several plans counts for each. Edges to plans outside the caller's 05 dependency closure "
          "are marked; whether they are real ordering bugs is in the `ordering_*` findings (a callee also "
          "defined inside the closure is not an ordering bug).\n")
        for caller in sorted(call_graph):
            items = ", ".join("%s:%d" % (q, n) for q, n in sorted(call_graph[caller].items()) if q != caller)
            outside = [q for q in call_graph[caller] if q != caller and q not in self.closure.get(caller, set())]
            w("- %s -> %s%s" % (caller, items or "(none)",
                                ("  **outside closure: %s**" % ", ".join(sorted(outside))) if outside else ""))
        w("")
        w("## Findings by category (in scope)\n")
        cats = collections.Counter((f["category"], f["severity"]) for f in inscope)
        w("| Category | Severity | Count | Meaning |")
        w("|---|---|---|---|")
        for (c, sv), n in sorted(cats.items(), key=lambda x: ({"error": 0, "warn": 1, "info": 2}.get(x[0][1], 3), x[0][0])):
            w("| %s | %s | %d | %s |" % (c, sv, n, CATEGORY_HELP.get(c, "")))
        w("")
        w("## All automatic findings (in scope)\n")
        w("Format: `Fnnnn [severity] category plan task line file: message`; `L` numbers are lines of the plan "
          "file named by the plan id (`T` = task number).\n")
        cur = None
        for f in inscope:
            key = (f["severity"], f["category"])
            if key != cur:
                w("\n### %s: %s\n" % (f["severity"], f["category"]))
                cur = key
            w("- %s %s" % (f["id"], f["text"].replace("|", "\\|")))
        w("")
        if outscope:
            w("## Findings that involve only out-of-scope plans\n")
            for f in outscope:
                w("- %s %s" % (f["id"], f["text"].replace("|", "\\|")))
            w("")
        w("## Method notes\n")
        for line in METHOD_NOTES:
            w("- " + line)
        w("")
        return "\n".join(out)

    def run(self):
        self.load()
        self.analyse()
        self.build_definitions()
        self.build_calls()
        self.find_duplicates()
        self.find_fixture_conflicts()
        self.find_file_issues()
        self.find_helper_and_undefined()
        self.find_near_names()
        self.find_contract_names()
        self.find_services()
        self.find_interfaces()
        self.find_contract_signatures()
        self.find_mentions()
        self.find_exports_and_owners()
        self.find_header_deps()
        self.find_roxygen()
        self.find_misc_r()
        self.find_parse_errors()
        self.find_attribution()
        return self.write()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--plan-dir", default=None)
    ap.add_argument("--spec-dir", default=None)
    ap.add_argument("--out", default=None,
                    help="output directory (default: a new temporary directory, so the large index never lands in the repo)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--scope", default="P01-P25",
                    help="plans whose findings are reported (others are parsed and indexed, and their findings "
                         "are listed separately); default P01-P25")
    ap.add_argument("--reuse-r", action="store_true",
                    help="cache the R analysis in <out>/.build_index_rcache.json and reuse it while the R blocks are unchanged")
    args = ap.parse_args(argv)
    if args.out is None:
        import tempfile
        args.out = tempfile.mkdtemp(prefix="gptr-plan-index-")
    b = Builder(args)
    jp, mp = b.run()
    tot = collections.Counter(f["severity"] for f in b.findings)
    print("wrote %s and %s: %d plans, %d blocks, %d definitions, %d calls, %d findings (%s)" % (
        jp, mp, len(b.plans), len(b.blocks), len(b.defs), len(b.calls), len(b.findings),
        ", ".join("%s %d" % (k, v) for k, v in sorted(tot.items()))))


if __name__ == "__main__":
    main()
