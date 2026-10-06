# The calibrated token estimator (architecture section 12.5; report G2 part f and its fact-check).
# Characters per o200k token by content class, fitted on a 730k-character corpus; CJK characters
# cost 0.848 tokens each and other non-ASCII characters 0.35. Median error 11.4% on held-out
# chunks against 43% for chars/4. Provider-reported usage is always authoritative.

#' Characters per o200k token by content class (G2 section 3.1)
#' @noRd
token_cpt = c(
  prose = 4.36, code = 3.24, r_output = 2.13, str = 2.01, csv = 1.57, json = 2.90,
  error = 2.98, describe = 2.39
)

#' @noRd
token_cjk_pattern = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]"

#' Whether an estimator input is one finite real number
#' @noRd
est_finite_number = function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x)
}

#' Estimated o200k tokens of `x` (joined with newlines) for a content class
#' @noRd
est_tokens = function(x, class = c("prose", "code", "r_output", "str", "csv", "json", "error",
                                   "describe")) {
  class = check_choice(class, names(token_cpt), "class")
  if (is.null(x) || !length(x)) return(0)
  x = as_utf8(as.character(x))
  x[is.na(x)] = "NA"
  sum(est_tokens_each(paste(x, collapse = "\n"), class))
}

#' Estimated tokens of each element (vectorised; used for per-line budgets)
#' @noRd
est_tokens_each = function(x, class) {
  if (!length(x)) return(numeric())
  x = as_utf8(x)
  n = nchar(x, type = "chars", allowNA = TRUE)
  n[is.na(n)] = nchar(x[is.na(n)], type = "bytes")
  ascii = nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), type = "bytes")
  other = pmax(n - ascii, 0)
  cjk = numeric(length(x))
  has = other > 0
  if (any(has)) {
    cjk[has] = n[has] - nchar(gsub(token_cjk_pattern, "", x[has], perl = TRUE), type = "chars")
  }
  ceiling(ascii / token_cpt[[class]] + 0.848 * cjk + 0.35 * (other - cjk))
}

#' The most leading lines within a token budget, counted with the line `notice(omitted)` when
#' given: all lines, else a binary search below them (where fewer lines never cost more)
#' @noRd
lines_fit = function(lines, budget, class, notice = NULL) {
  n = length(lines)
  fits = function(k) {
    est_tokens(c(lines[seq_len(k)], if (!is.null(notice)) notice(n - k)), class) <= budget
  }
  if (fits(n)) return(n)
  lo = 0L
  hi = n - 1L
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (fits(mid)) lo = mid else hi = mid - 1L
  }
  lo
}

#' Estimated tokens of an image (report G2 section 3.1 and its plot-size prototype)
#'
#' Anthropic (standard tier): the long edge is scaled to at most 1568 px, then the scale shrinks
#' in 1% steps until ceil(w/28) * ceil(h/28) is at most 1568. OpenAI GPT-5.x:
#' ceil(w/32) * ceil(h/32) * 1.2. Gemini 3: the default media resolution, 1120.
#' @noRd
est_image_tokens = function(width, height, api = "anthropic") {
  if (!est_finite_number(width)) arg_abort(width, "width", "one finite real dimension")
  if (!est_finite_number(height)) arg_abort(height, "height", "one finite real dimension")
  width = check_number(width, "width", min = 1)
  height = check_number(height, "height", min = 1)
  check_string(api, "api")
  if (api %in% c("openai", "openai-responses", "openai-completions")) {
    return(ceiling(ceiling(width / 32) * ceiling(height / 32) * 1.2))
  }
  if (api %in% c("google", "gemini", "google-generative-ai")) return(1120)
  scale = min(1, 1568 / max(width, height))
  repeat {
    tokens = ceiling(width * scale / 28) * ceiling(height * scale / 28)
    if (tokens <= 1568) return(tokens)
    scale = scale * 0.99
  }
}

#' The image blocks of a message list: position, id (8 hex of the data's sha256, NA without a data
#' string) and bytes
#' @noRd
images_scan = function(messages) {
  rows = list()
  for (i in seq_along(messages)) {
    content = messages[[i]]$content %||% list()
    for (j in seq_along(content)) {
      b = content[[j]]
      if (!identical(b$type, "image")) next
      id = if (rlang::is_string(b$data)) substr(hash_sha256(b$data), 1L, 8L) else NA_character_
      rows[[length(rows) + 1L]] = data.frame(msg = i, block = j, id = id,
                                             bytes = nchar(b$data, type = "bytes") * 3 / 4,
                                             stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(msg = integer(), block = integer(), id = character(), bytes = numeric(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Update the per-session estimator multiplier (EWMA of the log ratio; G2 section 3.3)
#'
#' `state` is NULL or `list(m, n)`; it starts at `prior`. It changes only when the estimate of the
#' new content is at least 150 tokens; the observed ratio is clamped to 0.5 to 3.
#' @noRd
est_multiplier = function(state, estimated, reported, prior) {
  if (is.null(state)) {
    if (!est_finite_number(prior) || prior <= 0) {
      arg_abort(prior, "prior", "one positive finite real multiplier")
    }
    state = list(m = prior, n = 0L)
  }
  usable = est_finite_number(estimated) && est_finite_number(reported) &&
    estimated >= 150 && reported > 0
  if (!usable) return(state)
  ratio = min(max(reported / estimated, 0.5), 3)
  list(m = exp(0.5 * log(state$m) + 0.5 * log(ratio)), n = state$n + 1L)
}

#' A short token count: 950, 1.2k, 3.4M ("unknown" when any count is unknown, IC-74); the unit
#' follows the printed value, so 999.7 is "1.0k"
#' @noRd
format_count = function(n) {
  n = sum(n)
  if (is.na(n)) return("unknown")
  if (round(n) < 1000) return(as.character(round(n)))
  k = sprintf("%.1f", n / 1000)
  if (as.numeric(k) < 1000) return(paste0(k, "k"))
  paste0(sprintf("%.1f", n / 1e6), "M")
}

#' A short cost in USD: "$0.0123"; "unknown cost" when any cost is unknown (IC-74)
#' @noRd
format_cost = function(x) {
  x = sum(x)
  if (is.na(x)) return("unknown cost")
  sprintf("$%.4f", x)
}
