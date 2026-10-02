# 21 — Rcpp hot paths: what (if anything) justifies compiled code in gptr v1

Track 21 research report. Date: 2026-09-29. Machine: Apple M2 (8 cores), 24 GB, macOS 26.6.2,
R 4.4.3 (`Rscript --vanilla`, locale `en_US.UTF-8`), Rcpp 1.1.1, Homebrew clang 23.1.1.
Answers decision **D-21** of `dev/spec/01-decision-register.md` against the bar in REQ-01.

**Status of the numbers.** An earlier researcher on this track left scripts and outputs in
`scratchpad/work/21/`. Every script kept was re-run for this report (folder `v2/`), and new scripts
were written and run for the missing work (`v3/`, `v4/`). The earlier outputs (`out*.txt`) are
cited only as a second sample, labelled "earlier run". **The machine was shared with other agents:
the 1-minute load average ranged from 8 to 153 during the runs** (logged at the start and end of
every output file). Absolute times are therefore inflated, by up to 2-3x in the worst windows.
Every figure is a **median of repeated runs** (n given). Speed-up ratios between implementations
measured in the same run were stable across runs and loads, and those ratios drive the verdicts.

## 1. Executive summary

**Decision for v1: no compiled code.** gptr v1 ships with no `src/` directory
(`NeedsCompilation: no`). None of the ten candidate hot paths meets the REQ-01 bar. REQ-01 itself
only says "performance absolutely matters" and R "is not good enough"; this report operationalises
that as: pure R (plus, in two places, an optional package) noticeably slower than a user would
accept (about 200 ms per typical operation or 1 s on a large workload) **and** Rcpp at least about
5x faster. (The 200 ms / 1 s / 5x thresholds are this report's, not REQ-01's wording.)
An independent verification pass (see "Verification log" at the end) re-ran the decisive
benchmarks and found better pure-R formulations for four candidates (grep, block search, globs,
SSE) that shrink the Rcpp advantage further; no verdict changed.
In most candidates, choosing a better algorithm in R closed the gap that a first look attributed
to the language. Section 3 specifies the integration completely, and it was verified end to end
with a test package (`R CMD check --as-cran`: OK apart from a sandbox time-server NOTE), so a
routine can be added later without redesign.

| # | Hot path | Typical operation: best pure R (optional pkg) | Rcpp | Rcpp speed-up | Runs per agent turn (estimate) | Time Rcpp would save per turn | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | Content search (grep) | 2.1k-file repo, 100-match limit: 40-211 ms; 10.6k files / 136 MB, limit 100: 252-805 ms | 37-124 ms; 248-667 ms | **1.0-1.7x** at the default limit; when every file matches and the limit is lifted, 3.6-4.0x with the report's tool but **2.4-2.5x** with the match-offset formulation found in verification (2.1); regex: no dependency-free C++ equivalent (C++ `std::regex` was 5-22x *slower* than R's PCRE) | 0-3 calls | per call: < 0.1 s (2k files), < 0.3 s (10k files) | **PURE R IS ENOUGH** (fs in Suggests speeds listing 3.5-4x) — watch #1 |
| 2 | Lines N..N+2000 of a 200 MB file | no index yet (page cache warm), near the end: 359-851 ms (grepRaw scan; two runs, load 10-34); with a cached sparse line index: 5-17 ms (index built once in 403-838 ms) | 117-185 ms | 3.1-4.6x without an index; pure R faster once indexed | rare (< 1 per session) | < 0.7 s, once per huge file | **PURE R IS ENOUGH** |
| 3 | Line diff for `edit` | 2,000 lines: 0.4-15 ms; 20,000 lines with 30% changed: 56-73 ms (patience + capped Myers) | 0.2-12.7 ms; 216-1,191 ms (plain Myers) | 1.2-13x only where pure R takes <= 15 ms; pure R 4-77x *faster* on big edits (algorithm, three runs) | 0-5 (one per edit) | < 25 ms | **PURE R IS ENOUGH** (do not use diffobj) |
| 4 | Whitespace-insensitive block search (edit fallback) | 50-line block in a 20,000-line file: 25.7-29.5 ms normalising every line; **1.6 ms** with a token prefilter (verification, 2.4) | 5.9-6.9 ms | 4.3-4.4x against the report's R; **0.27x (pure R 3.7x faster)** against the prefiltered R | only when the exact match fails | none | **PURE R IS ENOUGH** (stringi or utf8 in Suggests only for NFKC folding) |
| 5 | Glob + .gitignore over 100k paths | one glob: 9-92 ms with the report's translator, 10-58 ms with a literal prefilter (verification, 2.5); 44 rules: 247-252 ms (component dictionary) | 3-27 ms; 265-340 ms | 2-9x for globs with the report's translator, 1.6-3.3x with the prefilter; <= 1x for gitignore (but the Rcpp comparator does not use the dictionary) | 0-3 (file discovery) | < 35 ms on a real repo | **PURE R IS ENOUGH** |
| 6 | SSE splitting + delta accumulation | 35-58 µs per event incl. JSON parse with the report's splitter; 23-29 µs with the vectorised splitter found in verification (2.6) | 8-12 µs per event | 4.1-5.9x against the report's splitter (report and verification runs); **2.7-3.2x** against the vectorised one (1.2-1.5x with 16 KB network chunks) | every streamed event, spread over the stream | ~0.05-0.1 s of CPU per 2,000-event answer, not user-visible | **PURE R IS ENOUGH** — but not via `httr2::resp_stream_sse()` (192 µs/event) — watch #2 |
| 7 | Partial JSON of streamed tool arguments | 20 KB argument: 269-393 ms per call if repaired and parsed at every delta, 23-29 ms throttled to every 20th delta | 182-304 ms; 17-36 ms | 1.1-1.4x (0.6-1.7x throttled, two runs) | during tool-call streaming | ~0 | **PURE R IS ENOUGH** (incremental scanner + throttling) |
| 8 | Token estimation | chars/4 on 4 MB: 6 ms | Rust BPE (rtiktoken): 648 ms / 4 MB | n/a (accuracy question) | once per turn | n/a | **PURE R IS ENOUGH**: provider-reported usage + a content-aware heuristic. A BPE tokenizer in Rcpp is not justified |
| 9 | Object fingerprints between turns | `rlang::obj_address()` 0.86 µs; snapshot of 202 objects incl. 1.6 GB vector: 4.7 ms; full `rlang::hash()` of 1.6 GB: 70-89 ms | own `addr_cpp()`: 0.48 µs | irrelevant | once per R-tool call | 0 | **PURE R IS ENOUGH** (rlang, already a dependency of httr2) |
| 10 | Base64 of images; hashing | 1.2 MB PNG: 3.1-4.6 ms (base64enc / openssl); 200 MB file: `rlang::hash_file()` 26 ms | 7.2 ms (simple loop) | slower than existing C | 0-3 images; 0-5 hashes | 0 | **PURE R IS ENOUGH** using packages gptr already imports |

Findings that should shape the v1 design regardless of Rcpp (details in section 2):

* **Algorithms, not the language, were the lever.** Patience anchoring plus a cost cap took the
  pure-R diff of a 20,000-line file from 6.5 s to 56-73 ms, faster than both compiled plain-Myers
  implementations (Rcpp 0.2-1.2 s, diffobj 0.95-1.9 s across runs). A component dictionary took
  gitignore matching of 100k paths from 1.5-1.6 s to 250 ms, equal to or faster than a C++
  matcher that does *not* use the dictionary. A raw-byte prefilter (`grepRaw()`) took
  fixed-string grep at the default limit to within 1.0-1.7x of C++. In verification, a token
  prefilter made the whitespace-insensitive block search (1.6 ms) 3.7x *faster* than the Rcpp
  routine. Note that several comparisons pit a better R algorithm against a plainer C++ one
  (diff, gitignore, partial JSON); they show that pure R is fast enough, not that C++ could not
  be made faster.
* **`jsonlite::base64_enc()` inserts a newline every 72 characters.** Use
  `openssl::base64_encode()` (openssl arrives with httr2) or `base64enc::base64encode()`.
* **`httr2::resp_stream_sse()` costs about 0.19 ms per event** (0.29-0.46 ms at the
  verification's higher load), 3.5-5.5x more than reading `resp_stream_raw()` chunks with the
  report's 40-line pure-R splitter and 17x more than with the vectorised splitter found in
  verification (26 µs per event end to end over HTTP). Use raw chunks for streaming.
* **Never accumulate streamed text with `paste0()`**: 2.0-3.4 s for 20,000 deltas, against 7 ms
  for a list plus one `paste(collapse = "")`.
* **chars/4 underestimates printed R output by about 51% and CSV/JSON by 46-58%** (o200k_base).
  A 50 KB R-output tool result is about 26k tokens, not 13k, which is most of Pi's 16,384-token
  compaction reserve.
* **Address-based change detection is unsound on its own**: in-place modification keeps the
  address, and freed addresses were reused (16 of 20 trials). Use address plus sampled values
  plus static analysis of the evaluated code, and never keep references to user objects: holding
  one forced a 0.37 s, 1.6 GB copy on the next `x[2] <- 5`.

## 2. Benchmark details per candidate

### 2.0 Method

* **Corpus.** `corpus/rep1` is a copy of the Pi monorepo checkout (commit `1b347794`) without
  its `.git` directory: 2,125 files, 27.2 MB, about 420k lines of TypeScript plus the 186 KB
  `package-lock.json`. `corpus/` holds five such copies (10,625 files; 10,555 text files, 117 MB of
  text, 135.9 MB in all). `big200.txt` (200,002,953 bytes, 5,201,487 lines) is the corpus's
  `.ts`/`.tsx`/`.md`/`.mjs` files concatenated until 200 MB. Page cache warm in all runs.
* **Harness** (`helpers.R`; only the comment on `timeit_ns` added). `gc()` before every timed
  call, one warm-up call, median of n:

```r
timeit <- function(f, times = 5L, warmup = 1L) {
  for (i in seq_len(warmup)) f()
  el <- numeric(times)
  for (i in seq_len(times)) {
    gc(FALSE)
    t0 <- proc.time()[["elapsed"]]
    f()
    el[i] <- proc.time()[["elapsed"]] - t0
  }
  c(median_ms = stats::median(el) * 1000, min_ms = min(el) * 1000,
    max_ms = max(el) * 1000, n = times)
}
timeit_ns <- function(f, times = 5L, warmup = 1L) {   # same, with microbenchmark::get_nanotime()
  for (i in seq_len(warmup)) f()
  el <- numeric(times)
  for (i in seq_len(times)) {
    gc(FALSE)
    t0 <- microbenchmark::get_nanotime()
    f()
    el[i] <- (microbenchmark::get_nanotime() - t0) / 1e6
  }
  c(median_ms = stats::median(el), min_ms = min(el), max_ms = max(el), n = times)
}
compile_cpp <- function(file) {
  Rcpp::sourceCpp(file.path(W, file), cacheDir = CPPCACHE, env = globalenv(),
                  verbose = FALSE, showOutput = FALSE)
}
```

  `timeit()` (via `proc.time()`) resolves about 1 ms, so its single-digit millisecond results
  are indicative only; most sub-10 ms comparisons use `timeit_ns()`.
* **Correctness first.** Every comparison checks that all implementations return identical
  results (byte-identical text, identical positions) before timing, and each candidate has a
  randomised cross-check. The raw outputs print these checks.
* **Files.** All scripts and outputs:
  `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/21/`
  (`bench*.R`, `*.cpp`, `*_impl*.R`; outputs `v2/*.txt`, `v3/*.txt`, `v4/*.txt`; toy package `pkg/`).
  Runs: **v2** 18:39-19:27 (load 12-59), **v3** 19:27-19:53 (load 8-153), **v4** 19:53-19:56
  (load 7-11). Earlier-run outputs (`out*.txt`, 16:26-17:09) are used only for comparison.
* **"Runs per turn"** estimates come from Pi's tool design (grep limit 100 matches, one diff per
  edit, one stream per model call), not from usage telemetry.

### 2.1 Content search (grep) across a large tree

**Workload.** Search the 10,625-file corpus and one 2,123-file checkout (`rep1`) for a rare fixed
string (`registerTool`: 560 lines in 255 files), a common one (`import`: 50,305 lines in 8,875
files), an absent one, and two regexes (`function\s+\w+\(`: 28,190 lines; `TODO|FIXME`: 285),
reporting one hit per matching line (file, line number, text; trailing `\r` stripped), skipping
files with a NUL in the first 8,000 bytes (git's heuristic). "Limit 100" is Pi's default
(`DEFAULT_LIMIT = 100`, `grep.ts:41`).

**Implementations.**

* *R naive*: `readLines()` + `grep()` per file.
* *R optimised / tool* (`bench01b_grep_prod.R`): list, stat, batch of 512 files read with
  `readBin()`, NUL sniff, `rawToChar()`, then one vectorised whole-file `grepl()` prefilter
  (`fixed = TRUE, useBytes = TRUE`, or PCRE with `(?m)` for regexes), then `strsplit()` + `grep()`
  only on files that hit, with early exit at the limit.
* *R tool, raw prefilter* (`bench01d_rawprefilter.R`, new): for fixed strings, test the raw bytes
  with `grepRaw(fixed = TRUE)` before any conversion, so non-matching files never become R strings.
* *stringi + brio*: `brio::read_file()` + `stri_detect_fixed/regex`.
* *Rcpp* (`grep.cpp`): `fread` loop, NUL sniff, `std::boyer_moore_horspool_searcher`, line
  extraction, strings created with `Rf_mkCharLenCE(..., CE_UTF8)`; listing and stat stay in R.
  For regexes: `std::regex` (ECMAScript) per line.
* *Reference*: ripgrep 15.2.0 via `system2()`.

```r
# the pure-R tool with the raw-byte prefilter (fixed strings); regexes use the grep_tool_r() path
grep_tool_r_raw <- function(root, pattern, max_matches = 100L, max_size = 5e6) {
  files <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  sizes <- file.size(files)
  keep <- !is.na(sizes) & sizes > 0 & sizes <= max_size
  files <- files[keep]; sizes <- sizes[keep]
  pat_raw <- charToRaw(enc2utf8(pattern)); nul <- as.raw(0L)
  o_file <- list(); o_line <- list(); o_text <- list(); k <- 0L; total <- 0L
  for (i in seq_along(files)) {
    r <- readBin(files[i], "raw", n = sizes[i])
    if (!length(grepRaw(pat_raw, r, fixed = TRUE))) next                     # most files stop here, as raw
    if (length(grepRaw(nul, r[seq_len(min(8000L, length(r)))], fixed = TRUE))) next   # binary
    l <- strsplit(rawToChar(r), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
    ln <- grep(pattern, l, fixed = TRUE, useBytes = TRUE)
    if (!length(ln)) next
    if (max_matches > 0L && total + length(ln) > max_matches) ln <- ln[seq_len(max_matches - total)]
    k <- k + 1L; o_file[[k]] <- rep.int(i, length(ln)); o_line[[k]] <- ln
    o_text[[k]] <- sub("\r$", "", l[ln], useBytes = TRUE); total <- total + length(ln)
    if (max_matches > 0L && total >= max_matches) break
  }
  text <- as.character(unlist(o_text)); Encoding(text) <- "UTF-8"
  list(file = files[as.integer(unlist(o_file))], line = as.integer(unlist(o_line)), text = text)
}
```

```cpp
// grep.cpp, production-shaped variant (excerpt): read + sniff + BMH search + line extraction
List grep_fixed_cpp2(CharacterVector files, std::string pattern, int max_matches = -1, bool skip_binary = true) {
  std::vector<int> o_file, o_line; std::vector<std::string> o_text; std::string buf;
  if (pattern.empty()) Rcpp::stop("empty pattern");
  const std::boyer_moore_horspool_searcher<std::string::const_iterator> searcher(pattern.cbegin(), pattern.cend());
  R_xlen_t n = files.size(); bool done = false;
  for (R_xlen_t i = 0; i < n && !done; ++i) {
    if ((i & 255) == 0) Rcpp::checkUserInterrupt();
    if (!read_file(Rf_translateChar(files[i]), buf)) continue;
    if (skip_binary && std::memchr(buf.data(), 0, std::min<size_t>(buf.size(), 8000)) != nullptr) continue;
    std::string::const_iterator it = buf.cbegin(), last_counted = buf.cbegin(); int line_no = 1;
    while (true) {
      it = std::search(it, buf.cend(), searcher);
      if (it == buf.cend()) break;
      line_no += (int) std::count(last_counted, it, '\n'); last_counted = it;
      std::string::const_iterator ls = it, le = it;
      while (ls != buf.cbegin() && *(ls - 1) != '\n') --ls;
      while (le != buf.cend() && *le != '\n') ++le;
      std::string::const_iterator te = le; if (te != ls && *(te - 1) == '\r') --te;
      o_file.push_back((int) i + 1); o_line.push_back(line_no); o_text.emplace_back(ls, te);
      if (max_matches > 0 && (int) o_file.size() >= max_matches) { done = true; break; }
      if (le == buf.cend()) break;
      it = le;
    }
  }
  // ... convert to IntegerVector / CharacterVector with Rf_mkCharLenCE(..., CE_UTF8)
}
```

**Correctness.** In every configuration all implementations returned identical results
(files, line numbers, and bytes of every line), and ripgrep returned the same counts. Track 01
had already validated the pure-R tool against ripgrep line by line on the Pi tree.

**Results: the tool as the model would call it** (`v3/bench01d_rawprefilter.txt`, load 8-13, ms,
median of 5; listing and stat included in all three):

| Tree | Pattern | Limit | Lines returned | R tool (01b) | **R tool, raw prefilter** | Rcpp tool | best R / Rcpp |
|---|---|---|---|---|---|---|---|
| 10.6k files | registerTool | 100 | 100 | 613 | **362** | 305 | 1.19 |
| 10.6k files | import | 100 | 100 | 326 | **265** | 255 | 1.04 |
| 10.6k files | (absent) | 100 | 0 | 1,370 | **805** | 667 | 1.21 |
| 10.6k files | registerTool | none | 560 | 1,656 | **892** | 590 | 1.51 |
| 10.6k files | import | none | 50,305 | 2,224 | 2,156 | 592 | 3.64 |
| 10.6k files | (absent) | none | 0 | 1,604 | **1,262** | 683 | 1.85 |
| 2.1k files | registerTool | 100 | 100 | 220 | **119** | 80 | 1.49 |
| 2.1k files | import | 100 | 100 | 78 | **44** | 41 | 1.07 |
| 2.1k files | (absent) | 100 | 0 | 208 | 211 | 124 | 1.68 |
| 2.1k files | registerTool | none | 112 | 270 | **172** | 115 | 1.50 |
| 2.1k files | import | none | 10,061 | 506 | 511 | 137 | 3.73 |
| 2.1k files | (absent) | none | 0 | 277 | **156** | 121 | 1.29 |

(The two "(absent)" rows on 2.1k files do identical work; their 55 ms difference shows the
noise level at this load.)

Regex searches, pure-R tool only (`v2/bench01b_grep_prod.txt`, load 35-45; earlier run at lower
load in brackets): 10.6k files `function\s+\w+\(` limit 100: 395 ms [353]; unlimited (28,190
lines): 4,317 ms [2,403]; `TODO|FIXME` unlimited: 3,427 ms [1,474]. 2.1k files: 93 [76], 385 [340],
278 [213] ms. The dependency-free C++ alternative is far slower: `std::regex` per line took
23,580 and 23,240 ms for the two regexes on 10.5k files, against 2,169 and 1,073 ms for the
optimised pure-R path in the same run (`v2/bench01_grep.txt`). A faithful compiled regex would
need PCRE2 as a system library, which REQ-01 excludes. ripgrep in the same run: 191-462 ms.
Verification (`verify-21/out/v_regex_rep1.txt`, 2.1k files, load 22-35, so about 3-4x slower in
absolute terms than the bracketed figures): identical line sets from both; pure-R tool 1,714 and
627 ms against 8,051 and 12,040 ms for `std::regex`, i.e. 4.7x and 19x slower in C++; so the
range is 5-22x rather than 11-22x, and the conclusion stands. Note that unlimited searches of the
10.6k-file tree (regex 2.4-4.3 s; fixed `import`, 50k lines, 1.3-2.5 s) are the measured grep
operations above the 1 s bar; the regex case is not an Rcpp candidate because REQ-01(c) rules out
the only faithful compiled engine, and the fixed case is 2.5x from Rcpp with the match-offset
extraction below, short of the 5x bar.

**Cost split of the pure-R tool** (`v3/bench01c_split.txt`, load 11-12, each stage timed alone,
ms, median of 5; unlimited search):

| Stage | 10.6k files, registerTool | 10.6k files, import | 2.1k files, registerTool | 2.1k files, import |
|---|---|---|---|---|
| 1 `list.files(recursive = TRUE)` | 263 | 299 | 39 | 37 |
| 1' `fs::dir_ls(recurse = TRUE)` (alternative) | 68 | 74 | 13 | 12 |
| 2 `file.size()` | 29 | 29 | 5 | 6 |
| 3 `readBin()` every file | 551 | 544 | 92 | 81 |
| 4 NUL sniff + `rawToChar()` | 555 | 467 | 98 | 98 |
| 5 whole-file `grepl()` prefilter | 114 | 17 | 22 | 3 |
| 6 `strsplit()` + per-line `grep()` on hit files | 41 (255 files) | 948 (8,875 files) | 9 | 168 |
| **pure R, stages 1-6 (sum of rows 1-6, without 1')** | **1,553** | **2,304** | **265** | **393** |
| C++ stages 3-6 combined (`grep_fixed_cpp2`) | 373 | 488 | 62 | 91 |
| **Rcpp tool (sum: stages 1-2 in R + C++ row)** | **665** | **816** | **106** | **134** |

Reading, sniffing and converting (stages 3-4) are 44-72% of the pure-R cost; the whole-file
match (stage 5) is small, and splitting hit files (stage 6) matters only when most files hit. The raw prefilter removes most of stage 4 for fixed strings; `fs::dir_ls()`
cuts stage 1 by 3.5-4x. Micro-benchmarks from `v2/bench01_grep.txt` (load 27-45) confirm that
reading dominates: reading 10,555 files took 4,385 ms with `readLines()`, 1,196 ms with `readBin()`,
4,414 ms with `brio::read_file()`, 7,176 ms with `stringi::stri_read_raw()` and 810 ms in a C++
`fread` loop; in-memory matching of the 2.6M lines took 361 ms (`grepl(fixed, useBytes)`),
2,113 ms without `useBytes`, 558 ms for PCRE and 10,320 ms for the default TRE engine. Hence:
always `useBytes = TRUE`, always `perl = TRUE`, never `readLines()` per file, never TRE.

**Frequency and saving.** 0-3 grep calls per turn in code-heavy work (fewer in data analysis,
where the R tool dominates). At the default limit on a 2.1k-file repository, Rcpp saves 3-87 ms
per call; on a 10.6k-file tree 10-140 ms (300 ms for an unlimited rare-pattern scan). That is
at most a few tenths of a second per turn, against model latencies of several seconds per turn.

**Verification: a faster pure-R formulation for the "every file matches" case**
(`verify-21/v_grep_fast.R`, `verify-21/out/v_grep_fast.txt`, load 6-16, median of 5). The
remaining 3.6x gap came from `rawToChar()` + `strsplit()` of every hit file into lines (stage 6).
`grep_tool_r_pos()` keeps each hit file as raw bytes, finds match offsets with
`grepRaw(fixed = TRUE, all = TRUE)` and newline offsets the same way, maps matches to line numbers
with `findInterval()`, gathers only the matching lines' bytes with `sequence()`, and converts all
of them with one `rawToChar()` + `strsplit()` at the end:

```r
mp  <- grepRaw(pat_raw, r, fixed = TRUE, all = TRUE)            # match offsets
nlp <- grepRaw(nl, r, fixed = TRUE, all = TRUE)                 # newline offsets
ln  <- unique(findInterval(mp - 1L, nlp)) + 1L                  # line of each match
s <- c(0L, nlp)[ln] + 1L; e <- ifelse(ln <= length(nlp), nlp[ln] - 1L, n)   # line bounds (then strip \r)
idx <- sequence(e - s + 2L, s); idx[cumsum(e - s + 2L)] <- n + 1L           # line bytes + "\n"
bytes[[k]] <- c(r, nl)[idx]                                     # one rawToChar()/strsplit() at the end
```

Output was identical (files, line numbers, bytes of every line) to the report's tool and to Rcpp
in all twelve configurations and on an edge-case tree (CRLF, no final newline, match at the first
and last byte, a binary file, limits 1-3).

| Tree, pattern, limit | report's best R | **R, match offsets** | Rcpp | best R / Rcpp |
|---|---|---|---|---|
| 10.6k files, `import`, none (50,305 lines) | 2,143 | **1,345** | 533 | 2.5 (was 4.0) |
| 2.1k files, `import`, none (10,061 lines) | 359 | **250** | 102 | 2.5 (was 3.5) |
| 10.6k files, `registerTool`, none | 715 | **684** | 478 | 1.4 |
| 10.6k files, any pattern, limit 100 | 253-764 | 252-766 | 248-561 | 1.0-1.4 |
| 2.1k files, any pattern, limit 100 | 42-113 | 40-112 | 37-82 | 1.1-1.4 |

The same run also showed that reading is not where C++ wins: `readBin()` of all 2,125 files took
70 ms against 89 ms for the C++ `fread` loop. The re-run of the report's own script
(`verify-21/out/orig_bench01d_rawprefilter.txt`, load 9-22) reproduced the table above within
noise (for example 10.6k files, limit 100: 399 / 251 / 738 ms for the raw-prefilter tool, Rcpp
348 / 242 / 542 ms; unlimited `import`: 2,519 against 641 ms).

**Verdict: PURE R IS ENOUGH.** Implement grep as `grep_tool_r_raw()` for fixed strings, with the
match-offset line extraction above for files that hit, and the whole-file PCRE prefilter for
regexes, with the limit's early exit; use `fs::dir_ls()` for listing when fs is installed
(Suggests; sort the result so both paths give identical output). This is **watch candidate #1**:
the only measured case above 2x is "every file matches and every match is wanted" (2.5x with the
match-offset extraction), which the 100-match limit prevents. Windows file I/O was not measured (6).

### 2.2 Offset/limit reads of a 200 MB text file

**Workload.** Return lines N..N+1999 of `big200.txt` (200 MB, 5,201,487 lines) for N = 1,000,
2,600,000 and 5,199,488 (the last 2,000 lines), byte-identical to `readLines()`, CR stripped,
without materialising the whole file.

**Implementations** (`bench02_readlines.R`, `bench02c_readlines_best.R`, `readlines.cpp`):
B text connection, discarding in 50k-line chunks; C `scan(skip =, nlines =)`; D binary chunks with
`sum(r == nl)`; **D2 binary 1 MB chunks with newline positions from `grepRaw(fixed = TRUE, all =
TRUE)`** (new); **J a sparse line index** (byte offset of every 10,000th line, built in one pass
and cached by path, size and mtime) plus `seek()`; E `data.table::fread(skip =, nrows =)`;
F `vroom::vroom_lines()`; G `readr::read_lines()`; I Rcpp `fread` 1 MB + `memchr`.

```r
rl_raw2 <- function(path, from, n, chunk = 1048576L) {           # D2
  con <- file(path, "rb"); on.exit(close(con))
  line <- 1; tail <- raw()
  if (from > 1) repeat {
    r <- readBin(con, "raw", n = chunk)
    if (!length(r)) return(character())
    p <- grepRaw(nl, r, fixed = TRUE, all = TRUE)
    k <- length(p)
    if (line + k >= from) { pos <- p[from - line]; tail <- if (pos < length(r)) r[(pos + 1L):length(r)] else raw(); break }
    line <- line + k
  }
  pieces <- list(tail); np <- 1L; have <- length(grepRaw(nl, tail, fixed = TRUE, all = TRUE)); eof <- FALSE
  while (have < n) {
    r <- readBin(con, "raw", n = 262144L)
    if (!length(r)) { eof <- TRUE; break }
    np <- np + 1L; pieces[[np]] <- r; have <- have + length(grepRaw(nl, r, fixed = TRUE, all = TRUE))
  }
  r <- if (np == 1L) pieces[[1L]] else do.call(c, pieces)
  if (!length(r)) return(character())
  if (!eof || have >= n) { e <- grepRaw(nl, r, fixed = TRUE, all = TRUE)[n]; r <- r[seq_len(e - 1L)] }
  else if (r[length(r)] == nl) r <- r[-length(r)]
  x <- strsplit(rawToChar(r), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  if (length(r) && r[length(r)] == nl) x <- c(x, "")
  x <- sub("\r$", "", x, useBytes = TRUE); Encoding(x) <- "UTF-8"
  x
}
build_index_r2 <- function(path, every = 10000L, chunk = 4194304L) {   # J, one pass
  con <- file(path, "rb"); on.exit(close(con))
  offs <- list(0); k <- 1L; line <- 1; base <- 0
  repeat {
    r <- readBin(con, "raw", n = chunk)
    if (!length(r)) break
    p <- grepRaw(nl, r, fixed = TRUE, all = TRUE)
    if (length(p)) {
      want <- which((line + seq_along(p)) %% every == 1L)
      if (length(want)) { k <- k + 1L; offs[[k]] <- base + p[want] }
      line <- line + length(p)
    }
    base <- base + length(r)
  }
  list(every = every, offsets = unlist(offs), lines = line - 1)
}
# rl_indexed(): seek() to offsets[(from - 1) %/% every + 1], read 256 KB blocks until skip + n lines, split.
```

**Correctness.** All eight methods were byte-identical to `readLines()` at all three positions;
D2 was identical to Rcpp at those positions plus N = 1, 2 and 40,000, and on a four-line file with
CRLF and an empty line for every start position. The two index builders gave identical indexes.

**Results** (ms, median of 5):

| Method | near start | middle | near end | run |
|---|---|---|---|---|
| D pure R `r == nl` | 48 | 270 | 765 | v3/02c, load 10-17 |
| **D2 pure R `grepRaw()`** | **11** | **172** | **359** | v3/02c |
| **J pure R, sparse index already built** | **5.0** | **7.4** | **5.8** | v3/02c |
| I Rcpp `fread` + `memchr` | 0.77 | 66.8 | 117 | v3/02c |
| index build over 200 MB: `grepRaw()` / `r == nl` / Rcpp line count | 403 / 689 / 113 (whole file) | | | v3/02c |
| B text connection | 3 | 1,340 | 2,546 | v2/02, load 35-40 |
| C `scan()` | 3 | 1,055 | 1,470 | v2/02 |
| E `data.table::fread()` | 3 | 144 | 233 | v2/02 |
| F `vroom::vroom_lines()` | 1 | 124 | 206 | v2/02 |
| G `readr::read_lines()` | 3 | 130 | 236 | v2/02 |
| whole-file `readLines()` then subset | 2,716 | 2,716 | 2,716 | v2/02 |

Counting newlines in one 4 MB raw chunk (`v2/bench02b_count.txt`, median of 11):
`grepRaw(all = TRUE)` 6.6 ms, `which(r == nl)` 10.7, `sum(r == nl)` 11.1,
`stri_count_fixed(rawToChar(r), "\n")` 17.1, `tabulate()` 23.5, `strsplit()` 51.3,
`gregexpr(fixed = TRUE, useBytes = TRUE)` 6,742 ms (pathological; never use it for this).

**Reading.** A far read without an index (page cache warm; cold-cache I/O was not measured)
costs 359 ms in the best pure R against 117 ms in Rcpp (3.1x, below the 5x bar). The
verification re-run of `bench02c_readlines_best.R` (`verify-21/out/orig_bench02c_readlines_best.txt`,
load 15-34, so about 2x slower in absolute terms) gave 851 against 185 ms near the end (**4.6x**;
4.3x on the minima), 414 against 131 ms in the middle (3.2x), and 838 against 213 ms for the
whole-file pass (3.9x); all methods again byte-identical. So this ratio sits at 3-4.6x, closer to
the bar than the first run suggested; the verdict rests on rarity and on the index, not on the
ratio. The sparse index makes every later read 5-17 ms, faster than Rcpp without an index,
and its one-time build (403-838 ms) can be the same pass as the first far read. No faster
base-R newline counter was found: `grepRaw(all = TRUE)` (about 600 MB/s at low load) is the
fastest of the seven counters below and of three more tried in verification
(`verify-21/out/v_nlcount.txt`, 4 MiB chunk: `grepRaw` 10.5 ms, `sum(r == nl)` 17.3,
`nchar()` minus `nchar(gsub(fixed, useBytes))` 29.2, `length(r[r != nl])` 31.4 ms). data.table and vroom
reach 206-233 ms, but they are parsers with their own rules (quotes, blank lines, NULs) and are
not needed.

**Frequency and saving.** Rare: most files an agent reads are small, the first read of any file
starts near line 1 (11 ms for lines 1,000-2,999 here), and R users open big data files with R code, not the read tool.
Saving: 0.25-0.7 s (depending on load), once per huge file.

**Verdict: PURE R IS ENOUGH.** Use D2 for the scan and cache a sparse index keyed by
(path, size, mtime) once a file is larger than, for example, 20 MB.

### 2.3 Line-based diff for the edit tool

**Workload.** Lines 1..n of `big200.txt` (TypeScript and Markdown) for n = 200, 2,000 and 20,000, edited three
ways: *small* (5 lines modified, 3 inserted, 4 deleted: D = 17), *large* (30% of lines modified,
5% deleted, 5% inserted, scattered), and *rewrite* (a completely different block of the same
length: the worst case). The output is a pair of logical vectors (`del`, `ins`) marking removed
and added lines; validity means `identical(a[!del], b[!ins])`.

**Implementations** (`diff_impl.R`, `diff.cpp`): all intern lines to integer ids first
(`u <- unique(c(a, b)); match(a, u); match(b, u)`) and trim the common prefix and suffix.

* pure R scalar Myers O(ND) with trace (the textbook algorithm);
* pure R Myers vectorised over diagonals (one vector operation per edit distance d);
* pure R **patience**: lines unique in both files become anchors, the longest increasing
  subsequence (O(n log n)) of anchors is kept, gaps are trimmed vectorised, pure insertions,
  deletions and 1:1 replacements are handled vectorised, and only the remaining gaps go to
  vectorised Myers;
* pure R **patience + cap**: as above, but a gap whose edit distance exceeds 256 is reported as
  "replace the whole gap" (a valid but non-minimal diff; bounds the pathological case);
* `diffobj::ses_dat()` and `diffobj::ses()` (C, Myers);
* Rcpp linear-space Myers (middle snake, divide and conquer, no trace), interning in R.

The core of the capped patience algorithm (see `diff_impl.R` for the whole file):

```r
patience_core <- function(ia, ib, gap_core = myers_core_vec) {
  n <- length(ia); m <- length(ib)
  del <- logical(n); ins <- logical(m)
  if (n == 0L) { ins[] <- TRUE; return(list(del = del, ins = ins)) }
  if (m == 0L) { del[] <- TRUE; return(list(del = del, ins = ins)) }
  nid <- max(ia, ib)
  ca <- tabulate(ia, nid); cb <- tabulate(ib, nid)
  uniq <- which(ca == 1L & cb == 1L)                 # lines unique in both files = anchors
  pa <- match(uniq, ia); pb <- match(uniq, ib)
  o <- order(pa); pa <- pa[o]; pb <- pb[o]
  keep <- lis_idx(pb)                                  # longest increasing subsequence
  pa <- pa[keep]; pb <- pb[keep]
  if (!length(pa)) return(gap_core(ia, ib))
  sa <- c(1L, pa + 1L); ea <- c(pa - 1L, n); sb <- c(1L, pb + 1L); eb <- c(pb - 1L, m)
  # ... vectorised trimming of equal lines at both ends of every gap ...
  la <- ea - sa + 1L; lb <- eb - sb + 1L
  g <- which(la > 0L & lb == 0L); if (length(g)) del[sequence(la[g], sa[g])] <- TRUE
  g <- which(lb > 0L & la == 0L); if (length(g)) ins[sequence(lb[g], sb[g])] <- TRUE
  g <- which(la == 1L & lb == 1L); if (length(g)) { del[sa[g]] <- TRUE; ins[sb[g]] <- TRUE }
  for (j in which(la > 0L & lb > 0L & !(la == 1L & lb == 1L))) {
    ra <- sa[j]:ea[j]; rb <- sb[j]:eb[j]
    r <- gap_core(ia[ra], ib[rb]); del[ra] <- r$del; ins[rb] <- r$ins
  }
  list(del = del, ins = ins)
}
capped_gap <- function(max_d) function(ia, ib) {
  r <- myers_core_vec(ia, ib, max_d = max_d)
  if (is.null(r)) list(del = rep(TRUE, length(ia)), ins = rep(TRUE, length(ib))) else r
}
diff_r_patience_capped <- wrap_core(function(ia, ib) patience_core(ia, ib, gap_core = capped_gap(256L)))
```

**Correctness.** Property test: 3,000 random pairs (alphabets of 2-8 symbols, lengths 0-40,
half derived from `a` by 1-4 edits): **0 failures**. Every implementation produced a valid
diff; scalar, vectorised, Rcpp and diffobj agreed on the optimal edit distance; patience and
capped were never better than optimal. On every benchmark case all implementations were valid.

**Results** (v2 run, milliseconds, median of 5; 3 for n = 20,000 large and rewrite):

| n | kind | D (optimal) | scalar R | vectorised R | patience R | patience + cap R (D found) | diffobj::ses_dat | Rcpp Myers |
|---|---|---|---|---|---|---|---|---|
| 200 | small | 17 | 0.19 | 0.27 | 0.23 | 0.23 (17) | 0.77 | 0.058 |
| 200 | large | 128 | 4.28 | 2.08 | 0.75 | 0.75 (128) | 0.86 | 0.10 |
| 200 | rewrite | 304 | 14.5 | 4.18 | 4.24 | 2.91 (400) | 1.33 | 0.22 |
| 2,000 | small | 17 | 0.47 | 1.18 | 0.63 | 0.71 (17) | 1.43 | 0.21 |
| 2,000 | large | 1,342 | 308 | 71.3 | 7.02 | 6.34 (1,342) | 14.7 | 3.61 |
| 2,000 | rewrite | 2,752 | 1,240 | 246 | 124 | **15.2** (3,978) | 67.2 | 12.7 |
| 20,000 | small | 17 | 4.39 | 11.5 | 4.88 | 5.41 (17) | 5.48 | 1.98 |
| 20,000 | large | 13,368 | 31,800 (1 run) | 6,468 | 71.7 | **73.3** (13,368) | 1,875 | 1,191 |
| 20,000 | rewrite | 33,514 | not run | not run | 14,500 | **65.0** (39,882) | 15,830 | 2,288 |

The earlier run of the same script (lower load) gave the same ordering: for example 20,000
large: patience + cap 54 ms, Rcpp 216 ms, diffobj 954 ms; 20,000 rewrite: capped 28 ms, Rcpp
1,343 ms, diffobj 6,549 ms. The verification re-run (`verify-21/v_diff.R`, load 9-27; 1,000 new
random cases, 0 failures) gave: 2,000 lines small / large / rewrite: capped 0.41 / 4.5 / 8.9 ms,
Rcpp 0.16 / 2.4 / 9.9 ms, diffobj 0.72 / 9.3 / 36 ms; 20,000 small: 4.0 against 1.7 ms;
20,000 large: capped 55.7 ms (D = 13,368, optimal), Rcpp 321 ms, diffobj 1,331 ms; 20,000
rewrite: capped 46.8 ms (D = 39,882), Rcpp 3,620 ms, diffobj 8,606 ms. The Rcpp time for
the large 20,000-line case thus ranged 216-1,191 ms over three runs, so the "pure R faster"
factor on big edits is 4-16x (large) and 35-77x (rewrite), not a fixed 16-35x.

**Reading.** The algorithm matters far more than the language. Once patience anchoring is
used, pure R is at or below 7 ms for every file up to 2,000 lines and 73 ms for a 20,000-line
file with 30% of its lines changed, where the compiled plain-Myers routines (Rcpp and diffobj)
take 0.2-1.9 s across runs because Myers is O(ND). (A compiled *patience* diff would of course
beat both; it was not written, because the pure-R version is already far below the bar.) The one pathological case, a total rewrite, costs 14.5 s
in uncapped patience; the cap bounds it at 65 ms at the price of a diff 19% longer than
minimal, which is irrelevant for display. The Rcpp routine is faster only where pure R already
takes at most 15 ms (1.2-3.4x at 2,000 lines; up to 13x on 200-line files, where pure R takes
0.2-2.9 ms).

**Frequency and saving.** One diff per `edit` call (Pi's edit tool returns a unified diff),
roughly 0-5 edits per turn, on files that are almost always under 2,000 lines: at most about
7 ms per diff in pure R, so the saving from Rcpp is under 5 ms per edit and under 25 ms per turn.

**Verdict: PURE R IS ENOUGH.** Ship patience + capped vectorised Myers. Do not use diffobj (slower,
and one more Import). An Rcpp port would only make sense if uncapped minimal diffs of huge
rewrites were required, which they are not.

### 2.4 Fuzzy / normalised block matching (edit-tool fallback)

**Workload.** A 20,000-line, 1.18 MB file. The model's copy of a 50-line block starting at line
15,000 differs from the file in whitespace only: tabs replaced by two spaces, two extra leading
spaces, random trailing blanks, `" = "` written as `"  =  "`. The exact text is not present.
Task: find every start line where the whitespace-normalised block matches. Second task: Pi's
own fallback (strip trailing whitespace per line, fold smart quotes, dashes and exotic spaces,
optionally NFKC) followed by a fixed-string search of the whole text.

**Implementations** (`bench04_fuzzy.R`, `fuzzy.cpp`):

```r
norm_base <- function(x) gsub("[ \t]+", " ", gsub("^[ \t\r]+|[ \t\r]+$", "", x, perl = TRUE), perl = TRUE)
norm_stri <- function(x) stri_replace_all_regex(stri_trim_both(x, "[^\\u0020\\t\\r]"), "[ \\t]+", " ")
find_block <- function(lines, block, norm) {
  nf <- norm(lines); nb <- norm(block)
  k <- length(nb); n <- length(nf)
  if (k == 0L || n < k) return(integer())
  cand <- which(nf[seq_len(n - k + 1L)] == nb[1L])
  for (j in seq_len(k)[-1L]) { if (!length(cand)) break; cand <- cand[nf[cand + j - 1L] == nb[j]] }
  cand
}
```

The Rcpp version normalises each line into a `std::string` and compares (`find_block_ws_cpp`).
All five implementations returned exactly `15000`, and `norm_base()`, `norm_stri()` and
`norm_ws_cpp()` produced identical vectors for all 20,000 lines.

**Results** (v2 run, ms, median of 11):

| Implementation | median | min-max |
|---|---|---|
| base R, 2x `gsub(perl = TRUE)` + vectorised block compare | 33.8 | 32.0-62.2 |
| base R, same with `useBytes = TRUE` | 29.5 | 28.2-33.3 |
| base R, `trimws()` + TRE `gsub` | 64.7 | 61.7-183.5 |
| stringi `stri_trim_both` + `stri_replace_all_regex` | 34.3 | 31.5-44.3 |
| Rcpp normalise + compare | 6.9 | 6.5-8.2 |
| exact `regexpr(fixed = TRUE)` on the whole text (for scale) | 3.1 | 2.6-3.4 |
| Pi-style fold + find, base R (no NFKC) | 45.3 | 40.4-65.4 |
| Pi-style fold + find, stringi, no NFKC | 84.7 | 75.4-112.7 |
| Pi-style fold + find, stringi with `stri_trans_nfkc()` | 89.3 | 79.0-106.6 |
| `stri_trans_nfkc()` alone on the 1.2 MB text | 9.6 | 8.7-12.6 |
| `agrepl(max.distance = 0.1)`, one line vs 20,000 lines | 923 | 843-1,624 |
| `utils::adist()`, one line vs 20,000 lines | 847 | 546-1,013 |

**Reading.** Rcpp is 4.3x faster than the base-R versions in this table (but 3.7x *slower* than
the prefiltered base-R version in the verification below), and the base-R version already
takes 30 ms on a 20,000-line file, far below anything a user notices, and the fallback runs only
when the exact match fails. Two useful side results: (1) base R has no Unicode NFKC; Pi applies
NFKC in its fallback, and the only measured options are `stringi::stri_trans_nfkc()` (9.6 ms
here) or `utf8::utf8_normalize(map_compat = TRUE)` (identical output on the three test strings
checked: full-width letters, combining accent, `fi` ligature). (2) Edit-distance matching with
`agrepl()`/`adist()` over all lines costs close to a second; if an approximate fallback is ever
added, it must be restricted to candidate windows first.

**Verification: the 4.3x came from a slow R formulation** (`verify-21/v_fuzzy_fast.R`,
`verify-21/out/v_fuzzy_fast.txt`, load 15-17, median of 11). `find_block()` normalises all 20,000
lines although only windows that can match matter. Normalisation only trims and collapses blanks,
so every maximal non-blank token of a normalised block line must occur verbatim in the file line.
`find_block_tok()` takes the longest such token in the block, finds candidate lines with one
`grepl(fixed = TRUE, useBytes = TRUE)`, and normalises and compares only the candidate windows:

```r
find_block_tok <- function(lines, block, norm = norm_base_bytes) {
  nb <- norm(block); k <- length(nb); n <- length(lines)
  if (k == 0L || n < k) return(integer())
  tok <- strsplit(nb, " ", fixed = TRUE)
  best <- vapply(tok, function(t) if (length(t)) t[which.max(nchar(t, "bytes"))] else "", "")
  j <- which.max(nchar(best, "bytes"))
  if (!nzchar(best[j])) return(find_block(lines, block, norm))          # all-blank block: full scan
  cand <- which(grepl(best[j], lines, fixed = TRUE, useBytes = TRUE)) - j + 1L
  cand <- cand[cand >= 1L & cand <= n - k + 1L]
  if (!length(cand)) return(integer())
  win <- unique(as.vector(outer(0:(k - 1L), cand, `+`)))
  nf <- character(n); nf[win] <- norm(lines[win])
  for (jj in seq_len(k)) { if (!length(cand)) break; cand <- cand[nf[cand + jj - 1L] == nb[jj]] }
  cand
}
```

It returned `15000` like the others and agreed with `find_block()` and the Rcpp routine on 300
random blocks (repeated blocks, tabs, CR, all-blank blocks): 0 mismatches. Times: report's
`find_block()` 26.8 ms, with `useBytes` 25.7 ms, **token prefilter 1.6 ms**, Rcpp 5.9 ms. Even a
block whose longest token is `});` (243 candidate lines) took 1.8 ms against Rcpp's 5.5 ms. Only an
all-blank block falls back to the full scan (about 26 ms).

**Frequency and saving.** Only on edits whose exact `oldText` is not found (a minority of
edits), about 2 ms each in pure R with the prefilter (30 ms without): nothing to save with Rcpp.

**Verdict: PURE R IS ENOUGH** (and faster than the measured Rcpp routine once the token
prefilter is used), with **stringi (or utf8) in Suggests** only for NFKC folding (a correctness
feature, not a speed one); without it, skip the NFKC step.

### 2.5 Glob matching of 100k paths and .gitignore rules

**Workload.** 100,000 relative paths (the 2,125 paths of one Pi checkout replicated under 48
prefixes, with `node_modules/`, `dist/` and `.log` entries sprinkled in, half of the prefixes
stripped so anchored rules hit; padded to exactly 100,000; median 59 characters). Six globs
with `**`, `*`, `{a,b}`; and a 44-rule gitignore set (Pi's own `.gitignore` plus six extra
rules: 13 anchored, 22 directory-only, 2 negations, 29 without metacharacters).

**Implementations** (`glob_impl.R`, `glob.cpp`): a pure-R glob-to-PCRE translator
(`**/` becomes `(?:.*/)?`, `*` becomes `[^/]*`, brace expansion first) then
`grepl(perl = TRUE, useBytes = TRUE)`; the same regex through `stringi::stri_detect_regex()`; a
recursive C++ wildmatch (`glob_match_cpp`, `gitignore_cpp`). For gitignore: one `grepl()` per rule
(last matching rule wins), rules merged into alternations, a literal-rule fast path, and the
**component dictionary** algorithm: un-anchored rules can only match a single path component,
100,000 paths contain only 46,123 distinct component names, so those rules are evaluated on the
distinct names and mapped back with `match()`; only the 13 anchored rules run on full paths.

```r
gitignore_r_dict <- function(paths, rules) {
  n <- length(paths); last <- integer(n)          # index of the last matching rule, 0 = none
  un <- which(!rules$anchored)
  if (length(un)) {
    comps <- strsplit(paths, "/", fixed = TRUE)
    len <- lengths(comps); flat <- unlist(comps, use.names = FALSE)
    is_last <- sequence(len) == rep.int(len, len); owner <- rep.int(seq_len(n), len)
    u <- unique(flat); id <- match(flat, u)
    last_dir <- integer(length(u)); last_file <- integer(length(u))
    for (r in un) {
      m <- grepl(paste0("^(?:", rules$body[r], ")$"), u, perl = TRUE, useBytes = TRUE)
      last_dir[m] <- r
      if (!rules$dir_only[r]) last_file[m] <- r
    }
    v <- last_dir[id]; v[is_last] <- last_file[id[is_last]]
    nz <- which(v > 0L)
    if (length(nz)) {
      ow <- owner[nz]; vv <- v[nz]; o <- order(ow, vv); ow <- ow[o]; vv <- vv[o]
      keep <- !duplicated(ow, fromLast = TRUE); last[ow[keep]] <- vv[keep]
    }
  }
  for (r in which(rules$anchored)) { m <- grepl(rules$rx[r], paths, perl = TRUE, useBytes = TRUE); last[m] <- pmax(last[m], r) }
  out <- logical(n); h <- which(last > 0L); out[h] <- !rules$negate[last[h]]; out
}
```

**Correctness.** For every glob, base R, stringi and Rcpp gave identical logical vectors. For
the 44-rule set all five gitignore implementations agreed (19,702 ignored), and a property test
of 200 random rule sets x 5,000 paths found **0 mismatches** between per-rule R, dictionary R
and Rcpp.

**Results** (v2 run, ms; globs median of 11, gitignore median of 7):

| Glob over 100,000 paths | hits | base `grepl(perl, useBytes)` | stringi | Rcpp wildmatch |
|---|---|---|---|---|
| `**/*.ts` | 88,917 | 60.4 | 81.8 | 27.4 |
| `packages/**/src/**/*.{ts,tsx}` | 2,366 | 19.5 | 39.1 | 7.2 |
| `**/test/**/*.test.ts` | 17,527 | 92.2 | 101.6 | 10.4 |
| `**/node_modules/**` | 15,373 | 78.0 | 118.3 | 9.3 |
| `*.md` | 5 | 25.2 | 40.7 | 6.1 |
| `packages/*/README.md` | 13 | 8.9 | 29.9 | 3.0 |
| `endsWith(paths, ".ts")` fast path for `**/*.ext` | | 3.6 | | |

| .gitignore, 44 rules | 100,000 paths | 2,125 paths (one real checkout) |
|---|---|---|
| base R, one `grepl()` per rule | 1,579 (05b run); 2,417 (05 run) | 82.1 |
| base R, literal fast path + regex for the rest | 1,558 | 50.1 |
| base R, rules merged into alternations | 6,091 | |
| stringi, one `stri_detect_regex()` per rule | 7,379 | |
| **base R, component dictionary** | **247** (v2 05b run; `strsplit` 30 of it); **252** (v4 run, load 7-11) | |
| Rcpp wildmatch, last rule wins | 265 (v2 05b run); 340 (v4 run); 1,770 (v2 05 run, min 660) | 15.1 |

File discovery on the 10,625-file corpus: `list.files(recursive = TRUE)` + gitignore filter
551 ms; a pruned directory walk with one `list.files()` per directory 1,439 ms (the corpus has
no large ignored directory, so pruning cannot pay off here); `fs::dir_ls()` + `fs::path_rel()` +
filter 3,581 ms (dominated by `path_rel`).

**Reading.** Single globs: Rcpp is 2-9x faster, but the pure-R cost is 9-92 ms for 100,000
paths, and a real project has a few thousand paths (about 1-2 ms at the same rate). Gitignore: the naive pure-R method
takes 1.6-2.4 s on 100,000 paths, but the dictionary algorithm brings it to 247 ms, the same
as the Rcpp wildmatch (265 ms measured in the same run). Once again the algorithm, not the
language, is what matters. **Caveat (verification):** the Rcpp wildmatch runs every rule on every
path; it does not use the dictionary, so "dictionary R = Rcpp" compares algorithms. A cost split
of the dictionary evaluator (`verify-21/v_gitignore_split.R`, load 18-23, median of 7) shows
where its time goes: whole evaluator 477 ms; `strsplit` + `unique` + `match` 81 ms; the 31
un-anchored rules on the 46,123 distinct names 94 ms with `grepl()` against 63 ms with the C++
wildmatch (identical verdicts); the 13 anchored rules on the 100k full paths 288 ms; Rcpp
wildmatch over everything 585 ms. So a compiled matcher inside the same algorithm would save
little on the un-anchored part; the anchored rules are the remaining cost (a fixed-prefix filter
such as `startsWith(paths, "packages/")` before the regex is the obvious next pure-R step, not
measured). The re-run of `bench05b_gitignore.R` at load 9-22 again found the dictionary on a par
with Rcpp (880 against 831 ms, 0 mismatches in the 200-rule-set property test).

**Verification: faster single globs in pure R** (`verify-21/v_glob_fast.R`; two runs, load 6-38,
median of 11; 0 mismatches against the report's translator for 400 random globs x 5,010 paths).
Two changes: a fixed-string prefilter on the longest literal piece of the glob (a piece outside
metacharacters and brace groups; `**/` counts as a separator because it can match nothing), and
rewriting a leading `^(?:.*/)?` as an unanchored `(?:^|/)` and a trailing `/.*$` as `/`. The
rewrite helps `**/X/**` globs but made `**/*.ts` 3x slower (unanchored search from every
position), so it must be applied selectively. Best pure-R variant against Rcpp, run 1 (run 2 in
brackets, higher load): `**/test/**/*.test.ts` 25.3 ms vs 10.5 (2.4x) [54 vs 32, 1.7x];
`**/node_modules/**` [24 vs 11.6, 2.1x]; `*.md` 10.0 vs 5.3 (1.9x) [13.7 vs 8.4, 1.6x];
`packages/**/src/**/*.{ts,tsx}` 18.5 vs 6.4 (2.9x) [58 vs 28, 2.1x] and `packages/*/README.md`
9.9 vs 3.0 (3.3x) [12.6 vs 4.3, 2.9x] (for these two the report's own anchored regex stayed
best); `**/*.ts` is best served by the `endsWith()` fast path (3.6 ms in the report's run,
against 22-27 ms for Rcpp at comparable load). So the glob gap is 1.6-3.3x, not 2-9x.

**Frequency and saving.** Once per `find`/`grep`/`ls` call (file discovery), typically 0-3
per turn, on a few thousand paths: under 50 ms in pure R. Saving from Rcpp: effectively 0 with
the dictionary algorithm.

**Verdict: PURE R IS ENOUGH.** Ship the glob translator with the `endsWith()` fast path and the
literal prefilter, and the dictionary gitignore evaluator. For trees with large ignored directories (a `node_modules` with
100k files), prune during the walk rather than listing everything first; that is a design
choice, not a compiled-code one.

### 2.6 Server-sent events: splitting and accumulating 20,000 chunks

**Workload.** An Anthropic-style stream built from Pi's README repeated 40 times plus
non-ASCII text (`café 日本語 😀 naïve — “quoted”`), cut into 20,000 `text_delta` events of 2-7
code points each (a token-sized delta), plus `message_start`, `content_block_start`, a
`: keep-alive` comment and the stop events: 20,005 events, 2.39 MB. Delivered two ways: 20,000
chunks cut at random byte offsets (boundaries inside events and inside UTF-8 sequences), and
20,005 event-aligned chunks. Each event's `data` is decoded with `jsonlite::parse_json()` and
text deltas are accumulated.

**Implementations** (`sse_impl.R`, `sse.cpp`): a pure-R closure parser with a raw-vector buffer
(safe when a chunk ends inside a multi-byte character), the same with a character buffer, and an
Rcpp parser keeping its buffer in an external pointer. Accumulation either with
`acc <- paste0(acc, t)` or by appending to a pre-grown list and one `paste(collapse = "")` at the
end.

```r
sse_new_r <- function() {
  buf <- raw(); nl <- as.raw(10L); cr <- as.raw(13L)
  parse_event <- function(e) {
    l <- strsplit(e, "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
    l <- l[nzchar(l) & !startsWith(l, ":")]
    if (!length(l)) return(NULL)
    isd <- startsWith(l, "data:"); d <- substring(l[isd], 6L)
    sp <- startsWith(d, " "); d[sp] <- substring(d[sp], 2L)
    ty <- l[startsWith(l, "event:")]
    ty <- if (length(ty)) sub("^event: ?", "", ty[1L]) else "message"
    structure(paste(d, collapse = "\n"), names = ty)
  }
  function(chunk) {
    if (any(chunk == cr)) chunk <- chunk[chunk != cr]
    buf <<- c(buf, chunk); n <- length(buf)
    if (n < 2L) return(character())
    isnl <- buf == nl; w <- which(isnl[-n] & isnl[-1L])
    if (!length(w)) return(character())
    last <- w[length(w)]
    txt <- rawToChar(buf[seq_len(last - 1L)])
    rest <- last + 2L; while (rest <= n && buf[rest] == nl) rest <- rest + 1L
    buf <<- if (rest <= n) buf[rest:n] else raw()
    ev <- strsplit(txt, "\n\n", fixed = TRUE, useBytes = TRUE)[[1L]]
    ev <- sub("^\n+", "", ev, useBytes = TRUE)
    out <- unlist(lapply(ev[nzchar(ev)], parse_event))
    if (is.null(out)) return(character())
    Encoding(out) <- "UTF-8"; out
  }
}
```

**Correctness.** All three parsers found 20,004 data events in both chunkings, and the
accumulated text was `identical()` to the source text in every case (including the UTF-8
sequences split across chunks).

**Results** (`v4/bench06_sse.txt`, load 8-11, ms, median of 5; the v2 run at load 22-34 in
brackets):

| 20,004 events | random 120-byte chunks | event-aligned chunks |
|---|---|---|
| split only, pure R raw buffer | 882 [755] | 863 [1,166] |
| split only, pure R character buffer | 735 [548] | 824 [1,757] |
| split only, Rcpp | 51 [38] | 53 [73] |
| split + `parse_json` + list accumulation, pure R | 1,051 [1,188] | 1,155 [1,111] |
| split + `parse_json` + list accumulation, Rcpp splitter | 241 [435] | 247 [306] |
| split + `parse_json` + **`paste0()` accumulation**, pure R | 3,416 [3,348] | 3,338 [4,950] |

Component costs (v4): `jsonlite::parse_json()` on 20,000 payloads 140 ms, `jsonlite::fromJSON()`
935 ms, regex extraction of the delta text without JSON parsing 22 ms, **`paste0()` accumulation
of 20,000 deltas 2,045 ms against 7 ms for list accumulation plus one `paste(collapse = "")`**,
empty loop 1 ms; one `parse_json()` of all 20,000 payloads as a JSON array 64 ms.

**The same stream over HTTP** (`bench06b_sse_httr2.R`): the 2.39 MB stream was served from a
local `webfakes` process and consumed with httr2 1.2.2, the HTTP client gptr is expected to
import (D-01).

```r
run_httr2_sse <- function() {                       # httr2's own SSE parser
  resp <- httr2::req_perform_connection(httr2::request(url)); on.exit(close(resp))
  parts <- vector("list", 20100L); k <- 0L; n <- 0L
  while (!httr2::resp_stream_is_complete(resp)) {
    ev <- httr2::resp_stream_sse(resp)
    if (is.null(ev)) next
    n <- n + 1L
    t <- get_text(ev$data); if (!is.na(t)) { k <- k + 1L; parts[[k]] <- t }
  }
  list(n = n, text = paste(unlist(parts[seq_len(k)]), collapse = ""))
}
run_raw_own <- function(kb = 16) {                  # raw chunks + the pure-R splitter above
  resp <- httr2::req_perform_connection(httr2::request(url)); on.exit(close(resp))
  ps <- sse_new_r(); parts <- vector("list", 20100L); k <- 0L; n <- 0L
  while (!httr2::resp_stream_is_complete(resp)) {
    ch <- httr2::resp_stream_raw(resp, kb = kb); if (!length(ch)) next
    for (d in ps(ch)) { n <- n + 1L; t <- get_text(d); if (!is.na(t)) { k <- k + 1L; parts[[k]] <- t } }
  }
  list(n = n, text = paste(unlist(parts[seq_len(k)]), collapse = ""))
}
```

Both returned 20,004 events and text identical to the source. Times (median of 5; v4 at load
7-8, v3 at load 67-153 in brackets): download only (`req_perform()` + `resp_body_raw()`) 11 ms
[16]; **`resp_stream_sse()` loop 3,832 ms [6,159], i.e. 192 µs per event**;
**`resp_stream_raw(kb = 16)` + own splitter 703 ms [1,240], i.e. 35 µs per event** (147 chunks).
Verification over the same local HTTP set-up (`verify-21/out/orig_bench06b_sse_httr2.txt`, load
7-19, and `verify-21/out/v_sse_httr2.txt`, load 15-27): `resp_stream_sse()` 5,765 and 9,242 ms,
the report's splitter 1,631 and 1,817 ms (3.5x and 5.1x apart), and the vectorised splitter of
the verification below **529 ms (26 µs per event), 17x faster than `resp_stream_sse()`**; all
returned 20,004 events and text identical to the source. (The first attempt of the httr2
re-run failed only because the `webfakes` child process inherited a working directory whose
`.Rprofile` expects renv; it was re-run from the scratch directory.)

**Reading.** Splitting alone is where C++ shines (51-53 ms against 735-882 ms: 14-17x), but
the JSON decode and the R loop around each event are paid in both versions. Per event, including
the JSON decode: own pure-R splitter 35-58 µs, Rcpp splitter 12 µs (4.4-4.7x; 2.7-3.2x
against the vectorised pure-R splitter in the verification below),
`httr2::resp_stream_sse()` 192 µs. Events arrive at the model's generation rate, roughly 20-150
per second for a text stream (an estimate, not measured here). Even at 1,000 events per second, the pure-R
splitter would use 3.5-6% of one core, against 19% for `resp_stream_sse()`. The total for a
20,000-event answer (0.7-1.2 s) is spread over minutes of generation, so it never appears as
latency. The one place where the total becomes visible is replaying a recorded stream in bulk,
and there one `parse_json()` over all payloads (64 ms) is the right tool.

**Verification: a leaner pure-R splitter** (`verify-21/v_sse_fast.R`,
`verify-21/out/v_sse_fast_run2.txt`, load 7-11, median of 5; the same stream and chunkings, built
by the report's own code). `sse_new_r()` calls `lapply(parse_event)` per event, and every call
compiles two regexes (`sub("^event: ?")`, `sub("^\n+")`). `sse_new_r2()` finds blank-line
boundaries with `grepRaw()`, splits the completed part into lines once, and parses all events of
the chunk with vectorised `startsWith()` / `substr()` / `cumsum()` (no regex, no per-event
closure). Its event vectors (payloads and names) were `identical()` to the report's parser and to
Rcpp for all three chunkings and for an edge-case stream (comments, multi-line data, `data:`
without space, blank-line runs, CRLF, an event without data, cut at every byte).

```r
sse_parse_lines <- function(l) {                    # all events of one chunk at once
  blank <- !nzchar(l); id <- cumsum(blank)
  keep <- !blank & !startsWith(l, ":"); if (!any(keep)) return(character())
  l <- l[keep]; id <- id[keep]; ids <- unique(id); out <- character(length(ids))
  isd <- startsWith(l, "data:")
  if (any(isd)) {
    d <- substr(l[isd], 6L, 1e6L); sp <- startsWith(d, " "); d[sp] <- substr(d[sp], 2L, 1e6L)
    did <- id[isd]
    if (anyDuplicated(did)) out <- unname(vapply(split(d, factor(did, levels = ids)), paste, "", collapse = "\n"))
    else out[match(did, ids)] <- d
  }
  ty <- rep.int("message", length(ids)); ise <- startsWith(l, "event:")
  if (any(ise)) {
    e <- substr(l[ise], 7L, 1e6L); sp <- startsWith(e, " "); e[sp] <- substr(e[sp], 2L, 1e6L)
    eid <- id[ise]; f <- !duplicated(eid); ty[match(eid[f], ids)] <- e[f]
  }
  names(out) <- ty; Encoding(out) <- "UTF-8"; out
}
sse_new_r2 <- function() {
  buf <- raw(); nl <- as.raw(10L); cr <- as.raw(13L); nn <- as.raw(c(10L, 10L))
  function(chunk) {
    if (length(grepRaw(cr, chunk, fixed = TRUE))) chunk <- chunk[chunk != cr]
    buf <<- if (length(buf)) c(buf, chunk) else chunk
    p <- grepRaw(nn, buf, fixed = TRUE, all = TRUE); if (!length(p)) return(character())
    last <- p[length(p)] + 1L; n <- length(buf); rest <- last + 1L
    while (rest <= n && buf[rest] == nl) rest <- rest + 1L
    txt <- rawToChar(buf[seq_len(last)]); buf <<- if (rest <= n) buf[rest:n] else raw()
    sse_parse_lines(strsplit(txt, "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
  }
}
```

(Like the report's parsers and the C++ one, it treats CR as a byte to drop, not as a lone line
terminator, and with several `event:` lines in one event it keeps the first, as the report's R
parser does, whereas the C++ parser keeps the last and the SSE specification says the last one
wins. Neither case occurs in the providers' streams, but the production parser should follow the
specification and the property test should include both cases.)

| 20,004 events | report's pure R | **vectorised pure R** | Rcpp splitter |
|---|---|---|---|
| random 120-byte chunks: split only | 570 | 313 | 36 |
| random chunks: split + `parse_json` per event + list | 770 (38 µs/event) | **457 (23 µs)** | 169 (8.4 µs) |
| event-aligned chunks: split + `parse_json` + list | 801 (40 µs) | **581 (29 µs)** | 180 (9.0 µs) |
| 147 chunks of 16 KB (`resp_stream_raw(kb = 16)` size): split + `parse_json` per event | 645 | **218** | 178 |
| 16 KB chunks: split + one `parse_json()` per chunk over a JSON array | | **136** | 92 |

The report's own ratio reproduces (4.5x at this load; an unmodified re-run of `bench06_sse.R`,
`verify-21/out/orig_bench06_sse.txt` at load 8-31, gave 4.1x and **5.9x**, so the report's
splitter can cross the 5x line), but the best pure R is 2.7-3.2x behind the Rcpp splitter with one
event per chunk and 1.2-1.5x with network-sized chunks. The same re-run confirmed the
accumulation rule: `paste0()` over 20,000 deltas 2,747 ms against 11 ms for list + one `paste()`. (An earlier run of
the same script at load 65-73 was discarded: medians up to 8.7 s with maxima of 32 s.)

**Frequency and saving.** Every model call streams. A long 2,000-event answer costs about
0.05-0.1 s of CPU in pure R against 0.02 s with Rcpp, spread over 20-60 s of streaming. Nothing
user-visible is saved.

**Verdict: PURE R IS ENOUGH**, with three rules: read raw chunks (`httr2::resp_stream_raw()`, or a
curl callback) into the vectorised pure-R splitter (`sse_new_r2()` above) instead of calling
`resp_stream_sse()` per event, never compile a regex per event, and accumulate deltas in a list. **Watch candidate #2** if gptr ever drives many parallel streams
from one R process or providers with more than about 1,000 events per second.

### 2.7 Incremental / partial JSON of streamed tool-call arguments

**Workload.** A `write`-style tool call whose arguments hold source code
(`{"path": ..., "content": <20 KB or 200 KB of TypeScript>, "options": {...}}`), streamed as
deltas of 8-40 characters: 21,870-21,942 bytes in 901-904 deltas, and 217,623 bytes in 9,000
deltas. At each delta the accumulated prefix is *repaired* (cut back to the last complete value,
an open string value closed, open objects and arrays closed) so that it parses, then parsed with
`jsonlite::parse_json()`. This is what Pi does for UI previews: it re-parses the whole
accumulated string with `partial-json` at every delta
(`packages/ai/src/api/openai-responses-shared.ts:660`).

**Implementations** (`pjson_impl.R`, `pjson_impl2.R`, `pjson.cpp`): a byte-at-a-time state
machine (string/key/number/literal states, escape and `\uXXXX` tracking, a bracket stack, the
position of the last safe cut). Variants: pure R "naive" loop over code points, full rescan per
delta; the earlier "skip-ahead" pure R (jumps to the next quote but copies `cp[i:n]` on every
string entry, which is accidentally O(n^2)); the earlier incremental pure-R scanner (state kept in
a closure, only the new delta is scanned); **the fixed incremental scanner** (new: the positions
of quotes and backslashes are computed once per delta with `which()` and walked with a pointer);
and an Rcpp scanner, full rescan per delta.

```r
# the fixed fast path inside json_scanner_r2()$feed(delta): skip string contents in one step
sp <- which(cp == 34L | cp == 92L); ns <- length(sp); q <- 1L      # once per delta
# ...
if (l_tok == 1L || l_tok == 2L) {                                   # inside a key or a string value
  if (l_esc == 0L) {
    if (c != 34L && c != 92L) {
      while (q <= ns && sp[q] < i) q <- q + 1L
      if (q > ns) { l_pos <- l_pos + (n - i + 1L); i <- n + 1L; next }   # rest of the delta is string content
      l_pos <- l_pos + (sp[q] - i); i <- sp[q]; c <- cp[i]
    }
    l_pos <- l_pos + 1L
    if (c == 92L) { l_esc <- 1L; l_esc_start <- l_pos }
    else { if (l_tok == 2L) { l_safe_end <- l_pos; l_safe_depth <- l_depth }; l_tok <- 0L }
  }
  # ... escape states, then the structural switch on { [ } ] " : , t n f digits
}
```

```r
run_incr <- function(deltas, every = 1L, parse = TRUE) {   # the driver that was timed
  s <- json_scanner_r2(); out <- NULL; k <- length(deltas)
  for (i in seq_len(k)) { s$feed(deltas[i]); if (i %% every == 0L || i == k) { r <- s$repaired(); if (parse) out <- jsonlite::parse_json(r) } }
  out
}
```

**Correctness.** 300 random JSON documents (nested objects and arrays, strings with quotes,
backslashes, newlines, tabs, `é`, `日`, numbers with exponents, literals, pretty and compact),
every one of their 24,516 prefixes: **0 mismatches** between naive, skip-ahead, earlier
incremental, fixed full-rescan, fixed incremental and Rcpp; 0 repaired prefixes that failed to
parse; complete documents never altered (`v2/bench07_pjson.txt`, `v3/bench07b_pjson.txt`). A
further 535 prefixes with multi-character deltas (which exercise the pointer) also matched.

**Results** (ms, median of 5; 3 for the naive loop and the 200 KB rows):

| 20 KB argument, 904 deltas (`v2/bench07_pjson.txt`, load 18-59) | ms |
|---|---|
| repair at every delta, full rescan: pure R naive loop | 1,206 |
| repair at every delta, full rescan: pure R "skip-ahead" (the O(n^2) bug) | 41,170 |
| repair at every delta, full rescan: Rcpp | 67 |
| repair at every delta: earlier pure-R incremental scanner | 298 |
| repair + parse at every delta: pure R naive / earlier incremental / Rcpp | 1,232 / 478 / 167 |
| repair + parse every 10th delta: earlier incremental | 59 |
| final parse only | 0.20 |
| one repair of the complete 20 KB: naive R / Rcpp; one `parse_json()` | 3.70 / 0.129; 0.205 |
| 1,000 repairs of an 80-byte argument: R / Rcpp; 1,000 `parse_json()` | 68.7 / 1.99; 14.7 |

| `v3/bench07b_pjson.txt` (load 67 falling to 15) | 20 KB, 901 deltas | 200 KB, 9,000 deltas |
|---|---|---|
| **fixed pure-R incremental**, repair at every delta | 274 | 25,990 |
| Rcpp full rescan (text accumulated in a list), repair at every delta | 196 | 17,470 |
| **fixed pure-R incremental**, repair + parse at every delta | 335 | 19,420 |
| Rcpp full rescan, repair + parse at every delta | 304 | 18,540 |
| **fixed pure-R incremental, repair + parse every 20th delta** | **23** | **1,705** |
| Rcpp, repair + parse every 20th delta | 36 | 1,491 |
| scanner state only (feed every delta, no repair or parse), pure R | 11 | 78 |
| final `parse_json()` only | 0.20 | 1.30 |

**Reading.** Scanning is not the cost: the pure-R scanner digests a 200 KB argument in 78 ms. The
cost is producing and parsing the whole repaired prefix at every delta, which is O(n^2) in any
language: 17-26 s for 200 KB in both R and C++. Throttling (every 20th delta here; in production,
at most every 100-250 ms) cuts it by more than 10x in both languages. With throttling, Rcpp was
1.14x faster at 200 KB (1.49 against 1.71 s) and slower at 20 KB in this run (36 against 23 ms);
the verification re-run of the 20 KB case (`verify-21/out/v_pjson_20k.txt`, load 9-22, property
test again 0 mismatches over 24,516 prefixes) gave the opposite order, 29 ms pure R against
17 ms Rcpp (1.7x), with every-delta repair + parse at 393 against 299 ms (1.3x). Either way the
throttled cost is a few tens of milliseconds per 20 KB argument. (As with the diff, the Rcpp
scanner rescans the whole prefix while the R scanner is incremental; the comparison is between
the two shipped designs, not between languages.) The per-call
cost of a small argument (69 µs in R, 2 µs in C++) is irrelevant next to the network.

**Frequency and saving.** Once per streamed tool call, spread over its streaming time. Nothing
is saved by Rcpp once the O(n^2) pattern is avoided.

**Verdict: PURE R IS ENOUGH.** Use the incremental scanner, materialise and parse the prefix at
most every 100-250 ms (and only if a live preview is shown), and parse the final arguments once.
Do not copy Pi's parse-at-every-delta approach.

### 2.8 Token-count estimation for context management

**Question.** Is a real BPE tokenizer (which would need compiled code) worth it, or is a
character heuristic plus provider-reported usage enough? This is what Pi does:
`estimateContextTokens()` = the last assistant message's reported usage + `ceil(chars / 4)`
for the messages after it, and images count as 4,800 characters
(`packages/coding-agent/src/core/compaction/compaction.ts`, "This is conservative
(overestimates tokens)").

**Workload and oracle.** Ten kinds of content an R agent puts into its context: 60 TypeScript files
and 40 Markdown files from Pi, R code (this track's scripts and the vignette code shipped with
data.table, jsonlite, knitr, shiny, stringi), printed R console output (`print(head(mtcars, 32))`,
`summary(lm(...))`, `str(iris)`, `sessionInfo()`, ... as `capture.output()` returns it), CSV,
`package-lock.json`, and non-English text from R's own message catalogues (zh_CN, ja, ru, de,
`msgstr` strings read from the installed `.mo` files). Oracle: **rtiktoken 0.0.7** (Rust, CRAN,
already present in the private library; nothing was downloaded), encodings `o200k_base` (GPT-4o
family) and `cl100k_base`. Claude's and Gemini's tokenizers are not public, and no paid or keyed
API call was allowed, so provider-specific accuracy is an open question (6).

```r
h_chars4 <- function(x) ceiling(nchar(x, "chars") / 4)                    # Pi's heuristic
h_bytes4 <- function(x) ceiling(nchar(x, "bytes") / 4)
h_mixed  <- function(x) { ch <- nchar(x, "chars")                          # ASCII / 4, non-ASCII as 1 each
  na <- ch - nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), "chars"); ceiling((ch - na) / 4 + na) }
cnt <- function(x, rx) nchar(x, "chars") - nchar(gsub(rx, "", x, perl = TRUE), "chars")
features <- function(x) {                                                  # character classes for a fitted heuristic
  cjk <- cnt(x, "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]")
  cbind(alpha = cnt(x, "[A-Za-z]"), digit = cnt(x, "[0-9]"), punct = cnt(x, "[!-/:-@\\[-`{-~]"),
        ws_run = cnt(x, "(?<!\\s)\\s"), cjk = cjk, other_nonascii = cnt(x, "[^\\x00-\\x7F]") - cjk)
}
h_class <- function(x, coef) ceiling(drop(features(x) %*% coef))           # coef from lm.fit on half the chunks
```

**Results** (`v3/bench08_tokens.txt`). Whole corpora, error = heuristic minus o200k_base, as a
percentage of o200k_base:

| Content | chars | o200k tokens | chars per token (o200k / cl100k) | chars/4 error | bytes/4 error | ASCII/4 + non-ASCII error |
|---|---|---|---|---|---|---|
| TypeScript (60 files) | 557,159 | 146,665 | 3.80 / 3.85 | -5.0% | -4.7% | -4.6% |
| Markdown (40 files) | 971,723 | 223,303 | 4.35 / 4.37 | +8.8% | +8.9% | +9.0% |
| R source | 305,471 | 81,431 | 3.75 / 3.77 | -6.2% | -6.2% | -6.1% |
| **printed R console output** | 9,959 | 5,135 | **1.94** / 1.94 | **-51.4%** | -51.3% | -51.3% |
| **CSV** | 9,630 | 5,742 | **1.68** / 1.68 | **-58.1%** | -58.1% | -58.1% |
| **JSON (package-lock)** | 186,184 | 85,343 | **2.18** / 2.17 | **-45.5%** | -45.5% | -45.5% |
| Chinese | 84,709 | 54,961 | 1.54 / 1.28 | -61.5% | -17.7% | +4.2% |
| Japanese | 136,901 | 85,815 | 1.60 / 1.21 | -60.1% | -8.5% | +17.3% |
| Russian | 284,821 | 84,353 | 3.38 / 2.42 | -15.6% | +43.8% | +162.6% |
| German | 270,239 | 72,743 | 3.71 / 3.26 | -7.1% | -5.9% | -3.4% |

Per file, chars/4 against o200k (median, 5th and 95th percentile): TypeScript -3.0% (-13.4%,
+8.5%), Markdown +11.2% (-23.2%, +29.0%), R source -14.3% (-32.7%, +35.2%).

Fitted character-class heuristic (coefficients fitted with `lm.fit` on a random half of about
1,400 chunks of about 2,000 characters, evaluated on the other 707): tokens per character alpha
0.341, digit 1.531, punct 0.386, whitespace run -0.442, CJK 0.919, other non-ASCII 0.419 (the
classes are collinear; the coefficients are not individually meaningful). On held-out chunks,
median absolute error: chars/4 13.0%, class heuristic 9.5%; 95th percentile 60.6% against 31.6%.
The class heuristic is still off by +75% on CSV (5 chunks) and -22% on JSON. (Verification re-run,
`verify-21/out/orig_bench08_tokens.txt`: all whole-corpus token counts and error percentages above
reproduced exactly except the R-source row, whose corpus includes this track's own scripts and
had grown since (313,691 chars, 84,014 tokens, chars/4 error -6.6%); that also changed the random
chunk split, giving chars/4 12.6% against class 8.9% median error, 95th percentile 60.3% against
32.6%, CSV +54% (3 chunks) and JSON -26%. The CSV and JSON figures for the class heuristic are
therefore unstable; the chars/2 rule below does not depend on them.) On the same held-out
chunks cl100k_base and o200k_base differ by a median of 1.2%, but on the whole corpora above
cl100k_base needs 20% more tokens than o200k_base for Chinese, 32% for Japanese and 39% for
Russian: even two public tokenizers from one vendor disagree strongly outside English and code.

Speed on 4.0 MB of mixed text (median of 11; BPE median of 5): chars/4 6.1 ms (3.4 ms over
14,759 pieces); ASCII/4 + non-ASCII 18.8 ms; fitted class heuristic 398 ms (six regex passes);
**rtiktoken o200k_base 648 ms; on a 600 KB, ~150k-token context 241 ms**. rtiktoken's installed
size is 13.2 MB, 11.8 MB of it the shared library with the vocabularies compiled in. (Verification
re-run at load 25-35, about 3x slower in absolute terms: chars/4 17 ms, rtiktoken 1,966 ms per
4 MB and 554 ms per 600 KB; the ordering is unchanged.)

**Reading.** A BPE tokenizer would be exact only for OpenAI models. It would still be a guess for
Claude and Gemini, whose tokenizers are not public, and it would cost a vocabulary of several MB
(well above CRAN's 5 MB data guideline if shipped as data) plus 0.2-0.6 s per full recount. The
provider reports exact usage after every call, so an estimate is only ever needed for the few
messages added since then. For those, the measured problem is not precision but a **systematic
bias: chars/4 underestimates exactly the content an R agent produces most** (printed output,
CSV, JSON) by about half, and CJK by 60%.

**Verdict: PURE R IS ENOUGH; a BPE tokenizer in Rcpp is not justified.** Use provider-reported
usage plus a content-aware heuristic for the trailing messages: chars/4 for prose and code,
**chars/2 for tool results** (measured error -3% for printed R output, -16% for CSV, +9% for
JSON), and about 1 token per non-ASCII CJK character; keep a safety margin. With Pi's 50 KB
tool-output cap, chars/2 cuts the underestimate for one maximal result of printed R output from
about 13.6k tokens to about 0.8k (CSV: from 17.7k to 4.9k).

### 2.9 Object fingerprints for environment diffs between turns

**Question.** Can gptr tell which objects in the user's environment changed during an agent turn,
without hashing multi-GB objects, and is compiled code needed?

**Implementations** (`bench09_fingerprint.R`, `bench09b_fingerprint.R`): address getters
`rlang::obj_address()`, `data.table::address()`, `lobstr::obj_addr()`, `tracemem()` +
`untracemem()`, and our own one-line Rcpp function:

```r
Rcpp::cppFunction('std::string addr_cpp(SEXP x) { char b[32]; std::snprintf(b, sizeof b, "%p", (void*) x); return std::string(b); }')
```

and a fingerprint that never touches the data beyond k sampled elements:

```r
A <- rlang::obj_address
fp_one <- function(v, k = 64L) {
  at <- attributes(v); rn <- NULL
  if ("row.names" %in% names(at)) { rn <- .row_names_info(v, 2L); at$row.names <- NULL }  # never expand compact row names
  parts <- c(A(v), typeof(v), length(v), rn, names(at), vapply(at, A, ""))
  if (is.list(v) && !is.object(v) || is.data.frame(v)) parts <- c(parts, vapply(v, A, ""))  # column addresses
  if (is.atomic(v) && length(v)) { n <- length(v); idx <- unique(round(seq(1, n, length.out = min(k, n))))
    parts <- c(parts, rlang::hash(v[idx])) }                                                   # k sampled values
  if (is.environment(v)) parts <- c(parts, "ENV")      # opaque: contents can change at a constant address
  paste(parts, collapse = "|")
}
snapshot2 <- function(env) { nm <- ls(env, all.names = TRUE, sorted = FALSE)
  vapply(nm, function(n) fp_one(get(n, envir = env, inherits = FALSE)), "") }
```

**Results.**

* All five getters returned the same address (`0x300000000`) for a 1.49 GiB (1.6 GB) double
  vector. Cost per call (median of 5 x 10,000 calls): `tracemem()` + `untracemem()` 0.33 µs, own
  Rcpp 0.48 µs, `rlang::obj_address()` 0.86 µs, `data.table::address()` 0.99 µs,
  `lobstr::obj_addr()` 3.9 µs. `tracemem()` needs R built with memory profiling
  (`capabilities("profmem")` was TRUE here) and marks the object, so it is not a clean API.
* **What an address can and cannot tell** (observed, `v3/bench09_fingerprint.txt`):

| Change | Address changed? | Content changed? |
|---|---|---|
| none | no | no |
| `x[1] <- 5`, x not shared (modified in place) | **no** | yes |
| `attr(x, "note") <- "v2"` (in place) | **no** | yes |
| `x[2] <- 5` while the harness holds a reference (forces a copy) | yes | yes |
| `x <- x + 0` (same values, new object) | yes | no |
| environment / R6 field changed | **no** | yes |
| `data.table::set()` on a shared data.table: table and column address | **no** | yes (the held snapshot changed too) |
| `dt[, c := 1]` (table address) | **no** | yes |

* Address reuse after `rm()` + `gc()`: an 8 MB vector got its predecessor's address back in
  **16 of 20** trials; a 400 MB vector in 1 of 5. Equal addresses therefore do not prove "same
  object" across a free.
* Holding a reference to make copy-on-modify visible is too expensive: the next `x[2] <- 5` on
  the 1.6 GB vector duplicated it (0.37 s and +1.6 GB of memory), exactly what gptr must never do
  to a 5 GB Seurat object.
* `identical(y, y)` on the same 200 MB object: 2.3 µs (pointer check); `identical(y, y2)` on an
  equal but distinct copy: 85.8 ms (full comparison).
* **Snapshot** (fingerprint v2) of a 202-object environment (195 small vectors, the 1.6 GB vector,
  a 1M-row data.frame, a data.table, an `lm` fit, an environment): **4.7 ms** (median of 11). Two
  snapshots with no change in between were identical. After in-place `obj001[1] <- 0`, in-place
  `big[1] <- 7` and `big[123457] <- 7`, `new <- 1`, `rm(obj002)` and `data.table::set(dt, 5L,
  "a", 3)`, it reported added `new`, removed `obj002`, changed `big` and `obj001`, and **missed
  the by-reference change to `dt`** (row 5 is not sampled; columns are compared by address). The
  first version of the snapshot, which used `attributes()` naively, falsely flagged the untouched
  data.frame and data.table: `attributes(df)$row.names` expands compact row names into a new
  vector on every call (two calls gave `0x109e14ad0` and `0x109e18270`).
* **Full hashes are cheaper than expected** (`rlang::hash()` = XXH128 over streamed
  serialisation, medians of 3): 1.6 GB double vector 70-89 ms; 2M-string character vector 83 ms;
  list of 200k small vectors 38.5 ms; 2M-row data.frame (character, numeric, factor) 83 ms; the
  sampled `fp_one()` of that data.frame 0.07 ms; ALTREP `1:2e9` about 0 ms (serialised
  compactly, not materialised). For comparison: `xxhashlite::xxhash()` 114 ms and
  `secretbase::siphash13()` 1,291 ms on 1.6 GB; `digest::digest(xxhash64)` serialises into RAM
  first (176 ms for 200 MB); `lobstr::obj_size()` of the data.frame 394 ms; `object.size()` of the
  2M strings 65 ms.

*Verification re-run* (`verify-21/out/orig_bench09b_fingerprint.txt`, load 17-33): the behaviour
reproduced exactly (two unchanged snapshots identical; detected added `new`, removed `obj002`,
changed `big` and `obj001`; missed the `data.table::set()` change; `attributes(df)$row.names` got a
new address on each call). Times were 2-4x higher at this load (snapshot 18.9 ms, `rlang::hash()`
of the 1.6 GB vector 328 ms, of the 2M-row data.frame 201 ms), still far from noticeable.

**Reading.** No address API is exact on its own, whatever language it is written in: the
missing information (in-place writes, by-reference semantics, address reuse) is not in the
address. Writing our own C function saves 0.4 µs per call over `rlang::obj_address()` and would add
a compiled dependency for nothing. The only extra information C could read is R's internal
reference count (`NAMED`/`REFCNT` macros), and building a feature on reference-counting internals
is exactly the kind of dependence on R internals that R 4.5 and 4.6 have been removing from the
package API (R 4.5.0 upgraded *some* non-API NOTEs to WARNINGs; in R 4.6.0 packages using
`ATTRIB` and `SET_ATTRIB` "will now receive check NOTEs").

**Verdict: PURE R IS ENOUGH** (rlang is already a dependency of httr2). Design: (1) per turn, a
v2-style snapshot (address, type, length, attribute addresses without expanding row names,
column addresses, 64 sampled values) of the environments the agent touched; (2) complement it
with static analysis of the R code gptr itself evaluates (assignment targets of `<-`, `=`,
`<<-`, `assign()`, replacement functions, `set()`, `:=`), since gptr always has that code's text;
(3) optional exact mode: `rlang::hash()` of objects under a size budget, about 0.1 s per 1.6 GB;
(4) never hold references to user objects between turns, and treat environments as opaque.

### 2.10 Base64 encoding of images and hashing

Track 19 had not reported on these, so they were measured here (`bench10_b64_hash.R`,
`v3/bench10_b64_hash.txt`, load 12-13).

**Base64** of a typical agent plot (800x600 PNG, 175,523 bytes), a large plot (2400x1800 PNG,
1,226,320 bytes) and 5 MiB of random bytes (worst case), ms, median of 11:

| Encoder | 176 KB | 1.2 MB | 5 MiB | identical to `base64enc::base64encode()` |
|---|---|---|---|---|
| `jsonlite::base64_enc()` (C) | 0.41 | 3.27 | 13.9 | **no: newline every 72 characters** |
| `jsonlite::base64_enc()` + `gsub("\n", "")` | 1.03 | 8.39 | 35.5 | yes |
| `base64enc::base64encode()` (C) | 0.45 | 3.18 | 14.9 | reference |
| `openssl::base64_encode()` (C) | 0.67 | 4.57 | 19.8 | yes |
| `secretbase::base64enc()` (C) | 1.12 | 8.14 | 35.7 | yes |
| `b64::encode()` (Rust) | 0.45 | 3.08 | 14.7 | yes |
| pure R, vectorised (below) | 7.04 | 41.6 | 182 | yes |
| Rcpp, simple loop | 1.01 | 7.17 | 34.6 | yes |

```r
b64_r <- function(r) {
  n <- length(r); if (!n) return("")
  pad <- (3L - n %% 3L) %% 3L
  v <- matrix(as.integer(c(r, as.raw(integer(pad)))), nrow = 3L)
  i1 <- bitwShiftR(v[1L, ], 2L)
  i2 <- bitwOr(bitwShiftL(bitwAnd(v[1L, ], 3L), 4L), bitwShiftR(v[2L, ], 4L))
  i3 <- bitwOr(bitwShiftL(bitwAnd(v[2L, ], 15L), 2L), bitwShiftR(v[3L, ], 6L))
  i4 <- bitwAnd(v[3L, ], 63L)
  alphabet <- charToRaw("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
  out <- alphabet[rbind(i1, i2, i3, i4) + 1L]
  if (pad) out[length(out) - seq_len(pad) + 1L] <- charToRaw("=")
  rawToChar(out)
}
```

**Hashing** (medians of 5; 3 for the slowest): all 2,125 files of one Pi checkout (27.2 MB):
`file.info()` size + mtime only 6.2 ms; `tools::md5sum()` 122 ms; `rlang::hash_file()` 110 ms;
`xxhashlite::xxhash_file()` 116 ms; `digest::digest(file =, "xxhash64")` 141 ms;
`secretbase::sha256(file =)` 183 ms; `openssl::sha256(file())` 453 ms. One 200 MB file:
`rlang::hash_file()` 25.9 ms, `xxhashlite::xxhash_file()` 61.1 ms, `tools::md5sum()` 464 ms,
`secretbase::sha256()` 914 ms. 1,000 hashes of a 4 KB string: `rlang::hash()` 1.7 ms,
`digest::digest(md5, serialize = FALSE)` 16.6 ms. `tools::sha256sum()` does not exist in R 4.4.3;
it was added in R 4.5.0 (R NEWS, re-checked in verification).

*Verification re-run* (`verify-21/out/orig_bench10_b64_hash.txt`, load 17-23, absolute times about
1.5-2x higher): every encoder again identical to `base64enc::base64encode()` except raw
`jsonlite::base64_enc()` (line breaks); on the 1.2 MB PNG base64enc 7.1 ms, b64 6.1, openssl 9.6,
the Rcpp loop 13.2 and pure R 72 ms, so the hand-written Rcpp encoder is again about 2x slower
than the existing C/Rust encoders. Hashing kept its order (`rlang::hash_file()` 39 ms per 200 MB
against 994 ms for `tools::md5sum()`; 213 ms for 2,125 files, as fast as `md5sum()`).

**Verdict: PURE R IS ENOUGH, using packages gptr already depends on.** Base64:
`openssl::base64_encode()` (openssl arrives with httr2) or `base64enc::base64encode()`; never
`jsonlite::base64_enc()` without stripping its line breaks; the vectorised pure-R encoder
(7 ms for a typical plot) is an acceptable last-resort fallback. Hashing: compare size and mtime
first (6 ms per 2k files), then `rlang::hash_file()` (XXH128, 26 ms per 200 MB) for content;
`tools::md5sum()` needs no package at all. A hand-written Rcpp encoder was slower than the
existing C packages.

## 3. Integration specification (ready for when a routine earns its place)

Everything in this section was exercised on this machine with a minimal package
(`scratchpad/work/21/pkg/rcpptoy`, one routine `grep_lines_cpp()` plus its R reference,
dispatcher and property test): `Rcpp::compileAttributes()`, `roxygen2::roxygenise()`,
`R CMD build`, and `R CMD check --as-cran` on R 4.4.3 with Rcpp 1.1.1. Result:
**Status: 1 NOTE**, and that NOTE is "checking for future file timestamps ... unable to verify
current time" (the sandbox cannot reach the time server; it is not a package problem).
All tests (503 expectations, 0 failures), examples, "checking compiled code", "checking
compilation flags used" and "checking foreign function calls" were OK. The check was run twice,
the second time after converting the test file to ASCII `\u` escapes; installation took 7 s CPU /
15 s wall, then 8 s / 12 s, under load. Logs: `pkg/check_as_cran.txt`, `pkg/check_as_cran2.txt`,
`pkg/rcpptoy.Rcheck/`.

### 3.1 DESCRIPTION

```
Imports:
    Rcpp (>= 1.1.1),
    ...
LinkingTo:
    Rcpp (>= 1.1.1)
Suggests:
    testthat (>= 3.0.0),
    withr
```

* `LinkingTo: Rcpp` gives the compiler Rcpp's headers. `Imports: Rcpp` is also required, because
  code generated by Rcpp calls into the Rcpp shared library at run time (exceptions, `Rcout`,
  interrupt handling), so the Rcpp namespace must be loaded before gptr's DLL is used. This is
  the exception to Writing R Extensions' general rule that a header-only `LinkingTo` package
  "do[es] not need to be (and usually should not be) listed in the 'Depends' or 'Imports'
  fields"; the Rcpp-package vignette's skeleton uses "both Imports: and LinkingTo for Rcpp" plus
  `importFrom(Rcpp, evalCpp)` in NAMESPACE (any Rcpp symbol works; `sourceCpp` is used below).
* `withr` and `testthat` in Suggests: the property test in 3.5 uses both.
* `>= 1.1.0`: from Rcpp 1.1.0 (2025-07-01) C++11 is the minimum standard (Rcpp NEWS).
  *Corrected in verification:* unwind protection has been on by default since Rcpp 1.0.10
  (2023-01-12) and is used unconditionally only from **1.1.1** (2026-01-08), not 1.1.0 (checked
  in the NEWS.Rd of the installed Rcpp 1.1.1 and on GitHub). Rcpp 1.1.1 also stopped using the
  non-API `ATTRIB` entry point, and Rcpp 1.1.2 uses the new R 4.6.0 attribute accessors
  conditionally. Because Rcpp's headers are compiled into gptr's own shared object, a floor of
  `Rcpp (>= 1.1.1)` in both `Imports` and `LinkingTo` is the safer choice: it keeps a source
  install against an older Rcpp from pulling `ATTRIB` into gptr's binary, which R 4.6's check
  reports. (CRAN itself always builds against the current Rcpp.) Current CRAN release:
  **Rcpp 1.1.2, published 2026-07-05** (CRAN package page, re-checked 2026-09-29). The toy
  package that was checked declared `Imports: Rcpp (>= 1.0.12)`, not the floor recommended here.
* `NeedsCompilation: yes` is written by `R CMD build`; do not hand-edit it.
* `SystemRequirements`: **none**. No external library, and no C++ standard should be pinned (3.4).
* Do not add Rcpp to `Depends`.

### 3.2 NAMESPACE via a package-level roxygen block

`R/gptr-package.R`:

```r
#' @keywords internal
#' @useDynLib gptr, .registration = TRUE
#' @importFrom Rcpp sourceCpp
"_PACKAGE"
```

which roxygen turns into

```
importFrom(Rcpp,sourceCpp)
useDynLib(gptr, .registration = TRUE)
```

`importFrom(Rcpp, sourceCpp)` is the conventional way to force the Rcpp namespace to load (any
Rcpp function would do). `.registration = TRUE` makes R use the routine table registered by
`R_init_gptr()` instead of dynamic symbol lookup.

**Bootstrap order (observed).** On a package with no `NAMESPACE` file,
`Rcpp::compileAttributes()` fails with "pkgdir must refer to the directory containing an R
package", and `roxygen2::roxygenise()` fails the same way because it calls `compileAttributes()`
while loading. The working sequence was:

1. write a minimal `NAMESPACE` containing `useDynLib(gptr, .registration = TRUE)` (this is what
   `usethis::use_rcpp()` does for you);
2. `Rcpp::compileAttributes()`;
3. `roxygen2::roxygenise()` (it rewrites NAMESPACE from the roxygen block and re-runs step 2).

With `.registration = TRUE` present, `compileAttributes()` generated this registration code
(verbatim from the test package):

```cpp
static const R_CallMethodDef CallEntries[] = {
    {"_rcpptoy_grep_lines_cpp", (DL_FUNC) &_rcpptoy_grep_lines_cpp, 2},
    {NULL, NULL, 0}
};
RcppExport void R_init_rcpptoy(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
```

and the R wrapper `grep_lines_cpp <- function(x, pattern) .Call(`_rcpptoy_grep_lines_cpp`, x, pattern)`.

### 3.3 `src/` layout and generated files

```
src/
  gptr_grep.cpp        # one file per hot path, each exporting 1-3 functions
  RcppExports.cpp      # GENERATED by Rcpp::compileAttributes(); commit it
R/
  RcppExports.R        # GENERATED; commit it
  grep.R               # grep_lines_r() (reference), grep_lines() (dispatcher)
```

* `RcppExports.cpp` and `RcppExports.R` must be committed: `R CMD build` does not run
  `compileAttributes()`, only `devtools::document()`, `pkgload::load_all()` and
  `pkgbuild::compile_dll()` do.
* Export with `// [[Rcpp::export(rng = false)]]` unless the routine draws random numbers
  (skips the RNG-state save/restore on every call).
* Name compiled entry points `*_cpp` and keep them internal (never `@export` them).
* **`src/Makevars` and `src/Makevars.win` are not needed** and should not be created: no external
  libraries, no include paths beyond `LinkingTo`, no custom flags. The test package built and
  checked without either file. *Corrected in verification:* if one is ever added, a single
  `src/Makevars` is also used on Windows; Writing R Extensions (R 4.6.1): "src/Makevars.win takes
  precedence over src/Makevars" and "Since R 4.2.0, src/Makevars.ucrt takes precedence over
  src/Makevars.win". So add a `.win`/`.ucrt` file only when Windows needs different settings,
  and then keep the files in sync. Never put compiler-specific or diagnostic-suppressing flags in
  them: CRAN policy says packages "should not attempt to disable compiler diagnostics", Writing R
  Extensions calls flags such as `-O2 -Wall -pedantic` GCC/clang-specific, and `R CMD check`
  ("checking compilation flags used", source of R 4.4.3's `tools:::.check_packages`) gives a
  WARNING for `-Wno-*` flags and a NOTE for other `-W` flags such as `-Werror`, `-m` flags such as
  `-march=native`, and `-ffast-math`-type flags. `-O3` is not in that check but is equally
  compiler-specific, so leave optimisation to the site configuration.
* No `cleanup` script is needed (it only matters with a `configure` script). `R CMD build`
  already ran "cleaning src": the built tarball contained only `grep_lines.cpp` and
  `RcppExports.cpp`, not the `.o` / `.so` files that `load_all()` had left in `src/`.
* `.gitignore`: `src/*.o`, `src/*.so`, `src/*.dll`. `.Rbuildignore` (belt and braces, since
  build cleans src anyway): `^src/.*\.o$`, `^src/.*\.so$`, `^src/.*\.dll$`.

### 3.4 C++ standard

* **Do not set `CXX_STD`.** Default standards (R NEWS; *corrected in verification*): C++11 in
  R 4.0.x (the minimum supported since R 4.0.0); **C++14 from R 4.1.0 on Unix-alikes, but still C++11 on Windows until R 4.2.3**
  (R 4.2.3 NEWS: "(Windows) The default C++ standard had accidentally been left at C++11 when it
  was changed to C++14 on Unix"); C++17 from R 4.3.0; and **C++20 from R 4.6.0** ("The default
  C++ standard has been changed to C++20 where available", R 4.6.0 NEWS). R 4.6.0 also removed
  C++11 and C++14 as selectable standards ("Support for these standards has been removed: the
  default C++ standard will be used"), and notes that "Packages can request C++17 if essential".
  R 4.5.3 checks `CXX_STD` values more thoroughly (invalid values are ignored with a warning).
* gptr's minimum R is 4.1.0 (decision D-23, preliminary), where the default is C++14 on
  macOS/Linux but C++11 on Windows (R 4.1.0-4.2.2). Therefore **write the routines in the C++11
  subset that is also valid C++14/17/20/23** (C++11 is also Rcpp >= 1.1.0's minimum; for example
  `std::search` or `memchr`/`memcmp` instead of C++17's `std::boyer_moore_horspool_searcher`, no
  `std::string_view`, no `if constexpr`, no C++14 generic lambdas or `std::make_unique`). Then no
  `CXX_STD` line is needed on any supported R version.
* Verified here: all eight C++ files written for this track compile with **zero warnings** under
  `clang++ -Wall -pedantic -DR_NO_REMAP` in `-std=gnu++17`, `gnu++20` and `gnu++23`
  (Homebrew clang 23.1.1). `-DR_NO_REMAP` matters because R 4.5.0 and later compile all C++ with it:
  always write `Rf_mkCharLenCE`, `Rf_translateCharUTF8`, `Rf_length` etc. with the `Rf_` prefix.
  (The benchmark files use C++17's Boyer-Moore-Horspool searcher and `// [[Rcpp::plugins(cpp17)]]`;
  a package version would replace that with `memchr` + `memcmp` to stay C++11-clean.)
  Re-checked in verification with `clang++ -fsyntax-only -Wall -pedantic -DR_NO_REMAP` (Homebrew
  clang 23.1.1, R 4.4.3 and Rcpp 1.1.1 headers): all eight files 0 warnings, 0 errors under
  gnu++17, gnu++20 and gnu++23; under gnu++11 and gnu++14 seven of eight are clean and `grep.cpp`
  fails (2 errors, the C++17 searcher), as expected.

### 3.5 The dual-implementation pattern

Every compiled routine is a triple: reference, compiled, dispatcher. The reference is the
specification; the compiled version is an optimisation of it.

```r
# R/grep.R
grep_lines <- function(x, pattern) {
  x <- enc2utf8(as.character(x))                       # 1. all normalisation and validation in R
  pattern <- enc2utf8(as.character(pattern))
  if (length(pattern) != 1L || is.na(pattern) || !nzchar(pattern))
    stop("`pattern` must be a single non-empty string.", call. = FALSE)
  if (gptr_use_compiled()) grep_lines_cpp(x, pattern) else grep_lines_r(x, pattern)
}

# Reference implementation: THE specification of grep_lines_cpp().
grep_lines_r <- function(x, pattern) which(grepl(pattern, x, fixed = TRUE, useBytes = TRUE))

gptr_use_compiled <- function() {
  opt <- getOption("gptr.use_compiled")
  if (is.null(opt)) opt <- !identical(Sys.getenv("GPTR_USE_COMPILED"), "false")
  isTRUE(opt)
}
```

```cpp
// src/gptr_grep.cpp
#include <Rcpp.h>
#include <algorithm>
#include <climits>
#include <vector>
// Behaviour is defined by grep_lines_r() in R/grep.R; tests cross-check the two.
// [[Rcpp::export(rng = false)]]
Rcpp::IntegerVector grep_lines_cpp(Rcpp::CharacterVector x, Rcpp::String pattern) {
  const R_xlen_t n = x.size();
  if (n > INT_MAX) Rcpp::stop("long vectors are not supported");
  const char* p = pattern.get_cstring();
  const char* pe = p + std::char_traits<char>::length(p);
  std::vector<int> hits;
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 65535) == 0) Rcpp::checkUserInterrupt();
    SEXP s = STRING_ELT(x, i);
    if (s == NA_STRING) continue;
    const char* c = CHAR(s);
    const char* ce = c + LENGTH(s);
    if (std::search(c, ce, p, pe) != ce) hits.push_back(static_cast<int>(i + 1));
  }
  return Rcpp::wrap(hits);
}
```

```r
# tests/testthat/test-grep-lines.R. The toy package ran this under R CMD check --as-cran (it used
# options() + on.exit() where this version uses withr::local_options(); all tests passed).
random_lines <- function(n) {
  alphabet <- c("a", "b", "c", "d", " ", "\t", "\u00e9", "\u65e5", "\U0001F600")
  x <- vapply(seq_len(n), function(j) paste(sample(alphabet, sample(0:12, 1), TRUE), collapse = ""), "")
  if (n > 0 && stats::runif(1) < 0.2) x[sample(n, 1)] <- NA
  enc2utf8(x)
}
test_that("compiled and reference implementations agree on random inputs", {
  set.seed(20260929)
  alphabet <- c("a", "b", "c", " ", "\u00e9", "\u65e5")
  for (i in 1:500) {
    x <- random_lines(sample(0:60, 1))
    pat <- enc2utf8(paste(sample(alphabet, sample(1:3, 1), TRUE), collapse = ""))
    expect_identical(gptr:::grep_lines_cpp(x, pat), gptr:::grep_lines_r(x, pat))
  }
})
test_that("the option switches implementation without changing results", {
  x <- c("alpha", "beta", NA, "alphabet", "\u00e9t\u00e9")
  withr::local_options(gptr.use_compiled = FALSE)
  r_result <- grep_lines(x, "alpha")
  withr::local_options(gptr.use_compiled = TRUE)
  expect_identical(grep_lines(x, "alpha"), r_result)
})
```

Rules that make the pattern hold up:

1. **The R wrapper owns all semantics that are not the hot loop**: argument validation, `NA`
   policy, encoding conversion (`enc2utf8()`), path normalisation, file I/O where possible, result
   shaping. The C++ function receives validated UTF-8 input and does one thing.
2. **Property tests on random inputs**, seeded, including the awkward cases: zero-length
   vectors, `NA`, empty strings, multi-byte UTF-8 (2-, 3- and 4-byte), CR/LF, very long strings,
   boundary positions (match at byte 0 / last byte), and inputs larger than any internal buffer.
   Every benchmark in this track already has such a cross-check (diff: 3,000 random cases;
   partial JSON: 24,516 prefixes; gitignore: 200 random rule sets x 5,000 paths).
3. **Run the whole test suite twice in CI**: once as is, once with `GPTR_USE_COMPILED=false`, so
   that every tool-level test also exercises the reference path.
4. **Keep the benchmark that justified the routine** in `dev/bench/` (excluded by
   `.Rbuildignore`), per REQ-01(a), and re-run it when either implementation changes.
5. The option is a debugging and escape hatch, not a feature flag: results must be identical
   either way, so users never need to set it.

### 3.6 C++ rules for R data (checked against this track's code)

* **Strings.** R strings cannot contain NUL; `std::string` can. `Rf_mkCharLenCE()` raises
  "embedded nul in string" for such input, so binary content must be detected (the NUL sniff)
  before strings are created. Always create strings with `Rf_mkCharLenCE(ptr, len, CE_UTF8)`
  (or `Rcpp::String::set_encoding(CE_UTF8)`), never with `Rf_mkChar()` (native encoding, no
  mark). Read R strings with `Rf_translateCharUTF8()` when the input may carry another encoding
  mark; if the R wrapper already did `enc2utf8()`, `CHAR()` is safe.
* **Paths.** `fopen(Rf_translateChar(path))` works on macOS/Linux and on Windows with R >= 4.2
  (UTF-8 active code page), but the portable choice is to do file I/O in R (`readBin()`) and hand
  raw vectors to C++; the measurements below show reading is not where Rcpp wins most.
* **Long vectors.** Index with `R_xlen_t`; return 1-based positions as `double` (or refuse
  `n > INT_MAX` explicitly, as above).
* **Interrupts.** Call `Rcpp::checkUserInterrupt()` every 2^8 to 2^16 iterations of any loop
  that can run longer than about 100 ms. It unwinds through C++ destructors, so hold resources
  in RAII objects (`std::unique_ptr<FILE, int(*)(FILE*)>`, `std::vector`), not raw handles.
* **Never** `abort()`, `exit()`, `assert()`, `std::terminate()`, `printf()`, `std::cout`,
  `std::cerr`. CRAN policy: "Compiled code should never terminate the R process within which it
  is running." Use `Rcpp::stop()`, `Rcpp::warning()`, `Rcpp::Rcout`, `Rcpp::Rcerr`.
* **Memory protection.** Use Rcpp vector classes (they protect themselves) or build results in
  `std::vector` and convert once at the end, as every routine in this track does. Never keep a
  bare `SEXP` across an allocation. CRAN's rchk runs catch the rest.
* **API only.** Use typed accessors (`STRING_ELT`, `CHAR`, `LENGTH`, `RAW`, `INTEGER`, `REAL`)
  and Rcpp proxies. Never use a non-API entry point: R 4.5.0 upgraded "some" of the non-API
  NOTEs to WARNINGs, and R 4.6.0 reports `ATTRIB` and `SET_ATTRIB` with NOTEs
  (`tools:::nonAPI` in the running R gives the current list). R 4.5.0 also made strict R headers
  the default (no `PI`, `Calloc`, `Free`: use `M_PI`, `R_Calloc`, `R_Free`). Do not build anything on reference-count internals (`NAMED`, `REFCNT`).
* **Threads.** None in v1. If ever added, never call the R API (including allocation and
  `checkUserInterrupt`) off the main thread, and never use more than two threads under CRAN
  checks.

### 3.7 Order of preference before writing C++

1. A better algorithm in R (this track: patience diff, gitignore dictionary, raw-byte grep
   prefilter and match-offset line extraction, sparse line index, incremental JSON scanner, list
   accumulation; from verification: token prefilter for the block search, literal prefilter for
   globs, vectorised per-chunk SSE parsing with no regex per event).
2. A function of a package gptr already imports (rlang, openssl, curl, jsonlite via httr2).
3. An optional accelerator in Suggests with an identical-results test (fs for listing; stringi
   or utf8 for NFKC).
4. Only then an Rcpp routine, following 3.1-3.6. Section 5 compares the costs of options 2-4.

## 4. Recommended decision for v1, and the watch list

**Decision (answer to D-21): gptr v1 contains no compiled code.** `DESCRIPTION` has no
`LinkingTo`, no `src/`, and `NeedsCompilation` stays `no`. REQ-01's Rcpp exception remains
available: section 3 is the ready-made procedure, and the candidate C++ files from this track
(all compiled, all cross-checked, all warning-free under C++17/20/23) are the starting points.

What v1 should do instead (all pure R, all measured above):

| Area | v1 implementation |
|---|---|
| grep | list (base `list.files()`, or `fs::dir_ls()` when installed, then sorted), `readBin()` per file, raw-byte `grepRaw(fixed = TRUE)` prefilter for literal patterns, whole-file `grepl("(?m)...", perl = TRUE, useBytes = TRUE)` prefilter for regexes, NUL sniff on the first 8,000 bytes; for files that hit, match and newline offsets with `grepRaw(all = TRUE)` + `findInterval()` and one `rawToChar()` / `strsplit()` over the gathered matching lines (2.1, verification); early exit at the limit (default 100) |
| read with offset | `grepRaw()` newline scan in 1 MB chunks; cache a sparse line index (every 10,000th line) keyed by path, size and mtime for files over about 20 MB |
| edit diff | interning with `unique()` + `match()`, common prefix/suffix trim, patience anchors (LIS), vectorised Myers on gaps capped at D = 256 per gap |
| edit fallback | fixed-string prefilter on the block's longest non-blank token, then whitespace normalisation (two PCRE `gsub()` calls) of the candidate windows only and vectorised block comparison (2.4, verification: 1.6 ms); NFKC folding only when stringi (or utf8) is installed |
| find / glob / ignore | glob-to-PCRE translator with an `endsWith()` fast path and a fixed-string prefilter on the glob's longest literal piece; component-dictionary gitignore evaluator; prune ignored directories during the walk |
| streaming | `httr2::resp_stream_raw()` (or a curl callback) into the vectorised pure-R SSE splitter (`sse_new_r2()`, 2.6: no regex and no function call per event); deltas accumulated in a list; never `resp_stream_sse()` per event, never `paste0()` accumulation |
| tool-call arguments | incremental JSON scanner; materialise and parse a preview at most every 100-250 ms; parse the final arguments once |
| context size | provider-reported usage + chars/4 for prose and code + chars/2 for tool results + a margin |
| workspace diff | address/type/length/attribute/column fingerprint with 64 sampled values (4.7 ms per 202 objects) + static analysis of evaluated code; optional `rlang::hash()` under a size budget; no references held to user objects |
| images, hashes | `openssl::base64_encode()` or `base64enc::base64encode()`; `file.info()` size + mtime, then `rlang::hash_file()` |

**Watch list.** Each item names the trigger that would reopen the question and the measured
starting point. The bar is unchanged: noticeable in pure R *and* at least about 5x from Rcpp.

1. **Fixed-string grep on very large trees, especially on Windows.** Today 1.0-1.7x at the
   default limit (2.5x for "every file matches, no limit" with the match-offset extraction;
   3.6-4.0x without it). Reopen if Windows or Linux
   measurements (not done here) show the pure-R tool above about 1 s on a typical 2k-5k-file
   repository, or users routinely search trees of 50k+ files. Starting point: `grep_fixed_cpp2()`
   in `grep.cpp` (move file I/O back to R and pass raw vectors; replace the C++17 searcher with
   `memchr` + `memcmp`).
2. **SSE splitting for many parallel streams or very fast providers.** Today 2.7-3.2x per event
   with the vectorised pure-R splitter (8-9 against 23-29 µs; 4.1-5.9x against the report's
   original splitter; 1.2-1.5x with 16 KB network chunks). Reopen if gptr runs many sub-agent
   streams in one R process (REQ-33) and the splitter measurably exceeds about 5% of the main
   thread. Starting point: `sse.cpp`.
3. **Line index for huge files** (`count_lines_cpp`: 113-213 ms against 403-838 ms per 200 MB,
   3.6-3.9x; a far read without an index 3.1-4.6x). This is now the candidate closest to the 5x
   ratio, but it is paid once per huge file. Reopen only if paging through multi-GB logs becomes
   a core use.
4. **Glob matching of more than about 1M paths** (1.6-3.3x per glob with the literal prefilter;
   2-9x with the plain translator).

Not on the watch list, because a better algorithm or design already equals or beats C++:
gitignore evaluation (dictionary), line diff (patience + cap), partial JSON (incremental +
throttle), whitespace-normalised block search (token prefilter: 1.6 ms, faster than the Rcpp
routine), base64 and hashing (existing packages), token counts (usage + heuristic),
fingerprints (rlang).

**Re-evaluation protocol.** Keep this track's scripts under `dev/bench/` (excluded by
`.Rbuildignore`), and re-run the grep, read and SSE benchmarks on Windows and Linux (CI runners)
before the v1 release and whenever the pure-R implementations change. Any future Rcpp routine
must arrive with its benchmark output, its R reference implementation and the property test
(section 3.5).

## 5. CRAN and cross-platform considerations

What changes the day gptr gains a `src/` directory:

| Area | Pure R package (v1 as recommended) | With Rcpp code |
|---|---|---|
| Install on Windows / macOS from CRAN | platform-independent tarball, no compiler, available immediately on acceptance | CRAN-built binaries (Windows x86_64, macOS arm64 and x86_64). For the first hours to days after each release, until binaries are built, `install.packages()` may offer the newer *source* version, which needs **Rtools** (Rtools 4.5 covers R >= 4.5.0 including R-devel) or the **Xcode command line tools** |
| Install on Linux | no compiler needed | CRAN is source-only on Linux: needs `g++`/`clang++` (Posit Package Manager and r-universe provide Linux binaries) |
| Build time | none | test package with one 20-line routine: 7-8 s CPU / 12-15 s wall to install under load (Rcpp headers dominate); expect roughly 20-40 s for three or four routines |
| Run-time dependency | none | `Rcpp` in Imports (9.3 MB installed here; nearly universal in practice) |
| Installed size | R code only | test package `.so`: 118,616 bytes (arm64, `-g -O2`); installed package 204 KB. Size is not a concern for small routines |
| Extra CRAN check flavours ("additional issues") | almost none apply to pure R code | clang-ASAN, gcc-ASAN, clang-UBSAN, gcc-UBSAN, valgrind, rchk, rcnst, LTO, noRemap, Strict (`STRICT_R_HEADERS`), 0len, M1mac, linux-arm64, musl, Intel oneAPI, and new-compiler runs (clang23 is listed now). A finding on these pages typically comes with a CRAN deadline to fix before the package is archived |
| Compiler warnings | n/a | CRAN's check machines compile with at least `-Wall -pedantic` and report "significant" warnings. Our routines: 0 warnings under `-Wall -pedantic` in C++17/20/23 with `-DR_NO_REMAP`. With `-Wextra`, clang 23.1.1 emitted 105 warnings (57 `-Wcast-function-type-mismatch`, 48 `-Wunused-parameter`): 104 in Rcpp's own headers and 1 (a function-pointer cast) in the generated `RcppExports.cpp`; none in our code. `R CMD check` did not flag them |
| Future R changes | R-level API only | C API evolution: R 4.5 compiles C++ with `-DR_NO_REMAP`, makes strict R headers the default, and upgraded some non-API NOTEs to WARNINGs; R 4.6 made C++20 the default, removed C++11/14, and reports `ATTRIB`/`SET_ATTRIB` with NOTEs. Rcpp absorbs most of this (1.1.1, 1.1.2), but gptr's own code must follow too |
| webR / WebAssembly | works | needs an Emscripten build (r-universe / the webR repository); plain portable C++ like these routines should build, but this was not tested |
| CRAN policy exposure | file system, network, cores | also: "Compiled code should never terminate the R process" (no `abort`/`exit`/`assert`/`std::terminate`), no disabling diagnostics, at most two threads |

Cross-platform text details that the C++ side would have to reproduce exactly, and that the
pure-R path gets from R for free:

* **Encoding.** On R >= 4.2 for Windows the native encoding is UTF-8; before that it was a
  Windows code page. Returning strings marked `CE_UTF8` is correct on every platform. The R
  wrapper should call `enc2utf8()` on inputs (the test package does).
* **Line endings.** Every routine in this track strips a trailing `\r` per line exactly like the
  R reference (`sub("\r$", "", ...)`); the property tests include CRLF.
* **Binary detection.** NUL in the first 8,000 bytes (git's heuristic; ripgrep checks any NUL).
  Required before creating R strings.
* **Paths.** `list.files()` returns native-encoded names; C `fopen()` of a UTF-8 path works on
  Windows only with the UTF-8 code page (R >= 4.2). Doing I/O in R avoids the question.

Alternatives that avoid owning compiled code:

* **Optional accelerator packages (Suggests)**, used only if installed, with a test proving
  identical results. Measured candidates: `stringi` (NFKC normalisation, which base R lacks;
  36.3 MB installed, 35.5 MB of it the shared library with ICU bundled), `utf8` (NFKC via `utf8_normalize(map_compat = TRUE)`,
  0.7 MB), `data.table` / `vroom` (line ranges of huge files; 6.8 MB / 2.0 MB plus 14 Imports for
  vroom), `fs` (directory listing 3.5-4x faster than `list.files()`; 0.4 MB), `yyjsonr` (JSON,
  see track 19; 3.0 MB). `diffobj` is **not** worth it: slower than the pure-R patience diff (2.3).
* **Packages gptr imports anyway.** If gptr imports `httr2` (decision D-01), it already pulls in
  `rlang`, `openssl` and `curl`, so `rlang::obj_address()`, `rlang::hash()`,
  `rlang::hash_file()`, `openssl::base64_encode()` and `openssl::sha256()` are free.
  `jsonlite::base64_enc()` is free with jsonlite.
* **The trade-off.** Every accelerator in Suggests is another code path to test (and CRAN's
  noSuggests flavour runs without them). Every package in Imports is weight and upgrade risk
  for all users. Owning C++ adds the extra check flavours and the release-day
  source-install window. For v1 the measured gains do not pay for any of the three except
  where an accelerator is needed for correctness (NFKC).
* **cpp11** (header-only, 1.1 MB, no run-time dependency) is the other mainstream C++
  interface. REQ-01 names Rcpp, so this report specifies Rcpp. cpp11 would remove the
  `Imports: Rcpp` line, and the dual-implementation pattern is the same.

## 6. Risks and open questions

**Risks**

* **Measurement noise.** Load averages of 8-153 from other agents. Absolute times are inflated,
  in the worst windows by 2-3x (for example, reading 10.6k files took 551 ms at load 12 and
  7.7-9.9 s at load 150), and some medians have wide ranges (Rcpp gitignore 660-2,441 ms in one
  run). Speed-up ratios measured within one run were stable across the v2, v3, v4 and earlier runs
  (grep, unlimited searches: 2.1-4.1x in all four samples; gitignore dictionary at or below Rcpp
  in all three samples, including the earlier run's 198 against 199 ms), and
  no verdict depends on the ratio alone. The one ratio that crossed 5x in any run for a
  shipped-design comparison is SSE with the report's splitter (4.1-5.9x; 5.9x in one verification
  run), where the absolute cost is far below noticeable and the vectorised splitter brings it to
  2.7-3.2x. The next closest is the far read of a 200 MB file without an index (3.1x in the
  report's run, 4.6x in the verification re-run at load 15-34), paid once per huge file. Ratios above 5x occur only where the pure-R cost per operation
  is small in absolute terms (diff of 200-line files under 3 ms, single globs over 100k paths under
  100 ms with the plain translator, SSE splitting alone at about 16-40 µs per event).
* **macOS only.** All numbers are from an Apple M2 with APFS and a warm page cache. Windows (NTFS,
  antivirus scanning, slower `list.files()`) could make pure-R grep and discovery several times
  slower; this is the most likely way watch item 1 becomes real. Cold-cache I/O was not measured
  and would slow C++ and R alike.
* **Per-turn frequencies are estimates** derived from Pi's tool design, not telemetry.
* **Fingerprinting blind spots.** In-place writes at unsampled positions, by-reference changes
  (data.table `set()`/`:=`, environments, R6, external pointers) and address reuse after a free can
  all hide a change. The design relies on static analysis of the evaluated code to cover them. That
  analysis is not yet specified and cannot see through arbitrary function calls.
* **Token heuristics** were validated against OpenAI encodings only; Claude's and Gemini's
  tokenizers may deviate more, especially for non-English text.
* **Adding compiled code later** brings a one-time cost: CRAN's release-day window in which
  Windows and macOS users are offered a source package that needs Rtools or Xcode tools, plus the
  additional check flavours from then on.
* **The toy-package check ran on R 4.4.3 only.** R 4.6's C++20 default and `-DR_NO_REMAP` were
  emulated with explicit compiler flags (all eight C++ files compiled without warnings); a full
  `R CMD check` on R 4.6 and on Windows was not run.

**Open questions**

1. Should gptr use an `rg` binary when one is already on `PATH` as an optional accelerator, as
   track 01 suggested? It is not an R package, so it is outside REQ-01's Rcpp rule. In the v2 run on
   10.5k files it took 191-462 ms against 875-2,169 ms for the optimised pure-R search (1.9-5.4x,
   with the R figures excluding listing). It would need an exact output-parity test suite.
2. Should `fs` be in Suggests purely for faster listing (3.5-4x on stage 1)? It is small (0.4 MB)
   and compiled, and results must be sorted and normalised to match `list.files()`.
3. What minimum R version will gptr declare (D-23: preliminarily 4.1.0)? It fixes the default C++
   standard that any future routine must compile under without `CXX_STD`: C++11 on Windows for
   R 4.1.0-4.2.2, C++14 on Unix-alikes for R 4.1-4.2, C++17 from R 4.3.0.
4. For NFKC folding in the edit fallback: stringi (36 MB installed, already common) or utf8
   (0.7 MB, same output on the cases checked)? Or drop NFKC, which Pi applies?
5. How large may a workspace become before the optional full `rlang::hash()` pass should be
   skipped? The measured rate (about 18 GB/s for doubles, about 1.7 GB/s for strings and lists)
   suggests a default budget of about 1 GB per turn.
6. Does the streaming layer run on the main thread only, or will parallel sub-agents stream in
   the same process (REQ-33)? The answer decides whether watch item 2 can ever trigger.

## 7. Sources

Primary, checked on 2026-09-29:

* Rcpp on CRAN, version 1.1.2, published 2026-07-05, Depends R (>= 3.5.0):
  https://cran.r-project.org/package=Rcpp
* Rcpp NEWS (C++11 minimum in 1.1.0 (2025-07-01); unwind protection on by default since 1.0.10
  and used unconditionally, and `ATTRIB` no longer used, in 1.1.1 (2026-01-08); R 4.6.0 attribute
  accessors used conditionally in 1.1.2; development version 1.1.2.4 dated 2026-09-22):
  https://raw.githubusercontent.com/RcppCore/Rcpp/master/inst/NEWS.Rd, and the `NEWS.Rd` of the
  installed Rcpp 1.1.1 (verification)
* Rcpp vignette "Rcpp-package" (installed with Rcpp 1.1.1, dated January 8, 2026): skeleton
  DESCRIPTION uses "both Imports: and LinkingTo for Rcpp", NAMESPACE `importFrom(Rcpp, evalCpp)`,
  Makevars optional since Rcpp 0.11.0. Vignette "Rcpp-attributes": `// [[Rcpp::export(rng = false)]]`;
  `compileAttributes()` is called automatically only by RStudio and devtools.
* R NEWS, current release R 4.6.1 (2026-06-24): C++20 default in R 4.6.0, "Packages can request
  C++17 if essential", C++11/C++14 support removed and their `R CMD config` variables defunct,
  `ATTRIB`/`SET_ATTRIB` NOTEs; R 4.5.0: C++ compiled with `-DR_NO_REMAP`, strict R headers the
  default, "Some" non-API NOTEs upgraded to WARNINGs, `tools::sha256sum()` added; R 4.5.3:
  `CXX_STD` values checked more thoroughly: https://cran.r-project.org/doc/manuals/r-release/NEWS.html
* R 4.1.0 made C++14 the default on Unix; R 4.2.3 notes that on Windows the default "had
  accidentally been left at C++11"; R 4.3.0 made C++17 the default (R 4.4.3's own `doc/NEWS`,
  read in verification; also https://cran.r-project.org/bin/windows/base/NEWS.R-4.6.0.html)
* Writing R Extensions (R 4.6.1), "Using C++ code", plus (verification) the `NeedsCompilation`
  field ("normally set by R CMD build or the repository"), Makevars precedence on Windows
  (`Makevars.win` over `Makevars`, `Makevars.ucrt` over `Makevars.win` since R 4.2.0), the
  `LinkingTo` rule for header-only packages, and portable flags:
  https://cran.r-project.org/doc/manuals/r-release/R-exts.html
* `R CMD check`'s "compilation flags used" rules: body of `tools:::.check_packages` in R 4.4.3
  (`-Wno-*` gives a WARNING; other `-W` flags, `-m` flags and fast-math flags a NOTE)
* CRAN Repository Policy (revision 6875): no terminating the R process from compiled code, no
  disabling diagnostics, at most two threads, binaries only built by CRAN, 5 MB data/doc
  guideline: https://cran.r-project.org/web/packages/policies.html
* CRAN "additional issues" check kinds (ASAN, UBSAN, valgrind, rchk, LTO, noRemap, Strict, 0len,
  M1mac, musl, linux-arm64, clang23, ...): https://cran.r-project.org/web/checks/check_issue_kinds.html
* Rtools ("RTools 4.5 for R versions from 4.5.0 (including R-devel)"):
  https://cran.r-project.org/bin/windows/Rtools/
* macOS toolchain (Xcode command line tools sufficient for C/C++):
  https://mac.r-project.org/tools/

Code read first-hand (Pi monorepo, commit `1b347794`):

* `packages/coding-agent/src/core/compaction/compaction.ts`: `estimateTokens()` uses
  `Math.ceil(chars / 4)` ("This is conservative (overestimates tokens)"), images count as 4,800
  characters, and `estimateContextTokens()` = last provider-reported usage + chars/4 for the
  messages after it.
* `packages/ai/src/utils/json-parse.ts` and `packages/ai/src/api/openai-responses-shared.ts`:
  tool-call arguments are re-parsed with `partial-json` over the whole accumulated string at
  every delta (`parseStreamingJson(slot.block.partialJson)`).

Related gptr research used: `dev/research/01-pi-builtin-tools.md` (pure-R grep validated against
ripgrep; stage profile), `dev/research/00-digest.md`, `dev/spec/00-vision-brief.md` (REQ-01),
`dev/spec/01-decision-register.md` (D-01, D-19, D-20, D-21, D-23), and the in-progress track 19
JSON benchmark (`scratchpad/work/track-19/out_b1_json.txt`). Reports 11 and 19 did not exist when
this report was written.

Measurements: every number in this report comes from the scripts in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/21/`
run on 2026-09-29. Raw outputs are in `v2/` (re-runs of the earlier researcher's scripts), `v3/`
(new scripts) and `v4/` (low-load repeats of the SSE and gitignore benchmarks). The toy package and its check log are in `pkg/`.
Numbers marked "verification" come from the scripts and outputs in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-21/`
(`v_*.R` new, `orig_*.R` unmodified copies of the track scripts; outputs in `out/`).

## Verification log

Independent adversarial check, 2026-09-29, same machine (Apple M2, 8 cores), R 4.4.3
(`Rscript --vanilla`, `en_US.UTF-8`), Rcpp 1.1.1, same corpus (`work/21/corpus`: five copies of
the Pi checkout in `scratchpad/pi` without `.git`, `diff -rq` against `rep1` clean) and the same
`big200.txt`. The machine was again shared: 1-minute load 6-174 during the runs; each output file
logs the load at start and end, a run at load 65-73 was discarded, and only ratios measured in
the same run are compared. Every verdict was attacked from both sides: is pure R slower than
claimed (Rcpp justified after all), and was the pure R used the best available formulation (the
task's main test for a fair comparison). No "RCPP JUSTIFIED" verdict existed to overturn; no
"PURE R IS ENOUGH" verdict was overturned. Changes made in the report are listed per claim.

**Benchmarks** (outputs in `verify-21/out/`; "report" = the report's own number)

| # | Claim checked | Verification measurement | Verdict |
|---|---|---|---|
| B1 | 2.1 grep at the default limit is 1.0-1.7x from Rcpp | Unmodified re-run of `bench01d` (load 9-22): 10.6k files 1.04-1.36x, 2.1k files 1.1-1.9x (the 1.9x is `import`, median 102 ms with range 68-323); `v_grep_fast` (load 6-16): 1.0-1.4x | Confirmed |
| B2 | 2.1 "every file matches, no limit" is 3.6-3.7x | Re-run 3.8-3.9x; new match-offset extraction (`grepRaw(all = TRUE)` + `findInterval()`, identical output in 12 configurations + edge cases) 1,345 vs 533 ms and 250 vs 102 ms: **2.5x** | Refined: better pure R found; text, table, v1 plan and watch #1 updated |
| B3 | 2.1 reading dominates and C++ reads faster | `readBin()` of 2,125 files 70 ms vs C++ `fread` loop 89 ms (load 6-16) | Refined (note added) |
| B4 | 2.1 `std::regex` 11-22x slower than R's PCRE | 2.1k files, load 22-35: 4.7x and 19x slower, identical line sets | Corrected to 5-22x; conclusion stands |
| B5 | 2.2 far read without index 3.1x from Rcpp | Re-run of `bench02c` (load 15-34): 851 vs 185 ms (4.6x; 4.3x on minima); middle 3.2x; index pass 3.9x; all byte-identical | Corrected to 3.1-4.6x; "cold" relabelled "no index yet (page cache warm)"; verdict unchanged (rare, index) |
| B6 | 2.2 `grepRaw(all = TRUE)` is the best base-R newline counter | 10.5 ms per 4 MiB vs 17.3 (`sum(r == nl)`), 29.2 (`gsub` count), 31.4 ms (logical subset); counts equal | Confirmed |
| B7 | 2.3 diff: capped patience fast and valid; Rcpp plain Myers slower on big edits | 1,000 random cases 0 failures; 2,000 lines 0.4-8.9 ms; 20,000 large 55.7 ms vs Rcpp 321 / diffobj 1,331; rewrite 46.8 vs 3,620 / 8,606 ms | Confirmed; "16-35x" corrected to 4-16x (large) / 35-77x (rewrite); exec bullet "Rcpp 1.2 s" corrected to 0.2-1.2 s |
| B8 | 2.4 Rcpp 4.3x faster for the block search | Report's R 25.7-26.8 ms vs Rcpp 5.9 ms (4.4x) reproduced; **token prefilter 1.6 ms** (1.8 ms worst case), 0 mismatches on 300 random blocks | **Overturned ratio**: pure R 3.7x *faster* than Rcpp; watch item removed; v1 plan updated |
| B9 | 2.5 single globs 2-9x from Rcpp | Literal prefilter (+ selective regex rewrite), 0 mismatches for 400 random globs: 1.6-3.3x over two runs; the rewrite alone made `**/*.ts` 3.2-3.8x slower | Refined: 1.6-3.3x; watch item updated |
| B10 | 2.5 gitignore dictionary = Rcpp | Re-run of `bench05b` (load 9-22): 880 vs 831 ms, property test 0 failures; cost split: anchored rules 288 ms of 477 | Confirmed, with a fairness caveat added (the Rcpp matcher does not use the dictionary) |
| B11 | 2.6 SSE 4.4-4.7x per event | `v_sse_fast` (load 7-11): report's splitter 38-40 µs vs Rcpp 8.4-9.0 µs (4.5x); re-run of `bench06` (load 8-31): 4.1x and 5.9x; **vectorised splitter 23-29 µs (2.7-3.2x)**, 16 KB chunks 1.2-1.5x; identical events in all chunkings and edge cases | Refined: better pure R found; watch #2 updated; R/C++ disagreement on repeated `event:` lines flagged |
| B12 | 2.6 `resp_stream_sse()` 192 µs/event, 5.5x the raw-chunk path | Load 7-27: 288-462 µs/event, 3.5-5.1x the report's splitter, 17x the vectorised splitter (529 ms for 20,004 events over HTTP) | Corrected range; recommendation strengthened |
| B13 | 2.6 `paste0()` accumulation 2.0-3.4 s vs 7 ms | 2,747 vs 11 ms | Confirmed |
| B14 | 2.7 partial JSON: Rcpp 0.6x when throttled (20 KB) | 29 ms pure R vs 17 ms Rcpp (1.7x); every delta 393 vs 299 ms; 24,516 prefixes 0 mismatches | Corrected to 0.6-1.7x; verdict unchanged (tens of ms). 200 KB rows not re-run |
| B15 | 2.8 token counts and chars/4 errors | 9 of 10 corpora identical to the digit; R-source corpus grew (track scripts added) so -6.6% vs -6.2%; held-out class heuristic CSV +54% vs +75% (3-5 chunks) | Confirmed; instability of the small-sample CSV/JSON figures noted. chars/2 arithmetic (-3%, -16%, +9%; 13.6k -> 0.8k) recomputed: confirmed |
| B16 | 2.9 fingerprint behaviour and cost | Detections, the missed `set()` change and the row-names address churn reproduced; times 2-4x higher at load 17-33 | Confirmed |
| B17 | 2.10 base64 / hashing | Same identities (`jsonlite` line breaks every 72 characters confirmed separately), same ordering; Rcpp loop about 2x slower than base64enc/b64 | Confirmed |
| B18 | Warm vs cold cache | Page cache warm in every run of both passes; cold-cache I/O could not be measured (no `purge` without sudo) | Noted as untested (already in section 6) |

**Integration specification** (sources in section 7)

| # | Claim checked | Source / check | Verdict |
|---|---|---|---|
| S1 | REQ-01 "bar" of 200 ms / 1 s / 5x | `dev/spec/00-vision-brief.md` REQ-01 and D-21 contain no numbers | Corrected: labelled as this report's operationalisation |
| S2 | Imports + LinkingTo + `importFrom(Rcpp, ...)` | Rcpp-package vignette ("both Imports: and LinkingTo for Rcpp", `importFrom(Rcpp, evalCpp)`); WRE `LinkingTo` rule | Confirmed; WRE exception explained |
| S3 | "From Rcpp 1.1.0 ... unwind-protect always on" | Installed Rcpp 1.1.1 `NEWS.Rd` and GitHub NEWS: unconditional in 1.1.1; default since 1.0.10 | **Corrected**; floor `>= 1.1.1` suggested |
| S4 | Rcpp 1.1.2 on CRAN, published 2026-07-05 | CRAN package page | Confirmed |
| S5 | `NeedsCompilation` written by `R CMD build` | WRE: "normally set by R CMD build or the repository" | Confirmed |
| S6 | Bootstrap: `compileAttributes()` fails without NAMESPACE | Reproduced ("pkgdir must refer to the directory containing an R package"); works after writing `useDynLib(..., .registration = TRUE)`; generated `R_registerRoutines` / `R_useDynamicSymbols(dll, FALSE)` | Confirmed |
| S7 | `R CMD build` does not run `compileAttributes()`; `rng = false` | Rcpp-attributes vignette; generated code for `rng = false` has no `RNGScope` | Confirmed |
| S8 | Makevars: "both must exist and stay in sync" | WRE: `Makevars.win` takes precedence over `Makevars`, `Makevars.ucrt` over `.win` (R >= 4.2.0) | **Corrected** |
| S9 | `-O3` reported under "checking compilation flags used" | `tools:::.check_packages` (R 4.4.3): `-Wno-*` WARNING; other `-W`, `-m`, fast-math NOTE; `-O3` not checked | **Corrected** |
| S10 | Default C++ standard "C++14 before R 4.3.0" | R NEWS: C++11 before 4.1.0; C++14 from 4.1.0 on Unix but C++11 on Windows until 4.2.3; C++17 from 4.3.0; C++20 from 4.6.0; C++11/14 removed in 4.6.0 | **Corrected**: write C++11-clean code |
| S11 | `-DR_NO_REMAP` from R 4.5.0 | R NEWS 4.5.0 | Confirmed (strict headers default added) |
| S12 | "R 4.5 turned the non-API NOTEs into WARNINGs; R 4.6 added ATTRIB/SET_ATTRIB" | R NEWS: "Some" NOTEs upgraded in 4.5.0; `ATTRIB`/`SET_ATTRIB` give NOTEs in 4.6.0 | **Corrected wording** (2.9, 3.6, 5, 7) |
| S13 | All eight C++ files warning-free in C++17/20/23 with `-DR_NO_REMAP` | Re-compiled (`-fsyntax-only -Wall -pedantic`): 0 warnings / 0 errors; C++11/14: `grep.cpp` fails (C++17 searcher), others clean | Confirmed |
| S14 | Toy package check: 1 NOTE, 503 tests, sizes | `pkg/check_as_cran2.txt`, `testthat.Rout`, `.so` 118,616 bytes, 204 KB installed, tarball holds only the two `.cpp` files | Confirmed; the toy `DESCRIPTION` used `Rcpp (>= 1.0.12)` (noted) |
| S15 | `checkUserInterrupt()` unwinds through destructors | `Rcpp/Interrupt.h`: throws `internal::InterruptedException` | Confirmed |
| S16 | CRAN policy quotes (revision 6875) | Policy page: process termination, diagnostics, two threads, binaries, 5 MB | Confirmed |
| S17 | Rtools 4.5 for R >= 4.5.0 incl. R-devel; macOS x86_64 binaries; check kinds incl. clang23 | Rtools page (no Rtools 4.6 listed); R 4.6.1 x86_64 installer listed; check-issue-kinds page | Confirmed |
| S18 | Package sizes in section 5 | `v3_pkgsizes.txt` against `du` of the installed packages | Confirmed |

**Not re-run:** the 200 KB partial-JSON rows (8 minutes per run), the grep stage-split
(`bench01c`), the text-connection/`scan()`/data.table/vroom rows of 2.2, the full `bench01`
micro-benchmarks other than the regex comparison, and the address-getter micro-timings of 2.9.
Nothing in them bears on a verdict.

**Net effect on the decision:** D-21 stands (no compiled code in v1). The verification removed one
watch item (block search), weakened two (SSE, globs), and made the grep case weaker than
reported (2.5x worst case); the closest remaining candidate to the 5x ratio is the huge-file line
index (3.1-4.6x), which is paid once per file.
