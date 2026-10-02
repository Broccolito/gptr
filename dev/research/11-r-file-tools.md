# Track 11 — Pure-R implementation of read, write, edit, grep, find, ls, sort

Research date: 2026-09-29. Author: research sub-agent (track 11). Consumers: the gptr design and implementation agents.

Requirement IDs (`REQ-nn`) refer to `/Users/wanjun/Desktop/gptr/dev/spec/00-vision-brief.md` (REQ-01, 02, 03, 05–08, 10 are the ones this track serves). Decision IDs (`D-nn`) refer to `dev/spec/01-decision-register.md`.

**Evidence levels.** VERIFIED = I ran it or read the cited source lines myself. LIKELY = inferred from verified evidence. UNCERTAIN = could not verify here (almost always Windows runtime behaviour: this machine is macOS arm64).

**Environment for every experiment** (VERIFIED): R 4.4.3 (aarch64-apple-darwin20), `Rscript --vanilla`, Apple M2 (8 cores), macOS Darwin 25.6.0, PCRE 10.44, ICU 78.1, Apple libiconv 1.11, ripgrep 15.2.0 at `/opt/homebrew/bin/rg`, Apple git. `Rscript --vanilla` runs in the **C locale** here (`LANG` unset), which turned out to be a very good stress test; every test was also run with `LANG=LC_ALL=en_US.UTF-8`. Package versions: stringi 1.8.7, data.table 1.18.2.1, vroom 1.7.1, readr 2.2.0, brio 1.1.5, fs 2.1.0, arrow 23.0.1.1, qs 0.27.3, magick 2.9.1, png 0.1.9, jpeg 0.1.11, base64enc 0.1.6, diffobj 0.3.6, jsonlite 2.0.0, filelock 1.0.3, processx 3.8.6, readxl 1.4.5, openssl 2.3.5, utf8 1.2.6 (qs2 and nanoparquet not installed).

**Machine load warning.** The machine was shared with many parallel agents; load averages during benchmarks ranged from 8 to 70 on 8 cores. Every benchmark table states the load average at its start. Absolute milliseconds are therefore inflated (typically 1.5–4x); orderings and ratios were stable across repeated runs and are what the recommendations rely on.

**Benchmark corpus.** The Pi clone at `…/scratchpad/pi` (commit `1b347794`, 2026-09-29): 2,125 files visible to git and to the gptr walker (25.9 MB), 422,936 lines of TypeScript, `package-lock.json` 186,185 bytes / 5,935 lines. Two synthetic big files were built from it (`mkcorpus.R`, from the interrupted earlier run, re-verified): `big.ts` = all `.ts` files concatenated, 14,774,596 bytes / 422,246 lines; `big10.ts` = 10 copies, 147,745,960 bytes / 4,222,460 lines. A synthetic R project with a heavy `node_modules/` (24,000 files) and `renv/library/` (16,000 files) was built for the walker benchmark.

**Prior work.** An earlier researcher on this track was interrupted after writing `work/11/mkcorpus.R`, `work/11/bench-read.R` and `data/bench-read.rds`, and no report. Its results flagged `readBin`/`readChar` window readers as "MISMATCH". I traced that to a **bug in the benchmark, not in the readers**: `strsplit(..., useBytes = TRUE)` returns *unmarked* strings, so non-ASCII lines compared unequal to the UTF-8-marked reference in a C locale (VERIFIED, §2.9 P1). A second bug appeared after that fix: `strsplit()` drops a trailing empty piece when a window ends on a blank line (P2). The corrected benchmark `bench/bench-read2.R` shows all 12 readers returning identical windows. Track 01 (`01-pi-builtin-tools.md`) had already specified Pi's tools and written a first R prototype; this track re-implemented the file tools independently, went deeper on performance, encodings, atomic writes and Windows, and cross-checks track 01 where they overlap (differences are listed in §7).

All scratch material is in `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11/` (`proto/` implementation, `tests/` test + platform probe, `bench/` benchmarks, `out/` logs). Because that directory is temporary, **§5 embeds every source file and every log verbatim**.

---

## 1. Executive summary

1. **All seven file capabilities can be pure base R and fast enough for an agent loop.** A complete prototype (8 files, ~1,600 lines, ASCII-only, base R + `tools`/`utils` + `jsonlite`) implements `read`, `write`, `edit`, `grep`, `find`, `ls` and sorting. **159 assertions pass in the C locale and in `en_US.UTF-8`; 144 pass with every optional package blocked** (stringi, utf8, magick, base64enc, openssl, arrow, qs, png, jpeg, diffobj, processx). VERIFIED.
2. **Oracles agree exactly.** The walker's file set equals `git ls-files --cached --others --exclude-standard` on the Pi monorepo (2,125 files) and equals `git ls-files --others --exclude-standard` on a synthetic repo with 14 tricky `.gitignore` constructs (negation, dir-only, anchoring, `**`, escapes, nested ignore files, case folding). `grep` returns the identical (file, line) set as ripgrep for 5 patterns (110 to 10,061 matching lines). Unified diffs apply cleanly with `git apply`. VERIFIED.
3. **Speed on the Pi monorepo (26 MB, 2,125 files).** A full-scan pure-R grep takes 0.26–0.63 s versus 0.05–0.17 s for ripgrep, under load average ~28. With the tool default `limit = 100` the R engine stops early: 0.09–0.27 s, and on common patterns it beats ripgrep, which must scan everything (0.14 s vs 0.46 s). The walker takes 32–46 ms. **No Rcpp is needed for the file tools** (REQ-01 bar not met). VERIFIED.
4. **Pruning ignored directories is the decisive walker optimisation for R projects.** On a project with `node_modules/` and `renv/library/` (40,419 entries, 401 relevant), the breadth-first pruned walk takes **5 ms**. `list.files(recursive = TRUE)` + filter takes 575 ms and `fs::dir_ls(recurse = TRUE)` takes **9.1 s**. `list.files(recursive = TRUE)` also *follows symlinked directories*, and on a symlink loop it produced thousands of bogus paths. VERIFIED.
5. **The fastest way to read thousands of small files in R is `readChar(path, size, useBytes = TRUE)`.** It runs at 127–145 ms for 2,125 files, versus 363–436 ms for `readBin` + `rawToChar` and 925 ms for `stringi::stri_read_raw`. A NUL byte truncates the result, so `nchar(x, "bytes") < size` detects binary files anywhere in the file for free, which is ripgrep's rule. VERIFIED.
6. **Line-window reads (`offset`/`limit`) need no dependency.** Files ≤ 16 MB are read whole, newlines are indexed on the raw vector, and only the window is decoded and split: a 14.8 MB file reads in 79–149 ms. Larger files use a streaming 8 MB-chunk newline index with bounded memory and exact total line count: a 148 MB file reads in 0.43–0.90 s. `vroom`/`fread`/`readr` skip faster but cannot give the total line count cheaply. `vroom` with ALTREP also **keeps the file handle open** until garbage collection, which on Windows blocks the next edit or rename of that file. VERIFIED (handle), LIKELY (Windows consequence; confirmed by the vroom maintainer).
7. **Atomic write = temp file in the same directory + `file.rename()`.** On Windows R calls `MoveFileExW(REPLACE_EXISTING|COPY_ALLOWED|WRITE_THROUGH)` and **retries 10 × 500 ms** on sharing violations (R source `src/gnuwin32/extra.c`). Verified POSIX side effects that the prototype handles: rename replaces a symlink with a regular file (so resolve the link first), resets the mode (`755`→`644`, so copy it), and breaks hard links (documented). Encoding happens *before* the file is touched, and a failed rename falls back to an in-place overwrite. VERIFIED (macOS), UNCERTAIN (Windows runtime).
8. **Never write through text-mode connections.** In a C locale, `writeLines(x)` and `cat(x)` write `caf<U+00E9>` instead of the UTF-8 bytes. `file(encoding = "latin1")` silently writes `<U+4E2D>` escapes for unrepresentable characters. `writeLines` always appends a newline, and on Windows text mode turns `\n` into `\r\n`. Use `writeBin(charToRaw(enc2utf8-safe text))` on a `"wb"` connection. VERIFIED (macOS), docs for Windows.
9. **`edit` is byte-exact outside the edited spans.** This goes beyond Pi, which rewrites every line ending to the first one found. Mixed CRLF/LF files, UTF-8 BOM, CP1252/latin1/UTF-16 files, and files with stray invalid bytes all round-trip. The fuzzy fallback (NFKC, trailing whitespace, smart quotes, dashes, special spaces) rewrites only the touched lines, as in Pi. `replaceAll` (Claude Code's `replace_all`) is added. VERIFIED.
10. **The diff engine can be pure R.** It trims the common prefix/suffix, anchors on unique lines with a longest-increasing-subsequence step (patience), and runs Myers with a cost cap on the remaining gaps. It needs 1 ms for typical edits and 34 ms for a 200k-line file with 2 edits, versus 1 and 11 ms for `diffobj::ses` (C). Pathological rewrites (30–100% of lines changed) cost 0.15–0.3 s in pure R. `diffobj` is a useful *optional* accelerator. `tools::Rdiff` is not a diff algorithm and is unsuitable. VERIFIED.
11. **`utils::glob2rx()` cannot be used.** Its `*` crosses `/`, `**/*.R` misses top-level files, it supports neither `{a,b}` nor `[ab]` (it escapes the class), and it leaves `+` unescaped, so `a+b.R` never matches itself. A 40-line `glob_to_regex()` handles all of these with fast paths (`*.ext` → `endsWith`). VERIFIED.
12. **The `.gitignore` matcher must implement nearly the whole spec.** That covers negation, dir-only rules, leading/middle-slash anchoring, `*` `?` `[]` `**`, escapes, trailing spaces, per-directory files with their own base, ancestor files up to the repo root, `.git/info/exclude`, last-match-wins, pruning of excluded parents (so no re-inclusion is possible), and **case folding when `core.ignorecase`/the file system is case-insensitive** (macOS clones get `core.ignorecase=true`). Only `core.excludesFile` is left out, and it is documented. VERIFIED against git.
13. **Twenty-one R platform traps were verified (§2.9), and each has a guard or an open item.** The verifier narrowed two of them: P5 is about `\x{…}` only, not `\p{…}`, and in P16 the `fread` text-file failure was an artifact. The ones that break naive code: `iconv(sub = "Unicode")` **loops forever** on invalid UTF-8 (macOS libiconv); `iconv(sub = <UTF-8 string>)` inserts the literal text `<U+FFFD>` in a C locale; PCRE `\x{2019}` fails to compile whenever all inputs are ASCII, in every locale, unless the pattern starts with `(*UTF)`; the default TRE engine does not short-circuit `^`-anchored patterns (267 ms vs 18 ms); `enc2utf8()` corrupts unmarked UTF-8 in a C locale; `readLines()` treats a lone CR as a line break and strips a BOM only in UTF-8 locales.
14. **Sorting must use `method = "radix"`.** `sort()` uses the locale's collation (354 ms for 100k paths vs 11 ms radix at load 11; 1.3 s under load 45; verifier re-run at load 22: 1,599 vs 39 ms) and orders differently in C and UTF-8 locales. Natural sort in pure R (vectorised `natural_key()`) takes 0.47 s per 100k; `stringi::stri_order(numeric = TRUE)` takes 0.2 s. Top-N is `order()` + `head` (3 ms). `data.table` gives only ~1.6x on 100k rows and is not worth a dependency. VERIFIED.
15. **Paths.** `normalizePath()` returns non-existent paths unchanged, even relative ones and with `..` intact, so resolution must be lexical (`path_norm()`). Workspace containment must use the realpath of the longest existing ancestor (catches symlink and `..` escapes) and compare case-insensitively on case-insensitive file systems (macOS default, Windows). Drive letters, UNC roots and Git-Bash `/c/…` paths are handled lexically. VERIFIED (logic), UNCERTAIN (Windows runtime).
16. **Images.** Sniff by magic bytes (PNG/JPEG/GIF/WebP/BMP, APNG rejected). A pure-R header parser gets dimensions. Images within limits pass through untouched; otherwise `magick` (Suggests) resizes to ≤ 2000 px and < 4.5 MB of base64 (Pi's defaults). Current Anthropic API limits: 10 MB per image direct / 5 MB on Bedrock/Vertex, 8000 px max, 2000 px when a request holds > 20 images. Use `base64enc` (13 ms per 5 MB) or `openssl`. `jsonlite::base64_enc` alone is about as fast as `base64enc` (verifier re-run: 32 vs 28 ms), but it wraps its output with `\n` every **72** characters, and stripping those made the pipeline 2–16x slower across runs. VERIFIED (corrected by the verifier: wrap width and cause of the slowdown).
17. **Structured data in `read`.** `.rds/.RData/.qs/.parquet/.feather/.xlsx` get a compact preview (class, dims, `str()`, first rows, a loading hint) in 15–36 ms for 1e6-row files. Deserialisation (`.rds/.RData/.qs`) is capped at 50 MB and **refused on R < 4.4.0** because of CVE-2024-27322 (RDS deserialisation RCE, fixed in 4.4.0). VERIFIED.
18. **Dependency recommendation.** No new `Imports` for the file tools. `Suggests`: `stringi` (or the tiny `utf8`) for NFKC and NFD, `base64enc`, `magick`, `arrow`, `qs`/`qs2`, `readxl`, `diffobj`, `processx` (for the optional ripgrep accelerator), `filelock` (cross-process writes). Not needed: `fs`, `vroom`, `readr`, `brio`, `data.table` (for these tools).

---

## 2. Findings

### 2.1 Pi behaviour to match (read first-hand)

Paths are relative to `pi/packages/coding-agent/src/`. Track 01 §3 has the verbatim schemas; only what shapes the R implementation is repeated here (all VERIFIED).

| Topic | Pi behaviour | Source |
|---|---|---|
| Limits | 2000 lines / 51,200 bytes (50 KB), whichever first; grep line cap 500 chars | `core/tools/truncate.ts:11-13` |
| Head truncation | never partial lines; a first line above the byte limit yields empty content + `firstLineExceedsLimit` | `truncate.ts:78-160` |
| `read` splitting | `buffer.toString("utf-8").split("\n")`: JS split semantics, so a trailing `\n` gives a final empty line and `\r` of CRLF stays in the text; **no line numbers** | `core/tools/read.ts:134-136` |
| `read` notices | `[Showing lines A-B of N. Use offset=K to continue.]`, `(50.0KB limit)` variant, `[R more lines in file. Use offset=K to continue.]`, error `Offset X is beyond end of file (N lines total)` | `read.ts:142-181` |
| `read` images | magic-byte sniff (JPEG, PNG without `acTL`, GIF, WebP, BMP), resized to ≤ 2000×2000 and < 4.5 MB base64 (Photon/WASM), text note first | `utils/mime.ts:6-23`, `utils/image-resize-core.ts:5-29`, `read.ts:112-131` |
| `write` | `mkdir -p` of the parent, then `writeFile(path, content, "utf-8")`: verbatim, **not atomic**, no EOL/encoding preservation; message `Successfully wrote to <path>` | `core/tools/write.ts:34-37, 78-87` |
| Mutation queue | writes/edits to the same realpath are serialised in-process | `core/tools/file-mutation-queue.ts:32-61` |
| `edit` schema | `{path, edits: [{oldText, newText}]}`; legacy top-level `oldText/newText` and JSON-string `edits` accepted | `core/tools/edit.ts:21-41, 103-134` |
| `edit` algorithm | strip BOM; EOL = first line ending; normalise CRLF and lone CR to LF; match all edits against the original; fall back to fuzzy space if any edit fails exactly; duplicates, overlap and "no change" are errors; restore EOL everywhere; re-add BOM | `edit.ts:190-199`, `core/tools/edit-diff.ts:11-25, 300-362` |
| Fuzzy normalisation | NFKC, `trimEnd()` per line, `‘’‚‛`→`'`, `“”„‟`→`"`, U+2010–2015/U+2212→`-`, NBSP/U+2002–200A/U+202F/U+205F/U+3000→space | `edit-diff.ts:34-55` |
| Occurrence counting | **always in fuzzy space**, even for exact matches (quirk) | `edit-diff.ts:247-251, 328` |
| Unchanged-line preservation | fuzzy path rewrites only touched line groups from the normalised text | `edit-diff.ts:132-173` |
| `edit` result | model sees only `Successfully replaced N block(s) in <path>.`; diff and patch go to `details` (UI only) | `edit.ts:201-210` |
| `grep` | spawns ripgrep `--json --line-number --color=never --hidden [--ignore-case] [--fixed-strings] [--glob G] -- pattern path`; default limit 100 matching **lines**; context lines re-read from the file; `path:N: text` / `path-N- text`; 500-char line cap; 50 KB output cap | `core/tools/grep.ts:41, 136, 162-166, 197-215, 280-303` |
| `find` | spawns fd `--glob --color=never --hidden [--no-require-git] --max-results N [--full-path]`; `--no-require-git` only when no `.git` is found in an ancestor; a pattern containing `/` gets `--full-path` and a `**/` prefix, so it matches at any depth; default 1000; the SDK fallback ignores `**/node_modules/**`, `**/.git/**` | `core/tools/find.ts:41, 126, 182-214` |
| `ls` | `readdir` + `stat`, sorted `a.toLowerCase().localeCompare(b.toLowerCase())`, `/` suffix for dirs, broken links skipped, default 500 | `core/tools/ls.ts:23, 100-130` |
| Paths | unicode spaces→space, strip leading `@`, `~` expansion, `file://` URLs, Git-Bash/WSL drive paths on Windows; read-only fallbacks for macOS screenshot names (U+202F, NFD, U+2019) | `utils/paths.ts:7, 68-107`, `core/tools/path-utils.ts:52-84` |

### 2.2 `read`: line windows, big files, encodings, binary, images, data files

**Window readers (`bench/bench-read2.R`).** Each reader returns lines `[offset, offset+limit)` with `limit = 2000`. Correctness is checked against `readLines()`, and all 12 readers return identical windows (VERIFIED). The table shows median ms, en_US.UTF-8, load average 11.6 (run at 19:46). A second run at load 27 kept the same order at 1.5–2.5x the times (`out/bench-read2.txt`).

| reader | 15 MB head | 15 MB middle (200k) | 15 MB tail (420k) | 148 MB head | 148 MB tail (4.2M) | gives total lines? |
|---|---|---|---|---|---|---|
| `readBin` whole + `which(b == 0x0A)` index, split window only | 49 | 68 | 60 | 378 | 415 | yes |
| streaming 8 MB chunks, newline index, `seek` + read window | 82 | 88 | 65 | 371 | 568 | yes (bounded memory) |
| whole file → one string → split all (what Pi does) | 150 | 125 | 99 | 939 | 1508 | yes |
| `readLines()` all | 204 | 158 | 132 | 1541 | 2432 | yes |
| `readLines(con)` skip in 50k chunks | 5 | 356 | 662 | 4 | 7755 | no |
| `scan(skip, nlines)` | 1 | 45 | 80 | 1 | 1163 | no |
| `stringi::stri_read_lines` | 193 | 177 | 142 | 1339 | 1642 | yes |
| `data.table::fread(sep="\n", skip, nrows)` | 2 | 8 | 15 | 2 | 203 | no |
| `vroom::vroom_lines(skip, n_max, altrep=FALSE)` | 2 | 8 | 15 | 2 | 192 | no |
| `vroom_lines(altrep=TRUE)` + `length()` | 25 | 26 | 22 | 248 | 305 | yes (lazy index, open handle) |
| `brio::read_lines(n)` | 1 | 27 | 93 | 1 | 706 | no |
| `readr::read_lines(skip, n_max)` | 2 | 7 | 17 | 1 | 163 | no |

Findings:
* Pi's contract needs the **total line count** (`… of N`). Only readers that scan the whole file provide it. Among them the pure-R newline index is 2–4x faster than splitting everything, and within 1.5–2x of vroom's multithreaded lazy index. VERIFIED.
* `fread`/`vroom`/`readr` are the fastest at *skipping*, but: (a) no total line count; (b) `fread(sep = "\n")` warns or stops early on binary files (NUL bytes) and warns on empty files. **Corrected by the verifier:** the original claim that it also failed on a plain text file (`packages/ai/test/empty.test.ts`) was a benchmark artifact. `tryCatch(..., warning = )` aborted `fread()` mid-call on the preceding binary file (`red-circle.png`), and the *next* call then warned "Previous fread() session was not cleaned up properly", so it returned nothing. When warnings are muffled with `withCallingHandlers()` so that every call completes, `fread` agrees with `readLines()` on all text files, and its `import` matches equal ripgrep's 10,061 lines exactly (verifier re-run). The real pitfall is that aborting `fread()` from a warning handler poisons the next call; (c) they are multi-threaded by default (CRAN: at most 2 cores); (d) vroom ALTREP keeps 2 file handles open until `rm()` + `gc()` (VERIFIED with `lsof`, `out/probe-*.txt` §V1; per the maintainer the handle is also released once all data has been materialised). The vroom maintainer confirms that on Windows this blocks deleting the file ("vroom holds an open file handle to the file until all data has been read", r-lib/vroom#280). `altrep = FALSE` and `fread` leave no handle open (VERIFIED).
* The final `read_text_lines()` design: for size ≤ 16 MB, read the whole file, decide the encoding on the whole text (`validUTF8`), index newlines on the raw vector, and decode and split **only the window**. Above 16 MB, sample 64 KB for the encoding and use the streaming index (bounded memory). The threshold is 16 MB rather than 64 MB because `b == 0x0A` allocates a 4-bytes-per-byte logical vector. End-to-end `gptr_read()` timings: 14.8 MB file 79–94 ms (load 11) / 128–149 ms (load 15); 148 MB file 533–896 ms / 663–781 ms; a 556-line source file 1–3 ms. Before the window-only split the 14.8 MB case took 272–309 ms. VERIFIED (`out/bench-readtool.txt`).
* Counting lines of the 148 MB file (load 11): chunked `readBin` + `sum(b == 0x0A)` 657 ms, vroom ALTREP 432 ms, `fread` 1147 ms, `readLines` 2494 ms, `wc -l` 277 ms. VERIFIED.

**Line semantics.** Pi splits on `\n` only. `readLines()` treats LF, CRLF **and a lone CR** as line ends ("Any of LF, CRLF or CR will be accepted as the EOL marker for a line", R docs). `'a\rb\nc'` is 3 lines for `readLines` and 2 for Pi. VERIFIED (`out/probe-C.txt` §R1). gptr must therefore never use `readLines` for tool line numbers, or `grep`, `read` and `edit` would disagree. The prototype splits on `\n`, strips the `\r` of CRLF for display (Pi shows the `\r`), and keeps lone CRs.

**Encodings** (all VERIFIED, `tests/test-tools.R` core section):
* UTF-8 BOM: stripped for display/matching, remembered, and re-added on write. `readLines()` keeps it as U+FEFF in a C locale but strips it in a UTF-8 locale (locale-dependent behaviour, `probe` §R1). Only `file(encoding = "UTF-8-BOM")` strips it everywhere.
* UTF-16LE/BE and UTF-32 with BOM: decoded with `iconv(list(raw), from, "UTF-8")`. They are not binary even though they contain NULs, the same as ripgrep's BOM sniffing ("will read the first three bytes … if they correspond to a UTF-16 BOM … transcode", ripgrep GUIDE).
* Invalid UTF-8: if invalid bytes outnumber the valid multibyte characters, the file is legacy 8-bit and decoded as **CP1252** (legacy Windows R scripts; `0x93`/`0x94` → curly quotes), with latin1 as the last resort (maps every byte). Otherwise it is "mostly UTF-8 with stray bytes" and shown with U+FFFD, while `edit` works on the raw bytes so the stray bytes survive exactly.
* **Never `iconv(sub = "Unicode")` or `sub = "c99"`: both hang forever on invalid UTF-8 with the macOS libiconv** (killed by an 8 s watchdog in both C and UTF-8 locales; `sub = "byte"` and `sub = <string>` are fine). VERIFIED (`tmp/iconv_hang.R`).
* `iconv(sub = <UTF-8-marked "�">)` inserts the literal ASCII text `<U+FFFD>` in a C locale (the `sub` string is translated to the native encoding first). The fix is to pass the replacement as unmarked bytes `rawToChar(as.raw(c(0xEF,0xBF,0xBD)))`. VERIFIED (`tmp/dbg2.R`: bytes `3c 55 2b 46 46 46 44 3e` in C vs `ef bf bd` in UTF-8).

**Embedded NUL / binary detection.** `rawToChar()` errors on any NUL ("embedded nul in string"). `readLines()` truncates the line at the NUL and warns ("line N appears to contain an embedded nul"). `readChar(useBytes = TRUE)` truncates the string at the NUL with the warning "truncating string with embedded nuls" (VERIFIED, probe §R1: `readChar(path, 7)` on `ab\0cd\ne` returns `"ab"`). Heuristics: git uses "NUL in the first 8000 bytes"; ripgrep uses "NUL anywhere" ("a file is considered 'binary' if and only if it contains a NUL byte", ripgrep GUIDE). The prototype sniffs 8000 bytes first (cheap) and treats a later NUL as binary through the `rawToChar`/`readChar` failure, which gives ripgrep parity for free. There is one small difference: in its default mode ripgrep stops at the first NUL it sees, but it keeps and prints any match found before that point, with a warning (GUIDE, "Binary data"). gptr skips the whole file.

**Images** (VERIFIED, test section "read"): magic-byte detection is a port of Pi's `mime.ts`, including APNG rejection and JPEG-LS (`FF D8 FF F7`) rejection. A pure-R dimension parser covers PNG (IHDR), GIF (logical screen), JPEG (SOF0–15 scan), WebP (VP8/VP8L/VP8X) and BMP (all tested against files written by png/jpeg/magick). When the image is a provider-native format, fits in 2000×2000 and is < 4.5 MB of base64, it is sent unchanged. Otherwise `magick` (Suggests) takes the first frame, resizes with `"2000x2000>"`, and keeps the smaller of PNG and JPEG q85 → q40. The coordinate note uses Pi's wording. A 3000×2000 noisy 33 MB PNG takes 0.87–1.3 s. Without magick an oversize image is omitted with an actionable note. Current provider limits (fetched 2026-09-29, platform.claude.com vision docs): formats JPEG/PNG/GIF/WebP; max 8000×8000 px; if a request holds more than 20 images, 2000 px per side; 10 MB per image (base64) on the direct API and 5 MB on Bedrock/Vertex; long-edge downscale to 1568 px (standard models) or 2576 px (Claude 4.7+). Pi's 2000 px / 4.5 MB defaults stay safe across all of these. base64 of 5 MB: `base64enc::base64encode` 13 ms, `openssl::base64_encode` 17 ms, `jsonlite::base64_enc` + newline removal 132 ms (it inserts `\n` every **72** characters; corrected by the verifier from "76"). The slow part is the `gsub()` that removes the newlines: in a verifier re-run `jsonlite::base64_enc` alone took 32 ms against 28 ms for base64enc, and with `gsub("[\r\n]", "", …)` it took 96–383 ms depending on load. All three give identical output. VERIFIED.

**Structured data files.** For binary data files the preview is far more useful to an R agent than a "binary file" notice (VERIFIED in tests, timings from `out/bench-readtool.txt`):

| extension | engine (Suggests) | preview content | time (1e6 rows) |
|---|---|---|---|
| `.rds` | base `readRDS` | class, dim/length, `str()`, first 10 rows | 23–36 ms |
| `.RData/.rda` | base `load` into a new env | object names, classes, dims | – |
| `.qs` | `qs::qread(nthreads = 1)` | class + `str()` | – |
| `.parquet` | `arrow::ParquetFileReader` + `read_parquet(as_data_frame = FALSE)$Slice` | rows × cols, schema, first rows | 15–24 ms |
| `.feather/.arrow/.ipc` | `arrow::read_ipc_file(as_data_frame = FALSE)` | same | – |
| `.xlsx/.xls` | `readxl::excel_sheets` + `read_excel(n_max = 10)` | sheet names, first rows | – |

Deserialisation is a code-execution surface. CVE-2024-27322 (R 1.4.0–4.3.x) lets a crafted RDS evaluate a promise during `readRDS`/`load`, and it is fixed in R 4.4.0 (CERT VU#238194, HiddenLayer write-up). The prototype therefore previews `.rds/.RData/.qs` only on R ≥ 4.4.0 and only up to 50 MB. Larger objects belong in the `r` tool (in-memory philosophy, REQ-21). CSV/TSV are text and are shown as text, as in Pi. Other binaries (`.sav/.dta/.fst/.pdf/.h5ad/.zip/.gz`) get a notice with the right loading function.

**Line numbers.** Pi sends none; Claude Code's Read "returns the contents with line numbers" (code.claude.com tools reference). `cat -n` style numbering (6-wide number + TAB) costs **+18.6% bytes (+7.0 bytes/line)** over 1,998 `.ts/.md/.json` files / 474,756 lines of the corpus (VERIFIED; a verifier re-count on the same 1,998 whole files found 500,188 newline-terminated lines and +18.3%, so read the figure as "about 18%"). Numbers also risk leaking into `edit` `oldText`. Recommendation: off by default (Pi parity and fewer tokens) behind option `gptr.read_line_numbers`. The continuation notices already carry offsets.

### 2.3 `write`: atomic replace, line endings, encodings, R pitfalls

**How R renames.** On Unix `file.rename()` calls POSIX `rename()` (`src/main/platform.c`, `do_filerename`), which is atomic within one file system. On Windows it calls `Rwin_wrename()` (VERIFIED from R-devel source `src/gnuwin32/extra.c`, `Rwin_wrename()`, lines 439-451 in trunk as of 2026-09-29):

```c
int Rwin_wrename(const wchar_t *from, const wchar_t *to)
{
    for(int retries = 0; retries < 10; retries++) {
	if (MoveFileExW(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED | MOVEFILE_WRITE_THROUGH))
	    return 0;
	DWORD err = GetLastError();
	if (err != ERROR_SHARING_VIOLATION && err != ERROR_ACCESS_DENIED)
	    return 1;
	Sleep(500);
	R_ProcessEvents();
    }
    return 1;
}
```

(Verifier note: the code is byte-identical in trunk, but in trunk fetched on 2026-09-29 `Rwin_wrename` sits at lines **439-451**, not 535-546. The same loop is present in the R-4-1 to R-4-5 branches, at lines 409, 355, 355, 361 and 439, so it applies to every R version gptr would support.)

Consequences:
* An existing target is replaced on Windows too (`MOVEFILE_REPLACE_EXISTING`). VERIFIED from source.
* A target held open without `FILE_SHARE_DELETE` (Excel does this, antivirus scanners do it briefly) makes each attempt fail. R retries for **up to 5 s** and then returns `FALSE` with a warning. The prototype then falls back to an in-place `writeBin` overwrite. If Excel holds the file, that also fails, with "cannot open file … Permission denied", which is the correct outcome. UNCERTAIN (runtime not testable here); LIKELY from the source.
* `MOVEFILE_COPY_ALLOWED` makes cross-volume moves copy + delete, which is **not atomic**. The temp file must therefore live in the *same directory* as the target. R's docs also warn that renaming from `tempdir()` to user filespace "often fail[s]" across file systems. VERIFIED (docs).

**POSIX side effects measured on macOS** (VERIFIED, `out/probe-*.txt` §F1 and tests):

| situation | plain `file.rename(tmp, target)` | prototype `write_bytes_atomic()` |
|---|---|---|
| target exists | replaced (`TRUE`) | same |
| target is a symlink | **the link is replaced by a regular file**; the real target is unchanged | resolve the link chain first (`Sys.readlink`), write the real target, keep the link |
| target has mode 755 | new file gets **644** | copy mode with `Sys.chmod(tmp, mode, use_umask = FALSE)` before the rename |
| target has a hard link | other name keeps the **old** content | documented; `atomic = FALSE` writes in place if hard links matter |
| rename a dir onto a non-empty dir | `FALSE` | n/a |
| temp file left behind on error | – | `on.exit(unlink(tmp))` |

The write timing cost is negligible: 24.8 MB via `writeBin` direct 10–18 ms, atomic 13–18 ms, `writeLines(useBytes = TRUE)` 11–13 ms, `cat` 12–16 ms, `writeChar(eos = NULL)` 74–84 ms. VERIFIED.

**R output functions and encodings** (VERIFIED, `out/probe-C.txt` vs `out/probe-UTF8.txt` §W1, string `café` marked UTF-8):

| call | C locale bytes | UTF-8 locale bytes |
|---|---|---|
| `writeLines(x, path)` | `63 61 66 3c 55 2b 30 30 45 39 3e 0a` = `caf<U+00E9>\n` | `63 61 66 c3 a9 0a` |
| `writeLines(x, path, useBytes = TRUE)` | `63 61 66 c3 a9 0a` | same |
| `cat(x, file = path)` | `caf<U+00E9>` | `c3 a9` bytes |
| `file(path, "w", encoding = "UTF-8")` + `writeLines` | `caf<U+00E9>\n` | correct |
| `file(path, "w", encoding = "latin1")` + CJK text | silently `<U+4E2D><U+6587>` | warning "invalid char string in output conversion" |
| `writeBin(charToRaw(x), file(path, "wb"))` | `63 61 66 c3 a9` | same |

R's docs: "Normally (when false) character strings with marked encodings are converted to the current encoding before being passed to the connection", and on Windows text-mode connections convert the separator to CRLF. Also `writeLines()` always appends `sep`, so it cannot write a file without a final newline, and `readLines()` + `writeLines()` loses CRLF, the BOM and the final-newline state. **Rule: tools read and write only through raw vectors on binary connections (`"rb"`/`"wb"`).**

**Policy implemented in `gptr_write()`:**
* `content` is written **verbatim** (no trailing-newline insertion or removal), as in Pi.
* `eol = "keep"` (default): if the target exists and is CRLF-dominant, bare LF in `content` becomes CRLF. New files are written as given. `"asis"`, `"lf"` and `"crlf"` are explicit overrides. (Pi writes verbatim; models send LF, so without this a Windows CRLF file would silently become LF and produce a whole-file git diff.)
* `encoding = "keep"`: an existing CP1252/latin1/UTF-16 file stays in its encoding, and its UTF-8 BOM is kept. Text that cannot be represented raises `Text contains characters that cannot be represented in the file's encoding (CP1252).` **before** the file is touched (tested: bytes unchanged).
* The parent directory is created recursively, symlinks are written through, and a workspace guard runs (see §2.8).

### 2.4 `edit`: exact matching, uniqueness, `replaceAll`, EOL/BOM/encoding preservation, fuzzy fallback, diffs

**Algorithm (`apply_edits()`, VERIFIED by 21 edit assertions):**
1. Read raw bytes and refuse binaries. Decode: BOM, UTF-8, CP1252/latin1/UTF-16. For *lossy* UTF-8 (stray invalid bytes) the raw bytes are kept as an unmarked string and every operation uses `useBytes = TRUE`, so invalid bytes outside the edit survive.
2. Split on `\n` only (JS semantics). `has_cr` marks the lines whose ending is CRLF. `base` = lines without that `\r`, joined by `\n` (the LF view the model sees). Lone CRs stay (Pi turns them into LF).
3. Normalise each `oldText`/`newText` with CRLF→LF. An empty `oldText` is an error (Pi message).
4. Exact search: `gregexpr(old, base, fixed = TRUE, useBytes = TRUE)` gives all non-overlapping occurrences (0-based byte offsets). This is locale independent.
5. If any edit has zero exact matches and `fuzzy = TRUE`: `space` = `fuzzy_normalize_lines(body)`, line by line so the line structure is unchanged. Each `oldText` is searched raw first and then fuzzy-normalised (Pi `fuzzyFindText`). All edits are then matched in that space (Pi semantics).
6. Occurrences: 0 → "Could not find …"; >1 without `replaceAll` → "Found N occurrences … or set replaceAll = true." (gptr counts **in the space where matching happened**; Pi always counts in fuzzy space, see §2.1). With `replaceAll`, every occurrence is replaced.
7. Sort the spans and reject overlaps ("edits[i] and edits[j] overlap …", 0-based indices as in Pi).
8. Apply:
   * *exact path*: map base offsets to original offsets by adding 1 byte for every CRLF newline strictly before the offset (`findInterval` on the newline positions). Splice on the raw bytes. `newText` gets the file's dominant EOL (Pi's `detectLineEnding`: first ending wins). **Every byte outside the spans is unchanged, including mixed endings.**
   * *fuzzy path*: port of Pi's `applyReplacementsPreservingUnchangedLines`. Untouched lines keep their original bytes and endings; touched line groups are rewritten from the normalised view.
9. "No changes made …" if the result is identical. Re-encode to the original encoding and BOM, then write atomically.
10. Return the Pi message plus a **unified diff (truncated to 4 KB)** so the model can verify its change. Pi hides the diff from the model. Whether Claude Code's Edit returns a snippet is UNCERTAIN, because the Claude Code tools reference (fetched 2026-09-29) does not describe the Edit result. The display diff and the full patch go to `details`.

Tested round-trips (bytes compared exactly): mixed `one\r\ntwo\nthree\r\nfour\n` with an edit of the last two lines gives `one\r\ntwo\n3\r\n4\n`; BOM + CRLF with a multi-line LF `oldText`; a CP1252 file edited with UTF-8 text stays CP1252; a UTF-8 file with a stray `0xFF` keeps the `0xFF`; the fuzzy case (curly quotes, em dash, trailing spaces) rewrites only the touched lines, and an untouched line with trailing `"  \t"` is kept.

**Fuzzy-normalisation engine notes.** NFKC comes from `stringi::stri_trans_nfkc`, or `utf8::utf8_normalize(map_compat = TRUE)` (a smaller package, same result on the test input), or is skipped. JS `trimEnd()` corresponds to PCRE `[\h\v\x{FEFF}]+$`. Every Unicode class pattern **must start with `(*UTF)`**: R switches PCRE to UTF mode only when some input is non-ASCII, so `\x{2019}` fails with "character code point value in \x{} or \o{} is too large" on all-ASCII input, in the C locale *and* in `en_US.UTF-8`. VERIFIED (`tmp/pcre_utf.R`).

**Diff engine choice** (`bench/bench-misc.R`, load 10.9, median of 3):

| case | pure R `diff_ops()` | `diffobj::ses` (C) | changed lines (R / diffobj) |
|---|---|---|---|
| 556 lines, 3 edits | 1 ms | 1 ms | 6 / 6 |
| 5k lines, 3 edits | 1 ms | 1 ms | 6 / 6 |
| 200k lines (6.2 MB), 2 edits | 34 ms | 11 ms | 4 / 4 |
| 2k lines, 30% of lines changed (few unique lines) | 147 ms | 34 ms | 1200 / 1200 (uses diffobj fallback when installed; pure R without it: 3994 = gap reported as replaced) |
| 2k vs 2k unrelated random lines | 292 ms | 92 ms | 3998 / 3998 |

* Algorithm: hash lines to integers with `match()`, trim the common prefix/suffix vectorised, anchor on lines unique in both ranges and keep their longest increasing subsequence (`findInterval` patience sort), recurse on the gaps, and run Myers O(ND) on gaps with no anchors. Myers is capped at D = 1000; beyond it `diffobj::ses_dat` is used when installed, otherwise the gap is reported as replaced (still a valid patch). 150 random property tests all produce valid edit scripts; 6/150 are slightly longer than diffobj's minimal script (expected for patience anchoring). VERIFIED (`tmp/t-diff2.R`).
* Two performance bugs were found and fixed while benchmarking, and both are worth recording as R lessons. (1) Growing the backtrack vectors with `c()` inside the loop was O(n²): **72 s** for a 150k-line snake. Recording snakes as ranges fixed it. (2) An element-wise `while` for snakes costs about 0.5 µs per line, but a fully vectorised snake costs about 10 µs per *call*. The hybrid (8 scalar steps, then doubling vectorised blocks) is best for both short and long snakes.
* `diffobj::ses_dat()` gotcha: `id.b` is `NA` on `Match` rows, so matched b-indices must be derived as `cumsum(op != "Delete")` (VERIFIED). Its `max.diffs` default is 50,000.
* `tools::Rdiff()` compares R output files for `R CMD check`. With `useDiff = TRUE` it shells out to an external `diff`. The internal mode is a crude `diff -b`-like line comparison, and it is used only when both files have the same number of lines; otherwise `diff -bw` is called anyway. It is not a diff algorithm for this purpose (R docs `?Rdiff`, checked by the verifier; not used).
* End-to-end `gptr_edit()` on the 6.2 MB / 200k-line file (load 10.9): 2 exact edits 0.94 s, fuzzy fallback 1.18 s, duplicate-error path 0.21 s. The profile is dominated by `strsplit`, `paste0` and `Encoding<-` over 200k lines. Typical source files (< 5k lines) take a few ms.

**Diff output formats** (VERIFIED; unified patches applied with `git apply` in tests):

```text
--- a/f.txt
+++ b/f.txt
@@ -1,8 +1,9 @@
+new first
 line 1
 line 2
 line 3
 line 4
-line 5
+line five
 line 6
 line 7
 line 8
@@ -14,7 +15,6 @@
 line 14
 line 15
 line 16
-line 17
 line 18
 line 19
 line 20
```

GNU conventions: a count of 1 is omitted (`@@ -1 +1 @@`), start = 0 for an empty side, and `\ No newline at end of file` after a side's last line when it lacks one. A change in only the final newline is detected (the last line is keyed with a sentinel). The display diff is Pi's `generateDiffString` format (`+NN`, `-NN`, ` NN`, one ` ...` marker per skipped run including leading/trailing, width from `split("\n")` length):

```text
    ...
  6 l6
  7 l7
  8 l8
  9 l9
-10 l10
+10 ten
 11 l11
 12 l12
 13 l13
 14 l14
    ...
 36 l36
 37 l37
 38 l38
 39 l39
-40 l40
-41 l41
 42 l42
 43 l43
 44 l44
 45 l45
    ...
```
(verbatim from `out/test-UTF8.txt`: edits `l10`→`ten` and deletion of `l40`,`l41` in a 50-line file)

### 2.5 `grep`: engines, reading strategy, regex dialect, ignore rules, output

**Engine benchmark (`bench/bench-grep.R`)**: full scan returning *all* matches over the 2,125-file corpus, 5 interleaved rounds, median ms, en_US.UTF-8, load average 27.9 (final run; an earlier run at load 9 gave the same order with gptr_base 320–666 ms and rg 46–194 ms):

| engine | literal_rare (110 lines) | regex_medium `export (async )?function \w+\(` (1462) | common_word `import` (10061) | no_match | ignorecase `todo\|fixme` (285) | identical to rg |
|---|---|---|---|---|---|---|
| **ripgrep via `system2`, plain output** | 66 | 78 | 166 | 54 | 51 | reference |
| ripgrep `--json` + `jsonlite::stream_in` | 57 | 215 | 1116 | 43 | 68 | yes |
| **gptr base engine** (walk + batch `readChar` + whole-file prefilter + per-line PCRE) | 279 | 383 | 634 | 258 | 390 | **yes, all 5** |
| gptr with stringi (ICU regex) | 356 | 494 | 665 | 318 | 449 | yes |
| naive: per-file `readLines` + `grepl(perl)` | 443 | 512 | 505 | 421 | 513 | yes (no binary check) |
| read all, split all, one `grepl` | 730 | 936 | 784 | 742 | 818 | yes |
| per-file `data.table::fread(sep="\n")` | 740 | 798 | 726 | 716 | 794 | **no** (22 lines missing for `import`). Verifier: this is a benchmark artifact, not an `fread` defect. The missing lines are in the two text files that follow a binary PNG, see §2.2 (b); with warnings muffled there are 0 missing lines |
| per-file `stringi::stri_read_lines` | 18905 | 21741 | 19351 | 20083 | 19548 | yes (errors on NUL files unless caught) |

With the tool default **`limit = 100`** the gptr engine stops early (files are processed in path order in batches of ≤ 256 files / 4 MB): literal_rare 251 ms, regex_medium 92, common_word 116, no_match 265, ignorecase 209. VERIFIED.

**Stage profile of a full scan** (same run): walker 32 ms; `list.files(recursive)` 22 ms; `readBin` of all files 101 ms; 8000-byte NUL sniff 56 ms (full-file NUL scan 70 ms); `rawToChar` + `validUTF8` + mark 87 ms; whole-file prefilter `grepl("(*UTF)(?m)pat", texts, perl = TRUE)` 21 ms (fixed 10 ms; `stri_detect_regex` 93 ms; `stri_detect_fixed` 30 ms); `strsplit` of all texts into 523,575 lines 122 ms; per-line `grepl` PCRE 49 ms, PCRE + `(*UCP)` 49 ms, **TRE (`perl = FALSE`) 283 ms**, `stri_detect_regex` 138 ms, fixed 25 ms. VERIFIED.

What moved the R engine from 0.8–1.4 s to 0.26–0.63 s (each step profiled with `Rprof`):
1. **`readChar(path, size, useBytes = TRUE)` instead of `readBin` + `rawToChar`** (`bench/bench-readfiles.R`, load 11, 2,125 files): readChar 127–131 ms; `file(raw = TRUE)` + readBin 363; `brio::read_file_raw` 396; readBin(path) + rawToChar 404; `brio::read_file` 451; `readLines` 702; `stringi::stri_read_raw` 925. All give identical strings and the same 14 binary files. VERIFIED. The remaining floor is R connection open/close (about 50–100 µs per file under load; `file` + `close.connection` dominate `Rprof`). Only C code could avoid it, and that is not justified at these totals.
2. Vectorise per batch: one `validUTF8`, one `Encoding<-`, one CRLF `gsub` over the files that contain `\r`, one prefilter call, and one `strsplit` of the surviving texts only.
3. **PCRE instead of TRE everywhere.** TRE does not short-circuit anchored patterns: `grepl("^\xef\xbb\xbf", texts, useBytes = TRUE)` took 267 ms with TRE vs 18 ms with `perl = TRUE` over 26 MB, and `^import` took 353 vs 84 ms. VERIFIED (`tmp/bom-grepl.R`).
4. The whole-file prefilter is exact because a line-mode match is always a whole-text match under `(?m)`. It is disabled for `\A \z \Z \G`, leading verbs `(*…)` and `(?s)`, which change meaning (track 01 found the same).

**Regex dialect.** PCRE via `perl = TRUE`, prefixed with **`(*UTF)(*UCP)`**. `(*UTF)` makes `\x{..}` above U+00FF compile on ASCII-only files (`\p{..}` compiles either way; verifier-checked), and `(*UCP)` makes `\w \b \d` Unicode-aware like ripgrep's (cost measured at zero). Case-insensitive: `ignore.case = TRUE` (PCRE caseless in UTF mode). Literal: `fixed = TRUE, useBytes = TRUE`. **Literal + case-insensitive: `\Q…\E` with PCRE**, because `grepl(fixed = TRUE, ignore.case = TRUE)` ignores `ignore.case`. It does warn ("argument 'ignore.case = TRUE' will be ignored"), so the ignore is not silent (track 01 E15 as corrected by its verifier; re-checked here). Invalid patterns become `regex parse error: <PCRE reason> (pattern: …)`, taken from the compile *warning*, not the terse error. PCRE vs ripgrep's Rust regex: PCRE is a superset for look-around and backreferences; minor syntax differences (`\z`, possessive quantifiers) rarely matter for model-written patterns. VERIFIED (tests).

**Binary files and encodings.** NUL anywhere means skip, which is ripgrep's rule. UTF-16/32 with a BOM are decoded and searched (ripgrep parity; tested). CP1252/latin1 files are decoded before matching (tested). The UTF-8 BOM is stripped on the *bytes*: `substring(x, 4)` is wrong in a UTF-8 locale, where the BOM is one character. Files over 20 MB are skipped with a notice (gptr policy; R projects hold big CSVs).

**Ignore rules** (walker, §2.6): `.gitignore`, `.ignore`, `.gptrignore` at every level, ancestors up to the repo root, `.git/info/exclude`, and a default prune list (`.git/`, `node_modules/`, `.Rproj.user/`, `renv/library/`, `renv/staging/`, `renv/sandbox/`, `packrat/lib*/`, `packrat/src/`, `.venv/`, `__pycache__/`, `.ipynb_checkpoints/`, `.quarto/`). They are honoured inside **and outside** git repos (ripgrep needs `--no-require-git` for the latter). A positive `glob` does **not** override ignore rules (it does in ripgrep). `glob` accepts a comma list and `!` exclusions (`"*.R,*.Rmd"`, `"!*.txt"`).

**Output.** `content` (Pi's `path:N: text`, context `path-N- text`) with overlapping context windows merged and `--` between non-adjacent blocks (grep convention; Pi repeats lines); `files` (paths only); `count` (`path:N` plus `Total: X matching lines in Y files`), matching Claude Code's three grep output modes. Sort: `path` (default, deterministic), `mtime` (recent first), `count` (files ranked by number of matching lines, the "relevance" of REQ-08). Lines longer than 500 characters show a **500-character window centred on the first match** (Pi cuts at the start, which hides the match in minified files). Notices use Pi's wording (§3.3).

**ripgrep as an optional accelerator.** `grep_rg()` runs ripgrep (via `processx::run(wd = root)`, falling back to `system2`) with `--no-require-git --hidden --field-match-separator \x1e --path-separator / --max-count limit --max-filesize 20480K` and globs for the default prune list. It then sorts in R and returns the same data frame. On the Pi corpus it returned **identical (file, line, text)** for 4 patterns, and the test suite checks `engine = "rg"` against the base engine. It is worth it only for rare patterns on big trees (73–155 ms vs 229–354 ms); for common patterns with `limit = 100` the R engine is faster (137 ms vs 456 ms), because ripgrep has no global limit. Recommendation: pure R by default, `options(gptr.grep_engine = "rg")` opt-in, never download ripgrep (Pi downloads rg and fd from GitHub, which is not acceptable for a CRAN package). Known differences: Rust regex dialect, per-directory `.gptrignore` not read, raw-byte matching of non-UTF-8 files. VERIFIED.

### 2.6 `find` / `ls`: walker, glob semantics, `.gitignore` completeness

**Discovery strategies (`bench/bench-walk.R`, load 7.6–10.7, median of 5):**

| tree | strategy | ms | files | equals git? |
|---|---|---|---|---|
| Pi monorepo (2,125 files, `.git` present) | `list.files(recursive, all.files)` + regex filter | 24 | 2125 | yes |
| | `rg --files --hidden` | 27 | 2125 | yes |
| | `git ls-files --cached --others --exclude-standard` | 41 | 2125 | reference |
| | **`walk_tree()` pruned BFS, full gitignore semantics** | 46 | 2125 | **yes** |
| | `fs::dir_ls(recurse, all)` + filter | 451 | 2125 | yes |
| synthetic R project (40,419 entries: 401 source + `node_modules/` 24k + `renv/library/` 16k) | **`walk_tree()`** | **5** | 401 | (git does not know gptr's default prune list) |
| | `git ls-files …` | 88 | 16401 | – |
| | `rg --files` | 161 | 16401 | – |
| | `list.files(recursive)` + filter | 575 | 401 | – |
| | `fs::dir_ls(recurse)` + filter | **9136** | 401 | – |

Raw costs on the 40,419-entry tree: `list.files(recursive, all.files)` 537 ms; `list.dirs()` 247 ms; `file.info(extra_cols = FALSE)` 85 ms; `file.mtime` 84 ms; `dir.exists` 80 ms; `Sys.readlink` 54 ms; `fs::dir_info(recurse)` 480 ms; `fs::file_info` 237 ms. VERIFIED.

Conclusions: (1) prune before descending. One `list.files(dir, all.files = TRUE, no.. = TRUE)` per directory, with one vectorised `dir.exists` / `Sys.readlink` / rule evaluation per *level*, costs 46 ms on the Pi repo, and that is the price of exact gitignore semantics. (2) `fs::dir_ls` is 10–100x slower than base R here and brings no benefit. (3) `list.files(recursive = TRUE)` **follows symlinked directories** ("On a POSIX filesystem recursive listings will follow symbolic links to directories", R docs). On a two-node symlink loop it returned 66 entries with `include.dirs = TRUE`; on a loop through a symlinked parent directory it printed 6,764 nested paths (verifier re-run: 6,763). The listing stops at 32 path components, 160 characters here, which is far below the OS path-length limit. This is consistent with the kernel's limit on symlinks per path lookup (ELOOP, 32 on macOS) and is LIKELY that limit (VERIFIED count, `tmp/dbg2.R`; the verifier corrected "stops at the OS path limit"). `walk_tree()` lists links without following them (ripgrep/fd default). With `follow_links = TRUE`, or always on Windows where `Sys.readlink()` returns `""`, it detects cycles by canonical path (`normalizePath`, which resolves junctions on Windows). Tested: the loop gives ≤ 3 entries. VERIFIED (macOS), UNCERTAIN (Windows junctions).

**Glob semantics** (`glob_to_regex()` + `glob_matcher()`; 10 assertions). The semantics follow fd, which Pi's `find` uses:
* A pattern without `/` matches the **basename** at any depth (`*.R` finds `R/utils.R`). A pattern with `/` matches the path relative to the search root (`src/*.R` is anchored; `**/` crosses zero or more directories; a trailing `/**` means everything inside). **Deviation from Pi (verifier-found):** Pi's `find` passes a pattern that contains `/` to fd with `--full-path` and prepends `**/` unless the pattern starts with `/` or `**/` (`core/tools/find.ts:201-214`). So in Pi `src/*.R` also matches `a/b/src/x.R` at any depth. The design lead should decide whether gptr anchors (as the prototype does) or matches Pi.
* `*` and `?` never cross `/`. `[abc]`, `[!a-z]`, `[^a]` and POSIX classes are supported, and negated classes also exclude `/`. `{a,b,{c,d}}` alternation is supported, and an unbalanced `{` is literal (bash behaviour). Backslash escapes the next character, and every other regex metacharacter is escaped.
* Smart case, as in fd: case-insensitive unless the pattern contains an uppercase letter.
* Fast paths: a literal basename becomes `==`; `*.ext` and `**/*.ext` become `endsWith()`. Track 21 measured `endsWith` at 2 ms vs 45 ms for PCRE per 100k paths.
* `utils::glob2rx()` fails on all of these (VERIFIED): `glob2rx("*.R")` = `^.*\.R$` (matches `dir/sub/x.R`); `glob2rx("**/*.R")` = `^.*.*/.*\.R$` (misses `a.R`); `glob2rx("src/*.{R,Rmd}")` = `^src/.*\.\{R,Rmd}$` (literal braces); `glob2rx("[ab]?.R")` = `^\[ab].\.R$` (class escaped); `glob2rx("a+b(1).R")` = `^a+b\(1)\.R$` (`+` unescaped, so `a+b(1).R` does not match itself).

**`.gitignore`: how complete must it be?** Exactly as complete as the git spec (git-scm.com/docs/gitignore, PATTERN FORMAT + PRECEDENCE), apart from the global excludes file. Implemented and verified against git:

| rule (git spec) | implemented | verified by |
|---|---|---|
| blank lines, `#` comments, `\#` escape | yes | synthetic repo (`#hash.txt`) |
| trailing spaces ignored unless `\ ` | yes | `sp\ ace.txt`, `src/deep/tmp.R   ` |
| `!` negation, `\!` literal | yes | `!keep.log`, `!bang.txt` |
| trailing `/` = directories only | yes | `build/` |
| leading or middle `/` anchors to the ignore file's directory | yes | `/doc/frotz/` vs `a/doc/frotz/` |
| `*` `?` `[]` never cross `/` (FNM_PATHNAME) | yes | `star\*.txt` |
| `**/x`, `x/**`, `a/**/b` | yes | `logs/**/b.txt`, `abc/**` |
| trailing backslash = invalid pattern, never matches | yes | unit logic |
| per-directory `.gitignore`, patterns relative to that directory | yes | `src/.gitignore` with `gen/*` `!gen/keep.R`; `nested/inner/.gitignore` |
| ancestor `.gitignore` files up to the repo root apply when walking a subdirectory | yes | `walk_tree(repo/src)` test |
| `$GIT_DIR/info/exclude` | yes | code path |
| last matching pattern wins; deeper files override shallower ones | yes | `build/` + `!build/keep.txt` → git also keeps `build/keep.txt` excluded (parent excluded) |
| "not possible to re-include a file if a parent directory is excluded" | yes (pruning) | same |
| case folding when `core.ignorecase=true` (macOS/Windows clones) | yes (FS probe) | `UPPER.LOG` ignored by `*.log`, as in git (`core.ignorecase=true` on this clone) |
| `core.excludesFile` (global) | **no** (documented gap; could read `$XDG_CONFIG_HOME/git/ignore`) | – |
| nested repositories / submodule boundaries | no (ripgrep stops at nested repos) | – |

Result: the walker's file set equals `git ls-files --others --exclude-standard` on the synthetic repo (24 files, 14 rule kinds) and equals `git ls-files --cached --others --exclude-standard` on the Pi monorepo (2,125 files, 0.05–0.15 s). VERIFIED. Performance: rules are compiled to `literal` (`==` on basename), `suffix` (`endsWith`) or regex. Each rule is evaluated vectorised over all entries of a level, restricted to entries under its base, and the last hit wins.

**`ls`**: `list.files(all.files = TRUE, no.. = TRUE)` + `file.info(extra_cols = FALSE)`, which follows symlinks; entries that cannot be stat-ed (broken links) are dropped as in Pi. Sorting is a case-insensitive radix order (Pi uses locale `localeCompare`; radix is deterministic across platforms). `/` suffix for directories. Optional `long = TRUE` (size and mtime columns) and `sort = natural|mtime|size`.

### 2.7 Sorting (REQ-08)

`bench/bench-misc.R`, 100,000 synthetic paths, load 10.9 (VERIFIED):

| operation | ms |
|---|---|
| `sort(x)` (locale collation) | 354 (1322 under load 45) |
| `order(x, method = "radix")` (C byte order) | 11 |
| `order(tolower(x), x, method = "radix")` (case-insensitive, deterministic) | 66 |
| `stringi::stri_order(x)` (ICU collation) | 88 |
| natural: `order(natural_key(x), method = "radix")` (pure R, vectorised) | 470 |
| natural: `stringi::stri_order(x, opts_collator = stri_opts_collator(numeric = TRUE))` | 202 |
| top-100 newest: `order(-mtime, method = "radix")[1:100]` | 3 |
| top-100 via `sort(partial = 100)` | 1 |
| 2 keys: `order(-size, tolower(path), method = "radix")` on a data.frame | 58 |
| `data.table::setorder(copy(dt), -s, p)` | 36 |

* `sort()` depends on the locale. The same vector sorts `_c.R a.R B.R b10.R b9.R é.R Z.R` in en_US.UTF-8 and `B.R Z.R _c.R a.R b10.R b9.R é.R` under radix (C). In the C locale `sort()` even puts `é.R` first, because it is compared as the escape text `<U+00E9>` (VERIFIED, probe §S1). Tools must use radix so that transcripts and document histories (REQ-24) are reproducible across machines.
* `natural_key()`: split into digit and non-digit runs (one PCRE `strsplit`), left-pad digit runs to 20 digits in one vectorised step, and re-assemble column-wise with `do.call(paste0, …)`. The first version with ``regmatches<-`` took **10 s** per 100k (it loops in R). The key agrees with stringi's numeric collation on the test vector.
* Recommended tool-level sort capabilities: `find(sort = path|name|natural|mtime|size, reverse)`, `ls(sort = name|natural|mtime|size)`, `grep(sort = path|mtime|count)`, plus top-N through `limit`. mtime and size default to descending (newest or largest first). Claude Code's Glob sorts by mtime; Pi's find and grep do not sort at all.

### 2.8 Paths and workspace safety

VERIFIED on macOS (`out/probe-*.txt` §P1, `tests/test-tools.R` paths section):
* `normalizePath("no/such/../file", mustWork = FALSE)` returns `"no/such/../file"` unchanged, and `/tmp/../tmp/./x/../y` is also unchanged. "If an input is not a real path the result is system-dependent" (R docs). So paths are resolved **lexically** first (`path_norm()`: collapse `.`, `..`, `//`; `..` never climbs above `/`, `C:/` or a UNC share `//server/share`).
* `normalizePath()` of an existing path resolves symlinks (`realpath`). On macOS it also returns the **canonical case** for a case-variant spelling: `toupper(tempdir())` becomes the lowercase real path. On Windows it "converts short names … return[s] the canonical case" (docs).
* `path_real()` = realpath of the longest existing ancestor + the remaining components. It is needed for targets that do not exist yet.
* `path_within(p, root)` compares `path_real()` results with a separator boundary (`/w` does not contain `/wX`), case-insensitively when `fs_case_insensitive()` is TRUE. That is always TRUE on Windows; on Unix it is probed by flipping the case of the root's basename, or by a temporary probe file. Tests: a non-existent file inside is inside; a symlink escape, a `..` escape and a prefix-collision path are all refused.
* `path_resolve()` ports Pi's `resolveToCwd`: unicode spaces become space; a leading `@` is stripped; `~` uses **`path.expand()`** (R's notion of home, so the tool agrees with `read.csv("~/x")` in R code; on Windows this is usually `Documents`); `file://` URLs are decoded; on Windows `/c/…`, `/mnt/c/…`, `/cygdrive/c/…` become `C:/…` and drive-relative `C:foo` goes to `normalizePath`. **Corrected by the verifier:** `path.expand("~user/x")` is *not* generally left unchanged. On Unix it expands to that user's home when the user exists (`path.expand("~root/x")` gives `/var/root/x` on macOS; `?path.expand`). It is returned unchanged only for an unknown user, and the original probe used `~nosuchuser`. The prototype still matches Pi, which expands only `~` and `~/` (`utils/paths.ts`), because `path_resolve()` calls `path.expand()` only for `~`, `~/` and `~\` (`01-paths.R:49`). The implementation must keep that guard and never pass other `~` forms to `path.expand()`.
* The macOS screenshot-name fallbacks (U+202F before AM/PM, NFD, U+2019) are ported for `read` (NFD needs stringi).
* `guard_write_path()` is advisory (the R session itself is not a sandbox, D-11). Writes and edits outside the workspace are refused unless `options(gptr.allow_outside_workspace = TRUE)` is set or the permission layer approves.
* Non-UTF-8 Unix locales: a UTF-8-*marked* non-ASCII path fails in `file.exists()` with "unable to translate" (track 01 E4). `os_path()` strips the mark before OS calls, and `list.files()` results are re-marked as UTF-8.

### 2.9 R platform pitfalls (all VERIFIED here, with the guard used)

| # | pitfall | evidence | guard |
|---|---|---|---|
| P1 | `strsplit(x, useBytes = TRUE)` returns **unmarked** strings; in a C locale non-ASCII lines then compare unequal | test "PITFALL verified"; cause of the old run's "MISMATCH" | re-mark with `Encoding<-` (`split_lines_js`) |
| P2 | `strsplit("a\n", "\n")` drops the trailing empty piece, so a window ending on a blank line loses a line | `tmp/dbg-tail` (1999 vs 2000 lines) | `strsplit(paste0(x, "\n"), …)` (JS semantics) |
| P3 | `iconv(sub = "Unicode")` / `"c99"` never returns on invalid UTF-8 (macOS libiconv 1.11) | 8 s watchdog, both locales | only `sub = "byte"` or a byte string |
| P4 | `iconv(sub = <UTF-8-marked string>)` inserts literal `<U+FFFD>` text in a C locale | byte dump | `REPLACEMENT_SUB` as unmarked bytes |
| P5 | PCRE `\x{…}` with a code point above U+00FF fails to compile ("character code point value in \x{} or \o{} is too large") when all inputs are ASCII, in every locale. `\p{…}` compiles fine; this was corrected by the verifier, who re-ran `grepl("\\p{L}", "abc", perl = TRUE)` and got TRUE | `tmp/pcre_utf.R`, verifier `claims1.R` | prefix `(*UTF)` (and `(*UCP)`) |
| P6 | TRE (default engine) scans whole strings even for `^`-anchored patterns: 267 vs 18 ms; per-line 283 vs 49 ms | `tmp/bom-grepl.R`, grep stage profile | always `perl = TRUE` or `fixed = TRUE` |
| P7 | `writeLines`/`cat`/`file(encoding=)` re-encode to the native encoding (C locale: `<U+00E9>`; latin1 target: silent `<U+4E2D>`); text mode adds CRLF on Windows | probe §W1, R docs | raw bytes, `"wb"` connections |
| P8 | `enc2utf8()` on an unmarked valid-UTF-8 string in a C locale mangles it (`caf<c3><a9>`) | probe §R1 | `as_utf8()`: mark if `validUTF8`, convert otherwise |
| P9 | `readLines()`: lone CR = newline; NUL truncates the line with a warning; BOM kept in C, stripped in a UTF-8 locale | probe §R1 | never used by the tools |
| P10 | `readChar(useBytes = TRUE)` truncates at NUL (with a warning): `nchar < size` means binary; `rawToChar` errors | probe §R1 | used deliberately in `read_texts()` |
| P11 | `normalizePath()` leaves non-existent paths unchanged (relative stays relative, `..` kept) | probe §P1 | `path_norm()` + `path_real()` |
| P12 | `file.rename()` onto a symlink replaces the link; onto a hard link breaks it; mode reset to umask; fails on a non-empty dir | probe §F1 | resolve link, `Sys.chmod`, document |
| P13 | `list.files(recursive = TRUE)` follows symlinked dirs and loops | `tmp/dbg2.R` | own BFS walker |
| P14 | `sort()`/default `order()` are locale dependent and slow | probe §S1, bench | `method = "radix"` |
| P15 | vroom ALTREP keeps the file handle open until GC or full materialisation (Windows: blocks delete/rename) | `lsof` probe §V1, vroom#280 | never use ALTREP readers in tools |
| P16 | `stringi::stri_read_lines` errors on NUL. `fread(sep = "\n")` warns or stops on binary and empty files, and a `tryCatch(warning = )` that aborts it makes the *next* `fread()` call warn "Previous fread() session was not cleaned up properly" and return nothing. The original "fails on a plain text file" was this artifact (verifier) | `tmp/dbg-naive.R`, verifier `fr2.R`–`fr4.R` | not used as line readers; if `fread` is ever used, muffle warnings with `withCallingHandlers` instead of aborting |
| P17 | `jsonlite::base64_enc()` inserts `\n` every **72** characters (verifier-corrected from 76) | bench-misc, verifier re-run | `base64enc`/`openssl`, or `gsub` |
| P18 | `utils::glob2rx()` is not a path glob | test | `glob_to_regex()` |
| P19 | ``regmatches<-`` and `c()`-growing loops are O(n)/O(n²) R loops (10 s and 72 s on our sizes) | bench-misc before/after | vectorised rewrites |
| P20 | R connection open/close ~50–100 µs per file, the floor for per-file I/O | `Rprof` of grep | batch; accept |
| P21 | PCRE match-limit overflow (catastrophic backtracking) returns `FALSE` with only a *warning*: silent false negatives | `tmp/claims.R` (1.05 s, warning "match limit exceeded") | capture warnings in the grep engine, add a notice (open item, §7.1) |

---

## 3. Exact specifications

### 3.1 Constants (prototype values; Pi source where inherited)

| constant | value | origin |
|---|---|---|
| `GPTR_MAX_LINES` | 2000 | Pi `DEFAULT_MAX_LINES`, `truncate.ts:11` |
| `GPTR_MAX_BYTES` | 51200 (50 KB) | Pi `DEFAULT_MAX_BYTES`, `truncate.ts:12` |
| `GPTR_GREP_MAX_LINE` | 500 characters | Pi `GREP_MAX_LINE_LENGTH`, `truncate.ts:13` |
| `GPTR_GREP_LIMIT` | 100 matching lines | Pi `grep.ts:41` |
| `GPTR_FIND_LIMIT` | 1000 | Pi `find.ts:41` |
| `GPTR_LS_LIMIT` | 500 | Pi `ls.ts:23` |
| `GPTR_BINARY_SNIFF` | 8000 bytes (plus NUL-anywhere via read failure) | git heuristic; ripgrep rule |
| `GPTR_BIG_FILE` | 16 MiB (in-memory vs streaming read) | this track (memory of `b == 0x0A`) |
| streaming chunk | 8 MiB (prototype) | track 21 measured 1–4 MiB chunks best (534 ms / 200 MB) and 16 MiB ~20% slower; 8 MiB was not tuned here, so 4 MiB is the safer production value |
| grep batch | ≤ 256 files or 4 MiB | this track (early termination) |
| grep max file size | 20 MiB (skipped with notice) | gptr policy |
| `GPTR_IMAGE_MAX_EDGE` | 2000 px | Pi `image-resize-core.ts:25`; Anthropic > 20-image limit |
| `GPTR_IMAGE_MAX_B64` | 4.5 MiB base64 | Pi `image-resize-core.ts:21-22` (below the 5 MB Bedrock/Vertex limit) |
| `GPTR_PREVIEW_MAX_DESERIALIZE` | 50 MiB and R ≥ 4.4.0 | CVE-2024-27322 |
| Myers cost cap | D ≤ 1000 per gap | this track |
| edit diff in result | ≤ 4000 bytes | this track |

### 3.2 Model-facing JSON schemas (proposal)

`read` and `write` keep Pi's schemas byte-identical (track 01 §3.2–3.3), with one description sentence added. `edit`, `grep`, `find` and `ls` extend Pi's schemas with **optional** fields only, so models trained on Pi- or Claude-Code-style tools keep working.

```json
{ "name": "read",
  "description": "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. Binary data files (.rds, .RData, .qs, .parquet, .feather, .xlsx) are summarised. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
  "parameters": { "type": "object", "required": ["path"], "properties": {
    "path":   { "type": "string", "description": "Path to the file to read (relative or absolute)" },
    "offset": { "type": "number", "description": "Line number to start reading from (1-indexed)" },
    "limit":  { "type": "number", "description": "Maximum number of lines to read" } } } }
```

```json
{ "name": "write",
  "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories. An existing file keeps its line endings and text encoding.",
  "parameters": { "type": "object", "required": ["path", "content"], "properties": {
    "path":    { "type": "string", "description": "Path to the file to write (relative or absolute)" },
    "content": { "type": "string", "description": "Content to write to the file" } } } }
```

```json
{ "name": "edit",
  "description": "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file, unless replaceAll is true. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes. Returns a unified diff of the change.",
  "parameters": { "type": "object", "required": ["path", "edits"], "properties": {
    "path":  { "type": "string", "description": "Path to the file to edit (relative or absolute)" },
    "edits": { "type": "array", "description": "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead.",
      "items": { "type": "object", "required": ["oldText", "newText"], "properties": {
        "oldText":    { "type": "string",  "description": "Exact text for one targeted replacement. It must be unique in the original file (unless replaceAll is true) and must not overlap with any other edits[].oldText in the same call." },
        "newText":    { "type": "string",  "description": "Replacement text for this targeted edit." },
        "replaceAll": { "type": "boolean", "description": "Replace every occurrence of oldText (default: false)" } } } } } } }
```

```json
{ "name": "grep",
  "description": "Search file contents for a pattern (Perl-compatible regex or literal). Returns matching lines with file paths and line numbers, sorted by path. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars around the match.",
  "parameters": { "type": "object", "required": ["pattern"], "properties": {
    "pattern":    { "type": "string",  "description": "Search pattern (Perl-compatible regex or literal string)" },
    "path":       { "type": "string",  "description": "Directory or file to search (default: current directory)" },
    "glob":       { "type": "string",  "description": "Filter files by glob pattern, e.g. '*.R', '**/*.qmd' or '*.R,*.Rmd'; prefix with ! to exclude" },
    "ignoreCase": { "type": "boolean", "description": "Case-insensitive search (default: false)" },
    "literal":    { "type": "boolean", "description": "Treat pattern as literal string instead of regex (default: false)" },
    "context":    { "type": "number",  "description": "Number of lines to show before and after each match (default: 0)" },
    "limit":      { "type": "number",  "description": "Maximum number of matches to return (default: 100)" },
    "output":     { "type": "string",  "enum": ["content", "files", "count"], "description": "content: matching lines (default); files: file paths only; count: matching lines per file" },
    "sort":       { "type": "string",  "enum": ["path", "mtime", "count"], "description": "File order: path (default), mtime (recently modified first) or count (most matches first)" } } } }
```

```json
{ "name": "find",
  "description": "Search for files by glob pattern. Returns matching paths relative to the search directory; directories end with '/'. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).",
  "parameters": { "type": "object", "required": ["pattern"], "properties": {
    "pattern": { "type": "string",  "description": "Glob pattern to match files, e.g. '*.R', '**/*.csv', or 'R/**/*.R'" },
    "path":    { "type": "string",  "description": "Directory to search in (default: current directory)" },
    "limit":   { "type": "number",  "description": "Maximum number of results (default: 1000)" },
    "sort":    { "type": "string",  "enum": ["path", "mtime", "size", "name", "natural"], "description": "Result order: path (default), mtime (newest first), size (largest first), name, natural (file2 before file10)" },
    "reverse": { "type": "boolean", "description": "Reverse the sort order (default: false)" },
    "type":    { "type": "string",  "enum": ["any", "file", "dir"], "description": "Only files, only directories, or both (default: any)" } } } }
```

```json
{ "name": "ls",
  "description": "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).",
  "parameters": { "type": "object", "properties": {
    "path":  { "type": "string",  "description": "Directory to list (default: current directory)" },
    "limit": { "type": "number",  "description": "Maximum number of entries to return (default: 500)" },
    "long":  { "type": "boolean", "description": "Show size and modification time (default: false)" },
    "sort":  { "type": "string",  "enum": ["name", "natural", "mtime", "size"], "description": "Order (default: name)" } } } }
```

Argument parsing: `jsonlite::fromJSON(txt, simplifyVector = FALSE)`, and wrap `required`/`enum` in `I()` when serialising schemas (track 01 §4.2). The `edit` adapter must accept `edits` as a JSON **string**, a single object, or legacy top-level `oldText/newText` (Pi `prepareEditArguments`, `edit.ts:103-134`; implemented in `normalize_edit_args()` and tested).

### 3.3 Verbatim result texts produced by the prototype

| tool | text | Pi-identical? |
|---|---|---|
| read | `[Showing lines %d-%d of %d. Use offset=%d to continue.]` | yes |
| read | `[Showing lines %d-%d of %d (50.0KB limit). Use offset=%d to continue.]` | yes |
| read | `[%d more lines in file. Use offset=%d to continue.]` | yes |
| read (error) | `Offset %d is beyond end of file (%d lines total)` | yes |
| read | `[Line %d is %s; showing its first 50.0KB. Use the R tool (e.g. substr()) to see the rest.]` | new (Pi points at `sed`) |
| read | `[File is empty: <path>]` | new (Claude Code has a similar notice) |
| read | `[Binary file: <path> (<size>). Not shown as text. Load it with the R tool, e.g. readRDS().]` | new |
| read | `[Decoded from CP1252]`, `[File is not valid UTF-8; invalid bytes shown as U+FFFD]` | new |
| read (image) | `Read image file [image/png]` then optional `[Image: original 3000x1000, displayed at 2000x667. Multiply coordinates by 1.50 to map to original image.]` | yes |
| read (image) | `[Image omitted: could not be resized below the inline image size limit.]` / `[Image omitted: <mime> is <size>, WxH px; install the 'magick' package to let gptr resize/convert it.]` | first yes, second new |
| read (error) | `File not found: <path>`, `Is a directory: <path>. Use the ls tool to list it.`, `Permission denied: <path>` | new wording (Pi surfaces Node errno text) |
| write | `Successfully wrote <n> bytes to <path>` | Pi: `Successfully wrote to <path>` |
| write/edit (error) | `Refusing to write outside the workspace: <real> (workspace: <real>). Symlinks are resolved before this check.` | new |
| write/edit (error) | `Text contains characters that cannot be represented in the file's encoding (CP1252).` | new |
| edit | `Successfully replaced <n> block(s) in <path>.` + ` (matched after whitespace/quote/dash normalisation)` + blank line + unified diff | first part yes |
| edit (errors) | `Could not find the exact text in <path>. The old text must match exactly including all whitespace and newlines.` / `Could not find edits[<i>] in <path>. The oldText must match exactly including all whitespace and newlines.` | yes |
| edit (errors) | `Found <n> occurrences of the text in <path>. The text must be unique. Please provide more context to make it unique, or set replaceAll = true.` (multi: `… of edits[<i>] … Each oldText must be unique …`) | yes + suffix |
| edit (errors) | `edits[<i>] and edits[<j>] overlap in <path>. Merge them into one edit or target disjoint regions.`; `oldText must not be empty in <path>.`; `No changes made to <path>. The replacement produced identical content. …`; `Could not edit file: <path>. Error code: ENOENT.`; `Could not edit file: <path>. It is a binary file.` | yes (last new) |
| grep | `No matches found`; `%d matches limit reached. Use limit=%d for more, or refine pattern`; `Some lines truncated to 500 chars. Use read tool to see full lines`; `50.0KB limit reached` (joined with `. ` inside one `[...]`) | yes |
| grep | `%d file(s) larger than 20MB skipped`; `%d files limit reached. Use limit=%d for more`; count footer `Total: %d matching lines in %d files`; `regex parse error: <reason> (pattern: <p>)` | new |
| find | `No files found matching pattern`; `%d results limit reached. Use limit=%d for more, or refine pattern` | yes |
| ls | `(empty directory)`; `%d entries limit reached. Use limit=%d for more`; `Path not found: <abs>`; `Not a directory: <abs>` | yes |

Line formats: grep match `path:LINE: text`, context `path-LINE- text`, block separator `--`; find directories end in `/`, `sort = mtime|size` appends `  (2026-09-29 19:03)` / `  (4.9KB)`; ls long `%8s  %Y-%m-%d %H:%M  name`.

### 3.4 Glob and ignore semantics (normative for the implementation)

* Glob → PCRE: `**` as a whole segment: leading `**/` = `(?:[^/]*/)*`, middle `/**/` = `/(?:[^/]*/)*`, trailing `/**` = `/(?:.*)?`, alone = `.*`; `*` = `[^/]*`; `?` = `[^/]`; `[!…]`/`[^…]` = `[^/…]`; `{a,b}` = `(?:a|b)` (only when balanced); `\x` = literal x; metacharacters `. + ( ) | ^ $ { } [ ] \ * ?` escaped. Anchored `^…$`.
* `find`: no `/` in the pattern means match the basename; with `/`, match the root-relative path; smart case.
* `grep glob`: comma-separated globs (commas inside `{}` preserved), `!glob` excludes, same basename/path rule.
* `.gitignore` compile: strip `\r`; skip blanks and `#`; strip unescaped trailing spaces; skip a pattern ending in a lone `\`; `!` negates; `\#`, `\!` literal; trailing `/` means dir-only; any remaining `/` means anchored (leading `/` removed); `*.ext` → suffix rule, no metacharacters → literal rule, else regex without braces.
* Evaluation per directory level: for every rule in order (defaults, `info/exclude`, ancestor files from the root down, then files discovered while walking), candidates = entries under the rule's base (dir-only rules: directories only), target = basename (unanchored) or base-relative path (anchored); a hit sets ignored = !negated. Excluded directories are never listed. Case folding is on when the file system is case-insensitive.

---

## 4. Recommended design for gptr

### 4.1 Two layers: R-native functions + thin tool adapters

Every capability should exist as an **exported R function that returns R data** (usable by the user and by the agent from the `r` tool, REQ-10, D-03), plus an **internal tool adapter** that turns that data into Pi-format text for the model. The prototype shows both shapes: `find_files()` / `grep_files()` return data frames, while `gptr_find()` / `gptr_grep()` produce the tool text. For the package I recommend renaming them as follows (D-28 prefix rule):

| exported R API (returns data, prints like the tool) | internal adapter (args list → `gptr_tool_result`) | prototype function |
|---|---|---|
| `gptr_read(path, offset = NULL, limit = NULL, line_numbers = getOption("gptr.read_line_numbers", FALSE))` → character vector of class `gptr_lines` with attributes `path, offset, total, encoding, bom, crlf` | `tool_read(args, ctx)` | `read_text_lines()` + `gptr_read()` |
| `gptr_write(path, content, eol = c("keep","asis","lf","crlf"), encoding = c("keep","UTF-8"), atomic = TRUE, workspace = gptr_workspace())` → invisible list(path, bytes, created, method) | `tool_write(args, ctx)` | `gptr_write()` |
| `gptr_edit(path, edits, dry_run = FALSE, fuzzy = TRUE, workspace = gptr_workspace())` → invisible `gptr_patch` (unified diff string; `print` shows it) | `tool_edit(args, ctx)` | `apply_edits()` + `gptr_edit()` |
| `gptr_grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, literal = FALSE, context = 0L, limit = 100L, sort = c("path","mtime","count"), engine = getOption("gptr.grep_engine", "base"))` → data.frame of class `gptr_matches` (`file, line, text`) | `tool_grep(args, ctx)` | `grep_files()` + `format_grep()` |
| `gptr_find(pattern = "**", path = ".", type = c("any","file","dir"), sort = "path", decreasing = NULL, limit = 1000L, hidden = TRUE, gitignore = TRUE, max_depth = Inf)` → data.frame of class `gptr_files` (`path, is_dir, is_link, size, mtime`) | `tool_find(args, ctx)` | `find_files()` |
| `gptr_ls(path = ".", all = TRUE, sort = "name", long = FALSE)` → `gptr_files` | `tool_ls(args, ctx)` | `gptr_ls()` |

Internal helpers (names from the prototype, all unexported): `decode_raw()`, `encode_text()`, `sniff_bom()`, `is_binary_raw()`, `split_lines_js()`, `split_lines_count()`, `truncate_lines_head()`, `truncate_line()`, `format_size()`, `as_utf8()`, `os_path()`, `path_norm()`, `path_resolve()`, `path_resolve_read()`, `path_real()`, `path_within()`, `fs_case_insensitive()`, `guard_write_path()`, `resolve_link_target()`, `write_bytes_atomic()`, `file_conventions()`, `line_window_stream()`, `read_text_lines()`, `detect_image_mime()`, `image_dims()`, `process_image()`, `base64_raw()`, `preview_data_file()`, `fuzzy_normalize_lines()`, `apply_edits()`, `diff_match()`, `diff_ops()`, `unified_diff()`, `display_diff()`, `glob_to_regex()`, `glob_matcher()`, `compile_ignore()`, `eval_ignore()`, `walk_tree()`, `read_texts()`, `grep_engine()`, `grep_rg()`, `natural_key()`, `order_entries()`.

Context passed to adapters (compatible with track 01 §4.2): `ctx$cwd` (evaluated at call time), `ctx$workspace` (for the write guard), `ctx$images` (does the model accept images?), `ctx$check_abort` (called between batches in walk/grep), `ctx$permission` (mode, REQ-37).

### 4.2 Options (all have safe defaults)

`gptr.read_line_numbers` (FALSE), `gptr.allow_outside_workspace` (FALSE), `gptr.grep_engine` ("base" | "stringi" | "rg"), `gptr.big_file` (16 MiB), `gptr.grep_max_file_size` (20 MiB), `gptr.preview_max_deserialize` (50 MiB), `gptr.default_ignore` (the prune list), `gptr.image_max_edge` (2000), `gptr.image_max_b64` (4.5 MiB; raise to about 9.5 MiB for direct-Anthropic-only use).

### 4.3 Algorithms (summary; code in §5)

* **read**: resolve (Pi fallbacks) → stat → sniff 64 KB → image (magic) → binary (NUL in 8000 bytes) → structured preview or notice → text window (≤ 16 MiB in-memory index with a whole-file encoding decision; otherwise a streaming 8 MiB index with a 64 KB encoding sample) → head truncation (2000 lines / 50 KB, never partial lines; a giant first line is shown partially at a UTF-8 boundary) → Pi notices.
* **write**: resolve → reject directories → resolve symlink chain → workspace guard → conventions of the existing file (encoding, BOM, dominant EOL) → EOL conversion → **encode before touching the file** → temp file in the same dir → `writeBin` on `"wb"` → verify size → copy mode → `file.rename` → fallback in-place write.
* **edit**: §2.4 steps 1–10; diff computed on the LF view.
* **diff**: §2.4; `diff_ops()` returns `data.frame(op, a, b)`, from which `unified_diff()` (git-appliable) and `display_diff()` (Pi format) are rendered.
* **walk**: BFS, one `list.files()` per directory, vectorised `dir.exists`/`Sys.readlink` per level, rules evaluated per level, prune ignored directories, never follow links (or follow with a canonical-path cycle guard), `max_entries` 500k and `max_depth` caps, `check_abort()` per level.
* **grep**: walk → glob filter → stats → skip > 20 MiB → sort → batches (≤ 256 files / 4 MiB) → `readChar` batch read (binary = truncated) → UTF-16/32 and CP1252 fixes → CRLF→LF → whole-file prefilter → split survivors → per-line match → early stop at `limit` → format (context merge, centred long-line window) → 50 KB head truncation → notices.
* **find/ls**: walk (find) or `list.files` (ls) → type filter → glob matcher (fast paths) → stats only if sorting needs them → radix `order_entries()` → limit → format.
* **Stale-file protection** (recommended, not prototyped): record `(size, mtime, tools::md5sum)` when `read` returns a file; `edit`/`write` compare and either warn in the result text ("file changed on disk since you read it") or require a re-read. Claude Code used to refuse such edits. Since v2.1.208 it allows an edit to an unread or changed file when `old_string` matches the current content exactly and unambiguously, and it notes in the result that the file carries other changes (Claude Code tools reference, fetched 2026-09-29). `tools::md5sum` is base R, so this needs no new dependency.
* **Concurrency**: tool calls run sequentially inside the R session, so Pi's per-file mutation queue is unnecessary in-process. Sub-agents in separate R processes (REQ-33, D-12) that edit the same tree should take a `filelock::lock(paste0(realpath, ".gptr-lock"))` around read-modify-write (Suggests), or the design must accept last-writer-wins.

### 4.4 Package choices

| package | role | recommendation | evidence |
|---|---|---|---|
| base `tools`, `utils` | `file_ext`, `md5sum`, `URLdecode`, `capture.output`, `head` | Imports (base) | – |
| `jsonlite` | JSON-string `edits`, fallback base64 | Imports (already required by providers) | – |
| `stringi` | NFKC (fuzzy edit), NFD (macOS screenshot names), optional ICU grep engine | **Suggests** | fuzzy works without NFKC (tests pass with it blocked); stringi grep is not faster (§2.5) |
| `utf8` | NFKC fallback when stringi is absent | Suggests (tiny) | same output on the test input |
| `base64enc` / `openssl` | base64 of images | Suggests (openssl is installed with httr2 anyway) | 13 / 17 ms vs 132 ms for jsonlite + newline removal. jsonlite alone is comparable in speed but wraps at 72 characters |
| `magick` | resize/convert images (BMP, oversize) | Suggests | only way to resize in R; system library |
| `arrow`, `qs`, `qs2`, `readxl` | data-file previews in `read` | Suggests | 15–36 ms previews |
| `diffobj` | Myers accelerator for pathological gaps | Suggests (optional) | 3–4x faster only on heavy rewrites |
| `processx` | `rg` accelerator (no shell quoting, `wd =`) | Suggests (other tracks may promote it to Imports) | `system2` fallback tested |
| `filelock` | cross-process write serialisation | Suggests | – |
| `fs` | – | **not needed** | `dir_ls` 10–100x slower; base covers everything else |
| `vroom`, `readr`, `brio`, `data.table` | – | **not needed for file tools** | no total line count, open-handle issue (vroom), warnings/early stop on binary and empty files (`fread`; its apparent text-file failures were a benchmark artifact, §2.2), marginal sort gains |
| Rcpp | – | **not needed** | largest R cost is a 0.26–0.63 s full-scan grep of 26 MB (0.09–0.27 s at the default limit); the only C-worthy hot spot would be multi-file reading (connection overhead), a small absolute gain; track 21 owns the decision |

`Depends: R (>= 4.1.0)` is LIKELY to work for these tools. UNCERTAIN: the prototype ran only on R 4.4.3; a scan found no R ≥ 4.2-only functions, and it defines its own `%||%`, which base R gained only in 4.4.0. **R ≥ 4.4.0 is needed for the deserialising previews** (checked at run time), and R ≥ 4.2 is strongly preferable on Windows (UTF-8 native encoding).

### 4.5 Deliberate deviations from Pi

| topic | Pi | gptr | why |
|---|---|---|---|
| grep/find engine | ripgrep/fd binaries (downloaded) | pure R (optional `rg`) | REQ-01/07/08, CRAN |
| result order | unordered (parallel) | sorted (path; optional mtime/size/natural/count) | reproducible transcripts, REQ-08 |
| `.gitignore` outside git repos | find yes, grep no | always | consistency |
| `.git/`, `node_modules/`, `renv/library/`… | searched (grep `--hidden`) | always pruned | tokens and speed (5 ms vs 575 ms) |
| positive grep glob vs ignore rules | glob overrides | ignore wins | simpler, safer |
| `find` pattern containing `/` | `**/` prepended: matches at any depth | anchored to the search root (prototype) | open decision (verifier-found; §2.6) |
| regex dialect | Rust regex | PCRE `(*UTF)(*UCP)` | base R; superset |
| grep context | overlapping blocks repeated | merged, `--` separators | fewer tokens |
| grep output modes | content only | content / files / count | Claude Code parity, tokens |
| long grep lines | first 500 chars | 500 chars centred on the match | minified files |
| read `\r` of CRLF | shown | stripped | cleaner; edit normalises anyway |
| read giant first line | "use sed" notice | first 50 KB shown | no bash in gptr |
| read binary non-images | decoded as garbage | notice or structured preview | R data files |
| read non-UTF-8 text | U+FFFD garbage; edit corrupts the file | CP1252/latin1/UTF-16 decoded and re-encoded | legacy Windows R scripts |
| write | verbatim UTF-8, not atomic | atomic, keeps EOL/encoding/BOM/mode/symlink, workspace guard | safety, Windows repos |
| edit EOL handling | whole file rewritten with the first EOL | bytes outside the spans untouched | clean diffs on mixed files |
| edit uniqueness count | fuzzy space always | space where it matched | fewer false duplicates |
| edit `replaceAll` | no | yes | Claude Code parity |
| edit result text | message only | message + unified diff (≤ 4 KB) | self-verification |
| line numbers | none | optional (off) | tokens (+18.6%) |
| mutation queue | in-process queue | sequential calls; filelock across processes | R single-threaded |

---

## 5. Verified R prototypes

Everything below was executed on this machine with `Rscript --vanilla` (R 4.4.3). Source layout in `work/11/`:

| file | lines | content |
|---|---|---|
| `proto/00-core.R` | 195 | constants, UTF-8 helpers, raw I/O, BOM/binary sniffing, decode/encode, JS line splitting, truncation, result objects |
| `proto/01-paths.R` | 122 | lexical normalisation, resolution, realpath of partial paths, case-insensitivity probe, workspace guard, Pi read-path fallbacks |
| `proto/10-read.R` | 282 | image sniff/dims/resize/base64, structured previews, streaming line index, window reader, `gptr_read()` |
| `proto/20-write.R` | 83 | symlink resolution, atomic write, file conventions, `gptr_write()` |
| `proto/30-diff.R` | 185 | LIS, snake, capped Myers, patience `diff_match()`, `diff_ops()`, `unified_diff()`, `display_diff()` |
| `proto/31-edit.R` | 169 | fuzzy normalisation, byte-level splicing, `apply_edits()`, argument normalisation, `gptr_edit()` |
| `proto/40-walk.R` | 198 | glob→regex, glob matcher, gitignore compiler/evaluator, git root, `walk_tree()` |
| `proto/50-search.R` | 341 | natural sort, `order_entries()`, find/ls, batch reader, grep engine, rg accelerator, formatter, `gptr_grep()` |
| `tests/test-tools.R` | 287 | 159 assertions incl. git and ripgrep oracles |
| `tests/probe-platform.R` | 72 | platform behaviour probes (§2.3, §2.8, §2.9) |
| `bench/*.R` | ~380 | benchmarks quoted in §2 |

### 5.1 Test results

Commands: `Rscript --vanilla tests/test-tools.R` (C locale), the same with `LANG=LC_ALL=en_US.UTF-8`, and the same with `GPTR_BLOCK=stringi,utf8,magick,base64enc,openssl,arrow,qs,png,jpeg,diffobj,processx` (every optional package made unavailable through `has_pkg()`). `VERBOSE=1` prints each passing assertion.

| configuration | result |
|---|---|
| C locale, all optional packages | **159 passed, 0 failed** |
| en_US.UTF-8, all optional packages | **159 passed, 0 failed** |
| C locale, optional packages blocked | **144 passed, 0 failed** (the 15 missing assertions need png/jpeg/magick/arrow/qs/stringi; the fuzzy edit, rg engine via `system2`, and everything else still pass) |

The full verbose log of the UTF-8 run is in §5.3.

### 5.2 Additional executed checks (outputs quoted in §2)

* `tmp/t-diff.R`: 7 diff cases (scattered edits, final newline removed or added, from/to empty, repetitive lines, 400 random lines). Every patch from `unified_diff()` applies with `git apply` and reproduces the new text.
* `tmp/t-diff2.R` / `tmp/t-diff3.R`: 150 random property tests (all edit scripts valid, 6 non-minimal) and timings with and without the diffobj accelerator.
* `tmp/t-rg.R`: ripgrep accelerator vs R engine on 4 patterns (identical file/line/text).
* `tmp/iconv_hang.R`, `tmp/pcre_utf.R`, `tmp/bom-grepl.R`, `tmp/dbg2.R`, `tmp/dbg-naive.R`, `tmp/chk-repo.R`: pitfall reproductions P3–P6, P13, P16 and the gitignore oracle listing (git keeps `.gitignore, a.R, a/doc/frotz/y.txt, keep.log, logs/2026/a.txt, nested/drop.csv, nested/inner/.gitignore, nested/inner/ok.R, src/.gitignore, src/deep/.hidden, src/gen/keep.R` and excludes the other 14, exactly as the walker does).

### 5.3 Test log (en_US.UTF-8, `VERBOSE=1`), verbatim `out/test-UTF8.txt`

```text
R 4.4.3 | LC_CTYPE=en_US.UTF-8 | UTF-8 locale: TRUE | blocked: (none)
== core: decoding, splitting, truncation
  ok: valid UTF-8 
  ok: UTF-8 text 
  ok: UTF-8 BOM stripped and remembered 
  ok: UTF-16LE with BOM decoded 
  ok: UTF-16 with BOM is not binary 
  ok: CP1252 fallback (smart quotes 0x93/0x94) 
  ok: mostly-UTF-8 with a stray byte stays UTF-8 (lossy) 
  ok: NUL => binary 
  ok: decode refuses NUL 
  ok: JS split keeps trailing empty piece 
  ok: JS split of empty string 
  ok: Pi splitLinesForCounting 
  ok: PITFALL verified: strsplit(useBytes=TRUE) drops the UTF-8 mark 
  ok: split_lines_js re-marks 
  ok: detect_eol CRLF first 
  ok: detect_eol LF first (non-ASCII prefix) 
  ok: truncate by lines 
  ok: truncate by bytes (100B/line -> 512 lines) 
  ok: first line exceeds byte limit 
  ok: truncate_line 
  ok: truncate_line centred on match 
  ok: format_size 
== paths
  ok: lexical norm unix 
  ok: lexical norm drive letter 
  ok: cannot climb above drive root 
  ok: UNC share is a root 
  ok: relative .. kept 
  ok: resolve relative 
  ok: strip @ prefix (Pi) 
  ok: unicode space normalised 
  ok: file:// URL 
  ok: ~ expansion (R's HOME) 
[1] TRUE
  ok: inside workspace (non-existent file) 
  ok: symlink escape detected 
  ok: .. escape detected 
  ok: prefix must end at a separator 
   file system case-insensitive here: TRUE 
  ok: case-insensitive containment 
  ok: guard refuses symlink escape 
== read
  ok: read: line-limit notice (Pi text) 
  ok: read: offset to end, no notice 
  ok: read: offset+limit notice 
  ok: read: offset beyond EOF (Pi text) 
  ok: read: cat -n line numbers 
  ok: read: byte-limit notice 
  ok: read: giant first line shown partially at a UTF-8 boundary 
  ok: read: CR of CRLF not shown 
  ok: read: CP1252 decoded with note 
NULL
  ok: read: empty file notice 
  ok: read: binary notice 
  ok: read: directory error 
  ok: read: missing file 
  ok: read: streaming window == in-memory window (middle) 
  ok: read: streaming window == in-memory window (tail) 
  ok: read: PNG -> image block 
  ok: read: base64 round-trips 
  ok: read: base64 has no newlines 
  ok: image_dims PNG 
  ok: image_dims JPEG 
  ok: sniff JPEG 
  ok: image_dims GIF 
  ok: sniff WebP 
  ok: image_dims WebP 
  ok: read: BMP converted to PNG via magick 
  ok: read: large image resized with coordinate note 
  ok: read: .rds preview 
  ok: read: .RData object listing 
  ok: read: parquet preview 
  ok: read: qs preview 
== write
  ok: write: creates parent dirs 
  ok: write: message 
  ok: write: no temp file left 
  ok: write: atomic rename used 
  ok: write: permission bits preserved across rename 
[1] TRUE
  ok: write: writes THROUGH a symlink and keeps it 
Successfully wrote 9 bytes to crlf.R
  ok: write: eol='keep' preserves CRLF 
  ok: write: eol='asis' writes verbatim 
  ok: write: CP1252 file stays CP1252 
  ok: write: unrepresentable char refused 
  ok: write: refused write left file untouched 
Successfully wrote 11 bytes to bom.csv
  ok: write: UTF-8 BOM kept 
  ok: write: outside workspace refused 
[1] TRUE
  ok: write: NOTE atomic rename breaks hard links (hard2 keeps old content) 
== edit
  ok: edit: success message 
  ok: edit: unified patch 
  ok: edit: not found (Pi text) 
  ok: edit: not found multi (0-based index) 
  ok: edit: duplicate count 
  ok: edit: replaceAll 
  ok: edit: multi-edit against original 
  ok: edit: overlap error 
  ok: edit: empty oldText 
  ok: edit: no change 
  ok: edit: dry_run leaves file untouched 
  ok: edit: edits given as JSON string 
  ok: edit: legacy oldText/newText arguments 
  ok: edit: mixed EOL preserved outside span; new text uses dominant EOL 
  ok: edit: BOM + CRLF preserved, multi-line oldText with LF matched 
  ok: edit: CP1252 file round-trips 
  ok: edit: stray invalid byte preserved (byte-level edit) 
  ok: edit: fuzzy fallback reported 
  ok: edit: fuzzy rewrites touched lines only; untouched trailing whitespace kept 
  ok: edit: fuzzy can be disabled 
  ok: edit: patch applies with git apply 
    ...
  6 l6
  7 l7
  8 l8
  9 l9
-10 l10
+10 ten
 11 l11
 12 l12
 13 l13
 14 l14
    ...
 36 l36
 37 l37
 38 l38
 39 l39
-40 l40
-41 l41
 42 l42
 43 l43
 44 l44
 45 l45
    ... 
== glob / gitignore / walk
  ok: glob *.R matches basename at any depth (fd) 
  ok: glob with / is anchored; * does not cross / 
  ok: glob **/ matches zero or more dirs 
  ok: glob a/**/b 
  ok: glob braces 
  ok: glob class 
  ok: glob negated class 
  ok: glob escapes regex metachars 
  ok: glob trailing /** 
  ok: glob unbalanced brace is literal 
  ok: PITFALL verified: glob2rx crosses '/', lacks braces/classes, leaves '+' unescaped 
  ok: gitignore: walker file set == git ls-files --others --exclude-standard 
   git core.ignorecase=true
  ok: gitignore: rules of ancestor .gitignore apply when walking a subdirectory 
[1] TRUE
  ok: walk: symlinked dir listed, not followed 
  ok: walk: follow_links = TRUE terminates on a loop (cycle guard by canonical path) 
   list.files(recursive=TRUE) on the symlink loop returned 66 entries (follows links)
  ok: walk: Pi monorepo file set == git ls-files (2125 files, 0.08s) 
== find / ls / sort
  ok: find: *.R, case-insensitive path order, hidden included 
  ok: find: natural sort f2 < f10 
  ok: find: mtime sort newest first 
  ok: find: size sort largest first 
  ok: find: path pattern 
  ok: find: directories get / 
  ok: find: limit notice 
  ok: find: no results 
  ok: ls: Pi format 
  ok: ls: limit notice 
  ok: ls: long format has sizes 
  ok: natural_key order 
  ok: stringi numeric collation agrees 
== grep
  ok: grep: basic, binary + ignored skipped, sorted 
  ok: grep: UTF-8 BOM stripped (^ anchors at first char) 
  ok: grep: UTF-16LE file searched (ripgrep BOM sniffing parity) 
  ok: grep: CP1252 file decoded before matching 
  ok: grep: ignoreCase 
  ok: grep: literal (and CRLF stripped) 
  ok: grep: literal + ignoreCase via \Q..\E 
  ok: grep: $ anchors work on CRLF files 
  ok: grep: UTF-8 pattern 
  ok: grep: context merged with -- separators 
  ok: grep: limit notice 
  ok: grep: files output 
  ok: grep: count output 
  ok: grep: files ranked by match count (relevance) 
  ok: grep: long line window keeps the match visible 
  ok: grep: invalid regex message 
  ok: grep: \x{..} escapes accepted (UTF mode forced) 
  ok: grep: \w is Unicode-aware (UCP), like ripgrep 
  ok: grep: no matches 
  ok: grep: single file path 
  ok: grep: negative glob 
  ok: grep: stringi engine == base engine 
  ok: grep: optional ripgrep engine == base engine 
  ok: grep oracle vs ripgrep: 'DEFAULT_MAX_BYTES' (110 lines) 
  ok: grep oracle vs ripgrep: 'export (async )?function \w+\(' (1462 lines) 
  ok: grep oracle vs ripgrep: 'TODO|FIXME' (57 lines) 
  ok: grep oracle vs ripgrep: '^import .* from "\./' (1434 lines) 

RESULT: 159 passed, 0 failed
```

The C-locale log (`out/test-C.txt`) is identical except for the header line and the walk timing; the base-only log (`out/test-base.txt`) lacks the 15 optional-package assertions listed in §5.1.

### 5.4 Benchmark and probe logs (verbatim; loader chatter from readr/lsof removed)

#### `bench/bench-grep.R` (final run, load ~28)

```text
load average: 20:03  up 7 days, 16:31, 1 user, load averages: 27.87 27.33 25.41 
corpus: 2125 files, 25.9 MB (walker, gitignore-aware)

median ms over 5 interleaved rounds (full scan, all matches):
                  impl common_word ignorecase_alt literal_rare no_match
               rg_json        1116             68           57       43
            rg_system2         166             51           66       54
             gptr_base         634            390          279      258
          gptr_stringi         665            449          356      318
       naive_readLines         505            513          443      421
   all_lines_one_grepl         784            818          730      742
           fread_lines         726            794          740      716
 naive_stri_read_lines       19351          19548        18905    20083
 regex_medium
          215
           78
          383
          494
          512
          936
          798
        21741

matching lines per pattern (ripgrep reference): literal_rare=110, regex_medium=1462, common_word=10061, no_match=0, ignorecase_alt=285 
identical (file,line) vectors vs ripgrep / size of set difference:
                  impl ndiff.common_word ndiff.ignorecase_alt
   all_lines_one_grepl                 0                    0
           fread_lines                22                    0
             gptr_base                 0                    0
          gptr_stringi                 0                    0
       naive_readLines                 0                    0
 naive_stri_read_lines                 0                    0
               rg_json                 0                    0
            rg_system2                 0                    0
 ndiff.literal_rare ndiff.no_match ndiff.regex_medium
                  0              0                  0
                  0              0                  1
                  0              0                  0
                  0              0                  0
                  0              0                  0
                  0              0                  0
                  0              0                  0
                  0              0                  0
                  impl  same
   all_lines_one_grepl  TRUE
           fread_lines FALSE
             gptr_base  TRUE
          gptr_stringi  TRUE
       naive_readLines FALSE
 naive_stri_read_lines FALSE
               rg_json  TRUE
            rg_system2  TRUE

limit = 100 (tool default), gptr_base median ms:
  literal_rare        251
  regex_medium         92
  common_word         116
  no_match            265
  ignorecase_alt      209

stage profile, full scan (median of 5 ):
  walk_tree (gitignore-aware)            32 ms
  list.files(recursive, all.files)       22 ms
  readBin all files                     101 ms
  binary sniff (8000 B)                  56 ms
  full NUL scan (any(b == 0))            70 ms
  rawToChar + validUTF8 + mark           87 ms
  whole-file grepl prefilter (perl)      21 ms
  whole-file grepl fixed, useBytes       10 ms
  whole-file stri_detect_regex           93 ms
  whole-file stri_detect_fixed           30 ms
  strsplit all into lines               122 ms
  per-line grepl perl (523575 lines)      49 ms
  per-line grepl perl + (*UCP)           49 ms
  per-line grepl TRE (perl = FALSE)     283 ms
  per-line stri_detect_regex            138 ms
  per-line grepl fixed useBytes          25 ms
```

#### `bench/bench-readfiles.R`

```text
load average: 19:56  up 7 days, 16:23, 1 user, load averages: 11.04 10.90 21.34 
2125 files, 25.9 MB
                   impl  ms n_binary same_as_readBin
      readChar_file_raw 127       14            TRUE
 readChar_path_useBytes 131       14            TRUE
  file_raw_TRUE_readBin 363       14            TRUE
     brio_read_file_raw 396       14            TRUE
 readBin_path_rawToChar 404       14            TRUE
         brio_read_file 451       14            TRUE
         readLines_path 702        0           FALSE
       stringi_read_raw 925       14            TRUE

note: readLines_path drops the final newline / normalises CRLF, so its strings differ by design

rawToChar per file (2111 calls)          50 ms
rawToChar once on 22.3 MB               44 ms
validUTF8 on all texts                   10 ms
Encoding(txt) <- 'UTF-8'                 28 ms
```

#### `bench/bench-walk.R`

```text
load average: 19:54  up 7 days, 16:22, 1 user, load averages: 7.62 10.69 22.18 
                tree                       impl   ms files same_as_git
         pi_monorepo list.files_rec_then_filter   24  2125        TRUE
         pi_monorepo                   rg_files   27  2125        TRUE
         pi_monorepo               git_ls_files   41  2125        TRUE
         pi_monorepo           walk_tree_pruned   46  2125        TRUE
         pi_monorepo      fs_dir_ls_then_filter  451  2125        TRUE
 synthetic_R_project           walk_tree_pruned    5   401       FALSE
 synthetic_R_project               git_ls_files   88 16401        TRUE
 synthetic_R_project                   rg_files  161 16401        TRUE
 synthetic_R_project list.files_rec_then_filter  575   401       FALSE
 synthetic_R_project      fs_dir_ls_then_filter 9136   401       FALSE

raw listing cost of everything under the synthetic tree (incl. ignored dirs):
  list.files(recursive=TRUE, all.files=TRUE): 40419 entries     537 ms
  list.dirs(recursive=TRUE):                  3236 dirs        247 ms
  file.info(40419 paths, extra_cols = FALSE)          85 ms
  file.info(40419 paths, extra_cols = TRUE)           86 ms
  file.mtime(40419 paths)                             84 ms
  dir.exists(40419 paths)                             80 ms
  Sys.readlink(40419 paths)                           54 ms
  fs::dir_info(recurse=TRUE)                     480 ms
  fs::file_info(40419 paths)                         237 ms
```

#### `bench/bench-misc.R`

```text
load average: 19:57  up 7 days, 16:24, 1 user, load averages: 10.86 10.91 20.46 

### sorting 100,000 paths
  sort(x) (locale collation)                     354.0 ms
  order(x, method='radix')  (C byte order)         11.0 ms
  order(tolower(x), x, method='radix')             66.0 ms
  stringi::stri_order(x)  (ICU collation)          88.0 ms
  natural: order(natural_key(x), method='radix')  470.0 ms
  natural: stri_order(numeric = TRUE)             202.0 ms
  top-100 newest: order(-mtime)[1:100]              3.0 ms
  top-100 newest: -sort(-mtime, partial=100)        1.0 ms
  base order(-s, tolower(p)) 2 keys                58.0 ms
  data.table setorder(copy(dt), -s, p)             36.0 ms
  sort() in this locale:       _c.R a.R B.R b10.R b9.R Z.R 
  order(tolower, radix):       _c.R a.R B.R b10.R b9.R Z.R 
  natural_key radix:           _c.R a.R B.R b9.R b10.R Z.R 

### diff: pure-R (prefix/suffix trim + patience anchors + Myers) vs diffobj::ses (C Myers)
  556 lines, 3 edits                             pure R     1.0 ms (    6 +/- lines) | diffobj::ses     1.0 ms (    6 +/- lines)
  5k lines, 3 edits                              pure R     1.0 ms (    6 +/- lines) | diffobj::ses     1.0 ms (    6 +/- lines)
  200k lines, 2 edits (edit tool on a 5MB file)  pure R    34.0 ms (    4 +/- lines) | diffobj::ses    11.0 ms (    4 +/- lines)
  2k lines, 30% lines changed                    pure R   147.0 ms ( 1200 +/- lines) | diffobj::ses    34.0 ms ( 1200 +/- lines)
  2k vs 2k unrelated random lines                pure R   292.0 ms ( 3998 +/- lines) | diffobj::ses    92.0 ms ( 3998 +/- lines)
  unified_diff() on the 200k-line pair              159.0 ms
  display_diff() on the 200k-line pair              450.0 ms

### edit end-to-end on a 5.4 MB / 200k-line file (2 edits, atomic write, diff)
  file: 6.2 MB
  1 edit (unique needle, 29x repeated file => 29 occurrences => duplicate error path)   206.0 ms
  2 exact edits                                     938.0 ms
  1 edit needing the fuzzy fallback                1181.0 ms
  profile (self time, top 8):
                 self.time self.pct total.time total.pct
"strsplit"           0.120    15.19      0.175     22.15
"paste0"             0.110    13.92      0.155     19.62
"Encoding<-"         0.110    13.92      0.110     13.92
"gc"                 0.090    11.39      0.090     11.39
"splice_bytes"       0.035     4.43      0.070      8.86
"diff_match"         0.030     3.80      0.095     12.03
"rawToChar"          0.030     3.80      0.045      5.70
"unique.default"     0.030     3.80      0.030      3.80

### base64 of a 5 MB image payload
  base64enc::base64encode        13.0 ms
  openssl::base64_encode         17.0 ms
  jsonlite::base64_enc + gsub   132.0 ms
  identical outputs: TRUE TRUE 
  jsonlite::base64_enc contains newlines: TRUE 

### writing 50 MB of text
  text: 24.8 MB
  writeBin(charToRaw(x), file(,'wb'))  direct    18.0 ms
  write_bytes_atomic (tmp + rename)              18.0 ms
  writeLines(x, f, useBytes = TRUE)              13.0 ms
  cat(x, file = f)                               16.0 ms
  writeChar(x, con, eos = NULL, useBytes=TRUE)   84.0 ms

### counting lines of the 148 MB file
  readBin 8MB chunks + sum(b == 0x0A)      657 ms  -> 4222460
  length(readLines(f))                    2494 ms
  vroom::vroom_lines(altrep=TRUE) length    432 ms
  data.table::fread(sep='\n') nrow        1147 ms
  system2('wc', '-l')                      277 ms
```

#### `bench/bench-readtool.R` (second run, load ~15; first run: 15 MB 79–94 ms, 148 MB 533–896 ms)

```text
load average: 19:58  up 7 days, 16:25, 1 user, load averages: 14.57 11.65 20.23 
gptr_read, 14.8 MB file (in-memory path):   head   149 ms | offset=200000   136 ms | offset=420000 limit=100   128 ms
gptr_read, 148 MB file (streaming index):   head   730 ms | offset=2000000   663 ms | offset=4200000 limit=100   781 ms
gptr_read, 556-line source file:              3.0 ms (line numbers:   3.0 ms)
gptr_read preview: parquet 1e6 rows    24 ms | rds 1e6 rows    36 ms
gptr_read image: 3000x2000 noisy PNG (33.2 MB) -> resize+encode  1316 ms
line numbers on 1998 files / 474756 lines: 17.0 MB -> 20.2 MB (+18.6%, +7.0 bytes/line)
```

#### `bench/bench-read2.R` (second run at load ~27; the load-11.6 run is the table in §2.2)

```text
R 4 4.3  locale: en_US.UTF-8 
big.ts: 14774596 bytes; big10.ts: 147745960 bytes

               impl 15MB head 15MB middle 15MB tail 148MB head 148MB tail
      readBin_index        70         110        86        731       1063
          split_all       188         213       180       3017       2008
         stream_8MB       100         125       117       1022        644
     readLines_skip         6         524      1289         10      19716
      readLines_all       247         233       762       3689       3462
               scan         2          54       243          2       2313
 stringi_read_lines       262         203       429       2843       2745
              fread         2          10        40          3        299
        vroom_lines         3          10        41          2        312
   vroom_altrep_len        43          30        52        422        453
             brio_n         1          39       179          1       1256
              readr         2          11        35          3        959

all windows identical to readLines reference: TRUE ; failures: 0 
total-line counts correct where provided: TRUE 
```

#### `tests/probe-platform.R` in the C locale

```text
R 4.4.3 | aarch64-apple-darwin20 | LC_CTYPE=C | UTF-8 locale=FALSE

[W1] writing a UTF-8 string
  writeLines(x, path)                 ->                     63 61 66 3c 55 2b 30 30 45 39 3e 0a
  writeLines(x, path, useBytes = TRUE) ->                    63 61 66 c3 a9 0a
  cat(x, file = path)                 ->                     63 61 66 3c 55 2b 30 30 45 39 3e
  writeBin(charToRaw(x))              ->                     63 61 66 c3 a9
  file(encoding='UTF-8') + writeLines  ->                    63 61 66 3c 55 2b 30 30 45 39 3e 0a
  file(encoding='latin1') + writeLines(CJK)                  3c 55 2b 34 45 32 44 3e 3c 55 2b 36 35 38 37 3e 0a

[R1] reading
  readLines('a\rb\nc') (lone CR)                             c("a", "b", "c")
  JS/Pi split('\n') equivalent                               c("a\rb", "c")
    warning: line 1 appears to contain an embedded nul 
    warning: incomplete final line found on 'nul.txt' 
  readLines on 'ab\0cd\ne'                                   c("ab", "e")
    warning: truncating string with embedded nuls 
  readChar(path, 7, useBytes = TRUE) (nchar bytes)           "ab" | 2   
  rawToChar on the same bytes                                ERROR: embedded nul in string: 'ab\0cd\ne'
  readLines on UTF-8 BOM file: first char code               65279
  readLines(file(encoding='UTF-8-BOM')) first char           120
Warning message:
In readLines(file("u8.txt", encoding = "UTF-8")) :
  incomplete final line found on 'u8.txt'
  readLines(file(encoding='UTF-8')) -> bytes / Encoding      99 97 102 195 169 | UTF-8            
Warning message:
In readLines("u8.txt", encoding = "UTF-8") :
  incomplete final line found on 'u8.txt'
  readLines(path, encoding='UTF-8')  -> bytes / Encoding     99 97 102 195 169 | UTF-8            
  enc2utf8(<unmarked valid UTF-8>) bytes                     99 97 102 60 99 51 62 60 97 57 62

[P1] paths
  normalizePath('no/such/../file', mustWork=FALSE)           no/such/../file
  normalizePath('/tmp/../tmp/./x/../y', mustWork=FALSE)      /tmp/../tmp/./x/../y
  normalizePath(tempdir())                                   /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpOegniP
  normalizePath(toupper(tempdir()))  (case-insens. FS)       /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpOegniP
  file.exists(toupper(tempdir()))                            TRUE
  path.expand('~/x'), path.expand('~user/x')                 /Users/wanjun/x | ~nosuchuser/x  
[1] TRUE
  normalizePath('lnk/t.txt') resolves the symlink            /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpOegniP/probe11d9c6021968d/real/t.txt
  Sys.readlink(c('lnk','real','missing'))                    c("/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T//RtmpOegniP/probe11d9c6021968d/real",  | "", NA)                                                                                   
  basename/dirname of 'a/b/' and 'C:/x/y'                    b    | a    | y    | C:/x

[F1] file.rename semantics (POSIX rename(2))
  rename over existing target                                TRUE | new 
[1] TRUE
[1] TRUE
  rename onto a symlink: link still a link? target content   FALSE  | target
[1] TRUE
[1] TRUE
  rename onto a hard link: other name keeps old content      h
[1] TRUE
  rename onto a 755 file: resulting mode                     644
  rename dir onto a NON-empty dir                            FALSE
  file.rename(tempfile in tempdir(), cwd) same volume?       TRUE

[S1] sorting is locale dependent
  sort(v)                                                    <U+00E9>.R | B.R        | Z.R        | _c.R       | a.R        | b10.R      | b9.R      
  v[order(v, method = 'radix')]                              B.R        | Z.R        | _c.R       | a.R        | b10.R      | b9.R       | <U+00E9>.R

[V1] vroom ALTREP keeps the file open (Windows: blocks rename/delete of that file)
  after vroom_lines(altrep=TRUE): open handles on v.txt      2
  after rm(x); gc()                                          0
  after vroom_lines(altrep=FALSE)                            0
  after data.table::fread (mmap)                             0
```

#### `tests/probe-platform.R` in en_US.UTF-8

```text
R 4.4.3 | aarch64-apple-darwin20 | LC_CTYPE=en_US.UTF-8 | UTF-8 locale=TRUE

[W1] writing a UTF-8 string
  writeLines(x, path)                 ->                     63 61 66 c3 a9 0a
  writeLines(x, path, useBytes = TRUE) ->                    63 61 66 c3 a9 0a
  cat(x, file = path)                 ->                     63 61 66 c3 a9
  writeBin(charToRaw(x))              ->                     63 61 66 c3 a9
  file(encoding='UTF-8') + writeLines  ->                    63 61 66 c3 a9 0a
  file(encoding='latin1') + writeLines(CJK)                  WARNING: invalid char string in output conversion

[R1] reading
  readLines('a\rb\nc') (lone CR)                             c("a", "b", "c")
  JS/Pi split('\n') equivalent                               c("a\rb", "c")
    warning: line 1 appears to contain an embedded nul 
    warning: incomplete final line found on 'nul.txt' 
  readLines on 'ab\0cd\ne'                                   c("ab", "e")
    warning: truncating string with embedded nuls 
  readChar(path, 7, useBytes = TRUE) (nchar bytes)           "ab" | 2   
  rawToChar on the same bytes                                ERROR: embedded nul in string: 'ab\0cd\ne'
  readLines on UTF-8 BOM file: first char code               120
  readLines(file(encoding='UTF-8-BOM')) first char           120
Warning message:
In readLines(file("u8.txt", encoding = "UTF-8")) :
  incomplete final line found on 'u8.txt'
  readLines(file(encoding='UTF-8')) -> bytes / Encoding      99 97 102 195 169 | UTF-8            
Warning message:
In readLines("u8.txt", encoding = "UTF-8") :
  incomplete final line found on 'u8.txt'
  readLines(path, encoding='UTF-8')  -> bytes / Encoding     99 97 102 195 169 | UTF-8            
  enc2utf8(<unmarked valid UTF-8>) bytes                     99 97 102 195 169

[P1] paths
  normalizePath('no/such/../file', mustWork=FALSE)           no/such/../file
  normalizePath('/tmp/../tmp/./x/../y', mustWork=FALSE)      /tmp/../tmp/./x/../y
  normalizePath(tempdir())                                   /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpGOYYCd
  normalizePath(toupper(tempdir()))  (case-insens. FS)       /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpGOYYCd
  file.exists(toupper(tempdir()))                            TRUE
  path.expand('~/x'), path.expand('~user/x')                 /Users/wanjun/x | ~nosuchuser/x  
[1] TRUE
  normalizePath('lnk/t.txt') resolves the symlink            /private/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T/RtmpGOYYCd/probe11db1528d7e27/real/t.txt
  Sys.readlink(c('lnk','real','missing'))                    c("/var/folders/83/pgprwt8s3w5_cgrt3rz3x21w0000gn/T//RtmpGOYYCd/probe11db1528d7e27/real",  | "", NA)                                                                                   
  basename/dirname of 'a/b/' and 'C:/x/y'                    b    | a    | y    | C:/x

[F1] file.rename semantics (POSIX rename(2))
  rename over existing target                                TRUE | new 
[1] TRUE
[1] TRUE
  rename onto a symlink: link still a link? target content   FALSE  | target
[1] TRUE
[1] TRUE
  rename onto a hard link: other name keeps old content      h
[1] TRUE
  rename onto a 755 file: resulting mode                     644
  rename dir onto a NON-empty dir                            FALSE
  file.rename(tempfile in tempdir(), cwd) same volume?       TRUE

[S1] sorting is locale dependent
  sort(v)                                                    _c.R  | a.R   | B.R   | b10.R | b9.R  | é.R   | Z.R  
  v[order(v, method = 'radix')]                              B.R   | Z.R   | _c.R  | a.R   | b10.R | b9.R  | é.R  

[V1] vroom ALTREP keeps the file open (Windows: blocks rename/delete of that file)
  after vroom_lines(altrep=TRUE): open handles on v.txt      2
  after rm(x); gc()                                          0
  after vroom_lines(altrep=FALSE)                            0
  after data.table::fread (mmap)                             0
```

### 5.5 Prototype source (verbatim, ASCII-only)

Load order: `for (f in sort(list.files("proto", "\\.R$", full.names = TRUE))) source(f)`.

#### `proto/00-core.R`

```r
# gptr file tools prototype (track 11) -- core utilities. Base R only; ASCII-only source.
# Optional accelerators are always guarded by requireNamespace().

GPTR_MAX_LINES      <- 2000L          # Pi DEFAULT_MAX_LINES (truncate.ts:11)
GPTR_MAX_BYTES      <- 51200L         # Pi DEFAULT_MAX_BYTES = 50 * 1024 (truncate.ts:12)
GPTR_GREP_MAX_LINE  <- 500L           # Pi GREP_MAX_LINE_LENGTH (truncate.ts:13)
GPTR_GREP_LIMIT     <- 100L           # Pi grep DEFAULT_LIMIT (grep.ts:41)
GPTR_FIND_LIMIT     <- 1000L          # Pi find DEFAULT_LIMIT (find.ts:41)
GPTR_LS_LIMIT       <- 500L           # Pi ls DEFAULT_LIMIT (ls.ts:23)
GPTR_BINARY_SNIFF   <- 8000L          # git's FIRST_FEW_BYTES heuristic
GPTR_BIG_FILE       <- 16 * 1024^2    # read: above this size use the streaming line index (bounded memory)

`%||%` <- function(a, b) if (is.null(a)) b else a

has_pkg <- function(pkg) {
  blocked <- strsplit(Sys.getenv("GPTR_BLOCK", ""), ",", fixed = TRUE)[[1L]]
  !(pkg %in% blocked) && requireNamespace(pkg, quietly = TRUE)
}

# ---- encoding marks ---------------------------------------------------------
u_chr <- function(...) { x <- intToUtf8(c(...)); Encoding(x) <- "UTF-8"; x }
mark_utf8 <- function(x) { Encoding(x) <- "UTF-8"; x }
# Unmarked strings that are valid UTF-8 are taken to BE UTF-8; enc2utf8() would re-encode them
# from the native encoding and corrupt them in a C/CP1252 locale.
as_utf8 <- function(x) {
  x <- as.character(x)
  enc <- Encoding(x)
  lat <- enc == "latin1"
  if (any(lat)) x[lat] <- iconv(x[lat], "latin1", "UTF-8")
  unk <- enc == "unknown" & !validUTF8(x)
  if (any(unk)) x[unk] <- enc2utf8(x[unk])
  mark_utf8(x)
}
nbytes <- function(x) nchar(x, type = "bytes")
os_path <- function(p) {                       # path handed to OS calls
  if (.Platform$OS.type != "windows" && !isTRUE(l10n_info()[["UTF-8"]])) Encoding(p) <- "unknown"
  p
}

format_size <- function(bytes) {
  if (bytes < 1024) sprintf("%dB", as.integer(bytes))
  else if (bytes < 1024^2) sprintf("%.1fKB", bytes / 1024)
  else sprintf("%.1fMB", bytes / 1024^2)
}

# ---- raw file I/O ------------------------------------------------------------
read_raw <- function(path, n = NULL, offset = 0) {
  p <- os_path(path)
  size <- file.size(p)
  if (is.na(size)) stop(sprintf("File not found: %s", path), call. = FALSE)
  if (isTRUE(file.info(p, extra_cols = FALSE)$isdir)) stop(sprintf("Is a directory: %s", path), call. = FALSE)
  con <- file(p, "rb"); on.exit(close(con))
  if (offset > 0) seek(con, offset, rw = "read")
  readBin(con, "raw", n = if (is.null(n)) size - offset else n)
}

# ---- BOM / binary sniffing -----------------------------------------------------
sniff_bom <- function(b) {
  n <- length(b)
  if (n >= 3L && b[1] == as.raw(0xEF) && b[2] == as.raw(0xBB) && b[3] == as.raw(0xBF)) return("UTF-8")
  if (n >= 4L && b[1] == as.raw(0xFF) && b[2] == as.raw(0xFE) && b[3] == as.raw(0) && b[4] == as.raw(0)) return("UTF-32LE")
  if (n >= 4L && b[1] == as.raw(0) && b[2] == as.raw(0) && b[3] == as.raw(0xFE) && b[4] == as.raw(0xFF)) return("UTF-32BE")
  if (n >= 2L && b[1] == as.raw(0xFF) && b[2] == as.raw(0xFE)) return("UTF-16LE")
  if (n >= 2L && b[1] == as.raw(0xFE) && b[2] == as.raw(0xFF)) return("UTF-16BE")
  ""
}
bom_len <- c("UTF-8" = 3L, "UTF-16LE" = 2L, "UTF-16BE" = 2L, "UTF-32LE" = 4L, "UTF-32BE" = 4L)
bom_bytes <- list("UTF-8" = as.raw(c(0xEF, 0xBB, 0xBF)), "UTF-16LE" = as.raw(c(0xFF, 0xFE)),
                  "UTF-16BE" = as.raw(c(0xFE, 0xFF)), "UTF-32LE" = as.raw(c(0xFF, 0xFE, 0, 0)),
                  "UTF-32BE" = as.raw(c(0, 0, 0xFE, 0xFF)))

# git / ripgrep heuristic: a NUL byte means binary (git looks at the first 8000 bytes). UTF-16/32 text
# with a BOM contains NULs by construction and is exempt.
is_binary_raw <- function(b, sniff = GPTR_BINARY_SNIFF) {
  if (nzchar(sniff_bom(b)) && sniff_bom(b) != "UTF-8") return(FALSE)
  n <- min(length(b), sniff)
  n > 0L && any(b[seq_len(n)] == as.raw(0L))
}

# ---- decoding -----------------------------------------------------------------------
# Returns list(text = <one UTF-8-marked string without BOM>, encoding, bom (logical), lossy (logical)).
# Order: BOM -> valid UTF-8 -> caller-supplied fallback (default CP1252, which is what legacy Windows
# R scripts use; latin1 maps every byte so it never fails) -> otherwise UTF-8 with U+FFFD.
# NEVER use iconv(sub = "Unicode") / sub = "c99": it loops forever on invalid UTF-8 input with the
# macOS libiconv (verified R 4.4.3). sub = <string> and sub = "byte" are safe.
REPLACEMENT_CHAR <- u_chr(0xFFFD)
# iconv(sub = <UTF-8-marked string>) re-encodes `sub` to the NATIVE encoding first: in a C locale that
# inserts the literal text "<U+FFFD>" (verified). Pass the replacement as unmarked bytes instead.
REPLACEMENT_SUB <- rawToChar(as.raw(c(0xEF, 0xBF, 0xBD)))
decode_raw <- function(b, fallback = c("CP1252", "latin1")) {
  if (!length(b)) return(list(text = mark_utf8(""), encoding = "UTF-8", bom = FALSE, lossy = FALSE))
  bom <- sniff_bom(b)
  if (nzchar(bom)) {
    body <- b[-seq_len(bom_len[[bom]])]
    if (bom == "UTF-8") b <- body
    else {
      txt <- iconv(list(body), from = bom, to = "UTF-8", sub = REPLACEMENT_SUB)
      return(list(text = mark_utf8(txt), encoding = bom, bom = TRUE, lossy = FALSE))
    }
  }
  if (any(b == as.raw(0L))) stop("embedded NUL: binary data", call. = FALSE)
  txt <- rawToChar(b)
  if (validUTF8(txt)) return(list(text = mark_utf8(txt), encoding = "UTF-8", bom = nzchar(bom), lossy = FALSE))
  # Mostly-UTF-8 text with a few stray bytes stays UTF-8 (lossy display, byte-exact edits).
  n_hi <- sum(b >= as.raw(0x80))
  n_bad <- (nchar(iconv(txt, "UTF-8", "UTF-8", sub = "byte"), "bytes") - length(b)) / 3  # bad byte -> "<xx>"
  # legacy 8-bit if invalid bytes outnumber the (approx. 2-byte) valid UTF-8 characters
  if (!nzchar(bom) && n_bad * 2 > (n_hi - n_bad)) {
    for (enc in fallback) {
      out <- suppressWarnings(iconv(txt, from = enc, to = "UTF-8"))
      if (!is.na(out)) return(list(text = mark_utf8(out), encoding = enc, bom = FALSE, lossy = FALSE))
    }
  }
  list(text = mark_utf8(iconv(txt, "UTF-8", "UTF-8", sub = REPLACEMENT_SUB)), encoding = "UTF-8",
       bom = nzchar(bom), lossy = TRUE)
}

# Encode UTF-8 text for writing. Fails loudly (before the file is touched) if the text cannot be
# represented in the target encoding.
encode_text <- function(text, encoding = "UTF-8", bom = FALSE) {
  text <- as_utf8(text)
  out <- if (identical(encoding, "UTF-8")) charToRaw(text) else {
    r <- iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1L]]
    if (is.null(r)) stop(sprintf("Text contains characters that cannot be represented in the file's encoding (%s).", encoding), call. = FALSE)
    r
  }
  if (isTRUE(bom) && encoding %in% names(bom_bytes)) out <- c(bom_bytes[[encoding]], out)
  out
}

# ---- line splitting --------------------------------------------------------------------
# strsplit(useBytes = TRUE) returns UNMARKED pieces (verified): always re-mark.
# JavaScript "x".split("\n") semantics: "a\n" -> c("a", ""), "" -> "".
split_lines_js <- function(x) {
  out <- strsplit(paste0(x, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]
  if (!length(out)) out <- ""
  mark_utf8(out)
}
# Pi splitLinesForCounting(): "" -> 0 lines; a single trailing "\n" is not an extra line.
split_lines_count <- function(x) {
  if (!nzchar(x)) return(character())
  mark_utf8(strsplit(x, "\n", fixed = TRUE, useBytes = TRUE)[[1L]])
}
detect_eol <- function(x) {                    # Pi detectLineEnding(): first line ending decides
  lf <- regexpr("\n", x, fixed = TRUE, useBytes = TRUE); crlf <- regexpr("\r\n", x, fixed = TRUE, useBytes = TRUE)
  if (lf < 0 || crlf < 0) return("\n")
  if (crlf < lf) "\r\n" else "\n"
}
normalize_lf <- function(x) {
  x <- gsub("\r\n", "\n", x, fixed = TRUE, useBytes = TRUE)
  mark_utf8(gsub("\r", "\n", x, fixed = TRUE, useBytes = TRUE))
}

# ---- truncation (Pi truncate.ts, operating on a vector of lines) -------------------------
truncate_lines_head <- function(lines, max_lines = GPTR_MAX_LINES, max_bytes = GPTR_MAX_BYTES) {
  n <- length(lines)
  lb <- as.numeric(nbytes(lines))
  total_bytes <- sum(lb) + max(0, n - 1)
  if (n <= max_lines && total_bytes <= max_bytes)
    return(list(lines = lines, truncated = FALSE, by = NA_character_, output_lines = n, first_line_exceeds = FALSE))
  if (n && lb[1L] > max_bytes)
    return(list(lines = character(), truncated = TRUE, by = "bytes", output_lines = 0L, first_line_exceeds = TRUE))
  k <- min(n, max_lines)
  cum <- cumsum(lb[seq_len(k)] + c(0, rep(1, k - 1L)))
  fit <- sum(cum <= max_bytes)
  list(lines = lines[seq_len(fit)], truncated = TRUE, by = if (fit < k) "bytes" else "lines",
       output_lines = fit, first_line_exceeds = FALSE)
}

# Vectorised line cap. Pi cuts at the first max_chars characters; with `center` (0-based char offset of
# the match) the window is moved so the match stays visible (useful for minified files).
truncate_line <- function(x, max_chars = GPTR_GREP_MAX_LINE, center = NULL) {
  n <- nchar(x, type = "chars", allowNA = TRUE)
  long <- !is.na(n) & n > max_chars
  if (!any(long)) return(structure(x, truncated = long))
  start <- rep(1L, length(x))
  if (!is.null(center)) {
    c0 <- pmax(0L, as.integer(center))
    start[long] <- pmax(1L, pmin(c0[long] - max_chars %/% 5L, n[long] - max_chars + 1L))
  }
  x[long] <- paste0(ifelse(start[long] > 1L, "...", ""),
                    substr(x[long], start[long], start[long] + max_chars - 1L), "... [truncated]")
  structure(mark_utf8(x), truncated = long)
}

# ---- results ----------------------------------------------------------------------------
tool_text <- function(text, details = NULL, is_error = FALSE) {
  structure(list(content = list(list(type = "text", text = mark_utf8(paste(text, collapse = "\n")))),
                 details = details, isError = is_error), class = "gptr_tool_result")
}
print.gptr_tool_result <- function(x, ...) {
  for (b in x$content) if (b$type == "text") cat(b$text, "\n", sep = "") else cat(sprintf("<%s block: %s, %d base64 chars>\n", b$type, b$mimeType, nchar(b$data)))
  invisible(x)
}
result_text <- function(res) paste(vapply(Filter(function(b) b$type == "text", res$content), `[[`, "", "text"), collapse = "\n")
```

#### `proto/01-paths.R`

```r
# gptr file tools prototype -- paths. All paths returned use "/" separators on every platform.

is_windows <- function() .Platform$OS.type == "windows"

# Absolute: "/x", "C:/x", "C:\x", "//server/share", "\\server\share". ("C:x" is drive-relative on Windows.)
path_is_abs <- function(p) grepl("^([/\\\\]|[A-Za-z]:[/\\\\])", p)

.path_prefix <- function(p) {                      # p already uses "/"
  if (grepl("^[A-Za-z]:/", p)) return(substr(p, 1L, 3L))
  if (grepl("^//[^/]+/[^/]+", p)) return(regmatches(p, regexpr("^//[^/]+/[^/]+/?", p)))   # UNC: //server/share/
  if (startsWith(p, "/")) return("/")
  ""
}

# Lexical normalisation (no file system access), like node's path.resolve(): collapses "//", ".", ".."
# (".." never climbs above the root / drive / UNC share). normalizePath() cannot do this for paths that
# do not exist: it returns them unchanged on Unix (verified).
path_norm <- function(p) {
  p <- gsub("\\", "/", p, fixed = TRUE)
  pre <- .path_prefix(p)
  if (nzchar(pre)) { p <- substring(p, nchar(pre) + 1L); if (!endsWith(pre, "/")) pre <- paste0(pre, "/") }
  segs <- strsplit(p, "/", fixed = TRUE)[[1L]]
  out <- character()
  for (s in segs) {
    if (s == "" || s == ".") next
    if (s == "..") { if (length(out) && out[length(out)] != "..") out <- out[-length(out)] else if (!nzchar(pre)) out <- c(out, ".."); next }
    out <- c(out, s)
  }
  res <- paste0(pre, paste(out, collapse = "/"))
  if (!nzchar(res)) res <- "."
  if (nchar(res) > 1L && endsWith(res, "/") && !grepl("^[A-Za-z]:/$", res)) res <- sub("/+$", "", res)
  mark_utf8(res)
}

# Model-supplied path -> absolute, normalised path (no symlink resolution). Mirrors Pi's resolveToCwd():
# unicode spaces -> " ", strip a leading "@", "~" expansion, file:// URLs, Git-Bash/WSL drive paths on Windows.
path_resolve <- function(path, cwd = getwd()) {
  p <- as_utf8(path)
  sp <- c(0xA0L, 0x2000L:0x200AL, 0x202FL, 0x205FL, 0x3000L)
  cp <- utf8ToInt(p)
  if (!anyNA(cp) && any(cp %in% sp)) { cp[cp %in% sp] <- 32L; p <- u_chr(cp) }
  if (startsWith(p, "@")) p <- substring(p, 2L)
  if (grepl("^file://", p)) {
    p <- utils::URLdecode(sub("^file://(localhost)?", "", p))
    if (is_windows()) p <- sub("^/([A-Za-z]:)", "\\1", p)
  }
  if (is_windows() && grepl("^/(mnt/|cygdrive/)?[A-Za-z](/|$)", p) && !startsWith(p, "//"))
    p <- sub("^/(mnt/|cygdrive/)?([A-Za-z])(/|$)", "\\2:/", p)          # /c/Users -> C:/Users
  if (p == "~" || startsWith(p, "~/") || startsWith(p, "~\\")) p <- as_utf8(path.expand(p))  # R's HOME (Documents on Windows)
  if (is_windows() && grepl("^[A-Za-z]:[^/\\\\]", p))                # drive-relative "C:foo": let Windows resolve it
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (!path_is_abs(p)) p <- paste0(gsub("\\", "/", as_utf8(cwd), fixed = TRUE), "/", p)
  path_norm(p)
}

# Canonical path even when the tail does not exist yet: realpath() of the longest existing ancestor
# (resolves symlinks, 8.3 short names and -- on Windows -- canonical case) + the remaining components.
path_real <- function(p) {
  p <- path_norm(p)
  tail <- character(); cur <- p
  repeat {
    if (file.exists(os_path(cur))) break
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    tail <- c(basename(cur), tail); cur <- parent
  }
  base <- as_utf8(normalizePath(os_path(cur), winslash = "/", mustWork = FALSE))
  path_norm(if (length(tail)) paste(c(base, tail), collapse = "/") else base)
}

# Is the file system that holds `dir` case-insensitive? (NTFS and default APFS/HFS+: yes; ext4: no.)
fs_case_insensitive <- function(dir) {
  if (is_windows()) return(TRUE)
  dir <- path_real(dir)
  b <- basename(dir)
  flip <- chartr(paste(c(letters, LETTERS), collapse = ""), paste(c(LETTERS, letters), collapse = ""), b)
  if (identical(flip, b) || !dir.exists(os_path(dir))) {
    probe <- tempfile("gptrCaseProbe", tmpdir = dir)
    if (!file.create(os_path(probe), showWarnings = FALSE)) return(FALSE)
    on.exit(unlink(os_path(probe)))
    return(file.exists(os_path(file.path(dirname(probe), toupper(basename(probe))))))
  }
  file.exists(os_path(file.path(dirname(dir), flip)))
}

# TRUE if `p` (after symlink resolution) lies inside one of `roots`.
path_within <- function(p, roots, case_insensitive = NULL) {
  rp <- path_real(p)
  for (r in roots) {
    rr <- path_real(r)
    ci <- case_insensitive %||% fs_case_insensitive(rr)
    a <- if (ci) tolower(rp) else rp; b <- if (ci) tolower(rr) else rr
    if (identical(a, b) || startsWith(a, if (endsWith(b, "/")) b else paste0(b, "/"))) return(TRUE)
  }
  FALSE
}

# Relative path for display ("/" separators); falls back to the absolute path outside `base`.
path_rel <- function(p, base) {
  base <- path_norm(base)
  pre <- if (endsWith(base, "/")) base else paste0(base, "/")
  out <- ifelse(p == base, ".", ifelse(startsWith(p, pre), substring(p, nchar(pre) + 1L), p))
  mark_utf8(out)
}

# Permission gate for mutating tools (advisory; the R session itself is not sandboxed).
guard_write_path <- function(abs_path, workspace = getwd(), allow_outside = getOption("gptr.allow_outside_workspace", FALSE)) {
  if (isTRUE(allow_outside) || path_within(abs_path, workspace)) return(invisible(TRUE))
  stop(sprintf("Refusing to write outside the workspace: %s (workspace: %s). Symlinks are resolved before this check.",
               path_real(abs_path), path_real(workspace)), call. = FALSE)
}

# Pi resolveReadPath(): macOS screenshot names use U+202F before AM/PM, NFD, and U+2019 apostrophes.
path_resolve_read <- function(path, cwd = getwd()) {
  res <- path_resolve(path, cwd)
  if (file.exists(os_path(res))) return(res)
  nfd <- if (has_pkg("stringi")) stringi::stri_trans_nfd(res) else res     # utf8::utf8_normalize() only does NFC/NFKC
  cand <- c(gsub(" (AM|PM)\\.", paste0(u_chr(0x202F), "\\1."), res, ignore.case = TRUE, perl = TRUE),
            nfd, gsub("'", u_chr(0x2019), res, fixed = TRUE), gsub("'", u_chr(0x2019), nfd, fixed = TRUE))
  for (v in unique(mark_utf8(cand))) if (!identical(v, res) && file.exists(os_path(v))) return(v)
  res
}
```

#### `proto/10-read.R`

```r
# gptr file tools prototype -- read

# ---- image sniffing (magic bytes, never the extension; port of Pi utils/mime.ts) ----------------
.u32be <- function(b, o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(3:0))
.u32le <- function(b, o) sum(as.numeric(as.integer(b[o + 0:3])) * 256^(0:3))
.u16le <- function(b, o) as.integer(b[o]) + 256L * as.integer(b[o + 1L])
.u16be <- function(b, o) 256L * as.integer(b[o]) + as.integer(b[o + 1L])
.ascii_at <- function(b, o, s) { r <- charToRaw(s); length(b) >= o + length(r) - 1L && identical(b[o:(o + length(r) - 1L)], r) }

detect_image_mime <- function(b) {
  if (length(b) >= 3L && identical(b[1:3], as.raw(c(0xFF, 0xD8, 0xFF)))) return(if (length(b) >= 4L && b[4] == as.raw(0xF7)) NA_character_ else "image/jpeg")
  if (length(b) >= 16L && identical(b[1:8], as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))) {
    if (.u32be(b, 9L) != 13 || !.ascii_at(b, 13L, "IHDR")) return(NA_character_)
    off <- 9L                                            # APNG (acTL before IDAT) is not supported by providers
    while (off + 7L <= length(b)) {
      if (.ascii_at(b, off + 4L, "acTL")) return(NA_character_)
      if (.ascii_at(b, off + 4L, "IDAT")) break
      off <- off + 12L + .u32be(b, off)
    }
    return("image/png")
  }
  if (.ascii_at(b, 1L, "GIF87a") || .ascii_at(b, 1L, "GIF89a")) return("image/gif")
  if (.ascii_at(b, 1L, "RIFF") && .ascii_at(b, 9L, "WEBP")) return("image/webp")
  if (.ascii_at(b, 1L, "BM") && length(b) >= 26L) return("image/bmp")
  NA_character_
}

# Width/height without decoding (pure R). Returns c(w, h) or NULL.
image_dims <- function(b, mime) {
  tryCatch(switch(mime,
    "image/png"  = c(.u32be(b, 17L), .u32be(b, 21L)),
    "image/gif"  = c(.u16le(b, 7L), .u16le(b, 9L)),
    "image/bmp"  = c(.u32le(b, 19L), abs(.u32le(b, 23L) - if (.u32le(b, 23L) > 2^31) 2^32 else 0)),
    "image/webp" = {
      if (.ascii_at(b, 13L, "VP8X")) c(1 + .u16le(b, 25L) + 65536 * as.integer(b[27]), 1 + .u16le(b, 28L) + 65536 * as.integer(b[30]))
      else if (.ascii_at(b, 13L, "VP8L")) { v <- .u32le(b, 22L); c(1 + v %% 16384, 1 + (v %/% 16384) %% 16384) }
      else c(.u16le(b, 27L) %% 16384, .u16le(b, 29L) %% 16384)
    },
    "image/jpeg" = {
      o <- 3L; n <- length(b); out <- NULL
      while (o + 8L <= n) {
        if (b[o] != as.raw(0xFF)) { o <- o + 1L; next }
        m <- as.integer(b[o + 1L])
        if (m %in% c(0xC0:0xC3, 0xC5:0xC7, 0xC9:0xCB, 0xCD:0xCF)) { out <- c(.u16be(b, o + 7L), .u16be(b, o + 5L)); break }
        if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) { o <- o + 2L; next }
        o <- o + 2L + .u16be(b, o + 2L)
      }
      out
    }), error = function(e) NULL)
}

base64_raw <- function(b) {           # no line breaks (jsonlite::base64_enc() inserts "\n" every 76 chars)
  if (has_pkg("base64enc")) return(base64enc::base64encode(b))
  if (has_pkg("openssl")) return(openssl::base64_encode(b))
  gsub("[\r\n]", "", jsonlite::base64_enc(b))
}

GPTR_IMAGE_MAX_EDGE <- 2000L                   # Pi default; also the Anthropic limit for >20-image requests
GPTR_IMAGE_MAX_B64  <- 4.5 * 1024^2            # Pi default: headroom below the 5 MB Bedrock/Vertex limit

# Returns list(ok, data, mime, note). Resizing/re-encoding needs 'magick' (Suggests).
process_image <- function(b, mime, max_edge = GPTR_IMAGE_MAX_EDGE, max_b64 = GPTR_IMAGE_MAX_B64) {
  dims <- image_dims(b, mime)
  b64_size <- ceiling(length(b) / 3) * 4
  native <- mime %in% c("image/png", "image/jpeg", "image/gif", "image/webp")
  fits <- native && !is.null(dims) && all(dims <= max_edge) && b64_size < max_b64
  if (fits) return(list(ok = TRUE, data = base64_raw(b), mime = mime, note = NULL))
  if (!has_pkg("magick"))
    return(list(ok = FALSE, note = sprintf("[Image omitted: %s is %s%s; install the 'magick' package to let gptr resize/convert it.]",
                                           mime, format_size(length(b)), if (is.null(dims)) "" else sprintf(", %dx%d px", dims[1], dims[2]))))
  img <- magick::image_read(b)[1]                                   # first frame only
  info <- magick::image_info(img)
  if (info$width > max_edge || info$height > max_edge) img <- magick::image_resize(img, sprintf("%dx%d>", max_edge, max_edge))
  best <- NULL
  for (q in c(NA, 85, 70, 55, 40)) {
    cand <- if (is.na(q)) magick::image_write(img, format = "png") else magick::image_write(magick::image_flatten(img), format = "jpeg", quality = q)
    if (is.null(best) || length(cand) < length(best$raw)) best <- list(raw = cand, mime = if (is.na(q)) "image/png" else "image/jpeg")
    if (ceiling(length(best$raw) / 3) * 4 < max_b64) break
  }
  if (ceiling(length(best$raw) / 3) * 4 >= max_b64) return(list(ok = FALSE, note = "[Image omitted: could not be resized below the inline image size limit.]"))
  ni <- magick::image_info(img)
  note <- if (ni$width != info$width) sprintf("[Image: original %dx%d, displayed at %dx%d. Multiply coordinates by %.2f to map to original image.]",
                                             info$width, info$height, ni$width, ni$height, info$width / ni$width)
  list(ok = TRUE, data = base64_raw(best$raw), mime = best$mime, note = note)
}

# ---- structured data preview (binary data files that R users actually have) ---------------------
.capture <- function(expr, width = 120L) {
  op <- options(width = width); on.exit(options(op))
  paste(utils::capture.output(expr), collapse = "\n")
}
GPTR_PREVIEW_MAX_DESERIALIZE <- 50 * 1024^2    # never deserialize big .rds/.RData/.qs in a read-only tool

preview_data_file <- function(path, n = 10L) {
  ext <- tolower(tools::file_ext(path)); size <- file.size(os_path(path))
  deser_ok <- size <= GPTR_PREVIEW_MAX_DESERIALIZE && getRversion() >= "4.4.0"   # CVE-2024-27322 fixed in 4.4.0
  head_df <- function(df) .capture(print(utils::head(as.data.frame(df), n)))
  hint <- function(code) sprintf("[To load it into the session use the R tool: %s]", code)
  q <- function(p) deparse(p)
  switch(ext,
    rds = if (!deser_ok) NULL else {
      x <- readRDS(path)
      paste0(sprintf("[R object file (.rds, %s): class %s%s]\n", format_size(size), paste(class(x), collapse = "/"),
                     if (!is.null(dim(x))) sprintf(", dim %s", paste(dim(x), collapse = " x ")) else sprintf(", length %d", length(x))),
             if (is.data.frame(x)) paste0(.capture(utils::str(x, list.len = 30, vec.len = 2)), "\n", head_df(x))
             else .capture(utils::str(x, max.level = 1, list.len = 30, vec.len = 3)),
             "\n", hint(sprintf("x <- readRDS(%s)", q(path))))
    },
    rda = , rdata = if (!deser_ok) NULL else {
      e <- new.env(); nm <- load(path, envir = e)
      rows <- vapply(nm, function(o) { v <- get(o, e); sprintf("%s: %s %s", o, paste(class(v), collapse = "/"),
                                                         if (!is.null(dim(v))) paste(dim(v), collapse = " x ") else paste0("length ", length(v))) }, "")
      paste0(sprintf("[R workspace file (%s) with %d object(s)]\n", format_size(size), length(nm)), paste(rows, collapse = "\n"), "\n",
             hint(sprintf("load(%s)", q(path))))
    },
    qs = if (!deser_ok || !has_pkg("qs")) NULL else {
      x <- qs::qread(path, nthreads = 1L)
      paste0(sprintf("[qs file (%s): class %s]\n", format_size(size), paste(class(x), collapse = "/")),
             .capture(utils::str(x, max.level = 1, list.len = 30, vec.len = 3)), "\n", hint(sprintf("x <- qs::qread(%s)", q(path))))
    },
    parquet = if (!has_pkg("arrow")) NULL else {
      pf <- arrow::ParquetFileReader$create(path)
      tbl <- arrow::read_parquet(path, as_data_frame = FALSE)$Slice(0, n)   # reads row groups lazily enough for a preview
      paste0(sprintf("[Parquet file (%s): %s rows x %d columns]\n", format_size(size), format(pf$num_rows, big.mark = ","), pf$GetSchema()$num_fields),
             .capture(print(pf$GetSchema())), "\n", head_df(tbl), "\n", hint(sprintf("df <- arrow::read_parquet(%s)", q(path))))
    },
    feather = , arrow = , ipc = if (!has_pkg("arrow")) NULL else {
      tbl <- arrow::read_ipc_file(path, as_data_frame = FALSE)
      paste0(sprintf("[Arrow IPC/Feather file (%s): %s rows x %d columns]\n", format_size(size), format(tbl$num_rows, big.mark = ","), tbl$num_columns),
             .capture(print(tbl$schema)), "\n", head_df(tbl$Slice(0, n)), "\n", hint(sprintf("df <- arrow::read_feather(%s)", q(path))))
    },
    xlsx = , xls = if (!has_pkg("readxl")) NULL else {
      sh <- readxl::excel_sheets(path)
      df <- readxl::read_excel(path, sheet = 1L, n_max = n, .name_repair = "minimal")
      paste0(sprintf("[Excel workbook (%s), sheets: %s]\nFirst sheet, first %d rows:\n", format_size(size), paste(sh, collapse = ", "), n),
             head_df(df), "\n", hint(sprintf("df <- readxl::read_excel(%s, sheet = 1)", q(path))))
    },
    NULL)
}

BINARY_HINTS <- c(rds = "readRDS()", rda = "load()", rdata = "load()", qs = "qs::qread()", qs2 = "qs2::qs_read()",
                  parquet = "arrow::read_parquet()", feather = "arrow::read_feather()", xlsx = "readxl::read_excel()",
                  xls = "readxl::read_excel()", sav = "haven::read_sav()", dta = "haven::read_dta()", fst = "fst::read_fst()",
                  pdf = "pdftools::pdf_text()", h5 = "hdf5r", h5ad = "anndata / zellkonverter", zip = "utils::unzip(list = TRUE)",
                  gz = "readLines(gzfile())")

# ---- line windows ---------------------------------------------------------------------------------------
# Streaming newline index for big files: bounded memory (one chunk), returns the byte range of the lines
# [offset, offset + n - 1] and the total number of lines. Pure base R.
line_window_stream <- function(path, offset, n, chunk = 8L * 1024L^2) {
  NL <- as.raw(10L)
  con <- file(os_path(path), "rb"); on.exit(close(con))
  want_s <- offset - 1L; want_e <- offset + n - 1L
  seen <- 0; pos <- 0; s_byte <- if (offset == 1L) 0 else NA_real_; e_byte <- NA_real_; last <- NL
  repeat {
    b <- readBin(con, "raw", chunk); if (!length(b)) break
    nl <- which(b == NL); k <- length(nl)
    if (is.na(s_byte) && seen + k >= want_s) s_byte <- pos + nl[want_s - seen]
    if (is.na(e_byte) && seen + k >= want_e) e_byte <- pos + nl[want_e - seen] - 1
    seen <- seen + k; pos <- pos + length(b); last <- b[length(b)]
  }
  total <- seen + 1      # JS "split('\n')" semantics (Pi): a trailing newline yields a final empty line
  list(start = s_byte, end = if (is.na(e_byte)) pos else e_byte, total = total)
}

# All lines of a file as a UTF-8 character vector (JS split semantics; "\r" of CRLF stripped) plus metadata.
read_text_lines <- function(path, offset = 1L, n = NULL) {
  size <- file.size(os_path(path))
  if (size <= GPTR_BIG_FILE) {
    b <- read_raw(path)
    if (is_binary_raw(b)) return(list(binary = TRUE, bytes = b))
    bom <- sniff_bom(b)
    if (nzchar(bom) && bom != "UTF-8") {                            # UTF-16/32: decode everything, then split
      d <- tryCatch(decode_raw(b), error = function(e) NULL)
      if (is.null(d)) return(list(binary = TRUE, bytes = b))
      lines <- split_lines_js(d$text); total <- length(lines)
      sel <- if (offset > total) character() else lines[offset:(if (is.null(n)) total else min(total, offset + n - 1L))]
      crlf <- any(endsWith(sel, "\r")); sel <- sub("\r$", "", sel, perl = TRUE, useBytes = TRUE)
      return(list(binary = FALSE, lines = mark_utf8(sel), total = total, encoding = d$encoding, bom = TRUE, lossy = FALSE, crlf = crlf))
    }
    if (bom == "UTF-8") b <- b[-(1:3)]
    # encoding is decided on the whole file, but only the requested window is split into lines
    all_txt <- tryCatch(rawToChar(b), error = function(e) NULL)       # NUL beyond the sniff window => binary
    if (is.null(all_txt)) return(list(binary = TRUE, bytes = b))
    d <- if (validUTF8(all_txt)) list(encoding = "UTF-8", lossy = FALSE) else decode_raw(b)
    nl <- which(b == as.raw(10L)); total <- length(nl) + 1L          # JS split semantics
    if (offset > total) return(list(binary = FALSE, lines = character(), total = total, encoding = d$encoding, bom = bom == "UTF-8", lossy = d$lossy, crlf = FALSE))
    last <- if (is.null(n)) total else min(total, offset + n - 1L)
    s0 <- if (offset == 1L) 1L else nl[offset - 1L] + 1L
    e0 <- if (last <= length(nl)) nl[last] - 1L else length(b)
    wtxt <- if (e0 >= s0) rawToChar(b[s0:e0]) else ""
    wtxt <- if (d$encoding == "UTF-8") { if (d$lossy) iconv(wtxt, "UTF-8", "UTF-8", sub = REPLACEMENT_SUB) else wtxt } else iconv(wtxt, d$encoding, "UTF-8")
    lines <- split_lines_js(wtxt)
    crlf <- any(endsWith(lines[seq_len(min(length(lines), 1000L))], "\r"))
    lines <- sub("\r$", "", lines, perl = TRUE, useBytes = TRUE)
    return(list(binary = FALSE, lines = mark_utf8(lines), total = total, encoding = d$encoding, bom = bom == "UTF-8", lossy = d$lossy, crlf = crlf))
  }
  head <- read_raw(path, n = min(size, 65536))
  if (is_binary_raw(head)) return(list(binary = TRUE, bytes = head))
  enc <- decode_raw(head[seq_len(max(0L, length(head) - 4L))])$encoding     # sample (avoid a cut multibyte char)
  if (enc %in% c("UTF-16LE", "UTF-16BE", "UTF-32LE", "UTF-32BE")) stop("UTF-16/32 files larger than 64MB are not supported by read; use the R tool", call. = FALSE)
  w <- line_window_stream(path, offset, n %||% GPTR_MAX_LINES)
  if (offset > w$total) return(list(binary = FALSE, lines = character(), total = w$total, encoding = enc, bom = FALSE, lossy = FALSE, crlf = FALSE))
  bytes <- read_raw(path, n = w$end - w$start, offset = w$start)
  if (w$start == 0 && sniff_bom(bytes) == "UTF-8") bytes <- bytes[-(1:3)]
  txt <- rawToChar(bytes)
  txt <- if (enc == "UTF-8") { if (validUTF8(txt)) txt else iconv(txt, "UTF-8", "UTF-8", sub = REPLACEMENT_SUB) } else iconv(txt, enc, "UTF-8")
  lines <- split_lines_js(txt)
  crlf <- any(endsWith(lines, "\r"))
  list(binary = FALSE, lines = mark_utf8(sub("\r$", "", lines, perl = TRUE, useBytes = TRUE)), total = w$total, encoding = enc, bom = FALSE, lossy = FALSE, crlf = crlf)
}

number_lines <- function(lines, start) {
  if (!length(lines)) return(lines)
  num <- seq.int(start, length.out = length(lines))
  mark_utf8(paste0(formatC(num, width = max(6L, nchar(max(num)))), "\t", lines))   # `cat -n` style
}

# ---- the tool --------------------------------------------------------------------------------------------
gptr_read <- function(path, offset = NULL, limit = NULL, cwd = getwd(),
                      line_numbers = getOption("gptr.read_line_numbers", FALSE),
                      images = TRUE, preview_data = TRUE,
                      max_lines = GPTR_MAX_LINES, max_bytes = GPTR_MAX_BYTES) {
  abs <- path_resolve_read(path, cwd)
  if (!file.exists(os_path(abs))) stop(sprintf("File not found: %s", path), call. = FALSE)
  if (dir.exists(os_path(abs))) stop(sprintf("Is a directory: %s. Use the ls tool to list it.", path), call. = FALSE)
  if (file.access(os_path(abs), 4L) != 0L) stop(sprintf("Permission denied: %s", path), call. = FALSE)
  size <- file.size(os_path(abs))
  head <- read_raw(abs, n = min(size, 65536))
  mime <- detect_image_mime(head)
  if (!is.na(mime) && isTRUE(images)) {
    b <- read_raw(abs)
    im <- process_image(b, mime)
    if (!im$ok) return(tool_text(sprintf("Read image file [%s]\n%s", mime, im$note)))
    txt <- paste(c(sprintf("Read image file [%s]", im$mime), im$note), collapse = "\n")
    return(structure(list(content = list(list(type = "text", text = txt), list(type = "image", data = im$data, mimeType = im$mime)),
                          details = list(bytes = length(b)), isError = FALSE), class = "gptr_tool_result"))
  }
  start <- if (is.null(offset)) 1L else max(1L, as.integer(offset))
  want <- if (is.null(limit)) max_lines + 1L else as.integer(limit)
  if (is_binary_raw(head)) {
    ext <- tolower(tools::file_ext(abs))
    if (isTRUE(preview_data)) {
      pv <- tryCatch(preview_data_file(abs), error = function(e) NULL)
      if (!is.null(pv)) return(tool_text(pv, details = list(preview = TRUE)))
    }
    how <- if (!is.na(BINARY_HINTS[ext])) sprintf(" Load it with the R tool, e.g. %s.", BINARY_HINTS[[ext]]) else ""
    return(tool_text(sprintf("[Binary file: %s (%s). Not shown as text.%s]", path, format_size(size), how)))
  }
  r <- read_text_lines(abs, start, want)
  if (isTRUE(r$binary)) return(tool_text(sprintf("[Binary file: %s (%s). Not shown as text.]", path, format_size(size))))
  if (r$total == 0L || (r$total == 1L && !nzchar(r$lines[1]) && start == 1L)) return(tool_text(sprintf("[File is empty: %s]", path)))
  if (start > r$total) stop(sprintf("Offset %d is beyond end of file (%d lines total)", start, r$total), call. = FALSE)
  lines <- r$lines
  user_limited <- !is.null(limit)
  tr <- truncate_lines_head(lines, max_lines, max_bytes)
  notes <- character()
  if (tr$first_line_exceeds) {
    # gptr deviation: show the first max_bytes of the line instead of pointing at `sed`.
    b <- charToRaw(lines[1L])[seq_len(max_bytes)]
    while (length(b) && bitwAnd(as.integer(b[length(b)]), 0xC0L) == 0x80L) b <- b[-length(b)]   # UTF-8 boundary
    if (length(b) && as.integer(b[length(b)]) >= 0xC0L) b <- b[-length(b)]
    body <- mark_utf8(rawToChar(b))
    out <- if (isTRUE(line_numbers)) number_lines(body, start) else body
    notes <- sprintf("[Line %d is %s; showing its first %s. Use the R tool (e.g. substr()) to see the rest.]",
                     start, format_size(nbytes(lines[1L])), format_size(max_bytes))
  } else {
    out <- if (isTRUE(line_numbers)) number_lines(tr$lines, start) else tr$lines
    end <- start + tr$output_lines - 1L
    if (tr$truncated) {
      notes <- sprintf("[Showing lines %d-%d of %d%s. Use offset=%d to continue.]", start, end, r$total,
                       if (tr$by == "bytes") sprintf(" (%s limit)", format_size(max_bytes)) else "", end + 1L)
    } else if (user_limited && end < r$total) {
      notes <- sprintf("[%d more lines in file. Use offset=%d to continue.]", r$total - end, end + 1L)
    }
  }
  extra <- c(if (!identical(r$encoding, "UTF-8")) sprintf("[Decoded from %s]", r$encoding),
             if (isTRUE(r$lossy)) "[File is not valid UTF-8; invalid bytes shown as U+FFFD]")
  text <- paste(out, collapse = "\n")
  if (length(c(notes, extra))) text <- paste0(text, "\n\n", paste(c(notes, extra), collapse = "\n"))
  tool_text(text, details = list(total_lines = r$total, encoding = r$encoding, bom = r$bom, crlf = r$crlf, truncated = tr$truncated))
}
```

#### `proto/20-write.R`

```r
# gptr file tools prototype -- write (atomic)

# Resolve a symlink chain so we replace the TARGET, not the link (file.rename over a link replaces the
# link itself with a regular file -- verified on macOS). Sys.readlink() returns "" on Windows.
resolve_link_target <- function(p, max_hops = 40L) {
  for (i in seq_len(max_hops)) {
    l <- Sys.readlink(os_path(p))
    if (is.na(l) || !nzchar(l)) return(p)
    p <- if (path_is_abs(l)) path_norm(as_utf8(l)) else path_norm(file.path(dirname(p), as_utf8(l)))
  }
  stop("Too many levels of symbolic links: ", p, call. = FALSE)
}

# Low-level: write raw bytes to `path` atomically when possible.
#  1. temp file in the SAME directory (tempdir() may be on another volume: rename would fail)
#  2. copy permission bits of the existing file (rename would otherwise reset them to umask defaults)
#  3. file.rename(): POSIX rename(2) is atomic; on Windows R calls MoveFileExW(REPLACE_EXISTING |
#     COPY_ALLOWED | WRITE_THROUGH) and retries 10 x 500 ms on sharing violations (src/gnuwin32/extra.c)
#  4. if the rename fails (file open in Excel without FILE_SHARE_DELETE, ACLs, hard links wanted...),
#     fall back to an in-place overwrite (not atomic) so the user's intent still succeeds.
write_bytes_atomic <- function(path, bytes, atomic = TRUE, preserve_mode = TRUE) {
  dir <- dirname(path)
  if (!dir.exists(os_path(dir)) && !dir.create(os_path(dir), recursive = TRUE, showWarnings = FALSE) && !dir.exists(os_path(dir)))
    stop(sprintf("Could not create directory: %s", dir), call. = FALSE)
  existed <- file.exists(os_path(path))
  method <- "direct"
  if (atomic) {
    tmp <- file.path(dir, sprintf(".%s.gptr-%s.tmp", basename(path), paste(sample(c(letters, 0:9), 8, TRUE), collapse = "")))
    on.exit(if (file.exists(os_path(tmp))) unlink(os_path(tmp)), add = TRUE)
    ok <- tryCatch({
      con <- file(os_path(tmp), "wb"); writeBin(bytes, con); close(con)
      if (!identical(file.size(os_path(tmp)), as.numeric(length(bytes)))) stop("short write")
      if (existed && preserve_mode) Sys.chmod(os_path(tmp), file.info(os_path(path), extra_cols = FALSE)$mode, use_umask = FALSE)
      suppressWarnings(file.rename(os_path(tmp), os_path(path)))
    }, error = function(e) FALSE)
    if (isTRUE(ok)) method <- "rename"
  }
  if (method == "direct") {                          # non-atomic fallback / atomic = FALSE
    con <- file(os_path(path), "wb"); on.exit(close(con), add = TRUE)
    writeBin(bytes, con)
  }
  invisible(list(method = method, existed = existed))
}

# Inspect an existing file to keep its conventions (encoding, BOM, dominant EOL, final newline).
file_conventions <- function(path) {
  if (!file.exists(os_path(path))) return(NULL)
  b <- read_raw(path, n = min(file.size(os_path(path)), 1024^2))
  if (is_binary_raw(b)) return(list(binary = TRUE))
  d <- tryCatch(decode_raw(b), error = function(e) NULL)
  if (is.null(d)) return(list(binary = TRUE))
  n_crlf <- lengths(gregexpr("\r\n", d$text, fixed = TRUE, useBytes = TRUE)) * (regexpr("\r\n", d$text, fixed = TRUE, useBytes = TRUE) > 0)
  n_lf <- lengths(gregexpr("\n", d$text, fixed = TRUE, useBytes = TRUE)) * (regexpr("\n", d$text, fixed = TRUE, useBytes = TRUE) > 0)
  list(binary = FALSE, encoding = if (d$lossy) "UTF-8" else d$encoding, bom = d$bom,
       eol = if (n_crlf > 0 && n_crlf >= (n_lf - n_crlf)) "\r\n" else "\n")
}

# The tool. `content` comes from the model (UTF-8, usually LF).
#  eol: "keep" = if the file exists and is CRLF-dominant, convert bare LF to CRLF; new files: as given.
#  encoding: "keep" = re-encode to the existing file's encoding/BOM (CP1252 scripts stay CP1252).
gptr_write <- function(path, content, cwd = getwd(), eol = c("keep", "asis", "lf", "crlf"),
                       encoding = c("keep", "UTF-8"), atomic = TRUE, workspace = cwd) {
  eol <- match.arg(eol); encoding <- match.arg(encoding)
  abs <- path_resolve(path, cwd)
  if (dir.exists(os_path(abs))) stop(sprintf("Is a directory: %s", path), call. = FALSE)
  target <- resolve_link_target(abs)
  guard_write_path(target, workspace)
  conv <- file_conventions(target)
  text <- as_utf8(content)
  target_eol <- switch(eol, asis = NULL, lf = "\n", crlf = "\r\n",
                       keep = if (!is.null(conv) && !isTRUE(conv$binary)) conv$eol else NULL)
  if (!is.null(target_eol)) {
    text <- gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
    if (target_eol == "\r\n") text <- gsub("\n", "\r\n", text, fixed = TRUE, useBytes = TRUE)
  }
  enc <- "UTF-8"; bom <- FALSE
  if (encoding == "keep" && !is.null(conv) && !isTRUE(conv$binary)) { enc <- conv$encoding; bom <- conv$bom }
  bytes <- encode_text(mark_utf8(text), enc, bom)            # encode BEFORE touching the file
  res <- write_bytes_atomic(target, bytes, atomic = atomic)
  msg <- sprintf("Successfully wrote %d bytes to %s", length(bytes), path)
  tool_text(msg, details = list(path = target, bytes = length(bytes), created = !res$existed, method = res$method,
                                encoding = enc, bom = bom, eol = target_eol %||% "asis"))
}
```

#### `proto/30-diff.R`

```r
# gptr file tools prototype -- line diff in pure base R (no diffobj / jsdiff dependency).
# Strategy (like git's patience diff with a Myers fallback):
#   lines -> integer tokens (match() is hashed) -> trim common prefix/suffix (vectorised) ->
#   anchors = lines unique in both ranges, longest increasing subsequence -> recurse between anchors ->
#   gaps without anchors: Myers O(ND) with a cost cap (beyond it the gap is reported as replaced).
# Result: integer vector m, m[i] = index of b matched to a[i] (0 = deleted). Matches are increasing.

.lis <- function(x) {                                    # indices of a longest strictly increasing subsequence
  n <- length(x); if (n <= 1L) return(seq_len(n))
  if (!is.unsorted(x, strictly = TRUE)) return(seq_len(n))   # fast path: already increasing
  tails_val <- numeric(0); tails_idx <- integer(0); prev <- integer(n)
  for (i in seq_len(n)) {
    k <- findInterval(x[i], tails_val, left.open = TRUE)    # number of tails < x[i]
    prev[i] <- if (k > 0L) tails_idx[k] else 0L
    tails_val[k + 1L] <- x[i]; tails_idx[k + 1L] <- i
  }
  out <- integer(length(tails_idx)); j <- tails_idx[length(tails_idx)]
  for (p in rev(seq_along(out))) { out[p] <- j; j <- prev[j] }
  out
}

# Length of the common run a[x+1..], b[y+1..] -- vectorised in doubling blocks (an element-wise R while
# loop costs ~0.5 us per line; long snakes between distant edits made that dominate).
.snake <- function(a, b, x, y) {
  L <- min(length(a) - x, length(b) - y); k <- 0L
  while (k < L && k < 8L) { if (a[x + k + 1L] != b[y + k + 1L]) return(k); k <- k + 1L }   # short snakes: scalar
  blk <- 64L
  while (k < L) {                                                                          # long snakes: blocks
    len <- min(blk, L - k); i <- seq_len(len)
    neq <- which(a[x + k + i] != b[y + k + i])
    if (length(neq)) return(k + neq[1L] - 1L)
    k <- k + len; blk <- blk * 2L
  }
  L
}

# Myers greedy forward algorithm on integer vectors; returns matched pairs (ia, ib) or NULL if D > max_d.
# Backtracking records each snake as a RANGE and expands once at the end (growing vectors with c() inside
# the loop was O(n^2): 72 s for a 150k-line snake).
.myers <- function(a, b, max_d = 1000L) {
  n <- length(a); m <- length(b); off <- n + m + 2L
  v <- integer(2L * off + 1L); trace <- vector("list", 0L)
  dmax <- min(n + m, max_d)
  for (d in 0:dmax) {
    trace[[d + 1L]] <- v
    for (k in seq.int(-d, d, by = 2L)) {
      x <- if (k == -d || (k != d && v[off + k - 1L] < v[off + k + 1L])) v[off + k + 1L] else v[off + k - 1L] + 1L
      y <- x - k
      if (x < n && y < m && a[x + 1L] == b[y + 1L]) { s <- .snake(a, b, x, y); x <- x + s; y <- y + s }
      v[off + k] <- x
      if (x >= n && y >= m) {                          # backtrack
        ra <- integer(0); rb <- integer(0); rl <- integer(0); x <- n; y <- m
        for (dd in seq.int(d, 1L, by = -1L)[seq_len(d)]) {
          vv <- trace[[dd + 1L]]; kk <- x - y
          pk <- if (kk == -dd || (kk != dd && vv[off + kk - 1L] < vv[off + kk + 1L])) kk + 1L else kk - 1L
          px <- vv[off + pk]; py <- px - pk
          len <- min(x - px, y - py)
          if (len > 0L) { ra <- c(ra, x - len + 1L); rb <- c(rb, y - len + 1L); rl <- c(rl, len) }
          x <- px; y <- py
        }
        if (x > 0L && y > 0L) { len <- min(x, y); ra <- c(ra, x - len + 1L); rb <- c(rb, y - len + 1L); rl <- c(rl, len) }
        if (!length(rl)) return(list(a = integer(0), b = integer(0)))
        o <- order(ra)
        idx <- sequence(rl[o]) - 1L
        return(list(a = rep(ra[o], rl[o]) + idx, b = rep(rb[o], rl[o]) + idx))
      }
    }
  }
  NULL
}

diff_match <- function(a, b, max_d = 1000L) {
  u <- unique(c(a, b)); ta <- match(a, u); tb <- match(b, u)
  m <- integer(length(a))
  stack <- list(c(1L, length(a), 1L, length(b)))
  while (length(stack)) {
    r <- stack[[length(stack)]]; stack[[length(stack)]] <- NULL
    a0 <- r[1]; a1 <- r[2]; b0 <- r[3]; b1 <- r[4]
    if (a0 > a1 || b0 > b1) next
    # common prefix
    k <- min(a1 - a0, b1 - b0) + 1L
    neq <- which(ta[a0:(a0 + k - 1L)] != tb[b0:(b0 + k - 1L)])
    p <- if (length(neq)) neq[1L] - 1L else k
    if (p > 0L) { m[a0:(a0 + p - 1L)] <- b0:(b0 + p - 1L); a0 <- a0 + p; b0 <- b0 + p }
    if (a0 > a1 || b0 > b1) next
    # common suffix
    k <- min(a1 - a0, b1 - b0) + 1L
    neq <- which(ta[a1:(a1 - k + 1L)] != tb[b1:(b1 - k + 1L)])
    s <- if (length(neq)) neq[1L] - 1L else k
    if (s > 0L) { m[(a1 - s + 1L):a1] <- (b1 - s + 1L):b1; a1 <- a1 - s; b1 <- b1 - s }
    if (a0 > a1 || b0 > b1) next
    # patience anchors
    ra <- ta[a0:a1]; rb <- tb[b0:b1]
    ua <- !duplicated(ra) & !duplicated(ra, fromLast = TRUE)
    ub <- !duplicated(rb) & !duplicated(rb, fromLast = TRUE)
    pa <- which(ua); pb <- match(ra[pa], rb)
    ok <- !is.na(pb); pa <- pa[ok]; pb <- pb[ok]; ok <- ub[pb]; pa <- pa[ok]; pb <- pb[ok]
    if (length(pa)) {
      keep <- .lis(pb); pa <- pa[keep] + a0 - 1L; pb <- pb[keep] + b0 - 1L
      m[pa] <- pb
      lo_a <- c(a0, pa + 1L); hi_a <- c(pa - 1L, a1); lo_b <- c(b0, pb + 1L); hi_b <- c(pb - 1L, b1)
      for (i in seq_along(lo_a)) if (lo_a[i] <= hi_a[i] && lo_b[i] <= hi_b[i]) stack[[length(stack) + 1L]] <- c(lo_a[i], hi_a[i], lo_b[i], hi_b[i])
      next
    }
    my <- .myers(ra, rb, max_d)
    if (is.null(my) && has_pkg("diffobj")) {               # pathological gap (D > max_d): C accelerator if installed
      sd <- diffobj::ses_dat(as.character(ra), as.character(rb), warn = FALSE); op <- as.character(sd$op); mt <- op == "Match"
      my <- list(a = cumsum(op != "Insert")[mt], b = cumsum(op != "Delete")[mt])   # id.b is NA on Match rows
    }
    if (!is.null(my) && length(my$a)) m[my$a + a0 - 1L] <- my$b + b0 - 1L   # NULL => gap reported as replaced
  }
  m
}

# Edit script as a data.frame(op = "=", "-", "+"; a = line in a or NA; b = line in b or NA), in file order.
# Vectorised: every line gets a (group, type, index) sort key; deletions and insertions sort before the
# matched pair that follows them.
diff_ops <- function(a, b, max_d = 1000L) {
  m <- diff_match(a, b, max_d)
  matched_a <- m > 0L
  mb <- logical(length(b)); mb[m[matched_a]] <- TRUE
  ca <- cumsum(matched_a); cb <- cumsum(mb)
  del <- which(!matched_a); ins <- which(!mb); eq <- which(matched_a)
  op  <- c(rep("-", length(del)), rep("+", length(ins)), rep("=", length(eq)))
  A   <- c(del, rep(NA_integer_, length(ins)), eq)
  B   <- c(rep(NA_integer_, length(del)), ins, m[eq])
  grp <- c(ca[del] + 1L, cb[ins] + 1L, ca[eq])
  typ <- c(rep(1L, length(del)), rep(2L, length(ins)), rep(3L, length(eq)))
  o <- order(grp, typ, c(del, ins, eq), method = "radix")
  data.frame(op = op[o], a = A[o], b = B[o], stringsAsFactors = FALSE)
}

# Text -> lines for diffing, remembering whether the text ends with "\n" (for "\ No newline at end of file").
.diff_lines <- function(x) { l <- split_lines_js(x); nl <- length(l) && l[length(l)] == ""; if (nl) l <- l[-length(l)]; list(lines = l, final_nl = nl || !nzchar(x)) }

# Standard unified diff (GNU/git format; accepted by `git apply` and `patch`).
unified_diff <- function(old, new, path_a = "a", path_b = path_a, context = 3L) {
  A <- .diff_lines(old); B <- .diff_lines(new)
  # a missing final newline makes the last line differ (GNU diff semantics)
  ka <- A$lines; kb <- B$lines
  if (!A$final_nl && length(ka)) ka[length(ka)] <- paste0(ka[length(ka)], "\001<no-eol>")
  if (!B$final_nl && length(kb)) kb[length(kb)] <- paste0(kb[length(kb)], "\001<no-eol>")
  ops <- diff_ops(ka, kb)
  ch <- which(ops$op != "=")
  if (!length(ch)) return("")
  # hunk boundaries: changes closer than 2*context+1 lines merge into one hunk
  brk <- c(TRUE, diff(ch) > 2L * context + 1L)
  starts <- ch[brk]; ends <- ch[c(brk[-1L], TRUE)]
  out <- c(sprintf("--- %s", path_a), sprintf("+++ %s", path_b))
  for (h in seq_along(starts)) {
    lo <- max(1L, starts[h] - context); hi <- min(nrow(ops), ends[h] + context)
    o <- ops[lo:hi, ]
    a_lines <- o$a[!is.na(o$a)]; b_lines <- o$b[!is.na(o$b)]
    a_start <- if (length(a_lines)) min(a_lines) else { pa <- ops$a[seq_len(lo - 1L)]; pa <- pa[!is.na(pa)]; if (length(pa)) max(pa) else 0L }
    b_start <- if (length(b_lines)) min(b_lines) else { pb <- ops$b[seq_len(lo - 1L)]; pb <- pb[!is.na(pb)]; if (length(pb)) max(pb) else 0L }
    rng <- function(s, n) if (n == 1L) sprintf("%d", s) else sprintf("%d,%d", s, n)
    out <- c(out, sprintf("@@ -%s +%s @@", rng(a_start, length(a_lines)), rng(b_start, length(b_lines))))
    body <- ifelse(o$op == "=", paste0(" ", A$lines[o$a]), ifelse(o$op == "-", paste0("-", A$lines[o$a]), paste0("+", B$lines[o$b])))
    # "\ No newline at end of file" after the last line of a side that lacks it
    nonl <- (!A$final_nl & !is.na(o$a) & o$a == length(A$lines) & o$op != "+") | (!B$final_nl & !is.na(o$b) & o$b == length(B$lines) & o$op != "-")
    body <- as.vector(rbind(body, ifelse(nonl, "\\ No newline at end of file", NA_character_)))
    out <- c(out, body[!is.na(body)])
  }
  mark_utf8(paste0(paste(out, collapse = "\n"), "\n"))
}

# Pi generateDiffString(): "+NN line" / "-NN line" / " NN line"; every run of skipped context lines
# becomes one " ... " marker (also before the first and after the last change, as in Pi).
display_diff <- function(old, new, context = 4L) {
  w <- nchar(max(length(split_lines_js(old)), length(split_lines_js(new))))   # Pi: width from split("\n")
  A <- .diff_lines(old)$lines; B <- .diff_lines(new)$lines
  ops <- diff_ops(A, B)
  n <- nrow(ops); ch <- which(ops$op != "=")
  if (!length(ch)) return(list(diff = "", first_changed_line = NA_integer_))
  idx <- as.vector(outer(ch, -context:context, "+")); idx <- idx[idx >= 1L & idx <= n]
  near <- logical(n); near[idx] <- TRUE
  num <- ifelse(ops$op == "+", ops$b, ops$a)
  txt <- ifelse(ops$op == "+", B[pmax(1L, ops$b)], A[pmax(1L, ops$a)])
  line <- paste0(ifelse(ops$op == "=", " ", ops$op), formatC(num, width = w), " ", txt)
  gap_start <- which(!near & c(TRUE, near[-n]))
  keep <- which(near)
  out <- c(line[keep], rep(paste0(" ", strrep(" ", w), " ..."), length(gap_start)))[order(c(keep, gap_start))]
  first <- ops$b[ch[1L]]; if (is.na(first)) { pb <- ops$b[seq_len(ch[1L])]; first <- max(c(0L, pb[!is.na(pb)])) + 1L }
  list(diff = mark_utf8(paste(out, collapse = "\n")), first_changed_line = first)
}
```

#### `proto/31-edit.R`

```r
# gptr file tools prototype -- edit (port of Pi edit.ts + edit-diff.ts, byte-exact outside the edited spans)

# Pi normalizeForFuzzyMatch(), applied LINE BY LINE so the line structure is unchanged:
# NFKC (stringi, else utf8, else skipped), trailing whitespace (JS trimEnd = PCRE [\h\v] + BOM),
# smart quotes -> ASCII, Unicode dashes -> "-", special spaces -> " ".
# "(*UTF)" is required: R only switches PCRE to UTF mode when an input is non-ASCII, so \x{2019} is a
# compile error ("code point value ... too large") on all-ASCII input -- in every locale (verified).
fuzzy_normalize_lines <- function(x) {
  x <- mark_utf8(x)
  if (has_pkg("stringi")) x <- stringi::stri_trans_nfkc(x)
  else if (has_pkg("utf8")) x <- utf8::utf8_normalize(x, map_compat = TRUE)
  x <- sub("(*UTF)[\\h\\v\\x{FEFF}]+$", "", x, perl = TRUE)
  x <- gsub("(*UTF)[\\x{2018}\\x{2019}\\x{201A}\\x{201B}]", "'", x, perl = TRUE)
  x <- gsub("(*UTF)[\\x{201C}\\x{201D}\\x{201E}\\x{201F}]", "\"", x, perl = TRUE)
  x <- gsub("(*UTF)[\\x{2010}-\\x{2015}\\x{2212}]", "-", x, perl = TRUE)
  x <- gsub("(*UTF)[\\x{00A0}\\x{2002}-\\x{200A}\\x{202F}\\x{205F}\\x{3000}]", " ", x, perl = TRUE)
  mark_utf8(x)
}
fuzzy_normalize <- function(text) mark_utf8(paste(fuzzy_normalize_lines(split_lines_js(text)), collapse = "\n"))

# All non-overlapping occurrences (0-based byte offsets) of a fixed string. Locale independent.
fixed_positions <- function(haystack, needle) {
  r <- gregexpr(needle, haystack, fixed = TRUE, useBytes = TRUE)[[1L]]
  if (r[1L] == -1L) integer(0) else as.integer(r) - 1L
}
# Splice replacements (0-based start, byte length, new text) into a string, working on raw bytes.
splice_bytes <- function(x, start, len, new) {
  if (!length(start)) return(x)
  o <- order(start); start <- start[o]; len <- len[o]; new <- new[o]
  b <- charToRaw(x); pieces <- vector("list", 2L * length(start) + 1L); pos <- 0
  for (i in seq_along(start)) {
    pieces[[2L * i - 1L]] <- if (start[i] > pos) b[(pos + 1):start[i]] else raw(0)
    pieces[[2L * i]] <- charToRaw(new[i])
    pos <- start[i] + len[i]
  }
  pieces[[length(pieces)]] <- if (pos < length(b)) b[(pos + 1):length(b)] else raw(0)
  rawToChar(unlist(pieces))
}

.edit_err <- function(fmt1, fmtn, path, i, n, ...) {
  stop(if (n == 1L) sprintf(fmt1, ..., path) else sprintf(fmtn, i - 1L, ..., path), call. = FALSE)
}

# Core algorithm on a decoded text (string without BOM). Returns list(text = new original-space text,
# base_old, base_new (LF-normalised, for diffs), fuzzy, counts).
apply_edits <- function(text, edits, path = "file", fuzzy = TRUE) {
  n <- length(edits)
  if (!n) stop("Edit tool input is invalid. edits must contain at least one replacement.", call. = FALSE)
  # original lines with their endings; base = LF-normalised view (CRLF -> LF; lone CR kept)
  pieces <- strsplit(paste0(text, "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1L]]   # JS split on "\n" only
  k <- length(pieces)
  has_cr <- grepl("\r$", pieces, perl = TRUE, useBytes = TRUE) & seq_len(k) < k   # CR of a CRLF ending (not on the final piece)
  lossy <- !validUTF8(text)
  remark <- function(x) if (lossy) x else mark_utf8(x)
  body <- pieces; body[has_cr] <- sub("\r$", "", pieces[has_cr], perl = TRUE, useBytes = TRUE)   # bytes, not chars
  body <- remark(body)
  base <- remark(paste(body, collapse = "\n"))
  eol <- detect_eol(text)
  olds <- normalize_lf(vapply(edits, function(e) as_utf8(e$oldText %||% e$old_text %||% ""), ""))
  news <- normalize_lf(vapply(edits, function(e) as_utf8(e$newText %||% e$new_text %||% ""), ""))
  all_  <- vapply(edits, function(e) isTRUE(e$replaceAll %||% e$replace_all), NA)
  for (i in seq_len(n)) if (!nzchar(olds[i])) .edit_err("oldText must not be empty in %s.", "edits[%d].oldText must not be empty in %s.", path, i, n)
  exact_pos <- lapply(olds, function(o) fixed_positions(base, o))
  need_fuzzy <- any(lengths(exact_pos) == 0L)
  used_fuzzy <- FALSE; space <- base; pos <- exact_pos; olds_space <- olds
  if (need_fuzzy && fuzzy && !lossy) {
    fz_lines <- fuzzy_normalize_lines(body)
    space <- mark_utf8(paste(fz_lines, collapse = "\n"))
    olds_space <- vapply(olds, function(o) { p <- fixed_positions(space, o); if (length(p)) o else fuzzy_normalize(o) }, "")
    pos <- lapply(olds_space, function(o) fixed_positions(space, o))
    used_fuzzy <- TRUE
  }
  starts <- integer(0); lens <- integer(0); repl <- character(0); owner <- integer(0); counts <- integer(n)
  for (i in seq_len(n)) {
    p <- pos[[i]]
    if (!length(p)) .edit_err("Could not find the exact text in %s. The old text must match exactly including all whitespace and newlines.",
                              "Could not find edits[%d] in %s. The oldText must match exactly including all whitespace and newlines.", path, i, n)
    if (length(p) > 1L && !all_[i])
      stop(if (n == 1L) sprintf("Found %d occurrences of the text in %s. The text must be unique. Please provide more context to make it unique, or set replaceAll = true.", length(p), path)
           else sprintf("Found %d occurrences of edits[%d] in %s. Each oldText must be unique. Please provide more context to make it unique, or set replaceAll = true.", length(p), i - 1L, path), call. = FALSE)
    counts[i] <- length(p)
    starts <- c(starts, p); lens <- c(lens, rep(nbytes(olds_space[i]), length(p)))
    repl <- c(repl, rep(news[i], length(p))); owner <- c(owner, rep(i, length(p)))
  }
  o <- order(starts); starts <- starts[o]; lens <- lens[o]; repl <- repl[o]; owner <- owner[o]
  ov <- which(starts[-1L] < (starts + lens)[-length(starts)])
  if (length(ov)) stop(sprintf("edits[%d] and edits[%d] overlap in %s. Merge them into one edit or target disjoint regions.",
                               owner[ov[1]] - 1L, owner[ov[1] + 1L] - 1L, path), call. = FALSE)
  base_new <- if (!used_fuzzy) splice_bytes(base, starts, lens, repl) else NULL
  if (!used_fuzzy) {
    # map base offsets -> original offsets: +1 byte for every CRLF newline strictly before the offset
    nl_base <- cumsum(nbytes(body) + 1L)[seq_len(k - 1L)] - 1L        # 0-based offsets of "\n" in base
    crs <- cumsum(has_cr[seq_len(k - 1L)])
    shift <- function(off) { j <- findInterval(off, nl_base, left.open = TRUE); ifelse(j > 0L, crs[pmax(1L, j)], 0L) }
    o_start <- starts + shift(starts); o_end <- (starts + lens) + shift(starts + lens)
    repl_eol <- if (eol == "\r\n") gsub("\n", "\r\n", repl, fixed = TRUE, useBytes = TRUE) else repl
    new_text <- splice_bytes(text, o_start, o_end - o_start, repl_eol)
  } else {
    # Pi applyReplacementsPreservingUnchangedLines(): untouched lines keep their original bytes and endings;
    # touched line groups are rewritten from the fuzzy-normalised view with the replacements applied.
    line_start <- c(0L, cumsum(nbytes(fz_lines) + 1L))[seq_len(k)]
    s_line <- findInterval(starts, line_start); e_line <- findInterval(starts + lens - 1L, line_start)
    grp <- cumsum(c(TRUE, s_line[-1L] > cummax(e_line)[-length(e_line)]))
    g_s <- tapply(s_line, grp, min); g_e <- tapply(e_line, grp, max)
    out <- character(0); cur <- 1L
    orig_line <- paste0(body, ifelse(has_cr, "\r\n", ifelse(seq_len(k) < k, "\n", "")))
    for (g in seq_along(g_s)) {
      if (g_s[g] > cur) out <- c(out, orig_line[cur:(g_s[g] - 1L)])
      seg_off <- line_start[g_s[g]]
      seg <- paste(fz_lines[g_s[g]:g_e[g]], collapse = "\n")
      sel <- grp == g
      seg <- splice_bytes(seg, starts[sel] - seg_off, lens[sel], repl[sel])
      last_eol <- if (g_e[g] < k) (if (has_cr[g_e[g]]) "\r\n" else "\n") else ""
      if (eol == "\r\n") seg <- gsub("\n", "\r\n", seg, fixed = TRUE, useBytes = TRUE)
      out <- c(out, paste0(seg, last_eol)); cur <- g_e[g] + 1L
    }
    if (cur <= k) out <- c(out, orig_line[cur:k])
    new_text <- paste(out, collapse = "")
  }
  new_text <- if (lossy) new_text else mark_utf8(new_text)
  if (identical(new_text, text))
    stop(if (n == 1L) sprintf("No changes made to %s. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.", path)
         else sprintf("No changes made to %s. The replacements produced identical content.", path), call. = FALSE)
  base_new <- normalize_lf(new_text)
  list(text = new_text, base_old = base, base_new = base_new, fuzzy = used_fuzzy, counts = counts)
}

# Accepts edits as list(list(oldText=, newText=[, replaceAll=]), ...), a single such list, a JSON string
# (some models send that -- Pi prepareEditArguments()), or a data.frame with oldText/newText columns.
normalize_edit_args <- function(edits, oldText = NULL, newText = NULL) {
  if (is.character(edits) && length(edits) == 1L) edits <- jsonlite::fromJSON(edits, simplifyVector = FALSE)
  if (is.data.frame(edits)) edits <- lapply(seq_len(nrow(edits)), function(i) as.list(edits[i, , drop = FALSE]))
  if (is.list(edits) && !is.null(edits$oldText %||% edits$old_text)) edits <- list(edits)
  if (!is.null(oldText) && !is.null(newText)) edits <- c(edits, list(list(oldText = oldText, newText = newText)))
  edits
}

gptr_edit <- function(path, edits = list(), cwd = getwd(), fuzzy = TRUE, dry_run = FALSE, workspace = cwd,
                      oldText = NULL, newText = NULL, diff_in_result = TRUE, max_diff_bytes = 4000L) {
  edits <- normalize_edit_args(edits, oldText, newText)
  abs <- path_resolve(path, cwd)
  if (!file.exists(os_path(abs))) stop(sprintf("Could not edit file: %s. Error code: ENOENT.", path), call. = FALSE)
  target <- resolve_link_target(abs)
  if (!dry_run) guard_write_path(target, workspace)
  if (!dry_run && file.access(os_path(target), 2L) != 0L) stop(sprintf("Could not edit file: %s. Error code: EACCES.", path), call. = FALSE)
  b <- read_raw(target)
  if (is_binary_raw(b) || any(b == as.raw(0L)) && !nzchar(sniff_bom(b))) stop(sprintf("Could not edit file: %s. It is a binary file.", path), call. = FALSE)
  d <- decode_raw(b)
  # lossy UTF-8 (stray invalid bytes): operate on the raw bytes so untouched bytes survive exactly
  text <- if (d$lossy) { t <- rawToChar(if (d$bom) b[-(1:3)] else b); Encoding(t) <- "unknown"; t } else d$text
  res <- apply_edits(text, edits, path, fuzzy = fuzzy)
  view <- function(x) if (d$lossy) mark_utf8(iconv(x, "UTF-8", "UTF-8", sub = REPLACEMENT_SUB)) else x   # diffs must be valid UTF-8
  patch <- unified_diff(view(res$base_old), view(res$base_new), path, path, context = 4L)
  disp <- display_diff(view(res$base_old), view(res$base_new))
  if (!dry_run) {
    bytes <- if (d$lossy) c(if (d$bom) bom_bytes[["UTF-8"]], charToRaw(res$text)) else encode_text(res$text, d$encoding, d$bom)
    write_bytes_atomic(target, bytes)
  }
  n_rep <- sum(res$counts)
  msg <- sprintf("%s %d block(s) in %s.%s", if (dry_run) "Would replace" else "Successfully replaced", n_rep, path,
                 if (res$fuzzy) " (matched after whitespace/quote/dash normalisation)" else "")
  if (diff_in_result) {
    p <- patch
    if (nbytes(p) > max_diff_bytes) p <- paste0(substr(p, 1L, max_diff_bytes), "\n[diff truncated]")
    msg <- paste0(msg, "\n\n", p)
  }
  tool_text(msg, details = list(diff = disp$diff, patch = patch, firstChangedLine = disp$first_changed_line,
                                fuzzy = res$fuzzy, encoding = d$encoding, bom = d$bom))
}
```

#### `proto/40-walk.R`

```r
# gptr file tools prototype -- glob, .gitignore, directory walker (pure base R)

# Always pruned (gptr policy; Pi's SDK fallback ignores node_modules and .git only).
GPTR_DEFAULT_IGNORE <- c(".git/", "node_modules/", ".Rproj.user/", "renv/library/", "renv/staging/", "renv/sandbox/",
                         "packrat/lib*/", "packrat/src/", ".venv/", "__pycache__/", ".ipynb_checkpoints/", ".quarto/")

# ---- glob -> PCRE ------------------------------------------------------------------------------------------
# `*`/`?` never cross "/"; `**` as a whole segment crosses directories ("**/x", "a/**/b", "a/**");
# [abc] [!a-z] [^a] classes; {a,b{c,d}} alternation; "\" escapes. utils::glob2rx() gets all of these wrong.
glob_to_regex <- function(glob, braces = TRUE) {
  ch <- strsplit(as_utf8(glob), "", fixed = TRUE)[[1L]]
  n <- length(ch); i <- 1L; out <- character(); depth <- 0L
  meta <- c(".", "+", "(", ")", "|", "^", "$", "{", "}", "[", "]", "\\", "*", "?")
  esc <- function(c) if (c %in% meta) paste0("\\", c) else c
  # a "{" only opens a group if it has a matching "}" (otherwise literal, like bash)
  closes <- function(from) { d <- 0L; for (j in from:n) { if (ch[j] == "\\") next; if (ch[j] == "{") d <- d + 1L; if (ch[j] == "}") { d <- d - 1L; if (d == 0L) return(TRUE) } }; FALSE }
  while (i <= n) {
    c <- ch[i]
    if (c == "\\" && i < n) { out <- c(out, esc(ch[i + 1L])); i <- i + 2L; next }
    if (c == "*") {
      j <- i; while (j < n && ch[j + 1L] == "*") j <- j + 1L
      seg_start <- i == 1L || ch[i - 1L] == "/"; seg_end <- j == n || ch[j + 1L] == "/"
      if (j > i && seg_start && seg_end) {
        if (j == n) { out <- c(out, if (i == 1L) ".*" else "(?:.*)?"); i <- j + 1L }  # "**" / "a/**"
        else { out <- c(out, "(?:[^/]*/)*"); i <- j + 2L }                        # "**/" (also inside "/**/")
      } else { out <- c(out, "[^/]*"); i <- j + 1L }
      next
    }
    if (c == "?") { out <- c(out, "[^/]"); i <- i + 1L; next }
    if (c == "[") {
      j <- i + 1L
      if (j <= n && ch[j] %in% c("!", "^")) j <- j + 1L
      if (j <= n && ch[j] == "]") j <- j + 1L
      while (j <= n && ch[j] != "]") { if (ch[j] == "[" && j < n && ch[j + 1L] == ":") { k <- j + 2L; while (k < n && !(ch[k] == ":" && ch[k + 1L] == "]")) k <- k + 1L; j <- k + 1L }; j <- j + 1L }
      if (j > n) { out <- c(out, "\\["); i <- i + 1L; next }                # unterminated: literal "["
      body <- ch[(i + 1L):(j - 1L)]
      neg <- body[1L] %in% c("!", "^"); if (neg) body <- body[-1L]
      body <- vapply(seq_along(body), function(k) if (body[k] == "\\" || (body[k] == "]" && k > 1L)) paste0("\\", body[k]) else body[k], "")
      out <- c(out, paste0("[", if (neg) "^/" , paste(body, collapse = ""), "]")); i <- j + 1L; next
    }
    if (braces && c == "{" && closes(i)) { depth <- depth + 1L; out <- c(out, "(?:"); i <- i + 1L; next }
    if (braces && c == "}" && depth > 0L) { depth <- depth - 1L; out <- c(out, ")"); i <- i + 1L; next }
    if (braces && c == "," && depth > 0L) { out <- c(out, "|"); i <- i + 1L; next }
    out <- c(out, esc(c)); i <- i + 1L
  }
  mark_utf8(paste(out, collapse = ""))
}

# Compile a glob for path matching. Returns a matcher function(rel_paths, basenames) -> logical.
# Semantics (fd-like): a pattern without "/" matches the basename; with "/" it matches the whole relative path
# ("src/*.R" anchored at the search root; prefix "**/" to match at any depth). Fast paths avoid regex.
glob_matcher <- function(glob, ignore_case = FALSE) {
  full <- grepl("/", glob, fixed = TRUE)
  g <- sub("^/", "", glob)
  if (ignore_case) g <- tolower(g)
  prep <- function(x) if (ignore_case) tolower(x) else x
  if (!full && !grepl("[][*?{}\\\\]", g))                        # literal basename
    return(function(rel, base) prep(base) == g)
  if (!full && grepl("^\\*[^][*?{}\\\\/]+$", g)) {               # "*.ext"
    suf <- substring(g, 2L); return(function(rel, base) endsWith(prep(base), suf))
  }
  if (full && grepl("^\\*\\*/\\*[^][*?{}\\\\/]+$", g)) {         # "**/*.ext"
    suf <- substring(g, 5L); return(function(rel, base) endsWith(prep(base), suf))
  }
  rx <- paste0("^", glob_to_regex(g), "$")
  function(rel, base) grepl(rx, prep(if (full) rel else base), perl = TRUE)
}

# ---- .gitignore -------------------------------------------------------------------------------------------
# One rule = list(kind = "literal"|"suffix"|"regex", value, negated, dir_only, anchored, base)
# `base` = directory of the ignore file relative to the anchor (repo root or walk root), "" for the anchor.
compile_ignore <- function(lines, base = "", ignore_case = FALSE) {
  rules <- list()
  for (ln in lines) {
    ln <- sub("\r$", "", ln)
    if (!nzchar(ln) || startsWith(ln, "#")) next
    ln <- sub("(?<!\\\\)[ ]+$", "", ln, perl = TRUE)              # trailing spaces unless escaped
    if (!nzchar(ln) || endsWith(ln, "\\") && !endsWith(ln, "\\ ")) next   # trailing backslash: invalid, never matches
    neg <- startsWith(ln, "!"); if (neg) ln <- substring(ln, 2L)
    if (startsWith(ln, "\\#") || startsWith(ln, "\\!")) ln <- substring(ln, 2L)
    dir_only <- endsWith(ln, "/"); if (dir_only) ln <- sub("/+$", "", ln)
    if (!nzchar(ln)) next
    anchored <- grepl("/", ln, fixed = TRUE)
    ln <- sub("^/", "", ln)
    if (ignore_case) ln <- tolower(ln)
    kind <- "regex"; value <- NULL
    if (!anchored && !grepl("[][*?\\\\]", ln)) { kind <- "literal"; value <- ln }
    else if (!anchored && grepl("^\\*[^][*?\\\\]+$", ln)) { kind <- "suffix"; value <- substring(ln, 2L) }
    else value <- paste0("^", glob_to_regex(ln, braces = FALSE), "$")
    rules[[length(rules) + 1L]] <- list(kind = kind, value = value, negated = neg, dir_only = dir_only, anchored = anchored, base = base)
  }
  rules
}

# rel: paths relative to the anchor ("/"-separated); returns TRUE (ignored) / FALSE (re-included) / NA (no rule)
eval_ignore <- function(rules, rel, is_dir, ignore_case = FALSE) {
  res <- rep(NA, length(rel))
  if (!length(rules) || !length(rel)) return(res)
  relc <- if (ignore_case) tolower(rel) else rel
  bn <- basename(relc)
  for (r in rules) {
    cand <- if (nzchar(r$base)) startsWith(relc, paste0(if (ignore_case) tolower(r$base) else r$base, "/")) else rep(TRUE, length(rel))
    if (r$dir_only) cand <- cand & is_dir
    if (!any(cand)) next
    idx <- which(cand)
    tgt <- if (r$anchored) (if (nzchar(r$base)) substring(relc[idx], nchar(r$base) + 2L) else relc[idx]) else bn[idx]
    hit <- switch(r$kind, literal = tgt == r$value, suffix = endsWith(tgt, r$value), regex = grepl(r$value, tgt, perl = TRUE))
    res[idx[hit]] <- !r$negated
  }
  res
}

.read_lines_quiet <- function(f) {
  b <- tryCatch(read_raw(f), error = function(e) raw())
  if (!length(b) || is_binary_raw(b)) return(character())
  split_lines_js(tryCatch(decode_raw(b)$text, error = function(e) ""))
}

find_git_root <- function(dir) {
  cur <- path_real(dir)
  repeat {
    if (file.exists(os_path(file.path(cur, ".git")))) return(cur)
    parent <- dirname(cur); if (identical(parent, cur)) return(NULL); cur <- parent
  }
}

# ---- walker ------------------------------------------------------------------------------------------------
# Breadth-first; one list.files() per directory; ignored directories are pruned before descending
# (git: "It is not possible to re-include a file if a parent directory of that file is excluded").
# Symlinked directories are listed but not followed (ripgrep/fd default; list.files(recursive = TRUE)
# FOLLOWS them on POSIX and can loop). Returns data.frame(rel, is_dir, is_link).
walk_tree <- function(root, hidden = TRUE, gitignore = TRUE, default_ignore = GPTR_DEFAULT_IGNORE,
                      ignore_files = c(".gitignore", ".ignore", ".gptrignore"), max_entries = 500000L,
                      max_depth = Inf, ignore_case = NULL, follow_links = FALSE,
                      detect_cycles = follow_links || is_windows(), check_abort = NULL) {
  # Windows: Sys.readlink() is always "" (junctions/symlinks are invisible to base R), so directory
  # cycles are detected by canonical path (normalizePath resolves junctions there) instead.
  root <- path_real(root)
  visited <- if (detect_cycles) root else character()
  if (is.null(ignore_case)) ignore_case <- fs_case_insensitive(root)
  rules <- compile_ignore(default_ignore, "", ignore_case)
  prefix <- ""
  if (gitignore) {
    git_root <- find_git_root(root)
    if (!is.null(git_root)) {
      prefix <- path_rel(root, git_root); if (prefix == ".") prefix <- ""
      ex <- file.path(git_root, ".git", "info", "exclude")
      if (file.exists(os_path(ex))) rules <- c(rules, compile_ignore(.read_lines_quiet(ex), "", ignore_case))
      if (nzchar(prefix)) {                                    # ignore files of the ancestors inside the repo
        segs <- strsplit(prefix, "/", fixed = TRUE)[[1L]]
        bases <- c("", vapply(seq_len(length(segs) - 1L), function(k) paste(segs[seq_len(k)], collapse = "/"), ""))
        for (bs in bases) for (nm in ignore_files) {
          f <- if (nzchar(bs)) file.path(git_root, bs, nm) else file.path(git_root, nm)
          if (file.exists(os_path(f))) rules <- c(rules, compile_ignore(.read_lines_quiet(f), bs, ignore_case))
        }
      }
    }
  }
  anchor_rel <- function(rel) if (nzchar(prefix)) paste(prefix, rel, sep = "/") else rel
  frontier <- ""; depth <- 0L; acc_rel <- list(); acc_dir <- list(); acc_lnk <- list(); total <- 0L; truncated <- FALSE
  while (length(frontier) && depth < max_depth) {
    if (is.function(check_abort)) check_abort()
    depth <- depth + 1L
    dirs_abs <- ifelse(nzchar(frontier), paste(root, frontier, sep = "/"), root)
    listing <- lapply(dirs_abs, function(d) list.files(os_path(d), all.files = TRUE, no.. = TRUE))
    counts <- lengths(listing)
    if (!sum(counts)) break
    nm <- mark_utf8(unlist(listing, use.names = FALSE))
    parent <- rep(frontier, counts)
    rel <- ifelse(nzchar(parent), paste(parent, nm, sep = "/"), nm)
    full <- paste(root, rel, sep = "/")
    if (gitignore) {                                           # ignore files found at this level apply to it
      for (f in which(nm %in% ignore_files)) {
        bs <- anchor_rel(parent[f]); if (!nzchar(parent[f])) bs <- prefix
        rules <- c(rules, compile_ignore(.read_lines_quiet(full[f]), bs, ignore_case))
      }
    }
    lnk <- Sys.readlink(os_path(full)); is_link <- !is.na(lnk) & nzchar(lnk)
    is_dir <- dir.exists(os_path(full))
    ign <- eval_ignore(rules, anchor_rel(rel), is_dir, ignore_case)
    keep <- is.na(ign) | !ign
    if (!hidden) keep <- keep & !startsWith(nm, ".")
    rel <- rel[keep]; is_dir <- is_dir[keep]; is_link <- is_link[keep]
    acc_rel[[depth]] <- rel; acc_dir[[depth]] <- is_dir; acc_lnk[[depth]] <- is_link
    total <- total + length(rel)
    if (total >= max_entries) { truncated <- TRUE; break }
    frontier <- rel[is_dir & (follow_links | !is_link)]
    if (detect_cycles && length(frontier)) {
      real <- as_utf8(normalizePath(os_path(paste(root, frontier, sep = "/")), winslash = "/", mustWork = FALSE))
      fresh <- !duplicated(real) & !(real %in% visited)
      frontier <- frontier[fresh]; visited <- c(visited, real[fresh])
    }
  }
  out <- data.frame(rel = mark_utf8(as.character(unlist(acc_rel))), is_dir = as.logical(unlist(acc_dir)),
                    is_link = as.logical(unlist(acc_lnk)), stringsAsFactors = FALSE)
  attr(out, "truncated") <- truncated; attr(out, "root") <- root
  out
}
```

#### `proto/50-search.R`

```r
# gptr file tools prototype -- sorting, find, ls, grep

# ---- sorting ------------------------------------------------------------------------------------------------
# Deterministic on every platform: radix order is C-locale byte order (sort()/order() default collation
# depends on the locale and the platform's strcoll/ICU).
# Natural sort key: every digit run is left-padded to `width` digits ("file10" -> "file000...010").
# Vectorised: runs are padded in one pass and re-assembled column-wise with paste0 (regmatches<- was
# ~10 s for 100k paths).
natural_key <- function(x, width = 20L) {
  x <- tolower(as_utf8(x))
  ch <- strsplit(x, "(?<=[0-9])(?=[^0-9])|(?<=[^0-9])(?=[0-9])", perl = TRUE)
  len <- lengths(ch); u <- unlist(ch, use.names = FALSE)
  dig <- grepl("^[0-9]", u, perl = TRUE)
  if (any(dig)) {
    d <- sub("^0+(?=[0-9])", "", u[dig], perl = TRUE)
    u[dig] <- paste0(strrep("0", pmax(0L, width - nchar(d))), d)
  }
  grp <- rep.int(seq_along(x), len); pos <- sequence(len)
  cols <- lapply(seq_len(max(c(1L, len))), function(k) { v <- character(length(x)); s <- pos == k; v[grp[s]] <- u[s]; v })
  out <- do.call(paste0, cols)
  out[len == 0L] <- ""
  mark_utf8(out)
}
order_entries <- function(df, by = c("path", "name", "natural", "mtime", "size", "ext"), decreasing = NULL) {
  by <- match.arg(by)
  if (!nrow(df)) return(integer(0))
  rel <- df$rel
  dec <- decreasing %||% (by %in% c("mtime", "size"))          # newest / largest first by default
  tie <- tolower(rel)
  key <- switch(by,
    path = tolower(rel), name = tolower(basename(rel)), natural = natural_key(rel),
    ext = tolower(tools::file_ext(rel)), mtime = as.numeric(df$mtime), size = as.numeric(df$size))
  if (is.numeric(key)) order(if (dec) -key else key, tie, rel, method = "radix", na.last = TRUE)
  else order(key, tie, rel, method = "radix", decreasing = c(dec, FALSE, FALSE))
}
add_stats <- function(df, root) {
  if (!nrow(df)) { df$size <- numeric(0); df$mtime <- as.POSIXct(numeric(0)); return(df) }
  fi <- file.info(os_path(file.path(root, df$rel)), extra_cols = FALSE)
  df$size <- ifelse(df$is_dir, NA_real_, fi$size); df$mtime <- fi$mtime
  df
}

.notices <- function(text, notices) if (length(notices)) paste0(text, "\n\n[", paste(notices, collapse = ". "), "]") else text

# ---- find ---------------------------------------------------------------------------------------------------
find_files <- function(pattern = "**", path = ".", type = c("any", "file", "dir"), hidden = TRUE, gitignore = TRUE,
                       sort = "path", decreasing = NULL, max_depth = Inf, ignore_case = NULL, cwd = getwd()) {
  type <- match.arg(type)
  root <- path_resolve(path, cwd)
  if (!dir.exists(os_path(root))) stop(sprintf("Path not found: %s", root), call. = FALSE)
  pattern <- as_utf8(pattern)
  w <- walk_tree(root, hidden = hidden, gitignore = gitignore, max_depth = max_depth)
  if (type == "file") w <- w[!w$is_dir, , drop = FALSE] else if (type == "dir") w <- w[w$is_dir, , drop = FALSE]
  ic <- ignore_case %||% !grepl("[[:upper:]]", pattern)          # fd "smart case"
  if (!pattern %in% c("**", "*", "**/*")) w <- w[glob_matcher(pattern, ic)(w$rel, basename(w$rel)), , drop = FALSE]
  if (sort %in% c("mtime", "size")) w <- add_stats(w, attr(w, "root") %||% root)
  w <- w[order_entries(w, sort, decreasing), , drop = FALSE]
  rownames(w) <- NULL
  structure(w, class = c("gptr_files", "data.frame"), root = root)
}

gptr_find <- function(pattern, path = NULL, limit = NULL, sort = c("path", "mtime", "size", "name", "natural"),
                      reverse = FALSE, type = c("any", "file", "dir"), cwd = getwd(), hidden = TRUE, gitignore = TRUE) {
  sort <- match.arg(sort); type <- match.arg(type)
  limit <- as.integer(limit %||% GPTR_FIND_LIMIT)
  f <- find_files(pattern, path %||% ".", type = type, hidden = hidden, gitignore = gitignore, sort = sort,
                  decreasing = if (isTRUE(reverse)) !(sort %in% c("mtime", "size")) else NULL, cwd = cwd)
  if (!nrow(f)) return(tool_text("No files found matching pattern"))
  reached <- nrow(f) > limit
  f <- utils::head(f, limit)
  lines <- paste0(f$rel, ifelse(f$is_dir, "/", ""))
  if (sort == "mtime") lines <- paste0(lines, "  (", format(f$mtime, "%Y-%m-%d %H:%M"), ")")
  if (sort == "size") lines <- paste0(lines, "  (", vapply(f$size, function(s) if (is.na(s)) "dir" else format_size(s), ""), ")")
  tr <- truncate_lines_head(lines, .Machine$integer.max, GPTR_MAX_BYTES)
  notes <- c(if (reached) sprintf("%d results limit reached. Use limit=%d for more, or refine pattern", limit, limit * 2L),
             if (tr$truncated) sprintf("%s limit reached", format_size(GPTR_MAX_BYTES)))
  tool_text(.notices(paste(tr$lines, collapse = "\n"), notes), details = list(n = nrow(f), limit_reached = reached))
}

# ---- ls -----------------------------------------------------------------------------------------------------
gptr_ls <- function(path = NULL, limit = NULL, cwd = getwd(), all = TRUE, long = FALSE,
                    sort = c("name", "natural", "mtime", "size")) {
  sort <- match.arg(sort)
  dir <- path_resolve(path %||% ".", cwd)
  if (!file.exists(os_path(dir))) stop(sprintf("Path not found: %s", dir), call. = FALSE)
  if (!dir.exists(os_path(dir))) stop(sprintf("Not a directory: %s", dir), call. = FALSE)
  limit <- as.integer(limit %||% GPTR_LS_LIMIT)
  nm <- mark_utf8(list.files(os_path(dir), all.files = all, no.. = TRUE))
  if (!length(nm)) return(tool_text("(empty directory)"))
  full <- file.path(dir, nm)
  fi <- file.info(os_path(full), extra_cols = FALSE)            # follows symlinks; broken links -> NA
  df <- data.frame(rel = nm, is_dir = fi$isdir, size = fi$size, mtime = fi$mtime, stringsAsFactors = FALSE)
  df <- df[!is.na(df$is_dir), , drop = FALSE]                    # Pi: skip entries that cannot be stat-ed
  df <- df[order_entries(df, if (sort == "name") "path" else sort), , drop = FALSE]
  reached <- nrow(df) > limit
  df <- utils::head(df, limit)
  lines <- paste0(df$rel, ifelse(df$is_dir, "/", ""))
  if (long) lines <- sprintf("%8s  %s  %s", ifelse(df$is_dir, "-", vapply(df$size, format_size, "")), format(df$mtime, "%Y-%m-%d %H:%M"), lines)
  tr <- truncate_lines_head(lines, .Machine$integer.max, GPTR_MAX_BYTES)
  notes <- c(if (reached) sprintf("%d entries limit reached. Use limit=%d for more", limit, limit * 2L),
             if (tr$truncated) sprintf("%s limit reached", format_size(GPTR_MAX_BYTES)))
  tool_text(.notices(paste(tr$lines, collapse = "\n"), notes))
}

# ---- grep ---------------------------------------------------------------------------------------------------
.regex_check <- function(pattern, perl = TRUE) {
  warn <- NULL
  r <- tryCatch(withCallingHandlers(grepl(pattern, "", perl = perl),
                                    warning = function(w) { warn <<- conditionMessage(w); invokeRestart("muffleWarning") }),
                error = function(e) e)
  if (inherits(r, "error")) stop(sprintf("regex parse error: %s (pattern: %s)", trimws(sub("^PCRE pattern compilation error\\s*", "", warn %||% conditionMessage(r))), pattern), call. = FALSE)
  invisible(TRUE)
}
.quote_literal <- function(p) paste0("\\Q", gsub("\\E", "\\E\\\\E\\Q", p, fixed = TRUE), "\\E")

# Read one file for searching: NULL for binary; UTF-8-marked text with LF line endings otherwise.
.search_text <- function(f) {
  b <- tryCatch(read_raw(f), error = function(e) NULL)
  if (is.null(b) || !length(b) || is_binary_raw(b)) return(NULL)
  t <- tryCatch(decode_raw(b)$text, error = function(e) NULL)       # NUL beyond sniff window -> binary
  if (is.null(t)) return(NULL)
  if (grepl("\r", t, fixed = TRUE, useBytes = TRUE)) t <- gsub("\r\n", "\n", t, fixed = TRUE, useBytes = TRUE)
  mark_utf8(t)
}

# Batch reader for search: returns UTF-8-marked texts with LF endings, NA for binary files.
# readChar(path, size, useBytes = TRUE) is ~3x faster than readBin() + rawToChar() over thousands of
# small files (no raw copy, no tryCatch) and a NUL byte truncates the string (with a warning), so
# nchar(x, "bytes") < size detects binary files anywhere in the file (ripgrep's rule) for free.
# UTF-16/32 files (BOM) contain NULs too and are decoded separately; UTF-8 BOMs are stripped on bytes.
read_texts <- function(files, sizes) {
  txt <- vapply(seq_along(files), function(k) {
    if (sizes[k] <= 0) return("")
    x <- tryCatch(suppressWarnings(readChar(os_path(files[k]), sizes[k], useBytes = TRUE)), error = function(e) character())
    if (!length(x) || nchar(x, "bytes") < sizes[k]) NA_character_ else x
  }, "")
  for (k in which(is.na(txt))) {                                   # binary or UTF-16/32 with BOM
    head <- tryCatch(read_raw(files[k], n = min(4, sizes[k])), error = function(e) raw(0))
    bom <- sniff_bom(head)
    if (nzchar(bom) && bom != "UTF-8") txt[k] <- tryCatch(decode_raw(read_raw(files[k]))$text, error = function(e) NA_character_)
  }
  ok <- !is.na(txt)
  bom8 <- which(ok & grepl("^\xef\xbb\xbf", txt, perl = TRUE, useBytes = TRUE))  # PCRE: anchored => O(1); TRE scans the whole string
  if (length(bom8)) txt[bom8] <- sub("^\xef\xbb\xbf", "", txt[bom8], perl = TRUE, useBytes = TRUE)
  bad <- which(ok & !validUTF8(txt))
  if (length(bad)) { conv <- suppressWarnings(iconv(txt[bad], "CP1252", "UTF-8")); miss <- is.na(conv)
                     conv[miss] <- iconv(txt[bad][miss], "latin1", "UTF-8"); txt[bad] <- conv }
  cr <- which(ok & grepl("\r", txt, fixed = TRUE, useBytes = TRUE))
  if (length(cr)) txt[cr] <- gsub("\r\n", "\n", txt[cr], fixed = TRUE, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  txt
}

# Engine: returns data.frame(file, abs, line, text) for up to `limit` matching lines (files in the given
# order). `matcher(lines)` and `prefilter(texts)` are vectorised closures. Small batches => early stop.
grep_engine <- function(files, labels, matcher, prefilter, limit, sizes = NULL, batch_files = 256L,
                        batch_bytes = 4 * 1024^2, check_abort = NULL) {
  if (is.null(sizes)) sizes <- file.size(os_path(files))
  sizes[is.na(sizes)] <- 0
  batch <- pmax(cumsum(sizes) %/% batch_bytes, (seq_along(files) - 1L) %/% batch_files)
  batch <- cummax(batch)
  res <- list(); n <- 0L; n_bin <- 0L; searched <- 0L
  for (bi in unique(batch)) {
    if (is.function(check_abort)) check_abort()
    idx <- which(batch == bi)
    texts <- read_texts(files[idx], sizes[idx])
    bin <- is.na(texts); n_bin <- n_bin + sum(bin & sizes[idx] > 0)
    idx <- idx[!bin]; texts <- texts[!bin]
    searched <- searched + length(idx)
    if (!length(idx)) next
    cand <- prefilter(texts)
    idx <- idx[cand]; texts <- texts[cand]
    if (!length(idx)) next
    pieces <- strsplit(texts, "\n", fixed = TRUE, useBytes = TRUE)
    lines <- mark_utf8(unlist(pieces, use.names = FALSE))
    fid <- rep(idx, lengths(pieces)); lno <- sequence(lengths(pieces))
    hit <- which(matcher(lines))
    if (!length(hit)) next
    take <- hit[seq_len(min(length(hit), limit - n))]
    res[[length(res) + 1L]] <- data.frame(file = labels[fid[take]], abs = files[fid[take]], line = lno[take], text = lines[take], stringsAsFactors = FALSE)
    n <- n + length(take)
    if (n >= limit) break
  }
  out <- if (length(res)) do.call(rbind, res) else data.frame(file = character(), abs = character(), line = integer(), text = character())
  attr(out, "limit_reached") <- n >= limit; attr(out, "binary_skipped") <- n_bin; attr(out, "searched") <- searched
  out
}

grep_files <- function(pattern, path = ".", glob = NULL, ignore_case = FALSE, literal = FALSE, limit = GPTR_GREP_LIMIT,
                       hidden = TRUE, gitignore = TRUE, sort = c("path", "mtime"), max_file_size = 20 * 1024^2,
                       engine = c("base", "stringi", "rg"), cwd = getwd(), check_abort = NULL) {
  sort <- match.arg(sort); engine <- match.arg(engine)
  pattern <- as_utf8(pattern)
  if (!nzchar(pattern)) stop("pattern must not be empty", call. = FALSE)
  root <- path_resolve(path, cwd)
  if (!file.exists(os_path(root))) stop(sprintf("Path not found: %s", root), call. = FALSE)
  if (engine == "rg" && dir.exists(os_path(root)) && sort == "path") {
    out <- grep_rg(pattern, root, glob = glob, ignore_case = ignore_case, literal = literal, hidden = hidden, max_file_size = max_file_size, limit = limit)
    if (!is.null(out)) {
      rx2 <- paste0("(*UTF)", if (isTRUE(literal)) .quote_literal(pattern) else pattern)
      attr(out, "locator") <- function(x) as.integer(regexpr(rx2, x, perl = TRUE, ignore.case = isTRUE(ignore_case)))
      return(out)
    }
    engine <- "base"                                                   # rg not installed: pure R
  }
  if (engine == "rg") engine <- "base"
  if (dir.exists(os_path(root))) {
    w <- walk_tree(root, hidden = hidden, gitignore = gitignore, check_abort = check_abort)
    w <- w[!w$is_dir, , drop = FALSE]
    if (!is.null(glob) && nzchar(glob)) {
      gl <- strsplit(glob, ",(?![^{]*})", perl = TRUE)[[1L]]      # "*.R,*.Rmd" allowed; commas inside {} kept
      inc <- gl[!startsWith(gl, "!")]; exc <- substring(gl[startsWith(gl, "!")], 2L)
      keep <- if (length(inc)) Reduce(`|`, lapply(inc, function(g) glob_matcher(g)(w$rel, basename(w$rel)))) else rep(TRUE, nrow(w))
      for (g in exc) keep <- keep & !glob_matcher(g)(w$rel, basename(w$rel))
      w <- w[keep, , drop = FALSE]
    }
    w <- add_stats(w, attr(w, "root"))
    too_big <- !is.na(w$size) & w$size > max_file_size
    skipped_big <- sum(too_big); w <- w[!too_big, , drop = FALSE]
    w <- w[order_entries(w, sort), , drop = FALSE]
    files <- file.path(attr(w, "root") %||% root, w$rel); labels <- w$rel; sizes <- w$size
  } else {
    files <- root; labels <- basename(root); skipped_big <- 0L; sizes <- NULL
  }
  if (isTRUE(literal) && !isTRUE(ignore_case)) {
    if (engine == "stringi" && has_pkg("stringi")) { matcher <- function(x) stringi::stri_detect_fixed(x, pattern); prefilter <- matcher }
    else { matcher <- function(x) grepl(pattern, x, fixed = TRUE, useBytes = TRUE); prefilter <- matcher }
  } else {
    rx <- if (isTRUE(literal)) .quote_literal(pattern) else pattern
    # (*UTF): \x{..}/\p{..} need UTF mode even on ASCII-only input; (*UCP): \w \b \d are Unicode-aware (as in ripgrep)
    utf <- if (grepl("^\\(\\*UTF", rx)) "" else "(*UTF)(*UCP)"
    .regex_check(paste0(utf, rx))
    if (engine == "stringi" && has_pkg("stringi")) {
      matcher <- function(x) stringi::stri_detect_regex(x, rx, case_insensitive = isTRUE(ignore_case))
      prefilter <- function(x) stringi::stri_detect_regex(x, rx, case_insensitive = isTRUE(ignore_case), multiline = TRUE)
    } else {
      matcher <- function(x) grepl(paste0(utf, rx), x, perl = TRUE, ignore.case = isTRUE(ignore_case))
      unsafe <- grepl("\\\\[AzZG]|^\\(\\*|\\(\\?[a-zA-Z]*s", rx)      # anchors / verbs / dotall defeat the prefilter
      prefilter <- if (unsafe) function(x) rep(TRUE, length(x)) else function(x) grepl(paste0(utf, "(?m)", rx), x, perl = TRUE, ignore.case = isTRUE(ignore_case))
    }
  }
  locator <- if (isTRUE(literal) && !isTRUE(ignore_case)) function(x) as.integer(regexpr(pattern, x, fixed = TRUE))
             else { rx2 <- paste0("(*UTF)(*UCP)", if (isTRUE(literal)) .quote_literal(pattern) else sub("^\\(\\*UTF\\)", "", pattern))
                    function(x) as.integer(regexpr(rx2, x, perl = TRUE, ignore.case = isTRUE(ignore_case))) }
  out <- grep_engine(files, labels, matcher, prefilter, limit, sizes = sizes, check_abort = check_abort)
  attr(out, "skipped_big") <- skipped_big; attr(out, "locator") <- locator
  out
}

# Optional accelerator: ripgrep, if the user has it on PATH (never downloaded, never required).
# Returns the same data.frame as grep_engine() or NULL when rg is unavailable. Differences to the R engine
# (documented): rg regex dialect is Rust `regex` (no look-around/backreferences), per-directory .gptrignore is
# not read, lines are matched on raw bytes (non-UTF-8 files are searched lossily).
grep_rg <- function(pattern, root, glob = NULL, ignore_case = FALSE, literal = FALSE, hidden = TRUE,
                    max_file_size = 20 * 1024^2, limit = GPTR_GREP_LIMIT, sort = "path") {
  rg <- Sys.which("rg"); if (!nzchar(rg)) return(NULL)
  sep <- "\x1e"                                                     # record separator: never in paths/code
  ign <- sub("/$", "", GPTR_DEFAULT_IGNORE)
  args <- c("--no-heading", "--line-number", "--with-filename", "--color=never", "--no-messages", "--no-require-git",
            "--field-match-separator", sep, "--path-separator", "/", "--max-count", sprintf("%d", as.integer(min(limit, .Machine$integer.max))),
            "--max-filesize", sprintf("%dK", as.integer(max_file_size / 1024)), if (hidden) "--hidden",
            if (ignore_case) "--ignore-case", if (literal) "--fixed-strings",
            as.vector(rbind("--glob", paste0("!", ifelse(grepl("/", ign), ign, paste0("**/", ign)), "/**"))),
            if (!is.null(glob) && nzchar(glob)) as.vector(rbind("--glob", strsplit(glob, ",(?![^{]*})", perl = TRUE)[[1L]])),
            "--regexp", pattern, "--", ".")
  out <- if (has_pkg("processx")) {
    r <- processx::run(rg, args, wd = root, error_on_status = FALSE, encoding = "UTF-8")
    if (!r$status %in% c(0L, 1L)) stop(sprintf("ripgrep failed: %s", trimws(r$stderr)), call. = FALSE)
    if (nzchar(r$stdout)) strsplit(r$stdout, "\n", fixed = TRUE)[[1L]] else character()
  } else {
    old <- setwd(root); on.exit(setwd(old))
    suppressWarnings(system2(rg, shQuote(args), stdout = TRUE, stderr = FALSE))
  }
  out <- mark_utf8(sub("\r$", "", out))
  if (!length(out)) return(data.frame(file = character(), abs = character(), line = integer(), text = character()))
  p1 <- regexpr(sep, out, fixed = TRUE, useBytes = TRUE)
  file <- substr(out, 1L, p1 - 1L); rest <- substring(out, p1 + 1L)
  p2 <- regexpr(sep, rest, fixed = TRUE, useBytes = TRUE)
  df <- data.frame(file = sub("^\\./", "", file), line = as.integer(substr(rest, 1L, p2 - 1L)), text = substring(rest, p2 + 1L), stringsAsFactors = FALSE)
  df <- df[order(tolower(df$file), df$file, df$line, method = "radix"), , drop = FALSE]
  reached <- nrow(df) > limit; df <- utils::head(df, limit)
  df$abs <- file.path(root, df$file); rownames(df) <- NULL
  attr(df, "limit_reached") <- reached; attr(df, "binary_skipped") <- NA; attr(df, "skipped_big") <- 0L
  df[, c("file", "abs", "line", "text")] |> structure(limit_reached = reached, binary_skipped = NA, skipped_big = 0L)
}

# Format matches like Pi (path:LINE: text / path-LINE- text); overlapping context windows are merged and
# non-adjacent blocks separated by "--" (grep convention; Pi repeats overlapping lines).
format_grep <- function(m, context = 0L, max_line = GPTR_GREP_MAX_LINE, locator = NULL) {
  if (!nrow(m)) return(list(lines = character(), truncated = FALSE))
  cap <- function(txt) {                       # long lines: keep a window around the first match visible
    n <- nchar(txt, allowNA = TRUE); long <- !is.na(n) & n > max_line
    ctr <- NULL
    if (any(long) && is.function(locator)) { ctr <- integer(length(txt)); ctr[long] <- pmax(0L, locator(txt[long]) - 1L) }
    truncate_line(txt, max_line, center = ctr)
  }
  if (context <= 0L) {
    t <- cap(m$text)
    return(list(lines = sprintf("%s:%d: %s", m$file, m$line, t), truncated = any(attr(t, "truncated"))))
  }
  out <- character(); any_trunc <- FALSE
  for (f in unique(m$file)) {
    mm <- m[m$file == f, ]
    lines <- split_lines_count(.search_text(mm$abs[1L]) %||% "")      # no phantom line after a final newline
    want <- sort(unique(unlist(lapply(mm$line, function(h) max(1L, h - context):min(length(lines), h + context)))))
    t <- cap(lines[want]); any_trunc <- any_trunc || any(attr(t, "truncated"))
    blk <- ifelse(want %in% mm$line, sprintf("%s:%d: %s", f, want, t), sprintf("%s-%d- %s", f, want, t))
    gap <- c(FALSE, diff(want) > 1L)
    blk <- as.vector(rbind(ifelse(gap, "--", NA_character_), blk)); blk <- blk[!is.na(blk)]
    out <- c(out, if (length(out)) "--", blk)
  }
  list(lines = out, truncated = any_trunc)
}

gptr_grep <- function(pattern, path = NULL, glob = NULL, ignoreCase = FALSE, literal = FALSE, context = NULL,
                      limit = NULL, output = c("content", "files", "count"), sort = c("path", "mtime", "count"),
                      cwd = getwd(), engine = "base") {
  output <- match.arg(output); sort <- match.arg(sort)
  if (sort == "count" && output == "content") output <- "count"      # "relevance" = most matching lines first
  limit <- max(1L, as.integer(limit %||% GPTR_GREP_LIMIT))
  lim_engine <- if (output == "content") limit else .Machine$integer.max
  m <- grep_files(pattern, path %||% ".", glob = glob, ignore_case = ignoreCase, literal = literal, limit = lim_engine,
                  sort = if (sort == "count") "path" else sort, engine = engine, cwd = cwd)
  if (!nrow(m)) return(tool_text("No matches found"))
  notes <- character()
  if (output == "content") {
    fm <- format_grep(m, as.integer(context %||% 0L), locator = attr(m, "locator"))
    body <- fm$lines
    if (isTRUE(attr(m, "limit_reached"))) notes <- c(notes, sprintf("%d matches limit reached. Use limit=%d for more, or refine pattern", limit, limit * 2L))
    if (fm$truncated) notes <- c(notes, sprintf("Some lines truncated to %d chars. Use read tool to see full lines", GPTR_GREP_MAX_LINE))
  } else {
    cnt <- table(factor(m$file, levels = unique(m$file)))
    if (sort == "count") cnt <- cnt[order(-as.integer(cnt), names(cnt), method = "radix")]
    body <- if (output == "files") names(cnt) else c(sprintf("%s:%d", names(cnt), as.integer(cnt)), sprintf("\nTotal: %d matching lines in %d files", sum(cnt), length(cnt)))
    if (length(body) > limit) { notes <- c(notes, sprintf("%d files limit reached. Use limit=%d for more", limit, limit * 2L)); body <- body[seq_len(limit)] }
  }
  tr <- truncate_lines_head(body, .Machine$integer.max, GPTR_MAX_BYTES)
  if (tr$truncated) notes <- c(notes, sprintf("%s limit reached", format_size(GPTR_MAX_BYTES)))
  if (attr(m, "skipped_big") > 0L) notes <- c(notes, sprintf("%d file(s) larger than 20MB skipped", attr(m, "skipped_big")))
  tool_text(.notices(paste(tr$lines, collapse = "\n"), notes), details = list(matches = nrow(m), binary_skipped = attr(m, "binary_skipped")))
}
```

### 5.6 Test and probe scripts (verbatim)

#### `tests/test-tools.R`

```r
# Track 11 test script. Run: Rscript --vanilla tests/test-tools.R   (optionally LANG=en_US.UTF-8, GPTR_BLOCK=pkg1,pkg2)
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)

n_ok <- 0L; n_fail <- 0L
ok <- function(cond, label, info = NULL) {
  if (isTRUE(cond)) { n_ok <<- n_ok + 1L; if (nzchar(Sys.getenv("VERBOSE"))) cat("  ok:", label, "\n") } else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n"); if (!is.null(info)) { cat("    got: "); utils::str(info) } }
}
eq <- function(got, want, label) ok(identical(got, want), label, if (!identical(got, want)) list(got = got, want = want))
err <- function(expr, pattern, label) { m <- tryCatch({ force(expr); "<no error>" }, error = function(e) conditionMessage(e)); ok(grepl(pattern, m, fixed = TRUE), label, m) }
rt <- function(res) result_text(res)
raw_of <- function(p) readBin(p, "raw", file.size(p) + 1)
put <- function(p, bytes) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeBin(if (is.character(bytes)) charToRaw(bytes) else bytes, p) }
section <- function(s) cat(sprintf("== %s\n", s))

cat(sprintf("R %s | LC_CTYPE=%s | UTF-8 locale: %s | blocked: %s\n", getRversion(), Sys.getlocale("LC_CTYPE"),
            l10n_info()[["UTF-8"]], Sys.getenv("GPTR_BLOCK", "(none)")))
TD <- file.path(tempdir(), "t11"); unlink(TD, recursive = TRUE); dir.create(TD)
TD <- path_real(TD)
E_ACUTE <- u_chr(0xE9); LQ <- u_chr(0x201C); RQ <- u_chr(0x201D); RSQ <- u_chr(0x2019); EMDASH <- u_chr(0x2014); NBSP <- u_chr(0xA0)

# ------------------------------------------------------------------------------------------------ core
section("core: decoding, splitting, truncation")
d <- decode_raw(charToRaw(paste0("caf", E_ACUTE))); eq(d$encoding, "UTF-8", "valid UTF-8"); eq(d$text, paste0("caf", E_ACUTE), "UTF-8 text")
d <- decode_raw(c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x"))); ok(d$bom && d$text == "x", "UTF-8 BOM stripped and remembered")
u16 <- c(as.raw(c(0xFF, 0xFE)), iconv(paste0("h", E_ACUTE, "\n"), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]])
d <- decode_raw(u16); ok(d$encoding == "UTF-16LE" && d$text == paste0("h", E_ACUTE, "\n"), "UTF-16LE with BOM decoded"); ok(!is_binary_raw(u16), "UTF-16 with BOM is not binary")
d <- decode_raw(as.raw(c(0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94))); ok(d$encoding == "CP1252" && d$text == paste0("caf", E_ACUTE, " ", LQ, "q", RQ), "CP1252 fallback (smart quotes 0x93/0x94)")
mostly <- c(charToRaw(strrep(paste0("caf", E_ACUTE, " "), 20)), as.raw(0xE9), charToRaw(" end"))
d <- decode_raw(mostly); ok(d$encoding == "UTF-8" && d$lossy && grepl(REPLACEMENT_CHAR, d$text, fixed = TRUE), "mostly-UTF-8 with a stray byte stays UTF-8 (lossy)")
ok(is_binary_raw(as.raw(c(0x41, 0, 0x42))), "NUL => binary"); err(decode_raw(as.raw(c(0x41, 0, 0x42))), "embedded NUL", "decode refuses NUL")
eq(split_lines_js("a\nb\n"), c("a", "b", ""), "JS split keeps trailing empty piece")
eq(split_lines_js(""), "", "JS split of empty string")
eq(split_lines_count("a\nb\n"), c("a", "b"), "Pi splitLinesForCounting")
x <- mark_utf8(paste0(E_ACUTE, "\nb")); p <- strsplit(x, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
ok(Encoding(p[1]) == "unknown", "PITFALL verified: strsplit(useBytes=TRUE) drops the UTF-8 mark")
eq(Encoding(split_lines_js(x))[1], "UTF-8", "split_lines_js re-marks")
eq(detect_eol("a\r\nb\nc"), "\r\n", "detect_eol CRLF first"); eq(detect_eol(paste0(E_ACUTE, "a\nb\r\n")), "\n", "detect_eol LF first (non-ASCII prefix)")
tr <- truncate_lines_head(rep("x", 2500)); ok(tr$truncated && tr$by == "lines" && tr$output_lines == 2000L, "truncate by lines")
tr <- truncate_lines_head(rep(strrep("y", 99), 1000)); ok(tr$truncated && tr$by == "bytes" && tr$output_lines == 512L, "truncate by bytes (100B/line -> 512 lines)", tr$output_lines)
tr <- truncate_lines_head(strrep("z", 60000)); ok(tr$first_line_exceeds, "first line exceeds byte limit")
tl <- truncate_line(c("short", strrep("a", 600)), 500); ok(endsWith(tl[2], "... [truncated]") && !attr(tl, "truncated")[1], "truncate_line")
tl <- truncate_line(paste0(strrep("a", 1000), "NEEDLE", strrep("b", 1000)), 500, center = 1000L); ok(grepl("NEEDLE", tl) && startsWith(tl, "..."), "truncate_line centred on match")
eq(format_size(51200), "50.0KB", "format_size")

# ------------------------------------------------------------------------------------------------ paths
section("paths")
eq(path_norm("/a/./b/../c//d/"), "/a/c/d", "lexical norm unix")
eq(path_norm("C:\\x\\..\\y\\.\\z"), "C:/y/z", "lexical norm drive letter")
eq(path_norm("C:/.."), "C:/", "cannot climb above drive root")
eq(path_norm("\\\\server\\share\\..\\x"), "//server/share/x", "UNC share is a root")
eq(path_norm("../../a"), "../../a", "relative .. kept")
eq(path_resolve("sub/../f.R", "/w"), "/w/f.R", "resolve relative")
eq(path_resolve("@src/x.R", "/w"), "/w/src/x.R", "strip @ prefix (Pi)")
eq(path_resolve(paste0("a", NBSP, "b.txt"), "/w"), "/w/a b.txt", "unicode space normalised")
eq(path_resolve("file:///tmp/a%20b.txt", "/w"), "/tmp/a b.txt", "file:// URL")
eq(path_resolve("~/x", "/w"), path_norm(path.expand("~/x")), "~ expansion (R's HOME)")
dir.create(file.path(TD, "ws/sub"), recursive = TRUE); dir.create(file.path(TD, "outside"))
file.symlink(file.path(TD, "outside"), file.path(TD, "ws/escape"))
ok(path_within(file.path(TD, "ws/sub/new.txt"), file.path(TD, "ws")), "inside workspace (non-existent file)")
ok(!path_within(file.path(TD, "ws/escape/evil.txt"), file.path(TD, "ws")), "symlink escape detected")
ok(!path_within(file.path(TD, "ws/../outside/x"), file.path(TD, "ws")), ".. escape detected")
ok(!path_within(file.path(TD, "wsX/x"), file.path(TD, "ws")), "prefix must end at a separator")
ci <- fs_case_insensitive(TD); cat("   file system case-insensitive here:", ci, "\n")
if (ci) ok(path_within(file.path(toupper(TD), "ws", "a"), file.path(TD, "ws")) || path_within(file.path(TD, "WS", "a"), file.path(TD, "ws")), "case-insensitive containment")
err(guard_write_path(file.path(TD, "ws/escape/evil.txt"), file.path(TD, "ws")), "Refusing to write outside the workspace", "guard refuses symlink escape")

# ------------------------------------------------------------------------------------------------ read
section("read")
f <- file.path(TD, "r/lines.txt"); put(f, paste0("line ", 1:3000, "\n", collapse = ""))
r <- rt(gptr_read(f)); ok(endsWith(r, "[Showing lines 1-2000 of 3001. Use offset=2001 to continue.]"), "read: line-limit notice (Pi text)", substring(r, nchar(r) - 80))
r <- rt(gptr_read(f, offset = 2990)); ok(startsWith(r, "line 2990\n") && !grepl("[", r, fixed = TRUE), "read: offset to end, no notice")
r <- rt(gptr_read(f, offset = 10, limit = 5)); eq(r, paste0(paste0("line ", 10:14, collapse = "\n"), "\n\n[2987 more lines in file. Use offset=15 to continue.]"), "read: offset+limit notice")
err(gptr_read(f, offset = 5000), "Offset 5000 is beyond end of file (3001 lines total)", "read: offset beyond EOF (Pi text)")
r <- rt(gptr_read(f, offset = 9, limit = 2, line_numbers = TRUE)); eq(r, "     9\tline 9\n    10\tline 10\n\n[2991 more lines in file. Use offset=11 to continue.]", "read: cat -n line numbers")
fb <- file.path(TD, "r/wide.txt"); put(fb, paste0(strrep("w", 199), "\n", collapse = "") |> rep(400) |> paste(collapse = ""))
r <- rt(gptr_read(fb)); ok(grepl("[Showing lines 1-256 of 401 (50.0KB limit). Use offset=257 to continue.]", r, fixed = TRUE), "read: byte-limit notice", substring(r, nchar(r) - 90))
fl <- file.path(TD, "r/oneline.txt"); put(fl, strrep(paste0(E_ACUTE, "x"), 40000))
r <- rt(gptr_read(fl)); ok(grepl("[Line 1 is 117.2KB; showing its first 50.0KB.", r, fixed = TRUE) && validUTF8(r), "read: giant first line shown partially at a UTF-8 boundary")
fc <- file.path(TD, "r/crlf.txt"); put(fc, "a\r\nb\r\n"); eq(rt(gptr_read(fc)), "a\nb\n", "read: CR of CRLF not shown")
fw <- file.path(TD, "r/win.R"); put(fw, as.raw(c(charToRaw("x <- \""), as.raw(0xE9), charToRaw("t"), as.raw(0xE9), charToRaw("\"\n"))))
r <- rt(gptr_read(fw)); ok(grepl(paste0("x <- \"", E_ACUTE, "t", E_ACUTE, "\""), r, fixed = TRUE) && grepl("[Decoded from CP1252]", r, fixed = TRUE), "read: CP1252 decoded with note")
fe <- file.path(TD, "r/empty.txt"); put(fe, raw(0)); eq(rt(gptr_read(fe)), sprintf("[File is empty: %s]", fe), "read: empty file notice")
fbin <- file.path(TD, "r/data.bin"); put(fbin, as.raw(c(1:10, 0, 1:10)))
ok(grepl("^\\[Binary file: .*data.bin \\(21B\\). Not shown as text.\\]$", rt(gptr_read(fbin))), "read: binary notice")
err(gptr_read(file.path(TD, "r")), "Is a directory", "read: directory error")
err(gptr_read(file.path(TD, "r/nope.txt")), "File not found", "read: missing file")
# big-file streaming path must equal the in-memory path
old_big <- GPTR_BIG_FILE
fbig <- file.path(TD, "r/big.txt"); put(fbig, paste0(sprintf("row %06d %s", 1:60000, E_ACUTE), "\n", collapse = ""))
a1 <- rt(gptr_read(fbig, offset = 30001, limit = 700)); a2 <- rt(gptr_read(fbig, offset = 59990))
GPTR_BIG_FILE <- 1024; b1 <- rt(gptr_read(fbig, offset = 30001, limit = 700)); b2 <- rt(gptr_read(fbig, offset = 59990)); GPTR_BIG_FILE <- old_big
eq(b1, a1, "read: streaming window == in-memory window (middle)"); eq(b2, a2, "read: streaming window == in-memory window (tail)")
# images
if (has_pkg("png")) {
  fp <- file.path(TD, "img/p.png"); dir.create(dirname(fp)); png::writePNG(array(runif(30 * 20 * 3), c(20, 30, 3)), fp)
  res <- gptr_read(fp); ok(length(res$content) == 2L && res$content[[2]]$mimeType == "image/png", "read: PNG -> image block")
  ok(identical(base64enc::base64decode(res$content[[2]]$data), raw_of(fp)[seq_len(file.size(fp))]), "read: base64 round-trips")
  ok(!grepl("\n", res$content[[2]]$data, fixed = TRUE), "read: base64 has no newlines")
  eq(as.numeric(image_dims(raw_of(fp), "image/png")), c(30, 20), "image_dims PNG")
}
if (has_pkg("jpeg")) { fj <- file.path(TD, "img/j.jpg"); jpeg::writeJPEG(array(runif(40 * 25 * 3), c(25, 40, 3)), fj); eq(as.numeric(image_dims(raw_of(fj), "image/jpeg")), c(40, 25), "image_dims JPEG"); eq(detect_image_mime(raw_of(fj)), "image/jpeg", "sniff JPEG") }
if (has_pkg("magick")) {
  im <- magick::image_blank(50, 35, "red")
  fg <- file.path(TD, "img/g.gif"); magick::image_write(im, fg, format = "gif"); eq(as.numeric(image_dims(raw_of(fg), "image/gif")), c(50, 35), "image_dims GIF")
  fwp <- file.path(TD, "img/w.webp"); magick::image_write(im, fwp, format = "webp"); eq(detect_image_mime(raw_of(fwp)), "image/webp", "sniff WebP"); eq(as.numeric(image_dims(raw_of(fwp), "image/webp")), c(50, 35), "image_dims WebP")
  fbm <- file.path(TD, "img/b.bmp"); magick::image_write(im, fbm, format = "bmp")
  res <- gptr_read(fbm); ok(res$content[[2]]$mimeType == "image/png", "read: BMP converted to PNG via magick")
  flg <- file.path(TD, "img/large.png"); magick::image_write(magick::image_blank(3000, 1000, "blue"), flg, format = "png")
  res <- gptr_read(flg); ok(grepl("original 3000x1000, displayed at 2000x667", res$content[[1]]$text, fixed = TRUE), "read: large image resized with coordinate note", res$content[[1]]$text)
}
# structured previews
fr <- file.path(TD, "d/m.rds"); dir.create(dirname(fr)); saveRDS(mtcars, fr)
r <- rt(gptr_read(fr)); ok(grepl("[R object file (.rds", r, fixed = TRUE) && grepl("Mazda RX4", r) && grepl("readRDS(", r, fixed = TRUE), "read: .rds preview")
fda <- file.path(TD, "d/ws.RData"); a_obj <- 1:3; b_obj <- iris; save(a_obj, b_obj, file = fda)
r <- rt(gptr_read(fda)); ok(grepl("b_obj: data.frame 150 x 5", r, fixed = TRUE), "read: .RData object listing", r)
if (has_pkg("arrow")) { fpq <- file.path(TD, "d/m.parquet"); arrow::write_parquet(mtcars, fpq); r <- rt(gptr_read(fpq)); ok(grepl("[Parquet file", r, fixed = TRUE) && grepl("32 rows x 11 columns", r, fixed = TRUE), "read: parquet preview", r) }
if (has_pkg("qs")) { fq <- file.path(TD, "d/m.qs"); qs::qsave(mtcars, fq, nthreads = 1L); ok(grepl("[qs file", rt(gptr_read(fq)), fixed = TRUE), "read: qs preview") }

# ------------------------------------------------------------------------------------------------ write
section("write")
ws <- file.path(TD, "ws")
res <- gptr_write("new/deep/a.R", "x <- 1\n", cwd = ws); ok(file.exists(file.path(ws, "new/deep/a.R")), "write: creates parent dirs")
eq(rt(res), "Successfully wrote 7 bytes to new/deep/a.R", "write: message")
ok(!length(list.files(file.path(ws, "new/deep"), all.files = TRUE, pattern = "gptr-")), "write: no temp file left")
eq(res$details$method, "rename", "write: atomic rename used")
fx <- file.path(ws, "run.sh"); put(fx, "echo hi\n"); Sys.chmod(fx, "755")
invisible(gptr_write("run.sh", "echo bye\n", cwd = ws)); eq(as.character(file.info(fx)$mode), "755", "write: permission bits preserved across rename")
tgt <- file.path(ws, "sub/real.txt"); put(tgt, "old\n"); file.symlink(tgt, file.path(ws, "link.txt"))
invisible(gptr_write("link.txt", "new\n", cwd = ws)); ok(nzchar(Sys.readlink(file.path(ws, "link.txt"))) && rawToChar(raw_of(tgt)[1:4]) == "new\n", "write: writes THROUGH a symlink and keeps it")
fcr <- file.path(ws, "crlf.R"); put(fcr, "a\r\nb\r\n"); gptr_write("crlf.R", "a\nb\nc\n", cwd = ws); eq(rawToChar(raw_of(fcr)[seq_len(file.size(fcr))]), "a\r\nb\r\nc\r\n", "write: eol='keep' preserves CRLF")
invisible(gptr_write("crlf.R", "a\nb\n", cwd = ws, eol = "asis")); eq(rawToChar(raw_of(fcr)[seq_len(file.size(fcr))]), "a\nb\n", "write: eol='asis' writes verbatim")
fcp <- file.path(ws, "legacy.R"); put(fcp, as.raw(c(charToRaw("s <- \""), as.raw(0xE9), charToRaw("\"\n"))))
invisible(gptr_write("legacy.R", paste0("s <- \"", E_ACUTE, E_ACUTE, "\"\n"), cwd = ws)); eq(raw_of(fcp)[seq_len(file.size(fcp))], as.raw(c(charToRaw("s <- \""), 0xE9, 0xE9, charToRaw("\"\n"))), "write: CP1252 file stays CP1252")
err(gptr_write("legacy.R", paste0("s <- \"", u_chr(0x4E2D), "\"\n"), cwd = ws), "cannot be represented in the file's encoding (CP1252)", "write: unrepresentable char refused")
eq(raw_of(fcp)[seq_len(file.size(fcp))], as.raw(c(charToRaw("s <- \""), 0xE9, 0xE9, charToRaw("\"\n"))), "write: refused write left file untouched")
fbom <- file.path(ws, "bom.csv"); put(fbom, c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("a,b\n"))); gptr_write("bom.csv", "a,b\n1,2\n", cwd = ws)
eq(raw_of(fbom)[1:3], as.raw(c(0xEF, 0xBB, 0xBF)), "write: UTF-8 BOM kept")
err(gptr_write(file.path(TD, "outside/x.txt"), "x", cwd = ws), "Refusing to write outside the workspace", "write: outside workspace refused")
hl <- file.path(ws, "hard.txt"); put(hl, "h\n"); file.link(hl, file.path(ws, "hard2.txt"))
invisible(gptr_write("hard.txt", "changed\n", cwd = ws)); ok(rawToChar(raw_of(file.path(ws, "hard2.txt"))[1:2]) == "h\n", "write: NOTE atomic rename breaks hard links (hard2 keeps old content)")

# ------------------------------------------------------------------------------------------------ edit
section("edit")
fe1 <- file.path(ws, "e1.R"); put(fe1, "f <- function(x) {\n  x + 1\n}\n\ng <- function(y) {\n  y + 1\n}\n")
res <- gptr_edit("e1.R", list(list(oldText = "  x + 1", newText = "  x + 2")), cwd = ws)
ok(startsWith(rt(res), "Successfully replaced 1 block(s) in e1.R."), "edit: success message"); ok(grepl("-  x + 1\n+  x + 2", res$details$patch, fixed = TRUE), "edit: unified patch")
err(gptr_edit("e1.R", list(list(oldText = "zzz", newText = "q")), cwd = ws), "Could not find the exact text in e1.R. The old text must match exactly including all whitespace and newlines.", "edit: not found (Pi text)")
err(gptr_edit("e1.R", list(list(oldText = "+ 1", newText = "+ 3"), list(oldText = "nope", newText = "x")), cwd = ws), "Could not find edits[1] in e1.R.", "edit: not found multi (0-based index)")
err(gptr_edit("e1.R", list(list(oldText = "function", newText = "\\(x)")), cwd = ws), "Found 2 occurrences of the text in e1.R. The text must be unique.", "edit: duplicate count")
res <- gptr_edit("e1.R", list(list(oldText = "function", newText = "fn", replaceAll = TRUE)), cwd = ws); ok(grepl("replaced 2 block", rt(res)), "edit: replaceAll")
put(fe1, "a\nb\nc\nd\n")
invisible(gptr_edit("e1.R", list(list(oldText = "a\n", newText = "A\n"), list(oldText = "d", newText = "D")), cwd = ws)); eq(rawToChar(raw_of(fe1)[1:8]), "A\nb\nc\nD\n", "edit: multi-edit against original")
err(gptr_edit("e1.R", list(list(oldText = "A\nb", newText = "x"), list(oldText = "b\nc", newText = "y")), cwd = ws), "overlap in e1.R", "edit: overlap error")
err(gptr_edit("e1.R", list(list(oldText = "", newText = "x")), cwd = ws), "oldText must not be empty in e1.R.", "edit: empty oldText")
err(gptr_edit("e1.R", list(list(oldText = "A", newText = "A")), cwd = ws), "No changes made to e1.R.", "edit: no change")
before <- raw_of(fe1); invisible(gptr_edit("e1.R", list(list(oldText = "A", newText = "Z")), cwd = ws, dry_run = TRUE)); eq(raw_of(fe1), before, "edit: dry_run leaves file untouched")
invisible(gptr_edit("e1.R", '[{"oldText":"b","newText":"B"}]', cwd = ws)); ok(grepl("B", rawToChar(raw_of(fe1)[seq_len(file.size(fe1))])), "edit: edits given as JSON string")
invisible(gptr_edit("e1.R", oldText = "c", newText = "C", cwd = ws)); ok(grepl("C", rawToChar(raw_of(fe1)[seq_len(file.size(fe1))])), "edit: legacy oldText/newText arguments")
# line endings and BOM: bytes outside the edited span are preserved exactly (mixed EOL file)
fm <- file.path(ws, "mixed.R"); put(fm, "one\r\ntwo\nthree\r\nfour\n")
invisible(gptr_edit("mixed.R", list(list(oldText = "three\nfour", newText = "3\n4")), cwd = ws))
eq(rawToChar(raw_of(fm)[seq_len(file.size(fm))]), "one\r\ntwo\n3\r\n4\n", "edit: mixed EOL preserved outside span; new text uses dominant EOL")
fb2 <- file.path(ws, "bom.R"); put(fb2, c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x <- 1\r\ny <- 2\r\n")))
invisible(gptr_edit("bom.R", list(list(oldText = "x <- 1\ny", newText = "x <- 10\ny")), cwd = ws))
eq(raw_of(fb2)[seq_len(file.size(fb2))], c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x <- 10\r\ny <- 2\r\n")), "edit: BOM + CRLF preserved, multi-line oldText with LF matched")
invisible(gptr_edit("legacy.R", list(list(oldText = paste0(E_ACUTE, E_ACUTE), newText = paste0(E_ACUTE, "!"))), cwd = ws))
eq(raw_of(fcp)[seq_len(file.size(fcp))], as.raw(c(charToRaw("s <- \""), 0xE9, charToRaw("!\"\n"))), "edit: CP1252 file round-trips")
fl2 <- file.path(ws, "lossy.R"); put(fl2, c(charToRaw(paste0("# caf", E_ACUTE, "\n")), as.raw(0xFF), charToRaw("\nx <- 1\n")))
invisible(gptr_edit("lossy.R", list(list(oldText = "x <- 1", newText = "x <- 2")), cwd = ws))
eq(raw_of(fl2)[seq_len(file.size(fl2))], c(charToRaw(paste0("# caf", E_ACUTE, "\n")), as.raw(0xFF), charToRaw("\nx <- 2\n")), "edit: stray invalid byte preserved (byte-level edit)")
ff <- file.path(ws, "fuzzy.R"); put(ff, paste0("msg <- ", LQ, "hello", RQ, "   \n# it", RSQ, "s ", EMDASH, " fine\nkeep  \t\nz <- 1\n"))
res <- gptr_edit("fuzzy.R", list(list(oldText = "msg <- \"hello\"\n# it's - fine", newText = "msg <- \"bye\"\n# it's - fine")), cwd = ws)
ok(grepl("normalisation", rt(res)), "edit: fuzzy fallback reported")
eq(rawToChar(raw_of(ff)[seq_len(file.size(ff))]), "msg <- \"bye\"\n# it's - fine\nkeep  \t\nz <- 1\n", "edit: fuzzy rewrites touched lines only; untouched trailing whitespace kept")
err(gptr_edit("fuzzy.R", list(list(oldText = "msg <- 'nope'", newText = "x")), cwd = ws, fuzzy = FALSE), "Could not find the exact text", "edit: fuzzy can be disabled")
# unified patch from edit applies with git
fg <- file.path(TD, "gitapply"); dir.create(fg); orig <- paste0("l", 1:50, "\n", collapse = ""); put(file.path(fg, "f.txt"), orig)
res <- gptr_edit("f.txt", list(list(oldText = "l10\n", newText = "ten\n"), list(oldText = "l40\nl41\n", newText = "")), cwd = fg, workspace = fg, dry_run = TRUE)
put(file.path(fg, "p.diff"), sub("^--- f.txt\n\\+\\+\\+ f.txt", "--- a/f.txt\n+++ b/f.txt", res$details$patch))
st <- suppressWarnings(system2("git", c("-C", fg, "apply", "p.diff"), stdout = TRUE, stderr = TRUE))
eq(rawToChar(raw_of(file.path(fg, "f.txt"))[seq_len(file.size(file.path(fg, "f.txt")))]), sub("l40\nl41\n", "", sub("l10\n", "ten\n", orig)), "edit: patch applies with git apply")
cat(res$details$diff, "\n")

# ------------------------------------------------------------------------------------------------ glob / gitignore / walk
section("glob / gitignore / walk")
gm <- function(g, x) glob_matcher(g)(x, basename(x))
eq(gm("*.R", c("a.R", "d/a.R", "a.r", "a.Rmd")), c(TRUE, TRUE, FALSE, FALSE), "glob *.R matches basename at any depth (fd)")
eq(gm("src/*.R", c("src/a.R", "src/x/a.R", "a/src/a.R")), c(TRUE, FALSE, FALSE), "glob with / is anchored; * does not cross /")
eq(gm("**/*.R", c("a.R", "d/e/a.R")), c(TRUE, TRUE), "glob **/ matches zero or more dirs")
eq(gm("src/**/*.R", c("src/a.R", "src/x/y/a.R", "x/src/a.R")), c(TRUE, TRUE, FALSE), "glob a/**/b")
eq(gm("*.{R,Rmd,qmd}", c("a.R", "b.Rmd", "c.qmd", "d.md")), c(TRUE, TRUE, TRUE, FALSE), "glob braces")
eq(gm("[ab].R", c("a.R", "b.R", "c.R")), c(TRUE, TRUE, FALSE), "glob class"); eq(gm("[!ab].R", c("a.R", "c.R")), c(FALSE, TRUE), "glob negated class")
eq(gm("a+b(1).R", c("a+b(1).R", "aab(1).R")), c(TRUE, FALSE), "glob escapes regex metachars")
eq(gm("data/**", c("data/x", "data/y/z", "data")), c(TRUE, TRUE, FALSE), "glob trailing /**")
eq(gm("{a,b", c("{a,b")), TRUE, "glob unbalanced brace is literal")
eq(grepl(glob2rx("*.R"), "dir/x.R") && !grepl(glob2rx("*.{R,Rmd}"), "a.R") && !grepl(glob2rx("[ab].R"), "a.R") && !grepl(glob2rx("a+b.R"), "a+b.R"), TRUE, "PITFALL verified: glob2rx crosses '/', lacks braces/classes, leaves '+' unescaped")
# synthetic repo vs git as oracle
repo <- file.path(TD, "repo"); dir.create(repo)
files <- c("a.R", "b.log", "keep.log", "build/out.o", "build/keep.txt", "doc/frotz/x.txt", "a/doc/frotz/y.txt", "src/deep/tmp.R",
           "src/deep/.hidden", "src/.gitignore", "src/gen/g.R", "src/gen/keep.R", "logs/2026/a.txt", "logs/2026/b.txt", "UPPER.LOG",
           "sp ace.txt", "star*.txt", "nested/inner/.gitignore", "nested/inner/drop.csv", "nested/inner/ok.R", "nested/drop.csv", "abc/x/y", "#hash.txt", "!bang.txt")
for (f in files) put(file.path(repo, f), "x\n")
put(file.path(repo, ".gitignore"), paste(c("# comment", "*.log", "!keep.log", "build/", "!build/keep.txt", "/doc/frotz/", "logs/**/b.txt",
                                           "sp\\ ace.txt", "star\\*.txt", "abc/**", "\\#hash.txt", "\\!bang.txt", "", "src/deep/tmp.R   "), collapse = "\n"))
put(file.path(repo, "src/.gitignore"), "gen/*\n!gen/keep.R\n")
put(file.path(repo, "nested/inner/.gitignore"), "*.csv\n")
system2("git", c("-C", repo, "init", "-q"))
git_files <- sort(system2("git", c("-C", repo, "ls-files", "--others", "--exclude-standard"), stdout = TRUE))
w <- walk_tree(repo); ours <- sort(w$rel[!w$is_dir])
eq(ours, git_files, "gitignore: walker file set == git ls-files --others --exclude-standard")
if (!identical(ours, git_files)) { cat("   only ours:", setdiff(ours, git_files), "\n   only git:", setdiff(git_files, ours), "\n") }
cat(sprintf("   git core.ignorecase=%s\n", paste(suppressWarnings(system2("git", c("-C", repo, "config", "core.ignorecase"), stdout = TRUE)), collapse = "")))
w2 <- walk_tree(file.path(repo, "src")); eq(sort(w2$rel[!w2$is_dir]), c(".gitignore", "deep/.hidden", "gen/keep.R"), "gitignore: rules of ancestor .gitignore apply when walking a subdirectory")
# symlink loop must not hang
lp <- file.path(TD, "loop"); dir.create(file.path(lp, "a"), recursive = TRUE); file.symlink(lp, file.path(lp, "a/back"))
t0 <- Sys.time(); wl <- walk_tree(lp, gitignore = FALSE); ok(as.numeric(Sys.time() - t0) < 5 && "a/back" %in% wl$rel && wl$is_link[wl$rel == "a/back"], "walk: symlinked dir listed, not followed")
wf <- walk_tree(lp, gitignore = FALSE, follow_links = TRUE); ok(nrow(wf) <= 3L, "walk: follow_links = TRUE terminates on a loop (cycle guard by canonical path)", wf$rel)
lf <- tryCatch(length(list.files(lp, recursive = TRUE, include.dirs = TRUE)), error = function(e) NA)
cat(sprintf("   list.files(recursive=TRUE) on the symlink loop returned %s entries (follows links)\n", lf))
# Pi repo oracle
pi_git <- sort(system2("git", c("-C", PI, "ls-files", "--cached", "--others", "--exclude-standard"), stdout = TRUE))
t0 <- Sys.time(); wp <- walk_tree(PI); tw <- as.numeric(Sys.time() - t0, units = "secs")
eq(sort(wp$rel[!wp$is_dir]), pi_git, sprintf("walk: Pi monorepo file set == git ls-files (%d files, %.2fs)", length(pi_git), tw))

# ------------------------------------------------------------------------------------------------ find / ls / sort
section("find / ls / sort")
fr2 <- file.path(TD, "fr"); for (f in c("f1.R", "f10.R", "f2.R", "B.R", "a.R", "sub/x.R", "sub/y.Rmd", ".hid.R")) put(file.path(fr2, f), "x\n")
Sys.setFileTime(file.path(fr2, "f2.R"), Sys.time() + 100); put(file.path(fr2, "big.R"), strrep("x", 5000))
r <- rt(gptr_find("*.R", fr2)); eq(strsplit(r, "\n")[[1]], c(".hid.R", "a.R", "B.R", "big.R", "f1.R", "f10.R", "f2.R", "sub/x.R"), "find: *.R, case-insensitive path order, hidden included")
r <- rt(gptr_find("*.R", fr2, sort = "natural")); ok(which(strsplit(r, "\n")[[1]] == "f2.R") < which(strsplit(r, "\n")[[1]] == "f10.R"), "find: natural sort f2 < f10")
r <- rt(gptr_find("*.R", fr2, sort = "mtime")); ok(startsWith(r, "f2.R  ("), "find: mtime sort newest first", r)
r <- rt(gptr_find("*", fr2, sort = "size", type = "file")); ok(startsWith(r, "big.R  (4.9KB)"), "find: size sort largest first", r)
r <- rt(gptr_find("sub/*", fr2)); eq(strsplit(r, "\n")[[1]], c("sub/x.R", "sub/y.Rmd"), "find: path pattern")
r <- rt(gptr_find("sub", fr2, type = "dir")); eq(r, "sub/", "find: directories get /")
r <- rt(gptr_find("*.R", fr2, limit = 3)); ok(grepl("[3 results limit reached. Use limit=6 for more, or refine pattern]", r, fixed = TRUE), "find: limit notice")
eq(rt(gptr_find("*.zzz", fr2)), "No files found matching pattern", "find: no results")
r <- rt(gptr_ls(fr2)); eq(strsplit(r, "\n")[[1]], c(".hid.R", "a.R", "B.R", "big.R", "f1.R", "f10.R", "f2.R", "sub/"), "ls: Pi format")
r <- rt(gptr_ls(fr2, limit = 2)); ok(grepl("[2 entries limit reached. Use limit=4 for more]", r, fixed = TRUE), "ls: limit notice")
ok(grepl("4.9KB", rt(gptr_ls(fr2, long = TRUE))), "ls: long format has sizes")
eq(order(natural_key(c("x10", "x9", "X1", "x01a"))), c(3L, 4L, 2L, 1L), "natural_key order")
if (has_pkg("stringi")) eq(stringi::stri_order(c("x10", "x9", "X1", "x01a"), opts_collator = stringi::stri_opts_collator(numeric = TRUE)), c(3L, 4L, 2L, 1L), "stringi numeric collation agrees")

# ------------------------------------------------------------------------------------------------ grep
section("grep")
gd <- file.path(TD, "g"); put(file.path(gd, "a.R"), "alpha <- 1\nbeta <- 2\n# TODO fix\ngamma <- alpha + beta\n")
put(file.path(gd, "b.txt"), paste0("Alpha\r\nx.y\r\n", E_ACUTE, "t", E_ACUTE, "\r\n")); put(file.path(gd, "bin.dat"), as.raw(c(97, 108, 112, 104, 97, 0, 1)))
put(file.path(gd, "sub/c.R"), paste0(sprintf("line %d", 1:12), "\n", collapse = "")); put(file.path(gd, ".gitignore"), "ignored.R\n"); put(file.path(gd, "ignored.R"), "alpha\n")
put(file.path(gd, "long.js"), paste0(strrep("x", 3000), "needle", strrep("y", 3000), "\n"))
eq(rt(gptr_grep("alpha", gd)), "a.R:1: alpha <- 1\na.R:4: gamma <- alpha + beta", "grep: basic, binary + ignored skipped, sorted")
gb <- file.path(TD, "gbom"); put(file.path(gb, "bom.R"), c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw(paste0("x", E_ACUTE, "yz <- 1\n"))))
put(file.path(gb, "u16.txt"), c(as.raw(c(0xFF, 0xFE)), iconv("u16 needle\r\n", "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]))
eq(rt(gptr_grep(paste0("^x", E_ACUTE, "yz"), gb)), paste0("bom.R:1: x", E_ACUTE, "yz <- 1"), "grep: UTF-8 BOM stripped (^ anchors at first char)")
eq(rt(gptr_grep("needle$", gb)), "u16.txt:1: u16 needle", "grep: UTF-16LE file searched (ripgrep BOM sniffing parity)")
put(file.path(gb, "legacy.R"), as.raw(c(charToRaw("# caf"), 0xE9, charToRaw(" legacyword\n"))))
eq(rt(gptr_grep(paste0(E_ACUTE, " legacy"), gb)), paste0("legacy.R:1: # caf", E_ACUTE, " legacyword"), "grep: CP1252 file decoded before matching")
eq(rt(gptr_grep("alpha", gd, ignoreCase = TRUE)), "a.R:1: alpha <- 1\na.R:4: gamma <- alpha + beta\nb.txt:1: Alpha", "grep: ignoreCase")
eq(rt(gptr_grep("x.y", gd, literal = TRUE)), "b.txt:2: x.y", "grep: literal (and CRLF stripped)")
eq(rt(gptr_grep("X.Y", gd, literal = TRUE, ignoreCase = TRUE)), "b.txt:2: x.y", "grep: literal + ignoreCase via \\Q..\\E")
eq(rt(gptr_grep("y$", gd, glob = "*.txt")), "b.txt:2: x.y", "grep: $ anchors work on CRLF files")
eq(rt(gptr_grep(paste0(E_ACUTE, "t"), gd)), paste0("b.txt:3: ", E_ACUTE, "t", E_ACUTE), "grep: UTF-8 pattern")
eq(rt(gptr_grep("line (3|5|12)$", gd, context = 1)), "sub/c.R-2- line 2\nsub/c.R:3: line 3\nsub/c.R-4- line 4\nsub/c.R:5: line 5\nsub/c.R-6- line 6\n--\nsub/c.R-11- line 11\nsub/c.R:12: line 12", "grep: context merged with -- separators")
r <- rt(gptr_grep("line", gd, limit = 3)); ok(grepl("[3 matches limit reached. Use limit=6 for more, or refine pattern]", r, fixed = TRUE), "grep: limit notice")
eq(rt(gptr_grep("alpha|line", gd, output = "files")), "a.R\nsub/c.R", "grep: files output")
ok(grepl("sub/c.R:12\n\nTotal: 14 matching lines in 2 files", rt(gptr_grep("alpha|line", gd, output = "count")), fixed = TRUE), "grep: count output")
eq(strsplit(rt(gptr_grep("alpha|line", gd, output = "files", sort = "count")), "\n")[[1]], c("sub/c.R", "a.R"), "grep: files ranked by match count (relevance)")
r <- rt(gptr_grep("needle", gd)); ok(grepl("needle", r) && grepl("Some lines truncated to 500 chars", r, fixed = TRUE), "grep: long line window keeps the match visible")
err(gptr_grep("a(", gd), "regex parse error", "grep: invalid regex message")
eq(rt(gptr_grep("\\x{E9}t", gd)), paste0("b.txt:3: ", E_ACUTE, "t", E_ACUTE), "grep: \\x{..} escapes accepted (UTF mode forced)")
eq(rt(gptr_grep("^\\w+$", gd, glob = "*.txt")), paste0("b.txt:1: Alpha\nb.txt:3: ", E_ACUTE, "t", E_ACUTE), "grep: \\w is Unicode-aware (UCP), like ripgrep")
eq(rt(gptr_grep("zzz", gd)), "No matches found", "grep: no matches")
eq(rt(gptr_grep("beta", file.path(gd, "a.R"))), "a.R:2: beta <- 2\na.R:4: gamma <- alpha + beta", "grep: single file path")
eq(rt(gptr_grep("alpha", gd, glob = "!*.txt", ignoreCase = TRUE)), "a.R:1: alpha <- 1\na.R:4: gamma <- alpha + beta", "grep: negative glob")
if (has_pkg("stringi")) eq(rt(gptr_grep("alpha|line 1\\b", gd, engine = "stringi")), rt(gptr_grep("alpha|line 1\\b", gd)), "grep: stringi engine == base engine")
if (nzchar(Sys.which("rg"))) eq(rt(gptr_grep("alpha|line 1\\b", gd, engine = "rg", ignoreCase = TRUE, context = 1)), rt(gptr_grep("alpha|line 1\\b", gd, ignoreCase = TRUE, context = 1)), "grep: optional ripgrep engine == base engine")
# ripgrep oracle on the Pi monorepo: same (file, line) set
if (nzchar(Sys.which("rg"))) {
  for (pat in c("DEFAULT_MAX_BYTES", "export (async )?function \\w+\\(", "TODO|FIXME", "^import .* from \"\\./")) {
    rg <- system2("rg", c("--line-number", "--no-heading", "--with-filename", "--color=never", "--hidden", "-g", "!.git", "--", shQuote(pat), shQuote(PI)), stdout = TRUE)
    rg <- sub(paste0("^", PI, "/"), "", rg); rg_key <- sort(sub("^([^:]+:[0-9]+):.*$", "\\1", rg))
    m <- grep_files(pat, PI, limit = 1e6); our_key <- sort(paste0(m$file, ":", m$line))
    eq(our_key, rg_key, sprintf("grep oracle vs ripgrep: '%s' (%d lines)", pat, length(rg_key)))
  }
}

cat(sprintf("\nRESULT: %d passed, %d failed\n", n_ok, n_fail))
```

#### `tests/probe-platform.R`

```r
# Track 11: R platform behaviours that shape the file tools. Run in C and UTF-8 locales.
cat(sprintf("R %s | %s | LC_CTYPE=%s | UTF-8 locale=%s\n", getRversion(), R.version$platform, Sys.getlocale("LC_CTYPE"), l10n_info()[["UTF-8"]]))
td <- tempfile("probe"); dir.create(td); setwd(td)
hex <- function(p) paste(sprintf("%02x", as.integer(readBin(p, "raw", file.size(p)))), collapse = " ")
e <- intToUtf8(0xE9); Encoding(e) <- "UTF-8"; s <- paste0("caf", e)
say <- function(label, value) cat(sprintf("  %-58s %s\n", label, paste(format(value), collapse = " | ")))

cat("\n[W1] writing a UTF-8 string\n")
writeLines(s, "wl.txt");                       say("writeLines(x, path)                 ->", hex("wl.txt"))
writeLines(s, "wlb.txt", useBytes = TRUE);     say("writeLines(x, path, useBytes = TRUE) ->", hex("wlb.txt"))
cat(s, file = "cat.txt");                      say("cat(x, file = path)                 ->", hex("cat.txt"))
con <- file("wb.txt", "wb"); writeBin(charToRaw(s), con); close(con); say("writeBin(charToRaw(x))              ->", hex("wb.txt"))
con <- file("wenc.txt", "w", encoding = "UTF-8"); writeLines(s, con); close(con); say("file(encoding='UTF-8') + writeLines  ->", hex("wenc.txt"))
l1 <- intToUtf8(c(0x4E2D, 0x6587)); Encoding(l1) <- "UTF-8"
r <- tryCatch({ con <- file("lat.txt", "w", encoding = "latin1"); writeLines(l1, con); close(con); hex("lat.txt") }, warning = function(w) paste("WARNING:", conditionMessage(w)), error = function(e) paste("ERROR:", conditionMessage(e)))
say("file(encoding='latin1') + writeLines(CJK)", r)

cat("\n[R1] reading\n")
writeBin(charToRaw("a\rb\nc"), "cr.txt")
say("readLines('a\\rb\\nc') (lone CR)", deparse(readLines("cr.txt", warn = FALSE)))
say("JS/Pi split('\\n') equivalent", deparse(strsplit("a\rb\nc", "\n", fixed = TRUE)[[1]]))
writeBin(as.raw(c(0x61, 0x62, 0x00, 0x63, 0x64, 0x0a, 0x65)), "nul.txt")
r <- withCallingHandlers(readLines("nul.txt"), warning = function(w) { cat("    warning:", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
say("readLines on 'ab\\0cd\\ne'", deparse(r))
r <- withCallingHandlers(readChar("nul.txt", 7, useBytes = TRUE), warning = function(w) { cat("    warning:", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
say("readChar(path, 7, useBytes = TRUE) (nchar bytes)", c(deparse(r), nchar(r, "bytes")))
say("rawToChar on the same bytes", tryCatch(rawToChar(readBin("nul.txt", "raw", 7)), error = function(e) paste("ERROR:", conditionMessage(e))))
writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x,y\n")), "bom.csv")
say("readLines on UTF-8 BOM file: first char code", utf8ToInt(enc2utf8(readLines("bom.csv", encoding = "UTF-8")))[1])
say("readLines(file(encoding='UTF-8-BOM')) first char", utf8ToInt(readLines(file("bom.csv", encoding = "UTF-8-BOM")))[1])
writeBin(charToRaw(s), "u8.txt")
x <- readLines(file("u8.txt", encoding = "UTF-8")); say("readLines(file(encoding='UTF-8')) -> bytes / Encoding", c(paste(as.integer(charToRaw(x)), collapse = " "), Encoding(x)))
x <- readLines("u8.txt", encoding = "UTF-8");       say("readLines(path, encoding='UTF-8')  -> bytes / Encoding", c(paste(as.integer(charToRaw(x)), collapse = " "), Encoding(x)))
u <- rawToChar(charToRaw(s));                       say("enc2utf8(<unmarked valid UTF-8>) bytes", paste(as.integer(charToRaw(enc2utf8(u))), collapse = " "))

cat("\n[P1] paths\n")
say("normalizePath('no/such/../file', mustWork=FALSE)", normalizePath("no/such/../file", mustWork = FALSE))
say("normalizePath('/tmp/../tmp/./x/../y', mustWork=FALSE)", normalizePath("/tmp/../tmp/./x/../y", mustWork = FALSE))
say("normalizePath(tempdir())", normalizePath(tempdir()))
say("normalizePath(toupper(tempdir()))  (case-insens. FS)", tryCatch(normalizePath(toupper(tempdir()), mustWork = TRUE), error = function(e) paste("ERROR:", conditionMessage(e))))
say("file.exists(toupper(tempdir()))", file.exists(toupper(tempdir())))
say("path.expand('~/x'), path.expand('~user/x')", c(path.expand("~/x"), path.expand("~nosuchuser/x")))
dir.create("real"); writeLines("t", "real/t.txt"); file.symlink(file.path(td, "real"), "lnk")
say("normalizePath('lnk/t.txt') resolves the symlink", normalizePath("lnk/t.txt"))
say("Sys.readlink(c('lnk','real','missing'))", deparse(Sys.readlink(c("lnk", "real", "missing"))))
say("basename/dirname of 'a/b/' and 'C:/x/y'", c(basename("a/b/"), dirname("a/b/"), basename("C:/x/y"), dirname("C:/x/y")))

cat("\n[F1] file.rename semantics (POSIX rename(2))\n")
writeLines("old", "t1.txt"); writeLines("new", "t2.txt")
say("rename over existing target", c(file.rename("t2.txt", "t1.txt"), readLines("t1.txt")))
writeLines("target", "tgt.txt"); file.symlink(file.path(td, "tgt.txt"), "sl.txt"); writeLines("via rename", "tmp.txt"); file.rename("tmp.txt", "sl.txt")
say("rename onto a symlink: link still a link? target content", c(nzchar(Sys.readlink("sl.txt")), readLines("tgt.txt")))
writeLines("h", "h1.txt"); file.link("h1.txt", "h2.txt"); writeLines("new", "tmp2.txt"); file.rename("tmp2.txt", "h1.txt")
say("rename onto a hard link: other name keeps old content", readLines("h2.txt"))
writeLines("x", "mode.sh"); Sys.chmod("mode.sh", "755"); writeLines("y", "tmp3.txt"); file.rename("tmp3.txt", "mode.sh")
say("rename onto a 755 file: resulting mode", format(file.info("mode.sh")$mode))
dir.create("d1"); dir.create("d2"); writeLines("z", "d2/f")
say("rename dir onto a NON-empty dir", suppressWarnings(file.rename("d1", "d2")))
say("file.rename(tempfile in tempdir(), cwd) same volume?", file.rename({ f <- tempfile(); writeLines("q", f); f }, "moved.txt"))

cat("\n[S1] sorting is locale dependent\n")
v <- c("B.R", "a.R", "_c.R", "Z.R", "b10.R", "b9.R", "\u00e9.R")
say("sort(v)", sort(v))
say("v[order(v, method = 'radix')]", v[order(v, method = "radix")])

cat("\n[V1] vroom ALTREP keeps the file open (Windows: blocks rename/delete of that file)\n")
big <- file.path(td, "v.txt"); writeLines(rep("line", 1e5), big)
open_files <- function() { o <- suppressWarnings(system2("lsof", c("-p", Sys.getpid()), stdout = TRUE)); sum(grepl("v.txt", o, fixed = TRUE)) }
x <- vroom::vroom_lines(big, altrep = TRUE, progress = FALSE, num_threads = 1); say("after vroom_lines(altrep=TRUE): open handles on v.txt", open_files())
rm(x); invisible(gc()); say("after rm(x); gc()", open_files())
x <- vroom::vroom_lines(big, altrep = FALSE, progress = FALSE, num_threads = 1); say("after vroom_lines(altrep=FALSE)", open_files())
x <- data.table::fread(big, sep = "\n", header = FALSE, showProgress = FALSE, nThread = 1); say("after data.table::fread (mmap)", open_files())
```

### 5.7 Benchmark scripts (verbatim)

`mkcorpus.R` (from the interrupted earlier run; re-run outputs verified: 14,774,596 bytes / 422,246 lines and 147,745,960 bytes):

```r
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
W  <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11/data"
fl <- list.files(PI, pattern = "\\.ts$", recursive = TRUE, full.names = TRUE)
fl <- fl[!grepl("/(node_modules|\\.git)/", fl)]
cat("ts files:", length(fl), "\n")
big <- file.path(W, "big.ts")
out <- file(big, "wb")
for (f in fl) { r <- readBin(f, "raw", file.size(f)); writeBin(r, out); if (length(r) && r[length(r)] != as.raw(10L)) writeBin(as.raw(10L), out) }
close(out)
cat("big.ts bytes:", file.size(big), "\n")
r <- readBin(big, "raw", file.size(big))
cat("big.ts lines:", sum(r == as.raw(10L)), "\n")
big10 <- file.path(W, "big10.ts")
out <- file(big10, "wb"); for (i in 1:10) writeBin(r, out); close(out)
cat("big10.ts bytes:", file.size(big10), "\n")
```

#### `bench/bench-read2.R`

```r
# Track 11: read-window benchmark v2 (fixes the UTF-8 re-mark bug of the interrupted v1 run).
# Each impl returns list(lines = <window>, total = <total line count or NA>).
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11/data"
big <- file.path(W, "big.ts"); big10 <- file.path(W, "big10.ts")
NL <- as.raw(10L)
tm <- function(f, times) { t <- vapply(seq_len(times), function(i) { gc(FALSE); system.time(f())[["elapsed"]] }, 0); median(t) }
mk <- function(x) { Encoding(x) <- "UTF-8"; x }

# base: whole file readBin, newline index, slice the window bytes, split
rd_readBin <- function(f, offset, limit) {
  r <- readBin(f, "raw", file.size(f)); nl <- which(r == NL); n <- length(nl)
  total <- n + (length(r) > 0L && r[length(r)] != NL)
  s <- if (offset == 1L) 1L else nl[offset - 1L] + 1L
  last <- min(offset + limit - 1L, total)
  e <- if (last <= n) nl[last] - 1L else length(r)
  list(lines = mk(strsplit(paste0(rawToChar(r[s:e]), "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1]]), total = total)
}
# base: whole file as ONE string, split everything (what Pi does in JS)
rd_split_all <- function(f, offset, limit) {
  x <- strsplit(rawToChar(readBin(f, "raw", file.size(f))), "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  list(lines = mk(x[offset:min(length(x), offset + limit - 1L)]), total = length(x))
}
# base: streaming chunks (bounded memory), newline index per chunk, then seek + read the window
rd_stream <- function(f, offset, limit, chunk = 8L * 1024L^2) {
  con <- file(f, "rb"); on.exit(close(con))
  want_s <- offset - 1L; want_e <- offset + limit - 1L       # need newline #(offset-1) and #(offset+limit-1)
  seen <- 0L; pos <- 0; s_byte <- if (offset == 1L) 0 else NA_real_; e_byte <- NA_real_; last <- NL
  repeat {
    b <- readBin(con, "raw", chunk); if (!length(b)) break
    nl <- which(b == NL); k <- length(nl)
    if (is.na(s_byte) && seen + k >= want_s) s_byte <- pos + nl[want_s - seen]
    if (is.na(e_byte) && seen + k >= want_e) e_byte <- pos + nl[want_e - seen] - 1
    seen <- seen + k; pos <- pos + length(b); last <- b[length(b)]
  }
  total <- seen + (pos > 0 && last != NL)
  if (is.na(e_byte)) e_byte <- pos
  seek(con, s_byte, rw = "read"); w <- readBin(con, "raw", e_byte - s_byte)
  list(lines = mk(strsplit(paste0(rawToChar(w), "\n"), "\n", fixed = TRUE, useBytes = TRUE)[[1]]), total = total)
}
# base: text connection, skip then read (no total)
rd_readLines_skip <- function(f, offset, limit) {
  con <- file(f, "rb"); on.exit(close(con))
  if (offset > 1L) { left <- offset - 1L; while (left > 0L) { k <- min(left, 50000L); left <- left - length(readLines(con, n = k, warn = FALSE)) ; if (k == 0) break } }
  list(lines = readLines(con, n = limit, warn = FALSE, encoding = "UTF-8"), total = NA)
}
rd_readLines_all <- function(f, offset, limit) { x <- readLines(f, warn = FALSE, encoding = "UTF-8"); list(lines = x[offset:min(length(x), offset + limit - 1L)], total = length(x)) }
rd_scan <- function(f, offset, limit) list(lines = scan(f, what = "", sep = "\n", skip = offset - 1L, nlines = limit, quote = "", quiet = TRUE, blank.lines.skip = FALSE, comment.char = "", allowEscapes = FALSE, encoding = "UTF-8", na.strings = character(), strip.white = FALSE), total = NA)
rd_stringi <- function(f, offset, limit) { x <- stringi::stri_read_lines(f, encoding = "UTF-8"); list(lines = x[offset:min(length(x), offset + limit - 1L)], total = length(x)) }
rd_fread <- function(f, offset, limit) list(lines = data.table::fread(f, sep = "\n", header = FALSE, quote = "", skip = offset - 1L, nrows = limit, strip.white = FALSE, blank.lines.skip = FALSE, encoding = "UTF-8", showProgress = FALSE, colClasses = "character", nThread = 2L)[[1]], total = NA)
rd_vroom <- function(f, offset, limit) list(lines = vroom::vroom_lines(f, skip = offset - 1L, n_max = limit, progress = FALSE, altrep = FALSE, num_threads = 2L), total = NA)
rd_vroom_altrep <- function(f, offset, limit) { x <- vroom::vroom_lines(f, altrep = TRUE, progress = FALSE, num_threads = 2L); n <- length(x); out <- x[offset:min(n, offset + limit - 1L)]; rm(x); list(lines = out, total = n) }
rd_brio_n <- function(f, offset, limit) { x <- brio::read_lines(f, n = offset + limit - 1L); list(lines = x[offset:length(x)], total = NA) }
rd_readr <- function(f, offset, limit) list(lines = readr::read_lines(f, skip = offset - 1L, n_max = limit, progress = FALSE, lazy = FALSE, skip_empty_rows = FALSE, num_threads = 2L), total = NA)

impl <- list(readBin_index = rd_readBin, split_all = rd_split_all, stream_8MB = rd_stream, readLines_skip = rd_readLines_skip,
             readLines_all = rd_readLines_all, scan = rd_scan, stringi_read_lines = rd_stringi, fread = rd_fread,
             vroom_lines = rd_vroom, vroom_altrep_len = rd_vroom_altrep, brio_n = rd_brio_n, readr = rd_readr)
cases <- list(
  list(name = "15MB head",   f = big,   offset = 1L,       limit = 2000L, times = 5L),
  list(name = "15MB middle", f = big,   offset = 200000L,  limit = 2000L, times = 5L),
  list(name = "15MB tail",   f = big,   offset = 420000L,  limit = 2000L, times = 5L),
  list(name = "148MB head",  f = big10, offset = 1L,       limit = 2000L, times = 3L),
  list(name = "148MB tail",  f = big10, offset = 4200000L, limit = 2000L, times = 3L))
res <- list()
for (cs in cases) {
  ref <- rd_readLines_all(cs$f, cs$offset, cs$limit)
  for (nm in names(impl)) {
    got <- tryCatch(impl[[nm]](cs$f, cs$offset, cs$limit), error = function(e) e)
    if (inherits(got, "error")) { res[[length(res) + 1]] <- data.frame(case = cs$name, impl = nm, ms = NA, same = NA, total = NA); next }
    same <- identical(mk(as.character(got$lines)), mk(ref$lines))
    t <- tm(function() impl[[nm]](cs$f, cs$offset, cs$limit), cs$times) * 1000
    res[[length(res) + 1]] <- data.frame(case = cs$name, impl = nm, ms = round(t), same = same,
                                         total = if (is.na(got$total)) "-" else as.character(got$total == ref$total))
  }
}
res <- do.call(rbind, res)
wide <- reshape(res[, c("case", "impl", "ms")], idvar = "impl", timevar = "case", direction = "wide")
names(wide) <- sub("^ms\\.", "", names(wide))
cat("R", R.version$major, R.version$minor, " locale:", Sys.getlocale("LC_CTYPE"), "\n")
cat("big.ts:", file.size(big), "bytes; big10.ts:", file.size(big10), "bytes\n\n")
print(wide, row.names = FALSE)
cat("\nall windows identical to readLines reference:", all(res$same, na.rm = TRUE), "; failures:", sum(is.na(res$same)), "\n")
cat("total-line counts correct where provided:", all(res$total %in% c("TRUE", "-")), "\n")
saveRDS(res, file.path(W, "bench-read2.rds"))
```

#### `bench/bench-readtool.R`

```r
# Track 11: the read tool end to end + cost of line numbers.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)
ROUNDS <- as.integer(Sys.getenv("ROUNDS", "5"))
st <- function(expr) { e <- substitute(expr); pf <- parent.frame(); median(vapply(seq_len(ROUNDS), function(i) { gc(FALSE); system.time(eval(e, pf))[["elapsed"]] }, 0)) * 1000 }
cat("load average:", system("uptime", intern = TRUE), "\n")
b1 <- file.path(W, "data/big.ts"); b10 <- file.path(W, "data/big10.ts")
cat(sprintf("gptr_read, 14.8 MB file (in-memory path):   head %5.0f ms | offset=200000 %5.0f ms | offset=420000 limit=100 %5.0f ms\n",
            st(gptr_read(b1)), st(gptr_read(b1, offset = 200000)), st(gptr_read(b1, offset = 420000, limit = 100))))
cat(sprintf("gptr_read, 148 MB file (streaming index):   head %5.0f ms | offset=2000000 %5.0f ms | offset=4200000 limit=100 %5.0f ms\n",
            st(gptr_read(b10)), st(gptr_read(b10, offset = 2000000)), st(gptr_read(b10, offset = 4200000, limit = 100))))
src <- file.path(PI, "packages/coding-agent/src/core/tools/edit-diff.ts")
cat(sprintf("gptr_read, 556-line source file:            %5.1f ms (line numbers: %5.1f ms)\n", st(gptr_read(src)), st(gptr_read(src, line_numbers = TRUE))))
fpq <- tempfile(fileext = ".parquet"); arrow::write_parquet(data.frame(a = 1:1e6, b = rnorm(1e6), c = sample(letters, 1e6, TRUE)), fpq)
frds <- tempfile(fileext = ".rds"); saveRDS(data.frame(a = 1:1e6, b = rnorm(1e6)), frds)
cat(sprintf("gptr_read preview: parquet 1e6 rows %5.0f ms | rds 1e6 rows %5.0f ms\n", st(gptr_read(fpq)), st(gptr_read(frds))))
if (has_pkg("magick")) { fimg <- tempfile(fileext = ".png"); magick::image_write(magick::image_noise(magick::image_blank(3000, 2000, "gray")), fimg, format = "png")
  cat(sprintf("gptr_read image: 3000x2000 noisy PNG (%.1f MB) -> resize+encode %5.0f ms\n", file.size(fimg) / 1024^2, st(gptr_read(fimg)))) }

# line-number overhead on the Pi corpus: bytes of the read output with and without cat -n numbering
w <- walk_tree(PI); fs <- file.path(PI, w$rel[!w$is_dir & grepl("\\.(ts|md|json)$", w$rel)])
raw_b <- 0; num_b <- 0; lines_total <- 0
for (f in fs) { r <- read_text_lines(f, 1L, 2000L); if (isTRUE(r$binary)) next; l <- r$lines; lines_total <- lines_total + length(l)
  raw_b <- raw_b + sum(nbytes(l)) + length(l); num_b <- num_b + sum(nbytes(number_lines(l, 1L))) + length(l) }
cat(sprintf("line numbers on %d files / %d lines: %.1f MB -> %.1f MB (+%.1f%%, +%.1f bytes/line)\n", length(fs), lines_total, raw_b / 1024^2, num_b / 1024^2, 100 * (num_b / raw_b - 1), (num_b - raw_b) / lines_total))
```

#### `bench/bench-readfiles.R`

```r
# Track 11: read MANY small files into strings (the grep inner loop). Pi monorepo, 2,125 files, 25.9 MB.
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)
ROUNDS <- as.integer(Sys.getenv("ROUNDS", "7"))
cat("load average:", system("uptime", intern = TRUE), "\n")
wk <- walk_tree(PI); files <- file.path(PI, sort(wk$rel[!wk$is_dir])); sizes <- file.size(files)
cat(sprintf("%d files, %.1f MB\n", length(files), sum(sizes) / 1024^2))
nul_safe <- function(b) tryCatch(rawToChar(b), error = function(e) NA_character_)
impl <- list(
  readBin_path_rawToChar = function() vapply(seq_along(files), function(k) nul_safe(readBin(files[k], "raw", sizes[k])), ""),
  file_raw_TRUE_readBin  = function() vapply(seq_along(files), function(k) { con <- file(files[k], "rb", raw = TRUE); on.exit(close(con)); nul_safe(readBin(con, "raw", sizes[k])) }, ""),
  readChar_path_useBytes = function() vapply(seq_along(files), function(k) { x <- suppressWarnings(readChar(files[k], sizes[k], useBytes = TRUE)); if (!length(x)) "" else if (nchar(x, "bytes") < sizes[k]) NA_character_ else x }, ""),
  readChar_file_raw      = function() vapply(seq_along(files), function(k) { con <- file(files[k], "rb", raw = TRUE); on.exit(close(con)); x <- suppressWarnings(readChar(con, sizes[k], useBytes = TRUE)); if (!length(x)) "" else if (nchar(x, "bytes") < sizes[k]) NA_character_ else x }, ""),
  readLines_path         = function() vapply(files, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"), "", USE.NAMES = FALSE),
  brio_read_file         = function() vapply(files, function(f) { x <- tryCatch(brio::read_file(f), error = function(e) NA_character_); if (length(x)) x else "" }, "", USE.NAMES = FALSE),
  brio_read_file_raw     = function() vapply(files, function(f) nul_safe(brio::read_file_raw(f)), "", USE.NAMES = FALSE),
  stringi_read_raw       = function() vapply(files, function(f) nul_safe(stringi::stri_read_raw(f)), "", USE.NAMES = FALSE)
)
res <- list(); out <- list()
for (r in seq_len(ROUNDS)) for (nm in names(impl)) { gc(FALSE); t <- system.time(x <- impl[[nm]]())[["elapsed"]]; res[[length(res) + 1]] <- data.frame(impl = nm, ms = t * 1000); if (r == 1) out[[nm]] <- x }
agg <- aggregate(ms ~ impl, do.call(rbind, res), median); agg$ms <- round(agg$ms)
ref <- out$readBin_path_rawToChar
agg$n_binary <- vapply(agg$impl, function(nm) sum(is.na(out[[nm]])), 0L)
agg$same_as_readBin <- vapply(agg$impl, function(nm) { a <- out[[nm]]; ok <- !is.na(ref) & !is.na(a); sum(a[ok] != ref[ok]) == 0 && identical(is.na(a), is.na(ref)) }, NA)
print(agg[order(agg$ms), ], row.names = FALSE)
cat("\nnote: readLines_path drops the final newline / normalises CRLF, so its strings differ by design\n")
# one big string vs many
txt <- ref[!is.na(ref)]
st <- function(expr) { e <- substitute(expr); pf <- parent.frame(); median(vapply(seq_len(ROUNDS), function(i) { gc(FALSE); system.time(eval(e, pf))[["elapsed"]] }, 0)) * 1000 }
raws <- lapply(seq_along(files), function(k) readBin(files[k], "raw", sizes[k])); raws <- raws[!is.na(ref)]
cat(sprintf("\nrawToChar per file (%d calls)      %6.0f ms\n", length(raws), st(vapply(raws, rawToChar, ""))))
big <- unlist(raws)
cat(sprintf("rawToChar once on %.1f MB           %6.0f ms\n", length(big) / 1024^2, st(rawToChar(big))))
cat(sprintf("validUTF8 on all texts               %6.0f ms\n", st(validUTF8(txt))))
cat(sprintf("Encoding(txt) <- 'UTF-8'             %6.0f ms\n", st({ y <- txt; Encoding(y) <- "UTF-8" })))
```

#### `bench/bench-grep.R`

```r
# Track 11: grep engine benchmark on the Pi monorepo (2,125 files). Interleaved rounds, median ms.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)
suppressPackageStartupMessages({ library(stringi); library(data.table) })
setDTthreads(2L)
ROUNDS <- as.integer(Sys.getenv("ROUNDS", "5"))
cat("load average:", system("uptime", intern = TRUE), "\n")

wk <- walk_tree(PI); files_rel <- sort(wk$rel[!wk$is_dir]); files <- file.path(PI, files_rel)
cat(sprintf("corpus: %d files, %.1f MB (walker, gitignore-aware)\n", length(files), sum(file.size(files)) / 1024^2))

key <- function(f, l) if (!length(f)) character() else sort(paste0(f, ":", l))   # paste0() of zero-length vectors returns ":"
impl <- list(
  gptr_base = function(p, ic) { m <- grep_files(p, PI, ignore_case = ic, limit = 1e7); key(m$file, m$line) },
  gptr_stringi = function(p, ic) { m <- grep_files(p, PI, ignore_case = ic, limit = 1e7, engine = "stringi"); key(m$file, m$line) },
  naive_readLines = function(p, ic) {                  # per file: readLines + grepl (no binary check, no prefilter)
    out <- lapply(seq_along(files), function(i) { x <- readLines(files[i], warn = FALSE, encoding = "UTF-8"); h <- which(grepl(p, x, perl = TRUE, ignore.case = ic)); if (length(h)) paste0(files_rel[i], ":", h) })
    sort(unlist(out)) },
  naive_stri_read_lines = function(p, ic) {
    out <- lapply(seq_along(files), function(i) { x <- tryCatch(stri_read_lines(files[i]), error = function(e) character()); h <- which(stri_detect_regex(x, p, case_insensitive = ic)); if (length(h)) paste0(files_rel[i], ":", h) })
    sort(unlist(out)) },
  all_lines_one_grepl = function(p, ic) {              # read everything, split everything, ONE grepl call
    raw <- lapply(files, function(f) readBin(f, "raw", file.size(f))); bin <- vapply(raw, function(b) any(b == as.raw(0L)), NA)
    txt <- vapply(raw[!bin], rawToChar, ""); fr <- files_rel[!bin]
    pcs <- strsplit(txt, "\n", fixed = TRUE, useBytes = TRUE); l <- unlist(pcs); Encoding(l) <- "UTF-8"
    h <- which(grepl(paste0("(*UTF)", p), l, perl = TRUE, ignore.case = ic))
    key(rep(fr, lengths(pcs))[h], sequence(lengths(pcs))[h]) },
  fread_lines = function(p, ic) {                      # data.table::fread(sep = "\n") per file
    out <- lapply(seq_along(files), function(i) { x <- tryCatch(fread(files[i], sep = "\n", header = FALSE, quote = "", strip.white = FALSE, blank.lines.skip = FALSE, colClasses = "character", showProgress = FALSE, encoding = "UTF-8")[[1]], error = function(e) character(), warning = function(w) character())
      h <- which(grepl(p, x, perl = TRUE, ignore.case = ic)); if (length(h)) paste0(files_rel[i], ":", h) })
    sort(unlist(out)) },
  rg_system2 = function(p, ic) {                       # optional accelerator: ripgrep, plain output
    o <- suppressWarnings(system2("rg", c("--no-heading", "--line-number", "--with-filename", "--color=never", "--hidden", "-g", shQuote("!.git"), if (ic) "-i", "--", shQuote(p), shQuote(PI)), stdout = TRUE))
    if (!length(o)) return(character()); o <- substring(o, nchar(PI) + 2L); sort(sub("^([^:]+:[0-9]+):.*$", "\\1", o)) },
  rg_json = function(p, ic) {                          # ripgrep --json parsed with jsonlite (robust to odd bytes)
    o <- suppressWarnings(system2("rg", c("--json", "--hidden", "-g", shQuote("!.git"), if (ic) "-i", "--", shQuote(p), shQuote(PI)), stdout = TRUE))
    o <- o[startsWith(o, "{\"type\":\"match\"")]
    if (!length(o)) return(character())
    j <- jsonlite::stream_in(textConnection(o), verbose = FALSE, simplifyVector = TRUE)
    key(substring(j$data$path$text, nchar(PI) + 2L), j$data$line_number) }
)
pats <- list(literal_rare = list("DEFAULT_MAX_BYTES", FALSE), regex_medium = list("export (async )?function \\w+\\(", FALSE),
             common_word = list("import", FALSE), no_match = list("zzz_not_present_zzz", FALSE), ignorecase_alt = list("todo|fixme", TRUE))
res <- list(); refs <- list()
for (pn in names(pats)) refs[[pn]] <- impl$rg_system2(pats[[pn]][[1]], pats[[pn]][[2]])
for (r in seq_len(ROUNDS)) for (pn in names(pats)) for (nm in names(impl)) {
  gc(FALSE); t0 <- proc.time()[["elapsed"]]
  got <- tryCatch(impl[[nm]](pats[[pn]][[1]], pats[[pn]][[2]]), error = function(e) paste("ERR", conditionMessage(e)))
  t <- (proc.time()[["elapsed"]] - t0) * 1000
  res[[length(res) + 1L]] <- data.frame(pattern = pn, impl = nm, ms = t, same = identical(got, refs[[pn]]), n = length(got),
                                         ndiff = length(setdiff(got, refs[[pn]])) + length(setdiff(refs[[pn]], got)))
}
res <- do.call(rbind, res)
agg <- aggregate(ms ~ pattern + impl, res, median)
wide <- reshape(agg, idvar = "impl", timevar = "pattern", direction = "wide"); names(wide) <- sub("^ms\\.", "", names(wide))
wide[-1] <- lapply(wide[-1], round)
cat("\nmedian ms over", ROUNDS, "interleaved rounds (full scan, all matches):\n"); print(wide[order(wide$literal_rare), ], row.names = FALSE)
cat("\nmatching lines per pattern (ripgrep reference):", paste(sprintf("%s=%d", names(refs), lengths(refs)), collapse = ", "), "\n")
chk <- aggregate(cbind(same, ndiff) ~ impl + pattern, res, function(v) v[1]); cat("identical (file,line) vectors vs ripgrep / size of set difference:\n")
print(reshape(chk[, c("impl", "pattern", "ndiff")], idvar = "impl", timevar = "pattern", direction = "wide"), row.names = FALSE)
print(aggregate(same ~ impl, res, all), row.names = FALSE)

# early termination: first 100 matches (what the tool does by default)
cat("\nlimit = 100 (tool default), gptr_base median ms:\n")
for (pn in names(pats)) { t <- replicate(ROUNDS, { gc(FALSE); system.time(grep_files(pats[[pn]][[1]], PI, ignore_case = pats[[pn]][[2]], limit = 100))[["elapsed"]] }); cat(sprintf("  %-16s %6.0f\n", pn, median(t) * 1000)) }

# stage profile of a full scan (no match): where does the time go?
cat("\nstage profile, full scan (median of", ROUNDS, "):\n")
st <- function(expr) { e <- substitute(expr); pf <- parent.frame(); median(vapply(seq_len(ROUNDS), function(i) { gc(FALSE); system.time(eval(e, pf))[["elapsed"]] }, 0)) * 1000 }
cat(sprintf("  walk_tree (gitignore-aware)        %6.0f ms\n", st(walk_tree(PI))))
cat(sprintf("  list.files(recursive, all.files)   %6.0f ms\n", st(list.files(PI, recursive = TRUE, all.files = TRUE))))
raws <- NULL
cat(sprintf("  readBin all files                  %6.0f ms\n", st(raws <- lapply(files, function(f) readBin(f, "raw", file.size(f))))))
cat(sprintf("  binary sniff (8000 B)              %6.0f ms\n", st(bin <- vapply(raws, is_binary_raw, NA))))
cat(sprintf("  full NUL scan (any(b == 0))        %6.0f ms\n", st(vapply(raws, function(b) any(b == as.raw(0L)), NA))))
raws <- raws[!bin]
txts <- NULL
cat(sprintf("  rawToChar + validUTF8 + mark       %6.0f ms\n", st({ txts <- vapply(raws, rawToChar, ""); v <- validUTF8(txts); Encoding(txts) <- "UTF-8" })))
cat(sprintf("  whole-file grepl prefilter (perl)  %6.0f ms\n", st(grepl("(*UTF)(?m)zzz_not_present_zzz", txts, perl = TRUE))))
cat(sprintf("  whole-file grepl fixed, useBytes   %6.0f ms\n", st(grepl("zzz_not_present_zzz", txts, fixed = TRUE, useBytes = TRUE))))
cat(sprintf("  whole-file stri_detect_regex       %6.0f ms\n", st(stri_detect_regex(txts, "zzz_not_present_zzz"))))
cat(sprintf("  whole-file stri_detect_fixed       %6.0f ms\n", st(stri_detect_fixed(txts, "zzz_not_present_zzz"))))
lines <- NULL
cat(sprintf("  strsplit all into lines            %6.0f ms\n", st(lines <- unlist(strsplit(txts, "\n", fixed = TRUE, useBytes = TRUE)))))
Encoding(lines) <- "UTF-8"
cat(sprintf("  per-line grepl perl (%d lines)  %6.0f ms\n", length(lines), st(grepl("(*UTF)zzz_not_present_zzz", lines, perl = TRUE))))
cat(sprintf("  per-line grepl perl + (*UCP)       %6.0f ms\n", st(grepl("(*UTF)(*UCP)zzz_not_present_zzz", lines, perl = TRUE))))
cat(sprintf("  per-line grepl TRE (perl = FALSE)  %6.0f ms\n", st(grepl("zzz_not_present_zzz", lines))))
cat(sprintf("  per-line stri_detect_regex         %6.0f ms\n", st(stri_detect_regex(lines, "zzz_not_present_zzz"))))
cat(sprintf("  per-line grepl fixed useBytes      %6.0f ms\n", st(grepl("zzz_not_present_zzz", lines, fixed = TRUE, useBytes = TRUE))))
saveRDS(res, file.path(W, "data/bench-grep.rds"))
```

#### `bench/bench-walk.R`

```r
# Track 11: file discovery strategies. Pi monorepo + a synthetic R project with heavy ignored dirs.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)
ROUNDS <- as.integer(Sys.getenv("ROUNDS", "5"))
cat("load average:", system("uptime", intern = TRUE), "\n")

# synthetic R project: 400 source files + node_modules (24k files) + renv/library (16k files) + .git
T <- file.path(W, "data/tree")
if (!dir.exists(T)) {
  mk <- function(dir, n, ext) { dir.create(dir, recursive = TRUE, showWarnings = FALSE); for (i in seq_len(n)) writeLines("x <- 1", file.path(dir, sprintf("f%03d.%s", i, ext))) }
  for (d in 1:20) mk(file.path(T, "R", sprintf("mod%02d", d)), 20, "R")
  for (p in 1:1200) mk(file.path(T, "node_modules", sprintf("pkg%04d", p), "lib"), 20, "js")
  for (p in 1:400) mk(file.path(T, "renv/library/R-4.4/aarch64-apple-darwin20", sprintf("pkg%03d", p), "R"), 40, "rdb")
  writeLines(c("node_modules/", ".Rhistory"), file.path(T, ".gitignore"))
  system2("git", c("-C", T, "init", "-q"))
}
trees <- list(pi_monorepo = PI, synthetic_R_project = T)
ign_rx <- "(^|/)(\\.git|node_modules|\\.Rproj\\.user|__pycache__|\\.venv)(/|$)|^renv/(library|staging|sandbox)(/|$)"
impl <- list(
  walk_tree_pruned = function(root) { w <- walk_tree(root); sort(w$rel[!w$is_dir]) },
  list.files_rec_then_filter = function(root) { x <- list.files(root, recursive = TRUE, all.files = TRUE); sort(x[!grepl(ign_rx, x, perl = TRUE)]) },
  fs_dir_ls_then_filter = function(root) { x <- fs::path_rel(fs::dir_ls(root, recurse = TRUE, all = TRUE, type = c("file", "symlink")), root); x <- as.character(x); sort(x[!grepl(ign_rx, x, perl = TRUE)]) },
  git_ls_files = function(root) sort(system2("git", c("-C", shQuote(root), "ls-files", "--cached", "--others", "--exclude-standard"), stdout = TRUE)),
  rg_files = function(root) { x <- system2("rg", c("--files", "--hidden", "-g", shQuote("!.git"), shQuote(root)), stdout = TRUE); sort(substring(x, nchar(root) + 2L)) }
)
res <- list(); outs <- list()
for (r in seq_len(ROUNDS)) for (tn in names(trees)) for (nm in names(impl)) {
  gc(FALSE); t <- system.time(x <- impl[[nm]](trees[[tn]]))[["elapsed"]]
  if (r == 1) outs[[paste(tn, nm)]] <- x
  res[[length(res) + 1]] <- data.frame(tree = tn, impl = nm, ms = t * 1000)
}
agg <- aggregate(ms ~ tree + impl, do.call(rbind, res), median); agg$ms <- round(agg$ms)
agg$files <- vapply(seq_len(nrow(agg)), function(i) length(outs[[paste(agg$tree[i], agg$impl[i])]]), 0L)
agg$same_as_git <- vapply(seq_len(nrow(agg)), function(i) identical(outs[[paste(agg$tree[i], agg$impl[i])]], outs[[paste(agg$tree[i], "git_ls_files")]]), NA)
print(agg[order(agg$tree, agg$ms), ], row.names = FALSE)
cat("\nraw listing cost of everything under the synthetic tree (incl. ignored dirs):\n")
st <- function(expr) { e <- substitute(expr); pf <- parent.frame(); median(vapply(seq_len(ROUNDS), function(i) { gc(FALSE); system.time(eval(e, pf))[["elapsed"]] }, 0)) * 1000 }
cat(sprintf("  list.files(recursive=TRUE, all.files=TRUE): %d entries  %6.0f ms\n", length(list.files(T, recursive = TRUE, all.files = TRUE)), st(list.files(T, recursive = TRUE, all.files = TRUE))))
cat(sprintf("  list.dirs(recursive=TRUE):                  %d dirs     %6.0f ms\n", length(list.dirs(T)), st(list.dirs(T))))
fl <- list.files(T, recursive = TRUE, all.files = TRUE, full.names = TRUE)
cat(sprintf("  file.info(%d paths, extra_cols = FALSE)      %6.0f ms\n", length(fl), st(file.info(fl, extra_cols = FALSE))))
cat(sprintf("  file.info(%d paths, extra_cols = TRUE)       %6.0f ms\n", length(fl), st(file.info(fl))))
cat(sprintf("  file.mtime(%d paths)                         %6.0f ms\n", length(fl), st(file.mtime(fl))))
cat(sprintf("  dir.exists(%d paths)                         %6.0f ms\n", length(fl), st(dir.exists(fl))))
cat(sprintf("  Sys.readlink(%d paths)                       %6.0f ms\n", length(fl), st(Sys.readlink(fl))))
cat(sprintf("  fs::dir_info(recurse=TRUE)                  %6.0f ms\n", st(fs::dir_info(T, recurse = TRUE, all = TRUE))))
cat(sprintf("  fs::file_info(%d paths)                      %6.0f ms\n", length(fl), st(fs::file_info(fl))))
```

#### `bench/bench-misc.R`

```r
# Track 11: sorting, diff, edit, base64, write, line counting.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/11"
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
for (f in sort(list.files(file.path(W, "proto"), "\\.R$", full.names = TRUE))) source(f)
suppressPackageStartupMessages(library(data.table)); setDTthreads(2L)
ROUNDS <- as.integer(Sys.getenv("ROUNDS", "5"))
st <- function(expr) { e <- substitute(expr); pf <- parent.frame(); median(vapply(seq_len(ROUNDS), function(i) { gc(FALSE); system.time(eval(e, pf))[["elapsed"]] }, 0)) * 1000 }
cat("load average:", system("uptime", intern = TRUE), "\n")
set.seed(42)

cat("\n### sorting 100,000 paths\n")
paths <- paste0(sample(c("R", "src", "data", "Tests", "_build"), 1e5, TRUE), "/", sample(c("File", "file", "a", "Z", "b"), 1e5, TRUE), sample(1:5000, 1e5, TRUE), ".", sample(c("R", "Rmd", "csv", "qmd"), 1e5, TRUE))
mtime <- runif(1e5, 1.7e9, 1.8e9); size <- rexp(1e5) * 1e5
cat(sprintf("  sort(x) (locale collation)                    %6.1f ms\n", st(sort(paths))))
cat(sprintf("  order(x, method='radix')  (C byte order)       %6.1f ms\n", st(order(paths, method = "radix"))))
cat(sprintf("  order(tolower(x), x, method='radix')           %6.1f ms\n", st(order(tolower(paths), paths, method = "radix"))))
cat(sprintf("  stringi::stri_order(x)  (ICU collation)        %6.1f ms\n", st(stringi::stri_order(paths))))
cat(sprintf("  natural: order(natural_key(x), method='radix') %6.1f ms\n", st(order(natural_key(paths), method = "radix"))))
cat(sprintf("  natural: stri_order(numeric = TRUE)            %6.1f ms\n", st(stringi::stri_order(paths, opts_collator = stringi::stri_opts_collator(numeric = TRUE)))))
cat(sprintf("  top-100 newest: order(-mtime)[1:100]           %6.1f ms\n", st(order(-mtime, method = "radix")[1:100])))
cat(sprintf("  top-100 newest: -sort(-mtime, partial=100)     %6.1f ms\n", st(which(mtime >= -sort(-mtime, partial = 100)[100]))))
dt <- data.table(p = paths, m = mtime, s = size); df <- as.data.frame(dt)
cat(sprintf("  base order(-s, tolower(p)) 2 keys              %6.1f ms\n", st(df[order(-df$s, tolower(df$p), method = "radix"), ])))
cat(sprintf("  data.table setorder(copy(dt), -s, p)           %6.1f ms\n", st(setorder(copy(dt), -s, p))))
loc <- c("B.R", "a.R", "_c.R", "Z.R", "b10.R", "b9.R")
cat("  sort() in this locale:      ", sort(loc), "\n")
cat("  order(tolower, radix):      ", loc[order(tolower(loc), loc, method = "radix")], "\n")
cat("  natural_key radix:          ", loc[order(natural_key(loc), method = "radix")], "\n")

cat("\n### diff: pure-R (prefix/suffix trim + patience anchors + Myers) vs diffobj::ses (C Myers)\n")
src <- readLines(file.path(PI, "packages/coding-agent/src/core/tools/edit-diff.ts"))
big <- rep(src, length.out = 200000)
mut <- function(x, k) { i <- sort(sample(length(x), k)); x[i] <- paste(x[i], "// changed"); x }
cases <- list(
  "556 lines, 3 edits" = list(src, mut(src, 3)),
  "5k lines, 3 edits" = list(rep(src, 9), mut(rep(src, 9), 3)),
  "200k lines, 2 edits (edit tool on a 5MB file)" = list(big, mut(big, 2)),
  "2k lines, 30% lines changed" = list(rep(src, 4)[1:2000], mut(rep(src, 4)[1:2000], 600)),
  "2k vs 2k unrelated random lines" = list(as.character(sample(1e6, 2000)), as.character(sample(1e6, 2000))))
for (cn in names(cases)) {
  a <- cases[[cn]][[1]]; b <- cases[[cn]][[2]]
  t1 <- st(ops <- diff_ops(a, b)); n1 <- sum(ops$op != "=")
  t2 <- st(ses <- diffobj::ses(a, b)); sd <- diffobj::ses_dat(a, b); n2 <- sum(sd$op != "Match")
  cat(sprintf("  %-46s pure R %7.1f ms (%5d +/- lines) | diffobj::ses %7.1f ms (%5d +/- lines)\n", cn, t1, n1, t2, n2))
}
old <- paste0(paste(big, collapse = "\n"), "\n"); new <- paste0(paste(mut(big, 2), collapse = "\n"), "\n")
cat(sprintf("  unified_diff() on the 200k-line pair            %7.1f ms\n", st(unified_diff(old, new, "a", "b"))))
cat(sprintf("  display_diff() on the 200k-line pair            %7.1f ms\n", st(display_diff(old, new))))

cat("\n### edit end-to-end on a 5.4 MB / 200k-line file (2 edits, atomic write, diff)\n")
fe <- tempfile(fileext = ".ts"); writeBin(charToRaw(old), fe)
tgt <- big[c(1000, 150000)]; tgt <- tgt[nzchar(trimws(tgt))]
e1 <- list(oldText = paste(big[999:1001], collapse = "\n"), newText = paste(big[999:1001], collapse = "\n// x\n"))
e2 <- list(oldText = paste(big[150000:150003], collapse = "\n"), newText = "// replaced")
cat(sprintf("  file: %.1f MB\n", file.size(fe) / 1024^2))
tm_edit <- function(ed) { writeBin(charToRaw(old), fe); gc(FALSE); system.time(tryCatch(gptr_edit(fe, ed, cwd = dirname(fe), workspace = dirname(fe)), error = function(e) conditionMessage(e)))[["elapsed"]] * 1000 }
u1 <- vapply(1:ROUNDS, function(i) tm_edit(list(list(oldText = "export function generateDiffString(", newText = "export function generateDiffString2("))), 0)
cat(sprintf("  1 edit (unique needle, 29x repeated file => 29 occurrences => duplicate error path) %7.1f ms\n", median(u1)))
bigu <- big; bigu[c(1000, 150000)] <- c("UNIQUE_MARKER_ONE", "UNIQUE_MARKER_TWO"); oldu <- paste0(paste(bigu, collapse = "\n"), "\n")
tm_edit2 <- function(ed, fuzzy = TRUE) { writeBin(charToRaw(oldu), fe); gc(FALSE); system.time(gptr_edit(fe, ed, cwd = dirname(fe), workspace = dirname(fe), fuzzy = fuzzy))[["elapsed"]] * 1000 }
cat(sprintf("  2 exact edits                                   %7.1f ms\n", median(vapply(1:ROUNDS, function(i) tm_edit2(list(list(oldText = "UNIQUE_MARKER_ONE", newText = "ONE"), list(oldText = "UNIQUE_MARKER_TWO", newText = "TWO"))), 0))))
cat(sprintf("  1 edit needing the fuzzy fallback               %7.1f ms\n", median(vapply(1:ROUNDS, function(i) tm_edit2(list(list(oldText = "UNIQUE_MARKER_ONE   ", newText = "ONE"))), 0))))
Rprof(pf <- tempfile(), interval = 0.005); invisible(tm_edit2(list(list(oldText = "UNIQUE_MARKER_ONE", newText = "ONE"), list(oldText = "UNIQUE_MARKER_TWO", newText = "TWO")))); Rprof(NULL)
cat("  profile (self time, top 8):\n"); print(utils::head(summaryRprof(pf)$by.self, 8))

cat("\n### base64 of a 5 MB image payload\n")
rb <- as.raw(sample(0:255, 5 * 1024^2, TRUE))
cat(sprintf("  base64enc::base64encode      %6.1f ms\n", st(base64enc::base64encode(rb))))
cat(sprintf("  openssl::base64_encode       %6.1f ms\n", st(openssl::base64_encode(rb))))
cat(sprintf("  jsonlite::base64_enc + gsub  %6.1f ms\n", st(gsub("[\r\n]", "", jsonlite::base64_enc(rb)))))
cat("  identical outputs:", identical(base64enc::base64encode(rb), openssl::base64_encode(rb)), identical(base64enc::base64encode(rb), gsub("[\r\n]", "", jsonlite::base64_enc(rb))), "\n")
cat("  jsonlite::base64_enc contains newlines:", grepl("\n", jsonlite::base64_enc(rb[1:100])), "\n")

cat("\n### writing 50 MB of text\n")
txt <- paste(rep(src, length.out = 800000), collapse = "\n"); Encoding(txt) <- "UTF-8"
cat(sprintf("  text: %.1f MB\n", nchar(txt, "bytes") / 1024^2))
d <- tempfile(); dir.create(d); f1 <- file.path(d, "a.txt")
cat(sprintf("  writeBin(charToRaw(x), file(,'wb'))  direct  %6.1f ms\n", st({ con <- file(f1, "wb"); writeBin(charToRaw(txt), con); close(con) })))
cat(sprintf("  write_bytes_atomic (tmp + rename)            %6.1f ms\n", st(write_bytes_atomic(f1, charToRaw(txt)))))
cat(sprintf("  writeLines(x, f, useBytes = TRUE)            %6.1f ms\n", st(writeLines(txt, f1, useBytes = TRUE))))
cat(sprintf("  cat(x, file = f)                             %6.1f ms\n", st(cat(txt, file = f1))))
cat(sprintf("  writeChar(x, con, eos = NULL, useBytes=TRUE) %6.1f ms\n", st({ con <- file(f1, "wb"); writeChar(txt, con, eos = NULL, useBytes = TRUE); close(con) })))

cat("\n### counting lines of the 148 MB file\n")
b10 <- file.path(W, "data/big10.ts")
cnt_chunks <- function(f, chunk = 8L * 1024L^2) { con <- file(f, "rb"); on.exit(close(con)); n <- 0; repeat { b <- readBin(con, "raw", chunk); if (!length(b)) break; n <- n + sum(b == as.raw(10L)) }; n }
cat(sprintf("  readBin 8MB chunks + sum(b == 0x0A)   %6.0f ms  -> %d\n", st(cnt_chunks(b10)), as.integer(cnt_chunks(b10))))
cat(sprintf("  length(readLines(f))                  %6.0f ms\n", st(length(readLines(b10, warn = FALSE)))))
cat(sprintf("  vroom::vroom_lines(altrep=TRUE) length %6.0f ms\n", st(length(vroom::vroom_lines(b10, altrep = TRUE, progress = FALSE, num_threads = 2L)))))
cat(sprintf("  data.table::fread(sep='\\n') nrow      %6.0f ms\n", st(nrow(fread(b10, sep = "\n", header = FALSE, quote = "", colClasses = "character", showProgress = FALSE, nThread = 2L)))))
cat(sprintf("  system2('wc', '-l')                   %6.0f ms\n", st(system2("wc", c("-l", b10), stdout = TRUE))))
```


---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN policy

* "Packages should not write in the user's home filespace (including clipboards), nor anywhere else on the file system apart from the R session's temporary directory" (CRAN Repository Policy). gptr's `write`/`edit` write where the *user or agent directs*, which is the purpose of the function (like `writeLines()`), inside a workspace guard. **Examples, tests and vignettes must write only under `tempdir()`** (the prototype tests do: `TD <- file.path(tempdir(), "t11")`). Persistent gptr state belongs in `tools::R_user_dir("gptr", …)` (policy exception for R ≥ 4.0).
* "If running a package uses multiple threads/cores it must never use more than two simultaneously." The file tools use none (base R is single-threaded). Suggested packages must be called with `nthreads = 1`/`num_threads` limits (the prototype does this for `qs::qread`). Benchmarks with data.table/vroom set 2 threads.
* External programs: `rg` and `git` are optional oracles and accelerators. Tests that use them must `skip_on_cran()` and `skip_if(Sys.which("rg") == "")`. Never download binaries (Pi's `ensureTool()` downloads ripgrep and fd from GitHub: `utils/tools-manager.ts:349`).
* Source must be ASCII. The prototype builds every non-ASCII constant with `intToUtf8()` (`u_chr()`). **Corrected by the verifier:** the original rationale, that `"\u00e9"` literals are not reliably marked UTF-8 in a C locale, is wrong. In `Rscript --vanilla` under `LC_ALL=C`, `"caf\u00e9"` is marked `UTF-8` with `nchar` 4 and bytes `63 61 66 c3 a9` (re-run here; track 01's own verifier corrected E1/E2 the same way). Only *raw* non-ASCII bytes in source are unreliable. So both `\u` escapes (CRAN's recommended form) and `intToUtf8()` are fine. R CMD check's "found non-ASCII strings" note is avoided either way. Byte escapes like `"\xef\xbb\xbf"` are ASCII in the source and used only with `useBytes = TRUE`.
* Tests must pass in a C locale and a UTF-8 locale (CRAN machines differ). The prototype suite passes both.
* Examples should run in seconds: use tiny temp trees; never walk `~` or `getwd()` in examples.

### 6.2 Windows specifics (source-verified; runtime UNCERTAIN, no Windows machine here)

| topic | behaviour | design consequence |
|---|---|---|
| Atomic replace | `file.rename()` → `MoveFileExW(REPLACE_EXISTING \| COPY_ALLOWED \| WRITE_THROUGH)`, retried 10 × 500 ms on `ERROR_SHARING_VIOLATION`/`ERROR_ACCESS_DENIED` (R source `src/gnuwin32/extra.c`, `Rwin_wrename()`, lines 439-451 in trunk) | temp file in the same directory; expect up to 5 s stalls when a file is locked; fall back to in-place write; report "file is open in another program" clearly |
| Files open in Excel | locked for write and delete | both the rename and the fallback fail; return an error telling the user to close the file |
| Text-mode connections | `\n` → `\r\n` (writeLines docs) | only `"wb"`/`"rb"` connections in tools |
| Native encoding | UTF-8 since R 4.2.0 (UCRT; R blog 2021-12-07, 2022-11-07); CP1252 before | prefer `Depends: R (>= 4.2.0)`; `os_path()` is a no-op on Windows (R uses wide-character APIs) |
| Legacy CP1252 files | common for old R scripts on Windows | `decode_raw()` falls back to CP1252 and `edit`/`write` re-encode to it |
| CRLF | frequent in Windows repos | `write` keeps the dominant EOL; `edit` keeps every untouched byte |
| Case-insensitive NTFS | `fs_case_insensitive()` returns TRUE | workspace containment compares `tolower()`; gitignore matching folds case (git sets `core.ignorecase=true`) |
| Symlinks/junctions | `Sys.readlink()` returns `""` on Windows ("Symbolic links are a POSIX concept, not implemented on Windows", R docs); `normalizePath()` resolves symbolic links, 8.3 short names and canonical case | walker cycle guard by canonical path is on by default on Windows; write-through-link resolution silently does nothing, so rely on `normalizePath` in `path_real()` for the guard |
| `file.symlink()` in tests | needs the create-symbolic-link privilege, "not normally granted except to Administrator accounts" (R `?file.symlink`, Windows section). Whether Windows Developer Mode is enough is UNCERTAIN (not in the R docs) | skip symlink tests on Windows |
| Path forms | `C:/x`, `C:\x`, drive-relative `C:x`, UNC `\\server\share`, Git-Bash `/c/x`, WSL `/mnt/c/x` | handled lexically in `path_norm()`/`path_resolve()` (tests cover drive and UNC normalisation); `normalizePath(winslash = "/")` may return UNC paths for mapped drives, and R falls back to avoid them (docs) |
| `~` | `path.expand("~")` = R's home (usually `Documents`), not `%USERPROFILE%` | tool and R code agree; document it for users |
| MAX_PATH | 260 UCS-2 units unless long paths are enabled; R ≥ 4.3 supports long paths "where and when the system limit can be overridden", still experimental (R blog 2023-03-07) | keep temp names short (`.<name>.gptr-XXXXXXXX.tmp`); surface OS errors |
| `Sys.chmod` | only toggles read-only | mode preservation is effectively a no-op; harmless |
| vroom ALTREP | open handle blocks delete/rename until GC (vroom#280) | never use ALTREP readers in tools |
| `rg.exe` | `Sys.which("rg")` works | accelerator via `processx::run(wd = root)`, `--path-separator /` |
| Antivirus/indexers | briefly lock new files | R's rename retry loop covers it |
| Hidden files | Windows hidden attribute is independent of dot-names; `all.files = TRUE` only concerns dot-names | documented; the Windows hidden attribute is ignored |

### 6.3 Other platforms

* macOS: default APFS is case-insensitive (VERIFIED: `file.exists(toupper(tempdir()))` is TRUE), and `normalizePath()` returns canonical case (VERIFIED). The Pi fallbacks for screenshot names (U+202F, NFD, U+2019) matter here.
* Linux: case-sensitive (ext4); `fs_case_insensitive()` probes rather than assuming. In non-UTF-8 locales (rare today; CRAN still tests some), marked UTF-8 paths fail in OS calls, so use `os_path()`.
* Network and cloud-synced folders (OneDrive, Dropbox, SMB): rename can fail or be non-atomic. The fallback path handles failure; atomicity is best-effort there.

---

## 7. Risks, pitfalls, open questions

### 7.1 Risks

1. **Windows runtime is untested.** The rename/lock behaviour, junction handling, CP1252 defaults of R < 4.2, and long paths are derived from R source and docs. A Windows CI job (GitHub Actions `windows-latest`, R release and oldrel) must run the test suite with symlink tests skipped. (UNCERTAIN)
2. **Benchmarks ran on a heavily loaded machine** (load 8–70). Absolute numbers are inflated; ratios were stable across repeated runs. Re-measure on an idle machine before quoting numbers to users.
3. **Pathological inputs.** (a) Huge single-line files (minified JSON): `read` shows the first 50 KB of the line; `grep` centres a 500-character window on the match. (b) Directory trees with millions of entries: `max_entries = 500000` caps the walk, but memory for `list.files` of a single giant directory is unbounded. (c) Regexes with catastrophic backtracking: when PCRE hits its match limit, R returns **`FALSE` with only a warning** ("PCRE error 'match limit exceeded' for element 1"), so the line is silently reported as "no match". VERIFIED: `grepl("^(a+)+$", paste0(strrep("a", 30), "b"), perl = TRUE)` took 1.05 s and warned. The production grep engine must capture these warnings with `withCallingHandlers` and add a notice ("pattern too expensive on N lines; results may be incomplete"). The prototype does not do this yet. A hard timeout would need `setTimeLimit()`, which is soft (track 01 E10/E11).
4. **Encoding heuristics can be wrong.** A mostly-ASCII latin1 file with one accented character is decoded as CP1252, which is correct for Western Europe but wrong for, say, a KOI8-R file. `edit` round-trips bytes in either case, but what the model sees may be mojibake. Mitigation: a `read` notice always names the non-UTF-8 decoding used, and an explicit `encoding =` override in the R API.
5. **Fuzzy edit can change more than asked.** Touched lines are rewritten from the normalised view (curly quotes → straight, trailing whitespace dropped) *in those lines only*, which is Pi's behaviour. The result says "(matched after whitespace/quote/dash normalisation)" and the diff shows it.
6. **Hard links are broken by atomic writes** (VERIFIED). This matters for tools such as `renv` caches (which use symlinks, handled) and for some dotfile managers. Option: `atomic = FALSE` when the link count is > 1. R's `file.info()` has no link-count column (VERIFIED: its columns are `size isdir mode mtime ctime atime uid gid uname grname`); `fs::file_info()` has one, so this needs fs or a `system2("stat")` fallback: an open question.
7. **Data previews deserialize user files.** They are capped at 50 MB and require R ≥ 4.4.0, but `readRDS` of an object with custom ALTREP classes or refhooks can still load packages and run their code. Treat previews as code execution in permission mode `plan`/read-only (D-11): the safest default is to allow `.parquet/.feather/.xlsx` previews (no R code involved) and ask before `.rds/.RData/.qs`.
8. **Default prune list vs user intent.** `node_modules/` and `renv/library/` are always pruned, even when the user explicitly wants to grep inside an installed package. Mitigation: an explicit `path` *inside* a pruned directory is honoured, because the walk root itself is never excluded. Document `gitignore = FALSE` / `default_ignore = character()` in the R API.

### 7.2 Differences from track 01 (`01-pi-builtin-tools.md`) found while re-implementing

* Track 01's grep normalised lone `\r` to `\n` before matching (`normalize_to_lf_bytes`), which makes grep line numbers disagree with `read` (and with ripgrep) for files containing lone CRs. This track converts only CRLF and keeps lone CRs (split on `\n` only everywhere).
* Track 01 decodes every invalid-UTF-8 file as CP1252. This track keeps "mostly UTF-8 with stray bytes" files as UTF-8 (U+FFFD for display, byte-level edits) and falls back to CP1252 only when invalid bytes dominate.
* Track 21 (not track 01; the verifier corrected the attribution) found the pruned per-directory walk slower than `list.files(recursive)` + filter on a clean tree: 744 vs 266 ms on 10.6k files (`work/21/out05_glob.txt`). Track 01 itself specifies a pruned walker. This track confirms the ratio on a clean tree (46 vs 24 ms) but shows the **opposite by 100x** once ignored heavy directories exist (5 vs 575 ms), which is the normal case for R projects with renv. Recommendation: the pruned walk.
* Track 01's edit restores all line endings to the first-found EOL (Pi behaviour); this track preserves untouched bytes exactly.

### 7.3 Open questions for the design lead

1. **Default tool set.** Should `grep`, `find` and `ls` be active by default (track 01 recommends yes, because gptr has no bash)? This track supports that: their schemas cost about 700 characters, and each saves several `r` round-trips.
2. **Line numbers in `read`**: off (Pi, −18.6% tokens) or on (Claude Code)? The recommendation is off, with an option; make the decision per model family if evals show a difference.
3. **Diff in the edit result**: always (recommended, ≤ 4 KB), never (Pi), or a compact 3-line context only?
4. **Stale-file check**: warn, or refuse `edit`/`write` when the file changed since the last `read`? Claude Code's read-before-edit rule was relaxed in v2.1.208: exact, unambiguous matches against the current content are allowed and flagged, and older models still require the read. This needs a per-session read registry.
5. **`core.excludesFile`**: read `$XDG_CONFIG_HOME/git/ignore` / `~/.config/git/ignore` (read-only access to the home directory is allowed), or parse `git config` via `system2` when git exists?
6. **ripgrep accelerator**: opt-in only (recommended), or automatic when `rg` is on PATH and the pattern contains no PCRE-only constructs?
7. **Preview of `.rds`/`.RData` in `plan` mode**: allow or ask (§7.1 item 7)?
8. Should the `r` tool's `readLines()`/`writeLines()` in agent-written code be linted by the advisory risk classifier (D-11) for the encoding pitfalls in §2.9 (for example, suggest `useBytes = TRUE`)?

---

## 8. Sources

Local source (read first-hand; Pi commit `1b347794e2a630e4359f2584f4eea388145d0ddf`, `@earendil-works/pi-coding-agent` 0.99.1, `diff` 8.0.4). Paths are relative to `…/scratchpad/pi/packages/coding-agent/src/`:
* `core/tools/read.ts` (lines 14-18 schema, 76 description, 112-131 images, 134-181 text path and notices)
* `core/tools/truncate.ts` (11-13 constants, 47-56 line counting, 78-160 `truncateHead`, 268-276 `truncateLine`)
* `core/tools/write.ts` (34-37 operations, 52-53 description, 65-89 execute)
* `core/tools/edit.ts` (21-51 schema and guidelines, 103-134 `prepareEditArguments`, 185-210 execute)
* `core/tools/edit-diff.ts` (11-25 EOL, 34-55 fuzzy normalisation, 132-173 unchanged-line preservation, 207-251 find and count, 253-289 error texts, 300-362 apply, 365-370 unified patch, 376-499 display diff)
* `core/tools/grep.ts` (21-33 schema, 41 limit, 136, 162-166 rg args, 197-215 context blocks, 280-303 notices)
* `core/tools/find.ts` (14-24 relativize, 26-32 schema, 41, 126 SDK ignore list, 182-214 fd args)
* `core/tools/ls.ts` (11-14, 23, 100-130)
* `core/tools/path-utils.ts` (52-84), `core/tools/file-mutation-queue.ts` (32-61)
* `utils/paths.ts` (7, 68-107), `utils/mime.ts` (3-23), `utils/image-process.ts` (72-119), `utils/image-resize.ts` (116-123), `utils/image-resize-core.ts` (5-29), `utils/text.ts` (2-4), `utils/tools-manager.ts` (349)

R source and documentation:
* R-devel `src/gnuwin32/extra.c` (`Rwin_rename`/`Rwin_wrename`, lines 422-451 in trunk as of 2026-09-29; the same code is in the R-4-1 to R-4-5 branches): https://raw.githubusercontent.com/wch/r-source/trunk/src/gnuwin32/extra.c
* R-devel `src/main/platform.c` (`do_filerename`): https://raw.githubusercontent.com/wch/r-source/trunk/src/main/platform.c
* `?files` (`file.rename`, `file.copy`): https://stat.ethz.ch/R-manual/R-devel/library/base/html/files.html
* `?readLines`: https://stat.ethz.ch/R-manual/R-devel/library/base/html/readLines.html
* `?writeLines`: https://stat.ethz.ch/R-manual/R-devel/library/base/html/writeLines.html
* `?normalizePath`: https://stat.ethz.ch/R-manual/R-devel/library/base/html/normalizePath.html
* `?Sys.readlink`: https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.readlink.html
* `?list.files`: https://stat.ethz.ch/R-manual/R-devel/library/base/html/list.files.html
* R blog, UTF-8 and UCRT on Windows (R 4.2): https://developer.r-project.org/Blog/public/2021/12/07/upcoming-changes-in-r-4.2-on-windows/index.html and https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/
* R blog, path length limit on Windows: https://blog.r-project.org/2023/03/07/path-length-limit-on-windows/
* CRAN Repository Policy: https://cran.r-project.org/web/packages/policies.html

Other:
* git `gitignore` documentation (pattern format, precedence): https://git-scm.com/docs/gitignore
* ripgrep GUIDE (binary detection, BOM sniffing, automatic filtering, `--sort path`): https://raw.githubusercontent.com/BurntSushi/ripgrep/master/GUIDE.md
* Anthropic vision docs (formats, 8000 px, 2000 px for > 20 images, 10 MB / 5 MB, long-edge limits, base64 block shape): https://platform.claude.com/docs/en/build-with-claude/vision
* Claude Code tools reference (Read line numbers, Edit `replace_all`, Glob mtime sort, Grep output modes): https://code.claude.com/docs/en/tools-reference
* vroom open-handle issue (maintainer explanation): https://github.com/r-lib/vroom/issues/280 (read via `gh issue view 280 --repo r-lib/vroom --comments`), and https://github.com/r-lib/vroom/issues/177
* CVE-2024-27322 (R deserialisation, fixed in R 4.4.0): https://www.kb.cert.org/vuls/id/238194, https://www.hiddenlayer.com/research/r-bitrary-code-execution
* Related gptr research: `dev/research/01-pi-builtin-tools.md` (track 01) and track 21's scratch outputs `work/21/out05_glob.txt`, `out05b_gitignore.txt`, `out02_readlines.txt`, `out01b_grep_prod.txt` (glob/gitignore/readline/grep numbers cited for cross-checks).

Executed evidence (all under `work/11/`): `tests/test-tools.R` → `out/test-{C,UTF8,base}.txt`; `tests/probe-platform.R` → `out/probe-{C,UTF8}.txt`; `bench/bench-*.R` → `out/bench-*.txt`; ad-hoc reproductions in `tmp/`.

---

## Verification log

An adversarial verifier checked this report on 2026-09-29 (R 4.4.3, macOS arm64, load average 6–30). Scratch files are in `work/verify-11/`. The prototypes and tests were **extracted from this report's §5.5–5.7 code blocks**, not taken from `work/11/`. They are byte-identical to `work/11/` (all 16 files) and were re-run from the extracted copy.

| # | Claim | Verdict | Source / method |
|---|---|---|---|
| 1 | Prototype runs; 159 assertions pass in the C locale and in en_US.UTF-8; 144 pass with the 11 optional packages blocked | confirmed | report-extracted `tests/test-tools.R` re-run 3×. The verbose UTF-8 log equals §5.3 except one timing |
| 2 | Platform probe outputs (§2.3 W1, R1, P1, F1, S1, V1 tables) | confirmed | report-extracted `probe-platform.R` in C and UTF-8. The C log equals §5.4 apart from temp paths and whitespace |
| 3 | Pi constants 2000 lines / 51,200 bytes / 500 chars; grep 100, find 1000, ls 500; image 2000 px / 4.5 MiB base64 | confirmed | `truncate.ts:11-13`, `grep.ts:41`, `find.ts:41`, `ls.ts:23`, `image-resize-core.ts:22-28` |
| 4 | Pi read/grep/find/ls/edit behaviour, notices and schemas (§2.1, §3.2, §3.3) | confirmed | `read.ts:14-18,134-181`, `grep.ts:162-166,197-215,280-303`, `ls.ts:100-130`, `edit-diff.ts:11-55,247-251,256-347`, `edit.ts:174-210`, `mime.ts`, `path-utils.ts` |
| 5 | Pi `find` path-pattern semantics ("follow fd"; `src/*.R` anchored) | **corrected** | `find.ts:201-214`: Pi prepends `**/` to patterns containing `/`. Added to §2.1, §2.6 and §4.5 as an open deviation |
| 6 | Windows `Rwin_wrename` retry loop (10 × 500 ms, `MoveFileExW` flags) | confirmed (code); **corrected** (lines) | R trunk `extra.c` lines 439-451, not 535-546. Same code in the R-4-1 to R-4-5 branches. `platform.c` `do_filerename` calls `rename()` / `Rwin_wrename()` |
| 7 | `Sys.readlink()` returns `""` on Windows | confirmed | `platform.c` `do_readlink`: loop only `#ifdef HAVE_READLINK`; `?Sys.readlink` |
| 8 | `iconv(sub = "Unicode"/"c99")` hangs on invalid UTF-8; `sub = "byte"` and string subs return | confirmed | 8 s `alarm` watchdog, both locales (exit 142) |
| 9 | `iconv(sub = <marked U+FFFD>)` gives literal `<U+FFFD>` in C | confirmed | bytes `3c 55 2b 46 46 46 44 3e` in C; `ef bf bd` in UTF-8 |
| 10 | PCRE `\x{2019}` fails on all-ASCII input; `(*UTF)` fixes it | confirmed | `claims1.R`, both locales |
| 11 | PCRE `\p{…}` also fails on ASCII input (P5, §2.5) | **corrected** | `grepl("\\p{L}", "abc", perl = TRUE)` is TRUE |
| 12 | `grepl(fixed = TRUE, ignore.case = TRUE)` "silently" ignores `ignore.case` | **corrected** | it warns "argument 'ignore.case = TRUE' will be ignored" (also the track 01 verifier's E15 correction) |
| 13 | TRE does not short-circuit `^` anchors | confirmed | 286 vs 26 ms on 29 MB (`claims1.R`); per-line 587 vs 108 ms (bench-grep re-run) |
| 14 | PCRE match-limit returns FALSE with only a warning | confirmed | warning "match limit exceeded"; 0.25 s |
| 15 | `jsonlite::base64_enc` inserts `\n` every 76 characters and is 10x slower | **corrected** | the wrap is at 72 characters. jsonlite alone runs at 32 vs 28 ms for base64enc; the slowdown (2–16x across runs) comes from the newline-removal `gsub` |
| 16 | `glob2rx()` outputs for 5 globs and their failures | confirmed | `claims1.R`, exact strings |
| 17 | `file.info()` has no link-count column; `fs::file_info()` has one | confirmed | columns `size isdir mode mtime ctime atime uid gid uname grname`; fs has `hard_links` |
| 18 | `path.expand("~user/x")` is left unchanged | **corrected** | `~root/x` becomes `/var/root/x`; only unknown users are left unchanged. The prototype guard (`01-paths.R:49`) still matches Pi |
| 19 | `\u`-escape literals (e.g. `"caf\u00e9"` in R source) are not reliably UTF-8-marked in a C locale (§6.1) | **corrected** | marked `UTF-8`, `nchar` 4 under `LC_ALL=C`. Track 01's verifier made the same correction |
| 20 | `fread(sep = "\n")` fails on a plain text file; grep engine "22 lines missing" | **corrected** (artifact) | `fr2.R`–`fr4.R`: aborting fread via `tryCatch(warning=)` poisons the next call. With warnings muffled, fread gives 10,061/10,061 `import` lines |
| 21 | `list.files(recursive = TRUE)` follows symlinked dirs; 66 entries; loop output "stops at the OS path limit" | confirmed (66; 6,763 vs 6,764); **corrected** (stop reason) | the loop stops at 32 path components and 160 characters. The ELOOP symlink limit is LIKELY, not PATH_MAX |
| 22 | Anthropic image limits: 8000 px; 2000 px for > 20 images; 10 MB direct / 5 MB Bedrock and Google Cloud; 1568 / 2576 px (Claude 4.7+) | confirmed | platform.claude.com vision docs, fetched 2026-09-29 |
| 23 | CRAN policy quotes (home filespace, ≤ 2 threads, `R_user_dir` for R ≥ 4.0, no binary downloads) | confirmed | cran.r-project.org/web/packages/policies.html |
| 24 | CVE-2024-27322: R 1.4.0–4.3.x, fixed in 4.4.0 | confirmed | CERT VU#238194; NVD/vendor summaries |
| 25 | vroom#280 maintainer quote | confirmed | `gh issue view 280 --repo r-lib/vroom --comments` (jimhester, Windows 10) |
| 26 | ripgrep GUIDE quotes (NUL rule, UTF-16 BOM transcoding); `-g` overrides ignore logic; `--max-count` is per file | confirmed | GUIDE.md (master); `rg --help` 15.2.0 |
| 27 | R doc quotes (readLines EOL, list.files symlinks, writeLines useBytes, normalizePath, Sys.readlink, file.rename "often fail") | confirmed | `tools::Rd2txt` of R 4.4.3 base help |
| 28 | Claude Code: Read returns line numbers; Glob sorts by mtime; Grep has 3 output modes | confirmed | code.claude.com/docs/en/tools-reference |
| 29 | Claude Code Edit "returns a snippet"; stale-file behaviour "as Claude Code does" | **downgraded / updated** | the page does not describe the Edit result, so this is now UNCERTAIN. The read-before-edit rule was relaxed in v2.1.208 |
| 30 | Package versions and API signatures (`qs::qread(nthreads)`, `arrow` readers, `utf8_normalize(map_compat)`, `processx::run(wd)`, `filelock::lock`, `Sys.chmod(use_umask)`, `diffobj::ses_dat` `id.b` NA on Match, `max.diffs` 50,000) | confirmed | `formals()` and `packageVersion()` in R 4.4.3 |
| 31 | Track 21 numbers (endsWith 2 vs 45 ms; 1–4 MiB chunks 534 ms, 16 MiB ~20% slower; 744 vs 266 ms walk) | confirmed; **corrected** attribution | `work/21/out05_glob.txt`, `out02_readlines.txt`. The walk result is track 21's, not track 01's |
| 32 | Diff engine: 7 `git apply` cases; 150 property tests, 0 invalid, 6 non-minimal | confirmed | `tmp/t-diff.R`, `tmp/t-diff2.R` re-run |
| 33 | Benchmark orderings (grep engines, readChar fastest, pruned walk 100x faster on the R-project tree, radix sort, natural sort, diff, line counting) | confirmed (orderings); absolute ms not reproducible | re-run at load 16–30 (`out/bench-*.txt`, `ROUNDS=3`, `stri_read_lines` engine skipped). Absolute times were 2–4x the report's. gptr with `limit = 100` still beat full-scan rg on `import` (263 vs 359 ms) |
| 34 | `cat -n` line numbers cost +18.6% | approximately confirmed | re-count gives +18.3% (500,188 lines over the same 1,998 files) |
| 35 | Corpus: 2,125 files, 25.9 MB, 422,936 TS lines, `package-lock.json` 186,185 B / 5,935 lines, `big.ts`/`big10.ts` sizes | confirmed | `git ls-files`, `wc`, `stat` |
| 36 | `Depends: R (>= 4.1.0)` works | **downgraded** to LIKELY / UNCERTAIN | tested only on R 4.4.3 |
| 37 | `file.symlink` on Windows "needs developer mode or admin" | **downgraded** | R docs mention only the Administrator privilege; Developer Mode is UNCERTAIN |

Benchmark reproduction caveat (verifier): the first call of a sourced (not installed) prototype function includes R's JIT byte-compilation, which was about 0.35–0.6 s for `walk_tree()` on the first call and 71–106 ms warm (`Rprof` shows `cmpfun`). Installed packages are byte-compiled at install time, so this cost does not apply to gptr. Benchmarks with few rounds can still pick it up.

