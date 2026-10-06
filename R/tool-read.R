# The `read` tool and `peter$read()` (P10; research 11 section 5.5, research 21 section 2.2): Pi's
# read without line numbers, images by magic bytes, BOM/UTF-16/UTF-32/CP1252 decoding, line windows
# over a raw newline index (sparse above 16 MiB), the 2,000-line/50 KB/token caps and `skill:` paths
# (IC-68). Data files are never deserialised for a preview (CVE-2024-27322).

tool_max_lines = 2000L
tool_max_bytes = 51200L
read_big_file = 16 * 1024^2
read_index_min = 20 * 1024^2
read_index_every = 10000L
read_chunk = 4L * 1024L^2
# Bytes of a window kept by the streaming reader (twice the 50 KB cap, so a line cut there is
# always past the cap); the length of a longer first line is measured by scanning, not kept
read_window_cap = 2L * tool_max_bytes
read_sniff_bytes = 65536L
image_sniff_bytes = 4100L
image_max_edge = 2000L
image_max_b64 = 4.5 * 1024^2
binary_sniff = 8000L
replacement_sub = rawToChar(as.raw(c(0xEF, 0xBF, 0xBD)))
bom_len = c("UTF-8" = 3L, "UTF-16LE" = 2L, "UTF-16BE" = 2L, "UTF-32LE" = 4L, "UTF-32BE" = 4L)
bom_bytes = list("UTF-8" = as.raw(c(0xEF, 0xBB, 0xBF)), "UTF-16LE" = as.raw(c(0xFF, 0xFE)),
                 "UTF-16BE" = as.raw(c(0xFE, 0xFF)), "UTF-32LE" = as.raw(c(0xFF, 0xFE, 0, 0)),
                 "UTF-32BE" = as.raw(c(0, 0, 0xFE, 0xFF)))
binary_hints = c(rds = "readRDS()", rda = "load()", rdata = "load()", qs = "qs::qread()",
                 qs2 = "qs2::qs_read()", parquet = "arrow::read_parquet()",
                 feather = "arrow::read_feather()", xlsx = "readxl::read_excel()",
                 xls = "readxl::read_excel()", sav = "haven::read_sav()", dta = "haven::read_dta()",
                 fst = "fst::read_fst()", pdf = "pdftools::pdf_text()",
                 zip = "utils::unzip(list = TRUE)", gz = "readLines(gzfile())")

# Sparse line indexes of files above 20 MB (read_line_index())
read_index_cache = list2env(list(entries = list(), clock = 0), parent = emptyenv())

#' Pi formatSize(): 512B, 50.0KB, 3.0MB
#' @noRd
format_size = function(bytes) {
  if (bytes < 1024) return(sprintf("%dB", as.integer(bytes)))
  if (bytes < 1024^2) return(sprintf("%.1fKB", bytes / 1024))
  sprintf("%.1fMB", bytes / 1024^2)
}

#' Raw bytes of a file: all, or `n` bytes from byte `offset`
#' @noRd
read_raw = function(path, n = NULL, offset = 0) {
  p = fs_path(path)
  size = file.size(p)
  if (is.na(size)) {
    gptr_abort(paste0("ENOENT: no such file or directory, access '", path, "'"), "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  con = file(p, "rb")
  on.exit(close(con), add = TRUE)
  if (offset > 0) seek(con, offset, rw = "read")
  readBin(con, "raw", n = if (is.null(n)) size - offset else n)
}

#' Byte-order mark of a raw vector ("" when there is none)
#' @noRd
sniff_bom = function(b) {
  n = length(b)
  starts = function(x) n >= length(x) && identical(b[seq_along(x)], x)
  if (starts(bom_bytes[["UTF-8"]])) return("UTF-8")
  if (starts(bom_bytes[["UTF-32LE"]])) return("UTF-32LE")
  if (starts(bom_bytes[["UTF-32BE"]])) return("UTF-32BE")
  if (starts(bom_bytes[["UTF-16LE"]])) return("UTF-16LE")
  if (starts(bom_bytes[["UTF-16BE"]])) return("UTF-16BE")
  ""
}

#' Binary heuristic (git): a NUL byte in the first 8000 bytes; UTF-16/32 text with a BOM is exempt
#' @noRd
is_binary_raw = function(b, sniff = binary_sniff) {
  bom = sniff_bom(b)
  if (nzchar(bom) && bom != "UTF-8") return(FALSE)
  n = min(length(b), sniff)
  n > 0L && any(b[seq_len(n)] == as.raw(0L))
}

#' Drop an incomplete UTF-8 sequence at the end of a byte vector (a cut inside a character); a
#' complete last character is kept, and invalid bytes are left for the decoder
#' @noRd
utf8_trim_partial = function(b) {
  n = length(b)
  if (!n) return(b)
  i = n
  while (i > 1L && i > n - 3L && bitwAnd(as.integer(b[i]), 0xC0L) == 0x80L) i = i - 1L
  lead = as.integer(b[i])
  need = if (lead >= 0xF0L) 4L else if (lead >= 0xE0L) 3L else if (lead >= 0xC0L) 2L else 1L
  if (n - i + 1L < need) b[seq_len(i - 1L)] else b
}

#' Decode bytes to one UTF-8 string without BOM: `list(text, encoding, bom, lossy)`
#' Order: BOM; valid UTF-8; CP1252 (then latin1) when invalid bytes dominate; else UTF-8 with U+FFFD
#' (`lossy`; iconv(sub =) only on unmarked bytes, never "Unicode": report 11 rows 8-9).
#' @noRd
decode_raw = function(b, fallback = c("CP1252", "latin1")) {
  if (!length(b)) return(list(text = as_utf8(""), encoding = "UTF-8", bom = FALSE, lossy = FALSE))
  bom = sniff_bom(b)
  if (nzchar(bom)) {
    body = b[-seq_len(bom_len[[bom]])]
    if (bom != "UTF-8") {
      txt = iconv(list(body), from = bom, to = "UTF-8", sub = replacement_sub)
      return(list(text = as_utf8(txt), encoding = bom, bom = TRUE, lossy = FALSE))
    }
    b = body
  }
  if (any(b == as.raw(0L))) {
    gptr_abort("The file contains NUL bytes: it is binary.", "invalid_argument", arg = "path",
               expected = "a text file")
  }
  txt = rawToChar(b)
  if (validUTF8(txt)) {
    return(list(text = as_utf8(txt), encoding = "UTF-8", bom = nzchar(bom), lossy = FALSE))
  }
  n_hi = sum(b >= as.raw(0x80))
  n_bad = (nchar(iconv(txt, "UTF-8", "UTF-8", sub = "byte"), "bytes") - length(b)) / 3
  if (!nzchar(bom) && n_bad * 2 > (n_hi - n_bad)) {
    for (enc in fallback) {
      out = suppressWarnings(iconv(txt, from = enc, to = "UTF-8"))
      if (!is.na(out)) return(list(text = as_utf8(out), encoding = enc, bom = FALSE, lossy = FALSE))
    }
  }
  list(text = as_utf8(iconv(txt, "UTF-8", "UTF-8", sub = replacement_sub)), encoding = "UTF-8",
       bom = nzchar(bom), lossy = TRUE)
}

#' Encode UTF-8 text for writing; fails before any file is touched when a character is not
#' representable in the target encoding (report 11 section 2.3)
#' @noRd
encode_text = function(text, encoding = "UTF-8", bom = FALSE) {
  text = as_utf8(text)
  out = if (identical(encoding, "UTF-8")) {
    charToRaw(text)
  } else {
    r = iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1L]]
    if (is.null(r)) {
      gptr_abort(
        paste0("Text contains characters that cannot be represented in the file's encoding (",
               encoding, ")."),
        "invalid_argument", arg = "content", expected = "text representable in the file's encoding"
      )
    }
    r
  }
  if (isTRUE(bom) && encoding %in% names(bom_bytes)) out = c(bom_bytes[[encoding]], out)
  out
}

#' JavaScript "x".split("\n") semantics: "a\n" -> c("a", ""), "" -> "" (re-marked UTF-8, report 11
#' P1)
#' @noRd
split_lines_js = function(x) {
  out = strsplit(paste0(x, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  if (!length(out)) out = ""
  utf8_mark(out)
}

#' Pi splitLinesForCounting(): "" -> no lines; one trailing "\n" is not an extra line
#' @noRd
split_lines_count = function(x) {
  if (!nzchar(x)) return(character())
  utf8_mark(strsplit(x, "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
}

#' Pi detectLineEnding(): CRLF when the first line ending is CRLF, else LF
#' @noRd
detect_eol = function(x) {
  lf = regexpr("\n", x, fixed = TRUE, useBytes = TRUE)
  crlf = regexpr("\r\n", x, fixed = TRUE, useBytes = TRUE)
  if (lf < 0 || crlf < 0) return("\n")
  if (crlf < lf) "\r\n" else "\n"
}

#' CRLF and lone CR to LF
#' @noRd
normalize_lf = function(x) {
  x = gsub("\r\n", "\n", x, fixed = TRUE, useBytes = TRUE)
  utf8_mark(gsub("\r", "\n", x, fixed = TRUE, useBytes = TRUE))
}

#' Keep the first lines within a line and byte limit, never a partial line (Pi truncateHead)
#' @noRd
truncate_lines_head = function(lines, max_lines = tool_max_lines, max_bytes = tool_max_bytes) {
  n = length(lines)
  lb = as.numeric(nchar(lines, type = "bytes"))
  if (n <= max_lines && sum(lb) + max(0, n - 1) <= max_bytes) {
    return(list(lines = lines, truncated = FALSE, by = NA_character_, first_line_exceeds = FALSE))
  }
  if (n && lb[1L] > max_bytes) {
    return(list(lines = character(), truncated = TRUE, by = "bytes", first_line_exceeds = TRUE))
  }
  k = min(n, max_lines)
  cum = cumsum(lb[seq_len(k)] + c(0, rep(1, k - 1L)))
  fit = sum(cum <= max_bytes)
  list(lines = lines[seq_len(fit)], truncated = TRUE, by = if (fit < k) "bytes" else "lines",
       first_line_exceeds = FALSE)
}

#' Image type from magic bytes (never the extension; Pi mime.ts); NA when not an accepted image
#' JPEG-LS and animated PNG are rejected; a BMP needs a plausible DIB header (report 01, 2.3).
#' @noRd
detect_image_mime = function(b) {
  u32be = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(3:0))
  ascii_at = function(o, s) {
    r = charToRaw(s)
    length(b) >= o + length(r) - 1L && identical(b[o:(o + length(r) - 1L)], r)
  }
  if (length(b) >= 3L && identical(b[1:3], as.raw(c(0xFF, 0xD8, 0xFF)))) {
    return(if (length(b) >= 4L && b[4] == as.raw(0xF7)) NA_character_ else "image/jpeg")
  }
  png_sig = as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
  if (length(b) >= 16L && identical(b[1:8], png_sig)) {
    if (u32be(9L) != 13 || !ascii_at(13L, "IHDR")) return(NA_character_)
    off = 9L
    while (off + 7L <= length(b)) {
      if (ascii_at(off + 4L, "acTL")) return(NA_character_)
      if (ascii_at(off + 4L, "IDAT")) break
      off = off + 12L + u32be(off)
    }
    return("image/png")
  }
  if (ascii_at(1L, "GIF87a") || ascii_at(1L, "GIF89a")) return("image/gif")
  if (ascii_at(1L, "RIFF") && ascii_at(9L, "WEBP")) return("image/webp")
  if (ascii_at(1L, "BM") && length(b) >= 26L && bmp_header_ok(b)) return("image/bmp")
  NA_character_
}

#' Plausible BMP file and DIB headers (Pi mime.ts, as ported in report 01 section 5): file size 0
#' or at least 26, pixel data after both headers and inside the file, a core (12) or info (40-124)
#' header, one plane and a standard bit depth
#' @noRd
bmp_header_ok = function(b) {
  u32le = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(0:3))
  u16le = function(o) as.integer(b[o]) + 256L * as.integer(b[o + 1L])
  fsize = u32le(3L)
  pix = u32le(11L)
  dib = u32le(15L)
  if ((fsize != 0 && fsize < 26) || pix < 14 + dib || (fsize != 0 && pix >= fsize)) return(FALSE)
  if (dib == 12) {
    planes = u16le(23L)
    bpp = u16le(25L)
  } else if (dib >= 40 && dib <= 124 && length(b) >= 30L) {
    planes = u16le(27L)
    bpp = u16le(29L)
  } else {
    return(FALSE)
  }
  planes == 1L && bpp %in% c(1L, 4L, 8L, 16L, 24L, 32L)
}

#' Width and height from the image header without decoding; NULL when unknown (JPEG fill bytes
#' before a marker are skipped; a BMP core header has 16-bit dimensions)
#' @noRd
image_dims = function(b, mime) {
  u32be = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(3:0))
  u32le = function(o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(0:3))
  u16le = function(o) as.integer(b[o]) + 256L * as.integer(b[o + 1L])
  u16be = function(o) 256L * as.integer(b[o]) + as.integer(b[o + 1L])
  jpeg_dims = function() {
    o = 3L
    n = length(b)
    while (o + 8L <= n) {
      if (b[o] != as.raw(0xFF)) {
        o = o + 1L
        next
      }
      m = as.integer(b[o + 1L])
      if (m == 0xFF) {
        o = o + 1L
        next
      }
      if (m %in% c(0xC0:0xC3, 0xC5:0xC7, 0xC9:0xCB, 0xCD:0xCF)) {
        return(c(u16be(o + 7L), u16be(o + 5L)))
      }
      if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
        o = o + 2L
        next
      }
      o = o + 2L + u16be(o + 2L)
    }
    NULL
  }
  webp_dims = function() {
    if (identical(b[13:16], charToRaw("VP8X"))) {
      return(c(1 + u16le(25L) + 65536 * as.integer(b[27]),
               1 + u16le(28L) + 65536 * as.integer(b[30])))
    }
    if (identical(b[13:16], charToRaw("VP8L"))) {
      v = u32le(22L)
      return(c(1 + v %% 16384, 1 + (v %/% 16384) %% 16384))
    }
    c(u16le(27L) %% 16384, u16le(29L) %% 16384)
  }
  bmp_dims = function() {
    if (u32le(15L) == 12) return(c(u16le(19L), u16le(21L)))
    c(u32le(19L), abs(u32le(23L) - if (u32le(23L) > 2^31) 2^32 else 0))
  }
  dims = function() {
    switch(mime,
           "image/png" = c(u32be(17L), u32be(21L)),
           "image/gif" = c(u16le(7L), u16le(9L)),
           "image/bmp" = bmp_dims(),
           "image/webp" = webp_dims(),
           "image/jpeg" = jpeg_dims(),
           NULL)
  }
  tryCatch(dims(), error = function(e) NULL)
}

#' base64 without line breaks (openssl when installed; jsonlite wraps every 72 characters)
#' @noRd
base64_raw = function(b) {
  if (requireNamespace("openssl", quietly = TRUE)) return(as.character(openssl::base64_encode(b)))
  gsub("[\r\n]", "", jsonlite::base64_enc(b))
}

#' Image bytes to an inline payload: unchanged when a provider-native format within 2000 px and 4.5
#' MB of base64 (Pi image-resize-core.ts), else converted and resized with magick (Suggests) or
#' omitted with a note. Returns `list(ok, data, mime, note, dims)`.
#' @noRd
process_image = function(b, mime) {
  dims = image_dims(b, mime)
  b64_size = ceiling(length(b) / 3) * 4
  native = mime %in% c("image/png", "image/jpeg", "image/gif", "image/webp")
  if (native && !is.null(dims) && all(dims <= image_max_edge) && b64_size < image_max_b64) {
    return(list(ok = TRUE, data = base64_raw(b), mime = mime, note = NULL, dims = dims))
  }
  if (!requireNamespace("magick", quietly = TRUE)) {
    shape = if (is.null(dims)) "" else sprintf(", %dx%d px", as.integer(dims[1]),
                                               as.integer(dims[2]))
    note = paste0("[Image omitted: ", mime, " is ", format_size(length(b)), shape,
                  "; install the 'magick' package to let gptr resize or convert it.]")
    return(list(ok = FALSE, note = note))
  }
  tryCatch(process_image_magick(b, mime), error = function(e) {
    list(ok = FALSE,
         note = "[Image omitted: could not be converted to a supported inline image format.]")
  })
}

#' Resize and convert image bytes with magick: the smaller of PNG and JPEG q85 -> q40 within 2000
#' px and 4.5 MB of base64. An image magick cannot decode (a corrupt file whose magic bytes passed)
#' errors here, and process_image() omits it with Pi's note.
#' @noRd
process_image_magick = function(b, mime) {
  img = magick::image_read(b)[1]
  info = magick::image_info(img)
  if (info$width > image_max_edge || info$height > image_max_edge) {
    img = magick::image_resize(img, sprintf("%dx%d>", image_max_edge, image_max_edge))
  }
  best = NULL
  for (q in c(NA, 85, 70, 55, 40)) {
    cand = if (is.na(q)) {
      magick::image_write(img, format = "png")
    } else {
      magick::image_write(magick::image_flatten(img), format = "jpeg", quality = q)
    }
    if (is.null(best) || length(cand) < length(best$raw)) {
      best = list(raw = cand, mime = if (is.na(q)) "image/png" else "image/jpeg")
    }
    if (ceiling(length(best$raw) / 3) * 4 < image_max_b64) break
  }
  if (ceiling(length(best$raw) / 3) * 4 >= image_max_b64) {
    note = "[Image omitted: could not be resized below the inline image size limit.]"
    return(list(ok = FALSE, note = note))
  }
  ni = magick::image_info(img)
  notes = character()
  if (!identical(best$mime, mime)) {
    notes = paste0("[Image converted from ", mime, " to ", best$mime, ".]")
  }
  if (ni$width != info$width) {
    fmt = paste("[Image: original %dx%d, displayed at %dx%d.",
                "Multiply coordinates by %.2f to map to original image.]")
    notes = c(notes, sprintf(fmt, as.integer(info$width), as.integer(info$height),
                             as.integer(ni$width), as.integer(ni$height), info$width / ni$width))
  }
  list(ok = TRUE, data = base64_raw(best$raw), mime = best$mime,
       note = if (length(notes)) paste(notes, collapse = "\n") else NULL,
       dims = c(ni$width, ni$height))
}

#' `skill:<name>/<path>` to a file inside the skill's directory (the `skill.body` service of P17)
#' @noRd
skill_file_path = function(name, rel) {
  if (!ext_service_has("skill.body")) {
    gptr_abort(paste0("Skills are not available in this session (skill:", name, ")."),
               "not_available", member = "skill.body", provided_by = "P17")
  }
  sk = tryCatch(ext_service_get("skill.body")(name), error = function(e) NULL)
  if (!is.list(sk) || !is.character(sk$dir) || length(sk$dir) != 1L) {
    gptr_abort(paste0("Unknown skill: ", name), "invalid_argument", arg = "path",
               expected = "skill:<name>/<path> of a visible skill")
  }
  inner = tool_path_norm(rel)
  if (tool_path_is_abs(rel) || inner == ".." || startsWith(inner, "../")) {
    gptr_abort(paste0("A skill path must stay inside the skill directory: ", rel),
               "invalid_argument", arg = "path",
               expected = "a path relative to the skill directory")
  }
  tool_path_norm(file.path(sk$dir, inner))
}

#' Resolve a path for reading: skill pseudo-paths, then Pi's fallbacks for macOS screenshot names
#' (U+202F before AM/PM, NFD, U+2019) when the path does not exist
#' @noRd
read_resolve = function(path) {
  m = regmatches(path, regexec("^skill:([^/]+)/(.+)$", path))[[1L]]
  if (length(m)) return(skill_file_path(m[2L], m[3L]))
  res = resolve_tool_path(path)
  if (file.exists(fs_path(res))) return(res)
  nfd = if (requireNamespace("stringi", quietly = TRUE)) stringi::stri_trans_nfd(res) else res
  cand = c(gsub(" (AM|PM)\\.", "\u202f\\1.", res, ignore.case = TRUE, perl = TRUE),
           nfd, gsub("'", "\u2019", res, fixed = TRUE), gsub("'", "\u2019", nfd, fixed = TRUE))
  for (v in unique(as_utf8(cand))) {
    if (!identical(v, res) && file.exists(fs_path(v))) return(v)
  }
  res
}

#' Decode a window of text and split it (JS semantics, the CR of CRLF removed)
#' An 8-bit window iconv() cannot convert (a CP1252 gap byte) is decoded as latin1; `lossy` also
#' when this window holds invalid UTF-8 (replaced with U+FFFD).
#' @noRd
read_decode_lines = function(txt, encoding, lossy) {
  utf8 = identical(encoding, "UTF-8")
  bad = utf8 && !validUTF8(txt)
  if (utf8) {
    if (lossy || bad) txt = iconv(txt, "UTF-8", "UTF-8", sub = replacement_sub)
  } else {
    out = iconv(txt, encoding, "UTF-8")
    txt = if (is.na(out)) iconv(txt, "latin1", "UTF-8") else out
  }
  lines = split_lines_js(txt)
  crlf = any(endsWith(lines[seq_len(min(length(lines), 1000L))], "\r"))
  list(lines = utf8_mark(sub("\r$", "", lines, perl = TRUE, useBytes = TRUE)),
       eol = if (crlf) "\r\n" else "\n", lossy = isTRUE(lossy) || bad)
}

#' Line window of a file up to 16 MiB: raw newline index, decode and split only the window
#' The encoding is decided on the whole file; any NUL in a UTF-8 or 8-bit file makes it binary
#' (ripgrep), found with grepRaw() because rawToChar() silently drops trailing NULs.
#' @noRd
read_window_small = function(abs, offset, n) {
  b = read_raw(abs)
  if (is_binary_raw(b)) return(list(binary = TRUE))
  bom = sniff_bom(b)
  if (nzchar(bom) && bom != "UTF-8") {
    d = decode_raw(b)
    lines = split_lines_js(d$text)
    total = length(lines)
    last = if (is.null(n)) total else min(total, as.numeric(offset) + n - 1)
    sel = if (offset > total) character() else lines[offset:last]
    crlf = any(endsWith(sel, "\r"))
    sel = utf8_mark(sub("\r$", "", sel, perl = TRUE, useBytes = TRUE))
    return(list(binary = FALSE, lines = sel, total = total, encoding = d$encoding, lossy = FALSE,
                eol = if (crlf) "\r\n" else "\n"))
  }
  body = if (bom == "UTF-8") b[-(1:3)] else b
  if (length(grepRaw(as.raw(0L), body, fixed = TRUE))) return(list(binary = TRUE))
  all_txt = rawToChar(body)
  d = if (validUTF8(all_txt)) list(encoding = "UTF-8", lossy = FALSE) else decode_raw(b)
  b = body
  nl = grepRaw(as.raw(10L), b, fixed = TRUE, all = TRUE)
  total = length(nl) + 1L
  if (offset > total) {
    return(list(binary = FALSE, lines = character(), total = total, encoding = d$encoding,
                lossy = d$lossy, eol = "\n"))
  }
  last = if (is.null(n)) total else min(total, as.numeric(offset) + n - 1)
  s0 = if (offset == 1L) 1L else nl[offset - 1L] + 1L
  e0 = if (last <= length(nl)) nl[last] - 1L else length(b)
  wtxt = if (e0 >= s0) rawToChar(b[s0:e0]) else ""
  lines = read_decode_lines(wtxt, d$encoding, d$lossy)
  list(binary = FALSE, lines = lines$lines, total = total, encoding = d$encoding,
       lossy = lines$lossy, eol = lines$eol)
}

#' Sparse line index: 0-based byte offsets of lines 1, every + 1, 2 * every + 1, ... and the total
#' line count (JS semantics), in one streaming grepRaw() pass (report 21 section 2.2)
#' @noRd
read_line_index_build = function(abs, every = read_index_every, chunk = read_chunk) {
  con = file(fs_path(abs), "rb")
  on.exit(close(con), add = TRUE)
  offs = list(0)
  k = 1L
  line = 1
  base = 0
  repeat {
    r = readBin(con, "raw", chunk)
    if (!length(r)) break
    p = grepRaw(as.raw(10L), r, fixed = TRUE, all = TRUE)
    if (length(p)) {
      want = which(((line + seq_along(p) - 1) %% every) == 0)
      if (length(want)) {
        k = k + 1L
        offs[[k]] = base + p[want]
      }
      line = line + length(p)
    }
    base = base + length(r)
  }
  list(every = every, offsets = as.numeric(unlist(offs)), total = as.integer(line))
}

#' The sparse index of a file, cached per process for files above 20 MB (key: path, size, mtime)
#' At most 8 entries, least recently used evicted, an old version's entry dropped; a list compared
#' by value, since an environment symbol made from a path would need locale translation.
#' @noRd
read_line_index = function(abs, size, every = read_index_every) {
  mtime = as.numeric(file.mtime(fs_path(abs)))
  ents = read_index_cache$entries
  read_index_cache$clock = read_index_cache$clock + 1
  same = vapply(ents, function(e) identical(e$path, abs), TRUE)
  hit = which(same & vapply(ents, function(e) {
    identical(e$size, as.numeric(size)) && identical(e$mtime, mtime) &&
      identical(e$every, as.numeric(every))
  }, TRUE))
  if (length(hit)) {
    ents[[hit[1L]]]$used = read_index_cache$clock
    read_index_cache$entries = ents
    return(ents[[hit[1L]]]$idx)
  }
  idx = read_line_index_build(abs, every = every)
  if (size > read_index_min) {
    ents = ents[!same]
    if (length(ents) >= 8L) {
      used = vapply(ents, function(e) e$used, 0)
      ents = ents[-order(used)[seq_len(length(ents) - 7L)]]
    }
    ents[[length(ents) + 1L]] = list(path = abs, size = as.numeric(size), mtime = mtime,
                                     every = as.numeric(every), idx = idx,
                                     used = read_index_cache$clock)
    read_index_cache$entries = ents
  }
  idx
}

#' Stream the bytes of a line window: skip `skip` lines from byte `start`, then keep `want` lines
#' (without the last newline), at most `cap` bytes; a first line cut by the cap is scanned to
#' measure it (`first_bytes`, without its line ending; NA when not cut).
#' @noRd
read_span = function(abs, start, skip, want, cap = Inf, chunk = 262144L) {
  con = file(fs_path(abs), "rb")
  on.exit(close(con), add = TRUE)
  if (start > 0) seek(con, start, rw = "read")
  nl = as.raw(10L)
  cr = as.raw(13L)
  r = raw()
  while (skip > 0) {
    r = readBin(con, "raw", chunk)
    if (!length(r)) break
    p = grepRaw(nl, r, fixed = TRUE, all = TRUE)
    if (length(p) >= skip) {
      r = r[-seq_len(p[skip])]
      skip = 0
    } else {
      skip = skip - length(p)
      r = raw()
    }
  }
  pieces = list()
  kept = 0
  pos = 0
  seen = 0
  first_nl = NA_real_
  first = NA_real_
  prev = as.raw(0L)
  cut = FALSE
  repeat {
    if (!length(r)) {
      r = readBin(con, "raw", chunk)
      if (!length(r)) break
    }
    p = grepRaw(nl, r, fixed = TRUE, all = TRUE)
    if (is.na(first_nl) && length(p)) {
      first_nl = pos + p[1L] - 1
      first = first_nl - ((if (p[1L] > 1L) r[p[1L] - 1L] else prev) == cr)
    }
    done = seen + length(p) >= want
    end = if (done) p[want - seen] - 1 else length(r)
    if (kept + end > cap) {
      end = cap - kept
      cut = TRUE
    }
    if (end > 0) pieces[[length(pieces) + 1L]] = r[seq_len(end)]
    kept = kept + end
    seen = seen + length(p)
    pos = pos + length(r)
    prev = r[length(r)]
    if (done || cut) break
    r = raw()
  }
  first_cut = cut && (is.na(first_nl) || first_nl >= kept)
  if (first_cut && is.na(first_nl)) {
    repeat {
      r = readBin(con, "raw", chunk)
      if (!length(r)) {
        first = pos - (prev == cr)
        break
      }
      p = grepRaw(nl, r, fixed = TRUE)
      if (length(p)) {
        first = pos + p - 1 - ((if (p > 1L) r[p - 1L] else prev) == cr)
        break
      }
      pos = pos + length(r)
      prev = r[length(r)]
    }
  }
  list(bytes = if (length(pieces)) do.call(c, pieces) else raw(), cut = cut,
       first_bytes = if (first_cut) first else NA_real_)
}

#' Line window of a file above 16 MiB through the sparse index (bounded memory)
#' The encoding is decided on the first 64 KB; a NUL there or in the window makes it binary. At most
#' `cap` bytes are kept; a first line longer than `cap` is measured by scanning (`first_bytes`).
#' @noRd
read_window_big = function(abs, offset, n, size, every = read_index_every, cap = Inf) {
  head = read_raw(abs, n = min(size, read_sniff_bytes))
  if (is_binary_raw(head, sniff = length(head))) return(list(binary = TRUE))
  bom = sniff_bom(head)
  if (nzchar(bom) && bom != "UTF-8") {
    gptr_abort(paste("UTF-16 and UTF-32 files larger than 16 MB are not supported by read;",
                     "load it in the r tool."),
               "invalid_argument", arg = "path", expected = "a UTF-8 or 8-bit text file")
  }
  d = decode_raw(if (length(head) < size) utf8_trim_partial(head) else head)
  idx = read_line_index(abs, size, every = every)
  if (offset > idx$total) {
    return(list(binary = FALSE, lines = character(), total = idx$total, encoding = d$encoding,
                lossy = d$lossy, eol = "\n"))
  }
  want = if (is.null(n)) idx$total - offset + 1 else min(n, idx$total - offset + 1)
  k = (offset - 1) %/% idx$every
  start_byte = idx$offsets[k + 1]
  skip = offset - (k * idx$every + 1)
  span = read_span(abs, start_byte, skip, want, cap = cap)
  bytes = span$bytes
  first_bytes = span$first_bytes
  if (start_byte == 0 && skip == 0 && bom == "UTF-8") {
    bytes = bytes[-seq_len(min(3L, length(bytes)))]
    first_bytes = first_bytes - 3
  }
  if (any(bytes == as.raw(0L))) return(list(binary = TRUE))
  if (span$cut && identical(d$encoding, "UTF-8")) bytes = utf8_trim_partial(bytes)
  lines = read_decode_lines(rawToChar(bytes), d$encoding, d$lossy)
  list(binary = FALSE, lines = lines$lines, total = idx$total, encoding = d$encoding,
       lossy = lines$lossy, eol = lines$eol, first_bytes = first_bytes)
}

#' Lines `offset .. offset + n - 1` of a text file with the total line count
#' `cap` bounds the bytes kept by the streaming reader only (read_window_big()).
#' @noRd
read_text_window = function(abs, offset = 1L, n = NULL, big = read_big_file,
                            every = read_index_every, cap = Inf) {
  size = file.size(fs_path(abs))
  if (size <= big) return(read_window_small(abs, offset, n))
  read_window_big(abs, offset, n, size, every = every, cap = cap)
}

#' Estimator class of a file by its extension
#' @noRd
read_token_class = function(path) {
  ext = tolower(path_ext(path))
  code = c("r", "rmd", "qmd", "py", "js", "ts", "c", "cpp", "h", "java", "sql", "sh", "jl", "rs",
           "go")
  if (ext %in% code) return("code")
  if (ext %in% c("csv", "tsv")) return("csv")
  if (ext %in% c("json", "jsonl", "ipynb")) return("json")
  "prose"
}

#' The leading part of one long line, cut on a UTF-8 character boundary
#' @noRd
read_line_prefix = function(line, max_bytes) {
  b = charToRaw(line)
  as_utf8(rawToChar(utf8_trim_partial(b[seq_len(min(max_bytes, length(b)))])))
}

#' Shared core of read_file() and peter$read(): kind (text, empty, image, binary), the window and
#' notices
#' @noRd
read_core = function(path, offset = NULL, limit = NULL, budget_tokens = Inf) {
  check_string(path, "path")
  check_number(offset, "offset", min = 0, max = .Machine$integer.max, null = TRUE)
  check_number(limit, "limit", min = 1, max = .Machine$integer.max, null = TRUE)
  abs = read_resolve(path)
  p = fs_path(abs)
  if (!file.exists(p)) {
    gptr_abort(paste0("ENOENT: no such file or directory, access '", abs, "'"), "invalid_argument",
               arg = "path", expected = "an existing file")
  }
  if (dir.exists(p)) {
    gptr_abort(paste0("EISDIR: illegal operation on a directory, read '", abs, "'"),
               "invalid_argument", arg = "path", expected = "a file, not a directory")
  }
  if (file.access(p, 4L) != 0L) {
    gptr_abort(paste0("EACCES: permission denied, access '", abs, "'"), "invalid_argument",
               arg = "path", expected = "a readable file")
  }
  size = file.size(p)
  start = if (is.null(offset) || offset < 1) 1L else as.integer(offset)
  out = list(kind = "text", path = path, abs = abs, size = size, start = start, total = NA_integer_,
             lines = character(), truncated = FALSE, by = NA_character_,
             first_line_bytes = NA_real_, first_line_limit = "bytes",
             user_limited = !is.null(limit), encoding = "UTF-8",
             eol = "\n", lossy = FALSE, image = NULL, note = NULL, budget_tokens = budget_tokens)
  if (size == 0) {
    out$kind = "empty"
    out$total = 0L
    return(out)
  }
  head = read_raw(abs, n = min(size, read_sniff_bytes))
  mime = detect_image_mime(head[seq_len(min(length(head), image_sniff_bytes))])
  if (!is.na(mime)) {
    im = process_image(read_raw(abs), mime)
    out$kind = "image"
    shown_mime = if (isTRUE(im$ok)) im$mime else mime
    out$note = paste(c(paste0("Read image file [", shown_mime, "]"), im$note), collapse = "\n")
    if (isTRUE(im$ok)) {
      out$image = block_image(im$data, mime = im$mime, source = "file",
                              width = as.integer(im$dims[1]), height = as.integer(im$dims[2]))
    }
    return(out)
  }
  if (is_binary_raw(head)) {
    out$kind = "binary"
    return(out)
  }
  w = read_text_window(abs, start, if (is.null(limit)) tool_max_lines + 1L else as.integer(limit),
                       cap = read_window_cap)
  if (isTRUE(w$binary)) {
    out$kind = "binary"
    return(out)
  }
  out$total = w$total
  out$encoding = w$encoding
  out$eol = w$eol
  out$lossy = isTRUE(w$lossy)
  if (start > w$total) {
    gptr_abort(paste0("Offset ", format(offset, scientific = FALSE, trim = TRUE),
                      " is beyond end of file (", w$total,
                      " lines total)"),
               "invalid_argument", arg = "offset", expected = "a line within the file")
  }
  tr = truncate_lines_head(w$lines)
  lines = tr$lines
  cls = read_token_class(abs)
  if (!tr$first_line_exceeds && length(lines) && is.finite(budget_tokens) &&
        est_tokens(lines, cls) > budget_tokens) {
    k = lines_fit(lines, budget_tokens, cls)
    if (k == 0L) {
      tr$first_line_exceeds = TRUE
      out$first_line_limit = "tokens"
    } else {
      lines = lines[seq_len(k)]
      tr$truncated = TRUE
      tr$by = "tokens"
    }
  }
  if (tr$first_line_exceeds) {
    first = w$lines[1L]
    keep = tool_max_bytes
    if (is.finite(budget_tokens)) {
      per_token = nchar(first, type = "bytes") / max(1, est_tokens(first, cls))
      keep = min(keep, floor(per_token * budget_tokens))
    }
    lines = read_line_prefix(first, keep)
    measured = w$first_bytes %||% NA_real_
    out$first_line_bytes = if (is.na(measured)) nchar(first, type = "bytes") else measured
    tr$truncated = TRUE
    tr$by = "first_line"
  }
  out$lines = lines
  out$truncated = isTRUE(tr$truncated)
  out$by = tr$by
  out
}

#' Notice lines of a read: Pi's texts plus the first-line, token-cap and encoding notices of report
#' 11 (a first line cut by the token budget names that budget, not the 50 KB cap)
#' @noRd
read_notices = function(rc) {
  n = length(rc$lines)
  end = rc$start + n - 1L
  notes = if (identical(rc$by, "first_line")) {
    limit = if (identical(rc$first_line_limit, "tokens")) {
      paste0(as.integer(rc$budget_tokens), " token limit")
    } else {
      paste0(format_size(tool_max_bytes), " limit")
    }
    paste0("[Line ", rc$start, " is ", format_size(rc$first_line_bytes), ", exceeds the ", limit,
           "; showing its first ", format_size(nchar(rc$lines[1L], type = "bytes")),
           ". Use the r tool (for example substr()) to see the rest.]")
  } else if (isTRUE(rc$truncated)) {
    why = switch(rc$by, bytes = paste0(" (", format_size(tool_max_bytes), " limit)"),
                 tokens = paste0(" (", as.integer(rc$budget_tokens), " token limit)"), "")
    paste0("[Showing lines ", rc$start, "-", end, " of ", rc$total, why, ". Use offset=", end + 1L,
           " to continue.]")
  } else if (isTRUE(rc$user_limited) && end < rc$total) {
    paste0("[", rc$total - end, " more lines in file. Use offset=", end + 1L, " to continue.]")
  }
  c(notes, if (!identical(rc$encoding, "UTF-8")) paste0("[Decoded from ", rc$encoding, "]"),
    if (isTRUE(rc$lossy)) "[File is not valid UTF-8; invalid bytes shown as U+FFFD]")
}

#' Binary-file notice with a loading hint (report 11 section 3.3)
#' @noRd
read_binary_text = function(path, abs, size) {
  ext = tolower(path_ext(abs))
  hint = if (ext %in% names(binary_hints)) binary_hints[[ext]] else "readBin()"
  paste0("[Binary file: ", path, " (", format_size(size), "). Not shown as text. ",
         "Load it with the r tool, e.g. ", hint, ".]")
}

#' Text of a read window: the lines and, after a blank line, the notices
#' @noRd
read_text_body = function(rc) {
  body = paste(rc$lines, collapse = "\n")
  notes = read_notices(rc)
  if (length(notes)) paste0(body, "\n\n", paste(notes, collapse = "\n")) else body
}

#' Read a file for the model: the `read` tool (contract section 7.10)
#' Returns `list(text, image, details = list(path, offset, limit, lines_total, truncated, image,
#' encoding, eol), value)`; `value` is the same window's `gptr_lines` without the image block.
#' @noRd
read_file = function(path, offset = NULL, limit = NULL,
                     budget_tokens = gptr_opt("read_max_tokens")) {
  check_number(budget_tokens, "budget_tokens", min = 1)
  rc = read_core(path, offset, limit, budget_tokens = budget_tokens)
  details = list(path = rc$abs, offset = rc$start, limit = length(rc$lines), lines_total = rc$total,
                 truncated = isTRUE(rc$truncated), image = identical(rc$kind, "image"),
                 encoding = rc$encoding, eol = rc$eol)
  text = switch(rc$kind,
                empty = paste0("[File is empty: ", path, "]"),
                image = rc$note,
                binary = read_binary_text(path, rc$abs, rc$size),
                read_text_body(rc))
  value = read_lines_of(rc, path)
  attr(value, "image_block") = NULL
  list(text = as_utf8(text), image = rc$image, details = details, value = value)
}

#' The value of `peter$read()`: the window's lines as a `gptr_lines` vector (contract section 5.10)
#' An image file gives its note line; its block travels in attribute `image_block` until the member
#' attaches it to the running `r` result.
#' @noRd
read_lines_value = function(path, offset = NULL, limit = NULL) {
  read_lines_of(read_core(path, offset, limit, budget_tokens = Inf), path)
}

#' The `gptr_lines` of a read_core() window (shared by peter$read() and the direct `read` value)
#' @noRd
read_lines_of = function(rc, path) {
  lines = switch(rc$kind,
                 empty = character(),
                 image = rc$note,
                 binary = read_binary_text(path, rc$abs, rc$size),
                 rc$lines)
  structure(as_utf8(lines), class = c("gptr_lines", "character"), path = rc$abs, offset = rc$start,
            limit = length(rc$lines), total = rc$total, truncated = isTRUE(rc$truncated),
            encoding = rc$encoding,
            notices = if (identical(rc$kind, "text")) read_notices(rc) else character(),
            image_block = rc$image)
}

#' Print the lines of `peter$read()` in Pi's read format within the member budget
#'
#' @param x A `gptr_lines` vector.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_lines = function(x, ...) {
  shown = budget_head(as.character(x), member_budget(), read_token_class(attr(x, "path") %||% ""))
  out = shown$lines
  if (shown$omitted > 0L) {
    out = c(out, paste0("[... ", shown$omitted,
                        " more lines not printed; index the value or use offset/limit]"))
  }
  notes = attr(x, "notices") %||% character()
  if (length(notes)) out = c(out, "", notes)
  ns_print_lines(out)
  invisible(x)
}
